// 由 scripts/export-shared.mjs 用 esbuild 打包后运行。从浏览器扩展版仓库导出共享数据。
import { writeFileSync, mkdirSync } from "node:fs";
import * as OpenCC from "opencc-js";
import { TERM_RULES } from "../../chinese-variants-linter/src/assets/rules";
import { detectText } from "../../chinese-variants-linter/src/core/detect";
import { DEFAULT_SETTINGS, mergeSettings } from "../../chinese-variants-linter/src/core/storage";

const out = process.argv[2]!;
const data = process.argv[3]!; // CVLCore 的 Resources 目录
mkdirSync(`${data}/opencc`, { recursive: true });

type Dict = string | [string, string][];
function entries(d: Dict): [string, string][] {
  if (typeof d !== "string") return d;
  return d.split("|").filter(Boolean).map((e) => {
    const [a = "", b = ""] = e.split(" ");
    return [a, b];
  });
}

const { Locale } = OpenCC as any;
const groups: Record<string, Dict[]> = {
  from_tw: Locale.from.tw[0],
  from_hk: Locale.from.hk[0],
  from_cn: Locale.from.cn[0],
  to_cn: Locale.to.cn[0],
  to_tw: Locale.to.tw[0],
  to_hk: Locale.to.hk[0],
};
for (const [name, group] of Object.entries(groups)) {
  if (group.length !== 2) throw new Error(`${name}: 预期 [词组, 单字] 两个字典，实际 ${group.length}`);
  group.forEach((d, i) => {
    const file = `${data}/opencc/${name}.${i === 0 ? "phrases" : "chars"}.txt`;
    writeFileSync(file, entries(d).map(([a, b]) => `${a}\t${b}`).join("\n") + "\n");
  });
}

writeFileSync(`${data}/term-rules.json`, JSON.stringify(TERM_RULES, null, 1) + "\n");

// ---- 测试向量 ----
const texts = [
  "这个软件默认支持上传。",
  "软件默认很好用。",
  "這個軟體預設支援上傳。",
  "請使用滑鼠點選連結並下載影片。",
  "服务器上的视频文件需要通过鼠标点击链接下载。",
  "皇后在后面，面条很好吃，面子很重要。",
  "干擾里長若干人，頭髮發展。",
  "他发现了发财的办法，头发很长。",
  "出租车、公交车和自行车都停在幼儿园门口。",
  "新西兰、澳大利亚和意大利的人工智能发展很快。",
  "我的笔记本电脑和智能手机都有高清屏幕。",
  "台灣的台北有很多好吃的。",
  "用户使用户外设备。",
  "程序员在云计算平台上写博客。",
  "社交媒体上的短信和激光笔。",
  "Hello 世界 mixed English text 123 软件 and 軟體.",
  "  \n\t ",
  "",
  "😀软件😀𠀀视频",
  "鼠标，键盘，显示器，内存，硬盘",
  "菠萝和西红柿，方便面，空调。",
  "悉尼的巴士和的士。",
  "這個程式設計師在雲端運算上寫部落格。",
  "裡面的麵包和麪條，後面的皇后。",
  "著名的网络协议与信息安全。",
  "「引号」和《书名》，标点！",
  "㐷㐹 罕见字 兀 𪚥",
  "软软软软软件件件",
];
const settingsCases: Array<[string, any]> = [];
for (const v of ["zh-CN", "zh-TW", "zh-HK", "zh-Hant"]) {
  for (const level of ["standard", "relaxed"]) {
    settingsCases.push([`${v}/${level}`, { defaultVariant: v, detectionLevel: level }]);
  }
}
settingsCases.push(["tw/allow", { defaultVariant: "zh-TW", userDictionary: { allowPhrases: { "zh-TW": ["软件", "里長"] } } }]);
settingsCases.push(["tw/allow-char", { defaultVariant: "zh-TW", userDictionary: { allowPhrases: { "zh-TW": ["默认支持"] } } }]);
settingsCases.push(["tw/user-phrase", { defaultVariant: "zh-TW", userDictionary: { phrases: { "zh-TW": [
  { id: "custom-software", from: "软件", to: "軟件", enabled: true },
  { id: "custom-off", from: "视频", to: "視訊", enabled: false },
  { id: "custom-mouse", from: "鼠标", to: "滑鼠器", enabled: true },
] } } }]);
settingsCases.push(["cn/user-phrase", { defaultVariant: "zh-CN", userDictionary: { phrases: { "zh-CN": [
  { id: "p1", from: "軟體", to: "软件", enabled: true },
] } } }]);

const vectors: any[] = [];
for (const [name, patch] of settingsCases) {
  const settings = mergeSettings(DEFAULT_SETTINGS, patch);
  for (const text of texts) {
    const issues = detectText({ text, settings });
    vectors.push({
      name: `${name} :: ${JSON.stringify(text).slice(0, 30)}`,
      text,
      settings: { defaultVariant: patch.defaultVariant, detectionLevel: patch.detectionLevel ?? "standard", userDictionary: patch.userDictionary ?? null },
      expected: issues.map((i) => ({
        id: i.id, type: i.type, subtype: i.subtype, sourceText: i.sourceText,
        start: i.start, end: i.end, confidence: i.confidence, ruleId: i.ruleId,
        suggestion: i.suggestions[0]?.value ?? null,
      })),
    });
  }
}
writeFileSync(`${out}/test-vectors.json`, JSON.stringify(vectors, null, 1) + "\n");
console.log(`导出完成：${vectors.length} 条向量，${TERM_RULES.length} 条词汇规则`);
