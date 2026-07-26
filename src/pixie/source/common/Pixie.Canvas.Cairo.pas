unit Pixie.Canvas.Cairo;

// Cairo + PangoCairo implementation of TPixieCanvas for Linux/GTK2 and GTK3.
// Provides 2D drawing via Cairo and text measurement/rendering via Pango.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Math, dynlibs,
  cairo, glib2, pango, pangocairo,
  Graphics, IntfGraphics, FPImage,
  // FPImage format readers — registered so DecodeImageByContent's
  // content sniffing works even in canvas-only builds (no NativeContainer).
  FPReadPNG, FPReadJPEG, FPReadBMP, FPReadGIF,
  Pixie.Types, Pixie.WebColor, Pixie.Borders,
  Pixie.GradientLayer, Pixie.FontDescription,
  Pixie.ImageUtils, Pixie.Canvas;

type
  { TPixieCairoFont }

  TPixieCairoFont = class
    FontDesc: PPangoFontDescription;
    Metrics: TPixieFontMetrics;
    DecorationLine: Integer;
    destructor Destroy; override;
  end;

  { TPixieCairoImage }

  TPixieCairoImage = class
    Surface: Pcairo_surface_t;
    PixelData: Pointer;
    SvgRenderer: TObject;  // TPixieSvgCanvasRenderer (owns)
    ImgWidth: Integer;
    ImgHeight: Integer;
    AspectOnly: Boolean;
    AspectRatio: Single;
    destructor Destroy; override;
  end;

  TPixieCairoSavedState = record
    ClipsPushed: Integer;
  end;

  TPixieOpacityEntry = record
    Value: Single;
  end;

  TPixieCairoMaskEntry = record
    Surface: Pcairo_surface_t;
    Pixels: Pointer;
    X, Y, W, H: Single;
    ImgW, ImgH: Integer;
  end;

  { TPixieCairoCanvas }

  TPixieCairoCanvas = class(TPixieCanvas)
  private
    FCairo: Pcairo_t;
    FPersistentContext: PPangoContext;  // always available for metrics/measure
    FPangoContext: PPangoContext;       // paint-time context (may equal FPersistentContext)
    FViewWidth, FViewHeight: Integer;
    FStateStack: array[0..63] of TPixieCairoSavedState;
    FStateTop: Integer;
    FOpacityStack: array[0..15] of TPixieOpacityEntry;
    FOpacityTop: Integer;
    FMaskStack: array[0..15] of TPixieCairoMaskEntry;
    FMaskTop: Integer;
    FTileSurface: Pcairo_surface_t;
    FTileSavedCairo: Pcairo_t;
    FTileSavedPangoCtx: PPangoContext;
    FTileSavedStateTop: Integer;
    FTileSavedViewW, FTileSavedViewH: Integer;
    FOffscreenSurface: Pcairo_surface_t;

    procedure RoundedRectPath(X, Y, W, H: Single;
      const R: TPixieBorderRadiuses);
    procedure SetSourceColor(const C: TPixieWebColor);
    procedure ApplyDashPattern;
    procedure ClearDashPattern;
    procedure DrawBorderSide(const Border: TPixieBorder;
      X1, Y1, X2, Y2: Single);
    function DecodeImageFile(const Path: string): TPixieImageHandle;
    function DecodeImageByContent(const Path: string): TPixieImageHandle;
    // Wraps an owned premultiplied-BGRA buffer in a Cairo image surface; the
    // surface takes ownership of Buf via Info.PixelData.
    function NewCairoImageFromBuffer(Buf: PByte;
      W, H, Pitch: Integer): TPixieImageHandle;
    function LoadSvgFile(const Path: string): TPixieImageHandle;
  public
    constructor Create;
    destructor Destroy; override;

    procedure BeginPaint(DC: PtrUInt); override;
    procedure EndPaint; override;

    procedure SaveState; override;
    procedure RestoreState; override;
    procedure PushOpacity(AOpacity: Single); override;
    procedure PopOpacity; override;
    procedure PushMask(MaskHandle: TPixieImageHandle;
      MaskX, MaskY, MaskW, MaskH: Single); override;
    procedure PopMask; override;
    function SetBlendMode(Mode: TPixieBlendMode): Boolean; override;
    procedure ResetBlendMode; override;

    procedure SetClipRect(const R: TPixiePosition;
      const Radius: TPixieBorderRadiuses); override;

    procedure FillRect(X, Y, W, H: Single;
      Color: TPixieWebColor); override;
    procedure FillRoundedRect(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      Color: TPixieWebColor); override;
    procedure FillLinearGradient(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      const Gradient: TPixieLinearGradientLayer); override;
    procedure FillRadialGradient(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      const Gradient: TPixieRadialGradientLayer); override;
    procedure FillConicGradient(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      const Gradient: TPixieConicGradientLayer); override;

    procedure DrawBorders(const Borders: TPixieBorders;
      const Pos: TPixiePosition; IsRoot: Boolean); override;

    function CreateFont(const Descr: TPixieFontDescription;
      out Metrics: TPixieFontMetrics): TPixieFontHandle; override;
    procedure DoDeleteFont(Handle: TPixieFontHandle); override;
    function DoMeasureText(const Text: string;
      Handle: TPixieFontHandle): TPixiePixel; override;
    procedure DrawText(const Text: string; Handle: TPixieFontHandle;
      Color: TPixieWebColor; X, Y, W, H: Single); override;
    procedure StrokeTextAtBaseline(const Text: string;
      Handle: TPixieFontHandle; const Metrics: TPixieFontMetrics;
      Color: TPixieWebColor; Width: Single; X, BaselineY: Single); override;
    function PtToPx(Pt: Single): TPixiePixel; override;

    function LoadImage(const Path: string): TPixieImageHandle; override;
    function LoadImageFromPixels(Width, Height: Integer;
      Pixels: Pointer; Pitch: Integer): TPixieImageHandle; override;
    procedure FreeImage(Handle: TPixieImageHandle); override;
    procedure GetImageSize(Handle: TPixieImageHandle;
      out W, H: Single); override;
    function GetImageAspectInfo(Handle: TPixieImageHandle;
      out AspectRatio: Single): Boolean; override;
    procedure DrawImage(Handle: TPixieImageHandle;
      DstX, DstY, DstW, DstH: Single); override;
    procedure FillTiledImage(Handle: TPixieImageHandle;
      TileX, TileY, TileW, TileH: Single;
      FillX, FillY, FillW, FillH: Single); override;

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
    procedure StrokePathLinearGradient(
      const Gradient: TPixieLinearGradientLayer; Width: Single); override;
    procedure StrokePathRadialGradient(
      const Gradient: TPixieRadialGradientLayer; Width: Single); override;
    procedure ConcatMatrix(A, B, C, D, E, F: Single); override;

    function LoadSvgFromData(Data: Pointer;
      Size: Integer): TPixieImageHandle; override;

    procedure SetViewSize(W, H: Integer; ACanvasScale: Single = 1); override;

    // Off-screen tile rendering (pattern optimisation)
    function BeginTileRender(Width, Height: Integer): Boolean; override;
    function EndTileRender: TPixieImageHandle; override;
    procedure GetTransformScale(out ScaleX, ScaleY: Single); override;

    // Offscreen rendering (Cairo image surface)
    function BeginOffscreenPaint(Width, Height: Integer): Pcairo_surface_t;
    procedure EndOffscreenPaint;
    procedure SaveSurfaceToPng(Surface: Pcairo_surface_t;
      const FileName: string);

    // Public off-screen + image export API
    procedure BeginOffscreen(Width, Height: Integer;
      ClearColor: TPixieWebColor); override;
    procedure EndOffscreen; override;
    procedure SaveAsPng(Stream: TStream); override;
    procedure SaveAsPng(const FileName: string); override;
    procedure SaveAsBmp(Stream: TStream); override;
  end;

implementation

uses
  {$IFDEF LCLGtk2} Gtk2Def, gdk2 {$ENDIF}
  {$IFDEF LCLGtk3} Gtk3Objects {$ENDIF}
  , Pixie.SvgRenderer.Canvas
  ;

var
  GCheckFontContext: PPangoContext;

function CheckCairoFont(const Name: string): Boolean;
var
  PFontDesc: PPangoFontDescription;
  PFont: PPangoFont;
begin
  Result := False;
  if GCheckFontContext = nil then
    Exit(True); // no context — accept and let Pango resolve
  PFontDesc := pango_font_description_new;
  pango_font_description_set_family(PFontDesc, PAnsiChar(Name));
  pango_font_description_set_absolute_size(PFontDesc, 12 * PANGO_SCALE);
  PFont := pango_font_map_load_font(
    pango_cairo_font_map_get_default, GCheckFontContext, PFontDesc);
  Result := PFont <> nil;
  if PFont <> nil then
    g_object_unref(PFont);
  pango_font_description_free(PFontDesc);
