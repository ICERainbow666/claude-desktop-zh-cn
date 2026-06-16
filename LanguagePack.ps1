[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$Extract,
    [switch]$TranslationOnly,
    [switch]$NoRestart,
    [switch]$PauseAtEnd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$packDir = Join-Path $scriptDir "translated-zh-CN"
$backupDir = Join-Path ([System.IO.Path]::GetTempPath()) "claude-zh-cn-backup"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Administrator {
    param(
        [string[]]$Arguments = @()
    )

    if (Test-IsAdministrator) {
        return
    }

    $argumentList = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "`"$PSCommandPath`""
    ) + $Arguments

    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argumentList | Out-Null
    exit
}

function Wait-BeforeExit {
    if (-not $PauseAtEnd) {
        return
    }

    Write-Host ""
    [void](Read-Host "按回车关闭窗口")
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if ($parent) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Find-ClaudePath {
    try {
        $pkg = Get-AppxPackage -Name Claude -ErrorAction Stop |
            Sort-Object Version -Descending |
            Select-Object -First 1
        if ($pkg -and $pkg.InstallLocation -and (Test-Path -LiteralPath $pkg.InstallLocation)) {
            return $pkg.InstallLocation
        }
    }
    catch {
    }

    try {
        $deployments = Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deployments" -ErrorAction Stop |
            Where-Object { $_.PSChildName -like "Claude*" } |
            Sort-Object PSChildName -Descending

        foreach ($deployment in $deployments) {
            $candidate = Join-Path ${env:ProgramFiles} "WindowsApps\$($deployment.PSChildName)"
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }
    catch {
    }

    $windowsApps = Join-Path ${env:ProgramFiles} "WindowsApps"
    if (Test-Path -LiteralPath $windowsApps) {
        $candidate = Get-ChildItem -LiteralPath $windowsApps -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "Claude*" } |
            Sort-Object Name -Descending |
            Select-Object -First 1

        if ($candidate) {
            return $candidate.FullName
        }
    }

    return $null
}

function Get-ResourcesPath {
    param(
        [Parameter(Mandatory = $true)][string]$ClaudePath
    )

    $resourcesPath = Join-Path $ClaudePath "app\resources"
    if (Test-Path -LiteralPath $resourcesPath) {
        return $resourcesPath
    }

    return $null
}

function Grant-WriteAccess {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        $takeownArgs = @("/f", $Path, "/a")
        if ($item.PSIsContainer) {
            $takeownArgs += @("/r", "/d", "Y")
        }

        & takeown.exe @takeownArgs | Out-Null

        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        if ($identity) {
            & icacls.exe $Path "/grant" "${identity}:(F)" "/t" "/c" | Out-Null
        }
    }
    catch {
    }
}

function Backup-File {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    [System.IO.Directory]::CreateDirectory($backupDir) | Out-Null
    Copy-Item -LiteralPath $Path -Destination (Join-Path $backupDir (Split-Path $Path -Leaf)) -Force
}

function Patch-JsLanguage {
    param(
        [Parameter(Mandatory = $true)][string]$ResourcesPath
    )

    $assetsDir = Join-Path $ResourcesPath "ion-dist\assets\v1"
    if (-not (Test-Path -LiteralPath $assetsDir -PathType Container)) {
        Write-Host "  [警告] 未找到 assets 目录，跳过 JS 补丁" -ForegroundColor Yellow
        return $false
    }

    $jsFiles = Get-ChildItem -LiteralPath $assetsDir -Filter "*.js" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -lt 10MB }  # Skip oversized vendor files
    if (-not $jsFiles) {
        Write-Host "  [警告] 未找到 JS 文件，跳过 JS 补丁" -ForegroundColor Yellow
        return $false
    }

    # Old array format: Mz=["en-US","de-DE",...,"id-ID"]
    $exactOldArr = 'Mz=["en-US","de-DE","fr-FR","ko-KR","ja-JP","es-419","es-ES","it-IT","hi-IN","pt-BR","id-ID"]'
    $exactNewArr = 'Mz=["en-US","de-DE","fr-FR","ko-KR","ja-JP","es-419","es-ES","it-IT","hi-IN","pt-BR","id-ID","zh-CN"]'
    # New object format: vX={"en-US":"en","de-DE":"de",...,"id-ID":"id"}
    $exactOldObj = ',"id-ID":"id"}'
    $exactNewObj = ',"id-ID":"id","zh-CN":"zh"}'
    # Regex: object format  VarName={"en-US":"xx",...,"xx-XX":"xx"(,)}
    $regexObj = [regex]'((?:\w+)=\{"en-US":"[^"]+"(?:,"[^"]+":")[^"]*"),?\}'
    # Regex: old array format  VarName=["en-US",...,"xx-XX"(,)]
    $regexArr = [regex]'((?:\w+)=\["en-US"(?:,"[^"]+")*),?\]'

    $patched = $false

    foreach ($jsFile in $jsFiles) {
        Grant-WriteAccess -Path $jsFile.FullName

        $content = [System.IO.File]::ReadAllText($jsFile.FullName)
        # Skip files without locale data
        if (-not $content.Contains('"en-US"')) { continue }
        if ($content.Contains('"zh-CN"')) {
            Write-Host "  已注册: $($jsFile.Name)"
            $patched = $true
            continue
        }

        Backup-File -Path $jsFile.FullName

        # Try exact matches first (fast path)
        if ($content.Contains($exactOldArr)) {
            $newContent = $content.Replace($exactOldArr, $exactNewArr)
            Write-Utf8File -Path $jsFile.FullName -Content $newContent
            Write-Host "  JS补丁已应用(数组): $($jsFile.Name)"
            $patched = $true
            continue
        }
        if ($content.Contains($exactOldObj)) {
            $newContent = $content.Replace($exactOldObj, $exactNewObj)
            Write-Utf8File -Path $jsFile.FullName -Content $newContent
            Write-Host "  JS补丁已应用(对象): $($jsFile.Name)"
            $patched = $true
            continue
        }

        # Regex fallback: try object format first, then array format
        $newContent = $regexObj.Replace($content, '$1,"zh-CN":"zh"}', 1)
        if ($newContent -ne $content) {
            Write-Utf8File -Path $jsFile.FullName -Content $newContent
            Write-Host "  JS补丁已应用(对象正则): $($jsFile.Name)"
            $patched = $true
            continue
        }
        $newContent = $regexArr.Replace($content, '$1,"zh-CN"]', 1)
        if ($newContent -ne $content) {
            Write-Utf8File -Path $jsFile.FullName -Content $newContent
            Write-Host "  JS补丁已应用(数组正则): $($jsFile.Name)"
            $patched = $true
            continue
        }

        # Only warn for files that look like they should have a language list
        if ($content.Contains('"de-DE"') -and $content.Contains('"id-ID"')) {
            Write-Host "  [警告] 未匹配到语言列表: $($jsFile.Name) (Claude 可能已更新)" -ForegroundColor Yellow
        }
    }

    if (-not $patched) {
        Write-Host "  [警告] 未在任何 JS 文件中找到语言列表 (Claude 可能已更新)" -ForegroundColor Yellow
    }

    return $patched
}

function Unpatch-JsLanguage {
    param(
        [Parameter(Mandatory = $true)][string]$ResourcesPath
    )

    $assetsDir = Join-Path $ResourcesPath "ion-dist\assets\v1"
    if (-not (Test-Path -LiteralPath $assetsDir -PathType Container)) {
        Write-Host "  [警告] 未找到 assets 目录" -ForegroundColor Yellow
        return
    }

    $jsFiles = Get-ChildItem -LiteralPath $assetsDir -Filter "*.js" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -lt 10MB }  # Skip oversized vendor files
    # Old array format
    $exactOldArr = 'Mz=["en-US","de-DE","fr-FR","ko-KR","ja-JP","es-419","es-ES","it-IT","hi-IN","pt-BR","id-ID","zh-CN"]'
    $exactNewArr = 'Mz=["en-US","de-DE","fr-FR","ko-KR","ja-JP","es-419","es-ES","it-IT","hi-IN","pt-BR","id-ID"]'
    # New object format
    $exactOldObj = ',"id-ID":"id","zh-CN":"zh"}'
    $exactNewObj = ',"id-ID":"id"}'
    # Regex: object format
    $regexObj = [regex]'((?:\w+)=\{(?:"[^"]+":"[^"]+",)+)"zh-CN":"[^"]+",?\}'
    # Regex: array format
    $regexArr = [regex]'((?:\w+)=\[(?:"[^"]+",)+)"zh-CN",?\]'

    foreach ($jsFile in $jsFiles) {
        $backupPath = Join-Path $backupDir $jsFile.Name

        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Grant-WriteAccess -Path $jsFile.FullName
            Copy-Item -LiteralPath $backupPath -Destination $jsFile.FullName -Force
            Write-Host "  从备份恢复: $($jsFile.Name)"
            continue
        }

        Grant-WriteAccess -Path $jsFile.FullName
        $content = [System.IO.File]::ReadAllText($jsFile.FullName)

        if (-not $content.Contains('"zh-CN"')) {
            Write-Host "  无需恢复: $($jsFile.Name)"
            continue
        }

        if ($content.Contains($exactOldArr)) {
            $newContent = $content.Replace($exactOldArr, $exactNewArr)
            Write-Utf8File -Path $jsFile.FullName -Content $newContent
            Write-Host "  语言注册已恢复(数组): $($jsFile.Name)"
            continue
        }

        if ($content.Contains($exactOldObj)) {
            $newContent = $content.Replace($exactOldObj, $exactNewObj)
            Write-Utf8File -Path $jsFile.FullName -Content $newContent
            Write-Host "  语言注册已恢复(对象): $($jsFile.Name)"
            continue
        }

        $newContent = $regexObj.Replace($content, '$1}', 1)
        if ($newContent -ne $content) {
            Write-Utf8File -Path $jsFile.FullName -Content $newContent
            Write-Host "  语言注册已恢复(对象正则): $($jsFile.Name)"
            continue
        }

        $newContent = $regexArr.Replace($content, '$1]', 1)
        if ($newContent -ne $content) {
            Write-Utf8File -Path $jsFile.FullName -Content $newContent
            Write-Host "  语言注册已恢复(数组正则): $($jsFile.Name)"
            continue
        }

        Write-Host "  [警告] 无法移除 zh-CN: $($jsFile.Name)" -ForegroundColor Yellow
        Write-Host "  建议重新安装 Claude Desktop" -ForegroundColor Yellow
    }

    if (Test-Path -LiteralPath $backupDir -PathType Container) {
        Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  备份已清理"
    }
}

function Patch-HardcodedStrings {
    param(
        [Parameter(Mandatory = $true)][string]$ResourcesPath
    )

    $assetsDir = Join-Path $ResourcesPath "ion-dist\assets\v1"
    if (-not (Test-Path -LiteralPath $assetsDir -PathType Container)) { return }

    # These strings bypass the i18n system and must be replaced directly in JS
    $replacements = @(
        @{ Old = '?"New task":"New chat"'; New = '?"新任务":"新对话"' },
        @{ Old = '||"New task"'; New = '||"新任务"' },
        @{ Old = 'baseDescription:"New chat"'; New = 'baseDescription:"新对话"' },
        @{ Old = 'baseDescription:"New task"'; New = 'baseDescription:"新任务"' },
        @{ Old = 'recents:"Recents",shared:"Shared"'; New = 'recents:"最近",shared:"共享"' },
        @{ Old = 'all:"All",active:"Active",archived:"Archived"'; New = 'all:"全部",active:"活跃",archived:"已归档"' },
        @{ Old = 'all:"No tasks yet."'; New = 'all:"暂无任务。"' },
        @{ Old = 'active:"No active tasks."'; New = 'active:"没有活跃任务。"' },
        @{ Old = 'archived:"No archived tasks."'; New = 'archived:"没有已归档任务。"' },
        @{ Old = 'newTask:{defaultMessage:"New task"'; New = 'newTask:{defaultMessage:"新任务"' },
        @{ Old = 'newRoutine:{defaultMessage:"New code session"'; New = 'newRoutine:{defaultMessage:"新建代码会话"' },
        # --- Property context patterns ---
        @{ Old = 'code:"New session"'; New = 'code:"新建会话"' },
        @{ Old = 'code:"New code session"'; New = 'code:"新建代码会话"' },
        @{ Old = 'cowork:"New task"'; New = 'cowork:"新任务"' },
        @{ Old = 'chat:"New chat"'; New = 'chat:"新对话"' },
        @{ Old = 'label:"New session"'; New = 'label:"新建会话"' },
        @{ Old = 'label:"New chat"'; New = 'label:"新对话"' },
        @{ Old = 'label:"New task"'; New = 'label:"新任务"' },
        @{ Old = 'label:"New code session"'; New = 'label:"新建代码会话"' },
        @{ Old = 'label:"Go to home"'; New = 'label:"返回首页"' },
        @{ Old = 'label:"Phone call"'; New = 'label:"电话"' },
        @{ Old = 'title:"New session"'; New = 'title:"新建会话"' },
        @{ Old = 'title:"New chat"'; New = 'title:"新对话"' },
        @{ Old = 'title:"New task"'; New = 'title:"新任务"' },
        @{ Old = 'title:"Go to home"'; New = 'title:"返回首页"' },
        @{ Old = 'children:"Recents"'; New = 'children:"最近"' },
        # --- Global standalone string replacements (catches remaining defaultMessage etc.) ---
        @{ Old = '"New code session"'; New = '"新建代码会话"' },
        @{ Old = '"New scheduled task"'; New = '"新建计划任务"' },
        @{ Old = '"New session"'; New = '"新建会话"' },
        @{ Old = '"New chat"'; New = '"新对话"' },
        @{ Old = '"New task"'; New = '"新任务"' },
        @{ Old = '"Go to home"'; New = '"返回首页"' },
        @{ Old = '"Phone call"'; New = '"电话"' },
        @{ Old = '"Recents"'; New = '"最近"' },
        @{ Old = '"Shared"'; New = '"共享"' },
        @{ Old = '"No tasks yet."'; New = '"暂无任务。"' },
        @{ Old = '"No active tasks."'; New = '"没有活跃任务。"' },
        @{ Old = '"No archived tasks."'; New = '"没有已归档任务。"' },
        # --- Dev tools & settings ---
        @{ Old = '"Enable Main Process Debugger"'; New = '"启用主进程调试器"' },
        @{ Old = '"Record Performance Trace"'; New = '"记录性能跟踪"' },
        @{ Old = '"Write Main Process Heap Snapshot"'; New = '"写入主进程堆快照"' },
        @{ Old = '"Record Memory Trace (auto-stop)"'; New = '"记录内存跟踪（自动停止）"' },
        @{ Old = '"Inference configuration"'; New = '"推理配置"' },
        @{ Old = '"View changelog"'; New = '"查看更新日志"' }
    )

    $patched = 0
    $jsFiles = Get-ChildItem -LiteralPath $assetsDir -Filter "*.js" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -lt 10MB }

    foreach ($jsFile in $jsFiles) {
        $content = [System.IO.File]::ReadAllText($jsFile.FullName)
        $changed = $false

        foreach ($r in $replacements) {
            if ($content.Contains($r.Old)) {
                $content = $content.Replace($r.Old, $r.New)
                $changed = $true
                $patched++
            }
        }

        if ($changed) {
            Grant-WriteAccess -Path $jsFile.FullName
            Write-Utf8File -Path $jsFile.FullName -Content $content
            Write-Host "  硬编码替换: $($jsFile.Name)"
        }
    }

    if ($patched -gt 0) {
        Write-Host "  共替换 $patched 处硬编码字符串"
    }
}

function Unpatch-HardcodedStrings {
    param(
        [Parameter(Mandatory = $true)][string]$ResourcesPath
    )

    $assetsDir = Join-Path $ResourcesPath "ion-dist\assets\v1"
    if (-not (Test-Path -LiteralPath $assetsDir -PathType Container)) { return }

    # Comprehensive reversals: Chinese back to English
    # Order matters: longer/more specific patterns first
    $reversals = @(
        # --- Direct pattern replacements (PS script + Node.js Phase 3) ---
        @{ Old = '?"新任务":"新对话"'; New = '?"New task":"New chat"' },
        @{ Old = '||"新任务"'; New = '||"New task"' },
        @{ Old = 'baseDescription:"新对话"'; New = 'baseDescription:"New chat"' },
        @{ Old = 'baseDescription:"新任务"'; New = 'baseDescription:"New task"' },
        @{ Old = 'recents:"最近",shared:"共享"'; New = 'recents:"Recents",shared:"Shared"' },
        @{ Old = 'all:"全部",active:"活跃",archived:"已归档"'; New = 'all:"All",active:"Active",archived:"Archived"' },
        @{ Old = 'all:"暂无任务。"'; New = 'all:"No tasks yet."' },
        @{ Old = 'active:"没有活跃任务。"'; New = 'active:"No active tasks."' },
        @{ Old = 'archived:"没有已归档任务。"'; New = 'archived:"No archived tasks."' },
        @{ Old = 'recents:"暂无任务。"'; New = 'recents:"No tasks yet."' },
        @{ Old = 'shared:"您还没有共享任何任务。"'; New = 'shared:"You haven''t shared any tasks yet."' },
        @{ Old = 'noResults:"没有匹配的任务。"'; New = 'noResults:"No tasks match your search."' },
        @{ Old = 'searchPlaceholder:"筛选任务"'; New = 'searchPlaceholder:"Filter tasks"' },
        # --- defaultMessage context (Node.js Phase 2) ---
        @{ Old = 'defaultMessage:"新建会话"'; New = 'defaultMessage:"New session"' },
        @{ Old = 'defaultMessage:"新对话"'; New = 'defaultMessage:"New chat"' },
        @{ Old = 'defaultMessage:"新任务"'; New = 'defaultMessage:"New task"' },
        @{ Old = 'defaultMessage:"新建代码会话"'; New = 'defaultMessage:"New code session"' },
        @{ Old = 'defaultMessage:"返回首页"'; New = 'defaultMessage:"Go to home"' },
        @{ Old = 'defaultMessage:"电话"'; New = 'defaultMessage:"Phone call"' },
        @{ Old = 'defaultMessage:"最近"'; New = 'defaultMessage:"Recents"' },
        @{ Old = 'defaultMessage:"共享"'; New = 'defaultMessage:"Shared"' },
        @{ Old = 'defaultMessage:"暂无任务。"'; New = 'defaultMessage:"No tasks yet."' },
        @{ Old = 'defaultMessage:"没有活跃任务。"'; New = 'defaultMessage:"No active tasks."' },
        @{ Old = 'defaultMessage:"没有已归档任务。"'; New = 'defaultMessage:"No archived tasks."' },
        # --- Object property context (Node.js Phase 1 targets) ---
        @{ Old = 'label:"新建会话"'; New = 'label:"New session"' },
        @{ Old = 'label:"新对话"'; New = 'label:"New chat"' },
        @{ Old = 'label:"新任务"'; New = 'label:"New task"' },
        @{ Old = 'label:"新建代码会话"'; New = 'label:"New code session"' },
        @{ Old = 'label:"返回首页"'; New = 'label:"Go to home"' },
        @{ Old = 'label:"电话"'; New = 'label:"Phone call"' },
        @{ Old = 'title:"新建会话"'; New = 'title:"New session"' },
        @{ Old = 'title:"新对话"'; New = 'title:"New chat"' },
        @{ Old = 'title:"新任务"'; New = 'title:"New task"' },
        @{ Old = 'title:"返回首页"'; New = 'title:"Go to home"' },
        @{ Old = 'children:"最近"'; New = 'children:"Recents"' },
        @{ Old = 'placeholder:"新建会话"'; New = 'placeholder:"New session"' },
        @{ Old = 'placeholder:"新对话"'; New = 'placeholder:"New chat"' },
        @{ Old = 'placeholder:"新任务"'; New = 'placeholder:"New task"' },
        # --- code/cowork/chat object context (from current patched state) ---
        @{ Old = 'code:"新建会话"'; New = 'code:"New session"' },
        @{ Old = 'code:"新建代码会话"'; New = 'code:"New code session"' },
        @{ Old = 'cowork:"新任务"'; New = 'cowork:"New task"' },
        @{ Old = 'chat:"新对话"'; New = 'chat:"New chat"' },
        @{ Old = 'newTask:{defaultMessage:"新任务"'; New = 'newTask:{defaultMessage:"New task"' },
        @{ Old = 'newRoutine:{defaultMessage:"新建代码会话"'; New = 'newRoutine:{defaultMessage:"New code session"' },
        # --- Global standalone string reversals ---
        @{ Old = '"新建会话"'; New = '"New session"' },
        @{ Old = '"新对话"'; New = '"New chat"' },
        @{ Old = '"新任务"'; New = '"New task"' },
        @{ Old = '"新建代码会话"'; New = '"New code session"' },
        @{ Old = '"新建计划任务"'; New = '"New scheduled task"' },
        @{ Old = '"返回首页"'; New = '"Go to home"' },
        @{ Old = '"电话"'; New = '"Phone call"' },
        @{ Old = '"最近"'; New = '"Recents"' },
        @{ Old = '"共享"'; New = '"Shared"' },
        @{ Old = '"暂无任务。"'; New = '"No tasks yet."' },
        @{ Old = '"没有活跃任务。"'; New = '"No active tasks."' },
        @{ Old = '"没有已归档任务。"'; New = '"No archived tasks."' },
        @{ Old = '"重试。"'; New = '"Try again."' },
        # --- Dev tools & settings ---
        @{ Old = '"启用主进程调试器"'; New = '"Enable Main Process Debugger"' },
        @{ Old = '"记录性能跟踪"'; New = '"Record Performance Trace"' },
        @{ Old = '"写入主进程堆快照"'; New = '"Write Main Process Heap Snapshot"' },
        @{ Old = '"记录内存跟踪（自动停止）"'; New = '"Record Memory Trace (auto-stop)"' },
        @{ Old = '"推理配置"'; New = '"Inference configuration"' },
        @{ Old = '"查看更新日志"'; New = '"View changelog"' }
    )

    $restored = 0
    $jsFiles = Get-ChildItem -LiteralPath $assetsDir -Filter "*.js" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -lt 10MB }

    foreach ($jsFile in $jsFiles) {
        $content = [System.IO.File]::ReadAllText($jsFile.FullName)
        $changed = $false

        foreach ($r in $reversals) {
            if ($content.Contains($r.Old)) {
                $content = $content.Replace($r.Old, $r.New)
                $changed = $true
                $restored++
            }
        }

        if ($changed) {
            Grant-WriteAccess -Path $jsFile.FullName
            Write-Utf8File -Path $jsFile.FullName -Content $content
            Write-Host "  还原硬编码字符串: $($jsFile.Name)"
        }
    }

    if ($restored -gt 0) {
        Write-Host "  共还原 $restored 处硬编码字符串"
    } else {
        Write-Host "  未发现需要还原的硬编码字符串"
    }
}

function Update-Config {
    param(
        [Parameter(Mandatory = $true)][string]$Locale
    )

    $base = Join-Path ${env:LOCALAPPDATA} "Packages\Claude_pzs8sxrjxfjjc"
    $configPaths = @(
        (Join-Path $base "LocalCache\Roaming\Claude\config.json"),
        (Join-Path $base "LocalCache\Roaming\Claude-3p\config.json")
    )

    foreach ($configPath in $configPaths) {
        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
            continue
        }

        try {
            $raw = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
            $config = $raw | ConvertFrom-Json

            if ($config.PSObject.Properties.Name -contains "locale") {
                $config.locale = $Locale
            }
            else {
                $config | Add-Member -NotePropertyName "locale" -NotePropertyValue $Locale
            }

            $json = $config | ConvertTo-Json -Depth 100
            Write-Utf8File -Path $configPath -Content $json
            Write-Host "  $(Split-Path $configPath -Leaf)"
        }
        catch {
            Write-Host "  [警告] 配置更新失败: $(Split-Path $configPath -Leaf) ($($_.Exception.Message))" -ForegroundColor Yellow
        }
    }
}

function Get-ClaudeApplicationId {
    param(
        [Parameter(Mandatory = $true)][string]$ClaudePath
    )

    $manifestPath = Join-Path $ClaudePath "AppxManifest.xml"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return $null
    }

    try {
        [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
        $application = @($manifest.Package.Applications.Application | Select-Object -First 1)[0]
        if ($application -and $application.Id) {
            return [string]$application.Id
        }
    }
    catch {
    }

    return $null
}

function Get-ClaudePackageFamilyName {
    param(
        [Parameter(Mandatory = $true)][string]$ClaudePath
    )

    try {
        $resolvedClaudePath = [System.IO.Path]::GetFullPath($ClaudePath).TrimEnd("\")
        $pkg = Get-AppxPackage -Name Claude -ErrorAction Stop |
            Sort-Object Version -Descending |
            Where-Object {
                $_.InstallLocation -and
                ([System.IO.Path]::GetFullPath($_.InstallLocation).TrimEnd("\") -ieq $resolvedClaudePath)
            } |
            Select-Object -First 1

        if ($pkg -and $pkg.PackageFamilyName) {
            return [string]$pkg.PackageFamilyName
        }
    }
    catch {
    }

    try {
        [xml]$manifest = Get-Content -LiteralPath (Join-Path $ClaudePath "AppxManifest.xml") -Raw
        $identityName = [string]$manifest.Package.Identity.Name
        $folderName = Split-Path -Leaf $ClaudePath
        if ($identityName -and ($folderName -match "__([^_\\]+)$")) {
            return "$identityName`_$($Matches[1])"
        }
    }
    catch {
    }

    return $null
}

