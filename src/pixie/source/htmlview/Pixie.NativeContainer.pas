unit Pixie.NativeContainer;

// Concrete TPixieContainer implementation that delegates all drawing
// to a TPixieCanvas instance. This contains all HTML-specific rendering
// logic (background layers, borders, list markers, etc.) written once
// and shared across all platforms.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Math, Generics.Collections,
  {$IFDEF FPC}LCLType, FPImage,{$ELSE}{$IFDEF MSWINDOWS}Windows,{$ENDIF}{$ENDIF}
  Pixie.Types, Pixie.WebColor, Pixie.Borders,
  Pixie.GradientLayer, Pixie.Background,
  Pixie.FontDescription, Pixie.CssLength,
  Pixie.AnimatedImage,
  Pixie.Container, Pixie.Canvas, Pixie.FontFace;

type
  TPixieAnchorClickEvent = procedure(Sender: TObject;
    El: TObject; const Url: string) of object;
  TPixieElementClickEvent = function(Sender: TObject;
    El: TObject): Boolean of object;
  TPixieFetchUrlEvent = procedure(Sender: TObject;
    const Url: string; Stream: TStream; var Success: Boolean) of object;

  TPixieImageCacheMap = TDictionary<string, TPixieImageHandle>;

  TPixiePendingImage = record
    Data: TMemoryStream;
  end;
  TPixiePendingImageMap = TDictionary<string, TPixiePendingImage>;
  TPixieCssCacheEntry = record
    Text: string;
    BaseUrl: string;
  end;
  TPixieCssCache = TDictionary<string, TPixieCssCacheEntry>;

  { TPixieNativeContainer }

  TPixieNativeContainer = class(TPixieContainer)
  private
    FCanvas: TPixieCanvas;
    FImages: TPixieImageCacheMap;
    FAnimations: TPixieAnimatedImageMap;
    FPendingImages: TPixiePendingImageMap;
    FCssCache: TPixieCssCache;
    FBaseUrl: string;
    FDefaultFontSize: TPixiePixel;
    FDefaultFontName: string;
    FViewportWidth: TPixiePixel;
    FViewportHeight: TPixiePixel;
    FOnAnchorClick: TPixieAnchorClickEvent;
    FOnElementClick: TPixieElementClickEvent;
    FOnFetchUrl: TPixieFetchUrlEvent;
    FOnAnimatedImageDiscovered: TPixieAnimatedImageDiscoveredEvent;
    FOnAcquireAnimationCursor: TPixieAnimCursorAcquireEvent;
    FOnReleaseAnimationCursor: TPixieAnimCursorReleaseEvent;
    FOnSetCaption: TNotifyEvent;
    FCaption: string;
    FCursor: string;
    FCaretVisible: Boolean;
    FMediaType: TPixieMediaType;
    FColorScheme: TPixieColorScheme;

    function ResolveUrl(const Src, ABaseUrl: string): string;
    function CacheKey(const Src, ABaseUrl: string): string;
    function TryGetCachedHandle(const Key: string;
      out Handle: TPixieImageHandle): Boolean;
    function GetCachedImage(const Src, ABaseUrl: string): TPixieImageHandle;
    function DecodeStreamToHandle(Stream: TStream;
      const AKey: string = ''): TPixieImageHandle;
    // Decodes Stream as a multi-frame animated image and stores it in
    // FAnimations[AKey]. Returns True only on multi-frame success (Handle
    // is the first-frame handle); the static fallback path is unchanged
    // and runs only when this returns False.
    function TryDecodeAnimated(Stream: TStream; const AKey: string;
      out Handle: TPixieImageHandle): Boolean;
    procedure FreeAnimation(AnimImg: TPixieAnimatedImage);
    function LoadFromResource(const ResName: string): TPixieImageHandle;
    function ResolvePendingImage(const Key: string): TPixieImageHandle;
    procedure FetchAndInstallFontFace(Entry: TPixieFontFaceEntry);
  public
    constructor Create(ACanvas: TPixieCanvas);
    destructor Destroy; override;

    procedure RegisterImage(const Name: string; Stream: TStream);
    procedure UnregisterImage(const Name: string);
    procedure ClearCssCache;

    // Animated image lookup for elements that want a playback cursor.
    function GetAnimatedImage(const Src,
      ABaseUrl: string): TPixieAnimatedImage; override;

    // Cursor lifecycle bridge — the view core registers acquire/release
    // callbacks; elements call these to bind/unbind playback state.
    function AcquireAnimationCursor(Element: TObject;
      AnimImg: TPixieAnimatedImage): TPixieAnimationCursor; override;
    procedure ReleaseAnimationCursor(
      Cursor: TPixieAnimationCursor); override;

    property Canvas: TPixieCanvas read FCanvas;
    property Caption: string read FCaption;
    property Cursor: string read FCursor;
    property DefaultFontSize: TPixiePixel read FDefaultFontSize write FDefaultFontSize;
    property DefaultFontName: string read FDefaultFontName write FDefaultFontName;
    property ViewportWidth: TPixiePixel read FViewportWidth write FViewportWidth;
    property ViewportHeight: TPixiePixel read FViewportHeight write FViewportHeight;
    property OnAnchorClickEvent: TPixieAnchorClickEvent
      read FOnAnchorClick write FOnAnchorClick;
    property OnElementClickEvent: TPixieElementClickEvent
      read FOnElementClick write FOnElementClick;
    property OnFetchUrlEvent: TPixieFetchUrlEvent
      read FOnFetchUrl write FOnFetchUrl;
    property OnAnimatedImageDiscoveredEvent:
      TPixieAnimatedImageDiscoveredEvent
      read FOnAnimatedImageDiscovered write FOnAnimatedImageDiscovered;
    property OnAcquireAnimationCursorEvent: TPixieAnimCursorAcquireEvent
      read FOnAcquireAnimationCursor write FOnAcquireAnimationCursor;
    property OnReleaseAnimationCursorEvent: TPixieAnimCursorReleaseEvent
      read FOnReleaseAnimationCursor write FOnReleaseAnimationCursor;
    property OnSetCaptionEvent: TNotifyEvent
      read FOnSetCaption write FOnSetCaption;
    property BaseUrl: string read FBaseUrl write FBaseUrl;
    property MediaType: TPixieMediaType read FMediaType write FMediaType;
    property ColorScheme: TPixieColorScheme read FColorScheme write FColorScheme;
    property CaretVisible: Boolean read FCaretVisible write FCaretVisible;

    // ---- TPixieContainer overrides ----

    // Font management
    function CreateFont(const Descr: TPixieFontDescription; Doc: TObject;
      out Metrics: TPixieFontMetrics): PtrUInt; override;
    procedure DeleteFont(HFont: PtrUInt); override;
    procedure UninstallFont(Handle: PtrUInt); override;
    function TextWidth(const Text: string; HFont: PtrUInt): TPixiePixel; override;
    procedure DrawText(Hdc: PtrUInt; const Text: string; HFont: PtrUInt;
      Color: TPixieWebColor; const Pos: TPixiePosition); override;
    function PtToPx(Pt: Single): TPixiePixel; override;
    function GetDefaultFontSize: TPixiePixel; override;
    function GetDefaultFontName: string; override;

    // Drawing
    procedure DrawListMarker(Hdc: PtrUInt;
      const Marker: TPixieListMarker); override;
    procedure LoadImage(const Src, ABaseUrl: string;
      RedrawOnReady: Boolean); override;
    procedure GetImageInfo(const Src, ABaseUrl: string;
      out Sz: TPixieSize; out AspectOnly: Boolean;
      out AspectRatio: Single); override;
    procedure GetImageSize(const Src, ABaseUrl: string;
      out Sz: TPixieSize); override;
    procedure DrawImage(Hdc: PtrUInt; const Layer: TPixieBackgroundLayer;
      const Url, ABaseUrl: string;
      FrameOverride: TPixieImageHandle = 0); override;
    procedure DrawSolidFill(Hdc: PtrUInt; const Layer: TPixieBackgroundLayer;
      Color: TPixieWebColor); override;
    procedure DrawLinearGradient(Hdc: PtrUInt;
      const Layer: TPixieBackgroundLayer;
      const Gradient: TPixieLinearGradientLayer); override;
    procedure DrawRadialGradient(Hdc: PtrUInt;
      const Layer: TPixieBackgroundLayer;
      const Gradient: TPixieRadialGradientLayer); override;
    procedure DrawConicGradient(Hdc: PtrUInt;
      const Layer: TPixieBackgroundLayer;
      const Gradient: TPixieConicGradientLayer); override;
    procedure DrawBorders(Hdc: PtrUInt; const Borders: TPixieBorders;
      const DrawPos: TPixiePosition; IsRoot: Boolean); override;

    // Document events
    procedure SetCaption(const ACaption: string); override;
    procedure SetBaseUrl(const ABaseUrl: string); override;
    procedure Link(Doc: TObject; El: TObject); override;
    procedure OnAnchorClick(const Url: string; El: TObject); override;
    function OnElementClick(El: TObject): Boolean; override;
    procedure OnMouseEvent(El: TObject; Event: TPixieMouseEvent); override;
    procedure SetCursor(const ACursor: string); override;

    // Text & CSS
    procedure TransformText(var Text: string;
      Tt: TPixieTextTransform); override;
    procedure ImportCss(var Text: string; const Url: string;
      var ABaseUrl: string); override;

    // Selection highlight
    procedure DrawHighlight(Hdc: PtrUInt; const Pos: TPixiePosition;
      Color: TPixieWebColor); override;

    // Decoration line
    procedure DrawLine(Hdc: PtrUInt; X1, Y1, X2, Y2: TPixiePixel;
      Color: TPixieWebColor; StrokeWidth: Single;
      Style: TPixieTextDecorationStyle = tdsSolid); override;

    // Opacity layers
    procedure PushOpacity(AOpacity: Single); override;
    procedure PopOpacity; override;

    // Clipping
    procedure SetClip(const Pos: TPixiePosition;
      const BdrRadius: TPixieBorderRadiuses); override;
    procedure DelClip; override;

    // Graphics state stack + affine transform
    procedure SaveState; override;
    procedure RestoreState; override;
    procedure ConcatMatrix(A, B, C, D, E, F: Single); override;
    function SupportsTransform: Boolean; override;

    // Viewport & media
    procedure GetViewport(out Viewport: TPixiePosition); override;
    procedure GetMediaFeatures(out Media: TPixieMediaFeatures); override;
    procedure GetLanguage(out Language, Culture: string); override;

    // Element creation
    function CreateElement(const TagName: string; Attrs: TPixieStringMap;
      Doc: TObject): TObject; override;
  end;

