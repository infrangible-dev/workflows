#!/usr/bin/env bash
# Checks with Rector that a module uses the syntax of PHP 8.2 (the minimum PHP version of the modules), for example
# constructor property promotion, readonly properties, null coalescing assignment and arrow functions. See
# templates/rector/rector.php for the rules that are skipped and why.
#
# To apply the changes instead of reporting them, run Rector with the same configuration without --dry-run:
#   MODULE_DIR=<module> MAGENTO_ROOT=<magento> rector process --config templates/rector/rector.php
# Constructor signatures are printed on one line, split them into one parameter per line afterwards (PHPCS line
# length).
#
# Usage: tools/check-php-syntax.sh <module directory> <Magento root> [<rector binary>, default: rector]
#
# Install Rector in a container with Cosyses: cosyses Rector 2.8

set -u

moduleDir="${1:?Usage: $0 <module directory> <Magento root> [<rector binary>]}"
magentoRoot="${2:?Usage: $0 <module directory> <Magento root> [<rector binary>]}"
rector="${3:-rector}"

if [[ ! -x "$(command -v "${rector}")" ]]; then
  >&2 echo "rector not found: ${rector}"
  exit 1
fi

config="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/templates/rector/rector.php"

MODULE_DIR="$(cd "${moduleDir}" && pwd)" MAGENTO_ROOT="$(cd "${magentoRoot}" && pwd)" \
  "${rector}" process --config "${config}" --dry-run --no-progress-bar --clear-cache
result=$?

if [[ "${result}" -ne 0 ]]; then
  message="Use the syntax of PHP 8.2 as shown above (see tools/check-php-syntax.sh how to apply it)"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::${message}"
  else
    echo "${message}" >&2
  fi
fi

exit "${result}"
