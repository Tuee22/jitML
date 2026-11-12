#!/bin/sh
# Windows-checkout portability guard for every version-controlled path.
#
# Fails (exit 1) when any tracked, or untracked-but-not-ignored, path:
#   * is longer than MAX_PATH_CHARS repo-relative characters (default 160), or
#   * has a component longer than MAX_COMPONENT_CHARS characters (default 100), or
#   * contains a character Windows rejects (< > : " \ | ? * or a control byte), or
#   * has a component beginning with a space or ending in a dot or a space, or
#   * has a component that is a reserved Windows device name (CON, NUL, COM1, ...), or
#   * differs from another path only by letter case.
#
# Rationale: Windows MAX_PATH is 260 characters including the drive, the checkout
# directory and a terminating NUL, and Git for Windows fails checkout on longer
# paths unless the user enabled core.longpaths. 160 repo-relative characters leaves
# 99 characters for the checkout prefix. Never rely on core.longpaths.
#
# Usage: bootstrap/check-path-lengths.sh [--list]   (--list prints offenders only)
# Needs git, sh and awk. Python 3 enables conservative Unicode case-collision
# detection; without it, non-ASCII paths fail closed. Run inside the repository.
set -eu

MAX_PATH_CHARS=${MAX_PATH_CHARS:-160}
MAX_COMPONENT_CHARS=${MAX_COMPONENT_CHARS:-100}

root=$(git rev-parse --show-toplevel)
cd "$root"
if ! paths=$(git -c core.quotepath=off ls-files --cached --others --exclude-standard); then
  printf '%s\n' 'FAIL: cannot enumerate tracked and unignored paths' >&2
  exit 1
fi

unicode_status=0
if command -v python3 >/dev/null 2>&1; then
  python3 -c '
import os, subprocess, sys
try:
    paths = subprocess.run(
        ["git", "-c", "core.quotepath=off", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        check=True, stdout=subprocess.PIPE,
    ).stdout
except (OSError, subprocess.CalledProcessError) as error:
    print("FAIL: cannot enumerate paths for Unicode collision check: " + str(error), file=sys.stderr)
    sys.exit(1)
seen = {}
failed = False
for raw in paths.split(b"\0"):
    if not raw:
        continue
    path = os.fsdecode(raw)
    parts = path.split("/")
    for end in range(1, len(parts) + 1):
        prefix = "/".join(parts[:end])
        key = prefix.casefold()
        previous = seen.get(key)
        if previous is not None and previous != prefix and (not prefix.isascii() or not previous.isascii()):
            print("conservative Unicode case collision: " + repr(previous) + " / " + repr(prefix))
            failed = True
        else:
            seen[key] = prefix
sys.exit(1 if failed else 0)
' || unicode_status=1
else
  printf '%s\n' "$paths" |
    LC_ALL=C awk '
      /[^\001-\177]/ { found = 1 }
      END { if (found) { print "FAIL: Python 3 required to check non-ASCII path collisions"; exit 1 } }
    ' || unicode_status=1
fi

ascii_status=0
printf '%s\n' "$paths" |
  LC_ALL=C awk -v maxp="$MAX_PATH_CHARS" -v maxc="$MAX_COMPONENT_CHARS" -v listonly="${1:-}" -v unicode_status="$unicode_status" '
  function bad(kind, path) {
    n++
    if (n <= 40 || listonly == "--list") printf("%s: %s (%d chars)\n", kind, path, length(path))
  }
  {
    if ($0 == "") next
    path = $0
    if (length(path) > maxp) bad("path too long", path)
    if (path ~ /[<>:"\\|?*]/ || path ~ /[[:cntrl:]]/) bad("invalid Windows character", path)
    m = split(path, parts, "/")
    for (i = 1; i <= m; i++) {
      c = parts[i]
      if (length(c) > maxc) { bad("component too long", path); break }
      if (c ~ /^ /) { bad("leading space", path); break }
      if (c ~ /[. ]$/) { bad("trailing dot or space", path); break }
      stem = c; sub(/\..*$/, "", stem); sub(/ +$/, "", stem); stem = toupper(stem)
      if (stem ~ /^(CON|CONIN\$|CONOUT\$|PRN|AUX|NUL|(COM|LPT)([1-9]|¹|²|³))$/) { bad("reserved device name", path); break }
    }
    prefix = ""
    for (i = 1; i <= m; i++) {
      prefix = (i == 1 ? parts[i] : prefix "/" parts[i])
      key = tolower(prefix)
      kind = (i == m ? "file" : "directory")
      if (key in seen && seen[key] != prefix) bad("case-only collision with " seen[key], path)
      if (key in kinds && kinds[key] != kind) bad("file/directory collision with " seen[key], path)
      if (!(key in seen)) seen[key] = prefix
      if (!(key in kinds)) kinds[key] = kind
    }
    total++
  }
  END {
    if (n > 0) {
      if (listonly != "--list" && n > 40) printf("... and %d more (use --list)\n", n - 40)
      printf("FAIL: %d offending path(s) of %d checked (limits: path %d, component %d)\n", n, total, maxp, maxc)
      exit 1
    }
    if (unicode_status != 0) {
      printf("FAIL: Unicode collision check failed (%d paths; limits: path %d, component %d)\n", total, maxp, maxc)
      exit 1
    }
    printf("OK: %d paths checked (limits: path %d, component %d)\n", total, maxp, maxc)
  }' || ascii_status=1

if [ "$unicode_status" -ne 0 ] || [ "$ascii_status" -ne 0 ]; then
  exit 1
fi
