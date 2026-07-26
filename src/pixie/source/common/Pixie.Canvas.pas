unit Pixie.Canvas;

// Platform-independent drawing canvas interface.
// Concrete implementations: Pixie.Canvas.D2D (Windows), Pixie.Canvas.Cairo (Linux).

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Classes, Generics.Collections,
  Pixie.Types, Pixie.WebColor, Pixie.Borders,
  Pixie.GradientLayer, Pixie.FontDescription,
  Pixie.AnimatedImage;

type
  TPixieFontHandle = PtrUInt;
  TPixieImageHandle = PtrUInt;
  TPixieFillRule = (frNonZero, frEvenOdd);
  TPixieTextWidthMap = TDictionary<string, TPixiePixel>;
  TPixieTextWidthCache = TDictionary<TPixieFontHandle, TPixieTextWidthMap>;

  TPixieBlendMode = (
    bmNormal, bmMultiply, bmScreen, bmOverlay, bmDarken, bmLighten,
    bmColorDodge, bmColorBurn, bmHardLight, bmSoftLight,
    bmDifference, bmExclusion, bmHue, bmSaturation, bmColor, bmLuminosity
  );

  { TPixieCanvas }

  TPixieCanvas = class
  private
    FTextWidthCache: TPixieTextWidthCache;
  protected
    FScale: Single;
    FPathLineCap: TPixieLineCap;
    FPathLineJoin: TPixieLineJoin;
    FPathDashArray: array of Single;
    FPathDashOffset: Single;
    function DoMeasureText(const Text: string;
      Handle: TPixieFontHandle): TPixiePixel; virtual; abstract;
    procedure DoDeleteFont(Handle: TPixieFontHandle); virtual; abstract;
  public
    constructor Create;
    destructor Destroy; override;
    procedure ClearTextWidthCache;

    // Lifecycle — bind to a platform device context for painting
    procedure BeginPaint(DC: PtrUInt); virtual; abstract;
    procedure EndPaint; virtual; abstract;

    // Graphics state save/restore (used for push/pop clipping)
    procedure SaveState; virtual; abstract;
    procedure RestoreState; virtual; abstract;

    // Opacity layers
    procedure PushOpacity(AOpacity: Single); virtual;
    procedure PopOpacity; virtual;

    // Mask layers — applies a luminance mask image to all drawing until PopMask
    procedure PushMask(MaskHandle: TPixieImageHandle;
      MaskX, MaskY, MaskW, MaskH: Single); virtual;
    procedure PopMask; virtual;

    // Blend mode — returns True if the backend supports the requested mode
    function SetBlendMode(Mode: TPixieBlendMode): Boolean; virtual;
    procedure ResetBlendMode; virtual;

    // Path stroke style (line cap/join for SVG path operations)
    procedure SetPathStrokeStyle(Cap: TPixieLineCap; Join: TPixieLineJoin); virtual;
    procedure SetPathDashStyle(const DashArray: array of Single;
      DashOffset: Single); virtual;
    procedure ClearPathDashStyle; virtual;

    // Clipping
    procedure SetClipRect(const R: TPixiePosition;
      const Radius: TPixieBorderRadiuses); virtual; abstract;

    // Solid colour fill
    procedure FillRect(X, Y, W, H: Single;
      Color: TPixieWebColor); virtual; abstract;

    // Rounded-rect path fill
    procedure FillRoundedRect(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      Color: TPixieWebColor); overload; virtual; abstract;

    // Linear gradient fill
    procedure FillLinearGradient(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      const Gradient: TPixieLinearGradientLayer); virtual; abstract;

    // Radial gradient fill
    procedure FillRadialGradient(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      const Gradient: TPixieRadialGradientLayer); virtual; abstract;

    // Conic gradient fill (software fallback acceptable)
    procedure FillConicGradient(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses;
      const Gradient: TPixieConicGradientLayer); virtual; abstract;

    // Border drawing
    procedure DrawBorders(const Borders: TPixieBorders;
      const Pos: TPixiePosition; IsRoot: Boolean); virtual; abstract;

    // Font management
    function CreateFont(const Descr: TPixieFontDescription;
      out Metrics: TPixieFontMetrics): TPixieFontHandle; virtual; abstract;
    procedure DeleteFont(Handle: TPixieFontHandle);

    // Custom font installation (@font-face)
    function InstallFontFromMemory(Data: Pointer; Size: Integer;
      out Handle: PtrUInt): Boolean; virtual;
    procedure UninstallFont(Handle: PtrUInt); virtual;

    // Text
    function MeasureText(const Text: string;
      Handle: TPixieFontHandle): TPixiePixel;
    procedure DrawText(const Text: string; Handle: TPixieFontHandle;
      Color: TPixieWebColor; X, Y, W, H: Single); virtual; abstract;
    // Draws a single text run anchored to BaselineY (used by SVG text where
    // mixed-font runs on the same line must share a baseline). Default impl
    // forwards to DrawText with Y = BaselineY - Metrics.Ascent; backends may
    // override to pin the layout baseline more precisely (DWrite/D2D's default
    // line baseline includes lineGap which would offset mixed-font runs).
    procedure DrawTextAtBaseline(const Text: string;
      Handle: TPixieFontHandle; const Metrics: TPixieFontMetrics;
      Color: TPixieWebColor; X, BaselineY: Single); virtual;
    // Stroke text outline at baseline position. Default: no-op.
    procedure StrokeTextAtBaseline(const Text: string;
      Handle: TPixieFontHandle; const Metrics: TPixieFontMetrics;
      Color: TPixieWebColor; Width: Single; X, BaselineY: Single); virtual;

    // ---- Convenience methods (non-abstract, call through to abstract) ----

    // Rounded rect with uniform radius
    procedure FillRoundedRect(X, Y, W, H, Radius: Single;
      Color: TPixieWebColor); overload;

    // Text at a position (no clip rect)
    procedure DrawSimpleText(const Text: string; Handle: TPixieFontHandle;
      Color: TPixieWebColor; X, Y: Single);

    // Text aligned within a rectangle
    procedure TextRect(const Text: string; Handle: TPixieFontHandle;
      const Metrics: TPixieFontMetrics;
      Color: TPixieWebColor; X, Y, W, H: Single;
      HAlign: TPixieTextAlign = taCenter;
      VAlign: TPixieVerticalAlign = vaMiddle);

    // Unit conversion
    function PtToPx(Pt: Single): TPixiePixel; virtual; abstract;

    // Image
    function LoadImage(const Path: string): TPixieImageHandle; virtual; abstract;
    function LoadImageFromPixels(Width, Height: Integer;
      Pixels: Pointer; Pitch: Integer): TPixieImageHandle; virtual; abstract;
    procedure FreeImage(Handle: TPixieImageHandle); virtual; abstract;
    procedure GetImageSize(Handle: TPixieImageHandle;
      out W, H: Single); virtual; abstract;
    // Returns True when the image has no natural size (e.g. an SVG with
    // only a viewBox and no width/height). When True, AspectRatio is the
    // natural width/height ratio so callers can fit the image to a
    // container while preserving aspect.
    function GetImageAspectInfo(Handle: TPixieImageHandle;
      out AspectRatio: Single): Boolean; virtual;
    procedure DrawImage(Handle: TPixieImageHandle;
      DstX, DstY, DstW, DstH: Single); virtual; abstract;
    procedure FillTiledImage(Handle: TPixieImageHandle;
      TileX, TileY, TileW, TileH: Single;
      FillX, FillY, FillW, FillH: Single); virtual;
    function LoadImageFromStream(Stream: TStream): TPixieImageHandle; virtual;
    function LoadWebPFile(const Path: string): TPixieImageHandle; virtual;
    function LoadSvgFromData(Data: Pointer;
      Size: Integer): TPixieImageHandle; virtual;
    // Animated image decoding. Returns nil for static or unsupported
    // formats; the caller falls back to LoadImageFromStream. Default
    // impl handles GIF via the software decoder + LoadImageFromPixels.
    // Backends with native multi-frame APIs (WIC, ImageIO, QImageReader)
    // should override.
    function LoadAnimatedFromStream(
      Stream: TStream): TPixieAnimatedImage; virtual;

    // Off-screen tile rendering (pattern optimisation)
    function BeginTileRender(Width, Height: Integer): Boolean; virtual;
    function EndTileRender: TPixieImageHandle; virtual;
    procedure GetTransformScale(out ScaleX, ScaleY: Single); virtual;

    // ---- Off-screen rendering and image export ----
    // Bind the canvas to an off-screen pixel buffer of the given size,
    // cleared to ClearColor (use 0 alpha for transparent background).
    // After BeginOffscreen the caller draws as usual, then calls
    // SaveAsPng/SaveAsBmp and finally EndOffscreen to release resources.
    procedure BeginOffscreen(Width, Height: Integer;
      ClearColor: TPixieWebColor); virtual; abstract;
    procedure EndOffscreen; virtual; abstract;

    // Save the current off-screen surface as a PNG.
    // Must be called between BeginOffscreen and EndOffscreen.
    procedure SaveAsPng(Stream: TStream); overload; virtual; abstract;
    procedure SaveAsPng(const FileName: string); overload; virtual;

    // Save the current off-screen surface as a 32bpp BGRA BMP with
    // alpha preserved. Must be called between BeginOffscreen and
    // EndOffscreen.
    procedure SaveAsBmp(Stream: TStream); overload; virtual; abstract;
    procedure SaveAsBmp(const FileName: string); overload; virtual;

    // Shared 32bpp BGRA BMP writer (top-down pixels in, bottom-up BMP out).
    class procedure WriteBmpStream(Stream: TStream;
      PixelsBGRA: Pointer; Width, Height, Stride: Integer);

    // Shared PNG writer for 32bpp top-down BGRA pixels (FPC-only — Delphi
    // uses Vcl.Imaging.pngimage directly).
    {$IFDEF FPC}
    class procedure WritePngStream(Stream: TStream;
      PixelsBGRA: Pointer; Width, Height, Stride: Integer);
    {$ENDIF}

    // Simple shapes (for list markers and form controls)
    procedure FillEllipse(X, Y, W, H: Single;
      Color: TPixieWebColor); virtual; abstract;
    procedure DrawEllipse(X, Y, W, H: Single;
      Color: TPixieWebColor; StrokeWidth: Single); virtual; abstract;
    procedure DrawRect(X, Y, W, H: Single;
      Color: TPixieWebColor; StrokeWidth: Single); virtual; abstract;
    procedure DrawLine(X1, Y1, X2, Y2: Single;
      Color: TPixieWebColor; StrokeWidth: Single;
      Style: TPixieTextDecorationStyle = tdsSolid); virtual; abstract;
    procedure StrokePolyline(const Points: array of Single;
      Color: TPixieWebColor; StrokeWidth: Single); virtual; abstract;

    // Path construction — builds an implicit "current path"
    procedure BeginPath; virtual;
    procedure MoveTo(X, Y: Single); virtual;
    procedure LineTo(X, Y: Single); virtual;
    procedure CurveTo(X1, Y1, X2, Y2, X3, Y3: Single); virtual;
    procedure ClosePath; virtual;

    // Path rendering — renders current path, then clears it
    procedure FillPath(Color: TPixieWebColor;
      FillRule: TPixieFillRule = frNonZero); virtual;
    procedure StrokePath(Color: TPixieWebColor; Width: Single); virtual;
    procedure FillAndStrokePath(FillColor: TPixieWebColor;
      StrokeColor: TPixieWebColor; StrokeWidth: Single;
      FillRule: TPixieFillRule = frNonZero); virtual;

    // Discard current path without rendering
    procedure DiscardPath; virtual;

    // Clip to current path, then clear path
    procedure ClipPath(FillRule: TPixieFillRule = frNonZero); virtual;

    // Fill current path with gradient, then clear path
    procedure FillPathLinearGradient(
      const Gradient: TPixieLinearGradientLayer;
      FillRule: TPixieFillRule = frNonZero); virtual;
    procedure FillPathRadialGradient(
      const Gradient: TPixieRadialGradientLayer;
      FillRule: TPixieFillRule = frNonZero); virtual;

    // Stroke current path with gradient, then clear path
    procedure StrokePathLinearGradient(
      const Gradient: TPixieLinearGradientLayer; Width: Single); virtual;
    procedure StrokePathRadialGradient(
      const Gradient: TPixieRadialGradientLayer; Width: Single); virtual;

    // Affine transform — concatenates with current CTM
    // Parameters match SVG matrix(a,b,c,d,e,f) convention
    procedure ConcatMatrix(A, B, C, D, E, F: Single); virtual;
    // True when ConcatMatrix supports a relative draw-space concatenation as
    // used by CSS transforms. The PDF backend converts coordinates per
    // primitive (no base CTM flip), so it returns False and CSS-transformed
    // elements render untransformed there rather than mis-placed.
    function SupportsTransform: Boolean; virtual;

    // View size hint for render targets that need explicit sizing
    procedure SetViewSize(W, H: Integer; ACanvasScale: Single = 1); virtual;
    // Scale/zoom — applies a uniform scale transform to all drawing
    procedure SetScale(Scale: Single); virtual;
    property Scale: Single read FScale;
  end;

