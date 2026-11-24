<?php

/**
 * Compares the deprecated code that PHPStan found (phpstan/phpstan-deprecation-rules, JSON output) with the
 * suppressions of PhpStorm's inspection in the module, see check-deprecations.sh.
 *
 * Usage: php check-deprecations.php <module directory> <PHPStan JSON result> [<Magento directory>]
 *
 * A suppression is a comment with "@noinspection PhpDeprecationInspection <reason>". It covers:
 *   - the whole file, if it directly follows the opening tag of the file
 *   - otherwise the declaration or statement that follows it: up to the end of the body of a class, function or block,
 *     or up to the semicolon of a statement or property
 *
 * Deprecated classes count where the module names them (types, new, extends, implements), not where it uses the members
 * of an object of such a class that are not deprecated themselves, as in PhpStorm. PhpStorm also reports the import of
 * a deprecated class ("use") and its name with "::class" (for example in createStub() of tests), which PHPStan does
 * not: with the Magento directory, these are checked as well, by the doc comment of the file of the class that
 * Composer's autoloader finds (without loading the class).
 *
 * Fails for deprecated code that no suppression covers and for suppressions without reason. Suppressions that cover no
 * deprecated code are reported as warnings, PhpStorm may know deprecations that PHPStan does not find.
 */

declare(strict_types=1);

if ($argc !== 3 && $argc !== 4) {
    fwrite(STDERR, "Usage: php check-deprecations.php <module directory> <PHPStan JSON result> [<Magento directory>]\n");
    exit(1);
}

$moduleDirectory = rtrim((string)realpath($argv[ 1 ]), '/');
$result = json_decode((string)file_get_contents($argv[ 2 ]), true);

if (! is_array($result)) {
    fwrite(STDERR, "No PHPStan result in: {$argv[2]}\n");
    exit(1);
}

foreach ($result[ 'errors' ] ?? [] as $error) {
    fwrite(STDERR, "PHPStan: $error\n");
}

/**
 * Returns the suppressions of a file.
 *
 * @return array<int, array{start: int, end: int, reason: string, used: bool}>
 */
function findSuppressions(string $code): array
{
    $tokens = token_get_all($code);
    $suppressions = [];

    foreach ($tokens as $index => $token) {
        if (! is_array($token) || ! in_array($token[ 0 ], [T_COMMENT, T_DOC_COMMENT], true)) {
            continue;
        }

        if (! preg_match('/@noinspection\s+[\w\s,]*?\bPhpDeprecationInspection\b([^\n]*)/', $token[ 1 ], $matches)) {
            continue;
        }

        // without the end of the comment and further inspections of the list ("PhpDeprecationInspection, PhpFoo")
        $reason = preg_replace(['#\*/\s*$#', '#^(\s*,\s*\w+)+#'], '', $matches[ 1 ]) ?? '';
        $reason = trim($reason, " \t*,");
        $startLine = $token[ 2 ];

        $suppressions[] = [
            'start'  => $startLine,
            'end'    => isFileStart($tokens, $index) ? PHP_INT_MAX : findScopeEnd($tokens, $index + 1, $startLine),
            'reason' => $reason,
            'used'   => false
        ];
    }

    return $suppressions;
}

/**
 * Tells whether the comment directly follows the opening tag at the start of the file.
 *
 * @param array<int, array{0: int, 1: string, 2: int}|string> $tokens
 */
function isFileStart(array $tokens, int $index): bool
{
    for ($previous = $index - 1; $previous >= 0; $previous--) {
        $token = $tokens[ $previous ];

        if (is_array($token) && $token[ 0 ] === T_WHITESPACE) {
            continue;
        }

        return $previous === 0 && is_array($token) && $token[ 0 ] === T_OPEN_TAG;
    }

    return false;
}

/**
 * Returns the last line of the declaration or statement that starts after the comment.
 *
 * @param array<int, array{0: int, 1: string, 2: int}|string> $tokens
 */
function findScopeEnd(array $tokens, int $index, int $line): int
{
    $depth = 0;
    $bodyDepth = null;
    $count = count($tokens);

    for (; $index < $count; $index++) {
        $token = $tokens[ $index ];
        $text = is_array($token) ? $token[ 1 ] : $token;

        if (is_array($token)) {
            $line = $token[ 2 ] + substr_count($text, "\n");
        }

        if (is_array($token) && in_array($token[ 0 ], [T_CURLY_OPEN, T_DOLLAR_OPEN_CURLY_BRACES, T_ATTRIBUTE], true)) {
            $depth++;
        } elseif ($text === '{') {
            if ($depth === 0 && $bodyDepth === null) {
                $bodyDepth = 0;
            }
            $depth++;
        } elseif ($text === '(' || $text === '[') {
            $depth++;
        } elseif ($text === '}' || $text === ')' || $text === ']') {
            $depth--;

            if ($text === '}' && $bodyDepth !== null && $depth === $bodyDepth) {
                return $line;
            }
            if ($depth < 0) {
                return $line;
            }
        } elseif ($text === ';' && $depth === 0 && $bodyDepth === null) {
            return $line;
        } elseif (is_array($token) && $token[ 0 ] === T_CLOSE_TAG && $depth === 0 && $bodyDepth === null) {
            return $line;
        }
    }

    return $line;
}

