unit Pixie.DrawingCanvas;

// TPixieDrawingCanvas — TCanvas-like stateful wrapper around TPixieCanvas.
// Provides Pen, Brush, Font properties and familiar shape/text methods.
// Pen, Brush, Font are classes (like TCanvas) so C.Pen.Color := X works.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Math,
  Pixie.Types, Pixie.WebColor, Pixie.Canvas, Pixie.FontDescription;

type
  TPixiePenStyle = (psSolid, psDash, psDot, psClear);
  TPixieBrushStyle = (bsSolid, bsClear);

  TPixieDrawingFontStyle = (fsBold, fsItalic);
  TPixieDrawingFontStyles = set of TPixieDrawingFontStyle;

  { TPixiePen }

  TPixiePen = class
  public
    Color: TPixieWebColor;
    Width: Single;
    Style: TPixiePenStyle;
    constructor Create;
  end;

  { TPixieBrush }

  TPixieBrush = class
  public
    Color: TPixieWebColor;
    Style: TPixieBrushStyle;
    constructor Create;
  end;

  { TPixieDrawingFont }

  TPixieDrawingFont = class
  public
    Family: string;
    Size: Single;
    Style: TPixieDrawingFontStyles;
    Color: TPixieWebColor;
    constructor Create;
  end;

  TPixieDrawingCanvas = class;

  TPixiePaintEvent = procedure(Sender: TObject;
    ACanvas: TPixieDrawingCanvas) of object;

  { TPixieDrawingCanvas }

  TPixieDrawingCanvas = class
  private
    FCanvas: TPixieCanvas;
    FFontOwner: TPixieCanvas;  // Canvas that owns FFontHandle (may outlast Unbind)
    FPen: TPixiePen;
    FBrush: TPixieBrush;
    FFont: TPixieDrawingFont;
    FFontHandle: TPixieFontHandle;
    FFontMetrics: TPixieFontMetrics;
    // Cached font identity — used to detect changes
    FCachedFamily: string;
    FCachedSize: Single;
    FCachedStyle: TPixieDrawingFontStyles;
    procedure EnsureFont;
    procedure DestroyFont;
    function PenDecoStyle: TPixieTextDecorationStyle;
    procedure DoStrokeRect(X, Y, W, H: Single);
    procedure DoFillAndStrokeFromPath;
    procedure EmitRoundRectPath(X, Y, W, H, R: Single);
  public
    constructor Create;
    destructor Destroy; override;

    // Lifecycle — bind to a TPixieCanvas for painting
    procedure Bind(ACanvas: TPixieCanvas);
    procedure Unbind;

    // Shape drawing (uses current Pen and Brush)
    procedure Line(X1, Y1, X2, Y2: Single);
    procedure Rectangle(X, Y, W, H: Single);
    procedure FillRect(X, Y, W, H: Single);
    procedure RoundRect(X, Y, W, H, Radius: Single);
    procedure Ellipse(X, Y, W, H: Single);
    procedure Circle(CX, CY, Radius: Single);
    procedure Polygon(const Points: array of TPixiePointF);
    procedure Polyline(const Points: array of TPixiePointF);
    procedure Arc(X, Y, W, H: Single; StartAngle, SweepAngle: Single);

    // Text (uses current Font)
    procedure TextOut(X, Y: Single; const Text: string);
    procedure TextRect(X, Y, W, H: Single; const Text: string;
      HAlign: TPixieTextAlign = taLeft;
      VAlign: TPixieVerticalAlign = vaTop);
    function TextWidth(const Text: string): Single;
    function TextHeight: Single;

    // Image pass-through
    procedure DrawImage(Handle: TPixieImageHandle;
      X, Y, W, H: Single);

    // State pass-through
    procedure SaveState;
    procedure RestoreState;

    // Properties
    property Canvas: TPixieCanvas read FCanvas;
    property Pen: TPixiePen read FPen;
    property Brush: TPixieBrush read FBrush;
    property Font: TPixieDrawingFont read FFont;
  end;

implementation

{ TPixiePen }

constructor TPixiePen.Create;
begin
  inherited Create;
  Color := TPixieWebColor.Black;
  Width := 1.0;
  Style := psSolid;
end;

