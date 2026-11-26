#!/usr/bin/env python3
"""Applies the shared PhpStorm settings (templates/phpstorm) to the .idea folders of Magento modules.

    - profiles_settings.xml: the inspection profile of the modules (.idea/inspectionProfiles/profiles_settings.xml),
      the IDE profile "Magento", shared by all modules
    - inspections.xml: inspection settings, written into the "Project Default" profile of every module
      (.idea/inspectionProfiles/Project_Default.xml) and, with --ide-profile, into the IDE profile; each
      inspection_tool element replaces the one of the same class
    - project-resources.xml: XML schema catalog for urn:magento:... (component ProjectResources in .idea/misc.xml),
      completed with the schemas of the module and of the Infrangible modules in its vendor folder
      with corrected copies of Magento schemas in schemas, relative to the module like the stubs
    - entry-points.xml: class patterns the inspection "Unused declaration" treats as used (component
      PhpEntryPointsManager in .idea/misc.xml)
    - module-folders.xml: folders that are indexed or excluded (.idea/<module>.iml)
    - unchecked-exceptions.xml: exceptions that need no @throws tag (.idea/php.xml, merged with existing ones)
    - js-libraries.xml: JavaScript libraries (.idea/libraries/<name>.xml), assigned to the project
      (.idea/jsLibraryMappings.xml, merged with libraries assigned there already)
    - scopes.xml: scopes that inspections.xml refers to (.idea/scopes/<name>.xml)
    - ../spelling/words.txt: words for the spell checker, shared with tools/check-spelling.sh, for example from class
      names like ReinitableConfigInterface (.idea/dictionaries/magento.xml; the dictionary "project" of the module
      stays)
    - .idea/workspace.xml: the Composer synchronization of PhpStorm is switched off (component ComposerSettings); when
      the installed packages changed, it runs when the project is opened and excludes all packages again, also
      vendor/magento/magento2-base with the JavaScript libraries and the LESS library that module-folders.xml indexes
    - stubs: declarations for PhpStorm only, added as include path (.idea/php.xml), relative to the module, so the
      workflows repository has to be next to the modules
    - ESLint with the rules of the Magento coding standard, like tools/check-eslint.sh: the rules and their npm
      packages are installed into .eslint of the workflows (not in git) from vendor/magento/magento-coding-standard of
      a module with a running development environment (or of MAGENTO_ROOT) with npm, again when its package-lock.json
      changes; every module gets .idea/eslint.config.mjs, which loads them without the bundled JavaScript libraries of
      the module (files without the copyright header of Andreas Knollmann), .idea/jsLinters/eslint.xml, which points
      PhpStorm to it, and the ESLint package and Node.js of WSL in .idea/workspace.xml (component PropertiesComponent)

Modules without a .idea folder are skipped; PhpStorm creates it when the module is opened for the first time, so run
the script again afterwards. PhpStorm reloads changed project files; if a module is open, check that the settings are
applied (or close the project before running the script).
New JavaScript libraries are only loaded when PhpStorm opens the project, so reopen modules that are open.

Usage: configure-phpstorm.py [--check] [--ide-profile <file>] <module directory> [<module directory> ...]

    --check                 only report modules whose settings differ, exit with 1 if any differs (also without
                            --check: Magento schemas of the module that PhpStorm cannot load and that have no
                            corrected copy in templates/phpstorm/schemas, and imported factories and proxies that
                            are not generated yet in generated/code, which PhpStorm reports as undefined classes)
    --ide-profile <file>    also write the inspection settings into this IDE profile, for example
                            /mnt/c/Users/<user>/AppData/Roaming/JetBrains/PhpStorm<version>/inspection/Magento.xml;
                            PhpStorm saves IDE profiles itself, so close it before using this option; a missing
                            file is created with the name of the file as profile name
"""

import json
import os
import re
import shutil
import subprocess
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

ESLINT_PATH = Path(__file__).resolve().parent.parent / ".eslint"

ESLINT_XML = """<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="EslintConfiguration">
    <custom-configuration-file used="true" path="$PROJECT_DIR$/.idea/eslint.config.mjs" />
  </component>
</project>
"""

NODE_PATH = "/usr/bin/node"

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


