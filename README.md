# Claude Desktop 简体中文语言包

为 Claude Desktop (Windows) 提供简体中文界面翻译。

## 支持的版本

| Claude Desktop 版本 | 状态 | 备注 |
|---------------------|------|------|
| **1.13576.x** | 当前最新版 | 推荐，大部分硬编码已移入 i18n |
| **1.12603.x** | 支持 | 旧版 |

小版本更新（如 1.13576.0.0 → 1.13576.1.0）通常翻译内容不变，脚本会自动使用最接近的翻译版本。安装后会提示实际使用的翻译版本，如有适配问题请到 [Issues](https://github.com/ICERainbow666/claude-desktop-zh-cn/issues) 反馈。

### 如何查看你的 Claude Desktop 版本

在 Claude Desktop 中，点击左上角头像 → **Settings** → 滚动到底部，版本号会显示在页面底部。

或者在 PowerShell 中运行：

```powershell
Get-AppxPackage -Name Claude | Select-Object Version
```

如果你的版本不在上面的列表中，可以：
1. 到 [Issues](https://github.com/ICERainbow666/claude-desktop-zh-cn/issues) 反馈，附上版本号
2. 让 AI Agent（如 Claude Code）帮你扫描 JS 文件，找出硬编码字符串并提交 PR

### 关于硬编码字符串

Claude Desktop 的 JS 中有一些 UI 字符串绕过了 i18n 翻译系统。**随着版本更新，Anthropic 已经将大部分硬编码字符串移入了 i18n**：
- v1.12603.1.0：20+ 个硬编码模式需要 JS 补丁替换
- v1.13576.0.0：仅剩 2-3 个硬编码模式

因此**新版本推荐使用选项 2（仅语言包）**，旧版本建议使用选项 1（完整安装）。

## 安装方法

双击 `ClaudeChineseLangPack.bat`，以**管理员身份**运行。

**第一步：选择 Claude Desktop 版本**

```
Supported versions:
  1. 1.13576.0.0 (latest)
  2. 1.12603.1.0
  0. Exit
```

**第二步：选择操作**

```
  1. Full Install (Translation + JS Patch)   ← 推荐
  2. Language Pack Only (Translation Only)
  3. Uninstall Language Pack
  0. Back
```

| 选项 | 说明 |
|------|------|
| **1. 完整安装** | 翻译 JSON + 替换 JS 中硬编码英文 → **推荐** |
| **2. 仅安装语言包** | 仅替换翻译 JSON，不修改 JS |
| **3. 卸载语言包** | 删除翻译文件，还原 JS，locale 回退 en-US |

脚本会自动关闭 Claude Desktop、执行操作、再重启 Claude Desktop。

运行完成后会停留在输出界面，按任意键才返回主菜单，方便查看是否有报错。

### 前提

- Windows 10 / 11
- 已安装 [Claude Desktop](https://claude.ai/download)
- 管理员权限（脚本会自动请求）

### 命令行用法（PowerShell）

```powershell
# 完整安装（自动检测版本）
powershell -ExecutionPolicy Bypass -File .\LanguagePack.ps1

# 指定版本安装
powershell -ExecutionPolicy Bypass -File .\LanguagePack.ps1 -Version "1.13576.0.0"

# 仅安装语言包
powershell -ExecutionPolicy Bypass -File .\LanguagePack.ps1 -TranslationOnly

# 卸载
powershell -ExecutionPolicy Bypass -File .\LanguagePack.ps1 -Uninstall
```

## 覆盖范围

**v1.13576.0.0（最新）**

| 模块 | 已翻译 | 未翻译 | 说明 |
|------|--------|--------|------|
| ion-dist | 16,224 | 276 | 主界面，剩余为品牌名/格式字符串 |
| desktop-shell | 428 | 0 | 桌面外壳 |
| dynamic | 46 | 0 | 动态内容，全部完成 |

**v1.12603.1.0**

| 模块 | 已翻译 | 未翻译 | 说明 |
|------|--------|--------|------|
| ion-dist | 15,892 | 264 | 主界面，剩余为品牌名/格式字符串 |
| desktop-shell | 420 | 5 | 桌面外壳 |
| dynamic | 69 | 0 | 动态内容，全部完成 |

**未翻译的键**均为不应翻译的内容：
- 品牌名：Google Play、Python、Surface、Sonnet、Claude、Anthropic、Microsoft 365 等
- 技术术语：CI、CSV、CLI、USB、GHE 等
- 格式字符串：`{size} KB`、`{percent}%`、`v{version}` 等
- URL / 路径占位符：`~/Documents/work`、`https://...` 等

## 工作原理

### 1. 翻译 JSON 文件

将 `translated-zh-CN/{版本}/` 下的 3 个 JSON 文件复制到 Claude Desktop 的 `resources` 目录，Claude 的 i18n 系统通过 `fetch('/i18n/{locale}.json')` 加载翻译。

### 2. 注册 zh-CN 语言

在 JS 打包文件中补丁语言列表，添加 `"zh-CN"`，使 Claude 设置页面出现中文选项。

### 3. 替换硬编码字符串

Claude Desktop 的部分 UI 字符串硬编码在 JS 中，绕过了 i18n 系统。脚本通过直接查找替换将英文改为中文，并在替换前备份原始 JS 文件。卸载时自动从备份恢复。

## 目录结构

```
├── ClaudeChineseLangPack.bat           # 统一入口（先选版本再选操作）
├── LanguagePack.ps1                    # 安装/卸载主脚本（-Version 参数指定版本）
├── translated-zh-CN/                   # 翻译文件（按版本分目录）
│   ├── 1.13576.0.0/                    # 最新版
│   │   ├── ion-dist/zh-CN.json
│   │   ├── desktop-shell/zh-CN.json
│   │   └── dynamic/zh-CN.json
│   ├── 1.12603.1.0/                    # 旧版
│   │   ├── ion-dist/zh-CN.json
│   │   ├── desktop-shell/zh-CN.json
│   │   └── dynamic/zh-CN.json
│   └── ion-dist/en-US.json             # 英文源文件（供参考）
└── README.md
```

## 贡献：报告尚未翻译的英文

安装语言包后，如果界面上仍然有英文，欢迎反馈！

请提供以下信息：
1. **英文内容**（截图或文字）
2. **出现位置**（侧栏、设置页、对话页、弹窗等）
3. **触发方式**（启动时就有 / 点击某个按钮后出现）

可以通过 Issue 或直接提交 PR。

### 可以硬编码翻译的字符串

以下类型的英文可以通过修改 JS 文件来翻译：
- UI 按钮文字：如 "New session"、"Sign in"
- 提示文案：如 "No tasks yet."、"Try again"
- 标签页文字：如 "Recents"、"Shared"
- 空状态提示：如 "No active tasks."、"No archived tasks."
- 任何看起来是**普通英文句子或短语**、对用户有实际语义的内容

### 不能硬编码翻译的内容

以下内容**不适用**硬编码替换，不需要报告：

| 类型 | 示例 | 原因 |
|------|------|------|
| 品牌名 | Google Play、Python、Sonnet、Surface、Claude | 产品/技术品牌，全球统一 |
| 技术术语 | CI、CSV、CLI、USB、GHE | 行业通用缩写，无对应中文 |
| 格式占位符 | `{size} KB`、`{percent}%`、`v{version}` | 程序模板变量，翻译会破坏格式 |
| URL / 路径 | `~/Documents/work`、`https://...` | 系统路径或链接 |
| Electron 原生菜单 | "Enable Main Process Debugger"、"Record Performance Trace" | 内置在 Electron 框架二进制文件中，JS 层面无法修改 |
| 属性/变量名 | `defaultMessage`、`children`、`baseDescription` | 代码字段名，非用户可见文本 |

### 反馈格式（建议）

```
位置：侧栏底部
英文：Switch workspace
触发：始终可见
```

或直接在 Issue 中贴上截图，标注未翻译的位置即可。

AI Agent 也可以扫描 Claude Desktop 的 JS 文件，找出硬编码的英文字符串，报告给维护者或直接提交替换方案到 `LanguagePack.ps1` 中的 `$replacements` 数组。

## 常见问题

**安装后界面没变中文？**
- 确认 Claude Desktop 已完全重启（任务管理器中结束所有 claude 进程后重新打开）
- 检查 Claude 设置中语言是否已切换为中文

**脚本报权限错误？**
- 脚本会自动请求管理员权限，若被系统拦截请手动允许
- WindowsApps 目录受系统保护，需要管理员权限才能写入

**版本不匹配报错？**
- 语言包针对特定 Claude Desktop 版本制作，版本不一致时会停止并提示
- 更新 Claude Desktop 后需下载对应版本的语言包

**Claude 更新后中文消失？**
- Claude 更新会覆盖 resources 目录，需要重新运行安装脚本

## 许可

[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0)

仅供个人学习使用。Claude Desktop 是 Anthropic 的产品，本项目与 Anthropic 无关。

## 致谢

- 简体中文包原型：[RICK @ Linux Do](https://linux.do/t/topic/2040184)
- [Linux Do 社区](https://linux.do/)
