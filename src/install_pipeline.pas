{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit install_pipeline;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

type
  TStringArray = array of string;

  TInstallConfig = record
    InstallFpc:     Boolean;
    InstallLazarus: Boolean;
    FpcLatest:      Boolean;
    FpcBranch:      string;
    FpcHash:        string;
    LazLatest:      Boolean;
    LazBranch:      string;
    LazHash:        string;
    TargetDir:      string;
    CrossWin64:     Boolean;     // only meaningful on Linux host
    CrossWin32:     Boolean;     // legacy
    CrossLinux64:   Boolean;     // only meaningful on Windows host
    CrossLinux32:   Boolean;     // legacy
    CrossWasm:      Boolean;
    // Lazarus IDE addons; each toggles one --add-package call. lazbuild --build-ide picks up <pcp>/staticpackages.inc
    // and links via the {$IFDEF AddStaticPkgs} block in lazarus.pp; packagesystem.pas:2533 sets that define automatically
    InstallMinimap: Boolean;
    // user pref; persisted to manifest only so a re-run can restore the checkbox state
    LaunchAfter:    Boolean;
    // UI-resolved SHA (head of chosen branch or user-provided hash); manifest stores it for later compare
    FpcSelectedSha: string;
    LazSelectedSha: string;
    // when True, pipeline mirrors every Log() line to <TargetDir>\installer.log (truncated each run)
    SaveLog: Boolean;
  end;

  TInstallLogEvent      = procedure(const msg: string) of object;
  TInstallProgressEvent = procedure(Percent: Integer; const status: string) of object;

  // pipeline stages, ordered. each gets a slice of the 0..100 overall
  // bar via STAGE_END below. boundaries are tuned to typical wall-clock
  // proportions: build steps dominate, downloads + cfg are short.
  TInstallStage = (
    isInit,
    isBootstrap,        //  0..8    download + extract bootstrap zip
    isFpcSrc,           //  8..14   download + extract fpc source
    isFpcMakeAll,       // 14..40   make all (~5-10 min)
    isFpcMakeUtils,     // 40..44   make utils
    isFpcMakeInstall,   // 44..48   make install
    isFpcCfg,           // 48..49   fpcmkcfg (must run before any cross
                        //          step so Linux cross can patch fpc.cfg)
    isFpcCross,         // 49..63   crossinstall i386-win32 (~3-5 min)
    isFpcCrossWasm,     // 63..65   crossinstall wasm32-wasip1 (~2 min)
    isFpcCrossLinux64,  // 65..71   crossinstall x86_64-linux (~5-10 min)
    isFpcCrossLinux32,  // 71..77   crossinstall i386-linux (~5-10 min)
    isLazSrc,           // 77..80   download + extract lazarus
    isLazMakelazbuild,  // 80..85   make lazbuild prereqs
    isLazPackages,      // 85..89   N x lazbuild --add-package
    isLazIde,           // 89..97   lazbuild --build-ide
    isLazConfig,        // 97..98   write env opts + ack files
    isShortcut,         // 98..99   desktop shortcut
    isDone);            // 100

  TInstallThread = class(TThread)
  private
    FCfg: TInstallConfig;
    FOnLog: TInstallLogEvent;
    FOnProgress: TInstallProgressEvent;
    FSuccess: Boolean;
    FErrorMsg: string;
    FStage: TInstallStage;
    // marshalled fields (thread writes, main reads in Sync*)
    FLogMsg: string;
    FProgressMsg: string;
    FProgressPct: Integer;
    // optional installer.log writer; nil when save-log is off. owned
    // and freed inside Execute so lifetime is exactly the pipeline run.
    FLogStream: TFileStream;
    procedure SyncLog;
    procedure SyncProgress;
    procedure Log(const msg: string);
    procedure Progress(Percent: Integer; const status: string);
    procedure SetStage(s: TInstallStage);
    procedure OnMakeLine(const Line: string);
    function ResolveLogPath: string;
    function StepBootstrap: Boolean;
    function StepDownloadFpcSource: Boolean;
    function StepBuildFpcNative: Boolean;
    function StepBuildFpcCross: Boolean;
    function StepRemoveCrossWin32: Boolean;
    function StepBuildFpcCrossWasm: Boolean;
    function StepRemoveCrossWasm: Boolean;
    function StepBuildFpcCrossLinux64: Boolean;
    function StepRemoveCrossLinux64: Boolean;
    function StepBuildFpcCrossLinux32: Boolean;
    function StepRemoveCrossLinux32: Boolean;
    function DownloadAndVerify(const Url, Sha, DestZip, StepLabel: string): Boolean;
    function UnpackLinuxCross(const Tag, BinUrl, BinSha, LibUrl, LibSha, BinDir, LibDir: string): Boolean;
    function LinuxCommonMakeArgs(const TargetCpu, BinDir, LibDir, BinPrefix: string): TStringArray;
    function PatchFpcCfgCrossSection(const TargetOs, TargetCpu, BinDir, LibDir, BinPrefix: string; Add: Boolean): Boolean;
    procedure StepM3Cleanup;
    function StepGenerateFpcCfg: Boolean;
    function StepRebuildLazarusForAddons: Boolean;
    procedure UnregisterIdePackage(const PkgName: string);
    function StepDownloadLazarusSource: Boolean;
    function StepBuildLazarus: Boolean;
    function StepGenerateLazarusConfig: Boolean;
    function StepCreateDesktopShortcut: Boolean;
    function ResolveLazarusRef: string;
    function LazarusDir: string;
    function LazarusPcp: string;
    function ShortcutLabel: string;
    function RunLazbuild(const Args: array of string; const StepLabel: string): Boolean;
    function AddPackage(const LpkRel: string; LinkOnly: Boolean=False): Boolean;
    function WriteConfigFile(const FilePath, Content: string): Boolean;
    function ResolveFpcRef: string;
    function MakeWorkDir: string;
    function BootstrapBinDir: string;
    function RunMake(const Args: array of string; const StepLabel: string): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const Cfg: TInstallConfig; ALog: TInstallLogEvent; AProgress: TInstallProgressEvent; AOnTerminate: TNotifyEvent);
    property Success: Boolean read FSuccess;
    property ErrorMsg: string read FErrorMsg;
  end;

const
  // portable extract of the Inno Setup fpc-3.2.2.i386-win32.exe (no registry/PATH/file-assoc side effects)
  // ppc386.exe (i386-win32 native) bootstraps unleashed; combo bundle + ppcrossx64 trips 'Cannot open x86_64.inc' on native make all
  BOOTSTRAP_URL = 'https://github.com/fpc-unleashed/freepascal/releases/download/bootstrappers-v1/fpc-3.2.2-i386-win32-portable.zip';
  BOOTSTRAP_SHA = '0DFB6E34EC1FB1E89B5EAEA90E3A514B1F37867AE91989FA18143750EB39BF30';

  // codeload accepts branch, tag, full or short SHA in <ref>
  FPC_SOURCE_URL_PREFIX     = 'https://codeload.github.com/fpc-unleashed/freepascal/zip/';
  LAZARUS_SOURCE_URL_PREFIX = 'https://codeload.github.com/fpc-unleashed/lazarus/zip/';

  // cross-toolchain mirrors; _BIN = Win32 PE binutils producing Linux ELF, _LIB = glibc runtime + Ubuntu 18.04 .so
  CROSS_LINUX64_BIN_URL = 'https://github.com/fpc-unleashed/freepascal/releases/download/bootstrappers-v1/Linux_AMD64_Linux_V241.zip';
  CROSS_LINUX64_BIN_SHA = 'BE7F575C4383C98F4A14D22CD939C58C9D8A458B8E3FC2125348ECA5E9826733';
  CROSS_LINUX64_LIB_URL = 'https://github.com/fpc-unleashed/freepascal/releases/download/bootstrappers-v1/Linux_AMD64_Ubuntu_1804.zip';
  CROSS_LINUX64_LIB_SHA = '674B1CB4A21E0CE7000B848CB75E201CD2E317C8E71833C76D9EAD05FD7DF221';
  CROSS_LINUX32_BIN_URL = 'https://github.com/fpc-unleashed/freepascal/releases/download/bootstrappers-v1/Linux_i386_Linux_V241.zip';
  CROSS_LINUX32_BIN_SHA = '119459D71FB54ECBA5760BDE0D96AA4455C16C7AC9A5F8CC3E2C0CC02B8E48E3';
  CROSS_LINUX32_LIB_URL = 'https://github.com/fpc-unleashed/freepascal/releases/download/bootstrappers-v1/Linux_i386_Ubuntu_1804.zip';
  CROSS_LINUX32_LIB_SHA = 'A09F3168FFCBBF21AD15A3FD0A6A88C0DD4123FA6FF47B18C63701A7A05728EA';

implementation

uses
  XMLConf, download_util, hash_util, zip_util, proc_util, shortcut_util,
  install_manifest;

