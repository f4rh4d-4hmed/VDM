@echo off
setlocal enabledelayedexpansion
title VirusDownloader Extension & Integration Setup

set "SCRIPT_DIR=%~dp0"
set "APP_DIR=%SCRIPT_DIR%.."
if exist "%SCRIPT_DIR%extension\manifest.json" (
    set "APP_DIR=%SCRIPT_DIR%"
)

set "ACTION=install"
set "SILENT=0"

:parse_args
if "%~1"=="" goto run_action
if /i "%~1"=="/uninstall" set "ACTION=uninstall"
if /i "%~1"=="-uninstall" set "ACTION=uninstall"
if /i "%~1"=="/install" set "ACTION=install"
if /i "%~1"=="-install" set "ACTION=install"
if /i "%~1"=="/silent" set "SILENT=1"
if /i "%~1"=="-silent" set "SILENT=1"
if /i "%~1"=="/s" set "SILENT=1"
shift
goto parse_args

:run_action
REM Try running modern PowerShell engine first
where powershell >nul 2>nul
if %ERRORLEVEL% equ 0 (
    if "%SILENT%"=="1" (
        powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%install_extension.ps1" -Action %ACTION% -Silent -AppDir "%APP_DIR%" >nul 2>&1
    ) else (
        powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%install_extension.ps1" -Action %ACTION% -AppDir "%APP_DIR%"
    )
    if %ERRORLEVEL% equ 0 goto done
)

REM Fallback purely in Windows Batch & Reg command
set "EXT_ID=jdkegfbblbdneoeabighglhgkpfpebji"
set "EXE_PATH=%APP_DIR%\vdm.exe"
if not exist "%EXE_PATH%" set "EXE_PATH=%APP_DIR%\virus_download_manager.exe"
if not exist "%EXE_PATH%" set "EXE_PATH=%APP_DIR%\virusdownloader.exe"

if "%ACTION%"=="uninstall" (
    if "%SILENT%"=="0" echo [VirusDownloader] Removing browser extensions and protocols...
    reg delete "HKCU\Software\Classes\virusdownloader" /f >nul 2>&1
    reg delete "HKCU\Software\Google\Chrome\Extensions\%EXT_ID%" /f >nul 2>&1
    reg delete "HKCU\Software\Microsoft\Edge\Extensions\%EXT_ID%" /f >nul 2>&1
    reg delete "HKCU\Software\BraveSoftware\Brave-Browser\Extensions\%EXT_ID%" /f >nul 2>&1
    reg delete "HKCU\Software\Google\Chrome\NativeMessagingHosts\com.virusdownloader.host" /f >nul 2>&1
    reg delete "HKCU\Software\Microsoft\Edge\NativeMessagingHosts\com.virusdownloader.host" /f >nul 2>&1
    reg delete "HKCU\Software\Mozilla\NativeMessagingHosts\com.virusdownloader.host" /f >nul 2>&1
    if "%SILENT%"=="0" echo [VirusDownloader] Cleanup completed.
    goto done
)

if "%SILENT%"=="0" (
    echo ==========================================================
    echo        VirusDownloader Browser Extension & Protocol Setup
    echo ==========================================================
    echo.
    echo Installing integration for Chrome, Edge, Brave, and other browsers...
)

REM 1. Custom Protocol virusdownloader://
reg add "HKCU\Software\Classes\virusdownloader" /ve /d "URL:VirusDownloader Protocol" /f >nul 2>&1
reg add "HKCU\Software\Classes\virusdownloader" /v "URL Protocol" /d "" /f >nul 2>&1
if exist "%EXE_PATH%" (
    reg add "HKCU\Software\Classes\virusdownloader\DefaultIcon" /ve /d "\"%EXE_PATH%\",0" /f >nul 2>&1
    reg add "HKCU\Software\Classes\virusdownloader\shell\open\command" /ve /d "\"%EXE_PATH%\" \"%%1\"" /f >nul 2>&1
)

REM 2. Browser Extensions Registration
set "UPDATE_URL=http://127.0.0.1:9849/update.xml"
reg add "HKCU\Software\Google\Chrome\Extensions\%EXT_ID%" /v "update_url" /d "%UPDATE_URL%" /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Edge\Extensions\%EXT_ID%" /v "update_url" /d "%UPDATE_URL%" /f >nul 2>&1
reg add "HKCU\Software\BraveSoftware\Brave-Browser\Extensions\%EXT_ID%" /v "update_url" /d "%UPDATE_URL%" /f >nul 2>&1

REM 3. Extension Policies (ExtensionInstallForcelist)
reg add "HKCU\Software\Policies\Microsoft\Edge\ExtensionInstallForcelist" /v "1" /d "%EXT_ID%;%UPDATE_URL%" /f >nul 2>&1
reg add "HKCU\Software\Policies\Microsoft\Edge\ExtensionInstallSources" /v "1" /d "http://127.0.0.1:9849/*" /f >nul 2>&1
reg add "HKCU\Software\Policies\Google\Chrome\ExtensionInstallForcelist" /v "1" /d "%EXT_ID%;%UPDATE_URL%" /f >nul 2>&1
reg add "HKCU\Software\Policies\Google\Chrome\ExtensionInstallSources" /v "1" /d "http://127.0.0.1:9849/*" /f >nul 2>&1

if "%SILENT%"=="0" (
    echo.
    echo [OK] Extension and protocol configured successfully!
    echo Restart your browser to apply the integration.
    echo.
    pause
)

:done
endlocal
