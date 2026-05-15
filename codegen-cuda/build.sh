#!/usr/bin/env bash
set -euo pipefail
nvcc --use_fast_math=false -Xcompiler -fPIC -shared -o .build/jit/linux-cuda/kernel.so codegen-cuda/kernel.cu
