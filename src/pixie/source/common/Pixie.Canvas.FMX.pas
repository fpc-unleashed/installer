unit Pixie.Canvas.FMX;

// FMX (FireMonkey) implementation of TPixieCanvas for cross-platform Delphi.
// Uses FMX.Graphics for 2D drawing and Pixie.FontMetrics for font metrics
// (FMX has no public ascent/descent API).

interface

uses
  System.SysUtils, System.Classes, System.Math, System.Types, System.UITypes,
  System.UIConsts, System.Generics.Collections, System.Math.Vectors,
  FMX.Graphics, FMX.Types, FMX.TextLayout,
  Pixie.Types, Pixie.WebColor, Pixie.Borders,
  Pixie.GradientLayer, Pixie.FontDescription,
  Pixie.Canvas, Pixie.FontMetrics;

type
  { TPixieFmxFont — font instance with FMX font + metrics }

  TPixieFmxFont = class
  public
    FmxFont: TFont;
    Metrics: TPixieFontMetrics;
    DecorationLine: Integer;
    SmallCaps: Boolean;
    constructor Create;
    destructor Destroy; override;
  end;

  { TPixieFmxImage — image instance backed by FMX TBitmap }

  TPixieFmxImage = class
  public
    Bitmap: TBitmap;
    SvgRenderer: TObject;  // TPixieSvgCanvasRenderer (owns)
    ImgWidth: Integer;
    ImgHeight: Integer;
    AspectOnly: Boolean;
    AspectRatio: Single;
    constructor Create;
    destructor Destroy; override;
  end;

  TPixieFmxFontList = TObjectList<TPixieFmxFont>;
  TPixieFmxImageList = TObjectList<TPixieFmxImage>;

  { TPixieFmxCanvas }

  TPixieFmxCanvas = class(TPixieCanvas)
  private
    FCanvas: TCanvas;
    FOpacity: Single;
    FOpacityStack: array[0..31] of Single;
    FOpacityTop: Integer;
    FBrush: TBrush;
    FStrokeBrush: TStrokeBrush;
    FPath: TPathData;
    FCurrentPath: TPathData;
    FTextLayout: TTextLayout;
    FStateStack: array[0..63] of TCanvasSaveState;
    FStateTop: Integer;
    FBaseState: TCanvasSaveState;
    FOffscreenBitmap: TBitmap;
    FOffscreenSavedCanvas: TCanvas;
    FOffscreenWidth, FOffscreenHeight: Integer;
    FOffscreenScene: Boolean;

    function ToAlphaColor(const C: TPixieWebColor): TAlphaColor;
    procedure ApplyDashPattern(Width: Single);
    procedure BuildRoundedRectPath(Path: TPathData; X, Y, W, H: Single;
      const R: TPixieBorderRadiuses);
    procedure SetupGradientStops(const Points: TPixieColorPointList;
      ABrush: TBrush = nil);
    procedure DrawBorderSide(const Border: TPixieBorder;
      X1, Y1, X2, Y2: Single);
    procedure FlushOffscreen;
  public
    constructor Create;
    destructor Destroy; override;

    // Lifecycle
    procedure BeginPaint(DC: PtrUInt); override;
    procedure EndPaint; override;

    // State
    procedure SaveState; override;
    procedure RestoreState; override;
    procedure PushOpacity(AOpacity: Single); override;
    procedure PopOpacity; override;

    // Clipping
    procedure SetClipRect(const R: TPixiePosition;
      const Radius: TPixieBorderRadiuses); override;

    // Fills
    procedure FillRect(X, Y, W, H: Single;
      Color: TPixieWebColor); override;
    procedure FillRoundedRect(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      Color: TPixieWebColor); override;

    // Gradients
    procedure FillLinearGradient(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      const Gradient: TPixieLinearGradientLayer); override;
    procedure FillRadialGradient(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      const Gradient: TPixieRadialGradientLayer); override;
    procedure FillConicGradient(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      const Gradient: TPixieConicGradientLayer); override;

    // Borders
    procedure DrawBorders(const Borders: TPixieBorders;
      const Pos: TPixiePosition; IsRoot: Boolean); override;

    // Fonts
    function CreateFont(const Descr: TPixieFontDescription;
      out Metrics: TPixieFontMetrics): TPixieFontHandle; override;
    procedure DoDeleteFont(Handle: TPixieFontHandle); override;

    // Text
    function DoMeasureText(const Text: string;
      Handle: TPixieFontHandle): TPixiePixel; override;
    procedure DrawText(const Text: string; Handle: TPixieFontHandle;
      Color: TPixieWebColor; X, Y, W, H: Single); override;

    // Units
    function PtToPx(Pt: Single): TPixiePixel; override;

    // Images
    function LoadImage(const Path: string): TPixieImageHandle; override;
    function LoadImageFromPixels(Width, Height: Integer;
      Pixels: Pointer; Pitch: Integer): TPixieImageHandle; override;
    function LoadImageFromStream(Stream: TStream): TPixieImageHandle; override;
    function LoadSvgFromData(Data: Pointer;
      Size: Integer): TPixieImageHandle; override;
    procedure FreeImage(Handle: TPixieImageHandle); override;
    procedure GetImageSize(Handle: TPixieImageHandle;
      out W, H: Single); override;
    function GetImageAspectInfo(Handle: TPixieImageHandle;
      out AspectRatio: Single): Boolean; override;
    procedure DrawImage(Handle: TPixieImageHandle;
      DstX, DstY, DstW, DstH: Single); override;

    // Simple shapes
    procedure FillEllipse(X, Y, W, H: Single;
      Color: TPixieWebColor); override;
    procedure DrawEllipse(X, Y, W, H: Single;
      Color: TPixieWebColor; StrokeWidth: Single); override;
    procedure DrawRect(X, Y, W, H: Single;
      Color: TPixieWebColor; StrokeWidth: Single); override;
    procedure DrawLine(X1, Y1, X2, Y2: Single;
      Color: TPixieWebColor; StrokeWidth: Single;
      Style: TPixieTextDecorationStyle = tdsSolid); override;
    procedure StrokePolyline(const Points: array of Single;
      Color: TPixieWebColor; StrokeWidth: Single); override;

    // Path API
    procedure BeginPath; override;
    procedure MoveTo(X, Y: Single); override;
    procedure LineTo(X, Y: Single); override;
    procedure CurveTo(X1, Y1, X2, Y2, X3, Y3: Single); override;
    procedure ClosePath; override;
    procedure FillPath(Color: TPixieWebColor;
      FillRule: TPixieFillRule = frNonZero); override;
    procedure StrokePath(Color: TPixieWebColor; Width: Single); override;
    procedure FillAndStrokePath(FillColor: TPixieWebColor;
      StrokeColor: TPixieWebColor; StrokeWidth: Single;
      FillRule: TPixieFillRule = frNonZero); override;
    procedure DiscardPath; override;
    procedure ClipPath(FillRule: TPixieFillRule = frNonZero); override;
    procedure FillPathLinearGradient(
      const Gradient: TPixieLinearGradientLayer;
      FillRule: TPixieFillRule = frNonZero); override;
    procedure FillPathRadialGradient(
      const Gradient: TPixieRadialGradientLayer;
      FillRule: TPixieFillRule = frNonZero); override;
    procedure StrokePathLinearGradient(
      const Gradient: TPixieLinearGradientLayer;
      Width: Single); override;
    procedure StrokePathRadialGradient(
      const Gradient: TPixieRadialGradientLayer;
      Width: Single); override;
    procedure ConcatMatrix(A, B, C, D, E, F: Single); override;

    // Off-screen + image export API
    procedure BeginOffscreen(Width, Height: Integer;
      ClearColor: TPixieWebColor); override;
    procedure EndOffscreen; override;
    procedure SaveAsPng(Stream: TStream); override;
    procedure SaveAsPng(const FileName: string); override;
    procedure SaveAsBmp(Stream: TStream); override;

    // View / scale
  end;

