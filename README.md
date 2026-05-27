# Claude Desktop 简体中文语言包

> **只需把这个仓库丢给 AI Agent，它就能帮你完成安装。**
>
> Agent 执行 `ClaudeChineseLangPack.bat` 选择「完整安装」即可。

为 Claude Desktop (Windows) 提供完整的简体中文界面翻译。

覆盖 ion-dist（15,996 条）、desktop-shell（374 条）、statsig（46 条）三个模块，并额外修补了 JS 中硬编码的英文 UI 字符串。

## 前提

- Windows 10 / 11
- 已安装 [Claude Desktop](https://claude.ai/download)
- Node.js（用于修补硬编码字符串，选项 1/4 需要）

## 使用方法

双击 `ClaudeChineseLangPack.bat`，按提示选择：

```
1. 完整安装（翻译 + 界面补丁）  ← 推荐
2. 仅安装语言包
3. 卸载语言包
4. 还原所有
```

| 选项 | 说明 |
|------|------|
| **1. 完整安装** | 替换翻译 JSON + 修补 JS 中硬编码的英文字符串（如 "New session"、"New chat" 等） |
| **2. 仅安装语言包** | 只替换翻译 JSON 文件，不修改 JS |
| **3. 卸载语言包** | 删除翻译文件，恢复语言注册，locale 回退到 en-US |
| **4. 还原所有** | 卸载语言包 + 还原 JS 文件到原始状态 |

操作完成后需**重启 Claude Desktop** 生效。

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

### 硬编码字符串修补

Claude Desktop 的 JS 中有一部分 UI 字符串绕过了 i18n 系统（如 "New session"、"Create with Claude"、"Try again" 等）。`patch-hardcoded-strings.js` 会将这些硬编码英文替换为中文，并在修改前自动备份原始 JS 文件。

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

## 许可

[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0)

仅供个人学习使用。Claude Desktop 是 Anthropic 的产品，本项目与 Anthropic 无关。

## 致谢

- 简体中文包原型：[RICK @ Linux Do](https://linux.do/t/topic/2040184)
- [Linux Do 社区](https://linux.do/)