/**
 * Returns the classes, interfaces and traits that a file imports, with the line of the import.
 *
 * @return array<int, array{0: string, 1: int}>
 */
function findImports(string $code): array
{
    $tokens = token_get_all($code);
    $imports = [];
    $count = count($tokens);

    for ($index = 0; $index < $count; $index++) {
        $token = $tokens[ $index ];

        // imports are written before the class, use inside a class imports traits, in a closure variables
        if (is_array($token) && in_array($token[ 0 ], [T_CLASS, T_INTERFACE, T_TRAIT, T_ENUM], true)) {
            break;
        }

        if (! is_array($token) || $token[ 0 ] !== T_USE) {
            continue;
        }

        $line = $token[ 2 ];
        $name = '';

        for ($index++; $index < $count; $index++) {
            $part = $tokens[ $index ];

            if ($part === ';' || $part === ',' || (is_array($part) && $part[ 0 ] === T_AS)) {
                break;
            }
            if ($part === '{' || (is_array($part) && in_array($part[ 0 ], [T_FUNCTION, T_CONST], true))) {
                // group imports and imports of functions or constants are not checked
                $name = '';
                break;
            }
            if (is_array($part) && in_array($part[ 0 ], [T_NAME_QUALIFIED, T_NAME_FULLY_QUALIFIED, T_STRING], true)) {
                $name .= $part[ 1 ];
            }
        }

        if ($name !== '') {
            $imports[] = [ltrim($name, '\\'), $line];
        }
    }

    return $imports;
}

/**
 * Returns the classes that a file names with "::class", resolved with its namespace and imports, with their line;
 * PhpStorm reports them, PHPStan does not.
 *
 * @return array<int, array{0: string, 1: int}>
 */
function findClassNameReferences(string $code): array
{
    $tokens = array_values(
        array_filter(
            token_get_all($code),
            fn($token) => ! is_array($token) || ! in_array($token[ 0 ], [T_WHITESPACE, T_COMMENT, T_DOC_COMMENT], true)
        )
    );
    $namespace = '';
    $aliases = [];

    foreach (findImports($code) as [$className]) {
        $aliases[ strtolower(substr((string)strrchr('\\' . $className, '\\'), 1)) ] = $className;
    }

    foreach ($tokens as $index => $token) {
        if (is_array($token) && $token[ 0 ] === T_NAMESPACE) {
            $next = $tokens[ $index + 1 ] ?? null;
            $namespace = is_array($next) ? $next[ 1 ] : '';
        }
    }

    $references = [];
    $count = count($tokens);

    for ($index = 0; $index + 2 < $count; $index++) {
        $token = $tokens[ $index ];
        $colon = $tokens[ $index + 1 ];
        $class = $tokens[ $index + 2 ];

        if (! is_array($token) ||
            ! in_array($token[ 0 ], [T_NAME_QUALIFIED, T_NAME_FULLY_QUALIFIED, T_STRING], true) ||
            ! is_array($colon) || $colon[ 0 ] !== T_DOUBLE_COLON || ! is_array($class) || $class[ 0 ] !== T_CLASS) {

            continue;
        }

        $name = $token[ 1 ];

        if (in_array(strtolower($name), ['self', 'static', 'parent'], true)) {
            continue;
        }

        if ($name[ 0 ] === '\\') {
            $className = substr($name, 1);
        } else {
            $parts = explode('\\', $name, 2);
            $alias = $aliases[ strtolower($parts[ 0 ]) ] ?? null;
            $className = $alias !== null ?
                $alias . (isset($parts[ 1 ]) ? '\\' . $parts[ 1 ] : '') :
                ($namespace !== '' ? $namespace . '\\' : '') . $name;
        }

        $references[] = [$className, $token[ 2 ]];
    }

    return $references;
}

/**
 * Tells whether the doc comment of a class, interface or trait declares it deprecated, read from its file.
 */
function isDeprecatedClass(string $className, ?object $classLoader): bool
{
    static $cache = [];

    if ($classLoader === null || ! method_exists($classLoader, 'findFile')) {
        return false;
    }

    if (! array_key_exists($className, $cache)) {
        $cache[ $className ] = false;
        $file = $classLoader->findFile($className);

        if (is_string($file) && is_file($file)) {
            $shortName = substr((string)strrchr('\\' . $className, '\\'), 1);
            $docComment = null;

            foreach (token_get_all((string)file_get_contents($file)) as $token) {
                if (! is_array($token)) {
                    continue;
                }
                if ($token[ 0 ] === T_DOC_COMMENT) {
                    $docComment = $token[ 1 ];
                } elseif (in_array($token[ 0 ], [T_CLASS, T_INTERFACE, T_TRAIT, T_ENUM], true)) {
                    // the doc comment directly before the declaration (attributes and modifiers in between)
                    $cache[ $className ] = $docComment !== null && str_contains($docComment, '@deprecated');
                    break;
                } elseif (! in_array($token[ 0 ], [T_WHITESPACE, T_ABSTRACT, T_FINAL, T_READONLY, T_COMMENT], true)
                    && $token[ 1 ] !== $shortName) {
                    $docComment = null;
                }
            }
        }
    }

    return $cache[ $className ];
}

