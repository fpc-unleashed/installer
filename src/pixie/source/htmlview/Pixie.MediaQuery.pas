unit Pixie.MediaQuery;

// CSS Media Queries Level 4 parsing and evaluation.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Math, Generics.Collections,
  Pixie.Types, Pixie.StringId, Pixie.Utils,
  Pixie.CssTokenizer, Pixie.CssParser;

type
  TPixieTrilean = (trilFalse, trilTrue, trilUnknown);

  TPixieMediaFeature = class;
  TPixieMediaCondition = class;

  { TPixieMediaInParens }

  TPixieMediaInParensKind = (mipFeature, mipCondition, mipGeneralEnclosed);

  TPixieMediaInParens = class
  public
    Kind: TPixieMediaInParensKind;
    Feature: TPixieMediaFeature;      // owned, nil unless Kind = mipFeature
    Condition: TPixieMediaCondition;   // owned, nil unless Kind = mipCondition

    constructor Create(AKind: TPixieMediaInParensKind);
    destructor Destroy; override;
    function Check(const Features: TPixieMediaFeatures): TPixieTrilean;
  end;

  TPixieMediaInParensList = TObjectList<TPixieMediaInParens>;

  { TPixieMediaCondition }

  TPixieMediaCondition = class
  public
    Op: Integer;  // Ord(psid_and), Ord(psid_or), Ord(psid_not)
    Conditions: TPixieMediaInParensList; // owned

    constructor Create;
    destructor Destroy; override;
    function Check(const Features: TPixieMediaFeatures): TPixieTrilean;
  end;

  { TPixieMediaFeature }

  TPixieMediaFeature = class
  public
    Name: string;
    Value: Single;
    Value2: Single;
    Op: Integer;   // comparison operator
    Op2: Integer;  // second comparison operator for range syntax

    constructor Create;
    function Compare(X: Single): Boolean; overload;
    function CompareInt(X: Integer): Boolean;
    function Check(const Features: TPixieMediaFeatures): Boolean;
  end;

  { TPixieMediaQuery }

  TPixieMediaQuery = class
  public
    IsNot: Boolean;
    MediaType: Integer;  // index into MediaTypeStrings + 1, 0 = unknown
    Condition: TPixieMediaCondition; // owned, may be nil

    constructor Create;
    destructor Destroy; override;
    function Check(const Features: TPixieMediaFeatures): TPixieTrilean;
  end;

  TPixieMediaQueryObjList = TObjectList<TPixieMediaQuery>;

  { TPixieMediaQueryList }

  TPixieMediaQueryList = class
  public
    Queries: TPixieMediaQueryObjList; // owned

    constructor Create;
    destructor Destroy; override;
    function IsEmpty: Boolean;
    function Check(const Features: TPixieMediaFeatures): Boolean;

    class function Parse(Tokens: TPixieCssTokenList): TPixieMediaQueryList; static;
    class function ParseFromString(const Str: string): TPixieMediaQueryList; static;
  end;

  TPixieMediaQueryListObjList = TObjectList<TPixieMediaQueryList>;

  { TPixieMediaQueryListList }

  TPixieMediaQueryListList = class
  public
    Lists: TPixieMediaQueryListObjList; // owned
  private
    FIsUsed: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(MqList: TPixieMediaQueryList);
    function IsUsed: Boolean;
    function ApplyMediaFeatures(const Features: TPixieMediaFeatures): Boolean;
  end;

  TPixieMediaQueryListListObjList = TObjectList<TPixieMediaQueryListList>;

implementation

const
  // Comparison operators
  OpEquals     = Ord('=');
  OpLessThan   = Ord('<');
  OpGreaterThan = Ord('>');
  OpLessEqual  = 1; // custom
  OpGreaterEqual = 2; // custom
  OpNotEqual   = 3; // custom

  // Media type constants
  MediaTypeUnknown          = 0;
  MediaTypeAll              = 1;
  MediaTypePrint            = 2;
  MediaTypeScreen           = 3;
  MediaTypeFirstDeprecated  = 4;

{ Trilean logic }

function TrilNot(X: TPixieTrilean): TPixieTrilean;
begin
  case X of
    trilFalse: Result := trilTrue;
    trilTrue:  Result := trilFalse;
  else
    Result := trilUnknown;
  end;
end;

function TrilAnd(A, B: TPixieTrilean): TPixieTrilean;
begin
  if (A = trilFalse) or (B = trilFalse) then
    Result := trilFalse
  else if (A = trilTrue) and (B = trilTrue) then
    Result := trilTrue
  else
    Result := trilUnknown;
end;

function TrilOr(A, B: TPixieTrilean): TPixieTrilean;
begin
  if (A = trilTrue) or (B = trilTrue) then
    Result := trilTrue
  else if (A = trilFalse) and (B = trilFalse) then
    Result := trilFalse
  else
    Result := trilUnknown;
end;

function BoolToTril(B: Boolean): TPixieTrilean; inline;
begin
  if B then
    Result := trilTrue
  else
    Result := trilFalse;
end;

{ Comparison helpers }

function EvalOp(X: Single; Op: Integer; Value: Single): Boolean;
const
  Epsilon = 0.00001;
