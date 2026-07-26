unit Pixie.Gradient;

// CSS gradient data model and parsing.
//
// Parses linear-gradient, radial-gradient, conic-gradient (and repeating
// variants) from componentized CSS function tokens into TPixieGradient.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Math, Generics.Collections,
  Pixie.Types, Pixie.StringId, Pixie.Utils,
  Pixie.CssLength, Pixie.WebColor, Pixie.GradientLayer,
  Pixie.CssTokenizer, Pixie.CssParser, Pixie.Style;

const
  // Gradient side bitmask
  GradientSideNone    = $00;
  GradientSideLeft    = $01;
  GradientSideRight   = $02;
  GradientSideTop     = $04;
  GradientSideBottom  = $08;
  GradientSideXCenter = $10;
  GradientSideYCenter = $20;
  GradientSideXLength = $40;
  GradientSideYLength = $80;

  RadialExtentStrings = 'closest-corner;closest-side;farthest-corner;farthest-side';
  ColorSpaceStrings =
    'srgb;srgb-linear;display-p3;a98-rgb;prophoto-rgb;rec2020;' +
    'lab;oklab;xyz;xyz-d50;xyz-d65;hsl;hwb;lch;oklch';
  HueInterpolationStrings = 'shorter;longer;increasing;decreasing';

type
  TPixieRadialShape = (rsNone, rsCircle, rsEllipse);

  TPixieRadialExtent = (reNone, reClosestCorner, reClosestSide,
    reFarthestCorner, reFarthestSide);

  TPixieImageType = (itNone, itUrl, itGradient);

  { TPixieGradientColorStop }
  TPixieGradientColorStop = class
  public
    IsColorHint: Boolean;
    Color: TPixieWebColor;
    Length: TPixieCssLength;
    HasLength: Boolean;
    Angle: Single;
    HasAngle: Boolean;

    constructor Create;
    constructor CreateWithColor(const AColor: TPixieWebColor);
    constructor CreateWithColorLength(const AColor: TPixieWebColor;
      const ALength: TPixieCssLength);
    constructor CreateWithColorAngle(const AColor: TPixieWebColor;
      AAngle: Single);
    constructor CreateHintLength(const ALength: TPixieCssLength);
    constructor CreateHintAngle(AAngle: Single);
  end;

  TPixieGradientColorStopList = TObjectList<TPixieGradientColorStop>;

  { TPixieGradient }
  TPixieGradient = class
  public
    GradientType: Integer;  // string_id (psid_linear_gradient etc.)
    Side: UInt32;
    Angle: Single;
    Colors: TPixieGradientColorStopList;
    PositionX: TPixieCssLength;
    PositionY: TPixieCssLength;
    RadialShape: TPixieRadialShape;
    RadialExtent: TPixieRadialExtent;
    RadialRadiusX: TPixieCssLength;
    RadialRadiusY: TPixieCssLength;
    ConicFromAngle: Single;
    ColorSpace: TPixieColorSpace;
    HueInterpolation: TPixieHueInterpolation;

    constructor Create(AType: Integer = 0);
    destructor Destroy; override;

    function IsEmpty: Boolean;
    function IsLinear: Boolean;
    function IsRadial: Boolean;
    function IsConic: Boolean;
  end;

  { TPixieImage }
  TPixieImage = class
  public
    ImageType: TPixieImageType;
    Url: string;
    Gradient: TPixieGradient;

    constructor Create;
    destructor Destroy; override;
    function IsEmpty: Boolean;
    function CloneImage: TPixieImage;
  end;

function PixieParseGradient(Token: TPixieCssToken; out Grad: TPixieGradient): Boolean;
function PixieParseBgImage(Token: TPixieCssToken): TPixieImage;

implementation

{ TPixieGradientColorStop }

constructor TPixieGradientColorStop.Create;
begin
  inherited Create;
  IsColorHint := False;
  HasLength := False;
  HasAngle := False;
  Angle := 0;
end;

constructor TPixieGradientColorStop.CreateWithColor(const AColor: TPixieWebColor);
begin
  Create;
  Color := AColor;
end;

constructor TPixieGradientColorStop.CreateWithColorLength(
  const AColor: TPixieWebColor; const ALength: TPixieCssLength);
begin
  Create;
  Color := AColor;
  Length := ALength;
  HasLength := True;
end;

