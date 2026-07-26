unit Pixie.Canvas.CG;

// CoreGraphics + CoreText implementation of TPixieCanvas for macOS/Cocoa.
// Provides 2D drawing via Quartz 2D and text measurement/rendering via CoreText.
// SVG rendering via Pixie.SvgRenderer.Canvas (cross-platform path-based renderer).

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Math,
  MacOSAll,
  Pixie.Types, Pixie.WebColor, Pixie.Borders,
  Pixie.GradientLayer, Pixie.FontDescription,
  Pixie.Canvas;

type
  { TPixieCGFont }

  TPixieCGFont = class
    Font: CTFontRef;
    SmallFont: CTFontRef;
    Metrics: TPixieFontMetrics;
    DecorationLine: Integer;
    SmallCaps: Boolean;
    destructor Destroy; override;
  end;

  { TPixieCGImage }

  TPixieCGImage = class
    Image: CGImageRef;
    SvgRenderer: TObject;  // TPixieSvgCanvasRenderer (owns)
    ImgWidth: Integer;
    ImgHeight: Integer;
    AspectOnly: Boolean;
    AspectRatio: Single;
    destructor Destroy; override;
  end;

  TPixieCGSavedState = record
    ClipsPushed: Integer;
  end;

  { TPixieCGCanvas }

  TPixieCGCanvas = class(TPixieCanvas)
  private
    FCG: CGContextRef;
    FColorSpace: CGColorSpaceRef;
    FCanvasScale: Single;
    FViewWidth, FViewHeight: Integer;
    FStateStack: array[0..63] of TPixieCGSavedState;
    FStateTop: Integer;
    FMaskPixels: Pointer;
    FTileContext: CGContextRef;
    FTileWidth, FTileHeight: Integer;
    FTileSavedCG: CGContextRef;
    FTileSavedStateTop: Integer;
    FTileSavedViewW, FTileSavedViewH: Integer;
    FOffscreenCtx: CGContextRef;
    FOffscreenWidth, FOffscreenHeight: Integer;

    procedure RoundedRectPath(X, Y, W, H: Single;
      const R: TPixieBorderRadiuses);
    procedure SetFillColor(const C: TPixieWebColor);
    procedure SetStrokeColor(const C: TPixieWebColor);
    procedure ApplyDashPattern;
    procedure ClearDashPattern;
    procedure DrawBorderSide(const Border: TPixieBorder;
      X1, Y1, X2, Y2: Single);
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

    // Offscreen rendering (CGBitmapContext)
    function BeginOffscreenPaint(Width, Height: Integer): CGContextRef;
    procedure EndOffscreenPaint;
    procedure SaveContextToPng(Ctx: CGContextRef; Width, Height: Integer;
      const FileName: string);

    // Public off-screen + image export API
    procedure BeginOffscreen(Width, Height: Integer;
      ClearColor: TPixieWebColor); override;
    procedure EndOffscreen; override;
    procedure SaveAsPng(Stream: TStream); override;
    procedure SaveAsBmp(Stream: TStream); override;
  end;

implementation

uses
  {$IFDEF LCL}CocoaGDIObjects,{$ENDIF}
  FPImage, FPWritePNG,
  Pixie.SvgRenderer.Canvas;

const
  kCGTextStroke = 1;

function CheckCGFont(const Name: string): Boolean;
var
  CFName: CFStringRef;
  Font: CTFontRef;
begin
  CFName := CFStringCreateWithCString(nil,
    PAnsiChar(Name), kCFStringEncodingUTF8);
  Font := CTFontCreateWithName(CFName, 12, nil);
  CFRelease(CFName);
  Result := Font <> nil;
  if Result then
    CFRelease(Font);
end;

// ---------------------------------------------------------------------------
// TPixieCGFont / TPixieCGImage destructors
// ---------------------------------------------------------------------------

destructor TPixieCGFont.Destroy;
begin
  if SmallFont <> nil then
    CFRelease(SmallFont);
  if Font <> nil then
    CFRelease(Font);
  inherited;
end;

destructor TPixieCGImage.Destroy;
begin
  if Image <> nil then
    CGImageRelease(Image);
  SvgRenderer.Free;
  inherited;
end;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.SetFillColor(const C: TPixieWebColor);
begin
  CGContextSetRGBFillColor(FCG,
    C.Red / 255.0, C.Green / 255.0,
    C.Blue / 255.0, C.Alpha / 255.0);
end;

procedure TPixieCGCanvas.SetStrokeColor(const C: TPixieWebColor);
begin
  CGContextSetRGBStrokeColor(FCG,
    C.Red / 255.0, C.Green / 255.0,
    C.Blue / 255.0, C.Alpha / 255.0);
end;

procedure TPixieCGCanvas.ApplyDashPattern;
var
  CGDashes: array of CGFloat;
  I: Integer;
begin
  if Length(FPathDashArray) > 0 then
  begin
    SetLength(CGDashes, Length(FPathDashArray));
    for I := 0 to High(FPathDashArray) do
      CGDashes[I] := FPathDashArray[I];
    CGContextSetLineDash(FCG, FPathDashOffset, @CGDashes[0], Length(CGDashes));
  end;
end;

procedure TPixieCGCanvas.ClearDashPattern;
begin
  if Length(FPathDashArray) > 0 then
    CGContextSetLineDash(FCG, 0, nil, 0);
end;

procedure TPixieCGCanvas.RoundedRectPath(X, Y, W, H: Single;
  const R: TPixieBorderRadiuses);
begin
  // Build a rounded-rect path using arc segments for elliptical corners.
  // Uses CGContext path ops with save/scale for elliptical radii,
  // same approach as the Cairo backend.
  CGContextBeginPath(FCG);
  CGContextMoveToPoint(FCG, X, Y + R.TopLeftY);

  // Top-left arc
  if (R.TopLeftX > 0) and (R.TopLeftY > 0) then
  begin
    CGContextSaveGState(FCG);
    CGContextTranslateCTM(FCG, X + R.TopLeftX, Y + R.TopLeftY);
    CGContextScaleCTM(FCG, R.TopLeftX, R.TopLeftY);
    CGContextAddArc(FCG, 0, 0, 1, Pi, 3 * Pi / 2, 0);
    CGContextRestoreGState(FCG);
  end
  else
    CGContextAddLineToPoint(FCG, X, Y);

  // Top edge
  CGContextAddLineToPoint(FCG, X + W - R.TopRightX, Y);

  // Top-right arc
  if (R.TopRightX > 0) and (R.TopRightY > 0) then
  begin
    CGContextSaveGState(FCG);
    CGContextTranslateCTM(FCG, X + W - R.TopRightX, Y + R.TopRightY);
    CGContextScaleCTM(FCG, R.TopRightX, R.TopRightY);
    CGContextAddArc(FCG, 0, 0, 1, 3 * Pi / 2, 2 * Pi, 0);
    CGContextRestoreGState(FCG);
  end
  else
    CGContextAddLineToPoint(FCG, X + W, Y);

  // Right edge
  CGContextAddLineToPoint(FCG, X + W, Y + H - R.BottomRightY);

  // Bottom-right arc
  if (R.BottomRightX > 0) and (R.BottomRightY > 0) then
  begin
    CGContextSaveGState(FCG);
    CGContextTranslateCTM(FCG, X + W - R.BottomRightX,
      Y + H - R.BottomRightY);
    CGContextScaleCTM(FCG, R.BottomRightX, R.BottomRightY);
    CGContextAddArc(FCG, 0, 0, 1, 0, Pi / 2, 0);
    CGContextRestoreGState(FCG);
  end
  else
    CGContextAddLineToPoint(FCG, X + W, Y + H);

  // Bottom edge
  CGContextAddLineToPoint(FCG, X + R.BottomLeftX, Y + H);

  // Bottom-left arc
  if (R.BottomLeftX > 0) and (R.BottomLeftY > 0) then
  begin
    CGContextSaveGState(FCG);
    CGContextTranslateCTM(FCG, X + R.BottomLeftX,
      Y + H - R.BottomLeftY);
    CGContextScaleCTM(FCG, R.BottomLeftX, R.BottomLeftY);
    CGContextAddArc(FCG, 0, 0, 1, Pi / 2, Pi, 0);
    CGContextRestoreGState(FCG);
  end
  else
    CGContextAddLineToPoint(FCG, X, Y + H);

  CGContextClosePath(FCG);
