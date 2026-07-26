unit Pixie.CssParser;

// CSS3 rule/declaration parser following https://www.w3.org/TR/css-syntax-3/
//
// Consumes the flat token list from Pixie.CssTokenizer and produces:
//   - Componentized values (functions/blocks group their children)
//   - At-rules and qualified rules (TPixieCssRawRule)
//   - Declaration lists (TPixieCssRawDeclaration)

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Generics.Collections, Pixie.Utils, Pixie.CssTokenizer;

type
  TPixieCssRuleType = (
    cssRuleQualified,
    cssRuleAt
  );

  { TPixieCssRawRule }

  TPixieCssRawRule = class
  public
    RuleType: TPixieCssRuleType;
    Name: string;                  // at-rule name (empty for qualified rules)
    Prelude: TPixieCssTokenList;   // owned
    Block: TPixieCssToken;         // the { } block (nil if none, e.g. @import ...;)

    constructor Create(AType: TPixieCssRuleType; const AName: string = '');
    destructor Destroy; override;
  end;

  TPixieCssRawRuleList = TObjectList<TPixieCssRawRule>;

  { TPixieCssRawDeclaration }

  TPixieCssRawDeclaration = record
    Name: string;                 // property name (lowercased)
    Value: TPixieCssTokenList;    // component values (owned by caller)
    Important: Boolean;

    function IsValid: Boolean;
  end;

  TPixieCssRawDeclarationList = TList<TPixieCssRawDeclaration>;

  { TPixieCssKeepWhitespaceFunc }

  // Callback: given the token to the left and right of a whitespace token,
  // return True to keep the whitespace, False to remove it.
  TPixieCssKeepWhitespaceFunc = function(const Left, Right: TPixieCssToken): Boolean;

const
  cssCssNormComponentize    = 1;
  cssCssNormRemoveWhitespace = 2;

// Main public API

function PixieCssParseStylesheet(const Input: string; TopLevel: Boolean): TPixieCssRawRuleList; overload;
function PixieCssParseStylesheet(Tokens: TPixieCssTokenList; TopLevel: Boolean): TPixieCssRawRuleList; overload;

procedure PixieCssComponentize(Tokens: TPixieCssTokenList);

function PixieCssNormalizeStr(const Input: string;
  Options: Integer = 0; KeepWhitespace: TPixieCssKeepWhitespaceFunc = nil): TPixieCssTokenList;
function PixieCssNormalizeTokens(Tokens: TPixieCssTokenList;
  Options: Integer = 0; KeepWhitespace: TPixieCssKeepWhitespaceFunc = nil): TPixieCssTokenList;

procedure PixieCssRemoveWhitespace(Tokens: TPixieCssTokenList;
  KeepWhitespace: TPixieCssKeepWhitespaceFunc = nil);

// Parse the contents of a style block (inside { }) into declarations and nested rules.
// Caller owns the returned lists and must free each Value token list in declarations.
procedure PixieCssParseStyleBlockContents(Tokens: TPixieCssTokenList;
  out Decls: TPixieCssRawDeclarationList; out Rules: TPixieCssRawRuleList);

function PixieCssParseCommaSeparatedList(Tokens: TPixieCssTokenList): TPixieCssTokenListList;

function PixieCssIsAnyValue(Tokens: TPixieCssTokenList): Boolean;
function PixieCssIsDeclarationValue(Tokens: TPixieCssTokenList; Index: Integer = 0): Boolean;
function PixieCssSkipWhitespace(Tokens: TPixieCssTokenList; var Index: Integer): Boolean;

function PixieCssTokenClone(Source: TPixieCssToken): TPixieCssToken;
procedure PixieCssTokenListCopy(Source, Dest: TPixieCssTokenList);

implementation

{ Helpers }

function TokenAt(Tokens: TPixieCssTokenList; Index: Integer): TPixieCssToken;
begin
  // Safe access: returns a dummy EOF-like token for out-of-range indices.
  // Supports negative indices (from end).
  if Index < 0 then
    Index := Index + Tokens.Count;
  if (Index >= 0) and (Index < Tokens.Count) then
    Result := Tokens[Index]
  else
    Result := nil;
end;

