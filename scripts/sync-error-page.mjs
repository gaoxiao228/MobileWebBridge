import { copyFileSync, mkdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

// 默认资源由同一来源生成，发布包本身不依赖此脚本或共享目录。
const root = fileURLToPath(new URL('../', import.meta.url));
const args = process.argv.slice(2);
if (args.some(arg => arg !== '--check') || args.length > 1) throw new Error('只支持 --check 参数。');
const files = ['index.html', 'error.css', 'error.js', 'runtime.js'];
for (const path of ['MWB-iOS/Resources/ErrorPage', 'MWB-Android/mwb/src/main/assets/mwb-error']) {
  const target = join(root, path);
  if (!args.length) mkdirSync(target, { recursive: true });
  for (const file of files) {
    const source = join(root, 'MWB-ErrorPage', file);
    if (!args.length) copyFileSync(source, join(target, file));
    else if (!readFileSync(source).equals(readFileSync(join(target, file)))) throw new Error(`资源不同步：${path}/${file}`);
  }
}
console.log(args.length ? '默认错误页资源一致' : '默认错误页已同步到两端 SDK');
