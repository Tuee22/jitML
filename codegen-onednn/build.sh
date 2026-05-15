#!/usr/bin/env bash
set -euo pipefail
g++ -O2 -fno-fast-math -o .build/jit/linux-cpu/kernel.so -shared -fPIC codegen-onednn/kernel.cc