function TokenTypeAt(Tokens: TPixieCssTokenList; Index: Integer): Integer;
var
  T: TPixieCssToken;
begin
  T := TokenAt(Tokens, Index);
  if T <> nil then
    Result := T.TokenType
  else
    Result := cssTokenEof;
end;

procedure TokensRemove(Tokens: TPixieCssTokenList; Index: Integer; Count: Integer = 1);
begin
  if Index < 0 then
    Index := Index + Tokens.Count;
  if (Index < 0) or (Index >= Tokens.Count) then
    Exit;
  if Count > Tokens.Count - Index then
    Count := Tokens.Count - Index;
  if Count <= 0 then
    Exit;
  Tokens.DeleteRange(Index, Count);
end;

procedure TrimWhitespace(Tokens: TPixieCssTokenList);
var
  TailStart, HeadCount: Integer;
begin
  // Trailing whitespace.
  TailStart := Tokens.Count;
  while (TailStart > 0) and
        (Tokens[TailStart - 1].TokenType = cssTokenWhitespace) do
    Dec(TailStart);
  if TailStart < Tokens.Count then
    Tokens.DeleteRange(TailStart, Tokens.Count - TailStart);
  // Leading whitespace.
  HeadCount := 0;
  while (HeadCount < Tokens.Count) and
        (Tokens[HeadCount].TokenType = cssTokenWhitespace) do
    Inc(HeadCount);
  if HeadCount > 0 then
    Tokens.DeleteRange(0, HeadCount);
end;

function MirrorBracket(C: Char): Char;
begin
  case C of
    '{': Result := '}';
    '[': Result := ']';
    '(': Result := ')';
  else
    Result := C;
  end;
end;

{ TPixieCssRawRule }

constructor TPixieCssRawRule.Create(AType: TPixieCssRuleType; const AName: string);
begin
  inherited Create;
  RuleType := AType;
  Name := AName;
  Prelude := TPixieCssTokenList.Create;
  Block := nil;
end;

destructor TPixieCssRawRule.Destroy;
begin
  Prelude.Free;
  Block.Free;
  inherited;
end;

{ TPixieCssRawDeclaration }

function TPixieCssRawDeclaration.IsValid: Boolean;
begin
  Result := Name <> '';
end;

{ TPixieCssParser - internal parser class }

type
  TPixieCssParser = class
  private
    FTokens: TPixieCssTokenList; // not owned
    FIndex: Integer;

    function NextToken: TPixieCssToken;
    function PeekToken: TPixieCssToken;
  public
    constructor Create(Tokens: TPixieCssTokenList);

    function ConsumeListOfRules(TopLevel: Boolean): TPixieCssRawRuleList;
    function ConsumeQualifiedRule: TPixieCssRawRule;
    function ConsumeAtRule: TPixieCssRawRule;
    function ConsumeSimpleBlock(OpeningBracket: Char): TPixieCssToken;
    function ConsumeComponentValue: TPixieCssToken;
    function ConsumeFunction(const FuncName: string): TPixieCssToken;
    function ConsumeDeclaration: TPixieCssRawDeclaration;
    procedure ConsumeStyleBlockContents(out Decls: TPixieCssRawDeclarationList;
      out Rules: TPixieCssRawRuleList);
  end;

constructor TPixieCssParser.Create(Tokens: TPixieCssTokenList);
begin
  inherited Create;
  FTokens := Tokens;
  FIndex := 0;
end;

// https://www.w3.org/TR/css-syntax-3/#consume-the-next-input-token
function TPixieCssParser.NextToken: TPixieCssToken;
begin
  if FIndex >= FTokens.Count then
    Result := nil
  else
  begin
    Result := FTokens[FIndex];
    Inc(FIndex);
  end;
end;

function TPixieCssParser.PeekToken: TPixieCssToken;
begin
  if FIndex >= FTokens.Count then
    Result := nil
  else
    Result := FTokens[FIndex];
end;

function GetTokenType(T: TPixieCssToken): Integer;
begin
  if T = nil then
    Result := cssTokenEof
  else
    Result := T.TokenType;
end;

function GetTokenStr(T: TPixieCssToken): string;
begin
  if T = nil then
    Result := ''
  else
    Result := T.Str;
