{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit shortcut_util;

{$mode unleashed}

interface

// desktop shortcut. Windows: .lnk via IShellLinkW; Linux: .desktop in ~/Desktop/ + ~/.local/share/applications/
function CreateDesktopShortcut(const TargetPath, Args, ShortcutName: string): Boolean;
// shortcut placed directly inside Dir (the install folder). Windows: Dir\Name.lnk; Linux: Dir/<sanitized>.desktop
function CreateFolderShortcut(const Dir, TargetPath, Args, ShortcutName: string): Boolean;

implementation

uses
  SysUtils
  {$ifdef MSWINDOWS}, Windows, ActiveX, ComObj, ShlObj{$endif}
  {$ifdef LINUX}, Classes, proc_util{$endif};

{$ifdef MSWINDOWS}
function GetDesktopPath: string;
var
  Buf: array[0..MAX_PATH] of AnsiChar;
begin
  Result := '';
  // CSIDL_DESKTOPDIRECTORY = physical per-user desktop dir; CSIDL_DESKTOP is the virtual folder (My Computer etc)
  if SHGetFolderPathA(0, CSIDL_DESKTOPDIRECTORY, 0, 0, @Buf[0]) = S_OK then Result := AnsiString(Buf);
end;

// write a .lnk at LnkPath pointing at TargetPath with Args; icon index 0 = first group in the exe
function WriteLnk(const LnkPath, TargetPath, Args: string): Boolean;
begin
  Result := False;
  if FAILED(CoInitialize(nil)) then Exit;
  try
    var Link: IShellLinkW := CreateComObject(CLSID_ShellLink) as IShellLinkW;
    var WTarget: WideString := UTF8Decode(TargetPath);
    Link.SetPath(PWideChar(WTarget));
    if Args <> '' then begin
      var WArgs: WideString := UTF8Decode(Args);
      Link.SetArguments(PWideChar(WArgs));
    end;
    var WWorkDir: WideString := UTF8Decode(ExtractFilePath(TargetPath));
    Link.SetWorkingDirectory(PWideChar(WWorkDir));
    Link.SetIconLocation(PWideChar(WTarget), 0);
    var Persist: IPersistFile := Link as IPersistFile;
    var WLnkPath: WideString := UTF8Decode(LnkPath);
    Result := Persist.Save(PWideChar(WLnkPath), True) = S_OK;
  finally
    CoUninitialize;
  end;
end;

function CreateDesktopShortcut(const TargetPath, Args, ShortcutName: string): Boolean;
begin
  Result := False;
  var DesktopDir := GetDesktopPath;
  if DesktopDir = '' then Exit;
  Result := WriteLnk(IncludeTrailingPathDelimiter(DesktopDir)+ShortcutName+'.lnk', TargetPath, Args);
end;

function CreateFolderShortcut(const Dir, TargetPath, Args, ShortcutName: string): Boolean;
begin
  Result := False;
  if Dir = '' then Exit;
  ForceDirectories(Dir);
  Result := WriteLnk(IncludeTrailingPathDelimiter(Dir)+ShortcutName+'.lnk', TargetPath, Args);
end;
{$endif}

{$ifdef LINUX}
// XDG Desktop Entry body; Categories=Development;IDE; lands under Programming on GNOME/KDE/Cinnamon/XFCE
function BuildDesktopEntry(const TargetPath, Args, ShortcutName: string): string;
begin
  var ExecLine := TargetPath;
  if Args <> '' then ExecLine := TargetPath+' '+Args;
  // probe icon names; Lazarus 2.x: ide_icon.png, 3.x: ide_icon48x48.png, 4.x+: ide_icon128x128.png. Missing Icon= => placeholder
  var LazDir := IncludeTrailingPathDelimiter(ExtractFilePath(TargetPath))+'images/';
  var IconCandidates: array of string := [LazDir+'ide_icon128x128.png', LazDir+'ide_icon48x48.png', LazDir+'ide_icon.png'];
  var IconPath: string := '';
  for var i := Low(IconCandidates) to High(IconCandidates) do
    if FileExists(IconCandidates[i]) then begin
      IconPath := IconCandidates[i];
      Break;
    end;
  Result := '[Desktop Entry]'#10+'Type=Application'#10+'Version=1.0'#10+'Name='+ShortcutName+#10+'Comment=Lazarus IDE (FPC Unleashed)'#10+'Exec='+ExecLine+#10+
            (if IconPath <> '' then 'Icon='+IconPath+#10 else '')+'Terminal=false'#10+'Categories=Development;IDE;'#10+'StartupNotify=false'#10;
end;

function WriteDesktopFile(const Path, Body: string): Boolean;
begin
  Result := False;
  ForceDirectories(ExtractFilePath(Path));
  try
    var Sl := autofree TStringList.Create;
    Sl.Text := Body;
    Sl.SaveToFile(Path);
  except
    Exit;
  end;
  // GNOME 3.34+ wants 0755 for double-click launch; KDE doesn't care. Best-effort; failure non-fatal
  RunSilent('/bin/chmod', ['0755', Path]);
  Result := True;
end;

// ascii letters/digits/dot/dash/underscore; whitespace -> '-'; everything else dropped
function SanitizeName(const ShortcutName: string): string;
begin
  Result := '';
  for var i := 1 to Length(ShortcutName) do begin
    var c := ShortcutName[i];
    case c of
      'A'..'Z', 'a'..'z', '0'..'9', '.', '-', '_': Result := Result+c;
      ' ', #9: Result := Result+'-';
    end;
  end;
  if Result = '' then Result := 'lazarus-unleashed';
end;

function CreateDesktopShortcut(const TargetPath, Args, ShortcutName: string): Boolean;
begin
  Result := False;
  var Home := GetEnvironmentVariable('HOME');
  if Home = '' then Exit;
  var Body := BuildDesktopEntry(TargetPath, Args, ShortcutName);
  var FileBase := SanitizeName(ShortcutName);
  var DesktopPath := IncludeTrailingPathDelimiter(Home)+'Desktop'+DirectorySeparator+FileBase+'.desktop';
  var MenuPath    := IncludeTrailingPathDelimiter(Home)+'.local/share/applications/'+FileBase+'.desktop';
  // best-effort: write both. Succeed if either lands
  var WroteDesktop := WriteDesktopFile(DesktopPath, Body);
  var WroteMenu    := WriteDesktopFile(MenuPath, Body);
  Result := WroteDesktop or WroteMenu;
end;

function CreateFolderShortcut(const Dir, TargetPath, Args, ShortcutName: string): Boolean;
begin
  Result := False;
  if Dir = '' then Exit;
  var Body := BuildDesktopEntry(TargetPath, Args, ShortcutName);
  Result := WriteDesktopFile(IncludeTrailingPathDelimiter(Dir)+SanitizeName(ShortcutName)+'.desktop', Body);
end;
{$endif}

end.
