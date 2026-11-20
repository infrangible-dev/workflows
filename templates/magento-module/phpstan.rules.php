<?php

declare(strict_types=1);

/**
 * PHPStan rules for the conventions of PhpStorm that PHPStan does not check itself (classes in phpstan-rules).
 *
 * Included by phpstan.neon as configuration, because PHPStan creates the rules before it loads the bootstrap files.
 *
 * @author      Andreas Knollmann
 * @copyright   Copyright (c) 2014-2026 Softwareentwicklung Andreas Knollmann
 * @license     http://www.opensource.org/licenses/mit-license.php MIT
 */

require_once __DIR__ . '/phpstan-rules/DefaultArgumentRule.php';
require_once __DIR__ . '/phpstan-rules/LoopToArrayMapRule.php';
require_once __DIR__ . '/phpstan-rules/NeverThrownCatchRule.php';
require_once __DIR__ . '/phpstan-rules/OnlyImplementationInstanceofRule.php';
require_once __DIR__ . '/phpstan-rules/OwnThrowsRule.php';
require_once __DIR__ . '/phpstan-rules/RedundantCastRule.php';

return [
    'rules' => [
        // a literal as last argument that is the default value of the parameter
        Infrangible\PhpStan\DefaultArgumentRule::class,
        // a foreach loop that only fills an empty array with one value per element
        Infrangible\PhpStan\LoopToArrayMapRule::class,
        // a catch of a checked exception that no call of the try block declares
        Infrangible\PhpStan\NeverThrownCatchRule::class,
        // an instanceof check against the only class of the module that implements the declared interface
        Infrangible\PhpStan\OnlyImplementationInstanceofRule::class,
        // checked exceptions declared only in the @throws tag of a parent method
        Infrangible\PhpStan\OwnThrowsRule::class,
        // a cast of a value that already has the type of the cast
        Infrangible\PhpStan\RedundantCastRule::class
    ]
];
