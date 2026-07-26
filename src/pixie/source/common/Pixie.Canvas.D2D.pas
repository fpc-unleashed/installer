unit Pixie.Canvas.D2D;

// Direct2D + DirectWrite implementation of TPixieCanvas for Windows.
// Replaces GDI+ for jitter-free ClearType text and native gradient support.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Windows, ActiveX, SysUtils, Classes, Math, Generics.Collections,
  Pixie.Types, Pixie.WebColor, Pixie.Borders,
  Pixie.GradientLayer, Pixie.FontDescription,
  Pixie.Canvas,
  Pixie.D2DHeaders;

type
  PPixieD2DFont = ^TPixieD2DFont;
  TPixieD2DFont = record
    TextFormat: IDWriteTextFormat;
    Metrics: TPixieFontMetrics;
    DecorationLine: Integer;
    SmallCaps: Boolean;
  end;

  PPixieD2DImage = ^TPixieD2DImage;
  TPixieD2DImage = record
    WicSource: IWICBitmapSource;
    WicStream: IStream;       // Prevent premature release of underlying stream
    D2DBitmap: ID2D1Bitmap;
    SvgRenderer: TObject;     // TPixieSvgCanvasRenderer (owns)
    ImgWidth: UINT;
    ImgHeight: UINT;
    AspectOnly: Boolean;       // True when SVG has only viewBox (no width/height)
    AspectRatio: Single;       // viewBox width / height when AspectOnly
  end;

  TPixieD2DImageList = TList<PPixieD2DImage>;

  TPixieD2DSavedState = record
    Transform: TD2d1Matrix3x2F;
    ClipsPushed: Integer;
    LayersPushed: Integer;
  end;

  { TPixieD2DCanvas }

  TPixieD2DCanvas = class(TPixieCanvas)
  private
    FFactory: ID2D1Factory;
    FDWriteFactory: IDWriteFactory;
    FWicFactory: IWICImagingFactory;
    FTarget: ID2D1RenderTarget;
    FDCTarget: ID2D1DCRenderTarget;
    FBrush: ID2D1SolidColorBrush;
    FViewWidth: Integer;
    FViewHeight: Integer;
    FPathGeometry: ID2D1PathGeometry;
    FPathSink: ID2D1GeometrySink;
    FPathFigureOpen: Boolean;
    FStateStack: array[0..63] of TPixieD2DSavedState;
    FStateTop: Integer;
    FTileWicBitmap: IWICBitmap;
    FTileSavedTarget: ID2D1RenderTarget;
    FTileSavedBrush: ID2D1SolidColorBrush;
    FTileSavedStateTop: Integer;
    FTileSavedViewW, FTileSavedViewH: Integer;
    FOffscreenBitmap: IWICBitmap;
    FOffscreenDrawing: Boolean;
    FImages: TPixieD2DImageList;

    procedure RecreateTarget;
    procedure FlushOffscreenDrawing;
    function RegisterImage(Info: PPixieD2DImage): TPixieImageHandle;
    function ToColorF(const C: TPixieWebColor): TD2d1ColorF;
    function MakeRectF(X, Y, W, H: Single): TD2d1RectF;
    function MakePoint(X, Y: Single): TD2d1Point2f;
    procedure CreateRoundedRectGeometry(X, Y, W, H: Single;
      const R: TPixieBorderRadiuses; out Geom: ID2D1PathGeometry);
    function CreateGradientStops(const Points: TPixieColorPointList;
      out Collection: ID2D1GradientStopCollection): Boolean;
    procedure ApplyFillRule(FillRule: TPixieFillRule);
    function CreatePathStrokeStyle(StrokeWidth: Single): ID2D1StrokeStyle;
    procedure FinalizePath;
    function FindFontMetrics(const Family: UnicodeString;
      Weight: TDwriteFontWeight; Style: TDwriteFontStyle;
      out FM: TDwriteFontMetrics): Boolean;
    procedure DrawBorderSide(const Border: TPixieBorder;
      X1, Y1, X2, Y2: Single);
    function LoadSvgImage(const Path: string): TPixieImageHandle;
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
    function InstallFontFromMemory(Data: Pointer; Size: Integer;
      out Handle: PtrUInt): Boolean; override;
    procedure UninstallFont(Handle: PtrUInt); override;
    function DoMeasureText(const Text: string;
      Handle: TPixieFontHandle): TPixiePixel; override;
    procedure DrawText(const Text: string; Handle: TPixieFontHandle;
      Color: TPixieWebColor; X, Y, W, H: Single); override;
    procedure DrawTextAtBaseline(const Text: string;
      Handle: TPixieFontHandle; const Metrics: TPixieFontMetrics;
      Color: TPixieWebColor; X, BaselineY: Single); override;
    procedure StrokeTextAtBaseline(const Text: string;
      Handle: TPixieFontHandle; const Metrics: TPixieFontMetrics;
      Color: TPixieWebColor; Width: Single; X, BaselineY: Single); override;
    function PtToPx(Pt: Single): TPixiePixel; override;

    function LoadImage(const Path: string): TPixieImageHandle; override;
    function LoadImageFromStream(
      Stream: TStream): TPixieImageHandle; override;
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
    procedure FillPathLinearGradient(
      const Gradient: TPixieLinearGradientLayer;
      FillRule: TPixieFillRule = frNonZero); override;
    procedure FillPathRadialGradient(
      const Gradient: TPixieRadialGradientLayer;
      FillRule: TPixieFillRule = frNonZero); override;
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

    // Offscreen rendering (WIC bitmap target)
    function BeginOffscreenPaint(Width, Height: Integer): IWICBitmap;
    procedure EndOffscreenPaint;
    {$IFDEF FPC}
    procedure SaveWicBitmapToPng(const Bitmap: IWICBitmap;
      const FileName: string);
    {$ENDIF}

    // Public off-screen + image export API (TPixieCanvas overrides)
    procedure BeginOffscreen(Width, Height: Integer;
      ClearColor: TPixieWebColor); override;
    procedure EndOffscreen; override;
    procedure SaveAsPng(Stream: TStream); override;
    procedure SaveAsBmp(Stream: TStream); override;
  end;

implementation

uses
  {$IFDEF FPC}FPImage, FPWritePNG,{$ELSE}Vcl.Graphics, Vcl.Imaging.pngimage,{$ENDIF}
  Pixie.WebP, Pixie.SvgRenderer.Canvas;

function AddFontMemResourceEx(pFileView: Pointer; cjSize: DWORD;
  pvReserved: Pointer; pNumFonts: PDWORD): THandle;
  stdcall; external 'gdi32.dll' name 'AddFontMemResourceEx';
function RemoveFontMemResourceEx(fh: THandle): BOOL;
  stdcall; external 'gdi32.dll' name 'RemoveFontMemResourceEx';

var
  GCheckFontCanvas: TPixieD2DCanvas;
  GCheckFontWeight: TDwriteFontWeight;
  GCheckFontStyle: TDwriteFontStyle;

function CheckFontCb(const Name: string): Boolean;
var
  FM: TDwriteFontMetrics;
begin
  Result := GCheckFontCanvas.FindFontMetrics(
    UnicodeString(Name), GCheckFontWeight, GCheckFontStyle, FM);
end;

function CoCreateInstance(const clsid: TGUID; unkOuter: Pointer;
  dwClsContext: DWORD; const iid: TGUID; out pv): HResult; stdcall;
  external 'ole32.dll' name 'CoCreateInstance';


const
  CLSCTX_INPROC_SERVER = $1;
  D2D1_LAYER_OPTIONS_INITIALIZE_FOR_CLEARTYPE = 1;

  GUID_WICPixelFormat32bppPBGRA: TGUID = (
    D1: $6FDDC324; D2: $4E03; D3: $4BFE;
    D4: ($B1, $85, $3D, $77, $76, $8D, $C9, $10));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function TPixieD2DCanvas.ToColorF(const C: TPixieWebColor): TD2d1ColorF;
begin
  Result.r := C.Red / 255.0;
  Result.g := C.Green / 255.0;
  Result.b := C.Blue / 255.0;
  Result.a := C.Alpha / 255.0;
end;

function TPixieD2DCanvas.MakeRectF(X, Y, W, H: Single): TD2d1RectF;
begin
  // Snap edges to device pixels to prevent sub-pixel seams between
  // adjacent filled rectangles (D2D anti-aliases at non-integer coords)
  Result.left   := Round(X * FScale) / FScale;
  Result.top    := Round(Y * FScale) / FScale;
  Result.right  := Round((X + W) * FScale) / FScale;
  Result.bottom := Round((Y + H) * FScale) / FScale;
end;

function TPixieD2DCanvas.MakePoint(X, Y: Single): TD2d1Point2f;
begin
  Result.x := X;
  Result.y := Y;
end;

procedure TPixieD2DCanvas.CreateRoundedRectGeometry(X, Y, W, H: Single;
  const R: TPixieBorderRadiuses; out Geom: ID2D1PathGeometry);
var
  Sink: ID2D1GeometrySink;
  Arc: TD2d1ArcSegment;
begin
  Geom := nil;
  if FFactory = nil then Exit;
  if Failed(FFactory.CreatePathGeometry(Geom)) then Exit;
  if Failed(Geom.Open(Sink)) then begin Geom := nil; Exit; end;

  Sink.SetFillMode(D2D1_FILL_MODE_WINDING);

  // Start on left edge, below top-left corner
  Sink.BeginFigure(MakePoint(X, Y + R.TopLeftY),
    D2D1_FIGURE_BEGIN_FILLED);

  // Top-left arc
  if (R.TopLeftX > 0) and (R.TopLeftY > 0) then
  begin
    Arc.point := MakePoint(X + R.TopLeftX, Y);
    Arc.size.width := R.TopLeftX;
    Arc.size.height := R.TopLeftY;
    Arc.rotationAngle := 0;
    Arc.sweepDirection := D2D1_SWEEP_DIRECTION_CLOCKWISE;
    Arc.arcSize := D2D1_ARC_SIZE_SMALL;
    Sink.AddArc(Arc);
  end
  else
    Sink.AddLine(MakePoint(X, Y));

  // Top edge + top-right arc
  Sink.AddLine(MakePoint(X + W - R.TopRightX, Y));
  if (R.TopRightX > 0) and (R.TopRightY > 0) then
  begin
    Arc.point := MakePoint(X + W, Y + R.TopRightY);
    Arc.size.width := R.TopRightX;
    Arc.size.height := R.TopRightY;
    Arc.rotationAngle := 0;
    Arc.sweepDirection := D2D1_SWEEP_DIRECTION_CLOCKWISE;
    Arc.arcSize := D2D1_ARC_SIZE_SMALL;
    Sink.AddArc(Arc);
  end
  else
    Sink.AddLine(MakePoint(X + W, Y));

  // Right edge + bottom-right arc
  Sink.AddLine(MakePoint(X + W, Y + H - R.BottomRightY));
  if (R.BottomRightX > 0) and (R.BottomRightY > 0) then
  begin
    Arc.point := MakePoint(X + W - R.BottomRightX, Y + H);
    Arc.size.width := R.BottomRightX;
    Arc.size.height := R.BottomRightY;
    Arc.rotationAngle := 0;
    Arc.sweepDirection := D2D1_SWEEP_DIRECTION_CLOCKWISE;
    Arc.arcSize := D2D1_ARC_SIZE_SMALL;
    Sink.AddArc(Arc);
  end
  else
    Sink.AddLine(MakePoint(X + W, Y + H));

  // Bottom edge + bottom-left arc
  Sink.AddLine(MakePoint(X + R.BottomLeftX, Y + H));
  if (R.BottomLeftX > 0) and (R.BottomLeftY > 0) then
  begin
    Arc.point := MakePoint(X, Y + H - R.BottomLeftY);
    Arc.size.width := R.BottomLeftX;
    Arc.size.height := R.BottomLeftY;
    Arc.rotationAngle := 0;
    Arc.sweepDirection := D2D1_SWEEP_DIRECTION_CLOCKWISE;
    Arc.arcSize := D2D1_ARC_SIZE_SMALL;
    Sink.AddArc(Arc);
  end
  else
    Sink.AddLine(MakePoint(X, Y + H));

  // Close figure (draws left edge back to start)
  Sink.EndFigure(D2D1_FIGURE_END_CLOSED);
  Sink.Close;
