# NAME

cdist-audit

# SYNOPSIS

`cdist-audit [OPTION]...`

# DESCRIPTION

Static audit of a cdist configuration directory. No host is contacted and no
code is executed: the findings are derived from the configuration itself, the
inventory and, optionally, the recorded explorer output.

This is the first layer of cdist verification: it catches the mistakes that are
otherwise only found when the branch in question happens to run on some host -
a typo in a type name, a missing source file, a variable that no explorer
provides, a parameter that does not exist, a manifest that is never included.

Locations are taken from the environment when not given on the command line:

* configuration directory: `CDIST_CONFIG_DIR`, else `~/config`
* cdist installation: `CDIST_INSTALL`, else the `cdist` binary on `PATH`
* inventory: `CDIST_INVENTORY`, else `~/.cdist/inventory`
* explorer output: `CDIST_EXPLORE`

# OPTIONS

`-c`, `--config-dir DIR`
Configuration directory. Can be repeated; later directories win, exactly like
cdist's own conf dir layering. Defaults to `CDIST_CONFIG_DIR` or `~/config`.

`-u`, `--upstream-conf DIR`
The `conf` directory of the cdist installation. Defaults to
`CDIST_INSTALL/cdist/conf` or the `conf` directory next to the `cdist` binary.

`-i`, `--inventory DIR`
Inventory directory used for the tag checks.

`-e`, `--explore DIR`
Directory with recorded explorer output, one subdirectory per host. Enables the
host-stale and explore-missing checks.

`--stale-days N`
Age in days after which explorer output is considered stale (default 30).

`--shellcheck`
Also run shellcheck over every shell file and report its error severity
findings. Off by default: 74 of them are deliberate `${e_packages[@]}` style
unquoted array expansions in the current configuration, which drown out the
real findings.

`--only CHECK`
Only run checks whose name starts with `CHECK`. Can be repeated.

`--json`
Write the findings as json (for machine consumption).

`-q`, `--quiet`
Only print the summary line.

`--strict`
Let warnings fail the run as well.

# CHECKS

Severity `error` fails the run (exit status 1), `warning` and `info` do not.

## error

`type-missing`
A type is invoked that does not exist in the effective type set (upstream
`conf/type` plus every `-c` directory).

`require-missing`
A `require=`/`autorequire=` target uses a type that does not exist.

`explorer-undefined`
`$e_...` is used but no explorer provides that value. The check accounts for
variables assigned locally in the same file.

`source-missing`
A literal `$files/...` reference points to a file that does not exist. Paths
built at runtime (`$files/x/$e_network/...`) are skipped; only a real run can
resolve those.

`include-missing`
`include`/`include_once` names a manifest that is neither in `manifest/` nor in
one of its subdirectories.

`include-cfg-repo-missing`
The repository directory passed to `include_cfg` does not exist.

`param-unknown`
A `--parameter` is passed that the type does not declare. Quoted values and
command substitutions are parsed properly, so flags inside a string do not
count.

`syntax`
`bash -n` rejects the file.

`shellcheck`
shellcheck reports an error severity finding (only with `--shellcheck`).

`symlink-broken`
A symlink in type, manifest, explorer or the configuration root points nowhere.

## warning

`tag-undefined`
`$t_...` is used but the tag is not present in the inventory.

`param-required-missing`
A required parameter of a type is never passed literally at any call site of
that type. Call sites that pass parameters through an array or variable are not
seen, hence a warning and not an error.

`path-conflict`
The same path is managed literally from more than one manifest (for example
`__file /etc/example` in two files). Only literal object ids are compared.

`leftover-file`
An editor, vcs or packaging leftover lives inside the configuration (for
example `manifest/autorun/.foo.swp`, which the autorun loop would source, or
`manifest/jitsi.old`). Leftovers are never parsed, only reported.

`host-stale`
The newest explorer output of a host is older than `--stale-days`, which means
the last run for that host fails or does not happen at all. Hosts like this are
still selected by tag based runs.

`explore-missing`
A host is in the inventory but has no explorer data.

## info

`type-unused`
A type from the configuration (not from the cdist installation) is not
referenced anywhere - dead code, or it is only invoked from a place this tool
does not scan.

`explorer-unused`
An explorer from the configuration is not used by any manifest or type.

`manifest-unreferenced`
A manifest in a subdirectory of `manifest/` (other than `autorun/`) that nothing
includes. It can still be used explicitly with `runcdist -o`.

`tag-unused`
Tags that exist in the inventory but are used by no manifest.

`manifest-disabled`
A manifest whose first statement is `return 0` or `exit 0`: it is included and
executed, but does nothing.

# EXAMPLES

Audit the default configuration:

```
cdist-audit -e "$CDIST_EXPLORE"
```

Only look for mistakes, no style:

```
cdist-audit --only type-missing --only explorer-undefined \
   --only source-missing --only param-
```

Machine readable, for a digest or a database:

```
cdist-audit --json --no-shellcheck | jq -r '.[] | "\(.severity): \(.check): \(.message)"'
```

# EXIT STATUS

`0` when no errors were found (and no warnings with `--strict`), `1` otherwise.

# SEE ALSO

`runcdist`, `cdist-inventory`, `cdist`
