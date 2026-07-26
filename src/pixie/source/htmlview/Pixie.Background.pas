unit Pixie.Background;

// CSS background data model: multi-layer backgrounds, gradient layer computation.
//
// TPixieBackground holds per-layer CSS background properties (images, color,
// positions, sizes, repeat, clip, origin, attachment).
//
// Gradient layer extraction methods compute concrete drawing data
// (endpoints, radii, normalized color stops) for linear, radial and conic
// gradients.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Math, Generics.Collections,
  Pixie.Types, Pixie.StringId,
  Pixie.CssLength, Pixie.WebColor, Pixie.Borders,
  Pixie.GradientLayer, Pixie.Gradient;

type
  TPixieBackgroundLayerType = (
    bltNone,
    bltColor,
    bltImage,
    bltLinearGradient,
    bltRadialGradient,
    bltConicGradient
  );

  { TPixieBackgroundLayer - computed layer with box model info }
  TPixieBackgroundLayer = record
    BorderBox: TPixiePosition;
    BorderRadius: TPixieBorderRadiuses;
    ClipBox: TPixiePosition;
    OriginBox: TPixiePosition;
    Attachment: TPixieBackgroundAttachment;
    Repeat_: TPixieBackgroundRepeat;
    IsRoot: Boolean;
    procedure Init;
  end;

  { TPixieBackgroundImage - layer content: image URL }
  TPixieBackgroundImage = class
  public
    Url: string;
    BaseUrl: string;
  end;

  { TPixieBackgroundColor - layer content: solid colour }
  TPixieBackgroundColor = class
  public
    Color: TPixieWebColor;
  end;

  TPixieImageList = TObjectList<TPixieImage>;

  { TPixieBackground - main background data, holds per-layer CSS properties }
  TPixieBackground = class
  public
    Images: TPixieImageList;
    BaseUrl: string;
    Color: TPixieWebColor;
    Attachment: TPixieIntVector;
    PositionX: TPixieLengthVector;
    PositionY: TPixieLengthVector;
    Size: TPixieSizeVector;
    Repeat_: TPixieIntVector;
    Clip: TPixieIntVector;
    Origin: TPixieIntVector;

    constructor Create;
    destructor Destroy; override;

    function IsEmpty: Boolean;
    function GetLayersNumber: Integer;
    function GetLayerType(Idx: Integer): TPixieBackgroundLayerType;
    function GetImageLayer(Idx: Integer): TPixieBackgroundImage;
    function GetColorLayer(Idx: Integer): TPixieBackgroundColor;
    function GetLinearGradientLayer(Idx: Integer;
      const Layer: TPixieBackgroundLayer;
      const ACurrentColor: TPixieWebColor): TPixieLinearGradientLayer;
    function GetRadialGradientLayer(Idx: Integer;
      const Layer: TPixieBackgroundLayer;
      const ACurrentColor: TPixieWebColor): TPixieRadialGradientLayer;
    function GetConicGradientLayer(Idx: Integer;
      const Layer: TPixieBackgroundLayer;
      const ACurrentColor: TPixieWebColor): TPixieConicGradientLayer;
    function GetLayer(Idx: Integer; Pos: TPixiePosition;
      El: TObject; Ri: TObject; out Layer: TPixieBackgroundLayer;
      FixedBox: PPixiePosition = nil): Boolean;
    procedure DrawLayer(Hdc: PtrUInt; Idx: Integer;
      const Layer: TPixieBackgroundLayer; Container: TObject;
      const ACurrentColor: TPixieWebColor);
  end;

// Static helpers exposed for testing
procedure EndPointsFromAngle(AngleDeg: Single; const BoxSize: TPixieSize;
  out FirstPoint, SecondPoint: TPixiePointF);
function PixieBgDistance(const P1, P2: TPixiePointF): Single;
function PixieBgFindCorner(const Center: TPixiePointF;
  const Box: TPixiePosition; Farthest: Boolean): TPixiePointF;
function PixieBgCalcEllipseRadius(const Offset: TPixiePointF;
  AspectRatio: Single): TPixiePointF;

implementation

uses
  Pixie.Container, Pixie.Element, Pixie.RenderItem, Pixie.Document;

{ TPixieBackgroundLayer }

procedure TPixieBackgroundLayer.Init;
begin
  BorderBox.Clear;
  BorderRadius.Init;
  ClipBox.Clear;
  OriginBox.Clear;
  Attachment := baScroll;
  Repeat_ := brRepeat;
  IsRoot := False;
end;

// Normalize a CSS length into a value between 0 and 1
function NormalizeLength(const Len: TPixieCssLength; LineLen: Single): Single;
begin
  if Len.IsMath then
  begin
    if LineLen <> 0 then
      Result := Len.CalcPercent(LineLen) / LineLen
    else
      Result := 0;
  end
  else if Len.Units = cssUnitsCalc then
  begin
    if LineLen <> 0 then
      Result := Len.CalcPercentCoeff / 100 + Len.Val / LineLen
    else
      Result := 0;
  end
  else if Len.Units = cssUnitsPercentage then
    Result := Len.Val / 100.0
  else if LineLen <> 0 then
    Result := Len.Val / LineLen
  else
    Result := Len.Val;
end;

procedure RepeatColorPoints(ColorPoints: TPixieColorPointList);
var
  OldPoints: array of TPixieColorPoint;
  I, Cnt, Idx: Integer;
  GdSize: Single;
  Pt: TPixieColorPoint;