implementation

uses
  SysUtils, Math,
  {$IFDEF FPC}FPImage, FPWritePNG,{$ENDIF}
  Pixie.WebP, Pixie.GifDecode, Pixie.ApngDecode, Pixie.WebPAnim;

constructor TPixieCanvas.Create;
begin
  inherited Create;
  FScale := 1.0;
  FTextWidthCache := TPixieTextWidthCache.Create;
end;

destructor TPixieCanvas.Destroy;
begin
  ClearTextWidthCache;
  FTextWidthCache.Free;
  inherited Destroy;
end;

function TPixieCanvas.GetImageAspectInfo(Handle: TPixieImageHandle;
  out AspectRatio: Single): Boolean;
begin
  AspectRatio := 0;
  Result := False;
end;

procedure TPixieCanvas.ClearTextWidthCache;
var
  Pair: TPair<TPixieFontHandle, TPixieTextWidthMap>;
begin
  for Pair in FTextWidthCache do
    Pair.Value.Free;
  FTextWidthCache.Clear;
end;

procedure TPixieCanvas.DeleteFont(Handle: TPixieFontHandle);
var
  FontMap: TPixieTextWidthMap;
begin
  if FTextWidthCache.TryGetValue(Handle, FontMap) then
  begin
    FontMap.Free;
    FTextWidthCache.Remove(Handle);
  end;
  DoDeleteFont(Handle);
