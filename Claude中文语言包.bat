@echo off
setlocal
chcp 65001 >nul 2>&1

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%LanguagePack.ps1"
set "PATCH_SCRIPT=%SCRIPT_DIR%patch-hardcoded-strings.js"
set "RESTORE_SCRIPT=%SCRIPT_DIR%restore-hardcoded-strings.js"
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS_EXE%" set "PS_EXE=powershell.exe"

:MENU
cls
echo.
echo  ╔══════════════════════════════════════════╗
echo  ║     Claude Desktop 简体中文语言包        ║
echo  ╠══════════════════════════════════════════╣
echo  ║                                          ║
echo  ║   1. 完整安装（翻译 + 界面补丁）         ║
echo  ║      安装语言包并修补硬编码英文字符串     ║
echo  ║                                          ║
echo  ║   2. 仅安装语言包                        ║
echo  ║      只替换翻译文件，不修补 JS            ║
echo  ║                                          ║
echo  ║   3. 卸载语言包                          ║
echo  ║      删除翻译文件，恢复语言注册           ║
echo  ║                                          ║
echo  ║   4. 还原所有                            ║
echo  ║      卸载语言包 + 还原硬编码字符串补丁    ║
echo  ║                                          ║
echo  ║   0. 退出                                ║
echo  ║                                          ║
echo  ╚══════════════════════════════════════════╝
echo.
set /p CHOICE=请选择 [0-4]:

if "%CHOICE%"=="1" goto FULL_INSTALL
if "%CHOICE%"=="2" goto LANG_ONLY
if "%CHOICE%"=="3" goto UNINSTALL
if "%CHOICE%"=="4" goto RESTORE_ALL
if "%CHOICE%"=="0" goto EXIT
echo 无效选择，请重试
pause
goto MENU

:FULL_INSTALL
echo.
echo === 步骤 1/2: 安装语言包 ===
if not exist "%PS_SCRIPT%" (
    echo [错误] 未找到 LanguagePack.ps1
    pause
    goto MENU
)
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -NoRestart -PauseAtEnd
if errorlevel 1 (
    echo [错误] 语言包安装失败
    pause
    goto MENU
)
echo.
echo === 步骤 2/2: 修补硬编码英文字符串 ===
if not exist "%PATCH_SCRIPT%" (
    echo [警告] 未找到 patch-hardcoded-strings.js，跳过界面补丁
    pause
    goto MENU
)
node "%PATCH_SCRIPT%"
if errorlevel 1 (
    echo [警告] 界面补丁失败，请确认 Node.js 已安装
    pause
    goto MENU
)
echo.
echo === 完整安装完成，请重启 Claude Desktop ===
pause
goto MENU

:LANG_ONLY
echo.
echo === 安装语言包 ===
if not exist "%PS_SCRIPT%" (
    echo [错误] 未找到 LanguagePack.ps1
    pause
    goto MENU
)
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -PauseAtEnd
if errorlevel 1 (
    echo [错误] 语言包安装失败
    pause
    goto MENU
)
echo.
echo === 语言包安装完成 ===
pause
goto MENU

:UNINSTALL
echo.
echo === 卸载语言包 ===
if not exist "%PS_SCRIPT%" (
    echo [错误] 未找到 LanguagePack.ps1
    pause
    goto MENU
)
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Uninstall -PauseAtEnd
if errorlevel 1 (
    echo [错误] 卸载失败
    pause
    goto MENU
)
echo.
echo === 语言包已卸载 ===
pause
goto MENU

:RESTORE_ALL
echo.
echo === 步骤 1/2: 卸载语言包 ===
if not exist "%PS_SCRIPT%" (
    echo [错误] 未找到 LanguagePack.ps1
    pause
    goto MENU
)
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Uninstall -NoRestart -PauseAtEnd
if errorlevel 1 (
    echo [错误] 卸载失败
    pause
    goto MENU
)
echo.
echo === 步骤 2/2: 还原硬编码字符串补丁 ===
if not exist "%RESTORE_SCRIPT%" (
    echo [警告] 未找到 restore-hardcoded-strings.js，跳过
    pause
    goto MENU
)
node "%RESTORE_SCRIPT%"
if errorlevel 1 (
    echo [警告] 还原失败
    pause
    goto MENU
)
echo.
echo === 所有更改已还原，请重启 Claude Desktop ===
pause
goto MENU

:EXIT
endlocal
exit /b 0
