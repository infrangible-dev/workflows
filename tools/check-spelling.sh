#!/usr/bin/env bash
# Checks the spelling of a module with cspell, like the PhpStorm inspection "Typo": words in code, comments, texts and
# documentation must be English words, terms of the dictionaries of cspell (PHP, HTML, CSS, JavaScript, software
# terms) or in templates/spelling/words.txt. Translations (i18n), generated files and minified files (lines longer
# than 500 characters) are skipped. Fix the spelling, or add a correctly spelled term to templates/spelling/words.txt;
# tools/configure-phpstorm.py writes the same words into the PhpStorm dictionary.
#
# Usage: tools/check-spelling.sh <module directory> [<cspell binary>, default: cspell]
#
# Install cspell in a container with Cosyses: cosyses Node.js 24.13 && cosyses CSpell 10.4

set -u

moduleDir="${1:?Usage: $0 <module directory> [<cspell binary>]}"
cspell="${2:-cspell}"
config="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/templates/spelling/cspell.json"

if [[ ! -x "$(command -v "${cspell}")" ]]; then
  >&2 echo "cspell not found: ${cspell}"
  exit 1
fi

cd "${moduleDir}" || exit 1

# the files of the module without the directories of a development environment and without minified files
find . -type d \( -name .git -o -name .idea -o -name vendor -o -name generated -o -name pub -o -name var \
  -o -path ./app \) -prune -o -type f -print0 \
  | while IFS= read -r -d '' file; do
      awk 'length > 500 { found = 1; exit } END { exit found }' "${file}" && echo "${file}"
    done \
  | "${cspell}" lint --no-progress --no-summary --no-must-find-files --config "${config}" --file-list stdin
