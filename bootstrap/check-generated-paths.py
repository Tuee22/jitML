#!/usr/bin/env python3
"""Check an explicit generated-output tree against a mapped Windows root.

The caller supplies a quiescent tree and its intended absolute Windows root.
This does not discover producers, prove the mapping, or defend against
concurrent tree changes. Ignored files are included; links are refused.
The optional suffix reserve checks length only: the caller must establish a
sufficient reserve and validate the actual temporary names and collisions.
Planned paths are caller-supplied examples, not a producer inventory or proof
of future names, collisions, filesystem behavior, or Windows execution.
"""

import argparse
import os
from pathlib import Path, PureWindowsPath
import re
import sys


RESERVED = re.compile(r"^(CON|CONIN\$|CONOUT\$|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\..*)?$", re.IGNORECASE)
INVALID = set('<>:"/\\|?*')


def utf16_units(value):
    return len(value.encode("utf-16-le", errors="strict")) // 2


def component_problem(name, limit):
    if not name or name in (".", ".."):
        return "empty or relative component"
    if any(char in INVALID or ord(char) < 32 for char in name):
        return "invalid Windows character"
    if name.startswith(" "):
        return "component begins with a space"
    if name.endswith((".", " ")):
        return "component ends in a dot or space"
    if RESERVED.fullmatch(name.split(".", 1)[0].rstrip(" ")):
        return "reserved Windows device name"
    try:
        if utf16_units(name) > limit:
            return "component exceeds UTF-16 budget"
    except UnicodeEncodeError:
        return "component is not valid UTF-16"
    return None


