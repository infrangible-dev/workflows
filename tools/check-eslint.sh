#!/usr/bin/env bash
# Checks the JavaScript of a module with the ESLint rules of the Magento coding standard (magento/magento-coding-standard,
# eslint/eslint.config.mjs), which the Adobe Commerce Marketplace applies besides PHPCS; PHPCS checks no JavaScript.
#
# Only the module's own files are checked (with the copyright header of Andreas Knollmann), not bundled libraries like
# select2.js, like the JavaScript checks of tools/check-code-conventions.sh. Warnings fail the check as well.
#
# ESLint only checks files below the directory of its configuration, so the files are copied into a temporary
# directory next to a configuration that loads the one of the coding standard; the findings name the files of the
# module. The packages of the coding standard (ESLint and its plugin) are installed with npm into a copy of the
# standard, which is kept in ESLINT_CACHE_DIR (default: ~/.cache/infrangible-eslint) for the next run.
#
# Usage: tools/check-eslint.sh <module directory> <Magento root> [--fix]
#
#   --fix   applies the fixes of ESLint ("eslint --fix") to the files of the module and reports what is left
#
# Needs Node.js and npm (install them in a container with Cosyses: cosyses Node.js 24.13).

set -u

moduleDir="${1:?Usage: $0 <module directory> <Magento root>}"
magentoRoot="${2:?Usage: $0 <module directory> <Magento root>}"
fix=()
if [[ "${3:-}" == "--fix" ]]; then
  fix=(--fix)
fi

if [[ ! -x "$(command -v npm)" ]]; then
  >&2 echo "npm not found, install Node.js"
  exit 1
fi

standard="${magentoRoot}/vendor/magento/magento-coding-standard"
if [[ ! -f "${standard}/eslint/eslint.config.mjs" ]]; then
  >&2 echo "ESLint configuration of the Magento coding standard not found in: ${standard}"
  exit 1
fi

moduleDir="$(cd "${moduleDir}" && pwd)"

# the files of the module itself
mapfile -t files < <(cd "${moduleDir}" && find src -name '*.js' -not -path '*/node_modules/*' -print0 |
  xargs -0 -r grep -l -m 1 'Andreas Knollmann' 2>/dev/null | sort)
if [[ "${#files[@]}" -eq 0 ]]; then
  echo "No JavaScript of the module"
  exit 0
fi

# the coding standard with its npm packages, installed once per version of its package-lock.json
cacheDir="${ESLINT_CACHE_DIR:-${HOME}/.cache/infrangible-eslint}"
lockHash=$(sha256sum "${standard}/package-lock.json" | cut -c1-16)
standardCopy="${cacheDir}/${lockHash}"
if [[ ! -d "${standardCopy}/node_modules" ]]; then
  mkdir -p "${standardCopy}"
  cp -r "${standard}/eslint" "${standard}/package.json" "${standard}/package-lock.json" "${standardCopy}/"
  if ! (cd "${standardCopy}" && npm ci --no-audit --no-fund --no-update-notifier --loglevel=error); then
    >&2 echo "Could not install the npm packages of the coding standard"
    exit 1
  fi
fi

workDir=$(mktemp -d "${standardCopy}/check.XXXXXX")
trap 'rm -rf "${workDir}"' EXIT
for file in "${files[@]}"; do
  mkdir -p "${workDir}/$(dirname "${file}")"
  cp "${moduleDir}/${file}" "${workDir}/${file}"
done
cat > "${workDir}/eslint.config.mjs" <<'CONFIG'
import config from '../eslint/eslint.config.mjs';

export default [{ignores: ['eslint.config.mjs']}].concat(config);
CONFIG

output=$(cd "${workDir}" && "${standardCopy}/node_modules/.bin/eslint" --max-warnings 0 "${fix[@]}" . 2>&1)
result=$?
if [[ "${#fix[@]}" -gt 0 ]]; then
  for file in "${files[@]}"; do
    cmp -s "${workDir}/${file}" "${moduleDir}/${file}" || cp "${workDir}/${file}" "${moduleDir}/${file}"
  done
fi
# the temporary directory in the findings is the module directory
echo "${output//${workDir}\//}"

if [[ "${result}" -ne 0 ]]; then
  message="Fix the JavaScript as shown above, it does not follow the ESLint rules of the Magento coding standard (many findings can be fixed with 'eslint --fix', see tools/check-eslint.sh)"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
  exit 1
fi
