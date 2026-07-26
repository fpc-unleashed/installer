unit Pixie.SvgRenderer;

// Shared SVG rendering base class.
// Provides SVG parsing (DOM walking, attribute/color/transform/path-data parsing,
// arc-to-bezier conversion, state inheritance) and shape renderers that call
// abstract drawing primitives. Subclasses override the primitives to emit
// backend-specific commands (PDF operators, FMX canvas calls, etc.).

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections,
  Pixie.Types, Pixie.WebColor, Pixie.Canvas, Pixie.Matrix;

const
  SvgDecorationThickness: Single = 0.05;       // fraction of font size
  SvgDecorationUnderlineOffset: Single = 0.15;  // fraction of font size

type
  { TPixieSvgMatrix - 2D affine transform, shared with the HTML engine }
  TPixieSvgMatrix = Pixie.Matrix.TPixieMatrix;

  TPixieSingleArray = array of Single;

  TPixieSvgDominantBaseline = (dbAuto, dbHanging, dbMiddle, dbCentral,
    dbMathematical, dbIdeographic, dbTextBeforeEdge, dbTextAfterEdge);

  { TPixieSvgState - inherited graphics state }

  TPixieSvgState = record
    FillColor: TPixieWebColor;
    StrokeColor: TPixieWebColor;
    Color: TPixieWebColor;         // CSS 'color' property (for currentColor)
    StrokeWidth: Single;
    LineCap: TPixieLineCap;
    LineJoin: TPixieLineJoin;
    DashArray: TPixieSingleArray;
    DashOffset: Single;
    Opacity: Single;
    FillOpacity: Single;
    StrokeOpacity: Single;
    HasFill: Boolean;
    HasStroke: Boolean;
    EvenOddFill: Boolean;
    FontFamily: string;
    FontSize: Single;
    FontWeight: Integer;
    FontItalic: Boolean;
    LetterSpacing: Single;
    TextAnchor: TPixieTextAlign;
    TextDecoration: Integer;
    FillGradientId: string;
    StrokeGradientId: string;
    BlendMode: TPixieBlendMode;
    XmlSpacePreserve: Boolean;
    StrokeBeforeFill: Boolean;
    BaselineShift: Single;
    DominantBaseline: TPixieSvgDominantBaseline;
    MarkerStart: string;
    MarkerMid: string;
    MarkerEnd: string;
  end;

  { TPixieSvgGradientStop }

  TPixieSvgGradientStop = record
    Offset: Single;
    Color: TPixieWebColor;
  end;

  TPixieSvgGradientStopList = TList<TPixieSvgGradientStop>;

  TPixieSvgSpread = (smPad, smRepeat, smReflect);

  { TPixieSvgGradient }

  TPixieSvgGradient = class
  public
    Id: string;
    IsRadial: Boolean;
    X1, Y1, X2, Y2: Single;
    CX, CY, R, FX, FY: Single;
    Stops: TPixieSvgGradientStopList;
    UserSpaceUnits: Boolean;
    HrefId: string;
    GradientTransform: string;
    HasUnits: Boolean;
    HasCoords: Boolean;
    HasTransform: Boolean;
    Spread: TPixieSvgSpread;
    HasSpread: Boolean;
    constructor Create;
    destructor Destroy; override;
  end;

  TPixieSvgGradientMap = TObjectDictionary<string, TPixieSvgGradient>;

  { TPixieSvgPatternInfo - resolved attributes of a <pattern> element }

  TPixieSvgPatternInfo = record
    ImageHref: string;
    // Tile rectangle in pattern's own coordinate system (before applying units).
    // When PatternUnitsUserSpace=False these are fractions of the bbox;
    // otherwise they are user-space units.
    X, Y, Width, Height: Single;
    // Pattern viewBox (if present) — maps content coordinates into the tile
    HasViewBox: Boolean;
    ViewBoxX, ViewBoxY, ViewBoxW, ViewBoxH: Single;
    // Image child element position and size (in pattern content space)
    ImgX, ImgY, ImgW, ImgH: Single;
    // Units flags
    PatternUnitsUserSpace: Boolean;   // default False (objectBoundingBox)
    ContentUnitsObjectBBox: Boolean;  // default False (userSpaceOnUse)
    // Content node for subtree rendering (the pattern element with children)
    PatternNode: Pointer;
    HasChildren: Boolean;
    HasPatternTransform: Boolean;
    PatternTransform: TPixieSvgMatrix;
    procedure Init;
  end;

  { TPixieSvgPathCmd - tokenised path command }

  TPixieSvgPathCmd = record
    Cmd: AnsiChar;
    Args: TPixieSingleArray;
  end;

  TPixieSvgPathCmdList = TList<TPixieSvgPathCmd>;

  { TPixieSvgPathStats - geometry summary of a path for marker placement }

  TPixieSvgPathStats = record
    StartX, StartY: Single;             // path origin (first moveto target)
    EndX, EndY: Single;                 // current point after last command
    FirstSegEndX, FirstSegEndY: Single; // start tangent direction (CP1 for curves, endpoint for lines)
    LastSegStartX, LastSegStartY: Single; // end tangent direction (CP2 for curves, startpoint for lines)
    HasSegment: Boolean;
  end;

  { TPixieSvgRendererBase - abstract SVG renderer }

  TPixieSvgIdMap = TDictionary<string, Pointer>;
  TPixieSvgStyleMap = TDictionary<string, string>;
  TPixieSvgPatternInfoMap = TDictionary<string, TPixieSvgPatternInfo>;
  TPixieSvgRendererBase = class
  protected
    FDoc: TObject;
    FSvgRoot: Pointer;
    FInitState: TPixieSvgState;
    FViewBoxX, FViewBoxY, FViewBoxW, FViewBoxH: Single;
    FHasExplicitSize: Boolean;
    FOverflowVisible: Boolean;
    FGradients: TPixieSvgGradientMap;
    FPatternInfos: TPixieSvgPatternInfoMap;
    FIdMap: TPixieSvgIdMap;
    FStyleMap: TPixieSvgStyleMap;
    // Scratch dictionary reused by InheritState across every element of
    // a render walk; cleared and re-filled per element instead of
    // allocating a fresh dict each time.
    FInlineStyleMap: TPixieSvgStyleMap;
    FUseDepth: Integer;
    FSystemLanguage: string;
    // SVG 2 context paint (set while rendering marker children so
    // fill:context-stroke / fill:context-fill resolve to the referencing
    // element's paint)
    FContextFillColor: TPixieWebColor;
    FContextStrokeColor: TPixieWebColor;
    FHasContextFill: Boolean;
    FHasContextStroke: Boolean;
  protected
    // Abstract drawing primitives — subclasses override these
    procedure DoMoveTo(X, Y: Single); virtual; abstract;
    procedure DoLineTo(X, Y: Single); virtual; abstract;
    procedure DoCurveTo(X1, Y1, X2, Y2, X3, Y3: Single); virtual; abstract;
    procedure DoClosePath; virtual; abstract;
    procedure DoSaveState; virtual; abstract;
    procedure DoRestoreState; virtual; abstract;
    procedure DoSetTransform(const M: TPixieSvgMatrix); virtual; abstract;
    procedure DoFillAndStroke(const State: TPixieSvgState); virtual; abstract;
    procedure DoBeginOpacity(Opacity: Single); virtual; abstract;
    procedure DoEndOpacity; virtual; abstract;
    procedure DoClipPath(EvenOdd: Boolean); virtual; abstract;
    procedure DoBeginMask(const MaskImageHref: string;
      MaskX, MaskY, MaskW, MaskH: Single); virtual; abstract;
    procedure DoEndMask; virtual; abstract;
    procedure DoDrawText(const Text: string; X, Y: Single;
      const State: TPixieSvgState); virtual;
    procedure DoRenderTextRun(const Text: string; X, Y: Single;
      const State: TPixieSvgState); virtual;
    function DoMeasureTextRun(const Text: string;
      const State: TPixieSvgState): Single; virtual; abstract;
    procedure DoDrawImage(const Href: string;
      X, Y, W, H: Single); virtual;
    procedure DoClearImages; virtual;

    // Attribute parsing
    function GetAttr(Node: Pointer; const Name: string;
      const Default: string = ''): string;
    function GetHref(Node: Pointer): string;
    function ParseSvgFloat(const S: string): Single;
    function TryParseSvgFloat(const S: string; out Value: Single): Boolean;
    function ParseSvgLengthEm(const S: string; FontSize: Single): Single;
    function IsFontRelativeLength(const S: string): Boolean;
    procedure ParseViewBox(const S: string;
      out VbX, VbY, VbW, VbH: Single);
    function ParseSvgColor(const S: string;
      out Color: TPixieWebColor): Boolean;
    function ParseStyleAttribute(
      const StyleStr, PropName: string): string;
    function BuildStyleMap(const StyleStr: string): TPixieSvgStyleMap;
    procedure PopulateStyleMap(Map: TPixieSvgStyleMap;
      const StyleStr: string);
    function StyleVal(Map: TPixieSvgStyleMap; const Key: string): string;
    function ResolveNodeStyle(Node: Pointer): string;
    function InheritState(Node: Pointer;
      const ParentState: TPixieSvgState): TPixieSvgState;
    procedure ParseFontShorthand(const S: string;
      var State: TPixieSvgState);
    function NormalizeFontFamily(const S: string): string;
    function ParseTransform(const S: string): TPixieSvgMatrix;
    function ParseDashArray(const S: string): TPixieSingleArray;

    // Path data parsing
    function ParsePathData(const D: string): TPixieSvgPathCmdList;
    procedure EmitPathCommands(Cmds: TPixieSvgPathCmdList);
    procedure ComputePathStats(Cmds: TPixieSvgPathCmdList;
      out Stats: TPixieSvgPathStats);
    procedure ArcToBezier(X1, Y1, RX, RY, XRotation: Single;
      LargeArc, Sweep: Boolean; X2, Y2: Single);

    // Shape helpers
    procedure EmitBezierEllipse(CX, CY, RX, RY: Single);
    procedure ApplyNodeTransform(Node: Pointer);
    procedure ApplyOpacity(const State: TPixieSvgState;
      out NeedRestore: Boolean);
    procedure EmitShapeGeometry(Node: Pointer;
      const XForm: TPixieSvgMatrix);
    procedure ApplyClipPath(Node: Pointer);
    procedure ApplyMask(Node: Pointer; out NeedMaskRestore: Boolean);

    // CSS <style> support
    procedure ParseStyleElement(const CSS: string);

    // Gradient support
    procedure CollectDefs(Node: Pointer);
    procedure CollectAllGradients(Node: Pointer);
    procedure ParseGradient(Node: Pointer; IsRadial: Boolean);
    function ResolveGradientStops(const Id: string): TPixieSvgGradient;
    class function ExtractUrlId(const S: string): string; static;

    // Pattern/image helpers
    function IsPatternFill(const Id: string): Boolean;
    function ResolvePatternImageHref(const PatternId: string): string;
    function GetPatternInfo(const PatternId: string;
      out Info: TPixieSvgPatternInfo): Boolean;
    function FindImageElement(Node: Pointer; Depth: Integer): Pointer;

    // ID map for <use> element lookup
    procedure BuildIdMap(Node: Pointer);

    // Shape renderers (call abstract drawing primitives)
    procedure RenderElement(Node: Pointer; const State: TPixieSvgState);
    procedure RenderGroup(Node: Pointer; const State: TPixieSvgState);
    procedure RenderSwitch(Node: Pointer; const State: TPixieSvgState);
    procedure RenderNestedSvg(Node: Pointer; const State: TPixieSvgState);
    procedure RenderUse(Node: Pointer; const State: TPixieSvgState);
    procedure RenderRect(Node: Pointer; const State: TPixieSvgState);
    procedure RenderCircle(Node: Pointer; const State: TPixieSvgState);
    procedure RenderEllipse(Node: Pointer; const State: TPixieSvgState);
    procedure RenderLine(Node: Pointer; const State: TPixieSvgState);
    procedure RenderPolyline(Node: Pointer; const State: TPixieSvgState;
      ClosePath: Boolean);
    procedure RenderPath(Node: Pointer; const State: TPixieSvgState);
    procedure RenderText(Node: Pointer;
      const State: TPixieSvgState); virtual;
    function CollectAllText(Node: Pointer): string;
    function NormalizeTextNode(const Raw: string;
      Preserve: Boolean): string;
    procedure RenderTextChunk(Node: Pointer;
      const State: TPixieSvgState; var X, Y: Single);
    procedure RenderTextChunkContents(Node: Pointer;
      const State: TPixieSvgState; var X, Y: Single);
    procedure RenderTextPositioned(Node: Pointer;
      const State: TPixieSvgState;
      const XPositions, YPositions: TPixieSingleArray;
      DxOffset, DyOffset: Single; var X, Y: Single);
    function MeasureTextChunkWidth(Node: Pointer;
      const State: TPixieSvgState): Single;
    function ParseSvgFloatList(const S: string): TPixieSingleArray;
    procedure RenderImage(Node: Pointer;
      const State: TPixieSvgState);
    procedure RenderMarkerAt(const MarkerId: string;
      X, Y, Angle, StrokeW: Single; const State: TPixieSvgState;
      IsStart: Boolean = False);
    procedure RenderMarkers(Node: Pointer; const State: TPixieSvgState;
      X1, Y1, X2, Y2, Angle1, Angle2: Single);
  public
    destructor Destroy; override;

    // Parse SVG XML, extract dimensions. Call RenderDocument after setup.
    function ParseSvg(Data: Pointer; Size: Integer;
      out W, H: Single): Boolean;
    // True when the SVG root element specified explicit width AND height
    // attributes (i.e. has a natural size). False when only viewBox is
    // present, indicating an aspect-ratio-only image. Valid after ParseSvg.
    function HasExplicitSize: Boolean;
    // Returns the SVG's natural aspect ratio (viewBox width / viewBox
    // height, or W / H if no viewBox), or 0 when neither is available.
    function GetAspectRatio: Single;
    // Override viewport dimensions (call after ParseSvg, before rendering)
    procedure SetViewport(AWidth, AHeight: Single);
    // Set the initial CSS 'color' property for currentColor resolution
    // (call after ParseSvg, before rendering).
    procedure SetCurrentColor(AColor: TPixieWebColor);
    // Render the parsed document by walking the SVG tree.
    procedure RenderDocument;
    // Free the parsed document.
    procedure ClearDocument; virtual;
  end;

implementation

uses
  Math, Pixie.SimpleXml, Pixie.Utf8, Pixie.Utils;

const
  Kappa: Single = 0.5522847498;



// Locale-independent float parse (Val uses '.' regardless of locale)
function SvgStrToFloat(const S: string): Single;
var
  Code: Integer;
begin
  Val(S, Result, Code);
  if Code <> 0 then
    Result := 0;
end;

// ===========================================================================
// DOCTYPE entity expansion
// ===========================================================================

// Operates on raw UTF-8 bytes (AnsiString) so no code-page conversion
// happens — Delphi's UnicodeString SetString with PAnsiChar would otherwise
// interpret the bytes as the system code page (CP1252 on Windows), corrupting
// any non-ASCII content like en dashes or bullets.
procedure ExpandDoctypeEntities(var S: AnsiString; DtdStart, DtdEnd: Integer);
var
  Subset, EntName, EntValue, Marker: AnsiString;
  BracketStart, BracketEnd: Integer;
  P, Q, ValStart, ValEnd, PMatch: Integer;
  QuoteCh: AnsiChar;
