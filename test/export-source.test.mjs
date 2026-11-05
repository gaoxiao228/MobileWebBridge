import assert from 'node:assert/strict';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';

/** 使用微型真实目录，捕获缓存泄漏、符号链接外带、权限丢失及覆盖导出目标。 */
test('source export includes public files and preserves originals while excluding local state', () => {
  const temporary = mkdtempSync(join(tmpdir(), 'mwb-export-contract-'));
  const source = join(temporary, 'source');
  const output = join(temporary, 'output');
  const script = resolve('scripts/export-source.mjs');
  assert.ok(existsSync(script), '公开源码导出工具尚未实现');
  const put = (name, value = name) => {
    const path = join(source, name);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, value);
  };
  try {
    for (const name of ['README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', '.gitignore', 'CHANGELOG.md', 'CONTRIBUTING.md', 'SECURITY.md',
      'MobileWebBridge.podspec', '.env.android-release.example', 'docs/native-plugins.md', 'docs/compatibility.md', 'docs/releasing.md',
      'docs/versioning.md', 'docs/integration-checks.md', 'MWB-JS/src/index.ts', 'MWB-Android/gradlew',
      'MWB-iOS/Example/Resources/index.html', 'MWB-Demo-Web/src/main.js']) put(name);
    for (const name of ['MWB-JS/node_modules/private.txt', 'MWB-JS/dist/private.js', 'MWB-Android/.idea/workspace.xml',
      'MWB-Android/local.properties', 'MWB-Android/sample/build/private.apk', 'MWB-iOS/Example/Pods/private.txt',
      'MWB-iOS/Example/App.xcworkspace/xcuserdata/private.xml', 'MWB-JS/.env', 'MWB-iOS/signing.p12',
      'test/consumers/android/.kotlin/private.txt', 'scripts/__pycache__/release.pyc', 'MWB-Android/.env.android-release',
      '.env.android-release', 'docs/android-release-automation-design.md', 'docs/maintainers/private.md',
      'docs/superpowers/private.txt', '.superpowers/private.log', '.impeccable/private.json']) put(name, 'private-fixture');
    // 被复制的脚本从自身所在目录识别源码根，不依赖测试专用参数。
    if (existsSync(script)) cpSync(script, join(source, 'scripts/export-source.mjs'));
    const external = join(temporary, 'external.txt');
    writeFileSync(external, 'external-private-fixture');
    symlinkSync(external, join(source, 'MWB-JS/linked.txt'));
    const chmod = spawnSync('chmod', ['+x', join(source, 'MWB-Android/gradlew')]);
    assert.equal(chmod.status, 0);
    const result = spawnSync(process.execPath, [join(source, 'scripts/export-source.mjs'), output], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(readFileSync(join(output, 'MWB-JS/src/index.ts'), 'utf8'), 'MWB-JS/src/index.ts');
    // 根 Podspec 与公开版本说明属于接入入口，不能在公开导出时遗漏。
    for (const name of ['MobileWebBridge.podspec', '.env.android-release.example', 'docs/versioning.md']) {
      assert.ok(existsSync(join(output, name)), name);
    }
    // 维护文档即使存在于本机，也不能随公开源码导出；原文件必须保留。
    for (const name of ['CONTRIBUTING.md', 'docs/releasing.md', 'docs/integration-checks.md',
      'docs/android-release-automation-design.md', 'docs/maintainers/private.md']) {
      assert.equal(existsSync(join(output, name)), false, name);
      assert.ok(existsSync(join(source, name)), name);
    }
    assert.ok(existsSync(join(output, 'MWB-iOS/Example/Resources/index.html')));
    assert.ok(statSync(join(output, 'MWB-Android/gradlew')).mode & 0o111);
    for (const name of ['MWB-JS/node_modules', 'MWB-JS/dist', 'MWB-JS/.env', 'MWB-JS/linked.txt', 'MWB-Android/.idea',
      'MWB-Android/local.properties', 'MWB-Android/sample/build', 'MWB-iOS/Example/Pods', 'MWB-iOS/signing.p12',
      'MWB-iOS/Example/App.xcworkspace/xcuserdata', 'test/consumers/android/.kotlin',
      '.env.android-release', 'MWB-Android/.env.android-release', 'scripts/__pycache__',
      'docs/superpowers', '.superpowers', '.impeccable']) assert.equal(existsSync(join(output, name)), false, name);
    assert.ok(existsSync(join(source, '.superpowers/private.log')), '本机原文件必须保留');
    const repeated = spawnSync(process.execPath, [join(source, 'scripts/export-source.mjs'), output], { encoding: 'utf8' });
    assert.notEqual(repeated.status, 0, '不能覆盖已有导出目录');
    const nested = spawnSync(process.execPath, [join(source, 'scripts/export-source.mjs'), join(source, 'nested')], { encoding: 'utf8' });
    assert.notEqual(nested.status, 0, '不能递归导出到源码内部');
    assert.equal(existsSync(join(source, 'nested')), false);
  } finally { rmSync(temporary, { recursive: true, force: true }); }
});
