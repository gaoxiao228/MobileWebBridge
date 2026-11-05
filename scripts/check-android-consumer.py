#!/usr/bin/env python3
"""本地发布并独立消费 Android AAR；只做编译验证，不安装或启动设备。"""

from __future__ import annotations

import argparse
import io
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path
from zipfile import ZipFile


def verify_publication(repository: Path, version: str) -> None:
    """核对发布物、POM 和随包许可，防止仅 assemble AAR 就被视为可接入。"""
    directory = repository / "io/github/gaoxiao228/mobile-web-bridge" / version
    basename = f"mobile-web-bridge-{version}"
    pom = ET.parse(directory / f"{basename}.pom").getroot()
    namespace = {"m": "http://maven.apache.org/POM/4.0.0"}

    def value(path: str) -> str | None:
        return pom.findtext(path, namespaces=namespace)

    assert value("m:groupId") == "io.github.gaoxiao228"
    assert value("m:artifactId") == "mobile-web-bridge"
    assert value("m:version") == version
    assert value("m:packaging") == "aar"
    assert value("m:url") == "https://github.com/gaoxiao228/MobileWebBridge"
    assert value("m:licenses/m:license/m:name") == "MIT License"
    assert value("m:developers/m:developer/m:id") == "gaoxiao228"
    assert value("m:scm/m:url") == "https://github.com/gaoxiao228/MobileWebBridge"
    dependencies = {
        (dependency.findtext("m:groupId", namespaces=namespace),
         dependency.findtext("m:artifactId", namespaces=namespace),
         dependency.findtext("m:version", namespaces=namespace))
        for dependency in pom.findall("m:dependencies/m:dependency", namespace)
    }
    assert ("androidx.appcompat", "appcompat", "1.7.0") in dependencies
    assert ("com.google.android.gms", "play-services-code-scanner", "16.1.0") in dependencies
    with ZipFile(directory / f"{basename}.aar") as aar:
        assert "AndroidManifest.xml" in aar.namelist()
        # 许可任务生成的 Java 资源应随实际 AAR 中的 classes.jar 分发。
        with ZipFile(io.BytesIO(aar.read("classes.jar"))) as classes:
            assert "META-INF/mobile-web-bridge/LICENSE" in classes.namelist()
            assert "META-INF/mobile-web-bridge/THIRD_PARTY_NOTICES.md" in classes.namelist()
    with ZipFile(directory / f"{basename}-sources.jar") as sources:
        assert "com/mobilewebbridge/MWBConfiguration.kt" in sources.namelist()
        assert "com/mobilewebbridge/plugins/MWBPlugin.kt" in sources.namelist()
    # 文档必须包含 Kotlin 公开 API，避免仅提供空 JAR 或 DSBridge Java 文档。
    with ZipFile(directory / f"{basename}-javadoc.jar") as documentation:
        pages = [name for name in documentation.namelist() if name.endswith(".html")]
        assert any("m-w-b-configuration" in name for name in pages), pages[:10]
        assert any("m-w-b-plugin" in name for name in pages), pages[:10]
    print(f"已验证本机 Maven 发布物：{directory}", flush=True)


def main() -> None:
    """使用仓库自带 Wrapper，允许 CI 通过环境设置 JDK 17 和 Android SDK 35。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="0.1.0", help="候选本地发布版本")
    parser.add_argument("--offline", action="store_true", help="仅使用已有 Gradle 缓存")
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    wrapper = root / "MWB-Android/gradlew"
    repository = root / "MWB-Android/build/maven-repository"
    # 本地消费检查即使继承了发布环境，也不启用 Central 或签名。
    common = ["--console=plain", "-PmwbCentral=false", f"-PmwbVersion={arguments.version}"]
    if arguments.offline:
        common.append("--offline")
    subprocess.run([
        str(wrapper), "-p", str(root / "MWB-Android"),
        ":mwb:publishReleasePublicationToLocalIntegrationRepository", *common
    ], check=True)
    verify_publication(repository, arguments.version)
    subprocess.run([
        str(wrapper), "-p", str(root / "test/consumers/android"),
        f"-PmwbRepository={repository}", "assembleRelease",
        "verifyPublishedRuntimeDependencies", *common
    ], check=True)
    print("Android 独立 Maven 消费编译通过；未执行真机或模拟器验证。", flush=True)


if __name__ == "__main__":
    main()