const
  // upper bound (on 0..100) of each stage's overall-progress slice.
  // index 0 (isInit) is implicitly 0; subsequent values are the cap.
  STAGE_END: array[TInstallStage] of Byte = (
    0,    // isInit
    8,    // isBootstrap
    14,   // isFpcSrc
    40,   // isFpcMakeAll
    44,   // isFpcMakeUtils
    48,   // isFpcMakeInstall
    49,   // isFpcCfg
    63,   // isFpcCross
    65,   // isFpcCrossWasm
    71,   // isFpcCrossLinux64
    77,   // isFpcCrossLinux32
    80,   // isLazSrc
    85,   // isLazMakelazbuild
    89,   // isLazPackages
    97,   // isLazIde
    98,   // isLazConfig
    99,   // isShortcut
    100); // isDone

  STAGE_NAME: array[TInstallStage] of string = (
    'init',
    'bootstrap FPC 3.2.2',
    'fpc-unleashed source',
    'building native FPC',
    'building utils',
    'installing FPC',
    'fpc.cfg',
    'building i386 cross compiler',
    'building wasm cross compiler',
    'building x86_64-linux cross compiler',
    'building i386-linux cross compiler',
    'lazarus source',
    'building lazbuild + LCL',
    'registering Lazarus packages',
    'building Lazarus IDE',
    'writing IDE config',
    'desktop shortcut',
    'done');

const
  // baked minimal Lazarus environmentoptions.xml. Version 112 / Lazarus
  // 4.99 matches the current main of fpc-unleashed/lazarus.
  // ActiveDesktop="default docked" makes the IDE start in single-window
  // dock layout (anchordockingdsgn handles the runtime when the package
  // is installed - which we do via lazbuild --add-package).
  // InitialFPCSrcRescanDone skips the slow first-launch scan over <fpcsrc>.
  ENV_OPTIONS_TEMPLATE: string =
    '<?xml version="1.0" encoding="UTF-8"?>'#13#10 +
    '<CONFIG>'#13#10 +
    '  <EnvironmentOptions>'#13#10 +
    '    <Version Lazarus="4.99" Value="112"/>'#13#10 +
    '    <Language ID="en"/>'#13#10 +
    '    <LazarusDirectory Value="%LAZ%"/>'#13#10 +
    '    <CompilerFilename Value="%FPC%"/>'#13#10 +
    '    <FPCSourceDirectory Value="%FPCSRC%"/>'#13#10 +
    '    <MakeFilename Value="%MAKE%"/>'#13#10 +
    '    <TestBuildDirectory Value="%PROJECTS%"/>'#13#10 +
    '    <InitialFPCSrcRescanDone Value="True"/>'#13#10 +
    '  </EnvironmentOptions>'#13#10 +
    // explicit Desktop1 + Desktop2 so the IDE has named entries to
    // activate; DockMaster ties Desktop2 to anchordocking. layout
    // details (window positions etc.) are filled in on first save.
    '  <Desktops Count="2" ActiveDesktop="default docked">'#13#10 +
    '    <Desktop1 Name="default"/>'#13#10 +
    '    <Desktop2 Name="default docked" DockMaster="TIDEAnchorDockMaster"/>'#13#10 +
    '  </Desktops>'#13#10 +
    '</CONFIG>'#13#10;

  // pre-acknowledge the "Enable anchor docking?" prompt. without this
  // the IDE shows a blocking dialog on first run.
  ANCHOR_DOCKING_OPTIONS: string =
    '<?xml version="1.0" encoding="UTF-8"?>'#13#10 +
    '<CONFIG>'#13#10 +
    '  <DoneAskUserEnableAnchorDock Value="True"/>'#13#10 +
    '</CONFIG>'#13#10;

  // pre-acknowledge the "Enable docked form designer?" prompt.
  DOCKED_FORM_EDITOR_OPTIONS: string =
    '<?xml version="1.0" encoding="UTF-8"?>'#13#10 +
    '<CONFIG>'#13#10 +
    '  <DoneAskUserEnableDockedDesigner Value="True"/>'#13#10 +
    '</CONFIG>'#13#10;

  // FpDebug is the user fork's preferred backend (modern, internal, no
  // external gdb.exe required). without this file the IDE pops the
  // "Configure Lazarus IDE" wizard on first launch with a red "!" on
  // the Debugger tab. UID is a fixed GUID matching unleashed21's
  // reference install.
  DEBUGGER_OPTIONS: string =
    '<?xml version="1.0" encoding="UTF-8"?>'#13#10 +
    '<CONFIG>'#13#10 +
    '  <Debugger Version="1">'#13#10 +
    '    <Backends Version="1">'#13#10 +
    '      <Config ConfigName="FpDebug" ConfigClass="TFpDebugDebugger" Active="True" UID="{65D78958-7ADA-40EE-B528-5FFCB08E4544}"/>'#13#10 +
    '    </Backends>'#13#10 +
    '  </Debugger>'#13#10 +
    '</CONFIG>'#13#10;

constructor TInstallThread.Create(const Cfg: TInstallConfig; ALog: TInstallLogEvent; AProgress: TInstallProgressEvent; AOnTerminate: TNotifyEvent);
begin
  inherited Create(True);
  FCfg := Cfg;
  FOnLog := ALog;
  FOnProgress := AProgress;
  FreeOnTerminate := True;
  OnTerminate := AOnTerminate;
  Start;
end;

procedure TInstallThread.SyncLog;
begin
  if Assigned(FOnLog) then FOnLog(FLogMsg);
end;

procedure TInstallThread.SyncProgress;
begin
  if Assigned(FOnProgress) then FOnProgress(FProgressPct, FProgressMsg);
end;

procedure TInstallThread.Log(const msg: string);
begin
  if FLogStream <> nil then begin
    var line: AnsiString := AnsiString(FormatDateTime('hh:nn:ss', Now)+'  '+msg+LineEnding);
    if Length(line) > 0 then FLogStream.WriteBuffer(line[1], Length(line));
  end;
  FLogMsg := msg;
  Synchronize(@SyncLog);
end;

// Percent is LOCAL pct of current stage (0..100), or -1 for marquee; remap to overall via STAGE_END
procedure TInstallThread.Progress(Percent: Integer; const status: string);
begin
  var rangeStart := if FStage = isInit then 0 else STAGE_END[Pred(FStage)];
  var rangeEnd   := STAGE_END[FStage];
  if Percent < 0 then FProgressPct := -1
  else begin
    if Percent > 100 then Percent := 100;
    FProgressPct := rangeStart+Round((rangeEnd-rangeStart)*Percent / 100);
  end;
  FProgressMsg := STAGE_NAME[FStage]+': '+status;
  Synchronize(@SyncProgress);
end;

procedure TInstallThread.SetStage(s: TInstallStage);
begin
  FStage := s;
  // park bar at stage start (= prev stage end); status shows stage name until sub-progress arrives
  Progress(0, '...');
end;

// installer.log alongside installer.ini in install dir; truncated each run (fmCreate in Execute)
function TInstallThread.ResolveLogPath: string;
begin
  Result := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'installer.log';
end;

// pull "[ NN%]" out of a lazbuild --build-ide line and feed it into the current stage's progress
function ExtractLazbuildPercent(const Line: string; out Pct: Integer): Boolean;
begin
  Result := False;
  var pOpen := Pos('[', Line);
  if pOpen = 0 then Exit;
  var pClose := Pos('%]', Line);
  if (pClose = 0) or (pClose < pOpen) then Exit;
  Pct := StrToIntDef(Trim(Copy(Line, pOpen+1, pClose-pOpen-1)), -1);
  Result := (Pct >= 0) and (Pct <= 100);
end;

procedure TInstallThread.OnMakeLine(const Line: string);
begin
  // drop Hint/Note to keep the user-visible log readable; Warning and structural lines still come through
  if Pos('Hint:', Line) > 0 then Exit;
  if Pos('Note:', Line) > 0 then Exit;
  Log(Line);
  // lazbuild --build-ide emits "[ NN%] ..." per package; map to current stage's progress slice
  var Pct: Integer;
  if ExtractLazbuildPercent(Line, Pct) then Progress(Pct, Trim(Copy(Line, Pos('%]', Line)+2, MaxInt)));
end;

function TInstallThread.ResolveFpcRef: string;
begin
  Result := if (not FCfg.FpcLatest) and (FCfg.FpcHash <> '') then FCfg.FpcHash else FCfg.FpcBranch;
end;

function TInstallThread.MakeWorkDir: string;
begin
  // FPC source at <install>\fpcsrc, sibling of fpc/ and lazarus/; referenced by make + IDE config
  Result := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpcsrc';
end;

function TInstallThread.BootstrapBinDir: string;
begin
  Result := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc322\bin\i386-win32';
end;