end;

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

constructor TPixieCGCanvas.Create;
begin
  inherited Create;
  FCG := nil;
  FColorSpace := CGColorSpaceCreateDeviceRGB;
  FCanvasScale := 1.0;
  FViewWidth := 800;
  FViewHeight := 600;
  FStateTop := 0;
end;

destructor TPixieCGCanvas.Destroy;
begin
  if FColorSpace <> nil then
    CGColorSpaceRelease(FColorSpace);
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.BeginPaint(DC: PtrUInt);
{$IFDEF LCL}
var
  CocoaCtx: TCocoaContext;
{$ENDIF}
begin
  FStateTop := 0;
  {$IFDEF LCL}
  CocoaCtx := TCocoaContext(DC);
  FCG := CocoaCtx.CGContext;
  {$ELSE}
  FCG := CGContextRef(Pointer(DC));
  {$ENDIF}
  if FCG = nil then Exit;
  CGContextSaveGState(FCG);
  CGContextScaleCTM(FCG, FScale, FScale);
end;

procedure TPixieCGCanvas.EndPaint;
begin
  if FCG <> nil then
  begin
    CGContextRestoreGState(FCG);
    FCG := nil;
  end;
end;

// ---------------------------------------------------------------------------
// State save/restore
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.SaveState;
begin
  if (FCG = nil) or (FStateTop > High(FStateStack)) then Exit;

  CGContextSaveGState(FCG);
  FStateStack[FStateTop].ClipsPushed := 0;
  Inc(FStateTop);
end;

procedure TPixieCGCanvas.RestoreState;
var
  I: Integer;
begin
  if (FCG = nil) or (FStateTop <= 0) then Exit;
  Dec(FStateTop);

  for I := 0 to FStateStack[FStateTop].ClipsPushed - 1 do
    CGContextRestoreGState(FCG);

  CGContextRestoreGState(FCG);
end;

procedure TPixieCGCanvas.PushOpacity(AOpacity: Single);
begin
  if FCG = nil then Exit;
  CGContextSaveGState(FCG);
  CGContextSetAlpha(FCG, AOpacity);
  CGContextBeginTransparencyLayer(FCG, nil);
end;

procedure TPixieCGCanvas.PopOpacity;
begin
  if FCG = nil then Exit;
  CGContextEndTransparencyLayer(FCG);
  CGContextRestoreGState(FCG);
end;

procedure TPixieCGCanvas.PushMask(MaskHandle: TPixieImageHandle;
  MaskX, MaskY, MaskW, MaskH: Single);
var
  Info: TPixieCGImage;
  W, H, I: Integer;
  SrcCtx: CGContextRef;
  SrcPixels, GrayPixels: PByte;
  SrcPitch: Integer;
  GraySpace: CGColorSpaceRef;
  GrayProvider: CGDataProviderRef;
  MaskImg: CGImageRef;
begin
  if (FCG = nil) or (MaskHandle = 0) then Exit;
  Info := TPixieCGImage(MaskHandle);
  if Info.Image = nil then Exit;
  W := Info.ImgWidth;
  H := Info.ImgHeight;
  if (W = 0) or (H = 0) then Exit;

  // Extract RGBA pixels from the source image
  SrcPitch := W * 4;
  GetMem(SrcPixels, SrcPitch * H);
  SrcCtx := CGBitmapContextCreate(SrcPixels, W, H, 8, SrcPitch,
    FColorSpace, kCGImageAlphaPremultipliedFirst or kCGBitmapByteOrder32Little);
  if SrcCtx = nil then begin FreeMem(SrcPixels); Exit; end;
  CGContextDrawImage(SrcCtx, CGRectMake(0, 0, W, H), Info.Image);
  CGContextRelease(SrcCtx);

  // Convert to grayscale: extract R channel (luminance) from BGRA pixels
  GetMem(GrayPixels, W * H);
  for I := 0 to W * H - 1 do
    GrayPixels[I] := SrcPixels[I * 4 + 2]; // R channel
  FreeMem(SrcPixels);

  // Create a grayscale CGImage for use as mask
  GraySpace := CGColorSpaceCreateDeviceGray;
  GrayProvider := CGDataProviderCreateWithData(nil, GrayPixels, W * H, nil);
  MaskImg := CGImageCreate(W, H, 8, 8, W, GraySpace,
    kCGImageAlphaNone, GrayProvider, nil, 0, kCGRenderingIntentDefault);
  CGDataProviderRelease(GrayProvider);
  CGColorSpaceRelease(GraySpace);

  CGContextSaveGState(FCG);
  // Y-flip: CG native coords have Y up, our canvas has Y down
  CGContextTranslateCTM(FCG, MaskX, MaskY + MaskH);
  CGContextScaleCTM(FCG, 1, -1);
  CGContextClipToMask(FCG, CGRectMake(0, 0, MaskW, MaskH), MaskImg);
  CGContextScaleCTM(FCG, 1, -1);
  CGContextTranslateCTM(FCG, -MaskX, -(MaskY + MaskH));

  CGImageRelease(MaskImg);
  // GrayPixels freed in PopMask — CG retains mask data until RestoreGState
  FMaskPixels := GrayPixels;
end;

procedure TPixieCGCanvas.PopMask;
begin
  if FCG = nil then Exit;
  CGContextRestoreGState(FCG);
  if FMaskPixels <> nil then
  begin
    FreeMem(FMaskPixels);
    FMaskPixels := nil;
  end;
end;

function TPixieCGCanvas.SetBlendMode(Mode: TPixieBlendMode): Boolean;
const
  CGModes: array[TPixieBlendMode] of CGBlendMode = (
    kCGBlendModeNormal,      // bmNormal
    kCGBlendModeMultiply,    // bmMultiply
    kCGBlendModeScreen,      // bmScreen
    kCGBlendModeOverlay,     // bmOverlay
    kCGBlendModeDarken,      // bmDarken
    kCGBlendModeLighten,     // bmLighten
    kCGBlendModeColorDodge,  // bmColorDodge
    kCGBlendModeColorBurn,   // bmColorBurn
    kCGBlendModeHardLight,   // bmHardLight
    kCGBlendModeSoftLight,   // bmSoftLight
    kCGBlendModeDifference,  // bmDifference
    kCGBlendModeExclusion,   // bmExclusion
    kCGBlendModeHue,         // bmHue
    kCGBlendModeSaturation,  // bmSaturation
    kCGBlendModeColor,       // bmColor
    kCGBlendModeLuminosity   // bmLuminosity
  );
begin
  Result := FCG <> nil;
  if Result then
    CGContextSetBlendMode(FCG, CGModes[Mode]);
end;

procedure TPixieCGCanvas.ResetBlendMode;
begin
  if FCG <> nil then
    CGContextSetBlendMode(FCG, kCGBlendModeNormal);
end;

// ---------------------------------------------------------------------------
// Clipping
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.SetClipRect(const R: TPixiePosition;
  const Radius: TPixieBorderRadiuses);
begin
  if FCG = nil then Exit;

  CGContextSaveGState(FCG);

  if Radius.HasRadius then
  begin
    RoundedRectPath(R.X, R.Y, R.Width, R.Height, Radius);
    CGContextClip(FCG);
  end
  else
    CGContextClipToRect(FCG, CGRectMake(R.X, R.Y, R.Width, R.Height));

  if FStateTop > 0 then
    Inc(FStateStack[FStateTop - 1].ClipsPushed);
end;

// ---------------------------------------------------------------------------
// Solid fills
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.FillRect(X, Y, W, H: Single;
  Color: TPixieWebColor);
begin
  if (FCG = nil) or (Color.Alpha = 0) then Exit;
  SetFillColor(Color);
  CGContextFillRect(FCG, CGRectMake(X, Y, W, H));
end;

procedure TPixieCGCanvas.FillRoundedRect(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses; Color: TPixieWebColor);
begin
  if (FCG = nil) or (Color.Alpha = 0) then Exit;
  SetFillColor(Color);

  if Radius.HasRadius then
  begin
    RoundedRectPath(X, Y, W, H, Radius);
    CGContextFillPath(FCG);
  end
  else
    CGContextFillRect(FCG, CGRectMake(X, Y, W, H));
end;

// ---------------------------------------------------------------------------
// Gradients
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.FillLinearGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieLinearGradientLayer);
var
  Components: array of CGFloat;
  Locations: array of CGFloat;
  I, Count: Integer;
  Cp: TPixieColorPoint;
  Grad: CGGradientRef;