end;

function TPixieD2DCanvas.CreateGradientStops(
  const Points: TPixieColorPointList;
  out Collection: ID2D1GradientStopCollection): Boolean;
var
  Stops: array of TD2d1GradientStop;
  I, Count: Integer;
begin
  Result := False;
  Collection := nil;
  if (FTarget = nil) or (Points = nil) then Exit;
  Count := Points.Count;
  if Count < 2 then Exit;

  SetLength(Stops, Count);
  for I := 0 to Count - 1 do
  begin
    Stops[I].position := Points[I].Offset;
    Stops[I].color := ToColorF(Points[I].Color);
  end;

  Result := Succeeded(FTarget.CreateGradientStopCollection(
    @Stops[0], Count, D2D1_GAMMA_2_2, D2D1_EXTEND_MODE_CLAMP,
    Collection));
end;

function TPixieD2DCanvas.FindFontMetrics(const Family: UnicodeString;
  Weight: TDwriteFontWeight; Style: TDwriteFontStyle;
  out FM: TDwriteFontMetrics): Boolean;
var
  FontCollection: IDWriteFontCollection;
  FamilyIndex: UINT32;
  Found: BOOL;
  FontFamily: IDWriteFontFamily;
  Font: IDWriteFont;
begin
  Result := False;
  FillChar(FM, SizeOf(FM), 0);
  if FDWriteFactory = nil then Exit;

  if Failed(FDWriteFactory.GetSystemFontCollection(FontCollection, False)) then Exit;
  if Failed(FontCollection.FindFamilyName(PWideChar(Family), FamilyIndex, Found)) then Exit;
  if not Found then Exit;
  if Failed(FontCollection.GetFontFamily(FamilyIndex, FontFamily)) then Exit;
  if Failed(FontFamily.GetFirstMatchingFont(Weight,
    DWRITE_FONT_STRETCH_NORMAL, Style, Font)) then Exit;

  Font.GetMetrics(FM);
  Result := FM.designUnitsPerEm > 0;
end;

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

procedure TPixieD2DCanvas.RecreateTarget;
var
  Props: TD2d1RenderTargetProperties;
  C: TD2d1ColorF;
  I: Integer;
begin
  FBrush := nil;
  FDCTarget := nil;
  FTarget := nil;

  // Invalidate cached D2D bitmaps; DrawImage recreates them lazily from WicSource
  for I := 0 to FImages.Count - 1 do
    FImages[I].D2DBitmap := nil;

  // Create DC render target
  if FFactory <> nil then
  begin
    FillChar(Props, SizeOf(Props), 0);
    Props._type := D2D1_RENDER_TARGET_TYPE_DEFAULT;
    Props.pixelFormat.format := DXGI_FORMAT_B8G8R8A8_UNORM;
    Props.pixelFormat.alphaMode := D2D1_ALPHA_MODE_PREMULTIPLIED;
    Props.dpiX := 96;
    Props.dpiY := 96;
    Props.usage := D2D1_RENDER_TARGET_USAGE_NONE;
    Props.minLevel := D2D1_FEATURE_LEVEL_DEFAULT;
    FFactory.CreateDCRenderTarget(Props, FDCTarget);
    FTarget := FDCTarget;
  end;

  // Create reusable solid brush
  if FTarget <> nil then
  begin
    C.r := 0; C.g := 0; C.b := 0; C.a := 1;
    FTarget.CreateSolidColorBrush(C, nil, FBrush);
  end;
end;

function TPixieD2DCanvas.RegisterImage(Info: PPixieD2DImage): TPixieImageHandle;
begin
  FImages.Add(Info);
  Result := TPixieImageHandle(Info);
end;

constructor TPixieD2DCanvas.Create;
var
  Unk: IUnknown;
begin
  inherited Create;
  FViewWidth := 800;
  FViewHeight := 600;
  FStateTop := 0;
  FImages := TPixieD2DImageList.Create;

  // Create D2D factory
  D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,
    IID_ID2D1Factory, nil, FFactory);

  // Create DirectWrite factory
  if Succeeded(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED,
    IID_IDWriteFactory, Unk)) then
    Unk.QueryInterface(IID_IDWriteFactory, FDWriteFactory);

  // Create WIC factory
  CoCreateInstance(CLSID_WICImagingFactory, nil, CLSCTX_INPROC_SERVER,
    IID_IWICImagingFactory, FWicFactory);

  RecreateTarget;
end;

destructor TPixieD2DCanvas.Destroy;
begin
  // COM interfaces release automatically
  FBrush := nil;
  FDCTarget := nil;
  FTarget := nil;
  FWicFactory := nil;
  FDWriteFactory := nil;
  FFactory := nil;
  FImages.Free;
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

procedure TPixieD2DCanvas.BeginPaint(DC: PtrUInt);
var
  R: TRect;
  M: TD2d1Matrix3x2F;
  HR: HResult;
begin
  if FTarget = nil then Exit;
  FStateTop := 0;

  R.Left := 0;
  R.Top := 0;
  R.Right := FViewWidth;
  R.Bottom := FViewHeight;

  // BindDC may return D2DERR_RECREATE_TARGET after session disconnect/reconnect.
  // In that case recreate the target and retry once.
  if FDCTarget = nil then Exit;
  HR := FDCTarget.BindDC(HDC(DC), R);
  if HR = D2DERR_RECREATE_TARGET then
  begin
    RecreateTarget;
    if FDCTarget = nil then Exit;
    HR := FDCTarget.BindDC(HDC(DC), R);
  end;
  if Failed(HR) then Exit;

  FTarget.BeginDraw;
  FTarget.SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
  FTarget.SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_CLEARTYPE);

  // Apply scale transform
  FillChar(M, SizeOf(M), 0);
  M.m11 := FScale;
  M.m22 := FScale;
  FTarget.SetTransform(@M);
end;

procedure TPixieD2DCanvas.EndPaint;
begin
  if FTarget = nil then Exit;
  if FTarget.EndDraw(nil, nil) = D2DERR_RECREATE_TARGET then
    RecreateTarget;
end;

// ---------------------------------------------------------------------------
// State save/restore
// ---------------------------------------------------------------------------

procedure TPixieD2DCanvas.SaveState;
begin
  if (FTarget = nil) or (FStateTop > High(FStateStack)) then Exit;

  FTarget.GetTransform(FStateStack[FStateTop].Transform);
  FStateStack[FStateTop].ClipsPushed := 0;
  FStateStack[FStateTop].LayersPushed := 0;
  Inc(FStateTop);
end;

procedure TPixieD2DCanvas.RestoreState;
var
  I: Integer;
begin
  if (FTarget = nil) or (FStateTop <= 0) then Exit;
  Dec(FStateTop);

  // Pop layers
  for I := 0 to FStateStack[FStateTop].LayersPushed - 1 do
    FTarget.PopLayer;

  // Pop axis-aligned clips
  for I := 0 to FStateStack[FStateTop].ClipsPushed - 1 do
    FTarget.PopAxisAlignedClip;

  // Restore transform
  FTarget.SetTransform(@FStateStack[FStateTop].Transform);
end;

procedure TPixieD2DCanvas.PushOpacity(AOpacity: Single);
var
  Params: TD2d1LayerParameters;
begin
  if FTarget = nil then Exit;

  FillChar(Params, SizeOf(Params), 0);
  Params.contentBounds.left := -1e6;
  Params.contentBounds.top := -1e6;
  Params.contentBounds.right := 1e6;
  Params.contentBounds.bottom := 1e6;
  Params.maskAntialiasMode := D2D1_ANTIALIAS_MODE_PER_PRIMITIVE;
  Params.maskTransform._11 := 1;
  Params.maskTransform._22 := 1;
  Params.opacity := AOpacity;
  Params.layerOptions := D2D1_LAYER_OPTIONS_INITIALIZE_FOR_CLEARTYPE;
  FTarget.PushLayer(@Params, nil);

  if FStateTop > 0 then
    Inc(FStateStack[FStateTop - 1].LayersPushed);
end;

procedure TPixieD2DCanvas.PopOpacity;
begin
  if FTarget = nil then Exit;
  FTarget.PopLayer;

  if FStateTop > 0 then
    Dec(FStateStack[FStateTop - 1].LayersPushed);
end;

procedure TPixieD2DCanvas.PushMask(MaskHandle: TPixieImageHandle;
  MaskX, MaskY, MaskW, MaskH: Single);
var
  Info: PPixieD2DImage;
  W, H, Stride: UINT;
  Pixels: PByte;
  BufSize, I: Integer;
  MaskBmp: ID2D1Bitmap;
  BmpSize: TD2d1SizeU;
  BmpProps: TD2d1BitmapProperties;
  BrushBmpProps: TD2d1BitmapBrushProperties;
  BrushProps: TD2d1BrushProperties;
  BitmapBrush: ID2D1BitmapBrush;
  Params: TD2d1LayerParameters;
begin
  if (MaskHandle = 0) or (FTarget = nil) then Exit;
  Info := PPixieD2DImage(MaskHandle);
  if Info.WicSource = nil then Exit;
  if (MaskW <= 0) or (MaskH <= 0) then Exit;

  Info.WicSource.GetSize(W, H);
  if (W = 0) or (H = 0) then Exit;
  Stride := W * 4;
  BufSize := Stride * H;
  GetMem(Pixels, BufSize);
  try
    if Failed(Info.WicSource.CopyPixels(nil, Stride, BufSize, Pixels)) then Exit;

    // Convert luminance to alpha in-place: grayscale PNG has R=G=B=luminance,
    // A=255. D2D opacity brush uses brush alpha, so set A=luminance, clear RGB.
    for I := 0 to W * H - 1 do
    begin
      Pixels[I * 4 + 3] := Pixels[I * 4 + 2]; // A = R (luminance)
      Pixels[I * 4 + 0] := 0;
      Pixels[I * 4 + 1] := 0;
      Pixels[I * 4 + 2] := 0;
    end;

    BmpSize.width := W;
    BmpSize.height := H;
    BmpProps.pixelFormat.format := DXGI_FORMAT_B8G8R8A8_UNORM;
    BmpProps.pixelFormat.alphaMode := D2D1_ALPHA_MODE_PREMULTIPLIED;
    BmpProps.dpiX := 96;
    BmpProps.dpiY := 96;
    if Failed(FTarget.CreateBitmap(BmpSize, Pixels, Stride,
      @BmpProps, MaskBmp)) then Exit;
  finally
    FreeMem(Pixels);
  end;

  // Create bitmap brush from mask bitmap
  BrushBmpProps.extendModeX := D2D1_EXTEND_MODE_CLAMP;
  BrushBmpProps.extendModeY := D2D1_EXTEND_MODE_CLAMP;
  BrushBmpProps.interpolationMode := D2D1_BITMAP_INTERPOLATION_MODE_LINEAR;

  BrushProps.opacity := 1.0;
  BrushProps.transform.m11 := MaskW / W;
  BrushProps.transform.m12 := 0;
  BrushProps.transform.m21 := 0;
  BrushProps.transform.m22 := MaskH / H;
  BrushProps.transform.dx := MaskX;
  BrushProps.transform.dy := MaskY;

  if Failed(FTarget.CreateBitmapBrush(MaskBmp,
    @BrushBmpProps, @BrushProps, BitmapBrush)) then Exit;

  // Push layer with opacity brush
  FillChar(Params, SizeOf(Params), 0);
  Params.contentBounds.left := -1e6;
  Params.contentBounds.top := -1e6;
  Params.contentBounds.right := 1e6;
  Params.contentBounds.bottom := 1e6;
  Params.maskAntialiasMode := D2D1_ANTIALIAS_MODE_PER_PRIMITIVE;
  Params.maskTransform._11 := 1;
  Params.maskTransform._22 := 1;
  Params.opacity := 1.0;
  Params.opacityBrush := Pointer(BitmapBrush);
  Params.layerOptions := 0; // D2D1_LAYER_OPTIONS_NONE (not CLEARTYPE — needed for opacity brush)
  FTarget.PushLayer(@Params, nil);

  if FStateTop > 0 then
    Inc(FStateStack[FStateTop - 1].LayersPushed);
