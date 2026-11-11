#!/bin/sh
# Windows-checkout portability guard for every version-controlled path.
#
# Fails (exit 1) when any tracked, or untracked-but-not-ignored, path:
#   * is longer than MAX_PATH_CHARS repo-relative characters (default 160), or
#   * has a component longer than MAX_COMPONENT_CHARS characters (default 100), or
#   * contains a character Windows rejects (< > : " \ | ? * or a control byte), or
#   * has a component ending in a dot or a space, or
#   * has a component that is a reserved Windows device name (CON, NUL, COM1, ...), or
#   * differs from another path only by letter case.
#
# Rationale: Windows MAX_PATH is 260 characters including the drive, the checkout
# directory and a terminating NUL, and Git for Windows fails checkout on longer
# paths unless the user enabled core.longpaths. 160 repo-relative characters leaves
# 99 characters for the checkout prefix. Never rely on core.longpaths.
#
# Usage: bootstrap/check-path-lengths.sh [--list]   (--list prints offenders only)
# Needs only git, sh and awk. Run from anywhere inside the repository.
set -eu

MAX_PATH_CHARS=${MAX_PATH_CHARS:-160}
MAX_COMPONENT_CHARS=${MAX_COMPONENT_CHARS:-100}

root=$(git rev-parse --show-toplevel)
cd "$root"

git -c core.quotepath=off ls-files --cached --others --exclude-standard |
  LC_ALL=C awk -v maxp="$MAX_PATH_CHARS" -v maxc="$MAX_COMPONENT_CHARS" -v listonly="${1:-}" '
  function bad(kind, path) {
    n++
    if (n <= 40 || listonly == "--list") printf("%s: %s (%d chars)\n", kind, path, length(path))
  }
  {
    path = $0
    if (length(path) > maxp) bad("path too long", path)
    if (path ~ /[<>:"\\|?*]/ || path ~ /[[:cntrl:]]/) bad("invalid Windows character", path)
    m = split(path, parts, "/")
    for (i = 1; i <= m; i++) {
      c = parts[i]
      if (length(c) > maxc) { bad("component too long", path); break }
      if (c ~ /[. ]$/) { bad("trailing dot or space", path); break }
      stem = c; sub(/\..*$/, "", stem); stem = toupper(stem)
      if (stem ~ /^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$/) { bad("reserved device name", path); break }
    }
    key = tolower(path)
    if (key in seen && seen[key] != path) bad("case-only collision with " seen[key], path)
    seen[key] = path
    total++
  }
  END {
    if (n > 0) {
      if (listonly != "--list" && n > 40) printf("... and %d more (use --list)\n", n - 40)
      printf("FAIL: %d offending path(s) of %d checked (limits: path %d, component %d)\n", n, total, maxp, maxc)
      exit 1
    }
    printf("OK: %d paths checked (limits: path %d, component %d)\n", total, maxp, maxc)
  }'
