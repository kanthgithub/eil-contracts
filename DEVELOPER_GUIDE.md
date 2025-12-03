# Developer Guide - @eil-protocol/contracts

This guide provides step-by-step instructions for building, packaging, and using the `@eil-protocol/contracts` package locally.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Building the Package](#building-the-package)
- [Creating the NPM Package](#creating-the-npm-package)
- [Using in Other Projects](#using-in-other-projects)
- [Development Workflow](#development-workflow)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software

1. **Node.js** - Version **18.19.0 or higher** (recommended: **20.x or 22.x**)
2. **Yarn** - Version 1.22.x or higher
3. **Git**

### Check Your Environment

Run these commands to verify your setup:

```bash
node --version    # Should show v18.19.0 or higher
yarn --version    # Should show 1.22.x or higher
```

### Installing/Upgrading Node.js

If you need to install or upgrade Node.js, use one of these methods:

#### Option 1: Using nvm (Recommended)

```bash
# Install nvm (if not already installed)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# Restart your terminal or run:
source ~/.zshrc  # or source ~/.bashrc

# Install Node.js 22 LTS
nvm install 22
nvm use 22
nvm alias default 22

# Verify installation
node --version
```

#### Option 2: Using asdf

```bash
# Install asdf (if not already installed)
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.13.1

# Add to shell config and restart terminal
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.zshrc
source ~/.zshrc

# Install Node.js plugin and latest version
asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git
asdf install nodejs 22.12.0
asdf global nodejs 22.12.0

# Verify installation
node --version
```

#### Option 3: Direct Download

Visit [nodejs.org](https://nodejs.org/) and download the LTS version for your operating system.

---

## Initial Setup

### 1. Clone the Repository

```bash
git clone https://github.com/eth-infinitism/eil-contracts.git
cd eil-contracts
```

### 2. Install Dependencies

```bash
# Install all dependencies using Yarn
yarn install
```

**Expected output:** Dependencies should install without errors.

---

## Building the Package

### Build Command

```bash
yarn build
```

**What this does:**
- Runs `hardhat compile`
- Compiles all Solidity contracts in the `src/` directory
- Generates artifacts in the `artifacts/` directory
- Creates TypeScript type definitions

**Expected output:**
```
Compiled X Solidity files successfully
```

### Verify Build Artifacts

```bash
# Check that artifacts were created
ls -la artifacts/

# Should show:
# - artifacts.d.ts
# - build-info/
# - src/
```

---

## Creating the NPM Package

### Create Local Package Tarball

```bash
npm pack
```

**What this does:**
1. Runs the `prepack` script automatically (which runs `yarn build`)
2. Bundles `src/` and `artifacts/` directories (as specified in `package.json`)
3. Creates a `.tgz` file in the current directory

**Expected output:**
```
npm notice 
npm notice 📦  @eil-protocol/contracts@0.1.0
npm notice === Tarball Contents === 
npm notice <list of files>
npm notice === Tarball Details === 
npm notice name:          @eil-protocol/contracts                        
npm notice version:       0.1.0                                   
npm notice filename:      eil-protocol-contracts-0.1.0.tgz        
npm notice package size:  2.4 MB                                  
npm notice unpacked size: 21.2 MB                                 
npm notice total files:   273                                     
npm notice 
eil-protocol-contracts-0.1.0.tgz
```

### Verify Package Contents

```bash
# List contents of the tarball
tar -tzf eil-protocol-contracts-0.1.0.tgz | head -20
```

---

## Using in Other Projects

### Method 1: Install from Local Tarball (Recommended for Testing)

This method installs a snapshot of the package.

```bash
# In your target project (e.g., eil-protocol/sdk)
cd /path/to/your/project

# Install using absolute path
npm install /absolute/path/to/eil-contracts/eil-protocol-contracts-0.1.0.tgz

# Or using relative path
npm install ../eil-contracts/eil-protocol-contracts-0.1.0.tgz
```

**Verification:**
```bash
# Check package.json
cat package.json | grep "@eil-protocol/contracts"

# Should show:
# "@eil-protocol/contracts": "file:../eil-contracts/eil-protocol-contracts-0.1.0.tgz"
```

### Method 2: Using npm link (Recommended for Active Development)

This method creates a symlink, so changes in contracts are immediately available.

```bash
# Step 1: In the contracts repository
cd /path/to/eil-contracts
npm link

# Expected output:
# /usr/local/lib/node_modules/@eil-protocol/contracts -> /path/to/eil-contracts

# Step 2: In your target project
cd /path/to/your/project
npm link @eil-protocol/contracts

# Expected output:
# /path/to/your/project/node_modules/@eil-protocol/contracts -> 
# /usr/local/lib/node_modules/@eil-protocol/contracts -> 
# /path/to/eil-contracts
```

**To unlink:**
```bash
# In your target project
npm unlink @eil-protocol/contracts

# In the contracts repository (optional, to remove global link)
npm unlink
```

### Method 3: Package.json File Reference

Add this to your target project's `package.json`:

```json
{
  "dependencies": {
    "@eil-protocol/contracts": "file:../eil-contracts/eil-protocol-contracts-0.1.0.tgz"
  }
}
```

Then run:
```bash
npm install
```

---

## Development Workflow

### Typical Development Cycle

```bash
# 1. Make changes to Solidity contracts in src/

# 2. Build the contracts
yarn build

# 3. If using npm link: changes are immediately available in linked projects
# If using tarball: recreate package

# 4. Recreate package (if needed)
npm pack

# 5. Reinstall in target project (if using tarball method)
cd /path/to/target/project
npm install /path/to/eil-contracts/eil-protocol-contracts-0.1.0.tgz
```

### Quick Rebuild Script

Create a script for faster iteration:

```bash
# rebuild.sh
#!/bin/bash
set -e

echo "🔨 Building contracts..."
yarn build

echo "📦 Creating package..."
npm pack

echo "✅ Package created: eil-protocol-contracts-0.1.0.tgz"
```

Make it executable:
```bash
chmod +x rebuild.sh
./rebuild.sh
```

---

## Troubleshooting

### Issue: Node.js Version Mismatch

**Error:**
```
WARNING: You are using Node.js X.X.X which is not supported by Hardhat.
Please upgrade to 22.10.0 or a later LTS version
```

**Solution:**
```bash
# Check current version
node --version

# Upgrade using nvm
nvm install 22
nvm use 22
nvm alias default 22

# Verify
node --version  # Should show v22.x.x
```

### Issue: Module Not Found After Install

**Error:**
```
Cannot find module '@eil-protocol/contracts'
```

**Solution:**
```bash
# Verify package is in node_modules
ls -la node_modules/@eil-protocol/

# Reinstall
npm install /path/to/eil-contracts/eil-protocol-contracts-0.1.0.tgz --force
```

### Issue: Build Fails with "Command Failed"

**Error:**
```
Error: command failed: yarn build
```

**Solution:**
```bash
# Clean previous builds
yarn clean

# Or manually remove cache and artifacts
rm -rf cache/ artifacts/

# Reinstall dependencies
rm -rf node_modules/
yarn install

# Build again
yarn build
```

### Issue: Package Size Too Large

**Symptom:** Package tarball is unexpectedly large.

**Solution:**
```bash
# Check what's being packaged
npm pack --dry-run

# Verify package.json "files" field only includes necessary directories
# Should be: ["artifacts", "src"]
```

### Issue: Tarball Not Created

**Error:** `npm pack` completes but no `.tgz` file appears.

**Solution:**
```bash
# Check if prepack script failed
npm pack 2>&1 | tee pack.log

# Try with verbose logging
npm pack --verbose

# Skip prepack if needed (only if artifacts/ exists)
npm pack --ignore-scripts
```

### Issue: Permission Denied When Installing

**Error:**
```
EACCES: permission denied
```

**Solution:**
```bash
# Don't use sudo with npm
# Instead, configure npm to use a different directory

# Set npm prefix to home directory
mkdir ~/.npm-global
npm config set prefix '~/.npm-global'

# Add to PATH in ~/.zshrc or ~/.bashrc
echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.zshrc
source ~/.zshrc
```

---

## Importing Contracts in Your Project

### Import Contract ABIs

```typescript
// Import contract artifacts
import CrossChainPaymasterArtifact from '@eil-protocol/contracts/artifacts/src/CrossChainPaymaster.sol/CrossChainPaymaster.json';
import L1StakeManagerArtifact from '@eil-protocol/contracts/artifacts/src/L1AtomicSwapStakeManager.sol/L1AtomicSwapStakeManager.json';

// Use the ABI
const abi = CrossChainPaymasterArtifact.abi;
const bytecode = CrossChainPaymasterArtifact.bytecode;
```

### Import TypeScript Types (if available)

```typescript
// Import type definitions
import type { CrossChainPaymaster } from '@eil-protocol/contracts/artifacts/src/CrossChainPaymaster.sol/CrossChainPaymaster';
```

### Import Source Files

```solidity
// In Solidity contracts
import "@eil-protocol/contracts/src/CrossChainPaymaster.sol";
import "@eil-protocol/contracts/src/interfaces/ICrossChainPaymaster.sol";
```

---

## CI/CD Considerations

### In GitHub Actions or Similar CI

```yaml
# .github/workflows/build.yml
name: Build and Test

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '22'
          
      - name: Install dependencies
        run: yarn install --frozen-lockfile
        
      - name: Build contracts
        run: yarn build
        
      - name: Create package
        run: npm pack
        
      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: npm-package
          path: eil-protocol-contracts-*.tgz
```

---

## Best Practices

### ✅ DO

- Always use Node.js version **18.19+** or **20.x+** or **22.x+**
- Run `yarn install` after pulling latest changes
- Run `yarn build` before creating a package
- Use `npm link` for active development
- Use tarball install for production-like testing
- Commit `package-lock.json` or `yarn.lock` to version control

### ❌ DON'T

- Don't use outdated Node.js versions (< 18.19)
- Don't commit `node_modules/` to git
- Don't commit `artifacts/` or `cache/` to git (they're generated)
- Don't use `sudo` with npm/yarn commands
- Don't manually edit `artifacts/` directory

---

## Package Information

- **Package Name:** `@eil-protocol/contracts`
- **Version:** `0.1.0`
- **License:** MIT
- **Included Directories:** `src/`, `artifacts/`
- **Package Size:** ~2.4 MB (packed)
- **Unpacked Size:** ~21 MB

---

## Support

For issues or questions:
- Check the [Troubleshooting](#troubleshooting) section above
- Review the main [README.md](./README.md)
- Check Hardhat documentation: https://hardhat.org/
- Open an issue on the repository

---

## Quick Reference

```bash
# Complete setup from scratch
git clone https://github.com/eth-infinitism/eil-contracts.git
cd eil-contracts
nvm use 22  # or ensure Node.js 18.19+
yarn install
yarn build
npm pack

# Use in another project (one-time setup)
cd /path/to/other/project
npm install /path/to/eil-contracts/eil-protocol-contracts-0.1.0.tgz

# OR use npm link for development
cd /path/to/eil-contracts
npm link
cd /path/to/other/project
npm link @eil-protocol/contracts

# Rebuild after changes
cd /path/to/eil-contracts
yarn build
npm pack  # if using tarball method
```

---

**Last Updated:** December 3, 2025