function TInstallThread.StepBootstrap: Boolean;
begin
  Result := False;
  var ZipFile      := IncludeTrailingPathDelimiter(GetTempDir)+'fpc-3.2.2-i386-win32-portable.zip';
  var BootstrapDir := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc322';

  Log('Downloading portable bootstrap FPC 3.2.2');
  Log('  URL: '+BOOTSTRAP_URL);
  Progress(0, 'Downloading bootstrap...');
  if not DownloadFile(BOOTSTRAP_URL, ZipFile, @Progress) then begin
    FErrorMsg := 'bootstrap download failed';
    Exit;
  end;

  Log('Verifying SHA256...');
  Progress(-1, 'Verifying SHA256');
  var ActualHash := SHA256OfFile(ZipFile);
  if ActualHash <> BOOTSTRAP_SHA then begin
    Log('  expected: '+BOOTSTRAP_SHA);
    Log('  actual:   '+ActualHash);
    FErrorMsg := 'bootstrap SHA256 mismatch';
    Exit;
  end;
  Log('  OK');

  Log('Extracting bootstrap to '+BootstrapDir);
  Progress(0, 'Extracting bootstrap...');
  if not ExtractZip(ZipFile, BootstrapDir, @Progress) then begin
    FErrorMsg := 'bootstrap extract failed';
    Exit;
  end;
  DeleteFile(ZipFile);

  Log('Bootstrap ready: '+BootstrapDir+'\bin\i386-win32\ppc386.exe');
  Result := True;
end;

// codeload leaves a single top-level dir like "freepascal-<sha>"; return its name, or '' if not exactly one
function FindOnlyTopDir(const ParentDir: string): string;
var
  SR: TSearchRec;
  Count: Integer;
begin
  Result := '';
  Count := 0;
  if FindFirst(IncludeTrailingPathDelimiter(ParentDir)+'*', faDirectory, SR) = 0 then begin
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      if (SR.Attr and faDirectory) = 0 then Continue;
      Inc(Count);
      if Count = 1 then Result := SR.Name else Result := '';
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  if Count <> 1 then Result := '';
end;

function TInstallThread.StepDownloadFpcSource: Boolean;
begin
  Result := False;
  var Ref     := ResolveFpcRef;
  var Url     := FPC_SOURCE_URL_PREFIX+Ref;
  var ZipFile := IncludeTrailingPathDelimiter(GetTempDir)+'fpc-unleashed-source.zip';
  var Target  := MakeWorkDir;
  // hidden temp parent so FindOnlyTopDir works regardless of siblings in TargetDir
  var TempParent := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'.fpcsrc-extract';

  if DirectoryExists(Target) then begin
    Log('Removing existing '+Target);
    Progress(-1, 'Cleaning previous source...');
    RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', Target]);
  end;
  if DirectoryExists(TempParent) then RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', TempParent]);
  ForceDirectories(TempParent);

  Log('Downloading fpc-unleashed source (ref='+Ref+')');
  Log('  URL: '+Url);
  Progress(0, 'Downloading source...');
  if not DownloadFile(Url, ZipFile, @Progress) then begin
    FErrorMsg := 'source download failed';
    Exit;
  end;

  Log('Extracting source');
  Progress(0, 'Extracting source...');
  if not ExtractZip(ZipFile, TempParent, @Progress) then begin
    FErrorMsg := 'source extract failed';
    Exit;
  end;
  DeleteFile(ZipFile);

  // codeload top dir is "freepascal-<sha>"; rename it to "fpcsrc"
  var ExtractedTopDir := FindOnlyTopDir(TempParent);
  if ExtractedTopDir = '' then begin
    FErrorMsg := 'unexpected source archive layout (no single top dir)';
    Exit;
  end;
  if not RenameFile(IncludeTrailingPathDelimiter(TempParent)+ExtractedTopDir, Target) then begin
    FErrorMsg := 'cannot rename '+ExtractedTopDir+' to fpcsrc';
    Exit;
  end;
  RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', TempParent]);

  Log('Source ready: '+Target);
  Result := True;
end;

// run <bootstrap>\make.exe with PATH = bootstrap bin (binutils as.exe/ld.exe/ar.exe ship alongside)
function TInstallThread.RunMake(const Args: array of string; const StepLabel: string): Boolean;
begin
  var MakeExe := IncludeTrailingPathDelimiter(BootstrapBinDir)+'make.exe';
  var ArgList := '';
  for var i := Low(Args) to High(Args) do begin
    if ArgList <> '' then ArgList := ArgList+' ';
    ArgList := ArgList+Args[i];
  end;
  Log('Running: make '+ArgList);
  Progress(-1, StepLabel);
  var ExitCode := RunStream(MakeExe, Args, MakeWorkDir, BootstrapBinDir, @OnMakeLine);
  Result := ExitCode = 0;
  if not Result then begin
    FErrorMsg := StepLabel+' failed (make exit='+IntToStr(ExitCode)+')';
    Log('  '+FErrorMsg);
  end;
end;

function TInstallThread.StepBuildFpcNative: Boolean;
begin
  Result := False;
  // ppc386 (FPC 3.2.2 i386 native) bootstraps the x86_64 unleashed compiler; x86_64 bootstrap breaks native make all
  var PpBootstrap      := IncludeTrailingPathDelimiter(BootstrapBinDir)+'ppc386.exe';
  var WorkDir          := MakeWorkDir;
  var PpSelf           := IncludeTrailingPathDelimiter(WorkDir)+'compiler\ppcx64.exe';
  var FpcInstallPrefix := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc';

  Log('--- Building native FPC x86_64-win64 ---');
  Log('  source dir:      '+WorkDir);
  Log('  bootstrap PP:    '+PpBootstrap);
  Log('  install prefix:  '+FpcInstallPrefix);

  // distclean is brief; bundled into make-all stage start
  SetStage(isFpcMakeAll);
  if not RunMake(['distclean'], 'make distclean') then Exit;

  if not RunMake(['all', 'OS_TARGET=win64', 'CPU_TARGET=x86_64', 'PP='+PpBootstrap], 'make all (native FPC, ~5-10 min)') then Exit;

  SetStage(isFpcMakeUtils);
  if not RunMake(['utils', 'OS_TARGET=win64', 'CPU_TARGET=x86_64', 'PP='+PpSelf], 'make utils') then Exit;

  SetStage(isFpcMakeInstall);
  if not RunMake(['install', 'OS_TARGET=win64', 'CPU_TARGET=x86_64', 'INSTALL_PREFIX='+FpcInstallPrefix, 'PP='+PpSelf], 'make install') then Exit;

  Log('--- Native FPC ready: '+FpcInstallPrefix+'\bin\x86_64-win64\ppcx64.exe ---');
  Result := True;
end;

function TInstallThread.StepBuildFpcCross: Boolean;
begin
  Result := False;
  var PpSelf           := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc\bin\x86_64-win64\ppcx64.exe';
  var FpcInstallPrefix := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc';

  Log('--- Building cross-compiler i386-win32 ---');
  // -dFPC_SOFT_FPUX80 required: x86_64 host lacks FPC_HAS_TYPE_EXTENDED, fpcdefs.inc:432 blocks i386 cross without soft-x80
  if not RunMake(['crossinstall', 'OS_TARGET=win32', 'CPU_TARGET=i386', 'INSTALL_PREFIX='+FpcInstallPrefix, 'PP='+PpSelf, 'OPT=-dFPC_SOFT_FPUX80'],
    'make crossinstall (i386-win32, ~5 min)') then Exit;

  Log('--- Cross-compiler ready: '+FpcInstallPrefix+'\bin\x86_64-win64\ppcross386.exe ---');
  Result := True;
end;

function TInstallThread.StepBuildFpcCrossWasm: Boolean;
begin
  Result := False;
  var PpSelf           := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc\bin\x86_64-win64\ppcx64.exe';
  var FpcInstallPrefix := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc';

  Log('--- Building cross-compiler wasm32-wasip1 ---');
  // internal WASM linker, no external binutils/libc; OS target 'wasip1' (current Makefile rejects 'wasi')
  if not RunMake(['crossinstall', 'OS_TARGET=wasip1', 'CPU_TARGET=wasm32', 'INSTALL_PREFIX='+FpcInstallPrefix, 'PP='+PpSelf],
    'make crossinstall (wasm32-wasip1, ~2 min)') then Exit;

  Log('--- Cross-compiler ready: '+FpcInstallPrefix+'\bin\x86_64-win64\ppcrosswasm32.exe ---');
  Result := True;
end;

function TInstallThread.StepRemoveCrossWasm: Boolean;
begin
  Result := True;  // best-effort
  var FpcInstall := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc';
  var PpcrossBin := IncludeTrailingPathDelimiter(FpcInstall)+'bin\x86_64-win64\ppcrosswasm32.exe';
  var UnitsDir   := IncludeTrailingPathDelimiter(FpcInstall)+'units\wasm32-wasip1';

  Log('Removing cross compiler wasm32-wasip1');
  Progress(-1, 'Removing wasm32-wasip1');
  if FileExists(PpcrossBin) then begin
    Log('  '+PpcrossBin);
    DeleteFile(PpcrossBin);
  end;
  if DirectoryExists(UnitsDir) then begin
    Log('  '+UnitsDir);
    RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', UnitsDir]);
  end;
end;

