unit Pixie.SimpleXml;

// Minimal XML DOM parser providing the same API surface as FPC's fcl-xml
// (DOM, XMLRead units). Supports the subset needed by Pixie.SvgToPdf:
// element/text nodes, attributes, child iteration, and basic entities.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes;

type
  TPixieXmlNodeType = (xntElement, xntText);

  TDOMNode = class;
  TDOMElement = class;
  TDOMNamedNodeMap = class;

  { TDOMNode }

  TDOMNode = class
  private
    FNodeType: TPixieXmlNodeType;
    FNodeValue: UnicodeString;
    FFirstChild: TDOMNode;
    FLastChild: TDOMNode;
    FNextSibling: TDOMNode;
  public
    destructor Destroy; override;
    procedure AppendChild(Child: TDOMNode);
    property NodeType: TPixieXmlNodeType read FNodeType;
    property NodeValue: UnicodeString read FNodeValue write FNodeValue;
    property FirstChild: TDOMNode read FFirstChild;
    property NextSibling: TDOMNode read FNextSibling;
  end;

  { TDOMElement }

  TDOMElement = class(TDOMNode)
  private
    FTagName: UnicodeString;
    FAttrNames: TStringList;
    FAttrValues: TStringList;
    FAttrNode: TDOMNode;
    FAttributes: TDOMNamedNodeMap;
  public
    constructor Create;
    destructor Destroy; override;
    function GetAttribute(const Name: UnicodeString): UnicodeString;
    function GetAttributeStr(const Name: string): string;
    function HasAttribute(const Name: string): Boolean;
    property TagName: UnicodeString read FTagName;
    property Attributes: TDOMNamedNodeMap read FAttributes;
  end;

  { TDOMNamedNodeMap }

  TDOMNamedNodeMap = class
  private
    FOwner: TDOMElement;
  public
    constructor Create(AOwner: TDOMElement);
    function GetNamedItem(const Name: UnicodeString): TDOMNode;
  end;

  { TXMLDocument }

  TXMLDocument = class(TDOMNode)
  private
    FDocumentElement: TDOMElement;
  public
    destructor Destroy; override;
    property DocumentElement: TDOMElement read FDocumentElement;
  end;

procedure PixieReadXMLFile(out Doc: TXMLDocument; Stream: TStream);

function PixieDomToStr(const S: UnicodeString): string; inline;
function PixieStrToDom(const S: string): UnicodeString; inline;

implementation

{$IFDEF FPC}
function PixieDomToStr(const S: UnicodeString): string; inline;
begin Result := UTF8Encode(S); end;
function PixieStrToDom(const S: string): UnicodeString; inline;
begin Result := UTF8Decode(S); end;
{$ELSE}
function PixieDomToStr(const S: UnicodeString): string; inline;
begin Result := S; end;
function PixieStrToDom(const S: string): UnicodeString; inline;
begin Result := S; end;
{$ENDIF}

// ---------------------------------------------------------------------------
// TDOMNode
// ---------------------------------------------------------------------------

destructor TDOMNode.Destroy;
var
  Child, Next: TDOMNode;
begin
  Child := FFirstChild;
  while Child <> nil do
  begin
    Next := Child.FNextSibling;
    Child.Free;
    Child := Next;
  end;
  inherited;
end;

procedure TDOMNode.AppendChild(Child: TDOMNode);
begin
  if FLastChild = nil then
    FFirstChild := Child
  else
    FLastChild.FNextSibling := Child;
  FLastChild := Child;
end;

// ---------------------------------------------------------------------------
// TDOMElement
// ---------------------------------------------------------------------------

constructor TDOMElement.Create;
begin
  inherited Create;
  FNodeType := xntElement;
  FAttrNames := TStringList.Create;
  FAttrValues := TStringList.Create;
  FAttrNode := TDOMNode.Create;
  FAttributes := TDOMNamedNodeMap.Create(Self);
end;

destructor TDOMElement.Destroy;
begin
  FAttributes.Free;
  FAttrNode.Free;
  FAttrValues.Free;
  FAttrNames.Free;
  inherited;