end;

procedure TPixieD2DCanvas.PopMask;
begin
  if FTarget = nil then Exit;
  FTarget.PopLayer;

  if FStateTop > 0 then
    Dec(FStateStack[FStateTop - 1].LayersPushed);
end;

// ---------------------------------------------------------------------------
// Clipping
// ---------------------------------------------------------------------------

procedure TPixieD2DCanvas.SetClipRect(const R: TPixiePosition;
  const Radius: TPixieBorderRadiuses);
var
  Rect: TD2d1RectF;
begin
  if FTarget = nil then Exit;

  Rect := MakeRectF(R.X, R.Y, R.Width, R.Height);
  FTarget.PushAxisAlignedClip(@Rect, D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);

  if FStateTop > 0 then
    Inc(FStateStack[FStateTop - 1].ClipsPushed);
end;

// ---------------------------------------------------------------------------
// Solid fills
// ---------------------------------------------------------------------------

procedure TPixieD2DCanvas.FillRect(X, Y, W, H: Single;
  Color: TPixieWebColor);
var
  R: TD2d1RectF;
begin
  if (FTarget = nil) or (Color.Alpha = 0) then Exit;
  FBrush.SetColor(ToColorF(Color));
  R := MakeRectF(X, Y, W, H);
  FTarget.FillRectangle(@R, FBrush);
end;

procedure TPixieD2DCanvas.FillRoundedRect(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses; Color: TPixieWebColor);
var
  R: TD2d1RectF;
  Geom: ID2D1PathGeometry;
begin
  if (FTarget = nil) or (Color.Alpha = 0) then Exit;
  FBrush.SetColor(ToColorF(Color));

  if Radius.HasRadius then
  begin
    CreateRoundedRectGeometry(X, Y, W, H, Radius, Geom);
    if Geom <> nil then
      FTarget.FillGeometry(Geom, FBrush);
  end
  else
  begin
    R := MakeRectF(X, Y, W, H);
    FTarget.FillRectangle(@R, FBrush);
  end;
end;

// ---------------------------------------------------------------------------
// Gradients
// ---------------------------------------------------------------------------

procedure TPixieD2DCanvas.FillLinearGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieLinearGradientLayer);
var
  Stops: ID2D1GradientStopCollection;
  Props: TD2d1LinearGradientBrushProperties;
  LBrush: ID2D1LinearGradientBrush;
  R: TD2d1RectF;
  Geom: ID2D1PathGeometry;
begin
  if (FTarget = nil) or (Gradient = nil) then Exit;
  if not CreateGradientStops(Gradient.ColorPoints, Stops) then Exit;

  Props.startPoint := MakePoint(Gradient.StartPt.X, Gradient.StartPt.Y);
  Props.endPoint := MakePoint(Gradient.EndPt.X, Gradient.EndPt.Y);

  if Failed(FTarget.CreateLinearGradientBrush(@Props, nil, Stops,
    LBrush)) then Exit;

  if Radius.HasRadius then
  begin
    CreateRoundedRectGeometry(X, Y, W, H, Radius, Geom);
    if Geom <> nil then
      FTarget.FillGeometry(Geom, LBrush);
  end
  else
  begin
    R := MakeRectF(X, Y, W, H);
    FTarget.FillRectangle(@R, LBrush);
  end;
end;

procedure TPixieD2DCanvas.FillRadialGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieRadialGradientLayer);
var
  Stops: ID2D1GradientStopCollection;
  Props: TD2d1RadialGradientBrushProperties;
  RBrush: ID2D1RadialGradientBrush;
  R: TD2d1RectF;
  Geom: ID2D1PathGeometry;
begin
  if (FTarget = nil) or (Gradient = nil) then Exit;
  if not CreateGradientStops(Gradient.ColorPoints, Stops) then Exit;

  Props.center := MakePoint(Gradient.Position.X, Gradient.Position.Y);
  Props.gradientOriginOffset := MakePoint(0, 0);
  Props.radiusX := Gradient.Radius.X;
  Props.radiusY := Gradient.Radius.Y;

  if Failed(FTarget.CreateRadialGradientBrush(@Props, nil, Stops,
    RBrush)) then Exit;

  // Clip to target rect, then fill the full ellipse area
  SaveState;
  try
    if Radius.HasRadius then
    begin
      CreateRoundedRectGeometry(X, Y, W, H, Radius, Geom);
      if Geom <> nil then
        FTarget.FillGeometry(Geom, RBrush);
    end
    else
    begin
      R := MakeRectF(X, Y, W, H);
      FTarget.PushAxisAlignedClip(@R, D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
      try
        R := MakeRectF(
          Gradient.Position.X - Gradient.Radius.X,
          Gradient.Position.Y - Gradient.Radius.Y,
          Gradient.Radius.X * 2,
          Gradient.Radius.Y * 2);
        FTarget.FillRectangle(@R, RBrush);
      finally
        FTarget.PopAxisAlignedClip;
      end;
    end;
  finally
    RestoreState;
  end;
end;

procedure TPixieD2DCanvas.FillConicGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieConicGradientLayer);
var
  Count, I, Steps, J: Integer;
  Cx, Cy, MaxR, Angle, Frac: Single;
  Cp: TPixieColorPoint;
  SectorPath: ID2D1PathGeometry;
  Sink: ID2D1GeometrySink;
  C: TPixieWebColor;
  StartAngle, SweepAngle, CosA, SinA, CosB, SinB: Single;
  R: TD2d1RectF;
begin
  // D2D has no native conic gradient — approximate with pie sectors
  if (FTarget = nil) or (Gradient = nil) then Exit;
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
    begin
      SetClipRect(TPixiePosition.Create(X, Y, W, H), Radius);
    end
    else
    begin
      R := MakeRectF(X, Y, W, H);
      FTarget.PushAxisAlignedClip(@R, D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
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

      FBrush.SetColor(ToColorF(C));

      // Build pie sector as a triangle fan segment
      StartAngle := (Gradient.Angle - 90 + J * (360.0 / Steps)) * Pi / 180.0;

      SinCos(StartAngle, SinA, CosA);
      SinCos(StartAngle + SweepAngle, SinB, CosB);

      SectorPath := nil;
      if Failed(FFactory.CreatePathGeometry(SectorPath)) then Continue;
      if Failed(SectorPath.Open(Sink)) then Continue;
      Sink.SetFillMode(D2D1_FILL_MODE_WINDING);
      Sink.BeginFigure(MakePoint(Cx, Cy), D2D1_FIGURE_BEGIN_FILLED);
      Sink.AddLine(MakePoint(Cx + CosA * MaxR, Cy + SinA * MaxR));
      Sink.AddLine(MakePoint(Cx + CosB * MaxR, Cy + SinB * MaxR));
      Sink.EndFigure(D2D1_FIGURE_END_CLOSED);
      Sink.Close;

      FTarget.FillGeometry(SectorPath, FBrush);
    end;
  finally
    RestoreState;
  end;
end;

// ---------------------------------------------------------------------------
// Borders
// ---------------------------------------------------------------------------

procedure TPixieD2DCanvas.DrawBorderSide(const Border: TPixieBorder;
  X1, Y1, X2, Y2: Single);
var
  StrokeProps: TD2d1StrokeStyleProperties;
  StrokeStyle: ID2D1StrokeStyle;
  DashStyle: TD2d1DashStyle;
  LineW, Offset, Dx, Dy, Len, Nx, Ny: Single;
begin
  if (Border.Width <= 0) or (Border.Style = bsNone) or
     (Border.Style = bsHidden) then
    Exit;

  FBrush.SetColor(ToColorF(Border.Color));

  // Double border: two lines of width/3 separated by width/3 gap
  if Border.Style = bsDouble then
  begin
    LineW := Border.Width / 3;
    if LineW < 1 then LineW := 1;
    // Compute perpendicular normal
    Dx := X2 - X1;
    Dy := Y2 - Y1;
    Len := Sqrt(Dx * Dx + Dy * Dy);
    if Len < 0.001 then Exit;
    Nx := -Dy / Len;
    Ny := Dx / Len;
    Offset := Border.Width / 2 - LineW / 2;
    // Outer line
    FTarget.DrawLine(
      MakePoint(X1 - Nx * Offset, Y1 - Ny * Offset),
      MakePoint(X2 - Nx * Offset, Y2 - Ny * Offset),
      FBrush, LineW, nil);
    // Inner line
    FTarget.DrawLine(
      MakePoint(X1 + Nx * Offset, Y1 + Ny * Offset),
      MakePoint(X2 + Nx * Offset, Y2 + Ny * Offset),
      FBrush, LineW, nil);
    Exit;
  end;

  case Border.Style of
    bsDotted:  DashStyle := D2D1_DASH_STYLE_DOT;
    bsDashed:  DashStyle := D2D1_DASH_STYLE_DASH;
  else
    DashStyle := D2D1_DASH_STYLE_SOLID;
  end;

  if DashStyle <> D2D1_DASH_STYLE_SOLID then
  begin
    FillChar(StrokeProps, SizeOf(StrokeProps), 0);
    if Border.Style = bsDotted then
    begin
      StrokeProps.startCap := D2D1_CAP_STYLE_ROUND;
      StrokeProps.endCap := D2D1_CAP_STYLE_ROUND;
      StrokeProps.dashCap := D2D1_CAP_STYLE_ROUND;
    end
    else
    begin
      StrokeProps.startCap := D2D1_CAP_STYLE_FLAT;
      StrokeProps.endCap := D2D1_CAP_STYLE_FLAT;
      StrokeProps.dashCap := D2D1_CAP_STYLE_FLAT;
    end;
    StrokeProps.lineJoin := D2D1_LINE_JOIN_MITER;
    StrokeProps.miterLimit := 10;
    StrokeProps.dashStyle := DashStyle;
    StrokeProps.dashOffset := 0;
    FFactory.CreateStrokeStyle(StrokeProps, nil, 0, StrokeStyle);
    FTarget.DrawLine(MakePoint(X1, Y1), MakePoint(X2, Y2),
      FBrush, Border.Width, StrokeStyle);
  end
  else
    FTarget.DrawLine(MakePoint(X1, Y1), MakePoint(X2, Y2),
      FBrush, Border.Width, nil);
end;

procedure TPixieD2DCanvas.DrawBorders(const Borders: TPixieBorders;
  const Pos: TPixiePosition; IsRoot: Boolean);
var
  X, Y, W, H: Single;
  Geom: ID2D1PathGeometry;
  Resolved: TPixieBorders;
  B: ^TPixieBorders;
begin
  if FTarget = nil then Exit;
  if not Borders.IsVisible then Exit;
  if (Borders.Top.Style in [bsOutset, bsInset]) or
     (Borders.Right.Style in [bsOutset, bsInset]) or
     (Borders.Bottom.Style in [bsOutset, bsInset]) or
     (Borders.Left.Style in [bsOutset, bsInset]) then
  begin
    Resolved := Borders;
    Resolved.ResolveOutsetInset;
    B := @Resolved;
  end
  else
    B := @Borders;

  X := Pos.X;
  Y := Pos.Y;
  W := Pos.Width;
  H := Pos.Height;

  if B^.Radius.HasRadius then
  begin
    if (B^.Top.Width > 0) and (B^.Top.Style <> bsNone) then
    begin
      FBrush.SetColor(ToColorF(B^.Top.Color));
      CreateRoundedRectGeometry(X, Y, W, H, B^.Radius, Geom);
      if Geom <> nil then
        FTarget.DrawGeometry(Geom, FBrush, B^.Top.Width, nil);
      Exit;
    end;
  end;

  // Top
  DrawBorderSide(B^.Top,
    X, Y + B^.Top.Width / 2,
    X + W, Y + B^.Top.Width / 2);

  // Right
  DrawBorderSide(B^.Right,
    X + W - B^.Right.Width / 2, Y,
    X + W - B^.Right.Width / 2, Y + H);

  // Bottom
  DrawBorderSide(B^.Bottom,
    X, Y + H - B^.Bottom.Width / 2,
    X + W, Y + H - B^.Bottom.Width / 2);

  // Left
  DrawBorderSide(B^.Left,
    X + B^.Left.Width / 2, Y,
    X + B^.Left.Width / 2, Y + H);
end;

// ---------------------------------------------------------------------------
// Font management
// ---------------------------------------------------------------------------

function TPixieD2DCanvas.CreateFont(
  const Descr: TPixieFontDescription;
  out Metrics: TPixieFontMetrics): TPixieFontHandle;
var
  Info: PPixieD2DFont;
  WFamily: UnicodeString;
  WLocale: UnicodeString;
  DWWeight: TDwriteFontWeight;
  DWStyle: TDwriteFontStyle;
  FM: TDwriteFontMetrics;
  Scale: Single;
begin
  Result := 0;
  if FDWriteFactory = nil then Exit;

  New(Info);
  FillChar(Info^, SizeOf(TPixieD2DFont), 0);
  Info.DecorationLine := Descr.DecorationLine;
  Info.SmallCaps := Descr.Variant = fvSmallCaps;

  // Map font weight and style — clamp to DirectWrite range (1..950)
  // CSS Fonts Level 4 allows 1..1000 but DirectWrite max is ULTRA_BLACK (950)
  DWWeight := EnsureRange(Descr.Weight, 1, DWRITE_FONT_WEIGHT_ULTRA_BLACK);
  if Descr.Style = fstItalic then
    DWStyle := DWRITE_FONT_STYLE_ITALIC
  else
    DWStyle := DWRITE_FONT_STYLE_NORMAL;

  // Find font family — resolve CSS font-family list
  GCheckFontCanvas := Self;
  GCheckFontWeight := DWWeight;
  GCheckFontStyle := DWStyle;
  WFamily := UnicodeString(PixieResolveFontFamily(Descr.Family, CheckFontCb));
  FindFontMetrics(WFamily, DWWeight, DWStyle, FM);

  // Create text format with resolved family
  WLocale := '';
  if Failed(FDWriteFactory.CreateTextFormat(PWideChar(WFamily), nil,
    DWWeight, DWStyle, DWRITE_FONT_STRETCH_NORMAL, Descr.Size,
    PWideChar(WLocale), Info.TextFormat)) then
  begin
    Dispose(Info);
    Exit;
  end;

  // Set no-wrap mode
  Info.TextFormat.SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);

  // Calculate metrics from design metrics
  if FM.designUnitsPerEm > 0 then
  begin
    Scale := Descr.Size / FM.designUnitsPerEm;
    Metrics.Ascent := FM.ascent * Scale;
    Metrics.Descent := FM.descent * Scale;
    Metrics.Height := (Integer(FM.ascent) + FM.descent + FM.lineGap) * Scale;
    Metrics.XHeight := FM.xHeight * Scale;
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

