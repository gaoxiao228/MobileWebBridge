<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';

const sdk = window.mwb;
const native = Boolean(window._dsbridge || window._dswk || navigator.userAgent.includes('_dsbridge'));
const url = ref('');
const method = ref('GET');
const headers = ref('{}');
const body = ref('');
const busy = ref(false);
const opening = ref(false);
const checking = ref(false);
const availability = ref(native ? '尚未检测，点击“检测插件”查询宿主注册。' : '浏览器预览：请在原生容器中检测和调用。');
const availabilityState = ref('idle');
const result = ref('填写 HTTPS 地址后发起请求；页面不会自动访问网络。');
const resultState = ref('idle');
const subscribing = ref(false);
const events = ref([]);
let stopEvents;
let active = true;

const code = computed(() => `const mwb = createMWB({ plugins: [networkPlugin] });\n\nconst response = await mwb.network.request(${JSON.stringify({
  url: url.value || 'https://example.com/', method: method.value,
  ...(method.value === 'POST' ? { body: body.value } : {})
}, null, 2)});\nconsole.log(response.result);`);

function errorText(error) {
  return `${Number.isInteger(error?.errCode) ? `错误 ${error.errCode}：` : ''}${error?.message ?? String(error)}`;
}

async function checkPlugin() {
  if (checking.value) return;
  if (!native || !sdk?.hasPlugin) {
    availability.value = '请在更新后的 iOS 或 Android 原生容器中打开此页。';
    availabilityState.value = 'error';
    return;
  }
  checking.value = true;
  try {
    const available = await sdk.hasPlugin('network');
    if (!active) return;
    availability.value = available ? 'network 已注册，可以发起原生网络请求。' : '宿主未注册 network，请先在 App 启动时注册插件。';
    availabilityState.value = available ? 'success' : 'error';
  } catch (error) {
    if (active) { availability.value = errorText(error); availabilityState.value = 'error'; }
  } finally { if (active) checking.value = false; }
}

async function request() {
  if (busy.value) return;
  try {
    if (!native || !sdk?.network) throw new Error('请在原生 Demo 容器中运行网络插件。');
    let target;
    try { target = new URL(url.value); } catch { throw new Error('请输入完整的 HTTPS 地址，例如 https://example.com/。'); }
    if (target.protocol !== 'https:') throw new Error('示例只允许 HTTPS 地址。');
    let parsed;
    try { parsed = JSON.parse(headers.value); } catch { throw new Error('请求头必须是合法 JSON 对象。'); }
    if (!parsed || Array.isArray(parsed) || typeof parsed !== 'object' || Object.values(parsed).some(value => typeof value !== 'string')) {
      throw new Error('请求头必须是键和值都为字符串的 JSON 对象。');
    }
    busy.value = true;
    result.value = '等待原生网络层返回…';
    resultState.value = 'loading';
    const response = await sdk.network.request({
      url: target.href, method: method.value, headers: parsed,
      ...(method.value === 'POST' ? { body: body.value } : {})
    });
    if (active) { result.value = JSON.stringify(response, null, 2); resultState.value = 'success'; }
  } catch (error) {
    if (active) { result.value = errorText(error); resultState.value = 'error'; }
  } finally { if (active) busy.value = false; }
}

function toggleEvents() {
  if (subscribing.value) { stopEvents?.(); stopEvents = undefined; subscribing.value = false; return; }
  try {
    if (!native || !sdk?.network) throw new Error('请在原生 Demo 容器中订阅事件。');
    stopEvents = sdk.network.on('requestFinished', data => {
      events.value.unshift({ id: Date.now() + Math.random(), text: JSON.stringify(data) });
      events.value = events.value.slice(0, 10);
    });
    subscribing.value = true;
  } catch (error) { result.value = errorText(error); resultState.value = 'error'; }
}

async function openContainer() {
  if (opening.value) return;
  opening.value = true;
  try {
    if (!native || !sdk) throw new Error('请在原生容器中打开新的插件页面。');
    const next = new URL(window.location.href);
    next.searchParams.set('mwbChild', '1');
    await sdk.basic.navigateTo({ url: next.href, hidden: true });
  } catch (error) { if (active) { result.value = errorText(error); resultState.value = 'error'; } }
  finally { if (active) opening.value = false; }
}

