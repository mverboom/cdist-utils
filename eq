#!/usr/bin/env python3
"""ExplorerQuery - query cdist explorer output.

Reads the per-host explorer files under $CDIST_EXPLORE, selects the hosts that
match an expression, and reports the requested fields for each match.

The expression language supports ``and``, ``or`` and ``not`` with the usual
precedence (``not`` > ``and`` > ``or``). Square brackets may still be used for
grouping, so queries written for the old bash implementation keep working.
"""

from __future__ import annotations

import argparse
import csv
import html
import io
import json
import math
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
from pathlib import Path

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_USAGE = 2

# Operator help doubles as the source of truth for the operator sets and for
# completion/reference output.
OPERATOR_HELP = {
    "=": "exact string match against any record",
    "==": "exact string match against any record",
    "ne": "not equal (the field must exist)",
    "eq": "numeric equal",
    "gt": "numeric greater than",
    "ge": "numeric greater than or equal",
    "lt": "numeric less than",
    "le": "numeric less than or equal",
    "contains": "substring match against any record",
    "icontains": "case insensitive substring match",
    "matches": "regular expression match",
    "startswith": "record starts with the operand",
    "endswith": "record ends with the operand",
    "in": "record equals one of a comma separated list",
    "exists": "the explorer file exists for the host",
    "empty": "missing, or has no non-empty records",
    "nonempty": "has at least one non-empty record",
}
# Operators that only look at the field itself.
UNARY_OPERATORS = {"exists", "empty", "nonempty"}
# Operators that compare a field against an operand.
BINARY_OPERATORS = set(OPERATOR_HELP) - UNARY_OPERATORS

LOGICAL_HELP = {
    "and": "both expressions are true",
    "or": "either expression is true",
    "not": "negate the next expression",
}


def _ordinal(number: int) -> str:
    """Return the English ordinal word for a small number."""
    words = {1: "first", 2: "second", 3: "third", 4: "fourth", 5: "fifth"}
    return words.get(number, f"{number}th")


def _hosts_label(count: int) -> str:
    """Return '1 host' or 'N hosts'."""
    return f"{count} host" if count == 1 else f"{count} hosts"


MODIFIER_HELP = {
    **{f"f{i}": f"{_ordinal(i)} whitespace separated field" for i in range(1, 6)},
    **{f"l{i}": f"{_ordinal(i)} line" for i in range(1, 4)},
    "~": "keep lines matching a regular expression",
    "trim": "strip surrounding whitespace",
    "lower": "lowercase the records",
    "upper": "uppercase the records",
    "sort": "sort the records",
    "unique": "remove duplicate records",
}

# SI suffixes accepted by numeric comparisons. Binary suffixes add an "i" and
# use a base of 1024. Lowercase "m" is deliberately not accepted, matching
# numfmt, to avoid confusing milli with mega.
_SI_STEPS = "KMGTPEZY"
_NUMBER_RE = re.compile(
    r"^\s*([+-]?(?:\d+\.?\d*|\.\d+))\s*([kKMGTPEZY]?)(i?)b?\s*$"
)

_FIELD_SPEC_RE = re.compile(r"^[A-Za-z0-9._-]+$")
_MODIFIER_RE = re.compile(r"^(f|l)(\d+)$")


class QueryError(Exception):
    """Raised for problems in the query itself (bad syntax or operand)."""


class DataError(Exception):
    """Raised for problems in the explorer data or environment."""


def parse_number(text: str) -> float | None:
    """Parse a number with an optional SI suffix, returning None if invalid.

    ``1K`` is 1000, ``1Ki`` is 1024 and ``1MiB`` is 1024**2. Plain integers and
    floats are accepted as well.
    """
    match = _NUMBER_RE.match(text)
    if match is None:
        return None
    value = float(match.group(1))
    prefix = match.group(2)
    binary = match.group(3) == "i"
    if prefix:
        power = _SI_STEPS.index(prefix.upper()) + 1
        base = 1024 if binary else 1000
        value *= base**power
    return value


