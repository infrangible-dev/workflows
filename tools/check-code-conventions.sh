#!/usr/bin/env bash
# Checks conventions of a module that PHPCS and PHPStan cannot express, mostly findings that PhpStorm reports.
#
# Array types in docblocks need a notation that satisfies both PhpStorm and PHPStan level 9: PhpStorm reports array
# types without key type ("mixed[]", "array<mixed>", "array<mixed, mixed>", "iterable<mixed>") as replaceable with
# "array", PHPStan needs the value type. Array keys are always int or string. So
# write "@param array $x" together with "@phpstan-param array<string, mixed> $x" (or "array<int, mixed>", or a more
# precise type).
#
# Exceptions that are caught without using them are caught without variable (PHP 8: "catch (Exception)"), PhpStorm
# reports the variable as unused.
#
# Null checks before a method call are written with the nullsafe operator (PHP 8: "$x?->get()" instead of
# "$x !== null ? $x->get() : null"), PhpStorm reports the ternary as replaceable.
#
# HTML elements of templates have no attribute "price" (PhpStorm: "Attribute price is not allowed here"), Magento's
# templates had it for scripts that no longer read it; the value is written as "data-price".
#
# JavaScript widget options that default to an empty object declare the properties that are read from them,
# PhpStorm reports them as unresolved otherwise. This applies also to options that a parent widget of Magento declares
# as empty object (for example "jsonConfig" of the swatch renderer): properties read from widget options have to be
# declared somewhere in the JavaScript of the module or of Magento (MAGENTO_ROOT, or the vendor folder of the module
# in the development environment; without Magento this part is skipped).
#
# JavaScript widgets are returned as the value of "$.widget()", which returns the constructor, not read from the
# namespace that "$.widget()" creates at runtime ("$.infrangible.x"); PhpStorm reports the namespace as unresolved.
#
# JavaScript regular expressions have no escapes that change nothing ("\]" outside a character class), PhpStorm
# reports "Redundant character escape".
#
# JavaScript variables are declared with "const" or "let" instead of "var" (ES6, supported by all browsers of Magento
# 2.4), PhpStorm reports "var". Only the JavaScript files of the module itself are checked (with the copyright header
# of Andreas Knollmann), not bundled libraries like select2.js. The variable "config" of requirejs-config.js may be a
# "const": Magento wraps each file in a function before it reads the variable.
#
# Methods that return nothing declare "@return void" in their docblock; PhpStorm reports a docblock with another return
# type (for example "@return mixed") as "Missing 'return' statement". PHPStan does not, when the method has no native
# return type.
#
# Classes that are imported with "use" are written with their short name; PhpStorm reports "\\RuntimeException" after
# "use RuntimeException;" as "Qualifier is unnecessary and can be removed". Classes that are not imported are imported
# instead of written with their fully qualified name, also in docblocks ("Qualifier can be replaced with an import"),
# unless the short name is taken by another import or the class itself.
#
# Every module requires infrangible/m2-foundation in its composer.json, the module that presents Infrangible in the
# Magento admin, also when the code of the module does not use it. m2-foundation itself is the exception.
#
# Blocks and templates escape with Magento's escaper ("$this->_escaper->escapeHtml()" in blocks, "$escaper->escapeHtml()"
# in templates); the escape methods of the blocks are deprecated since Magento 2.4. tools/check-deprecations.sh finds
# them in classes too, but in templates only if "$block" has a declared type.
#
# Parameters of "@method" tags have no generic types with a comma ("array<string, mixed> $x"): PhpStorm splits the
# parameter list at the comma and reports "Expected: variable". They are written as "array $x". Return types of
# "@method" tags may be generic ("array<string, mixed>"), but not nested with a comma inside
# ("array<int, array<string, mixed>>"): PhpStorm misreads the method name and reports "Method with same name already
# defined in this class". They are written as "array".
#
# HTML elements "<html>" have a "lang" attribute, also in strings of PHP code like tests; PhpStorm treats such strings
# as HTML and reports "Missing required 'lang' attribute".
#
# Templates call no methods of the blocks of the module (the type of "$block") that declare exceptions in their
# docblock: a template cannot catch them, PhpStorm reports "Unhandled exception", and PHPStan does not analyze
# templates.
#
# The JavaScript of the module has no duplicated fragments of 6 or more lines (without empty lines and lines with only
# brackets); PhpStorm reports them as "Duplicated code fragment", PHPCPD checks only PHP.
#
# Usage: tools/check-code-conventions.sh <module directory>

set -u

moduleDir="${1:?Usage: $0 <module directory>}"

cd "${moduleDir}" || exit 1

# the PHPStan rules (src) and the shared PHP files of the modules (bootstrap and configuration files in the root
# directory) are in the package infrangible/phpstan-magento (composer type phpstan-extension), which runs this script
# for itself as well; modules check only their own code
if [[ $(python3 -c 'import json; print(json.load(open("composer.json")).get("type", ""))') == "phpstan-extension" ]]; then
  RULES_DIR="$(pwd)/src"
  SHARED_DIR="$(pwd)"
else
  RULES_DIR=""
  SHARED_DIR=""
fi
export RULES_DIR SHARED_DIR

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
check 'iterable<mixed>' "Use 'iterable<int|string, mixed>' (or a more precise type) instead of 'iterable<mixed>'"
check 'array<mixed\s*,' "Use 'array<int|string, mixed>' (or a more precise key type) instead of 'array<mixed, ...>'"
check '@method\s[^(]*\([^)]*<[^>)]*,' \
  "Write parameters of '@method' tags without generic types with a comma ('array \$x'), PhpStorm expects a variable after the comma"
check '@method\s+[^ (]*<[^ (]*,\s*[^ (]*<' \
  "Write nested generic return types of '@method' tags as 'array', PhpStorm misreads the method name"