async function goBack(event) {
  if (!native) return;
  event.preventDefault();
  try { await sdk.basic.navigateBack(); }
  catch (error) { result.value = errorText(error); resultState.value = 'error'; }
}

onMounted(() => {
  // 子页独立 WebView 仍默认可调试，主页的白屏统计不受此页影响。
  if (native) { try { sdk?.basic?.setEnableDebug(true); } catch { /* 检测按钮提供诊断。 */ } }
});
onUnmounted(() => { active = false; stopEvents?.(); });
</script>

<template>
  <main class="theme-page plugin-page">
    <div class="theme-page-top">
      <a class="back-button" href="./index.html" @click="goBack">返回方法目录</a>
      <span class="theme-platform">basic + network</span>
    </div>
    <header class="theme-heading">
      <h1>自定义原生插件</h1>
      <p>同一份 H5，调用 iOS 和 Android 各自的宿主网络层。</p>
    </header>

    <section aria-labelledby="plugin-detection-title">
      <div class="section-head">
        <h2 id="plugin-detection-title">宿主能力</h2>
        <button type="button" class="quiet-button plugin-check" :disabled="checking" @click="checkPlugin">{{ checking ? '检测中…' : '检测插件' }}</button>
      </div>
      <p class="theme-status plugin-availability" :data-state="availabilityState" role="status">{{ availability }}</p>
    </section>

    <form class="theme-form plugin-form" @submit.prevent="request">
      <label class="theme-field" for="plugin-url">请求地址
        <input id="plugin-url" v-model="url" type="url" placeholder="https://example.com/" autocomplete="off" :disabled="busy">
      </label>
      <p class="plugin-help">Sample 仅允许 example.com 和 httpbin.org，响应文本最多 1 MiB。接入方可在原生服务中调整自己的访问规则。</p>
      <label class="theme-field" for="plugin-method">请求方法
        <select id="plugin-method" v-model="method" :disabled="busy"><option>GET</option><option>POST</option></select>
      </label>
      <label class="theme-field" for="plugin-headers">请求头 · JSON 字符串对象
        <textarea id="plugin-headers" v-model="headers" class="args-editor" spellcheck="false" :disabled="busy"></textarea>
      </label>
      <label v-if="method === 'POST'" class="theme-field" for="plugin-body">请求体 · 文本
        <textarea id="plugin-body" v-model="body" class="args-editor" spellcheck="false" :disabled="busy"></textarea>
      </label>
      <button type="submit" class="run-button" :disabled="busy">{{ busy ? '原生请求中…' : '发起原生请求' }}</button>
    </form>

    <section class="content-section" aria-labelledby="plugin-result-title">
      <div class="section-head"><h2 id="plugin-result-title">调用结果</h2></div>
      <pre class="result-panel plugin-result" :data-state="resultState" role="status" aria-live="polite">{{ result }}</pre>
    </section>

    <section class="content-section" aria-labelledby="plugin-events-title">
      <div class="section-head"><h2 id="plugin-events-title">requestFinished 事件</h2>
        <button type="button" class="quiet-button plugin-events" :aria-pressed="subscribing" @click="toggleEvents">{{ subscribing ? '取消订阅' : '订阅事件' }}</button>
      </div>
      <p v-if="events.length === 0" class="empty-events">先订阅，再发起请求。事件只发送到当前页面。</p>
      <ol class="event-list plugin-event-log"><li v-for="event in events" :key="event.id">{{ event.text }}</li></ol>
    </section>

    <section class="content-section" aria-labelledby="plugin-code-title">
      <div class="section-head"><h2 id="plugin-code-title">H5 调用示例</h2></div>
      <pre class="code-panel"><code>{{ code }}</code></pre>
    </section>
    <button type="button" class="run-button theme-open-page plugin-open" :disabled="opening" @click="openContainer">{{ opening ? '打开中…' : '打开新的插件容器页面' }}</button>
  </main>
</template>
