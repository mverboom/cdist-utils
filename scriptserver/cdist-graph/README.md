# cdist dependency graph

Web UI for inspecting the object dependency graph of a cdist host, without
configuring anything.

## How it works

cdist materialises the whole object tree on disk while it runs a host and then
moves it into `~/.cdist/cache/<hash>/`. Each object directory records, among
other things:

* `require` / `autorequire` — the execution-order dependencies cdist resolves
  between objects.
* `parents` / `children` — the type-expansion tree (not shown here).

`cdist-graph` finds the **newest cached run** for the chosen host, parses those
dependencies and renders them with Graphviz. No host is contacted and no
configuration is applied, so it is safe to run at any time. Because it reads
the cache, the graph shows the state of the last actual run; a config change
made since then is not reflected until the host is run again (including a
`runcdist -d` dry run).

## Views

| View | What it shows |
|---|---|
| `tree` (default) | The run as layered levels, rendered top-to-bottom by default. By default the objects that depend on something come first and the primitives (objects that depend on nothing) last; `--order primitives` reverses that. |
| `types` | Objects collapsed to their type, with the number of objects and edges per type. Compact whole-system network. |
| `objects` | Every object as its own node, grouped in a dashed cluster per type. Detailed network. |

Arrow direction depends on the tree order: with the default `--order
dependents` an arrow points from an object to what it depends on (read it as
"needs"); with `--order primitives` it points from a dependency to the object
that requires it (execution order). In the `types` and `objects` views arrows
always point dependency → dependent. `require` edges are solid and
`autorequire` dashed (line style, not colour, so it stays readable for
colour-blind users).

### Why the tree view collapses chains

The levels are the longest-path rank over `require` **and** `autorequire`;
nodes sharing a level can run in parallel. `--order dependents` (the default)
renders those levels with the most-dependent objects first, `primitives` with
the dependency-free objects first. A faithful object-level tree is
often unusable: the `__le` type alone produces a ~200-object pass-through
require chain (cert → directory → next cert → …), so the tree would be ~200
levels of single nodes. The tree view therefore merges runs of pass-through
objects (exactly one dependency and one dependent) into one node labelled
`<n> chained: <types>`. Hovering gives the full member list. `--no-collapse`
turns this off.

`require` still drives the Graphviz ranking; `autorequire` is drawn with
`constraint=false` so its large fan-ins cannot make the layout explode.

## Runners

The **cdist dependency graph** runner exposes:

| Parameter | Meaning |
|---|---|
| `host` | host whose cache to read (populated from cached hosts) |
| `view` | `tree` (default), `types` or `objects` |
| `orientation` | tree view: `tb` (levels top-to-bottom, default) or `lr` (left-to-right) |
| `order` | tree view: `dependents` (objects with dependencies first, default) or `primitives` (objects with no dependencies first) |
| `types` | optional filter, one or more object types |
| `focus` | optional object to centre on, e.g. `__file/etc/motd` |
| `direction` | with `focus`: `up` (its dependencies), `down` (its dependents) or `both` |
| `no collapse` | tree view: do not merge pass-through chains |

The helper modes `--list-hosts`, `--list-types HOST` and `--list-objects HOST`
feed the script-server value lists; they print plain lines and are not used
interactively.

## Files

| File | Purpose |
|---|---|
| `cdist-graph` | The renderer (Python 3, shells out to `dot`). |
| `cdist-graph.json` | The script-server runner definition. |

## Deployment

    ln -s .../scriptserver/cdist-graph/cdist-graph ~/bin/cdist-graph
    ln -s .../scriptserver/cdist-graph/cdist-graph.json \
          /etc/script-server-dev/runners/cdist-graph.json

Requires the `graphviz` package (`dot`) on the cdist server.

## CLI examples

    cdist-graph --list-hosts
    cdist-graph --list-types proxy.lnw.verboom.net
    cdist-graph proxy.lnw.verboom.net                     # layered tree, top-to-bottom, dependents first
    cdist-graph proxy.lnw.verboom.net --orientation lr      # layered tree, left-to-right
    cdist-graph proxy.lnw.verboom.net --order primitives    # primitives first (run order)
    cdist-graph proxy.lnw.verboom.net --view types
    cdist-graph proxy.lnw.verboom.net --focus __le --direction down
    cdist-graph proxy.lnw.verboom.net --types __file --dot | dot -Tpng > g.png