function Get-ClaudeAppUserModelId {
    param(
        [Parameter(Mandatory = $true)][string]$ClaudePath
    )

    $packageFamilyName = Get-ClaudePackageFamilyName -ClaudePath $ClaudePath
    $applicationId = Get-ClaudeApplicationId -ClaudePath $ClaudePath

    if ($packageFamilyName -and $applicationId) {
        return "$packageFamilyName!$applicationId"
    }

    return $null
}

function Start-ClaudeWithExplorer {
    param(
        [Parameter(Mandatory = $true)][string]$Target
    )

    try {
        $argument = $Target
        if ($Target -notlike "shell:*") {
            $argument = "`"$Target`""
        }

        Start-Process -FilePath "explorer.exe" -ArgumentList $argument | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Start-ClaudeWithWmi {
    param(
        [Parameter(Mandatory = $true)][string]$ExePath
    )

    try {
        $workingDirectory = Split-Path -Parent $ExePath
        $result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
            CommandLine      = "`"$ExePath`""
            CurrentDirectory = $workingDirectory
        }

        return ($result.ReturnValue -eq 0)
    }
    catch {
        return $false
    }
}

function Start-ClaudeDetached {
    param(
        [Parameter(Mandatory = $true)][string]$ClaudePath
    )

    $appUserModelId = Get-ClaudeAppUserModelId -ClaudePath $ClaudePath
    if ($appUserModelId) {
        if (Start-ClaudeWithExplorer -Target "shell:AppsFolder\$appUserModelId") {
            return $true
        }
    }

    $exe = Join-Path $ClaudePath "app\claude.exe"
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        return $false
    }

    if (Start-ClaudeWithExplorer -Target $exe) {
        return $true
    }

    return (Start-ClaudeWithWmi -ExePath $exe)
}

