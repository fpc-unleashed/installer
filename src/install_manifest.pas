{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit install_manifest;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

type
  // snapshot of what got installed; later run compares against UI selection to decide skip vs refresh
  TInstallManifest = record
    Present: Boolean;
    FpcBranch: string;
    FpcSha: string;
    LazBranch: string;
    LazSha: string;
    CrossWin32: Boolean;
    CrossLinux64: Boolean;
    CrossLinux32: Boolean;
    InstalledAt: string;
  end;

const
  MANIFEST_FILE = 'installer.ini';

function ManifestPathFor(const InstallDir: string): string;
function ReadManifest(const InstallDir: string): TInstallManifest;
function WriteManifest(const InstallDir: string; const M: TInstallManifest): Boolean;

implementation

function ManifestPathFor(const InstallDir: string): string;
begin
  Result := IncludeTrailingPathDelimiter(InstallDir)+MANIFEST_FILE;
end;

function StrToBoolDefSafe(const S: string; const Def: Boolean): Boolean;
begin
  if (S = 'yes') or (S = 'true') or (S = '1') then Result := True
  else if (S = 'no') or (S = 'false') or (S = '0') then Result := False
  else Result := Def;
end;

function BoolFlag(B: Boolean): string;
begin
  if B then Result := 'yes' else Result := 'no';
end;

function ReadManifest(const InstallDir: string): TInstallManifest;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Present := False;
  var Path := ManifestPathFor(InstallDir);
  if not FileExists(Path) then Exit;

  var Lines := autofree TStringList.Create;
  Lines.NameValueSeparator := '=';
  try
    Lines.LoadFromFile(Path);
  except
    Exit;
  end;
  Result.FpcBranch    := Lines.Values['fpc-branch'];
  Result.FpcSha       := LowerCase(Lines.Values['fpc-sha']);
  Result.LazBranch    := Lines.Values['lazarus-branch'];
  Result.LazSha       := LowerCase(Lines.Values['lazarus-sha']);
  Result.CrossWin32   := StrToBoolDefSafe(Lines.Values['cross-i386-win32'], False);
  Result.CrossLinux64 := StrToBoolDefSafe(Lines.Values['cross-x86_64-linux'], False);
  Result.CrossLinux32 := StrToBoolDefSafe(Lines.Values['cross-i386-linux'], False);
  Result.InstalledAt  := Lines.Values['installed-at'];
  Result.Present      := True;
end;

function WriteManifest(const InstallDir: string; const M: TInstallManifest): Boolean;
begin
  Result := False;
  var Lines := autofree TStringList.Create;
  Lines.Add('# Unleashed Installer manifest - written automatically');
  Lines.Add('# Do not edit; the installer relies on these values to detect updates.');
  Lines.Add('fpc-branch='+M.FpcBranch);
  Lines.Add('fpc-sha='+LowerCase(M.FpcSha));
  Lines.Add('lazarus-branch='+M.LazBranch);
  Lines.Add('lazarus-sha='+LowerCase(M.LazSha));
  Lines.Add('cross-i386-win32='+BoolFlag(M.CrossWin32));
  Lines.Add('cross-x86_64-linux='+BoolFlag(M.CrossLinux64));
  Lines.Add('cross-i386-linux='+BoolFlag(M.CrossLinux32));
  Lines.Add('installed-at='+M.InstalledAt);
  try
    Lines.SaveToFile(ManifestPathFor(InstallDir));
    Result := True;
  except
    // swallow; Result stays False
  end;
end;

end.
