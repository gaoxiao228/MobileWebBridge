import { readFileSync } from 'node:fs';

// 脚本常被单独复制；完整许可随 bundle 保留，不能只链接源码目录的文件。
export const licenseBanner = `/*!\n${readFileSync(new URL('../LICENSE', import.meta.url), 'utf8')}\n${readFileSync(new URL('../THIRD_PARTY_NOTICES.md', import.meta.url), 'utf8')}\n*/`;
