import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { licenseBanner } from '../../MWB-JS/scripts/license-banner.mjs';

const project = fileURLToPath(new URL('../', import.meta.url));
const workspace = fileURLToPath(new URL('../../', import.meta.url));
const sdk = join(workspace, 'MWB-JS');
const output = join(project, 'dist');
const pageFiles = ['index.html', 'navigation-theme.html', 'native-plugins.html', 'styles.css'];
const demoBundle = 'demo.js';
const allFiles = [...pageFiles, demoBundle, 'mwb.iife.js', 'plugins.iife.js', 'LICENSE.txt', 'THIRD_PARTY_NOTICES.txt'];
const syncNative = process.argv.slice(2).includes('--sync-native');

if (process.argv.slice(2).some(arg => arg !== '--sync-native')) {
  throw new Error('只支持 --sync-native 参数。');
}

// 先重新构建 SDK，确保演示页使用的是当前源码，而不是旧的浏览器包。
execFileSync('pnpm', ['build'], { cwd: sdk, stdio: 'inherit' });
// Vite 库模式将 Vue 运行时和组件打包成 IIFE，避免本地 file:// 的 ES Module 限制。
execFileSync('pnpm', ['exec', 'vite', 'build'], { cwd: project, stdio: 'inherit' });
// Vite压缩会移除Rollup banner；在最终产物上加完整许可，避免发布时丢失。
const demoPath = join(output, demoBundle);
const demoLicense = `/*!\n${readFileSync(join(project, 'LICENSE'), 'utf8')}\n${readFileSync(join(project, 'THIRD_PARTY_NOTICES.md'), 'utf8')}\n*/\n`;
writeFileSync(demoPath, demoLicense + readFileSync(demoPath, 'utf8'));
copyFileSync(join(project, 'src/index.html'), join(output, 'index.html'));
copyFileSync(join(project, 'src/navigation-theme.html'), join(output, 'navigation-theme.html'));
copyFileSync(join(project, 'src/native-plugins.html'), join(output, 'native-plugins.html'));
copyFileSync(join(sdk, 'dist', 'mwb.iife.js'), join(output, 'mwb.iife.js'));
copyFileSync(join(project, 'LICENSE'), join(output, 'LICENSE.txt'));
copyFileSync(join(project, 'THIRD_PARTY_NOTICES.md'), join(output, 'THIRD_PARTY_NOTICES.txt'));
// 接入方用自己的 TS 入口组合 native 插件；原默认 SDK 产物保持独立。
execFileSync('pnpm', ['exec', 'esbuild', join(project, 'src/plugins-sdk.ts'), '--bundle', '--format=iife', '--platform=browser', '--preserve-symlinks', `--banner:js=${licenseBanner}`, `--outfile=${join(output, 'plugins.iife.js')}`], { cwd: sdk, stdio: 'inherit' });
console.log(`已生成 ${output}`);

if (syncNative) {
  // 原生工程保留本地 HTML，线上静态站点和两个 App 使用同一组构建文件。
  for (const target of [
    join(workspace, 'MWB-iOS/Example/Resources'),
    join(workspace, 'MWB-Android/sample/src/main/assets')
  ]) {
    mkdirSync(target, { recursive: true });
    for (const file of allFiles) copyFileSync(join(output, file), join(target, file));
    console.log(`已同步 ${target}`);
  }
}