function Restart-Claude {
    try {
        Stop-Process -Name "claude" -Force -ErrorAction SilentlyContinue
    }
    catch {
    }

    Start-Sleep -Seconds 2

    $claudePath = Find-ClaudePath
    if (-not $claudePath) {
        return
    }

    if (Start-ClaudeDetached -ClaudePath $claudePath) {
        Start-Sleep -Seconds 3
        Write-Host "Claude Desktop 已重启"
    }
    else {
        Write-Host "  [警告] 自动启动 Claude 失败，请手动打开 Claude Desktop" -ForegroundColor Yellow
    }
}

function Get-RequiredTranslationFiles {
    $required = @(
        [pscustomobject]@{ Name = "ion-dist"; Path = (Join-Path $packDir "ion-dist\zh-CN.json") },
        [pscustomobject]@{ Name = "desktop-shell"; Path = (Join-Path $packDir "desktop-shell\zh-CN.json") },
        [pscustomobject]@{ Name = "dynamic"; Path = (Join-Path $packDir "ion-dist\dynamic\zh-CN.json") }
    )

    foreach ($item in $required) {
        if (-not (Test-Path -LiteralPath $item.Path -PathType Leaf)) {
            $legacyPath = Join-Path $scriptDir "$($item.Name)\zh-CN.json"
            if (Test-Path -LiteralPath $legacyPath -PathType Leaf) {
                $item.Path = $legacyPath
            }
        }
    }

    return $required
}