begin
  Cnt := ColorPoints.Count;
  if Cnt = 0 then
    Exit;

  SetLength(OldPoints, Cnt);
  for I := 0 to Cnt - 1 do
    OldPoints[I] := ColorPoints[I];

  // Extend forward to reach 1.0
  if ColorPoints[ColorPoints.Count - 1].Offset < 1 then
  begin
    GdSize := ColorPoints[ColorPoints.Count - 1].Offset - OldPoints[0].Offset;
    Idx := 0;
    while ColorPoints[ColorPoints.Count - 1].Offset < 1 do
    begin
      Pt := TPixieColorPoint.Create(
        OldPoints[Idx].Offset + GdSize,
        OldPoints[Idx].Color
      );
      ColorPoints.Add(Pt);
      Inc(Idx);
      if Idx >= Cnt then
      begin
        Idx := 0;
        GdSize := ColorPoints[ColorPoints.Count - 1].Offset - OldPoints[0].Offset;
      end;
    end;
  end;

  // Extend backward to reach 0.0
  if ColorPoints[0].Offset > 0 then
  begin
    GdSize := ColorPoints[0].Offset;
    Idx := Cnt - 1;
    while ColorPoints[0].Offset > 0 do
    begin
      Pt := TPixieColorPoint.Create(
        GdSize - (OldPoints[Cnt - 1].Offset - OldPoints[Idx].Offset),
        OldPoints[Idx].Color
      );
      ColorPoints.Insert(0, Pt);
      Dec(Idx);
      if Idx < 0 then
      begin
        Idx := Cnt - 1;
        GdSize := ColorPoints[0].Offset;
      end;
    end;
  end;
end;

function PrepareColorPoints(Layer: TPixieGradientBase; LineLen: Single;
  GradType: Integer; Colors: TPixieGradientColorStopList;
  const ACurrentColor: TPixieWebColor): Boolean;
var
  ColorPoints: TPixieColorPointList;
  Repeating: Boolean;
  NoneUnits: Integer;
  HasTransparent: Boolean;
  I, J, Num: Integer;
  Item: TPixieGradientColorStop;
  Cpt, LastCpt: TPixieColorPoint;
  Sum, StepOffset: Single;
  StopColor: TPixieWebColor;
begin
  ColorPoints := Layer.ColorPoints;

  if GradType = Ord(psid_linear_gradient) then
    Repeating := False
  else if GradType = Ord(psid_radial_gradient) then
    Repeating := False
  else if GradType = Ord(psid_conic_gradient) then
    Repeating := False
  else if GradType = Ord(psid_repeating_linear_gradient) then
    Repeating := True
  else if GradType = Ord(psid_repeating_radial_gradient) then
    Repeating := True
  else if GradType = Ord(psid_repeating_conic_gradient) then
    Repeating := True
  else
    Exit(False);

  NoneUnits := 0;
  HasTransparent := False;

  for I := 0 to Colors.Count - 1 do
  begin
    Item := Colors[I];
    if Item.IsColorHint then
    begin
      if ColorPoints.Count > 0 then
      begin
        LastCpt := ColorPoints[ColorPoints.Count - 1];
        if Item.HasLength then
          LastCpt.Hint := NormalizeLength(Item.Length, LineLen)
        else
          LastCpt.Hint := Item.Angle / 360;
        LastCpt.HasHint := True;
        ColorPoints[ColorPoints.Count - 1] := LastCpt;
      end;
      Continue;
    end;

    // Resolve currentColor to the element's computed color
    if Item.Color.IsCurrentColor then
      StopColor := ACurrentColor
    else
      StopColor := Item.Color;

    if StopColor.Alpha = 0 then
      HasTransparent := True;

    if Item.HasLength then
    begin
      ColorPoints.Add(TPixieColorPoint.Create(
        NormalizeLength(Item.Length, LineLen), StopColor));
    end
    else if Item.HasAngle then
    begin
      ColorPoints.Add(TPixieColorPoint.Create(
        Item.Angle / 360, StopColor));
    end
    else
    begin
      if ColorPoints.Count > 0 then
        Inc(NoneUnits);
      ColorPoints.Add(TPixieColorPoint.Create(0.0, StopColor));
    end;
  end;

  if ColorPoints.Count = 0 then
    Exit(False);

  if not Repeating then
  begin
    // Add color point with offset 0 if not exists
    if ColorPoints[0].Offset <> 0 then
    begin
      ColorPoints.Insert(0, TPixieColorPoint.Create(0.0, ColorPoints[0].Color));
    end;
    // Add color point with offset 1.0 if not exists
    if ColorPoints[ColorPoints.Count - 1].Offset < 1 then
    begin
      if ColorPoints[ColorPoints.Count - 1].Offset = 0 then
      begin
        Cpt := ColorPoints[ColorPoints.Count - 1];
        Cpt.Offset := 1;
        ColorPoints[ColorPoints.Count - 1] := Cpt;
        Dec(NoneUnits);
      end
      else
        ColorPoints.Add(TPixieColorPoint.Create(1.0,
          ColorPoints[ColorPoints.Count - 1].Color));
    end;
  end
  else
  begin
    // Add color point with offset 1.0 if not exists
    if ColorPoints[ColorPoints.Count - 1].Offset = 0 then
    begin
      Cpt := ColorPoints[ColorPoints.Count - 1];
      Cpt.Offset := 1;
      ColorPoints[ColorPoints.Count - 1] := Cpt;
      Dec(NoneUnits);
    end;
  end;

  // Distribute auto-positioned stops
  if NoneUnits > 0 then
  begin
    I := 1;
    while I < ColorPoints.Count do
    begin
      if ColorPoints[I].Offset <> 0 then
      begin
        Inc(I);
        Continue;
      end;
      // Find next defined offset
      J := I + 1;
      while ColorPoints[J].Offset = 0 do
        Inc(J);
      Num := J - I;
      Sum := ColorPoints[I - 1].Offset + ColorPoints[J].Offset;
      StepOffset := Sum / (Num + 1);
      while I < J do
      begin
        Cpt := ColorPoints[I];
        Cpt.Offset := ColorPoints[I - 1].Offset + StepOffset;
        ColorPoints[I] := Cpt;
        Inc(I);
      end;
    end;
  end;

  // Process transparent
  if HasTransparent then
    Layer.ColorPointsTransparentFix;

  if Repeating then
    RepeatColorPoints(ColorPoints);

  Result := True;
