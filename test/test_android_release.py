"""隔离测试发布边界；不使用真实 Token、GPG 密钥或远程发布。"""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/release-android.py"
SPEC = importlib.util.spec_from_file_location("android_release", SCRIPT)


class AndroidReleaseTests(unittest.TestCase):
    """真实解析和子进程测试结合外部发布服务的隔离替身。"""

    @classmethod
    def setUpClass(cls):
        if not SCRIPT.exists():
            raise AssertionError("Android 一键发布脚本尚未实现")
        cls.release = importlib.util.module_from_spec(SPEC)
        SPEC.loader.exec_module(cls.release)

    def test_versions_require_explicit_semver(self):
        for version in ["patch", "1.0", "v1.0.0", "01.0.0", "1.0.0+build", "1.0.0-beta.01", "1.0.0-SNAPSHOT"]:
            with self.subTest(version=version), self.assertRaises(self.release.ReleaseError):
                self.release.validate_version(version)
        self.release.validate_version("1.0.0-beta.1")

    def test_dotenv_values_are_literal_without_shell_evaluation(self):
        text = '# 注释\nMAVEN_CENTRAL_USERNAME="user"\nMAVEN_CENTRAL_PASSWORD=\'$(touch /tmp/should-never-run) # literal\'\nGPG_KEY_PASSWORD="a\\nb\\\\c"\n'
        values = self.release.parse_env(text)
        self.assertEqual(values["MAVEN_CENTRAL_PASSWORD"], "$(touch /tmp/should-never-run) # literal")
        self.assertEqual(values["GPG_KEY_PASSWORD"], "a\nb\\c")

    def test_invalid_dotenv_does_not_expose_values(self):
        for text in ['MAVEN_CENTRAL_PASSWORD="SECRET', 'BAD_KEY=SECRET', 'MAVEN_CENTRAL_PASSWORD=x\nMAVEN_CENTRAL_PASSWORD=SECRET']:
            with self.subTest(text=text), self.assertRaises(self.release.ReleaseError) as error:
                self.release.parse_env(text)
            self.assertNotIn("SECRET", str(error.exception))

    def test_env_round_trip_is_private(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".env.android-release"
            values = {"MAVEN_CENTRAL_USERNAME": "user", "MAVEN_CENTRAL_PASSWORD": 'a"$\\# 密码', "GPG_KEY_FINGERPRINT": "A" * 40}
            self.release.write_env(path, values)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(self.release.load_env(path), values)
            self.release.write_env(path, {"MAVEN_CENTRAL_USERNAME": "new"})
            self.assertEqual(self.release.load_env(path), {"MAVEN_CENTRAL_USERNAME": "new"})

    def test_env_rejects_public_permissions_and_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".env"
            path.write_text('MAVEN_CENTRAL_PASSWORD="secret"\n')
            path.chmod(0o644)
            with self.assertRaises(self.release.ReleaseError):
                self.release.load_env(path)
            link = Path(directory) / ".link"
            link.symlink_to(path)
            with self.assertRaises(self.release.ReleaseError):
                self.release.write_env(link, {})

    def test_tracked_config_is_not_read_as_release_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / ".env.android-release"
            self.release.write_env(path, {"MAVEN_CENTRAL_PASSWORD": "SECRET"})
            with patch.object(self.release, "ROOT", root), patch.object(self.release, "run", return_value=".env.android-release\n"):
                with self.assertRaises(self.release.ReleaseError):
                    self.release.load_env(path)

    def test_native_env_names_override_file_values(self):
        env = {"MAVEN_CENTRAL_USERNAME": "ENV_USER", "MAVEN_CENTRAL_PASSWORD": "ENV_PASSWORD", "ORG_GRADLE_PROJECT_signingInMemoryKey": "PRIVATE_KEY"}
        result = self.release.prepare_credentials(env, {"MAVEN_CENTRAL_USERNAME": "FILE_USER", "MAVEN_CENTRAL_PASSWORD": "FILE_PASSWORD"})
        self.assertEqual(result["ORG_GRADLE_PROJECT_mavenCentralUsername"], "ENV_USER")
        self.assertEqual(result["ORG_GRADLE_PROJECT_mavenCentralPassword"], "ENV_PASSWORD")

    def test_gpg_fingerprint_selection_excludes_revoked_or_expired_keys(self):
        data = '\n'.join(['sec:u:4096:1:ID:0:0:::::scSC:', 'fpr:::::::::' + 'A' * 40 + ':', 'sec:r:4096:1:ID:0:0:::::scSC:', 'fpr:::::::::' + 'B' * 40 + ':', 'sec:e:4096:1:ID:0:0:::::scSC:', 'fpr:::::::::' + 'C' * 40 + ':'])
        self.assertEqual(self.release.signing_fingerprints(data), ["A" * 40])

    def test_remote_404_means_absent_but_403_or_timeout_stop(self):
        for code in (403, 429, 500):
            with self.subTest(code=code), patch.object(self.release, "urlopen", side_effect=HTTPError("url", code, "blocked", {}, None)):
                with self.assertRaises(self.release.ReleaseError):
                    self.release.remote_exists("1.0.0")
        with patch.object(self.release, "urlopen", side_effect=HTTPError("url", 404, "absent", {}, None)):
            self.assertFalse(self.release.remote_exists("1.0.0"))
        with patch.object(self.release, "urlopen", side_effect=URLError("timeout")):
            with self.assertRaises(self.release.ReleaseError):
                self.release.remote_exists("1.0.0")

    def test_published_version_is_detected(self):
        with patch.object(self.release, "urlopen") as request:
            request.return_value.__enter__.return_value.read.return_value = b"pom"
            self.assertTrue(self.release.remote_exists("0.1.0"))

    def test_signing_credentials_reach_only_publication_process(self):
        base = {"PATH": os.environ["PATH"], "ORG_GRADLE_PROJECT_mavenCentralPassword": "ENV_TOKEN"}
        values = {"MAVEN_CENTRAL_USERNAME": "USER", "MAVEN_CENTRAL_PASSWORD": "FILE_TOKEN", "GPG_KEY_FINGERPRINT": "A" * 40, "GPG_KEY_PASSWORD": "PASSPHRASE"}
        with patch.object(self.release, "run", return_value="-----BEGIN PGP PRIVATE KEY BLOCK-----\nKEY_DATA\n-----END PGP PRIVATE KEY BLOCK-----") as command:
            env = self.release.prepare_credentials(base, values)
        self.assertEqual(env["ORG_GRADLE_PROJECT_mavenCentralPassword"], "ENV_TOKEN")
        self.assertIn("KEY_DATA", env["ORG_GRADLE_PROJECT_signingInMemoryKey"])
        self.assertNotIn("PASSPHRASE", json.dumps(command.call_args.args))
        self.assertEqual(command.call_args.kwargs["input_text"], "PASSPHRASE\n")
        sanitized = self.release.check_environment(env)
        self.assertNotIn("ORG_GRADLE_PROJECT_signingInMemoryKey", sanitized)
        self.assertNotIn("ORG_GRADLE_PROJECT_mavenCentralPassword", sanitized)
        self.assertEqual(sanitized["ORG_GRADLE_PROJECT_mwbCentral"], "false")

    def test_missing_credentials_stop_before_gpg_export(self):
        with patch.object(self.release, "run") as command:
            with self.assertRaises(self.release.ReleaseError):
                self.release.prepare_credentials({}, {})
            command.assert_not_called()

    def test_dry_run_never_reads_credentials_exports_keys_or_checks_network(self):
        options = self.release.options(["1.0.0", "--dry-run"])
        with patch.object(self.release, "resolve_environment", return_value={}), patch.object(self.release, "run_checks") as checks, patch.object(self.release, "load_env", side_effect=AssertionError("读取了凭据")), patch.object(self.release, "prepare_credentials", side_effect=AssertionError("导出了密钥")), patch.object(self.release, "remote_exists", side_effect=AssertionError("访问了网络")), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.release.release(options), 0)
            checks.assert_called_once()

    def test_failed_checks_do_not_upload(self):
        options = self.release.options(["1.0.0"])
        with patch.object(self.release, "resolve_environment", return_value={}), patch.object(self.release, "verify_source"), patch.object(self.release, "remote_exists", return_value=False), patch.object(self.release, "run_checks", side_effect=self.release.ReleaseError("测试失败")), patch.object(self.release, "prepare_credentials") as signing:
            with self.assertRaises(self.release.ReleaseError):
                self.release.release(options)
            signing.assert_not_called()

    def test_existing_version_stops_before_checks_or_signing(self):
        options = self.release.options(["0.1.0"])
        with patch.object(self.release, "resolve_environment", return_value={}), patch.object(self.release, "verify_source"), patch.object(self.release, "remote_exists", return_value=True), patch.object(self.release, "run_checks") as checks:
            with self.assertRaises(self.release.ReleaseError):
                self.release.release(options)
            checks.assert_not_called()

    def test_formal_release_uses_automatic_task_and_public_consumer(self):
        options = self.release.options(["1.0.0", "--tag", "2.0.0"])
        with patch.object(self.release, "resolve_environment", return_value={}), patch.object(self.release, "verify_source") as source, patch.object(self.release, "remote_exists", return_value=False), patch.object(self.release, "run_checks"), patch.object(self.release, "load_env", return_value={}), patch.object(self.release, "prepare_credentials", return_value={"ORG_GRADLE_PROJECT_mavenCentralUsername": "USER", "ORG_GRADLE_PROJECT_mavenCentralPassword": "TOKEN"}), patch.object(self.release, "wait_for_publication"), patch.object(self.release, "run") as command, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.release.release(options), 0)
        self.assertEqual(source.call_count, 2)
        self.assertTrue(all(call.args == ("2.0.0",) for call in source.call_args_list))
        invocations = [call.args[0] for call in command.call_args_list]
        self.assertTrue(any(":mwb:publishAndReleaseToMavenCentral" in args for args in invocations))
        self.assertTrue(any("-PmwbRepository=https://repo.maven.apache.org/maven2" in args for args in invocations))

    def test_download_failure_after_upload_does_not_retry_upload(self):
        options = self.release.options(["1.0.0"])
        with patch.object(self.release, "resolve_environment", return_value={}), patch.object(self.release, "verify_source"), patch.object(self.release, "remote_exists", return_value=False), patch.object(self.release, "run_checks"), patch.object(self.release, "load_env", return_value={}), patch.object(self.release, "prepare_credentials", return_value={"ORG_GRADLE_PROJECT_mavenCentralUsername": "USER", "ORG_GRADLE_PROJECT_mavenCentralPassword": "TOKEN"}), patch.object(self.release, "wait_for_publication", side_effect=self.release.ReleaseError("403")), patch.object(self.release, "run") as command, contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(self.release.release(options), 2)
        self.assertIn("不要重复上传", output.getvalue())
        self.assertEqual(sum(":mwb:publishAndReleaseToMavenCentral" in call.args[0] for call in command.call_args_list), 1)

    def test_failed_upload_reports_uncertain_remote_state_without_retry(self):
        options = self.release.options(["1.0.0"])
        with patch.object(self.release, "resolve_environment", return_value={}), patch.object(self.release, "verify_source"), patch.object(self.release, "remote_exists", return_value=False), patch.object(self.release, "run_checks"), patch.object(self.release, "load_env", return_value={}), patch.object(self.release, "prepare_credentials", return_value={"ORG_GRADLE_PROJECT_mavenCentralUsername": "USER", "ORG_GRADLE_PROJECT_mavenCentralPassword": "TOKEN"}), patch.object(self.release, "run", side_effect=self.release.ReleaseError("连接中断")), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(self.release.release(options), 2)
        self.assertIn("Portal", output.getvalue())
        self.assertIn("不要重复上传", output.getvalue())

    def test_source_change_during_checks_or_credential_input_prevents_upload(self):
        for final_state in (self.release.ReleaseError("工作区已变更"), "different-commit"):
            options = self.release.options(["1.0.0"])
            with self.subTest(final_state=final_state), patch.object(self.release, "resolve_environment", return_value={}), patch.object(self.release, "verify_source", side_effect=["original-commit", final_state]), patch.object(self.release, "remote_exists", return_value=False), patch.object(self.release, "run_checks"), patch.object(self.release, "load_env", return_value={}), patch.object(self.release, "prepare_credentials", return_value={"ORG_GRADLE_PROJECT_mavenCentralUsername": "USER", "ORG_GRADLE_PROJECT_mavenCentralPassword": "TOKEN"}), patch.object(self.release, "wait_for_publication"), patch.object(self.release, "run") as command:
                with self.assertRaises(self.release.ReleaseError):
                    self.release.release(options)
                command.assert_not_called()

    def test_command_output_redacts_secrets_even_on_failure(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output), self.assertRaises(self.release.ReleaseError) as error:
            self.release.run([sys.executable, "-c", 'print("test-secret-token"); raise SystemExit(7)'], env=dict(os.environ), secrets=["test-secret-token"])
        self.assertNotIn("test-secret-token", output.getvalue() + str(error.exception))
        self.assertIn("[REDACTED]", output.getvalue())

    def test_source_requires_clean_tree_and_tag_pointing_to_head(self):
        for results in [[" M source.kt\n"], ["", "tag-sha", "head-sha"]]:
            with self.subTest(results=results), patch.object(self.release, "run", side_effect=results):
                with self.assertRaises(self.release.ReleaseError):
                    self.release.verify_source("1.0.0")

    def test_main_handles_keyboard_interrupt_without_traceback(self):
        with patch.object(self.release, "release", side_effect=KeyboardInterrupt), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(self.release.main(["1.0.0", "--dry-run"]), 130)
        self.assertNotIn("Traceback", output.getvalue())

    def test_setup_requires_interactive_input_to_avoid_echoing_secrets(self):
        with patch.object(self.release.sys.stdin, "isatty", return_value=False), patch.object(self.release.getpass, "getpass") as secret:
            with self.assertRaises(self.release.ReleaseError):
                self.release.setup(Path("/tmp/.env-test"))
            secret.assert_not_called()

    def test_setup_saves_token_without_printing_or_passing_it_as_arguments(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".env.android-release"
            gpg = 'sec:u:4096:1:ID:0:0:::::scSC:\nfpr:::::::::' + 'A' * 40 + ':'
            with patch.object(self.release.sys.stdin, "isatty", return_value=True), patch.object(self.release.shutil, "which", return_value="gpg"), patch.object(self.release, "run", return_value=gpg) as command, patch("builtins.input", return_value="1"), patch.object(self.release.getpass, "getpass", side_effect=["USER_SECRET", "TOKEN_SECRET", "KEY_PASSWORD_SECRET"]), contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(self.release.setup(path), 0)
            self.assertEqual(self.release.load_env(path)["MAVEN_CENTRAL_PASSWORD"], "TOKEN_SECRET")
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            for secret in ("USER_SECRET", "TOKEN_SECRET", "KEY_PASSWORD_SECRET"):
                self.assertNotIn(secret, output.getvalue() + str(command.call_args_list))

    def test_cli_dry_run_with_fake_tools_never_reads_env_or_exports_secrets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            shutil.copy2(SCRIPT, root / "scripts/release-android.py")
            (root / "scripts/check-android-consumer.py").write_text('import os\nassert not any(k.startswith("ORG_GRADLE_PROJECT_signing") or k.startswith("ORG_GRADLE_PROJECT_mavenCentral") for k in os.environ)\nprint("fake consumer passed")\n')
            (root / "MWB-Android").mkdir()
            wrapper = root / "MWB-Android/gradlew"
            wrapper.write_text('#!/bin/sh\necho "fake unit tests passed"\n')
            wrapper.chmod(0o755)
            (root / "jdk/bin").mkdir(parents=True)
            java = root / "jdk/bin/java"
            java.write_text('#!/bin/sh\necho \'openjdk 17.0.1\'\n')
            java.chmod(0o755)
            (root / "jdk/release").write_text('JAVA_VERSION="17.0.1"\n')
            sdk = root / "sdk/platforms/android-35"
            sdk.mkdir(parents=True)
            (sdk / "android.jar").touch()
            (root / ".env.android-release").write_text('THIS MUST NOT BE PARSED\n')
            env = dict(os.environ, JAVA_HOME=str(root / "jdk"), ANDROID_HOME=str(root / "sdk"), ORG_GRADLE_PROJECT_mavenCentralPassword="DO_NOT_PASS_TO_CHECKS", ORG_GRADLE_PROJECT_signingInMemoryKey="DO_NOT_PASS_TO_CHECKS")
            result = subprocess.run([sys.executable, str(root / "scripts/release-android.py"), "1.2.0", "--dry-run"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("fake consumer passed", result.stdout)
            self.assertNotIn("DO_NOT_PASS_TO_CHECKS", result.stdout + result.stderr)

    def test_interrupt_kills_descendant_even_when_group_leader_exits_first(self):
        # 后代忽略 SIGTERM；只等待组长退出会遗留继续执行的后代。
        real_popen = subprocess.Popen
        descendant = []
        spawned = []

        class InterruptingStream:
            def __init__(self, stream):
                self.stream = stream

            def __iter__(self):
                descendant.append(int(self.stream.readline().strip()))
                raise KeyboardInterrupt

            def close(self):
                self.stream.close()

        def launch(*args, **kwargs):
            process = real_popen(*args, **kwargs)
            process.stdout = InterruptingStream(process.stdout)
            spawned.append(process)
            return process

        child_code = 'import os,signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); print(os.getpid(), flush=True); time.sleep(30)'
        parent_code = f'import subprocess,sys,time; subprocess.Popen([sys.executable,"-c",{child_code!r}]); time.sleep(30)'
        try:
            with patch.object(self.release.subprocess, "Popen", side_effect=launch):
                with self.assertRaises(KeyboardInterrupt):
                    self.release.run([sys.executable, "-c", parent_code], env=dict(os.environ))
            running = True
            for _ in range(20):
                state = subprocess.run(["ps", "-o", "stat=", "-p", str(descendant[0])], text=True, capture_output=True).stdout.strip()
                running = bool(state) and not state.startswith("Z")
                if not running:
                    break
                time.sleep(0.05)
            self.assertFalse(running, "中断后仍有后代进程运行")
        finally:
            # RED 阶段同样只清理本测试创建的进程，避免留下测试后代。
            for process in spawned:
                try:
                    os.killpg(process.pid, self.release.signal.SIGKILL)
                except ProcessLookupError:
                    pass


if __name__ == "__main__":
    unittest.main()
