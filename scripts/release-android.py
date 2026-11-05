#!/usr/bin/env python3
"""Android 一键发布：本机 .env 配置、真实预演、签名及 Central 自动发布。"""

from __future__ import annotations

import argparse
import base64
import getpass
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.request import urlopen


ROOT = Path(__file__).resolve().parents[1]
CENTRAL = "https://repo.maven.apache.org/maven2"
ENV_FILE = ROOT / ".env.android-release"
CONFIG_KEYS = {"MAVEN_CENTRAL_USERNAME", "MAVEN_CENTRAL_PASSWORD", "GPG_KEY_FINGERPRINT", "GPG_KEY_PASSWORD"}
GRADLE_PREFIX = "ORG_GRADLE_PROJECT_"


class ReleaseError(Exception):
    """可直接展示、且不包含凭据的发布错误。"""


def validate_version(version: str) -> None:
    """只接受完整 SemVer；正式 Central 流程不处理 SNAPSHOT 或构建元数据。"""
    match = re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?", version)
    if not match or len(version) > 128 or "SNAPSHOT" in version.upper() or (match[4] and any(re.fullmatch(r"0\d+", part) for part in match[4].split("."))):
        raise ReleaseError("请指定完整版本号，例如 0.1.1 或 0.2.0-beta.1；不支持 SNAPSHOT、+build 或隐式递增。")


