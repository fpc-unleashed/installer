unit Pixie.Markdown.InlineParser;

// Markdown inline parser. Takes a string of inline source (typically
// the contents of a paragraph or heading) and emits a list of inline
// AST nodes (mnText, mnEmph, mnStrong, mnCodeSpan, mnLink, mnImage,
// mnLineBreak, mnSoftBreak, mnRawHtml, mnStrikethrough).
//
// Pragmatic implementation rather than a full CommonMark conformance:
// emphasis matching is greedy and avoids the intricate left/right
// flanking delimiter-run rules of the spec — works correctly for
// common cases like **bold**, *em*, ***both***, **bold *em* bold**,
// but won't reproduce every spec edge case.
//
// Also exposes ParseInlinesIntoBlocks which walks an AST and replaces
// the raw mnText children left by the block parser with parsed
// inline trees.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Classes, SysUtils, Generics.Collections,
  Pixie.Markdown.Types, Pixie.Markdown.Parser;

type
  TPixieMdInlineParser = class
  public
    // Parses inline source and returns a list of inline nodes. Caller
    // owns the returned nodes; pass them to a parent's AddChild.
    // RefDefs (when non-nil) lets [text][label] resolve to a stored
    // link target.
    class function Parse(const Source: string;
      RefDefs: TPixieMdLinkRefMap = nil;
      Options: TPixieMdOptions = DefaultPixieMdOptions): TPixieMdNodeList;

    // Walks Doc, replacing the single mnText child the block parser
    // left in paragraphs / headings / list items / table cells with
    // parsed inline trees.
    class procedure ParseInlinesIntoBlocks(Doc: TPixieMdNode;
      RefDefs: TPixieMdLinkRefMap = nil;
      Options: TPixieMdOptions = DefaultPixieMdOptions);
  end;

implementation

uses
  Pixie.Utils, Pixie.HtmlEntities, Pixie.Utf8;

function ResolveNamedEntity(const Name: string): string;
var
  Data: TPixieEntityData;
begin
  Result := '';
  if PixieLookupEntity(Name, Data) then
  begin
    AppendUtf8Char(Result, Data.Codepoint1);
    if Data.Codepoint2 <> 0 then
      AppendUtf8Char(Result, Data.Codepoint2);
  end;
end;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function IsAsciiAlpha(C: Char): Boolean;
begin
  Result := ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z'));
end;

function IsAsciiAlnum(C: Char): Boolean;
begin
  Result := IsAsciiAlpha(C) or ((C >= '0') and (C <= '9'));
end;

