unit Pixie.Markdown.Parser;

// Markdown block parser. Walks the input line by line, maintaining a
// stack of open container blocks (document, blockquote, list, list-item)
// and at most one open leaf block (paragraph, code block, HTML block,
// heading), and emits an AST of block nodes.
//
// Block-level only: leaf blocks contain a single mnText child whose
// Literal holds the raw inline source. The inline parser
// (TPixieMdInlineParser.ParseInlinesIntoBlocks) replaces those text
// children with parsed inline trees.
//
// Implements ATX and setext headings, thematic breaks, blockquotes,
// fenced and indented code blocks, ordered and unordered lists with
// nesting, basic HTML blocks, paragraphs, lazy continuation, YAML
// front-matter stripping, GFM tables, GFM task list items, and
// single-line link reference definitions.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Classes, SysUtils, Generics.Collections,
  Pixie.Markdown.Types;

type
  TPixieMdLinkRef = record
    Url: string;
    Title: string;
  end;
  TPixieMdLinkRefMap = TDictionary<string, TPixieMdLinkRef>;

  TPixieMdParser = class
  public
    class function ParseBlocks(const Md: string;
      RefDefs: TPixieMdLinkRefMap = nil;
      Options: TPixieMdOptions = DefaultPixieMdOptions): TPixieMdNode;
  end;

procedure PixieMdSplitLines(const S: string; out Lines: TArray<string>);
function NormalizeLinkLabel(const S: string): string;

implementation

// ---------------------------------------------------------------------------
// Line splitting
// ---------------------------------------------------------------------------

procedure PixieMdSplitLines(const S: string; out Lines: TArray<string>);
var
  Buf: TList<string>;
  I, Start, Len: Integer;
  C: Char;