begin
  if Abs(X - Value) < Epsilon then
  begin
    if (Op = OpEquals) or (Op = OpGreaterEqual) or (Op = OpLessEqual) then
      Exit(True);
    if Op = OpNotEqual then
      Exit(False);
  end;

  case Op of
    OpLessThan:     Result := X < Value;
    OpLessEqual:    Result := X <= Value;
    OpGreaterThan:  Result := X > Value;
    OpGreaterEqual: Result := X >= Value;
    OpEquals:       Result := X = Value;
    OpNotEqual:     Result := X <> Value;
  else
    Result := False;
  end;
end;

function MirrorOp(Op: Integer): Integer;
begin
  case Op of
    OpLessThan:     Result := OpGreaterThan;
    OpGreaterThan:  Result := OpLessThan;
    OpLessEqual:    Result := OpGreaterEqual;
    OpGreaterEqual: Result := OpLessEqual;
  else
    Result := Op;
  end;
end;

{ Supported media features table }

type
  TMfType = (mfRange, mfDiscrete);
  TMfValueType = (mfvLength, mfvRatio, mfvResolution, mfvInteger, mfvKeyword);

  TMfInfo = record
    FeatureType: TMfType;
    ValueType: TMfValueType;
    Keywords: array of Integer; // string_id ordinals for keyword features
    Known: Boolean;
  end;

  TPixieMfInfoMap = TDictionary<string, TMfInfo>;

function MakeMfInfo(AType: TMfType; AVType: TMfValueType): TMfInfo;
begin
  Result.FeatureType := AType;
  Result.ValueType := AVType;
  SetLength(Result.Keywords, 0);
  Result.Known := True;
end;

function MakeMfInfoKw(AType: TMfType; AVType: TMfValueType;
  const AKw: array of Integer): TMfInfo;
var
  I: Integer;
begin
  Result.FeatureType := AType;
  Result.ValueType := AVType;
  SetLength(Result.Keywords, Length(AKw));
  for I := 0 to High(AKw) do
    Result.Keywords[I] := AKw[I];
  Result.Known := True;
end;

function UnknownMfInfo: TMfInfo;
begin
  Result.Known := False;
  Result.FeatureType := mfRange;
  Result.ValueType := mfvLength;
  SetLength(Result.Keywords, 0);
end;

var
  SupportedFeatures: TPixieMfInfoMap;

procedure InitSupportedFeatures;
begin
  SupportedFeatures := TPixieMfInfoMap.Create;
  SupportedFeatures.Add('width',              MakeMfInfo(mfRange, mfvLength));
  SupportedFeatures.Add('height',             MakeMfInfo(mfRange, mfvLength));
  SupportedFeatures.Add('aspect-ratio',       MakeMfInfo(mfRange, mfvRatio));
  SupportedFeatures.Add('orientation',        MakeMfInfoKw(mfDiscrete, mfvKeyword,
    [Ord(psid_portrait), Ord(psid_landscape)]));
  SupportedFeatures.Add('prefers-color-scheme', MakeMfInfoKw(mfDiscrete, mfvKeyword,
    [Ord(psid_light), Ord(psid_dark)]));
  SupportedFeatures.Add('resolution',         MakeMfInfo(mfRange, mfvResolution));
  SupportedFeatures.Add('color',              MakeMfInfo(mfRange, mfvInteger));
  SupportedFeatures.Add('color-index',        MakeMfInfo(mfRange, mfvInteger));
  SupportedFeatures.Add('monochrome',         MakeMfInfo(mfRange, mfvInteger));
  SupportedFeatures.Add('device-width',       MakeMfInfo(mfRange, mfvLength));
  SupportedFeatures.Add('device-height',      MakeMfInfo(mfRange, mfvLength));
  SupportedFeatures.Add('device-aspect-ratio', MakeMfInfo(mfRange, mfvRatio));
end;

function GetMfInfo(const Name: string): TMfInfo;
begin
  if not SupportedFeatures.TryGetValue(Name, Result) then
    Result := UnknownMfInfo;
end;

{ Unit conversion }

function ConvertUnits(const Mfi: TMfInfo; var Val0Type: Integer;
  var Val0Number: Single; var Val0Unit: string; var Val0Ident: string;
  Val1Type: Integer; Val1Number: Single): Boolean;
var
  UnitIdx, K: Integer;
  UnitStr: string;