implementation

uses
  Pixie.SvgRenderer.Canvas;

const
  // Kappa constant for quarter-circle bezier approximation
  BezierKappa = 0.5522847498;

  // Line cap/join mapping
  // FMX has no square cap — Flat is the closest.
  // FMX has no MiterOrBevel — Bevel avoids degenerate miter spikes.
  CapMap: array[TPixieLineCap] of TStrokeCap = (
    TStrokeCap.Flat, TStrokeCap.Round, TStrokeCap.Flat);
  JoinMap: array[TPixieLineJoin] of TStrokeJoin = (
    TStrokeJoin.Bevel, TStrokeJoin.Round, TStrokeJoin.Bevel);

// ---------------------------------------------------------------------------
// Font check callback for PixieResolveFontFamily
// ---------------------------------------------------------------------------

function FmxCheckFont(const Name: string): Boolean;
var
  Entry: TPixieFontMetricsEntry;
begin
  Result := PixieLookupFontMetrics(Name, Entry);
end;

// ---------------------------------------------------------------------------
// TPixieFmxFont
// ---------------------------------------------------------------------------

constructor TPixieFmxFont.Create;
begin
  inherited Create;
  FmxFont := TFont.Create;
  DecorationLine := 0;
end;

destructor TPixieFmxFont.Destroy;
begin
  FmxFont.Free;
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// TPixieFmxImage
// ---------------------------------------------------------------------------

constructor TPixieFmxImage.Create;
begin
  inherited Create;
  Bitmap := nil;
  ImgWidth := 0;
  ImgHeight := 0;
  AspectOnly := False;
  AspectRatio := 0;
end;

destructor TPixieFmxImage.Destroy;
begin
  Bitmap.Free;
  SvgRenderer.Free;
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// TPixieFmxCanvas — Construction
// ---------------------------------------------------------------------------

constructor TPixieFmxCanvas.Create;
begin
  inherited Create;
  FCanvas := nil;
  FOpacity := 1.0;
  FOpacityTop := 0;
  FStateTop := 0;
  FBaseState := nil;
  FBrush := TBrush.Create(TBrushKind.Solid, claBlack);
  FStrokeBrush := TStrokeBrush.Create(TBrushKind.Solid, claBlack);
  FPath := TPathData.Create;
  FCurrentPath := TPathData.Create;
  FTextLayout := TTextLayoutManager.DefaultTextLayout.Create;
end;

destructor TPixieFmxCanvas.Destroy;
begin
  FTextLayout.Free;
  FCurrentPath.Free;
  FPath.Free;
  FStrokeBrush.Free;
  FBrush.Free;
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function TPixieFmxCanvas.ToAlphaColor(const C: TPixieWebColor): TAlphaColor;
var
  Rec: TAlphaColorRec;
begin
  Rec.R := C.Red;
  Rec.G := C.Green;
  Rec.B := C.Blue;
  Rec.A := C.Alpha;
  Result := Rec.Color;
end;

procedure TPixieFmxCanvas.ApplyDashPattern(Width: Single);
var
  FmxDashes: TDashArray;
  I: Integer;
begin
  if (Length(FPathDashArray) > 0) and (Width > 0) then
  begin
    SetLength(FmxDashes, Length(FPathDashArray));
    for I := 0 to High(FPathDashArray) do
      FmxDashes[I] := FPathDashArray[I] / Width;
    FStrokeBrush.SetCustomDash(FmxDashes, FPathDashOffset / Width);
  end
  else
    FStrokeBrush.Dash := TStrokeDash.Solid;
end;

procedure TPixieFmxCanvas.BuildRoundedRectPath(Path: TPathData;
  X, Y, W, H: Single; const R: TPixieBorderRadiuses);
const
  K = BezierKappa;
begin
  Path.Clear;

  // Start at top-left, after the top-left radius
  Path.MoveTo(PointF(X + R.TopLeftX, Y));

  // Top edge
  Path.LineTo(PointF(X + W - R.TopRightX, Y));

  // Top-right corner
  if (R.TopRightX > 0) and (R.TopRightY > 0) then
    Path.CurveTo(
      PointF(X + W - R.TopRightX * (1 - K), Y),
      PointF(X + W, Y + R.TopRightY * (1 - K)),
      PointF(X + W, Y + R.TopRightY))
  else
    Path.LineTo(PointF(X + W, Y));

  // Right edge
  Path.LineTo(PointF(X + W, Y + H - R.BottomRightY));

  // Bottom-right corner
  if (R.BottomRightX > 0) and (R.BottomRightY > 0) then
    Path.CurveTo(
      PointF(X + W, Y + H - R.BottomRightY * (1 - K)),
      PointF(X + W - R.BottomRightX * (1 - K), Y + H),
      PointF(X + W - R.BottomRightX, Y + H))
  else
    Path.LineTo(PointF(X + W, Y + H));

  // Bottom edge
  Path.LineTo(PointF(X + R.BottomLeftX, Y + H));

  // Bottom-left corner
  if (R.BottomLeftX > 0) and (R.BottomLeftY > 0) then
    Path.CurveTo(
      PointF(X + R.BottomLeftX * (1 - K), Y + H),
      PointF(X, Y + H - R.BottomLeftY * (1 - K)),
      PointF(X, Y + H - R.BottomLeftY))
  else
    Path.LineTo(PointF(X, Y + H));

  // Left edge
  Path.LineTo(PointF(X, Y + R.TopLeftY));

  // Top-left corner
  if (R.TopLeftX > 0) and (R.TopLeftY > 0) then
    Path.CurveTo(
      PointF(X, Y + R.TopLeftY * (1 - K)),
      PointF(X + R.TopLeftX * (1 - K), Y),
      PointF(X + R.TopLeftX, Y))
  else
    Path.LineTo(PointF(X, Y));

  Path.ClosePath;
end;

procedure TPixieFmxCanvas.SetupGradientStops(
  const Points: TPixieColorPointList; ABrush: TBrush);
var
  I: Integer;
  GradPt: TGradientPoint;
  Target: TBrush;
begin
  if ABrush <> nil then Target := ABrush else Target := FBrush;
  Target.Gradient.Points.Clear;
  for I := 0 to Points.Count - 1 do
  begin
    GradPt := TGradientPoint(Target.Gradient.Points.Add);
    GradPt.Offset := Points[I].Offset;
    GradPt.Color := ToAlphaColor(Points[I].Color);
  end;
end;

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

procedure TPixieFmxCanvas.BeginPaint(DC: PtrUInt);
var
  M: TMatrix;
begin
  FCanvas := TCanvas(Pointer(DC));
  FOpacity := 1.0;
  FOpacityTop := 0;
  FStateTop := 0;

  if FScale <> 1.0 then
  begin
    FBaseState := FCanvas.SaveState;
    M := TMatrix.CreateScaling(FScale, FScale);
    FCanvas.MultiplyMatrix(M);
  end
  else
    FBaseState := nil;
end;

procedure TPixieFmxCanvas.EndPaint;
begin
  if FBaseState <> nil then
  begin
    FCanvas.RestoreState(FBaseState);
    FBaseState := nil;
  end;
  FCanvas := nil;
end;

// ---------------------------------------------------------------------------
// State save/restore
// ---------------------------------------------------------------------------

procedure TPixieFmxCanvas.SaveState;
begin
  if (FCanvas = nil) or (FStateTop > High(FStateStack)) then Exit;
  FStateStack[FStateTop] := FCanvas.SaveState;
  Inc(FStateTop);
end;

procedure TPixieFmxCanvas.RestoreState;
begin
  if (FCanvas = nil) or (FStateTop <= 0) then Exit;
  Dec(FStateTop);
  FCanvas.RestoreState(FStateStack[FStateTop]);
end;

procedure TPixieFmxCanvas.PushOpacity(AOpacity: Single);
begin
  if FOpacityTop >= Length(FOpacityStack) then Exit;
  FOpacityStack[FOpacityTop] := FOpacity;
  Inc(FOpacityTop);
  FOpacity := FOpacity * AOpacity;