end;

function TDOMElement.GetAttribute(const Name: UnicodeString): UnicodeString;
var
  I: Integer;
  N: string;
begin
  N := string(Name);
  for I := 0 to FAttrNames.Count - 1 do
    if FAttrNames[I] = N then
    begin
      Result := UnicodeString(FAttrValues[I]);
      Exit;
    end;
  Result := '';
end;

function TDOMElement.GetAttributeStr(const Name: string): string;
var
  I: Integer;
begin
  for I := 0 to FAttrNames.Count - 1 do
    if FAttrNames[I] = Name then
    begin
      Result := FAttrValues[I];
      Exit;
    end;
  Result := '';
end;

function TDOMElement.HasAttribute(const Name: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to FAttrNames.Count - 1 do
    if FAttrNames[I] = Name then
      Exit(True);
  Result := False;
end;

// ---------------------------------------------------------------------------
// TDOMNamedNodeMap
// ---------------------------------------------------------------------------

constructor TDOMNamedNodeMap.Create(AOwner: TDOMElement);
begin
  inherited Create;
  FOwner := AOwner;
end;

function TDOMNamedNodeMap.GetNamedItem(const Name: UnicodeString): TDOMNode;
var
  I: Integer;
  N: string;
begin
  N := string(Name);
  for I := 0 to FOwner.FAttrNames.Count - 1 do
    if FOwner.FAttrNames[I] = N then
    begin
      FOwner.FAttrNode.FNodeValue := UnicodeString(FOwner.FAttrValues[I]);
      Result := FOwner.FAttrNode;
      Exit;
    end;
  Result := nil;
end;

// ---------------------------------------------------------------------------
// TXMLDocument
// ---------------------------------------------------------------------------

destructor TXMLDocument.Destroy;
begin
  FDocumentElement.Free;
  inherited;
end;

// ---------------------------------------------------------------------------
// XML Parser
// ---------------------------------------------------------------------------

type
  TXmlParser = record
    Data: string;
    Pos: Integer;
    Len: Integer;
  end;

function AtEnd(var P: TXmlParser): Boolean; inline;
begin
  Result := P.Pos > P.Len;
end;

function Peek(var P: TXmlParser): Char; inline;
begin
  if P.Pos <= P.Len then
    Result := P.Data[P.Pos]
  else
    Result := #0;
end;

procedure Skip(var P: TXmlParser; Count: Integer = 1); inline;
begin
  Inc(P.Pos, Count);
end;

function Matches(var P: TXmlParser; const S: string): Boolean;
var
  I, SLen: Integer;
begin
  SLen := Length(S);
  if P.Pos + SLen - 1 > P.Len then Exit(False);
  for I := 1 to SLen do
    if P.Data[P.Pos + I - 1] <> S[I] then Exit(False);
  Result := True;
end;

procedure SkipWhitespace(var P: TXmlParser);
begin
  while (P.Pos <= P.Len) and (P.Data[P.Pos] <= ' ') do
    Inc(P.Pos);
end;

function DecodeEntity(const Data: string; EntStart, EntLen: Integer): UnicodeString;
var
  Code, I: Integer;
  C: Char;
begin
  // Named entities — compare directly from buffer, no allocation
  case EntLen of
    2: begin
         if (Data[EntStart] = 'l') and (Data[EntStart + 1] = 't') then
           Exit('<');
         if (Data[EntStart] = 'g') and (Data[EntStart + 1] = 't') then
           Exit('>');
       end;
    3: if (Data[EntStart] = 'a') and (Data[EntStart + 1] = 'm') and
          (Data[EntStart + 2] = 'p') then
         Exit('&');
    4: begin
         if (Data[EntStart] = 'q') and (Data[EntStart + 1] = 'u') and
            (Data[EntStart + 2] = 'o') and (Data[EntStart + 3] = 't') then
           Exit('"');
         if (Data[EntStart] = 'a') and (Data[EntStart + 1] = 'p') and
            (Data[EntStart + 2] = 'o') and (Data[EntStart + 3] = 's') then
           Exit('''');
       end;
  end;

  // Numeric entity: &#NNN; or &#xHHH; — parse inline, no StrToIntDef/Copy
  if (EntLen >= 2) and (Data[EntStart] = '#') then
  begin
    Code := 0;
    if (EntLen >= 3) and ((Data[EntStart + 1] = 'x') or
       (Data[EntStart + 1] = 'X')) then
    begin
      for I := EntStart + 2 to EntStart + EntLen - 1 do
      begin
        C := Data[I];
        case C of
          '0'..'9': Code := Code * 16 + Ord(C) - Ord('0');
          'a'..'f': Code := Code * 16 + Ord(C) - Ord('a') + 10;
          'A'..'F': Code := Code * 16 + Ord(C) - Ord('A') + 10;
        else Code := 0; Break;
        end;
      end;
    end
    else
    begin
      for I := EntStart + 1 to EntStart + EntLen - 1 do
      begin
        C := Data[I];
        if (C >= '0') and (C <= '9') then
          Code := Code * 10 + Ord(C) - Ord('0')
        else begin Code := 0; Break; end;
      end;
    end;
    if Code > 0 then
      Exit(WideChar(Code));
  end;

  // Unknown entity — keep as-is
  Result := '&' + PixieStrToDom(Copy(Data, EntStart, EntLen)) + ';';
end;

function ReadText(var P: TXmlParser; StopChar: Char): UnicodeString;
var
  Start, ScanPos, EntStart, EntLen: Integer;
begin
  // Pass 1: scan ahead to check for entity references
  ScanPos := P.Pos;
  while (ScanPos <= P.Len) and (P.Data[ScanPos] <> StopChar) do
  begin
    if P.Data[ScanPos] = '&' then Break;
    Inc(ScanPos);
  end;

  // Fast path: no entities — single copy, no per-segment concatenation
  if (ScanPos > P.Len) or (P.Data[ScanPos] <> '&') then
  begin
    Start := P.Pos;
    P.Pos := ScanPos;
    Result := PixieStrToDom(Copy(P.Data, Start, ScanPos - Start));
    Exit;
  end;

  // Pass 2: copy clean prefix before first entity, then decode
  Start := P.Pos;
  if ScanPos > Start then
    Result := PixieStrToDom(Copy(P.Data, Start, ScanPos - Start))
  else
    Result := '';
  P.Pos := ScanPos;

  while (P.Pos <= P.Len) and (P.Data[P.Pos] <> StopChar) do
  begin
    if P.Data[P.Pos] = '&' then
    begin
      Inc(P.Pos);
      EntStart := P.Pos;
      while (P.Pos <= P.Len) and (P.Data[P.Pos] <> ';') do
        Inc(P.Pos);
      EntLen := P.Pos - EntStart;
      if P.Pos <= P.Len then Inc(P.Pos); // skip ';'
      Result := Result + DecodeEntity(P.Data, EntStart, EntLen);
    end
    else
    begin
      Start := P.Pos;
      while (P.Pos <= P.Len) and (P.Data[P.Pos] <> StopChar) and
            (P.Data[P.Pos] <> '&') do
        Inc(P.Pos);
      Result := Result + PixieStrToDom(Copy(P.Data, Start, P.Pos - Start));
    end;
  end;
end;

function ReadAttrValue(var P: TXmlParser): UnicodeString;
var
  Quote: Char;
begin
  SkipWhitespace(P);
  if AtEnd(P) then Exit('');
  Quote := P.Data[P.Pos];
  if (Quote <> '"') and (Quote <> '''') then Exit('');
  Inc(P.Pos);
  Result := ReadText(P, Quote);
  if (P.Pos <= P.Len) and (P.Data[P.Pos] = Quote) then
    Inc(P.Pos);
end;

function ReadName(var P: TXmlParser): string;
var
  Start: Integer;
begin
  Start := P.Pos;
  while (P.Pos <= P.Len) and not
    CharInSet(P.Data[P.Pos], [' ', #9, #10, #13, '/', '>', '=']) do
    Inc(P.Pos);
  Result := Copy(P.Data, Start, P.Pos - Start);
end;

procedure SkipComment(var P: TXmlParser);
begin
  // Skip past '-->'
  while P.Pos <= P.Len do
  begin
    if Matches(P, '-->') then
    begin
      Skip(P, 3);
      Exit;
    end;
    Inc(P.Pos);
  end;
end;

procedure SkipPI(var P: TXmlParser);
begin
  // Skip past '?>'
  while P.Pos <= P.Len do
  begin
    if Matches(P, '?>') then
    begin
      Skip(P, 2);
      Exit;
    end;
    Inc(P.Pos);
  end;
end;

procedure SkipDoctype(var P: TXmlParser);
var
  Depth: Integer;
begin
  // Skip past matching '>'
  Depth := 1;
  while (P.Pos <= P.Len) and (Depth > 0) do
  begin
    if P.Data[P.Pos] = '<' then Inc(Depth)
    else if P.Data[P.Pos] = '>' then Dec(Depth);
    Inc(P.Pos);
  end;
end;

function ReadCDATA(var P: TXmlParser): UnicodeString;
var
  Start: Integer;
begin
  Start := P.Pos;
  while P.Pos <= P.Len do
  begin
    if Matches(P, ']]>') then
    begin
      Result := PixieStrToDom(Copy(P.Data, Start, P.Pos - Start));
      Skip(P, 3);
      Exit;
    end;
    Inc(P.Pos);
  end;
  Result := PixieStrToDom(Copy(P.Data, Start, P.Pos - Start));
end;

function ParseElement(var P: TXmlParser): TDOMElement; forward;

procedure ParseChildren(var P: TXmlParser; Parent: TDOMNode;
  const ParentTag: string);
var
  TextVal: UnicodeString;
  TextNode: TDOMNode;
  ChildEl: TDOMElement;
  CloseName: string;
begin
  while not AtEnd(P) do
  begin
    if P.Data[P.Pos] = '<' then
    begin
      // Check for closing tag
      if Matches(P, '</') then
      begin
        Skip(P, 2);
        CloseName := ReadName(P);
        // Skip past '>'
        while (P.Pos <= P.Len) and (P.Data[P.Pos] <> '>') do
          Inc(P.Pos);
        if P.Pos <= P.Len then Inc(P.Pos);
        Exit;
      end;

      // Comment
      if Matches(P, '<!--') then
      begin
        Skip(P, 4);
        SkipComment(P);
        Continue;
      end;

      // CDATA
      if Matches(P, '<![CDATA[') then
      begin
        Skip(P, 9);
        TextVal := ReadCDATA(P);
        if TextVal <> '' then
        begin
          TextNode := TDOMNode.Create;
          TextNode.FNodeType := xntText;
          TextNode.FNodeValue := TextVal;
          Parent.AppendChild(TextNode);
        end;
        Continue;
      end;

      // Processing instruction
      if Matches(P, '<?') then
      begin
        Skip(P, 2);
        SkipPI(P);
        Continue;
      end;

      // DOCTYPE
      if Matches(P, '<!') then
      begin
        Skip(P, 2);
        SkipDoctype(P);
        Continue;
      end;

      // Child element
      ChildEl := ParseElement(P);
      if ChildEl <> nil then
        Parent.AppendChild(ChildEl);
    end
    else
    begin
      // Text content
      TextVal := ReadText(P, '<');
      if Trim(string(TextVal)) <> '' then
      begin
        TextNode := TDOMNode.Create;
        TextNode.FNodeType := xntText;
        TextNode.FNodeValue := TextVal;
        Parent.AppendChild(TextNode);
      end;
    end;
  end;
end;

function ParseElement(var P: TXmlParser): TDOMElement;
var
  El: TDOMElement;
  TagName, AttrName: string;
  AttrValue: UnicodeString;
  SelfClosing: Boolean;
  ColonPos: Integer;
begin
  Result := nil;
  if AtEnd(P) or (P.Data[P.Pos] <> '<') then Exit;
  Inc(P.Pos); // skip '<'

  TagName := ReadName(P);
  if TagName = '' then Exit;

  // Strip namespace prefix (e.g. 'svg:rect' -> 'rect')
  ColonPos := Pos(':', TagName);
  if ColonPos > 0 then
    TagName := Copy(TagName, ColonPos + 1, MaxInt);

  El := TDOMElement.Create;
  El.FTagName := UnicodeString(TagName);

  // Parse attributes
  while not AtEnd(P) do
  begin
    SkipWhitespace(P);
    if AtEnd(P) then Break;
    if (P.Data[P.Pos] = '/') or (P.Data[P.Pos] = '>') then Break;

    AttrName := ReadName(P);
    if AttrName = '' then
    begin
      Inc(P.Pos); // skip unknown char
      Continue;
    end;

    // Strip namespace prefix (e.g. 'xlink:href' -> 'href')
    ColonPos := Pos(':', AttrName);
    if ColonPos > 0 then
      AttrName := Copy(AttrName, ColonPos + 1, MaxInt);

    SkipWhitespace(P);
    if (P.Pos <= P.Len) and (P.Data[P.Pos] = '=') then
    begin
      Inc(P.Pos); // skip '='
      AttrValue := ReadAttrValue(P);
    end
    else
      AttrValue := UnicodeString(AttrName); // boolean attribute

    El.FAttrNames.Add(AttrName);
    El.FAttrValues.Add(string(AttrValue));
  end;

  // Self-closing?
  SelfClosing := False;
  if (P.Pos <= P.Len) and (P.Data[P.Pos] = '/') then
  begin
    Inc(P.Pos);
    SelfClosing := True;
  end;
  if (P.Pos <= P.Len) and (P.Data[P.Pos] = '>') then
    Inc(P.Pos);

  if not SelfClosing then
    ParseChildren(P, El, TagName);

  Result := El;
end;

// ---------------------------------------------------------------------------
// PixieReadXMLFile
// ---------------------------------------------------------------------------

procedure PixieReadXMLFile(out Doc: TXMLDocument; Stream: TStream);
var
  Bytes: TBytes;
  Text: string;
  P: TXmlParser;
  El: TDOMElement;
begin
  Doc := nil;
  if (Stream = nil) or (Stream.Size = 0) then Exit;

  SetLength(Bytes, Stream.Size - Stream.Position);
  Stream.Read(Bytes[0], Length(Bytes));

  // Detect and skip UTF-8 BOM
  {$IFDEF FPC}
  // FPC string = UTF-8 AnsiString — use raw bytes directly
  if (Length(Bytes) >= 3) and
     (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    SetString(Text, PAnsiChar(@Bytes[3]), Length(Bytes) - 3)
  else
    SetString(Text, PAnsiChar(@Bytes[0]), Length(Bytes));
  {$ELSE}
  if (Length(Bytes) >= 3) and
     (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    Text := TEncoding.UTF8.GetString(Bytes, 3, Length(Bytes) - 3)
  else
    Text := TEncoding.UTF8.GetString(Bytes);
  {$ENDIF}

  P.Data := Text;
  P.Pos := 1;
  P.Len := Length(Text);

  // Skip prolog (<?xml?>, comments, whitespace, DOCTYPE)
  while not AtEnd(P) do
  begin
    SkipWhitespace(P);
    if AtEnd(P) then Break;

    if Matches(P, '<?') then
    begin
      Skip(P, 2);
      SkipPI(P);
    end
    else if Matches(P, '<!--') then
    begin
      Skip(P, 4);
      SkipComment(P);
    end
    else if Matches(P, '<!') then
    begin
      Skip(P, 2);
      SkipDoctype(P);
    end
    else
      Break;
  end;

  // Parse root element
  if AtEnd(P) then Exit;
  El := ParseElement(P);
  if El = nil then Exit;

  Doc := TXMLDocument.Create;
  Doc.FDocumentElement := El;
end;

end.