begin
  case Mfi.ValueType of
    mfvInteger:
    begin
      Result := (Val0Type = cssTokenNumber) and (Val1Type = 0);
      // We accept number types here without strict integer check for simplicity
    end;

    mfvLength:
    begin
      if Val1Type <> 0 then Exit(False);
      if Val0Type = cssTokenNumber then
      begin
        // Unitless zero is allowed for lengths
        if Val0Number <> 0 then Exit(False);
        // Already in px (= 0)
        Exit(True);
      end;
      if Val0Type <> cssTokenDimension then Exit(False);
      UnitStr := PixieLowerCase(Val0Unit);
      UnitIdx := PixieValueIndex(UnitStr, CssUnitsStrings);
      if UnitIdx < 0 then Exit(False);
      case TPixieCssUnits(UnitIdx) of
        cssUnitsPx:   ; // already px
        cssUnitsEm:   Val0Number := Val0Number * 16;
        cssUnitsRem:  Val0Number := Val0Number * 16;
        cssUnitsPt:   Val0Number := Val0Number * (96 / 72);
        cssUnitsPc:   Val0Number := Val0Number * (96 / 6);
        cssUnitsIn:   Val0Number := Val0Number * 96;
        cssUnitsCm:   Val0Number := Val0Number * (96 / 2.54);
        cssUnitsMm:   Val0Number := Val0Number * (96 / 25.4);
        cssUnitsEx:   Val0Number := Val0Number * 8; // approximate
        cssUnitsCh:   Val0Number := Val0Number * 8; // approximate
        cssUnitsVw:   Val0Number := Val0Number; // can't convert without viewport, keep as-is
        cssUnitsVh:   Val0Number := Val0Number;
        cssUnitsVmin: Val0Number := Val0Number;
        cssUnitsVmax: Val0Number := Val0Number;
      else
        Exit(False);
      end;
      Result := True;
    end;

    mfvResolution:
    begin
      if Val1Type <> 0 then Exit(False);
      if Val0Type = cssTokenDimension then
      begin
        UnitStr := PixieLowerCase(Val0Unit);
        if Val0Number < 0 then Exit(False);
        if (UnitStr = 'dpi') then
          // already in dpi
        else if (UnitStr = 'dpcm') then
          Val0Number := Val0Number * 2.54
        else if (UnitStr = 'dppx') or (UnitStr = 'x') then
          Val0Number := Val0Number * 96
        else
          Exit(False);
        Result := True;
      end
      else if (Val0Type = cssTokenIdent) and SameText(Val0Ident, 'infinite') then
      begin
        Val0Number := Infinity;
        Result := True;
      end
      else
        Result := False;
    end;

    mfvRatio:
    begin
      if (Val0Type = cssTokenNumber) and (Val0Number >= 0) then
      begin
        if (Val1Type = cssTokenNumber) and (Val1Number >= 0) then
        begin
          if Val1Number <> 0 then
            Val0Number := Val0Number / Val1Number
          else
            Val0Number := Infinity;
        end
        else if Val1Type <> 0 then
          Exit(False);
        Result := True;
      end
      else
        Result := False;
    end;

    mfvKeyword:
    begin
      if Val1Type <> 0 then Exit(False);
      if Val0Type <> cssTokenIdent then Exit(False);
      UnitIdx := PixieId(PixieLowerCase(Val0Ident));
      Result := False;
      for K := 0 to High(Mfi.Keywords) do
        if Mfi.Keywords[K] = UnitIdx then
        begin
          Val0Number := UnitIdx;
          Result := True;
          Break;
        end;
    end;

  else
    Result := False;
  end;
end;

{ Parse helpers }

function TokenAt(Tokens: TPixieCssTokenList; Index: Integer): TPixieCssToken;
begin
  if (Index >= 0) and (Index < Tokens.Count) then
    Result := Tokens[Index]
  else
    Result := nil;
end;

function TokenIdent(Tokens: TPixieCssTokenList; Index: Integer): string;
var
  T: TPixieCssToken;
begin
  T := TokenAt(Tokens, Index);
  if T <> nil then
    Result := T.Ident
  else
    Result := '';
end;

function TokenType(Tokens: TPixieCssTokenList; Index: Integer): Integer;
var
  T: TPixieCssToken;
begin
  T := TokenAt(Tokens, Index);
  if T <> nil then
    Result := T.TokenType
  else
    Result := cssTokenEof;
end;

function TokenCh(Tokens: TPixieCssTokenList; Index: Integer): Integer;
var
  T: TPixieCssToken;
begin
  T := TokenAt(Tokens, Index);
  if (T <> nil) and (T.TokenType > 0) and (T.TokenType < 128) then
    Result := T.TokenType
  else
    Result := 0;
end;

{ Forward declarations }

function ParseMediaCondition(Tokens: TPixieCssTokenList;
  var Index: Integer; OrAllowed: Boolean): TPixieMediaCondition; forward;
function ParseMediaInParens(Token: TPixieCssToken): TPixieMediaInParens; forward;
function ParseMediaFeature(Token: TPixieCssToken): TPixieMediaFeature; forward;

{ Parse mf-value }

// <mf-value> = <number> | <dimension> | <ident> | <ratio>
// <ratio> = <number [0,inf]> / <number [0,inf]>
// Returns True if parsed, sets Val0/Val1 tokens info
type
  TMfVal = record
    TokType: Integer;
    Number: Single;
    NumberType: TPixieCssNumberType;
    UnitStr: string;
    IdentStr: string;
  end;

function ParseMfValue(Tokens: TPixieCssTokenList; var Index: Integer;
  out Val0, Val1: TMfVal): Boolean;
var
  A, B, C: TPixieCssToken;
begin
  Val0.TokType := 0;
  Val0.Number := 0;
  Val0.NumberType := cssNumberNumber;
  Val0.UnitStr := '';
  Val0.IdentStr := '';
  Val1.TokType := 0;
  Val1.Number := 0;
  Val1.NumberType := cssNumberNumber;
  Val1.UnitStr := '';
  Val1.IdentStr := '';

  A := TokenAt(Tokens, Index);
  if A = nil then Exit(False);

  if (A.TokenType <> cssTokenNumber) and (A.TokenType <> cssTokenDimension) and
     (A.TokenType <> cssTokenIdent) then
    Exit(False);

  Val0.TokType := A.TokenType;
  Val0.IdentStr := A.Str;

  if A.TokenType = cssTokenNumber then
  begin
    Val0.Number := A.Number;
    Val0.NumberType := A.NumberType;
  end
  else if A.TokenType = cssTokenDimension then
  begin
    Val0.Number := A.Number;
    Val0.NumberType := A.NumberType;
    Val0.UnitStr := A.Str; // unit is stored in Str for dimensions after repr
    // Actually need to check how unit is stored. Let's get it from the token.
    // For dimension tokens, Str is the unit suffix and Number is the numeric value
  end;

  // Check for ratio: number / number
  B := TokenAt(Tokens, Index + 1);
  C := TokenAt(Tokens, Index + 2);
  if (A.TokenType = cssTokenNumber) and (A.Number >= 0) and
     (B <> nil) and (B.TokenType = Ord('/')) and
     (C <> nil) and (C.TokenType = cssTokenNumber) and (C.Number >= 0) then
  begin
    Val1.TokType := cssTokenNumber;
    Val1.Number := C.Number;
    Val1.NumberType := C.NumberType;
    Inc(Index, 3);
  end
  else
    Inc(Index);

  Result := True;
