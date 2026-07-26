unit Pixie.Style;

// CSS declaration block and property parsing.
//
// This unit is the bridge between raw CSS parser output (token lists) and
// typed property values. It stores parsed property values in a map of
// TPixieStringId -> TPixiePropertyValue, handles shorthand expansion
// (margin, padding, border, background, font, flex, list-style, etc.),
// and provides helper functions to parse individual property values from
// token lists.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Math, Generics.Collections,
  Pixie.Types, Pixie.StringId, Pixie.Utils,
  Pixie.CssLength, Pixie.WebColor, Pixie.Borders,
  Pixie.CssTokenizer, Pixie.CssParser;

type
  // Calc resolution context — font metrics and viewport dimensions
  TCalcContext = record
    EmSize: Single;
    RemSize: Single;
    ExHeight: Single;
    ChWidth: Single;
    VwPx: Single;
    VhPx: Single;
  end;
  PCalcContext = ^TCalcContext;

  // Property value kind (what is stored in the variant-like record)
  TPixiePropertyKind = (
    pkInvalid,      // not found / empty
    pkInherit,      // "inherit" was specified
    pkInt,          // single integer (keyword index, flags)
    pkIntVector,    // comma-separated int list
    pkCssLength,    // CSS length value
    pkLengthVector, // comma-separated length list
    pkFloat,        // floating point (flex-grow, flex-shrink)
    pkColor,        // web colour
    pkString,       // font-family, content, cursor, etc.
    pkStringVector, // counter-reset, counter-increment
    pkSizeVector,   // background-size list
    pkTokenVector   // raw tokens (var(), custom properties)
  );

  { TPixiePropertyValue }
  TPixiePropertyValue = record
    Kind: TPixiePropertyKind;
    Important: Boolean;
    HasVar: Boolean;
    HasCalc: Boolean;
    IntVal: Integer;
    FloatVal: Single;
    LengthVal: TPixieCssLength;
    ColorVal: TPixieWebColor;
    StrVal: string;
    IntVecVal: TPixieIntVector;
    LengthVecVal: TPixieLengthVector;
    StringVecVal: TPixieStringVector;
    SizeVecVal: TPixieSizeVector;
    TokenVecVal: TPixieCssTokenList;

    class function Invalid: TPixiePropertyValue; static;
    class function Inherit(AImportant: Boolean): TPixiePropertyValue; static;
    class function FromInt(AVal: Integer; AImportant: Boolean): TPixiePropertyValue; static;
    class function FromLength(const AVal: TPixieCssLength; AImportant: Boolean): TPixiePropertyValue; static;
    class function FromFloat(AVal: Single; AImportant: Boolean): TPixiePropertyValue; static;
    class function FromColor(const AVal: TPixieWebColor; AImportant: Boolean): TPixiePropertyValue; static;
    class function FromString(const AVal: string; AImportant: Boolean): TPixiePropertyValue; static;
    class function FromIntVec(AVec: TPixieIntVector; AImportant: Boolean): TPixiePropertyValue; static;
    class function FromLengthVec(AVec: TPixieLengthVector; AImportant: Boolean): TPixiePropertyValue; static;
    class function FromStringVec(AVec: TPixieStringVector; AImportant: Boolean): TPixiePropertyValue; static;
    class function FromSizeVec(AVec: TPixieSizeVector; AImportant: Boolean): TPixiePropertyValue; static;
    class function FromTokenVec(AVec: TPixieCssTokenList; AImportant, AHasVar: Boolean): TPixiePropertyValue; static;

    function Clone: TPixiePropertyValue;
    procedure FreeOwnedObjects;
  end;

  TPixiePropsMap = TDictionary<Integer, TPixiePropertyValue>;

  TPixieShorthandEntry = record
    Name: Integer;
    Atoms: array of Integer;
  end;

  { TPixieStyle }
  TPixieStyle = class
  private
    FProperties: TPixiePropsMap;

    procedure InheritProperty(Name: Integer; Important: Boolean);
    procedure AddParsedProperty(Name: Integer; const PropVal: TPixiePropertyValue);
    procedure AddLengthProperty(Name: Integer; Val: TPixieCssToken;
      const Keywords: string; Options: Integer; Important: Boolean);

    procedure AddFourLengths(TopName: Integer; const Len: array of TPixieCssLength;
      N: Integer; Important: Boolean);
    procedure AddFourInts(TopName: Integer; const Vals: array of Integer;
      N: Integer; Important: Boolean);
    procedure AddFourColors(TopName: Integer; const Cols: array of TPixieWebColor;
      N: Integer; Important: Boolean);

    procedure ParseBackground(Tokens: TPixieCssTokenList; const BaseUrl: string;
      Important: Boolean);
    procedure ParseBackgroundImage(Tokens: TPixieCssTokenList; const BaseUrl: string;
      Important: Boolean);
    procedure ParseKeywordCommaList(Name: Integer; Tokens: TPixieCssTokenList;
      Important: Boolean);
    procedure ParseBackgroundPosition(Tokens: TPixieCssTokenList; Important: Boolean);
    procedure ParseBackgroundSize(Tokens: TPixieCssTokenList; Important: Boolean);

    procedure ParseBorder(Tokens: TPixieCssTokenList; Important: Boolean);
    procedure ParseBorderSide(Name: Integer; Tokens: TPixieCssTokenList; Important: Boolean);
    procedure ParseBorderRadius(Tokens: TPixieCssTokenList; Important: Boolean);
    procedure ParseOutline(Tokens: TPixieCssTokenList; Important: Boolean);

    procedure ParseListStyle(Tokens: TPixieCssTokenList; const BaseUrl: string; Important: Boolean);

    procedure ParseFont(Tokens: TPixieCssTokenList; Important: Boolean);
    procedure ParseTextDecoration(Tokens: TPixieCssTokenList; Important: Boolean);
    procedure ParseTextDecorationLine(Tokens: TPixieCssTokenList; Important: Boolean);
    procedure ParseTextEmphasis(Tokens: TPixieCssTokenList; Important: Boolean);
    procedure ParseTextEmphasisPosition(Tokens: TPixieCssTokenList; Important: Boolean);

    procedure ParseFlex(Tokens: TPixieCssTokenList; Important: Boolean);
    procedure ParseFlexFlow(Tokens: TPixieCssTokenList; Important: Boolean);
    procedure ParseAlignSelf(Name: Integer; Tokens: TPixieCssTokenList; Important: Boolean);

    procedure ParseGridTemplate(Name: Integer; Tokens: TPixieCssTokenList; Important: Boolean);
    procedure ParseGridLine(Name: Integer; Tokens: TPixieCssTokenList; Important: Boolean);

  public
    constructor Create;
    destructor Destroy; override;

    procedure Add(const Txt: string; const BaseUrl: string = ''); overload;
    procedure Add(Tokens: TPixieCssTokenList; const BaseUrl: string = ''); overload;

    procedure AddProperty(Name: Integer; Tokens: TPixieCssTokenList;
      const BaseUrl: string = ''; Important: Boolean = False); overload;
    procedure AddProperty(Name: Integer; const Val: string;
      const BaseUrl: string = ''; Important: Boolean = False); overload;

    function GetProperty(Name: Integer): TPixiePropertyValue;
    procedure Combine(Src: TPixieStyle);
    procedure Clear;

    // var() substitution — resolves CSS custom property references.
    // El is TPixieHtmlTag (passed as TObject to avoid circular dependency).
    procedure SubstVars(El: TObject);

    // Resolve deferred calc() expressions that contain context-dependent
    // units (em/rem/vw/vh). Called from Compute after font metrics are known.
    procedure ResolveCalc(const Ctx: TCalcContext);

    // Resolve a single property's deferred calc() using the supplied
    // context. Used to resolve font-size's calc before the rest of font
    // metrics are known (CSS Values 4: em in font-size = parent's font).
    procedure ResolveCalcForKey(Key: Integer; const Ctx: TCalcContext);

    property Properties: TPixiePropsMap read FProperties;
  end;

  TPixieStyleList = TObjectList<TPixieStyle>;

// Free-standing parse helpers (used by Style and later by CssProperties)
function PixieParseUrl(Token: TPixieCssToken; out Url: string): Boolean;
function PixieParseCssLength(Token: TPixieCssToken; out Len: TPixieCssLength;
  Options: Integer; const Keywords: string = ''): Boolean;
function PixieParseAngle(Token: TPixieCssToken; out Angle: Single;
  PercentsAllowed: Boolean = False): Boolean;
function PixieParseKeyword(Token: TPixieCssToken; out Val: Integer;
  const Keywords: string; FirstKeywordValue: Integer = 0): Boolean;
function PixieParseBgPosition(Tokens: TPixieCssTokenList; var Index: Integer;
  out X, Y: TPixieCssLength; ConvertKeywordsToPercents: Boolean): Boolean;
function PixieParseCssColor(Token: TPixieCssToken; out Color: TPixieWebColor): Boolean;

function PixieTokenAt(Tokens: TPixieCssTokenList; Index: Integer): TPixieCssToken;
function PixieGetValidValues(Name: Integer): string;

// Resolve var() references inside an arbitrary value string (e.g. an SVG
// presentation attribute) against the custom properties cascaded onto El.
// El is TPixieHtmlTag (passed as TObject to avoid a circular dependency).
// Returns the value with every var() substituted; the original string is
// returned unchanged when it contains no var() or cannot be resolved.
function PixieResolveCssVars(const Value: string; El: TObject): string;

implementation

uses
  Classes, Pixie.HtmlTag;

{ Valid values map: maps property string_id -> keyword strings }

type
  TValidValuesMap = TDictionary<Integer, string>;
  TPixieShorthandMap = TDictionary<Integer, TPixieIntVector>;
  TPixieIntArray = TArray<Integer>;

var
  ValidValues: TValidValuesMap;
  ShorthandMap: TPixieShorthandMap;

procedure InitValidValues;
begin
  ValidValues := TValidValuesMap.Create;

  ValidValues.Add(Ord(psid_display), StyleDisplayStrings);
  ValidValues.Add(Ord(psid_visibility), VisibilityStrings);
  ValidValues.Add(Ord(psid_user_select), UserSelectStrings);
  ValidValues.Add(Ord(psid_position), ElementPositionStrings);
  ValidValues.Add(Ord(psid_float), ElementFloatStrings);
  ValidValues.Add(Ord(psid_clear), ElementClearStrings);
  ValidValues.Add(Ord(psid_overflow), OverflowStrings);
  ValidValues.Add(Ord(psid_overflow_x), OverflowStrings);
  ValidValues.Add(Ord(psid_appearance), AppearanceStrings);
  ValidValues.Add(Ord(psid_box_sizing), BoxSizingStrings);

  ValidValues.Add(Ord(psid_text_align), TextAlignStrings);
  ValidValues.Add(Ord(psid_vertical_align), VerticalAlignStrings);
  ValidValues.Add(Ord(psid_text_transform), TextTransformStrings);
  ValidValues.Add(Ord(psid_white_space), WhiteSpaceStrings);

  ValidValues.Add(Ord(psid_font_style), FontStyleStrings);
  ValidValues.Add(Ord(psid_font_variant), FontVariantStrings);
  ValidValues.Add(Ord(psid_font_weight), FontWeightStrings);

  ValidValues.Add(Ord(psid_list_style_type), ListStyleTypeStrings);
  ValidValues.Add(Ord(psid_list_style_position), ListStylePositionStrings);

  ValidValues.Add(Ord(psid_border_left_style), BorderStyleStrings);
  ValidValues.Add(Ord(psid_border_right_style), BorderStyleStrings);
  ValidValues.Add(Ord(psid_border_top_style), BorderStyleStrings);
  ValidValues.Add(Ord(psid_border_bottom_style), BorderStyleStrings);
  ValidValues.Add(Ord(psid_border_collapse), BorderCollapseStrings);
  ValidValues.Add(Ord(psid_table_layout), TableLayoutStrings);

  ValidValues.Add(Ord(psid_background_attachment), BackgroundAttachmentStrings);
  ValidValues.Add(Ord(psid_background_repeat), BackgroundRepeatStrings);
  ValidValues.Add(Ord(psid_background_clip), BackgroundBoxStrings);
  ValidValues.Add(Ord(psid_background_origin), BackgroundBoxStrings);

  ValidValues.Add(Ord(psid_flex_direction), FlexDirectionStrings);
  ValidValues.Add(Ord(psid_flex_wrap), FlexWrapStrings);
  ValidValues.Add(Ord(psid_justify_content), FlexJustifyContentStrings);
  ValidValues.Add(Ord(psid_align_content), FlexAlignContentStrings);
  ValidValues.Add(Ord(psid_align_items), FlexAlignItemsStrings);
  ValidValues.Add(Ord(psid_align_self), FlexAlignItemsStrings);
  ValidValues.Add(Ord(psid_justify_items), FlexAlignItemsStrings);
  ValidValues.Add(Ord(psid_justify_self), FlexAlignItemsStrings);

  ValidValues.Add(Ord(psid_caption_side), CaptionSideStrings);
  ValidValues.Add(Ord(psid_overflow_wrap), OverflowWrapStrings);

  ValidValues.Add(Ord(psid_text_decoration_style), TextDecorationStyleStrings);
  ValidValues.Add(Ord(psid_text_emphasis_position), TextEmphasisPositionStrings);
end;

procedure InitShorthands;

  procedure AddShorthand(Name: Integer; const Atoms: array of Integer);
  var
    Vec: TPixieIntVector;
    I: Integer;
  begin
    Vec := TPixieIntVector.Create;
    for I := 0 to High(Atoms) do
      Vec.Add(Atoms[I]);
    ShorthandMap.Add(Name, Vec);
  end;

begin
  ShorthandMap := TPixieShorthandMap.Create;

  AddShorthand(Ord(psid_font), [
    Ord(psid_font_style), Ord(psid_font_variant), Ord(psid_font_weight),
    Ord(psid_font_size), Ord(psid_line_height), Ord(psid_font_family)]);

  AddShorthand(Ord(psid_background), [
    Ord(psid_background_color),
    Ord(psid_background_position_x), Ord(psid_background_position_y),
    Ord(psid_background_repeat), Ord(psid_background_attachment),
    Ord(psid_background_image),
    Ord(psid_background_size),
    Ord(psid_background_origin), Ord(psid_background_clip)]);

  AddShorthand(Ord(psid_list_style), [
    Ord(psid_list_style_image), Ord(psid_list_style_image_baseurl),
    Ord(psid_list_style_position), Ord(psid_list_style_type)]);

  AddShorthand(Ord(psid_margin), [
    Ord(psid_margin_top), Ord(psid_margin_right),
    Ord(psid_margin_bottom), Ord(psid_margin_left)]);
  AddShorthand(Ord(psid_padding), [
    Ord(psid_padding_top), Ord(psid_padding_right),
    Ord(psid_padding_bottom), Ord(psid_padding_left)]);

  AddShorthand(Ord(psid_border_width), [
    Ord(psid_border_top_width), Ord(psid_border_right_width),
    Ord(psid_border_bottom_width), Ord(psid_border_left_width)]);
  AddShorthand(Ord(psid_border_style), [
    Ord(psid_border_top_style), Ord(psid_border_right_style),
    Ord(psid_border_bottom_style), Ord(psid_border_left_style)]);
  AddShorthand(Ord(psid_border_color), [
    Ord(psid_border_top_color), Ord(psid_border_right_color),
    Ord(psid_border_bottom_color), Ord(psid_border_left_color)]);

  AddShorthand(Ord(psid_border_top), [
    Ord(psid_border_top_width), Ord(psid_border_top_style),
    Ord(psid_border_top_color)]);
  AddShorthand(Ord(psid_border_right), [
    Ord(psid_border_right_width), Ord(psid_border_right_style),
    Ord(psid_border_right_color)]);
  AddShorthand(Ord(psid_border_bottom), [
    Ord(psid_border_bottom_width), Ord(psid_border_bottom_style),
    Ord(psid_border_bottom_color)]);
  AddShorthand(Ord(psid_border_left), [
    Ord(psid_border_left_width), Ord(psid_border_left_style),
    Ord(psid_border_left_color)]);
  AddShorthand(Ord(psid_border), [
    Ord(psid_border_top_width), Ord(psid_border_right_width),
    Ord(psid_border_bottom_width), Ord(psid_border_left_width),
    Ord(psid_border_top_style), Ord(psid_border_right_style),
    Ord(psid_border_bottom_style), Ord(psid_border_left_style),
    Ord(psid_border_top_color), Ord(psid_border_right_color),
    Ord(psid_border_bottom_color), Ord(psid_border_left_color)]);

  AddShorthand(Ord(psid_flex), [
    Ord(psid_flex_grow), Ord(psid_flex_shrink), Ord(psid_flex_basis)]);
  AddShorthand(Ord(psid_flex_flow), [
    Ord(psid_flex_direction), Ord(psid_flex_wrap)]);
  AddShorthand(Ord(psid_gap), [
    Ord(psid_row_gap), Ord(psid_column_gap)]);
  AddShorthand(Ord(psid_grid_column), [
    Ord(psid_grid_column_start), Ord(psid_grid_column_end)]);
  AddShorthand(Ord(psid_grid_row), [
    Ord(psid_grid_row_start), Ord(psid_grid_row_end)]);

  AddShorthand(Ord(psid_outline), [
    Ord(psid_outline_width), Ord(psid_outline_style),
    Ord(psid_outline_color)]);

  AddShorthand(Ord(psid_text_decoration), [
    Ord(psid_text_decoration_color), Ord(psid_text_decoration_line),
    Ord(psid_text_decoration_style), Ord(psid_text_decoration_thickness)]);
  AddShorthand(Ord(psid_text_emphasis), [
    Ord(psid_text_emphasis_style), Ord(psid_text_emphasis_color)]);