end;

procedure TPixieFmxCanvas.PopOpacity;
begin
  if FOpacityTop <= 0 then Exit;
  Dec(FOpacityTop);
  FOpacity := FOpacityStack[FOpacityTop];
end;

// ---------------------------------------------------------------------------
// Clipping
// ---------------------------------------------------------------------------

procedure TPixieFmxCanvas.SetClipRect(const R: TPixiePosition;
  const Radius: TPixieBorderRadiuses);
begin
  if FCanvas = nil then Exit;
  FCanvas.IntersectClipRect(TRectF.Create(R.X, R.Y, R.X + R.Width,
    R.Y + R.Height));
end;

// ---------------------------------------------------------------------------
// Solid fills
// ---------------------------------------------------------------------------

procedure TPixieFmxCanvas.FillRect(X, Y, W, H: Single;
  Color: TPixieWebColor);
begin
  if (FCanvas = nil) or (Color.Alpha = 0) then Exit;
  FBrush.Kind := TBrushKind.Solid;
  FBrush.Color := ToAlphaColor(Color);
  FCanvas.FillRect(TRectF.Create(X, Y, X + W, Y + H), 0, 0, AllCorners,
    FOpacity, FBrush);
end;

procedure TPixieFmxCanvas.FillRoundedRect(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses; Color: TPixieWebColor);
begin
  if (FCanvas = nil) or (Color.Alpha = 0) then Exit;
  FBrush.Kind := TBrushKind.Solid;
  FBrush.Color := ToAlphaColor(Color);

  if Radius.HasRadius then
  begin
    BuildRoundedRectPath(FPath, X, Y, W, H, Radius);
    FCanvas.FillPath(FPath, FOpacity, FBrush);
  end
  else
    FCanvas.FillRect(TRectF.Create(X, Y, X + W, Y + H), 0, 0, AllCorners,
      FOpacity, FBrush);
end;

// ---------------------------------------------------------------------------
// Gradients
// ---------------------------------------------------------------------------

procedure TPixieFmxCanvas.FillLinearGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieLinearGradientLayer);
var
  R: TRectF;
  BX1, BY1, BX2, BY2, BW, BH: Single;
begin
  if (FCanvas = nil) or (Gradient = nil) then Exit;
  if Gradient.ColorPoints.Count < 2 then Exit;

  // Bounding rect covering fill area and gradient line
  BX1 := Min(X, Min(Gradient.StartPt.X, Gradient.EndPt.X));
  BY1 := Min(Y, Min(Gradient.StartPt.Y, Gradient.EndPt.Y));
  BX2 := Max(X + W, Max(Gradient.StartPt.X, Gradient.EndPt.X));
  BY2 := Max(Y + H, Max(Gradient.StartPt.Y, Gradient.EndPt.Y));
  BW := BX2 - BX1;
  BH := BY2 - BY1;
  if (BW <= 0) or (BH <= 0) then Exit;

  FBrush.Kind := TBrushKind.Gradient;
  FBrush.Gradient.Style := TGradientStyle.Linear;
  FBrush.Gradient.StartPosition.X := (Gradient.StartPt.X - BX1) / BW;
  FBrush.Gradient.StartPosition.Y := (Gradient.StartPt.Y - BY1) / BH;
  FBrush.Gradient.StopPosition.X := (Gradient.EndPt.X - BX1) / BW;
  FBrush.Gradient.StopPosition.Y := (Gradient.EndPt.Y - BY1) / BH;
  SetupGradientStops(Gradient.ColorPoints);

  SaveState;
  try
    if Radius.HasRadius then
    begin
      FCanvas.IntersectClipRect(TRectF.Create(X, Y, X + W, Y + H));
      BuildRoundedRectPath(FPath, X, Y, W, H, Radius);
      FCanvas.FillPath(FPath, FOpacity, FBrush);
    end
    else
    begin
      FCanvas.IntersectClipRect(TRectF.Create(X, Y, X + W, Y + H));
      R := TRectF.Create(BX1, BY1, BX2, BY2);
      FCanvas.FillRect(R, 0, 0, AllCorners, FOpacity, FBrush);
    end;
  finally
    RestoreState;
  end;
end;

procedure TPixieFmxCanvas.FillRadialGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieRadialGradientLayer);
var
  R: TRectF;
  GradRect: TRectF;
begin
  if (FCanvas = nil) or (Gradient = nil) then Exit;
  if Gradient.ColorPoints.Count < 2 then Exit;

  FBrush.Kind := TBrushKind.Gradient;
  FBrush.Gradient.Style := TGradientStyle.Radial;
  SetupGradientStops(Gradient.ColorPoints);

  // FMX radial gradient fills an ellipse inscribed in the bounding rect
  GradRect := TRectF.Create(
    Gradient.Position.X - Gradient.Radius.X,
    Gradient.Position.Y - Gradient.Radius.Y,
    Gradient.Position.X + Gradient.Radius.X,
    Gradient.Position.Y + Gradient.Radius.Y);

  SaveState;
  try
    if Radius.HasRadius then
    begin
      FCanvas.IntersectClipRect(TRectF.Create(X, Y, X + W, Y + H));
      BuildRoundedRectPath(FPath, X, Y, W, H, Radius);
      FCanvas.FillPath(FPath, FOpacity, FBrush);
    end
    else
    begin
      R := TRectF.Create(X, Y, X + W, Y + H);
      FCanvas.IntersectClipRect(R);
      FCanvas.FillRect(GradRect, 0, 0, AllCorners, FOpacity, FBrush);
    end;
  finally
    RestoreState;
  end;
end;

procedure TPixieFmxCanvas.FillConicGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieConicGradientLayer);
var
  Count, I, J, Steps: Integer;
  Cx, Cy, MaxR, Angle, Frac: Single;
  Cp: TPixieColorPoint;
  C: TPixieWebColor;
  StartAngle, SweepAngle, CosA, SinA, CosB, SinB: Single;
begin
  // FMX has no native conic gradient — approximate with pie sectors
  if (FCanvas = nil) or (Gradient = nil) then Exit;
  Count := Gradient.ColorPoints.Count;
  if Count < 2 then Exit;

  Cx := Gradient.Position.X;
  Cy := Gradient.Position.Y;
  MaxR := Max(Max(Abs(X + W - Cx), Abs(X - Cx)),
              Max(Abs(Y + H - Cy), Abs(Y - Cy))) * 1.5;
  if MaxR < 1 then MaxR := 1;

  SaveState;
  try
    FCanvas.IntersectClipRect(TRectF.Create(X, Y, X + W, Y + H));

    Steps := 360;
    SweepAngle := 2 * Pi / Steps;

    for J := 0 to Steps - 1 do
    begin
      Angle := J / Steps;

      // Find the color at this angle
      C := Gradient.ColorPoints[0].Color;
      for I := 0 to Count - 2 do
      begin
        if (Angle >= Gradient.ColorPoints[I].Offset) and
           (Angle <= Gradient.ColorPoints[I + 1].Offset) then
        begin
          Cp := Gradient.ColorPoints[I];
          if (Gradient.ColorPoints[I + 1].Offset - Cp.Offset) > 0.0001 then
          begin
            Frac := (Angle - Cp.Offset) /
              (Gradient.ColorPoints[I + 1].Offset - Cp.Offset);
            C.Red := Round(Cp.Color.Red +
              Frac * (Gradient.ColorPoints[I + 1].Color.Red - Cp.Color.Red));
            C.Green := Round(Cp.Color.Green +
              Frac * (Gradient.ColorPoints[I + 1].Color.Green - Cp.Color.Green));
            C.Blue := Round(Cp.Color.Blue +
              Frac * (Gradient.ColorPoints[I + 1].Color.Blue - Cp.Color.Blue));
            C.Alpha := Round(Cp.Color.Alpha +
              Frac * (Gradient.ColorPoints[I + 1].Color.Alpha - Cp.Color.Alpha));
          end
          else
            C := Cp.Color;
          Break;
        end;
      end;

      FBrush.Kind := TBrushKind.Solid;
      FBrush.Color := ToAlphaColor(C);

      // Build pie sector as a triangle fan segment
      StartAngle := (Gradient.Angle - 90 + J * (360.0 / Steps)) * Pi / 180.0;
      SinCos(StartAngle, SinA, CosA);
      SinCos(StartAngle + SweepAngle, SinB, CosB);

      FPath.Clear;
      FPath.MoveTo(PointF(Cx, Cy));
      FPath.LineTo(PointF(Cx + CosA * MaxR, Cy + SinA * MaxR));
      FPath.LineTo(PointF(Cx + CosB * MaxR, Cy + SinB * MaxR));
      FPath.ClosePath;

      FCanvas.FillPath(FPath, FOpacity, FBrush);
    end;
  finally
    RestoreState;
  end;
