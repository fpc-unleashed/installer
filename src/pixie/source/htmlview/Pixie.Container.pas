unit Pixie.Container;

// Abstract container interface.
//
// This is the callback interface that the host application must implement
// to handle font creation, text measurement, drawing, image loading,
// CSS import, and other platform-specific operations.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils,
  Pixie.Types, Pixie.WebColor, Pixie.Borders,
  Pixie.GradientLayer, Pixie.Background,
  Pixie.FontDescription, Pixie.CssLength,
  Pixie.AnimatedImage, Pixie.Canvas;

type
  TPixieTextPieceKind = (tpWord, tpSpace);
  TPixieTextPieceCallback = procedure(const Text: string;
    Kind: TPixieTextPieceKind; UserData: Pointer);

  TPixieMouseEvent = (meEnter, meLeave);

  // Fired by the container the first time an animated image is decoded
  // and cached. The view core uses this to attach a playback cursor and
  // start the per-view animation timer.
  TPixieAnimatedImageDiscoveredEvent = procedure(Sender: TObject;
    const Key: string; Image: TPixieAnimatedImage) of object;

  // Acquire/release callbacks let an element ask the view core for a
  // per-element playback cursor without depending on the view-core unit
  // (avoids a circular reference; the container is the meeting place).
  TPixieAnimCursorAcquireEvent = function(Sender: TObject;
    Element: TObject;
    Image: TPixieAnimatedImage): TPixieAnimationCursor of object;
  TPixieAnimCursorReleaseEvent = procedure(Sender: TObject;
    Cursor: TPixieAnimationCursor) of object;

  { TPixieListMarker }
  TPixieListMarker = record
    Image: string;
    BaseUrl: string;
    MarkerType: TPixieListStyleType;
    Color: TPixieWebColor;
    Pos: TPixiePosition;
    Index: Integer;
    Font: PtrUInt;
  end;

  { TPixieContainer }
  TPixieContainer = class
  public
    // Font management
    function CreateFont(const Descr: TPixieFontDescription; Doc: TObject;
      out Metrics: TPixieFontMetrics): PtrUInt; virtual; abstract;
    procedure DeleteFont(HFont: PtrUInt); virtual; abstract;
    procedure UninstallFont(Handle: PtrUInt); virtual;
    function TextWidth(const Text: string; HFont: PtrUInt): TPixiePixel; virtual; abstract;
    procedure DrawText(Hdc: PtrUInt; const Text: string; HFont: PtrUInt;
      Color: TPixieWebColor; const Pos: TPixiePosition); virtual; abstract;
    function PtToPx(Pt: Single): TPixiePixel; virtual; abstract;
    function GetDefaultFontSize: TPixiePixel; virtual; abstract;
    function GetDefaultFontName: string; virtual; abstract;

    // Drawing
    procedure DrawListMarker(Hdc: PtrUInt;
      const Marker: TPixieListMarker); virtual; abstract;
    procedure LoadImage(const Src, BaseUrl: string;
      RedrawOnReady: Boolean); virtual; abstract;
    procedure GetImageSize(const Src, BaseUrl: string;
      out Sz: TPixieSize); virtual; abstract;
    // Combined size + aspect-only lookup with a single cache hit. When
    // AspectOnly is True (e.g. SVG with viewBox but no width/height),
    // AspectRatio gives width/height and Sz reports the viewBox extents.
    procedure GetImageInfo(const Src, BaseUrl: string;
      out Sz: TPixieSize; out AspectOnly: Boolean;
      out AspectRatio: Single); virtual;
    // FrameOverride: when non-zero, the container should draw this image
    // handle instead of resolving Url through its cache. Used by animated
    // <img> elements to substitute the current cursor frame without
    // mutating the shared cache.
    procedure DrawImage(Hdc: PtrUInt; const Layer: TPixieBackgroundLayer;
      const Url, BaseUrl: string;
      FrameOverride: TPixieImageHandle = 0); virtual; abstract;
    // Animation: nil from the default container; concrete native
    // containers wire these to a view-core cursor registry.
    function GetAnimatedImage(const Src,
      BaseUrl: string): TPixieAnimatedImage; virtual;
    function AcquireAnimationCursor(Element: TObject;
      AnimImg: TPixieAnimatedImage): TPixieAnimationCursor; virtual;
    procedure ReleaseAnimationCursor(
      Cursor: TPixieAnimationCursor); virtual;
    procedure DrawSolidFill(Hdc: PtrUInt; const Layer: TPixieBackgroundLayer;
      Color: TPixieWebColor); virtual; abstract;
    procedure DrawLinearGradient(Hdc: PtrUInt;
      const Layer: TPixieBackgroundLayer;
      const Gradient: TPixieLinearGradientLayer); virtual; abstract;
    procedure DrawRadialGradient(Hdc: PtrUInt;
      const Layer: TPixieBackgroundLayer;
      const Gradient: TPixieRadialGradientLayer); virtual; abstract;
    procedure DrawConicGradient(Hdc: PtrUInt;
      const Layer: TPixieBackgroundLayer;
      const Gradient: TPixieConicGradientLayer); virtual; abstract;
    procedure DrawBorders(Hdc: PtrUInt; const Borders: TPixieBorders;
      const DrawPos: TPixiePosition; IsRoot: Boolean); virtual; abstract;

    // Document events
    procedure SetCaption(const Caption: string); virtual; abstract;
    procedure SetBaseUrl(const BaseUrl: string); virtual; abstract;
    procedure Link(Doc: TObject; El: TObject); virtual; abstract;
    procedure OnAnchorClick(const Url: string;
      El: TObject); virtual; abstract;
    function OnElementClick(El: TObject): Boolean; virtual;
    procedure OnMouseEvent(El: TObject;
      Event: TPixieMouseEvent); virtual; abstract;
    procedure SetCursor(const Cursor: string); virtual; abstract;

    // Text & CSS
    procedure TransformText(var Text: string;
      Tt: TPixieTextTransform); virtual; abstract;
    procedure ImportCss(var Text: string; const Url: string;
      var BaseUrl: string); virtual; abstract;
    procedure SplitText(const Text: string;
      Callback: TPixieTextPieceCallback; UserData: Pointer); virtual;

    // Opacity layers
    procedure PushOpacity(AOpacity: Single); virtual;
    procedure PopOpacity; virtual;

    // Clipping
    procedure SetClip(const Pos: TPixiePosition;
      const BdrRadius: TPixieBorderRadiuses); virtual; abstract;
    procedure DelClip; virtual; abstract;

    // Graphics state stack + affine transform (for CSS transforms)
    procedure SaveState; virtual; abstract;
    procedure RestoreState; virtual; abstract;
    procedure ConcatMatrix(A, B, C, D, E, F: Single); virtual; abstract;
    function SupportsTransform: Boolean; virtual; abstract;

    // Viewport & media
    procedure GetViewport(out Viewport: TPixiePosition); virtual; abstract;
    procedure GetMediaFeatures(
      out Media: TPixieMediaFeatures); virtual; abstract;
    procedure GetLanguage(
      out Language, Culture: string); virtual; abstract;

    // Element creation
    function CreateElement(const TagName: string; Attrs: TPixieStringMap;
      Doc: TObject): TObject; virtual; abstract;

    // Selection highlight
    procedure DrawHighlight(Hdc: PtrUInt; const Pos: TPixiePosition;
      Color: TPixieWebColor); virtual;

    // Decoration line
    procedure DrawLine(Hdc: PtrUInt; X1, Y1, X2, Y2: TPixiePixel;
      Color: TPixieWebColor; StrokeWidth: Single;
      Style: TPixieTextDecorationStyle = tdsSolid); virtual;

    // Text offset helper (converts pixel X to byte offset in UTF-8 text)
    function TextOffsetAtX(const Text: string; HFont: PtrUInt;
      X: TPixiePixel): Integer;

  end;