end;

{ Helpers }

function PixieTokenAt(Tokens: TPixieCssTokenList; Index: Integer): TPixieCssToken;
begin
  if (Index >= 0) and (Index < Tokens.Count) then
    Result := Tokens[Index]
  else
    Result := nil;
end;

function TokenIdent(T: TPixieCssToken): string;
begin
  if T = nil then
    Result := ''
  else
    Result := T.Ident;
end;

function TokenType(T: TPixieCssToken): Integer;
begin
  if T = nil then
    Result := cssTokenEof
  else
    Result := T.TokenType;
end;

function TokenCh(T: TPixieCssToken): Char;
begin
  if (T <> nil) and (T.TokenType > 0) and (T.TokenType < 128) then
    Result := Char(T.TokenType)
  else
    Result := #0;
end;

function HasVarFunction(Tokens: TPixieCssTokenList): Boolean;
var
  I: Integer;
  Tok: TPixieCssToken;
begin
  for I := 0 to Tokens.Count - 1 do
  begin
    Tok := Tokens[I];
    if (Tok.TokenType = cssTokenCvFunction) and PixieStrEqualNoCase(Tok.Str, 'var') then
      Exit(True);
    if Tok.IsComponentValue and (Tok.Value <> nil) and HasVarFunction(Tok.Value) then
      Exit(True);
  end;
  Result := False;
end;

function HasCalcContextUnit(Tokens: TPixieCssTokenList): Boolean;
var
  I: Integer;
  Tok: TPixieCssToken;
  U: string;
begin
  for I := 0 to Tokens.Count - 1 do
  begin
    Tok := Tokens[I];
    if Tok.TokenType = cssTokenDimension then
    begin
      U := PixieLowerCase(Tok.Str);
      if (U = 'em') or (U = 'rem') or (U = 'ex') or (U = 'ch') or
         (U = 'vw') or (U = 'vh') or (U = 'vmin') or (U = 'vmax') then
        Exit(True);
    end;
    if Tok.IsComponentValue and (Tok.Value <> nil) and
       HasCalcContextUnit(Tok.Value) then
      Exit(True);
  end;
  Result := False;
end;

function HasDeferredCalc(Tokens: TPixieCssTokenList): Boolean;
var
  I: Integer;
  Tok: TPixieCssToken;
begin
  for I := 0 to Tokens.Count - 1 do
  begin
    Tok := Tokens[I];
    if (Tok.TokenType = cssTokenCvFunction) and
       (PixieStrEqualNoCase(Tok.Str, 'calc') or
        PixieStrEqualNoCase(Tok.Str, 'min') or
        PixieStrEqualNoCase(Tok.Str, 'max') or
        PixieStrEqualNoCase(Tok.Str, 'clamp')) and
       (Tok.Value <> nil) and HasCalcContextUnit(Tok.Value) then
      Exit(True);
    if Tok.IsComponentValue and (Tok.Value <> nil) and
       HasDeferredCalc(Tok.Value) then
      Exit(True);
  end;
  Result := False;
end;

function PixieGetValidValues(Name: Integer): string;
begin
  if not ValidValues.TryGetValue(Name, Result) then
    Result := '';
end;

function IsOneOfId(Val: Integer; A, B: Integer): Boolean; inline;
begin
  Result := (Val = A) or (Val = B);
end;

function IsOneOfId3(Val: Integer; A, B, C: Integer): Boolean; inline;
begin
  Result := (Val = A) or (Val = B) or (Val = C);
end;

function IsOneOfStr(const Val: string; const A, B: string): Boolean; inline;
begin
  Result := (Val = A) or (Val = B);
end;

function IsOneOfStr3(const Val: string; const A, B, C: string): Boolean; inline;
begin
  Result := (Val = A) or (Val = B) or (Val = C);
end;

function IsOneOfStr4(const Val: string; const A, B, C, D: string): Boolean; inline;
begin
  Result := (Val = A) or (Val = B) or (Val = C) or (Val = D);
end;

{ TPixiePropertyValue }

class function TPixiePropertyValue.Invalid: TPixiePropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := pkInvalid;
  Result.StrVal := '';
end;

class function TPixiePropertyValue.Inherit(AImportant: Boolean): TPixiePropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := pkInherit;
  Result.Important := AImportant;
  Result.StrVal := '';
end;

class function TPixiePropertyValue.FromInt(AVal: Integer; AImportant: Boolean): TPixiePropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := pkInt;
  Result.IntVal := AVal;
  Result.Important := AImportant;
  Result.StrVal := '';
end;

class function TPixiePropertyValue.FromLength(const AVal: TPixieCssLength; AImportant: Boolean): TPixiePropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := pkCssLength;
  Result.LengthVal := AVal;
  Result.Important := AImportant;
  Result.StrVal := '';
end;

class function TPixiePropertyValue.FromFloat(AVal: Single; AImportant: Boolean): TPixiePropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := pkFloat;
  Result.FloatVal := AVal;
  Result.Important := AImportant;
  Result.StrVal := '';
end;

class function TPixiePropertyValue.FromColor(const AVal: TPixieWebColor; AImportant: Boolean): TPixiePropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := pkColor;
  Result.ColorVal := AVal;
  Result.Important := AImportant;
  Result.StrVal := '';
end;

class function TPixiePropertyValue.FromString(const AVal: string; AImportant: Boolean): TPixiePropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := pkString;
  Result.StrVal := AVal;
  Result.Important := AImportant;
end;

class function TPixiePropertyValue.FromIntVec(AVec: TPixieIntVector; AImportant: Boolean): TPixiePropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := pkIntVector;
  Result.IntVecVal := AVec;
  Result.Important := AImportant;
  Result.StrVal := '';
end;

class function TPixiePropertyValue.FromLengthVec(AVec: TPixieLengthVector; AImportant: Boolean): TPixiePropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := pkLengthVector;
  Result.LengthVecVal := AVec;
  Result.Important := AImportant;
  Result.StrVal := '';
end;

class function TPixiePropertyValue.FromStringVec(AVec: TPixieStringVector; AImportant: Boolean): TPixiePropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := pkStringVector;
  Result.StringVecVal := AVec;
  Result.Important := AImportant;
  Result.StrVal := '';
end;

class function TPixiePropertyValue.FromSizeVec(AVec: TPixieSizeVector; AImportant: Boolean): TPixiePropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := pkSizeVector;
  Result.SizeVecVal := AVec;
  Result.Important := AImportant;
  Result.StrVal := '';
end;

class function TPixiePropertyValue.FromTokenVec(AVec: TPixieCssTokenList; AImportant, AHasVar: Boolean): TPixiePropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := pkTokenVector;
  Result.TokenVecVal := AVec;
  Result.Important := AImportant;
  Result.HasVar := AHasVar;
  Result.StrVal := '';
end;

function TPixiePropertyValue.Clone: TPixiePropertyValue;
begin
  Result := Self;
  // Deep-copy owned objects so source and clone are independent
  if IntVecVal <> nil then
  begin
    Result.IntVecVal := TPixieIntVector.Create;
    Result.IntVecVal.AddRange(IntVecVal);
  end;
  if LengthVecVal <> nil then
  begin
    Result.LengthVecVal := TPixieLengthVector.Create;
    Result.LengthVecVal.AddRange(LengthVecVal);
  end;
  if StringVecVal <> nil then
  begin
    Result.StringVecVal := TPixieStringVector.Create;
    Result.StringVecVal.AddRange(StringVecVal);
  end;
  if SizeVecVal <> nil then
  begin
    Result.SizeVecVal := TPixieSizeVector.Create;
    Result.SizeVecVal.AddRange(SizeVecVal);
  end;
  if TokenVecVal <> nil then
  begin
    Result.TokenVecVal := TPixieCssTokenList.Create;
    PixieCssTokenListCopy(TokenVecVal, Result.TokenVecVal);
  end;
end;

procedure TPixiePropertyValue.FreeOwnedObjects;
begin
  FreeAndNil(IntVecVal);
  FreeAndNil(LengthVecVal);
  FreeAndNil(StringVecVal);
  FreeAndNil(SizeVecVal);
  FreeAndNil(TokenVecVal);
end;

{ Forward declarations }
function ParseColorFunction(const FuncName: string; Args: TPixieCssTokenList;
  out Color: TPixieWebColor): Boolean; forward;

{ Free-standing parse helpers }

function PixieParseUrl(Token: TPixieCssToken; out Url: string): Boolean;
begin
  Result := False;
  if Token = nil then
    Exit;

  if Token.TokenType = cssTokenUrl then
  begin
    Url := PixieTrim(Token.Str);
    Exit(True);
  end;

  if (Token.TokenType = cssTokenCvFunction) and
     IsOneOfStr(PixieLowerCase(Token.Str), 'url', 'src') and
     (Token.Value <> nil) and (Token.Value.Count = 1) and
     (Token.Value[0].TokenType = cssTokenString) then
  begin
    Url := PixieTrim(Token.Value[0].Str);
    Exit(True);
  end;
end;

// --- calc() expression evaluator ---
// Evaluates calc() into a dual-value form: absolutePx + percentCoeff.
// Supports +, -, *, / with correct precedence.
// Context-dependent units (em/rem/vw/vh/vmin/vmax/ex/ch) are resolved
// when GCalcCtx is set; otherwise they cause evaluation to fail so the
// property is deferred until Compute provides the context.

type
  TCalcValue = record
    Px: Single;
    Pct: Single;
  end;

var
  GCalcCtx: PCalcContext = nil;

function CalcTokenToValue(Tok: TPixieCssToken; out V: TCalcValue): Boolean;
var
  UnitStr: string;
begin
  Result := False;
  V.Px := 0;
  V.Pct := 0;
  if Tok = nil then Exit;

  if Tok.TokenType = cssTokenPercentage then
  begin
    V.Pct := Tok.Number;
    Exit(True);
  end;

  if Tok.TokenType = cssTokenNumber then
  begin
    if Tok.Number = 0 then
      Exit(True); // zero is valid
    // Unitless non-zero: only valid as multiplier, handled by caller
    V.Px := Tok.Number;
    Exit(True);
  end;

  if Tok.TokenType = cssTokenDimension then
  begin
    UnitStr := PixieLowerCase(Tok.Str);
    if UnitStr = 'px' then
      V.Px := Tok.Number
    else if UnitStr = 'pt' then
      V.Px := Tok.Number * 96 / 72
    else if UnitStr = 'in' then
      V.Px := Tok.Number * 96
    else if UnitStr = 'cm' then
      V.Px := Tok.Number * 96 / 2.54
    else if UnitStr = 'mm' then
      V.Px := Tok.Number * 96 / 25.4
    else if UnitStr = 'pc' then
      V.Px := Tok.Number * 96 / 6
    else if GCalcCtx <> nil then
    begin
      if UnitStr = 'em' then
        V.Px := Tok.Number * GCalcCtx^.EmSize
      else if UnitStr = 'rem' then
        V.Px := Tok.Number * GCalcCtx^.RemSize
      else if UnitStr = 'ex' then
      begin
        // ExHeight/ChWidth = 0 means the metric isn't available yet
        // (e.g. font-size pre-pass); refuse to resolve so the property
        // stays deferred for the later full pass.
        if GCalcCtx^.ExHeight = 0 then Exit(False);
        V.Px := Tok.Number * GCalcCtx^.ExHeight;
      end
      else if UnitStr = 'ch' then
      begin
        if GCalcCtx^.ChWidth = 0 then Exit(False);
        V.Px := Tok.Number * GCalcCtx^.ChWidth;
      end
      else if UnitStr = 'vw' then
        V.Px := Tok.Number * GCalcCtx^.VwPx / 100
      else if UnitStr = 'vh' then
        V.Px := Tok.Number * GCalcCtx^.VhPx / 100
      else if UnitStr = 'vmin' then
        V.Px := Tok.Number * Min(GCalcCtx^.VwPx, GCalcCtx^.VhPx) / 100
      else if UnitStr = 'vmax' then
        V.Px := Tok.Number * Max(GCalcCtx^.VwPx, GCalcCtx^.VhPx) / 100
      else
        Exit(False);
    end
    else
      Exit(False);
    Exit(True);
  end;
end;

function PixieParseCalcExpression(Tokens: TPixieCssTokenList;
  out Len: TPixieCssLength): Boolean; forward;

function EvalCalcSum(Tokens: TPixieCssTokenList; var Pos: Integer;
  out V: TCalcValue): Boolean; forward;

function EvalCalcValue(Tokens: TPixieCssTokenList; var Pos: Integer;
  out V: TCalcValue): Boolean;
var
  Tok: TPixieCssToken;
  InnerPos: Integer;
begin
  Result := False;
  // Skip whitespace
  while (Pos < Tokens.Count) and (Tokens[Pos].TokenType = cssTokenWhitespace) do
    Inc(Pos);
  if Pos >= Tokens.Count then Exit;

  Tok := Tokens[Pos];

  // Nested calc()
  if (Tok.TokenType = cssTokenCvFunction) and
     (PixieLowerCase(Tok.Str) = 'calc') then
  begin
    InnerPos := 0;
    Result := EvalCalcSum(Tok.Value, InnerPos, V);
    if Result then
      Inc(Pos);
    Exit;
  end;

  // Parenthesized sub-expression
  if Tok.TokenType = cssTokenRoundBlock then
  begin
    InnerPos := 0;
    Result := EvalCalcSum(Tok.Value, InnerPos, V);
    if Result then
      Inc(Pos);
    Exit;
  end;

  // Simple value
  Result := CalcTokenToValue(Tok, V);
  if Result then
    Inc(Pos);
end;

function EvalCalcProduct(Tokens: TPixieCssTokenList; var Pos: Integer;
  out V: TCalcValue): Boolean;
var
  Right: TCalcValue;
  Op: Integer;
begin
  Result := EvalCalcValue(Tokens, Pos, V);
  if not Result then Exit;

  while Pos < Tokens.Count do
  begin
    // Skip whitespace
    while (Pos < Tokens.Count) and (Tokens[Pos].TokenType = cssTokenWhitespace) do
      Inc(Pos);
    if Pos >= Tokens.Count then Break;

    Op := Tokens[Pos].TokenType;
    if (Op <> Ord('*')) and (Op <> Ord('/')) then
      Break;
    Inc(Pos);

    if not EvalCalcValue(Tokens, Pos, Right) then
      Exit(False);

    if Op = Ord('*') then
    begin
      // One operand must be unitless (plain number with no percentage)
      if (V.Pct = 0) and (Right.Pct = 0) then
        V.Px := V.Px * Right.Px
      else if V.Pct = 0 then
      begin
        // Left is plain number, right has units
        Right.Px := Right.Px * V.Px;
        Right.Pct := Right.Pct * V.Px;
        V := Right;
      end
      else
      begin
        // Left has units, right should be plain number
        V.Px := V.Px * Right.Px;
        V.Pct := V.Pct * Right.Px;
      end;
    end
    else // division
    begin
      if Right.Px = 0 then
        Exit(False); // division by zero
      if Right.Pct <> 0 then
        Exit(False); // can't divide by percentage
      V.Px := V.Px / Right.Px;
      V.Pct := V.Pct / Right.Px;
    end;
  end;
end;

function EvalCalcSum(Tokens: TPixieCssTokenList; var Pos: Integer;
  out V: TCalcValue): Boolean;
var
  Right: TCalcValue;
  Op: Integer;
  SavePos: Integer;
begin
  // Skip leading whitespace
  while (Pos < Tokens.Count) and (Tokens[Pos].TokenType = cssTokenWhitespace) do
    Inc(Pos);

  Result := EvalCalcProduct(Tokens, Pos, V);
  if not Result then Exit;

  while Pos < Tokens.Count do
  begin
    // + and - must be surrounded by whitespace per CSS spec
    // Pattern: WS op WS
    SavePos := Pos;
    while (Pos < Tokens.Count) and (Tokens[Pos].TokenType = cssTokenWhitespace) do
      Inc(Pos);
    if Pos >= Tokens.Count then Break;

    Op := Tokens[Pos].TokenType;
    if (Op <> Ord('+')) and (Op <> Ord('-')) then
    begin
      Pos := SavePos; // not an operator, put back
      Break;
    end;
    Inc(Pos);

    // Skip whitespace after operator
    while (Pos < Tokens.Count) and (Tokens[Pos].TokenType = cssTokenWhitespace) do
      Inc(Pos);

    if not EvalCalcProduct(Tokens, Pos, Right) then
      Exit(False);

    if Op = Ord('+') then
    begin
      V.Px := V.Px + Right.Px;
      V.Pct := V.Pct + Right.Pct;
    end
    else
    begin
      V.Px := V.Px - Right.Px;
      V.Pct := V.Pct - Right.Pct;
    end;
  end;
