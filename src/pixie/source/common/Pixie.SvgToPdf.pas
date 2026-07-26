unit Pixie.SvgToPdf;

// SVG-to-PDF vector conversion.
// Inherits SVG parsing from TPixieSvgRendererBase and overrides abstract
// drawing primitives to emit PDF path operators into a Form XObject.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections,
  Pixie.Types, Pixie.WebColor, Pixie.TrueType, Pixie.PdfWriter,
  Pixie.SvgRenderer;

type
  { TPixieSvgFontInfo - font used in SVG text }

  TPixieSvgFontInfo = record
    TtFont: TPixieTrueTypeFont;
    PdfName: AnsiString;
    Type0ObjId: Integer;
    UsedGlyphs: TPixieGlyphMap;
    Weight: Integer;
    Italic: Boolean;
  end;

  TPixieSvgFontInfoList = TList<TPixieSvgFontInfo>;

  { TPixieSvgRenderer - PDF SVG renderer }

  TPixieSvgRenderer = class(TPixieSvgRendererBase)
  private
    FWriter: TPixiePdfWriter;
    FFontCache: TPixieTrueTypeFontCache;
    FStream: TMemoryStream;
    FResourceExtGState: AnsiString;
    FResourceShading: AnsiString;
    FResourceXObject: AnsiString;
    FImageCounter: Integer;
    FImageCache: TDictionary<string, AnsiString>;
    FFonts: TPixieSvgFontInfoList;
    FGsCounter: Integer;
    FFontCounter: Integer;
    FShadingCounter: Integer;

    // Bounding box tracking for gradient fills
    FBBoxMinX, FBBoxMinY, FBBoxMaxX, FBBoxMaxY: Single;
    FBBoxValid: Boolean;

    procedure Emit(const S: AnsiString);
    procedure EmitLn(const S: AnsiString);
    procedure EmitDashPattern(const State: TPixieSvgState);
    procedure SetPdfColor(const Color: TPixieWebColor; Fill: Boolean);
    procedure UpdateBBox(X, Y: Single);

    // Gradient helpers
    function BuildType2Function(const C0, C1: TPixieWebColor): Integer;
    function BuildColorFunction(const Grad: TPixieSvgGradient;
      const State: TPixieSvgState): Integer;
    function GradientNeedsAlpha(const Grad: TPixieSvgGradient;
      const State: TPixieSvgState): Boolean;
    function BuildAlphaType2Function(A0, A1: Byte): Integer;
    function BuildAlphaFunction(const Grad: TPixieSvgGradient;
      const State: TPixieSvgState): Integer;
    function BuildGradientSMask(const Grad: TPixieSvgGradient;
      IsRadial: Boolean; const CoordsStr: AnsiString;
      ShadingType: Integer; const State: TPixieSvgState): AnsiString;
    procedure FillGradient(const State: TPixieSvgState);

    // Image helpers
    function EmbedImageFromHref(const Href: string;
      out PdfName: AnsiString): Integer;
    function EmbedSvgFormFromData(DataStream: TMemoryStream;
      const CacheKey: string; out PdfName: AnsiString): Integer;
    procedure FillWithPattern(const State: TPixieSvgState);

    // Font helpers
    function FindOrCreateSvgFont(const Family: string;
      Weight: Integer; Italic: Boolean): Integer;
    procedure BuildSvgFontObjects;
  protected
    // Override abstract drawing primitives with PDF operators
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

    // Override text run rendering for PDF font embedding
    procedure DoRenderTextRun(const Text: string; X, Y: Single;
      const State: TPixieSvgState); override;
    function DoMeasureTextRun(const Text: string;
      const State: TPixieSvgState): Single; override;
    procedure DoDrawImage(const Href: string;
      X, Y, W, H: Single); override;
  public
    constructor Create(AWriter: TPixiePdfWriter;
      AFontCache: TPixieTrueTypeFontCache);
    destructor Destroy; override;

    function RenderToFormXObject(Data: Pointer; Size: Integer;
      out OutWidth, OutHeight: Single): Integer;
  end;

implementation

uses
  Math, Pixie.SimpleXml, Pixie.Utf8, Pixie.DataUri, Pixie.Html
  {$IFDEF FPC}, FPImage, FPReadPNG, FPReadJPEG, FPReadBMP, FPReadGIF,
  Pixie.ImageUtils{$ENDIF};



// ===========================================================================
// Construction
// ===========================================================================

constructor TPixieSvgRenderer.Create(AWriter: TPixiePdfWriter;
  AFontCache: TPixieTrueTypeFontCache);
begin
  inherited Create;
  FWriter := AWriter;
  FFontCache := AFontCache;
  FStream := TMemoryStream.Create;
  FFonts := TPixieSvgFontInfoList.Create;
  FGsCounter := 0;
  FFontCounter := 0;
  FShadingCounter := 0;
  FImageCounter := 0;
  FImageCache := TDictionary<string, AnsiString>.Create;
  FBBoxValid := False;
end;

destructor TPixieSvgRenderer.Destroy;
var
  I: Integer;
begin
  for I := 0 to FFonts.Count - 1 do
    FFonts[I].UsedGlyphs.Free;
  FFonts.Free;
  FImageCache.Free;
  FStream.Free;
  inherited;
end;

// ===========================================================================
// Content stream writing
// ===========================================================================

procedure TPixieSvgRenderer.Emit(const S: AnsiString);
begin
  if Length(S) > 0 then
    FStream.Write(S[1], Length(S));
end;