end;

// ---------------------------------------------------------------------------
// Borders
// ---------------------------------------------------------------------------

procedure TPixieFmxCanvas.DrawBorderSide(const Border: TPixieBorder;
  X1, Y1, X2, Y2: Single);
var
  LineW, Offset, Dx, Dy, Len, Nx, Ny: Single;
begin
  if (Border.Width <= 0) or (Border.Style = bsNone) or
     (Border.Style = bsHidden) then
    Exit;

  FStrokeBrush.Kind := TBrushKind.Solid;
  FStrokeBrush.Color := ToAlphaColor(Border.Color);
  FStrokeBrush.Thickness := Border.Width;

  // Double border: two solid lines of width/3 separated by width/3 gap
  if Border.Style = bsDouble then
  begin
    LineW := Border.Width / 3;
    if LineW < 1 then LineW := 1;
    Dx := X2 - X1;
    Dy := Y2 - Y1;
    Len := Sqrt(Dx * Dx + Dy * Dy);
    if Len < 0.001 then Exit;
    Nx := -Dy / Len;
    Ny := Dx / Len;
    Offset := Border.Width / 2 - LineW / 2;
    FStrokeBrush.Thickness := LineW;
    FStrokeBrush.Dash := TStrokeDash.Solid;
    FStrokeBrush.Cap := TStrokeCap.Flat;
    // Outer line
    FCanvas.DrawLine(
      PointF(X1 - Nx * Offset, Y1 - Ny * Offset),
      PointF(X2 - Nx * Offset, Y2 - Ny * Offset),
      FOpacity, FStrokeBrush);
    // Inner line
    FCanvas.DrawLine(
      PointF(X1 + Nx * Offset, Y1 + Ny * Offset),
      PointF(X2 + Nx * Offset, Y2 + Ny * Offset),
      FOpacity, FStrokeBrush);
    Exit;
  end;

  case Border.Style of
    bsDotted: FStrokeBrush.Dash := TStrokeDash.Dot;
    bsDashed: FStrokeBrush.Dash := TStrokeDash.Dash;
  else
    FStrokeBrush.Dash := TStrokeDash.Solid;
  end;

  if Border.Style = bsDotted then
    FStrokeBrush.Cap := TStrokeCap.Round
  else
    FStrokeBrush.Cap := TStrokeCap.Flat;
  FCanvas.DrawLine(PointF(X1, Y1), PointF(X2, Y2), FOpacity, FStrokeBrush);
end;

procedure TPixieFmxCanvas.DrawBorders(const Borders: TPixieBorders;
  const Pos: TPixiePosition; IsRoot: Boolean);
var
  X, Y, W, H: Single;
begin
  if FCanvas = nil then Exit;
  if not Borders.IsVisible then Exit;

  X := Pos.X;
  Y := Pos.Y;
  W := Pos.Width;
  H := Pos.Height;

  // Rounded borders: draw as single path
  if Borders.Radius.HasRadius then
  begin
    if (Borders.Top.Width > 0) and (Borders.Top.Style <> bsNone) then
    begin
      FStrokeBrush.Kind := TBrushKind.Solid;
      FStrokeBrush.Color := ToAlphaColor(Borders.Top.Color);
      FStrokeBrush.Thickness := Borders.Top.Width;
      FStrokeBrush.Dash := TStrokeDash.Solid;
      BuildRoundedRectPath(FPath, X, Y, W, H, Borders.Radius);
      FCanvas.DrawPath(FPath, FOpacity, FStrokeBrush);
      Exit;
    end;
  end;

  // Straight borders: draw each side, inset by half adjacent width for clean corners
  DrawBorderSide(Borders.Top,
    X + Borders.Left.Width / 2, Y + Borders.Top.Width / 2,
    X + W - Borders.Right.Width / 2, Y + Borders.Top.Width / 2);

  DrawBorderSide(Borders.Right,
    X + W - Borders.Right.Width / 2, Y + Borders.Top.Width / 2,
    X + W - Borders.Right.Width / 2, Y + H - Borders.Bottom.Width / 2);

  DrawBorderSide(Borders.Bottom,
    X + Borders.Left.Width / 2, Y + H - Borders.Bottom.Width / 2,
    X + W - Borders.Right.Width / 2, Y + H - Borders.Bottom.Width / 2);

  DrawBorderSide(Borders.Left,
    X + Borders.Left.Width / 2, Y + Borders.Top.Width / 2,
    X + Borders.Left.Width / 2, Y + H - Borders.Bottom.Width / 2);
end;

// ---------------------------------------------------------------------------
// Font management
// ---------------------------------------------------------------------------

function TPixieFmxCanvas.CreateFont(
  const Descr: TPixieFontDescription;
  out Metrics: TPixieFontMetrics): TPixieFontHandle;
var
  Info: TPixieFmxFont;
  ResolvedFamily: string;
  Entry: TPixieFontMetricsEntry;
  Scale: Single;
begin
  Info := TPixieFmxFont.Create;
  Info.DecorationLine := Descr.DecorationLine;
  Info.SmallCaps := Descr.Variant = fvSmallCaps;

  // Resolve font family
  ResolvedFamily := PixieResolveFontFamily(Descr.Family, FmxCheckFont);

  // Configure FMX font
  Info.FmxFont.Family := ResolvedFamily;
  Info.FmxFont.Size := Descr.Size;
  Info.FmxFont.Style := [];
  if Descr.Weight >= 600 then
    Info.FmxFont.Style := Info.FmxFont.Style + [TFontStyle.fsBold];
  if Descr.Style = fstItalic then
    Info.FmxFont.Style := Info.FmxFont.Style + [TFontStyle.fsItalic];

  // Compute metrics from font metrics table
  if PixieLookupFontMetrics(ResolvedFamily, Entry) then
  begin
    Scale := Descr.Size / Entry.UnitsPerEm;
    Metrics.Ascent := Entry.Ascent * Scale;
    Metrics.Descent := Entry.Descent * Scale;
    Metrics.Height := (Entry.Ascent + Entry.Descent + Entry.LineGap) * Scale;
    if Entry.XHeight > 0 then
      Metrics.XHeight := Entry.XHeight * Scale
    else
      Metrics.XHeight := Descr.Size * 0.5;
  end
  else
  begin
    // Fallback: use generic sans-serif metrics
    PixieDefaultFontMetrics(fmcSansSerif, Entry);
    Scale := Descr.Size / Entry.UnitsPerEm;
    Metrics.Ascent := Entry.Ascent * Scale;
    Metrics.Descent := Entry.Descent * Scale;
    Metrics.Height := (Entry.Ascent + Entry.Descent + Entry.LineGap) * Scale;
    Metrics.XHeight := Entry.XHeight * Scale;
  end;

  Metrics.FontSize := Descr.Size;
  Metrics.ChWidth := Descr.Size * 0.6;
  Metrics.DrawSpaces := True;
  Metrics.CalcShifts;
  Info.Metrics := Metrics;

  Result := TPixieFontHandle(Info);