end;

{ Static helpers }

procedure EndPointsFromAngle(AngleDeg: Single; const BoxSize: TPixieSize;
  out FirstPoint, SecondPoint: TPixiePointF);
var
  Slope, PerpSlope: Single;
  HalfWidth, HalfHeight: Single;
  EndCorner: TPixiePointF;
  C, EndX, EndY: Single;
begin
  AngleDeg := AngleDeg - Floor(AngleDeg / 360) * 360;
  if AngleDeg < 0 then
    AngleDeg := AngleDeg + 360;

  if AngleDeg = 0 then
  begin
    FirstPoint := TPixiePointF.Create(0, BoxSize.Height);
    SecondPoint := TPixiePointF.Create(0, 0);
    Exit;
  end;

  if AngleDeg = 90 then
  begin
    FirstPoint := TPixiePointF.Create(0, 0);
    SecondPoint := TPixiePointF.Create(BoxSize.Width, 0);
    Exit;
  end;

  if AngleDeg = 180 then
  begin
    FirstPoint := TPixiePointF.Create(0, 0);
    SecondPoint := TPixiePointF.Create(0, BoxSize.Height);
    Exit;
  end;

  if AngleDeg = 270 then
  begin
    FirstPoint := TPixiePointF.Create(BoxSize.Width, 0);
    SecondPoint := TPixiePointF.Create(0, 0);
    Exit;
  end;

  // angleDeg is a "bearing angle" (0deg = N, 90deg = E),
  // but tan expects 0deg = E, 90deg = N.
  Slope := Tan((90.0 - AngleDeg) * Pi / 180.0);
  PerpSlope := -1 / Slope;

  HalfHeight := BoxSize.Height / 2.0;
  HalfWidth := BoxSize.Width / 2.0;

  if AngleDeg < 90 then
    EndCorner := TPixiePointF.Create(HalfWidth, HalfHeight)
  else if AngleDeg < 180 then
    EndCorner := TPixiePointF.Create(HalfWidth, -HalfHeight)
  else if AngleDeg < 270 then
    EndCorner := TPixiePointF.Create(-HalfWidth, -HalfHeight)
  else
    EndCorner := TPixiePointF.Create(-HalfWidth, HalfHeight);

  C := EndCorner.Y - PerpSlope * EndCorner.X;
  EndX := C / (Slope - PerpSlope);
  EndY := PerpSlope * EndX + C;

  SecondPoint := TPixiePointF.Create(HalfWidth + EndX, HalfHeight - EndY);
  FirstPoint := TPixiePointF.Create(HalfWidth - EndX, HalfHeight + EndY);
end;

function PixieBgDistance(const P1, P2: TPixiePointF): Single;
var
  Dx, Dy: Double;
begin
  Dx := P2.X - P1.X;
  Dy := P2.Y - P1.Y;
  Result := Sqrt(Dx * Dx + Dy * Dy);
end;

function PixieBgCalcEllipseRadius(const Offset: TPixiePointF;
  AspectRatio: Single): TPixiePointF;
var
  A: Single;
begin
  if IsNan(AspectRatio) or IsInfinite(AspectRatio) or (AspectRatio = 0) then
  begin
    Result := TPixiePointF.Create(0, 0);
    Exit;
  end;

  // x^2/a^2 + y^2/b^2 = 1
  // a/b = aspectRatio, b = a/aspectRatio
  // a = sqrt(x^2 + y^2 * aspectRatio^2)
  A := Sqrt(Offset.X * Offset.X +
            Offset.Y * Offset.Y *
            AspectRatio * AspectRatio);
  Result := TPixiePointF.Create(A, A / AspectRatio);
end;

function PixieBgFindCorner(const Center: TPixiePointF;
  const Box: TPixiePosition; Farthest: Boolean): TPixiePointF;
var
  Dist, NextDist: Single;
  CornerX, CornerY: Single;
begin
  // Start with left-top corner
  CornerX := Box.X;
  CornerY := Box.Y;
  Dist := PixieBgDistance(Center, TPixiePointF.Create(Box.X, Box.Y));

  // Right-top
  NextDist := PixieBgDistance(Center, TPixiePointF.Create(Box.Right, Box.Y));
  if (Farthest and (NextDist > Dist)) or
     ((not Farthest) and (NextDist < Dist)) then
  begin
    CornerX := Box.Right;
    CornerY := Box.Y;
    Dist := NextDist;
  end;

  // Right-bottom
  NextDist := PixieBgDistance(Center, TPixiePointF.Create(Box.Right, Box.Bottom));
  if (Farthest and (NextDist > Dist)) or
     ((not Farthest) and (NextDist < Dist)) then
  begin
    CornerX := Box.Right;
    CornerY := Box.Bottom;
    Dist := NextDist;
  end;

  // Left-bottom
  NextDist := PixieBgDistance(Center, TPixiePointF.Create(Box.X, Box.Bottom));
  if (Farthest and (NextDist > Dist)) or
     ((not Farthest) and (NextDist < Dist)) then
  begin
    CornerX := Box.X;
    CornerY := Box.Bottom;
  end;

  Result.X := CornerX - Center.X;
  Result.Y := CornerY - Center.Y;
