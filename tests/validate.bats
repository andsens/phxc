#!/usr/bin/env bats
set -Eeo pipefail

@test 'ensure all fai scripts are executable' {
  # shellcheck disable=SC2314
  ! { find bootstrap/scripts -not -executable | grep '' >&2; }
}
