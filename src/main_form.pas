{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit main_form;

{$mode unleashed}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Dialogs, Graphics, LCLType, LCLIntf, LResources, Menus, Clipbrd, RegExpr, fileinfo,
  {$ifdef MSWINDOWS} Windows, ShellApi, {$endif}
  {$ifdef LINUX} process, {$endif}
  branch_fetch, branch_cache, install_pipeline, install_manifest, hash_branch, about_form;

const
  GH_OWNER     = 'fpc-unleashed';
  REPO_FPC     = 'freepascal';
  REPO_LAZARUS = 'lazarus';

type
  TMainForm = class(TForm)
    bevel1: tbevel;
    bevel2: tbevel;
    bevel3: tbevel;
    button1: tbutton;
    CheckBoxCPUView: tcheckbox;
    checkboxcrosslinux32: tcheckbox;
    checkboxcrosslinux64: tcheckbox;
    checkboxcrosswasm: tcheckbox;
    checkboxcrosswin32: tcheckbox;
    checkboxcrosswin64: tcheckbox;
    checkboxminimap: tcheckbox;
    checkboxtoggleaffinity: tcheckbox;
    CheckBoxMetaDarkStyle: TCheckBox;
    GroupBoxTarget: TGroupBox;
    GroupBoxUnleashed: TGroupBox;
    CheckBoxInstallUnleashed: TCheckBox;
    imagelogo: timage;
    labellazarusaddons: tlabel;
    LabelLinkCPUView: TLabel;
    LabelLinkMetaDarkStyle: TLabel;
    labellazarushash1: tlabel;
    LabelUnleashedBranch: TLabel;
    ComboBoxUnleashedBranch: TComboBox;
    LabelUnleashedHash: TLabel;
    EditUnleashedHash: TEdit;
    CheckBoxUnleashedLatest: TCheckBox;
    GroupBoxLazarus: TGroupBox;
    CheckBoxInstallLazarus: TCheckBox;
    CheckBoxLaunchAfter: TCheckBox;
    ComboBoxLazarusBranch: TComboBox;
    LabelLazarusHash: TLabel;
    EditLazarusHash: TEdit;
    CheckBoxLazarusLatest: TCheckBox;
    LabelCross: TLabel;
    MainMenu1: TMainMenu;
    MenuFile: TMenuItem;
    MenuFileExit: TMenuItem;
    MenuRepo: TMenuItem;
    MenuRepoMain: TMenuItem;
    MenuRepoFreepascal: TMenuItem;
    MenuRepoLazarus: TMenuItem;
    MenuRepoInstaller: TMenuItem;
    MenuHelp: TMenuItem;
    MenuHelpDocs: TMenuItem;
    MenuHelpAbout: TMenuItem;
    panel1: tpanel;
    panel10: tpanel;
    panel11: tpanel;
    panel12: tpanel;
    panel13: tpanel;
    panel14: tpanel;
    panel15: tpanel;
    panel16: tpanel;
    panel17: tpanel;
    panel2: tpanel;
    panel3: tpanel;
    panel4: tpanel;
    panel5: tpanel;
    panel6: tpanel;
    panel7: tpanel;
    panel8: tpanel;
    panel9: tpanel;
    PanelTargetContent: TPanel;
    PanelTargetEdit: TPanel;
    EditTargetDir: TEdit;
    ButtonBrowse: TButton;
    LabelMode: TLabel;
    PanelUnleashedBody: TPanel;
    PanelLazarusBody: TPanel;
    SelectDirDialog: TSelectDirectoryDialog;
    ProgressBar: TProgressBar;
    CheckBoxSaveLog: TCheckBox;
    ButtonInstall: TButton;
    ButtonClose: TButton;
    ListBoxLog: TListBox;
    PopupMenuLog: TPopupMenu;
    MenuCopy: TMenuItem;
    StatusBar: TStatusBar;
    procedure button1click(sender: tobject);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure ButtonBrowseClick(Sender: TObject);
    procedure ButtonInstallClick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
    procedure EditTargetDirChange(Sender: TObject);
    procedure CheckBoxInstallUnleashedChange(Sender: TObject);
    procedure CheckBoxInstallLazarusChange(Sender: TObject);
    procedure CheckBoxUnleashedLatestChange(Sender: TObject);
    procedure CheckBoxLazarusLatestChange(Sender: TObject);
    procedure OnAddonOrCrossChange(Sender: TObject);
    procedure LabelLinkCPUViewClick(Sender: TObject);
    procedure LabelLinkMetaDarkStyleClick(Sender: TObject);
    procedure OnSelectionChange(Sender: TObject);
    procedure ListBoxLogDrawItem(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
    procedure ListBoxLogKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure MenuCopyClick(Sender: TObject);
    procedure MenuFileExitClick(Sender: TObject);
    procedure MenuRepoMainClick(Sender: TObject);
    procedure MenuRepoFreepascalClick(Sender: TObject);
    procedure MenuRepoLazarusClick(Sender: TObject);
    procedure MenuRepoInstallerClick(Sender: TObject);
    procedure MenuHelpDocsClick(Sender: TObject);
    procedure MenuHelpAboutClick(Sender: TObject);
  protected
    {$ifdef MSWINDOWS}
    procedure CreateParams(var Params: TCreateParams); override;
    procedure WMEnterSizeMove(var Msg: TMessage); message WM_ENTERSIZEMOVE;
    procedure WMExitSizeMove(var Msg: TMessage); message WM_EXITSIZEMOVE;
    procedure WMNCPaint(var Msg: TMessage); message WM_NCPAINT;
    {$endif}
  private
    {$ifdef MSWINDOWS}
    FInSizeMove: Boolean;
    {$endif}
    FFetchPending: Integer;
    FUnleashedReady, FLazarusReady: Boolean;
    FShowFired: Boolean;
    FShuttingDown: Boolean;
    FInstalling: Boolean;
    // snapshot of cfg.InstallLazarus from current install run; combined with
    // live CheckBoxLaunchAfter.Checked at OnInstallComplete to decide launch
    FInstalledLazarus: Boolean;
    FInstallTargetDir: string;
    // last target dir for which cross checkboxes were synced; prevents RefreshTargetState clobbering toggles
    FCrossSyncedFor: string;
    // gate for state-B reset so a re-entry from a checkbox toggle won't clobber the just-made change
    FLastState: Char;
    FLastStateDir: string;
    // raw 'name=sha' lists from branch_fetch; Values[branch] yields head SHA
    FFpcBranchShas: TStringList;
    FLazBranchShas: TStringList;
    // pin hints from filename; one of *Name (predefined) / *HashHex (murmur3 prefix) per repo. Resolved in FillCombo
    FPinnedFpcBranchName: string;
    FPinnedFpcBranchHex:  string;
    FPinnedLazBranchName: string;
    FPinnedLazBranchHex:  string;
    // cache file is rewritten only when BOTH fetches succeed; partial-success can't leave a stale "fresh" file
    FFpcFetchOk: Boolean;
    FLazFetchOk: Boolean;
    // True while target dir is unusable (blank or non-empty w/o installer.ini); gates ButtonInstall
    FFolderError: Boolean;
    // re-entrancy guard for RefreshTargetState; state-B reset writes to controls whose OnChange re-enters here
    FRefreshingTarget: Boolean;
    procedure CopySelectedLogLines;
    procedure SetDoubleBufferedRecursive(c: TWinControl);
    procedure LaunchInstalledIde;
    procedure RefreshTargetState;
    procedure ResetTargetControlsToDefaults;
    procedure ApplyHashesFromBinaryName;
    function ResolveSelectedFpcSha: string;
    function ResolveSelectedLazSha: string;
    procedure StartBranchFetch;
    procedure OnUnleashedDone(Sender: TObject);
    procedure OnLazarusDone(Sender: TObject);
    procedure FillCombo(Combo: TComboBox; const Repo: string; Branches: TStringList; const ErrorMsg: string);
    procedure FetchTick;
    procedure ApplyUnleashedEnabled;
    procedure ApplyLazarusEnabled;
    procedure SetInputsEnabled(act: Boolean);
    procedure OnInstallLog(const msg: string);
    procedure OnInstallProgress(Percent: Integer; const status: string);
    procedure OnInstallComplete(Sender: TObject);
    procedure SetStatus(const msg: string);
    procedure Log(const msg: string);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

const
  // mirror install_pipeline's per-OS host paths so RefreshTargetState/LaunchInstalledIde see the same files
{$ifdef MSWINDOWS}
  HostFpcWrapperSub  = 'fpc\bin\x86_64-win64\fpc.exe';
  LazarusBinarySub   = 'lazarus\lazarus.exe';
{$endif}
{$ifdef LINUX}
  HostFpcWrapperSub  = 'fpc/bin/fpc';
  LazarusBinarySub   = 'lazarus/lazarus';
{$endif}

// filesystem is authoritative for what's installed; manifest only records intent (crash leaves no manifest)
function IsDirEffectivelyEmpty(const Dir: string): Boolean;
var SR: TSearchRec;
begin
  Result := True;
  if FindFirst(IncludeTrailingPathDelimiter(Dir)+'*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') then begin
        Result := False;
        Exit;
      end;
    until FindNext(SR) <> 0;
  finally
    // SysUtils. qualifier needed -- Windows unit also exports FindClose(HANDLE) which shadows the TSearchRec one
    SysUtils.FindClose(SR);
  end;
end;

function ProbeCrossInstalled(const dir, target: string): Boolean;
begin
  Result := False;
  if dir = '' then Exit;
{$ifdef MSWINDOWS}
  Result := DirectoryExists(IncludeTrailingPathDelimiter(dir)+'fpc\units\'+target);
{$endif}
{$ifdef LINUX}
  var Base := IncludeTrailingPathDelimiter(dir)+'fpc/lib/fpc/';
  if not DirectoryExists(Base) then Exit;
  var SR: TSearchRec;
  if FindFirst(Base+'*', faDirectory, SR) = 0 then
  try
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') and ((SR.Attr and faDirectory) <> 0) and (Length(SR.Name) > 0) and (SR.Name[1] in ['0'..'9']) and DirectoryExists(Base+SR.Name+'/units/'+target) then begin
        Result := True;
        Exit;
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
{$endif}
end;

// {$I %DATE%}/%TIME% are frozen at build by the FPC preprocessor (not function calls)
const
  BUILD_DATE_RAW = {$I %DATE%};
  BUILD_TIME_RAW = {$I %TIME%};

function GetAppVersion: string;
begin
  Result := '';
  var Info := autofree TFileVersionInfo.Create(nil);
  try
    Info.ReadFileInfo;
    Result := Info.VersionStrings.Values['FileVersion'];
  except
    // resource missing or unreadable -> caller falls back to no version
  end;
end;

{$ifdef MSWINDOWS}
// WS_EX_COMPOSITED makes DWM composite form + ~50 child HWNDs atomically; without it restore/resize shows paint cascade
procedure TMainForm.CreateParams(var Params: TCreateParams);
const
  WS_EX_COMPOSITED = $02000000;
begin
  inherited CreateParams(Params);
  Params.ExStyle := Params.ExStyle or WS_EX_COMPOSITED;
end;

// menu bar is in NC area which WS_EX_COMPOSITED doesn't cover; suppress NC paint during drag, redraw once on exit
procedure TMainForm.WMEnterSizeMove(var Msg: TMessage);
begin
  FInSizeMove := True;
  inherited;
end;

procedure TMainForm.WMExitSizeMove(var Msg: TMessage);
begin
  FInSizeMove := False;
  inherited;
  RedrawWindow(Handle, nil, 0, RDW_FRAME or RDW_INVALIDATE);
end;

procedure TMainForm.WMNCPaint(var Msg: TMessage);
begin
  if not FInSizeMove then inherited;
end;
{$endif}

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FFpcBranchShas := TStringList.Create;
  FLazBranchShas := TStringList.Create;

  // Linux LCL gtk2/qt doesn't consume the PE icon group; load the embedded PNG resource at runtime instead
  {$ifdef LINUX}
  var IconStream := autofree TLazarusResourceStream.Create('installer', nil);
  var Png        := autofree TPortableNetworkGraphic.Create;
  Png.LoadFromStream(IconStream);
  Application.Icon.Assign(Png);
  Self.Icon.Assign(Png);
  {$endif}

  // augment LFM caption with version + build stamp
  var BuildDate := StringReplace(BUILD_DATE_RAW, '/', '-', [rfReplaceAll]);
  var BuildTime := Copy(BUILD_TIME_RAW, 1, 5);   // HH:MM, drop :SS
  var Ver := GetAppVersion;
  if Ver <> '' then Caption := Caption+' v'+Ver;
  Caption := Caption+' (built at '+BuildDate+' '+BuildTime+')';
  // cross checkbox defaults must be set BEFORE EditTargetDir.Text -- that fires RefreshTargetState which probes the FS
  // and sets FCrossSyncedFor. Overrides applied after that would win against the "nothing installed" probe
  {$ifdef LINUX}
  // host is x86_64-linux; native build covers it. cross-to-win64 starts off so we don't surprise user with downloads
  CheckBoxCrossLinux64.Enabled := False;
  CheckBoxCrossLinux64.Checked := False;
  CheckBoxCrossLinux64.Caption := 'x86_64-linux (native)';
  EditTargetDir.Text := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME'))+'fpcunleashed';
  // Toggle Display Affinity uses Set/GetWindowDisplayAffinity (user32). Package's Register is {$ifdef WINDOWS} so no-op on linux
  CheckBoxToggleAffinity.Enabled := False;
  CheckBoxToggleAffinity.Checked := False;
  {$else}
  // host is x86_64-win64; cross-to-linux64 starts off
  CheckBoxCrossWin64.Enabled := False;
  CheckBoxCrossWin64.Checked := False;
  CheckBoxCrossWin64.Caption := 'x86_64-win64 (native)';
  EditTargetDir.Text := 'C:\fpcunleashed';
  {$endif}
  // per-child DoubleBuffered; form-level only covers background, each child HWND otherwise paints direct to screen
  SetDoubleBufferedRecursive(Self);

  SetStatus('Ready');
  ApplyUnleashedEnabled;
  ApplyLazarusEnabled;
  RefreshTargetState;
  ApplyHashesFromBinaryName;

  // 80% of work area, re-centered vertically. LFM Position=poScreenCenter uses designer Height which cramps the log
  Self.Height := Screen.WorkAreaHeight*80 div 100;
  Self.Top := Screen.WorkAreaTop+(Screen.WorkAreaHeight-Self.Height) div 2;
end;

procedure tmainform.button1click(sender: tobject);
begin
  ListBoxLog.Clear;
end;

// pull pinned (fpc, laz) from ParamStr(1) or filename. Wire format: README.md "Filename hash pin" + hash_branch.pas
procedure TMainForm.ApplyHashesFromBinaryName;
const
  // legacy fallback only; new encoder produces single hex+digit run with no separators
  HASH_PATTERN = '(?<![0-9a-fA-F])([0-9a-fA-F]{7,12})[^0-9a-fA-F]+([0-9a-fA-F]{7,12})(?![0-9a-fA-F])';
begin
  var parsed: TParsedBinaryName;
  parsed.Present := False;

  // 1. cmdline override via ParamStr(1) -- whole arg as raw blob; falls back to filename if not a valid blob
  if (ParamCount >= 1) and (ParamStr(1) <> '') then begin
    if TryParseBlob(ParamStr(1), parsed) then Log('using cmdline pin: '+ParamStr(1))
    else Log('cmdline arg "'+ParamStr(1)+'" is not a pin blob; falling back to filename');
  end;

  // 2. filename (new length-prefixed format) -- LAST hex run >= 12
  if not parsed.Present then parsed := ParseBinaryName(ExtractFileName(ParamStr(0)));

  if parsed.Present then begin
    // empty FpcCommit/LazCommit = '0' length digit = "latest of selected branch" sentinel -> tick Latest, clear hash
    Log('binary name carries pinned commit hashes: fpc='+(if parsed.FpcCommit = '' then '(latest)' else parsed.FpcCommit)+' ide='+(if parsed.LazCommit = '' then '(latest)' else parsed.LazCommit));

    if parsed.FpcCommit = '' then begin
      EditUnleashedHash.Text          := '';
      CheckBoxUnleashedLatest.Checked := True;
    end else begin
      EditUnleashedHash.Text          := parsed.FpcCommit;
      CheckBoxUnleashedLatest.Checked := False;
    end;

    if parsed.LazCommit = '' then begin
      EditLazarusHash.Text          := '';
      CheckBoxLazarusLatest.Checked := True;
    end else begin
      EditLazarusHash.Text          := parsed.LazCommit;
      CheckBoxLazarusLatest.Checked := False;
    end;

    // stash branch hints for FillCombo. Hash override (pos 3/4) beats predefined/implicit-main (pos 1/2)
    if parsed.FpcBranchHashOverride <> '' then FPinnedFpcBranchHex := parsed.FpcBranchHashOverride
    else if parsed.FpcBranchFromCommit <> '' then FPinnedFpcBranchName := parsed.FpcBranchFromCommit;
    if parsed.LazBranchHashOverride <> '' then FPinnedLazBranchHex := parsed.LazBranchHashOverride
    else if parsed.LazBranchFromCommit <> '' then FPinnedLazBranchName := parsed.LazBranchFromCommit;

    // companion summary line; hash-overridden branches show the hex here, matching branch name lands later via FillCombo
    var fpcStr: string := if parsed.FpcBranchHashOverride <> '' then parsed.FpcBranchHashOverride else if parsed.FpcBranchFromCommit <> '' then parsed.FpcBranchFromCommit else '(default)';
    var lazStr: string := if parsed.LazBranchHashOverride <> '' then parsed.LazBranchHashOverride else if parsed.LazBranchFromCommit <> '' then parsed.LazBranchFromCommit else '(default)';
    Log('binary name carries pinned branch hashes: fpc='+fpcStr+' ide='+lazStr);

    RefreshTargetState;
    Exit;
  end;

  // 3. legacy two-hash regex fallback; only consulted when neither cmdline nor new-format filename matched
  var Name := ExtractFileName(ParamStr(0));
  var R := autofree TRegExpr.Create;
  R.Expression := HASH_PATTERN;
  if not R.Exec(Name) then Exit;

  var FpcHash := LowerCase(R.&Match[1]);
  var LazHash := LowerCase(R.&Match[2]);
  Log('binary name carries pinned commit hashes (legacy): fpc='+FpcHash+' ide='+LazHash);
  EditUnleashedHash.Text       := FpcHash;
  CheckBoxUnleashedLatest.Checked := False;
  EditLazarusHash.Text         := LazHash;
  CheckBoxLazarusLatest.Checked := False;
  // RefreshTargetState already ran w/ manifest-restored hashes; rerun so LabelMode reflects the new pin
  RefreshTargetState;
end;

procedure TMainForm.EditTargetDirChange(Sender: TObject);
begin
  RefreshTargetState;
end;

// folder is authoritative; installer.ini carries build SHA for update detection
//   A. blank path           -> error, Install disabled
//   B. dir absent or empty  -> defaults, "New installation"
//   C. dir has installer.ini -> restore from manifest
//   D. dir non-empty w/o ini -> error (someone else's folder)
procedure TMainForm.RefreshTargetState;
begin
  // re-entry guard: bound Edit/Combo writes fire OnSelectionChange -> back here
  if FRefreshingTarget then Exit;
  FRefreshingTarget := True;
  try
  var rawDir := Trim(EditTargetDir.Text);

  // optimistic reset; each branch re-sets the flag as needed
  FFolderError := False;
  LabelMode.Font.Color := clWindowText;

  // ---- state A: no path entered ----
  if rawDir = '' then begin
    FFolderError := True;
    LabelMode.Font.Color := clRed;
    LabelMode.Caption := 'No target directory selected';
    ButtonInstall.Enabled := False;
    FLastState := 'A';
    FLastStateDir := rawDir;
    Exit;
  end;

  var dir            := IncludeTrailingPathDelimiter(rawDir);
  var manifestExists := FileExists(dir+MANIFEST_FILE);
  var dirExists      := DirectoryExists(dir);

  // ---- state B: target absent or empty (no manifest) -> fresh install ----
  // reset only on entry into state-B so checkbox-toggle re-entry doesn't wipe the change
  if (not manifestExists) and ((not dirExists) or IsDirEffectivelyEmpty(dir)) then begin
    if (FLastState <> 'B') or (FLastStateDir <> rawDir) then ResetTargetControlsToDefaults;
    LabelMode.Caption := 'New installation';
    ButtonInstall.Caption := 'Install';
    if (FFetchPending = 0) and (not FInstalling) then ButtonInstall.Enabled := True;
    FLastState := 'B';
    FLastStateDir := rawDir;
    Exit;
  end;

  // ---- state D: dir has content but no manifest -> refuse ----
  // fresh install overwrites fpc/, lazarus/, ... -- a stray unrelated tree would get clobbered
  if not manifestExists then begin
    FFolderError := True;
    LabelMode.Font.Color := clRed;
    LabelMode.Caption := 'Target folder is not empty and is not an Unleashed install (installer.ini not found). Choose an empty directory or an existing Unleashed install location.';
    ButtonInstall.Enabled := False;
    FLastState := 'D';
    FLastStateDir := rawDir;
    Exit;
  end;

  // ---- state C: manifest present -> restore + update / reinstall ----
  var hasFpc := FileExists(dir+HostFpcWrapperSub);
  var hasLaz := FileExists(dir+LazarusBinarySub);

  var parts := '';
  if hasFpc then parts := 'fpc';
  if hasLaz then begin
    if parts <> '' then parts := parts+' + ';
    parts := parts+'lazarus';
  end;
  // list every selectable target, native first. listing native explicitly makes the summary match the cross checkbox set
  {$ifdef MSWINDOWS}
  var crossTargets: TStringArray := ['x86_64-win64', 'x86_64-linux', 'i386-win32', 'i386-linux', 'wasm32-wasip1'];
  {$endif}
  {$ifdef LINUX}
  var crossTargets: TStringArray := ['x86_64-linux', 'x86_64-win64', 'i386-win32', 'i386-linux', 'wasm32-wasip1'];
  {$endif}
  for var t in crossTargets do
    if ProbeCrossInstalled(rawDir, t) then begin
      if parts <> '' then parts := parts+' + ';
      parts := parts+t;
    end;

  // pull last-installed SHAs from manifest and compare to currently-selected to detect update.
  // user-typed short hash matches manifest's full SHA as prefix in either direction
  var m := ReadManifest(rawDir);
  var updates := '';
  // sync checkboxes once per target dir; gate on manifest-presence so partial install (manifest written, binary missing) still triggers restore
  if FCrossSyncedFor <> dir then begin
    FCrossSyncedFor := dir;
    // {Win64,Linux64} cross synced only on the host where they're not native (other host disables at FormCreate)
    if CheckBoxCrossWin64.Enabled   then CheckBoxCrossWin64.Checked   := ProbeCrossInstalled(rawDir, 'x86_64-win64');
    if CheckBoxCrossLinux64.Enabled then CheckBoxCrossLinux64.Checked := ProbeCrossInstalled(rawDir, 'x86_64-linux');
    CheckBoxCrossWin32.Checked   := ProbeCrossInstalled(rawDir, 'i386-win32');
    CheckBoxCrossLinux32.Checked := ProbeCrossInstalled(rawDir, 'i386-linux');
    CheckBoxCrossWasm.Checked    := ProbeCrossInstalled(rawDir, 'wasm32-wasip1');
    // restore non-FS-detectable selections (branch/hash/addons/launch-after) from manifest
    if m.Present then begin
      CheckBoxMinimap.Checked      := m.InstallMinimap;
      CheckBoxCPUView.Checked      := m.InstallCPUView;
      CheckBoxMetaDarkStyle.Checked := m.InstallMetaDarkStyle;
      // skip windows-only checkbox restore on linux (FormCreate locked Enabled=False)
      if CheckBoxToggleAffinity.Enabled then CheckBoxToggleAffinity.Checked := m.InstallToggleAffinity;
      CheckBoxLaunchAfter.Checked  := m.LaunchAfter;
      if m.FpcBranch <> '' then begin
        ComboBoxUnleashedBranch.Text := m.FpcBranch;
        // always show last installed SHA in the hash field (display-only while Latest=on); restore explicit Latest flag
        EditUnleashedHash.Text       := m.FpcSha;
        CheckBoxUnleashedLatest.Checked := m.FpcLatest;
      end;
      if m.LazBranch <> '' then begin
        ComboBoxLazarusBranch.Text   := m.LazBranch;
        EditLazarusHash.Text         := m.LazSha;
        CheckBoxLazarusLatest.Checked := m.LazLatest;
      end;
    end;
  end;
  if m.Present then begin

    var selFpc := ResolveSelectedFpcSha;
    var selLaz := ResolveSelectedLazSha;
    if hasFpc and (selFpc <> '') and (m.FpcSha <> '') and (Pos(selFpc, m.FpcSha) <> 1) and (Pos(m.FpcSha, selFpc) <> 1) then updates := updates+' fpc '+Copy(m.FpcSha, 1, 7)+' -> '+Copy(selFpc, 1, 7);
    if hasLaz and (selLaz <> '') and (m.LazSha <> '') and (Pos(selLaz, m.LazSha) <> 1) and (Pos(m.LazSha, selLaz) <> 1) then updates := updates+' lazarus '+Copy(m.LazSha, 1, 7)+' -> '+Copy(selLaz, 1, 7);
    // addon deltas. Pipeline's StepRebuildLazarusForAddons handles them without full reinstall, but labels need to reflect reality
    if hasLaz and (CheckBoxMinimap.Checked <> m.InstallMinimap) then updates := updates+(if CheckBoxMinimap.Checked then ' +minimap' else ' -minimap');
    if hasLaz and (CheckBoxCPUView.Checked <> m.InstallCPUView) then updates := updates+(if CheckBoxCPUView.Checked then ' +cpuview' else ' -cpuview');
    if hasLaz and (CheckBoxMetaDarkStyle.Checked <> m.InstallMetaDarkStyle) then updates := updates+(if CheckBoxMetaDarkStyle.Checked then ' +metadarkstyle' else ' -metadarkstyle');
    // skip toggle-affinity delta on linux (user can't change it)
    if hasLaz and CheckBoxToggleAffinity.Enabled and (CheckBoxToggleAffinity.Checked <> m.InstallToggleAffinity) then updates := updates+(if CheckBoxToggleAffinity.Checked then ' +toggle-affinity' else ' -toggle-affinity');
    if hasFpc and CheckBoxCrossWin64.Enabled and (CheckBoxCrossWin64.Checked <> m.CrossWin64) then updates := updates+(if CheckBoxCrossWin64.Checked then ' +x86_64-win64' else ' -x86_64-win64');
    if hasFpc and (CheckBoxCrossWin32.Checked <> m.CrossWin32) then updates := updates+(if CheckBoxCrossWin32.Checked then ' +i386-win32' else ' -i386-win32');
    if hasFpc and (CheckBoxCrossLinux64.Checked <> m.CrossLinux64) then updates := updates+(if CheckBoxCrossLinux64.Checked then ' +x86_64-linux' else ' -x86_64-linux');
    if hasFpc and (CheckBoxCrossLinux32.Checked <> m.CrossLinux32) then updates := updates+(if CheckBoxCrossLinux32.Checked then ' +i386-linux' else ' -i386-linux');
    if hasFpc and (CheckBoxCrossWasm.Checked <> m.CrossWasm) then updates := updates+(if CheckBoxCrossWasm.Checked then ' +wasm32-wasip1' else ' -wasm32-wasip1');
  end;

  if updates <> '' then begin
    LabelMode.Caption := 'Update available:'+updates;
    ButtonInstall.Caption := 'Update';
  end else if parts <> '' then begin
    LabelMode.Caption := 'Existing install detected ('+parts+') - Install will overwrite';
    ButtonInstall.Caption := 'Reinstall';
  end else begin
    // manifest present but no FPC/Lazarus binary -- prior install died after writing manifest. Treat as resumable
    LabelMode.Caption := 'Partial install detected (manifest only) - Install will resume';
    ButtonInstall.Caption := 'Resume';
  end;
  if (FFetchPending = 0) and (not FInstalling) then ButtonInstall.Enabled := True;
  FLastState := 'C';
  FLastStateDir := rawDir;
  finally
    FRefreshingTarget := False;
  end;
end;

procedure TMainForm.ResetTargetControlsToDefaults;
begin
  // cross checkboxes -- all unchecked; FormCreate handles host-native Enabled/Caption once at startup
  CheckBoxCrossWin64.Checked   := False;
  CheckBoxCrossLinux64.Checked := False;
  CheckBoxCrossWin32.Checked   := False;
  CheckBoxCrossLinux32.Checked := False;
  CheckBoxCrossWasm.Checked    := False;

  // addons -- match LFM first-time defaults: lightweight IDE extras on, theme + windows-only plugin off
  CheckBoxMinimap.Checked        := True;
  CheckBoxCPUView.Checked        := True;
  CheckBoxMetaDarkStyle.Checked  := False;
  // toggle-affinity .Enabled=False on linux; writing False here is a no-op visually and keeps the data model clean
  CheckBoxToggleAffinity.Checked := False;

  // master + latest + launch-after -- "fresh install" intent
  CheckBoxInstallUnleashed.Checked := True;
  CheckBoxInstallLazarus.Checked   := True;
  CheckBoxUnleashedLatest.Checked  := True;
  CheckBoxLazarusLatest.Checked    := True;
  CheckBoxLaunchAfter.Checked      := True;

  // hash fields are display-only while Latest=on; clear stale hex so the field is empty until user opts in
  EditUnleashedHash.Text := '';
  EditLazarusHash.Text   := '';

  // forget per-dir cross-sync cache so a transition into a manifest dir re-runs the FS + manifest restore
  FCrossSyncedFor := '';

  // sub-control enabling cascades from masters
  ApplyUnleashedEnabled;
  ApplyLazarusEnabled;
end;

function TMainForm.ResolveSelectedFpcSha: string;
begin
  // explicit hash wins; otherwise head SHA of currently-selected branch (as of last fetch)
  Result := if (not CheckBoxUnleashedLatest.Checked) and (Trim(EditUnleashedHash.Text) <> '') then LowerCase(Trim(EditUnleashedHash.Text))
            else if ComboBoxUnleashedBranch.Text <> '' then LowerCase(FFpcBranchShas.Values[ComboBoxUnleashedBranch.Text])
            else '';
end;

function TMainForm.ResolveSelectedLazSha: string;
begin
  Result := if (not CheckBoxLazarusLatest.Checked) and (Trim(EditLazarusHash.Text) <> '') then LowerCase(Trim(EditLazarusHash.Text))
            else if ComboBoxLazarusBranch.Text <> '' then LowerCase(FLazBranchShas.Values[ComboBoxLazarusBranch.Text])
            else '';
end;

procedure TMainForm.OnSelectionChange(Sender: TObject);
begin
  // wired to combo + hash edit OnChange; keeps LabelMode's '(update available)' hint live as user picks
  RefreshTargetState;
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  if FShowFired then Exit;
  FShowFired := True;
  StartBranchFetch;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  // worker threads have FreeOnTerminate=True; flag stops the callback from touching destroyed widgets
  FShuttingDown := True;
  FFpcBranchShas.Free;
  FLazBranchShas.Free;
end;

// while pipeline runs, install thread touches the target tree; prompt before hard exit
procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FInstalling then CanClose := MessageDlg('Installation in progress', 'An installation is currently running. Closing now will leave the target directory in a half-built state. Close anyway?', mtConfirmation, [mbYes, mbNo], 0) = mrYes;
end;

procedure TMainForm.StartBranchFetch;

  // convert bare-name list to 'name=sha' form FillCombo expects; only 'main' gets a SHA from cache
  procedure AppendWithMainSha(Src: TStrings; Dest: TStrings; const MainSha: string);
  begin
    Dest.Clear;
    for var i := 0 to Src.Count-1 do begin
      var name := Src[i];
      if SameText(name, 'main') then Dest.Add(name+'='+MainSha)
      else Dest.Add(name+'=');
    end;
  end;

begin
  SetStatus('Updating branches list...');
  FFetchPending := 2;
  FFpcFetchOk := False;
  FLazFetchOk := False;
  ButtonInstall.Enabled := False;

  // cache-first: skip GitHub fetch if cache file is younger than CACHE_TTL_MINUTES. saves anon API quota across launches
  var fpcNames := autofree TStringList.Create;
  var ideNames := autofree TStringList.Create;
  var age: Double;
  var fpcMainSha, ideMainSha: string;
  if LoadCache(fpcNames, ideNames, age, fpcMainSha, ideMainSha) and (age < CACHE_TTL_MINUTES*60) then begin
    Log('using cached branch lists ('+IntToStr(Round(age))+' sec(s) old, file="'+CacheFilePath+'")');
    var fpcCache := autofree TStringList.Create;
    var lazCache := autofree TStringList.Create;
    AppendWithMainSha(fpcNames, fpcCache, fpcMainSha);
    AppendWithMainSha(ideNames, lazCache, ideMainSha);
    FillCombo(ComboBoxUnleashedBranch, REPO_FPC, fpcCache, '');
    FUnleashedReady := True;
    ApplyUnleashedEnabled;
    FetchTick;
    FillCombo(ComboBoxLazarusBranch, REPO_LAZARUS, lazCache, '');
    FLazarusReady := True;
    ApplyLazarusEnabled;
    FetchTick;
    Exit;
  end;

  Log('Fetching branches from github.com/'+GH_OWNER+'/'+REPO_FPC+' and /'+REPO_LAZARUS);
  TBranchFetchThread.Create(GH_OWNER, REPO_FPC,     @OnUnleashedDone);
  TBranchFetchThread.Create(GH_OWNER, REPO_LAZARUS, @OnLazarusDone);
end;

// failed-fetch fallback: build 'name=sha' from bare names, attaching the cached HEAD SHA only to 'main'
procedure NamesToShaListWithMain(Src, Dest: TStringList; const MainSha: string);
begin
  Dest.Clear;
  for var i := 0 to Src.Count-1 do
    if SameText(Src[i], 'main') then Dest.Add(Src[i]+'='+MainSha)
    else Dest.Add(Src[i]+'=');
end;

procedure TMainForm.OnUnleashedDone(Sender: TObject);
begin
  if FShuttingDown then Exit;
  var T := TBranchFetchThread(Sender);
  if T.ErrorMsg <> '' then begin
    var fpcNames := autofree TStringList.Create;
    var ideNames := autofree TStringList.Create;
    var age: Double;
    var fpcMainSha, ideMainSha: string;
    if LoadCache(fpcNames, ideNames, age, fpcMainSha, ideMainSha) and (fpcNames.Count > 0) then begin
      var fallback := autofree TStringList.Create;
      NamesToShaListWithMain(fpcNames, fallback, fpcMainSha);
      Log('FAILED to fetch '+REPO_FPC+' branches ('+T.ErrorMsg+'); using stale cache ('+IntToStr(Round(age))+' min old)');
      FillCombo(ComboBoxUnleashedBranch, REPO_FPC, fallback, '');
    end else FillCombo(ComboBoxUnleashedBranch, REPO_FPC, T.Branches, T.ErrorMsg);
    FFpcFetchOk := False;
  end else begin
    FillCombo(ComboBoxUnleashedBranch, REPO_FPC, T.Branches, T.ErrorMsg);
    FFpcFetchOk := True;
  end;
  FUnleashedReady := True;
  ApplyUnleashedEnabled;
  FetchTick;
end;

procedure TMainForm.OnLazarusDone(Sender: TObject);
begin
  if FShuttingDown then Exit;
  var T := TBranchFetchThread(Sender);
  if T.ErrorMsg <> '' then begin
    var fpcNames := autofree TStringList.Create;
    var ideNames := autofree TStringList.Create;
    var age: Double;
    var fpcMainSha, ideMainSha: string;
    if LoadCache(fpcNames, ideNames, age, fpcMainSha, ideMainSha) and (ideNames.Count > 0) then begin
      var fallback := autofree TStringList.Create;
      NamesToShaListWithMain(ideNames, fallback, ideMainSha);
      Log('FAILED to fetch '+REPO_LAZARUS+' branches ('+T.ErrorMsg+'); using stale cache ('+IntToStr(Round(age))+' min old)');
      FillCombo(ComboBoxLazarusBranch, REPO_LAZARUS, fallback, '');
    end else FillCombo(ComboBoxLazarusBranch, REPO_LAZARUS, T.Branches, T.ErrorMsg);
    FLazFetchOk := False;
  end else begin
    FillCombo(ComboBoxLazarusBranch, REPO_LAZARUS, T.Branches, T.ErrorMsg);
    FLazFetchOk := True;
  end;
  FLazarusReady := True;
  ApplyLazarusEnabled;
  FetchTick;
end;

procedure TMainForm.FillCombo(Combo: TComboBox; const Repo: string; Branches: TStringList; const ErrorMsg: string);
begin
  // pick matching SHA map by repo so caller code stays simple
  var shaMap := if Repo = REPO_FPC then FFpcBranchShas else if Repo = REPO_LAZARUS then FLazBranchShas else nil;
  if shaMap <> nil then shaMap.Clear;

  Combo.Items.Clear;
  if ErrorMsg <> '' then begin
    Log('FAILED to fetch '+Repo+' branches: '+ErrorMsg);
    Combo.Items.Add('main');
    Combo.ItemIndex := 0;
    Exit;
  end;
  // Branches is 'name=sha'; Names[i] for combo, Values[name] for SHA
  if shaMap <> nil then shaMap.Assign(Branches);
  for var i := 0 to Branches.Count-1 do Combo.Items.Add(Branches.Names[i]);

  Log('Got '+IntToStr(Branches.Count)+' branches for '+Repo);
  // priority: pinned (filename) -> manifest -> main -> master -> first.
  // csDropDownList drops Combo.Text not in Items, so this must run after Items populates (fetch is async)
  var pinnedBranch: string := '';
  if Combo = ComboBoxUnleashedBranch then begin
    if FPinnedFpcBranchName <> '' then pinnedBranch := FPinnedFpcBranchName
    else if FPinnedFpcBranchHex <> '' then begin
      pinnedBranch := FindBranchByHashPrefix(Combo.Items, FPinnedFpcBranchHex);
      if pinnedBranch <> '' then Log('fpc branch '''+pinnedBranch+''' matches hash prefix '''+FPinnedFpcBranchHex+''', selecting this branch');
    end;
  end else if Combo = ComboBoxLazarusBranch then begin
    if FPinnedLazBranchName <> '' then pinnedBranch := FPinnedLazBranchName
    else if FPinnedLazBranchHex <> '' then begin
      pinnedBranch := FindBranchByHashPrefix(Combo.Items, FPinnedLazBranchHex);
      if pinnedBranch <> '' then Log('ide branch '''+pinnedBranch+''' matches hash prefix '''+FPinnedLazBranchHex+''', selecting this branch');
    end;
  end;

  var manifestBranch: string := '';
  var m := ReadManifest(Trim(EditTargetDir.Text));
  if m.Present then manifestBranch := if Combo = ComboBoxUnleashedBranch then m.FpcBranch else if Combo = ComboBoxLazarusBranch then m.LazBranch else '';

  var idx: Integer := -1;
  if pinnedBranch <> '' then idx := Combo.Items.IndexOf(pinnedBranch);
  if idx < 0 then if manifestBranch <> '' then idx := Combo.Items.IndexOf(manifestBranch);
  if idx < 0 then idx := Combo.Items.IndexOf('main');
  if idx < 0 then idx := Combo.Items.IndexOf('master');
  if idx < 0 then idx := 0;
  if Combo.Items.Count > 0 then Combo.ItemIndex := idx;
  RefreshTargetState;
end;

procedure TMainForm.FetchTick;
begin
  Dec(FFetchPending);
  if FFetchPending = 0 then begin
    // rewrite cache only on full success; partial-success leaves old file alone for future fallback
    if FFpcFetchOk and FLazFetchOk then begin
      SaveCache(FFpcBranchShas, FLazBranchShas);
      Log('cached branch lists (TTL '+IntToStr(CACHE_TTL_MINUTES)+' min, file="'+CacheFilePath+'")');
    end;
    SetStatus('Ready');
    // folder-error / install-in-progress gates keep Install off after a successful fetch
    ButtonInstall.Enabled := (not FFolderError) and (not FInstalling);
  end;
end;

procedure TMainForm.ApplyUnleashedEnabled;
begin
  var act := CheckBoxInstallUnleashed.Checked and (not FInstalling);
  ComboBoxUnleashedBranch.Enabled := act and FUnleashedReady;
  CheckBoxUnleashedLatest.Enabled := act;
  EditUnleashedHash.Enabled := act and (not CheckBoxUnleashedLatest.Checked);
  // crosses are nested under FPC; host's own native target locked Enabled=False at FormCreate
  CheckBoxCrossWin32.Enabled   := act;
  CheckBoxCrossWasm.Enabled    := act;
  CheckBoxCrossLinux32.Enabled := act;
{$ifdef MSWINDOWS}
  CheckBoxCrossLinux64.Enabled := act;     // cross direction (win -> linux)
{$endif}
{$ifdef LINUX}
  CheckBoxCrossWin64.Enabled := act;       // cross direction (linux -> win)
{$endif}
  RefreshTargetState;
end;

procedure TMainForm.ApplyLazarusEnabled;
begin
  var act := CheckBoxInstallLazarus.Checked and (not FInstalling);
  ComboBoxLazarusBranch.Enabled := act and FLazarusReady;
  CheckBoxLazarusLatest.Enabled := act;
  // launch-after stays toggleable even during install -- user can change mind mid-install,
  // OnInstallComplete reads the live checkbox value
  CheckBoxLaunchAfter.Enabled := CheckBoxInstallLazarus.Checked;
  EditLazarusHash.Enabled := act and (not CheckBoxLazarusLatest.Checked);
  // addons nested under IDE
  CheckBoxMinimap.Enabled := act;
  CheckBoxCPUView.Enabled := act;
  CheckBoxMetaDarkStyle.Enabled := act;
  // toggle-affinity locked off on non-Windows hosts (FormCreate disables it once)
{$ifdef MSWINDOWS}
  CheckBoxToggleAffinity.Enabled := act;
{$endif}
  RefreshTargetState;
end;

procedure TMainForm.CheckBoxInstallUnleashedChange(Sender: TObject);
begin
  ApplyUnleashedEnabled;
end;

procedure TMainForm.CheckBoxInstallLazarusChange(Sender: TObject);
begin
  ApplyLazarusEnabled;
end;

procedure TMainForm.CheckBoxUnleashedLatestChange(Sender: TObject);
begin
  // on checked->unchecked, pre-fill the now-enabled commit edit.
  // priority: 1) installer.ini SHA (pin to disk install, don't silently stage HEAD); 2) head SHA of selected branch.
  // live fetch knows every branch SHA; cache-hit only knows 'main' so other branches leave the edit blank
  if not CheckBoxUnleashedLatest.Checked then begin
    var sha: string := '';
    var m := ReadManifest(Trim(EditTargetDir.Text));
    if m.Present then sha := m.FpcSha;
    if (sha = '') and (FFpcBranchShas <> nil) and (ComboBoxUnleashedBranch.Text <> '') then sha := FFpcBranchShas.Values[ComboBoxUnleashedBranch.Text];
    if sha <> '' then EditUnleashedHash.Text := sha;
  end;
  ApplyUnleashedEnabled;
end;

procedure TMainForm.CheckBoxLazarusLatestChange(Sender: TObject);
begin
  if not CheckBoxLazarusLatest.Checked then begin
    // mirror Unleashed: manifest first then HEAD
    var sha: string := '';
    var m := ReadManifest(Trim(EditTargetDir.Text));
    if m.Present then sha := m.LazSha;
    if (sha = '') and (FLazBranchShas <> nil) and (ComboBoxLazarusBranch.Text <> '') then sha := FLazBranchShas.Values[ComboBoxLazarusBranch.Text];
    if sha <> '' then EditLazarusHash.Text := sha;
  end;
  ApplyLazarusEnabled;
end;

// i386-linux build needs ppcross386 (i386-win32 cross); auto-tick the prereq
procedure TMainForm.OnAddonOrCrossChange(Sender: TObject);
begin
  if (Sender = CheckBoxCrossLinux32) and CheckBoxCrossLinux32.Checked then CheckBoxCrossWin32.Checked := True;
  RefreshTargetState;
end;

procedure TMainForm.LabelLinkCPUViewClick(Sender: TObject);
begin
  OpenURL('https://github.com/AlexanderBagel/CPUView');
end;

procedure TMainForm.LabelLinkMetaDarkStyleClick(Sender: TObject);
begin
  OpenURL('https://github.com/zamtmn/metadarkstyle');
end;

procedure TMainForm.SetStatus(const msg: string);
begin
  StatusBar.SimpleText := msg;
end;

procedure TMainForm.Log(const msg: string);
begin
  var fullText := FormatDateTime('hh:nn:ss', Now)+'# '+msg;
  ListBoxLog.Items.Add(fullText);

  // grow horizontal scrollbar so wide make/lazbuild lines can scroll into view; +24 for per-line padding
  var lineWidth := ListBoxLog.Canvas.TextWidth(fullText)+24;
  if lineWidth > ListBoxLog.ScrollWidth then ListBoxLog.ScrollWidth := lineWidth;

  // keep last line visible. earlier ClientHeight-div math broke on gtk2 pre-first-paint (ClientHeight=0 -> TopIndex past end)
  ListBoxLog.TopIndex := ListBoxLog.Items.Count-1;
end;

procedure TMainForm.SetDoubleBufferedRecursive(c: TWinControl);
begin
  c.DoubleBuffered := True;
  for var i := 0 to c.ControlCount-1 do
    if c.Controls[i] is TWinControl then SetDoubleBufferedRecursive(TWinControl(c.Controls[i]));
end;

procedure TMainForm.CopySelectedLogLines;
begin
  var s := '';
  for var i := 0 to ListBoxLog.Items.Count-1 do
    if ListBoxLog.Selected[i] then begin
      if s <> '' then s := s+LineEnding;
      s := s+ListBoxLog.Items[i];
    end;
  // fall back to current item if nothing selected
  if (s = '') and (ListBoxLog.ItemIndex >= 0) then s := ListBoxLog.Items[ListBoxLog.ItemIndex];
  if s <> '' then Clipboard.AsText := s;
end;

procedure TMainForm.ListBoxLogKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // listbox eats Ctrl+C otherwise; menu shortcut also wired
  if (Key = VK_C) and (ssCtrl in Shift) then begin
    CopySelectedLogLines;
    Key := 0;
  end;
end;

procedure TMainForm.MenuCopyClick(Sender: TObject);
begin
  CopySelectedLogLines;
end;

procedure TMainForm.MenuFileExitClick(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.MenuRepoMainClick(Sender: TObject);
begin
  OpenURL('https://github.com/fpc-unleashed');
end;

procedure TMainForm.MenuRepoFreepascalClick(Sender: TObject);
begin
  OpenURL('https://github.com/fpc-unleashed/freepascal');
end;

procedure TMainForm.MenuRepoLazarusClick(Sender: TObject);
begin
  OpenURL('https://github.com/fpc-unleashed/lazarus');
end;

procedure TMainForm.MenuRepoInstallerClick(Sender: TObject);
begin
  OpenURL('https://github.com/fpc-unleashed/installer');
end;

procedure TMainForm.MenuHelpDocsClick(Sender: TObject);
begin
  OpenURL('https://github.com/fpc-unleashed/freepascal/blob/main/unleashed/docs/README.md');
end;

procedure TMainForm.MenuHelpAboutClick(Sender: TObject);
begin
  ShowAbout(Self, Self.Caption);
end;

// first match wins; ordered most-severe to least so "Error: warning" renders red
function ColorForLine(const s: string): TColor;
begin
  if (Pos('Error', s) > 0) or (Pos('Fatal', s) > 0) or (Pos('FAILED', s) > 0) or (Pos('failed:', s) > 0) then Result := clRed
  else if Pos('Warning', s) > 0 then Result := clOlive
  else if (Pos('===', s) > 0) or (Pos(' ---', s) > 0) then Result := clNavy
  else if (Pos('Compiling ', s) > 0) or (Pos('Linking ', s) > 0) or (Pos('Installing ', s) > 0) then Result := TColor($008000) // dark green
  else if Pos('make[', s) > 0 then Result := clGray
  else Result := clWindowText;
end;

procedure TMainForm.ListBoxLogDrawItem(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
begin
  var s := ListBoxLog.Items[Index];
  var cv := ListBoxLog.Canvas;
  if odSelected in State then begin
    cv.Brush.Color := clHighlight;
    cv.Font.Color := clHighlightText;
    cv.Font.Style := [];
  end else if Pos('IMPORTANT', s) > 0 then begin
    // banner: bold black on yellow
    cv.Brush.Color := clYellow;
    cv.Font.Color := clBlack;
    cv.Font.Style := [fsBold];
  end else begin
    cv.Brush.Color := clWindow;
    cv.Font.Color := ColorForLine(s);
    cv.Font.Style := [];
  end;
  cv.FillRect(ARect);
  cv.TextOut(ARect.Left+4, ARect.Top, s);
end;

procedure TMainForm.ButtonBrowseClick(Sender: TObject);
begin
  if SelectDirDialog.Execute then EditTargetDir.Text := SelectDirDialog.FileName;
end;

procedure TMainForm.SetInputsEnabled(act: Boolean);
begin
  CheckBoxInstallUnleashed.Enabled := act;
  CheckBoxInstallLazarus.Enabled := act;
  EditTargetDir.Enabled := act;
  ButtonBrowse.Enabled := act;
  // folder-error gate wins over act so post-install re-enable doesn't accidentally reopen Install when dir is bad
  ButtonInstall.Enabled := act and (not FFolderError);
  ApplyUnleashedEnabled;
  ApplyLazarusEnabled;
end;

procedure TMainForm.OnInstallLog(const msg: string);
begin
  if FShuttingDown then Exit;
  Log(msg);
end;

procedure TMainForm.OnInstallProgress(Percent: Integer; const status: string);
begin
  if FShuttingDown then Exit;
  if Percent < 0 then begin
    ProgressBar.Style := pbstMarquee;
    SetStatus(status);
  end else begin
    ProgressBar.Style := pbstNormal;
    if Percent > 100 then Percent := 100;
    if Percent < 0 then Percent := 0;
    ProgressBar.Position := Percent;
    SetStatus(IntToStr(Percent)+'%  '+status);
  end;
end;

procedure TMainForm.OnInstallComplete(Sender: TObject);
begin
  if FShuttingDown then Exit;
  var T := TInstallThread(Sender);
  ProgressBar.Style := pbstNormal;
  if T.Success then begin
    Log('=== INSTALL OK ===');
    SetStatus('Done');
    if FInstalledLazarus and CheckBoxLaunchAfter.Checked then LaunchInstalledIde;
  end else begin
    Log('=== INSTALL FAILED: '+T.ErrorMsg+' ===');
    SetStatus('Failed: '+T.ErrorMsg);
    ProgressBar.Position := 0;
  end;
  FInstalling := False;
  SetInputsEnabled(True);
end;

procedure TMainForm.LaunchInstalledIde;
begin
  var ExePath := IncludeTrailingPathDelimiter(FInstallTargetDir)+LazarusBinarySub;
  var PcpArg  := '--pcp='+IncludeTrailingPathDelimiter(FInstallTargetDir)+'config_lazarus';
  Log('Launching '+ExePath);
{$ifdef MSWINDOWS}
  // detached. ShellExecute wants args as one string; quotes protect spaces in target dir
  var Args := '"'+PcpArg+'"';
  ShellExecute(Handle, 'open', PChar(ExePath), PChar(Args), PChar(ExtractFilePath(ExePath)), SW_SHOWNORMAL);
{$endif}
{$ifdef LINUX}
  // TProcess + no poWaitOnExit -> lazarus runs independently of installer (same as +x .desktop double-click)
  var P := TProcess.Create(nil);
  try
    P.Executable := ExePath;
    P.Parameters.Add(PcpArg);
    P.CurrentDirectory := ExtractFilePath(ExePath);
    P.Options := [];
    P.InheritHandles := False;
    P.Execute;
  finally
    // don't Free before Execute returns -- child is running; Free would lose our handle, OS reaps it on installer exit
    P.Free;
  end;
{$endif}
end;

procedure TMainForm.ButtonInstallClick(Sender: TObject);
var
  cfg: TInstallConfig;
begin
  if FInstalling then Exit;
  // belt-and-braces: button is disabled while FFolderError, but a stale OnClick race could still land here
  if FFolderError then Exit;

  cfg.TargetDir := Trim(EditTargetDir.Text);
  if cfg.TargetDir = '' then begin
    Log('install dir is empty');
    Exit;
  end;

  cfg.InstallFpc     := CheckBoxInstallUnleashed.Checked;
  cfg.InstallLazarus := CheckBoxInstallLazarus.Checked;
  // cross choices meaningless w/o FPC (no ppcx64 to drive crossinstall); force-off so pipeline doesn't try
  cfg.CrossWin64     := CheckBoxCrossWin64.Checked   and cfg.InstallFpc;
  cfg.CrossWin32     := CheckBoxCrossWin32.Checked   and cfg.InstallFpc;
  cfg.CrossLinux64   := CheckBoxCrossLinux64.Checked and cfg.InstallFpc;
  cfg.CrossLinux32   := CheckBoxCrossLinux32.Checked and cfg.InstallFpc;
  cfg.CrossWasm      := CheckBoxCrossWasm.Checked    and cfg.InstallFpc;
  // addons meaningless w/o IDE (lazbuild needs IDE)
  cfg.InstallMinimap       := CheckBoxMinimap.Checked       and cfg.InstallLazarus;
  cfg.InstallCPUView       := CheckBoxCPUView.Checked       and cfg.InstallLazarus;
  cfg.InstallMetaDarkStyle := CheckBoxMetaDarkStyle.Checked and cfg.InstallLazarus;
  // on linux this is always False (FormCreate locks Enabled+Checked=False), so no host ifdef needed
  cfg.InstallToggleAffinity := CheckBoxToggleAffinity.Checked and cfg.InstallLazarus;
  cfg.LaunchAfter    := CheckBoxLaunchAfter.Checked;

  // snapshot IDE install decision; OnInstallComplete combines with live CheckBoxLaunchAfter.Checked to decide launch
  FInstalledLazarus := cfg.InstallLazarus;
  FInstallTargetDir := cfg.TargetDir;
  cfg.FpcLatest      := CheckBoxUnleashedLatest.Checked;
  cfg.FpcBranch      := ComboBoxUnleashedBranch.Text;
  cfg.FpcHash        := Trim(EditUnleashedHash.Text);
  cfg.LazLatest      := CheckBoxLazarusLatest.Checked;
  cfg.LazBranch      := ComboBoxLazarusBranch.Text;
  cfg.LazHash        := Trim(EditLazarusHash.Text);
  // resolved SHA into manifest for later compare; empty if branch list not yet loaded
  cfg.FpcSelectedSha := ResolveSelectedFpcSha;
  cfg.LazSelectedSha := ResolveSelectedLazSha;
  cfg.SaveLog        := CheckBoxSaveLog.Checked;

  Log('--- install requested ---');
  Log('target dir: '+cfg.TargetDir);
  if cfg.InstallFpc then Log('install fpc-unleashed: yes ('+cfg.FpcBranch+')') else Log('install fpc-unleashed: no');
  if cfg.InstallLazarus then Log('install lazarus IDE:  yes ('+cfg.LazBranch+')') else Log('install lazarus IDE:  no');

  FInstalling := True;
  SetInputsEnabled(False);
  ProgressBar.Position := 0;
  ProgressBar.Style := pbstNormal;

  TInstallThread.Create(cfg, @OnInstallLog, @OnInstallProgress, @OnInstallComplete);
end;

procedure TMainForm.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

// cross-platform icon resource generated from src/installer.png via:
//   tools/lazres.exe src/installer.lrs src/installer.png
// Windows uses PE .ico via .res; this .lrs is consumed only on Linux (gtk2/qt LCL needs in-memory image for Application.Icon)
{$ifdef LINUX}
initialization
  {$I installer.lrs}
{$endif}

end.