end;

{ TPixieBackground }

constructor TPixieBackground.Create;
begin
  inherited Create;
  Images := TPixieImageList.Create(True);
  Color := TPixieWebColor.Transparent;
  Attachment := TPixieIntVector.Create;
  PositionX := TPixieLengthVector.Create;
  PositionY := TPixieLengthVector.Create;
  Size := TPixieSizeVector.Create;
  Repeat_ := TPixieIntVector.Create;
  Clip := TPixieIntVector.Create;
  Origin := TPixieIntVector.Create;
end;

destructor TPixieBackground.Destroy;
begin
  Origin.Free;
  Clip.Free;
  Repeat_.Free;
  Size.Free;
  PositionY.Free;
  PositionX.Free;
  Attachment.Free;
  Images.Free;
  inherited;
end;

function TPixieBackground.IsEmpty: Boolean;
var
  I: Integer;
begin
  if Color.Alpha <> 0 then
    Exit(False);
  if Images.Count = 0 then
    Exit(True);
  for I := 0 to Images.Count - 1 do
  begin
    if not Images[I].IsEmpty then
      Exit(False);
  end;
  Result := True;
end;

function TPixieBackground.GetLayersNumber: Integer;
begin
  if Color <> TPixieWebColor.Transparent then
    Result := Images.Count + 1
  else
    Result := Images.Count;
end;

function TPixieBackground.GetLayerType(Idx: Integer): TPixieBackgroundLayerType;
begin
  if (Idx >= 0) and (Idx < Images.Count) then
  begin
    case Images[Idx].ImageType of
      itUrl:
        Result := bltImage;
      itGradient:
        begin
          if Images[Idx].Gradient = nil then
            Exit(bltNone);
          if (Images[Idx].Gradient.GradientType = Ord(psid_linear_gradient)) or
             (Images[Idx].Gradient.GradientType = Ord(psid_repeating_linear_gradient)) then
            Result := bltLinearGradient
          else if (Images[Idx].Gradient.GradientType = Ord(psid_radial_gradient)) or
                  (Images[Idx].Gradient.GradientType = Ord(psid_repeating_radial_gradient)) then
            Result := bltRadialGradient
          else if (Images[Idx].Gradient.GradientType = Ord(psid_conic_gradient)) or
                  (Images[Idx].Gradient.GradientType = Ord(psid_repeating_conic_gradient)) then
            Result := bltConicGradient
          else
            Result := bltNone;
        end;
    else
      Result := bltNone;
    end;
  end
  else if Idx = Images.Count then
    Result := bltColor
  else
    Result := bltNone;
end;

function TPixieBackground.GetImageLayer(Idx: Integer): TPixieBackgroundImage;
begin
  Result := nil;
  if (Idx >= 0) and (Idx < Images.Count) then
  begin
    if Images[Idx].ImageType = itUrl then
    begin
      Result := TPixieBackgroundImage.Create;
      Result.Url := Images[Idx].Url;
      Result.BaseUrl := BaseUrl;
    end;
  end;
end;

function TPixieBackground.GetColorLayer(Idx: Integer): TPixieBackgroundColor;
begin
  Result := nil;
  if Idx = Images.Count then
  begin
    Result := TPixieBackgroundColor.Create;
    Result.Color := Color;
  end;
end;

function TPixieBackground.GetLinearGradientLayer(Idx: Integer;
  const Layer: TPixieBackgroundLayer;
  const ACurrentColor: TPixieWebColor): TPixieLinearGradientLayer;
var
  Grad: TPixieGradient;
  Ret: TPixieLinearGradientLayer;
  GradAngle, Rise, Run, LineLen: Single;
begin
  Result := nil;
  if (Idx < 0) or (Idx >= Images.Count) then Exit;
  if Images[Idx].ImageType <> itGradient then Exit;
  Grad := Images[Idx].Gradient;
  if Grad = nil then Exit;
  if not Grad.IsLinear then Exit;

  Ret := TPixieLinearGradientLayer.Create;
  try
    if Grad.Side = 0 then
    begin
      GradAngle := Grad.Angle;
    end
    else
    begin
      Rise := Layer.OriginBox.Width;
      Run := Layer.OriginBox.Height;
      if (Grad.Side and GradientSideLeft) <> 0 then
        Run := -Run;
      if (Grad.Side and GradientSideBottom) <> 0 then
        Rise := -Rise;
      GradAngle := 90 - ArcTan2(Rise, Run) * 180 / Pi;
    end;

    EndPointsFromAngle(GradAngle,
      TPixieSize.Create(Layer.OriginBox.Width, Layer.OriginBox.Height),
      Ret.StartPt, Ret.EndPt);

    Ret.StartPt.X := Ret.StartPt.X + Layer.OriginBox.X;
    Ret.StartPt.Y := Ret.StartPt.Y + Layer.OriginBox.Y;
    Ret.EndPt.X := Ret.EndPt.X + Layer.OriginBox.X;
    Ret.EndPt.Y := Ret.EndPt.Y + Layer.OriginBox.Y;

    LineLen := PixieBgDistance(Ret.StartPt, Ret.EndPt);

    Ret.ColorSpace := Grad.ColorSpace;
    Ret.HueInterpolation := Grad.HueInterpolation;

    if not PrepareColorPoints(Ret, LineLen, Grad.GradientType, Grad.Colors,
      ACurrentColor) then
    begin
      Ret.Free;
      Exit;
    end;

    Result := Ret;
  except
    Ret.Free;
    raise;
  end;