def inspect_tree(root, windows_root, path_limit, component_limit, suffix_units, stats, planned_paths):
    """Return every detected problem; an unreadable tree is a problem."""
    problems = []
    windows = PureWindowsPath(windows_root)
    if os.name == "nt" and not hasattr(os.path, "isjunction"):
        return ["Windows inspection requires Python with junction detection"]
    if not windows.is_absolute() or not windows.drive:
        return ["Windows root must be an absolute drive or UNC path"]
    if windows.drive.startswith(("\\\\?\\", "\\\\.\\")):
        return ["extended or device Windows roots are not supported"]
    if not (re.fullmatch(r"[A-Za-z]:", windows.drive) or windows.drive.startswith("\\\\")):
        return ["Windows root has an invalid drive"]
    if path_limit < 1 or component_limit < 1:
        return ["path and component limits must be positive"]
    if suffix_units < 0:
        return ["file suffix reserve must not be negative"]
    if any(part in (".", "..") for part in re.split(r"[\\/]", windows_root)):
        return ["Windows root must not contain relative components"]
    if windows.drive.startswith("\\\\"):
        unc_parts = windows.drive[2:].split("\\")
        if len(unc_parts) != 2:
            return ["UNC root must include server and share"]
        for part in unc_parts:
            problem = component_problem(part, component_limit)
            if problem:
                problems.append(f"UNC root component {part!r}: {problem}")
    for part in windows.parts[1:]:
        problem = component_problem(part, component_limit)
        if problem:
            problems.append(f"Windows root component {part!r}: {problem}")
    try:
        root_units = utf16_units(str(windows)) + 1
        stats.update(max_path_units=root_units, max_path=".")
        if root_units > path_limit:
            problems.append("Windows root exceeds UTF-16 path budget including NUL")
    except UnicodeEncodeError:
        problems.append("Windows root is not valid UTF-16")
    if root.is_symlink() or (hasattr(os.path, "isjunction") and os.path.isjunction(root)) or not root.is_dir():
        return problems + ["inspection root is missing, not a directory, or a link"]

    seen = {}
    kinds = {}

    def visit(directory, relative):
        try:
            with os.scandir(directory) as iterator:
                entries = sorted(iterator, key=lambda entry: entry.name)
        except OSError as error:
            problems.append(f"cannot read {relative or '.'}: {error}")
            return
        for entry in entries:
            parts = relative + (entry.name,)
            display = "/".join(parts)
            stats["entries"] += 1
            problem = component_problem(entry.name, component_limit)
            if problem:
                problems.append(f"{display}: {problem}")
            folded = tuple(part.casefold() for part in parts)
            if folded in seen and seen[folded] != parts:
                problems.append(f"{display}: case collision with {'/'.join(seen[folded])}")
            else:
                seen[folded] = parts
            try:
                mapped = str(windows.joinpath(*parts))
                path_units = utf16_units(mapped) + 1
                component_units = utf16_units(entry.name)
                if stats["max_path_units"] is None or path_units > stats["max_path_units"]:
                    stats.update(max_path_units=path_units, max_path=display)
                if stats["max_component_units"] is None or component_units > stats["max_component_units"]:
                    stats.update(max_component_units=component_units, max_component=display)
                if path_units > path_limit:
                    problems.append(f"{display}: exceeds UTF-16 path budget including NUL")
                if entry.is_symlink() or (hasattr(os.path, "isjunction") and os.path.isjunction(entry.path)):
                    problems.append(f"{display}: link or junction cannot be inspected safely")
                elif entry.is_dir(follow_symlinks=False):
                    kinds[folded] = "directory"
                    visit(entry.path, parts)
                elif entry.is_file(follow_symlinks=False):
                    kinds[folded] = "file"
                    reserved_path_units = path_units + suffix_units
                    reserved_component_units = component_units + suffix_units
                    if stats["max_reserved_path_units"] is None or reserved_path_units > stats["max_reserved_path_units"]:
                        stats.update(max_reserved_path_units=reserved_path_units, max_reserved_path=display)
                    if reserved_path_units > path_limit and suffix_units:
                        problems.append(f"{display}: file plus suffix reserve exceeds UTF-16 path budget including NUL")
                    if reserved_component_units > component_limit and suffix_units:
                        problems.append(f"{display}: file plus suffix reserve exceeds UTF-16 component budget")
                else:
                    problems.append(f"{display}: unsupported filesystem object")
            except (OSError, UnicodeEncodeError) as error:
                problems.append(f"{display}: cannot inspect: {error}")

    visit(root, ())
    for planned in planned_paths:
        parts = re.split(r"[\\/]", planned)
        if not planned or any(not part or part in (".", "..") for part in parts):
            problems.append(f"planned {planned!r}: path must contain nonempty relative components")
            continue
        for part in parts:
            problem = component_problem(part, component_limit)
            if problem:
                problems.append(f"planned {planned!r}: component {part!r}: {problem}")
        for size in range(1, len(parts) + 1):
            prefix = tuple(parts[:size])
            folded = tuple(part.casefold() for part in prefix)
            kind = "file" if size == len(parts) else "directory"
            if folded in seen and seen[folded] != prefix:
                problems.append(f"planned {planned!r}: case collision with {'/'.join(seen[folded])}")
            elif folded not in seen:
                seen[folded] = prefix
            if folded in kinds and kinds[folded] != kind:
                problems.append(f"planned {planned!r}: {kind} conflicts with {kinds[folded]} {'/'.join(prefix)}")
            elif folded not in kinds:
                kinds[folded] = kind
        try:
            mapped_units = utf16_units(str(windows.joinpath(*parts))) + 1
            if mapped_units > path_limit:
                problems.append(f"planned {planned!r}: exceeds UTF-16 path budget including NUL")
            if suffix_units and mapped_units + suffix_units > path_limit:
                problems.append(f"planned {planned!r}: file plus suffix reserve exceeds UTF-16 path budget including NUL")
            if suffix_units and utf16_units(parts[-1]) + suffix_units > component_limit:
                problems.append(f"planned {planned!r}: file plus suffix reserve exceeds UTF-16 component budget")
        except UnicodeEncodeError:
            problems.append(f"planned {planned!r}: path is not valid UTF-16")
    if stats["entries"] == 0 and not planned_paths:
        problems.append("inspection root contains no entries")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, help="existing output directory to inspect, including ignored files")
    parser.add_argument("--windows-root", required=True, help="absolute Windows path corresponding to root")
    parser.add_argument("--path-units", type=int, default=260, help="maximum UTF-16 units including terminating NUL")
    parser.add_argument("--component-units", type=int, default=255, help="maximum UTF-16 units per component")
    parser.add_argument("--file-suffix-units", type=int, default=0, help="caller-supplied UTF-16 reserve appended to each file name")
    parser.add_argument("--planned-path", action="append", default=[], help="check a caller-supplied relative future file path; repeat for each path")
    args = parser.parse_args()
    stats = {"entries": 0, "max_path_units": None, "max_path": None, "max_component_units": None, "max_component": None, "max_reserved_path_units": None, "max_reserved_path": None}
    problems = inspect_tree(args.root, args.windows_root, args.path_units, args.component_units, args.file_suffix_units, stats, args.planned_path)
    print(f"inspection root: {args.root}")
    print(f"Windows mapping: {args.windows_root}")
    print(f"entries inspected: {stats['entries']}")
    print(f"planned paths checked: {len(args.planned_path)} (caller-supplied; not observed outputs)")
    print(f"longest mapped path including NUL: {stats['max_path_units']} UTF-16 units ({stats['max_path']})")
    print(f"longest observed component: {stats['max_component_units']} UTF-16 units ({stats['max_component']})")
    print(f"file suffix reserve: {args.file_suffix_units} UTF-16 units")
    print(f"longest file path with suffix reserve including NUL: {stats['max_reserved_path_units']} UTF-16 units ({stats['max_reserved_path']})")
    if problems:
        for problem in problems:
            print(problem, file=sys.stderr)
        print(f"FAIL: {len(problems)} generated-output path problem(s)", file=sys.stderr)
        return 1
    if stats["entries"]:
        print("OK: inspected generated-output tree for the supplied Windows mapping")
    else:
        print("OK: planned paths fit the supplied Windows mapping; no outputs observed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