end;

function PixieParseCalcExpression(Tokens: TPixieCssTokenList;
  out Len: TPixieCssLength): Boolean;
var
  V: TCalcValue;
  Pos: Integer;
begin
  Result := False;
  if (Tokens = nil) or (Tokens.Count = 0) then Exit;
  Pos := 0;
  if not EvalCalcSum(Tokens, Pos, V) then Exit;
  Len := TPixieCssLength.CreateCalc(V.Px, V.Pct);
  Result := True;
end;

function IsMathFuncName(const S: string): Boolean;
var
  LowerS: string;
begin
  LowerS := PixieLowerCase(S);
  Result := (LowerS = 'min') or (LowerS = 'max') or (LowerS = 'clamp');
end;

// Parse min()/max()/clamp(). Each comma-separated argument is evaluated to a
// linear (px + percentage) term via the calc evaluator, so context units
// (em/rem/vw...) and nested calc() work exactly as in calc(). min()/max() fold
// their pure-px and pure-% arguments together (both monotonic in the basis),
// keeping any mixed term separate; clamp() keeps its three positional terms.
function PixieParseMathFunction(const FuncName: string;
  Tokens: TPixieCssTokenList; out Len: TPixieCssLength): Boolean;
var
  Kind: TPixieMathKind;
  ArgPx, ArgPct, FinalPx, FinalPct: array of Single;
  V: TCalcValue;
  Pos, I, N: Integer;
  FoldPx, FoldPct: Single;
  HasPx, HasPct: Boolean;
  LowerName: string;

  procedure AddFinal(APx, APct: Single);
  begin
    SetLength(FinalPx, Length(FinalPx) + 1);
    SetLength(FinalPct, Length(FinalPct) + 1);
    FinalPx[High(FinalPx)] := APx;
    FinalPct[High(FinalPct)] := APct;
  end;

begin
  Result := False;
  if (Tokens = nil) or (Tokens.Count = 0) then Exit;
  LowerName := PixieLowerCase(FuncName);
  if LowerName = 'min' then Kind := mkMin
  else if LowerName = 'max' then Kind := mkMax
  else if LowerName = 'clamp' then Kind := mkClamp
  else Exit;

  // Collect each argument as a linear term.
  SetLength(ArgPx, 0);
  SetLength(ArgPct, 0);
  Pos := 0;
  while True do
  begin
    if not EvalCalcSum(Tokens, Pos, V) then Exit;
    SetLength(ArgPx, Length(ArgPx) + 1);
    SetLength(ArgPct, Length(ArgPct) + 1);
    ArgPx[High(ArgPx)] := V.Px;
    ArgPct[High(ArgPct)] := V.Pct;
    while (Pos < Tokens.Count) and (Tokens[Pos].TokenType = cssTokenWhitespace) do
      Inc(Pos);
    if Pos >= Tokens.Count then Break;
    if Tokens[Pos].TokenType = cssTokenComma then
    begin
      Inc(Pos);
      Continue;
    end;
    Exit; // unexpected token in the argument list
  end;
  N := Length(ArgPx);

  if Kind = mkClamp then
  begin
    if N <> 3 then Exit;
    Len := TPixieCssLength.CreateMath(mkClamp,
      [ArgPx[0], ArgPx[1], ArgPx[2]],
      [ArgPct[0], ArgPct[1], ArgPct[2]]);
    Exit(True);
  end;

  if N < 1 then Exit;
  SetLength(FinalPx, 0);
  SetLength(FinalPct, 0);
  HasPx := False;
  HasPct := False;
  FoldPx := 0;
  FoldPct := 0;
  for I := 0 to N - 1 do
  begin
    if ArgPct[I] = 0 then
    begin
      if not HasPx then FoldPx := ArgPx[I]
      else if Kind = mkMin then FoldPx := Min(FoldPx, ArgPx[I])
      else FoldPx := Max(FoldPx, ArgPx[I]);
      HasPx := True;
    end
    else if ArgPx[I] = 0 then
    begin
      if not HasPct then FoldPct := ArgPct[I]
      else if Kind = mkMin then FoldPct := Min(FoldPct, ArgPct[I])
      else FoldPct := Max(FoldPct, ArgPct[I]);
      HasPct := True;
    end
    else
      AddFinal(ArgPx[I], ArgPct[I]);
  end;
  if HasPx then AddFinal(FoldPx, 0);
  if HasPct then AddFinal(0, FoldPct);

  N := Length(FinalPx);
  // Storage holds at most three terms (term 0 plus two extras).
  if (N < 1) or (N > 3) then Exit;
  Len := TPixieCssLength.CreateMath(Kind, FinalPx, FinalPct);
  Result := True;
end;

function PixieParseCssLength(Token: TPixieCssToken; out Len: TPixieCssLength;
  Options: Integer; const Keywords: string): Boolean;
var
  Idx: Integer;
  UnitStr: string;
  UnitIdx: Integer;
begin
  Result := False;
  if Token = nil then
    Exit;

  // Try keyword
  if (Keywords <> '') and (Token.TokenType = cssTokenIdent) then
  begin
    Idx := PixieValueIndex(Token.Ident, Keywords);
    if Idx >= 0 then
    begin
      Len := TPixieCssLength.PredefValue(Idx);
      Exit(True);
    end;
  end;

  // Try number (unitless zero, or if f_number/f_integer allowed)
  if Token.TokenType = cssTokenNumber then
  begin
    if ((Options and clfPositive) <> 0) and (Token.Number < 0) then
      Exit;
    if ((Options and clfInteger) <> 0) and (Token.NumberType <> cssNumberInteger) then
      Exit;

    // Unitless zero is always valid for lengths
    if Token.Number = 0 then
    begin
      Len := TPixieCssLength.Create(0, cssUnitsPx);
      Exit(True);
    end;

    if (Options and clfNumber) <> 0 then
    begin
      Len := TPixieCssLength.Create(Token.Number, cssUnitsNone);
      Exit(True);
    end;

    if (Options and clfInteger) <> 0 then
    begin
      Len := TPixieCssLength.Create(Token.Number, cssUnitsNone);
      Exit(True);
    end;

    Exit;
  end;

  // Try percentage
  if (Token.TokenType = cssTokenPercentage) and ((Options and clfPercentage) <> 0) then
  begin
    if ((Options and clfPositive) <> 0) and (Token.Number < 0) then
      Exit;
    Len := TPixieCssLength.Create(Token.Number, cssUnitsPercentage);
    Exit(True);
  end;

  // Try dimension (length with unit)
  if (Token.TokenType = cssTokenDimension) and ((Options and clfLength) <> 0) then
  begin
    if ((Options and clfPositive) <> 0) and (Token.Number < 0) then
      Exit;
    UnitStr := PixieLowerCase(Token.Str);
    UnitIdx := PixieValueIndex(UnitStr,
      '%;in;cm;mm;em;ex;pt;pc;px;vw;vh;vmin;vmax;rem;ch;fr;cqw;cqh;cqi;cqb;cqmin;cqmax');
    if UnitIdx < 0 then
      Exit;
    Len := TPixieCssLength.Create(Token.Number, TPixieCssUnits(UnitIdx + 1));
    Exit(True);
  end;

  // Try calc() function
  if (Token.TokenType = cssTokenCvFunction) and
     ((Options and clfLengthPercentage) <> 0) and
     (PixieLowerCase(Token.Str) = 'calc') then
  begin
    if PixieParseCalcExpression(Token.Value, Len) then
      Exit(True);
  end;

  // Try min()/max()/clamp() math functions
  if (Token.TokenType = cssTokenCvFunction) and
     ((Options and clfLengthPercentage) <> 0) and
     IsMathFuncName(Token.Str) then
  begin
    if PixieParseMathFunction(Token.Str, Token.Value, Len) then
      Exit(True);
  end;
end;

function PixieParseAngle(Token: TPixieCssToken; out Angle: Single;
  PercentsAllowed: Boolean): Boolean;
var
  UnitStr: string;
begin
  Result := False;
  if Token = nil then
    Exit;

  if (Token.TokenType = cssTokenPercentage) and PercentsAllowed then
  begin
    Angle := Token.Number / 100 * 360;
    Exit(True);
  end;

  if Token.TokenType = cssTokenDimension then
  begin
    UnitStr := PixieLowerCase(Token.Str);
    if UnitStr = 'deg' then
    begin
      Angle := Token.Number;
      Exit(True);
    end
    else if UnitStr = 'grad' then
    begin
      Angle := Token.Number * 0.9;
      Exit(True);
    end
    else if UnitStr = 'rad' then
    begin
      Angle := Token.Number * 180 / Pi;
      Exit(True);
    end
    else if UnitStr = 'turn' then
    begin
      Angle := Token.Number * 360;
      Exit(True);
    end;
  end;

  // Unitless zero
  if (Token.TokenType = cssTokenNumber) and (Token.Number = 0) then
  begin
    Angle := 0;
    Exit(True);
  end;
end;

function PixieParseKeyword(Token: TPixieCssToken; out Val: Integer;
  const Keywords: string; FirstKeywordValue: Integer): Boolean;
var
  Idx: Integer;
begin
  Result := False;
  if Token = nil then
    Exit;
  Idx := PixieValueIndex(TokenIdent(Token), Keywords);
  if Idx < 0 then
    Exit;
  Val := FirstKeywordValue + Idx;
  Result := True;
end;

function PixieParseCssColor(Token: TPixieCssToken; out Color: TPixieWebColor): Boolean;
var
  S: string;
begin
  Result := False;
  if Token = nil then
    Exit;

  // #hash
  if Token.TokenType = cssTokenHash then
  begin
    Result := PixieParseHashColorString('#' + Token.Str, Color);
    Exit;
  end;

  // named colour
  if Token.TokenType = cssTokenIdent then
  begin
    S := Token.Ident;
    if S = 'currentcolor' then
    begin
      Color := TPixieWebColor.CurrentColor;
      Exit(True);
    end;
    Result := PixieParseNamedColor(S, Color);
    Exit;
  end;

  // rgb() / rgba() / hsl() / hsla() functions
  if Token.TokenType = cssTokenCvFunction then
  begin
    S := PixieLowerCase(Token.Str);
    if IsOneOfStr4(S, 'rgb', 'rgba', 'hsl', 'hsla') and (Token.Value <> nil) then
    begin
      Result := ParseColorFunction(S, Token.Value, Color);
    end;
  end;
end;

function ParseColorFunction(const FuncName: string; Args: TPixieCssTokenList;
  out Color: TPixieWebColor): Boolean;
var
  I: Integer;
  Values: array[0..3] of Single;
  Count: Integer;
  IsHsl: Boolean;
  R, G, B: Single;
  Tok: TPixieCssToken;
  IsPercentage: Boolean;
begin
  Result := False;
  IsHsl := (FuncName = 'hsl') or (FuncName = 'hsla');
  Count := 0;
  Values[3] := 255; // default alpha

  for I := 0 to Args.Count - 1 do
  begin
    Tok := Args[I];
    if (Tok.TokenType = cssTokenWhitespace) or (Tok.TokenType = cssTokenComma) or
       (TokenCh(Tok) = '/') then
      Continue;

    if Count >= 4 then
      Exit;

    IsPercentage := Tok.TokenType = cssTokenPercentage;

    if (Tok.TokenType = cssTokenNumber) or IsPercentage then
    begin
      if Count = 3 then // alpha
      begin
        if IsPercentage then
          Values[Count] := EnsureRange(Tok.Number / 100 * 255, 0, 255)
        else
          Values[Count] := EnsureRange(Tok.Number * 255, 0, 255);
      end
      else if IsHsl then
      begin
        if Count = 0 then
          Values[Count] := Tok.Number  // hue in degrees
        else
          Values[Count] := Tok.Number; // sat/light as percentage
      end
      else
      begin
        if IsPercentage then
          Values[Count] := EnsureRange(Tok.Number / 100 * 255, 0, 255)
        else
          Values[Count] := EnsureRange(Tok.Number, 0, 255);
      end;
      Inc(Count);
    end
    else if (Tok.TokenType = cssTokenDimension) and (Count = 0) and IsHsl then
    begin
      // hue with unit
      Values[Count] := Tok.Number;
      Inc(Count);
    end
    else
      Exit; // unexpected token
  end;

  if (Count < 3) then
    Exit;

  if IsHsl then
  begin
    PixieHslToRgb(Values[0], Values[1], Values[2], R, G, B);
    Color := TPixieWebColor.Create(
      Round(EnsureRange(R * 255, 0, 255)),
      Round(EnsureRange(G * 255, 0, 255)),
      Round(EnsureRange(B * 255, 0, 255)),
      Round(Values[3]));
  end
  else
    Color := TPixieWebColor.Create(
      Round(Values[0]),
      Round(Values[1]),
      Round(Values[2]),
      Round(Values[3]));
  Result := True;
end;

function IsOneOfPredef(const X: TPixieCssLength; Idx1, Idx2: Integer): Boolean;
begin
  Result := X.IsPredefined and IsOneOfId(X.Predef, Idx1, Idx2);
end;

function PixieParseBgPosition(Tokens: TPixieCssTokenList; var Index: Integer;
  out X, Y: TPixieCssLength; ConvertKeywordsToPercents: Boolean): Boolean;
var
  A, B: TPixieCssLength;
  TokA, TokB: TPixieCssToken;
begin
  Result := False;
  TokA := PixieTokenAt(Tokens, Index);
  if not PixieParseCssLength(TokA, A, clfLengthPercentage, BackgroundPositionStrings) then
    Exit;

  TokB := PixieTokenAt(Tokens, Index + 1);
  if not PixieParseCssLength(TokB, B, clfLengthPercentage, BackgroundPositionStrings) then
  begin
    // If only one value, second is assumed to be center
    B := TPixieCssLength.PredefValue(Ord(bpCenter));

    // fix wrong order: if A is top/bottom, swap
    if IsOneOfPredef(A, Ord(bpTop), Ord(bpBottom)) then
    begin
      B := A;
      A := TPixieCssLength.PredefValue(Ord(bpCenter));
    end;

    Inc(Index);
  end
  else
  begin
    // Two values: try to fix wrong order
    if (IsOneOfPredef(A, Ord(bpTop), Ord(bpBottom)) and B.IsPredefined) or
       (A.IsPredefined and IsOneOfPredef(B, Ord(bpLeft), Ord(bpRight))) then
    begin
      // swap
      X := A;
      A := B;
      B := X;
    end;

    // check for invalid order
    if IsOneOfPredef(A, Ord(bpTop), Ord(bpBottom)) or
       IsOneOfPredef(B, Ord(bpLeft), Ord(bpRight)) then
      Exit;

    Inc(Index, 2);
  end;

  if ConvertKeywordsToPercents then
  begin
    if A.IsPredefined then
      A := TPixieCssLength.Create(BackgroundPositionPercentages[TPixieBackgroundPosition(A.Predef)],
        cssUnitsPercentage);
    if B.IsPredefined then
      B := TPixieCssLength.Create(BackgroundPositionPercentages[TPixieBackgroundPosition(B.Predef)],
        cssUnitsPercentage);
  end;

  X := A;
  Y := B;
  Result := True;
end;

function ParseBorderWidth(Token: TPixieCssToken; out Width: TPixieCssLength): Boolean;
var
  W: TPixieCssLength;
begin
  Result := False;
  if not PixieParseCssLength(Token, W, clfLength or clfPositive, BorderWidthStrings) then
    Exit;
  if W.IsPredefined then
    W.SetValue(BorderWidthValues[TPixieBorderWidth(W.Predef)], cssUnitsPx);
  Width := W;
  Result := True;
end;

function ParseBorderHelper(Tokens: TPixieCssTokenList;
  out Width: TPixieCssLength; out Style: Integer; out Color: TPixieWebColor): Boolean;
var
  I: Integer;
  Tok: TPixieCssToken;
  WidthFound, StyleFound, ColorFound: Boolean;
  TempWidth: TPixieCssLength;
  TempStyle: Integer;
  TempColor: TPixieWebColor;
begin
  // initial values
  Width := TPixieCssLength.Create(BorderWidthMediumValue, cssUnitsPx);
  Style := Ord(bsNone);
  Color := TPixieWebColor.CurrentColor;

  WidthFound := False;
  StyleFound := False;
  ColorFound := False;

  for I := 0 to Tokens.Count - 1 do
  begin
    Tok := Tokens[I];
    if (not WidthFound) and ParseBorderWidth(Tok, TempWidth) then
    begin
      Width := TempWidth;
      WidthFound := True;
    end
    else if (not StyleFound) and PixieParseKeyword(Tok, TempStyle, BorderStyleStrings) then
    begin
      Style := TempStyle;
      StyleFound := True;
    end
    else if (not ColorFound) and PixieParseCssColor(Tok, TempColor) then
    begin
      Color := TempColor;
      ColorFound := True;
    end
    else
      Exit(False);
  end;
  Result := True;
end;

function ParseTwoLengths(Tokens: TPixieCssTokenList; out Len0, Len1: TPixieCssLength;
  Options: Integer): Boolean;