end;

procedure MapGradientPosition(Grad: TPixieGradient;
  const OriginBox: TPixiePosition; out PosX, PosY: Single);
begin
  // X position
  PosX := OriginBox.X + OriginBox.Width / 2.0;
  if (Grad.Side and GradientSideLeft) <> 0 then
    PosX := OriginBox.X
  else if (Grad.Side and GradientSideRight) <> 0 then
    PosX := OriginBox.Right
  else if (Grad.Side and GradientSideXCenter) <> 0 then
    PosX := OriginBox.X + OriginBox.Width / 2.0
  else if (Grad.Side and GradientSideXLength) <> 0 then
    PosX := OriginBox.X + Grad.PositionX.CalcPercent(OriginBox.Width);

  // Y position
  PosY := OriginBox.Y + OriginBox.Height / 2.0;
  if (Grad.Side and GradientSideTop) <> 0 then
    PosY := OriginBox.Y
  else if (Grad.Side and GradientSideBottom) <> 0 then
    PosY := OriginBox.Bottom
  else if (Grad.Side and GradientSideYCenter) <> 0 then
    PosY := OriginBox.Y + OriginBox.Height / 2.0
  else if (Grad.Side and GradientSideYLength) <> 0 then
    PosY := OriginBox.Y + Grad.PositionY.CalcPercent(OriginBox.Height);
end;

function TPixieBackground.GetRadialGradientLayer(Idx: Integer;
  const Layer: TPixieBackgroundLayer;
  const ACurrentColor: TPixieWebColor): TPixieRadialGradientLayer;
var
  Grad: TPixieGradient;
  Ret: TPixieRadialGradientLayer;
  PosX, PosY: Single;
  Corner1, Corner2, Corner3, Corner4: Single;
  AspectRatio: Single;
  Corner, Rad: TPixiePointF;
begin
  Result := nil;
  if (Idx < 0) or (Idx >= Images.Count) then Exit;
  if Images[Idx].ImageType <> itGradient then Exit;
  Grad := Images[Idx].Gradient;
  if Grad = nil then Exit;
  if not Grad.IsRadial then Exit;

  Ret := TPixieRadialGradientLayer.Create;
  try
    MapGradientPosition(Grad, Layer.OriginBox, PosX, PosY);
    Ret.Position := TPixiePointF.Create(PosX, PosY);

    if Grad.RadialExtent <> reNone then
    begin
      case Grad.RadialExtent of
        reClosestCorner:
          begin
            if Grad.RadialShape = rsCircle then
            begin
              Corner1 := PixieBgDistance(Ret.Position,
                TPixiePointF.Create(Layer.OriginBox.X, Layer.OriginBox.Y));
              Corner2 := PixieBgDistance(Ret.Position,
                TPixiePointF.Create(Layer.OriginBox.Right, Layer.OriginBox.Y));
              Corner3 := PixieBgDistance(Ret.Position,
                TPixiePointF.Create(Layer.OriginBox.X, Layer.OriginBox.Bottom));
              Corner4 := PixieBgDistance(Ret.Position,
                TPixiePointF.Create(Layer.OriginBox.Right, Layer.OriginBox.Bottom));
              Ret.Radius.X := Min(Min(Corner1, Corner2), Min(Corner3, Corner4));
              Ret.Radius.Y := Ret.Radius.X;
            end
            else
            begin
              // Aspect ratio same as closest-side
              AspectRatio := Min(
                Abs(Ret.Position.X - Layer.OriginBox.X),
                Abs(Ret.Position.X - Layer.OriginBox.Right)
              ) / Min(
                Abs(Ret.Position.Y - Layer.OriginBox.Y),
                Abs(Ret.Position.Y - Layer.OriginBox.Bottom)
              );
              Corner := PixieBgFindCorner(Ret.Position, Layer.OriginBox, False);
              Rad := PixieBgCalcEllipseRadius(Corner, AspectRatio);
              Ret.Radius.X := Rad.X;
              Ret.Radius.Y := Rad.Y;
            end;
          end;

        reClosestSide:
          begin
            if Grad.RadialShape = rsCircle then
            begin
              Ret.Radius.X := Min(
                Min(Abs(Ret.Position.X - Layer.OriginBox.X),
                    Abs(Ret.Position.X - Layer.OriginBox.Right)),
                Min(Abs(Ret.Position.Y - Layer.OriginBox.Y),
                    Abs(Ret.Position.Y - Layer.OriginBox.Bottom))
              );
              Ret.Radius.Y := Ret.Radius.X;
            end
            else
            begin
              Ret.Radius.X := Min(
                Abs(Ret.Position.X - Layer.OriginBox.X),
                Abs(Ret.Position.X - Layer.OriginBox.Right));
              Ret.Radius.Y := Min(
                Abs(Ret.Position.Y - Layer.OriginBox.Y),
                Abs(Ret.Position.Y - Layer.OriginBox.Bottom));
            end;
          end;

        reFarthestCorner:
          begin
            if Grad.RadialShape = rsCircle then
            begin
              Corner1 := PixieBgDistance(Ret.Position,
                TPixiePointF.Create(Layer.OriginBox.X, Layer.OriginBox.Y));
              Corner2 := PixieBgDistance(Ret.Position,
                TPixiePointF.Create(Layer.OriginBox.Right, Layer.OriginBox.Y));
              Corner3 := PixieBgDistance(Ret.Position,
                TPixiePointF.Create(Layer.OriginBox.X, Layer.OriginBox.Bottom));
              Corner4 := PixieBgDistance(Ret.Position,
                TPixiePointF.Create(Layer.OriginBox.Right, Layer.OriginBox.Bottom));
              Ret.Radius.X := Max(Max(Corner1, Corner2), Max(Corner3, Corner4));
              Ret.Radius.Y := Ret.Radius.X;
            end
            else
            begin
              AspectRatio := Max(
                Abs(Ret.Position.X - Layer.OriginBox.X),
                Abs(Ret.Position.X - Layer.OriginBox.Right)
              ) / Max(
                Abs(Ret.Position.Y - Layer.OriginBox.Y),
                Abs(Ret.Position.Y - Layer.OriginBox.Bottom)
              );
              Corner := PixieBgFindCorner(Ret.Position, Layer.OriginBox, True);
              Rad := PixieBgCalcEllipseRadius(Corner, AspectRatio);
              Ret.Radius.X := Rad.X;
              Ret.Radius.Y := Rad.Y;
            end;
          end;

        reFarthestSide:
          begin
            if Grad.RadialShape = rsCircle then
            begin
              Ret.Radius.X := Max(
                Max(Abs(Ret.Position.X - Layer.OriginBox.X),
                    Abs(Ret.Position.X - Layer.OriginBox.Right)),
                Max(Abs(Ret.Position.Y - Layer.OriginBox.Y),
                    Abs(Ret.Position.Y - Layer.OriginBox.Bottom))
              );
              Ret.Radius.Y := Ret.Radius.X;
            end
            else
            begin
              Ret.Radius.X := Max(
                Abs(Ret.Position.X - Layer.OriginBox.X),
                Abs(Ret.Position.X - Layer.OriginBox.Right));
              Ret.Radius.Y := Max(
                Abs(Ret.Position.Y - Layer.OriginBox.Y),
                Abs(Ret.Position.Y - Layer.OriginBox.Bottom));
            end;
          end;
      end;
    end;

    // Override with explicit radii
    if not Grad.RadialRadiusX.IsPredefined then
      Ret.Radius.X := Grad.RadialRadiusX.CalcPercent(Layer.OriginBox.Width);
    if not Grad.RadialRadiusY.IsPredefined then
      Ret.Radius.Y := Grad.RadialRadiusY.CalcPercent(Layer.OriginBox.Height);

    Ret.ColorSpace := Grad.ColorSpace;
    Ret.HueInterpolation := Grad.HueInterpolation;

    if PrepareColorPoints(Ret, Ret.Radius.X, Grad.GradientType, Grad.Colors,
      ACurrentColor) then
      Result := Ret
    else
      Ret.Free;
  except
    Ret.Free;
    raise;
  end;