{ TPixieBrush }

constructor TPixieBrush.Create;
begin
  inherited Create;
  Color := TPixieWebColor.White;
  Style := bsSolid;
end;

{ TPixieDrawingFont }

constructor TPixieDrawingFont.Create;
begin
  inherited Create;
  Family := 'sans-serif';
  Size := 13.0;
  Style := [];
  Color := TPixieWebColor.Black;
end;

{ TPixieDrawingCanvas }

constructor TPixieDrawingCanvas.Create;
begin
  inherited Create;
  FCanvas := nil;
  FPen := TPixiePen.Create;
  FBrush := TPixieBrush.Create;
  FFont := TPixieDrawingFont.Create;
  FFontHandle := 0;
  FCachedFamily := '';
  FCachedSize := 0;
  FCachedStyle := [];
end;

destructor TPixieDrawingCanvas.Destroy;
begin
  DestroyFont;
  FFont.Free;
  FBrush.Free;
  FPen.Free;
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

procedure TPixieDrawingCanvas.Bind(ACanvas: TPixieCanvas);
begin
  if (FFontOwner <> nil) and (ACanvas <> FFontOwner) then
    DestroyFont;
  FCanvas := ACanvas;
end;

procedure TPixieDrawingCanvas.Unbind;
begin
  // Keep font handle alive for next Bind with same canvas
  FCanvas := nil;
end;

// ---------------------------------------------------------------------------
// Font management
// ---------------------------------------------------------------------------

procedure TPixieDrawingCanvas.EnsureFont;
var
  Descr: TPixieFontDescription;
begin
  if FCanvas = nil then Exit;
  // Check if font identity changed since last CreateFont
  if (FFontHandle <> 0) and (FFont.Family = FCachedFamily) and
     (FFont.Size = FCachedSize) and (FFont.Style = FCachedStyle) then
    Exit;
  DestroyFont;
  Descr.Init;
  Descr.Family := FFont.Family;
  Descr.Size := FFont.Size;
  if fsBold in FFont.Style then
    Descr.Weight := 700
  else
    Descr.Weight := 400;
  if fsItalic in FFont.Style then
    Descr.Style := fstItalic
  else
    Descr.Style := fstNormal;
  FFontHandle := FCanvas.CreateFont(Descr, FFontMetrics);
  FFontOwner := FCanvas;
  FCachedFamily := FFont.Family;
  FCachedSize := FFont.Size;
  FCachedStyle := FFont.Style;
end;

procedure TPixieDrawingCanvas.DestroyFont;
begin
  if (FFontHandle <> 0) and (FFontOwner <> nil) then
    FFontOwner.DeleteFont(FFontHandle);
  FFontHandle := 0;
  FFontOwner := nil;
end;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function TPixieDrawingCanvas.PenDecoStyle: TPixieTextDecorationStyle;
begin
  case FPen.Style of
    psDash: Result := tdsDashed;
    psDot:  Result := tdsDotted;
  else
    Result := tdsSolid;
  end;
end;

procedure TPixieDrawingCanvas.DoStrokeRect(X, Y, W, H: Single);
begin
  if FPen.Style = psSolid then
    FCanvas.DrawRect(X, Y, W, H, FPen.Color, FPen.Width)
  else
  begin
    Line(X, Y, X + W, Y);
    Line(X + W, Y, X + W, Y + H);
    Line(X + W, Y + H, X, Y + H);
    Line(X, Y + H, X, Y);
  end;
end;

procedure TPixieDrawingCanvas.DoFillAndStrokeFromPath;
var
  DoFill, DoStroke: Boolean;
begin
  DoFill := FBrush.Style = bsSolid;
  DoStroke := FPen.Style <> psClear;
  if DoFill and DoStroke then
    FCanvas.FillAndStrokePath(FBrush.Color, FPen.Color, FPen.Width)
  else if DoFill then
    FCanvas.FillPath(FBrush.Color)
  else if DoStroke then
    FCanvas.StrokePath(FPen.Color, FPen.Width);
end;

procedure TPixieDrawingCanvas.EmitRoundRectPath(X, Y, W, H, R: Single);
const
  Kappa: Single = 0.5522847498;
var
  K: Single;
