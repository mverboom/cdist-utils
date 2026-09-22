# NAME

cdist-render

# SYNOPSIS

`cdist-render render [OPTION]... <host>...`

`cdist-render render --all [OPTION]...`

`cdist-render diff [OPTION]... <BASELINE> [CURRENT]`

# DESCRIPTION

Renders the cdist object tree of a host **offline** and keeps it as a json
snapshot. No host is contacted and no type code is executed, so it is safe to
run against every host as often as you like.

The tree is what cdist would build for that host: every object with its type,
object id, parameters, its `require`/`autorequire` edges and the order in which
the types would run. Diffing two snapshots answers the question "what does this
change touch", host by host, before anything is deployed.

How a host is rendered without touching it:

* the recorded explorer output is replayed through an extra conf directory
  whose explorer scripts cat `$CDIST_EXPLORE/<host>/<explorer>`, so every host
  is rendered with **its own** explorer data;
* `--remote-exec` and `--remote-copy` point at small stubs that run locally, so
  nothing leaves the machine;
* cdist runs with `-n`: manifests, type manifests and both gencode scripts run,
  but the generated code is never executed;
* the run is sandboxed: `HOME` points into the work directory (cdist caches
  there) and `CDIST_EXPLORE` points at a scratch directory, so neither the real
  cache nor the recorded explorer data is touched.

# OPTIONS

`-c`, `--config-dir DIR`
Configuration directory, repeatable and layered like cdist itself (later wins).
An overlay directory with a modified copy of `manifest/` is an easy way to
render a hypothetical change - see the example below.

`-u`, `--upstream-conf DIR`
The `conf` directory of the cdist installation.

`-e`, `--explore DIR`
Recorded explorer output, one directory per host (defaults to
`$CDIST_EXPLORE`). A host without explorer data cannot be rendered.

`-w`, `--work-dir DIR`
Scratch space (default `/tmp/cdist-render`): the fake remote, the explorer
overlay, the sandboxed home and the per host output. The directory of a host
that rendered successfully is removed afterwards.

`-s`, `--snapshot-dir DIR`
Where the snapshots are written (default `./rendered`), one
`<host>.json` per host plus an `index.json` that records when and from which
configuration revision they were rendered.

`-S`, `--stubs DIR`
Type explorer stubs (default: `cdist-render-stubs/` next to this script).

`-j`, `--jobs N`
Render up to N hosts in parallel.

`--keep-work`
Keep the per host work directory of a successful render, for debugging
(contains the full cache tree, the rendered gencode output and the log).

`--json`, `-q`
For `diff`: json output, or only the per host summary.

# TYPE EXPLORERS AND STUBS

Type explorers report **target state**: the content and ownership of a file,
whether a package is installed, the home directory of a user. That state is not
recorded anywhere, so the render cannot know it. Two rules apply:

1. If `cdist-render-stubs/<type>/<explorer>` exists, it is executed instead and
   its output is used. The stub gets `__object` and `__object_id` in its
   environment, so it can look at the object's parameters. The bundled stubs
   are:
   * `__ssh_dot_ssh/passwd`, `__ssh_dot_ssh/group` - a synthetic passwd/group
     entry for the object's owner;
   * `__ssh_authorized_keys/file`, `__ssh_authorized_keys/group` - where the
     authorized_keys file of the owner lives;
   * `__file/type`, `__directory/type` - "nothing exists yet", or "it exists"
     for `--state pre-exists`;
   * `__link/type` - "nothing exists yet".
2. Without a stub, an explorer named `state` reports the state that the object
   asks for (`--state present` -> `present`). The type then generates no code
   and needs no target state. This is also the right semantics for a render:
   the tree shows what the configuration would converge to.

An explorer with neither a stub nor a `state` name returns nothing. A type that
cannot cope with that fails, and the render reports it as a failure with the
tree it had built so far - which is itself worth knowing.

# EXAMPLES

Render the whole fleet into a baseline:

```
cdist-render render --all -j 5 -s ~/render/2026-09-22 -e "$CDIST_EXPLORE"
```

Render a hypothetical change and see what it would touch:

```
cp -a ~/config/manifest /tmp/overlay/manifest
$EDITOR /tmp/overlay/manifest/autorun/apt
cdist-render render -c ~/config -c /tmp/overlay -j 5 -s /tmp/after \
   $(cd /home/cdist/.cdist/inventory && ls)
cdist-render diff ~/render/2026-09-22 /tmp/after
```

Which hosts would gain or lose an object after a change:

```
cdist-render diff baseline after --json \
   | jq -r '.hosts | to_entries[] | select((.value.added // [])|length>0)
            | .key'
```

# OUTPUT

`render` prints one line per host (`ok`/`FAILED`, object count, seconds and the
first error) and exits non-zero when a host failed.

`diff` prints, per changed host, the objects added and removed, parameter
changes, requirement changes and execution order changes, and exits non-zero
when anything differs - so it can gate a deployment.

A snapshot looks like:

```
{
 "host": "shell.lnw.verboom.net",
 "ok": true,
 "error": "",
 "seconds": 34.62,
 "order": ["__file/etc/apt/apt.conf", "__line/aptdirect-repolnw", ...],
 "objects": [
  {"name": "__file/etc/apt/apt.conf",
   "parameters": {"mode": "644", "state": "exists"},
   "require": ["__package/apt"],
   "autorequire": [],
   "source": "/home/cdist/config/manifest/autorun/apt",
   "state": "done"}
 ]
}
```

Parameter values that point inside the run's object directory (cdist sets
`--source` like that) are rendered as `<object>/<path>` so that they do not
show up as a difference on every render.

# LIMITS

* Type explorer state is approximated (see above); gencode therefore takes the
  "nothing configured yet" path.
* A host run stops at the first error, so a tree is only complete when the
  render reports `ok`.
* Whether the rendered code *works* on the target is not decided here - that
  needs a real host.

# SEE ALSO

`cdist-audit` (static checks), `runcdist`, `cdist`
