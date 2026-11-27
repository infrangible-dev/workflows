# Infrangible Workflows

Reusable GitHub Actions workflows for the Infrangible Magento 2 modules.

## Magento module

`.github/workflows/magento-module.yml` checks a module and releases it when the checks pass.

### Checks

On every push and pull request, for each combination of the matrix:

| Magento | PHP |
|---------|-----|
| 2.4.6   | 8.1 |
| 2.4.7   | 8.2 |
| 2.4.8   | 8.3 |
| 2.4.8   | 8.4 |
| 2.4.9   | 8.5 |

Every PHP version that one of the Magento versions supports is tested once, because the Adobe Commerce Marketplace
rejects modules that allow fewer PHP versions than the Magento versions they support (PHP 8.1 with Magento 2.4.6).

1. A Magento project of the newest patch release of the version is created with Composer from the
   [Mage-OS mirror](https://mirror.mage-os.org/), so no access keys for repo.magento.com are needed, and the module is
   installed into it.
2. PHPCS with the `phpcs.xml` of the module and checks of conventions the tools cannot express, both only with the
   newest Magento version:
   - no `mixed[]`, `array<mixed>` or `array<mixed, …>` in docblocks: PhpStorm reports them as replaceable with
     `array`, PHPStan level 9 needs the value type, so use `@param array $x` together with
     `@phpstan-param array<string, mixed> $x` (or `array<int, mixed>`, `array<int|string, mixed>`, or a more precise
     type)
   - nullsafe operator instead of null checks before a method call (`$x?->get()` instead of
     `$x !== null ? $x->get() : null`), PhpStorm reports the ternary as replaceable
   - no unused exception variables: exceptions that are caught without using them are caught without variable
     (`catch (NoSuchEntityException)`), PhpStorm reports the variable as unused
   - no `var` in JavaScript: variables are declared with `const`, or `let` if they are assigned again (also `config`
     in `requirejs-config.js`), PhpStorm reports `var`; only the module's own files with the copyright header are
     checked, not bundled libraries
   - methods that return nothing declare `@return void` in their docblock, PhpStorm reports another return type as
     "Missing 'return' statement"
   - escaping with Magento's escaper (`$this->_escaper->escapeHtml()` in blocks, `$escaper->escapeHtml()` in
     templates) instead of the deprecated escape methods of blocks (`$this->escapeHtml()`, `$block->escapeUrl()`, …)
   - imported classes are written with their short name (`RuntimeException` instead of `\RuntimeException` after
     `use RuntimeException;`), PhpStorm reports the qualifier as unnecessary
   - LESS variables are defined in the module, in Magento's LESS library or in the LESS of Magento Blank or the admin
     theme, which every theme builds on; variables that only Luma defines in its module files (`@footer-links-color`)
     are reported, like PhpStorm reports them as "Cannot find variable"
   - every module requires `infrangible/m2-foundation` in `composer.json`, which presents Infrangible in the Magento
     admin, also when its code does not use it (except m2-foundation itself)
   - admin controllers declare their ACL resource (`const ADMIN_RESOURCE` or `_isAllowed()`) when they extend a base
     class that only checks `Magento_Backend::admin` (Magento's `Backend\App\Action`, the `Json` and `Ajax`
     controllers of m2-core), which every admin user has; `Magento_Backend::admin` itself is only declared on purpose
   - every text of the module (`__('…')` in PHP and templates, `$t('…')` in the module's JavaScript, everything marked
     with `translate` in XML) is translated in `src/i18n` into the 15 languages cs_CZ, da_DK, de_DE, es_ES, fi_FI,
     fr_FR, it_IT, nb_NO, nl_NL, nn_NO, pl_PL, pt_BR, pt_PT, sv_SE and uk_UA; the country variants de_AT, de_CH,
     de_LU, fr_BE, fr_CH, fr_LU, nl_BE, it_CH and sv_FI are copies; all checked with
     `tools/check-code-conventions.sh <module>`, which can also be run locally. In the package
     [infrangible/phpstan-magento](https://github.com/infrangible-dev/phpstan-magento) (composer type
     `phpstan-extension`), it also checks the PHPStan rules in `src` and the shared PHP files in the root directory
     (`bootstrap.php`, `versions.php`): no tags in running text, every parameter documented, imports instead of
     qualified names, also in the shared PHP files, where global classes need no leading backslash,
     no node classes that php-parser 5 deprecates, because the rules run with php-parser 4 of PHPStan 1 and php-parser
     5 of PHPStan 2; PHP extensions: the shared files only run in the PHPStan of Magento, whose framework requires them,
     and suppress `PhpComposerExtensionStubsInspection` with that reason, other PHP files of a module outside of `src`
     (composer-require-checker covers `src`) need the `ext-*` in composer.json; no inline `@var` tags in the shared PHP
     files, which PHPStan does not analyse and whose types PhpStorm infers, and no variables there that the file does
     not define itself (PhpStorm does not see the variables of required files); no calls in the shared PHP files of
     methods and constructors that the stubs of PhpStorm declare with a checked exception (on objects of the classes
     the file creates, with the `parents` of `src/phpstorm-throws.php` for inherited methods), unless the throws tag of
     the documented function or closure around them declares it: PhpStorm did not apply catch clauses in the closures
     of `bootstrap.php`
   - syntax of PHP 8.1 (constructor property promotion, readonly properties, null coalescing assignment, arrow
     functions, ...), checked with [Rector](https://getrector.com) and `templates/rector/rector.php` through
     `tools/check-php-syntax.sh <module> <magento> [<rector>]`, which also describes how to apply the changes
   - no duplicated code (at least 5 identical lines and 100 tokens, variable names ignored, like the PhpStorm
     inspection "Duplicated code fragment"), checked with [PHPCPD](https://github.com/systemsdk/phpcpd) through
     `tools/check-duplicated-code.sh <module> [<phpcpd>]`; move duplicated code into a shared method or base class,
     merge tests that only differ in their data into one test with a data provider; locally, install phpcpd with
     `cosyses PHPCPD 9.2`
   - correct spelling in code, comments, texts and documentation, like the PhpStorm inspection "Typo", checked with
     [cspell](https://cspell.org) and `templates/spelling/cspell.json` through
     `tools/check-spelling.sh <module> [<cspell>]`; translations (`i18n`), generated and minified files are skipped;
     fix the word, or add a correctly spelled term to `templates/spelling/words.txt`, which
     `tools/configure-phpstorm.py` also writes into the PhpStorm dictionary; locally, install cspell with
     `cosyses Node.js 24.13` and `cosyses CSpell 10.4` (Cosyses 1.157.0 or newer)
   - JavaScript of the module following the ESLint rules of the Magento coding standard
     (`magento/magento-coding-standard`, `eslint/eslint.config.mjs`), which the Adobe Commerce Marketplace applies
     besides PHPCS, through `tools/check-eslint.sh <module> <magento> [--fix]`; only the module's own files with the
     copyright header, not bundled libraries; warnings fail as well; `--fix` applies the automatic fixes to the
     module; locally, install Node.js with `cosyses Node.js 24.13`
   - every class, function and constant used by the module comes from a dependency in its `composer.json`, PHP
     extensions (`ext-<name>`) included, checked with
     [ComposerRequireChecker](https://github.com/maglnet/ComposerRequireChecker) through
     `tools/check-composer-requirements.sh`, which ignores classes generated by Magento (factories, proxies,
     interceptors, extension attributes) and PHPUnit; packages in `suggest` count as declared, for optional
     dependencies that the module only loads when they are installed (never in constructors, use
     `Infrangible\Core\Helper\Instances::createInstance()` or `getSharedInstance()` instead); locally, install the
     checker with `cosyses ComposerRequireChecker 4.24` (PHP 8.4 or newer)
   - no dead code: PHPStan (level 4 and higher) reports unused private methods, properties and constants; public and
     protected members are not checked, they are the API of the module for other modules and for Magento, which calls
     them through its XML configuration
   - no unexplained deprecated code: every deprecated class, method, function, constant or property that the module
     uses (found with [phpstan/phpstan-deprecation-rules](https://github.com/phpstan/phpstan-deprecation-rules) and
     PHPStan 2 through `tools/check-deprecations.sh`) is replaced, or, if it cannot be avoided (for example a
     constructor argument that a Magento parent class requires, or a filter callback of Magento's grid that receives
     a deprecated column), suppressed for PhpStorm with a reason:
     `@noinspection PhpDeprecationInspection <why it is needed>` in the doc comment of the method or class, or in a
     comment before the statement; directly after `<?php` it covers the whole file, which a file needs that imports a
     deprecated class (PhpStorm reports the `use` statement, the check looks up the doc comment of the imported class
     through Magento's autoloader). Suppressions without reason fail,
     suppressions that cover no finding are reported as warnings
3. PHPStan with the `phpstan.neon` of the module, which includes `magento.neon` of
   [infrangible/phpstan-magento](https://github.com/infrangible-dev/phpstan-magento) from the Magento installation: level
   9, the `@throws` tags as PhpStorm expects them, typed properties that are read before they are set, the classes that
   Magento generates, the differences between the Magento versions and rules for what PhpStorm checks beyond PHPStan
   (see the README of the package). The workflow installs the package in the version of the module's `require-dev`,
   which Composer does not install for a required package.
4. PHPUnit with the `phpunit.xml` of the module. PHPUnit's own notices and deprecations fail the step, for example a
   mock object without expectations (PHPUnit 12, use a stub instead). Modules without `src/Test/Unit` (no PHP logic, for example
   only JavaScript and styles) skip the step.

The path of the Magento installation is passed to the module configuration in the environment variable
`MAGENTO_ROOT`.

### Release

On a push to the default branch, after all checks passed:

1. The version is taken from `composer.json` of the module. Without a version, nothing is released.
2. If a tag for this version exists, nothing is released. A version lower than the latest release is an error.
3. The tag is created and pushed, and a GitHub release is created with the section `## <version>` of `CHANGELOG.md`
   as release notes.
4. Packagist picks up the new tag through the GitHub webhook of the module repository.

To release a module, raise `version` in `composer.json`, add the section to `CHANGELOG.md` and push to `main`.
Tags should only be created by this workflow.

### Usage

`.github/workflows/ci.yml` in the module repository:

```yaml
name: CI

on:
  push:
    branches:
      - main
      - master
  pull_request:

permissions:
  contents: write

jobs:
  module:
    uses: infrangible-dev/workflows/.github/workflows/magento-module.yml@main
```

The matrix can be changed with the input `matrix` (JSON list of objects with `magento`, `php` and optionally
`phpcs`). A module that supports fewer versions, for example one that fixes a bug of newer Magento versions only, keeps
the shared `ci.yml` and lists its versions in `.github/ci-matrix.json` instead, in the same format; the job "Versions"
reads it and it replaces the matrix:

```json
[
    {"magento": "2.4.8.*", "php": "8.3"},
    {"magento": "2.4.8.*", "php": "8.4"},
    {"magento": "2.4.9.*", "php": "8.5", "phpcs": true}
]
```

The module needs `phpcs.xml`, `phpstan.neon` and `phpunit.xml` in its root directory, and the PHPStan and PHPUnit
configuration have to load the Magento installation from `MAGENTO_ROOT` (see `templates/magento-module`), and
`infrangible/phpstan-magento` in `require-dev`.

## Shared module configuration

`templates/magento-module` contains the configuration that is the same in every module:

| File                       | Purpose                                                                  |
|----------------------------|--------------------------------------------------------------------------|
| `phpcs.xml`                | Magento2 coding standard and PHP 8.1 compatibility for `src`             |
| `phpstan.neon`             | PHPStan for `src` with the configuration of `infrangible/phpstan-magento` |
| `phpunit.xml`              | unit tests in `src/Test/Unit`                                            |
| `phpunit.bootstrap.php`    | loads the bootstrap of the Magento unit tests from `MAGENTO_ROOT`        |
| `.github/workflows/ci.yml` | calls the workflow of this repository                                    |

`MAGENTO_ROOT` defaults to `/var/www/magento`, the Magento installation of the Anodosys development environment.

Change these files here and copy them into the modules with:

```bash
tools/sync-module-config.sh ../m2-*            # add or update the files in all modules
tools/sync-module-config.sh --check ../m2-*    # only list modules with missing or outdated files
```

Directories without `composer.json` and `src` are skipped. The script also requires
[infrangible/phpstan-magento](https://github.com/infrangible-dev/phpstan-magento) in `require-dev` of the module, in
the version of `phpstanPackageVersion` in the script (raise it to move the modules to a new release of the package at
their next synchronization), and removes the PHPStan files that earlier versions of the templates copied into the
modules (`phpstan-rules`, `phpstan.bootstrap.php`, ...).

## Tools

`tools/check-deprecations.sh <tool directory> <module directory> <Magento directory>` runs the check of deprecated
code locally. The tool directory needs PHPStan 2 and the deprecation rules, `cosyses PHPStanDeprecationRules 2.0`
installs them:

```bash
cosyses PHPStanDeprecationRules 2.0
tools/check-deprecations.sh /usr/local/lib/composer-tools/phpstan-deprecation-rules /var/www/module /var/www/magento
```

`tools/check-composer-requirements.sh <composer-require-checker> <module directory>` runs the dependency check of the
workflow locally, for example in the cli container of the Anodosys development environment, where the vendor
directory of the module is the one of Magento.

`tools/add-property-types.py` adds native type declarations to class properties, taken from their `@var` docblocks
(`/** @var PageFactory */ protected $factory;` becomes `protected PageFactory $factory;`). It only changes
properties whose type is unambiguous and lists the others; the docblocks stay, as the Magento coding standard requires
them. Test doubles (`Class&MockObject`, `Class&Stub`) get `MockObject` or `Stub` as native type, because the coding
standard does not recognize docblocks of intersection types.

```bash
tools/add-property-types.py --dry-run ../m2-core/src   # show what would change
tools/add-property-types.py ../m2-core/src
```

Typing `protected` properties is a breaking change for classes that extend them, so it belongs in a major version.

`tools/add-method-docblocks.py` completes method docblocks as the Magento coding standard expects them: methods
without docblock get one, docblocks without short description get one generated from the method name (`getX` becomes
"Returns the x.", `loadX` "Loads the x.", `isX` "Checks whether it is x." and so on; constructors need none), and
missing `@param` tags (in argument order, existing ones are kept and sorted) and `@return` tags are added from the
native types. It lists every generated description, which are only a start and should be improved where the method
name says too little, as well as arguments and methods without native type (`mixed`) and arrays, which need a
`@phpstan-param` / `@phpstan-return` with the value type for PHPStan level 9.

```bash
tools/add-method-docblocks.py --dry-run ../m2-core/src
tools/add-method-docblocks.py ../m2-core/src
```

`tools/add-return-tags.py` adds missing `@return` tags to method docblocks, taken from the native return type, as the
PhpStorm default inspection "Missing @return tag" expects. Constructors, docblocks with `{@inheritDoc}` and methods
without native return type are skipped (the latter are listed).

```bash
tools/add-return-tags.py --dry-run ../m2-core/src
tools/add-return-tags.py ../m2-core/src
```

## PhpStorm settings

`templates/phpstorm` contains PhpStorm settings for every module, which `tools/configure-phpstorm.py` writes into the
`.idea` folder of the modules:

| File                     | Written to                                         | Purpose                                     |
|--------------------------|----------------------------------------------------|---------------------------------------------|
| `profiles_settings.xml`  | `.idea/inspectionProfiles/profiles_settings.xml`   | all modules use the IDE profile "Magento"   |
| `inspections.xml`        | `.idea/inspectionProfiles/Project_Default.xml`     | inspections that are changed, with reasons  |
|                          | and the IDE profile (`--ide-profile`)              |                                             |
| `project-resources.xml`  | `.idea/misc.xml` (component `ProjectResources`)    | catalog of the `urn:magento:...` schemas    |
| `schemas/`               | locations in the schema catalog                    | corrected copies of Magento schemas (see below) |
| `entry-points.xml`       | `.idea/misc.xml` (`PhpEntryPointsManager`)         | `\Infrangible\*` classes are not unused     |
| `module-folders.xml`     | `.idea/<module>.iml`                               | folders to index or exclude; the namespace prefix of the source folders comes from the PSR-4 autoload of composer.json |
| `stubs/`                 | include path in `.idea/php.xml`                    | classes for PhpStorm only (see below)       |
| `unchecked-exceptions.xml` | `.idea/php.xml` (`PhpAnalysisConfiguration`)     | exceptions that need no `@throws` tag       |
| `js-libraries.xml`       | `.idea/libraries/`, `.idea/jsLibraryMappings.xml`  | Magento's RequireJS, jQuery, ... (`lib/web`), scripts of Magento's modules that modules extend (price box, swatch renderer, ...), the Google Maps API (`stubs/google-maps.d.ts`), jQuery plugins of bundled libraries (`stubs/jquery-plugins.js`) |
| `scopes.xml`             | `.idea/scopes/`                                    | scopes the inspections refer to (shared configuration) |
| `../spelling/words.txt`  | `.idea/dictionaries/magento.xml`                   | words for the spell checker, shared with `tools/check-spelling.sh` |
| (ESLint)                 | `.idea/eslint.config.mjs`, `.idea/jsLinters/eslint.xml`, `.idea/workspace.xml` | ESLint with the rules of the Magento coding standard, like `tools/check-eslint.sh` (see below) |

PhpStorm excludes all Composer packages in `vendor` again when it opens a project after the installed packages
changed, also with its Composer synchronization switched off; Magento's LESS variables (`@media-common`) and the
functions of the JavaScript libraries (`define()`) would then be unresolved. So `configure-phpstorm.py` copies the files
of the JavaScript libraries in `vendor`, Magento's LESS library (`lib/web/css/source`) and the LESS of Magento Blank
and the admin theme (variables like `@minicart-icons-color` or `@icons-admin__font-name`) into `.phpstorm-magento` of
this repository (not in git) from a module whose development environment is running (or `MAGENTO_ROOT`), points the
libraries to the copies and makes the copy an additional content root of every module, because PhpStorm only indexes
library files inside the content roots; the Composer packages themselves stay excluded. The copies are updated whenever the files in `vendor` differ.

PhpStorm reports the JavaScript of a module with ESLint and the rules of the Magento coding standard, like the check
`tools/check-eslint.sh`. `configure-phpstorm.py` installs the rules with their npm packages into `.eslint` of this
repository (not in git) from `vendor/magento/magento-coding-standard` of a module whose development environment is
running (or of `MAGENTO_ROOT`), with npm of WSL, and again when its `package-lock.json` changes. Every module gets
`.idea/eslint.config.mjs`, which loads these rules without the folders of the Magento installation and without the
bundled libraries of the module (JavaScript files without the copyright header), `.idea/jsLinters/eslint.xml`, which
points PhpStorm to it, and the ESLint package and the Node.js of WSL (`/usr/bin/node`) in the properties of
`.idea/workspace.xml`. New settings apply when the project is opened, so close it before running the script.

The folders of the files of `js-libraries.xml` (for example `lib/web/requirejs` with `define()`) are indexed as well:
PhpStorm's Composer synchronization excludes `vendor/magento/magento2-base`, and files of a JavaScript library in an
excluded folder are unknown to PhpStorm. The folders are only changed while the `vendor` folder of the module exists
(the development environment of the module is running).

```bash
tools/configure-phpstorm.py ../m2-*            # apply the settings to all modules with a .idea folder
tools/configure-phpstorm.py --check ../m2-*    # only list modules with different settings
```

Only the listed inspections, folders and the schema catalog are changed, and the line endings of the files are kept; all other settings of the profile stay as they are.
PhpStorm creates `.idea` when a module is opened for the first time, so run the script again for new modules.
PhpStorm loads new JavaScript libraries only when it opens a project, so reopen modules that are open.
Magento's LESS library (`vendor/magento/magento2-base/lib/web/css/source`) is indexed so that PhpStorm resolves its
variables and mixins in `_module.less`. PhpStorm's Composer synchronization excludes the whole package, and the script
replaces this exclusion by the exclusion of the other folders of the package. This needs the Magento installation of
the development environment, so run the script again after `ads rise`. The script also switches off PhpStorm's
Composer synchronization (`.idea/workspace.xml`): when the installed packages changed, it ran when the project was
opened and excluded the packages again, so `define()` and the LESS variables were unresolved right after opening.
PhpStorm writes `workspace.xml` when it closes a project, so run the script while the project is closed.

The modules use the IDE profile "Magento", a copy of the PhpStorm default inspections. To write the inspection
settings into it as well, close PhpStorm (it saves IDE profiles itself) and run:

```bash
tools/configure-phpstorm.py --ide-profile /mnt/c/Users/<user>/AppData/Roaming/JetBrains/PhpStorm<version>/inspection/Magento.xml ../m2-*
```

`stubs/` declares classes that the tests use, but that the PHPUnit of the development environment may not have, for
example attributes of PHPUnit 12. PhpStorm finds them through the include path
`$PROJECT_DIR$/../workflows/templates/phpstorm/stubs`, so this repository has to be checked out next to the modules.
The file is never loaded by PHP. `stubs/google-maps.d.ts` declares the parts of the Google Maps JavaScript API that
the modules use (Google loads the API at runtime); the JavaScript library `google-maps` of `js-libraries.xml` points to
it, so PhpStorm does not take `google.maps.Map` for the built-in `Map` of JavaScript.
`stubs/jquery-plugins.js` declares jQuery plugins of libraries that the modules bundle and that register themselves
with a computed name (`$.fn[name] = ...`), for example `offcanvas()` of js-offcanvas; the JavaScript library
`jquery-plugins` points to it. `tools/check-code-conventions.sh` reports calls on jQuery objects that no library
declares.


`schemas/` holds copies of Magento schemas that PhpStorm cannot load, mapped in `project-resources.xml` to
`$PROJECT_DIR$/../workflows/templates/phpstorm/schemas` instead of the `vendor` folder. Magento's
`ObjectManager/etc/config.xsd` (all `di.xml` files) redefines the type `string` without extending it, which Xerces
rejects ("'extension' does not have a 'base' attribute that refers to the redefined element"), while libxml in Magento
accepts it; the copy extends `string` itself. `View/Layout/etc/elements.xsd` (all layout files with arguments) does the
same with the type `object`. `tools/configure-phpstorm.py` reports Magento schemas in the `vendor` folder of a module
that redefine a type without extending it and have no corrected copy.

To change an inspection for all modules, add it to `inspections.xml` with a comment why, and run the script.
