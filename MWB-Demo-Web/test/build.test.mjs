import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { test } from 'node:test';
import { JSDOM } from 'jsdom';

const project = fileURLToPath(new URL('../', import.meta.url));
const root = fileURLToPath(new URL('../../', import.meta.url));
const files = ['index.html', 'navigation-theme.html', 'native-plugins.html', 'styles.css', 'demo.js', 'mwb.iife.js', 'plugins.iife.js', 'LICENSE.txt', 'THIRD_PARTY_NOTICES.txt'];

test('替换演示提供 P 打开 A、A 替换 B 和 B 返回的真实调用入口', async () => {
  // 编译并运行真实 Vue 页面，只替代 WebView 原生桥边界。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const bundle = readFileSync(join(project, 'dist', 'demo.js'), 'utf8');
  for (const platform of ['ios', 'android']) {
    for (const stage of ['P', 'A', 'B']) {
      const dom = new JSDOM('<div id="app"></div>', {
        url: `file:///android_asset/index.html?mwbRedirect=${stage}`, runScripts: 'outside-only'
      });
      const calls = [];
      let onReturn;
      dom.window._dsbridge = {};
      dom.window.mwb = {
        getDeviceInfoSync: () => ({ osType: platform === 'android' ? 1 : 2 }),
        navigateTo: async params => { calls.push(['navigateTo', params]); },
        redirectTo: async params => { calls.push(['redirectTo', params]); },
        navigateBack: async () => { calls.push(['navigateBack']); },
        onPageShow: handler => { onReturn = handler; }, offPageShow() {},
        onAppShow: handler => { onReturn = handler; }, offAppShow() {}
      };
      try {
        dom.window.eval(bundle);
        // onMounted 的平台探测会触发一次 Vue 更新，再检查平台专有控件。
        await new Promise(resolve => setImmediate(resolve));
        assert.equal(dom.window.document.querySelector('h1')?.textContent, `页面 ${stage}`);
        const buttons = [...dom.window.document.querySelectorAll('button')];
        if (stage === 'P') {
          buttons.find(button => button.textContent === '打开页面 A').click();
          await new Promise(resolve => setImmediate(resolve));
          assert.equal(calls[0][0], 'navigateTo');
          assert.equal(new URL(calls[0][1].url).searchParams.get('mwbRedirect'), 'A');
          onReturn();
          await new Promise(resolve => setImmediate(resolve));
          assert.match(dom.window.document.querySelector('[role="status"]').textContent, /已返回页面 P/);
        } else if (stage === 'A') {
          const wait = dom.window.document.querySelector('input[type="checkbox"]');
          if (platform === 'ios') { assert.ok(wait); wait.click(); }
          else assert.equal(wait, null);
          buttons.find(button => button.textContent === '用 B 替换当前 A').click();
          await new Promise(resolve => setImmediate(resolve));
          assert.equal(calls[0][0], 'redirectTo');
          assert.equal(new URL(calls[0][1].url).searchParams.get('mwbRedirect'), 'B');
          if (platform === 'ios') assert.equal(calls[0][1].waitForReady, true);
          else assert.equal('waitForReady' in calls[0][1], false);
        } else {
          buttons.find(button => button.textContent === '返回页面 P').click();
          await new Promise(resolve => setImmediate(resolve));
          assert.equal(calls[0][0], 'navigateBack');
        }
      } finally { dom.window.close(); }
    }
  }
});

test('首页不展示错误页入口，保留原生插件入口与方法目录', () => {
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const dom = new JSDOM('<div id="app"></div>', { url: 'file:///android_asset/index.html', runScripts: 'outside-only' });
  dom.window._dsbridge = {};
  dom.window.mwb = {
    getDeviceInfoSync: () => ({ osType: 2 })
  };
  try {
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    const buttons = dom.window.document.querySelectorAll('[data-error-example]');
    assert.equal(buttons.length, 0);
    assert.doesNotMatch(dom.window.document.body.textContent, /默认错误页|自定义错误页/);
    assert.ok(dom.window.document.querySelector('.plugin-entry'));
    assert.ok(dom.window.document.querySelector('#method-search'));
    assert.equal([...dom.window.document.querySelectorAll('a')].some(link => /mwbRedirect=/.test(link.href)), false);
  } finally { dom.window.close(); }
});