implementation

uses
  {$IFDEF FPC}FPReadPNG, FPReadJPEG, FPReadBMP, FPReadGIF, Pixie.ImageUtils,
  Graphics,{$ELSE}{$IFDEF FRAMEWORK_VCL}Vcl.Graphics,{$ENDIF}{$ENDIF}
  Pixie.WebP, Pixie.Document, Pixie.GifDecode, Pixie.ApngDecode, Pixie.WebPAnim,
  Pixie.DataUri, Pixie.Utf8, Pixie.Url;

// Best-effort OS dark-mode probe backing 'prefers-color-scheme' when the
// application leaves ColorScheme at pcsAuto. Mirrors the luminance test
// shared across SoftPerfect apps: read the system window background colour
// and treat it as dark when its WCAG relative luminance drops below the
// midpoint. Works on every LCL widgetset and on VCL; FMX exposes no
// equivalent system colour, so it reports light there.
function PixieSystemPrefersDark: Boolean;
{$IF Defined(FPC) or Defined(FRAMEWORK_VCL)}
var
  WindowColor: LongInt;
  R, G, B: Byte;
  Luminance: Double;
{$ENDIF}
begin
  {$IF Defined(FPC) or Defined(FRAMEWORK_VCL)}
  WindowColor := ColorToRGB(clWindow);
  R := Byte(WindowColor);
  G := Byte(WindowColor shr 8);
  B := Byte(WindowColor shr 16);
  Luminance := (0.2126 * R + 0.7152 * G + 0.0722 * B) / 255.0;
  Result := Luminance < 0.5;
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

type
  TPixieStreamImageType = (sitUnknown, sitPng, sitJpeg, sitBmp, sitGif, sitSvg,
    sitWebP);

function DetectImageType(Stream: TStream): TPixieStreamImageType; forward;

function IsHttpUrl(const Url: string): Boolean;
begin
  Result := (Length(Url) > 7) and
    ((StrLComp(PChar(Url), 'http://', 7) = 0) or
     (StrLComp(PChar(Url), 'https://', 8) = 0));
end;

// True when the URL carries a real scheme that OnFetchUrl should handle.
// A single-letter scheme is a Windows drive (C:\...) and data: is
// self-contained, so neither is treated as fetchable.
function HasFetchableScheme(const Url: string): Boolean;
var
  Parsed: TPixieUrl;
begin
  Parsed := TPixieUrl.Create(Url);
  Result := Parsed.HasScheme and (Length(Parsed.Scheme) > 1) and
    (not SameText(Parsed.Scheme, 'data'));
end;

