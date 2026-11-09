<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { navigationOptions } from './runner.mjs';
import { sampleCode } from './sampleCode.mjs';

const sdk = window.mwb;
const native = Boolean(window._dsbridge || window._dswk || navigator.userAgent.includes('_dsbridge'));
const stage = new URLSearchParams(window.location.search).get('mwbRedirect');
const platform = ref('browser');
const waitForReady = ref(false);
const busy = ref(false);
const openedA = ref(false);
const status = ref(native ? '按下方步骤验证真实的原生页面替换。' : '浏览器预览：请在 iOS 或 Android Demo 中执行原生导航。');
const statusState = ref('idle');

/** 每个阶段是独立网页容器；URL 标记只用于展示身份，不模拟原生返回栈。 */
function pageURL(next) {
  const url = new URL(window.location.href);
  url.searchParams.set('mwbRedirect', next);
  url.hash = '';
  return url.href;
}

const description = computed(() => stage === 'P' ? '从这里打开 A，再让 A 替换为 B；B 返回时应直接回到这个 P。' :
  stage === 'A' ? '用 B 替换当前 A 后，A 将从返回路径移除。' : '当前是替换后的 B。返回应跳过 A，回到上一层 P。');
const options = computed(() => navigationOptions({ url: pageURL(stage === 'P' ? 'A' : 'B'),
  title: stage === 'P' ? '页面 A' : '页面 B', hidden: true, waitForReady: waitForReady.value }, platform.value));
const code = computed(() => sampleCode({ name: stage === 'P' ? 'navigateTo' : stage === 'A' ? 'redirectTo' : 'navigateBack' },
  JSON.stringify(stage === 'B' ? [] : [options.value]), platform.value));

function checkNative() {
  if (!native || !sdk) throw new Error('请在原生 Demo 容器中运行此示例。');
}

function showError(error) {
  status.value = `${Number.isInteger(error?.errCode) ? `错误 ${error.errCode}：` : ''}${error?.message ?? String(error)}；可在当前页重试。`;
  statusState.value = 'error';
}

async function openA() {
  if (busy.value) return;
  busy.value = true;
  try {
    checkNative();
    openedA.value = true;
    status.value = '已请求打开 A；在 A 替换为 B 后返回此处，检查是否跳过 A。';
    statusState.value = 'idle';
    await sdk.navigateTo(options.value);
  } catch (error) { openedA.value = false; showError(error); }
  finally { busy.value = false; }
}

async function replaceA(fail = false) {
  if (busy.value) return;
  busy.value = true;
  try {
    checkNative();
    const params = fail ? { ...options.value, url: new URL('./mwb-redirect-missing.html', window.location.href).href, waitForReady: true } : options.value;
    status.value = params.waitForReady ? '正在准备 B；失败或超时应继续保留当前 A。' : '已请求替换；成功后在 B 查看页面身份。';
    statusState.value = 'idle';
    // 成功后 A 销毁，不在 await 后执行业务；这里只处理 A 仍存在时的错误。
    await sdk.redirectTo(params);
  } catch (error) { showError(error); }
  finally { busy.value = false; }
}

async function goBack() {
  if (busy.value) return;
  busy.value = true;
  try { checkNative(); await sdk.navigateBack(); }
  catch (error) { showError(error); }
  finally { busy.value = false; }
}

function returnedToP() {
  if (stage !== 'P' || !openedA.value) return;
  openedA.value = false;
  status.value = '已返回页面 P。若刚才从 B 返回且没有经过 A，替换路径验证通过。';
  statusState.value = 'success';
}

onMounted(() => {
  if (!native || !sdk) return;
  try {
    platform.value = sdk.getDeviceInfoSync().osType === 1 ? 'android' : 'ios';
    // iOS 容器显示和 Android Activity 恢复分别走现有事件，不新增原生事件协议。
    sdk.onPageShow?.(returnedToP);
    sdk.onAppShow?.(returnedToP);
  } catch (error) { showError(error); }
});
onUnmounted(() => {
  sdk?.offPageShow?.(returnedToP);
  sdk?.offAppShow?.(returnedToP);
});
</script>

<template>
  <main class="theme-page">
    <div class="theme-page-top">
      <button v-if="stage !== 'B'" type="button" class="back-button" :disabled="busy" @click="goBack">{{ stage === 'P' ? '返回方法目录' : '返回页面 P' }}</button>
      <span class="theme-platform">{{ platform === 'ios' ? 'iOS 原生导航' : platform === 'android' ? 'Android 原生导航' : '浏览器预览' }}</span>
    </div>
    <header class="theme-heading">
      <h1>页面 {{ stage }}</h1>
      <p>{{ description }}</p>
    </header>
    <p class="method-note">打开 A：P → A；替换为 B：P → B；从 B 返回：P。</p>
    <label v-if="stage === 'A' && platform === 'ios'" class="theme-switch">
      <span><strong>等待 B 加载和绘制准备</strong><small>最多 3 秒，准备失败时保留 A。</small></span>
      <input v-model="waitForReady" type="checkbox" :disabled="busy">
    </label>
    <p v-if="stage === 'A' && platform === 'android'" class="method-note">Android 立即替换，调用时省略 waitForReady。</p>
    <button v-if="stage === 'P'" type="button" class="run-button theme-open-page" :disabled="busy" @click="openA">打开页面 A</button>
    <button v-else-if="stage === 'A'" type="button" class="run-button theme-open-page" :disabled="busy" @click="replaceA()">用 B 替换当前 A</button>
    <button v-else type="button" class="run-button theme-open-page" :disabled="busy" @click="goBack">返回页面 P</button>
    <button v-if="stage === 'A' && platform === 'ios'" type="button" class="quiet-button theme-open-page" :disabled="busy" @click="replaceA(true)">验证加载失败时保留 A</button>
    <p class="theme-status" :data-state="statusState" role="status" aria-live="polite">{{ status }}</p>
    <section class="theme-code" aria-labelledby="redirect-code-title">
      <h2 id="redirect-code-title">当前步骤的 SDK 调用</h2>
      <pre class="code-panel"><code>{{ code }}</code></pre>
    </section>
  </main>
</template>
