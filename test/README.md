# eq test suite

Tests for `eq` are written with [bats-core](https://github.com/bats-core/bats-core)
(Debian: `apt install bats`), matching the suite in the build repository.

Run them from the repository root:

```
bats test
```

`test/helper.bash` creates a throwaway `CDIST_EXPLORE` tree and a fake `cdist`
binary, so the tests never read real inventory or explorer data. The fake
covers `cdist inventory list`, `-H`, `-t` (any tag) and `-a -t` (all tags).

`test/eq.bats` covers the expression grammar and precedence, every operator,
the field modifiers, host/tag selection, deterministic report ordering, valid
JSON/CSV/HTML output, the missing-data regression, and the error exit codes.

`test/eq-completion.bats` sources `eq-completion` and drives `_eq_completions`
directly, checking the option, explorer-name, operator, bracket, host, tag,
field-modifier and operand-value completion contexts, plus the second-Tab help
legend. `test/eq.bats` also covers `--operators`, `--modifiers`, `--complete`
and the `--build` query builder.