end;

// ---------------------------------------------------------------------------
// TPixieCairoFont / TPixieCairoImage destructors
// ---------------------------------------------------------------------------

destructor TPixieCairoFont.Destroy;
begin
  if FontDesc <> nil then
    pango_font_description_free(FontDesc);
  inherited;
end;

destructor TPixieCairoImage.Destroy;
begin
  if Surface <> nil then
    cairo_surface_destroy(Surface);
  if PixelData <> nil then
    FreeMem(PixelData);
  SvgRenderer.Free;
  inherited;
end;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

procedure TPixieCairoCanvas.SetSourceColor(const C: TPixieWebColor);
begin
  cairo_set_source_rgba(FCairo,
    C.Red / 255.0, C.Green / 255.0,
    C.Blue / 255.0, C.Alpha / 255.0);
end;

procedure TPixieCairoCanvas.ApplyDashPattern;
var
  CairoDashes: array of Double;
  I: Integer;
begin
  if Length(FPathDashArray) > 0 then
  begin
    SetLength(CairoDashes, Length(FPathDashArray));
    for I := 0 to High(FPathDashArray) do
      CairoDashes[I] := FPathDashArray[I];
    cairo_set_dash(FCairo, @CairoDashes[0], Length(CairoDashes), FPathDashOffset);
  end;
end;

procedure TPixieCairoCanvas.ClearDashPattern;
begin
  if Length(FPathDashArray) > 0 then
    cairo_set_dash(FCairo, nil, 0, 0);
end;

procedure TPixieCairoCanvas.RoundedRectPath(X, Y, W, H: Single;
  const R: TPixieBorderRadiuses);
begin
  // Cairo Y-down: cairo_arc (increasing angle) goes clockwise on screen.
  // We trace the rect CW: left-edge down, top-left arc, top edge right, etc.
  cairo_new_path(FCairo);

  // Start on left edge, below top-left corner
  cairo_move_to(FCairo, X, Y + R.TopLeftY);

  // Top-left arc
  if (R.TopLeftX > 0) and (R.TopLeftY > 0) then
  begin
    cairo_save(FCairo);
    cairo_translate(FCairo, X + R.TopLeftX, Y + R.TopLeftY);
    cairo_scale(FCairo, R.TopLeftX, R.TopLeftY);
    cairo_arc(FCairo, 0, 0, 1, Pi, 3 * Pi / 2);
    cairo_restore(FCairo);
  end
  else
    cairo_line_to(FCairo, X, Y);

  // Top edge to top-right corner
  cairo_line_to(FCairo, X + W - R.TopRightX, Y);

  // Top-right arc
  if (R.TopRightX > 0) and (R.TopRightY > 0) then
  begin
    cairo_save(FCairo);
    cairo_translate(FCairo, X + W - R.TopRightX, Y + R.TopRightY);
    cairo_scale(FCairo, R.TopRightX, R.TopRightY);
    cairo_arc(FCairo, 0, 0, 1, 3 * Pi / 2, 2 * Pi);
    cairo_restore(FCairo);
  end
  else
    cairo_line_to(FCairo, X + W, Y);

  // Right edge to bottom-right corner
  cairo_line_to(FCairo, X + W, Y + H - R.BottomRightY);

  // Bottom-right arc
  if (R.BottomRightX > 0) and (R.BottomRightY > 0) then
  begin
    cairo_save(FCairo);
    cairo_translate(FCairo, X + W - R.BottomRightX, Y + H - R.BottomRightY);
    cairo_scale(FCairo, R.BottomRightX, R.BottomRightY);
    cairo_arc(FCairo, 0, 0, 1, 0, Pi / 2);
    cairo_restore(FCairo);
  end
  else
    cairo_line_to(FCairo, X + W, Y + H);

  // Bottom edge to bottom-left corner
  cairo_line_to(FCairo, X + R.BottomLeftX, Y + H);

  // Bottom-left arc
  if (R.BottomLeftX > 0) and (R.BottomLeftY > 0) then
  begin
    cairo_save(FCairo);
    cairo_translate(FCairo, X + R.BottomLeftX, Y + H - R.BottomLeftY);
    cairo_scale(FCairo, R.BottomLeftX, R.BottomLeftY);
    cairo_arc(FCairo, 0, 0, 1, Pi / 2, Pi);
    cairo_restore(FCairo);
  end
  else
    cairo_line_to(FCairo, X, Y + H);

  cairo_close_path(FCairo);
end;

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

constructor TPixieCairoCanvas.Create;
var
  FontMap: PPangoFontMap;
begin
  inherited Create;
  FCairo := nil;
  FPangoContext := nil;
  FPersistentContext := nil;
  FViewWidth := 800;
  FViewHeight := 600;
  FStateTop := 0;

  // Create a persistent Pango context for font metrics and text measurement
  // that works outside of BeginPaint/EndPaint
  FontMap := pango_cairo_font_map_get_default;
  if FontMap <> nil then
    FPersistentContext := pango_cairo_font_map_create_context(
      PPangoCairoFontMap(FontMap));
  FPangoContext := FPersistentContext;
end;

destructor TPixieCairoCanvas.Destroy;
begin
  if FPersistentContext <> nil then
    g_object_unref(FPersistentContext);
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

procedure TPixieCairoCanvas.BeginPaint(DC: PtrUInt);
{$IFDEF LCLGtk2}
var
  DevCtx: TGtkDeviceContext;
{$ENDIF}
{$IFDEF LCLGtk3}
var
  OrigCairo: Pcairo_t;
  Matrix: cairo_matrix_t;
  ClipX1, ClipY1, ClipX2, ClipY2: Double;
{$ENDIF}
begin
  FStateTop := 0;

  {$IFDEF LCLGtk2}
  DevCtx := TGtkDeviceContext(DC);
  FCairo := gdk_cairo_create(DevCtx.Drawable);
  {$ENDIF}
  {$IFDEF LCLGtk3}
  OrigCairo := Pcairo_t(Pointer(TGtk3DeviceContext(DC).pcr));
  FCairo := cairo_create(cairo_get_target(OrigCairo));
  // Copy the transform and clip from the original context so we
  // paint at the correct origin and don't damage sibling controls.
  cairo_get_matrix(OrigCairo, @Matrix);
  cairo_set_matrix(FCairo, @Matrix);
  cairo_clip_extents(OrigCairo, @ClipX1, @ClipY1, @ClipX2, @ClipY2);
  cairo_rectangle(FCairo, ClipX1, ClipY1,
    ClipX2 - ClipX1, ClipY2 - ClipY1);
  cairo_clip(FCairo);
  {$ENDIF}

  if FCairo = nil then Exit;

  // Apply scale transform
  cairo_scale(FCairo, FScale, FScale);

  // Update the persistent Pango context to match current Cairo transform
  if FPersistentContext <> nil then
    pango_cairo_update_context(FCairo, FPersistentContext);
  FPangoContext := FPersistentContext;
end;

procedure TPixieCairoCanvas.EndPaint;
begin
  if FCairo <> nil then
  begin
    cairo_destroy(FCairo);
    FCairo := nil;
  end;
  // FPangoContext stays as FPersistentContext (not freed per-paint)
end;

// ---------------------------------------------------------------------------
// State save/restore
// ---------------------------------------------------------------------------

procedure TPixieCairoCanvas.SaveState;
begin
  if (FCairo = nil) or (FStateTop > High(FStateStack)) then Exit;

  cairo_save(FCairo);
  FStateStack[FStateTop].ClipsPushed := 0;
  Inc(FStateTop);
end;

procedure TPixieCairoCanvas.RestoreState;
var
  I: Integer;
begin
  if (FCairo = nil) or (FStateTop <= 0) then Exit;
  Dec(FStateTop);

  // Each clip pushed its own cairo_save, undo them
  for I := 0 to FStateStack[FStateTop].ClipsPushed - 1 do
    cairo_restore(FCairo);

  // Undo the SaveState's cairo_save
  cairo_restore(FCairo);
end;

procedure TPixieCairoCanvas.PushOpacity(AOpacity: Single);
begin
  if (FCairo = nil) or (FOpacityTop > High(FOpacityStack)) then Exit;
  FOpacityStack[FOpacityTop].Value := AOpacity;
  Inc(FOpacityTop);
  cairo_push_group(FCairo);
end;

procedure TPixieCairoCanvas.PopOpacity;
var
  Alpha: Single;
begin
  if (FCairo = nil) or (FOpacityTop <= 0) then Exit;
  Dec(FOpacityTop);
  Alpha := FOpacityStack[FOpacityTop].Value;
  cairo_pop_group_to_source(FCairo);
  cairo_paint_with_alpha(FCairo, Alpha);
end;

procedure TPixieCairoCanvas.PushMask(MaskHandle: TPixieImageHandle;
  MaskX, MaskY, MaskW, MaskH: Single);
