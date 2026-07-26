unit Pixie.SvgRenderer.Canvas;

// SVG renderer that draws through TPixieCanvas.
// Inherits SVG parsing from TPixieSvgRendererBase and overrides abstract
// drawing primitives to render via the canvas path API, giving native
// vector rendering on all backends (D2D, Cairo, CG, Qt, FMX).

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Math, Generics.Collections,
  Pixie.Types, Pixie.WebColor, Pixie.FontDescription,
  Pixie.GradientLayer, Pixie.Borders, Pixie.Html,
  Pixie.Canvas, Pixie.SvgRenderer;

type
  { TPixieSvgCanvasRenderer }

  TPixieSvgCanvasRenderer = class(TPixieSvgRendererBase)
  private
    FCanvas: TPixieCanvas;
    FFontHandle: TPixieFontHandle;
    FFontMetrics: TPixieFontMetrics;
    FFontFamily: string;
    FFontSize: Single;
    FFontWeight: Integer;
    FFontItalic: Boolean;

    // Bounding box of the current path (for gradient coordinate mapping)
    FBBoxMinX, FBBoxMinY, FBBoxMaxX, FBBoxMaxY: Single;
    FBBoxValid: Boolean;

    // Image cache for <image> elements (freed on ClearDocument)
    FImageCache: TDictionary<string, TPixieImageHandle>;
    FPatternDepth: Integer;

    procedure UpdateBBox(X, Y: Single);
    procedure ResetBBox;
    procedure FillWithGradient(const State: TPixieSvgState;
      FillRule: TPixieFillRule);
    procedure StrokeWithGradient(const State: TPixieSvgState);
    procedure PopulateStops(Layer: TPixieGradientBase;
      const Grad: TPixieSvgGradient; Opacity: Single;
      const State: TPixieSvgState);
    procedure SetupLinearGradientLayer(
      Layer: TPixieLinearGradientLayer;
      const Grad: TPixieSvgGradient;
      const StartPt, EndPt: TPixiePointF;
      BX, BY, BW, BH: Single;
      Opacity: Single; const State: TPixieSvgState);
    procedure ReplayPath;
    procedure RebuildAndFill(const State: TPixieSvgState);
    procedure RebuildAndStroke(const State: TPixieSvgState);
    procedure RebuildAndStrokeGradient(const State: TPixieSvgState);
    function LoadImageFromHref(const Href: string): TPixieImageHandle;
    procedure FreeImageCache;
    procedure FillWithPattern(const State: TPixieSvgState;
      FillRule: TPixieFillRule);
    procedure RenderPatternChildren(PatternNode: Pointer);

    // Path recording — only active when gradient fill + stroke needs replay
    type
      TPathOp = (poMoveTo, poLineTo, poCurveTo, poClosePath);
      TPathEntry = record
        Op: TPathOp;
        X, Y, X2, Y2, X3, Y3: Single;
      end;
      TPathEntryList = TList<TPathEntry>;
    var
      FPathRecord: TPathEntryList;
  protected
    procedure DoMoveTo(X, Y: Single); override;
    procedure DoLineTo(X, Y: Single); override;
    procedure DoCurveTo(X1, Y1, X2, Y2, X3, Y3: Single); override;
    procedure DoClosePath; override;
    procedure DoSaveState; override;
    procedure DoRestoreState; override;
    procedure DoSetTransform(const M: TPixieSvgMatrix); override;
    procedure DoFillAndStroke(const State: TPixieSvgState); override;
    procedure DoBeginOpacity(Opacity: Single); override;
    procedure DoEndOpacity; override;
    procedure DoClipPath(EvenOdd: Boolean); override;
    procedure DoBeginMask(const MaskImageHref: string;
      MaskX, MaskY, MaskW, MaskH: Single); override;
    procedure DoEndMask; override;
    function ResolveGradientFirstColor(const Id: string): TPixieWebColor;
    procedure DoDrawText(const Text: string; X, Y: Single;
      const State: TPixieSvgState); override;
    function DoMeasureTextRun(const Text: string;
      const State: TPixieSvgState): Single; override;
    procedure DoDrawImage(const Href: string;
      X, Y, W, H: Single); override;
    procedure DoClearImages; override;
  private
    procedure EnsureFont(const State: TPixieSvgState);
  public
    constructor Create(ACanvas: TPixieCanvas);
    destructor Destroy; override;
    procedure ClearDocument; override;

    // Render SVG into a destination rectangle, handling viewBox transform
    procedure RenderToRect(DstX, DstY, DstW, DstH: Single);
  end;

implementation

uses
  Pixie.SimpleXml, Pixie.DataUri, Pixie.Utf8
  {$IFDEF FPC}, FPImage, FPReadPNG, FPReadJPEG, FPReadBMP, FPReadGIF,
  Pixie.ImageUtils{$ENDIF};

// ===========================================================================
// Construction
// ===========================================================================

constructor TPixieSvgCanvasRenderer.Create(ACanvas: TPixieCanvas);
begin
  inherited Create;
  FCanvas := ACanvas;
  FFontHandle := 0;
  FFontFamily := '';
  FFontSize := 0;
  FFontWeight := 0;
  FBBoxValid := False;
  FPathRecord := TPathEntryList.Create;
end;

destructor TPixieSvgCanvasRenderer.Destroy;
begin
  if (FFontHandle <> 0) and (FCanvas <> nil) then
    FCanvas.DeleteFont(FFontHandle);
  // Inherited Destroy runs ClearDocument, which now virtually dispatches
  // to our override and touches FPathRecord — so free the record AFTER.
  inherited;
  FPathRecord.Free;
end;

procedure TPixieSvgCanvasRenderer.ClearDocument;
begin
  inherited;
  // Reset per-shape state in case the renderer is reused to parse a new
  // SVG (as TPixieSvgView does). Any leftover entries would pollute the
  // first shape's stroke rebuild in the new document.
  FPathRecord.Clear;
  ResetBBox;
end;

// ===========================================================================
// Bounding box helpers
// ===========================================================================

procedure TPixieSvgCanvasRenderer.UpdateBBox(X, Y: Single);
begin
  if not FBBoxValid then
  begin
    FBBoxMinX := X; FBBoxMinY := Y;
    FBBoxMaxX := X; FBBoxMaxY := Y;
    FBBoxValid := True;
  end
  else
  begin
    if X < FBBoxMinX then FBBoxMinX := X;
    if Y < FBBoxMinY then FBBoxMinY := Y;
    if X > FBBoxMaxX then FBBoxMaxX := X;
    if Y > FBBoxMaxY then FBBoxMaxY := Y;
  end;
end;

procedure TPixieSvgCanvasRenderer.ResetBBox;
begin
  FBBoxValid := False;
  FBBoxMinX := 0; FBBoxMinY := 0;
  FBBoxMaxX := 0; FBBoxMaxY := 0;