var
  A, B: TPixieCssLength;
begin
  Result := False;
  if (Tokens.Count < 1) or (Tokens.Count > 2) then
    Exit;
  if not PixieParseCssLength(Tokens[0], A, Options) then
    Exit;
  if Tokens.Count = 1 then
    B := A
  else if not PixieParseCssLength(Tokens[1], B, Options) then
    Exit;
  Len0 := A;
  Len1 := B;
  Result := True;
end;

function Parse1234Lengths(Tokens: TPixieCssTokenList; out Len: array of TPixieCssLength;
  Options: Integer; const Keywords: string = ''): Integer;
var
  I: Integer;
  L: TPixieCssLength;
begin
  Result := 0;
  if (Tokens.Count < 1) or (Tokens.Count > 4) then
    Exit;
  for I := 0 to Tokens.Count - 1 do
  begin
    if not PixieParseCssLength(Tokens[I], L, Options, Keywords) then
      Exit(0);
    Len[I] := L;
  end;
  Result := Tokens.Count;
end;

function Parse1234Keywords(Tokens: TPixieCssTokenList; out Vals: array of Integer;
  const Keywords: string): Integer;
var
  I, V: Integer;
begin
  Result := 0;
  if (Tokens.Count < 1) or (Tokens.Count > 4) then
    Exit;
  for I := 0 to Tokens.Count - 1 do
  begin
    if not PixieParseKeyword(Tokens[I], V, Keywords) then
      Exit(0);
    Vals[I] := V;
  end;
  Result := Tokens.Count;
end;

function Parse1234Colors(Tokens: TPixieCssTokenList;
  out Cols: array of TPixieWebColor): Integer;
var
  I: Integer;
  C: TPixieWebColor;
begin
  Result := 0;
  if (Tokens.Count < 1) or (Tokens.Count > 4) then
    Exit;
  for I := 0 to Tokens.Count - 1 do
  begin
    if not PixieParseCssColor(Tokens[I], C) then
      Exit(0);
    Cols[I] := C;
  end;
  Result := Tokens.Count;
end;

function Parse1234BorderWidths(Tokens: TPixieCssTokenList;
  out Widths: array of TPixieCssLength): Integer;
var
  I: Integer;
  W: TPixieCssLength;
begin
  Result := 0;
  if (Tokens.Count < 1) or (Tokens.Count > 4) then
    Exit;
  for I := 0 to Tokens.Count - 1 do
  begin
    if not ParseBorderWidth(Tokens[I], W) then
      Exit(0);
    Widths[I] := W;
  end;
  Result := Tokens.Count;
end;

function ParseFontWeight(Token: TPixieCssToken; out Weight: TPixieCssLength): Boolean;
var
  Idx: Integer;
begin
  Result := False;
  if Token = nil then
    Exit;
  Idx := PixieValueIndex(TokenIdent(Token), FontWeightStrings);
  if Idx >= 0 then
  begin
    Weight := TPixieCssLength.PredefValue(Idx);
    Exit(True);
  end;
  if (Token.TokenType = cssTokenNumber) and (Token.Number >= 1) and (Token.Number <= 1000) then
  begin
    Weight.SetValue(Token.Number, cssUnitsNone);
    Exit(True);
  end;
end;

function ParseFontStyleVariantWeight(Tokens: TPixieCssTokenList; var Index: Integer;
  out FontStyle, FontVariant: Integer; out Weight: TPixieCssLength): Boolean;
var
  Tok: TPixieCssToken;
  StyleFound, VariantFound, WeightFound: Boolean;
  TempStyle, TempVariant: Integer;
  TempWeight: TPixieCssLength;
  Count: Integer;
begin
  Result := False;
  StyleFound := False;
  VariantFound := False;
  WeightFound := False;
  FontStyle := Ord(fstNormal);
  FontVariant := Ord(fvNormal);
  Weight := TPixieCssLength.PredefValue(Ord(fwNormal));

  Count := 0;
  while (Index < Tokens.Count) and (Count < 3) do
  begin
    Tok := Tokens[Index];
    Inc(Count);

    if TokenIdent(Tok) = 'normal' then
    begin
      Inc(Index);
      Result := True;
    end
    else if (not StyleFound) and PixieParseKeyword(Tok, TempStyle, FontStyleStrings) then
    begin
      FontStyle := TempStyle;
      StyleFound := True;
      Inc(Index);
      Result := True;
    end
    // 'oblique' has no separate representation — render it as italic.
    else if (not StyleFound) and (TokenIdent(Tok) = 'oblique') then
    begin
      FontStyle := Ord(fstItalic);
      StyleFound := True;
      Inc(Index);
      Result := True;
    end
    else if (not VariantFound) and PixieParseKeyword(Tok, TempVariant, FontVariantStrings) then
    begin
      if TempVariant > Ord(fvSmallCaps) then
        TempVariant := Ord(fvSmallCaps);
      FontVariant := TempVariant;
      VariantFound := True;
      Inc(Index);
      Result := True;
    end
    else if (not WeightFound) and ParseFontWeight(Tok, TempWeight) then
    begin
      Weight := TempWeight;
      WeightFound := True;
      Inc(Index);
      Result := True;
    end
    else
      Break;
  end;
end;

function IsCustomIdent(Token: TPixieCssToken): Boolean;
begin
  Result := False;
  if Token = nil then
    Exit;
  if Token.TokenType <> cssTokenIdent then
    Exit;
  Result := not IsOneOfStr4(PixieLowerCase(Token.Str), 'default', 'initial', 'inherit', 'unset');
end;

function ParseFontFamily(Tokens: TPixieCssTokenList; StartIndex: Integer;
  out FontFamily: string): Boolean;
var
  List: TPixieCssTokenListList;
  I, J: Integer;
  Name: TPixieCssTokenList;
  Tok: TPixieCssToken;
  SubTokens: TPixieCssTokenList;
  Families, Words: TStringList;
begin
  Result := False;

  // Build a sub-list starting from StartIndex
  SubTokens := TPixieCssTokenList.Create(False);
  try
    for I := StartIndex to Tokens.Count - 1 do
      SubTokens.Add(Tokens[I]);

    List := PixieCssParseCommaSeparatedList(SubTokens);
    try
      if List.Count = 0 then
        Exit;

      Families := TStringList.Create;
      Words := TStringList.Create;
      try
        Families.Delimiter := ',';
        Families.StrictDelimiter := True;
        Words.Delimiter := ' ';
        Words.StrictDelimiter := True;
        for I := 0 to List.Count - 1 do
        begin
          Name := List[I];
          if (Name.Count = 1) and (Name[0].TokenType = cssTokenString) then
          begin
            Families.Add(Name[0].Str);
            Continue;
          end;

          Words.Clear;
          for J := 0 to Name.Count - 1 do
          begin
            Tok := Name[J];
            if Tok.TokenType = cssTokenWhitespace then
              Continue;
            if not IsCustomIdent(Tok) then
              Exit;
            Words.Add(Tok.Str);
          end;
          if Words.Count = 0 then
            Exit;
          Families.Add(Words.DelimitedText);
        end;
        FontFamily := Families.DelimitedText;
        Result := FontFamily <> '';
      finally
        Families.Free;
        Words.Free;
      end;
    finally
      for I := 0 to List.Count - 1 do
        List[I].Free;
      List.Free;
    end;
  finally
    SubTokens.Free;
  end;
end;

function ParseListStyleImage(Token: TPixieCssToken; out Url: string): Boolean;
begin
  if TokenIdent(Token) = 'none' then
  begin
    Url := '';
    Exit(True);
  end;
  Result := PixieParseUrl(Token, Url);
end;

function ParseBgSize(Tokens: TPixieCssTokenList; var Index: Integer;
  out Size: TPixieCssSize): Boolean;
var
  A, B: TPixieCssLength;
  TokA, TokB: TPixieCssToken;
begin
  Result := False;
  TokA := PixieTokenAt(Tokens, Index);
  if not PixieParseCssLength(TokA, A, clfLengthPercentage or clfPositive, BackgroundSizeStrings) then
    Exit;

  // cover | contain
  if A.IsPredefined and (A.Predef <> Ord(bszAuto)) then
  begin
    Size := TPixieCssSize.Create(A, A);
    Inc(Index);
    Exit(True);
  end;

  TokB := PixieTokenAt(Tokens, Index + 1);
  if PixieParseCssLength(TokB, B, clfLengthPercentage or clfPositive, 'auto') then
    Inc(Index, 2)
  else
  begin
    B := TPixieCssLength.PredefValue(Ord(bszAuto));
    Inc(Index);
  end;

  Size := TPixieCssSize.Create(A, B);
  Result := True;
end;

function ParseBgPositionSize(Tokens: TPixieCssTokenList; var Index: Integer;
  out X, Y: TPixieCssLength; out Size: TPixieCssSize): Boolean;
var
  Tok: TPixieCssToken;
begin
  Result := False;
  if not PixieParseBgPosition(Tokens, Index, X, Y, True) then
    Exit;

  Tok := PixieTokenAt(Tokens, Index);
  if (Tok <> nil) and (TokenCh(Tok) = '/') then
  begin
    Inc(Index);
    if not ParseBgSize(Tokens, Index, Size) then
    begin
      Dec(Index);
      Exit(False);
    end;
  end
  else
  begin
    Size := TPixieCssSize.Create(
      TPixieCssLength.PredefValue(Ord(bszAuto)),
      TPixieCssLength.PredefValue(Ord(bszAuto)));
  end;
  Result := True;
end;

function ParseTextDecorationColor(Token: TPixieCssToken; out Color: TPixieWebColor): Boolean;
begin
  Result := False;
  if PixieParseCssColor(Token, Color) then
    Exit(True);
  if (Token <> nil) and (Token.TokenType = cssTokenIdent) and
     PixieValueInList(Token.Ident, 'auto;currentcolor') then
  begin
    Color := TPixieWebColor.CurrentColor;
    Exit(True);
  end;
end;

{ TPixieStyle }

constructor TPixieStyle.Create;
begin
  inherited Create;
  FProperties := TPixiePropsMap.Create;
end;

destructor TPixieStyle.Destroy;
var
  Pair: TPair<Integer, TPixiePropertyValue>;
  PV: TPixiePropertyValue;
begin
  for Pair in FProperties do
  begin
    PV := Pair.Value;
    PV.FreeOwnedObjects;
  end;
  FProperties.Free;
  inherited;
end;

procedure TPixieStyle.Clear;
var
  Pair: TPair<Integer, TPixiePropertyValue>;
  PV: TPixiePropertyValue;
begin
  for Pair in FProperties do
  begin
    PV := Pair.Value;
    PV.FreeOwnedObjects;
  end;
  FProperties.Clear;
end;

// Map the still-common vendor-prefixed spellings of 'user-select' onto the
// standard property. Stripping prefixes wholesale would be risky: for divergent
// pairs (e.g. '-webkit-appearance' vs 'appearance') a later prefixed hack could
// overwrite the intended modern value, so we only alias the names we support.
function PixieCanonicalPropertyName(const Name: string): string;
begin
  if (Name = '-webkit-user-select') or (Name = '-moz-user-select') or
     (Name = '-ms-user-select') then
    Result := 'user-select'
  else
    Result := Name;
end;

procedure TPixieStyle.Add(const Txt: string; const BaseUrl: string);
var
  Tokens: TPixieCssTokenList;
begin
  Tokens := PixieCssNormalizeStr(Txt, cssCssNormComponentize);
  try
    Add(Tokens, BaseUrl);
  finally
    Tokens.Free;
  end;
end;

procedure TPixieStyle.Add(Tokens: TPixieCssTokenList; const BaseUrl: string);
var
  Decls: TPixieCssRawDeclarationList;
  Rules: TPixieCssRawRuleList;
  I: Integer;
  Decl: TPixieCssRawDeclaration;
  Name: string;
begin
  PixieCssParseStyleBlockContents(Tokens, Decls, Rules);
  try
    for I := 0 to Decls.Count - 1 do
    begin
      Decl := Decls[I];
      PixieCssRemoveWhitespace(Decl.Value);
      if (Length(Decl.Name) >= 2) and (Decl.Name[1] = '-') and (Decl.Name[2] = '-') then
        Name := Decl.Name
      else
        Name := PixieCanonicalPropertyName(PixieLowerCase(Decl.Name));
      AddProperty(PixieId(Name), Decl.Value, BaseUrl, Decl.Important);
    end;
  finally
    // Free declarations' Value lists
    for I := 0 to Decls.Count - 1 do
    begin
      Decl := Decls[I];
      Decl.Value.Free;
    end;
    Decls.Free;
    Rules.Free;
  end;
end;

procedure TPixieStyle.AddProperty(Name: Integer; const Val: string;
  const BaseUrl: string; Important: Boolean);
var
  Tokens: TPixieCssTokenList;
begin
  Tokens := PixieCssNormalizeStr(Val, cssCssNormComponentize or cssCssNormRemoveWhitespace);
  try
    AddProperty(Name, Tokens, BaseUrl, Important);
  finally
    Tokens.Free;
  end;
end;

procedure TPixieStyle.AddProperty(Name: Integer; Tokens: TPixieCssTokenList;
  const BaseUrl: string; Important: Boolean);
var
  Val: TPixieCssToken;
  Ident: string;
  Idx: Integer;
  Len: array[0..3] of TPixieCssLength;
  Cols: array[0..3] of TPixieWebColor;
  Idxs: array[0..3] of Integer;
  Clr: TPixieWebColor;
  L: TPixieCssLength;
  N: Integer;
  S: string;
  NameStr: string;
  ValidStr: string;
  Vec: TPixieStringVector;
  I: Integer;
  TokensCopy: TPixieCssTokenList;
  Prop: TPixiePropertyValue;
