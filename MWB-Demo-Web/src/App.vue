<script setup>
import { computed, nextTick, onMounted, onUnmounted, reactive, ref } from 'vue';
import { catalog, groups } from './catalog.mjs';
import { createRunner, navigationOptions } from './runner.mjs';
import { sampleCode } from './sampleCode.mjs';
import { createDemoState } from './useDemoState.mjs';

const initialName = window.location.hash.slice(1);
const state = createDemoState(catalog, initialName);
const { query, category, active, view, filtered, choose, back } = state;
const sdk = window.mwb;
const bridgeReady = Boolean(window._dsbridge || window._dswk || navigator.userAgent.includes('_dsbridge'));

async function openPlugins(event) {
  if (!bridgeReady) return;
  event.preventDefault();
  try {
    const url = new URL('./native-plugins.html', window.location.href);
    url.searchParams.set('mwbChild', '1');
    await sdk.navigateTo(navigationOptions({ url: url.href, hidden: true, waitForReady: true }, context.platform));
  } catch (error) { returnError.value = `打开插件页面失败：${error?.message ?? String(error)}`; }
}
// Demo 子页通过 URL 标记显示网页返回入口，不改变 SDK 的容器参数。
const pageURL = new URL(window.location.href);
const isContainerChild = pageURL.searchParams.get('mwbChild') === '1';
const childURL = new URL(pageURL);
childURL.searchParams.set('mwbChild', '1');
// 替换示例始终回到主 H5，不携带子页身份或方法详情的 hash。
const redirectURL = new URL('./index.html', pageURL);
const context = reactive({ currentURL: childURL.href, redirectURL: redirectURL.href, platform: 'browser' });
const returning = ref(false);
const returnError = ref('');
const environment = ref('浏览器预览');
const argsInput = ref(JSON.stringify(active.value.args, null, 2));
const resultText = ref('点击“运行示例”查看原生返回。');
const resultState = ref('idle');
const resultTime = ref('等待执行');
const eventLog = ref([]);
const imageName = ref('尚未选择图片');
const copyLabel = ref('复制代码');
const busy = ref(false);
const quickResults = reactive({});
const visibleAt = ref(null);
const firstPaintAt = ref(null);
const bridgeUsableAt = ref(null);
const bridgeTimingFailed = ref(false);
let imageReadToken = 0;
let requestToken = 0;
let catalogScrollY = 0;

const groupName = computed(() => groups.find(item => item.id === active.value.group)?.label ?? '');
const code = computed(() => sampleCode(active.value, argsInput.value, context.platform));
const needsImage = computed(() => JSON.stringify(active.value.args).includes('{{imageBase64}}'));
const methodMode = computed(() => active.value.group === 'events' ? '事件与句柄' :
  active.value.name.endsWith('Sync') || active.value.name === 'setEnableDebug' ? '同步调用' : '异步调用');
const whiteTime = computed(() => elapsedText(visibleAt.value, firstPaintAt.value));
const bridgeTime = computed(() => !bridgeReady || !sdk ? '未连接' :
  bridgeTimingFailed.value ? '调用失败' : elapsedText(visibleAt.value, bridgeUsableAt.value));

function elapsedText(start, end) {
  if (start === null) return '—';
  if (end === null) return '计算中…';
  // 页面可能先于容器可见；这时用户没有经历可见白屏，按 0 毫秒记录。
  return `${Math.max(0, Math.round(end - start))} ms`;
}

function syncVisibleAt() {
  const value = Number(window.__mwbDemoVisibleAt);
  visibleAt.value = Number.isFinite(value) && value > 0 ? value : null;
}

// 页面只展示桥的真实返回，浏览器预览不生成任何模拟结果。
onMounted(() => {
  window.addEventListener('hashchange', syncHash);
  window.addEventListener('mwb-visible', syncVisibleAt);
  syncVisibleAt();
  // 两次动画帧保证 Vue 主内容至少经历一次浏览器绘制，再结束白屏计时。
  const nextFrame = window.requestAnimationFrame?.bind(window) ?? (callback => window.setTimeout(callback, 16));
  nextFrame(() => nextFrame(() => {
    firstPaintAt.value = Date.now();
    // 同步开启调试会阻塞 JS；首屏绘制后再执行，页面仍默认允许开发者检查。
    if (bridgeReady && sdk) window.setTimeout(() => {
      try {
        if (typeof sdk.setEnableDebug === 'function') sdk.setEnableDebug(true);
      } catch (error) {
        console.warn('自动开启 WebView 调试失败', error);
      }
    }, 0);
  }));
  if (!bridgeReady || !sdk) return;
  try {
    const earlyAt = Number(window.__mwbDemoBridgeAt);
    const hasEarlyResult = Number.isFinite(earlyAt) && earlyAt > 0 && window.__mwbDemoDeviceInfo;
    const deviceInfo = hasEarlyResult ? window.__mwbDemoDeviceInfo : sdk.getDeviceInfoSync();
    context.platform = deviceInfo.osType === 1 ? 'android' : 'ios';
    bridgeUsableAt.value = hasEarlyResult ? earlyAt : Date.now();
    environment.value = context.platform === 'ios' ? 'iOS 已连接' : 'Android 已连接';
  } catch {
    bridgeTimingFailed.value = true;
    environment.value = '原生桥已连接';
  }
});
onUnmounted(() => {
  window.removeEventListener('hashchange', syncHash);
  window.removeEventListener('mwb-visible', syncVisibleAt);
});