procedure TPixieD2DCanvas.DoDeleteFont(Handle: TPixieFontHandle);
var
  Info: PPixieD2DFont;
begin
  if Handle = 0 then Exit;
  Info := PPixieD2DFont(Handle);
  Info.TextFormat := nil;  // release COM interface
  Dispose(Info);
end;

function TPixieD2DCanvas.InstallFontFromMemory(Data: Pointer; Size: Integer;
  out Handle: PtrUInt): Boolean;
var
  NumFonts: DWORD;
  H: THandle;
  Collection: IDWriteFontCollection;
begin
  NumFonts := 0;
  H := AddFontMemResourceEx(Data, Size, nil, @NumFonts);
  Result := H <> 0;
  Handle := PtrUInt(H);
  // Force DirectWrite to refresh its font collection cache
  if Result and (FDWriteFactory <> nil) then
    FDWriteFactory.GetSystemFontCollection(Collection, True);
end;

procedure TPixieD2DCanvas.UninstallFont(Handle: PtrUInt);
begin
  if Handle <> 0 then
    RemoveFontMemResourceEx(THandle(Handle));
end;

// Applies small-caps simulation: sets a reduced font size on ranges
// that were originally lowercase, then forces uniform line spacing
// so the baseline stays anchored even for all-lowercase words.
procedure ApplySmallCapsToLayout(const Original, Upper: UnicodeString;
  Layout: IDWriteTextLayout; const Metrics: TPixieFontMetrics);
var
  I, RunStart, Len: Integer;
  SmallSize: Single;
  Range: TDwriteTextRange;
  InLower: Boolean;
begin
  Len := Length(Original);
  SmallSize := Metrics.FontSize * PixieSmallCapsScale;
  RunStart := 0;
  InLower := False;
  for I := 1 to Len do
  begin
    if Original[I] <> Upper[I] then
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
        Range.startPosition := RunStart - 1;
        Range.length := I - RunStart;
        Layout.SetFontSize(SmallSize, Range);
        InLower := False;
      end;
    end;
  end;
  if InLower then
  begin
    Range.startPosition := RunStart - 1;
    Range.length := Len - RunStart + 1;
    Layout.SetFontSize(SmallSize, Range);
  end;

  // Pin the baseline to the full-size font so all-lowercase words
  // don't float up.  Method 1 = DWRITE_LINE_SPACING_METHOD_UNIFORM.
  Layout.SetLineSpacing(1, Metrics.Height, Metrics.Ascent);
end;

function TPixieD2DCanvas.DoMeasureText(const Text: string;
  Handle: TPixieFontHandle): TPixiePixel;
var
  Info: PPixieD2DFont;
  WText, WUpper: UnicodeString;
  Layout: IDWriteTextLayout;
  TM: TDwriteTextMetrics;
begin
  Result := 0;
  if (Handle = 0) or (FDWriteFactory = nil) then Exit;
  Info := PPixieD2DFont(Handle);
  if Info.TextFormat = nil then
  begin
    Result := Length(Text) * Info.Metrics.ChWidth;
    Exit;
  end;

  WText := UnicodeString(Text);

  if Info.SmallCaps then
  begin
    WUpper := WText;
    if Length(WUpper) > 0 then
      CharUpperBuffW(PWideChar(WUpper), Length(WUpper));
    if Failed(FDWriteFactory.CreateTextLayout(PWideChar(WUpper),
      Length(WUpper), Info.TextFormat, 100000, 100000, Layout)) then
    begin
      Result := Length(Text) * Info.Metrics.ChWidth;
      Exit;
    end;
    ApplySmallCapsToLayout(WText, WUpper, Layout, Info.Metrics);
  end
  else
  begin
    if Failed(FDWriteFactory.CreateTextLayout(PWideChar(WText),
      Length(WText), Info.TextFormat, 100000, 100000, Layout)) then
    begin
      Result := Length(Text) * Info.Metrics.ChWidth;
      Exit;
    end;
  end;

  if Succeeded(Layout.GetMetrics(TM)) then
    Result := TM.widthIncludingTrailingWhitespace
  else
    Result := Length(Text) * Info.Metrics.ChWidth;
end;

procedure TPixieD2DCanvas.DrawText(const Text: string;
  Handle: TPixieFontHandle; Color: TPixieWebColor;
  X, Y, W, H: Single);
var
  Info: PPixieD2DFont;
  WText, WUpper: UnicodeString;
  Layout: IDWriteTextLayout;
begin
  if (Handle = 0) or (FTarget = nil) then Exit;
  Info := PPixieD2DFont(Handle);
  if Info.TextFormat = nil then Exit;

  WText := UnicodeString(Text);

  if Info.SmallCaps then
  begin
    WUpper := WText;
    if Length(WUpper) > 0 then
      CharUpperBuffW(PWideChar(WUpper), Length(WUpper));
    if Failed(FDWriteFactory.CreateTextLayout(PWideChar(WUpper),
      Length(WUpper), Info.TextFormat, W, H, Layout)) then
      Exit;
    ApplySmallCapsToLayout(WText, WUpper, Layout, Info.Metrics);
  end
  else
  begin
    if Failed(FDWriteFactory.CreateTextLayout(PWideChar(WText),
      Length(WText), Info.TextFormat, W, H, Layout)) then
      Exit;
  end;

  // Text decoration is drawn at the element level (TPixieHtmlTag.DrawBackground)
  // to produce continuous lines spanning inline boxes including spaces.

  FBrush.SetColor(ToColorF(Color));
  FTarget.DrawTextLayout(MakePoint(X, Y), Layout, FBrush,
    D2D1_DRAW_TEXT_OPTIONS_NONE);
end;

procedure TPixieD2DCanvas.DrawTextAtBaseline(const Text: string;
  Handle: TPixieFontHandle; const Metrics: TPixieFontMetrics;
  Color: TPixieWebColor; X, BaselineY: Single);
var
  Info: PPixieD2DFont;
  WText: UnicodeString;
  Layout: IDWriteTextLayout;
begin
  if (Handle = 0) or (FTarget = nil) then Exit;
  Info := PPixieD2DFont(Handle);
  if Info.TextFormat = nil then Exit;

  WText := UnicodeString(Text);
  if Failed(FDWriteFactory.CreateTextLayout(PWideChar(WText),
    Length(WText), Info.TextFormat, 1.0e6, Metrics.Height, Layout)) then
    Exit;

  // Pin layout baseline to Ascent from the top so different fonts on the
  // same SVG text line align (DWrite default would shift by lineGap).
  Layout.SetLineSpacing(1, Metrics.Height, Metrics.Ascent);

  FBrush.SetColor(ToColorF(Color));
  FTarget.DrawTextLayout(MakePoint(X, BaselineY - Metrics.Ascent),
    Layout, FBrush, D2D1_DRAW_TEXT_OPTIONS_NONE);
end;

procedure TPixieD2DCanvas.StrokeTextAtBaseline(const Text: string;
  Handle: TPixieFontHandle; const Metrics: TPixieFontMetrics;
  Color: TPixieWebColor; Width: Single; X, BaselineY: Single);
var
  Info: PPixieD2DFont;
  WText: UnicodeString;
  Collection: IDWriteFontCollection;
  Family: IDWriteFontFamily;
  Font: IDWriteFont;
  Face: IDWriteFontFace;
  FamilyName: array[0..255] of WideChar;
  NameLen, FamilyIdx: UINT32;
  Exists: BOOL;
  CodePoints: array of UINT32;
  GlyphIndices: array of UINT16;
  I, CharLen: Integer;
  Geometry: ID2D1PathGeometry;
  Sink: ID2D1GeometrySink;
  SavedMatrix, TranslateMatrix: TD2d1Matrix3x2F;
