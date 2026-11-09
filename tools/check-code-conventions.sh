#!/usr/bin/env bash
# Checks conventions of a module that PHPCS and PHPStan cannot express, mostly findings that PhpStorm reports.
#
# Array types in docblocks need a notation that satisfies both PhpStorm and PHPStan level 9: PhpStorm reports array
# types without key type ("mixed[]", "array<mixed>") as replaceable with "array", PHPStan needs the value type. So
# write "@param array $x" together with "@phpstan-param array<string, mixed> $x" (or "array<int, mixed>", or a more
# precise type).
#
# Exceptions that are caught without using them are caught without variable (PHP 8: "catch (Exception)"), PhpStorm
# reports the variable as unused.
#
# Usage: tools/check-code-conventions.sh <module directory>

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

# catch blocks whose exception variable is not used
unusedCatch=$(python3 - <<'PYTHON'
import pathlib, re

for path in sorted(pathlib.Path('src').rglob('*.php')):
    source = path.read_text(encoding='utf-8', errors='replace')
    for match in re.finditer(r'catch\s*\(([^)$]+?)\s+(\$\w+)\)\s*\{', source):
        start = end = match.end()
        depth = 1
        while depth and end < len(source):
            depth += (source[end] == '{') - (source[end] == '}')
            end += 1
        if not re.search(re.escape(match.group(2)) + r'\b', source[start:end]):
            line = source.count('\n', 0, match.start()) + 1
            print(f'{path}:{line}: catch ({match.group(1)} {match.group(2)})')
PYTHON
)
if [[ -n "${unusedCatch}" ]]; then
  echo "${unusedCatch}"
  message="Catch exceptions that are not used without variable: 'catch (Exception)'"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

exit "${failed}"
