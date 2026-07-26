unit Pixie.Canvas.Pdf;

// PDF content stream implementation of TPixieCanvas.
// All drawing is accumulated as PDF operators, text is measured
// using TrueType font metrics, and results are written to PDF objects
// via TPixiePdfWriter.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Math, Generics.Collections,
  Pixie.Types, Pixie.WebColor, Pixie.Borders,
  Pixie.GradientLayer, Pixie.FontDescription,
  Pixie.Canvas, Pixie.TrueType, Pixie.PdfWriter;

type
  TPixieUInt16List = TList<UInt16>;
  TPixiePdfObjectRefList = TList<TPixiePdfObject>;

  { TPixiePdfFontInfo }

  TPixiePdfFontInfo = class
    TtFont: TPixieTrueTypeFont;
    FamilyName: string;
    FontSize: TPixiePixel;
    DecorationLine: Integer;
    PdfName: AnsiString;      // e.g. /F1
    Type0ObjId: Integer;      // PDF object id for the Type0 font
    CidFontObjId: Integer;
    DescriptorObjId: Integer;
    FontFileObjId: Integer;
    ToUnicodeObjId: Integer;
    UsedGlyphs: TPixieGlyphMap; // glyph ID -> codepoint
    Metrics: TPixieFontMetrics;
    constructor Create;
    destructor Destroy; override;
  end;

  TPixiePdfFontInfoList = TObjectList<TPixiePdfFontInfo>;

  { TPixiePdfImageInfo }

  TPixiePdfImageInfo = class
    PdfName: AnsiString;      // e.g. /Im1
    ObjId: Integer;
    SmaskObjId: Integer;
    ImgWidth: Integer;
    ImgHeight: Integer;
  end;

  TPixiePdfImageInfoList = TObjectList<TPixiePdfImageInfo>;

  { TPixiePdfSavedState }

  TPixiePdfSavedState = record
    Dummy: Integer;
  end;

  { TPixiePdfCanvas }

  TPixiePdfCanvas = class(TPixieCanvas)
  private
    FWriter: TPixiePdfWriter;
    FPageHeight: Single;       // in points
    FFontCache: TPixieTrueTypeFontCache;
    FFonts: TPixiePdfFontInfoList;
    FImages: TPixiePdfImageInfoList;
    FContentStream: TMemoryStream;
    FFontCounter: Integer;
    FImageCounter: Integer;
    FGsCounter: Integer;
    FShadingCounter: Integer;
    FCurrentPage: TPixiePdfObject;
    FAllPages: TPixiePdfObjectRefList;
    FResourceFonts: AnsiString;
    FResourceXObjects: AnsiString;
    FResourceExtGState: AnsiString;
    FResourceShading: AnsiString;
    FOpacityStack: array[0..31] of Single;
    FOpacityTop: Integer;

    procedure Emit(const S: AnsiString);
    procedure EmitLn(const S: AnsiString);
    procedure EmitDashPattern;
    function PxToPt(V: Single): Single;
    function PxToY(V: Single): Single;
    procedure SetPdfColor(const C: TPixieWebColor; Fill: Boolean);
    procedure BuildRoundedRectPath(X, Y, W, H: Single;
      const R: TPixieBorderRadiuses);
    function FindOrCreateFont(const Family: string;
      Weight: Integer; Italic: Boolean): TPixieTrueTypeFont;
    function AllocFontName: AnsiString;
    function AllocImageName: AnsiString;
    function AllocGsName: AnsiString;
    function AllocShadingName: AnsiString;
    procedure EmitBezierEllipse(CX, CY, RX, RY: Single);
    procedure RegisterFontUsedGlyph(Info: TPixiePdfFontInfo;
      GlyphId: UInt16; Codepoint: UInt32);
    function FindFallbackFontInfo(Primary: TPixiePdfFontInfo;
      Codepoint: UInt32): TPixiePdfFontInfo;
    function BuildType2Function(const C0, C1: TPixieWebColor): TPixiePdfObject;
    function BuildColorFunction(
      ColorPoints: TPixieColorPointList): TPixiePdfObject;
    procedure EmitClipPath(X, Y, W, H: Single;
      const Radius: TPixieBorderRadiuses);
    procedure BuildFontObjects(Info: TPixiePdfFontInfo);
    procedure FinalizeFonts;
    procedure FinalizePageResources;
    {$IFDEF FPC}
    function LoadImageFPImage(const Data: TBytes): TPixieImageHandle;
    {$ENDIF}
  public
    constructor Create(AWriter: TPixiePdfWriter;
      AFontCache: TPixieTrueTypeFontCache);
    destructor Destroy; override;

    // Page management
    procedure BeginPage(PageWidth, PageHeight: Single);
    procedure EndPage;

    // --- TPixieCanvas overrides ---

    procedure BeginPaint(DC: PtrUInt); override;
    procedure EndPaint; override;

    procedure SaveState; override;
    procedure RestoreState; override;
    procedure PushOpacity(AOpacity: Single); override;
    procedure PopOpacity; override;

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
    function PtToPx(Pt: Single): TPixiePixel; override;

    function LoadImage(const Path: string): TPixieImageHandle; override;
    function LoadImageFromPixels(Width, Height: Integer;
      Pixels: Pointer; Pitch: Integer): TPixieImageHandle; override;
    procedure FreeImage(Handle: TPixieImageHandle); override;
    procedure GetImageSize(Handle: TPixieImageHandle;
      out W, H: Single); override;
    procedure DrawImage(Handle: TPixieImageHandle;
      DstX, DstY, DstW, DstH: Single); override;

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

    function LoadSvgFromData(Data: Pointer;
      Size: Integer): TPixieImageHandle; override;

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
    procedure ClipPath(FillRule: TPixieFillRule = frNonZero); override;
    procedure ConcatMatrix(A, B, C, D, E, F: Single); override;
    function SupportsTransform: Boolean; override;

    // Off-screen + image export — not meaningful for the PDF canvas
    // (PDF is itself a destination format). Stubs satisfy the abstract
    // contract on TPixieCanvas.
    procedure BeginOffscreen(Width, Height: Integer;
      ClearColor: TPixieWebColor); override;
    procedure EndOffscreen; override;
    procedure SaveAsPng(Stream: TStream); override;
    procedure SaveAsBmp(Stream: TStream); override;

    property Writer: TPixiePdfWriter read FWriter;
  end;

implementation

uses
  Pixie.Utf8, Pixie.SvgToPdf
  {$IFDEF FPC}
  , FPImage, FPReadPNG, FPReadBMP, FPReadGIF, FPReadJPEG
  {$ENDIF}
  ;

const
  // Bezier kappa for circle approximation
  Kappa: Single = 0.5522847498;

// ---------------------------------------------------------------------------
// TPixiePdfFontInfo
// ---------------------------------------------------------------------------

constructor TPixiePdfFontInfo.Create;
begin
  inherited Create;
  UsedGlyphs := TPixieGlyphMap.Create;
end;

destructor TPixiePdfFontInfo.Destroy;
begin
  UsedGlyphs.Free;
  inherited;
end;

// ---------------------------------------------------------------------------
// TPixiePdfCanvas - construction
// ---------------------------------------------------------------------------

constructor TPixiePdfCanvas.Create(AWriter: TPixiePdfWriter;
  AFontCache: TPixieTrueTypeFontCache);
begin
  inherited Create;
  FWriter := AWriter;
  FFontCache := AFontCache;
  FFonts := TPixiePdfFontInfoList.Create(True);
  FImages := TPixiePdfImageInfoList.Create(True);
  FAllPages := TPixiePdfObjectRefList.Create;
  FContentStream := TMemoryStream.Create;
  FFontCounter := 0;
  FImageCounter := 0;
  FGsCounter := 0;
  FShadingCounter := 0;
  FOpacityTop := -1;
end;

destructor TPixiePdfCanvas.Destroy;
begin
  FAllPages.Free;
  FContentStream.Free;
  FImages.Free;
  FFonts.Free;
  inherited;
end;

// ---------------------------------------------------------------------------
// Content stream writing
// ---------------------------------------------------------------------------

procedure TPixiePdfCanvas.Emit(const S: AnsiString);
begin
  if Length(S) > 0 then
    FContentStream.Write(S[1], Length(S));
end;

