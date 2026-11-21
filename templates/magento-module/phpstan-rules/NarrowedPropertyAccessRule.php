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
use PHPStan\Reflection\ReflectionProvider;
use PHPStan\Rules\IdentifierRuleError;
use PHPStan\Rules\Rule;
use PHPStan\Rules\RuleErrorBuilder;
use PHPStan\Type\Type;
use PHPStan\Type\TypeCombinator;

/**
 * A property or method of the value of a property that only exists after an instanceof check of the property.
 *
 * PHPStan narrows the type of "$node->expr" after "$node->expr instanceof Assign", PhpStorm only narrows variables: it
 * reports "$node->expr->var" as "Potentially polymorphic call. The code may be inoperable depending on the actual class
 * instance passed as the argument." when the declared type of the property (Expr) has no "var". Assign the property to
 * a variable before the check instead. PhpStorm narrows the properties of $this, and null checks are no polymorphism.
 *
 * @implements Rule<Expr>
 */
readonly class NarrowedPropertyAccessRule implements Rule
{
    public function __construct(private ReflectionProvider $reflectionProvider)
    {
    }

    public function getNodeType(): string
    {
        return Expr::class;
    }

    /**
     * @param Expr $node
     * @param Scope $scope
     *
     * @return list<IdentifierRuleError>
     */
    public function processNode(Node $node, Scope $scope): array
    {
        if (! ($node instanceof Expr\PropertyFetch || $node instanceof Expr\NullsafePropertyFetch ||
            $node instanceof Expr\MethodCall || $node instanceof Expr\NullsafeMethodCall) ||
            ! $node->name instanceof Node\Identifier) {

            return [];
        }

        $holder = $node->var;

        // PhpStorm narrows the properties of $this, but not of other variables
        if (! ($holder instanceof Expr\PropertyFetch || $holder instanceof Expr\NullsafePropertyFetch) ||
            ! $holder->name instanceof Node\Identifier ||
            ($holder->var instanceof Expr\Variable && $holder->var->name === 'this')) {

            return [];
        }

        $propertyName = $holder->name->toString();
        $declaredType = $this->getDeclaredPropertyType($scope->getType($holder->var), $propertyName, $scope);

        if ($declaredType === null) {
            return [];
        }

        // a null check is no polymorphism
        $declaredType = TypeCombinator::removeNull($declaredType);

        $memberName = $node->name->toString();
        $method = $node instanceof Expr\MethodCall || $node instanceof Expr\NullsafeMethodCall;
        $narrowedType = $scope->getType($holder);

        $declared = $method ? $declaredType->hasMethod($memberName) : $declaredType->hasProperty($memberName);
        $narrowed = $method ? $narrowedType->hasMethod($memberName) : $narrowedType->hasProperty($memberName);

        if ($declared->yes() || ! $narrowed->yes()) {
            return [];
        }

        return [
            RuleErrorBuilder::message(
                sprintf(
                    '%s %s only exists after the instanceof check of the property $%s, PhpStorm only narrows ' .
                    'variables. Assign $%s to a variable before the check.',
                    $method ? 'Method' : 'Property',
                    $method ? $memberName . '()' : '$' . $memberName,
                    $propertyName,
                    $propertyName
                )
            )->identifier('infrangible.narrowedPropertyAccess')->build()
        ];
    }

    /**
     * Returns the declared type of the property of the object type, or null if it is unknown.
     *
     * @param Type $objectType
     * @param string $propertyName
     * @param Scope $scope
     *
     * @return Type|null
     */
    private function getDeclaredPropertyType(Type $objectType, string $propertyName, Scope $scope): ?Type
    {
        $types = [];

        foreach ($objectType->getObjectClassNames() as $className) {
            if (! $this->reflectionProvider->hasClass($className)) {
                return null;
            }

            $class = $this->reflectionProvider->getClass($className);

            if (! $class->hasProperty($propertyName)) {
                return null;
            }

            $types[] = $class->getProperty($propertyName, $scope)->getReadableType();
        }

        return count($types) === 1 ? $types[ 0 ] : null;
    }
}
