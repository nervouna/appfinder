#!/usr/bin/env python3
"""Exercise release packaging and publication offline, using a real local Git remote.

The script under test is unchanged. Signing, notarization, GitHub, building and
installation are simulated at their command-line boundaries; ZIPs, hashes and Git
refs are real. No developer credentials are read, no command contacts GitHub or
Apple, and the installed application and its process are never touched.

Usage: python3 scripts/check-release.py
"""

import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parent.parent
VERSION = "0.1.3"
TAG = "v" + VERSION
ARCHIVE = "AppFinder-" + VERSION + ".zip"
REPO = "fixture/appfinder"
TOOLS = {"git", "gh", "security", "codesign", "xcrun", "spctl", "swift", "fixture-build", "fixture-install"}


def fake_tool(name, args):
    """Model external services, retaining their state between script invocations."""
    if name == "git":
        command = args[2:] if args[:1] == ["-C"] else args
        if command[:2] == ["remote", "get-url"]:
            print("git@github.com:" + REPO + ".git")
            return 0
        os.execv(os.environ["RELEASE_TEST_GIT"], [os.environ["RELEASE_TEST_GIT"], *args])

    state_path = Path(os.environ["RELEASE_TEST_STATE"])
    state = json.loads(state_path.read_text())
    work = Path(os.environ["RELEASE_TEST_WORK"])
    assets = state_path.parent / "assets"

    def save():
        state_path.write_text(json.dumps(state))

    def option(flag, default=None):
        return args[args.index(flag) + 1] if flag in args else default

    def fail(message):
        print(message, file=sys.stderr)
        save()
        return 1

    if name == "fixture-build":
        state["builds"] += 1
        contents = work / "build/AppFinder.app/Contents"
        (contents / "MacOS").mkdir(parents=True, exist_ok=True)
        version = re.search(r"MARKETING_VERSION = ([^;]+);", (work / "AppFinder.xcodeproj/project.pbxproj").read_text()).group(1)
        with (contents / "Info.plist").open("wb") as handle:
            plistlib.dump({"CFBundleShortVersionString": version}, handle)
        (contents / "MacOS/AppFinder").write_text("fixture build " + str(state["builds"]))
        if state.get("edit_during_build"):
            (work / "feature.txt").write_text("changed during build")
    elif name == "fixture-install":
        if len(args) != 2 or args[0] != "--archive":
            return fail("Unexpected installer arguments: " + repr(args))
        state["events"].append(["install", state["release"]["draft"] if state["release"] else None])
        if state.get("fail_install"):
            return fail("fixture installation failure")
        shutil.copyfile(args[1], state_path.parent / "installed.zip")
    elif name == "security":
        print('1) 0000000000 "Developer ID Application: Fixture"')
    elif name == "codesign":
        if "--entitlements" in args:
            print("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict/></plist>")
        elif "--verify" not in args:
            print("Authority=Developer ID Application: Fixture\nCodeDirectory v=20500 flags=0x10000(runtime)\nTimestamp=2026-10-31")
    elif name == "xcrun":
        if args[:2] == ["notarytool", "submit"]:
            state["notarizations"] += 1
            print(json.dumps({"status": "Invalid" if state.get("reject_notary") else "Accepted", "id": "fixture-submission"}))
        elif args[:2] == ["notarytool", "log"]:
            print('{"message":"fixture notarization rejection"}')
        elif args[:2] not in (["stapler", "staple"], ["stapler", "validate"]):
            return fail("Unexpected xcrun command: " + repr(args))
    elif name == "spctl":
        print("source=Notarized Developer ID")
    elif name == "swift":
        state["test_runs"] += 1
    elif name == "gh":
        host = option("--hostname", os.environ.get("GH_HOST", "github.com"))
        if host != "github.com":
            return fail("fixture GitHub host mismatch: " + host)
        if args[:2] == ["auth", "status"]:
            pass
        elif args[:2] == ["repo", "view"]:
            print("ADMIN")
        elif args[:1] == ["api"]:
            if state.get("query_failure"):
                return fail("fixture GitHub connection failure")
            release = state["release"]
            if release:
                fields = [str(release["draft"]).lower(), release["url"]]
                if "length" in option("--jq", ""):
                    fields.append(str(len(release["assets"])))
                print("\t".join(fields))
        elif args[:2] == ["release", "create"]:
            if state["release"]:
                return fail("release already exists")
            tag = args[2]
            notes_file = option("--notes-file")
            draft = "--draft" in args
            state["release"] = {"draft": draft, "tag": tag, "url": "https://github.com/" + REPO + "/releases/tag/" + tag,
                                "assets": [], "notes": Path(notes_file).read_text() if notes_file else "Generated notes"}
            state["events"].append(["create", draft])
        elif args[:2] == ["release", "upload"]:
            paths = []
            index = 3
            while index < len(args):
                if args[index] in ("--repo", "-R"):
                    index += 2
                elif args[index].startswith("--"):
                    index += 1
                else:
                    paths.append(Path(args[index]))
                    index += 1
            for path in paths:
                state["upload_attempts"] += 1
                if state["upload_attempts"] == state.get("fail_upload_at"):
                    return fail("fixture upload interrupted")
                if path.name in state["release"]["assets"]:
                    if "--clobber" not in args:
                        return fail("asset already exists: " + path.name)
                    state["events"].append(["delete", path.name])
                else:
                    state["release"]["assets"].append(path.name)
                shutil.copyfile(path, assets / path.name)
                state["events"].append(["upload", path.name])
        elif args[:2] == ["release", "download"]:
            name = option("--pattern")
            output = Path(option("--output"))
            if name not in state["release"]["assets"]:
                return fail("asset not found: " + str(name))
            shutil.copyfile(assets / name, output)
            if state.get("corrupt_download"):
                output.write_bytes(b"damaged download")
        elif args[:2] == ["release", "view"]:
            if state["release"] is None:
                return fail("release not found")
            fields = option("--json", "")
            if fields == "assets":
                if state.get("publish_on_asset_view"):
                    state["release"]["draft"] = False
                print("\n".join(state["release"]["assets"]))
            elif fields == "url":
                print(state["release"]["url"])
            else:
                return fail("Unexpected release view fields: " + fields)
        elif args[:2] == ["release", "edit"]:
            if "--draft=false" in args:
                if state.get("reject_publish"):
                    return fail("fixture publication failure")
                state["events"].append(["publish", sorted(state["release"]["assets"])])
                state["release"]["draft"] = False
            else:
                return fail("Unexpected release edit: " + repr(args))
        else:
            return fail("Unexpected gh command: " + repr(args))
    save()
    return 0


class ReleaseWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="appfinder-release-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.work = self.root / "checkout"
        self.remote = self.root / "origin.git"
        self.fake_bin = self.root / "bin"
        self.state_path = self.root / "state.json"
        self.real_git = shutil.which("git")
        self.env = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1")
        for variable in ("GIT_DIR", "GIT_WORK_TREE", "GH_REPO"):
            self.env.pop(variable, None)
        self.work.mkdir()
        self.fake_bin.mkdir()
        (self.root / "assets").mkdir()
        self.state_path.write_text(json.dumps({"builds": 0, "notarizations": 0, "test_runs": 0, "upload_attempts": 0, "release": None, "events": []}))
        for tool in TOOLS:
            (self.fake_bin / tool).symlink_to(Path(__file__).resolve())
        (self.work / "scripts").mkdir()
        for name in ("release.sh", "common.sh"):
            shutil.copyfile(ROOT / "scripts" / name, self.work / "scripts" / name)
        build = self.work / "scripts/build.sh"
        build.write_text('#!/bin/bash\nexec fixture-build "$@"\n')
        build.chmod(0o755)
        installer = self.work / "scripts/install.sh"
        installer.write_text('#!/bin/bash\nexec fixture-install "$@"\n')
        installer.chmod(0o755)
        project = self.work / "AppFinder.xcodeproj"
        project.mkdir()
        (project / "project.pbxproj").write_text(("MARKETING_VERSION = " + VERSION + ";\n") * 4)
        (self.work / ".gitignore").write_text("/build/\n")
        key = self.root / "fixture-key.p8"
        issuer = self.root / "fixture-issuer.txt"
        key.write_text("dummy test key")
        issuer.write_text("dummy-test-issuer")
        signing = self.root / "signing.env"
        signing.write_text("APPFINDER_CODESIGN_IDENTITY='Developer ID Application: Fixture'\nAPPFINDER_TEAM_ID=FIXTURE\n"
                           + "APPFINDER_NOTARY_KEY='" + str(key) + "'\nAPPFINDER_NOTARY_KEY_ID=FIXTURE\n"
                           + "APPFINDER_NOTARY_ISSUER_FILE='" + str(issuer) + "'\n")
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Release Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "tag.gpgsign", "false")
        self.git("config", "core.hooksPath", "/dev/null")
        self.git("add", ".")
        self.git("commit", "-m", "Initial fixture")
        self.base = self.git("rev-parse", "HEAD")
        subprocess.run([self.real_git, "init", "--bare", str(self.remote)], env=self.env, check=True, capture_output=True)
        self.git("remote", "add", "origin", str(self.remote))
        self.git("push", "origin", "main")
        (self.work / "feature.txt").write_text("release candidate")
        self.git("add", "feature.txt")
        self.git("commit", "-m", "Feature to release")
        self.head = self.git("rev-parse", "HEAD")
        self.env.update(PATH=str(self.fake_bin) + os.pathsep + self.env["PATH"],
                        RELEASE_TEST_GIT=self.real_git, RELEASE_TEST_STATE=str(self.state_path),
                        RELEASE_TEST_WORK=str(self.work), APPFINDER_SIGNING_ENV=str(signing))

    def git(self, *args, remote=False):
        cwd = self.remote if remote else self.work
        result = subprocess.run([self.real_git, "-C", str(cwd), *args], env=self.env, text=True, capture_output=True, check=True)
        return result.stdout.strip()

    def state(self, **changes):
        state = json.loads(self.state_path.read_text())
        if changes:
            state.update(changes)
            self.state_path.write_text(json.dumps(state))
        return state

    def run_release(self, *args, succeeds=True):
        result = subprocess.run(["/bin/bash", str(self.work / "scripts/release.sh"), *args], cwd=self.work,
                                env=self.env, text=True, capture_output=True, timeout=30)
        if succeeds:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def assert_remote_untouched(self):
        self.assertEqual(self.git("rev-parse", "refs/heads/main", remote=True), self.base)
        self.assertEqual(self.git("tag", "--list", remote=True), "")
        self.assertEqual(self.state()["events"], [])

    def test_package_only_does_not_publish(self):
        self.run_release()
        self.assertTrue((self.work / "build/release" / ARCHIVE).is_file())
        self.assertEqual(self.state()["notarizations"], 1)
        self.assertIsNone(self.state()["release"])
        self.assert_remote_untouched()

    def test_publishes_matching_refs_and_verified_assets(self):
        notes = self.root / "notes.md"
        notes.write_text("Calculator release notes.\n")
        self.env["GH_HOST"] = "enterprise.example.invalid"
        self.run_release("--publish", "--notes-file", str(notes))
        self.assertEqual(self.git("rev-parse", "refs/heads/main", remote=True), self.head)
        self.assertEqual(self.git("rev-parse", "refs/tags/" + TAG + "^{}", remote=True), self.head)
        state = self.state()
        self.assertFalse(state["release"]["draft"])
        self.assertEqual(state["release"]["notes"], notes.read_text())
        expected_assets = sorted([ARCHIVE, ARCHIVE + ".sha256"])
        self.assertEqual(sorted(state["release"]["assets"]), expected_assets)
        archive = (self.root / "assets" / ARCHIVE).read_bytes()
        checksum = (self.root / "assets" / (ARCHIVE + ".sha256")).read_text().split()
        self.assertEqual(checksum, [hashlib.sha256(archive).hexdigest(), ARCHIVE])
        self.assertEqual(state["events"][0], ["create", True])
        self.assertEqual(state["events"][-2:], [["publish", expected_assets], ["install", False]])
        self.assertEqual((self.root / "installed.zip").read_bytes(), archive)
        self.assertEqual(state["builds"], 1)

    def test_resumes_upload_without_rebuilding_or_overwriting(self):
        self.state(fail_upload_at=2)
        result = self.run_release("--publish", succeeds=False)
        self.assertIn("fixture upload interrupted", result.stderr)
        state = self.state()
        self.assertTrue(state["release"]["draft"])
        self.assertEqual(state["release"]["assets"], [ARCHIVE])
        self.assertFalse(any(event[0] == "install" for event in state["events"]))
        first_archive = (self.root / "assets" / ARCHIVE).read_bytes()

        # A valid hash cannot establish that a cached package has the intended version.
        cached = self.work / "build/release" / ARCHIVE
        checksum = cached.with_suffix(".zip.sha256")
        original_checksum = checksum.read_bytes()
        with zipfile.ZipFile(io.BytesIO(first_archive)) as original, zipfile.ZipFile(cached, "w") as changed:
            for entry in original.infolist():
                data = original.read(entry)
                if entry.filename == "AppFinder.app/Contents/Info.plist":
                    info = plistlib.loads(data)
                    info["CFBundleShortVersionString"] = "9.9.9"
                    data = plistlib.dumps(info)
                changed.writestr(entry, data)
        checksum.write_text(hashlib.sha256(cached.read_bytes()).hexdigest() + "  " + ARCHIVE + "\n")
        result = self.run_release("--publish", succeeds=False)
        self.assertIn("archived version 9.9.9 differs from expected " + VERSION, result.stderr)
        self.assertEqual(self.state(), state)
        cached.write_bytes(first_archive)
        checksum.write_bytes(original_checksum)

        self.run_release("--publish")
        state = self.state()
        self.assertEqual(state["builds"], 1)
        self.assertEqual(state["notarizations"], 1)
        self.assertEqual((self.root / "assets" / ARCHIVE).read_bytes(), first_archive)
        self.assertEqual(state["events"].count(["upload", ARCHIVE]), 1)
        self.assertFalse(any(event[0] == "delete" for event in state["events"]))
        self.assertFalse(state["release"]["draft"])

    def test_rejects_conflicting_remote_annotated_tag(self):
        self.git("tag", "-a", TAG, self.base, "-m", "Existing version")
        self.git("push", "origin", "refs/tags/" + TAG)
        self.git("tag", "-d", TAG)
        result = self.run_release("--publish", succeeds=False)
        self.assertIn(TAG + " points to " + self.base, result.stderr)
        self.assertEqual(self.git("rev-parse", "refs/tags/" + TAG + "^{}", remote=True), self.base)
        self.assertEqual(self.state()["builds"], 0)
        self.assertEqual(self.state()["events"], [])

    def test_leaves_published_release_unchanged(self):
        self.git("tag", "-a", TAG, "-m", "Existing version")
        self.git("push", "origin", "refs/tags/" + TAG)
        published = {"draft": False, "tag": TAG, "url": "https://github.com/" + REPO + "/releases/tag/" + TAG,
                     "assets": ["existing.zip"], "notes": "Existing public notes"}
        self.state(release=published)
        result = self.run_release("--publish", succeeds=False)
        self.assertIn("already published", result.stderr)
        self.assertEqual(self.state()["release"], published)
        self.assertEqual(self.state()["builds"], 0)
        self.assertEqual(self.state()["events"], [])

        # Publication by another actor during the run must also prevent uploads.
        concurrent = dict(published, assets=[])
        self.state(release=dict(concurrent, draft=True), publish_on_asset_view=True)
        result = self.run_release("--publish", succeeds=False)
        self.assertIn("already published", result.stderr)
        self.assertEqual(self.state()["release"], concurrent)
        self.assertEqual(self.state()["upload_attempts"], 0)
        self.assertEqual(self.state()["events"], [])

    def test_preflight_failure_never_builds_or_mutates_remote(self):
        notes = self.root / "notes.md"
        notes.write_text("Release notes")
        cases = [("unsigned publish", ["--publish", "--skip-notarize"], "--publish cannot be combined with --skip-notarize"),
                 ("unused notes", ["--notes-file", str(notes)], "--notes-file requires --publish"),
                 ("dirty checkout", ["--publish"], "uncommitted changes"),
                 ("GitHub unavailable", ["--publish"], "cannot query GitHub releases")]
        for name, args, diagnostic in cases:
            with self.subTest(name=name):
                dirty = self.work / "unfinished.txt"
                if name == "dirty checkout":
                    dirty.write_text("unfinished changes")
                self.state(query_failure=name == "GitHub unavailable")
                result = self.run_release(*args, succeeds=False)
                self.assertIn(diagnostic, result.stderr)
                self.assertEqual(self.state()["builds"], 0)
                self.assert_remote_untouched()
                if dirty.exists():
                    dirty.unlink()

    def test_download_or_publication_failure_prevents_installation(self):
        for failure, diagnostic in (("corrupt_download", "differs from"),
                                    ("reject_publish", "fixture publication failure")):
            with self.subTest(failure=failure):
                self.state(corrupt_download=failure == "corrupt_download", reject_publish=failure == "reject_publish")
                result = self.run_release("--publish", succeeds=False)
                self.assertIn(diagnostic, result.stderr)
                state = self.state()
                self.assertTrue(state["release"]["draft"])
                self.assertFalse(any(event[0] in ("publish", "install") for event in state["events"]))

    def test_installation_failure_preserves_published_release(self):
        self.state(fail_install=True)
        result = self.run_release("--publish", succeeds=False)
        state = self.state()
        expected_assets = sorted([ARCHIVE, ARCHIVE + ".sha256"])
        self.assertFalse(state["release"]["draft"])
        self.assertEqual(sorted(state["release"]["assets"]), expected_assets)
        self.assertEqual(state["events"][-2:], [["publish", expected_assets], ["install", False]])
        self.assertEqual(self.git("rev-parse", "refs/tags/" + TAG + "^{}", remote=True), self.head)
        self.assertIn("fixture installation failure", result.stderr)
        self.assertIn("published", result.stderr)
        self.assertIn("local installation or restart failed", result.stderr)
        self.assertIn("install.sh --archive", result.stderr)
        self.assertIn(str(self.work / "build/release" / ARCHIVE), result.stderr)

    def test_source_change_or_notary_rejection_prevents_pushing(self):
        for failure, diagnostic in (("edit_during_build", "uncommitted changes"),
                                    ("reject_notary", "notarization did not succeed")):
            with self.subTest(failure=failure):
                self.state(edit_during_build=failure == "edit_during_build", reject_notary=failure == "reject_notary")
                result = self.run_release("--publish", succeeds=False)
                self.assertIn(diagnostic, result.stderr)
                self.assert_remote_untouched()
                self.git("restore", "feature.txt")


if __name__ == "__main__":
    tool_name = Path(sys.argv[0]).name
    if tool_name in TOOLS:
        sys.exit(fake_tool(tool_name, sys.argv[1:]))
    unittest.main(verbosity=2)
