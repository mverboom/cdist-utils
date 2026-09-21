#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load helper

bt_setup

teardown_file() {
   bt_teardown
}

@test "builder keeps the chosen report field order" {
   if ! command -v node > /dev/null 2>&1; then
      skip "node is not installed"
   fi
   run node "$EQ_ROOT/test/eq-builder-dom.js"
   [ "$status" -eq 0 ]
   [ "$output" = "ok" ]
}

@test "run action takes report fields as an ordered text value" {
   run python3 -c '
import json
runner = json.load(open("'"$EQ_ROOT"'/scriptserver/include/eq-run.json"))
report = [p for p in runner["parameters"] if p["name"] == "Report"][0]
assert report["type"] == "text", report
assert report["param"] == "-r", report
'
   [ "$status" -eq 0 ]
}

@test "run action does not mark Query required so validation stays clean" {
   run python3 -c '
import json
runner = json.load(open("'"$EQ_ROOT"'/scriptserver/include/eq-run.json"))
query = [p for p in runner["parameters"] if p["name"] == "Query"][0]
assert not query.get("required"), query
'
   [ "$status" -eq 0 ]
}
