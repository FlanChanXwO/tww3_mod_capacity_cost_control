import base64
import json
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import prepare_release
import upload_workshop
from release_notes import release_notes


class ReleaseTests(unittest.TestCase):
    def test_version_pr_waits_for_approval_and_only_merges_after_verify_passes(self) -> None:
        workflow = (Path(__file__).resolve().parents[3] / ".github/workflows/release.yml").read_text(encoding="utf-8")
        step = workflow.split("      - name: Merge version PR through required verification\n", 1)[1]
        script = textwrap.dedent(step.split("        run: |\n", 1)[1].split("      - name:", 1)[0])
        bash = shutil.which("bash")
        self.assertIsNotNone(bash, "Workflow checks require Bash (included with Git for Windows)")
        stub = '''
gh() {
    case "$1 $2" in
        "pr list") echo 9 ;;
        "run list") echo 42 ;;
        "run view")
            if test "$4" = --json && test "$5" = url; then
                echo https://github.com/example/repo/actions/runs/42
            elif test -f approved; then echo queued
            else echo action_required; fi ;;
        "run watch") echo verify >> trace; return "$VERIFY_EXIT" ;;
        "pr merge") echo merge >> trace ;;
        *) return 99 ;;
    esac
}
sleep() { echo approval >> trace; touch approved; }
'''
        for verify_exit in (0, 1):
            with self.subTest(verify_exit=verify_exit), tempfile.TemporaryDirectory() as directory:
                env = dict(os.environ, BRANCH="codex/release-v1.0.1", COMMIT="abc", VERIFY_EXIT=str(verify_exit),
                           GITHUB_STEP_SUMMARY=(Path(directory) / "summary").as_posix())
                result = subprocess.run([bash, "-e", "-c", stub + script], cwd=directory, env=env,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, verify_exit, result.stderr)
                expected = ["approval", "verify"] + (["merge"] if verify_exit == 0 else [])
                self.assertEqual((Path(directory) / "trace").read_text().splitlines(), expected)

    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "data").mkdir()
        self.project = self.root / "data/project.json"
        self.project.write_text(json.dumps({"version": "1.0.0", "workshop_id": "3821170924"}) + "\n", encoding="utf-8")
        self.pack = self.root / "approved.pack"
        self.pack.write_bytes(b"approved pack")
        self.icon = self.pack.with_suffix(".png")
        self.icon.write_bytes(b"approved launcher icon")
        self.sha256 = hashlib.sha256(self.pack.read_bytes()).hexdigest()
        self.notes = '## [1.0.0] - 2026-10-17\n\n### 简体中文\n\n#### 新增\n\n- 显示版本。\n\n### English\n\n#### Added\n\n- Show the version.\n'
        self.changelog = self.root / 'CHANGELOG.md'
        self.changelog.write_text('# Changelog\n\n' + self.notes, encoding='utf-8')
        for module in (prepare_release, upload_workshop):
            patcher = patch.object(module, "ROOT", self.root)
            patcher.start()
            self.addCleanup(patcher.stop)

    def git(self, *args: str) -> None:
        subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)

    def init_repository(self) -> None:
        self.git("init", "--quiet")
        self.git("config", "user.email", "tests@example.invalid")
        self.git("config", "user.name", "Release tests")
        self.git("add", "data/project.json")
        self.git("commit", "--quiet", "-m", "Initial version")

    def test_release_notes_preserve_both_languages_and_select_exact_version(self) -> None:
        newer = self.notes.replace("1.0.0", "1.1.0").replace("显示版本", "新功能")
        self.changelog.write_text("# Changelog\n\n" + newer + "\n" + self.notes, encoding="utf-8")
        self.assertEqual(release_notes(self.changelog, "1.0.0"), self.notes)
        self.assertEqual(release_notes(self.changelog, "1.1.0"), newer)

    def test_release_notes_reject_missing_duplicate_or_incomplete_entries(self) -> None:
        for text in ("# Changelog\n", self.notes + "\n" + self.notes,
                     self.notes.split("### English")[0],
                     self.notes.split("- Show the version.")[0],
                     self.notes.replace("- 显示版本。", "")):
            with self.subTest(text=text):
                self.changelog.write_text(text, encoding="utf-8")
                with self.assertRaises(ValueError):
                    release_notes(self.changelog, "1.0.0")

    def test_vdf_preserves_unicode_newlines_and_escapes_quotes(self) -> None:
        self.assertEqual(upload_workshop.quote_vdf('中文\n"quoted"\\path'), '"中文\n\\"quoted\\"\\\\path"')
        with self.assertRaisesRegex(ValueError, "notes must not be empty"):
            upload_workshop.prepare_upload(self.pack, self.sha256, self.root / "upload", "\n  ")
        self.assertFalse((self.root / "upload").exists())

    def test_version_rejects_invalid_or_older_values_without_writing(self) -> None:
        before = self.project.read_bytes()
        for version in ("v1.0.0", "1.0", "01.0.0", "1.0.0\n", "0.9.9", "1.0.0; echo bad"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                prepare_release.prepare_release(version)
        self.assertEqual(self.project.read_bytes(), before)

    def test_version_update_and_existing_tag_retry(self) -> None:
        self.init_repository()
        self.assertEqual(prepare_release.prepare_release("1.2.3"), "v1.2.3")
        self.assertEqual(json.loads(self.project.read_text())["version"], "1.2.3")
        self.git("add", "data/project.json")
        self.git("commit", "--quiet", "-m", "Release")
        self.git("tag", "v1.2.3")
        with self.assertRaises(ValueError):
            prepare_release.prepare_release("1.2.3")
        self.assertEqual(prepare_release.prepare_release("1.2.3", resume=True), "v1.2.3")
        self.project.write_text(self.project.read_text().replace('"3821170924"', '"123"'))
        with self.assertRaises(subprocess.CalledProcessError):
            prepare_release.prepare_release("1.2.3", resume=True)

    def test_upload_vdf_preserves_listing_and_uses_approved_content(self) -> None:
        vdf = upload_workshop.prepare_upload(self.pack, self.sha256, self.root / "upload", self.notes)
        text = vdf.read_text(encoding="utf-8")
        self.assertIn('"appid" "1142710"', text)
        self.assertIn('"publishedfileid" "3821170924"', text)
        self.assertIn('"changenote" "' + self.notes + '"', text)
        self.assertNotIn('\\u', upload_workshop.quote_vdf(self.notes))
        self.assertNotIn('\\n', upload_workshop.quote_vdf(self.notes))
        for untouched in ("title", "description", "previewfile", "visibility"):
            self.assertNotIn('"' + untouched + '"', text)
        self.assertEqual((vdf.parent / "content" / upload_workshop.PACK_NAME).read_bytes(), self.pack.read_bytes())
        self.assertEqual((vdf.parent / "content" / Path(upload_workshop.PACK_NAME).with_suffix(".png")).read_bytes(), self.icon.read_bytes())

    def test_missing_launcher_icon_is_not_prepared(self) -> None:
        self.icon.unlink()
        with self.assertRaisesRegex(FileNotFoundError, "Launcher icon is required"):
            upload_workshop.prepare_upload(self.pack, self.sha256, self.root / "upload", self.notes)
        self.assertFalse((self.root / "upload").exists())

    def test_release_checksums_cover_pack_and_launcher_icon(self) -> None:
        workflow = (Path(__file__).resolve().parents[3] / ".github/workflows/release.yml").read_text(encoding="utf-8")
        step = workflow.split("      - name: Record pack checksum\n", 1)[1]
        script = textwrap.dedent(step.split("        run: |\n", 1)[1].split("      - uses:", 1)[0])
        build = self.root / "build"
        build.mkdir()
        for suffix in (".pack", ".png"):
            (build / Path(upload_workshop.PACK_NAME).with_suffix(suffix)).write_bytes(b"approved" + suffix.encode())
        env = dict(os.environ, GITHUB_OUTPUT=(self.root / "outputs").as_posix(),
                   GITHUB_STEP_SUMMARY=(self.root / "summary").as_posix())
        result = subprocess.run([shutil.which("bash"), "-e", "-c", script], cwd=self.root, env=env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = {f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}" for p in build.glob("*.*")}
        self.assertEqual({line.replace(" *", "  ", 1) for line in (build / "SHA256SUMS").read_text().splitlines()}, expected)
        pack_hash = hashlib.sha256((build / upload_workshop.PACK_NAME).read_bytes()).hexdigest()
        self.assertEqual((self.root / "outputs").read_text().splitlines(), ["sha256=" + pack_hash])

    def test_tampered_pack_is_not_prepared(self) -> None:
        self.pack.write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "SHA256 differs"):
            upload_workshop.prepare_upload(self.pack, self.sha256, self.root / "upload", self.notes)
        self.assertFalse((self.root / "upload").exists())

    def test_upload_cannot_create_a_new_item(self) -> None:
        self.project.write_text('{"version": "1.0.0", "workshop_id": "0"}')
        with self.assertRaisesRegex(ValueError, "new Workshop item"):
            upload_workshop.prepare_upload(self.pack, self.sha256, self.root / "upload", self.notes)

    def test_steam_requires_success_confirmation_and_removes_credentials(self) -> None:
        steamcmd = self.root / "steamcmd/steamcmd.sh"
        secret = base64.b64encode(b"cached Steam login").decode()
        for returncode, stdout, confirmed in (
            (0, "Success. Uploaded item 3821170924", True),
            (0, "Uploading content...\x1b[0m\nCommitting update...\x1b[0mSuccess.\x1b[0mUnloading Steam API...OK", True),
            (0, "Committing update...\nSuccess.\n", True),
            (0, "Success.", False),
            (0, "Committing update...\nERROR! Access Denied", False),
            (0, "ERROR! Access Denied", False),
            (0, "Success. Uploaded item 123", False),
            (1, "Committing update...Success.", False),
            (1, "FAILED login", False),
        ):
            with self.subTest(stdout=stdout), patch.dict(os.environ, STEAM_USERNAME="user", STEAM_CONFIG_VDF=secret):
                result = subprocess.CompletedProcess([], returncode, stdout=stdout, stderr="")
                with patch.object(upload_workshop.subprocess, "run", return_value=result) as run:
                    if confirmed:
                        upload_workshop.upload(steamcmd, self.pack, self.sha256, self.notes)
                    else:
                        with self.assertRaisesRegex(RuntimeError, "SteamCMD did not confirm"):
                            upload_workshop.upload(steamcmd, self.pack, self.sha256, self.notes)
                self.assertIn("+@NoPromptForPassword", run.call_args.args[0])
                self.assertFalse((steamcmd.parent / "config/config.vdf").exists())


if __name__ == "__main__":
    unittest.main()
