#!/usr/bin/env bash
# Checks a module for duplicated code with PHPCPD (maintained fork systemsdk/phpcpd, PHP 8.4 or newer), like the
# PhpStorm inspection "Duplicated code fragment": at least 5 identical lines and 100 tokens, with variable names
# ignored (--fuzzy). Move duplicated code into a shared method or base class, and merge tests that only differ in
# their data into one test with a data provider.
#
# Usage: tools/check-duplicated-code.sh <module directory> [<phpcpd binary>, default: phpcpd]
#
# Install phpcpd in a container with Cosyses: cosyses PHPCPD 9.2

set -u

moduleDir="${1:?Usage: $0 <module directory> [<phpcpd binary>]}"
phpcpd="${2:-phpcpd}"

if [[ ! -x "$(command -v "${phpcpd}")" ]]; then
  >&2 echo "phpcpd not found: ${phpcpd}"
  exit 1
fi

"${phpcpd}" --fuzzy "${moduleDir}/src"