check '<[^>]*\sprice="|^\s+price="' \
  "Write the price of HTML elements as 'data-price', PhpStorm reports the attribute 'price' as not allowed"
# shellcheck disable=SC2016 # the pattern contains $, not a variable
check '\$(this|block)->escape(Html|HtmlAttr|Js|Css|Url|XssInUrl|Quote|JsQuote)\(' \
  "Escape with Magento's escaper (\$this->_escaper in blocks, \$escaper in templates), the escape methods of blocks are deprecated"

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

# JavaScript widget options whose default is an empty object "{}" and whose properties are read with a dot
# (PhpStorm: "Unresolved variable"); declare the properties in the default ("config: {allowHideProductIds: {}}")
jsOption=$(python3 - <<'PYTHON'
import pathlib, re

for path in sorted(pathlib.Path('src').rglob('*.js')):
    source = path.read_text(encoding='utf-8', errors='replace')
    if 'Andreas Knollmann' not in source[:1000]:
        continue
    empty = set(re.findall(r'^\s*(\w+):\s*\{\s*\},?\s*$', source, re.M))
    for number, line in enumerate(source.splitlines(), 1):
        for name, prop in re.findall(r'\boptions\.(\w+)\.(\w+)', line.split('//', 1)[0]):
            if name in empty:
                print(f'{path}:{number}: options.{name}.{prop} in {line.strip()}')
PYTHON
)
# properties of widget options that no JavaScript of the module or of Magento declares (PhpStorm: "Unresolved
# variable"), for example of options that a parent widget of Magento declares as empty object
jsUndeclared=$(python3 - <<'PYTHON'
import os, pathlib, re

roots = [pathlib.Path(os.environ.get('MAGENTO_ROOT', '')), pathlib.Path('.')]
magento = next((root for root in roots if str(root) and (root / 'vendor' / 'magento').is_dir()), None)

own = [path for path in sorted(pathlib.Path('src').rglob('*.js'))
       if 'Andreas Knollmann' in path.read_text(encoding='utf-8', errors='replace')[:1000]]
reads = []
for path in own:
    for number, line in enumerate(path.read_text(encoding='utf-8', errors='replace').splitlines(), 1):
        for name, prop in re.findall(r'\boptions\.(\w+)\.(\w+)', line.split('//', 1)[0]):
            reads.append((path, number, name, prop, line.strip()))

if magento is not None and reads:
    declaration = re.compile(r'(?:^|[{,\s])[\'"]?(\w+)[\'"]?\s*:|\.(\w+)\s*=[^=]')
    declared = set()
    files = own + list((magento / 'vendor' / 'magento').glob('*/view/*/web/**/*.js')) + \
        list((magento / 'vendor' / 'magento' / 'magento2-base' / 'lib' / 'web').glob('**/*.js'))
    for path in files:
        try:
            source = path.read_text(encoding='utf-8', errors='replace')
        except OSError:
            continue
        for match in declaration.finditer(source):
            declared.add(match.group(1) or match.group(2))
    for path, number, name, prop, line in reads:
        if prop not in declared:
            print(f'{path}:{number}: options.{name}.{prop} in {line}')
PYTHON
)
if [[ -n "${jsUndeclared}" ]]; then
  echo "${jsUndeclared}"
  message="Declare the properties that are read from JavaScript widget options in the options of the widget, PhpStorm reports them as unresolved otherwise"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

if [[ -n "${jsOption}" ]]; then
  echo "${jsOption}"
  message="Declare the properties of JavaScript widget options in their default instead of an empty object '{}'"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# templates that call methods of blocks of the module that declare exceptions (PhpStorm: "Unhandled exception")
templateThrows=$(python3 - <<'PYTHON'
import json, pathlib, re

autoload = json.load(open('composer.json')).get('autoload', {}).get('psr-4', {})

def class_file(class_name):
    for prefix, directory in autoload.items():
        if class_name.startswith(prefix):
            path = pathlib.Path(directory) / (class_name[len(prefix):].replace('\\', '/') + '.php')
            return path if path.is_file() else None
    return None

throwing = {}

def throwing_methods(path):
    if path not in throwing:
        source = path.read_text(encoding='utf-8', errors='replace')
        throwing[path] = {
            match.group(2).lower()
            for match in re.finditer(r'/\*\*((?:(?!\*/).)*?)\*/\s*(?:(?:public|static|final)\s+)*function\s+(\w+)', source, re.S)
            if re.search(r'@throws\s', match.group(1))
        }
    return throwing[path]

for template in sorted(pathlib.Path('src').rglob('*.phtml')):
    source = template.read_text(encoding='utf-8', errors='replace')
    block_type = re.search(r'@var\s+\\?([\w\\]+)\s+\$block\b', source)
    if not block_type:
        continue
    class_name = block_type.group(1)
    if '\\' not in class_name:
        imported = re.search(r'^use\s+([\w\\]+\\' + re.escape(class_name) + r')\s*;', source, re.M)
        imported_as = re.search(r'^use\s+([\w\\]+)\s+as\s+' + re.escape(class_name) + r'\s*;', source, re.M)
        class_name = imported.group(1) if imported else imported_as.group(1) if imported_as else class_name
    path = class_file(class_name)
    if path is None:
        continue
    methods = throwing_methods(path)
    for number, line in enumerate(source.splitlines(), 1):
        for call in re.finditer(r'\$block->(\w+)\s*\(', line):
            if call.group(1).lower() in methods:
                print(f'{template}:{number}: {call.group(1)}() of {path} declares exceptions')
PYTHON
)
if [[ -n "${templateThrows}" ]]; then
  echo "${templateThrows}"
  message="Templates cannot handle exceptions: let the methods of the block return a default instead of throwing, PhpStorm reports 'Unhandled exception'"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# duplicated fragments in the JavaScript of the module (PhpStorm: "Duplicated code fragment")