function IsAsciiPunct(C: Char): Boolean;
begin
  case C of
    '!', '"', '#', '$', '%', '&', '''', '(', ')', '*', '+', ',', '-',
    '.', '/', ':', ';', '<', '=', '>', '?', '@', '[', '\', ']', '^',
    '_', '`', '{', '|', '}', '~':
      Result := True;
  else
    Result := False;
  end;
end;

// True for ASCII whitespace plus #0, which the inline parser uses as a
// sentinel for "before/after end of source".
function IsAsciiSpaceOrEof(C: Char): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13) or (C = #0);
end;

function IsValidScheme(const S: string): Boolean;
var
  I: Integer;
begin
  // RFC 3986 scheme: ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
  if Length(S) < 2 then Exit(False);
  if not IsAsciiAlpha(S[1]) then Exit(False);
  for I := 2 to Length(S) do
    if not (IsAsciiAlnum(S[I]) or (S[I] = '+') or (S[I] = '-') or
            (S[I] = '.')) then
      Exit(False);
  Result := True;
end;

function NewText(const S: string): TPixieMdNode;
begin
  Result := TPixieMdNode.Create(mnText);
  Result.Literal := S;
end;

procedure FlushText(var Pending: string; List: TPixieMdNodeList);
begin
  if Pending = '' then Exit;
  List.Add(NewText(Pending));
  Pending := '';
end;

// ---------------------------------------------------------------------------
// Inline scanners
// ---------------------------------------------------------------------------

// Backtick code span: opening run of N backticks must match a closing
// run of exactly N backticks. Returns position after closing backticks
// and sets Content (with internal whitespace stripped per CommonMark).
function ScanCodeSpan(const S: string; Start: Integer;
  out Content: string): Integer;
var
  N, I, Len, EndStart, EndCount, K: Integer;
  HasNonSpace: Boolean;
begin
  Result := 0;
  Len := Length(S);
  N := 0;
  I := Start;
  while (I <= Len) and (S[I] = '`') do
  begin
    Inc(N);
    Inc(I);
  end;
  if N = 0 then Exit;
  // Search for closing run of exactly N backticks.
  while I <= Len do
  begin
    if S[I] = '`' then
    begin
      EndStart := I;
      EndCount := 0;
      while (I <= Len) and (S[I] = '`') do
      begin
        Inc(EndCount);
        Inc(I);
      end;
      if EndCount = N then
      begin
        Content := Copy(S, Start + N, EndStart - (Start + N));
        if (Length(Content) >= 2) and (Content[1] = ' ') and
           (Content[Length(Content)] = ' ') then
        begin
          HasNonSpace := False;
          for K := 1 to Length(Content) do
            if Content[K] <> ' ' then
            begin
              HasNonSpace := True;
              Break;
            end;
          if HasNonSpace then
          begin
            Delete(Content, 1, 1);
            Delete(Content, Length(Content), 1);
          end;
        end;
        Result := I;
        Exit;
      end;
    end
    else
      Inc(I);
  end;
end;

// Autolink: <scheme:...> or <email@...>. Returns position after closing
// '>' and fills Url, or 0.
function ScanAutoLink(const S: string; Start: Integer;
  out Url: string; out IsEmail: Boolean): Integer;
var
  I, Len: Integer;
  Inner: string;
  ColonPos, AtPos: Integer;
  Scheme: string;
begin
  Result := 0;
  IsEmail := False;
  Len := Length(S);
  if (Start > Len) or (S[Start] <> '<') then Exit;
  I := Start + 1;
  Inner := '';
  while (I <= Len) and (S[I] <> '>') do
  begin
    if (S[I] = ' ') or (S[I] = #9) or (S[I] = '<') then Exit;
    Inner := Inner + S[I];
    Inc(I);
  end;
  if (I > Len) or (S[I] <> '>') then Exit;
  // URL form: contains a colon with valid scheme before it.
  ColonPos := Pos(':', Inner);
  if ColonPos > 0 then
  begin
    Scheme := Copy(Inner, 1, ColonPos - 1);
    if IsValidScheme(Scheme) then
    begin
      Url := Inner;
      Result := I + 1;
      Exit;
    end;
  end;
  // Email form: contains @ with at least one char before and dot after.
  AtPos := Pos('@', Inner);
  if (AtPos > 1) and (AtPos < Length(Inner)) and
     (Pos('.', Copy(Inner, AtPos + 1, Length(Inner))) > 0) then
  begin
    Url := Inner;
    IsEmail := True;
    Result := I + 1;
  end;
end;

function IsGfmUrlChar(C: Char): Boolean;
begin
  Result := (C > #32) and (C <> '<') and (C <> '>') and (C <> '"');
end;

// Non-allocating case-insensitive prefix match: does S match Prefix
// (which must be lowercase ASCII) starting at Start?
function MatchPrefixCI(const S: string; Start: Integer;
  const Prefix: string): Boolean;
var
  I, PLen: Integer;
  C: Char;
begin
  PLen := Length(Prefix);
  if Start + PLen - 1 > Length(S) then Exit(False);
  for I := 1 to PLen do
  begin
    C := S[Start + I - 1];
    if (C >= 'A') and (C <= 'Z') then
      C := Chr(Ord(C) + 32);
    if C <> Prefix[I] then Exit(False);
  end;
  Result := True;
end;

// GFM extended autolink: bare URLs starting with http://, https://,
// ftp://, or www. — auto-linked when at a word boundary. Returns
// position after the link or 0. Url is the visible text; IsWww means
// the caller should prepend http:// when building the href.
function ScanGfmAutolink(const S: string; Start: Integer;
  out Url: string; out IsWww: Boolean): Integer;
var
  I, Len, EndPos, ParenDepth, MinLen: Integer;
begin
  Result := 0;
  IsWww := False;
  Len := Length(S);
  if Start > Len then Exit;

  if MatchPrefixCI(S, Start, 'https://') then
    MinLen := 8
  else if MatchPrefixCI(S, Start, 'http://') then
    MinLen := 7
  else if MatchPrefixCI(S, Start, 'ftp://') then
    MinLen := 6
  else if MatchPrefixCI(S, Start, 'www.') then
  begin
    IsWww := True;
    MinLen := 4;
  end
  else
    Exit;

  I := Start + MinLen;
  while (I <= Len) and IsGfmUrlChar(S[I]) do Inc(I);
  EndPos := I - 1;

  // Need at least one character beyond the scheme / www. prefix.
  if EndPos < Start + MinLen then Exit;

  // Trim trailing punctuation that's never part of a URL in prose.
  while EndPos >= Start + MinLen do
  begin
    case S[EndPos] of
      '?', '!', '.', ',', ':', '*', '_', '~':
        Dec(EndPos);
    else
      Break;
    end;
  end;

  // Trim unbalanced trailing ')' so "see (https://x.com/y)" excludes
  // the outer paren.
  ParenDepth := 0;
  for I := Start to EndPos do
    if S[I] = '(' then Inc(ParenDepth)
    else if S[I] = ')' then Dec(ParenDepth);
  while (ParenDepth < 0) and (EndPos >= Start + MinLen) and
        (S[EndPos] = ')') do
  begin
    Dec(EndPos);
    Inc(ParenDepth);
  end;

  if EndPos < Start + MinLen then Exit;
  Url := Copy(S, Start, EndPos - Start + 1);
  Result := EndPos + 1;
end;

// Raw inline HTML tag: <tag ...>, </tag>, <!-- ... -->, etc. Returns
// position after the tag's closing '>' or 0.
function ScanRawHtml(const S: string; Start: Integer): Integer;
var
  I, Len: Integer;
begin
  Result := 0;
  Len := Length(S);
  if (Start > Len) or (S[Start] <> '<') then Exit;
  if Start + 1 > Len then Exit;
  // <!-- ... -->
  if (Start + 3 <= Len) and (Copy(S, Start, 4) = '<!--') then
  begin
    I := Start + 4;
    while I + 2 <= Len + 1 do
    begin
      if (I + 2 <= Len) and (S[I] = '-') and (S[I + 1] = '-') and
         (S[I + 2] = '>') then
        Exit(I + 3);
      Inc(I);
    end;
    Exit;
  end;
  // <? ... ?>
  if (Start + 1 <= Len) and (S[Start + 1] = '?') then
  begin
    I := Start + 2;
    while I + 1 <= Len do
    begin
      if (S[I] = '?') and (S[I + 1] = '>') then
        Exit(I + 2);
      Inc(I);
    end;
    Exit;
  end;
  // <![CDATA[ ... ]]>
  if (Start + 8 <= Len) and (Copy(S, Start, 9) = '<![CDATA[') then
  begin
    I := Start + 9;
    while I + 2 <= Len do
    begin
      if (S[I] = ']') and (S[I + 1] = ']') and (S[I + 2] = '>') then
        Exit(I + 3);
      Inc(I);
    end;
    Exit;
  end;
  // Open or close tag: <tag ...>, </tag ...>
  I := Start + 1;
  if (I <= Len) and (S[I] = '/') then Inc(I);
  if (I > Len) or not IsAsciiAlpha(S[I]) then Exit;
  while (I <= Len) and (IsAsciiAlnum(S[I]) or (S[I] = '-')) do Inc(I);
  // Skip attributes / whitespace until '>'
  while I <= Len do
  begin
    if S[I] = '>' then Exit(I + 1);
    if S[I] = '<' then Exit; // unterminated
    Inc(I);
  end;
end;

// HTML entity: &name; or &#NNN; or &#xHH;. Returns position after ';'
// and the decoded text, or 0.
function ScanEntity(const S: string; Start: Integer;
  out Decoded: string): Integer;
var
  I, Len, NumStart, CodePoint: Integer;
  IsHex: Boolean;
  Name: string;
  Resolved: string;
begin
  Result := 0;
  Len := Length(S);
  if (Start > Len) or (S[Start] <> '&') then Exit;
  if Start + 1 > Len then Exit;

  // Numeric: &# or &#x
  if S[Start + 1] = '#' then
  begin
    I := Start + 2;
    IsHex := False;
    if (I <= Len) and ((S[I] = 'x') or (S[I] = 'X')) then
    begin
      IsHex := True;
      Inc(I);
    end;
    NumStart := I;
    while (I <= Len) and (((not IsHex) and (S[I] >= '0') and (S[I] <= '9')) or
          (IsHex and (((S[I] >= '0') and (S[I] <= '9')) or
                      ((S[I] >= 'a') and (S[I] <= 'f')) or
                      ((S[I] >= 'A') and (S[I] <= 'F'))))) do
      Inc(I);
    if (I = NumStart) or (I > Len) or (S[I] <> ';') then Exit;
    if IsHex then
      CodePoint := StrToIntDef('$' + Copy(S, NumStart, I - NumStart), -1)
    else
      CodePoint := StrToIntDef(Copy(S, NumStart, I - NumStart), -1);
    if (CodePoint < 0) or (CodePoint > $10FFFF) then
      Exit;
    // HTML output forbids NUL; surrogates aren't valid codepoints.
    if (CodePoint = 0) or
       ((CodePoint >= $D800) and (CodePoint <= $DFFF)) then
      CodePoint := $FFFD;
    Decoded := '';
    AppendUtf8Char(Decoded, CodePoint);
    Result := I + 1;
    Exit;
  end;

  // Named entity
  I := Start + 1;
  while (I <= Len) and (IsAsciiAlnum(S[I])) do Inc(I);
  if (I > Len) or (S[I] <> ';') or (I = Start + 1) then Exit;
  Name := Copy(S, Start + 1, I - Start - 1);
  Resolved := ResolveNamedEntity(Name);
  if Resolved = '' then Exit;
  Decoded := Resolved;
  Result := I + 1;
end;

// Apply backslash escapes and decode HTML entities in a link
// destination or title (CommonMark "process link destination/title").
// Also used for fenced-code info strings, which the spec processes the
// same way. Other characters are passed through unchanged.
function MdProcessLinkPart(const S: string): string;
var
  I, Len, AfterEntity: Integer;
  Decoded: string;
begin
  // Fast path: most URLs/titles/CodeLang values contain neither '\' nor
  // '&'. AnsiString refcounting makes Exit(S) a no-copy return.
  if (Pos('\', S) = 0) and (Pos('&', S) = 0) then
    Exit(S);
  Len := Length(S);
  Result := '';
  I := 1;
  while I <= Len do
  begin
    if (S[I] = '\') and (I < Len) and IsAsciiPunct(S[I + 1]) then
    begin
      Result := Result + S[I + 1];
      Inc(I, 2);
    end
    else if S[I] = '&' then
    begin
      AfterEntity := ScanEntity(S, I, Decoded);
      if AfterEntity > 0 then
      begin
        Result := Result + Decoded;
        I := AfterEntity;
      end
      else
      begin
        Result := Result + S[I];
        Inc(I);
      end;
    end
    else
    begin
      Result := Result + S[I];
      Inc(I);
    end;
  end;
end;

// Percent-encode a URL per CommonMark output rules. Existing %XX
// sequences pass through verbatim so already-encoded input is preserved.
// The safe set follows cmark: RFC 3986 unreserved + sub-delims +
// "/?:@&=$#" — note `[` and `]` are NOT safe (encoded as %5B / %5D).
function MdPercentEncodeUrl(const S: string): string;
const
  HexChars: array[0..15] of Char = '0123456789ABCDEF';
var
  I, Len: Integer;
  C: Char;
begin
  Len := Length(S);
  Result := '';
  I := 1;
  while I <= Len do
  begin
    C := S[I];
    if (C = '%') and (I + 2 <= Len) and
       PixieIsHexDigit(Ord(S[I + 1])) and
       PixieIsHexDigit(Ord(S[I + 2])) then
    begin
      Result := Result + S[I] + S[I + 1] + S[I + 2];
      Inc(I, 3);
      Continue;
    end;
    case C of
      'A'..'Z', 'a'..'z', '0'..'9',
      '-', '_', '.', '+', '~', '!', '*', '''', '(', ')',
      ';', ',', '/', '?', ':', '@', '&', '=', '$', '#':
        Result := Result + C;
    else
      Result := Result + '%' +
        HexChars[(Ord(C) shr 4) and $F] +
        HexChars[Ord(C) and $F];
    end;
    Inc(I);
  end;