function PercentDecode(const S: string): string;
var
  I, Len, Ch: Integer;
{$IFNDEF FPC}
  Bytes: TBytes;
  ByteCount: Integer;
{$ENDIF}
begin
{$IFDEF FPC}
  // FPC: string is UTF-8 AnsiString, Chr() produces raw bytes — decode in place
  Result := '';
  I := 1;
  Len := Length(S);
  while I <= Len do
  begin
    if (S[I] = '%') and (I + 2 <= Len) then
    begin
      Ch := StrToIntDef('$' + Copy(S, I + 1, 2), -1);
      if Ch >= 0 then
      begin
        Result := Result + Chr(Ch);
        Inc(I, 3);
        Continue;
      end;
    end;
    Result := Result + S[I];
    Inc(I);
  end;
{$ELSE}
  // Delphi: string is UTF-16; collect decoded bytes then convert from UTF-8
  Len := Length(S);
  SetLength(Bytes, Len);
  ByteCount := 0;
  I := 1;
  while I <= Len do
  begin
    if (S[I] = '%') and (I + 2 <= Len) then
    begin
      Ch := StrToIntDef('$' + Copy(S, I + 1, 2), -1);
      if Ch >= 0 then
      begin
        Bytes[ByteCount] := Byte(Ch);
        Inc(ByteCount);
        Inc(I, 3);
        Continue;
      end;
    end;
    // Non-encoded ASCII character: flush as a byte
    Bytes[ByteCount] := Byte(Ord(S[I]));
    Inc(ByteCount);
    Inc(I);
  end;
  Result := TEncoding.UTF8.GetString(Bytes, 0, ByteCount);
{$ENDIF}
end;

function TPixieNativeContainer.ResolveUrl(
  const Src, ABaseUrl: string): string;
var
  Base: string;
