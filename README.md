# zhihu-answer-metrics

Word count and reading time for every answer on a Zhihu question page.

A third-party, unofficial browser extension (Manifest V3) and UserScript. No permissions,
no network requests, no data collection.

知乎问题页阅读辅助工具：在每条回答的正文开头插入一条只读统计栏，显示汉字数、英文单词数、
数字个数、总字数与预计阅读时间。同一套逻辑提供两种发行方式 —— 浏览器扩展与 UserScript。

> **非官方声明**：本项目是第三方工具，与知乎（北京智者天下科技有限公司）无任何关联，
> 未获其授权、赞助或背书。「知乎」字样仅用于说明本工具的适用网站。

---

## 功能

在 `https://www.zhihu.com/question/*` 的每条回答正文开头显示：

```
字数： 汉 1240 · Eng 36 · Num 12 ｜ 总 1288 ｜ 阅读 ≈ 5 分钟
```

- 汉字数、英文单词数、数字个数分别统计后求和
- 预计阅读时间：汉字按 300 字/分钟、英文按 200 词/分钟折算，向上取整，最小 1 分钟
- 向下滚动、点「查看全部回答」等动态加载出来的回答会自动补上统计栏
- 统计栏为纯展示元素（`pointer-events: none`），不拦截点击、不修改回答内容

## 两种发行方式

| | 浏览器扩展（MV3） | UserScript |
| --- | --- | --- |
| 适用 | Edge / Chrome / 其他 Chromium 内核浏览器 | 装了 Tampermonkey / Violentmonkey 的任意浏览器 |
| 文件 | `extension/` | `userscript/zhihu-answer-metrics.user.js` |
| 安装 | 商店（待上架）或「加载解压缩的扩展」 | 打开 raw 文件，脚本管理器会提示安装 |
| 权限 | 不声明任何 `permissions` / `host_permissions` | `@grant none` |

两种发行方式的统计与注入逻辑**逐字节相同**，由 `tools/build-userscript.mjs`
从 `extension/content.js` 生成 UserScript，CI 会校验两者不漂移。

### 安装扩展（开发版）

1. 打开 `edge://extensions` 或 `chrome://extensions`，开启「开发人员模式」
2. 「加载解压缩的扩展」，选择本仓库的 `extension/` 目录
3. 打开任意知乎问题页，约 1.2 秒后统计栏出现

### 安装 UserScript

安装 [Tampermonkey](https://www.tampermonkey.net/) 后打开：

```
https://raw.githubusercontent.com/chloeeee72/zhihu-answer-metrics/main/userscript/zhihu-answer-metrics.user.js
```

脚本头里的 `@namespace`、`@downloadURL`、`@updateURL` 都指向本仓库，安装后脚本管理器
可自动检查更新（跟本仓库 `main` 分支同步）。

## 隐私

- 不声明任何浏览器权限（扩展）／`@grant none`（UserScript）
- 不发起任何网络请求，不加载远程代码，不使用 `eval`
- 不读取、不存储、不上传任何用户数据；统计全部在页面本地内存中完成，关闭页面即丢弃
- 无 Cookie、无 localStorage、无遥测

扩展商店所需的隐私政策页：`extension/demo/privacy.html`。

## 目录结构

```
.
├── extension/                       浏览器扩展（Manifest V3）
│   ├── manifest.json
│   ├── content.js                   注入脚本（唯一真相源）
│   ├── icons/                       16/32/48/128 + 商店 300 + SVG 参考稿
│   ├── demo/                        离线演示页、自测页、隐私政策、审核验证说明
│   ├── store/                       商店文案与认证备注
│   └── tools/                       图标生成、逻辑比对
├── userscript/
│   ├── zhihu-answer-metrics.user.js 生成文件，勿手改
│   └── original/                    原始 UserScript 存档，供溯源比对
├── tools/
│   ├── build-userscript.mjs         content.js -> UserScript
│   └── pack.mjs                     打包 store-package.zip
├── docs/                            GitHub Pages 站点
│   ├── index.html                   索引页
│   ├── privacy.html                 隐私政策规范版（商店 Privacy 页用）
│   └── 仓库与发布清单.md              发布操作手册
└── .github/workflows/release.yml   打 tag 自动发包
```

## 开发

无需 `npm install`，只用 Node 内置模块与 PowerShell 7。

```bash
node tools/build-userscript.mjs            # 生成 UserScript
node tools/build-userscript.mjs --check    # 校验生成物是否最新（CI 用）
node extension/tools/run-logic-check.js    # DOM 桩逻辑比对，扩展 vs 原 UserScript
node tools/pack.mjs                        # 打包，并刷新 demo/privacy.html 重定向壳
node tools/pack.mjs --check                # 校验上面那个壳没有过期（CI 用）
```

图标重新生成（Windows + PowerShell 7）：

```powershell
pwsh -File extension/tools/render-icons.ps1              # 蓝底圆角方块 + 白色「字」
pwsh -File extension/tools/render-icons.ps1 -Ring        # 追加阅读进度圆环
pwsh -File extension/tools/render-icons.ps1 -Design bars # 柱状图版本
```

`extension/tools/run-logic-check.js` 会用最小 DOM 桩跑 `content.js` 与
`userscript/original/` 里的原稿，逐条比对注入的统计栏 HTML，两者输出必须完全一致。
`tools/build-userscript.mjs` 另有溯源校验：一旦 `content.js` 的函数体与原稿不一致就报错，
避免移植过程中悄悄改掉行为。

## 发布

推 `v*` tag 触发 `.github/workflows/release.yml`：跑校验、打 zip、生成 UserScript、
把 `store-package.zip` 与 `.user.js` 一起挂到 GitHub Release。

```bash
# 改 extension/manifest.json 的 version，然后
node tools/build-userscript.mjs
git commit -am "chore: bump to 4.4.0"
git tag v4.4.0 && git push origin main --tags
```

版本号口径：`extension/manifest.json` 的 `version` 为唯一来源，UserScript 的 `@version`
由生成脚本同步。商店要求点分数字，因此扩展用 `4.3.0` 三段式。

## 已知限制

- 只在知乎问题页生效，首页、专栏、视频页不注入
- 未登录访问知乎问题页会弹登录弹窗，这是知乎自身行为，与本工具无关，关闭即可
- 统计基于正文可见文本，折叠区域内的文本按页面渲染结果计算
- 阅读时间是按固定速率的粗略估算，仅供参考

## License

[MIT](LICENSE)
