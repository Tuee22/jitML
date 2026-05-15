# CUDA Codegen Notes

This directory is documentation-only. The Haskell renderer in
`src/JitML/Codegen/Cuda.hs` generates CUDA compiler inputs on demand under
`./.build/jit-src/linux-cuda/<hash>/`.

The Linux CUDA build plan invokes `nvcc` with `--use_fast_math=false` and
explicit deterministic algorithm IDs, then writes `.so` artifacts into
`./.build/jit/linux-cuda/`.