function Resolve-ClaudeResources {
    $claudePath = Find-ClaudePath
    if (-not $claudePath) {
        throw "未检测到 Claude Desktop"
    }

    $resourcesPath = Get-ResourcesPath -ClaudePath $claudePath
    if (-not $resourcesPath) {
        throw "未找到 resources 目录"
    }

    return [pscustomobject]@{
        ClaudePath = $claudePath
        ResourcesPath = $resourcesPath
    }
}

function Install-LanguagePack {
    Write-Host ""
    Write-Host "=== Claude Desktop 中文语言包安装 ==="
    Write-Host ""
    Write-Host "无需 Python，正在直接使用 PowerShell 安装。"

    $required = Get-RequiredTranslationFiles
    foreach ($item in $required) {
        if (-not (Test-Path -LiteralPath $item.Path -PathType Leaf)) {
            throw "缺少翻译文件: $($item.Path)"
        }

        $sizeKb = [math]::Floor((Get-Item -LiteralPath $item.Path).Length / 1KB)
        Write-Host ("  {0}: OK ({1}KB)" -f $item.Name, $sizeKb)
    }

    Write-Host ""
    Write-Host "[1/6] 查找 Claude Desktop..."
    $resolved = Resolve-ClaudeResources
    Write-Host "  Claude: $($resolved.ClaudePath)"

    Write-Host ""
    Write-Host "[2/6] 获取写入权限..."

    # WindowsApps 目录有系统级保护，需要给路径链上的关键目录都授予管理员权限
    $claudeParent = Split-Path -Parent $resolved.ClaudePath  # C:\Program Files\WindowsApps
    $appPath = Join-Path $resolved.ClaudePath "app"
    $criticalPaths = @($claudeParent, $resolved.ClaudePath, $appPath, $resolved.ResourcesPath)
    foreach ($path in $criticalPaths) {
        if (Test-Path -LiteralPath $path) {
            try {
                & takeown.exe "/f" $path "/a" | Out-Null
                & icacls.exe $path "/grant" "BUILTIN\Administrators:(OI)(CI)(F)" "/c" | Out-Null
            }
            catch { }
        }
    }

    $pathsToGrant = @(
        $resolved.ResourcesPath,
        (Join-Path $resolved.ResourcesPath "ion-dist"),
        (Join-Path $resolved.ResourcesPath "ion-dist\i18n"),
        (Join-Path $resolved.ResourcesPath "ion-dist\i18n\dynamic"),
        (Join-Path $resolved.ResourcesPath "ion-dist\assets"),
        (Join-Path $resolved.ResourcesPath "ion-dist\assets\v1")
    )

    foreach ($path in $pathsToGrant) {
        Grant-WriteAccess -Path $path
    }

    $assetsDir = Join-Path $resolved.ResourcesPath "ion-dist\assets\v1"
    if (Test-Path -LiteralPath $assetsDir -PathType Container) {
        Get-ChildItem -LiteralPath $assetsDir -Filter "*.js" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -lt 10MB } |
            ForEach-Object { Grant-WriteAccess -Path $_.FullName }
    }

    Write-Host "  权限处理完成"

    Write-Host ""
    Write-Host "[3/6] 安装翻译文件..."
    $targets = @(
        [pscustomobject]@{ Source = $required[0].Path; Target = (Join-Path $resolved.ResourcesPath "ion-dist\i18n\zh-CN.json") },
        [pscustomobject]@{ Source = $required[1].Path; Target = (Join-Path $resolved.ResourcesPath "zh-CN.json") },
        [pscustomobject]@{ Source = $required[2].Path; Target = (Join-Path $resolved.ResourcesPath "ion-dist\i18n\dynamic\zh-CN.json") }
    )

    foreach ($target in $targets) {
        [System.IO.Directory]::CreateDirectory((Split-Path -Parent $target.Target)) | Out-Null
        Copy-Item -LiteralPath $target.Source -Destination $target.Target -Force
        $relativeTarget = $target.Target.Substring($resolved.ResourcesPath.Length).TrimStart("\")
        Write-Host "  $relativeTarget"
    }

    if ($TranslationOnly) {
        Write-Host ""
        Write-Host "[4/4] 更新配置..."
        Update-Config -Locale "zh-CN"
    }
    else {
        Write-Host ""
        Write-Host "[4/6] 注册中文语言..."
        [void](Patch-JsLanguage -ResourcesPath $resolved.ResourcesPath)

        Write-Host ""
        Write-Host "[5/6] 替换硬编码字符串..."
        Patch-HardcodedStrings -ResourcesPath $resolved.ResourcesPath

        Write-Host ""
        Write-Host "[6/6] 更新配置..."
        Update-Config -Locale "zh-CN"
    }

    Write-Host ""
    Write-Host "=== 语言包安装完成 ==="
    if ($NoRestart) {
        Write-Host "请手动重启 Claude Desktop 使更改生效。"
    }
    else {
        Write-Host ""
        Restart-Claude
    }
}