end;

// ===========================================================================
// Drawing primitives — path construction
// ===========================================================================

procedure TPixieSvgCanvasRenderer.DoMoveTo(X, Y: Single);
var
  Entry: TPathEntry;
begin
  FCanvas.MoveTo(X, Y);
  UpdateBBox(X, Y);
  Entry.Op := poMoveTo;
  Entry.X := X; Entry.Y := Y;
  FPathRecord.Add(Entry);
end;

procedure TPixieSvgCanvasRenderer.DoLineTo(X, Y: Single);
var
  Entry: TPathEntry;
begin
  FCanvas.LineTo(X, Y);
  UpdateBBox(X, Y);
  Entry.Op := poLineTo;
  Entry.X := X; Entry.Y := Y;
  FPathRecord.Add(Entry);
end;

procedure TPixieSvgCanvasRenderer.DoCurveTo(X1, Y1, X2, Y2,
  X3, Y3: Single);
var
  Entry: TPathEntry;
begin
  FCanvas.CurveTo(X1, Y1, X2, Y2, X3, Y3);
  UpdateBBox(X1, Y1);
  UpdateBBox(X2, Y2);
  UpdateBBox(X3, Y3);
  Entry.Op := poCurveTo;
  Entry.X := X1; Entry.Y := Y1;
  Entry.X2 := X2; Entry.Y2 := Y2;
  Entry.X3 := X3; Entry.Y3 := Y3;
  FPathRecord.Add(Entry);
end;

procedure TPixieSvgCanvasRenderer.DoClosePath;
var
  Entry: TPathEntry;
begin
  FCanvas.ClosePath;
  Entry.Op := poClosePath;
  FPathRecord.Add(Entry);
end;

// ===========================================================================
// State management
// ===========================================================================

procedure TPixieSvgCanvasRenderer.DoSaveState;
begin
  FCanvas.SaveState;
end;

procedure TPixieSvgCanvasRenderer.DoRestoreState;
begin
  FCanvas.RestoreState;
end;

procedure TPixieSvgCanvasRenderer.DoSetTransform(
  const M: TPixieSvgMatrix);
begin
  FCanvas.ConcatMatrix(M.A, M.B, M.C, M.D, M.E, M.F);
end;

procedure TPixieSvgCanvasRenderer.PopulateStops(Layer: TPixieGradientBase;
  const Grad: TPixieSvgGradient; Opacity: Single;
  const State: TPixieSvgState);
var
  I: Integer;
  Stop: TPixieSvgGradientStop;
  CP: TPixieColorPoint;
begin
  for I := 0 to Grad.Stops.Count - 1 do
  begin
    Stop := Grad.Stops[I];
    CP := TPixieColorPoint.Create(Stop.Offset, Stop.Color);
    CP.Color.Alpha := Round(CP.Color.Alpha * Opacity);
    Layer.ColorPoints.Add(CP);
  end;
end;

// Set up a linear gradient layer's axis and stops, expanding for
// spreadMethod=repeat|reflect by replicating the stops across enough
// cycles to cover the path bbox and extending the axis endpoints to
// match. With smPad (the default), behaves like PopulateStops.
procedure TPixieSvgCanvasRenderer.SetupLinearGradientLayer(
  Layer: TPixieLinearGradientLayer;
  const Grad: TPixieSvgGradient;
  const StartPt, EndPt: TPixiePointF;
  BX, BY, BW, BH: Single;
  Opacity: Single; const State: TPixieSvgState);
const
  // Cap on cycles to keep stop counts sane when the gradient axis is
  // tiny relative to the path (e.g. a 2px gradient on a 2000px path).
  SpreadMaxCycles = 256;
var
  DX, DY, LenSq, InvCycles: Single;
  TMin, TMax, BBoxCenter: Single;
  KLow, KHigh, K, I, StopCount, Cycles: Integer;
  Stop: TPixieSvgGradientStop;
  CP: TPixieColorPoint;
  CycleOffset: Single;

  procedure ProjectCorner(CX, CY: Single);
  var
    T: Single;
  begin
    T := ((CX - StartPt.X) * DX + (CY - StartPt.Y) * DY) / LenSq;
    if T < TMin then TMin := T;
    if T > TMax then TMax := T;
  end;

  procedure UsePadFallback;
  begin
    Layer.StartPt := StartPt;
    Layer.EndPt := EndPt;
    PopulateStops(Layer, Grad, Opacity, State);
  end;

begin
  DX := EndPt.X - StartPt.X;
  DY := EndPt.Y - StartPt.Y;
  LenSq := DX * DX + DY * DY;

  if (not Grad.HasSpread) or (Grad.Spread = smPad)
    or (Grad.Stops.Count < 2) or (LenSq < 1e-9) then
  begin
    UsePadFallback;
    Exit;
  end;

  TMin := 0; TMax := 1;
  ProjectCorner(BX,        BY);
  ProjectCorner(BX + BW,   BY);
  ProjectCorner(BX,        BY + BH);
  ProjectCorner(BX + BW,   BY + BH);

  KLow  := Floor(TMin);
  KHigh := Ceil(TMax);
  if KHigh <= KLow then KHigh := KLow + 1;
  Cycles := KHigh - KLow;
  if Cycles > SpreadMaxCycles then
  begin
    // Centre the cycle window on the bbox so the visible region still
    // gets the gradient — clamping to a fixed -32..32 window would
    // leave the path entirely outside if the bbox projects far away.
    BBoxCenter := (TMin + TMax) * 0.5;
    KLow  := Floor(BBoxCenter) - SpreadMaxCycles div 2;
    KHigh := KLow + SpreadMaxCycles;
    Cycles := SpreadMaxCycles;
  end;

  Layer.StartPt := TPixiePointF.Create(
    StartPt.X + KLow  * DX, StartPt.Y + KLow  * DY);
  Layer.EndPt := TPixiePointF.Create(
    StartPt.X + KHigh * DX, StartPt.Y + KHigh * DY);

  StopCount := Grad.Stops.Count;
  InvCycles := 1.0 / Cycles;
  Layer.ColorPoints.Capacity :=
    Layer.ColorPoints.Count + Cycles * StopCount;

  for K := 0 to Cycles - 1 do
  begin
    CycleOffset := K * InvCycles;
    if (Grad.Spread = smReflect) and (((K + KLow) and 1) <> 0) then
    begin
      // Mirrored cycle — walk stops in reverse, mirror offsets
      for I := StopCount - 1 downto 0 do
      begin
        Stop := Grad.Stops[I];
        CP := TPixieColorPoint.Create(
          CycleOffset + (1 - Stop.Offset) * InvCycles, Stop.Color);
        CP.Color.Alpha := Round(CP.Color.Alpha * Opacity);
        Layer.ColorPoints.Add(CP);
      end;
    end
    else
    begin
      for I := 0 to StopCount - 1 do
      begin
        Stop := Grad.Stops[I];
        CP := TPixieColorPoint.Create(
          CycleOffset + Stop.Offset * InvCycles, Stop.Color);
        CP.Color.Alpha := Round(CP.Color.Alpha * Opacity);
        Layer.ColorPoints.Add(CP);
      end;
    end;
  end;