constructor TPixieGradientColorStop.CreateWithColorAngle(
  const AColor: TPixieWebColor; AAngle: Single);
begin
  Create;
  Color := AColor;
  Angle := AAngle;
  HasAngle := True;
end;

constructor TPixieGradientColorStop.CreateHintLength(
  const ALength: TPixieCssLength);
begin
  Create;
  IsColorHint := True;
  Length := ALength;
  HasLength := True;
end;

constructor TPixieGradientColorStop.CreateHintAngle(AAngle: Single);
begin
  Create;
  IsColorHint := True;
  Angle := AAngle;
  HasAngle := True;
end;

{ TPixieGradient }

constructor TPixieGradient.Create(AType: Integer);
begin
  inherited Create;
  GradientType := AType;
  Side := GradientSideNone;
  Angle := 180;  // to bottom
  Colors := TPixieGradientColorStopList.Create(True);
  PositionX := TPixieCssLength.PredefValue(0);
  PositionY := TPixieCssLength.PredefValue(0);
  RadialShape := rsEllipse;
  RadialExtent := reFarthestCorner;
  RadialRadiusX := TPixieCssLength.PredefValue(0);
  RadialRadiusY := TPixieCssLength.PredefValue(0);
  ConicFromAngle := 0;
  ColorSpace := csOklab;
  HueInterpolation := hiShorter;
end;

destructor TPixieGradient.Destroy;
begin
  Colors.Free;
  inherited;
end;

function TPixieGradient.IsEmpty: Boolean;
begin
  Result := (GradientType = 0) or (Colors.Count = 0);
end;

function TPixieGradient.IsLinear: Boolean;
begin
  Result := (GradientType = Ord(psid_linear_gradient)) or
            (GradientType = Ord(psid_repeating_linear_gradient));
end;

function TPixieGradient.IsRadial: Boolean;
begin
  Result := (GradientType = Ord(psid_radial_gradient)) or
            (GradientType = Ord(psid_repeating_radial_gradient));
end;

function TPixieGradient.IsConic: Boolean;
begin
  Result := (GradientType = Ord(psid_conic_gradient)) or
            (GradientType = Ord(psid_repeating_conic_gradient));
end;

{ TPixieImage }

constructor TPixieImage.Create;
begin
  inherited Create;
  ImageType := itNone;
  Gradient := nil;
end;

destructor TPixieImage.Destroy;
begin
  Gradient.Free;
  inherited;
end;

function TPixieImage.CloneImage: TPixieImage;
var
  I: Integer;
  Src, Dst: TPixieGradientColorStop;
begin
  Result := TPixieImage.Create;
  Result.ImageType := ImageType;
  Result.Url := Url;
  if Gradient <> nil then
  begin
    Result.Gradient := TPixieGradient.Create(Gradient.GradientType);
    Result.Gradient.Side := Gradient.Side;
    Result.Gradient.Angle := Gradient.Angle;
    Result.Gradient.PositionX := Gradient.PositionX;
    Result.Gradient.PositionY := Gradient.PositionY;
    Result.Gradient.RadialShape := Gradient.RadialShape;
    Result.Gradient.RadialExtent := Gradient.RadialExtent;
    Result.Gradient.RadialRadiusX := Gradient.RadialRadiusX;
    Result.Gradient.RadialRadiusY := Gradient.RadialRadiusY;
    Result.Gradient.ConicFromAngle := Gradient.ConicFromAngle;
    Result.Gradient.ColorSpace := Gradient.ColorSpace;
    Result.Gradient.HueInterpolation := Gradient.HueInterpolation;
    for I := 0 to Gradient.Colors.Count - 1 do
    begin
      Src := Gradient.Colors[I];
      Dst := TPixieGradientColorStop.Create;
      Dst.IsColorHint := Src.IsColorHint;
      Dst.Color := Src.Color;
      Dst.Length := Src.Length;
      Dst.HasLength := Src.HasLength;
      Dst.Angle := Src.Angle;
      Dst.HasAngle := Src.HasAngle;
      Result.Gradient.Colors.Add(Dst);
    end;
  end;
end;

function TPixieImage.IsEmpty: Boolean;
begin
  case ImageType of
    itNone: Result := True;
    itUrl: Result := Url = '';
    itGradient:
      if Gradient <> nil then
        Result := Gradient.IsEmpty
      else
        Result := True;
  else
    Result := True;
  end;
end;

