{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit install_manifest;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

type
  // a tiny snapshot of what got installed so a later run can decide
  // whether the user's currently-selected branch/hash matches what is
  // already on disk and therefore whether to skip or refresh the build.
  TInstallManifest = record
    Present: Boolean;
    FpcBranch: string;
    FpcSha: string;
    LazBranch: string;
    LazSha: string;
    CrossWin64: Boolean;       // cross to x86_64-win64 (only built on linux64 host)
    CrossWin32: Boolean;       // legacy 32-bit
    CrossLinux64: Boolean;     // cross to x86_64-linux (only built on win64 host)
    CrossLinux32: Boolean;     // legacy 32-bit
    CrossWasm: Boolean;
    // optional Lazarus IDE addons -- written so a re-run can pre-tick
    // the right checkboxes
    InstallMinimap: Boolean;
    // last launch-after-install state, restored to the checkbox on
    // re-run so the user does not have to re-tick every time
    LaunchAfter: Boolean;
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
  Result.CrossWin64   := StrToBoolDefSafe(Lines.Values['cross-x86_64-win64'], False);
  Result.CrossWin32   := StrToBoolDefSafe(Lines.Values['cross-i386-win32'], False);
  Result.CrossLinux64 := StrToBoolDefSafe(Lines.Values['cross-x86_64-linux'], False);
  Result.CrossLinux32 := StrToBoolDefSafe(Lines.Values['cross-i386-linux'], False);
  // accept both wasip1 (current) and wasi (older manifests) so a re-run reads the historical flag
  Result.CrossWasm    := StrToBoolDefSafe(Lines.Values['cross-wasm32-wasip1'], StrToBoolDefSafe(Lines.Values['cross-wasm32-wasi'], False));
  Result.InstallMinimap := StrToBoolDefSafe(Lines.Values['extras-minimap'], False);
  Result.LaunchAfter  := StrToBoolDefSafe(Lines.Values['launch-after-install'], True);
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
  Lines.Add('cross-x86_64-win64='+BoolFlag(M.CrossWin64));
  Lines.Add('cross-i386-win32='+BoolFlag(M.CrossWin32));
  Lines.Add('cross-x86_64-linux='+BoolFlag(M.CrossLinux64));
  Lines.Add('cross-i386-linux='+BoolFlag(M.CrossLinux32));
  Lines.Add('cross-wasm32-wasip1='+BoolFlag(M.CrossWasm));
  Lines.Add('extras-minimap='+BoolFlag(M.InstallMinimap));
  Lines.Add('launch-after-install='+BoolFlag(M.LaunchAfter));
  Lines.Add('installed-at='+M.InstalledAt);
  try
    Lines.SaveToFile(ManifestPathFor(InstallDir));
    Result := True;
  except
    // swallow; Result stays False
  end;
end;

end.