def dictionary() -> str:
    """Returns .idea/dictionaries/magento.xml with the words of templates/spelling/words.txt."""
    source = (TEMPLATE_PATH.parent / "spelling" / "words.txt").read_text(encoding="utf-8")
    words = sorted({line.strip().lower() for line in source.splitlines() if line.strip() and not line.startswith("#")})
    lines = "".join(f"      <w>{word}</w>\n" for word in words)
    return (
        '<component name="ProjectDictionaryState">\n  <dictionary name="magento">\n    <words>\n'
        + lines
        + "    </words>\n  </dictionary>\n</component>\n"
    )


def scopes() -> dict[str, str]:
    """Returns the content of .idea/scopes/<name>.xml of every scope in scopes.xml by file name."""
    source = (TEMPLATE_PATH / "scopes.xml").read_text(encoding="utf-8")
    source = re.sub(r"<!--.*?-->", "", source, flags=re.S)
    return {
        re.sub(r"\W", "_", match.group(1)) + ".xml":
            f'<component name="DependencyValidationManager">\n  {match.group(0)}\n</component>\n'
        for match in re.finditer(r'<scope name="([^"]+)" pattern="[^"]*" />', source)
    }


def profile_settings() -> str:
    return (TEMPLATE_PATH / "profiles_settings.xml").read_text(encoding="utf-8")


def project_resources() -> str:
    source = (TEMPLATE_PATH / "project-resources.xml").read_text(encoding="utf-8")
    return re.search(r'  <component name="ProjectResources">.*?</component>\n', source, re.S).group(0)


def infrangible_resources(directory: Path, resources: str) -> str:
    """Adds the schemas of the Infrangible modules (the module and the ones in vendor/infrangible) to the catalog as
    urn:magento:module:<Module>:etc/<file>.xsd, the form that Magento's dev:urn-catalog:generate uses; the template
    only knows Magento's schemas."""
    lines = []
    for module_dir in [directory] + sorted((directory / "vendor" / "infrangible").glob("*")):
        registration = module_dir / "src" / "registration.php"
        if not registration.is_file():
            continue
        name = re.search(r"'(Infrangible_\w+)'", registration.read_text(encoding="utf-8", errors="replace"))
        if name is None:
            continue
        for xsd in sorted((module_dir / "src" / "etc").glob("*.xsd")):
            url = f"urn:magento:module:{name.group(1)}:etc/{xsd.name}"
            location = "$PROJECT_DIR$/" + xsd.relative_to(directory).as_posix()
            if f'url="{url}"' not in resources:
                lines.append(f'    <resource url="{url}" location="{location}"/>\n')
    return resources.replace("  </component>", "".join(lines) + "  </component>", 1) if lines else resources


def module_folders() -> tuple[list[str], list[str]]:
    """Returns the paths to index and the paths to exclude from module-folders.xml."""
    source = (TEMPLATE_PATH / "module-folders.xml").read_text(encoding="utf-8")
    source = re.sub(r"<!--.*?-->", "", source, flags=re.S)
    return re.findall(r'<index path="([^"]+)"', source), re.findall(r'<exclude path="([^"]+)"', source)


def exclude_beside(module: Path, excluded: str, path: str) -> list[str]:
    """Returns the folders below the excluded folder that are not on the way to the path, sorted."""
    paths = []
    parent = excluded
    for part in Path(path).relative_to(excluded).parts:
        if not (module / parent).is_dir():
            return []
        paths += [f"{parent}/{child.name}" for child in (module / parent).iterdir()
                  if child.is_dir() and child.name != part]
        parent = f"{parent}/{part}"
    return sorted(paths)


def library_folders(libraries: dict[str, list[str]], index: list[str]) -> list[str]:
    """Returns the folders of the JavaScript library files that have to be indexed besides the index paths.

    A library file in an excluded folder is not indexed, so PhpStorm does not know its functions (for example define()
    of RequireJS in lib/web/requirejs). Folders that contain an index path (lib/web for jquery.js) stay as they are,
    their files are not excluded."""
    # files outside the module (the stubs of the workflows repository) are not in an excluded folder
    folders = sorted({str(Path(path).parent) for files in libraries.values() for path in files
                      if not path.startswith("../")})
    # folders that contain an index path are not excluded themselves
    folders = [folder for folder in folders if not any(path.startswith(folder + "/") for path in index)]
    # a folder inside another library folder is indexed with it
    result = [folder for folder in folders if not any(folder.startswith(other + "/") for other in folders)]
    return result


