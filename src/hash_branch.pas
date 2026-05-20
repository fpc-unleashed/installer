{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit hash_branch;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

// 32-bit MurmurHash3 over a Pascal AnsiString. PD reference algorithm by
// Austin Appleby; used here only as a deterministic short-name -> short-
// hex hash for branch-name encoding in release binary filenames. NOT for
// security; collisions are expected at 3-4 hex prefix and the encoder
// picks a longer prefix when current branch list contains collisions.
function Murmur3_32(const s: string; Seed: LongWord = 0): LongWord;

type
  // Result of parsing the filename-encoded pin blob. Wire format and
  // semantics are documented in README.md ("Filename hash pin").
  TParsedBinaryName = record
    Present: Boolean;
    FpcCommit: string;
    FpcBranchFromCommit: string;
    FpcBranchHashOverride: string;
    LazCommit: string;
    LazBranchFromCommit: string;
    LazBranchHashOverride: string;
  end;

// Parse a filename of the form "installer-anything-0000.exe" where some
// hex+digit run encodes the pin. The parser grabs the LAST hex+digit run
// in the filename (closest to extension) and tries to parse it. Any
// per-field error or trailing chars in the chosen run leaves
// Result.Present=False -- there is no fallback to an earlier run, so the
// run picked by the regex is the one and only candidate.
function ParseBinaryName(const FileName: string): TParsedBinaryName;

// Parse a single string as the encoded blob directly, without any run
// extraction or minimum-length floor. Used for the ParamStr(1) cmdline
// override path where the user explicitly hands the parser the blob and
// expects every char to be part of it. Returns False on any field-level
// failure or trailing chars.
function TryParseBlob(const blob: string; out p: TParsedBinaryName): Boolean;

// Resolve a murmur3 hex prefix to a branch name by scanning Items and
// returning the first match. Used by the UI after the async branch fetch
// populates the combo's Items so the filename-encoded hash can be turned
// into the actual branch name to select. Returns '' on no match.
function FindBranchByHashPrefix(Items: TStrings; const HexPrefix: string): string;

implementation

const
  // Indexed predefined branches surfaced via 0X encoding. Append-only: new
  // entries get higher indices so older encoded binaries keep parsing the
  // same way against any newer installer build.
  PREDEFINED_BRANCHES: array[0..1] of string = ('main', 'devel');

function Murmur3_32(const s: string; Seed: LongWord = 0): LongWord;
const
  C1: LongWord = $cc9e2d51;
  C2: LongWord = $1b873593;

  function rotl(x: LongWord; r: Byte): LongWord; inline;
  begin
    Result := (x shl r) or (x shr (32 - r));
  end;

begin
  {$push}{$Q-}{$R-}
  Result := Seed;
  var len := Length(s);
  var i := 1;
  while i+3 <= len do
  begin
    var k: LongWord :=  LongWord(Byte(s[i]))
                    or (LongWord(Byte(s[i+1])) shl 8)
                    or (LongWord(Byte(s[i+2])) shl 16)
                    or (LongWord(Byte(s[i+3])) shl 24);
    Result := rotl(Result xor (rotl(k * C1, 15) * C2), 13) * 5 + $e6546b64;
    Inc(i, 4);
  end;
  var rem := len - i+1;
  if rem > 0 then begin
    var k: LongWord := LongWord(Byte(s[i]));
    if rem >= 2 then k := k or (LongWord(Byte(s[i+1])) shl 8);
    if rem >= 3 then k := k or (LongWord(Byte(s[i+2])) shl 16);
    Result := Result xor (rotl(k * C1, 15) * C2);
  end;
  Result := Result xor LongWord(len);
  Result := Result xor (Result shr 16);
  Result := Result * LongWord($85ebca6b);
  Result := Result xor (Result shr 13);
  Result := Result * LongWord($c2b2ae35);
  Result := Result xor (Result shr 16);
  {$pop}
end;

// Collect every hex-character run of >= MinLen chars in s, in left-to-
// right order. Hex char set is [0-9a-fA-F]; runs are broken by any
// non-hex character (so version dots, dashes, underscores act as
// separators). The caller iterates these from right to left so the
// match closest to the file extension wins. Avoids pulling RegExpr
// into this unit for what is a single linear scan.
function CollectHexRuns(const s: string; MinLen: Integer): array of string;
begin
  SetLength(Result, 0);
  var i := 1;
  while i <= Length(s) do
  begin
    if s[i] in ['0'..'9', 'a'..'f', 'A'..'F'] then begin
      var startPos := i;
      while (i <= Length(s)) and (s[i] in ['0'..'9', 'a'..'f', 'A'..'F']) do
        Inc(i);
      if i - startPos >= MinLen then begin
        SetLength(Result, Length(Result)+1);
        Result[High(Result)] := Copy(s, startPos, i - startPos);
      end;
    end else
      Inc(i);
  end;
end;

function IsAllHex(const s: string): Boolean;
begin
  Result := False;
  if s = '' then Exit;
  for var i := 1 to Length(s) do
    if not (s[i] in ['0'..'9', 'a'..'f', 'A'..'F']) then Exit;
  Result := True;
end;

// Convert a single hex digit char to its 0..15 integer value, or -1 on
// non-hex. Cheaper / clearer than fishing a single char through StrToInt
// or chaining Ord arithmetic three times at every call site.
function HexCharToInt(c: Char): Integer;
begin
  if (c >= '0') and (c <= '9') then Result := Ord(c) - Ord('0')
  else if (c >= 'a') and (c <= 'f') then Result := Ord(c) - Ord('a')+10
  else if (c >= 'A') and (c <= 'F') then Result := Ord(c) - Ord('A')+10
  else Result := -1;
end;

// Read one commit-position field (pos 1 or 2 in the blob).
//   '0X'        -- predefined namespace, X in {0,1} -> branch main/devel,
//                  commit = "latest of that branch" (commitHex stays '')
//   '<L><Lhex>' -- L in 1..9, that many hex chars follow = commit SHA
//                  prefix pin; branch from this field is implicitly 'main'
// Returns False on any malformed / EOF / out-of-range case. On success
// pos is advanced and commitHex / branchFromCommit are populated.
function ReadCommitField(const blob: string; var pos: Integer;
  out commitHex, branchFromCommit: string): Boolean;
begin
  Result := False;
  commitHex := '';
  branchFromCommit := '';
  if pos > Length(blob) then Exit;
  if not (blob[pos] in ['0'..'9']) then Exit;
  if blob[pos] = '0' then begin
    // predefined namespace: 1 length digit + 1 hex char index into table
    if pos+1 > Length(blob) then Exit;
    var idx: Integer := HexCharToInt(blob[pos+1]);
    if (idx < 0) or (idx > High(PREDEFINED_BRANCHES)) then Exit;
    branchFromCommit := PREDEFINED_BRANCHES[idx];
    Inc(pos, 2);
    Result := True;
    Exit;
  end;
  // hash prefix of length blob[pos] in '1'..'9'. Branch defaults to main.
  var lenVal: Integer := Ord(blob[pos]) - Ord('0');
  if pos+lenVal > Length(blob) then Exit;
  commitHex := LowerCase(Copy(blob, pos+1, lenVal));
  if not IsAllHex(commitHex) then Exit;
  branchFromCommit := PREDEFINED_BRANCHES[0]; // 'main'
  Inc(pos, 1+lenVal);
  Result := True;
end;

// Read one branch-override field (pos 3 or 4 in the blob). These slots
// are *hash-only*: predefined entries are not allowed (use pos 1/2 if you
// want predefined). Length digit must be '1'..'9'; '0' rejects.
function ReadBranchOverrideField(const blob: string; var pos: Integer;
  out hashHex: string): Boolean;
begin
  Result := False;
  hashHex := '';
  if pos > Length(blob) then Exit;
  if not (blob[pos] in ['1'..'9']) then Exit;
  var lenVal: Integer := Ord(blob[pos]) - Ord('0');
  if pos+lenVal > Length(blob) then Exit;
  hashHex := LowerCase(Copy(blob, pos+1, lenVal));
  if not IsAllHex(hashHex) then Exit;
  Inc(pos, 1+lenVal);
  Result := True;
end;

// Try to parse a single hex+digit run as the encoded blob. The blob has
// to be consumed in full -- any trailing chars after the optional laz-
// branch field signal that this run isn't really our encoding. On
// success: writes into p and returns True; on any field-level failure
// or trailing chars, returns False (caller advances to the next run).
function TryParseBlob(const blob: string; out p: TParsedBinaryName): Boolean;
begin
  Result := False;
  FillChar(p, SizeOf(p), 0);
  if blob = '' then Exit;
  var pos := 1;

  // Pos 1 (required when Present=True): fpc commit / predefined branch.
  if not ReadCommitField(blob, pos, p.FpcCommit, p.FpcBranchFromCommit) then Exit;

  // Pos 2 (optional): ide commit / predefined branch. When absent, ide
  // defaults to 'main' / latest -- same as if `00` had been written here.
  if pos <= Length(blob) then begin
    if not ReadCommitField(blob, pos, p.LazCommit, p.LazBranchFromCommit) then Exit;
  end else
    p.LazBranchFromCommit := PREDEFINED_BRANCHES[0];

  // Pos 3 (optional): fpc branch hash override. Hash-only (1..9 hex chars).
  if pos <= Length(blob) then
    if not ReadBranchOverrideField(blob, pos, p.FpcBranchHashOverride) then Exit;

  // Pos 4 (optional): ide branch hash override.
  if pos <= Length(blob) then
    if not ReadBranchOverrideField(blob, pos, p.LazBranchHashOverride) then Exit;

  // Require complete consumption: any leftover chars means we picked
  // a candidate run that isn't actually the encoded blob.
  if pos <= Length(blob) then Exit;

  p.Present := True;
  Result := True;
end;

function ParseBinaryName(const FileName: string): TParsedBinaryName;
begin
  FillChar(Result, SizeOf(Result), 0);
  // Take the LAST hex+digit run in the filename (closest to extension).
  // No fallback to earlier runs: per the user-facing contract the regex
  // picks one candidate, the parser either accepts it or rejects (and
  // the install falls through to defaults). Min run length 2 matches
  // the shortest meaningful blob `00` (= fpc predefined main, latest).
  var runs := CollectHexRuns(FileName, 2);
  if Length(runs) = 0 then Exit;
  TryParseBlob(runs[High(runs)], Result);
end;

function FindBranchByHashPrefix(Items: TStrings; const HexPrefix: string): string;
begin
  Result := '';
  var prefixLen := Length(HexPrefix);
  if prefixLen = 0 then Exit;
  for var i := 0 to Items.Count - 1 do
  begin
    var name := Items[i];
    var hash := LowerCase(IntToHex(Murmur3_32(name), 8));
    if SameText(Copy(hash, 1, prefixLen), HexPrefix) then Exit(name);
  end;
end;

end.