procedure TPixiePdfCanvas.EmitLn(const S: AnsiString);
begin
  Emit(S + #10);
end;

procedure TPixiePdfCanvas.EmitDashPattern;
var
  DashStr: AnsiString;
  I: Integer;
begin
  if Length(FPathDashArray) > 0 then
  begin
    DashStr := '[';
    for I := 0 to High(FPathDashArray) do
    begin
      if I > 0 then DashStr := DashStr + ' ';
      DashStr := DashStr + PdfFloat(PxToPt(FPathDashArray[I]));
    end;
    DashStr := DashStr + '] ' + PdfFloat(PxToPt(FPathDashOffset)) + ' d';
    EmitLn(DashStr);
  end;
end;

// ---------------------------------------------------------------------------
// Coordinate transforms: Pixie px (top-left, Y-down) -> PDF pt (bottom-left, Y-up)
// ---------------------------------------------------------------------------

function TPixiePdfCanvas.PxToPt(V: Single): Single;
begin
  Result := V * 72.0 / 96.0;
end;

function TPixiePdfCanvas.PxToY(V: Single): Single;
begin
  // Convert Pixie Y (px, top-down) to PDF Y (pt, bottom-up)
  Result := FPageHeight - V * 72.0 / 96.0;
end;

// ---------------------------------------------------------------------------
// PDF color operators
// ---------------------------------------------------------------------------

procedure TPixiePdfCanvas.SetPdfColor(const C: TPixieWebColor; Fill: Boolean);
var
  R, G, B: Single;
begin
  R := C.Red / 255.0;
  G := C.Green / 255.0;
  B := C.Blue / 255.0;
  if Fill then
    EmitLn(PdfFloat(R) + ' ' + PdfFloat(G) + ' ' + PdfFloat(B) + ' rg')
  else
    EmitLn(PdfFloat(R) + ' ' + PdfFloat(G) + ' ' + PdfFloat(B) + ' RG');
end;

// ---------------------------------------------------------------------------
// Rounded rect path
// ---------------------------------------------------------------------------

procedure TPixiePdfCanvas.BuildRoundedRectPath(X, Y, W, H: Single;
  const R: TPixieBorderRadiuses);
var
  PX, PY, PW, PH: Single;
  RTlX, RTlY, RTrX, RTrY, RBrX, RBrY, RBlX, RBlY: Single;
begin
  PX := PxToPt(X);
  PY := PxToY(Y + H); // bottom-left in PDF coords
  PW := PxToPt(W);
  PH := PxToPt(H);
  RTlX := PxToPt(R.TopLeftX);
  RTlY := PxToPt(R.TopLeftY);
  RTrX := PxToPt(R.TopRightX);
  RTrY := PxToPt(R.TopRightY);
  RBrX := PxToPt(R.BottomRightX);
  RBrY := PxToPt(R.BottomRightY);
  RBlX := PxToPt(R.BottomLeftX);
  RBlY := PxToPt(R.BottomLeftY);

  // Start at top-left, after the top-left radius (in PDF: top = PY + PH)
  EmitLn(PdfFloat(PX + RTlX) + ' ' + PdfFloat(PY + PH) + ' m');

  // Top edge -> top-right corner
  EmitLn(PdfFloat(PX + PW - RTrX) + ' ' + PdfFloat(PY + PH) + ' l');
  if (RTrX > 0) or (RTrY > 0) then
    EmitLn(
      PdfFloat(PX + PW - RTrX + RTrX * Kappa) + ' ' + PdfFloat(PY + PH) + ' ' +
      PdfFloat(PX + PW) + ' ' + PdfFloat(PY + PH - RTrY + RTrY * Kappa) + ' ' +
      PdfFloat(PX + PW) + ' ' + PdfFloat(PY + PH - RTrY) + ' c');

  // Right edge -> bottom-right corner
  EmitLn(PdfFloat(PX + PW) + ' ' + PdfFloat(PY + RBrY) + ' l');
  if (RBrX > 0) or (RBrY > 0) then
    EmitLn(
      PdfFloat(PX + PW) + ' ' + PdfFloat(PY + RBrY - RBrY * Kappa) + ' ' +
      PdfFloat(PX + PW - RBrX + RBrX * Kappa) + ' ' + PdfFloat(PY) + ' ' +
      PdfFloat(PX + PW - RBrX) + ' ' + PdfFloat(PY) + ' c');

  // Bottom edge -> bottom-left corner
  EmitLn(PdfFloat(PX + RBlX) + ' ' + PdfFloat(PY) + ' l');
  if (RBlX > 0) or (RBlY > 0) then
    EmitLn(
      PdfFloat(PX + RBlX - RBlX * Kappa) + ' ' + PdfFloat(PY) + ' ' +
      PdfFloat(PX) + ' ' + PdfFloat(PY + RBlY - RBlY * Kappa) + ' ' +
      PdfFloat(PX) + ' ' + PdfFloat(PY + RBlY) + ' c');

  // Left edge -> top-left corner
  EmitLn(PdfFloat(PX) + ' ' + PdfFloat(PY + PH - RTlY) + ' l');
  if (RTlX > 0) or (RTlY > 0) then
    EmitLn(
      PdfFloat(PX) + ' ' + PdfFloat(PY + PH - RTlY + RTlY * Kappa) + ' ' +
      PdfFloat(PX + RTlX - RTlX * Kappa) + ' ' + PdfFloat(PY + PH) + ' ' +
      PdfFloat(PX + RTlX) + ' ' + PdfFloat(PY + PH) + ' c');
end;

// ---------------------------------------------------------------------------
// Bezier ellipse (4 curves)
// ---------------------------------------------------------------------------

procedure TPixiePdfCanvas.EmitBezierEllipse(CX, CY, RX, RY: Single);
var
  KX, KY: Single;
begin
  KX := RX * Kappa;
  KY := RY * Kappa;

  // Start at top
  EmitLn(PdfFloat(CX) + ' ' + PdfFloat(CY + RY) + ' m');
  // Top -> right
  EmitLn(PdfFloat(CX + KX) + ' ' + PdfFloat(CY + RY) + ' ' +
         PdfFloat(CX + RX) + ' ' + PdfFloat(CY + KY) + ' ' +
         PdfFloat(CX + RX) + ' ' + PdfFloat(CY) + ' c');
  // Right -> bottom
  EmitLn(PdfFloat(CX + RX) + ' ' + PdfFloat(CY - KY) + ' ' +
         PdfFloat(CX + KX) + ' ' + PdfFloat(CY - RY) + ' ' +
         PdfFloat(CX) + ' ' + PdfFloat(CY - RY) + ' c');
  // Bottom -> left
  EmitLn(PdfFloat(CX - KX) + ' ' + PdfFloat(CY - RY) + ' ' +
         PdfFloat(CX - RX) + ' ' + PdfFloat(CY - KY) + ' ' +
         PdfFloat(CX - RX) + ' ' + PdfFloat(CY) + ' c');
  // Left -> top
  EmitLn(PdfFloat(CX - RX) + ' ' + PdfFloat(CY + KY) + ' ' +
         PdfFloat(CX - KX) + ' ' + PdfFloat(CY + RY) + ' ' +
         PdfFloat(CX) + ' ' + PdfFloat(CY + RY) + ' c');
end;

// ---------------------------------------------------------------------------
// Font management
// ---------------------------------------------------------------------------

function TPixiePdfCanvas.FindOrCreateFont(const Family: string;
  Weight: Integer; Italic: Boolean): TPixieTrueTypeFont;
var
  Key, FilePath: string;
begin
  Key := LowerCase(Family) + ':' + IntToStr(Weight) + ':' +
    IntToStr(Ord(Italic));

  if FFontCache.TryGetValue(Key, Result) then
    Exit;

  FilePath := PixieFindFontFile(Family, Weight, Italic);
  if FilePath = '' then
  begin
    // Try default sans-serif
    {$IFDEF MSWINDOWS}
    FilePath := PixieFindFontFile('Segoe UI', Weight, Italic);
    if FilePath = '' then
      FilePath := PixieFindFontFile('Arial', Weight, Italic);
    {$ENDIF}
    {$IFDEF LINUX}
    FilePath := PixieFindFontFile('DejaVu Sans', Weight, Italic);
    {$ENDIF}
    {$IFDEF DARWIN}
    FilePath := PixieFindFontFile('Helvetica', Weight, Italic);
    {$ENDIF}
  end;

  Result := TPixieTrueTypeFont.Create;
  if (FilePath <> '') and Result.LoadFromFile(FilePath) then
    FFontCache.Add(Key, Result)
  else
  begin
    Result.Free;
    Result := nil;
  end;
end;

function TPixiePdfCanvas.AllocFontName: AnsiString;
begin
  Inc(FFontCounter);
  Result := 'F' + AnsiString(IntToStr(FFontCounter));
end;

function TPixiePdfCanvas.AllocImageName: AnsiString;
begin
  Inc(FImageCounter);
  Result := 'Im' + AnsiString(IntToStr(FImageCounter));
end;

function TPixiePdfCanvas.AllocGsName: AnsiString;
begin
  Inc(FGsCounter);
  Result := 'GS' + AnsiString(IntToStr(FGsCounter));
end;

function TPixiePdfCanvas.AllocShadingName: AnsiString;
begin
  Inc(FShadingCounter);
  Result := 'Sh' + AnsiString(IntToStr(FShadingCounter));
end;

// ---------------------------------------------------------------------------
// Gradient helpers
// ---------------------------------------------------------------------------

function TPixiePdfCanvas.BuildType2Function(
  const C0, C1: TPixieWebColor): TPixiePdfObject;
begin
  Result := FWriter.AllocObject;
  Result.AddEntry('FunctionType', '2');
  Result.AddEntry('Domain', '[0 1]');
  Result.AddEntry('C0', '[' + PdfFloat(C0.Red / 255.0) + ' ' +
    PdfFloat(C0.Green / 255.0) + ' ' + PdfFloat(C0.Blue / 255.0) + ']');
  Result.AddEntry('C1', '[' + PdfFloat(C1.Red / 255.0) + ' ' +
    PdfFloat(C1.Green / 255.0) + ' ' + PdfFloat(C1.Blue / 255.0) + ']');
  Result.AddEntry('N', '1');
end;

function TPixiePdfCanvas.BuildColorFunction(
  ColorPoints: TPixieColorPointList): TPixiePdfObject;
var
  I, N: Integer;
  SubFuncs: TPixiePdfObjectRefList;
  FuncsStr, BoundsStr, EncodeStr: AnsiString;
begin
  N := ColorPoints.Count;
  if N < 2 then
  begin
    Result := nil;
    Exit;
  end;

  if N = 2 then
  begin
    Result := BuildType2Function(ColorPoints[0].Color,
      ColorPoints[1].Color);
    Exit;
  end;

  // N >= 3: build stitching function (Type 3)
  SubFuncs := TPixiePdfObjectRefList.Create;
  try
    for I := 0 to N - 2 do
      SubFuncs.Add(BuildType2Function(ColorPoints[I].Color,
        ColorPoints[I + 1].Color));

    FuncsStr := '[';
    for I := 0 to SubFuncs.Count - 1 do
      FuncsStr := FuncsStr + PdfRef(SubFuncs[I].Id) + ' ';
    FuncsStr := FuncsStr + ']';

    BoundsStr := '[';
    for I := 1 to N - 2 do
      BoundsStr := BoundsStr + PdfFloat(ColorPoints[I].Offset) + ' ';
    BoundsStr := BoundsStr + ']';

    EncodeStr := '[';
    for I := 0 to N - 2 do
      EncodeStr := EncodeStr + '0 1 ';
    EncodeStr := EncodeStr + ']';

    Result := FWriter.AllocObject;
    Result.AddEntry('FunctionType', '3');
    Result.AddEntry('Domain', '[0 1]');
    Result.AddEntry('Functions', FuncsStr);
    Result.AddEntry('Bounds', BoundsStr);
    Result.AddEntry('Encode', EncodeStr);
  finally
    SubFuncs.Free;
  end;
end;

procedure TPixiePdfCanvas.EmitClipPath(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses);
var
  HasR: Boolean;
  PX, PY, PW, PH: Single;
begin
  HasR := (Radius.TopLeftX > 0) or (Radius.TopLeftY > 0) or
          (Radius.TopRightX > 0) or (Radius.TopRightY > 0) or
          (Radius.BottomRightX > 0) or (Radius.BottomRightY > 0) or
          (Radius.BottomLeftX > 0) or (Radius.BottomLeftY > 0);

  if HasR then
  begin
    BuildRoundedRectPath(X, Y, W, H, Radius);
    EmitLn('W n');
  end
  else
  begin
    PX := PxToPt(X);
    PY := PxToY(Y + H);
    PW := PxToPt(W);
    PH := PxToPt(H);
    EmitLn(PdfFloat(PX) + ' ' + PdfFloat(PY) + ' ' +
           PdfFloat(PW) + ' ' + PdfFloat(PH) + ' re W n');
  end;
end;

procedure TPixiePdfCanvas.RegisterFontUsedGlyph(Info: TPixiePdfFontInfo;
  GlyphId: UInt16; Codepoint: UInt32);
begin
  if not Info.UsedGlyphs.ContainsKey(GlyphId) then
    Info.UsedGlyphs.Add(GlyphId, Codepoint);
end;

function TPixiePdfCanvas.FindFallbackFontInfo(Primary: TPixiePdfFontInfo;
  Codepoint: UInt32): TPixiePdfFontInfo;
const
  FallbackFamilies: array[0..8] of string = (
    {$IFDEF MSWINDOWS}
    'Microsoft YaHei',   // Chinese
    'Yu Gothic',         // Japanese
    'Malgun Gothic',     // Korean
    'Arial Unicode MS',  // Broad coverage
    'Segoe UI Symbol',   // Symbols
    'Segoe UI Emoji',    // Emoji
    'Noto Sans',         // Cross-platform
    'Noto Emoji',        // Monochrome emoji
    'Symbola'            // Broad Unicode coverage
    {$ENDIF}
    {$IFDEF LINUX}
    'Noto Sans CJK SC',
    'Noto Sans CJK JP',
    'Noto Sans CJK KR',
    'WenQuanYi Micro Hei',
    'Noto Sans',
    'DejaVu Sans',
    'Liberation Sans',
    'Noto Emoji',        // Monochrome emoji (glyf outlines)
    'Symbola'            // Broad Unicode coverage
    {$ENDIF}
    {$IFDEF DARWIN}
    'PingFang SC',
    'Hiragino Sans',
    'Apple SD Gothic Neo',
    'Arial Unicode MS',
    'Noto Sans CJK SC',
    'Helvetica Neue',
    'Noto Sans',
    'Noto Emoji',        // Monochrome emoji
    'Apple Symbols'      // Symbols and pictographs
    {$ENDIF}
  );
var
  I, J: Integer;
  GlyphId: UInt16;
  TtFont: TPixieTrueTypeFont;
  Scale: Single;
  SpaceGlyph: UInt16;
begin
  // Check if any already-loaded fallback font has this glyph
  for I := 0 to FFonts.Count - 1 do
  begin
    Result := FFonts[I];
    if (Result.TtFont <> nil) and (Result.TtFont <> Primary.TtFont) and
       (Abs(Result.FontSize - Primary.FontSize) < 0.01) then
    begin
      GlyphId := Result.TtFont.CharToGlyph(Codepoint);
      if (GlyphId <> 0) and Result.TtFont.HasGlyphOutline(GlyphId) then
        Exit;
    end;
  end;

  // Try each fallback family
  for J := Low(FallbackFamilies) to High(FallbackFamilies) do
  begin
    TtFont := FindOrCreateFont(FallbackFamilies[J], 400, False);
    if (TtFont <> nil) and (TtFont <> Primary.TtFont) then
    begin
      GlyphId := TtFont.CharToGlyph(Codepoint);
      // Verify the glyph has outline data (rejects colour-only emoji fonts)
      if (GlyphId <> 0) and TtFont.HasGlyphOutline(GlyphId) then
      begin
        // Create a new TPixiePdfFontInfo for this fallback
        Result := TPixiePdfFontInfo.Create;
        Result.TtFont := TtFont;
        Result.FamilyName := FallbackFamilies[J];
        Result.FontSize := Primary.FontSize;
        Result.DecorationLine := Primary.DecorationLine;
        Result.PdfName := AllocFontName;

        Scale := Primary.FontSize / TtFont.UnitsPerEm;
        Result.Metrics := Primary.Metrics;
        Result.Metrics.Ascent := TtFont.Ascent * Scale;
        Result.Metrics.Descent := Abs(TtFont.Descent) * Scale;
        Result.Metrics.Height := Result.Metrics.Ascent + Result.Metrics.Descent;
        if TtFont.XHeight > 0 then
          Result.Metrics.XHeight := TtFont.XHeight * Scale
        else
          Result.Metrics.XHeight := Result.Metrics.Ascent * 0.53;
        SpaceGlyph := TtFont.CharToGlyph(Ord('0'));
        if SpaceGlyph <> 0 then
          Result.Metrics.ChWidth := TtFont.GetGlyphWidth(SpaceGlyph) * Scale
        else
          Result.Metrics.ChWidth := Primary.FontSize * 0.5;

        FFonts.Add(Result);
        Exit;
      end;
    end;
  end;

  Result := nil;
end;

// ---------------------------------------------------------------------------
// Font PDF object construction
// ---------------------------------------------------------------------------

// Encode a Unicode codepoint as a hex string in UTF-16BE for ToUnicode CMap.
// BMP codepoints produce 4 hex digits; supplementary plane produces 8 (surrogate pair).
function CodepointToUtf16Hex(Cp: UInt32): AnsiString;
var
  Hi, Lo: UInt16;
begin
  if Cp <= $FFFF then
    Result := AnsiString(IntToHex(Cp, 4))
  else begin
    Hi := UInt16(((Cp - $10000) shr 10) + $D800);
    Lo := UInt16(((Cp - $10000) and $3FF) + $DC00);
    Result := AnsiString(IntToHex(Hi, 4) + IntToHex(Lo, 4));
  end;
end;

procedure TPixiePdfCanvas.BuildFontObjects(Info: TPixiePdfFontInfo);
var
  FontFile, Descriptor, CidFont, Type0, ToUnicode: TPixiePdfObject;
  FontData: TBytes;
  WArray: AnsiString;
  I, J, ChunkSize: Integer;
  Pair: TPair<UInt16, UInt32>;
  SortedGlyphs: TPixieUInt16List;
  GlyphId: UInt16;
  AdvWidth: UInt16;
  Scale: Single;
  CmapStr: AnsiString;
  Flags: Integer;
  Asc, Desc: Single;
begin
  if Info.TtFont = nil then Exit;

  Scale := 1000.0 / Info.TtFont.UnitsPerEm;

  // 1. FontFile2 — Flate-compressed subset .ttf
  FontFile := FWriter.AllocObject;
  Info.FontFileObjId := FontFile.Id;
  FontData := Info.TtFont.BuildSubsetFont(Info.UsedGlyphs);
  FontFile.AddEntry('Length1', AnsiString(IntToStr(Length(FontData))));
  FontFile.SetStream(FontData, True);

  // 2. FontDescriptor
  Descriptor := FWriter.AllocObject;
  Info.DescriptorObjId := Descriptor.Id;
  Flags := 32; // Nonsymbolic
  if Info.TtFont.ItalicAngle <> 0 then
    Flags := Flags or 64; // Italic
  if Info.TtFont.WeightClass >= 700 then
    Flags := Flags or (1 shl 18); // ForceBold

  Asc := Info.TtFont.Ascent * Scale;
  Desc := Info.TtFont.Descent * Scale;

  Descriptor.AddEntry('Type', '/FontDescriptor');
  Descriptor.AddEntry('FontName', '/' + Info.PdfName + 'TT');
  Descriptor.AddEntry('Flags', AnsiString(IntToStr(Flags)));
  Descriptor.AddEntry('FontBBox', PdfRect(
    Info.TtFont.BBoxXMin * Scale,
    Info.TtFont.BBoxYMin * Scale,
    Info.TtFont.BBoxXMax * Scale,
    Info.TtFont.BBoxYMax * Scale));
  Descriptor.AddEntry('ItalicAngle', PdfFloat(Info.TtFont.ItalicAngle));
  Descriptor.AddEntry('Ascent', PdfFloat(Asc));
  Descriptor.AddEntry('Descent', PdfFloat(Desc));
  Descriptor.AddEntry('CapHeight',
    PdfFloat(Info.TtFont.CapHeight * Scale));
  Descriptor.AddEntry('StemV', '80');
  Descriptor.AddEntry('FontFile2', PdfRef(FontFile.Id));

  // 3. /W array (glyph widths for used glyphs)
  SortedGlyphs := TPixieUInt16List.Create;
  try
    for Pair in Info.UsedGlyphs do
      SortedGlyphs.Add(Pair.Key);
    SortedGlyphs.Sort;

    WArray := '[';
    for I := 0 to SortedGlyphs.Count - 1 do
    begin
      GlyphId := SortedGlyphs[I];
      AdvWidth := Info.TtFont.GetGlyphWidth(GlyphId);
      WArray := WArray + AnsiString(IntToStr(GlyphId)) + ' [' +
        PdfFloat(AdvWidth * Scale) + '] ';
    end;
    WArray := WArray + ']';
  finally
    SortedGlyphs.Free;
  end;

  // 4. CIDFontType2
  CidFont := FWriter.AllocObject;
  Info.CidFontObjId := CidFont.Id;
  CidFont.AddEntry('Type', '/Font');
  CidFont.AddEntry('Subtype', '/CIDFontType2');
  CidFont.AddEntry('BaseFont', '/' + Info.PdfName + 'TT');
  CidFont.AddEntry('CIDSystemInfo',
    '<< /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>');
  CidFont.AddEntry('FontDescriptor', PdfRef(Descriptor.Id));
  CidFont.AddEntry('W', WArray);
  CidFont.AddEntry('DW', '1000');
  CidFont.AddEntry('CIDToGIDMap', '/Identity');

  // 5. ToUnicode CMap
  ToUnicode := FWriter.AllocObject;
  Info.ToUnicodeObjId := ToUnicode.Id;

  CmapStr :=
    '/CIDInit /ProcSet findresource begin'#10 +
    '12 dict begin'#10 +
    'begincmap'#10 +
    '/CIDSystemInfo'#10 +
    '<< /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def'#10 +
    '/CMapName /Adobe-Identity-UCS def'#10 +
    '/CMapType 2 def'#10 +
    '1 begincodespacerange'#10 +
    '<0000> <FFFF>'#10 +
    'endcodespacerange'#10;

  // Build bfchar entries
  SortedGlyphs := TPixieUInt16List.Create;
  try
    for Pair in Info.UsedGlyphs do
      SortedGlyphs.Add(Pair.Key);
    SortedGlyphs.Sort;

    if SortedGlyphs.Count > 0 then
    begin
      I := 0;
      while I < SortedGlyphs.Count do
      begin
        ChunkSize := SortedGlyphs.Count - I;
        if ChunkSize > 100 then
          ChunkSize := 100;
        CmapStr := CmapStr +
          AnsiString(IntToStr(ChunkSize)) + ' beginbfchar'#10;
        for J := I to I + ChunkSize - 1 do
        begin
          GlyphId := SortedGlyphs[J];
          CmapStr := CmapStr +
            '<' + AnsiString(IntToHex(GlyphId, 4)) + '> ' +
            '<' + CodepointToUtf16Hex(Info.UsedGlyphs[GlyphId]) + '>'#10;
        end;
        CmapStr := CmapStr + 'endbfchar'#10;
        Inc(I, ChunkSize);
      end;
    end;
  finally
    SortedGlyphs.Free;
  end;

  CmapStr := CmapStr +
    'endcmap'#10 +
    'CMapName currentdict /CMap defineresource pop'#10 +
    'end'#10 +
    'end'#10;

  ToUnicode.SetStream(TEncoding.ASCII.GetBytes(string(CmapStr)), True);

  // 6. Type0 (composite font root)
  Type0 := FWriter.AllocObject;
  Info.Type0ObjId := Type0.Id;
  Type0.AddEntry('Type', '/Font');
  Type0.AddEntry('Subtype', '/Type0');
  Type0.AddEntry('BaseFont', '/' + Info.PdfName + 'TT');
  Type0.AddEntry('Encoding', '/Identity-H');
  Type0.AddEntry('DescendantFonts', '[' + PdfRef(CidFont.Id) + ']');
  Type0.AddEntry('ToUnicode', PdfRef(ToUnicode.Id));
end;

procedure TPixiePdfCanvas.FinalizeFonts;
var
  I: Integer;
begin
  for I := 0 to FFonts.Count - 1 do
    BuildFontObjects(FFonts[I]);
end;

procedure TPixiePdfCanvas.FinalizePageResources;
var
  I: Integer;
  FontsDict, XObjDict: AnsiString;
begin
  // Build font resource dictionary string
  FontsDict := '<< ';
  for I := 0 to FFonts.Count - 1 do
  begin
    if FFonts[I].Type0ObjId <> 0 then
      FontsDict := FontsDict + '/' + FFonts[I].PdfName + ' ' +
        PdfRef(FFonts[I].Type0ObjId) + ' ';
  end;
  FontsDict := FontsDict + '>>';
  FResourceFonts := FontsDict;

  // Build XObject dictionary for images
  XObjDict := '<< ';
  for I := 0 to FImages.Count - 1 do
    XObjDict := XObjDict + '/' + FImages[I].PdfName + ' ' +
      PdfRef(FImages[I].ObjId) + ' ';
  XObjDict := XObjDict + '>>';
  FResourceXObjects := XObjDict;
end;

// ---------------------------------------------------------------------------
// Page management
// ---------------------------------------------------------------------------

procedure TPixiePdfCanvas.BeginPage(PageWidth, PageHeight: Single);
begin
  FPageHeight := PageHeight;
  FContentStream.Size := 0;
  FCurrentPage := FWriter.AllocPage(PageWidth, PageHeight);
  FAllPages.Add(FCurrentPage);
end;

procedure TPixiePdfCanvas.EndPage;
var
  ContentObj: TPixiePdfObject;
  Buf: TBytes;
begin
  // Create content stream object
  ContentObj := FWriter.AllocObject;
  SetLength(Buf, FContentStream.Size);
  if FContentStream.Size > 0 then
  begin
    FContentStream.Position := 0;
    FContentStream.Read(Buf[0], Length(Buf));
  end;
  ContentObj.SetStream(Buf, True);

  FCurrentPage.AddEntry('Contents', PdfRef(ContentObj.Id));

  // Resources will be finalized later when all fonts are known
  // Store the page for later resource assignment
end;

// ---------------------------------------------------------------------------
// TPixieCanvas overrides
// ---------------------------------------------------------------------------

procedure TPixiePdfCanvas.BeginPaint(DC: PtrUInt);
begin
  // No-op for PDF
end;

procedure TPixiePdfCanvas.EndPaint;
var
  I: Integer;
  ResStr: AnsiString;
begin
  // Finalize all font objects and assign resources to pages
  FinalizeFonts;
  FinalizePageResources;

  // Build combined resource string
  ResStr := '<< /Font ' + FResourceFonts +
    ' /XObject ' + FResourceXObjects;
  if FResourceExtGState <> '' then
    ResStr := ResStr + ' /ExtGState << ' + FResourceExtGState + ' >>';
  if FResourceShading <> '' then
    ResStr := ResStr + ' /Shading << ' + FResourceShading + ' >>';
  ResStr := ResStr + ' >>';

  // Set resources on all pages
  for I := 0 to FAllPages.Count - 1 do
    FAllPages[I].SetEntry('Resources', ResStr);
end;

procedure TPixiePdfCanvas.SaveState;
begin
  EmitLn('q');
end;

procedure TPixiePdfCanvas.RestoreState;
begin
  EmitLn('Q');
end;

procedure TPixiePdfCanvas.PushOpacity(AOpacity: Single);
var
  GsName: AnsiString;
  GsObj: TPixiePdfObject;
  Effective: Single;
begin
  // Compose with parent opacity
  if (FOpacityTop >= 0) and (FOpacityTop <= High(FOpacityStack)) then
    Effective := AOpacity * FOpacityStack[FOpacityTop]
  else
    Effective := AOpacity;

  Inc(FOpacityTop);
  if FOpacityTop <= High(FOpacityStack) then
    FOpacityStack[FOpacityTop] := Effective;

  // Create ExtGState object
  GsObj := FWriter.AllocObject;
  GsObj.AddEntry('Type', '/ExtGState');
  GsObj.AddEntry('ca', PdfFloat(Effective));
  GsObj.AddEntry('CA', PdfFloat(Effective));

  GsName := AllocGsName;
  FResourceExtGState := FResourceExtGState + '/' + GsName + ' ' +
    PdfRef(GsObj.Id) + ' ';

  EmitLn('q');
  EmitLn('/' + GsName + ' gs');
end;

procedure TPixiePdfCanvas.PopOpacity;
begin
  if FOpacityTop >= 0 then
    Dec(FOpacityTop);
  EmitLn('Q');
end;

procedure TPixiePdfCanvas.SetClipRect(const R: TPixiePosition;
  const Radius: TPixieBorderRadiuses);
var
  HasR: Boolean;
  PX, PY, PW, PH: Single;
begin
  HasR := (Radius.TopLeftX > 0) or (Radius.TopLeftY > 0) or
          (Radius.TopRightX > 0) or (Radius.TopRightY > 0) or
          (Radius.BottomRightX > 0) or (Radius.BottomRightY > 0) or
          (Radius.BottomLeftX > 0) or (Radius.BottomLeftY > 0);

  if HasR then
  begin
    BuildRoundedRectPath(R.X, R.Y, R.Width, R.Height, Radius);
    EmitLn('W n');
  end
  else
  begin
    PX := PxToPt(R.X);
    PY := PxToY(R.Y + R.Height);
    PW := PxToPt(R.Width);
    PH := PxToPt(R.Height);
    EmitLn(PdfFloat(PX) + ' ' + PdfFloat(PY) + ' ' +
           PdfFloat(PW) + ' ' + PdfFloat(PH) + ' re W n');
  end;
end;

procedure TPixiePdfCanvas.FillRect(X, Y, W, H: Single;
  Color: TPixieWebColor);
var
  PX, PY, PW, PH: Single;
begin
  if Color.Alpha = 0 then Exit;
  PX := PxToPt(X);
  PY := PxToY(Y + H);
  PW := PxToPt(W);
  PH := PxToPt(H);
  if Color.Alpha < 255 then
    PushOpacity(Color.Alpha / 255.0);
  SetPdfColor(Color, True);
  EmitLn(PdfFloat(PX) + ' ' + PdfFloat(PY) + ' ' +
         PdfFloat(PW) + ' ' + PdfFloat(PH) + ' re f');
  if Color.Alpha < 255 then
    PopOpacity;
end;

procedure TPixiePdfCanvas.FillRoundedRect(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses; Color: TPixieWebColor);
var
  HasR: Boolean;
begin
  if Color.Alpha = 0 then Exit;

  HasR := (Radius.TopLeftX > 0) or (Radius.TopLeftY > 0) or
          (Radius.TopRightX > 0) or (Radius.TopRightY > 0) or
          (Radius.BottomRightX > 0) or (Radius.BottomRightY > 0) or
          (Radius.BottomLeftX > 0) or (Radius.BottomLeftY > 0);

  if HasR then
  begin
    if Color.Alpha < 255 then
      PushOpacity(Color.Alpha / 255.0);
    SetPdfColor(Color, True);
    BuildRoundedRectPath(X, Y, W, H, Radius);
    EmitLn('f');
    if Color.Alpha < 255 then
      PopOpacity;
  end
  else
    FillRect(X, Y, W, H, Color);
end;

procedure TPixiePdfCanvas.FillLinearGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieLinearGradientLayer);
var
  ColorFunc, ShadingObj: TPixiePdfObject;
  ShName: AnsiString;
  X0, Y0, X1, Y1: Single;
  I: Integer;
  AvgAlpha: Single;
  GsObj: TPixiePdfObject;
  GsName: AnsiString;