begin
  if (Handle = 0) or (FTarget = nil) or (Width <= 0) then Exit;
  Info := PPixieD2DFont(Handle);
  if Info.TextFormat = nil then Exit;

  WText := UnicodeString(Text);
  if Length(WText) = 0 then Exit;

  // Get font face from text format: Collection → Family → Font → FontFace
  if Failed(Info.TextFormat.GetFontCollection(Collection)) then Exit;
  NameLen := Info.TextFormat.GetFontFamilyNameLength;
  if NameLen > High(FamilyName) then Exit;
  if Failed(Info.TextFormat.GetFontFamilyName(FamilyName[0], NameLen + 1)) then Exit;
  if Failed(Collection.FindFamilyName(@FamilyName[0], FamilyIdx, Exists)) or not Exists then Exit;
  if Failed(Collection.GetFontFamily(FamilyIdx, Family)) then Exit;
  if Failed(Family.GetFirstMatchingFont(Info.TextFormat.GetFontWeight,
    Info.TextFormat.GetFontStretch, Info.TextFormat.GetFontStyle, Font)) then Exit;
  if Failed(Font.CreateFontFace(Face)) then Exit;

  // Convert UTF-16 codepoints to glyph indices
  SetLength(CodePoints, Length(WText));
  CharLen := 0;
  I := 1;
  while I <= Length(WText) do
  begin
    if (I < Length(WText)) and
       (Word(WText[I]) >= $D800) and (Word(WText[I]) <= $DBFF) then
    begin
      CodePoints[CharLen] := ((Word(WText[I]) - $D800) shl 10) +
        (Word(WText[I + 1]) - $DC00) + $10000;
      Inc(I, 2);
    end
    else
    begin
      CodePoints[CharLen] := Word(WText[I]);
      Inc(I);
    end;
    Inc(CharLen);
  end;
  if CharLen = 0 then Exit;

  SetLength(GlyphIndices, CharLen);
  if Failed(Face.GetGlyphIndices(@CodePoints[0], CharLen, @GlyphIndices[0])) then Exit;

  if Failed(FFactory.CreatePathGeometry(Geometry)) then Exit;
  if Failed(Geometry.Open(Sink)) then Exit;
  Face.GetGlyphRunOutline(Info.TextFormat.GetFontSize, @GlyphIndices[0],
    nil, nil, CharLen, False, False, Sink);
  Sink.Close;

  // Draw stroked geometry at text position
  FTarget.GetTransform(SavedMatrix);
  TranslateMatrix.m11 := SavedMatrix.m11;
  TranslateMatrix.m12 := SavedMatrix.m12;
  TranslateMatrix.m21 := SavedMatrix.m21;
  TranslateMatrix.m22 := SavedMatrix.m22;
  TranslateMatrix.dx := SavedMatrix.m11 * X + SavedMatrix.m21 * BaselineY + SavedMatrix.dx;
  TranslateMatrix.dy := SavedMatrix.m12 * X + SavedMatrix.m22 * BaselineY + SavedMatrix.dy;
  FTarget.SetTransform(@TranslateMatrix);
  FBrush.SetColor(ToColorF(Color));
  FTarget.DrawGeometry(Geometry, FBrush, Width, nil);
  FTarget.SetTransform(@SavedMatrix);
end;

function TPixieD2DCanvas.PtToPx(Pt: Single): TPixiePixel;
begin
  Result := Trunc(Pt * 96.0 / 72.0);
end;

// ---------------------------------------------------------------------------
// Image
// ---------------------------------------------------------------------------

function TPixieD2DCanvas.LoadSvgImage(
  const Path: string): TPixieImageHandle;
var
  Stream: TFileStream;
  Data: AnsiString;
begin
  Result := 0;
  if not FileExists(Path) then Exit;
  try
    Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
  except
    Exit;
  end;
  try
    if Stream.Size <= 0 then Exit;
    SetLength(Data, Stream.Size);
    Stream.ReadBuffer(Data[1], Stream.Size);
  finally
    Stream.Free;
  end;
  Result := LoadSvgFromData(@Data[1], Length(Data));
end;

function TPixieD2DCanvas.LoadSvgFromData(Data: Pointer;
  Size: Integer): TPixieImageHandle;
var
  Info: PPixieD2DImage;
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

  New(Info);
  FillChar(Info^, SizeOf(TPixieD2DImage), 0);
  Info.SvgRenderer := Renderer;
  Info.ImgWidth := Round(W);
  Info.ImgHeight := Round(H);
  Info.AspectOnly := not Renderer.HasExplicitSize;
  Info.AspectRatio := Renderer.GetAspectRatio;
  Result := RegisterImage(Info);
end;

function TPixieD2DCanvas.LoadImage(
  const Path: string): TPixieImageHandle;
var
  Info: PPixieD2DImage;
  Resolved: string;
  WPath: UnicodeString;
  Decoder: IWICBitmapDecoder;
  Frame: IWICBitmapFrameDecode;
  Converter: IWICFormatConverter;
  IW, IH: UINT;
  WicBmp: IWICBitmap;
  FileStream: TFileStream;
  MemStream: TMemoryStream;
  Buf: Pointer;
  BufSize: Integer;
  Pixels: Pointer;
  PW, PH: Integer;
begin
  Result := 0;

  Resolved := ExpandFileName(Path);

  // SVG images use canvas path API renderer
  if LowerCase(ExtractFileExt(Resolved)) = '.svg' then
  begin
    Result := LoadSvgImage(Resolved);
    Exit;
  end;

  if FWicFactory = nil then Exit;
  WPath := UnicodeString(Resolved);

  // Fast path: WIC by filename. The extension hints at the decoder, so a
  // .png that's really a WebP can land on the wrong decoder — fall
  // through to byte-sniffed paths below on failure.
  if not Failed(FWicFactory.CreateDecoderFromFilename(PWideChar(WPath),
    GUID_NULL, GENERIC_READ, 0, Decoder)) and
     not Failed(Decoder.GetFrame(0, Frame)) and
     not Failed(FWicFactory.CreateFormatConverter(Converter)) and
     not Failed(Converter.Initialize(Frame, GUID_WICPixelFormat32bppPBGRA,
       WICBitmapDitherTypeNone, nil, 0, WICBitmapPaletteTypeCustom)) then
  begin
    Frame.GetSize(IW, IH);
    New(Info);
    FillChar(Info^, SizeOf(TPixieD2DImage), 0);
    Info.WicSource := Converter;
    Info.ImgWidth := IW;
    Info.ImgHeight := IH;
    Result := RegisterImage(Info);
    Exit;
  end;

  // Read once, dispatch from the buffer.
  try
    FileStream := TFileStream.Create(Resolved, fmOpenRead or fmShareDenyNone);
  except
    on EFOpenError do Exit;
  end;
  try
    BufSize := FileStream.Size;
    if BufSize < 12 then Exit;
    GetMem(Buf, BufSize);
    try
      FileStream.ReadBuffer(Buf^, BufSize);

      // Retry WIC with content-based detection (handles WebP-saved-as-.png
      // on Win10+ where WIC has native WebP support installed).
      MemStream := TMemoryStream.Create;
      try
        MemStream.WriteBuffer(Buf^, BufSize);
        MemStream.Position := 0;
        Result := LoadImageFromStream(MemStream);
        if Result <> 0 then Exit;
      finally
        MemStream.Free;
      end;

      // libwebp fallback for systems without WIC WebP support. Sniff
      // RIFF/WEBP magic so we don't waste libwebp on unrelated files.
      if CompareMem(Buf, PAnsiChar('RIFF'), 4) and
         CompareMem(PAnsiChar(Buf) + 8, PAnsiChar('WEBP'), 4) then
      begin
        if PixieWebPDecode(Buf, BufSize, PW, PH, Pixels) then
        try
          if not Failed(FWicFactory.CreateBitmapFromMemory(
            PW, PH, @GUID_WICPixelFormat32bppPBGRA,
            PW * 4, PW * PH * 4, Pixels, WicBmp)) then
          begin
            New(Info);
            FillChar(Info^, SizeOf(TPixieD2DImage), 0);
            Info.WicSource := WicBmp;
            Info.ImgWidth := PW;
            Info.ImgHeight := PH;
            Result := RegisterImage(Info);
          end;
        finally
          PixieWebPFreePixels(Pixels);
        end;
      end;
    finally
      FreeMem(Buf);
    end;
  finally
    FileStream.Free;
  end;
end;

function TPixieD2DCanvas.LoadImageFromStream(
  Stream: TStream): TPixieImageHandle;
var
  Info: PPixieD2DImage;
  Copy: TMemoryStream;
  AdapterStream: IStream;
  Decoder: IWICBitmapDecoder;
  Frame: IWICBitmapFrameDecode;
  Converter: IWICFormatConverter;
  IW, IH: UINT;
begin
  Result := 0;
  if (FWicFactory = nil) or (Stream = nil) or (Stream.Size = 0) then Exit;

  // Copy stream data — WIC's decoder may seek back to it lazily during
  // CreateBitmapFromWicBitmap, long after the caller has freed the original.
  // soOwned lets the adapter free the copy when all COM references drop.
  Copy := TMemoryStream.Create;
  Copy.CopyFrom(Stream, 0);
  Copy.Position := 0;
  AdapterStream := TStreamAdapter.Create(Copy, soOwned);

  if Failed(FWicFactory.CreateDecoderFromStream(AdapterStream,
    GUID_NULL, 0, Decoder)) then
    Exit;

  if Failed(Decoder.GetFrame(0, Frame)) then Exit;

  if Failed(FWicFactory.CreateFormatConverter(Converter)) then Exit;
  if Failed(Converter.Initialize(Frame, GUID_WICPixelFormat32bppPBGRA,
    WICBitmapDitherTypeNone, nil, 0, WICBitmapPaletteTypeCustom)) then
    Exit;

  Frame.GetSize(IW, IH);

  New(Info);
  FillChar(Info^, SizeOf(TPixieD2DImage), 0);
  Info.WicSource := Converter;
  Info.WicStream := AdapterStream;
  Info.ImgWidth := IW;
  Info.ImgHeight := IH;
  Result := RegisterImage(Info);
end;

function TPixieD2DCanvas.LoadImageFromPixels(Width, Height: Integer;
  Pixels: Pointer; Pitch: Integer): TPixieImageHandle;
var
  Info: PPixieD2DImage;
  BmpProps: TD2D1BitmapProperties;
  Sz: TD2D1SizeU;
begin
  Result := 0;
  if FTarget = nil then Exit;

  BmpProps.pixelFormat.format := DXGI_FORMAT_B8G8R8A8_UNORM;
  BmpProps.pixelFormat.alphaMode := D2D1_ALPHA_MODE_PREMULTIPLIED;
  BmpProps.dpiX := 96;
  BmpProps.dpiY := 96;
  Sz.width := Width;
  Sz.height := Height;

  New(Info);
  FillChar(Info^, SizeOf(TPixieD2DImage), 0);
  Info.ImgWidth := Width;
  Info.ImgHeight := Height;

  if Failed(FTarget.CreateBitmap(Sz, Pixels, Pitch,
    @BmpProps, Info.D2DBitmap)) then
  begin
    Dispose(Info);
    Exit;
  end;

  Result := RegisterImage(Info);
end;

procedure TPixieD2DCanvas.FreeImage(Handle: TPixieImageHandle);
var
  Info: PPixieD2DImage;
begin
  if Handle = 0 then Exit;
  Info := PPixieD2DImage(Handle);
  FImages.Remove(Info);
  Info.SvgRenderer.Free;
  Info.D2DBitmap := nil;
  Info.WicSource := nil;
  Info.WicStream := nil;
  Dispose(Info);
end;

procedure TPixieD2DCanvas.GetImageSize(Handle: TPixieImageHandle;
  out W, H: Single);
var
  Info: PPixieD2DImage;
begin
  W := 0;
  H := 0;
  if Handle = 0 then Exit;
  Info := PPixieD2DImage(Handle);
  W := Info.ImgWidth;
  H := Info.ImgHeight;
end;

function TPixieD2DCanvas.GetImageAspectInfo(Handle: TPixieImageHandle;
  out AspectRatio: Single): Boolean;
var
  Info: PPixieD2DImage;
begin
  AspectRatio := 0;
  Result := False;
  if Handle = 0 then Exit;
  Info := PPixieD2DImage(Handle);
  Result := Info.AspectOnly;
  if Result then
    AspectRatio := Info.AspectRatio;
end;

procedure TPixieD2DCanvas.DrawImage(Handle: TPixieImageHandle;
  DstX, DstY, DstW, DstH: Single);
var
  Info: PPixieD2DImage;
  R: TD2d1RectF;