end;

function TPixieCanvas.MeasureText(const Text: string;
  Handle: TPixieFontHandle): TPixiePixel;
var
  FontMap: TPixieTextWidthMap;
begin
  if not FTextWidthCache.TryGetValue(Handle, FontMap) then
  begin
    FontMap := TPixieTextWidthMap.Create;
    FTextWidthCache.Add(Handle, FontMap);
  end;
  if not FontMap.TryGetValue(Text, Result) then
  begin
    Result := DoMeasureText(Text, Handle);
    FontMap.Add(Text, Result);
  end;
end;

// ---------------------------------------------------------------------------
// Convenience methods
// ---------------------------------------------------------------------------

procedure TPixieCanvas.FillRoundedRect(X, Y, W, H, Radius: Single;
  Color: TPixieWebColor);
var
  Rad: TPixieBorderRadiuses;
begin
  Rad.TopLeftX := Radius;     Rad.TopLeftY := Radius;
  Rad.TopRightX := Radius;    Rad.TopRightY := Radius;
  Rad.BottomRightX := Radius; Rad.BottomRightY := Radius;
  Rad.BottomLeftX := Radius;  Rad.BottomLeftY := Radius;
  FillRoundedRect(X, Y, W, H, Rad, Color);
end;

procedure TPixieCanvas.DrawSimpleText(const Text: string;
  Handle: TPixieFontHandle; Color: TPixieWebColor; X, Y: Single);