begin
  if Gradient.ColorPoints.Count < 2 then Exit;

  ColorFunc := BuildColorFunction(Gradient.ColorPoints);
  if ColorFunc = nil then Exit;

  // Convert gradient endpoints from px to PDF pt
  X0 := PxToPt(Gradient.StartPt.X);
  Y0 := PxToY(Gradient.StartPt.Y);
  X1 := PxToPt(Gradient.EndPt.X);
  Y1 := PxToY(Gradient.EndPt.Y);

  // Create shading object (Type 2 = axial)
  ShadingObj := FWriter.AllocObject;
  ShadingObj.AddEntry('ShadingType', '2');
  ShadingObj.AddEntry('ColorSpace', '/DeviceRGB');
  ShadingObj.AddEntry('Coords', '[' + PdfFloat(X0) + ' ' + PdfFloat(Y0) +
    ' ' + PdfFloat(X1) + ' ' + PdfFloat(Y1) + ']');
  ShadingObj.AddEntry('Function', PdfRef(ColorFunc.Id));
  ShadingObj.AddEntry('Extend', '[true true]');

  ShName := AllocShadingName;
  FResourceShading := FResourceShading + '/' + ShName + ' ' +
    PdfRef(ShadingObj.Id) + ' ';

  // Check average alpha for opacity
  AvgAlpha := 0;
  for I := 0 to Gradient.ColorPoints.Count - 1 do
    AvgAlpha := AvgAlpha + Gradient.ColorPoints[I].Color.Alpha;
  if Gradient.ColorPoints.Count > 0 then
    AvgAlpha := AvgAlpha / Gradient.ColorPoints.Count / 255.0;

  EmitLn('q');

  // Apply opacity if needed
  if AvgAlpha < 1.0 then
  begin
    GsObj := FWriter.AllocObject;
    GsObj.AddEntry('Type', '/ExtGState');
    GsObj.AddEntry('ca', PdfFloat(AvgAlpha));
    GsObj.AddEntry('CA', PdfFloat(AvgAlpha));
    GsName := AllocGsName;
    FResourceExtGState := FResourceExtGState + '/' + GsName + ' ' +
      PdfRef(GsObj.Id) + ' ';
    EmitLn('/' + GsName + ' gs');
  end;

  // Clip to the box
  EmitClipPath(X, Y, W, H, Radius);

  // Paint shading
  EmitLn('/' + ShName + ' sh');
  EmitLn('Q');
