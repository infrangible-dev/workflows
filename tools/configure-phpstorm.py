#!/usr/bin/env python3
"""Applies the shared PhpStorm settings (templates/phpstorm) to the .idea folders of Magento modules.

    - inspections.xml: inspection settings of the "Project Default" profile
      (.idea/inspectionProfiles/Project_Default.xml); each inspection_tool element replaces the one of the same class
    - project-resources.xml: XML schema catalog for urn:magento:... (component ProjectResources in .idea/misc.xml)

Modules without a .idea folder are skipped; PhpStorm creates it when the module is opened for the first time, so run
the script again afterwards. PhpStorm reloads changed project files; if a module is open, check that the settings are
applied (or close the project before running the script).

Usage: configure-phpstorm.py [--check] <module directory> [<module directory> ...]

    --check   only report modules whose settings differ, exit with 1 if any differs
"""

import re
import sys
from pathlib import Path

TEMPLATE_PATH = Path(__file__).resolve().parent.parent / "templates" / "phpstorm"

EMPTY_PROFILE = """<component name="InspectionProjectProfileManager">
  <profile version="1.0">
    <option name="myName" value="Project Default" />
  </profile>
</component>
"""

EMPTY_PROFILE_SETTINGS = """<component name="InspectionProjectProfileManager">
  <settings>
    <option name="USE_PROJECT_PROFILE" value="true" />
    <version value="1.0" />
  </settings>
</component>
"""

EMPTY_MISC = """<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
</project>
"""


def inspection_tools() -> list[tuple[str, str]]:
    """Returns (class, element) of every inspection_tool in inspections.xml."""
    source = (TEMPLATE_PATH / "inspections.xml").read_text(encoding="utf-8")
    source = re.sub(r"<!--.*?-->", "", source, flags=re.S)
    tools = []
    for match in re.finditer(r"<inspection_tool\b[^>]*?(?:/>|>.*?</inspection_tool>)", source, re.S):
        element = match.group(0)
        tools.append((re.search(r'class="([^"]+)"', element).group(1), element))
    return tools


def project_resources() -> str:
    source = (TEMPLATE_PATH / "project-resources.xml").read_text(encoding="utf-8")
    return re.search(r'  <component name="ProjectResources">.*?</component>\n', source, re.S).group(0)


def apply_inspections(profile: str, tools: list[tuple[str, str]]) -> str:
    for tool_class, element in tools:
        pattern = re.compile(
            r'[ \t]*<inspection_tool class="' + re.escape(tool_class) + r'"[^>]*?(?:/>|>.*?</inspection_tool>)\n?',
            re.S,
        )
        line = "    " + element + "\n"
        if pattern.search(profile):
            profile = pattern.sub(lambda m: line, profile, count=1)
        else:
            profile = profile.replace("  </profile>", line + "  </profile>", 1)
    return profile


def apply_resources(misc: str, resources: str) -> str:
    pattern = re.compile(r'[ \t]*<component name="ProjectResources">.*?</component>\n', re.S)
    if pattern.search(misc):
        return pattern.sub(lambda m: resources, misc, count=1)
    return misc.replace("</project>", resources + "</project>", 1)


def main() -> int:
    args = sys.argv[1:]
    check = "--check" in args
    directories = [Path(a) for a in args if a != "--check"]
    if not directories:
        print(__doc__)
        return 1

    tools = inspection_tools()
    resources = project_resources()
    outdated = False

    for directory in directories:
        idea = directory / ".idea"
        if not idea.is_dir():
            print(f"Skipping {directory}: no .idea folder")
            continue

        files = {
            idea / "inspectionProfiles" / "Project_Default.xml": lambda s: apply_inspections(s or EMPTY_PROFILE, tools),
            idea / "inspectionProfiles" / "profiles_settings.xml": lambda s: s or EMPTY_PROFILE_SETTINGS,
            idea / "misc.xml": lambda s: apply_resources(s or EMPTY_MISC, resources),
        }
        for path, update in files.items():
            current = path.read_text(encoding="utf-8") if path.is_file() else ""
            updated = update(current)
            if updated == current:
                continue
            if check:
                print(f"Outdated: {path}")
                outdated = True
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(updated, encoding="utf-8")
                print(f"{'Updated' if current else 'Added'}: {path}")

    return 1 if check and outdated else 0


if __name__ == "__main__":
    sys.exit(main())