end;

// ===========================================================================
// Gradient fill via clip-then-fill
// ===========================================================================

procedure TPixieSvgCanvasRenderer.FillWithGradient(
  const State: TPixieSvgState; FillRule: TPixieFillRule);
var
  Grad: TPixieSvgGradient;
  GradLayer: TPixieLinearGradientLayer;
  RadLayer: TPixieRadialGradientLayer;
  BX, BY, BW, BH: Single;
  GX1, GY1, GX2, GY2: Single;
  GCX, GCY, GRX, GRY: Single;
  M: TPixieSvgMatrix;
  HasTransform: Boolean;

  procedure TransformPt(var X, Y: Single);
  var
    TX, TY: Single;
  begin
    TX := M.A * X + M.C * Y + M.E;
    TY := M.B * X + M.D * Y + M.F;
    X := TX; Y := TY;
  end;

begin
  if State.FillGradientId = '' then Exit;
  Grad := ResolveGradientStops(State.FillGradientId);
  if (Grad = nil) or (Grad.Stops.Count < 2) then Exit;

  if not FBBoxValid then Exit;
  BX := FBBoxMinX;
  BY := FBBoxMinY;
  BW := FBBoxMaxX - FBBoxMinX;
  BH := FBBoxMaxY - FBBoxMinY;
  if (BW < 0.001) or (BH < 0.001) then Exit;

  // Parse gradientTransform
  HasTransform := Grad.GradientTransform <> '';
  if HasTransform then
    M := ParseTransform(Grad.GradientTransform);

  if not Grad.IsRadial then
  begin
    // Linear gradient — fill path directly with gradient brush
    GradLayer := TPixieLinearGradientLayer.Create;
    try
      if Grad.UserSpaceUnits then
      begin
        GX1 := Grad.X1; GY1 := Grad.Y1;
        GX2 := Grad.X2; GY2 := Grad.Y2;
        GradLayer.HasBrushTransform := False;
      end
      else
      begin
        // objectBoundingBox: keep gradient in normalised 0-1 bbox space
        // and use a brush transform to map to user space. This preserves
        // the gradient direction in bbox space per the SVG spec.
        GX1 := Grad.X1; GY1 := Grad.Y1;
        GX2 := Grad.X2; GY2 := Grad.Y2;
        GradLayer.HasBrushTransform := True;
        GradLayer.BrushTransform.M11 := BW;
        GradLayer.BrushTransform.M12 := 0;
        GradLayer.BrushTransform.M21 := 0;
        GradLayer.BrushTransform.M22 := BH;
        GradLayer.BrushTransform.DX := BX;
        GradLayer.BrushTransform.DY := BY;
      end;

      if HasTransform then
      begin
        TransformPt(GX1, GY1);
        TransformPt(GX2, GY2);
      end;

      SetupLinearGradientLayer(GradLayer, Grad,
        TPixiePointF.Create(GX1, GY1), TPixiePointF.Create(GX2, GY2),
        BX, BY, BW, BH, State.FillOpacity, State);
      FCanvas.FillPathLinearGradient(GradLayer, FillRule);
    finally
      GradLayer.Free;
    end;
  end
  else
  begin
    // Radial gradient
    RadLayer := TPixieRadialGradientLayer.Create;
    try
      if Grad.UserSpaceUnits then
      begin
        GCX := Grad.CX; GCY := Grad.CY;
        GRX := Grad.R; GRY := Grad.R;
        RadLayer.HasBrushTransform := False;
      end
      else
      begin
        // objectBoundingBox: normalised coordinates + brush transform
        GCX := Grad.CX; GCY := Grad.CY;
        GRX := Grad.R; GRY := Grad.R;
        RadLayer.HasBrushTransform := True;
        RadLayer.BrushTransform.M11 := BW;
        RadLayer.BrushTransform.M12 := 0;
        RadLayer.BrushTransform.M21 := 0;
        RadLayer.BrushTransform.M22 := BH;
        RadLayer.BrushTransform.DX := BX;
        RadLayer.BrushTransform.DY := BY;
      end;

      // Apply gradientTransform: transform center and compute
      // elliptical radii from the axis vectors
      if HasTransform then
      begin
        TransformPt(GCX, GCY);
        GRX := GRX * Sqrt(M.A * M.A + M.B * M.B);
        GRY := GRY * Sqrt(M.C * M.C + M.D * M.D);
      end;

      RadLayer.Position := TPixiePointF.Create(GCX, GCY);
      RadLayer.Radius := TPixiePointF.Create(GRX, GRY);
      PopulateStops(RadLayer, Grad, State.FillOpacity, State);
      FCanvas.FillPathRadialGradient(RadLayer, FillRule);
    finally
      RadLayer.Free;
    end;
  end;
end;

procedure TPixieSvgCanvasRenderer.StrokeWithGradient(
  const State: TPixieSvgState);
var
  Grad: TPixieSvgGradient;
  GradLayer: TPixieLinearGradientLayer;
  RadLayer: TPixieRadialGradientLayer;
  BX, BY, BW, BH: Single;
  GX1, GY1, GX2, GY2: Single;
  GCX, GCY, GRX, GRY: Single;
  M: TPixieSvgMatrix;
  HasTransform: Boolean;

  procedure TransformPt(var X, Y: Single);
  var
    TX, TY: Single;
  begin
    TX := M.A * X + M.C * Y + M.E;
    TY := M.B * X + M.D * Y + M.F;
    X := TX; Y := TY;
  end;