end;

{ Parse mf-range operator }

function ParseMfComparison(Tokens: TPixieCssTokenList; var Index: Integer;
  out Op: Integer): Boolean;
var
  Tok, Tok1: TPixieCssToken;
begin
  Tok := TokenAt(Tokens, Index);
  if Tok = nil then Exit(False);

  if Tok.TokenType = Ord('=') then
  begin
    Inc(Index);
    Op := OpEquals;
    Exit(True);
  end;

  Tok1 := TokenAt(Tokens, Index + 1);

  if Tok.TokenType = Ord('<') then
  begin
    if (Tok1 <> nil) and (Tok1.TokenType = Ord('=')) then
    begin
      Inc(Index, 2);
      Op := OpLessEqual;
    end
    else
    begin
      Inc(Index);
      Op := OpLessThan;
    end;
    Exit(True);
  end;

  if Tok.TokenType = Ord('>') then
  begin
    if (Tok1 <> nil) and (Tok1.TokenType = Ord('=')) then
    begin
      Inc(Index, 2);
      Op := OpGreaterEqual;
    end
    else
    begin
      Inc(Index);
      Op := OpGreaterThan;
    end;
    Exit(True);
  end;

  Result := False;
end;

function ParseMfLt(Tokens: TPixieCssTokenList; var Index: Integer;
  out Op: Integer): Boolean;
var
  Tok, Tok1: TPixieCssToken;
begin
  Tok := TokenAt(Tokens, Index);
  if (Tok = nil) or (Tok.TokenType <> Ord('<')) then Exit(False);
  Tok1 := TokenAt(Tokens, Index + 1);
  if (Tok1 <> nil) and (Tok1.TokenType = Ord('=')) then
  begin
    Inc(Index, 2);
    Op := OpLessEqual;
  end
  else
  begin
    Inc(Index);
    Op := OpLessThan;
  end;
  Result := True;
end;

function ParseMfGt(Tokens: TPixieCssTokenList; var Index: Integer;
  out Op: Integer): Boolean;
var
  Tok, Tok1: TPixieCssToken;
begin
  Tok := TokenAt(Tokens, Index);
  if (Tok = nil) or (Tok.TokenType <> Ord('>')) then Exit(False);
  Tok1 := TokenAt(Tokens, Index + 1);
  if (Tok1 <> nil) and (Tok1.TokenType = Ord('=')) then
  begin
    Inc(Index, 2);
    Op := OpGreaterEqual;
  end
  else
  begin
    Inc(Index);
    Op := OpGreaterThan;
  end;
  Result := True;
end;

{ Verify and convert units for a media feature }

function VerifyAndConvert(var MF: TPixieMediaFeature; Syntax: Integer;
  var Val0, Val1, Val2_0, Val2_1: TMfVal): Boolean;
var
  Mfi: TMfInfo;
  RealName: string;
begin
  if Syntax = Ord(psid_boolean) then
  begin
    Mfi := GetMfInfo(MF.Name);
    if not Mfi.Known then Exit(False);
    if Mfi.ValueType = mfvKeyword then
      MF.Value := Ord(psid_none)
    else
      MF.Value := 0;
    MF.Op := OpNotEqual;
    Exit(True);
  end;

  if Syntax = Ord(psid_plain) then
  begin
    if (Length(MF.Name) > 4) and
       ((StrLComp(PChar(MF.Name), 'min-', 4) = 0) or
        (StrLComp(PChar(MF.Name), 'max-', 4) = 0)) then
    begin
      RealName := Copy(MF.Name, 5, Length(MF.Name) - 4);
      Mfi := GetMfInfo(RealName);
      if (not Mfi.Known) or (Mfi.FeatureType = mfDiscrete) then
        Exit(False);
      if not ConvertUnits(Mfi, Val0.TokType, Val0.Number, Val0.UnitStr,
        Val0.IdentStr, Val1.TokType, Val1.Number) then
        Exit(False);
      MF.Value := Val0.Number;
      if StrLComp(PChar(MF.Name), 'min-', 4) = 0 then
        MF.Op := OpGreaterEqual
      else
        MF.Op := OpLessEqual;
      MF.Name := RealName;
      Exit(True);
    end
    else
    begin
      Mfi := GetMfInfo(MF.Name);
      if not Mfi.Known then Exit(False);
      if not ConvertUnits(Mfi, Val0.TokType, Val0.Number, Val0.UnitStr,
        Val0.IdentStr, Val1.TokType, Val1.Number) then
        Exit(False);
      MF.Value := Val0.Number;
      MF.Op := OpEquals;
      Exit(True);
    end;
  end;

  // Range syntax
  Mfi := GetMfInfo(MF.Name);
  if (not Mfi.Known) or (Mfi.FeatureType = mfDiscrete) then
    Exit(False);
  if not ConvertUnits(Mfi, Val0.TokType, Val0.Number, Val0.UnitStr,
    Val0.IdentStr, Val1.TokType, Val1.Number) then
    Exit(False);
  MF.Value := Val0.Number;
  if Val2_0.TokType <> 0 then
  begin
    if not ConvertUnits(Mfi, Val2_0.TokType, Val2_0.Number, Val2_0.UnitStr,
      Val2_0.IdentStr, Val2_1.TokType, Val2_1.Number) then
      Exit(False);
    MF.Value2 := Val2_0.Number;
  end;
  Result := True;