// download zip + verify SHA256; shared by cross-Linux 64/32 (each pulls BIN binutils + LIB glibc/runtime)
function TInstallThread.DownloadAndVerify(const Url, Sha, DestZip, StepLabel: string): Boolean;
begin
  Result := False;
  Log('Downloading '+StepLabel);
  Log('  URL: '+Url);
  Progress(0, 'Downloading '+StepLabel+'...');
  if not DownloadFile(Url, DestZip, @Progress) then begin
    FErrorMsg := StepLabel+' download failed';
    Exit;
  end;
  Progress(-1, 'Verifying SHA256');
  var ActualHash := SHA256OfFile(DestZip);
  if not SameText(ActualHash, Sha) then begin
    Log('  expected: '+Sha);
    Log('  actual:   '+ActualHash);
    FErrorMsg := StepLabel+' SHA256 mismatch';
    Exit;
  end;
  Log('  OK');
  Result := True;
end;

// add/remove a per-target cross section in fpc.cfg; tagged BEGIN/END markers let re-installs strip cleanly
// Add=False removes any existing tagged block (used by StepRemoveCrossLinux*)
function TInstallThread.PatchFpcCfgCrossSection(const TargetOs, TargetCpu, BinDir, LibDir, BinPrefix: string; Add: Boolean): Boolean;
begin
  Result := False;
  var CfgPath := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc\bin\x86_64-win64\fpc.cfg';
  if not FileExists(CfgPath) then begin
    Log('  fpc.cfg not present yet; skipping cross-section patch');
    Result := True;
    Exit;
  end;

  var Tag   := '# fpc-unleashed-cross '+TargetCpu+'-'+TargetOs;
  var Lines := autofree TStringList.Create;
  try
    Lines.LoadFromFile(CfgPath);
  except
    on E: Exception do begin
      FErrorMsg := 'cannot read fpc.cfg: '+E.Message;
      Exit;
    end;
  end;

  // strip any existing block with this tag
  var i := 0;
  while i < Lines.Count do begin
    if Pos('# BEGIN '+Tag, Lines[i]) > 0 then begin
      var endIdx := i;
      while (endIdx < Lines.Count) and (Pos('# END '+Tag, Lines[endIdx]) = 0) do Inc(endIdx);
      if endIdx < Lines.Count then begin
        for var k := endIdx downto i do Lines.Delete(k);
        Continue;
      end;
    end;
    Inc(i);
  end;

  if Add then begin
    Lines.Add('# BEGIN '+Tag);
    Lines.Add('#ifdef '+TargetOs);
    Lines.Add('#ifdef cpu'+TargetCpu);
    Lines.Add('-XP'+IncludeTrailingPathDelimiter(BinDir)+BinPrefix);
    Lines.Add('-FD'+BinDir);
    Lines.Add('-Fl'+LibDir);
    Lines.Add('#endif');
    Lines.Add('#endif');
    Lines.Add('# END '+Tag);
  end;

  try
    Lines.SaveToFile(CfgPath);
    Result := True;
  except
    on E: Exception do begin
      FErrorMsg := 'cannot write fpc.cfg: '+E.Message;
      Log('  '+FErrorMsg);
    end;
  end;
end;

// shared Linux-cross make args; explicit OS_SOURCE/CPU_SOURCE/FPCDIR/FPCFPMAKE keeps make from inferring host triple from an i386 PP
function TInstallThread.LinuxCommonMakeArgs(const TargetCpu, BinDir, LibDir, BinPrefix: string): TStringArray;
begin
  Result := [
    'OS_TARGET=linux',
    'CPU_TARGET='+TargetCpu,
    'OS_SOURCE=win64',
    'CPU_SOURCE=x86_64',
    'FPCDIR='+MakeWorkDir,
    'FPCFPMAKE='+IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc\bin\x86_64-win64\ppcx64.exe',
    'INSTALL_PREFIX='+IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc',
    'BINUTILSPREFIX='+BinPrefix,
    'CROSSBINDIR='+BinDir,
    'CROSSOPT=-Fl'+LibDir,
    'CROSSINSTALL=1'
  ];
end;

// shared download+extract for both Linux cross zips; returns False with FErrorMsg set
function TInstallThread.UnpackLinuxCross(const Tag, BinUrl, BinSha, LibUrl, LibSha, BinDir, LibDir: string): Boolean;
begin
  Result := False;
  ForceDirectories(BinDir);
  ForceDirectories(LibDir);

  var BinZip := IncludeTrailingPathDelimiter(GetTempDir)+'cross-'+Tag+'-bin.zip';
  if not DownloadAndVerify(BinUrl, BinSha, BinZip, 'cross-binutils '+Tag) then Exit;
  Progress(0, 'Extracting binutils...');
  if not ExtractZip(BinZip, BinDir, @Progress) then begin
    FErrorMsg := 'cross-binutils '+Tag+' extract failed';
    Exit;
  end;
  DeleteFile(BinZip);

  var LibZip := IncludeTrailingPathDelimiter(GetTempDir)+'cross-'+Tag+'-lib.zip';
  if not DownloadAndVerify(LibUrl, LibSha, LibZip, 'cross-libs '+Tag) then Exit;
  Progress(0, 'Extracting libs...');
  if not ExtractZip(LibZip, LibDir, @Progress) then begin
    FErrorMsg := 'cross-libs '+Tag+' extract failed';
    Exit;
  end;
  DeleteFile(LibZip);

  Result := True;
end;

function TInstallThread.StepBuildFpcCrossLinux64: Boolean;
begin
  Result := False;
  // staged compile (not `make crossinstall`): compiler_cycle/_install with host PP+soft-x80, rtl_*/packages_* with fresh ppcrossx64
  // a single FPC=host across the whole crossinstall trips IE 200208151 (with soft-x80) or IE 2015030501 (without)

  var CrossDir := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'cross\x86_64-linux';
  var BinDir   := IncludeTrailingPathDelimiter(CrossDir)+'bin';
  var LibDir   := IncludeTrailingPathDelimiter(CrossDir)+'lib';

  Log('--- Building cross-compiler x86_64-linux ---');
  if not UnpackLinuxCross('x86_64-linux', CROSS_LINUX64_BIN_URL, CROSS_LINUX64_BIN_SHA, CROSS_LINUX64_LIB_URL, CROSS_LINUX64_LIB_SHA, BinDir, LibDir) then Exit;

  var PpHost           := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc\bin\x86_64-win64\ppcx64.exe';
  var PpCrossInstalled := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc\bin\x86_64-win64\ppcrossx64.exe';
  var Common           := LinuxCommonMakeArgs('x86_64', BinDir, LibDir, 'x86_64-linux-gnu-');

  // stage 1: compiler_cycle (host PP + soft-x80) -> produces ppcrossx64.exe
  Log('  stage 1/6: compiler_cycle (build ppcrossx64 with soft-x80)');
  if not RunMake(['compiler_cycle', 'FPC='+PpHost, 'OPT=-dFPC_SOFT_FPUX80']+Common, 'compiler_cycle (x86_64-linux, ~3 min)') then Exit;

  var PpCrossBuilt := IncludeTrailingPathDelimiter(MakeWorkDir)+'compiler\ppcrossx64.exe';
  if not FileExists(PpCrossBuilt) then begin
    FErrorMsg := 'compiler_cycle did not produce '+PpCrossBuilt;
    Log('  '+FErrorMsg);
    Exit;
  end;
  Log('  freshly-built ppcrossx64: '+PpCrossBuilt);

  // stage 2: compiler_install (still host PP) -> copies ppcrossx64 to bin/
  Log('  stage 2/6: compiler_install (place ppcrossx64.exe in bin/)');
  if not RunMake(['compiler_install', 'FPC='+PpHost]+Common, 'compiler_install (x86_64-linux)') then Exit;

  var PpForRtl := if FileExists(PpCrossInstalled) then PpCrossInstalled else PpCrossBuilt;
  Log('  using cross compiler for RTL/packages: '+PpForRtl);

  // stages 3-4: rtl_all + rtl_install, FPC=cross compiler, no OPT
  Log('  stage 3/6: rtl_all (RTL via ppcrossx64)');
  if not RunMake(['rtl_all',     'FPC='+PpForRtl]+Common, 'rtl_all (x86_64-linux)') then Exit;
  Log('  stage 4/6: rtl_install');
  if not RunMake(['rtl_install', 'FPC='+PpForRtl]+Common, 'rtl_install (x86_64-linux)') then Exit;

  // stages 5-6: packages
  Log('  stage 5/6: packages_all (packages via ppcrossx64)');
  if not RunMake(['packages_all',     'FPC='+PpForRtl]+Common, 'packages_all (x86_64-linux, ~3 min)') then Exit;
  Log('  stage 6/6: packages_install');
  if not RunMake(['packages_install', 'FPC='+PpForRtl]+Common, 'packages_install (x86_64-linux)') then Exit;

  if not PatchFpcCfgCrossSection('linux', 'x86_64', BinDir, LibDir, 'x86_64-linux-gnu-', True) then Exit;

  Log('--- Cross-compile to x86_64-linux ready ---');
  Result := True;
