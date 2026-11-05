#!/bin/sh
# 在 macOS 运行真实插件核心，不创建或启动 iOS 模拟器。
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TASK_OUTPUT=$(mktemp -d)
trap 'rm -rf "$TASK_OUTPUT"' EXIT
xcrun clang -fobjc-arc -c "$TASK_ROOT/Sources/Plugins/MWBPluginException.m" -o "$TASK_OUTPUT/exceptions.o"
xcrun swiftc -swift-version 5 -import-objc-header "$TASK_ROOT/Sources/Plugins/MWBPluginException.h" "$TASK_ROOT"/Sources/MWBResult.swift \
  "$TASK_ROOT"/Sources/Plugins/*.swift "$TASK_ROOT"/Example/NetworkPlugin.swift "$TASK_ROOT"/Tests/PluginContract/main.swift \
  "$TASK_OUTPUT/exceptions.o" -o "$TASK_OUTPUT/plugin-contract"
"$TASK_OUTPUT/plugin-contract"
