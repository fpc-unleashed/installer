unit Pixie.Html;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Pixie.Types;

function PixieDecodeHtmlBytes(const Bytes: TBytes): string;
function PixieIsLikelySvg(const Content: string): Boolean;
function PixieDataLooksLikeSvg(Data: Pointer; Size: Integer): Boolean;

implementation

uses
  Pixie.Encoding;

// Detect charset from HTML using the spec prescan algorithm
// (https://html.spec.whatwg.org/multipage/parsing.html#prescan-a-byte-stream-to-determine-its-encoding).
// Scans the first 1024 bytes as Latin1, skips comments and non-meta tags,
// and extracts charset from <meta charset="..."> or
// <meta http-equiv="Content-Type" content="...; charset=...">.

function PrescanLowerAt(const S: string; Pos, Len: Integer;
  const Val: string): Boolean;
var
  I: Integer;
  C: Char;
begin
  if Pos + Length(Val) - 1 > Len then
    Exit(False);
  for I := 1 to Length(Val) do
  begin
    C := S[Pos + I - 1];
    if (C >= 'A') and (C <= 'Z') then
      C := Chr(Ord(C) + 32);
    if C <> Val[I] then
      Exit(False);
  end;
  Result := True;
end;

function PrescanIsWhitespace(C: Char): Boolean; inline;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13) or (C = #12);
end;

// Extract charset value from a content attribute string
// e.g. "text/html; charset=windows-1251" -> "windows-1251"
function PrescanExtractCharset(const Content: string): string;
var
  I, Start, Len: Integer;
  C: Char;
begin
  Result := '';
  Len := Length(Content);
  I := 1;
  while I + 7 <= Len do
  begin
    if not PrescanLowerAt(Content, I, Len, 'charset') then
    begin
      Inc(I);
      Continue;
    end;
    Inc(I, 7);
    // Skip spaces around '='
    while (I <= Len) and (Content[I] = ' ') do
      Inc(I);
    if (I > Len) or (Content[I] <> '=') then
      Continue;
    Inc(I);
    while (I <= Len) and (Content[I] = ' ') do
      Inc(I);
    if I > Len then
      Exit;
    // Quoted or unquoted value
    C := Content[I];
    if (C = '"') or (C = '''') then
    begin
      Inc(I);
      Start := I;
      while (I <= Len) and (Content[I] <> C) do
        Inc(I);
      Result := LowerCase(Copy(Content, Start, I - Start));
    end
    else
    begin
      Start := I;
      while (I <= Len) and (Content[I] <> ' ') and (Content[I] <> ';') do
        Inc(I);
      Result := LowerCase(Copy(Content, Start, I - Start));
    end;
    Exit;
  end;
end;

// Get an attribute name/value pair from the prescan position.
// Returns False when no more attributes are found.
function PrescanGetAttribute(const S: string; var Pos: Integer; Len: Integer;
  out AttrName, AttrValue: string): Boolean;
var
  Start: Integer;
  Quote: Char;
begin
  Result := False;
  AttrName := '';
  AttrValue := '';
  // Skip whitespace and slashes
  while (Pos <= Len) and (PrescanIsWhitespace(S[Pos]) or (S[Pos] = '/')) do
    Inc(Pos);
  if (Pos > Len) or (S[Pos] = '>') then
    Exit;
  // Collect attribute name
  Start := Pos;
  while (Pos <= Len) and (S[Pos] <> '=') and (S[Pos] <> '>')
        and not PrescanIsWhitespace(S[Pos]) do
    Inc(Pos);
  AttrName := LowerCase(Copy(S, Start, Pos - Start));
  if AttrName = '' then
    Exit;
  Result := True;
  // Skip whitespace before '='
  while (Pos <= Len) and PrescanIsWhitespace(S[Pos]) do
    Inc(Pos);
  if (Pos > Len) or (S[Pos] <> '=') then
    Exit; // attribute with no value
  Inc(Pos); // skip '='
  // Skip whitespace after '='
  while (Pos <= Len) and PrescanIsWhitespace(S[Pos]) do
    Inc(Pos);
  if Pos > Len then
    Exit;
  // Collect attribute value
  if (S[Pos] = '"') or (S[Pos] = '''') then
  begin
    Quote := S[Pos];
    Inc(Pos);
    Start := Pos;
    while (Pos <= Len) and (S[Pos] <> Quote) do
      Inc(Pos);
    AttrValue := Copy(S, Start, Pos - Start);
    if Pos <= Len then
      Inc(Pos); // skip closing quote
  end
  else
  begin
    Start := Pos;
    while (Pos <= Len) and not PrescanIsWhitespace(S[Pos]) and (S[Pos] <> '>') do
      Inc(Pos);
    AttrValue := Copy(S, Start, Pos - Start);
  end;
end;

function PixieDetectCharset(const Bytes: TBytes; Len: Integer): string;
var
  ScanLen, I, AttrPos: Integer;
  S: string;
  GotPragma, NeedPragma: Boolean;
  Charset, AttrName, AttrValue: string;
begin
  Result := '';
  ScanLen := Len;
  if ScanLen > 1024 then
    ScanLen := 1024;
  if ScanLen = 0 then
    Exit;

  // Interpret raw bytes as Latin1
  SetLength(S, ScanLen);
  for I := 0 to ScanLen - 1 do
    S[I + 1] := Char(Bytes[I]);

  I := 1;
  while I <= ScanLen do
  begin
    // Skip comment <!-- ... -->
    if (I + 3 <= ScanLen) and (S[I] = '<') and (S[I + 1] = '!')
       and (S[I + 2] = '-') and (S[I + 3] = '-') then
    begin
      Inc(I, 4);
      while I + 2 <= ScanLen do
      begin
        if (S[I] = '-') and (S[I + 1] = '-') and (S[I + 2] = '>') then
        begin
          Inc(I, 3);
          Break;
        end;
        Inc(I);
      end;
      Continue;
    end;

    // Check for <meta followed by whitespace or /
    if (I + 5 <= ScanLen) and (S[I] = '<')
       and PrescanLowerAt(S, I + 1, ScanLen, 'meta')
       and (PrescanIsWhitespace(S[I + 5]) or (S[I + 5] = '/')) then
    begin
      AttrPos := I + 5;
      GotPragma := False;
      NeedPragma := True;
      Charset := '';

      while PrescanGetAttribute(S, AttrPos, ScanLen, AttrName, AttrValue) do
      begin
        if AttrName = 'http-equiv' then
          GotPragma := LowerCase(AttrValue) = 'content-type'
        else if AttrName = 'content' then
        begin
          if Charset = '' then
            Charset := PrescanExtractCharset(AttrValue);
        end
        else if AttrName = 'charset' then
        begin
          Charset := LowerCase(AttrValue);
          NeedPragma := False;
        end;
      end;

      if (Charset <> '') and (not NeedPragma or GotPragma) then
        Exit(Charset);

      I := AttrPos;
      // Skip to '>'
      while (I <= ScanLen) and (S[I] <> '>') do
        Inc(I);
      if I <= ScanLen then
        Inc(I);
      Continue;
    end;

    // Skip other tags: <!, </, <?, or <letter
    if (I < ScanLen) and (S[I] = '<') then
    begin
      if ((S[I + 1] = '!') or (S[I + 1] = '/') or (S[I + 1] = '?'))
         or ((S[I + 1] >= 'A') and (S[I + 1] <= 'Z'))
         or ((S[I + 1] >= 'a') and (S[I + 1] <= 'z')) then
      begin
        Inc(I, 2);
        while (I <= ScanLen) and (S[I] <> '>') do
          Inc(I);
        if I <= ScanLen then
          Inc(I);
        Continue;
      end;
    end;

    Inc(I);
  end;
end;

function PixieCharsetToCodePage(const Charset: string): Integer;
var
  S: string;
begin
  S := LowerCase(Charset);

  // UTF-8 — no conversion needed
  if (S = 'utf-8') or (S = 'utf8') then
    Exit(0);

  // Windows code pages
  if (S = 'windows-1250') or (S = 'cp1250') then Exit(1250);
  if (S = 'windows-1251') or (S = 'cp1251') then Exit(1251);
  if (S = 'windows-1252') or (S = 'cp1252') then Exit(1252);
  if (S = 'windows-1253') or (S = 'cp1253') then Exit(1253);
  if (S = 'windows-1254') or (S = 'cp1254') then Exit(1254);
  if (S = 'windows-1255') or (S = 'cp1255') then Exit(1255);
  if (S = 'windows-1256') or (S = 'cp1256') then Exit(1256);
  if (S = 'windows-1257') or (S = 'cp1257') then Exit(1257);
  if (S = 'windows-1258') or (S = 'cp1258') then Exit(1258);

  // ISO-8859
  if (S = 'iso-8859-1') or (S = 'latin1') then Exit(28591);
  if S = 'iso-8859-2' then Exit(28592);
  if S = 'iso-8859-3' then Exit(28593);
  if S = 'iso-8859-4' then Exit(28594);
  if S = 'iso-8859-5' then Exit(28595);
  if S = 'iso-8859-6' then Exit(28596);
  if S = 'iso-8859-7' then Exit(28597);
  if S = 'iso-8859-8' then Exit(28598);
  if S = 'iso-8859-9' then Exit(28599);
  if S = 'iso-8859-10' then Exit(28600);
  if S = 'iso-8859-13' then Exit(28603);
  if S = 'iso-8859-14' then Exit(28604);
  if S = 'iso-8859-15' then Exit(28605);

  // KOI8
  if S = 'koi8-r' then Exit(20866);
  if S = 'koi8-u' then Exit(21866);

  // Other common
  if (S = 'us-ascii') or (S = 'ascii') then Exit(20127);
  if (S = 'shift_jis') or (S = 'shift-jis') then Exit(932);
  if S = 'euc-jp' then Exit(20932);
  if (S = 'gb2312') or (S = 'gbk') or (S = 'gb18030') then Exit(936);
  if S = 'euc-kr' then Exit(949);
  if S = 'big5' then Exit(950);
  if S = 'tis-620' then Exit(874);

  // Unknown — return 0, treat as UTF-8
  Result := 0;
end;

{$IFDEF FPC}
function BytesToUtf8(const Bytes: TBytes; Offset, Count: Integer): string;
begin
  SetLength(Result, Count);
  if Count > 0 then
    Move(Bytes[Offset], Result[1], Count);
end;

function DecodeViaCodePage(const Bytes: TBytes; CodePage: Integer): string;
var
  S: RawByteString;
begin
  SetLength(S, Length(Bytes));
  if Length(Bytes) > 0 then
    Move(Bytes[0], S[1], Length(Bytes));
  SetCodePage(S, CodePage, False);
  SetCodePage(S, 65001, True);
  Result := S;
end;
{$ENDIF}

function PixieDecodeHtmlBytes(const Bytes: TBytes): string;
var
  Charset: string;
  CodePage: Integer;
  HasMultiByte: Boolean;
  {$IFNDEF FPC}
  Enc: TEncoding;
  {$ENDIF}
begin
  // 1. BOM detection
  if (Length(Bytes) >= 3) and
     (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
  begin
    {$IFDEF FPC}
    Exit(BytesToUtf8(Bytes, 3, Length(Bytes) - 3));
    {$ELSE}
    Exit(TEncoding.UTF8.GetString(Bytes, 3, Length(Bytes) - 3));
    {$ENDIF}
  end;

  if (Length(Bytes) >= 2) and (Bytes[0] = $FF) and (Bytes[1] = $FE) then
    Exit(TEncoding.Unicode.GetString(Bytes, 2, Length(Bytes) - 2));

  if (Length(Bytes) >= 2) and (Bytes[0] = $FE) and (Bytes[1] = $FF) then
    Exit(TEncoding.BigEndianUnicode.GetString(Bytes, 2, Length(Bytes) - 2));

  // 2. Meta charset prescan
  Charset := PixieDetectCharset(Bytes, Length(Bytes));
  CodePage := PixieCharsetToCodePage(Charset);

  // 3. No declaration — auto-detect
  if (CodePage = 0) and (Charset = '') then
  begin
    if PixieIsValidUtf8(Bytes, Length(Bytes), HasMultiByte) and HasMultiByte then
      CodePage := 0
    else
    begin
      CodePage := PixieGuessCodePage(Bytes, Length(Bytes));
      if CodePage = 0 then
      begin
        if (DefaultSystemCodePage = 874) or
           ((DefaultSystemCodePage >= 1250) and (DefaultSystemCodePage <= 1258)) or
           (DefaultSystemCodePage = 20866) or (DefaultSystemCodePage = 21866) then
          CodePage := DefaultSystemCodePage
        else
          CodePage := 1252;
      end;
    end;
  end;

  // Decode
  if CodePage = 0 then
  begin
    {$IFDEF FPC}
    Result := BytesToUtf8(Bytes, 0, Length(Bytes));
    {$ELSE}
    Result := TEncoding.UTF8.GetString(Bytes);
    {$ENDIF}
  end
  else
  begin
    {$IFDEF FPC}
    Result := DecodeViaCodePage(Bytes, CodePage);
    {$ELSE}
    Enc := TEncoding.GetEncoding(CodePage);
    try
      Result := Enc.GetString(Bytes);
    finally
      Enc.Free;
    end;
    {$ENDIF}
  end;
end;

function PixieIsLikelySvg(const Content: string): Boolean;
var
  I, Len: Integer;

  function AtSvgTag: Boolean;
  begin
    Result := (I + 3 <= Len) and (Content[I] = '<') and
      ((Content[I + 1] = 's') or (Content[I + 1] = 'S')) and
      ((Content[I + 2] = 'v') or (Content[I + 2] = 'V')) and
      ((Content[I + 3] = 'g') or (Content[I + 3] = 'G'));
  end;

  procedure SkipWhitespace;
  begin
    while (I <= Len) and (Content[I] <= ' ') do Inc(I);
  end;

begin
  Result := False;
  Len := Length(Content);
  if Len < 4 then Exit;
  I := 1;

  // Skip any combination of whitespace, <?...?> processing instructions,
  // <!-- --> comments, and <!DOCTYPE ...> / other declarations before
  // arriving at <svg. Visio exports place both a DOCTYPE and a comment
  // in front of the root element.
  repeat
    SkipWhitespace;
    if AtSvgTag then
    begin
      Result := True;
      Exit;
    end;
    if (I + 1 > Len) or (Content[I] <> '<') then Exit;

    if Content[I + 1] = '?' then
    begin
      Inc(I, 2);
      while (I < Len) and not ((Content[I] = '?') and (Content[I + 1] = '>')) do
        Inc(I);
      Inc(I, 2);
    end
    else if (I + 3 <= Len) and (Content[I + 1] = '!') and
            (Content[I + 2] = '-') and (Content[I + 3] = '-') then
    begin
      // Comment — terminated by -->, not the first '>'
      Inc(I, 4);
      while (I + 2 <= Len) and not ((Content[I] = '-') and
        (Content[I + 1] = '-') and (Content[I + 2] = '>')) do
        Inc(I);
      Inc(I, 3);
    end
    else if Content[I + 1] = '!' then
    begin
      // DOCTYPE or other declaration
      while (I <= Len) and (Content[I] <> '>') do Inc(I);
      Inc(I);
    end
    else
      Exit;
  until I > Len;
end;

// Sniff a decoded image buffer (e.g. a data: URI payload) for SVG content.
// Only the leading bytes matter, so the scan is capped — enough to skip any
// XML declaration, comment or DOCTYPE and reach the <svg root element.
function PixieDataLooksLikeSvg(Data: Pointer; Size: Integer): Boolean;
var
  Head: string;
  HeadLen: Integer;
begin
  Result := False;
  if (Data = nil) or (Size <= 0) then Exit;
  HeadLen := Size;
  if HeadLen > 512 then HeadLen := 512;
  SetString(Head, PAnsiChar(Data), HeadLen);
  Result := PixieIsLikelySvg(Head);
end;

end.
