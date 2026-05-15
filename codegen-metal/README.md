# Metal Codegen Driver

The Apple Silicon driver builds deterministic Metal kernels and writes `.dylib`
artifacts into `./.build/jit/apple-silicon/`. The host daemon starts the Tart VM
only on a cache miss.
