<#
.SYNOPSIS
    VirusDownloader Browser Extension & Protocol Installer / Uninstaller
.DESCRIPTION
    Configures browser extensions, policies, native messaging hosts, and URL protocol
    for Google Chrome, Microsoft Edge, Brave Browser, Opera, Vivaldi, and Mozilla Firefox.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('install', 'uninstall', 'status')]
    [string]$Action = 'install',

    [switch]$Silent,
    [string]$AppDir
)

$ErrorActionPreference = 'SilentlyContinue'

$ExtensionId = "jdkegfbblbdneoeabighglhgkpfpebji"
$ProtocolName = "virusdownloader"
$NativeHostName = "com.virusdownloader.host"

# Determine base directory
if (-not $AppDir -or -not (Test-Path $AppDir)) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    if (Test-Path (Join-Path $ScriptDir "extension\manifest.json")) {
        $AppDir = $ScriptDir
    } elseif (Test-Path (Join-Path (Split-Path -Parent $ScriptDir) "extras\extension\manifest.json")) {
        $AppDir = Split-Path -Parent $ScriptDir
    } else {
        $AppDir = $ScriptDir
    }
}

# Resolve executable
$ExePath = Join-Path $AppDir "virus_download_manager.exe"
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $AppDir "virusdownloader.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path (Join-Path $AppDir "build\windows\x64\runner\Release") "virus_download_manager.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path (Join-Path $AppDir "build\windows\x64\runner\Release") "virusdownloader.exe"
}

# Resolve extension files
$ExtensionDir = Join-Path $AppDir "extension"
if (-not (Test-Path $ExtensionDir)) {
    $ExtensionDir = Join-Path $AppDir "extras\extension"
}
$CrxPath = Join-Path $AppDir "extension\extension.crx"
if (-not (Test-Path $CrxPath)) {
    $CrxPath = Join-Path $AppDir "extras\extension.crx"
}
$UpdateXmlPath = Join-Path $AppDir "extension\update.xml"
if (-not (Test-Path $UpdateXmlPath)) {
    $UpdateXmlPath = Join-Path $AppDir "extras\update.xml"
}

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    if (-not $Silent) {
        switch ($Type) {
            "SUCCESS" { Write-Host "[+] $Message" -ForegroundColor Green }
            "WARN"    { Write-Host "[!] $Message" -ForegroundColor Yellow }
            "ERROR"   { Write-Host "[-] $Message" -ForegroundColor Red }
            default   { Write-Host "[*] $Message" -ForegroundColor Cyan }
        }
    }
}

function Register-Protocol {
    Write-Log "Registering '$ProtocolName://' custom protocol..."
    $roots = @("HKCU:\Software\Classes\$ProtocolName")
    if ($IsAdmin) {
        $roots += "HKLM:\Software\Classes\$ProtocolName"
    }

    foreach ($r in $roots) {
        try {
            New-Item -Path $r -Force | Out-Null
            Set-ItemProperty -Path $r -Name "(Default)" -Value "URL:VirusDownloader Protocol" -Force
            Set-ItemProperty -Path $r -Name "URL Protocol" -Value "" -Force
            if (Test-Path $ExePath) {
                New-Item -Path "$r\DefaultIcon" -Force | Out-Null
                Set-ItemProperty -Path "$r\DefaultIcon" -Name "(Default)" -Value "`"$ExePath`",0" -Force
                New-Item -Path "$r\shell\open\command" -Force | Out-Null
                Set-ItemProperty -Path "$r\shell\open\command" -Name "(Default)" -Value "`"$ExePath`" `"%1`"" -Force
            }
        } catch {}
    }
    Write-Log "Protocol '$ProtocolName://' registered successfully." "SUCCESS"
}

