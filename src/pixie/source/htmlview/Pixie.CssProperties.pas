unit Pixie.CssProperties;

// Computed CSS properties for a single element.
//
// This unit defines the data class TPixieCssProperties holding all resolved
// property values that drive layout and rendering.  The Compute() method
// (which requires element and document types) is deferred to Phase 4.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Math,
  Pixie.Types, Pixie.Utils,
  Pixie.CssLength, Pixie.WebColor, Pixie.Borders,
  Pixie.FontDescription, Pixie.Background;

const
  FontSizeTable: array[0..7, 0..6] of TPixiePixel = (
    ( 9,  9,  9,  9, 11, 14, 18),
    ( 9,  9,  9, 10, 12, 15, 20),
    ( 9,  9,  9, 11, 13, 17, 22),
    ( 9,  9, 10, 12, 14, 18, 24),
    ( 9,  9, 10, 13, 16, 20, 26),
    ( 9,  9, 11, 14, 17, 21, 28),
    ( 9, 10, 12, 15, 17, 23, 30),
    ( 9, 10, 13, 16, 18, 24, 32)
  );

type
  { TPixieCssLineHeight }
  TPixieCssLineHeight = record
    CssValue: TPixieCssLength;
    ComputedValue: TPixiePixel;
  end;

  // One parsed CSS transform function. Translate keeps lengths (resolved
  // against the element box at layout/paint); the others carry resolved
  // numbers: scale=(sx,sy), rotate=(deg), skew=(axDeg,ayDeg), matrix=(a..f).
  TPixieTransformFunc = (ptfTranslate, ptfScale, ptfRotate, ptfSkew, ptfMatrix);
  TPixieTransformOp = record
    Func: TPixieTransformFunc;
    LenX, LenY: TPixieCssLength;
    Num: array[0..5] of Single;
  end;
  TPixieTransformOps = array of TPixieTransformOp;

  { TPixieCssProperties }
  TPixieCssProperties = class
  private
    // Enum fields
    FElPosition: TPixieElementPosition;
    FDisplay: TPixieDisplay;
    FVisibility: TPixieVisibility;
    FUserSelect: TPixieUserSelect;
    FTextAlign: TPixieTextAlign;
    FOverflow: TPixieOverflow;
    FOverflowX: TPixieOverflow;
    FWhiteSpace: TPixieWhiteSpace;
    FAppearance: TPixieAppearance;
    FBoxSizing: TPixieBoxSizing;
    FVerticalAlign: TPixieVerticalAlign;
    FFloat: TPixieElementFloat;
    FClear: TPixieElementClear;
    FTextTransform: TPixieTextTransform;
    FOverflowWrap: TPixieOverflowWrap;
    FBorderCollapse: TPixieBorderCollapse;
    FTableLayout: TPixieTableLayout;
    FCaptionSide: TPixieCaptionSide;
    FListStyleType: TPixieListStyleType;
    FListStylePosition: TPixieListStylePosition;
    FFontStyle: TPixieFontStyle;
    FFontVariant: TPixieFontVariant;
    FFlexDirection: TPixieFlexDirection;
    FFlexWrap: TPixieFlexWrap;
    FFlexJustifyContent: TPixieFlexJustifyContent;
    FFlexAlignItems: TPixieFlexAlignItems;
    FFlexAlignSelf: TPixieFlexAlignItems;
    FFlexAlignContent: TPixieFlexAlignContent;
    FJustifyItems: TPixieFlexAlignItems;
    FJustifySelf: TPixieFlexAlignItems;

    // CSS length fields
    FCssWidth: TPixieCssLength;
    FCssHeight: TPixieCssLength;
    FCssMinWidth: TPixieCssLength;
    FCssMinHeight: TPixieCssLength;
    FCssMaxWidth: TPixieCssLength;
    FCssMaxHeight: TPixieCssLength;
    FCssTextIndent: TPixieCssLength;
    FCssBorderSpacingX: TPixieCssLength;
    FCssBorderSpacingY: TPixieCssLength;
    FCssFontSize: TPixieCssLength;
    FCssFontWeight: TPixieCssLength;
    FTextDecorationThickness: TPixieCssLength;
    FZIndex: TPixieCssLength;
    FFlexBasis: TPixieCssLength;
    FRowGap: TPixieCssLength;
    FColumnGap: TPixieCssLength;

    // Grid properties
    FGridTemplateColumns: TPixieLengthVector;
    FGridTemplateRows: TPixieLengthVector;
    FGridColumnStart: TPixieCssLength;
    FGridColumnEnd: TPixieCssLength;
    FGridRowStart: TPixieCssLength;
    FGridRowEnd: TPixieCssLength;

    // Compound records
    FCssMargins: TPixieCssMargins;
    FCssPadding: TPixieCssMargins;
    FCssBorders: TPixieCssBorders;
    FCssOffsets: TPixieCssOffsets;

    // Outline
    FOutlineWidth: TPixiePixel;
    FOutlineStyle: TPixieBorderStyle;
    FOutlineColor: TPixieWebColor;

    // Colour fields
    FColor: TPixieWebColor;
    FTextDecorationColor: TPixieWebColor;
    FTextEmphasisColor: TPixieWebColor;

    // Float/integer fields
    FOpacity: Single;
    FFlexGrow: Single;
    FFlexShrink: Single;
    FAspectRatio: Single;  // 0 = auto/unset; otherwise width / height
    FTextDecorationLine: Integer;
    FOrder: Integer;

    // Text/font fields
    FFont: PtrUInt;
    FFontFamily: string;
    FFontMetrics: TPixieFontMetrics;
    FTextDecorationStyle: TPixieTextDecorationStyle;
    FTextEmphasisStyle: string;
    FTextEmphasisPosition: Integer;

    // Background (owned)
    FBg: TPixieBackground;

    // Misc strings
    FListStyleImage: string;
    FListStyleImageBaseUrl: string;
    FContent: string;
    FCursor: string;

    // CSS transform. FTransform/FTransformOriginStr hold the raw values so
    // transform[-origin]:inherit can copy them from the parent (GetPropertyString
    // reads the parent field at this offset); they are parsed into FTransformOps
    // and the origin lengths.
    FTransform: string;
    FTransformOriginStr: string;
    FTransformOps: TPixieTransformOps;
    FTransformOriginX: TPixieCssLength;
    FTransformOriginY: TPixieCssLength;

    // Line height
    FLineHeight: TPixieCssLineHeight;

    // Temporary pointer to TComputeContext during Compute (nil otherwise)
    FComputeCtxPtr: Pointer;

    // Special accessors
    function GetZIndex: Integer;
    procedure SetZIndex(Value: Integer);
    function GetFontSize: TPixiePixel;
    procedure SetFontSize(Value: TPixiePixel);
    function GetCssLineHeight: TPixieCssLength;
    procedure SetCssLineHeight(const Value: TPixieCssLength);
  public
    constructor Create;
    destructor Destroy; override;

    procedure DumpGetAttrs(List: TStringList);

    // Compute all CSS property values from the element's style.
    // El is TPixieHtmlTag, Doc is TPixieDocument (passed as TObject
    // to avoid circular unit dependency).
    procedure Compute(El: TObject; Doc: TObject);

  private
    procedure ComputeFont(El: TObject; Doc: TObject);
    procedure ComputeBackground(El: TObject; Doc: TObject);
    procedure ComputeFlex(El: TObject; Doc: TObject);
    procedure ComputeGrid(El: TObject; Doc: TObject);
    function GetColorProperty(El: TObject; Name: Integer;
      IsInherited: Boolean; DefaultVal: TPixieWebColor;
      MemberOffset: PtrUInt): TPixieWebColor;
    procedure SnapBorderWidth(var Width: TPixieCssLength; Doc: TObject);
  public

    // Enum properties
    property ElPosition: TPixieElementPosition read FElPosition write FElPosition;
    property Display: TPixieDisplay read FDisplay write FDisplay;
    property Visibility: TPixieVisibility read FVisibility write FVisibility;
    property UserSelect: TPixieUserSelect read FUserSelect write FUserSelect;
    property TextAlign: TPixieTextAlign read FTextAlign write FTextAlign;
    property Overflow: TPixieOverflow read FOverflow write FOverflow;
    property OverflowX: TPixieOverflow read FOverflowX write FOverflowX;
    property WhiteSpace: TPixieWhiteSpace read FWhiteSpace write FWhiteSpace;
    property Appearance: TPixieAppearance read FAppearance write FAppearance;
    property BoxSizing: TPixieBoxSizing read FBoxSizing write FBoxSizing;
    property VerticalAlign: TPixieVerticalAlign read FVerticalAlign write FVerticalAlign;
    property Float_: TPixieElementFloat read FFloat write FFloat;
    property Clear_: TPixieElementClear read FClear write FClear;
    property TextTransform: TPixieTextTransform read FTextTransform write FTextTransform;
    property OverflowWrap: TPixieOverflowWrap read FOverflowWrap write FOverflowWrap;
    property BorderCollapse: TPixieBorderCollapse read FBorderCollapse write FBorderCollapse;
    property TableLayout: TPixieTableLayout read FTableLayout write FTableLayout;
    property CaptionSide: TPixieCaptionSide read FCaptionSide write FCaptionSide;
    property ListStyleType: TPixieListStyleType read FListStyleType write FListStyleType;
    property ListStylePosition: TPixieListStylePosition read FListStylePosition write FListStylePosition;
    property FontStyle_: TPixieFontStyle read FFontStyle write FFontStyle;
    property FontVariant: TPixieFontVariant read FFontVariant write FFontVariant;
    property FlexDirection: TPixieFlexDirection read FFlexDirection write FFlexDirection;
    property FlexWrap: TPixieFlexWrap read FFlexWrap write FFlexWrap;
    property FlexJustifyContent: TPixieFlexJustifyContent read FFlexJustifyContent write FFlexJustifyContent;
    property FlexAlignItems: TPixieFlexAlignItems read FFlexAlignItems write FFlexAlignItems;
    property FlexAlignSelf: TPixieFlexAlignItems read FFlexAlignSelf write FFlexAlignSelf;
    property FlexAlignContent: TPixieFlexAlignContent read FFlexAlignContent write FFlexAlignContent;
    property JustifyItems: TPixieFlexAlignItems read FJustifyItems write FJustifyItems;
    property JustifySelf: TPixieFlexAlignItems read FJustifySelf write FJustifySelf;

    // CSS length properties
    property CssWidth: TPixieCssLength read FCssWidth write FCssWidth;
    property CssHeight: TPixieCssLength read FCssHeight write FCssHeight;
    property CssMinWidth: TPixieCssLength read FCssMinWidth write FCssMinWidth;
    property CssMinHeight: TPixieCssLength read FCssMinHeight write FCssMinHeight;
    property CssMaxWidth: TPixieCssLength read FCssMaxWidth write FCssMaxWidth;
    property CssMaxHeight: TPixieCssLength read FCssMaxHeight write FCssMaxHeight;
    property CssTextIndent: TPixieCssLength read FCssTextIndent write FCssTextIndent;
    property CssBorderSpacingX: TPixieCssLength read FCssBorderSpacingX write FCssBorderSpacingX;
    property CssBorderSpacingY: TPixieCssLength read FCssBorderSpacingY write FCssBorderSpacingY;
    property CssFontSize: TPixieCssLength read FCssFontSize write FCssFontSize;
    property CssFontWeight: TPixieCssLength read FCssFontWeight write FCssFontWeight;
    property TextDecorationThickness: TPixieCssLength read FTextDecorationThickness write FTextDecorationThickness;
    property CssZIndex: TPixieCssLength read FZIndex write FZIndex;
    property FlexBasis: TPixieCssLength read FFlexBasis write FFlexBasis;
    property RowGap: TPixieCssLength read FRowGap write FRowGap;
    property ColumnGap: TPixieCssLength read FColumnGap write FColumnGap;

    // Grid properties
    property GridTemplateColumns: TPixieLengthVector read FGridTemplateColumns;
    property GridTemplateRows: TPixieLengthVector read FGridTemplateRows;
    property GridColumnStart: TPixieCssLength read FGridColumnStart write FGridColumnStart;
    property GridColumnEnd: TPixieCssLength read FGridColumnEnd write FGridColumnEnd;
    property GridRowStart: TPixieCssLength read FGridRowStart write FGridRowStart;
    property GridRowEnd: TPixieCssLength read FGridRowEnd write FGridRowEnd;

    // Compound record properties
    property CssMargins: TPixieCssMargins read FCssMargins write FCssMargins;
    property CssPadding: TPixieCssMargins read FCssPadding write FCssPadding;
    property CssBorders: TPixieCssBorders read FCssBorders write FCssBorders;
    property CssOffsets: TPixieCssOffsets read FCssOffsets write FCssOffsets;

    // Outline
    property OutlineWidth: TPixiePixel read FOutlineWidth;
    property OutlineStyle: TPixieBorderStyle read FOutlineStyle;
    property OutlineColor: TPixieWebColor read FOutlineColor;

    // Colour properties
    property Color: TPixieWebColor read FColor write FColor;
    property TextDecorationColor: TPixieWebColor read FTextDecorationColor write FTextDecorationColor;
    property TextEmphasisColor: TPixieWebColor read FTextEmphasisColor write FTextEmphasisColor;

    // Float/integer properties
    property Opacity: Single read FOpacity write FOpacity;
    property AspectRatio: Single read FAspectRatio write FAspectRatio;
    property FlexGrow: Single read FFlexGrow write FFlexGrow;
    property FlexShrink: Single read FFlexShrink write FFlexShrink;
    property TextDecorationLine: Integer read FTextDecorationLine write FTextDecorationLine;
    property Order: Integer read FOrder write FOrder;

    // Text/font properties
    property Font: PtrUInt read FFont write FFont;
    property FontFamily: string read FFontFamily write FFontFamily;
    property FontMetrics: TPixieFontMetrics read FFontMetrics write FFontMetrics;
    property TextDecorationStyle: TPixieTextDecorationStyle read FTextDecorationStyle write FTextDecorationStyle;
    property TextEmphasisStyle: string read FTextEmphasisStyle write FTextEmphasisStyle;
    property TextEmphasisPosition: Integer read FTextEmphasisPosition write FTextEmphasisPosition;

    // Background (owned, read-only reference)
    property Bg: TPixieBackground read FBg;

    // Misc strings
    property ListStyleImage: string read FListStyleImage write FListStyleImage;
    property ListStyleImageBaseUrl: string read FListStyleImageBaseUrl write FListStyleImageBaseUrl;
    property Content: string read FContent write FContent;
    property Cursor: string read FCursor write FCursor;

    // CSS transform
    property TransformOps: TPixieTransformOps read FTransformOps;
    property TransformOriginX: TPixieCssLength read FTransformOriginX;
    property TransformOriginY: TPixieCssLength read FTransformOriginY;
    function HasTransform: Boolean;

    // Line height
    property LineHeight: TPixieCssLineHeight read FLineHeight write FLineHeight;
    property CssLineHeight: TPixieCssLength read GetCssLineHeight write SetCssLineHeight;
    // Single-line form-control intrinsic height: max(font height,
    // line-height) so inputs/buttons match surrounding line boxes.
    function IntrinsicLineHeight: TPixiePixel;

    // Special converted accessors
    property ZIndex: Integer read GetZIndex write SetZIndex;
    property FontSize: TPixiePixel read GetFontSize write SetFontSize;
  end;