implementation

uses
  Pixie.Utf8;

{ TPixieContainer }

procedure TPixieContainer.GetImageInfo(const Src, BaseUrl: string;
  out Sz: TPixieSize; out AspectOnly: Boolean; out AspectRatio: Single);
begin
  Sz.Width := 0;
  Sz.Height := 0;
  AspectOnly := False;
  AspectRatio := 0;
  GetImageSize(Src, BaseUrl, Sz);
end;

function TPixieContainer.GetAnimatedImage(const Src,
  BaseUrl: string): TPixieAnimatedImage;
begin
  Result := nil;
end;

function TPixieContainer.AcquireAnimationCursor(Element: TObject;
  AnimImg: TPixieAnimatedImage): TPixieAnimationCursor;
begin
  Result := nil;
end;

procedure TPixieContainer.ReleaseAnimationCursor(
  Cursor: TPixieAnimationCursor);
begin
  // no-op default
end;

procedure TPixieContainer.PushOpacity(AOpacity: Single);
begin
  // no-op default
end;

procedure TPixieContainer.PopOpacity;
begin
  // no-op default
end;

function TPixieContainer.OnElementClick(El: TObject): Boolean;
begin
  Result := False;
end;

procedure TPixieContainer.DrawHighlight(Hdc: PtrUInt;
  const Pos: TPixiePosition; Color: TPixieWebColor);
