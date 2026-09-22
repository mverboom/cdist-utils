#!/usr/bin/env bats
#
# Test suite for cdist-freshtest. Run with: bats test/cdist-freshtest.bats
#
# ct and runcdist are faked: the fake ct records deploy/destroy calls, the fake
# runcdist prints a cdist-like log whose content is chosen by the exported
# FAKE_MODE, so the idempotency verdict can be verified without touching any
# infrastructure.

bats_require_minimum_version 1.5.0

setup() {
   CF_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
   CF_TEST="$CF_ROOT/cdist-freshtest"
   CF_FIX="$(mktemp -d "${TMPDIR:-/tmp}/cdist-freshtest-test.XXXXXX")"
   export CF_FIX
   export CDIST_FRESHTEST_WORK="$CF_FIX/work"
   mkdir -p "$CF_FIX/bin"

   cat > "$CF_FIX/bin/ct" <<'FAKE'
#!/bin/bash
echo "ct $*" >> "$CF_FIX/calls"
if test "${FAKE_CT_FAIL:-}" = "deploy" && test "$1" = "deploy"; then
   echo "ct: no free container id" >&2
   exit 1
fi
exit 0
FAKE
   cat > "$CF_FIX/bin/runcdist" <<'FAKE'
#!/bin/bash
echo "runcdist $*" >> "$CF_FIX/calls"
host="${!#}"
probe=0
for arg in "$@"; do test "$arg" = "-d" && probe=1; done
echo "INFO: $host: Starting dry run"
case "${FAKE_MODE:-idempotent}" in
idempotent)
   ;;
nonidempotent)
   if test "$probe" -eq 1; then
      echo "INFO: $host: Processing __file/etc/example"
      echo "INFO: $host: Processing __file/etc/other"
      echo "INFO: $host: Processing __apt_update_index/"
   fi
   ;;
converge)
   n=$(cat "$CF_FIX/probes" 2>/dev/null || echo 0)
   echo $(( n + 1 )) > "$CF_FIX/probes"
   if test "$n" -eq 0; then
      echo "INFO: $host: Processing __file/etc/example"
   fi
   ;;
error)
   echo "ERROR: $host: /path/to/type/manifest: command not found"
   echo "ERROR: cdist: Failed to configure the following hosts: $host"
   exit 1
   ;;
esac
echo "INFO: $host: Finished dry run in 2.00 seconds"
exit 0
FAKE
   chmod 755 "$CF_FIX/bin/ct" "$CF_FIX/bin/runcdist"
   cat > "$CF_FIX/bin/ssh" <<'FAKE'
#!/bin/bash
echo "ssh $*" >> "$CF_FIX/calls"
test "${FAKE_SSH_OK:-1}" = "1" && exit 0
echo "ssh: connect to host port 22: Connection timed out" >&2
exit 255
FAKE
   chmod 755 "$CF_FIX/bin/ssh"
   export PATH="$CF_FIX/bin:$PATH"
   export FAKE_MODE=idempotent
   export CDIST_FRESHTEST_WAIT_TRIES=1 CDIST_FRESHTEST_WAIT_SLEEP=0
   : > "$CF_FIX/calls"
}

teardown() {
   rm -rf "$CF_FIX"
}

# Run the test tool for host "fresh"; result in CF_STATUS, output in CF_OUT.
run_freshtest() {
   CF_STATUS=0
   "$CF_TEST" "$@" fresh > "$CF_FIX/out" 2>&1 || CF_STATUS=$?
   CF_OUT="$(cat "$CF_FIX/out")"
   return 0
}

# Return the recorded ct/runcdist calls.
calls() {
   cat "$CF_FIX/calls"
}

@test "an idempotent host passes and is destroyed again" {
   run_freshtest
   [ "$CF_STATUS" -eq 0 ]
   [[ "$CF_OUT" == *"IDEMPOTENT"* ]]
   [[ "$CF_OUT" == *"0 object(s) would still change"* ]]
   run calls
   [[ "$output" == *"ct deploy fresh"* ]]
   [[ "$output" == *"ct destroy fresh"* ]]
}

@test "a host that is not idempotent fails and lists the objects" {
   FAKE_MODE=nonidempotent
   run_freshtest
   [ "$CF_STATUS" -eq 1 ]
   [[ "$CF_OUT" == *"NOT-IDEMPOTENT"* ]]
   [[ "$CF_OUT" == *"2 __file"* ]]
   [[ "$CF_OUT" == *"1 __apt_update_index"* ]]
   run calls
   [[ "$output" == *"ct destroy fresh"* ]]
}

@test "the fqdn is built from the name and the domain" {
   run_freshtest
   run calls
   [[ "$output" == *"runcdist -d -v fresh.lnw.verboom.net"* ]]
   [[ "$CF_OUT" == *"cdist-freshtest fresh: IDEMPOTENT (fresh.lnw.verboom.net)"* ]]
}

@test "a custom domain is honoured" {
   export CDIST_FRESHTEST_DOMAIN=example.net
   run_freshtest
   [[ "$CF_OUT" == *"fresh.example.net"* ]]
   run calls
   [[ "$output" == *"runcdist -d -v fresh.example.net"* ]]
}

@test "a deploy failure on an unreachable host is reported and cleaned up" {
   export FAKE_CT_FAIL=deploy
   export FAKE_SSH_OK=0
   export CDIST_FRESHTEST_RETRIES=0
   run_freshtest
   [ "$CF_STATUS" -eq 1 ]
   [[ "$CF_OUT" == *"DEPLOY-FAILED"* ]]
   run calls
   [[ "$output" == *"ct destroy fresh"* ]]
}