function Uninstall-LanguagePack {
    Write-Host ""
    Write-Host "=== Claude Desktop 中文语言包卸载 ==="
    Write-Host ""

    Write-Host "[1/5] 查找 Claude Desktop..."
    $resolved = Resolve-ClaudeResources
    Write-Host "  Claude: $($resolved.ClaudePath)"

    Write-Host ""
    Write-Host "[2/5] 删除翻译文件..."

    # 确保路径链上的关键目录有权限
    $claudeParent = Split-Path -Parent $resolved.ClaudePath
    $appPath = Join-Path $resolved.ClaudePath "app"
    $criticalPaths = @($claudeParent, $resolved.ClaudePath, $appPath, $resolved.ResourcesPath)
    foreach ($path in $criticalPaths) {
        if (Test-Path -LiteralPath $path) {
            try {
                & takeown.exe "/f" $path "/a" | Out-Null
                & icacls.exe $path "/grant" "BUILTIN\Administrators:(OI)(CI)(F)" "/c" | Out-Null
            }
            catch { }
        }
    }

    foreach ($path in @(
            (Join-Path $resolved.ResourcesPath "ion-dist\i18n\zh-CN.json"),
            (Join-Path $resolved.ResourcesPath "zh-CN.json"),
            (Join-Path $resolved.ResourcesPath "ion-dist\i18n\dynamic\zh-CN.json")
        )) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Grant-WriteAccess -Path $path
            Remove-Item -LiteralPath $path -Force
        }
    }
    Write-Host "  翻译文件已删除"

    Write-Host ""
    Write-Host "[3/5] 恢复语言注册..."
    Unpatch-JsLanguage -ResourcesPath $resolved.ResourcesPath

    Write-Host ""
    Write-Host "[4/5] 还原硬编码字符串..."
    Unpatch-HardcodedStrings -ResourcesPath $resolved.ResourcesPath

    Write-Host ""
    Write-Host "[5/5] 恢复配置..."
    Update-Config -Locale "en-US"

    Write-Host ""
    Write-Host "=== 语言包卸载完成 ==="
    if ($NoRestart) {
        Write-Host "请手动重启 Claude Desktop 使更改生效。"
    }
    else {
        Write-Host ""
        Restart-Claude
    }
}

