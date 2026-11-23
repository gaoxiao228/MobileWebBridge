<script setup>
import { navigationOptions } from './runner.mjs';
import { computed, onMounted, ref } from 'vue';

const sdk = window.mwb;
const bridgeReady = Boolean(window._dsbridge || window._dswk || navigator.userAgent.includes('_dsbridge'));
const platform = ref('browser');
const title = ref('导航栏样式');
const color = ref('#12374a');
const titleColor = ref('#ffffff');
const buttonColor = ref('#049f91');
const buttonBackgroundVisible = ref(true);
const backButtonStyle = ref('arrowText');
const backButtonText = ref('返回');
const separatorVisible = ref(true);
const separatorColor = ref('#dfe8e5');
const titleFontSize = ref(17);
const titleFontWeight = ref('semibold');
const buttonFontSize = ref(16);
// 初次进入与 navigateTo 默认策略一致；取消勾选并应用即可预览原生栏。
const hidden = ref(true);
const showBackButton = ref(true);
const showCloseButton = ref(false);
const isBright = ref(false);
const actionTxt = ref('');
const actionExt = ref('theme-demo');
const busy = ref(false);
const opening = ref(false);
const replacing = ref(false);
const openError = ref('');
const status = ref('默认隐藏导航栏；取消“隐藏导航栏”后点击“应用样式”即可预览。');
const statusType = ref('idle');

function hex(value) {
  return /^#?[0-9a-f]{6}$/i.test(value.trim()) ? value.trim().replace(/^#/, '').toLowerCase() : null;
}

// 三种调用共用外观值，目标操作回调仍由目标文档注册。
const appearance = computed(() => ({
  color: hex(color.value), titleColor: hex(titleColor.value), buttonColor: hex(buttonColor.value),
  backButtonStyle: backButtonStyle.value, backButtonText: backButtonText.value,
  showBackButton: showBackButton.value, separatorVisible: separatorVisible.value,
  separatorColor: hex(separatorColor.value), titleFontSize: Number(titleFontSize.value),
  titleFontWeight: titleFontWeight.value, buttonFontSize: Number(buttonFontSize.value),
  // iOS 26 起可单独隐藏系统按钮底；Android 不发送此参数。
  ...(platform.value === 'ios' ? { buttonBackgroundVisible: buttonBackgroundVisible.value } : {})
}));
const theme = computed(() => {
  const params = {
    ...appearance.value,
    title: title.value,
    color: hex(color.value),
    titleColor: hex(titleColor.value),
    hidden: hidden.value,
    actionTxt: actionTxt.value.trim()
  };
  if (params.actionTxt) params.actionExt = actionExt.value;
  if (platform.value === 'android') {
    params.showCloseButton = showCloseButton.value;
    params.isBright = isBright.value;
  }
  return params;
});
const navigationParams = computed(() => navigationOptions({
  ...appearance.value,
  url: new URL('./navigation-theme.html', window.location.href).href,
  title: '导航栏样式子页', hidden: hidden.value, waitForReady: true
}, platform.value));
const navigationCode = computed(() => `// 首帧前生效，无需目标 H5 再次设置\nconst options = ${JSON.stringify(navigationParams.value, null, 2)};\nawait mwb.navigateTo(options);\n// 替换时使用相同外观字段\nvoid mwb.redirectTo(options).catch(console.error);`);
const code = computed(() => {
  const values = JSON.stringify(theme.value, null, 2);
  if (!theme.value.actionTxt) return `await mwb.setNavigationBarTheme(${values});`;
  return `const theme = ${values};\ntheme.onActionClick = ({ actionExt }) => {\n  console.log('导航栏按钮点击', actionExt);\n};\nawait mwb.setNavigationBarTheme(theme);`;
});

onMounted(() => {
  if (!bridgeReady || !sdk) return;
  try {
    // 独立子页拥有独立 WebView，继续允许 Safari 检查当前页面。
    sdk.setEnableDebug?.(true);
    platform.value = sdk.getDeviceInfoSync().osType === 1 ? 'android' : 'ios';
  } catch (error) {
    status.value = `读取原生环境失败：${error.message ?? String(error)}`;
    statusType.value = 'error';
  }
});