def apply_folders(iml: str, index: list[str], exclude: list[str], module: Path) -> str:
    def excluded_in_iml(path: str) -> re.Pattern[str]:
        return re.compile(r'[ \t]*<excludeFolder url="file://\$MODULE_DIR\$/' + re.escape(path) + r'" />\n')

    def on_way_to_index(path: str) -> bool:
        return any(path == indexed or indexed.startswith(path + "/") for indexed in index)

    pending = list(exclude)
    for path in index:
        iml = excluded_in_iml(path).sub("", iml)
        # an excluded parent folder, for example a Composer package that PhpStorm's Composer synchronization excludes,
        # or a folder that an earlier index path excludes, is replaced by the exclusion of everything beside the path
        parts = path.split("/")
        for length in range(len(parts) - 1, 0, -1):
            parent = "/".join(parts[:length])
            if excluded_in_iml(parent).search(iml) or parent in pending:
                beside = exclude_beside(module, parent, path)
                if beside:
                    iml = excluded_in_iml(parent).sub("", iml)
                    pending = [folder for folder in pending if folder != parent] + beside
                break
    # no exclusion of an index path or of a folder on the way to one
    for path in index:
        for length in range(len(path.split("/")), 0, -1):
            iml = excluded_in_iml("/".join(path.split("/")[:length])).sub("", iml)
    for path in pending:
        if on_way_to_index(path):
            continue
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


def php_language_level(directory: Path) -> str | None:
    """The lowest PHP version that composer.json of the module allows (">=8.1" -> "8.1"), or None."""
    try:
        constraint = json.loads((directory / "composer.json").read_text()).get("require", {}).get("php", "")
    except (OSError, ValueError):
        return None
    match = re.search(r"(\d+)\.(\d+)", constraint) if isinstance(constraint, str) else None
    return f"{match.group(1)}.{match.group(2)}" if match else None


def apply_language_level(php: str, level: str | None) -> str:
    """Sets the PHP language level of the project to the lowest PHP version of the module; PhpStorm uses its newest
    version for new projects and then suggests functions the module cannot use (for example array_any() of PHP 8.4)."""
    if level is None:
        return php
    component = re.search(r'<component name="PhpProjectSharedConfiguration"([^>]*?)(/?)>', php)
    name = 'name="PhpProjectSharedConfiguration"'
    if component is None:
        element = f'  <component {name} php_language_level="{level}" />\n'
        return php.replace("</project>", element + "</project>", 1)
    attributes = re.sub(r'\s*php_language_level="[^"]*"', "", component.group(1)).rstrip()
    closing = " />" if component.group(2) else ">"
    element = f'<component {name}{attributes} php_language_level="{level}"{closing}'
    return php[:component.start()] + element + php[component.end():]


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


def js_libraries() -> dict[str, list[str]]:
    """Returns the files of every library in js-libraries.xml by library name."""
    source = (TEMPLATE_PATH / "js-libraries.xml").read_text(encoding="utf-8")
    source = re.sub(r"<!--.*?-->", "", source, flags=re.S)
    return {
        match.group(1): re.findall(r'<file path="([^"]+)"', match.group(2))
        for match in re.finditer(r'<library name="([^"]+)">(.*?)</library>', source, re.S)
    }


def js_library(name: str, files: list[str]) -> str:
    urls = [f"file://$PROJECT_DIR$/{path}" for path in files]
    return (
        '<component name="libraryTable">\n'
        f'  <library name="{name}" type="javaScript">\n'
        "    <properties>\n"
        "      <sourceFilesUrls>\n"
        + "".join(f'        <item url="{url}" />\n' for url in urls)
        + "      </sourceFilesUrls>\n"
        "    </properties>\n"
        "    <CLASSES>\n"
        + "".join(f'      <root url="{url}" />\n' for url in urls)
        + "    </CLASSES>\n"
        "    <SOURCES />\n"
        "  </library>\n"
        "</component>\n"
    )


