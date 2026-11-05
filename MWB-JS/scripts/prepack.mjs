import { readFileSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const project = fileURLToPath(new URL('../', import.meta.url));
// 每次打包重新构建，既修复空 dist，也避免发布与当前源码不一致的旧产物。
execFileSync(process.execPath, [fileURLToPath(new URL('./build.mjs', import.meta.url))], { cwd: project, stdio: 'inherit' });
for (const file of ['dist/index.js', 'dist/index.d.ts', 'dist/mwb.iife.js', 'LICENSE', 'THIRD_PARTY_NOTICES.md']) {
  if (!statSync(new URL(`../${file}`, import.meta.url)).size) throw new Error(`Empty package artifact: ${file}`);
}
for (const file of ['dist/index.js', 'dist/mwb.iife.js']) {
  const text = readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');
  if (!text.includes('wendux') || !text.includes('Permission is hereby granted')) throw new Error(`Missing license notice: ${file}`);
}