function Extract-EnglishFiles {
    Write-Host ""
    Write-Host "=== Claude Desktop 英文文本提取 ==="
    Write-Host ""

    Write-Host "[1/3] 查找 Claude Desktop..."
    $resolved = Resolve-ClaudeResources
    Write-Host "  Claude: $($resolved.ClaudePath)"

    $enDir = Join-Path $scriptDir "extracted-en-US"
    $templateDir = Join-Path $scriptDir "translation-template"
    $targets = @(
        [pscustomobject]@{ Name = "ion-dist"; Source = (Join-Path $resolved.ResourcesPath "ion-dist\i18n\en-US.json") },
        [pscustomobject]@{ Name = "desktop-shell"; Source = (Join-Path $resolved.ResourcesPath "en-US.json") },
        [pscustomobject]@{ Name = "dynamic"; Source = (Join-Path $resolved.ResourcesPath "ion-dist\i18n\dynamic\en-US.json") }
    )

    Write-Host ""
    Write-Host "[2/3] 提取 en-US 原文..."
    foreach ($target in $targets) {
        if (-not (Test-Path -LiteralPath $target.Source -PathType Leaf)) {
            Write-Host "  [警告] 未找到: $($target.Source)" -ForegroundColor Yellow
            continue
        }

        $enOut = Join-Path $enDir "$($target.Name)\en-US.json"
        $templateOut = Join-Path $templateDir "$($target.Name)\zh-CN.json"
        [System.IO.Directory]::CreateDirectory((Split-Path -Parent $enOut)) | Out-Null
        [System.IO.Directory]::CreateDirectory((Split-Path -Parent $templateOut)) | Out-Null
        Copy-Item -LiteralPath $target.Source -Destination $enOut -Force
        Copy-Item -LiteralPath $target.Source -Destination $templateOut -Force
        Write-Host "  $($target.Name): OK"
    }

    Write-Host ""
    Write-Host "[3/3] 提取完成"
    Write-Host ""
    Write-Host "英文原文目录: extracted-en-US/"
    Write-Host "待翻译模板目录: translation-template/"
    Write-Host ""
    Write-Host "翻译说明:"
    Write-Host "  1. 翻译 translation-template 目录中的 zh-CN.json"
    Write-Host "  2. 只修改 JSON 的 value，不要修改 key"
    Write-Host "  3. 不要删除 {count}、{name}、%s、<b>...</b> 等占位符"
    Write-Host "  4. 翻译完成后放到 translated-zh-CN 目录"
    Write-Host "  5. 然后运行安装中文语言包.bat 重新安装"
}

$scriptArgs = @()
if ($Uninstall) {
    $scriptArgs += "-Uninstall"
}
if ($Extract) {
    $scriptArgs += "-Extract"
}
if ($TranslationOnly) {
    $scriptArgs += "-TranslationOnly"
}
if ($NoRestart) {
    $scriptArgs += "-NoRestart"
}
if ($PauseAtEnd) {
    $scriptArgs += "-PauseAtEnd"
}

Ensure-Administrator -Arguments $scriptArgs

$exitCode = 0
try {
    if ($Extract) {
        Extract-EnglishFiles
    }
    elseif ($Uninstall) {
        Uninstall-LanguagePack
    }
    else {
        Install-LanguagePack
    }
}
catch {
    Write-Host ""
    Write-Host "[错误] $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
}
finally {
    Wait-BeforeExit
}

exit $exitCode
