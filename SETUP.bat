@echo off
setlocal
title Dawnwalker Controller + Keyboard Fix
cls

echo ==========================================================
echo   DAWNWALKER CONTROLLER + KEYBOARD FIX
echo ==========================================================
echo.
echo   1. Install
echo   2. Uninstall This Fix
echo   3. Revert to Pre-Install Setup
echo   4. Exit
echo.
echo   F8 in-game = Toggle mouse ON / OFF
echo.
set /p choice=Choose 1, 2, 3, or 4: 

if "%choice%"=="1" goto install
if "%choice%"=="2" goto uninstall
if "%choice%"=="3" goto revert
if "%choice%"=="4" exit /b
goto invalid

:install
cls
echo ==========================================================
echo   INSTALL
echo ==========================================================
echo.
echo Blocks mouse input in Dawnwalker.
echo Keyboard and controllers stay enabled.
echo.
echo Close Dawnwalker before continuing.
echo.
pause
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Setup.ps1" -Mode Install
echo.
echo Press any key to close.
pause >nul
exit /b

:uninstall
cls
echo ==========================================================
echo   UNINSTALL THIS FIX
echo ==========================================================
echo.
echo Removes the Controller + Keyboard Fix.
echo.
echo If another mod is currently loaded through version_chain.dll,
echo Setup will warn you BEFORE changing the chain.
echo.
echo Close Dawnwalker before continuing.
echo.
pause
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Setup.ps1" -Mode Uninstall
echo.
echo Press any key to close.
pause >nul
exit /b

:revert
cls
echo ==========================================================
echo   REVERT TO PRE-INSTALL SETUP
echo ==========================================================
echo.
echo Restores the saved setup from BEFORE this fix was installed.
echo.
echo Use this if Compatibility Mode or DLL chaining caused problems.
echo.
echo Close Dawnwalker before continuing.
echo.
pause
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Setup.ps1" -Mode Revert
echo.
echo Press any key to close.
pause >nul
exit /b

:invalid
cls
echo Please choose 1, 2, 3, or 4.
echo.
pause
goto :eof
