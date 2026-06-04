# Vendored Haskell Packages

The packages in this directory are source distributions used by
`cabal.project` as deterministic dependency pins.

- `lens-family-2.1.3`
- `lens-family-core-2.1.3`

They are BSD-licensed upstream packages by Russell O'Connor. jitML carries a
small compatibility patch that relaxes each package's `containers` upper bound
from `<0.8` to `<0.9` so the pinned GHC `9.14.1` toolchain can use its bundled
`containers-0.8` without a project-wide `allow-newer` override. The
`lens-family-core` copy also carries the minimal source hygiene needed for the
GHC `9.14.1` warning-clean gate: canonical local `First` / `Last`
Semigroup/Monoid instances and removal of a redundant import.

Cleanup ownership lives in
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`: remove these local source
packages once Hackage releases or metadata revisions solve and build
warning-clean under GHC `9.14.1` without local package patches.
