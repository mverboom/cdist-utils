# NAME

eq - query cdist explorer output

# SYNOPSIS

`eq [OPTION]... [<expressions>...]`

# DESCRIPTION

`eq` reads the explorer output that cdist stores under `$CDIST_EXPLORE` and
selects the hosts that match an expression. For every match the requested
fields are reported. It is meant to answer questions like "which systems run
debian with fewer than two cores" or "which systems have bluez installed"
without opening explorer files by hand.

The explorer output for a host lives in `$CDIST_EXPLORE/<fqdn>/<explorer>`.
A missing explorer file is normal in a mixed fleet: it never makes a positive
comparison succeed, it just means the field has no data for that host.

Running `eq` without any arguments prints the usage.

# OPTIONS

`-r, --report <fields>`
Comma separated list of fields to report for each match. Each field is an
explorer name with optional modifiers (see FIELD SPECIFIERS). May be repeated.
When omitted, `eq` prints the matching hostnames only.

`-H, --hosts <hosts>`
Comma separated list of hostnames to run the query against. May be repeated.
Hosts without explorer output are reported on stderr and skipped.

`-t, --tags <tags>`
Comma separated list of cdist inventory tags. Hosts carrying any of the tags
are queried. May be repeated.

`-T, --all-tags <tags>`
Like `-t`, but hosts must carry all of the listed tags. `-t` and `-T` cannot
be combined.

`-q, --query <string>`
Pass the whole query as one string. Quoting is honoured and parentheses are
split, so no shell escaping of brackets is needed.

`-j, --json`
Output a JSON array of objects. Values are escaped properly, including
embedded newlines.

`-w, --html`
Output an HTML table with escaped values.

`--tsv`
Output tab separated values.

`--csv`
Output CSV. Fields containing commas or newlines are quoted.

`--header`
Print a header row for the flat output formats.

`--sort <field>`
Sort matches by `host` (the default) or by one of the reported fields.

`--count`
Print only the number of matching hosts.

`--limit <n>`
Print at most `n` rows after sorting.

`--values <field>`
Print the sorted distinct values of a field across the matching hosts. Use
this to discover what values a field can take.

`--list-explorers`
Print the explorer names that exist for the selected hosts.

`--list-tags`
Print all tags known to the cdist inventory.

`--build`
Interactively build the query and run it. Uses fzf for the choices when it is
installed, otherwise a numbered prompt on stdin. Set `EQ_PLAIN=1` to force the
prompt even when fzf is available.

`--operators`
Print the operator reference with a description for each operator.

`--modifiers`
Print the field modifier reference with a description for each modifier.

`--complete <context>`
Print completion candidates as `value<TAB>description` for the given context
(`operators`, `logical`, `modifiers`, `fields`, `values`, `hosts` or `tags`).
This is what the shell completion calls; it is also handy for scripts.

`-x, --debug`
Print the number of candidate hosts to stderr.

`-h, --help`
Show help.

`-V, --version`
Show the version.

# EXPRESSIONS

A comparison looks like:

`<field> <operator> <operand>`

Comparisons are combined with `and`, `or` and `not`. The usual precedence
applies: `not` binds tightest, then `and`, then `or`. Grouping with `[ ]` or
`( )` is available when the default precedence is not what you want.

The old bracket-everything style is still valid, so queries written for the
previous implementation keep working:

`[ distr == debian ] and [ cpu_cores gt 1 ]`

The same query without brackets is shorter and reads the same way:

`distr == debian and cpu_cores gt 1`

Comparisons against multi-line explorers (for example `packages`) are true
when any record matches. Missing explorer data is only true for `exists` and
`empty`.

The following operators are available:

`=`, `==`
Exact string match against any record.

`ne`
Not equal. The field must exist, so hosts missing the explorer do not match.

`contains`
Substring match against any record.

`icontains`
Case insensitive substring match.

`matches`
Regular expression match against any record.

`startswith`, `endswith`
Record starts or ends with the operand.

`in`
Record equals one of a comma separated list, for example `distr in debian,ubuntu`.

`eq`, `gt`, `ge`, `lt`, `le`
Numeric comparison. Records that are not numbers are ignored; if no record is
numeric the comparison is false. Operands accept SI suffixes: `1K` is 1000,
`1Ki` and `1MiB` use 1024 as the base.

`exists`
The explorer file exists for the host.

`empty`
The explorer is missing, or has no non-empty records.

`nonempty`
The explorer has at least one non-empty record.

# FIELD SPECIFIERS

An explorer name can be followed by `:` separated modifiers that transform
the file before it is compared or reported:

