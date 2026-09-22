#!/usr/bin/env bats
#
# Test suite for the include/include_cfg functions of the initial manifest.
# Run with: bats test/initial-manifest.bats
#
# The functions are extracted from the initial manifest and run in a sandbox,
# because a manifest is not a library: sourcing the whole file would start a
# cdist run.
#
# The case that matters: include_cfg used to return at the first missing
# !reference, which silently dropped every reference after it. That deleted one
# sshconfig routing file and with it the whole block of container routes.

bats_require_minimum_version 1.5.0

setup() {
   IM="$BATS_TEST_DIRNAME/../initial-manifest"
   IM_FIX="$(mktemp -d "${TMPDIR:-/tmp}/initial-manifest-test.XXXXXX")"
   export IM_FIX
   mkdir -p "$IM_FIX/manifest/autorun" "$IM_FIX/repo" "$IM_FIX/dir1" \
      "$IM_FIX/dir2"

   {
      sed -n '/^include() {/,/^}$/p' "$IM"
      sed -n '/^include_cfg() {/,/^}$/p' "$IM"
   } > "$IM_FIX/functions.sh"

   # Minimal stubs for the parts of the initial manifest the functions expect.
   cat > "$IM_FIX/harness.sh" <<'EOF'
CDISTSOURCE() { . "$1"; }
MANIFESTALL=autorun
CDISTACTION=""
__manifest="$IM_FIX/manifest"
SOURCESTACKONCE=()
. "$IM_FIX/functions.sh"
EOF
   grep -q "^include() {" "$IM_FIX/functions.sh"
   grep -q "^include_cfg() {" "$IM_FIX/functions.sh"
}

teardown() {
   rm -rf "$IM_FIX"
}

# Run a shell snippet with the extracted functions loaded.
run_harness() {
   run bash -c ". '$IM_FIX/harness.sh'; $1"
}

@test "include_cfg expands !references in order" {
   printf '!present.conf\n!second.conf\n' > "$IM_FIX/dir1/user"
   printf 'x\n' > "$IM_FIX/repo/present.conf"
   printf 'x\n' > "$IM_FIX/repo/second.conf"
   run_harness 'include_cfg "$IM_FIX/repo" user "$IM_FIX/dir1"'
   [ "$status" -eq 0 ]
   [ "$output" = $'present.conf\nsecond.conf' ]
}

@test "a missing !reference is reported but the rest is still expanded" {
   printf '!missing.conf\n!present.conf\n!other.conf\n' > "$IM_FIX/dir1/user"
   printf 'x\n' > "$IM_FIX/repo/present.conf"
   printf 'x\n' > "$IM_FIX/repo/other.conf"
   run_harness 'include_cfg "$IM_FIX/repo" user "$IM_FIX/dir1"'
   [ "$status" -eq 1 ]
   [[ "$output" == *"present.conf"* ]]
   [[ "$output" == *"other.conf"* ]]
   [[ "$output" == *"File !missing.conf does not exist"* ]]
}

@test "a failing @include is reported but the rest is still expanded" {
   printf '@second\n!present.conf\n' > "$IM_FIX/dir1/user"
   printf '!missing.conf\n' > "$IM_FIX/dir2/second"
   printf 'x\n' > "$IM_FIX/repo/present.conf"
   run_harness 'include_cfg "$IM_FIX/repo" user "$IM_FIX/dir1" "$IM_FIX/dir2"'
   [ "$status" -eq 1 ]
   [[ "$output" == *"present.conf"* ]]
   [[ "$output" == *"Error processing include second"* ]]
}

@test "an unknown key returns 1 and expands nothing" {
   printf '!present.conf\n' > "$IM_FIX/dir1/user"
   run_harness 'include_cfg "$IM_FIX/repo" nosuchuser "$IM_FIX/dir1"'
   [ "$status" -eq 1 ]
   [ -z "$output" ]
}

@test "a key is looked up in the search directories in order" {
   printf '!present.conf\n' > "$IM_FIX/dir2/user"
   printf 'x\n' > "$IM_FIX/repo/present.conf"
   run_harness 'include_cfg "$IM_FIX/repo" user "$IM_FIX/dir1" "$IM_FIX/dir2"'
   [ "$status" -eq 0 ]
   [ "$output" = "present.conf" ]
}

@test "a !reference emits the file name and does not recurse into it" {
   printf '!middle.conf\n' > "$IM_FIX/dir1/user"
   printf '!leaf.conf\n' > "$IM_FIX/repo/middle.conf"
   printf 'x\n' > "$IM_FIX/repo/leaf.conf"
   run_harness 'include_cfg "$IM_FIX/repo" user "$IM_FIX/dir1"'
   [ "$status" -eq 0 ]
   [ "$output" = "middle.conf" ]
}

@test "include sources a manifest once per run" {
   printf 'SOURCED=$(( SOURCED + 1 ))\n' > "$IM_FIX/manifest/shared"
   run_harness 'SOURCED=0
      include shared
      include shared
      include_once shared
      echo "sourced=$SOURCED"'
   [ "$status" -eq 0 ]
   [[ "$output" == *"sourced=1"* ]]
}

@test "include returns 1 for a manifest that does not exist" {
   run_harness 'include nosuchmanifest; echo "rc=$?"'
   [[ "$output" == *"rc=1"* ]]
}

@test "include skips autorun manifests during a full run" {
   printf 'SOURCED=1\n' > "$IM_FIX/manifest/autorun/shared"
   run_harness 'CDISTACTION=""
      include shared; echo "rc=$?"'
   [[ "$output" == *"rc=0"* ]]
}

@test "include refuses to source the initial manifest itself" {
   printf 'echo self\n' > "$IM_FIX/manifest/init"
   run_harness '__cdist_manifest="$IM_FIX/manifest/init"
      include init; echo "rc=$?"'
   [[ "$output" == *"cannot be included"* ]]
}