def apply_js_library_mappings(mappings: str, names: list[str]) -> str:
    if not mappings:
        mappings = (
            '<?xml version="1.0" encoding="UTF-8"?>\n<project version="4">\n'
            '  <component name="JavaScriptLibraryMappings">\n'
            '    <file url="PROJECT" libraries="{}" />\n'
            "  </component>\n</project>\n"
        )
    project = re.search(r'<file url="PROJECT" libraries="\{([^}]*)\}" />', mappings)
    if project is None:
        return mappings.replace(
            '<component name="JavaScriptLibraryMappings">',
            '<component name="JavaScriptLibraryMappings">\n    <file url="PROJECT" libraries="{'
            + ", ".join(names) + '}" />',
            1,
        )
    libraries = [library.strip() for library in project.group(1).split(",") if library.strip()]
    libraries += [name for name in names if name not in libraries]
    return mappings.replace(project.group(0), '<file url="PROJECT" libraries="{' + ", ".join(libraries) + '}" />', 1)


def uncorrected_schemas(directory: Path, resources: str) -> list[str]:
    """Returns the Magento schemas of the module's vendor folder that PhpStorm cannot load and the catalog does not map
    to a corrected copy: a type in xs:redefine has to extend or restrict itself, which Magento does not always do
    (Xerces in PhpStorm rejects such a schema in every file that uses it, libxml in Magento accepts it)."""
    vendor = directory / "vendor" / "magento"
    if not vendor.is_dir():
        return []
    found = []
    for xsd in sorted(list((vendor / "framework").rglob("*.xsd")) + list(vendor.glob("module-*/etc/**/*.xsd"))):
        source = xsd.read_text(encoding="utf-8", errors="replace")
        for redefine in re.finditer(r"<xs:redefine\b.*?</xs:redefine>", source, re.S):
            for type_match in re.finditer(r'<xs:(complexType|simpleType)\s+name="([^"]+)".*?</xs:\1>',
                                          redefine.group(0), re.S):
                bases = re.findall(r'<xs:(?:extension|restriction)\s+base="([^"]+)"', type_match.group(0))
                location = "$PROJECT_DIR$/" + xsd.relative_to(directory).as_posix()
                if bases and bases[0] != type_match.group(2) and f'location="{location}"' in resources:
                    found.append(f"{xsd.relative_to(directory)}: type {type_match.group(2)} extends {bases[0]}")
    return found


def missing_generated_classes(directory: Path) -> list[str]:
    """Returns the factories and proxies that the module imports and that are neither a class of the module or of its
    vendor folder nor generated in generated/code: Magento generates them on first use or with setup:di:compile, and
    PhpStorm reports their imports as "Undefined class" until they are generated."""
    psr4_file = directory / "vendor" / "composer" / "autoload_psr4.php"
    if not psr4_file.is_file() or not (directory / "src").is_dir():
        return []
    prefixes = [(prefix.replace("\\\\", "\\"), directory / "vendor" / path.lstrip("/"))
                for prefix, path in re.findall(r"'([^']+)' => array\(\$vendorDir \. '([^']+)'",
                                               psr4_file.read_text(encoding="utf-8"))]
    composer_file = directory / "composer.json"
    if composer_file.is_file():
        autoload = json.loads(composer_file.read_text(encoding="utf-8")).get("autoload", {}).get("psr-4", {})
        prefixes += [(prefix, directory / path) for prefix, path in autoload.items() if isinstance(path, str)]
    prefixes.sort(key=lambda entry: len(entry[0]), reverse=True)
    missing = []
    for php in sorted((directory / "src").rglob("*.php")):
        source = php.read_text(encoding="utf-8", errors="replace")
        for class_name in re.findall(r"^use\s+\\?([\w\\]+(?:Factory|Proxy))(?:\s+as\s+\w+)?\s*;", source, re.M):
            relative = class_name.replace("\\", "/") + ".php"
            if (directory / "generated" / "code" / relative).is_file():
                continue
            if any(class_name.startswith(prefix) and (path / (class_name[len(prefix):].replace("\\", "/") + ".php"))
                   .is_file() for prefix, path in prefixes):
                continue
            missing.append(f"{php.relative_to(directory)}: {class_name}")
    return sorted(set(missing))


