[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$TranslationOnly,
    [switch]$NoRestart,
    [switch]$PauseAtEnd
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ============================================================================
# 嵌入的翻译数据（base64 + gzip）
# 由 build-exe.ps1 在构建时注入翻译数据（替换下方变量赋值中的占位符）
# ============================================================================
$TranslationsBlob = "@@TRANSLATIONS_BLOB@@"

# ============================================================================
# 路径初始化
# ============================================================================
$script:packDir = Join-Path ([System.IO.Path]::GetTempPath()) "claude-zh-cn-exe-pack"
$backupDir = Join-Path ([System.IO.Path]::GetTempPath()) "claude-zh-cn-backup"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

# ============================================================================
# 解压嵌入的翻译数据到临时目录
# ============================================================================
function Expand-Translations {
    if ($TranslationsBlob.Length -lt 100) {
        Write-Host "[错误] 翻译数据未嵌入（这是模板文件，请用 build-exe.ps1 构建）" -ForegroundColor Red
        exit 1
    }

    if (Test-Path -LiteralPath $script:packDir) {
        Remove-Item -LiteralPath $script:packDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    [System.IO.Directory]::CreateDirectory($script:packDir) | Out-Null

    try {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        $bytes = [System.Convert]::FromBase64String($TranslationsBlob)
        $ms = New-Object System.IO.MemoryStream(,$bytes)
        $zip = New-Object System.IO.Compression.ZipArchive($ms, [System.IO.Compression.ZipArchiveMode]::Read)

        $fileCount = 0
        foreach ($entry in $zip.Entries) {
            $targetPath = Join-Path $script:packDir $entry.FullName
            $parent = Split-Path -Parent $targetPath
            if ($parent) { [System.IO.Directory]::CreateDirectory($parent) | Out-Null }
            $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
            $content = $reader.ReadToEnd()
            $reader.Close()
            [System.IO.File]::WriteAllText($targetPath, $content, $utf8NoBom)
            $fileCount++
        }
        $zip.Dispose()
        $ms.Close()
        Write-Host "已释放 $fileCount 个翻译文件" -ForegroundColor DarkGray
    }
    catch {
        Write-Host "[错误] 解压翻译数据失败: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

function Cleanup-TempPack {
    if ($script:packDir -and (Test-Path -LiteralPath $script:packDir)) {
        Remove-Item -LiteralPath $script:packDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# 管理员权限
# ============================================================================
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

    $exePath = [Environment]::GetCommandLineArgs()[0]
    if (-not $exePath -or -not (Test-Path -LiteralPath $exePath)) {
        $exePath = $MyInvocation.MyCommand.Path
    }
    if (-not $exePath) {
        Write-Host "[错误] 无法确定可执行文件路径，请以管理员身份运行" -ForegroundColor Red
        exit 1
    }

    $argumentList = @()
    foreach ($a in $Arguments) { $argumentList += $a }

    try {
        Start-Process -FilePath $exePath -Verb RunAs -Wait -ArgumentList $argumentList | Out-Null
    }
    catch {
        Write-Host "[错误] 需要管理员权限才能运行" -ForegroundColor Red
    }
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

# ============================================================================
# 查找 Claude Desktop
# ============================================================================
function Find-ClaudePath {
    try {
        $pkg = Get-AppxPackage -Name Claude -ErrorAction Stop |
            Sort-Object Version -Descending |
            Select-Object -First 1
        if ($pkg -and $pkg.InstallLocation -and (Test-Path -LiteralPath $pkg.InstallLocation)) {
            return [pscustomobject]@{
                Path = [string]$pkg.InstallLocation
                Version = [string]$pkg.Version.ToString()
            }
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
                # Extract version from folder name: Claude_1.28929.0.0_x64__pzs8sxrjxfjjc
                $ver = ""
                if ($deployment.PSChildName -match "Claude_(\d+\.\d+\.\d+\.\d+)") { $ver = $Matches[1] }
                return [pscustomobject]@{ Path = [string]$candidate; Version = [string]$ver }
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
            $ver = ""
            if ($candidate.Name -match "Claude_(\d+\.\d+\.\d+\.\d+)") { $ver = $Matches[1] }
            return [pscustomobject]@{ Path = [string]$candidate.FullName; Version = [string]$ver }
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

# ============================================================================
# JS 语言注册补丁
# ============================================================================
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
        Where-Object { $_.Length -lt 10MB }
    if (-not $jsFiles) {
        Write-Host "  [警告] 未找到 JS 文件，跳过 JS 补丁" -ForegroundColor Yellow
        return $false
    }

    $exactOldArr = '["en-US","de-DE","fr-FR","ko-KR","ja-JP","es-419","es-ES","it-IT","hi-IN","pt-BR","id-ID"]'
    $exactNewArr = '["en-US","de-DE","fr-FR","ko-KR","ja-JP","es-419","es-ES","it-IT","hi-IN","pt-BR","id-ID","zh-CN"]'
    $exactOldObj = ',"id-ID":"id"}'
    $exactNewObj = ',"id-ID":"id","zh-CN":"zh"}'
    $regexObj = [regex]'((?:\w+)=\{"en-US":"[^"]+"(?:,"[^"]+":")[^"]*"),?\}'
    $regexArr = [regex]'((?:\w+)=\["en-US"(?:,"[^"]+")*),?\]'

    $patched = $false

    foreach ($jsFile in $jsFiles) {
        Grant-WriteAccess -Path $jsFile.FullName
        $content = [System.IO.File]::ReadAllText($jsFile.FullName)
        if (-not $content.Contains('"en-US"')) { continue }
        if ($content -match '\w+=\["en-US"(?:,"[^"]+")*,"zh-CN"(?:,"[^"]+")*]' -and
            $content -match '\w+=\{"en-US":"[^"]+"[^}]*"zh-CN":"[^"]+"[^}]*}') {
            Write-Host "  已注册: $($jsFile.Name)"
            $patched = $true
            continue
        }

        Backup-File -Path $jsFile.FullName
        $filePatched = $false

        if ($content.Contains($exactOldArr)) {
            $content = $content.Replace($exactOldArr, $exactNewArr)
            Write-Host "  JS补丁已应用(数组): $($jsFile.Name)"
            $filePatched = $true
        }
        if ($content.Contains($exactOldObj)) {
            $content = $content.Replace($exactOldObj, $exactNewObj)
            Write-Host "  JS补丁已应用(对象): $($jsFile.Name)"
            $filePatched = $true
        }
        if ($filePatched) {
            Write-Utf8File -Path $jsFile.FullName -Content $content
            $patched = $true
            continue
        }

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

        if ($content.Contains('"de-DE"') -and $content.Contains('"id-ID"')) {
            Write-Host "  [提示] 未匹配到语言列表: $($jsFile.Name)（正常，该文件格式不同，不影响安装）" -ForegroundColor DarkGray
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
        Where-Object { $_.Length -lt 10MB }
    $exactOldArr = '["en-US","de-DE","fr-FR","ko-KR","ja-JP","es-419","es-ES","it-IT","hi-IN","pt-BR","id-ID","zh-CN"]'
    $exactNewArr = '["en-US","de-DE","fr-FR","ko-KR","ja-JP","es-419","es-ES","it-IT","hi-IN","pt-BR","id-ID"]'
    $exactOldObj = ',"id-ID":"id","zh-CN":"zh"}'
    $exactNewObj = ',"id-ID":"id"}'
    $regexObj = [regex]'((?:\w+)=\{(?:"[^"]+":"[^"]+",)+)"zh-CN":"[^"]+",?\}'
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
        if (-not $content.Contains('"zh-CN"')) { continue }

        $filePatched = $false
        if ($content.Contains($exactOldArr)) {
            $content = $content.Replace($exactOldArr, $exactNewArr)
            Write-Host "  语言注册已恢复(数组): $($jsFile.Name)"
            $filePatched = $true
        }
        if ($content.Contains($exactOldObj)) {
            $content = $content.Replace($exactOldObj, $exactNewObj)
            Write-Host "  语言注册已恢复(对象): $($jsFile.Name)"
            $filePatched = $true
        }
        if ($filePatched) {
            Write-Utf8File -Path $jsFile.FullName -Content $content
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

# ============================================================================
# 硬编码字符串补丁（仅旧版本）
# ============================================================================
function Patch-HardcodedStrings {
    param(
        [Parameter(Mandatory = $true)][string]$ResourcesPath
    )
    $assetsDir = Join-Path $ResourcesPath "ion-dist\assets\v1"
    if (-not (Test-Path -LiteralPath $assetsDir -PathType Container)) { return }

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
        @{ Old = '"No archived tasks."'; New = '"没有已归档任务。"' }
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

    $reversals = @(
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
        @{ Old = 'code:"新建会话"'; New = 'code:"New session"' },
        @{ Old = 'code:"新建代码会话"'; New = 'code:"New code session"' },
        @{ Old = 'cowork:"新任务"'; New = 'cowork:"New task"' },
        @{ Old = 'chat:"新对话"'; New = 'chat:"New chat"' },
        @{ Old = 'newTask:{defaultMessage:"新任务"'; New = 'newTask:{defaultMessage:"New task"' },
        @{ Old = 'newRoutine:{defaultMessage:"新建代码会话"'; New = 'newRoutine:{defaultMessage:"New code session"' },
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
        @{ Old = '"重试。"'; New = '"Try again."' }
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

# ============================================================================
# 配置 / 缓存
# ============================================================================
function Test-IsNewUserDataLayout {
    param([Parameter(Mandatory = $true)][string]$Version)
    return ([version]$Version -ge [version]"1.15000.0.0")
}

function Test-UseHardcodedStrings {
    param([Parameter(Mandatory = $true)][string]$TranslationVersion)
    return @("1.12603.1.0", "1.13576.0.0") -contains $TranslationVersion
}

function Get-ClaudeConfigPaths {
    param([Parameter(Mandatory = $true)][string]$Version)
    $packageBase = Join-Path ${env:LOCALAPPDATA} "Packages\Claude_pzs8sxrjxfjjc"
    if (Test-IsNewUserDataLayout -Version $Version) {
        return @(
            (Join-Path ${env:LOCALAPPDATA} "Claude-3p\config.json"),
            (Join-Path ${env:LOCALAPPDATA} "Claude\config.json")
        ) | Select-Object -Unique
    }
    return @(
        (Join-Path $packageBase "LocalCache\Roaming\Claude\config.json"),
        (Join-Path $packageBase "LocalCache\Roaming\Claude-3p\config.json"),
        (Join-Path ${env:APPDATA} "Claude\config.json")
    ) | Select-Object -Unique
}

function Update-Config {
    param(
        [Parameter(Mandatory = $true)][string]$Locale,
        [Parameter(Mandatory = $true)][string]$Version
    )
    $configPaths = Get-ClaudeConfigPaths -Version $Version
    foreach ($configPath in $configPaths) {
        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { continue }
        try {
            $raw = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
            $config = $raw | ConvertFrom-Json
            if ($config.PSObject.Properties.Name -contains "locale") {
                $config.locale = $Locale
            } else {
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

function Clear-ClaudeRuntimeCache {
    param([Parameter(Mandatory = $true)][string]$Version)
    $cacheNames = @("Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "Session Storage", "fcache")
    $packageBase = Join-Path ${env:LOCALAPPDATA} "Packages\Claude_pzs8sxrjxfjjc"
    if (Test-IsNewUserDataLayout -Version $Version) {
        $cacheBases = @(
            (Join-Path ${env:LOCALAPPDATA} "Claude-3p"),
            (Join-Path ${env:LOCALAPPDATA} "Claude")
        ) | Select-Object -Unique
    } else {
        $cacheBases = @(
            (Join-Path $packageBase "LocalCache\Roaming\Claude"),
            (Join-Path $packageBase "LocalCache\Roaming\Claude-3p")
        ) | Select-Object -Unique
    }
    foreach ($base in $cacheBases) {
        if (-not (Test-Path -LiteralPath $base -PathType Container)) { continue }
        try {
            $baseResolved = (Resolve-Path -LiteralPath $base).Path
            foreach ($name in $cacheNames) {
                $target = Join-Path $baseResolved $name
                if (-not (Test-Path -LiteralPath $target)) { continue }
                $resolved = (Resolve-Path -LiteralPath $target).Path
                if ($resolved -like "$baseResolved*") {
                    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Host "  已清理缓存: $name"
                }
            }
        }
        catch {
            Write-Host "  [警告] 清理缓存失败: $base ($($_.Exception.Message))" -ForegroundColor Yellow
        }
    }
}

# ============================================================================
# Claude 启动
# ============================================================================
function Get-ClaudeApplicationId {
    param([Parameter(Mandatory = $true)][string]$ClaudePath)
    $manifestPath = Join-Path $ClaudePath "AppxManifest.xml"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $null }
    try {
        [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
        $application = @($manifest.Package.Applications.Application | Select-Object -First 1)[0]
        if ($application -and $application.Id) { return [string]$application.Id }
    } catch {}
    return $null
}

function Get-ClaudePackageFamilyName {
    param([Parameter(Mandatory = $true)][string]$ClaudePath)
    try {
        $resolvedClaudePath = [System.IO.Path]::GetFullPath($ClaudePath).TrimEnd("\")
        $pkg = Get-AppxPackage -Name Claude -ErrorAction Stop |
            Sort-Object Version -Descending |
            Where-Object {
                $_.InstallLocation -and
                ([System.IO.Path]::GetFullPath($_.InstallLocation).TrimEnd("\") -ieq $resolvedClaudePath)
            } |
            Select-Object -First 1
        if ($pkg -and $pkg.PackageFamilyName) { return [string]$pkg.PackageFamilyName }
    } catch {}
    try {
        [xml]$manifest = Get-Content -LiteralPath (Join-Path $ClaudePath "AppxManifest.xml") -Raw
        $identityName = [string]$manifest.Package.Identity.Name
        $folderName = Split-Path -Leaf $ClaudePath
        if ($identityName -and ($folderName -match "__([^_\\]+)$")) {
            return "$identityName`_$($Matches[1])"
        }
    } catch {}
    return $null
}

function Get-ClaudeAppUserModelId {
    param([Parameter(Mandatory = $true)][string]$ClaudePath)
    $packageFamilyName = Get-ClaudePackageFamilyName -ClaudePath $ClaudePath
    $applicationId = Get-ClaudeApplicationId -ClaudePath $ClaudePath
    if ($packageFamilyName -and $applicationId) { return "$packageFamilyName!$applicationId" }
    return $null
}

function Start-ClaudeWithExplorer {
    param([Parameter(Mandatory = $true)][string]$Target)
    try {
        $argument = $Target
        if ($Target -notlike "shell:*") { $argument = "`"$Target`"" }
        Start-Process -FilePath "explorer.exe" -ArgumentList $argument | Out-Null
        return $true
    } catch { return $false }
}

function Start-ClaudeWithWmi {
    param([Parameter(Mandatory = $true)][string]$ExePath)
    try {
        $workingDirectory = Split-Path -Parent $ExePath
        $result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
            CommandLine      = "`"$ExePath`""
            CurrentDirectory = $workingDirectory
        }
        return ($result.ReturnValue -eq 0)
    } catch { return $false }
}

function Start-ClaudeDetached {
    param([Parameter(Mandatory = $true)][string]$ClaudePath)
    $appUserModelId = Get-ClaudeAppUserModelId -ClaudePath $ClaudePath
    if ($appUserModelId) {
        if (Start-ClaudeWithExplorer -Target "shell:AppsFolder\$appUserModelId") { return $true }
    }
    $exe = Join-Path $ClaudePath "app\claude.exe"
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { return $false }
    if (Start-ClaudeWithExplorer -Target $exe) { return $true }
    return (Start-ClaudeWithWmi -ExePath $exe)
}

function Stop-ClaudeProcess {
    Write-Host "  正在关闭 Claude Desktop..."
    try { Stop-Process -Name "claude" -Force -ErrorAction SilentlyContinue } catch {}
    Start-Sleep -Seconds 3
    Write-Host "  Claude Desktop 已关闭"
}

function Restart-Claude {
    $claudeFound = Find-ClaudePath
    if (-not $claudeFound) { return }
    if (Start-ClaudeDetached -ClaudePath $claudeFound.Path) {
        Start-Sleep -Seconds 3
        Write-Host "Claude Desktop 已重启"
    } else {
        Write-Host "  [警告] 自动启动 Claude 失败，请手动打开 Claude Desktop" -ForegroundColor Yellow
    }
}

# ============================================================================
# 翻译文件匹配
# ============================================================================
function Get-RequiredTranslationFiles {
    param([Parameter(Mandatory = $true)][string]$InstalledVersion)

    $installed = [version]$InstalledVersion

    $available = Get-ChildItem -LiteralPath $script:packDir -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
        ForEach-Object { [pscustomobject]@{ Name = $_.Name; Path = $_.FullName; Ver = [version]$_.Name } } |
        Sort-Object Ver -Descending

    if (-not $available) {
        throw "翻译数据释放失败：临时目录中没有找到任何版本"
    }

    $matched = $available | Where-Object { $_.Ver -eq $installed } | Select-Object -First 1
    if (-not $matched) {
        $matched = $available | Where-Object { $_.Ver -lt $installed } | Select-Object -First 1
    }
    if (-not $matched) {
        $matched = $available | Sort-Object Ver | Select-Object -First 1
    }

    $versionDir = $matched.Path
    $script:ActualTranslationVersion = $matched.Name

    if ($matched.Name -eq $InstalledVersion) {
        Write-Host "  翻译版本: $($matched.Name) (精确匹配)" -ForegroundColor Green
        $script:VersionMismatch = $false
    } else {
        $script:VersionMismatch = $true
        Write-Host ""
        Write-Host "  ┌─────────────────────────────────────────────────────┐" -ForegroundColor Yellow
        Write-Host "  │ [注意] 当前 Claude 版本: $InstalledVersion" -ForegroundColor Yellow
        Write-Host "  │        实际使用翻译:   $($matched.Name)" -ForegroundColor Yellow
        Write-Host "  │ 如有适配问题请反馈: https://github.com/ICERainbow666/claude-desktop-zh-cn/issues" -ForegroundColor Yellow
        Write-Host "  └─────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    }

    $required = @(
        [pscustomobject]@{ Name = "ion-dist"; Path = (Join-Path $versionDir "ion-dist\zh-CN.json") },
        [pscustomobject]@{ Name = "desktop-shell"; Path = (Join-Path $versionDir "desktop-shell\zh-CN.json") },
        [pscustomobject]@{ Name = "dynamic"; Path = (Join-Path $versionDir "ion-dist\dynamic\zh-CN.json") }
    )

    return $required
}

function Resolve-ClaudeResources {
    $found = Find-ClaudePath
    if (-not $found) { throw "未检测到 Claude Desktop" }
    $resourcesPath = Get-ResourcesPath -ClaudePath $found.Path
    if (-not $resourcesPath) { throw "未找到 resources 目录" }
    return [pscustomobject]@{
        ClaudePath = $found.Path
        Version = $found.Version
        ResourcesPath = $resourcesPath
    }
}

# ============================================================================
# 安装 / 卸载
# ============================================================================
function Install-LanguagePack {
    Write-Host ""
    Write-Host "=== Claude Desktop 中文语言包安装 ==="
    Write-Host ""

    $totalSteps = 7

    Write-Host ""
    Write-Host "[1/$totalSteps] 关闭 Claude Desktop..."
    Stop-ClaudeProcess

    Write-Host ""
    Write-Host "[2/$totalSteps] 查找 Claude Desktop..."
    $resolved = Resolve-ClaudeResources
    Write-Host "  Claude: $($resolved.ClaudePath)"
    Write-Host "  版本:  $($resolved.Version)"

    $required = Get-RequiredTranslationFiles -InstalledVersion $resolved.Version
    $useHardcodedStrings = (-not $TranslationOnly) -and (Test-UseHardcodedStrings -TranslationVersion $script:ActualTranslationVersion)
    if ($useHardcodedStrings) { Write-Host "  硬编码补丁: 启用" }
    else { Write-Host "  硬编码补丁: 跳过" }

    foreach ($item in $required) {
        if (-not (Test-Path -LiteralPath $item.Path -PathType Leaf)) {
            throw "缺少翻译文件: $($item.Path)"
        }
        $sizeKb = [math]::Floor((Get-Item -LiteralPath $item.Path).Length / 1KB)
        Write-Host ("  {0}: OK ({1}KB)" -f $item.Name, $sizeKb)
    }

    Write-Host ""
    Write-Host "[3/$totalSteps] 获取写入权限..."
    try {
        $claudeParent = Split-Path -Parent $resolved.ClaudePath
        $appPath = Join-Path $resolved.ClaudePath "app"
        $criticalPaths = @($claudeParent, $resolved.ClaudePath, $appPath, $resolved.ResourcesPath)
        foreach ($path in $criticalPaths) {
            if (Test-Path -LiteralPath $path) {
                & takeown.exe "/f" $path "/a" | Out-Null
                & icacls.exe $path "/grant" "BUILTIN\Administrators:(OI)(CI)(F)" "/c" | Out-Null
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
        foreach ($path in $pathsToGrant) { Grant-WriteAccess -Path $path }
        $assetsDir = Join-Path $resolved.ResourcesPath "ion-dist\assets\v1"
        if (Test-Path -LiteralPath $assetsDir -PathType Container) {
            Get-ChildItem -LiteralPath $assetsDir -Filter "*.js" -File |
                Where-Object { $_.Length -lt 10MB } |
                ForEach-Object { Grant-WriteAccess -Path $_.FullName }
        }
        Write-Host "  权限处理完成"
    }
    catch {
        Write-Host "  [错误] 获取写入权限失败: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "[4/$totalSteps] 安装翻译文件..."
    try {
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
    }
    catch {
        Write-Host "  [错误] 安装翻译文件失败: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "[5/$totalSteps] 注册中文语言..."
    try { [void](Patch-JsLanguage -ResourcesPath $resolved.ResourcesPath) }
    catch {
        Write-Host "  [错误] 注册语言失败: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "[6/$totalSteps] 处理硬编码字符串..."
    try {
        if ($useHardcodedStrings) { Patch-HardcodedStrings -ResourcesPath $resolved.ResourcesPath }
        else { Write-Host "  当前版本不需要硬编码字符串补丁" }
    }
    catch {
        Write-Host "  [错误] 替换硬编码字符串失败: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "[7/$totalSteps] 更新配置..."
    try {
        Update-Config -Locale "zh-CN" -Version $resolved.Version
        Clear-ClaudeRuntimeCache -Version $resolved.Version
    }
    catch {
        Write-Host "  [错误] 更新配置失败: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "=== 语言包安装完成 ==="
    if ($NoRestart) {
        Write-Host "请手动重启 Claude Desktop 使更改生效。"
    } else {
        Write-Host ""
        Restart-Claude
    }
}

function Uninstall-LanguagePack {
    Write-Host ""
    Write-Host "=== Claude Desktop 中文语言包卸载 ==="
    Write-Host ""

    Write-Host "[1/6] 关闭 Claude Desktop..."
    Stop-ClaudeProcess

    Write-Host ""
    Write-Host "[2/6] 查找 Claude Desktop..."
    $resolved = Resolve-ClaudeResources
    Write-Host "  Claude: $($resolved.ClaudePath)"
    Write-Host "  版本:  $($resolved.Version)"
    [void](Get-RequiredTranslationFiles -InstalledVersion $resolved.Version)
    $useHardcodedStrings = Test-UseHardcodedStrings -TranslationVersion $script:ActualTranslationVersion
    if ($useHardcodedStrings) { Write-Host "  硬编码还原: 启用" }
    else { Write-Host "  硬编码还原: 跳过" }

    Write-Host ""
    Write-Host "[3/6] 删除翻译文件..."
    try {
        $claudeParent = Split-Path -Parent $resolved.ClaudePath
        $appPath = Join-Path $resolved.ClaudePath "app"
        $criticalPaths = @($claudeParent, $resolved.ClaudePath, $appPath, $resolved.ResourcesPath)
        foreach ($path in $criticalPaths) {
            if (Test-Path -LiteralPath $path) {
                & takeown.exe "/f" $path "/a" | Out-Null
                & icacls.exe $path "/grant" "BUILTIN\Administrators:(OI)(CI)(F)" "/c" | Out-Null
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
    }
    catch {
        Write-Host "  [错误] 删除翻译文件失败: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "[4/6] 恢复语言注册..."
    try { Unpatch-JsLanguage -ResourcesPath $resolved.ResourcesPath }
    catch {
        Write-Host "  [错误] 恢复语言注册失败: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "[5/6] 还原硬编码字符串..."
    try {
        if ($useHardcodedStrings) { Unpatch-HardcodedStrings -ResourcesPath $resolved.ResourcesPath }
        else { Write-Host "  当前版本不需要还原硬编码字符串" }
    }
    catch {
        Write-Host "  [错误] 还原硬编码字符串失败: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "[6/6] 恢复配置..."
    try {
        Update-Config -Locale "en-US" -Version $resolved.Version
        Clear-ClaudeRuntimeCache -Version $resolved.Version
    }
    catch {
        Write-Host "  [错误] 恢复配置失败: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "=== 语言包卸载完成 ==="
    if ($NoRestart) {
        Write-Host "请手动重启 Claude Desktop 使更改生效。"
    } else {
        Write-Host ""
        Restart-Claude
    }
}

# ============================================================================
# 交互菜单
# ============================================================================
function Show-Menu {
    while ($true) {
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Cyan
        Write-Host "  Claude Desktop 中文语言包" -ForegroundColor Cyan
        Write-Host "============================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  1. 安装语言包"
        Write-Host "  2. 卸载语言包"
        Write-Host "  0. 退出"
        Write-Host ""
        $choice = Read-Host "请选择"

        switch ($choice) {
            "1" {
                $exitCode = 0
                try { Install-LanguagePack }
                catch {
                    Write-Host ""
                    Write-Host "[错误] $($_.Exception.Message)" -ForegroundColor Red
                }
                Write-Host ""
                Write-Host "按任意键返回菜单..." -ForegroundColor DarkGray
                [void]($host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown"))
            }
            "2" {
                $exitCode = 0
                try { Uninstall-LanguagePack }
                catch {
                    Write-Host ""
                    Write-Host "[错误] $($_.Exception.Message)" -ForegroundColor Red
                }
                Write-Host ""
                Write-Host "按任意键返回菜单..." -ForegroundColor DarkGray
                [void]($host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown"))
            }
            "0" { return }
            default {
                Write-Host "  无效选择，请重试" -ForegroundColor Yellow
            }
        }
    }
}

# ============================================================================
# 主流程
# ============================================================================
$scriptArgs = @()
if ($Install) { $scriptArgs += "-Install" }
if ($Uninstall) { $scriptArgs += "-Uninstall" }
if ($TranslationOnly) { $scriptArgs += "-TranslationOnly" }
if ($NoRestart) { $scriptArgs += "-NoRestart" }
if ($PauseAtEnd) { $scriptArgs += "-PauseAtEnd" }

Ensure-Administrator -Arguments $scriptArgs

Expand-Translations

try {
    if ($Uninstall) {
        Uninstall-LanguagePack
        Wait-BeforeExit
    }
    elseif ($Install) {
        Install-LanguagePack
        Wait-BeforeExit
    }
    else {
        Show-Menu
    }
}
catch {
    Write-Host ""
    Write-Host "[错误] $($_.Exception.Message)" -ForegroundColor Red
    Wait-BeforeExit
}
finally {
    Cleanup-TempPack
}