begin
  // No-op default
end;

procedure TPixieContainer.DrawLine(Hdc: PtrUInt;
  X1, Y1, X2, Y2: TPixiePixel; Color: TPixieWebColor;
  StrokeWidth: Single; Style: TPixieTextDecorationStyle);
begin
  // No-op default
end;

function TPixieContainer.TextOffsetAtX(const Text: string;
  HFont: PtrUInt; X: TPixiePixel): Integer;
var
  I, Len, BestPos: Integer;
  MeasW, BestDist, Dist: TPixiePixel;
begin
  Len := Length(Text);
  BestPos := 0;
  BestDist := Abs(X);

  I := 1;
  while I <= Len do
  begin
    ReadUtf8Char(Text, I); // advances I past next character
    MeasW := TextWidth(Copy(Text, 1, I - 1), HFont);
    Dist := Abs(X - MeasW);
    if Dist < BestDist then
    begin
      BestDist := Dist;
      BestPos := I - 1;
    end;
  end;

  Result := BestPos;
end;

procedure TPixieContainer.SplitText(const Text: string;
  Callback: TPixieTextPieceCallback; UserData: Pointer);
var
  Buf: string;
  I, Len: Integer;
  Cp: UInt32;
begin
  // Default implementation: split on whitespace and CJK boundaries,
  // matching the document_container split_text logic.
  Buf := '';
  I := 1;
  Len := Length(Text);
  while I <= Len do
  begin
    Cp := ReadUtf8Char(Text, I);
    if (Cp <= 32) and ((Cp = 32) or (Cp = 9) or (Cp = 10) or
      (Cp = 13) or (Cp = 12)) then
    begin
      if Buf <> '' then
      begin
        Callback(Buf, tpWord, UserData);
        Buf := '';
      end;
      Buf := '';
      AppendUtf8Char(Buf, Cp);
      Callback(Buf, tpSpace, UserData);
      Buf := '';
    end
    else if (Cp >= $4E00) and (Cp <= $9FCC) then
    begin
      // CJK character - each is its own word
      if Buf <> '' then
      begin
        Callback(Buf, tpWord, UserData);
        Buf := '';
      end;
      AppendUtf8Char(Buf, Cp);
      Callback(Buf, tpWord, UserData);
      Buf := '';
    end
    else
      AppendUtf8Char(Buf, Cp);
  end;
  if Buf <> '' then
    Callback(Buf, tpWord, UserData);
end;

procedure TPixieContainer.UninstallFont(Handle: PtrUInt);
begin
end;

end.