var
  Img: TPixieCairoImage;
  MaskPixels: PByte;
  MaskPitch, BufSize, I: Integer;
  MaskSurface: Pcairo_surface_t;
begin
  if (FCairo = nil) or (MaskHandle = 0) or
     (FMaskTop > High(FMaskStack)) then Exit;
  Img := TPixieCairoImage(MaskHandle);
  if (Img.Surface = nil) or (Img.ImgWidth = 0) or (Img.ImgHeight = 0) then Exit;

  // Create a separate mask surface with luminance→alpha conversion.
  // Cairo's cairo_mask_surface uses the A channel, but grayscale PNGs
  // have A=255 everywhere with luminance in RGB — must convert.
  MaskPitch := Img.ImgWidth * 4;
  BufSize := MaskPitch * Img.ImgHeight;
  GetMem(MaskPixels, BufSize);
  if Img.PixelData <> nil then
    Move(Img.PixelData^, MaskPixels^, BufSize)
  else
  begin
    FreeMem(MaskPixels);
    Exit;
  end;
  // ARGB32 layout (native endian): B=P[0], G=P[1], R=P[2], A=P[3]
  for I := 0 to Img.ImgWidth * Img.ImgHeight - 1 do
  begin
    MaskPixels[I * 4 + 3] := MaskPixels[I * 4 + 2]; // A = R (luminance)
    MaskPixels[I * 4 + 0] := 0;
    MaskPixels[I * 4 + 1] := 0;
    MaskPixels[I * 4 + 2] := 0;
  end;
  MaskSurface := cairo_image_surface_create_for_data(
    MaskPixels, CAIRO_FORMAT_ARGB32, Img.ImgWidth, Img.ImgHeight, MaskPitch);

  FMaskStack[FMaskTop].Surface := MaskSurface;
  FMaskStack[FMaskTop].Pixels := MaskPixels;
  FMaskStack[FMaskTop].X := MaskX;
  FMaskStack[FMaskTop].Y := MaskY;
  FMaskStack[FMaskTop].W := MaskW;
  FMaskStack[FMaskTop].H := MaskH;
  FMaskStack[FMaskTop].ImgW := Img.ImgWidth;
  FMaskStack[FMaskTop].ImgH := Img.ImgHeight;
  Inc(FMaskTop);
  cairo_push_group(FCairo);
end;

procedure TPixieCairoCanvas.PopMask;
var
  Entry: TPixieCairoMaskEntry;
begin
  if (FCairo = nil) or (FMaskTop <= 0) then Exit;
  Dec(FMaskTop);
  Entry := FMaskStack[FMaskTop];
  cairo_pop_group_to_source(FCairo);

  // Apply mask: scale mask surface to cover MaskX,MaskY,MaskW,MaskH
  cairo_save(FCairo);
  cairo_translate(FCairo, Entry.X, Entry.Y);
  if (Entry.W > 0) and (Entry.H > 0) then
    cairo_scale(FCairo, Entry.W / Entry.ImgW, Entry.H / Entry.ImgH);
  cairo_mask_surface(FCairo, Entry.Surface, 0, 0);
  cairo_restore(FCairo);

  cairo_surface_destroy(Entry.Surface);
  FreeMem(Entry.Pixels);
end;

function TPixieCairoCanvas.SetBlendMode(Mode: TPixieBlendMode): Boolean;
const
  CairoOps: array[TPixieBlendMode] of cairo_operator_t = (
    CAIRO_OPERATOR_OVER,           // bmNormal
    CAIRO_OPERATOR_MULTIPLY,       // bmMultiply
    CAIRO_OPERATOR_SCREEN,         // bmScreen
    CAIRO_OPERATOR_OVERLAY,        // bmOverlay
    CAIRO_OPERATOR_DARKEN,         // bmDarken
    CAIRO_OPERATOR_LIGHTEN,        // bmLighten
    CAIRO_OPERATOR_COLOR_DODGE,    // bmColorDodge
    CAIRO_OPERATOR_COLOR_BURN,     // bmColorBurn
    CAIRO_OPERATOR_HARD_LIGHT,     // bmHardLight
    CAIRO_OPERATOR_SOFT_LIGHT,     // bmSoftLight
    CAIRO_OPERATOR_DIFFERENCE,     // bmDifference
    CAIRO_OPERATOR_EXCLUSION,      // bmExclusion
    CAIRO_OPERATOR_HSL_HUE,        // bmHue
    CAIRO_OPERATOR_HSL_SATURATION, // bmSaturation
    CAIRO_OPERATOR_HSL_COLOR,      // bmColor
    CAIRO_OPERATOR_HSL_LUMINOSITY  // bmLuminosity
  );
begin
  Result := FCairo <> nil;
  if Result then
    cairo_set_operator(FCairo, CairoOps[Mode]);
end;

procedure TPixieCairoCanvas.ResetBlendMode;
begin
  if FCairo <> nil then
    cairo_set_operator(FCairo, CAIRO_OPERATOR_OVER);
end;

// ---------------------------------------------------------------------------
// Clipping
// ---------------------------------------------------------------------------

procedure TPixieCairoCanvas.SetClipRect(const R: TPixiePosition;
  const Radius: TPixieBorderRadiuses);
begin
  if FCairo = nil then Exit;

  // Each clip gets its own cairo_save so it can be independently undone
  cairo_save(FCairo);

  if Radius.HasRadius then
  begin
    RoundedRectPath(R.X, R.Y, R.Width, R.Height, Radius);
    cairo_clip(FCairo);
  end
  else
  begin
    cairo_rectangle(FCairo, R.X, R.Y, R.Width, R.Height);
    cairo_clip(FCairo);
  end;

  if FStateTop > 0 then
    Inc(FStateStack[FStateTop - 1].ClipsPushed);
end;

// ---------------------------------------------------------------------------
// Solid fills
// ---------------------------------------------------------------------------

procedure TPixieCairoCanvas.FillRect(X, Y, W, H: Single;
  Color: TPixieWebColor);
begin
  if (FCairo = nil) or (Color.Alpha = 0) then Exit;
  SetSourceColor(Color);
  cairo_rectangle(FCairo, X, Y, W, H);
  cairo_fill(FCairo);
end;

procedure TPixieCairoCanvas.FillRoundedRect(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses; Color: TPixieWebColor);
begin
  if (FCairo = nil) or (Color.Alpha = 0) then Exit;
  SetSourceColor(Color);

  if Radius.HasRadius then
  begin
    RoundedRectPath(X, Y, W, H, Radius);
    cairo_fill(FCairo);
  end
  else
  begin
    cairo_rectangle(FCairo, X, Y, W, H);
    cairo_fill(FCairo);
  end;
end;

// ---------------------------------------------------------------------------
// Gradients
// ---------------------------------------------------------------------------

procedure TPixieCairoCanvas.FillLinearGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieLinearGradientLayer);
var
  Pattern: Pcairo_pattern_t;
  I: Integer;
  Cp: TPixieColorPoint;
begin
  if (FCairo = nil) or (Gradient = nil) then Exit;
  if Gradient.ColorPoints.Count < 2 then Exit;

  Pattern := cairo_pattern_create_linear(
    Gradient.StartPt.X, Gradient.StartPt.Y,
    Gradient.EndPt.X, Gradient.EndPt.Y);
  try
    for I := 0 to Gradient.ColorPoints.Count - 1 do
    begin
      Cp := Gradient.ColorPoints[I];
      cairo_pattern_add_color_stop_rgba(Pattern, Cp.Offset,
        Cp.Color.Red / 255.0, Cp.Color.Green / 255.0,
        Cp.Color.Blue / 255.0, Cp.Color.Alpha / 255.0);
    end;

    cairo_set_source(FCairo, Pattern);

    if Radius.HasRadius then
    begin
      RoundedRectPath(X, Y, W, H, Radius);
      cairo_fill(FCairo);
    end
    else
    begin
      cairo_rectangle(FCairo, X, Y, W, H);
      cairo_fill(FCairo);
    end;
  finally
    cairo_pattern_destroy(Pattern);
  end;
end;

procedure TPixieCairoCanvas.FillRadialGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieRadialGradientLayer);
var
  Pattern: Pcairo_pattern_t;
  I: Integer;
  Cp: TPixieColorPoint;
  Cx, Cy, Rx, Ry, MaxR: Single;