const runner = createRunner(sdk, event => {
  eventLog.value.unshift({ id: Date.now() + Math.random(), time: new Date().toLocaleTimeString(), ...event });
  if (eventLog.value.length > 20) eventLog.value.length = 20;
});

// 对照按钮直接更新可编辑参数与复制代码，运行结果沿用真实桥接响应。
function setNavigationWait(enabled) {
  try {
    const args = JSON.parse(argsInput.value);
    args[0].waitForReady = enabled;
    argsInput.value = JSON.stringify(args, null, 2);
  } catch { returnError.value = '请先修正调用参数 JSON。'; }
}

function syncHash() {
  const selected = catalog.find(item => item.name === window.location.hash.slice(1));
  if (selected) selectMethod(selected, false);
  else showCatalog(false);
}

function invalidatePendingRequest() {
  // 切换详情后，旧原生回调仍可能到达，但不能更新当前方法的结果或按钮。
  requestToken++;
  busy.value = false;
}

function selectMethod(item, updateHash = true) {
  if (view.value === 'list') catalogScrollY = window.scrollY;
  invalidatePendingRequest();
  choose(item);
  argsInput.value = JSON.stringify(item.args, null, 2);
  resultText.value = '点击“运行示例”查看原生返回。';
  resultState.value = 'idle';
  resultTime.value = '等待执行';
  copyLabel.value = '复制代码';
  if (updateHash) window.history.replaceState(null, '', `#${item.name}`);
  nextTick(() => window.scrollTo({ top: 0, behavior: 'auto' }));
}

function showCatalog(updateHash = true) {
  invalidatePendingRequest();
  back();
  if (updateHash) window.history.replaceState(null, '', window.location.pathname + window.location.search);
  // 详情始终从顶部开始；返回长目录时回到之前浏览的方法附近。
  nextTick(() => window.scrollTo({ top: catalogScrollY, behavior: 'auto' }));
}

function formatValue(value) {
  if (value === undefined) return '调用完成，无返回值';
  try { return JSON.stringify(value, null, 2) ?? String(value); }
  catch { return String(value); }
}

function showResult(message, error) {
  resultText.value = message;
  resultState.value = error ? 'error' : 'success';
  resultTime.value = new Date().toLocaleTimeString();
}

function formatError(error) {
  return `${error?.name ?? 'Error'}${Number.isFinite(error?.errCode) ? ` (${error.errCode})` : ''}: ${error?.message ?? String(error)}`;
}

function rememberMediaResult(item, response) {
  const result = response?.result;
  if (item.name === 'chooseImage') {
    const image = result?.data?.[0];
    context.imagePath = image?.original || image?.compressed || context.imagePath;
  }
  if (item.name === 'convertImagePathToBase64' || item.name === 'compressImage') {
    context.imageBase64 = result?.base64Image || context.imageBase64;
  }
}

async function runMethod() {
  if (!bridgeReady) {
    showResult('浏览器预览无法调用原生方法，请在 iOS 或 Android Demo 中打开此页。', true);
    return;
  }
  const item = active.value;
  if (item.confirm && !window.confirm(item.confirm)) return;
  const currentRequest = ++requestToken;
  busy.value = true;
  try {
    const response = await runner.run(item, argsInput.value, context);
    if (currentRequest !== requestToken) return;
    rememberMediaResult(item, response);
    showResult(formatValue(response), false);
  } catch (error) {
    if (currentRequest === requestToken) {
      showResult(formatError(error), true);
    }
  } finally {
    if (currentRequest === requestToken) busy.value = false;
  }
}

