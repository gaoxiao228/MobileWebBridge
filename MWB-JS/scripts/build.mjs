import { build } from 'esbuild';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { licenseBanner } from './license-banner.mjs';

const project = fileURLToPath(new URL('../', import.meta.url));
const require = createRequire(import.meta.url);
const compiler = require.resolve('typescript/lib/tsc.js');
// 直接使用项目工具，npm prepack 不依赖调用者全局安装的 pnpm 命令。
execFileSync(process.execPath, [compiler, '--noEmit'], { cwd: project, stdio: 'inherit' });
execFileSync(process.execPath, [compiler, '-p', 'tsconfig.build.json'], { cwd: project, stdio: 'inherit' });
for (const [entry, format, output] of [['src/index.ts', 'esm', 'dist/index.js'], ['src/browser.ts', 'iife', 'dist/mwb.iife.js']]) {
  await build({ absWorkingDir: project, entryPoints: [entry], bundle: true, format, platform: 'browser',
    outfile: output, preserveSymlinks: true, banner: { js: licenseBanner }, legalComments: 'eof' });
}