begin
  if (FCG = nil) or (Gradient = nil) then Exit;
  Count := Gradient.ColorPoints.Count;
  if Count < 2 then Exit;

  SetLength(Components, Count * 4);
  SetLength(Locations, Count);

  for I := 0 to Count - 1 do
  begin
    Cp := Gradient.ColorPoints[I];
    Components[I * 4 + 0] := Cp.Color.Red / 255.0;
    Components[I * 4 + 1] := Cp.Color.Green / 255.0;
    Components[I * 4 + 2] := Cp.Color.Blue / 255.0;
    Components[I * 4 + 3] := Cp.Color.Alpha / 255.0;
    Locations[I] := Cp.Offset;
  end;

  Grad := CGGradientCreateWithColorComponents(FColorSpace,
    @Components[0], @Locations[0], Count);
  if Grad = nil then Exit;
  try
    CGContextSaveGState(FCG);
    try
      if Radius.HasRadius then
      begin
        RoundedRectPath(X, Y, W, H, Radius);
        CGContextClip(FCG);
      end
      else
        CGContextClipToRect(FCG, CGRectMake(X, Y, W, H));

      CGContextDrawLinearGradient(FCG, Grad,
        CGPointMake(Gradient.StartPt.X, Gradient.StartPt.Y),
        CGPointMake(Gradient.EndPt.X, Gradient.EndPt.Y),
        kCGGradientDrawsBeforeStartLocation or
          kCGGradientDrawsAfterEndLocation);
    finally
      CGContextRestoreGState(FCG);
    end;
  finally
    CGGradientRelease(Grad);
  end;
end;

procedure TPixieCGCanvas.FillRadialGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieRadialGradientLayer);
var
  Components: array of CGFloat;
  Locations: array of CGFloat;
  I, Count: Integer;
  Cp: TPixieColorPoint;
  Grad: CGGradientRef;
  Cx, Cy, Rx, Ry: Single;
begin
  if (FCG = nil) or (Gradient = nil) then Exit;
  Count := Gradient.ColorPoints.Count;
  if Count < 2 then Exit;

  Cx := Gradient.Position.X;
  Cy := Gradient.Position.Y;
  Rx := Gradient.Radius.X;
  Ry := Gradient.Radius.Y;
  if (Rx < 0.001) or (Ry < 0.001) then Exit;

  SetLength(Components, Count * 4);
  SetLength(Locations, Count);

  for I := 0 to Count - 1 do
  begin
    Cp := Gradient.ColorPoints[I];
    Components[I * 4 + 0] := Cp.Color.Red / 255.0;
    Components[I * 4 + 1] := Cp.Color.Green / 255.0;
    Components[I * 4 + 2] := Cp.Color.Blue / 255.0;
    Components[I * 4 + 3] := Cp.Color.Alpha / 255.0;
    Locations[I] := Cp.Offset;
  end;

  Grad := CGGradientCreateWithColorComponents(FColorSpace,
    @Components[0], @Locations[0], Count);
  if Grad = nil then Exit;
  try
    CGContextSaveGState(FCG);
    try
      // Scale Y to form ellipse (same technique as Cairo)
      CGContextScaleCTM(FCG, 1.0, Ry / Rx);

      if Radius.HasRadius then
      begin
        RoundedRectPath(X, Y * Rx / Ry, W, H * Rx / Ry, Radius);
        CGContextClip(FCG);
      end
      else
        CGContextClipToRect(FCG,
          CGRectMake(X, Y * Rx / Ry, W, H * Rx / Ry));

      CGContextDrawRadialGradient(FCG, Grad,
        CGPointMake(Cx, Cy * Rx / Ry), 0,
        CGPointMake(Cx, Cy * Rx / Ry), Rx,
        kCGGradientDrawsBeforeStartLocation or
          kCGGradientDrawsAfterEndLocation);
    finally
      CGContextRestoreGState(FCG);
    end;
  finally
    CGGradientRelease(Grad);
  end;
end;

procedure TPixieCGCanvas.FillConicGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieConicGradientLayer);
var
  Count, I, J, Steps: Integer;
  Cx, Cy, MaxR, Angle, Frac: Single;
  Cp: TPixieColorPoint;
  C: TPixieWebColor;
  StartAngle, SweepAngle, CosA, SinA, CosB, SinB: Single;
begin
  if (FCG = nil) or (Gradient = nil) then Exit;
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
      CGContextSaveGState(FCG);
      CGContextClipToRect(FCG, CGRectMake(X, Y, W, H));
      if FStateTop > 0 then
        Inc(FStateStack[FStateTop - 1].ClipsPushed);
    end;

    Steps := 360;
    SweepAngle := 2 * Pi / Steps;

    for J := 0 to Steps - 1 do
    begin
      Angle := J / Steps;

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

      SetFillColor(C);

      StartAngle := (Gradient.Angle - 90 + J * (360.0 / Steps)) * Pi / 180.0;

      SinCos(StartAngle, SinA, CosA);
      SinCos(StartAngle + SweepAngle, SinB, CosB);

      CGContextBeginPath(FCG);
      CGContextMoveToPoint(FCG, Cx, Cy);
      CGContextAddLineToPoint(FCG, Cx + CosA * MaxR, Cy + SinA * MaxR);
      CGContextAddLineToPoint(FCG, Cx + CosB * MaxR, Cy + SinB * MaxR);
      CGContextClosePath(FCG);
      CGContextFillPath(FCG);
    end;
  finally
    RestoreState;
  end;
end;

// ---------------------------------------------------------------------------
// Borders
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.DrawBorderSide(const Border: TPixieBorder;
  X1, Y1, X2, Y2: Single);
var
  LineW, Offset, Dx, Dy, Len, Nx, Ny: Single;
  Dashes: array[0..1] of CGFloat;
begin
  if (Border.Width <= 0) or (Border.Style = bsNone) or
     (Border.Style = bsHidden) then
    Exit;

  SetStrokeColor(Border.Color);

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

    CGContextSetLineWidth(FCG, LineW);
    // Outer line
    CGContextBeginPath(FCG);
    CGContextMoveToPoint(FCG, X1 - Nx * Offset, Y1 - Ny * Offset);
    CGContextAddLineToPoint(FCG, X2 - Nx * Offset, Y2 - Ny * Offset);
    CGContextStrokePath(FCG);
    // Inner line
    CGContextBeginPath(FCG);
    CGContextMoveToPoint(FCG, X1 + Nx * Offset, Y1 + Ny * Offset);
    CGContextAddLineToPoint(FCG, X2 + Nx * Offset, Y2 + Ny * Offset);
    CGContextStrokePath(FCG);
    Exit;
  end;

  CGContextSetLineWidth(FCG, Border.Width);

  case Border.Style of
    bsDotted:
    begin
      CGContextSetLineCap(FCG, kCGLineCapRound);
      Dashes[0] := 0;
      Dashes[1] := Border.Width * 2;
      CGContextSetLineDash(FCG, 0, @Dashes[0], 2);
    end;
    bsDashed:
    begin
      Dashes[0] := Border.Width * 3;
      Dashes[1] := Border.Width * 3;
      CGContextSetLineDash(FCG, 0, @Dashes[0], 2);
    end;
  else
    CGContextSetLineDash(FCG, 0, nil, 0);
  end;

  CGContextBeginPath(FCG);
  CGContextMoveToPoint(FCG, X1, Y1);
  CGContextAddLineToPoint(FCG, X2, Y2);
  CGContextStrokePath(FCG);

  if Border.Style = bsDotted then
    CGContextSetLineCap(FCG, kCGLineCapButt);
  CGContextSetLineDash(FCG, 0, nil, 0);
end;

procedure TPixieCGCanvas.DrawBorders(const Borders: TPixieBorders;
  const Pos: TPixiePosition; IsRoot: Boolean);
var
  X, Y, W, H: Single;
begin
  if FCG = nil then Exit;
  if not Borders.IsVisible then Exit;

  X := Pos.X;
  Y := Pos.Y;
  W := Pos.Width;
  H := Pos.Height;

  if Borders.Radius.HasRadius then
  begin
    if (Borders.Top.Width > 0) and (Borders.Top.Style <> bsNone) then
    begin
      SetStrokeColor(Borders.Top.Color);
      CGContextSetLineWidth(FCG, Borders.Top.Width);
      RoundedRectPath(X, Y, W, H, Borders.Radius);
      CGContextStrokePath(FCG);
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