procedure TPixieSvgRenderer.EmitLn(const S: AnsiString);
begin
  Emit(S + #10);
end;

procedure TPixieSvgRenderer.EmitDashPattern(const State: TPixieSvgState);
var
  DashStr: AnsiString;
  I: Integer;
begin
  if Length(State.DashArray) > 0 then
  begin
    DashStr := '[';
    for I := 0 to High(State.DashArray) do
    begin
      if I > 0 then DashStr := DashStr + ' ';
      DashStr := DashStr + PdfFloat(State.DashArray[I]);
    end;
    DashStr := DashStr + '] ' + PdfFloat(State.DashOffset) + ' d';
    EmitLn(DashStr);
  end;
end;

procedure TPixieSvgRenderer.SetPdfColor(const Color: TPixieWebColor;
  Fill: Boolean);
var
  R, G, B: Single;
begin
  R := Color.Red / 255.0;
  G := Color.Green / 255.0;
  B := Color.Blue / 255.0;
  if Fill then
    EmitLn(PdfFloat(R) + ' ' + PdfFloat(G) + ' ' + PdfFloat(B) + ' rg')
  else
    EmitLn(PdfFloat(R) + ' ' + PdfFloat(G) + ' ' + PdfFloat(B) + ' RG');
end;

// ===========================================================================
// Bounding box and gradient helpers
// ===========================================================================

procedure TPixieSvgRenderer.UpdateBBox(X, Y: Single);
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

function TPixieSvgRenderer.BuildType2Function(
  const C0, C1: TPixieWebColor): Integer;
var
  Obj: TPixiePdfObject;
begin
  Obj := FWriter.AllocObject;
  Obj.AddEntry('FunctionType', '2');
  Obj.AddEntry('Domain', '[0 1]');
  Obj.AddEntry('C0', '[' + PdfFloat(C0.Red / 255.0) + ' ' +
    PdfFloat(C0.Green / 255.0) + ' ' + PdfFloat(C0.Blue / 255.0) + ']');
  Obj.AddEntry('C1', '[' + PdfFloat(C1.Red / 255.0) + ' ' +
    PdfFloat(C1.Green / 255.0) + ' ' + PdfFloat(C1.Blue / 255.0) + ']');
  Obj.AddEntry('N', '1');
  Result := Obj.Id;
end;

function TPixieSvgRenderer.BuildColorFunction(
  const Grad: TPixieSvgGradient; const State: TPixieSvgState): Integer;
var
  I, N: Integer;
  SubIds: array of Integer;
  FuncsStr, BoundsStr, EncodeStr: AnsiString;
  Obj: TPixiePdfObject;
  C0, C1: TPixieWebColor;
begin
  N := Grad.Stops.Count;
  if N < 2 then begin Result := 0; Exit; end;

  if N = 2 then
  begin
    C0 := Grad.Stops[0].Color;
    C1 := Grad.Stops[1].Color;
    Result := BuildType2Function(C0, C1);
    Exit;
  end;

  // N >= 3: stitching function (Type 3)
  SetLength(SubIds, N - 1);
  for I := 0 to N - 2 do
  begin
    C0 := Grad.Stops[I].Color;
    C1 := Grad.Stops[I + 1].Color;
    SubIds[I] := BuildType2Function(C0, C1);
  end;

  FuncsStr := '[';
  for I := 0 to N - 2 do
    FuncsStr := FuncsStr + PdfRef(SubIds[I]) + ' ';
  FuncsStr := FuncsStr + ']';

  BoundsStr := '[';
  for I := 1 to N - 2 do
    BoundsStr := BoundsStr + PdfFloat(Grad.Stops[I].Offset) + ' ';
  BoundsStr := BoundsStr + ']';

  EncodeStr := '[';
  for I := 0 to N - 2 do
    EncodeStr := EncodeStr + '0 1 ';
  EncodeStr := EncodeStr + ']';

  Obj := FWriter.AllocObject;
  Obj.AddEntry('FunctionType', '3');
  Obj.AddEntry('Domain', '[0 1]');
  Obj.AddEntry('Functions', FuncsStr);
  Obj.AddEntry('Bounds', BoundsStr);
  Obj.AddEntry('Encode', EncodeStr);
  Result := Obj.Id;
end;

function TPixieSvgRenderer.GradientNeedsAlpha(
  const Grad: TPixieSvgGradient; const State: TPixieSvgState): Boolean;
var
  I: Integer;
  C: TPixieWebColor;
begin
  Result := False;
  for I := 0 to Grad.Stops.Count - 1 do
  begin
    C := Grad.Stops[I].Color;
    if C.Alpha < 255 then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function TPixieSvgRenderer.BuildAlphaType2Function(A0, A1: Byte): Integer;
var
  Obj: TPixiePdfObject;
begin
  Obj := FWriter.AllocObject;
  Obj.AddEntry('FunctionType', '2');
  Obj.AddEntry('Domain', '[0 1]');
  Obj.AddEntry('C0', '[' + PdfFloat(A0 / 255.0) + ']');
  Obj.AddEntry('C1', '[' + PdfFloat(A1 / 255.0) + ']');
  Obj.AddEntry('N', '1');
  Result := Obj.Id;
end;

function TPixieSvgRenderer.BuildAlphaFunction(
  const Grad: TPixieSvgGradient; const State: TPixieSvgState): Integer;
var
  I, N: Integer;
  SubIds: array of Integer;
  FuncsStr, BoundsStr, EncodeStr: AnsiString;
  Obj: TPixiePdfObject;
  A0, A1: Byte;
begin
  N := Grad.Stops.Count;
  if N < 2 then begin Result := 0; Exit; end;

  if N = 2 then
  begin
    A0 := Grad.Stops[0].Color.Alpha;
    A1 := Grad.Stops[1].Color.Alpha;
    Result := BuildAlphaType2Function(A0, A1);
    Exit;
  end;

  SetLength(SubIds, N - 1);
  for I := 0 to N - 2 do
  begin
    A0 := Grad.Stops[I].Color.Alpha;
    A1 := Grad.Stops[I + 1].Color.Alpha;
    SubIds[I] := BuildAlphaType2Function(A0, A1);
  end;

  FuncsStr := '[';
  for I := 0 to N - 2 do
    FuncsStr := FuncsStr + PdfRef(SubIds[I]) + ' ';
  FuncsStr := FuncsStr + ']';

  BoundsStr := '[';
  for I := 1 to N - 2 do
    BoundsStr := BoundsStr + PdfFloat(Grad.Stops[I].Offset) + ' ';
  BoundsStr := BoundsStr + ']';

  EncodeStr := '[';
  for I := 0 to N - 2 do
    EncodeStr := EncodeStr + '0 1 ';
  EncodeStr := EncodeStr + ']';

  Obj := FWriter.AllocObject;
  Obj.AddEntry('FunctionType', '3');
  Obj.AddEntry('Domain', '[0 1]');
  Obj.AddEntry('Functions', FuncsStr);
  Obj.AddEntry('Bounds', BoundsStr);
  Obj.AddEntry('Encode', EncodeStr);
  Result := Obj.Id;
end;

function TPixieSvgRenderer.BuildGradientSMask(
  const Grad: TPixieSvgGradient; IsRadial: Boolean;
  const CoordsStr: AnsiString; ShadingType: Integer;
  const State: TPixieSvgState): AnsiString;
var
  AlphaFuncId: Integer;
  AlphaShObj, FormObj, GsObj: TPixiePdfObject;
  StreamData: AnsiString;
  StreamBytes: TBytes;
  BBoxStr, GsName: AnsiString;
begin
  AlphaFuncId := BuildAlphaFunction(Grad, State);
  if AlphaFuncId = 0 then begin Result := ''; Exit; end;

  // Grayscale shading for opacity
  AlphaShObj := FWriter.AllocObject;
  AlphaShObj.AddEntry('ShadingType', AnsiString(IntToStr(ShadingType)));
  AlphaShObj.AddEntry('ColorSpace', '/DeviceGray');
  AlphaShObj.AddEntry('Coords', CoordsStr);
  AlphaShObj.AddEntry('Function', PdfRef(AlphaFuncId));
  AlphaShObj.AddEntry('Extend', '[true true]');

  // Form XObject that paints the opacity shading
  BBoxStr := '[' + PdfFloat(FViewBoxX) + ' ' + PdfFloat(FViewBoxY) + ' ' +
    PdfFloat(FViewBoxX + FViewBoxW) + ' ' + PdfFloat(FViewBoxY + FViewBoxH) + ']';

  StreamData := '/AlSh sh' + #10;
  SetLength(StreamBytes, Length(StreamData));
  Move(StreamData[1], StreamBytes[0], Length(StreamData));

  FormObj := FWriter.AllocObject;
  FormObj.AddEntry('Type', '/XObject');
  FormObj.AddEntry('Subtype', '/Form');
  FormObj.AddEntry('BBox', BBoxStr);
  FormObj.AddEntry('Group',
    '<< /Type /Group /S /Transparency /CS /DeviceGray >>');
  FormObj.AddEntry('Resources',
    '<< /Shading << /AlSh ' + PdfRef(AlphaShObj.Id) + ' >> >>');
  FormObj.SetStream(StreamBytes, False);

  // ExtGState with SMask
  GsObj := FWriter.AllocObject;
  GsObj.AddEntry('Type', '/ExtGState');
  GsObj.AddEntry('SMask',
    '<< /Type /Mask /S /Luminosity /G ' + PdfRef(FormObj.Id) + ' >>');

  Inc(FGsCounter);
  GsName := 'SvgGS' + AnsiString(IntToStr(FGsCounter));
  FResourceExtGState := FResourceExtGState + '/' + GsName + ' ' +
    PdfRef(GsObj.Id) + ' ';
  Result := GsName;
end;

procedure TPixieSvgRenderer.FillGradient(const State: TPixieSvgState);
var
  Grad: TPixieSvgGradient;
  FuncId: Integer;
  ShObj: TPixiePdfObject;
  ShName, CoordsStr, GsName: AnsiString;
  ShadingTypeVal: Integer;
  BX, BY, BW, BH: Single;
  GX1, GY1, GX2, GY2: Single;
  GCX, GCY, GR: Single;
  TX, TY: Single;
  M: TPixieSvgMatrix;
  HasTransform: Boolean;
begin
  Grad := ResolveGradientStops(State.FillGradientId);
  if (Grad = nil) or (Grad.Stops.Count < 2) then
  begin
    EmitLn('n');
    Exit;
  end;

  if not FBBoxValid then begin EmitLn('n'); Exit; end;
  BX := FBBoxMinX; BY := FBBoxMinY;
  BW := FBBoxMaxX - FBBoxMinX; BH := FBBoxMaxY - FBBoxMinY;
  if (BW < 0.001) or (BH < 0.001) then begin EmitLn('n'); Exit; end;

  FuncId := BuildColorFunction(Grad, State);
  if FuncId = 0 then begin EmitLn('n'); Exit; end;

  HasTransform := Grad.GradientTransform <> '';
  if HasTransform then
    M := ParseTransform(Grad.GradientTransform);

  // Build PDF shading object
  ShObj := FWriter.AllocObject;
  ShObj.AddEntry('ColorSpace', '/DeviceRGB');
  ShObj.AddEntry('Function', PdfRef(FuncId));
  ShObj.AddEntry('Extend', '[true true]');

  if not Grad.IsRadial then
  begin
    ShadingTypeVal := 2;
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
      TX := M.A * GX1 + M.C * GY1 + M.E;
      TY := M.B * GX1 + M.D * GY1 + M.F;
      GX1 := TX; GY1 := TY;
      TX := M.A * GX2 + M.C * GY2 + M.E;
      TY := M.B * GX2 + M.D * GY2 + M.F;
      GX2 := TX; GY2 := TY;
    end;
    CoordsStr := '[' + PdfFloat(GX1) + ' ' + PdfFloat(GY1) + ' ' +
      PdfFloat(GX2) + ' ' + PdfFloat(GY2) + ']';
  end
  else
  begin
    ShadingTypeVal := 3;
    if Grad.UserSpaceUnits then
    begin
      GCX := Grad.CX; GCY := Grad.CY; GR := Grad.R;
    end
    else
    begin
      GCX := BX + Grad.CX * BW; GCY := BY + Grad.CY * BH;
      GR := Grad.R * Max(BW, BH);
    end;
    if HasTransform then
    begin
      TX := M.A * GCX + M.C * GCY + M.E;
      TY := M.B * GCX + M.D * GCY + M.F;
      GCX := TX; GCY := TY;
      GR := GR * Sqrt(M.A * M.A + M.B * M.B);
    end;
    CoordsStr := '[' + PdfFloat(GCX) + ' ' + PdfFloat(GCY) + ' 0 ' +
      PdfFloat(GCX) + ' ' + PdfFloat(GCY) + ' ' + PdfFloat(GR) + ']';
  end;

  ShObj.AddEntry('ShadingType', AnsiString(IntToStr(ShadingTypeVal)));
  ShObj.AddEntry('Coords', CoordsStr);

  // Register shading resource
  Inc(FShadingCounter);
  ShName := 'SvgSh' + AnsiString(IntToStr(FShadingCounter));
  FResourceShading := FResourceShading + '/' + ShName + ' ' +
    PdfRef(ShObj.Id) + ' ';

  // Apply soft mask for gradient stop-opacity if needed
  if GradientNeedsAlpha(Grad, State) then
  begin
    GsName := BuildGradientSMask(Grad, Grad.IsRadial, CoordsStr, ShadingTypeVal, State);
    if GsName <> '' then
      EmitLn('/' + GsName + ' gs');
  end;

  // Clip to path and paint shading
  if State.EvenOddFill then
    EmitLn('W* n')
  else
    EmitLn('W n');
  EmitLn('/' + ShName + ' sh');
end;

// ===========================================================================
// Abstract drawing primitive overrides — PDF operators
// ===========================================================================

procedure TPixieSvgRenderer.DoMoveTo(X, Y: Single);
begin
  UpdateBBox(X, Y);
  EmitLn(PdfFloat(X) + ' ' + PdfFloat(Y) + ' m');
end;

procedure TPixieSvgRenderer.DoLineTo(X, Y: Single);
begin
  UpdateBBox(X, Y);
  EmitLn(PdfFloat(X) + ' ' + PdfFloat(Y) + ' l');
end;

procedure TPixieSvgRenderer.DoCurveTo(X1, Y1, X2, Y2, X3, Y3: Single);
begin
  UpdateBBox(X1, Y1);
  UpdateBBox(X2, Y2);
  UpdateBBox(X3, Y3);
  EmitLn(PdfFloat(X1) + ' ' + PdfFloat(Y1) + ' ' +
         PdfFloat(X2) + ' ' + PdfFloat(Y2) + ' ' +
         PdfFloat(X3) + ' ' + PdfFloat(Y3) + ' c');
end;

procedure TPixieSvgRenderer.DoClosePath;
begin
  EmitLn('h');
end;

procedure TPixieSvgRenderer.DoSaveState;
begin
  EmitLn('q');
end;

procedure TPixieSvgRenderer.DoRestoreState;
begin
  EmitLn('Q');
end;

procedure TPixieSvgRenderer.DoSetTransform(const M: TPixieSvgMatrix);
begin
  EmitLn(PdfFloat(M.A) + ' ' + PdfFloat(M.B) + ' ' +
         PdfFloat(M.C) + ' ' + PdfFloat(M.D) + ' ' +
         PdfFloat(M.E) + ' ' + PdfFloat(M.F) + ' cm');
end;

procedure TPixieSvgRenderer.DoFillAndStroke(const State: TPixieSvgState);
var
  FC, SC: TPixieWebColor;
  FillAlpha, StrokeAlpha: Single;
  DoFill, DoStroke: Boolean;
  GsObj: TPixiePdfObject;
  GsName: AnsiString;
begin
  FC := State.FillColor;
  SC := State.StrokeColor;

  FillAlpha := (FC.Alpha / 255.0) * State.FillOpacity;
  StrokeAlpha := (SC.Alpha / 255.0) * State.StrokeOpacity;
  DoFill := State.HasFill and ((State.FillGradientId <> '') or (FillAlpha > 0.001));
  // Gradient strokes not supported in PDF — skip them
  DoStroke := State.HasStroke and (State.StrokeGradientId = '') and
    (StrokeAlpha > 0.001);

  if State.FillGradientId <> '' then
  begin
    EmitLn('q');
    if IsPatternFill(State.FillGradientId) then
      FillWithPattern(State)
    else
      FillGradient(State);
    EmitLn('Q');
  end
  else if DoFill or DoStroke then
  begin
    // Apply fill/stroke opacity via ExtGState if not fully opaque
    if (DoFill and (FillAlpha < 0.999)) or
       (DoStroke and (StrokeAlpha < 0.999)) then
    begin
      GsObj := FWriter.AllocObject;
      GsObj.AddEntry('Type', '/ExtGState');
      if DoFill then
        GsObj.AddEntry('ca', PdfFloat(FillAlpha));
      if DoStroke then
        GsObj.AddEntry('CA', PdfFloat(StrokeAlpha));
      Inc(FGsCounter);
      GsName := 'SvgGS' + AnsiString(IntToStr(FGsCounter));
      FResourceExtGState := FResourceExtGState + '/' + GsName + ' ' +
        PdfRef(GsObj.Id) + ' ';
      EmitLn('/' + GsName + ' gs');
    end;

    if DoFill and DoStroke then
    begin
      EmitLn(IntToStr(Ord(State.LineCap)) + ' J');
      EmitLn(IntToStr(Ord(State.LineJoin)) + ' j');
      EmitDashPattern(State);
      SetPdfColor(FC, True);
      SetPdfColor(SC, False);
      EmitLn(PdfFloat(State.StrokeWidth) + ' w');
      if State.EvenOddFill then
        EmitLn('B*')
      else
        EmitLn('B');
    end
    else if DoFill then
    begin
      SetPdfColor(FC, True);
      if State.EvenOddFill then
        EmitLn('f*')
      else
        EmitLn('f');
    end
    else if DoStroke then
    begin
      EmitLn(IntToStr(Ord(State.LineCap)) + ' J');
      EmitLn(IntToStr(Ord(State.LineJoin)) + ' j');
      EmitDashPattern(State);
      SetPdfColor(SC, False);
      EmitLn(PdfFloat(State.StrokeWidth) + ' w');
      EmitLn('S');
    end
    else
      EmitLn('n');
  end
  else
    EmitLn('n');

  FBBoxValid := False;
end;

procedure TPixieSvgRenderer.DoBeginOpacity(Opacity: Single);
var
  GsObj: TPixiePdfObject;
  GsName: AnsiString;
begin
  GsObj := FWriter.AllocObject;
  GsObj.AddEntry('Type', '/ExtGState');
  GsObj.AddEntry('ca', PdfFloat(Opacity));
  GsObj.AddEntry('CA', PdfFloat(Opacity));

  Inc(FGsCounter);
  GsName := 'SvgGS' + AnsiString(IntToStr(FGsCounter));
  FResourceExtGState := FResourceExtGState + '/' + GsName + ' ' +
    PdfRef(GsObj.Id) + ' ';

  EmitLn('/' + GsName + ' gs');
end;

procedure TPixieSvgRenderer.DoEndOpacity;
begin
  // No-op for PDF — restore handled by q/Q
end;

procedure TPixieSvgRenderer.DoClipPath(EvenOdd: Boolean);
begin
  // W n — clip to current path (non-zero winding), then clear path
  // W* n — even-odd clip rule
  if EvenOdd then
    EmitLn('W* n')
  else
    EmitLn('W n');
end;

procedure TPixieSvgRenderer.DoBeginMask(const MaskImageHref: string;
  MaskX, MaskY, MaskW, MaskH: Single);
begin
  // PDF mask support not implemented — no-op
end;

procedure TPixieSvgRenderer.DoEndMask;
begin
  // no-op
end;

// ===========================================================================
// Font helpers
// ===========================================================================

function TPixieSvgRenderer.FindOrCreateSvgFont(const Family: string;
  Weight: Integer; Italic: Boolean): Integer;
var
  I: Integer;
  FilePath: string;
  TtFont: TPixieTrueTypeFont;
  Key: string;
  Info: TPixieSvgFontInfo;
begin
  // Check existing — match family, weight, and italic
  for I := 0 to FFonts.Count - 1 do
  begin
    if (FFonts[I].TtFont <> nil) and
       (LowerCase(FFonts[I].TtFont.FamilyName) = LowerCase(Family)) and
       (FFonts[I].Weight = Weight) and
       (FFonts[I].Italic = Italic) then
    begin
      Result := I;
      Exit;
    end;
  end;

  // Find font file
  Key := LowerCase(Family) + ':' + IntToStr(Weight) + ':' + IntToStr(Ord(Italic));
  if not FFontCache.TryGetValue(Key, TtFont) then
  begin
    FilePath := PixieFindFontFile(Family, Weight, Italic);
    if FilePath = '' then
    begin
      // Try fallbacks
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

    TtFont := TPixieTrueTypeFont.Create;
    if (FilePath <> '') and TtFont.LoadFromFile(FilePath) then
      FFontCache.Add(Key, TtFont)
    else
    begin
      TtFont.Free;
      Result := -1;
      Exit;
    end;
  end;

  Inc(FFontCounter);
  Info.TtFont := TtFont;
  Info.PdfName := 'SvgF' + AnsiString(IntToStr(FFontCounter));
  Info.Type0ObjId := 0;
  Info.UsedGlyphs := TPixieGlyphMap.Create;
  Info.Weight := Weight;
  Info.Italic := Italic;
  FFonts.Add(Info);
  Result := FFonts.Count - 1;
end;

// Encode a Unicode codepoint as a hex string in UTF-16BE for ToUnicode CMap.
// BMP codepoints produce 4 hex digits; supplementary plane produces 8 (surrogate pair).
function SvgCodepointToUtf16Hex(Cp: UInt32): AnsiString;
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

procedure TPixieSvgRenderer.BuildSvgFontObjects;
var
  I, J, K, ChunkSize: Integer;
  Info: TPixieSvgFontInfo;
  Scale: Single;
  FontFile, Descriptor, CidFont, Type0, ToUnicode: TPixiePdfObject;
  FontData: TBytes;
  WArray, CmapStr: AnsiString;
  SortedGlyphs: TList<UInt16>;
  Pair: TPair<UInt16, UInt32>;
  GlyphId, AdvWidth: UInt16;
  Flags: Integer;
  Asc, Desc: Single;
begin
  for I := 0 to FFonts.Count - 1 do
  begin
    Info := FFonts[I];
    if (Info.TtFont = nil) or (Info.UsedGlyphs.Count = 0) then Continue;

    Scale := 1000.0 / Info.TtFont.UnitsPerEm;

    // FontFile2
    FontFile := FWriter.AllocObject;
    FontData := Info.TtFont.BuildSubsetFont(Info.UsedGlyphs);
    FontFile.AddEntry('Length1', AnsiString(IntToStr(Length(FontData))));
    FontFile.SetStream(FontData, True);

    // FontDescriptor
    Descriptor := FWriter.AllocObject;
    Flags := 32;
    if Info.TtFont.ItalicAngle <> 0 then
      Flags := Flags or 64;
    if Info.TtFont.WeightClass >= 700 then
      Flags := Flags or (1 shl 18);

    Asc := Info.TtFont.Ascent * Scale;
    Desc := Info.TtFont.Descent * Scale;

    Descriptor.AddEntry('Type', '/FontDescriptor');
    Descriptor.AddEntry('FontName', '/' + Info.PdfName + 'TT');
    Descriptor.AddEntry('Flags', AnsiString(IntToStr(Flags)));
    Descriptor.AddEntry('FontBBox', PdfRect(
      Info.TtFont.BBoxXMin * Scale, Info.TtFont.BBoxYMin * Scale,
      Info.TtFont.BBoxXMax * Scale, Info.TtFont.BBoxYMax * Scale));
    Descriptor.AddEntry('ItalicAngle', PdfFloat(Info.TtFont.ItalicAngle));
    Descriptor.AddEntry('Ascent', PdfFloat(Asc));
    Descriptor.AddEntry('Descent', PdfFloat(Desc));
    Descriptor.AddEntry('CapHeight', PdfFloat(Info.TtFont.CapHeight * Scale));
    Descriptor.AddEntry('StemV', '80');
    Descriptor.AddEntry('FontFile2', PdfRef(FontFile.Id));

    // W array
    SortedGlyphs := TList<UInt16>.Create;
    try
      for Pair in Info.UsedGlyphs do
        SortedGlyphs.Add(Pair.Key);
      SortedGlyphs.Sort;

      WArray := '[';
      for J := 0 to SortedGlyphs.Count - 1 do
      begin
        GlyphId := SortedGlyphs[J];
        AdvWidth := Info.TtFont.GetGlyphWidth(GlyphId);
        WArray := WArray + AnsiString(IntToStr(GlyphId)) + ' [' +
          PdfFloat(AdvWidth * Scale) + '] ';
      end;
      WArray := WArray + ']';
    finally
      SortedGlyphs.Free;
    end;

    // CIDFontType2
    CidFont := FWriter.AllocObject;
    CidFont.AddEntry('Type', '/Font');
    CidFont.AddEntry('Subtype', '/CIDFontType2');
    CidFont.AddEntry('BaseFont', '/' + Info.PdfName + 'TT');
    CidFont.AddEntry('CIDSystemInfo',
      '<< /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>');
    CidFont.AddEntry('FontDescriptor', PdfRef(Descriptor.Id));
    CidFont.AddEntry('W', WArray);
    CidFont.AddEntry('DW', '1000');
    CidFont.AddEntry('CIDToGIDMap', '/Identity');

    // ToUnicode CMap
    ToUnicode := FWriter.AllocObject;
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

    SortedGlyphs := TList<UInt16>.Create;
    try
      for Pair in Info.UsedGlyphs do
        SortedGlyphs.Add(Pair.Key);
      SortedGlyphs.Sort;

      if SortedGlyphs.Count > 0 then
      begin
        J := 0;
        while J < SortedGlyphs.Count do
        begin
          ChunkSize := SortedGlyphs.Count - J;
          if ChunkSize > 100 then ChunkSize := 100;
          CmapStr := CmapStr +
            AnsiString(IntToStr(ChunkSize)) + ' beginbfchar'#10;
          for K := J to J + ChunkSize - 1 do
          begin
            GlyphId := SortedGlyphs[K];
            CmapStr := CmapStr +
              '<' + AnsiString(IntToHex(GlyphId, 4)) + '> ' +
              '<' + SvgCodepointToUtf16Hex(Info.UsedGlyphs[GlyphId]) + '>'#10;
          end;
          CmapStr := CmapStr + 'endbfchar'#10;
          Inc(J, ChunkSize);
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

    // Type0
    Type0 := FWriter.AllocObject;
    Type0.AddEntry('Type', '/Font');
    Type0.AddEntry('Subtype', '/Type0');
    Type0.AddEntry('BaseFont', '/' + Info.PdfName + 'TT');
    Type0.AddEntry('Encoding', '/Identity-H');
    Type0.AddEntry('DescendantFonts', '[' + PdfRef(CidFont.Id) + ']');
    Type0.AddEntry('ToUnicode', PdfRef(ToUnicode.Id));

    // Update info with object ID
    Info.Type0ObjId := Type0.Id;
    FFonts[I] := Info;
  end;
end;

// ===========================================================================
// Image embedding and pattern fill
// ===========================================================================

function TPixieSvgRenderer.EmbedImageFromHref(const Href: string;
  out PdfName: AnsiString): Integer;
var
  CacheKey: string;
  DataStream: TMemoryStream;
{$IFDEF FPC}
  ImgObj, SmaskObj: TPixiePdfObject;
  RgbData, AlphaData: TBytes;
  X, Y, W, H, Pitch: Integer;
  Src: PByte;
  HasAlpha: Boolean;
  B, G, R, A: Byte;
  RgbIdx, AlphaIdx: Integer;
  Img: TFPMemoryImage;
  Pixels: PByte;
{$ENDIF}
begin
  Result := 0;
  PdfName := '';

  if Pos('data:', Href) <> 1 then Exit;

  // Cache key — short fingerprint for large data URIs
  if Length(Href) > 256 then
    CacheKey := 'data:' + IntToStr(Length(Href)) + ':' +
      Copy(Href, Length(Href) - 31, 32)
  else
    CacheKey := Href;
  if FImageCache.TryGetValue(CacheKey, PdfName) then
  begin
    Result := 1;
    Exit;
  end;
  if not DecodeDataUri(Href, DataStream) then Exit;
  try
    // An SVG embedded as a data: URI (e.g. shields.io badge logos carry the
    // brand mark as `data:image/svg+xml;base64,...`) is rendered as vector
    // content via a child renderer into a Form XObject. Feeding the XML to the
    // raster decoders below would drop the image (and raise a handled
    // FPImageException on FPC). Sniff the decoded bytes rather than trusting
    // the media type, which is sometimes missing or wrong.
    if PixieDataLooksLikeSvg(DataStream.Memory, DataStream.Size) then
    begin
      Result := EmbedSvgFormFromData(DataStream, CacheKey, PdfName);
      Exit;
    end;
  {$IFDEF FPC}
    Img := TFPMemoryImage.Create(0, 0);
    try
      try
        DataStream.Position := 0;
        Img.LoadFromStream(DataStream);
      except
        Exit;
      end;
      ConvertFPImageToBGRA(Img, Pixels, W, H, Pitch);
      if Pixels = nil then Exit;
      try
        SetLength(RgbData, W * H * 3);
        SetLength(AlphaData, W * H);
        HasAlpha := False;
        RgbIdx := 0;
        AlphaIdx := 0;
        for Y := 0 to H - 1 do
        begin
          Src := Pixels + Y * Pitch;
          for X := 0 to W - 1 do
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
          SmaskObj.AddEntry('Width', AnsiString(IntToStr(W)));
          SmaskObj.AddEntry('Height', AnsiString(IntToStr(H)));
          SmaskObj.AddEntry('ColorSpace', '/DeviceGray');
          SmaskObj.AddEntry('BitsPerComponent', '8');
          SmaskObj.SetStream(AlphaData, True);
        end;

        // Create image object
        ImgObj := FWriter.AllocObject;
        ImgObj.AddEntry('Type', '/XObject');
        ImgObj.AddEntry('Subtype', '/Image');
        ImgObj.AddEntry('Width', AnsiString(IntToStr(W)));
        ImgObj.AddEntry('Height', AnsiString(IntToStr(H)));
        ImgObj.AddEntry('ColorSpace', '/DeviceRGB');
        ImgObj.AddEntry('BitsPerComponent', '8');
        if SmaskObj <> nil then
          ImgObj.AddEntry('SMask', PdfRef(SmaskObj.Id));
        ImgObj.SetStream(RgbData, True);

        Inc(FImageCounter);
        PdfName := 'SvgIm' + AnsiString(IntToStr(FImageCounter));
        FResourceXObject := FResourceXObject + '/' + PdfName + ' ' +
          PdfRef(ImgObj.Id) + ' ';
        FImageCache.Add(CacheKey, PdfName);
        Result := ImgObj.Id;
      finally
        FreeMem(Pixels);
      end;
    finally
      Img.Free;
    end;
  {$ENDIF}
  finally
    DataStream.Free;
  end;
end;

// Render an SVG carried in a data: URI into a Form XObject, using a child
// renderer that shares this renderer's PDF writer and font cache so the form
// and its sub-resources land in the same document. A separate instance is
// required because RenderToFormXObject resets the renderer's content stream
// and viewBox, which must not disturb the in-progress outer render.
function TPixieSvgRenderer.EmbedSvgFormFromData(DataStream: TMemoryStream;
  const CacheKey: string; out PdfName: AnsiString): Integer;
var
  Child: TPixieSvgRenderer;
  FormId: Integer;
  OutW, OutH: Single;
begin
  Result := 0;
  PdfName := '';

  Child := TPixieSvgRenderer.Create(FWriter, FFontCache);
  try
    FormId := Child.RenderToFormXObject(DataStream.Memory, DataStream.Size,
      OutW, OutH);
  finally
    Child.Free;
  end;
  if FormId = 0 then Exit;

  Inc(FImageCounter);
  PdfName := 'SvgIm' + AnsiString(IntToStr(FImageCounter));
  FResourceXObject := FResourceXObject + '/' + PdfName + ' ' +
    PdfRef(FormId) + ' ';
  FImageCache.Add(CacheKey, PdfName);
  Result := FormId;
end;

procedure TPixieSvgRenderer.FillWithPattern(const State: TPixieSvgState);
var
  ImgHref: string;
  PdfName: AnsiString;
  BX, BY, BW, BH: Single;
begin
  ImgHref := ResolvePatternImageHref(State.FillGradientId);
  if (ImgHref = '') or (EmbedImageFromHref(ImgHref, PdfName) = 0) or
     not FBBoxValid then
  begin
    EmitLn('n');
    FBBoxValid := False;
    Exit;
  end;

  BX := FBBoxMinX;
  BY := FBBoxMinY;
  BW := FBBoxMaxX - FBBoxMinX;
  BH := FBBoxMaxY - FBBoxMinY;
  FBBoxValid := False;

  if (BW <= 0) or (BH <= 0) then
  begin
    EmitLn('n');
    Exit;
  end;

  if State.EvenOddFill then
    EmitLn('W* n')
  else
    EmitLn('W n');

  EmitLn(PdfFloat(BW) + ' 0 0 ' + PdfFloat(-BH) + ' ' +
    PdfFloat(BX) + ' ' + PdfFloat(BY + BH) + ' cm');
  EmitLn('/' + PdfName + ' Do');
end;

procedure TPixieSvgRenderer.DoDrawImage(const Href: string;
  X, Y, W, H: Single);
var
  PdfName: AnsiString;
begin
  if EmbedImageFromHref(Href, PdfName) = 0 then Exit;
  EmitLn('q');
  EmitLn(PdfFloat(W) + ' 0 0 ' + PdfFloat(-H) + ' ' +
    PdfFloat(X) + ' ' + PdfFloat(Y + H) + ' cm');
  EmitLn('/' + PdfName + ' Do');
  EmitLn('Q');
end;

// ===========================================================================
// Text run rendering (PDF — uses glyph-based font embedding)
// ===========================================================================

function TPixieSvgRenderer.DoMeasureTextRun(const Text: string;
  const State: TPixieSvgState): Single;
var
  FontIdx: Integer;
  Info: TPixieSvgFontInfo;
  Scale: Single;
  I, Len: Integer;
  Codepoint: UInt32;
  GlyphId: UInt16;
begin
  Result := 0;
  FontIdx := FindOrCreateSvgFont(State.FontFamily, State.FontWeight, State.FontItalic);
  if FontIdx < 0 then Exit;
  Info := FFonts[FontIdx];
  if Info.TtFont = nil then Exit;
  Scale := State.FontSize / Info.TtFont.UnitsPerEm;
  I := 1;
  Len := Length(Text);
  while I <= Len do
  begin
    Codepoint := ReadUtf8Char(Text, I);
    if Codepoint = 0 then Break;
    GlyphId := Info.TtFont.CharToGlyph(Codepoint);
    Result := Result + Info.TtFont.GetGlyphWidth(GlyphId) * Scale;
    if State.LetterSpacing > 0 then
      Result := Result + State.LetterSpacing;
  end;
end;

procedure TPixieSvgRenderer.DoRenderTextRun(const Text: string;
  X, Y: Single; const State: TPixieSvgState);
var
  FontIdx: Integer;
  Info: TPixieSvgFontInfo;
  PtSize, Scale: Single;
  I, Len: Integer;
  Codepoint: UInt32;
  GlyphId: UInt16;
  HexStr: AnsiString;
  TotalWidth, GlyphW, DecY, FontAscent, FontXHeight: Single;
begin
  FontIdx := FindOrCreateSvgFont(State.FontFamily, State.FontWeight, State.FontItalic);
  if FontIdx < 0 then Exit;

  Info := FFonts[FontIdx];
  if Info.TtFont = nil then Exit;

  PtSize := State.FontSize;
  Scale := PtSize / Info.TtFont.UnitsPerEm;

  SetPdfColor(State.FillColor, True);

  EmitLn('BT');
  EmitLn('/' + Info.PdfName + ' ' + PdfFloat(PtSize) + ' Tf');
  EmitLn('1 0 0 -1 ' + PdfFloat(X) + ' ' + PdfFloat(Y) + ' Tm');

  if (State.LetterSpacing > 0) then
  begin
    I := 1;
    Len := Length(Text);
    while I <= Len do
    begin
      Codepoint := ReadUtf8Char(Text, I);
      if Codepoint = 0 then Break;
      GlyphId := Info.TtFont.CharToGlyph(Codepoint);
      if not Info.UsedGlyphs.ContainsKey(GlyphId) then
        Info.UsedGlyphs.Add(GlyphId, Codepoint);

      HexStr := '<' + AnsiString(LowerCase(IntToHex(GlyphId, 4))) + '>';
      GlyphW := Info.TtFont.GetGlyphWidth(GlyphId) * Scale + State.LetterSpacing;
      EmitLn(HexStr + ' Tj');
      EmitLn(PdfFloat(GlyphW) + ' 0 Td');
    end;
  end
  else
  begin
    HexStr := '<';
    I := 1;
    Len := Length(Text);
    while I <= Len do
    begin
      Codepoint := ReadUtf8Char(Text, I);
      if Codepoint = 0 then Break;
      GlyphId := Info.TtFont.CharToGlyph(Codepoint);
      if not Info.UsedGlyphs.ContainsKey(GlyphId) then
        Info.UsedGlyphs.Add(GlyphId, Codepoint);
      HexStr := HexStr + AnsiString(LowerCase(IntToHex(GlyphId, 4)));
    end;
    HexStr := HexStr + '>';
    EmitLn(HexStr + ' Tj');
  end;

  FFonts[FontIdx] := Info;
  EmitLn('ET');

  // Draw text-decoration lines
  if State.TextDecoration <> TextDecorationLineNone then
  begin
    TotalWidth := DoMeasureTextRun(Text, State);
    FontAscent := Info.TtFont.Ascent * Scale;
    FontXHeight := Info.TtFont.XHeight * Scale;
    SetPdfColor(State.FillColor, False);
    EmitLn(PdfFloat(PtSize * SvgDecorationThickness) + ' w');
    if (State.TextDecoration and TextDecorationLineUnderline) <> 0 then
    begin
      DecY := Y + PtSize * SvgDecorationUnderlineOffset;
      EmitLn(PdfFloat(X) + ' ' + PdfFloat(DecY) + ' m ' +
        PdfFloat(X + TotalWidth) + ' ' + PdfFloat(DecY) + ' l S');
    end;
    if (State.TextDecoration and TextDecorationLineOverline) <> 0 then
    begin
      DecY := Y - FontAscent;
      EmitLn(PdfFloat(X) + ' ' + PdfFloat(DecY) + ' m ' +
        PdfFloat(X + TotalWidth) + ' ' + PdfFloat(DecY) + ' l S');
    end;
    if (State.TextDecoration and TextDecorationLineLineThrough) <> 0 then
    begin
      DecY := Y - FontXHeight / 2;
      EmitLn(PdfFloat(X) + ' ' + PdfFloat(DecY) + ' m ' +
        PdfFloat(X + TotalWidth) + ' ' + PdfFloat(DecY) + ' l S');
    end;
  end;
end;

// ===========================================================================
// Main entry point
// ===========================================================================

function TPixieSvgRenderer.RenderToFormXObject(Data: Pointer; Size: Integer;
  out OutWidth, OutHeight: Single): Integer;
var
  FormObj: TPixiePdfObject;
  Buf: TBytes;
  MatrixStr, ResourceStr: AnsiString;
  I: Integer;
begin
  Result := 0;
  OutWidth := 0;
  OutHeight := 0;

  if not ParseSvg(Data, Size, OutWidth, OutHeight) then Exit;
  try
    // Clear stream and render
    FStream.Size := 0;
    RenderDocument;

    // Build font objects for any text rendered
    BuildSvgFontObjects;

    // Create Form XObject
    // DrawImage maps unit square [0,0,1,1] to destination rect.
    // Matrix must normalise SVG viewBox coords to [0,0,1,1] and
    // flip Y (SVG is Y-down, PDF DrawImage is Y-up).
    MatrixStr := '[' +
      PdfFloat(1.0 / FViewBoxW) + ' 0 0 ' +
      PdfFloat(-1.0 / FViewBoxH) + ' ' +
      PdfFloat(-FViewBoxX / FViewBoxW) + ' ' +
      PdfFloat((FViewBoxY + FViewBoxH) / FViewBoxH) + ']';

    // Build resource dictionary
    ResourceStr := '<< ';
    if FResourceExtGState <> '' then
      ResourceStr := ResourceStr + '/ExtGState << ' + FResourceExtGState + ' >> ';
    if FResourceShading <> '' then
      ResourceStr := ResourceStr + '/Shading << ' + FResourceShading + ' >> ';
    if FResourceXObject <> '' then
      ResourceStr := ResourceStr + '/XObject << ' + FResourceXObject + ' >> ';
    if FFonts.Count > 0 then
    begin
      ResourceStr := ResourceStr + '/Font << ';
      for I := 0 to FFonts.Count - 1 do
        if FFonts[I].Type0ObjId <> 0 then
          ResourceStr := ResourceStr + '/' + FFonts[I].PdfName + ' ' +
            PdfRef(FFonts[I].Type0ObjId) + ' ';
      ResourceStr := ResourceStr + '>> ';
    end;
    ResourceStr := ResourceStr + '>>';

    // Create the Form XObject
    FormObj := FWriter.AllocObject;
    FormObj.AddEntry('Type', '/XObject');
    FormObj.AddEntry('Subtype', '/Form');
    FormObj.AddEntry('BBox', '[' + PdfFloat(FViewBoxX) + ' ' +
      PdfFloat(FViewBoxY) + ' ' + PdfFloat(FViewBoxX + FViewBoxW) + ' ' +
      PdfFloat(FViewBoxY + FViewBoxH) + ']');
    FormObj.AddEntry('Matrix', MatrixStr);
    FormObj.AddEntry('Resources', ResourceStr);

    SetLength(Buf, FStream.Size);
    if FStream.Size > 0 then
    begin
      FStream.Position := 0;
      FStream.Read(Buf[0], Length(Buf));
    end;
    FormObj.SetStream(Buf, True);

    Result := FormObj.Id;
  finally
    ClearDocument;
  end;
end;

end.