end;

procedure TPixieFmxCanvas.DoDeleteFont(Handle: TPixieFontHandle);
begin
  if Handle = 0 then Exit;
  TPixieFmxFont(Handle).Free;
end;

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

function TPixieFmxCanvas.DoMeasureText(const Text: string;
  Handle: TPixieFontHandle): TPixiePixel;
var
  Info: TPixieFmxFont;
  Upper: string;
  I, RunStart, Len: Integer;
  InLower: Boolean;
  SmallSize: Single;
begin
  Result := 0;
  if Handle = 0 then Exit;
  Info := TPixieFmxFont(Handle);

  if Info.SmallCaps then
  begin
    Upper := UpperCase(Text);
    Len := Length(Text);
    SmallSize := Info.FmxFont.Size * PixieSmallCapsScale;
    FTextLayout.Font.Family := Info.FmxFont.Family;
    FTextLayout.Font.Style := Info.FmxFont.Style;
    FTextLayout.MaxSize := TSizeF.Create(100000, 100000);
    FTextLayout.WordWrap := False;
    FTextLayout.Trimming := TTextTrimming.None;
    RunStart := 1;
    InLower := False;
    for I := 1 to Len do
    begin
      if (Text[I] <> Upper[I]) <> InLower then
      begin
        if I > RunStart then
        begin
          FTextLayout.BeginUpdate;
          try
            if InLower then
              FTextLayout.Font.Size := SmallSize
            else
              FTextLayout.Font.Size := Info.FmxFont.Size;
            FTextLayout.Text := Copy(Upper, RunStart, I - RunStart);
          finally
            FTextLayout.EndUpdate;
          end;
          Result := Result + FTextLayout.TextWidth;
        end;
        RunStart := I;
        InLower := Text[I] <> Upper[I];
      end;
    end;
    if RunStart <= Len then
    begin
      FTextLayout.BeginUpdate;
      try
        if InLower then
          FTextLayout.Font.Size := SmallSize
        else
          FTextLayout.Font.Size := Info.FmxFont.Size;
        FTextLayout.Text := Copy(Upper, RunStart, Len - RunStart + 1);
      finally
        FTextLayout.EndUpdate;
      end;
      Result := Result + FTextLayout.TextWidth;
    end;
    Exit;
  end;

  FTextLayout.BeginUpdate;
  try
    FTextLayout.Font.Family := Info.FmxFont.Family;
    FTextLayout.Font.Size := Info.FmxFont.Size;
    FTextLayout.Font.Style := Info.FmxFont.Style;
    FTextLayout.Text := Text;
    FTextLayout.MaxSize := TSizeF.Create(100000, 100000);
    FTextLayout.WordWrap := False;
    FTextLayout.Trimming := TTextTrimming.None;
  finally
    FTextLayout.EndUpdate;
  end;
  Result := FTextLayout.TextWidth;
end;

procedure TPixieFmxCanvas.DrawText(const Text: string;
  Handle: TPixieFontHandle; Color: TPixieWebColor;
  X, Y, W, H: Single);
var
  Info: TPixieFmxFont;
  R: TRectF;
  Seg, Upper: string;
  I, RunStart, Len: Integer;
  InLower: Boolean;
  SmallSize, SegW, CurX, SegY, BaselineShift: Single;
begin
  if (FCanvas = nil) or (Handle = 0) then Exit;
  Info := TPixieFmxFont(Handle);

  FCanvas.Fill.Kind := TBrushKind.Solid;
  FCanvas.Fill.Color := ToAlphaColor(Color);

  if Info.SmallCaps then
  begin
    Upper := UpperCase(Text);
    Len := Length(Text);
    CurX := X;
    SmallSize := Info.FmxFont.Size * PixieSmallCapsScale;
    // FillText aligns from the top; shift small segments down so baselines match
    BaselineShift := Info.Metrics.Ascent * (1 - PixieSmallCapsScale);
    FCanvas.Font.Family := Info.FmxFont.Family;
    FCanvas.Font.Style := Info.FmxFont.Style;
    FTextLayout.Font.Family := Info.FmxFont.Family;
    FTextLayout.Font.Style := Info.FmxFont.Style;
    FTextLayout.MaxSize := TSizeF.Create(100000, 100000);
    FTextLayout.WordWrap := False;
    RunStart := 1;
    InLower := False;
    for I := 1 to Len do
    begin
      if (Text[I] <> Upper[I]) <> InLower then
      begin
        if I > RunStart then
        begin
          if InLower then
          begin
            FCanvas.Font.Size := SmallSize;
            SegY := Y + BaselineShift;
          end
          else
          begin
            FCanvas.Font.Size := Info.FmxFont.Size;
            SegY := Y;
          end;
          Seg := Copy(Upper, RunStart, I - RunStart);
          FTextLayout.BeginUpdate;
          try
            FTextLayout.Font.Size := FCanvas.Font.Size;
            FTextLayout.Text := Seg;
          finally
            FTextLayout.EndUpdate;
          end;
          SegW := FTextLayout.TextWidth;
          R := TRectF.Create(CurX, SegY, CurX + SegW, SegY + H);
          FCanvas.FillText(R, Seg,
            False, FOpacity, [], TTextAlign.Leading, TTextAlign.Leading);
          CurX := CurX + SegW;
        end;
        RunStart := I;
        InLower := Text[I] <> Upper[I];
      end;
    end;
    if RunStart <= Len then
    begin
      if InLower then
      begin
        FCanvas.Font.Size := SmallSize;
        SegY := Y + BaselineShift;
      end
      else
      begin
        FCanvas.Font.Size := Info.FmxFont.Size;
        SegY := Y;
      end;
      R := TRectF.Create(CurX, SegY, CurX + W - (CurX - X), SegY + H);
      FCanvas.FillText(R, Copy(Upper, RunStart, Len - RunStart + 1),
        False, FOpacity, [], TTextAlign.Leading, TTextAlign.Leading);
    end;
    Exit;
  end;

  FCanvas.Font.Family := Info.FmxFont.Family;
  FCanvas.Font.Size := Info.FmxFont.Size;
  FCanvas.Font.Style := Info.FmxFont.Style;

  // Text decoration is drawn at the element level (TPixieHtmlTag.DrawBackground)

  R := TRectF.Create(X, Y, X + W, Y + H);
  FCanvas.FillText(R, Text, False, FOpacity, [],
    TTextAlign.Leading, TTextAlign.Leading);
end;

function TPixieFmxCanvas.PtToPx(Pt: Single): TPixiePixel;
begin
  Result := Trunc(Pt * 96.0 / 72.0);
end;

// ---------------------------------------------------------------------------
// Images
// ---------------------------------------------------------------------------

function TPixieFmxCanvas.LoadImage(const Path: string): TPixieImageHandle;
var
  Info: TPixieFmxImage;
  Resolved: string;
  Stream: TFileStream;
  Data: TBytes;
begin
  Result := 0;
  Resolved := ExpandFileName(Path);
  if not FileExists(Resolved) then Exit;

  // SVG — use canvas renderer
  if LowerCase(ExtractFileExt(Resolved)) = '.svg' then
  begin
    try
      Stream := TFileStream.Create(Resolved, fmOpenRead or fmShareDenyNone);
      try
        if Stream.Size <= 0 then Exit;
        SetLength(Data, Stream.Size);
        Stream.ReadBuffer(Data[0], Stream.Size);
      finally
        Stream.Free;
      end;
      Result := LoadSvgFromData(@Data[0], Length(Data));
    except
      Result := 0;
    end;
    Exit;
  end;

  Info := TPixieFmxImage.Create;
  try
    Info.Bitmap := TBitmap.CreateFromFile(Resolved);
    Info.ImgWidth := Info.Bitmap.Width;
    Info.ImgHeight := Info.Bitmap.Height;
    Result := TPixieImageHandle(Info);
  except
    Info.Free;
  end;

  // Native load failed — try libwebp for .webp files
  if (Result = 0) and
     (LowerCase(ExtractFileExt(Resolved)) = '.webp') then
    Result := LoadWebPFile(Resolved);
