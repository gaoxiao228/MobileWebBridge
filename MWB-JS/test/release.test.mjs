import { afterEach, expect, test } from 'vitest';
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const temporary = [];
afterEach(() => { for (const path of temporary.splice(0)) rmSync(path, { recursive: true, force: true }); });

/** 在真实临时工程执行 CLI；仅替换 npm 外部边界，杜绝测试实际公开发布。 */
function fixture() {
  const root = mkdtempSync(join(tmpdir(), 'mwb-release-'));
  temporary.push(root);
  for (const name of ['scripts', 'src', 'bin']) mkdirSync(join(root, name));
  const script = resolve('scripts/release.mjs');
  if (existsSync(script)) copyFileSync(script, join(root, 'scripts/release.mjs'));
  const manifest = '{\n  "name": "mobile-web-bridge",\n  "version": "0.1.0",\n  "type": "module"\n}\n';
  const types = '// SDK version fixture\nexport const version = "0.1.0";\nexport type Result = string;\n';
  writeFileSync(join(root, 'package.json'), manifest);
  writeFileSync(join(root, 'src/types.ts'), types);
  writeFileSync(join(root, 'pnpm-lock.yaml'), "lockfileVersion: '9.0'\n");
  // tar 保持真实打包/解包行为；记录命令执行时的版本和发布时的包内容。
  const npm = join(root, 'bin/npm');
  writeFileSync(npm, `#!${process.execPath}
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const args = process.argv.slice(2);
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const entry = {args, version: pkg.version, types: fs.readFileSync('src/types.ts', 'utf8')};
if (args[0] === 'publish') {
  entry.packed = JSON.parse(execFileSync('tar', ['-xOf', args[1], 'package.json'], {encoding: 'utf8'}));
  entry.packedTypes = execFileSync('tar', ['-xOf', args[1], 'src/types.ts'], {encoding: 'utf8'});
}
fs.appendFileSync('commands.jsonl', JSON.stringify(entry) + '\\n');
if (process.env.INTERRUPT_NPM === args[0]) {
  process.kill(process.ppid, process.env.RELEASE_SIGNAL || 'SIGTERM');
  // 留出事件循环处理信号的时间，避免测试在父进程退出前继续执行发布。
  setTimeout(() => process.exit(0), 500);
  await new Promise(() => {});
}
if (process.env.FAIL_NPM === args.slice(0, 2).join(' ') || process.env.FAIL_NPM === args[0]) process.exit(7);
if (args[0] === 'pack') {
  const destination = args[args.indexOf('--pack-destination') + 1];
  const filename = pkg.name + '-' + pkg.version + '.tgz';
  execFileSync('tar', ['-czf', path.join(destination, filename), 'package.json', 'src/types.ts']);
  console.log(JSON.stringify([{name: pkg.name, version: process.env.WRONG_PACK_VERSION ? '9.9.9' : pkg.version, filename}]));
} else if (args[0] !== 'publish' && args[0] !== 'test' && args.join(' ') !== 'run typecheck') {
  console.error('Unexpected npm command'); process.exit(8);
}
`);
  chmodSync(npm, 0o755);
  const read = name => readFileSync(join(root, name), 'utf8');
  return {
    root, read, manifest, types,
    commands: () => existsSync(join(root, 'commands.jsonl')) ? read('commands.jsonl').trim().split('\n').map(line => JSON.parse(line)) : [],
    run: (args, env = {}) => spawnSync(process.execPath, ['scripts/release.mjs', ...args], {
      cwd: root, encoding: 'utf8', timeout: 10000, env: { ...process.env, PATH: join(root, 'bin') + delimiter + process.env.PATH, ...env },
    }),
  };
}

test('dry-run validates and packs the requested version while restoring both source versions', () => {
  const sdk = fixture();
  const result = sdk.run(['--', '0.2.0-beta.1', '--dry-run']);
  expect(result.status, result.stderr).toBe(0);
  const commands = sdk.commands();
  expect(commands.map(call => call.args[0])).toEqual(['run', 'test', 'pack', 'publish']);
  for (const call of commands) {
    expect(call.version).toBe('0.2.0-beta.1');
    expect(call.types).toContain('export const version = "0.2.0-beta.1";');
  }
  const published = commands.at(-1);
  expect(published.args).toEqual(['publish', expect.stringMatching(/\.tgz$/), '--registry', 'https://registry.npmjs.org/', '--access', 'public', '--tag', 'next', '--dry-run']);
  expect(published.packed.version).toBe('0.2.0-beta.1');
  expect(published.packedTypes).toContain('export const version = "0.2.0-beta.1";');
  expect(sdk.read('package.json')).toBe(sdk.manifest);
  expect(sdk.read('src/types.ts')).toBe(sdk.types);
  expect(sdk.read('pnpm-lock.yaml')).toBe("lockfileVersion: '9.0'\n");
});

test('real release publishes the checked tarball and retains the requested package and runtime versions', () => {
  const sdk = fixture();
  const result = sdk.run(['0.2.0', '--tag', 'latest']);
  expect(result.status, result.stderr).toBe(0);
  const published = sdk.commands().at(-1);
  expect(published.args).toContain('latest');
  expect(published.args).not.toContain('--dry-run');
  expect(published.packed.version).toBe('0.2.0');
  expect(published.packedTypes).toContain('export const version = "0.2.0";');
  expect(JSON.parse(sdk.read('package.json')).version).toBe('0.2.0');
  expect(sdk.read('src/types.ts')).toContain('export const version = "0.2.0";');
});