def apply_composer_settings(workspace: str) -> str:
    """Switches the Composer synchronization off in the workspace (written by PhpStorm when it opens the project)."""
    if not workspace:
        return workspace
    component = re.search(r'<component name="ComposerSettings"[^>]*?(/?)>', workspace)
    if not component:
        return workspace.replace(
            "</project>", '  <component name="ComposerSettings" synchronizationState="DONT_SYNCHRONIZE" />\n</project>', 1
        )
    element = component.group(0)
    if 'synchronizationState="' in element:
        updated = re.sub(r'synchronizationState="[^"]*"', 'synchronizationState="DONT_SYNCHRONIZE"', element)
    else:
        updated = element.replace('name="ComposerSettings"', 'name="ComposerSettings" synchronizationState="DONT_SYNCHRONIZE"')
    return workspace.replace(element, updated, 1)


def coding_standard(directories: list[Path]) -> Path | None:
    """The Magento coding standard of MAGENTO_ROOT or of the vendor folder of one of the modules."""
    roots = ([Path(os.environ["MAGENTO_ROOT"])] if os.environ.get("MAGENTO_ROOT") else []) + directories
    for root in roots:
        standard = root / "vendor" / "magento" / "magento-coding-standard"
        if (standard / "eslint" / "eslint.config.mjs").is_file() and (standard / "package-lock.json").is_file():
            return standard
    return None


def install_eslint(directories: list[Path], check: bool) -> bool:
    """Installs the ESLint rules of the Magento coding standard with their npm packages into ESLINT_PATH, if they are
    missing or the coding standard has another package-lock.json; returns whether they are installed."""
    installed = (ESLINT_PATH / "node_modules" / "eslint").is_dir()
    standard = coding_standard(directories)
    lock = ESLINT_PATH / "package-lock.json"
    if standard is None or check or (installed and lock.is_file()
                                     and lock.read_bytes() == (standard / "package-lock.json").read_bytes()):
        if not installed:
            print("ESLint is not installed: needs the Magento coding standard (vendor/magento/magento-coding-standard of"
                  " a module with a running development environment, or MAGENTO_ROOT) and npm")
        return installed
    ESLINT_PATH.mkdir(exist_ok=True)
    shutil.rmtree(ESLINT_PATH / "eslint", ignore_errors=True)
    shutil.copytree(standard / "eslint", ESLINT_PATH / "eslint")
    for name in ("package.json", "package-lock.json"):
        shutil.copyfile(standard / name, ESLINT_PATH / name)
    result = subprocess.run(["npm", "ci", "--no-audit", "--no-fund", "--no-update-notifier", "--loglevel=error"],
                            cwd=ESLINT_PATH)
    if result.returncode != 0:
        print(f"Could not install the npm packages of the Magento coding standard into {ESLINT_PATH}")
        return False
    print(f"Installed ESLint with the rules of the Magento coding standard into {ESLINT_PATH}")
    return True


def eslint_config(directory: Path) -> str:
    """The ESLint configuration of the module: the rules of the Magento coding standard, without the folders of the
    Magento installation and without bundled libraries (JavaScript files without the copyright header)."""
    ignores = ["**/vendor/**", "**/generated/**", "**/pub/**", "**/var/**", "**/app/**", "**/.idea/**"]
    for path in sorted((directory / "src").rglob("*.js")):
        if "Andreas Knollmann" not in path.read_text(encoding="utf-8", errors="replace")[:1000]:
            ignores.append("**/" + path.relative_to(directory).as_posix())
    entries = "".join(f"            '{ignore}',\n" for ignore in ignores)
    return ("// ESLint configuration of PhpStorm, written by tools/configure-phpstorm.py of the workflows: the rules of the\n"
            "// Magento coding standard, which tools/check-eslint.sh applies in the checks, without bundled libraries.\n"
            "import config from '../../workflows/.eslint/eslint/eslint.config.mjs';\n\n"
            "export default [\n    {\n        ignores: [\n" + entries.rstrip(",\n") + "\n        ]\n    }\n].concat(config);\n")


