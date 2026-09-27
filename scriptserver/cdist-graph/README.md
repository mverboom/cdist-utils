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

Two levels are available:

* **types** (default in the runner) — objects are collapsed to their type, so
  `__file -> __package` becomes a single edge annotated with how many objects
  and dependencies it represents. Compact and readable; the whole-system
  overview.
* **objects** — one node per object, grouped in a dashed cluster per type.
  Detailed, and meant to be narrowed with `focus` or `types`.

In the graph:

* arrows point from a dependency to the object that requires it, following
  execution order;
* `require` edges are solid, `autorequire` edges dashed (line style, not
  colour, so it stays readable for colour-blind users);
* `require` edges drive the Graphviz ranking; `autorequire` is drawn but not
  allowed to influence it (its large fan-ins otherwise make the layout
  explode).

## Runners

The **cdist dependency graph** runner exposes:

| Parameter | Meaning |
|---|---|
| `host` | host whose cache to read (populated from cached hosts) |
| `level` | `types` (overview) or `objects` (detail) |
| `types` | optional filter, one or more object types |
| `focus` | optional object to centre on, e.g. `__file/etc/motd` |
| `direction` | with `focus`: `up` (its dependencies), `down` (its dependents) or `both` |

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
    cdist-graph proxy.lnw.verboom.net --level types
    cdist-graph proxy.lnw.verboom.net --focus __le --direction down
    cdist-graph proxy.lnw.verboom.net --types __file --dot | dot -Tpng > g.png