end;

{ ParseMediaFeature }

// <media-feature> = ( [ <mf-plain> | <mf-boolean> | <mf-range> ] )
function ParseMediaFeature(Token: TPixieCssToken): TPixieMediaFeature;
var
  Tokens: TPixieCssTokenList;
  Index: Integer;
  MF: TPixieMediaFeature;
  Val0, Val1, Val2_0, Val2_1, DummyVal0, DummyVal1: TMfVal;
  Op, Op2: Integer;
  Name: string;
begin
  if (Token = nil) or (Token.TokenType <> cssTokenRoundBlock) then Exit(nil);
  Tokens := Token.Value;
  if (Tokens = nil) or (Tokens.Count = 0) then Exit(nil);

  // Boolean: (name)
  if Tokens.Count = 1 then
  begin
    if Tokens[0].TokenType <> cssTokenIdent then Exit(nil);
    MF := TPixieMediaFeature.Create;
    MF.Name := Tokens[0].Ident;
    DummyVal0.TokType := 0;
    DummyVal1.TokType := 0;
    Val2_0.TokType := 0;
    Val2_1.TokType := 0;
    if not VerifyAndConvert(MF, Ord(psid_boolean), DummyVal0, DummyVal1, Val2_0, Val2_1) then
    begin
      MF.Free;
      Exit(nil);
    end;
    Exit(MF);
  end;

  // Plain: name : value
  if (Tokens[0].TokenType = cssTokenIdent) and
     (Tokens.Count >= 2) and (Tokens[1].TokenType = Ord(':')) then
  begin
    Index := 2;
    if not ParseMfValue(Tokens, Index, Val0, Val1) then Exit(nil);
    if Index <> Tokens.Count then Exit(nil);
    MF := TPixieMediaFeature.Create;
    MF.Name := Tokens[0].Ident;
    Val2_0.TokType := 0;
    Val2_1.TokType := 0;
    if not VerifyAndConvert(MF, Ord(psid_plain), Val0, Val1, Val2_0, Val2_1) then
    begin
      MF.Free;
      Exit(nil);
    end;
    Exit(MF);
  end;

  // Range syntax
  if Tokens.Count < 3 then Exit(nil);

  // Try: name comparison value
  Index := 0;
  if (TokenType(Tokens, 0) = cssTokenIdent) then
  begin
    Name := TokenIdent(Tokens, 0);
    // Check it's not "infinite" (which would be a value, not a name)
    if Name <> 'infinite' then
    begin
      Index := 1;
      if ParseMfComparison(Tokens, Index, Op) then
      begin
        if ParseMfValue(Tokens, Index, Val0, Val1) and (Index = Tokens.Count) then
        begin
          MF := TPixieMediaFeature.Create;
          MF.Name := Name;
          MF.Op := Op;
          Val2_0.TokType := 0;
          Val2_1.TokType := 0;
          if VerifyAndConvert(MF, Ord(psid_range), Val0, Val1, Val2_0, Val2_1) then
            Exit(MF);
          MF.Free;
        end;
      end;
    end;
  end;

  // Try: value comparison name
  Index := 0;
  if ParseMfValue(Tokens, Index, Val0, Val1) then
  begin
    if ParseMfComparison(Tokens, Index, Op) then
    begin
      if (TokenType(Tokens, Index) = cssTokenIdent) then
      begin
        Name := TokenIdent(Tokens, Index);
        if Name <> 'infinite' then
        begin
          Inc(Index);
          if Index = Tokens.Count then
          begin
            MF := TPixieMediaFeature.Create;
            MF.Name := Name;
            MF.Op := MirrorOp(Op);
            Val2_0.TokType := 0;
            Val2_1.TokType := 0;
            if VerifyAndConvert(MF, Ord(psid_range), Val0, Val1, Val2_0, Val2_1) then
              Exit(MF);
            MF.Free;
          end;
        end;
      end;
    end;
  end;

  // Try: value < name < value  or  value > name > value
  Index := 0;
  if ParseMfValue(Tokens, Index, Val0, Val1) then
  begin
    if ParseMfLt(Tokens, Index, Op) then
    begin
      if (TokenType(Tokens, Index) = cssTokenIdent) then
      begin
        Name := TokenIdent(Tokens, Index);
        if Name <> 'infinite' then
        begin
          Inc(Index);
          if ParseMfLt(Tokens, Index, Op2) then
          begin
            if ParseMfValue(Tokens, Index, Val2_0, Val2_1) and (Index = Tokens.Count) then
            begin
              MF := TPixieMediaFeature.Create;
              MF.Name := Name;
              MF.Op := Op;
              MF.Op2 := Op2;
              if VerifyAndConvert(MF, Ord(psid_range), Val0, Val1, Val2_0, Val2_1) then
                Exit(MF);
              MF.Free;
            end;
          end;
        end;
      end;
    end;
  end;

  Index := 0;
  if ParseMfValue(Tokens, Index, Val0, Val1) then
  begin
    if ParseMfGt(Tokens, Index, Op) then
    begin
      if (TokenType(Tokens, Index) = cssTokenIdent) then
      begin
        Name := TokenIdent(Tokens, Index);
        if Name <> 'infinite' then
        begin
          Inc(Index);
          if ParseMfGt(Tokens, Index, Op2) then
          begin
            if ParseMfValue(Tokens, Index, Val2_0, Val2_1) and (Index = Tokens.Count) then
            begin
              MF := TPixieMediaFeature.Create;
              MF.Name := Name;
              MF.Op := Op;
              MF.Op2 := Op2;
              if VerifyAndConvert(MF, Ord(psid_range), Val0, Val1, Val2_0, Val2_1) then
                Exit(MF);
              MF.Free;
            end;
          end;
        end;
      end;
    end;
  end;

  Result := nil;
