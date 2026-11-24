#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p build/tests
swiftc -swift-version 5 Sources/CoreTypes.swift Sources/ChatDatabase.swift Tests/CoreTests.swift -lsqlite3 -o build/tests/CoreTests
build/tests/CoreTests