end;

// https://www.w3.org/TR/css-syntax-3/#consume-list-of-rules
function TPixieCssParser.ConsumeListOfRules(TopLevel: Boolean): TPixieCssRawRuleList;
var
  Token: TPixieCssToken;
  TT: Integer;
  Rule: TPixieCssRawRule;
begin
  Result := TPixieCssRawRuleList.Create;
  while True do
  begin
    Token := NextToken;
    TT := GetTokenType(Token);

    case TT of
      cssTokenWhitespace:
        ; // Do nothing

      cssTokenEof:
        Exit;

      cssTokenCdo, cssTokenCdc:
      begin
        if TopLevel then
          // Do nothing
        else
        begin
          Dec(FIndex);
          Rule := ConsumeQualifiedRule;
          if Rule <> nil then
            Result.Add(Rule);
        end;
      end;

      cssTokenAtKeyword:
      begin
        Dec(FIndex);
        Rule := ConsumeAtRule;
        if Rule <> nil then
          Result.Add(Rule);
      end;

    else
      Dec(FIndex);
      Rule := ConsumeQualifiedRule;
      if Rule <> nil then
        Result.Add(Rule);
    end;
  end;
end;

// https://www.w3.org/TR/css-syntax-3/#consume-qualified-rule
function TPixieCssParser.ConsumeQualifiedRule: TPixieCssRawRule;
var
  Token: TPixieCssToken;
  TT: Integer;
  Value: TPixieCssToken;
begin
  Result := TPixieCssRawRule.Create(cssRuleQualified);
  while True do
  begin
    Token := NextToken;
    TT := GetTokenType(Token);

    case TT of
      cssTokenEof:
      begin
        // Parse error. Return nothing.
        FreeAndNil(Result);
        Exit;
      end;

      cssTokenLeftBrace: // '{'
      begin
        Result.Block := ConsumeSimpleBlock('{');
        Exit;
      end;

      cssTokenCurlyBlock:
      begin
        // Token is already a curly block - clone it for the rule
        Result.Block := TPixieCssToken.Create(Token.TokenType);
        Result.Block.Str := Token.Str;
        PixieCssTokenListCopy(Token.Value, Result.Block.Value);
        Exit;
      end;

    else
      Dec(FIndex);
      Value := ConsumeComponentValue;
      Result.Prelude.Add(Value);
    end;
  end;
end;

// https://www.w3.org/TR/css-syntax-3/#consume-at-rule
function TPixieCssParser.ConsumeAtRule: TPixieCssRawRule;
var
  Token: TPixieCssToken;
  TT: Integer;
  Value: TPixieCssToken;
  AtName: string;
begin
  Token := NextToken;
  AtName := GetTokenStr(Token);
  Result := TPixieCssRawRule.Create(cssRuleAt, AtName);

  while True do
  begin
    Token := NextToken;
    TT := GetTokenType(Token);

    case TT of
      cssTokenSemicolon: // ';'
        Exit;

      cssTokenEof:
        Exit;

      cssTokenLeftBrace: // '{'
      begin
        Result.Block := ConsumeSimpleBlock('{');
        Exit;
      end;

      cssTokenCurlyBlock:
      begin
        Result.Block := TPixieCssToken.Create(Token.TokenType);
        Result.Block.Str := Token.Str;
        PixieCssTokenListCopy(Token.Value, Result.Block.Value);
        Exit;
      end;

    else
      Dec(FIndex);
      Value := ConsumeComponentValue;
      Result.Prelude.Add(Value);
    end;
  end;
end;

// https://www.w3.org/TR/css-syntax-3/#consume-simple-block
function TPixieCssParser.ConsumeSimpleBlock(OpeningBracket: Char): TPixieCssToken;
var
  BlockType: Integer;
  ClosingBracket: Integer;
  Token: TPixieCssToken;
  TT: Integer;
  Value: TPixieCssToken;
