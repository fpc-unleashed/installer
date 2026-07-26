unit Pixie.HtmlParser;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Generics.Collections;

type
  TPixieHtmlNodeType = (
    hntDocument, hntElement, hntText, hntWhitespace,
    hntComment, hntCData
  );

  TPixieHtmlQuirksMode = (hqNoQuirks, hqQuirks, hqLimitedQuirks);

  TPixieHtmlNamespace = (hnsHtml, hnsSvg, hnsMathMl);

  TPixieHtmlAttribute = record
    Name: string;
    Value: string;
  end;

  TPixieHtmlNode = class;
  TPixieHtmlAttributeList = TList<TPixieHtmlAttribute>;
  TPixieHtmlNodeList = TList<TPixieHtmlNode>;

  TPixieHtmlNode = class
  public
    NodeType: TPixieHtmlNodeType;
    Tag: string;
    Text: string;
    Namespace: TPixieHtmlNamespace;
    Attributes: TPixieHtmlAttributeList;
    Children: TPixieHtmlNodeList;
    Parent: TPixieHtmlNode;
    QuirksMode: TPixieHtmlQuirksMode;
    constructor Create(AType: TPixieHtmlNodeType);
    destructor Destroy; override;
    function AppendChild(Child: TPixieHtmlNode): TPixieHtmlNode;
    procedure AdoptAllChildrenFrom(Source: TPixieHtmlNode);
    function GetAttribute(const AName: string): string;
    function HasAttribute(const AName: string): Boolean;
    procedure SetAttribute(const AName, AValue: string);
    function CloneShallow: TPixieHtmlNode;
    procedure RemoveChild(Child: TPixieHtmlNode);
    procedure InsertChildBefore(Child, Before: TPixieHtmlNode);
  end;

function PixieParseHtml(const Html: string): TPixieHtmlNode;
function PixieParseFragment(const Html, ContextTag: string): TPixieHtmlNode;
implementation

uses
  Pixie.Utf8, Pixie.HtmlEntities;

const
  EOF_CHAR = -1;
  NULL_CHAR = 0;
  REPLACEMENT_CHAR = $FFFD;

type
  // Token types emitted by the tokenizer
  TPixieTokenType = (
    ttDoctype, ttStartTag, ttEndTag, ttComment,
    ttCharacter, ttEof
  );

  // A single token from the tokenizer
  TPixieToken = record
    TokenType: TPixieTokenType;
    Name: string;
    PublicId: string;
    SystemId: string;
    ForceQuirks: Boolean;
    SelfClosing: Boolean;
    Attrs: TPixieHtmlAttributeList;
    Data: string;
    DataChar: Integer;  // for character tokens
  end;

  // Tokenizer states (matching HTML5 spec)
  TPixieLexState = (
    lsData,
    lsRcdata,
    lsRawtext,
    lsScript,
    lsPlaintext,
    lsTagOpen,
    lsEndTagOpen,
    lsTagName,
    lsRcdataLt,
    lsRcdataEndTagOpen,
    lsRcdataEndTagName,
    lsRawtextLt,
    lsRawtextEndTagOpen,
    lsRawtextEndTagName,
    lsScriptLt,
    lsScriptEndTagOpen,
    lsScriptEndTagName,
    lsScriptEscapedStart,
    lsScriptEscapedStartDash,
    lsScriptEscaped,
    lsScriptEscapedDash,
    lsScriptEscapedDashDash,
    lsScriptEscapedLt,
    lsScriptEscapedEndTagOpen,
    lsScriptEscapedEndTagName,
    lsScriptDoubleEscapedStart,
    lsScriptDoubleEscaped,
    lsScriptDoubleEscapedDash,
    lsScriptDoubleEscapedDashDash,
    lsScriptDoubleEscapedLt,
    lsScriptDoubleEscapedEnd,
    lsBeforeAttrName,
    lsAttrName,
    lsAfterAttrName,
    lsBeforeAttrValue,
    lsAttrValueDoubleQuoted,
    lsAttrValueSingleQuoted,
    lsAttrValueUnquoted,
    lsAfterAttrValueQuoted,
    lsSelfClosingStartTag,
    lsBogusComment,
    lsMarkupDeclaration,
    lsCommentStart,
    lsCommentStartDash,
    lsComment,
    lsCommentEndDash,
    lsCommentEnd,
    lsCommentEndBang,
    lsDoctype,
    lsBeforeDoctypeName,
    lsDoctypeName,
    lsAfterDoctypeName,
    lsAfterDoctypePublicKeyword,
    lsBeforeDoctypePublicId,
    lsDoctypePublicIdDoubleQuoted,
    lsDoctypePublicIdSingleQuoted,
    lsAfterDoctypePublicId,
    lsBetweenDoctypePublicSystemId,
    lsAfterDoctypeSystemKeyword,
    lsBeforeDoctypeSystemId,
    lsDoctypeSystemIdDoubleQuoted,
    lsDoctypeSystemIdSingleQuoted,
    lsAfterDoctypeSystemId,
    lsBogusDoctype,
    lsCdata
  );

  // Insertion modes for the tree builder
  TPixieInsertionMode = (
    imInitial,
    imBeforeHtml,
    imBeforeHead,
    imInHead,
    imInHeadNoscript,
    imAfterHead,
    imInBody,
    imText,
    imInTable,
    imInTableText,
    imInCaption,
    imInColumnGroup,
    imInTableBody,
    imInRow,
    imInCell,
    imInSelect,
    imInSelectInTable,
    imInTemplate,
    imAfterBody,
    imInFrameset,
    imAfterFrameset,
    imAfterAfterBody,
    imAfterAfterFrameset
  );

  // Forward declarations
  TPixieTokenizer = class;
  TPixieTreeBuilder = class;

  // =========================================================================
  // Tokenizer
  // =========================================================================
  TPixieTokenizer = class
  private
    FInput: string;
    FPos: Integer;
    FState: TPixieLexState;
    FReturnState: TPixieLexState;
    FReconsume: Boolean;
    FCurrentChar: Integer;
    FTagName: string;
    FTagIsStart: Boolean;
    FTagSelfClosing: Boolean;
    FTagAttrs: TPixieHtmlAttributeList;
    FAttrName: string;
    FAttrValue: string;
    FComment: string;
    FDoctypeName: string;
    FDoctypePublicId: string;
    FDoctypeSystemId: string;
    FDoctypeForceQuirks: Boolean;
    FDoctypeHasPublicId: Boolean;
    FDoctypeHasSystemId: Boolean;
    FTempBuffer: string;
    FLastStartTag: string;
    FIsForeignContext: Boolean;
    procedure Advance;
    function Peek: Integer;
    function MatchAhead(const S: string; CaseInsensitive: Boolean): Boolean;
    procedure ConsumeAhead(Len: Integer);
    procedure StartNewTag(IsStart: Boolean);
    procedure FinishAttrName;
    procedure FinishAttr;
    function IsAppropriateEndTag: Boolean;
    procedure ConsumeCharRef(AdditionalAllowed: Integer; InAttr: Boolean;
      out Cp1, Cp2: Integer);
    function EmitChar(C: Integer; out Token: TPixieToken): Boolean;
    function EmitTag(out Token: TPixieToken): Boolean;
    function EmitComment(out Token: TPixieToken): Boolean;
    function EmitDoctype(out Token: TPixieToken): Boolean;
    function EmitEof(out Token: TPixieToken): Boolean;
  public
    constructor Create(const AInput: string);
    destructor Destroy; override;
    function NextToken(out Token: TPixieToken): Boolean;
    procedure SetState(AState: TPixieLexState);
    procedure SetForeignContext(Value: Boolean);
  end;

  // =========================================================================
  // Tree Builder
  // =========================================================================
  TPixieInsertionModeStack = TList<TPixieInsertionMode>;

  TPixieTreeBuilder = class
  private
    FTokenizer: TPixieTokenizer;
    FDocument: TPixieHtmlNode;
    FMode: TPixieInsertionMode;
    FOriginalMode: TPixieInsertionMode;
    FOpenElements: TPixieHtmlNodeList;
    FActiveFormatting: TPixieHtmlNodeList;
    FTemplateInsertionModes: TPixieInsertionModeStack;
    FHeadElement: TPixieHtmlNode;
    FFormElement: TPixieHtmlNode;
    FFragmentContext: TPixieHtmlNode;
    FReprocess: Boolean;
    FFramesetOk: Boolean;
    FIgnoreNextLf: Boolean;
    FFosterParenting: Boolean;
    FPendingTableChars: string;
    FPendingTableCharsHasNonWs: Boolean;
    FTextBuffer: TStringBuilder;
    FTextBufferType: TPixieHtmlNodeType;
    // Stack operations
    function CurrentNode: TPixieHtmlNode;
    function AdjustedCurrentNode: TPixieHtmlNode;
    procedure PopCurrentNode;
    procedure PopUntil(const Tag: string);
    procedure PopUntilOneOf(const Tags: array of string);
    // Active formatting
    procedure AddFormattingElement(Node: TPixieHtmlNode);
    procedure AddFormattingMarker;
    procedure ReconstructActiveFormatting;
    procedure ClearFormattingToLastMarker;
    function IsFormattingMarker(Node: TPixieHtmlNode): Boolean;
    function NodeInActiveFormatting(Node: TPixieHtmlNode): Integer;
    // Scope checking
    function HasElementInScope(const Tag: string): Boolean;
    function HasElementInButtonScope(const Tag: string): Boolean;
    function HasElementInListScope(const Tag: string): Boolean;
    function HasElementInTableScope(const Tag: string): Boolean;
    function HasElementInSelectScope(const Tag: string): Boolean;
    function HasElementInSpecificScope(const Tag: string;
      const ScopeTags: array of string): Boolean;
    // Implied end tags
    procedure GenerateImpliedEndTags(const Except_: string = '');
    procedure GenerateAllImpliedEndTags;
    // Node creation and insertion
    function CreateElement(const Tag: string; Ns: TPixieHtmlNamespace): TPixieHtmlNode;
    function CreateElementFromToken(var Token: TPixieToken; Ns: TPixieHtmlNamespace): TPixieHtmlNode;
    function InsertElement(var Token: TPixieToken; Ns: TPixieHtmlNamespace = hnsHtml): TPixieHtmlNode;
    function InsertElementNamed(const Tag: string; Ns: TPixieHtmlNamespace = hnsHtml): TPixieHtmlNode;
    procedure InsertCharacter(C: Integer);
    procedure InsertText(const S: string);
    procedure FlushTextBuffer;
    procedure InsertComment(const Data: string);
    function GetFosterParent(out InsertBefore: TPixieHtmlNode): TPixieHtmlNode;
    // Tag classification
    function IsSpecialTag(const Tag: string): Boolean;
    function IsFormattingTag(const Tag: string): Boolean;
    function IsHeadingTag(const Tag: string): Boolean;
    // Adoption agency
    procedure AdoptionAgency(const Tag: string);
    // Close tags
    procedure ClosePElement;
    procedure CloseCell;
    // Quirks mode
    function ComputeQuirksMode(const Name, PubId, SysId: string;
      ForceQuirks, HasSysId: Boolean): TPixieHtmlQuirksMode;
    // Foreign content
    function IsMathMlIntegrationPoint(Node: TPixieHtmlNode): Boolean;
    function IsSvgIntegrationPoint(Node: TPixieHtmlNode): Boolean;
    procedure AdjustSvgAttributes(Attrs: TPixieHtmlAttributeList);
    procedure AdjustMathMlAttributes(Attrs: TPixieHtmlAttributeList);
    procedure AdjustForeignAttributes(Attrs: TPixieHtmlAttributeList);
    // Token dispatch
    procedure ProcessToken(var Token: TPixieToken);
    procedure ProcessInForeignContent(var Token: TPixieToken);
    // Insertion mode handlers
    procedure HandleInitial(var Token: TPixieToken);
    procedure HandleBeforeHtml(var Token: TPixieToken);
    procedure HandleBeforeHead(var Token: TPixieToken);
    procedure HandleInHead(var Token: TPixieToken);
    procedure HandleInHeadNoscript(var Token: TPixieToken);
    procedure HandleAfterHead(var Token: TPixieToken);
    procedure HandleInBody(var Token: TPixieToken);
    procedure HandleText(var Token: TPixieToken);
    procedure HandleInTable(var Token: TPixieToken);
    procedure HandleInTableText(var Token: TPixieToken);
    procedure HandleInCaption(var Token: TPixieToken);
    procedure HandleInColumnGroup(var Token: TPixieToken);
    procedure HandleInTableBody(var Token: TPixieToken);
    procedure HandleInRow(var Token: TPixieToken);
    procedure HandleInCell(var Token: TPixieToken);
    procedure HandleInSelect(var Token: TPixieToken);
    procedure HandleInSelectInTable(var Token: TPixieToken);
    procedure HandleInTemplate(var Token: TPixieToken);
    procedure HandleAfterBody(var Token: TPixieToken);
    procedure HandleInFrameset(var Token: TPixieToken);
    procedure HandleAfterFrameset(var Token: TPixieToken);
    procedure HandleAfterAfterBody(var Token: TPixieToken);
    procedure HandleAfterAfterFrameset(var Token: TPixieToken);
    // Reset insertion mode
    procedure ResetInsertionMode;
    // Update foreign context
    procedure UpdateForeignContext;
  public
    constructor Create(const AInput: string);
    destructor Destroy; override;
    function Parse: TPixieHtmlNode;
    function ParseFragment(const ContextTag: string): TPixieHtmlNode;
  end;

// Helper: case-insensitive string match
function StrEqI(const A, B: string): Boolean;
var
  I, Len: Integer;
begin
  Len := Length(A);
  if Len <> Length(B) then
    Exit(False);
  for I := 1 to Len do
    if Ord(A[I]) or $20 <> Ord(B[I]) or $20 then
      if not (((A[I] >= 'A') and (A[I] <= 'Z')) or ((A[I] >= 'a') and (A[I] <= 'z'))) then
      begin
        if A[I] <> B[I] then
          Exit(False);
      end
      else
        Exit(False);
  Result := True;
end;

function TagIn(const Tag: string; const Tags: array of string): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Tags) do
    if Tag = Tags[I] then
      Exit(True);
  Result := False;
end;

function IsAsciiAlpha(C: Integer): Boolean; inline;
begin
  Result := ((C >= Ord('A')) and (C <= Ord('Z'))) or
            ((C >= Ord('a')) and (C <= Ord('z')));
end;

function IsAsciiDigit(C: Integer): Boolean; inline;
begin
  Result := (C >= Ord('0')) and (C <= Ord('9'));
end;

function IsAsciiHexDigit(C: Integer): Boolean; inline;
begin
  Result := IsAsciiDigit(C) or
            ((C >= Ord('a')) and (C <= Ord('f'))) or
            ((C >= Ord('A')) and (C <= Ord('F')));
end;

function IsAsciiAlphaNum(C: Integer): Boolean; inline;
begin
  Result := IsAsciiAlpha(C) or IsAsciiDigit(C);
end;

function IsHtmlWhitespace(C: Integer): Boolean; inline;
begin
  Result := (C = Ord(' ')) or (C = 9) or (C = 10) or (C = 13) or (C = 12);
end;

function ToLower(C: Integer): Integer; inline;
begin
  if (C >= Ord('A')) and (C <= Ord('Z')) then
    Result := C + 32
  else
    Result := C;
end;

function LowerStr(const S: string): string;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    if (Result[I] >= 'A') and (Result[I] <= 'Z') then
      Result[I] := Chr(Ord(Result[I]) + 32);
end;

// Scope marker sentinel
var
  FormattingScopeMarker: TPixieHtmlNode;

// =========================================================================
// TPixieHtmlNode
// =========================================================================

constructor TPixieHtmlNode.Create(AType: TPixieHtmlNodeType);
begin
  inherited Create;
  NodeType := AType;
  Namespace := hnsHtml;
  Attributes := TPixieHtmlAttributeList.Create;
  Children := TPixieHtmlNodeList.Create;
  Parent := nil;
  QuirksMode := hqNoQuirks;
end;

destructor TPixieHtmlNode.Destroy;
var
  I: Integer;
begin
  for I := 0 to Children.Count - 1 do
    Children[I].Free;
  Children.Free;
  Attributes.Free;
  inherited;
end;

function TPixieHtmlNode.AppendChild(Child: TPixieHtmlNode): TPixieHtmlNode;
begin
  if Child.Parent <> nil then
    Child.Parent.Children.Remove(Child);
  Child.Parent := Self;
  Children.Add(Child);
  Result := Child;
end;

// Bulk-moves every child of Source onto Self, in order, without the
// O(n) Remove(Child) scan that AppendChild does per child. Use this
// in adoption-agency fixups where AppendChild(Source.Children[0]) was
// being called in a tight loop.
procedure TPixieHtmlNode.AdoptAllChildrenFrom(Source: TPixieHtmlNode);
var
  I: Integer;
  Child: TPixieHtmlNode;
begin
  if (Source = nil) or (Source = Self) then Exit;
  for I := 0 to Source.Children.Count - 1 do
  begin
    Child := Source.Children[I];
    Child.Parent := Self;
    Children.Add(Child);
  end;
  Source.Children.Clear;
end;

procedure TPixieHtmlNode.RemoveChild(Child: TPixieHtmlNode);
begin
  Children.Remove(Child);
  Child.Parent := nil;
end;

procedure TPixieHtmlNode.InsertChildBefore(Child, Before: TPixieHtmlNode);
var
  Idx: Integer;
begin
  if Child.Parent <> nil then
    Child.Parent.Children.Remove(Child);
  Child.Parent := Self;
  Idx := Children.IndexOf(Before);
  if Idx >= 0 then
    Children.Insert(Idx, Child)
  else
    Children.Add(Child);
end;

function TPixieHtmlNode.GetAttribute(const AName: string): string;
var
  I: Integer;
begin
  for I := 0 to Attributes.Count - 1 do
    if Attributes[I].Name = AName then
      Exit(Attributes[I].Value);
  Result := '';
end;