begin
  if (Handle = 0) or (FTarget = nil) then Exit;
  Info := PPixieD2DImage(Handle);

  // SVG rendering via canvas path API
  if Info.SvgRenderer <> nil then
  begin
    TPixieSvgCanvasRenderer(Info.SvgRenderer).RenderToRect(
      DstX, DstY, DstW, DstH);
    Exit;
  end;

  // Lazy-create D2D bitmap from WIC source
  if (Info.D2DBitmap = nil) and (Info.WicSource <> nil) then
    FTarget.CreateBitmapFromWicBitmap(Info.WicSource, nil, Info.D2DBitmap);

  if Info.D2DBitmap = nil then Exit;

  R := MakeRectF(DstX, DstY, DstW, DstH);
  FTarget.DrawBitmap(Info.D2DBitmap, @R, 1.0,
    D2D1_BITMAP_INTERPOLATION_MODE_LINEAR, nil);
end;

procedure TPixieD2DCanvas.FillTiledImage(Handle: TPixieImageHandle;
  TileX, TileY, TileW, TileH: Single;
  FillX, FillY, FillW, FillH: Single);
var
  Info: PPixieD2DImage;
  BmpProps: TD2d1BitmapBrushProperties;
  BrushProps: TD2d1BrushProperties;
  BitmapBrush: ID2D1BitmapBrush;
  R: TD2d1RectF;
begin
  if (Handle = 0) or (FTarget = nil) then Exit;
  Info := PPixieD2DImage(Handle);

  // SVG images: fall back to base-class per-tile loop
  if Info.SvgRenderer <> nil then
  begin
    inherited;
    Exit;
  end;

  // Lazy-create D2D bitmap from WIC source
  if (Info.D2DBitmap = nil) and (Info.WicSource <> nil) then
    FTarget.CreateBitmapFromWicBitmap(Info.WicSource, nil, Info.D2DBitmap);
  if Info.D2DBitmap = nil then Exit;

  if (TileW <= 0) or (TileH <= 0) or
     (Info.ImgWidth = 0) or (Info.ImgHeight = 0) then Exit;

  BmpProps.extendModeX := D2D1_EXTEND_MODE_WRAP;
  BmpProps.extendModeY := D2D1_EXTEND_MODE_WRAP;
  BmpProps.interpolationMode := D2D1_BITMAP_INTERPOLATION_MODE_LINEAR;

  BrushProps.opacity := 1.0;
  BrushProps.transform.m11 := TileW / Info.ImgWidth;
  BrushProps.transform.m12 := 0;
  BrushProps.transform.m21 := 0;
  BrushProps.transform.m22 := TileH / Info.ImgHeight;
  BrushProps.transform.dx := TileX;
  BrushProps.transform.dy := TileY;

  if Failed(FTarget.CreateBitmapBrush(Info.D2DBitmap,
    @BmpProps, @BrushProps, BitmapBrush)) then Exit;

  R := MakeRectF(FillX, FillY, FillW, FillH);
  FTarget.FillRectangle(@R, BitmapBrush);
end;

// ---------------------------------------------------------------------------
// Simple shapes (list markers)
// ---------------------------------------------------------------------------

procedure TPixieD2DCanvas.FillEllipse(X, Y, W, H: Single;
  Color: TPixieWebColor);
var
  E: TD2d1Ellipse;
begin
  if (FTarget = nil) or (Color.Alpha = 0) then Exit;
  FBrush.SetColor(ToColorF(Color));
  E.point := MakePoint(X + W / 2, Y + H / 2);
  E.radiusX := W / 2;
  E.radiusY := H / 2;
  FTarget.FillEllipse(@E, FBrush);
end;

procedure TPixieD2DCanvas.DrawEllipse(X, Y, W, H: Single;
  Color: TPixieWebColor; StrokeWidth: Single);
var
  E: TD2d1Ellipse;
begin
  if (FTarget = nil) or (Color.Alpha = 0) then Exit;
  FBrush.SetColor(ToColorF(Color));
  E.point := MakePoint(X + W / 2, Y + H / 2);
  E.radiusX := W / 2;
  E.radiusY := H / 2;
  FTarget.DrawEllipse(@E, FBrush, StrokeWidth, nil);
end;

procedure TPixieD2DCanvas.DrawRect(X, Y, W, H: Single;
  Color: TPixieWebColor; StrokeWidth: Single);
var
  R: TD2d1RectF;
begin
  if (FTarget = nil) or (Color.Alpha = 0) then Exit;
  FBrush.SetColor(ToColorF(Color));
  R := MakeRectF(X, Y, W, H);
  FTarget.DrawRectangle(@R, FBrush, StrokeWidth, nil);
end;

procedure TPixieD2DCanvas.DrawLine(X1, Y1, X2, Y2: Single;
  Color: TPixieWebColor; StrokeWidth: Single;
  Style: TPixieTextDecorationStyle);
var
  StrokeProps: TD2d1StrokeStyleProperties;
  StrokeStyle: ID2D1StrokeStyle;
begin
  if (FTarget = nil) or (Color.Alpha = 0) then Exit;
  FBrush.SetColor(ToColorF(Color));
  if Style in [tdsDotted, tdsDashed] then
  begin
    StrokeProps.startCap := D2D1_CAP_STYLE_ROUND;
    StrokeProps.endCap := D2D1_CAP_STYLE_ROUND;
    StrokeProps.dashCap := D2D1_CAP_STYLE_ROUND;
    StrokeProps.lineJoin := D2D1_LINE_JOIN_ROUND;
    StrokeProps.miterLimit := 1;
    if Style = tdsDotted then
      StrokeProps.dashStyle := D2D1_DASH_STYLE_DOT
    else
      StrokeProps.dashStyle := D2D1_DASH_STYLE_DASH;
    StrokeProps.dashOffset := 0;
    if Succeeded(FFactory.CreateStrokeStyle(StrokeProps, nil, 0, StrokeStyle)) then
      FTarget.DrawLine(MakePoint(X1, Y1), MakePoint(X2, Y2),
        FBrush, StrokeWidth, StrokeStyle)
    else
      FTarget.DrawLine(MakePoint(X1, Y1), MakePoint(X2, Y2),
        FBrush, StrokeWidth, nil);
  end
  else
    FTarget.DrawLine(MakePoint(X1, Y1), MakePoint(X2, Y2),
      FBrush, StrokeWidth, nil);
end;

procedure TPixieD2DCanvas.StrokePolyline(const Points: array of Single;
  Color: TPixieWebColor; StrokeWidth: Single);
var
  Geom: ID2D1PathGeometry;
  Sink: ID2D1GeometrySink;
  StrokeProps: TD2d1StrokeStyleProperties;
  StrokeStyle: ID2D1StrokeStyle;
  Count, I: Integer;
begin
  Count := Length(Points) div 2;
  if (FTarget = nil) or (Color.Alpha = 0) or (Count < 2) then Exit;
  if FFactory.CreatePathGeometry(Geom) <> S_OK then Exit;
  if Geom.Open(Sink) <> S_OK then Exit;
  Sink.BeginFigure(MakePoint(Points[0], Points[1]), D2D1_FIGURE_BEGIN_HOLLOW);
  for I := 1 to Count - 1 do
    Sink.AddLine(MakePoint(Points[I * 2], Points[I * 2 + 1]));
  Sink.EndFigure(D2D1_FIGURE_END_OPEN);
  Sink.Close;

  FillChar(StrokeProps, SizeOf(StrokeProps), 0);
  StrokeProps.startCap := D2D1_CAP_STYLE_ROUND;
  StrokeProps.endCap := D2D1_CAP_STYLE_ROUND;
  StrokeProps.lineJoin := D2D1_LINE_JOIN_ROUND;
  StrokeProps.miterLimit := 10;
  StrokeProps.dashStyle := D2D1_DASH_STYLE_SOLID;
  FFactory.CreateStrokeStyle(StrokeProps, nil, 0, StrokeStyle);

  FBrush.SetColor(ToColorF(Color));
  FTarget.DrawGeometry(Geom, FBrush, StrokeWidth, StrokeStyle);
end;

// ---------------------------------------------------------------------------
// Scale / View size
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Path API
// ---------------------------------------------------------------------------

procedure TPixieD2DCanvas.ApplyFillRule(FillRule: TPixieFillRule);
begin
  if FPathSink <> nil then
  begin
    if FillRule = frEvenOdd then
      FPathSink.SetFillMode(D2D1_FILL_MODE_ALTERNATE)
    else
      FPathSink.SetFillMode(D2D1_FILL_MODE_WINDING);
  end;
end;

function TPixieD2DCanvas.CreatePathStrokeStyle(
  StrokeWidth: Single): ID2D1StrokeStyle;
const
  CapMap: array[TPixieLineCap] of Integer = (
    D2D1_CAP_STYLE_FLAT, D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_SQUARE);
  // D2D's plain MITER does not auto-bevel at degenerate turns (unlike Cairo/CG/Qt),
  // causing spike artifacts on 180-degree back-and-forth paths.
  // MITER_OR_BEVEL automatically falls back to bevel when the miter limit is
  // exceeded, matching SVG spec and other backends' behaviour.
  JoinMap: array[TPixieLineJoin] of Integer = (
    D2D1_LINE_JOIN_MITER_OR_BEVEL, D2D1_LINE_JOIN_ROUND, D2D1_LINE_JOIN_BEVEL);
var
  Props: TD2d1StrokeStyleProperties;
  Normalized: array of Single;
  I: Integer;
begin
  Result := nil;
  FillChar(Props, SizeOf(Props), 0);
  Props.startCap := CapMap[FPathLineCap];
  Props.endCap := CapMap[FPathLineCap];
  Props.dashCap := CapMap[FPathLineCap];
  Props.lineJoin := JoinMap[FPathLineJoin];
  Props.miterLimit := 4;
  // D2D custom dash values are in stroke-width multiples
  if (Length(FPathDashArray) > 0) and (StrokeWidth > 0) then
  begin
    Props.dashStyle := D2D1_DASH_STYLE_CUSTOM;
    Props.dashOffset := FPathDashOffset / StrokeWidth;
    SetLength(Normalized, Length(FPathDashArray));
    for I := 0 to High(FPathDashArray) do
      Normalized[I] := FPathDashArray[I] / StrokeWidth;
    FFactory.CreateStrokeStyle(Props, @Normalized[0],
      Length(Normalized), Result);
  end
  else
  begin
    Props.dashStyle := D2D1_DASH_STYLE_SOLID;
    FFactory.CreateStrokeStyle(Props, nil, 0, Result);
  end;
end;

procedure TPixieD2DCanvas.FinalizePath;
begin
  if FPathSink <> nil then
  begin
    if FPathFigureOpen then
    begin
      FPathSink.EndFigure(D2D1_FIGURE_END_OPEN);
      FPathFigureOpen := False;
    end;
    FPathSink.Close;
    FPathSink := nil;
  end;
end;

procedure TPixieD2DCanvas.BeginPath;
begin
  if FFactory = nil then Exit;
  FinalizePath;
  FPathGeometry := nil;
  FFactory.CreatePathGeometry(FPathGeometry);
  if FPathGeometry <> nil then
    FPathGeometry.Open(FPathSink);
  FPathFigureOpen := False;
end;

procedure TPixieD2DCanvas.MoveTo(X, Y: Single);
var
  Pt: TD2d1Point2f;
begin
  if FPathSink = nil then
    BeginPath;
  if FPathSink = nil then Exit;
  if FPathFigureOpen then
    FPathSink.EndFigure(D2D1_FIGURE_END_OPEN);
  Pt.x := X;
  Pt.y := Y;
  FPathSink.BeginFigure(Pt, D2D1_FIGURE_BEGIN_FILLED);
  FPathFigureOpen := True;
end;

procedure TPixieD2DCanvas.LineTo(X, Y: Single);
var
  Pt: TD2d1Point2f;
begin
  if (FPathSink = nil) or (not FPathFigureOpen) then Exit;
  Pt.x := X;
  Pt.y := Y;
  FPathSink.AddLine(Pt);
end;

