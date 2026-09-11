# 知乎回答字数统计 | 阅读时间估算 — Manifest V3 扩展

本目录是 [zhihu-answer-metrics](../README.md) 的浏览器扩展发行版，用于提交 Microsoft Edge Add-ons / Chrome Web Store。

`content.js` 是同名 UserScript 的 MV3 移植，**功能未做任何改动**：只去掉了 UserScript 元数据头，
`@match` 迁移为 manifest 的 `content_scripts.matches`，`@grant none` 对应不声明任何权限。
UserScript 发行版由 `../tools/build-userscript.mjs` 从本目录的 `content.js` 生成，两者逐字节相同。

## 目录结构

```
extension/
├── manifest.json                  MV3 清单
├── content.js                     注入脚本（唯一真相源，扩展与 UserScript 共用）
├── icons/
│   ├── icon16.png  icon32.png  icon48.png  icon128.png   扩展内图标
│   ├── icon300.png                商店列表图标
│   └── icon-source.svg            等价矢量参考稿（PNG 为准）
├── demo/
│   ├── demo.html                  离线演示页（复刻知乎问题页 DOM 结构）
│   ├── verify.html                单文件自测页（直接加载 content.js，不依赖扩展加载）
│   ├── privacy.html               隐私政策页（商店必填）
│   └── README-审核验证.md          审核验证说明（认证备注用）
├── store/
│   ├── 商店文案.md                 名称/描述/搜索词/分类/权限理由/数据声明
│   └── 认证备注.md                 提交时填入 Certification notes 的文本
├── tools/
│   ├── render-icons.ps1           图标生成脚本（PowerShell 7，GDI+）
│   └── run-logic-check.js         DOM 桩逻辑比对脚本（Node，无依赖）
└── README.md
```

打包脚本在仓库根目录的 `../tools/pack.mjs`（Node）与 `../tools/pack.ps1`（PowerShell），
产出仓库根目录的 `store-package.zip`。原始 UserScript 存档在 `../userscript/original/`。

## 本地加载

1. 打开 `edge://extensions`，开启「开发人员模式」。
2. 「加载解压缩的扩展」，选择 `extension` 目录（含 `manifest.json` 的那一层）。
3. 打开 `https://www.zhihu.com/question/<任意问题 ID>`，约 1.2 秒后每条回答正文开头出现统计条。

## 功能一致性自测

```bash
node tools/run-logic-check.js                              # 测 content.js
node tools/run-logic-check.js ../userscript/original/zhihu-answer-metrics-4.2.user.js   # 测原稿
```

用最小 DOM 桩跑两种脚本，逐条比对注入的统计栏 HTML。两者输出必须完全一致：

```
[PASS] pure chinese: <strong>字数</strong>： 汉 36 · Eng 0 · Num 0 ｜ <strong>总</strong> 36 ｜ <strong>阅读</strong> ≈ 1 分钟
[PASS] mixed: 汉 2 · Eng 12 · Num 2 ｜ 总 16 ｜ 阅读 ≈ 1 分钟
[PASS] long: 汉 480 ｜ 总 480 ｜ 阅读 ≈ 2 分钟
[PASS] blank: blank answer skipped = true
RESULT: all checks passed
```

跨发行版一致性由仓库根目录的 `tools/build-userscript.mjs` 守：它会校验 `content.js`
的函数体与原稿逐字节相同，并校验生成出的 UserScript 与当前 `content.js` 同步。

## 重新生成图标

```powershell
pwsh -File tools/render-icons.ps1                          # 蓝底 + 白「字」（当前方案）
pwsh -File tools/render-icons.ps1 -Ring                    # 追加阅读进度圆环
pwsh -File tools/render-icons.ps1 -Design bars             # 切回柱状图版本
pwsh -File tools/render-icons.ps1 -Glyph '时' -Blue '#056DE8'
```

设计：圆角方块（半径 23%）+ 单个白色汉字，配色 `#056DE8`（知乎站内主蓝）。
16/32/48 px 由 1024 px 主图 bicubic 缩放，笔画在 32 px 仍可辨。
需要 Windows 上的 PowerShell 7（FullLanguage，可 `Add-Type -AssemblyName System.Drawing`）。
`icons/icon-source.svg` 是等价矢量参考稿，字体依赖渲染环境，**以 PNG 为准**。

## 打包上架

```bash
node ../tools/pack.mjs            # 推荐，仅需 Node
pwsh -File ../tools/pack.ps1      # 等价实现，仅需 PowerShell 7
```

两者都产出仓库根目录的 `store-package.zip`：仅含 `manifest.json`、`content.js`、
`icons/icon16|32|48|128.png`。`demo/`、`store/`、`tools/` 不入包，避免审核误判与体积浪费。

## 上架前仍需人工补齐

- **支持邮箱 / 支持网页**：在 Partner Center 的 Properties 页填写，仓库里无法代填。
  建议填 `https://github.com/chloeeee72/zhihu-answer-metrics/issues`。
- **商店截图**：至少 1 张，1280×800 或 640×400。用真实知乎问题页截图，需能看清统计条。
- **隐私政策 URL**：规范文件是 `../docs/privacy.html`，经 GitHub Pages 发布后填：

  ```
  https://chloeeee72.github.io/zhihu-answer-metrics/privacy.html
  ```

  Pages 的 Source 要设为 `main` 分支的 `/docs` 目录。本目录下的 `demo/privacy.html`
  只是由 `../tools/pack.mjs` 生成的重定向壳，不要编辑它。
  若隐私政策选「本扩展不收集任何数据」，也可只做声明不填 URL。
- **开发者身份验证**：Partner Center 账号需完成邮箱/身份验证，审核通过后才可提交。

## 版本号

`manifest.json` 的 `version` 为 `4.3.0`，是唯一版本来源；UserScript 的 `@version`
由 `../tools/build-userscript.mjs` 同步生成。商店要求点分数字、每段 0–65535，
因此扩展用三段式 `4.3.0`，而不是脚本头的 `4.3`。升版时改这里再跑一次生成脚本。
