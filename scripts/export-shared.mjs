// 从浏览器扩展版仓库导出词典、词表和测试向量到 Shared/。
// 用法：node scripts/export-shared.mjs [扩展版仓库路径] [--check]
// --check：生成到临时目录，与仓库内已提交的产物逐字节比较，不一致时以非 0 退出。
import { build } from "../../chinese-variants-linter/node_modules/esbuild/lib/main.js";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const check = args.includes("--check");
const ext = path.resolve(args.find((arg) => !arg.startsWith("--")) ?? path.join(here, "../../chinese-variants-linter"));
const outfile = path.join(here, ".build/export-shared.cjs");
await build({
  entryPoints: [path.join(here, "export-shared.entry.ts")],
  bundle: true, platform: "node", format: "cjs", outfile,
  nodePaths: [path.join(ext, "node_modules")],
  define: { "import.meta.env": "{}" },
  logLevel: "warning",
});

/** 仓库里已提交的共享产物（也是 Office 版比对的来源）。 */
const committed = {
  vectors: path.join(here, "../Shared/test-vectors.json"),
  rules: path.join(here, "../Packages/CVLCore/Sources/CVLCore/Resources/term-rules.json"),
};

// --check 时写入临时目录，避免污染工作区。
const tmp = path.join(here, ".build/check");
const sharedOut = check ? path.join(tmp, "Shared") : path.dirname(committed.vectors);
const resourcesOut = check ? path.join(tmp, "Resources") : path.dirname(committed.rules);
if (check) {
  mkdirSync(sharedOut, { recursive: true });
  mkdirSync(resourcesOut, { recursive: true });
}

execFileSync("node", [outfile, sharedOut, resourcesOut], { stdio: "inherit" });

if (check) {
  const pairs = [
    ["test-vectors.json", path.join(sharedOut, "test-vectors.json"), committed.vectors],
    ["term-rules.json", path.join(resourcesOut, "term-rules.json"), committed.rules],
  ];
  const stale = pairs.filter(([, fresh, have]) => {
    try {
      return readFileSync(fresh, "utf8") !== readFileSync(have, "utf8");
    } catch {
      return true;
    }
  });
  if (stale.length > 0) {
    console.error(`共享产物已过期：${stale.map(([name]) => name).join("、")}。请重新运行 node scripts/export-shared.mjs。`);
    process.exit(1);
  }
  console.log("共享产物与扩展版一致。");
}
