#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load helper

bt_setup

teardown_file() {
   bt_teardown
}

setup() {
   # shellcheck source=/dev/null
   source "$EQ_ROOT/eq-completion"
}

# Call _eq_completions with the given command line; the last argument is the
# word being completed (pass an empty string to complete a fresh word).
complete_eq() {
   COMP_WORDS=(eq "$@")
   COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
   COMP_TYPE=TAB
   COMP_LINE="${COMP_WORDS[*]}"
   COMP_POINT=${#COMP_LINE}
   _eq_completions
   return 0
}

@test "fresh word offers explorer names and options" {
   complete_eq ""
   [[ " ${COMPREPLY[*]} " == *" distr "* ]]
   [[ " ${COMPREPLY[*]} " == *" --json "* ]]
}

@test "first word completion is not blocked by the eq operator collision" {
   complete_eq "di"
   [ "${COMPREPLY[*]}" = "distr" ]
}

@test "report option completes explorer names" {
   complete_eq -r ""
   [[ " ${COMPREPLY[*]} " == *" distr "* ]]
   [[ " ${COMPREPLY[*]} " == *" packages "* ]]
}

@test "report option completes comma lists" {
   complete_eq -r "fqdn,dis"
   [[ " ${COMPREPLY[*]} " == *"fqdn,distr"* ]]
}

@test "report option completes field modifiers" {
   complete_eq -r "packages:"
   [[ " ${COMPREPLY[*]} " == *"packages:f1"* ]]
   [[ " ${COMPREPLY[*]} " == *"packages:trim"* ]]
}

@test "field modifiers complete after a comma in a report list" {
   complete_eq -r "fqdn,packages:"
   [[ " ${COMPREPLY[*]} " == *"fqdn,packages:f1"* ]]
   [[ " ${COMPREPLY[*]} " == *"fqdn,packages:trim"* ]]
   [[ " ${COMPREPLY[*]} " == *"fqdn,packages:~"* ]]
}

@test "field modifiers complete in an expression" {
   complete_eq "packages:"
   [[ " ${COMPREPLY[*]} " == *"packages:~"* ]]
   [[ " ${COMPREPLY[*]} " == *"packages:l1"* ]]
}

@test "field modifiers complete after a chained modifier" {
   complete_eq -r "packages:~^nginx:"
   [[ " ${COMPREPLY[*]} " == *"packages:~^nginx:f1"* ]]
}

@test "field completes the operators" {
   complete_eq distr ""
   [[ " ${COMPREPLY[*]} " == *" =="* ]]
   [[ " ${COMPREPLY[*]} " == *" contains "* ]]
   [[ " ${COMPREPLY[*]} " == *" exists "* ]]
}

@test "operand position offers the field values" {
   complete_eq distr == ""
   [[ " ${COMPREPLY[*]} " == *" debian "* ]]
   [[ " ${COMPREPLY[*]} " == *" alpine "* ]]
}

@test "operand completion filters by prefix" {
   complete_eq distr == de
   [ "${COMPREPLY[*]}" = "debian" ]
}

@test "fzf menu picks a candidate when enabled" {
   PATH="$BT_FIXTURE/fzfbins:$PATH"
   export PATH FZF_PICK=2
   unset EQ_PLAIN
   COMP_WORDS=(eq distr "")
   COMP_CWORD=2
   COMP_TYPE=TAB
   _eq_completions
   [ "${COMPREPLY[*]}" = "ne" ]
}

@test "fzf menu picks a field value at the operand position" {
   PATH="$BT_FIXTURE/fzfbins:$PATH"
   export PATH FZF_PICK=0
   unset EQ_PLAIN
   COMP_WORDS=(eq distr == "")
   COMP_CWORD=3
   COMP_TYPE=TAB
   _eq_completions
   [ "${COMPREPLY[*]}" = "alpine" ]
}

@test "field modifiers complete when readline splits on the colon" {
   COMP_LINE="eq -r fqdn:"
   COMP_POINT=${#COMP_LINE}
   COMP_WORDS=(eq -r fqdn :)
   COMP_CWORD=3
   COMP_TYPE=TAB
   _eq_completions
   [[ " ${COMPREPLY[*]} " == *"fqdn:f1"* ]]
   [[ " ${COMPREPLY[*]} " == *"fqdn:~"* ]]
}

@test "tokenizer keeps operators intact for value completion" {
   COMP_LINE="eq distr == de"
   COMP_POINT=${#COMP_LINE}
   COMP_WORDS=(eq distr == de)
   COMP_CWORD=3
   COMP_TYPE=TAB
   _eq_completions
   [ "${COMPREPLY[*]}" = "debian" ]
}

@test "second Tab prints help descriptions" {
   COMP_WORDS=(eq distr "")
   COMP_CWORD=2
   COMP_TYPE='?'
   _eq_completions 2> "$BT_FIXTURE/legend"
   grep -q "exact string match" "$BT_FIXTURE/legend"

   COMP_WORDS=(eq -r packages:)
   COMP_CWORD=2
   COMP_TYPE='?'
   _eq_completions 2> "$BT_FIXTURE/legend"
   grep -q "whitespace separated field" "$BT_FIXTURE/legend"
}

@test "after an operand offer close brackets and logic" {
   complete_eq distr == debian ""
   [[ " ${COMPREPLY[*]} " == *" and "* ]]
   [[ " ${COMPREPLY[*]} " == *" or "* ]]
   [[ " ${COMPREPLY[*]} " == *" ] "* ]]
}

@test "after a unary operator offer close brackets and logic" {
   complete_eq packages exists ""
   [[ " ${COMPREPLY[*]} " == *" and "* ]]
   [[ " ${COMPREPLY[*]} " == *" ] "* ]]
}

@test "closing bracket offers logic operators" {
   complete_eq "]" ""
   [ "${COMPREPLY[*]}" = "and or not" ]
}

@test "opening bracket offers only explorer names" {
   complete_eq "[" ""
   [[ " ${COMPREPLY[*]} " == *" distr "* ]]
   [[ " ${COMPREPLY[*]} " != *" --json "* ]]
}

@test "logic operator offers brackets and explorer names" {
   complete_eq distr == debian and ""
   [[ " ${COMPREPLY[*]} " == *" distr "* ]]
   [[ " ${COMPREPLY[*]} " == *" ["* ]]
}

@test "host option completes hostnames" {
   complete_eq -H ""
   [[ " ${COMPREPLY[*]} " == *"h1.example.com"* ]]
   [[ " ${COMPREPLY[*]} " == *"h2.example.com"* ]]
}

@test "tag option completes inventory tags" {
   complete_eq -t ""
   [[ " ${COMPREPLY[*]} " == *"tagA"* ]]
   [[ " ${COMPREPLY[*]} " == *"tagB"* ]]
}

@test "after a completed option value a fresh word offers explorer names" {
   complete_eq -r fqdn ""
   [[ " ${COMPREPLY[*]} " == *" distr "* ]]
   [[ " ${COMPREPLY[*]} " == *" packages "* ]]
   [[ " ${COMPREPLY[*]} " == *" --report "* ]]
}

@test "option value completions reset for each value-taking option" {
   complete_eq -H h1.example.com ""
   [[ " ${COMPREPLY[*]} " == *" distr "* ]]

   complete_eq --values distr ""
   [[ " ${COMPREPLY[*]} " == *" distr "* ]]
}

@test "flags do not shift the expression state" {
   complete_eq -x ""
   [[ " ${COMPREPLY[*]} " == *" distr "* ]]

   complete_eq -r fqdn distr ""
   [[ " ${COMPREPLY[*]} " == *" =="* ]]
}

@test "explorer and host completion skip hidden directories" {
   complete_eq ""
   [[ " ${COMPREPLY[*]} " != *" HEAD "* ]]
   [[ " ${COMPREPLY[*]} " == *" distr "* ]]

   complete_eq -H ""
   [[ " ${COMPREPLY[*]} " != *".git"* ]]
   [[ " ${COMPREPLY[*]} " == *"h1.example.com"* ]]
}