@test "--keep leaves the container alone" {
   run_freshtest --keep
   [ "$CF_STATUS" -eq 0 ]
   run calls
   [[ "$output" == *"ct deploy fresh"* ]]
   [[ "$output" != *"destroy"* ]]
}

@test "--probe-only only probes" {
   run_freshtest --probe-only --keep
   [ "$CF_STATUS" -eq 0 ]
   run calls
   [[ "$output" == *"runcdist -d -v fresh.lnw.verboom.net"* ]]
   [[ "$output" != *"ct deploy"* ]]
   [[ "$output" != *"destroy"* ]]
}

@test "errors during the dry run are reported" {
   FAKE_MODE=error
   run_freshtest --probe-only --keep
   [ "$CF_STATUS" -eq 1 ]
   [[ "$CF_OUT" == *"command not found"* ]]
}

@test "--second-run reports convergence" {
   FAKE_MODE=converge
   run_freshtest --probe-only --keep --second-run
   [ "$CF_STATUS" -eq 0 ]
   [[ "$CF_OUT" == *"NOT-IDEMPOTENT, converged after a second run"* ]]
   run calls
   [[ "$output" == *"runcdist -v fresh.lnw.verboom.net"* ]]
}

@test "--quiet prints the summary only" {
   run_freshtest --quiet
   [ "$CF_STATUS" -eq 0 ]
   [[ "$CF_OUT" == *"cdist-freshtest fresh: IDEMPOTENT"* ]]
   [[ "$CF_OUT" != *"=== deploy"* ]]
}

@test "a deploy that fails while the host is reachable is continued" {
   export FAKE_CT_FAIL=deploy
   run_freshtest
   [ "$CF_STATUS" -eq 0 ]
   [[ "$CF_OUT" == *"answers over ssh"* ]]
   [[ "$CF_OUT" == *"IDEMPOTENT, after configuring it here"* ]]
   run calls
   [[ "$output" == *"runcdist -v fresh.lnw.verboom.net"* ]]
   [[ "$output" == *"ct destroy fresh"* ]]
}

@test "the reachability check does not use the ssh control master" {
   export FAKE_CT_FAIL=deploy
   run_freshtest
   [ "$CF_STATUS" -eq 0 ]
   run calls
   [[ "$output" == *"ControlMaster=no"* ]]
   [[ "$output" == *"ControlPath=none"* ]]
}

@test "the reachability check has its own timeout" {
   grep -q "kill-after" "$CF_TEST"
   grep -q 'ControlMaster=no' "$CF_TEST"
}

@test "a deploy that leaves the host unreachable is retried once" {
   export FAKE_CT_FAIL=deploy
   export FAKE_SSH_OK=0
   run_freshtest
   [ "$CF_STATUS" -eq 1 ]
   [[ "$CF_OUT" == *"DEPLOY-FAILED"* ]]
   run calls
   [[ "$output" == *"ct deploy fresh"* ]]
   [[ "$output" == *"ct destroy fresh"* ]]
   [ "$(grep -c "ct deploy fresh" "$CF_FIX/calls")" -eq 2 ]
}

@test "the log contains every step" {
   FAKE_MODE=nonidempotent
   run_freshtest
   run cat "$CF_FIX/work/fresh.log"
   [[ "$output" == *"=== deploy: ct deploy fresh"* ]]
   [[ "$output" == *"Processing __file/etc/example"* ]]
   [[ "$output" == *"=== destroy"* ]]
}

@test "the inventory entry of the test host is removed again" {
   mkdir -p "$CF_FIX/inventory"
   printf 'lnw\nlxc\n' > "$CF_FIX/inventory/fresh.lnw.verboom.net"
   export CDIST_INVENTORY="$CF_FIX/inventory"
   run_freshtest
   [ "$CF_STATUS" -eq 0 ]
   [ ! -f "$CF_FIX/inventory/fresh.lnw.verboom.net" ]
   [ -f "$CF_FIX/work/fresh.inventory" ]
}

@test "an existing inventory entry of another host is left alone" {
   mkdir -p "$CF_FIX/inventory"
   printf 'lnw\n' > "$CF_FIX/inventory/other.lnw.verboom.net"
   export CDIST_INVENTORY="$CF_FIX/inventory"
   run_freshtest
   [ -f "$CF_FIX/inventory/other.lnw.verboom.net" ]
}

@test "the known_hosts entry of the test host is removed again" {
   cat > "$CF_FIX/bin/ssh-keygen" <<'FAKE'
#!/bin/bash
case "$1" in
-F) exit "${FAKE_KEYGEN_FOUND:-1}" ;;
-R) echo "removed $2" ;;
esac
exit 0
FAKE
   chmod 755 "$CF_FIX/bin/ssh-keygen"
   export FAKE_KEYGEN_FOUND=0
   run_freshtest
   [ "$CF_STATUS" -eq 0 ]
   [[ "$CF_OUT" == *"removed the known_hosts entry"* ]]
}

@test "without a name it prints usage" {
   run "$CF_TEST"
   [ "$status" -eq 1 ]
   [[ "$output" == *"cdist-freshtest"* ]]
}

@test "an unknown option is refused" {
   run "$CF_TEST" --nonsense fresh
   [ "$status" -eq 1 ]
   [[ "$output" == *"Unknown option"* ]]
}