begin
  DrawText(Text, Handle, Color, X, Y, 1e6, 1e6);
end;

procedure TPixieCanvas.DrawTextAtBaseline(const Text: string;
  Handle: TPixieFontHandle; const Metrics: TPixieFontMetrics;
  Color: TPixieWebColor; X, BaselineY: Single);
begin
  DrawText(Text, Handle, Color, X, BaselineY - Metrics.Ascent,
    1e6, Metrics.Height);
end;

procedure TPixieCanvas.StrokeTextAtBaseline(const Text: string;
  Handle: TPixieFontHandle; const Metrics: TPixieFontMetrics;
  Color: TPixieWebColor; Width: Single; X, BaselineY: Single);
begin
  // No-op default — backends override with platform-specific text stroke
end;

procedure TPixieCanvas.TextRect(const Text: string;
  Handle: TPixieFontHandle; const Metrics: TPixieFontMetrics;
  Color: TPixieWebColor; X, Y, W, H: Single;
  HAlign: TPixieTextAlign; VAlign: TPixieVerticalAlign);
var
  TextW, TX, TY: Single;
begin
  TextW := MeasureText(Text, Handle);

  case HAlign of
    taCenter: TX := X + (W - TextW) * 0.5;
    taRight:  TX := X + W - TextW;
  else
    TX := X;
  end;

  case VAlign of
    vaMiddle: TY := Y + (H - Metrics.Height) * 0.5;
    vaBottom: TY := Y + H - Metrics.Height;
  else
    TY := Y;
  end;

  DrawText(Text, Handle, Color, TX, TY, X + W, Y + H);
