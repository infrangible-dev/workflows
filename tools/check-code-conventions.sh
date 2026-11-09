#!/usr/bin/env bash
# Checks conventions of a module that PHPCS and PHPStan cannot express, mostly findings that PhpStorm reports.
#
# Array types in docblocks need a notation that satisfies both PhpStorm and PHPStan level 9: PhpStorm reports array
# types without key type ("mixed[]", "array<mixed>", "array<mixed, mixed>") as replaceable with "array", PHPStan needs
# the value type. Array keys are always int or string. So
# write "@param array $x" together with "@phpstan-param array<string, mixed> $x" (or "array<int, mixed>", or a more
# precise type).
#
# Exceptions that are caught without using them are caught without variable (PHP 8: "catch (Exception)"), PhpStorm
# reports the variable as unused.
#
# Null checks before a method call are written with the nullsafe operator (PHP 8: "$x?->get()" instead of
# "$x !== null ? $x->get() : null"), PhpStorm reports the ternary as replaceable.
#
# JavaScript variables are declared with "const" or "let" instead of "var" (ES6, supported by all browsers of Magento
# 2.4), PhpStorm reports "var". Only the JavaScript files of the module itself are checked (with the copyright header
# of Andreas Knollmann), not bundled libraries like select2.js. The variable "config" of requirejs-config.js may be a
# "const": Magento wraps each file in a function before it reads the variable.
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
check 'array<mixed\s*,' "Use 'array<int|string, mixed>' (or a more precise key type) instead of 'array<mixed, ...>'"

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
        body = source[start:end]
        # a nested catch with the same variable overwrites it, so uses inside it do not count
        nested = re.compile(r'catch\s*\([^)$]+?\s+' + re.escape(match.group(2)) + r'\)\s*\{')
        while (inner := nested.search(body)) is not None:
            innerEnd = inner.end()
            innerDepth = 1
            while innerDepth and innerEnd < len(body):
                innerDepth += (body[innerEnd] == '{') - (body[innerEnd] == '}')
                innerEnd += 1
            body = body[:inner.start()] + body[innerEnd:]
        if not re.search(re.escape(match.group(2)) + r'\b', body):
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

# ternaries that the nullsafe operator replaces
nullsafe=$(python3 - <<'PYTHON'
import pathlib, re

pattern = re.compile(
    r'(\$\w+(?:->\w+)*)\s*!==\s*null\s*\?\s*\1->\w+(?:\([^()]*\))?\s*:\s*null(?![\w(])'
    r'|null\s*!==\s*(\$\w+(?:->\w+)*)\s*\?\s*\2->\w+(?:\([^()]*\))?\s*:\s*null(?![\w(])'
    r'|(\$\w+(?:->\w+)*)\s*===\s*null\s*\?\s*null\s*:\s*\3->'
)
for path in sorted(pathlib.Path('src').rglob('*.php')):
    source = path.read_text(encoding='utf-8', errors='replace')
    for match in pattern.finditer(source):
        line = source.count('\n', 0, match.start()) + 1
        print(f'{path}:{line}: {match.group(0)}')
PYTHON
)
if [[ -n "${nullsafe}" ]]; then
  echo "${nullsafe}"
  message="Use the nullsafe operator: '\$x?->get()' instead of '\$x !== null ? \$x->get() : null'"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# JavaScript variables declared with var
jsVar=$(python3 - <<'PYTHON'
import pathlib, re

pattern = re.compile(r'(?<![\w$.])var\s+[\w$]')
for path in sorted(pathlib.Path('src').rglob('*.js')):
    source = path.read_text(encoding='utf-8', errors='replace')
    if 'Andreas Knollmann' not in source[:1000]:
        continue
    for number, line in enumerate(source.splitlines(), 1):
        if pattern.search(line.split('//', 1)[0]):
            print(f'{path}:{number}: {line.strip()}')
PYTHON
)
if [[ -n "${jsVar}" ]]; then
  echo "${jsVar}"
  message="Declare JavaScript variables with 'const' (or 'let' if they are assigned again) instead of 'var'"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

exit "${failed}"
