<?php

/**
 * Compares the deprecated code that PHPStan found (phpstan/phpstan-deprecation-rules, JSON output) with the
 * suppressions of PhpStorm's inspection in the module, see check-deprecations.sh.
 *
 * Usage: php check-deprecations.php <module directory> <PHPStan JSON result>
 *
 * A suppression is a comment with "@noinspection PhpDeprecationInspection <reason>". It covers:
 *   - the whole file, if it directly follows the opening tag of the file
 *   - otherwise the declaration or statement that follows it: up to the end of the body of a class, function or block,
 *     or up to the semicolon of a statement or property
 *
 * Deprecated classes count where the module names them (types, new, extends, implements), not where it uses the members
 * of an object of such a class that are not deprecated themselves, as in PhpStorm.
 *
 * Fails for deprecated code that no suppression covers and for suppressions without reason. Suppressions that cover no
 * deprecated code are reported as warnings, PhpStorm may know deprecations that PHPStan does not find.
 */

declare(strict_types=1);

if ($argc !== 3) {
    fwrite(STDERR, "Usage: php check-deprecations.php <module directory> <PHPStan JSON result>\n");
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

        $reason = trim(preg_replace('#\*/\s*$#', '', $matches[ 1 ]) ?? '', " \t*,");
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

$failures = 0;
$suppressionsByFile = [];

foreach ($result[ 'files' ] ?? [] as $file => $fileResult) {
    $code = (string)file_get_contents($file);
    $suppressionsByFile[ $file ] = findSuppressions($code);
    $relativeFile = str_replace($moduleDirectory . '/', '', $file);

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

        $line = (int)($message[ 'line' ] ?? 0);
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
                preg_replace('/\s+/', ' ', trim((string)($message[ 'message' ] ?? ''))),
                PHP_EOL
            );
        }
    }
}

// suppressions in files without findings
$iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($moduleDirectory . '/src'));

foreach ($iterator as $fileInfo) {
    if (! $fileInfo->isFile() || ! in_array($fileInfo->getExtension(), ['php', 'phtml'], true)) {
        continue;
    }

    $file = $fileInfo->getPathname();
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
