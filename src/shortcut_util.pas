{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit shortcut_util;

{$mode unleashed}

interface

// Place a desktop shortcut for TargetPath with the given launch Args.
// On Windows writes a .lnk via IShellLinkW COM. On Linux writes a
// .desktop file to ~/Desktop/ (per the XDG spec) plus a copy to
// ~/.local/share/applications/ so the IDE shows up in the system
// menu as well. Returns False on any failure.
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
  // CSIDL_DESKTOPDIRECTORY is the per-user file-system Desktop path.
  // CSIDL_DESKTOP is the virtual desktop folder (which contains things
  // like My Computer); we want the physical dir.
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
    var WLnkPath: WideString := UTF8Decode(IncludeTrailingPathDelimiter(DesktopDir) + ShortcutName + '.lnk');
    Result := Persist.Save(PWideChar(WLnkPath), True) = S_OK;
  finally
    CoUninitialize;
  end;
end;
{$endif}

{$ifdef LINUX}
// build a .desktop file body per XDG Desktop Entry Specification.
// Categories=Development;IDE; puts the entry under Programming menus
// on GNOME/KDE/Cinnamon/XFCE.
function BuildDesktopEntry(const TargetPath, Args, ShortcutName: string): string;
begin
  var ExecLine := TargetPath;
  if Args <> '' then ExecLine := TargetPath + ' ' + Args;
  // Lazarus ships its own icon under <lazarusdir>/images/. The exact
  // filename has shifted across versions: 2.x had ide_icon.png, 3.x
  // ide_icon48x48.png, 4.x added ide_icon128x128.png and similar
  // sizes. TargetPath is <lazarusdir>/lazarus, so ExtractFilePath
  // gives us the dir. Probe a few candidates and pick the first that
  // actually exists; Linux .desktop renderers silently fall back to
  // a generic placeholder when Icon= points at a missing file.
  var LazDir := IncludeTrailingPathDelimiter(ExtractFilePath(TargetPath)) + 'images/';
  var IconCandidates: array of string := [ LazDir + 'ide_icon128x128.png', LazDir + 'ide_icon48x48.png', LazDir + 'ide_icon.png' ];
  var IconPath: string := '';
  for var i := Low(IconCandidates) to High(IconCandidates) do
    if FileExists(IconCandidates[i]) then begin
      IconPath := IconCandidates[i];
      Break;
    end;
  Result :=
    '[Desktop Entry]'#10 + 'Type=Application'#10 + 'Version=1.0'#10 + 'Name=' + ShortcutName + #10 +
    'Comment=Lazarus IDE (FPC Unleashed)'#10 + 'Exec=' + ExecLine + #10 + (if IconPath <> '' then 'Icon=' + IconPath + #10 else '') + 'Terminal=false'#10 +
    'Categories=Development;IDE;'#10 + 'StartupNotify=false'#10;
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
  // GNOME 3.34+ requires the .desktop file to be executable for
  // double-click to launch it; KDE doesn't care. We shell out to
  // /bin/chmod so we don't have to pull BaseUnix in just for fpchmod.
  // Best-effort; failure is non-fatal (the file is still parsable for
  // menu entries, just not double-clickable from the desktop).
  RunSilent('/bin/chmod', ['0755', Path]);
  Result := True;
end;

function CreateDesktopShortcut(const TargetPath, Args, ShortcutName: string): Boolean;
begin
  Result := False;
  var Home := GetEnvironmentVariable('HOME');
  if Home = '' then Exit;

  var Body := BuildDesktopEntry(TargetPath, Args, ShortcutName);
  // Sanitize the filename: spaces and parens are fine in Name= but
  // ugly in the on-disk path. Replace whitespace with '-' and strip
  // problematic chars; keep ascii letters / digits / dot / dash / underscore.
  var FileBase: string := '';
  for var i := 1 to Length(ShortcutName) do begin
    var c := ShortcutName[i];
    case c of
      'A'..'Z', 'a'..'z', '0'..'9', '.', '-', '_':
        FileBase := FileBase + c;
      ' ', #9:
        FileBase := FileBase + '-';
      // skip anything else
    end;
  end;
  if FileBase = '' then FileBase := 'lazarus-unleashed';

  var DesktopPath  := IncludeTrailingPathDelimiter(Home) + 'Desktop' + DirectorySeparator + FileBase + '.desktop';
  var MenuPath     := IncludeTrailingPathDelimiter(Home) + '.local/share/applications/' + FileBase + '.desktop';

  // best-effort: write both locations. Desktop entry is the primary;
  // menu entry is nice-to-have. Succeed if either lands.
  var WroteDesktop := WriteDesktopFile(DesktopPath, Body);
  var WroteMenu    := WriteDesktopFile(MenuPath,    Body);
  Result := WroteDesktop or WroteMenu;
end;
{$endif}

end.
