# cdist-utils

This is a small collection of scripts I use in combination with cdist to make my
life a bit easier :)

The scripts assume some settings that need to be available in order to function
properly. I set them in the cdist user's environment.

`CDIST_INSTALL=path_to_cdist_install`

The directory where cdist is installed.

`CDIST_EXPLORE=path_to_explore_output`

The directory where explorer output is stored.

## Components

The following components can be found in this repository:

### runcdist

Wrapper around cdist to make it easier to run cdist.

### cdist-upgrade

Wrapper around some git commands to make it easier to change versions/upgrade.

### eq

Query the explorer output to quickly find systems matching a condition, for
example `eq -r fqdn 'distr == debian and cpu_cores gt 1'`. See `EQ.md` for the
full description. The bash completion in `eq-completion` offers operator and
modifier help (press Tab twice) and completes real field values; `eq --build`
builds a query interactively.

### cdist-inventory

Create a cdist inventory based on explorer output.

### cdist-audit

Static audit of a cdist configuration: reports types, source files, explorer
variables, parameters and manifests that do not hold up, without contacting a
single host. See `CDIST-AUDIT.md` for the full description.

### cdist-render

Render the cdist object tree of a host offline (recorded explorer output, no
host contacted, no code executed) and diff two renders to see what a change
would touch. See `CDIST-RENDER.md`.

### initial-manifest

An example initial manifest I use and integrates part of the other scripts.

## Tests

The test suites use [bats](https://github.com/bats-core/bats-core) and live in
`test/`. Run them from the repository root with `bats test`.
