import assert from 'node:assert/strict';
import { test } from 'node:test';
import { catalog } from '../src/catalog.mjs';
import { createDemoState } from '../src/useDemoState.mjs';
import { sampleCode } from '../src/sampleCode.mjs';

test('手机目录按分类和关键词筛选，进入详情后可返回', () => {
  // 目录与详情共用同一份状态，避免手机视图切换时丢失筛选条件。
  const state = createDemoState(catalog);
  state.category.value = 'media';
  state.query.value = '图片';
  assert.ok(state.filtered.value.length > 0);
  assert.ok(state.filtered.value.every(item => item.group === 'media'));
  const selected = state.filtered.value[0];
  state.choose(selected);
  assert.equal(state.view.value, 'detail');
  assert.equal(state.active.value.name, selected.name);
  state.back();
  assert.equal(state.view.value, 'list');
  assert.equal(state.query.value, '图片');
});

test('句柄代码示例跟随编辑后的名称更新', () => {
  const item = catalog.find(entry => entry.name === 'registerHandler');
  const code = sampleCode(item, '["customGreeting"]');
  assert.match(code, /mwb\.registerHandler\("customGreeting", handler\)/);
  assert.doesNotMatch(code, /nativeGreeting/);
});


test('等待绘制参数仅在 iOS 示例中传入，false 保留用于对照', async () => {
  const { resolveArgs } = await import('../src/runner.mjs');
  const item = catalog.find(entry => entry.name === 'navigateTo');
  for (const waitForReady of [true, false]) {
    const input = JSON.stringify([{ url: 'https://example.test/child', waitForReady }]);
    assert.equal(resolveArgs(item, input, { platform: 'ios' })[0].waitForReady, waitForReady);
    assert.equal('waitForReady' in resolveArgs(item, input, { platform: 'android' })[0], false);
    assert.equal('waitForReady' in resolveArgs(item, input, { platform: 'browser' })[0], false);
    assert.match(sampleCode(item, input, 'ios'), /waitForReady/);
    assert.doesNotMatch(sampleCode(item, input, 'android'), /waitForReady/);
  }
});
