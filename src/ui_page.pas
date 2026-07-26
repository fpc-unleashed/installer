{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit ui_page;

{$mode unleashed}

// the window is one HTML document drawn by pixie. this unit turns the state
// main_form holds into that document and knows nothing about the install.
//
// every clickable element carries data-act, and the handler in main_form walks
// the click up to the first ancestor that has one.

interface

uses
  Classes, SysUtils;

const
  // the log pane keeps the tail; the whole log lives in main_form and goes to
  // the log file, but laying out tens of thousands of lines costs too much
  LOG_TAIL = 400;

type
  TUiTheme = (utLight, utDark);

  // umNote just says something, the rest carry an action the OK button fires
  TUiModalKind = (umNone, umNote, umConfirm, umText);

  TUiModal = record
    kind: TUiModalKind;
    title: string;
    text: string;
    body: string;
    okAct: string;
    okLabel: string;
  end;

  TUiCheck = record
    act: string;
    caption: string;
    hint: string;
    link: string;
    on: boolean;
    enabled: boolean;
  end;

  TUiChecks = array of TUiCheck;

  TUiState = record
    theme: TUiTheme;
    title: string;
    // target folder
    targetDir: string;
    mode: string;
    modeBad: boolean;
    installLabel: string;
    canInstall: boolean;
    installing: boolean;
    inputsOn: boolean;
    // fpc half
    fpcOn: boolean;
    fpcBranch: string;
    fpcBranches: TStringList;
    fpcReady: boolean;
    fpcLatest: boolean;
    fpcHash: string;
    crosses: TUiChecks;
    // lazarus half
    lazOn: boolean;
    lazBranch: string;
    lazBranches: TStringList;
    lazReady: boolean;
    lazLatest: boolean;
    lazHash: string;
    addons: TUiChecks;
    shortcuts: TUiChecks;
    shortcutWarn: string;
    // log and progress
    log: TStringList;
    saveLog: boolean;
    status: string;
    percent: integer;
    openDrop: string;
    modal: TUiModal;
    // one pass with the page free to be as tall as it wants, so the first-run
    // window can be sized to it
    fitting: boolean;
  end;

function esc(const s: string): string;
function sanitize(const s: string): string;
function barWidth(const st: TUiState): integer;
function logLinesHtml(log: TStrings): string;
function buildLogLines(const st: TUiState): string;
function buildPage(const st: TUiState): string;

implementation

const
  // every colour is a token the theme fills in. longer tokens come first, so
  // that "@accent" does not eat the front of "@accentsoft"
  TOKENS: array[24] of string = (
    '@accentsoft', '@accent2', '@accent', '@onaccent', '@bg', '@panel', '@border', '@line', '@text', '@muted',
    '@dim', '@hover2', '@hover', '@rowhover', '@head2', '@head', '@input', '@ok', '@okbg', '@warn', '@warnbg', '@bad', '@badbg', '@navy');

  LIGHT: array[24] of string = (
    '#eef0ff', '#3730a3', '#4f46e5', '#ffffff', '#eef1f5', '#ffffff', '#dfe3e8', '#f0f2f5', '#1f2430', '#5b6472',
    '#9aa1ab', '#c3ccdb', '#dbe2ec', '#eaeef4', '#e9ecf1', '#f6f7f9', '#ffffff', '#047857', '#ecfdf5', '#b45309', '#fff7ed', '#b91c1c', '#fef2f2', '#1d4ed8');

  DARK: array[24] of string = (
    '#272c3d', '#a5b4fc', '#818cf8', '#14161a', '#14161a', '#1c1f26', '#2c313b', '#23272f', '#e5e7eb', '#a5adb9',
    '#6f7885', '#4b5566', '#3a4454', '#2a303b', '#2b323d', '#21252d', '#14161a', '#34d399', '#12291f', '#fbbf24', '#2a2113', '#f87171', '#2c1618', '#93b4ff');

  CSS =
    '''
    * { box-sizing: border-box; cursor: default; user-select: none; }
    input, textarea { cursor: text; user-select: text; }
    .log, .lg { user-select: text; }
    body { display: flex; flex-direction: column; height: 100vh; margin: 0; overflow: hidden; background: @bg; color: @text; font-family: "Segoe UI", system-ui, sans-serif; font-size: 12px; }
    .top { flex-shrink: 0; display: flex; align-items: center; background: @panel; border-bottom: 1px solid @border; padding: 5px 10px; }
    .logo { font-size: 13px; font-weight: 600; color: @accent; margin-right: 10px; }
    .ver { color: @dim; flex-grow: 1; }
    .menu { flex-shrink: 0; display: flex; background: @panel; border-bottom: 1px solid @border; padding: 4px 8px; }
    .btn { padding: 3px 9px; margin-right: 4px; border: 1px solid @border; border-radius: 3px; background: @panel; color: @text; white-space: nowrap; }
    .btn:hover { background: @hover; border-color: @dim; }
    .btn:active { background: @hover2; }
    .btn.pri { background: @accent; border-color: @accent; color: @onaccent; }
    .btn.pri:hover { background: @accent2; border-color: @accent2; }
    .btn.off { color: @dim; background: @head; border-color: @border; }
    .btn.off:hover { background: @head; border-color: @border; }
    .btn.flat { border-color: @panel; background: @panel; }
    .btn.flat:hover { background: @hover; border-color: @dim; }
    .cols { flex-grow: 1; min-height: 0; display: flex; padding: 8px; }
    .col { flex-grow: 1; flex-shrink: 1; flex-basis: 0; min-width: 0; min-height: 0; display: flex; flex-direction: column; }
    .col.left { flex-grow: 0; flex-shrink: 0; flex-basis: 520px; width: 520px; margin-right: 8px; overflow-y: auto; }
    .card { background: @panel; border: 1px solid @border; border-radius: 4px; margin-bottom: 8px; }
    .card.logcard { flex-grow: 1; min-height: 0; display: flex; flex-direction: column; margin-bottom: 0; }
    .card h2 { font-size: 10px; text-transform: uppercase; letter-spacing: 1px; color: @dim; font-weight: 600; margin: 0; padding: 6px 9px; border-bottom: 1px solid @line; }
    .pad { padding: 7px 9px; }
    .row { display: flex; align-items: flex-start; margin-bottom: 5px; }
    .grow { flex-grow: 1; flex-shrink: 1; flex-basis: 0; min-width: 0; }
    .lbl { width: 110px; color: @muted; padding-top: 3px; }
    input { padding: 3px 7px; width: 100%; border: 1px solid @border; border-radius: 3px; background: @input; color: @text; font-family: Consolas, monospace; }
    input:hover { background: @rowhover; border-color: @dim; }
    input:focus { background: @input; border-color: @accent; }
    input.off { color: @dim; background: @head; }
    input.off:hover { background: @head; border-color: @border; }
    .chk { display: flex; align-items: flex-start; padding: 2px 3px; margin-bottom: 2px; border-radius: 2px; }
    .chk:hover { background: @rowhover; }
    .chk.off:hover { background: transparent; }
    .chk .box { width: 13px; height: 13px; margin: 2px 7px 0 0; border: 1px solid @dim; border-radius: 2px; background: @input; color: @onaccent; text-align: center; font-size: 10px; }
    .chk.on .box { background: @accent; border-color: @accent; }
    .chk.off { color: @dim; }
    .chk.off .box { border-color: @border; background: @head; }
    .chk.off.on .box { border-color: @dim; background: @dim; color: @panel; }
    .chk .hint { color: @dim; margin-left: 6px; }
    .tight { flex-grow: 1; flex-shrink: 1; min-width: 0; margin-right: 10px; white-space: nowrap; }
    .lnk { color: @navy; margin-left: 6px; }
    .lnk:hover { color: @accent; }
    .mode { padding: 4px 9px; color: @muted; }
    .mode.bad { color: @bad; }
    .warn { margin: 5px 0 2px 0; padding: 6px 8px; border-radius: 3px; background: @badbg; color: @bad; font-weight: 600; }
    .drop { position: relative; margin-right: 4px; }
    .dropbtn { padding: 3px 9px; border: 1px solid @border; border-radius: 3px; background: @panel; white-space: nowrap; }
    .dropbtn:hover { background: @hover; border-color: @dim; }
    .dropbtn.off { color: @dim; background: @head; }
    .seg { display: flex; align-items: center; padding: 1px; border: 1px solid @border; border-radius: 3px; background: @head; }
    .seg .opt { padding: 2px 10px; border-radius: 2px; color: @muted; }
    .seg .opt:hover { background: @hover; color: @text; }
    .seg .opt.on { background: @accent; color: @onaccent; font-weight: 600; }
    .seg .opt.on:hover { background: @accent; color: @onaccent; }
    .seg .sep { color: @dim; }
    .car { color: @dim; margin-left: 6px; }
    .drop .items { position: absolute; z-index: 30; width: 240px; margin-top: 2px; padding: 3px; background: @panel; border: 1px solid @border; border-radius: 3px; }
    .drop .items div { padding: 3px 7px; border-radius: 3px; }
    .drop .items div:hover { background: @hover; }
    .drop .items div.on { color: @accent; font-weight: 600; }
    .log { flex-grow: 1; min-height: 0; overflow-y: auto; padding: 5px 7px; font-family: Consolas, monospace; font-size: 11px; }
    .lg { padding: 0 2px; white-space: pre-wrap; overflow-wrap: anywhere; }
    .lg.err { color: @bad; }
    .lg.warn2 { color: @warn; }
    .lg.head { color: @navy; }
    .lg.step { color: @ok; }
    .lg.make { color: @dim; }
    .lg.bang { background: @warnbg; color: @warn; font-weight: 600; }
    .bar { flex-shrink: 0; background: @panel; border-top: 1px solid @border; padding: 7px 10px; }
    .bar .line { display: flex; align-items: center; }
    .track { flex-grow: 1; flex-shrink: 1; flex-basis: 0; height: 8px; margin-right: 10px; border-radius: 4px; background: @head; border: 1px solid @border; }
    .fill { height: 6px; border-radius: 3px; background: @accent; }
    .status { flex-shrink: 0; width: 360px; margin-right: 10px; color: @muted; text-align: right; white-space: nowrap; overflow: hidden; }
    .overlay { position: fixed; left: 0; top: 0; right: 0; bottom: 0; z-index: 20; background: rgba(0, 0, 0, 0.35); }
    .modal { width: 560px; margin: 70px auto 0 auto; background: @panel; border: 1px solid @border; border-radius: 4px; }
    .modal h2 { font-size: 12px; text-transform: none; letter-spacing: 0; color: @text; font-weight: 600; margin: 0; padding: 8px 11px; border-bottom: 1px solid @line; }
    .modal .mtext { padding: 11px; color: @muted; }
    .modal .acts { border-top: 1px solid @line; padding: 8px 11px; display: flex; }
    body.fit { height: auto; overflow: visible; }
    body.fit .cols { flex-grow: 0; }
    body.fit .col.left { overflow-y: visible; }
    body.fit .log { overflow-y: visible; }
    .license { margin: 0 11px 11px 11px; padding: 7px 9px; height: 300px; width: 536px; border: 1px solid @border; border-radius: 3px; background: @input; color: @muted; font-family: Consolas, monospace; font-size: 11px; }
    ''';

function themeCss(theme: TUiTheme): string;
begin
  result := CSS;
  for var i := 0 to high(TOKENS) do
    if theme = utDark then result := StringReplace(result, TOKENS[i], DARK[i], [rfReplaceAll])
    else result := StringReplace(result, TOKENS[i], LIGHT[i], [rfReplaceAll]);
end;

// how many bytes the utf-8 sequence starting here takes, or 0 when the bytes do
// not form one
function utf8Run(const s: string; at: integer): integer;
begin
  var lead := ord(s[at]);
  var need := 0;
  if lead < $80 then exit(1)
  else if (lead >= $C2) and (lead <= $DF) then need := 1
  else if (lead >= $E0) and (lead <= $EF) then need := 2
  else if (lead >= $F0) and (lead <= $F4) then need := 3
  else exit(0);

  if at+need > Length(s) then exit(0);
  for var i := 1 to need do
    if (ord(s[at+i]) and $C0) <> $80 then exit(0);
  result := need+1;
end;

// the engine reads the page as utf-8, so a raw byte that is not part of a valid
// sequence swallows the markup that follows it. make and curl put whatever the
// tool wrote into the log, so every string is filtered on the way in
function sanitize(const s: string): string;
begin
  result := '';
  var i := 1;
  while i <= Length(s) do
  begin
    var c: char := s[i];
    var run := utf8Run(s, i);
    if (run = 0) or ((c < ' ') and (c <> #9) and (c <> #10) and (c <> #13)) then
    begin
      result := result+'\x'+IntToHex(ord(c), 2);
      inc(i);
      continue;
    end;
    result := result+Copy(s, i, run);
    inc(i, run);
  end;
end;

function esc(const s: string): string;
begin
  result := StringReplace(sanitize(s), '&', '&amp;', [rfReplaceAll]);
  result := StringReplace(result, '<', '&lt;', [rfReplaceAll]);
  result := StringReplace(result, '>', '&gt;', [rfReplaceAll]);
  result := StringReplace(result, '"', '&quot;', [rfReplaceAll]);
end;

function button(const act, caption: string; enabled: boolean; primary: boolean=false; flat: boolean=false): string;
begin
  var cls := 'btn';
  if primary then cls := cls+' pri';
  if flat then cls := cls+' flat';
  if not enabled then exit($'<div class="{cls} off">{esc(caption)}</div>');
  result := $'<div class="{cls}" data-act="{act}">{esc(caption)}</div>';
end;

// a dropdown carries its own open state: it is drawn open only while openDrop
// names it, and it opens in the flow so the mouse can reach its items
function dropdown(const st: TUiState; const id, act, caption: string; items: TStrings; const selected: string; enabled: boolean): string;
begin
  var cls := 'dropbtn';
  if not enabled then cls := cls+' off';
  var head := $'<div class="{cls}">{esc(caption)}<span class="car">&#9662;</span></div>';
  if enabled then head := $'<div class="{cls}" data-act="drop" data-name="{id}">{esc(caption)}<span class="car">&#9662;</span></div>';

  result := $'<div class="drop">{head}';
  if (not enabled) or (st.openDrop <> id) or (items = nil) then exit(result+'</div>');

  result := result+'<div class="items">';
  for var i := 0 to items.Count-1 do
  begin
    var on := '';
    if items[i] = selected then on := ' class="on"';
    result := result+$'<div{on} data-act="{act}" data-name="{esc(items[i])}">{esc(items[i])}</div>';
  end;
  result := result+'</div></div>';
end;

function checkbox(const c: TUiCheck): string;
begin
  var cls := 'chk';
  var mark := '';
  if c.on then begin cls := cls+' on'; mark := '&#10003;'; end;
  if not c.enabled then cls := cls+' off';

  var tail := '';
  if c.hint <> '' then tail := $'<span class="hint">{esc(c.hint)}</span>';
  if c.link <> '' then tail := tail+$'<span class="lnk" data-act="url" data-name="{esc(c.link)}">{esc(c.link)}</span>';

  var body := $'<div class="box">{mark}</div><div>{esc(c.caption)}{tail}</div>';
  if not c.enabled then exit($'<div class="{cls}">{body}</div>');
  result := $'<div class="{cls}" data-act="{c.act}">{body}</div>';
end;

function checkList(const list: TUiChecks): string;
begin
  result := '';
  for var c in list do result := result+checkbox(c);
end;

function buildMenu(const st: TUiState): string;
begin
  var files := autofree TStringList.Create;
  files.Add('Exit');
  var repos := autofree TStringList.Create;
  repos.Add('Unleashed GitHub Organization');
  repos.Add('Unleashed Compiler');
  repos.Add('Unleashed IDE');
  repos.Add('Unleashed Pascal Installer');
  var help := autofree TStringList.Create;
  help.Add('Documentation');
  help.Add('About');

  var lightCls := '';
  var darkCls := '';
  if st.theme = utDark then darkCls := ' on' else lightCls := ' on';

  var seg := $'<div class="seg"><div class="opt{lightCls}" data-act="themelight">Light</div>'+
    '<div class="sep">|</div>'+
    $'<div class="opt{darkCls}" data-act="themedark">Dark</div></div>';

  result := '<div class="menu">'+
    dropdown(st, 'file', 'menufile', 'File', files, '', true)+
    dropdown(st, 'repo', 'menurepo', 'Repositories', repos, '', true)+
    dropdown(st, 'help', 'menuhelp', 'Help', help, '', true)+
    '<div class="grow"></div>'+
    seg+
    '</div>';
end;

function buildTarget(const st: TUiState): string;
begin
  var cls := 'mode';
  if st.modeBad then cls := cls+' bad';
  var browse := button('browse', 'Browse...', st.inputsOn);
  var box := $'<input type="text" id="targetDir" value="{esc(st.targetDir)}">';
  if not st.inputsOn then box := $'<input type="text" class="off" readonly value="{esc(st.targetDir)}">';

  result := '<div class="card"><h2>where to install</h2><div class="pad">'+
    $'<div class="row"><div class="grow">{box}</div>{browse}</div>'+
    $'</div><div class="{cls}">{esc(st.mode)}</div></div>';
end;

function buildRepoCard(const st: TUiState; fpc: boolean): string;
begin
  var master: TUiCheck;
  var branch, hash, hashId, dropId, actBranch, actLatest, hint: string;
  var latest, ready, on: boolean;
  var list: TStringList;

  if fpc then
  begin
    master.act := 'togglefpc';
    master.caption := 'Install FPC Unleashed';
    on := st.fpcOn;
    branch := st.fpcBranch;
    list := st.fpcBranches;
    ready := st.fpcReady;
    latest := st.fpcLatest;
    hash := st.fpcHash;
    hashId := 'fpcHash';
    dropId := 'fpcbranch';
    actBranch := 'pickfpcbranch';
    actLatest := 'togglefpclatest';
    hint := 'the compiler, its RTL and the cross targets below';
  end
  else begin
    master.act := 'togglelaz';
    master.caption := 'Install Lazarus IDE';
    on := st.lazOn;
    branch := st.lazBranch;
    list := st.lazBranches;
    ready := st.lazReady;
    latest := st.lazLatest;
    hash := st.lazHash;
    hashId := 'lazHash';
    dropId := 'lazbranch';
    actBranch := 'picklazbranch';
    actLatest := 'togglelazlatest';
    hint := 'the IDE, its packages and the add-ons below';
  end;

  master.on := on;
  master.enabled := st.inputsOn;
  master.hint := hint;
  master.link := '';

  var live := on and st.inputsOn;
  var latestBox: TUiCheck;
  latestBox.act := actLatest;
  latestBox.caption := 'Latest commit of the branch';
  latestBox.hint := '';
  latestBox.link := '';
  latestBox.on := latest;
  latestBox.enabled := live;

  var hashBox := $'<input type="text" id="{hashId}" value="{esc(hash)}">';
  if latest or (not live) then hashBox := $'<input type="text" class="off" readonly value="{esc(hash)}">';

  var branchName := branch;
  if branchName = '' then branchName := '(no branch)';

  result := '<div class="card"><h2>'+
    (if fpc then 'compiler' else 'ide')+
    '</h2><div class="pad">'+
    checkbox(master)+
    '<div class="row" style="margin-top: 6px"><div class="lbl">branch</div><div class="grow">'+
    dropdown(st, dropId, actBranch, branchName, list, branch, live and ready)+
    '</div></div>'+
    checkbox(latestBox)+
    $'<div class="row" style="margin-top: 4px"><div class="lbl">commit</div><div class="grow">{hashBox}</div></div>';

  if fpc then result := result+'<div class="lbl" style="width: auto; margin-top: 6px">cross targets</div>'+checkList(st.crosses)
  else begin
    result := result+'<div class="lbl" style="width: auto; margin-top: 6px">add-ons</div>'+checkList(st.addons)+
      '<div class="lbl" style="width: auto; margin-top: 6px">shortcuts</div>'+checkList(st.shortcuts);
    if st.shortcutWarn <> '' then result := result+$'<div class="warn">{esc(st.shortcutWarn)}</div>';
  end;

  result := result+'</div></div>';
end;

// first match wins; ordered most-severe to least so "Error: warning" reads as
// an error, the same order the log had when it was drawn by hand
function logClass(const s: string): string;
begin
  if Pos('IMPORTANT', s) > 0 then exit('lg bang');
  if (Pos('Error', s) > 0) or (Pos('Fatal', s) > 0) or (Pos('FAILED', s) > 0) or (Pos('failed:', s) > 0) then exit('lg err');
  if Pos('Warning', s) > 0 then exit('lg warn2');
  if (Pos('===', s) > 0) or (Pos(' ---', s) > 0) then exit('lg head');
  if (Pos('Compiling ', s) > 0) or (Pos('Linking ', s) > 0) or (Pos('Installing ', s) > 0) then exit('lg step');
  if Pos('make[', s) > 0 then exit('lg make');
  result := 'lg';
end;

// the lines alone: while an install runs they are the only thing that changes,
// and main_form drops them straight into the log element. pure string work on
// a plain list, so a worker thread may run it on a snapshot of the log
function logLinesHtml(log: TStrings): string;
begin
  var count := 0;
  if log <> nil then count := log.Count;
  var first := count-LOG_TAIL;
  if first < 0 then first := 0;

  result := '';
  if count = 0 then result := '<div class="lg make">nothing logged yet</div>';
  if first > 0 then result := result+$'<div class="lg make">... {first} earlier line(s) not shown</div>';
  for var i := first to count-1 do
    result := result+$'<div class="{logClass(log[i])}">{esc(log[i])}</div>';
end;

function buildLogLines(const st: TUiState): string;
begin
  result := logLinesHtml(st.log);
end;

function buildLog(const st: TUiState): string;
begin
  var saveBox: TUiCheck;
  saveBox.act := 'togglesavelog';
  saveBox.caption := 'Write the log next to the install';
  saveBox.hint := '';
  saveBox.link := '';
  saveBox.on := st.saveLog;
  saveBox.enabled := st.inputsOn;

  var count := 0;
  if st.log <> nil then count := st.log.Count;

  result := '<div class="card logcard"><h2>log</h2><div class="pad" style="padding-bottom: 0">'+
    '<div class="row"><div class="tight">'+checkbox(saveBox)+'</div>'+
    button('copylog', 'Copy', count > 0)+button('clearlog', 'Clear', count > 0)+
    '</div></div><div class="log" id="log">'+buildLogLines(st)+'</div></div>';
end;

function barWidth(const st: TUiState): integer;
begin
  result := st.percent;
  if result < 0 then result := 0;
  if result > 100 then result := 100;
end;

function buildBar(const st: TUiState): string;
begin
  var width := barWidth(st);
  var install := button('install', st.installLabel, st.canInstall, true);
  result := '<div class="bar"><div class="line">'+
    $'<div class="track"><div class="fill" id="fill" style="width: {width}%"></div></div>'+
    $'<div class="status" id="status">{esc(st.status)}</div>{install}'+
    button('close', 'Close', true)+
    '</div></div>';
end;

function buildModal(const st: TUiState): string;
begin
  if st.modal.kind = umNone then exit('');

  var buttons := button(st.modal.okAct, st.modal.okLabel, true, true);
  if st.modal.kind <> umNote then buttons := buttons+button('modalclose', 'Cancel', true);

  result := $'<div class="overlay" data-act="modalstay"><div class="modal"><h2>{esc(st.modal.title)}</h2>'+
    $'<div class="mtext">{esc(st.modal.text)}</div>{st.modal.body}<div class="acts">{buttons}</div></div></div>';
end;

function buildPage(const st: TUiState): string;
begin
  var left := buildTarget(st)+buildRepoCard(st, true)+buildRepoCard(st, false);
  var right := buildLog(st);

  // the fit pass drops the viewport-tall layout so the page reports the height
  // it would like to have, which is what the window is then sized to
  var cls := '';
  if st.fitting then cls := ' class="fit"';

  result := $'<html><head><style>{themeCss(st.theme)}</style></head><body{cls} data-act="closedrop">'+
    $'<div class="top"><div class="logo">Unleashed Pascal</div><div class="ver">{esc(st.title)}</div></div>'+
    buildMenu(st)+
    $'<div class="cols"><div class="col left">{left}</div><div class="col">{right}</div></div>'+
    buildBar(st)+buildModal(st)+
    '</body></html>';
end;

end.
