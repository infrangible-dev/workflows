<?php

declare(strict_types=1);

/**
 * Loads the PHPStan autoloader of Magento, which generates factories and extension attributes for the analysis.
 *
 * The Magento installation is taken from the environment variable MAGENTO_ROOT, by default the one of the Anodosys
 * development environment.
 *
 * @author      Andreas Knollmann
 * @copyright   Copyright (c) 2014-2026 Softwareentwicklung Andreas Knollmann
 * @license     http://www.opensource.org/licenses/mit-license.php MIT
 */

$magentoRoot = getenv('MAGENTO_ROOT') ?: '/var/www/magento';

require rtrim($magentoRoot, '/') . '/dev/tests/static/framework/Magento/PhpStan/autoload.php';