end;

procedure TPixieCanvas.PushOpacity(AOpacity: Single);
begin
  // no-op by default
end;

procedure TPixieCanvas.PopOpacity;
begin
  // no-op by default
end;

procedure TPixieCanvas.PushMask(MaskHandle: TPixieImageHandle;
  MaskX, MaskY, MaskW, MaskH: Single);
begin
  // no-op by default
end;

procedure TPixieCanvas.PopMask;
begin
  // no-op by default
end;

function TPixieCanvas.SetBlendMode(Mode: TPixieBlendMode): Boolean;
begin
  Result := False;
end;

procedure TPixieCanvas.ResetBlendMode;
begin
  // no-op by default
end;

procedure TPixieCanvas.SetPathStrokeStyle(Cap: TPixieLineCap;
  Join: TPixieLineJoin);
begin
  FPathLineCap := Cap;
  FPathLineJoin := Join;
end;

procedure TPixieCanvas.SetPathDashStyle(const DashArray: array of Single;
  DashOffset: Single);
var
  I: Integer;
begin
  SetLength(FPathDashArray, Length(DashArray));
  for I := 0 to High(DashArray) do
    FPathDashArray[I] := DashArray[I];
  FPathDashOffset := DashOffset;
end;

procedure TPixieCanvas.ClearPathDashStyle;
begin
  SetLength(FPathDashArray, 0);
  FPathDashOffset := 0;
end;

procedure TPixieCanvas.SetViewSize(W, H: Integer; ACanvasScale: Single);
begin
  // no-op by default
end;

procedure TPixieCanvas.SetScale(Scale: Single);
begin
  FScale := Scale;
end;

function TPixieCanvas.LoadImageFromStream(
  Stream: TStream): TPixieImageHandle;