begin
  if State.StrokeGradientId = '' then Exit;
  Grad := ResolveGradientStops(State.StrokeGradientId);
  if (Grad = nil) or (Grad.Stops.Count < 2) then Exit;

  if not FBBoxValid then Exit;
  BX := FBBoxMinX;
  BY := FBBoxMinY;
  BW := FBBoxMaxX - FBBoxMinX;
  BH := FBBoxMaxY - FBBoxMinY;
  if (BW < 0.001) or (BH < 0.001) then Exit;

  HasTransform := Grad.GradientTransform <> '';
  if HasTransform then
    M := ParseTransform(Grad.GradientTransform);

  if not Grad.IsRadial then
  begin
    GradLayer := TPixieLinearGradientLayer.Create;
    try
      if Grad.UserSpaceUnits then
      begin
        GX1 := Grad.X1; GY1 := Grad.Y1;
        GX2 := Grad.X2; GY2 := Grad.Y2;
      end
      else
      begin
        GX1 := BX + Grad.X1 * BW; GY1 := BY + Grad.Y1 * BH;
        GX2 := BX + Grad.X2 * BW; GY2 := BY + Grad.Y2 * BH;
      end;
      if HasTransform then
      begin
        TransformPt(GX1, GY1);
        TransformPt(GX2, GY2);
      end;
      SetupLinearGradientLayer(GradLayer, Grad,
        TPixiePointF.Create(GX1, GY1), TPixiePointF.Create(GX2, GY2),
        BX, BY, BW, BH, State.StrokeOpacity, State);
      FCanvas.StrokePathLinearGradient(GradLayer, State.StrokeWidth);
    finally
      GradLayer.Free;
    end;
  end
  else
  begin
    RadLayer := TPixieRadialGradientLayer.Create;
    try
      if Grad.UserSpaceUnits then
      begin
        GCX := Grad.CX; GCY := Grad.CY;
        GRX := Grad.R; GRY := Grad.R;
      end
      else
      begin
        GCX := BX + Grad.CX * BW; GCY := BY + Grad.CY * BH;
        GRX := Grad.R * BW; GRY := Grad.R * BH;
      end;
      if HasTransform then
      begin
        TransformPt(GCX, GCY);
        GRX := GRX * Sqrt(M.A * M.A + M.B * M.B);
        GRY := GRY * Sqrt(M.C * M.C + M.D * M.D);
      end;
      RadLayer.Position := TPixiePointF.Create(GCX, GCY);
      RadLayer.Radius := TPixiePointF.Create(GRX, GRY);
      PopulateStops(RadLayer, Grad, State.StrokeOpacity, State);
      FCanvas.StrokePathRadialGradient(RadLayer, State.StrokeWidth);
    finally
      RadLayer.Free;
    end;
  end;
end;

procedure TPixieSvgCanvasRenderer.ReplayPath;
var
  I: Integer;
  Entry: TPathEntry;
begin
  for I := 0 to FPathRecord.Count - 1 do
  begin
    Entry := FPathRecord[I];
    case Entry.Op of
      poMoveTo: FCanvas.MoveTo(Entry.X, Entry.Y);
      poLineTo: FCanvas.LineTo(Entry.X, Entry.Y);
      poCurveTo: FCanvas.CurveTo(Entry.X, Entry.Y,
                   Entry.X2, Entry.Y2, Entry.X3, Entry.Y3);
      poClosePath: FCanvas.ClosePath;
    end;
  end;
end;

procedure TPixieSvgCanvasRenderer.RebuildAndFill(
  const State: TPixieSvgState);
var
  FC: TPixieWebColor;
  FR: TPixieFillRule;
begin
  ReplayPath;
  FC := State.FillColor;
  FC.Alpha := Round(FC.Alpha * State.FillOpacity);
  if State.EvenOddFill then FR := frEvenOdd else FR := frNonZero;
  FCanvas.FillPath(FC, FR);
end;

procedure TPixieSvgCanvasRenderer.RebuildAndStroke(
  const State: TPixieSvgState);
var
  SC: TPixieWebColor;
begin
  ReplayPath;
  SC := State.StrokeColor;
  SC.Alpha := Round(SC.Alpha * State.StrokeOpacity);
  FCanvas.StrokePath(SC, State.StrokeWidth);
end;

procedure TPixieSvgCanvasRenderer.RebuildAndStrokeGradient(
  const State: TPixieSvgState);
begin
  ReplayPath;
  StrokeWithGradient(State);
end;

// ===========================================================================
// Fill and stroke
// ===========================================================================

procedure TPixieSvgCanvasRenderer.DoFillAndStroke(
  const State: TPixieSvgState);
var
  FC, SC: TPixieWebColor;
  HasGradientFill, HasGradientStroke, SkipFill, BlendSet: Boolean;
  FR: TPixieFillRule;
begin
  // Set line cap/join and dash style for this stroke operation
  if State.HasStroke then
  begin
    FCanvas.SetPathStrokeStyle(State.LineCap, State.LineJoin);
    if Length(State.DashArray) > 0 then
      FCanvas.SetPathDashStyle(State.DashArray, State.DashOffset);
  end;

  SkipFill := False;
  BlendSet := False;
  if State.BlendMode <> bmNormal then
  begin
    BlendSet := FCanvas.SetBlendMode(State.BlendMode);
    if not BlendSet then
      SkipFill := True;
  end;

  HasGradientFill := (State.FillGradientId <> '') and not SkipFill;
  HasGradientStroke := State.HasStroke and (State.StrokeGradientId <> '');
  if State.EvenOddFill then
    FR := frEvenOdd
  else
    FR := frNonZero;

  if HasGradientFill and IsPatternFill(State.FillGradientId) then
  begin
    FillWithPattern(State, FR);
    if State.HasStroke then
    begin
      if HasGradientStroke then
        RebuildAndStrokeGradient(State)
      else
        RebuildAndStroke(State);
    end;
  end
  else if HasGradientFill then
  begin
    FillWithGradient(State, FR);
    if State.HasStroke then
    begin
      if HasGradientStroke then
        RebuildAndStrokeGradient(State)
      else
        RebuildAndStroke(State);
    end;
  end
  else if State.HasFill and not SkipFill then
  begin
    FC := State.FillColor;
    FC.Alpha := Round(FC.Alpha * State.FillOpacity);
    if State.HasStroke and not HasGradientStroke then
    begin
      SC := State.StrokeColor;
      SC.Alpha := Round(SC.Alpha * State.StrokeOpacity);
      if State.StrokeBeforeFill then
      begin
        // paint-order: stroke first, then fill on top (covers inner half)
        FCanvas.StrokePath(SC, State.StrokeWidth);
        RebuildAndFill(State);
      end
      else
        FCanvas.FillAndStrokePath(FC, SC, State.StrokeWidth, FR);
    end
    else
    begin
      FCanvas.FillPath(FC, FR);
      if HasGradientStroke then
        RebuildAndStrokeGradient(State);
    end;
  end
  else if HasGradientStroke then
    StrokeWithGradient(State)
  else if State.HasStroke then
  begin
    SC := State.StrokeColor;
    SC.Alpha := Round(SC.Alpha * State.StrokeOpacity);
    FCanvas.StrokePath(SC, State.StrokeWidth);
  end
  else
    FCanvas.DiscardPath;

  if BlendSet then
    FCanvas.ResetBlendMode;

  // Reset stroke style to defaults
  FCanvas.SetPathStrokeStyle(lcButt, ljMiter);
  FCanvas.ClearPathDashStyle;

  ResetBBox;
  FPathRecord.Clear;
end;

// ===========================================================================
// Opacity
// ===========================================================================

procedure TPixieSvgCanvasRenderer.DoBeginOpacity(Opacity: Single);
begin
  FCanvas.PushOpacity(Opacity);
