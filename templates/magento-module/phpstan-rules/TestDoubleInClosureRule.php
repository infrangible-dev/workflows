<?php

declare(strict_types=1);

/**
 * @author      Andreas Knollmann
 * @copyright   Copyright (c) 2014-2026 Softwareentwicklung Andreas Knollmann
 * @license     http://www.opensource.org/licenses/mit-license.php MIT
 */

namespace Infrangible\PhpStan;

use PhpParser\Node;
use PhpParser\Node\Expr;
use PHPStan\Analyser\Scope;
use PHPStan\Rules\Rule;
use PHPStan\Rules\RuleErrorBuilder;

/**
 * A test double of PHPUnit created inside a closure.
 *
 * Inside a closure, PhpStorm does not resolve the template type of createStub() and createMock() for generated classes
 * like factories, and reports "Expected parameter of type 'XFactory', 'object&Stub|Stub' provided". Create the test
 * doubles before the closure and pass them with "use".
 *
 * @implements Rule<Expr>
 */
class TestDoubleInClosureRule implements Rule
{
    private const METHODS = [
        'createstub',
        'createmock',
        'createpartialmock',
        'createconfiguredmock',
        'createconfiguredstub',
        'getmockbuilder'
    ];

    public function getNodeType(): string
    {
        return Expr::class;
    }

    /**
     * @param Expr $node
     *
     * @return list<\PHPStan\Rules\IdentifierRuleError>
     */
    public function processNode(Node $node, Scope $scope): array
    {
        if (! ($node instanceof Expr\MethodCall || $node instanceof Expr\StaticCall) ||
            ! $node->name instanceof Node\Identifier ||
            ! in_array($node->name->toLowerString(), self::METHODS, true) || ! $scope->isInAnonymousFunction()) {

            return [];
        }

        return [
            RuleErrorBuilder::message(
                sprintf(
                    'Create the test double of %s() before the closure and pass it with "use": PhpStorm does not ' .
                    'resolve its type inside a closure.',
                    $node->name->toString()
                )
            )->identifier('infrangible.testDoubleInClosure')->build()
        ];
    }
}