def ide_path(path: str) -> str:
    """The path as PhpStorm on Windows sees a path in WSL (//wsl.localhost/<distribution>/...)."""
    distribution = os.environ.get("WSL_DISTRO_NAME")
    return f"//wsl.localhost/{distribution}{path}" if distribution else path


def apply_eslint_properties(workspace: str) -> str:
    """Sets the ESLint package of ESLINT_PATH and the Node.js of WSL in the properties of the workspace."""
    if not workspace:
        return workspace
    properties = {
        "node.js.detected.package.eslint": "true",
        # PhpStorm writes the package as Windows path with backslashes, the interpreter with slashes
        "node.js.selected.package.eslint": ide_path(str(ESLINT_PATH / "node_modules" / "eslint")).replace("/", "\\"),
        "nodejs_interpreter_path": ide_path(NODE_PATH),
    }
    component = re.search(r'(<component name="PropertiesComponent"><!\[CDATA\[)(.*?)(\]\]></component>)', workspace, re.S)
    if not component:
        content = json.dumps({"keyToString": properties}, indent=2)
        return workspace.replace(
            "</project>", f'  <component name="PropertiesComponent"><![CDATA[{content}]]></component>\n</project>', 1)
    data = json.loads(component.group(2))
    key_to_string = data.setdefault("keyToString", {})
    if all(key_to_string.get(key) == value for key, value in properties.items()):
        return workspace
    key_to_string.update(properties)
    data["keyToString"] = dict(sorted(key_to_string.items()))
    return workspace[:component.start(2)] + json.dumps(data, indent=2) + workspace[component.end(2):]


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
    words = dictionary()
    scope_files = scopes()
    resources = project_resources()
    entries = entry_points()
    index, exclude = module_folders()
    libraries = js_libraries()
    index = index + library_folders(libraries, index)
    unchecked = unchecked_exceptions()
    eslint = install_eslint(directories, check)
    outdated = False
    schema_problems = False

    for directory in directories:
        idea = directory / ".idea"
        if not idea.is_dir():
            print(f"Skipping {directory}: no .idea folder")
            continue

        files = {
            idea / "inspectionProfiles" / "Project_Default.xml": lambda s: apply_inspections(s or EMPTY_PROFILE, tools),
            idea / "inspectionProfiles" / "profiles_settings.xml": lambda s: settings,
            idea / "dictionaries" / "magento.xml": lambda s: words,
            idea / "misc.xml": lambda s, own=infrangible_resources(directory, resources): apply_component(
                apply_component(s or EMPTY_MISC, "PhpEntryPointsManager", entries), "ProjectResources", own),
            idea / "php.xml": lambda s, level=php_language_level(directory): apply_language_level(
                apply_unchecked_exceptions(apply_include_path(s or EMPTY_PHP, STUBS_INCLUDE_PATH), unchecked), level),
        }
        for file_name, scope in scope_files.items():
            files[idea / "scopes" / file_name] = lambda s, scope=scope: scope
        for name, library_files in libraries.items():
            files[idea / "libraries" / (re.sub(r"\W", "_", name) + ".xml")] = (
                lambda s, library=js_library(name, library_files): library
            )
        files[idea / "jsLibraryMappings.xml"] = lambda s: apply_js_library_mappings(s, list(libraries))
        files[idea / "workspace.xml"] = (
            (lambda s: apply_eslint_properties(apply_composer_settings(s))) if eslint else apply_composer_settings
        )
        if eslint:
            files[idea / "eslint.config.mjs"] = lambda s, config=eslint_config(directory): config
            files[idea / "jsLinters" / "eslint.xml"] = lambda s: ESLINT_XML
        for iml in sorted(idea.glob("*.iml")):
            files[iml] = lambda s: apply_folders(s, index, exclude, directory)
        for schema in uncorrected_schemas(directory, resources):
            print(f"Schema without corrected copy in templates/phpstorm/schemas: {schema}")
            schema_problems = True
        for generated in missing_generated_classes(directory):
            print(f"Not generated, run bin/magento setup:di:compile in the environment: {generated}")
            schema_problems = True
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

    return 1 if (check and outdated) or schema_problems else 0


if __name__ == "__main__":
    sys.exit(main())