test('替换当前页面方法行使用主 H5 地址而非子页或独立替换演示', async () => {
  // 运行编译后的默认参数解析与调用，防止子页标记被带到替换目标。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const bundle = readFileSync(join(project, 'dist', 'demo.js'), 'utf8');
  for (const osType of [1, 2]) {
    const dom = new JSDOM('<div id="app"></div>', {
      url: 'file:///android_asset/index.html?mwbChild=1', runScripts: 'outside-only'
    });
    const calls = [];
    dom.window._dsbridge = {};
    dom.window.mwb = {
      getDeviceInfoSync: () => ({ osType }),
      redirectTo: async params => { calls.push(params); }
    };
    try {
      dom.window.eval(bundle);
      await new Promise(resolve => setImmediate(resolve));
      dom.window.document.querySelector('[aria-label="运行替换当前页面"]').click();
      await new Promise(resolve => setImmediate(resolve));
      assert.equal(calls.length, 1);
      assert.equal(calls[0].url, 'file:///android_asset/index.html');
      assert.equal('waitForReady' in calls[0], false);
    } finally { dom.window.close(); }
  }
});

test('customError：构建同步自定义模板目录，保留相对 CSS 和脚本', () => {
  execFileSync(process.execPath, ['scripts/build.mjs', '--sync-native'], { cwd: project, stdio: 'pipe' });
  for (const directory of ['MWB-iOS/Example/Resources', 'MWB-Android/sample/src/main/assets']) {
    for (const name of ['index.html', 'error.css', 'error.js']) {
      assert.equal(readFileSync(join(root, directory, 'custom-error', name), 'utf8'),
        readFileSync(join(project, 'src/custom-error', name), 'utf8'));
    }
  }
});

/** 执行实际发布 bundle，只把无法在 Node 中存在的原生边界替换为确定响应。 */
function pluginPage(native = true, osType = 2) {
  const html = readFileSync(join(project, 'dist', 'native-plugins.html'), 'utf8');
  const dom = new JSDOM(html, { url: 'https://example.test/native-plugins.html', runScripts: 'outside-only' });
  const calls = [];
  const handlers = new Map();
  const close = dom.window.close.bind(dom.window);
  let nativeBridge;
  if (native) {
    // DSBridge 自身会异步通知 dsinit，并替换 window.close；保留这些边界的安全实现。
    dom.window._dsbridge = { call: () => JSON.stringify({ data: null }) };
    nativeBridge = {
      register: (name, callback) => handlers.set(name, callback),
      hasNativeMethod: () => true,
      call(method, args, done) {
        if (method === 'mwb.getDeviceInfoSync') return { osType };
        if (method === 'mwb.pluginSession') return JSON.stringify({ errCode: 0, result: { protocol: 1, documentId: 'demo-doc' } });
        if (method === 'mwb.pluginInfo') { done(JSON.stringify({ errCode: 0, result: { available: true } })); return; }
        calls.push({ method, args: JSON.parse(JSON.stringify(args ?? null)) });
        if (method === 'mwb.invokePlugin') done(JSON.stringify({ errCode: 0, result: { status: 200, headers: {}, body: 'native-network-response' } }));
        else done?.({ errCode: 0 });
      }
    };
  }
  dom.window.eval(readFileSync(join(project, 'dist', 'plugins.iife.js'), 'utf8'));
  dom.window.close = close;
  if (nativeBridge) dom.window.dsBridge = nativeBridge;
  dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
  return { dom, calls, handlers };
}

