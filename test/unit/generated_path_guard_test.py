"""Independent CLI controls for the generated-output path guard."""

from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest


GUARD = Path(__file__).resolve().parents[2] / "bootstrap" / "check-generated-paths.py"


class GeneratedPathGuardTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def run_guard(self, *arguments):
        return subprocess.run(
            [sys.executable, str(GUARD), str(self.root), *arguments],
            text=True,
            capture_output=True,
            check=False,
        )

    def test_includes_ignored_and_nested_outputs(self):
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        (self.root / ".gitignore").write_text(".ignored/\n")
        nested = self.root / ".ignored" / "nested"
        nested.mkdir(parents=True)
        (nested / "CON.txt").write_text("x")
        ignored = subprocess.run(
            ["git", "-C", str(self.root), "check-ignore", ".ignored/nested/CON.txt"],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(ignored.returncode, 0, ignored.stderr)
        result = self.run_guard("--windows-root", "C:\\out")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(".ignored/nested/CON.txt", result.stderr)
        self.assertIn("reserved Windows device name", result.stderr)

    def test_path_budget_includes_root_surrogate_pair_and_nul(self):
        (self.root / "😀").write_text("x")
        # C:\\x\\ plus one supplementary character is seven UTF-16 units;
        # the terminating NUL makes eight.
        good = self.run_guard("--windows-root", "C:\\x", "--path-units", "8")
        bad = self.run_guard("--windows-root", "C:\\x", "--path-units", "7")
        self.assertEqual(good.returncode, 0, good.stderr)
        self.assertIn("entries inspected: 1", good.stdout)
        self.assertIn("longest mapped path including NUL: 8 UTF-16 units", good.stdout)
        self.assertIn("longest observed component: 2 UTF-16 units", good.stdout)
        self.assertEqual(bad.returncode, 1, bad.stdout + bad.stderr)
        self.assertIn("including NUL", bad.stderr)

    def test_component_budget_counts_utf16_units(self):
        (self.root / "😀😀").write_text("x")
        result = self.run_guard("--windows-root", "C:\\x", "--component-units", "3")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("component exceeds UTF-16 budget", result.stderr)

    def test_file_suffix_reserve_checks_path_and_component_boundaries(self):
        (self.root / "kernel").write_text("x")
        (self.root / "longer_dir").mkdir()
        good = self.run_guard("--windows-root", "C:\\x", "--file-suffix-units", "4", "--path-units", "16", "--component-units", "10")
        path_bad = self.run_guard("--windows-root", "C:\\x", "--file-suffix-units", "4", "--path-units", "15")
        component_bad = self.run_guard("--windows-root", "C:\\x", "--file-suffix-units", "4", "--component-units", "9")
        self.assertEqual(good.returncode, 0, good.stdout + good.stderr)
        self.assertIn("longest file path with suffix reserve including NUL: 16 UTF-16 units", good.stdout)
        self.assertEqual(path_bad.returncode, 1, path_bad.stdout + path_bad.stderr)
        self.assertIn("file plus suffix reserve exceeds UTF-16 path budget", path_bad.stderr)
        self.assertEqual(component_bad.returncode, 1, component_bad.stdout + component_bad.stderr)
        self.assertIn("file plus suffix reserve exceeds UTF-16 component budget", component_bad.stderr)

    def test_rejects_negative_suffix_reserve(self):
        (self.root / "file").write_text("x")
        result = self.run_guard("--windows-root", "C:\\x", "--file-suffix-units", "-1")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("file suffix reserve must not be negative", result.stderr)

    def test_rejects_case_collisions_and_invalid_names(self):
        (self.root / "Foo").write_text("x")
        (self.root / "foo").write_text("x")
        (self.root / "trailing.").write_text("x")
        result = self.run_guard("--windows-root", "C:\\x")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("case collision", result.stderr)
        self.assertIn("component ends in a dot or space", result.stderr)

    def test_rejects_superscript_device_names_with_extensions(self):
        (self.root / "COM¹").write_text("x")
        (self.root / "lpt².txt").write_text("x")
        result = self.run_guard("--windows-root", "C:\\x")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("COM¹: reserved Windows device name", result.stderr)
        self.assertIn("lpt².txt: reserved Windows device name", result.stderr)

    def test_rejects_console_devices_and_leading_spaces(self):
        for name in ("CONIN$", "conout$.txt", " file"):
            (self.root / name).write_text("x")
        result = self.run_guard("--windows-root", "C:\\x")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("CONIN$: reserved Windows device name", result.stderr)
        self.assertIn("conout$.txt: reserved Windows device name", result.stderr)
        self.assertIn(" file: component begins with a space", result.stderr)

    def test_device_stems_with_spaces_before_extensions_are_rejected(self):
        for name in ("CON .txt", "lpt¹  .txt", "CONIN$ .txt"):
            (self.root / name).write_text("x")
        (self.root / "CON tent.txt").write_text("x")
        result = self.run_guard("--windows-root", "C:\\x")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        for name in ("CON .txt", "lpt¹  .txt", "CONIN$ .txt"):
            self.assertIn(name + ": reserved Windows device name", result.stderr)
        self.assertNotIn("CON tent.txt:", result.stderr)

    def test_checkout_guard_detects_portability_names(self):
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        for name in ("COM¹.txt", "NUL .txt", "CONOUT$", " leading"):
            (self.root / name).write_text("x")
        (self.root / "CON tent.txt").write_text("x")
        result = subprocess.run(
            [str(GUARD.parent / "check-path-lengths.sh"), "--list"],
            cwd=self.root,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        for name in ("COM¹.txt", "NUL .txt", "CONOUT$", " leading"):
            self.assertIn(name, result.stdout)
        self.assertNotIn("CON tent.txt", result.stdout)

    def test_checkout_guard_detects_unicode_case_collisions(self):
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        (self.root / "Ä.txt").write_text("x")
        (self.root / "ä.txt").write_text("x")
        result = subprocess.run(
            [str(GUARD.parent / "check-path-lengths.sh"), "--list"],
            cwd=self.root,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("conservative Unicode case collision", result.stdout)

    def test_checkout_guard_detects_unicode_directory_case_collisions(self):
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        for directory, filename in (("Ä", "one"), ("ä", "two")):
            (self.root / directory).mkdir()
            (self.root / directory / filename).write_text("x")
        result = subprocess.run(
            [str(GUARD.parent / "check-path-lengths.sh"), "--list"],
            cwd=self.root,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("conservative Unicode case collision", result.stdout)

    def test_checkout_guard_detects_ascii_directory_case_collisions(self):
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        for directory, filename in (("Folder", "one"), ("folder", "two")):
            (self.root / directory).mkdir()
            (self.root / directory / filename).write_text("x")
        result = subprocess.run(
            [str(GUARD.parent / "check-path-lengths.sh"), "--list"],
            cwd=self.root,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("case-only collision", result.stdout)

    def test_checkout_guard_fails_closed_without_unicode_checker(self):
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        (self.root / "ä.txt").write_text("x")
        with tempfile.TemporaryDirectory() as tool_dir:
            for name in ("git", "awk"):
                Path(tool_dir, name).symlink_to(shutil.which(name))
            result = subprocess.run(
                [str(GUARD.parent / "check-path-lengths.sh")],
                cwd=self.root,
                env={**os.environ, "PATH": tool_dir},
                text=True,
                capture_output=True,
                check=False,
            )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Python 3 required to check non-ASCII", result.stdout)

    def test_checkout_guard_refuses_git_enumeration_failures(self):
        with tempfile.TemporaryDirectory() as tool_dir:
            git = Path(tool_dir, "git")
            git.write_text(
                '#!/bin/sh\n'
                'if [ "$1" = rev-parse ]; then printf "%s\\n" "$FAKE_ROOT"; exit 0; fi\n'
                'case "$*" in *-z*) exit 42;; esac\n'
                'if [ "$FAIL_PRIMARY" = yes ]; then exit 43; fi\n'
                'printf "valid.txt\\n"\n'
            )
            git.chmod(0o755)
            for name in ("awk", "python3"):
                Path(tool_dir, name).symlink_to(shutil.which(name))
            for fail_primary in ("yes", "no"):
                result = subprocess.run(
                    [str(GUARD.parent / "check-path-lengths.sh")],
                    cwd=self.root,
                    env={**os.environ, "PATH": tool_dir, "FAKE_ROOT": str(self.root), "FAIL_PRIMARY": fail_primary},
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("cannot enumerate", result.stderr)
                self.assertNotIn("OK:", result.stdout)

    def test_rejects_special_files(self):
        os.mkfifo(self.root / "pipe")
        result = self.run_guard("--windows-root", "C:\\x")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("pipe: unsupported filesystem object", result.stderr)

    def test_rejects_symlinks_instead_of_skipping_them(self):
        (self.root / "target").mkdir()
        (self.root / "link").symlink_to(self.root / "target", target_is_directory=True)
        result = self.run_guard("--windows-root", "C:\\x")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("link or junction", result.stderr)

    def test_rejects_relative_and_overlong_roots(self):
        relative = self.run_guard("--windows-root", "relative")
        overlong = self.run_guard("--windows-root", "C:\\long-root", "--path-units", "5")
        self.assertEqual(relative.returncode, 1, relative.stdout + relative.stderr)
        self.assertIn("absolute", relative.stderr)
        self.assertEqual(overlong.returncode, 1, overlong.stdout + overlong.stderr)
        self.assertIn("Windows root exceeds", overlong.stderr)

    def test_rejects_missing_inspection_root(self):
        missing = self.root / "absent"
        result = subprocess.run(
            [sys.executable, str(GUARD), str(missing), "--windows-root", "C:\\x"],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("inspection root is missing", result.stderr)

    def test_empty_tree_is_not_a_passing_observation(self):
        result = self.run_guard("--windows-root", "C:\\x")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("inspection root contains no entries", result.stderr)

    def test_planned_path_preflights_empty_tree_at_exact_boundary(self):
        path = "dir/😀.bin"
        good = self.run_guard("--windows-root", "C:\\x", "--planned-path", path, "--path-units", "16")
        bad = self.run_guard("--windows-root", "C:\\x", "--planned-path", path, "--path-units", "15")
        self.assertEqual(good.returncode, 0, good.stdout + good.stderr)
        self.assertIn("planned paths checked: 1", good.stdout)
        self.assertIn("no outputs observed", good.stdout)
        self.assertEqual(bad.returncode, 1, bad.stdout + bad.stderr)
        self.assertIn("exceeds UTF-16 path budget", bad.stderr)

    def test_planned_paths_reject_unsafe_components_and_reserve_overflow(self):
        for path in ("../escape", "C:\\outside", "nested//empty", "dir/CON.txt", "/absolute"):
            result = self.run_guard("--windows-root", "C:\\x", "--planned-path", path)
            self.assertEqual(result.returncode, 1, path + result.stdout + result.stderr)
        result = self.run_guard("--windows-root", "C:\\x", "--planned-path", "dir/file", "--file-suffix-units", "2", "--path-units", "14")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("file plus suffix reserve exceeds", result.stderr)

    def test_planned_path_does_not_hide_existing_bad_output(self):
        (self.root / "NUL.txt").write_text("x")
        result = self.run_guard("--windows-root", "C:\\x", "--planned-path", "future.txt")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("reserved Windows device name", result.stderr)

    def test_planned_paths_detect_case_collisions_and_file_directory_conflicts(self):
        for paths, expected in (
            (("Foo/a", "foo/b"), "case collision"),
            (("dir", "dir/child"), "conflicts with file"),
            (("dir/child", "dir"), "conflicts with directory"),
        ):
            args = ["--windows-root", "C:\\x"]
            for path in paths:
                args.extend(("--planned-path", path))
            result = self.run_guard(*args)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn(expected, result.stderr)

    def test_planned_paths_check_existing_entries_and_allow_exact_reuse(self):
        (self.root / "Directory").mkdir()
        (self.root / "existing").write_text("x")
        good = self.run_guard("--windows-root", "C:\\x", "--planned-path", "existing", "--planned-path", "Directory/new")
        self.assertEqual(good.returncode, 0, good.stdout + good.stderr)
        for path, expected in (("directory/new", "case collision"), ("existing/child", "conflicts with file"), ("Directory", "conflicts with directory")):
            result = self.run_guard("--windows-root", "C:\\x", "--planned-path", path)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn(expected, result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
