unit Pixie.CssSelector;

// CSS selector model and parsing.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Generics.Collections,
  Pixie.Types, Pixie.StringId, Pixie.Utils,
  Pixie.CssTokenizer, Pixie.CssParser,
  Pixie.MediaQuery;

type
  TPixieAttrSelectType = (
    selectClass,
    selectId,
    selectAttr,
    selectPseudoClass,
    selectPseudoElement
  );

const
  // Attribute matchers
  PixieAttrExists           = 0;
  PixieAttrEquals           = Ord('=');
  PixieAttrContainsString   = Ord('*'); // *=
  PixieAttrContainsWord     = Ord('~'); // ~=
  PixieAttrStartsWithString = Ord('^'); // ^=
  PixieAttrStartsWithHyphen = Ord('|'); // |=
  PixieAttrEndsWithString   = Ord('$'); // $=

  // Combinators
  PixieCombinatorDescendant       = Ord(' ');
  PixieCombinatorChild            = Ord('>');
  PixieCombinatorAdjacentSibling  = Ord('+');
  PixieCombinatorGeneralSibling   = Ord('~');

  // Selector list parse options
  PixieSelectorStrict         = 0;
  PixieSelectorForgiving      = 1;
  PixieSelectorForbidPseudo   = 2;

type
  TPixieCssSelector = class;
  TPixieCssSelectorList = TObjectList<TPixieCssSelector>;

  { TPixieSelectorSpecificity }

  TPixieSelectorSpecificity = record
    A, B, C, D: Integer;
    class function Create(VA: Integer = 0; VB: Integer = 0;
      VC: Integer = 0; VD: Integer = 0): TPixieSelectorSpecificity; static;
    procedure Add(const Val: TPixieSelectorSpecificity);
    function Compare(const Val: TPixieSelectorSpecificity): Integer;
  end;

  { TPixieAttrSelector }

  TPixieAttrSelector = class
  public
    SelectType: TPixieAttrSelectType;
    Prefix: Integer;         // string_id for namespace prefix
    Name: Integer;           // string_id for .name, #name, [name], :name
    Value: string;           // [name=value], :lang(value)
    Matcher: Integer;        // PixieAttr* constants
    CaselessMatch: Boolean;
    SelectorList: TPixieCssSelectorList; // :not(list), :is(list), :nth-child(of list)
    A, B: Integer;           // :nth-child(An+B)

    constructor Create(AType: TPixieAttrSelectType = selectClass;
      const AName: string = '');
    destructor Destroy; override;
  end;

  TPixieAttrSelectorList = TObjectList<TPixieAttrSelector>;

  { TPixieCompoundSelector }

  TPixieCompoundSelector = class
  public
    Prefix: Integer;   // string_id
    Tag: Integer;      // string_id
    Attrs: TPixieAttrSelectorList;

    constructor Create;
    destructor Destroy; override;
  end;

  { TPixieCssSelector }

  TPixieCssSelector = class
  public
    Specificity: TPixieSelectorSpecificity;
    Order: Integer;
    Left: TPixieCssSelector;      // owned - next selector in the chain
    Right: TPixieCompoundSelector; // owned - compound selector for this part
    Combinator: Integer;           // PixieCombinator* constants
    Style: TObject;                // not owned - TPixieStyle, owned by stylesheet
    MediaQuery: TPixieMediaQueryListList; // not owned - media query, owned by stylesheet

    constructor Create;
    destructor Destroy; override;
    function Parse(const Text: string; Mode: TPixieDocumentMode): Boolean;
    procedure CalcSpecificity;
    function IsMediaValid: Boolean; overload; inline;
    function IsMediaValid(const Features: TPixieMediaFeatures): Boolean; overload; inline;
  end;

  { TPixieUsedSelector }

  TPixieUsedSelector = class
  public
    Selector: TPixieCssSelector; // not owned
    Used: Boolean;

    constructor Create(ASelector: TPixieCssSelector; AUsed: Boolean);
  end;

  TPixieUsedSelectorList = TObjectList<TPixieUsedSelector>;

