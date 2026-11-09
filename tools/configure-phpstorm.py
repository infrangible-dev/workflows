#!/usr/bin/env python3
"""Applies the shared PhpStorm settings (templates/phpstorm) to the .idea folders of Magento modules.

    - profiles_settings.xml: the inspection profile of the modules (.idea/inspectionProfiles/profiles_settings.xml),
      the IDE profile "Magento", shared by all modules
    - inspections.xml: inspection settings, written into the "Project Default" profile of every module
      (.idea/inspectionProfiles/Project_Default.xml) and, with --ide-profile, into the IDE profile; each
      inspection_tool element replaces the one of the same class
    - project-resources.xml: XML schema catalog for urn:magento:... (component ProjectResources in .idea/misc.xml)
    - entry-points.xml: class patterns the inspection "Unused declaration" treats as used (component
      PhpEntryPointsManager in .idea/misc.xml)
    - module-folders.xml: folders that are indexed or excluded (.idea/<module>.iml)
    - unchecked-exceptions.xml: exceptions that need no @throws tag (.idea/php.xml, merged with existing ones)
    - stubs: declarations for PhpStorm only, added as include path (.idea/php.xml), relative to the module, so the
      workflows repository has to be next to the modules

Modules without a .idea folder are skipped; PhpStorm creates it when the module is opened for the first time, so run
the script again afterwards. PhpStorm reloads changed project files; if a module is open, check that the settings are
applied (or close the project before running the script).

Usage: configure-phpstorm.py [--check] [--ide-profile <file>] <module directory> [<module directory> ...]

    --check                 only report modules whose settings differ, exit with 1 if any differs
    --ide-profile <file>    also write the inspection settings into this IDE profile, for example
                            /mnt/c/Users/<user>/AppData/Roaming/JetBrains/PhpStorm<version>/inspection/Magento.xml;
                            PhpStorm saves IDE profiles itself, so close it before using this option; a missing
                            file is created with the name of the file as profile name
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


STUBS_INCLUDE_PATH = "$PROJECT_DIR$/../workflows/templates/phpstorm/stubs"

EMPTY_PHP = """<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
</project>
"""

EMPTY_MISC = """<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
</project>
"""


def read_file(path: Path) -> tuple[str, str]:
    """Returns the content with \\n line endings and the line ending of the file (PhpStorm on Windows uses \\r\\n)."""
    if not path.is_file():
        return "", "\n"
    with path.open(encoding="utf-8", newline="") as file:
        content = file.read()
    return content.replace("\r\n", "\n"), "\r\n" if "\r\n" in content else "\n"


def write_file(path: Path, content: str, line_ending: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as file:
        file.write(content.replace("\n", line_ending))


def inspection_tools() -> list[tuple[str, str]]:
    """Returns (class, element) of every inspection_tool in inspections.xml."""
    source = (TEMPLATE_PATH / "inspections.xml").read_text(encoding="utf-8")
    source = re.sub(r"<!--.*?-->", "", source, flags=re.S)
    tools = []
    for match in re.finditer(r"<inspection_tool\b[^>]*?(?:/>|>.*?</inspection_tool>)", source, re.S):
        element = match.group(0)
        tools.append((re.search(r'class="([^"]+)"', element).group(1), element))
    return tools


def profile_settings() -> str:
    return (TEMPLATE_PATH / "profiles_settings.xml").read_text(encoding="utf-8")


def project_resources() -> str:
    source = (TEMPLATE_PATH / "project-resources.xml").read_text(encoding="utf-8")
    return re.search(r'  <component name="ProjectResources">.*?</component>\n', source, re.S).group(0)


def module_folders() -> tuple[list[str], list[str]]:
    """Returns the paths to index and the paths to exclude from module-folders.xml."""
    source = (TEMPLATE_PATH / "module-folders.xml").read_text(encoding="utf-8")
    source = re.sub(r"<!--.*?-->", "", source, flags=re.S)
    return re.findall(r'<index path="([^"]+)"', source), re.findall(r'<exclude path="([^"]+)"', source)


def apply_folders(iml: str, index: list[str], exclude: list[str]) -> str:
    for path in index:
        iml = re.sub(r'[ \t]*<excludeFolder url="file://\$MODULE_DIR\$/' + re.escape(path) + r'" />\n', "", iml)
    for path in exclude:
        element = f'<excludeFolder url="file://$MODULE_DIR$/{path}" />'
        if element in iml:
            continue
        content = re.search(r'([ \t]*)<content url="file://\$MODULE_DIR\$"\s*(/?)>', iml)
        if not content:
            continue
        if content.group(2):
            # empty content element
            iml = iml.replace(content.group(0), f'{content.group(1)}<content url="file://$MODULE_DIR$">\n'
                              f'{content.group(1)}  {element}\n{content.group(1)}</content>', 1)
        else:
            iml = re.sub(r'(<content url="file://\$MODULE_DIR\$"\s*>.*?)([ \t]*</content>)',
                         lambda m: m.group(1) + f'{content.group(1)}  {element}\n' + m.group(2), iml, count=1, flags=re.S)
    return iml


def apply_include_path(php: str, path: str) -> str:
    element = f'<path value="{path}" />'
    if element in php:
        return php
    manager = re.search(r'([ \t]*)<component name="PhpIncludePathManager">\s*<include_path>\n', php)
    if manager:
        indent = manager.group(1)
        return php[:manager.end()] + f"{indent}    {element}\n" + php[manager.end():]
    empty = re.search(r'[ \t]*<component name="PhpIncludePathManager"\s*/>\n', php)
    block = (f'  <component name="PhpIncludePathManager">\n    <include_path>\n      {element}\n'
             f'    </include_path>\n  </component>\n')
    if empty:
        return php[:empty.start()] + block + php[empty.end():]
    return php.replace("</project>", block + "</project>", 1)


def unchecked_exceptions() -> list[str]:
    source = (TEMPLATE_PATH / "unchecked-exceptions.xml").read_text(encoding="utf-8")
    source = re.sub(r"<!--.*?-->", "", source, flags=re.S)
    return re.findall(r'<fqn value="([^"]+)"', source)


def apply_unchecked_exceptions(php: str, fqns: list[str]) -> str:
    component = re.search(
        r'([ \t]*)<component name="PhpAnalysisConfiguration">\s*<unchecked_exceptions>(.*?)</unchecked_exceptions>'
        r'\s*</component>\n', php, re.S)
    existing = re.findall(r'<fqn value="([^"]+)"', component.group(2)) if component else []
    merged = sorted(set(existing) | set(fqns))
    if component and merged == sorted(existing):
        return php
    block = '  <component name="PhpAnalysisConfiguration">\n    <unchecked_exceptions>\n'
    block += "".join(f'      <fqn value="{fqn}" />\n' for fqn in merged)
    block += '    </unchecked_exceptions>\n  </component>\n'
    if component:
        return php[:component.start()] + block + php[component.end():]
    # components are sorted by name in PhpStorm files, but any position works
    return php.replace("</project>", block + "</project>", 1)


def apply_inspections(profile: str, tools: list[tuple[str, str]]) -> str:
    for tool_class, element in tools:
        pattern = re.compile(
            r'[ \t]*<inspection_tool class="' + re.escape(tool_class) + r'"[^>]*?(?:/>|>.*?</inspection_tool>)\n?',
            re.S,
        )
        # project profiles are nested in a component (indent 4), IDE profiles are not (indent 2)
        closing = re.search(r"^([ \t]*)</profile>", profile, re.M)
        indent = (closing.group(1) if closing else "") + "  "
        line = indent + element + "\n"
        if pattern.search(profile):
            profile = pattern.sub(lambda m: line, profile, count=1)
        elif closing:
            profile = profile[:closing.start()] + line + profile[closing.start():]
    return profile


def entry_points() -> str:
    source = (TEMPLATE_PATH / "entry-points.xml").read_text(encoding="utf-8")
    return re.search(r'  <component name="PhpEntryPointsManager">.*?</component>\n', source, re.S).group(0)


def apply_component(misc: str, name: str, component: str) -> str:
    pattern = re.compile(r'[ \t]*<component name="' + name + r'">.*?</component>\n', re.S)
    if pattern.search(misc):
        return pattern.sub(lambda m: component, misc, count=1)
    return misc.replace("</project>", component + "</project>", 1)


def main() -> int:
    args = sys.argv[1:]
    check = "--check" in args
    ide_profile = None
    if "--ide-profile" in args:
        position = args.index("--ide-profile")
        ide_profile = Path(args[position + 1])
        del args[position:position + 2]
    directories = [Path(a) for a in args if a != "--check"]
    if not directories:
        print(__doc__)
        return 1

    tools = inspection_tools()
    settings = profile_settings()
    resources = project_resources()
    entries = entry_points()
    index, exclude = module_folders()
    unchecked = unchecked_exceptions()
    outdated = False

    for directory in directories:
        idea = directory / ".idea"
        if not idea.is_dir():
            print(f"Skipping {directory}: no .idea folder")
            continue

        files = {
            idea / "inspectionProfiles" / "Project_Default.xml": lambda s: apply_inspections(s or EMPTY_PROFILE, tools),
            idea / "inspectionProfiles" / "profiles_settings.xml": lambda s: settings,
            idea / "misc.xml": lambda s: apply_component(
                apply_component(s or EMPTY_MISC, "PhpEntryPointsManager", entries), "ProjectResources", resources),
            idea / "php.xml": lambda s: apply_unchecked_exceptions(
                apply_include_path(s or EMPTY_PHP, STUBS_INCLUDE_PATH), unchecked),
        }
        for iml in sorted(idea.glob("*.iml")):
            files[iml] = lambda s: apply_folders(s, index, exclude)
        for path, update in files.items():
            current, line_ending = read_file(path)
            updated = update(current)
            if updated == current:
                continue
            if check:
                print(f"Outdated: {path}")
                outdated = True
            else:
                write_file(path, updated, line_ending)
                print(f"{'Updated' if current else 'Added'}: {path}")

    if ide_profile is not None:
        current, line_ending = read_file(ide_profile)
        if not current:
            # PhpStorm only writes a profile that differs from its defaults; a new file needs the name only
            line_ending = "\r\n" if str(ide_profile).startswith("/mnt/") else "\n"
            base = f'<profile version="1.0">\n  <option name="myName" value="{ide_profile.stem}" />\n</profile>\n'
        else:
            base = current
        updated = apply_inspections(base, tools)
        if updated != current:
            if check:
                print(f"Outdated: {ide_profile}")
                outdated = True
            else:
                write_file(ide_profile, updated, line_ending)
                print(f"Updated: {ide_profile}")

    return 1 if check and outdated else 0


if __name__ == "__main__":
    sys.exit(main())