end;

// Link or image: [text](url "title") or ![alt](url "title").
// Returns position after closing paren, or 0.
function ScanLink(const S: string; Start: Integer; var IsImage: Boolean;
  out LabelText, Url, Title: string; out LabelEnd: Integer): Integer;
var
  I, Len, BracketDepth, ParenDepth: Integer;
  TitleStart: Integer;
  Quote: Char;
begin
  Result := 0;
  IsImage := False;
  Len := Length(S);
  I := Start;
  if (I <= Len) and (S[I] = '!') then
  begin
    IsImage := True;
    Inc(I);
  end;
  if (I > Len) or (S[I] <> '[') then Exit;
  Inc(I);
  // Find matching ']'
  BracketDepth := 1;
  LabelEnd := I;
  while I <= Len do
  begin
    if S[I] = '\' then
    begin
      Inc(I, 2);
      Continue;
    end;
    if S[I] = '[' then Inc(BracketDepth)
    else if S[I] = ']' then
    begin
      Dec(BracketDepth);
      if BracketDepth = 0 then
      begin
        LabelEnd := I - 1;
        Break;
      end;
    end;
    Inc(I);
  end;
  if (I > Len) or (S[I] <> ']') then Exit;
  if IsImage then
    LabelText := Copy(S, Start + 2, LabelEnd - Start - 1)
  else
    LabelText := Copy(S, Start + 1, LabelEnd - Start);
  Inc(I);
  // Inline form: ( url "title" )
  if (I > Len) or (S[I] <> '(') then Exit;
  Inc(I);
  // Skip whitespace incl. one line ending (CommonMark allows the
  // destination/title to start on the next line).
  while (I <= Len) and IsAsciiSpaceOrEof(S[I]) do Inc(I);
  // URL: <...> or non-whitespace, balanced parens
  if (I <= Len) and (S[I] = '<') then
  begin
    Inc(I);
    Url := '';
    while (I <= Len) and (S[I] <> '>') and (S[I] <> #10) and
          (S[I] <> '<') do
    begin
      // Inside <...>, backslash-escaped punctuation passes through as
      // \X (decoded later by MdProcessLinkPart). An unescaped '<' is
      // forbidden by spec.
      if (S[I] = '\') and (I < Len) and IsAsciiPunct(S[I + 1]) then
      begin
        Url := Url + S[I] + S[I + 1];
        Inc(I, 2);
        Continue;
      end;
      Url := Url + S[I];
      Inc(I);
    end;
    if (I > Len) or (S[I] <> '>') then Exit;
    Inc(I);
  end
  else
  begin
    Url := '';
    ParenDepth := 0;
    while I <= Len do
    begin
      // Keep \X raw so MdProcessLinkPart can later unescape; \( and \)
      // must not affect ParenDepth tracking, hence the explicit skip.
      if (S[I] = '\') and (I < Len) then
      begin
        Url := Url + S[I] + S[I + 1];
        Inc(I, 2);
        Continue;
      end;
      if (S[I] = ' ') or (S[I] = #9) or (S[I] = #10) then Break;
      if S[I] = '(' then Inc(ParenDepth)
      else if S[I] = ')' then
      begin
        if ParenDepth = 0 then Break;
        Dec(ParenDepth);
      end;
      Url := Url + S[I];
      Inc(I);
    end;
  end;
  // Optional title — title can start on next line, hence newlines in
  // the gap. Title content itself can also span lines.
  Title := '';
  while (I <= Len) and IsAsciiSpaceOrEof(S[I]) do Inc(I);
  if (I <= Len) and ((S[I] = '"') or (S[I] = '''') or (S[I] = '(')) then
  begin
    if S[I] = '(' then Quote := ')' else Quote := S[I];
    Inc(I);
    TitleStart := I;
    while (I <= Len) and (S[I] <> Quote) do
    begin
      if S[I] = '\' then Inc(I);
      Inc(I);
    end;
    if (I <= Len) and (S[I] = Quote) then
    begin
      Title := Copy(S, TitleStart, I - TitleStart);
      Inc(I);
    end
    else
      Exit;
  end;
  while (I <= Len) and IsAsciiSpaceOrEof(S[I]) do Inc(I);
  if (I > Len) or (S[I] <> ')') then Exit;
  Url := MdPercentEncodeUrl(MdProcessLinkPart(Url));
  Title := MdProcessLinkPart(Title);
  Result := I + 1;
end;

// Reference-style link: [text][label] (full), [text][] (collapsed),
// or [text] alone (shortcut). Returns True if a matching label was
// found in RefDefs and fills LabelText / Url / Title / AfterEnd.
function TryReferenceLink(const S: string; Start: Integer;
  RefDefs: TPixieMdLinkRefMap;
  out LabelText, Url, Title: string;
  out AfterEnd: Integer): Boolean;
var
  I, Len, BracketDepth, RefStart, RefEnd, AfterText: Integer;
  RefLabel: string;
  Ref: TPixieMdLinkRef;
begin
  Result := False;
  Len := Length(S);
  if (Start > Len) or (S[Start] <> '[') then Exit;
  I := Start + 1;
  BracketDepth := 1;
  while I <= Len do
  begin
    if S[I] = '\' then
    begin
      Inc(I, 2);
      Continue;
    end;
    if S[I] = '[' then Inc(BracketDepth)
    else if S[I] = ']' then
    begin
      Dec(BracketDepth);
      if BracketDepth = 0 then Break;
    end;
    Inc(I);
  end;
  if (I > Len) or (S[I] <> ']') then Exit;
  LabelText := Copy(S, Start + 1, I - Start - 1);
  AfterText := I + 1;

  // Optional [label] following the text label.
  RefLabel := '';
  if (AfterText <= Len) and (S[AfterText] = '[') then
  begin
    I := AfterText + 1;
    RefStart := I;
    while (I <= Len) and (S[I] <> ']') do Inc(I);
    if (I > Len) or (S[I] <> ']') then Exit;
    RefEnd := I - 1;
    RefLabel := Copy(S, RefStart, RefEnd - RefStart + 1);
    AfterText := I + 1;
  end;
  // Empty -> collapsed; no second bracket pair -> shortcut. Both reuse
  // LabelText as the lookup key.
  if RefLabel = '' then RefLabel := LabelText;

  if not RefDefs.TryGetValue(NormalizeLinkLabel(RefLabel), Ref) then Exit;
  // Ref defs are stored verbatim; apply backslash + entity processing
  // at lookup time so the resolved URL/title match CommonMark output.
  Url := MdPercentEncodeUrl(MdProcessLinkPart(Ref.Url));
  Title := MdProcessLinkPart(Ref.Title);
  AfterEnd := AfterText;
  Result := True;
end;

// ---------------------------------------------------------------------------
// Emphasis processor
// ---------------------------------------------------------------------------
//
// CommonMark left/right-flanking delimiter-run algorithm. Each delimiter
// run is classified at scan time as can-open / can-close based on the
// characters immediately before and after the run. Emphasis pairing
// then walks a doubly-linked list of delimiters applying the spec's
// rules (including the rule-of-3 to avoid mismatched nesting like
// **bold *em* bold**).

type
  TDelimMarker = class(TPixieMdNode)
  public
    DelimChar: Char;
    DelimLen: Integer;
    OriginalLen: Integer;
    CanOpen: Boolean;
    CanClose: Boolean;
    PrevDelim, NextDelim: TDelimMarker;
    constructor CreateMarker(C: Char; Len: Integer;
      AOpen, AClose: Boolean);
  end;

constructor TDelimMarker.CreateMarker(C: Char; Len: Integer;
  AOpen, AClose: Boolean);
begin
  inherited Create(mnText);
  Literal := StringOfChar(C, Len);
  DelimChar := C;
  DelimLen := Len;
  OriginalLen := Len;
  CanOpen := AOpen;
  CanClose := AClose;
end;

procedure ComputeFlanking(C: Char; PrevCh, NextCh: Char;
  out CanOpen, CanClose: Boolean);
var
  PrevSpace, NextSpace, PrevPunct, NextPunct: Boolean;
  LeftFlank, RightFlank: Boolean;
begin
  PrevSpace := IsAsciiSpaceOrEof(PrevCh);
  NextSpace := IsAsciiSpaceOrEof(NextCh);
  PrevPunct := IsAsciiPunct(PrevCh);
  NextPunct := IsAsciiPunct(NextCh);

  // Left-flanking: not followed by whitespace; and either not followed
  // by punctuation, or followed by punctuation but preceded by
  // whitespace or punctuation.
  LeftFlank := (not NextSpace) and
    ((not NextPunct) or (PrevSpace or PrevPunct));

  // Right-flanking: not preceded by whitespace; and either not preceded
  // by punctuation, or preceded by punctuation but followed by
  // whitespace or punctuation.
  RightFlank := (not PrevSpace) and
    ((not PrevPunct) or (NextSpace or NextPunct));

  if C = '_' then
  begin
    // Underscore can't open intra-word: opener also requires not
    // right-flanking unless preceded by punctuation; symmetric for
    // closer.
    CanOpen := LeftFlank and ((not RightFlank) or PrevPunct);
    CanClose := RightFlank and ((not LeftFlank) or NextPunct);
  end
  else
  begin
    CanOpen := LeftFlank;
    CanClose := RightFlank;
  end;
end;

type
  // Per-character lower bound on how far back the opener search may
  // walk, indexed by [DelimChar, OriginalLen mod 3]. Sized to cover
  // the two emphasis chars '*' (42) and '_' (95).
  TOpenersBottom = array['*'..'_', 0..2] of TDelimMarker;

procedure UnlinkDelim(var Head: TDelimMarker; D: TDelimMarker);
begin
  if D.PrevDelim <> nil then
    D.PrevDelim.NextDelim := D.NextDelim
  else
    Head := D.NextDelim;
  if D.NextDelim <> nil then
    D.NextDelim.PrevDelim := D.PrevDelim;
  D.PrevDelim := nil;
  D.NextDelim := nil;
end;

// CommonMark "rule of 3": a pair is allowed if EITHER the simple-case
// short-circuit applies (neither side both opens and closes), OR the
// sum of original lengths is not a multiple of 3, OR each individual
// length is itself a multiple of 3.
function PairAllowed(Opener, Closer: TDelimMarker): Boolean;
begin
  Result := (not (Closer.CanOpen or Opener.CanClose)) or
            (((Closer.OriginalLen + Opener.OriginalLen) mod 3) <> 0) or
            ((Closer.OriginalLen mod 3 = 0) and
             (Opener.OriginalLen mod 3 = 0));
end;

procedure ResolveDelimiters(List: TPixieMdNodeList; DelimHead: TDelimMarker);
var
  Closer, Opener, NextCloser, BottomCutoff, Walker: TDelimMarker;
  Bottom: TOpenersBottom;
  Take, OpenPos, ClosePos, ContentCount, J, ModIdx: Integer;
  Wrapper: TPixieMdNode;
  FoundOpener: Boolean;
begin
  FillChar(Bottom, SizeOf(Bottom), 0);

  Closer := DelimHead;
  while Closer <> nil do
  begin
    if not Closer.CanClose then
    begin
      Closer := Closer.NextDelim;
      Continue;
    end;

    // Search backward for a matching opener, but no further than
    // openers_bottom for this (char, original_length mod 3) combination.
    ModIdx := Closer.OriginalLen mod 3;
    BottomCutoff := Bottom[Closer.DelimChar, ModIdx];
    Opener := Closer.PrevDelim;
    FoundOpener := False;
    while (Opener <> nil) and (Opener <> BottomCutoff) do
    begin
      if Opener.CanOpen and (Opener.DelimChar = Closer.DelimChar) and
         PairAllowed(Opener, Closer) then
      begin
        FoundOpener := True;
        Break;
      end;
      Opener := Opener.PrevDelim;
    end;

    if FoundOpener then
    begin
      // Decide strong (consume 2) vs emph (consume 1).
      if (Closer.DelimLen >= 2) and (Opener.DelimLen >= 2) then
        Take := 2
      else
        Take := 1;

      if Take = 2 then
        Wrapper := TPixieMdNode.Create(mnStrong)
      else
        Wrapper := TPixieMdNode.Create(mnEmph);

      // Move every node strictly between opener and closer in the node
      // list into the wrapper. Any delimiter markers in that range are
      // dropped (their content was unpaired). After the move, Opener's
      // position in the list is unchanged (we only extracted from after
      // it), so the cached OpenPos remains valid through the rest of
      // this branch.
      OpenPos := List.IndexOf(Opener);
      ClosePos := List.IndexOf(Closer);
      ContentCount := ClosePos - OpenPos - 1;
      for J := 0 to ContentCount - 1 do
        Wrapper.AddChild(List.Extract(List[OpenPos + 1]));

      // Drop the now-stale delimiters between opener and closer from
      // the doubly-linked chain.
      Walker := Opener.NextDelim;
      while (Walker <> nil) and (Walker <> Closer) do
      begin
        NextCloser := Walker.NextDelim;
        UnlinkDelim(DelimHead, Walker);
        Walker := NextCloser;
      end;

      Opener.DelimLen := Opener.DelimLen - Take;
      Closer.DelimLen := Closer.DelimLen - Take;

      if Opener.DelimLen = 0 then
      begin
        List.Insert(OpenPos, Wrapper);
        List.Extract(Opener);
        UnlinkDelim(DelimHead, Opener);
        Opener.Free;
      end
      else
      begin
        Opener.Literal := StringOfChar(Opener.DelimChar, Opener.DelimLen);
        List.Insert(OpenPos + 1, Wrapper);
      end;

      if Closer.DelimLen = 0 then
      begin
        NextCloser := Closer.NextDelim;
        List.Extract(Closer);
        UnlinkDelim(DelimHead, Closer);
        Closer.Free;
        Closer := NextCloser;
      end
      else
        Closer.Literal := StringOfChar(Closer.DelimChar, Closer.DelimLen);
      // If closer still has length, leave Closer pointing at it so the
      // outer loop tries again with the reduced delimiter.
    end
    else
    begin
      // No opener found within the cutoff. Lower the bottom mark and
      // either advance past this closer or, if it can't open either,
      // discard it as literal.
      Bottom[Closer.DelimChar, ModIdx] := Closer.PrevDelim;
      if not Closer.CanOpen then
      begin
        NextCloser := Closer.NextDelim;
        UnlinkDelim(DelimHead, Closer);
        Closer := NextCloser;
      end
      else
        Closer := Closer.NextDelim;
    end;
  end;
end;

// ---------------------------------------------------------------------------
// Main inline parse
// ---------------------------------------------------------------------------

function ParseImpl(const Source: string;
  RefDefs: TPixieMdLinkRefMap;
  Options: TPixieMdOptions): TPixieMdNodeList; forward;

// Build a link or image node and populate it by inline-parsing the
// label as its children.
function BuildLinkLikeNode(Kind: TPixieMdNodeKind;
  const Url, Title, LabelText: string;
  RefDefs: TPixieMdLinkRefMap;
  Options: TPixieMdOptions): TPixieMdNode;
var
  InlineList: TPixieMdNodeList;
begin
  Result := TPixieMdNode.Create(Kind);
  Result.LinkUrl := Url;
  Result.LinkTitle := Title;
  InlineList := ParseImpl(LabelText, RefDefs, Options);
  try
    while InlineList.Count > 0 do
      Result.AddChild(InlineList.Extract(InlineList[0]));
  finally
    InlineList.Free;
  end;
end;

function HasLinkDescendant(Node: TPixieMdNode): Boolean;
var
  I: Integer;
begin
  if Node.Kind = mnLink then Exit(True);
  if Node.HasChildren then
    for I := 0 to Node.ChildCount - 1 do
      if HasLinkDescendant(Node.Children[I]) then Exit(True);
  Result := False;
end;

function ListHasLinkDescendant(List: TPixieMdNodeList): Boolean;
var
  I: Integer;
begin
  for I := 0 to List.Count - 1 do
    if HasLinkDescendant(List[I]) then Exit(True);
  Result := False;
end;

function ParseImpl(const Source: string;
  RefDefs: TPixieMdLinkRefMap;
  Options: TPixieMdOptions): TPixieMdNodeList;
var
  I, Len, RunLen: Integer;
  C: Char;
  Pending: string;
  CodeContent, Url, Decoded, LabelText, Title: string;
  AfterCode, AfterAuto, AfterEntity, AfterLink, AfterHtml, LabelEnd: Integer;
  IsEmail, IsImage, IsWww: Boolean;
  Node: TPixieMdNode;
  Marker, DelimHead, DelimTail: TDelimMarker;
  StrikeStart, StrikeEnd: Integer;
  InlineList: TPixieMdNodeList;
  PrevCh, NextCh: Char;
  MOpen, MClose: Boolean;
begin
  Result := TPixieMdNodeList.Create(True);
  Pending := '';
  DelimHead := nil;
  DelimTail := nil;
  Len := Length(Source);
  I := 1;
  while I <= Len do
  begin
    C := Source[I];

    // GFM extended autolink: bare http(s)://, ftp://, www. URLs at a
    // word boundary become links without the <...> wrapper. The
    // trigger-char + boundary gate is checked first to keep the
    // common per-character cost down to two comparisons.
    if (moGfmAutolinks in Options) and
       (C in ['h', 'H', 'w', 'W', 'f', 'F']) and
       ((I = 1) or not IsAsciiAlnum(Source[I - 1])) then
    begin
      AfterAuto := ScanGfmAutolink(Source, I, Url, IsWww);
      if AfterAuto > 0 then
      begin
        FlushText(Pending, Result);
        Node := TPixieMdNode.Create(mnLink);
        if IsWww then
          Node.LinkUrl := MdPercentEncodeUrl('http://' + Url)
        else
          Node.LinkUrl := MdPercentEncodeUrl(Url);
        Node.AddChild(NewText(Url));
        Result.Add(Node);
        I := AfterAuto;
        Continue;
      end;
    end;

    case C of
      '\':
        begin
          // Backslash escape: \X for ASCII punctuation, or \<line-end>
          // (LF, CR, CRLF) as a hard break.
          if I + 1 <= Len then
          begin
            NextCh := Source[I + 1];
            if (NextCh = #10) or (NextCh = #13) then
            begin
              FlushText(Pending, Result);
              Result.Add(TPixieMdNode.Create(mnLineBreak));
              Inc(I, 2);
              if (NextCh = #13) and (I <= Len) and (Source[I] = #10) then
                Inc(I);
              Continue;
            end;
            if IsAsciiPunct(NextCh) then
            begin
              Pending := Pending + NextCh;
              Inc(I, 2);
              Continue;
            end;
          end;
          Pending := Pending + C;
          Inc(I);
        end;
      '`':
        begin
          AfterCode := ScanCodeSpan(Source, I, CodeContent);
          if AfterCode > 0 then
          begin
            FlushText(Pending, Result);
            Node := TPixieMdNode.Create(mnCodeSpan);
            Node.Literal := CodeContent;
            Result.Add(Node);
            I := AfterCode;
          end
          else
          begin
            Pending := Pending + C;
            Inc(I);
          end;
        end;
      '<':
        begin
          AfterAuto := ScanAutoLink(Source, I, Url, IsEmail);
          if AfterAuto > 0 then
          begin
            FlushText(Pending, Result);
            Node := TPixieMdNode.Create(mnLink);
            if IsEmail then
              Node.LinkUrl := 'mailto:' + MdPercentEncodeUrl(Url)
            else
              Node.LinkUrl := MdPercentEncodeUrl(Url);
            Node.AddChild(NewText(Url));
            Result.Add(Node);
            I := AfterAuto;
            Continue;
          end;
          AfterHtml := ScanRawHtml(Source, I);
          if (AfterHtml > 0) and (moAllowRawHtml in Options) then
          begin
            FlushText(Pending, Result);
            Node := TPixieMdNode.Create(mnRawHtml);
            Node.Literal := Copy(Source, I, AfterHtml - I);
            Result.Add(Node);
            I := AfterHtml;
            Continue;
          end;
          Pending := Pending + C;
          Inc(I);
        end;
      '&':
        begin
          AfterEntity := ScanEntity(Source, I, Decoded);
          if AfterEntity > 0 then
          begin
            Pending := Pending + Decoded;
            I := AfterEntity;
          end
          else
          begin
            Pending := Pending + C;
            Inc(I);
          end;
        end;
      '!':
        begin
          if (I < Len) and (Source[I + 1] = '[') then
          begin
            IsImage := True;
            AfterLink := ScanLink(Source, I, IsImage,
              LabelText, Url, Title, LabelEnd);
            if AfterLink > 0 then
            begin
              FlushText(Pending, Result);
              // Image alt is the inline-parsed label flattened to plain
              // text by the writer.
              Result.Add(BuildLinkLikeNode(mnImage, Url, Title,
                LabelText, RefDefs, Options));
              I := AfterLink;
              Continue;
            end;
            if (RefDefs <> nil) and TryReferenceLink(Source, I + 1, RefDefs,
              LabelText, Url, Title, AfterLink) then
            begin
              FlushText(Pending, Result);
              Result.Add(BuildLinkLikeNode(mnImage, Url, Title,
                LabelText, RefDefs, Options));
              I := AfterLink;
              Continue;
            end;
          end;
          Pending := Pending + C;
          Inc(I);
        end;
      '[':
        begin
          IsImage := False;
          AfterLink := ScanLink(Source, I, IsImage,
            LabelText, Url, Title, LabelEnd);
          if AfterLink = 0 then
          begin
            if (RefDefs = nil) or not TryReferenceLink(Source, I, RefDefs,
                LabelText, Url, Title, AfterLink) then
            begin
              Pending := Pending + C;
              Inc(I);
              Continue;
            end;
            // Reference-link path: ScanLink didn't run, so derive
            // LabelEnd from the LabelText length.
            LabelEnd := I + Length(LabelText);
          end;
          // Parse the label so the link's children are ready, and so we
          // can apply CommonMark's link-in-link veto. When vetoed, only
          // the bracketed prefix [...] emits literally; the trailing
          // (...) or [ref] is re-parsed as inline so a following
          // shortcut reference still forms its own link.
          InlineList := ParseImpl(LabelText, RefDefs, Options);
          try
            FlushText(Pending, Result);
            if ListHasLinkDescendant(InlineList) then
            begin
              Result.Add(NewText('['));
              while InlineList.Count > 0 do
                Result.Add(InlineList.Extract(InlineList[0]));
              Result.Add(NewText(']'));
              I := LabelEnd + 2;
            end
            else
            begin
              Node := TPixieMdNode.Create(mnLink);
              Node.LinkUrl := Url;
              Node.LinkTitle := Title;
              while InlineList.Count > 0 do
                Node.AddChild(InlineList.Extract(InlineList[0]));
              Result.Add(Node);
              I := AfterLink;
            end;
          finally
            InlineList.Free;
          end;
          Continue;
        end;
      '*', '_':
        begin
          // Run of delimiter chars. Capture preceding and following
          // characters before measuring the run so flanking can be
          // computed; characters past the source bounds are treated as
          // whitespace per CommonMark.
          if I > 1 then
            PrevCh := Source[I - 1]
          else
            PrevCh := ' ';
          RunLen := 0;
          while (I <= Len) and (Source[I] = C) do
          begin
            Inc(RunLen);
            Inc(I);
          end;
          if I <= Len then
            NextCh := Source[I]
          else
            NextCh := ' ';
          ComputeFlanking(C, PrevCh, NextCh, MOpen, MClose);
          FlushText(Pending, Result);
          Marker := TDelimMarker.CreateMarker(C, RunLen, MOpen, MClose);
          if DelimHead = nil then
            DelimHead := Marker
          else
          begin
            Marker.PrevDelim := DelimTail;
            DelimTail.NextDelim := Marker;
          end;
          DelimTail := Marker;
          Result.Add(Marker);
        end;
      '~':
        begin
          if (moGfmStrikethrough in Options) and
             (I + 1 <= Len) and (Source[I + 1] = '~') then
          begin
            // Search for closing ~~
            StrikeStart := I + 2;
            StrikeEnd := StrikeStart;
            while StrikeEnd < Len do
            begin
              if (Source[StrikeEnd] = '~') and
                 (StrikeEnd + 1 <= Len) and (Source[StrikeEnd + 1] = '~') then
                Break;
              Inc(StrikeEnd);
            end;
            if (StrikeEnd < Len) and (Source[StrikeEnd] = '~') and
               (StrikeEnd > StrikeStart) then
            begin
              FlushText(Pending, Result);
              Node := TPixieMdNode.Create(mnStrikethrough);
              InlineList := ParseImpl(
                Copy(Source, StrikeStart, StrikeEnd - StrikeStart),
                RefDefs, Options);
              try
                while InlineList.Count > 0 do
                  Node.AddChild(InlineList.Extract(InlineList[0]));
              finally
                InlineList.Free;
              end;
              Result.Add(Node);
              I := StrikeEnd + 2;
              Continue;
            end;
          end;
          Pending := Pending + C;
          Inc(I);
        end;
      #10:
        begin
          // Soft break: trailing two spaces or backslash at end -> hard break.
          if (Length(Pending) >= 2) and
             (Pending[Length(Pending)] = ' ') and
             (Pending[Length(Pending) - 1] = ' ') then
          begin
            // Strip trailing spaces, emit hard break.
            while (Length(Pending) > 0) and
                  (Pending[Length(Pending)] = ' ') do
              SetLength(Pending, Length(Pending) - 1);
            FlushText(Pending, Result);
            Result.Add(TPixieMdNode.Create(mnLineBreak));
          end
          else
          begin
            // Soft break: trim trailing whitespace, emit soft break.
            while (Length(Pending) > 0) and
                  ((Pending[Length(Pending)] = ' ') or
                   (Pending[Length(Pending)] = #9)) do
              SetLength(Pending, Length(Pending) - 1);
            FlushText(Pending, Result);
            Result.Add(TPixieMdNode.Create(mnSoftBreak));
          end;
          Inc(I);
          // Skip leading whitespace on next line.
          while (I <= Len) and ((Source[I] = ' ') or (Source[I] = #9)) do
            Inc(I);
        end;
      #13:
        Inc(I); // ignore CR
    else
      Pending := Pending + C;
      Inc(I);
    end;
  end;
  FlushText(Pending, Result);

  // Resolve emphasis/strong delimiter pairs.
  ResolveDelimiters(Result, DelimHead);
end;

class function TPixieMdInlineParser.Parse(const Source: string;
  RefDefs: TPixieMdLinkRefMap;
  Options: TPixieMdOptions): TPixieMdNodeList;
begin
  Result := ParseImpl(Source, RefDefs, Options);
end;

// ---------------------------------------------------------------------------
// Tree walk: replace block-parser's raw mnText with parsed inlines
// ---------------------------------------------------------------------------

procedure ProcessBlock(Node: TPixieMdNode; RefDefs: TPixieMdLinkRefMap;
  Options: TPixieMdOptions); forward;

procedure ProcessLeaf(Node: TPixieMdNode; RefDefs: TPixieMdLinkRefMap;
  Options: TPixieMdOptions);
var
  Source: string;
  InlineList: TPixieMdNodeList;
  Child: TPixieMdNode;
begin
  if (Node.ChildCount = 1) and (Node.Children[0].Kind = mnText) then
  begin
    Source := Node.Children[0].Literal;
    Node.Children.Clear;
    InlineList := TPixieMdInlineParser.Parse(Source, RefDefs, Options);
    try
      while InlineList.Count > 0 do
      begin
        Child := InlineList.Extract(InlineList[0]);
        Node.AddChild(Child);
      end;
    finally
      InlineList.Free;
    end;
  end;
end;

procedure ProcessBlock(Node: TPixieMdNode; RefDefs: TPixieMdLinkRefMap;
  Options: TPixieMdOptions);
var
  I: Integer;
begin
  case Node.Kind of
    mnDocument, mnBlockQuote, mnList, mnListItem, mnTable, mnTableRow:
      if Node.HasChildren then
        for I := 0 to Node.ChildCount - 1 do
          ProcessBlock(Node.Children[I], RefDefs, Options);
    mnHeading, mnParagraph, mnTableCell:
      ProcessLeaf(Node, RefDefs, Options);
    mnCodeBlock:
      // The block parser stores fenced-code info verbatim; CommonMark
      // says it's processed like a link destination.
      Node.CodeLang := MdProcessLinkPart(Node.CodeLang);
    // mnHtmlBlock, mnThematicBreak: nothing to do
  end;
end;

class procedure TPixieMdInlineParser.ParseInlinesIntoBlocks(Doc: TPixieMdNode;
  RefDefs: TPixieMdLinkRefMap; Options: TPixieMdOptions);
begin
  if Doc <> nil then
    ProcessBlock(Doc, RefDefs, Options);
end;

end.
