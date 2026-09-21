; ==============================================================================
; VirusDownloader - Inno Setup Script
; Builds modern Windows Installer (.exe) with dual install mode (User vs All Users),
; MIT license agreement, browser extension installation, and clean uninstallation
; with an option to keep or delete user data.
; ==============================================================================

#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

#ifndef MyTag
  #define MyTag "v1.0.0"
#endif

#define MyAppName "Virus Download Manager"
#define MyAppPublisher "f4rh4d-4hmed"
#define MyAppURL "https://github.com/f4rh4d-4hmed/VDM"
#define MyAppExeName "virus_download_manager.exe"
#define MyExtensionId "jdkegfbblbdneoeabighglhgkpfpebji"

[Setup]
; Uniquely identifies this application for upgrades and uninstallation
AppId={{C8E19B24-8F4C-4D56-91BE-55B1B7AA1001}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
LicenseFile=..\..\LICENSE
OutputDir=..\..\dist
OutputBaseFilename=VirusDownloader-Windows-x64-Setup-{#MyTag}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
ArchitecturesAllowed=x64

; Dual-mode installation:
; Prompts the user on setup launch: "Install for all users (recommended)" / "Install for me only"
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "browserext"; Description: "Register browser extension for Chrome, Edge, Brave, etc."; GroupDescription: "Browser Integration:"; Flags: checkedonce

[Files]
; Main Flutter Application Release Bundle
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; Secondary alias executable
Source: "..\..\build\windows\x64\runner\Release\virus_download_manager.exe"; DestDir: "{app}"; DestName: "virusdownloader.exe"; Flags: ignoreversion

; App Icon
Source: "..\runner\resources\app_icon.ico"; DestDir: "{app}"; Flags: ignoreversion

; Browser Extension files (unpacked)
Source: "..\..\extras\extension\*"; DestDir: "{app}\extension"; Flags: ignoreversion recursesubdirs createallsubdirs

; Packaged extension and update manifest
Source: "..\..\extras\extension.crx"; DestDir: "{app}\extension"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\..\extras\update.xml"; DestDir: "{app}\extension"; Flags: ignoreversion skipifsourcedoesntexist

; Extension and protocol installer scripts
Source: "..\..\extras\install_extension.bat"; DestDir: "{app}\extras"; Flags: ignoreversion
Source: "..\..\extras\install_extension.ps1"; DestDir: "{app}\extras"; Flags: ignoreversion
Source: "..\..\extras\register_protocol.bat"; DestDir: "{app}\extras"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app_icon.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app_icon.ico"; Tasks: desktopicon

[Registry]
; Register custom protocol: virusdownloader://
Root: HKA; Subkey: "Software\Classes\virusdownloader"; ValueType: string; ValueData: "URL:VirusDownloader Protocol"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\virusdownloader"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\virusdownloader\DefaultIcon"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"",0"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\virusdownloader\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey

; App Paths for Run command
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\App Paths\{#MyAppExeName}"; ValueType: string; ValueData: "{app}\{#MyAppExeName}"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\App Paths\{#MyAppExeName}"; ValueType: string; ValueName: "Path"; ValueData: "{app}"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\App Paths\virusdownloader.exe"; ValueType: string; ValueData: "{app}\virusdownloader.exe"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\App Paths\virusdownloader.exe"; ValueType: string; ValueName: "Path"; ValueData: "{app}"; Flags: uninsdeletekey

; Browser External Extension Entries
Root: HKA; Subkey: "Software\Google\Chrome\Extensions\{#MyExtensionId}"; ValueType: string; ValueName: "update_url"; ValueData: "http://127.0.0.1:9849/update.xml"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Google\Chrome\Extensions\{#MyExtensionId}"; ValueType: string; ValueName: "path"; ValueData: "{app}\extension\extension.crx"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Google\Chrome\Extensions\{#MyExtensionId}"; ValueType: string; ValueName: "version"; ValueData: "1.0.0"; Flags: uninsdeletekey

Root: HKA; Subkey: "Software\Microsoft\Edge\Extensions\{#MyExtensionId}"; ValueType: string; ValueName: "update_url"; ValueData: "http://127.0.0.1:9849/update.xml"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Microsoft\Edge\Extensions\{#MyExtensionId}"; ValueType: string; ValueName: "path"; ValueData: "{app}\extension\extension.crx"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Microsoft\Edge\Extensions\{#MyExtensionId}"; ValueType: string; ValueName: "version"; ValueData: "1.0.0"; Flags: uninsdeletekey

Root: HKA; Subkey: "Software\BraveSoftware\Brave-Browser\Extensions\{#MyExtensionId}"; ValueType: string; ValueName: "update_url"; ValueData: "http://127.0.0.1:9849/update.xml"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\BraveSoftware\Brave-Browser\Extensions\{#MyExtensionId}"; ValueType: string; ValueName: "path"; ValueData: "{app}\extension\extension.crx"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\BraveSoftware\Brave-Browser\Extensions\{#MyExtensionId}"; ValueType: string; ValueName: "version"; ValueData: "1.0.0"; Flags: uninsdeletekey

[Run]
; Run extension registration during installation
Filename: "{app}\extras\install_extension.bat"; Parameters: "/install /silent"; Flags: runhidden; Tasks: browserext
; Post-installation launch option
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[Code]
var
  RemoveUserData: Boolean;

// Helper to safely delete a registry key and all subkeys
procedure CleanRegistryKey(RootKey: Integer; SubKey: String);
begin
  try
    RegDeleteKeyIncludingSubkeys(RootKey, SubKey);
  except
  end;
end;

// Helper to safely delete a registry value
procedure CleanRegistryValue(RootKey: Integer; SubKey, ValueName: String);
begin
  try
    RegDeleteValue(RootKey, SubKey, ValueName);
  except
  end;
end;

// Helper to remove extension from ExtensionInstallForcelist policy
procedure CleanPolicyValue(RootKey: Integer; PolicyKey, ExtensionId: String);
var
  Names: TArrayOfString;
  I: Integer;
  Val: String;
begin
  try
    if RegGetValueNames(RootKey, PolicyKey, Names) then
    begin
      for I := 0 to GetArrayLength(Names) - 1 do
      begin
        if RegQueryStringValue(RootKey, PolicyKey, Names[I], Val) then
        begin
          if Pos(ExtensionId, Val) > 0 then
          begin
            RegDeleteValue(RootKey, PolicyKey, Names[I]);
          end;
        end;
      end;
    end;
  except
  end;
end;

// Uninstaller Initialization: Presents clear option to keep or delete user data
function InitializeUninstall(): Boolean;
var
  Form: TSetupForm;
  PromptLabel, Desc1Label, Desc2Label, NoteLabel: TLabel;
  KeepRadio, DeleteRadio: TNewRadioButton;
  OkButton, CancelButton: TNewButton;
begin
  Result := True;
  RemoveUserData := False;

  if WizardSilent() then
  begin
    RemoveUserData := (Pos('/DELETEUSERDATA', UpperCase(GetCmdTail())) > 0);
    Exit;
  end;

  Form := CreateCustomForm(ScaleX(460), ScaleY(240), False, False);
  try
    Form.ClientWidth := ScaleX(460);
    Form.ClientHeight := ScaleY(240);
    Form.Caption := 'VirusDownloader Uninstaller';
    Form.Position := poScreenCenter;
    Form.BorderStyle := bsDialog;

    PromptLabel := TLabel.Create(Form);
    PromptLabel.Parent := Form;
    PromptLabel.Left := ScaleX(24);
    PromptLabel.Top := ScaleY(18);
    PromptLabel.Width := ScaleX(412);
    PromptLabel.Font.Style := [fsBold];
    PromptLabel.Font.Size := 9;
    PromptLabel.Caption := 'Choose whether to keep or remove your VirusDownloader user data:';

    KeepRadio := TNewRadioButton.Create(Form);
    KeepRadio.Parent := Form;
    KeepRadio.Left := ScaleX(30);
    KeepRadio.Top := ScaleY(48);
    KeepRadio.Width := ScaleX(400);
    KeepRadio.Font.Style := [fsBold];
    KeepRadio.Caption := 'Keep user data (Recommended)';
    KeepRadio.Checked := True;

    Desc1Label := TLabel.Create(Form);
    Desc1Label.Parent := Form;
    Desc1Label.Left := ScaleX(48);
    Desc1Label.Top := ScaleY(68);
    Desc1Label.Width := ScaleX(380);
    Desc1Label.WordWrap := True;
    Desc1Label.Caption := 'Preserves settings, history, and preferences for future installations.';

    DeleteRadio := TNewRadioButton.Create(Form);
    DeleteRadio.Parent := Form;
    DeleteRadio.Left := ScaleX(30);
    DeleteRadio.Top := ScaleY(100);
    DeleteRadio.Width := ScaleX(400);
    DeleteRadio.Font.Style := [fsBold];
    DeleteRadio.Caption := 'Remove all user data';

    Desc2Label := TLabel.Create(Form);
    Desc2Label.Parent := Form;
    Desc2Label.Left := ScaleX(48);
    Desc2Label.Top := ScaleY(120);
    Desc2Label.Width := ScaleX(380);
    Desc2Label.WordWrap := True;
    Desc2Label.Caption := 'Deletes download task history, cached data, and preferences completely.';

    NoteLabel := TLabel.Create(Form);
    NoteLabel.Parent := Form;
    NoteLabel.Left := ScaleX(30);
    NoteLabel.Top := ScaleY(154);
    NoteLabel.Width := ScaleX(400);
    NoteLabel.WordWrap := True;
    NoteLabel.Font.Color := clGrayText;
    NoteLabel.Caption := 'Note: Files you have downloaded to your Downloads folder will NOT be deleted under either option.';

    OkButton := TNewButton.Create(Form);
    OkButton.Parent := Form;
    OkButton.Left := ScaleX(275);
    OkButton.Top := ScaleY(195);
    OkButton.Width := ScaleX(80);
    OkButton.Caption := 'Continue';
    OkButton.ModalResult := mrOk;
    OkButton.Default := True;

    CancelButton := TNewButton.Create(Form);
    CancelButton.Parent := Form;
    CancelButton.Left := ScaleX(365);
    CancelButton.Top := ScaleY(195);
    CancelButton.Width := ScaleX(80);
    CancelButton.Caption := 'Cancel';
    CancelButton.ModalResult := mrCancel;
    CancelButton.Cancel := True;

    if Form.ShowModal() = mrOk then
    begin
      RemoveUserData := DeleteRadio.Checked;
    end
    else
    begin
      Result := False;
    end;
  finally
    Form.Free();
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  AppBat: String;
  ResultCode: Integer;
  ExtId: String;
begin
  ExtId := '{#MyExtensionId}';

  if CurUninstallStep = usUninstall then
  begin
    // Run extension uninstaller helper if present
    AppBat := ExpandConstant('{app}\extras\install_extension.bat');
    if FileExists(AppBat) then
    begin
      Exec(AppBat, '/uninstall /silent', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;
  end;

  if CurUninstallStep = usPostUninstall then
  begin
    // 1. If RemoveUserData was chosen, delete application data directories
    if RemoveUserData then
    begin
      // Roaming AppData
      DelTree(ExpandConstant('{userappdata}\VirusDownloader'), True, True, True);
      DelTree(ExpandConstant('{userappdata}\virus_download_manager'), True, True, True);
      DelTree(ExpandConstant('{userappdata}\com.virusdownloadmanager'), True, True, True);

      // Local AppData
      DelTree(ExpandConstant('{localappdata}\VirusDownloader'), True, True, True);
      DelTree(ExpandConstant('{localappdata}\virus_download_manager'), True, True, True);
      DelTree(ExpandConstant('{localappdata}\com.virusdownloadmanager'), True, True, True);

      // Temp AppData
      DelTree(ExpandConstant('{tmp}\VirusDownloader'), True, True, True);
    end;

    // 2. Clean ALL registry entries completely so no regedit files are left behind
    // Protocol handler
    CleanRegistryKey(HKEY_CURRENT_USER, 'Software\Classes\virusdownloader');
    CleanRegistryKey(HKEY_LOCAL_MACHINE, 'Software\Classes\virusdownloader');

    // Extension registrations
    CleanRegistryKey(HKEY_CURRENT_USER, 'Software\Google\Chrome\Extensions\' + ExtId);
    CleanRegistryKey(HKEY_LOCAL_MACHINE, 'Software\Google\Chrome\Extensions\' + ExtId);
    CleanRegistryKey(HKEY_LOCAL_MACHINE, 'Software\WOW6432Node\Google\Chrome\Extensions\' + ExtId);

    CleanRegistryKey(HKEY_CURRENT_USER, 'Software\Microsoft\Edge\Extensions\' + ExtId);
    CleanRegistryKey(HKEY_LOCAL_MACHINE, 'Software\Microsoft\Edge\Extensions\' + ExtId);
    CleanRegistryKey(HKEY_LOCAL_MACHINE, 'Software\WOW6432Node\Microsoft\Edge\Extensions\' + ExtId);

    CleanRegistryKey(HKEY_CURRENT_USER, 'Software\BraveSoftware\Brave-Browser\Extensions\' + ExtId);
    CleanRegistryKey(HKEY_LOCAL_MACHINE, 'Software\BraveSoftware\Brave-Browser\Extensions\' + ExtId);

    // Extension policies
    CleanPolicyValue(HKEY_CURRENT_USER, 'Software\Policies\Google\Chrome\ExtensionInstallForcelist', ExtId);
    CleanPolicyValue(HKEY_LOCAL_MACHINE, 'Software\Policies\Google\Chrome\ExtensionInstallForcelist', ExtId);
    CleanPolicyValue(HKEY_CURRENT_USER, 'Software\Policies\Microsoft\Edge\ExtensionInstallForcelist', ExtId);
    CleanPolicyValue(HKEY_LOCAL_MACHINE, 'Software\Policies\Microsoft\Edge\ExtensionInstallForcelist', ExtId);
    CleanPolicyValue(HKEY_CURRENT_USER, 'Software\Policies\BraveSoftware\Brave-Browser\ExtensionInstallForcelist', ExtId);
    CleanPolicyValue(HKEY_LOCAL_MACHINE, 'Software\Policies\BraveSoftware\Brave-Browser\ExtensionInstallForcelist', ExtId);

    // Native Messaging Hosts
    CleanRegistryKey(HKEY_CURRENT_USER, 'Software\Google\Chrome\NativeMessagingHosts\com.virusdownloader.host');
    CleanRegistryKey(HKEY_LOCAL_MACHINE, 'Software\Google\Chrome\NativeMessagingHosts\com.virusdownloader.host');
    CleanRegistryKey(HKEY_CURRENT_USER, 'Software\Microsoft\Edge\NativeMessagingHosts\com.virusdownloader.host');
    CleanRegistryKey(HKEY_LOCAL_MACHINE, 'Software\Microsoft\Edge\NativeMessagingHosts\com.virusdownloader.host');
    CleanRegistryKey(HKEY_CURRENT_USER, 'Software\Mozilla\NativeMessagingHosts\com.virusdownloader.host');
    CleanRegistryKey(HKEY_LOCAL_MACHINE, 'Software\Mozilla\NativeMessagingHosts\com.virusdownloader.host');

    // Startup / Run keys
    CleanRegistryValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Run', 'VirusDownloader');
    CleanRegistryValue(HKEY_LOCAL_MACHINE, 'Software\Microsoft\Windows\CurrentVersion\Run', 'VirusDownloader');

    // App Paths
    CleanRegistryKey(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\App Paths\virus_download_manager.exe');
    CleanRegistryKey(HKEY_LOCAL_MACHINE, 'Software\Microsoft\Windows\CurrentVersion\App Paths\virus_download_manager.exe');
    CleanRegistryKey(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\App Paths\virusdownloader.exe');
    CleanRegistryKey(HKEY_LOCAL_MACHINE, 'Software\Microsoft\Windows\CurrentVersion\App Paths\virusdownloader.exe');

    // App Registry Keys
    CleanRegistryKey(HKEY_CURRENT_USER, 'Software\VirusDownloader');
    CleanRegistryKey(HKEY_LOCAL_MACHINE, 'Software\VirusDownloader');
    CleanRegistryKey(HKEY_CURRENT_USER, 'Software\com.virusdownloadmanager');
    CleanRegistryKey(HKEY_LOCAL_MACHINE, 'Software\com.virusdownloadmanager');
  end;
end;
