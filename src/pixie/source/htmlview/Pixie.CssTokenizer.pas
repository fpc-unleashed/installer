unit Pixie.CssTokenizer;

// CSS3 tokenizer following https://www.w3.org/TR/css-syntax-3/#tokenization

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Math, Generics.Collections, Pixie.Utils, Pixie.Utf8;

const
  // CSS token types
  // Delimiter/punctuation tokens use their ASCII ordinal as the type value.
  // Named tokens use negative values to avoid collision with Unicode chars.
  // EOF token: type = -1

  cssTokenWhitespace     = Ord(' ');  // 32
  cssTokenEof            = -1;
  cssTokenLeftBrace      = Ord('{');  // 123
  cssTokenRightBrace     = Ord('}');  // 125
  cssTokenLeftBracket    = Ord('[');  // 91
  cssTokenRightBracket   = Ord(']');  // 93
  cssTokenLeftParen      = Ord('(');  // 40
  cssTokenRightParen     = Ord(')');  // 41
  cssTokenColon          = Ord(':');  // 58
  cssTokenSemicolon      = Ord(';');  // 59
  cssTokenComma          = Ord(',');  // 44
  cssTokenBang           = Ord('!');  // 33
  cssTokenDot            = Ord('.');  // 46
  cssTokenAmpersand      = Ord('&');  // 38

  cssTokenIdent          = -20;
  cssTokenFunction       = -19;      // e.g. calc(
  cssTokenAtKeyword      = -18;      // e.g. @media
  cssTokenHash           = -17;      // e.g. #foo
  cssTokenString         = -16;      // "xxx" or 'xxx'
  cssTokenBadString      = -15;
  cssTokenUrl            = -14;      // url(x.com) - not url("x.com") which is function+string+')'
  cssTokenBadUrl         = -13;
  cssTokenNumber         = -12;
  cssTokenPercentage     = -11;      // 25%
  cssTokenDimension      = -10;      // 25px
  cssTokenCdo            = -9;       // <!--
  cssTokenCdc            = -8;       // -->

  // Component values (populated by parser, not tokenizer)
  cssTokenCvFunction     = -100;
  cssTokenCurlyBlock     = -100 - Ord('{');   // -223
  cssTokenRoundBlock     = -100 - Ord('(');   // -140
  cssTokenSquareBlock    = -100 - Ord('[');   // -191

type
  TPixieCssNumberType = (
    cssNumberInteger,
    cssNumberNumber
  );

  TPixieCssHashType = (
    cssHashUnrestricted,
    cssHashId
  );

  TPixieCssToken = class;
  TPixieCssTokenList = TObjectList<TPixieCssToken>;
  TPixieCssTokenListList = TList<TPixieCssTokenList>;

  { TPixieCssToken }
  TPixieCssToken = class
  public
    TokenType: Integer;
    Str: string;            // STRING/URL value; IDENT/HASH/AT_KEYWORD/FUNCTION name; DIMENSION unit
    Number: Single;         // NUMBER/PERCENTAGE/DIMENSION value
    NumberType: TPixieCssNumberType;
    HashType: TPixieCssHashType;
    Repr: string;           // original source text
    Value: TPixieCssTokenList;  // CV_FUNCTION, XXX_BLOCK (nil until parser sets it)

    constructor Create(AType: Integer = 0); overload;
    constructor Create(AType: Integer; ANumber: Single;
      ANumberType: TPixieCssNumberType = cssNumberInteger;
      const AStr: string = ''); overload;
    constructor Create(AType: Integer; const AStr: string); overload;
    destructor Destroy; override;

    function IsComponentValue: Boolean;
    function Ident: string;
    function GetRepr(InsertSpaces: Boolean = False): string;
  end;

function PixieCssGetRepr(Tokens: TPixieCssTokenList; Index: Integer = 0;
  Count: Integer = -1; InsertSpaces: Boolean = False): string;
function PixieCssTokenize(const Input: string): TPixieCssTokenList;

implementation

{ Helpers }

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

{ TPixieCssToken }

