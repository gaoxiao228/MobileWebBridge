import { cpSync, existsSync, lstatSync, mkdirSync, realpathSync } from 'node:fs';
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = realpathSync(fileURLToPath(new URL('../', import.meta.url)));
const argument = process.argv.slice(2);
const inside = path => {
  const child = relative(root, path);
  return child === '' || (!isAbsolute(child) && child !== '..' && !child.startsWith(`..${sep}`));
};

try {
  if (argument.length !== 1) throw new Error('Usage: node scripts/export-source.mjs /existing/parent/new-directory');
  const requested = resolve(argument[0]);
  if (existsSync(requested)) throw new Error('Destination already exists; choose a new directory');
  // 先解析父目录，避免经符号链接把导出目标指回源码并递归复制。
  const destination = join(realpathSync(dirname(requested)), basename(requested));
  if (inside(destination)) throw new Error('Destination must be outside the source tree');
  // 仅导出公开接入资料，维护文档即使存在于本机也不复制。
  const publicRoots = ['README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'CHANGELOG.md', 'SECURITY.md', '.gitignore',
    'MobileWebBridge.podspec', '.env.android-release.example', 'docs/native-plugins.md', 'docs/compatibility.md', 'docs/versioning.md',
    'scripts', 'test', '.github', 'MWB-JS', 'MWB-iOS', 'MWB-Android', 'MWB-Demo-Web'];
  const excluded = new Set(['node_modules', 'dist', 'build', 'Pods', '.gradle', '.kotlin', '.git', '.idea', 'xcuserdata', '.DS_Store',
    '.superpowers', '.impeccable', '__pycache__', 'local.properties', '.env', '.npmrc']);
  const permit = path => {
    const parts = relative(root, path).split(sep);
    const name = parts.at(-1);
    // 不跟随任何符号链接；忽略签名、密钥、环境文件与本机IDE产物。
    return !lstatSync(path).isSymbolicLink() && !parts.some(part => excluded.has(part))
      && !(!['.env.example', '.env.android-release.example'].includes(name) && /^\.env\./.test(name)) && !/\.(?:p12|p8|pem|key|jks|keystore|mobileprovision|xcuserstate|iml|ipa|apk|aar|tgz)$/i.test(name);
  };
  mkdirSync(destination);
  for (const name of publicRoots) {
    const source = join(root, name);
    if (existsSync(source)) cpSync(source, join(destination, name), { recursive: true, preserveTimestamps: false, filter: permit });
  }
  console.log(`Public source exported to ${destination}`);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