begin
  Result := 0;
end;

function TPixieCanvas.LoadWebPFile(
  const Path: string): TPixieImageHandle;
var
  Stream: TFileStream;
  Buf: Pointer;
  BufSize: Integer;
  Pixels: Pointer;
  W, H: Integer;
begin
  Result := 0;
  Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
  try
    BufSize := Stream.Size;
    if BufSize = 0 then Exit;
    GetMem(Buf, BufSize);
    try
      Stream.ReadBuffer(Buf^, BufSize);
      if PixieWebPDecode(Buf, BufSize, W, H, Pixels) then
      try
        Result := LoadImageFromPixels(W, H, Pixels, W * 4);
      finally
        PixieWebPFreePixels(Pixels);
      end;
    finally
      FreeMem(Buf);
    end;
  finally
    Stream.Free;
  end;
end;

function TPixieCanvas.InstallFontFromMemory(Data: Pointer; Size: Integer;
  out Handle: PtrUInt): Boolean;
begin
  Result := False;
  Handle := 0;
end;

procedure TPixieCanvas.UninstallFont(Handle: PtrUInt);
begin
end;

function TPixieCanvas.LoadSvgFromData(Data: Pointer;
  Size: Integer): TPixieImageHandle;
begin
  Result := 0;
end;

function TPixieCanvas.LoadAnimatedFromStream(
  Stream: TStream): TPixieAnimatedImage;
var
  Anim: TPixieRawAnimation;
  Decoded: Boolean;
  I, J: Integer;
  Handle: TPixieImageHandle;
begin
  Result := nil;
  if Stream = nil then Exit;

  Decoded := False;
  if PixieIsGifStream(Stream) then
    Decoded := PixieDecodeGif(Stream, Anim)
  else if PixieIsApngStream(Stream) then
    Decoded := PixieDecodeApng(Stream, Anim)
  else if PixieIsWebPAnimStream(Stream) then
    Decoded := PixieDecodeWebPAnim(Stream, Anim);

  if not Decoded then Exit;
  if Length(Anim.Frames) = 0 then Exit;

  Result := TPixieAnimatedImage.Create;
  Result.Width := Anim.Width;
  Result.Height := Anim.Height;
  Result.Loops := Anim.Loops;
  for I := 0 to High(Anim.Frames) do
  begin
    Handle := LoadImageFromPixels(Anim.Width, Anim.Height,
      @Anim.Frames[I].Pixels[0], Anim.Width * 4);
    SetLength(Anim.Frames[I].Pixels, 0);
    if Handle = 0 then
    begin
      for J := 0 to Result.FrameCount - 1 do
        FreeImage(Result.Frames[J].Handle);
      Result.ClearFrames;
      Result.Free;
      Result := nil;
      Exit;
    end;
    Result.AddFrame(Handle, Anim.Frames[I].DelayMs);
  end;
end;

procedure TPixieCanvas.FillTiledImage(Handle: TPixieImageHandle;
  TileX, TileY, TileW, TileH: Single;
  FillX, FillY, FillW, FillH: Single);
var
  Col, Row, StartCol, EndCol, StartRow, EndRow: Integer;
begin
  if (Handle = 0) or (TileW <= 0) or (TileH <= 0) then Exit;
  StartCol := Floor((FillX - TileX) / TileW);
  EndCol := Ceil((FillX + FillW - TileX) / TileW) - 1;
  StartRow := Floor((FillY - TileY) / TileH);
  EndRow := Ceil((FillY + FillH - TileY) / TileH) - 1;
  for Row := StartRow to EndRow do
    for Col := StartCol to EndCol do
      DrawImage(Handle,
        TileX + Col * TileW, TileY + Row * TileH, TileW, TileH);
end;

function TPixieCanvas.BeginTileRender(Width, Height: Integer): Boolean;
begin
  Result := False;
end;

function TPixieCanvas.EndTileRender: TPixieImageHandle;
begin
  Result := 0;