begin
  BlockType := -100 - Ord(OpeningBracket);
  Result := TPixieCssToken.Create(BlockType);
  ClosingBracket := Ord(MirrorBracket(OpeningBracket));

  while True do
  begin
    Token := NextToken;
    TT := GetTokenType(Token);

    if TT = ClosingBracket then
      Exit
    else if TT = cssTokenEof then
      Exit
    else
    begin
      Dec(FIndex);
      Value := ConsumeComponentValue;
      Result.Value.Add(Value);
    end;
  end;
end;

// https://www.w3.org/TR/css-syntax-3/#consume-component-value
function TPixieCssParser.ConsumeComponentValue: TPixieCssToken;
var
  Token: TPixieCssToken;
  TT: Integer;
begin
  Token := NextToken;
  TT := GetTokenType(Token);

  case TT of
    cssTokenLeftBrace, cssTokenLeftBracket, cssTokenLeftParen:
      Result := ConsumeSimpleBlock(Char(TT));

    cssTokenFunction:
      Result := ConsumeFunction(GetTokenStr(Token));

  else
    // Return the token itself. We must clone it since FTokens owns it.
    Result := PixieCssTokenClone(Token);
  end;
end;

// https://www.w3.org/TR/css-syntax-3/#consume-function
function TPixieCssParser.ConsumeFunction(const FuncName: string): TPixieCssToken;
var
  Token: TPixieCssToken;
  TT: Integer;
  Value: TPixieCssToken;
begin
  Result := TPixieCssToken.Create(cssTokenCvFunction, FuncName);
  while True do
  begin
    Token := NextToken;
    TT := GetTokenType(Token);

    case TT of
      cssTokenRightParen: // ')'
        Exit;

      cssTokenEof:
        Exit;

    else
      Dec(FIndex);
      Value := ConsumeComponentValue;
      Result.Value.Add(Value);
    end;
  end;
end;

// https://www.w3.org/TR/css-syntax-3/#consume-declaration
// Next token is guaranteed to be IDENT
function TPixieCssParser.ConsumeDeclaration: TPixieCssRawDeclaration;
var
  Token: TPixieCssToken;
  Tok2: TPixieCssToken;
  BangIndex: Integer;
begin
  Token := NextToken;
  Result.Name := PixieLowerCase(GetTokenStr(Token));
  Result.Value := TPixieCssTokenList.Create;
  Result.Important := False;

  // 1. Skip whitespace
  while GetTokenType(PeekToken) = cssTokenWhitespace do
    NextToken;

  // 2. If next is not ':', parse error, return nothing
  if GetTokenType(PeekToken) <> cssTokenColon then
  begin
    Result.Name := '';
    FreeAndNil(Result.Value);
    Exit;
  end;
  NextToken; // consume ':'

  // 3. Skip whitespace
  while GetTokenType(PeekToken) = cssTokenWhitespace do
    NextToken;

  // 4. Consume component values until EOF
  while GetTokenType(PeekToken) <> cssTokenEof do
    Result.Value.Add(ConsumeComponentValue);

  // 5. Check for !important (whitespace allowed between '!' and 'important')
  TrimWhitespace(Result.Value);

  if (Result.Value.Count >= 2) then
  begin
    Tok2 := TokenAt(Result.Value, -1);
    if (Tok2 <> nil) and
       (Tok2.TokenType = cssTokenIdent) and SameText(Tok2.Str, 'important') then
    begin
      BangIndex := Result.Value.Count - 2;
      while (BangIndex >= 0) and
            (Result.Value[BangIndex].TokenType = cssTokenWhitespace) do
        Dec(BangIndex);
      if (BangIndex >= 0) and
         (Result.Value[BangIndex].TokenType = cssTokenBang) then
      begin
        TokensRemove(Result.Value, BangIndex, Result.Value.Count - BangIndex);
        Result.Important := True;
      end;
    end;
  end;

  // 6. Trim trailing whitespace
  TrimWhitespace(Result.Value);
end;

// https://www.w3.org/TR/css-syntax-3/#consume-style-block
procedure TPixieCssParser.ConsumeStyleBlockContents(
  out Decls: TPixieCssRawDeclarationList; out Rules: TPixieCssRawRuleList);
var
  Token: TPixieCssToken;
  TT: Integer;
  Rule: TPixieCssRawRule;
  Temp: TPixieCssTokenList;
  TempParser: TPixieCssParser;
  Decl: TPixieCssRawDeclaration;