end;

procedure TPixiePdfCanvas.FillRadialGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieRadialGradientLayer);
var
  ColorFunc, ShadingObj: TPixiePdfObject;
  ShName: AnsiString;
  CX, CY, MaxR, ScaleX, ScaleY: Single;
  I: Integer;
  AvgAlpha: Single;
  GsObj: TPixiePdfObject;
  GsName: AnsiString;
  IsEllipse: Boolean;
begin
  if Gradient.ColorPoints.Count < 2 then Exit;

  ColorFunc := BuildColorFunction(Gradient.ColorPoints);
  if ColorFunc = nil then Exit;

  // Determine if elliptical
  IsEllipse := Abs(Gradient.Radius.X - Gradient.Radius.Y) > 0.01;

  if IsEllipse then
  begin
    // Use the larger radius for the circle shading, then scale via CTM
    MaxR := Max(PxToPt(Gradient.Radius.X), PxToPt(Gradient.Radius.Y));
    ScaleX := PxToPt(Gradient.Radius.X) / MaxR;
    ScaleY := PxToPt(Gradient.Radius.Y) / MaxR;
    // Shading centre must be pre-divided by the scale so it maps correctly
    CX := PxToPt(Gradient.Position.X) / ScaleX;
    CY := PxToY(Gradient.Position.Y) / ScaleY;
  end
  else
  begin
    MaxR := PxToPt(Gradient.Radius.X);
    CX := PxToPt(Gradient.Position.X);
    CY := PxToY(Gradient.Position.Y);
    ScaleX := 1;
    ScaleY := 1;
  end;

  // Create shading object (Type 3 = radial)
  ShadingObj := FWriter.AllocObject;
  ShadingObj.AddEntry('ShadingType', '3');
  ShadingObj.AddEntry('ColorSpace', '/DeviceRGB');
  ShadingObj.AddEntry('Coords', '[' + PdfFloat(CX) + ' ' + PdfFloat(CY) +
    ' 0 ' + PdfFloat(CX) + ' ' + PdfFloat(CY) + ' ' +
    PdfFloat(MaxR) + ']');
  ShadingObj.AddEntry('Function', PdfRef(ColorFunc.Id));
  ShadingObj.AddEntry('Extend', '[true true]');

  ShName := AllocShadingName;
  FResourceShading := FResourceShading + '/' + ShName + ' ' +
    PdfRef(ShadingObj.Id) + ' ';

  // Check average alpha
  AvgAlpha := 0;
  for I := 0 to Gradient.ColorPoints.Count - 1 do
    AvgAlpha := AvgAlpha + Gradient.ColorPoints[I].Color.Alpha;
  if Gradient.ColorPoints.Count > 0 then
    AvgAlpha := AvgAlpha / Gradient.ColorPoints.Count / 255.0;

  EmitLn('q');

  // Apply opacity if needed
  if AvgAlpha < 1.0 then
  begin
    GsObj := FWriter.AllocObject;
    GsObj.AddEntry('Type', '/ExtGState');
    GsObj.AddEntry('ca', PdfFloat(AvgAlpha));
    GsObj.AddEntry('CA', PdfFloat(AvgAlpha));
    GsName := AllocGsName;
    FResourceExtGState := FResourceExtGState + '/' + GsName + ' ' +
      PdfRef(GsObj.Id) + ' ';
    EmitLn('/' + GsName + ' gs');
  end;

  // Clip to the box
  EmitClipPath(X, Y, W, H, Radius);

  // Apply elliptical CTM if needed
  if IsEllipse then
    EmitLn(PdfFloat(ScaleX) + ' 0 0 ' + PdfFloat(ScaleY) + ' 0 0 cm');

  // Paint shading
  EmitLn('/' + ShName + ' sh');
  EmitLn('Q');
