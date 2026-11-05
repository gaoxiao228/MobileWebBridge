import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const sdk = join(root, 'MWB-JS');
const require = createRequire(join(sdk, 'package.json'));
const temporary = mkdtempSync(join(tmpdir(), 'mwb-js-consumer-'));

try {
  // 从真实打包产物安装到独立工程，不使用源码引用或工作区 node_modules 链接。
  const packed = JSON.parse(execFileSync('npm', ['pack', '--json', '--pack-destination', temporary, '--ignore-scripts=false'], {
    cwd: sdk, encoding: 'utf8', stdio: ['inherit', 'pipe', 'inherit'],
  }));
  assert.equal(packed.length, 1);
  const { filename, version } = packed[0];
  const consumer = join(temporary, 'consumer');
  mkdirSync(consumer);
  writeFileSync(join(consumer, 'package.json'), JSON.stringify({ private: true, type: 'module' }));
  execFileSync('npm', ['install', join(temporary, filename), '--ignore-scripts', '--no-audit', '--no-fund', '--package-lock=false', '--registry=https://registry.npmjs.org/'], {
    cwd: consumer, stdio: 'inherit',
  });
  // SDK 的目标运行环境是浏览器；此处仅提供宿主全局对象，不模拟原生返回。
  const runtime = `
    import assert from 'node:assert/strict';
    import {readFileSync} from 'node:fs';
    import vm from 'node:vm';
    globalThis.window = {};
    Object.defineProperty(globalThis, 'navigator', {value: {userAgent: 'MWB consumer check'}});
    const {mwb, createMWB, defineNativePlugin} = await import('mobile-web-bridge');
    assert.equal(mwb.version, ${JSON.stringify(version)});
    assert.equal(mwb.basic.toast, mwb.toast);
    assert.equal(typeof mwb.basic.notifyPageReady, 'function');
    assert.equal(mwb.basic.notifyPageReady, mwb.notifyPageReady);
    const payment = defineNativePlugin()({name: 'payment'});
    assert.equal(typeof createMWB({plugins: [payment]}).payment.pay, 'function');
    const browser = {window: {}, navigator: {userAgent: 'MWB consumer check'}, setTimeout, console};
    vm.runInNewContext(readFileSync('node_modules/mobile-web-bridge/dist/mwb.iife.js', 'utf8'), browser);
    assert.equal(browser.window.mwb.version, ${JSON.stringify(version)});
    assert.equal(typeof browser.window.mwb.basic.notifyPageReady, 'function');
  `;
  execFileSync(process.execPath, ['--input-type=module', '-e', runtime], { cwd: consumer, stdio: 'inherit' });
  // 类型检查引用已安装包的公开声明，同时覆盖 basic、兼容入口和业务插件推导。
  writeFileSync(join(consumer, 'consumer.ts'), `
    import {mwb, createMWB, defineNativePlugin, type GenericAsyncResult} from 'mobile-web-bridge';
    const payment = defineNativePlugin<{pay(params: {orderId: string}): Promise<GenericAsyncResult<{paid: boolean}>>}>()({name: 'payment'});
    createMWB({plugins: [payment]}).payment.pay({orderId: 'example'});
    mwb.basic.getStorageSync<string>('key');
    mwb.getStorageSync<string>('key');
    const ready: Promise<GenericAsyncResult<void>> = mwb.basic.notifyPageReady();
    void ready;
  `);
  execFileSync(process.execPath, [require.resolve('typescript/lib/tsc.js'), '--noEmit', '--strict', '--skipLibCheck', '--target', 'ES2022', '--module', 'ESNext', '--moduleResolution', 'Bundler', 'consumer.ts'], {
    cwd: consumer, stdio: 'inherit',
  });
  for (const name of ['LICENSE', 'THIRD_PARTY_NOTICES.md']) {
    assert.ok(readFileSync(join(consumer, 'node_modules/mobile-web-bridge', name), 'utf8').includes('Permission is hereby granted'));
  }
  console.log(`PASS: 独立 JS 消费端安装、ESM/IIFE、类型和许可检查（${version}）`);
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
