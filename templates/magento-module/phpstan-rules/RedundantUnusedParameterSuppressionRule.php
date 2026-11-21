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
use PhpParser\NodeFinder;
use PHPStan\Analyser\Scope;
use PHPStan\Node\InClassMethodNode;
use PHPStan\Rules\Rule;
use PHPStan\Rules\RuleErrorBuilder;

/**
 * A suppression of unused parameters on a method that cannot have an unused parameter in the sense of PhpStorm.
 *
 * PhpStorm does not report unused parameters of methods that override or implement a method of a parent class or an
 * interface (the signature is given), and of course not if the method uses all its parameters. A
 * "@noinspection PhpUnusedParameterInspection" in the docblock of such a method is reported by PhpStorm as
 * "Redundant suppression".
 *
 * @implements Rule<InClassMethodNode>
 */
class RedundantUnusedParameterSuppressionRule implements Rule
{
    private const INSPECTION = 'PhpUnusedParameterInspection';

    public function getNodeType(): string
    {
        return InClassMethodNode::class;
    }

    /**
     * @param InClassMethodNode $node
     *
     * @return list<\PHPStan\Rules\IdentifierRuleError>
     */
    public function processNode(Node $node, Scope $scope): array
    {
        $method = $node->getOriginalNode();
        $docComment = $method->getDocComment();

        if ($docComment === null ||
            preg_match('/@noinspection\s+[^\n]*\b' . self::INSPECTION . '\b/', $docComment->getText()) !== 1) {

            return [];
        }

        $methodName = $method->name->toString();

        if ($this->overridesMethod($scope, $methodName)) {
            return [$this->buildError(sprintf('%s() overrides or implements a parent method', $methodName))];
        }

        if ($this->usesAllParameters($method)) {
            return [$this->buildError(sprintf('%s() uses all its parameters', $methodName))];
        }

        return [];
    }

    /**
     * Checks if the method overrides or implements a method of a parent class or an interface.
     *
     * @param Scope $scope
     * @param string $methodName
     *
     * @return bool
     */
    private function overridesMethod(Scope $scope, string $methodName): bool
    {
        $classReflection = $scope->getClassReflection();

        if ($classReflection === null || strtolower($methodName) === '__construct') {
            return false;
        }

        $parentClass = $classReflection->getParentClass();

        if ($parentClass !== null && $parentClass->hasMethod($methodName)) {
            return true;
        }

        foreach ($classReflection->getInterfaces() as $interface) {
            if ($interface->hasMethod($methodName)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Checks if the body of the method uses all parameters of the method.
     *
     * @param Node\Stmt\ClassMethod $method
     *
     * @return bool
     */
    private function usesAllParameters(Node\Stmt\ClassMethod $method): bool
    {
        if ($method->stmts === null || count($method->params) === 0) {
            return false;
        }

        $nodeFinder = new NodeFinder();

        $usedNames = array_map(
            static fn(Expr\Variable $variable): mixed => $variable->name,
            $nodeFinder->findInstanceOf($method->stmts, Expr\Variable::class)
        );

        foreach ($method->params as $param) {
            if ($param->var instanceof Expr\Variable && is_string($param->var->name) &&
                ! in_array($param->var->name, $usedNames, true)) {

                return false;
            }
        }

        return true;
    }

    /**
     * Returns the error for a redundant suppression.
     *
     * @param string $reason
     *
     * @return \PHPStan\Rules\IdentifierRuleError
     */
    private function buildError(string $reason): \PHPStan\Rules\IdentifierRuleError
    {
        return RuleErrorBuilder::message(
            sprintf(
                'The suppression of %s is redundant: %s, PhpStorm reports no unused parameter.',
                self::INSPECTION,
                $reason
            )
        )->identifier('infrangible.redundantUnusedParameterSuppression')->build();
    }
}
