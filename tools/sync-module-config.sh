#!/bin/bash -e

# Copies the shared configuration of the Magento modules (templates/magento-module) into module directories, or checks
# whether the modules are up to date. Also requires the PHPStan configuration and rules of the modules
# (infrangible/phpstan-magento, in the version of phpstanPackageVersion below) in require-dev of composer.json, and
# removes the copies of the PHPStan files that were part of the templates before.
#
# Usage:
#   sync-module-config.sh [--check] <module directory> [<module directory> ...]
#
#   --check   only report modules whose files differ from the templates, exit with 1 if any differs
#
# Example for all modules next to this repository:
#   tools/sync-module-config.sh ../m2-*

scriptPath=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
templatePath="${scriptPath}/../templates/magento-module"

check=0
moduleDirectories=()
for argument in "$@"; do
  case "${argument}" in
    --check) check=1;;
    -h|--help) sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0;;
    -*) >&2 echo "Unknown option: ${argument}"; exit 1;;
    *) moduleDirectories+=( "${argument}" );;
  esac
done

if [[ "${#moduleDirectories[@]}" -eq 0 ]]; then
  >&2 echo "No module directory specified!"
  exit 1
fi

templateFiles=()
while IFS= read -r -d '' templateFile; do
  templateFiles+=( "${templateFile#"${templatePath}/"}" )
done < <(find "${templatePath}" -type f -print0 | sort -z)

# the version of infrangible/phpstan-magento that the modules require; raising it updates the modules at their next
# synchronization
phpstanPackage="infrangible/phpstan-magento"
phpstanPackageVersion="~1.2.0"

# files of earlier versions of the templates, now in infrangible/phpstan-magento
obsoleteFiles=(
  phpstan-rules
  phpstan.bootstrap.php
  phpstan.escaper.stub
  phpstan.rules.php
  phpstan.versions.php
)

outdated=0
for moduleDirectory in "${moduleDirectories[@]}"; do
  moduleDirectory="${moduleDirectory%/}"

  if [[ ! -f "${moduleDirectory}/composer.json" ]] || [[ ! -d "${moduleDirectory}/src" ]]; then
    echo "Skipping ${moduleDirectory}: no Magento module (composer.json and src expected)"
    continue
  fi

  for templateFile in "${templateFiles[@]}"; do
    target="${moduleDirectory}/${templateFile}"

    if [[ -f "${target}" ]] && cmp -s "${templatePath}/${templateFile}" "${target}"; then
      continue
    fi

    if [[ "${check}" == 1 ]]; then
      if [[ -f "${target}" ]]; then
        echo "Outdated: ${target}"
      else
        echo "Missing: ${target}"
      fi
      outdated=1
    else
      if [[ -f "${target}" ]]; then
        echo "Updating: ${target}"
      else
        echo "Adding: ${target}"
      fi
      mkdir -p "$(dirname "${target}")"
      cp "${templatePath}/${templateFile}" "${target}"
    fi
  done

  for obsoleteFile in "${obsoleteFiles[@]}"; do
    target="${moduleDirectory}/${obsoleteFile}"

    if [[ ! -e "${target}" ]]; then
      continue
    fi

    if [[ "${check}" == 1 ]]; then
      echo "Obsolete: ${target}"
      outdated=1
    else
      echo "Removing: ${target}"
      rm -rf "${target}"
    fi
  done

  # composer.json with 4 spaces as Composer writes it; the order of the other entries stays
  if ! python3 - "${moduleDirectory}/composer.json" "${phpstanPackage}" "${phpstanPackageVersion}" "${check}" <<'PY'
import json, sys
path, package, version, check = sys.argv[1:]
with open(path, encoding='utf-8') as file:
    composer = json.load(file)
if composer.get('require-dev', {}).get(package) == version:
    sys.exit(0)
if check == '1':
    print(f'Outdated: {path} (require-dev {package} {version})')
    sys.exit(1)
print(f'Updating: {path} (require-dev {package} {version})')
composer.setdefault('require-dev', {})[package] = version
if 'require' in composer:
    # require-dev after require, as Composer adds it
    ordered = {}
    for key, value in composer.items():
        if key != 'require-dev':
            ordered[key] = value
        if key == 'require':
            ordered['require-dev'] = composer['require-dev']
    composer = ordered
with open(path, 'w', encoding='utf-8') as file:
    file.write(json.dumps(composer, indent=4, ensure_ascii=False).replace('\\/', '/') + '\n')
PY
  then
    outdated=1
  fi
done

if [[ "${check}" == 1 ]] && [[ "${outdated}" == 1 ]]; then
  exit 1
fi
