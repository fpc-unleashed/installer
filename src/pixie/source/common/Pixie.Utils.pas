unit Pixie.Utils;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Pixie.Types;

const
  PixieWhitespace = ' '#10#13#9#12;

function PixieTrim(const S: string; const CharsToTrim: string = PixieWhitespace): string;
function PixieLowerCase(const S: string): string;
function PixieEqualI(const S1, S2: string): Boolean;
function PixieMatch(const Str: string; Index: Integer; const Substr: string): Boolean;
function PixieValueIndex(const Val, Strings: string; DefValue: Integer = -1; Delim: Char = ';'): Integer;
function PixieIndexValue(Index: Integer; const Strings: string; Delim: Char = ';'): string;
function PixieValueInList(const Val, Strings: string; Delim: Char = ';'): Boolean;
function PixieStrEqualNoCase(const S, LowerVal: string): Boolean;
procedure PixieSplitString(const Str: string; Tokens: TPixieStringVector; const Delims: string = PixieWhitespace; const DelimsPreserve: string = ''; const Quote: string = '"');

function PixieIsWhitespace(C: Integer): Boolean; inline;
function PixieIsAlpha(C: Integer): Boolean; inline;
function PixieIsDigit(C: Integer): Boolean; inline;
function PixieIsHexDigit(C: Integer): Boolean; inline;
function PixieDigitValue(C: Integer): Integer; inline;
function PixieIsSurrogate(C: Integer): Boolean; inline;
function PixieToLower(C: Integer): Integer; inline;

// Extract leading numeric prefix from HTML attribute values (e.g. "50px" -> "50").
// Required because FPC's System.Val zeroes the result on any parse failure.
function PixieExtractInteger(const S: string): string;
function PixieExtractFloat(const S: string): string;

implementation

function PixieTrim(const S: string; const CharsToTrim: string): string;
var
  I, J, Len: Integer;
  Found: Boolean;
  Ch: Char;
begin
  Len := Length(S);
  I := 1;
  while I <= Len do
  begin
    Ch := S[I];
    Found := False;
    for J := 1 to Length(CharsToTrim) do
      if Ch = CharsToTrim[J] then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      Break;
    Inc(I);
  end;

  if I > Len then
  begin
    Result := '';
    Exit;
  end;

  J := Len;
  while J >= I do
  begin
    Ch := S[J];
    Found := False;
    for Len := 1 to Length(CharsToTrim) do
      if Ch = CharsToTrim[Len] then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      Break;
    Dec(J);
  end;

  Result := Copy(S, I, J - I + 1);
end;

function PixieLowerCase(const S: string): string;
var
  I, J, Len: Integer;
begin
  Len := Length(S);
  for I := 1 to Len do
    if (S[I] >= 'A') and (S[I] <= 'Z') then
    begin
      Result := S;
      Result[I] := Chr(Ord(Result[I]) + 32);
      for J := I + 1 to Len do
        if (Result[J] >= 'A') and (Result[J] <= 'Z') then
          Result[J] := Chr(Ord(Result[J]) + 32);
      Exit;
    end;
  Result := S;
end;

function PixieEqualI(const S1, S2: string): Boolean;
var
  I, Len: Integer;
begin
  Len := Length(S1);
  if Len <> Length(S2) then
    Exit(False);
  for I := 1 to Len do
    if PixieToLower(Ord(S1[I])) <> PixieToLower(Ord(S2[I])) then
      Exit(False);
  Result := True;
end;

function PixieMatch(const Str: string; Index: Integer; const Substr: string): Boolean;
var
  I: Integer;
begin
  // Index is 1-based
  if Index < 1 then
    Index := Length(Str) + 1 + Index;
  if (Index < 1) or (Index + Length(Substr) - 1 > Length(Str)) then
    Exit(False);
  for I := 1 to Length(Substr) do
    if Str[Index + I - 1] <> Substr[I] then
      Exit(False);
  Result := True;
end;

function PixieCompareAt(const S: string; Start, Len: Integer; const Val: string): Boolean;
var
  I: Integer;
