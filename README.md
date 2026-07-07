# Claude Desktop 简体中文语言包

为 Claude Desktop (Windows) 提供简体中文界面翻译。

> **关于版本更新的一点说明**
>
> Claude Desktop 更新频繁，我无法保证每个小版本都及时跟进。部分小版本因为个人原因没有单独制作翻译文件，但**这并不影响使用**——脚本会自动匹配最接近的翻译版本。即使翻译文件比当前 Claude 版本旧，绝大多数界面文案也都能正常显示中文，因为相邻版本之间的翻译内容变化通常很小。
>
> 还有一部分键没有翻译，它们是品牌名（如 Claude、Anthropic、Google）、技术术语（如 API、CLI、SSO）和格式占位符（如 `{count}`、`{size} KB`）等，这些本身就不应该翻译，不影响语言包的正常使用。
>
> 如果你遇到明显缺失翻译的界面，欢迎到 [Issues](https://github.com/ICERainbow666/claude-desktop-zh-cn/issues) 反馈。

## 支持的版本

脚本会自动识别已安装的 Claude Desktop 版本，并按「精确匹配 → 最近旧版 → 最近新版」的顺序选择翻译文件。

| 翻译版本 | 项目更新日期 | ion-dist | desktop-shell | dynamic |
|---------|------|----------|---------------|---------|
| **1.18286.2.0** | 2026-07-07 | 18,363 键 | 435 键 | 50 键 |
| 1.17377.1.0 | 2026-07-02 | 18,043 键 | 435 键 | 46 键 |
| 1.15962.1.0 | 2026-06-29 | 17,316 键 | 430 键 | 46 键 |
| 1.15200.0.0 | 2026-06-25 | 16,980 键 | 428 键 | 46 键 |
| 1.14271.0.0 | 2026-06-19 | 16,625 键 | 424 键 | 46 键 |
| 1.13576.0.0 | 2026-06-17 | 16,500 键 | 428 键 | 46 键 |
| 1.12603.1.0 | 2026-06-16 | 16,178 键 | 425 键 | 69 键 |

如果你的 Claude 版本高于上表最新版本，脚本会自动使用最近的翻译并提示适配情况。运行时「精确匹配」会显示为绿色；若使用了不同版本的翻译，会用黄色框标注当前版本与实际翻译版本，提示可能存在少量适配差异。

### 如何查看你的 Claude Desktop 版本

在 Claude Desktop 中，点击左上角头像 → **Settings** → 滚动到底部，版本号会显示在页面底部。

或者在 PowerShell 中运行：

```powershell
Get-AppxPackage -Name Claude | Select-Object Version
```

如果你的版本不在上表中，可以：
1. 到 [Issues](https://github.com/ICERainbow666/claude-desktop-zh-cn/issues) 反馈，附上版本号
2. 让 AI Agent（如 Claude Code）帮你扫描 JS 文件，找出硬编码字符串并提交 PR

### 关于硬编码字符串

Claude Desktop 的 JS 中曾有一些 UI 字符串绕过了 i18n 翻译系统。**随着版本更新，Anthropic 已经将大部分硬编码字符串移入了 i18n**：

- v1.12603.1.0：20+ 个硬编码模式需要 JS 补丁替换
- v1.13576.0.0：仅剩 2-3 个硬编码模式
- v1.15200.0.0 及以后：硬编码已基本移入 i18n，无需 JS 补丁

脚本会根据 Claude Desktop 版本自动判断是否需要硬编码补丁。新版本（≥ 1.14271.0.0）仅安装语言包即可；旧版本会额外处理硬编码字符串。

## 安装方法

双击 `ClaudeChineseLangPack.bat`，以**管理员身份**运行。

```
Claude Desktop Chinese Language Pack

  1. Install Language Pack
  2. Uninstall Language Pack
  0. Exit
```

| 选项 | 说明 |
|------|------|
| **1. 安装语言包** | 安装翻译 JSON、注册 zh-CN，并按版本自动决定是否替换硬编码英文 |
| **2. 卸载语言包** | 删除翻译文件，还原 JS，locale 回退 en-US，并按版本自动还原硬编码字符串 |

脚本会自动关闭 Claude Desktop、执行操作、再重启 Claude Desktop。运行完成后会停留在输出界面，按任意键才返回主菜单，方便查看是否有报错。

### 前提

- Windows 10 / 11
- 已安装 [Claude Desktop](https://claude.ai/download)
- 管理员权限（脚本会自动请求）

### 命令行用法（PowerShell）

```powershell
# 完整安装（自动识别版本）
powershell -ExecutionPolicy Bypass -File .\LanguagePack.ps1

# 仅安装语言包
powershell -ExecutionPolicy Bypass -File .\LanguagePack.ps1 -TranslationOnly

# 卸载
powershell -ExecutionPolicy Bypass -File .\LanguagePack.ps1 -Uninstall
```

## 工作原理

1. **翻译 JSON 文件** — 将 `translated-zh-CN/{版本}/` 下的 3 个 JSON 复制到 Claude 的 `resources` 目录，Claude 的 i18n 系统通过 `fetch('/i18n/{locale}.json')` 加载翻译。
2. **注册 zh-CN 语言** — 在 JS 打包文件中补丁语言列表，添加 `"zh-CN"`，使 Claude 设置页面出现中文选项。
3. **替换硬编码字符串**（仅旧版本）— 旧版 Claude 的部分 UI 字符串硬编码在 JS 中，脚本通过直接查找替换将英文改为中文，并在替换前备份原始 JS 文件，卸载时自动恢复。
4. **清理 Electron 缓存** — 安装/卸载后清理 Code Cache 等运行时缓存，确保 JS 补丁立即生效。

## 目录结构

```
├── ClaudeChineseLangPack.bat           # 统一入口（安装/卸载）
├── LanguagePack.ps1                    # 安装/卸载主脚本（自动匹配版本）
├── translated-zh-CN/                   # 翻译文件（按版本分目录）
│   ├── 1.18286.2.0/                    # 最新版
│   │   ├── ion-dist/zh-CN.json
│   │   ├── desktop-shell/zh-CN.json
│   │   └── dynamic/zh-CN.json
│   ├── ...                             # 历史版本
│   └── ion-dist/en-US.json             # 英文源文件（供参考）
└── README.md
```

## 贡献：报告尚未翻译的英文

安装语言包后，如果界面上仍然有**大段英文**（不是品牌名或术语），欢迎反馈！

请提供：
1. **英文内容**（截图或文字）
2. **出现位置**（侧栏、设置页、对话页、弹窗等）
3. **触发方式**（启动时就有 / 点击某个按钮后出现）

### 这些情况不需要报告

| 类型 | 示例 | 原因 |
|------|------|------|
| 品牌名 | Google Play、Python、Sonnet、Surface、Claude | 产品/技术品牌，全球统一 |
| 技术术语 | CI、CSV、CLI、USB、GHE、API、SSO | 行业通用缩写，无对应中文 |
| 格式占位符 | `{size} KB`、`{percent}%`、`v{version}` | 程序模板变量，翻译会破坏格式 |
| URL / 路径 | `~/Documents/work`、`https://...` | 系统路径或链接 |
| Electron 原生菜单 | "Enable Main Process Debugger"、"Record Performance Trace" | 内置在 Electron 框架中，JS 层面无法修改 |

AI Agent 也可以扫描 Claude Desktop 的 JS 文件，找出硬编码的英文字符串，直接提交替换方案到 `LanguagePack.ps1`。

## 常见问题

**安装后界面没变中文？**
- 确认 Claude Desktop 已完全重启（任务管理器中结束所有 claude 进程后重新打开）
- 检查 Claude 设置中语言是否已切换为中文
- 脚本会自动清理 Electron 缓存，若仍无效可手动结束所有 claude 进程后重试

**脚本报权限错误？**
- 脚本会自动请求管理员权限，若被系统拦截请手动允许
- WindowsApps 目录受系统保护，需要管理员权限才能写入

**Claude 更新后中文消失？**
- Claude 更新会覆盖 resources 目录，重新运行安装脚本即可
- 新版本若未单独制作翻译，脚本会自动使用最近的翻译版本

**安装提示「未匹配到语言列表」？**
- 这是正常现象，表示某个 JS 文件格式不同被跳过，不影响安装

## 许可

[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0)

仅供个人学习使用。Claude Desktop 是 Anthropic 的产品，本项目与 Anthropic 无关。

## 致谢

- 简体中文包原型：[RICK @ Linux Do](https://linux.do/t/topic/2040184)
- [Linux Do 社区](https://linux.do/)