constructor TPixieCssToken.Create(AType: Integer);
begin
  inherited Create;
  TokenType := AType;
  if IsComponentValue then
    Value := TPixieCssTokenList.Create;
end;

constructor TPixieCssToken.Create(AType: Integer; ANumber: Single;
  ANumberType: TPixieCssNumberType; const AStr: string);
begin
  inherited Create;
  TokenType := AType;
  Number := ANumber;
  NumberType := ANumberType;
  Str := AStr;
  if IsComponentValue then
    Value := TPixieCssTokenList.Create;
end;

constructor TPixieCssToken.Create(AType: Integer; const AStr: string);
begin
  inherited Create;
  TokenType := AType;
  Str := AStr;
  if IsComponentValue then
    Value := TPixieCssTokenList.Create;
end;

destructor TPixieCssToken.Destroy;
begin
  Value.Free;
  inherited;
end;

function TPixieCssToken.IsComponentValue: Boolean;
begin
  Result := TokenType <= cssTokenCvFunction;
end;

function TPixieCssToken.Ident: string;
begin
  if TokenType <> cssTokenIdent then
    Result := ''
  else if (Length(Str) >= 2) and (Str[1] = '-') and (Str[2] = '-') then
    Result := Str   // custom properties are case-sensitive
  else
    Result := PixieLowerCase(Str);
end;

function TPixieCssToken.GetRepr(InsertSpaces: Boolean): string;
var
  OpenBracket: Char;
  CloseBracket: Char;
begin
  if not IsComponentValue then
    Exit(Repr);

  if TokenType = cssTokenCvFunction then
    Exit(Str + '(' + PixieCssGetRepr(Value, 0, -1, InsertSpaces) + ')');

  OpenBracket := Char(-TokenType - 100);
  CloseBracket := MirrorBracket(OpenBracket);
  Result := OpenBracket + PixieCssGetRepr(Value, 0, -1, InsertSpaces) + CloseBracket;
end;

{ Free functions }

function PixieCssGetRepr(Tokens: TPixieCssTokenList; Index: Integer;
  Count: Integer; InsertSpaces: Boolean): string;
var
  I: Integer;
  Space: string;
begin
  if Count < 0 then
    Count := Tokens.Count - Index;
  Result := '';
  if InsertSpaces then
    Space := ' '
  else
    Space := '';
  for I := Index to Index + Count - 1 do
    Result := Result + Tokens[I].GetRepr(InsertSpaces) + Space;
  if InsertSpaces and (Result <> '') then
    Delete(Result, Length(Result), 1);
end;

{ Input preprocessing }

function PreprocessCssInput(const S: string): string;
var
  I, J, Len: Integer;
  NeedsWork: Boolean;
