#!/usr/bin/env bash
# Checks docblock conventions of a module that PHPCS and PHPStan cannot express. Array types need a notation that
# satisfies both PhpStorm and PHPStan level 9: PhpStorm reports array types without key type ("mixed[]",
# "array<mixed>") as replaceable with "array", PHPStan needs the value type. So write "@param array $x" together with
# "@phpstan-param array<string, mixed> $x" (or "array<int, mixed>", or a more precise type).
#
# Usage: tools/check-docblock-conventions.sh <module directory>

set -u

moduleDir="${1:?Usage: $0 <module directory>}"

cd "${moduleDir}" || exit 1

failed=0

check() {
  local pattern="$1"
  local message="$2"

  if grep -rnE --include='*.php' --include='*.phtml' "${pattern}" src; then
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
      echo "::error::${message}"
    else
      echo "${message}" >&2
    fi
    failed=1
  fi
}

check 'mixed\[\]' "Use '@param array \$x' with '@phpstan-param array<string, mixed> \$x' instead of 'mixed[]'"
check 'array<mixed>' "Use 'array<string, mixed>' or 'array<int, mixed>' (or a more precise type) instead of 'array<mixed>'"

exit "${failed}"
