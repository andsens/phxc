#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

# bats file_tags=shellcheck
@test 'shellcheck tooling' {
  type shellcheck &>/dev/null || skip 'shellcheck not installed'
  find "$BATS_TEST_DIRNAME/../bin" "$BATS_TEST_DIRNAME/../workloads" -type f -exec grep -q '#!/usr/bin/env bash' \{\} \; -print0 | \
  xargs -0 shellcheck -x
}

# bats file_tags=shellcheck
@test 'shellcheck tests' {
  type shellcheck &>/dev/null || skip 'shellcheck not installed'
  (
    cd tests
    shellcheck -x -- *.bats
  )
}