begin
  // Empty value: only valid for custom properties
  NameStr := PixieStr(Name);
  if (Tokens.Count = 0) and not ((Length(NameStr) >= 2) and (NameStr[1] = '-') and (NameStr[2] = '-')) then
    Exit;

  // Check for var() - delay parsing
  if HasVarFunction(Tokens) then
  begin
    TokensCopy := TPixieCssTokenList.Create;
    PixieCssTokenListCopy(Tokens, TokensCopy);
    AddParsedProperty(Name, TPixiePropertyValue.FromTokenVec(TokensCopy, Important, True));
    Exit;
  end;

  // Check for calc() with context-dependent units (em/rem/vw/vh) - delay
  if (GCalcCtx = nil) and HasDeferredCalc(Tokens) then
  begin
    TokensCopy := TPixieCssTokenList.Create;
    PixieCssTokenListCopy(Tokens, TokensCopy);
    Prop := TPixiePropertyValue.FromTokenVec(TokensCopy, Important, False);
    Prop.HasCalc := True;
    AddParsedProperty(Name, Prop);
    Exit;
  end;

  // Single token shortcuts
  if Tokens.Count = 1 then
    Val := Tokens[0]
  else
    Val := nil;
  Ident := TokenIdent(Val);

  // "inherit" applies to all properties
  if Ident = 'inherit' then
  begin
    InheritProperty(Name, Important);
    Exit;
  end;

  // Legacy property aliases (word-wrap predates overflow-wrap, grid-*gap
  // predates *gap from the CSS Grid L1→L2 rename, font-variant-caps is the
  // CSS Fonts L3 longhand of the original font-variant — all collapse here)
  if Name = Ord(psid_word_wrap) then
    Name := Ord(psid_overflow_wrap)
  else if Name = Ord(psid_grid_gap) then
    Name := Ord(psid_gap)
  else if Name = Ord(psid_grid_row_gap) then
    Name := Ord(psid_row_gap)
  else if Name = Ord(psid_grid_column_gap) then
    Name := Ord(psid_column_gap)
  else if Name = Ord(psid_font_variant_caps) then
    Name := Ord(psid_font_variant);

  // overflow-y maps to the single overflow (vertical/shorthand) value;
  // overflow-x is kept as its own property and clips the horizontal axis only.
  if Name = Ord(psid_overflow_y) then
    Name := Ord(psid_overflow);

  // =============================  SINGLE KEYWORD  =============================

  if (Name = Ord(psid_display)) or (Name = Ord(psid_visibility)) or
     (Name = Ord(psid_user_select)) or
     (Name = Ord(psid_position)) or (Name = Ord(psid_float)) or
     (Name = Ord(psid_clear)) or (Name = Ord(psid_appearance)) or
     (Name = Ord(psid_box_sizing)) or (Name = Ord(psid_overflow)) or
     (Name = Ord(psid_overflow_x)) or
     (Name = Ord(psid_text_align)) or (Name = Ord(psid_vertical_align)) or
     (Name = Ord(psid_text_transform)) or (Name = Ord(psid_white_space)) or
     (Name = Ord(psid_font_style)) or (Name = Ord(psid_font_variant)) or
     (Name = Ord(psid_text_decoration_style)) or
     (Name = Ord(psid_list_style_type)) or (Name = Ord(psid_list_style_position)) or
     (Name = Ord(psid_border_top_style)) or (Name = Ord(psid_border_bottom_style)) or
     (Name = Ord(psid_border_left_style)) or (Name = Ord(psid_border_right_style)) or
     (Name = Ord(psid_border_collapse)) or
     (Name = Ord(psid_table_layout)) or
     (Name = Ord(psid_flex_direction)) or (Name = Ord(psid_flex_wrap)) or
     (Name = Ord(psid_justify_content)) or (Name = Ord(psid_align_content)) or
     (Name = Ord(psid_caption_side)) or
     (Name = Ord(psid_overflow_wrap)) then
  begin
    ValidStr := PixieGetValidValues(Name);
    if ValidStr <> '' then
    begin
      Idx := PixieValueIndex(Ident, ValidStr);
      // CSS-wide keyword 'initial' resets a property to its initial value.
      // Dropping it (Idx < 0) wrongly lets a less specific rule win — e.g.
      // 'display: initial' must override an earlier 'display: none' rather
      // than be ignored (issue #271). The initial value of 'display' is
      // 'inline'; position/float blockification then promotes it as needed.
      if (Idx < 0) and (Ident = 'initial') then
      begin
        if Name = Ord(psid_display) then
          Idx := PixieValueIndex('inline', ValidStr)
        else if Name = Ord(psid_visibility) then
          Idx := PixieValueIndex('visible', ValidStr);
      end;
      // 'oblique' has no separate representation — render it as italic.
      if (Name = Ord(psid_font_style)) and (Idx < 0) and (Ident = 'oblique') then
        Idx := Ord(fstItalic);
      // CSS Fonts L3 caps keywords past index 1 collapse to fvSmallCaps —
      // TPixieFontVariant has no separate petite/titling/unicase representation.
      if (Name = Ord(psid_font_variant)) and (Idx > Ord(fvSmallCaps)) then
        Idx := Ord(fvSmallCaps);
      if Idx >= 0 then
        AddParsedProperty(Name, TPixiePropertyValue.FromInt(Idx, Important));
    end;
    Exit;
  end;

  // =============================  LENGTH  =============================

  if Name = Ord(psid_z_index) then
  begin
    AddLengthProperty(Name, Val, 'auto', clfInteger, Important);
    Exit;
  end;

  if Name = Ord(psid_text_indent) then
  begin
    AddLengthProperty(Name, Val, '', clfLengthPercentage, Important);
    Exit;
  end;

  if (Name = Ord(psid_padding_left)) or (Name = Ord(psid_padding_right)) or
     (Name = Ord(psid_padding_top)) or (Name = Ord(psid_padding_bottom)) then
  begin
    AddLengthProperty(Name, Val, '', clfLengthPercentage or clfPositive, Important);
    Exit;
  end;

  if (Name = Ord(psid_left)) or (Name = Ord(psid_right)) or
     (Name = Ord(psid_top)) or (Name = Ord(psid_bottom)) or
     (Name = Ord(psid_margin_left)) or (Name = Ord(psid_margin_right)) or
     (Name = Ord(psid_margin_top)) or (Name = Ord(psid_margin_bottom)) then
  begin
    AddLengthProperty(Name, Val, 'auto', clfLengthPercentage, Important);
    Exit;
  end;

  if (Name = Ord(psid_width)) or (Name = Ord(psid_height)) or
     (Name = Ord(psid_min_width)) or (Name = Ord(psid_min_height)) then
  begin
    AddLengthProperty(Name, Val, 'auto;fit-content;min-content;max-content',
      clfLengthPercentage or clfPositive, Important);
    Exit;
  end;

  if (Name = Ord(psid_max_width)) or (Name = Ord(psid_max_height)) then
  begin
    AddLengthProperty(Name, Val, 'none;fit-content;min-content;max-content',
      clfLengthPercentage or clfPositive, Important);
    Exit;
  end;

  if Name = Ord(psid_line_height) then
  begin
    AddLengthProperty(Name, Val, LineHeightStrings, clfNumber or clfLengthPercentage or clfPositive, Important);
    Exit;
  end;

  if Name = Ord(psid_font_size) then
  begin
    AddLengthProperty(Name, Val, FontSizeStrings, clfLengthPercentage or clfPositive, Important);
    Exit;
  end;

  if Name = Ord(psid_margin) then
  begin
    N := Parse1234Lengths(Tokens, Len, clfLengthPercentage, 'auto');
    if N > 0 then
      AddFourLengths(Ord(psid_margin_top), Len, N, Important);
    Exit;
  end;

  if Name = Ord(psid_padding) then
  begin
    N := Parse1234Lengths(Tokens, Len, clfLengthPercentage or clfPositive);
    if N > 0 then
      AddFourLengths(Ord(psid_padding_top), Len, N, Important);
    Exit;
  end;

  // =============================  COLOR  =============================

  if Name = Ord(psid_color) then
  begin
    if Ident = 'currentcolor' then
    begin
      InheritProperty(Name, Important);
      Exit;
    end;
    if PixieParseCssColor(Val, Clr) then
      AddParsedProperty(Name, TPixiePropertyValue.FromColor(Clr, Important));
    Exit;
  end;

  if (Name = Ord(psid_background_color)) or
     (Name = Ord(psid_border_top_color)) or (Name = Ord(psid_border_bottom_color)) or
     (Name = Ord(psid_border_left_color)) or (Name = Ord(psid_border_right_color)) then
  begin
    if PixieParseCssColor(Val, Clr) then
      AddParsedProperty(Name, TPixiePropertyValue.FromColor(Clr, Important));
    Exit;
  end;

  // =============================  BACKGROUND  =============================

  if Name = Ord(psid_background) then
  begin
    ParseBackground(Tokens, BaseUrl, Important);
    Exit;
  end;

  if Name = Ord(psid_background_image) then
  begin
    ParseBackgroundImage(Tokens, BaseUrl, Important);
    Exit;
  end;

  if Name = Ord(psid_background_position) then
  begin
    ParseBackgroundPosition(Tokens, Important);
    Exit;
  end;

  if Name = Ord(psid_background_size) then
  begin
    ParseBackgroundSize(Tokens, Important);
    Exit;
  end;

  if (Name = Ord(psid_background_repeat)) or (Name = Ord(psid_background_attachment)) or
     (Name = Ord(psid_background_origin)) or (Name = Ord(psid_background_clip)) then
  begin
    ParseKeywordCommaList(Name, Tokens, Important);
    Exit;
  end;

  // =============================  BORDER  =============================

  if Name = Ord(psid_border) then
  begin
    ParseBorder(Tokens, Important);
    Exit;
  end;

  if Name = Ord(psid_outline) then
  begin
    ParseOutline(Tokens, Important);
    Exit;
  end;

  if (Name = Ord(psid_border_left)) or (Name = Ord(psid_border_right)) or
     (Name = Ord(psid_border_top)) or (Name = Ord(psid_border_bottom)) then
  begin
    ParseBorderSide(Name, Tokens, Important);
    Exit;
  end;

  if Name = Ord(psid_border_width) then
  begin
    N := Parse1234BorderWidths(Tokens, Len);
    if N > 0 then
      AddFourLengths(Ord(psid_border_top_width), Len, N, Important);
    Exit;
  end;

  if Name = Ord(psid_border_style) then
  begin
    N := Parse1234Keywords(Tokens, Idxs, BorderStyleStrings);
    if N > 0 then
      AddFourInts(Ord(psid_border_top_style), Idxs, N, Important);
    Exit;
  end;

  if Name = Ord(psid_border_color) then
  begin
    N := Parse1234Colors(Tokens, Cols);
    if N > 0 then
      AddFourColors(Ord(psid_border_top_color), Cols, N, Important);
    Exit;
  end;

  if (Name = Ord(psid_border_top_width)) or (Name = Ord(psid_border_bottom_width)) or
     (Name = Ord(psid_border_left_width)) or (Name = Ord(psid_border_right_width)) then
  begin
    if ParseBorderWidth(Val, L) then
      AddParsedProperty(Name, TPixiePropertyValue.FromLength(L, Important));
    Exit;
  end;

  if (Name = Ord(psid_border_bottom_left_radius)) or
     (Name = Ord(psid_border_bottom_right_radius)) or
     (Name = Ord(psid_border_top_right_radius)) or
     (Name = Ord(psid_border_top_left_radius)) then
  begin
    if ParseTwoLengths(Tokens, Len[0], Len[1], clfLengthPercentage or clfPositive) then
    begin
      AddParsedProperty(PixieId(NameStr + '-x'), TPixiePropertyValue.FromLength(Len[0], Important));
      AddParsedProperty(PixieId(NameStr + '-y'), TPixiePropertyValue.FromLength(Len[1], Important));
    end;
    Exit;
  end;

  if (Name = Ord(psid_border_radius_x)) or (Name = Ord(psid_border_radius_y)) then
  begin
    if Name = Ord(psid_border_radius_x) then
      Idx := Ord(psid_border_top_left_radius_x)
    else
      Idx := Ord(psid_border_top_left_radius_y);
    N := Parse1234Lengths(Tokens, Len, clfLengthPercentage or clfPositive);
    if N > 0 then
      AddFourLengths(Idx, Len, N, Important);
    Exit;
  end;

  if Name = Ord(psid_border_radius) then
  begin
    ParseBorderRadius(Tokens, Important);
    Exit;
  end;

  if Name = Ord(psid_border_spacing) then
  begin
    if ParseTwoLengths(Tokens, Len[0], Len[1], clfLength or clfPositive) then
    begin
      AddParsedProperty(Ord(psid__pixie_border_spacing_x),
        TPixiePropertyValue.FromLength(Len[0], Important));
      AddParsedProperty(Ord(psid__pixie_border_spacing_y),
        TPixiePropertyValue.FromLength(Len[1], Important));
    end;
    Exit;
  end;

  // =============================  LIST  =============================

  if Name = Ord(psid_list_style_image) then
  begin
    if ParseListStyleImage(Val, S) then
    begin
      AddParsedProperty(Ord(psid_list_style_image),
        TPixiePropertyValue.FromString(S, Important));
      AddParsedProperty(Ord(psid_list_style_image_baseurl),
        TPixiePropertyValue.FromString(BaseUrl, Important));
    end;
    Exit;
  end;

  if Name = Ord(psid_list_style) then
  begin
    ParseListStyle(Tokens, BaseUrl, Important);
    Exit;
  end;

  // =============================  FONT  =============================

  if Name = Ord(psid_font) then
  begin
    ParseFont(Tokens, Important);
    Exit;
  end;

  if Name = Ord(psid_font_family) then
  begin
    if ParseFontFamily(Tokens, 0, S) then
      AddParsedProperty(Name, TPixiePropertyValue.FromString(S, Important));
    Exit;
  end;

  if Name = Ord(psid_font_weight) then
  begin
    if ParseFontWeight(Val, L) then
      AddParsedProperty(Name, TPixiePropertyValue.FromLength(L, Important));
    Exit;
  end;

  if Name = Ord(psid_text_decoration) then
  begin
    ParseTextDecoration(Tokens, Important);
    Exit;
  end;

  if Name = Ord(psid_text_decoration_thickness) then
  begin
    AddLengthProperty(Name, Val, TextDecorationThicknessStrings,
      clfLengthPercentage or clfPositive, Important);
    Exit;
  end;

  if Name = Ord(psid_text_decoration_color) then
  begin
    if ParseTextDecorationColor(Val, Clr) then
      AddParsedProperty(Name, TPixiePropertyValue.FromColor(Clr, Important));
    Exit;
  end;

  if Name = Ord(psid_text_decoration_line) then
  begin
    ParseTextDecorationLine(Tokens, Important);
    Exit;
  end;

  if Name = Ord(psid_text_emphasis) then
  begin
    ParseTextEmphasis(Tokens, Important);
    Exit;
  end;

  if Name = Ord(psid_text_emphasis_style) then
  begin
    S := PixieCssGetRepr(Tokens, 0, -1, True);
    AddParsedProperty(Name, TPixiePropertyValue.FromString(S, Important));
    Exit;
  end;

  if Name = Ord(psid_text_emphasis_color) then
  begin
    if ParseTextDecorationColor(Val, Clr) then
      AddParsedProperty(Name, TPixiePropertyValue.FromColor(Clr, Important));
    Exit;
  end;

  if Name = Ord(psid_text_emphasis_position) then
  begin
    ParseTextEmphasisPosition(Tokens, Important);
    Exit;
  end;

  // =============================  FLEX  =============================

  if Name = Ord(psid_flex) then
  begin
    ParseFlex(Tokens, Important);
    Exit;
  end;

  if (Name = Ord(psid_flex_grow)) or (Name = Ord(psid_flex_shrink)) then
  begin
    if (Val <> nil) and (Val.TokenType = cssTokenNumber) and (Val.Number >= 0) then
      AddParsedProperty(Name, TPixiePropertyValue.FromFloat(Val.Number, Important));
    Exit;
  end;

  if Name = Ord(psid_opacity) then
  begin
    if (Val <> nil) and (Val.TokenType = cssTokenNumber) then
      AddParsedProperty(Name, TPixiePropertyValue.FromFloat(
        Max(0, Min(1, Val.Number)), Important));
    Exit;
  end;

  // aspect-ratio: <number> | <number> / <number> | auto
  // Stored as a Single (width / height); 0 means unset/auto.
  if Name = Ord(psid_aspect_ratio) then
  begin
    if (Val <> nil) and (Val.TokenType = cssTokenNumber) and (Val.Number > 0) then
      AddParsedProperty(Name, TPixiePropertyValue.FromFloat(Val.Number, Important))
    else if (Tokens.Count = 3) and
            (Tokens[0].TokenType = cssTokenNumber) and
            (Tokens[0].Number > 0) and
            (Tokens[1].TokenType = Ord('/')) and
            (Tokens[2].TokenType = cssTokenNumber) and
            (Tokens[2].Number > 0) then
      AddParsedProperty(Name, TPixiePropertyValue.FromFloat(
        Tokens[0].Number / Tokens[2].Number, Important));
    Exit;
  end;

  if Name = Ord(psid_flex_basis) then
  begin
    AddLengthProperty(Name, Val, FlexBasisStrings, clfLengthPercentage or clfPositive, Important);
    Exit;
  end;

  if Name = Ord(psid_flex_flow) then
  begin
    ParseFlexFlow(Tokens, Important);
    Exit;
  end;

  if (Name = Ord(psid_align_items)) or (Name = Ord(psid_align_self)) then
  begin
    ParseAlignSelf(Name, Tokens, Important);
    Exit;
  end;

  if Name = Ord(psid_order) then
  begin
    if (Val <> nil) and (Val.TokenType = cssTokenNumber) and
       (Val.NumberType = cssNumberInteger) then
      AddParsedProperty(Name, TPixiePropertyValue.FromInt(Round(Val.Number), Important));
    Exit;
  end;

  // Grid template tracks
  if (Name = Ord(psid_grid_template_columns)) or
     (Name = Ord(psid_grid_template_rows)) then
  begin
    ParseGridTemplate(Name, Tokens, Important);
    Exit;
  end;

  // Grid line placement (longhand): auto | <integer> | span <integer>
  if (Name = Ord(psid_grid_column_start)) or (Name = Ord(psid_grid_column_end)) or
     (Name = Ord(psid_grid_row_start)) or (Name = Ord(psid_grid_row_end)) then
  begin
    if Ident = 'auto' then
      AddParsedProperty(Name, TPixiePropertyValue.FromLength(
        TPixieCssLength.PredefValue(0), Important))
    else if (Tokens.Count = 1) and (Val <> nil) and
            (Val.TokenType = cssTokenNumber) and
            (Val.NumberType = cssNumberInteger) and (Val.Number > 0) then
      // Line number: stored as positive value
      AddParsedProperty(Name, TPixiePropertyValue.FromLength(
        TPixieCssLength.Create(Val.Number, cssUnitsNone), Important))
    else if (Tokens.Count = 2) and (TokenIdent(Tokens[0]) = 'span') and
            (Tokens[1].TokenType = cssTokenNumber) and
            (Tokens[1].NumberType = cssNumberInteger) and (Tokens[1].Number > 0) then
      // Span N: stored as negative value
      AddParsedProperty(Name, TPixiePropertyValue.FromLength(
        TPixieCssLength.Create(-Tokens[1].Number, cssUnitsNone), Important));
    Exit;
  end;

  // Grid line shorthands: grid-column, grid-row -> start / end
  if (Name = Ord(psid_grid_column)) or (Name = Ord(psid_grid_row)) then
  begin
    ParseGridLine(Name, Tokens, Important);
    Exit;
  end;

  // Justify items/self (reuse align-items/self parsing)
  if (Name = Ord(psid_justify_items)) or (Name = Ord(psid_justify_self)) then
  begin
    ParseAlignSelf(Name, Tokens, Important);
    Exit;
  end;

  if (Name = Ord(psid_row_gap)) or (Name = Ord(psid_column_gap)) then
  begin
    AddLengthProperty(Name, Val, 'normal', clfLengthPercentage or clfPositive, Important);
    Exit;
  end;

  if Name = Ord(psid_gap) then
  begin
    // gap: <row-gap> <column-gap>?
    // If only one value, it applies to both
    N := Parse1234Lengths(Tokens, Len, clfLengthPercentage or clfPositive, 'normal');
    if N >= 1 then
    begin
      AddParsedProperty(Ord(psid_row_gap), TPixiePropertyValue.FromLength(Len[0], Important));
      if N >= 2 then
        AddParsedProperty(Ord(psid_column_gap), TPixiePropertyValue.FromLength(Len[1], Important))
      else
        AddParsedProperty(Ord(psid_column_gap), TPixiePropertyValue.FromLength(Len[0], Important));
    end;
    Exit;
  end;

  // =============================  COUNTER, CONTENT  =============================

  if (Name = Ord(psid_counter_increment)) or (Name = Ord(psid_counter_reset)) then
  begin
    Vec := TPixieStringVector.Create;
    for I := 0 to Tokens.Count - 1 do
      Vec.Add(Tokens[I].GetRepr(True));
    AddParsedProperty(Name, TPixiePropertyValue.FromStringVec(Vec, Important));
    Exit;
  end;

  if Name = Ord(psid_content) then
  begin
    S := PixieCssGetRepr(Tokens, 0, -1, True);
    AddParsedProperty(Name, TPixiePropertyValue.FromString(S, Important));
    Exit;
  end;

  // =============================  OTHER  =============================

  if Name = Ord(psid_cursor) then
  begin
    S := PixieCssGetRepr(Tokens, 0, -1, True);
    AddParsedProperty(Name, TPixiePropertyValue.FromString(S, Important));
    Exit;
  end;

  if (Name = Ord(psid_transform)) or (Name = Ord(psid_transform_origin)) then
  begin
    S := PixieCssGetRepr(Tokens, 0, -1, True);
    AddParsedProperty(Name, TPixiePropertyValue.FromString(S, Important));
    Exit;
  end;

  // SVG presentation properties — stored as raw strings and surfaced by
  // Pixie.ElSvg.SerializeElement as XML attributes on inline SVG.
  for I := Low(PixieSvgPresentationPropIds) to High(PixieSvgPresentationPropIds) do
    if Name = Ord(PixieSvgPresentationPropIds[I]) then
    begin
      S := PixieCssGetRepr(Tokens, 0, -1, True);
      AddParsedProperty(Name, TPixiePropertyValue.FromString(S, Important));
      Exit;
    end;

  // =============================  CUSTOM PROPERTY  =============================

  if (Length(NameStr) >= 3) and (NameStr[1] = '-') and (NameStr[2] = '-') then
  begin
    if (Tokens.Count = 0) or PixieCssIsDeclarationValue(Tokens) then
    begin
      TokensCopy := TPixieCssTokenList.Create;
      PixieCssTokenListCopy(Tokens, TokensCopy);
      AddParsedProperty(Name, TPixiePropertyValue.FromTokenVec(TokensCopy, Important, False));
    end;
  end;