function PixieParseBgImage(Token: TPixieCssToken): TPixieImage;
var
  Url: string;
  Grad: TPixieGradient;
begin
  Result := nil;
  if Token = nil then
    Exit;

  if (Token.TokenType = cssTokenIdent) and
     SameText(Token.Str, 'none') then
  begin
    Result := TPixieImage.Create;
    Exit;
  end;

  if PixieParseUrl(Token, Url) then
  begin
    Result := TPixieImage.Create;
    Result.ImageType := itUrl;
    Result.Url := Url;
    Exit;
  end;

  if PixieParseGradient(Token, Grad) then
  begin
    Result := TPixieImage.Create;
    Result.ImageType := itGradient;
    Result.Gradient := Grad;
  end;
end;

{ Internal helpers }

function TokenIdent(T: TPixieCssToken): string;
begin
  if T = nil then
    Result := ''
  else if T.TokenType = cssTokenIdent then
    Result := PixieLowerCase(T.Str)
  else
    Result := '';
end;

function IsGradientType(Id: Integer): Boolean;
begin
  Result := (Id = Ord(psid_linear_gradient)) or
            (Id = Ord(psid_repeating_linear_gradient)) or
            (Id = Ord(psid_radial_gradient)) or
            (Id = Ord(psid_repeating_radial_gradient)) or
            (Id = Ord(psid_conic_gradient)) or
            (Id = Ord(psid_repeating_conic_gradient));
end;

{ Color interpolation parsing }

function ParseColorInterpolation(Tokens: TPixieCssTokenList; var Index: Integer;
  out AColorSpace: TPixieColorSpace; out AHueInterp: TPixieHueInterpolation): Boolean;
var
  Val: Integer;
begin
  Result := False;
  AColorSpace := csOklab;
  AHueInterp := hiShorter;

  // Require 'in' keyword
  if TokenIdent(PixieTokenAt(Tokens, Index)) <> 'in' then
    Exit;

  // Parse color space
  if not PixieParseKeyword(PixieTokenAt(Tokens, Index + 1), Val,
    ColorSpaceStrings, 1) then
    Exit;

  AColorSpace := TPixieColorSpace(Val);
  Inc(Index, 2);
  Result := True;

  // For polar color spaces: optional <hue-method> hue
  if AColorSpace >= csHsl then
  begin
    // Must check for 'hue' keyword BEFORE parsing the interpolation keyword,
    // otherwise hue_interpolation may be assigned when there is no 'hue' keyword
    if (TokenIdent(PixieTokenAt(Tokens, Index + 1)) = 'hue') and
       PixieParseKeyword(PixieTokenAt(Tokens, Index), Val,
         HueInterpolationStrings, 1) then
    begin
      AHueInterp := TPixieHueInterpolation(Val);
      Inc(Index, 2);
    end;
  end;
end;

{ Linear gradient direction parsing }

function ParseLinearDirection(Tokens: TPixieCssTokenList; var Index: Integer;
  out AAngle: Single; out ASide: UInt32): Boolean;
var
  A, B: string;
begin
  Result := False;
  ASide := GradientSideNone;

  // Try <angle>
  if PixieParseAngle(PixieTokenAt(Tokens, Index), AAngle) then
  begin
    Inc(Index);
    Exit(True);
  end;

  // Try 'to <side-or-corner>'
  if TokenIdent(PixieTokenAt(Tokens, Index)) <> 'to' then
    Exit;

  A := TokenIdent(PixieTokenAt(Tokens, Index + 1));
  B := TokenIdent(PixieTokenAt(Tokens, Index + 2));

  if (A = 'left') or (A = 'right') or (A = 'top') or (A = 'bottom') then
  begin
    if (B <> 'left') and (B <> 'right') and (B <> 'top') and (B <> 'bottom') then
    begin
      // Single keyword
      if A = 'top' then
        AAngle := 0
      else if A = 'bottom' then
        AAngle := 180
      else if A = 'left' then
        AAngle := 270
      else if A = 'right' then
        AAngle := 90
      else
        Exit;
      Inc(Index, 2);
      Exit(True);
    end
    else
    begin
      // Two keywords - fix order so horizontal comes first
      if (A = 'top') or (A = 'bottom') then
      begin
        // Swap
        A := TokenIdent(PixieTokenAt(Tokens, Index + 2));
        B := TokenIdent(PixieTokenAt(Tokens, Index + 1));
      end;

      // Validate order: horizontal then vertical
      if not ((A = 'left') or (A = 'right')) then
        Exit;
      if not ((B = 'top') or (B = 'bottom')) then
        Exit;

      if A = 'left' then
        ASide := GradientSideLeft
      else
        ASide := GradientSideRight;

      if B = 'top' then
        ASide := ASide or GradientSideTop
      else
        ASide := ASide or GradientSideBottom;

      Inc(Index, 3);
      Exit(True);
    end;
  end;
