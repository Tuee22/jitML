# CUDA Codegen Driver

The Linux CUDA driver builds deterministic CUDA kernels with
`--use_fast_math=false` and explicit algorithm IDs, then writes `.so` artifacts
into `./.build/jit/linux-cuda/`.
