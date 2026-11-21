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
use PhpParser\Node\Stmt;
use PHPStan\Analyser\Scope;
use PHPStan\Reflection\ReflectionProvider;
use PHPStan\Rules\Rule;
use PHPStan\Rules\RuleErrorBuilder;
use PHPStan\Type\FileTypeMapper;
use PHPStan\Type\VerbosityLevel;

/**
 * An inline @var tag of an assignment that specifies the type that the assigned value already has.
 *
 * PhpStorm reports it as "@var tag specifies the type already inferred from source code". Like PhpStorm, the declared
 * types count, also those of docblocks, for example "@var Item[] $items" above "$items = $quote->getAllVisibleItems();".
 * Not for calls of functions with template types, whose declaration can depend on the version of Magento.
 *
 * @implements Rule<Stmt\Expression>
 */
class RedundantVarTagRule implements Rule
{
    public function __construct(
        private readonly FileTypeMapper $fileTypeMapper,
        private readonly ReflectionProvider $reflectionProvider
    ) {
    }

    public function getNodeType(): string
    {
        return Stmt\Expression::class;
    }

    /**
     * @param Stmt\Expression $node
     *
     * @return list<\PHPStan\Rules\IdentifierRuleError>
     */
    public function processNode(Node $node, Scope $scope): array
    {
        $docComment = $node->getDocComment();

        if ($docComment === null || ! $node->expr instanceof Expr\Assign ||
            ! $node->expr->var instanceof Expr\Variable || ! is_string($node->expr->var->name)) {

            return [];
        }

        $variableName = $node->expr->var->name;

        $varTags = $this->fileTypeMapper->getResolvedPhpDoc(
            $scope->getFile(),
            $scope->getClassReflection()?->getName(),
            $scope->getTraitReflection()?->getName(),
            $scope->getFunction()?->getName(),
            $docComment->getText()
        )->getVarTags();

        if (! isset($varTags[ $variableName ])) {
            return [];
        }

        if ($this->callsGenericFunction($node->expr->expr, $scope)) {
            return [];
        }

        $varType = $varTags[ $variableName ]->getType();
        $valueType = $scope->getType($node->expr->expr);

        if (! $varType->isSuperTypeOf($valueType)->yes() || ! $valueType->isSuperTypeOf($varType)->yes()) {
            return [];
        }

        return [
            RuleErrorBuilder::message(
                sprintf(
                    'The @var tag of $%s is redundant, the assigned value already has the type %s.',
                    $variableName,
                    $valueType->describe(VerbosityLevel::typeOnly())
                )
            )->identifier('infrangible.redundantVarTag')->build()
        ];
    }

    /**
     * Checks if the expression calls a function or method with template types, whose result type depends on its
     * arguments.
     *
     * Such a declaration can be new in a version of Magento (LayoutInterface::createBlock() returns the created class
     * since 2.4.9), the tag is needed for the older versions.
     *
     * @param Expr $expression
     * @param Scope $scope
     *
     * @return bool
     */
    private function callsGenericFunction(Expr $expression, Scope $scope): bool
    {
        $reflection = null;

        if ($expression instanceof Expr\MethodCall && $expression->name instanceof Node\Identifier) {
            $type = $scope->getType($expression->var);

            if ($type->hasMethod($expression->name->toString())->yes()) {
                $reflection = $type->getMethod($expression->name->toString(), $scope);
            }
        } elseif ($expression instanceof Expr\StaticCall && $expression->class instanceof Node\Name &&
            $expression->name instanceof Node\Identifier) {

            $type = $scope->resolveTypeByName($expression->class);

            if ($type->hasMethod($expression->name->toString())->yes()) {
                $reflection = $type->getMethod($expression->name->toString(), $scope);
            }
        } elseif ($expression instanceof Expr\FuncCall && $expression->name instanceof Node\Name &&
            $this->reflectionProvider->hasFunction($expression->name, $scope)) {

            $reflection = $this->reflectionProvider->getFunction($expression->name, $scope);
        }

        if ($reflection === null) {
            return false;
        }

        foreach ($reflection->getVariants() as $variant) {
            if (! $variant->getTemplateTypeMap()->isEmpty()) {
                return true;
            }
        }

        return false;
    }
}