end;

function ParseLinearDirectionAndInterpolation(Tokens: TPixieCssTokenList;
  Grad: TPixieGradient): Boolean;
var
  Index: Integer;
  LAngle: Single;
  LSide: UInt32;
  LColorSpace: TPixieColorSpace;
  LHueInterp: TPixieHueInterpolation;
begin
  Result := False;
  LAngle := 180;
  LSide := GradientSideNone;
  LColorSpace := csOklab;
  LHueInterp := hiShorter;

  Index := 0;

  // || combinator: try direction then interpolation, or vice versa
  if ParseLinearDirection(Tokens, Index, LAngle, LSide) then
  begin
    ParseColorInterpolation(Tokens, Index, LColorSpace, LHueInterp);
  end
  else if ParseColorInterpolation(Tokens, Index, LColorSpace, LHueInterp) then
  begin
    ParseLinearDirection(Tokens, Index, LAngle, LSide);
  end
  else
    Exit;

  if Index <> Tokens.Count then
    Exit;

  Grad.Angle := LAngle;
  Grad.Side := LSide;
  Grad.ColorSpace := LColorSpace;
  Grad.HueInterpolation := LHueInterp;
  Result := True;
end;

{ Gradient position parsing }

function ParseGradientPosition(Tokens: TPixieCssTokenList; var Index: Integer;
  Grad: TPixieGradient): Boolean;
var
  X, Y: TPixieCssLength;
begin
  Result := False;
  if not PixieParseBgPosition(Tokens, Index, X, Y, False) then
    Exit;

  Grad.Side := 0;

  // Map X
  if X.IsPredefined then
  begin
    if X.Predef = Ord(bpCenter) then
      Grad.Side := Grad.Side or GradientSideXCenter
    else
      Grad.Side := Grad.Side or UInt32(1 shl X.Predef);
  end
  else
  begin
    Grad.Side := Grad.Side or GradientSideXLength;
    Grad.PositionX := X;
  end;

  // Map Y
  if Y.IsPredefined then
  begin
    if Y.Predef = Ord(bpCenter) then
      Grad.Side := Grad.Side or GradientSideYCenter
    else
      Grad.Side := Grad.Side or UInt32(1 shl Y.Predef);
  end
  else
  begin
    Grad.Side := Grad.Side or GradientSideYLength;
    Grad.PositionY := Y;
  end;

  Result := True;
end;

{ Radial gradient parsing }

function ParseRadialSize(Tokens: TPixieCssTokenList; var Index: Integer;
  Grad: TPixieGradient): Boolean;
var
  Tok0, Tok1: TPixieCssToken;
  Len0, Len1: TPixieCssLength;
  Val: Integer;
begin
  Result := False;
  Tok0 := PixieTokenAt(Tokens, Index);
  Tok1 := PixieTokenAt(Tokens, Index + 1);

  // Try extent keyword
  if PixieParseKeyword(Tok0, Val, RadialExtentStrings, 1) then
  begin
    Grad.RadialExtent := TPixieRadialExtent(Val);
    Inc(Index);
    Exit(True);
  end;

  // Try two length-percentages (ellipse radii)
  if PixieParseCssLength(Tok0, Len0, clfLengthPercentage or clfPositive) and
     PixieParseCssLength(Tok1, Len1, clfLengthPercentage or clfPositive) then
  begin
    Grad.RadialExtent := reNone;
    Grad.RadialRadiusX := Len0;
    Grad.RadialRadiusY := Len1;
    Inc(Index, 2);
    Exit(True);
  end;

  // Try single length (circle radius) - length only, no percentage
  if PixieParseCssLength(Tok0, Len0, clfLength or clfPositive) then
  begin
    Grad.RadialExtent := reNone;
    Grad.RadialRadiusX := Len0;
    Inc(Index);
    Exit(True);
  end;
end;