end;

procedure TPixieSvgCanvasRenderer.DoEndOpacity;
begin
  FCanvas.PopOpacity;
end;

function TPixieSvgCanvasRenderer.ResolveGradientFirstColor(
  const Id: string): TPixieWebColor;
var
  Grad: TPixieSvgGradient;
begin
  Result := TPixieWebColor.Create(0, 0, 0, 0);
  Grad := ResolveGradientStops(Id);
  if (Grad <> nil) and (Grad.Stops <> nil) and (Grad.Stops.Count > 0) then
    Result := Grad.Stops[0].Color;
end;

procedure TPixieSvgCanvasRenderer.DoBeginMask(const MaskImageHref: string;
  MaskX, MaskY, MaskW, MaskH: Single);
var
  Handle: TPixieImageHandle;
begin
  Handle := LoadImageFromHref(MaskImageHref);
  if Handle = 0 then Exit;
  FCanvas.PushMask(Handle, MaskX, MaskY, MaskW, MaskH);
end;

procedure TPixieSvgCanvasRenderer.DoEndMask;
begin
  FCanvas.PopMask;
end;

procedure TPixieSvgCanvasRenderer.DoClipPath(EvenOdd: Boolean);
begin
  if EvenOdd then
    FCanvas.ClipPath(frEvenOdd)
  else
    FCanvas.ClipPath(frNonZero);
  // The clip path's geometry belonged to the clip, not to the shape that
  // will emit its own path next. Reset so the subsequent stroke rebuild
  // (for pattern/gradient fills) sees only the shape's own geometry.
  FPathRecord.Clear;
  ResetBBox;
end;

// ===========================================================================
// Text
// ===========================================================================

procedure TPixieSvgCanvasRenderer.EnsureFont(const State: TPixieSvgState);
var
  Desc: TPixieFontDescription;
begin
  if (FFontHandle <> 0) and (FFontFamily = State.FontFamily) and
     (Abs(FFontSize - State.FontSize) <= 0.01) and
     (FFontWeight = State.FontWeight) and
     (FFontItalic = State.FontItalic) then Exit;

  if FFontHandle <> 0 then
    FCanvas.DeleteFont(FFontHandle);
  Desc.Init;
  Desc.Family := State.FontFamily;
  Desc.Size := State.FontSize;
  Desc.Weight := State.FontWeight;
  if State.FontItalic then
    Desc.Style := fstItalic;
  FFontHandle := FCanvas.CreateFont(Desc, FFontMetrics);
  FFontFamily := State.FontFamily;
  FFontSize := State.FontSize;
  FFontWeight := State.FontWeight;
  FFontItalic := State.FontItalic;
end;

function TPixieSvgCanvasRenderer.DoMeasureTextRun(const Text: string;
  const State: TPixieSvgState): Single;
var
  I, CharCount: Integer;
begin
  EnsureFont(State);
  if FFontHandle = 0 then
  begin
    Result := 0;
    Exit;
  end;
  Result := FCanvas.MeasureText(Text, FFontHandle);
  if State.LetterSpacing <> 0 then
  begin
    // Count UTF-8 characters
    CharCount := 0;
    I := 1;
    while I <= Length(Text) do
    begin
      ReadUtf8Char(Text, I);
      Inc(CharCount);
    end;
    if CharCount > 1 then
      Result := Result + State.LetterSpacing * (CharCount - 1);
  end;
end;

procedure TPixieSvgCanvasRenderer.DoDrawText(const Text: string;
  X, Y: Single; const State: TPixieSvgState);

  procedure DrawRun(const S: string; RunX: Single;
    DoFill, DoStroke, StrokeFirst: Boolean;
    const FC, SC: TPixieWebColor);
  begin
    if DoFill and DoStroke then
    begin
      if StrokeFirst then
      begin
        FCanvas.StrokeTextAtBaseline(S, FFontHandle, FFontMetrics,
          SC, State.StrokeWidth, RunX, Y);
        FCanvas.DrawTextAtBaseline(S, FFontHandle, FFontMetrics, FC, RunX, Y);
      end
      else
      begin
        FCanvas.DrawTextAtBaseline(S, FFontHandle, FFontMetrics, FC, RunX, Y);
        FCanvas.StrokeTextAtBaseline(S, FFontHandle, FFontMetrics,
          SC, State.StrokeWidth, RunX, Y);
      end;
    end
    else if DoFill then
      FCanvas.DrawTextAtBaseline(S, FFontHandle, FFontMetrics, FC, RunX, Y)
    else
      FCanvas.StrokeTextAtBaseline(S, FFontHandle, FFontMetrics,
        SC, State.StrokeWidth, RunX, Y);
  end;

var
  TextW: Single;
  FC, SC, DecColor: TPixieWebColor;
  I, Start: Integer;
  Ch: string;
  ChW: Single;
  HasFill, HasStroke: Boolean;
begin
  EnsureFont(State);
  if FFontHandle = 0 then Exit;

  // Heuristic baseline offsets (no font baseline table access)
  case State.DominantBaseline of
    dbAuto: ;
    dbHanging:         Y := Y + FFontMetrics.Ascent * 0.8;
    dbMiddle:          Y := Y + FFontMetrics.XHeight * 0.5;
    dbCentral:         Y := Y + FFontMetrics.Ascent - FFontMetrics.Height * 0.5;
    dbMathematical:    Y := Y + FFontMetrics.Ascent * 0.5;
    dbIdeographic:     Y := Y - FFontMetrics.Descent;
    dbTextBeforeEdge:  Y := Y + FFontMetrics.Ascent;
    dbTextAfterEdge:   Y := Y - FFontMetrics.Descent;
  end;

  HasFill := State.HasFill;
  HasStroke := State.HasStroke and (State.StrokeWidth > 0);
  if not HasFill and not HasStroke then Exit;

  // Resolve fill color
  if HasFill then
  begin
    FC := State.FillColor;
    if State.FillGradientId <> '' then
    begin
      FC := ResolveGradientFirstColor(State.FillGradientId);
      if FC.Alpha = 0 then
        FC := State.FillColor;
    end;
    FC.Alpha := Round(FC.Alpha * State.FillOpacity);
  end;

  // Resolve stroke color
  if HasStroke then
  begin
    SC := State.StrokeColor;
    SC.Alpha := Round(SC.Alpha * State.StrokeOpacity);
  end;

  // Draw fill and/or stroke
  if State.LetterSpacing <> 0 then
  begin
    ChW := 0;
    I := 1;
    while I <= Length(Text) do
    begin
      Start := I;
      ReadUtf8Char(Text, I);
      Ch := Copy(Text, Start, I - Start);
      DrawRun(Ch, X + ChW, HasFill, HasStroke, State.StrokeBeforeFill, FC, SC);
      ChW := ChW + FCanvas.MeasureText(Ch, FFontHandle) + State.LetterSpacing;
    end;
    if ChW > 0 then
      TextW := ChW - State.LetterSpacing
    else
      TextW := 0;
  end
  else
  begin
    DrawRun(Text, X, HasFill, HasStroke, State.StrokeBeforeFill, FC, SC);
    TextW := FCanvas.MeasureText(Text, FFontHandle);
  end;

  // Draw text-decoration lines
  if State.TextDecoration <> TextDecorationLineNone then
  begin
    if HasFill then DecColor := FC else DecColor := SC;
    if (State.TextDecoration and TextDecorationLineUnderline) <> 0 then
      FCanvas.DrawLine(X, Y + State.FontSize * SvgDecorationUnderlineOffset,
        X + TextW, Y + State.FontSize * SvgDecorationUnderlineOffset,
        DecColor, State.FontSize * SvgDecorationThickness);
    if (State.TextDecoration and TextDecorationLineOverline) <> 0 then
      FCanvas.DrawLine(X, Y - FFontMetrics.Ascent, X + TextW,
        Y - FFontMetrics.Ascent, DecColor, State.FontSize * SvgDecorationThickness);
    if (State.TextDecoration and TextDecorationLineLineThrough) <> 0 then
      FCanvas.DrawLine(X, Y - FFontMetrics.XHeight / 2, X + TextW,
        Y - FFontMetrics.XHeight / 2, DecColor, State.FontSize * SvgDecorationThickness);
  end;