begin
  Buf := TList<string>.Create;
  try
    Len := Length(S);
    Start := 1;
    I := 1;
    while I <= Len do
    begin
      C := S[I];
      if C = #10 then
      begin
        Buf.Add(Copy(S, Start, I - Start));
        Inc(I);
        Start := I;
      end
      else if C = #13 then
      begin
        Buf.Add(Copy(S, Start, I - Start));
        Inc(I);
        if (I <= Len) and (S[I] = #10) then
          Inc(I);
        Start := I;
      end
      else
        Inc(I);
    end;
    if Start <= Len then
      Buf.Add(Copy(S, Start, Len - Start + 1));
    Lines := Buf.ToArray;
  finally
    Buf.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Whitespace / character helpers
// ---------------------------------------------------------------------------

function IsBlankLine(const S: string): Boolean;
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    if (S[I] <> ' ') and (S[I] <> #9) then
      Exit(False);
  Result := True;
end;

// Returns column count consumed and updates Offset (1-based), counting
// tabs as advancing to the next tab stop (4-col).
procedure SkipIndent(const S: string; var Offset: Integer; MaxCols: Integer;
  out Consumed: Integer);
begin
  Consumed := 0;
  while (Offset <= Length(S)) and (Consumed < MaxCols) do
  begin
    if S[Offset] = ' ' then
      Inc(Consumed)
    else if S[Offset] = #9 then
      Consumed := Consumed + (4 - (Consumed mod 4))
    else
      Break;
    Inc(Offset);
  end;
end;

procedure StripTrailingLf(var S: string);
begin
  if (Length(S) > 0) and (S[Length(S)] = #10) then
    SetLength(S, Length(S) - 1);
end;

function StripTrailingWhitespace(const S: string): string;
var
  I: Integer;
begin
  I := Length(S);
  while (I >= 1) and ((S[I] = ' ') or (S[I] = #9)) do
    Dec(I);
  Result := Copy(S, 1, I);
end;

function TrimSpaces(const S: string): string;
var
  I, J: Integer;
begin
  I := 1;
  while (I <= Length(S)) and ((S[I] = ' ') or (S[I] = #9)) do
    Inc(I);
  J := Length(S);
  while (J >= I) and ((S[J] = ' ') or (S[J] = #9)) do
    Dec(J);
  Result := Copy(S, I, J - I + 1);
end;

// ---------------------------------------------------------------------------
// Block-start probes
// ---------------------------------------------------------------------------

// ATX heading: 1-6 #s followed by space/tab/EOL. Returns level or 0.
function ProbeAtxHeading(const S: string; Offset: Integer;
  out ContentStart, ContentEnd: Integer): Integer;
var
  HashCount, I, Len: Integer;
  TailStart, TailEnd: Integer;
begin
  Result := 0;
  Len := Length(S);
  HashCount := 0;
  I := Offset;
  while (I <= Len) and (S[I] = '#') and (HashCount < 7) do
  begin
    Inc(HashCount);
    Inc(I);
  end;
  if (HashCount = 0) or (HashCount > 6) then Exit;
  if (I <= Len) and (S[I] <> ' ') and (S[I] <> #9) then Exit;
  while (I <= Len) and ((S[I] = ' ') or (S[I] = #9)) do Inc(I);
  ContentStart := I;
  TailEnd := Len;
  while (TailEnd >= ContentStart) and
        ((S[TailEnd] = ' ') or (S[TailEnd] = #9)) do
    Dec(TailEnd);
  TailStart := TailEnd;
  while (TailStart >= ContentStart) and (S[TailStart] = '#') do
    Dec(TailStart);
  if (TailStart < TailEnd) and (TailStart >= ContentStart) and
     ((S[TailStart] = ' ') or (S[TailStart] = #9)) then
  begin
    while (TailStart >= ContentStart) and
          ((S[TailStart] = ' ') or (S[TailStart] = #9)) do
      Dec(TailStart);
    ContentEnd := TailStart;
  end
  else if (TailStart < ContentStart) and (TailEnd >= ContentStart) then
    ContentEnd := ContentStart - 1
  else
    ContentEnd := TailEnd;
  Result := HashCount;
end;

function ProbeSetextUnderline(const S: string; Offset: Integer): Integer;
var
  I, Len: Integer;
  C: Char;
  HasContent: Boolean;
begin
  Result := 0;
  Len := Length(S);
  I := Offset;
  if I > Len then Exit;
  C := S[I];
  if (C <> '=') and (C <> '-') then Exit;
  HasContent := False;
  while (I <= Len) and (S[I] = C) do
  begin
    HasContent := True;
    Inc(I);
  end;
  if not HasContent then Exit;
  while I <= Len do
  begin
    if (S[I] <> ' ') and (S[I] <> #9) then Exit;
    Inc(I);
  end;
  if C = '=' then Result := 1 else Result := 2;
end;

function ProbeThematicBreak(const S: string; Offset: Integer): Boolean;
var
  I, Len, Count: Integer;
  C, Marker: Char;
begin
  Result := False;
  Len := Length(S);
  I := Offset;
  if I > Len then Exit;
  Marker := S[I];
  if (Marker <> '-') and (Marker <> '_') and (Marker <> '*') then Exit;
  Count := 0;
  while I <= Len do
  begin
    C := S[I];
    if C = Marker then
      Inc(Count)
    else if (C <> ' ') and (C <> #9) then
      Exit;
    Inc(I);
  end;
  Result := Count >= 3;
end;

function ProbeFence(const S: string; Offset: Integer;
  out FenceLen: Integer; out InfoStart, InfoEnd: Integer): Char;
var
  I, Len, J: Integer;
  Marker: Char;
begin
  Result := #0;
  FenceLen := 0;
  Len := Length(S);
  I := Offset;
  if I > Len then Exit;
  Marker := S[I];
  if (Marker <> '`') and (Marker <> '~') then Exit;
  while (I <= Len) and (S[I] = Marker) do
  begin
    Inc(FenceLen);
    Inc(I);
  end;
  if FenceLen < 3 then Exit;
  InfoStart := I;
  InfoEnd := Len;
  if Marker = '`' then
  begin
    J := InfoStart;
    while J <= InfoEnd do
    begin
      if S[J] = '`' then Exit;
      Inc(J);
    end;
  end;
  Result := Marker;
end;

function IsClosingFence(const S: string; Offset: Integer;
  Marker: Char; MinLen: Integer): Boolean;
var
  I, Len, Count: Integer;
begin
  Result := False;
  Len := Length(S);
  I := Offset;
  Count := 0;
  while (I <= Len) and (S[I] = Marker) do
  begin
    Inc(Count);
    Inc(I);
  end;
  if Count < MinLen then Exit;
  while I <= Len do
  begin
    if (S[I] <> ' ') and (S[I] <> #9) then Exit;
    Inc(I);
  end;
  Result := True;
end;

function ProbeListMarker(const S: string; Offset: Integer;
  out IsOrdered: Boolean; out ListChar: Char; out OrderedStart: Integer;
  out AfterMarker: Integer): Integer;
var
  I, Len, Digits: Integer;
  C: Char;
  NumStr: string;
begin
  Result := 0;
  IsOrdered := False;
  ListChar := #0;
  OrderedStart := 1;
  AfterMarker := Offset;
  Len := Length(S);
  I := Offset;
  if I > Len then Exit;
  C := S[I];
  if (C = '-') or (C = '*') or (C = '+') then
  begin
    if (I + 1 > Len) or (S[I + 1] = ' ') or (S[I + 1] = #9) then
    begin
      ListChar := C;
      AfterMarker := I + 1;
      Result := 1;
      Exit;
    end;
  end
  else if (C >= '0') and (C <= '9') then
  begin
    Digits := 0;
    NumStr := '';
    while (I <= Len) and (S[I] >= '0') and (S[I] <= '9') and (Digits < 9) do
    begin
      NumStr := NumStr + S[I];
      Inc(Digits);
      Inc(I);
    end;
    if Digits = 0 then Exit;
    if (I > Len) then Exit;
    if (S[I] <> '.') and (S[I] <> ')') then Exit;
    ListChar := S[I];
    Inc(I);
    if (I <= Len) and (S[I] <> ' ') and (S[I] <> #9) then Exit;
    IsOrdered := True;
    OrderedStart := StrToIntDef(NumStr, 1);
    AfterMarker := I;
    Result := I - Offset;
  end;
end;

function ProbeBlockQuote(const S: string; Offset: Integer): Integer;
var
  I, Spaces: Integer;
begin
  Result := 0;
  I := Offset;
  Spaces := 0;
  while (I <= Length(S)) and (S[I] = ' ') and (Spaces < 3) do
  begin
    Inc(I);
    Inc(Spaces);
  end;
  if (I > Length(S)) or (S[I] <> '>') then Exit;
  Inc(I);
  if (I <= Length(S)) and ((S[I] = ' ') or (S[I] = #9)) then
    Inc(I);
  Result := I;
end;

// HTML block start: returns 1-7 type or 0. Conservative subset that
// covers the common cases (script/pre/style/textarea, comments, CDATA,
// known block-level tags). Type 7 (any complete tag with whitespace)
// not implemented to avoid false positives breaking paragraphs.
function ProbeHtmlBlockStart(const S: string; Offset: Integer): Integer;
const
  Type1: array[0..3] of string = ('script', 'pre', 'style', 'textarea');
  Type6Tags: array[0..61] of string = (
    'address', 'article', 'aside', 'base', 'basefont', 'blockquote',
    'body', 'caption', 'center', 'col', 'colgroup', 'dd', 'details',
    'dialog', 'dir', 'div', 'dl', 'dt', 'fieldset', 'figcaption',
    'figure', 'footer', 'form', 'frame', 'frameset', 'h1', 'h2', 'h3',
    'h4', 'h5', 'h6', 'head', 'header', 'hr', 'html', 'iframe',
    'legend', 'li', 'link', 'main', 'menu', 'menuitem', 'nav',
    'noframes', 'ol', 'optgroup', 'option', 'p', 'param', 'section',
    'source', 'summary', 'table', 'tbody', 'td', 'tfoot', 'th',
    'thead', 'title', 'tr', 'track', 'ul');
var
  Rest: string;
  TagStart, TagEnd, I: Integer;
  Tag: string;
  After: Char;
begin
  Result := 0;
  if (Offset > Length(S)) or (S[Offset] <> '<') then Exit;
  Rest := Copy(S, Offset, Length(S) - Offset + 1);
  if Length(Rest) < 2 then Exit;

  if (Length(Rest) >= 4) and (Copy(Rest, 1, 4) = '<!--') then Exit(2);
  if (Length(Rest) >= 2) and (Copy(Rest, 1, 2) = '<?') then Exit(3);
  if (Length(Rest) >= 3) and (Rest[2] = '!') and
     (Rest[3] >= 'A') and (Rest[3] <= 'Z') then Exit(4);
  if (Length(Rest) >= 9) and (Copy(Rest, 1, 9) = '<![CDATA[') then Exit(5);

  if Rest[2] = '/' then
    TagStart := 3
  else
    TagStart := 2;
  if TagStart > Length(Rest) then Exit;
  if not (((Rest[TagStart] >= 'a') and (Rest[TagStart] <= 'z')) or
          ((Rest[TagStart] >= 'A') and (Rest[TagStart] <= 'Z'))) then Exit;
  TagEnd := TagStart;
  while (TagEnd <= Length(Rest)) and
        (((Rest[TagEnd] >= 'a') and (Rest[TagEnd] <= 'z')) or
         ((Rest[TagEnd] >= 'A') and (Rest[TagEnd] <= 'Z')) or
         ((Rest[TagEnd] >= '0') and (Rest[TagEnd] <= '9')) or
         (Rest[TagEnd] = '-')) do
    Inc(TagEnd);
  Tag := LowerCase(Copy(Rest, TagStart, TagEnd - TagStart));
  if TagEnd > Length(Rest) then
    After := ' '
  else
    After := Rest[TagEnd];
  if (After = ' ') or (After = #9) or (After = '>') or
     ((After = '/') and (TagEnd + 1 <= Length(Rest)) and
      (Rest[TagEnd + 1] = '>')) then
  begin
    for I := 0 to High(Type1) do
      if Tag = Type1[I] then Exit(1);
    for I := 0 to High(Type6Tags) do
      if Tag = Type6Tags[I] then Exit(6);
  end;
end;

function IsHtmlBlockEnd(const S: string; StartType: Integer): Boolean;
var
  Lower: string;
begin
  case StartType of
    1:
      begin
        Lower := LowerCase(S);
        Result := (Pos('</script>', Lower) > 0) or
                  (Pos('</pre>', Lower) > 0) or
                  (Pos('</style>', Lower) > 0) or
                  (Pos('</textarea>', Lower) > 0);
      end;
    2: Result := Pos('-->', S) > 0;
    3: Result := Pos('?>', S) > 0;
    4: Result := Pos('>', S) > 0;
    5: Result := Pos(']]>', S) > 0;
    6, 7: Result := IsBlankLine(S);
  else
    Result := True;
  end;
end;

// GFM task list marker: [ ] or [x] or [X] followed by space/EOL.
// Returns offset after marker (and trailing space) or 0.
function ProbeTaskMarker(const S: string; Offset: Integer;
  out Checked: Boolean): Integer;
var
  Len: Integer;
  C: Char;
begin
  Result := 0;
  Checked := False;
  Len := Length(S);
  if Offset + 2 > Len then Exit;
  if S[Offset] <> '[' then Exit;
  C := S[Offset + 1];
  if (C <> ' ') and (C <> 'x') and (C <> 'X') then Exit;
  if S[Offset + 2] <> ']' then Exit;
  if (Offset + 3 <= Len) and (S[Offset + 3] <> ' ') and
     (S[Offset + 3] <> #9) then Exit;
  Checked := (C = 'x') or (C = 'X');
  Result := Offset + 3;
  if (Result <= Len) and ((S[Result] = ' ') or (S[Result] = #9)) then
    Inc(Result);
end;

// GFM table delimiter row: optional leading | then cells of dashes with
// optional flanking colons. Returns column count or 0; fills Aligns.
function ProbeTableDelimiter(const S: string; Offset: Integer;
  out Aligns: TArray<TPixieMdCellAlign>): Integer;
var
  I, Len, Start, J, DashCount: Integer;
  Cell, Trimmed: string;
  Left, Right: Boolean;
  Cols: TList<TPixieMdCellAlign>;
begin
  Result := 0;
  Aligns := nil;
  Len := Length(S);
  I := Offset;
  while (I <= Len) and ((S[I] = ' ') or (S[I] = #9)) do Inc(I);
  if (I <= Len) and (S[I] = '|') then Inc(I);
  Cols := TList<TPixieMdCellAlign>.Create;
  try
    while I <= Len do
    begin
      Start := I;
      while (I <= Len) and (S[I] <> '|') do Inc(I);
      Cell := Copy(S, Start, I - Start);
      Trimmed := TrimSpaces(Cell);
      if Trimmed = '' then
      begin
        if I > Len then Break;
        Exit;
      end;
      Left := False;
      Right := False;
      J := 1;
      if (J <= Length(Trimmed)) and (Trimmed[J] = ':') then
      begin
        Left := True;
        Inc(J);
      end;
      DashCount := 0;
      while (J <= Length(Trimmed)) and (Trimmed[J] = '-') do
      begin
        Inc(J);
        Inc(DashCount);
      end;
      if (J <= Length(Trimmed)) and (Trimmed[J] = ':') then
      begin
        Right := True;
        Inc(J);
      end;
      if (DashCount = 0) or (J <= Length(Trimmed)) then Exit;
      if Left and Right then Cols.Add(maCenter)
      else if Right then Cols.Add(maRight)
      else if Left then Cols.Add(maLeft)
      else Cols.Add(maNone);
      if I <= Len then Inc(I);
    end;
    if Cols.Count = 0 then Exit;
    Aligns := Cols.ToArray;
    Result := Cols.Count;
  finally
    Cols.Free;
  end;
end;

// Splits a GFM table row line into cell strings. Pipes are escapable
// as \| within cell content.
procedure SplitTableRow(const S: string; out Cells: TArray<string>);
var
  Buf: TList<string>;
  Cur: string;
  CellStart, I, Len: Integer;
  HasEscape: Boolean;

  procedure FlushCell;
  begin
    if HasEscape then
      Buf.Add(TrimSpaces(Cur))
    else
      Buf.Add(TrimSpaces(Copy(S, CellStart, I - CellStart)));
    Cur := '';
    HasEscape := False;
  end;

begin
  Buf := TList<string>.Create;
  try
    Len := Length(S);
    I := 1;
    while (I <= Len) and ((S[I] = ' ') or (S[I] = #9)) do Inc(I);
    if (I <= Len) and (S[I] = '|') then Inc(I);
    CellStart := I;
    Cur := '';
    HasEscape := False;
    while I <= Len do
    begin
      if (S[I] = '\') and (I < Len) and (S[I + 1] = '|') then
      begin
        // Materialise the prefix into Cur so we can strip the backslash.
        if not HasEscape then
        begin
          Cur := Copy(S, CellStart, I - CellStart);
          HasEscape := True;
        end;
        Cur := Cur + '|';
        Inc(I, 2);
      end
      else if S[I] = '|' then
      begin
        FlushCell;
        Inc(I);
        CellStart := I;
      end
      else
      begin
        if HasEscape then
          Cur := Cur + S[I];
        Inc(I);
      end;
    end;
    if HasEscape then
      Cur := TrimSpaces(Cur)
    else
      Cur := TrimSpaces(Copy(S, CellStart, I - CellStart));
    if (Cur <> '') or (Buf.Count = 0) then
      Buf.Add(Cur);
    Cells := Buf.ToArray;
  finally
    Buf.Free;
  end;
end;

// Normalises a link-reference label per CommonMark: trim, lowercase
// ASCII, collapse internal whitespace runs to a single space.
function NormalizeLinkLabel(const S: string): string;
var
  I, Len, Out_: Integer;
  C: Char;
  PrevSpace: Boolean;
begin
  Len := Length(S);
  SetLength(Result, Len);
  Out_ := 0;
  PrevSpace := False;
  for I := 1 to Len do
  begin
    C := S[I];
    case C of
      ' ', #9, #10, #13:
        if not PrevSpace and (Out_ > 0) then
        begin
          Inc(Out_);
          Result[Out_] := ' ';
          PrevSpace := True;
        end;
      'A'..'Z':
        begin
          Inc(Out_);
          Result[Out_] := Chr(Ord(C) + 32);
          PrevSpace := False;
        end;
    else
      Inc(Out_);
      Result[Out_] := C;
      PrevSpace := False;
    end;
  end;
  if (Out_ > 0) and (Result[Out_] = ' ') then
    Dec(Out_);
  SetLength(Result, Out_);
end;

// Tries to consume a single-line link reference definition from Source
// starting at Cursor (1-based). On success, advances Cursor past the
// consumed characters (including the trailing newline if present) and
// returns True. On failure, Cursor is unchanged and the function
// returns False. The resolved (label, url, title) entry is added to
// RefMap keyed by NormalizeLinkLabel(label).
function TryConsumeLinkRefDef(const Source: string; var Cursor: Integer;
  RefMap: TPixieMdLinkRefMap): Boolean;
var
  I, Len, LabelStart, LabelEnd, TitleStart, UrlStart, SpaceCount: Integer;
  Label_, Url, Title: string;
  TitleQuote: Char;
  Saved: Integer;
  Ref: TPixieMdLinkRef;
  Key: string;
begin
  Result := False;
  Len := Length(Source);
  I := Cursor;
  SpaceCount := 0;
  while (I <= Len) and (Source[I] = ' ') and (SpaceCount < 3) do
  begin
    Inc(I);
    Inc(SpaceCount);
  end;
  if (I > Len) or (Source[I] <> '[') then Exit;
  Inc(I);
  LabelStart := I;
  while I <= Len do
  begin
    if Source[I] = ']' then Break;
    if Source[I] = '\' then Inc(I);
    if (I > Len) or (Source[I] = #10) or (Source[I] = #13) then Exit;
    Inc(I);
  end;
  if (I > Len) or (Source[I] <> ']') then Exit;
  LabelEnd := I - 1;
  Inc(I);
  if (I > Len) or (Source[I] <> ':') then Exit;
  Inc(I);
  while (I <= Len) and ((Source[I] = ' ') or (Source[I] = #9)) do Inc(I);
  if I > Len then Exit;

  if Source[I] = '<' then
  begin
    Inc(I);
    UrlStart := I;
    while (I <= Len) and (Source[I] <> '>') and
          (Source[I] <> #10) and (Source[I] <> #13) do
      Inc(I);
    if (I > Len) or (Source[I] <> '>') then Exit;
    Url := Copy(Source, UrlStart, I - UrlStart);
    Inc(I);
  end
  else
  begin
    UrlStart := I;
    while (I <= Len) and (Source[I] > ' ') do
      Inc(I);
    Url := Copy(Source, UrlStart, I - UrlStart);
    if Url = '' then Exit;
  end;

  Title := '';
  Saved := I;
  while (I <= Len) and ((Source[I] = ' ') or (Source[I] = #9)) do Inc(I);
  if (I <= Len) and ((Source[I] = '"') or (Source[I] = '''') or
     (Source[I] = '(')) then
  begin
    if Source[I] = '(' then TitleQuote := ')'
    else TitleQuote := Source[I];
    Inc(I);
    TitleStart := I;
    while (I <= Len) and (Source[I] <> TitleQuote) and
          (Source[I] <> #10) do
    begin
      if Source[I] = '\' then Inc(I);
      Inc(I);
    end;
    if (I <= Len) and (Source[I] = TitleQuote) then
    begin
      Title := Copy(Source, TitleStart, I - TitleStart);
      Inc(I);
    end
    else
      I := Saved;
  end;

  while (I <= Len) and ((Source[I] = ' ') or (Source[I] = #9)) do Inc(I);
  if (I <= Len) and (Source[I] <> #10) and (Source[I] <> #13) then Exit;

  // Consume line terminator.
  if (I <= Len) and (Source[I] = #13) then Inc(I);
  if (I <= Len) and (Source[I] = #10) then Inc(I);

  Label_ := TrimSpaces(Copy(Source, LabelStart, LabelEnd - LabelStart + 1));
  if Label_ = '' then Exit;
  Key := NormalizeLinkLabel(Label_);
  if not RefMap.ContainsKey(Key) then
  begin
    Ref.Url := Url;
    Ref.Title := Title;
    RefMap.Add(Key, Ref);
  end;
  Cursor := I;
  Result := True;
end;

function LineHasUnescapedPipe(const S: string): Boolean;
var
  I, Len: Integer;
begin
  Len := Length(S);
  I := 1;
  while I <= Len do
  begin
    if S[I] = '\' then Inc(I, 2)
    else
    begin
      if S[I] = '|' then Exit(True);
      Inc(I);
    end;
  end;
  Result := False;
end;

// ---------------------------------------------------------------------------
// Open-block stack
// ---------------------------------------------------------------------------

type
  TOpenBlockKind = (
    obDocument, obBlockQuote, obList, obListItem,
    obParagraph, obFencedCode, obIndentedCode, obHtmlBlock, obHeading,
    obTable);

  TOpenBlock = class
    Node: TPixieMdNode;
    Kind: TOpenBlockKind;
    ListContentIndent: Integer;
    // For obList: the marker character ('-', '*', '+') or delimiter
    // ('.' / ')' for ordered). Different markers split into separate
    // lists per CommonMark.
    ListChar: Char;
    // For obList: pending blank seen; consumed when the next item or
    // sub-block joins (loose) or when the list closes (ignored).
    HadBlank: Boolean;
    FenceChar: Char;
    FenceLen: Integer;
    FenceIndent: Integer;
    HtmlStartType: Integer;
    Text: string;
    TableAligns: TArray<TPixieMdCellAlign>;
  end;

  TPixieMdParserImpl = class
  private
    FSource: string;
    FLines: TArray<string>;
    FOptions: TPixieMdOptions;
    FOpen: TList<TOpenBlock>;
    FDoc: TPixieMdNode;
    FRefDefs: TPixieMdLinkRefMap;
    FOwnsRefDefs: Boolean;

    procedure StripFrontMatter;
    function LineWouldStartBlock(const Line: string;
      Offset: Integer): Boolean;
    procedure ProcessLine(const Line: string;
      MatchContainers: Boolean = True);
    function MatchOpenContainers(const Line: string;
      var Offset: Integer): Integer;
    procedure CloseBlocksFrom(Index: Integer);
    procedure CloseBlock(OB: TOpenBlock);
    function DeepestLeaf: TOpenBlock;
    function CurrentContainer: TOpenBlock;
    procedure AddToContainer(Node: TPixieMdNode);
    procedure AddLeaf(OB: TOpenBlock);
    function InnermostOpenList: Integer;
    procedure ConfirmListLoose;
    procedure AppendToParagraph(const Text: string);
    function TryStartListItem(const Line: string;
      var Offset: Integer): Boolean;
    function TryStartTable(const Line: string; Offset: Integer): Boolean;
    procedure AppendTableRow(TableOB: TOpenBlock; const RowLine: string);
  public
    constructor Create(const Md: string; Options: TPixieMdOptions;
      RefDefs: TPixieMdLinkRefMap);
    destructor Destroy; override;
    function Parse: TPixieMdNode;
  end;

constructor TPixieMdParserImpl.Create(const Md: string;
  Options: TPixieMdOptions; RefDefs: TPixieMdLinkRefMap);
begin
  inherited Create;
  FSource := Md;
  FOptions := Options;
  FOpen := TList<TOpenBlock>.Create;
  if RefDefs = nil then
  begin
    FRefDefs := TPixieMdLinkRefMap.Create;
    FOwnsRefDefs := True;
  end
  else
  begin
    FRefDefs := RefDefs;
    FOwnsRefDefs := False;
  end;
end;

destructor TPixieMdParserImpl.Destroy;
var
  I: Integer;
begin
  if FOpen <> nil then
  begin
    for I := 0 to FOpen.Count - 1 do
      FOpen[I].Free;
    FOpen.Free;
  end;
  if FOwnsRefDefs then
    FRefDefs.Free;
  inherited Destroy;
end;

procedure TPixieMdParserImpl.StripFrontMatter;
var
  I, Last: Integer;
begin
  if Length(FLines) < 2 then Exit;
  if TrimSpaces(FLines[0]) <> '---' then Exit;
  Last := -1;
  for I := 1 to High(FLines) do
    if TrimSpaces(FLines[I]) = '---' then
    begin
      Last := I;
      Break;
    end;
  if Last < 0 then Exit;
  if (Last + 1 <= High(FLines)) and IsBlankLine(FLines[Last + 1]) then
    Inc(Last);
  FLines := Copy(FLines, Last + 1, Length(FLines) - Last - 1);
end;

function TPixieMdParserImpl.CurrentContainer: TOpenBlock;
var
  I: Integer;
begin
  Result := nil;
  for I := FOpen.Count - 1 downto 0 do
    if FOpen[I].Kind in [obDocument, obBlockQuote, obList, obListItem] then
      Exit(FOpen[I]);
end;

function TPixieMdParserImpl.DeepestLeaf: TOpenBlock;
begin
  Result := nil;
  if FOpen.Count = 0 then Exit;
  Result := FOpen[FOpen.Count - 1];
  if Result.Kind in [obDocument, obBlockQuote, obList, obListItem] then
    Result := nil;
end;

procedure TPixieMdParserImpl.AddToContainer(Node: TPixieMdNode);
var
  Container: TOpenBlock;
begin
  Container := CurrentContainer;
  if (Container = nil) or (Container.Node = nil) then
    FDoc.AddChild(Node)
  else
    Container.Node.AddChild(Node);
end;

function TPixieMdParserImpl.InnermostOpenList: Integer;
var
  I: Integer;
begin
  for I := FOpen.Count - 1 downto 0 do
    if FOpen[I].Kind = obList then Exit(I);
  Result := -1;
end;

// CommonMark "loose": when starting a new block while a list is open
// and a blank was seen inside it, the list is loose. Only the innermost
// open list matters since the blank/new block are inside it.
procedure TPixieMdParserImpl.ConfirmListLoose;
var
  Idx: Integer;
begin
  Idx := InnermostOpenList;
  if (Idx >= 0) and FOpen[Idx].HadBlank then
  begin
    FOpen[Idx].Node.ListTight := False;
    FOpen[Idx].HadBlank := False;
  end;
end;

procedure TPixieMdParserImpl.AddLeaf(OB: TOpenBlock);
begin
  // A list only legally contains list-items. When the topmost open
  // container is a bare list (its last item just closed) and we're
  // adding any other leaf, close the list first so the leaf becomes a
  // sibling of the list, not a stray child.
  while (FOpen.Count > 0) and (FOpen[FOpen.Count - 1].Kind = obList) do
    CloseBlocksFrom(FOpen.Count - 1);
  ConfirmListLoose;
  AddToContainer(OB.Node);
  FOpen.Add(OB);
end;

procedure TPixieMdParserImpl.AppendToParagraph(const Text: string);
var
  OB: TOpenBlock;
  Para: TPixieMdNode;
begin
  OB := DeepestLeaf;
  if (OB <> nil) and (OB.Kind = obParagraph) then
  begin
    if OB.Text <> '' then OB.Text := OB.Text + #10;
    OB.Text := OB.Text + Text;
    Exit;
  end;
  if OB <> nil then
    CloseBlocksFrom(FOpen.IndexOf(OB));
  Para := TPixieMdNode.Create(mnParagraph);
  OB := TOpenBlock.Create;
  OB.Node := Para;
  OB.Kind := obParagraph;
  OB.Text := Text;
  AddLeaf(OB);
end;

procedure TPixieMdParserImpl.CloseBlock(OB: TOpenBlock);
var
  S: string;
  TextChild: TPixieMdNode;
  Cursor: Integer;
  Parent: TPixieMdNode;
  ParentIdx: Integer;
begin
  case OB.Kind of
    obParagraph:
      begin
        // Drain link reference definitions from the start of the
        // paragraph; they vanish from rendered output but populate
        // FRefDefs for the inline parser to resolve [text][label].
        Cursor := 1;
        while TryConsumeLinkRefDef(OB.Text, Cursor, FRefDefs) do
          ;
        if Cursor > 1 then
          S := Copy(OB.Text, Cursor, Length(OB.Text) - Cursor + 1)
        else
          S := OB.Text;
        S := TrimSpaces(S);
        if S = '' then
        begin
          // Whole paragraph was ref defs — drop the empty paragraph node.
          ParentIdx := FOpen.IndexOf(OB);
          if ParentIdx > 0 then
            Parent := FOpen[ParentIdx - 1].Node
          else
            Parent := FDoc;
          if Parent = nil then Parent := FDoc;
          Parent.Children.Extract(OB.Node);
          OB.Node.Free;
          OB.Node := nil;
        end
        else
        begin
          TextChild := TPixieMdNode.Create(mnText);
          TextChild.Literal := S;
          OB.Node.AddChild(TextChild);
        end;
      end;
    obHeading:
      begin
        // Raw inline source becomes a single mnText child here; the
        // inline parser later replaces it with the parsed inline tree.
        S := TrimSpaces(OB.Text);
        if S <> '' then
        begin
          TextChild := TPixieMdNode.Create(mnText);
          TextChild.Literal := S;
          OB.Node.AddChild(TextChild);
        end;
      end;
    obFencedCode, obIndentedCode, obHtmlBlock:
      begin
        // Line accumulator uses bare LF; CommonMark output keeps literal
        // LFs so the trailing one (sentinel from the last appended line)
        // is dropped here.
        S := OB.Text;
        StripTrailingLf(S);
        OB.Node.Literal := S;
      end;
  end;
end;

procedure TPixieMdParserImpl.CloseBlocksFrom(Index: Integer);
var
  I: Integer;
begin
  for I := FOpen.Count - 1 downto Index do
  begin
    CloseBlock(FOpen[I]);
    FOpen[I].Free;
    FOpen.Delete(I);
  end;
end;

function TPixieMdParserImpl.LineWouldStartBlock(const Line: string;
  Offset: Integer): Boolean;
var
  TmpOff, Indent, TmpCS, TmpCE, FenceLen, InfoStart, InfoEnd: Integer;
  TmpOrdered: Boolean;
  TmpListChar: Char;
  TmpStart, TmpAfter, TmpLen: Integer;
begin
  TmpOff := Offset;
  SkipIndent(Line, TmpOff, 3, Indent);
  if ProbeAtxHeading(Line, TmpOff, TmpCS, TmpCE) > 0 then Exit(True);
  if ProbeThematicBreak(Line, TmpOff) then Exit(True);
  if ProbeFence(Line, TmpOff, FenceLen, InfoStart, InfoEnd) <> #0 then
    Exit(True);
  if ProbeBlockQuote(Line, TmpOff) > 0 then Exit(True);
  TmpLen := ProbeListMarker(Line, TmpOff, TmpOrdered, TmpListChar,
    TmpStart, TmpAfter);
  if TmpLen > 0 then Exit(True);
  Result := False;
end;

function TPixieMdParserImpl.MatchOpenContainers(const Line: string;
  var Offset: Integer): Integer;
var
  I, NewOffset, Indent, AfterBq: Integer;
  OB: TOpenBlock;
begin
  Result := FOpen.Count;
  for I := 1 to FOpen.Count - 1 do
  begin
    OB := FOpen[I];
    case OB.Kind of
      obBlockQuote:
        begin
          AfterBq := ProbeBlockQuote(Line, Offset);
          if AfterBq = 0 then Exit(I);
          Offset := AfterBq;
        end;
      obListItem:
        begin
          if IsBlankLine(Line) then Continue;
          NewOffset := Offset;
          SkipIndent(Line, NewOffset, OB.ListContentIndent, Indent);
          if Indent < OB.ListContentIndent then Exit(I);
          Offset := NewOffset;
        end;
      obList: ;
      obFencedCode: ;
      obIndentedCode:
        begin
          // Verify 4 cols of indent but leave Offset unchanged: the
          // indented-code branch in ProcessLine re-strips 4 itself so
          // excess indentation is preserved verbatim in the code text.
          if IsBlankLine(Line) then Continue;
          NewOffset := Offset;
          SkipIndent(Line, NewOffset, 4, Indent);
          if Indent < 4 then Exit(I);
        end;
      obHtmlBlock: ;
      obParagraph:
        begin
          if IsBlankLine(Line) then Exit(I);
        end;
      obHeading: Exit(I);
    end;
  end;
end;

function TPixieMdParserImpl.TryStartListItem(const Line: string;
  var Offset: Integer): Boolean;
var
  PreSpaces, Tmp, MarkerLen, ContentIndent, OrderedStart, AfterMarker: Integer;
  IsOrdered: Boolean;
  ListChar: Char;
  Container, ListOB, ItemOB: TOpenBlock;
  ListNode, ItemNode: TPixieMdNode;
  I, ListIdx, TaskAfter: Integer;
  TaskChecked: Boolean;
begin
  Result := False;
  PreSpaces := 0;
  Tmp := Offset;
  while (Tmp <= Length(Line)) and (Line[Tmp] = ' ') and (PreSpaces < 4) do
  begin
    Inc(Tmp);
    Inc(PreSpaces);
  end;
  if PreSpaces >= 4 then Exit;
  MarkerLen := ProbeListMarker(Line, Tmp,
    IsOrdered, ListChar, OrderedStart, AfterMarker);
  if MarkerLen = 0 then Exit;

  // CommonMark: ordered lists with start <> 1 cannot interrupt a
  // paragraph; an empty list item also cannot. Without these
  // restrictions a stray "14. ..." in a wrapped paragraph would split
  // it into a list.
  if (DeepestLeaf <> nil) and (DeepestLeaf.Kind = obParagraph) then
  begin
    if IsOrdered and (OrderedStart <> 1) then Exit;
    if IsBlankLine(Copy(Line, AfterMarker, Length(Line))) then Exit;
  end;

  ContentIndent := PreSpaces + (AfterMarker - Tmp);
  if (AfterMarker <= Length(Line)) and
     ((Line[AfterMarker] = ' ') or (Line[AfterMarker] = #9)) then
  begin
    Inc(ContentIndent);
    Inc(AfterMarker);
  end
  else
    Inc(ContentIndent);

  // A new marker only continues the existing list when the topmost open
  // container is that list (we just closed its previous item). When the
  // topmost is a list-item, we're inside it and the marker starts a new
  // sublist child of the item.
  Container := nil;
  if (FOpen.Count > 0) and (FOpen[FOpen.Count - 1].Kind = obList) then
    Container := FOpen[FOpen.Count - 1];

  if (Container <> nil) and
     (Container.Node.ListOrdered = IsOrdered) and
     (Container.ListChar = ListChar) then
  begin
    ListIdx := FOpen.IndexOf(Container);
    CloseBlocksFrom(ListIdx + 1);
    // A blank line preceding this new item means the items are
    // separated by blanks, which makes the list loose.
    ConfirmListLoose;
  end
  else
  begin
    if Container <> nil then
      CloseBlocksFrom(FOpen.IndexOf(Container));
    // A new sublist inside an item that's part of a list with a pending
    // blank counts as the "two blocks separated by blank" loose case.
    ConfirmListLoose;
    ListNode := TPixieMdNode.Create(mnList);
    ListNode.ListOrdered := IsOrdered;
    ListNode.ListStart := OrderedStart;
    ListNode.ListTight := True;
    ListOB := TOpenBlock.Create;
    ListOB.Node := ListNode;
    ListOB.Kind := obList;
    ListOB.ListChar := ListChar;
    AddToContainer(ListNode);
    FOpen.Add(ListOB);
  end;

  ItemNode := TPixieMdNode.Create(mnListItem);
  ItemOB := TOpenBlock.Create;
  ItemOB.Node := ItemNode;
  ItemOB.Kind := obListItem;
  ItemOB.ListContentIndent := ContentIndent;
  CurrentContainer.Node.AddChild(ItemNode);
  FOpen.Add(ItemOB);

  Offset := AfterMarker;

  if (moGfmTaskLists in FOptions) and (Offset <= Length(Line)) then
  begin
    TaskAfter := ProbeTaskMarker(Line, Offset, TaskChecked);
    if TaskAfter > 0 then
    begin
      ItemNode.IsTaskItem := True;
      ItemNode.TaskChecked := TaskChecked;
      Offset := TaskAfter;
    end;
  end;

  Result := True;
end;

function TPixieMdParserImpl.TryStartTable(const Line: string;
  Offset: Integer): Boolean;
var
  Paragraph: TOpenBlock;
  TmpOff, Indent, ColCount: Integer;
  Aligns: TArray<TPixieMdCellAlign>;
  HeaderLine: string;
  NL: Integer;
  HeaderCells: TArray<string>;
  Parent, TableNode, Row, Cell, TextChild: TPixieMdNode;
  ParaIdx, ChildIdx, I: Integer;
  TableOB: TOpenBlock;
begin
  Result := False;
  if not (moGfmTables in FOptions) then Exit;
  Paragraph := DeepestLeaf;
  if (Paragraph = nil) or (Paragraph.Kind <> obParagraph) then Exit;
  if not LineHasUnescapedPipe(Paragraph.Text) then Exit;

  TmpOff := Offset;
  SkipIndent(Line, TmpOff, 3, Indent);
  ColCount := ProbeTableDelimiter(Line, TmpOff, Aligns);
  if ColCount = 0 then Exit;

  // Header is the last line of the paragraph (typically the only line).
  NL := Length(Paragraph.Text);
  while (NL > 0) and (Paragraph.Text[NL] <> #10) do Dec(NL);
  if NL > 0 then
    HeaderLine := Copy(Paragraph.Text, NL + 1, Length(Paragraph.Text))
  else
    HeaderLine := Paragraph.Text;
  SplitTableRow(HeaderLine, HeaderCells);
  if Length(HeaderCells) <> ColCount then Exit;

  ParaIdx := FOpen.IndexOf(Paragraph);
  if ParaIdx > 0 then
    Parent := FOpen[ParaIdx - 1].Node
  else
    Parent := FDoc;
  if Parent = nil then Parent := FDoc;
  ChildIdx := Parent.Children.IndexOf(Paragraph.Node);
  Parent.Children.Extract(Paragraph.Node);
  Paragraph.Node.Free;
  Paragraph.Free;
  FOpen.Delete(ParaIdx);

  TableNode := TPixieMdNode.Create(mnTable);
  Parent.Children.Insert(ChildIdx, TableNode);

  Row := TPixieMdNode.Create(mnTableRow);
  Row.IsHeaderRow := True;
  TableNode.AddChild(Row);
  for I := 0 to ColCount - 1 do
  begin
    Cell := TPixieMdNode.Create(mnTableCell);
    Cell.CellAlignment := Aligns[I];
    if HeaderCells[I] <> '' then
    begin
      TextChild := TPixieMdNode.Create(mnText);
      TextChild.Literal := HeaderCells[I];
      Cell.AddChild(TextChild);
    end;
    Row.AddChild(Cell);
  end;

  TableOB := TOpenBlock.Create;
  TableOB.Node := TableNode;
  TableOB.Kind := obTable;
  TableOB.TableAligns := Aligns;
  FOpen.Add(TableOB);
  Result := True;
end;

procedure TPixieMdParserImpl.AppendTableRow(TableOB: TOpenBlock;
  const RowLine: string);
var
  Cells: TArray<string>;
  Row, Cell, TextChild: TPixieMdNode;
  I, ColCount: Integer;
begin
  ColCount := Length(TableOB.TableAligns);
  SplitTableRow(RowLine, Cells);
  Row := TPixieMdNode.Create(mnTableRow);
  TableOB.Node.AddChild(Row);
  for I := 0 to ColCount - 1 do
  begin
    Cell := TPixieMdNode.Create(mnTableCell);
    Cell.CellAlignment := TableOB.TableAligns[I];
    if (I < Length(Cells)) and (Cells[I] <> '') then
    begin
      TextChild := TPixieMdNode.Create(mnText);
      TextChild.Literal := Cells[I];
      Cell.AddChild(TextChild);
    end;
    Row.AddChild(Cell);
  end;
end;

procedure TPixieMdParserImpl.ProcessLine(const Line: string;
  MatchContainers: Boolean);
var
  Offset, FailedAt, Indent, Level: Integer;
  ContentStart, ContentEnd: Integer;
  Heading, CodeNode, HtmlNode, Hr, Bq, NewHeading, Parent,
    TextChild: TPixieMdNode;
  HeadingOB, CodeOB, HtmlOB, BqOB, Leaf, OB: TOpenBlock;
  TmpOff, TmpOffset, FenceLen, InfoStart, InfoEnd: Integer;
  FenceChar: Char;
  HtmlType, BqStart, ChildIdx, SI, ListIdx, ParaIdx, SpacePos: Integer;
  IsBlank: Boolean;
  TextRem: string;
begin
  Offset := 1;
  if MatchContainers then
    FailedAt := MatchOpenContainers(Line, Offset)
  else
    FailedAt := FOpen.Count;
  IsBlank := IsBlankLine(Copy(Line, Offset, Length(Line)));
  Leaf := DeepestLeaf;

  // Fenced code block: check for closing fence first.
  if (Leaf <> nil) and (Leaf.Kind = obFencedCode) then
  begin
    TmpOffset := Offset;
    SkipIndent(Line, TmpOffset, Leaf.FenceIndent, Indent);
    if (Indent <= 3) and IsClosingFence(Line, TmpOffset,
      Leaf.FenceChar, Leaf.FenceLen) then
    begin
      CloseBlocksFrom(FOpen.IndexOf(Leaf));
      Exit;
    end;
    SkipIndent(Line, Offset, Leaf.FenceIndent, Indent);
    Leaf.Text := Leaf.Text + Copy(Line, Offset, Length(Line)) + #10;
    Exit;
  end;

  // HTML block: append until end condition.
  if (Leaf <> nil) and (Leaf.Kind = obHtmlBlock) then
  begin
    Leaf.Text := Leaf.Text + Line + #10;
    if IsHtmlBlockEnd(Line, Leaf.HtmlStartType) then
      CloseBlocksFrom(FOpen.IndexOf(Leaf));
    Exit;
  end;

  // Open table: each non-blank line is another row; blank line ends.
  if (Leaf <> nil) and (Leaf.Kind = obTable) then
  begin
    if IsBlank or not LineHasUnescapedPipe(Copy(Line, Offset,
      Length(Line))) then
    begin
      CloseBlocksFrom(FOpen.IndexOf(Leaf));
      // Re-process this line in case it starts a new block.
      if not IsBlank then
        ProcessLine(Line, False);
      Exit;
    end;
    AppendTableRow(Leaf, Copy(Line, Offset, Length(Line)));
    Exit;
  end;

  // Lazy paragraph continuation across container boundaries — only when
  // the line doesn't itself start a new block.
  if FailedAt < FOpen.Count then
  begin
    if (not IsBlank) and (Leaf <> nil) and (Leaf.Kind = obParagraph) and
       not LineWouldStartBlock(Line, Offset) then
    begin
      Leaf.Text := Leaf.Text + #10 +
        TrimSpaces(Copy(Line, Offset, Length(Line)));
      Exit;
    end;
    CloseBlocksFrom(FailedAt);
    Leaf := DeepestLeaf;
  end;

  if IsBlank then
  begin
    if Leaf <> nil then
    begin
      if Leaf.Kind = obParagraph then
        CloseBlocksFrom(FOpen.IndexOf(Leaf))
      else if Leaf.Kind = obIndentedCode then
        Leaf.Text := Leaf.Text + #10;
    end;
    // Defer the loose decision: only loose if this list gets another
    // item or sub-block after the blank. If the list closes without
    // one, the blank stays inside the already-closed last item.
    ListIdx := InnermostOpenList;
    if (ListIdx >= 0) and (FOpen[ListIdx].Node.ChildCount > 0) then
      FOpen[ListIdx].HadBlank := True;
    Exit;
  end;

  // 1. Indented code (no paragraph open).
  TmpOff := Offset;
  SkipIndent(Line, TmpOff, 4, Indent);
  if (Indent >= 4) and ((Leaf = nil) or (Leaf.Kind <> obParagraph)) then
  begin
    if (Leaf <> nil) and (Leaf.Kind = obIndentedCode) then
    begin
      Leaf.Text := Leaf.Text + Copy(Line, TmpOff, Length(Line)) + #10;
      Exit;
    end;
    if Leaf <> nil then CloseBlocksFrom(FOpen.IndexOf(Leaf));
    CodeNode := TPixieMdNode.Create(mnCodeBlock);
    CodeOB := TOpenBlock.Create;
    CodeOB.Node := CodeNode;
    CodeOB.Kind := obIndentedCode;
    CodeOB.Text := Copy(Line, TmpOff, Length(Line)) + #10;
    AddLeaf(CodeOB);
    Exit;
  end;

  // 2. ATX heading.
  TmpOff := Offset;
  SkipIndent(Line, TmpOff, 3, Indent);
  Level := ProbeAtxHeading(Line, TmpOff, ContentStart, ContentEnd);
  if Level > 0 then
  begin
    if Leaf <> nil then CloseBlocksFrom(FOpen.IndexOf(Leaf));
    Heading := TPixieMdNode.Create(mnHeading);
    Heading.HeadingLevel := Level;
    HeadingOB := TOpenBlock.Create;
    HeadingOB.Node := Heading;
    HeadingOB.Kind := obHeading;
    if ContentStart <= ContentEnd then
      HeadingOB.Text := Copy(Line, ContentStart, ContentEnd - ContentStart + 1)
    else
      HeadingOB.Text := '';
    AddLeaf(HeadingOB);
    CloseBlocksFrom(FOpen.IndexOf(HeadingOB));
    Exit;
  end;

  // 3. Fenced code block.
  TmpOff := Offset;
  SkipIndent(Line, TmpOff, 3, Indent);
  FenceChar := ProbeFence(Line, TmpOff, FenceLen, InfoStart, InfoEnd);
  if FenceChar <> #0 then
  begin
    if Leaf <> nil then CloseBlocksFrom(FOpen.IndexOf(Leaf));
    CodeNode := TPixieMdNode.Create(mnCodeBlock);
    CodeNode.CodeLang := TrimSpaces(Copy(Line, InfoStart,
      InfoEnd - InfoStart + 1));
    SpacePos := Pos(' ', CodeNode.CodeLang);
    if SpacePos > 0 then
      CodeNode.CodeLang := Copy(CodeNode.CodeLang, 1, SpacePos - 1);
    CodeOB := TOpenBlock.Create;
    CodeOB.Node := CodeNode;
    CodeOB.Kind := obFencedCode;
    CodeOB.FenceChar := FenceChar;
    CodeOB.FenceLen := FenceLen;
    CodeOB.FenceIndent := Indent;
    CodeOB.Text := '';
    AddLeaf(CodeOB);
    Exit;
  end;

  // 4a. GFM table — paragraph above + delimiter row converts the
  // paragraph into a <table>. Must come BEFORE setext/thematic so a
  // pipe-bearing setext-like line is recognised as a table delim.
  if TryStartTable(Line, Offset) then
    Exit;

  // 4b. Setext heading underline (when paragraph is open). Must come
  // BEFORE thematic break because '---' matches both, and setext wins
  // when a paragraph is open above it.
  if (Leaf <> nil) and (Leaf.Kind = obParagraph) then
  begin
    TmpOff := Offset;
    SkipIndent(Line, TmpOff, 3, Indent);
    Level := ProbeSetextUnderline(Line, TmpOff);
    if Level > 0 then
    begin
      ParaIdx := FOpen.IndexOf(Leaf);
      if ParaIdx > 0 then
        Parent := FOpen[ParaIdx - 1].Node
      else
        Parent := FDoc;
      if Parent = nil then Parent := FDoc;
      NewHeading := TPixieMdNode.Create(mnHeading);
      NewHeading.HeadingLevel := Level;
      TextChild := TPixieMdNode.Create(mnText);
      TextChild.Literal := TrimSpaces(Leaf.Text);
      NewHeading.AddChild(TextChild);
      ChildIdx := Parent.Children.IndexOf(Leaf.Node);
      Parent.Children.Extract(Leaf.Node);
      Leaf.Node.Free;
      Leaf.Node := nil;
      Parent.Children.Insert(ChildIdx, NewHeading);
      Leaf.Free;
      FOpen.Delete(ParaIdx);
      Exit;
    end;
  end;

  // 5. Thematic break.
  TmpOff := Offset;
  SkipIndent(Line, TmpOff, 3, Indent);
  if ProbeThematicBreak(Line, TmpOff) then
  begin
    if Leaf <> nil then CloseBlocksFrom(FOpen.IndexOf(Leaf));
    Hr := TPixieMdNode.Create(mnThematicBreak);
    AddToContainer(Hr);
    Exit;
  end;

  // 6. Blockquote.
  TmpOff := Offset;
  SkipIndent(Line, TmpOff, 3, Indent);
  BqStart := ProbeBlockQuote(Line, TmpOff);
  if BqStart > 0 then
  begin
    if Leaf <> nil then CloseBlocksFrom(FOpen.IndexOf(Leaf));
    Bq := TPixieMdNode.Create(mnBlockQuote);
    BqOB := TOpenBlock.Create;
    BqOB.Node := Bq;
    BqOB.Kind := obBlockQuote;
    AddToContainer(Bq);
    FOpen.Add(BqOB);
    Offset := BqStart;
    ProcessLine(Copy(Line, Offset, Length(Line)), False);
    Exit;
  end;

  // 7. List item.
  if TryStartListItem(Line, Offset) then
  begin
    TextRem := Copy(Line, Offset, Length(Line));
    if not IsBlankLine(TextRem) then
      ProcessLine(TextRem, False);
    Exit;
  end;

  // 8. HTML block.
  TmpOff := Offset;
  SkipIndent(Line, TmpOff, 3, Indent);
  HtmlType := ProbeHtmlBlockStart(Line, TmpOff);
  if (HtmlType > 0) and (moAllowRawHtml in FOptions) then
  begin
    if Leaf <> nil then CloseBlocksFrom(FOpen.IndexOf(Leaf));
    HtmlNode := TPixieMdNode.Create(mnHtmlBlock);
    HtmlOB := TOpenBlock.Create;
    HtmlOB.Node := HtmlNode;
    HtmlOB.Kind := obHtmlBlock;
    HtmlOB.HtmlStartType := HtmlType;
    HtmlOB.Text := Line + #10;
    AddLeaf(HtmlOB);
    if IsHtmlBlockEnd(Line, HtmlType) then
      CloseBlocksFrom(FOpen.IndexOf(HtmlOB));
    Exit;
  end;

  // 9. Paragraph (default). Preserve trailing whitespace — the inline
  // parser uses two trailing spaces to detect hard breaks.
  TextRem := Copy(Line, Offset, Length(Line));
  SI := 1;
  while (SI <= Length(TextRem)) and (TextRem[SI] = ' ') and (SI <= 3) do
    Inc(SI);
  Delete(TextRem, 1, SI - 1);
  AppendToParagraph(TextRem);
end;

function TPixieMdParserImpl.Parse: TPixieMdNode;
var
  I: Integer;
  RootOB: TOpenBlock;
begin
  PixieMdSplitLines(FSource, FLines);

  if moStripFrontMatter in FOptions then
    StripFrontMatter;

  FDoc := TPixieMdNode.Create(mnDocument);

  RootOB := TOpenBlock.Create;
  RootOB.Node := nil;
  RootOB.Kind := obDocument;
  FOpen.Add(RootOB);

  for I := 0 to High(FLines) do
    ProcessLine(FLines[I], True);

  CloseBlocksFrom(1);

  Result := FDoc;
end;

class function TPixieMdParser.ParseBlocks(const Md: string;
  RefDefs: TPixieMdLinkRefMap;
  Options: TPixieMdOptions): TPixieMdNode;
var
  Impl: TPixieMdParserImpl;
begin
  Impl := TPixieMdParserImpl.Create(Md, Options, RefDefs);
  try
    Result := Impl.Parse;
  finally
    Impl.Free;
  end;
end;

end.