procedure TPixieD2DCanvas.CurveTo(X1, Y1, X2, Y2, X3, Y3: Single);
var
  Seg: TD2d1BezierSegment;
begin
  if (FPathSink = nil) or (not FPathFigureOpen) then Exit;
  Seg.point1.x := X1; Seg.point1.y := Y1;
  Seg.point2.x := X2; Seg.point2.y := Y2;
  Seg.point3.x := X3; Seg.point3.y := Y3;
  FPathSink.AddBezier(Seg);
end;

procedure TPixieD2DCanvas.ClosePath;
begin
  if (FPathSink = nil) or (not FPathFigureOpen) then Exit;
  FPathSink.EndFigure(D2D1_FIGURE_END_CLOSED);
  FPathFigureOpen := False;
end;

procedure TPixieD2DCanvas.FillPath(Color: TPixieWebColor;
  FillRule: TPixieFillRule);
begin
  if FTarget = nil then Exit;
  ApplyFillRule(FillRule);
  FinalizePath;
  if FPathGeometry = nil then Exit;
  if Color.Alpha > 0 then
  begin
    FBrush.SetColor(ToColorF(Color));
    FTarget.FillGeometry(FPathGeometry, FBrush, nil);
  end;
  FPathGeometry := nil;
end;

procedure TPixieD2DCanvas.StrokePath(Color: TPixieWebColor; Width: Single);
var
  Style: ID2D1StrokeStyle;
begin
  if FTarget = nil then Exit;
  FinalizePath;
  if FPathGeometry = nil then Exit;
  if Color.Alpha > 0 then
  begin
    Style := CreatePathStrokeStyle(Width);
    FBrush.SetColor(ToColorF(Color));
    FTarget.DrawGeometry(FPathGeometry, FBrush, Width, Style);
  end;
  FPathGeometry := nil;
end;

procedure TPixieD2DCanvas.FillAndStrokePath(FillColor: TPixieWebColor;
  StrokeColor: TPixieWebColor; StrokeWidth: Single;
  FillRule: TPixieFillRule);
var
  Style: ID2D1StrokeStyle;
begin
  if FTarget = nil then Exit;
  ApplyFillRule(FillRule);
  FinalizePath;
  if FPathGeometry = nil then Exit;
  if FillColor.Alpha > 0 then
  begin
    FBrush.SetColor(ToColorF(FillColor));
    FTarget.FillGeometry(FPathGeometry, FBrush, nil);
  end;
  if StrokeColor.Alpha > 0 then
  begin
    Style := CreatePathStrokeStyle(StrokeWidth);
    FBrush.SetColor(ToColorF(StrokeColor));
    FTarget.DrawGeometry(FPathGeometry, FBrush, StrokeWidth, Style);
  end;
  FPathGeometry := nil;
end;

procedure TPixieD2DCanvas.DiscardPath;
begin
  FinalizePath;
  FPathGeometry := nil;
end;

procedure TPixieD2DCanvas.ClipPath(FillRule: TPixieFillRule);
var
  LayerParams: TD2d1LayerParameters;
begin
  if FTarget = nil then Exit;
  ApplyFillRule(FillRule);
  FinalizePath;
  if FPathGeometry = nil then Exit;
  FillChar(LayerParams, SizeOf(LayerParams), 0);
  LayerParams.contentBounds.left := -1e9;
  LayerParams.contentBounds.top := -1e9;
  LayerParams.contentBounds.right := 1e9;
  LayerParams.contentBounds.bottom := 1e9;
  LayerParams.geometricMask := FPathGeometry;
  LayerParams.maskAntialiasMode := D2D1_ANTIALIAS_MODE_PER_PRIMITIVE;
  LayerParams.maskTransform.m11 := 1;
  LayerParams.maskTransform.m22 := 1;
  LayerParams.opacity := 1.0;
  LayerParams.layerOptions := D2D1_LAYER_OPTIONS_INITIALIZE_FOR_CLEARTYPE;
  FTarget.PushLayer(@LayerParams, nil);
  if FStateTop > 0 then
    Inc(FStateStack[FStateTop - 1].LayersPushed);
  FPathGeometry := nil;
end;

procedure TPixieD2DCanvas.FillPathLinearGradient(
  const Gradient: TPixieLinearGradientLayer;
  FillRule: TPixieFillRule);
var
  Stops: ID2D1GradientStopCollection;
  Props: TD2d1LinearGradientBrushProperties;
  BP: TD2d1BrushProperties;
  PBP: PD2d1BrushProperties;
  LBrush: ID2D1LinearGradientBrush;
begin
  if (FTarget = nil) or (Gradient = nil) then Exit;
  ApplyFillRule(FillRule);
  FinalizePath;
  if FPathGeometry = nil then Exit;
  if not CreateGradientStops(Gradient.ColorPoints, Stops) then
  begin
    FPathGeometry := nil;
    Exit;
  end;
  Props.startPoint := MakePoint(Gradient.StartPt.X, Gradient.StartPt.Y);
  Props.endPoint := MakePoint(Gradient.EndPt.X, Gradient.EndPt.Y);
  if Gradient.HasBrushTransform then
  begin
    BP.opacity := 1.0;
    BP.transform.m11 := Gradient.BrushTransform.M11;
    BP.transform.m12 := Gradient.BrushTransform.M12;
    BP.transform.m21 := Gradient.BrushTransform.M21;
    BP.transform.m22 := Gradient.BrushTransform.M22;
    BP.transform.dx := Gradient.BrushTransform.DX;
    BP.transform.dy := Gradient.BrushTransform.DY;
    PBP := @BP;
  end
  else
    PBP := nil;
  if Succeeded(FTarget.CreateLinearGradientBrush(@Props, PBP, Stops,
    LBrush)) then
    FTarget.FillGeometry(FPathGeometry, LBrush, nil);
  FPathGeometry := nil;
end;

procedure TPixieD2DCanvas.FillPathRadialGradient(
  const Gradient: TPixieRadialGradientLayer;
  FillRule: TPixieFillRule);
var
  Stops: ID2D1GradientStopCollection;
  Props: TD2d1RadialGradientBrushProperties;
  BP: TD2d1BrushProperties;
  PBP: PD2d1BrushProperties;
  RBrush: ID2D1RadialGradientBrush;
begin
  if (FTarget = nil) or (Gradient = nil) then Exit;
  ApplyFillRule(FillRule);
  FinalizePath;
  if FPathGeometry = nil then Exit;
  if not CreateGradientStops(Gradient.ColorPoints, Stops) then
  begin
    FPathGeometry := nil;
    Exit;
  end;
  Props.center := MakePoint(Gradient.Position.X, Gradient.Position.Y);
  Props.gradientOriginOffset := MakePoint(0, 0);
  Props.radiusX := Gradient.Radius.X;
  Props.radiusY := Gradient.Radius.Y;
  if Gradient.HasBrushTransform then
  begin
    BP.opacity := 1.0;
    BP.transform.m11 := Gradient.BrushTransform.M11;
    BP.transform.m12 := Gradient.BrushTransform.M12;
    BP.transform.m21 := Gradient.BrushTransform.M21;
    BP.transform.m22 := Gradient.BrushTransform.M22;
    BP.transform.dx := Gradient.BrushTransform.DX;
    BP.transform.dy := Gradient.BrushTransform.DY;
    PBP := @BP;
  end
  else
    PBP := nil;
  if Succeeded(FTarget.CreateRadialGradientBrush(@Props, PBP, Stops,
    RBrush)) then
    FTarget.FillGeometry(FPathGeometry, RBrush, nil);
  FPathGeometry := nil;
end;

procedure TPixieD2DCanvas.StrokePathLinearGradient(
  const Gradient: TPixieLinearGradientLayer; Width: Single);
var
  Stops: ID2D1GradientStopCollection;
  Props: TD2d1LinearGradientBrushProperties;
  LBrush: ID2D1LinearGradientBrush;
begin
  if (FTarget = nil) or (Gradient = nil) then Exit;
  FinalizePath;
  if FPathGeometry = nil then Exit;
  if not CreateGradientStops(Gradient.ColorPoints, Stops) then
  begin
    FPathGeometry := nil;
    Exit;
  end;
  Props.startPoint := MakePoint(Gradient.StartPt.X, Gradient.StartPt.Y);
  Props.endPoint := MakePoint(Gradient.EndPt.X, Gradient.EndPt.Y);
  if Succeeded(FTarget.CreateLinearGradientBrush(@Props, nil, Stops,
    LBrush)) then
    FTarget.DrawGeometry(FPathGeometry, LBrush, Width, CreatePathStrokeStyle(Width));
  FPathGeometry := nil;
end;

procedure TPixieD2DCanvas.StrokePathRadialGradient(
  const Gradient: TPixieRadialGradientLayer; Width: Single);
var
  Stops: ID2D1GradientStopCollection;
  Props: TD2d1RadialGradientBrushProperties;
  RBrush: ID2D1RadialGradientBrush;
begin
  if (FTarget = nil) or (Gradient = nil) then Exit;
  FinalizePath;
  if FPathGeometry = nil then Exit;
  if not CreateGradientStops(Gradient.ColorPoints, Stops) then
  begin
    FPathGeometry := nil;
    Exit;
  end;
  Props.center := MakePoint(Gradient.Position.X, Gradient.Position.Y);
  Props.gradientOriginOffset := MakePoint(0, 0);
  Props.radiusX := Gradient.Radius.X;
  Props.radiusY := Gradient.Radius.Y;
  if Succeeded(FTarget.CreateRadialGradientBrush(@Props, nil, Stops,
    RBrush)) then
    FTarget.DrawGeometry(FPathGeometry, RBrush, Width, CreatePathStrokeStyle(Width));
  FPathGeometry := nil;
end;

procedure TPixieD2DCanvas.ConcatMatrix(A, B, C, D, E, F: Single);
var
  Current, New_, Combined: TD2d1Matrix3x2F;
begin
  if FTarget = nil then Exit;
  FTarget.GetTransform(Current);
  New_.m11 := A;  New_.m12 := B;
  New_.m21 := C;  New_.m22 := D;
  New_.dx  := E;  New_.dy  := F;
  // SVG column-vector: Combined = Current * New_ (new transform in local space)
  // D2D stores transposed 2x2, so row-vector order is New_ * Current
  Combined.m11 := Current.m11 * New_.m11 + Current.m21 * New_.m12;
  Combined.m12 := Current.m12 * New_.m11 + Current.m22 * New_.m12;
  Combined.m21 := Current.m11 * New_.m21 + Current.m21 * New_.m22;
  Combined.m22 := Current.m12 * New_.m21 + Current.m22 * New_.m22;
  Combined.dx  := Current.m11 * New_.dx + Current.m21 * New_.dy + Current.dx;
  Combined.dy  := Current.m12 * New_.dx + Current.m22 * New_.dy + Current.dy;
  FTarget.SetTransform(@Combined);
end;

// ---------------------------------------------------------------------------
// View size / scale
// ---------------------------------------------------------------------------

procedure TPixieD2DCanvas.SetViewSize(W, H: Integer; ACanvasScale: Single);
begin
  FViewWidth := W;
  FViewHeight := H;
end;

// ---------------------------------------------------------------------------
// Off-screen tile rendering (pattern optimisation)
// ---------------------------------------------------------------------------

function TPixieD2DCanvas.BeginTileRender(Width, Height: Integer): Boolean;
var
  Props: TD2d1RenderTargetProperties;
  C: TD2d1ColorF;
  M: TD2d1Matrix3x2F;