test.each([
  [], ['latest'], ['01.2.3'], ['1.2'], ['1.2.3; echo unsafe'], ['1.2.3-beta.01'], ['1.2.3+build.1'],
  ['1.2.3', '--unknown'], ['1.2.3', '--tag'], ['1.2.3', '--tag', 'v1'],
  ['1.2.3-beta.1', '--tag', 'latest'], ['1.2.3', '2.0.0'],
])('invalid arguments %j fail before changing files or running npm', (...args) => {
  const sdk = fixture();
  const result = sdk.run(args);
  expect(result.status).not.toBe(0);
  expect(result.stderr).toMatch(/版本|参数|标签/);
  expect(sdk.commands()).toEqual([]);
  expect(sdk.read('package.json')).toBe(sdk.manifest);
  expect(sdk.read('src/types.ts')).toBe(sdk.types);
});

test.each(['run typecheck', 'test', 'pack'])('%s failure restores versions and prevents publishing', command => {
  const sdk = fixture();
  const result = sdk.run(['0.2.0'], { FAIL_NPM: command });
  expect(result.status).not.toBe(0);
  expect(sdk.commands().at(-1)?.args.slice(0, command.split(' ').length).join(' ')).toBe(command);
  expect(sdk.commands().some(call => call.args[0] === 'publish')).toBe(false);
  expect(sdk.read('package.json')).toBe(sdk.manifest);
  expect(sdk.read('src/types.ts')).toBe(sdk.types);
});

test('a tarball reporting the wrong version is never published', () => {
  const sdk = fixture();
  const result = sdk.run(['0.2.0'], { WRONG_PACK_VERSION: '1' });
  expect(result.status).not.toBe(0);
  expect(sdk.commands().at(-1)?.args[0]).toBe('pack');
  expect(result.stderr).toMatch(/版本/);
  expect(sdk.commands().some(call => call.args[0] === 'publish')).toBe(false);
  expect(sdk.read('package.json')).toBe(sdk.manifest);
  expect(sdk.read('src/types.ts')).toBe(sdk.types);
});

test('an uncertain real publish failure retains versions and tells the maintainer to verify npm', () => {
  const sdk = fixture();
  const result = sdk.run(['0.2.0'], { FAIL_NPM: 'publish' });
  expect(result.status).not.toBe(0);
  expect(result.stderr).toMatch(/核实.*npm/);
  expect(JSON.parse(sdk.read('package.json')).version).toBe('0.2.0');
  expect(sdk.read('src/types.ts')).toContain('export const version = "0.2.0";');
});

test('a dry-run publish failure still restores both source versions', () => {
  const sdk = fixture();
  const result = sdk.run(['0.2.0', '--dry-run'], { FAIL_NPM: 'publish' });
  expect(result.status).not.toBe(0);
  expect(sdk.commands().at(-1)?.args[0]).toBe('publish');
  expect(sdk.read('package.json')).toBe(sdk.manifest);
  expect(sdk.read('src/types.ts')).toBe(sdk.types);
});

test('a missing runtime version declaration fails before editing the manifest or running npm', () => {
  const sdk = fixture();
  writeFileSync(join(sdk.root, 'src/types.ts'), 'export type Result = string;\n');
  const result = sdk.run(['0.2.0']);
  expect(result.status).not.toBe(0);
  expect(result.stderr).toMatch(/版本/);
  expect(sdk.commands()).toEqual([]);
  expect(sdk.read('package.json')).toBe(sdk.manifest);
  expect(sdk.read('src/types.ts')).toBe('export type Result = string;\n');
});

test('help explains usage without changing versions or running npm', () => {
  const sdk = fixture();
  const result = sdk.run(['--help']);
  expect(result.status, result.stderr).toBe(0);
  expect(result.stdout).toContain('--dry-run');
  expect(result.stdout).toContain('--tag');
  expect(sdk.commands()).toEqual([]);
  expect(sdk.read('package.json')).toBe(sdk.manifest);
});

test.each(['SIGINT', 'SIGTERM'])('%s during dry-run restores source versions and prevents publishing', signal => {
  const sdk = fixture();
  const result = sdk.run(['0.2.0', '--dry-run'], { INTERRUPT_NPM: 'run', RELEASE_SIGNAL: signal });
  expect(result.status).not.toBe(0);
  expect(sdk.commands().map(call => call.args[0])).toEqual(['run']);
  expect(sdk.read('package.json')).toBe(sdk.manifest);
  expect(sdk.read('src/types.ts')).toBe(sdk.types);
});

test('interrupting an in-flight real publish retains the version for checking the registry', () => {
  const sdk = fixture();
  const result = sdk.run(['0.2.0'], { INTERRUPT_NPM: 'publish' });
  expect(result.status).not.toBe(0);
  expect(sdk.commands().at(-1)?.args[0]).toBe('publish');
  expect(result.stderr).toMatch(/核实.*npm/);
  expect(JSON.parse(sdk.read('package.json')).version).toBe('0.2.0');
});
