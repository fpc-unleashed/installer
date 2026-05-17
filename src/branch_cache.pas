{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit branch_cache;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

const
  // plain-text key=value cache file next to the exe; fresh within CACHE_TTL_MINUTES
  CACHE_FILENAME = 'cache-git-branches';
  CACHE_TTL_MINUTES = 5;

// load branch lists + per-repo HEAD-of-main SHA; AgeMinutes vs CACHE_TTL_MINUTES decides freshness
function LoadCache(FpcBranches, IdeBranches: TStringList; out AgeMinutes: Double; out FpcMainSha, IdeMainSha: string): Boolean;

// write branch lists + per-repo HEAD-of-main SHA with current timestamp
procedure SaveCache(FpcBranches, IdeBranches: TStrings);

implementation

uses
  DateUtils;

const
  FPC_PREFIX      = 'fpc-branches=';
  IDE_PREFIX      = 'ide-branches=';
  // schema scales: future preload-heads keys like sha1-fpc-devel= just slot in next to these
  FPC_HASH_PREFIX = 'sha1-fpc-main=';
  IDE_HASH_PREFIX = 'sha1-ide-main=';
  // parser still extracts the timestamp from this comment line
  TS_PREFIX       = '# Cached at: ';
  HEADER          = '# We recently checked repos branches, give them a rest for at least 5 minutes.';
  TS_FORMAT       = 'yyyy-mm-dd hh:nn:ss';
  MAIN_BRANCH     = 'main';

function CacheFilePath: string;
begin
  Result := ExtractFilePath(ParamStr(0))+CACHE_FILENAME;
end;

// split "a, b, c" into Dest; empty tokens skipped, whitespace trimmed
procedure ParseCommaList(const Value: string; Dest: TStringList);
begin
  Dest.Clear;
  var i := 1;
  var L := Length(Value);
  while i <= L do begin
    while (i <= L) and ((Value[i] = ' ') or (Value[i] = #9)) do Inc(i);
    var startPos := i;
    while (i <= L) and (Value[i] <> ',') do Inc(i);
    var token := Trim(Copy(Value, startPos, i-startPos));
    if token <> '' then Dest.Add(token);
    if (i <= L) and (Value[i] = ',') then Inc(i);
  end;
end;

function LoadCache(FpcBranches, IdeBranches: TStringList; out AgeMinutes: Double; out FpcMainSha, IdeMainSha: string): Boolean;
begin
  Result := False;
  AgeMinutes := 1e9;
  FpcMainSha := '';
  IdeMainSha := '';
  FpcBranches.Clear;
  IdeBranches.Clear;
  if not FileExists(CacheFilePath) then Exit;

  var lines := autofree TStringList.Create;
  try
    lines.LoadFromFile(CacheFilePath);
  except
    Exit;
  end;

  var fpcLine := '';
  var ideLine := '';
  var gotTimestamp := False;
  var cachedAt: TDateTime := 0;

  for var i := 0 to lines.Count-1 do begin
    var ln := Trim(lines[i]);
    if ln = '' then Continue;
    // `# Cached at: ...` is a real comment but holds the freshness stamp; check before the generic skip
    if Pos(TS_PREFIX, ln) = 1 then begin
      try
        cachedAt := ScanDateTime(TS_FORMAT, Copy(ln, Length(TS_PREFIX)+1, MaxInt));
        gotTimestamp := True;
      except
        Exit;
      end;
      Continue;
    end;
    if ln[1] = '#' then Continue;
    if Pos(FPC_PREFIX, ln) = 1 then fpcLine := Copy(ln, Length(FPC_PREFIX)+1, MaxInt)
    else if Pos(IDE_PREFIX, ln) = 1 then ideLine := Copy(ln, Length(IDE_PREFIX)+1, MaxInt)
    else if Pos(FPC_HASH_PREFIX, ln) = 1 then FpcMainSha := LowerCase(Trim(Copy(ln, Length(FPC_HASH_PREFIX)+1, MaxInt)))
    else if Pos(IDE_HASH_PREFIX, ln) = 1 then IdeMainSha := LowerCase(Trim(Copy(ln, Length(IDE_HASH_PREFIX)+1, MaxInt)));
  end;

  if not gotTimestamp then Exit;
  AgeMinutes := MinutesBetween(Now, cachedAt);

  ParseCommaList(fpcLine, FpcBranches);
  ParseCommaList(ideLine, IdeBranches);
  Result := True;
end;

procedure SaveCache(FpcBranches, IdeBranches: TStrings);

  // join into "a, b, c"; reads Names[i] on 'name=sha' pairs, raw entry otherwise
  function JoinNames(L: TStrings): string;
  begin
    Result := '';
    for var i := 0 to L.Count-1 do begin
      var entry := L[i];
      if Pos('=', entry) > 0 then entry := L.Names[i];
      if entry = '' then Continue;
      if Result <> '' then Result := Result+', ';
      Result := Result+entry;
    end;
  end;

  // SHA of 'main' from a 'name=sha' TStrings, '' if absent or blank
  function MainSha(L: TStrings): string;
  begin
    Result := '';
    for var i := 0 to L.Count-1 do if SameText(L.Names[i], MAIN_BRANCH) then begin
      Result := L.ValueFromIndex[i];
      Exit;
    end;
  end;

begin
  var f := autofree TStringList.Create;
  f.Add(HEADER);
  f.Add(TS_PREFIX+FormatDateTime(TS_FORMAT, Now));
  f.Add('');
  f.Add(FPC_PREFIX+JoinNames(FpcBranches));
  f.Add(IDE_PREFIX+JoinNames(IdeBranches));
  f.Add(FPC_HASH_PREFIX+MainSha(FpcBranches));
  f.Add(IDE_HASH_PREFIX+MainSha(IdeBranches));
  try
    f.SaveToFile(CacheFilePath);
  except
    // best effort; on failure we just refetch next run
  end;
end;

end.
