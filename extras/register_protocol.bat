@echo off
REM ==============================================================================
REM VirusDownloader - URL Protocol Registration Script
REM
REM Registers the 'virusdownloader://' custom protocol scheme in the Windows Registry
REM so that browser extensions, external tools, and web links can invoke VirusDownloader.
REM ==============================================================================

setlocal

if /i "%~1"=="/uninstall" (
    echo [VirusDownloader] Removing virusdownloader:// protocol...
    reg delete "HKCU\Software\Classes\virusdownloader" /f >nul 2>&1
    echo [VirusDownloader] Protocol unregistered.
    goto done
)

set "APP_DIR=%~dp0.."
set "EXE_PATH=%APP_DIR%\virus_download_manager.exe"
if not exist "%EXE_PATH%" (
    set "EXE_PATH=%APP_DIR%\virusdownloader.exe"
)
if not exist "%EXE_PATH%" (
    set "EXE_PATH=%APP_DIR%\build\windows\x64\runner\Release\virus_download_manager.exe"
)
if not exist "%EXE_PATH%" (
    set "EXE_PATH=%APP_DIR%\build\windows\x64\runner\Release\virusdownloader.exe"
)
if not exist "%EXE_PATH%" (
    set "EXE_PATH=%APP_DIR%\build\windows\x64\runner\Debug\virus_download_manager.exe"
)
if not exist "%EXE_PATH%" (
    echo [VirusDownloader] Executable not found in build directory. Using current directory.
    set "EXE_PATH=%cd%\virus_download_manager.exe"
)

echo [VirusDownloader] Registering virusdownloader:// custom URI protocol...
echo Target executable: "%EXE_PATH%"

REM Register protocol under HKCU (no administrator privileges required)
reg add "HKCU\Software\Classes\virusdownloader" /ve /d "URL:VirusDownloader Protocol" /f
reg add "HKCU\Software\Classes\virusdownloader" /v "URL Protocol" /d "" /f
reg add "HKCU\Software\Classes\virusdownloader\DefaultIcon" /ve /d "\"%EXE_PATH%\",0" /f
reg add "HKCU\Software\Classes\virusdownloader\shell\open\command" /ve /d "\"%EXE_PATH%\" \"%%1\"" /f

if %ERRORLEVEL% equ 0 (
    echo [VirusDownloader] Custom protocol registered successfully!
    echo Example usage: virusdownloader://add?url=https://example.com/file.zip
) else (
    echo [VirusDownloader] Error: Failed to register protocol in Windows Registry.
)

:done
endlocal