end;

function TPixieFmxCanvas.LoadImageFromStream(
  Stream: TStream): TPixieImageHandle;
var
  Info: TPixieFmxImage;
begin
  Result := 0;
  if (Stream = nil) or (Stream.Size = 0) then Exit;

  Info := TPixieFmxImage.Create;
  try
    Info.Bitmap := TBitmap.Create;
    Stream.Position := 0;
    Info.Bitmap.LoadFromStream(Stream);
    Info.ImgWidth := Info.Bitmap.Width;
    Info.ImgHeight := Info.Bitmap.Height;
    if (Info.ImgWidth = 0) or (Info.ImgHeight = 0) then
    begin
      Info.Free;
      Exit;
    end;
  except
    Info.Free;
    Exit;
  end;

  Result := TPixieImageHandle(Info);
end;

function TPixieFmxCanvas.LoadSvgFromData(Data: Pointer;
  Size: Integer): TPixieImageHandle;
var
  Info: TPixieFmxImage;
  Renderer: TPixieSvgCanvasRenderer;
  W, H: Single;
begin
  Result := 0;
  if (Data = nil) or (Size <= 0) then Exit;

  Renderer := TPixieSvgCanvasRenderer.Create(Self);
  if not Renderer.ParseSvg(Data, Size, W, H) then
  begin
    Renderer.Free;
    Exit;
  end;

  Info := TPixieFmxImage.Create;
  Info.SvgRenderer := Renderer;
  Info.ImgWidth := Round(W);
  Info.ImgHeight := Round(H);
  Info.AspectOnly := not Renderer.HasExplicitSize;
  Info.AspectRatio := Renderer.GetAspectRatio;
  Result := TPixieImageHandle(Info);
end;

function TPixieFmxCanvas.LoadImageFromPixels(Width, Height: Integer;
  Pixels: Pointer; Pitch: Integer): TPixieImageHandle;
var
  Info: TPixieFmxImage;
  MapData: TBitmapData;
  Y, X: Integer;
  Src, Dst: PByte;
  Tmp: Byte;
  NeedSwapRB: Boolean;
begin
  Result := 0;
  if (Width <= 0) or (Height <= 0) or (Pixels = nil) then Exit;

  Info := TPixieFmxImage.Create;
  Info.Bitmap := TBitmap.Create(Width, Height);
  Info.ImgWidth := Width;
  Info.ImgHeight := Height;

  if Info.Bitmap.Map(TMapAccess.Write, MapData) then
  try
    NeedSwapRB := MapData.PixelFormat in [TPixelFormat.RGBA,
      TPixelFormat.RGBA16];
    for Y := 0 to Height - 1 do
    begin
      Src := PByte(Pixels) + Y * Pitch;
      Dst := PByte(MapData.Data) + Y * MapData.Pitch;
      Move(Src^, Dst^, Width * 4);
      if NeedSwapRB then
      begin
        Dst := PByte(MapData.Data) + Y * MapData.Pitch;
        for X := 0 to Width - 1 do
        begin
          Tmp := Dst^; Dst^ := (Dst + 2)^; (Dst + 2)^ := Tmp;
          Inc(Dst, 4);
        end;
      end;
    end;
  finally
    Info.Bitmap.Unmap(MapData);
  end;

  Result := TPixieImageHandle(Info);
end;

procedure TPixieFmxCanvas.FreeImage(Handle: TPixieImageHandle);
begin
  if Handle = 0 then Exit;
  TPixieFmxImage(Handle).Free;
end;

procedure TPixieFmxCanvas.GetImageSize(Handle: TPixieImageHandle;
  out W, H: Single);
var
  Info: TPixieFmxImage;
begin
  W := 0;
  H := 0;
  if Handle = 0 then Exit;
  Info := TPixieFmxImage(Handle);
  W := Info.ImgWidth;
  H := Info.ImgHeight;
end;

function TPixieFmxCanvas.GetImageAspectInfo(Handle: TPixieImageHandle;
  out AspectRatio: Single): Boolean;
var
  Info: TPixieFmxImage;
begin
  AspectRatio := 0;
  Result := False;
  if Handle = 0 then Exit;
  Info := TPixieFmxImage(Handle);
  Result := Info.AspectOnly;
  if Result then
    AspectRatio := Info.AspectRatio;
end;

procedure TPixieFmxCanvas.DrawImage(Handle: TPixieImageHandle;
  DstX, DstY, DstW, DstH: Single);
var
  Info: TPixieFmxImage;
  SrcRect, DstRect: TRectF;
begin
  if (FCanvas = nil) or (Handle = 0) then Exit;
  Info := TPixieFmxImage(Handle);

  // SVG rendering via canvas path API
  if Info.SvgRenderer <> nil then
  begin
    TPixieSvgCanvasRenderer(Info.SvgRenderer).RenderToRect(
      DstX, DstY, DstW, DstH);
    Exit;
  end;

  if Info.Bitmap = nil then Exit;

  SrcRect := TRectF.Create(0, 0, Info.ImgWidth, Info.ImgHeight);
  DstRect := TRectF.Create(DstX, DstY, DstX + DstW, DstY + DstH);
  FCanvas.DrawBitmap(Info.Bitmap, SrcRect, DstRect, FOpacity);
end;

// ---------------------------------------------------------------------------
// Simple shapes
// ---------------------------------------------------------------------------

procedure TPixieFmxCanvas.FillEllipse(X, Y, W, H: Single;
  Color: TPixieWebColor);
begin
  if (FCanvas = nil) or (Color.Alpha = 0) then Exit;
  FBrush.Kind := TBrushKind.Solid;
  FBrush.Color := ToAlphaColor(Color);
  FCanvas.FillEllipse(TRectF.Create(X, Y, X + W, Y + H), FOpacity, FBrush);
end;

procedure TPixieFmxCanvas.DrawEllipse(X, Y, W, H: Single;
  Color: TPixieWebColor; StrokeWidth: Single);
begin
  if (FCanvas = nil) or (Color.Alpha = 0) then Exit;
  FStrokeBrush.Kind := TBrushKind.Solid;
  FStrokeBrush.Color := ToAlphaColor(Color);
  FStrokeBrush.Thickness := StrokeWidth;
  FStrokeBrush.Dash := TStrokeDash.Solid;
  FCanvas.DrawEllipse(TRectF.Create(X, Y, X + W, Y + H), FOpacity,
    FStrokeBrush);
end;

procedure TPixieFmxCanvas.DrawRect(X, Y, W, H: Single;
  Color: TPixieWebColor; StrokeWidth: Single);
begin
  if (FCanvas = nil) or (Color.Alpha = 0) then Exit;
  FStrokeBrush.Kind := TBrushKind.Solid;
  FStrokeBrush.Color := ToAlphaColor(Color);
  FStrokeBrush.Thickness := StrokeWidth;
  FStrokeBrush.Dash := TStrokeDash.Solid;
  FCanvas.DrawRect(TRectF.Create(X, Y, X + W, Y + H), 0, 0, AllCorners,
    FOpacity, FStrokeBrush);
end;

procedure TPixieFmxCanvas.DrawLine(X1, Y1, X2, Y2: Single;
  Color: TPixieWebColor; StrokeWidth: Single;
  Style: TPixieTextDecorationStyle);
begin
  if (FCanvas = nil) or (Color.Alpha = 0) then Exit;
  FStrokeBrush.Kind := TBrushKind.Solid;
  FStrokeBrush.Color := ToAlphaColor(Color);
  FStrokeBrush.Thickness := StrokeWidth;
  case Style of
    tdsDotted: FStrokeBrush.Dash := TStrokeDash.Dot;
    tdsDashed: FStrokeBrush.Dash := TStrokeDash.Dash;
  else
    FStrokeBrush.Dash := TStrokeDash.Solid;
  end;
  FCanvas.DrawLine(PointF(X1, Y1), PointF(X2, Y2), FOpacity, FStrokeBrush);
