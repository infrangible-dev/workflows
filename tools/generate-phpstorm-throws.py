#!/usr/bin/env python3
"""
Generates templates/magento-module/phpstan-rules/phpstorm-throws.php: the checked exceptions that the PHP stubs of
PhpStorm (https://github.com/JetBrains/phpstorm-stubs) declare in @throws tags of functions and methods, and the
functions whose declared result can be false or null (RedundantCastRule: PHPStan narrows for example base64_decode()
without $strict to string, for PhpStorm it is string|false, so a cast is not redundant).

PhpStorm requires these exceptions in the @throws tag of the calling method ("PHPDoc comment doesn't contain all the
necessary @throws tags"), PHPStan does not know them (for example DOMException of DOMDocument::saveXML()). The
extension PhpStormThrowTypeExtension adds them to the throw types of PHPStan, so that its check of missing @throws
tags reports them as well. Exceptions that are unchecked in PhpStorm and PHPStan (subclasses of Error, LogicException
and RuntimeException) are left out.

Usage: tools/generate-phpstorm-throws.py <directory of phpstorm-stubs>
"""

import pathlib
import re
import sys

UNCHECKED = {'error', 'logicexception', 'runtimeexception'}
TOKEN = re.compile(
    r'(?P<doc>/\*\*.*?\*/)'
    r'|(?P<comment>/\*.*?\*/|//[^\n]*|#(?!\[)[^\n]*)'
    r'|(?P<string>\'(?:\\.|[^\'\\])*\'|"(?:\\.|[^"\\])*")'
    r'|(?P<namespace>\bnamespace\s+([\w\\]+)\s*[;{])'
    r'|(?P<class>\b(?:class|interface|trait|enum)\s+(\w+)(?:\s+extends\s+([\w\\]+))?)'
    r'|(?P<function>\bfunction\s+&?\s*(\w+)\s*\()'
    r'|(?P<open>\{)|(?P<close>\})',
    re.S
)


def qualify(name: str, namespace: str, known: set[str]) -> str:
    """Returns the lower-case fully qualified name: in the namespace if known there, else global."""
    name = name.strip()

    if name.startswith('\\'):
        return name[1:].lower()

    if namespace and f'{namespace}\\{name}'.lower() in known:
        return f'{namespace}\\{name}'.lower()

    return name.lower()


def return_type(text: str, start: int) -> str:
    """Returns the native return type of the function whose parameter list starts at the position, or ''."""
    depth = 1
    position = start

    while position < len(text) and depth > 0:
        depth += {'(': 1, ')': -1}.get(text[position], 0)
        position += 1

    match = re.match(r'\s*:\s*([?\w|\\ ]+?)\s*[{;]', text[position:position + 200])

    return match.group(1).strip() if match else ''


def scan(files: list[pathlib.Path]):
    """Yields (kind, data) of class declarations and documented functions and methods of the stubs."""
    for path in files:
        text = path.read_text(encoding='utf-8', errors='replace')
        namespace = ''
        depth = 0
        classes = []  # (name, depth of its body)
        pending_class = None
        doc = None

        for match in TOKEN.finditer(text):
            kind = match.lastgroup

            if kind == 'doc':
                doc = match.group('doc')
            elif kind == 'namespace':
                namespace = match.group(5)
            elif kind == 'class':
                pending_class = (match.group(7), match.group(8))
                doc = None
            elif kind == 'function':
                name = match.group(10)
                owner = classes[-1][0] if classes and classes[-1][1] == depth else None

                yield 'function', (namespace, owner, name, doc or '', return_type(text, match.end()))

                doc = None
            elif kind == 'open':
                depth += 1

                if pending_class is not None:
                    full = f'{namespace}\\{pending_class[0]}' if namespace else pending_class[0]
                    classes.append((full, depth))

                    yield 'class', (namespace, full, pending_class[1])

                    pending_class = None
            elif kind == 'close':
                if classes and classes[-1][1] == depth:
                    classes.pop()

                depth -= 1


def main() -> None:
    stubs = pathlib.Path(sys.argv[1])
    files = sorted(p for p in stubs.rglob('*.php') if 'tests' not in p.parts and 'meta' not in p.parts)
    items = list(scan(files))

    classes = [data for kind, data in items if kind == 'class']
    known = {full.lower() for ns, full, parent in classes}
    parents = {full.lower(): qualify(parent, ns, known) if parent else None for ns, full, parent in classes}

    def checked(exception: str) -> bool:
        seen = set()

        while exception and exception not in seen:
            if exception in UNCHECKED:
                return False

            seen.add(exception)
            exception = parents.get(exception)

        return exception is None or exception not in UNCHECKED

    def exception_names(doc: str, namespace: str) -> list[str]:
        names = []

        for name in re.findall(r'@throws\s+([\\\w|]+)', doc):
            for part in name.split('|'):
                full = qualify(part, namespace, known)

                if full in known and full not in names and checked(full):
                    names.append(full)

        return names

    functions = {}
    methods = {}
    nullable_returns = []

    for kind, data in items:
        if kind != 'function':
            continue

        namespace, owner, name, doc, native = data

        # functions whose declared result can be false or null: casting it is not redundant for PhpStorm
        declared = native if native and native != 'mixed' else ' '.join(re.findall(r'@return\s+(\S+)', doc)[:1])

        if owner is None and re.search(r'(^|\|)(false|null)\b|^\?', declared.lower()):
            nullable_returns.append((f'{namespace}\\{name}' if namespace else name).lower())

        names = exception_names(doc, namespace)

        if not names:
            continue

        if owner is None:
            functions[(f'{namespace}\\{name}' if namespace else name).lower()] = names
        else:
            methods[f'{owner}::{name}'.lower()] = names

    def php_array(entries: dict[str, list[str]]) -> str:
        return ''.join(
            f"        '{key.replace(chr(92), chr(92) * 2)}' => [" +
            ', '.join(f"'{n.replace(chr(92), chr(92) * 2)}'" for n in value) + '],\n'
            for key, value in sorted(entries.items())
        )

    target = pathlib.Path(__file__).resolve().parent.parent / 'templates/magento-module/phpstan-rules/phpstorm-throws.php'
    target.write_text(
        "<?php\n\n"
        "/**\n"
        " * Checked exceptions in the @throws tags of the PHP stubs of PhpStorm, by lower-case function and\n"
        " * class::method. Generated by tools/generate-phpstorm-throws.py, do not edit.\n"
        " */\n\n"
        "return [\n"
        "    'functions' => [\n" + php_array(functions) + "    ],\n"
        "    'methods' => [\n" + php_array(methods) + "    ],\n"
        "    // functions whose declared result can be false or null, so that casting it is not redundant\n"
        "    'nullable_returns' => [\n" +
        ''.join(f"        '{n.replace(chr(92), chr(92) * 2)}',\n" for n in sorted(set(nullable_returns))) +
        "    ]\n"
        "];\n",
        encoding='utf-8'
    )

    print(f'{len(functions)} functions, {len(methods)} methods, {len(set(nullable_returns))} nullable results: {target}')


if __name__ == '__main__':
    main()
