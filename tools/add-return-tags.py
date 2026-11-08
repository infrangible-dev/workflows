#!/usr/bin/env python3
"""Adds missing @return tags to method docblocks, taken from the native return type of the method.

    /**                                   /**
     * Checks whether ...                  * Checks whether ...
     */                            ->      *
    public function isLoaded(): bool       * @return bool
                                           */
                                          public function isLoaded(): bool

PhpStorm (default inspection "Missing @return tag") expects a @return tag in every docblock of a method. Methods are
skipped when their docblock already has @return or {@inheritDoc}, for constructors and destructors, and when the
method has no native return type (these are listed, so they can be checked by hand). The tag is inserted before
@throws, as in Magento, otherwise at the end of the docblock.

Usage: add-return-tags.py [--dry-run] <directory> [<directory> ...]
"""

import re
import sys
from pathlib import Path

METHOD = re.compile(
    r"(?P<doc>[ \t]*/\*\*(?:(?!\*/).)*\*/)"
    r"(?P<between>\s*(?:#\[[^\]]*\]\s*)*)"
    r"(?P<signature>(?:(?:abstract|final|public|protected|private|static)\s+)*function\s+&?(?P<name>\w+)\s*"
    r"\((?P<params>(?:[^()]|\([^()]*\))*)\)\s*(?::\s*(?P<type>[^{;]+?))?\s*[{;])",
    re.S,
)


def add_return_tag(doc: str, return_type: str) -> str:
    lines = doc.split("\n")
    closing = len(lines) - 1
    indent = re.match(r"[ \t]*", lines[closing]).group(0)
    tag = f"{indent}* @return {return_type}"
    if len(lines) == 1:
        # single line docblock: /** Description */
        text = re.match(r"\s*/\*\*\s*(.*?)\s*\*/", doc).group(1)
        start = re.match(r"[ \t]*", doc).group(0)
        body = [f"{start}/**", f"{start} * {text}", f"{start} *", f"{start} * @return {return_type}", f"{start} */"]
        return "\n".join(body)
    insert_at = closing
    for index, line in enumerate(lines):
        if re.match(r"\s*\*\s*@throws\b", line):
            insert_at = index
            break
    has_tags = any(re.match(r"\s*\*\s*@", line) for line in lines[:insert_at])
    previous = lines[insert_at - 1] if insert_at > 0 else ""
    new_lines = [tag]
    if not has_tags and not re.fullmatch(r"\s*\*\s*", previous) and not previous.strip().startswith("/**"):
        # a blank line between the description and the first tag
        new_lines.insert(0, f"{indent}*")
    return "\n".join(lines[:insert_at] + new_lines + lines[insert_at:])


def process(path: Path, dry_run: bool) -> tuple[int, list[str]]:
    with path.open(encoding="utf-8", newline="") as file:
        original = file.read()
    line_ending = "\r\n" if "\r\n" in original else "\n"
    source = original.replace("\r\n", "\n")
    skipped: list[str] = []
    changed = 0

    def replace(match: re.Match) -> str:
        nonlocal changed
        doc = match.group("doc")
        name = match.group("name")
        if re.search(r"@return\b|\{?@inheritDoc\}?", doc, re.I) or name in ("__construct", "__destruct"):
            return match.group(0)
        return_type = match.group("type")
        if not return_type:
            line = source.count("\n", 0, match.start("signature")) + 1
            skipped.append(f"{path}:{line}: {name}() has no native return type")
            return match.group(0)
        changed += 1
        return add_return_tag(doc, re.sub(r"\s+", "", return_type)) + match.group("between") + match.group("signature")

    result = METHOD.sub(replace, source)
    if changed and not dry_run:
        with path.open("w", encoding="utf-8", newline="") as file:
            file.write(result.replace("\n", line_ending))
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
        for path in sorted(list(Path(directory).rglob("*.php")) + list(Path(directory).rglob("*.phtml"))):
            changed, skipped = process(path, dry_run)
            if changed:
                print(f"{'would change' if dry_run else 'changed'} {changed:3} docblocks in {path}")
            total += changed
            skipped_all += skipped
    print(f"{total} @return tags {'would be ' if dry_run else ''}added")
    for line in skipped_all:
        print(f"skipped: {line}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
