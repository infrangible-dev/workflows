#!/usr/bin/env python3
"""Completes the docblocks of methods as the Magento coding standard and PhpStorm expect them.

    public function loadReview(int $id): Review     /**
    {                                                 * Loads the review.
                                              ->      *
                                                      * @param int $id
                                                      *
                                                      * @return Review
                                                      */
                                                     public function loadReview(int $id): Review

- methods without docblock get one
- docblocks without short description get one, generated from the method name (get -> "Returns the ...", load ->
  "Loads the ...", is -> "Checks whether ..." and so on); constructors and the setUp/tearDown methods of PHPUnit do
  not need one
- missing @param tags are added in the order of the arguments, with the native type of the argument
- missing @return tags are added with the native return type (not for constructors)

The generated descriptions are only a start: the script lists every method it described, so the descriptions can be
improved by hand where the method name says too little. Arguments and methods without native type get "mixed" and are
listed as well, as are array types, which need a @phpstan-param / @phpstan-return with the value type for PHPStan.

Usage: add-method-docblocks.py [--dry-run] <directory> [<directory> ...]
"""

import re
import sys
from pathlib import Path

DECLARATION = re.compile(
    r"^(?P<indent>[ \t]+)(?P<modifiers>(?:(?:abstract|final|public|protected|private|static)\s+)+)function\s+&?"
    r"(?P<name>\w+)\s*\(",
    re.M,
)

VERBS = {
    "get": "Returns the",
    "fetch": "Fetches the",
    "load": "Loads the",
    "save": "Saves the",
    "new": "Creates a new",
    "create": "Creates the",
    "set": "Sets the",
    "add": "Adds the",
    "remove": "Removes the",
    "delete": "Deletes the",
    "update": "Updates the",
    "import": "Imports the",
    "export": "Exports the",
    "render": "Renders the",
    "determine": "Determines the",
    "prepare": "Prepares the",
    "format": "Formats the",
    "read": "Reads the",
    "write": "Writes the",
    "clean": "Cleans the",
    "invalidate": "Invalidates the",
    "collect": "Collects the",
    "process": "Processes the",
    "handle": "Handles the",
    "move": "Moves the",
    "reset": "Resets the",
    "select": "Selects the",
    "encrypt": "Encrypts the",
    "decrypt": "Decrypts the",
    "register": "Registers the",
    "unregister": "Unregisters the",
}

# methods that need no short description (the Magento coding standard does not require one for them)
NO_DESCRIPTION = {"__construct", "setUp", "tearDown", "setUpBeforeClass", "tearDownAfterClass"}

SPECIAL = {
    "toOptionArray": "Returns the options for a select field.",
    "toOptions": "Returns the options as value => label.",
    "getAllOptions": "Returns all options of the source.",
    "execute": "Executes the action.",
    "dispatch": "Dispatches the request.",
    "configure": "Configures the command.",
    "run": "Runs the task.",
}


def words(name: str) -> list:
    return re.findall(r"[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z0-9]+|[A-Z]+[0-9]*s?", name.lstrip("_"))


def describe(name: str) -> str:
    if name in SPECIAL:
        return SPECIAL[name]
    parts = words(name)
    if not parts:
        return name + "."
    verb = parts[0].lower()
    rest = " ".join(part if part.isupper() or re.fullmatch(r"[A-Z]+s", part) else part.lower() for part in parts[1:])
    if verb in ("is", "has", "can", "should"):
        phrase = {"is": "is", "has": "has", "can": "can", "should": "should"}[verb]
        return f"Checks whether it {phrase} {rest}.".replace("  ", " ") if rest else "Checks the state."
    if verb in VERBS:
        return f"{VERBS[verb]} {rest}." if rest else VERBS[verb].rsplit(" ", 1)[0] + "."
    if re.search(r"[^aeiou]y$", verb):
        third = verb[:-1] + "ies"
    else:
        third = verb + ("es" if re.search(r"(s|sh|ch|x|z)$", verb) else "s")
    return f"{third.capitalize()} the {rest}." if rest else f"{third.capitalize()}."