end;

procedure TPixiePdfCanvas.FillConicGradient(X, Y, W, H: Single;
  const Radius: TPixieBorderRadiuses;
  const Gradient: TPixieConicGradientLayer);
var
  C: TPixieWebColor;
begin
  // Simplified: fill with first color
  if Gradient.ColorPoints.Count > 0 then
  begin
    C := Gradient.ColorPoints[0].Color;
    FillRoundedRect(X, Y, W, H, Radius, C);
  end;
end;

// ---------------------------------------------------------------------------
// Borders
// ---------------------------------------------------------------------------

procedure TPixiePdfCanvas.DrawBorders(const Borders: TPixieBorders;
  const Pos: TPixiePosition; IsRoot: Boolean);

  procedure DrawSide(const Border: TPixieBorder;
    X1, Y1, X2, Y2: Single);
  var
    PX1, PY1, PX2, PY2, PW: Single;
  begin
    if (Border.Width <= 0) or (Border.Style = bsNone) or
       (Border.Style = bsHidden) then Exit;

    PW := PxToPt(Border.Width);
    PX1 := PxToPt(X1);
    PY1 := PxToY(Y1);
    PX2 := PxToPt(X2);
    PY2 := PxToY(Y2);

    SetPdfColor(Border.Color, False);
    EmitLn(PdfFloat(PW) + ' w');

    // Dash pattern and line cap
    case Border.Style of
      bsDotted:
      begin
        EmitLn('1 J'); // round cap for round dots
        EmitLn('[0 ' + PdfFloat(PW * 2) + '] 0 d');
      end;
      bsDashed:
        EmitLn('[' + PdfFloat(PW * 3) + ' ' + PdfFloat(PW * 3) + '] 0 d');
    else
      EmitLn('[] 0 d');
    end;

    EmitLn(PdfFloat(PX1) + ' ' + PdfFloat(PY1) + ' m ' +
           PdfFloat(PX2) + ' ' + PdfFloat(PY2) + ' l S');

    // Reset line cap if changed
    if Border.Style = bsDotted then
      EmitLn('0 J');
  end;