$classLoader = null;

if (isset($argv[ 3 ])) {
    $classLoader = require rtrim($argv[ 3 ], '/') . '/vendor/autoload.php';
}

// deprecated code per file: line and message
$findings = [];

foreach ($result[ 'files' ] ?? [] as $file => $fileResult) {
    // code of a parent class or trait is analysed in the context of each class: "<path> (in context of class X)"
    $file = (string)preg_replace('/ \(in context of .*\)$/', '', (string)$file);

    foreach ($fileResult[ 'messages' ] ?? [] as $message) {
        $identifier = (string)($message[ 'identifier' ] ?? '');

        if (! str_contains(strtolower($identifier), 'deprecated')) {
            continue;
        }

        // members that are not deprecated themselves, used on an object of a deprecated class or interface, for
        // example $this->getRequest() in every admin controller (Magento\Backend\App\AbstractAction is deprecated):
        // PhpStorm does not report them, the class is reported where the module names it (type, new, extends)
        if (preg_match('/^(method|staticMethod|property|staticProperty|classConstant)\.deprecated(Class|Interface|Trait)$/', $identifier)) {
            continue;
        }

        $findings[ $file ][] = [
            (int)($message[ 'line' ] ?? 0),
            preg_replace('/\s+/', ' ', trim((string)($message[ 'message' ] ?? '')))
        ];
    }
}

$moduleFiles = [];
$iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($moduleDirectory . '/src'));

foreach ($iterator as $fileInfo) {
    if ($fileInfo->isFile() && in_array($fileInfo->getExtension(), ['php', 'phtml'], true)) {
        $moduleFiles[] = $fileInfo->getPathname();
    }
}

if ($classLoader !== null) {
    foreach ($moduleFiles as $file) {
        $code = (string)file_get_contents($file);

        foreach (findImports($code) as [$className, $line]) {
            if (isDeprecatedClass($className, $classLoader)) {
                $findings[ $file ][] = [$line, sprintf('Import of deprecated class %s.', $className)];
            }
        }

        foreach (findClassNameReferences($code) as [$className, $line]) {
            if (isDeprecatedClass($className, $classLoader)) {
                $findings[ $file ][] = [$line, sprintf('Name of deprecated class %s with ::class.', $className)];
            }
        }
    }
}

$failures = 0;
$suppressionsByFile = [];

foreach ($findings as $file => $fileFindings) {
    $suppressionsByFile[ $file ] ??= findSuppressions((string)file_get_contents($file));
    $relativeFile = str_replace($moduleDirectory . '/', '', $file);

    foreach ($fileFindings as [$line, $message]) {
        $covered = false;

        foreach ($suppressionsByFile[ $file ] as &$suppression) {
            if ($line >= $suppression[ 'start' ] && $line <= $suppression[ 'end' ]) {
                $suppression[ 'used' ] = true;
                $covered = true;
            }
        }
        unset($suppression);

        if (! $covered) {
            $failures++;
            printf(
                "::error file=%s,line=%d::%s Replace it, or suppress it with: @noinspection PhpDeprecationInspection <reason>%s",
                $relativeFile,
                $line,
                $message,
                PHP_EOL
            );
        }
    }
}

// suppressions in files without findings
foreach ($moduleFiles as $file) {
    $suppressionsByFile[ $file ] ??= findSuppressions((string)file_get_contents($file));
}

ksort($suppressionsByFile);

foreach ($suppressionsByFile as $file => $suppressions) {
    $relativeFile = str_replace($moduleDirectory . '/', '', $file);

    foreach ($suppressions as $suppression) {
        if ($suppression[ 'reason' ] === '') {
            $failures++;
            printf(
                "::error file=%s,line=%d::Suppression of PhpDeprecationInspection without reason, add why the deprecated code is needed%s",
                $relativeFile,
                $suppression[ 'start' ],
                PHP_EOL
            );
        }

        if (! $suppression[ 'used' ]) {
            printf(
                "::warning file=%s,line=%d::Suppression of PhpDeprecationInspection without deprecated code that PHPStan found, remove it if PhpStorm does not report anything either%s",
                $relativeFile,
                $suppression[ 'start' ],
                PHP_EOL
            );
        }
    }
}

if ($failures > 0) {
    printf('%d deprecation finding(s), see above%s', $failures, PHP_EOL);
    exit(1);
}

echo "No unexplained deprecated code found\n";