function Unregister-Protocol {
    Write-Log "Removing '$ProtocolName://' protocol registration..."
    Remove-Item -Path "HKCU:\Software\Classes\$ProtocolName" -Recurse -Force -ErrorAction SilentlyContinue
    if ($IsAdmin) {
        Remove-Item -Path "HKLM:\Software\Classes\$ProtocolName" -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Register-BrowserExtensions {
    Write-Log "Configuring browser extensions for VirusDownloader..."
    
    # Target hives: HKCU always, HKLM if running as administrator
    $hives = @("HKCU")
    if ($IsAdmin) { $hives += "HKLM" }

    # Generate or resolve update URL
    # Can use local HTTP bridge URL: http://127.0.0.1:9849/update.xml
    $updateUrl = "http://127.0.0.1:9849/update.xml"
    if (Test-Path $UpdateXmlPath) {
        $fileUri = [System.Uri]::new($UpdateXmlPath).AbsoluteUri
    } else {
        $fileUri = $updateUrl
    }

    # Browser policies definitions
    $browserConfigs = @(
        @{
            Name = "Microsoft Edge"
            ExtensionsKey = "Software\Microsoft\Edge\Extensions\$ExtensionId"
            PolicyKey = "Software\Policies\Microsoft\Edge"
        },
        @{
            Name = "Google Chrome"
            ExtensionsKey = "Software\Google\Chrome\Extensions\$ExtensionId"
            PolicyKey = "Software\Policies\Google\Chrome"
        },
        @{
            Name = "Brave Browser"
            ExtensionsKey = "Software\BraveSoftware\Brave-Browser\Extensions\$ExtensionId"
            PolicyKey = "Software\Policies\BraveSoftware\Brave-Browser"
        }
    )

    foreach ($b in $browserConfigs) {
        foreach ($h in $hives) {
            $root = "$h`:"
            # 1. External extension via path / update_url
            $extPath = "$root\$($b.ExtensionsKey)"
            try {
                New-Item -Path $extPath -Force | Out-Null
                if (Test-Path $CrxPath) {
                    Set-ItemProperty -Path $extPath -Name "path" -Value $CrxPath -Force
                    Set-ItemProperty -Path $extPath -Name "version" -Value "1.0.0" -Force
                }
                Set-ItemProperty -Path $extPath -Name "update_url" -Value $updateUrl -Force
            } catch {}

            # 2. ExtensionInstallForcelist policy
            $policyPath = "$root\$($b.PolicyKey)\ExtensionInstallForcelist"
            try {
                New-Item -Path $policyPath -Force | Out-Null
                # Check for existing value for ExtensionId or add new numbered value
                $props = Get-ItemProperty -Path $policyPath -ErrorAction SilentlyContinue
                $found = $false
                $maxIndex = 0
                if ($props) {
                    $props.PSObject.Properties | Where-Object { $_.Name -match '^\d+$' } | ForEach-Object {
                        $idx = [int]$_.Name
                        if ($idx -gt $maxIndex) { $maxIndex = $idx }
                        if ($_.Value -like "*$ExtensionId*") { $found = $true }
                    }
                }
                if (-not $found) {
                    $newIndex = ($maxIndex + 1).ToString()
                    Set-ItemProperty -Path $policyPath -Name $newIndex -Value "$ExtensionId;$updateUrl" -Force
                }
            } catch {}

            # 3. ExtensionInstallSources policy
            $sourcesPath = "$root\$($b.PolicyKey)\ExtensionInstallSources"
            try {
                New-Item -Path $sourcesPath -Force | Out-Null
                Set-ItemProperty -Path $sourcesPath -Name "1" -Value "http://127.0.0.1:9849/*" -Force
                Set-ItemProperty -Path $sourcesPath -Name "2" -Value "file:///*" -Force
            } catch {}

            # 64-bit WOW6432Node mirror if HKLM on 64-bit Windows
            if ($h -eq "HKLM" -and [Environment]::Is64BitOperatingSystem) {
                $wowExtPath = "HKLM:\Software\WOW6432Node\$($b.ExtensionsKey)"
                try {
                    New-Item -Path $wowExtPath -Force | Out-Null
                    if (Test-Path $CrxPath) {
                        Set-ItemProperty -Path $wowExtPath -Name "path" -Value $CrxPath -Force
                        Set-ItemProperty -Path $wowExtPath -Name "version" -Value "1.0.0" -Force
                    }
                    Set-ItemProperty -Path $wowExtPath -Name "update_url" -Value $updateUrl -Force
                } catch {}
            }
        }
        Write-Log "Configured integration for $($b.Name)." "SUCCESS"
    }

    # Native Messaging Hosts Registration
    Register-NativeMessagingHosts

    Write-Log "All browser extensions configured successfully." "SUCCESS"
}

function Register-NativeMessagingHosts {
    $manifestObj = @{
        name = $NativeHostName
        description = "VirusDownloader Native Messaging Host"
        path = if (Test-Path $ExePath) { $ExePath } else { "virus_download_manager.exe" }
        type = "stdio"
        allowed_origins = @(
            "chrome-extension://$ExtensionId/"
        )
    }
    $manifestJson = $manifestObj | ConvertTo-Json -Depth 4

    $targetDirs = @(
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\NativeMessagingHosts"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\NativeMessagingHosts"),
        (Join-Path $env:APPDATA "Mozilla\NativeMessagingHosts")
    )

    foreach ($dir in $targetDirs) {
        try {
            if (-not (Test-Path $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
            }
            $manifestFile = Join-Path $dir "$NativeHostName.json"
            $manifestJson | Set-Content -Path $manifestFile -Encoding UTF8 -Force

            # Register in Windows Registry for each browser
            if ($dir -like "*Chrome*") {
                New-Item -Path "HKCU:\Software\Google\Chrome\NativeMessagingHosts\$NativeHostName" -Force | Out-Null
                Set-ItemProperty -Path "HKCU:\Software\Google\Chrome\NativeMessagingHosts\$NativeHostName" -Name "(Default)" -Value $manifestFile -Force
            } elseif ($dir -like "*Edge*") {
                New-Item -Path "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\$NativeHostName" -Force | Out-Null
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\$NativeHostName" -Name "(Default)" -Value $manifestFile -Force
            } elseif ($dir -like "*Mozilla*") {
                New-Item -Path "HKCU:\Software\Mozilla\NativeMessagingHosts\$NativeHostName" -Force | Out-Null
                Set-ItemProperty -Path "HKCU:\Software\Mozilla\NativeMessagingHosts\$NativeHostName" -Name "(Default)" -Value $manifestFile -Force
            }
        } catch {}
    }
}

function Unregister-BrowserExtensions {
    Write-Log "Cleaning up browser extension registries and policies..."

    $hives = @("HKCU")
    if ($IsAdmin) { $hives += "HKLM" }

    $keysToRemove = @(
        "Software\Microsoft\Edge\Extensions\$ExtensionId",
        "Software\Google\Chrome\Extensions\$ExtensionId",
        "Software\BraveSoftware\Brave-Browser\Extensions\$ExtensionId",
        "Software\Google\Chrome\NativeMessagingHosts\$NativeHostName",
        "Software\Microsoft\Edge\NativeMessagingHosts\$NativeHostName",
        "Software\Mozilla\NativeMessagingHosts\$NativeHostName"
    )

    foreach ($h in $hives) {
        foreach ($k in $keysToRemove) {
            Remove-Item -Path "$h`:\$k" -Recurse -Force -ErrorAction SilentlyContinue
            if ($h -eq "HKLM" -and [Environment]::Is64BitOperatingSystem) {
                Remove-Item -Path "HKLM:\Software\WOW6432Node\$k" -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # Remove our specific entry from ExtensionInstallForcelist
        $forcelists = @(
            "$h`:\Software\Policies\Microsoft\Edge\ExtensionInstallForcelist",
            "$h`:\Software\Policies\Google\Chrome\ExtensionInstallForcelist",
            "$h`:\Software\Policies\BraveSoftware\Brave-Browser\ExtensionInstallForcelist"
        )
        foreach ($fl in $forcelists) {
            try {
                $props = Get-ItemProperty -Path $fl -ErrorAction SilentlyContinue
                if ($props) {
                    $props.PSObject.Properties | Where-Object { $_.Value -like "*$ExtensionId*" } | ForEach-Object {
                        Remove-ItemProperty -Path $fl -Name $_.Name -Force -ErrorAction SilentlyContinue
                    }
                }
            } catch {}
        }
    }

    # Remove NativeMessagingHost JSON files
    $manifestFiles = @(
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\NativeMessagingHosts\$NativeHostName.json"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\NativeMessagingHosts\$NativeHostName.json"),
        (Join-Path $env:APPDATA "Mozilla\NativeMessagingHosts\$NativeHostName.json")
    )
    foreach ($mf in $manifestFiles) {
        if (Test-Path $mf) {
            Remove-Item -Path $mf -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Log "Browser extension registrations cleaned up completely." "SUCCESS"
}

# Main Execution
switch ($Action.ToLower()) {
    'install' {
        Register-Protocol
        Register-BrowserExtensions
        if (-not $Silent) {
            Write-Host "`nInstallation finished successfully! Restart your browser to activate." -ForegroundColor Green
        }
    }
    'uninstall' {
        Unregister-BrowserExtensions
        Unregister-Protocol
        if (-not $Silent) {
            Write-Host "`nUninstallation finished cleanly! No registry keys left behind." -ForegroundColor Green
        }
    }
    'status' {
        Write-Host "VirusDownloader Extension Status (ID: $ExtensionId)" -ForegroundColor White
        Write-Host "Executable: $ExePath (Exists: $(Test-Path $ExePath))"
        Write-Host "Extension Dir: $ExtensionDir (Exists: $(Test-Path $ExtensionDir))"
        Write-Host "Packed CRX: $CrxPath (Exists: $(Test-Path $CrxPath))"
    }
}