end;

// ===========================================================================
// Image support
// ===========================================================================

procedure TPixieSvgCanvasRenderer.FreeImageCache;
var
  Handle: TPixieImageHandle;
begin
  if FImageCache <> nil then
  begin
    if FCanvas <> nil then
      for Handle in FImageCache.Values do
        FCanvas.FreeImage(Handle);
    FreeAndNil(FImageCache);
  end;
end;

function TPixieSvgCanvasRenderer.LoadImageFromHref(
  const Href: string): TPixieImageHandle;
var
  CacheKey: string;
  DataStream: TMemoryStream;
{$IFDEF FPC}
  Img: TFPMemoryImage;
  Pixels: PByte;
  Pitch, W, H: Integer;
{$ENDIF}
begin
  Result := 0;
  if FCanvas = nil then Exit;

  // Use a short key for data: URIs to avoid hashing megabytes of base64
  if (Length(Href) > 256) and (Pos('data:', Href) = 1) then
    CacheKey := 'data:' + IntToStr(Length(Href)) + ':' +
      Copy(Href, Length(Href) - 31, 32)
  else
    CacheKey := Href;

  // Check cache
  if FImageCache <> nil then
    if FImageCache.TryGetValue(CacheKey, Result) then Exit;

  // Decode data: URI
  if Pos('data:', Href) = 1 then
  begin
    if not DecodeDataUri(Href, DataStream) then Exit;
    try
      // An SVG embedded as a data: URI (e.g. shields.io badge logos carry the
      // brand mark as `data:image/svg+xml;base64,...`) must go through the SVG
      // path. The raster decoders below cannot read XML, and FPImage in
      // particular raises an exception on the markup bytes. Sniff the decoded
      // content rather than trusting the media type, which is sometimes
      // missing or wrong.
      if PixieDataLooksLikeSvg(DataStream.Memory, DataStream.Size) then
        Result := FCanvas.LoadSvgFromData(DataStream.Memory, DataStream.Size)
      else
      begin
        // Try canvas-native stream loading (D2D/WIC, FMX)
        Result := FCanvas.LoadImageFromStream(DataStream);
      {$IFDEF FPC}
        // FPC backends: FPImage fallback for Cairo/CG/Qt
        if Result = 0 then
        begin
          Img := TFPMemoryImage.Create(0, 0);
          try
            try
              DataStream.Position := 0;
              Img.LoadFromStream(DataStream);
            except
              Exit;
            end;
            ConvertFPImageToBGRA(Img, Pixels, W, H, Pitch);
            if Pixels <> nil then
            try
              Result := FCanvas.LoadImageFromPixels(W, H, Pixels, Pitch);
            finally
              FreeMem(Pixels);
            end;
          finally
            Img.Free;
          end;
        end;
      {$ENDIF}
      end;
    finally
      DataStream.Free;
    end;
  end
  else
    // File path
    Result := FCanvas.LoadImage(Href);

  // Cache the loaded handle
  if Result <> 0 then
  begin
    if FImageCache = nil then
      FImageCache := TDictionary<string, TPixieImageHandle>.Create;
    FImageCache.Add(CacheKey, Result);
  end;
end;

procedure TPixieSvgCanvasRenderer.DoDrawImage(const Href: string;
  X, Y, W, H: Single);
var
  Handle: TPixieImageHandle;
begin
  Handle := LoadImageFromHref(Href);
  if Handle = 0 then Exit;
  FCanvas.DrawImage(Handle, X, Y, W, H);
end;

procedure TPixieSvgCanvasRenderer.DoClearImages;
begin
  FreeImageCache;
end;

// ===========================================================================
// Pattern fill
// ===========================================================================

// Inverse-transform the bounding box through the patternTransform matrix.
// After ConcatMatrix applies the transform to the canvas, tile positions
// are in untransformed coordinates, so we need the bounding box in that space.
procedure InvertPatternTransform(const M: TPixieSvgMatrix;
  var BX, BY, BW, BH: Single);
var
  Det, InvA, InvB, InvC, InvD, InvE, InvF: Single;
  CX, CY: array[0..3] of Single;
  I: Integer;
  MinX, MinY, MaxX, MaxY: Single;
begin
  Det := M.A * M.D - M.B * M.C;
  if Abs(Det) < 1e-10 then Exit;
  Det := 1 / Det;

  // Compute inverse matrix
  InvA :=  M.D * Det;
  InvB := -M.B * Det;
  InvC := -M.C * Det;
  InvD :=  M.A * Det;
  InvE := (M.C * M.F - M.D * M.E) * Det;
  InvF := (M.B * M.E - M.A * M.F) * Det;

  // Transform all 4 corners of the bounding box
  CX[0] := InvA * BX       + InvC * BY       + InvE;
  CY[0] := InvB * BX       + InvD * BY       + InvF;
  CX[1] := InvA * (BX+BW)  + InvC * BY       + InvE;
  CY[1] := InvB * (BX+BW)  + InvD * BY       + InvF;
  CX[2] := InvA * BX       + InvC * (BY+BH)  + InvE;
  CY[2] := InvB * BX       + InvD * (BY+BH)  + InvF;
  CX[3] := InvA * (BX+BW)  + InvC * (BY+BH)  + InvE;
  CY[3] := InvB * (BX+BW)  + InvD * (BY+BH)  + InvF;

  // Find axis-aligned bounding box of transformed corners
  MinX := CX[0]; MaxX := CX[0];
  MinY := CY[0]; MaxY := CY[0];
  for I := 1 to 3 do
  begin
    if CX[I] < MinX then MinX := CX[I];
    if CX[I] > MaxX then MaxX := CX[I];
    if CY[I] < MinY then MinY := CY[I];
    if CY[I] > MaxY then MaxY := CY[I];
  end;

  BX := MinX; BY := MinY;
  BW := MaxX - MinX; BH := MaxY - MinY;
