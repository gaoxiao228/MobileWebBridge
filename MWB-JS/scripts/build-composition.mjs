import { build } from "esbuild";
import { mkdir } from "node:fs/promises";
import { licenseBanner } from "./license-banner.mjs";

// 组合构建只接受已公开的插件名，避免命令输入被拼接为任意源码。
const groups = ["container", "device", "media", "storage"];
const pluginNames = ["basic", ...groups];
const option = process.argv.find(argument => argument.startsWith("--plugins="));
const selected = option?.slice("--plugins=".length).split(",").filter(Boolean) ?? [];
const unknown = selected.filter(name => !pluginNames.includes(name));
if (selected.length === 0 || unknown.length > 0) {
  console.error(`Invalid plugins. Available: ${pluginNames.join(", ")}`);
  process.exit(1);
}

// basic 为完整官方插件；与旧分组混用时只包含一次实际方法。
const expanded = [...new Set(selected.flatMap(name => name === "basic" ? groups : [name]))];
const imports = expanded.map(name =>
  `import { ${name}Plugin } from "./src/plugins/${name}.ts";`
).join("\n");
const code = `import "dsbridge";
import { assembleMWB } from "./src/assembleMWB.ts";
${imports}
window.mwb = assembleMWB([${expanded.map(name => `${name}Plugin`).join(", ")}]);`;

await mkdir("dist", { recursive: true });
await build({
  stdin: { contents: code, sourcefile: "mwb-composition.ts", resolveDir: process.cwd(), loader: "ts" },
  bundle: true,
  format: "iife",
  platform: "browser",
  preserveSymlinks: true,
  banner: { js: licenseBanner },
  outfile: `dist/mwb.${selected.join("-")}.iife.js`
});