end;

function TPixieStyle.GetProperty(Name: Integer): TPixiePropertyValue;
begin
  if not FProperties.TryGetValue(Name, Result) then
    Result := TPixiePropertyValue.Invalid;
end;

procedure TPixieStyle.Combine(Src: TPixieStyle);
var
  Pair: TPair<Integer, TPixiePropertyValue>;
begin
  for Pair in Src.FProperties do
    AddParsedProperty(Pair.Key, Pair.Value.Clone);
end;

procedure TPixieStyle.InheritProperty(Name: Integer; Important: Boolean);
var
  Atoms: TPixieIntVector;
  I: Integer;
begin
  if ShorthandMap.TryGetValue(Name, Atoms) then
  begin
    for I := 0 to Atoms.Count - 1 do
      AddParsedProperty(Atoms[I], TPixiePropertyValue.Inherit(Important));
  end
  else
    AddParsedProperty(Name, TPixiePropertyValue.Inherit(Important));
end;

procedure TPixieStyle.AddParsedProperty(Name: Integer; const PropVal: TPixiePropertyValue);
var
  Existing: TPixiePropertyValue;
begin
  if FProperties.TryGetValue(Name, Existing) then
  begin
    if (not Existing.Important) or (PropVal.Important and Existing.Important) then
    begin
      Existing.FreeOwnedObjects;
      FProperties[Name] := PropVal;
    end;
  end
  else
    FProperties.Add(Name, PropVal);
end;

procedure TPixieStyle.AddLengthProperty(Name: Integer; Val: TPixieCssToken;
  const Keywords: string; Options: Integer; Important: Boolean);
var
  Len: TPixieCssLength;
begin
  if PixieParseCssLength(Val, Len, Options, Keywords) then
    AddParsedProperty(Name, TPixiePropertyValue.FromLength(Len, Important));
end;

// Maps n values to 4 properties in TRBL order. The four property IDs are
// consecutive starting from TopName.
procedure TPixieStyle.AddFourLengths(TopName: Integer; const Len: array of TPixieCssLength;
  N: Integer; Important: Boolean);
var
  TopIdx, RightIdx, BottomIdx, LeftIdx: Integer;
begin
  TopIdx := 0;
  if N > 1 then RightIdx := 1 else RightIdx := 0;
  BottomIdx := (N div 3) * 2;
  LeftIdx := (N div 2) + (N div 4);

  AddParsedProperty(TopName,     TPixiePropertyValue.FromLength(Len[TopIdx], Important));
  AddParsedProperty(TopName + 1, TPixiePropertyValue.FromLength(Len[RightIdx], Important));
  AddParsedProperty(TopName + 2, TPixiePropertyValue.FromLength(Len[BottomIdx], Important));
  AddParsedProperty(TopName + 3, TPixiePropertyValue.FromLength(Len[LeftIdx], Important));
end;

procedure TPixieStyle.AddFourInts(TopName: Integer; const Vals: array of Integer;
  N: Integer; Important: Boolean);
var
  TopIdx, RightIdx, BottomIdx, LeftIdx: Integer;
begin
  TopIdx := 0;
  if N > 1 then RightIdx := 1 else RightIdx := 0;
  BottomIdx := (N div 3) * 2;
  LeftIdx := (N div 2) + (N div 4);

  AddParsedProperty(TopName,     TPixiePropertyValue.FromInt(Vals[TopIdx], Important));
  AddParsedProperty(TopName + 1, TPixiePropertyValue.FromInt(Vals[RightIdx], Important));
  AddParsedProperty(TopName + 2, TPixiePropertyValue.FromInt(Vals[BottomIdx], Important));
  AddParsedProperty(TopName + 3, TPixiePropertyValue.FromInt(Vals[LeftIdx], Important));
end;

procedure TPixieStyle.AddFourColors(TopName: Integer; const Cols: array of TPixieWebColor;
  N: Integer; Important: Boolean);
var
  TopIdx, RightIdx, BottomIdx, LeftIdx: Integer;
begin
  TopIdx := 0;
  if N > 1 then RightIdx := 1 else RightIdx := 0;
  BottomIdx := (N div 3) * 2;
  LeftIdx := (N div 2) + (N div 4);

  AddParsedProperty(TopName,     TPixiePropertyValue.FromColor(Cols[TopIdx], Important));
  AddParsedProperty(TopName + 1, TPixiePropertyValue.FromColor(Cols[RightIdx], Important));
  AddParsedProperty(TopName + 2, TPixiePropertyValue.FromColor(Cols[BottomIdx], Important));
  AddParsedProperty(TopName + 3, TPixiePropertyValue.FromColor(Cols[LeftIdx], Important));
end;

{ Shorthand parsers }

procedure TPixieStyle.ParseBackground(Tokens: TPixieCssTokenList;
  const BaseUrl: string; Important: Boolean);
var
  Layers: TPixieCssTokenListList;
  I, J: Integer;
  Layer: TPixieCssTokenList;
  Tok: TPixieCssToken;
  Color: TPixieWebColor;
  PosX, PosY: TPixieCssLength;
  Size: TPixieCssSize;
  Repeat_, Attachment, Origin, Clip: Integer;
  Url: string;
  ColorFound, ImageFound, PositionFound, RepeatFound: Boolean;
  AttachmentFound, OriginFound, ClipFound: Boolean;
  IsFinalLayer: Boolean;
  XPositions, YPositions: TPixieLengthVector;
  Sizes: TPixieSizeVector;
  Repeats, Attachments, Origins, Clips: TPixieIntVector;
  ImageTokens: TPixieCssTokenList;
  BgColor: TPixieWebColor;

  function IsBgImage(T: TPixieCssToken): Boolean;
  begin
    Result := False;
    if T = nil then Exit;
    // none
    if TokenIdent(T) = 'none' then Exit(True);
    // url(...)
    if PixieParseUrl(T, Url) then Exit(True);
    // gradient function: linear-gradient, radial-gradient, etc.
    if (T.TokenType = cssTokenCvFunction) and
       (PixieValueIndex(PixieLowerCase(T.Str),
         'linear-gradient;repeating-linear-gradient;' +
         'radial-gradient;repeating-radial-gradient;' +
         'conic-gradient;repeating-conic-gradient') >= 0) then
      Exit(True);
  end;

  procedure CleanupAndExit;
  begin
    XPositions.Free;
    YPositions.Free;
    Sizes.Free;
    Repeats.Free;
    Attachments.Free;
    Origins.Free;
    Clips.Free;
    ImageTokens.Free;
  end;

begin
  Layers := PixieCssParseCommaSeparatedList(Tokens);
  try
    if Layers.Count = 0 then
      Exit;

    XPositions := TPixieLengthVector.Create;
    YPositions := TPixieLengthVector.Create;
    Sizes := TPixieSizeVector.Create;
    Repeats := TPixieIntVector.Create;
    Attachments := TPixieIntVector.Create;
    Origins := TPixieIntVector.Create;
    Clips := TPixieIntVector.Create;
    ImageTokens := TPixieCssTokenList.Create;
    BgColor := TPixieWebColor.Transparent;

    try
      for I := 0 to Layers.Count - 1 do
      begin
        Layer := Layers[I];
        IsFinalLayer := (I = Layers.Count - 1);

        Color := TPixieWebColor.Transparent;
        PosX := TPixieCssLength.Create(0, cssUnitsPercentage);
        PosY := TPixieCssLength.Create(0, cssUnitsPercentage);
        Size := TPixieCssSize.Create(
          TPixieCssLength.PredefValue(Ord(bszAuto)),
          TPixieCssLength.PredefValue(Ord(bszAuto)));
        Repeat_ := Ord(brRepeat);
        Attachment := Ord(baScroll);
        Origin := Ord(bbPadding);
        Clip := Ord(bbBorder);

        ColorFound := False;
        ImageFound := False;
        PositionFound := False;
        RepeatFound := False;
        AttachmentFound := False;
        OriginFound := False;
        ClipFound := False;
        Url := '';

        J := 0;
        while J < Layer.Count do
        begin
          Tok := Layer[J];
          if (not ColorFound) and IsFinalLayer and PixieParseCssColor(Tok, Color) then
            ColorFound := True
          else if (not ImageFound) and IsBgImage(Tok) then
          begin
            ImageFound := True;
            ImageTokens.Add(PixieCssTokenClone(Tok));
          end
          else if (not PositionFound) and ParseBgPositionSize(Layer, J, PosX, PosY, Size) then
          begin
            PositionFound := True;
            Dec(J); // ParseBgPositionSize already advanced J
          end
          else if (not RepeatFound) and PixieParseKeyword(Tok, Repeat_, BackgroundRepeatStrings) then
            RepeatFound := True
          else if (not AttachmentFound) and PixieParseKeyword(Tok, Attachment, BackgroundAttachmentStrings) then
            AttachmentFound := True
          else if (not OriginFound) and PixieParseKeyword(Tok, Origin, BackgroundBoxStrings) then
          begin
            OriginFound := True;
            Clip := Origin;
          end
          else if (not ClipFound) and PixieParseKeyword(Tok, Clip, BackgroundBoxStrings) then
            ClipFound := True
          else
          begin
            CleanupAndExit;
            Exit;
          end;
          Inc(J);
        end;

        // If no image token found, add a "none" placeholder
        if not ImageFound then
        begin
          Tok := TPixieCssToken.Create;
          Tok.TokenType := cssTokenIdent;
          Tok.Str := 'none';
          ImageTokens.Add(Tok);
        end;

        BgColor := Color;
        XPositions.Add(PosX);
        YPositions.Add(PosY);
        Sizes.Add(Size);
        Repeats.Add(Repeat_);
        Attachments.Add(Attachment);
        Origins.Add(Origin);
        Clips.Add(Clip);
      end;

      AddParsedProperty(Ord(psid_background_color),
        TPixiePropertyValue.FromColor(BgColor, Important));
      AddParsedProperty(Ord(psid_background_image),
        TPixiePropertyValue.FromTokenVec(ImageTokens, Important, False));
      AddParsedProperty(Ord(psid_background_image_baseurl),
        TPixiePropertyValue.FromString(BaseUrl, Important));
      AddParsedProperty(Ord(psid_background_position_x),
        TPixiePropertyValue.FromLengthVec(XPositions, Important));
      AddParsedProperty(Ord(psid_background_position_y),
        TPixiePropertyValue.FromLengthVec(YPositions, Important));
      AddParsedProperty(Ord(psid_background_size),
        TPixiePropertyValue.FromSizeVec(Sizes, Important));
      AddParsedProperty(Ord(psid_background_repeat),
        TPixiePropertyValue.FromIntVec(Repeats, Important));
      AddParsedProperty(Ord(psid_background_attachment),
        TPixiePropertyValue.FromIntVec(Attachments, Important));
      AddParsedProperty(Ord(psid_background_origin),
        TPixiePropertyValue.FromIntVec(Origins, Important));
      AddParsedProperty(Ord(psid_background_clip),
        TPixiePropertyValue.FromIntVec(Clips, Important));
    except
      CleanupAndExit;
      raise;
    end;
  finally
    for I := 0 to Layers.Count - 1 do
      Layers[I].Free;
    Layers.Free;
  end;
end;

procedure TPixieStyle.ParseBackgroundImage(Tokens: TPixieCssTokenList;
  const BaseUrl: string; Important: Boolean);
var
  Layers: TPixieCssTokenListList;
  I: Integer;
  ImageTokens: TPixieCssTokenList;
begin
  Layers := PixieCssParseCommaSeparatedList(Tokens);
  try
    if Layers.Count = 0 then
      Exit;

    ImageTokens := TPixieCssTokenList.Create;
    for I := 0 to Layers.Count - 1 do
    begin
      if Layers[I].Count <> 1 then
      begin
        ImageTokens.Free;
        Exit;
      end;
      ImageTokens.Add(PixieCssTokenClone(Layers[I][0]));
    end;

    AddParsedProperty(Ord(psid_background_image),
      TPixiePropertyValue.FromTokenVec(ImageTokens, Important, False));
    AddParsedProperty(Ord(psid_background_image_baseurl),
      TPixiePropertyValue.FromString(BaseUrl, Important));
  finally
    for I := 0 to Layers.Count - 1 do
      Layers[I].Free;
    Layers.Free;
  end;
end;

procedure TPixieStyle.ParseKeywordCommaList(Name: Integer; Tokens: TPixieCssTokenList;
  Important: Boolean);
var
  Layers: TPixieCssTokenListList;
  I, Idx: Integer;
  Vec: TPixieIntVector;
  ValidStr: string;
begin
  Layers := PixieCssParseCommaSeparatedList(Tokens);
  try
    ValidStr := PixieGetValidValues(Name);
    if ValidStr = '' then
      Exit;

    Vec := TPixieIntVector.Create;
    for I := 0 to Layers.Count - 1 do
    begin
      if Layers[I].Count <> 1 then
      begin
        Vec.Free;
        Exit;
      end;
      if not PixieParseKeyword(Layers[I][0], Idx, ValidStr) then
      begin
        Vec.Free;
        Exit;
      end;
      Vec.Add(Idx);
    end;

    AddParsedProperty(Name, TPixiePropertyValue.FromIntVec(Vec, Important));
  finally
    for I := 0 to Layers.Count - 1 do
      Layers[I].Free;
    Layers.Free;
  end;
end;

procedure TPixieStyle.ParseBackgroundPosition(Tokens: TPixieCssTokenList; Important: Boolean);
var
  Layers: TPixieCssTokenListList;
  I, Index: Integer;
  X, Y: TPixieCssLength;
  XPos, YPos: TPixieLengthVector;
begin
  Layers := PixieCssParseCommaSeparatedList(Tokens);
  try
    if Layers.Count = 0 then
      Exit;

    XPos := TPixieLengthVector.Create;
    YPos := TPixieLengthVector.Create;

    for I := 0 to Layers.Count - 1 do
    begin
      Index := 0;
      if not PixieParseBgPosition(Layers[I], Index, X, Y, True) or
         (Index <> Layers[I].Count) then
      begin
        XPos.Free;
        YPos.Free;
        Exit;
      end;
      XPos.Add(X);
      YPos.Add(Y);
    end;

    AddParsedProperty(Ord(psid_background_position_x),
      TPixiePropertyValue.FromLengthVec(XPos, Important));
    AddParsedProperty(Ord(psid_background_position_y),
      TPixiePropertyValue.FromLengthVec(YPos, Important));
  finally
    for I := 0 to Layers.Count - 1 do
      Layers[I].Free;
    Layers.Free;
  end;
end;