end;

{ ParseMediaInParens }

function ParseMediaInParens(Token: TPixieCssToken): TPixieMediaInParens;
var
  Tokens: TPixieCssTokenList;
  Index: Integer;
  Cond: TPixieMediaCondition;
  Feat: TPixieMediaFeature;
begin
  if Token = nil then Exit(nil);

  // <general-enclosed>: function token
  if Token.TokenType = cssTokenCvFunction then
  begin
    if (Token.Value <> nil) and (Token.Value.Count > 0) and
       not PixieCssIsAnyValue(Token.Value) then
      Exit(nil);
    Result := TPixieMediaInParens.Create(mipGeneralEnclosed);
    Exit;
  end;

  if Token.TokenType <> cssTokenRoundBlock then Exit(nil);
  Tokens := Token.Value;

  // Try: ( <media-condition> )
  Index := 0;
  Cond := ParseMediaCondition(Tokens, Index, True);
  if (Cond <> nil) and (Index = Tokens.Count) then
  begin
    Result := TPixieMediaInParens.Create(mipCondition);
    Result.Condition := Cond;
    Exit;
  end;
  Cond.Free;

  // Try: <media-feature>
  Feat := ParseMediaFeature(Token);
  if Feat <> nil then
  begin
    Result := TPixieMediaInParens.Create(mipFeature);
    Result.Feature := Feat;
    Exit;
  end;

  // <general-enclosed>: ( any-value )
  if (Tokens = nil) or (Tokens.Count = 0) or PixieCssIsAnyValue(Tokens) then
  begin
    Result := TPixieMediaInParens.Create(mipGeneralEnclosed);
    Exit;
  end;

  Result := nil;
end;

{ ParseMediaCondition }

function ParseMediaCondition(Tokens: TPixieCssTokenList;
  var Index: Integer; OrAllowed: Boolean): TPixieMediaCondition;
var
  MIP: TPixieMediaInParens;
  Ident: string;
  Token: TPixieCssToken;
  IsOrAllowed, IsAndAllowed: Boolean;
begin
  if (Tokens = nil) or (Index >= Tokens.Count) then Exit(nil);

  // "not" prefix
  if TokenIdent(Tokens, Index) = 'not' then
  begin
    Token := TokenAt(Tokens, Index + 1);
    MIP := ParseMediaInParens(Token);
    if MIP = nil then Exit(nil);
    Result := TPixieMediaCondition.Create;
    Result.Op := Ord(psid_not);
    Result.Conditions.Add(MIP);
    Inc(Index, 2);
    Exit;
  end;

  // First media-in-parens
  Token := TokenAt(Tokens, Index);
  MIP := ParseMediaInParens(Token);
  if MIP = nil then Exit(nil);

  Result := TPixieMediaCondition.Create;
  Result.Conditions.Add(MIP);
  Inc(Index);

  IsOrAllowed := OrAllowed;
  IsAndAllowed := True;

  while True do
  begin
    Ident := TokenIdent(Tokens, Index);
    if (Ident = 'and') and IsAndAllowed then
    begin
      Result.Op := Ord(psid_and);
      IsOrAllowed := False;
    end
    else if (Ident = 'or') and IsOrAllowed then
    begin
      Result.Op := Ord(psid_or);
      IsAndAllowed := False;
    end
    else
      Break;

    Inc(Index);
    Token := TokenAt(Tokens, Index);
    MIP := ParseMediaInParens(Token);
    if MIP = nil then
    begin
      // Failed to parse, but we already have at least one condition.
      // Revert the index for the "and"/"or" keyword we consumed.
      Dec(Index);
      Break;
    end;

    Result.Conditions.Add(MIP);
    Inc(Index);
  end;
end;

{ ParseMediaQuery }

function ParseMediaQuery(Tokens: TPixieCssTokenList): TPixieMediaQuery;
var
  Index: Integer;
  Cond: TPixieMediaCondition;
  Ident: string;
  IsNot: Boolean;
  Idx: Integer;
  MT: Integer;
