@echo off
:: Self-elevate to admin if not already
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

setlocal
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%LanguagePack.ps1"
set "PATCH_SCRIPT=%SCRIPT_DIR%patch-hardcoded-strings.js"
set "RESTORE_SCRIPT=%SCRIPT_DIR%restore-hardcoded-strings.js"
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
echo   4. Restore Everything (Undo All Changes)
echo   0. Exit
echo.
set /p CHOICE=Select [0-4]:

if "%CHOICE%"=="1" goto FULL_INSTALL
if "%CHOICE%"=="2" goto LANG_ONLY
if "%CHOICE%"=="3" goto UNINSTALL
if "%CHOICE%"=="4" goto RESTORE_ALL
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

:CHECK_JS_PATCHED
set "JS_PATCHED=0"
for /f "delims=" %%f in ('dir /s /b "C:\Program Files\WindowsApps\Claude_*\app\resources\ion-dist\assets\v1\*.bak" 2^>nul') do set "JS_PATCHED=1"
goto :eof

:FULL_INSTALL
echo.
echo === Step 0/3: Closing Claude Desktop ===
call :KILL_CLAUDE
echo.
echo === Step 1/3: Installing language pack ===
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -NoRestart
if errorlevel 1 (echo [ERROR] Failed & pause & goto MENU)
echo.
echo === Step 2/3: Patching hardcoded English strings ===
node "%PATCH_SCRIPT%"
if errorlevel 1 (echo [WARN] JS patch failed, check Node.js & pause & goto MENU)
echo.
echo === Step 3/3: Starting Claude Desktop ===
call :START_CLAUDE
echo.
echo === Done!
timeout /t 3 /nobreak >nul
goto MENU

:LANG_ONLY
echo.
echo === Step 0/2: Closing Claude Desktop ===
call :KILL_CLAUDE
echo.
echo === Step 1/2: Installing language pack ===
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -NoRestart
if errorlevel 1 (echo [ERROR] Failed & pause & goto MENU)
echo.
echo === Step 2/2: Starting Claude Desktop ===
call :START_CLAUDE
echo.
echo === Done!
timeout /t 3 /nobreak >nul
goto MENU

:UNINSTALL
call :CHECK_JS_PATCHED
if "%JS_PATCHED%"=="1" (
    echo.
    echo [!] You used option 1 which modified the JS file.
    echo [!] Option 3 can only uninstall the language pack, but cannot restore the JS file.
    echo [!] Please use option 4 to fully restore everything.
    echo.
    pause
    goto MENU
)
echo.
echo === Step 0/2: Closing Claude Desktop ===
call :KILL_CLAUDE
echo.
echo === Step 1/2: Uninstalling language pack ===
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Uninstall -NoRestart
if errorlevel 1 (echo [ERROR] Failed & pause & goto MENU)
echo.
echo === Step 2/2: Starting Claude Desktop ===
call :START_CLAUDE
echo.
echo === Done!
timeout /t 3 /nobreak >nul
goto MENU

:RESTORE_ALL
call :CHECK_JS_PATCHED
echo.
echo === Step 0/3: Closing Claude Desktop ===
call :KILL_CLAUDE
echo.
echo === Step 1/3: Uninstalling language pack ===
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Uninstall -NoRestart
if errorlevel 1 (echo [ERROR] Failed & pause & goto MENU)
echo.
if "%JS_PATCHED%"=="1" (
    echo === Step 2/3: Restoring JS patch ===
    node "%RESTORE_SCRIPT%"
    if errorlevel 1 (echo [WARN] Restore failed & pause & goto MENU)
) else (
    echo === Step 2/3: No hardcoded UI text patch found, skipping ===
)
echo.
echo === Step 3/3: Starting Claude Desktop ===
call :START_CLAUDE
echo.
echo === All changes reverted!
timeout /t 3 /nobreak >nul
goto MENU

:EXIT
endlocal
exit /b 0