end;

function TPixieBackground.GetConicGradientLayer(Idx: Integer;
  const Layer: TPixieBackgroundLayer;
  const ACurrentColor: TPixieWebColor): TPixieConicGradientLayer;
var
  Grad: TPixieGradient;
  Ret: TPixieConicGradientLayer;
  PosX, PosY: Single;
  Corner1, Corner2, Corner3, Corner4: Single;
begin
  Result := nil;
  if (Idx < 0) or (Idx >= Images.Count) then Exit;
  if Images[Idx].ImageType <> itGradient then Exit;
  Grad := Images[Idx].Gradient;
  if Grad = nil then Exit;
  if not Grad.IsConic then Exit;

  Ret := TPixieConicGradientLayer.Create;
  try
    MapGradientPosition(Grad, Layer.OriginBox, PosX, PosY);
    Ret.Position := TPixiePointF.Create(PosX, PosY);
    Ret.Angle := Grad.ConicFromAngle;
    Ret.ColorSpace := Grad.ColorSpace;
    Ret.HueInterpolation := Grad.HueInterpolation;

    Corner1 := PixieBgDistance(Ret.Position,
      TPixiePointF.Create(Layer.OriginBox.X, Layer.OriginBox.Y));
    Corner2 := PixieBgDistance(Ret.Position,
      TPixiePointF.Create(Layer.OriginBox.Right, Layer.OriginBox.Y));
    Corner3 := PixieBgDistance(Ret.Position,
      TPixiePointF.Create(Layer.OriginBox.X, Layer.OriginBox.Bottom));
    Corner4 := PixieBgDistance(Ret.Position,
      TPixiePointF.Create(Layer.OriginBox.Right, Layer.OriginBox.Bottom));
    Ret.Radius := Max(Max(Corner1, Corner2), Max(Corner3, Corner4));

    if PrepareColorPoints(Ret, 0, Grad.GradientType, Grad.Colors,
      ACurrentColor) then
      Result := Ret
    else
      Ret.Free;
  except
    Ret.Free;
    raise;
  end;
end;

function TPixieBackground.GetLayer(Idx: Integer; Pos: TPixiePosition;
  El: TObject; Ri: TObject; out Layer: TPixieBackgroundLayer;
  FixedBox: PPixiePosition = nil): Boolean;