procedure TPixieStyle.ParseBackgroundSize(Tokens: TPixieCssTokenList; Important: Boolean);
var
  Layers: TPixieCssTokenListList;
  I, Index: Integer;
  Size: TPixieCssSize;
  Sizes: TPixieSizeVector;
begin
  Layers := PixieCssParseCommaSeparatedList(Tokens);
  try
    if Layers.Count = 0 then
      Exit;

    Sizes := TPixieSizeVector.Create;
    for I := 0 to Layers.Count - 1 do
    begin
      Index := 0;
      if not ParseBgSize(Layers[I], Index, Size) or (Index <> Layers[I].Count) then
      begin
        Sizes.Free;
        Exit;
      end;
      Sizes.Add(Size);
    end;

    AddParsedProperty(Ord(psid_background_size),
      TPixiePropertyValue.FromSizeVec(Sizes, Important));
  finally
    for I := 0 to Layers.Count - 1 do
      Layers[I].Free;
    Layers.Free;
  end;
end;

procedure TPixieStyle.ParseBorder(Tokens: TPixieCssTokenList; Important: Boolean);
var
  Width: TPixieCssLength;
  Style: Integer;
  Color: TPixieWebColor;
begin
  if not ParseBorderHelper(Tokens, Width, Style, Color) then
    Exit;

  AddParsedProperty(Ord(psid_border_left_width), TPixiePropertyValue.FromLength(Width, Important));
  AddParsedProperty(Ord(psid_border_right_width), TPixiePropertyValue.FromLength(Width, Important));
  AddParsedProperty(Ord(psid_border_top_width), TPixiePropertyValue.FromLength(Width, Important));
  AddParsedProperty(Ord(psid_border_bottom_width), TPixiePropertyValue.FromLength(Width, Important));

  AddParsedProperty(Ord(psid_border_left_style), TPixiePropertyValue.FromInt(Style, Important));
  AddParsedProperty(Ord(psid_border_right_style), TPixiePropertyValue.FromInt(Style, Important));
  AddParsedProperty(Ord(psid_border_top_style), TPixiePropertyValue.FromInt(Style, Important));
  AddParsedProperty(Ord(psid_border_bottom_style), TPixiePropertyValue.FromInt(Style, Important));

  AddParsedProperty(Ord(psid_border_left_color), TPixiePropertyValue.FromColor(Color, Important));
  AddParsedProperty(Ord(psid_border_right_color), TPixiePropertyValue.FromColor(Color, Important));
  AddParsedProperty(Ord(psid_border_top_color), TPixiePropertyValue.FromColor(Color, Important));
  AddParsedProperty(Ord(psid_border_bottom_color), TPixiePropertyValue.FromColor(Color, Important));
end;

procedure TPixieStyle.ParseOutline(Tokens: TPixieCssTokenList; Important: Boolean);
var
  Width: TPixieCssLength;
  Style: Integer;
  Color: TPixieWebColor;
begin
  if not ParseBorderHelper(Tokens, Width, Style, Color) then
    Exit;
  AddParsedProperty(Ord(psid_outline_width), TPixiePropertyValue.FromLength(Width, Important));
  AddParsedProperty(Ord(psid_outline_style), TPixiePropertyValue.FromInt(Style, Important));
  AddParsedProperty(Ord(psid_outline_color), TPixiePropertyValue.FromColor(Color, Important));
end;

procedure TPixieStyle.ParseBorderSide(Name: Integer; Tokens: TPixieCssTokenList;
  Important: Boolean);
var
  Width: TPixieCssLength;
  Style: Integer;
  Color: TPixieWebColor;
  NameStr: string;
begin
  if not ParseBorderHelper(Tokens, Width, Style, Color) then
    Exit;
  NameStr := PixieStr(Name);
  AddParsedProperty(PixieId(NameStr + '-width'), TPixiePropertyValue.FromLength(Width, Important));
  AddParsedProperty(PixieId(NameStr + '-style'), TPixiePropertyValue.FromInt(Style, Important));
  AddParsedProperty(PixieId(NameStr + '-color'), TPixiePropertyValue.FromColor(Color, Important));
end;

procedure TPixieStyle.ParseBorderRadius(Tokens: TPixieCssTokenList; Important: Boolean);
var
  I, N, M: Integer;
  SlashIdx: Integer;
  RX, RY, Len: array[0..3] of TPixieCssLength;
  XTokens, YTokens: TPixieCssTokenList;
begin
  // Find '/' separator
  SlashIdx := -1;
  for I := 0 to Tokens.Count - 1 do
    if TokenCh(Tokens[I]) = '/' then
    begin
      SlashIdx := I;
      Break;
    end;

  if SlashIdx < 0 then
  begin
    // No '/' - same radii for X and Y
    N := Parse1234Lengths(Tokens, Len, clfLengthPercentage or clfPositive);
    if N > 0 then
    begin
      AddFourLengths(Ord(psid_border_top_left_radius_x), Len, N, Important);
      AddFourLengths(Ord(psid_border_top_left_radius_y), Len, N, Important);
    end;
  end
  else
  begin
    // Separate X and Y radii
    XTokens := TPixieCssTokenList.Create(False);
    YTokens := TPixieCssTokenList.Create(False);
    try
      for I := 0 to SlashIdx - 1 do
        XTokens.Add(Tokens[I]);
      for I := SlashIdx + 1 to Tokens.Count - 1 do
        YTokens.Add(Tokens[I]);

      N := Parse1234Lengths(XTokens, RX, clfLengthPercentage or clfPositive);
      M := Parse1234Lengths(YTokens, RY, clfLengthPercentage or clfPositive);
      if (N > 0) and (M > 0) then
      begin
        AddFourLengths(Ord(psid_border_top_left_radius_x), RX, N, Important);
        AddFourLengths(Ord(psid_border_top_left_radius_y), RY, M, Important);
      end;
    finally
      XTokens.Free;
      YTokens.Free;
    end;
  end;
end;

procedure TPixieStyle.ParseListStyle(Tokens: TPixieCssTokenList; const BaseUrl: string;
  Important: Boolean);
var
  I: Integer;
  Tok: TPixieCssToken;
  LstType, Position: Integer;
  Image, Url: string;
  TypeFound, PositionFound, ImageFound: Boolean;
  NoneCount: Integer;
begin
  LstType := Ord(lstDisc);
  Position := Ord(lspOutside);
  Image := '';

  TypeFound := False;
  PositionFound := False;
  ImageFound := False;
  NoneCount := 0;

  for I := 0 to Tokens.Count - 1 do
  begin
    Tok := Tokens[I];
    if TokenIdent(Tok) = 'none' then
    begin
      Inc(NoneCount);
      Continue;
    end;
    if (not TypeFound) and PixieParseKeyword(Tok, LstType, ListStyleTypeStrings) then
      TypeFound := True
    else if (not PositionFound) and PixieParseKeyword(Tok, Position, ListStylePositionStrings) then
      PositionFound := True
    else if (not ImageFound) and ParseListStyleImage(Tok, Url) then
    begin
      Image := Url;
      ImageFound := True;
    end
    else
      Exit; // syntax error
  end;

  case NoneCount of
    0: ;
    1:
    begin
      if TypeFound and ImageFound then Exit;
      if not TypeFound then LstType := Ord(lstNone);
    end;
    2:
    begin
      if TypeFound or ImageFound then Exit;
      LstType := Ord(lstNone);
    end;
  else
    Exit;
  end;

  AddParsedProperty(Ord(psid_list_style_type), TPixiePropertyValue.FromInt(LstType, Important));
  AddParsedProperty(Ord(psid_list_style_position), TPixiePropertyValue.FromInt(Position, Important));
  AddParsedProperty(Ord(psid_list_style_image), TPixiePropertyValue.FromString(Image, Important));
  AddParsedProperty(Ord(psid_list_style_image_baseurl), TPixiePropertyValue.FromString(BaseUrl, Important));
end;

procedure TPixieStyle.ParseFont(Tokens: TPixieCssTokenList; Important: Boolean);
var
  Index: Integer;
  FontStyle, FontVariant: Integer;
  Weight, FontSize, LineHeight: TPixieCssLength;
  Family: string;
  Tok: TPixieCssToken;
begin
  FontStyle := Ord(fstNormal);
  FontVariant := Ord(fvNormal);
  Weight := TPixieCssLength.PredefValue(Ord(fwNormal));
  FontSize := TPixieCssLength.PredefValue(Ord(fsMedium));
  LineHeight := TPixieCssLength.PredefValue;

  // Check for system font (single ident)
  if (Tokens.Count = 1) and
     ((Tokens[0].TokenType = cssTokenString) or (Tokens[0].TokenType = cssTokenIdent)) and
     PixieValueInList(Tokens[0].Str, FontSystemFamilyNameStrings) then
  begin
    Family := Tokens[0].Str;
  end
  else
  begin
    Index := 0;
    ParseFontStyleVariantWeight(Tokens, Index, FontStyle, FontVariant, Weight);

    // font-size (required)
    Tok := PixieTokenAt(Tokens, Index);
    if not PixieParseCssLength(Tok, FontSize, clfLengthPercentage or clfPositive, FontSizeStrings) then
      Exit;
    Inc(Index);

    // Optional: / line-height
    Tok := PixieTokenAt(Tokens, Index);
    if (Tok <> nil) and (TokenCh(Tok) = '/') then
    begin
      Inc(Index);
      Tok := PixieTokenAt(Tokens, Index);
      if not PixieParseCssLength(Tok, LineHeight, clfNumber or clfLengthPercentage, LineHeightStrings) then
        Exit;
      Inc(Index);
    end;

    // font-family (rest of tokens)
    if not ParseFontFamily(Tokens, Index, Family) then
      Exit;
  end;

  AddParsedProperty(Ord(psid_font_style), TPixiePropertyValue.FromInt(FontStyle, Important));
  AddParsedProperty(Ord(psid_font_variant), TPixiePropertyValue.FromInt(FontVariant, Important));
  AddParsedProperty(Ord(psid_font_weight), TPixiePropertyValue.FromLength(Weight, Important));
  AddParsedProperty(Ord(psid_font_size), TPixiePropertyValue.FromLength(FontSize, Important));
  AddParsedProperty(Ord(psid_line_height), TPixiePropertyValue.FromLength(LineHeight, Important));
  AddParsedProperty(Ord(psid_font_family), TPixiePropertyValue.FromString(Family, Important));
end;

procedure TPixieStyle.ParseTextDecoration(Tokens: TPixieCssTokenList; Important: Boolean);
var
  I: Integer;
  Tok: TPixieCssToken;
  Len: TPixieCssLength;
  LineTokens: TPixieCssTokenList;
  Clr: TPixieWebColor;
  Style: Integer;
begin
  LineTokens := TPixieCssTokenList.Create(False);
  try
    for I := 0 to Tokens.Count - 1 do
    begin
      Tok := Tokens[I];
      if ParseTextDecorationColor(Tok, Clr) then
      begin
        AddParsedProperty(Ord(psid_text_decoration_color),
          TPixiePropertyValue.FromColor(Clr, Important));
        Continue;
      end;

      if PixieParseCssLength(Tok, Len, clfLengthPercentage or clfPositive,
                             TextDecorationThicknessStrings) then
      begin
        AddParsedProperty(Ord(psid_text_decoration_thickness),
          TPixiePropertyValue.FromLength(Len, Important));
      end
      else if (Tok.TokenType = cssTokenIdent) then
      begin
        Style := PixieValueIndex(Tok.Ident, TextDecorationStyleStrings);
        if Style >= 0 then
          AddParsedProperty(Ord(psid_text_decoration_style),
            TPixiePropertyValue.FromInt(Style, Important))
        else
          LineTokens.Add(Tok);
      end
      else
        LineTokens.Add(Tok);
    end;

    if LineTokens.Count > 0 then
      ParseTextDecorationLine(LineTokens, Important);
  finally
    LineTokens.Free;
  end;
end;

procedure TPixieStyle.ParseTextDecorationLine(Tokens: TPixieCssTokenList; Important: Boolean);
var
  I, Idx, Val: Integer;
begin
  Val := 0;
  for I := 0 to Tokens.Count - 1 do
  begin
    if Tokens[I].TokenType = cssTokenIdent then
    begin
      Idx := PixieValueIndex(Tokens[I].Ident, TextDecorationLineStrings);
      if Idx >= 1 then // skip 'none' (idx=0)
        Val := Val or (1 shl (Idx - 1));
    end;
  end;
  AddParsedProperty(Ord(psid_text_decoration_line),
    TPixiePropertyValue.FromInt(Val, Important));
end;

procedure TPixieStyle.ParseTextEmphasis(Tokens: TPixieCssTokenList; Important: Boolean);
var
  I: Integer;
  Tok: TPixieCssToken;
  Words: TStringList;
  Clr: TPixieWebColor;
begin
  Words := TStringList.Create;
  try
    Words.Delimiter := ' ';
    Words.StrictDelimiter := True;
    // Walk forward; non-color tokens become style words preserving order.
    for I := 0 to Tokens.Count - 1 do
    begin
      Tok := Tokens[I];
      if ParseTextDecorationColor(Tok, Clr) then
      begin
        AddParsedProperty(Ord(psid_text_emphasis_color),
          TPixiePropertyValue.FromColor(Clr, Important));
        Continue;
      end;
      if Tok.TokenType = cssTokenWhitespace then
        Continue;
      Words.Add(Tok.Str);
    end;
    if Words.Count > 0 then
      AddParsedProperty(Ord(psid_text_emphasis_style),
        TPixiePropertyValue.FromString(Words.DelimitedText, Important));
  finally
    Words.Free;
  end;
end;

procedure TPixieStyle.ParseTextEmphasisPosition(Tokens: TPixieCssTokenList; Important: Boolean);
var
  I, Idx, Val: Integer;
begin
  Val := 0;
  for I := 0 to Tokens.Count - 1 do
  begin
    if Tokens[I].TokenType = cssTokenIdent then
    begin
      Idx := PixieValueIndex(Tokens[I].Ident, TextEmphasisPositionStrings);
      if Idx >= 0 then
        Val := Val or (1 shl (Idx - 1));
    end;
  end;
  AddParsedProperty(Ord(psid_text_emphasis_position),
    TPixiePropertyValue.FromInt(Val, Important));
end;

procedure TPixieStyle.ParseFlex(Tokens: TPixieCssTokenList; Important: Boolean);
var
  N: Integer;
  A, B, C: TPixieCssToken;
  Grow, Shrink: Single;
  Basis: TPixieCssLength;
  IdentId: Integer;
  AutoBasis: TPixieCssLength;
begin
  N := Tokens.Count;
  if (N < 1) or (N > 3) then
    Exit;

  A := PixieTokenAt(Tokens, 0);
  B := PixieTokenAt(Tokens, 1);
  C := PixieTokenAt(Tokens, 2);

  Grow := 1;
  Shrink := 1;
  Basis := TPixieCssLength.Create(0, cssUnitsPx);
  AutoBasis := TPixieCssLength.PredefValue(Ord(fbAuto));

  if N = 1 then
  begin
    IdentId := PixieId(TokenIdent(A));
    if (IdentId = Ord(psid_initial)) then
    begin
      Grow := 0; Shrink := 1; Basis := AutoBasis;
    end
    else if (IdentId = Ord(psid_auto)) then
    begin
      Grow := 1; Shrink := 1; Basis := AutoBasis;
    end
    else if (IdentId = Ord(psid_none)) then
    begin
      Grow := 0; Shrink := 0; Basis := AutoBasis;
    end
    else if (A.TokenType = cssTokenNumber) and (A.Number >= 0) then
      Grow := A.Number
    else if PixieParseCssLength(A, Basis, clfLengthPercentage or clfPositive, FlexBasisStrings) then
      { OK }
    else
      Exit;
  end
  else if N = 2 then
  begin
    // <number> <number>  or  <number> <basis>  or  <basis> <number>
    if (A.TokenType = cssTokenNumber) and (A.Number >= 0) then
    begin
      Grow := A.Number;
      if (B.TokenType = cssTokenNumber) and (B.Number >= 0) then
        Shrink := B.Number
      else if not PixieParseCssLength(B, Basis, clfLengthPercentage or clfPositive, FlexBasisStrings) then
        Exit;
    end
    else if PixieParseCssLength(A, Basis, clfLengthPercentage or clfPositive, FlexBasisStrings) then
    begin
      if (B.TokenType = cssTokenNumber) and (B.Number >= 0) then
        Grow := B.Number
      else
        Exit;
    end
    else
      Exit;
  end
  else // N = 3
  begin
    // <number> <number> <basis>  or  <basis> <number> <number>
    if (A.TokenType = cssTokenNumber) and (A.Number >= 0) then
    begin
      Grow := A.Number;
      if not ((B.TokenType = cssTokenNumber) and (B.Number >= 0)) then
        Exit;
      Shrink := B.Number;
      // Basis: unitless zero allowed here
      if (C.TokenType = cssTokenNumber) and (C.Number = 0) then
        Basis := TPixieCssLength.Create(0, cssUnitsPx)
      else if not PixieParseCssLength(C, Basis, clfLengthPercentage or clfPositive, FlexBasisStrings) then
        Exit;
    end
    else if PixieParseCssLength(A, Basis, clfLengthPercentage or clfPositive, FlexBasisStrings) then
    begin
      if not ((B.TokenType = cssTokenNumber) and (B.Number >= 0)) then Exit;
      Grow := B.Number;
      if not ((C.TokenType = cssTokenNumber) and (C.Number >= 0)) then Exit;
      Shrink := C.Number;
    end
    else
      Exit;
  end;

  AddParsedProperty(Ord(psid_flex_grow), TPixiePropertyValue.FromFloat(Grow, Important));
  AddParsedProperty(Ord(psid_flex_shrink), TPixiePropertyValue.FromFloat(Shrink, Important));
  AddParsedProperty(Ord(psid_flex_basis), TPixiePropertyValue.FromLength(Basis, Important));