def split_field_spec(spec: str) -> tuple[str, list[str]]:
    """Split ``<explorer>[:<modifier>...]`` into the base name and modifiers."""
    parts = spec.split(":")
    base, modifiers = parts[0], parts[1:]
    if not _FIELD_SPEC_RE.match(base):
        raise QueryError(f"Invalid explorer name: {base!r}")
    return base, modifiers


def apply_modifiers(lines: list[str], modifiers: list[str], spec: str) -> list[str]:
    """Apply the ``:`` modifiers of an explorer spec to its lines in order."""
    result = lines
    for modifier in modifiers:
        if modifier.startswith("~"):
            pattern = modifier[1:]
            try:
                regex = re.compile(pattern)
            except re.error as exc:
                raise QueryError(f"Invalid regex in {spec!r}: {exc}") from exc
            result = [line for line in result if regex.search(line)]
            continue
        match = _MODIFIER_RE.match(modifier)
        if match:
            kind, number = match.groups()
            index = int(number)
            if index < 1:
                raise QueryError(f"Invalid index in modifier {modifier!r}")
            if kind == "l":
                result = [result[index - 1]] if len(result) >= index else []
            else:
                result = [
                    line.split()[index - 1]
                    for line in result
                    if len(line.split()) >= index
                ]
        elif modifier == "trim":
            result = [line.strip() for line in result]
        elif modifier == "lower":
            result = [line.lower() for line in result]
        elif modifier == "upper":
            result = [line.upper() for line in result]
        elif modifier == "sort":
            result = sorted(result)
        elif modifier == "unique":
            result = list(dict.fromkeys(result))
        else:
            raise QueryError(f"Unknown explorer modifier {modifier!r} in {spec!r}")
    return result