begin
  Decls := TPixieCssRawDeclarationList.Create;
  Rules := TPixieCssRawRuleList.Create;

  while True do
  begin
    Token := NextToken;
    TT := GetTokenType(Token);

    case TT of
      cssTokenWhitespace, cssTokenSemicolon:
        ; // Do nothing

      cssTokenEof:
        Exit;

      cssTokenAtKeyword:
      begin
        Dec(FIndex);
        Rule := ConsumeAtRule;
        if Rule <> nil then
          Rules.Add(Rule);
      end;

      cssTokenIdent:
      begin
        // Build temporary list starting with the current ident token
        Temp := TPixieCssTokenList.Create;
        try
          Temp.Add(PixieCssTokenClone(Token));
          // Consume until ';' or EOF
          while not ((GetTokenType(PeekToken) = cssTokenSemicolon) or
                     (GetTokenType(PeekToken) = cssTokenEof)) do
            Temp.Add(ConsumeComponentValue);

          TempParser := TPixieCssParser.Create(Temp);
          try
            Decl := TempParser.ConsumeDeclaration;
            if Decl.IsValid then
            begin
              // Transfer ownership of Decl.Value to caller
              Decls.Add(Decl);
            end
            else
            begin
              // Invalid declaration - free the value list if allocated
              Decl.Value.Free;
            end;
          finally
            TempParser.Free;
          end;
        finally
          Temp.Free;
        end;
      end;

      cssTokenAmpersand:
      begin
        Dec(FIndex);
        Rule := ConsumeQualifiedRule;
        if Rule <> nil then
          Rules.Add(Rule);
      end;

    else
    begin
      // Parse error. Consume component values until ';' or EOF
      Dec(FIndex);
      while not ((GetTokenType(PeekToken) = cssTokenSemicolon) or
                 (GetTokenType(PeekToken) = cssTokenEof)) do
      begin
        Token := ConsumeComponentValue;
        Token.Free;
      end;
    end;
    end;
  end;
end;

{ Token cloning helper }

function PixieCssTokenClone(Source: TPixieCssToken): TPixieCssToken;
begin
  if Source = nil then
    Exit(nil);

  Result := TPixieCssToken.Create(Source.TokenType);
  Result.Str := Source.Str;
  Result.Number := Source.Number;
  Result.NumberType := Source.NumberType;
  Result.HashType := Source.HashType;
  Result.Repr := Source.Repr;

  if Source.IsComponentValue and (Source.Value <> nil) then
    PixieCssTokenListCopy(Source.Value, Result.Value);
end;

procedure PixieCssTokenListCopy(Source, Dest: TPixieCssTokenList);
var
  I: Integer;
begin
  if Source = nil then
    Exit;
  for I := 0 to Source.Count - 1 do
    Dest.Add(PixieCssTokenClone(Source[I]));
end;

{ Componentize }

procedure PixieCssComponentize(Tokens: TPixieCssTokenList);
var
  Parser: TPixieCssParser;
  NewTokens: TPixieCssTokenList;
  Token: TPixieCssToken;
  I: Integer;
begin
  Parser := TPixieCssParser.Create(Tokens);
  try
    NewTokens := TPixieCssTokenList.Create(True);
    try
      while True do
      begin
        Token := Parser.ConsumeComponentValue;
        if (Token = nil) or (Token.TokenType = cssTokenEof) then
        begin
          Token.Free;
          Break;
        end;
        NewTokens.Add(Token);
      end;

      // Clear old tokens (frees them since OwnsObjects=True).
      // Parser is done reading, so this is safe.
      Tokens.Clear;

      // Move new tokens to Tokens
      for I := 0 to NewTokens.Count - 1 do
        Tokens.Add(NewTokens[I]);

      // Prevent NewTokens destructor from freeing transferred tokens
      NewTokens.OwnsObjects := False;
    finally
      NewTokens.Free;
    end;
  finally
    Parser.Free;
  end;
end;

{ Remove whitespace }

procedure RemoveWhitespaceSmall(Tokens: TPixieCssTokenList;
  KeepWhitespace: TPixieCssKeepWhitespaceFunc); forward;

