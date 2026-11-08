#!/bin/bash -e

# Copies the shared configuration of the Magento modules (templates/magento-module) into module directories, or checks
# whether the modules are up to date.
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
done

if [[ "${check}" == 1 ]] && [[ "${outdated}" == 1 ]]; then
  exit 1
fi
