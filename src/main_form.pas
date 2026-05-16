{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit main_form;

{$mode unleashed}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Dialogs,
  Graphics, LCLType, LCLIntf, LResources, Menus, Clipbrd, RegExpr, fileinfo,
  {$ifdef MSWINDOWS} Windows, ShellApi, {$endif}
  {$ifdef LINUX} process, {$endif}
  branch_fetch, install_pipeline, install_manifest;

const
  GH_OWNER     = 'fpc-unleashed';
  REPO_FPC     = 'freepascal';
  REPO_LAZARUS = 'lazarus';

type
  TMainForm = class(TForm)
    GroupBoxTarget: TGroupBox;
    GroupBoxUnleashed: TGroupBox;
    CheckBoxInstallUnleashed: TCheckBox;
    ImageLogo: TImage;
    LabelUnleashedBranch: TLabel;
    ComboBoxUnleashedBranch: TComboBox;
    LabelUnleashedHash: TLabel;
    EditUnleashedHash: TEdit;
    CheckBoxUnleashedLatest: TCheckBox;
    GroupBoxLazarus: TGroupBox;
    CheckBoxInstallLazarus: TCheckBox;
    CheckBoxLaunchAfter: TCheckBox;
    LabelLazarusBranch: TLabel;
    ComboBoxLazarusBranch: TComboBox;
    LabelLazarusHash: TLabel;
    EditLazarusHash: TEdit;
    CheckBoxLazarusLatest: TCheckBox;
    LabelCross: TLabel;
    CheckBoxCrossWin64: TCheckBox;
    CheckBoxCrossWin32: TCheckBox;
    CheckBoxCrossLinux64: TCheckBox;
    CheckBoxCrossLinux32: TCheckBox;
    CheckBoxCrossWasm: TCheckBox;
    LabelLazarusAddons: TLabel;
    CheckBoxMinimap: TCheckBox;
    CheckBoxCPUView: TCheckBox;
    LabelLinkCPUView: TLabel;
    CheckBoxToggleAffinity: TCheckBox;
    PanelTargetContent: TPanel;
    PanelTargetEdit: TPanel;
    EditTargetDir: TEdit;
    ButtonBrowse: TButton;
    LabelMode: TLabel;
    PanelUnleashedBody: TPanel;
    PanelLazarusBody: TPanel;
    SelectDirDialog: TSelectDirectoryDialog;
    PanelButtons: TPanel;
    ProgressBar: TProgressBar;
    CheckBoxSaveLog: TCheckBox;
    ButtonInstall: TButton;
    ButtonClose: TButton;
    ListBoxLog: TListBox;
    PopupMenuLog: TPopupMenu;
    MenuCopy: TMenuItem;
    StatusBar: TStatusBar;
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
    procedure CheckBoxCrossLinux32Change(Sender: TObject);
    procedure LabelLinkCPUViewClick(Sender: TObject);
    procedure OnSelectionChange(Sender: TObject);
    procedure ListBoxLogDrawItem(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
    procedure ListBoxLogKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure MenuCopyClick(Sender: TObject);
  private
    FFetchPending: Integer;
    FUnleashedReady, FLazarusReady: Boolean;
    FShowFired: Boolean;
    FShuttingDown: Boolean;
    FInstalling: Boolean;
    FLaunchAfterInstall: Boolean;
    FInstallTargetDir: string;
    // last target dir for which the cross checkboxes were synced from the
    // manifest; prevents RefreshTargetState (called on every selection change)
    // from clobbering the user's subsequent checkbox toggles
    FCrossSyncedFor: string;
    // raw 'name=sha' lists from branch_fetch; Values[branchName] yields head
    // SHA; both kept to drive update-vs-installed comparisons
    FFpcBranchShas: TStringList;
    FLazBranchShas: TStringList;
    procedure CopySelectedLogLines;
    procedure LaunchInstalledIde;
    procedure RefreshTargetState;
    procedure ApplyHashesFromBinaryName;
    function ResolveSelectedFpcSha: string;
    function ResolveSelectedLazSha: string;
    procedure StartBranchFetch;
    procedure OnUnleashedDone(Sender: TObject);
    procedure OnLazarusDone(Sender: TObject);
    procedure FillCombo(Combo: TComboBox; T: TBranchFetchThread);
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

// Filesystem is authoritative for what's installed; the manifest only records
// intent (a crashed install leaves no manifest). Linux scans for the version
// dir under fpc/lib/fpc/ since fpc-unleashed reports 3.3.1+ vs the 3.2.2 bootstrap.
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

// Tag the form's title bar with the version string baked into the exe's
// VERSIONINFO resource plus the wall-clock moment the binary was compiled.
// {$I %DATE%}/{$I %TIME%} are expanded by the FPC preprocessor at compile time.
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

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FFpcBranchShas := TStringList.Create;
  FLazBranchShas := TStringList.Create;

  // On Linux the icon embedded via the .res from .lpi does not reach
  // Application.Icon (LCL gtk2/qt do not consume the PE icon group), so the
  // same PNG is embedded as a Lazarus resource and loaded here at runtime.
  // Windows already has the .ico-multi-size icon via the PE resource.
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
  if Ver <> '' then Caption := Caption+' v'+Ver;
  Caption := Caption+' (built at '+BuildDate+' '+BuildTime+')';
  // Set the cross checkbox defaults BEFORE assigning EditTargetDir.Text.
  // Setting .Text fires EditTargetDirChange -> RefreshTargetState, and that
  // handler does a filesystem probe to set the cross-checkbox state to match
  // what's actually installed (sets FCrossSyncedFor). If we override the
  // checkbox defaults AFTER that runs, the explicit RefreshTargetState below
  // sees FCrossSyncedFor already set, skips the re-sync, and the overrides
  // win -- producing "checkbox shows ticked even though nothing's installed".
  {$ifdef LINUX}
  // host is x86_64-linux; native build covers it, so "cross to linux64" is
  // meaningless. The cross-to-win64 checkbox is left unchecked at startup --
  // user opts in deliberately so we don't surprise them with cross-toolchain downloads.
  CheckBoxCrossLinux64.Enabled := False;
  CheckBoxCrossLinux64.Checked := False;
  CheckBoxCrossLinux64.Caption := 'x86_64-linux (native)';
  EditTargetDir.Text := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME'))+'fpcunleashed';
  // Toggle Display Affinity uses Windows-only user32 API (Set/GetWindowDisplayAffinity).
  // The package compiles on Linux (its Register is {$ifdef WINDOWS}) but
  // installing it would be a no-op, so the checkbox is locked off here to
  // make the platform restriction obvious. Stays disabled across ApplyLazarusEnabled calls.
  CheckBoxToggleAffinity.Enabled := False;
  CheckBoxToggleAffinity.Checked := False;
  {$else}
  // host is x86_64-win64; mirror the logic for the other direction. Cross-to-linux64 also starts unchecked.
  CheckBoxCrossWin64.Enabled := False;
  CheckBoxCrossWin64.Checked := False;
  CheckBoxCrossWin64.Caption := 'x86_64-win64 (native)';
  EditTargetDir.Text := 'C:\fpcunleashed';
  {$endif}
  SetStatus('Ready');
  ApplyUnleashedEnabled;
  ApplyLazarusEnabled;
  RefreshTargetState;
  ApplyHashesFromBinaryName;
end;

// Release binaries are named so they carry a pinned (fpc, lazarus) commit pair
// in the filename, e.g.:
//   installer-abc1234-def5678.exe
//   installer-v1.0-abc1234-def5678.exe
//   unleashed-installer_abc1234_def5678.bin
// Two short SHAs extracted with a single regex: each hash is 7-12 hex chars,
// flanked by a non-hex delimiter, bounded by either non-hex or string edge
// so an unrelated longer hex run can't accidentally match.
//
// On hit: fills the two commit edits, unticks both 'latest' checkboxes, and
// re-runs RefreshTargetState so LabelMode reflects the new pinned values.
procedure TMainForm.ApplyHashesFromBinaryName;
const
  // (?<![0-9a-fA-F]) ensures we don't bite into a longer hex run before the
  // first hash; (?![0-9a-fA-F]) does the same after the second one.
  HASH_PATTERN = '(?<![0-9a-fA-F])([0-9a-fA-F]{7,12})[^0-9a-fA-F]+([0-9a-fA-F]{7,12})(?![0-9a-fA-F])';
begin
  var Name := ExtractFileName(ParamStr(0));
  var R := autofree TRegExpr.Create;
  R.Expression := HASH_PATTERN;
  if not R.Exec(Name) then Exit;

  var FpcHash := LowerCase(R.&Match[1]);
  var LazHash := LowerCase(R.&Match[2]);
  Log('binary name carries pinned hashes: fpc='+FpcHash+' lazarus='+LazHash);
  EditUnleashedHash.Text       := FpcHash;
  CheckBoxUnleashedLatest.Checked := False;
  EditLazarusHash.Text         := LazHash;
  CheckBoxLazarusLatest.Checked := False;
  // RefreshTargetState already ran during FormCreate using manifest-restored
  // hashes; rerun so LabelMode reflects the new pinned values (e.g. switches
  // to 'Update available: fpc abc1234 -> def5678' when the binary points at a
  // newer commit than what's installed). FCrossSyncedFor stops it re-running
  // the manifest checkbox sync this time.
  RefreshTargetState;
end;

procedure TMainForm.EditTargetDirChange(Sender: TObject);
begin
  RefreshTargetState;
end;

// inspect what is sitting in the chosen target directory and steer the UI
// accordingly. folder inspection is the source of truth for what's installed;
// the manifest file (installer.ini, written by the pipeline at end of install)
// carries the build's commit SHA so we can flag '(update available)' when the
// user has selected a newer commit.
procedure TMainForm.RefreshTargetState;
begin
  var dir    := IncludeTrailingPathDelimiter(Trim(EditTargetDir.Text));
  var hasFpc := FileExists(dir+HostFpcWrapperSub);
  var hasLaz := FileExists(dir+LazarusBinarySub);

  if not (hasFpc or hasLaz) then begin
    LabelMode.Caption := 'New installation';
    ButtonInstall.Caption := 'Install';
    Exit;
  end;

  var parts := '';
  if hasFpc then parts := 'fpc';
  if hasLaz then begin
    if parts <> '' then parts := parts+' + ';
    parts := parts+'lazarus';
  end;
  // List every target compiler the user can pick, native first. Native shares
  // the units/ layout with crosses so ProbeCrossInstalled picks it up
  // naturally; listing it explicitly makes the label match the full set of
  // cross checkboxes (otherwise users wonder why the "what's installed"
  // summary omits the host platform).
  {$ifdef MSWINDOWS}
  var crossTargets: TStringArray := ['x86_64-win64', 'x86_64-linux', 'i386-win32', 'i386-linux', 'wasm32-wasip1'];
  {$endif}
  {$ifdef LINUX}
  var crossTargets: TStringArray := ['x86_64-linux', 'x86_64-win64', 'i386-win32', 'i386-linux', 'wasm32-wasip1'];
  {$endif}
  for var t in crossTargets do
    if ProbeCrossInstalled(Trim(EditTargetDir.Text), t) then begin
      if parts <> '' then parts := parts+' + ';
      parts := parts+t;
    end;

  // pull last-installed SHAs from manifest (if present) and compare to
  // currently-selected SHAs to decide whether to flag an update. user-typed
  // short hashes are matched as a prefix of the manifest's full SHA in either
  // direction (typed-short vs stored-full).
  var m := ReadManifest(Trim(EditTargetDir.Text));
  var updates := '';
  // Sync the checkbox state with what's ACTUALLY on disk when we're pointed
  // at an existing install. Filesystem is the authoritative truth (a
  // half-completed prior install may never have written the manifest);
  // manifest is used for branch/sha/addon restoration only. Sync once per
  // target dir so subsequent RefreshTargetState calls (combo change, etc.)
  // leave the user's own checkbox edits alone.
  if hasFpc and (FCrossSyncedFor <> dir) then begin
    FCrossSyncedFor := dir;
    var rawDir := Trim(EditTargetDir.Text);
    // CheckBoxCross{Win64,Linux64} only get synced on the host where they
    // are not the native target -- on the other host they are disabled at FormCreate.
    if CheckBoxCrossWin64.Enabled   then CheckBoxCrossWin64.Checked   := ProbeCrossInstalled(rawDir, 'x86_64-win64');
    if CheckBoxCrossLinux64.Enabled then CheckBoxCrossLinux64.Checked := ProbeCrossInstalled(rawDir, 'x86_64-linux');
    CheckBoxCrossWin32.Checked   := ProbeCrossInstalled(rawDir, 'i386-win32');
    CheckBoxCrossLinux32.Checked := ProbeCrossInstalled(rawDir, 'i386-linux');
    CheckBoxCrossWasm.Checked    := ProbeCrossInstalled(rawDir, 'wasm32-wasip1');
    // Restore last-used non-filesystem-detectable selections (branch, commit
    // hash, addon ticks, launch-after) from the manifest. These don't have a
    // filesystem fingerprint so manifest is the only source.
    if m.Present then begin
      CheckBoxMinimap.Checked      := m.InstallMinimap;
      CheckBoxCPUView.Checked      := m.InstallCPUView;
      // Only restore the Windows-only addon ticks on hosts where the checkbox
      // is interactable. On Linux the checkbox is locked .Enabled=False at
      // FormCreate; flipping its .Checked from a Windows-written manifest
      // would just confuse the user.
      if CheckBoxToggleAffinity.Enabled then CheckBoxToggleAffinity.Checked := m.InstallToggleAffinity;
      CheckBoxLaunchAfter.Checked  := m.LaunchAfter;
      if m.FpcBranch <> '' then begin
        ComboBoxUnleashedBranch.Text := m.FpcBranch;
        // Always show the last installed SHA in the hash field, even when
        // latest was selected -- user can see what commit they're currently
        // on. The hash field stays disabled when latest is ticked (existing
        // UI behavior) so it's display-only in that case. Restore
        // CheckBoxLatest from the explicit manifest flag rather than
        // guessing from an empty SHA: latest=yes still records a resolved
        // SHA in FpcSha for display purposes.
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
      updates := updates+' fpc '+Copy(m.FpcSha, 1, 7)+' -> '+Copy(selFpc, 1, 7);
    if hasLaz and (selLaz <> '') and (m.LazSha <> '') and (Pos(selLaz, m.LazSha) <> 1) and (Pos(m.LazSha, selLaz) <> 1) then
      updates := updates+' lazarus '+Copy(m.LazSha, 1, 7)+' -> '+Copy(selLaz, 1, 7);
    // addon deltas. Pipeline's StepRebuildLazarusForAddons handles these
    // without a full reinstall, but the user needs visual cues so the
    // Install/Reinstall button labels reflect reality.
    if hasLaz and (CheckBoxMinimap.Checked <> m.InstallMinimap) then
      updates := updates+(if CheckBoxMinimap.Checked then ' +minimap' else ' -minimap');
    if hasLaz and (CheckBoxCPUView.Checked <> m.InstallCPUView) then
      updates := updates+(if CheckBoxCPUView.Checked then ' +cpuview' else ' -cpuview');
    // Same .Enabled guard as the manifest restore above: on Linux the delta
    // is meaningless because the user can't change the toggle.
    if hasLaz and CheckBoxToggleAffinity.Enabled and (CheckBoxToggleAffinity.Checked <> m.InstallToggleAffinity) then
      updates := updates+(if CheckBoxToggleAffinity.Checked then ' +toggle-affinity' else ' -toggle-affinity');
    if hasFpc and CheckBoxCrossWin64.Enabled and (CheckBoxCrossWin64.Checked <> m.CrossWin64) then
      updates := updates+(if CheckBoxCrossWin64.Checked then ' +x86_64-win64' else ' -x86_64-win64');
    if hasFpc and (CheckBoxCrossWin32.Checked <> m.CrossWin32) then
      updates := updates+(if CheckBoxCrossWin32.Checked then ' +i386-win32' else ' -i386-win32');
    if hasFpc and (CheckBoxCrossLinux64.Checked <> m.CrossLinux64) then
      updates := updates+(if CheckBoxCrossLinux64.Checked then ' +x86_64-linux' else ' -x86_64-linux');
    if hasFpc and (CheckBoxCrossLinux32.Checked <> m.CrossLinux32) then
      updates := updates+(if CheckBoxCrossLinux32.Checked then ' +i386-linux' else ' -i386-linux');
    if hasFpc and (CheckBoxCrossWasm.Checked <> m.CrossWasm) then
      updates := updates+(if CheckBoxCrossWasm.Checked then ' +wasm32-wasip1' else ' -wasm32-wasip1');
  end;

  if updates <> '' then begin
    LabelMode.Caption := 'Update available:'+updates;
    ButtonInstall.Caption := 'Update';
  end else begin
    LabelMode.Caption := 'Existing install detected ('+parts+') - Install will overwrite';
    ButtonInstall.Caption := 'Reinstall';
  end;
end;

function TMainForm.ResolveSelectedFpcSha: string;
begin
  // explicit hash override wins, otherwise use the head SHA of the
  // currently-selected branch as known at the last fetch
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
  // wired to combo + hash edit OnChange events; keeps LabelMode's '(update
  // available)' hint live as the user picks a different branch or types a
  // different commit.
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
begin
  SetStatus('Updating branches list...');
  Log('Fetching branches from github.com/'+GH_OWNER+'/'+REPO_FPC+' and /'+REPO_LAZARUS);
  FFetchPending := 2;
  ButtonInstall.Enabled := False;
  TBranchFetchThread.Create(GH_OWNER, REPO_FPC, @OnUnleashedDone);
  TBranchFetchThread.Create(GH_OWNER, REPO_LAZARUS, @OnLazarusDone);
end;

procedure TMainForm.OnUnleashedDone(Sender: TObject);
begin
  if FShuttingDown then Exit;
  FillCombo(ComboBoxUnleashedBranch, TBranchFetchThread(Sender));
  FUnleashedReady := True;
  ApplyUnleashedEnabled;
  FetchTick;
end;

procedure TMainForm.OnLazarusDone(Sender: TObject);
begin
  if FShuttingDown then Exit;
  FillCombo(ComboBoxLazarusBranch, TBranchFetchThread(Sender));
  FLazarusReady := True;
  ApplyLazarusEnabled;
  FetchTick;
end;

procedure TMainForm.FillCombo(Combo: TComboBox; T: TBranchFetchThread);
begin
  // pick the matching SHA map field by repo so caller code stays simple
  var shaMap := if T.Repo = REPO_FPC then FFpcBranchShas
                else if T.Repo = REPO_LAZARUS then FLazBranchShas
                else nil;
  if shaMap <> nil then shaMap.Clear;

  Combo.Items.Clear;
  if T.ErrorMsg <> '' then begin
    Log('FAILED to fetch '+T.Repo+' branches: '+T.ErrorMsg);
    Combo.Items.Add('main');
    Combo.ItemIndex := 0;
    Exit;
  end;
  // T.Branches contains 'name=sha'; Names[i] for combo, Values[name] for SHA
  if shaMap <> nil then shaMap.Assign(T.Branches);
  for var i := 0 to T.Branches.Count-1 do Combo.Items.Add(T.Branches.Names[i]);

  Log('Got '+IntToStr(T.Branches.Count)+' branches for '+T.Repo);
  // prefer the manifest-stored branch if it survived to the new list. The
  // earlier RefreshTargetState (in FormCreate) tried to set Combo.Text to the
  // saved branch, but csDropDownList drops anything not already in .Items --
  // and .Items was still empty because the fetch is async.
  var manifestBranch: string := '';
  var m := ReadManifest(Trim(EditTargetDir.Text));
  if m.Present then
    manifestBranch := if Combo = ComboBoxUnleashedBranch then m.FpcBranch
                      else if Combo = ComboBoxLazarusBranch then m.LazBranch
                      else '';

  var idx := if manifestBranch <> '' then Combo.Items.IndexOf(manifestBranch) else -1;
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
    SetStatus('Ready');
    ButtonInstall.Enabled := True;
  end;
end;

procedure TMainForm.ApplyUnleashedEnabled;
begin
  var act := CheckBoxInstallUnleashed.Checked and (not FInstalling);
  ComboBoxUnleashedBranch.Enabled := act and FUnleashedReady;
  CheckBoxUnleashedLatest.Enabled := act;
  EditUnleashedHash.Enabled := act and (not CheckBoxUnleashedLatest.Checked);
  // cross compilers are conceptually nested under fpc-unleashed: no FPC install
  // -> no cross compiler. The host's own native target (x86_64-win64 on Win
  // host / x86_64-linux on Linux host) was locked .Enabled=False at FormCreate
  // -- it's not a cross, just the native install -- and we deliberately don't toggle it here.
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
  // Toggle Display Affinity stays locked off on non-Windows hosts; the
  // FormCreate {$ifdef LINUX} block disables it once and we leave it alone here.
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
  ApplyUnleashedEnabled;
end;

procedure TMainForm.CheckBoxLazarusLatestChange(Sender: TObject);
begin
  ApplyLazarusEnabled;
end;

procedure TMainForm.CheckBoxCrossLinux32Change(Sender: TObject);
begin
  // i386-linux is built using the i386-win32 cross compiler (ppcross386, an
  // i386-CPU binary with soft-x80 baked in -- supports both -Twin32 and
  // -Tlinux). Auto-tick win32 so the user does not have to remember the prerequisite.
  if CheckBoxCrossLinux32.Checked then CheckBoxCrossWin32.Checked := True;
end;

procedure TMainForm.LabelLinkCPUViewClick(Sender: TObject);
begin
  OpenURL('https://github.com/AlexanderBagel/CPUView');
end;

procedure TMainForm.SetStatus(const msg: string);
begin
  StatusBar.SimpleText := msg;
end;

procedure TMainForm.Log(const msg: string);
begin
  var fullText := FormatDateTime('hh:nn:ss', Now)+'  '+msg;
  ListBoxLog.Items.Add(fullText);

  // grow the horizontal scrollbar range so wide make/lazbuild lines can be
  // revealed; +24 covers the per-line left padding
  var lineWidth := ListBoxLog.Canvas.TextWidth(fullText)+24;
  if lineWidth > ListBoxLog.ScrollWidth then ListBoxLog.ScrollWidth := lineWidth;

  // keep the last line visible. Just point TopIndex at the new last item; the
  // LCL setter clamps so the listbox shows as many trailing items as fit. The
  // earlier ClientHeight-div-ItemHeight math broke on GTK2 when ClientHeight
  // returned 0 before first paint (vis=0 -> TopIndex past end -> some old
  // gtk widget versions failed to clamp and the list froze on the first lines).
  ListBoxLog.TopIndex := ListBoxLog.Items.Count-1;
end;

procedure TMainForm.CopySelectedLogLines;
begin
  var s := '';
  for var i := 0 to ListBoxLog.Items.Count-1 do
    if ListBoxLog.Selected[i] then begin
      if s <> '' then s := s+LineEnding;
      s := s+ListBoxLog.Items[i];
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

// First match wins; ordered most-severe to least so "Error: warning" renders red, not olive.
function ColorForLine(const s: string): TColor;
begin
  if (Pos('Error', s) > 0) or (Pos('Fatal', s) > 0) or (Pos('FAILED', s) > 0) or (Pos('failed:', s) > 0) then Result := clRed
  else if Pos('Warning', s) > 0 then Result := clOlive
  else if (Pos('===', s) > 0) or (Pos(' ---', s) > 0) then Result := clNavy
  else if (Pos('Compiling ', s) > 0) or (Pos('Linking ', s) > 0) or (Pos('Installing ', s) > 0) then Result := TColor($008000)   // dark green
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
  ButtonInstall.Enabled := act;
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
    if FLaunchAfterInstall then LaunchInstalledIde;
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
  // detached; let the IDE run independently of installer.exe. ShellExecute
  // wants the args quoted as one string ("--pcp=..."); the quotes around the
  // pcp value protect spaces in the target dir.
  var Args := '"'+PcpArg+'"';
  ShellExecute(Handle, 'open', PChar(ExePath), PChar(Args), PChar(ExtractFilePath(ExePath)), SW_SHOWNORMAL);
{$endif}
{$ifdef LINUX}
  // TProcess with poDetached + nothing waiting on Output -> lazarus runs
  // independently of installer (.desktop double-click works the same way when
  // the file is +x).
  var P := TProcess.Create(nil);
  try
    P.Executable := ExePath;
    P.Parameters.Add(PcpArg);
    P.CurrentDirectory := ExtractFilePath(ExePath);
    P.Options := [];                    // not poWaitOnExit
    P.InheritHandles := False;
    P.Execute;
  finally
    // we don't Free here -- once Execute returns, the child is running. Free
    // would not kill the child but would lose our handle to it. The OS reaps
    // it once the installer exits.
    P.Free;
  end;
{$endif}
end;

procedure TMainForm.ButtonInstallClick(Sender: TObject);
var
  cfg: TInstallConfig;
begin
  if FInstalling then Exit;

  cfg.TargetDir := Trim(EditTargetDir.Text);
  if cfg.TargetDir = '' then begin
    Log('install dir is empty');
    Exit;
  end;

  cfg.InstallFpc     := CheckBoxInstallUnleashed.Checked;
  cfg.InstallLazarus := CheckBoxInstallLazarus.Checked;
  // cross-compiler choice is meaningless without an FPC install (no ppcx64 to
  // drive the crossinstall make target). force-off so the pipeline never tries
  // to build a cross against a missing FPC.
  cfg.CrossWin64     := CheckBoxCrossWin64.Checked   and cfg.InstallFpc;
  cfg.CrossWin32     := CheckBoxCrossWin32.Checked   and cfg.InstallFpc;
  cfg.CrossLinux64   := CheckBoxCrossLinux64.Checked and cfg.InstallFpc;
  cfg.CrossLinux32   := CheckBoxCrossLinux32.Checked and cfg.InstallFpc;
  cfg.CrossWasm      := CheckBoxCrossWasm.Checked    and cfg.InstallFpc;
  // Lazarus addons - meaningless without IDE install (lazbuild needs IDE)
  cfg.InstallMinimap := CheckBoxMinimap.Checked      and cfg.InstallLazarus;
  cfg.InstallCPUView := CheckBoxCPUView.Checked      and cfg.InstallLazarus;
  // On Linux the checkbox is locked .Enabled=False and .Checked=False at
  // FormCreate, so .Checked is always False here -- no host-ifdef needed.
  cfg.InstallToggleAffinity := CheckBoxToggleAffinity.Checked and cfg.InstallLazarus;
  cfg.LaunchAfter    := CheckBoxLaunchAfter.Checked;

  // snapshot launch decision at install start; user may toggle the checkbox
  // while the install runs, but we honor the original choice
  FLaunchAfterInstall := cfg.InstallLazarus and CheckBoxLaunchAfter.Checked;
  FInstallTargetDir   := cfg.TargetDir;
  cfg.FpcLatest      := CheckBoxUnleashedLatest.Checked;
  cfg.FpcBranch      := ComboBoxUnleashedBranch.Text;
  cfg.FpcHash        := Trim(EditUnleashedHash.Text);
  cfg.LazLatest      := CheckBoxLazarusLatest.Checked;
  cfg.LazBranch      := ComboBoxLazarusBranch.Text;
  cfg.LazHash        := Trim(EditLazarusHash.Text);
  // resolved SHA goes into the manifest so a later run can compare; empty
  // when branch list isn't yet loaded - manifest just stores ''
  cfg.FpcSelectedSha := ResolveSelectedFpcSha;
  cfg.LazSelectedSha := ResolveSelectedLazSha;
  cfg.SaveLog        := CheckBoxSaveLog.Checked;

  Log('--- install requested ---');
  Log('target dir: '+cfg.TargetDir);
  if cfg.InstallFpc then Log('install fpc-unleashed: yes ('+cfg.FpcBranch+')')
  else Log('install fpc-unleashed: no');
  if cfg.InstallLazarus then Log('install lazarus IDE:  yes ('+cfg.LazBranch+')')
  else Log('install lazarus IDE:  no');

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
// On Windows the .lpi already wires the .ico through the .res file for the PE
// icon directory (so the taskbar icon comes from there), so this .lrs is
// consumed only on Linux where the LCL widgetsets (gtk2/qt) need an in-memory
// image to render Application.Icon / Form.Icon at run time. The .lrs file is
// Pascal source emitting a LazarusResources.Add(...) call, so it goes through
// {\$I} (include) in an initialization block, not {\$R} (link as binary resource).
{$ifdef LINUX}
initialization
  {$I installer.lrs}
{$endif}

end.
