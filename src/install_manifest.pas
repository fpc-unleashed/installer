{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit install_manifest;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

type
  // snapshot of what got installed so a later run can compare against the UI selection
  TInstallManifest = record
    Present: Boolean;
    FpcBranch: string;
    FpcSha: string;
    // CheckBoxLatest state at install time; FpcSha holds the resolved head SHA either way
    FpcLatest: Boolean;
    LazBranch: string;
    LazSha: string;
    LazLatest: Boolean;
    CrossWin64: Boolean;       // cross to x86_64-win64 (only built on linux64 host)
    CrossWin32: Boolean;       // legacy 32-bit
    CrossLinux64: Boolean;     // cross to x86_64-linux (only built on win64 host)
    CrossLinux32: Boolean;     // legacy 32-bit
    CrossWasm: Boolean;
    InstallMinimap: Boolean;
    InstallCPUView: Boolean;
    // win-only IDE plugin; field exists on every host so the manifest stays portable
    InstallToggleAffinity: Boolean;
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
  // pre-fpc-latest manifests: empty SHA implied latest=true
  Result.FpcLatest    := StrToBoolDefSafe(Lines.Values['fpc-latest'], Result.FpcSha = '');
  Result.LazBranch    := Lines.Values['lazarus-branch'];
  Result.LazSha       := LowerCase(Lines.Values['lazarus-sha']);
  Result.LazLatest    := StrToBoolDefSafe(Lines.Values['lazarus-latest'], Result.LazSha = '');
  Result.CrossWin64   := StrToBoolDefSafe(Lines.Values['cross-x86_64-win64'], False);
  Result.CrossWin32   := StrToBoolDefSafe(Lines.Values['cross-i386-win32'], False);
  Result.CrossLinux64 := StrToBoolDefSafe(Lines.Values['cross-x86_64-linux'], False);
  Result.CrossLinux32 := StrToBoolDefSafe(Lines.Values['cross-i386-linux'], False);
  // accept both wasip1 (current) and legacy wasi key
  Result.CrossWasm    := StrToBoolDefSafe(Lines.Values['cross-wasm32-wasip1'], StrToBoolDefSafe(Lines.Values['cross-wasm32-wasi'], False));
  Result.InstallMinimap := StrToBoolDefSafe(Lines.Values['extras-minimap'], False);
  Result.InstallCPUView := StrToBoolDefSafe(Lines.Values['extras-cpuview'], False);
  Result.InstallToggleAffinity := StrToBoolDefSafe(Lines.Values['extras-toggle-affinity'], False);
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
  Lines.Add('fpc-latest='+BoolFlag(M.FpcLatest));
  Lines.Add('lazarus-branch='+M.LazBranch);
  Lines.Add('lazarus-sha='+LowerCase(M.LazSha));
  Lines.Add('lazarus-latest='+BoolFlag(M.LazLatest));
  Lines.Add('cross-x86_64-win64='+BoolFlag(M.CrossWin64));
  Lines.Add('cross-i386-win32='+BoolFlag(M.CrossWin32));
  Lines.Add('cross-x86_64-linux='+BoolFlag(M.CrossLinux64));
  Lines.Add('cross-i386-linux='+BoolFlag(M.CrossLinux32));
  Lines.Add('cross-wasm32-wasip1='+BoolFlag(M.CrossWasm));
  Lines.Add('extras-minimap='+BoolFlag(M.InstallMinimap));
  Lines.Add('extras-cpuview='+BoolFlag(M.InstallCPUView));
  Lines.Add('extras-toggle-affinity='+BoolFlag(M.InstallToggleAffinity));
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