end;

function TInstallThread.StepRemoveCrossLinux64: Boolean;
begin
  Result := True;  // best-effort
  var CrossDir := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'cross\x86_64-linux';
  var UnitsDir := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc\units\x86_64-linux';

  Log('Removing cross compiler x86_64-linux');
  Progress(-1, 'Removing x86_64-linux');
  if DirectoryExists(UnitsDir) then begin
    Log('  '+UnitsDir);
    RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', UnitsDir]);
  end;
  if DirectoryExists(CrossDir) then begin
    Log('  '+CrossDir);
    RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', CrossDir]);
  end;
  PatchFpcCfgCrossSection('linux', 'x86_64', '', '', '', False);
end;

function TInstallThread.StepBuildFpcCrossLinux32: Boolean;
begin
  Result := False;
  // i386-linux needs ppcross386 (built by i386-win32 step); supports both -Twin32 and -Tlinux at runtime
  var Pp := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc\bin\x86_64-win64\ppcross386.exe';
  if not FileExists(Pp) then begin
    FErrorMsg := 'i386-linux cross requires the i386-win32 cross compiler. Tick "i386-win32" in the cross list as well, then run install.';
    Log('  '+FErrorMsg);
    Exit;
  end;

  var CrossDir := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'cross\i386-linux';
  var BinDir   := IncludeTrailingPathDelimiter(CrossDir)+'bin';
  var LibDir   := IncludeTrailingPathDelimiter(CrossDir)+'lib';

  Log('--- Building cross-compiler i386-linux ---');
  if not UnpackLinuxCross('i386-linux', CROSS_LINUX32_BIN_URL, CROSS_LINUX32_BIN_SHA, CROSS_LINUX32_LIB_URL, CROSS_LINUX32_LIB_SHA, BinDir, LibDir) then Exit;

  var PpHost := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc\bin\x86_64-win64\ppcx64.exe';
  var Common := LinuxCommonMakeArgs('i386', BinDir, LibDir, 'i386-linux-gnu-');

  // skip compiler_cycle/_install: ppcross386 is already correct; rebuilding for OS_TARGET=linux trips "Cannot open i386.inc"
  // prior `make distclean` wiped compiler/msgtxt.inc + msgidx.inc; `msg` regenerates them cheaply
  Log('  stage 1/5: msg (regenerate compiler/msgtxt.inc + msgidx.inc)');
  if not RunMake(['-C', 'compiler', 'msg', 'FPC='+PpHost], 'msg (i386-linux prerequisite)') then Exit;

  // stages 2-3: rtl_all + rtl_install, FPC=ppcross386, no OPT (ppcross386 has soft-x80 baked in)
  Log('  stage 2/5: rtl_all (RTL via ppcross386)');
  if not RunMake(['rtl_all',     'FPC='+Pp]+Common, 'rtl_all (i386-linux)') then Exit;
  Log('  stage 3/5: rtl_install');
  if not RunMake(['rtl_install', 'FPC='+Pp]+Common, 'rtl_install (i386-linux)') then Exit;

  // stages 4-5: packages
  Log('  stage 4/5: packages_all (packages via ppcross386)');
  if not RunMake(['packages_all',     'FPC='+Pp]+Common, 'packages_all (i386-linux, ~3 min)') then Exit;
  Log('  stage 5/5: packages_install');
  if not RunMake(['packages_install', 'FPC='+Pp]+Common, 'packages_install (i386-linux)') then Exit;

  if not PatchFpcCfgCrossSection('linux', 'i386', BinDir, LibDir, 'i386-linux-gnu-', True) then Exit;

  Log('--- Cross-compile to i386-linux ready ---');
  Result := True;
end;

function TInstallThread.StepRemoveCrossLinux32: Boolean;
begin
  Result := True;  // best-effort
  var CrossDir := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'cross\i386-linux';
  var UnitsDir := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc\units\i386-linux';

  Log('Removing cross compiler i386-linux');
  Progress(-1, 'Removing i386-linux');
  if DirectoryExists(UnitsDir) then begin
    Log('  '+UnitsDir);
    RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', UnitsDir]);
  end;
  if DirectoryExists(CrossDir) then begin
    Log('  '+CrossDir);
    RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', CrossDir]);
  end;
  PatchFpcCfgCrossSection('linux', 'i386', '', '', '', False);
end;

function TInstallThread.ResolveLazarusRef: string;
begin
  Result := if (not FCfg.LazLatest) and (FCfg.LazHash <> '') then FCfg.LazHash else FCfg.LazBranch;
end;

function TInstallThread.LazarusDir: string;
begin
  Result := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'lazarus';
end;

function TInstallThread.LazarusPcp: string;
begin
  Result := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'config_lazarus';
end;

// strip 'unleashed-' prefix so C:\unleashed-2026-05-09 yields '2026-05-09'
function TInstallThread.ShortcutLabel: string;
const
  Prefix = 'unleashed-';
begin
  var Base := ExtractFileName(ExcludeTrailingPathDelimiter(FCfg.TargetDir));
  if (Length(Base) > Length(Prefix)) and (LowerCase(Copy(Base, 1, Length(Prefix))) = Prefix) then Delete(Base, 1, Length(Prefix));
  Result := 'Unleashed ('+Base+')';
end;

function TInstallThread.StepDownloadLazarusSource: Boolean;
begin
  Result := False;
  var Ref        := ResolveLazarusRef;
  var Url        := LAZARUS_SOURCE_URL_PREFIX+Ref;
  var ZipFile    := IncludeTrailingPathDelimiter(GetTempDir)+'lazarus-source.zip';
  var Target     := LazarusDir;
  // hidden temp parent so FindOnlyTopDir works regardless of siblings in install dir
  var TempParent := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'.lazarus-extract';

  if DirectoryExists(Target) then begin
    Log('Removing existing '+Target);
    Progress(-1, 'Cleaning previous lazarus...');
    RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', Target]);
  end;
  if DirectoryExists(TempParent) then RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', TempParent]);
  ForceDirectories(TempParent);

  Log('Downloading lazarus source (ref='+Ref+')');
  Log('  URL: '+Url);
  Progress(0, 'Downloading lazarus source...');
  if not DownloadFile(Url, ZipFile, @Progress) then begin
    FErrorMsg := 'lazarus download failed';
    Exit;
  end;

  Log('Extracting lazarus source');
  Progress(0, 'Extracting lazarus source...');
  if not ExtractZip(ZipFile, TempParent, @Progress) then begin
    FErrorMsg := 'lazarus extract failed';
    Exit;
  end;
  DeleteFile(ZipFile);

  var ExtractedTop := FindOnlyTopDir(TempParent);
  if ExtractedTop = '' then begin
    FErrorMsg := 'unexpected lazarus archive layout (no single top dir)';
    Exit;
  end;
  if not RenameFile(IncludeTrailingPathDelimiter(TempParent)+ExtractedTop, Target) then begin
    FErrorMsg := 'cannot rename '+ExtractedTop+' to lazarus';
    Exit;
  end;
  RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', TempParent]);

  Log('Lazarus source ready: '+Target);
  Result := True;
end;

const
  // Packages installed into the IDE statically. Base packages first
  // reduces dep churn (lazbuild resolves but is faster on a clean
  // queue). Paths relative to <lazarus>\.
  LAZ_BASE_PACKAGES: array[0..19] of string = (
    'components\lazcontrols\design\lazcontroldsgn.lpk',
    'components\datetimectrls\datetimectrls.lpk',
    'components\datetimectrls\design\datetimectrlsdsgn.lpk',
    'components\sdf\sdflaz.lpk',
    'components\codetools\ide\cody.lpk',
    'components\projecttemplates\projtemplates.lpk',
    'components\sqldb\sqldblaz.lpk',
    'components\memds\memdslaz.lpk',
    'components\tdbf\dbflaz.lpk',
    'components\fpcunit\ide\fpcunitide.lpk',
    'components\fpcunit\testinsight\laztestinsight.lpk',
    'components\daemon\lazdaemon.lpk',
    'components\leakview\leakview.lpk',
    'components\tachart\tachartlazaruspkg.lpk',
    'components\jcf2\IdePlugin\lazarus\jcfidelazarus.lpk',
    'components\chmhelp\packages\help\lhelpcontrolpkg.lpk',
    'components\chmhelp\packages\idehelp\chmhelppkg.lpk',
    'components\instantfpc\instantfpclaz.lpk',
    'components\externhelp\externhelp.lpk',
    'components\synedit\design\syneditdsgn.lpk');

  // Docked IDE. anchordocking added as link only; its dsgn package
  // pulls it in for IDE static linkage.
  LAZ_DOCKED_LINK_ONLY = 'components\anchordocking\anchordocking.lpk';
  LAZ_DOCKED_PACKAGES: array[0..1] of string = (
    'components\anchordocking\design\anchordockingdsgn.lpk',
    'components\dockedformeditor\dockedformeditor.lpk');

  // user fork's custom IDE addon
  LAZ_UNLEASHED_PACKAGES: array[0..0] of string = (
    'components\minimap\lazminimap.lpk');

