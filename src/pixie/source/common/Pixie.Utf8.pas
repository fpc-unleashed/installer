unit Pixie.Utf8;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

function ReadUtf8Char(const Str: string; var Index: Integer): UInt32;
procedure PrevUtf8Char(const Str: string; var Index: Integer);
procedure AppendUtf8Char(var Str: string; Ch: UInt32);

implementation

{$IFDEF FPC}

// ---------------------------------------------------------------------------
// FPC implementation — string is UTF-8 (AnsiString)
// ---------------------------------------------------------------------------

function ReadUtf8Char(const Str: string; var Index: Integer): UInt32;
var
  B1, B2, B3, B4: Byte;
  Len: Integer;
begin
  Len := Length(Str);
  if Index > Len then
    Exit(0);

  B1 := Ord(Str[Index]);
  Inc(Index);

  // 1-byte sequence: 0xxxxxxx
  if (B1 and $80) = 0 then
    Exit(B1);

  // 2-byte sequence: 110yyyyy 10xxxxxx
  if (B1 and $E0) = $C0 then
  begin
    Result := (B1 and $1F) shl 6;
    if Index <= Len then
    begin
      Result := Result or (Ord(Str[Index]) and $3F);
      Inc(Index);
    end;
    Exit;
  end;

  // 3-byte sequence: 1110zzzz 10yyyyyy 10xxxxxx
  if (B1 and $F0) = $E0 then
  begin
    Result := (B1 and $0F) shl 12;
    if Index <= Len then
    begin
      B2 := Ord(Str[Index]);
      Inc(Index);
      Result := Result or ((B2 and $3F) shl 6);
    end;
    if Index <= Len then
    begin
      Result := Result or (Ord(Str[Index]) and $3F);
      Inc(Index);
    end;
    Exit;
  end;

  // 4-byte sequence: 11110uuu 10zzzzzz 10yyyyyy 10xxxxxx
  if (B1 and $F8) = $F0 then
  begin
    B2 := 0;
    B3 := 0;
    B4 := 0;
    if Index <= Len then
    begin
      B2 := Ord(Str[Index]) and $3F;
      Inc(Index);
    end;
    if Index <= Len then
    begin
      B3 := Ord(Str[Index]) and $3F;
      Inc(Index);
    end;
    if Index <= Len then
    begin
      B4 := Ord(Str[Index]) and $3F;
      Inc(Index);
    end;
    Result := ((B1 and $07) shl 18) or (B2 shl 12) or (B3 shl 6) or B4;
    Exit;
  end;

  // Invalid byte
  Result := $FFFD;
end;

procedure PrevUtf8Char(const Str: string; var Index: Integer);
begin
  // Skip continuation bytes (10xxxxxx)
  while (Index > 1) do
  begin
    Dec(Index);
    if (Ord(Str[Index]) shr 6) <> 2 then
      Break;
  end;
end;

procedure AppendUtf8Char(var Str: string; Ch: UInt32);
var
  Len: Integer;
begin
  Len := Length(Str);
  if Ch <= $7F then
  begin
    SetLength(Str, Len + 1);
    Str[Len + 1] := Char(Ch);
  end
  else if Ch <= $7FF then
  begin
    SetLength(Str, Len + 2);
    Str[Len + 1] := Char((Ch shr 6) + 192);
    Str[Len + 2] := Char((Ch and 63) + 128);
  end
  else if (Ch >= $D800) and (Ch <= $DFFF) then
  begin
    // Surrogate: skip (error)
  end
  else if Ch <= $FFFF then
  begin
    SetLength(Str, Len + 3);
    Str[Len + 1] := Char((Ch shr 12) + 224);
    Str[Len + 2] := Char(((Ch shr 6) and 63) + 128);
    Str[Len + 3] := Char((Ch and 63) + 128);
  end
  else if Ch <= $10FFFF then
  begin
    SetLength(Str, Len + 4);
    Str[Len + 1] := Char((Ch shr 18) + 240);
    Str[Len + 2] := Char(((Ch shr 12) and 63) + 128);
    Str[Len + 3] := Char(((Ch shr 6) and 63) + 128);
    Str[Len + 4] := Char((Ch and 63) + 128);
  end;
end;

{$ELSE}

// ---------------------------------------------------------------------------
// Delphi implementation — string is UTF-16 (UnicodeString)
// ---------------------------------------------------------------------------

function ReadUtf8Char(const Str: string; var Index: Integer): UInt32;
var
  W: Word;
  Len: Integer;
begin
  Len := Length(Str);
  if Index > Len then
    Exit(0);

  W := Ord(Str[Index]);
  Inc(Index);

  // BMP character (not a surrogate)
  if (W < $D800) or (W > $DFFF) then
    Exit(W);

  // High surrogate — read low surrogate to form full codepoint
  if (W >= $D800) and (W <= $DBFF) then
  begin
    Result := (W - $D800) shl 10;
    if Index <= Len then
    begin
      W := Ord(Str[Index]);
      if (W >= $DC00) and (W <= $DFFF) then
      begin
        Result := (Result or UInt32(W - $DC00)) + $10000;
        Inc(Index);
      end
      else
        Result := $FFFD;
    end
    else
      Result := $FFFD;
    Exit;
  end;

  // Lone low surrogate
  Result := $FFFD;
end;

procedure PrevUtf8Char(const Str: string; var Index: Integer);
var
  W: Word;
begin
  if Index > 1 then
  begin
    Dec(Index);
    W := Ord(Str[Index]);
    // If we landed on a low surrogate, skip back past the high surrogate
    if (W >= $DC00) and (W <= $DFFF) and (Index > 1) then
      Dec(Index);
  end;
end;

procedure AppendUtf8Char(var Str: string; Ch: UInt32);
var
  Len: Integer;
begin
  if (Ch >= $D800) and (Ch <= $DFFF) then
    Exit; // Surrogate: skip (error)

  Len := Length(Str);
  if Ch <= $FFFF then
  begin
    SetLength(Str, Len + 1);
    Str[Len + 1] := Char(Ch);
  end
  else if Ch <= $10FFFF then
  begin
    Ch := Ch - $10000;
    SetLength(Str, Len + 2);
    Str[Len + 1] := Char($D800 + (Ch shr 10));
    Str[Len + 2] := Char($DC00 + (Ch and $3FF));
  end;
end;

{$ENDIF}

end.
