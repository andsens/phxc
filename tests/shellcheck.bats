#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

# bats file_tags=shellcheck
@test 'shellcheck tooling' {
  type shellcheck &>/dev/null || skip 'shellcheck not installed'
  shellcheck -x \
    "$BATS_TEST_DIRNAME"/../bin/* \
    "$BATS_TEST_DIRNAME"/../workloads/*/commands/* \
    "$BATS_TEST_DIRNAME"/../lib/*
}

# bats file_tags=shellcheck
@test 'shellcheck tests' {
  type shellcheck &>/dev/null || skip 'shellcheck not installed'
  (
    cd tests
    shellcheck -x -- *.bats
  )
}