function TPixieCGCanvas.CreateFont(
  const Descr: TPixieFontDescription;
  out Metrics: TPixieFontMetrics): TPixieFontHandle;
var
  Info: TPixieCGFont;
  CFName: CFStringRef;
  BaseFont, StyledFont: CTFontRef;
  TraitValue, TraitMask: CTFontSymbolicTraits;
  Ascent, Descent, Leading: CGFloat;
  ResolvedFamily: string;
begin
  Result := 0;
  Info := TPixieCGFont.Create;
  Info.DecorationLine := Descr.DecorationLine;

  // Resolve CSS font-family list
  ResolvedFamily := PixieResolveFontFamily(Descr.Family, CheckCGFont);
  if ResolvedFamily <> '' then
    CFName := CFStringCreateWithCString(nil,
      PAnsiChar(ResolvedFamily), kCFStringEncodingUTF8)
  else
    CFName := CFStringCreateWithCString(nil,
      'Helvetica', kCFStringEncodingUTF8);

  BaseFont := CTFontCreateWithName(CFName, Descr.Size, nil);
  CFRelease(CFName);

  // Apply bold/italic traits if needed
  TraitValue := 0;
  TraitMask := 0;

  if Descr.Weight >= 700 then
  begin
    TraitValue := TraitValue or kCTFontTraitBold;
    TraitMask := TraitMask or kCTFontTraitBold;
  end;

  if Descr.Style = fstItalic then
  begin
    TraitValue := TraitValue or kCTFontTraitItalic;
    TraitMask := TraitMask or kCTFontTraitItalic;
  end;

  if (TraitMask <> 0) and (BaseFont <> nil) then
  begin
    StyledFont := CTFontCreateCopyWithSymbolicTraits(
      BaseFont, 0, nil, TraitValue, TraitMask);
    if StyledFont <> nil then
    begin
      CFRelease(BaseFont);
      BaseFont := StyledFont;
    end;
    // If CTFontCreateCopyWithSymbolicTraits returns nil (font doesn't
    // have the requested trait), keep the base font.
  end;

  Info.Font := BaseFont;
  Info.SmallCaps := Descr.Variant = fvSmallCaps;
  if Info.SmallCaps and (BaseFont <> nil) then
    Info.SmallFont := CTFontCreateCopyWithAttributes(
      BaseFont, Descr.Size * PixieSmallCapsScale, nil, nil)
  else
    Info.SmallFont := nil;

  // Get metrics from CoreText
  if BaseFont <> nil then
  begin
    Ascent := CTFontGetAscent(BaseFont);
    Descent := CTFontGetDescent(BaseFont);
    Leading := CTFontGetLeading(BaseFont);

    Metrics.Ascent := Ascent;
    Metrics.Descent := Descent;
    Metrics.Height := Ascent + Descent + Leading;
    Metrics.XHeight := CTFontGetXHeight(BaseFont);
  end
  else
  begin
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

procedure TPixieCGCanvas.DoDeleteFont(Handle: TPixieFontHandle);
begin
  if Handle <> 0 then
    TPixieCGFont(Handle).Free;
end;

// Builds a small-caps attributed string for CoreText: uppercases the text
// and applies SmallFont to ranges that were originally lowercase.
function BuildSmallCapsAttrString(const Text: string;
  Font, SmallFont: CTFontRef;
  ExtraAttrName: CFStringRef; ExtraAttrValue: CFTypeRef): CFAttributedStringRef;
var
  CFMut: CFMutableStringRef;
  CFImmut: CFStringRef;
  MutAttr: CFMutableAttributedStringRef;
  Len, I, RunStart: CFIndex;
  OrigCh, UpperCh: UniChar;
  InLower: Boolean;
begin
  Result := nil;
  CFImmut := CFStringCreateWithCString(nil,
    PAnsiChar(Text), kCFStringEncodingUTF8);
  if CFImmut = nil then Exit;

  CFMut := CFStringCreateMutableCopy(nil, 0, CFImmut);
  Len := CFStringGetLength(CFImmut);
  CFStringUppercase(CFMut, nil);

  MutAttr := CFAttributedStringCreateMutable(nil, 0);
  CFAttributedStringReplaceString(MutAttr, CFRangeMake(0, 0), CFMut);
  CFAttributedStringSetAttribute(MutAttr,
    CFRangeMake(0, Len), kCTFontAttributeName, Font);

  if ExtraAttrName <> nil then
    CFAttributedStringSetAttribute(MutAttr,
      CFRangeMake(0, Len), ExtraAttrName, ExtraAttrValue);

  if SmallFont <> nil then
  begin
    RunStart := 0;
    InLower := False;
    for I := 0 to Len - 1 do
    begin
      OrigCh := CFStringGetCharacterAtIndex(CFImmut, I);
      UpperCh := CFStringGetCharacterAtIndex(CFMut, I);
      if OrigCh <> UpperCh then
      begin
        if not InLower then
        begin
          RunStart := I;
          InLower := True;
        end;
      end
      else
      begin
        if InLower then
        begin
          CFAttributedStringSetAttribute(MutAttr,
            CFRangeMake(RunStart, I - RunStart),
            kCTFontAttributeName, SmallFont);
          InLower := False;
        end;
      end;
    end;
    if InLower then
      CFAttributedStringSetAttribute(MutAttr,
        CFRangeMake(RunStart, Len - RunStart),
        kCTFontAttributeName, SmallFont);
  end;

  CFRelease(CFMut);
  CFRelease(CFImmut);
  Result := CFAttributedStringRef(MutAttr);
end;

function TPixieCGCanvas.DoMeasureText(const Text: string;
  Handle: TPixieFontHandle): TPixiePixel;
var
  Info: TPixieCGFont;
  CFText: CFStringRef;
  AttrStr: CFAttributedStringRef;
  Attrs: CFMutableDictionaryRef;
  Line: CTLineRef;
  Width: Float64;