async function runQuickMethod(item) {
  // 目录使用示例默认参数直接调用；结果留在该行，不改变当前详情与网址。
  if (quickResults[item.name]?.state === 'loading') return;
  if (!bridgeReady) {
    quickResults[item.name] = { state: 'error', text: '浏览器预览无法调用原生方法，请在 iOS 或 Android Demo 中打开此页。' };
    return;
  }
  if (item.confirm && !window.confirm(item.confirm)) return;
  quickResults[item.name] = { state: 'loading', text: '正在调用原生方法…' };
  try {
    // 导航栏配置需要独立原生容器，目录入口先打开子页；信息按钮仍保留 JSON 调试。
    const response = item.name === 'setNavigationBarTheme'
      ? await sdk.navigateTo(navigationOptions({ url: new URL('./navigation-theme.html', window.location.href).href, title: '导航栏样式', hidden: true, waitForReady: true }, context.platform))
      : await runner.run(item, JSON.stringify(item.args), context);
    rememberMediaResult(item, response);
    quickResults[item.name] = { state: 'success', text: formatValue(response) };
  } catch (error) {
    quickResults[item.name] = { state: 'error', text: formatError(error) };
  }
}

async function returnToParent() {
  if (returning.value) return;
  returning.value = true;
  returnError.value = '';
  try {
    if (bridgeReady && sdk) await sdk.navigateBack();
    else returnError.value = '请在 iOS 或 Android Demo 容器中返回上一页。';
  } catch (error) {
    returnError.value = `返回失败：${error?.message ?? String(error)}`;
  } finally {
    returning.value = false;
  }
}

async function copyCode() {
  try { await navigator.clipboard.writeText(code.value); copyLabel.value = '已复制'; }
  catch { copyLabel.value = '复制失败'; }
}

function selectImage(event) {
  // 清除旧图并用序号丢弃过期的读取结果，避免快速换图时误用上一张。
  context.imageBase64 = undefined;
  const currentRead = ++imageReadToken;
  const file = event.target.files?.[0];
  if (!file) { imageName.value = '尚未选择图片'; return; }
  imageName.value = `正在读取 ${file.name}…`;
  const reader = new FileReader();
  reader.onload = () => {
    if (currentRead !== imageReadToken) return;
    context.imageBase64 = String(reader.result).split(',')[1];
    imageName.value = `${file.name} · ${(file.size / 1024).toFixed(0)} KB`;
  };
  reader.onerror = () => {
    if (currentRead !== imageReadToken) return;
    context.imageBase64 = undefined;
    imageName.value = '读取失败，请重新选择图片';
    showResult('读取图片失败，请重新选择。', true);
  };
  reader.readAsDataURL(file);
}

function clearEvents() {
  eventLog.value = [];
}
</script>