var
  X, Y, W, H: Single;
  HasR: Boolean;
  PW: Single;
begin
  if not Borders.IsVisible then Exit;

  X := Pos.X;
  Y := Pos.Y;
  W := Pos.Width;
  H := Pos.Height;

  HasR := (Borders.Radius.TopLeftX > 0) or (Borders.Radius.TopLeftY > 0) or
          (Borders.Radius.TopRightX > 0) or (Borders.Radius.TopRightY > 0) or
          (Borders.Radius.BottomRightX > 0) or (Borders.Radius.BottomRightY > 0) or
          (Borders.Radius.BottomLeftX > 0) or (Borders.Radius.BottomLeftY > 0);

  if HasR then
  begin
    // Stroke a rounded rect path using the top border's style
    if (Borders.Top.Width > 0) and (Borders.Top.Style <> bsNone) and
       (Borders.Top.Style <> bsHidden) then
    begin
      PW := PxToPt(Borders.Top.Width);
      SetPdfColor(Borders.Top.Color, False);
      EmitLn(PdfFloat(PW) + ' w');
      case Borders.Top.Style of
        bsDotted:
        begin
          EmitLn('1 J');
          EmitLn('[0 ' + PdfFloat(PW * 2) + '] 0 d');
        end;
        bsDashed:
          EmitLn('[' + PdfFloat(PW * 3) + ' ' + PdfFloat(PW * 3) + '] 0 d');
      else
        EmitLn('[] 0 d');
      end;
      BuildRoundedRectPath(X, Y, W, H, Borders.Radius);
      EmitLn('S');
      if Borders.Top.Style = bsDotted then
        EmitLn('0 J');
    end;
    Exit;
  end;

  // Top
  DrawSide(Borders.Top,
    X, Y + Borders.Top.Width / 2,
    X + W, Y + Borders.Top.Width / 2);
  // Right
  DrawSide(Borders.Right,
    X + W - Borders.Right.Width / 2, Y,
    X + W - Borders.Right.Width / 2, Y + H);
  // Bottom
  DrawSide(Borders.Bottom,
    X, Y + H - Borders.Bottom.Width / 2,
    X + W, Y + H - Borders.Bottom.Width / 2);
  // Left
  DrawSide(Borders.Left,
    X + Borders.Left.Width / 2, Y,
    X + Borders.Left.Width / 2, Y + H);
end;

// ---------------------------------------------------------------------------
// Font creation and text
// ---------------------------------------------------------------------------

function CheckPdfFont(const Name: string): Boolean;
begin
  // Accept all — we resolve to files ourselves
  Result := True;
end;

function TPixiePdfCanvas.CreateFont(const Descr: TPixieFontDescription;
  out Metrics: TPixieFontMetrics): TPixieFontHandle;
var
  Info: TPixiePdfFontInfo;
  TtFont: TPixieTrueTypeFont;
  Family: string;
  Scale: Single;
  SpaceGlyph: UInt16;
  I: Integer;
begin
  FillChar(Metrics, SizeOf(Metrics), 0);

  Family := PixieResolveFontFamily(Descr.Family, CheckPdfFont);

  TtFont := FindOrCreateFont(Family, Descr.Weight,
    Descr.Style = fstItalic);
  if TtFont = nil then
  begin
    Result := 0;
    Exit;
  end;

  // Reuse existing font info if same font and size (avoids duplicate
  // PDF font objects and ensures glyph registration is shared)
  for I := 0 to FFonts.Count - 1 do
  begin
    Info := FFonts[I];
    if (Info.TtFont = TtFont) and
       (Abs(Info.FontSize - Descr.Size) < 0.01) and
       (Info.DecorationLine = Descr.DecorationLine) then
    begin
      Metrics := Info.Metrics;
      Result := TPixieFontHandle(Info);
      Exit;
    end;
  end;

  Info := TPixiePdfFontInfo.Create;
  Info.TtFont := TtFont;
  Info.FamilyName := Family;
  Info.FontSize := Descr.Size;
  Info.DecorationLine := Descr.DecorationLine;
  Info.PdfName := AllocFontName;
  FFonts.Add(Info);

  // Compute metrics (in CSS pixels)
  Scale := Descr.Size / TtFont.UnitsPerEm;
  Metrics.FontSize := Descr.Size;
  Metrics.Ascent := TtFont.Ascent * Scale;
  Metrics.Descent := Abs(TtFont.Descent) * Scale;
  Metrics.Height := Metrics.Ascent + Metrics.Descent;

  if TtFont.XHeight > 0 then
    Metrics.XHeight := TtFont.XHeight * Scale
  else
    Metrics.XHeight := Metrics.Ascent * 0.53;

  // ch width (width of '0')
  SpaceGlyph := TtFont.CharToGlyph(Ord('0'));
  if SpaceGlyph <> 0 then
    Metrics.ChWidth := TtFont.GetGlyphWidth(SpaceGlyph) * Scale
  else
    Metrics.ChWidth := Descr.Size * 0.5;

  Metrics.SubShift := Metrics.Ascent * 0.25;
  Metrics.SuperShift := Metrics.Ascent * 0.35;
  Metrics.DrawSpaces := False;

  Info.Metrics := Metrics;

  Result := TPixieFontHandle(Info);
end;

procedure TPixiePdfCanvas.DoDeleteFont(Handle: TPixieFontHandle);
begin
  // Fonts are owned by FFonts list and freed on canvas destroy
  // Do not delete individual fonts here — they are needed for PDF writing
end;

function TPixiePdfCanvas.DoMeasureText(const Text: string;
  Handle: TPixieFontHandle): TPixiePixel;
var
  Info, Fallback: TPixiePdfFontInfo;
  Scale: Single;
  I, Len: Integer;
  Codepoint: UInt32;
  GlyphId: UInt16;
  TotalWidth: Single;
begin
  Result := 0;
  if Handle = 0 then Exit;
  Info := TPixiePdfFontInfo(Handle);
  if Info.TtFont = nil then Exit;

  Scale := Info.FontSize / Info.TtFont.UnitsPerEm;
  TotalWidth := 0;
  I := 1;
  Len := Length(Text);

  while I <= Len do
  begin
    Codepoint := ReadUtf8Char(Text, I);
    if Codepoint = 0 then Break;

    GlyphId := Info.TtFont.CharToGlyph(Codepoint);
    if GlyphId = 0 then
    begin
      Fallback := FindFallbackFontInfo(Info, Codepoint);
      if Fallback <> nil then
      begin
        GlyphId := Fallback.TtFont.CharToGlyph(Codepoint);
        TotalWidth := TotalWidth + Fallback.TtFont.GetGlyphWidth(GlyphId) *
          (Fallback.FontSize / Fallback.TtFont.UnitsPerEm);
        Continue;
      end;
    end;
    TotalWidth := TotalWidth + Info.TtFont.GetGlyphWidth(GlyphId) * Scale;
  end;

  Result := TotalWidth;
end;

procedure TPixiePdfCanvas.DrawText(const Text: string;
  Handle: TPixieFontHandle; Color: TPixieWebColor;
  X, Y, W, H: Single);

  procedure FlushRun(RunFont: TPixiePdfFontInfo; const Hex: AnsiString;
    RunStartX, BaselineY: Single);
  var
    Pt: Single;
  begin
    if Hex = '' then Exit;
    Pt := RunFont.FontSize * 72.0 / 96.0;
    EmitLn('BT');
    EmitLn('/' + RunFont.PdfName + ' ' + PdfFloat(Pt) + ' Tf');
    EmitLn(PdfFloat(PxToPt(RunStartX)) + ' ' +
      PdfFloat(PxToY(BaselineY)) + ' Td');
    EmitLn('<' + Hex + '> Tj');
    EmitLn('ET');
  end;

var
  Info, CurFont, Fallback: TPixiePdfFontInfo;
  Scale, TextY, CurX, RunStartX, GlyphW: Single;
  I, Len: Integer;
  Codepoint: UInt32;
  GlyphId: UInt16;
  HexStr: AnsiString;
  UseFont: TPixiePdfFontInfo;
begin
  if Handle = 0 then Exit;
  Info := TPixiePdfFontInfo(Handle);
  if Info.TtFont = nil then Exit;

  Scale := Info.FontSize / Info.TtFont.UnitsPerEm;
  TextY := Y + Info.TtFont.Ascent * Scale;

  SetPdfColor(Color, True);

  CurFont := Info;
  CurX := X;
  RunStartX := X;
  HexStr := '';
  I := 1;
  Len := Length(Text);
  while I <= Len do
  begin
    Codepoint := ReadUtf8Char(Text, I);
    if Codepoint = 0 then Break;

    // Determine which font to use for this character
    GlyphId := Info.TtFont.CharToGlyph(Codepoint);
    if (GlyphId = 0) then
    begin
      Fallback := FindFallbackFontInfo(Info, Codepoint);
      if Fallback <> nil then
        UseFont := Fallback
      else
        UseFont := Info;
    end
    else
      UseFont := Info;

    // Font changed — flush the accumulated run
    if UseFont <> CurFont then
    begin
      FlushRun(CurFont, HexStr, RunStartX, TextY);
      HexStr := '';
      RunStartX := CurX;
      CurFont := UseFont;
    end;

    // Get glyph from the active font
    GlyphId := CurFont.TtFont.CharToGlyph(Codepoint);
    RegisterFontUsedGlyph(CurFont, GlyphId, Codepoint);
    GlyphW := CurFont.TtFont.GetGlyphWidth(GlyphId) *
      (CurFont.FontSize / CurFont.TtFont.UnitsPerEm);
    HexStr := HexStr + AnsiString(LowerCase(IntToHex(GlyphId, 4)));
    CurX := CurX + GlyphW;
  end;

  // Flush remaining run
  FlushRun(CurFont, HexStr, RunStartX, TextY);