var
  ContentBox, PaddingBox, BorderBox: TPixiePosition;
  ClipVal, OriginVal: Integer;
  BgSize: TPixieSize;
  SizeVal: TPixieCssSize;
  PosXVal, PosYVal: TPixieCssLength;
  ImgLayer: TPixieBackgroundImage;
  ImgSz: TPixieSize;
  ImgArWidth, ImgArHeight: TPixiePixel;
  ImgAspectOnly: Boolean;
  ImgAspectRatio: Single;
  ImgNewSz: TPixieSize;
  NewOriginBox: TPixiePosition;
  AutoAuto: TPixieCssSize;
  RiObj: TPixieRenderItem;
  ElObj: TPixieElement;
begin
  Result := False;
  if (Idx < 0) or (Idx >= GetLayersNumber) then
    Exit;

  Layer.Init;
  Assert(TObject(Ri) is TPixieRenderItem);
  Assert(El is TPixieElement);
  RiObj := TPixieRenderItem(Ri);
  ElObj := TPixieElement(El);

  ContentBox := Pos;
  PaddingBox := Pos;
  PaddingBox.AddMargins(RiObj.GetPaddings);
  BorderBox := PaddingBox;
  BorderBox.AddMargins(RiObj.GetBorders);

  Layer.BorderRadius := ElObj.Css.CssBorders.Radius.CalcPercents(
    BorderBox.Width, BorderBox.Height);
  Layer.BorderBox := BorderBox;
  Layer.IsRoot := ElObj.IsRoot;

  if Idx = Images.Count then
  begin
    // Color layer — use clip only
    if Images.Count = 0 then
    begin
      if Clip.Count > 0 then
        ClipVal := Clip[0]
      else
        ClipVal := Ord(bbBorder);
    end
    else
    begin
      if Clip.Count > 0 then
        ClipVal := Clip[(Idx - 1) mod Clip.Count]
      else
        ClipVal := Ord(bbBorder);
    end;
  end
  else
  begin
    // Image/gradient layer
    if Attachment.Count > 0 then
      Layer.Attachment := TPixieBackgroundAttachment(
        Attachment[Idx mod Attachment.Count])
    else
      Layer.Attachment := baScroll;

    if Repeat_.Count > 0 then
      Layer.Repeat_ := TPixieBackgroundRepeat(
        Repeat_[Idx mod Repeat_.Count])
    else
      Layer.Repeat_ := brRepeat;

    if Clip.Count > 0 then
      ClipVal := Clip[Idx mod Clip.Count]
    else
      ClipVal := Ord(bbBorder);

    if Origin.Count > 0 then
      OriginVal := Origin[Idx mod Origin.Count]
    else
      OriginVal := Ord(bbPadding);

    AutoAuto.Width := TPixieCssLength.PredefValue(Ord(bszAuto));
    AutoAuto.Height := TPixieCssLength.PredefValue(Ord(bszAuto));

    if Size.Count > 0 then
      SizeVal := Size[Idx mod Size.Count]
    else
      SizeVal := AutoAuto;

    if PositionX.Count > 0 then
      PosXVal := PositionX[Idx mod PositionX.Count]
    else
      PosXVal := TPixieCssLength.Create(0, cssUnitsPercentage);

    if PositionY.Count > 0 then
      PosYVal := PositionY[Idx mod PositionY.Count]
    else
      PosYVal := TPixieCssLength.Create(0, cssUnitsPercentage);

    case OriginVal of
      Ord(bbBorder):  Layer.OriginBox := BorderBox;
      Ord(bbContent): Layer.OriginBox := ContentBox;
    else
      Layer.OriginBox := PaddingBox;
    end;

    // fixed attachment resolves size and position against the viewport
    if (Layer.Attachment = baFixed) and Layer.IsRoot and (FixedBox <> nil) then
      Layer.OriginBox := FixedBox^;
  end;

  case ClipVal of
    Ord(bbPadding): Layer.ClipBox := PaddingBox;
    Ord(bbContent): Layer.ClipBox := ContentBox;
  else
    Layer.ClipBox := BorderBox;
  end;

  BgSize.Width := Layer.OriginBox.Width;
  BgSize.Height := Layer.OriginBox.Height;

  if GetLayerType(Idx) = bltImage then
  begin
    ImgLayer := GetImageLayer(Idx);
    if ImgLayer <> nil then
    try
      Assert(ElObj.GetDocument is TPixieDocument);
      TPixieDocument(ElObj.GetDocument).Container.GetImageInfo(
        ImgLayer.Url, ImgLayer.BaseUrl, ImgSz, ImgAspectOnly, ImgAspectRatio);

      // SVGs with only a viewBox have an aspect ratio but no natural
      // size. Per CSS, background-size: auto on such an image fills the
      // background area preserving aspect — equivalent to 'contain'.
      if ImgAspectOnly and (ImgAspectRatio > 0) and
         SizeVal.Width.IsPredefined and
         (SizeVal.Width.Predef = Ord(bszAuto)) and
         SizeVal.Height.IsPredefined and
         (SizeVal.Height.Predef = Ord(bszAuto)) then
      begin
        SizeVal.Width := TPixieCssLength.PredefValue(Ord(bszContain));
        ImgSz.Width := ImgAspectRatio;
        ImgSz.Height := 1;
      end;

      if (ImgSz.Width <> 0) and (ImgSz.Height <> 0) then
      begin
        ImgNewSz := ImgSz;
        ImgArWidth := ImgSz.Width / ImgSz.Height;
        ImgArHeight := ImgSz.Height / ImgSz.Width;

        if SizeVal.Width.IsPredefined then
        begin
          case SizeVal.Width.Predef of
            Ord(bszContain):
            begin
              if (Layer.OriginBox.Width * ImgArHeight) <=
                Layer.OriginBox.Height then
              begin
                ImgNewSz.Width := Layer.OriginBox.Width;
                ImgNewSz.Height :=
                  Layer.OriginBox.Width * ImgArHeight;
              end
              else
              begin
                ImgNewSz.Height := Layer.OriginBox.Height;
                ImgNewSz.Width :=
                  Layer.OriginBox.Height * ImgArWidth;
              end;
            end;
            Ord(bszCover):
            begin
              if (Layer.OriginBox.Width * ImgArHeight) >=
                Layer.OriginBox.Height then
              begin
                ImgNewSz.Width := Layer.OriginBox.Width;
                ImgNewSz.Height :=
                  Layer.OriginBox.Width * ImgArHeight;
              end
              else
              begin
                ImgNewSz.Height := Layer.OriginBox.Height;
                ImgNewSz.Width :=
                  Layer.OriginBox.Height * ImgArWidth;
              end;
            end;
            Ord(bszAuto):
            begin
              if not SizeVal.Height.IsPredefined then
              begin
                ImgNewSz.Height :=
                  SizeVal.Height.CalcPercent(Layer.OriginBox.Height);
                ImgNewSz.Width := ImgNewSz.Height * ImgArWidth;
              end;
            end;
          end;
        end
        else
        begin
          ImgNewSz.Width :=
            SizeVal.Width.CalcPercent(Layer.OriginBox.Width);
          if SizeVal.Height.IsPredefined then
            ImgNewSz.Height := ImgNewSz.Width * ImgArHeight
          else
            ImgNewSz.Height :=
              SizeVal.Height.CalcPercent(Layer.OriginBox.Height);
        end;
        BgSize := ImgNewSz;
      end;
    finally
      ImgLayer.Free;
    end;
  end
  else
  begin
    if Idx < Images.Count then
    begin
      if not SizeVal.Width.IsPredefined then
        BgSize.Width :=
          SizeVal.Width.CalcPercent(Layer.OriginBox.Width);
      if not SizeVal.Height.IsPredefined then
        BgSize.Height :=
          SizeVal.Height.CalcPercent(Layer.OriginBox.Height);
    end;
  end;

  if Idx < Images.Count then
  begin
    NewOriginBox.Width := BgSize.Width;
    NewOriginBox.Height := BgSize.Height;
    NewOriginBox.X := Layer.OriginBox.X +
      PosXVal.CalcPercent(Layer.OriginBox.Width - BgSize.Width);
    NewOriginBox.Y := Layer.OriginBox.Y +
      PosYVal.CalcPercent(Layer.OriginBox.Height - BgSize.Height);
    Layer.OriginBox := NewOriginBox;
  end;

  Result := True;
