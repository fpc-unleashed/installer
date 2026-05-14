{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit shortcut_util;

{$mode unleashed}

interface

// create a .lnk on the user's desktop. WorkingDir defaults to ExtractFilePath
// of TargetPath. icon comes from TargetPath itself (embedded resource).
function CreateDesktopShortcut(const TargetPath, Args, ShortcutName: string): Boolean;

implementation

uses
  Windows, ActiveX, ComObj, ShlObj, SysUtils;

function GetDesktopPath: string;
var
  Buf: array[0..MAX_PATH] of AnsiChar;
begin
  Result := '';
  // CSIDL_DESKTOPDIRECTORY = per-user file-system Desktop; CSIDL_DESKTOP is the virtual folder (My Computer etc.)
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

end.
