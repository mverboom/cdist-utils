#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load helper

bt_setup

teardown_file() {
   bt_teardown
}

# --- basic matching ---------------------------------------------------------

@test "single comparison selects matching hosts" {
   run "$EQ" -r fqdn distr == debian
   [ "$status" -eq 0 ]
   [ "$output" = $'h1.example.com\nh2.example.com' ]
}

@test "bracketed expressions still work" {
   run "$EQ" -r fqdn '[' distr == debian ']' and '[' cpu_cores gt 1 ']'
   [ "$status" -eq 0 ]
   [ "$output" = $'h1.example.com\nh2.example.com' ]
}

@test "and binds tighter than or" {
   run "$EQ" -r fqdn distr == alpine or distr == debian and cpu_cores gt 1
   [ "$status" -eq 0 ]
   [ "$output" = $'h1.example.com\nh2.example.com\nh3.example.com' ]
}

@test "or selects either side" {
   run "$EQ" -r fqdn distr == alpine or cpu_cores gt 100
   [ "$status" -eq 0 ]
   [ "$output" = "h3.example.com" ]
}

@test "not negates an expression" {
   run "$EQ" -r fqdn not distr == debian
   [ "$status" -eq 0 ]
   [ "$output" = "h3.example.com" ]
}

@test "parentheses group in a -q query" {
   run "$EQ" -r fqdn -q 'not (distr == debian or distr == alpine)'
   [ "$status" -eq 0 ]
   [ "$output" = "" ]
}

# --- operators --------------------------------------------------------------

@test "ne matches only hosts where the field differs" {
   run "$EQ" -r fqdn distr ne debian
   [ "$status" -eq 0 ]
   [ "$output" = "h3.example.com" ]
}

@test "numeric gt ignores hosts without the explorer (regression)" {
   run "$EQ" -r fqdn cpu_cores gt 1
   [ "$status" -eq 0 ]
   [ "$output" = $'h1.example.com\nh2.example.com' ]
}

@test "numeric lt ignores hosts without the explorer" {
   run "$EQ" -r fqdn cpu_cores lt 3
   [ "$status" -eq 0 ]
   [ "$output" = "h2.example.com" ]
}

@test "eq operator is implemented" {
   run "$EQ" -r fqdn cpu_cores eq 2
   [ "$status" -eq 0 ]
   [ "$output" = "h2.example.com" ]
}

@test "numeric comparison accepts SI suffixes" {
   run "$EQ" -r fqdn cpu_cores ge 1K
   [ "$status" -eq 0 ]
   [ "$output" = "" ]
}

@test "contains searches every record" {
   run "$EQ" -r fqdn packages contains nginx
   [ "$status" -eq 0 ]
   [ "$output" = $'h1.example.com\nh2.example.com' ]
}

@test "contains does not match hosts without the explorer" {
   run "$EQ" -r fqdn packages contains apache
   [ "$status" -eq 0 ]
   [ "$output" = "h1.example.com" ]
}

@test "icontains is case insensitive" {
   run "$EQ" -r fqdn distr icontains DEB
   [ "$status" -eq 0 ]
   [ "$output" = $'h1.example.com\nh2.example.com' ]
}

@test "matches uses a regular expression" {
   run "$EQ" -r fqdn distr matches '^deb'
   [ "$status" -eq 0 ]
   [ "$output" = $'h1.example.com\nh2.example.com' ]
}

@test "in matches a comma separated list" {
   run "$EQ" -r fqdn distr in alpine,ubuntu
   [ "$status" -eq 0 ]
   [ "$output" = "h3.example.com" ]
}

@test "exists selects hosts that have the explorer" {
   run "$EQ" -r fqdn packages exists
   [ "$status" -eq 0 ]
   [ "$output" = $'h1.example.com\nh2.example.com' ]
}

@test "empty selects hosts missing the explorer" {
   run "$EQ" -r fqdn cpu_cores empty
   [ "$status" -eq 0 ]
   [ "$output" = "h3.example.com" ]
}

@test "nonempty selects hosts with records" {
   run "$EQ" -r fqdn packages nonempty
   [ "$status" -eq 0 ]
   [ "$output" = $'h1.example.com\nh2.example.com' ]
}

# --- reporting --------------------------------------------------------------

@test "report columns keep the requested order" {
   run "$EQ" -r cpu_cores,fqdn cpu_cores nonempty
   [ "$status" -eq 0 ]
   [ "$output" = $'8 h1.example.com\n2 h2.example.com' ]
}

@test "missing explorer in a report is an empty column, not an error" {
   run --separate-stderr "$EQ" -r fqdn,cpu_cores distr == alpine
   [ "$status" -eq 0 ]
   [ "$output" = "h3.example.com " ]
   [ -z "$stderr" ]
}

@test "no report lists matching hostnames" {
   run "$EQ" distr == debian
   [ "$status" -eq 0 ]
   [ "$output" = $'h1.example.com\nh2.example.com' ]
}

