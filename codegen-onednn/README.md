# oneDNN Codegen Notes

This directory is documentation-only. The Haskell renderer in
`src/JitML/Codegen/OneDnn.hs` generates oneDNN-style C++ compiler inputs on
demand under `./.build/jit-src/linux-cpu/<hash>/`.

The Linux CPU build plan uses fixed blocked reductions and writes `.so`
artifacts into `./.build/jit/linux-cpu/`.
