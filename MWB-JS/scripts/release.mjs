import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, join } from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const project = fileURLToPath(new URL('../', import.meta.url));
const registry = 'https://registry.npmjs.org/';
const usage = `用法：npm run release -- <版本号> [--tag next|latest|beta] [--dry-run]
示例：npm run release -- 0.2.0-beta.1 --dry-run
      npm run release -- 0.2.0-beta.1
      npm run release -- 0.2.0 --tag latest
默认发布到 next 标签；--dry-run 只预演并恢复源码版本。`;

/** 仅接受完整 SemVer，拒绝 npm version 支持的 patch 等隐式递增参数。 */
function options() {
  const args = process.argv.slice(2);
  if (args[0] === '--') args.shift();
  if (args.length === 1 && ['--help', '-h'].includes(args[0])) return null;
  const version = args.shift();
  // npm 发布会移除构建元数据，拒绝 +build，避免注册表版本与 mwb.version 不同。
  if (version?.includes('+')) throw new Error('版本号不能包含 +build 构建元数据：npm 发布时会移除它。');
  const matched = version?.match(/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/);
  if (!matched || version.length > 256 || matched.slice(1, 4).some(part => !Number.isSafeInteger(Number(part)))
    || matched[4]?.split('.').some(part => /^0\d+$/.test(part))) {
    throw new Error(`请指定有效的完整版本号，例如 0.2.0 或 0.2.0-beta.1。\n${usage}`);
  }
  let tag = 'next';
  let dryRun = false;
  const seen = new Set();
  while (args.length) {
    const option = args.shift();
    if (seen.has(option)) throw new Error(`重复参数：${option}`);
    seen.add(option);
    if (option === '--dry-run') dryRun = true;
    else if (option === '--tag') {
      tag = args.shift();
      // dist-tag 不得与版本或版本范围混淆；常用 next/latest/beta/canary 均可。
      if (!tag || !/^[a-z][a-z0-9_-]*$/.test(tag) || tag === 'x' || /^v\d/.test(tag)) throw new Error('请指定有效的 npm 标签。');
    } else throw new Error(`未知参数：${option}\n${usage}`);
  }
  if (matched[4] && tag === 'latest') throw new Error('预发布版本不能使用 latest 标签，请使用 next 或 beta。');
  return { version, tag, dryRun };
}

/** 使用参数数组调用 npm，不把版本号或标签拼接成 shell 命令。 */
function npm(args, signal, capture = false) {
  return new Promise((resolve, reject) => {
    const child = spawn('npm', args, {
      cwd: project, signal, stdio: capture ? ['inherit', 'pipe', 'inherit'] : 'inherit',
    });
    let output = '';
    let failure;
    if (capture) {
      child.stdout.setEncoding('utf8');
      child.stdout.on('data', chunk => { output += chunk; });
    }
    child.on('error', error => { failure = error; });
    // 等待子进程关闭后再恢复文件；异步等待允许处理 Ctrl-C 和终止信号。
    child.once('close', (code, terminated) => {
      if (failure) reject(failure);
      else if (code !== 0) reject(new Error(`npm ${args[0]} 执行失败（${terminated || code}）。`));
      else resolve(output);
    });
  });
}

async function release({ version, tag, dryRun }) {
  const manifestPath = join(project, 'package.json');
  const typesPath = join(project, 'src/types.ts');
  const originalManifest = readFileSync(manifestPath, 'utf8');
  const originalTypes = readFileSync(typesPath, 'utf8');
  const manifest = JSON.parse(originalManifest);
  const declaration = /^export const version = ["'][^"'\r\n]+["'];?$/gm;
  if (Array.from(originalTypes.matchAll(declaration)).length !== 1) throw new Error('src/types.ts 必须包含唯一的 SDK 版本声明。');
  const temporary = mkdtempSync(join(tmpdir(), 'mwb-npm-release-'));
  const controller = new AbortController();
  const cancel = () => controller.abort();
  process.once('SIGINT', cancel);
  process.once('SIGTERM', cancel);
  let publishStarted = false;
  try {
    // pnpm 锁文件不记录根包版本；无需修改依赖、锁文件或任何原生项目版本。
    writeFileSync(manifestPath, JSON.stringify({ ...manifest, version }, null, 2) + '\n');
    writeFileSync(typesPath, originalTypes.replace(declaration, `export const version = "${version}";`));
    console.log(`${dryRun ? '预演' : '发布'} ${manifest.name}@${version}，标签 ${tag}，仓库 ${registry}`);
    await npm(['run', 'typecheck'], controller.signal);
    await npm(['test'], controller.signal);
    // prepack 自动构建并校验入口、类型与许可证；发布同一个 tgz，避免再次打包产生差异。
    const packed = JSON.parse(await npm(['pack', '--json', '--pack-destination', temporary, '--ignore-scripts=false'], controller.signal, true));
    const info = packed[0];
    if (packed.length !== 1 || info?.name !== manifest.name || info?.version !== version
      || typeof info.filename !== 'string' || basename(info.filename) !== info.filename || !info.filename.endsWith('.tgz')) {
      throw new Error('打包结果的包名、版本或文件名与发布目标不一致。');
    }
    const tarball = join(temporary, info.filename);
    if (!statSync(tarball).isFile() || !statSync(tarball).size) throw new Error('发布安装包为空或不存在。');
    publishStarted = !dryRun;
    await npm(['publish', tarball, '--registry', registry, '--access', 'public', '--tag', tag, ...(dryRun ? ['--dry-run'] : [])], controller.signal);
    console.log(dryRun ? '预演通过，未发布，源码版本将恢复。' : `已发布 ${manifest.name}@${version}（${tag}），请提交版本文件并记录变更。`);
  } catch (error) {
    if (publishStarted) console.error(`已尝试发布，保留目标版本；请核实 npm 上 ${manifest.name}@${version} 的状态后再决定是否重试。`);
    throw error;
  } finally {
    process.removeListener('SIGINT', cancel);
    process.removeListener('SIGTERM', cancel);
    // 真正发布开始后，网络失败也可能已在服务端完成，不自动回退版本或重试。
    if (!publishStarted) {
      writeFileSync(manifestPath, originalManifest);
      writeFileSync(typesPath, originalTypes);
    }
    rmSync(temporary, { recursive: true, force: true });
  }
}

try {
  const parsed = options();
  if (parsed) await release(parsed);
  else console.log(usage);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
