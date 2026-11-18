#!/bin/bash -e

# Reports deprecated classes, methods, constants and properties (of Magento, other packages or the module itself) that a
# module uses, found with PHPStan and phpstan/phpstan-deprecation-rules. Each one has to be replaced, or, if it cannot
# be avoided (for example a constructor argument that a Magento parent class requires), suppressed for PhpStorm with a
# reason:
#
#   * @noinspection PhpDeprecationInspection Magento's grid, which the parent class extends, needs the backend helper.
#
# The suppression covers the declaration or statement that follows it, or the whole file directly after "<?php", see
# check-deprecations.php. Imports ("use") of deprecated classes count as well, as in PhpStorm; a file that imports one
# needs the suppression for the whole file.
#
# Usage:
#   check-deprecations.sh <tool directory> <module directory> <Magento directory>
#
#   tool directory     Composer project with phpstan/phpstan-deprecation-rules (and with it PHPStan 2), created for
#                      example with: cosyses PHPStanDeprecationRules 2.0 (in /usr/local/lib/composer-tools/
#                      phpstan-deprecation-rules) or composer require --working-dir <tool directory>
#                      phpstan/phpstan-deprecation-rules
#   module directory   the module with src/
#   Magento directory  a Magento installation that contains the dependencies of the module

if [[ "$#" -ne 3 ]]; then
  >&2 echo "Usage: ${0##*/} <tool directory> <module directory> <Magento directory>"
  exit 1
fi

toolDirectory=$(cd "${1}" && pwd)
moduleDirectory=$(cd "${2}" && pwd)
magentoDirectory=$(cd "${3}" && pwd)
scriptPath=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
stubFile="${scriptPath}/../templates/phpstorm/stubs/phpunit.php"

for requiredFile in "${toolDirectory}/vendor/bin/phpstan" \
  "${toolDirectory}/vendor/phpstan/phpstan-deprecation-rules/rules.neon" \
  "${magentoDirectory}/vendor/autoload.php" "${moduleDirectory}/src"; do
  if [[ ! -e "${requiredFile}" ]]; then
    >&2 echo "Not found: ${requiredFile}"
    exit 1
  fi
done

workDirectory=$(mktemp -d)
trap 'rm -rf "${workDirectory:?}"' EXIT

# Magento comes with PHPStan 1, the rules need PHPStan 2; the autoloader of Magento is loaded before PHPStan starts
cat > "${workDirectory}/prepend.php" << EOF
<?php
require '${magentoDirectory}/vendor/autoload.php';
EOF

cat > "${workDirectory}/deprecations.neon" << EOF
includes:
    - ${toolDirectory}/vendor/phpstan/phpstan-deprecation-rules/rules.neon
parameters:
    # only the deprecation rules, the other checks run with the configuration of the module
    level: 0
    paths:
        - ${moduleDirectory}/src
    fileExtensions:
        - php
        - phtml
    bootstrapFiles:
        - ${magentoDirectory}/dev/tests/static/framework/Magento/PhpStan/autoload.php
    scanFiles:
        - ${stubFile}
EOF

cd "${workDirectory}"
php -d "auto_prepend_file=${workDirectory}/prepend.php" -d memory_limit=-1 \
  "${toolDirectory}/vendor/bin/phpstan" analyse -c "${workDirectory}/deprecations.neon" --no-progress --debug \
  --error-format=json > "${workDirectory}/result.txt" || true

# --debug (one process, the parallel workers of PHPStan 2 do not start with the autoloader of Magento's PHPStan 1)
# lists every analysed file before the result, only the result is of interest
grep '^{' "${workDirectory}/result.txt" > "${workDirectory}/result.json" || cat "${workDirectory}/result.txt" >&2

php "${scriptPath}/check-deprecations.php" "${moduleDirectory}" "${workDirectory}/result.json" "${magentoDirectory}"
