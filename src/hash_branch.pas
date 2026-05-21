{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit hash_branch;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

// MurmurHash3 32-bit (Austin Appleby PD ref); deterministic short-name -> hex for branch-pin in filenames. NOT security.
function Murmur3_32(const s: string; Seed: LongWord = 0): LongWord;

type
  // wire format documented in README.md ("Filename hash pin")
  TParsedBinaryName = record
    Present: Boolean;
    FpcCommit: string;
    FpcBranchFromCommit: string;
    FpcBranchHashOverride: string;
    LazCommit: string;
    LazBranchFromCommit: string;
    LazBranchHashOverride: string;
  end;

// picks LAST hex+digit run in filename (closest to ext); no fallback to earlier runs
function ParseBinaryName(const FileName: string): TParsedBinaryName;

// parse a string as the blob directly (no run extraction); for ParamStr(1) override
function TryParseBlob(const blob: string; out p: TParsedBinaryName): Boolean;

// scan Items for first murmur3 prefix match; '' on no match
function FindBranchByHashPrefix(Items: TStrings; const HexPrefix: string): string;

implementation

const
  // append-only: new entries get higher indices so old encoded binaries still parse the same
  PREDEFINED_BRANCHES: array[0..1] of string = ('main', 'devel');

function Murmur3_32(const s: string; Seed: LongWord = 0): LongWord;
const
  C1: LongWord = $cc9e2d51;
  C2: LongWord = $1b873593;

  function rotl(x: LongWord; r: Byte): LongWord; inline;
  begin
    Result := (x shl r) or (x shr (32-r));
  end;

begin
  {$push}{$Q-}{$R-}
  Result := Seed;
  var len := Length(s);
  var i := 1;
  while i+3 <= len do begin
    var k: LongWord := LongWord(Byte(s[i])) or (LongWord(Byte(s[i+1])) shl 8) or (LongWord(Byte(s[i+2])) shl 16) or (LongWord(Byte(s[i+3])) shl 24);
    Result := rotl(Result xor (rotl(k*C1, 15)*C2), 13)*5+$e6546b64;
    Inc(i, 4);
  end;
  var rem := len-i+1;
  if rem > 0 then begin
    var k: LongWord := LongWord(Byte(s[i]));
    if rem >= 2 then k := k or (LongWord(Byte(s[i+1])) shl 8);
    if rem >= 3 then k := k or (LongWord(Byte(s[i+2])) shl 16);
    Result := Result xor (rotl(k*C1, 15)*C2);
  end;
  Result := Result xor LongWord(len);
  Result := Result xor (Result shr 16);
  Result := Result*LongWord($85ebca6b);
  Result := Result xor (Result shr 13);
  Result := Result*LongWord($c2b2ae35);
  Result := Result xor (Result shr 16);
  {$pop}
end;

// left-to-right hex-char runs >= MinLen; non-hex breaks the run
function CollectHexRuns(const s: string; MinLen: Integer): array of string;
begin
  SetLength(Result, 0);
  var i := 1;
  while i <= Length(s) do begin
    if s[i] in ['0'..'9', 'a'..'f', 'A'..'F'] then begin
      var startPos := i;
      while (i <= Length(s)) and (s[i] in ['0'..'9', 'a'..'f', 'A'..'F']) do Inc(i);
      if i-startPos >= MinLen then begin
        SetLength(Result, Length(Result)+1);
        Result[High(Result)] := Copy(s, startPos, i-startPos);
      end;
    end else Inc(i);
  end;
end;

function IsAllHex(const s: string): Boolean;
begin
  Result := False;
  if s = '' then Exit;
  for var i := 1 to Length(s) do if not (s[i] in ['0'..'9', 'a'..'f', 'A'..'F']) then Exit;
  Result := True;
end;

// single hex char -> 0..15 or -1
function HexCharToInt(c: Char): Integer;
begin
  if (c >= '0') and (c <= '9') then Result := Ord(c)-Ord('0')
  else if (c >= 'a') and (c <= 'f') then Result := Ord(c)-Ord('a')+10
  else if (c >= 'A') and (c <= 'F') then Result := Ord(c)-Ord('A')+10
  else Result := -1;
end;

// read commit field (pos 1/2):  '0X' = predefined index (latest),  '<L><Lhex>' = SHA prefix pin (branch='main')
function ReadCommitField(const blob: string; var pos: Integer; out commitHex, branchFromCommit: string): Boolean;
begin
  Result := False;
  commitHex := '';
  branchFromCommit := '';
  if pos > Length(blob) then Exit;
  if not (blob[pos] in ['0'..'9']) then Exit;
  if blob[pos] = '0' then begin
    // predefined: 1 length digit + 1 hex index into table
    if pos+1 > Length(blob) then Exit;
    var idx: Integer := HexCharToInt(blob[pos+1]);
    if (idx < 0) or (idx > High(PREDEFINED_BRANCHES)) then Exit;
    branchFromCommit := PREDEFINED_BRANCHES[idx];
    Inc(pos, 2);
    Result := True;
    Exit;
  end;
  // hash-prefix pin, length blob[pos] in '1'..'9'; branch defaults to main
  var lenVal: Integer := Ord(blob[pos])-Ord('0');
  if pos+lenVal > Length(blob) then Exit;
  commitHex := LowerCase(Copy(blob, pos+1, lenVal));
  if not IsAllHex(commitHex) then Exit;
  branchFromCommit := PREDEFINED_BRANCHES[0];  // 'main'
  Inc(pos, 1+lenVal);
  Result := True;
end;

// branch-override (pos 3/4): hash-only, length '1'..'9'; '0' rejects (use commit field for predefined)
function ReadBranchOverrideField(const blob: string; var pos: Integer; out hashHex: string): Boolean;
begin
  Result := False;
  hashHex := '';
  if pos > Length(blob) then Exit;
  if not (blob[pos] in ['1'..'9']) then Exit;
  var lenVal: Integer := Ord(blob[pos])-Ord('0');
  if pos+lenVal > Length(blob) then Exit;
  hashHex := LowerCase(Copy(blob, pos+1, lenVal));
  if not IsAllHex(hashHex) then Exit;
  Inc(pos, 1+lenVal);
  Result := True;
end;

// blob must be consumed in full; any trailing chars after pos4 means this run isn't our encoding
function TryParseBlob(const blob: string; out p: TParsedBinaryName): Boolean;
begin
  Result := False;
  FillChar(p, SizeOf(p), 0);
  if blob = '' then Exit;
  var pos := 1;

  // pos1 (required): fpc commit / predefined branch
  if not ReadCommitField(blob, pos, p.FpcCommit, p.FpcBranchFromCommit) then Exit;

  // pos2 (optional): ide commit / predefined; absent = main/latest (same as '00')
  if pos <= Length(blob) then begin
    if not ReadCommitField(blob, pos, p.LazCommit, p.LazBranchFromCommit) then Exit;
  end else p.LazBranchFromCommit := PREDEFINED_BRANCHES[0];

  // pos3 (optional): fpc branch hash override (hash-only)
  if pos <= Length(blob) then if not ReadBranchOverrideField(blob, pos, p.FpcBranchHashOverride) then Exit;

  // pos4 (optional): ide branch hash override
  if pos <= Length(blob) then if not ReadBranchOverrideField(blob, pos, p.LazBranchHashOverride) then Exit;

  // leftover chars => candidate run isn't the encoded blob
  if pos <= Length(blob) then Exit;

  p.Present := True;
  Result := True;
end;

function ParseBinaryName(const FileName: string): TParsedBinaryName;
begin
  FillChar(Result, SizeOf(Result), 0);
  // last hex+digit run wins (no fallback); min 2 matches the shortest meaningful blob '00'
  var runs := CollectHexRuns(FileName, 2);
  if Length(runs) = 0 then Exit;
  TryParseBlob(runs[High(runs)], Result);
end;

function FindBranchByHashPrefix(Items: TStrings; const HexPrefix: string): string;
begin
  Result := '';
  var prefixLen := Length(HexPrefix);
  if prefixLen = 0 then Exit;
  for var i := 0 to Items.Count-1 do begin
    var name := Items[i];
    var hash := LowerCase(IntToHex(Murmur3_32(name), 8));
    if SameText(Copy(hash, 1, prefixLen), HexPrefix) then Exit(name);
  end;
end;

end.
