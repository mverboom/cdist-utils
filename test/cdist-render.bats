#!/usr/bin/env bats
#
# Test suite for cdist-render. Run with: bats test/cdist-render.bats
#
# cdist itself is faked: the fake binary writes a cache tree for the requested
# host, which is exactly what cdist-render has to parse. FAKE_MODE switches the
# fake between two configurations so the diff can be verified.

bats_require_minimum_version 1.5.0

setup() {
   CR_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
   CR_RENDER="$CR_ROOT/cdist-render"
   CR_FIX="$(mktemp -d "${TMPDIR:-/tmp}/cdist-render-test.XXXXXX")"
   export CR_FIX
   mkdir -p "$CR_FIX/bin" "$CR_FIX/explore" "$CR_FIX/config/manifest" \
      "$CR_FIX/config/explorer" "$CR_FIX/upstream/cdist/conf/explorer" \
      "$CR_FIX/stubs"
   printf '#!/bin/sh\necho host.example.com\n' > "$CR_FIX/config/explorer/fqdn"
   for host in host.example.com other.example.com fail.example.com; do
      mkdir -p "$CR_FIX/explore/$host"
      printf '%s\n' "$host" > "$CR_FIX/explore/$host/fqdn"
      printf 'debian\n' > "$CR_FIX/explore/$host/os"
   done
   cat > "$CR_FIX/bin/cdist" <<'FAKE'
#!/bin/bash
out=""
host=""
while test $# -gt 0; do
   case "$1" in
   -o) out="$2"; shift 2 ;;
   -C|-c|-r|--remote-exec|--remote-copy) shift 2 ;;
   config|-n) shift ;;
   *) host="$1"; shift ;;
   esac
done
data="$out/$host/data"
marker=".cdist-test"
mkdir -p "$data/object/__file/etc/base/$marker"
printf '%s\n' "$marker" > "$data/object_marker"
printf '__file/etc/base\n' > "$data/typeorder"
printf '__file/etc/example\n__file/etc/base\n' > "$data/typeorder"
if test -n "${FAKE_MODE:-}"; then
   printf 'changed\n' > "$data/messages"
   mkdir -p "$data/object/__file/etc/example/$marker/parameter"
   printf '0600\n' > "$data/object/__file/etc/example/$marker/parameter/mode"
   printf '__file/etc/base\n' > "$data/object/__file/etc/example/$marker/require"
   printf '__file/etc/base\n__file/etc/example\n' > "$data/typeorder"
else
   mkdir -p "$data/object/__file/etc/example/$marker/parameter"
   printf '0644\n' > "$data/object/__file/etc/example/$marker/parameter/mode"
   printf 'present\n' > "$data/object/__file/etc/example/$marker/parameter/state"
   printf '__file/etc/base\n' > "$data/object/__file/etc/example/$marker/require"
fi
if test "$host" = "fail.example.com"; then
   echo "ERROR: fake cdist failed on purpose" >&2
   exit 1
fi
exit 0
FAKE
   chmod 755 "$CR_FIX/bin/cdist"
}

teardown() {
   rm -rf "$CR_FIX"
}

run_render() {
   PATH="$CR_FIX/bin:$PATH" "$CR_RENDER" render \
      -c "$CR_FIX/config" -u "$CR_FIX/upstream/cdist/conf" \
      -e "$CR_FIX/explore" -w "$CR_FIX/work" -S "$CR_FIX/stubs" \
      -s "$CR_FIX/snap" "$@" 2>&1
}

@test "renders a host into a snapshot" {
   run run_render host.example.com
   [ "$status" -eq 0 ]
   [[ "$output" == *"host.example.com: ok, 2 objects"* ]]
   [ -f "$CR_FIX/snap/host.example.com.json" ]
}

@test "the snapshot holds objects, parameters, requires and order" {
   run_render host.example.com >/dev/null
   run jq -r '.objects[] | "\(.name) mode=\(.parameters.mode)"' \
      "$CR_FIX/snap/host.example.com.json"
   [[ "$output" == *"__file/etc/base mode=null"* ]]
   [[ "$output" == *"__file/etc/example mode=0644"* ]]
   run jq -r '.order | join(",")' "$CR_FIX/snap/host.example.com.json"
   [ "$output" = "__file/etc/example,__file/etc/base" ]
   run jq -r '.objects[] | select(.name == "__file/etc/example") | .require[0]' \
      "$CR_FIX/snap/host.example.com.json"
   [ "$output" = "__file/etc/base" ]
}

@test "renders every host that has explorer data with --all" {
   run run_render --all
   [ "$status" -eq 1 ]
   [[ "$output" == *"rendered 3 hosts"* ]]
   [[ "$output" == *"1 failed"* ]]
   [ -f "$CR_FIX/snap/other.example.com.json" ]
   [ -f "$CR_FIX/snap/fail.example.com.json" ]
}

@test "a failing host is reported with its error and the tree it had" {
   run run_render --all
   run jq -r '"\(.ok) \(.error)"' "$CR_FIX/snap/fail.example.com.json"
   [[ "$output" == *"false"* ]]
   [[ "$output" == *"fake cdist failed on purpose"* ]]
}