end;

procedure TPixieBackground.DrawLayer(Hdc: PtrUInt; Idx: Integer;
  const Layer: TPixieBackgroundLayer; Container: TObject;
  const ACurrentColor: TPixieWebColor);
var
  ColorLayer: TPixieBackgroundColor;
  ImgLayer: TPixieBackgroundImage;
  LinearGrad: TPixieLinearGradientLayer;
  RadialGrad: TPixieRadialGradientLayer;
  ConicGrad: TPixieConicGradientLayer;
  Cont: TPixieContainer;
  LT: TPixieBackgroundLayerType;
begin
  Assert(Container is TPixieContainer);
  Cont := TPixieContainer(Container);
  LT := GetLayerType(Idx);
  case LT of
    bltColor:
    begin
      ColorLayer := GetColorLayer(Idx);
      if ColorLayer <> nil then
      try
        Cont.DrawSolidFill(Hdc, Layer, ColorLayer.Color);
      finally
        ColorLayer.Free;
      end;
    end;

    bltImage:
    begin
      if (Layer.OriginBox.Width <> 0) and
         (Layer.OriginBox.Height <> 0) then
      begin
        ImgLayer := GetImageLayer(Idx);
        if ImgLayer <> nil then
        try
          Cont.DrawImage(Hdc, Layer, ImgLayer.Url, ImgLayer.BaseUrl);
        finally
          ImgLayer.Free;
        end;
      end;
    end;

    bltLinearGradient:
    begin
      if (Layer.OriginBox.Width <> 0) and
         (Layer.OriginBox.Height <> 0) then
      begin
        LinearGrad := GetLinearGradientLayer(Idx, Layer, ACurrentColor);
        if LinearGrad <> nil then
        try
          Cont.DrawLinearGradient(Hdc, Layer, LinearGrad);
        finally
          LinearGrad.Free;
        end;
      end;
    end;

    bltRadialGradient:
    begin
      if (Layer.OriginBox.Width <> 0) and
         (Layer.OriginBox.Height <> 0) then
      begin
        RadialGrad := GetRadialGradientLayer(Idx, Layer, ACurrentColor);
        if RadialGrad <> nil then
        try
          Cont.DrawRadialGradient(Hdc, Layer, RadialGrad);
        finally
          RadialGrad.Free;
        end;
      end;
    end;

    bltConicGradient:
    begin
      if (Layer.OriginBox.Width <> 0) and
         (Layer.OriginBox.Height <> 0) then
      begin
        ConicGrad := GetConicGradientLayer(Idx, Layer, ACurrentColor);
        if ConicGrad <> nil then
        try
          Cont.DrawConicGradient(Hdc, Layer, ConicGrad);
        finally
          ConicGrad.Free;
        end;
      end;
    end;
  end;
end;

end.