jsDuplicates=$(python3 - <<'PYTHON'
import pathlib, re

minimum = 6
fragments = {}
for path in sorted(pathlib.Path('src').rglob('*.js')):
    source = path.read_text(encoding='utf-8', errors='replace')
    if 'Andreas Knollmann' not in source[:1000]:
        continue
    lines = []
    for number, line in enumerate(source.splitlines(), 1):
        code = re.sub(r'\s+', ' ', line.split('//', 1)[0]).strip()
        if code and not re.fullmatch(r'[\[\](){};,\s]*', code) and not code.startswith(('*', '/*')):
            lines.append((number, code))
    for index in range(len(lines) - minimum + 1):
        key = tuple(code for number, code in lines[index:index + minimum])
        fragments.setdefault(key, []).append((path, lines[index][0]))

reported = set()
for key, places in fragments.items():
    if len(places) > 1:
        # report each pair of places once, at the start of the first window
        first, second = places[0], places[1]
        if (first[0], second[0], first[1] - 1, second[1] - 1) in reported or \
                any((first[0], second[0]) == (a, b) and 0 < first[1] - x <= 30 and 0 < second[1] - y <= 30
                    for a, b, x, y in reported):
            reported.add((first[0], second[0], first[1], second[1]))
            continue
        reported.add((first[0], second[0], first[1], second[1]))
        print(f'{first[0]}:{first[1]} and {second[0]}:{second[1]}: duplicated fragment, starting with "{key[0]}"')
PYTHON
)
if [[ -n "${jsDuplicates}" ]]; then
  echo "${jsDuplicates}"
  message="Move duplicated JavaScript into a function or a method of the widget, PhpStorm reports 'Duplicated code fragment'"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# JavaScript widgets read from the namespace "infrangible" that only "$.widget()" creates at runtime (PhpStorm:
# "Unresolved variable infrangible")
jsNamespace=$(python3 - <<'PYTHON'
import pathlib, re

pattern = re.compile(r'\$\.infrangible\b')
for path in sorted(pathlib.Path('src').rglob('*.js')):
    source = path.read_text(encoding='utf-8', errors='replace')
    if 'Andreas Knollmann' not in source[:1000]:
        continue
    for number, line in enumerate(source.splitlines(), 1):
        code = line.split('//', 1)[0]
        if code.lstrip().startswith(('*', '/*')):
            continue
        if pattern.search(code):
            print(f'{path}:{number}: {line.strip()}')
PYTHON
)
if [[ -n "${jsNamespace}" ]]; then
  echo "${jsNamespace}"
  message="Return the widget as the value of \$.widget() instead of reading \$.infrangible, PhpStorm reports the namespace as unresolved"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# JavaScript regular expressions with escapes that change nothing (PhpStorm: "Redundant character escape"): outside a
# character class "\]", "\}" and punctuation without meaning, inside one also ".", "*", "+", "?", "(", ")", "{", "}",
# "|" and "$"
jsEscape=$(python3 - <<'PYTHON'
import pathlib, re

start = re.compile(r'(?:^|[(,=:\[!&|?{};]|\breturn|\btypeof)\s*/(?![/*])')
plain = set(']}"\':=!<>,#@%&~`')
plainInClass = plain | set('.*+?(){}|$')
for path in sorted(pathlib.Path('src').rglob('*.js')):
    source = path.read_text(encoding='utf-8', errors='replace')
    if 'Andreas Knollmann' not in source[:1000]:
        continue
    for number, line in enumerate(source.splitlines(), 1):
        if line.lstrip().startswith(('//', '*', '/*')):
            continue
        for match in start.finditer(line):
            index = match.end()
            inClass = False
            redundant = []
            while index < len(line):
                char = line[index]
                if char == '\\' and index + 1 < len(line):
                    escaped = line[index + 1]
                    if escaped in (plainInClass if inClass else plain) and not (inClass and escaped == ']'):
                        redundant.append('\\' + escaped)
                    index += 2
                    continue
                if char == '[' and not inClass:
                    inClass = True
                elif char == ']' and inClass:
                    inClass = False
                elif char == '/' and not inClass:
                    break
                index += 1
            if redundant and index < len(line):
                print(f'{path}:{number}: {" ".join(redundant)} in {line.strip()}')
PYTHON
)
if [[ -n "${jsEscape}" ]]; then
  echo "${jsEscape}"
  message="Remove escapes that change nothing from JavaScript regular expressions, for example '\\]' outside a character class"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# methods with a return type in their docblock that return nothing
missingReturn=$(python3 - <<'PYTHON'
import pathlib, re

pattern = re.compile(
    r'@return\s+([^\s*]+)(?:(?!\*/).)*?\*/\s*'
    r'((?:(?:abstract|public|protected|private|static|final)\s+)*)function\s+&?(\w+)\s*'
    r'\((?:[^()]|\([^()]*\))*\)\s*(?::\s*[^{;/]+)?\s*(?://[^\n]*\n\s*)?([{;])',
    re.S
)
for path in sorted(pathlib.Path('src').rglob('*.php')):
    source = path.read_text(encoding='utf-8', errors='replace')
    for match in pattern.finditer(source):
        if match.group(4) == ';' or match.group(1) in ('void', 'never'):
            continue
        end = match.end()
        depth = 1
        while depth and end < len(source):
            depth += (source[end] == '{') - (source[end] == '}')
            end += 1
        if not re.search(r'\b(return|throw|yield)\b', source[match.end():end]):
            line = source.count('\n', 0, match.start()) + 1
            print(f'{path}:{line}: {match.group(3)}() @return {match.group(1)}')
PYTHON
)
if [[ -n "${missingReturn}" ]]; then
  echo "${missingReturn}"
  message="Methods that return nothing declare '@return void'"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# imports that are used only in the text of comments (PhpStorm: "Import ... is never used"); PhpStorm counts code and
