#!/usr/bin/env bats
#
# Test suite for cdist-audit. Run with: bats test/cdist-audit.bats
#
# Builds a throwaway configuration tree containing one good manifest and a pile
# of deliberate defects, then asserts that every check fires - and, just as
# important, that the checks stay quiet on the harmless cases (quoted
# parameters, require targets, $files references, upstream types).

bats_require_minimum_version 1.5.0

setup() {
   CA_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
   CA_AUDIT="$CA_ROOT/cdist-audit"
   CA_FIX="$(mktemp -d "${TMPDIR:-/tmp}/cdist-audit-test.XXXXXX")"
   export CA_FIX
   build_fixture
   run_audit
}

teardown() {
   rm -rf "$CA_FIX"
}

build_fixture() {
   local up="$CA_FIX/upstream/cdist/conf" cfg="$CA_FIX/config"

   mkdir -p "$up/type" "$up/explorer"
   printf '#!/bin/sh\necho upstream\n' > "$up/explorer/upstream_explorer"
   printf '#!/bin/sh\necho host.example.com\n' > "$up/explorer/fqdn"
   mkdir -p "$up/type/__upstream_type/parameter"
   printf '#!/bin/sh\necho upstream\n' > "$up/type/__upstream_type/manifest"
   printf 'state\n' > "$up/type/__upstream_type/parameter/optional"
   local type
   for type in __file __config_file __directory; do
      mkdir -p "$up/type/$type/parameter"
      printf '#!/bin/sh\necho upstream\n' > "$up/type/$type/manifest"
      printf 'state\n' > "$up/type/$type/parameter/required"
      printf 'group\nmode\nowner\nsource\nonchange\nparents\n' \
         > "$up/type/$type/parameter/optional"
   done

   mkdir -p "$cfg/manifest/autorun" "$cfg/manifest/old" "$cfg/files/dir" \
      "$cfg/explorer" "$cfg/type/__local_type/parameter" \
      "$cfg/type/__other_type/parameter" "$cfg/type/__unused_type"
   printf 'include good\n' > "$cfg/manifest/init"

   cat > "$cfg/manifest/autorun/good" <<'EOF'
#!/bin/bash
test "$e_fqdn" = "" && return 0
__local_type good1 --state present --mode 0644 --source "$files/dir/file"
__other_type thing --flag "value with --notaparam and --state inside"
require="__local_type/good1" __other_type thing2 --flag other
__file /etc/example --state present --source "$files/dir/file"
if test "$e_local_explorer" = "yes"; then
   echo "good explorer"
fi
EOF

   cat > "$cfg/manifest/autorun/defects" <<'EOF'
#!/bin/bash
__nosuchtype broken
require="__nosuchtype/other" __local_type broken2 --state present
echo "$e_nosuchvar $t_nosuchtag"
__local_type broken3 --state present --nosuchparam yes
__config_file /etc/other --state present --source "$files/missing/file"
__file /etc/example --state present
include no_such_manifest
include_cfg "$files/nosuchdir" somekey
EOF
   printf '#!/bin/bash\nif true; then\n' > "$cfg/manifest/autorun/syntaxerror"
   printf '#!/bin/bash\necho dead\n' > "$cfg/manifest/old/dead"
   touch "$cfg/manifest/autorun/.good.swp"

   printf '#!/bin/sh\necho present\n' > "$cfg/type/__local_type/manifest"
   printf 'state\n' > "$cfg/type/__local_type/parameter/required"
   printf 'mode\nsource\nonchange\n' > "$cfg/type/__local_type/parameter/optional"
   printf '#!/bin/sh\necho present\n' > "$cfg/type/__other_type/manifest"
   printf 'name\n' > "$cfg/type/__other_type/parameter/required"
   printf 'flag\n' > "$cfg/type/__other_type/parameter/optional"
   printf '#!/bin/sh\necho unused\n' > "$cfg/type/__unused_type/manifest"
   printf '#!/bin/sh\necho local\n' > "$cfg/explorer/local_explorer"
   printf 'content\n' > "$cfg/files/dir/file"
   ln -s /nonexistent/target "$cfg/type/__broken_type"

   mkdir -p "$CA_FIX/inventory" "$CA_FIX/explore/old.example.com"
   printf 'tag1,qemu\n' > "$CA_FIX/inventory/host1.example.com"
   printf 'x\n' > "$CA_FIX/explore/old.example.com/local_explorer"
   touch -d '100 days ago' "$CA_FIX/explore/old.example.com/local_explorer"

   mkdir -p "$CA_FIX/clean/manifest/autorun" "$CA_FIX/clean/type/__thing" \
      "$CA_FIX/clean/type/__thing/parameter"
   printf '__thing x --state present\n' > "$CA_FIX/clean/manifest/init"
   printf '#!/bin/sh\necho present\n' > "$CA_FIX/clean/type/__thing/manifest"
   printf 'state\n' > "$CA_FIX/clean/type/__thing/parameter/required"
   printf '' > "$CA_FIX/clean/type/__thing/parameter/optional"
   printf '#!/bin/bash\nlocal bad=1\n' > "$CA_FIX/clean/manifest/notafunction"
}

# Run the audit over the defect fixture and keep the json output.
run_audit() {
   CA_STATUS=0
   "$CA_AUDIT" --json --no-shellcheck -q \
      -c "$CA_FIX/config" \
      -u "$CA_FIX/upstream/cdist/conf" \
      -i "$CA_FIX/inventory" \
      -e "$CA_FIX/explore" > "$CA_FIX/out.json" || CA_STATUS=$?
   return 0
}

