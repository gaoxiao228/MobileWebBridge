import { createApp } from 'vue';
import App from './App.vue';
import NavigationTheme from './NavigationTheme.vue';
import NativePlugins from './NativePlugins.vue';
import './styles.css';

// 两个独立 HTML 入口复用同一份离线脚本，各自挂载对应的页面。
const path = window.location.pathname;
const page = path.endsWith('/native-plugins.html') ? NativePlugins : path.endsWith('/navigation-theme.html') ? NavigationTheme : App;
createApp(page).mount('#app');