begin
  if Len <> Length(Val) then
    Exit(False);
  for I := 1 to Len do
    if S[Start + I - 1] <> Val[I] then
      Exit(False);
  Result := True;
end;

function PixieValueIndex(const Val, Strings: string; DefValue: Integer; Delim: Char): Integer;
var
  Idx, Start, ItemEnd, ItemLen, ValLen, StrLen: Integer;
begin
  if (Val = '') or (Strings = '') then
    Exit(DefValue);

  Idx := 0;
  Start := 1;
  ValLen := Length(Val);
  StrLen := Length(Strings);

  while Start <= StrLen do
  begin
    ItemEnd := Start;
    while (ItemEnd <= StrLen) and (Strings[ItemEnd] <> Delim) do
      Inc(ItemEnd);

    ItemLen := ItemEnd - Start;
    if (ItemLen = ValLen) and PixieCompareAt(Strings, Start, ItemLen, Val) then
      Exit(Idx);

    Inc(Idx);
    Start := ItemEnd + 1;
  end;

  Result := DefValue;
end;

function PixieIndexValue(Index: Integer; const Strings: string; Delim: Char): string;
var
  Vals: TPixieStringVector;
  DelimStr: string;
begin
  Vals := TPixieStringVector.Create;
  try
    DelimStr := Delim;
    PixieSplitString(Strings, Vals, DelimStr);
    if (Index >= 0) and (Index < Vals.Count) then
      Result := Vals[Index]
    else
      Result := IntToStr(Index);
  finally
    Vals.Free;
  end;
end;

function PixieValueInList(const Val, Strings: string; Delim: Char): Boolean;
begin
  Result := PixieValueIndex(Val, Strings, -1, Delim) >= 0;
end;

function PixieStrEqualNoCase(const S, LowerVal: string): Boolean;
var
  I, Len: Integer;
  C: Byte;
begin
  Len := Length(S);
  if Len <> Length(LowerVal) then
    Exit(False);
  for I := 1 to Len do
  begin
    C := Ord(S[I]);
    if (C >= Ord('A')) and (C <= Ord('Z')) then
      C := C + 32;
    if C <> Ord(LowerVal[I]) then
      Exit(False);
  end;
  Result := True;
end;

function PixieFindCloseBracket(const S: string; Off: Integer; OpenB: Char; CloseB: Char): Integer;
var
  Cnt, I: Integer;
begin
  Cnt := 0;
  for I := Off to Length(S) do
  begin
    if S[I] = OpenB then
      Inc(Cnt)
    else if S[I] = CloseB then
    begin
      Dec(Cnt);
      if Cnt = 0 then
        Exit(I);
    end;
  end;
  Result := 0;
end;

function CharInStr(Ch: Char; const S: string): Boolean; inline;
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    if S[I] = Ch then
      Exit(True);
  Result := False;
end;

procedure PixieSplitString(const Str: string; Tokens: TPixieStringVector; const Delims: string; const DelimsPreserve: string; const Quote: string);
var
  AllDelims: string;
  TokenStart, TokenEnd, StrLen, TokenLen: Integer;
  Token: string;