function PixieParseSelectorList(Tokens: TPixieCssTokenList; Options: Integer;
  Mode: TPixieDocumentMode): TPixieCssSelectorList;

implementation

var
  SentinelToken: TPixieCssToken;

{ Helpers }

function TokenSafe(Tokens: TPixieCssTokenList; Index: Integer): TPixieCssToken;
begin
  if (Index >= 0) and (Index < Tokens.Count) then
    Result := Tokens[Index]
  else
    Result := SentinelToken;
end;

const
  SupportedSimplePseudoClasses =
    'any-link;link;visited;local-link;target;target-within;scope;' +
    'hover;active;focus;focus-visible;focus-within;' +
    'checked;disabled;enabled;' +
    'root;empty;first-child;last-child;only-child;' +
    'first-of-type;last-of-type;only-of-type';

  SpecialAttributeNames =
    'accept;accept-charset;align;alink;axis;bgcolor;charset;checked;' +
    'clear;codetype;color;compact;declare;defer;dir;direction;disabled;' +
    'enctype;face;frame;hreflang;http-equiv;lang;language;link;media;' +
    'method;multiple;nohref;noresize;noshade;nowrap;readonly;rel;rev;' +
    'rules;scope;scrolling;selected;shape;target;text;type;valign;' +
    'valuetype;vlink';

function IsSupportedSimplePseudoClass(const Name: string): Boolean;
begin
  Result := PixieValueInList(PixieLowerCase(Name), SupportedSimplePseudoClasses);
end;

function IsSupportedSimplePseudoElement(const Name: string): Boolean;
begin
  Result := SameText(Name, 'before') or SameText(Name, 'after');
end;

function IsSpecialAttribute(const Name: string): Boolean;
begin
  Result := PixieValueInList(Name, SpecialAttributeNames);
end;

{ An+B parsing }

type
  TAnB = record
    A, B: Integer;
    Valid: Boolean;
  end;

function MakeAnB(AA, AB: Integer): TAnB;
begin
  Result.A := AA;
  Result.B := AB;
  Result.Valid := True;
end;

function InvalidAnB: TAnB;
begin
  Result.A := 0;
  Result.B := 0;
  Result.Valid := False;
end;

function TryParseInt(const S: string; out N: Integer): Boolean;
var
  Code: Integer;
begin
  if S = '' then Exit(False);
  Val(S, N, Code);
  Result := Code = 0;
end;

function ParseAnB(S: string): TAnB;
var
  I, A, B: Integer;
  StrA, StrB: string;
begin
  S := PixieLowerCase(PixieTrim(S));
  if S = 'even' then Exit(MakeAnB(2, 0));
  if S = 'odd' then Exit(MakeAnB(2, 1));

  I := Pos('n', S);
  if I = 0 then
  begin
    if not TryParseInt(S, B) then Exit(InvalidAnB);
    Exit(MakeAnB(0, B));
  end;

  StrA := Copy(S, 1, I - 1);
  StrB := Copy(S, I + 1, Length(S) - I);

  if (StrA = '') or (StrA = '+') or (StrA = '-') then
  begin
    if StrA = '-' then A := -1 else A := 1;
  end
  else if not TryParseInt(StrA, A) then
    Exit(InvalidAnB);

  StrB := PixieTrim(StrB);
  if StrB <> '' then
  begin
    if (StrB[1] = '+') or (StrB[1] = '-') then
      while (Length(StrB) > 1) and PixieIsWhitespace(Ord(StrB[2])) do
        Delete(StrB, 2, 1);
    if not TryParseInt(StrB, B) then Exit(InvalidAnB);
  end
  else
    B := 0;

  Result := MakeAnB(A, B);
end;

function FindOfKeyword(Tokens: TPixieCssTokenList): Integer;
var
  I: Integer;