function TInstallThread.RunLazbuild(const Args: array of string; const StepLabel: string): Boolean;
begin
  var LazbuildExe := IncludeTrailingPathDelimiter(LazarusDir)+'lazbuild.exe';
  var FpcBinDir   := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc\bin\x86_64-win64';
  var PathPrefix  := FpcBinDir+';'+BootstrapBinDir;

  // every lazbuild invocation gets the same boilerplate so package and IDE builds agree on pcp/cpu/os/lazarusdir
  var ArgsArr: array of string;
  begin
    var ExtArgs := autofree TStringList.Create;
    ExtArgs.Add('--pcp='+LazarusPcp);
    ExtArgs.Add('--lazarusdir='+LazarusDir);
    ExtArgs.Add('--cpu=x86_64');
    ExtArgs.Add('--os=win64');
    for var i := Low(Args) to High(Args) do ExtArgs.Add(Args[i]);
    SetLength(ArgsArr, ExtArgs.Count);
    for var i := 0 to ExtArgs.Count-1 do ArgsArr[i] := ExtArgs[i];
  end;

  Log('Running: lazbuild '+StepLabel);
  Progress(-1, StepLabel);
  var ExitCode := RunStream(LazbuildExe, ArgsArr, LazarusDir, PathPrefix, @OnMakeLine);
  Result := ExitCode = 0;
  if not Result then begin
    FErrorMsg := StepLabel+' failed (lazbuild exit='+IntToStr(ExitCode)+')';
    Log('  '+FErrorMsg);
  end;
end;

function TInstallThread.AddPackage(const LpkRel: string; LinkOnly: Boolean): Boolean;
begin
  var LpkPath := IncludeTrailingPathDelimiter(LazarusDir)+LpkRel;
  var Mode    := if LinkOnly then '--add-package-link' else '--add-package';
  Result := RunLazbuild([Mode, LpkPath], Mode+' '+ExtractFileName(LpkRel));
end;

function TInstallThread.StepBuildLazarus: Boolean;
begin
  Result := False;
  var MakeExe    := IncludeTrailingPathDelimiter(BootstrapBinDir)+'make.exe';
  var FpcBinDir  := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc\bin\x86_64-win64';
  var FpcExe     := IncludeTrailingPathDelimiter(FpcBinDir)+'fpc.exe';
  ForceDirectories(LazarusPcp);

  // native fpc.exe before bootstrap so lazbuild PATH-based detection picks the x86_64 wrapper; bootstrap stays for make/binutils
  var PathPrefix := FpcBinDir+';'+BootstrapBinDir;

  Log('--- Building Lazarus IDE ---');
  Log('  source dir: '+LazarusDir);
  Log('  PP:         '+FpcExe);

  // 1. build lazbuild + LCL + prereqs that the upcoming --add-package calls compile against
  SetStage(isLazMakelazbuild);
  Progress(-1, 'make lazbuild (LCL + lazbuild, ~3 min)');
  var ExitCode := RunStream(MakeExe, ['lazbuild', 'PP='+FpcExe], LazarusDir, PathPrefix, @OnMakeLine);
  if ExitCode <> 0 then begin
    FErrorMsg := 'lazbuild bootstrap failed (make exit='+IntToStr(ExitCode)+')';
    Log('  '+FErrorMsg);
    Exit;
  end;

  // 2. register packages with our isolated config_lazarus; lazbuild appends to staticpackages.inc + idemake.cfg
  SetStage(isLazPackages);
  Log('Registering base packages ('+IntToStr(Length(LAZ_BASE_PACKAGES))+')');
  for var i := Low(LAZ_BASE_PACKAGES) to High(LAZ_BASE_PACKAGES) do begin
    if not AddPackage(LAZ_BASE_PACKAGES[i]) then Exit;
    // smooth-fill the package-registration slice as each lpk lands
    Progress(Round((i+1)*100 / (Length(LAZ_BASE_PACKAGES)+Length(LAZ_DOCKED_PACKAGES)+Length(LAZ_UNLEASHED_PACKAGES)+1)), ExtractFileName(LAZ_BASE_PACKAGES[i]));
  end;

  Log('Registering docked-IDE packages');
  // anchordocking is runtime; the *dsgn variant is statically linked and depends on the runtime - add runtime as link-only
  if not AddPackage(LAZ_DOCKED_LINK_ONLY, True) then Exit;
  for var i := Low(LAZ_DOCKED_PACKAGES) to High(LAZ_DOCKED_PACKAGES) do
    if not AddPackage(LAZ_DOCKED_PACKAGES[i]) then Exit;

  if FCfg.InstallMinimap then begin
    Log('Registering fpc-unleashed addon packages');
    for var i := Low(LAZ_UNLEASHED_PACKAGES) to High(LAZ_UNLEASHED_PACKAGES) do
      if not AddPackage(LAZ_UNLEASHED_PACKAGES[i]) then Exit;
  end else
    Log('Skipping minimap addon (not selected)');

  // 3. final IDE build; -dKeepInstalledPackages preserves the list across rebuilds
  // lazarus/ide/packages/idepackager/packagesystem.pas:2533 emits -dAddStaticPkgs automatically; redundant on the call line
  // lazbuild prints "[ NN%]" lines that OnMakeLine catches and feeds back into progress
  SetStage(isLazIde);
  if not RunLazbuild(['--build-ide=-dKeepInstalledPackages'], 'lazbuild --build-ide (~5 min)') then Exit;

  Log('--- Lazarus ready: '+LazarusDir+'\lazarus.exe ---');
  Result := True;
end;

// edit miscellaneousoptions.xml + packagefiles.xml in-place to drop a package's IDE registration; needs `lazbuild --build-ide` after
procedure TInstallThread.UnregisterIdePackage(const PkgName: string);

  procedure RemoveIndexedItem(const XmlPath, KeyStart, ValuePath: string);
  begin
    if not FileExists(XmlPath) then Exit;
    var Cfg := autofree TXMLConfig.Create(nil);
    Cfg.Filename := XmlPath;
    var Cnt: Integer := Cfg.GetValue(KeyStart+'Count', 0);
    var Found: Integer := -1;
    var EmptyStr: string := '';
    for var i := 1 to Cnt do
      if SameText(Cfg.GetValue(KeyStart+'Item'+IntToStr(i)+'/'+ValuePath, EmptyStr), PkgName) then begin
        Found := i;
        Break;
      end;
    if Found < 1 then Exit;
    // shift remaining items down by one
    for var i := Found to Cnt-1 do
      Cfg.SetValue(KeyStart+'Item'+IntToStr(i)+'/'+ValuePath, Cfg.GetValue(KeyStart+'Item'+IntToStr(i+1)+'/'+ValuePath, EmptyStr));
    Cfg.DeletePath(KeyStart+'Item'+IntToStr(Cnt));
    Cfg.SetValue(KeyStart+'Count', Cnt-1);
    Cfg.Flush;
  end;

begin
  var Pcp := IncludeTrailingPathDelimiter(LazarusPcp);
  // miscellaneousoptions.xml controls what gets statically linked into the IDE on --build-ide
  RemoveIndexedItem(Pcp+'miscellaneousoptions.xml', 'MiscellaneousOptions/BuildLazarusOptions/StaticAutoInstallPackages/', 'Value');
  // packagefiles.xml is the IDE's known-packages list (Package menu, Open Package..., etc)
  RemoveIndexedItem(Pcp+'packagefiles.xml', 'UserPkgLinks/', 'Name/Value');
end;

// Reinstall with a flipped addon: add/remove the addon registration, then re-run --build-ide
function TInstallThread.StepRebuildLazarusForAddons: Boolean;
begin
  Result := False;
  var Prev := ReadManifest(FCfg.TargetDir);
  SetStage(isLazPackages);

  if FCfg.InstallMinimap and (not Prev.InstallMinimap) then begin
    Log('Adding minimap addon');
    for var i := Low(LAZ_UNLEASHED_PACKAGES) to High(LAZ_UNLEASHED_PACKAGES) do
      if not AddPackage(LAZ_UNLEASHED_PACKAGES[i]) then Exit;
  end else if (not FCfg.InstallMinimap) and Prev.InstallMinimap then begin
    Log('Removing minimap addon');
    UnregisterIdePackage('lazminimap');
  end;

  SetStage(isLazIde);
  if not RunLazbuild(['--build-ide=-dKeepInstalledPackages'], 'lazbuild --build-ide (~5 min)') then Exit;

  Log('--- Lazarus IDE rebuilt with new addon set ---');
  Result := True;
end;

function TInstallThread.WriteConfigFile(const FilePath, Content: string): Boolean;
begin
  Result := False;
  ForceDirectories(ExtractFilePath(FilePath));
  try
    var Stream := autofree TFileStream.Create(FilePath, fmCreate);
    if Length(Content) > 0 then Stream.WriteBuffer(Content[1], Length(Content));
    Result := True;
  except
    on E: Exception do begin
      FErrorMsg := 'cannot write '+FilePath+': '+E.Message;
      Log('  '+FErrorMsg);
    end;
  end;