implementation

uses
  Pixie.HtmlTag, Pixie.StringId, Pixie.Gradient,
  Pixie.Element, Pixie.Style, Pixie.Container,
  Pixie.Document;

type
  // Context for CSS unit conversion within Compute
  TComputeContext = record
    Cont: TPixieContainer;
    RootFontSize: TPixiePixel;
    Media: TPixieMediaFeatures;
  end;
  PComputeContext = ^TComputeContext;

  TPixieArgArray = array of string;

// Locale-independent float parse that also accepts a leading decimal point
// (".5", "-.5"), which System.Val rejects. Returns False on failure.
function ParseLenientFloat(const S: string; out V: Single): Boolean;
var
  T: string;
  Code: Integer;
begin
  V := 0;
  T := Trim(S);
  if T = '' then Exit(False);
  if T[1] = '.' then
    T := '0' + T
  else if (Length(T) >= 2) and ((T[1] = '-') or (T[1] = '+')) and (T[2] = '.') then
    Insert('0', T, 2);
  Val(T, V, Code);
  Result := Code = 0;
end;

// Split the numeric prefix and unit suffix of a length token at the first
// non-(digit/sign/dot) character.
procedure SplitNumberUnit(const S: string; out NumStr, UnitStr: string);
var
  T: string;
  I, L: Integer;
begin
  T := Trim(S);
  L := Length(T);
  I := 1;
  if (I <= L) and ((T[I] = '-') or (T[I] = '+')) then Inc(I);
  while (I <= L) and (((T[I] >= '0') and (T[I] <= '9')) or (T[I] = '.')) do
    Inc(I);
  // scientific-notation exponent (1e2, 1.5E-3)
  if (I <= L) and ((T[I] = 'e') or (T[I] = 'E')) then
  begin
    Inc(I);
    if (I <= L) and ((T[I] = '-') or (T[I] = '+')) then Inc(I);
    while (I <= L) and (T[I] >= '0') and (T[I] <= '9') do Inc(I);
  end;
  NumStr := Copy(T, 1, I - 1);
  UnitStr := Trim(LowerCase(Copy(T, I, L - I + 1)));
end;

// Parse a length token ("-50%", "10px", ".5em", "0") into a CSS length.
// A bare number is treated as pixels.
function ParseTransformLen(const S: string): TPixieCssLength;
var
  NumStr, UnitStr: string;
  UIdx: Integer;
  V: Single;
begin
  Result := TPixieCssLength.Create(0, cssUnitsPx);
  SplitNumberUnit(S, NumStr, UnitStr);
  if not ParseLenientFloat(NumStr, V) then Exit;
  if UnitStr = '' then
    Result := TPixieCssLength.Create(V, cssUnitsPx)
  else if UnitStr = '%' then
    Result := TPixieCssLength.Create(V, cssUnitsPercentage)
  else
  begin
    UIdx := PixieValueIndex(UnitStr, CssUnitsStrings);
    if UIdx > 0 then
      Result := TPixieCssLength.Create(V, TPixieCssUnits(UIdx))
    else
      Result := TPixieCssLength.Create(V, cssUnitsPx);
  end;
end;

// Parse a unitless number token (scale factor, matrix component).
function ParseTransformNumber(const S: string): Single;
begin
  if not ParseLenientFloat(Trim(S), Result) then Result := 0;
end;

// Parse an angle token to degrees (deg/rad/turn/grad; bare number = deg).
function ParseTransformAngle(const S: string): Single;
var
  NumStr, UnitStr: string;
  V: Single;
begin
  Result := 0;
  SplitNumberUnit(S, NumStr, UnitStr);
  if not ParseLenientFloat(NumStr, V) then Exit;
  if UnitStr = 'rad' then
    Result := V * 180.0 / Pi
  else if UnitStr = 'turn' then
    Result := V * 360.0
  else if UnitStr = 'grad' then
    Result := V * 0.9
  else
    Result := V;
end;

// Split a function argument list on top-level commas (parens are tracked so
// nested function args such as calc(a, b) are not mis-split).
function SplitTransformArgs(const S: string): TPixieArgArray;
var
  I, Depth, Start, N: Integer;
  Seg: string;
begin
  SetLength(Result, 0);
  if Trim(S) = '' then Exit;
  Depth := 0;
  Start := 1;
  N := 0;
  for I := 1 to Length(S) do
  begin
    if S[I] = '(' then Inc(Depth)
    else if S[I] = ')' then Dec(Depth)
    else if (S[I] = ',') and (Depth = 0) then
    begin
      // Skip empty segments so a stray/trailing comma (e.g. "scale(2,)")
      // doesn't inject a spurious 0 arg that clobbers a defaulted value.
      Seg := Trim(Copy(S, Start, I - Start));
      if Seg <> '' then
      begin
        SetLength(Result, N + 1);
        Result[N] := Seg;
        Inc(N);
      end;
      Start := I + 1;
    end;
  end;
  Seg := Trim(Copy(S, Start, Length(S) - Start + 1));
  if Seg <> '' then
  begin
    SetLength(Result, N + 1);
    Result[N] := Seg;
    Inc(N);
  end;
end;

// Parse a full CSS transform value into an ordered op-list. Functions are
// applied left-to-right (leftmost outermost). Unknown/3D functions are skipped.
function ParseTransformOps(const S: string): TPixieTransformOps;
var
  Lower, FuncName, ArgsStr: string;
  I, L, NameStart, ArgStart, Depth, N: Integer;
  Args: TPixieArgArray;
  Op: TPixieTransformOp;