async function applyTheme() {
  if (!bridgeReady || !sdk) {
    status.value = '请在 iOS 或 Android Demo 容器中打开此页。';
    statusType.value = 'error';
    return;
  }
  if (!validAppearance()) {
    status.value = '颜色请输入 6 位十六进制值；检查返回文案及字号：标题 1–32，按钮 1–28。';
    statusType.value = 'error';
    return;
  }
  busy.value = true;
  try {
    // 回调由 SDK 留在当前网页，原生点击后只回传 actionExt。
    const onActionClick = theme.value.actionTxt ? ({ actionExt: value }) => {
      status.value = `右上角按钮已点击，回传数据：${value ?? '无'}`;
      statusType.value = 'success';
    } : undefined;
    await sdk.setNavigationBarTheme({ ...theme.value, onActionClick });
    status.value = theme.value.actionTxt ? '已应用；点击右上角文字按钮查看回调。' : '已应用到当前原生导航栏。';
    statusType.value = 'success';
  } catch (error) {
    status.value = `应用失败：${error.message ?? String(error)}`;
    statusType.value = 'error';
  } finally {
    busy.value = false;
  }
}

async function goBack() {
  if (bridgeReady && sdk) {
    try { await sdk.navigateBack(); }
    catch (error) { status.value = `返回失败：${error.message ?? String(error)}`; statusType.value = 'error'; }
  } else {
    window.history.back();
  }
}

function validAppearance() {
  const value = appearance.value;
  return value.color && value.titleColor && value.buttonColor && value.separatorColor && value.backButtonText.trim()
    && Number.isFinite(value.titleFontSize) && value.titleFontSize > 0 && value.titleFontSize <= 32
    && Number.isFinite(value.buttonFontSize) && value.buttonFontSize > 0 && value.buttonFontSize <= 28;
}

async function openNewContainer(replace = false) {
  if (!bridgeReady || !sdk) {
    openError.value = '请在 iOS 或 Android Demo 容器中打开此页。';
    return;
  }
  if (opening.value) return;
  if (!validAppearance()) { openError.value = '请检查颜色、返回文案和字号后重试。'; return; }
  opening.value = true;
  replacing.value = replace;
  openError.value = '';
  try {
    // 打开时传入外观，Android 不发送 waitForReady，也不传来源页的操作函数。
    await sdk[replace ? 'redirectTo' : 'navigateTo'](navigationParams.value);
  } catch (error) {
    openError.value = `${replace ? "替换当前容器" : "打开新容器"}失败：${error.message ?? String(error)}`;
  } finally {
    opening.value = false;
    replacing.value = false;
  }
}
</script>