begin
  if (Tokens = nil) or (Tokens.Count = 0) then Exit(nil);

  // Try: <media-condition>
  Index := 0;
  Cond := ParseMediaCondition(Tokens, Index, True);
  if (Cond <> nil) and (Index = Tokens.Count) then
  begin
    Result := TPixieMediaQuery.Create;
    Result.IsNot := False;
    Result.MediaType := MediaTypeAll;
    Result.Condition := Cond;
    Exit;
  end;
  Cond.Free;

  // [ not | only ]? <media-type> [ and <media-condition-without-or> ]?
  Index := 0;
  Ident := TokenIdent(Tokens, 0);
  IsNot := False;

  if Ident = 'not' then
  begin
    Inc(Index);
    IsNot := True;
  end
  else if Ident = 'only' then
    Inc(Index);

  // <media-type>
  if Index >= Tokens.Count then Exit(nil);
  Ident := TokenIdent(Tokens, Index);
  if (Ident = '') or (Ident = 'only') or (Ident = 'not') or
     (Ident = 'and') or (Ident = 'or') or (Ident = 'layer') then
    Exit(nil);

  Idx := PixieValueIndex(Ident, MediaTypeStrings);
  if Idx < 0 then
    MT := MediaTypeUnknown
  else
    MT := Idx + 1;
  Inc(Index);

  // Optional "and" <media-condition-without-or>
  Cond := nil;
  if TokenIdent(Tokens, Index) = 'and' then
  begin
    Inc(Index);
    Cond := ParseMediaCondition(Tokens, Index, False);
    if (Cond = nil) or (Index <> Tokens.Count) then
    begin
      Cond.Free;
      Exit(nil);
    end;
  end;

  if Index <> Tokens.Count then
  begin
    Cond.Free;
    Exit(nil);
  end;

  Result := TPixieMediaQuery.Create;
  Result.IsNot := IsNot;
  Result.MediaType := MT;
  Result.Condition := Cond;
end;

{ Whitespace keep callback for media queries }

function KeepWhitespaceAroundOps(const Left, Right: TPixieCssToken): Boolean;
begin
  // Keep whitespace between < > and = so "< =" stays as two tokens
  Result := ((Left.TokenType = Ord('<')) or (Left.TokenType = Ord('>'))) and
            (Right.TokenType = Ord('='));
end;

{ TPixieMediaInParens }

constructor TPixieMediaInParens.Create(AKind: TPixieMediaInParensKind);
begin
  inherited Create;
  Kind := AKind;
  Feature := nil;
  Condition := nil;
end;

destructor TPixieMediaInParens.Destroy;
begin
  Feature.Free;
  Condition.Free;
  inherited;
end;

function TPixieMediaInParens.Check(const Features: TPixieMediaFeatures): TPixieTrilean;
begin
  case Kind of
    mipCondition:
      if Condition <> nil then
        Result := Condition.Check(Features)
      else
        Result := trilUnknown;
    mipFeature:
      if Feature <> nil then
        Result := BoolToTril(Feature.Check(Features))
      else
        Result := trilUnknown;
    mipGeneralEnclosed:
      Result := trilUnknown;
  else
    Result := trilUnknown;
  end;
end;

{ TPixieMediaCondition }

constructor TPixieMediaCondition.Create;
begin
  inherited Create;
  Op := Ord(psid_and);
  Conditions := TPixieMediaInParensList.Create;
end;

destructor TPixieMediaCondition.Destroy;
begin
  Conditions.Free;
  inherited;
end;

function TPixieMediaCondition.Check(const Features: TPixieMediaFeatures): TPixieTrilean;
var
  I: Integer;
  R: TPixieTrilean;
begin
  if Op = Ord(psid_not) then
  begin
    if Conditions.Count > 0 then
      Result := TrilNot(Conditions[0].Check(Features))
    else
      Result := trilUnknown;
    Exit;
  end;

  if Op = Ord(psid_and) then
  begin
    R := trilTrue;
    for I := 0 to Conditions.Count - 1 do
    begin
      R := TrilAnd(R, Conditions[I].Check(Features));
      if R = trilFalse then Exit(R);
    end;
    Exit(R);
  end;

  if Op = Ord(psid_or) then
  begin
    R := trilFalse;
    for I := 0 to Conditions.Count - 1 do
    begin
      R := TrilOr(R, Conditions[I].Check(Features));
      if R = trilTrue then Exit(R);
    end;
    Exit(R);
  end;

  Result := trilFalse;
end;

{ TPixieMediaFeature }

constructor TPixieMediaFeature.Create;
begin
  inherited Create;
  Value := 0;
  Value2 := 0;
  Op := 0;
  Op2 := 0;
end;

function TPixieMediaFeature.Compare(X: Single): Boolean;
begin
  if Op2 = 0 then
    Result := EvalOp(X, Op, Value)
  else
    Result := EvalOp(Value, Op, X) and EvalOp(X, Op2, Value2);
end;

function TPixieMediaFeature.CompareInt(X: Integer): Boolean;
begin
  Result := Compare(X);
end;

function TPixieMediaFeature.Check(const Features: TPixieMediaFeatures): Boolean;
var
  Id: Integer;
begin
  Id := PixieId(Name);

  if Id = Ord(psid_width) then
    Exit(Compare(Features.Width));
  if Id = Ord(psid_height) then
    Exit(Compare(Features.Height));
  if Id = Ord(psid_device_width) then
    Exit(Compare(Features.DeviceWidth));
  if Id = Ord(psid_device_height) then
    Exit(Compare(Features.DeviceHeight));
  if Id = Ord(psid_orientation) then
  begin
    if Features.Height >= Features.Width then
      Exit(Compare(Ord(psid_portrait)))
    else
      Exit(Compare(Ord(psid_landscape)));
  end;
  if Id = Ord(psid_prefers_color_scheme) then
  begin
    if Features.PrefersDark then
      Exit(Compare(Ord(psid_dark)))
    else
      Exit(Compare(Ord(psid_light)));
  end;
  if Id = Ord(psid_aspect_ratio) then
  begin
    if Features.Height <> 0 then
      Exit(Compare(Features.Width / Features.Height))
    else
      Exit(False);
  end;
  if Id = Ord(psid_device_aspect_ratio) then
  begin
    if Features.DeviceHeight <> 0 then
      Exit(Compare(Features.DeviceWidth / Features.DeviceHeight))
    else
      Exit(False);
  end;
  if Id = Ord(psid_color) then
    Exit(CompareInt(Features.Color));
  if Id = Ord(psid_color_index) then
    Exit(CompareInt(Features.ColorIndex));
  if Id = Ord(psid_monochrome) then
    Exit(CompareInt(Features.Monochrome));
  if Id = Ord(psid_resolution) then
    Exit(Compare(Features.Resolution));

  Result := False;
