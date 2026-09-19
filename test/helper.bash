# Shared fixture for the eq test suite. Run with: bats test
#
# Creates a throwaway CDIST_EXPLORE tree plus a fake cdist binary, so the
# tests never touch real inventory or explorer data.

EQ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034  # EQ is used by the .bats files, not here
EQ="$EQ_ROOT/eq"

bt_setup() {
   BT_FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/eq-test.XXXXXX")"
   export BT_FIXTURE
   export CDIST_EXPLORE="$BT_FIXTURE/explore"
   mkdir -p "$CDIST_EXPLORE" "$BT_FIXTURE/bin"

   # h1: debian, 8 cores, two packages, hostile note.
   # h2: debian, 2 cores, one package.
   # h3: alpine, no cpu_cores, no packages, no note.
   mkdir -p "$CDIST_EXPLORE/h1.example.com" "$CDIST_EXPLORE/h2.example.com" \
      "$CDIST_EXPLORE/h3.example.com"

   printf 'h1.example.com\n' > "$CDIST_EXPLORE/h1.example.com/fqdn"
   printf 'h2.example.com\n' > "$CDIST_EXPLORE/h2.example.com/fqdn"
   printf 'h3.example.com\n' > "$CDIST_EXPLORE/h3.example.com/fqdn"

   printf 'debian\n' > "$CDIST_EXPLORE/h1.example.com/distr"
   printf 'debian\n' > "$CDIST_EXPLORE/h2.example.com/distr"
   printf 'alpine\n' > "$CDIST_EXPLORE/h3.example.com/distr"

   printf '8\n' > "$CDIST_EXPLORE/h1.example.com/cpu_cores"
   printf '2\n' > "$CDIST_EXPLORE/h2.example.com/cpu_cores"

   printf 'nginx 1.2.3\napache 2.0\n' > "$CDIST_EXPLORE/h1.example.com/packages"
   printf 'nginx 1.2.3\n' > "$CDIST_EXPLORE/h2.example.com/packages"

   printf '%s\n' '<b>&"q"' > "$CDIST_EXPLORE/h1.example.com/note"

   # A versioned explore tree contains a .git directory; it must never be
   # treated as a host.
   mkdir -p "$CDIST_EXPLORE/.git"
   printf 'ref: refs/heads/master\n' > "$CDIST_EXPLORE/.git/HEAD"

   # Fake cdist. h1 carries tagA,tagB, h2 carries tagB and h3 carries tagC.
   # `cdist inventory list -H` lists hosts, `-t` does any-tag, `-a -t` all-tag.
   cat > "$BT_FIXTURE/bin/cdist" <<'EOF'
#!/bin/bash
hosts=(h1.example.com h2.example.com h3.example.com)
tags=(tagA,tagB tagB tagC)
all=0; want=0; haveH=0; tlist=()
while test $# -gt 0; do
   case "$1" in
   inventory|list) shift ;;
   -H) haveH=1; shift ;;
   -a) all=1; shift ;;
   -t) want=1; shift
       while test $# -gt 0 && [[ "$1" != -* ]]; do tlist+=("$1"); shift; done ;;
   *) shift ;;
   esac
done
for i in "${!hosts[@]}"; do
   h="${hosts[$i]}"; ht=(${tags[$i]//,/ })
   if test "$haveH" = 1; then
      if test "$want" = 0; then echo "$h"; continue; fi
      match=0
      if test "$all" = 1; then
         match=1
         for t in "${tlist[@]}"; do
            [[ " ${ht[*]} " == *" $t "* ]] || match=0
         done
      else
         for t in "${tlist[@]}"; do
            [[ " ${ht[*]} " == *" $t "* ]] && match=1
         done
      fi
      test "$match" = 1 && echo "$h"
   else
      echo "$h ${tags[$i]}"
   fi
done
exit 0
EOF
   chmod +x "$BT_FIXTURE/bin/cdist"
   # The completion calls `eq --complete`, so eq must be on PATH.
   ln -sf "$EQ" "$BT_FIXTURE/bin/eq"
   export PATH="$BT_FIXTURE/bin:$PATH"

   # Tests use the plain completion so they never need a TTY; the fzf path has
   # its own test with the stub below.
   export EQ_PLAIN=1
   mkdir -p "$BT_FIXTURE/fzfbins"
   cat > "$BT_FIXTURE/fzfbins/fzf" <<'EOF'
#!/bin/bash
lines=(); while IFS= read -r line; do lines+=("$line"); done
printf '%s\n' "${lines[${FZF_PICK:-0}]}"
exit 0
EOF
   chmod +x "$BT_FIXTURE/fzfbins/fzf"
}

bt_teardown() {
   test -n "$BT_FIXTURE" && rm -rf "$BT_FIXTURE"
}
