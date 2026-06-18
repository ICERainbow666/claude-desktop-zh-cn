@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%LanguagePack.ps1"
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS_EXE%" set "PS_EXE=powershell.exe"

:MENU
cls
echo.
echo  ============================================
echo       Claude Desktop Chinese Language Pack
echo  ============================================
echo.
echo   1. Full Install (Translation + JS Patch)
echo   2. Language Pack Only (Translation Only)
echo   3. Uninstall Language Pack
echo   0. Exit
echo.
set /p CHOICE=Select [0-3]:

if "%CHOICE%"=="1" goto FULL_INSTALL
if "%CHOICE%"=="2" goto LANG_ONLY
if "%CHOICE%"=="3" goto UNINSTALL
if "%CHOICE%"=="0" goto EXIT
echo Invalid choice
pause
goto MENU

:KILL_CLAUDE
echo.
echo [*] Closing Claude Desktop...
taskkill /IM Claude.exe /F >nul 2>&1
if not errorlevel 1 (
    echo [*] Claude Desktop closed. Waiting 3 seconds...
    timeout /t 3 /nobreak >nul
) else (
    echo [*] Claude Desktop is not running.
)
goto :eof

:START_CLAUDE
echo.
echo [*] Starting Claude Desktop...
"%PS_EXE%" -NoProfile -Command "Start-Process 'shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude'" >nul 2>&1
echo [*] Claude Desktop started.
goto :eof

:FULL_INSTALL
echo.
echo === Step 1/3: Closing Claude Desktop ===
call :KILL_CLAUDE
echo.
echo === Step 2/3: Installing language pack ===
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -NoRestart
if errorlevel 1 (echo [ERROR] Failed & pause & goto MENU)
echo.
echo === Step 3/3: Starting Claude Desktop ===
call :START_CLAUDE
echo.
echo === Done! Please set language to Chinese in Claude settings.
echo.
echo Press any key to return to menu...
pause >nul
goto MENU

:LANG_ONLY
echo.
echo === Step 1/3: Closing Claude Desktop ===
call :KILL_CLAUDE
echo.
echo === Step 2/3: Installing translation files ===
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -TranslationOnly -NoRestart
if errorlevel 1 (echo [ERROR] Failed & pause & goto MENU)
echo.
echo === Step 3/3: Starting Claude Desktop ===
call :START_CLAUDE
echo.
echo === Done! Please set language to Chinese in Claude settings.
echo.
echo Press any key to return to menu...
pause >nul
goto MENU

:UNINSTALL
echo.
echo === Step 1/3: Closing Claude Desktop ===
call :KILL_CLAUDE
echo.
echo === Step 2/3: Uninstalling language pack ===
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Uninstall -NoRestart
if errorlevel 1 (echo [ERROR] Failed & pause & goto MENU)
echo.
echo === Step 3/3: Starting Claude Desktop ===
call :START_CLAUDE
echo.
echo === Language pack uninstalled.
echo.
echo Press any key to return to menu...
pause >nul
goto MENU

:EXIT
endlocal
exit /b 0
