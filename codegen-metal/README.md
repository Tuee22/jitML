# Metal Codegen Notes

This directory is documentation-only. The Haskell renderer in
`src/JitML/Codegen/Metal.hs` generates Swift package and Metal kernel inputs on
demand under `./.build/jit-src/apple-silicon/<hash>/`.

The Apple Silicon build plan runs `swift build` through `tart ssh` and writes
`.dylib` artifacts into `./.build/jit/apple-silicon/`. The host daemon starts
the Tart VM only on a cache miss.