begin
  if (FCairo = nil) or (Gradient = nil) then Exit;
  if Gradient.ColorPoints.Count < 2 then Exit;

  Cx := Gradient.Position.X;
  Cy := Gradient.Position.Y;
  Rx := Gradient.Radius.X;
  Ry := Gradient.Radius.Y;
  if (Rx < 0.001) or (Ry < 0.001) then Exit;

  // Cairo only supports circular radial gradients; use scale to simulate
  // an elliptical one. We scale Y axis by Ry/Rx to map circle to ellipse.
  MaxR := Rx;

  Pattern := cairo_pattern_create_radial(Cx, Cy * Rx / Ry, 0,
    Cx, Cy * Rx / Ry, MaxR);
  try
    for I := 0 to Gradient.ColorPoints.Count - 1 do
    begin
      Cp := Gradient.ColorPoints[I];
      cairo_pattern_add_color_stop_rgba(Pattern, Cp.Offset,
        Cp.Color.Red / 255.0, Cp.Color.Green / 255.0,
        Cp.Color.Blue / 255.0, Cp.Color.Alpha / 255.0);
    end;

    cairo_save(FCairo);
    try
      // Scale Y to form ellipse
      cairo_scale(FCairo, 1.0, Ry / Rx);
      cairo_set_source(FCairo, Pattern);

      // Clip to target rect (in scaled coordinates)
      if Radius.HasRadius then
      begin
        RoundedRectPath(X, Y * Rx / Ry, W, H * Rx / Ry, Radius);
        cairo_fill(FCairo);
      end
      else
      begin
        cairo_rectangle(FCairo, X, Y * Rx / Ry, W, H * Rx / Ry);
        cairo_fill(FCairo);
      end;
    finally
      cairo_restore(FCairo);
    end;
  finally
    cairo_pattern_destroy(Pattern);
  end;
end;

procedure TPixieCairoCanvas.FillConicGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieConicGradientLayer);
var
  Count, I, J, Steps: Integer;
  Cx, Cy, MaxR, Angle, Frac: Single;
  Cp: TPixieColorPoint;
  C: TPixieWebColor;
  StartAngle, SweepAngle, CosA, SinA, CosB, SinB: Single;
begin
  // Cairo has no native conic gradient — approximate with pie sectors
  if (FCairo = nil) or (Gradient = nil) then Exit;
  Count := Gradient.ColorPoints.Count;
  if Count < 2 then Exit;

  Cx := Gradient.Position.X;
  Cy := Gradient.Position.Y;
  MaxR := Max(Max(Abs(X + W - Cx), Abs(X - Cx)),
              Max(Abs(Y + H - Cy), Abs(Y - Cy))) * 1.5;
  if MaxR < 1 then MaxR := 1;

  SaveState;
  try
    if Radius.HasRadius then
      SetClipRect(TPixiePosition.Create(X, Y, W, H), Radius)
    else
    begin
      cairo_save(FCairo);
      cairo_rectangle(FCairo, X, Y, W, H);
      cairo_clip(FCairo);
      if FStateTop > 0 then
        Inc(FStateStack[FStateTop - 1].ClipsPushed);
    end;

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

      SetSourceColor(C);

      // Build pie sector as a triangle fan segment
      StartAngle := (Gradient.Angle - 90 + J * (360.0 / Steps)) * Pi / 180.0;

      SinCos(StartAngle, SinA, CosA);
      SinCos(StartAngle + SweepAngle, SinB, CosB);

      cairo_new_path(FCairo);
      cairo_move_to(FCairo, Cx, Cy);
      cairo_line_to(FCairo, Cx + CosA * MaxR, Cy + SinA * MaxR);
      cairo_line_to(FCairo, Cx + CosB * MaxR, Cy + SinB * MaxR);
      cairo_close_path(FCairo);
      cairo_fill(FCairo);
    end;
  finally
    RestoreState;
  end;
end;

// ---------------------------------------------------------------------------
// Borders
// ---------------------------------------------------------------------------

procedure TPixieCairoCanvas.DrawBorderSide(const Border: TPixieBorder;
  X1, Y1, X2, Y2: Single);
var
  LineW, Offset, Dx, Dy, Len, Nx, Ny: Single;
  Dashes: array[0..1] of Double;
begin
  if (Border.Width <= 0) or (Border.Style = bsNone) or
     (Border.Style = bsHidden) then
    Exit;

  SetSourceColor(Border.Color);

  // Double border: two lines of width/3 separated by width/3 gap
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

    cairo_set_line_width(FCairo, LineW);
    // Outer line
    cairo_move_to(FCairo, X1 - Nx * Offset, Y1 - Ny * Offset);
    cairo_line_to(FCairo, X2 - Nx * Offset, Y2 - Ny * Offset);
    cairo_stroke(FCairo);
    // Inner line
    cairo_move_to(FCairo, X1 + Nx * Offset, Y1 + Ny * Offset);
    cairo_line_to(FCairo, X2 + Nx * Offset, Y2 + Ny * Offset);
    cairo_stroke(FCairo);
    Exit;
  end;

  cairo_set_line_width(FCairo, Border.Width);

  case Border.Style of
    bsDotted:
    begin
      cairo_set_line_cap(FCairo, CAIRO_LINE_CAP_ROUND);
      Dashes[0] := 0;
      Dashes[1] := Border.Width * 2;
      cairo_set_dash(FCairo, @Dashes[0], 2, 0);
    end;
    bsDashed:
    begin
      Dashes[0] := Border.Width * 3;
      Dashes[1] := Border.Width * 3;
      cairo_set_dash(FCairo, @Dashes[0], 2, 0);
    end;
  else
    cairo_set_dash(FCairo, nil, 0, 0);
  end;

  cairo_move_to(FCairo, X1, Y1);
  cairo_line_to(FCairo, X2, Y2);
  cairo_stroke(FCairo);

  // Reset dash and line cap
  if Border.Style = bsDotted then
    cairo_set_line_cap(FCairo, CAIRO_LINE_CAP_BUTT);
  cairo_set_dash(FCairo, nil, 0, 0);
end;

procedure TPixieCairoCanvas.DrawBorders(const Borders: TPixieBorders;
  const Pos: TPixiePosition; IsRoot: Boolean);
var
  X, Y, W, H: Single;
begin
  if FCairo = nil then Exit;
  if not Borders.IsVisible then Exit;

  X := Pos.X;
  Y := Pos.Y;
  W := Pos.Width;
  H := Pos.Height;

  if Borders.Radius.HasRadius then
  begin
    if (Borders.Top.Width > 0) and (Borders.Top.Style <> bsNone) then
    begin
      SetSourceColor(Borders.Top.Color);
      cairo_set_line_width(FCairo, Borders.Top.Width);
      RoundedRectPath(X, Y, W, H, Borders.Radius);
      cairo_stroke(FCairo);
      Exit;
    end;
  end;

  // Top
  DrawBorderSide(Borders.Top,
    X, Y + Borders.Top.Width / 2,
    X + W, Y + Borders.Top.Width / 2);

  // Right
  DrawBorderSide(Borders.Right,
    X + W - Borders.Right.Width / 2, Y,
    X + W - Borders.Right.Width / 2, Y + H);

  // Bottom
  DrawBorderSide(Borders.Bottom,
    X, Y + H - Borders.Bottom.Width / 2,
    X + W, Y + H - Borders.Bottom.Width / 2);

  // Left
  DrawBorderSide(Borders.Left,
    X + Borders.Left.Width / 2, Y,
    X + Borders.Left.Width / 2, Y + H);
end;

// ---------------------------------------------------------------------------
// Font management
// ---------------------------------------------------------------------------

function TPixieCairoCanvas.CreateFont(
  const Descr: TPixieFontDescription;
  out Metrics: TPixieFontMetrics): TPixieFontHandle;
var
  Info: TPixieCairoFont;
  PFontDesc: PPangoFontDescription;
  PMetrics: PPangoFontMetrics;
  PangoAscent, PangoDescent: Integer;
  ResolvedFamily: string;