end;

procedure TPixieFmxCanvas.StrokePolyline(const Points: array of Single;
  Color: TPixieWebColor; StrokeWidth: Single);
var
  I, Count: Integer;
begin
  if (FCanvas = nil) or (Color.Alpha = 0) then Exit;
  Count := Length(Points) div 2;
  if Count < 2 then Exit;

  FPath.Clear;
  FPath.MoveTo(PointF(Points[0], Points[1]));
  for I := 1 to Count - 1 do
    FPath.LineTo(PointF(Points[I * 2], Points[I * 2 + 1]));

  FStrokeBrush.Kind := TBrushKind.Solid;
  FStrokeBrush.Color := ToAlphaColor(Color);
  FStrokeBrush.Thickness := StrokeWidth;
  FStrokeBrush.Dash := TStrokeDash.Solid;
  FCanvas.DrawPath(FPath, FOpacity, FStrokeBrush);
end;

// ---------------------------------------------------------------------------
// View / scale
// ---------------------------------------------------------------------------


// ---------------------------------------------------------------------------
// Path API
// ---------------------------------------------------------------------------

procedure TPixieFmxCanvas.BeginPath;
begin
  FCurrentPath.Clear;
end;

procedure TPixieFmxCanvas.MoveTo(X, Y: Single);
begin
  FCurrentPath.MoveTo(PointF(X, Y));
end;

procedure TPixieFmxCanvas.LineTo(X, Y: Single);
begin
  FCurrentPath.LineTo(PointF(X, Y));
end;

procedure TPixieFmxCanvas.CurveTo(X1, Y1, X2, Y2, X3, Y3: Single);
begin
  FCurrentPath.CurveTo(PointF(X1, Y1), PointF(X2, Y2), PointF(X3, Y3));
end;

procedure TPixieFmxCanvas.ClosePath;
begin
  FCurrentPath.ClosePath;
end;

procedure TPixieFmxCanvas.FillPath(Color: TPixieWebColor;
  FillRule: TPixieFillRule);
begin
  if FCanvas = nil then Exit;
  if Color.Alpha > 0 then
  begin
    FBrush.Kind := TBrushKind.Solid;
    FBrush.Color := ToAlphaColor(Color);
    FCanvas.FillPath(FCurrentPath, FOpacity, FBrush);
  end;
  FCurrentPath.Clear;
end;

procedure TPixieFmxCanvas.StrokePath(Color: TPixieWebColor;
  Width: Single);
begin
  if FCanvas = nil then Exit;
  if Color.Alpha > 0 then
  begin
    FStrokeBrush.Kind := TBrushKind.Solid;
    FStrokeBrush.Color := ToAlphaColor(Color);
    FStrokeBrush.Thickness := Width;
    ApplyDashPattern(Width);
    FStrokeBrush.Cap := CapMap[FPathLineCap];
    FStrokeBrush.Join := JoinMap[FPathLineJoin];
    FCanvas.DrawPath(FCurrentPath, FOpacity, FStrokeBrush);
  end;
  FCurrentPath.Clear;
end;

procedure TPixieFmxCanvas.FillAndStrokePath(FillColor: TPixieWebColor;
  StrokeColor: TPixieWebColor; StrokeWidth: Single;
  FillRule: TPixieFillRule);
begin
  if FCanvas = nil then Exit;
  if FillColor.Alpha > 0 then
  begin
    FBrush.Kind := TBrushKind.Solid;
    FBrush.Color := ToAlphaColor(FillColor);
    FCanvas.FillPath(FCurrentPath, FOpacity, FBrush);
  end;
  if StrokeColor.Alpha > 0 then
  begin
    FStrokeBrush.Kind := TBrushKind.Solid;
    FStrokeBrush.Color := ToAlphaColor(StrokeColor);
    FStrokeBrush.Thickness := StrokeWidth;
    ApplyDashPattern(StrokeWidth);
    FStrokeBrush.Cap := CapMap[FPathLineCap];
    FStrokeBrush.Join := JoinMap[FPathLineJoin];
    FCanvas.DrawPath(FCurrentPath, FOpacity, FStrokeBrush);
  end;
  FCurrentPath.Clear;
end;

procedure TPixieFmxCanvas.DiscardPath;
begin
  FCurrentPath.Clear;
end;

procedure TPixieFmxCanvas.ClipPath(FillRule: TPixieFillRule);
var
  R: TRectF;
begin
  if FCanvas = nil then Exit;
  R := FCurrentPath.GetBounds;
  FCanvas.IntersectClipRect(R);
  FCurrentPath.Clear;
end;

procedure TPixieFmxCanvas.FillPathLinearGradient(
  const Gradient: TPixieLinearGradientLayer;
  FillRule: TPixieFillRule);
var
  R: TRectF;
  RW, RH: Single;
begin
  if (FCanvas = nil) or (Gradient = nil) then Exit;
  if Gradient.ColorPoints.Count < 2 then
  begin
    FCurrentPath.Clear;
    Exit;
  end;

  // FMX FillPath maps gradient 0..1 relative to path bounding box
  R := FCurrentPath.GetBounds;
  RW := R.Width;
  RH := R.Height;
  if (RW <= 0) or (RH <= 0) then
  begin
    FCurrentPath.Clear;
    Exit;
  end;

  FBrush.Kind := TBrushKind.Gradient;
  FBrush.Gradient.Style := TGradientStyle.Linear;
  if Gradient.HasBrushTransform then
  begin
    // Normalised bbox coords map directly to FMX's 0-1 gradient positions
    FBrush.Gradient.StartPosition.X := Gradient.StartPt.X;
    FBrush.Gradient.StartPosition.Y := Gradient.StartPt.Y;
    FBrush.Gradient.StopPosition.X := Gradient.EndPt.X;
    FBrush.Gradient.StopPosition.Y := Gradient.EndPt.Y;
  end
  else
  begin
    FBrush.Gradient.StartPosition.X := (Gradient.StartPt.X - R.Left) / RW;
    FBrush.Gradient.StartPosition.Y := (Gradient.StartPt.Y - R.Top) / RH;
    FBrush.Gradient.StopPosition.X := (Gradient.EndPt.X - R.Left) / RW;
    FBrush.Gradient.StopPosition.Y := (Gradient.EndPt.Y - R.Top) / RH;
  end;
  SetupGradientStops(Gradient.ColorPoints);

  FCanvas.FillPath(FCurrentPath, FOpacity, FBrush);
  FCurrentPath.Clear;
end;

procedure TPixieFmxCanvas.FillPathRadialGradient(
  const Gradient: TPixieRadialGradientLayer;
  FillRule: TPixieFillRule);
var
  R: TRectF;
  I: Integer;
  GradPt: TGradientPoint;
