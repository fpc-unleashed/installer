{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit main_form;

{$mode unleashed}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Dialogs,
  Graphics, Math, LCLType, Menus, Clipbrd, Windows, ShellApi,
  branch_fetch, install_pipeline, install_manifest;

const
  GH_OWNER     = 'fpc-unleashed';
  REPO_FPC     = 'freepascal';
  REPO_LAZARUS = 'lazarus';

type
  TMainForm = class(TForm)
    GroupBoxUnleashed: TGroupBox;
    CheckBoxInstallUnleashed: TCheckBox;
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
    PanelTarget: TPanel;
    LabelTargetDir: TLabel;
    EditTargetDir: TEdit;
    ButtonBrowse: TButton;
    LabelMode: TLabel;
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
    // manifest; prevents RefreshTargetState (called on every selection
    // change) from clobbering the user's subsequent checkbox toggles
    FCrossSyncedFor: string;
    // raw 'name=sha' lists from branch_fetch; Values[branchName] yields
    // head SHA; both kept to drive update-vs-installed comparisons
    FFpcBranchShas: TStringList;
    FLazBranchShas: TStringList;
    procedure CopySelectedLogLines;
    procedure LaunchInstalledIde;
    procedure RefreshTargetState;
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

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FFpcBranchShas := TStringList.Create;
  FLazBranchShas := TStringList.Create;
  {$ifdef LINUX}
  EditTargetDir.Text := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME'))+'fpcunleashed';
  // host is native linux64; cross-to-linux64 is meaningless. cross-to-win64 starts unchecked (opt-in)
  CheckBoxCrossLinux64.Enabled := False;
  CheckBoxCrossLinux64.Checked := False;
  CheckBoxCrossLinux64.Caption := 'x86_64-linux (host -- native)';
  {$else}
  EditTargetDir.Text := 'C:\fpcunleashed';
  // host is native win64; mirror the logic. cross-to-linux64 also starts unchecked
  CheckBoxCrossWin64.Enabled := False;
  CheckBoxCrossWin64.Checked := False;
  CheckBoxCrossWin64.Caption := 'x86_64-win64 (host -- native)';
  {$endif}
  SetStatus('Ready');
  ApplyUnleashedEnabled;
  ApplyLazarusEnabled;
  RefreshTargetState;
end;

procedure TMainForm.EditTargetDirChange(Sender: TObject);
begin
  RefreshTargetState;
end;

// inspect target dir + manifest to steer the UI; folder is truth for installed state, manifest carries SHAs
procedure TMainForm.RefreshTargetState;
begin
  var dir    := IncludeTrailingPathDelimiter(Trim(EditTargetDir.Text));
  var hasFpc := FileExists(dir+'fpc\bin\x86_64-win64\fpc.exe');
  var hasLaz := FileExists(dir+'lazarus\lazarus.exe');
  var hasW32 := FileExists(dir+'fpc\bin\x86_64-win64\ppcross386.exe');

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
  if hasW32 then begin
    if parts <> '' then parts := parts+' + ';
    parts := parts+'i386-win32';
  end;

  // compare manifest SHAs against current selection; user-typed shorts match as prefix of stored full SHA
  var m := ReadManifest(Trim(EditTargetDir.Text));
  var updates := '';
  if m.Present then begin
    // sync on-disk cross set into the UI once per target dir so a Reinstall doesn't drop user's last picks
    if FCrossSyncedFor <> dir then begin
      FCrossSyncedFor := dir;
      // host-native cross checkboxes are disabled at FormCreate; only sync when actually editable
      if CheckBoxCrossWin64.Enabled   then CheckBoxCrossWin64.Checked   := m.CrossWin64;
      if CheckBoxCrossLinux64.Enabled then CheckBoxCrossLinux64.Checked := m.CrossLinux64;
      CheckBoxCrossWin32.Checked   := m.CrossWin32;
      CheckBoxCrossLinux32.Checked := m.CrossLinux32;
      CheckBoxCrossWasm.Checked    := m.CrossWasm;
      CheckBoxMinimap.Checked      := m.InstallMinimap;
      CheckBoxLaunchAfter.Checked  := m.LaunchAfter;
      // restore last-used branch + hash; empty manifest values -> leave UI alone
      if m.FpcBranch <> '' then begin
        ComboBoxUnleashedBranch.Text := m.FpcBranch;
        EditUnleashedHash.Text       := m.FpcSha;
        CheckBoxUnleashedLatest.Checked := (m.FpcSha = '');
      end;
      if m.LazBranch <> '' then begin
        ComboBoxLazarusBranch.Text   := m.LazBranch;
        EditLazarusHash.Text         := m.LazSha;
        CheckBoxLazarusLatest.Checked := (m.LazSha = '');
      end;
    end;

    var selFpc := ResolveSelectedFpcSha;
    var selLaz := ResolveSelectedLazSha;
    if hasFpc and (selFpc <> '') and (m.FpcSha <> '') and (Pos(selFpc, m.FpcSha) <> 1) and (Pos(m.FpcSha, selFpc) <> 1) then
      updates := updates+' fpc '+Copy(m.FpcSha, 1, 7)+' -> '+Copy(selFpc, 1, 7);
    if hasLaz and (selLaz <> '') and (m.LazSha <> '') and (Pos(selLaz, m.LazSha) <> 1) and (Pos(m.LazSha, selLaz) <> 1) then
      updates := updates+' lazarus '+Copy(m.LazSha, 1, 7)+' -> '+Copy(selLaz, 1, 7);
    // addon + cross deltas; StepRebuildLazarusForAddons handles addons without a full reinstall
    if hasLaz and (CheckBoxMinimap.Checked <> m.InstallMinimap) then updates := updates+(if CheckBoxMinimap.Checked then ' +minimap' else ' -minimap');
    if hasFpc and CheckBoxCrossWin64.Enabled and (CheckBoxCrossWin64.Checked <> m.CrossWin64) then updates := updates+(if CheckBoxCrossWin64.Checked then ' +x86_64-win64' else ' -x86_64-win64');
    if hasFpc and (CheckBoxCrossWin32.Checked <> m.CrossWin32) then updates := updates+(if CheckBoxCrossWin32.Checked then ' +i386-win32' else ' -i386-win32');
    if hasFpc and (CheckBoxCrossLinux64.Checked <> m.CrossLinux64) then updates := updates+(if CheckBoxCrossLinux64.Checked then ' +x86_64-linux' else ' -x86_64-linux');
    if hasFpc and (CheckBoxCrossLinux32.Checked <> m.CrossLinux32) then updates := updates+(if CheckBoxCrossLinux32.Checked then ' +i386-linux' else ' -i386-linux');
    if hasFpc and (CheckBoxCrossWasm.Checked <> m.CrossWasm) then updates := updates+(if CheckBoxCrossWasm.Checked then ' +wasm32-wasip1' else ' -wasm32-wasip1');
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
  // explicit hash override wins, otherwise head SHA of the selected branch as known at last fetch
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
  // wired to combo + hash edit OnChange; keeps the LabelMode 'update available' hint live
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
  // worker threads are FreeOnTerminate=True and call us via OnTerminate; flag blocks touching destroyed widgets
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
  var idx := Combo.Items.IndexOf('main');
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
  // crosses are nested under FPC: no FPC -> no cross
  CheckBoxCrossWin32.Enabled   := act;
  CheckBoxCrossWasm.Enabled    := act;
  CheckBoxCrossLinux64.Enabled := act;
  CheckBoxCrossLinux32.Enabled := act;
  RefreshTargetState;
end;

procedure TMainForm.ApplyLazarusEnabled;
begin
  var act := CheckBoxInstallLazarus.Checked and (not FInstalling);
  ComboBoxLazarusBranch.Enabled := act and FLazarusReady;
  CheckBoxLazarusLatest.Enabled := act;
  CheckBoxLaunchAfter.Enabled := act;
  EditLazarusHash.Enabled := act and (not CheckBoxLazarusLatest.Checked);
  // addons nested under the IDE install
  CheckBoxMinimap.Enabled := act;
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
  // i386-linux needs ppcross386 (i386 codegen + soft-x80, supports -Twin32 and -Tlinux); auto-tick win32
  if CheckBoxCrossLinux32.Checked then CheckBoxCrossWin32.Checked := True;
end;

procedure TMainForm.SetStatus(const msg: string);
begin
  StatusBar.SimpleText := msg;
end;

procedure TMainForm.Log(const msg: string);
begin
  var fullText := FormatDateTime('hh:nn:ss', Now)+'  '+msg;
  ListBoxLog.Items.Add(fullText);

  // grow horizontal scrollbar so wide make/lazbuild lines reveal; +24 covers per-line left padding
  var lineWidth := ListBoxLog.Canvas.TextWidth(fullText)+24;
  if lineWidth > ListBoxLog.ScrollWidth then ListBoxLog.ScrollWidth := lineWidth;

  // keep last line visible: TopIndex is the top-visible row, so subtract visible_lines from count
  if ListBoxLog.ItemHeight > 0 then begin
    var vis := ListBoxLog.ClientHeight div ListBoxLog.ItemHeight;
    ListBoxLog.TopIndex := Max(0, ListBoxLog.Items.Count-vis);
  end;
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
  // listbox eats Ctrl+C otherwise; menu shortcut is also wired
  if (Key = VK_C) and (ssCtrl in Shift) then begin
    CopySelectedLogLines;
    Key := 0;
  end;
end;

procedure TMainForm.MenuCopyClick(Sender: TObject);
begin
  CopySelectedLogLines;
end;

// first match wins; ordered most-severe to least so "Error: warning" renders red, not olive
function ColorForLine(const s: string): TColor;
begin
  if (Pos('Error', s) > 0) or (Pos('Fatal', s) > 0) or (Pos('FAILED', s) > 0) or (Pos('failed:', s) > 0) then Result := clRed
  else if Pos('Warning', s) > 0 then Result := clOlive
  else if (Pos('===', s) > 0) or (Pos(' ---', s) > 0) then Result := clNavy
  else if (Pos('Compiling ', s) > 0) or (Pos('Linking ', s) > 0) or (Pos('Installing ', s) > 0) then Result := TColor($008000)
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
  var ExePath := IncludeTrailingPathDelimiter(FInstallTargetDir)+'lazarus\lazarus.exe';
  var Args    := '--pcp="'+IncludeTrailingPathDelimiter(FInstallTargetDir)+'config_lazarus"';
  Log('Launching '+ExePath);
  // detached; let the IDE run independently of installer.exe
  ShellExecute(Handle, 'open', PChar(ExePath), PChar(Args), PChar(ExtractFilePath(ExePath)), SW_SHOWNORMAL);
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
  // cross requires FPC (ppcx64 drives crossinstall); force-off when FPC is unchecked
  cfg.CrossWin64     := CheckBoxCrossWin64.Checked   and cfg.InstallFpc;
  cfg.CrossWin32     := CheckBoxCrossWin32.Checked   and cfg.InstallFpc;
  cfg.CrossLinux64   := CheckBoxCrossLinux64.Checked and cfg.InstallFpc;
  cfg.CrossLinux32   := CheckBoxCrossLinux32.Checked and cfg.InstallFpc;
  cfg.CrossWasm      := CheckBoxCrossWasm.Checked    and cfg.InstallFpc;
  // Lazarus addons need IDE (lazbuild)
  cfg.InstallMinimap := CheckBoxMinimap.Checked      and cfg.InstallLazarus;
  cfg.LaunchAfter    := CheckBoxLaunchAfter.Checked;

  // snapshot launch decision at install start so a mid-run toggle does not change behaviour
  FLaunchAfterInstall := cfg.InstallLazarus and CheckBoxLaunchAfter.Checked;
  FInstallTargetDir   := cfg.TargetDir;
  cfg.FpcLatest      := CheckBoxUnleashedLatest.Checked;
  cfg.FpcBranch      := ComboBoxUnleashedBranch.Text;
  cfg.FpcHash        := Trim(EditUnleashedHash.Text);
  cfg.LazLatest      := CheckBoxLazarusLatest.Checked;
  cfg.LazBranch      := ComboBoxLazarusBranch.Text;
  cfg.LazHash        := Trim(EditLazarusHash.Text);
  // resolved SHA goes to manifest for later compare; empty when branch list isn't yet loaded
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

end.