test('插件页通过真实组合 SDK 调用 network 并支持事件订阅解绑', async () => {
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  // 独立分发的脚本也必须带作者与许可条款，而不只依赖源码目录的 LICENSE。
  for (const bundle of ['mwb.iife.js', 'plugins.iife.js']) {
    const text = readFileSync(join(project, 'dist', bundle), 'utf8');
    assert.match(text, /wendux/);
    assert.match(text, /Permission is hereby granted/);
  }
  assert.match(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'), /Yuxi \(Evan\) You/);
  assert.match(readFileSync(join(project, 'dist', 'THIRD_PARTY_NOTICES.txt'), 'utf8'), /DSBridge/);
  const { dom, calls, handlers } = pluginPage();
  const { document, Event } = dom.window;
  try {
    assert.match(document.body.textContent, /自定义原生插件/);
    document.querySelector('.plugin-check').click();
    await new Promise(resolve => setImmediate(resolve));
    assert.match(document.querySelector('.plugin-availability').textContent, /已注册/);
    const url = document.querySelector('#plugin-url');
    url.value = 'https://example.com/';
    url.dispatchEvent(new Event('input', { bubbles: true }));
    document.querySelector('.plugin-events').click();
    document.querySelector('.plugin-form').dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    await new Promise(resolve => setImmediate(resolve));
    assert.match(document.querySelector('.plugin-result').textContent, /native-network-response/);
    assert.deepEqual(calls.find(call => call.method === 'mwb.invokePlugin').args.params, {
      url: 'https://example.com/', method: 'GET', headers: {}
    });
    const event = dom.window.JSON.parse(JSON.stringify({ documentId: 'demo-doc', plugin: 'network', name: 'requestFinished', data: { url: 'https://example.com/', status: 200 } }));
    handlers.get('mwb.pluginEvent')(event);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(document.querySelectorAll('.plugin-event-log li').length, 1);
    document.querySelector('.plugin-events').click();
    handlers.get('mwb.pluginEvent')(event);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(document.querySelectorAll('.plugin-event-log li').length, 1);
  } finally { dom.window.close(); }
});

test('插件页阻止非法参数并通过容器打开相同的插件子页', async () => {
  const { dom, calls } = pluginPage();
  const { document, Event } = dom.window;
  try {
    const headers = document.querySelector('#plugin-headers');
    headers.value = '{invalid';
    headers.dispatchEvent(new Event('input', { bubbles: true }));
    document.querySelector('.plugin-form').dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    await new Promise(resolve => setImmediate(resolve));
    assert.match(document.querySelector('.plugin-result').textContent, /HTTPS|JSON/);
    assert.equal(calls.filter(call => call.method === 'mwb.invokePlugin').length, 0);
    document.querySelector('.plugin-open').click();
    await new Promise(resolve => setImmediate(resolve));
    const navigation = calls.find(call => call.method === 'mwb.navigateTo');
    assert.equal(new URL(navigation.args.url).pathname, '/native-plugins.html');
    assert.equal(new URL(navigation.args.url).searchParams.get('mwbChild'), '1');
    assert.equal(navigation.args.hidden, true);
    assert.equal(navigation.args.waitForReady, true);
  } finally { dom.window.close(); }
});

test('Android 插件子页省略 iOS 等待参数', async () => {
  const { dom, calls } = pluginPage(true, 1);
  try {
    dom.window.document.querySelector('.plugin-open').click();
    await new Promise(resolve => setImmediate(resolve));
    const navigation = calls.find(call => call.method === 'mwb.navigateTo');
    assert.ok(navigation);
    assert.equal('waitForReady' in navigation.args, false);
  } finally { dom.window.close(); }
});

test('插件页浏览器预览明确提示原生要求且不会伪造网络成功', async () => {
  const { dom, calls } = pluginPage(false);
  try {
    dom.window.document.querySelector('.plugin-check').click();
    await new Promise(resolve => setImmediate(resolve));
    assert.match(dom.window.document.querySelector('.plugin-availability').textContent, /原生容器/);
    assert.equal(calls.length, 0);
    assert.doesNotMatch(dom.window.document.querySelector('.plugin-result').textContent, /native-network-response/);
  } finally { dom.window.close(); }
});

test('静态构建产物包含可离线加载的完整页面', () => {
  // 实际运行构建命令，捕获页面资源漏复制和 SDK 版本不同步。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  for (const file of files) assert.ok(readFileSync(join(project, 'dist', file)).byteLength > 0, file);
  const html = readFileSync(join(project, 'dist', 'index.html'), 'utf8');
  assert.match(html, /defer src="\.\/demo\.js"/);
  assert.doesNotMatch(html, /type="module"/);
  assert.deepEqual(
    readFileSync(join(project, 'dist', 'mwb.iife.js')),
    readFileSync(join(root, 'MWB-JS/dist/mwb.iife.js'))
  );
});

test('两个移动端页面禁用缩放与长按文字菜单', () => {
  // 检查实际发布页面，避免配置子页漏掉与首页一致的手势约束。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  for (const file of ['index.html', 'navigation-theme.html']) {
    const html = readFileSync(join(project, 'dist', file), 'utf8');
    assert.match(html, /user-scalable=no/);
    assert.match(html, /maximum-scale=1/);
  }
  const css = readFileSync(join(project, 'dist', 'styles.css'), 'utf8');
  assert.match(css, /-webkit-touch-callout:\s*none/);
  assert.match(css, /-webkit-user-select:\s*none/);
});

