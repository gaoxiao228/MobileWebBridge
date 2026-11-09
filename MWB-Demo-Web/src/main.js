import { createApp } from 'vue';
import App from './App.vue';
import NavigationTheme from './NavigationTheme.vue';
import NativePlugins from './NativePlugins.vue';
import RedirectNavigation from './RedirectNavigation.vue';
import './styles.css';

// 两个独立 HTML 入口复用同一份离线脚本，各自挂载对应的页面。
const path = window.location.pathname;
// 替换示例沿用 index.html，通过明确的页面身份验证原生返回栈。
const redirectStage = new URLSearchParams(window.location.search).get('mwbRedirect');
const page = path.endsWith('/native-plugins.html') ? NativePlugins : path.endsWith('/navigation-theme.html') ? NavigationTheme :
  ['P', 'A', 'B'].includes(redirectStage) ? RedirectNavigation : App;
createApp(page).mount('#app');