begin
  K := R * Kappa;
  FCanvas.BeginPath;
  FCanvas.MoveTo(X + R, Y);
  FCanvas.LineTo(X + W - R, Y);
  FCanvas.CurveTo(X + W - R + K, Y, X + W, Y + R - K, X + W, Y + R);
  FCanvas.LineTo(X + W, Y + H - R);
  FCanvas.CurveTo(X + W, Y + H - R + K, X + W - R + K, Y + H, X + W - R, Y + H);
  FCanvas.LineTo(X + R, Y + H);
  FCanvas.CurveTo(X + R - K, Y + H, X, Y + H - R + K, X, Y + H - R);
  FCanvas.LineTo(X, Y + R);
  FCanvas.CurveTo(X, Y + R - K, X + R - K, Y, X + R, Y);
  FCanvas.ClosePath;
end;

// ---------------------------------------------------------------------------
// Shape drawing
// ---------------------------------------------------------------------------

procedure TPixieDrawingCanvas.Line(X1, Y1, X2, Y2: Single);
begin
  if (FCanvas = nil) or (FPen.Style = psClear) then Exit;
  FCanvas.DrawLine(X1, Y1, X2, Y2, FPen.Color, FPen.Width, PenDecoStyle);
end;

procedure TPixieDrawingCanvas.Rectangle(X, Y, W, H: Single);
begin
  if FCanvas = nil then Exit;
  if FBrush.Style = bsSolid then
    FCanvas.FillRect(X, Y, W, H, FBrush.Color);
  if FPen.Style <> psClear then
    DoStrokeRect(X, Y, W, H);
end;

procedure TPixieDrawingCanvas.FillRect(X, Y, W, H: Single);
begin
  if (FCanvas = nil) or (FBrush.Style = bsClear) then Exit;
  FCanvas.FillRect(X, Y, W, H, FBrush.Color);
end;

procedure TPixieDrawingCanvas.RoundRect(X, Y, W, H, Radius: Single);
begin
  if FCanvas = nil then Exit;
  if Radius <= 0 then
  begin
    Rectangle(X, Y, W, H);
    Exit;
  end;
  if FBrush.Style = bsSolid then
    FCanvas.FillRoundedRect(X, Y, W, H, Radius, FBrush.Color);
  if FPen.Style <> psClear then
  begin
    EmitRoundRectPath(X, Y, W, H, Radius);
    FCanvas.StrokePath(FPen.Color, FPen.Width);
  end;
end;

procedure TPixieDrawingCanvas.Ellipse(X, Y, W, H: Single);
begin
  if FCanvas = nil then Exit;
  if FBrush.Style = bsSolid then
    FCanvas.FillEllipse(X, Y, W, H, FBrush.Color);
  if FPen.Style <> psClear then
    FCanvas.DrawEllipse(X, Y, W, H, FPen.Color, FPen.Width);
end;

procedure TPixieDrawingCanvas.Circle(CX, CY, Radius: Single);
begin
  Ellipse(CX - Radius, CY - Radius, Radius * 2, Radius * 2);
end;

procedure TPixieDrawingCanvas.Polygon(const Points: array of TPixiePointF);
var
  I: Integer;
begin
  if (FCanvas = nil) or (Length(Points) < 2) then Exit;
  FCanvas.BeginPath;
  FCanvas.MoveTo(Points[0].X, Points[0].Y);
  for I := 1 to High(Points) do
    FCanvas.LineTo(Points[I].X, Points[I].Y);
  FCanvas.ClosePath;
  DoFillAndStrokeFromPath;
end;

procedure TPixieDrawingCanvas.Polyline(const Points: array of TPixiePointF);
var
  Flat: array of Single;
  I: Integer;
begin
  if (FCanvas = nil) or (FPen.Style = psClear) or (Length(Points) < 2) then Exit;
  if FPen.Style = psSolid then
  begin
    SetLength(Flat, Length(Points) * 2);
    for I := 0 to High(Points) do
    begin
      Flat[I * 2] := Points[I].X;
      Flat[I * 2 + 1] := Points[I].Y;
    end;
    FCanvas.StrokePolyline(Flat, FPen.Color, FPen.Width);
  end
  else
    for I := 0 to High(Points) - 1 do
      Line(Points[I].X, Points[I].Y, Points[I + 1].X, Points[I + 1].Y);