test('普通浏览器环境无需 Node 全局变量即可挂载 Vue 页面', () => {
  // WebView 不提供 process；直接执行发布脚本，覆盖真实的本地 HTML 入口。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const html = readFileSync(join(project, 'dist', 'index.html'), 'utf8');
  const dom = new JSDOM(html, { url: 'https://example.test/', runScripts: 'outside-only' });
  assert.equal(dom.window.process, undefined);
  try {
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    assert.match(dom.window.document.querySelector('#app')?.textContent ?? '', /查找方法/);
  } finally {
    dom.window.close();
  }
});

test('原生容器在首屏绘制后自动开启 WebView 调试', async () => {
  // 使用发布脚本验证页面挂载行为，不能依赖开发者手动点击目录方法。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const dom = new JSDOM('<div id="app"></div>', { url: 'https://example.test/', runScripts: 'outside-only' });
  const debugCalls = [];
  const frames = [];
  dom.window.requestAnimationFrame = callback => frames.push(callback);
  dom.window._dsbridge = {};
  dom.window.mwb = {
    setEnableDebug: enabled => debugCalls.push(enabled),
    getDeviceInfoSync: () => ({ osType: 2 })
  };
  try {
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    // 同步调试调用不能占用首屏绘制前的时间，但页面显示后仍自动可检查。
    assert.deepEqual(debugCalls, []);
    frames.shift()();
    assert.deepEqual(debugCalls, []);
    frames.shift()();
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.deepEqual(debugCalls, [true]);
  } finally {
    dom.window.close();
  }
});

test('顶部显示容器可见后的白屏与 MWB 可调用耗时', async () => {
  // 原生时间戳和网页使用同一设备时钟；两帧后才算首屏已经绘制。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const dom = new JSDOM('<div id="app"></div>', { url: 'https://example.test/', runScripts: 'outside-only' });
  let now = 1100;
  dom.window.__mwbDemoVisibleAt = 1000;
  dom.window.Date.now = () => now;
  // 手动驱动帧，避免机器负载使固定 30ms 等待早于第二帧执行。
  const frames = [];
  dom.window.requestAnimationFrame = callback => frames.push(callback);
  dom.window._dsbridge = {};
  dom.window.mwb = { getDeviceInfoSync: () => { now = 1120; return { osType: 2 }; } };
  try {
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(dom.window.document.querySelector('.load-metric-bridge strong')?.textContent, '120 ms');
    assert.equal(dom.window.document.querySelector('.load-metric-white strong')?.textContent, '计算中…');
    now = 1170;
    frames.shift()(now);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(dom.window.document.querySelector('.load-metric-white strong')?.textContent, '计算中…');
    now = 1220;
    frames.shift()(now);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(dom.window.document.querySelector('.load-metric-white strong')?.textContent, '220 ms');
  } finally {
    dom.window.close();
  }
});

test('MWB 可用时间在 SDK 脚本加载后立即记录', async () => {
  // Vue 的编译包可能较大，原生调用不应等它挂载后才开始计时。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const html = readFileSync(join(project, 'dist', 'index.html'), 'utf8');
  const inline = [...html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)]
    .find(match => !match[1].includes('src='))?.[2];
  assert.ok(inline, 'SDK 与 Vue 脚本之间应有早期探测脚本');
  const dom = new JSDOM('<div id="app"></div>', { url: 'https://example.test/', runScripts: 'outside-only' });
  let calls = 0;
  let now = 1080;
  dom.window.Date.now = () => now;
  dom.window.__mwbDemoVisibleAt = 1000;
  dom.window._dsbridge = {};
  dom.window.mwb = { getDeviceInfoSync: () => { calls++; return { osType: 2 }; } };
  try {
    dom.window.eval(inline);
    assert.equal(calls, 1);
    assert.equal(dom.window.__mwbDemoBridgeAt, 1080);
    now = 2000;
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(calls, 1);
    assert.equal(dom.window.document.querySelector('.load-metric-bridge strong')?.textContent, '80 ms');
  } finally {
    dom.window.close();
  }
});