end;

procedure TPixieCanvas.GetTransformScale(out ScaleX, ScaleY: Single);
begin
  ScaleX := 1;
  ScaleY := 1;
end;

procedure TPixieCanvas.SaveAsPng(const FileName: string);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    SaveAsPng(Stream);
  finally
    Stream.Free;
  end;
end;

procedure TPixieCanvas.SaveAsBmp(const FileName: string);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    SaveAsBmp(Stream);
  finally
    Stream.Free;
  end;
end;

class procedure TPixieCanvas.WriteBmpStream(Stream: TStream;
  PixelsBGRA: Pointer; Width, Height, Stride: Integer);
const
  BMP_SIGNATURE = $4D42; // 'BM' little-endian
  BMP_BI_RGB    = 0;     // uncompressed
type
  TBmpFileHeader = packed record
    bfType: Word;
    bfSize: LongWord;
    bfReserved1: Word;
    bfReserved2: Word;
    bfOffBits: LongWord;
  end;
  TBmpInfoHeader = packed record
    biSize: LongWord;
    biWidth: LongInt;
    biHeight: LongInt;
    biPlanes: Word;
    biBitCount: Word;
    biCompression: LongWord;
    biSizeImage: LongWord;
    biXPelsPerMeter: LongInt;
    biYPelsPerMeter: LongInt;
    biClrUsed: LongWord;
    biClrImportant: LongWord;
  end;
var
  Fh: TBmpFileHeader;
  Ih: TBmpInfoHeader;
  PixelBytes: LongWord;
  Y: Integer;
  Src: PByte;
begin
  if (PixelsBGRA = nil) or (Width <= 0) or (Height <= 0) then Exit;
  PixelBytes := LongWord(Width) * LongWord(Height) * 4;
  FillChar(Fh, SizeOf(Fh), 0);
  Fh.bfType := BMP_SIGNATURE;
  Fh.bfSize := SizeOf(Fh) + SizeOf(Ih) + PixelBytes;
  Fh.bfOffBits := SizeOf(Fh) + SizeOf(Ih);
  FillChar(Ih, SizeOf(Ih), 0);
  Ih.biSize := SizeOf(Ih);
  Ih.biWidth := Width;
  Ih.biHeight := Height;
  Ih.biPlanes := 1;
  Ih.biBitCount := 32;
  Ih.biCompression := BMP_BI_RGB;
  Ih.biSizeImage := PixelBytes;
  Stream.WriteBuffer(Fh, SizeOf(Fh));
  Stream.WriteBuffer(Ih, SizeOf(Ih));
  for Y := Height - 1 downto 0 do
  begin
    Src := PByte(PixelsBGRA) + Y * Stride;
    Stream.WriteBuffer(Src^, Width * 4);
  end;
end;

{$IFDEF FPC}
class procedure TPixieCanvas.WritePngStream(Stream: TStream;
  PixelsBGRA: Pointer; Width, Height, Stride: Integer);
var
  Img: TFPMemoryImage;
  Writer: TFPWriterPNG;
  X, Y: Integer;
  Row: PByte;
  C: TFPColor;
begin
  if (PixelsBGRA = nil) or (Width <= 0) or (Height <= 0) then Exit;
  Img := TFPMemoryImage.Create(Width, Height);
  try
    Writer := TFPWriterPNG.Create;
    try
      Writer.UseAlpha := True;
      for Y := 0 to Height - 1 do
      begin
        Row := PByte(PixelsBGRA) + Y * Stride;
        for X := 0 to Width - 1 do
        begin
          C.Blue := Row[0] or (Row[0] shl 8);
          C.Green := Row[1] or (Row[1] shl 8);
          C.Red := Row[2] or (Row[2] shl 8);
          C.Alpha := Row[3] or (Row[3] shl 8);
          Img.Colors[X, Y] := C;
          Inc(Row, 4);
        end;
      end;
      Img.SaveToStream(Stream, Writer);
    finally
      Writer.Free;
    end;
  finally
    Img.Free;
  end;