def matching_parenthesis(text: str, start: int) -> int:
    depth = 0
    position = start
    while position < len(text):
        character = text[position]
        if character in "'\"":
            end = position + 1
            while end < len(text) and text[end] != character:
                end += 2 if text[end] == "\\" else 1
            position = end
        elif character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
            if depth == 0:
                return position
        position += 1
    raise ValueError("unbalanced parentheses")


def split_arguments(text: str) -> list:
    arguments, depth, current = [], 0, ""
    for character in text:
        if character in "([":
            depth += 1
        elif character in ")]":
            depth -= 1
        if character == "," and depth == 0:
            arguments.append(current)
            current = ""
        else:
            current += character
    if current.strip():
        arguments.append(current)
    return [argument.strip() for argument in arguments if argument.strip()]


def parse_argument(argument: str):
    argument = re.sub(r"#\[[^\]]*\]\s*", "", argument)
    argument = argument.split("=", 1)[0].strip()
    argument = re.sub(r"^(?:(?:public|protected|private|readonly)\s+)+", "", argument)
    match = re.match(r"(?P<type>[^$&.]*?)\s*(?P<ref>&)?\s*(?P<variadic>\.\.\.)?\s*\$(?P<name>\w+)$", argument)
    if not match:
        return None
    native = match.group("type").strip()
    return {
        "name": match.group("name"),
        "type": native,
        "variadic": bool(match.group("variadic")),
    }


def doc_type(native: str) -> str:
    if not native:
        return "mixed"
    if native.startswith("?"):
        return native[1:] + "|null"
    return native