test('首屏先绘制时晚到的原生起点仍更新顶部耗时', async () => {
  // didFinish/onPageFinished 可能晚于首屏，不能因此永远显示占位符。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const dom = new JSDOM('<div id="app"></div>', { url: 'https://example.test/', runScripts: 'outside-only' });
  dom.window.Date.now = () => 1200;
  dom.window.requestAnimationFrame = callback => dom.window.setTimeout(callback, 0);
  dom.window._dsbridge = {};
  dom.window.mwb = { getDeviceInfoSync: () => ({ osType: 2 }) };
  try {
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.equal(dom.window.document.querySelector('.load-metric-white strong')?.textContent, '—');
    dom.window.__mwbDemoVisibleAt = 1250;
    dom.window.dispatchEvent(new dom.window.Event('mwb-visible'));
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(dom.window.document.querySelector('.load-metric-white strong')?.textContent, '0 ms');
  } finally {
    dom.window.close();
  }
});

test('普通浏览器预览明确提示白屏计时仅适用于原生容器', () => {
  // 浏览器没有原生容器可见时刻，不能把导航耗时伪装成白屏时间。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const dom = new JSDOM('<div id="app"></div>', { url: 'https://example.test/', runScripts: 'outside-only' });
  try {
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    assert.equal(dom.window.document.querySelector('.load-metric-white strong')?.textContent, '—');
    assert.match(dom.window.document.querySelector('.load-metric-white small')?.textContent ?? '', /仅原生容器统计/);
    assert.equal(dom.window.document.querySelector('.load-metric-bridge strong')?.textContent, '未连接');
    assert.match(dom.window.document.querySelector('.action-footer small')?.textContent ?? '', /加载时自动探测桥/);
  } finally {
    dom.window.close();
  }
});

test('目录点按方法直接调用原生桥并在原行显示结果', async () => {
  // 快捷执行使用目录默认参数，且不切换到调试详情。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const dom = new JSDOM('<div id="app"></div>', { url: 'https://example.test/', runScripts: 'outside-only' });
  let received;
  dom.window._dsbridge = {};
  dom.window.mwb = {
    getDeviceInfoSync: () => ({ osType: 2 }),
    toast: async value => { received = value; return { errCode: 0, result: '已显示' }; }
  };
  try {
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    const entry = [...dom.window.document.querySelectorAll('.method-entry')]
      .find(element => element.textContent.includes('toast'));
    entry.querySelector('.method-row').click();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(received?.msg, '你好，Mobile Web Bridge');
    assert.ok(dom.window.document.querySelector('.view-list'));
    assert.equal(dom.window.location.hash, '');
    assert.match(entry.querySelector('.quick-result')?.textContent ?? '', /已显示/);
  } finally {
    dom.window.close();
  }
});

test('点击设置导航栏主题方法行通过容器打开独立配置页', async () => {
  // 配置页需要自己的原生导航栏，目录入口不能直接修改当前页面的导航栏。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const dom = new JSDOM('<div id="app"></div>', { url: 'https://example.test/index.html', runScripts: 'outside-only' });
  let navigation;
  let directThemeCalls = 0;
  dom.window._dsbridge = {};
  dom.window.mwb = {
    getDeviceInfoSync: () => ({ osType: 2 }),
    navigateTo: async value => { navigation = value; return { errCode: 0 }; },
    setNavigationBarTheme: async () => { directThemeCalls++; }
  };
  try {
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    const entry = [...dom.window.document.querySelectorAll('.method-entry')]
      .find(element => element.textContent.includes('setNavigationBarTheme'));
    entry.querySelector('.method-row').click();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(navigation?.url, 'https://example.test/navigation-theme.html');
    assert.equal(navigation?.hidden, true);
    assert.equal(directThemeCalls, 0);
    assert.ok(dom.window.document.querySelector('.view-list'));
  } finally {
    dom.window.close();
  }
});

test('导航栏配置页将表单值应用到当前原生容器', async () => {
  // 独立页面展示实际支持的字段，并让开发者一次点击看到原生效果。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const dom = new JSDOM('<div id="app"></div>', { url: 'https://example.test/navigation-theme.html', runScripts: 'outside-only' });
  let applied;
  dom.window._dsbridge = {};
  dom.window.mwb = {
    getDeviceInfoSync: () => ({ osType: 2 }),
    setNavigationBarTheme: async value => { applied = value; return { errCode: 0 }; }
  };
  try {
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    assert.match(dom.window.document.querySelector('#app')?.textContent ?? '', /导航栏样式/);
    assert.equal(dom.window.document.querySelector('[name="showBackButton"]'), null);
    const title = dom.window.document.querySelector('[name="title"]');
    title.value = '预览标题';
    title.dispatchEvent(new dom.window.Event('input', { bubbles: true }));
    await new Promise(resolve => setImmediate(resolve));
    dom.window.document.querySelector('.theme-apply').click();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(dom.window.document.querySelector('[name="hidden"]').checked, true);
    assert.equal(applied?.hidden, true);
    assert.equal(applied?.title, '预览标题');
    assert.equal(applied?.color, '12374a');
  } finally {
    dom.window.close();
  }
});

