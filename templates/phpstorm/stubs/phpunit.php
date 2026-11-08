<?php

/**
 * Declarations for PhpStorm only, added as include path to every module by tools/configure-phpstorm.py; never loaded
 * by PHP, Composer or PHPUnit.
 *
 * The unit tests run with PHPUnit 9 (Magento 2.4.6) up to 12 (Magento 2.4.9) and use attributes of newer versions,
 * which older versions ignore. The development environment can have an older PHPUnit, so PhpStorm would report these
 * classes as undefined.
 */

namespace PHPUnit\Framework\Attributes;

use Attribute;

if (false) {
    /**
     * PHPUnit 12.5+: allows mock objects without configured expectations in a test class or method.
     */
    #[Attribute(Attribute::TARGET_CLASS | Attribute::TARGET_METHOD)]
    final class AllowMockObjectsWithoutExpectations
    {
    }

    /**
     * PHPUnit 10+: data provider of a test method.
     */
    #[Attribute(Attribute::TARGET_METHOD | Attribute::IS_REPEATABLE)]
    final class DataProvider
    {
        public function __construct(string $methodName)
        {
        }
    }
}