end;

procedure TPixieDrawingCanvas.Arc(X, Y, W, H: Single;
  StartAngle, SweepAngle: Single);
var
  CX, CY, RX, RY: Single;
  Theta, DTheta, SegAngle, Alpha, T: Single;
  Segments, Seg: Integer;
  Cos1, Sin1, Cos2, Sin2: Single;
begin
  if (FCanvas = nil) or (FPen.Style = psClear) then Exit;
  if Abs(SweepAngle) < 0.001 then Exit;

  // Full ellipse — stroke only (Arc is a stroke operation)
  if Abs(SweepAngle) >= 360 then
  begin
    if FCanvas = nil then Exit;
    FCanvas.DrawEllipse(X, Y, W, H, FPen.Color, FPen.Width);
    Exit;
  end;

  CX := X + W * 0.5;
  CY := Y + H * 0.5;
  RX := W * 0.5;
  RY := H * 0.5;

  // Convert degrees to radians
  Theta := DegToRad(StartAngle);
  DTheta := DegToRad(SweepAngle);

  // Split into segments of at most 90 degrees
  Segments := Ceil(Abs(DTheta) / (Pi * 0.5));
  if Segments < 1 then Segments := 1;
  SegAngle := DTheta / Segments;
  Alpha := 4.0 / 3.0 * Tan(SegAngle * 0.25);

  FCanvas.BeginPath;
  T := Theta;
  SinCos(T, Sin1, Cos1);
  FCanvas.MoveTo(CX + RX * Cos1, CY + RY * Sin1);

  for Seg := 0 to Segments - 1 do
  begin
    SinCos(T + SegAngle, Sin2, Cos2);
    FCanvas.CurveTo(
      CX + RX * (Cos1 - Alpha * Sin1),
      CY + RY * (Sin1 + Alpha * Cos1),
      CX + RX * (Cos2 + Alpha * Sin2),
      CY + RY * (Sin2 - Alpha * Cos2),
      CX + RX * Cos2,
      CY + RY * Sin2);
    T := T + SegAngle;
    Cos1 := Cos2;
    Sin1 := Sin2;
  end;

  FCanvas.StrokePath(FPen.Color, FPen.Width);
end;

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

procedure TPixieDrawingCanvas.TextOut(X, Y: Single; const Text: string);
begin
  if FCanvas = nil then Exit;
  EnsureFont;
  if FFontHandle = 0 then Exit;
  FCanvas.DrawSimpleText(Text, FFontHandle, FFont.Color, X, Y);
end;

procedure TPixieDrawingCanvas.TextRect(X, Y, W, H: Single;
  const Text: string; HAlign: TPixieTextAlign; VAlign: TPixieVerticalAlign);
begin
  if FCanvas = nil then Exit;
  EnsureFont;
  if FFontHandle = 0 then Exit;
  FCanvas.TextRect(Text, FFontHandle, FFontMetrics, FFont.Color,
    X, Y, W, H, HAlign, VAlign);
end;

function TPixieDrawingCanvas.TextWidth(const Text: string): Single;
begin
  Result := 0;
  if FCanvas = nil then Exit;
  EnsureFont;
  if FFontHandle = 0 then Exit;
  Result := FCanvas.MeasureText(Text, FFontHandle);
end;

function TPixieDrawingCanvas.TextHeight: Single;
begin
  Result := 0;
  if FCanvas = nil then Exit;
  EnsureFont;
  Result := FFontMetrics.Height;
end;

// ---------------------------------------------------------------------------
// Image and state pass-through
// ---------------------------------------------------------------------------

procedure TPixieDrawingCanvas.DrawImage(Handle: TPixieImageHandle;
  X, Y, W, H: Single);
begin
  if FCanvas <> nil then
    FCanvas.DrawImage(Handle, X, Y, W, H);
end;

procedure TPixieDrawingCanvas.SaveState;
begin
  if FCanvas <> nil then
    FCanvas.SaveState;
end;

procedure TPixieDrawingCanvas.RestoreState;
begin
  if FCanvas <> nil then
    FCanvas.RestoreState;
end;

end.
