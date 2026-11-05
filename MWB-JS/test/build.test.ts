import { expect, test } from "vitest";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import vm from "node:vm";

test("the browser build exposes mwb without global package managers or a legacy sp global", () => {
  // 隔离 PATH，确保发布检查只依赖当前 Node 和项目依赖，不依赖全局 pnpm。
  const build = spawnSync(process.execPath, ["scripts/build.mjs"], {
    cwd: process.cwd(), encoding: "utf8", env: { ...process.env, PATH: "" }
  });
  expect(build.status, build.error?.message || build.stderr || build.stdout).toBe(0);

  const file = resolve("dist/mwb.iife.js");
  expect(existsSync(file)).toBe(true);
  const browserWindow: Record<string, unknown> = {};
  vm.runInNewContext(readFileSync(file, "utf8"), {
    window: browserWindow,
    navigator: { userAgent: "test" },
    setTimeout() {},
    console
  });
  expect(typeof (browserWindow.mwb as Record<string, unknown>).navigateTo).toBe("function");
  expect(browserWindow.sp).toBeUndefined();
  expect(existsSync(resolve("dist/index.js"))).toBe(true);
  expect(existsSync(resolve("dist/index.d.ts"))).toBe(true);
}, 15000);

test("unknown composition plugins fail with available names", () => {
  const result = spawnSync(process.execPath, ["scripts/build-composition.mjs", "--plugins=unknown"], {
    cwd: process.cwd(), encoding: "utf8"
  });

  expect(result.status).not.toBe(0);
  expect(result.stderr).toContain("container");
  expect(result.stderr).toContain("device");
});

test("a selected composition is smaller than the full browser bundle", () => {
  const result = spawnSync(process.execPath, ["scripts/build-composition.mjs", "--plugins=container,device"], {
    cwd: process.cwd(), encoding: "utf8"
  });
  expect(result.status, result.stderr).toBe(0);

  const full = readFileSync(resolve("dist/mwb.iife.js")).byteLength;
  const selected = readFileSync(resolve("dist/mwb.container-device.iife.js")).byteLength;
  expect(full - selected).toBeGreaterThan(1000);
});

test("local composition artifacts are excluded from the public package", () => {
  const result = spawnSync("npm", ["pack", "--dry-run", "--json"], {
    cwd: process.cwd(), encoding: "utf8"
  });
  expect(result.status, result.stderr).toBe(0);
  const files = (JSON.parse(result.stdout) as Array<{ files: Array<{ path: string }> }>)[0].files;
  expect(files.some(file => file.path === "dist/mwb.container-device.iife.js")).toBe(false);
}, 15000);

test("basic composition expands once when mixed with legacy groups", () => {
  const result = spawnSync(process.execPath, ["scripts/build-composition.mjs", "--plugins=basic,container"], {
    cwd: process.cwd(), encoding: "utf8"
  });
  expect(result.status, result.stderr).toBe(0);
  const browserWindow: Record<string, unknown> = {};
  vm.runInNewContext(readFileSync(resolve("dist/mwb.basic-container.iife.js"), "utf8"), {
    window: browserWindow, navigator: { userAgent: "test" }, setTimeout() {}, console
  });
  const sdk = browserWindow.mwb as { navigateTo: unknown; basic: { navigateTo: unknown; chooseImage: unknown } };
  expect(sdk.basic.navigateTo).toBe(sdk.navigateTo);
  expect(typeof sdk.basic.chooseImage).toBe("function");
});