procedure RemoveWhitespaceLarge(Tokens: TPixieCssTokenList;
  KeepWhitespace: TPixieCssKeepWhitespaceFunc);
var
  I, N: Integer;
  Tok, Left, Right: TPixieCssToken;
  Keep: Boolean;
  Saved: array of TPixieCssToken;
  IsKept: array of Boolean;
  AnyRemoved: Boolean;
begin
  N := Tokens.Count;
  SetLength(Saved, N);
  SetLength(IsKept, N);
  AnyRemoved := False;

  // Phase 1: decide what to keep, save references, recurse into component values
  for I := 0 to N - 1 do
  begin
    Tok := Tokens[I];
    Saved[I] := Tok;
    Keep := True;

    if Tok.TokenType = cssTokenWhitespace then
    begin
      Left := TokenAt(Tokens, I - 1);
      Right := TokenAt(Tokens, I + 1);
      Keep := Assigned(KeepWhitespace) and KeepWhitespace(Left, Right);
      if not Keep then
        AnyRemoved := True;
    end
    else if Tok.IsComponentValue and (Tok.Value <> nil) then
    begin
      if Tok.Value.Count > 50 then
        RemoveWhitespaceLarge(Tok.Value, KeepWhitespace)
      else
        RemoveWhitespaceSmall(Tok.Value, KeepWhitespace);
    end;

    IsKept[I] := Keep;
  end;

  if not AnyRemoved then
    Exit;

  // Phase 2: clear list without freeing tokens
  Tokens.OwnsObjects := False;
  Tokens.Clear;
  Tokens.OwnsObjects := True;

  // Phase 3: re-add kept tokens, free removed tokens
  for I := 0 to N - 1 do
  begin
    if IsKept[I] then
      Tokens.Add(Saved[I])
    else
      Saved[I].Free;
  end;
end;

procedure RemoveWhitespaceSmall(Tokens: TPixieCssTokenList;
  KeepWhitespace: TPixieCssKeepWhitespaceFunc);
var
  I: Integer;
  Tok, Left, Right: TPixieCssToken;
  Keep: Boolean;
begin
  I := 0;
  while I < Tokens.Count do
  begin
    Tok := Tokens[I];

    if Tok.TokenType = cssTokenWhitespace then
    begin
      Left := TokenAt(Tokens, I - 1);
      Right := TokenAt(Tokens, I + 1);
      Keep := Assigned(KeepWhitespace) and KeepWhitespace(Left, Right);
      if not Keep then
      begin
        Tokens.Delete(I);
        Continue;
      end;
    end
    else if Tok.IsComponentValue and (Tok.Value <> nil) then
    begin
      if Tok.Value.Count > 50 then
        RemoveWhitespaceLarge(Tok.Value, KeepWhitespace)
      else
        RemoveWhitespaceSmall(Tok.Value, KeepWhitespace);
    end;

    Inc(I);
  end;
end;

procedure PixieCssRemoveWhitespace(Tokens: TPixieCssTokenList;
  KeepWhitespace: TPixieCssKeepWhitespaceFunc);
begin
  if Tokens.Count > 50 then
    RemoveWhitespaceLarge(Tokens, KeepWhitespace)
  else
    RemoveWhitespaceSmall(Tokens, KeepWhitespace);
end;

{ Normalize }

function PixieCssNormalizeTokens(Tokens: TPixieCssTokenList;
  Options: Integer; KeepWhitespace: TPixieCssKeepWhitespaceFunc): TPixieCssTokenList;
begin
  Result := Tokens;
  if (Options and cssCssNormComponentize) <> 0 then
    PixieCssComponentize(Result);
  if (Options and cssCssNormRemoveWhitespace) <> 0 then
    PixieCssRemoveWhitespace(Result, KeepWhitespace);
end;

function PixieCssNormalizeStr(const Input: string;
  Options: Integer; KeepWhitespace: TPixieCssKeepWhitespaceFunc): TPixieCssTokenList;
begin
  Result := PixieCssTokenize(Input);
  PixieCssNormalizeTokens(Result, Options, KeepWhitespace);
end;

{ Parse stylesheet }

