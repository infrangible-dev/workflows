<?php

declare(strict_types=1);

/**
 * @author      Andreas Knollmann
 * @copyright   Copyright (c) 2014-2026 Softwareentwicklung Andreas Knollmann
 * @license     http://www.opensource.org/licenses/mit-license.php MIT
 */

namespace Infrangible\PhpStan;

use PhpParser\Node;
use PhpParser\Node\Expr\Instanceof_;
use PhpParser\Node\Name;
use PHPStan\Analyser\Scope;
use PHPStan\Reflection\ReflectionProvider;
use PHPStan\Rules\Rule;
use PHPStan\Rules\RuleErrorBuilder;

/**
 * An instanceof check of a value whose declared type is an interface or abstract class of the module against the only
 * class of the module that implements it.
 *
 * PhpStorm knows all classes of the project and reports such a check as "Condition is always 'true' because '$x' is
 * evaluated at this point"; PHPStan only knows the declared type. Instead of the check, the interface should declare
 * the methods that the code needs.
 *
 * @implements Rule<Instanceof_>
 */
class OnlyImplementationInstanceofRule implements Rule
{
    /** @var array<string, list<string>> classes declared in the files of a module, by module directory */
    private array $moduleClasses = [];

    public function __construct(private readonly ReflectionProvider $reflectionProvider)
    {
    }

    public function getNodeType(): string
    {
        return Instanceof_::class;
    }

    /**
     * @param Instanceof_ $node
     *
     * @return list<\PHPStan\Rules\IdentifierRuleError>
     */
    public function processNode(Node $node, Scope $scope): array
    {
        if (! $node->class instanceof Name) {
            return [];
        }

        $checkedClassName = $scope->resolveName($node->class);
        $declaredClassNames = $scope->getType($node->expr)->getObjectClassNames();

        if (count($declaredClassNames) !== 1 || ! $this->reflectionProvider->hasClass($checkedClassName) ||
            ! $this->reflectionProvider->hasClass($declaredClassNames[ 0 ])) {

            return [];
        }

        $declaredClass = $this->reflectionProvider->getClass($declaredClassNames[ 0 ]);
        $checkedClass = $this->reflectionProvider->getClass($checkedClassName);

        if (! ($declaredClass->isInterface() || $declaredClass->isAbstract()) || $checkedClass->isInterface() ||
            ! $checkedClass->isSubclassOf($declaredClass->getName())) {

            return [];
        }

        $moduleDirectory = $this->getModuleDirectory($scope->getFile());

        if ($moduleDirectory === null) {
            return [];
        }

        $moduleClassNames = $this->getModuleClasses($moduleDirectory);

        if (! in_array($declaredClass->getName(), $moduleClassNames, true)) {
            return [];
        }

        foreach ($moduleClassNames as $moduleClassName) {
            if ($moduleClassName === $checkedClass->getName() ||
                ! $this->reflectionProvider->hasClass($moduleClassName)) {

                continue;
            }

            $moduleClass = $this->reflectionProvider->getClass($moduleClassName);

            if (! $moduleClass->isInterface() && ! $moduleClass->isAbstract() &&
                $moduleClass->isSubclassOf($declaredClass->getName()) &&
                ! $moduleClass->isSubclassOf($checkedClass->getName())) {

                return [];
            }
        }

        return [
            RuleErrorBuilder::message(
                sprintf(
                    'Instanceof %s is always true: it is the only class of the module that implements %s. Declare ' .
                    'the needed methods in %s instead.',
                    $checkedClass->getName(),
                    $declaredClass->getName(),
                    $declaredClass->getName()
                )
            )->identifier('infrangible.onlyImplementationInstanceof')->build()
        ];
    }

    /**
     * Returns the directory of the module of the file: the nearest directory above it with a composer.json.
     *
     * @param string $file
     *
     * @return string|null
     */
    private function getModuleDirectory(string $file): ?string
    {
        $directory = dirname($file);

        while ($directory !== dirname($directory)) {
            if (is_file($directory . '/composer.json')) {
                return $directory;
            }

            $directory = dirname($directory);
        }

        return null;
    }

    /**
     * Returns the names of the classes, interfaces and traits declared in the PHP files of the module.
     *
     * @param string $moduleDirectory
     *
     * @return list<string>
     */
    private function getModuleClasses(string $moduleDirectory): array
    {
        if (isset($this->moduleClasses[ $moduleDirectory ])) {
            return $this->moduleClasses[ $moduleDirectory ];
        }

        $classNames = [];
        $sourceDirectory = is_dir($moduleDirectory . '/src') ? $moduleDirectory . '/src' : $moduleDirectory;

        $files = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($sourceDirectory, \FilesystemIterator::SKIP_DOTS)
        );

        /** @var \SplFileInfo $file */
        foreach ($files as $file) {
            if ($file->getExtension() !== 'php' || str_contains($file->getPathname(), '/vendor/')) {
                continue;
            }

            $content = (string)file_get_contents($file->getPathname());

            $namespace = preg_match('/^namespace\s+([^;\s]+)\s*;/m', $content, $matches) === 1 ? $matches[ 1 ] : '';

            if (preg_match_all(
                '/^\s*(?:(?:abstract|final|readonly)\s+)*(?:class|interface|trait|enum)\s+(\w+)/m',
                $content,
                $matches
            )) {
                foreach ($matches[ 1 ] as $className) {
                    $classNames[] = ltrim($namespace . '\\' . $className, '\\');
                }
            }
        }

        return $this->moduleClasses[ $moduleDirectory ] = $classNames;
    }
}
