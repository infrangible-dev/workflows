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
# HTML elements "<html>" have a "lang" attribute, also in strings of PHP code like tests; PhpStorm treats such strings
# as HTML and reports "Missing required 'lang' attribute".
#
# Usage: tools/check-code-conventions.sh <module directory>

set -u

moduleDir="${1:?Usage: $0 <module directory>}"

# the PHPStan rules are checked in the templates of the workflows, which tools/sync-module-config.sh copies into the
# modules: an older copy in a module must not fail its checks before the next synchronization
RULES_DIR="$(cd "$(dirname "$0")/../templates/magento-module/phpstan-rules" && pwd)"
export RULES_DIR

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
check 'iterable<mixed>' "Use 'iterable<int|string, mixed>' (or a more precise type) instead of 'iterable<mixed>'"
check 'array<mixed\s*,' "Use 'array<int|string, mixed>' (or a more precise key type) instead of 'array<mixed, ...>'"
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

# imported classes that are written with their fully qualified name
qualifiedImport=$(python3 - <<'PYTHON'
import os, pathlib, re

for path in sorted(list(pathlib.Path('src').rglob('*.php')) + list(pathlib.Path(os.environ['RULES_DIR']).glob('*.php'))):
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

# also the PHPStan rules copied from the workflows, which PhpStorm inspects as part of the module
paths = sorted(list(pathlib.Path('src').rglob('*.php')) + list(pathlib.Path('src').rglob('*.phtml')) +
               list(pathlib.Path(os.environ['RULES_DIR']).glob('*.php')))

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
        for match in re.finditer(r'(?<![\w\\$])\\([A-Za-z_]\w*(?:\\[A-Za-z_]\w*)+)', code):
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
# missing in composer.json". The shared files of templates/magento-module (checked there, not the copies in the modules,
# which may be older) only run in the PHPStan of Magento, whose framework requires the extensions: they suppress the
# inspection with a reason; other files of the module need the extension in composer.json
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
templates = pathlib.Path(os.environ['RULES_DIR']).parent
templateNames = {path.name for path in templates.glob('*.php')}
composer = json.loads((module / 'composer.json').read_text(encoding='utf-8'))
required = {name[4:].lower() for section in ('require', 'require-dev') for name in composer.get(section, {})
            if name.startswith('ext-')}
paths = [(path, True) for path in sorted(templates.glob('*.php')) + sorted(templates.glob('phpstan-rules/*.php'))
         if path.name != 'phpstorm-throws.php']
paths += [(path, False) for path in sorted(module.glob('*.php')) if path.name not in templateNames]
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

# inline @var tags in the shared PHP files of templates/magento-module (bootstrap files and configurations): PHPStan does
# not analyse them, and PhpStorm infers the types, also of the variables of required files ("@var tag specifies the type
# already inferred from source code")
if grep -nP '^\s*/\*\*\s*@var\b' "${RULES_DIR}"/../*.php; then
  message="Remove inline @var tags from the shared PHP files of templates/magento-module, PhpStorm infers the types"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# variables of the shared PHP files of templates/magento-module that the file does not define itself, for example the
# variables of a required file: PhpStorm reports them as "Undefined variable"
if ! python3 - <<'PY'
import os, pathlib, re, sys
failed = False
for path in sorted(pathlib.Path(os.environ['RULES_DIR']).parent.glob('*.php')):
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

# docblocks of the PHPStan rules without all parameters
if ! python3 - <<'PY'
import os, pathlib, re, sys
failed = False
for path in sorted(pathlib.Path(os.environ['RULES_DIR']).glob('*.php')):
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
  message="Document every parameter in the docblocks of phpstan-rules (in the workflows repository)"
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

paths = sorted(pathlib.Path(os.environ['RULES_DIR']).glob('*.php'))
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
if grep -nP 'function\s+\w+\s*\([^)]*\)\s*:\s*\??\\?(?:[\w\\]*\\)?(?:Identifier)?RuleError\b' "${RULES_DIR}"/*.php; then
  message="Return the rule errors of RuleErrorBuilder::build() in the array of processNode(), PhpStorm does not resolve its generic type"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# node classes of php-parser 4 that php-parser 5 deprecates; the PHPStan rules run with both (PHPStan 1 and 2)
if grep -nP '^(?!\s*(\*|//)).*\b(Scalar\\(LNumber|DNumber|Encapsed|EncapsedStringPart)|Expr\\(ArrayItem|ClosureUse)|Stmt\\(DeclareDeclare|PropertyProperty|StaticVar|UseUse))\b' \
  "${RULES_DIR}"/*.php; then
  message="Do not use node classes that php-parser 5 deprecates, compare the node type (getType()) of both versions instead"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  failed=1
fi

# docblock tags in running text
if grep -rnP --include='*.php' --include='*.phtml' '^\s*\*\s+[^@\s].*(?<![{\w])@(throws|param|return|var)\b' \
  src "${RULES_DIR}"; then
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
if [[ "${name}" != "infrangible/m2-foundation" ]] && ! python3 -c '
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