begin
  for I := 0 to Tokens.Count - 1 do
    if Tokens[I].Ident = 'of' then
      Exit(I);
  Result := -1;
end;

{ Namespace prefix parsing }

// <ns-prefix> = [ <ident-token> | '*' ]? '|'
function ParseNsPrefix(Tokens: TPixieCssTokenList; var Index: Integer): string;
var
  A, B: TPixieCssToken;
begin
  A := TokenSafe(Tokens, Index);
  B := TokenSafe(Tokens, Index + 1);

  if A.TokenType = Ord('|') then
  begin
    Inc(Index);
    Exit('');
  end;

  if ((A.TokenType = cssTokenIdent) or (A.TokenType = Ord('*'))) and
     (B.TokenType = Ord('|')) then
  begin
    Inc(Index, 2);
    if A.TokenType = cssTokenIdent then
      Exit(A.Str)
    else
      Exit('*');
  end;

  Result := '';
end;

// <wq-name> = <ns-prefix>? <ident-token>
procedure ParseWqName(Tokens: TPixieCssTokenList; var Index: Integer;
  out Prefix, Name: string);
var
  Start: Integer;
  Tok: TPixieCssToken;
begin
  Prefix := '';
  Name := '';
  Start := Index;
  Prefix := ParseNsPrefix(Tokens, Index);

  Tok := TokenSafe(Tokens, Index);
  if Tok.TokenType = cssTokenIdent then
  begin
    Inc(Index);
    Name := Tok.Str;
    Exit;
  end;

  // Restore index if ident not found after prefix
  Index := Start;

  // Handle case where name was parsed as prefix, e.g. [x|=a]
  Tok := TokenSafe(Tokens, Index);
  if Tok.TokenType = cssTokenIdent then
  begin
    Inc(Index);
    Prefix := '';
    Name := Tok.Str;
    Exit;
  end;
end;

// <type-selector> = <ns-prefix>? [ <ident-token> | '*' ]
procedure ParseTypeSelector(Tokens: TPixieCssTokenList; var Index: Integer;
  out Prefix, Tag: string);
var
  Start: Integer;
  NsPrefix: string;
  Tok: TPixieCssToken;
begin
  Prefix := '';
  Tag := '';
  Start := Index;
  NsPrefix := ParseNsPrefix(Tokens, Index);

  Tok := TokenSafe(Tokens, Index);
  if (Tok.TokenType = cssTokenIdent) or (Tok.TokenType = Ord('*')) then
  begin
    Inc(Index);
    if Tok.TokenType = cssTokenIdent then
      Tag := Tok.Str
    else
      Tag := '*';
    // Type selector is always case-insensitive for HTML
    Prefix := PixieLowerCase(NsPrefix);
    Tag := PixieLowerCase(Tag);
    Exit;
  end;

  // Restore index
  Index := Start;
end;

{ Attribute selector parsing }

// <attr-matcher> = [ '~' | '|' | '^' | '$' | '*' ]? '='
function ParseAttrMatcher(Tokens: TPixieCssTokenList; var Index: Integer;
  out Matcher: Integer): Boolean;
var
  A, B: TPixieCssToken;
begin
  A := TokenSafe(Tokens, Index);
  B := TokenSafe(Tokens, Index + 1);

  if A.TokenType = Ord('=') then
  begin
    Inc(Index);
    Matcher := PixieAttrEquals;
    Exit(True);
  end;

  if ((A.TokenType = Ord('~')) or (A.TokenType = Ord('|')) or
      (A.TokenType = Ord('^')) or (A.TokenType = Ord('$')) or
      (A.TokenType = Ord('*'))) and (B.TokenType = Ord('=')) then
  begin
    Inc(Index, 2);
    Matcher := A.TokenType;
    Exit(True);
  end;

  Result := False;
end;