test('导航栏配置页底部按钮通过原生桥打开新的配置容器', async () => {
  // 使用同一份本地页面 URL 新建容器，才能验证子页导航栏与返回路径。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const dom = new JSDOM('<div id="app"></div>', { url: 'file:///android_asset/navigation-theme.html', runScripts: 'outside-only' });
  let navigation;
  let themeCalls = 0;
  dom.window._dsbridge = {};
  dom.window.mwb = {
    getDeviceInfoSync: () => ({ osType: 1 }),
    navigateTo: async value => { navigation = value; return { errCode: 0 }; },
    setNavigationBarTheme: async () => { themeCalls++; return { errCode: 0 }; }
  };
  try {
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    const button = dom.window.document.querySelector('.theme-open-page');
    assert.ok(button, '配置页底部应提供打开新容器的按钮');
    button.click();
    await new Promise(resolve => setImmediate(resolve));
    // JSDOM 中的对象来自另一个 Realm，分别核对传给原生的字段。
    assert.equal(navigation?.url, 'file:///android_asset/navigation-theme.html');
    assert.equal(navigation?.title, '导航栏样式子页');
    assert.equal(navigation?.hidden, true);
    assert.equal(themeCalls, 0);
  } finally {
    dom.window.close();
  }
});

test('Android 配置页显示专有选项且无效颜色不会调用原生', async () => {
  // iOS 不支持的按钮和状态栏字段只在 Android 出现；颜色错误要在页面拦截。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const dom = new JSDOM('<div id="app"></div>', { url: 'https://example.test/navigation-theme.html', runScripts: 'outside-only' });
  const applied = [];
  dom.window._dsbridge = {};
  dom.window.mwb = {
    getDeviceInfoSync: () => ({ osType: 1 }),
    setNavigationBarTheme: async value => { applied.push(value); return { errCode: 0 }; }
  };
  try {
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    await new Promise(resolve => setImmediate(resolve));
    assert.ok(dom.window.document.querySelector('[name="showBackButton"]'));
    const color = dom.window.document.querySelector('[name="color"]');
    color.value = 'invalid';
    color.dispatchEvent(new dom.window.Event('input', { bubbles: true }));
    await new Promise(resolve => setImmediate(resolve));
    dom.window.document.querySelector('.theme-apply').click();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(applied.length, 0);
    assert.match(dom.window.document.querySelector('.theme-status').textContent, /6 位十六进制/);

    color.value = '#445566';
    color.dispatchEvent(new dom.window.Event('input', { bubbles: true }));
    await new Promise(resolve => setImmediate(resolve));
    dom.window.document.querySelector('.theme-apply').click();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(applied[0]?.color, '445566');
    assert.equal(applied[0]?.showBackButton, true);
    assert.equal(applied[0]?.isBright, false);
  } finally {
    dom.window.close();
  }
});

test('导航栏配置页设置右上角文字并在点击后展示回传数据', async () => {
  // 配置页使用 SDK 回调展示真实点击，不通过网页弹框伪造按钮事件。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const dom = new JSDOM('<div id="app"></div>', { url: 'https://example.test/navigation-theme.html', runScripts: 'outside-only' });
  let applied;
  dom.window._dsbridge = {};
  dom.window.mwb = {
    getDeviceInfoSync: () => ({ osType: 2 }),
    setNavigationBarTheme: async value => { applied = value; return { errCode: 0 }; }
  };
  try {
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    const actionText = dom.window.document.querySelector('[name="actionTxt"]');
    assert.ok(actionText);
    actionText.value = '保存';
    actionText.dispatchEvent(new dom.window.Event('input', { bubbles: true }));
    await new Promise(resolve => setImmediate(resolve));
    dom.window.document.querySelector('.theme-apply').click();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(applied?.actionTxt, '保存');
    assert.equal(typeof applied?.onActionClick, 'function');
    applied.onActionClick({ actionExt: 'draft-42' });
    await new Promise(resolve => setImmediate(resolve));
    assert.match(dom.window.document.querySelector('.theme-status').textContent, /draft-42/);
    assert.match(dom.window.document.querySelector('.theme-code').textContent, /onActionClick/);
  } finally {
    dom.window.close();
  }
});

