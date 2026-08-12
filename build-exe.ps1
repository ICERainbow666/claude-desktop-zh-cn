<#
.SYNOPSIS
    构建 ClaudeChineseLangPack.exe（自包含单文件）
.DESCRIPTION
    1. 读取 translated-zh-CN/ 下所有版本的翻译 JSON
    2. 打包为单个 JSON -> gzip 压缩 -> base64 编码
    3. 将 base64 数据注入 LanguagePack-Standalone.ps1 的占位符
    4. 用 PS2EXE 编译为 ClaudeChineseLangPack.exe
#>
[CmdletBinding()]
param(
    [string]$OutputPath = ".\ClaudeChineseLangPack.exe",
    [string]$IconPath
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectDir

Write-Host "=== 构建 ClaudeChineseLangPack.exe ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1. 收集翻译文件
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "[1/4] 收集翻译文件..." -ForegroundColor Yellow

$packDir = Join-Path $projectDir "translated-zh-CN"
$versionDirs = Get-ChildItem -LiteralPath $packDir -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
    Sort-Object Name

if (-not $versionDirs) {
    throw "未在 translated-zh-CN/ 下找到版本目录"
}

$totalFiles = 0
$totalBytes = 0

foreach ($vDir in $versionDirs) {
    $ver = $vDir.Name
    $fileDefs = @(
        @{ Path = (Join-Path $vDir.FullName "ion-dist\zh-CN.json") },
        @{ Path = (Join-Path $vDir.FullName "desktop-shell\zh-CN.json") },
        @{ Path = (Join-Path $vDir.FullName "ion-dist\dynamic\zh-CN.json") }
    )
    foreach ($f in $fileDefs) {
        if (-not (Test-Path -LiteralPath $f.Path -PathType Leaf)) { continue }
        $totalFiles++
        $totalBytes += (Get-Item -LiteralPath $f.Path).Length
    }
    Write-Host "  $ver : OK"
}

Write-Host "  共 $totalFiles 个文件，原始大小 $([math]::Round($totalBytes/1MB, 2)) MB"

# ---------------------------------------------------------------------------
# 2. 打包为 zip + base64 编码（直接压缩文件内容，避免 JSON 双重转义）
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "[2/4] 压缩翻译数据..." -ForegroundColor Yellow

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$ms = New-Object System.IO.MemoryStream
$zip = New-Object System.IO.Compression.ZipArchive($ms, [System.IO.Compression.ZipArchiveMode]::Create)

foreach ($vDir in $versionDirs) {
    $ver = $vDir.Name
    $fileDefs = @(
        @{ Entry = "$ver/ion-dist/zh-CN.json";         Path = (Join-Path $vDir.FullName "ion-dist\zh-CN.json") },
        @{ Entry = "$ver/desktop-shell/zh-CN.json";    Path = (Join-Path $vDir.FullName "desktop-shell\zh-CN.json") },
        @{ Entry = "$ver/ion-dist/dynamic/zh-CN.json"; Path = (Join-Path $vDir.FullName "ion-dist\dynamic\zh-CN.json") }
    )
    foreach ($f in $fileDefs) {
        if (-not (Test-Path -LiteralPath $f.Path -PathType Leaf)) { continue }
        $content = [System.IO.File]::ReadAllText($f.Path, [System.Text.Encoding]::UTF8)
        $entry = $zip.CreateEntry($f.Entry, [System.IO.Compression.CompressionLevel]::Optimal)
        $writer = New-Object System.IO.StreamWriter($entry.Open(), [System.Text.UTF8Encoding]::new($false))
        $writer.Write($content)
        $writer.Close()
    }
}
$zip.Dispose()
$compressed = $ms.ToArray()
$ms.Close()

$blob = [System.Convert]::ToBase64String($compressed)
$blobSize = [math]::Round($blob.Length / 1MB, 2)
Write-Host "  zip: $([math]::Round($compressed.Length/1MB, 2)) MB -> base64: $blobSize MB"

# ---------------------------------------------------------------------------
# 3. 注入到 Standalone 脚本
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "[3/4] 生成独立脚本..." -ForegroundColor Yellow

$templatePath = Join-Path $projectDir "LanguagePack-Standalone.ps1"
$template = [System.IO.File]::ReadAllText($templatePath, [System.Text.Encoding]::UTF8)

$placeholder = '@@TRANSLATIONS_BLOB@@'
if (-not $template.Contains($placeholder)) {
    throw "LanguagePack-Standalone.ps1 中未找到占位符 $placeholder"
}

# 将 base64 字符串拆成多行（每行 200 字符），避免单行过长
$lineLen = 200
$blobLines = @()
for ($i = 0; $i -lt $blob.Length; $i += $lineLen) {
    $end = [Math]::Min($i + $lineLen, $blob.Length)
    $blobLines += $blob.Substring($i, $end - $i)
}
$blobMultiline = $blobLines -join "`n"

$filled = $template.Replace($placeholder, $blobMultiline)

$tempScript = Join-Path ([System.IO.Path]::GetTempPath()) "claude-langpack-build.ps1"
[System.IO.File]::WriteAllText($tempScript, $filled, [System.Text.UTF8Encoding]::new($false))
Write-Host "  临时脚本: $tempScript ($([math]::Round($filled.Length/1MB, 2)) MB)"

# ---------------------------------------------------------------------------
# 4. PS2EXE 编译
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "[4/4] 编译 EXE..." -ForegroundColor Yellow

# 确保 ps2exe 已安装
$ps2exe = Get-Module -ListAvailable ps2exe
if (-not $ps2exe) {
    Write-Host "  安装 ps2exe 模块..." -ForegroundColor DarkGray
    Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
    Import-Module ps2exe -Force
}

$outputFullPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $projectDir $OutputPath }

$ps2exeArgs = @{
    inputFile  = $tempScript
    outputFile = $outputFullPath
    requireAdmin = $true
    title      = "Claude Desktop 中文语言包"
    description = "Claude Desktop Simplified Chinese Language Pack"
    version    = "1.0.0"
    noConsole  = $false
}
if ($IconPath -and (Test-Path -LiteralPath $IconPath)) {
    $ps2exeArgs.iconFile = $IconPath
}

Write-Host "  调用 PS2EXE..."
Invoke-PS2EXE @ps2exeArgs

# 清理临时脚本
Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $outputFullPath) {
    $exeSize = [math]::Round((Get-Item -LiteralPath $outputFullPath).Length / 1MB, 2)
    Write-Host ""
    Write-Host "=== 构建完成 ===" -ForegroundColor Green
    Write-Host "  输出: $outputFullPath" -ForegroundColor Green
    Write-Host "  大小: $exeSize MB" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "=== 构建失败 ===" -ForegroundColor Red
    exit 1
}