begin
  Result := 0;

  Info := TPixieCairoFont.Create;
  Info.DecorationLine := Descr.DecorationLine;

  PFontDesc := pango_font_description_new;

  // Resolve CSS font-family list
  GCheckFontContext := FPersistentContext;
  ResolvedFamily := PixieResolveFontFamily(Descr.Family, CheckCairoFont);
  pango_font_description_set_family(PFontDesc, PAnsiChar(ResolvedFamily));

  // Set size (Descr.Size is in pixels; use absolute size which is device units)
  pango_font_description_set_absolute_size(PFontDesc,
    Descr.Size * PANGO_SCALE);

  // Set weight (CSS weights map directly to Pango weights)
  pango_font_description_set_weight(PFontDesc, Descr.Weight);

  // Set style
  if Descr.Style = fstItalic then
    pango_font_description_set_style(PFontDesc, PANGO_STYLE_ITALIC)
  else
    pango_font_description_set_style(PFontDesc, PANGO_STYLE_NORMAL);

  // Set variant (Pango synthesises small-caps if the font lacks native support)
  if Descr.Variant = fvSmallCaps then
    pango_font_description_set_variant(PFontDesc, PANGO_VARIANT_SMALL_CAPS);

  Info.FontDesc := PFontDesc;

  // Get metrics from Pango context if available
  if FPangoContext <> nil then
  begin
    PMetrics := pango_context_get_metrics(FPangoContext, PFontDesc, nil);
    if PMetrics <> nil then
    begin
      PangoAscent := pango_font_metrics_get_ascent(PMetrics);
      PangoDescent := pango_font_metrics_get_descent(PMetrics);
      Metrics.Ascent := PangoAscent / PANGO_SCALE;
      Metrics.Descent := PangoDescent / PANGO_SCALE;
      Metrics.Height := (PangoAscent + PangoDescent) / PANGO_SCALE;
      Metrics.XHeight := Descr.Size * 0.5;
      pango_font_metrics_unref(PMetrics);
    end
    else
    begin
      Metrics.Height := Descr.Size * 1.2;
      Metrics.Ascent := Descr.Size * 0.8;
      Metrics.Descent := Metrics.Height - Metrics.Ascent;
      Metrics.XHeight := Descr.Size * 0.5;
    end;
  end
  else
  begin
    // Fallback when no Pango context (before BeginPaint)
    Metrics.Height := Descr.Size * 1.2;
    Metrics.Ascent := Descr.Size * 0.8;
    Metrics.Descent := Metrics.Height - Metrics.Ascent;
    Metrics.XHeight := Descr.Size * 0.5;
  end;

  Metrics.FontSize := Descr.Size;
  Metrics.ChWidth := Descr.Size * 0.6;
  Metrics.DrawSpaces := True;
  Metrics.CalcShifts;
  Info.Metrics := Metrics;

  Result := TPixieFontHandle(Info);
end;

procedure TPixieCairoCanvas.DoDeleteFont(Handle: TPixieFontHandle);
begin
  if Handle <> 0 then
    TPixieCairoFont(Handle).Free;
end;

function TPixieCairoCanvas.DoMeasureText(const Text: string;
  Handle: TPixieFontHandle): TPixiePixel;
var
  Info: TPixieCairoFont;
  Layout: PPangoLayout;
  PW, PH: LongInt;
begin
  Result := 0;
  if (Handle = 0) or (FPangoContext = nil) then Exit;
  Info := TPixieCairoFont(Handle);
  if Info.FontDesc = nil then
  begin
    Result := Length(Text) * Info.Metrics.ChWidth;
    Exit;
  end;

  Layout := pango_layout_new(FPangoContext);
  try
    pango_layout_set_font_description(Layout, Info.FontDesc);
    pango_layout_set_text(Layout, PAnsiChar(Text), -1);
    pango_layout_set_width(Layout, -1); // no wrap
    pango_layout_get_pixel_size(Layout, @PW, @PH);
    Result := PW;
  finally
    g_object_unref(Layout);
  end;
end;

procedure TPixieCairoCanvas.DrawText(const Text: string;
  Handle: TPixieFontHandle; Color: TPixieWebColor;
  X, Y, W, H: Single);
var
  Info: TPixieCairoFont;
  Layout: PPangoLayout;
begin
  if (Handle = 0) or (FCairo = nil) then Exit;
  Info := TPixieCairoFont(Handle);
  if Info.FontDesc = nil then Exit;

  Layout := pango_cairo_create_layout(FCairo);
  try
    pango_layout_set_font_description(Layout, Info.FontDesc);
    pango_layout_set_text(Layout, PAnsiChar(Text), -1);
    pango_layout_set_width(Layout, -1);

    // Text decoration is drawn at the element level (TPixieHtmlTag.DrawBackground)

    SetSourceColor(Color);
    cairo_move_to(FCairo, X, Y);
    pango_cairo_show_layout(FCairo, Layout);
  finally
    g_object_unref(Layout);
  end;
end;

procedure TPixieCairoCanvas.StrokeTextAtBaseline(const Text: string;
  Handle: TPixieFontHandle; const Metrics: TPixieFontMetrics;
  Color: TPixieWebColor; Width: Single; X, BaselineY: Single);
var
  Info: TPixieCairoFont;
  Layout: PPangoLayout;
begin
  if (Handle = 0) or (FCairo = nil) or (Width <= 0) then Exit;
  Info := TPixieCairoFont(Handle);
  if Info.FontDesc = nil then Exit;

  Layout := pango_cairo_create_layout(FCairo);
  try
    pango_layout_set_font_description(Layout, Info.FontDesc);
    pango_layout_set_text(Layout, PAnsiChar(Text), -1);
    pango_layout_set_width(Layout, -1);

    // Position at baseline
    cairo_move_to(FCairo, X, BaselineY - Metrics.Ascent);
    // Convert text layout to path, then stroke
    pango_cairo_layout_path(FCairo, Layout);
    SetSourceColor(Color);
    cairo_set_line_width(FCairo, Width);
    cairo_stroke(FCairo);
  finally
    g_object_unref(Layout);
  end;
end;

function TPixieCairoCanvas.PtToPx(Pt: Single): TPixiePixel;
begin
  Result := Trunc(Pt * 96.0 / 72.0);
end;

// ---------------------------------------------------------------------------
// Image
// ---------------------------------------------------------------------------

function TPixieCairoCanvas.DecodeImageFile(
  const Path: string): TPixieImageHandle;
var
  Pic: TPicture;
  Bmp: TBitmap;
  RawImage: TLazIntfImage;
  PixelBuf: PByte;
  Pitch, ImgW, ImgH: Integer;
begin
  Result := 0;

  Pic := TPicture.Create;
  try
    try
      Pic.LoadFromFile(Path);
    except
      // TPicture picks its reader by file extension, so it raises when the
      // extension misreports the format. Retry decoding by actual content
      // (the FPImage readers match on magic bytes) — issue #266.
      Result := DecodeImageByContent(Path);
      Exit;
    end;

    ImgW := Pic.Width;
    ImgH := Pic.Height;
    if (ImgW <= 0) or (ImgH <= 0) then Exit;

    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(ImgW, ImgH);
      Bmp.Canvas.Draw(0, 0, Pic.Graphic);

      RawImage := Bmp.CreateIntfImage;
      try
        ConvertFPImageToBGRA(RawImage, PixelBuf, ImgW, ImgH, Pitch);
        if PixelBuf <> nil then
          Result := NewCairoImageFromBuffer(PixelBuf, ImgW, ImgH, Pitch);
      finally
        RawImage.Free;
      end;
    finally
      Bmp.Free;
    end;
  finally
    Pic.Free;
  end;
end;

// Decode a raster file by its actual content (the FPImage readers identify
// the format from its magic bytes, not the file extension) and build a
// premultiplied BGRA Cairo surface. Used as a fallback when the extension
// misreports the format, so a JPEG saved as .png still renders (issue #266).
function TPixieCairoCanvas.DecodeImageByContent(
  const Path: string): TPixieImageHandle;
var
  Stream: TFileStream;
  Img: TFPMemoryImage;
  Pixels: PByte;
  Pitch, W, H: Integer;
begin
  Result := 0;
  Pixels := nil;
  Img := TFPMemoryImage.Create(0, 0);
  try
    try
      Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
      try
        Img.LoadFromStream(Stream);
      finally
        Stream.Free;
      end;
      ConvertFPImageToBGRA(Img, Pixels, W, H, Pitch);
    except
      // Any failure (unreadable, unknown format, bad dimensions) degrades to
      // no image rather than raising into the layout/render pass.
      if Pixels <> nil then FreeMem(Pixels);
      Exit;
    end;
    // The buffer is freshly owned, so hand it to the surface directly rather
    // than through LoadImageFromPixels, which would copy it.
    if Pixels <> nil then
      Result := NewCairoImageFromBuffer(Pixels, W, H, Pitch);
  finally
    Img.Free;
  end;
end;

function TPixieCairoCanvas.NewCairoImageFromBuffer(
  Buf: PByte; W, H, Pitch: Integer): TPixieImageHandle;
var
  Info: TPixieCairoImage;
begin
  Info := TPixieCairoImage.Create;
  Info.Surface := cairo_image_surface_create_for_data(
    Buf, CAIRO_FORMAT_ARGB32, W, H, Pitch);
  Info.PixelData := Buf;
  Info.ImgWidth := W;
  Info.ImgHeight := H;
  Result := TPixieImageHandle(Info);
end;

function TPixieCairoCanvas.LoadSvgFile(
  const Path: string): TPixieImageHandle;
var
  Stream: TFileStream;
  Buf: Pointer;
  BufSize: Integer;
begin
  Result := 0;
  if not FileExists(Path) then Exit;
  try
    Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
    try
      BufSize := Stream.Size;
      if BufSize <= 0 then Exit;
      GetMem(Buf, BufSize);
      try
        Stream.ReadBuffer(Buf^, BufSize);
        Result := LoadSvgFromData(Buf, BufSize);
      finally
        FreeMem(Buf);
      end;
    finally
      Stream.Free;
    end;
  except
  end;
end;