end;

function TPixiePdfCanvas.PtToPx(Pt: Single): TPixiePixel;
begin
  Result := Trunc(Pt * 96.0 / 72.0);
end;

// ---------------------------------------------------------------------------
// Image
// ---------------------------------------------------------------------------

{$IFDEF FPC}
function TPixiePdfCanvas.LoadImageFPImage(
  const Data: TBytes): TPixieImageHandle;
var
  Img: TFPMemoryImage;
  Stream: TBytesStream;
  X, Y, W, H: Integer;
  C: TFPColor;
  Pixels: TBytes;
  Idx: Integer;
begin
  Result := 0;
  Img := TFPMemoryImage.Create(0, 0);
  try
    Stream := TBytesStream.Create(Data);
    try
      try
        Img.LoadFromStream(Stream);
      except
        Exit;
      end;
    finally
      Stream.Free;
    end;
    W := Img.Width;
    H := Img.Height;
    if (W <= 0) or (H <= 0) then Exit;

    // Convert to BGRA pixel array (matches LoadImageFromPixels expectation)
    SetLength(Pixels, W * H * 4);
    Idx := 0;
    for Y := 0 to H - 1 do
      for X := 0 to W - 1 do
      begin
        C := Img.Colors[X, Y];
        Pixels[Idx] := Byte(C.Blue shr 8);  Inc(Idx);
        Pixels[Idx] := Byte(C.Green shr 8); Inc(Idx);
        Pixels[Idx] := Byte(C.Red shr 8);   Inc(Idx);
        Pixels[Idx] := Byte(C.Alpha shr 8); Inc(Idx);
      end;

    Result := LoadImageFromPixels(W, H, @Pixels[0], W * 4);
  finally
    Img.Free;
  end;
end;
{$ENDIF}

function TPixiePdfCanvas.LoadImage(const Path: string): TPixieImageHandle;
var
  Resolved: string;
  Stream: TFileStream;
  ImgData: TBytes;
  ImgObj: TPixiePdfObject;
  Info: TPixiePdfImageInfo;
  W, H: Integer;
  IsJpeg: Boolean;
  SofLen: Integer;
  I: Integer;
begin
  Result := 0;
  Resolved := ExpandFileName(Path);
  if not FileExists(Resolved) then Exit;

  // Detect SVG by file extension
  if LowerCase(ExtractFileExt(Resolved)) = '.svg' then
  begin
    try
      Stream := TFileStream.Create(Resolved, fmOpenRead or fmShareDenyNone);
      try
        if Stream.Size < 4 then Exit;
        SetLength(ImgData, Stream.Size);
        Stream.ReadBuffer(ImgData[0], Length(ImgData));
      finally
        Stream.Free;
      end;
    except
      Exit;
    end;
    Result := LoadSvgFromData(@ImgData[0], Length(ImgData));
    Exit;
  end;

  try
    Stream := TFileStream.Create(Resolved, fmOpenRead or fmShareDenyNone);
    try
      if Stream.Size < 4 then Exit;
      SetLength(ImgData, Stream.Size);
      Stream.ReadBuffer(ImgData[0], Length(ImgData));
    finally
      Stream.Free;
    end;
  except
    Exit;
  end;

  // Detect JPEG by FF D8 FF header
  IsJpeg := (ImgData[0] = $FF) and (ImgData[1] = $D8) and (ImgData[2] = $FF);

  if IsJpeg then
  begin
    // Parse JPEG SOF marker for dimensions
    W := 0;
    H := 0;
    I := 2;
    while I < Length(ImgData) - 8 do
    begin
      if ImgData[I] = $FF then
      begin
        if (ImgData[I + 1] >= $C0) and (ImgData[I + 1] <= $C3) then
        begin
          H := (ImgData[I + 5] shl 8) or ImgData[I + 6];
          W := (ImgData[I + 7] shl 8) or ImgData[I + 8];
          Break;
        end;
        SofLen := (ImgData[I + 2] shl 8) or ImgData[I + 3];
        Inc(I, 2 + SofLen);
      end
      else
        Inc(I);
    end;

    if (W = 0) or (H = 0) then Exit;

    ImgObj := FWriter.AllocObject;
    ImgObj.AddEntry('Type', '/XObject');
    ImgObj.AddEntry('Subtype', '/Image');
    ImgObj.AddEntry('Width', AnsiString(IntToStr(W)));
    ImgObj.AddEntry('Height', AnsiString(IntToStr(H)));
    ImgObj.AddEntry('ColorSpace', '/DeviceRGB');
    ImgObj.AddEntry('BitsPerComponent', '8');
    ImgObj.AddEntry('Filter', '/DCTDecode');
    ImgObj.SetStream(ImgData, False); // JPEG is already compressed
    ImgObj.CompressStream := False;

    Info := TPixiePdfImageInfo.Create;
    Info.PdfName := AllocImageName;
    Info.ObjId := ImgObj.Id;
    Info.SmaskObjId := 0;
    Info.ImgWidth := W;
    Info.ImgHeight := H;
    FImages.Add(Info);
    Result := TPixieImageHandle(Info);
  end
  {$IFDEF FPC}
  else
  begin
    // Decode PNG/BMP/GIF via FPImage and create from raw pixels
    Result := LoadImageFPImage(ImgData);
  end
  {$ENDIF}
  ;
end;

function TPixiePdfCanvas.LoadImageFromPixels(Width, Height: Integer;
  Pixels: Pointer; Pitch: Integer): TPixieImageHandle;
var
  ImgObj, SmaskObj: TPixiePdfObject;
  Info: TPixiePdfImageInfo;
  RgbData, AlphaData: TBytes;
  X, Y: Integer;
  Src: PByte;
  HasAlpha: Boolean;
  B, G, R, A: Byte;
  RgbIdx, AlphaIdx: Integer;
begin
  Result := 0;
  if (Width <= 0) or (Height <= 0) or (Pixels = nil) then Exit;

  // Split BGRA pixels into RGB + Alpha
  SetLength(RgbData, Width * Height * 3);
  SetLength(AlphaData, Width * Height);
  HasAlpha := False;
  RgbIdx := 0;
  AlphaIdx := 0;

  for Y := 0 to Height - 1 do
  begin
    Src := PByte(Pixels) + Y * Pitch;
    for X := 0 to Width - 1 do
    begin
      B := Src^; Inc(Src);
      G := Src^; Inc(Src);
      R := Src^; Inc(Src);
      A := Src^; Inc(Src);

      // Un-premultiply alpha
      if (A > 0) and (A < 255) then
      begin
        R := Min(255, R * 255 div A);
        G := Min(255, G * 255 div A);
        B := Min(255, B * 255 div A);
      end;

      RgbData[RgbIdx] := R; Inc(RgbIdx);
      RgbData[RgbIdx] := G; Inc(RgbIdx);
      RgbData[RgbIdx] := B; Inc(RgbIdx);
      AlphaData[AlphaIdx] := A; Inc(AlphaIdx);

      if A <> 255 then HasAlpha := True;
    end;
  end;

  // Create SMask if needed
  SmaskObj := nil;
  if HasAlpha then
  begin
    SmaskObj := FWriter.AllocObject;
    SmaskObj.AddEntry('Type', '/XObject');
    SmaskObj.AddEntry('Subtype', '/Image');
    SmaskObj.AddEntry('Width', AnsiString(IntToStr(Width)));
    SmaskObj.AddEntry('Height', AnsiString(IntToStr(Height)));
    SmaskObj.AddEntry('ColorSpace', '/DeviceGray');
    SmaskObj.AddEntry('BitsPerComponent', '8');
    SmaskObj.SetStream(AlphaData, True);
  end;

  // Create image object
  ImgObj := FWriter.AllocObject;
  ImgObj.AddEntry('Type', '/XObject');
  ImgObj.AddEntry('Subtype', '/Image');
  ImgObj.AddEntry('Width', AnsiString(IntToStr(Width)));
  ImgObj.AddEntry('Height', AnsiString(IntToStr(Height)));
  ImgObj.AddEntry('ColorSpace', '/DeviceRGB');
  ImgObj.AddEntry('BitsPerComponent', '8');
  if SmaskObj <> nil then
    ImgObj.AddEntry('SMask', PdfRef(SmaskObj.Id));
  ImgObj.SetStream(RgbData, True);

  Info := TPixiePdfImageInfo.Create;
  Info.PdfName := AllocImageName;
  Info.ObjId := ImgObj.Id;
  if SmaskObj <> nil then
    Info.SmaskObjId := SmaskObj.Id
  else
    Info.SmaskObjId := 0;
  Info.ImgWidth := Width;
  Info.ImgHeight := Height;
  FImages.Add(Info);
  Result := TPixieImageHandle(Info);
end;

procedure TPixiePdfCanvas.FreeImage(Handle: TPixieImageHandle);
begin
  // Images are owned by FImages list; freed on canvas destroy
end;

procedure TPixiePdfCanvas.GetImageSize(Handle: TPixieImageHandle;
  out W, H: Single);
var
  Info: TPixiePdfImageInfo;
begin
  W := 0;
  H := 0;
  if Handle = 0 then Exit;
  Info := TPixiePdfImageInfo(Handle);
  W := Info.ImgWidth;
  H := Info.ImgHeight;
end;

procedure TPixiePdfCanvas.DrawImage(Handle: TPixieImageHandle;
  DstX, DstY, DstW, DstH: Single);
var
  Info: TPixiePdfImageInfo;
  PX, PY, PW, PH: Single;
