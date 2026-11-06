import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';

// 运行实际页面及运行时，验证接入方可见的动作和文本行为。
const resource = name => readFileSync(new URL(`../../MWB-ErrorPage/${name}`, import.meta.url), 'utf8');
const context = extra => ({ version: 1, kind: 'network', message: '请检查网络连接后重试。',
  canRetry: true, canGoHome: false, isRetrying: false, ...extra });
function page(extra = {}) {
  const dom = new JSDOM(resource('index.html'), { runScripts: 'outside-only' });
  const calls = [];
  dom.window.eval(resource('error.js'));
  dom.window.eval(resource('runtime.js'));
  const runtime = dom.window.__mwbInstallErrorPage(context(extra), action => calls.push(action));
  return { dom, calls, runtime, document: dom.window.document };
}
test('defaultPageAndRuntime：默认错误页显示标题并调用专用重试动作', () => {
  const { dom, calls, document } = page();
  assert.equal(document.querySelector('h1').textContent, '页面暂时无法打开');
  document.querySelector('#retry').click();
  assert.deepEqual(calls, ['retry']);
  assert.equal(dom.window.mwb, undefined);
  dom.window.close();
});
test('homeAvailability：未配置首页时隐藏按钮，配置后使用专用动作', () => {
  const { dom, document, runtime, calls } = page();
  assert.equal(document.querySelector('#home').hidden, true);
  runtime.update(context({ canGoHome: true }));
  assert.equal(document.querySelector('#home').hidden, false);
  document.querySelector('#home').click();
  assert.deepEqual(calls, ['goHome']);
  dom.window.close();
});
test('retryState：重试期间禁用重复操作，首页仍然可用', () => {
  const { dom, document, runtime, calls } = page({ canGoHome: true });
  runtime.update(context({ canGoHome: true, isRetrying: true }));
  assert.equal(document.querySelector('#retry').disabled, true);
  assert.equal(document.querySelector('#retry').textContent, '正在重新加载…');
  document.querySelector('#retry').click();
  document.querySelector('#home').click();
  assert.deepEqual(calls, ['goHome']);
  dom.window.close();
});
test('escapedMessage：错误消息作为文本显示而非可执行 HTML', () => {
  const text = '<img src=x onerror=alert(1)>';
  const { dom, document } = page({ message: text });
  assert.equal(document.querySelector('#message').textContent, text);
  assert.equal(document.querySelector('img'), null);
  dom.window.close();
});
test('disposedRuntime：旧页面与被替换运行时均不能继续调用原生', () => {
  const { dom, runtime, calls } = page();
  const old = dom.window.mwbErrorPage;
  assert.equal(Object.isFrozen(old.context), true);
  runtime.dispose();
  old.retry(); old.goHome();
  assert.deepEqual(calls, []);
  dom.window.close();
});
