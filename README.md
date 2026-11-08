# Infrangible Workflows

Reusable GitHub Actions workflows for the Infrangible Magento 2 modules.

## Magento module

`.github/workflows/magento-module.yml` checks a module and releases it when the checks pass.

### Checks

On every push and pull request, for each combination of the matrix:

| Magento | PHP |
|---------|-----|
| 2.4.6   | 8.2 |
| 2.4.7   | 8.3 |
| 2.4.8   | 8.4 |
| 2.4.9   | 8.5 |

1. A Magento project of the newest patch release of the version is created with Composer from the
   [Mage-OS mirror](https://mirror.mage-os.org/), so no access keys for repo.magento.com are needed, and the module is
   installed into it.
2. PHPCS with the `phpcs.xml` of the module (only with the newest Magento version).
3. PHPStan with the `phpstan.neon` of the module.
4. PHPUnit with the `phpunit.xml` of the module.

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
  pull_request:

permissions:
  contents: write

jobs:
  module:
    uses: infrangible-dev/workflows/.github/workflows/magento-module.yml@main
```

The matrix can be changed with the input `matrix` (JSON list of objects with `magento`, `php` and optionally
`phpcs`).

The module needs `phpcs.xml`, `phpstan.neon` and `phpunit.xml` in its root directory, and the PHPStan and PHPUnit
configuration have to load the Magento installation from `MAGENTO_ROOT` (see `phpstan.bootstrap.php` and
`phpunit.bootstrap.php` in [m2-foundation](https://github.com/infrangible-dev/m2-foundation)).