end;

function TInstallThread.StepGenerateLazarusConfig: Boolean;
begin
  Result := False;
  Progress(-1, 'Writing Lazarus config');
  ForceDirectories(LazarusPcp);
  var ProjectsDir := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'projects';
  ForceDirectories(ProjectsDir);

  var Xml := ENV_OPTIONS_TEMPLATE;
  Xml := StringReplace(Xml, '%LAZ%',      LazarusDir,                                                                  [rfReplaceAll]);
  Xml := StringReplace(Xml, '%FPC%',      IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc\bin\x86_64-win64\fpc.exe', [rfReplaceAll]);
  Xml := StringReplace(Xml, '%FPCSRC%',   MakeWorkDir,                                                                 [rfReplaceAll]);
  Xml := StringReplace(Xml, '%MAKE%',     IncludeTrailingPathDelimiter(BootstrapBinDir)+'make.exe',                    [rfReplaceAll]);
  Xml := StringReplace(Xml, '%PROJECTS%', ProjectsDir,                                                                 [rfReplaceAll]);

  Log('Writing '+LazarusPcp+'\environmentoptions.xml');
  if not WriteConfigFile(IncludeTrailingPathDelimiter(LazarusPcp)+'environmentoptions.xml', Xml) then Exit;

  Log('Writing '+LazarusPcp+'\anchordockingoptions.xml');
  if not WriteConfigFile(IncludeTrailingPathDelimiter(LazarusPcp)+'anchordockingoptions.xml', ANCHOR_DOCKING_OPTIONS) then Exit;

  Log('Writing '+LazarusPcp+'\dockedformeditoroptions.xml');
  if not WriteConfigFile(IncludeTrailingPathDelimiter(LazarusPcp)+'dockedformeditoroptions.xml', DOCKED_FORM_EDITOR_OPTIONS) then Exit;

  Log('Writing '+LazarusPcp+'\debuggeroptions.xml');
  if not WriteConfigFile(IncludeTrailingPathDelimiter(LazarusPcp)+'debuggeroptions.xml', DEBUGGER_OPTIONS) then Exit;

  Result := True;
end;

function TInstallThread.StepCreateDesktopShortcut: Boolean;
begin
  var TargetExe := IncludeTrailingPathDelimiter(LazarusDir)+'lazarus.exe';
  // --pcp tells Lazarus to load our isolated config_lazarus instead of %LOCALAPPDATA%\lazarus
  var Args := '--pcp="'+LazarusPcp+'"';
  var Name := ShortcutLabel;
  Log('Creating desktop shortcut: '+Name);
  Progress(-1, 'Creating desktop shortcut');
  Result := CreateDesktopShortcut(TargetExe, Args, Name);
  if not Result then begin
    FErrorMsg := 'failed to create desktop shortcut';
    Log('  '+FErrorMsg);
    Exit;
  end;
  Log('Shortcut placed on the desktop.');
  Log('');
  // marker 'IMPORTANT' triggers main_form owner-draw: yellow background, bold black text
  Log('============================================================');
  Log('IMPORTANT: ALWAYS start Lazarus IDE from the desktop');
  Log('IMPORTANT: shortcut "'+Name+'".');
  Log('IMPORTANT: Running lazarus.exe directly skips the --pcp flag,');
  Log('IMPORTANT: spills config into %LOCALAPPDATA%\lazarus, and');
  Log('IMPORTANT: breaks the docked layout.');
  Log('============================================================');
end;

function TInstallThread.StepGenerateFpcCfg: Boolean;
begin
  Result := False;
  var FpcMkCfg := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc\bin\x86_64-win64\fpcmkcfg.exe';
  var CfgPath  := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc\bin\x86_64-win64\fpc.cfg';
  var BasePath := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc';

  // `make install` doesn't generate fpc.cfg (the Inno Setup installer runs fpcmkcfg as a [Run] step)
  // without fpc.cfg the compiler can't find unit paths beyond rtl - breaks any non-trivial build
  Log('Generating fpc.cfg');
  Progress(-1, 'Generating fpc.cfg');
  var ExitCode := RunSilent(FpcMkCfg, ['-d', 'basepath='+BasePath, '-o', CfgPath, '-s']);
  if ExitCode <> 0 then begin
    FErrorMsg := 'fpcmkcfg failed (exit='+IntToStr(ExitCode)+')';
    Log('  '+FErrorMsg);
    Exit;
  end;
  Log('fpc.cfg ready: '+CfgPath);
  Result := True;
end;

function TInstallThread.StepRemoveCrossWin32: Boolean;
begin
  Result := True;  // best-effort
  var FpcInstall := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc';
  var PpcrossBin := IncludeTrailingPathDelimiter(FpcInstall)+'bin\x86_64-win64\ppcross386.exe';
  var UnitsDir   := IncludeTrailingPathDelimiter(FpcInstall)+'units\i386-win32';

  Log('Removing cross compiler i386-win32');
  Progress(-1, 'Removing i386-win32');
  if FileExists(PpcrossBin) then begin
    Log('  '+PpcrossBin);
    DeleteFile(PpcrossBin);
  end;
  if DirectoryExists(UnitsDir) then begin
    Log('  '+UnitsDir);
    RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', UnitsDir]);
  end;
end;

procedure TInstallThread.StepM3Cleanup;
begin
  // crossinstall drops a 32-bit native bin tree; we keep only the cross in x86_64-win64\
  // (fpc322 bootstrap stays - lazarus build still needs make.exe + binutils from there)
  var P := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc\bin\i386-win32';
  if DirectoryExists(P) then begin
    Log('Removing '+P);
    Progress(-1, 'Cleanup: drop i386-win32 native bin');
    RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', P]);
  end;
end;

procedure TInstallThread.Execute;
var
  Manifest: TInstallManifest;
begin
  FSuccess := False;
  FErrorMsg := '';
  FLogStream := nil;
  try
    if not (FCfg.InstallFpc or FCfg.InstallLazarus) then begin
      Log('nothing to install');
      FSuccess := True;
      Exit;
    end;

    if not DirectoryExists(FCfg.TargetDir) then
      if not ForceDirectories(FCfg.TargetDir) then begin
        FErrorMsg := 'cannot create directory '+FCfg.TargetDir;
        Exit;
      end;

    // open installer.log AFTER target dir exists; fmCreate truncates each run so each install has its own log
    if FCfg.SaveLog then
    try
      var LogPath := ResolveLogPath;
      FLogStream := TFileStream.Create(LogPath, fmCreate);
      Log('installer.log: '+LogPath);
    except
      on E: Exception do begin
        FLogStream := nil;
        // surface but don't abort - logging is a nice-to-have
        FLogMsg := 'WARNING: could not open installer.log: '+E.Message;
        Synchronize(@SyncLog);
      end;
    end;

    // pipeline is idempotent: each step checks its end-state and skips if done; Reinstall just applies the delta
    var TargetPrefix    := IncludeTrailingPathDelimiter(FCfg.TargetDir);
    var hasFpcExe       := FileExists(TargetPrefix+'fpc\bin\x86_64-win64\fpc.exe');
    var hasLazExe       := FileExists(TargetPrefix+'lazarus\lazarus.exe');
    var hasCrossW32     := FileExists(TargetPrefix+'fpc\bin\x86_64-win64\ppcross386.exe');
    var hasCrossWasm    := FileExists(TargetPrefix+'fpc\bin\x86_64-win64\ppcrosswasm32.exe');
    // Linux crosses don't have a dedicated ppcross<arch> (ppcx64 / ppcross386 are multi-OS); detect by RTL units
    var hasCrossLinux64 := DirectoryExists(TargetPrefix+'fpc\units\x86_64-linux');
    var hasCrossLinux32 := DirectoryExists(TargetPrefix+'fpc\units\i386-linux');
    var hasBootstrap    := FileExists(IncludeTrailingPathDelimiter(BootstrapBinDir)+'ppc386.exe');
    Log(Format('current state: fpc=%s laz=%s cross386=%s wasm=%s linux64=%s linux32=%s bootstrap=%s',
      [BoolToStr(hasFpcExe, True), BoolToStr(hasLazExe, True), BoolToStr(hasCrossW32, True), BoolToStr(hasCrossWasm, True),
       BoolToStr(hasCrossLinux64, True), BoolToStr(hasCrossLinux32, True), BoolToStr(hasBootstrap, True)]));

    // fail upfront if linux32 was ticked without an existing ppcross386 and without win32 in the same run
    if FCfg.CrossLinux32 and (not hasCrossW32) and (not FCfg.CrossWin32) then begin
      FErrorMsg := 'i386-linux cross requires the i386-win32 cross compiler. Tick "i386-win32" in the cross list and run install again.';
      Log('ERROR: '+FErrorMsg);
      Exit;
    end;

    // compare manifest SHAs against UI selection; refresh just the affected component on mismatch
    Manifest := ReadManifest(FCfg.TargetDir);
    var wantFpcRefresh := False;
    var wantLazRefresh := False;
    if Manifest.Present then begin
      Log(Format('manifest: fpc=%s@%s laz=%s@%s', [Manifest.FpcBranch, Copy(Manifest.FpcSha, 1, 7), Manifest.LazBranch, Copy(Manifest.LazSha, 1, 7)]));
      if hasFpcExe and (FCfg.FpcSelectedSha <> '') and (LowerCase(FCfg.FpcSelectedSha) <> Manifest.FpcSha) then begin
        Log('FPC selection ('+Copy(FCfg.FpcSelectedSha, 1, 7)+') differs from installed ('+Copy(Manifest.FpcSha, 1, 7)+') -> wiping fpcsrc + fpc to force fresh build');
        wantFpcRefresh := True;
      end;
      if hasLazExe and (FCfg.LazSelectedSha <> '') and (LowerCase(FCfg.LazSelectedSha) <> Manifest.LazSha) then begin
        Log('Lazarus selection ('+Copy(FCfg.LazSelectedSha, 1, 7)+') differs from installed ('+Copy(Manifest.LazSha, 1, 7)+') -> wiping lazarus to force fresh build');
        wantLazRefresh := True;
      end;
    end;

    if wantFpcRefresh then begin
      Progress(-1, 'Cleaning previous FPC build');
      RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', TargetPrefix+'fpc']);
      RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', TargetPrefix+'fpcsrc']);
      RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', TargetPrefix+'cross']);
      hasFpcExe := False;
      hasCrossW32 := False;
      hasCrossWasm := False;
      hasCrossLinux64 := False;
      hasCrossLinux32 := False;
    end;
    if wantLazRefresh then begin
      Progress(-1, 'Cleaning previous Lazarus build');
      RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', TargetPrefix+'lazarus']);
      hasLazExe := False;
    end;

    // bootstrap is needed for any make-based step; only re-fetch if missing AND something below needs it
    SetStage(isBootstrap);
    if hasBootstrap then Log('bootstrap fpc322 already installed, skipping')
    else begin
      if (not hasFpcExe) or (FCfg.CrossWin32 and not hasCrossW32) or (FCfg.CrossWasm and not hasCrossWasm) or
         (FCfg.CrossLinux64 and not hasCrossLinux64) or (FCfg.CrossLinux32 and not hasCrossLinux32) then
        if not StepBootstrap then Exit;
    end;

    // FPC source + native build - skip if FPC binary already there; user must wipe <fpc> to force rebuild
    if hasFpcExe then Log('native FPC already built at <target>\fpc, skipping source + make all')
    else begin
      SetStage(isFpcSrc);
      if not StepDownloadFpcSource then Exit;
      if not StepBuildFpcNative then Exit;
    end;

    // fpc.cfg must exist before any cross step that wants to patch it (Linux cross appends a target section)
    if FileExists(TargetPrefix+'fpc\bin\x86_64-win64\fpc.cfg') then Log('fpc.cfg already present, skipping fpcmkcfg')
    else begin
      SetStage(isFpcCfg);
      if not StepGenerateFpcCfg then Exit;
    end;

    // cross i386-win32: smart add/remove based on checkbox + current state
    if FCfg.CrossWin32 and (not hasCrossW32) then begin
      SetStage(isFpcCross);
      if not StepBuildFpcCross then Exit;
      StepM3Cleanup;
    end else if (not FCfg.CrossWin32) and hasCrossW32 then begin
      if not StepRemoveCrossWin32 then Exit;
    end else if hasCrossW32 then Log('cross compiler i386-win32 already installed, leaving as is')
    else Log('skipping cross compiler i386-win32 (not selected)');

    // cross wasm32-wasip1: no external binutils/libc, just compiler + RTL units
    if FCfg.CrossWasm and (not hasCrossWasm) then begin
      SetStage(isFpcCrossWasm);
      if not StepBuildFpcCrossWasm then Exit;
    end else if (not FCfg.CrossWasm) and hasCrossWasm then begin
      if not StepRemoveCrossWasm then Exit;
    end else if hasCrossWasm then Log('cross compiler wasm32-wasip1 already installed, leaving as is')
    else Log('skipping cross compiler wasm32-wasip1 (not selected)');

    // cross x86_64-linux: zips + SHA + extract + staged crossinstall + fpc.cfg patch
    // already-installed branch re-runs the patcher so config tweaks in newer installer versions reach pre-existing installs
    if FCfg.CrossLinux64 and (not hasCrossLinux64) then begin
      SetStage(isFpcCrossLinux64);
      if not StepBuildFpcCrossLinux64 then Exit;
    end else if (not FCfg.CrossLinux64) and hasCrossLinux64 then begin
      if not StepRemoveCrossLinux64 then Exit;
    end else if hasCrossLinux64 then begin
      Log('cross compiler x86_64-linux already installed, refreshing fpc.cfg block');
      var BinDir := IncludeTrailingPathDelimiter(TargetPrefix)+'cross\x86_64-linux\bin';
      var LibDir := IncludeTrailingPathDelimiter(TargetPrefix)+'cross\x86_64-linux\lib';
      PatchFpcCfgCrossSection('linux', 'x86_64', BinDir, LibDir, 'x86_64-linux-gnu-', True);
    end else Log('skipping cross compiler x86_64-linux (not selected)');

    // cross i386-linux: requires ppcross386 from the i386-win32 step
    if FCfg.CrossLinux32 and (not hasCrossLinux32) then begin
      SetStage(isFpcCrossLinux32);
      if not StepBuildFpcCrossLinux32 then Exit;
    end else if (not FCfg.CrossLinux32) and hasCrossLinux32 then begin
      if not StepRemoveCrossLinux32 then Exit;
    end else if hasCrossLinux32 then begin
      Log('cross compiler i386-linux already installed, refreshing fpc.cfg block');
      var BinDir := IncludeTrailingPathDelimiter(TargetPrefix)+'cross\i386-linux\bin';
      var LibDir := IncludeTrailingPathDelimiter(TargetPrefix)+'cross\i386-linux\lib';
      PatchFpcCfgCrossSection('linux', 'i386', BinDir, LibDir, 'i386-linux-gnu-', True);
    end else Log('skipping cross compiler i386-linux (not selected)');

    if FCfg.InstallLazarus and (not hasLazExe) then begin
      SetStage(isLazSrc);
      if not StepDownloadLazarusSource then Exit;
      if not StepBuildLazarus then Exit;
      SetStage(isLazConfig);
      if not StepGenerateLazarusConfig then Exit;
      SetStage(isShortcut);
      if not StepCreateDesktopShortcut then Exit;
    end else if hasLazExe and FCfg.InstallLazarus then begin
      // already built; if addon selection changed vs manifest, do the small "add packages + rebuild IDE" path
      var addonsChanged := (FCfg.InstallMinimap <> Manifest.InstallMinimap);
      if addonsChanged then begin
        Log('lazarus already built but addon selection changed -- rebuilding IDE');
        if not StepRebuildLazarusForAddons then Exit;
      end else
        Log('lazarus already built at <target>\lazarus, no addon delta, skipping');
    end else
      Log('skipping Lazarus IDE (not selected)');

    // record what's now on disk so a later run can compare
    Manifest.Present     := True;
    Manifest.FpcBranch   := FCfg.FpcBranch;
    Manifest.FpcSha      := FCfg.FpcSelectedSha;
    Manifest.LazBranch   := FCfg.LazBranch;
    Manifest.LazSha      := FCfg.LazSelectedSha;
    // CrossWin64 only meaningful when host = linux64; on win64 host we just record user intent
    Manifest.CrossWin64   := FCfg.CrossWin64;
    Manifest.CrossWin32   := FileExists(TargetPrefix+'fpc\bin\x86_64-win64\ppcross386.exe');
    Manifest.CrossLinux64 := DirectoryExists(TargetPrefix+'fpc\units\x86_64-linux');
    Manifest.CrossLinux32 := DirectoryExists(TargetPrefix+'fpc\units\i386-linux');
    Manifest.CrossWasm    := FileExists(TargetPrefix+'fpc\bin\x86_64-win64\ppcrosswasm32.exe');
    Manifest.InstallMinimap := FCfg.InstallMinimap;
    Manifest.LaunchAfter := FCfg.LaunchAfter;
    Manifest.InstalledAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
    if WriteManifest(FCfg.TargetDir, Manifest) then Log('Manifest written: '+ManifestPathFor(FCfg.TargetDir))
    else Log('WARNING: could not write manifest at '+ManifestPathFor(FCfg.TargetDir));

    SetStage(isDone);
    Log('--- pipeline done ---');
    Progress(100, 'complete');
    FSuccess := True;
  except
    on E: Exception do FErrorMsg := E.ClassName+': '+E.Message;
  end;
  // flush + release installer.log regardless of success
  if FLogStream <> nil then begin
    FLogStream.Free;
    FLogStream := nil;
  end;
end;

end.