<template>
  <div class="demo-shell" :class="`view-${view}`">
    <header class="app-header">
      <div class="app-brand">
        <button v-if="isContainerChild" type="button" class="container-back" aria-label="返回上一页" :disabled="returning" @click="returnToParent">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m14 5-7 7 7 7" /></svg>
        </button>
        <span v-else class="brand-mark">MWB</span>
        <div><strong>Mobile Web Bridge</strong><small>开发者示例</small></div>
      </div>
      <span class="bridge-state" :class="{ connected: bridgeReady }" role="status">{{ environment }}</span>
    </header>

    <p v-if="returnError" class="container-back-error" role="alert">{{ returnError }}</p>

    <section class="load-metrics" aria-label="本次页面加载时间">
      <div class="load-metric load-metric-white"><span>白屏时间</span><strong>{{ whiteTime }}</strong><small>{{ visibleAt === null ? '仅原生容器统计' : '容器可见 → 首屏绘制' }}</small></div>
      <div class="load-metric load-metric-bridge"><span>MWB 可调用</span><strong>{{ bridgeTime }}</strong><small>容器可见 → 原生响应</small></div>
    </section>

    <main class="layout">
      <!-- 手机目录直接运行方法，信息按钮进入详情；宽屏保留双栏结构。 -->
      <section class="catalog-pane" :class="{ 'mobile-hidden': view === 'detail' }" aria-label="方法目录">
        <div class="catalog-intro">
          <p class="section-label">MWB · METHOD LAB</p>
          <h1>用一个页面<br>试遍所有原生能力</h1>
          <p>点方法直接运行；点信息按钮调整参数、查看代码和真实返回。</p>
        </div>
        <a class="plugin-entry" href="./native-plugins.html" @click="openPlugins"><strong>自定义原生插件</strong><span>测试宿主 network 方法与事件</span></a>
        <label class="field-label" for="method-search">查找方法</label>
        <input id="method-search" v-model="query" class="search-field" type="search" placeholder="搜索名称或用途" autocomplete="off">
        <div class="category-strip" role="group" aria-label="方法分类">
          <button type="button" :aria-pressed="category === 'all'" @click="category = 'all'">全部</button>
          <button v-for="item in groups" :key="item.id" type="button" :aria-pressed="category === item.id" @click="category = item.id">{{ item.label }}</button>
        </div>
        <p class="list-count">{{ filtered.length }} / {{ catalog.length }} 个方法</p>
        <div class="method-list">
          <div v-for="item in filtered" :key="item.name" class="method-entry">
            <div class="method-actions">
              <button type="button" class="method-row" :aria-label="`运行${item.title}`" :disabled="quickResults[item.name]?.state === 'loading'" @click="runQuickMethod(item)">
                <span class="method-copy"><strong>{{ item.title }}</strong><small>{{ item.name }}</small></span>
                <span class="run-cue" aria-hidden="true">{{ quickResults[item.name]?.state === 'loading' ? '…' : '▶' }}</span>
              </button>
              <button type="button" class="method-info" :aria-label="`查看${item.title}调试详情`" @click="selectMethod(item)"><span class="info-glyph" aria-hidden="true">i</span></button>
            </div>
            <div v-if="quickResults[item.name]" class="quick-result" :data-state="quickResults[item.name].state" role="status" aria-live="polite">
              <strong>{{ quickResults[item.name].state === 'loading' ? '执行中' : quickResults[item.name].state === 'success' ? '执行成功' : '执行失败' }}</strong>
              <pre>{{ quickResults[item.name].text }}</pre>
            </div>
          </div>
          <p v-if="filtered.length === 0" class="empty-list">没有匹配的方法，试试其他关键词。</p>
        </div>
      </section>

      <section class="detail-pane" :class="{ 'mobile-hidden': view === 'list' }" aria-labelledby="method-title">
        <button type="button" class="back-button" @click="showCatalog()">返回方法目录</button>
        <div class="detail-heading">
          <p class="detail-category">{{ groupName }} <span>·</span> {{ methodMode }}</p>
          <h2 id="method-title">{{ active.title }}</h2>
          <code class="method-id">mwb.{{ active.name }}</code>
          <p>{{ active.description }}</p>
        </div>
        <p v-if="active.note" class="method-note">{{ active.note }}</p>

        <section class="content-section" aria-labelledby="code-heading">
          <div class="section-head"><h3 id="code-heading">调用代码</h3><button type="button" class="quiet-button" @click="copyCode">{{ copyLabel }}</button></div>
          <pre class="code-panel"><code>{{ code }}</code></pre>
        </section>

        <section class="content-section" aria-labelledby="args-heading">
          <div class="section-head"><h3 id="args-heading">调用参数</h3><span>JSON 数组</span></div>
          <div v-if="['navigateTo', 'redirectTo'].includes(active.name) && context.platform === 'ios'" class="section-head">
            <button type="button" class="quiet-button" :disabled="busy" @click="setNavigationWait(true)">等待绘制后转场</button>
            <button type="button" class="quiet-button" :disabled="busy" @click="setNavigationWait(false)">立即转场（对照）</button>
          </div>
          <p v-if="['navigateTo', 'redirectTo'].includes(active.name)" class="method-note">仅 iOS 支持等待绘制，最多 3 秒；失败保留当前页。成功表示已发起导航，异步业务数据可能仍在加载。</p>
          <label class="sr-only" for="args-input">调用参数 JSON</label>
          <textarea id="args-input" v-model="argsInput" class="args-editor" spellcheck="false" autocomplete="off"></textarea>
          <div v-if="needsImage" class="image-picker">
            <label for="image-file">选择图片作为 Base64 输入</label>
            <input id="image-file" type="file" accept="image/*" @change="selectImage">
            <small>{{ imageName }}</small>
          </div>
        </section>

        <section class="content-section" aria-labelledby="result-heading">
          <div class="section-head"><h3 id="result-heading">执行结果</h3><span>{{ resultTime }}</span></div>
          <pre class="result-panel" :data-state="resultState" role="status" aria-live="polite">{{ resultText }}</pre>
        </section>

        <section class="content-section event-section" aria-labelledby="event-heading">
          <div class="section-head"><h3 id="event-heading">原生事件</h3><button type="button" class="quiet-button" @click="clearEvents">清空</button></div>
          <p v-if="eventLog.length === 0" class="empty-events">订阅事件或注册 JS 句柄后，消息会显示在这里。</p>
          <ol v-else class="event-list" aria-live="polite"><li v-for="event in eventLog" :key="event.id"><time>{{ event.time }}</time><strong>{{ event.method }}</strong><span>{{ formatValue(event.data) }}</span></li></ol>
        </section>

        <div class="action-footer">
          <button type="button" class="run-button" :disabled="busy" @click="runMethod">{{ busy ? '正在调用…' : '运行示例' }}</button>
          <small>加载时自动探测桥；示例操作由点击触发。</small>
        </div>
      </section>
    </main>
  </div>
</template>
