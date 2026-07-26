{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit main_form;

{$mode unleashed}

// the window is a single HTML view drawn by pixie, so this unit keeps the state
// the user is editing, talks to the install pipeline, and hands the state to
// ui_page whenever the page has to be drawn again.

interface

uses
  Classes, SysUtils, Types, Math, Forms, Controls, Dialogs, Graphics, LCLType, LCLIntf, Clipbrd, ExtCtrls, RegExpr, fileinfo,
  Pixie.HtmlView, Pixie.HtmlTag, Pixie.ElTextInput, Pixie.Document, Pixie.Element, Pixie.RenderItem, Pixie.Types, Generics.Collections,
  {$ifdef WINDOWS} Windows, ShellApi, Registry, {$endif}
  {$ifdef LINUX} process, {$endif}
  {$ifdef LCLGTK2} ctypes, gtk2, gdk2, gdk2x, x, xlib, {$endif}
  branch_fetch, branch_cache, install_pipeline, install_manifest, hash_branch, app_settings, ui_page;

const
  // the dropdowns of the menu bar, in the order they are drawn
  MENU_DROPS: array[3] of string = ('file', 'repo', 'help');

  GH_OWNER     = 'fpc-unleashed';
  REPO_FPC     = 'freepascal';
  REPO_LAZARUS = 'lazarus';

type
  TMainForm = class(TForm)
    SelectDirDialog: TSelectDirectoryDialog;
    view: TPixieHtmlView;
    logTimer: TTimer;
    liveTimer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    function viewElementClick(Sender: TObject; El: TObject): Boolean;
    procedure viewAfterPaint(Sender: TObject);
    procedure viewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure viewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure viewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure logTimerTimer(Sender: TObject);
    procedure liveTimerTimer(Sender: TObject);
  private
    st: TUiState;
    FLog: TStringList;
    // what an install has changed since the last live update
    FLogDirty: Boolean;
    FStatusDirty: Boolean;
    FRenderQueued: Boolean;
    // the log pane scrolls on its own and is followed until the user scrolls
    // away from its end; the window itself never scrolls
    FFollowLog: Boolean;
    FLogTop: Double;
    FLogRebuilt: Boolean;
    // a live-update worker is building strings; the next one waits its turn
    FLiveBusy: Boolean;
    FHoverDirty: Boolean;
    // defaults a fresh target dir starts from, built in and then overwritten
    // by installer_settings.ini
    FPrefs: TAppSettings;
    // a commit the binary name pins is not a preference and cannot be reset
    FPinnedHashes: Boolean;
    // where the pointer is, in client pixels; -1 when it is outside the window
    FMouseX, FMouseY: Integer;
    FMouseDown: Boolean;
    // no settings file yet: the window takes its height from what it holds
    FSizeToContent: Boolean;
    FFetchPending: Integer;
    FShowFired: Boolean;
    FInstalling: Boolean;
    FClosing: Boolean;
    // snapshot of cfg.InstallLazarus from current install run; combined with
    // the live launch-after box at OnInstallComplete to decide launch
    FInstalledLazarus: Boolean;
    FInstallTargetDir: string;
    FLaunchAfter: Boolean;
    // native target of this host cannot be cross-built and stays locked
    FCrossWin64, FCrossWin32, FCrossLinux64, FCrossLinux32, FCrossWasm: Boolean;
    FNativeWin64, FNativeLinux64: Boolean;
    FMinimap, FCpuView, FMetaDark, FHelpFiles, FToggleAffinity: Boolean;
    FDesktopShortcut, FFolderShortcut: Boolean;
    // last target dir for which cross checkboxes were synced; prevents refreshTarget clobbering toggles
    FCrossSyncedFor: string;
    // gate for state-B reset so a re-entry from a checkbox toggle won't clobber the just-made change
    FLastState: Char;
    FLastStateDir: string;
    // raw 'name=sha' lists from branch_fetch; Values[branch] yields head SHA
    FFpcBranchShas: TStringList;
    FLazBranchShas: TStringList;
    // pin hints from filename; one of *Name (predefined) / *HashHex (murmur3 prefix) per repo
    FPinnedFpcBranchName: string;
    FPinnedFpcBranchHex:  string;
    FPinnedLazBranchName: string;
    FPinnedLazBranchHex:  string;
    // cache file is rewritten only when BOTH fetches succeed
    FFpcFetchOk: Boolean;
    FLazFetchOk: Boolean;
    // True while target dir is unusable (blank or non-empty w/o installer.ini)
    FFolderError: Boolean;
    // True when IDE install is on but neither shortcut picked
    FShortcutError: Boolean;
    // re-entrancy guard for refreshTarget
    FRefreshingTarget: Boolean;
    procedure runAct(const act: string; el: TPixieHtmlTag);
    procedure captureInputs;
    function focusIsTextBox: Boolean;
    procedure note(const title, text: string);
    procedure confirm(const title, text, okAct, okLabel: string);
    procedure showAbout;
    procedure launchInstalledIde;
    procedure refreshTarget;
    procedure updateShortcutError;
    procedure resetTargetToDefaults;
    function applyStoredSettings: Boolean;
    procedure storeSettings;
    procedure applyHashesFromBinaryName;
    function resolveSelectedFpcSha: string;
    function resolveSelectedLazSha: string;
    procedure startBranchFetch;
    procedure onUnleashedDone(Sender: TObject);
    procedure onLazarusDone(Sender: TObject);
    procedure fillBranches(fpc: Boolean; branches: TStringList; const errorMsg: string);
    procedure fetchTick;
    procedure startInstall;
    procedure setInputsEnabled(act: Boolean);
    procedure onInstallLog(const msg: string);
    procedure onInstallProgress(percent: Integer; const status: string);
    procedure onInstallComplete(Sender: TObject);
    procedure setStatus(const msg: string);
    procedure log(const msg: string);
    procedure applyWindowTheme;
    procedure restoreHover;
    function menuUnderPoint(x, y: Integer): string;
    function logItem: TPixieRenderItem;
    procedure restoreLogScroll;
    procedure noticeLogScroll;
    procedure settleDocument(layoutWidth: Double);
    procedure buildChecks;
    procedure queueRender;
    procedure asyncRender(data: PtrInt);
    procedure render;
    procedure renderLive(withLog: Boolean);
    procedure applyLive(const linesHtml, statusText: string; percent: integer; withLog: Boolean);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

function isMenuDrop(const name: string): Boolean;
begin
  result := False;
  for var m in MENU_DROPS do
    if m = name then exit(True);
end;

{$ifdef LINUX}
// Windows takes the icon from the PE .ico via the project .res; gtk2/qt LCL ignores that
// and needs an in-memory image, so the PNG is baked into the binary here
{$embedbytes INSTALLER_PNG 'installer.png'}
{$endif}

var
  // set in FormDestroy; FreeOnTerminate-thread callbacks queued via Synchronize can fire after the
  // form is freed, so they gate on this global; a form field there would be read from freed memory
  GShuttingDown: Boolean = False;

const
  // mirror install_pipeline's per-OS host paths so refreshTarget/launchInstalledIde see the same files
{$ifdef WINDOWS}
  HostFpcWrapperSub  = 'fpc\bin\x86_64-win64\fpc.exe';
  LazarusBinarySub   = 'lazarus\lazarus.exe';
{$endif}
{$ifdef LINUX}
  HostFpcWrapperSub  = 'fpc/bin/fpc';
  LazarusBinarySub   = 'lazarus/lazarus';
{$endif}

  LAUNCH_WARN_MSG = 'Tick at least one IDE shortcut above. A shortcut is the only correct way to launch the IDE; the raw binary skips --pcp and breaks the config.';

  // Keep in sync with installer/LICENSE.
  LICENSE_TEXT =
    '''
    Unleashed Installer License

    Copyright (c) 2026 fpc-unleashed.

    This software is the official installer for the fpc-unleashed
    project (https://github.com/fpc-unleashed). The source is published
    so users can audit what the installer does.

    YOU MAY, FREE OF CHARGE:
      1. Run the installer binary released by fpc-unleashed, or build
         it yourself from this source.
      2. Read this source code for understanding or auditing.

    YOU MAY NOT, WITHOUT WRITTEN PERMISSION FROM fpc-unleashed:
      1. Copy, modify, merge, redistribute, or sublicense any part of
         the source or binary - in original or modified form.
      2. Create forks, branches, ports, or derivative works, even if
         URLs, names, configuration, or branding are changed. This
         installer is the fpc-unleashed installer; it is not licensed
         for use by any other project, including forks of fpc-unleashed
         itself.
      3. Use the names "Unleashed", "FPC Unleashed", or any
         confusingly similar name in derived works, packaging, or marketing materials.

    There is no permitted fork.

    THIRD-PARTY COMPONENTS

    The installer binary statically links the FPC Runtime Library and the
    Lazarus Component Library, both distributed under the Modified LGPL with
    linking exception. Those licenses apply only to those components and do
    not grant additional rights to the source or binary of this installer.

    NO WARRANTY

    THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
    OR IMPLIED. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM,
    DAMAGES, OR OTHER LIABILITY ARISING FROM THE USE OF THIS SOFTWARE.
    ''';

type
  // the caret position is protected; a descendant of the box type reaches it,
  // which is what a rebuilt page needs to put the caret back where it was
  TBoxAccess = class(TPixieElTextBase);

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
{$ifdef WINDOWS}
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

// what the desktop is set to right now, for the first run that has no settings
function systemPrefersDark: Boolean;
begin
  Result := False;
{$ifdef WINDOWS}
  var reg := autofree TRegistry.Create(KEY_READ);
  reg.RootKey := HKEY_CURRENT_USER;
  if not reg.OpenKeyReadOnly('SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize') then Exit;
  try
    if reg.ValueExists('AppsUseLightTheme') then Result := reg.ReadInteger('AppsUseLightTheme') = 0;
  except
  end;
  reg.CloseKey;
{$endif}
end;

function check(const act, caption, hint, link: string; on, enabled: Boolean): TUiCheck;
begin
  result.act := act;
  result.caption := caption;
  result.hint := hint;
  result.link := link;
  result.on := on;
  result.enabled := enabled;
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FLog := TStringList.Create;
  FFpcBranchShas := TStringList.Create;
  FLazBranchShas := TStringList.Create;
  st.fpcBranches := TStringList.Create;
  st.lazBranches := TStringList.Create;
  st.log := FLog;

  {$ifdef LINUX}
  var IconStream := autofree TMemoryStream.Create;
  IconStream.WriteBuffer(INSTALLER_PNG, SizeOf(INSTALLER_PNG));
  IconStream.Position := 0;
  var png := autofree TPortableNetworkGraphic.Create;
  png.LoadFromStream(IconStream);
  Application.Icon.Assign(png);
  Self.Icon.Assign(png);
  {$endif}

  // augment LFM caption with version + build stamp
  var BuildDate := StringReplace(BUILD_DATE_RAW, '/', '-', [rfReplaceAll]);
  var BuildTime := Copy(BUILD_TIME_RAW, 1, 5);   // HH:MM, drop :SS
  var Ver := GetAppVersion;
  if Ver <> '' then Caption := Caption+' v'+Ver;
  Caption := Caption+' (built at '+BuildDate+' '+BuildTime+')';
  st.title := Caption;

  // host-native target cannot be cross-built: it is the build itself
  {$ifdef LINUX}
  FNativeLinux64 := True;
  st.targetDir := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME'))+'fpcunleashed';
  {$else}
  FNativeWin64 := True;
  st.targetDir := 'C:\fpcunleashed';
  {$endif}

  // what a fresh install looks like before installer_settings.ini says otherwise
  FillChar(FPrefs, SizeOf(FPrefs), 0);
  FPrefs.InstallFpc := True;
  FPrefs.InstallLazarus := True;
  FPrefs.FpcLatest := True;
  FPrefs.LazLatest := True;
  FPrefs.InstallMinimap := True;
  FPrefs.InstallCPUView := True;
  FPrefs.InstallHelpFiles := True;
  FPrefs.MakeDesktopShortcut := True;
  FPrefs.MakeFolderShortcut := True;
  FPrefs.LaunchAfter := True;

  st.fpcOn := True;
  st.lazOn := True;
  st.fpcLatest := True;
  st.lazLatest := True;
  st.installLabel := 'Install';
  st.inputsOn := True;
  FMinimap := True;
  FCpuView := True;
  FHelpFiles := True;
  FDesktopShortcut := True;
  FFolderShortcut := True;
  FLaunchAfter := True;
  st.saveLog := True;
  FFollowLog := True;
  FMouseX := -1;

  // with nothing saved yet, the desktop decides
  if systemPrefersDark then st.theme := utDark else st.theme := utLight;

  setStatus('Ready');
  refreshTarget;
  applyHashesFromBinaryName;

  // stored geometry wins; without it the window is sized to its contents once
  // the first layout says how tall they are
  FSizeToContent := not applyStoredSettings;

  render;
end;

// Preferences from installer_settings.ini. Returns True when it applied a
// window geometry, so FormCreate knows to skip its own sizing. A manifest
// in the target dir outranks the stored checkboxes: it describes what is
// actually installed there, the settings only carry a habit.
function TMainForm.applyStoredSettings: Boolean;
begin
  result := False;
  var s := readSettings;
  if not s.Present then exit;
  FPrefs := s;

  if s.FpcBranch <> '' then st.fpcBranch := s.FpcBranch;
  if s.LazBranch <> '' then st.lazBranch := s.LazBranch;
  if s.TargetDir <> '' then st.targetDir := s.TargetDir;
  st.saveLog := s.SaveLog;
  if s.Theme = 'dark' then st.theme := utDark
  else if s.Theme = 'light' then st.theme := utLight;

  if not ReadManifest(Trim(st.targetDir)).Present then resetTargetToDefaults;
  refreshTarget;

  if (s.WindowWidth <= 0) or (s.WindowHeight <= 0) then exit;
  // clamp into the current desktop: the monitor that held the window last
  // run may be gone, and an off-screen window is unreachable
  var w := Min(s.WindowWidth, Screen.DesktopWidth);
  var h := Min(s.WindowHeight, Screen.DesktopHeight);
  var l := Max(Screen.DesktopLeft, Min(s.WindowLeft, Screen.DesktopLeft+Screen.DesktopWidth-w));
  var t := Max(Screen.DesktopTop, Min(s.WindowTop, Screen.DesktopTop+Screen.DesktopHeight-h));
  SetBounds(l, t, w, h);
  if s.WindowMaximized then WindowState := wsMaximized;
  result := True;
end;

procedure TMainForm.storeSettings;
begin
  var s: TAppSettings;
  s.Present := True;
  // Restored* is the pre-maximize geometry; Left/Width would store the
  // maximized frame and the window would never come back to its own size
  s.WindowLeft   := RestoredLeft;
  s.WindowTop    := RestoredTop;
  s.WindowWidth  := RestoredWidth;
  s.WindowHeight := RestoredHeight;
  s.WindowMaximized := WindowState = wsMaximized;
  s.TargetDir := Trim(st.targetDir);
  s.FpcBranch := st.fpcBranch;
  s.LazBranch := st.lazBranch;
  s.FpcHash := Trim(st.fpcHash);
  s.LazHash := Trim(st.lazHash);
  s.FpcLatest := st.fpcLatest;
  s.LazLatest := st.lazLatest;
  s.InstallFpc := st.fpcOn;
  s.InstallLazarus := st.lazOn;
  s.CrossWin64   := FCrossWin64;
  s.CrossWin32   := FCrossWin32;
  s.CrossLinux64 := FCrossLinux64;
  s.CrossLinux32 := FCrossLinux32;
  s.CrossWasm    := FCrossWasm;
  s.InstallMinimap        := FMinimap;
  s.InstallCPUView        := FCpuView;
  s.InstallToggleAffinity := FToggleAffinity;
  s.InstallMetaDarkStyle  := FMetaDark;
  s.InstallHelpFiles      := FHelpFiles;
  s.MakeDesktopShortcut   := FDesktopShortcut;
  s.MakeFolderShortcut    := FFolderShortcut;
  s.LaunchAfter := FLaunchAfter;
  s.SaveLog     := st.saveLog;
  s.Theme       := if st.theme = utDark then 'dark' else 'light';
  writeSettings(s);
end;

// -- clicks ---------------------------------------------------------

// the click bubbles from the element that was hit up to <body>, so the first
// ancestor carrying data-act owns it
function TMainForm.viewElementClick(Sender: TObject; El: TObject): Boolean;
begin
  Result := False;
  var tag := TPixieHtmlTag(El);
  var act := tag.GetAttr('data-act');
  if act = '' then Exit;
  captureInputs;
  if act <> 'modalstay' then st.modal.kind := umNone;
  runAct(act, tag);
  Result := True;
end;

// the boxes the user types into live in the document, so what is in them has to
// be read back before the page is thrown away and built again
procedure TMainForm.captureInputs;

  function typed(const id: string; out text: string): Boolean;
  begin
    text := '';
    Result := False;
    if view.Document = nil then Exit;
    var el := view.Document.GetElementById(id);
    Result := el is TPixieElTextBase;
    if Result then text := TPixieElTextBase(el).Value;
  end;

begin
  var text: string;
  if typed('targetDir', text) and (text <> st.targetDir) then
  begin
    st.targetDir := text;
    refreshTarget;
  end;
  if typed('fpcHash', text) then st.fpcHash := text;
  if typed('lazHash', text) then st.lazHash := text;
end;

// any click that is not on a dropdown button closes the open dropdown, which
// is what a click outside one is expected to do
procedure TMainForm.runAct(const act: string; el: TPixieHtmlTag);
begin
  var wasOpen := st.openDrop <> '';
  if act <> 'drop' then st.openDrop := '';

  match act of
    'drop': begin
      var name := el.GetAttr('data-name');
      if st.openDrop = name then st.openDrop := '' else st.openDrop := name;
      queueRender;
    end;

    'closedrop': if wasOpen then queueRender;
    'modalstay': ;
    'modalclose': queueRender;
    'url': OpenURL(el.GetAttr('data-name'));
    'close': Close;
    'quit!': begin FClosing := True; Close; end;

    'themelight': if st.theme <> utLight then begin st.theme := utLight; applyWindowTheme; queueRender; end;
    'themedark':  if st.theme <> utDark then begin st.theme := utDark; applyWindowTheme; queueRender; end;

    'browse': begin
      if SelectDirDialog.Execute then
      begin
        st.targetDir := SelectDirDialog.FileName;
        refreshTarget;
      end;
      queueRender;
    end;

    'install':  startInstall;
    'clearlog': begin FLog.Clear; queueRender; end;
    'copylog':  begin Clipboard.AsText := FLog.Text; queueRender; end;

    'menufile': if el.GetAttr('data-name') = 'Exit' then Close;

    'menurepo': begin
      var repo := match el.GetAttr('data-name') of
        'Unleashed Compiler':           'freepascal';
        'Unleashed IDE':                'lazarus';
        'Unleashed Pascal Installer':   'installer';
        _:                              '';
      end;
      OpenURL('https://github.com/fpc-unleashed/'+repo);
      queueRender;
    end;

    'menuhelp': begin
      if el.GetAttr('data-name') = 'About' then showAbout
      else begin
        OpenURL('https://github.com/fpc-unleashed/freepascal/blob/main/unleashed/docs/README.md');
        queueRender;
      end;
    end;

    'togglefpc': begin st.fpcOn := not st.fpcOn; refreshTarget; queueRender; end;
    'togglelaz': begin st.lazOn := not st.lazOn; refreshTarget; queueRender; end;

    // on checked->unchecked, pre-fill the now-editable commit box.
    // priority: 1) installer.ini SHA (pin to disk install, don't silently stage HEAD); 2) head SHA of selected branch.
    // live fetch knows every branch SHA; cache-hit only knows 'main' so other branches leave the box blank
    'togglefpclatest': begin
      st.fpcLatest := not st.fpcLatest;
      if not st.fpcLatest then
      begin
        var sha := '';
        var m := ReadManifest(Trim(st.targetDir));
        if m.Present then sha := m.FpcSha;
        if (sha = '') and (st.fpcBranch <> '') then sha := FFpcBranchShas.Values[st.fpcBranch];
        if sha <> '' then st.fpcHash := sha;
      end;
      refreshTarget;
      queueRender;
    end;

    'togglelazlatest': begin
      st.lazLatest := not st.lazLatest;
      if not st.lazLatest then
      begin
        var sha := '';
        var m := ReadManifest(Trim(st.targetDir));
        if m.Present then sha := m.LazSha;
        if (sha = '') and (st.lazBranch <> '') then sha := FLazBranchShas.Values[st.lazBranch];
        if sha <> '' then st.lazHash := sha;
      end;
      refreshTarget;
      queueRender;
    end;

    'pickfpcbranch': begin st.fpcBranch := el.GetAttr('data-name'); refreshTarget; queueRender; end;
    'picklazbranch': begin st.lazBranch := el.GetAttr('data-name'); refreshTarget; queueRender; end;

    'crosswin64':   begin FCrossWin64 := not FCrossWin64; refreshTarget; queueRender; end;
    'crosswin32':   begin FCrossWin32 := not FCrossWin32; refreshTarget; queueRender; end;
    'crosslinux64': begin FCrossLinux64 := not FCrossLinux64; refreshTarget; queueRender; end;
    'crosswasm':    begin FCrossWasm := not FCrossWasm; refreshTarget; queueRender; end;

    // i386-linux build needs ppcross386 (the i386-win32 cross); tick the prereq
    'crosslinux32': begin
      FCrossLinux32 := not FCrossLinux32;
      if FCrossLinux32 then FCrossWin32 := True;
      refreshTarget;
      queueRender;
    end;

    'minimap':   begin FMinimap := not FMinimap; refreshTarget; queueRender; end;
    'cpuview':   begin FCpuView := not FCpuView; refreshTarget; queueRender; end;
    'metadark':  begin FMetaDark := not FMetaDark; refreshTarget; queueRender; end;
    'helpfiles': begin FHelpFiles := not FHelpFiles; refreshTarget; queueRender; end;
    'affinity':  begin FToggleAffinity := not FToggleAffinity; refreshTarget; queueRender; end;
    'desktopsc': begin FDesktopShortcut := not FDesktopShortcut; refreshTarget; queueRender; end;
    'foldersc':  begin FFolderShortcut := not FFolderShortcut; refreshTarget; queueRender; end;
    'launch':    begin FLaunchAfter := not FLaunchAfter; queueRender; end;
    'togglesavelog': begin st.saveLog := not st.saveLog; queueRender; end;
  end;
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if st.modal.kind <> umNone then
  begin
    if Key = VK_RETURN then
    begin
      Key := 0;
      var okAct := st.modal.okAct;
      st.modal.kind := umNone;
      runAct(okAct, nil);
    end
    else if Key = VK_ESCAPE then
    begin
      Key := 0;
      st.modal.kind := umNone;
      queueRender;
    end;
    Exit;
  end;

  // select-all belongs to a box that holds text, not to the whole window
  if (Key = VK_A) and (ssCtrl in Shift) and (not focusIsTextBox) then Key := 0;

  // what was typed reaches the box after this handler returns, so the page is
  // rebuilt a moment later: that keeps the folder line in step with the path
  if focusIsTextBox then
  begin
    liveTimer.Enabled := False;
    liveTimer.Enabled := True;
  end;
end;

procedure TMainForm.liveTimerTimer(Sender: TObject);
begin
  liveTimer.Enabled := False;
  captureInputs;
  render;
end;

function TMainForm.focusIsTextBox: Boolean;
begin
  Result := False;
  if view.Document = nil then Exit;
  Result := view.Document.FocusedElement is TPixieElTextBase;
end;

// -- dialogs --------------------------------------------------------

// every dialog is part of the page, so none of these wait for an answer: the
// answer arrives later as a click on okAct
procedure TMainForm.note(const title, text: string);
begin
  st.modal.kind := umNote;
  st.modal.title := title;
  st.modal.text := text;
  st.modal.body := '';
  st.modal.okAct := 'modalclose';
  st.modal.okLabel := 'OK';
  queueRender;
end;

procedure TMainForm.confirm(const title, text, okAct, okLabel: string);
begin
  st.modal.kind := umConfirm;
  st.modal.title := title;
  st.modal.text := text;
  st.modal.body := '';
  st.modal.okAct := okAct;
  st.modal.okLabel := okLabel;
  queueRender;
end;

procedure TMainForm.showAbout;
begin
  st.modal.kind := umNote;
  st.modal.title := st.title;
  st.modal.text := 'The official installer for fpc-unleashed. It fetches, builds and installs the compiler and the IDE.';
  // the parser eats the first line break of a textarea, so it gets one to eat
  st.modal.body := '<textarea class="license" readonly>'+LineEnding+esc(LICENSE_TEXT)+'</textarea>';
  st.modal.okAct := 'modalclose';
  st.modal.okLabel := 'Close';
  queueRender;
end;

// -- target state ---------------------------------------------------

// IDE needs at least one launch shortcut (desktop or install-folder) -- it's
// the only --pcp-correct way to start it
procedure TMainForm.updateShortcutError;
begin
  FShortcutError := st.lazOn and (not FDesktopShortcut) and (not FFolderShortcut);
  if FShortcutError then st.shortcutWarn := LAUNCH_WARN_MSG else st.shortcutWarn := '';
end;

// folder is authoritative; installer.ini carries build SHA for update detection
//   A. blank path           -> error, Install disabled
//   B. dir absent or empty  -> defaults, "New installation"
//   C. dir has installer.ini -> restore from manifest
//   D. dir non-empty w/o ini -> error (someone else's folder)
procedure TMainForm.refreshTarget;
begin
  // re-entry guard: the reset writes state that lands back here
  if FRefreshingTarget then Exit;
  FRefreshingTarget := True;
  try
  var rawDir := Trim(st.targetDir);

  // optimistic reset; each branch re-sets the flag as needed
  FFolderError := False;
  st.modeBad := False;
  updateShortcutError;

  // ---- state A: no path entered ----
  if rawDir = '' then begin
    FFolderError := True;
    st.modeBad := True;
    st.mode := 'No target directory selected';
    FLastState := 'A';
    FLastStateDir := rawDir;
    Exit;
  end;

  var dir            := IncludeTrailingPathDelimiter(rawDir);
  var manifestExists := FileExists(dir+MANIFEST_FILE);
  var dirExists      := DirectoryExists(dir);

  // ---- state B: target absent or empty (no manifest) -> fresh install ----
  // reset only on entry into state-B so a checkbox toggle re-entry doesn't wipe the change
  if (not manifestExists) and ((not dirExists) or IsDirEffectivelyEmpty(dir)) then begin
    if (FLastState <> 'B') or (FLastStateDir <> rawDir) then resetTargetToDefaults;
    st.mode := 'New installation';
    st.installLabel := 'Install';
    updateShortcutError;
    FLastState := 'B';
    FLastStateDir := rawDir;
    Exit;
  end;

  // ---- state D: dir has content but no manifest -> refuse ----
  // fresh install overwrites fpc/, lazarus/, ... -- a stray unrelated tree would get clobbered
  if not manifestExists then begin
    FFolderError := True;
    st.modeBad := True;
    st.mode := 'Target folder is not empty and is not an Unleashed install (installer.ini not found). Choose an empty directory or an existing Unleashed install location.';
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
  // list every selectable target, native first, so the summary matches the cross boxes
  {$ifdef WINDOWS}
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
  // sync once per target dir; gate on manifest-presence so a partial install still triggers restore
  if FCrossSyncedFor <> dir then begin
    FCrossSyncedFor := dir;
    // {Win64,Linux64} cross synced only on the host where they are not native
    if not FNativeWin64 then FCrossWin64 := ProbeCrossInstalled(rawDir, 'x86_64-win64');
    if not FNativeLinux64 then FCrossLinux64 := ProbeCrossInstalled(rawDir, 'x86_64-linux');
    FCrossWin32   := ProbeCrossInstalled(rawDir, 'i386-win32');
    FCrossLinux32 := ProbeCrossInstalled(rawDir, 'i386-linux');
    FCrossWasm    := ProbeCrossInstalled(rawDir, 'wasm32-wasip1');
    // restore non-FS-detectable selections (branch/hash/addons/launch-after) from manifest
    if m.Present then begin
      FMinimap  := m.InstallMinimap;
      FCpuView  := m.InstallCPUView;
      FMetaDark := m.InstallMetaDarkStyle;
      // help stays ticked once installed; unticking never removes the files, it just skips the fetch
      FHelpFiles := m.InstallHelpFiles;
      {$ifdef WINDOWS}
      FToggleAffinity := m.InstallToggleAffinity;
      {$endif}
      FLaunchAfter := m.LaunchAfter;
      FDesktopShortcut := m.MakeDesktopShortcut;
      FFolderShortcut  := m.MakeFolderShortcut;
      if m.FpcBranch <> '' then begin
        st.fpcBranch := m.FpcBranch;
        // always show last installed SHA in the hash box (display-only while Latest=on); restore explicit Latest flag
        st.fpcHash := m.FpcSha;
        st.fpcLatest := m.FpcLatest;
      end;
      if m.LazBranch <> '' then begin
        st.lazBranch := m.LazBranch;
        st.lazHash := m.LazSha;
        st.lazLatest := m.LazLatest;
      end;
    end;
  end;
  if m.Present then begin
    var selFpc := resolveSelectedFpcSha;
    var selLaz := resolveSelectedLazSha;
    if hasFpc and (selFpc <> '') and (m.FpcSha <> '') and (Pos(selFpc, m.FpcSha) <> 1) and (Pos(m.FpcSha, selFpc) <> 1) then updates := updates+' fpc '+Copy(m.FpcSha, 1, 7)+' -> '+Copy(selFpc, 1, 7);
    if hasLaz and (selLaz <> '') and (m.LazSha <> '') and (Pos(selLaz, m.LazSha) <> 1) and (Pos(m.LazSha, selLaz) <> 1) then updates := updates+' lazarus '+Copy(m.LazSha, 1, 7)+' -> '+Copy(selLaz, 1, 7);
    // addon deltas. the pipeline handles them without a full reinstall, but the label has to reflect reality
    if hasLaz and (FMinimap <> m.InstallMinimap) then updates := updates+(if FMinimap then ' +minimap' else ' -minimap');
    if hasLaz and (FCpuView <> m.InstallCPUView) then updates := updates+(if FCpuView then ' +cpuview' else ' -cpuview');
    if hasLaz and (FMetaDark <> m.InstallMetaDarkStyle) then updates := updates+(if FMetaDark then ' +metadarkstyle' else ' -metadarkstyle');
    // help files are add-only: nothing gets deleted when the box goes off, so only the +delta is real
    if hasLaz and FHelpFiles and (not m.InstallHelpFiles) then updates := updates+' +help';
    {$ifdef WINDOWS}
    if hasLaz and (FToggleAffinity <> m.InstallToggleAffinity) then updates := updates+(if FToggleAffinity then ' +toggle-affinity' else ' -toggle-affinity');
    {$endif}
    if hasFpc and (not FNativeWin64) and (FCrossWin64 <> m.CrossWin64) then updates := updates+(if FCrossWin64 then ' +x86_64-win64' else ' -x86_64-win64');
    if hasFpc and (FCrossWin32 <> m.CrossWin32) then updates := updates+(if FCrossWin32 then ' +i386-win32' else ' -i386-win32');
    if hasFpc and (FCrossLinux64 <> m.CrossLinux64) then updates := updates+(if FCrossLinux64 then ' +x86_64-linux' else ' -x86_64-linux');
    if hasFpc and (FCrossLinux32 <> m.CrossLinux32) then updates := updates+(if FCrossLinux32 then ' +i386-linux' else ' -i386-linux');
    if hasFpc and (FCrossWasm <> m.CrossWasm) then updates := updates+(if FCrossWasm then ' +wasm32-wasip1' else ' -wasm32-wasip1');
  end;

  if updates <> '' then begin
    st.mode := 'Update available:'+updates;
    st.installLabel := 'Update';
  end else if parts <> '' then begin
    st.mode := 'Existing install detected ('+parts+') - Install will overwrite';
    st.installLabel := 'Reinstall';
  end else begin
    // manifest present but no FPC/Lazarus binary -- a prior install died after writing it. Treat as resumable
    st.mode := 'Partial install detected (manifest only) - Install will resume';
    st.installLabel := 'Resume';
  end;
  updateShortcutError;
  FLastState := 'C';
  FLastStateDir := rawDir;
  finally
    FRefreshingTarget := False;
  end;
end;

// a target dir with nothing in it comes up with what the last run was left
// set to, so wiping a broken install and starting over keeps the choices
procedure TMainForm.resetTargetToDefaults;
begin
  // the host-native cross target is locked off anyway
  FCrossWin64 := FPrefs.CrossWin64 and (not FNativeWin64);
  FCrossLinux64 := FPrefs.CrossLinux64 and (not FNativeLinux64);
  FCrossWin32 := FPrefs.CrossWin32;
  FCrossLinux32 := FPrefs.CrossLinux32;
  FCrossWasm := FPrefs.CrossWasm;

  FMinimap := FPrefs.InstallMinimap;
  FCpuView := FPrefs.InstallCPUView;
  FMetaDark := FPrefs.InstallMetaDarkStyle;
  FHelpFiles := FPrefs.InstallHelpFiles;
  {$ifdef WINDOWS}
  FToggleAffinity := FPrefs.InstallToggleAffinity;
  {$endif}

  st.fpcOn := FPrefs.InstallFpc;
  st.lazOn := FPrefs.InstallLazarus;
  FLaunchAfter := FPrefs.LaunchAfter;
  FDesktopShortcut := FPrefs.MakeDesktopShortcut;
  FFolderShortcut := FPrefs.MakeFolderShortcut;

  // a commit pinned by the binary name outranks anything stored
  if not FPinnedHashes then begin
    st.fpcLatest := FPrefs.FpcLatest;
    st.lazLatest := FPrefs.LazLatest;
    st.fpcHash := FPrefs.FpcHash;
    st.lazHash := FPrefs.LazHash;
  end;

  // forget the per-dir sync so moving into a manifest dir re-runs the restore
  FCrossSyncedFor := '';
end;

function TMainForm.resolveSelectedFpcSha: string;
begin
  // explicit hash wins; otherwise head SHA of currently-selected branch (as of last fetch)
  Result := if (not st.fpcLatest) and (Trim(st.fpcHash) <> '') then LowerCase(Trim(st.fpcHash))
            else if st.fpcBranch <> '' then LowerCase(FFpcBranchShas.Values[st.fpcBranch])
            else '';
end;

function TMainForm.resolveSelectedLazSha: string;
begin
  Result := if (not st.lazLatest) and (Trim(st.lazHash) <> '') then LowerCase(Trim(st.lazHash))
            else if st.lazBranch <> '' then LowerCase(FLazBranchShas.Values[st.lazBranch])
            else '';
end;

// pull pinned (fpc, laz) from ParamStr(1) or filename. Wire format: README.md "Filename hash pin" + hash_branch.pas
procedure TMainForm.applyHashesFromBinaryName;
const
  // legacy fallback only; new encoder produces single hex+digit run with no separators
  HASH_PATTERN = '(?<![0-9a-fA-F])([0-9a-fA-F]{7,12})[^0-9a-fA-F]+([0-9a-fA-F]{7,12})(?![0-9a-fA-F])';
begin
  var parsed: TParsedBinaryName;
  parsed.Present := False;

  // 1. cmdline override via ParamStr(1) -- whole arg as raw blob; falls back to filename if not a valid blob
  if (ParamCount >= 1) and (ParamStr(1) <> '') then begin
    if TryParseBlob(ParamStr(1), parsed) then log('using cmdline pin: '+ParamStr(1))
    else log('cmdline arg "'+ParamStr(1)+'" is not a pin blob; falling back to filename');
  end;

  // 2. filename (new length-prefixed format) -- LAST hex run >= 12
  if not parsed.Present then parsed := ParseBinaryName(ExtractFileName(ParamStr(0)));

  if parsed.Present then begin
    FPinnedHashes := True;
    // empty FpcCommit/LazCommit = '0' length digit = "latest of selected branch" sentinel
    log('binary name carries pinned commit hashes: fpc='+(if parsed.FpcCommit = '' then '(latest)' else parsed.FpcCommit)+' ide='+(if parsed.LazCommit = '' then '(latest)' else parsed.LazCommit));

    if parsed.FpcCommit = '' then begin
      st.fpcHash := '';
      st.fpcLatest := True;
    end else begin
      st.fpcHash := parsed.FpcCommit;
      st.fpcLatest := False;
    end;

    if parsed.LazCommit = '' then begin
      st.lazHash := '';
      st.lazLatest := True;
    end else begin
      st.lazHash := parsed.LazCommit;
      st.lazLatest := False;
    end;

    // stash branch hints for fillBranches. Hash override beats predefined/implicit-main
    if parsed.FpcBranchHashOverride <> '' then FPinnedFpcBranchHex := parsed.FpcBranchHashOverride
    else if parsed.FpcBranchFromCommit <> '' then FPinnedFpcBranchName := parsed.FpcBranchFromCommit;
    if parsed.LazBranchHashOverride <> '' then FPinnedLazBranchHex := parsed.LazBranchHashOverride
    else if parsed.LazBranchFromCommit <> '' then FPinnedLazBranchName := parsed.LazBranchFromCommit;

    // companion summary line; hash-overridden branches show the hex here, the matching name lands later
    var fpcStr: string := if parsed.FpcBranchHashOverride <> '' then parsed.FpcBranchHashOverride else if parsed.FpcBranchFromCommit <> '' then parsed.FpcBranchFromCommit else '(default)';
    var lazStr: string := if parsed.LazBranchHashOverride <> '' then parsed.LazBranchHashOverride else if parsed.LazBranchFromCommit <> '' then parsed.LazBranchFromCommit else '(default)';
    log('binary name carries pinned branch hashes: fpc='+fpcStr+' ide='+lazStr);

    refreshTarget;
    Exit;
  end;

  // 3. legacy two-hash regex fallback; only consulted when neither cmdline nor new-format filename matched
  var Name := ExtractFileName(ParamStr(0));
  var R := autofree TRegExpr.Create;
  R.Expression := HASH_PATTERN;
  if not R.Exec(Name) then Exit;

  var FpcHash := LowerCase(R.&Match[1]);
  var LazHash := LowerCase(R.&Match[2]);
  log('binary name carries pinned commit hashes (legacy): fpc='+FpcHash+' ide='+LazHash);
  FPinnedHashes := True;
  st.fpcHash := FpcHash;
  st.fpcLatest := False;
  st.lazHash := LazHash;
  st.lazLatest := False;
  refreshTarget;
end;

// -- branches -------------------------------------------------------

procedure TMainForm.FormShow(Sender: TObject);
begin
  if FShowFired then Exit;
  FShowFired := True;
  // the frame exists only once the window is up
  applyWindowTheme;
  startBranchFetch;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  storeSettings;
  // worker threads have FreeOnTerminate=True; the flag stops their callbacks from touching a destroyed form
  GShuttingDown := True;
  FFpcBranchShas.Free;
  FLazBranchShas.Free;
  st.fpcBranches.Free;
  st.lazBranches.Free;
  FLog.Free;
end;

// while the pipeline runs, the install thread touches the target tree
procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FClosing or (not FInstalling) then Exit;
  CanClose := False;
  confirm('Installation in progress',
    'An installation is currently running. Closing now will leave the target directory in a half-built state.',
    'quit!', 'Close anyway');
end;

// cache age for logs (LoadCache returns seconds); trims leading zero units: 13->"13s", 193->"3m 13s"
function ageStr(ageSeconds: Double): string;
begin
  var total := Round(ageSeconds);
  if total < 0 then total := 0;
  var d := total div 86400;
  var h := (total div 3600) mod 24;
  var m := (total div 60) mod 60;
  var s := total mod 60;
  result := '';
  if d > 0 then result := result+IntToStr(d)+'d ';
  if (result <> '') or (h > 0) then result := result+IntToStr(h)+'h ';
  if (result <> '') or (m > 0) then result := result+IntToStr(m)+'m ';
  result := result+IntToStr(s)+'s';
end;

procedure TMainForm.startBranchFetch;

  // convert bare-name list to 'name=sha' form fillBranches expects; only 'main' gets a SHA from cache
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
  setStatus('Updating branches list...');
  FFetchPending := 2;
  FFpcFetchOk := False;
  FLazFetchOk := False;

  // cache-first: skip the GitHub fetch if the cache file is younger than CACHE_TTL_MINUTES
  var fpcNames := autofree TStringList.Create;
  var ideNames := autofree TStringList.Create;
  var age: Double;
  var fpcMainSha, ideMainSha: string;
  if LoadCache(fpcNames, ideNames, age, fpcMainSha, ideMainSha) and (age < CACHE_TTL_MINUTES*60) then begin
    log('using cached branch lists ('+ageStr(age)+' old, file="'+CacheFilePath+'")');
    var fpcCache := autofree TStringList.Create;
    var lazCache := autofree TStringList.Create;
    AppendWithMainSha(fpcNames, fpcCache, fpcMainSha);
    AppendWithMainSha(ideNames, lazCache, ideMainSha);
    fillBranches(True, fpcCache, '');
    st.fpcReady := True;
    fetchTick;
    fillBranches(False, lazCache, '');
    st.lazReady := True;
    fetchTick;
    Exit;
  end;

  log('Fetching branches from github.com/'+GH_OWNER+'/'+REPO_FPC+' and /'+REPO_LAZARUS);
  TBranchFetchThread.Create(GH_OWNER, REPO_FPC,     @onUnleashedDone);
  TBranchFetchThread.Create(GH_OWNER, REPO_LAZARUS, @onLazarusDone);
end;

// failed-fetch fallback: build 'name=sha' from bare names, attaching the cached HEAD SHA only to 'main'
procedure NamesToShaListWithMain(Src, Dest: TStringList; const MainSha: string);
begin
  Dest.Clear;
  for var i := 0 to Src.Count-1 do
    if SameText(Src[i], 'main') then Dest.Add(Src[i]+'='+MainSha)
    else Dest.Add(Src[i]+'=');
end;

procedure TMainForm.onUnleashedDone(Sender: TObject);
begin
  if GShuttingDown then exit;
  var T := TBranchFetchThread(Sender);
  if T.ErrorMsg <> '' then begin
    var fpcNames := autofree TStringList.Create;
    var ideNames := autofree TStringList.Create;
    var age: Double;
    var fpcMainSha, ideMainSha: string;
    if LoadCache(fpcNames, ideNames, age, fpcMainSha, ideMainSha) and (fpcNames.Count > 0) then begin
      var fallback := autofree TStringList.Create;
      NamesToShaListWithMain(fpcNames, fallback, fpcMainSha);
      log('FAILED to fetch '+REPO_FPC+' branches ('+T.ErrorMsg+'); using stale cache ('+ageStr(age)+' old)');
      fillBranches(True, fallback, '');
    end else fillBranches(True, T.Branches, T.ErrorMsg);
    FFpcFetchOk := False;
  end else begin
    fillBranches(True, T.Branches, T.ErrorMsg);
    FFpcFetchOk := True;
  end;
  st.fpcReady := True;
  fetchTick;
end;

procedure TMainForm.onLazarusDone(Sender: TObject);
begin
  if GShuttingDown then exit;
  var T := TBranchFetchThread(Sender);
  if T.ErrorMsg <> '' then begin
    var fpcNames := autofree TStringList.Create;
    var ideNames := autofree TStringList.Create;
    var age: Double;
    var fpcMainSha, ideMainSha: string;
    if LoadCache(fpcNames, ideNames, age, fpcMainSha, ideMainSha) and (ideNames.Count > 0) then begin
      var fallback := autofree TStringList.Create;
      NamesToShaListWithMain(ideNames, fallback, ideMainSha);
      log('FAILED to fetch '+REPO_LAZARUS+' branches ('+T.ErrorMsg+'); using stale cache ('+ageStr(age)+' old)');
      fillBranches(False, fallback, '');
    end else fillBranches(False, T.Branches, T.ErrorMsg);
    FLazFetchOk := False;
  end else begin
    fillBranches(False, T.Branches, T.ErrorMsg);
    FLazFetchOk := True;
  end;
  st.lazReady := True;
  fetchTick;
end;

procedure TMainForm.fillBranches(fpc: Boolean; branches: TStringList; const errorMsg: string);
begin
  var list := if fpc then st.fpcBranches else st.lazBranches;
  var shaMap := if fpc then FFpcBranchShas else FLazBranchShas;
  var repo := if fpc then REPO_FPC else REPO_LAZARUS;
  shaMap.Clear;
  list.Clear;

  if errorMsg <> '' then begin
    log('FAILED to fetch '+repo+' branches: '+errorMsg);
    list.Add('main');
    if fpc then st.fpcBranch := 'main' else st.lazBranch := 'main';
    Exit;
  end;

  // branches is 'name=sha'; Names[i] for the list, Values[name] for the SHA
  shaMap.Assign(branches);
  for var i := 0 to branches.Count-1 do list.Add(branches.Names[i]);
  log('Got '+IntToStr(branches.Count)+' branches for '+repo);

  // priority: pinned (filename) -> manifest -> what is already selected (the
  // stored preference on startup, the user's pick on a refetch) -> main ->
  // master -> first
  var current := if fpc then st.fpcBranch else st.lazBranch;
  var pinnedBranch := '';
  if fpc then begin
    if FPinnedFpcBranchName <> '' then pinnedBranch := FPinnedFpcBranchName
    else if FPinnedFpcBranchHex <> '' then begin
      pinnedBranch := FindBranchByHashPrefix(list, FPinnedFpcBranchHex);
      if pinnedBranch <> '' then log('fpc branch '''+pinnedBranch+''' matches hash prefix '''+FPinnedFpcBranchHex+''', selecting this branch');
    end;
  end else begin
    if FPinnedLazBranchName <> '' then pinnedBranch := FPinnedLazBranchName
    else if FPinnedLazBranchHex <> '' then begin
      pinnedBranch := FindBranchByHashPrefix(list, FPinnedLazBranchHex);
      if pinnedBranch <> '' then log('ide branch '''+pinnedBranch+''' matches hash prefix '''+FPinnedLazBranchHex+''', selecting this branch');
    end;
  end;

  var manifestBranch := '';
  var m := ReadManifest(Trim(st.targetDir));
  if m.Present then manifestBranch := if fpc then m.FpcBranch else m.LazBranch;

  var idx := -1;
  if pinnedBranch <> '' then idx := list.IndexOf(pinnedBranch);
  if idx < 0 then if manifestBranch <> '' then idx := list.IndexOf(manifestBranch);
  if idx < 0 then if current <> '' then idx := list.IndexOf(current);
  if idx < 0 then idx := list.IndexOf('main');
  if idx < 0 then idx := list.IndexOf('master');
  if idx < 0 then idx := 0;
  if list.Count > 0 then
    if fpc then st.fpcBranch := list[idx] else st.lazBranch := list[idx];
  refreshTarget;
end;

procedure TMainForm.fetchTick;
begin
  Dec(FFetchPending);
  if FFetchPending = 0 then begin
    // rewrite the cache only on full success; a partial one leaves the old file for future fallback
    if FFpcFetchOk and FLazFetchOk then begin
      SaveCache(FFpcBranchShas, FLazBranchShas);
      log('cached branch lists (TTL '+IntToStr(CACHE_TTL_MINUTES)+' min, file="'+CacheFilePath+'")');
    end;
    setStatus('Ready');
  end;
  queueRender;
end;

// -- install --------------------------------------------------------

procedure TMainForm.setInputsEnabled(act: Boolean);
begin
  st.inputsOn := act;
  queueRender;
end;

procedure TMainForm.startInstall;
var
  cfg: TInstallConfig;
begin
  if FInstalling then Exit;
  if FFolderError then begin
    note('Nothing to install into', st.mode);
    Exit;
  end;
  if FShortcutError then begin
    note('Pick a shortcut', LAUNCH_WARN_MSG);
    Exit;
  end;

  cfg.TargetDir := Trim(st.targetDir);
  if cfg.TargetDir = '' then begin
    note('Nothing to install into', 'No target directory selected.');
    Exit;
  end;

  cfg.InstallFpc     := st.fpcOn;
  cfg.InstallLazarus := st.lazOn;
  // cross choices are meaningless w/o FPC (no ppcx64 to drive crossinstall)
  cfg.CrossWin64     := FCrossWin64   and cfg.InstallFpc;
  cfg.CrossWin32     := FCrossWin32   and cfg.InstallFpc;
  cfg.CrossLinux64   := FCrossLinux64 and cfg.InstallFpc;
  cfg.CrossLinux32   := FCrossLinux32 and cfg.InstallFpc;
  cfg.CrossWasm      := FCrossWasm    and cfg.InstallFpc;
  // addons are meaningless w/o the IDE (lazbuild needs it)
  cfg.InstallMinimap       := FMinimap  and cfg.InstallLazarus;
  cfg.InstallCPUView       := FCpuView  and cfg.InstallLazarus;
  cfg.InstallMetaDarkStyle := FMetaDark and cfg.InstallLazarus;
  cfg.InstallHelpFiles     := FHelpFiles and cfg.InstallLazarus;
  cfg.InstallToggleAffinity := FToggleAffinity and cfg.InstallLazarus;
  cfg.LaunchAfter    := FLaunchAfter;
  // shortcuts only when installing the IDE; the UI guarantees >=1 of these
  cfg.MakeDesktopShortcut := FDesktopShortcut and cfg.InstallLazarus;
  cfg.MakeFolderShortcut  := FFolderShortcut  and cfg.InstallLazarus;

  // snapshot the IDE decision; onInstallComplete combines it with the live launch box
  FInstalledLazarus := cfg.InstallLazarus;
  FInstallTargetDir := cfg.TargetDir;
  cfg.FpcLatest      := st.fpcLatest;
  cfg.FpcBranch      := st.fpcBranch;
  cfg.FpcHash        := Trim(st.fpcHash);
  cfg.LazLatest      := st.lazLatest;
  cfg.LazBranch      := st.lazBranch;
  cfg.LazHash        := Trim(st.lazHash);
  // resolved SHA into the manifest for a later compare; empty if the branch list is not loaded yet
  cfg.FpcSelectedSha := resolveSelectedFpcSha;
  cfg.LazSelectedSha := resolveSelectedLazSha;
  cfg.SaveLog        := st.saveLog;

  log('--- install requested ---');
  log('target dir: '+cfg.TargetDir);
  if cfg.InstallFpc then log('install fpc-unleashed: yes ('+cfg.FpcBranch+')') else log('install fpc-unleashed: no');
  if cfg.InstallLazarus then log('install lazarus IDE:  yes ('+cfg.LazBranch+')') else log('install lazarus IDE:  no');

  FInstalling := True;
  setInputsEnabled(False);
  st.percent := 0;
  st.done := False;
  // the pipeline logs faster than the page can be laid out, so during an install
  // the redraw runs on a timer instead of once per line
  logTimer.Enabled := True;

  TInstallThread.Create(cfg, @onInstallLog, @onInstallProgress, @onInstallComplete);
end;

procedure TMainForm.onInstallLog(const msg: string);
begin
  if GShuttingDown then exit;
  log(msg);
end;

procedure TMainForm.onInstallProgress(percent: Integer; const status: string);
begin
  if GShuttingDown then exit;
  if percent < 0 then setStatus(status)
  else begin
    if percent > 100 then percent := 100;
    st.percent := percent;
    setStatus(IntToStr(percent)+'%  '+status);
  end;
end;

procedure TMainForm.onInstallComplete(Sender: TObject);
begin
  if GShuttingDown then exit;
  var T := TInstallThread(Sender);
  if T.Success then begin
    log('=== INSTALL OK ===');
    setStatus('Done');
    st.done := True;
    st.percent := 100;
    if FInstalledLazarus and FLaunchAfter then launchInstalledIde;
  end else begin
    log('=== INSTALL FAILED: '+T.ErrorMsg+' ===');
    setStatus('Failed: '+T.ErrorMsg);
    st.percent := 0;
  end;
  FInstalling := False;
  logTimer.Enabled := False;
  setInputsEnabled(True);
  render;
end;

procedure TMainForm.launchInstalledIde;
begin
  var ExePath := IncludeTrailingPathDelimiter(FInstallTargetDir)+LazarusBinarySub;
  var PcpArg  := '--pcp='+IncludeTrailingPathDelimiter(FInstallTargetDir)+'config_lazarus';
  log('Launching '+ExePath);
{$ifdef WINDOWS}
  // detached. ShellExecute wants args as one string; quotes protect spaces in the target dir
  var Args := '"'+PcpArg+'"';
  ShellExecute(Handle, 'open', PChar(ExePath), PChar(Args), PChar(ExtractFilePath(ExePath)), SW_SHOWNORMAL);
{$endif}
{$ifdef LINUX}
  // TProcess + no poWaitOnExit -> lazarus runs independently of the installer
  var P := TProcess.Create(nil);
  try
    P.Executable := ExePath;
    P.Parameters.Add(PcpArg);
    P.CurrentDirectory := ExtractFilePath(ExePath);
    P.Options := [];
    P.InheritHandles := False;
    P.Execute;
  finally
    // don't Free before Execute returns -- the child is running; the OS reaps it on installer exit
    P.Free;
  end;
{$endif}
end;

// -- drawing --------------------------------------------------------

procedure TMainForm.setStatus(const msg: string);
begin
  st.status := msg;
  // a download reports every 256 KB, so during an install the page is left to
  // the timer: laying it out per report starves the window of everything else
  if FInstalling then FStatusDirty := True else queueRender;
end;

procedure TMainForm.log(const msg: string);
begin
  FLog.Add(FormatDateTime('hh:nn:ss', Now)+'# '+msg);
  FLogDirty := True;
  if not FInstalling then queueRender;
end;

procedure TMainForm.viewAfterPaint(Sender: TObject);
begin
  // how tall the page is is only known after it has been laid out, so the
  // window is grown to it here, once
  if FSizeToContent and (view.ContentHeight > 0) then
  begin
    FSizeToContent := False;
    var scale := 1.0;
    if view.Document.Width > 0 then scale := view.ClientWidth/view.Document.Width;
    if scale <= 0 then scale := 1;

    var wanted := Round(view.ContentHeight*scale)+(Height-ClientHeight);
    if wanted > Screen.WorkAreaHeight then wanted := Screen.WorkAreaHeight;
    if wanted < Constraints.MinHeight then wanted := Constraints.MinHeight;
    Height := wanted;
    Top := Screen.WorkAreaTop+(Screen.WorkAreaHeight-Height) div 2;
    // back to the layout that keeps the page inside the window
    queueRender;
  end;

  // a page settleDocument could not lay out itself is caught up with here
  if FLogRebuilt then begin FLogRebuilt := False; restoreLogScroll; end
  else noticeLogScroll;

  if FHoverDirty then
  begin
    FHoverDirty := False;
    restoreHover;
  end;
end;

function TMainForm.logItem: TPixieRenderItem;
begin
  result := nil;
  if view.Document = nil then Exit;
  var el := view.Document.GetElementById('log');
  if el = nil then Exit;
  result := TPixieRenderItem(el.GetRenderItem);
end;

// a rebuild throws the scroll offset away with the render tree, so the pane is
// put back where it was, or at its end while the log is followed
procedure TMainForm.restoreLogScroll;
begin
  var ri := logItem;
  if ri = nil then Exit;
  var want := FLogTop;
  if FFollowLog then want := 1000000;
  ri.VScroll(want-ri.GetScrollTop);
  FLogTop := ri.GetScrollTop;
end;

// there is no event for the wheel over a pane, so where the user left it is
// read off every paint that did not rebuild the page
procedure TMainForm.noticeLogScroll;
begin
  var ri := logItem;
  if ri = nil then Exit;
  FLogTop := ri.GetScrollTop;
  FFollowLog := not ri.IsVScrollable(24);
end;

// pixie lays a document out while it is painted, so a rebuilt one would first
// be drawn with the log pane at its top and nothing under the pointer, and only
// then be put right - one frame of flicker per update. laying it out here costs
// that layout twice but never shows the wrong frame
procedure TMainForm.settleDocument(layoutWidth: Double);
begin
  if (view.Document = nil) or (layoutWidth <= 0) then
  begin
    FLogRebuilt := True;
    FHoverDirty := True;
    Exit;
  end;

  view.Document.Render(layoutWidth);
  restoreLogScroll;
  restoreHover;
end;

procedure TMainForm.viewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  FMouseX := X;
  FMouseY := Y;

  // an open menu follows the pointer along the bar, the way a native one does
  if not isMenuDrop(st.openDrop) then Exit;
  var over := menuUnderPoint(X, Y);
  if (over = '') or (over = st.openDrop) or (not isMenuDrop(over)) then Exit;
  st.openDrop := over;
  queueRender;
end;

// which menu head the pointer sits on, '' when none. the dropdowns are the only
// thing hit-tested here, so their own boxes are enough. AbsolutePos is the
// content box, which for a button is just its caption: the padding and the
// border are put back so the whole button counts
function TMainForm.menuUnderPoint(x, y: Integer): string;
begin
  result := '';
  if view.Document = nil then Exit;
  var scale := 1.0;
  if view.Document.Width > 0 then scale := view.ClientWidth/view.Document.Width;
  if scale <= 0 then scale := 1;

  var vx := x/scale;
  var vy := y/scale+view.ScrollY;
  for var name in MENU_DROPS do
  begin
    var el := view.Document.GetElementById('drop-'+name);
    if el = nil then continue;
    var ri := TPixieRenderItem(el.GetRenderItem);
    if ri = nil then continue;
    var box := ri.AbsolutePos;
    box.AddMargins(ri.GetPaddings);
    box.AddMargins(ri.GetBorders);
    if box.IsPointInside(vx, vy) then exit(name);
  end;
end;

// a click is the element the button went down on being the one it comes up on,
// so no update may touch the page in between: it would drop the click
procedure TMainForm.viewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FMouseDown := True;
end;

procedure TMainForm.viewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FMouseDown := False;
end;

// the frame around the page belongs to the system, not to the page, so the
// light/dark switch has to reach it on its own
procedure TMainForm.applyWindowTheme;
{$ifdef WINDOWS}
type
  TDwmSetWindowAttribute = function(wnd: HWND; attr: DWORD; value: Pointer; size: DWORD): HRESULT; stdcall;
const
  // the attribute was 19 on the builds that first carried it (Windows 10
  // 1809), 20 from 20H1 on. asking with the wrong one just fails
  DWMWA_DARK_MODE     = 20;
  DWMWA_DARK_MODE_OLD = 19;
{$endif}
begin
  if not HandleAllocated then Exit;

{$ifdef WINDOWS}
  var lib := LoadLibrary('dwmapi.dll');
  if lib = 0 then Exit;
  try
    var setAttr := TDwmSetWindowAttribute(GetProcAddress(lib, 'DwmSetWindowAttribute'));
    if setAttr = nil then Exit;
    var dark: LongBool := st.theme = utDark;
    if setAttr(Handle, DWMWA_DARK_MODE, @dark, SizeOf(dark)) <> S_OK then
      setAttr(Handle, DWMWA_DARK_MODE_OLD, @dark, SizeOf(dark));

    // the attribute alone leaves the caption as it was drawn. of the ways to
    // ask for it again, this is the one windows 10 answers: SWP_FRAMECHANGED,
    // RedrawWindow and a resize all leave the old caption up
    SendMessage(Handle, WM_NCACTIVATE, 0, 0);
    SendMessage(Handle, WM_NCACTIVATE, 1, 0);
  finally
    FreeLibrary(lib);
  end;
{$endif}

{$ifdef LCLGTK2}
  // the decorations are the window manager's, and _GTK_THEME_VARIANT is what
  // it reads to pick the dark variant of its theme
  var top := gtk_widget_get_toplevel(PGtkWidget(Handle));
  if (top = nil) or (top^.window = nil) then Exit;

  var dpy := gdk_x11_drawable_get_xdisplay(PGdkDrawable(top^.window));
  var xid := GDK_WINDOW_XID(PGdkDrawable(top^.window));
  var name: string := if st.theme = utDark then 'dark' else 'light';
  XChangeProperty(dpy, xid, XInternAtom(dpy, '_GTK_THEME_VARIANT', False),
    XInternAtom(dpy, 'UTF8_STRING', False), 8, PropModeReplace, Pcuchar(PChar(name)), Length(name));
{$endif}
end;

// a rebuilt document knows nothing of the pointer, so what it is over would
// only light up again on the next mouse move: it is told here instead
procedure TMainForm.restoreHover;
begin
  if (view.Document = nil) or (FMouseX < 0) then Exit;
  var scale := 1.0;
  if view.Document.Width > 0 then scale := view.ClientWidth/view.Document.Width;
  if scale <= 0 then scale := 1;

  var vx := Round(FMouseX/scale);
  var vy := Round(FMouseY/scale);
  var boxes := autofree TPixiePositionVector.Create;
  if view.Document.OnMouseOver(vx, vy+view.ScrollY, vx, vy, boxes) then view.Invalidate;
end;

procedure TMainForm.logTimerTimer(Sender: TObject);
begin
  if FMouseDown or FLiveBusy then Exit;
  // a download reports progress far more often than it writes a line, and
  // rebuilding the log for a moved progress bar is what made it flicker
  var withLog := FLogDirty;
  if (not withLog) and (not FStatusDirty) then Exit;
  FLogDirty := False;
  FStatusDirty := False;
  renderLive(withLog);
end;

// the tick boxes are rebuilt from the flags they mirror, so the page and the
// install config can never drift apart
procedure TMainForm.buildChecks;
begin
  var live := st.fpcOn and st.inputsOn;
  var win64 := 'x86_64-win64';
  var linux64 := 'x86_64-linux';
  if FNativeWin64 then win64 := win64+' (native)';
  if FNativeLinux64 then linux64 := linux64+' (native)';

  SetLength(st.crosses, 5);
  st.crosses[0] := check('crosswin64', win64, '', '', FCrossWin64 or FNativeWin64, live and (not FNativeWin64));
  st.crosses[1] := check('crosslinux64', linux64, '', '', FCrossLinux64 or FNativeLinux64, live and (not FNativeLinux64));
  st.crosses[2] := check('crosswin32', 'i386-win32', '', '', FCrossWin32, live);
  st.crosses[3] := check('crosslinux32', 'i386-linux', 'requires i386-win32', '', FCrossLinux32, live);
  st.crosses[4] := check('crosswasm', 'wasm32-wasip1', '', '', FCrossWasm, live);

  var ide := st.lazOn and st.inputsOn;
  SetLength(st.addons, 5);
  st.addons[0] := check('minimap', 'Minimap', 'source editor side panel', '', FMinimap, ide);
  st.addons[1] := check('cpuview', 'CPU-View', 'debugger', 'https://github.com/AlexanderBagel/CPUView', FCpuView, ide);
  st.addons[2] := check('metadark', 'MetaDarkStyle', 'dark theme', 'https://github.com/zamtmn/metadarkstyle', FMetaDark, ide);
  st.addons[3] := check('helpfiles', 'Help files (CHM)', 'help viewer and offline docs', '', FHelpFiles, ide);
  {$ifdef WINDOWS}
  st.addons[4] := check('affinity', 'Toggle Display Affinity', 'hides the IDE from screen capture', '', FToggleAffinity, ide);
  {$else}
  st.addons[4] := check('affinity', 'Toggle Display Affinity', 'windows only', '', False, False);
  {$endif}

  SetLength(st.shortcuts, 3);
  st.shortcuts[0] := check('desktopsc', 'Desktop shortcut', '', '', FDesktopShortcut, ide);
  st.shortcuts[1] := check('foldersc', 'Shortcut in the install folder', '', '', FFolderShortcut, ide);
  // launch-after stays live during the install: the user may change their mind
  st.shortcuts[2] := check('launch', 'Launch the IDE when done', '', '', FLaunchAfter, st.lazOn);
end;

// the engine is still walking the DOM when a handler runs, so the page is
// rebuilt once the event has returned
procedure TMainForm.queueRender;
begin
  if FRenderQueued then Exit;
  FRenderQueued := True;
  Application.QueueAsyncCall(@asyncRender, 0);
end;

procedure TMainForm.asyncRender(data: PtrInt);
begin
  FRenderQueued := False;
  render;
end;

procedure TMainForm.render;
begin
  buildChecks;
  st.installing := FInstalling;
  st.canInstall := (FFetchPending = 0) and (not FInstalling);
  st.fitting := FSizeToContent;

  // the rebuild throws the old document away, so where the caret was sitting
  // has to be carried over by hand
  var focusId := '';
  var caret := 0;
  if view.Document <> nil then
  begin
    var was := view.Document.FocusedElement;
    if was is TPixieElTextBase then
    begin
      focusId := TPixieHtmlTag(was).GetAttr('id');
      caret := TBoxAccess(was).FCaretPos;
    end;
  end;

  // the view lays out at the width it had, so the old document carries it over
  var layoutWidth := 0.0;
  if view.Document <> nil then layoutWidth := view.Document.Width;

  view.LoadFromString(buildPage(st));

  if (focusId <> '') and (view.Document <> nil) then
  begin
    var box := view.Document.GetElementById(focusId);
    if box is TPixieElTextBase then
    begin
      view.Document.SetFocus(box);
      if caret > Length(TPixieElTextBase(box).Value) then caret := Length(TPixieElTextBase(box).Value);
      TBoxAccess(box).FCaretPos := caret;
    end;
  end;
  settleDocument(layoutWidth);
end;

// while an install runs only the log, the status and the progress move, and
// they are written into the page that is already up: a fresh document would
// drop what the pointer is over and what the log pane is scrolled to. building
// the log html is the costly half, so it runs on a worker
procedure TMainForm.renderLive(withLog: Boolean);
begin
  if view.Document = nil then begin render; Exit; end;

  var status := sanitize(st.status);
  var percent := barWidth(st);
  if not withLog then begin applyLive('', status, percent, False); Exit; end;

  FLiveBusy := True;
  // the log is appended on this thread, so the worker gets its own copy
  var tail := TStringList.Create;
  tail.Assign(FLog);

  async begin
    try
      var linesHtml := logLinesHtml(tail);
      sync applyLive(linesHtml, status, percent, True);
    finally
      tail.Free;
      FLiveBusy := False;
    end;
  end;
end;

procedure TMainForm.applyLive(const linesHtml, statusText: string; percent: integer; withLog: Boolean);
begin
  var doc := view.Document;
  if FClosing or (doc = nil) then Exit;

  doc.BeginUpdate;
  if withLog then
  begin
    var log := doc.GetElementById('log');
    if log <> nil then doc.SetInnerHtml(log, linesHtml);
  end;
  var el := doc.GetElementById('status');
  if el <> nil then doc.SetElementText(el, statusText);
  el := doc.GetElementById('fill');
  if el <> nil then
  begin
    el.SetAttr('style', 'width: '+IntToStr(percent)+'%');
    doc.Changed;
  end;
  doc.EndUpdate;

  settleDocument(doc.Width);
end;

end.