begin
  if (FCanvas = nil) or (Gradient = nil) then Exit;
  if Gradient.ColorPoints.Count < 2 then
  begin
    FCurrentPath.Clear;
    Exit;
  end;

  R := FCurrentPath.GetBounds;
  if (R.Width <= 0) or (R.Height <= 0) then
  begin
    FCurrentPath.Clear;
    Exit;
  end;

  FBrush.Kind := TBrushKind.Gradient;
  FBrush.Gradient.Style := TGradientStyle.Radial;

  if Gradient.HasBrushTransform then
  begin
    // Normalised bbox coords map directly to FMX rotation center
    FBrush.Gradient.RadialTransform.RotationCenter.X := Gradient.Position.X;
    FBrush.Gradient.RadialTransform.RotationCenter.Y := Gradient.Position.Y;
  end
  else
  begin
    // FMX D2D sets gradient centre = (BBox.Width * RC.X, BBox.Height * RC.Y)
    // without adding BBox.Left/Top, so RC must use absolute user-space coords
    // divided by the bbox dimensions.
    FBrush.Gradient.RadialTransform.RotationCenter.X :=
      Gradient.Position.X / R.Width;
    FBrush.Gradient.RadialTransform.RotationCenter.Y :=
      Gradient.Position.Y / R.Height;
  end;
  FBrush.Gradient.RadialTransform.Scale.X := 1;
  FBrush.Gradient.RadialTransform.Scale.Y := 1;
  FBrush.Gradient.RadialTransform.RotationAngle := 0;

  // FMX internally reverses stop positions for radial gradients (its
  // convention is center=1, edge=0 while SVG/D2D use center=0, edge=1).
  // Map SVG offsets to FMX convention (1-offset) and iterate in reverse
  // to keep ascending order — FMX's boundary logic requires sorted stops.
  FBrush.Gradient.Points.Clear;
  for I := Gradient.ColorPoints.Count - 1 downto 0 do
  begin
    GradPt := TGradientPoint(FBrush.Gradient.Points.Add);
    GradPt.Offset := 1 - Gradient.ColorPoints[I].Offset;
    GradPt.Color := ToAlphaColor(Gradient.ColorPoints[I].Color);
  end;

  FCanvas.FillPath(FCurrentPath, FOpacity, FBrush);
  FCurrentPath.Clear;
end;

procedure TPixieFmxCanvas.StrokePathLinearGradient(
  const Gradient: TPixieLinearGradientLayer; Width: Single);
var
  R: TRectF;
  RW, RH: Single;
begin
  if (FCanvas = nil) or (Gradient = nil) then Exit;
  if Gradient.ColorPoints.Count < 2 then
  begin
    FCurrentPath.Clear;
    Exit;
  end;

  R := FCurrentPath.GetBounds;
  RW := R.Width;
  RH := R.Height;
  if (RW <= 0) or (RH <= 0) then
  begin
    FCurrentPath.Clear;
    Exit;
  end;

  FStrokeBrush.Kind := TBrushKind.Gradient;
  FStrokeBrush.Gradient.Style := TGradientStyle.Linear;
  FStrokeBrush.Gradient.StartPosition.X := (Gradient.StartPt.X - R.Left) / RW;
  FStrokeBrush.Gradient.StartPosition.Y := (Gradient.StartPt.Y - R.Top) / RH;
  FStrokeBrush.Gradient.StopPosition.X := (Gradient.EndPt.X - R.Left) / RW;
  FStrokeBrush.Gradient.StopPosition.Y := (Gradient.EndPt.Y - R.Top) / RH;
  SetupGradientStops(Gradient.ColorPoints, FStrokeBrush);
  FStrokeBrush.Thickness := Width;
  ApplyDashPattern(Width);
  FStrokeBrush.Cap := CapMap[FPathLineCap];
  FStrokeBrush.Join := JoinMap[FPathLineJoin];

  FCanvas.DrawPath(FCurrentPath, FOpacity, FStrokeBrush);
  FCurrentPath.Clear;
end;

procedure TPixieFmxCanvas.StrokePathRadialGradient(
  const Gradient: TPixieRadialGradientLayer; Width: Single);
var
  R: TRectF;
  I: Integer;
  GradPt: TGradientPoint;
begin
  if (FCanvas = nil) or (Gradient = nil) then Exit;
  if Gradient.ColorPoints.Count < 2 then
  begin
    FCurrentPath.Clear;
    Exit;
  end;

  R := FCurrentPath.GetBounds;
  if (R.Width <= 0) or (R.Height <= 0) then
  begin
    FCurrentPath.Clear;
    Exit;
  end;

  FStrokeBrush.Kind := TBrushKind.Gradient;
  FStrokeBrush.Gradient.Style := TGradientStyle.Radial;

  // Same centre formula as FillPathRadialGradient — absolute coords / bbox size
  FStrokeBrush.Gradient.RadialTransform.RotationCenter.X :=
    Gradient.Position.X / R.Width;
  FStrokeBrush.Gradient.RadialTransform.RotationCenter.Y :=
    Gradient.Position.Y / R.Height;
  FStrokeBrush.Gradient.RadialTransform.Scale.X := 1;
  FStrokeBrush.Gradient.RadialTransform.Scale.Y := 1;
  FStrokeBrush.Gradient.RadialTransform.RotationAngle := 0;

  // Reverse stops in descending order for ascending FMX offsets
  FStrokeBrush.Gradient.Points.Clear;
  for I := Gradient.ColorPoints.Count - 1 downto 0 do
  begin
    GradPt := TGradientPoint(FStrokeBrush.Gradient.Points.Add);
    GradPt.Offset := 1 - Gradient.ColorPoints[I].Offset;
    GradPt.Color := ToAlphaColor(Gradient.ColorPoints[I].Color);
  end;

  FStrokeBrush.Thickness := Width;
  ApplyDashPattern(Width);
  FStrokeBrush.Cap := CapMap[FPathLineCap];
  FStrokeBrush.Join := JoinMap[FPathLineJoin];

  FCanvas.DrawPath(FCurrentPath, FOpacity, FStrokeBrush);
  FCurrentPath.Clear;
end;

procedure TPixieFmxCanvas.ConcatMatrix(A, B, C, D, E, F: Single);
var
  M: TMatrix;
begin
  if FCanvas = nil then Exit;
  M.m11 := A; M.m12 := B; M.m13 := 0;
  M.m21 := C; M.m22 := D; M.m23 := 0;
  M.m31 := E; M.m32 := F; M.m33 := 1;
  FCanvas.MultiplyMatrix(M);
end;

procedure TPixieFmxCanvas.BeginOffscreen(Width, Height: Integer;
  ClearColor: TPixieWebColor);
begin
  if FOffscreenBitmap <> nil then
    EndOffscreen;
  FOffscreenSavedCanvas := FCanvas;
  FOffscreenWidth := Width;
  FOffscreenHeight := Height;
  FOffscreenBitmap := TBitmap.Create(Width, Height);
  FOffscreenBitmap.Clear(ToAlphaColor(ClearColor));
  FCanvas := FOffscreenBitmap.Canvas;
  FOpacity := 1.0;
  FOpacityTop := 0;
  FStateTop := 0;
  FCanvas.BeginScene;
  FOffscreenScene := True;
end;

procedure TPixieFmxCanvas.EndOffscreen;
begin
  if FOffscreenScene and (FCanvas <> nil) then
  begin
    FCanvas.EndScene;
    FOffscreenScene := False;
  end;
  FCanvas := FOffscreenSavedCanvas;
  FOffscreenSavedCanvas := nil;
  if FOffscreenBitmap <> nil then
  begin
    FOffscreenBitmap.Free;
    FOffscreenBitmap := nil;
  end;
end;

procedure TPixieFmxCanvas.FlushOffscreen;
begin
  if FOffscreenScene and (FCanvas <> nil) then
  begin
    FCanvas.EndScene;
    FOffscreenScene := False;
  end;
end;

procedure TPixieFmxCanvas.SaveAsPng(Stream: TStream);
begin
  if FOffscreenBitmap = nil then Exit;
  FlushOffscreen;
  FOffscreenBitmap.SaveToStream(Stream);
end;

procedure TPixieFmxCanvas.SaveAsPng(const FileName: string);
begin
  if FOffscreenBitmap = nil then Exit;
  FlushOffscreen;
  FOffscreenBitmap.SaveToFile(FileName);
end;

procedure TPixieFmxCanvas.SaveAsBmp(Stream: TStream);
var
  Data: TBitmapData;
begin
  if FOffscreenBitmap = nil then Exit;
  FlushOffscreen;
  if FOffscreenBitmap.Map(TMapAccess.Read, Data) then
  try
    WriteBmpStream(Stream, Data.Data, FOffscreenWidth, FOffscreenHeight,
      Data.Pitch);
  finally
    FOffscreenBitmap.Unmap(Data);
  end;
end;

end.
