# Hack Scripts

This directory contains internal scripts for development, CI, and release management.

## Structure

```
hack/
├── install.sh          # Installation script for end-users
├── ci/
│   ├── release.sh      # Release preparation script
│   └── test-install.sh # CI script to test installation
```

## Scripts

### install.sh

Installation script that downloads and installs the `k8s-hosts-controller` binary and `hosts-controller-manager.sh` script to the user's system.

**Usage:**
```bash
curl -fsSL https://raw.githubusercontent.com/TykTechnologies/k8s-hosts-controller/main/install.sh | bash
```

**Note:** A redirect script exists at the repository root (`/install.sh`) for backward compatibility with existing documentation and installations.

### ci/release.sh

Prepares and creates a new release:

1. Validates version format
2. Checks if tag exists (locally and on GitHub)
3. Updates `hack/install.sh` VERSION variable
4. Creates a release commit
5. Creates and pushes the tag

**Usage:**
```bash
./hack/ci/release.sh v0.1.0
./hack/ci/release.sh v0.1.0-beta.4
```

### ci/test-install.sh

Tests the installation script in a Docker container to ensure it works correctly.

**Usage:**
```bash
./hack/ci/test-install.sh
```

## Purpose

Scripts in this directory are **not** part of the product itself but are used for:
- Building and packaging the product
- Testing and validation
- Release management
- Developer workflows

Product scripts (like `hosts-controller-manager.sh`) remain at the repository root.