begin
  // Find internal subset between [ and ]
  BracketStart := Pos(AnsiString('['), S, DtdStart);
  if (BracketStart = 0) or (BracketStart > DtdEnd) then Exit;
  BracketEnd := Pos(AnsiString(']'), S, BracketStart);
  if (BracketEnd = 0) or (BracketEnd > DtdEnd) then Exit;

  Subset := Copy(S, BracketStart + 1, BracketEnd - BracketStart - 1);

  // Parse <!ENTITY Name "Value"> declarations and expand &Name; in body
  P := 1;
  while P < Length(Subset) do
  begin
    P := Pos(AnsiString('<!ENTITY'), Subset, P);
    if P = 0 then Break;
    Inc(P, 8);

    // Skip whitespace
    while (P <= Length(Subset)) and (Subset[P] <= ' ') do Inc(P);

    // Read entity name
    Q := P;
    while (Q <= Length(Subset)) and (Subset[Q] > ' ') and
          (Subset[Q] <> '"') and (Subset[Q] <> '''') do Inc(Q);
    EntName := Copy(Subset, P, Q - P);
    P := Q;

    // Skip whitespace
    while (P <= Length(Subset)) and (Subset[P] <= ' ') do Inc(P);
    if P > Length(Subset) then Break;

    // Read quoted value
    QuoteCh := Subset[P];
    if (QuoteCh <> '"') and (QuoteCh <> '''') then
    begin
      Inc(P);
      Continue;
    end;
    Inc(P);
    ValStart := P;
    while (P <= Length(Subset)) and (Subset[P] <> QuoteCh) do Inc(P);
    ValEnd := P;
    EntValue := Copy(Subset, ValStart, ValEnd - ValStart);
    Inc(P);

    // Expand &Name; references in the document body (after DOCTYPE).
    // Inlined byte-level replace — Delphi's StringReplace is UnicodeString
    // only, and going through UnicodeString would interpret the UTF-8 bytes
    // as the system code page and corrupt non-ASCII content.
    if EntName <> '' then
    begin
      Marker := AnsiString('&') + EntName + AnsiString(';');
      PMatch := Pos(Marker, S);
      while PMatch > 0 do
      begin
        Delete(S, PMatch, Length(Marker));
        Insert(EntValue, S, PMatch);
        PMatch := Pos(Marker, S, PMatch + Length(EntValue));
      end;
    end;
  end;
end;

// ===========================================================================
// TPixieSvgMatrix
// ===========================================================================

// ===========================================================================
// TPixieSvgGradient
// ===========================================================================

constructor TPixieSvgGradient.Create;
begin
  inherited Create;
  Stops := TPixieSvgGradientStopList.Create;
  // Linear defaults (left to right in objectBoundingBox)
  X1 := 0; Y1 := 0; X2 := 1; Y2 := 0;
  // Radial defaults
  CX := 0.5; CY := 0.5; R := 0.5; FX := -1; FY := -1;
  UserSpaceUnits := False;
  Spread := smPad;
  HasSpread := False;
end;

destructor TPixieSvgGradient.Destroy;
begin
  Stops.Free;
  inherited;
end;

// ===========================================================================
// TPixieSvgRendererBase — lifecycle
// ===========================================================================

destructor TPixieSvgRendererBase.Destroy;
begin
  ClearDocument;
  FreeAndNil(FInlineStyleMap);
  inherited;
end;

procedure TPixieSvgRendererBase.ClearDocument;
begin
  DoClearImages;
  FreeAndNil(FGradients);
  FreeAndNil(FPatternInfos);
  FreeAndNil(FIdMap);
  FreeAndNil(FStyleMap);
  if FDoc <> nil then
  begin
    FDoc.Free;
    FDoc := nil;
  end;
  FSvgRoot := nil;
end;

// ===========================================================================
// Default DoDrawText — no-op, override in subclasses
// ===========================================================================

procedure TPixieSvgRendererBase.DoDrawText(const Text: string;
  X, Y: Single; const State: TPixieSvgState);
begin
  // no-op — override in subclass for text rendering
end;

procedure TPixieSvgRendererBase.DoRenderTextRun(const Text: string;
  X, Y: Single; const State: TPixieSvgState);
begin
  DoDrawText(Text, X, Y, State);
end;

procedure TPixieSvgRendererBase.DoDrawImage(const Href: string;
  X, Y, W, H: Single);
begin
  // no-op — override in subclass for image rendering
end;

procedure TPixieSvgRendererBase.DoClearImages;
begin
  // no-op — override in subclass to free cached images
end;

// ===========================================================================
// Attribute parsing
// ===========================================================================

function TPixieSvgRendererBase.GetAttr(Node: Pointer; const Name: string;
  const Default: string): string;
begin
  if Node = nil then
    Result := Default
  else
  begin
    Result := TDOMElement(Node).GetAttributeStr(Name);
    if Result = '' then
      Result := Default;
  end;
end;

function TPixieSvgRendererBase.GetHref(Node: Pointer): string;
begin
  Result := GetAttr(Node, 'href');
end;

function TPixieSvgRendererBase.ParseSvgFloat(const S: string): Single;
var
  Trimmed, Suffix: string;
  Code, Len: Integer;
  Scale: Single;
begin
  Result := 0;
  Trimmed := Trim(S);
  if Trimmed = '' then Exit;

  // Handle percentage suffix (e.g. "50%" → 0.5)
  Len := Length(Trimmed);
  if (Len > 1) and (Trimmed[Len] = '%') then
  begin
    Trimmed := Copy(Trimmed, 1, Len - 1);
    Val(Trimmed, Result, Code);
    if Code = 0 then
      Result := Result / 100.0;
    Exit;
  end;

  // Detect and strip unit suffix, apply conversion factor
  // SVG default is px (user units); 1in=96px, 1cm=96/2.54, 1mm=96/25.4, 1pt=96/72
  Scale := 1.0;
  // Check 3-char 'rem' before 2-char suffixes so the 'em' tail doesn't win
  if (Len >= 3) and (Copy(Trimmed, Len - 2, 3) = 'rem') then
    Trimmed := Copy(Trimmed, 1, Len - 3)
  else if Len > 2 then
  begin
    Suffix := Copy(Trimmed, Len - 1, 2);
    if Suffix = 'px' then
      Trimmed := Copy(Trimmed, 1, Len - 2)
    else if Suffix = 'cm' then
    begin
      Trimmed := Copy(Trimmed, 1, Len - 2);
      Scale := 96.0 / 2.54;
    end
    else if Suffix = 'mm' then
    begin
      Trimmed := Copy(Trimmed, 1, Len - 2);
      Scale := 96.0 / 25.4;
    end
    else if Suffix = 'in' then
    begin
      Trimmed := Copy(Trimmed, 1, Len - 2);
      Scale := 96.0;
    end
    else if Suffix = 'pt' then
    begin
      Trimmed := Copy(Trimmed, 1, Len - 2);
      Scale := 96.0 / 72.0;
    end
    else if Suffix = 'pc' then
    begin
      Trimmed := Copy(Trimmed, 1, Len - 2);
      Scale := 96.0 / 6.0;
    end
    else if Suffix = 'em' then
      Trimmed := Copy(Trimmed, 1, Len - 2);
  end;

  Val(Trimmed, Result, Code);
  if Code = 0 then
    Result := Result * Scale;
end;

// Like ParseSvgFloat but returns False for non-numeric values like "null"
function TPixieSvgRendererBase.TryParseSvgFloat(const S: string;
  out Value: Single): Boolean;
var
  P, Len: Integer;
begin
  Value := 0;
  Len := Length(S);
  P := 1;
  while (P <= Len) and (S[P] <= ' ') do Inc(P);
  Result := (P <= Len) and CharInSet(S[P], ['0'..'9', '.', '-', '+']);
  if Result then
    Value := ParseSvgFloat(S);
end;

// Returns ParseSvgFloat(S) * FontSize for em/rem/% lengths, plain
// ParseSvgFloat(S) otherwise. "1em" means one font size, not literal 1.
function TPixieSvgRendererBase.ParseSvgLengthEm(const S: string;
  FontSize: Single): Single;
begin
  if IsFontRelativeLength(S) then
    Result := FontSize * ParseSvgFloat(S)
  else
    Result := ParseSvgFloat(S);
end;

// True when the length string ends in em, rem, or %. Scans S directly
// (no allocation) since this runs per-text-node on every render.
function TPixieSvgRendererBase.IsFontRelativeLength(const S: string): Boolean;
var
  Last: Integer;
begin
  Result := False;
  Last := Length(S);
  while (Last > 0) and (S[Last] <= ' ') do Dec(Last);
  if Last = 0 then Exit;
  if S[Last] = '%' then
  begin
    Result := True;
    Exit;
  end;
  // 'em' suffix (covers 'rem' too — we don't distinguish root em)
  if (Last >= 2) and CharInSet(S[Last], ['m', 'M'])
                 and CharInSet(S[Last - 1], ['e', 'E']) then
    Result := True;
end;

// Parses an SVG "viewBox" attribute value ("x y w h", any combination of
// space/comma/tab separators) into its four components. Missing or
// unparseable components come back as 0.
procedure TPixieSvgRendererBase.ParseViewBox(const S: string;
  out VbX, VbY, VbW, VbH: Single);
var
  Parts: array[0..3] of string;
  P, Idx: Integer;
begin
  VbX := 0; VbY := 0; VbW := 0; VbH := 0;
  if S = '' then Exit;
  for Idx := 0 to 3 do Parts[Idx] := '';
  P := 1; Idx := 0;
  while (P <= Length(S)) and (Idx <= 3) do
  begin
    while (P <= Length(S)) and CharInSet(S[P], [' ', ',', #9]) do Inc(P);
    while (P <= Length(S)) and not CharInSet(S[P], [' ', ',', #9]) do
    begin
      Parts[Idx] := Parts[Idx] + S[P];
      Inc(P);
    end;
    Inc(Idx);
  end;
  VbX := ParseSvgFloat(Parts[0]);
  VbY := ParseSvgFloat(Parts[1]);
  VbW := ParseSvgFloat(Parts[2]);
  VbH := ParseSvgFloat(Parts[3]);
end;

function TPixieSvgRendererBase.ParseDashArray(
  const S: string): TPixieSingleArray;
var
  I, Count: Integer;
begin
  Result := ParseSvgFloatList(S);
  Count := Length(Result);
  // SVG spec: negative values invalidate the entire dash array
  for I := 0 to Count - 1 do
    if Result[I] < 0 then
    begin
      SetLength(Result, 0);
      Exit;
    end;
  // SVG spec: odd-length dash arrays are repeated to make even length
  if (Count > 0) and (Count mod 2 = 1) then
  begin
    SetLength(Result, Count * 2);
    Move(Result[0], Result[Count], Count * SizeOf(Single));
  end;
end;

// Parses a space/comma-separated list of floats (for per-character x/y
// positioning in SVG text elements). Unlike ParseDashArray, negative
// values are preserved since they are valid coordinates.
function TPixieSvgRendererBase.ParseSvgFloatList(
  const S: string): TPixieSingleArray;
var
  P, Len, Count: Integer;
  NumStr: ShortString;
begin
  SetLength(Result, 0);
  Count := 0;
  P := 1;
  Len := Length(S);
  while P <= Len do
  begin
    while (P <= Len) and CharInSet(S[P], [' ', ',', #9, #10, #13]) do Inc(P);
    if P > Len then Break;
    NumStr := '';
    if (P <= Len) and CharInSet(S[P], ['-', '+']) then
    begin
      NumStr := NumStr + AnsiChar(S[P]);
      Inc(P);
    end;
    while (P <= Len) and CharInSet(S[P], ['0'..'9', '.']) do
    begin
      NumStr := NumStr + AnsiChar(S[P]);
      Inc(P);
    end;
    if NumStr <> '' then
    begin
      if Count >= Length(Result) then
        SetLength(Result, Length(Result) + 8);
      Result[Count] := SvgStrToFloat(string(NumStr));
      Inc(Count);
    end
    else
      // Skip any non-numeric character (e.g. stroke-dasharray="null")
      Inc(P);
  end;
  SetLength(Result, Count);
end;

function TPixieSvgRendererBase.ParseSvgColor(const S: string;
  out Color: TPixieWebColor): Boolean;
var
  Trimmed, Lower: string;
  P, ParenStart, Depth: Integer;
  Vals: array[0..3] of Single;
  ValCount: Integer;
  NumStr: ShortString;
  AlphaIsPercent: Boolean;
  Fallback: string;
begin
  Trimmed := Trim(S);
  if (Trimmed = '') or (Trimmed = 'none') then
  begin
    Result := False;
    Exit;
  end;

  // Resolve var() — extract fallback value (handles nesting)
  Lower := LowerCase(Trimmed);
  while Pos('var(', Lower) = 1 do
  begin
    // Find the comma separating property name from fallback
    P := 5; // after 'var('
    Depth := 1;
    while (P <= Length(Trimmed)) and (Depth > 0) do
    begin
      if Trimmed[P] = '(' then Inc(Depth)
      else if Trimmed[P] = ')' then Dec(Depth)
      else if (Trimmed[P] = ',') and (Depth = 1) then Break;
      Inc(P);
    end;
    if (P > Length(Trimmed)) or (Trimmed[P] <> ',') then
    begin
      // No fallback — cannot resolve
      Exit(False);
    end;
    // Extract fallback, strip outer closing paren
    Fallback := Trim(Copy(Trimmed, P + 1, Length(Trimmed) - P));
    if (Length(Fallback) > 0) and (Fallback[Length(Fallback)] = ')') then
      Fallback := Trim(Copy(Fallback, 1, Length(Fallback) - 1));
    Trimmed := Fallback;
    Lower := LowerCase(Trimmed);
  end;

  if (Trimmed = '') or (Trimmed = 'none') then
    Exit(False);

  // Try rgb()/rgba() first
  if (Pos('rgb(', Lower) = 1) or (Pos('rgba(', Lower) = 1) then
  begin
    ParenStart := Pos('(', Trimmed);
    if ParenStart = 0 then Exit(False);
    P := ParenStart + 1;
    ValCount := 0;
    AlphaIsPercent := False;
    while (P <= Length(Trimmed)) and (ValCount < 4) do
    begin
      while (P <= Length(Trimmed)) and
            CharInSet(Trimmed[P], [' ', ',', '/', #9]) do Inc(P);
      if (P > Length(Trimmed)) or (Trimmed[P] = ')') then Break;

      NumStr := '';
      while (P <= Length(Trimmed)) and
            CharInSet(Trimmed[P], ['0'..'9', '.', '-']) do
      begin
        NumStr := NumStr + AnsiChar(Trimmed[P]);
        Inc(P);
      end;
      if NumStr = '' then Break;

      Vals[ValCount] := SvgStrToFloat(string(NumStr));
      if (P <= Length(Trimmed)) and (Trimmed[P] = '%') then
      begin
        if ValCount < 3 then
          Vals[ValCount] := Vals[ValCount] * 255 / 100
        else
          AlphaIsPercent := True;
        Inc(P);
      end;
      Inc(ValCount);
    end;

    if ValCount >= 3 then
    begin
      Color := TPixieWebColor.Create(
        EnsureRange(Round(Vals[0]), 0, 255),
        EnsureRange(Round(Vals[1]), 0, 255),
        EnsureRange(Round(Vals[2]), 0, 255));
      if ValCount >= 4 then
      begin
        if AlphaIsPercent then
          Color.Alpha := EnsureRange(Round(Vals[3] * 255 / 100), 0, 255)
        else
          Color.Alpha := EnsureRange(Round(Vals[3] * 255), 0, 255);
      end;
      Exit(True);
    end;
    Exit(False);
  end;

  Result := PixieParseColorString(Trimmed, Color);
end;

procedure TPixieSvgRendererBase.ParseStyleElement(const CSS: string);
var
  P, I, Len, SelStart, BraceStart, BraceEnd: Integer;
  Declarations, KeySel, Existing, Sel: string;
  Selectors: TPixieStringVector;
  SpacePos, DotPos: Integer;

  procedure MergeStyle(const Key, Decl: string);
  begin
    if FStyleMap.TryGetValue(Key, Existing) then
      FStyleMap.AddOrSetValue(Key, Existing + ';' + Decl)
    else
      FStyleMap.Add(Key, Decl);
  end;

  procedure ProcessSelector(const Sel: string);
  begin
    // Extract key selector (last whitespace-delimited segment)
    // e.g. "svg.railroad-diagram path" -> "path"
    SpacePos := Length(Sel);
    while (SpacePos > 0) and (Sel[SpacePos] <> ' ') do Dec(SpacePos);
    if SpacePos > 0 then
      KeySel := Copy(Sel, SpacePos + 1, MaxInt)
    else
      KeySel := Sel;

    if KeySel = '' then Exit;

    if KeySel[1] = '.' then
    begin
      if Length(KeySel) > 1 then
        MergeStyle(LowerCase(Copy(KeySel, 2, MaxInt)), Declarations);
    end
    else
    begin
      DotPos := Pos('.', KeySel);
      if DotPos > 1 then
        MergeStyle('@' + LowerCase(KeySel), Declarations)
      else if CharInSet(KeySel[1], ['A'..'Z', 'a'..'z']) then
        MergeStyle('@' + LowerCase(KeySel), Declarations);
    end;
  end;

begin
  if FStyleMap = nil then
    FStyleMap := TPixieSvgStyleMap.Create;

  Selectors := TPixieStringVector.Create;
  try
    P := 1;
    Len := Length(CSS);
    while P <= Len do
    begin
      // Skip whitespace and comments
      while (P <= Len) and (CSS[P] <= ' ') do Inc(P);
      if (P < Len) and (CSS[P] = '/') and (CSS[P + 1] = '*') then
      begin
        Inc(P, 2);
        while (P < Len) and not ((CSS[P] = '*') and (CSS[P + 1] = '/')) do Inc(P);
        Inc(P, 2);
        Continue;
      end;
      if P > Len then Break;

      // Read selector(s) up to '{'
      SelStart := P;
      BraceStart := P;
      while (BraceStart <= Len) and (CSS[BraceStart] <> '{') do Inc(BraceStart);
      if BraceStart > Len then Break;

      // Read declarations up to '}'
      BraceEnd := BraceStart + 1;
      while (BraceEnd <= Len) and (CSS[BraceEnd] <> '}') do Inc(BraceEnd);
      if BraceEnd > Len then Break;
      Declarations := Trim(Copy(CSS, BraceStart + 1, BraceEnd - BraceStart - 1));
      P := BraceEnd + 1;

      if Declarations = '' then Continue;

      // Split comma-separated selector list and process each
      Selectors.Clear;
      PixieSplitString(Trim(Copy(CSS, SelStart, BraceStart - SelStart)), Selectors, ',');
      for I := 0 to Selectors.Count - 1 do
      begin
        Sel := Trim(Selectors[I]);
        if Sel <> '' then
          ProcessSelector(Sel);
      end;
    end;
  finally
    Selectors.Free;
  end;
end;

function TPixieSvgRendererBase.ParseStyleAttribute(
  const StyleStr, PropName: string): string;
var
  Props: string;
  P, SemiPos, ColonPos: Integer;
  Key, Value: string;
begin
  Result := '';
  Props := StyleStr;
  P := 1;
  while P <= Length(Props) do
  begin
    SemiPos := Pos(';', Props, P);
    if SemiPos = 0 then
      SemiPos := Length(Props) + 1;

    Key := Trim(Copy(Props, P, SemiPos - P));
    ColonPos := Pos(':', Key);
    if ColonPos > 0 then
    begin
      Value := Trim(Copy(Key, ColonPos + 1, MaxInt));
      Key := Trim(Copy(Key, 1, ColonPos - 1));
      if LowerCase(Key) = LowerCase(PropName) then
        Result := Value;
    end;
    P := SemiPos + 1;
  end;
end;

function TPixieSvgRendererBase.StyleVal(Map: TPixieSvgStyleMap;
  const Key: string): string;
begin
  if not Map.TryGetValue(Key, Result) then
    Result := '';
end;

function TPixieSvgRendererBase.BuildStyleMap(
  const StyleStr: string): TPixieSvgStyleMap;
begin
  Result := TPixieSvgStyleMap.Create;
  PopulateStyleMap(Result, StyleStr);
end;

procedure TPixieSvgRendererBase.PopulateStyleMap(Map: TPixieSvgStyleMap;
  const StyleStr: string);
var
  P, SemiPos, ColonPos: Integer;
  Decl, Key, Value: string;
begin
  P := 1;
  while P <= Length(StyleStr) do
  begin
    SemiPos := Pos(';', StyleStr, P);
    if SemiPos = 0 then
      SemiPos := Length(StyleStr) + 1;

    Decl := Trim(Copy(StyleStr, P, SemiPos - P));
    ColonPos := Pos(':', Decl);
    if ColonPos > 0 then
    begin
      // Trim already applied to Decl; the two halves are sub-ranges so
      // only the inside-facing edges can have whitespace.
      Key := LowerCase(TrimRight(Copy(Decl, 1, ColonPos - 1)));
      Value := TrimLeft(Copy(Decl, ColonPos + 1, MaxInt));
      Map.AddOrSetValue(Key, Value);
    end;
    P := SemiPos + 1;
  end;
end;

// Builds the effective style string for a node by merging, in order:
//   1. Type selector (@tag)
//   2. Class selectors (.className) in order of appearance
//   3. Type.class selectors (@tag.className)
//   4. Inline style="..." attribute
// Returns a single ';'-joined string suitable for ParseStyleAttribute.
function TPixieSvgRendererBase.ResolveNodeStyle(Node: Pointer): string;
var
  ClassStr, ClassDecl, InlineStyleStr, NodeTag, ClassName: string;
  SpacePos: Integer;
begin
  Result := '';

  // Resolve styles from <style> element: type selectors, class, type.class
  if FStyleMap <> nil then
  begin
    NodeTag := LowerCase(PixieDomToStr(TDOMElement(Node).TagName));

    // Type selector: @tag (lowest specificity)
    if (NodeTag <> '') and FStyleMap.TryGetValue('@' + NodeTag, ClassDecl) then
      Result := ClassDecl;

    ClassStr := GetAttr(Node, 'class');
    if ClassStr <> '' then
    begin
      // Support space-separated class lists: class="st0 st1 st2"
      while ClassStr <> '' do
      begin
        SpacePos := Pos(' ', ClassStr);
        if SpacePos > 0 then
        begin
          ClassName := Copy(ClassStr, 1, SpacePos - 1);
          ClassStr := TrimLeft(Copy(ClassStr, SpacePos + 1, MaxInt));
        end
        else
        begin
          ClassName := ClassStr;
          ClassStr := '';
        end;
        if ClassName = '' then Continue;

        // Class selector: .className
        if FStyleMap.TryGetValue(LowerCase(ClassName), ClassDecl) then
        begin
          if Result <> '' then
            Result := Result + ';' + ClassDecl
          else
            Result := ClassDecl;
        end;

        // Type.class selector: @tag.className (higher specificity)
        if (NodeTag <> '') and
           FStyleMap.TryGetValue('@' + NodeTag + '.' + LowerCase(ClassName), ClassDecl) then
        begin
          if Result <> '' then
            Result := Result + ';' + ClassDecl
          else
            Result := ClassDecl;
        end;
      end;
    end;
  end;

  // Inline style attribute overrides class styles
  InlineStyleStr := GetAttr(Node, 'style');
  if InlineStyleStr <> '' then
  begin
    if Result <> '' then
      Result := Result + ';' + InlineStyleStr
    else
      Result := InlineStyleStr;
  end;
end;

function TPixieSvgRendererBase.InheritState(Node: Pointer;
  const ParentState: TPixieSvgState): TPixieSvgState;
var
  FillStr, StrokeStr, StrokeWStr, OpacStr: string;
  FillOpStr, StrokeOpStr, ColorStr: string;
  FontFamilyStr, FontSizeStr, FontWeightStr, FontStyleStr, FontShorthand: string;
  LetterSpacingStr, TextDecStr, BaselineShiftStr, DomBaselineStr: string;
  LineCapStr, LineJoinStr: string;
  DashArrayStr, DashOffsetStr: string;
  AnchorStr, MarkerStr: string;
  Pos1, Pos2: Integer;
  V: Single;
  Color: TPixieWebColor;
begin
  Result := ParentState;

  // Parse the inline style string once into a key->value map so the ~30
  // property lookups below are O(1) each. The map is reused across every
  // element by clearing rather than reallocating per call.
  if FInlineStyleMap = nil then
    FInlineStyleMap := TPixieSvgStyleMap.Create
  else
    FInlineStyleMap.Clear;
  PopulateStyleMap(FInlineStyleMap, ResolveNodeStyle(Node));

  // CSS color property (resolve before fill/stroke for currentColor)
  // Inline style takes priority over presentation attributes per SVG/CSS spec
  ColorStr := StyleVal(FInlineStyleMap, 'color');
  if ColorStr = '' then
    ColorStr := GetAttr(Node, 'color');
  if (ColorStr <> '') and (ColorStr <> 'inherit') and ParseSvgColor(ColorStr, Color) then
    Result.Color := Color;

  // Fill
  FillStr := StyleVal(FInlineStyleMap, 'fill');
  if FillStr = '' then
    FillStr := GetAttr(Node, 'fill');
  if FillStr <> '' then
  begin
    if FillStr = 'none' then
    begin
      Result.HasFill := False;
      Result.FillGradientId := '';
    end
    else if Pos('url(', LowerCase(FillStr)) > 0 then
    begin
      Result.FillGradientId := ExtractUrlId(FillStr);
      Result.HasFill := True;
    end
    else if SameText(FillStr, 'currentColor') then
    begin
      Result.FillColor := Result.Color;
      Result.HasFill := True;
      Result.FillGradientId := '';
    end
    else if FHasContextStroke and SameText(FillStr, 'context-stroke') then
    begin
      Result.FillColor := FContextStrokeColor;
      Result.HasFill := True;
      Result.FillGradientId := '';
    end
    else if FHasContextFill and SameText(FillStr, 'context-fill') then
    begin
      Result.FillColor := FContextFillColor;
      Result.HasFill := True;
      Result.FillGradientId := '';
    end
    else if (FillStr <> 'inherit') and ParseSvgColor(FillStr, Color) then
    begin
      Result.FillColor := Color;
      Result.HasFill := True;
      Result.FillGradientId := '';
    end;
  end;

  // Stroke
  StrokeStr := StyleVal(FInlineStyleMap, 'stroke');
  if StrokeStr = '' then
    StrokeStr := GetAttr(Node, 'stroke');
  if StrokeStr <> '' then
  begin
    if StrokeStr = 'none' then
    begin
      Result.HasStroke := False;
      Result.StrokeGradientId := '';
    end
    else if Pos('url(', LowerCase(StrokeStr)) > 0 then
    begin
      Result.StrokeGradientId := ExtractUrlId(StrokeStr);
      Result.HasStroke := True;
    end
    else if SameText(StrokeStr, 'currentColor') then
    begin
      Result.StrokeColor := Result.Color;
      Result.HasStroke := True;
      Result.StrokeGradientId := '';
    end
    else if FHasContextStroke and SameText(StrokeStr, 'context-stroke') then
    begin
      Result.StrokeColor := FContextStrokeColor;
      Result.HasStroke := True;
      Result.StrokeGradientId := '';
    end
    else if FHasContextFill and SameText(StrokeStr, 'context-fill') then
    begin
      Result.StrokeColor := FContextFillColor;
      Result.HasStroke := True;
      Result.StrokeGradientId := '';
    end
    else if (StrokeStr <> 'inherit') and ParseSvgColor(StrokeStr, Color) then
    begin
      Result.StrokeColor := Color;
      Result.HasStroke := True;
      Result.StrokeGradientId := '';
    end;
  end;

  // Stroke width
  StrokeWStr := StyleVal(FInlineStyleMap, 'stroke-width');
  if StrokeWStr = '' then
    StrokeWStr := GetAttr(Node, 'stroke-width');
  if TryParseSvgFloat(StrokeWStr, V) then
    Result.StrokeWidth := V;

  // Stroke line cap
  LineCapStr := StyleVal(FInlineStyleMap, 'stroke-linecap');
  if LineCapStr = '' then
    LineCapStr := GetAttr(Node, 'stroke-linecap');
  if LineCapStr = 'round' then
    Result.LineCap := lcRound
  else if LineCapStr = 'square' then
    Result.LineCap := lcSquare
  else if LineCapStr = 'butt' then
    Result.LineCap := lcButt;

  // Stroke line join
  LineJoinStr := StyleVal(FInlineStyleMap, 'stroke-linejoin');
  if LineJoinStr = '' then
    LineJoinStr := GetAttr(Node, 'stroke-linejoin');
  if LineJoinStr = 'round' then
    Result.LineJoin := ljRound
  else if LineJoinStr = 'bevel' then
    Result.LineJoin := ljBevel
  else if LineJoinStr = 'miter' then
    Result.LineJoin := ljMiter;

  // Stroke dash array
  DashArrayStr := StyleVal(FInlineStyleMap, 'stroke-dasharray');
  if DashArrayStr = '' then
    DashArrayStr := GetAttr(Node, 'stroke-dasharray');
  if DashArrayStr <> '' then
  begin
    DashArrayStr := Trim(DashArrayStr);
    if (DashArrayStr = 'none') or (DashArrayStr = 'inherit') then
      SetLength(Result.DashArray, 0)
    else
      Result.DashArray := ParseDashArray(DashArrayStr);
  end;

  // Stroke dash offset
  DashOffsetStr := StyleVal(FInlineStyleMap, 'stroke-dashoffset');
  if DashOffsetStr = '' then
    DashOffsetStr := GetAttr(Node, 'stroke-dashoffset');
  if TryParseSvgFloat(DashOffsetStr, V) then
    Result.DashOffset := V;

  // Opacity (not inherited — each element defaults to 1.0 unless explicitly set)
  Result.Opacity := 1.0;
  OpacStr := StyleVal(FInlineStyleMap, 'opacity');
  if OpacStr = '' then
    OpacStr := GetAttr(Node, 'opacity');
  if TryParseSvgFloat(OpacStr, V) then
    Result.Opacity := V;

  // Fill opacity
  FillOpStr := StyleVal(FInlineStyleMap, 'fill-opacity');
  if FillOpStr = '' then
    FillOpStr := GetAttr(Node, 'fill-opacity');
  if TryParseSvgFloat(FillOpStr, V) then
    Result.FillOpacity := V;

  // Stroke opacity
  StrokeOpStr := StyleVal(FInlineStyleMap, 'stroke-opacity');
  if StrokeOpStr = '' then
    StrokeOpStr := GetAttr(Node, 'stroke-opacity');
  if TryParseSvgFloat(StrokeOpStr, V) then
    Result.StrokeOpacity := V;

  // Font shorthand: font: [style] [weight] size[/line-height] family[, ...]
  // Parsed first so individual properties can override below
  FontShorthand := StyleVal(FInlineStyleMap, 'font');
  if FontShorthand <> '' then
    ParseFontShorthand(FontShorthand, Result);

  // Font family
  FontFamilyStr := StyleVal(FInlineStyleMap, 'font-family');
  if FontFamilyStr = '' then
    FontFamilyStr := GetAttr(Node, 'font-family');
  if FontFamilyStr <> '' then
    Result.FontFamily := NormalizeFontFamily(FontFamilyStr);

  // Font size — em/rem/% resolve against the already-inherited Result.FontSize.
  FontSizeStr := StyleVal(FInlineStyleMap, 'font-size');
  if FontSizeStr = '' then
    FontSizeStr := GetAttr(Node, 'font-size');
  if FontSizeStr <> '' then
    Result.FontSize := ParseSvgLengthEm(FontSizeStr, Result.FontSize);

  // Font weight
  FontWeightStr := StyleVal(FInlineStyleMap, 'font-weight');
  if FontWeightStr = '' then
    FontWeightStr := GetAttr(Node, 'font-weight');
  if FontWeightStr <> '' then
  begin
    if FontWeightStr = 'bold' then
      Result.FontWeight := 700
    else if FontWeightStr = 'normal' then
      Result.FontWeight := 400
    else if TryParseSvgFloat(FontWeightStr, V) then
      Result.FontWeight := Round(V);
  end;

  // Font style
  FontStyleStr := StyleVal(FInlineStyleMap, 'font-style');
  if FontStyleStr = '' then
    FontStyleStr := GetAttr(Node, 'font-style');
  if FontStyleStr <> '' then
    Result.FontItalic := (FontStyleStr = 'italic') or (FontStyleStr = 'oblique');

  // Letter spacing
  LetterSpacingStr := StyleVal(FInlineStyleMap, 'letter-spacing');
  if LetterSpacingStr = '' then
    LetterSpacingStr := GetAttr(Node, 'letter-spacing');
  if LetterSpacingStr <> '' then
  begin
    if LetterSpacingStr = 'normal' then
      Result.LetterSpacing := 0
    else if TryParseSvgFloat(LetterSpacingStr, V) then
      Result.LetterSpacing := V;
  end;

  // Baseline shift (super/sub/percentage/length)
  BaselineShiftStr := StyleVal(FInlineStyleMap, 'baseline-shift');
  if BaselineShiftStr = '' then
    BaselineShiftStr := GetAttr(Node, 'baseline-shift');
  if BaselineShiftStr <> '' then
  begin
    BaselineShiftStr := LowerCase(BaselineShiftStr);
    if BaselineShiftStr = 'super' then
      Result.BaselineShift := -0.4 * Result.FontSize
    else if BaselineShiftStr = 'sub' then
      Result.BaselineShift := 0.2 * Result.FontSize
    else if (Length(BaselineShiftStr) > 1) and
            (BaselineShiftStr[Length(BaselineShiftStr)] = '%') then
      Result.BaselineShift := -ParseSvgFloat(Copy(BaselineShiftStr, 1,
        Length(BaselineShiftStr) - 1)) / 100 * Result.FontSize
    else if BaselineShiftStr <> 'baseline' then
      Result.BaselineShift := -ParseSvgFloat(BaselineShiftStr);
  end;

  // Dominant baseline
  DomBaselineStr := StyleVal(FInlineStyleMap, 'dominant-baseline');
  if DomBaselineStr = '' then
    DomBaselineStr := GetAttr(Node, 'dominant-baseline');
  if DomBaselineStr <> '' then
  begin
    DomBaselineStr := LowerCase(DomBaselineStr);
    if DomBaselineStr = 'hanging' then
      Result.DominantBaseline := dbHanging
    else if DomBaselineStr = 'middle' then
      Result.DominantBaseline := dbMiddle
    else if DomBaselineStr = 'central' then
      Result.DominantBaseline := dbCentral
    else if DomBaselineStr = 'mathematical' then
      Result.DominantBaseline := dbMathematical
    else if DomBaselineStr = 'ideographic' then
      Result.DominantBaseline := dbIdeographic
    else if (DomBaselineStr = 'text-before-edge') or
            (DomBaselineStr = 'text-top') then
      Result.DominantBaseline := dbTextBeforeEdge
    else if (DomBaselineStr = 'text-after-edge') or
            (DomBaselineStr = 'text-bottom') then
      Result.DominantBaseline := dbTextAfterEdge
    else
      Result.DominantBaseline := dbAuto;
  end;

  // Text anchor
  AnchorStr := StyleVal(FInlineStyleMap, 'text-anchor');
  if AnchorStr = '' then
    AnchorStr := GetAttr(Node, 'text-anchor');
  if AnchorStr = 'middle' then
    Result.TextAnchor := taCenter
  else if AnchorStr = 'end' then
    Result.TextAnchor := taRight
  else if AnchorStr = 'start' then
    Result.TextAnchor := taLeft;

  // Text decoration
  TextDecStr := StyleVal(FInlineStyleMap, 'text-decoration');
  if TextDecStr = '' then
    TextDecStr := GetAttr(Node, 'text-decoration');
  if TextDecStr <> '' then
  begin
    TextDecStr := LowerCase(TextDecStr);
    if TextDecStr = 'none' then
      Result.TextDecoration := TextDecorationLineNone
    else
    begin
      Result.TextDecoration := TextDecorationLineNone;
      if Pos('underline', TextDecStr) > 0 then
        Result.TextDecoration := Result.TextDecoration or TextDecorationLineUnderline;
      if Pos('overline', TextDecStr) > 0 then
        Result.TextDecoration := Result.TextDecoration or TextDecorationLineOverline;
      if Pos('line-through', TextDecStr) > 0 then
        Result.TextDecoration := Result.TextDecoration or TextDecorationLineLineThrough;
    end;
  end;

  // Fill rule
  AnchorStr := StyleVal(FInlineStyleMap, 'fill-rule');
  if AnchorStr = '' then
    AnchorStr := GetAttr(Node, 'fill-rule');
  if AnchorStr = 'evenodd' then
    Result.EvenOddFill := True
  else if AnchorStr = 'nonzero' then
    Result.EvenOddFill := False;

  // paint-order: default is "fill stroke markers".  Per SVG spec, if only
  // "stroke" is listed the omitted values follow in default order, so
  // "stroke" alone means "stroke fill markers".  "normal" resets to default.
  AnchorStr := StyleVal(FInlineStyleMap, 'paint-order');
  if AnchorStr = '' then
    AnchorStr := GetAttr(Node, 'paint-order');
  if AnchorStr <> '' then
  begin
    AnchorStr := LowerCase(Trim(AnchorStr));
    if AnchorStr = 'normal' then
      Result.StrokeBeforeFill := False
    else
    begin
      Pos1 := Pos('stroke', AnchorStr);
      Pos2 := Pos('fill', AnchorStr);
      Result.StrokeBeforeFill :=
        (Pos1 > 0) and ((Pos2 = 0) or (Pos1 < Pos2));
    end;
  end;

  // Marker properties (inherited per SVG spec)
  // 'marker' shorthand sets all three at once
  MarkerStr := StyleVal(FInlineStyleMap, 'marker');
  if MarkerStr = '' then
    MarkerStr := GetAttr(Node, 'marker');
  if MarkerStr <> '' then
  begin
    if MarkerStr = 'none' then
    begin
      Result.MarkerStart := '';
      Result.MarkerMid := '';
      Result.MarkerEnd := '';
    end
    else
    begin
      Result.MarkerStart := MarkerStr;
      Result.MarkerMid := MarkerStr;
      Result.MarkerEnd := MarkerStr;
    end;
  end;
  MarkerStr := StyleVal(FInlineStyleMap, 'marker-start');
  if MarkerStr = '' then
    MarkerStr := GetAttr(Node, 'marker-start');
  if MarkerStr <> '' then
    if MarkerStr = 'none' then Result.MarkerStart := ''
    else Result.MarkerStart := MarkerStr;
  MarkerStr := StyleVal(FInlineStyleMap, 'marker-mid');
  if MarkerStr = '' then
    MarkerStr := GetAttr(Node, 'marker-mid');
  if MarkerStr <> '' then
    if MarkerStr = 'none' then Result.MarkerMid := ''
    else Result.MarkerMid := MarkerStr;
  MarkerStr := StyleVal(FInlineStyleMap, 'marker-end');
  if MarkerStr = '' then
    MarkerStr := GetAttr(Node, 'marker-end');
  if MarkerStr <> '' then
    if MarkerStr = 'none' then Result.MarkerEnd := ''
    else Result.MarkerEnd := MarkerStr;

  // xml:space (inherited; "preserve" keeps all whitespace verbatim)
  AnchorStr := GetAttr(Node, 'space');
  if AnchorStr = 'preserve' then
    Result.XmlSpacePreserve := True
  else if AnchorStr = 'default' then
    Result.XmlSpacePreserve := False;

  // Mix blend mode (non-inherited — reset per element)
  Result.BlendMode := bmNormal;
  AnchorStr := StyleVal(FInlineStyleMap, 'mix-blend-mode');
  if AnchorStr = '' then
    AnchorStr := GetAttr(Node, 'mix-blend-mode');
  if AnchorStr = 'multiply' then Result.BlendMode := bmMultiply
  else if AnchorStr = 'screen' then Result.BlendMode := bmScreen
  else if AnchorStr = 'overlay' then Result.BlendMode := bmOverlay
  else if AnchorStr = 'darken' then Result.BlendMode := bmDarken
  else if AnchorStr = 'lighten' then Result.BlendMode := bmLighten
  else if AnchorStr = 'color-dodge' then Result.BlendMode := bmColorDodge
  else if AnchorStr = 'color-burn' then Result.BlendMode := bmColorBurn
  else if AnchorStr = 'hard-light' then Result.BlendMode := bmHardLight
  else if AnchorStr = 'soft-light' then Result.BlendMode := bmSoftLight
  else if AnchorStr = 'difference' then Result.BlendMode := bmDifference
  else if AnchorStr = 'exclusion' then Result.BlendMode := bmExclusion
  else if AnchorStr = 'hue' then Result.BlendMode := bmHue
  else if AnchorStr = 'saturation' then Result.BlendMode := bmSaturation
  else if AnchorStr = 'color' then Result.BlendMode := bmColor
  else if AnchorStr = 'luminosity' then Result.BlendMode := bmLuminosity;
end;

// ===========================================================================
// Font shorthand parsing
// ===========================================================================

procedure TPixieSvgRendererBase.ParseFontShorthand(const S: string;
  var State: TPixieSvgState);
// Parses CSS font shorthand: [style] [variant] [weight] size[/line-height] family
// Examples: "bold 14px monospace", "italic 12px sans-serif", "700 16px/1.2 Arial, Helvetica"
var
  P, Len, TokenStart: Integer;
  Token, FamilyStr: string;
  V: Single;
  SizeFound: Boolean;
begin
  P := 1;
  Len := Length(S);
  SizeFound := False;

  while P <= Len do
  begin
    // Skip whitespace
    while (P <= Len) and (S[P] = ' ') do Inc(P);
    if P > Len then Break;

    TokenStart := P;
    while (P <= Len) and (S[P] <> ' ') do Inc(P);
    Token := Copy(S, TokenStart, P - TokenStart);
    if Token = '' then Continue;

    if not SizeFound then
    begin
      // Check for font-style keywords
      if (Token = 'italic') or (Token = 'oblique') then
      begin
        State.FontItalic := True;
        Continue;
      end
      // Check for font-variant
      else if Token = 'small-caps' then
        Continue
      // Check for font-weight keywords/numbers
      else if Token = 'bold' then
        State.FontWeight := 700
      else if Token = 'bolder' then
        State.FontWeight := 700
      else if Token = 'lighter' then
        State.FontWeight := 300
      else if Token = 'normal' then
      begin
        // Resets style, weight, or variant — apply all initial values
        State.FontItalic := False;
        State.FontWeight := 400;
        Continue;
      end
      else if (Token[1] >= '0') and (Token[1] <= '9') then
      begin
        // Could be weight (100-900) or size (with unit)
        if (Pos('px', Token) > 0) or (Pos('pt', Token) > 0) or
           (Pos('em', Token) > 0) or (Pos('/', Token) > 0) then
        begin
          // Size value — strip /line-height if present
          if Pos('/', Token) > 0 then
            Token := Copy(Token, 1, Pos('/', Token) - 1);
          State.FontSize := ParseSvgLengthEm(Token, State.FontSize);
          SizeFound := True;
        end
        else
        begin
          // Bare number — weight if 100-900 range
          if TryParseSvgFloat(Token, V) then
            State.FontWeight := Round(V);
        end;
      end
      else
      begin
        // Unrecognised token before size — treat as size if it has units
        if (Pos('px', Token) > 0) or (Pos('pt', Token) > 0) or
           (Pos('em', Token) > 0) then
        begin
          State.FontSize := ParseSvgLengthEm(Token, State.FontSize);
          SizeFound := True;
        end;
      end;
    end
    else
    begin
      // Everything after size is font-family
      FamilyStr := NormalizeFontFamily(
        Trim(Copy(S, TokenStart, Len - TokenStart + 1)));
      if FamilyStr <> '' then
        State.FontFamily := FamilyStr;
      Break;
    end;
  end;
end;

function TPixieSvgRendererBase.NormalizeFontFamily(const S: string): string;
begin
  // Strip quotes and return first family name
  Result := StringReplace(S, '''', '', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '', [rfReplaceAll]);
  if Pos(',', Result) > 0 then
    Result := Trim(Copy(Result, 1, Pos(',', Result) - 1));
end;

// ===========================================================================
// Transform parsing
// ===========================================================================

function TPixieSvgRendererBase.ParseTransform(const S: string): TPixieSvgMatrix;
var
  P, Len: Integer;
  FuncName: string;
  Args: array[0..5] of Single;
  ArgCount: Integer;
  M: TPixieSvgMatrix;

  procedure ParseArgs;
  var
    NumStr: ShortString;
  begin
    ArgCount := 0;
    // Skip '('
    while (P <= Len) and (S[P] <> '(') do Inc(P);
    Inc(P); // skip '('

    while (P <= Len) and (S[P] <> ')') do
    begin
      // Skip separators
      while (P <= Len) and CharInSet(S[P], [' ', ',', #9, #10, #13]) do Inc(P);
      if (P > Len) or (S[P] = ')') then Break;

      // Read number
      NumStr := '';
      if (P <= Len) and CharInSet(S[P], ['-', '+']) then
      begin
        NumStr := NumStr + AnsiChar(S[P]);
        Inc(P);
      end;
      while (P <= Len) and CharInSet(S[P], ['0'..'9', '.', 'e', 'E']) do
      begin
        // Handle exponent sign: e.g. -4e-6
        if CharInSet(S[P], ['e', 'E']) then
        begin
          NumStr := NumStr + AnsiChar(S[P]);
          Inc(P);
          if (P <= Len) and CharInSet(S[P], ['-', '+']) then
          begin
            NumStr := NumStr + AnsiChar(S[P]);
            Inc(P);
          end;
          Continue;
        end;
        NumStr := NumStr + AnsiChar(S[P]);
        Inc(P);
      end;

      if (NumStr <> '') and (ArgCount <= High(Args)) then
      begin
        Args[ArgCount] := SvgStrToFloat(string(NumStr));
        Inc(ArgCount);
      end;
    end;

    if (P <= Len) and (S[P] = ')') then Inc(P);
  end;

begin
  Result := TPixieSvgMatrix.Identity;
  P := 1;
  Len := Length(S);

  while P <= Len do
  begin
    // Skip whitespace
    while (P <= Len) and CharInSet(S[P], [' ', ',', #9, #10, #13]) do Inc(P);
    if P > Len then Break;

    // Read function name
    FuncName := '';
    while (P <= Len) and CharInSet(S[P], ['a'..'z', 'A'..'Z']) do
    begin
      FuncName := FuncName + S[P];
      Inc(P);
    end;

    if FuncName = '' then
    begin
      Inc(P);
      Continue;
    end;

    FuncName := LowerCase(FuncName);
    FillChar(Args, SizeOf(Args), 0);
    ParseArgs;

    if FuncName = 'translate' then
    begin
      M := TPixieSvgMatrix.CreateTranslate(Args[0],
        IfThen(ArgCount >= 2, Args[1], 0));
      Result := Result.Multiply(M);
    end
    else if FuncName = 'scale' then
    begin
      if ArgCount >= 2 then
        M := TPixieSvgMatrix.CreateScale(Args[0], Args[1])
      else
        M := TPixieSvgMatrix.CreateScale(Args[0], Args[0]);
      Result := Result.Multiply(M);
    end
    else if FuncName = 'rotate' then
    begin
      if ArgCount >= 3 then
        M := TPixieSvgMatrix.CreateRotateAt(Args[0], Args[1], Args[2])
      else
        M := TPixieSvgMatrix.CreateRotate(Args[0]);
      Result := Result.Multiply(M);
    end
    else if FuncName = 'skewx' then
    begin
      M := TPixieSvgMatrix.Identity;
      M.C := Tan(Args[0] * Pi / 180);
      Result := Result.Multiply(M);
    end
    else if FuncName = 'skewy' then
    begin
      M := TPixieSvgMatrix.Identity;
      M.B := Tan(Args[0] * Pi / 180);
      Result := Result.Multiply(M);
    end
    else if FuncName = 'matrix' then
    begin
      if ArgCount >= 6 then
      begin
        M.A := Args[0]; M.B := Args[1];
        M.C := Args[2]; M.D := Args[3];
        M.E := Args[4]; M.F := Args[5];
        Result := Result.Multiply(M);
      end;
    end;
  end;
end;

// ===========================================================================
// Shape helpers
// ===========================================================================

procedure TPixieSvgRendererBase.ApplyNodeTransform(Node: Pointer);
var
  TransStr: string;
  M: TPixieSvgMatrix;
begin
  TransStr := GetAttr(Node, 'transform');
  if TransStr = '' then Exit;

  M := ParseTransform(TransStr);
  // Only apply if not identity
  if (Abs(M.A - 1) > 0.0001) or (Abs(M.B) > 0.0001) or
     (Abs(M.C) > 0.0001) or (Abs(M.D - 1) > 0.0001) or
     (Abs(M.E) > 0.0001) or (Abs(M.F) > 0.0001) then
    DoSetTransform(M);
end;

procedure TPixieSvgRendererBase.ApplyOpacity(const State: TPixieSvgState;
  out NeedRestore: Boolean);
begin
  NeedRestore := False;
  if State.Opacity >= 1.0 then Exit;
  DoBeginOpacity(State.Opacity);
  NeedRestore := True;
end;

procedure TPixieSvgRendererBase.EmitShapeGeometry(Node: Pointer;
  const XForm: TPixieSvgMatrix);

  procedure XFormPt(var PX, PY: Single);
  var
    OX: Single;
  begin
    OX := PX;
    PX := XForm.A * OX + XForm.C * PY + XForm.E;
    PY := XForm.B * OX + XForm.D * PY + XForm.F;
  end;

  procedure XMoveTo(PX, PY: Single);
  begin
    XFormPt(PX, PY);
    DoMoveTo(PX, PY);
  end;

  procedure XLineTo(PX, PY: Single);
  begin
    XFormPt(PX, PY);
    DoLineTo(PX, PY);
  end;

  procedure XCurveTo(X1, Y1, X2, Y2, X3, Y3: Single);
  begin
    XFormPt(X1, Y1);
    XFormPt(X2, Y2);
    XFormPt(X3, Y3);
    DoCurveTo(X1, Y1, X2, Y2, X3, Y3);
  end;

var
  TagName: string;
  X, Y, W, H, CX, CY, R, RX, RY: Single;
  KX, KY: Single;
  D: string;
  Cmds: TPixieSvgPathCmdList;
  Cmd: TPixieSvgPathCmd;
  J, K: Integer;
  CurX, CurY, SubX, SubY: Single;
  NewArgs: TPixieSingleArray;
begin
  TagName := LowerCase(PixieDomToStr(TDOMElement(Node).TagName));

  if TagName = 'path' then
  begin
    D := GetAttr(Node, 'd');
    if D <> '' then
    begin
      Cmds := ParsePathData(D);
      try
        // Apply transform to absolute path commands if not identity.
        // H/V are expanded to L using the pre-transform current point, since
        // H/V endpoints depend on the *other* axis of the current point —
        // a per-axis scalar transform cannot express the diagonal result of
        // rotating/skewing a horizontal or vertical line.
        if (Abs(XForm.A - 1) > 0.0001) or (Abs(XForm.D - 1) > 0.0001) or
           (Abs(XForm.B) > 0.0001) or (Abs(XForm.C) > 0.0001) or
           (Abs(XForm.E) > 0.0001) or (Abs(XForm.F) > 0.0001) then
        begin
          CurX := 0; CurY := 0; SubX := 0; SubY := 0;
          for J := 0 to Cmds.Count - 1 do
          begin
            Cmd := Cmds[J];
            case Cmd.Cmd of
              'M':
              begin
                if Length(Cmd.Args) >= 2 then
                begin
                  SubX := Cmd.Args[0]; SubY := Cmd.Args[1];
                end;
                K := 0;
                while K + 1 < Length(Cmd.Args) do
                begin
                  CurX := Cmd.Args[K]; CurY := Cmd.Args[K + 1];
                  XFormPt(Cmd.Args[K], Cmd.Args[K + 1]);
                  Inc(K, 2);
                end;
              end;
              'L', 'T':
              begin
                K := 0;
                while K + 1 < Length(Cmd.Args) do
                begin
                  CurX := Cmd.Args[K]; CurY := Cmd.Args[K + 1];
                  XFormPt(Cmd.Args[K], Cmd.Args[K + 1]);
                  Inc(K, 2);
                end;
              end;
              'H':
              begin
                SetLength(NewArgs, Length(Cmd.Args) * 2);
                for K := 0 to High(Cmd.Args) do
                begin
                  CurX := Cmd.Args[K];
                  NewArgs[K * 2] := CurX;
                  NewArgs[K * 2 + 1] := CurY;
                  XFormPt(NewArgs[K * 2], NewArgs[K * 2 + 1]);
                end;
                Cmd.Cmd := 'L';
                Cmd.Args := NewArgs;
              end;
              'V':
              begin
                SetLength(NewArgs, Length(Cmd.Args) * 2);
                for K := 0 to High(Cmd.Args) do
                begin
                  CurY := Cmd.Args[K];
                  NewArgs[K * 2] := CurX;
                  NewArgs[K * 2 + 1] := CurY;
                  XFormPt(NewArgs[K * 2], NewArgs[K * 2 + 1]);
                end;
                Cmd.Cmd := 'L';
                Cmd.Args := NewArgs;
              end;
              'C':
              begin
                K := 0;
                while K + 5 < Length(Cmd.Args) do
                begin
                  CurX := Cmd.Args[K + 4]; CurY := Cmd.Args[K + 5];
                  XFormPt(Cmd.Args[K], Cmd.Args[K + 1]);
                  XFormPt(Cmd.Args[K + 2], Cmd.Args[K + 3]);
                  XFormPt(Cmd.Args[K + 4], Cmd.Args[K + 5]);
                  Inc(K, 6);
                end;
              end;
              'S', 'Q':
              begin
                K := 0;
                while K + 3 < Length(Cmd.Args) do
                begin
                  CurX := Cmd.Args[K + 2]; CurY := Cmd.Args[K + 3];
                  XFormPt(Cmd.Args[K], Cmd.Args[K + 1]);
                  XFormPt(Cmd.Args[K + 2], Cmd.Args[K + 3]);
                  Inc(K, 4);
                end;
              end;
              'A':
              begin
                K := 0;
                while K + 6 < Length(Cmd.Args) do
                begin
                  CurX := Cmd.Args[K + 5]; CurY := Cmd.Args[K + 6];
                  XFormPt(Cmd.Args[K + 5], Cmd.Args[K + 6]);
                  Inc(K, 7);
                end;
              end;
              'Z', 'z':
              begin
                CurX := SubX; CurY := SubY;
              end;
            end;
            Cmds[J] := Cmd;
          end;
        end;
        EmitPathCommands(Cmds);
      finally
        Cmds.Free;
      end;
    end;
  end
  else if TagName = 'rect' then
  begin
    X := ParseSvgFloat(GetAttr(Node, 'x', '0'));
    Y := ParseSvgFloat(GetAttr(Node, 'y', '0'));
    W := ParseSvgFloat(GetAttr(Node, 'width', '0'));
    H := ParseSvgFloat(GetAttr(Node, 'height', '0'));
    RX := ParseSvgFloat(GetAttr(Node, 'rx', '0'));
    RY := ParseSvgFloat(GetAttr(Node, 'ry', '0'));
    if (RX > 0) and (RY = 0) then RY := RX;
    if (RY > 0) and (RX = 0) then RX := RY;
    if (W > 0) and (H > 0) then
    begin
      if (RX > 0) or (RY > 0) then
      begin
        if RX > W / 2 then RX := W / 2;
        if RY > H / 2 then RY := H / 2;
        XMoveTo(X + RX, Y);
        XLineTo(X + W - RX, Y);
        XCurveTo(X + W - RX + RX * Kappa, Y,
                 X + W, Y + RY - RY * Kappa,
                 X + W, Y + RY);
        XLineTo(X + W, Y + H - RY);
        XCurveTo(X + W, Y + H - RY + RY * Kappa,
                 X + W - RX + RX * Kappa, Y + H,
                 X + W - RX, Y + H);
        XLineTo(X + RX, Y + H);
        XCurveTo(X + RX - RX * Kappa, Y + H,
                 X, Y + H - RY + RY * Kappa,
                 X, Y + H - RY);
        XLineTo(X, Y + RY);
        XCurveTo(X, Y + RY - RY * Kappa,
                 X + RX - RX * Kappa, Y,
                 X + RX, Y);
        DoClosePath;
      end
      else
      begin
        XMoveTo(X, Y);
        XLineTo(X + W, Y);
        XLineTo(X + W, Y + H);
        XLineTo(X, Y + H);
        DoClosePath;
      end;
    end;
  end
  else if TagName = 'circle' then
  begin
    CX := ParseSvgFloat(GetAttr(Node, 'cx', '0'));
    CY := ParseSvgFloat(GetAttr(Node, 'cy', '0'));
    R := ParseSvgFloat(GetAttr(Node, 'r', '0'));
    if R > 0 then
    begin
      KX := R * Kappa; KY := KX;
      XMoveTo(CX, CY - R);
      XCurveTo(CX + KX, CY - R, CX + R, CY - KY, CX + R, CY);
      XCurveTo(CX + R, CY + KY, CX + KX, CY + R, CX, CY + R);
      XCurveTo(CX - KX, CY + R, CX - R, CY + KY, CX - R, CY);
      XCurveTo(CX - R, CY - KY, CX - KX, CY - R, CX, CY - R);
      DoClosePath;
    end;
  end
  else if TagName = 'ellipse' then
  begin
    CX := ParseSvgFloat(GetAttr(Node, 'cx', '0'));
    CY := ParseSvgFloat(GetAttr(Node, 'cy', '0'));
    RX := ParseSvgFloat(GetAttr(Node, 'rx', '0'));
    RY := ParseSvgFloat(GetAttr(Node, 'ry', '0'));
    if (RX > 0) and (RY > 0) then
    begin
      KX := RX * Kappa; KY := RY * Kappa;
      XMoveTo(CX, CY - RY);
      XCurveTo(CX + KX, CY - RY, CX + RX, CY - KY, CX + RX, CY);
      XCurveTo(CX + RX, CY + KY, CX + KX, CY + RY, CX, CY + RY);
      XCurveTo(CX - KX, CY + RY, CX - RX, CY + KY, CX - RX, CY);
      XCurveTo(CX - RX, CY - KY, CX - KX, CY - RY, CX, CY - RY);
      DoClosePath;
    end;
  end
  else if TagName = 'polygon' then
  begin
    // Reuse polyline parsing — emit points and close
    D := GetAttr(Node, 'points');
    if D <> '' then
    begin
      // Parse points as path M...L...Z
      D := 'M' + D + 'Z';
      Cmds := ParsePathData(D);
      try
        EmitPathCommands(Cmds);
      finally
        Cmds.Free;
      end;
    end;
  end
  else if TagName = 'use' then
  begin
    // Resolve <use> reference and emit the referenced shape's geometry
    D := GetHref(Node);
    if (D <> '') and (D[1] = '#') and (FIdMap <> nil) then
    begin
      D := Copy(D, 2, MaxInt);
      if FIdMap.TryGetValue(D, Node) then
        EmitShapeGeometry(Node, XForm);
    end;
  end;
end;

procedure TPixieSvgRendererBase.ApplyClipPath(Node: Pointer);
var
  ClipStr, ClipId, TransStr: string;
  ClipEl: Pointer;
  Child: TDOMNode;
  M: TPixieSvgMatrix;
begin
  if FIdMap = nil then Exit;

  ClipStr := GetAttr(Node, 'clip-path');
  if ClipStr = '' then Exit;

  ClipId := ExtractUrlId(ClipStr);
  if ClipId = '' then Exit;

  if not FIdMap.TryGetValue(ClipId, ClipEl) then Exit;

  // Emit geometry of all children in the <clipPath> element.
  // Each child's transform is applied directly to the emitted
  // coordinates (canvas transform does not affect path geometry).
  Child := TDOMNode(ClipEl).FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = xntElement then
    begin
      TransStr := GetAttr(Child, 'transform');
      if TransStr <> '' then
        M := ParseTransform(TransStr)
      else
        M := TPixieSvgMatrix.Identity;
      EmitShapeGeometry(Child, M);
    end;
    Child := Child.NextSibling;
  end;

  DoClipPath(False);
end;

procedure TPixieSvgRendererBase.ApplyMask(Node: Pointer;
  out NeedMaskRestore: Boolean);
var
  MaskStr, MaskId, Href, ChildTag, UseHref, UseTargetId, TransStr: string;
  MaskEl, UseTarget: Pointer;
  Child: TDOMNode;
  ContentNode: Pointer;
  MX, MY, MW, MH: Single;
  M: TPixieSvgMatrix;
begin
  NeedMaskRestore := False;
  if FIdMap = nil then Exit;

  MaskStr := GetAttr(Node, 'mask');
  if MaskStr = '' then
    MaskStr := ParseStyleAttribute(ResolveNodeStyle(Node), 'mask');
  if MaskStr = '' then Exit;

  MaskId := ExtractUrlId(MaskStr);
  if MaskId = '' then Exit;
  if not FIdMap.TryGetValue(MaskId, MaskEl) then Exit;
  if LowerCase(PixieDomToStr(TDOMElement(MaskEl).TagName)) <> 'mask' then Exit;

  // Find first <image> child in the mask element (also resolve <use>)
  Href := '';
  ContentNode := nil;
  Child := TDOMNode(MaskEl).FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = xntElement then
    begin
      ChildTag := LowerCase(PixieDomToStr(TDOMElement(Child).TagName));
      if ChildTag = 'image' then
      begin
        Href := GetHref(Child);
        ContentNode := Child;
        Break;
      end
      else if ChildTag = 'use' then
      begin
        UseHref := GetHref(Child);
        if (UseHref <> '') and (UseHref[1] = '#') then
        begin
          UseTargetId := Copy(UseHref, 2, MaxInt);
          if FIdMap.TryGetValue(UseTargetId, UseTarget) then
            if LowerCase(PixieDomToStr(TDOMElement(UseTarget).TagName)) = 'image' then
            begin
              Href := GetHref(UseTarget);
              ContentNode := UseTarget;
              Break;
            end;
        end;
      end;
    end;
    Child := Child.NextSibling;
  end;
  if Href = '' then
  begin
    // No image child — treat mask shapes as a clip path (binary mask).
    // Walk all children and emit their geometry, same as ApplyClipPath.
    Child := TDOMNode(MaskEl).FirstChild;
    while Child <> nil do
    begin
      if Child.NodeType = xntElement then
      begin
        TransStr := GetAttr(Child, 'transform');
        if TransStr <> '' then
          M := ParseTransform(TransStr)
        else
          M := TPixieSvgMatrix.Identity;
        EmitShapeGeometry(Child, M);
      end;
      Child := Child.NextSibling;
    end;
    // Even-odd clip so inner shapes (the common white-rect + black-hole
    // luminance-mask pattern) subtract rather than union — nonzero winding
    // would keep same-wound holes filled and they'd never appear.
    DoClipPath(True);
    Exit;
  end;

  // Use the image element's own dimensions for mask placement
  MX := ParseSvgFloat(GetAttr(ContentNode, 'x', '0'));
  MY := ParseSvgFloat(GetAttr(ContentNode, 'y', '0'));
  MW := ParseSvgFloat(GetAttr(ContentNode, 'width', '0'));
  MH := ParseSvgFloat(GetAttr(ContentNode, 'height', '0'));
  if (MW <= 0) or (MH <= 0) then Exit;

  DoBeginMask(Href, MX, MY, MW, MH);
  NeedMaskRestore := True;
end;

procedure TPixieSvgRendererBase.EmitBezierEllipse(CX, CY, RX, RY: Single);
var
  KX, KY: Single;
begin
  KX := RX * Kappa;
  KY := RY * Kappa;

  DoMoveTo(CX, CY - RY);
  // Top -> right
  DoCurveTo(CX + KX, CY - RY, CX + RX, CY - KY, CX + RX, CY);
  // Right -> bottom
  DoCurveTo(CX + RX, CY + KY, CX + KX, CY + RY, CX, CY + RY);
  // Bottom -> left
  DoCurveTo(CX - KX, CY + RY, CX - RX, CY + KY, CX - RX, CY);
  // Left -> top
  DoCurveTo(CX - RX, CY - KY, CX - KX, CY - RY, CX, CY - RY);
end;

// ===========================================================================
// Gradient support
// ===========================================================================

class function TPixieSvgRendererBase.ExtractUrlId(const S: string): string;
var
  P1, P2: Integer;
begin
  Result := '';
  P1 := Pos('#', S);
  if P1 = 0 then Exit;
  Inc(P1);
  P2 := Pos(')', S, P1);
  if P2 = 0 then P2 := Length(S) + 1;
  Result := Trim(Copy(S, P1, P2 - P1));
  // Strip optional quotes
  if (Length(Result) >= 2) and (Result[1] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

procedure TPixieSvgRendererBase.CollectDefs(Node: Pointer);
var
  Child: TDOMNode;
  El: TDOMElement;
  TagName: string;
begin
  if FGradients = nil then
    FGradients := TPixieSvgGradientMap.Create([doOwnsValues]);

  Child := TDOMNode(Node).FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = xntElement then
    begin
      El := TDOMElement(Child);
      TagName := LowerCase(PixieDomToStr(El.TagName));
      if TagName = 'lineargradient' then
        ParseGradient(Child, False)
      else if TagName = 'radialgradient' then
        ParseGradient(Child, True);
    end;
    Child := Child.NextSibling;
  end;
end;

procedure TPixieSvgRendererBase.CollectAllGradients(Node: Pointer);
begin
  // Merged into BuildIdMap — single tree walk collects both IDs and gradients
  BuildIdMap(Node);
end;

procedure TPixieSvgRendererBase.BuildIdMap(Node: Pointer);
var
  Child: TDOMNode;
  El: TDOMElement;
  IdStr, TagName, CSS: string;
begin
  if FIdMap = nil then
    FIdMap := TPixieSvgIdMap.Create;

  if TDOMNode(Node).NodeType = xntElement then
  begin
    El := TDOMElement(Node);
    IdStr := PixieDomToStr(El.GetAttribute('id'));
    if IdStr <> '' then
      FIdMap.AddOrSetValue(IdStr, Node);
  end;

  Child := TDOMNode(Node).FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = xntElement then
    begin
      TagName := LowerCase(PixieDomToStr(TDOMElement(Child).TagName));
      if TagName = 'defs' then
        CollectDefs(Child)
      else if TagName = 'lineargradient' then
        ParseGradient(Child, False)
      else if TagName = 'radialgradient' then
        ParseGradient(Child, True)
      else if TagName = 'style' then
      begin
        CSS := CollectAllText(Child);
        if CSS <> '' then
          ParseStyleElement(CSS);
      end;
      BuildIdMap(Child);
    end;
    Child := Child.NextSibling;
  end;
end;

function TPixieSvgRendererBase.IsPatternFill(const Id: string): Boolean;
var
  El: Pointer;
begin
  Result := False;
  if (FIdMap = nil) or (Id = '') then Exit;
  if not FIdMap.TryGetValue(Id, El) then Exit;
  Result := LowerCase(PixieDomToStr(TDOMElement(El).TagName)) = 'pattern';
end;

// Find the first descendant <image> element, following <use xlink:href>
// once. Used by ResolvePatternImageHref and GetPatternInfo.
function TPixieSvgRendererBase.FindImageElement(Node: Pointer;
  Depth: Integer): Pointer;
var
  Tag, HrefStr: string;
  Child, Target: Pointer;
begin
  Result := nil;
  if (Node = nil) or (Depth >= 10) then Exit;
  Tag := LowerCase(PixieDomToStr(TDOMElement(Node).TagName));
  if Tag = 'image' then
  begin
    Result := Node;
    Exit;
  end;
  if Tag = 'use' then
  begin
    HrefStr := GetHref(Node);
    if (HrefStr <> '') and (HrefStr[1] = '#') and
      FIdMap.TryGetValue(Copy(HrefStr, 2, MaxInt), Target) then
      Result := FindImageElement(Target, Depth + 1);
    Exit;
  end;
  Child := TDOMNode(Node).FirstChild;
  while Child <> nil do
  begin
    if TDOMNode(Child).NodeType = xntElement then
    begin
      Result := FindImageElement(Child, Depth + 1);
      if Result <> nil then Exit;
    end;
    Child := TDOMNode(Child).NextSibling;
  end;
end;

function TPixieSvgRendererBase.ResolvePatternImageHref(
  const PatternId: string): string;
var
  PatternEl, ImgEl: Pointer;
begin
  Result := '';
  if (FIdMap = nil) or (PatternId = '') then Exit;
  if not FIdMap.TryGetValue(PatternId, PatternEl) then Exit;
  ImgEl := FindImageElement(PatternEl, 0);
  if ImgEl <> nil then
    Result := GetHref(ImgEl);
end;

procedure TPixieSvgPatternInfo.Init;
begin
  ImageHref := '';
  X := 0; Y := 0;
  Width := 0; Height := 0;
  HasViewBox := False;
  ViewBoxX := 0; ViewBoxY := 0; ViewBoxW := 0; ViewBoxH := 0;
  ImgX := 0; ImgY := 0; ImgW := 0; ImgH := 0;
  PatternUnitsUserSpace := False;
  ContentUnitsObjectBBox := False;
  PatternNode := nil;
  HasChildren := False;
  HasPatternTransform := False;
end;

function TPixieSvgRendererBase.GetPatternInfo(const PatternId: string;
  out Info: TPixieSvgPatternInfo): Boolean;

  // Parse "x y w h" (space/comma separated) into Info.ViewBox* fields
  procedure ParseViewBoxAttr(const S: string);
  begin
    ParseViewBox(S, Info.ViewBoxX, Info.ViewBoxY, Info.ViewBoxW, Info.ViewBoxH);
    Info.HasViewBox := (Info.ViewBoxW > 0) and (Info.ViewBoxH > 0);
  end;

  // Read attributes from one pattern element, unconditionally overwriting
  // Info fields when an attribute is present. Called root-to-leaf so the
  // leaf element (the directly referenced pattern) wins, per SVG spec.
  procedure ReadPatternAttrs(Node: Pointer);
  var
    Attr: string;
    ImgEl: Pointer;
    Child: TDOMNode;
  begin
    Attr := GetAttr(Node, 'x');
    if Attr <> '' then Info.X := ParseSvgFloat(Attr);
    Attr := GetAttr(Node, 'y');
    if Attr <> '' then Info.Y := ParseSvgFloat(Attr);
    Attr := GetAttr(Node, 'width');
    if Attr <> '' then Info.Width := ParseSvgFloat(Attr);
    Attr := GetAttr(Node, 'height');
    if Attr <> '' then Info.Height := ParseSvgFloat(Attr);
    Attr := GetAttr(Node, 'viewBox');
    if Attr <> '' then ParseViewBoxAttr(Attr);
    Attr := GetAttr(Node, 'patternUnits');
    if Attr <> '' then
      Info.PatternUnitsUserSpace := SameText(Attr, 'userSpaceOnUse');
    Attr := GetAttr(Node, 'patternContentUnits');
    if Attr <> '' then
      Info.ContentUnitsObjectBBox := SameText(Attr, 'objectBoundingBox');
    Attr := GetAttr(Node, 'patternTransform');
    if Attr <> '' then
    begin
      Info.HasPatternTransform := True;
      Info.PatternTransform := ParseTransform(Attr);
    end;

    // Check for element children (content comes from this node)
    Child := TDOMNode(Node).FirstChild;
    while Child <> nil do
    begin
      if Child.NodeType = xntElement then
      begin
        Info.PatternNode := Node;
        Info.HasChildren := True;
        Break;
      end;
      Child := Child.NextSibling;
    end;

    ImgEl := FindImageElement(Node, 0);
    if ImgEl <> nil then
    begin
      Info.ImageHref := GetHref(ImgEl);
      Info.ImgX := ParseSvgFloat(GetAttr(ImgEl, 'x', '0'));
      Info.ImgY := ParseSvgFloat(GetAttr(ImgEl, 'y', '0'));
      Info.ImgW := ParseSvgFloat(GetAttr(ImgEl, 'width', '0'));
      Info.ImgH := ParseSvgFloat(GetAttr(ImgEl, 'height', '0'));
    end;
  end;

const
  MaxChain = 10;
var
  Chain: array[0..MaxChain - 1] of Pointer;
  ChainLen, I: Integer;
  El: Pointer;
  HrefStr: string;
begin
  Info.Init;
  Result := False;

  // Cache hit — pattern already parsed for this document
  if (FPatternInfos <> nil) and FPatternInfos.TryGetValue(PatternId, Info) then
  begin
    Result := (Info.Width > 0) and (Info.Height > 0) and
      (Info.HasChildren or (Info.ImageHref <> ''));
    Exit;
  end;

  if (FIdMap = nil) or (PatternId = '') then Exit;
  if not FIdMap.TryGetValue(PatternId, El) then Exit;
  if LowerCase(PixieDomToStr(TDOMElement(El).TagName)) <> 'pattern' then Exit;

  // Collect the xlink:href chain from leaf to root
  ChainLen := 0;
  while (El <> nil) and (ChainLen < MaxChain) do
  begin
    Chain[ChainLen] := El;
    Inc(ChainLen);
    HrefStr := GetHref(El);
    if (HrefStr = '') or (HrefStr[1] <> '#') then Break;
    if not FIdMap.TryGetValue(Copy(HrefStr, 2, MaxInt), El) then Break;
    if LowerCase(PixieDomToStr(TDOMElement(El).TagName)) <> 'pattern' then Break;
  end;

  // Apply root-to-leaf so the leaf (directly referenced) pattern wins
  for I := ChainLen - 1 downto 0 do
    ReadPatternAttrs(Chain[I]);

  Result := (Info.Width > 0) and (Info.Height > 0) and
    (Info.HasChildren or (Info.ImageHref <> ''));

  if FPatternInfos = nil then
    FPatternInfos := TPixieSvgPatternInfoMap.Create;
  FPatternInfos.AddOrSetValue(PatternId, Info);
end;

procedure TPixieSvgRendererBase.ParseGradient(Node: Pointer;
  IsRadial: Boolean);
var
  El: TDOMElement;
  Grad: TPixieSvgGradient;
  GradId, Units, HrefStr, S: string;
  Child: TDOMNode;
  ChildEl: TDOMElement;
  ChildTag: string;
  Stop: TPixieSvgGradientStop;
  OffsetStr, StopColorStr, StopOpacStr, StyleStr: string;
  StopColor: TPixieWebColor;
  StopOpacity: Single;
begin
  if FGradients = nil then
    FGradients := TPixieSvgGradientMap.Create([doOwnsValues]);

  El := TDOMElement(Node);
  GradId := PixieDomToStr(El.GetAttribute('id'));
  if GradId = '' then Exit;
  if (FGradients <> nil) and FGradients.ContainsKey(GradId) then Exit;

  Grad := TPixieSvgGradient.Create;
  Grad.Id := GradId;
  Grad.IsRadial := IsRadial;

  // gradientUnits
  Units := PixieDomToStr(El.GetAttribute('gradientUnits'));
  Grad.HasUnits := (Units <> '');
  Grad.UserSpaceUnits := (LowerCase(Units) = 'userspaceonuse');

  // xlink:href / href
  HrefStr := GetHref(Node);
  if (HrefStr <> '') and (HrefStr[1] = '#') then
    Grad.HrefId := Copy(HrefStr, 2, MaxInt);

  // gradientTransform
  Grad.GradientTransform := PixieDomToStr(El.GetAttribute('gradientTransform'));
  Grad.HasTransform := (Grad.GradientTransform <> '');

  // spreadMethod
  S := LowerCase(PixieDomToStr(El.GetAttribute('spreadMethod')));
  Grad.HasSpread := (S <> '');
  if S = 'repeat' then
    Grad.Spread := smRepeat
  else if S = 'reflect' then
    Grad.Spread := smReflect
  else
    Grad.Spread := smPad;

  if IsRadial then
  begin
    S := GetAttr(Node, 'cx');
    if S <> '' then
    begin
      Grad.HasCoords := True;
      Grad.CX := ParseSvgFloat(S);
    end
    else
      Grad.CX := 0.5;

    S := GetAttr(Node, 'cy');
    if S <> '' then
    begin
      Grad.HasCoords := True;
      Grad.CY := ParseSvgFloat(S);
    end
    else
      Grad.CY := 0.5;

    S := GetAttr(Node, 'r');
    if S <> '' then
    begin
      Grad.HasCoords := True;
      Grad.R := ParseSvgFloat(S);
    end
    else
      Grad.R := 0.5;

    Grad.FX := ParseSvgFloat(GetAttr(Node, 'fx', '-1'));
    Grad.FY := ParseSvgFloat(GetAttr(Node, 'fy', '-1'));
  end
  else
  begin
    S := GetAttr(Node, 'x1');
    if S <> '' then
    begin
      Grad.HasCoords := True;
      Grad.X1 := ParseSvgFloat(S);
    end
    else
      Grad.X1 := 0;

    S := GetAttr(Node, 'y1');
    if S <> '' then
    begin
      Grad.HasCoords := True;
      Grad.Y1 := ParseSvgFloat(S);
    end
    else
      Grad.Y1 := 0;

    S := GetAttr(Node, 'x2');
    if S <> '' then
    begin
      Grad.HasCoords := True;
      Grad.X2 := ParseSvgFloat(S);
    end
    else
      Grad.X2 := 1;

    S := GetAttr(Node, 'y2');
    if S <> '' then
    begin
      Grad.HasCoords := True;
      Grad.Y2 := ParseSvgFloat(S);
    end
    else
      Grad.Y2 := 0;
  end;

  // Parse <stop> children
  Child := TDOMNode(Node).FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = xntElement then
    begin
      ChildEl := TDOMElement(Child);
      ChildTag := LowerCase(PixieDomToStr(ChildEl.TagName));
      if ChildTag = 'stop' then
      begin
        OffsetStr := PixieDomToStr(ChildEl.GetAttribute('offset'));
        Stop.Offset := ParseSvgFloat(OffsetStr);
        Stop.Offset := EnsureRange(Stop.Offset, 0, 1);

        // Parse stop-color from attribute or style
        StyleStr := PixieDomToStr(ChildEl.GetAttribute('style'));
        StopColorStr := PixieDomToStr(ChildEl.GetAttribute('stop-color'));
        if StopColorStr = '' then
          StopColorStr := ParseStyleAttribute(StyleStr, 'stop-color');
        if StopColorStr = '' then
          StopColorStr := 'black';

        if not ParseSvgColor(StopColorStr, StopColor) then
          StopColor := TPixieWebColor.Black;

        // Parse stop-opacity
        StopOpacStr := PixieDomToStr(ChildEl.GetAttribute('stop-opacity'));
        if StopOpacStr = '' then
          StopOpacStr := ParseStyleAttribute(StyleStr, 'stop-opacity');
        if StopOpacStr <> '' then
          StopOpacity := EnsureRange(ParseSvgFloat(StopOpacStr), 0, 1)
        else
          StopOpacity := 1.0;

        StopColor.Alpha := Round(StopColor.Alpha * StopOpacity);
        Stop.Color := StopColor;
        Grad.Stops.Add(Stop);
      end;
    end;
    Child := Child.NextSibling;
  end;

  // Add or replace in dictionary
  if FGradients.ContainsKey(GradId) then
    FGradients.Remove(GradId);
  FGradients.Add(GradId, Grad);
end;

function TPixieSvgRendererBase.ResolveGradientStops(
  const Id: string): TPixieSvgGradient;
var
  Grad, Cur, RefGrad: TPixieSvgGradient;
  Visited: Integer;
begin
  Result := nil;
  if (FGradients = nil) or not FGradients.TryGetValue(Id, Grad) then
    Exit;

  // Walk the href chain to inherit attributes and stops
  Cur := Grad;
  Visited := 0;
  while (Cur.HrefId <> '') and (Visited < 10) do
  begin
    if not FGradients.TryGetValue(Cur.HrefId, RefGrad) then
      Break;

    // Inherit unspecified attributes from referenced gradient
    if not Grad.HasUnits then
    begin
      Grad.UserSpaceUnits := RefGrad.UserSpaceUnits;
      Grad.HasUnits := RefGrad.HasUnits;
    end;
    if not Grad.HasCoords then
    begin
      Grad.X1 := RefGrad.X1; Grad.Y1 := RefGrad.Y1;
      Grad.X2 := RefGrad.X2; Grad.Y2 := RefGrad.Y2;
      Grad.CX := RefGrad.CX; Grad.CY := RefGrad.CY;
      Grad.R := RefGrad.R; Grad.FX := RefGrad.FX; Grad.FY := RefGrad.FY;
      Grad.HasCoords := RefGrad.HasCoords;
    end;
    if not Grad.HasTransform then
    begin
      Grad.GradientTransform := RefGrad.GradientTransform;
      Grad.HasTransform := RefGrad.HasTransform;
    end;
    if not Grad.HasSpread then
    begin
      Grad.Spread := RefGrad.Spread;
      Grad.HasSpread := RefGrad.HasSpread;
    end;

    // Inherit stops
    if (Grad.Stops.Count = 0) and (RefGrad.Stops.Count > 0) then
      Grad.Stops.AddRange(RefGrad.Stops.ToArray);

    // Early exit once everything is resolved
    if Grad.HasUnits and Grad.HasCoords and Grad.HasTransform
      and Grad.HasSpread and (Grad.Stops.Count > 0) then
      Break;

    Cur := RefGrad;
    Inc(Visited);
  end;

  if Grad.Stops.Count > 0 then
    Result := Grad;
end;

// ===========================================================================
// Shape renderers
// ===========================================================================

procedure TPixieSvgRendererBase.RenderRect(Node: Pointer;
  const State: TPixieSvgState);
var
  X, Y, W, H, RX, RY: Single;
  NeedRestore: Boolean;
begin
  X := ParseSvgFloat(GetAttr(Node, 'x', '0'));
  Y := ParseSvgFloat(GetAttr(Node, 'y', '0'));
  W := ParseSvgFloat(GetAttr(Node, 'width', '0'));
  H := ParseSvgFloat(GetAttr(Node, 'height', '0'));
  RX := ParseSvgFloat(GetAttr(Node, 'rx', '0'));
  RY := ParseSvgFloat(GetAttr(Node, 'ry', '0'));

  if (W <= 0) or (H <= 0) then Exit;

  // If only one radius specified (attribute missing), use the other for both.
  // An explicit rx="0" or ry="0" means no rounding on that axis.
  if (RX > 0) and (RY = 0) and (GetAttr(Node, 'ry') = '') then RY := RX;
  if (RY > 0) and (RX = 0) and (GetAttr(Node, 'rx') = '') then RX := RY;

  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyClipPath(Node);
  ApplyOpacity(State, NeedRestore);

  if (RX > 0) or (RY > 0) then
  begin
    // Rounded rect via bezier corners
    if RX > W / 2 then RX := W / 2;
    if RY > H / 2 then RY := H / 2;

    DoMoveTo(X + RX, Y);
    // Top edge -> top-right corner
    DoLineTo(X + W - RX, Y);
    DoCurveTo(X + W - RX + RX * Kappa, Y,
              X + W, Y + RY - RY * Kappa,
              X + W, Y + RY);
    // Right edge -> bottom-right corner
    DoLineTo(X + W, Y + H - RY);
    DoCurveTo(X + W, Y + H - RY + RY * Kappa,
              X + W - RX + RX * Kappa, Y + H,
              X + W - RX, Y + H);
    // Bottom edge -> bottom-left corner
    DoLineTo(X + RX, Y + H);
    DoCurveTo(X + RX - RX * Kappa, Y + H,
              X, Y + H - RY + RY * Kappa,
              X, Y + H - RY);
    // Left edge -> top-left corner
    DoLineTo(X, Y + RY);
    DoCurveTo(X, Y + RY - RY * Kappa,
              X + RX - RX * Kappa, Y,
              X + RX, Y);
    DoClosePath;
  end
  else
  begin
    DoMoveTo(X, Y);
    DoLineTo(X + W, Y);
    DoLineTo(X + W, Y + H);
    DoLineTo(X, Y + H);
    DoClosePath;
  end;

  DoFillAndStroke(State);
  if NeedRestore then DoEndOpacity;
  DoRestoreState;
end;

procedure TPixieSvgRendererBase.RenderCircle(Node: Pointer;
  const State: TPixieSvgState);
var
  CX, CY, R: Single;
  NeedRestore: Boolean;
begin
  CX := ParseSvgFloat(GetAttr(Node, 'cx', '0'));
  CY := ParseSvgFloat(GetAttr(Node, 'cy', '0'));
  R := ParseSvgFloat(GetAttr(Node, 'r', '0'));

  if R <= 0 then Exit;

  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyClipPath(Node);
  ApplyOpacity(State, NeedRestore);

  EmitBezierEllipse(CX, CY, R, R);
  DoFillAndStroke(State);
  if NeedRestore then DoEndOpacity;
  DoRestoreState;
end;

procedure TPixieSvgRendererBase.RenderEllipse(Node: Pointer;
  const State: TPixieSvgState);
var
  CX, CY, RX, RY: Single;
  NeedRestore: Boolean;
begin
  CX := ParseSvgFloat(GetAttr(Node, 'cx', '0'));
  CY := ParseSvgFloat(GetAttr(Node, 'cy', '0'));
  RX := ParseSvgFloat(GetAttr(Node, 'rx', '0'));
  RY := ParseSvgFloat(GetAttr(Node, 'ry', '0'));

  if (RX <= 0) or (RY <= 0) then Exit;

  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyClipPath(Node);
  ApplyOpacity(State, NeedRestore);

  EmitBezierEllipse(CX, CY, RX, RY);
  DoFillAndStroke(State);
  if NeedRestore then DoEndOpacity;
  DoRestoreState;
end;

procedure TPixieSvgRendererBase.RenderLine(Node: Pointer;
  const State: TPixieSvgState);
var
  X1, Y1, X2, Y2, Angle: Single;
  NeedRestore: Boolean;
begin
  X1 := ParseSvgFloat(GetAttr(Node, 'x1', '0'));
  Y1 := ParseSvgFloat(GetAttr(Node, 'y1', '0'));
  X2 := ParseSvgFloat(GetAttr(Node, 'x2', '0'));
  Y2 := ParseSvgFloat(GetAttr(Node, 'y2', '0'));

  if not State.HasStroke then Exit;

  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyClipPath(Node);
  ApplyOpacity(State, NeedRestore);

  DoMoveTo(X1, Y1);
  DoLineTo(X2, Y2);
  DoFillAndStroke(State);

  Angle := ArcTan2(Y2 - Y1, X2 - X1) * 180 / Pi;
  RenderMarkers(Node, State, X1, Y1, X2, Y2, Angle, Angle);

  if NeedRestore then DoEndOpacity;
  DoRestoreState;
end;

procedure TPixieSvgRendererBase.RenderPolyline(Node: Pointer;
  const State: TPixieSvgState; ClosePath: Boolean);
var
  PointsStr: string;
  Nums: TPixieSingleArray;
  NumCount: Integer;
  P, Len: Integer;
  NumStr: ShortString;
  I: Integer;
  NeedRestore: Boolean;
begin
  PointsStr := GetAttr(Node, 'points');
  if PointsStr = '' then Exit;

  // Parse numbers from points attribute
  SetLength(Nums, 64);
  NumCount := 0;
  P := 1;
  Len := Length(PointsStr);

  while P <= Len do
  begin
    // Skip separators
    while (P <= Len) and CharInSet(PointsStr[P], [' ', ',', #9, #10, #13]) do Inc(P);
    if P > Len then Break;

    NumStr := '';
    if (P <= Len) and CharInSet(PointsStr[P], ['-', '+']) then
    begin
      NumStr := NumStr + AnsiChar(PointsStr[P]);
      Inc(P);
    end;
    while (P <= Len) and CharInSet(PointsStr[P], ['0'..'9', '.']) do
    begin
      NumStr := NumStr + AnsiChar(PointsStr[P]);
      Inc(P);
    end;

    if NumStr <> '' then
    begin
      if NumCount >= Length(Nums) then
        SetLength(Nums, Length(Nums) * 2);
      Nums[NumCount] := SvgStrToFloat(string(NumStr));
      Inc(NumCount);
    end
    else
      Inc(P);
  end;

  if NumCount < 4 then Exit; // need at least 2 points

  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyClipPath(Node);
  ApplyOpacity(State, NeedRestore);

  DoMoveTo(Nums[0], Nums[1]);
  I := 2;
  while I + 1 < NumCount do
  begin
    DoLineTo(Nums[I], Nums[I + 1]);
    Inc(I, 2);
  end;

  if ClosePath then
    DoClosePath;

  DoFillAndStroke(State);

  if (NumCount >= 4) and not ClosePath then
  begin
    RenderMarkers(Node, State,
      Nums[0], Nums[1],
      Nums[NumCount - 2], Nums[NumCount - 1],
      ArcTan2(Nums[3] - Nums[1], Nums[2] - Nums[0]) * 180 / Pi,
      ArcTan2(Nums[NumCount - 1] - Nums[NumCount - 3],
              Nums[NumCount - 2] - Nums[NumCount - 4]) * 180 / Pi);
  end;

  if NeedRestore then DoEndOpacity;
  DoRestoreState;
end;

// ===========================================================================
// SVG path mini-language
// ===========================================================================

function TPixieSvgRendererBase.ParsePathData(
  const D: string): TPixieSvgPathCmdList;
var
  P, Len: Integer;
  Cmd: TPixieSvgPathCmd;
  NumStr: ShortString;
  ArgList: TPixieSingleArray;
  ArgCount: Integer;
  Ch: Char;
  HasDot: Boolean;
begin
  Result := TPixieSvgPathCmdList.Create;
  P := 1;
  Len := Length(D);
  SetLength(ArgList, 32);

  while P <= Len do
  begin
    // Skip whitespace and commas
    while (P <= Len) and CharInSet(D[P], [' ', ',', #9, #10, #13]) do Inc(P);
    if P > Len then Break;

    Ch := D[P];
    if CharInSet(Ch, ['M','m','L','l','H','h','V','v','C','c','S','s',
              'Q','q','T','t','A','a','Z','z']) then
    begin
      Cmd.Cmd := AnsiChar(Ch);
      Inc(P);

      // Collect numeric arguments
      ArgCount := 0;
      while P <= Len do
      begin
        // Skip whitespace and commas
        while (P <= Len) and CharInSet(D[P], [' ', ',', #9, #10, #13]) do Inc(P);
        if P > Len then Break;

        // Check if next char starts a number or is a new command
        if CharInSet(D[P], ['M','m','L','l','H','h','V','v','C','c','S','s',
                     'Q','q','T','t','A','a','Z','z']) then
          Break;

        // SVG arc flags (the large-arc-flag and sweep-flag — the 4th and 5th
        // argument of each 7-argument A/a group) are single '0'/'1' characters
        // that the grammar permits to abut the following number with no
        // separator, e.g. "a19 19 0 00-4.88-1.5" packs both flags as "00".
        // Read them as one digit so the remaining arc parameters don't shift.
        if ((Cmd.Cmd = 'A') or (Cmd.Cmd = 'a')) and
           ((ArgCount mod 7 = 3) or (ArgCount mod 7 = 4)) and
           CharInSet(D[P], ['0', '1']) then
        begin
          if ArgCount >= Length(ArgList) then
            SetLength(ArgList, Length(ArgList) * 2);
          ArgList[ArgCount] := Ord(D[P]) - Ord('0');
          Inc(ArgCount);
          Inc(P);
          Continue;
        end;

        // Read number
        NumStr := '';
        if (P <= Len) and CharInSet(D[P], ['-', '+']) then
        begin
          NumStr := NumStr + AnsiChar(D[P]);
          Inc(P);
        end;
        HasDot := False;
        while (P <= Len) and CharInSet(D[P], ['0'..'9', '.', 'e', 'E']) do
        begin
          // Handle implicit separator on second decimal point
          if (D[P] = '.') then
          begin
            if HasDot then Break;
            HasDot := True;
          end;
          // Handle exponent sign: e.g. 2.81e-07
          if CharInSet(D[P], ['e', 'E']) then
          begin
            NumStr := NumStr + AnsiChar(D[P]);
            Inc(P);
            if (P <= Len) and CharInSet(D[P], ['-', '+']) then
            begin
              NumStr := NumStr + AnsiChar(D[P]);
              Inc(P);
            end;
            Continue;
          end;
          NumStr := NumStr + AnsiChar(D[P]);
          Inc(P);
        end;

        if NumStr <> '' then
        begin
          if ArgCount >= Length(ArgList) then
            SetLength(ArgList, Length(ArgList) * 2);
          ArgList[ArgCount] := SvgStrToFloat(string(NumStr));
          Inc(ArgCount);
        end
        else
          Break;
      end;

      SetLength(Cmd.Args, ArgCount);
      if ArgCount > 0 then
        Move(ArgList[0], Cmd.Args[0], ArgCount * SizeOf(Single));
      Result.Add(Cmd);
    end
    else
      Inc(P); // skip unexpected character
  end;
end;

procedure TPixieSvgRendererBase.EmitPathCommands(
  Cmds: TPixieSvgPathCmdList);
var
  I, J, ArgIdx, ArgLen: Integer;
  Cmd: TPixieSvgPathCmd;
  CurX, CurY, StartX, StartY: Single;
  X, Y, X1, Y1, X2, Y2: Single;
  PrevCpX, PrevCpY: Single;
  PrevQpX, PrevQpY: Single;
  PrevCmd: AnsiChar;
  RX, RY, XRot: Single;
  LargeArc, Sweep: Boolean;
  Cp1X, Cp1Y, Cp2X, Cp2Y: Single;
begin
  CurX := 0; CurY := 0;
  StartX := 0; StartY := 0;
  PrevCpX := 0; PrevCpY := 0;
  PrevQpX := 0; PrevQpY := 0;
  PrevCmd := #0;

  for I := 0 to Cmds.Count - 1 do
  begin
    Cmd := Cmds[I];
    ArgIdx := 0;
    ArgLen := Length(Cmd.Args);

    case Cmd.Cmd of
      'M':
      begin
        J := 0;
        while ArgIdx + 1 < ArgLen do
        begin
          X := Cmd.Args[ArgIdx]; Y := Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          if J = 0 then
          begin
            DoMoveTo(X, Y);
            StartX := X; StartY := Y;
          end
          else
            DoLineTo(X, Y);
          CurX := X; CurY := Y;
          Inc(J);
        end;
      end;

      'm':
      begin
        J := 0;
        while ArgIdx + 1 < ArgLen do
        begin
          X := CurX + Cmd.Args[ArgIdx]; Y := CurY + Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          if J = 0 then
          begin
            DoMoveTo(X, Y);
            StartX := X; StartY := Y;
          end
          else
            DoLineTo(X, Y);
          CurX := X; CurY := Y;
          Inc(J);
        end;
      end;

      'L':
      begin
        while ArgIdx + 1 < ArgLen do
        begin
          X := Cmd.Args[ArgIdx]; Y := Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          DoLineTo(X, Y);
          CurX := X; CurY := Y;
        end;
      end;

      'l':
      begin
        while ArgIdx + 1 < ArgLen do
        begin
          X := CurX + Cmd.Args[ArgIdx]; Y := CurY + Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          DoLineTo(X, Y);
          CurX := X; CurY := Y;
        end;
      end;

      'H':
      begin
        while ArgIdx < ArgLen do
        begin
          X := Cmd.Args[ArgIdx]; Inc(ArgIdx);
          DoLineTo(X, CurY);
          CurX := X;
        end;
      end;

      'h':
      begin
        while ArgIdx < ArgLen do
        begin
          X := CurX + Cmd.Args[ArgIdx]; Inc(ArgIdx);
          DoLineTo(X, CurY);
          CurX := X;
        end;
      end;

      'V':
      begin
        while ArgIdx < ArgLen do
        begin
          Y := Cmd.Args[ArgIdx]; Inc(ArgIdx);
          DoLineTo(CurX, Y);
          CurY := Y;
        end;
      end;

      'v':
      begin
        while ArgIdx < ArgLen do
        begin
          Y := CurY + Cmd.Args[ArgIdx]; Inc(ArgIdx);
          DoLineTo(CurX, Y);
          CurY := Y;
        end;
      end;

      'C':
      begin
        while ArgIdx + 5 < ArgLen do
        begin
          X1 := Cmd.Args[ArgIdx]; Y1 := Cmd.Args[ArgIdx + 1];
          X2 := Cmd.Args[ArgIdx + 2]; Y2 := Cmd.Args[ArgIdx + 3];
          X := Cmd.Args[ArgIdx + 4]; Y := Cmd.Args[ArgIdx + 5];
          Inc(ArgIdx, 6);
          DoCurveTo(X1, Y1, X2, Y2, X, Y);
          PrevCpX := X2; PrevCpY := Y2;
          CurX := X; CurY := Y;
        end;
      end;

      'c':
      begin
        while ArgIdx + 5 < ArgLen do
        begin
          X1 := CurX + Cmd.Args[ArgIdx]; Y1 := CurY + Cmd.Args[ArgIdx + 1];
          X2 := CurX + Cmd.Args[ArgIdx + 2]; Y2 := CurY + Cmd.Args[ArgIdx + 3];
          X := CurX + Cmd.Args[ArgIdx + 4]; Y := CurY + Cmd.Args[ArgIdx + 5];
          Inc(ArgIdx, 6);
          DoCurveTo(X1, Y1, X2, Y2, X, Y);
          PrevCpX := X2; PrevCpY := Y2;
          CurX := X; CurY := Y;
        end;
      end;

      'S':
      begin
        while ArgIdx + 3 < ArgLen do
        begin
          if PrevCmd in ['C', 'c', 'S', 's'] then
          begin
            X1 := 2 * CurX - PrevCpX;
            Y1 := 2 * CurY - PrevCpY;
          end
          else
          begin
            X1 := CurX; Y1 := CurY;
          end;
          X2 := Cmd.Args[ArgIdx]; Y2 := Cmd.Args[ArgIdx + 1];
          X := Cmd.Args[ArgIdx + 2]; Y := Cmd.Args[ArgIdx + 3];
          Inc(ArgIdx, 4);
          DoCurveTo(X1, Y1, X2, Y2, X, Y);
          PrevCpX := X2; PrevCpY := Y2;
          CurX := X; CurY := Y;
          PrevCmd := 'S';
        end;
        Continue;
      end;

      's':
      begin
        while ArgIdx + 3 < ArgLen do
        begin
          if PrevCmd in ['C', 'c', 'S', 's'] then
          begin
            X1 := 2 * CurX - PrevCpX;
            Y1 := 2 * CurY - PrevCpY;
          end
          else
          begin
            X1 := CurX; Y1 := CurY;
          end;
          X2 := CurX + Cmd.Args[ArgIdx]; Y2 := CurY + Cmd.Args[ArgIdx + 1];
          X := CurX + Cmd.Args[ArgIdx + 2]; Y := CurY + Cmd.Args[ArgIdx + 3];
          Inc(ArgIdx, 4);
          DoCurveTo(X1, Y1, X2, Y2, X, Y);
          PrevCpX := X2; PrevCpY := Y2;
          CurX := X; CurY := Y;
          PrevCmd := 's';
        end;
        Continue;
      end;

      'Q':
      begin
        while ArgIdx + 3 < ArgLen do
        begin
          X1 := Cmd.Args[ArgIdx]; Y1 := Cmd.Args[ArgIdx + 1];
          X := Cmd.Args[ArgIdx + 2]; Y := Cmd.Args[ArgIdx + 3];
          Inc(ArgIdx, 4);
          // Convert quadratic to cubic
          Cp1X := CurX + (2.0 / 3.0) * (X1 - CurX);
          Cp1Y := CurY + (2.0 / 3.0) * (Y1 - CurY);
          Cp2X := X + (2.0 / 3.0) * (X1 - X);
          Cp2Y := Y + (2.0 / 3.0) * (Y1 - Y);
          DoCurveTo(Cp1X, Cp1Y, Cp2X, Cp2Y, X, Y);
          PrevQpX := X1; PrevQpY := Y1;
          CurX := X; CurY := Y;
        end;
      end;

      'q':
      begin
        while ArgIdx + 3 < ArgLen do
        begin
          X1 := CurX + Cmd.Args[ArgIdx]; Y1 := CurY + Cmd.Args[ArgIdx + 1];
          X := CurX + Cmd.Args[ArgIdx + 2]; Y := CurY + Cmd.Args[ArgIdx + 3];
          Inc(ArgIdx, 4);
          Cp1X := CurX + (2.0 / 3.0) * (X1 - CurX);
          Cp1Y := CurY + (2.0 / 3.0) * (Y1 - CurY);
          Cp2X := X + (2.0 / 3.0) * (X1 - X);
          Cp2Y := Y + (2.0 / 3.0) * (Y1 - Y);
          DoCurveTo(Cp1X, Cp1Y, Cp2X, Cp2Y, X, Y);
          PrevQpX := X1; PrevQpY := Y1;
          CurX := X; CurY := Y;
        end;
      end;

      'T':
      begin
        while ArgIdx + 1 < ArgLen do
        begin
          if PrevCmd in ['Q', 'q', 'T', 't'] then
          begin
            X1 := 2 * CurX - PrevQpX;
            Y1 := 2 * CurY - PrevQpY;
          end
          else
          begin
            X1 := CurX; Y1 := CurY;
          end;
          X := Cmd.Args[ArgIdx]; Y := Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          Cp1X := CurX + (2.0 / 3.0) * (X1 - CurX);
          Cp1Y := CurY + (2.0 / 3.0) * (Y1 - CurY);
          Cp2X := X + (2.0 / 3.0) * (X1 - X);
          Cp2Y := Y + (2.0 / 3.0) * (Y1 - Y);
          DoCurveTo(Cp1X, Cp1Y, Cp2X, Cp2Y, X, Y);
          PrevQpX := X1; PrevQpY := Y1;
          CurX := X; CurY := Y;
          PrevCmd := 'T';
        end;
        Continue;
      end;

      't':
      begin
        while ArgIdx + 1 < ArgLen do
        begin
          if PrevCmd in ['Q', 'q', 'T', 't'] then
          begin
            X1 := 2 * CurX - PrevQpX;
            Y1 := 2 * CurY - PrevQpY;
          end
          else
          begin
            X1 := CurX; Y1 := CurY;
          end;
          X := CurX + Cmd.Args[ArgIdx]; Y := CurY + Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          Cp1X := CurX + (2.0 / 3.0) * (X1 - CurX);
          Cp1Y := CurY + (2.0 / 3.0) * (Y1 - CurY);
          Cp2X := X + (2.0 / 3.0) * (X1 - X);
          Cp2Y := Y + (2.0 / 3.0) * (Y1 - Y);
          DoCurveTo(Cp1X, Cp1Y, Cp2X, Cp2Y, X, Y);
          PrevQpX := X1; PrevQpY := Y1;
          CurX := X; CurY := Y;
          PrevCmd := 't';
        end;
        Continue;
      end;

      'A':
      begin
        while ArgIdx + 6 < ArgLen do
        begin
          RX := Cmd.Args[ArgIdx];
          RY := Cmd.Args[ArgIdx + 1];
          XRot := Cmd.Args[ArgIdx + 2];
          LargeArc := Cmd.Args[ArgIdx + 3] <> 0;
          Sweep := Cmd.Args[ArgIdx + 4] <> 0;
          X := Cmd.Args[ArgIdx + 5];
          Y := Cmd.Args[ArgIdx + 6];
          Inc(ArgIdx, 7);
          ArcToBezier(CurX, CurY, RX, RY, XRot, LargeArc, Sweep, X, Y);
          CurX := X; CurY := Y;
        end;
      end;

      'a':
      begin
        while ArgIdx + 6 < ArgLen do
        begin
          RX := Cmd.Args[ArgIdx];
          RY := Cmd.Args[ArgIdx + 1];
          XRot := Cmd.Args[ArgIdx + 2];
          LargeArc := Cmd.Args[ArgIdx + 3] <> 0;
          Sweep := Cmd.Args[ArgIdx + 4] <> 0;
          X := CurX + Cmd.Args[ArgIdx + 5];
          Y := CurY + Cmd.Args[ArgIdx + 6];
          Inc(ArgIdx, 7);
          ArcToBezier(CurX, CurY, RX, RY, XRot, LargeArc, Sweep, X, Y);
          CurX := X; CurY := Y;
        end;
      end;

      'Z', 'z':
      begin
        DoClosePath;
        CurX := StartX;
        CurY := StartY;
      end;
    end;

    PrevCmd := Cmd.Cmd;
  end;
end;

procedure TPixieSvgRendererBase.ComputePathStats(
  Cmds: TPixieSvgPathCmdList; out Stats: TPixieSvgPathStats);
var
  I, ArgIdx, ArgLen: Integer;
  Cmd: TPixieSvgPathCmd;
  CurX, CurY, SubpathStartX, SubpathStartY: Single;
  NewX, NewY: Single;

  procedure RecordSegment(NX, NY: Single);
  begin
    Stats.LastSegStartX := CurX;
    Stats.LastSegStartY := CurY;
    if not Stats.HasSegment then
    begin
      Stats.FirstSegEndX := NX;
      Stats.FirstSegEndY := NY;
      Stats.HasSegment := True;
    end;
    CurX := NX;
    CurY := NY;
  end;

  procedure RecordCurveSegment(NX, NY, TanToX, TanToY, TanFromX, TanFromY: Single);
  begin
    if not Stats.HasSegment then
    begin
      Stats.FirstSegEndX := TanToX;
      Stats.FirstSegEndY := TanToY;
      Stats.HasSegment := True;
    end;
    Stats.LastSegStartX := TanFromX;
    Stats.LastSegStartY := TanFromY;
    CurX := NX;
    CurY := NY;
  end;

begin
  Stats.StartX := 0; Stats.StartY := 0;
  Stats.EndX := 0; Stats.EndY := 0;
  Stats.FirstSegEndX := 0; Stats.FirstSegEndY := 0;
  Stats.LastSegStartX := 0; Stats.LastSegStartY := 0;
  Stats.HasSegment := False;

  CurX := 0; CurY := 0;
  SubpathStartX := 0; SubpathStartY := 0;

  for I := 0 to Cmds.Count - 1 do
  begin
    Cmd := Cmds[I];
    ArgIdx := 0;
    ArgLen := Length(Cmd.Args);

    case Cmd.Cmd of
      'M':
      begin
        if ArgIdx + 1 < ArgLen then
        begin
          NewX := Cmd.Args[ArgIdx]; NewY := Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          if I = 0 then begin Stats.StartX := NewX; Stats.StartY := NewY; end;
          CurX := NewX; CurY := NewY;
          SubpathStartX := NewX; SubpathStartY := NewY;
        end;
        while ArgIdx + 1 < ArgLen do
        begin
          NewX := Cmd.Args[ArgIdx]; NewY := Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          RecordSegment(NewX, NewY);
        end;
      end;
      'm':
      begin
        if ArgIdx + 1 < ArgLen then
        begin
          NewX := CurX + Cmd.Args[ArgIdx];
          NewY := CurY + Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          if I = 0 then begin Stats.StartX := NewX; Stats.StartY := NewY; end;
          CurX := NewX; CurY := NewY;
          SubpathStartX := NewX; SubpathStartY := NewY;
        end;
        while ArgIdx + 1 < ArgLen do
        begin
          NewX := CurX + Cmd.Args[ArgIdx];
          NewY := CurY + Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          RecordSegment(NewX, NewY);
        end;
      end;
      'L', 'T':
      begin
        while ArgIdx + 1 < ArgLen do
        begin
          NewX := Cmd.Args[ArgIdx]; NewY := Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          RecordSegment(NewX, NewY);
        end;
      end;
      'l', 't':
      begin
        while ArgIdx + 1 < ArgLen do
        begin
          NewX := CurX + Cmd.Args[ArgIdx];
          NewY := CurY + Cmd.Args[ArgIdx + 1];
          Inc(ArgIdx, 2);
          RecordSegment(NewX, NewY);
        end;
      end;
      'H':
      begin
        while ArgIdx < ArgLen do
        begin
          NewX := Cmd.Args[ArgIdx]; Inc(ArgIdx);
          RecordSegment(NewX, CurY);
        end;
      end;
      'h':
      begin
        while ArgIdx < ArgLen do
        begin
          NewX := CurX + Cmd.Args[ArgIdx]; Inc(ArgIdx);
          RecordSegment(NewX, CurY);
        end;
      end;
      'V':
      begin
        while ArgIdx < ArgLen do
        begin
          NewY := Cmd.Args[ArgIdx]; Inc(ArgIdx);
          RecordSegment(CurX, NewY);
        end;
      end;
      'v':
      begin
        while ArgIdx < ArgLen do
        begin
          NewY := CurY + Cmd.Args[ArgIdx]; Inc(ArgIdx);
          RecordSegment(CurX, NewY);
        end;
      end;
      'C':
      begin
        while ArgIdx + 5 < ArgLen do
        begin
          NewX := Cmd.Args[ArgIdx + 4]; NewY := Cmd.Args[ArgIdx + 5];
          RecordCurveSegment(NewX, NewY,
            Cmd.Args[ArgIdx], Cmd.Args[ArgIdx + 1],
            Cmd.Args[ArgIdx + 2], Cmd.Args[ArgIdx + 3]);
          Inc(ArgIdx, 6);
        end;
      end;
      'c':
      begin
        while ArgIdx + 5 < ArgLen do
        begin
          NewX := CurX + Cmd.Args[ArgIdx + 4];
          NewY := CurY + Cmd.Args[ArgIdx + 5];
          RecordCurveSegment(NewX, NewY,
            CurX + Cmd.Args[ArgIdx], CurY + Cmd.Args[ArgIdx + 1],
            CurX + Cmd.Args[ArgIdx + 2], CurY + Cmd.Args[ArgIdx + 3]);
          Inc(ArgIdx, 6);
        end;
      end;
      'S', 'Q':
      begin
        while ArgIdx + 3 < ArgLen do
        begin
          NewX := Cmd.Args[ArgIdx + 2]; NewY := Cmd.Args[ArgIdx + 3];
          RecordCurveSegment(NewX, NewY,
            Cmd.Args[ArgIdx], Cmd.Args[ArgIdx + 1],
            Cmd.Args[ArgIdx], Cmd.Args[ArgIdx + 1]);
          Inc(ArgIdx, 4);
        end;
      end;
      's', 'q':
      begin
        while ArgIdx + 3 < ArgLen do
        begin
          NewX := CurX + Cmd.Args[ArgIdx + 2];
          NewY := CurY + Cmd.Args[ArgIdx + 3];
          RecordCurveSegment(NewX, NewY,
            CurX + Cmd.Args[ArgIdx], CurY + Cmd.Args[ArgIdx + 1],
            CurX + Cmd.Args[ArgIdx], CurY + Cmd.Args[ArgIdx + 1]);
          Inc(ArgIdx, 4);
        end;
      end;
      'A':
      begin
        while ArgIdx + 6 < ArgLen do
        begin
          NewX := Cmd.Args[ArgIdx + 5]; NewY := Cmd.Args[ArgIdx + 6];
          Inc(ArgIdx, 7);
          RecordSegment(NewX, NewY);
        end;
      end;
      'a':
      begin
        while ArgIdx + 6 < ArgLen do
        begin
          NewX := CurX + Cmd.Args[ArgIdx + 5];
          NewY := CurY + Cmd.Args[ArgIdx + 6];
          Inc(ArgIdx, 7);
          RecordSegment(NewX, NewY);
        end;
      end;
      'Z', 'z':
      begin
        if (CurX <> SubpathStartX) or (CurY <> SubpathStartY) then
          RecordSegment(SubpathStartX, SubpathStartY);
      end;
    end;
  end;

  Stats.EndX := CurX;
  Stats.EndY := CurY;
end;

// ===========================================================================
// Arc-to-Bezier conversion (SVG spec Appendix F)
// ===========================================================================

procedure TPixieSvgRendererBase.ArcToBezier(X1, Y1, RX, RY,
  XRotation: Single; LargeArc, Sweep: Boolean; X2, Y2: Single);
var
  Phi, CosPhi, SinPhi: Single;
  X1p, Y1p, CxP, CyP, CX, CY: Single;
  Sq, Coeff: Single;
  Theta1, DTheta: Single;
  Segments, Seg: Integer;
  SegAngle: Single;
  T, Alpha: Single;
  Cos1, Sin1, Cos2, Sin2: Single;
  EP1X, EP1Y, EP2X, EP2Y: Single;
  E1X, E1Y, E2X, E2Y: Single;
  Cp1X, Cp1Y, Cp2X, Cp2Y: Single;
  Rx2, Ry2, X1p2, Y1p2, Lambda: Single;
  Dx, Dy: Single;
  N, NX, NY, DX2, DY2: Single;
begin
  // Degenerate cases
  Dx := X2 - X1;
  Dy := Y2 - Y1;
  if (Abs(Dx) < 0.001) and (Abs(Dy) < 0.001) then Exit;

  RX := Abs(RX);
  RY := Abs(RY);
  if (RX < 0.001) or (RY < 0.001) then
  begin
    DoLineTo(X2, Y2);
    Exit;
  end;

  Phi := XRotation * Pi / 180.0;
  CosPhi := Cos(Phi);
  SinPhi := Sin(Phi);

  // Step 1: compute (x1', y1')
  X1p := CosPhi * (X1 - X2) / 2.0 + SinPhi * (Y1 - Y2) / 2.0;
  Y1p := -SinPhi * (X1 - X2) / 2.0 + CosPhi * (Y1 - Y2) / 2.0;

  // Ensure radii are large enough (F.6.6)
  X1p2 := X1p * X1p;
  Y1p2 := Y1p * Y1p;
  Rx2 := RX * RX;
  Ry2 := RY * RY;
  Lambda := X1p2 / Rx2 + Y1p2 / Ry2;
  if Lambda > 1.0 then
  begin
    RX := RX * Sqrt(Lambda);
    RY := RY * Sqrt(Lambda);
    Rx2 := RX * RX;
    Ry2 := RY * RY;
  end;

  // Step 2: compute (cx', cy')
  Sq := (Rx2 * Ry2 - Rx2 * Y1p2 - Ry2 * X1p2) /
        (Rx2 * Y1p2 + Ry2 * X1p2);
  if Sq < 0 then Sq := 0;
  Coeff := Sqrt(Sq);
  if LargeArc = Sweep then
    Coeff := -Coeff;

  CxP := Coeff * (RX * Y1p / RY);
  CyP := Coeff * (-(RY * X1p / RX));

  // Step 3: compute (cx, cy)
  CX := CosPhi * CxP - SinPhi * CyP + (X1 + X2) / 2.0;
  CY := SinPhi * CxP + CosPhi * CyP + (Y1 + Y2) / 2.0;

  // Step 4: compute theta1 and dtheta
  NX := (X1p - CxP) / RX;
  NY := (Y1p - CyP) / RY;
  DX2 := (-X1p - CxP) / RX;
  DY2 := (-Y1p - CyP) / RY;

  N := Sqrt(NX * NX + NY * NY);
  if N < 0.0001 then N := 0.0001;
  Theta1 := ArcCos(EnsureRange(NX / N, -1, 1));
  if NY < 0 then
    Theta1 := -Theta1;

  N := Sqrt((NX * NX + NY * NY) * (DX2 * DX2 + DY2 * DY2));
  if N < 0.0001 then N := 0.0001;
  DTheta := ArcCos(EnsureRange((NX * DX2 + NY * DY2) / N, -1, 1));
  if (NX * DY2 - NY * DX2) < 0 then
    DTheta := -DTheta;

  if Sweep and (DTheta < 0) then
    DTheta := DTheta + 2 * Pi
  else if (not Sweep) and (DTheta > 0) then
    DTheta := DTheta - 2 * Pi;

  // Split into segments of at most 90 degrees
  Segments := Ceil(Abs(DTheta) / (Pi / 2));
  if Segments < 1 then Segments := 1;
  SegAngle := DTheta / Segments;
  Alpha := 4.0 / 3.0 * Tan(SegAngle / 4.0);

  T := Theta1;
  for Seg := 0 to Segments - 1 do
  begin
    Cos1 := Cos(T);
    Sin1 := Sin(T);
    Cos2 := Cos(T + SegAngle);
    Sin2 := Sin(T + SegAngle);

    EP1X := Cos1;
    EP1Y := Sin1;
    EP2X := Cos2;
    EP2Y := Sin2;

    Cp1X := EP1X - Alpha * Sin1;
    Cp1Y := EP1Y + Alpha * Cos1;
    Cp2X := EP2X + Alpha * Sin2;
    Cp2Y := EP2Y - Alpha * Cos2;

    E1X := CosPhi * RX * Cp1X - SinPhi * RY * Cp1Y + CX;
    E1Y := SinPhi * RX * Cp1X + CosPhi * RY * Cp1Y + CY;
    E2X := CosPhi * RX * Cp2X - SinPhi * RY * Cp2Y + CX;
    E2Y := SinPhi * RX * Cp2X + CosPhi * RY * Cp2Y + CY;

    EP2X := CosPhi * RX * Cos2 - SinPhi * RY * Sin2 + CX;
    EP2Y := SinPhi * RX * Cos2 + CosPhi * RY * Sin2 + CY;

    DoCurveTo(E1X, E1Y, E2X, E2Y, EP2X, EP2Y);

    T := T + SegAngle;
  end;
end;

// ===========================================================================
// Path rendering
// ===========================================================================

procedure TPixieSvgRendererBase.RenderPath(Node: Pointer;
  const State: TPixieSvgState);
var
  D: string;
  Cmds: TPixieSvgPathCmdList;
  NeedRestore: Boolean;
  Stats: TPixieSvgPathStats;
  Angle1, Angle2: Single;
begin
  D := GetAttr(Node, 'd');
  if D = '' then Exit;

  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyClipPath(Node);
  ApplyOpacity(State, NeedRestore);

  Cmds := ParsePathData(D);
  try
    EmitPathCommands(Cmds);
    ComputePathStats(Cmds, Stats);
  finally
    Cmds.Free;
  end;

  if Stats.HasSegment then
  begin
    Angle1 := ArcTan2(Stats.FirstSegEndY - Stats.StartY,
      Stats.FirstSegEndX - Stats.StartX) * 180 / Pi;
    Angle2 := ArcTan2(Stats.EndY - Stats.LastSegStartY,
      Stats.EndX - Stats.LastSegStartX) * 180 / Pi;
  end
  else
  begin
    Angle1 := 0;
    Angle2 := 0;
  end;

  DoFillAndStroke(State);
  RenderMarkers(Node, State, Stats.StartX, Stats.StartY,
    Stats.EndX, Stats.EndY, Angle1, Angle2);
  if NeedRestore then DoEndOpacity;
  DoRestoreState;
end;

// ===========================================================================
// Marker rendering (marker-start, marker-end, marker-mid)
// ===========================================================================

procedure TPixieSvgRendererBase.RenderMarkerAt(const MarkerId: string;
  X, Y, Angle, StrokeW: Single; const State: TPixieSvgState;
  IsStart: Boolean);
var
  MarkerNode: Pointer;
  MarkerEl: TDOMElement;
  VbStr: string;
  VbX, VbY, VbW, VbH: Single;
  MW, MH, RefX, RefY, SX, SY: Single;
  OrientStr, UnitsStr: string;
  M: TPixieSvgMatrix;
  MarkerState: TPixieSvgState;
  RotAngle: Single;
  SaveFill, SaveStroke: TPixieWebColor;
  SaveHasFill, SaveHasStroke: Boolean;
begin
  if (FIdMap = nil) or (MarkerId = '') then Exit;
  if not FIdMap.TryGetValue(MarkerId, MarkerNode) then Exit;

  MarkerEl := TDOMElement(MarkerNode);
  if LowerCase(PixieDomToStr(MarkerEl.TagName)) <> 'marker' then Exit;

  // Parse marker attributes
  MW := ParseSvgFloat(GetAttr(MarkerNode, 'markerWidth', '3'));
  MH := ParseSvgFloat(GetAttr(MarkerNode, 'markerHeight', '3'));
  RefX := ParseSvgFloat(GetAttr(MarkerNode, 'refX', '0'));
  RefY := ParseSvgFloat(GetAttr(MarkerNode, 'refY', '0'));
  OrientStr := GetAttr(MarkerNode, 'orient', 'auto');
  UnitsStr := GetAttr(MarkerNode, 'markerUnits', 'strokeWidth');

  VbStr := GetAttr(MarkerNode, 'viewBox');
  ParseViewBox(VbStr, VbX, VbY, VbW, VbH);
  if (VbStr <> '') and (VbW > 0) and (VbH > 0) then
  begin
    SX := MW / VbW;
    SY := MH / VbH;
  end
  else
  begin
    SX := 1;
    SY := 1;
  end;

  // Build transform: T(vertex) * R(angle) * S(strokeWidth) *
  //   T(-refVp) * S(vb-to-viewport) * T(-vbOrigin)
  // where refVp = (refX - vbX) * sx, (refY - vbY) * sy
  M := TPixieSvgMatrix.CreateTranslate(X, Y);
  if (OrientStr = 'auto') or (OrientStr = 'auto-start-reverse') then
  begin
    RotAngle := Angle;
    // auto-start-reverse: start marker is rotated 180° so the arrow points
    // back along the path direction; end/mid markers behave like 'auto'.
    if IsStart and (OrientStr = 'auto-start-reverse') then
      RotAngle := RotAngle + 180;
    M := M.Multiply(TPixieSvgMatrix.CreateRotate(RotAngle));
  end;
  if UnitsStr = 'strokeWidth' then
    M := M.Multiply(TPixieSvgMatrix.CreateScale(StrokeW, StrokeW));
  M := M.Multiply(TPixieSvgMatrix.CreateTranslate(
    -(RefX - VbX) * SX, -(RefY - VbY) * SY));
  M := M.Multiply(TPixieSvgMatrix.CreateScale(SX, SY));
  M := M.Multiply(TPixieSvgMatrix.CreateTranslate(-VbX, -VbY));

  DoSaveState;
  DoSetTransform(M);

  // Establish SVG 2 context paint so fill/stroke:context-stroke/context-fill
  // inside the marker resolve to the referencing element's paint. Save/restore
  // to support nested markers.
  SaveFill := FContextFillColor;
  SaveStroke := FContextStrokeColor;
  SaveHasFill := FHasContextFill;
  SaveHasStroke := FHasContextStroke;
  FContextFillColor := State.FillColor;
  FContextStrokeColor := State.StrokeColor;
  FHasContextFill := State.HasFill and (State.FillGradientId = '');
  FHasContextStroke := State.HasStroke and (State.StrokeGradientId = '');
  try
    // Render marker children — per SVG spec, marker contents inherit from the
    // marker element itself (its DOM position), not from the referencing shape
    MarkerState := InheritState(MarkerNode, FInitState);
    RenderGroup(MarkerNode, MarkerState);
  finally
    FContextFillColor := SaveFill;
    FContextStrokeColor := SaveStroke;
    FHasContextFill := SaveHasFill;
    FHasContextStroke := SaveHasStroke;
  end;

  DoRestoreState;
end;

procedure TPixieSvgRendererBase.RenderMarkers(Node: Pointer;
  const State: TPixieSvgState;
  X1, Y1, X2, Y2, Angle1, Angle2: Single);
var
  MarkerId: string;
  SW: Single;
begin
  if (State.MarkerStart = '') and (State.MarkerMid = '') and
     (State.MarkerEnd = '') then
    Exit;

  SW := State.StrokeWidth;

  // marker-start
  if State.MarkerStart <> '' then
  begin
    MarkerId := ExtractUrlId(State.MarkerStart);
    if MarkerId <> '' then
      RenderMarkerAt(MarkerId, X1, Y1, Angle1, SW, State, True);
  end;

  // marker-end
  if State.MarkerEnd <> '' then
  begin
    MarkerId := ExtractUrlId(State.MarkerEnd);
    if MarkerId <> '' then
      RenderMarkerAt(MarkerId, X2, Y2, Angle2, SW, State);
  end;
end;

// ===========================================================================
// Text rendering — handles <tspan> nesting (calls DoRenderTextRun)
// ===========================================================================

function TPixieSvgRendererBase.CollectAllText(Node: Pointer): string;
var
  Builder: TStringBuilder;

  procedure WalkInto(N: Pointer);
  var
    Child: TDOMNode;
    Tag: string;
  begin
    Child := TDOMNode(N).FirstChild;
    while Child <> nil do
    begin
      if Child.NodeType = xntText then
        Builder.Append(PixieDomToStr(Child.NodeValue))
      else if Child.NodeType = xntElement then
      begin
        Tag := LowerCase(PixieDomToStr(TDOMElement(Child).TagName));
        if (Tag <> 'desc') and (Tag <> 'title') and (Tag <> 'metadata') then
          WalkInto(Child);
      end;
      Child := Child.NextSibling;
    end;
  end;

begin
  Builder := TStringBuilder.Create;
  try
    WalkInto(Node);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function TPixieSvgRendererBase.NormalizeTextNode(const Raw: string;
  Preserve: Boolean): string;
var
  I: Integer;
  PrevSpace: Boolean;
  Ch: Char;
begin
  if Preserve then
  begin
    SetLength(Result, Length(Raw));
    for I := 1 to Length(Raw) do
    begin
      Ch := Raw[I];
      if (Ch = #9) or (Ch = #10) or (Ch = #13) then
        Result[I] := ' '
      else
        Result[I] := Ch;
    end;
    Exit;
  end;
  Result := '';
  PrevSpace := False;
  for I := 1 to Length(Raw) do
  begin
    Ch := Raw[I];
    if (Ch = #10) or (Ch = #13) then Continue;
    if Ch = #9 then Ch := ' ';
    if Ch = ' ' then
    begin
      if PrevSpace then Continue;
      PrevSpace := True;
    end
    else
      PrevSpace := False;
    Result := Result + Ch;
  end;
  Result := Trim(Result);
end;

function TPixieSvgRendererBase.MeasureTextChunkWidth(Node: Pointer;
  const State: TPixieSvgState): Single;
var
  Child: TDOMNode;
  ChildState: TPixieSvgState;
  TextContent: string;
begin
  Result := 0;
  Child := TDOMNode(Node).FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = xntText then
    begin
      TextContent := NormalizeTextNode(PixieDomToStr(Child.NodeValue),
        State.XmlSpacePreserve);
      if TextContent <> '' then
        Result := Result + DoMeasureTextRun(TextContent, State);
    end
    else if (Child.NodeType = xntElement) and
            (LowerCase(PixieDomToStr(TDOMElement(Child).TagName)) = 'tspan') then
    begin
      // A tspan with explicit x= starts a new anchored chunk and is measured
      // separately. Otherwise it continues this chunk.
      if GetAttr(Child, 'x') = '' then
      begin
        ChildState := InheritState(Child, State);
        Result := Result + MeasureTextChunkWidth(Child, ChildState);
      end;
    end;
    Child := Child.NextSibling;
  end;
end;

// Renders text content character-by-character using per-character x/y
// position arrays. Used for SVGs generated by tools like Inkscape/LaTeX
// that encode spacing via individual glyph positions instead of space
// characters.
procedure TPixieSvgRendererBase.RenderTextPositioned(Node: Pointer;
  const State: TPixieSvgState;
  const XPositions, YPositions: TPixieSingleArray;
  DxOffset, DyOffset: Single; var X, Y: Single);
var
  AllText, CharStr: string;
  CharIdx, CharStart, I: Integer;
  CharX, CharY, LastCharW: Single;
  CodePoint: UInt32;
begin
  AllText := CollectAllText(Node);
  if AllText = '' then Exit;

  CharIdx := 1;
  I := 0;
  CharX := 0;
  CharY := Y;
  while (CharIdx <= Length(AllText)) and (I < Length(XPositions)) do
  begin
    CharStart := CharIdx;
    CodePoint := ReadUtf8Char(AllText, CharIdx);
    if CodePoint = 0 then Break;
    CharStr := Copy(AllText, CharStart, CharIdx - CharStart);
    CharX := XPositions[I] + DxOffset;
    if I < Length(YPositions) then
      CharY := YPositions[I] + DyOffset
    else if Length(YPositions) > 0 then
      CharY := YPositions[High(YPositions)] + DyOffset
    else
      CharY := Y + DyOffset;
    DoRenderTextRun(CharStr, CharX, CharY, State);
    Inc(I);
  end;

  // Any remaining characters beyond the position list flow naturally
  if CharIdx <= Length(AllText) then
  begin
    LastCharW := DoMeasureTextRun(CharStr, State);
    CharStr := Copy(AllText, CharIdx, MaxInt);
    DoRenderTextRun(CharStr, CharX + LastCharW, CharY, State);
    X := CharX + LastCharW + DoMeasureTextRun(CharStr, State);
  end
  else if I > 0 then
    X := CharX + DoMeasureTextRun(CharStr, State)
  else
    X := 0;
  Y := CharY;
end;

procedure TPixieSvgRendererBase.RenderTextChunkContents(Node: Pointer;
  const State: TPixieSvgState; var X, Y: Single);
var
  Child: TDOMNode;
  ChildState: TPixieSvgState;
  XStr, YStr, DxStr, DyStr: string;
  TextContent: string;
  NewX, NewY, DxOff, DyOff: Single;
  XPositions, YPositions: TPixieSingleArray;
begin
  Child := TDOMNode(Node).FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = xntText then
    begin
      TextContent := NormalizeTextNode(PixieDomToStr(Child.NodeValue),
        State.XmlSpacePreserve);
      if TextContent <> '' then
      begin
        DoRenderTextRun(TextContent, X, Y, State);
        X := X + DoMeasureTextRun(TextContent, State);
      end;
    end
    else if (Child.NodeType = xntElement) and
            (LowerCase(PixieDomToStr(TDOMElement(Child).TagName)) = 'tspan') then
    begin
      ChildState := InheritState(Child, State);
      // baseline-shift: offset Y for this tspan, restore after
      Y := Y + ChildState.BaselineShift;
      XStr := GetAttr(Child, 'x');
      YStr := GetAttr(Child, 'y');
      DxStr := GetAttr(Child, 'dx');
      DyStr := GetAttr(Child, 'dy');
      // dx/dy in em units resolve against the tspan's own font size, which
      // is the inherited ChildState — Visio exports use dy="1.233em" on
      // each wrapped line to step down by one line height.
      if XStr <> '' then
      begin
        XPositions := ParseSvgFloatList(XStr);
        if Length(XPositions) > 1 then
        begin
          // Per-character x-positioning (Inkscape/LaTeX SVGs encode spacing
          // via individual glyph positions instead of space characters)
          if YStr <> '' then
            YPositions := ParseSvgFloatList(YStr)
          else
          begin
            SetLength(YPositions, 1);
            YPositions[0] := Y;
          end;
          DxOff := 0;
          DyOff := 0;
          if DxStr <> '' then DxOff := ParseSvgLengthEm(DxStr, ChildState.FontSize);
          if DyStr <> '' then DyOff := ParseSvgLengthEm(DyStr, ChildState.FontSize);
          RenderTextPositioned(Child, ChildState, XPositions, YPositions,
            DxOff, DyOff, X, Y);
        end
        else
        begin
          // New anchored chunk (single x value)
          if Length(XPositions) > 0 then
            NewX := XPositions[0]
          else
            NewX := 0;
          if YStr <> '' then NewY := ParseSvgLengthEm(YStr, ChildState.FontSize)
          else NewY := Y;
          if DxStr <> '' then NewX := NewX + ParseSvgLengthEm(DxStr, ChildState.FontSize);
          if DyStr <> '' then NewY := NewY + ParseSvgLengthEm(DyStr, ChildState.FontSize);
          RenderTextChunk(Child, ChildState, NewX, NewY);
          // SVG "current text position" carries forward — siblings without
          // their own x=/y= continue from where this chunk ended (including
          // any internal y/dy updates inside the chunk).
          X := NewX;
          Y := NewY;
        end;
      end
      else
      begin
        // Continues the current anchored chunk
        if YStr <> '' then Y := ParseSvgLengthEm(YStr, ChildState.FontSize);
        if DxStr <> '' then X := X + ParseSvgLengthEm(DxStr, ChildState.FontSize);
        if DyStr <> '' then Y := Y + ParseSvgLengthEm(DyStr, ChildState.FontSize);
        RenderTextChunkContents(Child, ChildState, X, Y);
      end;
      Y := Y - ChildState.BaselineShift;
    end;
    Child := Child.NextSibling;
  end;
end;

// X, Y are in/out: on entry they hold the chunk's anchor position; on exit
// they hold the pen position after the chunk (caller propagates this as the
// SVG "current text position" for subsequent siblings).
procedure TPixieSvgRendererBase.RenderTextChunk(Node: Pointer;
  const State: TPixieSvgState; var X, Y: Single);
var
  ChunkWidth: Single;
begin
  // Pre-measure the entire anchored chunk so text-anchor (middle/right) can
  // offset the start position once. Without this, runs from font changes
  // (mixed-font tspans) get centered individually and overlap.
  ChunkWidth := MeasureTextChunkWidth(Node, State);
  if State.TextAnchor = taCenter then
    X := X - ChunkWidth / 2
  else if State.TextAnchor = taRight then
    X := X - ChunkWidth;

  RenderTextChunkContents(Node, State, X, Y);
end;

procedure TPixieSvgRendererBase.RenderText(Node: Pointer;
  const State: TPixieSvgState);
var
  X, Y: Single;
  DxStr, DyStr: string;
  NeedRestore: Boolean;
begin
  if Trim(CollectAllText(Node)) = '' then Exit;

  X := ParseSvgLengthEm(GetAttr(Node, 'x', '0'), State.FontSize);
  Y := ParseSvgLengthEm(GetAttr(Node, 'y', '0'), State.FontSize);
  DxStr := GetAttr(Node, 'dx');
  DyStr := GetAttr(Node, 'dy');
  if DxStr <> '' then X := X + ParseSvgLengthEm(DxStr, State.FontSize);
  if DyStr <> '' then Y := Y + ParseSvgLengthEm(DyStr, State.FontSize);

  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyClipPath(Node);
  ApplyOpacity(State, NeedRestore);

  RenderTextChunk(Node, State, X, Y);

  if NeedRestore then DoEndOpacity;
  DoRestoreState;
end;

// ===========================================================================
// Image rendering
// ===========================================================================

procedure TPixieSvgRendererBase.RenderImage(Node: Pointer;
  const State: TPixieSvgState);
var
  X, Y, W, H: Single;
  HrefStr: string;
  NeedRestore, NeedMaskRestore: Boolean;
begin
  X := ParseSvgFloat(GetAttr(Node, 'x', '0'));
  Y := ParseSvgFloat(GetAttr(Node, 'y', '0'));
  W := ParseSvgFloat(GetAttr(Node, 'width', '0'));
  H := ParseSvgFloat(GetAttr(Node, 'height', '0'));

  HrefStr := GetHref(Node);
  if HrefStr = '' then Exit;
  if (W <= 0) or (H <= 0) then Exit;

  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyClipPath(Node);
  ApplyMask(Node, NeedMaskRestore);
  ApplyOpacity(State, NeedRestore);

  DoDrawImage(HrefStr, X, Y, W, H);

  if NeedRestore then DoEndOpacity;
  if NeedMaskRestore then DoEndMask;
  DoRestoreState;
end;

// ===========================================================================
// Element rendering (single-node dispatch)
// ===========================================================================

procedure TPixieSvgRendererBase.RenderElement(Node: Pointer;
  const State: TPixieSvgState);
var
  TagName, DisplayStr: string;
  IsGroup, NeedRestore, NeedMaskRestore: Boolean;
begin
  // SVG display="none" prevents rendering of the element and its entire subtree.
  // Check attribute, inline style, and CSS <style> resolved styles.
  DisplayStr := GetAttr(Node, 'display');
  if DisplayStr = '' then
    DisplayStr := ParseStyleAttribute(GetAttr(Node, 'style'), 'display');
  if DisplayStr = '' then
    DisplayStr := ParseStyleAttribute(ResolveNodeStyle(Node), 'display');
  if DisplayStr = 'none' then
    Exit;

  TagName := LowerCase(PixieDomToStr(TDOMElement(Node).TagName));

  IsGroup := (TagName = 'g') or (TagName = 'symbol') or (TagName = 'a');

  if IsGroup then
  begin
    DoSaveState;
    ApplyNodeTransform(Node);
    ApplyClipPath(Node);
    ApplyMask(Node, NeedMaskRestore);
    ApplyOpacity(State, NeedRestore);
    RenderGroup(Node, State);
    if NeedRestore then DoEndOpacity;
    if NeedMaskRestore then DoEndMask;
    DoRestoreState;
  end
  else if TagName = 'svg' then
    RenderNestedSvg(Node, State)
  else if TagName = 'rect' then
    RenderRect(Node, State)
  else if TagName = 'circle' then
    RenderCircle(Node, State)
  else if TagName = 'ellipse' then
    RenderEllipse(Node, State)
  else if TagName = 'line' then
    RenderLine(Node, State)
  else if TagName = 'polyline' then
    RenderPolyline(Node, State, False)
  else if TagName = 'polygon' then
    RenderPolyline(Node, State, True)
  else if TagName = 'path' then
    RenderPath(Node, State)
  else if TagName = 'text' then
    RenderText(Node, State)
  else if TagName = 'image' then
    RenderImage(Node, State)
  else if TagName = 'use' then
    RenderUse(Node, State)
  else if TagName = 'switch' then
    RenderSwitch(Node, State)
  else if TagName = 'defs' then
    CollectDefs(Node)
  else if TagName = 'lineargradient' then
    ParseGradient(Node, False)
  else if TagName = 'radialgradient' then
    ParseGradient(Node, True);
end;

// ===========================================================================
// <use> element rendering
// ===========================================================================

procedure TPixieSvgRendererBase.RenderUse(Node: Pointer;
  const State: TPixieSvgState);
const
  Eps = 0.0001;
var
  HrefStr, TargetId, TagName: string;
  Target: Pointer;
  X, Y, W, H: Single;
  VbX, VbY, VbW, VbH: Single;
  SX, SY: Single;
  NeedRestore, NeedMaskRestore: Boolean;
  M: TPixieSvgMatrix;
  TargetState: TPixieSvgState;
begin
  if FIdMap = nil then Exit;

  // Recursion guard
  if FUseDepth >= 10 then Exit;

  // Resolve href
  HrefStr := GetHref(Node);
  if (HrefStr = '') or (HrefStr[1] <> '#') then Exit;

  TargetId := Copy(HrefStr, 2, MaxInt);
  if not FIdMap.TryGetValue(TargetId, Target) then Exit;

  // Get x/y offset
  X := ParseSvgFloat(GetAttr(Node, 'x', '0'));
  Y := ParseSvgFloat(GetAttr(Node, 'y', '0'));

  DoSaveState;

  // Apply <use> element's own transform, then x/y translation
  ApplyNodeTransform(Node);
  ApplyClipPath(Node);
  ApplyMask(Node, NeedMaskRestore);
  ApplyOpacity(State, NeedRestore);
  if (Abs(X) > Eps) or (Abs(Y) > Eps) then
  begin
    M := TPixieSvgMatrix.CreateTranslate(X, Y);
    DoSetTransform(M);
  end;

  // Merge target's own style attributes on top of the <use> state
  TargetState := InheritState(Target, State);
  Inc(FUseDepth);
  try
    TagName := LowerCase(PixieDomToStr(TDOMElement(Target).TagName));
    if TagName = 'symbol' then
    begin
      // Per SVG spec, <symbol> referenced by <use> is treated as an inline
      // <svg>: width/height come from <use>, viewBox from <symbol>.
      W := ParseSvgFloat(GetAttr(Node, 'width', '0'));
      H := ParseSvgFloat(GetAttr(Node, 'height', '0'));
      ParseViewBox(GetAttr(Target, 'viewBox'), VbX, VbY, VbW, VbH);

      // Apply viewBox-to-viewport scaling (preserveAspectRatio not yet
      // honoured — always stretch, matching the common 'none' value)
      if (VbW > Eps) and (VbH > Eps) and (W > Eps) and (H > Eps) then
      begin
        SX := W / VbW;
        SY := H / VbH;
        if (Abs(SX - 1) > Eps) or (Abs(SY - 1) > Eps) then
        begin
          M := TPixieSvgMatrix.CreateScale(SX, SY);
          DoSetTransform(M);
        end;
        if (Abs(VbX) > Eps) or (Abs(VbY) > Eps) then
        begin
          M := TPixieSvgMatrix.CreateTranslate(-VbX, -VbY);
          DoSetTransform(M);
        end;
      end;

      // Render symbol children directly — the viewport transform is
      // already applied, so skip the group-level handling in RenderElement
      RenderGroup(Target, TargetState);
    end
    else
      RenderElement(Target, TargetState);
  finally
    Dec(FUseDepth);
  end;

  if NeedRestore then DoEndOpacity;
  if NeedMaskRestore then DoEndMask;
  DoRestoreState;
end;

// ===========================================================================
// Group rendering (recursive tree walk)
// ===========================================================================

procedure TPixieSvgRendererBase.RenderGroup(Node: Pointer;
  const State: TPixieSvgState);
var
  Child: TDOMNode;
  ChildState: TPixieSvgState;
begin
  Child := TDOMNode(Node).FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = xntElement then
    begin
      ChildState := InheritState(Child, State);
      RenderElement(Child, ChildState);
    end;

    Child := Child.NextSibling;
  end;
end;

// ===========================================================================
// <switch> conditional processing
// ===========================================================================

procedure TPixieSvgRendererBase.RenderSwitch(Node: Pointer;
  const State: TPixieSvgState);
var
  Child, Fallback: TDOMNode;
  ChildState: TPixieSvgState;
  NeedRestore: Boolean;
  Lang: string;

  function LanguageMatches(const LangAttr: string): Boolean;
  var
    P: Integer;
    Tag: string;
  begin
    // SVG spec: systemLanguage is a comma-separated list of BCP 47 tags.
    // Match if any tag equals or is a prefix of FSystemLanguage.
    Result := False;
    P := 1;
    while P <= Length(LangAttr) do
    begin
      while (P <= Length(LangAttr)) and CharInSet(LangAttr[P], [' ', ',']) do Inc(P);
      if P > Length(LangAttr) then Break;
      Tag := '';
      while (P <= Length(LangAttr)) and not CharInSet(LangAttr[P], [' ', ',']) do
      begin
        Tag := Tag + LangAttr[P];
        Inc(P);
      end;
      Tag := LowerCase(Tag);
      if (Tag = FSystemLanguage) or
         ((Length(Tag) < Length(FSystemLanguage)) and
          (Copy(FSystemLanguage, 1, Length(Tag) + 1) = Tag + '-')) then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;

begin
  // SVG <switch> renders the first child whose systemLanguage matches.
  // If none match, render the first child with no conditional attributes.
  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyClipPath(Node);
  ApplyOpacity(State, NeedRestore);

  Fallback := nil;
  Child := TDOMNode(Node).FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = xntElement then
    begin
      Lang := GetAttr(Child, 'systemLanguage');
      if Lang <> '' then
      begin
        if LanguageMatches(Lang) then
        begin
          ChildState := InheritState(Child, State);
          RenderElement(Child, ChildState);
          Fallback := nil;
          Break;
        end;
      end
      else if (Fallback = nil) and
              (GetAttr(Child, 'requiredFeatures') = '') and
              (GetAttr(Child, 'requiredExtensions') = '') then
        Fallback := Child;
    end;
    Child := Child.NextSibling;
  end;

  if Fallback <> nil then
  begin
    ChildState := InheritState(Fallback, State);
    RenderElement(Fallback, ChildState);
  end;

  if NeedRestore then DoEndOpacity;
  DoRestoreState;
end;

// ===========================================================================
// Nested <svg> element
// ===========================================================================
// Establishes a new viewport at (x, y) of size width/height with its own
// viewBox coordinate system. Must not be handled like <g> — Visio fallback
// images have an inner <svg viewBox="0 0 1028 1072" width="11"> whose
// children would otherwise draw at raw viewBox scale.

procedure TPixieSvgRendererBase.RenderNestedSvg(Node: Pointer;
  const State: TPixieSvgState);
const
  Eps = 0.0001;
var
  X, Y, W, H: Single;
  VbX, VbY, VbW, VbH: Single;
  OverflowStr: string;
  SX, SY: Single;
  M: TPixieSvgMatrix;
  NeedRestore: Boolean;
  DoClip: Boolean;
begin
  X := ParseSvgFloat(GetAttr(Node, 'x', '0'));
  Y := ParseSvgFloat(GetAttr(Node, 'y', '0'));
  W := ParseSvgFloat(GetAttr(Node, 'width', '0'));
  H := ParseSvgFloat(GetAttr(Node, 'height', '0'));

  ParseViewBox(GetAttr(Node, 'viewBox'), VbX, VbY, VbW, VbH);

  // Nested <svg> clips to its viewport unless overflow=visible. When the
  // dimensions are missing there's nothing to clip to, so treat it as
  // visible regardless of the attribute.
  OverflowStr := LowerCase(Trim(GetAttr(Node, 'overflow')));
  if OverflowStr = '' then
    OverflowStr := ParseStyleAttribute(ResolveNodeStyle(Node), 'overflow');
  DoClip := (OverflowStr <> 'visible') and (W > 0) and (H > 0);

  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyClipPath(Node);
  ApplyOpacity(State, NeedRestore);

  if (Abs(X) > Eps) or (Abs(Y) > Eps) then
  begin
    M := TPixieSvgMatrix.CreateTranslate(X, Y);
    DoSetTransform(M);
  end;

  // Clip must happen before the viewBox scale so the rect is in parent
  // user-space coordinates.
  if DoClip then
  begin
    DoMoveTo(0, 0);
    DoLineTo(W, 0);
    DoLineTo(W, H);
    DoLineTo(0, H);
    DoClosePath;
    DoClipPath(False);
  end;

  // preserveAspectRatio is not honoured — always stretch per-axis, matching
  // Visio's common 'none' value. Fix this when a Pixie test needs 'meet'.
  if (VbW > Eps) and (VbH > Eps) and (W > Eps) and (H > Eps) then
  begin
    SX := W / VbW;
    SY := H / VbH;
    if (Abs(SX - 1) > Eps) or (Abs(SY - 1) > Eps) then
    begin
      M := TPixieSvgMatrix.CreateScale(SX, SY);
      DoSetTransform(M);
    end;
    if (Abs(VbX) > Eps) or (Abs(VbY) > Eps) then
    begin
      M := TPixieSvgMatrix.CreateTranslate(-VbX, -VbY);
      DoSetTransform(M);
    end;
  end;

  RenderGroup(Node, State);

  if NeedRestore then DoEndOpacity;
  DoRestoreState;
end;

// ===========================================================================
// Public API
// ===========================================================================

function TPixieSvgRendererBase.ParseSvg(Data: Pointer; Size: Integer;
  out W, H: Single): Boolean;
var
  Doc: TXMLDocument;
  SvgRoot: TDOMElement;
  MemStream: TMemoryStream;
  WidthStr, HeightStr, OverflowStr: string;
  SvgStr: AnsiString;
  DtdStart, DtdEnd: Integer;
begin
  Result := False;
  W := 0;
  H := 0;

  if (Data = nil) or (Size <= 0) then Exit;

  // Free any previous document
  ClearDocument;

  // Strip <!DOCTYPE...> declaration — FPC XML parser fails on external DTDs.
  // Before stripping, extract <!ENTITY> definitions from any internal subset
  // and expand entity references in the document body.
  SetString(SvgStr, PAnsiChar(Data), Size);
  DtdStart := Pos(AnsiString('<!DOCTYPE'), SvgStr);
  if DtdStart > 0 then
  begin
    // Find closing '>' — handle nested brackets for internal subsets
    DtdEnd := DtdStart + 9;
    while (DtdEnd <= Length(SvgStr)) and (SvgStr[DtdEnd] <> '>') do
    begin
      if SvgStr[DtdEnd] = '[' then
        while (DtdEnd <= Length(SvgStr)) and (SvgStr[DtdEnd] <> ']') do
          Inc(DtdEnd);
      Inc(DtdEnd);
    end;

    // Extract and expand internal entities before removing DOCTYPE
    ExpandDoctypeEntities(SvgStr, DtdStart, DtdEnd);
    Delete(SvgStr, DtdStart, DtdEnd - DtdStart + 1);
  end;

  MemStream := TMemoryStream.Create;
  try
    if Length(SvgStr) > 0 then
      MemStream.Write(SvgStr[1], Length(SvgStr));
    MemStream.Position := 0;

    Doc := nil;
    try
      PixieReadXMLFile(Doc, MemStream);
    except
      Exit;
    end;

    if Doc = nil then Exit;
    SvgRoot := Doc.DocumentElement;
    if SvgRoot = nil then
    begin
      Doc.Free;
      Exit;
    end;

    ParseViewBox(PixieDomToStr(SvgRoot.GetAttribute('viewBox')),
      FViewBoxX, FViewBoxY, FViewBoxW, FViewBoxH);

    // Parse width/height, fall back to viewBox.
    // Percentage width/height on the outermost <svg> resolve against the
    // SVG viewport. When the renderer has no caller-supplied viewport (e.g.
    // SVG used as an <img> source), percentages contribute no intrinsic
    // dimension — fall through to the viewBox so the image keeps its
    // natural aspect ratio.
    WidthStr := Trim(PixieDomToStr(SvgRoot.GetAttribute('width')));
    HeightStr := Trim(PixieDomToStr(SvgRoot.GetAttribute('height')));

    if (WidthStr <> '') and (WidthStr[Length(WidthStr)] <> '%') then
      W := ParseSvgFloat(WidthStr)
    else
      W := 0;
    if (HeightStr <> '') and (HeightStr[Length(HeightStr)] <> '%') then
      H := ParseSvgFloat(HeightStr)
    else
      H := 0;

    // Track whether the SVG has a natural size (both width AND height
    // explicitly set). When only viewBox is present, callers may treat the
    // image as having only an aspect ratio.
    FHasExplicitSize := (W > 0) and (H > 0);

    // Determine overflow: browsers default to visible for the outermost
    // <svg>, only clipping when overflow="hidden" is explicitly set
    OverflowStr := LowerCase(Trim(
      PixieDomToStr(SvgRoot.GetAttribute('overflow'))));
    if OverflowStr = 'hidden' then
      FOverflowVisible := False
    else
      FOverflowVisible := True;

    // If only one dimension given, derive the other from the viewBox aspect
    // ratio. This must run before the plain viewBox fallback below, otherwise
    // a width-only (or height-only) <svg> would take the missing dimension
    // verbatim from the viewBox (e.g. width="36" viewBox="0 0 512 512" would
    // become 36x512 instead of the correct 36x36).
    if (W <= 0) and (H > 0) and (FViewBoxW > 0) and (FViewBoxH > 0) then
      W := H * FViewBoxW / FViewBoxH;
    if (H <= 0) and (W > 0) and (FViewBoxW > 0) and (FViewBoxH > 0) then
      H := W * FViewBoxH / FViewBoxW;

    // Fall back to viewBox dimensions when neither width nor height could be
    // parsed (e.g. malformed values like width="px" with no numeric part)
    if (W <= 0) and (FViewBoxW > 0) then W := FViewBoxW;
    if (H <= 0) and (FViewBoxH > 0) then H := FViewBoxH;

    // If still missing one dimension and no viewBox, match the other
    if (W <= 0) and (H > 0) then W := H;
    if (H <= 0) and (W > 0) then H := W;

    // Last resort: default to 300x150 (SVG spec default)
    if W <= 0 then W := 300;
    if H <= 0 then H := 150;

    if FViewBoxW <= 0 then FViewBoxW := W;
    if FViewBoxH <= 0 then FViewBoxH := H;

    // Initialise default state
    FInitState.FillColor := TPixieWebColor.Black;
    FInitState.StrokeColor := TPixieWebColor.Black;
    FInitState.Color := TPixieWebColor.Black;
    FInitState.StrokeWidth := 1;
    FInitState.LineCap := lcButt;
    FInitState.LineJoin := ljMiter;
    FInitState.Opacity := 1.0;
    FInitState.FillOpacity := 1.0;
    FInitState.StrokeOpacity := 1.0;
    FInitState.HasFill := True;
    FInitState.HasStroke := False;
    FInitState.EvenOddFill := False;
    FInitState.FontFamily := 'sans-serif';
    FInitState.FontSize := 16;
    FInitState.FontWeight := 400;
    FInitState.FontItalic := False;
    FInitState.LetterSpacing := 0;
    FInitState.TextAnchor := taLeft;
    FInitState.TextDecoration := TextDecorationLineNone;
    FInitState.FillGradientId := '';
    FInitState.StrokeGradientId := '';
    FInitState.BlendMode := bmNormal;
    FInitState.StrokeBeforeFill := False;
    FInitState.BaselineShift := 0;
    SetLength(FInitState.DashArray, 0);
    FInitState.DashOffset := 0;
    FSystemLanguage := 'en';

    // Store document for RenderDocument
    FDoc := Doc;
    FSvgRoot := SvgRoot;

    // Build ID map and pre-collect gradients (single tree walk).
    // Must run before InheritState on the root so that the style map
    // is populated and the root's class attribute can be resolved.
    BuildIdMap(SvgRoot);

    // Inherit state from the root SVG element
    FInitState := InheritState(SvgRoot, FInitState);

    Result := True;
  finally
    MemStream.Free;
  end;
end;

procedure TPixieSvgRendererBase.SetViewport(AWidth, AHeight: Single);
begin
  FViewBoxW := AWidth;
  FViewBoxH := AHeight;
end;

function TPixieSvgRendererBase.HasExplicitSize: Boolean;
begin
  Result := FHasExplicitSize;
end;

function TPixieSvgRendererBase.GetAspectRatio: Single;
begin
  if FViewBoxH > 0 then
    Result := FViewBoxW / FViewBoxH
  else
    Result := 0;
end;

procedure TPixieSvgRendererBase.SetCurrentColor(AColor: TPixieWebColor);
begin
  if FInitState.Color = AColor then Exit;
  FInitState.Color := AColor;
  // Re-resolve the root SVG's inherited state so paint attributes that
  // reference currentColor (e.g. <svg fill="currentColor">) pick up the
  // new color. ParseSvg ran InheritState on the root with the default
  // (black) initial color; without this re-run the cached FillColor stays
  // at black and propagates to every child.
  if FSvgRoot <> nil then
    FInitState := InheritState(FSvgRoot, FInitState);
end;

procedure TPixieSvgRendererBase.RenderDocument;
begin
  if FSvgRoot = nil then Exit;
  RenderGroup(FSvgRoot, FInitState);
end;

end.
