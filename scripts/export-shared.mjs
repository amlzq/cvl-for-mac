// 从浏览器扩展版仓库导出词典、词表和测试向量到 Shared/。
// 用法：node scripts/export-shared.mjs [扩展版仓库路径]
import { build } from "../../chinese-variants-linter/node_modules/esbuild/lib/main.js";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const ext = path.resolve(process.argv[2] ?? path.join(here, "../../chinese-variants-linter"));
const outfile = path.join(here, ".build/export-shared.cjs");
await build({
  entryPoints: [path.join(here, "export-shared.entry.ts")],
  bundle: true, platform: "node", format: "cjs", outfile,
  nodePaths: [path.join(ext, "node_modules")],
  define: { "import.meta.env": "{}" },
  logLevel: "warning",
});
execFileSync("node", [outfile, path.join(here, "../Shared"), path.join(here, "../Packages/CVLCore/Sources/CVLCore/Resources")], { stdio: "inherit" });