begin
  Result := False;
  if (FWicFactory = nil) or (FFactory = nil) then Exit;

  // Create WIC bitmap
  if Failed(FWicFactory.CreateBitmap(Width, Height,
    @GUID_WICPixelFormat32bppPBGRA, WICBitmapCacheOnLoad,
    FTileWicBitmap)) then Exit;

  // Create render target on the WIC bitmap
  FillChar(Props, SizeOf(Props), 0);
  Props._type := D2D1_RENDER_TARGET_TYPE_DEFAULT;
  Props.pixelFormat.format := DXGI_FORMAT_B8G8R8A8_UNORM;
  Props.pixelFormat.alphaMode := D2D1_ALPHA_MODE_PREMULTIPLIED;
  Props.dpiX := 96;
  Props.dpiY := 96;

  // Save current state
  FTileSavedTarget := FTarget;
  FTileSavedBrush := FBrush;
  FTileSavedStateTop := FStateTop;
  FTileSavedViewW := FViewWidth;
  FTileSavedViewH := FViewHeight;

  if Failed(FFactory.CreateWicBitmapRenderTarget(
    FTileWicBitmap, Props, FTarget)) then
  begin
    FTileWicBitmap := nil;
    FTarget := FTileSavedTarget;
    Exit;
  end;

  C.r := 0; C.g := 0; C.b := 0; C.a := 1;
  FTarget.CreateSolidColorBrush(C, nil, FBrush);
  FViewWidth := Width;
  FViewHeight := Height;
  FStateTop := 0;
  FTarget.BeginDraw;
  FTarget.SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);

  FillChar(M, SizeOf(M), 0);
  M.m11 := 1; M.m22 := 1;
  FTarget.SetTransform(@M);

  // Clear to transparent
  C.r := 0; C.g := 0; C.b := 0; C.a := 0;
  FTarget.Clear(C);
  Result := True;
end;

function TPixieD2DCanvas.EndTileRender: TPixieImageHandle;
var
  W, H, Stride: UINT;
  Lock: IWICBitmapLock;
  R: WICRect;
  Data: PByte;
  BufSize: UINT;
begin
  Result := 0;
  // End offscreen drawing
  FTarget.EndDraw(nil, nil);

  // Restore main canvas state
  FTarget := FTileSavedTarget;
  FBrush := FTileSavedBrush;
  FStateTop := FTileSavedStateTop;
  FViewWidth := FTileSavedViewW;
  FViewHeight := FTileSavedViewH;
  FTileSavedTarget := nil;
  FTileSavedBrush := nil;

  if FTileWicBitmap = nil then Exit;
  if Failed(FTileWicBitmap.GetSize(W, H)) then
  begin
    FTileWicBitmap := nil;
    Exit;
  end;
  R.X := 0; R.Y := 0;
  R.Width := W; R.Height := H;
  if Failed(FTileWicBitmap.Lock(@R, WICBitmapLockRead, Lock)) then
  begin
    FTileWicBitmap := nil;
    Exit;
  end;
  Lock.GetStride(Stride);
  Lock.GetDataPointer(BufSize, Data);
  Result := LoadImageFromPixels(W, H, Data, Stride);
  Lock := nil;
  FTileWicBitmap := nil;
end;

// ---------------------------------------------------------------------------
procedure TPixieD2DCanvas.GetTransformScale(out ScaleX, ScaleY: Single);
var
  M: TD2d1Matrix3x2F;
begin
  if FTarget = nil then
  begin
    ScaleX := 1;
    ScaleY := 1;
    Exit;
  end;
  FTarget.GetTransform(M);
  ScaleX := Sqrt(Sqr(M.m11) + Sqr(M.m21));
  ScaleY := Sqrt(Sqr(M.m12) + Sqr(M.m22));
end;

// ---------------------------------------------------------------------------
// Offscreen rendering (WIC bitmap target)
// ---------------------------------------------------------------------------

function TPixieD2DCanvas.BeginOffscreenPaint(
  Width, Height: Integer): IWICBitmap;
var
  Props: TD2d1RenderTargetProperties;
  C: TD2d1ColorF;
  M: TD2d1Matrix3x2F;
begin
  Result := nil;
  if (FWicFactory = nil) or (FFactory = nil) then Exit;

  // Create WIC bitmap
  if Failed(FWicFactory.CreateBitmap(Width, Height,
    @GUID_WICPixelFormat32bppPBGRA, WICBitmapCacheOnLoad, Result)) then Exit;

  // Create WIC bitmap render target
  FillChar(Props, SizeOf(Props), 0);
  Props._type := D2D1_RENDER_TARGET_TYPE_DEFAULT;
  Props.pixelFormat.format := DXGI_FORMAT_B8G8R8A8_UNORM;
  Props.pixelFormat.alphaMode := D2D1_ALPHA_MODE_PREMULTIPLIED;
  Props.dpiX := 96;
  Props.dpiY := 96;
  if Failed(FFactory.CreateWicBitmapRenderTarget(
    Result, Props, FTarget)) then
  begin
    Result := nil;
    FTarget := FDCTarget;
    Exit;
  end;

  // Create brush on new target
  C.r := 0; C.g := 0; C.b := 0; C.a := 1;
  FTarget.CreateSolidColorBrush(C, nil, FBrush);

  FViewWidth := Width;
  FViewHeight := Height;
  FStateTop := 0;
  FTarget.BeginDraw;
  FTarget.SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
  FTarget.SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);

  // Identity transform
  FillChar(M, SizeOf(M), 0);
  M.m11 := 1;
  M.m22 := 1;
  FTarget.SetTransform(@M);

  // Clear to white
  C.r := 1; C.g := 1; C.b := 1; C.a := 1;
  FTarget.Clear(C);
end;

procedure TPixieD2DCanvas.EndOffscreenPaint;
var
  C: TD2d1ColorF;
begin
  if FTarget = nil then Exit;
  FTarget.EndDraw(nil, nil);

  // Restore DC render target
  FTarget := FDCTarget;
  if FDCTarget <> nil then
  begin
    C.r := 0; C.g := 0; C.b := 0; C.a := 1;
    FDCTarget.CreateSolidColorBrush(C, nil, FBrush);
  end;
end;

{$IFDEF FPC}
procedure TPixieD2DCanvas.SaveWicBitmapToPng(const Bitmap: IWICBitmap;
  const FileName: string);
var
  W, H, Stride: UINT;
  Pixels: PByte;
  BufSize: Integer;
  Img: TFPMemoryImage;
  Writer: TFPWriterPNG;
  X, Y: Integer;
  P: PByte;
  C: TFPColor;
begin
  if Bitmap = nil then Exit;

  // Get bitmap dimensions and pixel data
  Bitmap.GetSize(W, H);
  Stride := W * 4; // 32bpp BGRA
  BufSize := Stride * H;
  GetMem(Pixels, BufSize);
  try
    if Failed(Bitmap.CopyPixels(nil, Stride, BufSize, Pixels)) then Exit;

    // Create FPImage and copy pixels (BGRA -> FPColor 16-bit)
    Img := TFPMemoryImage.Create(W, H);
    try
      Writer := TFPWriterPNG.Create;
      try
        Writer.UseAlpha := True;
        for Y := 0 to H - 1 do
        begin
          P := Pixels + Y * Stride;
          for X := 0 to W - 1 do
          begin
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
  finally
    FreeMem(Pixels);
  end;
end;
{$ENDIF}

procedure TPixieD2DCanvas.FlushOffscreenDrawing;
begin
  if FOffscreenDrawing and (FTarget <> nil) then
  begin
    FTarget.EndDraw(nil, nil);
    FOffscreenDrawing := False;
  end;
end;

procedure TPixieD2DCanvas.BeginOffscreen(Width, Height: Integer;
  ClearColor: TPixieWebColor);
var
  Props: TD2d1RenderTargetProperties;
  C: TD2d1ColorF;
  M: TD2d1Matrix3x2F;
begin
  if FOffscreenBitmap <> nil then
    EndOffscreen;
  if (FWicFactory = nil) or (FFactory = nil) then Exit;
  if Failed(FWicFactory.CreateBitmap(Width, Height,
    @GUID_WICPixelFormat32bppPBGRA, WICBitmapCacheOnLoad,
    FOffscreenBitmap)) then Exit;

  FillChar(Props, SizeOf(Props), 0);
  Props._type := D2D1_RENDER_TARGET_TYPE_DEFAULT;
  Props.pixelFormat.format := DXGI_FORMAT_B8G8R8A8_UNORM;
  Props.pixelFormat.alphaMode := D2D1_ALPHA_MODE_PREMULTIPLIED;
  Props.dpiX := 96;
  Props.dpiY := 96;
  if Failed(FFactory.CreateWicBitmapRenderTarget(
    FOffscreenBitmap, Props, FTarget)) then
  begin
    FOffscreenBitmap := nil;
    FTarget := FDCTarget;
    Exit;
  end;

  C.r := 0; C.g := 0; C.b := 0; C.a := 1;
  FTarget.CreateSolidColorBrush(C, nil, FBrush);

  FViewWidth := Width;
  FViewHeight := Height;
  FStateTop := 0;
  FTarget.BeginDraw;
  FOffscreenDrawing := True;
  FTarget.SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
  FTarget.SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);

  FillChar(M, SizeOf(M), 0);
  M.m11 := 1;
  M.m22 := 1;
  FTarget.SetTransform(@M);

  C.r := ClearColor.Red / 255;
  C.g := ClearColor.Green / 255;
  C.b := ClearColor.Blue / 255;
  C.a := ClearColor.Alpha / 255;
  FTarget.Clear(C);
end;

procedure TPixieD2DCanvas.EndOffscreen;
var
  C: TD2d1ColorF;
begin
  FlushOffscreenDrawing;
  FTarget := FDCTarget;
  if FDCTarget <> nil then
  begin
    C.r := 0; C.g := 0; C.b := 0; C.a := 1;
    FDCTarget.CreateSolidColorBrush(C, nil, FBrush);
  end;
  FOffscreenBitmap := nil;
end;

procedure TPixieD2DCanvas.SaveAsPng(Stream: TStream);
var
  W, H, Stride: UINT;
  Pixels: PByte;
  BufSize: Integer;
  {$IFNDEF FPC}
  Png: TPngImage;
  X, Y: Integer;
  Src: PByte;
  DstRgb: PByte;
  DstAlpha: PByte;
  {$ENDIF}
begin
  if FOffscreenBitmap = nil then Exit;
  FlushOffscreenDrawing;
  FOffscreenBitmap.GetSize(W, H);
  Stride := W * 4;
  BufSize := Stride * H;
  GetMem(Pixels, BufSize);
  try
    if Failed(FOffscreenBitmap.CopyPixels(nil, Stride, BufSize, Pixels)) then
      Exit;
    {$IFDEF FPC}
    WritePngStream(Stream, Pixels, W, H, Stride);
    {$ELSE}
    Png := TPngImage.CreateBlank(COLOR_RGBALPHA, 8, W, H);
    try
      for Y := 0 to H - 1 do
      begin
        Src := Pixels + Y * Stride;
        DstRgb := Png.Scanline[Y];
        DstAlpha := PByte(Png.AlphaScanline[Y]);
        for X := 0 to W - 1 do
        begin
          // Src is premultiplied BGRA; TPngImage Scanline is BGR.
          DstRgb[0] := Src[0];
          DstRgb[1] := Src[1];
          DstRgb[2] := Src[2];
          DstAlpha[X] := Src[3];
          Inc(Src, 4);
          Inc(DstRgb, 3);
        end;
      end;
      Png.SaveToStream(Stream);
    finally
      Png.Free;
    end;
    {$ENDIF}
  finally
    FreeMem(Pixels);
  end;
end;

procedure TPixieD2DCanvas.SaveAsBmp(Stream: TStream);
var
  W, H, Stride: UINT;
  Pixels: PByte;
  BufSize: Integer;
begin
  if FOffscreenBitmap = nil then Exit;
  FlushOffscreenDrawing;
  FOffscreenBitmap.GetSize(W, H);
  Stride := W * 4;
  BufSize := Stride * H;
  GetMem(Pixels, BufSize);
  try
    if Failed(FOffscreenBitmap.CopyPixels(nil, Stride, BufSize, Pixels)) then
      Exit;
    WriteBmpStream(Stream, Pixels, W, H, Stride);
  finally
    FreeMem(Pixels);
  end;
end;


end.
