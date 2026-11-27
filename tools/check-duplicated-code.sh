#!/usr/bin/env bash
# Checks a module for duplicated code with PHPCPD (maintained fork systemsdk/phpcpd, PHP 8.4 or newer), like the
# PhpStorm inspection "Duplicated code fragment":
# - PHP code of the module: at least 5 identical lines and 100 tokens, with variable names ignored (--fuzzy). Move
#   duplicated code into a shared method or base class, and merge tests that only differ in their data into one test
#   with a data provider.
# - Templates (.phtml) of the module, also against the templates of the Infrangible modules it requires, which
#   PhpStorm compares as well: at least 5 identical lines and 50 tokens, as template code has fewer tokens per line.
#   Move the values a template computes into methods of its block.
#
# Usage: tools/check-duplicated-code.sh <module directory> [<phpcpd binary>, default: phpcpd]
#        [<Magento root with the required modules in vendor>, default: $MAGENTO_ROOT]
#
# Install phpcpd in a container with Cosyses: cosyses PHPCPD 9.2

set -u

moduleDir="${1:?Usage: $0 <module directory> [<phpcpd binary>] [<Magento root>]}"
phpcpd="${2:-phpcpd}"
magentoRoot="${3:-${MAGENTO_ROOT:-}}"

if [[ ! -x "$(command -v "${phpcpd}")" ]]; then
  >&2 echo "phpcpd not found: ${phpcpd}"
  exit 1
fi

result=0

"${phpcpd}" --fuzzy "${moduleDir}/src" || result=1

# the templates are copied into a folder of their own, as phpcpd cannot leave out the PHP files of the other modules
templateDir=$(mktemp -d)
trap 'rm -rf "${templateDir}"' EXIT

copyTemplates() {
  local sourceDir="${1}"
  local targetDir="${2}"
  local template
  while IFS= read -r -d '' template; do
    mkdir -p "${targetDir}/$(dirname "${template#"${sourceDir}/"}")"
    cp "${template}" "${targetDir}/${template#"${sourceDir}/"}"
  done < <(find "${sourceDir}" -name '*.phtml' -print0)
}

copyTemplates "${moduleDir}/src" "${templateDir}/module"

if [[ -z "$(find "${templateDir}/module" -name '*.phtml' -print -quit)" ]]; then
  exit "${result}"
fi

if [[ -n "${magentoRoot}" ]]; then
  while IFS= read -r package; do
    if [[ -d "${magentoRoot}/vendor/${package}/src" ]]; then
      copyTemplates "${magentoRoot}/vendor/${package}/src" "${templateDir}/required/${package}/src"
    else
      >&2 echo "Required module not found in ${magentoRoot}/vendor: ${package}"
    fi
  done < <(php -r '
    $composer = json_decode((string)file_get_contents($argv[1]), true);
    foreach (array_keys($composer["require"] ?? []) as $package) {
      if (str_starts_with($package, "infrangible/m2-")) {
        echo $package, PHP_EOL;
      }
    }' "${moduleDir}/composer.json")
fi

# only the clones with a template of the module; clones among the required modules are checked in their repositories
clones=$("${phpcpd}" --fuzzy --suffix .phtml --min-tokens 50 "${templateDir}" 2>&1 | awk -v module="${templateDir}/module/" '
  /^  - / { if (clone != "" && withModule) { print clone } clone = $0; withModule = index($0, module) > 0; next }
  /^    / && clone != "" { clone = clone "\n" $0; if (index($0, module) > 0) { withModule = 1 } next }
  { if (clone != "" && withModule) { print clone } clone = ""; withModule = 0 }
  END { if (clone != "" && withModule) { print clone } }')

if [[ -n "${clones}" ]]; then
  echo "Duplicated template code (module templates in ${moduleDir}/src, required modules in vendor):"
  echo "${clones}" | sed -e "s#${templateDir}/module/#src/#g" -e "s#${templateDir}/required/#vendor/#g"
  result=1
fi

exit "${result}"