function ParseRadialShapeSizePositionInterpolation(Tokens: TPixieCssTokenList;
  Grad: TPixieGradient): Boolean;
var
  Index, SaveIndex: Integer;
  Shape: Integer;
  TempGrad: TPixieGradient;
  LColorSpace: TPixieColorSpace;
  LHueInterp: TPixieHueInterpolation;
  GotColorInterp, GotShapeSize: Boolean;

  function TryShape(var Idx: Integer): Boolean;
  begin
    Result := PixieParseKeyword(PixieTokenAt(Tokens, Idx), Shape,
      'circle;ellipse', 1);
    if Result then
      Inc(Idx);
  end;

  function TryShapeOrSize(var Idx: Integer): Boolean;
  var
    Save: Integer;
  begin
    // || combinator for shape and size
    Save := Idx;
    if TryShape(Idx) then
    begin
      ParseRadialSize(Tokens, Idx, TempGrad);
      Exit(True);
    end;
    Idx := Save;
    if ParseRadialSize(Tokens, Idx, TempGrad) then
    begin
      TryShape(Idx);
      Exit(True);
    end;
    Idx := Save;
    Result := False;
  end;

  function TryAtPosition(var Idx: Integer): Boolean;
  var
    Save: Integer;
  begin
    Result := False;
    Save := Idx;
    if TokenIdent(PixieTokenAt(Tokens, Idx)) = 'at' then
    begin
      Inc(Idx);
      if ParseGradientPosition(Tokens, Idx, TempGrad) then
        Exit(True);
      Idx := Save;
    end;
  end;

  function TryShapeSizePosition(var Idx: Integer): Boolean;
  begin
    // [ <shape> || <size> ]? [ at <position> ]?
    TryShapeOrSize(Idx);
    TryAtPosition(Idx);
    Result := True; // always succeeds (both parts optional)
  end;

begin
  Result := False;
  if Tokens.Count = 0 then
    Exit;

  Shape := 0; // radial_shape_none
  LColorSpace := csOklab;
  LHueInterp := hiShorter;

  // TempGrad to accumulate radial_extent, radii, side, position
  TempGrad := TPixieGradient.Create;
  try
    Index := 0;

    // || combinator: color-interpolation vs shape/size/position
    // Try color-interpolation first because shape/size/position always succeeds
    SaveIndex := Index;
    GotColorInterp := ParseColorInterpolation(Tokens, Index, LColorSpace, LHueInterp);
    if GotColorInterp then
    begin
      TryShapeSizePosition(Index);
    end
    else
    begin
      Index := SaveIndex;
      GotShapeSize := TryShapeSizePosition(Index);
      if GotShapeSize then
        ParseColorInterpolation(Tokens, Index, LColorSpace, LHueInterp);
    end;

    if Index <> Tokens.Count then
      Exit;

    // Validate shape/size combos
    // If shape is ellipse but only one radius given -> invalid
    if (Shape = Ord(rsEllipse)) and
       (not TempGrad.RadialRadiusX.IsPredefined) and
       TempGrad.RadialRadiusY.IsPredefined then
      Exit;

    // If shape is circle but two radii given -> invalid
    if (Shape = Ord(rsCircle)) and
       (not TempGrad.RadialRadiusY.IsPredefined) then
      Exit;

    // Infer shape if not specified
    if Shape = 0 then
    begin
      if (not TempGrad.RadialRadiusX.IsPredefined) and
         TempGrad.RadialRadiusY.IsPredefined then
        Shape := Ord(rsCircle)
      else
        Shape := Ord(rsEllipse);
    end;

    // Transfer results
    Grad.RadialShape := TPixieRadialShape(Shape);
    Grad.RadialExtent := TempGrad.RadialExtent;
    Grad.RadialRadiusX := TempGrad.RadialRadiusX;
    Grad.RadialRadiusY := TempGrad.RadialRadiusY;
    Grad.Side := TempGrad.Side;
    Grad.PositionX := TempGrad.PositionX;
    Grad.PositionY := TempGrad.PositionY;
    Grad.ColorSpace := LColorSpace;
    Grad.HueInterpolation := LHueInterp;
    Result := True;
  finally
    TempGrad.Free;
  end;
end;

{ Conic gradient parsing }

function ParseConicAnglePosition(Tokens: TPixieCssTokenList; var Index: Integer;
  Grad: TPixieGradient): Boolean;
var
  I: Integer;
  Ang: Single;
