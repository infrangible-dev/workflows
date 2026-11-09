<?php

/**
 * Rector configuration of tools/check-php-syntax.sh: reports code that PHP 8.2 writes shorter or safer (constructor
 * property promotion, readonly properties, null coalescing assignment, arrow functions, ...).
 *
 * Environment variables:
 *   MODULE_DIR    directory of the module, its src folder is checked
 *   MAGENTO_ROOT  Magento installation with the dependencies of the module
 */

declare(strict_types=1);

use Rector\CodingStyle\Rector\FuncCall\FunctionFirstClassCallableRector;
use Rector\Config\RectorConfig;
use Rector\Php70\Rector\FuncCall\RandomFunctionRector;
use Rector\Php80\Rector\Ternary\TernaryToNullsafeCoalesceRector;

$moduleDir = rtrim((string)getenv('MODULE_DIR'), '/');
$magentoRoot = rtrim((string)getenv('MAGENTO_ROOT'), '/');

// Rector only knows the classes of the checked paths and of the scanned paths; without the dependencies, it treats
// their classes as unknown and skips for example the promotion of properties with these types
$scan = [$magentoRoot . '/vendor/autoload.php'];
$composer = json_decode((string)file_get_contents($moduleDir . '/composer.json'), true);
foreach (array_keys($composer['require'] ?? []) as $package) {
    if (is_dir($magentoRoot . '/vendor/' . $package)) {
        $scan[] = $magentoRoot . '/vendor/' . $package;
    }
}
// factories and proxies, only available after setup:di:compile
if (is_dir($magentoRoot . '/generated/code')) {
    $scan[] = $magentoRoot . '/generated/code';
}

return RectorConfig::configure()
    ->withPaths([$moduleDir . '/src'])
    ->withAutoloadPaths($scan)
    ->withPhpSets(php82: true)
    ->withSkip([
        // Magento PHPCS discourages intval(), strval() etc., so the string callables are kept
        FunctionFirstClassCallableRector::class,
        // rand() is no security function in the modules, random_int() would throw RandomException
        RandomFunctionRector::class,
        // $x?->get() ?? $default also uses the default when get() returns null, for example a NULL value of fetchOne()
        TernaryToNullsafeCoalesceRector::class,
    ]);