function PixieCssParseStylesheet(const Input: string; TopLevel: Boolean): TPixieCssRawRuleList;
var
  Tokens: TPixieCssTokenList;
begin
  Tokens := PixieCssNormalizeStr(Input);
  try
    Result := PixieCssParseStylesheet(Tokens, TopLevel);
  finally
    Tokens.Free;
  end;
end;

function PixieCssParseStylesheet(Tokens: TPixieCssTokenList; TopLevel: Boolean): TPixieCssRawRuleList;
var
  Parser: TPixieCssParser;
begin
  Parser := TPixieCssParser.Create(Tokens);
  try
    Result := Parser.ConsumeListOfRules(TopLevel);
  finally
    Parser.Free;
  end;
end;

{ Parse style block contents }

procedure PixieCssParseStyleBlockContents(Tokens: TPixieCssTokenList;
  out Decls: TPixieCssRawDeclarationList; out Rules: TPixieCssRawRuleList);
var
  Parser: TPixieCssParser;
begin
  Parser := TPixieCssParser.Create(Tokens);
  try
    Parser.ConsumeStyleBlockContents(Decls, Rules);
  finally
    Parser.Free;
  end;
end;

{ Parse comma-separated list }

// https://www.w3.org/TR/css-syntax-3/#parse-comma-separated-list-of-component-values
// Note: result is never empty. If input is empty result is one empty list.
function PixieCssParseCommaSeparatedList(Tokens: TPixieCssTokenList): TPixieCssTokenListList;
var
  I: Integer;
  Current: TPixieCssTokenList;
  Tok: TPixieCssToken;
begin
  Result := TPixieCssTokenListList.Create;
  Current := TPixieCssTokenList.Create(False);

  for I := 0 to Tokens.Count - 1 do
  begin
    Tok := Tokens[I];
    if Tok.TokenType = cssTokenComma then
    begin
      Result.Add(Current);
      Current := TPixieCssTokenList.Create(False);
    end
    else
      Current.Add(Tok);
  end;

  Result.Add(Current);
end;

{ Validation helpers }

// https://drafts.csswg.org/css-syntax-3/#typedef-any-value
// Assumes tokens have been componentized
function PixieCssIsAnyValue(Tokens: TPixieCssTokenList): Boolean;
var
  I: Integer;
  Tok: TPixieCssToken;
begin
  if Tokens.Count = 0 then
    Exit(False);

  for I := 0 to Tokens.Count - 1 do
  begin
    Tok := Tokens[I];
    case Tok.TokenType of
      cssTokenBadString, cssTokenBadUrl,
      cssTokenRightParen, cssTokenRightBracket, cssTokenRightBrace:
        Exit(False);
    end;

    if Tok.IsComponentValue and (Tok.Value <> nil) and not PixieCssIsAnyValue(Tok.Value) then
      Exit(False);
  end;

  Result := True;
end;

// https://drafts.csswg.org/css-syntax-3/#typedef-declaration-value
// Assumes tokens have been componentized
function PixieCssIsDeclarationValue(Tokens: TPixieCssTokenList; Index: Integer): Boolean;
var
  I: Integer;
  Tok: TPixieCssToken;
begin
  if Index >= Tokens.Count then
    Exit(False);

  for I := Index to Tokens.Count - 1 do
  begin
    Tok := Tokens[I];
    case Tok.TokenType of
      cssTokenBadString, cssTokenBadUrl,
      cssTokenRightParen, cssTokenRightBracket, cssTokenRightBrace,
      cssTokenSemicolon, cssTokenBang:
        Exit(False);
    end;

    // ';' and '!' inside component values are allowed, so using is_any_value
    if Tok.IsComponentValue and (Tok.Value <> nil) and not PixieCssIsAnyValue(Tok.Value) then
      Exit(False);
  end;

  Result := True;
end;

// Note: it is possible to have several whitespace tokens in a row: "  /**/  /**/   "
function PixieCssSkipWhitespace(Tokens: TPixieCssTokenList; var Index: Integer): Boolean;
var
  Start: Integer;
begin
  Start := Index;
  while (Index < Tokens.Count) and (Tokens[Index].TokenType = cssTokenWhitespace) do
    Inc(Index);
  Result := Index <> Start;
end;

end.