begin
  if (Str = '') or ((Delims = '') and (DelimsPreserve = '')) then
    Exit;

  AllDelims := Delims + DelimsPreserve + Quote;
  StrLen := Length(Str);
  TokenStart := 1;

  // Find first delimiter
  TokenEnd := 0;
  for TokenLen := TokenStart to StrLen do
    if CharInStr(Str[TokenLen], AllDelims) then
    begin
      TokenEnd := TokenLen;
      Break;
    end;
  if TokenEnd = 0 then
    TokenEnd := StrLen + 1; // past end = no delimiter found

  while True do
  begin
    // Skip over quoted/bracketed content
    while (TokenEnd >= 1) and (TokenEnd <= StrLen) and CharInStr(Str[TokenEnd], Quote) do
    begin
      if Str[TokenEnd] = '(' then
        TokenEnd := PixieFindCloseBracket(Str, TokenEnd, '(', ')')
      else if Str[TokenEnd] = '[' then
        TokenEnd := PixieFindCloseBracket(Str, TokenEnd, '[', ']')
      else if Str[TokenEnd] = '{' then
        TokenEnd := PixieFindCloseBracket(Str, TokenEnd, '{', '}')
      else
      begin
        // Find matching quote char
        TokenLen := TokenEnd + 1;
        while (TokenLen <= StrLen) and (Str[TokenLen] <> Str[TokenEnd]) do
          Inc(TokenLen);
        if TokenLen <= StrLen then
          TokenEnd := TokenLen
        else
          TokenEnd := 0;
      end;

      if (TokenEnd >= 1) and (TokenEnd <= StrLen) then
      begin
        // Find next delimiter after the bracket/quote
        TokenLen := TokenEnd + 1;
        TokenEnd := 0;
        while TokenLen <= StrLen do
        begin
          if CharInStr(Str[TokenLen], AllDelims) then
          begin
            TokenEnd := TokenLen;
            Break;
          end;
          Inc(TokenLen);
        end;
        if TokenEnd = 0 then
          TokenEnd := StrLen + 1;
      end
      else
        TokenEnd := StrLen + 1;
    end;

    // Extract token
    if TokenEnd > StrLen then
      TokenLen := StrLen - TokenStart + 1
    else
      TokenLen := TokenEnd - TokenStart;

    if TokenLen > 0 then
    begin
      Token := Copy(Str, TokenStart, TokenLen);
      if Token <> '' then
        Tokens.Add(Token);
    end;

    // Add preserved delimiter
    if (TokenEnd >= 1) and (TokenEnd <= StrLen) and (DelimsPreserve <> '') and CharInStr(Str[TokenEnd], DelimsPreserve) then
      Tokens.Add(Str[TokenEnd]);

    TokenStart := TokenEnd;
    if (TokenStart < 1) or (TokenStart > StrLen) then
      Break;
    Inc(TokenStart);
    if TokenStart > StrLen then
      Break;

    // Find next delimiter
    TokenEnd := 0;
    for TokenLen := TokenStart to StrLen do
      if CharInStr(Str[TokenLen], AllDelims) then
      begin
        TokenEnd := TokenLen;
        Break;
      end;
    if TokenEnd = 0 then
      TokenEnd := StrLen + 1;
  end;
end;

function PixieIsWhitespace(C: Integer): Boolean;
begin
  Result := (C = Ord(' ')) or (C = 9) or (C = 10) or (C = 13) or (C = 12);
end;

function PixieIsAlpha(C: Integer): Boolean;
begin
  Result := ((C >= Ord('A')) and (C <= Ord('Z'))) or ((C >= Ord('a')) and (C <= Ord('z')));
end;

function PixieIsDigit(C: Integer): Boolean;
begin
  Result := (C >= Ord('0')) and (C <= Ord('9'));
end;

function PixieIsHexDigit(C: Integer): Boolean;
begin
  Result := PixieIsDigit(C) or ((C >= Ord('a')) and (C <= Ord('f'))) or ((C >= Ord('A')) and (C <= Ord('F')));
end;

function PixieDigitValue(C: Integer): Integer;
begin
  if PixieIsDigit(C) then
    Result := C - Ord('0')
  else
    Result := PixieToLower(C) - Ord('a') + 10;
end;

function PixieIsSurrogate(C: Integer): Boolean;
begin
  Result := (C >= $D800) and (C < $E000);
end;

function PixieToLower(C: Integer): Integer;
begin
  if (C >= Ord('A')) and (C <= Ord('Z')) then
    Result := C + 32
  else
    Result := C;
end;

function PixieExtractInteger(const S: string): string;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and PixieIsDigit(Ord(S[I])) do
    Inc(I);
  if I > Length(S) then
    Result := S
  else
    Result := Copy(S, 1, I - 1);
end;

function PixieExtractFloat(const S: string): string;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and (PixieIsDigit(Ord(S[I])) or (S[I] = '.')) do
    Inc(I);
  if I > Length(S) then
    Result := S
  else
    Result := Copy(S, 1, I - 1);
end;

end.
