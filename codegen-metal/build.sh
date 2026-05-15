#!/usr/bin/env bash
set -euo pipefail
swift build --package-path codegen-metal -c release