test('目录信息按钮只进入调试详情，不执行方法', async () => {
  // 详情和快捷执行是两个独立触控目标，点击信息图标不能触发原生调用。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const dom = new JSDOM('<div id="app"></div>', { url: 'https://example.test/', runScripts: 'outside-only' });
  let calls = 0;
  dom.window._dsbridge = {};
  dom.window.mwb = {
    getDeviceInfoSync: () => ({ osType: 2 }),
    toast: async () => { calls++; return { errCode: 0 }; }
  };
  dom.window.scrollTo = () => {};
  try {
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    const entry = [...dom.window.document.querySelectorAll('.method-entry')]
      .find(element => element.textContent.includes('toast'));
    const info = entry.querySelector('.method-info');
    assert.match(info.getAttribute('aria-label') ?? '', /详情/);
    info.click();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(calls, 0);
    assert.ok(dom.window.document.querySelector('.view-detail'));
    assert.match(dom.window.document.querySelector('#method-title').textContent, /显示原生提示/);
    assert.equal(dom.window.location.hash, '#toast');
  } finally {
    dom.window.close();
  }
});

test('切换方法后旧异步返回不会覆盖新详情', async () => {
  // 用可控 Promise 复现原生异步回调晚于开发者切换方法的情况。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const dom = new JSDOM('<div id="app"></div>', { url: 'https://example.test/#toast', runScripts: 'outside-only' });
  let finishToast;
  dom.window.scrollTo = () => {};
  dom.window._dsbridge = {};
  dom.window.mwb = {
    getDeviceInfoSync: () => ({ osType: 2 }),
    toast: () => new Promise(resolve => { finishToast = resolve; })
  };
  try {
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    const runButton = dom.window.document.querySelector('.run-button');
    runButton.click();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(runButton.disabled, true);
    const nextMethod = [...dom.window.document.querySelectorAll('.method-entry')]
      .find(element => element.textContent.includes('getDeviceInfoSync'));
    nextMethod.querySelector('.method-info').click();
    await new Promise(resolve => setImmediate(resolve));
    assert.match(dom.window.document.querySelector('#method-title').textContent, /读取设备信息/);
    assert.equal(runButton.disabled, false);
    finishToast({ result: '旧方法返回' });
    await new Promise(resolve => setImmediate(resolve));
    assert.doesNotMatch(dom.window.document.querySelector('.result-panel').textContent, /旧方法返回/);
  } finally {
    dom.window.close();
  }
});

test('手机从方法详情返回时恢复目录滚动位置', async () => {
  // 长目录进入详情后仍应能回到原方法附近，减少重复查找。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const dom = new JSDOM('<div id="app"></div>', { url: 'https://example.test/', runScripts: 'outside-only' });
  Object.defineProperty(dom.window, 'scrollY', { value: 2300, writable: true });
  dom.window.scrollTo = options => { dom.window.scrollY = options.top; };
  try {
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    const method = [...dom.window.document.querySelectorAll('.method-entry')]
      .find(element => element.textContent.includes('registerHandler'));
    method.querySelector('.method-info').click();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(dom.window.scrollY, 0);
    dom.window.document.querySelector('.back-button').click();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(dom.window.scrollY, 2300);
  } finally {
    dom.window.close();
  }
});

test('navigateTo 点击运行后直接调用原生桥，不弹出网页确认框', async () => {
  // 跳转示例应由开发者一次点击触发，不额外调用 WebView 的 JS confirm。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const dom = new JSDOM('<div id="app"></div>', { url: 'https://example.test/#navigateTo', runScripts: 'outside-only' });
  let confirmCount = 0;
  let navigateCount = 0;
  const navigationOptions = [];
  dom.window._dsbridge = {};
  dom.window.mwb = {
    getDeviceInfoSync: () => ({ osType: 2 }),
    navigateTo: async value => { navigationOptions.push(value); navigateCount++; return { errCode: 0 }; }
  };
  dom.window.confirm = () => { confirmCount++; return true; };
  try {
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    dom.window.document.querySelector('.run-button').click();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(confirmCount, 0);
    assert.equal(navigateCount, 1);
    assert.equal(navigationOptions[0].waitForReady, true);
    const immediate = [...dom.window.document.querySelectorAll('button')].find(button => button.textContent.includes('立即转场（对照）'));
    assert.ok(immediate);
    immediate.click();
    await new Promise(resolve => setImmediate(resolve));
    dom.window.document.querySelector('.run-button').click();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(navigationOptions[1].waitForReady, false);
  } finally {
    dom.window.close();
  }
});