function TPixieCairoCanvas.LoadSvgFromData(Data: Pointer;
  Size: Integer): TPixieImageHandle;
var
  Info: TPixieCairoImage;
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

  Info := TPixieCairoImage.Create;
  Info.SvgRenderer := Renderer;
  Info.ImgWidth := Round(W);
  Info.ImgHeight := Round(H);
  Info.AspectOnly := not Renderer.HasExplicitSize;
  Info.AspectRatio := Renderer.GetAspectRatio;
  Result := TPixieImageHandle(Info);
end;

function TPixieCairoCanvas.LoadImage(
  const Path: string): TPixieImageHandle;
var
  Info: TPixieCairoImage;
  Resolved: string;
  Surface: Pcairo_surface_t;
begin
  Result := 0;

  Resolved := ExpandFileName(Path);
  if not FileExists(Resolved) then Exit;

  // SVG — render via canvas SVG renderer
  if LowerCase(ExtractFileExt(Resolved)) = '.svg' then
  begin
    Result := LoadSvgFile(Resolved);
    Exit;
  end;

  // Try PNG first (native Cairo support). cairo_image_surface_create_from_png
  // returns a non-nil surface even on failure, so check its status: a file
  // with a .png extension that is not actually a PNG (e.g. a JPEG saved as
  // .png) yields an error surface here. Fall through to the content-sniffing
  // decode path rather than returning a blank image (issue #266).
  if LowerCase(ExtractFileExt(Resolved)) = '.png' then
  begin
    Surface := cairo_image_surface_create_from_png(
      PAnsiChar(Resolved));
    if (Surface <> nil) and
       (cairo_surface_status(Surface) = CAIRO_STATUS_SUCCESS) then
    begin
      Info := TPixieCairoImage.Create;
      Info.Surface := Surface;
      Info.ImgWidth := cairo_image_surface_get_width(Surface);
      Info.ImgHeight := cairo_image_surface_get_height(Surface);
      Result := TPixieImageHandle(Info);
      Exit;
    end;
    if Surface <> nil then
      cairo_surface_destroy(Surface);
    // A .png Cairo rejected is almost always a file whose extension lies
    // about its format (e.g. a JPEG saved as .png). Decode it by content
    // directly — the extension-based TPicture path would only fail again.
    Result := DecodeImageByContent(Resolved);
    Exit;
  end;

  // Other formats: decode via LCL
  Result := DecodeImageFile(Resolved);

  // LCL failed — try libwebp for .webp files
  if (Result = 0) and
     (LowerCase(ExtractFileExt(Resolved)) = '.webp') then
    Result := LoadWebPFile(Resolved);
end;

function TPixieCairoCanvas.LoadImageFromPixels(Width, Height: Integer;
  Pixels: Pointer; Pitch: Integer): TPixieImageHandle;
var
  BufSize: Integer;
  PixelCopy: Pointer;
begin
  Result := 0;
  if (Width <= 0) or (Height <= 0) or (Pixels = nil) then Exit;

  // Cairo needs the pixel buffer to remain valid for the surface lifetime,
  // so we make our own copy
  BufSize := Pitch * Height;
  GetMem(PixelCopy, BufSize);
  Move(Pixels^, PixelCopy^, BufSize);

  Result := NewCairoImageFromBuffer(PByte(PixelCopy), Width, Height, Pitch);
end;

procedure TPixieCairoCanvas.FreeImage(Handle: TPixieImageHandle);
begin
  if Handle <> 0 then
    TPixieCairoImage(Handle).Free;
end;

procedure TPixieCairoCanvas.GetImageSize(Handle: TPixieImageHandle;
  out W, H: Single);
var
  Info: TPixieCairoImage;
begin
  W := 0;
  H := 0;
  if Handle = 0 then Exit;
  Info := TPixieCairoImage(Handle);
  W := Info.ImgWidth;
  H := Info.ImgHeight;
end;

function TPixieCairoCanvas.GetImageAspectInfo(Handle: TPixieImageHandle;
  out AspectRatio: Single): Boolean;
var
  Info: TPixieCairoImage;
begin
  AspectRatio := 0;
  Result := False;
  if Handle = 0 then Exit;
  Info := TPixieCairoImage(Handle);
  Result := Info.AspectOnly;
  if Result then
    AspectRatio := Info.AspectRatio;
end;

procedure TPixieCairoCanvas.DrawImage(Handle: TPixieImageHandle;
  DstX, DstY, DstW, DstH: Single);
var
  Info: TPixieCairoImage;
  Sx, Sy: Double;
begin
  if (Handle = 0) or (FCairo = nil) then Exit;
  Info := TPixieCairoImage(Handle);
  if (Info.ImgWidth <= 0) or (Info.ImgHeight <= 0) then Exit;

  // SVG — re-render at destination size via canvas renderer
  if Info.SvgRenderer <> nil then
  begin
    TPixieSvgCanvasRenderer(Info.SvgRenderer).RenderToRect(
      DstX, DstY, DstW, DstH);
    Exit;
  end;

  // Raster image
  if Info.Surface = nil then Exit;

  Sx := DstW / Info.ImgWidth;
  Sy := DstH / Info.ImgHeight;

  cairo_save(FCairo);
  try
    cairo_translate(FCairo, DstX, DstY);
    cairo_scale(FCairo, Sx, Sy);
    cairo_set_source_surface(FCairo, Info.Surface, 0, 0);
    cairo_paint(FCairo);
  finally
    cairo_restore(FCairo);
  end;
end;

procedure TPixieCairoCanvas.FillTiledImage(Handle: TPixieImageHandle;
  TileX, TileY, TileW, TileH: Single;
  FillX, FillY, FillW, FillH: Single);
var
  Info: TPixieCairoImage;
  Pattern: Pcairo_pattern_t;
  Matrix: cairo_matrix_t;
begin
  if (Handle = 0) or (FCairo = nil) then Exit;
  Info := TPixieCairoImage(Handle);
  if (Info.ImgWidth <= 0) or (Info.ImgHeight <= 0) then Exit;

  // SVG images: fall back to base-class per-tile loop
  if Info.SvgRenderer <> nil then
  begin
    inherited;
    Exit;
  end;

  if Info.Surface = nil then Exit;
  if (TileW <= 0) or (TileH <= 0) then Exit;

  Pattern := cairo_pattern_create_for_surface(Info.Surface);
  try
    cairo_pattern_set_extend(Pattern, CAIRO_EXTEND_REPEAT);
    cairo_pattern_set_filter(Pattern, CAIRO_FILTER_BILINEAR);

    // Pattern matrix maps destination coords to pattern (image) coords.
    // We need: image_x = (dest_x - TileX) * (ImgW / TileW)
    //          image_y = (dest_y - TileY) * (ImgH / TileH)
    cairo_matrix_init(@Matrix,
      Info.ImgWidth / TileW, 0,
      0, Info.ImgHeight / TileH,
      -TileX * Info.ImgWidth / TileW,
      -TileY * Info.ImgHeight / TileH);
    cairo_pattern_set_matrix(Pattern, @Matrix);

    cairo_set_source(FCairo, Pattern);
    cairo_rectangle(FCairo, FillX, FillY, FillW, FillH);
    cairo_fill(FCairo);
  finally
    cairo_pattern_destroy(Pattern);
  end;
end;

// ---------------------------------------------------------------------------
// Simple shapes (list markers)
// ---------------------------------------------------------------------------

procedure TPixieCairoCanvas.FillEllipse(X, Y, W, H: Single;
  Color: TPixieWebColor);
begin
  if (FCairo = nil) or (Color.Alpha = 0) then Exit;
  SetSourceColor(Color);

  cairo_save(FCairo);
  try
    cairo_translate(FCairo, X + W / 2, Y + H / 2);
    cairo_scale(FCairo, W / 2, H / 2);
    cairo_arc(FCairo, 0, 0, 1, 0, 2 * Pi);
    cairo_fill(FCairo);
  finally
    cairo_restore(FCairo);
  end;
end;

procedure TPixieCairoCanvas.DrawEllipse(X, Y, W, H: Single;
  Color: TPixieWebColor; StrokeWidth: Single);
var
  ScaleX, ScaleY: Single;
begin
  if (FCairo = nil) or (Color.Alpha = 0) then Exit;
  SetSourceColor(Color);

  ScaleX := W / 2;
  ScaleY := H / 2;

  cairo_save(FCairo);
  try
    cairo_translate(FCairo, X + ScaleX, Y + ScaleY);
    cairo_scale(FCairo, ScaleX, ScaleY);
    // Adjust line width to compensate for the scale transform
    if ScaleX > 0 then
      cairo_set_line_width(FCairo, StrokeWidth / ScaleX)
    else
      cairo_set_line_width(FCairo, StrokeWidth);
    cairo_arc(FCairo, 0, 0, 1, 0, 2 * Pi);
    cairo_stroke(FCairo);
  finally
    cairo_restore(FCairo);
  end;
