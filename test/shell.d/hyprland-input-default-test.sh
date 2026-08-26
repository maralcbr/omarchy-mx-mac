#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

default_input="$ROOT/default/hypr/input.lua"
user_input="$ROOT/config/hypr/input.lua"

grep -Fq 'natural_scroll = false,' "$default_input" ||
  fail "shipped touchpad default uses traditional scrolling"
pass "shipped touchpad default uses traditional scrolling"

grep -Fq -- '--       natural_scroll = true,' "$user_input" ||
  fail "user override example documents natural scrolling"
pass "user override example documents natural scrolling"