# docblock tags ("@param Export $x", "@see Export::getProductsData()"), not class names in the description
unusedImport=$(python3 - <<'PYTHON'
import os, pathlib, re

for path in sorted(set(list(pathlib.Path('src').rglob('*.php')) + [path.relative_to(pathlib.Path.cwd()) for path in
                       (sorted(pathlib.Path(os.environ['RULES_DIR']).glob('*.php')) if os.environ['RULES_DIR'] else []) + (sorted(pathlib.Path(os.environ['SHARED_DIR']).glob('*.php')) if os.environ['SHARED_DIR'] else [])])):
    source = path.read_text(encoding='utf-8', errors='replace')
    lines = source.splitlines()
    imports = []
    for number, line in enumerate(lines, 1):
        match = re.match(r'use\s+(?!function\s|const\s)\\?([\w\\]+)(?:\s+as\s+(\w+))?\s*;', line)
        if match:
            imports.append((number, match.group(2) or match.group(1).split('\\')[-1], line))
    if not imports:
        continue
    used = set()
    for line in lines:
        stripped = line.strip()
        if re.match(r'use\s', stripped) and not line.startswith(' '):
            continue
        if re.match(r'(\*|/\*\*?)', stripped):
            text = ' '.join(re.findall(r'(@[\w-]+.*|\{@[^}]*\})', stripped))
        else:
            text = stripped
        used.update(re.findall(r'(?<![\w\\$>])([A-Za-z_]\w*)', text))
    for number, name, line in imports:
        if name not in used:
            print(f'{path}:{number}: {line.strip()}')
PYTHON
)
if [[ -n "${unusedImport}" ]]; then
  echo "${unusedImport}"
  message="Remove unused imports, or reference the class in a docblock tag ('@see Export::getProductsData()') instead of the description"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# imported classes that are written with their fully qualified name
qualifiedImport=$(python3 - <<'PYTHON'
import os, pathlib, re

for path in sorted(set(list(pathlib.Path('src').rglob('*.php')) + [path.relative_to(pathlib.Path.cwd()) for path in
                       (sorted(pathlib.Path(os.environ['RULES_DIR']).glob('*.php')) if os.environ['RULES_DIR'] else []) + (sorted(pathlib.Path(os.environ['SHARED_DIR']).glob('*.php')) if os.environ['SHARED_DIR'] else [])])):
    source = path.read_text(encoding='utf-8', errors='replace')
    imports = {}
    for match in re.finditer(r'^use\s+([\w\\]+)(?:\s+as\s+(\w+))?\s*;', source, re.M):
        imports[match.group(1).lstrip('\\').lower()] = True
    for number, line in enumerate(source.splitlines(), 1):
        code = line.split('//', 1)[0]
        if re.match(r'\s*(use\s|namespace\s|\*|/\*)', code):
            continue
        for match in re.finditer(r'(?<![\w\\$\'"])\\([A-Za-z_][\w\\]*)', code):
            if match.group(1).lower() in imports:
                print(f'{path}:{number}: {line.strip()}')
PYTHON
)
if [[ -n "${qualifiedImport}" ]]; then
  echo "${qualifiedImport}"
  message="Use the short name of imported classes: 'RuntimeException' instead of '\\RuntimeException' after 'use RuntimeException;'"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# fully qualified class names that could be imported (PhpStorm: "Qualifier can be replaced with an import"), in code