end;

procedure TPixieCairoCanvas.DrawRect(X, Y, W, H: Single;
  Color: TPixieWebColor; StrokeWidth: Single);
begin
  if (FCairo = nil) or (Color.Alpha = 0) then Exit;
  SetSourceColor(Color);
  cairo_set_line_width(FCairo, StrokeWidth);
  cairo_rectangle(FCairo, X, Y, W, H);
  cairo_stroke(FCairo);
end;

procedure TPixieCairoCanvas.DrawLine(X1, Y1, X2, Y2: Single;
  Color: TPixieWebColor; StrokeWidth: Single;
  Style: TPixieTextDecorationStyle);
var
  Dashes: array[0..1] of Double;
begin
  if (FCairo = nil) or (Color.Alpha = 0) then Exit;
  SetSourceColor(Color);
  cairo_set_line_width(FCairo, StrokeWidth);
  if Style = tdsDotted then
  begin
    Dashes[0] := StrokeWidth;
    Dashes[1] := StrokeWidth * 2;
    cairo_set_dash(FCairo, @Dashes[0], 2, 0);
  end
  else if Style = tdsDashed then
  begin
    Dashes[0] := StrokeWidth * 3;
    Dashes[1] := StrokeWidth * 2;
    cairo_set_dash(FCairo, @Dashes[0], 2, 0);
  end;
  cairo_move_to(FCairo, X1, Y1);
  cairo_line_to(FCairo, X2, Y2);
  cairo_stroke(FCairo);
  if Style in [tdsDotted, tdsDashed] then
    cairo_set_dash(FCairo, nil, 0, 0);
end;

procedure TPixieCairoCanvas.StrokePolyline(const Points: array of Single;
  Color: TPixieWebColor; StrokeWidth: Single);
var
  Count, I: Integer;
begin
  Count := Length(Points) div 2;
  if (FCairo = nil) or (Color.Alpha = 0) or (Count < 2) then Exit;
  SetSourceColor(Color);
  cairo_set_line_width(FCairo, StrokeWidth);
  cairo_set_line_cap(FCairo, CAIRO_LINE_CAP_ROUND);
  cairo_set_line_join(FCairo, CAIRO_LINE_JOIN_ROUND);
  cairo_move_to(FCairo, Points[0], Points[1]);
  for I := 1 to Count - 1 do
    cairo_line_to(FCairo, Points[I * 2], Points[I * 2 + 1]);
  cairo_stroke(FCairo);
  cairo_set_line_cap(FCairo, CAIRO_LINE_CAP_BUTT);
  cairo_set_line_join(FCairo, CAIRO_LINE_JOIN_MITER);
end;

// ---------------------------------------------------------------------------
// Path API
// ---------------------------------------------------------------------------

procedure TPixieCairoCanvas.BeginPath;
begin
  if FCairo = nil then Exit;
  cairo_new_path(FCairo);
end;

procedure TPixieCairoCanvas.MoveTo(X, Y: Single);
begin
  if FCairo = nil then Exit;
  cairo_move_to(FCairo, X, Y);
end;

procedure TPixieCairoCanvas.LineTo(X, Y: Single);
begin
  if FCairo = nil then Exit;
  cairo_line_to(FCairo, X, Y);
end;

procedure TPixieCairoCanvas.CurveTo(X1, Y1, X2, Y2, X3, Y3: Single);
begin
  if FCairo = nil then Exit;
  cairo_curve_to(FCairo, X1, Y1, X2, Y2, X3, Y3);
end;

procedure TPixieCairoCanvas.ClosePath;
begin
  if FCairo = nil then Exit;
  cairo_close_path(FCairo);
end;

procedure TPixieCairoCanvas.FillPath(Color: TPixieWebColor;
  FillRule: TPixieFillRule);
begin
  if FCairo = nil then Exit;
  if Color.Alpha > 0 then
  begin
    SetSourceColor(Color);
    if FillRule = frEvenOdd then
      cairo_set_fill_rule(FCairo, CAIRO_FILL_RULE_EVEN_ODD)
    else
      cairo_set_fill_rule(FCairo, CAIRO_FILL_RULE_WINDING);
    cairo_fill(FCairo);
  end
  else
    cairo_new_path(FCairo);
end;

procedure TPixieCairoCanvas.StrokePath(Color: TPixieWebColor;
  Width: Single);
begin
  if FCairo = nil then Exit;
  if Color.Alpha > 0 then
  begin
    SetSourceColor(Color);
    cairo_set_line_width(FCairo, Width);
    if (FPathLineCap <> lcButt) or (FPathLineJoin <> ljMiter) then
    begin
      cairo_set_line_cap(FCairo, cairo_line_cap_t(Ord(FPathLineCap)));
      cairo_set_line_join(FCairo, cairo_line_join_t(Ord(FPathLineJoin)));
    end;
    ApplyDashPattern;
    cairo_stroke(FCairo);
    ClearDashPattern;
    if (FPathLineCap <> lcButt) or (FPathLineJoin <> ljMiter) then
    begin
      cairo_set_line_cap(FCairo, CAIRO_LINE_CAP_BUTT);
      cairo_set_line_join(FCairo, CAIRO_LINE_JOIN_MITER);
    end;
  end
  else
    cairo_new_path(FCairo);
end;

procedure TPixieCairoCanvas.FillAndStrokePath(FillColor: TPixieWebColor;
  StrokeColor: TPixieWebColor; StrokeWidth: Single;
  FillRule: TPixieFillRule);
begin
  if FCairo = nil then Exit;
  if FillRule = frEvenOdd then
    cairo_set_fill_rule(FCairo, CAIRO_FILL_RULE_EVEN_ODD)
  else
    cairo_set_fill_rule(FCairo, CAIRO_FILL_RULE_WINDING);
  if FillColor.Alpha > 0 then
  begin
    SetSourceColor(FillColor);
    cairo_fill_preserve(FCairo);
  end;
  if StrokeColor.Alpha > 0 then
  begin
    SetSourceColor(StrokeColor);
    cairo_set_line_width(FCairo, StrokeWidth);
    if (FPathLineCap <> lcButt) or (FPathLineJoin <> ljMiter) then
    begin
      cairo_set_line_cap(FCairo, cairo_line_cap_t(Ord(FPathLineCap)));
      cairo_set_line_join(FCairo, cairo_line_join_t(Ord(FPathLineJoin)));
    end;
    ApplyDashPattern;
    cairo_stroke(FCairo);
    ClearDashPattern;
    if (FPathLineCap <> lcButt) or (FPathLineJoin <> ljMiter) then
    begin
      cairo_set_line_cap(FCairo, CAIRO_LINE_CAP_BUTT);
      cairo_set_line_join(FCairo, CAIRO_LINE_JOIN_MITER);
    end;
  end
  else
    cairo_new_path(FCairo);
end;

procedure TPixieCairoCanvas.DiscardPath;
begin
  if FCairo <> nil then
    cairo_new_path(FCairo);
end;

procedure TPixieCairoCanvas.StrokePathLinearGradient(
  const Gradient: TPixieLinearGradientLayer; Width: Single);
var
  Pattern: Pcairo_pattern_t;
  I: Integer;
  Cp: TPixieColorPoint;
begin
  if (FCairo = nil) or (Gradient = nil) then Exit;
  if Gradient.ColorPoints.Count < 2 then
  begin
    cairo_new_path(FCairo);
    Exit;
  end;
  Pattern := cairo_pattern_create_linear(
    Gradient.StartPt.X, Gradient.StartPt.Y,
    Gradient.EndPt.X, Gradient.EndPt.Y);
  try
    for I := 0 to Gradient.ColorPoints.Count - 1 do
    begin
      Cp := Gradient.ColorPoints[I];
      cairo_pattern_add_color_stop_rgba(Pattern, Cp.Offset,
        Cp.Color.Red / 255.0, Cp.Color.Green / 255.0,
        Cp.Color.Blue / 255.0, Cp.Color.Alpha / 255.0);
    end;
    cairo_set_source(FCairo, Pattern);
    cairo_set_line_width(FCairo, Width);
    ApplyDashPattern;
    cairo_stroke(FCairo);
    ClearDashPattern;
  finally
    cairo_pattern_destroy(Pattern);
  end;
end;

procedure TPixieCairoCanvas.StrokePathRadialGradient(
  const Gradient: TPixieRadialGradientLayer; Width: Single);
var
  Pattern: Pcairo_pattern_t;
  I: Integer;
  Cp: TPixieColorPoint;
  Cx, Cy, Rx, Ry: Single;
