{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit branch_cache;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

const
  // Plain-text key=value file next to the running exe holding both
  // repos' branch name lists plus a `Cached at:` timestamp. Re-running
  // the installer inside CACHE_TTL_MINUTES of that timestamp loads the
  // lists from disk instead of hitting GitHub. The file is owned by
  // the installer and gitignored.
  CACHE_FILENAME = 'cache-git-branches';
  CACHE_TTL_MINUTES = 5;

// Load both branch lists plus the per-repo HEAD SHA of `main`. Returns
// True iff the file exists, parses, and has the `Cached at:` timestamp;
// AgeMinutes is filled with the age (in minutes) of that timestamp
// relative to Now. FpcMainSha / IdeMainSha are filled when the file has
// those fields, '' otherwise. On True, caller compares AgeMinutes to
// CACHE_TTL_MINUTES to decide fresh-use vs stale-fallback. The lists
// are always cleared first; on False they end up empty.
function LoadCache(FpcBranches, IdeBranches: TStringList;
  out AgeMinutes: Double;
  out FpcMainSha, IdeMainSha: string): Boolean;

// Write both branch lists plus per-repo HEAD-of-`main` SHAs to the
// cache file with the current local timestamp. Source lists must be
// in 'name=sha' form (TStrings with Names[i] = branch name, Values[name]
// = SHA) so SaveCache can pull both the names and the SHA of the main
// branch in a single pass. Branches with no SHA in the source list
// just get their name written.
procedure SaveCache(FpcBranches, IdeBranches: TStrings);

implementation

uses
  DateUtils;

const
  FPC_PREFIX      = 'fpc-branches=';
  IDE_PREFIX      = 'ide-branches=';
  // Per-branch SHA-1 keys are prefixed `sha1-<repo>-<branch>=` so the
  // schema scales: only the main branches are written today, but a
  // future "preload heads for these N branches" feature could add
  // sha1-fpc-devel=..., sha1-ide-feat-x=..., etc. without breaking
  // older installers that just ignore unknown keys.
  FPC_HASH_PREFIX = 'sha1-fpc-main=';
  IDE_HASH_PREFIX = 'sha1-ide-main=';
  // `Cached at:` is a true comment line: the parser still has to
  // extract a timestamp from it for the freshness check, but visually
  // it sits in the header block with the rule-of-thumb message so a
  // user reading the file sees both together.
  TS_PREFIX       = '# Cached at: ';
  HEADER          = '# We recently checked repos branches, give them a rest for at least 5 minutes.';
  TS_FORMAT       = 'yyyy-mm-dd hh:nn:ss';
  MAIN_BRANCH     = 'main';

function CacheFilePath: string;
begin
  Result := ExtractFilePath(ParamStr(0))+CACHE_FILENAME;
end;

// Split a "a, b, c" string into Dest. Empty tokens are skipped so an
// empty branch list (or a trailing comma) doesn't produce phantom
// entries; whitespace around each name is trimmed.
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

function LoadCache(FpcBranches, IdeBranches: TStringList;
  out AgeMinutes: Double;
  out FpcMainSha, IdeMainSha: string): Boolean;
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
    // Timestamp lives in a `# Cached at: ...` comment line, so check
    // for it before the generic "skip comments" branch. Other lines
    // starting with `#` are free-form text and ignored.
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

  // Join a TStrings into "a, b, c". Reads Names[i] when the entry is a
  // 'name=sha' pair (so caller passes FFpcBranchShas directly) and the
  // raw entry otherwise. Branch names list intentionally drops the
  // per-branch SHAs -- only the HEAD-of-main SHA is preserved, in its
  // own line below.
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

  // Pull the SHA of the 'main' branch out of a 'name=sha' TStrings.
  // Returns '' when the list does not contain 'main' or its SHA is
  // blank (cache-hit-fed list where SHAs were not preserved last run).
  function MainSha(L: TStrings): string;
  begin
    Result := '';
    for var i := 0 to L.Count-1 do
      if SameText(L.Names[i], MAIN_BRANCH) then begin
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