begin
  if Handle = 0 then Exit;
  Info := TPixiePdfImageInfo(Handle);

  PW := PxToPt(DstW);
  PH := PxToPt(DstH);
  PX := PxToPt(DstX);
  PY := PxToY(DstY + DstH); // bottom-left in PDF

  EmitLn('q');
  // Transformation matrix: scale and translate
  EmitLn(PdfFloat(PW) + ' 0 0 ' + PdfFloat(PH) + ' ' +
         PdfFloat(PX) + ' ' + PdfFloat(PY) + ' cm');
  EmitLn('/' + Info.PdfName + ' Do');
  EmitLn('Q');
end;

// ---------------------------------------------------------------------------
// Shapes
// ---------------------------------------------------------------------------

procedure TPixiePdfCanvas.FillEllipse(X, Y, W, H: Single;
  Color: TPixieWebColor);
var
  CX, CY, RX, RY: Single;
begin
  if Color.Alpha = 0 then Exit;
  CX := PxToPt(X + W / 2);
  CY := PxToY(Y + H / 2);
  RX := PxToPt(W / 2);
  RY := PxToPt(H / 2);

  SetPdfColor(Color, True);
  EmitBezierEllipse(CX, CY, RX, RY);
  EmitLn('f');
end;

procedure TPixiePdfCanvas.DrawEllipse(X, Y, W, H: Single;
  Color: TPixieWebColor; StrokeWidth: Single);
var
  CX, CY, RX, RY: Single;
begin
  if Color.Alpha = 0 then Exit;
  CX := PxToPt(X + W / 2);
  CY := PxToY(Y + H / 2);
  RX := PxToPt(W / 2);
  RY := PxToPt(H / 2);

  SetPdfColor(Color, False);
  EmitLn(PdfFloat(PxToPt(StrokeWidth)) + ' w');
  EmitBezierEllipse(CX, CY, RX, RY);
  EmitLn('S');
end;

procedure TPixiePdfCanvas.DrawRect(X, Y, W, H: Single;
  Color: TPixieWebColor; StrokeWidth: Single);
var
  PX, PY, PW, PH: Single;
begin
  if Color.Alpha = 0 then Exit;
  PX := PxToPt(X);
  PY := PxToY(Y + H);
  PW := PxToPt(W);
  PH := PxToPt(H);

  SetPdfColor(Color, False);
  EmitLn(PdfFloat(PxToPt(StrokeWidth)) + ' w');
  EmitLn(PdfFloat(PX) + ' ' + PdfFloat(PY) + ' ' +
         PdfFloat(PW) + ' ' + PdfFloat(PH) + ' re S');
end;

procedure TPixiePdfCanvas.DrawLine(X1, Y1, X2, Y2: Single;
  Color: TPixieWebColor; StrokeWidth: Single;
  Style: TPixieTextDecorationStyle);
var
  PtW: Single;
begin
  if Color.Alpha = 0 then Exit;
  SetPdfColor(Color, False);
  PtW := PxToPt(StrokeWidth);
  EmitLn(PdfFloat(PtW) + ' w');
  if Style = tdsDotted then
    EmitLn('[' + PdfFloat(PtW) + ' ' + PdfFloat(PtW * 2) + '] 0 d')
  else if Style = tdsDashed then
    EmitLn('[' + PdfFloat(PtW * 3) + ' ' + PdfFloat(PtW * 2) + '] 0 d')
  else
    EmitLn('[] 0 d');
  EmitLn(PdfFloat(PxToPt(X1)) + ' ' + PdfFloat(PxToY(Y1)) + ' m ' +
         PdfFloat(PxToPt(X2)) + ' ' + PdfFloat(PxToY(Y2)) + ' l S');
end;

procedure TPixiePdfCanvas.StrokePolyline(const Points: array of Single;
  Color: TPixieWebColor; StrokeWidth: Single);
var
  I, Count: Integer;
begin
  Count := Length(Points) div 2;
  if (Count < 2) or (Color.Alpha = 0) then Exit;

  SetPdfColor(Color, False);
  EmitLn(PdfFloat(PxToPt(StrokeWidth)) + ' w');
  EmitLn('[] 0 d');

  EmitLn(PdfFloat(PxToPt(Points[0])) + ' ' +
         PdfFloat(PxToY(Points[1])) + ' m');
  for I := 1 to Count - 1 do
    EmitLn(PdfFloat(PxToPt(Points[I * 2])) + ' ' +
           PdfFloat(PxToY(Points[I * 2 + 1])) + ' l');
  EmitLn('S');
end;

// ---------------------------------------------------------------------------
// SVG loading
// ---------------------------------------------------------------------------

function TPixiePdfCanvas.LoadSvgFromData(Data: Pointer;
  Size: Integer): TPixieImageHandle;
var
  Renderer: TPixieSvgRenderer;
  Info: TPixiePdfImageInfo;
  ObjId: Integer;
  W, H: Single;
begin
  Result := 0;
  if (Data = nil) or (Size <= 0) then Exit;

  Renderer := TPixieSvgRenderer.Create(FWriter, FFontCache);
  try
    ObjId := Renderer.RenderToFormXObject(Data, Size, W, H);
  finally
    Renderer.Free;
  end;

  if ObjId = 0 then Exit;

  Info := TPixiePdfImageInfo.Create;
  Info.PdfName := AllocImageName;
  Info.ObjId := ObjId;
  Info.SmaskObjId := 0;
  Info.ImgWidth := Round(W);
  Info.ImgHeight := Round(H);
  FImages.Add(Info);
  Result := TPixieImageHandle(Info);
end;

// ---------------------------------------------------------------------------
// Path API
// ---------------------------------------------------------------------------

procedure TPixiePdfCanvas.BeginPath;
begin
  // PDF has implicit path state — nothing to do
end;

procedure TPixiePdfCanvas.MoveTo(X, Y: Single);
begin
  EmitLn(PdfFloat(PxToPt(X)) + ' ' + PdfFloat(PxToY(Y)) + ' m');
end;

procedure TPixiePdfCanvas.LineTo(X, Y: Single);
begin
  EmitLn(PdfFloat(PxToPt(X)) + ' ' + PdfFloat(PxToY(Y)) + ' l');
end;

procedure TPixiePdfCanvas.CurveTo(X1, Y1, X2, Y2, X3, Y3: Single);
begin
  EmitLn(PdfFloat(PxToPt(X1)) + ' ' + PdfFloat(PxToY(Y1)) + ' ' +
         PdfFloat(PxToPt(X2)) + ' ' + PdfFloat(PxToY(Y2)) + ' ' +
         PdfFloat(PxToPt(X3)) + ' ' + PdfFloat(PxToY(Y3)) + ' c');
end;

procedure TPixiePdfCanvas.ClosePath;
begin
  EmitLn('h');
end;

procedure TPixiePdfCanvas.FillPath(Color: TPixieWebColor;
  FillRule: TPixieFillRule);
begin
  if Color.Alpha = 0 then Exit;
  SetPdfColor(Color, True);
  if FillRule = frEvenOdd then
    EmitLn('f*')
  else
    EmitLn('f');
end;

procedure TPixiePdfCanvas.StrokePath(Color: TPixieWebColor;
  Width: Single);
begin
  if Color.Alpha = 0 then Exit;
  if FPathLineCap <> lcButt then
    EmitLn(AnsiString(IntToStr(Ord(FPathLineCap)) + ' J'));
  if FPathLineJoin <> ljMiter then
    EmitLn(AnsiString(IntToStr(Ord(FPathLineJoin)) + ' j'));
  EmitDashPattern;
  SetPdfColor(Color, False);
  EmitLn(PdfFloat(PxToPt(Width)) + ' w');
  EmitLn('S');
end;

procedure TPixiePdfCanvas.FillAndStrokePath(FillColor: TPixieWebColor;
  StrokeColor: TPixieWebColor; StrokeWidth: Single;
  FillRule: TPixieFillRule);
begin
  if FPathLineCap <> lcButt then
    EmitLn(AnsiString(IntToStr(Ord(FPathLineCap)) + ' J'));
  if FPathLineJoin <> ljMiter then
    EmitLn(AnsiString(IntToStr(Ord(FPathLineJoin)) + ' j'));
  EmitDashPattern;
  SetPdfColor(FillColor, True);
  SetPdfColor(StrokeColor, False);
  EmitLn(PdfFloat(PxToPt(StrokeWidth)) + ' w');
  if FillRule = frEvenOdd then
    EmitLn('B*')
  else
    EmitLn('B');
end;

procedure TPixiePdfCanvas.ClipPath(FillRule: TPixieFillRule);
begin
  if FillRule = frEvenOdd then
    EmitLn('W* n')
  else
    EmitLn('W n');
end;

procedure TPixiePdfCanvas.ConcatMatrix(A, B, C, D, E, F: Single);
begin
  // Note: PDF uses a different coordinate system (Y-up).
  // This method emits the raw cm operator; the caller is responsible
  // for coordinate conversion if needed. SVG rendering uses SvgToPdf
  // which handles its own coordinate system.
  EmitLn(PdfFloat(A) + ' ' + PdfFloat(B) + ' ' +
         PdfFloat(C) + ' ' + PdfFloat(D) + ' ' +
         PdfFloat(PxToPt(E)) + ' ' + PdfFloat(PxToY(F)) + ' cm');
end;

function TPixiePdfCanvas.SupportsTransform: Boolean;
begin
  // The HTML CSS-transform path passes relative draw-space matrices, which the
  // per-primitive PDF coordinate conversion cannot honour. Opt out so those
  // elements render untransformed in PDF rather than mis-placed off-page.
  Result := False;
end;

procedure TPixiePdfCanvas.BeginOffscreen(Width, Height: Integer;
  ClearColor: TPixieWebColor);
begin
end;

procedure TPixiePdfCanvas.EndOffscreen;
begin
end;

procedure TPixiePdfCanvas.SaveAsPng(Stream: TStream);
begin
end;

procedure TPixiePdfCanvas.SaveAsBmp(Stream: TStream);
begin
end;

end.
