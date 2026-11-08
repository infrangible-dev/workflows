<?php

declare(strict_types=1);

namespace Infrangible\Workflows\DeadCode;

use ReflectionMethod;
use ShipMonk\PHPStan\DeadCode\Provider\ReflectionBasedMemberUsageProvider;
use ShipMonk\PHPStan\DeadCode\Provider\VirtualUsageData;
use SimpleXMLElement;

/**
 * Marks methods as used that Magento calls because of the XML configuration of a module, which the dead code detector
 * cannot see:
 *
 *   - plugin methods (before..., after..., around...) of plugins declared in di.xml
 *   - methods of cron jobs (crontab.xml), observers (events.xml) and services of the web API (webapi.xml)
 *   - layout actions: <block class="..."><action method="..."/></block>
 *
 * Everything that Magento calls through its interfaces or parent classes (controllers, observers, patches, source
 * models, ...) is already detected through the vendor usage provider.
 */
final class MagentoUsageProvider extends ReflectionBasedMemberUsageProvider
{
    /** @var array<string, true> lower case class name => plugin */
    private array $pluginClasses = [];

    /** @var array<string, array<string, string>> lower case class name => lower case method name => note */
    private array $methods = [];

    public function __construct(string $moduleDirectory)
    {
        $sourceDirectory = rtrim($moduleDirectory, '/') . '/src';

        foreach ($this->findFiles($sourceDirectory . '/etc', 'di.xml') as $file) {
            $xml = $this->loadXml($file);

            foreach ($xml?->xpath('//plugin[@type]') ?: [] as $plugin) {
                $this->pluginClasses[ $this->normalize((string)$plugin[ 'type' ]) ] = true;
            }
        }

        foreach ($this->findFiles($sourceDirectory . '/etc', 'crontab.xml') as $file) {
            foreach ($this->loadXml($file)?->xpath('//job[@instance][@method]') ?: [] as $job) {
                $this->addMethod((string)$job[ 'instance' ], (string)$job[ 'method' ], 'cron job in crontab.xml');
            }
        }

        foreach ($this->findFiles($sourceDirectory . '/etc', 'events.xml') as $file) {
            foreach ($this->loadXml($file)?->xpath('//observer[@instance][@method]') ?: [] as $observer) {
                $this->addMethod(
                    (string)$observer[ 'instance' ],
                    (string)$observer[ 'method' ],
                    'observer in events.xml'
                );
            }
        }

        foreach ($this->findFiles($sourceDirectory . '/etc', 'webapi.xml') as $file) {
            foreach ($this->loadXml($file)?->xpath('//service[@class][@method]') ?: [] as $service) {
                $this->addMethod((string)$service[ 'class' ], (string)$service[ 'method' ], 'service in webapi.xml');
            }
        }

        foreach ($this->findFiles($sourceDirectory . '/view', '*.xml') as $file) {
            foreach ($this->loadXml($file)?->xpath('//block[@class]') ?: [] as $block) {
                foreach ($block->xpath('action[@method]') ?: [] as $action) {
                    $this->addMethod((string)$block[ 'class' ], (string)$action[ 'method' ], 'layout action');
                }
            }
        }
    }

    protected function shouldMarkMethodAsUsed(ReflectionMethod $method): ?VirtualUsageData
    {
        $className = $this->normalize($method->getDeclaringClass()->getName());
        $methodName = strtolower($method->getName());

        if (isset($this->methods[ $className ][ $methodName ])) {
            return VirtualUsageData::withNote('Magento: ' . $this->methods[ $className ][ $methodName ]);
        }

        if (isset($this->pluginClasses[ $className ]) && $method->isPublic() &&
            preg_match('/^(before|after|around)[A-Z]/', $method->getName()) === 1) {
            return VirtualUsageData::withNote('Magento: plugin method of a plugin in di.xml');
        }

        return null;
    }

    private function addMethod(string $className, string $methodName, string $note): void
    {
        $this->methods[ $this->normalize($className) ][ strtolower($methodName) ] = $note;
    }

    private function normalize(string $className): string
    {
        return strtolower(ltrim(trim($className), '\\'));
    }

    private function loadXml(string $file): ?SimpleXMLElement
    {
        $content = file_get_contents($file);

        if ($content === false) {
            return null;
        }

        $previous = libxml_use_internal_errors(true);
        $xml = simplexml_load_string($content);
        libxml_use_internal_errors($previous);

        return $xml === false ? null : $xml;
    }

    /**
     * @return string[]
     */
    private function findFiles(string $directory, string $pattern): array
    {
        if (! is_dir($directory)) {
            return [];
        }

        $files = [];
        $iterator = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($directory));

        foreach ($iterator as $file) {
            if ($file instanceof \SplFileInfo && $file->isFile() && fnmatch($pattern, $file->getFilename())) {
                $files[] = $file->getPathname();
            }
        }

        sort($files);

        return $files;
    }
}
