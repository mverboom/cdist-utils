# script-server integration

Web UI for building and running `eq` queries on the cdist server.

## How it works

The runner **Explorer Query** (`eq.json`) has an **Action** pulldown:

* **Query builder** (default) — an interactive HTML/JS page. Pick the report
  fields first (in order), then any number of conditions (field, operator,
  value, `not`) combined with `and`/`or`, and optionally limit hosts or tags.
* **Run query** — runs `eq -w` with the given flags and prints the result plus
  a link back to the builder.

Report fields are ordered: the page keeps an ordered list (add, ▲/▼, remove)
and passes it as a single comma separated `Report` value, so `eq -r` gets the
fields in exactly that order, just like the CLI. Each item is editable and has
an **add modifier** dropdown, so specs like `packages:~^nginx:f2` can be built
(the modifier help comes from `eq --catalog`). (script-server's multiselect
sends values in option order, not selection order, which is why `Report` is a
text parameter.)

The result table is built from `eq -j` using exactly the requested `-r` fields,
so it does not get the hostname column that `eq -w` always prepends. With no
report fields it lists the matching hostnames.

The builder keeps its state (conditions, report order, hosts, tags) in
`localStorage`, so returning after a run restores the previous query for
adjustment. **Reset** clears it.

The builder is rendered with `output_format: html_iframe`, so it is a full,
unsanitised HTML/JS document inside a same-origin `srcdoc` iframe. It does
**not** call any script-server API. Its **Run query** button navigates the top
window to this runner's hash route with the parameters prefilled:

```
#/Explorer%20Query?Action=run&Query=...&Report=...&Hosts=...&Tags=...&AllTags=...
```

`Action=run` is pinned because script-server's pre-fill replaces the whole
value state — parameters not in the link get no value, not their default.
Multiselect values are repeated query parameters (script-server turns them into
the array the multiselect expects).

## Files

| File | Purpose |
|---|---|
| `eq.json` | Runner definition (`output_format: html_iframe`), `Action` + include. |
| `include/eq-builder.json` | Builder action: no extra parameters. |
| `include/eq-run.json` | Run action: `Report` (ordered text), `Hosts`, `Tags`, `AllTags`, `Query`. |
| `eq-ss` | Wrapper: builder page or `eq -w` result page. |
| `eq-builder.html` | The builder page; `__EQ_CATALOG__` is replaced with the JSON from `eq --catalog`. |

The builder's data (fields with host counts and sample values, hosts, tags,
operator and modifier descriptions) comes from `eq --catalog` in one pass, so
there is a single source of truth with the CLI, completion and `--help`.

## Deployment

The runner and wrapper are symlinked from the cdist-utils checkout, so a
`git pull` activates changes (script-server re-reads runner files on page load):

```sh
cd /home/cdist/files.external/cdist-utils.git && git pull --ff-only origin master

# runner definition (replaces the previous regular file)
cp -a /etc/script-server-dev/runners/eq.json /root/eq.json.bak-$(date +%Y%m%d-%H%M)
ln -sfn /home/cdist/files.external/cdist-utils.git/scriptserver/eq.json \
        /etc/script-server-dev/runners/eq.json

# wrapper
ln -sfn ../files.external/cdist-utils.git/scriptserver/eq-ss /home/cdist/bin/eq-ss
```

No service restart is needed for parameter/value changes; restart
`script-server-dev` if the runner does not appear after a reload.

## Notes / limits

- **UI-mapped labels in deep-links.** script-server keeps the mapped
  `values_ui_mapping` label as the form value and maps it back to the script
  value for the command and the include path. A deep-link must therefore use
  the label (`Action=Run%20query`), not the raw value (`Action=run`), otherwise
  the form shows "Obsolete value". `eq-ss` reads the labels from `eq.json` and
  injects them into the builder, so the runner JSON stays the source of truth.
- The builder cannot execute anything itself; it only prefills the runner form,
  so a run needs one more click on **Run query** in the form.
- `X-Frame-Options: DENY` is set on script-server responses, so the app cannot
  be embedded in another site's iframe; `html_iframe` works because it uses
  `srcdoc` (same-origin), which is not subject to that header.
- The builder is only reachable by the users allowed in `conf.json`
  (`allowed_users`).