# Assert that at least one finding has the given check name.
assert_check() {
   jq -e --arg check "$1" 'any(.[]; .check == $check)' "$CA_FIX/out.json" \
      >/dev/null || {
      echo "no $1 finding in:"
      jq -r '.[] | "  \(.check): \(.message)"' "$CA_FIX/out.json"
      return 1
   }
}

# Assert that no finding has the given check name.
refute_check() {
   jq -e --arg check "$1" 'any(.[]; .check == $check) | not' \
      "$CA_FIX/out.json" >/dev/null || { echo "unexpected $1 finding"; return 1; }
}

# Assert that a check fired with a message containing the given text.
assert_message() {
   jq -e --arg check "$1" --arg text "$2" \
      'any(.[]; .check == $check and (.message | contains($text)))' \
      "$CA_FIX/out.json" >/dev/null || {
      echo "no $1 finding containing '$2'"
      return 1
   }
}

# Return every message of one check, one per line.
messages_of() {
   jq -r --arg check "$1" '.[] | select(.check == $check) | .message' \
      "$CA_FIX/out.json"
}

# Assert that a check fired for a path containing the given text.
assert_path() {
   jq -e --arg check "$1" --arg text "$2" \
      'any(.[]; .check == $check and (.path | contains($text)))' \
      "$CA_FIX/out.json" >/dev/null || {
      echo "no $1 finding for a path containing '$2'"
      return 1
   }
}

@test "reports a type that does not exist" {
   assert_check type-missing
   assert_message type-missing "__nosuchtype"
}

@test "reports a require target with an unknown type" {
   assert_check require-missing
   assert_message require-missing "__nosuchtype/other"
}

@test "reports an explorer variable no explorer provides" {
   assert_check explorer-undefined
   assert_message explorer-undefined '$e_nosuchvar'
}

@test "reports an inventory tag that does not exist" {
   assert_check tag-undefined
   assert_message tag-undefined '$t_nosuchtag'
}

@test "reports a \$files reference that does not exist" {
   assert_check source-missing
   assert_message source-missing 'files/missing/file'
}

@test "reports a manifest that cannot be included" {
   assert_check include-missing
   assert_message include-missing 'no_such_manifest'
}

@test "reports an include_cfg repository that does not exist" {
   assert_check include-cfg-repo-missing
   assert_message include-cfg-repo-missing 'nosuchdir'
}

@test "reports an unknown parameter" {
   assert_check param-unknown
   assert_message param-unknown '--nosuchparam'
}

@test "does not report parameters that sit inside a quoted value" {
   run messages_of param-unknown
   [[ "$output" != *notaparam* ]]
}

@test "does not report the special require parameter as unknown" {
   run messages_of param-unknown
   [[ "$output" != *"--require"* ]]
}

@test "does not report a known parameter as unknown" {
   run messages_of param-unknown
   [[ "$output" != *"--mode"* ]]
}

@test "reports a required parameter that is never passed" {
   assert_check param-required-missing
   assert_message param-required-missing '--name'
}

@test "reports the same path managed from two manifests" {
   assert_check path-conflict
   assert_message path-conflict '/etc/example'
}

@test "reports a syntax error" {
   assert_check syntax
   assert_message syntax 'syntaxerror'
}

@test "reports an editor leftover" {
   assert_check editor-leftover
   assert_path editor-leftover '.good.swp'
}

@test "reports a broken symlink" {
   assert_check symlink-broken
   assert_message symlink-broken '__broken_type'
}

@test "reports a manifest nothing includes" {
   assert_check manifest-unreferenced
   assert_path manifest-unreferenced 'manifest/old/dead'
}

@test "reports an unused local type but not an unused upstream type" {
   assert_check type-unused
   assert_message type-unused '__unused_type'
   run messages_of type-unused
   [[ "$output" != *"__upstream_type"* ]]
}

@test "reports stale explorer output and hosts without explorer data" {
   assert_check host-stale
   assert_message host-stale 'old.example.com'
   assert_check explore-missing
   assert_message explore-missing 'host1.example.com'
}

@test "reports tags that no manifest uses" {
   assert_check tag-unused
   assert_message tag-unused 'qemu'
}

@test "exits non-zero when errors were found" {
   [ "$CA_STATUS" -eq 1 ]
}

@test "a clean configuration has no errors and exits zero" {
   run "$CA_AUDIT" -q -c "$CA_FIX/clean" -u "$CA_FIX/upstream/cdist/conf" \
      --no-shellcheck
   [ "$status" -eq 0 ]
   [[ "$output" == *"0 error"* ]]
}

@test "--only limits the checks that run" {
   run "$CA_AUDIT" --json -q -c "$CA_FIX/config" \
      -u "$CA_FIX/upstream/cdist/conf" -i "$CA_FIX/inventory" \
      --only source-missing
   [ "$status" -eq 1 ]
   [ "$(jq -r '.[].check' <<<"$output" | sort -u)" = "source-missing" ]
}

@test "shellcheck reports its errors when enabled" {
   command -v shellcheck >/dev/null || skip "shellcheck is not installed"
   run "$CA_AUDIT" --json -q -c "$CA_FIX/clean" -u "$CA_FIX/upstream/cdist/conf"
   [ "$status" -eq 1 ]
   [[ "$output" == *'"check": "shellcheck"'* ]]
}