end;

{ TPixieMediaQuery }

constructor TPixieMediaQuery.Create;
begin
  inherited Create;
  IsNot := True;
  MediaType := MediaTypeAll;
  Condition := nil;
end;

destructor TPixieMediaQuery.Destroy;
begin
  Condition.Free;
  inherited;
end;

function TPixieMediaQuery.Check(const Features: TPixieMediaFeatures): TPixieTrilean;
var
  R: TPixieTrilean;
begin
  // Deprecated media types match nothing
  if MediaType >= MediaTypeFirstDeprecated then
    R := trilFalse
  else if MediaType = MediaTypeUnknown then
    R := trilFalse
  else if MediaType = MediaTypeAll then
    R := trilTrue
  else
    R := BoolToTril(MediaType = Ord(Features.MediaType));

  if R = trilTrue then
  begin
    if Condition <> nil then
      R := TrilAnd(R, Condition.Check(Features));
  end;

  if IsNot then
    R := TrilNot(R);

  Result := R;
end;

{ TPixieMediaQueryList }

constructor TPixieMediaQueryList.Create;
begin
  inherited Create;
  Queries := TPixieMediaQueryObjList.Create;
end;

destructor TPixieMediaQueryList.Destroy;
begin
  Queries.Free;
  inherited;
end;

function TPixieMediaQueryList.IsEmpty: Boolean;
begin
  Result := Queries.Count = 0;
end;

function TPixieMediaQueryList.Check(const Features: TPixieMediaFeatures): Boolean;
var
  I: Integer;
  R: TPixieTrilean;
begin
  if IsEmpty then
    Exit(True);

  R := trilFalse;
  for I := 0 to Queries.Count - 1 do
  begin
    R := TrilOr(R, Queries[I].Check(Features));
    if R = trilTrue then Break;
  end;

  Result := R = trilTrue;
end;

class function TPixieMediaQueryList.Parse(Tokens: TPixieCssTokenList): TPixieMediaQueryList;
var
  NormTokens: TPixieCssTokenList;
  Lists: TPixieCssTokenListList;
  I: Integer;
  Query: TPixieMediaQuery;
begin
  // Clone tokens because PixieCssNormalizeTokens modifies in-place
  NormTokens := TPixieCssTokenList.Create;
  PixieCssTokenListCopy(Tokens, NormTokens);
  PixieCssNormalizeTokens(NormTokens,
    cssCssNormComponentize or cssCssNormRemoveWhitespace,
    @KeepWhitespaceAroundOps);
  try
    if NormTokens.Count = 0 then
    begin
      Result := TPixieMediaQueryList.Create;
      Exit;
    end;

    Lists := PixieCssParseCommaSeparatedList(NormTokens);
    try
      Result := TPixieMediaQueryList.Create;
      for I := 0 to Lists.Count - 1 do
      begin
        Query := ParseMediaQuery(Lists[I]);
        if Query = nil then
        begin
          // Failed to parse — append a "not all" query per spec
          Query := TPixieMediaQuery.Create;
          Query.IsNot := True;
          Query.MediaType := MediaTypeAll;
        end;
        Result.Queries.Add(Query);
      end;
    finally
      for I := 0 to Lists.Count - 1 do
        Lists[I].Free;
      Lists.Free;
    end;
  finally
    NormTokens.Free;
  end;
end;

class function TPixieMediaQueryList.ParseFromString(const Str: string): TPixieMediaQueryList;
var
  Tokens: TPixieCssTokenList;
begin
  Tokens := PixieCssTokenize(Str);
  try
    Result := Parse(Tokens);
  finally
    Tokens.Free;
  end;
end;

{ TPixieMediaQueryListList }

constructor TPixieMediaQueryListList.Create;
begin
  inherited Create;
  Lists := TPixieMediaQueryListObjList.Create;
  FIsUsed := False;
end;

destructor TPixieMediaQueryListList.Destroy;
begin
  Lists.Free;
  inherited;
end;

procedure TPixieMediaQueryListList.Add(MqList: TPixieMediaQueryList);
begin
  Lists.Add(MqList);
end;

function TPixieMediaQueryListList.IsUsed: Boolean;
begin
  Result := FIsUsed;
end;

function TPixieMediaQueryListList.ApplyMediaFeatures(
  const Features: TPixieMediaFeatures): Boolean;
var
  Apply: Boolean;
  I: Integer;
begin
  Apply := True;
  for I := 0 to Lists.Count - 1 do
  begin
    if not Lists[I].Check(Features) then
    begin
      Apply := False;
      Break;
    end;
  end;

  Result := Apply <> FIsUsed;
  FIsUsed := Apply;
end;

initialization
  InitSupportedFeatures;

finalization
  SupportedFeatures.Free;

end.
