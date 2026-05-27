@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%LanguagePack.ps1"
set "PATCH_SCRIPT=%SCRIPT_DIR%patch-hardcoded-strings.js"
set "RESTORE_SCRIPT=%SCRIPT_DIR%restore-hardcoded-strings.js"
set "PS_EXE=%SystemRoot%System32WindowsPowerShell1.0powershell.exe"
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

:FULL_INSTALL
echo.
echo === Step 1/2: Installing language pack ===
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -NoRestart -PauseAtEnd
if errorlevel 1 (echo [ERROR] Failed & pause & goto MENU)
echo.
echo === Step 2/2: Patching hardcoded English strings ===
node "%PATCH_SCRIPT%"
if errorlevel 1 (echo [WARN] JS patch failed, check Node.js & pause & goto MENU)
echo.
echo === Done! Please restart Claude Desktop ===
pause
goto MENU

:LANG_ONLY
echo.
echo === Installing language pack ===
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -PauseAtEnd
if errorlevel 1 (echo [ERROR] Failed & pause & goto MENU)
echo.
echo === Done! Please restart Claude Desktop ===
pause
goto MENU

:UNINSTALL
echo.
echo === Uninstalling language pack ===
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Uninstall -PauseAtEnd
if errorlevel 1 (echo [ERROR] Failed & pause & goto MENU)
echo.
echo === Language pack uninstalled ===
pause
goto MENU

:RESTORE_ALL
echo.
echo === Step 1/2: Uninstalling language pack ===
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Uninstall -NoRestart -PauseAtEnd
if errorlevel 1 (echo [ERROR] Failed & pause & goto MENU)
echo.
echo === Step 2/2: Restoring JS patch ===
node "%RESTORE_SCRIPT%"
if errorlevel 1 (echo [WARN] Restore failed & pause & goto MENU)
echo.
echo === All changes reverted! Please restart Claude Desktop ===
pause
goto MENU

:EXIT
endlocal
exit /b 0