# and docblocks; allowed if the short name is already taken (an import of another class, the class itself, a class of
# the module in the same namespace) or with
# "@noinspection PhpFullyQualifiedNameUsageInspection" (or ALL) on the line, the line before, the method or the file
# (deprecated Magento classes)
qualifiedName=$(python3 - <<'PYTHON'
import os, pathlib, re

# in the package of the PHPStan rules also its shared PHP files in the root directory
sharedPaths = [path.relative_to(pathlib.Path.cwd()) for path in (sorted(pathlib.Path(os.environ['SHARED_DIR']).glob('*.php')) if os.environ['SHARED_DIR'] else [])]
paths = sorted(list(pathlib.Path('src').rglob('*.php')) + list(pathlib.Path('src').rglob('*.phtml'))) + sharedPaths

# classes of the module by namespace: their short names are taken in files of the same namespace
namespaceClasses = {}
for path in paths:
    source = path.read_text(encoding='utf-8', errors='replace')
    namespace = re.search(r'^namespace\s+([\w\\]+)\s*;', source, re.M)
    if namespace:
        for match in re.finditer(r'^\s*(?:abstract\s+|final\s+|readonly\s+)*(?:class|interface|trait|enum)\s+(\w+)', source, re.M):
            namespaceClasses.setdefault(namespace.group(1).lower(), set()).add(match.group(1).lower())

for path in paths:
    source = path.read_text(encoding='utf-8', errors='replace')
    if re.search(r'@noinspection[^\n]*\b(PhpFullyQualifiedNameUsageInspection|ALL)\b', source.split('\n', 1)[0]):
        continue
    # lines of methods whose PHPDoc suppresses the inspection, from the PHPDoc to the end of the method
    suppressedLines = set()
    for match in re.finditer(r'/\*\*(?:(?!\*/).)*?@noinspection[^\n]*?\b(?:PhpFullyQualifiedNameUsageInspection|ALL)\b.*?\*/\s*'
                             r'(?:(?:public|protected|private|static|final|abstract)\s+)*function\b[^{;]*', source, re.S):
        end = match.end()
        if end < len(source) and source[end] == '{':
            depth = 0
            for position in range(end, len(source)):
                if source[position] == '{':
                    depth += 1
                elif source[position] == '}':
                    depth -= 1
                    if depth == 0:
                        end = position
                        break
        suppressedLines.update(range(source.count('\n', 0, match.start()) + 1, source.count('\n', 0, end) + 2))
    taken = {}
    for match in re.finditer(r'^use\s+\\?([\w\\]+)(?:\s+as\s+(\w+))?\s*;', source, re.M):
        name = match.group(1)
        taken[(match.group(2) or name.rsplit('\\', 1)[-1]).lower()] = name.lower()
    namespace = re.search(r'^namespace\s+([\w\\]+)\s*;', source, re.M)
    for match in re.finditer(r'^\s*(?:abstract\s+|final\s+|readonly\s+)*(?:class|interface|trait|enum)\s+(\w+)', source, re.M):
        taken.setdefault(match.group(1).lower(), f'{namespace.group(1) if namespace else ""}\\{match.group(1)}'.lower())
    if namespace:
        for short in namespaceClasses.get(namespace.group(1).lower(), set()):
            taken.setdefault(short, f'{namespace.group(1)}\\{short}'.lower())
    lines = source.splitlines()
    for number, line in enumerate(lines, 1):
        if re.match(r'\s*(use|namespace)\s', line) or number in suppressedLines:
            continue
        if 'PhpFullyQualifiedNameUsageInspection' in line or (
                number > 1 and 'PhpFullyQualifiedNameUsageInspection' in lines[number - 2]):
            continue
        code = re.sub(r"'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"", "''", line)
        if not re.match(r'\s*(\*|/\*\*)', line):
            code = code.split('//', 1)[0]
        # in the shared files without namespace, also global classes: their leading backslash is not needed
        pattern = r'(?<![\w\\$])\\([A-Za-z_]\w*(?:\\[A-Za-z_]\w*)+)'
        if path in sharedPaths and not namespace:
            pattern = r'(?<![\w\\$])\\([A-Z]\w*(?:\\[A-Za-z_]\w*)*)(?!\s*\()'
        for match in re.finditer(pattern, code):
            name = match.group(1)
            short = name.rsplit('\\', 1)[-1].lower()
            if short in taken and taken[short] != name.lower():
                continue
            print(f'{path}:{number}: {line.strip()}')
PYTHON
)
if [[ -n "${qualifiedName}" ]]; then
  echo "${qualifiedName}"
  message="Import classes with 'use' instead of writing their fully qualified name (also in docblocks), unless the short name is taken"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# admin controllers without their own ACL resource
adminAcl=$(python3 - <<'PYTHON'
import pathlib, re

# base classes that only allow the resource Magento_Backend::admin, which every admin user has
OPEN_BASES = {
    'magento\\backend\\app\\action',
    'magento\\backend\\app\\abstractaction',
    'infrangible\\core\\controller\\adminhtml\\ajax',
    'infrangible\\core\\controller\\adminhtml\\json',
}

classes = {}
for path in sorted(pathlib.Path('src').rglob('*.php')):
    if 'Test' in path.parts:
        continue
    source = path.read_text(encoding='utf-8', errors='replace')
    namespace = re.search(r'^namespace\s+([\w\\]+)\s*;', source, re.M)
    declaration = re.search(r'^(abstract\s+|final\s+)?class\s+(\w+)(?:\s+extends\s+([\w\\]+))?', source, re.M)
    if not namespace or not declaration:
        continue
    imports = {}
    for match in re.finditer(r'^use\s+([\w\\]+)(?:\s+as\s+(\w+))?\s*;', source, re.M):
        full = match.group(1).lstrip('\\')
        imports[(match.group(2) or full.rsplit('\\', 1)[-1]).lower()] = full
    parent = declaration.group(3)
    if parent:
        if parent.startswith('\\'):
            parent = parent[1:]
        elif parent.split('\\', 1)[0].lower() in imports:
            first, _, rest = parent.partition('\\')
            parent = imports[first.lower()] + ('\\' + rest if rest else '')
        else:
            parent = namespace.group(1) + '\\' + parent
    name = namespace.group(1) + '\\' + declaration.group(2)
    classes[name.lower()] = {
        'path': path,
        'abstract': (declaration.group(1) or '').strip() == 'abstract',
        'parent': parent.lower() if parent else None,
        'acl': bool(re.search(r'const\s+ADMIN_RESOURCE\b|function\s+_isAllowed\s*\(', source)),
    }

def open_acl(name):
    """True if the class gets its ACL resource only from a base class that allows every admin user."""
    seen = set()
    while name in classes and name not in seen:
        seen.add(name)
        if classes[name]['acl']:
            return False
        name = classes[name]['parent']
    return name in OPEN_BASES

for name, info in classes.items():
    if not info['abstract'] and 'controller' in name.split('\\') and open_acl(name):
        print(f"{info['path']}")
PYTHON
)
if [[ -n "${adminAcl}" ]]; then
  echo "${adminAcl}"
  message="Admin controllers declare their ACL resource (const ADMIN_RESOURCE, or _isAllowed()); without it, every admin user may call them. Use 'Magento_Backend::admin' only on purpose."
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# texts without translation
translations=$(python3 - <<'PYTHON'
import csv, pathlib, re
import xml.etree.ElementTree as ElementTree

OWN = ['cs_CZ', 'da_DK', 'de_DE', 'es_ES', 'fi_FI', 'fr_FR', 'it_IT', 'nb_NO', 'nl_NL', 'nn_NO', 'pl_PL', 'pt_BR',
       'pt_PT', 'sv_SE', 'uk_UA']
COPIES = {'de_AT': 'de_DE', 'de_CH': 'de_DE', 'de_LU': 'de_DE', 'fr_BE': 'fr_FR', 'fr_CH': 'fr_FR', 'fr_LU': 'fr_FR',
          'nl_BE': 'nl_NL', 'it_CH': 'it_IT', 'sv_FI': 'sv_SE'}
LITERAL = r"""(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")"""

texts = set()
for path in pathlib.Path('src').rglob('*'):
    if not path.is_file() or 'Test' in path.parts or 'i18n' in path.parts:
        continue
    source = path.read_text(encoding='utf-8', errors='replace')
    if path.suffix in ('.php', '.phtml'):
        pattern = r'(?<![\w>$])__\(\s*' + LITERAL
    elif path.suffix in ('.js', '.html'):
        if 'Andreas Knollmann' not in source:
            continue
        pattern = r'\$t\(\s*' + LITERAL
    elif path.suffix == '.xml':
        try:
            root = ElementTree.fromstring(source)
        except ElementTree.ParseError:
            continue
        for element in root.iter():
            names = element.get('translate')
            if not names:
                continue
            if names == 'true':
                if element.text and element.text.strip():
                    texts.add(element.text.strip())
                continue
            for name in names.split():
                value = element.get(name)
                if value is None:
                    child = element.find(name)
                    value = child.text if child is not None else None
                if value and value.strip():
                    texts.add(value.strip())
        continue
    else:
        continue
    for match in re.finditer(pattern, source):
        text = match.group(1) if match.group(1) is not None else match.group(2)
        texts.add(re.sub(r'\\(.)', r'\1', text))

if texts:
    i18n = pathlib.Path('src/i18n')

    def read(locale):
        with open(i18n / f'{locale}.csv', encoding='utf-8', newline='') as file:
            return {row[0]: row[1] for row in csv.reader(file, skipinitialspace=True) if len(row) >= 2}

    for locale in OWN:
        if not (i18n / f'{locale}.csv').is_file():
            print(f'src/i18n/{locale}.csv is missing')
            continue
        for text in sorted(texts - read(locale).keys()):
            print(f'src/i18n/{locale}.csv: no translation of "{text}"')
    for locale, base in COPIES.items():
        copy, original = i18n / f'{locale}.csv', i18n / f'{base}.csv'
        if not copy.is_file():
            print(f'src/i18n/{locale}.csv is missing')
        elif original.is_file() and copy.read_bytes() != original.read_bytes():
            print(f'src/i18n/{locale}.csv is not a copy of {base}.csv')
PYTHON
)
if [[ -n "${translations}" ]]; then
  echo "${translations}"
  message="Every text of the module is translated into the 15 languages of src/i18n; the 9 country variants are copies (de_AT, de_CH, de_LU of de_DE, fr_BE, fr_CH, fr_LU of fr_FR, nl_BE of nl_NL, it_CH of it_IT, sv_FI of sv_SE)"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# PHP extensions in the PHP files outside of src (composer-require-checker checks src): PhpStorm reports "'ext-…' is
# missing in composer.json". The shared files of the package infrangible/phpstan-magento (its rules and the files in its
# root directory) only run in the PHPStan of Magento, whose framework requires the extensions: they suppress the
# inspection with a reason; other files of a module need the extension in composer.json
if ! python3 - . <<'PY'
import json, os, pathlib, re, sys
extensions = {
    'dom': r'\bDOM(?:Document|Element|Node|XPath|Attr|Text)\b|\bdom_import_simplexml\s*\(',
    'simplexml': r'\bSimpleXMLElement\b|\bsimplexml_\w+\s*\(',
    'libxml': r'\blibxml_\w+\s*\(',
    'xmlreader': r'\bXMLReader\b',
    'xmlwriter': r'\bXMLWriter\b',
    'mbstring': r'\bmb_\w+\s*\(',
    'iconv': r'\biconv\w*\s*\(',
    'ctype': r'\bctype_\w+\s*\(',
    'curl': r'\bcurl_\w+\s*\(',
    'zlib': r'\bgz\w+\s*\(',
    'intl': r'\b(?:Collator|NumberFormatter|IntlDateFormatter|Normalizer|Transliterator)\b',
}
suppression = re.compile(r'@noinspection\s+PhpComposerExtensionStubsInspection\b')
module = pathlib.Path(sys.argv[1])
composer = json.loads((module / 'composer.json').read_text(encoding='utf-8'))
required = {name[4:].lower() for section in ('require', 'require-dev') for name in composer.get(section, {})
            if name.startswith('ext-')}
shared = [path for path in (sorted(pathlib.Path(os.environ['SHARED_DIR']).glob('*.php')) if os.environ['SHARED_DIR'] else []) + (sorted(pathlib.Path(os.environ['RULES_DIR']).glob('*.php')) if os.environ['RULES_DIR'] else []) if path.name != 'phpstorm-throws.php']
paths = [(path, True) for path in shared]
paths += [(path, False) for path in sorted(module.glob('*.php')) if not shared]
failed = False
for path, shared in paths:
    source = path.read_text(encoding='utf-8', errors='replace')
    code = re.sub(r'/\*.*?\*/|//[^\n]*|\'(?:\\.|[^\'\\])*\'', '', source, flags=re.S)
    used = [name for name, pattern in extensions.items() if re.search(pattern, code)]
    missing = [] if suppression.search(source) else [name for name in used if shared or name not in required]
    for name in missing:
        print(f'{path}: uses ext-{name}' + (' without the suppression' if shared else ', missing in composer.json'))
        failed = True
sys.exit(1 if failed else 0)
PY
then
  message="Require the PHP extensions in composer.json, or suppress PhpComposerExtensionStubsInspection with a reason in shared files"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# inline @var tags in the shared PHP files of infrangible/phpstan-magento (bootstrap and configuration files): PHPStan does
# not analyse them, and PhpStorm infers the types, also of the variables of required files ("@var tag specifies the type
# already inferred from source code")
if [[ -n "${SHARED_DIR}" ]] && grep -nP '^\s*/\*\*\s*@var\b' "${SHARED_DIR}"/*.php; then
  message="Remove inline @var tags from the shared PHP files, PhpStorm infers the types"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# variables of the shared PHP files of infrangible/phpstan-magento that the file does not define itself, for example the
# variables of a required file: PhpStorm reports them as "Undefined variable"
if ! python3 - <<'PY'
import os, pathlib, re, sys
failed = False
for path in (sorted(pathlib.Path(os.environ['SHARED_DIR']).glob('*.php')) if os.environ['SHARED_DIR'] else []):
    source = path.read_text(encoding='utf-8', errors='replace')
    code = re.sub(r'/\*.*?\*/|//[^\n]*|\'(?:\\.|[^\'\\])*\'', '', source, flags=re.S)
    defined = {'this', 'GLOBALS', '_SERVER', '_ENV', '_GET', '_POST'}
    defined |= set(re.findall(r'(?<![:>\w])\$(\w+)\s*(?:=(?!=)|\.=|\?\?=|\[[^\]]*\]\s*=)', code))
    defined |= set(re.findall(r'\bas\s+(?:\$\w+\s*=>\s*)?&?\$(\w+)', code))
    defined |= set(re.findall(r'\bas\s+\$(\w+)\s*=>', code))
    defined |= set(re.findall(r'catch\s*\([^)$]*\$(\w+)', code))
    defined |= set(re.findall(r'\bstatic\s+\$(\w+)', code))
    for parameters in re.findall(r'\b(?:function|fn)\s*&?\w*\s*\(([^)]*)\)', code):
        defined |= set(re.findall(r'\$(\w+)', parameters))
    for name in sorted(set(re.findall(r'(?<![:>\w$])\$(\w+)', code)) - defined):
        line = code[:code.index('$' + name)].count('\n') + 1
        print(f'{path}:{line}: ${name} is not defined in the file')
        failed = True
sys.exit(1 if failed else 0)
PY
then
  message="Define the variables of the shared PHP files in the file itself, PhpStorm does not see the variables of required files"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# checked exceptions in the shared PHP files of infrangible/phpstan-magento, which PHPStan does not analyse: calls of
# methods that the PHP stubs of PhpStorm declare with a checked exception (src/phpstorm-throws.php) on
# objects of the classes that the file creates, and their constructors, have to be declared in the throws tag of the
# documented function or closure around them ("PHPDoc comment doesn't contain all the necessary throws tags",
# "Unhandled exception"); catching them is not enough: PhpStorm did not apply the catch clauses in the closures of
# bootstrap.php (DOMException, ReflectionException), so these files avoid such calls
if ! python3 - <<'PY'
import os, pathlib, re, sys
if not os.environ['RULES_DIR']:
    sys.exit(0)
rules = pathlib.Path(os.environ['RULES_DIR'])
throws = (rules / 'phpstorm-throws.php').read_text(encoding='utf-8')
section = lambda name: re.search(r"'" + name + r"' => \[\n(.*?)\n    \]", throws, re.S).group(1)
methods = {key.replace('\\\\', '\\'): re.findall(r"'([^']+)'", values)
           for key, values in re.findall(r"'([^']+)' => \[([^\]]*)\]", section('methods'))}
parents = {key.replace('\\\\', '\\'): value.replace('\\\\', '\\')
           for key, value in re.findall(r"'([^']+)' => '([^']+)'", section('parents'))}

def block_end(code, start):
    depth = 0
    for position in range(start, len(code)):
        depth += {'{': 1, '}': -1}.get(code[position], 0)
        if depth == 0 and code[position] == '}':
            return position
    return len(code)

failed = False
for path in (sorted(pathlib.Path(os.environ['SHARED_DIR']).glob('*.php')) if os.environ['SHARED_DIR'] else []):
    source = path.read_text(encoding='utf-8', errors='replace')
    # comments and strings blanked out with the same length, docblocks kept apart
    code = re.sub(r'/\*.*?\*/|//[^\n]*|\'(?:\\.|[^\'\\])*\'|"(?:\\.|[^"\\])*"',
                  lambda m: re.sub(r'[^\n]', ' ', m.group(0)), source, flags=re.S)
    imports = {(alias or name.rsplit('\\', 1)[-1]).lower(): name.lower()
               for name, alias in re.findall(r'^use\s+([\w\\]+)(?:\s+as\s+(\w+))?\s*;', code, re.M)}
    classes = {imports.get(name.lower(), name.lower()) for name in re.findall(r'\bnew\s+\\?([\w\\]+)', code)}
    # documented functions and closures: body range and the exceptions of their throws tags
    documented = []
    for match in re.finditer(r'(/\*\*.*?\*/)\s*[^;{]*?\bfunction\b[^{;]*\{', source, re.S):
        tags = {imports.get(n.lower(), n.lower()).lstrip('\\').rsplit('\\', 1)[-1]
                for n in re.findall(r'@throws\s+\\?([\w\\]+)', match.group(1))}
        documented.append((match.end() - 1, block_end(code, match.end() - 1), tags))
    for match in re.finditer(r'->\s*(\w+)\s*\(|\bnew\s+\\?([\w\\]+)\s*\(', code):
        exceptions = set()
        if match.group(2):
            created = imports.get(match.group(2).lower(), match.group(2).lower())
            exceptions.update(methods.get(f'{created}::__construct', []))
        for name in classes if match.group(1) else []:
            seen = set()
            while name and name not in seen:
                exceptions.update(methods.get(f'{name}::{match.group(1).lower()}', []))
                seen.add(name)
                name = parents.get(name)
        position = match.start()
        for exception in sorted(exceptions):
            short = exception.rsplit('\\', 1)[-1]
            # outside of documented functions and closures, PhpStorm reports it as "Unhandled exception"
            inner = [d for d in documented if d[0] < position < d[1]]
            if inner and short in max(inner, key=lambda d: d[0])[2]:
                continue
            print(f'{path}:{code.count(chr(10), 0, position) + 1}: {match.group(1) or match.group(2)}() throws {exception}')
            failed = True
sys.exit(1 if failed else 0)
PY
then
  message="Avoid calls with checked exceptions in the shared PHP files, or declare them in the throws tag"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# docblocks of the PHPStan rules without all parameters
if ! python3 - <<'PY'
import os, pathlib, re, sys
failed = False
for path in (sorted(pathlib.Path(os.environ['RULES_DIR']).glob('*.php')) if os.environ['RULES_DIR'] else []):
    text = path.read_text(encoding='utf-8')
    pattern = (r'(/\*\*(?:(?!\*/).)*\*/)\s*(?:(?:public|protected|private|static|final|abstract)\s+)*'
               r'function\s+(\w+)\s*\(([^)]*)\)')
    for match in re.finditer(pattern, text, re.S):
        documented = re.findall(r'@(?:phpstan-)?param\s+.*?&?(?:\.\.\.)?\$(\w+)', match.group(1))
        missing = [name for name in re.findall(r'\$(\w+)', match.group(3)) if name not in documented]
        if missing:
            line = text[:match.start()].count('\n') + 1
            print(f'{path}:{line}: {match.group(2)}() does not document ' + ', '.join('$' + n for n in missing))
            failed = True
sys.exit(1 if failed else 0)
PY
then
  message="Document every parameter in the docblocks of the PHPStan rules"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# classes of the PHPStan rules that can be readonly
readonlyClasses=$(python3 - <<'PYTHON'
import os, pathlib, re

paths = (sorted(pathlib.Path(os.environ['RULES_DIR']).glob('*.php')) if os.environ['RULES_DIR'] else [])
for path in paths:
    source = path.read_text(encoding='utf-8', errors='replace')
    for match in re.finditer(r'^((?:(?:abstract|final|readonly)\s+)*)class\s+(\w+)([^{]*)\{', source, re.M):
        modifiers, name, declaration = match.groups()
        if 'readonly' in modifiers or re.search(r'\bextends\b', declaration):
            continue
        # the body of the class
        depth, end = 0, len(source)
        for position in range(match.end() - 1, len(source)):
            if source[position] == '{':
                depth += 1
            elif source[position] == '}':
                depth -= 1
                if depth == 0:
                    end = position
                    break
        body = source[match.end():end]
        properties = re.findall(r'^\s*((?:(?:public|protected|private|static|readonly)\s+)+)(?:\??[\w\\|]+\s+)?\$\w+', body, re.M)
        constructor = re.search(r'function\s+__construct\s*\((.*?)\)\s*\{', body, re.S)
        if constructor:
            properties += re.findall(r'((?:(?:public|protected|private|readonly)\s+)+)(?:\??[\w\\|]+\s+)?\$\w+', constructor.group(1))
        if properties and all('readonly' in p and 'static' not in p for p in properties):
            print(f'{path}:{source.count(chr(10), 0, match.start()) + 1}: class {name}')
PYTHON
)
if [[ -n "${readonlyClasses}" ]]; then
  echo "${readonlyClasses}"
  message="Declare classes whose properties are all readonly as 'readonly class' (PHP 8.2)"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# methods of the PHPStan rules that return a single rule error
if [[ -n "${RULES_DIR}" ]] && grep -nP 'function\s+\w+\s*\([^)]*\)\s*:\s*\??\\?(?:[\w\\]*\\)?(?:Identifier)?RuleError\b' "${RULES_DIR}"/*.php; then
  message="Return the rule errors of RuleErrorBuilder::build() in the array of processNode(), PhpStorm does not resolve its generic type"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# node classes of php-parser 4 that php-parser 5 deprecates or removes (Stmt\Throw_); the PHPStan rules run with both
# (PHPStan 1 and 2)
if [[ -n "${RULES_DIR}" ]] && grep -nP '^(?!\s*(\*|//)).*\b(Scalar\\(LNumber|DNumber|Encapsed|EncapsedStringPart)|Expr\\(ArrayItem|ClosureUse)|Stmt\\(DeclareDeclare|PropertyProperty|StaticVar|UseUse|Throw_))\b' \
  "${RULES_DIR}"/*.php; then
  message="Do not use node classes that php-parser 5 deprecates or removes, compare the node type (getType()) of both versions instead"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# docblock tags in running text
if grep -rnP --include='*.php' --include='*.phtml' '^\s*\*\s+[^@\s].*(?<![{\w])@(throws|param|return|var)\b' \
  src; then
  message="Write docblock tags only as tags: 'throws tag' instead of '@throws tag' in running text"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# html elements without lang attribute
if grep -rnP --include='*.php' --include='*.phtml' --include='*.html' '<html(?![^>]*\blang=)[\s>/]' src; then
  message="Add a lang attribute to <html>, for example <html lang=\"en\">"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# the module that presents Infrangible in the admin
name=$(python3 -c 'import json; print(json.load(open("composer.json")).get("name", ""))')
if [[ -z "${RULES_DIR}" ]] && [[ "${name}" != "infrangible/m2-foundation" ]] && ! python3 -c '
import json, sys
sys.exit(0 if "infrangible/m2-foundation" in json.load(open("composer.json")).get("require", {}) else 1)'; then
  message="Every module requires infrangible/m2-foundation in composer.json"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

exit "${failed}"