@test "hidden directories like .git are not treated as hosts" {
   run "$EQ" --count
   [ "$status" -eq 0 ]
   [ "$output" = "3" ]
   run "$EQ"
   [ "$status" -eq 0 ]
   [ "$output" = $'h1.example.com\nh2.example.com\nh3.example.com' ]
}

@test "header is printed on request" {
   run "$EQ" --header --tsv -r fqdn,distr distr == debian
   [ "$status" -eq 0 ]
   [ "$output" = $'fqdn\tdistr\nh1.example.com\tdebian\nh2.example.com\tdebian' ]
}

@test "csv quotes embedded newlines" {
   run "$EQ" --csv -r fqdn,packages packages contains apache
   [ "$status" -eq 0 ]
   [[ "$output" == *'"nginx 1.2.3'* ]]
   [[ "$output" == *'apache 2.0"'* ]]
}

@test "json output is valid and preserves values" {
   run "$EQ" -j -r fqdn,note note exists
   [ "$status" -eq 0 ]
   echo "$output" | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert len(data) == 1, data
assert data[0]["hostname"] == "h1.example.com", data
assert data[0]["note"] == "<b>&\"q\"", data
'
}

@test "html output is escaped" {
   run "$EQ" -w -r note note exists
   [ "$status" -eq 0 ]
   [[ "$output" == *'&lt;b&gt;&amp;&quot;q&quot;'* ]]
}

# --- selection helpers ------------------------------------------------------

@test "count prints only the number of matches" {
   run "$EQ" --count -q 'cpu_cores ge 2'
   [ "$status" -eq 0 ]
   [ "$output" = "2" ]
}

@test "values lists distinct field values" {
   run "$EQ" --values distr
   [ "$status" -eq 0 ]
   [ "$output" = $'alpine\ndebian' ]
}

@test "list-explorers lists explorer names" {
   run "$EQ" --list-explorers
   [ "$status" -eq 0 ]
   [ "$output" = $'cpu_cores\ndistr\nfqdn\nnote\npackages' ]
}

@test "sort orders by a report field" {
   run "$EQ" --sort cpu_cores -r fqdn,cpu_cores cpu_cores nonempty
   [ "$status" -eq 0 ]
   [ "$output" = $'h2.example.com 2\nh1.example.com 8' ]
}

@test "limit truncates after sorting" {
   run "$EQ" --limit 1 -r fqdn distr == debian
   [ "$status" -eq 0 ]
   [ "$output" = "h1.example.com" ]
}

@test "H selects explicit hosts" {
   run "$EQ" -H h1.example.com,h3.example.com -r fqdn
   [ "$status" -eq 0 ]
   [ "$output" = $'h1.example.com\nh3.example.com' ]
}

@test "unknown explicit host warns but keeps going" {
   run --separate-stderr "$EQ" -H h1.example.com,nope.example.com -r fqdn
   [ "$status" -eq 0 ]
   [ "$output" = "h1.example.com" ]
   [[ "$stderr" == *"nope.example.com"* ]]
}

@test "t selects hosts with any tag" {
   run "$EQ" -t tagA,tagC -r fqdn
   [ "$status" -eq 0 ]
   [ "$output" = $'h1.example.com\nh3.example.com' ]
}

@test "T selects hosts with all tags" {
   run "$EQ" -T tagA,tagB -r fqdn
   [ "$status" -eq 0 ]
   [ "$output" = "h1.example.com" ]
}

@test "list-tags lists inventory tags" {
   run "$EQ" --list-tags
   [ "$status" -eq 0 ]
   [ "$output" = $'tagA\ntagB\ntagC' ]
}

# --- field modifiers --------------------------------------------------------

@test "field modifier selects a whitespace separated column" {
   run "$EQ" -r 'fqdn,packages:~^nginx:f2' packages exists
   [ "$status" -eq 0 ]
   [[ "$output" == *"h1.example.com 1.2.3"* ]]
}

@test "line and regex modifiers filter" {
   run "$EQ" -r 'packages:l1' packages exists
   [ "$status" -eq 0 ]
   [[ "$output" == *"nginx 1.2.3"* ]]
}

# --- errors -----------------------------------------------------------------

@test "unknown operator exits 2" {
   run --separate-stderr "$EQ" -r fqdn distr bogus x
   [ "$status" -eq 2 ]
   [[ "$stderr" == *"bogus"* ]]
}

@test "missing operand exits 2" {
   run "$EQ" -r fqdn distr ==
   [ "$status" -eq 2 ]
}

@test "invalid regex exits 2" {
   run "$EQ" -r fqdn distr matches '['
   [ "$status" -eq 2 ]
}

@test "sort by an unknown field exits 2" {
   run "$EQ" --sort nope -r fqdn
   [ "$status" -eq 2 ]
}

@test "unset CDIST_EXPLORE exits 1" {
   run --separate-stderr env -u CDIST_EXPLORE "$EQ" -r fqdn
   [ "$status" -eq 1 ]
   [[ "$stderr" == *CDIST_EXPLORE* ]]
}
