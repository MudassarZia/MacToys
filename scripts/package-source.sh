#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
# Explicit allowlist: never include neighboring projects, credentials, user profiles, or build caches.
COPYFILE_DISABLE=1 /usr/bin/tar -czf build/MacToys-0.1.0-source.tar.gz \
    Package.swift Sources Tests scripts .github .gitignore README.md LICENSE CONTRIBUTING.md SECURITY.md
echo "$PWD/build/MacToys-0.1.0-source.tar.gz"