<template>
  <main class="theme-page">
    <div class="theme-page-top">
      <button type="button" class="back-button" @click="goBack">返回上一页</button>
      <span class="theme-platform">{{ platform === 'ios' ? 'iOS 原生预览' : platform === 'android' ? 'Android 原生预览' : '浏览器预览' }}</span>
    </div>

    <header class="theme-heading">
      <h1>导航栏样式</h1>
      <p>默认隐藏导航栏；取消下方隐藏选项并应用，即可预览手机顶部的原生样式。</p>
      <p v-if="platform === 'ios'">从无导航栏的主示例页进入后，显示并应用默认深色栏，再从屏幕左边缘慢慢向右拖动。观察导航栏随手势退场；拖回取消时会恢复。</p>
    </header>

    <form class="theme-form" @submit.prevent="applyTheme">
      <label class="theme-field" for="theme-title"><span>标题</span><input id="theme-title" name="title" v-model="title" type="text" maxlength="60" placeholder="输入导航栏标题"></label>

      <div class="theme-color-grid">
        <label class="theme-field" for="theme-color"><span>背景色</span><div class="theme-color-control"><input type="color" aria-label="选择背景色" :value="hex(color) ? `#${hex(color)}` : '#12374a'" @input="color = $event.target.value"><input id="theme-color" name="color" v-model="color" type="text" inputmode="text" spellcheck="false" placeholder="#12374a"></div></label>
        <label class="theme-field" for="theme-title-color"><span>标题色</span><div class="theme-color-control"><input type="color" aria-label="选择标题色" :value="hex(titleColor) ? `#${hex(titleColor)}` : '#ffffff'" @input="titleColor = $event.target.value"><input id="theme-title-color" name="titleColor" v-model="titleColor" type="text" inputmode="text" spellcheck="false" placeholder="#ffffff"></div></label>
      </div>

      <label class="theme-switch"><span><strong>隐藏导航栏</strong><small>隐藏后可用本页的“返回上一页”返回</small></span><input name="hidden" v-model="hidden" type="checkbox"></label>

      <label class="theme-field" for="theme-button-color"><span>按钮颜色（返回、关闭、右侧操作）</span><input id="theme-button-color" name="buttonColor" v-model="buttonColor" type="text" spellcheck="false" placeholder="#049f91"></label>
      <button type="button" class="back-button" @click="buttonColor = titleColor">复制标题颜色到按钮</button>
      <label v-if="platform === 'ios'" class="theme-switch"><span><strong>显示按钮背景</strong><small>iOS 26 起生效。深色栏去底后，可试试浅色按钮，如 #74E1D5。</small></span><input name="buttonBackgroundVisible" v-model="buttonBackgroundVisible" type="checkbox"></label>
      <div class="theme-color-grid">
        <label class="theme-field" for="theme-back-style"><span>返回样式</span><select id="theme-back-style" name="backButtonStyle" v-model="backButtonStyle"><option value="text">文字</option><option value="arrow">箭头</option><option value="arrowText">箭头加文字</option></select></label>
        <label class="theme-field" for="theme-back-text"><span>返回文字</span><input id="theme-back-text" name="backButtonText" v-model="backButtonText" required maxlength="20"></label>
      </div>
      <label class="theme-switch"><span><strong>显示返回按钮</strong><small>保留系统返回和侧滑行为</small></span><input name="showBackButton" v-model="showBackButton" type="checkbox"></label>
      <label class="theme-switch"><span><strong>显示底部分隔线</strong></span><input name="separatorVisible" v-model="separatorVisible" type="checkbox"></label>
      <label class="theme-field" for="theme-separator-color"><span>分隔线颜色</span><input id="theme-separator-color" name="separatorColor" v-model="separatorColor" type="text" spellcheck="false" placeholder="#dfe8e5"></label>
      <div class="theme-color-grid">
        <label class="theme-field" for="theme-title-size"><span>标题字号（pt / sp）</span><input id="theme-title-size" name="titleFontSize" v-model="titleFontSize" type="number" min="1" max="32" step="0.5" required></label>
        <label class="theme-field" for="theme-button-size"><span>按钮字号（pt / sp）</span><input id="theme-button-size" name="buttonFontSize" v-model="buttonFontSize" type="number" min="1" max="28" step="0.5" required></label>
      </div>
      <label class="theme-field" for="theme-title-weight"><span>标题字重</span><select id="theme-title-weight" name="titleFontWeight" v-model="titleFontWeight"><option value="regular">常规</option><option value="medium">中等</option><option value="semibold">半粗</option><option value="bold">粗体</option></select></label>

      <div class="theme-action-fields">
        <label class="theme-field" for="theme-action-text"><span>右上角文字按钮</span><input id="theme-action-text" name="actionTxt" v-model="actionTxt" type="text" maxlength="12" placeholder="例如：保存；留空则移除按钮"></label>
        <label class="theme-field" for="theme-action-ext"><span>点击回传数据</span><input id="theme-action-ext" name="actionExt" v-model="actionExt" type="text" placeholder="例如：draft-42"></label>
        <p>应用后点击手机顶部的文字按钮，回调结果会显示在下方。</p>
      </div>

      <fieldset v-if="platform === 'android'" class="theme-android">
        <legend>Android 更多选项</legend>
        <label class="theme-switch"><span><strong>显示关闭按钮</strong></span><input name="showCloseButton" v-model="showCloseButton" type="checkbox"></label>
        <label class="theme-switch"><span><strong>亮色状态栏</strong></span><input name="isBright" v-model="isBright" type="checkbox"></label>
      </fieldset>

      <button type="submit" class="run-button theme-apply" :disabled="busy">{{ busy ? '正在应用…' : '应用样式' }}</button>
    </form>

    <p class="theme-status" :data-state="statusType" role="status" aria-live="polite">{{ status }}</p>
    <section class="theme-code" aria-labelledby="theme-code-title"><h2 id="theme-code-title">对应 SDK 调用</h2><pre class="code-panel"><code>{{ code }}</code></pre></section>
    <section class="theme-code"><h2>带当前样式打开或替换</h2><p>目标首帧前生效；右侧操作由目标网页自行注册。</p><pre class="code-panel"><code>{{ navigationCode }}</code></pre></section>
    <button type="button" class="run-button theme-open-page" :disabled="opening" @click="openNewContainer(false)">{{ opening && !replacing ? '正在打开…' : '打开新容器页面' }}</button>
    <button type="button" class="run-button theme-open-page theme-replace-page" :disabled="opening" @click="openNewContainer(true)">{{ replacing ? '正在替换…' : '用当前样式替换本页' }}</button>
    <p v-if="openError" class="theme-status theme-open-error" data-state="error" role="status" aria-live="polite">{{ openError }}</p>
  </main>
</template>