begin
  // Optional 'from <angle>'
  if (TokenIdent(PixieTokenAt(Tokens, Index)) = 'from') and
     PixieParseAngle(PixieTokenAt(Tokens, Index + 1), Ang) then
  begin
    Grad.ConicFromAngle := Ang;
    Inc(Index, 2);
  end;

  // Optional 'at <position>'
  I := Index;
  if TokenIdent(PixieTokenAt(Tokens, I)) = 'at' then
  begin
    Inc(I);
    if ParseGradientPosition(Tokens, I, Grad) then
      Index := I;
  end;

  Result := True; // always succeeds
end;

function ParseConicAnglePositionInterpolation(Tokens: TPixieCssTokenList;
  Grad: TPixieGradient): Boolean;
var
  Index: Integer;
  LColorSpace: TPixieColorSpace;
  LHueInterp: TPixieHueInterpolation;
begin
  Result := False;
  if Tokens.Count = 0 then
    Exit;

  LColorSpace := csOklab;
  LHueInterp := hiShorter;

  Index := 0;
  // Check color-interpolation first because conic angle/position always succeeds
  if ParseColorInterpolation(Tokens, Index, LColorSpace, LHueInterp) then
  begin
    ParseConicAnglePosition(Tokens, Index, Grad);
  end
  else if ParseConicAnglePosition(Tokens, Index, Grad) then
  begin
    ParseColorInterpolation(Tokens, Index, LColorSpace, LHueInterp);
  end
  else
    Exit;

  if Index <> Tokens.Count then
    Exit;

  Grad.ColorSpace := LColorSpace;
  Grad.HueInterpolation := LHueInterp;
  Result := True;
end;

{ Color stop parsing }

function ParseColorStopLength(Tokens: TPixieCssTokenList;
  Colors: TPixieGradientColorStopList): Boolean;
var
  Clr: TPixieWebColor;
  Len1, Len2: TPixieCssLength;
begin
  Result := False;
  if (Tokens.Count = 0) or (Tokens.Count > 3) then
    Exit;

  if not PixieParseCssColor(PixieTokenAt(Tokens, 0), Clr) then
    Exit;

  if Tokens.Count = 1 then
  begin
    Colors.Add(TPixieGradientColorStop.CreateWithColor(Clr));
    Exit(True);
  end;

  if Tokens.Count = 2 then
  begin
    if not PixieParseCssLength(PixieTokenAt(Tokens, 1), Len1,
      clfLengthPercentage) then
      Exit;
    Colors.Add(TPixieGradientColorStop.CreateWithColorLength(Clr, Len1));
    Exit(True);
  end;

  // 3 tokens: <color> <pos1> <pos2>
  if PixieParseCssLength(PixieTokenAt(Tokens, 1), Len1, clfLengthPercentage) and
     PixieParseCssLength(PixieTokenAt(Tokens, 2), Len2, clfLengthPercentage) then
  begin
    Colors.Add(TPixieGradientColorStop.CreateWithColorLength(Clr, Len1));
    Colors.Add(TPixieGradientColorStop.CreateWithColorLength(Clr, Len2));
    Exit(True);
  end;
end;

function ParseColorStopAngle(Tokens: TPixieCssTokenList;
  Colors: TPixieGradientColorStopList): Boolean;
var
  Clr: TPixieWebColor;
  Ang1, Ang2: Single;
begin
  Result := False;
  if (Tokens.Count = 0) or (Tokens.Count > 3) then
    Exit;

  if not PixieParseCssColor(PixieTokenAt(Tokens, 0), Clr) then
    Exit;

  if Tokens.Count = 1 then
  begin
    Colors.Add(TPixieGradientColorStop.CreateWithColor(Clr));
    Exit(True);
  end;

  if Tokens.Count = 2 then
  begin
    if not PixieParseAngle(PixieTokenAt(Tokens, 1), Ang1, True) then
      Exit;
    Colors.Add(TPixieGradientColorStop.CreateWithColorAngle(Clr, Ang1));
    Exit(True);
  end;

  // 3 tokens
  if PixieParseAngle(PixieTokenAt(Tokens, 1), Ang1, True) and
     PixieParseAngle(PixieTokenAt(Tokens, 2), Ang2, True) then
  begin
    Colors.Add(TPixieGradientColorStop.CreateWithColorAngle(Clr, Ang1));
    Colors.Add(TPixieGradientColorStop.CreateWithColorAngle(Clr, Ang2));
    Exit(True);
  end;