class ExplorerData:
    """Lazy reader for the explorer files of a set of hosts."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self._cache: dict[tuple[str, str], list[str] | None] = {}

    def host_dirs(self) -> list[str]:
        """Return the sorted names of all hosts that have explorer output.

        Hidden entries such as the ``.git`` directory of a versioned explore
        tree are not hosts and are ignored.
        """
        return sorted(
            entry.name
            for entry in self.root.iterdir()
            if entry.is_dir() and not entry.name.startswith(".")
        )

    def has_host(self, host: str) -> bool:
        """Return True if the host has an explorer output directory."""
        return (self.root / host).is_dir()

    def field(self, host: str, spec: str) -> list[str] | None:
        """Return the processed lines of an explorer spec for a host.

        Returns None when the explorer file does not exist for the host, which
        is normal in a mixed fleet and is treated as "no data" by the
        evaluator. An empty list means the file exists but the modifiers
        filtered everything out.
        """
        key = (host, spec)
        if key not in self._cache:
            base, modifiers = split_field_spec(spec)
            path = self.root / host / base
            if not path.is_file():
                value: list[str] | None = None
            else:
                lines = path.read_text(errors="replace").splitlines()
                value = apply_modifiers(lines, modifiers, spec)
            self._cache[key] = value
        return self._cache[key]


def evaluate_comparison(
    records: list[str] | None, operator: str, operand: str | None
) -> bool:
    """Evaluate a single field/operator/operand comparison.

    Missing data (``records is None``) never satisfies a positive comparison;
    only ``exists`` and ``empty`` can be true. This avoids the old behaviour
    where a missing file made numeric comparisons silently succeed.
    """
    if operator == "exists":
        return records is not None
    if operator == "empty":
        return records is None or not any(line.strip() for line in records)
    if operator == "nonempty":
        return records is not None and any(line.strip() for line in records)

    if records is None:
        return False
    assert operand is not None

    if operator in ("=", "=="):
        return any(line == operand for line in records)
    if operator == "ne":
        return bool(records) and all(line != operand for line in records)
    if operator == "contains":
        return any(operand in line for line in records)
    if operator == "icontains":
        needle = operand.lower()
        return any(needle in line.lower() for line in records)
    if operator == "matches":
        try:
            regex = re.compile(operand)
        except re.error as exc:
            raise QueryError(f"Invalid regex {operand!r}: {exc}") from exc
        return any(regex.search(line) for line in records)
    if operator == "startswith":
        return any(line.startswith(operand) for line in records)
    if operator == "endswith":
        return any(line.endswith(operand) for line in records)
    if operator == "in":
        wanted = [item.strip() for item in operand.split(",")]
        return any(line in wanted for line in records)

    wanted_number = parse_number(operand)
    if wanted_number is None:
        raise QueryError(f"Operator {operator!r} needs a number, got {operand!r}")
    numbers = [parse_number(line) for line in records]
    numbers = [number for number in numbers if number is not None]
    if not numbers:
        return False
    if operator == "eq":
        return any(math.isclose(number, wanted_number) for number in numbers)
    if operator == "gt":
        return any(number > wanted_number for number in numbers)
    if operator == "ge":
        return any(number >= wanted_number for number in numbers)
    if operator == "lt":
        return any(number < wanted_number for number in numbers)
    if operator == "le":
        return any(number <= wanted_number for number in numbers)
    raise QueryError(f"Unknown operator {operator!r}")


class Parser:
    """Recursive descent parser for the expression language."""

    def __init__(self, tokens: list[str]) -> None:
        self.tokens = tokens
        self.pos = 0

    def parse(self) -> tuple:
        """Parse the whole token list into an expression tree."""
        if not self.tokens:
            return ("true",)
        tree = self._parse_or()
        if self.pos != len(self.tokens):
            raise QueryError(f"Unexpected token {self.tokens[self.pos]!r}")
        return tree

    def _peek(self) -> str | None:
        return self.tokens[self.pos] if self.pos < len(self.tokens) else None

    def _next(self) -> str:
        token = self.tokens[self.pos]
        self.pos += 1
        return token

    def _parse_or(self) -> tuple:
        tree = self._parse_and()
        while self._peek() == "or":
            self._next()
            tree = ("or", tree, self._parse_and())
        return tree

    def _parse_and(self) -> tuple:
        tree = self._parse_not()
        while self._peek() == "and":
            self._next()
            tree = ("and", tree, self._parse_not())
        return tree

    def _parse_not(self) -> tuple:
        if self._peek() == "not":
            self._next()
            return ("not", self._parse_not())
        return self._parse_primary()

    def _parse_primary(self) -> tuple:
        token = self._peek()
        if token is None:
            raise QueryError("Unexpected end of expression")
        if token in ("[", "("):
            self._next()
            tree = self._parse_or()
            closing = ")" if token == "(" else "]"
            if self._peek() != closing:
                raise QueryError(f"Missing closing {closing}")
            self._next()
            return tree
        if token in ("]", ")", "and", "or"):
            raise QueryError(f"Unexpected token {token!r}")

        field = self._next()
        operator = self._peek()
        if operator is None:
            raise QueryError(f"Field {field!r} is missing an operator")
        if operator in UNARY_OPERATORS:
            self._next()
            return ("cmp", field, operator, None)
        if operator in BINARY_OPERATORS:
            self._next()
            operand = self._peek()
            if operand is None or operand in ("]", ")", "and", "or"):
                raise QueryError(f"Operator {operator!r} needs an operand")
            self._next()
            return ("cmp", field, operator, operand)
        raise QueryError(f"Unknown or misplaced operator {operator!r} after {field!r}")


def matches(tree: tuple, host: str, data: ExplorerData) -> bool:
    """Evaluate a parsed expression tree for one host."""
    kind = tree[0]
    if kind == "true":
        return True
    if kind == "and":
        return matches(tree[1], host, data) and matches(tree[2], host, data)
    if kind == "or":
        return matches(tree[1], host, data) or matches(tree[2], host, data)
    if kind == "not":
        return not matches(tree[1], host, data)
    _, spec, operator, operand = tree
    return evaluate_comparison(data.field(host, spec), operator, operand)


def run_cdist(args: list[str]) -> str:
    """Run a cdist command and return its stdout, raising DataError on failure."""
    try:
        result = subprocess.run(
            ["cdist", *args], capture_output=True, text=True, timeout=120, check=False
        )
    except FileNotFoundError as exc:
        raise DataError("cdist is not available; use -H to select hosts") from exc
    except subprocess.TimeoutExpired as exc:
        raise DataError("cdist command timed out") from exc
    if result.returncode != 0:
        message = result.stderr.strip() or "unknown error"
        raise DataError(f"cdist {' '.join(args)} failed: {message}")
    return result.stdout


def select_hosts(args: argparse.Namespace, data: ExplorerData) -> list[str]:
    """Work out which hosts the query should run against."""
    want_all = bool(args.all_tags)
    tag_values = comma_split(args.tags) + comma_split(args.all_tags)
    if args.tags and args.all_tags:
        raise DataError("Use either -t or -T, not both")

    if args.hosts:
        hosts = comma_split(args.hosts)
    elif tag_values:
        command = ["inventory", "list", "-H"]
        if want_all:
            command.append("-a")
        command.extend(["-t", *tag_values])
        hosts = run_cdist(command).split()
    else:
        return data.host_dirs()

    known = [host for host in hosts if data.has_host(host)]
    unknown = [host for host in hosts if host not in known]
    if unknown:
        print(f"eq: no explorer output for: {', '.join(unknown)}", file=sys.stderr)
    return known


def all_tags() -> list[str]:
    """Return all tags known to the cdist inventory."""
    tags: set[str] = set()
    for line in run_cdist(["inventory", "list"]).splitlines():
        parts = line.split()
        if len(parts) >= 2:
            tags.update(tag for tag in parts[1].split(",") if tag)
    return sorted(tags)


def explore_root() -> Path | None:
    """Return $CDIST_EXPLORE when it is a directory, else None."""
    explore_env = os.environ.get("CDIST_EXPLORE", "")
    root = Path(explore_env)
    if not explore_env or not root.is_dir():
        return None
    return root


def explorer_counts(data: ExplorerData, hosts: list[str]) -> dict[str, int]:
    """Count how many of the hosts have each explorer file."""
    counts: dict[str, int] = {}
    for host in hosts:
        for entry in (data.root / host).iterdir():
            if entry.is_file() and not entry.name.startswith("."):
                counts[entry.name] = counts.get(entry.name, 0) + 1
    return counts


def value_counts(data: ExplorerData, hosts: list[str], spec: str) -> dict[str, int]:
    """Count how many hosts have each distinct value of a field."""
    counts: dict[str, int] = {}
    for host in hosts:
        for record in set(data.field(host, spec) or []):
            if record.strip():
                counts[record] = counts.get(record, 0) + 1
    return counts


def completion_pairs(
    context: str, extra: list[str], data: ExplorerData | None, hosts: list[str]
) -> list[tuple[str, str]]:
    """Return (value, description) pairs for a completion context."""
    if context == "operators":
        return list(OPERATOR_HELP.items())
    if context == "logical":
        return list(LOGICAL_HELP.items())
    if context == "modifiers":
        return list(MODIFIER_HELP.items())
    if data is None:
        return []
    if context == "fields":
        return [
            (name, _hosts_label(count))
            for name, count in sorted(explorer_counts(data, hosts).items())
        ]
    if context == "values":
        field = extra[0] if extra else ""
        return [
            (value, _hosts_label(count))
            for value, count in sorted(value_counts(data, hosts, field).items())
        ]
    if context == "hosts":
        return [(host, "") for host in hosts]
    if context == "tags":
        return [(tag, "") for tag in all_tags()]
    raise QueryError(f"Unknown completion context {context!r}")


def run_complete(args: argparse.Namespace) -> int:
    """Print value<TAB>description completion candidates."""
    static = args.complete in ("operators", "logical", "modifiers")
    data = None
    hosts: list[str] = []
    if not static:
        root = explore_root()
        if root is None:
            return EXIT_OK
        data = ExplorerData(root)
        try:
            hosts = select_hosts(args, data)
        except DataError:
            hosts = data.host_dirs()
    pairs = completion_pairs(args.complete, list(args.expression), data, hosts)
    for value, description in pairs:
        print(f"{value}\t{description}" if description else value)
    return EXIT_OK


def print_reference(mapping: dict[str, str]) -> None:
    """Print an aligned name/description reference table."""
    width = max(len(name) for name in mapping) + 2
    for name, description in mapping.items():
        print(f"  {name:<{width}}{description}")


def _use_fzf() -> bool:
    """Return True when interactive choices should use fzf."""
    if os.environ.get("EQ_PLAIN"):
        return False
    return shutil.which("fzf") is not None


def _fzf_choice(
    prompt: str, pairs: list[tuple[str, str]], allow_custom: bool
) -> str | None:
    """Choose from pairs with fzf, optionally accepting typed text."""
    lines = "\n".join(
        f"{value}\t{description}" if description else value
        for value, description in pairs
    )
    command = [
        "fzf",
        "--height=40%",
        "--reverse",
        "--delimiter=\t",
        "--with-nth=1,2",
        "--nth=1",
        "--print-query",
        "--prompt",
        f"{prompt}> ",
    ]
    try:
        result = subprocess.run(
            command, input=lines, capture_output=True, text=True, check=False
        )
    except OSError:
        return _plain_choice(prompt, pairs, allow_custom)
    output = result.stdout.splitlines()
    if not output:
        return None
    query = output[0]
    if len(output) > 1 and output[1].strip():
        return output[1].split("\t")[0]
    if allow_custom and query.strip():
        return query.strip()
    return None


def _plain_choice(
    prompt: str, pairs: list[tuple[str, str]], allow_custom: bool
) -> str | None:
    """Choose from pairs with a numbered prompt, optionally accepting text.

    A literal value always wins, so a numeric operand such as ``1`` is not
    mistaken for a menu index. Numbers only select an entry for prompts that
    do not allow custom input (fields and operators).
    """
    for index, (value, description) in enumerate(pairs, 1):
        suffix = f"  - {description}" if description else ""
        print(f"  {index:>3}) {value}{suffix}", file=sys.stderr)
    try:
        answer = input(f"{prompt}> ").strip()
    except EOFError:
        return None
    if not answer:
        return None
    if any(value == answer for value, _ in pairs):
        return answer
    if not allow_custom and answer.isdigit():
        index = int(answer)
        if 1 <= index <= len(pairs):
            return pairs[index - 1][0]
    return answer if allow_custom else None


def _choose(
    prompt: str, pairs: list[tuple[str, str]], allow_custom: bool = False
) -> str | None:
    """Prompt for a choice, using fzf when available."""
    if _use_fzf():
        return _fzf_choice(prompt, pairs, allow_custom)
    return _plain_choice(prompt, pairs, allow_custom)


def _confirm(prompt: str) -> bool:
    """Ask a yes/no question."""
    try:
        answer = input(f"{prompt} [y/N] ").strip().lower()
    except EOFError:
        return False
    return answer in ("y", "yes")


def build_query(data: ExplorerData, hosts: list[str]) -> list[str]:
    """Interactively assemble a query and return it as tokens."""
    fields = [
        (name, _hosts_label(count))
        for name, count in sorted(explorer_counts(data, hosts).items())
    ]
    operators = list(OPERATOR_HELP.items())
    connectors = [("and", LOGICAL_HELP["and"]), ("or", LOGICAL_HELP["or"])]
    tokens: list[str] = []
    while True:
        field = _choose("field", fields)
        if field is None:
            raise KeyboardInterrupt
        operator = _choose("operator", operators)
        if operator is None:
            raise KeyboardInterrupt
        clause = [field, operator]
        if operator not in UNARY_OPERATORS:
            operand = _choose(
                "value",
                [
                    (value, _hosts_label(count))
                    for value, count in sorted(
                        value_counts(data, hosts, field).items()
                    )
                ],
                allow_custom=True,
            )
            if operand is None:
                raise KeyboardInterrupt
            clause.append(operand)
        tokens.extend(["[", *clause, "]"])
        if not _confirm("add another condition?"):
            break
        connector = _choose("combine with", connectors)
        if connector is None:
            break
        tokens.append(connector)
    return tokens


def format_query(tokens: list[str]) -> str:
    """Format query tokens the way they can be passed to -q."""
    return " ".join(shlex.quote(token) for token in tokens)


def flatten(value: str) -> str:
    """Collapse newlines so a value stays on one line in flat output."""
    return " ".join(value.splitlines()) if "\n" in value else value


def render_basic(rows: list[list[str]], header: list[str], show_header: bool) -> str:
    """Render space separated rows, one host per line."""
    out = [" ".join(header)] if show_header else []
    out.extend(" ".join(flatten(cell) for cell in row) for row in rows)
    return "\n".join(out)


def render_tsv(rows: list[list[str]], header: list[str], show_header: bool) -> str:
    """Render tab separated rows, one host per line."""
    out = ["\t".join(header)] if show_header else []
    out.extend("\t".join(flatten(cell) for cell in row) for row in rows)
    return "\n".join(out)


def render_csv(rows: list[list[str]], header: list[str], show_header: bool) -> str:
    """Render CSV; the csv module quotes embedded newlines and commas."""
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    if show_header:
        writer.writerow(header)
    writer.writerows(rows)
    return buffer.getvalue().rstrip("\n")


def render_json(rows: list[list[str]], header: list[str], hostnames: list[str]) -> str:
    """Render a JSON array of host objects."""
    documents = []
    for host, row in zip(hostnames, rows):
        document = {"hostname": host}
        document.update(zip(header, row))
        documents.append(document)
    return json.dumps(documents, indent=2, ensure_ascii=False)


def render_html(rows: list[list[str]], header: list[str], hostnames: list[str]) -> str:
    """Render an escaped HTML table."""
    out = ["<table border=1>"]
    head = ["<tr>", "<th>hostname</th>"]
    head.extend(f"<th>{html.escape(name)}</th>" for name in header)
    head.append("</tr>")
    out.append("".join(head))
    for host, row in zip(hostnames, rows):
        cells = ["<tr>", f"<td>{html.escape(host)}</td>"]
        cells.extend(f"<td>{html.escape(cell)}</td>" for cell in row)
        cells.append("</tr>")
        out.append("".join(cells))
    out.append("</table>")
    return "\n".join(out)


def build_parser() -> argparse.ArgumentParser:
    """Create the command line parser."""
    parser = argparse.ArgumentParser(
        prog="eq",
        description="Query cdist explorer output.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Expressions combine comparisons with and/or/not (not > and > or).\n"
            "Group with [ ] or ( ), or pass the whole query with -q.\n\n"
            "Operators:\n"
            "  =  ==        exact string match (any record)\n"
            "  ne           not equal (field must exist)\n"
            "  contains     substring match\n"
            "  icontains    case insensitive substring match\n"
            "  matches      regular expression match\n"
            "  startswith   record starts with the operand\n"
            "  endswith     record ends with the operand\n"
            "  in           record equals one of a comma separated list\n"
            "  eq gt ge lt le   numeric compare, SI suffixes allowed (1K, 2Mi)\n"
            "  exists       explorer file exists for the host\n"
            "  empty        explorer is missing or has no non-empty records\n"
            "  nonempty     explorer has at least one non-empty record\n"
            "\n"
            "Field specifiers:\n"
            "  <explorer>[:<modifier>...]\n"
            "  f<n>      keep the n-th whitespace separated field of each line\n"
            "  l<n>      keep the n-th line\n"
            "  ~<regex>  keep lines matching the regular expression\n"
            "  trim lower upper sort unique\n"
            "\n"
            "Examples:\n"
            "  eq -r fqdn,os_version 'distr == debian and os_version lt 12'\n"
            "  eq -r fqdn packages contains nginx\n"
            "  eq -r hostname 'not distr in debian,ubuntu'\n"
            "  eq --values distr\n"
            "  eq --count 'cpu_cores ge 8'\n"
        ),
    )
    parser.add_argument(
        "-r", "--report", action="append", help="comma separated report fields"
    )
    parser.add_argument(
        "-H", "--hosts", action="append", help="comma separated hostnames"
    )
    parser.add_argument(
        "-t", "--tags", action="append", help="comma separated tags, any match"
    )
    parser.add_argument(
        "-T", "--all-tags", action="append", help="comma separated tags, all match"
    )
    parser.add_argument(
        "-q", "--query", help="query as one string (quotes honoured, ( ) split)"
    )
    parser.add_argument("-j", "--json", action="store_true", help="JSON output")
    parser.add_argument("-w", "--html", action="store_true", help="HTML output")
    parser.add_argument("--tsv", action="store_true", help="tab separated output")
    parser.add_argument("--csv", action="store_true", help="CSV output")
    parser.add_argument("--header", action="store_true", help="print a header row")
    parser.add_argument("--sort", metavar="FIELD", help="sort by host or report field")
    parser.add_argument("--count", action="store_true", help="only print match count")
    parser.add_argument("--limit", type=int, metavar="N", help="limit number of rows")
    parser.add_argument(
        "--list-explorers",
        action="store_true",
        help="list explorer names present for the matching hosts",
    )
    parser.add_argument(
        "--list-tags", action="store_true", help="list all cdist inventory tags"
    )
    parser.add_argument(
        "--values", metavar="FIELD", help="list distinct values of a field"
    )
    parser.add_argument(
        "--complete",
        metavar="CONTEXT",
        help="print completion candidates: operators, logical, modifiers, "
        "fields, values, hosts or tags",
    )
    parser.add_argument(
        "--operators", action="store_true", help="print the operator reference"
    )
    parser.add_argument(
        "--modifiers",
        action="store_true",
        help="print the field modifier reference",
    )
    parser.add_argument(
        "--build",
        action="store_true",
        help="interactively build the query (uses fzf when available)",
    )
    parser.add_argument(
        "-x", "--debug", action="store_true", help="print progress to stderr"
    )
    parser.add_argument("-V", "--version", action="version", version="eq (python) 2.0")
    parser.add_argument(
        "expression", nargs="*", help="query tokens, e.g. distr == debian"
    )
    return parser


def comma_split(values: list[str] | None) -> list[str]:
    """Flatten repeated comma separated option arguments into a list."""
    items: list[str] = []
    for value in values or []:
        items.extend(item for item in value.split(",") if item)
    return items


def tokenize_query(text: str) -> list[str]:
    """Tokenize a -q query, splitting parentheses but keeping quoted operands."""
    lexer = shlex.shlex(text, posix=True, punctuation_chars="()")
    lexer.whitespace_split = True
    try:
        return list(lexer)
    except ValueError as exc:
        raise QueryError(f"Invalid query string: {exc}") from exc


def distinct_values(data: ExplorerData, hosts: list[str], spec: str) -> list[str]:
    """Return the sorted distinct records of a field across hosts."""
    values: set[str] = set()
    for host in hosts:
        records = data.field(host, spec)
        if records:
            values.update(record for record in records if record.strip())
    return sorted(values)


def sort_hosts(
    hosts: list[str], field: str, reports: list[str], data: ExplorerData
) -> list[str]:
    """Sort hosts by hostname or by the string value of a report field."""
    if field == "host":
        return sorted(hosts)
    if field not in reports:
        raise QueryError(f"--sort field {field!r} is not in --report")
    return sorted(hosts, key=lambda host: "\n".join(data.field(host, field) or []))


def run(args: argparse.Namespace) -> int:
    """Execute a parsed command line."""
    if args.complete:
        return run_complete(args)
    if args.operators:
        print_reference(OPERATOR_HELP)
        return EXIT_OK
    if args.modifiers:
        print_reference(MODIFIER_HELP)
        return EXIT_OK

    explore_env = os.environ.get("CDIST_EXPLORE", "")
    explore_root = Path(explore_env)
    if not explore_env or not explore_root.is_dir():
        raise DataError(
            "CDIST_EXPLORE is not set or is not a directory "
            f"({explore_env or 'unset'})"
        )

    data = ExplorerData(explore_root)

    if args.list_tags:
        print("\n".join(all_tags()))
        return EXIT_OK

    hosts = select_hosts(args, data)
    if args.debug:
        print(f"eq: {len(hosts)} candidate hosts", file=sys.stderr)

    if args.build:
        tokens = build_query(data, hosts)
        print(f"eq: query: {format_query(tokens)}", file=sys.stderr)
    else:
        tokens = list(args.expression)
        if args.query:
            tokens = tokenize_query(args.query) + tokens
    tree = Parser(tokens).parse()

    selected = [host for host in hosts if matches(tree, host, data)]

    if args.list_explorers:
        names: set[str] = set()
        for host in selected:
            names.update(entry.name for entry in (explore_root / host).iterdir())
        print("\n".join(sorted(names)))
        return EXIT_OK

    if args.values:
        print("\n".join(distinct_values(data, selected, args.values)))
        return EXIT_OK

    if args.count:
        print(len(selected))
        return EXIT_OK

    if args.limit is not None and args.limit >= 0:
        selected = selected[: args.limit]

    reports = comma_split(args.report)
    if args.sort:
        selected = sort_hosts(selected, args.sort, reports, data)
    else:
        selected = sorted(selected)

    report_rows = []
    for host in selected:
        row = []
        for spec in reports:
            records = data.field(host, spec)
            row.append("\n".join(records) if records is not None else "")
        report_rows.append(row)

    if reports:
        flat_header, flat_rows = reports, report_rows
    else:
        flat_header = ["hostname"]
        flat_rows = [[host] for host in selected]

    if args.json:
        output = render_json(report_rows, reports, selected)
    elif args.html:
        output = render_html(report_rows, reports, selected)
    elif args.csv:
        output = render_csv(flat_rows, flat_header, args.header)
    elif args.tsv:
        output = render_tsv(flat_rows, flat_header, args.header)
    else:
        output = render_basic(flat_rows, flat_header, args.header)

    if output:
        print(output)
    return EXIT_OK


def main(argv: list[str] | None = None) -> int:
    """Entry point: parse arguments, run the query and render the output."""
    if argv is None:
        argv = sys.argv[1:]
    parser = build_parser()
    if not argv:
        parser.print_help(sys.stderr)
        return EXIT_USAGE
    args = parser.parse_args(argv)
    try:
        return run(args)
    except QueryError as exc:
        print(f"eq: {exc}", file=sys.stderr)
        return EXIT_USAGE
    except DataError as exc:
        print(f"eq: {exc}", file=sys.stderr)
        return EXIT_ERROR
    except BrokenPipeError:
        return EXIT_OK
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    if hasattr(signal, "SIGPIPE"):
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    sys.exit(main())
