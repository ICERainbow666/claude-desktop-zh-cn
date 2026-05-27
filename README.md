# Claude Desktop 简体中文语言包

> **只需把这个仓库丢给 AI Agent，它就能帮你完成安装。**
>
> Agent 执行 `ClaudeChineseLangPack.bat` 选择「完整安装」即可。

为 Claude Desktop (Windows) 提供简体中文界面翻译。

覆盖 ion-dist（15,996 条）、desktop-shell（374 条）、statsig（46 条）三个模块。

> **⚠️ 已知限制：** Claude Desktop 的 JS 中存在部分硬编码英文 UI 字符串（如侧栏的 "New session"、"New chat"、"New task" 等），这些字符串绕过了 i18n 翻译系统。由于 Electron 的 V8 代码缓存机制，直接修改 JS 源文件**无法生效**——即使文件在磁盘上已被修改，Electron 仍会加载缓存的旧版本字节码。因此这些硬编码英文暂时无法通过本语言包翻译。详见 [已知问题](#已知问题硬编码英文-ui-字符串)。

## 前提

- Windows 10 / 11
- 已安装 [Claude Desktop](https://claude.ai/download)
- Node.js（仅选项 1 需要，用于尝试修补硬编码字符串，但目前无法生效，推荐使用选项 2）

## 使用方法

双击 `ClaudeChineseLangPack.bat`，按提示选择：

```
1. 完整安装（翻译 + JS 补丁）
2. 仅安装语言包          ← 推荐
3. 卸载语言包
4. 还原所有
```

| 选项 | 说明 |
|------|------|
| **1. 完整安装** | 替换翻译 JSON + 修补 JS 中硬编码的英文字符串（⚠️ 由于 Electron 缓存机制，JS 补丁可能无法生效） |
| **2. 仅安装语言包** | 只替换翻译 JSON 文件，不修改 JS  ← **推荐使用** |
| **3. 卸载语言包** | 删除翻译文件，恢复语言注册，locale 回退到 en-US |
| **4. 还原所有** | 卸载语言包 + 还原 JS 文件到原始状态 |

脚本会自动关闭 Claude Desktop、执行操作、再重启 Claude Desktop。

### 命令行用法（PowerShell）

```powershell
# 安装语言包（需管理员权限）
powershell -ExecutionPolicy Bypass -File .\LanguagePack.ps1

# 卸载
powershell -ExecutionPolicy Bypass -File .\LanguagePack.ps1 -Uninstall

# 修补硬编码英文字符串
node .\patch-hardcoded-strings.js

# 还原 JS 补丁
node .\restore-hardcoded-strings.js
```

## 工作原理

### 语言包安装

1. **写入翻译文件** — 将 `translated-zh-CN/` 下的 JSON 复制到 Claude 的 resources 目录
2. **注册 zh-CN 语言** — 在 JS 中补丁语言列表，添加 `"zh-CN"`
3. **切换配置** — 将 `config.json` 中 `locale` 设为 `"zh-CN"`

### 硬编码字符串修补（⚠️ 目前无法生效）

Claude Desktop 的 JS 中有一部分 UI 字符串绕过了 i18n 系统（如侧栏的 "New session"、"New chat"、"New task"，以及 "Try again"、"Create with Claude" 等）。`patch-hardcoded-strings.js` 尝试将这些硬编码英文替换为中文，但由于 Electron 的 V8 代码缓存机制，修改后的 JS 文件无法被 Electron 加载，因此**此补丁目前无法生效**。详见下方已知问题。

## 目录结构

```
├── ClaudeChineseLangPack.bat         # 统一入口（菜单选择）
├── LanguagePack.ps1                  # 安装/卸载主脚本
├── patch-hardcoded-strings.js        # 修补 JS 中硬编码英文
├── restore-hardcoded-strings.js      # 还原 JS 补丁
├── translated-zh-CN/                 # 翻译文件
│   ├── ion-dist/zh-CN.json           # 主界面 (15,996 条)
│   ├── desktop-shell/zh-CN.json      # 桌面外壳 (374 条)
│   └── statsig/zh-CN.json            # 功能开关 (46 条)
├── NOTICE
└── README.md
```

## 常见问题

**安装后界面没变中文？**
- 确认 Claude Desktop 已完全重启（任务管理器中结束所有 claude 进程后重新打开）
- 检查 Claude 设置中语言是否已切换为中文

**脚本报权限错误？**
- 脚本会自动请求管理员权限，若被系统拦截请手动允许
- WindowsApps 目录受系统保护，需要管理员权限才能写入

**Claude 更新后中文消失？**
- Claude 更新会覆盖 resources 目录，需要重新运行安装脚本
- 选项 1（完整安装）会自动处理新版 JS 的语言列表补丁

**硬编码补丁丢失？**
- Claude 更新会覆盖 JS 文件，需重新运行选项 1 或单独执行 `node patch-hardcoded-strings.js`

## 已知问题：硬编码英文 UI 字符串

Claude Desktop 中存在部分英文 UI 字符串无法通过本语言包翻译，具体表现为以下位置仍显示英文：

| 位置 | 英文文本 | 说明 |
|------|---------|------|
| 侧栏新建按钮 | "New task" / "New chat" | 取决于当前模式（协作/聊天） |
| 任务列表空状态 | "No tasks yet." / "No active tasks." | 各标签页的空列表提示 |
| 任务标签页 | "Recents" / "Active" / "Archived" | 顶部筛选标签 |
| 命令面板 | "New task" / "New chat" | 快捷命令描述 |
| 错误提示 | "Try again" | 操作失败时的提示 |
| 登录页 | "Sign in to continue" | 登录页面标题 |

### 原因

这些字符串硬编码在 Claude Desktop 的 JS 打包文件（`ion-dist/assets/v1/index-*.js`）中，没有走 i18n 翻译系统。虽然可以通过直接修改 JS 文件将英文替换为中文（磁盘上的文件确实会被修改），但由于 **Electron 的 V8 代码缓存机制**，应用启动时会加载之前编译好的字节码缓存，而不会重新读取修改后的 JS 源文件，因此修改无法生效。

已尝试的解决方案（均无效）：
- 清除 Electron Code Cache 目录 → 导致应用崩溃
- 在 Claude Desktop 未运行时修改 JS 文件 → 重启后仍显示英文
- 重启电脑后重新打开 → 仍然无效

### 可能的解决方向

1. **等待 Anthropic 官方支持** — 这些字符串应该通过 i18n 系统暴露翻译 key，目前它们没有 i18n key
2. **Electron 启动参数** — 可能存在禁用 V8 代码缓存的启动参数，但会影响性能
3. **修改 asar 包** — 使用 `@electron/asar` 工具直接修改打包后的资源，绕过文件系统缓存

## 许可

[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0)

仅供个人学习使用。Claude Desktop 是 Anthropic 的产品，本项目与 Anthropic 无关。

## 致谢

- 简体中文包原型：[RICK @ Linux Do](https://linux.do/t/topic/2040184)
- [Linux Do 社区](https://linux.do/)