end;
{$ENDIF}

procedure TPixieCanvas.BeginPath;
begin
end;

procedure TPixieCanvas.MoveTo(X, Y: Single);
begin
end;

procedure TPixieCanvas.LineTo(X, Y: Single);
begin
end;

procedure TPixieCanvas.CurveTo(X1, Y1, X2, Y2, X3, Y3: Single);
begin
end;

procedure TPixieCanvas.ClosePath;
begin
end;

procedure TPixieCanvas.FillPath(Color: TPixieWebColor;
  FillRule: TPixieFillRule);
begin
end;

procedure TPixieCanvas.StrokePath(Color: TPixieWebColor; Width: Single);
begin
end;

procedure TPixieCanvas.FillAndStrokePath(FillColor: TPixieWebColor;
  StrokeColor: TPixieWebColor; StrokeWidth: Single;
  FillRule: TPixieFillRule);
begin
end;

procedure TPixieCanvas.DiscardPath;
begin
  BeginPath;
end;

procedure TPixieCanvas.ClipPath(FillRule: TPixieFillRule);
begin
end;

procedure TPixieCanvas.FillPathLinearGradient(
  const Gradient: TPixieLinearGradientLayer;
  FillRule: TPixieFillRule);
var
  EmptyRadius: TPixieBorderRadiuses;
begin
  // Default: clip to path, fill bounding rect with gradient.
  // If the gradient has a brush transform (objectBoundingBox), apply it
  // as a canvas transform so the gradient direction is preserved.
  FillChar(EmptyRadius, SizeOf(EmptyRadius), 0);
  SaveState;
  ClipPath(FillRule);
  if Gradient.HasBrushTransform then
  begin
    ConcatMatrix(
      Gradient.BrushTransform.M11, Gradient.BrushTransform.M12,
      Gradient.BrushTransform.M21, Gradient.BrushTransform.M22,
      Gradient.BrushTransform.DX, Gradient.BrushTransform.DY);
    // Fill in normalised bbox space (shape maps to 0-1, padded for extend)
    FillLinearGradient(-1, -1, 3, 3, EmptyRadius, Gradient);
  end
  else
    FillLinearGradient(-1e6, -1e6, 2e6, 2e6, EmptyRadius, Gradient);
  RestoreState;
end;

procedure TPixieCanvas.FillPathRadialGradient(
  const Gradient: TPixieRadialGradientLayer;
  FillRule: TPixieFillRule);
var
  EmptyRadius: TPixieBorderRadiuses;
begin
  FillChar(EmptyRadius, SizeOf(EmptyRadius), 0);
  SaveState;
  ClipPath(FillRule);
  if Gradient.HasBrushTransform then
  begin
    ConcatMatrix(
      Gradient.BrushTransform.M11, Gradient.BrushTransform.M12,
      Gradient.BrushTransform.M21, Gradient.BrushTransform.M22,
      Gradient.BrushTransform.DX, Gradient.BrushTransform.DY);
    FillRadialGradient(-1, -1, 3, 3, EmptyRadius, Gradient);
  end
  else
    FillRadialGradient(-1e6, -1e6, 2e6, 2e6, EmptyRadius, Gradient);
  RestoreState;
end;

procedure TPixieCanvas.StrokePathLinearGradient(
  const Gradient: TPixieLinearGradientLayer; Width: Single);
begin
  // Default: discard path. Backends with native gradient stroke override this.
  DiscardPath;
end;

procedure TPixieCanvas.StrokePathRadialGradient(
  const Gradient: TPixieRadialGradientLayer; Width: Single);
begin
  DiscardPath;
end;

procedure TPixieCanvas.ConcatMatrix(A, B, C, D, E, F: Single);
begin
end;

function TPixieCanvas.SupportsTransform: Boolean;
begin
  Result := True;
end;

end.
