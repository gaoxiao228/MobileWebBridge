#!/usr/bin/env node
import { closeSync, cpSync, mkdtempSync, openSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

// 每次在系统临时目录创建全新宿主，避免 Example 的 Pods、缓存工程或签名设置掩盖接入问题。
if (process.platform !== 'darwin') {
  console.error('iOS 消费检查需要 macOS、完整 Xcode、CocoaPods 和 Node.js。');
  process.exit(1);
}
const repository = fileURLToPath(new URL('../', import.meta.url));
const workspace = mkdtempSync(join(tmpdir(), 'mwb-ios-consumer-'));
cpSync(join(repository, 'test/consumers/ios'), workspace, { recursive: true });

// 使用 Ruby 单引号字面量传递仓库路径，兼容空格、引号与插值字符。
const podPath = repository.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
writeFileSync(join(workspace, 'Podfile'), `platform :ios, '15.0'
use_frameworks!
install! 'cocoapods', :integrate_targets => true
project 'MWBConsumer.xcodeproj'
target 'MWBConsumer' do
  pod 'MobileWebBridge', :path => '${podPath}'
end
`);
console.log(`iOS 独立宿主及日志：${workspace}`);

// 复用 PATH 中已有工具；不下载依赖工具，不启动模拟器或设备，完整失败日志保留在临时目录。
function run(command, args, logName) {
  const log = join(workspace, logName);
  const descriptor = openSync(log, 'w');
  let result;
  try {
    result = spawnSync(command, args, {
      cwd: workspace,
      env: { ...process.env, COCOAPODS_DISABLE_STATS: 'true' },
      stdio: ['ignore', descriptor, descriptor],
    });
  } finally {
    closeSync(descriptor);
  }
  if (result.error || result.status !== 0) {
    console.error(readFileSync(log, 'utf8').slice(-8000));
    console.error(`${command} 失败：${result.error?.message ?? `退出码 ${result.status}`}; 日志：${log}`);
    process.exit(1);
  }
  console.log(`通过：${command} ${args.join(' ')}（${log}）`);
}

run('pod', ['install'], 'pod-install.log');
run('xcodebuild', [
  '-workspace', 'MWBConsumer.xcworkspace',
  '-scheme', 'MWBConsumer',
  '-configuration', 'Release',
  '-destination', 'generic/platform=iOS',
  '-derivedDataPath', join(workspace, 'DerivedData'),
  'CODE_SIGNING_ALLOWED=NO',
  'CODE_SIGNING_REQUIRED=NO',
  'build',
], 'xcodebuild.log');

// 检查最终宿主中的资源，避免 Podspec 声明存在但清单没有随 App 分发。
const appPath = join(workspace, 'DerivedData/Build/Products/Release-iphoneos/MWBConsumer.app');
// 默认错误页必须随 CocoaPods 消费进入最终宿主，且保留完整的独立资源 Bundle。
for (const name of ['index.html', 'error.css', 'error.js', 'runtime.js']) {
  const matches = readdirSync(appPath, { recursive: true }).filter(path =>
    path.endsWith(`MobileWebBridgeErrorPage.bundle/${name}`));
  assert.equal(matches.length, 1, `错误页资源缺失或重复：${name}`);
  assert.ok(readFileSync(join(appPath, matches[0])).length > 0);
}
console.log('已验证宿主默认错误页资源');
// CocoaPods 可能将 Bundle 放在 App 根目录或嵌入的动态 Framework 中。
const manifests = readdirSync(appPath, { recursive: true }).filter(path =>
  path.endsWith('MobileWebBridgePrivacy.bundle/PrivacyInfo.xcprivacy'));
assert.equal(manifests.length, 1, '宿主必须包含且仅包含一份 MWB 隐私清单');
const manifestPath = join(appPath, manifests[0]);
const manifest = JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', manifestPath], { encoding: 'utf8' }));
assert.equal(manifest.NSPrivacyTracking, false);
assert.deepEqual(manifest.NSPrivacyTrackingDomains, []);
assert.deepEqual(manifest.NSPrivacyCollectedDataTypes, []);
const reasons = Object.fromEntries(manifest.NSPrivacyAccessedAPITypes.map(entry =>
  [entry.NSPrivacyAccessedAPIType, entry.NSPrivacyAccessedAPITypeReasons]));
assert.deepEqual(reasons, {
  NSPrivacyAccessedAPICategoryUserDefaults: ['C56D.1'],
  NSPrivacyAccessedAPICategorySystemBootTime: ['35F9.1'],
});
console.log(`已验证宿主隐私清单：${manifestPath}`);