// <attribute-selector> = '[' <wq-name> ']' |
//   '[' <wq-name> <attr-matcher> [ <string-token> | <ident-token> ] <attr-modifier>? ']'
function ParseAttributeSelector(Block: TPixieCssToken): TPixieAttrSelector;
var
  Tokens: TPixieCssTokenList;
  Index: Integer;
  Prefix, Name: string;
  MatcherVal: Integer;
  ValueTok, ModTok: TPixieCssToken;
  Modifier: Char;
begin
  Tokens := Block.Value;
  Index := 0;

  // <wq-name>
  PixieCssSkipWhitespace(Tokens, Index);
  ParseWqName(Tokens, Index, Prefix, Name);
  if Name = '' then Exit(nil);

  // Attribute name is case-insensitive for HTML
  Prefix := PixieLowerCase(Prefix);
  Name := PixieLowerCase(Name);

  PixieCssSkipWhitespace(Tokens, Index);
  if Index >= Tokens.Count then
  begin
    // [name] - attribute existence
    Result := TPixieAttrSelector.Create(selectAttr);
    Result.Prefix := PixieId(Prefix);
    Result.Name := PixieId(Name);
    Result.Matcher := PixieAttrExists;
    Exit;
  end;

  // <attr-matcher>
  PixieCssSkipWhitespace(Tokens, Index);
  if not ParseAttrMatcher(Tokens, Index, MatcherVal) then Exit(nil);

  // <string-token> | <ident-token>
  PixieCssSkipWhitespace(Tokens, Index);
  ValueTok := TokenSafe(Tokens, Index);
  if (ValueTok.TokenType <> cssTokenString) and
     (ValueTok.TokenType <> cssTokenIdent) then
    Exit(nil);
  Inc(Index);

  // <attr-modifier>?
  PixieCssSkipWhitespace(Tokens, Index);
  Modifier := #0;
  ModTok := TokenSafe(Tokens, Index);
  if ModTok.TokenType = cssTokenIdent then
  begin
    if ModTok.Ident = 's' then Modifier := 's'
    else if ModTok.Ident = 'i' then Modifier := 'i'
    else Exit(nil);
    Inc(Index);
  end;

  PixieCssSkipWhitespace(Tokens, Index);
  if Index <> Tokens.Count then Exit(nil); // junk at end

  Result := TPixieAttrSelector.Create(selectAttr);
  Result.Prefix := PixieId(Prefix);
  Result.Name := PixieId(Name);
  Result.Matcher := MatcherVal;
  Result.CaselessMatch := (Modifier = 'i') or
    ((Modifier = #0) and IsSpecialAttribute(Name));
  if Result.CaselessMatch then
    Result.Value := PixieLowerCase(ValueTok.Str)
  else
    Result.Value := ValueTok.Str;
end;

{ Pseudo-class and pseudo-element parsing }

function ParseNthChild(Token: TPixieCssToken; OfKeyword: Boolean;
  Mode: TPixieDocumentMode): TPixieAttrSelector;
var
  Tokens: TPixieCssTokenList;
  OfIndex, I: Integer;
  SubList: TPixieCssTokenList;
  Str: string;
  AnB: TAnB;
begin
  Result := TPixieAttrSelector.Create(selectPseudoClass, PixieLowerCase(Token.Str));
  Tokens := Token.Value;

  // Find "of" keyword
  if OfKeyword then
    OfIndex := FindOfKeyword(Tokens)
  else
    OfIndex := -1;

  if OfIndex >= 0 then
  begin
    SubList := TPixieCssTokenList.Create(False);
    try
      for I := OfIndex + 1 to Tokens.Count - 1 do
        SubList.Add(Tokens[I]);
      Result.SelectorList := PixieParseSelectorList(SubList,
        PixieSelectorForgiving or PixieSelectorForbidPseudo, Mode);
    finally
      SubList.Free;
    end;
  end;

  // Get An+B string
  if OfIndex >= 0 then
    Str := PixieCssGetRepr(Tokens, 0, OfIndex)
  else
    Str := PixieCssGetRepr(Tokens);

  AnB := ParseAnB(Str);
  if not AnB.Valid then
  begin
    FreeAndNil(Result);
    Exit;
  end;

  Result.A := AnB.A;
  Result.B := AnB.B;
end;

function ParseFunctionPseudoClass(Token: TPixieCssToken;
  Mode: TPixieDocumentMode): TPixieAttrSelector;
var
  Name: string;
begin
  Name := PixieLowerCase(Token.Str);

  if (Name = 'nth-child') or (Name = 'nth-last-child') then
    Exit(ParseNthChild(Token, True, Mode));

  if (Name = 'nth-of-type') or (Name = 'nth-last-of-type') then
    Exit(ParseNthChild(Token, False, Mode));

  if Name = 'is' then
  begin
    Result := TPixieAttrSelector.Create(selectPseudoClass, Name);
    Result.SelectorList := PixieParseSelectorList(Token.Value,
      PixieSelectorForgiving or PixieSelectorForbidPseudo, Mode);
    Exit;
  end;

  if Name = 'not' then
  begin
    Result := TPixieAttrSelector.Create(selectPseudoClass, Name);
    Result.SelectorList := PixieParseSelectorList(Token.Value,
      PixieSelectorStrict or PixieSelectorForbidPseudo, Mode);
    if Result.SelectorList.Count = 0 then
    begin
      FreeAndNil(Result);
      Exit;
    end;
    Exit;
  end;

  if Name = 'lang' then
  begin
    Result := TPixieAttrSelector.Create(selectPseudoClass, Name);
    Result.Value := PixieCssGetRepr(Token.Value);
    Exit;
  end;

  Result := nil;
end;

// <pseudo-class-selector> = ':' <ident-token> | ':' <function-token> <any-value> ')'
function ParsePseudoClass(Tokens: TPixieCssTokenList; var Index: Integer;
  Mode: TPixieDocumentMode): TPixieAttrSelector;
var
  A, B: TPixieCssToken;
begin
  A := TokenSafe(Tokens, Index);
  B := TokenSafe(Tokens, Index + 1);

  if A.TokenType <> Ord(':') then Exit(nil);

  if B.TokenType = cssTokenIdent then
  begin
    if not IsSupportedSimplePseudoClass(B.Ident) then Exit(nil);
    Inc(Index, 2);
    Result := TPixieAttrSelector.Create(selectPseudoClass, B.Ident);
    Exit;
  end;

  if B.TokenType = cssTokenCvFunction then
  begin
    Result := ParseFunctionPseudoClass(B, Mode);
    if Result <> nil then
      Inc(Index, 2);
    Exit;
  end;

  Result := nil;
end;

// <subclass-selector> = <id-selector> | <class-selector> | <attribute-selector> | <pseudo-class-selector>
function ParseSubclassSelector(Tokens: TPixieCssTokenList; var Index: Integer;
  Mode: TPixieDocumentMode): TPixieAttrSelector;
var
  Tok0, Tok1: TPixieCssToken;
  Name: string;
begin
  Tok0 := TokenSafe(Tokens, Index);
  Tok1 := TokenSafe(Tokens, Index + 1);

  case Tok0.TokenType of
    cssTokenHash:
    begin
      if Tok0.HashType = cssHashId then
      begin
        Inc(Index);
        Name := Tok0.Str;
        if Mode = dmQuirks then
          Name := PixieLowerCase(Name);
        Result := TPixieAttrSelector.Create(selectId, Name);
        Result.Value := Name;
        Exit;
      end;
      Exit(nil);
    end;

    Ord('.'):
    begin
      if Tok1.TokenType = cssTokenIdent then
      begin
        Inc(Index, 2);
        Name := Tok1.Str;
        if Mode = dmQuirks then
          Name := PixieLowerCase(Name);
        Result := TPixieAttrSelector.Create(selectClass, Name);
        Result.Value := Name;
        Exit;
      end;
      Exit(nil);
    end;

    cssTokenSquareBlock:
    begin
      Result := ParseAttributeSelector(Tok0);
      if Result <> nil then
        Inc(Index);
      Exit;
    end;

  else
    Result := ParsePseudoClass(Tokens, Index, Mode);
  end;
end;

function ParsePseudoElement(Tokens: TPixieCssTokenList;
  var Index: Integer): TPixieAttrSelector;
var
  A, B, C: TPixieCssToken;
begin
  A := TokenSafe(Tokens, Index);
  B := TokenSafe(Tokens, Index + 1);
  C := TokenSafe(Tokens, Index + 2);

  if A.TokenType <> Ord(':') then Exit(nil);
  if (B.TokenType <> Ord(':')) and (B.TokenType <> cssTokenIdent) then Exit(nil);

  // Legacy syntax with one ':'
  if B.TokenType = cssTokenIdent then
  begin
    if not ((B.Ident = 'before') or (B.Ident = 'after')) then Exit(nil);
    Inc(Index, 2);
    Result := TPixieAttrSelector.Create(selectPseudoElement, B.Ident);
    Exit;
  end;

  // Normal syntax with '::'
  if C.TokenType = cssTokenIdent then
  begin
    if not IsSupportedSimplePseudoElement(C.Ident) then Exit(nil);
    Inc(Index, 3);
    Result := TPixieAttrSelector.Create(selectPseudoElement, C.Ident);
    Exit;
  end;

  Result := nil;
end;

{ Compound selector parsing }

// <compound-selector> = [ <type-selector>? <subclass-selector>*
//                         [ <pseudo-element-selector> <pseudo-class-selector>* ]* ]!
function ParseCompoundSelector(Tokens: TPixieCssTokenList; var Index: Integer;
  Mode: TPixieDocumentMode): TPixieCompoundSelector;
var
  Prefix, Tag: string;
  Sel: TPixieAttrSelector;
begin
  Result := TPixieCompoundSelector.Create;

  // <type-selector>?
  ParseTypeSelector(Tokens, Index, Prefix, Tag);
  Result.Prefix := PixieId(Prefix);
  Result.Tag := PixieId(Tag);

  // <subclass-selector>*
  Sel := ParseSubclassSelector(Tokens, Index, Mode);
  while Sel <> nil do
  begin
    Result.Attrs.Add(Sel);
    Sel := ParseSubclassSelector(Tokens, Index, Mode);
  end;

  // [ <pseudo-element-selector> <pseudo-class-selector>* ]*
  while True do
  begin
    Sel := ParsePseudoElement(Tokens, Index);
    if Sel = nil then Break;
    Result.Attrs.Add(Sel);

    Sel := ParsePseudoClass(Tokens, Index, Mode);
    while Sel <> nil do
    begin
      Result.Attrs.Add(Sel);
      Sel := ParsePseudoClass(Tokens, Index, Mode);
    end;
  end;

  // Must produce at least one value
  if (Result.Tag = PixieEmptyId) and (Result.Attrs.Count = 0) then
  begin
    FreeAndNil(Result);
    Exit;
  end;

  if Result.Tag = PixieEmptyId then
    Result.Tag := PixieStarId;
end;

{ Combinator parsing }

// <combinator> = '>' | '+' | '~' | <whitespace>
function ParseCombinator(Tokens: TPixieCssTokenList; var Index: Integer): Integer;
var
  WS: Boolean;
  Tok: TPixieCssToken;
begin
  WS := PixieCssSkipWhitespace(Tokens, Index);

  Tok := TokenSafe(Tokens, Index);
  if (Tok.TokenType = Ord('>')) or (Tok.TokenType = Ord('+')) or
     (Tok.TokenType = Ord('~')) then
  begin
    Inc(Index);
    PixieCssSkipWhitespace(Tokens, Index);
    Result := Tok.TokenType;
    Exit;
  end;

  if WS then
    Result := PixieCombinatorDescendant
  else
    Result := 0;
end;

{ Complex selector parsing }

function ParseComplexSelector(Tokens: TPixieCssTokenList;
  Mode: TPixieDocumentMode): TPixieCssSelector;
var
  Index, Comb: Integer;
  Compound: TPixieCompoundSelector;
  NewSel: TPixieCssSelector;
begin
  Index := 0;
  PixieCssSkipWhitespace(Tokens, Index);

  Compound := ParseCompoundSelector(Tokens, Index, Mode);
  if Compound = nil then Exit(nil);

  Result := TPixieCssSelector.Create;
  Result.Right.Free;
  Result.Right := Compound;

  while True do
  begin
    Comb := ParseCombinator(Tokens, Index);

    if Index >= Tokens.Count then
    begin
      // At end of tokens
      if (Comb = 0) or (Comb = PixieCombinatorDescendant) then
        Exit
      else
      begin
        FreeAndNil(Result);
        Exit;
      end;
    end;

    if Comb = 0 then
    begin
      // Not at end and no combinator
      FreeAndNil(Result);
      Exit;
    end;

    Compound := ParseCompoundSelector(Tokens, Index, Mode);
    if Compound = nil then
    begin
      FreeAndNil(Result);
      Exit;
    end;

    NewSel := TPixieCssSelector.Create;
    NewSel.Left := Result;
    NewSel.Right.Free;
    NewSel.Right := Compound;
    NewSel.Combinator := Comb;
    Result := NewSel;
  end;
end;

{ Utility }

function HasSelector(Sel: TPixieCssSelector; AType: TPixieAttrSelectType;
  const AName: string = ''): Boolean;
var
  I: Integer;
  Attr: TPixieAttrSelector;
begin
  for I := 0 to Sel.Right.Attrs.Count - 1 do
  begin
    Attr := Sel.Right.Attrs[I];
    if (Attr.SelectType = AType) and
       ((AName = '') or PixieEqualI(PixieStr(Attr.Name), AName)) then
      Exit(True);
  end;

  if Sel.Left <> nil then
    Exit(HasSelector(Sel.Left, AType, AName));

  Result := False;
end;

{ Public API }

function PixieParseSelectorList(Tokens: TPixieCssTokenList; Options: Integer;
  Mode: TPixieDocumentMode): TPixieCssSelectorList;
var
  Lists: TPixieCssTokenListList;
  I: Integer;
  Sel: TPixieCssSelector;
begin
  Lists := PixieCssParseCommaSeparatedList(Tokens);
  try
    Result := TPixieCssSelectorList.Create;
    for I := 0 to Lists.Count - 1 do
    begin
      Sel := ParseComplexSelector(Lists[I], Mode);

      if (Sel = nil) or
         ((Options and PixieSelectorForbidPseudo <> 0) and
          HasSelector(Sel, selectPseudoElement)) then
      begin
        FreeAndNil(Sel);
        if (Options and PixieSelectorForgiving) <> 0 then
          Continue
        else
        begin
          Result.Clear;
          Break;
        end;
      end;

      Result.Add(Sel);
    end;
  finally
    for I := 0 to Lists.Count - 1 do
      Lists[I].Free;
    Lists.Free;
  end;
end;

{ TPixieSelectorSpecificity }

class function TPixieSelectorSpecificity.Create(VA, VB, VC, VD: Integer): TPixieSelectorSpecificity;
begin
  Result.A := VA;
  Result.B := VB;
  Result.C := VC;
  Result.D := VD;
end;

procedure TPixieSelectorSpecificity.Add(const Val: TPixieSelectorSpecificity);
begin
  A := A + Val.A;
  B := B + Val.B;
  C := C + Val.C;
  D := D + Val.D;
end;

function TPixieSelectorSpecificity.Compare(const Val: TPixieSelectorSpecificity): Integer;
begin
  if A <> Val.A then Exit(A - Val.A);
  if B <> Val.B then Exit(B - Val.B);
  if C <> Val.C then Exit(C - Val.C);
  Result := D - Val.D;
end;

{ TPixieAttrSelector }

constructor TPixieAttrSelector.Create(AType: TPixieAttrSelectType;
  const AName: string);
begin
  inherited Create;
  SelectType := AType;
  Prefix := PixieEmptyId;
  Name := PixieId(AName);
  Matcher := PixieAttrExists;
  CaselessMatch := False;
  A := 0;
  B := 0;
end;

destructor TPixieAttrSelector.Destroy;
begin
  SelectorList.Free;
  inherited;
end;

{ TPixieCompoundSelector }

constructor TPixieCompoundSelector.Create;
begin
  inherited Create;
  Prefix := PixieEmptyId;
  Tag := PixieEmptyId;
  Attrs := TPixieAttrSelectorList.Create;
end;

destructor TPixieCompoundSelector.Destroy;
begin
  Attrs.Free;
  inherited;
end;

{ TPixieCssSelector }

constructor TPixieCssSelector.Create;
begin
  inherited Create;
  Specificity := TPixieSelectorSpecificity.Create;
  Order := 0;
  Left := nil;
  Right := TPixieCompoundSelector.Create;
  Combinator := PixieCombinatorDescendant;
  Style := nil;
  MediaQuery := nil;
end;

destructor TPixieCssSelector.Destroy;
begin
  Left.Free;
  Right.Free;
  inherited;
end;

function TPixieCssSelector.Parse(const Text: string; Mode: TPixieDocumentMode): Boolean;
var
  Tokens: TPixieCssTokenList;
  Parsed: TPixieCssSelector;
begin
  Tokens := PixieCssNormalizeStr(Text, cssCssNormComponentize);
  try
    Parsed := ParseComplexSelector(Tokens, Mode);
    if Parsed = nil then
      Exit(False);

    // Transfer state from Parsed to Self
    Left.Free;
    Right.Free;
    Left := Parsed.Left;
    Right := Parsed.Right;
    Combinator := Parsed.Combinator;
    Specificity := Parsed.Specificity;

    // Detach from Parsed so it doesn't free transferred objects
    Parsed.Left := nil;
    Parsed.Right := nil;
    Parsed.Free;

    Result := True;
  finally
    Tokens.Free;
  end;
end;

procedure TPixieCssSelector.CalcSpecificity;
var
  I: Integer;
  Attr: TPixieAttrSelector;
begin
  if Right.Tag <> PixieStarId then
    Specificity.D := 1;

  for I := 0 to Right.Attrs.Count - 1 do
  begin
    Attr := Right.Attrs[I];
    if Attr.SelectType = selectId then
      Inc(Specificity.B)
    else
      Inc(Specificity.C);
  end;

  if Left <> nil then
  begin
    Left.CalcSpecificity;
    Specificity.Add(Left.Specificity);
  end;
end;

function TPixieCssSelector.IsMediaValid: Boolean;
begin
  if MediaQuery = nil then
    Result := True
  else
    Result := MediaQuery.IsUsed;
end;

function TPixieCssSelector.IsMediaValid(const Features: TPixieMediaFeatures): Boolean;
begin
  if MediaQuery = nil then
    Result := True
  else
  begin
    MediaQuery.ApplyMediaFeatures(Features);
    Result := MediaQuery.IsUsed;
  end;
end;

{ TPixieUsedSelector }

constructor TPixieUsedSelector.Create(ASelector: TPixieCssSelector; AUsed: Boolean);
begin
  inherited Create;
  Selector := ASelector;
  Used := AUsed;
end;

initialization
  SentinelToken := TPixieCssToken.Create(cssTokenEof);

finalization
  SentinelToken.Free;

end.
