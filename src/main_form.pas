{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit main_form;

{$mode unleashed}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Dialogs,
  Graphics, LCLType, LCLIntf, LResources, Menus, Clipbrd, RegExpr, fileinfo,
  {$ifdef MSWINDOWS} Windows, ShellApi, {$endif}
  {$ifdef LINUX} process, {$endif}
  branch_fetch, branch_cache, install_pipeline, install_manifest, hash_branch,
  about_form;

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
    FLaunchAfterInstall: Boolean;
    FInstallTargetDir: string;
    // last target dir for which the cross checkboxes were synced from the
    // manifest; prevents RefreshTargetState (called on every selection
    // change) from clobbering the user's subsequent checkbox toggles
    FCrossSyncedFor: string;
    // Gate for the state-B reset so a re-entry from a checkbox toggle
    // does not clobber the just-made change. 'A'/'B'/'C'/'D' or #0.
    FLastState: Char;
    FLastStateDir: string;
    // raw 'name=sha' lists from branch_fetch; Values[branchName] yields
    // head SHA; both kept to drive update-vs-installed comparisons
    FFpcBranchShas: TStringList;
    FLazBranchShas: TStringList;
    // Branch hints from the filename pin (consumed in FillCombo once
    // the async fetch populates Combo.Items). One of *Name / *HashHex
    // per repo: *Name for predefined ('main'/'devel'), *HashHex for a
    // murmur3 prefix that needs the fetched list to resolve.
    FPinnedFpcBranchName: string;
    FPinnedFpcBranchHex:  string;
    FPinnedLazBranchName: string;
    FPinnedLazBranchHex:  string;
    // FetchTick rewrites the cache only when BOTH are True; a partial
    // success run can't leave an inconsistent file marked fresh.
    FFpcFetchOk: Boolean;
    FLazFetchOk: Boolean;
    // True while the chosen target dir is unusable (blank or non-empty
    // without installer.ini); gates ButtonInstall.Enabled.
    FFolderError: Boolean;
    // Re-entrancy guard for RefreshTargetState; the state-B reset
    // writes back to controls whose OnChange calls back here.
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
  // mirror install_pipeline's per-OS host paths so RefreshTargetState +
  // LaunchInstalledIde inspect the same files the pipeline creates.
{$ifdef MSWINDOWS}
  HostFpcWrapperSub  = 'fpc\bin\x86_64-win64\fpc.exe';
  LazarusBinarySub   = 'lazarus\lazarus.exe';
{$endif}
{$ifdef LINUX}
  HostFpcWrapperSub  = 'fpc/bin/fpc';
  LazarusBinarySub   = 'lazarus/lazarus';
{$endif}

// Filesystem is authoritative for what's installed; the manifest only
// records intent (a crashed install leaves no manifest). Linux scans
// for the version dir under fpc/lib/fpc/ since fpc-unleashed reports
// 3.3.1+ vs the 3.2.2 bootstrap.
function IsDirEffectivelyEmpty(const Dir: string): Boolean;
var SR: TSearchRec;
begin
  Result := True;
  if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') then begin
        Result := False;
        Exit;
      end;
    until FindNext(SR) <> 0;
  finally
    // SysUtils. qualifier needed -- on Windows the Windows unit in the
    // uses clause also exports FindClose (WinAPI, takes a HANDLE), which
    // otherwise shadows the SysUtils overload that takes a TSearchRec.
    SysUtils.FindClose(SR);
  end;
end;

function ProbeCrossInstalled(const dir, target: string): Boolean;
begin
  Result := False;
  if dir = '' then Exit;
{$ifdef MSWINDOWS}
  Result := DirectoryExists(IncludeTrailingPathDelimiter(dir) + 'fpc\units\' + target);
{$endif}
{$ifdef LINUX}
  var Base := IncludeTrailingPathDelimiter(dir) + 'fpc/lib/fpc/';
  if not DirectoryExists(Base) then Exit;
  var SR: TSearchRec;
  if FindFirst(Base + '*', faDirectory, SR) = 0 then
  try
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') and
         ((SR.Attr and faDirectory) <> 0) and
         (Length(SR.Name) > 0) and (SR.Name[1] in ['0'..'9']) and
         DirectoryExists(Base + SR.Name + '/units/' + target) then begin
        Result := True;
        Exit;
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
{$endif}
end;

// Tag the form's title bar with the version string baked into the exe's
// VERSIONINFO resource (filled in via Project Options -> Version Info)
// plus the wall-clock moment the binary was compiled. The %DATE% / %TIME%
// macros are expanded by the FPC preprocessor into string literals at
// compile time -- they are not function calls, the values are frozen at
// build. Format YYYY/MM/DD HH:MM:SS -> rewrite slashes to dashes and drop
// the seconds for the displayed timestamp.
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
// WS_EX_COMPOSITED tells DWM to composite the whole form + all child
// windows off-screen and present atomically -- without it the ~50
// child HWNDs (panels/checkboxes/edits) repaint individually on
// restore/resize, visible as a cascade.
procedure TMainForm.CreateParams(var Params: TCreateParams);
const
  WS_EX_COMPOSITED = $02000000;
begin
  inherited CreateParams(Params);
  Params.ExStyle := Params.ExStyle or WS_EX_COMPOSITED;
end;

// Menu bar lives in the non-client area where WS_EX_COMPOSITED does
// not reach. Suppress NC paint during a drag-resize and force one
// frame redraw on exit so the menu does not flicker as user drags.
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

  // On Linux the icon embedded via the .res from .lpi does not reach
  // Application.Icon (LCL gtk2/qt do not consume the PE icon group),
  // so the same PNG is also embedded as a Lazarus resource and loaded
  // here at runtime. Windows already has the .ico-multi-size icon via
  // the PE resource and needs nothing further.
  {$ifdef LINUX}
  var IconStream := autofree TLazarusResourceStream.Create('installer', nil);
  var Png        := autofree TPortableNetworkGraphic.Create;
  Png.LoadFromStream(IconStream);
  Application.Icon.Assign(Png);
  Self.Icon.Assign(Png);
  {$endif}

  // augment the captured-from-LFM caption with version + build stamp
  var BuildDate := StringReplace(BUILD_DATE_RAW, '/', '-', [rfReplaceAll]);
  var BuildTime := Copy(BUILD_TIME_RAW, 1, 5);   // HH:MM, drop :SS
  var Ver := GetAppVersion;
  if Ver <> '' then Caption := Caption + ' v' + Ver;
  Caption := Caption + ' (built at ' + BuildDate + ' ' + BuildTime + ')';
  // Set the cross checkbox defaults BEFORE assigning EditTargetDir.Text.
  // Setting .Text fires EditTargetDirChange -> RefreshTargetState, and
  // that handler does a filesystem probe to set the cross-checkbox state
  // to match what's actually installed (sets FCrossSyncedFor). If we
  // override the checkbox defaults AFTER that runs, the explicit
  // RefreshTargetState below sees FCrossSyncedFor already set, skips the
  // re-sync, and the overrides win -- producing "checkbox shows ticked
  // even though nothing's installed".
  {$ifdef LINUX}
  // host is x86_64-linux; native build covers it, so a "cross to
  // linux64" choice is meaningless. The cross-to-win64 checkbox is
  // left unchecked at startup -- user opts in deliberately so we don't
  // surprise them with cross-toolchain downloads.
  CheckBoxCrossLinux64.Enabled := False;
  CheckBoxCrossLinux64.Checked := False;
  CheckBoxCrossLinux64.Caption := 'x86_64-linux (native)';
  EditTargetDir.Text := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) + 'fpcunleashed';
  // Toggle Display Affinity uses Windows-only user32 API
  // (Set/GetWindowDisplayAffinity). The package itself compiles on Linux
  // (its Register is wrapped in {$ifdef WINDOWS}) but installing it would
  // be a no-op, so the checkbox is locked off here to make the platform
  // restriction obvious. Stays disabled across ApplyLazarusEnabled calls.
  CheckBoxToggleAffinity.Enabled := False;
  CheckBoxToggleAffinity.Checked := False;
  {$else}
  // host is x86_64-win64; mirror the logic for the other direction.
  // Cross-to-linux64 also starts unchecked.
  CheckBoxCrossWin64.Enabled := False;
  CheckBoxCrossWin64.Checked := False;
  CheckBoxCrossWin64.Caption := 'x86_64-win64 (native)';
  EditTargetDir.Text := 'C:\fpcunleashed';
  {$endif}
  // Per-child DoubleBuffered. Form-level alone only covers the form's
  // background; each child HWND (panel/edit/combo/listbox) still paints
  // direct to screen otherwise.
  SetDoubleBufferedRecursive(Self);

  SetStatus('Ready');
  ApplyUnleashedEnabled;
  ApplyLazarusEnabled;
  RefreshTargetState;
  ApplyHashesFromBinaryName;

  // Size to 80% of the work area (taskbar excluded) and re-center
  // vertically. The LFM Position=poScreenCenter handles initial
  // centering but uses the LFM-stored Height, which is just a
  // designer-time default. On a tall monitor the form would otherwise
  // sit fixed at ~614px and leave the log box cramped; resizing here
  // hands the surplus space to the alClient log box.
  Self.Height := Screen.WorkAreaHeight * 80 div 100;
  Self.Top := Screen.WorkAreaTop +
              (Screen.WorkAreaHeight - Self.Height) div 2;
end;

procedure tmainform.button1click(sender: tobject);
begin
  ListBoxLog.Clear;
end;

// Pull the pinned (fpc, laz) pair out of ParamStr(1) or the binary
// filename. Wire format and semantics: see README.md ("Filename hash
// pin") and hash_branch.pas. Legacy two-hash regex below is kept so
// older release filenames still self-pin (commits only).
procedure TMainForm.ApplyHashesFromBinaryName;
const
  // Used only by the legacy fallback path; the new encoder produces a
  // single hex+digit run with no separators which this pattern can't see.
  HASH_PATTERN = '(?<![0-9a-fA-F])([0-9a-fA-F]{7,12})[^0-9a-fA-F]+([0-9a-fA-F]{7,12})(?![0-9a-fA-F])';
begin
  var parsed: TParsedBinaryName;
  parsed.Present := False;

  // 1. Cmdline override via ParamStr(1) -- the whole arg is taken as the
  //    raw blob (no run extraction, no length floor). If the arg is a
  //    valid blob it wins; if it isn't (user passed something benign
  //    like a path or unrelated flag), the parser silently falls back
  //    to the filename so the override path doesn't break ordinary use.
  if (ParamCount >= 1) and (ParamStr(1) <> '') then begin
    if TryParseBlob(ParamStr(1), parsed) then Log('using cmdline pin: ' + ParamStr(1)) else Log('cmdline arg "' + ParamStr(1) + '" is not a pin blob; ' + 'falling back to filename');
  end;

  // 2. Filename (new length-prefixed format) -- the LAST hex run >= 12.
  if not parsed.Present then parsed := ParseBinaryName(ExtractFileName(ParamStr(0)));

  if parsed.Present then begin
    // Commits: empty FpcCommit / LazCommit means the blob encoded a '0'
    // length digit -- the "use latest of selected branch" sentinel. Tick
    // CheckBoxLatest in that case and clear the hash edit; otherwise
    // pin the explicit hash and untick.
    Log('binary name carries pinned commit hashes: fpc=' +
        (if parsed.FpcCommit = '' then '(latest)' else parsed.FpcCommit) +
        ' ide=' +
        (if parsed.LazCommit = '' then '(latest)' else parsed.LazCommit));

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

    // Stash branch hints for FillCombo to apply after the async fetch
    // returns. The hash override (pos 3/4) takes precedence over the
    // predefined / implicit-main branch chosen by the commit field
    // (pos 1/2); FillCombo's priority ladder reflects that.
    if parsed.FpcBranchHashOverride <> '' then FPinnedFpcBranchHex := parsed.FpcBranchHashOverride
    else if parsed.FpcBranchFromCommit <> '' then FPinnedFpcBranchName := parsed.FpcBranchFromCommit;
    if parsed.LazBranchHashOverride <> '' then FPinnedLazBranchHex := parsed.LazBranchHashOverride
    else if parsed.LazBranchFromCommit <> '' then FPinnedLazBranchName := parsed.LazBranchFromCommit;

    // Companion summary line for the branch info, mirroring the commit
    // line shape. For predefined / implicit-main branches the resolved
    // name lands here (so the log reads e.g. "fpc=main ide=devel"); for
    // hash-overridden branches the hex prefix shows up instead and the
    // matching branch name follows later as a FillCombo "branch ...
    // matches" line once the async fetch lands.
    var fpcStr: string :=
      if parsed.FpcBranchHashOverride <> '' then parsed.FpcBranchHashOverride
      else if parsed.FpcBranchFromCommit <> '' then parsed.FpcBranchFromCommit
      else '(default)';
    var lazStr: string :=
      if parsed.LazBranchHashOverride <> '' then parsed.LazBranchHashOverride
      else if parsed.LazBranchFromCommit <> '' then parsed.LazBranchFromCommit
      else '(default)';
    Log('binary name carries pinned branch hashes: fpc=' + fpcStr + ' ide=' + lazStr);

    RefreshTargetState;
    Exit;
  end;

  // 3. Fallback: legacy two-hash regex for older release filenames. Only
  //    consulted when neither the cmdline blob nor the new filename run
  //    produced anything usable. Always runs against the filename, never
  //    the cmdline arg (the cmdline form is strictly the new encoding).
  var Name := ExtractFileName(ParamStr(0));
  var R := autofree TRegExpr.Create;
  R.Expression := HASH_PATTERN;
  if not R.Exec(Name) then Exit;

  var FpcHash := LowerCase(R.&Match[1]);
  var LazHash := LowerCase(R.&Match[2]);
  Log('binary name carries pinned commit hashes (legacy): fpc=' + FpcHash + ' ide=' + LazHash);
  EditUnleashedHash.Text       := FpcHash;
  CheckBoxUnleashedLatest.Checked := False;
  EditLazarusHash.Text         := LazHash;
  CheckBoxLazarusLatest.Checked := False;
  // RefreshTargetState already ran once during FormCreate using the
  // manifest-restored hashes; rerun it so LabelMode reflects the new
  // pinned values (e.g. switches to 'Update available: fpc abc1234 ->
  // def5678' when the binary points at a newer commit than what's
  // installed). FCrossSyncedFor stops it re-running the manifest
  // checkbox sync this time.
  RefreshTargetState;
end;

procedure TMainForm.EditTargetDirChange(Sender: TObject);
begin
  RefreshTargetState;
end;

// Folder inspection is authoritative; installer.ini carries the build
// SHA so we can flag '(update available)'. Four states:
//   A. blank path           -> error, Install disabled
//   B. dir absent or empty  -> defaults, "New installation"
//   C. dir has installer.ini -> restore from manifest
//   D. dir non-empty w/o ini -> error (someone else's folder)
// A and D set FFolderError; FetchTick / SetInputsEnabled / ButtonInstallClick
// gate the Install button on it.
procedure TMainForm.RefreshTargetState;
begin
  // Re-entry guard: writing to the bound Edit/Combo controls inside
  // the body fires OnSelectionChange -> RefreshTargetState. Inner
  // calls safely no-op; the outer pass already plans to handle it.
  if FRefreshingTarget then Exit;
  FRefreshingTarget := True;
  try
  var rawDir := Trim(EditTargetDir.Text);

  // Optimistic reset; each branch either confirms or re-sets the flag.
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
  var manifestExists := FileExists(dir + MANIFEST_FILE);
  var dirExists      := DirectoryExists(dir);

  // ---- state B: target absent or empty (no manifest) -> fresh install ----
  // Reset only on entry into state-B (FLastState/Dir gate) so a checkbox
  // toggle re-firing RefreshTargetState does not wipe the user's change.
  if (not manifestExists) and ((not dirExists) or IsDirEffectivelyEmpty(dir)) then begin
    if (FLastState <> 'B') or (FLastStateDir <> rawDir) then ResetTargetControlsToDefaults;
    LabelMode.Caption := 'New installation';
    ButtonInstall.Caption := 'Install';
    if FFetchPending = 0 then ButtonInstall.Enabled := True;
    FLastState := 'B';
    FLastStateDir := rawDir;
    Exit;
  end;

  // ---- state D: dir has content but no manifest -> refuse ----
  // We can't safely install into a folder we don't own: a fresh install
  // overwrites large subtrees (fpc/, lazarus/, ...) and a stray
  // unrelated tree there would get clobbered. Force the user to pick a
  // clean dir or a genuine Unleashed install location.
  if not manifestExists then begin
    FFolderError := True;
    LabelMode.Font.Color := clRed;
    LabelMode.Caption :=
      'Target folder is not empty and is not an Unleashed install ' +
      '(installer.ini not found). Choose an empty directory or an ' +
      'existing Unleashed install location.';
    ButtonInstall.Enabled := False;
    FLastState := 'D';
    FLastStateDir := rawDir;
    Exit;
  end;

  // ---- state C: manifest present -> restore + update / reinstall ----
  var hasFpc := FileExists(dir + HostFpcWrapperSub);
  var hasLaz := FileExists(dir + LazarusBinarySub);

  var parts := '';
  if hasFpc then parts := 'fpc';
  if hasLaz then begin
    if parts <> '' then parts := parts + ' + ';
    parts := parts + 'lazarus';
  end;
  // List every target compiler the user can pick, native first. Native
  // shares the units/ layout with crosses so ProbeCrossInstalled picks
  // it up naturally; listing it explicitly makes the label match the
  // full set of cross checkboxes (otherwise users wonder why the
  // "what's installed" summary omits the host platform).
  {$ifdef MSWINDOWS}
  var crossTargets: TStringArray := [
    'x86_64-win64', 'x86_64-linux', 'i386-win32', 'i386-linux', 'wasm32-wasip1'];
  {$endif}
  {$ifdef LINUX}
  var crossTargets: TStringArray := [
    'x86_64-linux', 'x86_64-win64', 'i386-win32', 'i386-linux', 'wasm32-wasip1'];
  {$endif}
  for var t in crossTargets do
    if ProbeCrossInstalled(rawDir, t) then begin
      if parts <> '' then parts := parts + ' + ';
      parts := parts + t;
    end;

  // pull last-installed SHAs from manifest and compare to currently-
  // selected SHAs to decide whether to flag an update. User-typed short
  // hashes are matched as a prefix of the manifest's full SHA in either
  // direction (typed-short vs stored-full).
  var m := ReadManifest(rawDir);
  var updates := '';
  // Sync checkboxes once per target dir (subsequent RefreshTargetState
  // calls from combo / hash edits leave user toggles alone). Gate is
  // manifest-presence rather than hasFpc so a partial install (manifest
  // written but binary missing) still triggers the restore.
  if FCrossSyncedFor <> dir then begin
    FCrossSyncedFor := dir;
    // CheckBoxCross{Win64,Linux64} only get synced on the host where
    // they are not the native target -- on the other host they are
    // disabled at FormCreate.
    if CheckBoxCrossWin64.Enabled   then CheckBoxCrossWin64.Checked   := ProbeCrossInstalled(rawDir, 'x86_64-win64');
    if CheckBoxCrossLinux64.Enabled then CheckBoxCrossLinux64.Checked := ProbeCrossInstalled(rawDir, 'x86_64-linux');
    CheckBoxCrossWin32.Checked   := ProbeCrossInstalled(rawDir, 'i386-win32');
    CheckBoxCrossLinux32.Checked := ProbeCrossInstalled(rawDir, 'i386-linux');
    CheckBoxCrossWasm.Checked    := ProbeCrossInstalled(rawDir, 'wasm32-wasip1');
    // Restore last-used non-filesystem-detectable selections (branch,
    // commit hash, addon ticks, launch-after) from the manifest. These
    // don't have a filesystem fingerprint so manifest is the only source.
    if m.Present then begin
      CheckBoxMinimap.Checked      := m.InstallMinimap;
      CheckBoxCPUView.Checked      := m.InstallCPUView;
      CheckBoxMetaDarkStyle.Checked := m.InstallMetaDarkStyle;
      // Only restore the Windows-only addon ticks on hosts where the
      // checkbox is interactable. On Linux the checkbox is locked
      // .Enabled=False at FormCreate; flipping its .Checked from a
      // Windows-written manifest would just confuse the user.
      if CheckBoxToggleAffinity.Enabled then CheckBoxToggleAffinity.Checked := m.InstallToggleAffinity;
      CheckBoxLaunchAfter.Checked  := m.LaunchAfter;
      if m.FpcBranch <> '' then begin
        ComboBoxUnleashedBranch.Text := m.FpcBranch;
        // Always show the last installed SHA in the hash field, even
        // when latest was selected -- user can see what commit they're
        // currently on. The hash field stays disabled when latest is
        // ticked (existing UI behavior) so it's display-only in that
        // case. Restore CheckBoxLatest from the explicit manifest flag
        // rather than guessing from an empty SHA: latest=yes still
        // records a resolved SHA in FpcSha for display purposes.
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
    if hasFpc and (selFpc <> '') and (m.FpcSha <> '') and (Pos(selFpc, m.FpcSha) <> 1) and (Pos(m.FpcSha, selFpc) <> 1) then
      updates := updates + ' fpc ' + Copy(m.FpcSha, 1, 7) +
                 ' -> ' + Copy(selFpc, 1, 7);
    if hasLaz and (selLaz <> '') and (m.LazSha <> '') and (Pos(selLaz, m.LazSha) <> 1) and (Pos(m.LazSha, selLaz) <> 1) then
      updates := updates + ' lazarus ' + Copy(m.LazSha, 1, 7) +
                 ' -> ' + Copy(selLaz, 1, 7);
    // addon deltas. Pipeline's StepRebuildLazarusForAddons handles
    // these without a full reinstall, but the user needs visual cues
    // so the Install/Reinstall button labels reflect reality.
    if hasLaz and (CheckBoxMinimap.Checked <> m.InstallMinimap) then updates := updates + (if CheckBoxMinimap.Checked then ' +minimap' else ' -minimap');
    if hasLaz and (CheckBoxCPUView.Checked <> m.InstallCPUView) then updates := updates + (if CheckBoxCPUView.Checked then ' +cpuview' else ' -cpuview');
    if hasLaz and (CheckBoxMetaDarkStyle.Checked <> m.InstallMetaDarkStyle) then updates := updates + (if CheckBoxMetaDarkStyle.Checked then ' +metadarkstyle' else ' -metadarkstyle');
    // Same .Enabled guard as the manifest restore above: on Linux the
    // delta is meaningless because the user can't change the toggle.
    if hasLaz and CheckBoxToggleAffinity.Enabled and (CheckBoxToggleAffinity.Checked <> m.InstallToggleAffinity) then
      updates := updates + (if CheckBoxToggleAffinity.Checked then ' +toggle-affinity' else ' -toggle-affinity');
    if hasFpc and CheckBoxCrossWin64.Enabled and (CheckBoxCrossWin64.Checked <> m.CrossWin64) then updates := updates + (if CheckBoxCrossWin64.Checked then ' +x86_64-win64' else ' -x86_64-win64');
    if hasFpc and (CheckBoxCrossWin32.Checked <> m.CrossWin32) then updates := updates + (if CheckBoxCrossWin32.Checked then ' +i386-win32' else ' -i386-win32');
    if hasFpc and (CheckBoxCrossLinux64.Checked <> m.CrossLinux64) then updates := updates + (if CheckBoxCrossLinux64.Checked then ' +x86_64-linux' else ' -x86_64-linux');
    if hasFpc and (CheckBoxCrossLinux32.Checked <> m.CrossLinux32) then updates := updates + (if CheckBoxCrossLinux32.Checked then ' +i386-linux' else ' -i386-linux');
    if hasFpc and (CheckBoxCrossWasm.Checked <> m.CrossWasm) then updates := updates + (if CheckBoxCrossWasm.Checked then ' +wasm32-wasip1' else ' -wasm32-wasip1');
  end;

  if updates <> '' then begin
    LabelMode.Caption := 'Update available:' + updates;
    ButtonInstall.Caption := 'Update';
  end else if parts <> '' then begin
    LabelMode.Caption := 'Existing install detected (' + parts + ') - Install will overwrite';
    ButtonInstall.Caption := 'Reinstall';
  end else begin
    // Manifest present but neither FPC nor Lazarus binary on disk -- a
    // prior install died after writing the manifest (or before any of
    // the build phases produced binaries). Treat as resumable rather
    // than as a fresh install: the manifest still owns the directory.
    LabelMode.Caption := 'Partial install detected (manifest only) - Install will resume';
    ButtonInstall.Caption := 'Resume';
  end;
  if FFetchPending = 0 then ButtonInstall.Enabled := True;
  FLastState := 'C';
  FLastStateDir := rawDir;
  finally
    FRefreshingTarget := False;
  end;
end;

procedure TMainForm.ResetTargetControlsToDefaults;
begin
  // Cross checkboxes -- all unchecked. FormCreate handles host-native
  // .Enabled/Caption tweaks once at startup; leaving Enabled alone here
  // means a host-disabled box stays disabled, which is what we want.
  CheckBoxCrossWin64.Checked   := False;
  CheckBoxCrossLinux64.Checked := False;
  CheckBoxCrossWin32.Checked   := False;
  CheckBoxCrossLinux32.Checked := False;
  CheckBoxCrossWasm.Checked    := False;

  // Addons -- match the LFM defaults that the first-time installer
  // ships with: the two lightweight IDE extras on, the heavier theme +
  // the Windows-only design-time plugin off.
  CheckBoxMinimap.Checked        := True;
  CheckBoxCPUView.Checked        := True;
  CheckBoxMetaDarkStyle.Checked  := False;
  // Toggle Display Affinity is .Enabled=False on Linux; writing False
  // here is a no-op visually and keeps the data model clean across
  // host swaps via shared manifest.
  CheckBoxToggleAffinity.Checked := False;

  // Master + latest + launch-after -- "fresh install" intent.
  CheckBoxInstallUnleashed.Checked := True;
  CheckBoxInstallLazarus.Checked   := True;
  CheckBoxUnleashedLatest.Checked  := True;
  CheckBoxLazarusLatest.Checked    := True;
  CheckBoxLaunchAfter.Checked      := True;

  // Hash fields are display-only while Latest is ticked; a stale hex
  // string would just be confusing. Clear them so the field is empty
  // until either the user unticks Latest (auto-fill from branch HEAD
  // kicks in) or types one explicitly.
  EditUnleashedHash.Text := '';
  EditLazarusHash.Text   := '';

  // Forget the per-dir cross-sync cache so a subsequent transition into
  // a manifest dir re-runs the filesystem + manifest restore rather
  // than treating the stale dir key as "already synced".
  FCrossSyncedFor := '';

  // Sub-control enabling cascades from the masters (e.g. hash edit
  // disabled while latest=on, addon block disabled while IDE off).
  ApplyUnleashedEnabled;
  ApplyLazarusEnabled;
end;

function TMainForm.ResolveSelectedFpcSha: string;
begin
  // explicit hash override wins, otherwise use the head SHA of the
  // currently-selected branch as known at the last fetch
  Result := if (not CheckBoxUnleashedLatest.Checked) and (Trim(EditUnleashedHash.Text) <> '') then LowerCase(Trim(EditUnleashedHash.Text))
            else if ComboBoxUnleashedBranch.Text <> '' then LowerCase(FFpcBranchShas.Values[ComboBoxUnleashedBranch.Text]) else '';
end;

function TMainForm.ResolveSelectedLazSha: string;
begin
  Result := if (not CheckBoxLazarusLatest.Checked) and (Trim(EditLazarusHash.Text) <> '') then LowerCase(Trim(EditLazarusHash.Text))
            else if ComboBoxLazarusBranch.Text <> '' then LowerCase(FLazBranchShas.Values[ComboBoxLazarusBranch.Text]) else '';
end;

procedure TMainForm.OnSelectionChange(Sender: TObject);
begin
  // wired to combo + hash edit OnChange events; keeps LabelMode's
  // '(update available)' hint live as the user picks a different
  // branch or types a different commit.
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
  // worker threads have FreeOnTerminate=True and call us via OnTerminate;
  // flag stops the callback from touching destroyed widgets
  FShuttingDown := True;
  FFpcBranchShas.Free;
  FLazBranchShas.Free;
end;

procedure TMainForm.StartBranchFetch;

  // Convert a bare-name list ('main', 'devel', ...) into the 'name=sha'
  // form FillCombo expects. Only the 'main' entry gets a real SHA (from
  // the matching fpc-hash / ide-hash line in the cache file); every
  // other branch is left empty on the Values side. Live fetches still
  // fill in SHAs for all branches, so this lossiness only bites
  // cache-hit launches and only for non-main branches.
  procedure AppendWithMainSha(Src: TStrings; Dest: TStrings; const MainSha: string);
  begin
    Dest.Clear;
    for var i := 0 to Src.Count - 1 do begin
      var name := Src[i];
      if SameText(name, 'main') then Dest.Add(name + '=' + MainSha) else Dest.Add(name + '=');
    end;
  end;

begin
  SetStatus('Updating branches list...');
  FFetchPending := 2;
  FFpcFetchOk := False;
  FLazFetchOk := False;
  ButtonInstall.Enabled := False;

  // Cache-first path: if the cache file sits in the per-user temp dir
  // and its `Cached at:` timestamp is younger than CACHE_TTL_MINUTES,
  // skip the GitHub fetch entirely. Keeps the anon API quota intact
  // across back-to-back launches.
  var fpcNames := autofree TStringList.Create;
  var ideNames := autofree TStringList.Create;
  var age: Double;
  var fpcMainSha, ideMainSha: string;
  if LoadCache(fpcNames, ideNames, age, fpcMainSha, ideMainSha) and (age < CACHE_TTL_MINUTES * 60) then begin
    Log('using cached branch lists (' + IntToStr(Round(age)) + ' sec(s) old, file="' + CacheFilePath + '")');
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

  Log('Fetching branches from github.com/' + GH_OWNER + '/' + REPO_FPC + ' and /' + REPO_LAZARUS);
  TBranchFetchThread.Create(GH_OWNER, REPO_FPC,     @OnUnleashedDone);
  TBranchFetchThread.Create(GH_OWNER, REPO_LAZARUS, @OnLazarusDone);
end;

// On a failed fetch, try the cache file regardless of freshness. A
// stale cache is still better than the single-'main'-item fallback
// FillCombo would otherwise emit when GitHub rate-limits us or the
// network is down. Returns True if the current run produced fresh
// Build a 'name=sha' TStringList from a bare-name list, attaching the
// given SHA only to the 'main' entry. Used by the failed-fetch
// fallback path so a cache-hit's single recorded HEAD-of-main SHA
// still surfaces into FFpcBranchShas / FLazBranchShas, which feeds the
// "uncheck latest auto-fills commit edit" behavior below.
procedure NamesToShaListWithMain(Src, Dest: TStringList; const MainSha: string);
begin
  Dest.Clear;
  for var i := 0 to Src.Count - 1 do
    if SameText(Src[i], 'main') then Dest.Add(Src[i] + '=' + MainSha) else Dest.Add(Src[i] + '=');
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
      Log('FAILED to fetch ' + REPO_FPC + ' branches (' + T.ErrorMsg + '); using stale cache (' + IntToStr(Round(age)) + ' min old)');
      FillCombo(ComboBoxUnleashedBranch, REPO_FPC, fallback, '');
    end else
      FillCombo(ComboBoxUnleashedBranch, REPO_FPC, T.Branches, T.ErrorMsg);
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
      Log('FAILED to fetch ' + REPO_LAZARUS + ' branches (' + T.ErrorMsg + '); using stale cache (' + IntToStr(Round(age)) + ' min old)');
      FillCombo(ComboBoxLazarusBranch, REPO_LAZARUS, fallback, '');
    end else
      FillCombo(ComboBoxLazarusBranch, REPO_LAZARUS, T.Branches, T.ErrorMsg);
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
  // pick the matching SHA map field by repo so caller code stays simple
  var shaMap := if Repo = REPO_FPC then FFpcBranchShas
                else if Repo = REPO_LAZARUS then FLazBranchShas
                else nil;
  if shaMap <> nil then shaMap.Clear;

  Combo.Items.Clear;
  if ErrorMsg <> '' then begin
    Log('FAILED to fetch ' + Repo + ' branches: ' + ErrorMsg);
    Combo.Items.Add('main');
    Combo.ItemIndex := 0;
    Exit;
  end;
  // Branches contains 'name=sha'; Names[i] for combo, Values[name] for SHA
  if shaMap <> nil then shaMap.Assign(Branches);
  for var i := 0 to Branches.Count - 1 do Combo.Items.Add(Branches.Names[i]);

  Log('Got ' + IntToStr(Branches.Count) + ' branches for ' + Repo);
  // Priority: pinned (filename) -> manifest -> main -> master -> first.
  // csDropDownList drops Combo.Text not already in .Items, so this has
  // to run after .Items is populated (fetch is async, can't do it earlier).
  var pinnedBranch: string := '';
  if Combo = ComboBoxUnleashedBranch then begin
    if FPinnedFpcBranchName <> '' then pinnedBranch := FPinnedFpcBranchName
    else if FPinnedFpcBranchHex <> '' then begin
      pinnedBranch := FindBranchByHashPrefix(Combo.Items, FPinnedFpcBranchHex);
      if pinnedBranch <> '' then Log('fpc branch ''' + pinnedBranch + ''' matches hash prefix ''' + FPinnedFpcBranchHex + ''', selecting this branch');
    end;
  end else if Combo = ComboBoxLazarusBranch then begin
    if FPinnedLazBranchName <> '' then pinnedBranch := FPinnedLazBranchName
    else if FPinnedLazBranchHex <> '' then begin
      pinnedBranch := FindBranchByHashPrefix(Combo.Items, FPinnedLazBranchHex);
      if pinnedBranch <> '' then Log('ide branch ''' + pinnedBranch + ''' matches hash prefix ''' + FPinnedLazBranchHex + ''', selecting this branch');
    end;
  end;

  var manifestBranch: string := '';
  var m := ReadManifest(Trim(EditTargetDir.Text));
  if m.Present then manifestBranch := if Combo = ComboBoxUnleashedBranch then m.FpcBranch
                      else if Combo = ComboBoxLazarusBranch then m.LazBranch
                      else '';

  var idx: Integer := -1;
  if pinnedBranch   <> '' then idx := Combo.Items.IndexOf(pinnedBranch);
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
    // Rewrite the on-disk cache only when BOTH fetches succeeded this
    // run. A partial-success run (e.g. rate-limit on one repo) leaves
    // the old file alone so a future startup can still load its stale
    // sections as a fallback rather than treating a half-written cache
    // as authoritative.
    if FFpcFetchOk and FLazFetchOk then begin
      SaveCache(FFpcBranchShas, FLazBranchShas);
      Log('cached branch lists (TTL ' + IntToStr(CACHE_TTL_MINUTES) + ' min, file="' + CacheFilePath + '")');
    end;
    SetStatus('Ready');
    // Defer to the folder-error gate so a bad target dir keeps the
    // Install button off even after the fetches return successfully.
    ButtonInstall.Enabled := not FFolderError;
  end;
end;

procedure TMainForm.ApplyUnleashedEnabled;
begin
  var act := CheckBoxInstallUnleashed.Checked and (not FInstalling);
  ComboBoxUnleashedBranch.Enabled := act and FUnleashedReady;
  CheckBoxUnleashedLatest.Enabled := act;
  EditUnleashedHash.Enabled := act and (not CheckBoxUnleashedLatest.Checked);
  // cross compilers are conceptually nested under fpc-unleashed: no
  // FPC install -> no cross compiler. The host's own native target
  // (x86_64-win64 on Win host / x86_64-linux on Linux host) was
  // locked .Enabled=False at FormCreate -- it's not a cross, just
  // the native install -- and we deliberately don't toggle it here.
  CheckBoxCrossWin32.Enabled   := act;
  CheckBoxCrossWasm.Enabled    := act;
  CheckBoxCrossLinux32.Enabled := act;
{$ifdef MSWINDOWS}
  CheckBoxCrossLinux64.Enabled := act;     // cross direction (win -> linux)
  // CheckBoxCrossWin64 stays disabled (native)
{$endif}
{$ifdef LINUX}
  CheckBoxCrossWin64.Enabled := act;       // cross direction (linux -> win)
  // CheckBoxCrossLinux64 stays disabled (native)
{$endif}
  RefreshTargetState;
end;

procedure TMainForm.ApplyLazarusEnabled;
begin
  var act := CheckBoxInstallLazarus.Checked and (not FInstalling);
  ComboBoxLazarusBranch.Enabled := act and FLazarusReady;
  CheckBoxLazarusLatest.Enabled := act;
  CheckBoxLaunchAfter.Enabled := act;
  EditLazarusHash.Enabled := act and (not CheckBoxLazarusLatest.Checked);
  // addons are nested under the IDE install -- no IDE -> no addons
  CheckBoxMinimap.Enabled := act;
  CheckBoxCPUView.Enabled := act;
  CheckBoxMetaDarkStyle.Enabled := act;
  // Toggle Display Affinity stays locked off on non-Windows hosts; the
  // FormCreate {$ifdef LINUX} block disables it once and we leave it
  // alone here (mirrors the host-native-cross-checkbox pattern above).
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
  // On the checked->unchecked transition, fill the now-enabled commit
  // edit so the user has a sensible starting point.
  //
  // Priority:
  //   1. SHA recorded in installer.ini at the target dir -- pins to the
  //      build the user already has on disk. Unchecking 'latest' on an
  //      existing install should NOT silently stage an update to GitHub
  //      HEAD; we keep the install at what's installed and let the user
  //      edit the hash if they actually want to move forward.
  //   2. HEAD SHA of the selected branch (live fetch / cache).
  //      Fresh-install path: there is no manifest, so 'latest' resolves
  //      to GitHub HEAD and that's the right pre-fill.
  // A live fetch knows the SHA for every branch; on a cache-hit launch
  // only 'main' has a recorded SHA, so other selections leave the edit
  // empty until the user types or refetches.
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
    // Mirror Unleashed: manifest first (keeps install at installed SHA),
    // HEAD second (fresh-install fallback).
    var sha: string := '';
    var m := ReadManifest(Trim(EditTargetDir.Text));
    if m.Present then sha := m.LazSha;
    if (sha = '') and (FLazBranchShas <> nil) and (ComboBoxLazarusBranch.Text <> '') then sha := FLazBranchShas.Values[ComboBoxLazarusBranch.Text];
    if sha <> '' then EditLazarusHash.Text := sha;
  end;
  ApplyLazarusEnabled;
end;

// i386-linux build needs ppcross386 (the i386-win32 cross compiler);
// auto-tick the prereq so the user does not have to remember.
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
  var fullText := FormatDateTime('hh:nn:ss', Now) + '# ' + msg;
  ListBoxLog.Items.Add(fullText);

  // grow the horizontal scrollbar range so wide make/lazbuild lines can
  // be revealed; +24 covers the per-line left padding
  var lineWidth := ListBoxLog.Canvas.TextWidth(fullText) + 24;
  if lineWidth > ListBoxLog.ScrollWidth then ListBoxLog.ScrollWidth := lineWidth;

  // keep the last line visible. Just point TopIndex at the new last
  // item; the LCL setter clamps so the listbox shows as many trailing
  // items as fit. The earlier ClientHeight-div-ItemHeight math broke
  // on GTK2 when ClientHeight returned 0 before first paint (vis=0 ->
  // TopIndex past end -> some old gtk widget versions failed to clamp
  // and the list froze on the first lines).
  ListBoxLog.TopIndex := ListBoxLog.Items.Count - 1;
end;

procedure TMainForm.SetDoubleBufferedRecursive(c: TWinControl);
begin
  c.DoubleBuffered := True;
  for var i := 0 to c.ControlCount - 1 do
    if c.Controls[i] is TWinControl then SetDoubleBufferedRecursive(TWinControl(c.Controls[i]));
end;

procedure TMainForm.CopySelectedLogLines;
begin
  var s := '';
  for var i := 0 to ListBoxLog.Items.Count - 1 do
    if ListBoxLog.Selected[i] then begin
      if s <> '' then s := s + LineEnding;
      s := s + ListBoxLog.Items[i];
    end;
  // fall back to current item if nothing explicitly selected
  if (s = '') and (ListBoxLog.ItemIndex >= 0) then s := ListBoxLog.Items[ListBoxLog.ItemIndex];
  if s <> '' then Clipboard.AsText := s;
end;

procedure TMainForm.ListBoxLogKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // listbox itself eats Ctrl+C otherwise; menu shortcut is also wired
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

// First match wins; ordered most-severe to least so "Error: warning"
// renders red, not olive.
function ColorForLine(const s: string): TColor;
begin
  if (Pos('Error', s) > 0) or (Pos('Fatal', s) > 0) or (Pos('FAILED', s) > 0) or (Pos('failed:', s) > 0) then Result := clRed
  else if Pos('Warning', s) > 0 then Result := clOlive
  else if (Pos('===', s) > 0) or (Pos(' ---', s) > 0) then Result := clNavy
  else if (Pos('Compiling ', s) > 0) or (Pos('Linking ', s) > 0) or (Pos('Installing ', s) > 0) then Result := TColor($008000) // dark green
  else if Pos('make[', s) > 0 then Result := clGray else Result := clWindowText;
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
    // eye-catching banner: bold black text on yellow background
    cv.Brush.Color := clYellow;
    cv.Font.Color := clBlack;
    cv.Font.Style := [fsBold];
  end else begin
    cv.Brush.Color := clWindow;
    cv.Font.Color := ColorForLine(s);
    cv.Font.Style := [];
  end;
  cv.FillRect(ARect);
  cv.TextOut(ARect.Left + 4, ARect.Top, s);
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
  // Folder-error gate wins over the act flag so a finished install that
  // re-enables inputs does not accidentally re-enable Install when the
  // dir is somehow unusable (defensive -- in practice the just-installed
  // dir now carries installer.ini and the gate clears).
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
    SetStatus(IntToStr(Percent) + '%  ' + status);
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
    if FLaunchAfterInstall then LaunchInstalledIde;
  end else begin
    Log('=== INSTALL FAILED: ' + T.ErrorMsg + ' ===');
    SetStatus('Failed: ' + T.ErrorMsg);
    ProgressBar.Position := 0;
  end;
  FInstalling := False;
  SetInputsEnabled(True);
end;

procedure TMainForm.LaunchInstalledIde;
begin
  var ExePath := IncludeTrailingPathDelimiter(FInstallTargetDir) + LazarusBinarySub;
  var PcpArg  := '--pcp=' + IncludeTrailingPathDelimiter(FInstallTargetDir) + 'config_lazarus';
  Log('Launching ' + ExePath);
{$ifdef MSWINDOWS}
  // detached; let the IDE run independently of installer.exe. ShellExecute
  // wants the args quoted as one string ("--pcp=..."); the quotes around
  // the pcp value protect spaces in the target dir.
  var Args := '"' + PcpArg + '"';
  ShellExecute(Handle, 'open', PChar(ExePath), PChar(Args), PChar(ExtractFilePath(ExePath)), SW_SHOWNORMAL);
{$endif}
{$ifdef LINUX}
  // TProcess with poDetached + nothing waiting on Output -> lazarus runs
  // independently of installer (.desktop double-click works the same way
  // when the file is +x).
  var P := TProcess.Create(nil);
  try
    P.Executable := ExePath;
    P.Parameters.Add(PcpArg);
    P.CurrentDirectory := ExtractFilePath(ExePath);
    P.Options := [];                    // not poWaitOnExit
    P.InheritHandles := False;
    P.Execute;
  finally
    // we don't Free here -- once Execute returns, the child is running.
    // Free would not kill the child but would lose our handle to it.
    // The OS reaps it once the installer exits.
    P.Free;
  end;
{$endif}
end;

procedure TMainForm.ButtonInstallClick(Sender: TObject);
var
  cfg: TInstallConfig;
begin
  if FInstalling then Exit;
  // Belt-and-braces: the button is already disabled while FFolderError
  // holds, but a stale OnClick race (or a synthetic click via shortcut)
  // could still land here. Refuse to launch the pipeline against a
  // folder the user has not validated.
  if FFolderError then Exit;

  cfg.TargetDir := Trim(EditTargetDir.Text);
  if cfg.TargetDir = '' then begin
    Log('install dir is empty');
    Exit;
  end;

  cfg.InstallFpc     := CheckBoxInstallUnleashed.Checked;
  cfg.InstallLazarus := CheckBoxInstallLazarus.Checked;
  // cross-compiler choice is meaningless without an FPC install (no
  // ppcx64 to drive the crossinstall make target). force-off here so
  // the pipeline never tries to build a cross against a missing FPC.
  cfg.CrossWin64     := CheckBoxCrossWin64.Checked   and cfg.InstallFpc;
  cfg.CrossWin32     := CheckBoxCrossWin32.Checked   and cfg.InstallFpc;
  cfg.CrossLinux64   := CheckBoxCrossLinux64.Checked and cfg.InstallFpc;
  cfg.CrossLinux32   := CheckBoxCrossLinux32.Checked and cfg.InstallFpc;
  cfg.CrossWasm      := CheckBoxCrossWasm.Checked    and cfg.InstallFpc;
  // Lazarus addons - meaningless without IDE install (lazbuild needs IDE)
  cfg.InstallMinimap       := CheckBoxMinimap.Checked       and cfg.InstallLazarus;
  cfg.InstallCPUView       := CheckBoxCPUView.Checked       and cfg.InstallLazarus;
  cfg.InstallMetaDarkStyle := CheckBoxMetaDarkStyle.Checked and cfg.InstallLazarus;
  // On Linux the checkbox is locked .Enabled=False and .Checked=False
  // at FormCreate, so .Checked is always False here -- no need for an
  // explicit host-ifdef around the assignment.
  cfg.InstallToggleAffinity := CheckBoxToggleAffinity.Checked and cfg.InstallLazarus;
  cfg.LaunchAfter    := CheckBoxLaunchAfter.Checked;

  // snapshot launch decision at install start; user may toggle the
  // checkbox while the install runs, but we honor the original choice
  FLaunchAfterInstall := cfg.InstallLazarus and CheckBoxLaunchAfter.Checked;
  FInstallTargetDir   := cfg.TargetDir;
  cfg.FpcLatest      := CheckBoxUnleashedLatest.Checked;
  cfg.FpcBranch      := ComboBoxUnleashedBranch.Text;
  cfg.FpcHash        := Trim(EditUnleashedHash.Text);
  cfg.LazLatest      := CheckBoxLazarusLatest.Checked;
  cfg.LazBranch      := ComboBoxLazarusBranch.Text;
  cfg.LazHash        := Trim(EditLazarusHash.Text);
  // resolved SHA goes into the manifest so a later run can compare;
  // empty when branch list isn't yet loaded - manifest just stores ''
  cfg.FpcSelectedSha := ResolveSelectedFpcSha;
  cfg.LazSelectedSha := ResolveSelectedLazSha;
  cfg.SaveLog        := CheckBoxSaveLog.Checked;

  Log('--- install requested ---');
  Log('target dir: ' + cfg.TargetDir);
  if cfg.InstallFpc then Log('install fpc-unleashed: yes (' + cfg.FpcBranch + ')') else Log('install fpc-unleashed: no');
  if cfg.InstallLazarus then Log('install lazarus IDE:  yes (' + cfg.LazBranch + ')') else Log('install lazarus IDE:  no');

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

// Cross-platform icon resource. Generated from src/installer.png via
//   tools/lazres.exe src/installer.lrs src/installer.png
// On Windows the .lpi already wires the .ico through the .res file
// for the PE icon directory (so the taskbar icon comes from there),
// so this .lrs is consumed only on Linux where the LCL widgetsets
// (gtk2/qt) need an in-memory image to render Application.Icon /
// Form.Icon at run time. The .lrs file is Pascal source emitting a
// LazarusResources.Add(...) call, so it goes through {\$I} (include)
// in an initialization block, not {\$R} (link as binary resource).
{$ifdef LINUX}
initialization
  {$I installer.lrs}
{$endif}

end.