end;

function ParseColorHintLength(Tokens: TPixieCssTokenList;
  Colors: TPixieGradientColorStopList): Boolean;
var
  Len: TPixieCssLength;
begin
  Result := False;
  if (Tokens.Count = 1) and
     PixieParseCssLength(PixieTokenAt(Tokens, 0), Len, clfLengthPercentage) then
  begin
    Colors.Add(TPixieGradientColorStop.CreateHintLength(Len));
    Result := True;
  end;
end;

function ParseColorHintAngle(Tokens: TPixieCssTokenList;
  Colors: TPixieGradientColorStopList): Boolean;
var
  Ang: Single;
begin
  Result := False;
  if (Tokens.Count = 1) and
     PixieParseAngle(PixieTokenAt(Tokens, 0), Ang, True) then
  begin
    Colors.Add(TPixieGradientColorStop.CreateHintAngle(Ang));
    Result := True;
  end;
end;

function ParseColorStopListLength(List: TPixieCssTokenListList;
  Grad: TPixieGradient): Boolean;
var
  I: Integer;
begin
  Result := False;
  if List.Count < 2 then
    Exit;

  if not ParseColorStopLength(List[0], Grad.Colors) then
    Exit;

  I := 1;
  while I < List.Count do
  begin
    if ParseColorHintLength(List[I], Grad.Colors) then
    begin
      Inc(I);
      if I >= List.Count then
        Exit; // hint not followed by color stop
    end;
    if not ParseColorStopLength(List[I], Grad.Colors) then
      Exit;
    Inc(I);
  end;

  Result := True;
end;

function ParseColorStopListAngle(List: TPixieCssTokenListList;
  Grad: TPixieGradient): Boolean;
var
  I: Integer;
begin
  Result := False;
  if List.Count < 2 then
    Exit;

  if not ParseColorStopAngle(List[0], Grad.Colors) then
    Exit;

  I := 1;
  while I < List.Count do
  begin
    if ParseColorHintAngle(List[I], Grad.Colors) then
    begin
      Inc(I);
      if I >= List.Count then
        Exit; // hint not followed by color stop
    end;
    if not ParseColorStopAngle(List[I], Grad.Colors) then
      Exit;
    Inc(I);
  end;

  Result := True;
end;

{ Main entry point }

procedure FreeCommaList(List: TPixieCssTokenListList);
var
  I: Integer;
begin
  for I := 0 to List.Count - 1 do
    List[I].Free;
  List.Free;
end;

function PixieParseGradient(Token: TPixieCssToken; out Grad: TPixieGradient): Boolean;
var
  GradType: Integer;
  G: TPixieGradient;
  List: TPixieCssTokenListList;
  Ok: Boolean;
  First: TPixieCssTokenList;
begin
  Result := False;
  Grad := nil;

  if Token = nil then
    Exit;
  if Token.TokenType <> cssTokenCvFunction then
    Exit;

  GradType := Ord(PixieId(PixieLowerCase(Token.Str)));
  if not IsGradientType(GradType) then
    Exit;

  G := TPixieGradient.Create(GradType);
  try
    // Radial and conic position defaults to 'center'
    if not G.IsLinear then
      G.Side := GradientSideXCenter or GradientSideYCenter;

    if Token.Value = nil then
      Exit;

    List := PixieCssParseCommaSeparatedList(Token.Value);
    try
      if List.Count = 0 then
        Exit;

      // Parse first sublist as gradient header
      if G.IsLinear then
        Ok := ParseLinearDirectionAndInterpolation(List[0], G)
      else if G.IsRadial then
        Ok := ParseRadialShapeSizePositionInterpolation(List[0], G)
      else
        Ok := ParseConicAnglePositionInterpolation(List[0], G);

      if Ok then
      begin
        // Remove first sublist (header was consumed)
        First := List[0];
        List.Delete(0);
        First.Free;
      end;

      // Parse color stops
      if G.IsConic then
        Ok := ParseColorStopListAngle(List, G)
      else
        Ok := ParseColorStopListLength(List, G);

      if not Ok then
        Exit;
    finally
      FreeCommaList(List);
    end;

    Grad := G;
    G := nil; // ownership transferred
    Result := True;
  finally
    G.Free; // frees only on failure (G is nil on success)
  end;
end;

end.
