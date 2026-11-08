#!/bin/bash -e

# Reports unused methods, constants and properties of a module with PHPStan and the dead code detector
# (shipmonk/dead-code-detector), including the Magento entry points of phpstan/dead-code/MagentoUsageProvider.php.
#
# Usage:
#   check-dead-code.sh <tool directory> <module directory> <Magento directory>
#
#   tool directory     Composer project with phpstan/phpstan ^2 and shipmonk/dead-code-detector, created for example
#                      with: composer require --working-dir <tool directory> phpstan/phpstan shipmonk/dead-code-detector
#   module directory   the module with src/ (PHP, templates and XML configuration)
#   Magento directory  a Magento installation that contains the dependencies of the module
#
# Magento's PHPStan 1 cannot be used, the detector needs PHPStan 2. The autoloader of Magento is loaded before PHPStan
# starts and the analysis runs in one process, so that the detector recognizes classes of Magento, PHPUnit and Symfony
# as vendor code, whose methods (setUp(), execute(), ...) are called from outside.

if [[ "$#" -ne 3 ]]; then
  >&2 echo "Usage: ${0##*/} <tool directory> <module directory> <Magento directory>"
  exit 1
fi

toolDirectory=$(cd "${1}" && pwd)
moduleDirectory=$(cd "${2}" && pwd)
magentoDirectory=$(cd "${3}" && pwd)
scriptPath=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
providerPath="${scriptPath}/../phpstan/dead-code"
stubFile="${scriptPath}/../templates/phpstorm/stubs/phpunit.php"

for requiredFile in "${toolDirectory}/vendor/bin/phpstan" "${toolDirectory}/vendor/shipmonk/dead-code-detector/rules.neon" \
  "${magentoDirectory}/vendor/autoload.php" "${moduleDirectory}/src"; do
  if [[ ! -e "${requiredFile}" ]]; then
    >&2 echo "Not found: ${requiredFile}"
    exit 1
  fi
done

workDirectory=$(mktemp -d)
trap 'rm -rf "${workDirectory:?}"' EXIT

cat > "${workDirectory}/prepend.php" << EOF
<?php
require '${magentoDirectory}/vendor/autoload.php';
// the classes of the module are loaded from the module directory, not from a copy in the vendor directory of Magento
// (as in CI), otherwise the detector would take them for vendor code
\$composer = json_decode((string)file_get_contents('${moduleDirectory}/composer.json'), true);
foreach (\$composer['autoload']['psr-4'] ?? [] as \$prefix => \$path) {
    spl_autoload_register(static function (string \$class) use (\$prefix, \$path): void {
        if (str_starts_with(\$class, \$prefix)) {
            \$file = '${moduleDirectory}/' . rtrim((string)\$path, '/') . '/' . str_replace('\\\\', '/', substr(\$class, strlen(\$prefix))) . '.php';
            if (is_file(\$file)) {
                require \$file;
            }
        }
    }, true, true);
}
// loaded when PHPStan creates the service, after PHPStan and the detector are available
spl_autoload_register(static function (string \$class): void {
    if (\$class === 'Infrangible\\\\Workflows\\\\DeadCode\\\\MagentoUsageProvider') {
        require '${providerPath}/MagentoUsageProvider.php';
    }
});
EOF

cat > "${workDirectory}/dead-code.neon" << EOF
includes:
    - ${toolDirectory}/vendor/shipmonk/dead-code-detector/rules.neon
parameters:
    # only the rules of the dead code detector, the other checks run with the configuration of the module
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
    shipmonkDeadCode:
        usageProviders:
            phpunit:
                enabled: true
            symfony:
                enabled: true
services:
    -
        class: Infrangible\Workflows\DeadCode\MagentoUsageProvider
        arguments:
            moduleDirectory: ${moduleDirectory}
        tags:
            - shipmonk.deadCode.memberUsageProvider
EOF

cd "${workDirectory}"
exitCode=0
php -d "auto_prepend_file=${workDirectory}/prepend.php" -d memory_limit=-1 \
  "${toolDirectory}/vendor/bin/phpstan" analyse -c "${workDirectory}/dead-code.neon" --no-progress --debug \
  --error-format=raw > "${workDirectory}/result.txt" 2>&1 || exitCode=$?

# --debug lists every analysed file, only the findings are of interest
grep -v -e "^${moduleDirectory}/src/[^:]*$" -e "^Running " "${workDirectory}/result.txt" | sed "s#^${moduleDirectory}/##" || true

if [[ "${exitCode}" -eq 0 ]]; then
  echo "No dead code found"
fi

exit "${exitCode}"
