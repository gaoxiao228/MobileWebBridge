import { expect, test } from "vitest";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

/** 捕获未先构建时发布空包、遗漏类型或第三方许可的真实打包回归。 */
test("packing fresh source builds an installable SDK with declarations and license notices", () => {
  const temporary = mkdtempSync(join(tmpdir(), "mwb-pack-contract-"));
  const source = join(temporary, "sdk");
  const consumer = join(temporary, "consumer");
  mkdirSync(source);
  try {
    // 独立源码目录不复制 dist；仅复用已安装的构建工具，测试不请求网络。
    for (const name of ["src", "scripts", "package.json", "tsconfig.json", "tsconfig.build.json", "LICENSE", "README.md", "THIRD_PARTY_NOTICES.md"]) {
      if (existsSync(name)) cpSync(name, join(source, name), { recursive: true });
    }
    symlinkSync(resolve("node_modules"), join(source, "node_modules"), "dir");
    const packed = spawnSync("npm", ["pack", "--json", "--pack-destination", temporary], { cwd: source, encoding: "utf8" });
    expect(packed.status, packed.stderr || packed.stdout).toBe(0);
    const info = JSON.parse(packed.stdout)[0] as { filename: string; files: { path: string }[] };
    const paths = info.files.map(file => file.path);
    expect(paths).toEqual(expect.arrayContaining(["dist/index.js", "dist/index.d.ts", "dist/mwb.iife.js", "LICENSE", "THIRD_PARTY_NOTICES.md"]));
    expect(paths.some(path => path.startsWith("test/") || path.startsWith("src/") || path.startsWith("node_modules/"))).toBe(false);

    // 将真实 tgz 解包为消费端包，验证入口解析、运行时与公开声明，不读取源码代替产物。
    const installed = join(consumer, "node_modules/mobile-web-bridge");
    mkdirSync(installed, { recursive: true });
    const extracted = spawnSync("tar", ["-xzf", join(temporary, info.filename), "--strip-components=1", "-C", installed], { encoding: "utf8" });
    expect(extracted.status, extracted.stderr).toBe(0);
    for (const file of ["dist/index.js", "dist/mwb.iife.js"]) {
      const bundle = readFileSync(join(installed, file), "utf8");
      expect(bundle).toContain("wendux");
      expect(bundle).toContain("Permission is hereby granted");
      expect(bundle.includes(resolve("node_modules").slice(1)), `local dependency path in ${file}`).toBe(false);
    }
    // SDK针对浏览器；只提供宿主全局对象，不把本次打包修复扩大为SSR支持。
    const imported = spawnSync(process.execPath, ["--input-type=module", "-e", 'globalThis.window={};Object.defineProperty(globalThis,"navigator",{value:{userAgent:"test"}});const {mwb,defineNativePlugin}=await import("mobile-web-bridge");if(mwb.basic.toast!==mwb.toast||typeof defineNativePlugin!=="function")process.exit(1)'], { cwd: consumer, encoding: "utf8" });
    expect(imported.status, imported.stderr).toBe(0);
    writeFileSync(join(consumer, "example.ts"), 'import {mwb,createMWB,defineNativePlugin,type GenericAsyncResult} from "mobile-web-bridge";\nconst plugin=defineNativePlugin<{echo(p:{value:string}):Promise<GenericAsyncResult<string>>}>()({name:"example"});\nconst client=createMWB({plugins:[plugin]});\nclient.example.echo({value:"hello"});\nmwb.basic.getStorageSync<string>("key");\n');
    const typed = spawnSync(process.execPath, [resolve("node_modules/typescript/lib/tsc.js"), "--noEmit", "--strict", "--skipLibCheck", "--target", "ES2022", "--module", "ESNext", "--moduleResolution", "Bundler", join(consumer, "example.ts")], { cwd: consumer, encoding: "utf8" });
    expect(typed.status, typed.stderr || typed.stdout).toBe(0);
  } finally { rmSync(temporary, { recursive: true, force: true }); }
}, 30000);