begin
  if (FCairo = nil) or (Gradient = nil) then Exit;
  if Gradient.ColorPoints.Count < 2 then
  begin
    cairo_new_path(FCairo);
    Exit;
  end;
  Cx := Gradient.Position.X;
  Cy := Gradient.Position.Y;
  Rx := Gradient.Radius.X;
  Ry := Gradient.Radius.Y;
  if (Rx < 0.001) or (Ry < 0.001) then
  begin
    cairo_new_path(FCairo);
    Exit;
  end;
  Pattern := cairo_pattern_create_radial(Cx, Cy * Rx / Ry, 0,
    Cx, Cy * Rx / Ry, Rx);
  try
    for I := 0 to Gradient.ColorPoints.Count - 1 do
    begin
      Cp := Gradient.ColorPoints[I];
      cairo_pattern_add_color_stop_rgba(Pattern, Cp.Offset,
        Cp.Color.Red / 255.0, Cp.Color.Green / 255.0,
        Cp.Color.Blue / 255.0, Cp.Color.Alpha / 255.0);
    end;
    cairo_save(FCairo);
    try
      cairo_scale(FCairo, 1.0, Ry / Rx);
      cairo_set_source(FCairo, Pattern);
      cairo_set_line_width(FCairo, Width * Rx / Ry);
      ApplyDashPattern;
      cairo_stroke(FCairo);
    finally
      cairo_restore(FCairo);
    end;
  finally
    cairo_pattern_destroy(Pattern);
  end;
end;

procedure TPixieCairoCanvas.ClipPath(FillRule: TPixieFillRule);
begin
  if FCairo = nil then Exit;
  if FillRule = frEvenOdd then
    cairo_set_fill_rule(FCairo, CAIRO_FILL_RULE_EVEN_ODD)
  else
    cairo_set_fill_rule(FCairo, CAIRO_FILL_RULE_WINDING);
  cairo_clip(FCairo);
end;

procedure TPixieCairoCanvas.ConcatMatrix(A, B, C, D, E, F: Single);
var
  M: cairo_matrix_t;
begin
  if FCairo = nil then Exit;
  cairo_matrix_init(@M, A, B, C, D, E, F);
  cairo_transform(FCairo, @M);
end;

// ---------------------------------------------------------------------------
// Scale / View size
// ---------------------------------------------------------------------------

procedure TPixieCairoCanvas.SetViewSize(W, H: Integer; ACanvasScale: Single);
begin
  FViewWidth := W;
  FViewHeight := H;
end;

// ---------------------------------------------------------------------------
// Offscreen rendering (Cairo image surface)
// ---------------------------------------------------------------------------

procedure TPixieCairoCanvas.GetTransformScale(out ScaleX, ScaleY: Single);
var
  M: cairo_matrix_t;
begin
  if FCairo = nil then
  begin
    ScaleX := 1;
    ScaleY := 1;
    Exit;
  end;
  cairo_get_matrix(FCairo, @M);
  ScaleX := Sqrt(Sqr(M.xx) + Sqr(M.yx));
  ScaleY := Sqrt(Sqr(M.xy) + Sqr(M.yy));
end;

function TPixieCairoCanvas.BeginTileRender(Width, Height: Integer): Boolean;
begin
  Result := False;
  FTileSurface := cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Width, Height);
  if FTileSurface = nil then Exit;

  // Save current state
  FTileSavedCairo := FCairo;
  FTileSavedPangoCtx := FPangoContext;
  FTileSavedStateTop := FStateTop;
  FTileSavedViewW := FViewWidth;
  FTileSavedViewH := FViewHeight;

  FCairo := cairo_create(FTileSurface);
  FViewWidth := Width;
  FViewHeight := Height;
  FStateTop := 0;
  if FPersistentContext <> nil then
    pango_cairo_update_context(FCairo, FPersistentContext);
  FPangoContext := FPersistentContext;

  // Surface starts transparent (ARGB32 is zero-initialized)
  Result := True;
end;

function TPixieCairoCanvas.EndTileRender: TPixieImageHandle;
var
  W, H, Stride: Integer;
  Pixels: Pointer;
begin
  Result := 0;
  // Destroy offscreen context
  if FCairo <> nil then
    cairo_destroy(FCairo);

  // Restore main canvas state
  FCairo := FTileSavedCairo;
  FPangoContext := FTileSavedPangoCtx;
  FStateTop := FTileSavedStateTop;
  FViewWidth := FTileSavedViewW;
  FViewHeight := FTileSavedViewH;

  if FTileSurface = nil then Exit;
  cairo_surface_flush(FTileSurface);
  W := cairo_image_surface_get_width(FTileSurface);
  H := cairo_image_surface_get_height(FTileSurface);
  Stride := cairo_image_surface_get_stride(FTileSurface);
  Pixels := cairo_image_surface_get_data(FTileSurface);
  if Pixels <> nil then
    Result := LoadImageFromPixels(W, H, Pixels, Stride);
  cairo_surface_destroy(FTileSurface);
  FTileSurface := nil;
end;

function TPixieCairoCanvas.BeginOffscreenPaint(
  Width, Height: Integer): Pcairo_surface_t;
begin
  Result := cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Width, Height);
  if Result = nil then Exit;

  FCairo := cairo_create(Result);
  FViewWidth := Width;
  FViewHeight := Height;
  FStateTop := 0;

  // Update Pango context for text rendering
  if FPersistentContext <> nil then
    pango_cairo_update_context(FCairo, FPersistentContext);
  FPangoContext := FPersistentContext;

  // Clear to white
  cairo_set_source_rgb(FCairo, 1, 1, 1);
  cairo_paint(FCairo);
end;

procedure TPixieCairoCanvas.EndOffscreenPaint;
begin
  if FCairo <> nil then
  begin
    cairo_destroy(FCairo);
    FCairo := nil;
  end;
end;

procedure TPixieCairoCanvas.SaveSurfaceToPng(Surface: Pcairo_surface_t;
  const FileName: string);
begin
  if Surface <> nil then
    cairo_surface_write_to_png(Surface, PAnsiChar(AnsiString(FileName)));
end;

procedure TPixieCairoCanvas.BeginOffscreen(Width, Height: Integer;
  ClearColor: TPixieWebColor);
begin
  if FOffscreenSurface <> nil then
    EndOffscreen;
  FOffscreenSurface := cairo_image_surface_create(CAIRO_FORMAT_ARGB32,
    Width, Height);
  if FOffscreenSurface = nil then Exit;
  FCairo := cairo_create(FOffscreenSurface);
  FViewWidth := Width;
  FViewHeight := Height;
  FStateTop := 0;
  if FPersistentContext <> nil then
    pango_cairo_update_context(FCairo, FPersistentContext);
  FPangoContext := FPersistentContext;
  cairo_set_source_rgba(FCairo,
    ClearColor.Red / 255, ClearColor.Green / 255,
    ClearColor.Blue / 255, ClearColor.Alpha / 255);
  cairo_set_operator(FCairo, CAIRO_OPERATOR_SOURCE);
  cairo_paint(FCairo);
  cairo_set_operator(FCairo, CAIRO_OPERATOR_OVER);
end;

procedure TPixieCairoCanvas.EndOffscreen;
begin
  if FCairo <> nil then
  begin
    cairo_destroy(FCairo);
    FCairo := nil;
  end;
  if FOffscreenSurface <> nil then
  begin
    cairo_surface_destroy(FOffscreenSurface);
    FOffscreenSurface := nil;
  end;
end;

procedure TPixieCairoCanvas.SaveAsPng(Stream: TStream);
var
  W, H, Stride: Integer;
  Pixels: Pointer;
begin
  if FOffscreenSurface = nil then Exit;
  cairo_surface_flush(FOffscreenSurface);
  W := cairo_image_surface_get_width(FOffscreenSurface);
  H := cairo_image_surface_get_height(FOffscreenSurface);
  Stride := cairo_image_surface_get_stride(FOffscreenSurface);
  Pixels := cairo_image_surface_get_data(FOffscreenSurface);
  if Pixels = nil then Exit;
  WritePngStream(Stream, Pixels, W, H, Stride);
end;

procedure TPixieCairoCanvas.SaveAsPng(const FileName: string);
begin
  if FOffscreenSurface <> nil then
    cairo_surface_write_to_png(FOffscreenSurface,
      PAnsiChar(AnsiString(FileName)));
end;

procedure TPixieCairoCanvas.SaveAsBmp(Stream: TStream);
var
  W, H, Stride: Integer;
  Pixels: Pointer;
begin
  if FOffscreenSurface = nil then Exit;
  cairo_surface_flush(FOffscreenSurface);
  W := cairo_image_surface_get_width(FOffscreenSurface);
  H := cairo_image_surface_get_height(FOffscreenSurface);
  Stride := cairo_image_surface_get_stride(FOffscreenSurface);
  Pixels := cairo_image_surface_get_data(FOffscreenSurface);
  if Pixels = nil then Exit;
  WriteBmpStream(Stream, Pixels, W, H, Stride);
end;


end.
