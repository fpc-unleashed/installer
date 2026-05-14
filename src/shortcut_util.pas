{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit shortcut_util;

{$mode unleashed}

interface

// Windows: .lnk via IShellLinkW COM. Linux: .desktop in ~/Desktop and ~/.local/share/applications.
function CreateDesktopShortcut(const TargetPath, Args, ShortcutName: string): Boolean;

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
  // CSIDL_DESKTOPDIRECTORY = physical per-user Desktop dir; CSIDL_DESKTOP is the virtual one
  if SHGetFolderPathA(0, CSIDL_DESKTOPDIRECTORY, 0, 0, @Buf[0]) = S_OK then Result := AnsiString(Buf);
end;

function CreateDesktopShortcut(const TargetPath, Args, ShortcutName: string): Boolean;
begin
  Result := False;
  var DesktopDir := GetDesktopPath;
  if DesktopDir = '' then Exit;
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
    // index 0 = first icon group inside the exe (Lazarus' own icon)
    Link.SetIconLocation(PWideChar(WTarget), 0);

    var Persist: IPersistFile := Link as IPersistFile;
    var WLnkPath: WideString := UTF8Decode(IncludeTrailingPathDelimiter(DesktopDir)+ShortcutName+'.lnk');
    Result := Persist.Save(PWideChar(WLnkPath), True) = S_OK;
  finally
    CoUninitialize;
  end;
end;
{$endif}

{$ifdef LINUX}
// .desktop body per XDG spec; Categories=Development;IDE puts it under Programming menus
function BuildDesktopEntry(const TargetPath, Args, ShortcutName: string): string;
begin
  var ExecLine := TargetPath;
  if Args <> '' then ExecLine := TargetPath+' '+Args;
  // TargetPath is <lazarusdir>/lazarus, so ExtractFilePath gives <lazarusdir>/
  var IconPath := IncludeTrailingPathDelimiter(ExtractFilePath(TargetPath))+'images/ide_icon.png';
  Result :=
    '[Desktop Entry]'#10+
    'Type=Application'#10+
    'Version=1.0'#10+
    'Name='+ShortcutName+#10+
    'Comment=Lazarus IDE (FPC Unleashed)'#10+
    'Exec='+ExecLine+#10+
    'Icon='+IconPath+#10+
    'Terminal=false'#10+
    'Categories=Development;IDE;'#10+
    'StartupNotify=false'#10;
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
  // GNOME 3.34+ needs +x on .desktop to double-click; shell out to chmod (avoid BaseUnix)
  RunSilent('/bin/chmod', ['0755', Path]);
  Result := True;
end;

function CreateDesktopShortcut(const TargetPath, Args, ShortcutName: string): Boolean;
begin
  Result := False;
  var Home := GetEnvironmentVariable('HOME');
  if Home = '' then Exit;

  var Body := BuildDesktopEntry(TargetPath, Args, ShortcutName);
  // sanitize filename: keep [A-Za-z0-9._-], whitespace -> '-', drop the rest
  var FileBase: string := '';
  for var i := 1 to Length(ShortcutName) do begin
    var c := ShortcutName[i];
    case c of
      'A'..'Z', 'a'..'z', '0'..'9', '.', '-', '_': FileBase := FileBase+c;
      ' ', #9: FileBase := FileBase+'-';
    end;
  end;
  if FileBase = '' then FileBase := 'lazarus-unleashed';

  var DesktopPath := IncludeTrailingPathDelimiter(Home)+'Desktop'+DirectorySeparator+FileBase+'.desktop';
  var MenuPath    := IncludeTrailingPathDelimiter(Home)+'.local/share/applications/'+FileBase+'.desktop';

  // best-effort: succeed if either lands
  var WroteDesktop := WriteDesktopFile(DesktopPath, Body);
  var WroteMenu    := WriteDesktopFile(MenuPath, Body);
  Result := WroteDesktop or WroteMenu;
end;
{$endif}

end.