end;

// Preconditions: caller (DoFillAndStroke) owns FPathRecord and FBBox* —
// this routine must not clear them, so the subsequent stroke rebuild still
// sees the path. On any failure we only discard the canvas path.
procedure TPixieSvgCanvasRenderer.FillWithPattern(
  const State: TPixieSvgState; FillRule: TPixieFillRule);
const
  Eps = 0.001;
  MaxTiles = 100000;
var
  Info: TPixieSvgPatternInfo;
  Handle: TPixieImageHandle;
  BX, BY, BW, BH: Single;
  TileX, TileY, TileW, TileH: Single;
  ImgDrawX, ImgDrawY, ImgDrawW, ImgDrawH: Single;
  ScaleX, ScaleY: Single;
  NeedOpacity, ImageFillsTile, UseSubtree: Boolean;
  StartCol, EndCol, StartRow, EndRow, Col, Row: Integer;
  TileCount: Int64;
  TileImg: TPixieImageHandle;
  TileScaleX, TileScaleY: Single;
  TilePixelW, TilePixelH: Integer;
  SavedPath: TPathEntryList;
  SavedBBoxMinX, SavedBBoxMinY, SavedBBoxMaxX, SavedBBoxMaxY: Single;
  SavedBBoxValid: Boolean;
begin
  if not GetPatternInfo(State.FillGradientId, Info) or not FBBoxValid then
  begin
    FCanvas.DiscardPath;
    Exit;
  end;

  // Prefer subtree rendering for patterns with children (handles clips,
  // transforms, nested <use> correctly).  Fall back to image-based path
  // only for simple single-image patterns without children.
  Handle := 0;
  UseSubtree := Info.HasChildren and (Info.PatternNode <> nil) and
    (FPatternDepth < 3);
  if not UseSubtree then
  begin
    if Info.ImageHref <> '' then
      Handle := LoadImageFromHref(Info.ImageHref);
  end;
  if (Handle = 0) and not UseSubtree then
  begin
    FCanvas.DiscardPath;
    Exit;
  end;

  BX := FBBoxMinX;
  BY := FBBoxMinY;
  BW := FBBoxMaxX - FBBoxMinX;
  BH := FBBoxMaxY - FBBoxMinY;
  if (BW <= 0) or (BH <= 0) then
  begin
    FCanvas.DiscardPath;
    Exit;
  end;

  // Tile rectangle in user space per patternUnits
  if Info.PatternUnitsUserSpace then
  begin
    TileX := Info.X;
    TileY := Info.Y;
    TileW := Info.Width;
    TileH := Info.Height;
  end
  else
  begin
    TileX := BX + Info.X * BW;
    TileY := BY + Info.Y * BH;
    TileW := Info.Width * BW;
    TileH := Info.Height * BH;
  end;

  NeedOpacity := State.FillOpacity < 1.0;

  FCanvas.SaveState;
  try
    FCanvas.ClipPath(FillRule);

    if NeedOpacity then
      FCanvas.PushOpacity(State.FillOpacity);

    // Apply full patternTransform (rotation, scale, skew, translate)
    if Info.HasPatternTransform then
    begin
      FCanvas.ConcatMatrix(
        Info.PatternTransform.A, Info.PatternTransform.B,
        Info.PatternTransform.C, Info.PatternTransform.D,
        Info.PatternTransform.E, Info.PatternTransform.F);
      // Compute bounding box in inverse-transformed tile space
      InvertPatternTransform(Info.PatternTransform, BX, BY, BW, BH);
    end;

    if UseSubtree then
    begin
      // Subtree rendering: render pattern children into the canvas.
      Inc(FPatternDepth);
      // Save path record and bbox — child rendering will overwrite them
      SavedPath := FPathRecord;
      FPathRecord := TPathEntryList.Create;
      SavedBBoxMinX := FBBoxMinX; SavedBBoxMinY := FBBoxMinY;
      SavedBBoxMaxX := FBBoxMaxX; SavedBBoxMaxY := FBBoxMaxY;
      SavedBBoxValid := FBBoxValid;
      try
        StartCol := Floor((BX - TileX) / TileW);
        EndCol := Ceil((BX + BW - TileX) / TileW) - 1;
        StartRow := Floor((BY - TileY) / TileH);
        EndRow := Ceil((BY + BH - TileY) / TileH) - 1;
        TileCount := Int64(EndCol - StartCol + 1) *
           Int64(EndRow - StartRow + 1);

        // Try off-screen tile rendering: render once, tile as image.
        // The off-screen bitmap must match the display resolution —
        // query the full canvas transform (viewport + patternTransform).
        TileImg := 0;
        FCanvas.GetTransformScale(TileScaleX, TileScaleY);
        TilePixelW := Min(4096, Max(1, Ceil(TileW * TileScaleX)));
        TilePixelH := Min(4096, Max(1, Ceil(TileH * TileScaleY)));
        if (TileCount > 4) and (TileW > 0) and (TileH > 0) and
           FCanvas.BeginTileRender(TilePixelW, TilePixelH) then
        begin
          // Scale children from tile coords to pixel coords.
          // Must use pixel/tile ratio (not raw canvas scale) so content
          // fills the bitmap exactly — Ceil rounding would leave gaps.
          FCanvas.ConcatMatrix(
            TilePixelW / TileW, 0, 0, TilePixelH / TileH, 0, 0);
          if Info.HasViewBox then
            FCanvas.ConcatMatrix(
              TileW / Info.ViewBoxW, 0, 0, TileH / Info.ViewBoxH,
              -Info.ViewBoxX * TileW / Info.ViewBoxW,
              -Info.ViewBoxY * TileH / Info.ViewBoxH)
          else if Info.ContentUnitsObjectBBox then
            FCanvas.ConcatMatrix(BW, 0, 0, BH, 0, 0);
          RenderPatternChildren(Info.PatternNode);
          TileImg := FCanvas.EndTileRender;
        end;

        if TileImg <> 0 then
        begin
          // Tile the pre-rendered image (single GPU call on D2D).
          // Snap fill rect to tile boundaries — matches the per-tile
          // loop coverage exactly, preventing rounding gaps at edges.
          FCanvas.FillTiledImage(TileImg, TileX, TileY, TileW, TileH,
            TileX + StartCol * TileW, TileY + StartRow * TileH,
            (EndCol - StartCol + 1) * TileW,
            (EndRow - StartRow + 1) * TileH);
          FCanvas.FreeImage(TileImg);
        end
        else if TileCount <= MaxTiles then
          for Row := StartRow to EndRow do
            for Col := StartCol to EndCol do
            begin
              FCanvas.SaveState;
              FCanvas.ConcatMatrix(1, 0, 0, 1,
                TileX + Col * TileW, TileY + Row * TileH);
              // Clip to tile rect
              FCanvas.BeginPath;
              FCanvas.MoveTo(0, 0);
              FCanvas.LineTo(TileW, 0);
              FCanvas.LineTo(TileW, TileH);
              FCanvas.LineTo(0, TileH);
              FCanvas.ClosePath;
              FCanvas.ClipPath;
              // Apply content coordinate scaling
              if Info.HasViewBox then
                FCanvas.ConcatMatrix(
                  TileW / Info.ViewBoxW, 0, 0, TileH / Info.ViewBoxH,
                  -Info.ViewBoxX * TileW / Info.ViewBoxW,
                  -Info.ViewBoxY * TileH / Info.ViewBoxH)
              else if Info.ContentUnitsObjectBBox then
                FCanvas.ConcatMatrix(BW, 0, 0, BH, 0, 0);
              RenderPatternChildren(Info.PatternNode);
              FCanvas.RestoreState;
            end;
      finally
        FPathRecord.Free;
        FPathRecord := SavedPath;
        FBBoxMinX := SavedBBoxMinX; FBBoxMinY := SavedBBoxMinY;
        FBBoxMaxX := SavedBBoxMaxX; FBBoxMaxY := SavedBBoxMaxY;
        FBBoxValid := SavedBBoxValid;
        Dec(FPatternDepth);
      end;
    end
    else
    begin
      // Image-based path: tile the loaded image
      ImgDrawX := 0; ImgDrawY := 0;
      ImgDrawW := 0; ImgDrawH := 0;
      if Info.HasViewBox then
      begin
        ScaleX := TileW / Info.ViewBoxW;
        ScaleY := TileH / Info.ViewBoxH;
        ImgDrawX := (Info.ImgX - Info.ViewBoxX) * ScaleX;
        ImgDrawY := (Info.ImgY - Info.ViewBoxY) * ScaleY;
        ImgDrawW := Info.ImgW * ScaleX;
        ImgDrawH := Info.ImgH * ScaleY;
      end
      else if Info.ContentUnitsObjectBBox then
      begin
        if (Info.ImgW <= 1.0 + 0.01) and (Info.ImgH <= 1.0 + 0.01) then
        begin
          ImgDrawX := Info.ImgX * TileW;
          ImgDrawY := Info.ImgY * TileH;
          ImgDrawW := Info.ImgW * TileW;
          ImgDrawH := Info.ImgH * TileH;
        end;
      end
      else
      begin
        ImgDrawX := Info.ImgX;
        ImgDrawY := Info.ImgY;
        ImgDrawW := Info.ImgW;
        ImgDrawH := Info.ImgH;
      end;

      if (ImgDrawW <= 0) or (ImgDrawH <= 0) then
      begin
        ImgDrawX := 0;
        ImgDrawY := 0;
        ImgDrawW := TileW;
        ImgDrawH := TileH;
      end;

      ImageFillsTile :=
        (Abs(ImgDrawX) < Eps) and (Abs(ImgDrawY) < Eps) and
        (Abs(ImgDrawW - TileW) < Eps) and (Abs(ImgDrawH - TileH) < Eps);

      if ImageFillsTile then
        FCanvas.FillTiledImage(Handle, TileX, TileY, TileW, TileH,
          BX, BY, BW, BH)
      else
      begin
        StartCol := Floor((BX - TileX) / TileW);
        EndCol := Ceil((BX + BW - TileX) / TileW) - 1;
        StartRow := Floor((BY - TileY) / TileH);
        EndRow := Ceil((BY + BH - TileY) / TileH) - 1;
        if Int64(EndCol - StartCol + 1) *
           Int64(EndRow - StartRow + 1) <= MaxTiles then
          for Row := StartRow to EndRow do
            for Col := StartCol to EndCol do
              FCanvas.DrawImage(Handle,
                TileX + Col * TileW + ImgDrawX,
                TileY + Row * TileH + ImgDrawY,
                ImgDrawW, ImgDrawH);
      end;
    end;

    if NeedOpacity then
      FCanvas.PopOpacity;
  finally
    FCanvas.RestoreState;
  end;
