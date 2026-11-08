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

Usage: add-property-types.py [--dry-run] <directory> [<directory> ...]
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


def process(path: Path, dry_run: bool) -> tuple[int, list[str]]:
    source = path.read_text(encoding="utf-8")
    skipped: list[str] = []
    changed = 0

    def replace(match: re.Match) -> str:
        nonlocal changed
        modifiers = match.group("modifiers")
        # already typed: the text after the modifiers would be the type, not the variable
        t = native_type(match.group("type"))
        if t is None:
            skipped.append(f"{path}: ${match.group('name')} ({match.group('type')})")
            return match.group(0)
        changed += 1
        return f"{match.group('doc')}{match.group('indent')}{modifiers}{t} ${match.group('name')}{match.group('rest')}"

    result = PROPERTY.sub(replace, source)
    if changed and not dry_run:
        path.write_text(result, encoding="utf-8")
    return changed, skipped


def main() -> int:
    args = sys.argv[1:]
    dry_run = "--dry-run" in args
    directories = [a for a in args if a != "--dry-run"]
    if not directories:
        print(__doc__)
        return 1
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