def options(argv: list[str]) -> argparse.Namespace:
    """setup 与发布共用入口；所有路径都相对脚本仓库而非终端工作目录。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="setup 或显式 Maven 版本号")
    parser.add_argument("--dry-run", action="store_true", help="执行测试及本地消费检查，不读取凭据、不上传")
    parser.add_argument("--tag", help="已存在的多端共享 Tag；默认与版本相同")
    parser.add_argument("--env-file", type=Path, default=ENV_FILE, help="本机隐藏配置文件路径")
    parser.add_argument("--wait-seconds", type=int, default=600, help="上传后等待公共制品的秒数，默认 600")
    args = parser.parse_args(argv)
    if args.version != "setup":
        validate_version(args.version)
    elif args.dry_run or args.tag:
        raise ReleaseError("setup 不接受 --dry-run 或 --tag。")
    if args.wait_seconds < 0 or args.wait_seconds > 3600:
        raise ReleaseError("--wait-seconds 必须在 0 到 3600 之间。")
    args.env_file = args.env_file.expanduser().absolute()
    return args


def parse_env(text: str) -> dict[str, str]:
    """仅解析赋值，不执行 shell、变量替换或命令替换；错误不回显原始值。"""
    values = {}
    for number, line in enumerate(text.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"(?:export\s+)?([A-Z][A-Z0-9_]*)\s*=\s*(.*)", line)
        if not match or match[1] not in CONFIG_KEYS or match[1] in values:
            raise ReleaseError(f"配置文件第 {number} 行无效、字段不支持或重复；请参考示例文件。")
        key, value = match.groups()
        try:
            if value.startswith('"'):
                value = json.loads(value)
                if not isinstance(value, str):
                    raise ValueError()
            elif value.startswith("'"):
                if len(value) < 2 or not value.endswith("'") or "'" in value[1:-1]:
                    raise ValueError()
                value = value[1:-1]
        except (ValueError, json.JSONDecodeError):
            raise ReleaseError(f"配置文件第 {number} 行引号或转义格式无效。") from None
        if "\x00" in value:
            raise ReleaseError(f"配置文件第 {number} 行包含不支持的字符。")
        values[key] = value
    return values


def load_env(path: Path) -> dict[str, str]:
    """只读取当前用户的私有普通文件，避免误用可公开读取的凭据文件。"""
    if not path.exists():
        return {}
    info = path.lstat()
    if path.is_symlink() or not path.is_file() or info.st_mode & 0o077 or info.st_uid != os.getuid():
        raise ReleaseError("凭据文件必须为当前用户拥有的普通文件，权限应为 600；请执行 chmod 600 后重试。")
    if path.is_relative_to(ROOT) and run(["git", "ls-files", "--", str(path)], capture=True).strip():
        raise ReleaseError("凭据文件已被 Git 跟踪，请先处理误提交的凭据并移除跟踪。")
    return parse_env(path.read_text(encoding="utf-8"))


def write_env(path: Path, values: dict[str, str]) -> None:
    """原子写入 0600 文件；不沿符号链接覆盖已有文件。"""
    if path.is_symlink():
        raise ReleaseError("不能将凭据写入符号链接。")
    if not path.parent.is_dir():
        raise ReleaseError("配置文件的父目录不存在。")
    content = "# 本机 Android 发布凭据；禁止提交或分享。\n"
    content += "".join(f"{key}={json.dumps(value, ensure_ascii=False)}\n" for key, value in values.items())
    descriptor, name = tempfile.mkstemp(prefix=".env.android-release-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(content)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def run(command: list[str], *, env: dict[str, str] | None = None, capture: bool = False, input_text: str | None = None, secrets=()) -> str:
    """不用 shell；敏感输出只在内存中捕获，普通日志逐行脱敏。"""
    def redact(value):
        for secret in sorted((part for secret in secrets if secret for part in secret.splitlines() if part), key=len, reverse=True):
            value = value.replace(secret, "[REDACTED]")
        return value

    process = subprocess.Popen(command, cwd=ROOT, env=env, text=True, encoding="utf-8", errors="replace", stdin=subprocess.PIPE if input_text is not None else subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE if capture else subprocess.STDOUT, start_new_session=True)
    try:
        if capture:
            output, _ = process.communicate(input_text)
        else:
            output = ""
            for line in process.stdout:
                print(redact(line), end="", flush=True)
            process.wait()
        if process.returncode:
            raise ReleaseError(f"{Path(command[0]).name} 执行失败（退出码 {process.returncode}）；当前阶段已停止。")
        return output
    except BaseException:
        # Ctrl-C/SIGTERM 同时停止整个子进程组，避免脚本退出后继续上传。
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass
        # 组长退出不代表后代退出；即使组长已结束，也清理忽略 SIGTERM 的后代。
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        raise
    finally:
        for stream in (process.stdin, process.stdout, process.stderr):
            if stream:
                stream.close()


def resolve_environment() -> dict[str, str]:
    """优先复用环境，自动发现 macOS 常用的 JDK 17 和 Android SDK。"""
    env = dict(os.environ)
    if not env.get("JAVA_HOME"):
        candidates = [Path("/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"), Path("/usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home")]
        java_home = next((path for path in candidates if (path / "bin/java").is_file()), None)
        if java_home:
            env["JAVA_HOME"] = str(java_home)
    java = str(Path(env["JAVA_HOME"]) / "bin/java") if env.get("JAVA_HOME") else shutil.which("java")
    if not java:
        raise ReleaseError("未找到 JDK 17，请安装并配置 JAVA_HOME。")
    # release 文件提供确定的主版本，不依赖 java -version 的 stderr 或本地化文本。
    run([java, "--version"], env=check_environment(env), capture=True)
    java_root = Path(env.get("JAVA_HOME", Path(java).resolve().parents[1]))
    release_file = java_root / "release"
    if not release_file.is_file() or not re.search(r'JAVA_VERSION="17(?:[.\"]|$)', release_file.read_text()):
        raise ReleaseError("发布使用 JDK 17；请将 JAVA_HOME 指向 JDK 17。")
    env["JAVA_HOME"] = str(java_root)
    sdk = env.get("ANDROID_HOME") or env.get("ANDROID_SDK_ROOT")
    if not sdk:
        for candidate in [Path.home() / "Library/Android/sdk", Path.home() / "Android/Sdk"]:
            if candidate.is_dir():
                sdk = str(candidate)
                break
    if not sdk or not (Path(sdk) / "platforms/android-35/android.jar").is_file():
        raise ReleaseError("未找到 Android SDK 35，请设置 ANDROID_HOME 并安装 platforms;android-35。")
    env["ANDROID_HOME"] = sdk
    return env


def signing_fingerprints(output: str) -> list[str]:
    """只列出未撤销、未过期且具有签名能力的主密钥指纹。"""
    results = []
    usable = False
    for line in output.splitlines():
        fields = line.split(":")
        if fields[0] == "sec":
            usable = len(fields) > 11 and fields[1] not in {"r", "e", "d", "i"} and "s" in fields[11].lower()
        elif fields[0] == "fpr" and usable:
            results.append(fields[9])
            usable = False
    return results


def setup(path: Path) -> int:
    """一次性保存 Token、指纹和可选口令，不生成私钥文件。"""
    if not sys.stdin.isatty():
        raise ReleaseError("setup 需要交互终端，请在本机终端运行；CI 请使用环境变量。")
    if not shutil.which("gpg"):
        raise ReleaseError("未安装 GPG；macOS 可执行 brew install gnupg。")
    if path.is_relative_to(ROOT):
        tracked = run(["git", "ls-files", "--", str(path)], capture=True).strip()
        if tracked:
            raise ReleaseError("配置文件已被 Git 跟踪，不能写入凭据。")
        try:
            run(["git", "check-ignore", "-q", "--", str(path)], capture=True)
        except ReleaseError:
            raise ReleaseError("仓库内的配置文件必须先加入 .gitignore；建议使用默认路径。") from None
    keys = signing_fingerprints(run(["gpg", "--batch", "--with-colons", "--list-secret-keys", "--fingerprint"], capture=True))
    if not keys:
        raise ReleaseError("未找到有效签名密钥，请先创建 GPG 密钥并公开公钥。")
    for number, fingerprint in enumerate(keys, 1):
        print(f"{number}. {fingerprint}")
    choice = input("选择签名密钥序号 [1]：").strip() or "1"
    if not choice.isdigit() or not 1 <= int(choice) <= len(keys):
        raise ReleaseError("签名密钥序号无效。")
    username = getpass.getpass("Central Token username：")
    password = getpass.getpass("Central Token password：")
    if not username or not password:
        raise ReleaseError("Token username 和 password 均不能为空。")
    passphrase = getpass.getpass("PGP 私钥口令（留空则发布时询问；文件会明文保存所填口令）：")
    values = {"MAVEN_CENTRAL_USERNAME": username, "MAVEN_CENTRAL_PASSWORD": password, "GPG_KEY_FINGERPRINT": keys[int(choice) - 1]}
    if passphrase:
        values["GPG_KEY_PASSWORD"] = passphrase
    write_env(path, values)
    print(f"已保存本机配置：{path}（权限 600）；未执行上传。")
    return 0


def check_environment(env: dict[str, str]) -> dict[str, str]:
    """本地验证不继承发布凭据，并显式关闭公共发布模式。"""
    result = {key: value for key, value in env.items() if not (key.startswith(GRADLE_PREFIX) and any(word in key for word in ("signing", "mavenCentral"))) and key not in CONFIG_KEYS}
    result[GRADLE_PREFIX + "mwbCentral"] = "false"
    return result


def run_checks(version: str, env: dict[str, str]) -> None:
    """真实执行库测试、本地制品检查及独立消费构建。"""
    env = check_environment(env)
    print("[1/3] Android 单元测试", flush=True)
    run([str(ROOT / "MWB-Android/gradlew"), "-p", str(ROOT / "MWB-Android"), ":mwb:testDebugUnitTest", "--console=plain", "-PmwbCentral=false", f"-PmwbVersion={version}"], env=env)
    print("[2/3] 本地制品及独立 Maven 消费检查", flush=True)
    run([sys.executable, str(ROOT / "scripts/check-android-consumer.py"), "--version", version], env=env)


def verify_source(tag: str) -> str:
    """正式发布只使用干净工作区和当前提交上的共享 Tag。"""
    if run(["git", "status", "--porcelain"], capture=True).strip():
        raise ReleaseError("正式发布需要干净工作区，请先提交本轮源码、配置和版本记录。")
    tagged = run(["git", "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}"], capture=True).strip()
    current = run(["git", "rev-parse", "HEAD"], capture=True).strip()
    if tagged != current:
        raise ReleaseError("共享 Tag 未指向当前提交；请使用该 Tag 对应的源码，不要覆盖已发布 Tag。")
    return current


def remote_exists(version: str, suffix: str = ".pom") -> bool:
    """只有确切 404 才表示缺失；访问限制和网络故障必须停止。"""
    url = f"{CENTRAL}/io/github/gaoxiao228/mobile-web-bridge/{version}/mobile-web-bridge-{version}{suffix}"
    try:
        with urlopen(url, timeout=20) as response:
            response.read(1)
        return True
    except HTTPError as error:
        if error.code == 404:
            return False
        raise ReleaseError(f"公共仓库访问失败（HTTP {error.code}），不能据此判断版本是否存在。") from None
    except (URLError, TimeoutError, OSError):
        raise ReleaseError("公共仓库访问超时或网络不可用，未确认版本状态。") from None


def prepare_credentials(env: dict[str, str], values: dict[str, str]) -> dict[str, str]:
    """环境变量优先；私钥只进入正式上传子进程，不存盘或写入命令参数。"""
    result = dict(env)
    for source, target in {"MAVEN_CENTRAL_USERNAME": "mavenCentralUsername", "MAVEN_CENTRAL_PASSWORD": "mavenCentralPassword", "GPG_KEY_PASSWORD": "signingInMemoryKeyPassword"}.items():
        if GRADLE_PREFIX + target not in result and (source in env or source in values):
            result[GRADLE_PREFIX + target] = env.get(source, values.get(source, ""))
    if not all(result.get(GRADLE_PREFIX + key) for key in ("mavenCentralUsername", "mavenCentralPassword")):
        raise ReleaseError("缺少 Central Token，请先执行 setup 或配置 Gradle 环境变量。")
    if not result.get(GRADLE_PREFIX + "signingInMemoryKey"):
        fingerprint = env.get("GPG_KEY_FINGERPRINT") or values.get("GPG_KEY_FINGERPRINT", "")
        if not re.fullmatch(r"(?:[A-Fa-f0-9]{40}|[A-Fa-f0-9]{64})", fingerprint):
            raise ReleaseError("缺少有效 GPG 完整指纹，请先执行 setup。")
        passphrase = result.get(GRADLE_PREFIX + "signingInMemoryKeyPassword")
        if passphrase is None:
            if not sys.stdin.isatty():
                raise ReleaseError("非交互发布需要通过环境变量或本机 .env 提供 GPG_KEY_PASSWORD（无口令可设为空）。")
            passphrase = getpass.getpass("PGP 私钥口令（无口令直接回车）：")
        key = run(["gpg", "--batch", "--pinentry-mode", "loopback", "--passphrase-fd", "0", "--armor", "--export-secret-keys", fingerprint], env=check_environment(env), capture=True, input_text=passphrase + "\n")
        if "-----BEGIN PGP PRIVATE KEY BLOCK-----" not in key:
            raise ReleaseError("GPG 未导出可用私钥，请检查密钥指纹和口令。")
        result[GRADLE_PREFIX + "signingInMemoryKey"] = key
        result[GRADLE_PREFIX + "signingInMemoryKeyPassword"] = passphrase
    return result


def wait_for_publication(version: str, seconds: int) -> None:
    """等待四种公开制品可下载；不自动重试上传。"""
    deadline = time.monotonic() + seconds
    while True:
        if all(remote_exists(version, suffix) for suffix in (".pom", ".aar", "-sources.jar", "-javadoc.jar")):
            return
        if time.monotonic() >= deadline:
            raise ReleaseError("公共制品仍未完整可下载，可能正在验证或同步。")
        print("等待 Central 自动发布及公共仓库同步……", flush=True)
        time.sleep(min(15, max(0, deadline - time.monotonic())))


def release(args: argparse.Namespace) -> int:
    """从检查到公开消费验证；上传开始后的错误一律保留状态不确定提示。"""
    env = resolve_environment()
    source_commit = None
    if not args.dry_run:
        source_commit = verify_source(args.tag or args.version)
        if remote_exists(args.version):
            raise ReleaseError("该版本已存在于 Maven Central，不能覆盖；请使用新版本。")
    run_checks(args.version, env)
    if args.dry_run:
        print("预演通过：未读取发布配置、未导出私钥、未上传。正式发布前须准备共享 Tag 和凭据。")
        return 0
    publication = prepare_credentials(env, load_env(args.env_file))
    try:
        # 构建和口令输入可能耗时；上传前拒绝期间编辑源码或切换提交的情况。
        if verify_source(args.tag or args.version) != source_commit:
            raise ReleaseError("检查期间当前提交发生变化，请重新运行完整发布检查。")
    except BaseException:
        publication.clear()
        raise
    secrets = [value for key, value in publication.items() if key.startswith(GRADLE_PREFIX) and any(word in key for word in ("mavenCentral", "signing"))]
    basic = publication[GRADLE_PREFIX + "mavenCentralUsername"] + ":" + publication[GRADLE_PREFIX + "mavenCentralPassword"]
    secrets.append(base64.b64encode(basic.encode()).decode())
    print("[3/3] 签名、上传并请求 Central 自动公开发布", flush=True)
    try:
        run([str(ROOT / "MWB-Android/gradlew"), "-p", str(ROOT / "MWB-Android"), ":mwb:publishAndReleaseToMavenCentral", "--no-daemon", "--no-configuration-cache", "--console=plain", "-PmwbCentral=true", f"-PmwbVersion={args.version}"], env=publication, secrets=secrets)
        wait_for_publication(args.version, args.wait_seconds)
        run([str(ROOT / "MWB-Android/gradlew"), "-p", str(ROOT / "test/consumers/android"), f"-PmwbRepository={CENTRAL}", f"-PmwbVersion={args.version}", "--refresh-dependencies", "--console=plain", "assembleRelease", "verifyPublishedRuntimeDependencies"], env=check_environment(env))
    except (ReleaseError, KeyboardInterrupt, OSError) as error:
        if isinstance(error, ReleaseError):
            print(f"阶段信息：{error}")
        print("已开始上传，远程发布或公开消费验证状态尚未完整确认。请检查 Central Portal → Deployments；不要重复上传。")
        return 2
    finally:
        # Python 字符串无法保证内存擦除；不再保留可传递给后续子进程的私钥环境。
        publication.clear()
        secrets.clear()
    print(f"已公开发布并通过独立消费编译：io.github.gaoxiao228:mobile-web-bridge:{args.version}")
    return 0


def main(argv: list[str] | None = None) -> int:
    """将可预期错误和中断转换成简短中文提示，不回显环境或配置内容。"""
    try:
        args = options(sys.argv[1:] if argv is None else argv)
        return setup(args.env_file) if args.version == "setup" else release(args)
    except KeyboardInterrupt:
        print("已中断，子进程已停止；若上传已开始，请先核实 Portal 状态。")
        return 130
    except ReleaseError as error:
        print(f"发布已停止：{error}")
        return 1
    except (OSError, EOFError):
        print("发布已停止：工具、配置文件或终端输入不可用，请检查路径和权限。")
        return 1


if __name__ == "__main__":
    # SIGTERM 走同一清理路径，避免留下继续执行发布的 Gradle 子进程。
    def interrupted(*_):
        """将系统终止信号转为可清理的中断。"""
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    sys.exit(main())