function TPixieHtmlNode.HasAttribute(const AName: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to Attributes.Count - 1 do
    if Attributes[I].Name = AName then
      Exit(True);
  Result := False;
end;

procedure TPixieHtmlNode.SetAttribute(const AName, AValue: string);
var
  I: Integer;
  Attr: TPixieHtmlAttribute;
begin
  for I := 0 to Attributes.Count - 1 do
    if Attributes[I].Name = AName then
    begin
      Attr := Attributes[I];
      Attr.Value := AValue;
      Attributes[I] := Attr;
      Exit;
    end;
  Attr.Name := AName;
  Attr.Value := AValue;
  Attributes.Add(Attr);
end;

function TPixieHtmlNode.CloneShallow: TPixieHtmlNode;
var
  I: Integer;
begin
  Result := TPixieHtmlNode.Create(NodeType);
  Result.Tag := Tag;
  Result.Text := Text;
  Result.Namespace := Namespace;
  for I := 0 to Attributes.Count - 1 do
    Result.Attributes.Add(Attributes[I]);
end;

// =========================================================================
// TPixieTokenizer
// =========================================================================

constructor TPixieTokenizer.Create(const AInput: string);
begin
  inherited Create;
  FInput := AInput;
  FPos := 1;
  FState := lsData;
  FReturnState := lsData;
  FReconsume := False;
  FCurrentChar := 0;
  FTagAttrs := TPixieHtmlAttributeList.Create;
  FIsForeignContext := False;
end;

destructor TPixieTokenizer.Destroy;
begin
  FTagAttrs.Free;
  inherited;
end;

procedure TPixieTokenizer.SetState(AState: TPixieLexState);
begin
  FState := AState;
end;

procedure TPixieTokenizer.SetForeignContext(Value: Boolean);
begin
  FIsForeignContext := Value;
end;

procedure TPixieTokenizer.Advance;
begin
  if FPos <= Length(FInput) then
  begin
    // Skip CR, replace CR+LF with LF, standalone CR -> LF
    if Ord(FInput[FPos]) = 13 then
    begin
      Inc(FPos);
      if (FPos <= Length(FInput)) and (Ord(FInput[FPos]) = 10) then
        Inc(FPos);
      FCurrentChar := 10;
    end
    else
    begin
      FCurrentChar := Integer(ReadUtf8Char(FInput, FPos));
    end;
  end
  else
    FCurrentChar := EOF_CHAR;
end;

function TPixieTokenizer.Peek: Integer;
var
  TempPos: Integer;
begin
  if FPos <= Length(FInput) then
  begin
    if Ord(FInput[FPos]) = 13 then
      Result := 10
    else
    begin
      TempPos := FPos;
      Result := Integer(ReadUtf8Char(FInput, TempPos));
    end;
  end
  else
    Result := EOF_CHAR;
end;

function TPixieTokenizer.MatchAhead(const S: string; CaseInsensitive: Boolean): Boolean;
var
  I: Integer;
  C1, C2: Integer;
begin
  if FPos + Length(S) - 1 > Length(FInput) then
    Exit(False);
  for I := 1 to Length(S) do
  begin
    C1 := Ord(FInput[FPos + I - 1]);
    C2 := Ord(S[I]);
    if CaseInsensitive then
    begin
      C1 := ToLower(C1);
      C2 := ToLower(C2);
    end;
    if C1 <> C2 then
      Exit(False);
  end;
  Result := True;
end;

procedure TPixieTokenizer.ConsumeAhead(Len: Integer);
begin
  Inc(FPos, Len);
end;

procedure TPixieTokenizer.StartNewTag(IsStart: Boolean);
begin
  FTagName := '';
  FTagIsStart := IsStart;
  FTagSelfClosing := False;
  FTagAttrs.Clear;
  FAttrName := '';
  FAttrValue := '';
end;

procedure TPixieTokenizer.FinishAttrName;
begin
  FAttrName := LowerStr(FAttrName);
end;

procedure TPixieTokenizer.FinishAttr;
var
  Attr: TPixieHtmlAttribute;
  I: Integer;
  IsDup: Boolean;
begin
  FAttrName := LowerStr(FAttrName);
  if FAttrName = '' then
    Exit;
  // Check for duplicates - first attribute wins
  IsDup := False;
  for I := 0 to FTagAttrs.Count - 1 do
    if FTagAttrs[I].Name = FAttrName then
    begin
      IsDup := True;
      Break;
    end;
  if not IsDup then
  begin
    Attr.Name := FAttrName;
    Attr.Value := FAttrValue;
    FTagAttrs.Add(Attr);
  end;
  FAttrName := '';
  FAttrValue := '';
end;

function TPixieTokenizer.IsAppropriateEndTag: Boolean;
begin
  Result := (FLastStartTag <> '') and (FTagName = FLastStartTag);
end;

procedure TPixieTokenizer.ConsumeCharRef(AdditionalAllowed: Integer;
  InAttr: Boolean; out Cp1, Cp2: Integer);
var
  C: Integer;
  NumValue: UInt32;
  IsHex: Boolean;
  EntName: string;
  EntData: TPixieEntityData;
  SavePos: Integer;
  BestName: string;
  BestLen: Integer;
  Matched: Boolean;
begin
  Cp1 := -1;
  Cp2 := -1;

  // Current position is right after '&'
  C := Peek;
  if (C = EOF_CHAR) or (C = Ord('>')) or IsHtmlWhitespace(C) or
     (C = AdditionalAllowed) or (C = Ord('&')) then
    Exit;

  if C = Ord('#') then
  begin
    // Numeric character reference
    SavePos := FPos;
    Advance; // consume '#'
    C := Peek;
    IsHex := False;
    if (C = Ord('x')) or (C = Ord('X')) then
    begin
      IsHex := True;
      Advance; // consume 'x'
      C := Peek;
    end;

    if IsHex then
    begin
      if not IsAsciiHexDigit(C) then
      begin
        FPos := SavePos; // restore: not a valid numeric ref
        Exit;
      end;
    end
    else
    begin
      if not IsAsciiDigit(C) then
      begin
        FPos := SavePos; // restore: not a valid numeric ref
        Exit;
      end;
    end;

    NumValue := 0;
    while True do
    begin
      C := Peek;
      if IsHex and IsAsciiHexDigit(C) then
      begin
        Advance;
        if IsAsciiDigit(C) then
          NumValue := NumValue * 16 + UInt32(C - Ord('0'))
        else
          NumValue := NumValue * 16 + UInt32(ToLower(C) - Ord('a') + 10);
        if NumValue > $10FFFF then
          NumValue := $110000; // cap to detect overflow
      end
      else if (not IsHex) and IsAsciiDigit(C) then
      begin
        Advance;
        NumValue := NumValue * 10 + UInt32(C - Ord('0'));
        if NumValue > $10FFFF then
          NumValue := $110000;
      end
      else
        Break;
    end;

    // Consume optional ';'
    if Peek = Ord(';') then
      Advance;

    Cp1 := Integer(PixieDecodeNumericRef(NumValue));
  end
  else if IsAsciiAlphaNum(C) then
  begin
    // Named character reference
    // Use greedy matching: try longest match first
    SavePos := FPos;
    EntName := '';
    BestName := '';
    BestLen := 0;

    while True do
    begin
      C := Peek;
      if (C = EOF_CHAR) or not (IsAsciiAlphaNum(C) or (C = Ord(';'))) then
        Break;
      Advance;
      AppendUtf8Char(EntName, C);
      if C = Ord(';') then
      begin
        // Try exact match with semicolon
        if PixieLookupEntity(Copy(EntName, 1, Length(EntName) - 1), EntData) then
        begin
          BestName := Copy(EntName, 1, Length(EntName) - 1);
          BestLen := FPos - SavePos;
          Cp1 := Integer(EntData.Codepoint1);
          Cp2 := Integer(EntData.Codepoint2);
          if Cp2 = 0 then
            Cp2 := -1;
        end;
        Break;
      end
      else
      begin
        // Check if this prefix is a legacy entity (without semicolon)
        if PixieLookupEntity(EntName, EntData) and PixieIsLegacyEntity(EntName) then
        begin
          BestName := EntName;
          BestLen := FPos - SavePos;
          Cp1 := Integer(EntData.Codepoint1);
          Cp2 := Integer(EntData.Codepoint2);
          if Cp2 = 0 then
            Cp2 := -1;
        end;
      end;
    end;

    if BestName <> '' then
    begin
      // In attribute context, legacy entities followed by '=' or alphanumeric are not consumed
      if InAttr and (BestName + ';' <> Copy(EntName, 1, Length(BestName) + 1)) then
      begin
        Matched := False;
        FPos := SavePos + BestLen;
        C := Peek;
        if (C = Ord('=')) or IsAsciiAlphaNum(C) then
        begin
          // Don't consume
          FPos := SavePos;
          Cp1 := -1;
          Cp2 := -1;
          Matched := True;
        end;
        if not Matched then
          FPos := SavePos + BestLen;
      end
      else
        FPos := SavePos + BestLen;
    end
    else
      FPos := SavePos; // restore
  end;
end;

function TPixieTokenizer.EmitChar(C: Integer; out Token: TPixieToken): Boolean;
begin
  Token.TokenType := ttCharacter;
  Token.DataChar := C;
  Token.Data := '';
  if C > 0 then
    AppendUtf8Char(Token.Data, UInt32(C));
  Result := True;
end;

function TPixieTokenizer.EmitTag(out Token: TPixieToken): Boolean;
var
  I: Integer;
begin
  if FTagIsStart then
  begin
    Token.TokenType := ttStartTag;
    FLastStartTag := FTagName;
  end
  else
    Token.TokenType := ttEndTag;
  Token.Name := FTagName;
  Token.SelfClosing := FTagSelfClosing;
  Token.Attrs := TPixieHtmlAttributeList.Create;
  for I := 0 to FTagAttrs.Count - 1 do
    Token.Attrs.Add(FTagAttrs[I]);
  FTagAttrs.Clear;
  Result := True;
end;

function TPixieTokenizer.EmitComment(out Token: TPixieToken): Boolean;
begin
  Token.TokenType := ttComment;
  Token.Data := FComment;
  FComment := '';
  Result := True;
end;

function TPixieTokenizer.EmitDoctype(out Token: TPixieToken): Boolean;
begin
  Token.TokenType := ttDoctype;
  Token.Name := FDoctypeName;
  Token.PublicId := FDoctypePublicId;
  Token.SystemId := FDoctypeSystemId;
  Token.ForceQuirks := FDoctypeForceQuirks;
  Result := True;
end;

function TPixieTokenizer.EmitEof(out Token: TPixieToken): Boolean;
begin
  Token.TokenType := ttEof;
  Result := True;
end;

function TPixieTokenizer.NextToken(out Token: TPixieToken): Boolean;
var
  C, Cp1, Cp2: Integer;
  TempStr: string;
begin
  Token := Default(TPixieToken);
  Result := True;

  while True do
  begin
    if not FReconsume then
      Advance
    else
      FReconsume := False;
    C := FCurrentChar;

    case FState of
      // =====================================================================
      // DATA STATE
      // =====================================================================
      lsData:
      begin
        case C of
          Ord('&'):
          begin
            FReturnState := lsData;
            ConsumeCharRef(-1, False, Cp1, Cp2);
            if Cp1 >= 0 then
            begin
              EmitChar(Cp1, Token);
              // If second codepoint, we need to emit it next time
              // For simplicity, append it to the text
              if Cp2 >= 0 then
                AppendUtf8Char(Token.Data, UInt32(Cp2));
              Exit;
            end
            else
            begin
              EmitChar(Ord('&'), Token);
              Exit;
            end;
          end;
          Ord('<'):
          begin
            FState := lsTagOpen;
          end;
          NULL_CHAR:
          begin
            EmitChar(REPLACEMENT_CHAR, Token);
            Exit;
          end;
          EOF_CHAR:
          begin
            EmitEof(Token);
            Exit;
          end;
        else
          EmitChar(C, Token);
          Exit;
        end;
      end;

      // =====================================================================
      // TAG OPEN STATE
      // =====================================================================
      lsTagOpen:
      begin
        case C of
          Ord('!'):
          begin
            FState := lsMarkupDeclaration;
            FReconsume := True;
          end;
          Ord('/'):
            FState := lsEndTagOpen;
          Ord('?'):
          begin
            FComment := '';
            FReconsume := True;
            FState := lsBogusComment;
          end;
        else
          if IsAsciiAlpha(C) then
          begin
            StartNewTag(True);
            FReconsume := True;
            FState := lsTagName;
          end
          else
          begin
            FState := lsData;
            FReconsume := True;
            EmitChar(Ord('<'), Token);
            Exit;
          end;
        end;
      end;

      // =====================================================================
      // END TAG OPEN STATE
      // =====================================================================
      lsEndTagOpen:
      begin
        if IsAsciiAlpha(C) then
        begin
          StartNewTag(False);
          FReconsume := True;
          FState := lsTagName;
        end
        else if C = Ord('>') then
          FState := lsData // error: empty end tag
        else if C = EOF_CHAR then
        begin
          EmitChar(Ord('<'), Token);
          // Also need to emit '/' but for simplicity just return '<'
          FReconsume := True;
          FState := lsData;
          Exit;
        end
        else
        begin
          FComment := '';
          FReconsume := True;
          FState := lsBogusComment;
        end;
      end;

      // =====================================================================
      // TAG NAME STATE
      // =====================================================================
      lsTagName:
      begin
        if IsHtmlWhitespace(C) then
          FState := lsBeforeAttrName
        else if C = Ord('/') then
          FState := lsSelfClosingStartTag
        else if C = Ord('>') then
        begin
          FState := lsData;
          EmitTag(Token);
          Exit;
        end
        else if C = NULL_CHAR then
          AppendUtf8Char(FTagName, REPLACEMENT_CHAR)
        else if C = EOF_CHAR then
        begin
          EmitEof(Token);
          Exit;
        end
        else
          AppendUtf8Char(FTagName, ToLower(C));
      end;

      // =====================================================================
      // BEFORE ATTRIBUTE NAME STATE
      // =====================================================================
      lsBeforeAttrName:
      begin
        if IsHtmlWhitespace(C) then
          // skip
        else if (C = Ord('/')) or (C = Ord('>')) or (C = EOF_CHAR) then
        begin
          FReconsume := True;
          FState := lsAfterAttrName;
        end
        else if C = Ord('=') then
        begin
          // error, start attr with '='
          FAttrName := '';
          AppendUtf8Char(FAttrName, C);
          FAttrValue := '';
          FState := lsAttrName;
        end
        else
        begin
          FAttrName := '';
          FAttrValue := '';
          FReconsume := True;
          FState := lsAttrName;
        end;
      end;

      // =====================================================================
      // ATTRIBUTE NAME STATE
      // =====================================================================
      lsAttrName:
      begin
        if IsHtmlWhitespace(C) or (C = Ord('/')) or (C = Ord('>')) or (C = EOF_CHAR) then
        begin
          FinishAttrName;
          FReconsume := True;
          FState := lsAfterAttrName;
        end
        else if C = Ord('=') then
        begin
          FinishAttrName;
          FState := lsBeforeAttrValue;
        end
        else if C = NULL_CHAR then
          AppendUtf8Char(FAttrName, REPLACEMENT_CHAR)
        else
          AppendUtf8Char(FAttrName, ToLower(C));
      end;

      // =====================================================================
      // AFTER ATTRIBUTE NAME STATE
      // =====================================================================
      lsAfterAttrName:
      begin
        if IsHtmlWhitespace(C) then
          // skip
        else if C = Ord('/') then
        begin
          FinishAttr;
          FState := lsSelfClosingStartTag;
        end
        else if C = Ord('=') then
          FState := lsBeforeAttrValue
        else if C = Ord('>') then
        begin
          FinishAttr;
          FState := lsData;
          EmitTag(Token);
          Exit;
        end
        else if C = EOF_CHAR then
        begin
          FinishAttr;
          EmitEof(Token);
          Exit;
        end
        else
        begin
          FinishAttr;
          FAttrName := '';
          FAttrValue := '';
          FReconsume := True;
          FState := lsAttrName;
        end;
      end;

      // =====================================================================
      // BEFORE ATTRIBUTE VALUE STATE
      // =====================================================================
      lsBeforeAttrValue:
      begin
        if IsHtmlWhitespace(C) then
          // skip
        else if C = Ord('"') then
          FState := lsAttrValueDoubleQuoted
        else if C = Ord('''') then
          FState := lsAttrValueSingleQuoted
        else if C = Ord('>') then
        begin
          FinishAttr;
          FState := lsData;
          EmitTag(Token);
          Exit;
        end
        else
        begin
          FReconsume := True;
          FState := lsAttrValueUnquoted;
        end;
      end;

      // =====================================================================
      // ATTRIBUTE VALUE (DOUBLE-QUOTED) STATE
      // =====================================================================
      lsAttrValueDoubleQuoted:
      begin
        case C of
          Ord('"'):
          begin
            FinishAttr;
            FState := lsAfterAttrValueQuoted;
          end;
          Ord('&'):
          begin
            ConsumeCharRef(Ord('"'), True, Cp1, Cp2);
            if Cp1 >= 0 then
            begin
              AppendUtf8Char(FAttrValue, UInt32(Cp1));
              if Cp2 >= 0 then
                AppendUtf8Char(FAttrValue, UInt32(Cp2));
            end
            else
              FAttrValue := FAttrValue + '&';
          end;
          NULL_CHAR:
            AppendUtf8Char(FAttrValue, REPLACEMENT_CHAR);
          EOF_CHAR:
          begin
            FinishAttr;
            EmitEof(Token);
            Exit;
          end;
        else
          AppendUtf8Char(FAttrValue, C);
        end;
      end;

      // =====================================================================
      // ATTRIBUTE VALUE (SINGLE-QUOTED) STATE
      // =====================================================================
      lsAttrValueSingleQuoted:
      begin
        case C of
          Ord(''''):
          begin
            FinishAttr;
            FState := lsAfterAttrValueQuoted;
          end;
          Ord('&'):
          begin
            ConsumeCharRef(Ord(''''), True, Cp1, Cp2);
            if Cp1 >= 0 then
            begin
              AppendUtf8Char(FAttrValue, UInt32(Cp1));
              if Cp2 >= 0 then
                AppendUtf8Char(FAttrValue, UInt32(Cp2));
            end
            else
              FAttrValue := FAttrValue + '&';
          end;
          NULL_CHAR:
            AppendUtf8Char(FAttrValue, REPLACEMENT_CHAR);
          EOF_CHAR:
          begin
            FinishAttr;
            EmitEof(Token);
            Exit;
          end;
        else
          AppendUtf8Char(FAttrValue, C);
        end;
      end;

      // =====================================================================
      // ATTRIBUTE VALUE (UNQUOTED) STATE
      // =====================================================================
      lsAttrValueUnquoted:
      begin
        if IsHtmlWhitespace(C) then
        begin
          FinishAttr;
          FState := lsBeforeAttrName;
        end
        else
        case C of
          Ord('&'):
          begin
            ConsumeCharRef(Ord('>'), True, Cp1, Cp2);
            if Cp1 >= 0 then
            begin
              AppendUtf8Char(FAttrValue, UInt32(Cp1));
              if Cp2 >= 0 then
                AppendUtf8Char(FAttrValue, UInt32(Cp2));
            end
            else
              FAttrValue := FAttrValue + '&';
          end;
          Ord('>'):
          begin
            FinishAttr;
            FState := lsData;
            EmitTag(Token);
            Exit;
          end;
          NULL_CHAR:
            AppendUtf8Char(FAttrValue, REPLACEMENT_CHAR);
          EOF_CHAR:
          begin
            FinishAttr;
            EmitEof(Token);
            Exit;
          end;
        else
          AppendUtf8Char(FAttrValue, C);
        end;
      end;

      // =====================================================================
      // AFTER ATTRIBUTE VALUE (QUOTED) STATE
      // =====================================================================
      lsAfterAttrValueQuoted:
      begin
        if IsHtmlWhitespace(C) then
          FState := lsBeforeAttrName
        else if C = Ord('/') then
          FState := lsSelfClosingStartTag
        else if C = Ord('>') then
        begin
          FState := lsData;
          EmitTag(Token);
          Exit;
        end
        else if C = EOF_CHAR then
        begin
          EmitEof(Token);
          Exit;
        end
        else
        begin
          FReconsume := True;
          FState := lsBeforeAttrName;
        end;
      end;

      // =====================================================================
      // SELF-CLOSING START TAG STATE
      // =====================================================================
      lsSelfClosingStartTag:
      begin
        if C = Ord('>') then
        begin
          FTagSelfClosing := True;
          FState := lsData;
          EmitTag(Token);
          Exit;
        end
        else if C = EOF_CHAR then
        begin
          EmitEof(Token);
          Exit;
        end
        else
        begin
          FReconsume := True;
          FState := lsBeforeAttrName;
        end;
      end;

      // =====================================================================
      // BOGUS COMMENT STATE
      // =====================================================================
      lsBogusComment:
      begin
        if C = Ord('>') then
        begin
          FState := lsData;
          EmitComment(Token);
          Exit;
        end
        else if C = EOF_CHAR then
        begin
          EmitComment(Token);
          Exit;
        end
        else if C = NULL_CHAR then
          AppendUtf8Char(FComment, REPLACEMENT_CHAR)
        else
          AppendUtf8Char(FComment, C);
      end;

      // =====================================================================
      // MARKUP DECLARATION STATE
      // =====================================================================
      lsMarkupDeclaration:
      begin
        if MatchAhead('--', False) then
        begin
          ConsumeAhead(2);
          FComment := '';
          FState := lsCommentStart;
        end
        else if MatchAhead('DOCTYPE', True) then
        begin
          ConsumeAhead(7);
          FState := lsDoctype;
        end
        else if FIsForeignContext and MatchAhead('[CDATA[', False) then
        begin
          ConsumeAhead(7);
          FState := lsCdata;
        end
        else
        begin
          FComment := '';
          FState := lsBogusComment;
        end;
      end;

      // =====================================================================
      // COMMENT STATES
      // =====================================================================
      lsCommentStart:
      begin
        if C = Ord('-') then
          FState := lsCommentStartDash
        else if C = Ord('>') then
        begin
          FState := lsData;
          EmitComment(Token);
          Exit;
        end
        else if C = EOF_CHAR then
        begin
          EmitComment(Token);
          Exit;
        end
        else if C = NULL_CHAR then
        begin
          AppendUtf8Char(FComment, REPLACEMENT_CHAR);
          FState := lsComment;
        end
        else
        begin
          AppendUtf8Char(FComment, C);
          FState := lsComment;
        end;
      end;

      lsCommentStartDash:
      begin
        if C = Ord('-') then
          FState := lsCommentEnd
        else if C = Ord('>') then
        begin
          FState := lsData;
          EmitComment(Token);
          Exit;
        end
        else if C = EOF_CHAR then
        begin
          EmitComment(Token);
          Exit;
        end
        else
        begin
          FComment := FComment + '-';
          AppendUtf8Char(FComment, C);
          FState := lsComment;
        end;
      end;

      lsComment:
      begin
        if C = Ord('-') then
          FState := lsCommentEndDash
        else if C = NULL_CHAR then
          AppendUtf8Char(FComment, REPLACEMENT_CHAR)
        else if C = EOF_CHAR then
        begin
          EmitComment(Token);
          Exit;
        end
        else
          AppendUtf8Char(FComment, C);
      end;

      lsCommentEndDash:
      begin
        if C = Ord('-') then
          FState := lsCommentEnd
        else if C = EOF_CHAR then
        begin
          EmitComment(Token);
          Exit;
        end
        else
        begin
          FComment := FComment + '-';
          AppendUtf8Char(FComment, C);
          FState := lsComment;
        end;
      end;

      lsCommentEnd:
      begin
        if C = Ord('>') then
        begin
          FState := lsData;
          EmitComment(Token);
          Exit;
        end
        else if C = Ord('!') then
          FState := lsCommentEndBang
        else if C = Ord('-') then
          FComment := FComment + '-'
        else if C = EOF_CHAR then
        begin
          EmitComment(Token);
          Exit;
        end
        else
        begin
          FComment := FComment + '--';
          AppendUtf8Char(FComment, C);
          FState := lsComment;
        end;
      end;

      lsCommentEndBang:
      begin
        if C = Ord('-') then
        begin
          FComment := FComment + '--!';
          FState := lsCommentEndDash;
        end
        else if C = Ord('>') then
        begin
          FState := lsData;
          EmitComment(Token);
          Exit;
        end
        else if C = EOF_CHAR then
        begin
          EmitComment(Token);
          Exit;
        end
        else
        begin
          FComment := FComment + '--!';
          AppendUtf8Char(FComment, C);
          FState := lsComment;
        end;
      end;

      // =====================================================================
      // DOCTYPE STATES
      // =====================================================================
      lsDoctype:
      begin
        if IsHtmlWhitespace(C) then
          FState := lsBeforeDoctypeName
        else if C = Ord('>') then
        begin
          FReconsume := True;
          FState := lsBeforeDoctypeName;
        end
        else if C = EOF_CHAR then
        begin
          FDoctypeName := '';
          FDoctypePublicId := '';
          FDoctypeSystemId := '';
          FDoctypeForceQuirks := True;
          EmitDoctype(Token);
          Exit;
        end
        else
        begin
          FReconsume := True;
          FState := lsBeforeDoctypeName;
        end;
      end;

      lsBeforeDoctypeName:
      begin
        if IsHtmlWhitespace(C) then
          // skip
        else if C = Ord('>') then
        begin
          FDoctypeName := '';
          FDoctypeForceQuirks := True;
          FState := lsData;
          EmitDoctype(Token);
          Exit;
        end
        else if C = NULL_CHAR then
        begin
          FDoctypeName := '';
          AppendUtf8Char(FDoctypeName, REPLACEMENT_CHAR);
          FDoctypePublicId := '';
          FDoctypeSystemId := '';
          FDoctypeForceQuirks := False;
          FDoctypeHasPublicId := False;
          FDoctypeHasSystemId := False;
          FState := lsDoctypeName;
        end
        else if C = EOF_CHAR then
        begin
          FDoctypeName := '';
          FDoctypeForceQuirks := True;
          EmitDoctype(Token);
          Exit;
        end
        else
        begin
          FDoctypeName := '';
          AppendUtf8Char(FDoctypeName, ToLower(C));
          FDoctypePublicId := '';
          FDoctypeSystemId := '';
          FDoctypeForceQuirks := False;
          FDoctypeHasPublicId := False;
          FDoctypeHasSystemId := False;
          FState := lsDoctypeName;
        end;
      end;

      lsDoctypeName:
      begin
        if IsHtmlWhitespace(C) then
          FState := lsAfterDoctypeName
        else if C = Ord('>') then
        begin
          FState := lsData;
          EmitDoctype(Token);
          Exit;
        end
        else if C = NULL_CHAR then
          AppendUtf8Char(FDoctypeName, REPLACEMENT_CHAR)
        else if C = EOF_CHAR then
        begin
          FDoctypeForceQuirks := True;
          EmitDoctype(Token);
          Exit;
        end
        else
          AppendUtf8Char(FDoctypeName, ToLower(C));
      end;

      lsAfterDoctypeName:
      begin
        if IsHtmlWhitespace(C) then
          // skip
        else if C = Ord('>') then
        begin
          FState := lsData;
          EmitDoctype(Token);
          Exit;
        end
        else if C = EOF_CHAR then
        begin
          FDoctypeForceQuirks := True;
          EmitDoctype(Token);
          Exit;
        end
        else if MatchAhead('UBLIC', True) then // we already consumed 'P' via C
        begin
          if Chr(ToLower(C)) = 'p' then
          begin
            ConsumeAhead(5);
            FState := lsAfterDoctypePublicKeyword;
          end
          else if Chr(ToLower(C)) = 's' then
          begin
            // Check for SYSTEM: we consumed 'S', check 'YSTEM'
            if MatchAhead('YSTEM', True) then
            begin
              ConsumeAhead(5);
              FState := lsAfterDoctypeSystemKeyword;
            end
            else
            begin
              FDoctypeForceQuirks := True;
              FState := lsBogusDoctype;
            end;
          end
          else
          begin
            FDoctypeForceQuirks := True;
            FState := lsBogusDoctype;
          end;
        end
        else if (Chr(ToLower(C)) = 's') and MatchAhead('YSTEM', True) then
        begin
          ConsumeAhead(5);
          FState := lsAfterDoctypeSystemKeyword;
        end
        else
        begin
          FDoctypeForceQuirks := True;
          FState := lsBogusDoctype;
        end;
      end;

      lsAfterDoctypePublicKeyword:
      begin
        if IsHtmlWhitespace(C) then
          FState := lsBeforeDoctypePublicId
        else if C = Ord('"') then
        begin
          FDoctypePublicId := '';
          FDoctypeHasPublicId := True;
          FState := lsDoctypePublicIdDoubleQuoted;
        end
        else if C = Ord('''') then
        begin
          FDoctypePublicId := '';
          FDoctypeHasPublicId := True;
          FState := lsDoctypePublicIdSingleQuoted;
        end
        else if C = Ord('>') then
        begin
          FDoctypeForceQuirks := True;
          FState := lsData;
          EmitDoctype(Token);
          Exit;
        end
        else if C = EOF_CHAR then
        begin
          FDoctypeForceQuirks := True;
          EmitDoctype(Token);
          Exit;
        end
        else
        begin
          FDoctypeForceQuirks := True;
          FState := lsBogusDoctype;
        end;
      end;

      lsBeforeDoctypePublicId:
      begin
        if IsHtmlWhitespace(C) then
          // skip
        else if C = Ord('"') then
        begin
          FDoctypePublicId := '';
          FDoctypeHasPublicId := True;
          FState := lsDoctypePublicIdDoubleQuoted;
        end
        else if C = Ord('''') then
        begin
          FDoctypePublicId := '';
          FDoctypeHasPublicId := True;
          FState := lsDoctypePublicIdSingleQuoted;
        end
        else if C = Ord('>') then
        begin
          FDoctypeForceQuirks := True;
          FState := lsData;
          EmitDoctype(Token);
          Exit;
        end
        else if C = EOF_CHAR then
        begin
          FDoctypeForceQuirks := True;
          EmitDoctype(Token);
          Exit;
        end
        else
        begin
          FDoctypeForceQuirks := True;
          FState := lsBogusDoctype;
        end;
      end;

      lsDoctypePublicIdDoubleQuoted:
      begin
        if C = Ord('"') then
          FState := lsAfterDoctypePublicId
        else if C = NULL_CHAR then
          AppendUtf8Char(FDoctypePublicId, REPLACEMENT_CHAR)
        else if C = Ord('>') then
        begin
          FDoctypeForceQuirks := True;
          FState := lsData;
          EmitDoctype(Token);
          Exit;
        end
        else if C = EOF_CHAR then
        begin
          FDoctypeForceQuirks := True;
          EmitDoctype(Token);
          Exit;
        end
        else
          AppendUtf8Char(FDoctypePublicId, C);
      end;

      lsDoctypePublicIdSingleQuoted:
      begin
        if C = Ord('''') then
          FState := lsAfterDoctypePublicId
        else if C = NULL_CHAR then
          AppendUtf8Char(FDoctypePublicId, REPLACEMENT_CHAR)
        else if C = Ord('>') then
        begin
          FDoctypeForceQuirks := True;
          FState := lsData;
          EmitDoctype(Token);
          Exit;
        end
        else if C = EOF_CHAR then
        begin
          FDoctypeForceQuirks := True;
          EmitDoctype(Token);
          Exit;
        end
        else
          AppendUtf8Char(FDoctypePublicId, C);
      end;

      lsAfterDoctypePublicId:
      begin
        if IsHtmlWhitespace(C) then
          FState := lsBetweenDoctypePublicSystemId
        else if C = Ord('>') then
        begin
          FState := lsData;
          EmitDoctype(Token);
          Exit;
        end
        else if C = Ord('"') then
        begin
          FDoctypeSystemId := '';
          FDoctypeHasSystemId := True;
          FState := lsDoctypeSystemIdDoubleQuoted;
        end
        else if C = Ord('''') then
        begin
          FDoctypeSystemId := '';
          FDoctypeHasSystemId := True;
          FState := lsDoctypeSystemIdSingleQuoted;
        end
        else if C = EOF_CHAR then
        begin
          FDoctypeForceQuirks := True;
          EmitDoctype(Token);
          Exit;
        end
        else
        begin
          FDoctypeForceQuirks := True;
          FState := lsBogusDoctype;
        end;
      end;

      lsBetweenDoctypePublicSystemId:
      begin
        if IsHtmlWhitespace(C) then
          // skip
        else if C = Ord('>') then
        begin
          FState := lsData;
          EmitDoctype(Token);
          Exit;
        end
        else if C = Ord('"') then
        begin
          FDoctypeSystemId := '';
          FDoctypeHasSystemId := True;
          FState := lsDoctypeSystemIdDoubleQuoted;
        end
        else if C = Ord('''') then
        begin
          FDoctypeSystemId := '';
          FDoctypeHasSystemId := True;
          FState := lsDoctypeSystemIdSingleQuoted;
        end
        else if C = EOF_CHAR then
        begin
          FDoctypeForceQuirks := True;
          EmitDoctype(Token);
          Exit;
        end
        else
        begin
          FDoctypeForceQuirks := True;
          FState := lsBogusDoctype;
        end;
      end;

      lsAfterDoctypeSystemKeyword:
      begin
        if IsHtmlWhitespace(C) then
          FState := lsBeforeDoctypeSystemId
        else if C = Ord('"') then
        begin
          FDoctypeSystemId := '';
          FDoctypeHasSystemId := True;
          FState := lsDoctypeSystemIdDoubleQuoted;
        end
        else if C = Ord('''') then
        begin
          FDoctypeSystemId := '';
          FDoctypeHasSystemId := True;
          FState := lsDoctypeSystemIdSingleQuoted;
        end
        else if C = Ord('>') then
        begin
          FDoctypeForceQuirks := True;
          FState := lsData;
          EmitDoctype(Token);
          Exit;
        end
        else if C = EOF_CHAR then
        begin
          FDoctypeForceQuirks := True;
          EmitDoctype(Token);
          Exit;
        end
        else
        begin
          FDoctypeForceQuirks := True;
          FState := lsBogusDoctype;
        end;
      end;

      lsBeforeDoctypeSystemId:
      begin
        if IsHtmlWhitespace(C) then
          // skip
        else if C = Ord('"') then
        begin
          FDoctypeSystemId := '';
          FDoctypeHasSystemId := True;
          FState := lsDoctypeSystemIdDoubleQuoted;
        end
        else if C = Ord('''') then
        begin
          FDoctypeSystemId := '';
          FDoctypeHasSystemId := True;
          FState := lsDoctypeSystemIdSingleQuoted;
        end
        else if C = Ord('>') then
        begin
          FDoctypeForceQuirks := True;
          FState := lsData;
          EmitDoctype(Token);
          Exit;
        end
        else if C = EOF_CHAR then
        begin
          FDoctypeForceQuirks := True;
          EmitDoctype(Token);
          Exit;
        end
        else
        begin
          FDoctypeForceQuirks := True;
          FState := lsBogusDoctype;
        end;
      end;

      lsDoctypeSystemIdDoubleQuoted:
      begin
        if C = Ord('"') then
          FState := lsAfterDoctypeSystemId
        else if C = NULL_CHAR then
          AppendUtf8Char(FDoctypeSystemId, REPLACEMENT_CHAR)
        else if C = Ord('>') then
        begin
          FDoctypeForceQuirks := True;
          FState := lsData;
          EmitDoctype(Token);
          Exit;
        end
        else if C = EOF_CHAR then
        begin
          FDoctypeForceQuirks := True;
          EmitDoctype(Token);
          Exit;
        end
        else
          AppendUtf8Char(FDoctypeSystemId, C);
      end;

      lsDoctypeSystemIdSingleQuoted:
      begin
        if C = Ord('''') then
          FState := lsAfterDoctypeSystemId
        else if C = NULL_CHAR then
          AppendUtf8Char(FDoctypeSystemId, REPLACEMENT_CHAR)
        else if C = Ord('>') then
        begin
          FDoctypeForceQuirks := True;
          FState := lsData;
          EmitDoctype(Token);
          Exit;
        end
        else if C = EOF_CHAR then
        begin
          FDoctypeForceQuirks := True;
          EmitDoctype(Token);
          Exit;
        end
        else
          AppendUtf8Char(FDoctypeSystemId, C);
      end;

      lsAfterDoctypeSystemId:
      begin
        if IsHtmlWhitespace(C) then
          // skip
        else if C = Ord('>') then
        begin
          FState := lsData;
          EmitDoctype(Token);
          Exit;
        end
        else if C = EOF_CHAR then
        begin
          FDoctypeForceQuirks := True;
          EmitDoctype(Token);
          Exit;
        end
        else
          FState := lsBogusDoctype;
      end;

      lsBogusDoctype:
      begin
        if C = Ord('>') then
        begin
          FState := lsData;
          EmitDoctype(Token);
          Exit;
        end
        else if C = EOF_CHAR then
        begin
          EmitDoctype(Token);
          Exit;
        end;
        // else skip
      end;

      // =====================================================================
      // CDATA STATE
      // =====================================================================
      lsCdata:
      begin
        if C = EOF_CHAR then
        begin
          FState := lsData;
          EmitEof(Token);
          Exit;
        end
        else if (C = Ord(']')) and MatchAhead(']>', False) then
        begin
          ConsumeAhead(2);
          FState := lsData;
        end
        else
        begin
          EmitChar(C, Token);
          // Mark as CDATA by putting a special flag in the data
          Token.DataChar := -2; // sentinel for CDATA char
          Exit;
        end;
      end;

      // =====================================================================
      // RCDATA STATE
      // =====================================================================
      lsRcdata:
      begin
        case C of
          Ord('&'):
          begin
            ConsumeCharRef(-1, False, Cp1, Cp2);
            if Cp1 >= 0 then
            begin
              EmitChar(Cp1, Token);
              if Cp2 >= 0 then
                AppendUtf8Char(Token.Data, UInt32(Cp2));
              Exit;
            end
            else
            begin
              EmitChar(Ord('&'), Token);
              Exit;
            end;
          end;
          Ord('<'):
            FState := lsRcdataLt;
          NULL_CHAR:
          begin
            EmitChar(REPLACEMENT_CHAR, Token);
            Exit;
          end;
          EOF_CHAR:
          begin
            EmitEof(Token);
            Exit;
          end;
        else
          EmitChar(C, Token);
          Exit;
        end;
      end;

      lsRcdataLt:
      begin
        if C = Ord('/') then
        begin
          FTempBuffer := '';
          FState := lsRcdataEndTagOpen;
        end
        else
        begin
          FReconsume := True;
          FState := lsRcdata;
          EmitChar(Ord('<'), Token);
          Exit;
        end;
      end;

      lsRcdataEndTagOpen:
      begin
        if IsAsciiAlpha(C) then
        begin
          StartNewTag(False);
          FReconsume := True;
          FState := lsRcdataEndTagName;
        end
        else
        begin
          FReconsume := True;
          FState := lsRcdata;
          EmitChar(Ord('<'), Token);
          // We also need to emit '/' but simplify: put both in Data
          Token.Data := '</';
          Exit;
        end;
      end;

      lsRcdataEndTagName:
      begin
        if (IsHtmlWhitespace(C) or (C = Ord('/')) or (C = Ord('>'))) and IsAppropriateEndTag then
        begin
          if C = Ord('>') then
          begin
            FState := lsData;
            EmitTag(Token);
            Exit;
          end
          else if C = Ord('/') then
            FState := lsSelfClosingStartTag
          else
            FState := lsBeforeAttrName;
        end
        else if IsAsciiAlpha(C) then
        begin
          AppendUtf8Char(FTagName, ToLower(C));
          AppendUtf8Char(FTempBuffer, C);
        end
        else
        begin
          // Not an appropriate end tag, emit as text
          FState := lsRcdata;
          TempStr := '</' + FTempBuffer;
          FReconsume := True;
          EmitChar(Ord('<'), Token);
          Token.Data := TempStr;
          Exit;
        end;
      end;

      // =====================================================================
      // RAWTEXT STATE
      // =====================================================================
      lsRawtext:
      begin
        case C of
          Ord('<'):
            FState := lsRawtextLt;
          NULL_CHAR:
          begin
            EmitChar(REPLACEMENT_CHAR, Token);
            Exit;
          end;
          EOF_CHAR:
          begin
            EmitEof(Token);
            Exit;
          end;
        else
          EmitChar(C, Token);
          Exit;
        end;
      end;

      lsRawtextLt:
      begin
        if C = Ord('/') then
        begin
          FTempBuffer := '';
          FState := lsRawtextEndTagOpen;
        end
        else
        begin
          FReconsume := True;
          FState := lsRawtext;
          EmitChar(Ord('<'), Token);
          Exit;
        end;
      end;

      lsRawtextEndTagOpen:
      begin
        if IsAsciiAlpha(C) then
        begin
          StartNewTag(False);
          FReconsume := True;
          FState := lsRawtextEndTagName;
        end
        else
        begin
          FReconsume := True;
          FState := lsRawtext;
          EmitChar(Ord('<'), Token);
          Token.Data := '</';
          Exit;
        end;
      end;

      lsRawtextEndTagName:
      begin
        if (IsHtmlWhitespace(C) or (C = Ord('/')) or (C = Ord('>'))) and IsAppropriateEndTag then
        begin
          if C = Ord('>') then
          begin
            FState := lsData;
            EmitTag(Token);
            Exit;
          end
          else if C = Ord('/') then
            FState := lsSelfClosingStartTag
          else
            FState := lsBeforeAttrName;
        end
        else if IsAsciiAlpha(C) then
        begin
          AppendUtf8Char(FTagName, ToLower(C));
          AppendUtf8Char(FTempBuffer, C);
        end
        else
        begin
          FState := lsRawtext;
          TempStr := '</' + FTempBuffer;
          FReconsume := True;
          EmitChar(Ord('<'), Token);
          Token.Data := TempStr;
          Exit;
        end;
      end;

      // =====================================================================
      // SCRIPT DATA STATE
      // =====================================================================
      lsScript:
      begin
        case C of
          Ord('<'):
            FState := lsScriptLt;
          NULL_CHAR:
          begin
            EmitChar(REPLACEMENT_CHAR, Token);
            Exit;
          end;
          EOF_CHAR:
          begin
            EmitEof(Token);
            Exit;
          end;
        else
          EmitChar(C, Token);
          Exit;
        end;
      end;

      lsScriptLt:
      begin
        case C of
          Ord('/'):
          begin
            FTempBuffer := '';
            FState := lsScriptEndTagOpen;
          end;
          Ord('!'):
          begin
            FState := lsScriptEscapedStart;
            EmitChar(Ord('<'), Token);
            Token.Data := '<!';
            Exit;
          end;
        else
          FReconsume := True;
          FState := lsScript;
          EmitChar(Ord('<'), Token);
          Exit;
        end;
      end;

      lsScriptEndTagOpen:
      begin
        if IsAsciiAlpha(C) then
        begin
          StartNewTag(False);
          FReconsume := True;
          FState := lsScriptEndTagName;
        end
        else
        begin
          FReconsume := True;
          FState := lsScript;
          EmitChar(Ord('<'), Token);
          Token.Data := '</';
          Exit;
        end;
      end;

      lsScriptEndTagName:
      begin
        if (IsHtmlWhitespace(C) or (C = Ord('/')) or (C = Ord('>'))) and IsAppropriateEndTag then
        begin
          if C = Ord('>') then
          begin
            FState := lsData;
            EmitTag(Token);
            Exit;
          end
          else if C = Ord('/') then
            FState := lsSelfClosingStartTag
          else
            FState := lsBeforeAttrName;
        end
        else if IsAsciiAlpha(C) then
        begin
          AppendUtf8Char(FTagName, ToLower(C));
          AppendUtf8Char(FTempBuffer, C);
        end
        else
        begin
          FState := lsScript;
          TempStr := '</' + FTempBuffer;
          FReconsume := True;
          EmitChar(Ord('<'), Token);
          Token.Data := TempStr;
          Exit;
        end;
      end;

      lsScriptEscapedStart:
      begin
        if C = Ord('-') then
        begin
          FState := lsScriptEscapedStartDash;
          EmitChar(Ord('-'), Token);
          Exit;
        end
        else
        begin
          FReconsume := True;
          FState := lsScript;
        end;
      end;

      lsScriptEscapedStartDash:
      begin
        if C = Ord('-') then
        begin
          FState := lsScriptEscapedDashDash;
          EmitChar(Ord('-'), Token);
          Exit;
        end
        else
        begin
          FReconsume := True;
          FState := lsScript;
        end;
      end;

      lsScriptEscaped:
      begin
        case C of
          Ord('-'):
          begin
            FState := lsScriptEscapedDash;
            EmitChar(Ord('-'), Token);
            Exit;
          end;
          Ord('<'):
            FState := lsScriptEscapedLt;
          NULL_CHAR:
          begin
            EmitChar(REPLACEMENT_CHAR, Token);
            Exit;
          end;
          EOF_CHAR:
          begin
            EmitEof(Token);
            Exit;
          end;
        else
          EmitChar(C, Token);
          Exit;
        end;
      end;

      lsScriptEscapedDash:
      begin
        case C of
          Ord('-'):
          begin
            FState := lsScriptEscapedDashDash;
            EmitChar(Ord('-'), Token);
            Exit;
          end;
          Ord('<'):
            FState := lsScriptEscapedLt;
          NULL_CHAR:
          begin
            FState := lsScriptEscaped;
            EmitChar(REPLACEMENT_CHAR, Token);
            Exit;
          end;
          EOF_CHAR:
          begin
            EmitEof(Token);
            Exit;
          end;
        else
          FState := lsScriptEscaped;
          EmitChar(C, Token);
          Exit;
        end;
      end;

      lsScriptEscapedDashDash:
      begin
        case C of
          Ord('-'):
          begin
            EmitChar(Ord('-'), Token);
            Exit;
          end;
          Ord('<'):
            FState := lsScriptEscapedLt;
          Ord('>'):
          begin
            FState := lsScript;
            EmitChar(Ord('>'), Token);
            Exit;
          end;
          NULL_CHAR:
          begin
            FState := lsScriptEscaped;
            EmitChar(REPLACEMENT_CHAR, Token);
            Exit;
          end;
          EOF_CHAR:
          begin
            EmitEof(Token);
            Exit;
          end;
        else
          FState := lsScriptEscaped;
          EmitChar(C, Token);
          Exit;
        end;
      end;

      lsScriptEscapedLt:
      begin
        if C = Ord('/') then
        begin
          FTempBuffer := '';
          FState := lsScriptEscapedEndTagOpen;
        end
        else if IsAsciiAlpha(C) then
        begin
          FTempBuffer := '';
          FReconsume := True;
          FState := lsScriptDoubleEscapedStart;
          EmitChar(Ord('<'), Token);
          Exit;
        end
        else
        begin
          FReconsume := True;
          FState := lsScriptEscaped;
          EmitChar(Ord('<'), Token);
          Exit;
        end;
      end;

      lsScriptEscapedEndTagOpen:
      begin
        if IsAsciiAlpha(C) then
        begin
          StartNewTag(False);
          FReconsume := True;
          FState := lsScriptEscapedEndTagName;
        end
        else
        begin
          FReconsume := True;
          FState := lsScriptEscaped;
          EmitChar(Ord('<'), Token);
          Token.Data := '</';
          Exit;
        end;
      end;

      lsScriptEscapedEndTagName:
      begin
        if (IsHtmlWhitespace(C) or (C = Ord('/')) or (C = Ord('>'))) and IsAppropriateEndTag then
        begin
          if C = Ord('>') then
          begin
            FState := lsData;
            EmitTag(Token);
            Exit;
          end
          else if C = Ord('/') then
            FState := lsSelfClosingStartTag
          else
            FState := lsBeforeAttrName;
        end
        else if IsAsciiAlpha(C) then
        begin
          AppendUtf8Char(FTagName, ToLower(C));
          AppendUtf8Char(FTempBuffer, C);
        end
        else
        begin
          FState := lsScriptEscaped;
          TempStr := '</' + FTempBuffer;
          FReconsume := True;
          EmitChar(Ord('<'), Token);
          Token.Data := TempStr;
          Exit;
        end;
      end;

      lsScriptDoubleEscapedStart:
      begin
        if IsHtmlWhitespace(C) or (C = Ord('/')) or (C = Ord('>')) then
        begin
          if LowerStr(FTempBuffer) = 'script' then
            FState := lsScriptDoubleEscaped
          else
            FState := lsScriptEscaped;
          EmitChar(C, Token);
          Exit;
        end
        else if IsAsciiAlpha(C) then
        begin
          AppendUtf8Char(FTempBuffer, C);
          EmitChar(C, Token);
          Exit;
        end
        else
        begin
          FReconsume := True;
          FState := lsScriptEscaped;
        end;
      end;

      lsScriptDoubleEscaped:
      begin
        case C of
          Ord('-'):
          begin
            FState := lsScriptDoubleEscapedDash;
            EmitChar(Ord('-'), Token);
            Exit;
          end;
          Ord('<'):
          begin
            FState := lsScriptDoubleEscapedLt;
            EmitChar(Ord('<'), Token);
            Exit;
          end;
          NULL_CHAR:
          begin
            EmitChar(REPLACEMENT_CHAR, Token);
            Exit;
          end;
          EOF_CHAR:
          begin
            EmitEof(Token);
            Exit;
          end;
        else
          EmitChar(C, Token);
          Exit;
        end;
      end;

      lsScriptDoubleEscapedDash:
      begin
        case C of
          Ord('-'):
          begin
            FState := lsScriptDoubleEscapedDashDash;
            EmitChar(Ord('-'), Token);
            Exit;
          end;
          Ord('<'):
          begin
            FState := lsScriptDoubleEscapedLt;
            EmitChar(Ord('<'), Token);
            Exit;
          end;
          NULL_CHAR:
          begin
            FState := lsScriptDoubleEscaped;
            EmitChar(REPLACEMENT_CHAR, Token);
            Exit;
          end;
          EOF_CHAR:
          begin
            EmitEof(Token);
            Exit;
          end;
        else
          FState := lsScriptDoubleEscaped;
          EmitChar(C, Token);
          Exit;
        end;
      end;

      lsScriptDoubleEscapedDashDash:
      begin
        case C of
          Ord('-'):
          begin
            EmitChar(Ord('-'), Token);
            Exit;
          end;
          Ord('<'):
          begin
            FState := lsScriptDoubleEscapedLt;
            EmitChar(Ord('<'), Token);
            Exit;
          end;
          Ord('>'):
          begin
            FState := lsScript;
            EmitChar(Ord('>'), Token);
            Exit;
          end;
          NULL_CHAR:
          begin
            FState := lsScriptDoubleEscaped;
            EmitChar(REPLACEMENT_CHAR, Token);
            Exit;
          end;
          EOF_CHAR:
          begin
            EmitEof(Token);
            Exit;
          end;
        else
          FState := lsScriptDoubleEscaped;
          EmitChar(C, Token);
          Exit;
        end;
      end;

      lsScriptDoubleEscapedLt:
      begin
        if C = Ord('/') then
        begin
          FTempBuffer := '';
          FState := lsScriptDoubleEscapedEnd;
          EmitChar(Ord('/'), Token);
          Exit;
        end
        else
        begin
          FReconsume := True;
          FState := lsScriptDoubleEscaped;
        end;
      end;

      lsScriptDoubleEscapedEnd:
      begin
        if IsHtmlWhitespace(C) or (C = Ord('/')) or (C = Ord('>')) then
        begin
          if LowerStr(FTempBuffer) = 'script' then
            FState := lsScriptEscaped
          else
            FState := lsScriptDoubleEscaped;
          EmitChar(C, Token);
          Exit;
        end
        else if IsAsciiAlpha(C) then
        begin
          AppendUtf8Char(FTempBuffer, C);
          EmitChar(C, Token);
          Exit;
        end
        else
        begin
          FReconsume := True;
          FState := lsScriptDoubleEscaped;
        end;
      end;

      // =====================================================================
      // PLAINTEXT STATE
      // =====================================================================
      lsPlaintext:
      begin
        case C of
          NULL_CHAR:
          begin
            EmitChar(REPLACEMENT_CHAR, Token);
            Exit;
          end;
          EOF_CHAR:
          begin
            EmitEof(Token);
            Exit;
          end;
        else
          EmitChar(C, Token);
          Exit;
        end;
      end;
    end; // case FState
  end; // while True
end;


// =========================================================================
// TPixieTreeBuilder
// =========================================================================

constructor TPixieTreeBuilder.Create(const AInput: string);
begin
  inherited Create;
  FTokenizer := TPixieTokenizer.Create(AInput);
  FDocument := TPixieHtmlNode.Create(hntDocument);
  FMode := imInitial;
  FOriginalMode := imInitial;
  FOpenElements := TPixieHtmlNodeList.Create;
  FActiveFormatting := TPixieHtmlNodeList.Create;
  FTemplateInsertionModes := TPixieInsertionModeStack.Create;
  FHeadElement := nil;
  FFormElement := nil;
  FFragmentContext := nil;
  FReprocess := False;
  FFramesetOk := True;
  FIgnoreNextLf := False;
  FFosterParenting := False;
  FTextBuffer := TStringBuilder.Create;
  FTextBufferType := hntWhitespace;
end;

destructor TPixieTreeBuilder.Destroy;
begin
  FTokenizer.Free;
  FOpenElements.Free;
  FActiveFormatting.Free;
  FTemplateInsertionModes.Free;
  FTextBuffer.Free;
  // FDocument is returned to caller; don't free here
  inherited;
end;

// ---- Stack operations ----

function TPixieTreeBuilder.CurrentNode: TPixieHtmlNode;
begin
  if FOpenElements.Count > 0 then
    Result := FOpenElements[FOpenElements.Count - 1]
  else
    Result := nil;
end;

function TPixieTreeBuilder.AdjustedCurrentNode: TPixieHtmlNode;
begin
  if (FFragmentContext <> nil) and (FOpenElements.Count = 1) then
    Result := FFragmentContext
  else
    Result := CurrentNode;
end;

procedure TPixieTreeBuilder.PopCurrentNode;
begin
  if FOpenElements.Count > 0 then
    FOpenElements.Delete(FOpenElements.Count - 1);
end;

procedure TPixieTreeBuilder.PopUntil(const Tag: string);
begin
  while FOpenElements.Count > 0 do
  begin
    if CurrentNode.Tag = Tag then
    begin
      PopCurrentNode;
      Break;
    end;
    PopCurrentNode;
  end;
end;

procedure TPixieTreeBuilder.PopUntilOneOf(const Tags: array of string);
begin
  while FOpenElements.Count > 0 do
  begin
    if TagIn(CurrentNode.Tag, Tags) then
      Break;
    PopCurrentNode;
  end;
end;

// ---- Active formatting ----

function TPixieTreeBuilder.IsFormattingMarker(Node: TPixieHtmlNode): Boolean;
begin
  Result := Node = FormattingScopeMarker;
end;

function TPixieTreeBuilder.NodeInActiveFormatting(Node: TPixieHtmlNode): Integer;
var
  I: Integer;
begin
  for I := FActiveFormatting.Count - 1 downto 0 do
    if FActiveFormatting[I] = Node then
      Exit(I);
  Result := -1;
end;

procedure TPixieTreeBuilder.AddFormattingMarker;
begin
  FActiveFormatting.Add(FormattingScopeMarker);
end;

procedure TPixieTreeBuilder.AddFormattingElement(Node: TPixieHtmlNode);

  function AllAttributesMatch(A, B: TPixieHtmlNode): Boolean;
  var
    J, K: Integer;
    Found: Boolean;
  begin
    if A.Attributes.Count <> B.Attributes.Count then
      Exit(False);
    for J := 0 to A.Attributes.Count - 1 do
    begin
      Found := False;
      for K := 0 to B.Attributes.Count - 1 do
        if (A.Attributes[J].Name = B.Attributes[K].Name) and
           (A.Attributes[J].Value = B.Attributes[K].Value) then
        begin
          Found := True;
          Break;
        end;
      if not Found then
        Exit(False);
    end;
    Result := True;
  end;

var
  I, Count, Earliest: Integer;
begin
  // Noah's Ark clause: if there are already 3 identical elements
  // after the last scope marker, remove the earliest
  Count := 0;
  Earliest := -1;
  for I := FActiveFormatting.Count - 1 downto 0 do
  begin
    if IsFormattingMarker(FActiveFormatting[I]) then
      Break;
    if (FActiveFormatting[I].Tag = Node.Tag) and
       (FActiveFormatting[I].Namespace = Node.Namespace) and
       AllAttributesMatch(FActiveFormatting[I], Node) then
    begin
      Inc(Count);
      Earliest := I;
    end;
  end;
  if Count >= 3 then
    FActiveFormatting.Delete(Earliest);
  FActiveFormatting.Add(Node);
end;

procedure TPixieTreeBuilder.ReconstructActiveFormatting;
var
  I: Integer;
  Entry, NewNode: TPixieHtmlNode;
begin
  if FActiveFormatting.Count = 0 then
    Exit;
  I := FActiveFormatting.Count - 1;
  Entry := FActiveFormatting[I];
  if IsFormattingMarker(Entry) or (FOpenElements.IndexOf(Entry) >= 0) then
    Exit;

  // Walk backwards to find scope marker or element in open stack
  while I > 0 do
  begin
    Dec(I);
    Entry := FActiveFormatting[I];
    if IsFormattingMarker(Entry) or (FOpenElements.IndexOf(Entry) >= 0) then
    begin
      Inc(I);
      Break;
    end;
  end;

  // Walk forwards, cloning and inserting
  while I < FActiveFormatting.Count do
  begin
    Entry := FActiveFormatting[I];
    if IsFormattingMarker(Entry) then
    begin
      Inc(I);
      Continue;
    end;
    NewNode := Entry.CloneShallow;
    // Insert into tree
    FlushTextBuffer;
    CurrentNode.AppendChild(NewNode);
    FOpenElements.Add(NewNode);
    FActiveFormatting[I] := NewNode;
    Inc(I);
  end;
end;

procedure TPixieTreeBuilder.ClearFormattingToLastMarker;
begin
  while FActiveFormatting.Count > 0 do
  begin
    if IsFormattingMarker(FActiveFormatting[FActiveFormatting.Count - 1]) then
    begin
      FActiveFormatting.Delete(FActiveFormatting.Count - 1);
      Break;
    end;
    FActiveFormatting.Delete(FActiveFormatting.Count - 1);
  end;
end;

// ---- Scope checking ----

function TPixieTreeBuilder.HasElementInSpecificScope(const Tag: string;
  const ScopeTags: array of string): Boolean;
var
  I: Integer;
  Node: TPixieHtmlNode;
begin
  for I := FOpenElements.Count - 1 downto 0 do
  begin
    Node := FOpenElements[I];
    if Node.Tag = Tag then
      Exit(True);
    if TagIn(Node.Tag, ScopeTags) then
      Exit(False);
  end;
  Result := False;
end;

const
  ScopeBaseTags: array[0..17] of string = (
    'applet', 'caption', 'html', 'table', 'td', 'th',
    'marquee', 'object', 'template',
    'mi', 'mo', 'mn', 'ms', 'mtext', 'annotation-xml',
    'foreignobject', 'desc', 'title'
  );

function TPixieTreeBuilder.HasElementInScope(const Tag: string): Boolean;
begin
  Result := HasElementInSpecificScope(Tag, ScopeBaseTags);
end;

function TPixieTreeBuilder.HasElementInButtonScope(const Tag: string): Boolean;
const
  Tags: array[0..18] of string = (
    'applet', 'caption', 'html', 'table', 'td', 'th',
    'marquee', 'object', 'template',
    'mi', 'mo', 'mn', 'ms', 'mtext', 'annotation-xml',
    'foreignobject', 'desc', 'title',
    'button'
  );
begin
  Result := HasElementInSpecificScope(Tag, Tags);
end;

function TPixieTreeBuilder.HasElementInListScope(const Tag: string): Boolean;
const
  Tags: array[0..19] of string = (
    'applet', 'caption', 'html', 'table', 'td', 'th',
    'marquee', 'object', 'template',
    'mi', 'mo', 'mn', 'ms', 'mtext', 'annotation-xml',
    'foreignobject', 'desc', 'title',
    'ol', 'ul'
  );
begin
  Result := HasElementInSpecificScope(Tag, Tags);
end;

function TPixieTreeBuilder.HasElementInTableScope(const Tag: string): Boolean;
const
  Tags: array[0..2] of string = ('html', 'table', 'template');
begin
  Result := HasElementInSpecificScope(Tag, Tags);
end;

function TPixieTreeBuilder.HasElementInSelectScope(const Tag: string): Boolean;
var
  I: Integer;
  Node: TPixieHtmlNode;
begin
  // Select scope is inverted: everything EXCEPT optgroup/option is a boundary
  for I := FOpenElements.Count - 1 downto 0 do
  begin
    Node := FOpenElements[I];
    if Node.Tag = Tag then
      Exit(True);
    if (Node.Tag <> 'optgroup') and (Node.Tag <> 'option') then
      Exit(False);
  end;
  Result := False;
end;

// ---- Implied end tags ----

procedure TPixieTreeBuilder.GenerateImpliedEndTags(const Except_: string);
const
  ImpliedTags: array[0..9] of string = (
    'dd', 'dt', 'li', 'optgroup', 'option', 'p', 'rb', 'rp', 'rt', 'rtc'
  );
begin
  while (FOpenElements.Count > 0) and TagIn(CurrentNode.Tag, ImpliedTags) and
        (CurrentNode.Tag <> Except_) do
    PopCurrentNode;
end;

procedure TPixieTreeBuilder.GenerateAllImpliedEndTags;
const
  Tags: array[0..17] of string = (
    'caption', 'colgroup', 'dd', 'dt', 'head', 'li', 'optgroup', 'option',
    'p', 'rb', 'rp', 'rt', 'rtc', 'tbody', 'td', 'tfoot', 'th', 'tr'
  );
begin
  while (FOpenElements.Count > 0) and TagIn(CurrentNode.Tag, Tags) do
    PopCurrentNode;
end;

// ---- Node creation ----

function TPixieTreeBuilder.CreateElement(const Tag: string; Ns: TPixieHtmlNamespace): TPixieHtmlNode;
begin
  Result := TPixieHtmlNode.Create(hntElement);
  Result.Tag := Tag;
  Result.Namespace := Ns;
end;

function TPixieTreeBuilder.CreateElementFromToken(var Token: TPixieToken;
  Ns: TPixieHtmlNamespace): TPixieHtmlNode;
var
  I: Integer;
begin
  Result := TPixieHtmlNode.Create(hntElement);
  Result.Tag := Token.Name;
  Result.Namespace := Ns;
  if Token.Attrs <> nil then
  begin
    for I := 0 to Token.Attrs.Count - 1 do
      Result.Attributes.Add(Token.Attrs[I]);
  end;
end;

function TPixieTreeBuilder.GetFosterParent(out InsertBefore: TPixieHtmlNode): TPixieHtmlNode;
var
  I, LastTable, LastTemplate: Integer;
begin
  InsertBefore := nil;
  LastTable := -1;
  LastTemplate := -1;
  for I := FOpenElements.Count - 1 downto 0 do
  begin
    if (FOpenElements[I].Tag = 'table') and (LastTable < 0) then
      LastTable := I;
    if (FOpenElements[I].Tag = 'template') and (LastTemplate < 0) then
      LastTemplate := I;
  end;

  if (LastTemplate >= 0) and ((LastTable < 0) or (LastTemplate > LastTable)) then
  begin
    Result := FOpenElements[LastTemplate];
    Exit;
  end;

  if LastTable >= 0 then
  begin
    if FOpenElements[LastTable].Parent <> nil then
    begin
      Result := FOpenElements[LastTable].Parent;
      InsertBefore := FOpenElements[LastTable];
    end
    else
    begin
      // Table has no parent (shouldn't happen normally), use element before table
      Result := FOpenElements[LastTable - 1];
    end;
    Exit;
  end;

  Result := FOpenElements[0]; // html element
end;

function TPixieTreeBuilder.InsertElement(var Token: TPixieToken;
  Ns: TPixieHtmlNamespace): TPixieHtmlNode;
var
  FosterTarget, InsertBefore: TPixieHtmlNode;
begin
  FlushTextBuffer;
  Result := CreateElementFromToken(Token, Ns);
  if FFosterParenting and TagIn(CurrentNode.Tag, ['table', 'tbody', 'tfoot', 'thead', 'tr']) then
  begin
    FosterTarget := GetFosterParent(InsertBefore);
    if InsertBefore <> nil then
      FosterTarget.InsertChildBefore(Result, InsertBefore)
    else
      FosterTarget.AppendChild(Result);
  end
  else
    CurrentNode.AppendChild(Result);
  FOpenElements.Add(Result);
end;

function TPixieTreeBuilder.InsertElementNamed(const Tag: string;
  Ns: TPixieHtmlNamespace): TPixieHtmlNode;
var
  Token: TPixieToken;
begin
  Token := Default(TPixieToken);
  Token.TokenType := ttStartTag;
  Token.Name := Tag;
  Token.Attrs := TPixieHtmlAttributeList.Create;
  Result := InsertElement(Token, Ns);
  Token.Attrs.Free;
end;

procedure TPixieTreeBuilder.InsertCharacter(C: Integer);
var
  S: string;
begin
  S := '';
  AppendUtf8Char(S, UInt32(C));
  InsertText(S);
end;

procedure TPixieTreeBuilder.InsertText(const S: string);
begin
  if S = '' then
    Exit;
  // Check if this is whitespace or text
  if FTextBufferType = hntWhitespace then
  begin
    // If we see a non-whitespace char, upgrade to text
    if not IsHtmlWhitespace(Ord(S[1])) then
      FTextBufferType := hntText;
  end;
  FTextBuffer.Append(S);
end;

procedure TPixieTreeBuilder.FlushTextBuffer;
var
  Node, Target, FosterTarget, InsertBefore, LastChild: TPixieHtmlNode;
  I: Integer;
  AllWhitespace: Boolean;
  Buffered: string;
begin
  if FTextBuffer.Length = 0 then
    Exit;

  // Determine target parent and insertion point
  InsertBefore := nil;
  if FOpenElements.Count = 0 then
    Target := FDocument
  else if FFosterParenting and TagIn(CurrentNode.Tag, ['table', 'tbody', 'tfoot', 'thead', 'tr']) then
  begin
    FosterTarget := GetFosterParent(InsertBefore);
    Target := FosterTarget;
  end
  else
    Target := CurrentNode;

  Buffered := FTextBuffer.ToString;

  // Try to merge with last text child of target (if inserting at end)
  if (InsertBefore = nil) and (Target.Children.Count > 0) then
  begin
    LastChild := Target.Children[Target.Children.Count - 1];
    if LastChild.NodeType in [hntText, hntWhitespace] then
    begin
      LastChild.Text := LastChild.Text + Buffered;
      // Upgrade whitespace to text if needed
      if LastChild.NodeType = hntWhitespace then
      begin
        AllWhitespace := True;
        for I := 1 to Length(LastChild.Text) do
          if not IsHtmlWhitespace(Ord(LastChild.Text[I])) then
          begin
            AllWhitespace := False;
            Break;
          end;
        if not AllWhitespace then
          LastChild.NodeType := hntText;
      end;
      FTextBuffer.Clear;
      FTextBufferType := hntWhitespace;
      Exit;
    end;
  end;

  // Determine if all whitespace
  AllWhitespace := True;
  for I := 1 to Length(Buffered) do
    if not IsHtmlWhitespace(Ord(Buffered[I])) then
    begin
      AllWhitespace := False;
      Break;
    end;

  if AllWhitespace then
    Node := TPixieHtmlNode.Create(hntWhitespace)
  else
    Node := TPixieHtmlNode.Create(hntText);
  Node.Text := Buffered;
  FTextBuffer.Clear;
  FTextBufferType := hntWhitespace;

  if InsertBefore <> nil then
    Target.InsertChildBefore(Node, InsertBefore)
  else
    Target.AppendChild(Node);
end;

procedure TPixieTreeBuilder.InsertComment(const Data: string);
var
  Node: TPixieHtmlNode;
begin
  FlushTextBuffer;
  Node := TPixieHtmlNode.Create(hntComment);
  Node.Text := Data;
  if FOpenElements.Count > 0 then
    CurrentNode.AppendChild(Node)
  else
    FDocument.AppendChild(Node);
end;

// ---- Tag classification ----

function TPixieTreeBuilder.IsSpecialTag(const Tag: string): Boolean;
begin
  Result := TagIn(Tag, [
    'address', 'applet', 'area', 'article', 'aside', 'base', 'basefont',
    'bgsound', 'blockquote', 'body', 'br', 'button', 'caption', 'center',
    'col', 'colgroup', 'dd', 'details', 'dir', 'div', 'dl', 'dt', 'embed',
    'fieldset', 'figcaption', 'figure', 'footer', 'form', 'frame', 'frameset',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'head', 'header', 'hgroup', 'hr',
    'html', 'iframe', 'img', 'input', 'keygen', 'li', 'link', 'listing',
    'main', 'marquee', 'menu', 'meta', 'nav', 'noembed', 'noframes',
    'noscript', 'object', 'ol', 'p', 'param', 'plaintext', 'pre', 'script',
    'search', 'section', 'select', 'source', 'style', 'summary', 'table',
    'tbody', 'td', 'template', 'textarea', 'tfoot', 'th', 'thead', 'title',
    'tr', 'track', 'ul', 'wbr', 'xmp',
    'mi', 'mo', 'mn', 'ms', 'mtext', 'annotation-xml',
    'foreignobject', 'desc'
  ]);
end;

function TPixieTreeBuilder.IsFormattingTag(const Tag: string): Boolean;
begin
  Result := TagIn(Tag, [
    'a', 'b', 'big', 'code', 'em', 'font', 'i', 'nobr',
    's', 'small', 'strike', 'strong', 'tt', 'u'
  ]);
end;

function TPixieTreeBuilder.IsHeadingTag(const Tag: string): Boolean;
begin
  Result := TagIn(Tag, ['h1', 'h2', 'h3', 'h4', 'h5', 'h6']);
end;

// ---- Adoption agency ----

procedure TPixieTreeBuilder.AdoptionAgency(const Tag: string);
var
  OuterLoop, InnerLoop: Integer;
  FormattingIdx, StackIdx, FurthestIdx: Integer;
  FormattingNode, FurthestBlock, CommonAncestor: TPixieHtmlNode;
  Node, LastNode, NewNode: TPixieHtmlNode;
  NodeIdx, BookmarkIdx: Integer;
  I: Integer;
begin
  // Step 1: If current node is the subject tag and not in active formatting
  if (CurrentNode <> nil) and (CurrentNode.Tag = Tag) and
     (NodeInActiveFormatting(CurrentNode) < 0) then
  begin
    PopCurrentNode;
    Exit;
  end;

  for OuterLoop := 0 to 7 do
  begin
    // Step 4-5: Find formatting element in active formatting (backwards)
    FormattingIdx := -1;
    for I := FActiveFormatting.Count - 1 downto 0 do
    begin
      if IsFormattingMarker(FActiveFormatting[I]) then
        Break;
      if FActiveFormatting[I].Tag = Tag then
      begin
        FormattingIdx := I;
        Break;
      end;
    end;

    if FormattingIdx < 0 then
      Exit; // Not found, use "any other end tag" logic

    FormattingNode := FActiveFormatting[FormattingIdx];

    // Step 6: Check if in open elements stack
    StackIdx := FOpenElements.IndexOf(FormattingNode);
    if StackIdx < 0 then
    begin
      FActiveFormatting.Delete(FormattingIdx);
      Exit;
    end;

    // Step 7: Check if in scope
    if not HasElementInScope(Tag) then
      Exit;

    // Step 9: Find furthest block (first special after formatting in stack)
    FurthestIdx := -1;
    for I := StackIdx + 1 to FOpenElements.Count - 1 do
      if IsSpecialTag(FOpenElements[I].Tag) then
      begin
        FurthestIdx := I;
        Break;
      end;

    // Step 10: If no furthest block
    if FurthestIdx < 0 then
    begin
      // Pop up to and including formatting element
      while FOpenElements.Count > StackIdx do
        PopCurrentNode;
      FActiveFormatting.Delete(FormattingIdx);
      Exit;
    end;

    FurthestBlock := FOpenElements[FurthestIdx];
    CommonAncestor := FOpenElements[StackIdx - 1];

    // Step 12: Bookmark
    BookmarkIdx := FormattingIdx;

    // Step 13: Inner loop
    LastNode := FurthestBlock;
    NodeIdx := FurthestIdx;
    for InnerLoop := 1 to High(Integer) do
    begin
      Dec(NodeIdx);
      if NodeIdx < 0 then
        Break;
      Node := FOpenElements[NodeIdx];

      // Step 13.4: If node is the formatting element, break
      if Node = FormattingNode then
        Break;

      // Step 13.5: If inner loop > 3 and node in active formatting, remove
      I := NodeInActiveFormatting(Node);
      if (InnerLoop > 3) and (I >= 0) then
      begin
        FActiveFormatting.Delete(I);
        if I < BookmarkIdx then
          Dec(BookmarkIdx);
        if I < FormattingIdx then
          Dec(FormattingIdx);
        Continue;
      end;

      // Step 13.6: If node not in active formatting, remove from open elements
      if I < 0 then
      begin
        FOpenElements.Delete(NodeIdx);
        if NodeIdx < FurthestIdx then
          Dec(FurthestIdx);
        Continue;
      end;

      // Step 13.7: Clone node, replace in active formatting and open elements
      NewNode := Node.CloneShallow;
      FActiveFormatting[I] := NewNode;
      FOpenElements[NodeIdx] := NewNode;

      // Reparent: move node's children to newNode
      NewNode.AdoptAllChildrenFrom(Node);

      // Replace in parent
      if Node.Parent <> nil then
      begin
        Node.Parent.Children[Node.Parent.Children.IndexOf(Node)] := NewNode;
        NewNode.Parent := Node.Parent;
        Node.Parent := nil;
      end;

      // Step 13.8
      if LastNode = FurthestBlock then
        BookmarkIdx := I + 1;

      // Step 13.9: Move lastNode under newNode
      if LastNode.Parent <> nil then
        LastNode.Parent.RemoveChild(LastNode);
      NewNode.AppendChild(LastNode);

      LastNode := NewNode;
    end;

    // Step 14: Insert lastNode into common ancestor
    if LastNode.Parent <> nil then
      LastNode.Parent.RemoveChild(LastNode);
    CommonAncestor.AppendChild(LastNode);

    // Step 15: Clone formatting element
    NewNode := FormattingNode.CloneShallow;

    // Step 16: Move furthest block's children into clone
    NewNode.AdoptAllChildrenFrom(FurthestBlock);

    // Step 17: Append clone to furthest block
    FurthestBlock.AppendChild(NewNode);

    // Step 18: Remove formatting from active formatting, insert clone at bookmark
    I := NodeInActiveFormatting(FormattingNode);
    if I >= 0 then
    begin
      FActiveFormatting.Delete(I);
      if I < BookmarkIdx then
        Dec(BookmarkIdx);
    end;
    if BookmarkIdx > FActiveFormatting.Count then
      BookmarkIdx := FActiveFormatting.Count;
    FActiveFormatting.Insert(BookmarkIdx, NewNode);

    // Step 19: Remove formatting from open elements, insert clone after furthest block
    I := FOpenElements.IndexOf(FormattingNode);
    if I >= 0 then
      FOpenElements.Delete(I);
    I := FOpenElements.IndexOf(FurthestBlock);
    if I >= 0 then
      FOpenElements.Insert(I + 1, NewNode)
    else
      FOpenElements.Add(NewNode);
  end;
end;

// ---- Close helpers ----

procedure TPixieTreeBuilder.ClosePElement;
begin
  GenerateImpliedEndTags('p');
  PopUntil('p');
end;

procedure TPixieTreeBuilder.CloseCell;
begin
  if HasElementInTableScope('td') then
  begin
    GenerateImpliedEndTags;
    PopUntil('td');
    ClearFormattingToLastMarker;
    FMode := imInRow;
  end
  else if HasElementInTableScope('th') then
  begin
    GenerateImpliedEndTags;
    PopUntil('th');
    ClearFormattingToLastMarker;
    FMode := imInRow;
  end;
end;

// ---- Quirks mode ----

function TPixieTreeBuilder.ComputeQuirksMode(const Name, PubId, SysId: string;
  ForceQuirks, HasSysId: Boolean): TPixieHtmlQuirksMode;
var
  LPub: string;

  function StartsWith(const S, Prefix: string): Boolean;
  begin
    if (Length(S) >= Length(Prefix)) and (Prefix <> '') then
      Result := StrLComp(PChar(Prefix), PChar(S), Length(Prefix)) = 0
    else
      Result := (Prefix = '');
  end;

begin
  if ForceQuirks then
    Exit(hqQuirks);
  if LowerStr(Name) <> 'html' then
    Exit(hqQuirks);

  LPub := LowerStr(PubId);

  // Quirks mode public ID prefixes
  if StartsWith(LPub, '+//silmaril//dtd html pro v0r11 19970101//') or
     StartsWith(LPub, '-//advasoft ltd//dtd html 3.0 aswedit + extensions//') or
     StartsWith(LPub, '-//as//dtd html 3.0 aswedit + extensions//') or
     StartsWith(LPub, '-//ietf//dtd html 2.0') or
     StartsWith(LPub, '-//ietf//dtd html 3.') or
     StartsWith(LPub, '-//ietf//dtd html level') or
     StartsWith(LPub, '-//ietf//dtd html strict') or
     StartsWith(LPub, '-//ietf//dtd html//') or
     StartsWith(LPub, '-//metrius//dtd metrius presentational//') or
     StartsWith(LPub, '-//microsoft//dtd internet explorer') or
     StartsWith(LPub, '-//netscape comm. corp.//dtd') or
     StartsWith(LPub, '-//o''reilly and associates//dtd html') or
     StartsWith(LPub, '-//softquad software//dtd hotmetal pro') or
     StartsWith(LPub, '-//softquad//dtd hotmetal pro') or
     StartsWith(LPub, '-//spyglass//dtd html 2.0 extended//') or
     StartsWith(LPub, '-//sq//dtd html 2.0 hotmetal + extensions//') or
     StartsWith(LPub, '-//sun microsystems corp.//dtd hotjava') or
     StartsWith(LPub, '-//w3c//dtd html 3 1995-03-24//') or
     StartsWith(LPub, '-//w3c//dtd html 3.2 draft//') or
     StartsWith(LPub, '-//w3c//dtd html 3.2 final//') or
     StartsWith(LPub, '-//w3c//dtd html 3.2//') or
     StartsWith(LPub, '-//w3c//dtd html 3.2s draft//') or
     StartsWith(LPub, '-//w3c//dtd html 4.0 frameset//') or
     StartsWith(LPub, '-//w3c//dtd html 4.0 transitional//') or
     StartsWith(LPub, '-//w3c//dtd html experimental 19960712//') or
     StartsWith(LPub, '-//w3c//dtd html experimental 970421//') or
     StartsWith(LPub, '-//w3c//dtd w3 html//') or
     StartsWith(LPub, '-//w3o//dtd w3 html 3.0//') or
     StartsWith(LPub, '-//webtechs//dtd mozilla html') then
    Exit(hqQuirks);

  // Exact match quirks
  if (LPub = '-//w3o//dtd w3 html strict 3.0//en//') or
     (LPub = '-/w3c/dtd html 4.0 transitional/en') or
     (LPub = 'html') then
    Exit(hqQuirks);

  if LowerStr(SysId) = 'http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd' then
    Exit(hqQuirks);

  // Limited quirks
  if StartsWith(LPub, '-//w3c//dtd xhtml 1.0 frameset//') or
     StartsWith(LPub, '-//w3c//dtd xhtml 1.0 transitional//') then
    Exit(hqLimitedQuirks);

  // Requires system ID for limited quirks vs quirks
  if StartsWith(LPub, '-//w3c//dtd html 4.01 frameset//') or
     StartsWith(LPub, '-//w3c//dtd html 4.01 transitional//') then
  begin
    if HasSysId then
      Exit(hqLimitedQuirks)
    else
      Exit(hqQuirks);
  end;

  Result := hqNoQuirks;
end;

// ---- Foreign content ----

function TPixieTreeBuilder.IsMathMlIntegrationPoint(Node: TPixieHtmlNode): Boolean;
begin
  Result := (Node.Namespace = hnsMathMl) and
            TagIn(Node.Tag, ['mi', 'mo', 'mn', 'ms', 'mtext']);
end;

function TPixieTreeBuilder.IsSvgIntegrationPoint(Node: TPixieHtmlNode): Boolean;
var
  Enc: string;
begin
  // SVG foreignObject, desc, title are HTML integration points
  if (Node.Namespace = hnsSvg) and
     TagIn(Node.Tag, ['foreignobject', 'desc', 'title']) then
    Exit(True);
  // MathML annotation-xml with encoding="text/html" or "application/xhtml+xml"
  if (Node.Namespace = hnsMathMl) and (Node.Tag = 'annotation-xml') then
  begin
    Enc := LowerStr(Node.GetAttribute('encoding'));
    if (Enc = 'text/html') or (Enc = 'application/xhtml+xml') then
      Exit(True);
  end;
  Result := False;
end;

procedure TPixieTreeBuilder.AdjustSvgAttributes(Attrs: TPixieHtmlAttributeList);
type
  TReplacement = record F, T: string; end;
const
  Replacements: array[0..53] of TReplacement = (
    (F: 'attributename'; T: 'attributeName'),
    (F: 'attributetype'; T: 'attributeType'),
    (F: 'basefrequency'; T: 'baseFrequency'),
    (F: 'baseprofile'; T: 'baseProfile'),
    (F: 'calcmode'; T: 'calcMode'),
    (F: 'clippathunits'; T: 'clipPathUnits'),
    (F: 'diffuseconstant'; T: 'diffuseConstant'),
    (F: 'edgemode'; T: 'edgeMode'),
    (F: 'filterunits'; T: 'filterUnits'),
    (F: 'glyphref'; T: 'glyphRef'),
    (F: 'gradienttransform'; T: 'gradientTransform'),
    (F: 'gradientunits'; T: 'gradientUnits'),
    (F: 'kernelmatrix'; T: 'kernelMatrix'),
    (F: 'kernelunitlength'; T: 'kernelUnitLength'),
    (F: 'keypoints'; T: 'keyPoints'),
    (F: 'keysplines'; T: 'keySplines'),
    (F: 'keytimes'; T: 'keyTimes'),
    (F: 'lengthadjust'; T: 'lengthAdjust'),
    (F: 'limitingconeangle'; T: 'limitingConeAngle'),
    (F: 'markerheight'; T: 'markerHeight'),
    (F: 'markerunits'; T: 'markerUnits'),
    (F: 'markerwidth'; T: 'markerWidth'),
    (F: 'maskcontentunits'; T: 'maskContentUnits'),
    (F: 'maskunits'; T: 'maskUnits'),
    (F: 'numoctaves'; T: 'numOctaves'),
    (F: 'pathlength'; T: 'pathLength'),
    (F: 'patterncontentunits'; T: 'patternContentUnits'),
    (F: 'patterntransform'; T: 'patternTransform'),
    (F: 'patternunits'; T: 'patternUnits'),
    (F: 'pointsatx'; T: 'pointsAtX'),
    (F: 'pointsaty'; T: 'pointsAtY'),
    (F: 'pointsatz'; T: 'pointsAtZ'),
    (F: 'preservealpha'; T: 'preserveAlpha'),
    (F: 'preserveaspectratio'; T: 'preserveAspectRatio'),
    (F: 'primitiveunits'; T: 'primitiveUnits'),
    (F: 'refx'; T: 'refX'),
    (F: 'refy'; T: 'refY'),
    (F: 'repeatcount'; T: 'repeatCount'),
    (F: 'repeatdur'; T: 'repeatDur'),
    (F: 'requiredextensions'; T: 'requiredExtensions'),
    (F: 'requiredfeatures'; T: 'requiredFeatures'),
    (F: 'specularconstant'; T: 'specularConstant'),
    (F: 'specularexponent'; T: 'specularExponent'),
    (F: 'spreadmethod'; T: 'spreadMethod'),
    (F: 'startoffset'; T: 'startOffset'),
    (F: 'stddeviation'; T: 'stdDeviation'),
    (F: 'stitchtiles'; T: 'stitchTiles'),
    (F: 'surfacescale'; T: 'surfaceScale'),
    (F: 'systemlanguage'; T: 'systemLanguage'),
    (F: 'tablevalues'; T: 'tableValues'),
    (F: 'targetx'; T: 'targetX'),
    (F: 'targety'; T: 'targetY'),
    (F: 'textlength'; T: 'textLength'),
    (F: 'viewbox'; T: 'viewBox')
  );
var
  I, J: Integer;
  Attr: TPixieHtmlAttribute;
begin
  if Attrs = nil then
    Exit;
  for I := 0 to Attrs.Count - 1 do
  begin
    Attr := Attrs[I];
    for J := 0 to High(Replacements) do
      if Attr.Name = Replacements[J].F then
      begin
        Attr.Name := Replacements[J].T;
        Attrs[I] := Attr;
        Break;
      end;
  end;
end;

procedure TPixieTreeBuilder.AdjustMathMlAttributes(Attrs: TPixieHtmlAttributeList);
var
  I: Integer;
  Attr: TPixieHtmlAttribute;
begin
  if Attrs = nil then
    Exit;
  for I := 0 to Attrs.Count - 1 do
  begin
    Attr := Attrs[I];
    if Attr.Name = 'definitionurl' then
    begin
      Attr.Name := 'definitionURL';
      Attrs[I] := Attr;
    end;
  end;
end;

procedure TPixieTreeBuilder.AdjustForeignAttributes(Attrs: TPixieHtmlAttributeList);
begin
  // We don't track attribute namespaces.
  // The xlink:/xml:/xmlns: prefixed attributes are kept as-is.
end;

procedure TPixieTreeBuilder.UpdateForeignContext;
var
  Node: TPixieHtmlNode;
begin
  Node := AdjustedCurrentNode;
  if Node <> nil then
    FTokenizer.SetForeignContext(Node.Namespace <> hnsHtml)
  else
    FTokenizer.SetForeignContext(False);
end;

// ---- Reset insertion mode ----

procedure TPixieTreeBuilder.ResetInsertionMode;
var
  I, J: Integer;
  Node: TPixieHtmlNode;
  Last: Boolean;
begin
  for I := FOpenElements.Count - 1 downto 0 do
  begin
    Node := FOpenElements[I];
    Last := (I = 0);
    if Last and (FFragmentContext <> nil) then
      Node := FFragmentContext;

    if Node.Tag = 'select' then
    begin
      // Walk ancestors to determine InSelect vs InSelectInTable
      if not Last then
      begin
        FMode := imInSelect;
        for J := I - 1 downto 0 do
        begin
          if FOpenElements[J].Tag = 'template' then
            Break;
          if FOpenElements[J].Tag = 'table' then
          begin
            FMode := imInSelectInTable;
            Break;
          end;
        end;
      end
      else
        FMode := imInSelect;
    end
    else if TagIn(Node.Tag, ['td', 'th']) and not Last then
      FMode := imInCell
    else if Node.Tag = 'tr' then
      FMode := imInRow
    else if TagIn(Node.Tag, ['tbody', 'thead', 'tfoot']) then
      FMode := imInTableBody
    else if Node.Tag = 'caption' then
      FMode := imInCaption
    else if Node.Tag = 'colgroup' then
      FMode := imInColumnGroup
    else if Node.Tag = 'table' then
      FMode := imInTable
    else if Node.Tag = 'template' then
    begin
      if FTemplateInsertionModes.Count > 0 then
        FMode := FTemplateInsertionModes[FTemplateInsertionModes.Count - 1]
      else
        FMode := imInTemplate;
    end
    else if Node.Tag = 'head' then
    begin
      if Last then
        FMode := imInBody
      else
        FMode := imInHead;
    end
    else if Node.Tag = 'body' then
      FMode := imInBody
    else if Node.Tag = 'frameset' then
      FMode := imInFrameset
    else if Node.Tag = 'html' then
    begin
      if FHeadElement = nil then
        FMode := imBeforeHead
      else
        FMode := imAfterHead;
    end
    else if Last then
    begin
      FMode := imInBody;
      Exit;
    end
    else
      Continue;
    Exit;
  end;
  FMode := imInBody;
end;

// ---- Token dispatch ----

procedure TPixieTreeBuilder.ProcessToken(var Token: TPixieToken);
var
  AdjNode: TPixieHtmlNode;
begin
  // Flush pending text before processing non-character tokens
  if Token.TokenType in [ttStartTag, ttEndTag, ttDoctype, ttEof] then
    FlushTextBuffer;

  // Handle foreign content
  AdjNode := AdjustedCurrentNode;
  if (AdjNode <> nil) and (AdjNode.Namespace <> hnsHtml) then
  begin
    // Check if we should process in foreign content or fall through to HTML
    if Token.TokenType = ttStartTag then
    begin
      // Break out of foreign content for certain HTML tags
      if IsMathMlIntegrationPoint(AdjNode) and
         not TagIn(Token.Name, ['mglyph', 'malignmark']) then
        // Fall through to HTML handler
      else if (AdjNode.Namespace = hnsMathMl) and (AdjNode.Tag = 'annotation-xml') and
              (Token.Name = 'svg') then
        // Fall through to HTML handler
      else if IsSvgIntegrationPoint(AdjNode) then
        // Fall through to HTML handler
      else
      begin
        ProcessInForeignContent(Token);
        Exit;
      end;
    end
    else if (Token.TokenType = ttCharacter) then
    begin
      if IsMathMlIntegrationPoint(AdjNode) or IsSvgIntegrationPoint(AdjNode) then
        // Fall through to HTML handler
      else
      begin
        ProcessInForeignContent(Token);
        Exit;
      end;
    end
    else if Token.TokenType = ttEof then
      // Fall through
    else
    begin
      ProcessInForeignContent(Token);
      Exit;
    end;
  end;

  // HTML insertion mode dispatch
  case FMode of
    imInitial:              HandleInitial(Token);
    imBeforeHtml:           HandleBeforeHtml(Token);
    imBeforeHead:           HandleBeforeHead(Token);
    imInHead:               HandleInHead(Token);
    imInHeadNoscript:       HandleInHeadNoscript(Token);
    imAfterHead:            HandleAfterHead(Token);
    imInBody:               HandleInBody(Token);
    imText:                 HandleText(Token);
    imInTable:              HandleInTable(Token);
    imInTableText:          HandleInTableText(Token);
    imInCaption:            HandleInCaption(Token);
    imInColumnGroup:        HandleInColumnGroup(Token);
    imInTableBody:          HandleInTableBody(Token);
    imInRow:                HandleInRow(Token);
    imInCell:               HandleInCell(Token);
    imInSelect:             HandleInSelect(Token);
    imInSelectInTable:      HandleInSelectInTable(Token);
    imInTemplate:           HandleInTemplate(Token);
    imAfterBody:            HandleAfterBody(Token);
    imInFrameset:           HandleInFrameset(Token);
    imAfterFrameset:        HandleAfterFrameset(Token);
    imAfterAfterBody:       HandleAfterAfterBody(Token);
    imAfterAfterFrameset:   HandleAfterAfterFrameset(Token);
  end;
end;

// Helper for font tag check in foreign content
function HasFontColorSizeOrFace(var Token: TPixieToken): Boolean;
var
  I: Integer;
begin
  Result := False;
  if Token.Attrs = nil then
    Exit;
  for I := 0 to Token.Attrs.Count - 1 do
    if TagIn(Token.Attrs[I].Name, ['color', 'face', 'size']) then
      Exit(True);
end;

procedure TPixieTreeBuilder.ProcessInForeignContent(var Token: TPixieToken);
var
  Ns: TPixieHtmlNamespace;
  I: Integer;
  Node: TPixieHtmlNode;
begin
  case Token.TokenType of
    ttCharacter:
    begin
      if Token.DataChar = 0 then
        InsertCharacter(REPLACEMENT_CHAR)
      else
        InsertText(Token.Data);
      if (Token.Data <> '') and not IsHtmlWhitespace(Ord(Token.Data[1])) then
        FFramesetOk := False;
    end;
    ttComment:
      InsertComment(Token.Data);
    ttStartTag:
    begin
      // HTML breaking tags: pop foreign elements and reprocess
      if TagIn(Token.Name, [
        'b', 'big', 'blockquote', 'body', 'br', 'center', 'code', 'dd',
        'div', 'dl', 'dt', 'em', 'embed', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
        'head', 'hr', 'i', 'img', 'li', 'listing', 'menu', 'meta', 'nobr',
        'ol', 'p', 'pre', 'ruby', 's', 'small', 'span', 'strong', 'strike',
        'sub', 'sup', 'table', 'tt', 'u', 'ul', 'var']) or
        ((Token.Name = 'font') and
         (Token.Attrs <> nil) and
         (Token.Attrs.Count > 0) and
         (HasFontColorSizeOrFace(Token))) then
      begin
        // Pop until HTML namespace
        while (FOpenElements.Count > 0) and (CurrentNode.Namespace <> hnsHtml) and
              not IsMathMlIntegrationPoint(CurrentNode) and
              not IsSvgIntegrationPoint(CurrentNode) do
          PopCurrentNode;
        FReprocess := True;
        Exit;
      end;

      Ns := AdjustedCurrentNode.Namespace;
      if Ns = hnsMathMl then
        AdjustMathMlAttributes(Token.Attrs)
      else if Ns = hnsSvg then
        AdjustSvgAttributes(Token.Attrs);
      AdjustForeignAttributes(Token.Attrs);
      InsertElement(Token, Ns);
      if Token.SelfClosing then
        PopCurrentNode;
    end;
    ttEndTag:
    begin
      // Walk backwards through open elements per the spec
      if FOpenElements.Count > 0 then
      begin
        I := FOpenElements.Count - 1;
        Node := FOpenElements[I];
        // Step 1: if current node matches case-insensitively, pop and done
        if StrEqI(Node.Tag, Token.Name) then
          PopCurrentNode
        else
        begin
          // Step 2: walk backwards
          while I >= 1 do
          begin
            Dec(I);
            Node := FOpenElements[I];
            if Node.Namespace = hnsHtml then
            begin
              // Process as HTML token
              ProcessToken(Token);
              Exit;
            end;
            if StrEqI(Node.Tag, Token.Name) then
            begin
              // Pop everything above and including this node
              while FOpenElements.Count - 1 >= I do
                PopCurrentNode;
              Break;
            end;
          end;
        end;
      end;
    end;
  end;
  UpdateForeignContext;
end;

// Helper: get attribute value from a token record
function TokenGetAttribute(var Token: TPixieToken; const Name: string): string;
var
  I: Integer;
begin
  Result := '';
  if Token.Attrs = nil then Exit;
  for I := 0 to Token.Attrs.Count - 1 do
    if Token.Attrs[I].Name = Name then
      Exit(Token.Attrs[I].Value);
end;

// =========================================================================
// Insertion Mode Handlers
// =========================================================================

procedure TPixieTreeBuilder.HandleInitial(var Token: TPixieToken);
begin
  case Token.TokenType of
    ttCharacter:
      if IsHtmlWhitespace(Token.DataChar) then
        Exit; // ignore whitespace
    ttComment:
    begin
      FlushTextBuffer;
      InsertComment(Token.Data);
      Exit;
    end;
    ttDoctype:
    begin
      FDocument.QuirksMode := ComputeQuirksMode(
        Token.Name, Token.PublicId, Token.SystemId,
        Token.ForceQuirks, Token.SystemId <> '');
      FMode := imBeforeHtml;
      Exit;
    end;
  end;
  // Anything else: quirks mode, reprocess
  FDocument.QuirksMode := hqQuirks;
  FMode := imBeforeHtml;
  FReprocess := True;
end;

procedure TPixieTreeBuilder.HandleBeforeHtml(var Token: TPixieToken);
var
  El: TPixieHtmlNode;
begin
  case Token.TokenType of
    ttDoctype:
      Exit; // ignore
    ttComment:
    begin
      FlushTextBuffer;
      InsertComment(Token.Data);
      Exit;
    end;
    ttCharacter:
      if IsHtmlWhitespace(Token.DataChar) then
        Exit;
    ttStartTag:
      if Token.Name = 'html' then
      begin
        FlushTextBuffer;
        El := CreateElementFromToken(Token, hnsHtml);
        FDocument.AppendChild(El);
        FOpenElements.Add(El);
        FMode := imBeforeHead;
        UpdateForeignContext;
        Exit;
      end;
    ttEndTag:
      if not TagIn(Token.Name, ['head', 'body', 'html', 'br']) then
        Exit; // ignore
  end;
  // Anything else: create html element, reprocess
  FlushTextBuffer;
  El := CreateElement('html', hnsHtml);
  FDocument.AppendChild(El);
  FOpenElements.Add(El);
  FMode := imBeforeHead;
  FReprocess := True;
  UpdateForeignContext;
end;

procedure TPixieTreeBuilder.HandleBeforeHead(var Token: TPixieToken);
begin
  case Token.TokenType of
    ttCharacter:
      if IsHtmlWhitespace(Token.DataChar) then
        Exit;
    ttComment:
    begin
      InsertComment(Token.Data);
      Exit;
    end;
    ttDoctype:
      Exit;
    ttStartTag:
    begin
      if Token.Name = 'html' then
      begin
        HandleInBody(Token);
        Exit;
      end;
      if Token.Name = 'head' then
      begin
        FHeadElement := InsertElement(Token);
        FMode := imInHead;
        Exit;
      end;
    end;
    ttEndTag:
      if not TagIn(Token.Name, ['head', 'body', 'html', 'br']) then
        Exit;
  end;
  // Insert head, reprocess
  FHeadElement := InsertElementNamed('head');
  FMode := imInHead;
  FReprocess := True;
end;

procedure TPixieTreeBuilder.HandleInHead(var Token: TPixieToken);
begin
  case Token.TokenType of
    ttCharacter:
    begin
      if IsHtmlWhitespace(Token.DataChar) then
      begin
        InsertText(Token.Data);
        Exit;
      end;
    end;
    ttComment:
    begin
      InsertComment(Token.Data);
      Exit;
    end;
    ttDoctype:
      Exit;
    ttStartTag:
    begin
      if Token.Name = 'html' then
      begin
        HandleInBody(Token);
        Exit;
      end;
      if TagIn(Token.Name, ['base', 'basefont', 'bgsound', 'link']) then
      begin
        InsertElement(Token);
        PopCurrentNode;
        Exit;
      end;
      if Token.Name = 'meta' then
      begin
        InsertElement(Token);
        PopCurrentNode;
        Exit;
      end;
      if Token.Name = 'title' then
      begin
        InsertElement(Token);
        FTokenizer.SetState(lsRcdata);
        FOriginalMode := FMode;
        FMode := imText;
        Exit;
      end;
      if TagIn(Token.Name, ['noscript', 'noframes', 'style']) then
      begin
        if Token.Name = 'noscript' then
        begin
          InsertElement(Token);
          FMode := imInHeadNoscript;
          Exit;
        end;
        InsertElement(Token);
        FTokenizer.SetState(lsRawtext);
        FOriginalMode := FMode;
        FMode := imText;
        Exit;
      end;
      if Token.Name = 'script' then
      begin
        InsertElement(Token);
        FTokenizer.SetState(lsScript);
        FOriginalMode := FMode;
        FMode := imText;
        Exit;
      end;
      if Token.Name = 'template' then
      begin
        InsertElement(Token);
        AddFormattingMarker;
        FFramesetOk := False;
        FMode := imInTemplate;
        FTemplateInsertionModes.Add(imInTemplate);
        Exit;
      end;
      if Token.Name = 'head' then
        Exit; // ignore
    end;
    ttEndTag:
    begin
      if Token.Name = 'head' then
      begin
        PopCurrentNode;
        FMode := imAfterHead;
        Exit;
      end;
      if Token.Name = 'template' then
      begin
        if not HasElementInScope('template') then
          Exit;
        GenerateAllImpliedEndTags;
        PopUntil('template');
        ClearFormattingToLastMarker;
        if FTemplateInsertionModes.Count > 0 then
          FTemplateInsertionModes.Delete(FTemplateInsertionModes.Count - 1);
        ResetInsertionMode;
        Exit;
      end;
      if TagIn(Token.Name, ['body', 'html', 'br']) then
      begin
        // Fall through to anything else
      end
      else
        Exit; // ignore
    end;
  end;
  // Anything else: pop head, reprocess in after head
  PopCurrentNode;
  FMode := imAfterHead;
  FReprocess := True;
end;

procedure TPixieTreeBuilder.HandleInHeadNoscript(var Token: TPixieToken);
begin
  case Token.TokenType of
    ttDoctype: Exit;
    ttComment:
    begin
      HandleInHead(Token);
      Exit;
    end;
    ttCharacter:
      if IsHtmlWhitespace(Token.DataChar) then
      begin
        HandleInHead(Token);
        Exit;
      end;
    ttStartTag:
    begin
      if TagIn(Token.Name, ['basefont', 'bgsound', 'link', 'meta', 'noframes', 'style']) then
      begin
        HandleInHead(Token);
        Exit;
      end;
      if TagIn(Token.Name, ['head', 'noscript']) then
        Exit;
    end;
    ttEndTag:
    begin
      if Token.Name = 'noscript' then
      begin
        PopCurrentNode;
        FMode := imInHead;
        Exit;
      end;
      if Token.Name <> 'br' then
        Exit;
    end;
  end;
  // Pop noscript, reprocess
  PopCurrentNode;
  FMode := imInHead;
  FReprocess := True;
end;

procedure TPixieTreeBuilder.HandleAfterHead(var Token: TPixieToken);
begin
  case Token.TokenType of
    ttCharacter:
      if IsHtmlWhitespace(Token.DataChar) then
      begin
        InsertText(Token.Data);
        Exit;
      end;
    ttComment:
    begin
      InsertComment(Token.Data);
      Exit;
    end;
    ttDoctype: Exit;
    ttStartTag:
    begin
      if Token.Name = 'html' then
      begin
        HandleInBody(Token);
        Exit;
      end;
      if Token.Name = 'body' then
      begin
        InsertElement(Token);
        FFramesetOk := False;
        FMode := imInBody;
        Exit;
      end;
      if Token.Name = 'frameset' then
      begin
        InsertElement(Token);
        FMode := imInFrameset;
        Exit;
      end;
      if TagIn(Token.Name, ['base', 'basefont', 'bgsound', 'link', 'meta',
        'noframes', 'script', 'style', 'template', 'title']) then
      begin
        // Push head back, process as in-head, pop head
        FOpenElements.Add(FHeadElement);
        HandleInHead(Token);
        FOpenElements.Remove(FHeadElement);
        Exit;
      end;
      if Token.Name = 'head' then
        Exit;
    end;
    ttEndTag:
    begin
      if Token.Name = 'template' then
      begin
        HandleInHead(Token);
        Exit;
      end;
      if not TagIn(Token.Name, ['body', 'html', 'br']) then
        Exit;
    end;
  end;
  // Insert body, reprocess
  InsertElementNamed('body');
  FMode := imInBody;
  FReprocess := True;
end;

procedure TPixieTreeBuilder.HandleInBody(var Token: TPixieToken);
var
  I: Integer;
  Node: TPixieHtmlNode;
begin
  case Token.TokenType of
    ttCharacter:
    begin
      if Token.DataChar = 0 then
        Exit; // ignore null
      if FIgnoreNextLf and (Token.DataChar = 10) then
      begin
        FIgnoreNextLf := False;
        Exit;
      end;
      FIgnoreNextLf := False;
      ReconstructActiveFormatting;
      InsertText(Token.Data);
      if not IsHtmlWhitespace(Token.DataChar) then
        FFramesetOk := False;
      Exit;
    end;
    ttComment:
    begin
      InsertComment(Token.Data);
      Exit;
    end;
    ttDoctype:
      Exit;
    ttEof:
    begin
      // Flush and finish
      FlushTextBuffer;
      Exit;
    end;
    ttStartTag:
    begin
      FIgnoreNextLf := False;
      if Token.Name = 'html' then
      begin
        // Merge attributes onto existing html element
        if (FOpenElements.Count > 0) and (Token.Attrs <> nil) then
          for I := 0 to Token.Attrs.Count - 1 do
            if not FOpenElements[0].HasAttribute(Token.Attrs[I].Name) then
              FOpenElements[0].Attributes.Add(Token.Attrs[I]);
        Exit;
      end;

      if TagIn(Token.Name, ['base', 'basefont', 'bgsound', 'link', 'meta',
        'noframes', 'script', 'style', 'template', 'title']) then
      begin
        HandleInHead(Token);
        Exit;
      end;

      if Token.Name = 'body' then
      begin
        if (FOpenElements.Count >= 2) and (FOpenElements[1].Tag = 'body') then
        begin
          FFramesetOk := False;
          if Token.Attrs <> nil then
            for I := 0 to Token.Attrs.Count - 1 do
              if not FOpenElements[1].HasAttribute(Token.Attrs[I].Name) then
                FOpenElements[1].Attributes.Add(Token.Attrs[I]);
        end;
        Exit;
      end;

      if Token.Name = 'frameset' then
      begin
        if not FFramesetOk then
          Exit;
        if (FOpenElements.Count >= 2) and (FOpenElements[1].Tag = 'body') then
        begin
          if FOpenElements[1].Parent <> nil then
            FOpenElements[1].Parent.RemoveChild(FOpenElements[1]);
          while FOpenElements.Count > 1 do
            PopCurrentNode;
          InsertElement(Token);
          FMode := imInFrameset;
        end;
        Exit;
      end;

      if TagIn(Token.Name, ['address', 'article', 'aside', 'blockquote',
        'center', 'details', 'dialog', 'dir', 'div', 'dl', 'fieldset',
        'figcaption', 'figure', 'footer', 'header', 'hgroup', 'listing',
        'main', 'menu', 'nav', 'ol', 'p', 'search', 'section', 'summary', 'ul']) then
      begin
        if HasElementInButtonScope('p') then
          ClosePElement;
        InsertElement(Token);
        Exit;
      end;

      if IsHeadingTag(Token.Name) then
      begin
        if HasElementInButtonScope('p') then
          ClosePElement;
        if (CurrentNode <> nil) and IsHeadingTag(CurrentNode.Tag) then
          PopCurrentNode;
        InsertElement(Token);
        Exit;
      end;

      if TagIn(Token.Name, ['pre', 'listing']) then
      begin
        if HasElementInButtonScope('p') then
          ClosePElement;
        InsertElement(Token);
        FIgnoreNextLf := True;
        FFramesetOk := False;
        Exit;
      end;

      if Token.Name = 'form' then
      begin
        if (FFormElement <> nil) and not HasElementInScope('template') then
          Exit;
        if HasElementInButtonScope('p') then
          ClosePElement;
        Node := InsertElement(Token);
        if not HasElementInScope('template') then
          FFormElement := Node;
        Exit;
      end;

      if Token.Name = 'li' then
      begin
        FFramesetOk := False;
        for I := FOpenElements.Count - 1 downto 0 do
        begin
          Node := FOpenElements[I];
          if Node.Tag = 'li' then
          begin
            GenerateImpliedEndTags('li');
            PopUntil('li');
            Break;
          end;
          if IsSpecialTag(Node.Tag) and not TagIn(Node.Tag, ['address', 'div', 'p']) then
            Break;
        end;
        if HasElementInButtonScope('p') then
          ClosePElement;
        InsertElement(Token);
        Exit;
      end;

      if TagIn(Token.Name, ['dd', 'dt']) then
      begin
        FFramesetOk := False;
        for I := FOpenElements.Count - 1 downto 0 do
        begin
          Node := FOpenElements[I];
          if TagIn(Node.Tag, ['dd', 'dt']) then
          begin
            GenerateImpliedEndTags(Node.Tag);
            PopUntil(Node.Tag);
            Break;
          end;
          if IsSpecialTag(Node.Tag) and not TagIn(Node.Tag, ['address', 'div', 'p']) then
            Break;
        end;
        if HasElementInButtonScope('p') then
          ClosePElement;
        InsertElement(Token);
        Exit;
      end;

      if Token.Name = 'plaintext' then
      begin
        if HasElementInButtonScope('p') then
          ClosePElement;
        InsertElement(Token);
        FTokenizer.SetState(lsPlaintext);
        Exit;
      end;

      if Token.Name = 'button' then
      begin
        if HasElementInScope('button') then
        begin
          GenerateImpliedEndTags;
          PopUntil('button');
        end;
        ReconstructActiveFormatting;
        InsertElement(Token);
        FFramesetOk := False;
        Exit;
      end;

      if Token.Name = 'a' then
      begin
        // Check for existing <a> in active formatting
        for I := FActiveFormatting.Count - 1 downto 0 do
        begin
          if IsFormattingMarker(FActiveFormatting[I]) then
            Break;
          if FActiveFormatting[I].Tag = 'a' then
          begin
            Node := FActiveFormatting[I];
            AdoptionAgency('a');
            // Remove from both lists if still present
            FActiveFormatting.Remove(Node);
            FOpenElements.Remove(Node);
            Break;
          end;
        end;
        ReconstructActiveFormatting;
        Node := InsertElement(Token);
        AddFormattingElement(Node);
        Exit;
      end;

      if TagIn(Token.Name, ['b', 'big', 'code', 'em', 'font', 'i', 'nobr',
        's', 'small', 'strike', 'strong', 'tt', 'u']) then
      begin
        if Token.Name = 'nobr' then
        begin
          ReconstructActiveFormatting;
          if HasElementInScope('nobr') then
          begin
            AdoptionAgency('nobr');
            ReconstructActiveFormatting;
          end;
          Node := InsertElement(Token);
          AddFormattingElement(Node);
        end
        else
        begin
          ReconstructActiveFormatting;
          Node := InsertElement(Token);
          AddFormattingElement(Node);
        end;
        Exit;
      end;

      if Token.Name = 'table' then
      begin
        if (FDocument.QuirksMode <> hqQuirks) and HasElementInButtonScope('p') then
          ClosePElement;
        InsertElement(Token);
        FFramesetOk := False;
        FMode := imInTable;
        Exit;
      end;

      if TagIn(Token.Name, ['area', 'br', 'embed', 'img', 'keygen', 'wbr']) then
      begin
        ReconstructActiveFormatting;
        InsertElement(Token);
        PopCurrentNode;
        FFramesetOk := False;
        Exit;
      end;

      if Token.Name = 'input' then
      begin
        ReconstructActiveFormatting;
        InsertElement(Token);
        PopCurrentNode;
        // Only set frameset_ok = false for non-hidden inputs
        if LowerStr(TokenGetAttribute(Token, 'type')) <> 'hidden' then
          FFramesetOk := False;
        Exit;
      end;

      if TagIn(Token.Name, ['param', 'source', 'track']) then
      begin
        InsertElement(Token);
        PopCurrentNode;
        Exit;
      end;

      if Token.Name = 'hr' then
      begin
        if HasElementInButtonScope('p') then
          ClosePElement;
        InsertElement(Token);
        PopCurrentNode;
        FFramesetOk := False;
        Exit;
      end;

      if Token.Name = 'image' then
      begin
        Token.Name := 'img';
        FReprocess := True;
        Exit;
      end;

      if Token.Name = 'textarea' then
      begin
        InsertElement(Token);
        FIgnoreNextLf := True;
        FTokenizer.SetState(lsRcdata);
        FOriginalMode := FMode;
        FFramesetOk := False;
        FMode := imText;
        Exit;
      end;

      if Token.Name = 'xmp' then
      begin
        if HasElementInButtonScope('p') then
          ClosePElement;
        ReconstructActiveFormatting;
        FFramesetOk := False;
        InsertElement(Token);
        FTokenizer.SetState(lsRawtext);
        FOriginalMode := FMode;
        FMode := imText;
        Exit;
      end;

      if Token.Name = 'iframe' then
      begin
        FFramesetOk := False;
        InsertElement(Token);
        FTokenizer.SetState(lsRawtext);
        FOriginalMode := FMode;
        FMode := imText;
        Exit;
      end;

      if TagIn(Token.Name, ['noembed', 'noframes']) then
      begin
        InsertElement(Token);
        FTokenizer.SetState(lsRawtext);
        FOriginalMode := FMode;
        FMode := imText;
        Exit;
      end;

      if Token.Name = 'select' then
      begin
        ReconstructActiveFormatting;
        InsertElement(Token);
        FFramesetOk := False;
        if FMode in [imInTable, imInCaption, imInTableBody, imInRow, imInCell] then
          FMode := imInSelectInTable
        else
          FMode := imInSelect;
        Exit;
      end;

      if TagIn(Token.Name, ['optgroup', 'option']) then
      begin
        if (CurrentNode <> nil) and (CurrentNode.Tag = 'option') then
          PopCurrentNode;
        ReconstructActiveFormatting;
        InsertElement(Token);
        Exit;
      end;

      if TagIn(Token.Name, ['rb', 'rtc']) then
      begin
        if HasElementInScope('ruby') then
          GenerateImpliedEndTags;
        InsertElement(Token);
        Exit;
      end;

      if TagIn(Token.Name, ['rp', 'rt']) then
      begin
        if HasElementInScope('ruby') then
          GenerateImpliedEndTags('rtc');
        InsertElement(Token);
        Exit;
      end;

      if Token.Name = 'math' then
      begin
        ReconstructActiveFormatting;
        AdjustMathMlAttributes(Token.Attrs);
        AdjustForeignAttributes(Token.Attrs);
        InsertElement(Token, hnsMathMl);
        if Token.SelfClosing then
          PopCurrentNode;
        UpdateForeignContext;
        Exit;
      end;

      if Token.Name = 'svg' then
      begin
        ReconstructActiveFormatting;
        AdjustSvgAttributes(Token.Attrs);
        AdjustForeignAttributes(Token.Attrs);
        InsertElement(Token, hnsSvg);
        if Token.SelfClosing then
          PopCurrentNode;
        UpdateForeignContext;
        Exit;
      end;

      if TagIn(Token.Name, ['caption', 'col', 'colgroup', 'frame',
        'head', 'tbody', 'td', 'tfoot', 'th', 'thead', 'tr']) then
        Exit; // ignore

      // Any other start tag
      ReconstructActiveFormatting;
      InsertElement(Token);
      Exit;
    end;

    ttEndTag:
    begin
      FIgnoreNextLf := False;

      if Token.Name = 'template' then
      begin
        HandleInHead(Token);
        Exit;
      end;

      if Token.Name = 'body' then
      begin
        if not HasElementInScope('body') then
          Exit;
        FMode := imAfterBody;
        Exit;
      end;

      if Token.Name = 'html' then
      begin
        if not HasElementInScope('body') then
          Exit;
        FMode := imAfterBody;
        FReprocess := True;
        Exit;
      end;

      if TagIn(Token.Name, ['address', 'article', 'aside', 'blockquote',
        'button', 'center', 'details', 'dialog', 'dir', 'div', 'dl',
        'fieldset', 'figcaption', 'figure', 'footer', 'header', 'hgroup',
        'listing', 'main', 'menu', 'nav', 'ol', 'pre', 'search', 'section',
        'summary', 'ul']) then
      begin
        if not HasElementInScope(Token.Name) then
          Exit;
        GenerateImpliedEndTags;
        PopUntil(Token.Name);
        Exit;
      end;

      if Token.Name = 'form' then
      begin
        if not HasElementInScope('template') then
        begin
          Node := FFormElement;
          FFormElement := nil;
          if (Node = nil) or not HasElementInScope('form') then
            Exit;
          GenerateImpliedEndTags;
          FOpenElements.Remove(Node);
        end
        else
        begin
          if not HasElementInScope('form') then
            Exit;
          GenerateImpliedEndTags;
          PopUntil('form');
        end;
        Exit;
      end;

      if Token.Name = 'p' then
      begin
        if not HasElementInButtonScope('p') then
        begin
          // Create and immediately close a p element
          InsertElementNamed('p');
        end;
        ClosePElement;
        Exit;
      end;

      if Token.Name = 'li' then
      begin
        if not HasElementInListScope('li') then
          Exit;
        GenerateImpliedEndTags('li');
        PopUntil('li');
        Exit;
      end;

      if TagIn(Token.Name, ['dd', 'dt']) then
      begin
        if not HasElementInScope(Token.Name) then
          Exit;
        GenerateImpliedEndTags(Token.Name);
        PopUntil(Token.Name);
        Exit;
      end;

      if IsHeadingTag(Token.Name) then
      begin
        if not (HasElementInScope('h1') or HasElementInScope('h2') or
                HasElementInScope('h3') or HasElementInScope('h4') or
                HasElementInScope('h5') or HasElementInScope('h6')) then
          Exit;
        GenerateImpliedEndTags;
        PopUntilOneOf(['h1', 'h2', 'h3', 'h4', 'h5', 'h6']);
        PopCurrentNode;
        Exit;
      end;

      if IsFormattingTag(Token.Name) then
      begin
        AdoptionAgency(Token.Name);
        Exit;
      end;

      if Token.Name = 'applet' then
      begin
        if not HasElementInScope('applet') then
          Exit;
        GenerateImpliedEndTags;
        PopUntil('applet');
        ClearFormattingToLastMarker;
        Exit;
      end;

      if TagIn(Token.Name, ['marquee', 'object']) then
      begin
        if not HasElementInScope(Token.Name) then
          Exit;
        GenerateImpliedEndTags;
        PopUntil(Token.Name);
        ClearFormattingToLastMarker;
        Exit;
      end;

      if Token.Name = 'br' then
      begin
        // Treat </br> as <br>
        ReconstructActiveFormatting;
        InsertElementNamed('br');
        PopCurrentNode;
        FFramesetOk := False;
        Exit;
      end;

      // Any other end tag
      for I := FOpenElements.Count - 1 downto 0 do
      begin
        Node := FOpenElements[I];
        if Node.Tag = Token.Name then
        begin
          GenerateImpliedEndTags(Token.Name);
          while FOpenElements.Count > 0 do
          begin
            if CurrentNode = Node then
            begin
              PopCurrentNode;
              Break;
            end;
            PopCurrentNode;
          end;
          Break;
        end;
        if IsSpecialTag(Node.Tag) then
          Break; // ignore the end tag
      end;
    end;
  end;
end;

procedure TPixieTreeBuilder.HandleText(var Token: TPixieToken);
begin
  case Token.TokenType of
    ttCharacter:
      InsertText(Token.Data);
    ttEof:
    begin
      FlushTextBuffer;
      PopCurrentNode;
      FMode := FOriginalMode;
      FReprocess := True;
    end;
    ttEndTag:
    begin
      FlushTextBuffer;
      PopCurrentNode;
      FMode := FOriginalMode;
    end;
  end;
end;

procedure TPixieTreeBuilder.HandleInTable(var Token: TPixieToken);
begin
  case Token.TokenType of
    ttCharacter:
    begin
      if TagIn(CurrentNode.Tag, ['table', 'tbody', 'tfoot', 'thead', 'tr']) then
      begin
        FPendingTableChars := '';
        FPendingTableCharsHasNonWs := False;
        FOriginalMode := FMode;
        FMode := imInTableText;
        FReprocess := True;
        Exit;
      end;
    end;
    ttComment:
    begin
      InsertComment(Token.Data);
      Exit;
    end;
    ttDoctype: Exit;
    ttStartTag:
    begin
      if Token.Name = 'caption' then
      begin
        PopUntilOneOf(['table', 'html']);
        AddFormattingMarker;
        InsertElement(Token);
        FMode := imInCaption;
        Exit;
      end;
      if Token.Name = 'colgroup' then
      begin
        PopUntilOneOf(['table', 'html']);
        InsertElement(Token);
        FMode := imInColumnGroup;
        Exit;
      end;
      if Token.Name = 'col' then
      begin
        PopUntilOneOf(['table', 'html']);
        InsertElementNamed('colgroup');
        FMode := imInColumnGroup;
        FReprocess := True;
        Exit;
      end;
      if TagIn(Token.Name, ['tbody', 'tfoot', 'thead']) then
      begin
        PopUntilOneOf(['table', 'html']);
        InsertElement(Token);
        FMode := imInTableBody;
        Exit;
      end;
      if TagIn(Token.Name, ['td', 'th', 'tr']) then
      begin
        PopUntilOneOf(['table', 'html']);
        InsertElementNamed('tbody');
        FMode := imInTableBody;
        FReprocess := True;
        Exit;
      end;
      if Token.Name = 'table' then
      begin
        if not HasElementInTableScope('table') then
          Exit;
        PopUntil('table');
        ResetInsertionMode;
        FReprocess := True;
        Exit;
      end;
      if TagIn(Token.Name, ['style', 'script', 'template']) then
      begin
        HandleInHead(Token);
        Exit;
      end;
      if Token.Name = 'input' then
      begin
        if Token.Attrs <> nil then
        begin
          if LowerStr(TokenGetAttribute(Token, 'type')) = 'hidden' then
          begin
            InsertElement(Token);
            PopCurrentNode;
            Exit;
          end;
        end;
      end;
      if Token.Name = 'form' then
      begin
        if (FFormElement <> nil) or HasElementInScope('template') then
          Exit;
        FFormElement := InsertElement(Token);
        PopCurrentNode;
        Exit;
      end;
    end;
    ttEndTag:
    begin
      if Token.Name = 'table' then
      begin
        if not HasElementInTableScope('table') then
          Exit;
        PopUntil('table');
        ResetInsertionMode;
        Exit;
      end;
      if TagIn(Token.Name, ['body', 'caption', 'col', 'colgroup', 'html',
        'tbody', 'td', 'tfoot', 'th', 'thead', 'tr']) then
        Exit;
      if Token.Name = 'template' then
      begin
        HandleInHead(Token);
        Exit;
      end;
    end;
    ttEof:
    begin
      HandleInBody(Token);
      Exit;
    end;
  end;
  // Anything else: foster parent
  FFosterParenting := True;
  HandleInBody(Token);
  FFosterParenting := False;
end;

procedure TPixieTreeBuilder.HandleInTableText(var Token: TPixieToken);
var
  I: Integer;
begin
  if Token.TokenType = ttCharacter then
  begin
    if Token.DataChar = 0 then
      Exit;
    FPendingTableChars := FPendingTableChars + Token.Data;
    if not IsHtmlWhitespace(Token.DataChar) then
      FPendingTableCharsHasNonWs := True;
    Exit;
  end;
  // Non-character token: flush pending chars
  if FPendingTableChars <> '' then
  begin
    if FPendingTableCharsHasNonWs then
    begin
      // Foster parent the text
      FFosterParenting := True;
      for I := 1 to Length(FPendingTableChars) do
        InsertCharacter(Ord(FPendingTableChars[I]));
      FlushTextBuffer;
      FFosterParenting := False;
    end
    else
      InsertText(FPendingTableChars);
    FPendingTableChars := '';
  end;
  FMode := FOriginalMode;
  FReprocess := True;
end;

procedure TPixieTreeBuilder.HandleInCaption(var Token: TPixieToken);
begin
  case Token.TokenType of
    ttStartTag:
    begin
      if TagIn(Token.Name, ['caption', 'col', 'colgroup', 'tbody', 'td',
        'tfoot', 'th', 'thead', 'tr']) then
      begin
        if not HasElementInTableScope('caption') then
          Exit;
        GenerateImpliedEndTags;
        PopUntil('caption');
        ClearFormattingToLastMarker;
        FMode := imInTable;
        FReprocess := True;
        Exit;
      end;
    end;
    ttEndTag:
    begin
      if Token.Name = 'caption' then
      begin
        if not HasElementInTableScope('caption') then
          Exit;
        GenerateImpliedEndTags;
        PopUntil('caption');
        ClearFormattingToLastMarker;
        FMode := imInTable;
        Exit;
      end;
      if Token.Name = 'table' then
      begin
        if not HasElementInTableScope('caption') then
          Exit;
        GenerateImpliedEndTags;
        PopUntil('caption');
        ClearFormattingToLastMarker;
        FMode := imInTable;
        FReprocess := True;
        Exit;
      end;
      if TagIn(Token.Name, ['body', 'col', 'colgroup', 'html', 'tbody',
        'td', 'tfoot', 'th', 'thead', 'tr']) then
        Exit;
    end;
  end;
  HandleInBody(Token);
end;

procedure TPixieTreeBuilder.HandleInColumnGroup(var Token: TPixieToken);
begin
  case Token.TokenType of
    ttCharacter:
      if IsHtmlWhitespace(Token.DataChar) then
      begin
        InsertText(Token.Data);
        Exit;
      end;
    ttComment:
    begin
      InsertComment(Token.Data);
      Exit;
    end;
    ttDoctype: Exit;
    ttStartTag:
    begin
      if Token.Name = 'html' then
      begin
        HandleInBody(Token);
        Exit;
      end;
      if Token.Name = 'col' then
      begin
        InsertElement(Token);
        PopCurrentNode;
        Exit;
      end;
      if Token.Name = 'template' then
      begin
        HandleInHead(Token);
        Exit;
      end;
    end;
    ttEndTag:
    begin
      if Token.Name = 'colgroup' then
      begin
        if (CurrentNode <> nil) and (CurrentNode.Tag = 'colgroup') then
        begin
          PopCurrentNode;
          FMode := imInTable;
        end;
        Exit;
      end;
      if Token.Name = 'col' then
        Exit;
      if Token.Name = 'template' then
      begin
        HandleInHead(Token);
        Exit;
      end;
    end;
    ttEof:
    begin
      HandleInBody(Token);
      Exit;
    end;
  end;
  // Anything else: pop colgroup
  if (CurrentNode <> nil) and (CurrentNode.Tag = 'colgroup') then
  begin
    PopCurrentNode;
    FMode := imInTable;
    FReprocess := True;
  end;
end;

procedure TPixieTreeBuilder.HandleInTableBody(var Token: TPixieToken);
begin
  case Token.TokenType of
    ttStartTag:
    begin
      if Token.Name = 'tr' then
      begin
        PopUntilOneOf(['tbody', 'tfoot', 'thead', 'html']);
        InsertElement(Token);
        FMode := imInRow;
        Exit;
      end;
      if TagIn(Token.Name, ['th', 'td']) then
      begin
        PopUntilOneOf(['tbody', 'tfoot', 'thead', 'html']);
        InsertElementNamed('tr');
        FMode := imInRow;
        FReprocess := True;
        Exit;
      end;
      if TagIn(Token.Name, ['caption', 'col', 'colgroup', 'tbody', 'tfoot', 'thead']) then
      begin
        if not (HasElementInTableScope('tbody') or HasElementInTableScope('thead') or
                HasElementInTableScope('tfoot')) then
          Exit;
        PopUntilOneOf(['tbody', 'tfoot', 'thead', 'html']);
        PopCurrentNode;
        FMode := imInTable;
        FReprocess := True;
        Exit;
      end;
    end;
    ttEndTag:
    begin
      if TagIn(Token.Name, ['tbody', 'tfoot', 'thead']) then
      begin
        if not HasElementInTableScope(Token.Name) then
          Exit;
        PopUntilOneOf(['tbody', 'tfoot', 'thead', 'html']);
        PopCurrentNode;
        FMode := imInTable;
        Exit;
      end;
      if Token.Name = 'table' then
      begin
        if not (HasElementInTableScope('tbody') or HasElementInTableScope('thead') or
                HasElementInTableScope('tfoot')) then
          Exit;
        PopUntilOneOf(['tbody', 'tfoot', 'thead', 'html']);
        PopCurrentNode;
        FMode := imInTable;
        FReprocess := True;
        Exit;
      end;
      if TagIn(Token.Name, ['body', 'caption', 'col', 'colgroup', 'html',
        'td', 'th', 'tr']) then
        Exit;
    end;
  end;
  HandleInTable(Token);
end;

procedure TPixieTreeBuilder.HandleInRow(var Token: TPixieToken);
begin
  case Token.TokenType of
    ttStartTag:
    begin
      if TagIn(Token.Name, ['th', 'td']) then
      begin
        PopUntilOneOf(['tr', 'html']);
        InsertElement(Token);
        FMode := imInCell;
        AddFormattingMarker;
        Exit;
      end;
      if TagIn(Token.Name, ['caption', 'col', 'colgroup', 'tbody', 'tfoot',
        'thead', 'tr']) then
      begin
        if not HasElementInTableScope('tr') then
          Exit;
        PopUntilOneOf(['tr', 'html']);
        PopCurrentNode;
        FMode := imInTableBody;
        FReprocess := True;
        Exit;
      end;
    end;
    ttEndTag:
    begin
      if Token.Name = 'tr' then
      begin
        if not HasElementInTableScope('tr') then
          Exit;
        PopUntilOneOf(['tr', 'html']);
        PopCurrentNode;
        FMode := imInTableBody;
        Exit;
      end;
      if Token.Name = 'table' then
      begin
        if not HasElementInTableScope('tr') then
          Exit;
        PopUntilOneOf(['tr', 'html']);
        PopCurrentNode;
        FMode := imInTableBody;
        FReprocess := True;
        Exit;
      end;
      if TagIn(Token.Name, ['tbody', 'tfoot', 'thead']) then
      begin
        if not HasElementInTableScope(Token.Name) then
          Exit;
        if not HasElementInTableScope('tr') then
          Exit;
        PopUntilOneOf(['tr', 'html']);
        PopCurrentNode;
        FMode := imInTableBody;
        FReprocess := True;
        Exit;
      end;
      if TagIn(Token.Name, ['body', 'caption', 'col', 'colgroup', 'html',
        'td', 'th']) then
        Exit;
    end;
  end;
  HandleInTable(Token);
end;

procedure TPixieTreeBuilder.HandleInCell(var Token: TPixieToken);
begin
  case Token.TokenType of
    ttStartTag:
      if TagIn(Token.Name, ['caption', 'col', 'colgroup', 'tbody', 'td',
        'tfoot', 'th', 'thead', 'tr']) then
      begin
        if not (HasElementInTableScope('td') or HasElementInTableScope('th')) then
          Exit;
        CloseCell;
        FReprocess := True;
        Exit;
      end;
    ttEndTag:
    begin
      if TagIn(Token.Name, ['td', 'th']) then
      begin
        if not HasElementInTableScope(Token.Name) then
          Exit;
        GenerateImpliedEndTags;
        PopUntil(Token.Name);
        ClearFormattingToLastMarker;
        FMode := imInRow;
        Exit;
      end;
      if TagIn(Token.Name, ['body', 'caption', 'col', 'colgroup', 'html']) then
        Exit;
      if TagIn(Token.Name, ['table', 'tbody', 'tfoot', 'thead', 'tr']) then
      begin
        if not HasElementInTableScope(Token.Name) then
          Exit;
        CloseCell;
        FReprocess := True;
        Exit;
      end;
    end;
  end;
  HandleInBody(Token);
end;

procedure TPixieTreeBuilder.HandleInSelect(var Token: TPixieToken);
begin
  case Token.TokenType of
    ttCharacter:
    begin
      if Token.DataChar = 0 then
        Exit;
      InsertText(Token.Data);
      Exit;
    end;
    ttComment:
    begin
      InsertComment(Token.Data);
      Exit;
    end;
    ttDoctype: Exit;
    ttStartTag:
    begin
      if Token.Name = 'html' then
      begin
        HandleInBody(Token);
        Exit;
      end;
      if Token.Name = 'option' then
      begin
        if (CurrentNode <> nil) and (CurrentNode.Tag = 'option') then
          PopCurrentNode;
        InsertElement(Token);
        Exit;
      end;
      if Token.Name = 'optgroup' then
      begin
        if (CurrentNode <> nil) and (CurrentNode.Tag = 'option') then
          PopCurrentNode;
        if (CurrentNode <> nil) and (CurrentNode.Tag = 'optgroup') then
          PopCurrentNode;
        InsertElement(Token);
        Exit;
      end;
      if Token.Name = 'select' then
      begin
        if not HasElementInSelectScope('select') then
          Exit;
        PopUntil('select');
        ResetInsertionMode;
        Exit;
      end;
      if TagIn(Token.Name, ['input', 'keygen', 'textarea']) then
      begin
        if not HasElementInSelectScope('select') then
          Exit;
        PopUntil('select');
        ResetInsertionMode;
        FReprocess := True;
        Exit;
      end;
      if TagIn(Token.Name, ['script', 'template']) then
      begin
        HandleInHead(Token);
        Exit;
      end;
    end;
    ttEndTag:
    begin
      if Token.Name = 'optgroup' then
      begin
        if (CurrentNode <> nil) and (CurrentNode.Tag = 'option') and
           (FOpenElements.Count >= 2) and
           (FOpenElements[FOpenElements.Count - 2].Tag = 'optgroup') then
          PopCurrentNode;
        if (CurrentNode <> nil) and (CurrentNode.Tag = 'optgroup') then
          PopCurrentNode;
        Exit;
      end;
      if Token.Name = 'option' then
      begin
        if (CurrentNode <> nil) and (CurrentNode.Tag = 'option') then
          PopCurrentNode;
        Exit;
      end;
      if Token.Name = 'select' then
      begin
        if not HasElementInSelectScope('select') then
          Exit;
        PopUntil('select');
        ResetInsertionMode;
        Exit;
      end;
      if Token.Name = 'template' then
      begin
        HandleInHead(Token);
        Exit;
      end;
    end;
    ttEof:
    begin
      HandleInBody(Token);
      Exit;
    end;
  end;
end;

procedure TPixieTreeBuilder.HandleInSelectInTable(var Token: TPixieToken);
begin
  case Token.TokenType of
    ttStartTag:
      if TagIn(Token.Name, ['caption', 'table', 'tbody', 'tfoot', 'thead',
        'tr', 'td', 'th']) then
      begin
        PopUntil('select');
        ResetInsertionMode;
        FReprocess := True;
        Exit;
      end;
    ttEndTag:
      if TagIn(Token.Name, ['caption', 'table', 'tbody', 'tfoot', 'thead',
        'tr', 'td', 'th']) then
      begin
        if not HasElementInTableScope(Token.Name) then
          Exit;
        PopUntil('select');
        ResetInsertionMode;
        FReprocess := True;
        Exit;
      end;
  end;
  HandleInSelect(Token);
end;

procedure TPixieTreeBuilder.HandleInTemplate(var Token: TPixieToken);
begin
  case Token.TokenType of
    ttCharacter, ttComment, ttDoctype:
    begin
      HandleInBody(Token);
      Exit;
    end;
    ttStartTag:
    begin
      if TagIn(Token.Name, ['base', 'basefont', 'bgsound', 'link', 'meta',
        'noframes', 'script', 'style', 'template', 'title']) then
      begin
        HandleInHead(Token);
        Exit;
      end;
      if TagIn(Token.Name, ['caption', 'colgroup', 'tbody', 'tfoot', 'thead']) then
      begin
        if FTemplateInsertionModes.Count > 0 then
          FTemplateInsertionModes[FTemplateInsertionModes.Count - 1] := imInTable;
        FMode := imInTable;
        FReprocess := True;
        Exit;
      end;
      if Token.Name = 'col' then
      begin
        if FTemplateInsertionModes.Count > 0 then
          FTemplateInsertionModes[FTemplateInsertionModes.Count - 1] := imInColumnGroup;
        FMode := imInColumnGroup;
        FReprocess := True;
        Exit;
      end;
      if Token.Name = 'tr' then
      begin
        if FTemplateInsertionModes.Count > 0 then
          FTemplateInsertionModes[FTemplateInsertionModes.Count - 1] := imInTableBody;
        FMode := imInTableBody;
        FReprocess := True;
        Exit;
      end;
      if TagIn(Token.Name, ['td', 'th']) then
      begin
        if FTemplateInsertionModes.Count > 0 then
          FTemplateInsertionModes[FTemplateInsertionModes.Count - 1] := imInRow;
        FMode := imInRow;
        FReprocess := True;
        Exit;
      end;
      // Anything else
      if FTemplateInsertionModes.Count > 0 then
        FTemplateInsertionModes[FTemplateInsertionModes.Count - 1] := imInBody;
      FMode := imInBody;
      FReprocess := True;
      Exit;
    end;
    ttEndTag:
    begin
      if Token.Name = 'template' then
      begin
        HandleInHead(Token);
        Exit;
      end;
      // Anything else: ignore
      Exit;
    end;
    ttEof:
    begin
      if not HasElementInScope('template') then
        Exit; // stop parsing
      PopUntil('template');
      ClearFormattingToLastMarker;
      if FTemplateInsertionModes.Count > 0 then
        FTemplateInsertionModes.Delete(FTemplateInsertionModes.Count - 1);
      ResetInsertionMode;
      FReprocess := True;
    end;
  end;
end;

procedure TPixieTreeBuilder.HandleAfterBody(var Token: TPixieToken);
var
  CommentNode: TPixieHtmlNode;
begin
  case Token.TokenType of
    ttCharacter:
      if IsHtmlWhitespace(Token.DataChar) then
      begin
        HandleInBody(Token);
        Exit;
      end;
    ttComment:
    begin
      // Append to html element
      FlushTextBuffer;
      if FOpenElements.Count > 0 then
      begin
        CommentNode := TPixieHtmlNode.Create(hntComment);
        CommentNode.Text := Token.Data;
        FOpenElements[0].AppendChild(CommentNode);
      end;
      Exit;
    end;
    ttDoctype: Exit;
    ttStartTag:
      if Token.Name = 'html' then
      begin
        HandleInBody(Token);
        Exit;
      end;
    ttEndTag:
      if Token.Name = 'html' then
      begin
        if FFragmentContext <> nil then
          Exit;
        FMode := imAfterAfterBody;
        Exit;
      end;
    ttEof:
    begin
      FlushTextBuffer;
      Exit;
    end;
  end;
  FMode := imInBody;
  FReprocess := True;
end;

procedure TPixieTreeBuilder.HandleInFrameset(var Token: TPixieToken);
begin
  case Token.TokenType of
    ttCharacter:
      if IsHtmlWhitespace(Token.DataChar) then
      begin
        InsertText(Token.Data);
        Exit;
      end;
    ttComment:
    begin
      InsertComment(Token.Data);
      Exit;
    end;
    ttDoctype: Exit;
    ttStartTag:
    begin
      if Token.Name = 'html' then
      begin
        HandleInBody(Token);
        Exit;
      end;
      if Token.Name = 'frameset' then
      begin
        InsertElement(Token);
        Exit;
      end;
      if Token.Name = 'frame' then
      begin
        InsertElement(Token);
        PopCurrentNode;
        Exit;
      end;
      if Token.Name = 'noframes' then
      begin
        HandleInHead(Token);
        Exit;
      end;
    end;
    ttEndTag:
      if Token.Name = 'frameset' then
      begin
        if (CurrentNode <> nil) and (CurrentNode.Tag = 'html') then
          Exit;
        PopCurrentNode;
        if (FFragmentContext = nil) and (CurrentNode <> nil) and
           (CurrentNode.Tag <> 'frameset') then
          FMode := imAfterFrameset;
        Exit;
      end;
    ttEof:
    begin
      FlushTextBuffer;
      Exit;
    end;
  end;
end;

procedure TPixieTreeBuilder.HandleAfterFrameset(var Token: TPixieToken);
begin
  case Token.TokenType of
    ttCharacter:
      if IsHtmlWhitespace(Token.DataChar) then
      begin
        InsertText(Token.Data);
        Exit;
      end;
    ttComment:
    begin
      InsertComment(Token.Data);
      Exit;
    end;
    ttDoctype: Exit;
    ttStartTag:
    begin
      if Token.Name = 'html' then
      begin
        HandleInBody(Token);
        Exit;
      end;
      if Token.Name = 'noframes' then
      begin
        HandleInHead(Token);
        Exit;
      end;
    end;
    ttEndTag:
      if Token.Name = 'html' then
      begin
        FMode := imAfterAfterFrameset;
        Exit;
      end;
    ttEof:
    begin
      FlushTextBuffer;
      Exit;
    end;
  end;
end;

procedure TPixieTreeBuilder.HandleAfterAfterBody(var Token: TPixieToken);
var
  CommentNode: TPixieHtmlNode;
begin
  case Token.TokenType of
    ttComment:
    begin
      FlushTextBuffer;
      CommentNode := TPixieHtmlNode.Create(hntComment);
      CommentNode.Text := Token.Data;
      FDocument.AppendChild(CommentNode);
      Exit;
    end;
    ttDoctype, ttEof:
    begin
      if Token.TokenType = ttEof then
        FlushTextBuffer;
      Exit;
    end;
    ttCharacter:
      if IsHtmlWhitespace(Token.DataChar) then
      begin
        HandleInBody(Token);
        Exit;
      end;
    ttStartTag:
      if Token.Name = 'html' then
      begin
        HandleInBody(Token);
        Exit;
      end;
  end;
  FMode := imInBody;
  FReprocess := True;
end;

procedure TPixieTreeBuilder.HandleAfterAfterFrameset(var Token: TPixieToken);
var
  CommentNode: TPixieHtmlNode;
begin
  case Token.TokenType of
    ttComment:
    begin
      FlushTextBuffer;
      CommentNode := TPixieHtmlNode.Create(hntComment);
      CommentNode.Text := Token.Data;
      FDocument.AppendChild(CommentNode);
      Exit;
    end;
    ttDoctype, ttEof:
    begin
      if Token.TokenType = ttEof then
        FlushTextBuffer;
      Exit;
    end;
    ttCharacter:
      if IsHtmlWhitespace(Token.DataChar) then
      begin
        HandleInBody(Token);
        Exit;
      end;
    ttStartTag:
    begin
      if Token.Name = 'html' then
      begin
        HandleInBody(Token);
        Exit;
      end;
      if Token.Name = 'noframes' then
      begin
        HandleInHead(Token);
        Exit;
      end;
    end;
  end;
end;

// ---- Main parse loop ----

function TPixieTreeBuilder.Parse: TPixieHtmlNode;
var
  Token: TPixieToken;
  CdataNode: TPixieHtmlNode;
begin
  while True do
  begin
    if not FReprocess then
    begin
      Token := Default(TPixieToken);
      FTokenizer.NextToken(Token);
    end;
    FReprocess := False;

    // Handle CDATA sentinel
    if (Token.TokenType = ttCharacter) and (Token.DataChar = -2) then
    begin
      // CDATA character
      FlushTextBuffer;
      CdataNode := TPixieHtmlNode.Create(hntCData);
      CdataNode.Text := Token.Data;
      if CurrentNode <> nil then
        CurrentNode.AppendChild(CdataNode)
      else
        FDocument.AppendChild(CdataNode);
      Continue;
    end;

    // Handle ignore next LF
    if FIgnoreNextLf and (Token.TokenType = ttCharacter) and (Token.DataChar = 10) then
    begin
      FIgnoreNextLf := False;
      Continue;
    end;
    if Token.TokenType <> ttCharacter then
      FIgnoreNextLf := False;

    ProcessToken(Token);

    // Free attrs if not consumed and not being reprocessed
    if not FReprocess then
    begin
      if Token.Attrs <> nil then
      begin
        Token.Attrs.Free;
        Token.Attrs := nil;
      end;
    end;

    UpdateForeignContext;

    if Token.TokenType = ttEof then
      Break;
  end;

  FlushTextBuffer;

  // Pop remaining open elements
  while FOpenElements.Count > 0 do
    PopCurrentNode;

  Result := FDocument;
  FDocument := nil; // Transfer ownership
end;

function TPixieTreeBuilder.ParseFragment(const ContextTag: string): TPixieHtmlNode;
var
  ContextEl, HtmlEl: TPixieHtmlNode;
begin
  // Create context element
  ContextEl := TPixieHtmlNode.Create(hntElement);
  ContextEl.Tag := LowerStr(ContextTag);
  FFragmentContext := ContextEl;

  // Set tokenizer state based on context
  if TagIn(ContextEl.Tag, ['title', 'textarea']) then
    FTokenizer.SetState(lsRcdata)
  else if TagIn(ContextEl.Tag, ['style', 'xmp', 'iframe', 'noembed', 'noframes']) then
    FTokenizer.SetState(lsRawtext)
  else if ContextEl.Tag = 'script' then
    FTokenizer.SetState(lsScript)
  else if ContextEl.Tag = 'plaintext' then
    FTokenizer.SetState(lsPlaintext);

  // Create html root
  HtmlEl := CreateElement('html', hnsHtml);
  FDocument.AppendChild(HtmlEl);
  FOpenElements.Add(HtmlEl);

  if ContextEl.Tag = 'template' then
    FTemplateInsertionModes.Add(imInTemplate);

  ResetInsertionMode;
  UpdateForeignContext;

  // Set form element
  FFormElement := nil;

  // Run the parser
  Result := Parse;

  // Clean up context element
  ContextEl.Free;
end;

// =========================================================================
// Public API
// =========================================================================

function PixieParseHtml(const Html: string): TPixieHtmlNode;
var
  Builder: TPixieTreeBuilder;
begin
  Builder := TPixieTreeBuilder.Create(Html);
  try
    Result := Builder.Parse;
  finally
    Builder.Free;
  end;
end;

function PixieParseFragment(const Html, ContextTag: string): TPixieHtmlNode;
var
  Builder: TPixieTreeBuilder;
begin
  Builder := TPixieTreeBuilder.Create(Html);
  try
    Result := Builder.ParseFragment(ContextTag);
  finally
    Builder.Free;
  end;
end;

initialization
  FormattingScopeMarker := TPixieHtmlNode.Create(hntComment);
  FormattingScopeMarker.Tag := '#marker';

finalization
  FormattingScopeMarker.Free;

end.