begin
  SetLength(Result, 0);
  N := 0;
  Lower := LowerCase(S);
  L := Length(Lower);
  I := 1;
  while I <= L do
  begin
    while (I <= L) and ((Lower[I] = ' ') or (Lower[I] = #9) or
      (Lower[I] = ',')) do Inc(I);
    if I > L then Break;
    NameStart := I;
    while (I <= L) and (Lower[I] <> '(') do Inc(I);
    if I > L then Break;
    FuncName := Trim(Copy(Lower, NameStart, I - NameStart));
    Inc(I);
    ArgStart := I;
    Depth := 0;
    while (I <= L) and not ((Lower[I] = ')') and (Depth = 0)) do
    begin
      if Lower[I] = '(' then Inc(Depth)
      else if Lower[I] = ')' then Dec(Depth);
      Inc(I);
    end;
    ArgsStr := Copy(Lower, ArgStart, I - ArgStart);
    if I <= L then Inc(I);
    Args := SplitTransformArgs(ArgsStr);

    FillChar(Op, SizeOf(Op), 0);
    if (FuncName = 'translate') or (FuncName = 'translatex') or
       (FuncName = 'translatey') then
    begin
      Op.Func := ptfTranslate;
      Op.LenX := TPixieCssLength.Create(0, cssUnitsPx);
      Op.LenY := TPixieCssLength.Create(0, cssUnitsPx);
      if FuncName = 'translatey' then
      begin
        if Length(Args) >= 1 then Op.LenY := ParseTransformLen(Args[0]);
      end
      else
      begin
        if Length(Args) >= 1 then Op.LenX := ParseTransformLen(Args[0]);
        if (FuncName = 'translate') and (Length(Args) >= 2) then
          Op.LenY := ParseTransformLen(Args[1]);
      end;
    end
    else if (FuncName = 'scale') or (FuncName = 'scalex') or
            (FuncName = 'scaley') then
    begin
      Op.Func := ptfScale;
      Op.Num[0] := 1; Op.Num[1] := 1;
      if FuncName = 'scalex' then
      begin
        if Length(Args) >= 1 then Op.Num[0] := ParseTransformNumber(Args[0]);
      end
      else if FuncName = 'scaley' then
      begin
        if Length(Args) >= 1 then Op.Num[1] := ParseTransformNumber(Args[0]);
      end
      else
      begin
        if Length(Args) >= 1 then Op.Num[0] := ParseTransformNumber(Args[0]);
        if Length(Args) >= 2 then Op.Num[1] := ParseTransformNumber(Args[1])
        else Op.Num[1] := Op.Num[0];
      end;
    end
    else if FuncName = 'rotate' then
    begin
      Op.Func := ptfRotate;
      if Length(Args) >= 1 then Op.Num[0] := ParseTransformAngle(Args[0]);
    end
    else if (FuncName = 'skew') or (FuncName = 'skewx') or
            (FuncName = 'skewy') then
    begin
      Op.Func := ptfSkew;
      if FuncName = 'skewy' then
      begin
        if Length(Args) >= 1 then Op.Num[1] := ParseTransformAngle(Args[0]);
      end
      else
      begin
        if Length(Args) >= 1 then Op.Num[0] := ParseTransformAngle(Args[0]);
        if (FuncName = 'skew') and (Length(Args) >= 2) then
          Op.Num[1] := ParseTransformAngle(Args[1]);
      end;
    end
    else if FuncName = 'matrix' then
    begin
      if Length(Args) < 6 then Continue;
      Op.Func := ptfMatrix;
      Op.Num[0] := ParseTransformNumber(Args[0]);
      Op.Num[1] := ParseTransformNumber(Args[1]);
      Op.Num[2] := ParseTransformNumber(Args[2]);
      Op.Num[3] := ParseTransformNumber(Args[3]);
      Op.Num[4] := ParseTransformNumber(Args[4]);
      Op.Num[5] := ParseTransformNumber(Args[5]);
    end
    else
      Continue; // unknown / 3D function — skip

    SetLength(Result, N + 1);
    Result[N] := Op;
    Inc(N);
  end;
end;

// Resolve one transform-origin keyword/length component.
function ParseOriginComponent(const S: string): TPixieCssLength;
begin
  if (S = 'left') or (S = 'top') then
    Result := TPixieCssLength.Create(0, cssUnitsPercentage)
  else if (S = 'right') or (S = 'bottom') then
    Result := TPixieCssLength.Create(100, cssUnitsPercentage)
  else if S = 'center' then
    Result := TPixieCssLength.Create(50, cssUnitsPercentage)
  else
    Result := ParseTransformLen(S);
end;

// Parse transform-origin (default 50% 50%). Keyword pairs may appear in either
// order (e.g. "top left"); a single value sets X with Y defaulting to centre.
procedure ParseTransformOrigin(const S: string; out OX, OY: TPixieCssLength);
var
  Lower, P0, P1: string;
  I, Start, N: Integer;
  Parts: TPixieArgArray;
  FirstIsVert: Boolean;
begin
  OX := TPixieCssLength.Create(50, cssUnitsPercentage);
  OY := TPixieCssLength.Create(50, cssUnitsPercentage);
  Lower := Trim(LowerCase(S));
  if Lower = '' then Exit;

  SetLength(Parts, 0);
  N := 0; Start := 0;
  for I := 1 to Length(Lower) do
  begin
    if (Lower[I] = ' ') or (Lower[I] = #9) then
    begin
      if Start > 0 then
      begin
        SetLength(Parts, N + 1);
        Parts[N] := Copy(Lower, Start, I - Start);
        Inc(N); Start := 0;
      end;
    end
    else if Start = 0 then
      Start := I;
  end;
  if Start > 0 then
  begin
    SetLength(Parts, N + 1);
    Parts[N] := Copy(Lower, Start, Length(Lower) - Start + 1);
    Inc(N);
  end;
  if N = 0 then Exit;

  if N = 1 then
  begin
    if (Parts[0] = 'top') or (Parts[0] = 'bottom') then
      OY := ParseOriginComponent(Parts[0])
    else
      OX := ParseOriginComponent(Parts[0]);
    Exit;
  end;

  P0 := Parts[0];
  P1 := Parts[1];
  FirstIsVert := (P0 = 'top') or (P0 = 'bottom') or
    (P1 = 'left') or (P1 = 'right');
  if FirstIsVert then
  begin
    OY := ParseOriginComponent(P0);
    OX := ParseOriginComponent(P1);
  end
  else
  begin
    OX := ParseOriginComponent(P0);
    OY := ParseOriginComponent(P1);
  end;
end;

// Local CSS unit conversion — converts length to pixels using context
function CtxToPixels(const Val: TPixieCssLength;
  const Metrics: TPixieFontMetrics; const Ctx: TComputeContext): TPixiePixel;
begin
  if Val.IsPredefined then
    Exit(0);
  case Val.Units of
    cssUnitsEm:  Result := Val.Val * Metrics.FontSize;
    cssUnitsRem: Result := Val.Val * Ctx.RootFontSize;
    cssUnitsEx:  Result := Val.Val * Metrics.XHeight;
    cssUnitsCh:  Result := Val.Val * Metrics.ChWidth;
    cssUnitsPt:
      if Ctx.Cont <> nil then
        Result := Ctx.Cont.PtToPx(Val.Val)
      else
        Result := Val.Val * 96 / 72;
    cssUnitsIn:
      if Ctx.Cont <> nil then
        Result := Ctx.Cont.PtToPx(Val.Val * 72)
      else
        Result := Val.Val * 96;
    cssUnitsCm:
      if Ctx.Cont <> nil then
        Result := Ctx.Cont.PtToPx(Val.Val * 72 / 2.54)
      else
        Result := Val.Val * 96 / 2.54;
    cssUnitsMm:
      if Ctx.Cont <> nil then
        Result := Ctx.Cont.PtToPx(Val.Val * 72 / 25.4)
      else
        Result := Val.Val * 96 / 25.4;
    cssUnitsPc:
      if Ctx.Cont <> nil then
        Result := Ctx.Cont.PtToPx(Val.Val * 12)
      else
        Result := Val.Val * 96 / 6;
    // Container query units fall through to viewport (no container-type support)
    cssUnitsVw, cssUnitsCqw, cssUnitsCqi:
      Result := Ctx.Media.Width * Val.Val / 100;
    cssUnitsVh, cssUnitsCqh, cssUnitsCqb:
      Result := Ctx.Media.Height * Val.Val / 100;
    cssUnitsVmin, cssUnitsCqmin:
      Result := Min(Ctx.Media.Width, Ctx.Media.Height) * Val.Val / 100;
    cssUnitsVmax, cssUnitsCqmax:
      Result := Max(Ctx.Media.Width, Ctx.Media.Height) * Val.Val / 100;
    cssUnitsPercentage: Result := Val.Val; // stays as percentage
  else
    Result := Val.Val; // cssUnitsPx, cssUnitsNone
  end;
end;

// Local CSS unit conversion — modifies length in-place to px
procedure CtxCvtUnits(var Val: TPixieCssLength;
  const Metrics: TPixieFontMetrics; const Ctx: TComputeContext);
var
  Px: TPixiePixel;
begin
  if Val.IsPredefined then Exit;
  if Val.Units in [cssUnitsPx, cssUnitsPercentage, cssUnitsNone, cssUnitsFr, cssUnitsCalc] then Exit;
  Px := CtxToPixels(Val, Metrics, Ctx);
  Val.SetValue(Px, cssUnitsPx);
end;

// Initialise compute context from element tree
procedure InitComputeContext(Tag: TPixieHtmlTag; out Ctx: TComputeContext);
var
  El: TPixieElement;
begin
  Ctx.Cont := Tag.GetDocContainer;
  Ctx.Media.Init;
  if Ctx.Cont <> nil then
  begin
    Ctx.Cont.GetMediaFeatures(Ctx.Media);
    Ctx.RootFontSize := Ctx.Cont.GetDefaultFontSize;
  end
  else
    Ctx.RootFontSize := 16;

  // Walk to root to get computed root font size (root is computed first)
  El := Tag;
  while El.Parent <> nil do
    El := El.Parent;
  if (El <> Tag) and (El.Css <> nil) and (El.Css.GetFontSize > 0) then
    Ctx.RootFontSize := El.Css.GetFontSize;
end;

// Copy items from a TPixieIntVector (source may be nil)
procedure CopyIntVec(Src, Dest: TPixieIntVector);
var
  I: Integer;
begin
  Dest.Clear;
  if Src <> nil then
    for I := 0 to Src.Count - 1 do
      Dest.Add(Src[I]);
end;

// Copy items from a TPixieLengthVector
procedure CopyLengthVec(Src, Dest: TPixieLengthVector);
var
  I: Integer;
begin
  Dest.Clear;
  if Src <> nil then
    for I := 0 to Src.Count - 1 do
      Dest.Add(Src[I]);
end;

// Copy items from a TPixieSizeVector
procedure CopySizeVec(Src, Dest: TPixieSizeVector);
var
  I: Integer;
begin
  Dest.Clear;
  if Src <> nil then
    for I := 0 to Src.Count - 1 do
      Dest.Add(Src[I]);
end;

{ TPixieCssProperties }

constructor TPixieCssProperties.Create;
begin
  inherited Create;

  // Enum defaults
  FElPosition := epStatic;
  FDisplay := displayInline;
  FVisibility := visVisible;
  FUserSelect := usAuto;
  FTextAlign := taLeft;
  FOverflow := ovVisible;
  FOverflowX := ovVisible;
  FWhiteSpace := wsNormal;
  FAppearance := appNone;
  FBoxSizing := bxContentBox;
  FVerticalAlign := vaBaseline;
  FFloat := efNone;
  FClear := ecNone;
  FTextTransform := ttNone;
  FOverflowWrap := owNormal;
  FBorderCollapse := bcSeparate;
  FCaptionSide := csTop;
  FListStyleType := lstNone;
  FListStylePosition := lspOutside;
  FFontStyle := fstNormal;
  FFontVariant := fvNormal;
  FFlexDirection := fdRow;
  FFlexWrap := fwrNowrap;
  FFlexJustifyContent := fjcFlexStart;
  FFlexAlignItems := faiStretch;
  FFlexAlignSelf := faiAuto;
  FFlexAlignContent := facStretch;
  FJustifyItems := faiNormal;
  FJustifySelf := faiAuto;

  // Grid
  FGridTemplateColumns := nil;
  FGridTemplateRows := nil;

  // CSS length defaults (all zero/default-constructed)
  // Records auto-zero in Pascal, which gives us TPixieCssLength with
  // FValue=0, FPredef=0, FUnits=cssUnitsNone, FIsPredefined=False
  // That matches the default css_length(0) for most fields.

  // Float/integer defaults
  FOpacity := 1;
  FFlexGrow := 0;
  FFlexShrink := 1;
  FAspectRatio := 0;  // 0 = auto/unset
  FTextDecorationLine := TextDecorationLineNone;
  FTextDecorationStyle := tdsSolid;
  FTextEmphasisPosition := TextEmphasisPositionOver;
  FOrder := 0;

  // Font
  FFont := 0;

  // Background (owned)
  FBg := TPixieBackground.Create;
end;

destructor TPixieCssProperties.Destroy;
begin
  FGridTemplateColumns.Free;
  FGridTemplateRows.Free;
  FBg.Free;
  inherited Destroy;
end;

function TPixieCssProperties.HasTransform: Boolean;
begin
  Result := Length(FTransformOps) > 0;
end;

function TPixieCssProperties.GetZIndex: Integer;
var
  V: Single;
begin
  V := FZIndex.Val;
  if V >= MaxInt then
    Result := MaxInt
  else if V <= -MaxInt then
    Result := -MaxInt
  else
    Result := Round(V);
end;

procedure TPixieCssProperties.SetZIndex(Value: Integer);
begin
  FZIndex.SetValue(Value, cssUnitsNone);
end;

function TPixieCssProperties.GetFontSize: TPixiePixel;
begin
  Result := FCssFontSize.Val;
end;

procedure TPixieCssProperties.SetFontSize(Value: TPixiePixel);
begin
  FCssFontSize.SetValue(Value, cssUnitsNone);
end;

function TPixieCssProperties.GetCssLineHeight: TPixieCssLength;
begin
  Result := FLineHeight.CssValue;
end;

function TPixieCssProperties.IntrinsicLineHeight: TPixiePixel;
begin
  Result := FFontMetrics.Height;
  if FLineHeight.ComputedValue > Result then
    Result := FLineHeight.ComputedValue;
end;

procedure TPixieCssProperties.SetCssLineHeight(const Value: TPixieCssLength);
begin
  FLineHeight.CssValue := Value;
end;

procedure TPixieCssProperties.DumpGetAttrs(List: TStringList);
begin
  List.Add('display=' + PixieIndexValue(Ord(FDisplay), StyleDisplayStrings));
  List.Add('el_position=' + PixieIndexValue(Ord(FElPosition), ElementPositionStrings));
  List.Add('text_align=' + PixieIndexValue(Ord(FTextAlign), TextAlignStrings));
  List.Add('font_size=' + FCssFontSize.ToString);
  List.Add('overflow=' + PixieIndexValue(Ord(FOverflow), OverflowStrings));
  List.Add('white_space=' + PixieIndexValue(Ord(FWhiteSpace), WhiteSpaceStrings));
  List.Add('visibility=' + PixieIndexValue(Ord(FVisibility), VisibilityStrings));
  List.Add('user_select=' + PixieIndexValue(Ord(FUserSelect), UserSelectStrings));
  List.Add('appearance=' + PixieIndexValue(Ord(FAppearance), AppearanceStrings));
  List.Add('box_sizing=' + PixieIndexValue(Ord(FBoxSizing), BoxSizingStrings));
  List.Add('z_index=' + FZIndex.ToString);
  List.Add('vertical_align=' + PixieIndexValue(Ord(FVerticalAlign), VerticalAlignStrings));
  List.Add('float=' + PixieIndexValue(Ord(FFloat), ElementFloatStrings));
  List.Add('clear=' + PixieIndexValue(Ord(FClear), ElementClearStrings));
  List.Add('margins=' + FCssMargins.ToString);
  List.Add('padding=' + FCssPadding.ToString);
  List.Add('borders=' + FCssBorders.ToString);
  List.Add('width=' + FCssWidth.ToString);
  List.Add('height=' + FCssHeight.ToString);
  List.Add('min_width=' + FCssMinWidth.ToString);
  List.Add('min_height=' + FCssMinHeight.ToString);
  List.Add('max_width=' + FCssMaxWidth.ToString);
  List.Add('max_height=' + FCssMaxHeight.ToString);
  List.Add('offsets=' + FCssOffsets.ToString);
  List.Add('text_indent=' + FCssTextIndent.ToString);
  List.Add('line_height=' + FloatToStr(FLineHeight.ComputedValue));
  List.Add('list_style_type=' + PixieIndexValue(Ord(FListStyleType), ListStyleTypeStrings));
  List.Add('list_style_position=' + PixieIndexValue(Ord(FListStylePosition), ListStylePositionStrings));
  List.Add('border_spacing_x=' + FCssBorderSpacingX.ToString);
  List.Add('border_spacing_y=' + FCssBorderSpacingY.ToString);
end;

// https://www.w3.org/TR/css-values-4/#snap-a-length-as-a-border-width
procedure TPixieCssProperties.SnapBorderWidth(var Width: TPixieCssLength;
  Doc: TObject);
var
  Ctx: TComputeContext;
  Px: TPixiePixel;
begin
  if Width.IsPredefined or (Width.Units = cssUnitsPercentage) then
    Exit;
  Assert(Doc is TPixieHtmlTag);
  InitComputeContext(TPixieHtmlTag(Doc), Ctx);
  Px := CtxToPixels(Width, FFontMetrics, Ctx);
  if (Px > 0) and (Px < 1) then
    Px := 1
  else
    Px := Floor(Px);
  Width.SetValue(Px, cssUnitsPx);
end;

// Used for all color properties except `color`
// (color:currentcolor is converted to color:inherit during parsing)
function TPixieCssProperties.GetColorProperty(El: TObject; Name: Integer;
  IsInherited: Boolean; DefaultVal: TPixieWebColor;
  MemberOffset: PtrUInt): TPixieWebColor;
begin
  Assert(El is TPixieHtmlTag);
  Result := TPixieHtmlTag(El).GetPropertyColor(Name, IsInherited,
    DefaultVal, MemberOffset);
  if Result.IsCurrentColor then
    Result := FColor;
end;

procedure TPixieCssProperties.ComputeFont(El: TObject; Doc: TObject);
var
  Tag: TPixieHtmlTag;
  Ctx: TComputeContext;
  Sz: TPixieCssLength;
  ParentSz, DocFontSize, KeywordBase, FS: TPixiePixel;
  ElParent: TPixieElement;
  IdxInTable: Integer;
  PropagateDecoration: Boolean;
  Descr: TPixieFontDescription;
  InheritedWeight: Integer;
  Fm: TPixieFontMetrics;
  SelfMono, ParentMono: Boolean;
  CqWidth: TPixiePixel;
  CqEl: TPixieElement;
  FontSizeCalcCtx: TCalcContext;
begin
  Assert(El is TPixieHtmlTag);
  Assert((Doc = nil) or (Doc is TPixieDocument));
  Tag := TPixieHtmlTag(El);
  if FComputeCtxPtr <> nil then
    Ctx := PComputeContext(FComputeCtxPtr)^
  else
    InitComputeContext(Tag, Ctx);

  // Font family (computed first so font-size keyword resolution can
  // apply the monospace quirk)
  if Ctx.Cont <> nil then
    FFontFamily := Tag.GetPropertyString(Ord(psid_font_family), True,
      Ctx.Cont.GetDefaultFontName,
      PtrUInt(@FFontFamily) - PtrUInt(Self))
  else
    FFontFamily := Tag.GetPropertyString(Ord(psid_font_family), True,
      'serif',
      PtrUInt(@FFontFamily) - PtrUInt(Self));

  if Ctx.Cont <> nil then
    DocFontSize := Ctx.Cont.GetDefaultFontSize
  else
    DocFontSize := 16;

  ElParent := Tag.Parent;
  if ElParent <> nil then
    ParentSz := ElParent.Css.GetFontSize
  else
    ParentSz := DocFontSize;

  // CSS Values 4: em in font-size resolves against the parent's
  // font-size, not the element's own (still being computed here).
  // ExHeight/ChWidth = 0 leaves any ex/ch term deferred until the full
  // resolve pass that runs after metrics are known.
  FontSizeCalcCtx.EmSize := ParentSz;
  FontSizeCalcCtx.RemSize := Ctx.RootFontSize;
  FontSizeCalcCtx.ExHeight := 0;
  FontSizeCalcCtx.ChWidth := 0;
  FontSizeCalcCtx.VwPx := Ctx.Media.Width;
  FontSizeCalcCtx.VhPx := Ctx.Media.Height;
  Tag.Style.ResolveCalcForKey(Ord(psid_font_size), FontSizeCalcCtx);

  // Font size
  Sz := Tag.GetPropertyLength(Ord(psid_font_size), True,
    TPixieCssLength.PredefValue(Ord(fsMedium)),
    PtrUInt(@FCssFontSize) - PtrUInt(Self));

  if Sz.IsPredefined then
  begin
    // Chrome quirk: in a monospace font-family context, keyword font sizes
    // resolve against a fixed-font base (13px) instead of the standard 16px.
    // Explicit lengths (e.g. font-size: 16px) are unaffected.
    if PixieFontFamilyIsMonospace(FFontFamily) then
      KeywordBase := 13
    else
      KeywordBase := DocFontSize;
    IdxInTable := Round(KeywordBase - 9);
    if (IdxInTable >= 0) and (IdxInTable <= 7) then
    begin
      if (Sz.Predef >= Ord(fsXXSmall)) and (Sz.Predef <= Ord(fsXXLarge)) then
        FS := FontSizeTable[IdxInTable][Sz.Predef]
      else if Sz.Predef = Ord(fsSmaller) then
        FS := ParentSz / 1.2
      else if Sz.Predef = Ord(fsLarger) then
        FS := ParentSz * 1.2
      else
        FS := ParentSz;
    end
    else
    begin
      case Sz.Predef of
        Ord(fsXXSmall): FS := KeywordBase * 3 / 5;
        Ord(fsXSmall):  FS := KeywordBase * 3 / 4;
        Ord(fsSmall):   FS := KeywordBase * 8 / 9;
        Ord(fsLarge):   FS := KeywordBase * 6 / 5;
        Ord(fsXLarge):  FS := KeywordBase * 3 / 2;
        Ord(fsXXLarge): FS := KeywordBase * 2;
        Ord(fsSmaller): FS := ParentSz / 1.2;
        Ord(fsLarger):  FS := ParentSz * 1.2;
      else
        FS := ParentSz;
      end;
    end;
  end
  else
  begin
    if Sz.Units = cssUnitsPercentage then
      FS := Sz.CalcPercent(ParentSz)
    else if Sz.Units in [cssUnitsCqw, cssUnitsCqi, cssUnitsCqh, cssUnitsCqb,
                          cssUnitsCqmin, cssUnitsCqmax] then
    begin
      // Container query units in font-size: walk up the parent chain to find
      // the nearest ancestor with an explicit width or max-width as the
      // container size. Approximates container-type:inline-size without
      // full container query support.
      CqWidth := 0;
      CqEl := Tag.Parent;
      while CqEl <> nil do
      begin
        if CqEl.Css <> nil then
        begin
          if not CqEl.Css.CssWidth.IsPredefined and
             (CqEl.Css.CssWidth.Units = cssUnitsPx) then
          begin
            CqWidth := CqEl.Css.CssWidth.Val;
            Break;
          end;
          if not CqEl.Css.CssMaxWidth.IsPredefined and
             (CqEl.Css.CssMaxWidth.Units = cssUnitsPx) and
             (CqEl.Css.CssMaxWidth.Val > 0) then
          begin
            CqWidth := CqEl.Css.CssMaxWidth.Val;
            Break;
          end;
        end;
        CqEl := CqEl.Parent;
      end;
      if CqWidth <= 0 then
        CqWidth := Ctx.Media.Width;
      case Sz.Units of
        cssUnitsCqw, cssUnitsCqi:
          FS := CqWidth * Sz.Val / 100;
        cssUnitsCqh, cssUnitsCqb:
          FS := Ctx.Media.Height * Sz.Val / 100;
        cssUnitsCqmin:
          FS := Min(CqWidth, Ctx.Media.Height) * Sz.Val / 100;
        cssUnitsCqmax:
          FS := Max(CqWidth, Ctx.Media.Height) * Sz.Val / 100;
      end;
    end
    else
    begin
      FillChar(Fm, SizeOf(Fm), 0);
      Fm.XHeight := ParentSz;
      Fm.FontSize := ParentSz;
      FS := CtxToPixels(Sz, Fm, Ctx);
    end;
  end;

  // Chrome quirk: when font-family changes from proportional to monospace
  // (or vice versa) and font-size is not explicitly set, the inherited size
  // is scaled by the ratio of default sizes (13/16 or 16/13).  This handles
  // cases like <body style="font-family:monospace"> inheriting 16px from
  // <html> and adjusting it down to 13px.
  if (ElParent <> nil) and not Sz.IsPredefined and
     (Tag.Style.GetProperty(Ord(psid_font_size)).Kind <> pkCssLength) then
  begin
    SelfMono := PixieFontFamilyIsMonospace(FFontFamily);
    ParentMono := PixieFontFamilyIsMonospace(ElParent.Css.FontFamily);
    if SelfMono and not ParentMono then
      FS := FS * 13 / 16
    else if not SelfMono and ParentMono then
      FS := FS * 16 / 13;
  end;

  FCssFontSize.SetValue(FS, cssUnitsNone);

  // Font weight and style
  FCssFontWeight := Tag.GetPropertyLength(Ord(psid_font_weight), True,
    TPixieCssLength.PredefValue(Ord(fwNormal)),
    PtrUInt(@FCssFontWeight) - PtrUInt(Self));

  FFontStyle := TPixieFontStyle(Tag.GetPropertyInt(Ord(psid_font_style), True,
    Ord(fstNormal), PtrUInt(@FFontStyle) - PtrUInt(Self)));

  // Font variant
  FFontVariant := TPixieFontVariant(Tag.GetPropertyInt(Ord(psid_font_variant),
    True, Ord(fvNormal), PtrUInt(@FFontVariant) - PtrUInt(Self)));

  // Text decoration propagation
  PropagateDecoration :=
    not (FDisplay in [displayInlineBlock, displayInlineTable, displayInlineFlex]) and
    (FFloat = efNone) and
    not (FElPosition in [epAbsolute, epFixed]);

  FTextDecorationLine := Tag.GetPropertyInt(Ord(psid_text_decoration_line),
    PropagateDecoration, TextDecorationLineNone,
    PtrUInt(@FTextDecorationLine) - PtrUInt(Self));

  // Merge parent text decoration
  if PropagateDecoration and (Tag.Parent <> nil) then
    FTextDecorationLine := FTextDecorationLine or
      Tag.Parent.Css.TextDecorationLine;

  if FTextDecorationLine <> 0 then
  begin
    FTextDecorationThickness := Tag.GetPropertyLength(
      Ord(psid_text_decoration_thickness), PropagateDecoration,
      TPixieCssLength.PredefValue(Ord(tdtAuto)),
      PtrUInt(@FTextDecorationThickness) - PtrUInt(Self));
    FTextDecorationStyle := TPixieTextDecorationStyle(Tag.GetPropertyInt(
      Ord(psid_text_decoration_style), PropagateDecoration,
      Ord(tdsSolid),
      PtrUInt(@FTextDecorationStyle) - PtrUInt(Self)));
    FTextDecorationColor := GetColorProperty(El,
      Ord(psid_text_decoration_color), PropagateDecoration,
      TPixieWebColor.CurrentColor,
      PtrUInt(@FTextDecorationColor) - PtrUInt(Self));
  end
  else
  begin
    FTextDecorationThickness := TPixieCssLength.PredefValue(Ord(tdtAuto));
    FTextDecorationColor := TPixieWebColor.CurrentColor;
  end;

  // Text emphasis
  FTextEmphasisStyle := Tag.GetPropertyString(
    Ord(psid_text_emphasis_style), True, '',
    PtrUInt(@FTextEmphasisStyle) - PtrUInt(Self));
  FTextEmphasisPosition := Tag.GetPropertyInt(
    Ord(psid_text_emphasis_position), True,
    TextEmphasisPositionOver,
    PtrUInt(@FTextEmphasisPosition) - PtrUInt(Self));
  FTextEmphasisColor := GetColorProperty(El,
    Ord(psid_text_emphasis_color), True,
    TPixieWebColor.CurrentColor,
    PtrUInt(@FTextEmphasisColor) - PtrUInt(Self));

  if Tag.Parent <> nil then
  begin
    if (FTextEmphasisStyle = '') or (FTextEmphasisStyle = 'initial') or
       (FTextEmphasisStyle = 'unset') then
      FTextEmphasisStyle := Tag.Parent.Css.TextEmphasisStyle;
    if FTextEmphasisColor = TPixieWebColor.CurrentColor then
      FTextEmphasisColor := Tag.Parent.Css.TextEmphasisColor;
    FTextEmphasisPosition := FTextEmphasisPosition or
      Tag.Parent.Css.TextEmphasisPosition;
  end;

  // Font weight resolution
  if FCssFontWeight.IsPredefined then
  begin
    case FCssFontWeight.Predef of
      Ord(fwBold):
        FCssFontWeight.SetValue(700, cssUnitsNone);
      Ord(fwBolder):
        begin
          if Tag.Parent <> nil then
            InheritedWeight := Round(Tag.Parent.Css.CssFontWeight.Val)
          else
            InheritedWeight := 400;
          if InheritedWeight < 400 then
            FCssFontWeight.SetValue(400, cssUnitsNone)
          else if InheritedWeight < 600 then
            FCssFontWeight.SetValue(700, cssUnitsNone)
          else
            FCssFontWeight.SetValue(900, cssUnitsNone);
        end;
      Ord(fwLighter):
        begin
          if Tag.Parent <> nil then
            InheritedWeight := Round(Tag.Parent.Css.CssFontWeight.Val)
          else
            InheritedWeight := 400;
          if InheritedWeight < 600 then
            FCssFontWeight.SetValue(100, cssUnitsNone)
          else if InheritedWeight < 800 then
            FCssFontWeight.SetValue(400, cssUnitsNone)
          else
            FCssFontWeight.SetValue(700, cssUnitsNone);
        end;
    else
      FCssFontWeight.SetValue(400, cssUnitsNone);
    end;
  end;

  // Create font via container
  Descr.Init;
  Descr.Family := FFontFamily;
  Descr.Size := Round(FS);
  Descr.Style := FFontStyle;
  Descr.Variant := FFontVariant;
  Descr.Weight := Round(FCssFontWeight.Val);
  Descr.DecorationLine := FTextDecorationLine;
  Descr.DecorationThickness := FTextDecorationThickness;
  Descr.DecorationStyle := FTextDecorationStyle;
  Descr.DecorationColor := FTextDecorationColor;
  Descr.EmphasisStyle := FTextEmphasisStyle;
  Descr.EmphasisColor := FTextEmphasisColor;
  Descr.EmphasisPosition := FTextEmphasisPosition;

  if Doc <> nil then
    FFont := TPixieDocument(Doc).GetFont(Descr, FFontMetrics)
  else
  begin
    FFont := 0;
    FillChar(FFontMetrics, SizeOf(FFontMetrics), 0);
    FFontMetrics.FontSize := FS;
    FFontMetrics.Height := FS;
    FFontMetrics.XHeight := FS * 0.5;
    FFontMetrics.ChWidth := FS * 0.5;
  end;
end;

procedure TPixieCssProperties.ComputeBackground(El: TObject; Doc: TObject);
var
  Tag: TPixieHtmlTag;
  Ctx: TComputeContext;
  Prop: TPixiePropertyValue;
  AutoAuto: TPixieCssSize;
  TmpLen: TPixieCssLength;
  TmpSz: TPixieCssSize;
  I: Integer;
  Img: TPixieImage;
begin
  Assert(El is TPixieHtmlTag);
  Tag := TPixieHtmlTag(El);
  if FComputeCtxPtr <> nil then
    Ctx := PComputeContext(FComputeCtxPtr)^
  else
    InitComputeContext(Tag, Ctx);

  // Background color (FBg is a separate object — byte-offset trick N/A)
  Prop := Tag.Style.GetProperty(Ord(psid_background_color));
  if Prop.Kind = pkColor then
  begin
    FBg.Color := Prop.ColorVal;
    if FBg.Color.IsCurrentColor then
      FBg.Color := FColor;
  end
  else if (Prop.Kind = pkInherit) and (Tag.Parent <> nil) then
    FBg.Color := Tag.Parent.Css.Bg.Color
  else
    FBg.Color := TPixieWebColor.Transparent;

  // Position X
  Prop := Tag.Style.GetProperty(Ord(psid_background_position_x));
  FBg.PositionX.Clear;
  if Prop.Kind = pkLengthVector then
    CopyLengthVec(Prop.LengthVecVal, FBg.PositionX)
  else
    FBg.PositionX.Add(TPixieCssLength.Create(0, cssUnitsPercentage));

  // Position Y
  Prop := Tag.Style.GetProperty(Ord(psid_background_position_y));
  FBg.PositionY.Clear;
  if Prop.Kind = pkLengthVector then
    CopyLengthVec(Prop.LengthVecVal, FBg.PositionY)
  else
    FBg.PositionY.Add(TPixieCssLength.Create(0, cssUnitsPercentage));

  // Size
  Prop := Tag.Style.GetProperty(Ord(psid_background_size));
  FBg.Size.Clear;
  if Prop.Kind = pkSizeVector then
    CopySizeVec(Prop.SizeVecVal, FBg.Size)
  else
  begin
    AutoAuto := TPixieCssSize.Create(
      TPixieCssLength.PredefValue(Ord(bszAuto)),
      TPixieCssLength.PredefValue(Ord(bszAuto)));
    FBg.Size.Add(AutoAuto);
  end;

  // Convert position and size units
  for I := 0 to FBg.PositionX.Count - 1 do
  begin
    TmpLen := FBg.PositionX[I];
    CtxCvtUnits(TmpLen, FFontMetrics, Ctx);
    FBg.PositionX[I] := TmpLen;
  end;
  for I := 0 to FBg.PositionY.Count - 1 do
  begin
    TmpLen := FBg.PositionY[I];
    CtxCvtUnits(TmpLen, FFontMetrics, Ctx);
    FBg.PositionY[I] := TmpLen;
  end;
  for I := 0 to FBg.Size.Count - 1 do
  begin
    TmpSz := FBg.Size[I];
    CtxCvtUnits(TmpSz.Width, FFontMetrics, Ctx);
    CtxCvtUnits(TmpSz.Height, FFontMetrics, Ctx);
    FBg.Size[I] := TmpSz;
  end;

  // Attachment
  Prop := Tag.Style.GetProperty(Ord(psid_background_attachment));
  FBg.Attachment.Clear;
  if Prop.Kind = pkIntVector then
    CopyIntVec(Prop.IntVecVal, FBg.Attachment)
  else
    FBg.Attachment.Add(Ord(baScroll));

  // Repeat
  Prop := Tag.Style.GetProperty(Ord(psid_background_repeat));
  FBg.Repeat_.Clear;
  if Prop.Kind = pkIntVector then
    CopyIntVec(Prop.IntVecVal, FBg.Repeat_)
  else
    FBg.Repeat_.Add(Ord(brRepeat));

  // Clip
  Prop := Tag.Style.GetProperty(Ord(psid_background_clip));
  FBg.Clip.Clear;
  if Prop.Kind = pkIntVector then
    CopyIntVec(Prop.IntVecVal, FBg.Clip)
  else
    FBg.Clip.Add(Ord(bbBorder));

  // Origin
  Prop := Tag.Style.GetProperty(Ord(psid_background_origin));
  FBg.Origin.Clear;
  if Prop.Kind = pkIntVector then
    CopyIntVec(Prop.IntVecVal, FBg.Origin)
  else
    FBg.Origin.Add(Ord(bbPadding));

  // Background images — parse from stored token vector
  FBg.BaseUrl := Tag.GetPropertyString(
    Ord(psid_background_image_baseurl), False, '', 0);

  FBg.Images.Clear;
  Prop := Tag.Style.GetProperty(Ord(psid_background_image));
  if (Prop.Kind = pkTokenVector) and (Prop.TokenVecVal <> nil) then
  begin
    for I := 0 to Prop.TokenVecVal.Count - 1 do
    begin
      Img := PixieParseBgImage(Prop.TokenVecVal[I]);
      if Img <> nil then
        FBg.Images.Add(Img);
    end;
  end;

  // Load any URL-based images via container
  for I := 0 to FBg.Images.Count - 1 do
  begin
    Img := FBg.Images[I];
    if (Img.ImageType = itUrl) and (Img.Url <> '') and (Ctx.Cont <> nil) then
      Ctx.Cont.LoadImage(Img.Url, FBg.BaseUrl, True);
  end;
end;

procedure TPixieCssProperties.ComputeFlex(El: TObject; Doc: TObject);
var
  Tag: TPixieHtmlTag;
  Ctx: TComputeContext;
  Par: TPixieElement;
begin
  Assert(El is TPixieHtmlTag);
  Tag := TPixieHtmlTag(El);
  if FComputeCtxPtr <> nil then
    Ctx := PComputeContext(FComputeCtxPtr)^
  else
    InitComputeContext(Tag, Ctx);

  if FDisplay in [displayFlex, displayInlineFlex] then
  begin
    FFlexDirection := TPixieFlexDirection(Tag.GetPropertyInt(
      Ord(psid_flex_direction), False, Ord(fdRow),
      PtrUInt(@FFlexDirection) - PtrUInt(Self)));
    FFlexWrap := TPixieFlexWrap(Tag.GetPropertyInt(
      Ord(psid_flex_wrap), False, Ord(fwrNowrap),
      PtrUInt(@FFlexWrap) - PtrUInt(Self)));
    FFlexJustifyContent := TPixieFlexJustifyContent(Tag.GetPropertyInt(
      Ord(psid_justify_content), False, Ord(fjcFlexStart),
      PtrUInt(@FFlexJustifyContent) - PtrUInt(Self)));
    FFlexAlignItems := TPixieFlexAlignItems(Tag.GetPropertyInt(
      Ord(psid_align_items), False, Ord(faiNormal),
      PtrUInt(@FFlexAlignItems) - PtrUInt(Self)));
    FFlexAlignContent := TPixieFlexAlignContent(Tag.GetPropertyInt(
      Ord(psid_align_content), False, Ord(facStretch),
      PtrUInt(@FFlexAlignContent) - PtrUInt(Self)));
    FRowGap := Tag.GetPropertyLength(Ord(psid_row_gap), False,
      TPixieCssLength.Create(0, cssUnitsNone),
      PtrUInt(@FRowGap) - PtrUInt(Self));
    FColumnGap := Tag.GetPropertyLength(Ord(psid_column_gap), False,
      TPixieCssLength.Create(0, cssUnitsNone),
      PtrUInt(@FColumnGap) - PtrUInt(Self));
    CtxCvtUnits(FRowGap, FFontMetrics, Ctx);
    CtxCvtUnits(FColumnGap, FFontMetrics, Ctx);
  end;

  FFlexAlignSelf := TPixieFlexAlignItems(Tag.GetPropertyInt(
    Ord(psid_align_self), False, Ord(faiAuto),
    PtrUInt(@FFlexAlignSelf) - PtrUInt(Self)));

  Par := Tag.Parent;
  if (Par <> nil) and
     (Par.Css.Display in [displayFlex, displayInlineFlex]) then
  begin
    FFlexGrow := Tag.GetPropertyFloat(Ord(psid_flex_grow), False, 0,
      PtrUInt(@FFlexGrow) - PtrUInt(Self));
    FFlexShrink := Tag.GetPropertyFloat(Ord(psid_flex_shrink), False, 1,
      PtrUInt(@FFlexShrink) - PtrUInt(Self));
    FFlexBasis := Tag.GetPropertyLength(Ord(psid_flex_basis), False,
      TPixieCssLength.PredefValue(Ord(fbAuto)),
      PtrUInt(@FFlexBasis) - PtrUInt(Self));

    // flex-basis must contain units
    if not FFlexBasis.IsPredefined and
       (FFlexBasis.Units = cssUnitsNone) and (FFlexBasis.Val <> 0) then
      FFlexBasis.SetPredef(Ord(fbAuto));

    CtxCvtUnits(FFlexBasis, FFontMetrics, Ctx);

    // Flex item display normalization
    if FDisplay in [displayInline, displayInlineBlock] then
      FDisplay := displayBlock
    else if FDisplay = displayInlineTable then
      FDisplay := displayTable
    else if FDisplay = displayInlineFlex then
      FDisplay := displayFlex;
  end;
end;

procedure TPixieCssProperties.Compute(El: TObject; Doc: TObject);
var
  Tag: TPixieHtmlTag;
  Ctx: TComputeContext;
  CalcCtx: TCalcContext;
  AutoLen: TPixieCssLength;
  ZeroLen: TPixieCssLength;
  TmpLen: TPixieCssLength;
  FS: TPixiePixel;
begin
  Assert(El is TPixieHtmlTag);
  Tag := TPixieHtmlTag(El);
  InitComputeContext(Tag, Ctx);
  FComputeCtxPtr := @Ctx;

  // Predefined helper lengths
  AutoLen := TPixieCssLength.PredefValue(0);
  ZeroLen := TPixieCssLength.Create(0, cssUnitsNone);

  // 1. Color (inherited)
  FColor := Tag.GetPropertyColor(Ord(psid_color), True,
    TPixieWebColor.Black,
    PtrUInt(@FColor) - PtrUInt(Self));

  // 2. Enum properties
  FElPosition := TPixieElementPosition(Tag.GetPropertyInt(
    Ord(psid_position), False, Ord(epStatic),
    PtrUInt(@FElPosition) - PtrUInt(Self)));
  FDisplay := TPixieDisplay(Tag.GetPropertyInt(
    Ord(psid_display), False, Ord(displayInline),
    PtrUInt(@FDisplay) - PtrUInt(Self)));
  FVisibility := TPixieVisibility(Tag.GetPropertyInt(
    Ord(psid_visibility), True, Ord(visVisible),
    PtrUInt(@FVisibility) - PtrUInt(Self)));
  FUserSelect := TPixieUserSelect(Tag.GetPropertyInt(
    Ord(psid_user_select), True, Ord(usAuto),
    PtrUInt(@FUserSelect) - PtrUInt(Self)));
  FFloat := TPixieElementFloat(Tag.GetPropertyInt(
    Ord(psid_float), False, Ord(efNone),
    PtrUInt(@FFloat) - PtrUInt(Self)));
  FClear := TPixieElementClear(Tag.GetPropertyInt(
    Ord(psid_clear), False, Ord(ecNone),
    PtrUInt(@FClear) - PtrUInt(Self)));
  FAppearance := TPixieAppearance(Tag.GetPropertyInt(
    Ord(psid_appearance), False, Ord(appNone),
    PtrUInt(@FAppearance) - PtrUInt(Self)));
  FBoxSizing := TPixieBoxSizing(Tag.GetPropertyInt(
    Ord(psid_box_sizing), False, Ord(bxContentBox),
    PtrUInt(@FBoxSizing) - PtrUInt(Self)));
  FOverflow := TPixieOverflow(Tag.GetPropertyInt(
    Ord(psid_overflow), False, Ord(ovVisible),
    PtrUInt(@FOverflow) - PtrUInt(Self)));
  // overflow-x defaults to the shorthand value (overflow:auto sets both axes);
  // an explicit overflow-x overrides it for the horizontal axis only.
  FOverflowX := TPixieOverflow(Tag.GetPropertyInt(
    Ord(psid_overflow_x), False, Ord(FOverflow),
    PtrUInt(@FOverflowX) - PtrUInt(Self)));
  FTextAlign := TPixieTextAlign(Tag.GetPropertyInt(
    Ord(psid_text_align), True, Ord(taLeft),
    PtrUInt(@FTextAlign) - PtrUInt(Self)));
  FVerticalAlign := TPixieVerticalAlign(Tag.GetPropertyInt(
    Ord(psid_vertical_align), False, Ord(vaBaseline),
    PtrUInt(@FVerticalAlign) - PtrUInt(Self)));
  FTextTransform := TPixieTextTransform(Tag.GetPropertyInt(
    Ord(psid_text_transform), True, Ord(ttNone),
    PtrUInt(@FTextTransform) - PtrUInt(Self)));
  FWhiteSpace := TPixieWhiteSpace(Tag.GetPropertyInt(
    Ord(psid_white_space), True, Ord(wsNormal),
    PtrUInt(@FWhiteSpace) - PtrUInt(Self)));
  FOverflowWrap := TPixieOverflowWrap(Tag.GetPropertyInt(
    Ord(psid_overflow_wrap), True, Ord(owNormal),
    PtrUInt(@FOverflowWrap) - PtrUInt(Self)));
  FCaptionSide := TPixieCaptionSide(Tag.GetPropertyInt(
    Ord(psid_caption_side), True, Ord(csTop),
    PtrUInt(@FCaptionSide) - PtrUInt(Self)));

  // 3. Display/position/float normalization (CSS 2.2 section 9.7)
  if FDisplay = displayNone then
  begin
    FFloat := efNone;
  end
  else if FElPosition in [epAbsolute, epFixed] then
  begin
    FFloat := efNone;
    if FDisplay = displayInlineTable then
      FDisplay := displayTable
    else if FDisplay in [displayInline, displayTableRowGroup,
      displayTableColumn, displayTableColumnGroup,
      displayTableHeaderGroup, displayTableFooterGroup,
      displayTableRow, displayTableCell, displayTableCaption,
      displayInlineBlock] then
      FDisplay := displayBlock;
  end
  else if FFloat <> efNone then
  begin
    if FDisplay = displayInlineTable then
      FDisplay := displayTable
    else if FDisplay in [displayInline, displayTableRowGroup,
      displayTableColumn, displayTableColumnGroup,
      displayTableHeaderGroup, displayTableFooterGroup,
      displayTableRow, displayTableCell, displayTableCaption,
      displayInlineBlock] then
      FDisplay := displayBlock;
  end
  else if Tag.IsRoot then
  begin
    if FDisplay = displayInlineTable then
      FDisplay := displayTable
    else if FDisplay in [displayInline, displayTableRowGroup,
      displayTableColumn, displayTableColumnGroup,
      displayTableHeaderGroup, displayTableFooterGroup,
      displayTableRow, displayTableCell, displayTableCaption,
      displayInlineBlock, displayListItem] then
      FDisplay := displayBlock;
  end
  else if Tag.IsReplaced and (FDisplay = displayInline) then
    FDisplay := displayInlineBlock;

  // 4. Font computation (font-size, family, weight, text-decoration, emphasis)
  ComputeFont(El, Doc);
  FS := GetFontSize;

  // 4a. Resolve deferred calc() with context-dependent units
  CalcCtx.EmSize := FFontMetrics.FontSize;
  CalcCtx.RemSize := Ctx.RootFontSize;
  CalcCtx.ExHeight := FFontMetrics.XHeight;
  CalcCtx.ChWidth := FFontMetrics.ChWidth;
  CalcCtx.VwPx := Ctx.Media.Width;
  CalcCtx.VhPx := Ctx.Media.Height;
  Tag.Style.ResolveCalc(CalcCtx);

  // 5. Box model dimensions
  FCssWidth := Tag.GetPropertyLength(Ord(psid_width), False, AutoLen,
    PtrUInt(@FCssWidth) - PtrUInt(Self));
  FCssHeight := Tag.GetPropertyLength(Ord(psid_height), False, AutoLen,
    PtrUInt(@FCssHeight) - PtrUInt(Self));
  FCssMinWidth := Tag.GetPropertyLength(Ord(psid_min_width), False, AutoLen,
    PtrUInt(@FCssMinWidth) - PtrUInt(Self));
  FCssMinHeight := Tag.GetPropertyLength(Ord(psid_min_height), False, AutoLen,
    PtrUInt(@FCssMinHeight) - PtrUInt(Self));
  FCssMaxWidth := Tag.GetPropertyLength(Ord(psid_max_width), False, AutoLen,
    PtrUInt(@FCssMaxWidth) - PtrUInt(Self));
  FCssMaxHeight := Tag.GetPropertyLength(Ord(psid_max_height), False, AutoLen,
    PtrUInt(@FCssMaxHeight) - PtrUInt(Self));

  CtxCvtUnits(FCssWidth, FFontMetrics, Ctx);
  CtxCvtUnits(FCssHeight, FFontMetrics, Ctx);
  CtxCvtUnits(FCssMinWidth, FFontMetrics, Ctx);
  CtxCvtUnits(FCssMinHeight, FFontMetrics, Ctx);
  CtxCvtUnits(FCssMaxWidth, FFontMetrics, Ctx);
  CtxCvtUnits(FCssMaxHeight, FFontMetrics, Ctx);

  // 6. Margins
  FCssMargins.Left := Tag.GetPropertyLength(Ord(psid_margin_left), False,
    ZeroLen, PtrUInt(@FCssMargins.Left) - PtrUInt(Self));
  FCssMargins.Right := Tag.GetPropertyLength(Ord(psid_margin_right), False,
    ZeroLen, PtrUInt(@FCssMargins.Right) - PtrUInt(Self));
  FCssMargins.Top := Tag.GetPropertyLength(Ord(psid_margin_top), False,
    ZeroLen, PtrUInt(@FCssMargins.Top) - PtrUInt(Self));
  FCssMargins.Bottom := Tag.GetPropertyLength(Ord(psid_margin_bottom), False,
    ZeroLen, PtrUInt(@FCssMargins.Bottom) - PtrUInt(Self));

  CtxCvtUnits(FCssMargins.Left, FFontMetrics, Ctx);
  CtxCvtUnits(FCssMargins.Right, FFontMetrics, Ctx);
  CtxCvtUnits(FCssMargins.Top, FFontMetrics, Ctx);
  CtxCvtUnits(FCssMargins.Bottom, FFontMetrics, Ctx);

  // 7. Padding
  FCssPadding.Left := Tag.GetPropertyLength(Ord(psid_padding_left), False,
    ZeroLen, PtrUInt(@FCssPadding.Left) - PtrUInt(Self));
  FCssPadding.Right := Tag.GetPropertyLength(Ord(psid_padding_right), False,
    ZeroLen, PtrUInt(@FCssPadding.Right) - PtrUInt(Self));
  FCssPadding.Top := Tag.GetPropertyLength(Ord(psid_padding_top), False,
    ZeroLen, PtrUInt(@FCssPadding.Top) - PtrUInt(Self));
  FCssPadding.Bottom := Tag.GetPropertyLength(Ord(psid_padding_bottom), False,
    ZeroLen, PtrUInt(@FCssPadding.Bottom) - PtrUInt(Self));

  CtxCvtUnits(FCssPadding.Left, FFontMetrics, Ctx);
  CtxCvtUnits(FCssPadding.Right, FFontMetrics, Ctx);
  CtxCvtUnits(FCssPadding.Top, FFontMetrics, Ctx);
  CtxCvtUnits(FCssPadding.Bottom, FFontMetrics, Ctx);

  // 8. Border colors
  FCssBorders.Left.Color := GetColorProperty(El,
    Ord(psid_border_left_color), False, FColor,
    PtrUInt(@FCssBorders.Left.Color) - PtrUInt(Self));
  FCssBorders.Right.Color := GetColorProperty(El,
    Ord(psid_border_right_color), False, FColor,
    PtrUInt(@FCssBorders.Right.Color) - PtrUInt(Self));
  FCssBorders.Top.Color := GetColorProperty(El,
    Ord(psid_border_top_color), False, FColor,
    PtrUInt(@FCssBorders.Top.Color) - PtrUInt(Self));
  FCssBorders.Bottom.Color := GetColorProperty(El,
    Ord(psid_border_bottom_color), False, FColor,
    PtrUInt(@FCssBorders.Bottom.Color) - PtrUInt(Self));

  // 9. Border styles
  FCssBorders.Left.Style := TPixieBorderStyle(Tag.GetPropertyInt(
    Ord(psid_border_left_style), False, Ord(bsNone),
    PtrUInt(@FCssBorders.Left.Style) - PtrUInt(Self)));
  FCssBorders.Right.Style := TPixieBorderStyle(Tag.GetPropertyInt(
    Ord(psid_border_right_style), False, Ord(bsNone),
    PtrUInt(@FCssBorders.Right.Style) - PtrUInt(Self)));
  FCssBorders.Top.Style := TPixieBorderStyle(Tag.GetPropertyInt(
    Ord(psid_border_top_style), False, Ord(bsNone),
    PtrUInt(@FCssBorders.Top.Style) - PtrUInt(Self)));
  FCssBorders.Bottom.Style := TPixieBorderStyle(Tag.GetPropertyInt(
    Ord(psid_border_bottom_style), False, Ord(bsNone),
    PtrUInt(@FCssBorders.Bottom.Style) - PtrUInt(Self)));

  // 10. Border widths
  FCssBorders.Left.Width := Tag.GetPropertyLength(
    Ord(psid_border_left_width), False,
    TPixieCssLength.Create(BorderWidthMediumValue, cssUnitsPx),
    PtrUInt(@FCssBorders.Left.Width) - PtrUInt(Self));
  FCssBorders.Right.Width := Tag.GetPropertyLength(
    Ord(psid_border_right_width), False,
    TPixieCssLength.Create(BorderWidthMediumValue, cssUnitsPx),
    PtrUInt(@FCssBorders.Right.Width) - PtrUInt(Self));
  FCssBorders.Top.Width := Tag.GetPropertyLength(
    Ord(psid_border_top_width), False,
    TPixieCssLength.Create(BorderWidthMediumValue, cssUnitsPx),
    PtrUInt(@FCssBorders.Top.Width) - PtrUInt(Self));
  FCssBorders.Bottom.Width := Tag.GetPropertyLength(
    Ord(psid_border_bottom_width), False,
    TPixieCssLength.Create(BorderWidthMediumValue, cssUnitsPx),
    PtrUInt(@FCssBorders.Bottom.Width) - PtrUInt(Self));

  // Zero border width when style is none/hidden
  if FCssBorders.Left.Style in [bsNone, bsHidden] then
    FCssBorders.Left.Width := ZeroLen;
  if FCssBorders.Right.Style in [bsNone, bsHidden] then
    FCssBorders.Right.Width := ZeroLen;
  if FCssBorders.Top.Style in [bsNone, bsHidden] then
    FCssBorders.Top.Width := ZeroLen;
  if FCssBorders.Bottom.Style in [bsNone, bsHidden] then
    FCssBorders.Bottom.Width := ZeroLen;

  // Snap border widths
  SnapBorderWidth(FCssBorders.Left.Width, El);
  SnapBorderWidth(FCssBorders.Right.Width, El);
  SnapBorderWidth(FCssBorders.Top.Width, El);
  SnapBorderWidth(FCssBorders.Bottom.Width, El);

  // 11. Border radius
  FCssBorders.Radius.TopLeftX := Tag.GetPropertyLength(
    Ord(psid_border_top_left_radius_x), False, ZeroLen,
    PtrUInt(@FCssBorders.Radius.TopLeftX) - PtrUInt(Self));
  FCssBorders.Radius.TopLeftY := Tag.GetPropertyLength(
    Ord(psid_border_top_left_radius_y), False, ZeroLen,
    PtrUInt(@FCssBorders.Radius.TopLeftY) - PtrUInt(Self));
  FCssBorders.Radius.TopRightX := Tag.GetPropertyLength(
    Ord(psid_border_top_right_radius_x), False, ZeroLen,
    PtrUInt(@FCssBorders.Radius.TopRightX) - PtrUInt(Self));
  FCssBorders.Radius.TopRightY := Tag.GetPropertyLength(
    Ord(psid_border_top_right_radius_y), False, ZeroLen,
    PtrUInt(@FCssBorders.Radius.TopRightY) - PtrUInt(Self));
  FCssBorders.Radius.BottomLeftX := Tag.GetPropertyLength(
    Ord(psid_border_bottom_left_radius_x), False, ZeroLen,
    PtrUInt(@FCssBorders.Radius.BottomLeftX) - PtrUInt(Self));
  FCssBorders.Radius.BottomLeftY := Tag.GetPropertyLength(
    Ord(psid_border_bottom_left_radius_y), False, ZeroLen,
    PtrUInt(@FCssBorders.Radius.BottomLeftY) - PtrUInt(Self));
  FCssBorders.Radius.BottomRightX := Tag.GetPropertyLength(
    Ord(psid_border_bottom_right_radius_x), False, ZeroLen,
    PtrUInt(@FCssBorders.Radius.BottomRightX) - PtrUInt(Self));
  FCssBorders.Radius.BottomRightY := Tag.GetPropertyLength(
    Ord(psid_border_bottom_right_radius_y), False, ZeroLen,
    PtrUInt(@FCssBorders.Radius.BottomRightY) - PtrUInt(Self));

  CtxCvtUnits(FCssBorders.Radius.TopLeftX, FFontMetrics, Ctx);
  CtxCvtUnits(FCssBorders.Radius.TopLeftY, FFontMetrics, Ctx);
  CtxCvtUnits(FCssBorders.Radius.TopRightX, FFontMetrics, Ctx);
  CtxCvtUnits(FCssBorders.Radius.TopRightY, FFontMetrics, Ctx);
  CtxCvtUnits(FCssBorders.Radius.BottomLeftX, FFontMetrics, Ctx);
  CtxCvtUnits(FCssBorders.Radius.BottomLeftY, FFontMetrics, Ctx);
  CtxCvtUnits(FCssBorders.Radius.BottomRightX, FFontMetrics, Ctx);
  CtxCvtUnits(FCssBorders.Radius.BottomRightY, FFontMetrics, Ctx);

  // Outline
  FOutlineStyle := TPixieBorderStyle(Tag.GetPropertyInt(
    Ord(psid_outline_style), False, Ord(bsNone),
    PtrUInt(@FOutlineStyle) - PtrUInt(Self)));
  if FOutlineStyle in [bsNone, bsHidden] then
    FOutlineWidth := 0
  else
  begin
    TmpLen := Tag.GetPropertyLength(Ord(psid_outline_width), False,
      TPixieCssLength.Create(BorderWidthMediumValue, cssUnitsPx),
      PtrUInt(@FOutlineWidth) - PtrUInt(Self));
    CtxCvtUnits(TmpLen, FFontMetrics, Ctx);
    FOutlineWidth := TmpLen.Val;
  end;
  FOutlineColor := GetColorProperty(El,
    Ord(psid_outline_color), False, FColor,
    PtrUInt(@FOutlineColor) - PtrUInt(Self));

  // 12. Border collapse and spacing
  FBorderCollapse := TPixieBorderCollapse(Tag.GetPropertyInt(
    Ord(psid_border_collapse), True, Ord(bcSeparate),
    PtrUInt(@FBorderCollapse) - PtrUInt(Self)));

  FTableLayout := TPixieTableLayout(Tag.GetPropertyInt(
    Ord(psid_table_layout), False, Ord(tlAuto),
    PtrUInt(@FTableLayout) - PtrUInt(Self)));

  FCssBorderSpacingX := Tag.GetPropertyLength(
    Ord(psid__pixie_border_spacing_x), True, ZeroLen,
    PtrUInt(@FCssBorderSpacingX) - PtrUInt(Self));
  FCssBorderSpacingY := Tag.GetPropertyLength(
    Ord(psid__pixie_border_spacing_y), True, ZeroLen,
    PtrUInt(@FCssBorderSpacingY) - PtrUInt(Self));

  CtxCvtUnits(FCssBorderSpacingX, FFontMetrics, Ctx);
  CtxCvtUnits(FCssBorderSpacingY, FFontMetrics, Ctx);

  // 13. Offsets (top/right/bottom/left)
  FCssOffsets.Left := Tag.GetPropertyLength(Ord(psid_left), False, AutoLen,
    PtrUInt(@FCssOffsets.Left) - PtrUInt(Self));
  FCssOffsets.Right := Tag.GetPropertyLength(Ord(psid_right), False, AutoLen,
    PtrUInt(@FCssOffsets.Right) - PtrUInt(Self));
  FCssOffsets.Top := Tag.GetPropertyLength(Ord(psid_top), False, AutoLen,
    PtrUInt(@FCssOffsets.Top) - PtrUInt(Self));
  FCssOffsets.Bottom := Tag.GetPropertyLength(Ord(psid_bottom), False, AutoLen,
    PtrUInt(@FCssOffsets.Bottom) - PtrUInt(Self));

  CtxCvtUnits(FCssOffsets.Left, FFontMetrics, Ctx);
  CtxCvtUnits(FCssOffsets.Right, FFontMetrics, Ctx);
  CtxCvtUnits(FCssOffsets.Top, FFontMetrics, Ctx);
  CtxCvtUnits(FCssOffsets.Bottom, FFontMetrics, Ctx);

  // 14. Z-index, content, cursor
  FZIndex := Tag.GetPropertyLength(Ord(psid_z_index), False, AutoLen,
    PtrUInt(@FZIndex) - PtrUInt(Self));
  FContent := Tag.GetPropertyString(Ord(psid_content), False, '',
    PtrUInt(@FContent) - PtrUInt(Self));
  FCursor := Tag.GetPropertyString(Ord(psid_cursor), True, 'auto',
    PtrUInt(@FCursor) - PtrUInt(Self));

  // CSS transform + transform-origin. Stored unresolved; lengths/percentages
  // resolve against the element's own border box when the matrix is built.
  FTransform := Tag.GetPropertyString(Ord(psid_transform), False, '',
    PtrUInt(@FTransform) - PtrUInt(Self));
  FTransformOps := ParseTransformOps(FTransform);
  FTransformOriginStr := Tag.GetPropertyString(Ord(psid_transform_origin),
    False, '', PtrUInt(@FTransformOriginStr) - PtrUInt(Self));
  ParseTransformOrigin(FTransformOriginStr, FTransformOriginX, FTransformOriginY);

  // 15. Text indent
  FCssTextIndent := Tag.GetPropertyLength(Ord(psid_text_indent), True,
    ZeroLen, PtrUInt(@FCssTextIndent) - PtrUInt(Self));
  CtxCvtUnits(FCssTextIndent, FFontMetrics, Ctx);

  // 16. Line height
  FLineHeight.CssValue := Tag.GetPropertyLength(Ord(psid_line_height), True,
    AutoLen, PtrUInt(@FLineHeight.CssValue) - PtrUInt(Self));
  if FLineHeight.CssValue.IsPredefined then
    FLineHeight.ComputedValue := FFontMetrics.Height
  else if FLineHeight.CssValue.Units = cssUnitsNone then
    FLineHeight.ComputedValue := FLineHeight.CssValue.Val * FS
  else if FLineHeight.CssValue.Units = cssUnitsPercentage then
  begin
    FLineHeight.ComputedValue := FLineHeight.CssValue.Val / 100 * FS;
    FLineHeight.CssValue.SetValue(FLineHeight.ComputedValue, cssUnitsPx);
  end
  else
  begin
    FLineHeight.ComputedValue := CtxToPixels(FLineHeight.CssValue,
      FFontMetrics, Ctx);
    FLineHeight.CssValue.SetValue(FLineHeight.ComputedValue, cssUnitsPx);
  end;

  // 17. List style
  FListStyleType := TPixieListStyleType(Tag.GetPropertyInt(
    Ord(psid_list_style_type), True, Ord(lstDisc),
    PtrUInt(@FListStyleType) - PtrUInt(Self)));
  FListStylePosition := TPixieListStylePosition(Tag.GetPropertyInt(
    Ord(psid_list_style_position), True, Ord(lspOutside),
    PtrUInt(@FListStylePosition) - PtrUInt(Self)));
  FListStyleImage := Tag.GetPropertyString(
    Ord(psid_list_style_image), True, '',
    PtrUInt(@FListStyleImage) - PtrUInt(Self));
  if FListStyleImage <> '' then
  begin
    FListStyleImageBaseUrl := Tag.GetPropertyString(
      Ord(psid_list_style_image_baseurl), True, '',
      PtrUInt(@FListStyleImageBaseUrl) - PtrUInt(Self));
    if Ctx.Cont <> nil then
      Ctx.Cont.LoadImage(FListStyleImage, FListStyleImageBaseUrl, True);
  end;

  // 18. Order
  FOrder := Tag.GetPropertyInt(Ord(psid_order), False, 0,
    PtrUInt(@FOrder) - PtrUInt(Self));

  // 18a. Opacity
  FOpacity := Tag.GetPropertyFloat(Ord(psid_opacity), False, 1,
    PtrUInt(@FOpacity) - PtrUInt(Self));

  // 18b. Aspect-ratio (0 = unset/auto)
  FAspectRatio := Tag.GetPropertyFloat(Ord(psid_aspect_ratio), False, 0,
    PtrUInt(@FAspectRatio) - PtrUInt(Self));

  // 19. Background
  ComputeBackground(El, Doc);

  // 20. Flex
  ComputeFlex(El, Doc);

  // 21. Grid
  ComputeGrid(El, Doc);

  FComputeCtxPtr := nil;
end;

procedure TPixieCssProperties.ComputeGrid(El: TObject; Doc: TObject);
var
  Tag: TPixieHtmlTag;
  Ctx: TComputeContext;
  Par: TPixieElement;
  SrcVec: TPixieLengthVector;
  I: Integer;
  L: TPixieCssLength;
begin
  Assert(El is TPixieHtmlTag);
  Tag := TPixieHtmlTag(El);
  if FComputeCtxPtr <> nil then
    Ctx := PComputeContext(FComputeCtxPtr)^
  else
    InitComputeContext(Tag, Ctx);

  // Container properties (only for grid containers)
  if FDisplay in [displayGrid, displayInlineGrid] then
  begin
    // Grid template columns
    SrcVec := Tag.GetPropertyLengthVector(Ord(psid_grid_template_columns),
      False, nil, PtrUInt(@FGridTemplateColumns) - PtrUInt(Self));
    if SrcVec <> nil then
    begin
      FGridTemplateColumns.Free;
      FGridTemplateColumns := TPixieLengthVector.Create;
      for I := 0 to SrcVec.Count - 1 do
      begin
        L := SrcVec[I];
        CtxCvtUnits(L, FFontMetrics, Ctx);
        FGridTemplateColumns.Add(L);
      end;
    end;

    // Grid template rows
    SrcVec := Tag.GetPropertyLengthVector(Ord(psid_grid_template_rows),
      False, nil, PtrUInt(@FGridTemplateRows) - PtrUInt(Self));
    if SrcVec <> nil then
    begin
      FGridTemplateRows.Free;
      FGridTemplateRows := TPixieLengthVector.Create;
      for I := 0 to SrcVec.Count - 1 do
      begin
        L := SrcVec[I];
        CtxCvtUnits(L, FFontMetrics, Ctx);
        FGridTemplateRows.Add(L);
      end;
    end;

    // Justify items
    FJustifyItems := TPixieFlexAlignItems(Tag.GetPropertyInt(
      Ord(psid_justify_items), False, Ord(faiNormal),
      PtrUInt(@FJustifyItems) - PtrUInt(Self)));

    // Reuse flex alignment properties for grid
    FFlexAlignItems := TPixieFlexAlignItems(Tag.GetPropertyInt(
      Ord(psid_align_items), False, Ord(faiNormal),
      PtrUInt(@FFlexAlignItems) - PtrUInt(Self)));
    FFlexAlignContent := TPixieFlexAlignContent(Tag.GetPropertyInt(
      Ord(psid_align_content), False, Ord(facStretch),
      PtrUInt(@FFlexAlignContent) - PtrUInt(Self)));
    FFlexJustifyContent := TPixieFlexJustifyContent(Tag.GetPropertyInt(
      Ord(psid_justify_content), False, Ord(fjcFlexStart),
      PtrUInt(@FFlexJustifyContent) - PtrUInt(Self)));

    // Gap
    FRowGap := Tag.GetPropertyLength(Ord(psid_row_gap), False,
      TPixieCssLength.Create(0, cssUnitsNone),
      PtrUInt(@FRowGap) - PtrUInt(Self));
    FColumnGap := Tag.GetPropertyLength(Ord(psid_column_gap), False,
      TPixieCssLength.Create(0, cssUnitsNone),
      PtrUInt(@FColumnGap) - PtrUInt(Self));
    CtxCvtUnits(FRowGap, FFontMetrics, Ctx);
    CtxCvtUnits(FColumnGap, FFontMetrics, Ctx);
  end;

  // Item properties (only for children of grid containers)
  Par := Tag.Parent;
  if (Par <> nil) and
     (Par.Css.Display in [displayGrid, displayInlineGrid]) then
  begin
    FGridColumnStart := Tag.GetPropertyLength(Ord(psid_grid_column_start), False,
      TPixieCssLength.PredefValue(0),
      PtrUInt(@FGridColumnStart) - PtrUInt(Self));
    FGridColumnEnd := Tag.GetPropertyLength(Ord(psid_grid_column_end), False,
      TPixieCssLength.PredefValue(0),
      PtrUInt(@FGridColumnEnd) - PtrUInt(Self));
    FGridRowStart := Tag.GetPropertyLength(Ord(psid_grid_row_start), False,
      TPixieCssLength.PredefValue(0),
      PtrUInt(@FGridRowStart) - PtrUInt(Self));
    FGridRowEnd := Tag.GetPropertyLength(Ord(psid_grid_row_end), False,
      TPixieCssLength.PredefValue(0),
      PtrUInt(@FGridRowEnd) - PtrUInt(Self));

    FFlexAlignSelf := TPixieFlexAlignItems(Tag.GetPropertyInt(
      Ord(psid_align_self), False, Ord(faiAuto),
      PtrUInt(@FFlexAlignSelf) - PtrUInt(Self)));
    FJustifySelf := TPixieFlexAlignItems(Tag.GetPropertyInt(
      Ord(psid_justify_self), False, Ord(faiAuto),
      PtrUInt(@FJustifySelf) - PtrUInt(Self)));

    // Grid item display normalization (same as flex)
    if FDisplay in [displayInline, displayInlineBlock] then
      FDisplay := displayBlock
    else if FDisplay = displayInlineTable then
      FDisplay := displayTable
    else if FDisplay = displayInlineFlex then
      FDisplay := displayFlex
    else if FDisplay = displayInlineGrid then
      FDisplay := displayGrid;
  end;
end;

end.
