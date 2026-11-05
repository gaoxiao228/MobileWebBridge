import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

// 库模式把 Vue 页面和运行时打成普通脚本，供两个 file:// WebView 直接加载。
export default defineConfig({
  plugins: [vue()],
  publicDir: false,
  // Vue 运行时读取此常量；本地 WebView 没有 Node 的 process 全局变量。
  define: { 'process.env.NODE_ENV': JSON.stringify('production') },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    lib: {
      entry: 'src/main.js',
      name: 'MWBDemo',
      formats: ['iife'],
      fileName: () => 'demo.js',
      cssFileName: 'styles'
    }
  }
});