end;

procedure TPixieStyle.ParseFlexFlow(Tokens: TPixieCssTokenList; Important: Boolean);
var
  I: Integer;
  Tok: TPixieCssToken;
  Direction, Wrap: Integer;
  DirectionFound, WrapFound: Boolean;
begin
  Direction := Ord(fdRow);
  Wrap := Ord(fwrNowrap);
  DirectionFound := False;
  WrapFound := False;

  for I := 0 to Tokens.Count - 1 do
  begin
    Tok := Tokens[I];
    if (not DirectionFound) and PixieParseKeyword(Tok, Direction, FlexDirectionStrings) then
      DirectionFound := True
    else if (not WrapFound) and PixieParseKeyword(Tok, Wrap, FlexWrapStrings) then
      WrapFound := True
    else
      Exit;
  end;

  AddParsedProperty(Ord(psid_flex_direction), TPixiePropertyValue.FromInt(Direction, Important));
  AddParsedProperty(Ord(psid_flex_wrap), TPixiePropertyValue.FromInt(Wrap, Important));
end;

procedure TPixieStyle.ParseAlignSelf(Name: Integer; Tokens: TPixieCssTokenList;
  Important: Boolean);
var
  N: Integer;
  A, BIdent: string;
  Idx: Integer;
begin
  N := Tokens.Count;
  if (N < 1) or (N > 2) then
    Exit;
  if Tokens[0].TokenType <> cssTokenIdent then
    Exit;
  if (N = 2) and (Tokens[1].TokenType <> cssTokenIdent) then
    Exit;

  A := Tokens[0].Ident;

  if (Name = Ord(psid_align_items)) and (A = 'auto') then
    Exit;

  if N = 1 then
  begin
    Idx := PixieValueIndex(A, FlexAlignItemsStrings);
    if Idx >= 0 then
      AddParsedProperty(Name, TPixiePropertyValue.FromInt(Idx, Important));
    Exit;
  end;

  // N = 2
  BIdent := Tokens[1].Ident;

  // baseline variants: "first baseline" / "last baseline"
  if A = 'baseline' then
  begin
    // swap
    A := BIdent;
    BIdent := 'baseline';
  end;
  if (BIdent = 'baseline') and IsOneOfStr(A, 'first', 'last') then
  begin
    Idx := PixieValueIndex('baseline', FlexAlignItemsStrings);
    if A = 'first' then
      Idx := Idx or FlexAlignItemsFirst
    else
      Idx := Idx or FlexAlignItemsLast;
    AddParsedProperty(Name, TPixiePropertyValue.FromInt(Idx, Important));
    Exit;
  end;

  // <overflow-position> <self-position>
  Idx := PixieValueIndex(BIdent, SelfPositionStrings);
  if (Idx >= 0) and IsOneOfStr(A, 'safe', 'unsafe') then
  begin
    if A = 'safe' then
      Idx := Idx or FlexAlignItemsSafe
    else
      Idx := Idx or FlexAlignItemsUnsafe;
    AddParsedProperty(Name, TPixiePropertyValue.FromInt(Idx, Important));
  end;
end;

{ var() substitution }

// Check that the arguments of a var() function have valid syntax:
//   var( <custom-property-name> , <declaration-value>? )
function CheckVarSyntax(Args: TPixieCssTokenList): Boolean;
var
  Name: string;
begin
  if (Args = nil) or (Args.Count = 0) then
    Exit(False);
  // First arg must be a custom property name (--xxx)
  Name := Args[0].Ident;
  if Name = '' then
    Exit(False);
  if (Length(Name) <= 2) or (StrLComp(PChar(Name), '--', 2) <> 0) then
    Exit(False);
  // If more args, second must be comma
  if (Args.Count > 1) and (Args[1].TokenType <> cssTokenComma) then
    Exit(False);
  // If more args after comma, must be valid declaration value
  if (Args.Count > 2) and not PixieCssIsDeclarationValue(Args, 2) then
    Exit(False);
  Result := True;
end;

// Substitute one var() reference.  Returns True if a substitution was made
// or if an error occurred (stops further iteration).
function SubstOneVar(Tokens: TPixieCssTokenList;
  Tag: TPixieHtmlTag; UsedVars: TPixieIntVector): Boolean;
var
  I, J, NameId: Integer;
  Tok: TPixieCssToken;
  Args: TPixieCssTokenList;
  Value: TPixieCssTokenList;
  Clone: TPixieCssToken;
begin
  I := 0;
  while I < Tokens.Count do
  begin
    Tok := Tokens[I];
    if (Tok.TokenType = cssTokenCvFunction) and
       SameText(Tok.Str, 'var') then
    begin
      // Clone args since we may modify them
      Args := TPixieCssTokenList.Create(True);
      try
        if Tok.Value <> nil then
          for J := 0 to Tok.Value.Count - 1 do
            Args.Add(PixieCssTokenClone(Tok.Value[J]));

        if not CheckVarSyntax(Args) then
          Exit(False);

        NameId := PixieId(Args[0].Str);
        // Check for dependency cycle
        if UsedVars.IndexOf(NameId) >= 0 then
          Exit(False);
        UsedVars.Add(NameId);

        Value := nil;
        if Tag.GetCustomProperty(NameId, Value) and
           (Value <> nil) then
        begin
          // Replace var() token with the custom property value
          Tokens.Delete(I); // removes and frees Tok
          for J := Value.Count - 1 downto 0 do
          begin
            Clone := PixieCssTokenClone(Value[J]);
            Tokens.Insert(I, Clone);
          end;
        end
        else
        begin
          // Custom property not defined — use fallback
          if Args.Count <= 1 then
            Exit(False); // no fallback provided
          // Remove custom-property-name and comma, keep rest as fallback
          Args.Delete(0); // name
          Args.Delete(0); // comma
          Tokens.Delete(I); // removes and frees var() token
          // Move fallback args into tokens
          Args.OwnsObjects := False;
          for J := Args.Count - 1 downto 0 do
            Tokens.Insert(I, Args[J]);
        end;
      finally
        Args.Free;
      end;
      Exit(True);
    end;

    // Recurse into component values
    if Tok.IsComponentValue and (Tok.Value <> nil) then
      if SubstOneVar(Tok.Value, Tag, UsedVars) then
        Exit(True);

    Inc(I);
  end;
  Result := False;
end;

procedure SubstVarsInTokens(Name: Integer; Tokens: TPixieCssTokenList;
  Tag: TPixieHtmlTag);
var
  UsedVars: TPixieIntVector;
begin
  UsedVars := TPixieIntVector.Create;
  try
    UsedVars.Add(Name);
    while SubstOneVar(Tokens, Tag, UsedVars) do
      { keep substituting until no more var() found };
  finally
    UsedVars.Free;
  end;
end;

function ContainsVarFunc(const S: string): Boolean;
var
  P, Len: Integer;
begin
  Len := Length(S);
  P := 1;
  while P <= Len - 3 do
  begin
    if ((S[P] = 'v') or (S[P] = 'V')) and
       ((S[P + 1] = 'a') or (S[P + 1] = 'A')) and
       ((S[P + 2] = 'r') or (S[P + 2] = 'R')) and
       (S[P + 3] = '(') then
      Exit(True);
    Inc(P);
  end;
  Result := False;
end;

function PixieResolveCssVars(const Value: string; El: TObject): string;
var
  Tag: TPixieHtmlTag;
  Tokens: TPixieCssTokenList;
  UsedVars: TPixieIntVector;
begin
  Result := Value;
  if not (El is TPixieHtmlTag) then Exit;
  if not ContainsVarFunc(Value) then Exit;
  Tag := TPixieHtmlTag(El);

  Tokens := PixieCssNormalizeStr(Value, cssCssNormComponentize);
  try
    UsedVars := TPixieIntVector.Create;
    try
      while SubstOneVar(Tokens, Tag, UsedVars) do
        { keep substituting until no more var() found };
    finally
      UsedVars.Free;
    end;
    Result := PixieCssGetRepr(Tokens, 0, -1, False);
  finally
    Tokens.Free;
  end;
end;

procedure TPixieStyle.SubstVars(El: TObject);
var
  Tag: TPixieHtmlTag;
  Keys: TPixieIntArray;
  I, Key: Integer;
  Prop: TPixiePropertyValue;
begin
  Assert(El is TPixieHtmlTag);
  Tag := TPixieHtmlTag(El);
  Keys := FProperties.Keys.ToArray;
  for I := 0 to Length(Keys) - 1 do
  begin
    Key := Keys[I];
    if not FProperties.TryGetValue(Key, Prop) then
      Continue;
    if not Prop.HasVar then
      Continue;
    if Prop.Kind <> pkTokenVector then
      Continue;
    if Prop.TokenVecVal = nil then
      Continue;

    SubstVarsInTokens(Key, Prop.TokenVecVal, Tag);
    // Re-add the property — if it's a standard CSS property it will be
    // parsed into a typed value; if custom property it stays as tokens.
    AddProperty(Key, Prop.TokenVecVal, '', Prop.Important);
  end;
end;

procedure TPixieStyle.ResolveCalcForKey(Key: Integer; const Ctx: TCalcContext);
var
  Prop: TPixiePropertyValue;
begin
  // Common case is "no deferred calc on this key" — exit before
  // touching the global so we don't pay an exception frame for nothing.
  if not FProperties.TryGetValue(Key, Prop) then Exit;
  if not Prop.HasCalc then Exit;
  if Prop.Kind <> pkTokenVector then Exit;
  if Prop.TokenVecVal = nil then Exit;
  GCalcCtx := @Ctx;
  try
    AddProperty(Key, Prop.TokenVecVal, '', Prop.Important);
  finally
    GCalcCtx := nil;
  end;
end;

procedure TPixieStyle.ResolveCalc(const Ctx: TCalcContext);
var
  Keys: TPixieIntArray;
  I: Integer;
begin
  Keys := FProperties.Keys.ToArray;
  for I := 0 to Length(Keys) - 1 do
    ResolveCalcForKey(Keys[I], Ctx);
end;

// --- Grid parsing ---

const
  GridTrackKeywords = 'auto;min-content;max-content';
  GridTrackFlags = clfLength or clfPercentage or clfPositive;

function ParseSingleGridTrack(const Tok: TPixieCssToken;
  Vec: TPixieLengthVector): Boolean;
var
  J, CommaIdx: Integer;
  Args: TPixieCssTokenList;
  Len, MinLen, MaxLen, MarkerLen: TPixieCssLength;
begin
  Result := False;

  // minmax(min, max)
  if (Tok.TokenType = cssTokenCvFunction) and
     (LowerCase(Tok.Str) = 'minmax') and (Tok.Value <> nil) then
  begin
    Args := Tok.Value;
    CommaIdx := -1;
    for J := 0 to Args.Count - 1 do
      if Args[J].TokenType = cssTokenComma then
      begin
        CommaIdx := J;
        Break;
      end;
    if (CommaIdx <= 0) or (CommaIdx >= Args.Count - 1) then Exit;
    if not PixieParseCssLength(Args[0], MinLen,
        GridTrackFlags, GridTrackKeywords) then Exit;
    if not PixieParseCssLength(Args[CommaIdx + 1], MaxLen,
        GridTrackFlags, GridTrackKeywords) then Exit;
    MarkerLen := TPixieCssLength.PredefValue(CssGridMinmaxMarker);
    Vec.Add(MarkerLen);
    Vec.Add(MinLen);
    Vec.Add(MaxLen);
    Result := True;
    Exit;
  end;

  // Plain length / percentage / fr / auto / min-content / max-content
  if PixieParseCssLength(Tok, Len, GridTrackFlags, GridTrackKeywords) then
  begin
    Vec.Add(Len);
    Result := True;
  end;
end;

procedure TPixieStyle.ParseGridTemplate(Name: Integer;
  Tokens: TPixieCssTokenList; Important: Boolean);
var
  Vec: TPixieLengthVector;
  I, J, K, RepeatCount, BeforeCount, AddedCount, CommaIdx: Integer;
  Tok: TPixieCssToken;
  Args: TPixieCssTokenList;
begin
  // grid-template-columns / grid-template-rows: <track-list> | none
  if (Tokens.Count = 1) and (TokenIdent(Tokens[0]) = 'none') then
  begin
    AddParsedProperty(Name, TPixiePropertyValue.FromLength(
      TPixieCssLength.PredefValue(0), Important));
    Exit;
  end;

  Vec := TPixieLengthVector.Create;
  for I := 0 to Tokens.Count - 1 do
  begin
    Tok := Tokens[I];

    // repeat(<integer>, <track-list>) — auto-fill/auto-fit not supported
    if (Tok.TokenType = cssTokenCvFunction) and
       (LowerCase(Tok.Str) = 'repeat') and (Tok.Value <> nil) then
    begin
      Args := Tok.Value;
      CommaIdx := -1;
      for J := 0 to Args.Count - 1 do
        if Args[J].TokenType = cssTokenComma then
        begin
          CommaIdx := J;
          Break;
        end;
      if (CommaIdx <= 0) or (CommaIdx >= Args.Count - 1) or
         (Args[0].TokenType <> cssTokenNumber) or
         (Args[0].Number < 1) then
      begin
        Vec.Free;
        Exit;
      end;
      RepeatCount := Trunc(Args[0].Number);
      BeforeCount := Vec.Count;
      for J := CommaIdx + 1 to Args.Count - 1 do
        if not ParseSingleGridTrack(Args[J], Vec) then
        begin
          Vec.Free;
          Exit;
        end;
      AddedCount := Vec.Count - BeforeCount;
      for K := 1 to RepeatCount - 1 do
        for J := 0 to AddedCount - 1 do
          Vec.Add(Vec[BeforeCount + J]);
      Continue;
    end;

    if not ParseSingleGridTrack(Tok, Vec) then
    begin
      Vec.Free;
      Exit;
    end;
  end;

  if Vec.Count > 0 then
    AddParsedProperty(Name, TPixiePropertyValue.FromLengthVec(Vec, Important))
  else
    Vec.Free;
end;

procedure TPixieStyle.ParseGridLine(Name: Integer;
  Tokens: TPixieCssTokenList; Important: Boolean);
var
  StartName, EndName: Integer;
  SlashIdx, I: Integer;
  StartTokens, EndTokens: TPixieCssTokenList;
begin
  // grid-column: <start> / <end>  or  grid-column: <start>
  if Name = Ord(psid_grid_column) then
  begin
    StartName := Ord(psid_grid_column_start);
    EndName := Ord(psid_grid_column_end);
  end
  else
  begin
    StartName := Ord(psid_grid_row_start);
    EndName := Ord(psid_grid_row_end);
  end;

  // Find '/' delimiter
  SlashIdx := -1;
  for I := 0 to Tokens.Count - 1 do
    if Tokens[I].TokenType = Ord('/') then
    begin
      SlashIdx := I;
      Break;
    end;

  if SlashIdx < 0 then
  begin
    // No slash: single value applies to start; end = auto
    if Tokens.Count >= 1 then
    begin
      StartTokens := TPixieCssTokenList.Create(False);
      try
        for I := 0 to Tokens.Count - 1 do
          StartTokens.Add(Tokens[I]);
        AddProperty(StartName, StartTokens, '', Important);
      finally
        StartTokens.Free;
      end;
      AddParsedProperty(EndName, TPixiePropertyValue.FromLength(
        TPixieCssLength.PredefValue(0), Important));
    end;
  end
  else
  begin
    // Split on slash
    StartTokens := TPixieCssTokenList.Create(False);
    EndTokens := TPixieCssTokenList.Create(False);
    try
      for I := 0 to SlashIdx - 1 do
        StartTokens.Add(Tokens[I]);
      for I := SlashIdx + 1 to Tokens.Count - 1 do
        EndTokens.Add(Tokens[I]);
      if StartTokens.Count > 0 then
        AddProperty(StartName, StartTokens, '', Important);
      if EndTokens.Count > 0 then
        AddProperty(EndName, EndTokens, '', Important);
    finally
      StartTokens.Free;
      EndTokens.Free;
    end;
  end;
end;

procedure FreeShorthandMap;
var
  Pair: TPair<Integer, TPixieIntVector>;
begin
  if ShorthandMap <> nil then
  begin
    for Pair in ShorthandMap do
      Pair.Value.Free;
    FreeAndNil(ShorthandMap);
  end;
end;

initialization
  InitValidValues;
  InitShorthands;

finalization
  FreeAndNil(ValidValues);
  FreeShorthandMap;

end.
