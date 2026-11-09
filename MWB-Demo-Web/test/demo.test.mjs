import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { catalog } from '../src/catalog.mjs';
import { createRunner, resolveArgs } from '../src/runner.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));

test('H5 目录覆盖展示方法，但不提供容器就绪入口', () => {
  // 容器就绪能力保留在 SDK，H5 Demo 按产品范围排除该方法入口。
  const source = readFileSync(new URL('MWB-JS/src/apiManifest.ts', `file://${root}`), 'utf8');
  const manifest = source.match(/export const apiMethods = \[([\s\S]*?)\] as const/)?.[1];
  assert.ok(manifest, 'SDK 方法清单应能读取');
  const methods = [...manifest.matchAll(/"([A-Za-z]\w*)"/g)].map(match => match[1]);
  assert.equal(methods.length, 50);
  assert.equal(catalog.length, 49);
  assert.deepEqual(catalog.map(item => item.name).sort(), methods.filter(name => name !== 'notifyPageReady').sort());
  // 已移除的接口不应继续出现在开发者示例页面。
  assert.equal(catalog.some(item => item.name === 'addWaterMark'), false);
  for (const item of catalog) {
    assert.ok(item.title && item.description && item.group);
    assert.ok(Array.isArray(item.args));
  }
});

test('图片占位符缺少输入时阻止原生调用', () => {
  const item = catalog.find(entry => entry.name === 'compressImage');
  assert.throws(() => resolveArgs(item, JSON.stringify(item.args), {}), /先选择图片/);
});

test('删除图片和文件必填参数后不会调用原生方法', async () => {
  for (const name of ['compressImage', 'saveImageToPhotosAlbum', 'convertImagePathToBase64', 'openFile']) {
    let calls = 0;
    const runner = createRunner({ [name]: () => { calls += 1; return { errCode: 0 }; } }, () => {});
    await assert.rejects(runner.run(catalog.find(item => item.name === name), '[]', {}), /必填参数/);
    assert.equal(calls, 0, `${name} 不应进入原生层`);
  }
});

test('普通调用把编辑后的参数交给 SDK 并返回结果', async () => {
  let received;
  const runner = createRunner({ toast: async value => { received = value; return { errCode: 0 }; } }, () => {});
  const item = catalog.find(entry => entry.name === 'toast');
  const result = await runner.run(item, '[{"msg":"测试消息"}]', {});
  assert.deepEqual(received, { msg: '测试消息' });
  assert.deepEqual(result, { errCode: 0 });
});

test('事件订阅与取消复用同一个回调', async () => {
  let subscribed;
  let unsubscribed;
  const events = [];
  const runner = createRunner({
    onAppShow(handler) { subscribed = handler; },
    offAppShow(handler) { unsubscribed = handler; }
  }, event => events.push(event));
  await runner.run(catalog.find(item => item.name === 'onAppShow'), '[]', {});
  subscribed({ source: 'native' });
  await runner.run(catalog.find(item => item.name === 'offAppShow'), '[]', {});
  assert.equal(unsubscribed, subscribed);
  assert.equal(events.length, 1);
  assert.equal(events[0].method, 'onAppShow');
});

test('JS 句柄可以注册、检查并解绑同一个回调', async () => {
  const handlers = new Map();
  const events = [];
  const sdk = {
    registerHandler(name, handler) { handlers.set(name, handler); },
    checkHandlerExist(name) { return handlers.has(name); },
    unRegisterHandler(name, handler) {
      if (handlers.get(name) === handler) handlers.delete(name);
    }
  };
  const runner = createRunner(sdk, event => events.push(event));
  const byName = name => catalog.find(item => item.name === name);
  await runner.run(byName('registerHandler'), '["nativeGreeting"]', {});
  assert.equal(handlers.get('nativeGreeting')('你好'), undefined);
  assert.deepEqual(events, [{ method: 'registerHandler', data: '你好' }]);
  assert.equal(await runner.run(byName('checkHandlerExist'), '["nativeGreeting"]', {}), true);
  await runner.run(byName('unRegisterHandler'), '["nativeGreeting"]', {});
  assert.equal(handlers.size, 0);
});
