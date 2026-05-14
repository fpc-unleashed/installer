{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit install_pipeline;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

type
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
    CrossWin32:     Boolean;
    CrossLinux64:   Boolean;
    CrossLinux32:   Boolean;
    // SHA we resolved at the UI layer (head of chosen branch or
    // user-provided hash). pipeline writes this into the manifest at
    // end of install so a later run can decide whether to refresh.
    FpcSelectedSha: string;
    LazSelectedSha: string;
    // when True, pipeline appends every Log() line to
    // <TargetDir>\installer.log (truncated at start of each run).
    SaveLog: Boolean;
  end;

  TInstallLogEvent      = procedure(const msg: string) of object;
  TInstallProgressEvent = procedure(Percent: Integer; const status: string) of object;

  // ordered pipeline stages; each gets a slice of 0..100 via STAGE_END; build steps dominate
  TInstallStage = (
    isInit,
    isBootstrap,        //  0..8    download + extract bootstrap zip
    isFpcSrc,           //  8..14   download + extract fpc source
    isFpcMakeAll,       // 14..40   make all (~5-10 min)
    isFpcMakeUtils,     // 40..44   make utils
    isFpcMakeInstall,   // 44..48   make install
    isFpcCross,         // 48..62   make crossinstall (~3-5 min)
    isFpcCfg,           // 62..63   fpcmkcfg
    isLazSrc,           // 63..66   download + extract lazarus
    isLazPatch,         // 66..67   patch ide\lazarus.pp
    isLazMakelazbuild,  // 67..74   make lazbuild prereqs
    isLazPackages,      // 74..80   N x lazbuild --add-package
    isLazIde,           // 80..97   lazbuild --build-ide
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
    // optional installer.log writer; nil when save-log off; owned + freed inside Execute
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
    procedure StepM3Cleanup;
    function StepGenerateFpcCfg: Boolean;
    function StepDownloadLazarusSource: Boolean;
    function StepPatchLazarusSource: Boolean;
    function StepBuildLazarus: Boolean;
    function StepGenerateLazarusConfig: Boolean;
    function StepCreateDesktopShortcut: Boolean;
    function ResolveLazarusRef: string;
    function LazarusDir: string;
    function LazarusPcp: string;
    function ShortcutLabel: string;
    function RunLazbuild(const Args: array of string; const StepLabel: string): Boolean;
    function AddPackage(const LpkRel: string; LinkOnly: Boolean = False): Boolean;
    function WriteConfigFile(const FilePath, Content: string): Boolean;
    function ResolveFpcRef: string;
    function MakeWorkDir: string;
    function BootstrapBinDir: string;
    function RunMake(const Args: array of string; const StepLabel: string): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const Cfg: TInstallConfig;
      ALog: TInstallLogEvent; AProgress: TInstallProgressEvent; AOnTerminate: TNotifyEvent);
    property Success: Boolean read FSuccess;
    property ErrorMsg: string read FErrorMsg;
  end;

const
  // portable extract of fpc-3.2.2.i386-win32.exe, no registry/PATH/shortcut side effects
  BOOTSTRAP_URL = 'https://github.com/fpc-unleashed/freepascal/releases/download/bootstrappers-v1/fpc-3.2.2-i386-win32-portable.zip';
  BOOTSTRAP_SHA = '0DFB6E34EC1FB1E89B5EAEA90E3A514B1F37867AE91989FA18143750EB39BF30';

  // codeload accepts branch name, tag, full or short SHA in <ref>
  FPC_SOURCE_URL_PREFIX     = 'https://codeload.github.com/fpc-unleashed/freepascal/zip/';
  LAZARUS_SOURCE_URL_PREFIX = 'https://codeload.github.com/fpc-unleashed/lazarus/zip/';

implementation

uses
  download_util, hash_util, zip_util, proc_util, shortcut_util,
  install_manifest;

const
  // upper bound (on 0..100) of each stage's slice; isInit implicit 0, rest are caps
  STAGE_END: array[TInstallStage] of Byte = (
    0,    // isInit
    8,    // isBootstrap
    14,   // isFpcSrc
    40,   // isFpcMakeAll
    44,   // isFpcMakeUtils
    48,   // isFpcMakeInstall
    62,   // isFpcCross
    63,   // isFpcCfg
    66,   // isLazSrc
    67,   // isLazPatch
    74,   // isLazMakelazbuild
    80,   // isLazPackages
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
    'building i386 cross compiler',
    'fpc.cfg',
    'lazarus source',
    'patching lazarus.pp',
    'building lazbuild + LCL',
    'registering Lazarus packages',
    'building Lazarus IDE',
    'writing IDE config',
    'desktop shortcut',
    'done');

const
  // baked Lazarus environmentoptions.xml. Version 112 matches current main of fpc-unleashed/lazarus.
  // ActiveDesktop="default docked" -> single-window dock layout via anchordockingdsgn.
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
    // named Desktop1 + Desktop2 to activate; DockMaster ties Desktop2 to anchordocking
    '  <Desktops Count="2" ActiveDesktop="default docked">'#13#10 +
    '    <Desktop1 Name="default"/>'#13#10 +
    '    <Desktop2 Name="default docked" DockMaster="TIDEAnchorDockMaster"/>'#13#10 +
    '  </Desktops>'#13#10 +
    '</CONFIG>'#13#10;

  // pre-ack "Enable anchor docking?" prompt; without this the IDE shows a blocking dialog on first run
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

  // FpDebug: modern internal backend, no external gdb.exe required.
  // without this file the IDE pops the "Configure Lazarus IDE" wizard on first launch.
  // UID is a fixed GUID matching the reference install.
  DEBUGGER_OPTIONS: string =
    '<?xml version="1.0" encoding="UTF-8"?>'#13#10 +
    '<CONFIG>'#13#10 +
    '  <Debugger Version="1">'#13#10 +
    '    <Backends Version="1">'#13#10 +
    '      <Config ConfigName="FpDebug" ConfigClass="TFpDebugDebugger" Active="True" UID="{65D78958-7ADA-40EE-B528-5FFCB08E4544}"/>'#13#10 +
    '    </Backends>'#13#10 +
    '  </Debugger>'#13#10 +
    '</CONFIG>'#13#10;

constructor TInstallThread.Create(const Cfg: TInstallConfig;
  ALog: TInstallLogEvent; AProgress: TInstallProgressEvent; AOnTerminate: TNotifyEvent);
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

// Percent is LOCAL pct of current stage (0..100), or -1 for marquee; remap via STAGE_END for monotonic overall bar
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

// installer.log alongside installer.ini in the install dir; truncated each run (fmCreate in Execute)
function TInstallThread.ResolveLogPath: string;
begin
  Result := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'installer.log';
end;

// pull "[ NN%]" out of a lazbuild --build-ide line; False when no usable percent found
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
  // drop Hint/Note diagnostics; Warning and above still come through, plus Compiling/Linking/make[n]
  if Pos('Hint:', Line) > 0 then Exit;
  if Pos('Note:', Line) > 0 then Exit;
  Log(Line);
  // lazbuild --build-ide emits "[ NN%] ..." per package; feed into current stage's progress slice
  var Pct: Integer;
  if ExtractLazbuildPercent(Line, Pct) then Progress(Pct, Trim(Copy(Line, Pos('%]', Line)+2, MaxInt)));
end;

function TInstallThread.ResolveFpcRef: string;
begin
  Result := if (not FCfg.FpcLatest) and (FCfg.FpcHash <> '') then FCfg.FpcHash else FCfg.FpcBranch;
end;

function TInstallThread.MakeWorkDir: string;
begin
  // FPC source tree at <install>\fpcsrc - sibling of fpc/ and lazarus/; make + IDE config both point here
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

// codeload extract leaves a single top-level dir like "freepascal-abc123..."; find it in ParentDir, '' if not exactly one
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
      if Count = 1 then Result := SR.Name
      else Result := '';  // more than one - bail
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
  // hidden temp parent so FindOnlyTopDir ignores existing siblings (fpc, fpc322, lazarus, ...)
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

// run "<bootstrap>\make.exe" with args from the source dir; PATH gets bootstrap bin prepended for binutils (as/ld/ar)
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
  var PpBootstrap      := IncludeTrailingPathDelimiter(BootstrapBinDir)+'ppc386.exe';
  var WorkDir          := MakeWorkDir;
  var PpSelf           := IncludeTrailingPathDelimiter(WorkDir)+'compiler\ppcx64.exe';
  var FpcInstallPrefix := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc';

  Log('--- Building native FPC x86_64-win64 ---');
  Log('  source dir:      '+WorkDir);
  Log('  bootstrap PP:    '+PpBootstrap);
  Log('  install prefix:  '+FpcInstallPrefix);

  // distclean is brief; bundle under "make all" stage start
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
  // OPT=-dFPC_SOFT_FPUX80 keeps cross RTL on soft 80-bit floats (matches windows.yml CI)
  if not RunMake(['crossinstall', 'OS_TARGET=win32', 'CPU_TARGET=i386', 'INSTALL_PREFIX='+FpcInstallPrefix, 'PP='+PpSelf, 'OPT=-dFPC_SOFT_FPUX80'],
    'make crossinstall (i386-win32, ~5 min)') then Exit;

  Log('--- Cross-compiler ready: '+FpcInstallPrefix+'\bin\x86_64-win64\ppcross386.exe ---');
  Result := True;
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
  // hidden temp parent so FindOnlyTopDir ignores siblings (fpc, fpc322, src, ...)
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
  // packages installed into the IDE statically; base first for cleaner lazbuild dep resolution; paths relative to <lazarus>\
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

  // anchordocking added as link only; the dsgn package pulls it for IDE static linkage
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

  // every lazbuild invocation gets identical boilerplate so packages + IDE agree on pcp/cpu/os/lazarusdir
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

  // native fpc.exe before bootstrap so lazbuild's PATH-based detection picks the x86_64 wrapper; bootstrap stays for make + binutils
  var PathPrefix := FpcBinDir+';'+BootstrapBinDir;

  Log('--- Building Lazarus IDE ---');
  Log('  source dir: '+LazarusDir);
  Log('  PP:         '+FpcExe);

  // 1. build lazbuild + LCL + prereqs that --add-package calls below will compile against
  SetStage(isLazMakelazbuild);
  Progress(-1, 'make lazbuild (LCL + lazbuild, ~3 min)');
  var ExitCode := RunStream(MakeExe, ['lazbuild', 'PP='+FpcExe], LazarusDir, PathPrefix, @OnMakeLine);
  if ExitCode <> 0 then begin
    FErrorMsg := 'lazbuild bootstrap failed (make exit='+IntToStr(ExitCode)+')';
    Log('  '+FErrorMsg);
    Exit;
  end;

  // 2. register every package with our isolated config_lazarus; lazbuild appends to staticpackages.inc + idemake.cfg
  SetStage(isLazPackages);
  Log('Registering base packages ('+IntToStr(Length(LAZ_BASE_PACKAGES))+')');
  for var i := Low(LAZ_BASE_PACKAGES) to High(LAZ_BASE_PACKAGES) do begin
    if not AddPackage(LAZ_BASE_PACKAGES[i]) then Exit;
    // smooth-fill the package-registration slice as each lpk lands
    Progress(Round((i+1)*100 / (Length(LAZ_BASE_PACKAGES)+Length(LAZ_DOCKED_PACKAGES)+Length(LAZ_UNLEASHED_PACKAGES)+1)), ExtractFileName(LAZ_BASE_PACKAGES[i]));
  end;

  Log('Registering docked-IDE packages');
  // anchordocking is runtime; IDE statically links *dsgn which depends on it.
  // add runtime as link only -> in package list but not in staticpackages.inc.
  if not AddPackage(LAZ_DOCKED_LINK_ONLY, True) then Exit;
  for var i := Low(LAZ_DOCKED_PACKAGES) to High(LAZ_DOCKED_PACKAGES) do
    if not AddPackage(LAZ_DOCKED_PACKAGES[i]) then Exit;

  Log('Registering fpc-unleashed packages');
  for var i := Low(LAZ_UNLEASHED_PACKAGES) to High(LAZ_UNLEASHED_PACKAGES) do
    if not AddPackage(LAZ_UNLEASHED_PACKAGES[i]) then Exit;

  // 3. final IDE build linking from staticpackages.inc.
  // -dKeepInstalledPackages preserves the list across rebuilds; -dAddStaticPkgs activates the {$IFDEF} in lazarus.pp.
  // lazbuild emits "[ NN%]" lines that OnMakeLine feeds back into progress.
  SetStage(isLazIde);
  if not RunLazbuild(['--build-ide=-dKeepInstalledPackages -dAddStaticPkgs'], 'lazbuild --build-ide (~5 min)') then Exit;

  Log('--- Lazarus ready: '+LazarusDir+'\lazarus.exe ---');
  Result := True;
end;

function TInstallThread.StepPatchLazarusSource: Boolean;
begin
  // no-op; the explicit "uses lazminimap" in ide\lazarus.pp is what actually links it - leave source untouched
  Log('Lazarus source patch step is currently a no-op.');
  Result := True;
end;

// write Content to FilePath, return false on error and stash the message
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
  Xml := StringReplace(Xml, '%LAZ%',      LazarusDir, [rfReplaceAll]);
  Xml := StringReplace(Xml, '%FPC%',      IncludeTrailingPathDelimiter(FCfg.TargetDir)+'fpc\bin\x86_64-win64\fpc.exe', [rfReplaceAll]);
  Xml := StringReplace(Xml, '%FPCSRC%',   MakeWorkDir, [rfReplaceAll]);
  Xml := StringReplace(Xml, '%MAKE%',     IncludeTrailingPathDelimiter(BootstrapBinDir)+'make.exe', [rfReplaceAll]);
  Xml := StringReplace(Xml, '%PROJECTS%', ProjectsDir, [rfReplaceAll]);

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
  // --pcp loads our isolated config_lazarus instead of default %LOCALAPPDATA%\lazarus
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
  // 'IMPORTANT' marker is picked up by main_form's owner-draw (yellow bg + bold black)
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

  // make install does not generate fpc.cfg (Inno Setup installer does it as [Run] post-install).
  // without fpc.cfg the compiler can't find unit search paths beyond rtl -> e.g. lazarus "Can't find unit db".
  // template uses %basepath% to resolve -Fu/-Fl/-FD paths.
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
  // crossinstall drops a 32-bit native bin tree next to the cross bits; we only want the cross compiler
  // in x86_64-win64\, so ditch the 32-bit native bin. fpc322 bootstrap stays (lazarus needs make + binutils).
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

    // open installer.log AFTER target dir exists; fmCreate truncates each run for a clean per-install log
    if FCfg.SaveLog then
    try
      var LogPath := ResolveLogPath;
      FLogStream := TFileStream.Create(LogPath, fmCreate);
      Log('installer.log: '+LogPath);
    except
      on E: Exception do begin
        FLogStream := nil;
        // surface, but don't abort - logging is a nice-to-have
        FLogMsg := 'WARNING: could not open installer.log: '+E.Message;
        Synchronize(@SyncLog);
      end;
    end;

    // pipeline is idempotent: each step checks end-state and skips if done; SHA mismatch refreshes just that component
    var TargetPrefix := IncludeTrailingPathDelimiter(FCfg.TargetDir);
    var hasFpcExe    := FileExists(TargetPrefix+'fpc\bin\x86_64-win64\fpc.exe');
    var hasLazExe    := FileExists(TargetPrefix+'lazarus\lazarus.exe');
    var hasCrossW32  := FileExists(TargetPrefix+'fpc\bin\x86_64-win64\ppcross386.exe');
    var hasBootstrap := FileExists(IncludeTrailingPathDelimiter(BootstrapBinDir)+'ppc386.exe');
    Log(Format('current state: fpc=%s laz=%s cross386=%s bootstrap=%s',
      [BoolToStr(hasFpcExe, True), BoolToStr(hasLazExe, True), BoolToStr(hasCrossW32, True), BoolToStr(hasBootstrap, True)]));

    // compare manifest SHAs against UI selection; mismatch -> force refresh of that component
    Manifest := ReadManifest(FCfg.TargetDir);
    var wantFpcRefresh := False;
    var wantLazRefresh := False;
    if Manifest.Present then begin
      Log(Format('manifest: fpc=%s@%s laz=%s@%s',
        [Manifest.FpcBranch, Copy(Manifest.FpcSha, 1, 7), Manifest.LazBranch, Copy(Manifest.LazSha, 1, 7)]));
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
      hasFpcExe := False;
      hasCrossW32 := False;
    end;
    if wantLazRefresh then begin
      Progress(-1, 'Cleaning previous Lazarus build');
      RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', TargetPrefix+'lazarus']);
      hasLazExe := False;
    end;

    // bootstrap is needed for any make-based step; only re-fetch if missing
    SetStage(isBootstrap);
    if hasBootstrap then Log('bootstrap fpc322 already installed, skipping')
    else begin
      // bootstrap only runs if we'll need it (FPC build or cross compiler add)
      if (not hasFpcExe) or (FCfg.CrossWin32 and not hasCrossW32) then
        if not StepBootstrap then Exit;
    end;

    // FPC source + native build - skip if binary already there; user must wipe <fpc> to force a rebuild
    if hasFpcExe then Log('native FPC already built at <target>\fpc, skipping source + make all')
    else begin
      SetStage(isFpcSrc);
      if not StepDownloadFpcSource then Exit;
      if not StepBuildFpcNative then Exit;
    end;

    // cross i386-win32: add/remove based on checkbox + current state
    if FCfg.CrossWin32 and (not hasCrossW32) then begin
      SetStage(isFpcCross);
      if not StepBuildFpcCross then Exit;
      StepM3Cleanup;
    end else if (not FCfg.CrossWin32) and hasCrossW32 then begin
      if not StepRemoveCrossWin32 then Exit;
    end else if hasCrossW32 then Log('cross compiler i386-win32 already installed, leaving as is')
    else Log('skipping cross compiler i386-win32 (not selected)');

    // fpc.cfg
    if FileExists(TargetPrefix+'fpc\bin\x86_64-win64\fpc.cfg') then Log('fpc.cfg already present, skipping fpcmkcfg')
    else begin
      SetStage(isFpcCfg);
      if not StepGenerateFpcCfg then Exit;
    end;

    if FCfg.InstallLazarus and (not hasLazExe) then begin
      SetStage(isLazSrc);
      if not StepDownloadLazarusSource then Exit;
      SetStage(isLazPatch);
      if not StepPatchLazarusSource then Exit;
      if not StepBuildLazarus then Exit;
      SetStage(isLazConfig);
      if not StepGenerateLazarusConfig then Exit;
      SetStage(isShortcut);
      if not StepCreateDesktopShortcut then Exit;
    end else if hasLazExe then Log('lazarus already built at <target>\lazarus, skipping')
    else Log('skipping Lazarus IDE (not selected)');

    // record what's now on disk so a later run can compare
    Manifest.Present     := True;
    Manifest.FpcBranch   := FCfg.FpcBranch;
    Manifest.FpcSha      := FCfg.FpcSelectedSha;
    Manifest.LazBranch   := FCfg.LazBranch;
    Manifest.LazSha      := FCfg.LazSelectedSha;
    Manifest.CrossWin32  := FileExists(TargetPrefix+'fpc\bin\x86_64-win64\ppcross386.exe');
    Manifest.CrossLinux64 := False;
    Manifest.CrossLinux32 := False;
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
  // make sure installer.log gets flushed + released regardless of success
  if FLogStream <> nil then begin
    FLogStream.Free;
    FLogStream := nil;
  end;
end;

end.