`<explorer>[:<modifier>...]`

`f<n>`
Keep the n-th whitespace separated field of every line. Unlike the old
implementation this collapses runs of whitespace and ignores lines with too
few fields.

`l<n>`
Keep only line number `n`.

`~<regex>`
Keep only the lines matching the regular expression.

`trim`, `lower`, `upper`
Strip surrounding whitespace, or change case.

`sort`, `unique`
Sort the records, or remove duplicates.

Modifiers are applied left to right, for example
`packages:~^nginx:f2` keeps the nginx lines and reports the second field
(the version).

# SELECTING HOSTS

Without `-H`, `-t` or `-T`, `eq` queries every host directory under
`$CDIST_EXPLORE`. This does not need the `cdist` binary. The `cdist` binary is
only used when `-t`, `-T` or `--list-tags` is given.

# OUTPUT

The flat formats (`basic`, `--tsv`, `--csv`) print the reported fields in the
order given to `-r`, one host per line. Embedded newlines are collapsed to a
space for `basic` and `--tsv`, and quoted by `--csv`.

`--json` and `--html` always include the hostname in addition to the reported
fields.

# EXIT STATUS

`0`
The query ran. Note that finding no matches is still a successful run.

`1`
A data or environment problem, for example `CDIST_EXPLORE` is not set or
`cdist` is not available.

`2`
A problem with the query or options, for example an unknown operator.

# ENVIRONMENT

`CDIST_EXPLORE`
Directory holding the per-host explorer output. Required.

# EXAMPLES

Report fqdn and os version for all debian systems older than 12:

`eq -r fqdn,os_version 'distr == debian and os_version lt 12'`

Report fqdn for all systems where the package list contains nginx:

`eq -r fqdn packages contains nginx`

Report fqdn and the nginx version for all systems that have nginx installed:

`eq -r fqdn,'packages:~^nginx:f2' packages contains nginx`

List the hostnames that are not debian or ubuntu:

`eq 'not distr in debian,ubuntu'`

Show which distributions exist in the fleet:

`eq --values distr`

Count the systems with at least eight cores:

`eq --count 'cpu_cores ge 8'`

Export everything as JSON for further processing:

`eq -j -r fqdn,distr,cpu_cores`

# DIFFERENCES FROM THE OLD IMPLEMENTATION

* Missing or non-numeric explorer data no longer makes numeric comparisons
  succeed. This was the main source of silently wrong answers.
* The documented `eq` operator now exists.
* Report columns keep the order given to `-r` instead of associative array
  order.
* JSON output is valid JSON and HTML output is escaped.
* Expressions have real precedence; brackets are optional. `not` was added.
* `-r` is optional, and the tool works without `cdist` when no tags are used.
* `!=` is deliberately not used; the operator is spelled `ne` so it can never
  be mangled by shell history expansion.

# SHELL COMPLETION

Source `eq-completion` (or install it in your bash completion directory) to
get context aware completion for queries:

* Explorer field names at the start of an expression, after `[`, `(`, `and`,
  `or` and `not`, and for `-r`.
* Operators after a field, with their descriptions.
* `:` modifiers after a field, for example `packages:~<TAB>`.
* The real distinct values of a field at the operand position, so
  `distr == <TAB>` offers `debian`, `alpine`, and so on.
* `and`/`or`/`not` and closing brackets after a complete comparison.

Pressing Tab twice prints a description legend for the current candidates, for
example the meaning of every modifier or operator. There are no dependencies
for this; bash exposes the second Tab through `COMP_TYPE`.

Setting `EQ_FZF=1` turns the completion into a described fuzzy menu when fzf
is installed: candidates are shown as `value  description` and fuzzy search
picks one. Without fzf it silently falls back to the normal behaviour.

```
export EQ_FZF=1   # described fuzzy menu in completion (needs fzf)
```

# BUILDING QUERIES INTERACTIVELY

`eq --build` walks through field, operator, value and `and`/`or` and then runs
the assembled query. With fzf installed each step is a fuzzy menu; otherwise a
numbered prompt is used. The assembled query is printed to stderr so it can be
copied or refined:

```
eq --build -r fqdn
# eq: query: '[' distr == debian ']' and '[' cpu_cores gt 1 ']'
```

The help text for the operators and modifiers comes from the same tables as
`eq --operators` and `eq --modifiers`, so there is a single source of truth.

# AUTHOR

Written by Mark Verboom

# REPORTING BUGS

Preferably by opening an issue on the github page.

# COPYRIGHT

Copyright © 2014 Free Software Foundation, Inc. License GPLv3+: GNU
GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.
