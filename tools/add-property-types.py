#!/usr/bin/env python3
"""Adds native type declarations to class properties of a module, taken from their @var docblocks.

    /** @var PageFactory */            /** @var PageFactory */
    protected $resultPageFactory;  ->  protected PageFactory $resultPageFactory;

The docblock stays, because the Magento coding standard requires it and it can be more precise than the native type
(for example array shapes). Properties are only changed when the docblock type maps to a native type without doubt:

    Class                       -> the same
    Class&MockObject            -> MockObject (test doubles; the docblock keeps the intersection, because the Magento
    Class&Stub                  -> Stub        coding standard does not recognize docblocks of intersection types)
    Class|null                  -> ?Class
    string, int, float, bool    -> the same
    array, string[], array<..>  -> array (also with |null -> ?array)

Everything else (unions of several types, mixed, callable, missing docblocks, properties of parent classes) is left
alone and listed, so it can be checked by hand.

A typed property without default value must be assigned before it is read ("must not be accessed before
initialization"), unlike an untyped one, which is null. So a property without default that the constructor does not
assign (or setUp() of a test, _construct() of a Magento class) gets "= null" if its type is nullable, and is skipped and listed otherwise.

--check lists the typed properties without default value that the constructor does not assign, for example to find
these problems in code that was typed before this check existed.

Usage: add-property-types.py [--dry-run|--check] <directory> [<directory> ...]
"""

import re
import sys
from pathlib import Path

SCALARS = {"string", "int", "float", "bool", "array", "object", "iterable"}

PROPERTY = re.compile(
    r"(?P<doc>[ \t]*/\*\*(?:(?!\*/).)*?@var\s+(?P<type>[^\s*]+)(?:(?!\*/).)*\*/\n)"
    r"(?P<indent>[ \t]*)(?P<modifiers>(?:(?:public|protected|private|static|readonly)\s+)+)"
    r"\$(?P<name>\w+)(?P<rest>\s*(?:=[^;]*)?;)",
    re.S,
)


def native_type(doc_type: str) -> str | None:
    nullable = False
    parts = doc_type.split("|")
    if "null" in parts and len(parts) == 2:
        nullable = True
        parts = [p for p in parts if p != "null"]
    if len(parts) != 1:
        return None
    t = parts[0]
    if t.endswith("[]") or re.match(r"^array[<{]", t) or t.startswith("list<"):
        t = "array"
    elif "<" in t or "{" in t or t in ("mixed", "callable", "resource", "void", "never", "null", "self", "static"):
        return None
    elif t.lower() in SCALARS:
        t = t.lower()
    elif "&" in t:
        doubles = [p for p in t.split("&") if p.lstrip("\\").split("\\")[-1] in ("MockObject", "Stub")]
        if len(doubles) != 1:
            return None
        t = doubles[0]
    elif not re.fullmatch(r"\\?[A-Za-z_][\w\\]*", t):
        return None
    if nullable:
        if "&" in t:
            # (A&B)|null needs DNF types, keep it simple
            return None
        return "?" + t
    return t


def block_end(source: str, start: int, open_char: str, close_char: str) -> int:
    depth, position = 0, start
    while position < len(source):
        if source[position] == open_char:
            depth += 1
        elif source[position] == close_char:
            depth -= 1
            if depth == 0:
                return position
        position += 1
    return position


def constructor_assignments(source: str) -> set[str]:
    """Names of the properties that the constructor assigns or promotes, or that are assigned in the methods which
    initialize objects instead of the constructor: setUp() of PHPUnit tests and _construct() of Magento classes."""
    names: set[str] = set()
    for match in re.finditer(r"function\s+(?P<method>__construct|_construct|setUp)\s*\(", source):
        parameters_end = block_end(source, match.end() - 1, "(", ")")
        if match.group("method") == "__construct":
            names |= set(re.findall(
                r"(?:public|protected|private|readonly)\s+[^$,()]*\$(\w+)", source[match.end():parameters_end]
            ))
        body_start = source.find("{", parameters_end)
        if body_start < 0 or source.find(";", parameters_end, body_start) >= 0:
            continue
        body_end = block_end(source, body_start, "{", "}")
        names |= set(re.findall(r"\$this->(\w+)\s*=[^=]", source[body_start:body_end]))
    return names


TYPED = re.compile(
    r"^[ \t]*(?:(?:public|protected|private|readonly)\s+)+(?!static\b)(?!function\b)(?!const\b)"
    r"(?P<type>\??[\w\\|]+)\s+\$(?P<name>\w+)\s*;",
    re.M,
)


def check(path: Path) -> list[str]:
    source = path.read_text(encoding="utf-8")
    assigned = constructor_assignments(source)
    return [
        f"{path}: ${match.group('name')} ({match.group('type')}) has no default and is not set in the constructor"
        for match in TYPED.finditer(source)
        if match.group("name") not in assigned
    ]


def process(path: Path, dry_run: bool) -> tuple[int, list[str]]:
    source = path.read_text(encoding="utf-8")
    skipped: list[str] = []
    changed = 0
    assigned = constructor_assignments(source)

    def replace(match: re.Match) -> str:
        nonlocal changed
        modifiers = match.group("modifiers")
        # already typed: the text after the modifiers would be the type, not the variable
        t = native_type(match.group("type"))
        if t is None:
            skipped.append(f"{path}: ${match.group('name')} ({match.group('type')})")
            return match.group(0)
        rest = match.group("rest")
        if "=" not in rest and "static" not in modifiers and match.group("name") not in assigned:
            if not t.startswith("?"):
                skipped.append(
                    f"{path}: ${match.group('name')} ({match.group('type')}) has no default and is not set in the "
                    "constructor"
                )
                return match.group(0)
            rest = " = null;"
        changed += 1
        return f"{match.group('doc')}{match.group('indent')}{modifiers}{t} ${match.group('name')}{rest}"

    result = PROPERTY.sub(replace, source)
    if changed and not dry_run:
        path.write_text(result, encoding="utf-8")
    return changed, skipped


def main() -> int:
    args = sys.argv[1:]
    dry_run = "--dry-run" in args
    check_only = "--check" in args
    directories = [a for a in args if a not in ("--dry-run", "--check")]
    if not directories:
        print(__doc__)
        return 1
    if check_only:
        problems = [line for directory in directories for path in sorted(Path(directory).rglob("*.php"))
                    for line in check(path)]
        for line in problems:
            print(line)
        return 1 if problems else 0
    total = 0
    skipped_all: list[str] = []
    for directory in directories:
        for path in sorted(Path(directory).rglob("*.php")):
            changed, skipped = process(path, dry_run)
            if changed:
                print(f"{'would change' if dry_run else 'changed'} {changed:3} properties in {path}")
            total += changed
            skipped_all += skipped
    print(f"{total} properties {'would be ' if dry_run else ''}typed")
    for line in skipped_all:
        print(f"skipped: {line}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