begin
  Len := Length(S);
  // Quick check: does the string need any processing?
  NeedsWork := False;
  for I := 1 to Len do
    if {$IFDEF FPC}S[I] in [#0, #12, #13]{$ELSE}CharInSet(S[I], [#0, #12, #13]){$ENDIF} then
    begin
      NeedsWork := True;
      Break;
    end;
  if not NeedsWork then
    Exit(S);

  // Replace \r\n -> \n, \r -> \n, \f -> \n, NUL -> U+FFFD
  SetLength(Result, Len * 3); // worst case: all NULs expand to 3 bytes
  J := 0;
  I := 1;
  while I <= Len do
  begin
    case S[I] of
      #13: // \r
      begin
        Inc(J);
        Result[J] := #10;
        if (I < Len) and (S[I + 1] = #10) then
          Inc(I);
      end;
      #12: // \f
      begin
        Inc(J);
        Result[J] := #10;
      end;
      #0: // NUL -> U+FFFD (UTF-8: EF BF BD)
      begin
        Inc(J); Result[J] := #$EF;
        Inc(J); Result[J] := #$BF;
        Inc(J); Result[J] := #$BD;
      end;
    else
      Inc(J);
      Result[J] := S[I];
    end;
    Inc(I);
  end;
  SetLength(Result, J);
end;

{ TPixieCssTokenizer }

type
  TThreeChars = record
    C1, C2, C3: UInt32;
  end;

  TPixieCssTokenizer = class
  private
    FStr: string;         // preprocessed input + NUL sentinels
    FLen: Integer;        // actual content length (without sentinels)
    FIndex: Integer;      // 1-based index of next input char
    FCurrentChar: UInt32; // last consumed codepoint (0 at EOF)

    class function IsCssWhitespace(Ch: UInt32): Boolean; static; inline;
    class function IsNonPrintable(Ch: UInt32): Boolean; static; inline;
    class function IsIdentStart(Ch: UInt32): Boolean; static; inline;
    class function IsIdentChar(Ch: UInt32): Boolean; static; inline;

    function ByteAt(Idx: Integer): Integer; inline;
    function ConsumeChar: UInt32;
    procedure UnconsumeChar;
    function PeekChar: UInt32;
    function PeekChars: TThreeChars;

    procedure ConsumeComments;
    function ConsumeEscapedCodePoint: UInt32;
    function ConsumeStringToken(EndingCodePoint: UInt32): TPixieCssToken;

    class function WouldStartIdentSequence(const Chars: TThreeChars): Boolean; static;
    function ConsumeIdentSequence: string;

    class function WouldStartANumber(X, Y, Z: UInt32): Boolean; static;
    class function ConvertStringToNumber(const S: string): Double; static;
    function ConsumeNumber(out NumType: TPixieCssNumberType): Double;
    function ConsumeNumericToken: TPixieCssToken;

    procedure ConsumeRemnantsOfBadUrl;
    function ConsumeUrlToken: TPixieCssToken;

    function ConsumeIdentLikeToken: TPixieCssToken;
    function ConsumeToken: TPixieCssToken;

  public
    constructor Create(const Input: string);
    function Tokenize: TPixieCssTokenList;
  end;

function MakeThreeChars(A, B, C: UInt32): TThreeChars; inline;
begin
  Result.C1 := A;
  Result.C2 := B;
  Result.C3 := C;
end;

{ TPixieCssTokenizer }

constructor TPixieCssTokenizer.Create(const Input: string);
var
  Preprocessed: string;
begin
  inherited Create;
  Preprocessed := PreprocessCssInput(Input);
  FLen := Length(Preprocessed);
  // Append NUL sentinels for safe lookahead (up to 3 bytes past content)
  FStr := Preprocessed + #0#0#0;
  FIndex := 1;
  FCurrentChar := 0;
end;

class function TPixieCssTokenizer.IsCssWhitespace(Ch: UInt32): Boolean;
begin
  // \r and \f are already converted to \n in preprocessing
  Result := (Ch = 10) or (Ch = 9) or (Ch = 32);
end;

class function TPixieCssTokenizer.IsNonPrintable(Ch: UInt32): Boolean;
begin
  Result := (Ch <= 8) or (Ch = $0B) or ((Ch >= $0E) and (Ch <= $1F)) or (Ch = $7F);
end;

class function TPixieCssTokenizer.IsIdentStart(Ch: UInt32): Boolean;
begin
  Result := PixieIsAlpha(Ch) or (Ch >= $80) or (Ch = Ord('_'));
end;

class function TPixieCssTokenizer.IsIdentChar(Ch: UInt32): Boolean;
begin
  Result := IsIdentStart(Ch) or PixieIsDigit(Ch) or (Ch = Ord('-'));
end;

function TPixieCssTokenizer.ByteAt(Idx: Integer): Integer;
begin
  if (Idx >= 1) and (Idx <= Length(FStr)) then
    Result := Ord(FStr[Idx])
  else
    Result := 0;
end;

function TPixieCssTokenizer.ConsumeChar: UInt32;
begin
  if FIndex > FLen then
  begin
    FCurrentChar := 0;
    Exit(0);
  end;
  FCurrentChar := ReadUtf8Char(FStr, FIndex);
  Result := FCurrentChar;
end;

procedure TPixieCssTokenizer.UnconsumeChar;
begin
  if FCurrentChar = 0 then
    Exit;
  PrevUtf8Char(FStr, FIndex);
end;

function TPixieCssTokenizer.PeekChar: UInt32;
var
  TempIdx: Integer;
begin
  TempIdx := FIndex;
  Result := ReadUtf8Char(FStr, TempIdx);
end;

function TPixieCssTokenizer.PeekChars: TThreeChars;
var
  TempIdx: Integer;
begin
  TempIdx := FIndex;
  Result.C1 := ReadUtf8Char(FStr, TempIdx);
  Result.C2 := ReadUtf8Char(FStr, TempIdx);
  Result.C3 := ReadUtf8Char(FStr, TempIdx);
end;

// https://www.w3.org/TR/css-syntax-3/#consume-comments
procedure TPixieCssTokenizer.ConsumeComments;
var
  P: Integer;
begin
  while True do
  begin
    if (ByteAt(FIndex) = Ord('/')) and (ByteAt(FIndex + 1) = Ord('*')) then
    begin
      P := Pos('*/', FStr, FIndex + 2);
      if P > 0 then
        FIndex := P + 2
      else
      begin
        FIndex := FLen + 1;
        Break;
      end;
    end
    else
      Break;
  end;
end;

// https://www.w3.org/TR/css-syntax-3/#consume-escaped-code-point
// Assumes the backslash has already been consumed and the next char is not a newline.
function TPixieCssTokenizer.ConsumeEscapedCodePoint: UInt32;
var
  Ch: UInt32;
  Num, Max: Integer;
begin
  Ch := ConsumeChar;

  if PixieIsHexDigit(Ch) then
  begin
    Num := PixieDigitValue(Ch);
    Max := 5;
    while (Max > 0) and PixieIsHexDigit(ByteAt(FIndex)) do
    begin
      Dec(Max);
      Ch := ConsumeChar;
      Num := Num * 16 + PixieDigitValue(Ch);
    end;
    // If the next input code point is whitespace, consume it
    if IsCssWhitespace(ByteAt(FIndex)) then
      ConsumeChar;
    if (Num = 0) or PixieIsSurrogate(Num) or (Num > $10FFFF) then
      Exit($FFFD);
    Result := UInt32(Num);
  end
  else if Ch = 0 then // EOF
    Result := $FFFD
  else
    Result := Ch;
end;

// https://www.w3.org/TR/css-syntax-3/#consume-string-token
function TPixieCssTokenizer.ConsumeStringToken(EndingCodePoint: UInt32): TPixieCssToken;
var
  Ch: UInt32;
begin
  Result := TPixieCssToken.Create(cssTokenString);
  while True do
  begin
    Ch := ConsumeChar;
    if Ch = 0 then // EOF
      Exit
    else if Ch = 10 then // newline
    begin
      UnconsumeChar;
      Result.Free;
      Result := TPixieCssToken.Create(cssTokenBadString);
      Exit;
    end
    else if Ch = Ord('\') then
    begin
      if ByteAt(FIndex) = 0 then
        // next is EOF, do nothing
      else if ByteAt(FIndex) = 10 then
        Inc(FIndex)  // consume escaped newline (line continuation)
      else
        AppendUtf8Char(Result.Str, ConsumeEscapedCodePoint);
    end
    else if Ch = EndingCodePoint then
      Exit
    else
      AppendUtf8Char(Result.Str, Ch);
  end;
end;

// https://www.w3.org/TR/css-syntax-3/#would-start-an-identifier
class function TPixieCssTokenizer.WouldStartIdentSequence(const Chars: TThreeChars): Boolean;
begin
  if Chars.C1 = Ord('-') then
    Result := IsIdentStart(Chars.C2) or (Chars.C2 = Ord('-')) or
              ((Chars.C2 = Ord('\')) and (Chars.C3 <> 10))
  else if IsIdentStart(Chars.C1) then
    Result := True
  else if Chars.C1 = Ord('\') then
    Result := Chars.C2 <> 10
  else
    Result := False;
end;

// https://www.w3.org/TR/css-syntax-3/#consume-name
function TPixieCssTokenizer.ConsumeIdentSequence: string;
var
  Ch: UInt32;
  StartIdx, B: Integer;
begin
  // Fast path: scan ASCII ident chars without escape sequences
  StartIdx := FIndex;
  while FIndex <= FLen do
  begin
    B := Ord(FStr[FIndex]);
    if (B >= Ord('a')) and (B <= Ord('z')) or
       (B >= Ord('A')) and (B <= Ord('Z')) or
       (B >= Ord('0')) and (B <= Ord('9')) or
       (B = Ord('_')) or (B = Ord('-')) then
      Inc(FIndex)
    else if (B >= $80) or (B = Ord('\')) then
      Break // non-ASCII or escape — fall back to slow path
    else
    begin
      // Not an ident char — return what we have
      Result := Copy(FStr, StartIdx, FIndex - StartIdx);
      if Result <> '' then
        FCurrentChar := Ord(Result[Length(Result)]);
      Exit;
    end;
  end;

  // Either we hit end of input, or need slow path for non-ASCII/escape
  if FIndex > FLen then
  begin
    Result := Copy(FStr, StartIdx, FIndex - StartIdx);
    if Result <> '' then
      FCurrentChar := Ord(Result[Length(Result)]);
    Exit;
  end;

  // Slow path: start with what we scanned so far
  Result := Copy(FStr, StartIdx, FIndex - StartIdx);
  while True do
  begin
    Ch := ConsumeChar;
    if IsIdentChar(Ch) then
      AppendUtf8Char(Result, Ch)
    else if (Ch = Ord('\')) and (ByteAt(FIndex) <> 10) then
      AppendUtf8Char(Result, ConsumeEscapedCodePoint)
    else
    begin
      UnconsumeChar;
      Exit;
    end;
  end;
end;

// https://www.w3.org/TR/css-syntax-3/#starts-with-a-number
class function TPixieCssTokenizer.WouldStartANumber(X, Y, Z: UInt32): Boolean;
begin
  if (X = Ord('+')) or (X = Ord('-')) then
  begin
    if PixieIsDigit(Y) then
      Result := True
    else if (Y = Ord('.')) and PixieIsDigit(Z) then
      Result := True
    else
      Result := False;
  end
  else if X = Ord('.') then
    Result := PixieIsDigit(Y)
  else
    Result := PixieIsDigit(X);
end;

// https://www.w3.org/TR/css-syntax-3/#convert-string-to-number
class function TPixieCssTokenizer.ConvertStringToNumber(const S: string): Double;
var
  P, Len: Integer;
  Sign, IntPart, FracPart, FracDigits, ExpSign, ExpPart: Double;
  Mantissa, ExpVal: Double;
begin
  P := 1;
  Len := Length(S);

  // 1. Sign
  Sign := 1;
  if (P <= Len) and (S[P] = '-') then begin Sign := -1; Inc(P); end
  else if (P <= Len) and (S[P] = '+') then Inc(P);

  // 2. Integer part
  IntPart := 0;
  while (P <= Len) and PixieIsDigit(Ord(S[P])) do
  begin
    IntPart := IntPart * 10 + PixieDigitValue(Ord(S[P]));
    Inc(P);
  end;

  // 3. Decimal point
  if (P <= Len) and (S[P] = '.') then Inc(P);

  // 4. Fractional part
  FracPart := 0;
  FracDigits := 0;
  while (P <= Len) and PixieIsDigit(Ord(S[P])) do
  begin
    FracPart := FracPart * 10 + PixieDigitValue(Ord(S[P]));
    FracDigits := FracDigits + 1;
    Inc(P);
  end;

  // 5. Exponent indicator
  if (P <= Len) and ((S[P] = 'e') or (S[P] = 'E')) then Inc(P);

  // 6. Exponent sign
  ExpSign := 1;
  if (P <= Len) and (S[P] = '-') then begin ExpSign := -1; Inc(P); end
  else if (P <= Len) and (S[P] = '+') then Inc(P);

  // 7. Exponent
  ExpPart := 0;
  while (P <= Len) and PixieIsDigit(Ord(S[P])) do
  begin
    ExpPart := ExpPart * 10 + PixieDigitValue(Ord(S[P]));
    Inc(P);
  end;

  // Return s*(i + f*10^(-d))*10^(t*e)
  // Guard against FPU overflow from extreme exponents
  if FracDigits > 0 then
    Mantissa := IntPart + FracPart * Power(10, -FracDigits)
  else
    Mantissa := IntPart;
  if Mantissa = 0 then
    Result := 0
  else
  begin
    ExpVal := ExpSign * ExpPart;
    if ExpVal > 38 then
      Result := Sign * 3.4e38
    else if ExpVal < -38 then
      Result := 0
    else
      Result := Sign * Mantissa * Power(10, ExpVal);
  end;
end;

// https://www.w3.org/TR/css-syntax-3/#consume-number
function TPixieCssTokenizer.ConsumeNumber(out NumType: TPixieCssNumberType): Double;
var
  StartIdx, B: Integer;
  HasExpSign: Boolean;
begin
  NumType := cssNumberInteger;
  StartIdx := FIndex;

  // Sign
  B := ByteAt(FIndex);
  if (B = Ord('+')) or (B = Ord('-')) then
    Inc(FIndex);

  // Integer digits
  while PixieIsDigit(ByteAt(FIndex)) do
    Inc(FIndex);

  // Decimal part: '.' followed by digit
  if (ByteAt(FIndex) = Ord('.')) and PixieIsDigit(ByteAt(FIndex + 1)) then
  begin
    Inc(FIndex); // '.'
    Inc(FIndex); // first decimal digit
    NumType := cssNumberNumber;
    while PixieIsDigit(ByteAt(FIndex)) do
      Inc(FIndex);
  end;

  // Exponent part
  HasExpSign := (PixieToLower(ByteAt(FIndex)) = Ord('e'))
    and ((ByteAt(FIndex + 1) = Ord('+')) or (ByteAt(FIndex + 1) = Ord('-')))
    and PixieIsDigit(ByteAt(FIndex + 2));
  if HasExpSign or
     ((PixieToLower(ByteAt(FIndex)) = Ord('e')) and PixieIsDigit(ByteAt(FIndex + 1))) then
  begin
    Inc(FIndex); // 'e' or 'E'
    Inc(FIndex); // sign or first digit
    if HasExpSign then
      Inc(FIndex); // first digit after sign
    NumType := cssNumberNumber;
    while PixieIsDigit(ByteAt(FIndex)) do
      Inc(FIndex);
  end;

  Result := ConvertStringToNumber(Copy(FStr, StartIdx, FIndex - StartIdx));
end;

// https://www.w3.org/TR/css-syntax-3/#consume-numeric-token
function TPixieCssTokenizer.ConsumeNumericToken: TPixieCssToken;
var
  NumType: TPixieCssNumberType;
  Num: Single;
begin
  Num := ConsumeNumber(NumType);

  if WouldStartIdentSequence(PeekChars) then
  begin
    Result := TPixieCssToken.Create(cssTokenDimension, Num, NumType);
    Result.Str := ConsumeIdentSequence;
    Exit;
  end;

  if ByteAt(FIndex) = Ord('%') then
  begin
    Inc(FIndex);
    Result := TPixieCssToken.Create(cssTokenPercentage, Num);
    Exit;
  end;

  Result := TPixieCssToken.Create(cssTokenNumber, Num, NumType);
end;

// https://www.w3.org/TR/css-syntax-3/#consume-remnants-of-bad-url
procedure TPixieCssTokenizer.ConsumeRemnantsOfBadUrl;
var
  Ch: UInt32;
begin
  while True do
  begin
    Ch := ConsumeChar;
    if (Ch = Ord(')')) or (Ch = 0) then
      Exit
    else if (Ch = Ord('\')) and (ByteAt(FIndex) <> 10) then
      ConsumeEscapedCodePoint;
  end;
end;

// https://www.w3.org/TR/css-syntax-3/#consume-url-token
function TPixieCssTokenizer.ConsumeUrlToken: TPixieCssToken;
var
  Ch: UInt32;
begin
  Result := TPixieCssToken.Create(cssTokenUrl);

  // Consume leading whitespace
  while IsCssWhitespace(ByteAt(FIndex)) do
    Inc(FIndex);

  while True do
  begin
    Ch := ConsumeChar;

    if Ch = Ord(')') then
      Exit
    else if Ch = 0 then // EOF
      Exit
    else if (Ch = 10) or (Ch = 9) or (Ch = 32) then // whitespace
    begin
      while IsCssWhitespace(ByteAt(FIndex)) do
        Inc(FIndex);
      if (ByteAt(FIndex) = Ord(')')) or (ByteAt(FIndex) = 0) then
      begin
        if ByteAt(FIndex) <> 0 then
          Inc(FIndex); // consume ')'
        Exit;
      end;
      ConsumeRemnantsOfBadUrl;
      Result.Free;
      Result := TPixieCssToken.Create(cssTokenBadUrl);
      Exit;
    end
    else if (Ch = 34) or (Ch = 39) or (Ch = Ord('(')) or IsNonPrintable(Ch) then
    begin
      // " ' ( or non-printable: bad URL
      ConsumeRemnantsOfBadUrl;
      Result.Free;
      Result := TPixieCssToken.Create(cssTokenBadUrl);
      Exit;
    end
    else if Ch = Ord('\') then
    begin
      if ByteAt(FIndex) <> 10 then
        AppendUtf8Char(Result.Str, ConsumeEscapedCodePoint)
      else
      begin
        ConsumeRemnantsOfBadUrl;
        Result.Free;
        Result := TPixieCssToken.Create(cssTokenBadUrl);
        Exit;
      end;
    end
    else
      AppendUtf8Char(Result.Str, Ch);
  end;
end;

// https://www.w3.org/TR/css-syntax-3/#consume-ident-like-token
function TPixieCssTokenizer.ConsumeIdentLikeToken: TPixieCssToken;
var
  Name: string;
  Ch: Integer;
begin
  Name := ConsumeIdentSequence;

  // Unicode-range: U+hex — skip the range value so +10E60 etc.
  // are not parsed as numbers (would overflow Single).
  if (Length(Name) = 1) and SameText(Name, 'u')
    and (ByteAt(FIndex) = Ord('+')) then
  begin
    Ch := ByteAt(FIndex + 1);
    if PixieIsHexDigit(Ch) or (Ch = Ord('?')) then
    begin
      Inc(FIndex);
      while PixieIsHexDigit(ByteAt(FIndex))
        or (ByteAt(FIndex) = Ord('?')) do
        Inc(FIndex);
      if (ByteAt(FIndex) = Ord('-'))
        and PixieIsHexDigit(ByteAt(FIndex + 1)) then
      begin
        Inc(FIndex);
        while PixieIsHexDigit(ByteAt(FIndex)) do
          Inc(FIndex);
      end;
      Result := TPixieCssToken.Create(cssTokenIdent, Name);
      Exit;
    end;
  end;

  // Special handling for url(
  if SameText(Name, 'url') and (ByteAt(FIndex) = Ord('(')) then
  begin
    Inc(FIndex); // consume '('
    while IsCssWhitespace(ByteAt(FIndex)) do
      Inc(FIndex);
    if (ByteAt(FIndex) = 34) or (ByteAt(FIndex) = 39) then // " or '
    begin
      // Preserve a whitespace token before the quote
      if IsCssWhitespace(ByteAt(FIndex - 1)) then
        Dec(FIndex);
      Result := TPixieCssToken.Create(cssTokenFunction, Name);
      Exit;
    end
    else
    begin
      Result := ConsumeUrlToken;
      Exit;
    end;
  end

  // Regular function token
  else if ByteAt(FIndex) = Ord('(') then
  begin
    Inc(FIndex);
    Result := TPixieCssToken.Create(cssTokenFunction, Name);
    Exit;
  end;

  // Plain ident
  Result := TPixieCssToken.Create(cssTokenIdent, Name);
end;

// https://www.w3.org/TR/css-syntax-3/#consume-token
function TPixieCssTokenizer.ConsumeToken: TPixieCssToken;
var
  Ch: UInt32;
  Start: Integer;
  Next: TThreeChars;
begin
  ConsumeComments;
  Start := FIndex;
  Ch := ConsumeChar;

  case Ch of

    9, 10, 32: // whitespace: \t \n space
    begin
      while IsCssWhitespace(ByteAt(FIndex)) do
        Inc(FIndex);
      Result := TPixieCssToken.Create(cssTokenWhitespace);
    end;

    34, 39: // " or '
      Result := ConsumeStringToken(Ch);

    35: // #
    begin
      if IsIdentChar(PeekChar) or
         ((ByteAt(FIndex) = Ord('\')) and (ByteAt(FIndex + 1) <> 10)) then
      begin
        Result := TPixieCssToken.Create(cssTokenHash);
        if WouldStartIdentSequence(PeekChars) then
          Result.HashType := cssHashId
        else
          Result.HashType := cssHashUnrestricted;
        Result.Str := ConsumeIdentSequence;
      end
      else
        Result := TPixieCssToken.Create(Integer(Ch));
    end;

    43, 46: // + .
    begin
      Next := PeekChars;
      if WouldStartANumber(Ch, Next.C1, Next.C2) then
      begin
        UnconsumeChar;
        Result := ConsumeNumericToken;
      end
      else
        Result := TPixieCssToken.Create(Integer(Ch));
    end;

    45: // -
    begin
      Next := PeekChars;
      if WouldStartANumber(Ch, Next.C1, Next.C2) then
      begin
        UnconsumeChar;
        Result := ConsumeNumericToken;
      end
      else if (Next.C1 = Ord('-')) and (Next.C2 = Ord('>')) then
      begin
        Inc(FIndex, 2);
        Result := TPixieCssToken.Create(cssTokenCdc);
      end
      else if WouldStartIdentSequence(MakeThreeChars(Ch, Next.C1, Next.C2)) then
      begin
        UnconsumeChar;
        Result := ConsumeIdentLikeToken;
      end
      else
        Result := TPixieCssToken.Create(Integer(Ch));
    end;

    60: // <
    begin
      if PixieMatch(FStr, FIndex, '!--') then
      begin
        Inc(FIndex, 3);
        Result := TPixieCssToken.Create(cssTokenCdo);
      end
      else
        Result := TPixieCssToken.Create(Integer(Ch));
    end;

    64: // @
    begin
      if WouldStartIdentSequence(PeekChars) then
      begin
        Result := TPixieCssToken.Create(cssTokenAtKeyword);
        Result.Str := ConsumeIdentSequence;
      end
      else
        Result := TPixieCssToken.Create(Integer(Ch));
    end;

    92: // backslash
    begin
      if ByteAt(FIndex) <> 10 then
      begin
        UnconsumeChar;
        Result := ConsumeIdentLikeToken;
      end
      else
        Result := TPixieCssToken.Create(Integer(Ch));
    end;

    0: // EOF
      Result := TPixieCssToken.Create(cssTokenEof);

  else
    if PixieIsDigit(Ch) then
    begin
      UnconsumeChar;
      Result := ConsumeNumericToken;
    end
    else if IsIdentStart(Ch) then
    begin
      UnconsumeChar;
      Result := ConsumeIdentLikeToken;
    end
    else
      // Delim token: :;,()[]{}! and any other char
      Result := TPixieCssToken.Create(Integer(Ch));
  end;

  Result.Repr := Copy(FStr, Start, FIndex - Start);
end;

function TPixieCssTokenizer.Tokenize: TPixieCssTokenList;
var
  Token: TPixieCssToken;
begin
  Result := TPixieCssTokenList.Create;
  while True do
  begin
    Token := ConsumeToken;
    if Token.TokenType = cssTokenEof then
    begin
      Token.Free;
      Break;
    end;
    Result.Add(Token);
  end;
end;

{ Public API }

function PixieCssTokenize(const Input: string): TPixieCssTokenList;
var
  Tokenizer: TPixieCssTokenizer;
begin
  Tokenizer := TPixieCssTokenizer.Create(Input);
  try
    Result := Tokenizer.Tokenize;
  finally
    Tokenizer.Free;
  end;
end;

end.