@test "identical renders produce no differences" {
   run run_render host.example.com other.example.com
   [ "$status" -eq 0 ]
   run env PATH="$CR_FIX/bin:$PATH" "$CR_RENDER" diff "$CR_FIX/snap" \
      "$CR_FIX/snap" -q
   [ "$status" -eq 0 ]
   [[ "$output" == *"0 of 2 hosts change"* ]]
}

@test "diffs a changed configuration and keeps the old snapshot" {
   run_render host.example.com >/dev/null
   cp -a "$CR_FIX/snap" "$CR_FIX/baseline"
   FAKE_MODE=1 run_render host.example.com
   run env PATH="$CR_FIX/bin:$PATH" "$CR_RENDER" diff "$CR_FIX/baseline" \
      "$CR_FIX/snap"
   [ "$status" -eq 1 ]
   [[ "$output" == *"host.example.com: 2 change(s)"* ]]
   [[ "$output" == *"mode: 0644 -> 0600"* ]]
   [[ "$output" == *"order"* ]]
}

@test "reports hosts that appear or disappear between snapshots" {
   run_render host.example.com >/dev/null
   cp -a "$CR_FIX/snap" "$CR_FIX/baseline"
   run_render host.example.com other.example.com >/dev/null
   run env PATH="$CR_FIX/bin:$PATH" "$CR_RENDER" diff "$CR_FIX/baseline" \
      "$CR_FIX/snap"
   [ "$status" -eq 1 ]
   [[ "$output" == *"hosts only in the current snapshot: other.example.com"* ]]
}

@test "diff --json is machine readable" {
   run_render host.example.com >/dev/null
   cp -a "$CR_FIX/snap" "$CR_FIX/baseline"
   FAKE_MODE=1 run_render host.example.com
   run env PATH="$CR_FIX/bin:$PATH" "$CR_RENDER" diff "$CR_FIX/baseline" \
      "$CR_FIX/snap" --json
   [ "$status" -eq 1 ]
   run bash -c "printf '%s' \"\$1\" | jq -r '.hosts[\"host.example.com\"].parameters[0]'" \
      _ "$output"
   [[ "$output" == *"mode: 0644 -> 0600"* ]]
}

@test "an unknown type explorer state defaults to the requested state" {
   run_render host.example.com >/dev/null || true
   mkdir -p "$CR_FIX/object/parameter"
   printf 'present\n' > "$CR_FIX/object/parameter/state"
   run env STUBS="$CR_FIX/stubs" "$CR_FIX/work/bin/fake-exec" somehost \
      "/bin/sh -c 'export __object=$CR_FIX/object; export __object_id=x; \
      /tmp/conf/type/__line/explorer/state'"
   [ "$output" = "present" ]
}

@test "a stub overrides the default type explorer answer" {
   mkdir -p "$CR_FIX/stubs/__thing" "$CR_FIX/object/parameter"
   printf 'present\n' > "$CR_FIX/object/parameter/state"
   printf '#!/bin/sh\necho "stubbed $__object_id"\n' \
      > "$CR_FIX/stubs/__thing/state"
   chmod 755 "$CR_FIX/stubs/__thing/state"
   run_render host.example.com >/dev/null || true
   run env STUBS="$CR_FIX/stubs" "$CR_FIX/work/bin/fake-exec" somehost \
      "/bin/sh -c 'export __object=$CR_FIX/object; export __object_id=abc; \
      /tmp/conf/type/__thing/explorer/state'"
   [ "$output" = "stubbed abc" ]
}

@test "the bundled stub directory is the default" {
   run bash -c "cd '$CR_ROOT' && ./cdist-render render --help"
   [ "$status" -eq 0 ]
   [ -d "$CR_ROOT/cdist-render-stubs/__ssh_dot_ssh" ]
}

@test "the explorer overlay replays the recorded data" {
   run_render host.example.com >/dev/null
   run cat "$CR_FIX/work/overlay/explorer/fqdn"
   [[ "$output" == *"CDIST_EXPLORE"* ]]
   run bash -c "CDIST_EXPLORE='$CR_FIX/explore' __target_host=host.example.com \
      '$CR_FIX/work/overlay/explorer/fqdn'"
   [ "$output" = "host.example.com" ]
}

@test "the fake remote runs commands locally and skips type explorers" {
   run_render host.example.com >/dev/null || true
   grep -q "conf/type" "$CR_FIX/work/bin/fake-exec"
   run "$CR_FIX/work/bin/fake-exec" somehost \
      "/bin/sh -c 'echo ran-locally'"
   [ "$output" = "ran-locally" ]
   run bash -c "'$CR_FIX/work/bin/fake-copy' '$CR_FIX/config/explorer/fqdn' \
      'somehost:$CR_FIX/copied' && cat '$CR_FIX/copied'"
   [[ "$output" == *"host.example.com"* ]]
   run "$CR_FIX/work/bin/fake-exec" somehost \
      "/bin/sh -c 'export __object_id=someid; /tmp/x/conf/type/__thing/explorer/state'"
   [ -z "$output" ]
}