test('同步命令把同一份构建产物接入两个原生 Demo', () => {
  execFileSync(process.execPath, ['scripts/build.mjs', '--sync-native'], { cwd: project, stdio: 'pipe' });
  for (const target of [
    join(root, 'MWB-iOS/Example/Resources'),
    join(root, 'MWB-Android/sample/src/main/assets')
  ]) {
    for (const file of files) {
      assert.deepEqual(readFileSync(join(target, file)), readFileSync(join(project, 'dist', file)), `${target}/${file}`);
    }
  }
});


test('打开 Demo 容器使用子页标记，首页没有返回入口', async () => {
  // 保留页面查询参数，但把子页身份留在 Demo URL，不增加 SDK 参数。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const dom = new JSDOM('<div id="app"></div>', { url: 'https://example.test/index.html?env=test', runScripts: 'outside-only' });
  let navigation;
  dom.window._dsbridge = {};
  dom.window.mwb = {
    getDeviceInfoSync: () => ({ osType: 2 }),
    navigateTo: async value => { navigation = value; return { errCode: 0 }; }
  };
  try {
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    assert.equal(dom.window.document.querySelector('.container-back'), null);
    const entry = [...dom.window.document.querySelectorAll('.method-entry')]
      .find(element => element.querySelector('small')?.textContent === 'navigateTo');
    entry.querySelector('.method-row').click();
    await new Promise(resolve => setImmediate(resolve));
    const url = new URL(navigation.url);
    assert.equal(url.searchParams.get('mwbChild'), '1');
    assert.equal(url.searchParams.get('env'), 'test');
  } finally { dom.window.close(); }
});

test('Demo 子页返回按钮防重复并在页面展示返回错误', async () => {
  // 原生返回可能异步失败；等待期间不能重复 pop，失败后仍可重试。
  execFileSync(process.execPath, ['scripts/build.mjs'], { cwd: project, stdio: 'pipe' });
  const dom = new JSDOM('<div id="app"></div>', { url: 'file:///android_asset/index.html?mwbChild=1', runScripts: 'outside-only' });
  let calls = 0;
  let rejectBack;
  dom.window._dsbridge = {};
  dom.window.mwb = {
    getDeviceInfoSync: () => ({ osType: 1 }),
    navigateBack: () => { calls++; return new Promise((_, reject) => { rejectBack = reject; }); }
  };
  dom.window.alert = () => assert.fail('返回错误不应弹框');
  try {
    dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
    const button = dom.window.document.querySelector('.container-back');
    assert.ok(button);
    assert.equal(button.getAttribute('aria-label'), '返回上一页');
    button.click(); button.click();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(calls, 1);
    assert.equal(button.disabled, true);
    rejectBack(new Error('没有可返回的页面'));
    await new Promise(resolve => setImmediate(resolve));
    assert.match(dom.window.document.querySelector('.container-back-error').textContent, /没有可返回的页面/);
    assert.equal(button.disabled, false);
  } finally { dom.window.close(); }
});

test('首页不包含加载就绪展示，也不自动通知原生', async () => {
  // 同时覆盖原生和浏览器预览，防止示例区或隐式通知重新进入 H5 页面。
  for (const native of [true, false]) {
    const dom = new JSDOM('<div id="app"></div>', { url: 'https://example.test/', runScripts: 'outside-only' });
    const frames = [];
    let notifications = 0;
    dom.window.requestAnimationFrame = callback => frames.push(callback);
    if (native) dom.window._dsbridge = {};
    const notifyPageReady = async () => { notifications++; return { errCode: 0 }; };
    dom.window.mwb = {
      getDeviceInfoSync: () => ({ osType: 2 }), setEnableDebug: () => {},
      registerHandler: () => {}, unRegisterHandler: () => {},
      notifyPageReady, basic: { notifyPageReady }
    };
    try {
      dom.window.eval(readFileSync(join(project, 'dist', 'demo.js'), 'utf8'));
      frames.shift()(); frames.shift()();
      await new Promise(resolve => setImmediate(resolve));
      assert.equal(notifications, 0);
      assert.equal(dom.window.document.querySelector('.lifecycle-example'), null);
      assert.doesNotMatch(dom.window.document.body.textContent, /加载与首屏就绪|notifyPageReady|再次通知就绪/);
    } finally { dom.window.close(); }
  }
});