begin
  // Already a full URL — return as-is
  if Pos('://', Src) > 0 then
  begin
    Result := Src;
    Exit;
  end;

  // Determine effective base
  if ABaseUrl <> '' then
    Base := ABaseUrl
  else
    Base := FBaseUrl;

  // HTTP base — use RFC 3986 URL resolution for all references
  // (root-relative /path, protocol-relative //host, and relative paths)
  if IsHttpUrl(Base) then
  begin
    Result := PixieResolveUrl(TPixieUrl.Create(Base),
      TPixieUrl.Create(Src)).Str;
    Exit;
  end;

  // Protocol-relative URL: assume https for local-file bases. Without this,
  // "//host/..." falls through to LoadFromFile which Windows treats as UNC
  // "\\host\..." and stalls ~10 s on SMB connection per missing resource.
  if (Length(Src) >= 2) and (Src[1] = '/') and (Src[2] = '/') then
  begin
    Result := 'https:' + Src;
    Exit;
  end;

  // Local filesystem: absolute path — return as-is
  if (Length(Src) > 0) and
     ((Src[1] = '/') or (Src[1] = '\') or
      ((Length(Src) > 1) and (Src[2] = ':'))) then
  begin
    Result := PercentDecode(Src);
    Exit;
  end;

  if Base = '' then
    Result := PercentDecode(Src)
  else
    Result := IncludeTrailingPathDelimiter(Base) + PercentDecode(Src);
end;

function TPixieNativeContainer.CacheKey(const Src,
  ABaseUrl: string): string;
begin
  if (Length(Src) > 1) and ((Src[1] = '#') or (Src[1] = '@')) then
    Exit(Src);
  if (Length(Src) > 5) and (Copy(Src, 1, 5) = 'data:') then
    Exit(Src);
  Result := ResolveUrl(Src, ABaseUrl);
end;

function TPixieNativeContainer.TryGetCachedHandle(const Key: string;
  out Handle: TPixieImageHandle): Boolean;
var
  AnimImg: TPixieAnimatedImage;
begin
  if FAnimations.TryGetValue(Key, AnimImg) and (AnimImg.FrameCount > 0) then
  begin
    Handle := AnimImg.Frames[0].Handle;
    Exit(True);
  end;
  Result := FImages.TryGetValue(Key, Handle);
end;

function TPixieNativeContainer.GetCachedImage(
  const Src, ABaseUrl: string): TPixieImageHandle;
var
  Key: string;
  FetchStream: TMemoryStream;
  DataStream: TMemoryStream;
  FileStream: TFileStream;
  Success: Boolean;
begin
  Key := CacheKey(Src, ABaseUrl);
  if TryGetCachedHandle(Key, Result) then Exit;
  Result := 0;

  if (Length(Src) > 1) and (Src[1] = '#') then
    Result := ResolvePendingImage(Src)
  else if (Length(Src) > 1) and (Src[1] = '@') then
    Result := LoadFromResource(Copy(Src, 2, MaxInt))
  else if (Length(Src) > 5) and (Copy(Src, 1, 5) = 'data:') then
  begin
    if DecodeDataUri(Src, DataStream) then
    try
      Result := DecodeStreamToHandle(DataStream, Key);
    finally
      DataStream.Free;
    end;
  end
  else if HasFetchableScheme(Key) then
  begin
    if Assigned(FOnFetchUrl) then
    begin
      FetchStream := TMemoryStream.Create;
      try
        Success := False;
        FOnFetchUrl(Self, Key, FetchStream, Success);
        if Success and (FetchStream.Size > 0) then
        begin
          FetchStream.Position := 0;
          Result := DecodeStreamToHandle(FetchStream, Key);
        end;
      finally
        FetchStream.Free;
      end;
    end;
  end
  else
  begin
    // Local file. Peek the header so animated formats and WebP avoid a
    // second open via the canvas's path-based LoadImage (which still
    // handles SVG + native WIC/Cairo/CG/Qt decoders).
    try
      FileStream := TFileStream.Create(Key, fmOpenRead or fmShareDenyNone);
      try
        if PixieIsGifStream(FileStream) or PixieIsApngStream(FileStream)
          or PixieIsWebPAnimStream(FileStream) then
          TryDecodeAnimated(FileStream, Key, Result)
        else if DetectImageType(FileStream) = sitWebP then
          // Static WebP: decode through Pixie's own native (alpha-preserving)
          // decoder, not the platform path-based LoadImage whose LCL
          // TPicture/TBitmap.Canvas.Draw round-trip flattens transparency to
          // black on the gtk2 and Qt widgetsets (issue #282).
          Result := DecodeStreamToHandle(FileStream, Key);
      finally
        FileStream.Free;
      end;
    except
      Result := 0;
    end;
    if Result = 0 then
      Result := FCanvas.LoadImage(Key);
  end;

  if (Result <> 0) and not FAnimations.ContainsKey(Key) then
    FImages.Add(Key, Result);
end;

// ---------------------------------------------------------------------------
// Image format detection and stream decoding
// ---------------------------------------------------------------------------

function DetectImageType(Stream: TStream): TPixieStreamImageType;
var
  Header: array[0..11] of Byte;
  SavePos: Int64;
  BytesRead: Integer;
begin
  Result := sitUnknown;
  SavePos := Stream.Position;
  try
    FillChar(Header, SizeOf(Header), 0);
    BytesRead := Stream.Read(Header, SizeOf(Header));
    if BytesRead < 4 then Exit;

    // PNG: 89 50 4E 47
    if (Header[0] = $89) and (Header[1] = $50) and
       (Header[2] = $4E) and (Header[3] = $47) then
    begin
      Result := sitPng;
      Exit;
    end;

    // JPEG: FF D8 FF
    if (Header[0] = $FF) and (Header[1] = $D8) and
       (Header[2] = $FF) then
    begin
      Result := sitJpeg;
      Exit;
    end;

    // BMP: 42 4D
    if (Header[0] = $42) and (Header[1] = $4D) then
    begin
      Result := sitBmp;
      Exit;
    end;

    // GIF: 47 49 46 38
    if (Header[0] = $47) and (Header[1] = $49) and
       (Header[2] = $46) and (Header[3] = $38) then
    begin
      Result := sitGif;
      Exit;
    end;

    // SVG: look for '<svg' or '<?xml' in text content
    if (Header[0] = Ord('<')) then
    begin
      if (Header[1] = Ord('s')) and (Header[2] = Ord('v')) and
         (Header[3] = Ord('g')) then
      begin
        Result := sitSvg;
        Exit;
      end;
      if (Header[1] = Ord('?')) and (Header[2] = Ord('x')) and
         (Header[3] = Ord('m')) then
      begin
        Result := sitSvg;
        Exit;
      end;
    end;

    // SVG with UTF-8 BOM: EF BB BF 3C
    if (Header[0] = $EF) and (Header[1] = $BB) and
       (Header[2] = $BF) and (Header[3] = Ord('<')) then
    begin
      Result := sitSvg;
      Exit;
    end;

    // WebP: RIFF xxxx WEBP (bytes 0-3 = 'RIFF', bytes 8-11 = 'WEBP')
    if (BytesRead >= 12) and
       (Header[0] = Ord('R')) and (Header[1] = Ord('I')) and
       (Header[2] = Ord('F')) and (Header[3] = Ord('F')) and
       (Header[8] = Ord('W')) and (Header[9] = Ord('E')) and
       (Header[10] = Ord('B')) and (Header[11] = Ord('P')) then
    begin
      Result := sitWebP;
      Exit;
    end;
  finally
    Stream.Position := SavePos;
  end;
end;

function TPixieNativeContainer.DecodeStreamToHandle(
  Stream: TStream; const AKey: string): TPixieImageHandle;
var
  SvgBuf: TMemoryStream;
  WebPBuf: TMemoryStream;
  WebPPixels: Pointer;
  WebPW, WebPH: Integer;
{$IFDEF FPC}
  Img: TFPMemoryImage;
  Pixels: PByte;
  Pitch, W, H: Integer;
{$ENDIF}
begin
  Result := 0;
  if (FCanvas = nil) or (Stream = nil) or (Stream.Size = 0) then Exit;

  // SVG — route to canvas for native rendering (librsvg on Linux, D2D on Windows)
  if DetectImageType(Stream) = sitSvg then
  begin
    if Stream is TCustomMemoryStream then
      Result := FCanvas.LoadSvgFromData(
        TCustomMemoryStream(Stream).Memory,
        Stream.Size)
    else
    begin
      SvgBuf := TMemoryStream.Create;
      try
        SvgBuf.CopyFrom(Stream, 0);
        Result := FCanvas.LoadSvgFromData(SvgBuf.Memory, SvgBuf.Size);
      finally
        SvgBuf.Free;
      end;
    end;
    Exit;
  end;

  // Multi-frame GIFs/APNGs land in FAnimations; single-frame ones come
  // back as a plain static handle. Either way, skip the WIC/Cairo path
  // if we got a handle. Non-animated streams skip the peek and fall
  // through.
  if PixieIsGifStream(Stream) or PixieIsApngStream(Stream)
    or PixieIsWebPAnimStream(Stream) then
  begin
    TryDecodeAnimated(Stream, AKey, Result);
    if Result <> 0 then Exit;
  end;

  // Try canvas-native stream loading (D2D/WIC, FMX)
  Stream.Position := 0;
  Result := FCanvas.LoadImageFromStream(Stream);
  if Result <> 0 then Exit;

  // WebP — decode via libwebp
  if DetectImageType(Stream) = sitWebP then
  begin
    WebPBuf := TMemoryStream.Create;
    try
      Stream.Position := 0;
      WebPBuf.CopyFrom(Stream, 0);
      if WebPBuf.Size > 0 then
      begin
        if PixieWebPDecode(WebPBuf.Memory, WebPBuf.Size,
          WebPW, WebPH, WebPPixels) then
        try
          Result := FCanvas.LoadImageFromPixels(
            WebPW, WebPH, WebPPixels, WebPW * 4);
        finally
          PixieWebPFreePixels(WebPPixels);
        end;
      end;
    finally
      WebPBuf.Free;
    end;
    if Result <> 0 then Exit;
  end;

{$IFDEF FPC}
  // FPC: load via FPImage readers directly — bypasses platform bitmap handles
  // and preserves alpha (GTK2's TBitmap.Canvas.Draw composites against
  // black, destroying transparency)
  Img := TFPMemoryImage.Create(0, 0);
  try
    try
      Stream.Position := 0;
      Img.LoadFromStream(Stream);
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
{$ENDIF}
end;

function TPixieNativeContainer.TryDecodeAnimated(Stream: TStream;
  const AKey: string; out Handle: TPixieImageHandle): Boolean;
var
  AnimImg: TPixieAnimatedImage;
  StartPos: Int64;
  I: Integer;
begin
  Result := False;
  Handle := 0;
  if (FCanvas = nil) or (Stream = nil) then Exit;

  StartPos := Stream.Position;
  AnimImg := FCanvas.LoadAnimatedFromStream(Stream);
  if AnimImg = nil then
  begin
    Stream.Position := StartPos;
    Exit;
  end;

  if (AnimImg.FrameCount > 1) and (AKey <> '') then
  begin
    FAnimations.Add(AKey, AnimImg);
    Handle := AnimImg.Frames[0].Handle;
    if Assigned(FOnAnimatedImageDiscovered) then
      FOnAnimatedImageDiscovered(Self, AKey, AnimImg);
    Exit(True);
  end;

  // Degenerate cases: no key, or single-frame GIF. Keep frame 0 as a
  // plain static handle, release any surplus, dispose the wrapper.
  if AnimImg.FrameCount > 0 then
    Handle := AnimImg.Frames[0].Handle;
  for I := 1 to AnimImg.FrameCount - 1 do
    FCanvas.FreeImage(AnimImg.Frames[I].Handle);
  AnimImg.ClearFrames;
  AnimImg.Free;
end;

procedure TPixieNativeContainer.FreeAnimation(
  AnimImg: TPixieAnimatedImage);
var
  I: Integer;
begin
  if AnimImg = nil then Exit;
  for I := 0 to AnimImg.FrameCount - 1 do
    FCanvas.FreeImage(AnimImg.Frames[I].Handle);
  AnimImg.ClearFrames;
end;

function TPixieNativeContainer.GetAnimatedImage(const Src,
  ABaseUrl: string): TPixieAnimatedImage;
begin
  Result := nil;
  FAnimations.TryGetValue(CacheKey(Src, ABaseUrl), Result);
end;

function TPixieNativeContainer.AcquireAnimationCursor(Element: TObject;
  AnimImg: TPixieAnimatedImage): TPixieAnimationCursor;
begin
  Result := nil;
  if (AnimImg = nil) or not Assigned(FOnAcquireAnimationCursor) then Exit;
  Result := FOnAcquireAnimationCursor(Self, Element, AnimImg);
end;

procedure TPixieNativeContainer.ReleaseAnimationCursor(
  Cursor: TPixieAnimationCursor);
begin
  if (Cursor = nil) or not Assigned(FOnReleaseAnimationCursor) then Exit;
  FOnReleaseAnimationCursor(Self, Cursor);
end;

function TPixieNativeContainer.LoadFromResource(
  const ResName: string): TPixieImageHandle;
{$IF DEFINED(FPC) OR DEFINED(MSWINDOWS)}
var
  Stream: TResourceStream;
begin
  try
    Stream := TResourceStream.Create(HInstance, ResName, RT_RCDATA);
    try
      Result := DecodeStreamToHandle(Stream);
    finally
      Stream.Free;
    end;
  except
    Result := 0;
  end;
end;
{$ELSE}
begin
  Result := 0;
end;
{$ENDIF}

function TPixieNativeContainer.ResolvePendingImage(
  const Key: string): TPixieImageHandle;
var
  Pending: TPixiePendingImage;
begin
  Result := 0;
  if FPendingImages.TryGetValue(Key, Pending) then
  begin
    Pending.Data.Position := 0;
    Result := DecodeStreamToHandle(Pending.Data, Key);
    Pending.Data.Free;
    FPendingImages.Remove(Key);
  end;
end;

procedure TPixieNativeContainer.RegisterImage(const Name: string;
  Stream: TStream);
var
  Key: string;
  Pending: TPixiePendingImage;
begin
  Key := '#' + Name;

  // If already cached, free old handle first
  UnregisterImage(Name);

  // Copy stream data for deferred decoding
  Pending.Data := TMemoryStream.Create;
  Pending.Data.CopyFrom(Stream, 0);
  Pending.Data.Position := 0;
  FPendingImages.Add(Key, Pending);
end;

procedure TPixieNativeContainer.UnregisterImage(const Name: string);
var
  Key: string;
  Handle: TPixieImageHandle;
  AnimImg: TPixieAnimatedImage;
  Pending: TPixiePendingImage;
begin
  Key := '#' + Name;

  if FAnimations.TryGetValue(Key, AnimImg) then
  begin
    FreeAnimation(AnimImg);
    FAnimations.Remove(Key); // owns values — wrapper freed here
  end;

  if FImages.TryGetValue(Key, Handle) then
  begin
    FCanvas.FreeImage(Handle);
    FImages.Remove(Key);
  end;

  if FPendingImages.TryGetValue(Key, Pending) then
  begin
    Pending.Data.Free;
    FPendingImages.Remove(Key);
  end;
end;

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

constructor TPixieNativeContainer.Create(ACanvas: TPixieCanvas);
begin
  inherited Create;
  FCanvas := ACanvas;
  FImages := TPixieImageCacheMap.Create;
  FAnimations := TPixieAnimatedImageMap.Create([doOwnsValues]);
  FPendingImages := TPixiePendingImageMap.Create;
  FCssCache := TPixieCssCache.Create;
  FDefaultFontSize := 16;
  FDefaultFontName := 'serif';
  FViewportWidth := 1024;
  FViewportHeight := 768;
  FMediaType := mtScreen;
  FColorScheme := pcsAuto;
end;

destructor TPixieNativeContainer.Destroy;
var
  Pair: TPair<string, TPixieImageHandle>;
  AnimPair: TPair<string, TPixieAnimatedImage>;
  PendingPair: TPair<string, TPixiePendingImage>;
begin
  for AnimPair in FAnimations do
    FreeAnimation(AnimPair.Value);
  FAnimations.Free; // doOwnsValues frees the wrapper objects
  for Pair in FImages do
    FCanvas.FreeImage(Pair.Value);
  FImages.Free;
  for PendingPair in FPendingImages do
    PendingPair.Value.Data.Free;
  FPendingImages.Free;
  FCssCache.Free;
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Font management
// ---------------------------------------------------------------------------

function TPixieNativeContainer.CreateFont(
  const Descr: TPixieFontDescription; Doc: TObject;
  out Metrics: TPixieFontMetrics): PtrUInt;
var
  Resolved: TPixieFontDescription;
  Registry: TPixieFontFaceRegistry;
  I, J, Start, Len: Integer;
  Part: string;
  Entry: TPixieFontFaceEntry;
begin
  Resolved := Descr;
  if (Doc is TPixieDocument) then
  begin
    Registry := TPixieDocument(Doc).FontFaceRegistry;
    if Registry.Entries.Count > 0 then
    begin
      // Split family list, load matching @font-face fonts, substitute names
      Len := Length(Descr.Family);
      Start := 1;
      for I := 1 to Len + 1 do
      begin
        if (I > Len) or (Descr.Family[I] = ',') then
        begin
          Part := Trim(Copy(Descr.Family, Start, I - Start));
          if (Length(Part) >= 2) and
             ((Part[1] = '''') or (Part[1] = '"')) then
            Part := Copy(Part, 2, Length(Part) - 2);
          Start := I + 1;
          if Part = '' then Continue;
          for J := 0 to Registry.Entries.Count - 1 do
          begin
            Entry := Registry.Entries[J];
            if not SameText(Entry.Family, Part) then Continue;
            if not Entry.Loaded and not Entry.LoadFailed then
              FetchAndInstallFontFace(Entry);
            if Entry.Loaded and (Entry.InternalName <> '') then
            begin
              Resolved.Family := Entry.InternalName;
              Break;
            end;
          end;
        end;
      end;
    end;
  end;
  Result := PtrUInt(FCanvas.CreateFont(Resolved, Metrics));
end;

procedure TPixieNativeContainer.DeleteFont(HFont: PtrUInt);
begin
  FCanvas.DeleteFont(TPixieFontHandle(HFont));
end;

procedure TPixieNativeContainer.UninstallFont(Handle: PtrUInt);
begin
  FCanvas.UninstallFont(Handle);
end;

procedure TPixieNativeContainer.FetchAndInstallFontFace(
  Entry: TPixieFontFaceEntry);
var
  K: Integer;
  Src: TPixieFontFaceSrc;
  FullPath: string;
  Stream: TMemoryStream;
  Success: Boolean;
  H: PtrUInt;
begin
  for K := 0 to Entry.Sources.Count - 1 do
  begin
    Src := Entry.Sources[K];
    // Phase 1: only accept truetype or unspecified format
    if (Src.Format <> '') and (Src.Format <> 'truetype') then
      Continue;

    FullPath := ResolveUrl(Src.Url, Entry.BaseUrl);

    Stream := TMemoryStream.Create;
    try
      Success := False;
      if HasFetchableScheme(FullPath) and Assigned(FOnFetchUrl) then
        FOnFetchUrl(Self, FullPath, Stream, Success)
      else
      try
        Stream.LoadFromFile(FullPath);
        Success := Stream.Size > 0;
      except
        Success := False;
      end;

      if Success and (Stream.Size > 0) then
      begin
        if FCanvas.InstallFontFromMemory(Stream.Memory, Stream.Size, H) then
        begin
          Entry.Loaded := True;
          Entry.InstalledHandle := H;
          Entry.InternalName := PixieGetTtfFamilyName(
            Stream.Memory, Stream.Size);
          Exit;
        end;
      end;
    finally
      Stream.Free;
    end;
  end;

  Entry.LoadFailed := True;
end;

function TPixieNativeContainer.TextWidth(const Text: string;
  HFont: PtrUInt): TPixiePixel;
begin
  Result := FCanvas.MeasureText(Text, TPixieFontHandle(HFont));
end;

procedure TPixieNativeContainer.DrawText(Hdc: PtrUInt;
  const Text: string; HFont: PtrUInt; Color: TPixieWebColor;
  const Pos: TPixiePosition);
begin
  FCanvas.DrawText(Text, TPixieFontHandle(HFont), Color,
    Pos.X, Pos.Y, Pos.Width, Pos.Height);
end;

function TPixieNativeContainer.PtToPx(Pt: Single): TPixiePixel;
begin
  Result := FCanvas.PtToPx(Pt);
end;

function TPixieNativeContainer.GetDefaultFontSize: TPixiePixel;
begin
  Result := FDefaultFontSize;
end;

function TPixieNativeContainer.GetDefaultFontName: string;
begin
  Result := FDefaultFontName;
end;

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

procedure TPixieNativeContainer.DrawListMarker(Hdc: PtrUInt;
  const Marker: TPixieListMarker);
var
  Sz: Single;
begin
  Sz := Min(Marker.Pos.Width, Marker.Pos.Height);
  case Marker.MarkerType of
    lstDisc:
      FCanvas.FillEllipse(Marker.Pos.X, Marker.Pos.Y, Sz, Sz,
        Marker.Color);
    lstCircle:
      FCanvas.DrawEllipse(Marker.Pos.X, Marker.Pos.Y, Sz, Sz,
        Marker.Color, 1.0);
    lstSquare:
      FCanvas.FillRect(Marker.Pos.X, Marker.Pos.Y, Sz, Sz,
        Marker.Color);
  else
    // Numbered markers: draw as text using the marker's font
    if Marker.Font <> 0 then
      FCanvas.DrawText(IntToStr(Marker.Index) + '.',
        TPixieFontHandle(Marker.Font), Marker.Color,
        Marker.Pos.X, Marker.Pos.Y,
        Marker.Pos.Width, Marker.Pos.Height);
  end;
end;

procedure TPixieNativeContainer.LoadImage(const Src, ABaseUrl: string;
  RedrawOnReady: Boolean);
begin
  // Pre-cache the image (synchronous for local files)
  GetCachedImage(Src, ABaseUrl);
end;

procedure TPixieNativeContainer.GetImageSize(const Src, ABaseUrl: string;
  out Sz: TPixieSize);
var
  Handle: TPixieImageHandle;
  W, H: Single;
begin
  Sz.Width := 0;
  Sz.Height := 0;
  Handle := GetCachedImage(Src, ABaseUrl);
  if Handle <> 0 then
  begin
    FCanvas.GetImageSize(Handle, W, H);
    Sz.Width := W;
    Sz.Height := H;
  end;
end;

procedure TPixieNativeContainer.GetImageInfo(const Src, ABaseUrl: string;
  out Sz: TPixieSize; out AspectOnly: Boolean; out AspectRatio: Single);
var
  Handle: TPixieImageHandle;
  W, H: Single;
begin
  Sz.Width := 0;
  Sz.Height := 0;
  AspectOnly := False;
  AspectRatio := 0;
  Handle := GetCachedImage(Src, ABaseUrl);
  if Handle <> 0 then
  begin
    FCanvas.GetImageSize(Handle, W, H);
    Sz.Width := W;
    Sz.Height := H;
    AspectOnly := FCanvas.GetImageAspectInfo(Handle, AspectRatio);
  end;
end;

procedure TPixieNativeContainer.DrawImage(Hdc: PtrUInt;
  const Layer: TPixieBackgroundLayer; const Url, ABaseUrl: string;
  FrameOverride: TPixieImageHandle);
var
  Handle: TPixieImageHandle;
  R: TPixieBorderRadiuses;
  TileW, TileH: Single;
  RepeatX, RepeatY: Boolean;
  FillX, FillY, FillW, FillH: Single;
  CX, CY, CW, CH, K: Single;
begin
  if FrameOverride <> 0 then
    Handle := FrameOverride
  else
    Handle := GetCachedImage(Url, ABaseUrl);
  if Handle = 0 then Exit;

  TileW := Layer.OriginBox.Width;
  TileH := Layer.OriginBox.Height;
  if (TileW <= 0) or (TileH <= 0) then Exit;

  RepeatX := Layer.Repeat_ in [brRepeat, brRepeatX];
  RepeatY := Layer.Repeat_ in [brRepeat, brRepeatY];

  R := Layer.BorderRadius;
  FCanvas.SaveState;
  try
    FCanvas.SetClipRect(Layer.ClipBox, R);
    // SetClipRect ignores border radius on some backends (D2D, FMX).
    // Add an explicit rounded-rect path clip when radius is present.
    if R.HasRadius then
    begin
      CX := Layer.ClipBox.X;
      CY := Layer.ClipBox.Y;
      CW := Layer.ClipBox.Width;
      CH := Layer.ClipBox.Height;
      K := 0.5522847498; // bezier kappa for quarter-circle approximation
      FCanvas.BeginPath;
      FCanvas.MoveTo(CX + R.TopLeftX, CY);
      FCanvas.LineTo(CX + CW - R.TopRightX, CY);
      FCanvas.CurveTo(CX + CW - R.TopRightX * (1 - K), CY,
        CX + CW, CY + R.TopRightY * (1 - K), CX + CW, CY + R.TopRightY);
      FCanvas.LineTo(CX + CW, CY + CH - R.BottomRightY);
      FCanvas.CurveTo(CX + CW, CY + CH - R.BottomRightY * (1 - K),
        CX + CW - R.BottomRightX * (1 - K), CY + CH,
        CX + CW - R.BottomRightX, CY + CH);
      FCanvas.LineTo(CX + R.BottomLeftX, CY + CH);
      FCanvas.CurveTo(CX + R.BottomLeftX * (1 - K), CY + CH,
        CX, CY + CH - R.BottomLeftY * (1 - K),
        CX, CY + CH - R.BottomLeftY);
      FCanvas.LineTo(CX, CY + R.TopLeftY);
      FCanvas.CurveTo(CX, CY + R.TopLeftY * (1 - K),
        CX + R.TopLeftX * (1 - K), CY, CX + R.TopLeftX, CY);
      FCanvas.ClosePath;
      FCanvas.ClipPath;
    end;

    if not RepeatX and not RepeatY then
    begin
      // no-repeat: single tile
      FCanvas.DrawImage(Handle,
        Layer.OriginBox.X, Layer.OriginBox.Y, TileW, TileH);
    end
    else
    begin
      // Compute fill area — constrain non-repeating axis to one tile
      FillX := Layer.ClipBox.X;
      FillY := Layer.ClipBox.Y;
      FillW := Layer.ClipBox.Width;
      FillH := Layer.ClipBox.Height;
      if not RepeatX then
      begin
        FillX := Layer.OriginBox.X;
        FillW := TileW;
      end;
      if not RepeatY then
      begin
        FillY := Layer.OriginBox.Y;
        FillH := TileH;
      end;
      FCanvas.FillTiledImage(Handle,
        Layer.OriginBox.X, Layer.OriginBox.Y, TileW, TileH,
        FillX, FillY, FillW, FillH);
    end;
  finally
    FCanvas.RestoreState;
  end;
end;

procedure TPixieNativeContainer.DrawSolidFill(Hdc: PtrUInt;
  const Layer: TPixieBackgroundLayer; Color: TPixieWebColor);
begin
  if Color.Alpha = 0 then Exit;

  FCanvas.SaveState;
  try
    FCanvas.SetClipRect(Layer.ClipBox, Layer.BorderRadius);
    FCanvas.FillRoundedRect(
      Layer.BorderBox.X, Layer.BorderBox.Y,
      Layer.BorderBox.Width, Layer.BorderBox.Height,
      Layer.BorderRadius, Color);
  finally
    FCanvas.RestoreState;
  end;
end;

procedure TPixieNativeContainer.DrawLinearGradient(Hdc: PtrUInt;
  const Layer: TPixieBackgroundLayer;
  const Gradient: TPixieLinearGradientLayer);
begin
  FCanvas.SaveState;
  try
    FCanvas.SetClipRect(Layer.ClipBox, Layer.BorderRadius);
    FCanvas.FillLinearGradient(
      Layer.OriginBox.X, Layer.OriginBox.Y,
      Layer.OriginBox.Width, Layer.OriginBox.Height,
      Layer.BorderRadius, Gradient);
  finally
    FCanvas.RestoreState;
  end;
end;

procedure TPixieNativeContainer.DrawRadialGradient(Hdc: PtrUInt;
  const Layer: TPixieBackgroundLayer;
  const Gradient: TPixieRadialGradientLayer);
begin
  FCanvas.SaveState;
  try
    FCanvas.SetClipRect(Layer.ClipBox, Layer.BorderRadius);
    FCanvas.FillRadialGradient(
      Layer.OriginBox.X, Layer.OriginBox.Y,
      Layer.OriginBox.Width, Layer.OriginBox.Height,
      Layer.BorderRadius, Gradient);
  finally
    FCanvas.RestoreState;
  end;
end;

procedure TPixieNativeContainer.DrawConicGradient(Hdc: PtrUInt;
  const Layer: TPixieBackgroundLayer;
  const Gradient: TPixieConicGradientLayer);
begin
  FCanvas.SaveState;
  try
    FCanvas.SetClipRect(Layer.ClipBox, Layer.BorderRadius);
    FCanvas.FillConicGradient(
      Layer.OriginBox.X, Layer.OriginBox.Y,
      Layer.OriginBox.Width, Layer.OriginBox.Height,
      Layer.BorderRadius, Gradient);
  finally
    FCanvas.RestoreState;
  end;
end;

procedure TPixieNativeContainer.DrawBorders(Hdc: PtrUInt;
  const Borders: TPixieBorders; const DrawPos: TPixiePosition;
  IsRoot: Boolean);
begin
  FCanvas.DrawBorders(Borders, DrawPos, IsRoot);
end;

// ---------------------------------------------------------------------------
// Document events
// ---------------------------------------------------------------------------

procedure TPixieNativeContainer.SetCaption(const ACaption: string);
begin
  FCaption := ACaption;
  if Assigned(FOnSetCaption) then
    FOnSetCaption(Self);
end;

procedure TPixieNativeContainer.SetBaseUrl(const ABaseUrl: string);
begin
  FBaseUrl := ABaseUrl;
end;

procedure TPixieNativeContainer.Link(Doc: TObject; El: TObject);
begin
  // No-op: stylesheet link loading not yet implemented
end;

procedure TPixieNativeContainer.OnAnchorClick(const Url: string;
  El: TObject);
begin
  if Assigned(FOnAnchorClick) then
    FOnAnchorClick(Self, El, Url);
end;

function TPixieNativeContainer.OnElementClick(El: TObject): Boolean;
begin
  if Assigned(FOnElementClick) then
    Result := FOnElementClick(Self, El)
  else
    Result := False;
end;

procedure TPixieNativeContainer.OnMouseEvent(El: TObject;
  Event: TPixieMouseEvent);
begin
  // No-op by default
end;

procedure TPixieNativeContainer.SetCursor(const ACursor: string);
begin
  FCursor := ACursor;
end;

// ---------------------------------------------------------------------------
// Text & CSS
// ---------------------------------------------------------------------------

procedure TPixieNativeContainer.TransformText(var Text: string;
  Tt: TPixieTextTransform);
var
  I, Start: Integer;
  Ch: UInt32;
  PrevSpace: Boolean;
  Tmp, Up: string;
begin
  case Tt of
    ttUppercase:
      Text := AnsiUpperCase(Text);
    ttLowercase:
      Text := AnsiLowerCase(Text);
    ttCapitalize:
    begin
      PrevSpace := True;
      I := 1;
      while I <= Length(Text) do
      begin
        Start := I;
        Ch := ReadUtf8Char(Text, I);
        if PrevSpace and (Ch > 32) then
        begin
          Tmp := Copy(Text, Start, I - Start);
          Up := AnsiUpperCase(Tmp);
          if Up <> Tmp then
          begin
            Delete(Text, Start, I - Start);
            Insert(Up, Text, Start);
            I := Start + Length(Up);
          end;
        end;
        PrevSpace := (Ch = 32) or (Ch = 9) or (Ch = 10) or (Ch = 13) or (Ch = 12);
      end;
    end;
  end;
end;

procedure TPixieNativeContainer.ClearCssCache;
begin
  FCssCache.Clear;
end;

procedure TPixieNativeContainer.ImportCss(var Text: string;
  const Url: string; var ABaseUrl: string);
var
  FullPath: string;
  Sl: TStringList;
  FetchStream: TMemoryStream;
  Success: Boolean;
  ParsedUrl: TPixieUrl;
  CacheEntry: TPixieCssCacheEntry;
begin
  FullPath := ResolveUrl(Url, ABaseUrl);

  // Return cached if available
  if FCssCache.TryGetValue(FullPath, CacheEntry) then
  begin
    Text := CacheEntry.Text;
    ABaseUrl := CacheEntry.BaseUrl;
    Exit;
  end;

  // Schemed URL — fetch via event callback
  if HasFetchableScheme(FullPath) and Assigned(FOnFetchUrl) then
  begin
    FetchStream := TMemoryStream.Create;
    try
      Success := False;
      FOnFetchUrl(Self, FullPath, FetchStream, Success);
      if Success and (FetchStream.Size > 0) then
      begin
        FetchStream.Position := 0;
        Sl := TStringList.Create;
        try
          Sl.LoadFromStream(FetchStream);
          Text := Sl.Text;
        finally
          Sl.Free;
        end;
        ParsedUrl := TPixieUrl.Create(FullPath);
        ABaseUrl := TPixieUrl.Create(ParsedUrl.Scheme, ParsedUrl.Authority,
          PixieUrlPathDirectoryName(ParsedUrl.Path), '', '').Str;
      end
      else
        Text := '';
    finally
      FetchStream.Free;
    end;
    if Text <> '' then
    begin
      CacheEntry.Text := Text;
      CacheEntry.BaseUrl := ABaseUrl;
      FCssCache.Add(FullPath, CacheEntry);
    end;
    Exit;
  end;

  // Local file
  if FileExists(FullPath) then
  begin
    Sl := TStringList.Create;
    try
      Sl.LoadFromFile(FullPath);
      Text := Sl.Text;
      ABaseUrl := ExtractFilePath(FullPath);
    finally
      Sl.Free;
    end;
    CacheEntry.Text := Text;
    CacheEntry.BaseUrl := ABaseUrl;
    FCssCache.Add(FullPath, CacheEntry);
  end
  else
    Text := '';
end;

// ---------------------------------------------------------------------------
// Selection highlight
// ---------------------------------------------------------------------------

procedure TPixieNativeContainer.DrawHighlight(Hdc: PtrUInt;
  const Pos: TPixiePosition; Color: TPixieWebColor);
begin
  FCanvas.FillRect(Pos.X, Pos.Y, Pos.Width, Pos.Height, Color);
end;

procedure TPixieNativeContainer.DrawLine(Hdc: PtrUInt;
  X1, Y1, X2, Y2: TPixiePixel; Color: TPixieWebColor;
  StrokeWidth: Single; Style: TPixieTextDecorationStyle);
begin
  FCanvas.DrawLine(X1, Y1, X2, Y2, Color, StrokeWidth, Style);
end;

// ---------------------------------------------------------------------------
// Clipping
// ---------------------------------------------------------------------------

procedure TPixieNativeContainer.PushOpacity(AOpacity: Single);
begin
  FCanvas.PushOpacity(AOpacity);
end;

procedure TPixieNativeContainer.PopOpacity;
begin
  FCanvas.PopOpacity;
end;

procedure TPixieNativeContainer.SaveState;
begin
  FCanvas.SaveState;
end;

procedure TPixieNativeContainer.RestoreState;
begin
  FCanvas.RestoreState;
end;

procedure TPixieNativeContainer.ConcatMatrix(A, B, C, D, E, F: Single);
begin
  FCanvas.ConcatMatrix(A, B, C, D, E, F);
end;

function TPixieNativeContainer.SupportsTransform: Boolean;
begin
  Result := FCanvas.SupportsTransform;
end;

procedure TPixieNativeContainer.SetClip(const Pos: TPixiePosition;
  const BdrRadius: TPixieBorderRadiuses);
begin
  FCanvas.SaveState;
  FCanvas.SetClipRect(Pos, BdrRadius);
end;

procedure TPixieNativeContainer.DelClip;
begin
  FCanvas.RestoreState;
end;

// ---------------------------------------------------------------------------
// Viewport & media
// ---------------------------------------------------------------------------

procedure TPixieNativeContainer.GetViewport(
  out Viewport: TPixiePosition);
begin
  Viewport.X := 0;
  Viewport.Y := 0;
  Viewport.Width := FViewportWidth;
  Viewport.Height := FViewportHeight;
end;

procedure TPixieNativeContainer.GetMediaFeatures(
  out Media: TPixieMediaFeatures);
begin
  Media.MediaType := FMediaType;
  Media.Width := FViewportWidth;
  Media.Height := FViewportHeight;
  Media.DeviceWidth := FViewportWidth;
  Media.DeviceHeight := FViewportHeight;
  Media.Color := 8;
  Media.ColorIndex := 0;
  Media.Monochrome := 0;
  Media.Resolution := 96;
  // Resolve the application's colour-scheme preference. pcsAuto follows the
  // host OS/toolkit; pcsLight/pcsDark force the reported scheme.
  case FColorScheme of
    pcsLight: Media.PrefersDark := False;
    pcsDark:  Media.PrefersDark := True;
  else
    Media.PrefersDark := PixieSystemPrefersDark;
  end;
end;

procedure TPixieNativeContainer.GetLanguage(
  out Language, Culture: string);
begin
  Language := 'en';
  Culture := '';
end;

// ---------------------------------------------------------------------------
// Element creation
// ---------------------------------------------------------------------------

function TPixieNativeContainer.CreateElement(const TagName: string;
  Attrs: TPixieStringMap; Doc: TObject): TObject;
begin
  // Return nil — let the document create default elements
  Result := nil;
end;

end.