begin
  Result := 0;
  if Handle = 0 then Exit;
  Info := TPixieCGFont(Handle);
  if Info.Font = nil then
  begin
    Result := Length(Text) * Info.Metrics.ChWidth;
    Exit;
  end;
  if Text = '' then Exit;

  if Info.SmallCaps then
  begin
    AttrStr := BuildSmallCapsAttrString(Text,
      Info.Font, Info.SmallFont, nil, nil);
    if AttrStr = nil then Exit;
    try
      Line := CTLineCreateWithAttributedString(AttrStr);
      if Line = nil then Exit;
      try
        Width := CTLineGetTypographicBounds(Line, nil, nil, nil);
        Result := Width;
      finally
        CFRelease(Line);
      end;
    finally
      CFRelease(AttrStr);
    end;
    Exit;
  end;

  CFText := CFStringCreateWithCString(nil,
    PAnsiChar(Text), kCFStringEncodingUTF8);
  if CFText = nil then Exit;
  try
    Attrs := CFDictionaryCreateMutable(nil, 1,
      @kCFTypeDictionaryKeyCallBacks, @kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(Attrs, kCTFontAttributeName, Info.Font);

    AttrStr := CFAttributedStringCreate(nil, CFText, Attrs);
    CFRelease(Attrs);
    if AttrStr = nil then Exit;
    try
      Line := CTLineCreateWithAttributedString(AttrStr);
      if Line = nil then Exit;
      try
        Width := CTLineGetTypographicBounds(Line, nil, nil, nil);
        Result := Width;
      finally
        CFRelease(Line);
      end;
    finally
      CFRelease(AttrStr);
    end;
  finally
    CFRelease(CFText);
  end;
end;

procedure TPixieCGCanvas.DrawText(const Text: string;
  Handle: TPixieFontHandle; Color: TPixieWebColor;
  X, Y, W, H: Single);
var
  Info: TPixieCGFont;
  CFText: CFStringRef;
  AttrStr: CFAttributedStringRef;
  Attrs: CFMutableDictionaryRef;
  Line: CTLineRef;
  CGColor_: CGColorRef;
  Components: array[0..3] of CGFloat;
begin
  if (Handle = 0) or (FCG = nil) then Exit;
  Info := TPixieCGFont(Handle);
  if Info.Font = nil then Exit;
  if Text = '' then Exit;

  // Create color for text attribute
  Components[0] := Color.Red / 255.0;
  Components[1] := Color.Green / 255.0;
  Components[2] := Color.Blue / 255.0;
  Components[3] := Color.Alpha / 255.0;
  CGColor_ := CGColorCreate(FColorSpace, @Components[0]);

  if Info.SmallCaps then
  begin
    AttrStr := BuildSmallCapsAttrString(Text,
      Info.Font, Info.SmallFont,
      kCTForegroundColorAttributeName, CGColor_);
    CGColorRelease(CGColor_);
    if AttrStr = nil then Exit;
    try
      Line := CTLineCreateWithAttributedString(AttrStr);
      if Line = nil then Exit;
      try
        CGContextSaveGState(FCG);
        try
          CGContextTranslateCTM(FCG, X, Y + Info.Metrics.Ascent);
          CGContextScaleCTM(FCG, 1, -1);
          CGContextSetTextPosition(FCG, 0, 0);
          CTLineDraw(Line, FCG);
        finally
          CGContextRestoreGState(FCG);
        end;
      finally
        CFRelease(Line);
      end;
    finally
      CFRelease(AttrStr);
    end;
    Exit;
  end;

  CFText := CFStringCreateWithCString(nil,
    PAnsiChar(Text), kCFStringEncodingUTF8);
  if CFText = nil then
  begin
    CGColorRelease(CGColor_);
    Exit;
  end;
  try
    Attrs := CFDictionaryCreateMutable(nil, 2,
      @kCFTypeDictionaryKeyCallBacks, @kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(Attrs, kCTFontAttributeName, Info.Font);
    CFDictionarySetValue(Attrs, kCTForegroundColorAttributeName, CGColor_);

    AttrStr := CFAttributedStringCreate(nil, CFText, Attrs);
    CFRelease(Attrs);
    CGColorRelease(CGColor_);
    if AttrStr = nil then Exit;
    try
      Line := CTLineCreateWithAttributedString(AttrStr);
      if Line = nil then Exit;
      try
        // CoreText draws from the baseline. In our flipped coordinate
        // system, Y increases downward. The text position Y should be
        // at Y + Ascent (the baseline measured from the top of the
        // text box).
        //
        // However, CTLineDraw uses the text matrix which operates in
        // the native CG coordinate system. Since Cocoa flips the view
        // (isFlipped = YES), the CGContext Y-axis goes top-down. But
        // CTLineDraw still expects the glyph Y-axis to go upward from
        // the baseline. We need to flip the text matrix locally.
        CGContextSaveGState(FCG);
        try
          // Flip vertically at the text position so glyphs render right-side up
          CGContextTranslateCTM(FCG, X, Y + Info.Metrics.Ascent);
          CGContextScaleCTM(FCG, 1, -1);
          CGContextSetTextPosition(FCG, 0, 0);
          CTLineDraw(Line, FCG);
        finally
          CGContextRestoreGState(FCG);
        end;

        // Text decoration is drawn at the element level (TPixieHtmlTag.DrawBackground)
      finally
        CFRelease(Line);
      end;
    finally
      CFRelease(AttrStr);
    end;
  finally
    CFRelease(CFText);
  end;
end;

procedure TPixieCGCanvas.StrokeTextAtBaseline(const Text: string;
  Handle: TPixieFontHandle; const Metrics: TPixieFontMetrics;
  Color: TPixieWebColor; Width: Single; X, BaselineY: Single);
var
  Info: TPixieCGFont;
  CFText: CFStringRef;
  AttrStr: CFAttributedStringRef;
  Attrs: CFMutableDictionaryRef;
  Line: CTLineRef;
  Components: array[0..3] of CGFloat;
  CGColor_: CGColorRef;
begin
  if (Handle = 0) or (FCG = nil) or (Width <= 0) then Exit;
  Info := TPixieCGFont(Handle);
  if Info.Font = nil then Exit;
  if Text = '' then Exit;

  Components[0] := Color.Red / 255.0;
  Components[1] := Color.Green / 255.0;
  Components[2] := Color.Blue / 255.0;
  Components[3] := Color.Alpha / 255.0;
  CGColor_ := CGColorCreate(FColorSpace, @Components[0]);

  CFText := CFStringCreateWithCString(nil,
    PAnsiChar(Text), kCFStringEncodingUTF8);
  if CFText = nil then
  begin
    CGColorRelease(CGColor_);
    Exit;
  end;
  try
    Attrs := CFDictionaryCreateMutable(nil, 2,
      @kCFTypeDictionaryKeyCallBacks, @kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(Attrs, kCTFontAttributeName, Info.Font);
    CFDictionarySetValue(Attrs, kCTForegroundColorAttributeName, CGColor_);

    AttrStr := CFAttributedStringCreate(nil, CFText, Attrs);
    CFRelease(Attrs);
    CGColorRelease(CGColor_);
    if AttrStr = nil then Exit;
    try
      Line := CTLineCreateWithAttributedString(AttrStr);
      if Line = nil then Exit;
      try
        CGContextSaveGState(FCG);
        try
          CGContextTranslateCTM(FCG, X, BaselineY);
          CGContextScaleCTM(FCG, 1, -1);
          CGContextSetTextPosition(FCG, 0, 0);
          CGContextSetTextDrawingMode(FCG, kCGTextStroke);
          CGContextSetRGBStrokeColor(FCG,
            Color.Red / 255.0, Color.Green / 255.0,
            Color.Blue / 255.0, Color.Alpha / 255.0);
          CGContextSetLineWidth(FCG, Width);
          CTLineDraw(Line, FCG);
        finally
          CGContextRestoreGState(FCG);
        end;
      finally
        CFRelease(Line);
      end;
    finally
      CFRelease(AttrStr);
    end;
  finally
    CFRelease(CFText);
  end;
end;

function TPixieCGCanvas.PtToPx(Pt: Single): TPixiePixel;
begin
  Result := Trunc(Pt * 96.0 / 72.0);
end;

// ---------------------------------------------------------------------------
// Image loading
// ---------------------------------------------------------------------------

function TPixieCGCanvas.LoadSvgFile(
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

function TPixieCGCanvas.LoadSvgFromData(Data: Pointer;
  Size: Integer): TPixieImageHandle;
var
  Info: TPixieCGImage;
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

  Info := TPixieCGImage.Create;
  Info.SvgRenderer := Renderer;
  Info.ImgWidth := Round(W);
  Info.ImgHeight := Round(H);
  Info.AspectOnly := not Renderer.HasExplicitSize;
  Info.AspectRatio := Renderer.GetAspectRatio;
  Result := TPixieImageHandle(Info);
end;

function TPixieCGCanvas.LoadImage(
  const Path: string): TPixieImageHandle;
var
  Info: TPixieCGImage;
  Resolved: string;
  CFPath: CFStringRef;
  FileUrl: CFURLRef;
  ImageSource: CGImageSourceRef;
  Img: CGImageRef;
begin
  Result := 0;

  Resolved := ExpandFileName(Path);
  if not FileExists(Resolved) then Exit;

  // SVG — render via canvas path API
  if LowerCase(ExtractFileExt(Resolved)) = '.svg' then
  begin
    Result := LoadSvgFile(Resolved);
    Exit;
  end;

  // Raster images via ImageIO (supports PNG, JPEG, GIF, BMP, TIFF, ICO)
  CFPath := CFStringCreateWithCString(nil,
    PAnsiChar(Resolved), kCFStringEncodingUTF8);
  if CFPath <> nil then
  try
    FileUrl := CFURLCreateWithFileSystemPath(nil, CFPath,
      kCFURLPOSIXPathStyle, False);
    if FileUrl <> nil then
    try
      ImageSource := CGImageSourceCreateWithURL(FileUrl, nil);
      if ImageSource <> nil then
      try
        Img := CGImageSourceCreateImageAtIndex(ImageSource, 0, nil);
        if Img <> nil then
        begin
          Info := TPixieCGImage.Create;
          Info.Image := Img;
          Info.ImgWidth := CGImageGetWidth(Img);
          Info.ImgHeight := CGImageGetHeight(Img);
          Result := TPixieImageHandle(Info);
        end;
      finally
        CFRelease(ImageSource);
      end;
    finally
      CFRelease(FileUrl);
    end;
  finally
    CFRelease(CFPath);
  end;

  // ImageIO failed — try libwebp for .webp files
  if (Result = 0) and
     (LowerCase(ExtractFileExt(Resolved)) = '.webp') then
    Result := LoadWebPFile(Resolved);
end;

function TPixieCGCanvas.LoadImageFromPixels(Width, Height: Integer;
  Pixels: Pointer; Pitch: Integer): TPixieImageHandle;
var
  Info: TPixieCGImage;
  BmpCtx: CGContextRef;
  Img: CGImageRef;
  BufSize: Integer;
  PixelCopy: Pointer;
begin
  Result := 0;
  if (Width <= 0) or (Height <= 0) or (Pixels = nil) then Exit;

  // We need to copy the pixel data since CGBitmapContext doesn't own it
  BufSize := Pitch * Height;
  GetMem(PixelCopy, BufSize);
  Move(Pixels^, PixelCopy^, BufSize);

  BmpCtx := CGBitmapContextCreate(PixelCopy, Width, Height, 8, Pitch,
    FColorSpace,
    kCGImageAlphaPremultipliedFirst or kCGBitmapByteOrder32Little);

  if BmpCtx = nil then
  begin
    FreeMem(PixelCopy);
    Exit;
  end;

  Img := CGBitmapContextCreateImage(BmpCtx);
  CGContextRelease(BmpCtx);
  FreeMem(PixelCopy);

  if Img = nil then Exit;

  Info := TPixieCGImage.Create;
  Info.Image := Img;
  Info.ImgWidth := Width;
  Info.ImgHeight := Height;
  Result := TPixieImageHandle(Info);
end;

procedure TPixieCGCanvas.FreeImage(Handle: TPixieImageHandle);
begin
  if Handle <> 0 then
    TPixieCGImage(Handle).Free;
end;

procedure TPixieCGCanvas.GetImageSize(Handle: TPixieImageHandle;
  out W, H: Single);
var
  Info: TPixieCGImage;
begin
  W := 0;
  H := 0;
  if Handle = 0 then Exit;
  Info := TPixieCGImage(Handle);
  W := Info.ImgWidth;
  H := Info.ImgHeight;
end;

function TPixieCGCanvas.GetImageAspectInfo(Handle: TPixieImageHandle;
  out AspectRatio: Single): Boolean;
var
  Info: TPixieCGImage;
begin
  AspectRatio := 0;
  Result := False;
  if Handle = 0 then Exit;
  Info := TPixieCGImage(Handle);
  Result := Info.AspectOnly;
  if Result then
    AspectRatio := Info.AspectRatio;
end;

procedure TPixieCGCanvas.DrawImage(Handle: TPixieImageHandle;
  DstX, DstY, DstW, DstH: Single);
var
  Info: TPixieCGImage;
begin
  if (Handle = 0) or (FCG = nil) then Exit;
  Info := TPixieCGImage(Handle);
  if (Info.ImgWidth <= 0) or (Info.ImgHeight <= 0) then Exit;

  // SVG rendering via canvas path API
  if Info.SvgRenderer <> nil then
  begin
    TPixieSvgCanvasRenderer(Info.SvgRenderer).RenderToRect(
      DstX, DstY, DstW, DstH);
    Exit;
  end;

  // Raster image
  if Info.Image = nil then Exit;

  // CGContextDrawImage draws images in the native CG coordinate system.
  // Since Cocoa's flipped view makes Y go top-down, images would appear
  // upside-down. We flip vertically around the destination rect center.
  CGContextSaveGState(FCG);
  try
    CGContextTranslateCTM(FCG, DstX, DstY + DstH);
    CGContextScaleCTM(FCG, 1, -1);
    CGContextDrawImage(FCG, CGRectMake(0, 0, DstW, DstH), Info.Image);
  finally
    CGContextRestoreGState(FCG);
  end;
end;

procedure TPixieCGCanvas.FillTiledImage(Handle: TPixieImageHandle;
  TileX, TileY, TileW, TileH: Single;
  FillX, FillY, FillW, FillH: Single);
var
  Info: TPixieCGImage;
begin
  if (Handle = 0) or (FCG = nil) then Exit;
  Info := TPixieCGImage(Handle);
  if (Info.ImgWidth <= 0) or (Info.ImgHeight <= 0) then Exit;

  // SVG images: fall back to base-class per-tile loop
  if Info.SvgRenderer <> nil then
  begin
    inherited;
    Exit;
  end;

  if Info.Image = nil then Exit;
  if (TileW <= 0) or (TileH <= 0) then Exit;

  // CGContextDrawTiledImage tiles across the entire clip region.
  // Clip to the fill area and flip Y for CG's bottom-up coords.
  CGContextSaveGState(FCG);
  try
    CGContextClipToRect(FCG, CGRectMake(FillX, FillY, FillW, FillH));
    CGContextTranslateCTM(FCG, TileX, TileY + TileH);
    CGContextScaleCTM(FCG, 1, -1);
    CGContextDrawTiledImage(FCG,
      CGRectMake(0, 0, TileW, TileH), Info.Image);
  finally
    CGContextRestoreGState(FCG);
  end;
end;

// ---------------------------------------------------------------------------
// Simple shapes (list markers)
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.FillEllipse(X, Y, W, H: Single;
  Color: TPixieWebColor);
begin
  if (FCG = nil) or (Color.Alpha = 0) then Exit;
  SetFillColor(Color);
  CGContextFillEllipseInRect(FCG, CGRectMake(X, Y, W, H));
end;

procedure TPixieCGCanvas.DrawEllipse(X, Y, W, H: Single;
  Color: TPixieWebColor; StrokeWidth: Single);
begin
  if (FCG = nil) or (Color.Alpha = 0) then Exit;
  SetStrokeColor(Color);
  CGContextSetLineWidth(FCG, StrokeWidth);
  CGContextStrokeEllipseInRect(FCG, CGRectMake(X, Y, W, H));
end;

procedure TPixieCGCanvas.DrawRect(X, Y, W, H: Single;
  Color: TPixieWebColor; StrokeWidth: Single);
begin
  if (FCG = nil) or (Color.Alpha = 0) then Exit;
  SetStrokeColor(Color);
  CGContextSetLineWidth(FCG, StrokeWidth);
  CGContextStrokeRect(FCG, CGRectMake(X, Y, W, H));
end;

procedure TPixieCGCanvas.DrawLine(X1, Y1, X2, Y2: Single;
  Color: TPixieWebColor; StrokeWidth: Single;
  Style: TPixieTextDecorationStyle);
var
  Dashes: array[0..1] of CGFloat;
begin
  if (FCG = nil) or (Color.Alpha = 0) then Exit;
  SetStrokeColor(Color);
  CGContextSetLineWidth(FCG, StrokeWidth);
  if Style = tdsDotted then
  begin
    Dashes[0] := StrokeWidth;
    Dashes[1] := StrokeWidth * 2;
    CGContextSetLineDash(FCG, 0, @Dashes[0], 2);
  end
  else if Style = tdsDashed then
  begin
    Dashes[0] := StrokeWidth * 3;
    Dashes[1] := StrokeWidth * 2;
    CGContextSetLineDash(FCG, 0, @Dashes[0], 2);
  end;
  CGContextBeginPath(FCG);
  CGContextMoveToPoint(FCG, X1, Y1);
  CGContextAddLineToPoint(FCG, X2, Y2);
  CGContextStrokePath(FCG);
  if Style in [tdsDotted, tdsDashed] then
    CGContextSetLineDash(FCG, 0, nil, 0);
end;

procedure TPixieCGCanvas.StrokePolyline(const Points: array of Single;
  Color: TPixieWebColor; StrokeWidth: Single);
var
  Count, I: Integer;
begin
  Count := Length(Points) div 2;
  if (FCG = nil) or (Color.Alpha = 0) or (Count < 2) then Exit;
  SetStrokeColor(Color);
  CGContextSetLineWidth(FCG, StrokeWidth);
  CGContextSetLineCap(FCG, kCGLineCapRound);
  CGContextSetLineJoin(FCG, kCGLineJoinRound);
  CGContextBeginPath(FCG);
  CGContextMoveToPoint(FCG, Points[0], Points[1]);
  for I := 1 to Count - 1 do
    CGContextAddLineToPoint(FCG, Points[I * 2], Points[I * 2 + 1]);
  CGContextStrokePath(FCG);
  CGContextSetLineCap(FCG, kCGLineCapButt);
  CGContextSetLineJoin(FCG, kCGLineJoinMiter);
end;

// ---------------------------------------------------------------------------
// Path API
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.BeginPath;
begin
  if FCG = nil then Exit;
  CGContextBeginPath(FCG);
end;

procedure TPixieCGCanvas.MoveTo(X, Y: Single);
begin
  if FCG = nil then Exit;
  CGContextMoveToPoint(FCG, X, Y);
end;

procedure TPixieCGCanvas.LineTo(X, Y: Single);
begin
  if FCG = nil then Exit;
  CGContextAddLineToPoint(FCG, X, Y);
end;

procedure TPixieCGCanvas.CurveTo(X1, Y1, X2, Y2, X3, Y3: Single);
begin
  if FCG = nil then Exit;
  CGContextAddCurveToPoint(FCG, X1, Y1, X2, Y2, X3, Y3);
end;

procedure TPixieCGCanvas.ClosePath;
begin
  if FCG = nil then Exit;
  CGContextClosePath(FCG);
end;

procedure TPixieCGCanvas.FillPath(Color: TPixieWebColor;
  FillRule: TPixieFillRule);
begin
  if FCG = nil then Exit;
  if Color.Alpha > 0 then
  begin
    SetFillColor(Color);
    if FillRule = frEvenOdd then
      CGContextDrawPath(FCG, kCGPathEOFill)
    else
      CGContextDrawPath(FCG, kCGPathFill);
  end
  else
    CGContextBeginPath(FCG);
end;

procedure TPixieCGCanvas.StrokePath(Color: TPixieWebColor;
  Width: Single);
begin
  if FCG = nil then Exit;
  if Color.Alpha > 0 then
  begin
    SetStrokeColor(Color);
    CGContextSetLineWidth(FCG, Width);
    if (FPathLineCap <> lcButt) or (FPathLineJoin <> ljMiter) then
    begin
      CGContextSetLineCap(FCG, Ord(FPathLineCap));
      CGContextSetLineJoin(FCG, Ord(FPathLineJoin));
    end;
    ApplyDashPattern;
    CGContextDrawPath(FCG, kCGPathStroke);
    ClearDashPattern;
    if (FPathLineCap <> lcButt) or (FPathLineJoin <> ljMiter) then
    begin
      CGContextSetLineCap(FCG, kCGLineCapButt);
      CGContextSetLineJoin(FCG, kCGLineJoinMiter);
    end;
  end
  else
    CGContextBeginPath(FCG);
end;

procedure TPixieCGCanvas.FillAndStrokePath(FillColor: TPixieWebColor;
  StrokeColor: TPixieWebColor; StrokeWidth: Single;
  FillRule: TPixieFillRule);
begin
  if FCG = nil then Exit;
  if (FillColor.Alpha > 0) and (StrokeColor.Alpha > 0) then
  begin
    SetFillColor(FillColor);
    SetStrokeColor(StrokeColor);
    CGContextSetLineWidth(FCG, StrokeWidth);
    if (FPathLineCap <> lcButt) or (FPathLineJoin <> ljMiter) then
    begin
      CGContextSetLineCap(FCG, Ord(FPathLineCap));
      CGContextSetLineJoin(FCG, Ord(FPathLineJoin));
    end;
    ApplyDashPattern;
    if FillRule = frEvenOdd then
      CGContextDrawPath(FCG, kCGPathEOFillStroke)
    else
      CGContextDrawPath(FCG, kCGPathFillStroke);
    ClearDashPattern;
    if (FPathLineCap <> lcButt) or (FPathLineJoin <> ljMiter) then
    begin
      CGContextSetLineCap(FCG, kCGLineCapButt);
      CGContextSetLineJoin(FCG, kCGLineJoinMiter);
    end;
  end
  else if FillColor.Alpha > 0 then
  begin
    SetFillColor(FillColor);
    if FillRule = frEvenOdd then
      CGContextDrawPath(FCG, kCGPathEOFill)
    else
      CGContextDrawPath(FCG, kCGPathFill);
  end
  else if StrokeColor.Alpha > 0 then
  begin
    SetStrokeColor(StrokeColor);
    CGContextSetLineWidth(FCG, StrokeWidth);
    if (FPathLineCap <> lcButt) or (FPathLineJoin <> ljMiter) then
    begin
      CGContextSetLineCap(FCG, Ord(FPathLineCap));
      CGContextSetLineJoin(FCG, Ord(FPathLineJoin));
    end;
    ApplyDashPattern;
    CGContextDrawPath(FCG, kCGPathStroke);
    ClearDashPattern;
    if (FPathLineCap <> lcButt) or (FPathLineJoin <> ljMiter) then
    begin
      CGContextSetLineCap(FCG, kCGLineCapButt);
      CGContextSetLineJoin(FCG, kCGLineJoinMiter);
    end;
  end
  else
    CGContextBeginPath(FCG);
end;

procedure TPixieCGCanvas.DiscardPath;
begin
  if FCG <> nil then
    CGContextBeginPath(FCG);
end;

procedure TPixieCGCanvas.StrokePathLinearGradient(
  const Gradient: TPixieLinearGradientLayer; Width: Single);
var
  Components: array of CGFloat;
  Locations: array of CGFloat;
  I, Count: Integer;
  Cp: TPixieColorPoint;
  Grad: CGGradientRef;
begin
  if (FCG = nil) or (Gradient = nil) then Exit;
  Count := Gradient.ColorPoints.Count;
  if Count < 2 then
  begin
    CGContextBeginPath(FCG);
    Exit;
  end;

  SetLength(Components, Count * 4);
  SetLength(Locations, Count);
  for I := 0 to Count - 1 do
  begin
    Cp := Gradient.ColorPoints[I];
    Components[I * 4 + 0] := Cp.Color.Red / 255.0;
    Components[I * 4 + 1] := Cp.Color.Green / 255.0;
    Components[I * 4 + 2] := Cp.Color.Blue / 255.0;
    Components[I * 4 + 3] := Cp.Color.Alpha / 255.0;
    Locations[I] := Cp.Offset;
  end;

  Grad := CGGradientCreateWithColorComponents(FColorSpace,
    @Components[0], @Locations[0], Count);
  if Grad = nil then
  begin
    CGContextBeginPath(FCG);
    Exit;
  end;
  try
    CGContextSetLineWidth(FCG, Width);
    ApplyDashPattern;
    CGContextReplacePathWithStrokedPath(FCG);
    ClearDashPattern;
    CGContextSaveGState(FCG);
    try
      CGContextClip(FCG);
      CGContextDrawLinearGradient(FCG, Grad,
        CGPointMake(Gradient.StartPt.X, Gradient.StartPt.Y),
        CGPointMake(Gradient.EndPt.X, Gradient.EndPt.Y),
        kCGGradientDrawsBeforeStartLocation or
          kCGGradientDrawsAfterEndLocation);
    finally
      CGContextRestoreGState(FCG);
    end;
  finally
    CGGradientRelease(Grad);
  end;
end;

procedure TPixieCGCanvas.StrokePathRadialGradient(
  const Gradient: TPixieRadialGradientLayer; Width: Single);
var
  Components: array of CGFloat;
  Locations: array of CGFloat;
  I, Count: Integer;
  Cp: TPixieColorPoint;
  Grad: CGGradientRef;
begin
  if (FCG = nil) or (Gradient = nil) then Exit;
  Count := Gradient.ColorPoints.Count;
  if Count < 2 then
  begin
    CGContextBeginPath(FCG);
    Exit;
  end;

  SetLength(Components, Count * 4);
  SetLength(Locations, Count);
  for I := 0 to Count - 1 do
  begin
    Cp := Gradient.ColorPoints[I];
    Components[I * 4 + 0] := Cp.Color.Red / 255.0;
    Components[I * 4 + 1] := Cp.Color.Green / 255.0;
    Components[I * 4 + 2] := Cp.Color.Blue / 255.0;
    Components[I * 4 + 3] := Cp.Color.Alpha / 255.0;
    Locations[I] := Cp.Offset;
  end;

  Grad := CGGradientCreateWithColorComponents(FColorSpace,
    @Components[0], @Locations[0], Count);
  if Grad = nil then
  begin
    CGContextBeginPath(FCG);
    Exit;
  end;
  try
    CGContextSetLineWidth(FCG, Width);
    ApplyDashPattern;
    CGContextReplacePathWithStrokedPath(FCG);
    ClearDashPattern;
    CGContextSaveGState(FCG);
    try
      CGContextClip(FCG);
      CGContextDrawRadialGradient(FCG, Grad,
        CGPointMake(Gradient.Position.X, Gradient.Position.Y), 0,
        CGPointMake(Gradient.Position.X, Gradient.Position.Y),
        Gradient.Radius.X,
        kCGGradientDrawsBeforeStartLocation or
          kCGGradientDrawsAfterEndLocation);
    finally
      CGContextRestoreGState(FCG);
    end;
  finally
    CGGradientRelease(Grad);
  end;
end;

procedure TPixieCGCanvas.ClipPath(FillRule: TPixieFillRule);
begin
  if FCG = nil then Exit;
  if FillRule = frEvenOdd then
    CGContextEOClip(FCG)
  else
    CGContextClip(FCG);
end;

procedure TPixieCGCanvas.ConcatMatrix(A, B, C, D, E, F: Single);
var
  M: CGAffineTransform;
begin
  if FCG = nil then Exit;
  M.a := A;   M.b := B;
  M.c := C;   M.d := D;
  M.tx := E;  M.ty := F;
  CGContextConcatCTM(FCG, M);
end;

// ---------------------------------------------------------------------------
// Scale / View size
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.SetViewSize(W, H: Integer; ACanvasScale: Single);
begin
  FViewWidth := W;
  FViewHeight := H;
  FCanvasScale := ACanvasScale;
end;

// ---------------------------------------------------------------------------
// Offscreen rendering (CGBitmapContext)
// ---------------------------------------------------------------------------

procedure TPixieCGCanvas.GetTransformScale(out ScaleX, ScaleY: Single);
var
  M: CGAffineTransform;
begin
  if FCG = nil then
  begin
    ScaleX := 1;
    ScaleY := 1;
    Exit;
  end;
  M := CGContextGetCTM(FCG);
  ScaleX := Sqrt(Sqr(M.a) + Sqr(M.b));
  ScaleY := Sqrt(Sqr(M.c) + Sqr(M.d));
end;

function TPixieCGCanvas.BeginTileRender(Width, Height: Integer): Boolean;
begin
  Result := False;
  FTileContext := CGBitmapContextCreate(nil, Width, Height, 8, Width * 4,
    FColorSpace,
    kCGImageAlphaPremultipliedFirst or kCGBitmapByteOrder32Little);
  if FTileContext = nil then Exit;

  // Save current state
  FTileSavedCG := FCG;
  FTileSavedStateTop := FStateTop;
  FTileSavedViewW := FViewWidth;
  FTileSavedViewH := FViewHeight;

  FCG := FTileContext;
  FViewWidth := Width;
  FViewHeight := Height;
  FStateTop := 0;

  // Flip coordinate system (CG is bottom-up)
  CGContextTranslateCTM(FCG, 0, Height);
  CGContextScaleCTM(FCG, 1, -1);

  // Bitmap starts zero-filled (transparent)
  FTileWidth := Width;
  FTileHeight := Height;
  Result := True;
end;

function TPixieCGCanvas.EndTileRender: TPixieImageHandle;
var
  Pixels: Pointer;
  Stride: Integer;
begin
  Result := 0;
  // Restore main canvas state (don't release FTileContext yet — need pixels)
  FCG := FTileSavedCG;
  FStateTop := FTileSavedStateTop;
  FViewWidth := FTileSavedViewW;
  FViewHeight := FTileSavedViewH;

  if FTileContext = nil then Exit;
  Pixels := CGBitmapContextGetData(FTileContext);
  Stride := FTileWidth * 4;
  if Pixels <> nil then
    Result := LoadImageFromPixels(FTileWidth, FTileHeight, Pixels, Stride);
  CGContextRelease(FTileContext);
  FTileContext := nil;
end;

function TPixieCGCanvas.BeginOffscreenPaint(
  Width, Height: Integer): CGContextRef;
begin
  // Create a bitmap context — CG allocates the pixel buffer
  Result := CGBitmapContextCreate(nil, Width, Height, 8, Width * 4,
    FColorSpace,
    kCGImageAlphaPremultipliedFirst or kCGBitmapByteOrder32Little);
  if Result = nil then Exit;

  FCG := Result;
  FViewWidth := Width;
  FViewHeight := Height;
  FStateTop := 0;

  // Flip coordinate system (CG is bottom-up, SVG is top-down)
  CGContextTranslateCTM(FCG, 0, Height);
  CGContextScaleCTM(FCG, 1, -1);

  // Clear to white
  CGContextSetRGBFillColor(FCG, 1, 1, 1, 1);
  CGContextFillRect(FCG, CGRectMake(0, 0, Width, Height));
end;

procedure TPixieCGCanvas.EndOffscreenPaint;
begin
  // Don't destroy — the context is returned to the caller for saving
  FCG := nil;
end;

procedure TPixieCGCanvas.SaveContextToPng(Ctx: CGContextRef;
  Width, Height: Integer; const FileName: string);
var
  Pixels: PByte;
  Stride: Integer;
  Img: TFPMemoryImage;
  Writer: TFPWriterPNG;
  X, Y: Integer;
  P: PByte;
  C: TFPColor;
begin
  if Ctx = nil then Exit;

  Pixels := CGBitmapContextGetData(Ctx);
  Stride := Width * 4;
  if Pixels = nil then Exit;

  Img := TFPMemoryImage.Create(Width, Height);
  try
    Writer := TFPWriterPNG.Create;
    try
      Writer.UseAlpha := True;
      for Y := 0 to Height - 1 do
      begin
        P := Pixels + Y * Stride;
        for X := 0 to Width - 1 do
        begin
          // BGRA -> FPColor 16-bit
          C.Blue := P[0] or (P[0] shl 8);
          C.Green := P[1] or (P[1] shl 8);
          C.Red := P[2] or (P[2] shl 8);
          C.Alpha := P[3] or (P[3] shl 8);
          Img.Colors[X, Y] := C;
          Inc(P, 4);
        end;
      end;
      Img.SaveToFile(FileName, Writer);
    finally
      Writer.Free;
    end;
  finally
    Img.Free;
  end;
end;

procedure TPixieCGCanvas.BeginOffscreen(Width, Height: Integer;
  ClearColor: TPixieWebColor);
begin
  if FOffscreenCtx <> nil then
    EndOffscreen;
  FOffscreenCtx := CGBitmapContextCreate(nil, Width, Height, 8, Width * 4,
    FColorSpace,
    kCGImageAlphaPremultipliedFirst or kCGBitmapByteOrder32Little);
  if FOffscreenCtx = nil then Exit;
  FCG := FOffscreenCtx;
  FOffscreenWidth := Width;
  FOffscreenHeight := Height;
  FViewWidth := Width;
  FViewHeight := Height;
  FStateTop := 0;
  CGContextTranslateCTM(FCG, 0, Height);
  CGContextScaleCTM(FCG, 1, -1);
  CGContextSetRGBFillColor(FCG,
    ClearColor.Red / 255, ClearColor.Green / 255,
    ClearColor.Blue / 255, ClearColor.Alpha / 255);
  CGContextFillRect(FCG, CGRectMake(0, 0, Width, Height));
end;

procedure TPixieCGCanvas.EndOffscreen;
begin
  FCG := nil;
  if FOffscreenCtx <> nil then
  begin
    CGContextRelease(FOffscreenCtx);
    FOffscreenCtx := nil;
  end;
end;

procedure TPixieCGCanvas.SaveAsPng(Stream: TStream);
var
  Pixels: Pointer;
begin
  if FOffscreenCtx = nil then Exit;
  Pixels := CGBitmapContextGetData(FOffscreenCtx);
  if Pixels = nil then Exit;
  WritePngStream(Stream, Pixels, FOffscreenWidth, FOffscreenHeight,
    FOffscreenWidth * 4);
end;

procedure TPixieCGCanvas.SaveAsBmp(Stream: TStream);
var
  Pixels: Pointer;
begin
  if FOffscreenCtx = nil then Exit;
  Pixels := CGBitmapContextGetData(FOffscreenCtx);
  if Pixels = nil then Exit;
  WriteBmpStream(Stream, Pixels, FOffscreenWidth, FOffscreenHeight,
    FOffscreenWidth * 4);
end;


end.