def complete(text: str, path: Path, report: list) -> tuple:
    changes = 0
    result = []
    last = 0
    for match in DECLARATION.finditer(text):
        name = match.group("name")
        indent = match.group("indent")
        open_parenthesis = match.end() - 1
        close_parenthesis = matching_parenthesis(text, open_parenthesis)
        arguments = [parse_argument(argument) for argument in split_arguments(text[open_parenthesis + 1:close_parenthesis])]
        arguments = [argument for argument in arguments if argument]
        return_match = re.match(r"\s*:\s*(?P<type>[^{;]+?)\s*[{;]", text[close_parenthesis + 1:])
        return_type = return_match.group("type").strip() if return_match else ""

        before = text[last:match.start()]
        # the docblock (and attributes) directly in front of the declaration
        doc_match = re.search(r"(?P<doc>[ \t]*/\*\*(?:(?!\*/).)*\*/\n)(?P<attributes>(?:[ \t]*#\[[^\n]*\]\n)*)\Z", before, re.S)
        if doc_match and "\n" in doc_match.group("doc").strip():
            doc_lines = doc_match.group("doc").rstrip("\n").split("\n")
            prefix = before[:doc_match.start()]
            attributes = doc_match.group("attributes")
        elif doc_match:
            # single line docblock: /** @inheritDoc */ or similar
            single = doc_match.group("doc").strip()[3:-2].strip()
            doc_lines = [f"{indent}/**", f"{indent} * {single}", f"{indent} */"] if single else [f"{indent}/**", f"{indent} */"]
            prefix = before[:doc_match.start()]
            attributes = doc_match.group("attributes")
        else:
            attribute_match = re.search(r"(?P<attributes>(?:[ \t]*#\[.*\]\n)*)\Z", before)
            prefix = before[:attribute_match.start()]
            attributes = attribute_match.group("attributes")
            doc_lines = [f"{indent}/**", f"{indent} */"]

        body = doc_lines[1:-1]
        content = [re.sub(r"^\s*\*\s?", "", line) for line in body]
        if any(re.search(r"\{?@inheritDoc\}?", line, re.I) for line in content):
            result.append(before)
            last = match.start()
            continue

        changed = False
        tag_index = next((index for index, line in enumerate(content) if line.startswith("@")), len(content))
        description = [line for line in content[:tag_index] if line.strip()]
        lines = list(content)

        if not description and name not in NO_DESCRIPTION:
            generated = describe(name)
            lines = [generated, ""] + [line for line in lines if line.strip() or lines.index(line) >= tag_index]
            report.append(f"{path}: {name}(): {generated}")
            changed = True
            tag_index = 2

        tags = lines[tag_index:]
        # existing @param tags (with their continuation lines), by argument name
        existing, others, param_start, current = {}, [], None, None
        for line in tags:
            param = re.match(r"@param\s+[^$]*?(?:\.\.\.)?\$(\w+)", line)
            if param:
                param_start = len(others) if param_start is None else param_start
                current = param.group(1)
                existing.setdefault(current, []).append(line)
            elif current is not None and line.strip() and not line.startswith("@"):
                existing[current].append(line)
            else:
                current = None
                others.append(line)
        names = [argument["name"] for argument in arguments]
        new_params = []
        for argument in arguments:
            if argument["name"] in existing:
                new_params.extend(existing[argument["name"]])
                continue
            type_text = doc_type(argument["type"])
            prefix_variadic = "..." if argument["variadic"] else ""
            new_params.append(f"@param {type_text} {prefix_variadic}${argument['name']}")
            if type_text == "mixed" or "array" in type_text:
                report.append(f"{path}: {name}(): check type of ${argument['name']} ({type_text})")
        for parameter_name, parameter_lines in existing.items():
            if parameter_name not in names:
                new_params.extend(parameter_lines)
                report.append(f"{path}: {name}(): @param ${parameter_name} has no argument")
        old_params = [line for lines_of in existing.values() for line in lines_of]
        if new_params != old_params or (param_start is not None and old_params != [
            line for line in tags if line in old_params
        ]):
            insert_at = param_start if param_start is not None else 0
            if param_start is None and others and new_params:
                new_params = new_params + [""]
            tags = others[:insert_at] + new_params + others[insert_at:]
            changed = True
        elif param_start is not None:
            # unchanged order: keep the tags as they are
            pass

        if name != "__construct" and not any(line.startswith("@return") for line in tags):
            type_text = doc_type(return_type)
            if type_text == "mixed":
                report.append(f"{path}: {name}(): check return type (no native type)")
            elif "array" in type_text:
                report.append(f"{path}: {name}(): check return type ({type_text})")
            throws_index = next((index for index, line in enumerate(tags) if line.startswith("@throws")), len(tags))
            addition = [f"@return {type_text}"]
            if throws_index > 0 and tags[throws_index - 1].startswith("@param") or (
                throws_index > 0 and tags[throws_index - 1] and not tags[throws_index - 1].startswith("@return")
                and any(line.startswith("@param") for line in tags[:throws_index])
            ):
                addition = [""] + addition
            tags = tags[:throws_index] + addition + tags[throws_index:]
            changed = True

        if not changed:
            result.append(before)
            last = match.start()
            continue

        # exactly one blank line between description and tags
        head = lines[:tag_index]
        while head and not head[-1].strip():
            head.pop()
        while tags and not tags[0].strip():
            tags.pop(0)
        while tags and not tags[-1].strip():
            tags.pop()
        new_content = head + ([""] if head and tags else []) + tags
        new_doc = [f"{indent}/**"] + [f"{indent} *" + (f" {line}" if line else "") for line in new_content] + [f"{indent} */"]
        result.append(prefix + "\n".join(new_doc) + "\n" + attributes)
        last = match.start()
        changes += 1

    result.append(text[last:])
    return "".join(result), changes


def main() -> int:
    arguments = sys.argv[1:]
    dry_run = "--dry-run" in arguments
    directories = [argument for argument in arguments if argument != "--dry-run"]
    if not directories or "-h" in directories or "--help" in directories:
        print(__doc__)
        return 0 if directories else 1
    report = []
    total = 0
    for directory in directories:
        for path in sorted(Path(directory).rglob("*.php")):
            text = path.read_text()
            new_text, changes = complete(text, path, report)
            if changes:
                total += changes
                print(f"{'would change' if dry_run else 'changed'} {changes:3d} docblocks in {path}")
                if not dry_run:
                    path.write_text(new_text)
    if report:
        print("\nCheck by hand:")
        for line in report:
            print(f"  {line}")
    print(f"\n{total} docblocks {'would be ' if dry_run else ''}completed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