end;

procedure TPixieSvgCanvasRenderer.RenderPatternChildren(
  PatternNode: Pointer);
var
  Child: TDOMNode;
  ChildState: TPixieSvgState;
begin
  Child := TDOMNode(PatternNode).FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = xntElement then
    begin
      ChildState := InheritState(Pointer(Child), FInitState);
      RenderElement(Pointer(Child), ChildState);
    end;
    Child := Child.NextSibling;
  end;
end;

// ===========================================================================
// Public API
// ===========================================================================

procedure TPixieSvgCanvasRenderer.RenderToRect(
  DstX, DstY, DstW, DstH: Single);
var
  Sx, Sy, Scale, OffX, OffY: Single;
  ClipPos: TPixiePosition;
  ClipRadius: TPixieBorderRadiuses;
begin
  FCanvas.SaveState;
  try
    // Translate to destination position
    FCanvas.ConcatMatrix(1, 0, 0, 1, DstX, DstY);

    // Scale from viewBox to destination size, preserving aspect ratio
    if (FViewBoxW > 0.01) and (FViewBoxH > 0.01) then
    begin
      Sx := DstW / FViewBoxW;
      Sy := DstH / FViewBoxH;
      Scale := Min(Sx, Sy);
      // Centre within the destination rect
      OffX := (DstW - FViewBoxW * Scale) * 0.5;
      OffY := (DstH - FViewBoxH * Scale) * 0.5;
      if (Abs(OffX) > 0.01) or (Abs(OffY) > 0.01) then
        FCanvas.ConcatMatrix(1, 0, 0, 1, OffX, OffY);
      FCanvas.ConcatMatrix(Scale, 0, 0, Scale, 0, 0);

      // Clip to viewBox unless overflow is visible (e.g. no explicit size)
      if not FOverflowVisible then
      begin
        ClipPos := TPixiePosition.Create(0, 0, FViewBoxW, FViewBoxH);
        ClipRadius.Init;
        FCanvas.SetClipRect(ClipPos, ClipRadius);
      end;
    end;

    // Apply viewBox offset
    if (Abs(FViewBoxX) > 0.01) or (Abs(FViewBoxY) > 0.01) then
      FCanvas.ConcatMatrix(1, 0, 0, 1, -FViewBoxX, -FViewBoxY);

    RenderDocument;
  finally
    FCanvas.RestoreState;
  end;
end;

end.
