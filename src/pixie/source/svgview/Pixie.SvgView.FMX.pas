unit Pixie.SvgView.FMX;

// TPixieSvgView — Delphi FMX SVG display component.
// Renders SVG via FMX canvas, scales proportionally.

interface

uses
  System.SysUtils, System.Classes, System.Math, System.Types, System.UITypes, System.UIConsts,
  FMX.Controls, FMX.Types, FMX.Graphics,
  Pixie.Types, Pixie.WebColor, Pixie.Canvas, Pixie.Canvas.FMX,
  Pixie.SvgRenderer, Pixie.SvgRenderer.Canvas;

type
  TPixieSvgAlign = (
    saTopLeft,
    saCenterHorz,
    saCenterVert,
    saCenterBoth
  );

  { TPixieSvgView }

  TPixieSvgView = class(TControl)
  private
    FPixieCanvas: TPixieCanvas;
    FLines: TStringList;
    FRenderer: TPixieSvgCanvasRenderer;
    FAlignment: TPixieSvgAlign;
    FSvgW: Single;
    FSvgH: Single;
    FParsed: Boolean;
    FColorInner: TAlphaColor;
    FColorInnerBorder: TAlphaColor;
    FColorCheckers: TAlphaColor;
    FCheckersSize: Integer;
    FZoom: Double;

    procedure LinesChanged(Sender: TObject);
    procedure ParseSvg;
    procedure EnsureParsed;
    function GetLines: TStrings;
    procedure SetLines(Value: TStrings);
    procedure SetAlignment(Value: TPixieSvgAlign);
    procedure SetColorInner(Value: TAlphaColor);
    procedure SetColorInnerBorder(Value: TAlphaColor);
    procedure SetColorCheckers(Value: TAlphaColor);
    procedure SetCheckersSize(Value: Integer);
    procedure SetZoom(const Value: Double);
    function GetImageWidth: Single;
    function GetImageHeight: Single;
    procedure DrawCheckerboard(X, Y, W, H: Single;
      const C1, C2: TPixieWebColor; CellSize: Integer);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadFromFile(const FileName: string);
    procedure LoadFromStream(Stream: TStream);
    procedure LoadFromResource(const ResName: string); overload;
    procedure LoadFromResource(Instance: THandle; const ResName: string); overload;

    // Width/Height of 0 mean "use intrinsic SVG size". Transparent bg.
    procedure SaveAsPng(const FileName: string;
      Width: Integer = 0; Height: Integer = 0); overload;
    procedure SaveAsPng(Stream: TStream;
      Width: Integer = 0; Height: Integer = 0); overload;
    procedure SaveAsBmp(const FileName: string;
      Width: Integer = 0; Height: Integer = 0); overload;
    procedure SaveAsBmp(Stream: TStream;
      Width: Integer = 0; Height: Integer = 0); overload;

    property ImageWidth: Single read GetImageWidth;
    property ImageHeight: Single read GetImageHeight;
  published
    property Lines: TStrings read GetLines write SetLines;
    property Alignment: TPixieSvgAlign
      read FAlignment write SetAlignment default saCenterBoth;
    property ColorInner: TAlphaColor
      read FColorInner write SetColorInner;
    property ColorInnerBorder: TAlphaColor
      read FColorInnerBorder write SetColorInnerBorder;
    property ColorCheckers: TAlphaColor
      read FColorCheckers write SetColorCheckers;
    property CheckersSize: Integer
      read FCheckersSize write SetCheckersSize default 8;
    property Zoom: Double
      read FZoom write SetZoom;

    property Align;
    property Anchors;
    property Size;
    property Visible;
  end;

implementation

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

procedure TPixieSvgView.LoadFromFile(const FileName: string);
begin
  // SVG is UTF-8 by spec; default TStrings encoding on Delphi is the
  // system code page (CP1252 on Windows) which would mojibake any
  // non-ASCII text. A UTF-8 BOM, if present, still wins.
  FLines.LoadFromFile(FileName, TEncoding.UTF8);
end;

procedure TPixieSvgView.LoadFromStream(Stream: TStream);
begin
  FLines.LoadFromStream(Stream, TEncoding.UTF8);
end;

procedure TPixieSvgView.LoadFromResource(const ResName: string);
begin
  LoadFromResource(HInstance, ResName);
end;

procedure TPixieSvgView.LoadFromResource(Instance: THandle;
  const ResName: string);
var
  Stream: TResourceStream;
begin
  Stream := TResourceStream.Create(Instance, ResName, PChar(10)); // RT_RCDATA
  try
    LoadFromStream(Stream);
  finally
    Stream.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

constructor TPixieSvgView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 100;
  Height := 100;

  FPixieCanvas := TPixieFmxCanvas.Create;
  FLines := TStringList.Create;
  // SVG is UTF-8 by spec; this default applies when callers reach the
  // exposed Lines property directly (Lines.LoadFromFile etc.) instead of
  // going through the wrapper LoadFromFile/LoadFromStream methods.
  FLines.DefaultEncoding := TEncoding.UTF8;
  FLines.OnChange := LinesChanged;
  FRenderer := TPixieSvgCanvasRenderer.Create(FPixieCanvas);
  FAlignment := saCenterBoth;
  FSvgW := 0;
  FSvgH := 0;
  FParsed := False;
  FColorInner := claNull;
  FColorInnerBorder := claNull;
  FColorCheckers := claNull;
  FCheckersSize := 8;
  FZoom := 1.0;
end;

destructor TPixieSvgView.Destroy;
begin
  FreeAndNil(FRenderer);
  FreeAndNil(FLines);
  FreeAndNil(FPixieCanvas);
  inherited Destroy;
end;

function TPixieSvgView.GetLines: TStrings;
begin
  Result := FLines;
end;

procedure TPixieSvgView.SetLines(Value: TStrings);
begin
  FLines.Assign(Value);
end;

procedure TPixieSvgView.SetAlignment(Value: TPixieSvgAlign);
begin
  if FAlignment <> Value then
  begin
    FAlignment := Value;
    Repaint;
  end;
end;

procedure TPixieSvgView.SetColorInner(Value: TAlphaColor);
begin
  if FColorInner <> Value then
  begin
    FColorInner := Value;
    Repaint;
  end;
end;

procedure TPixieSvgView.SetColorInnerBorder(Value: TAlphaColor);
begin
  if FColorInnerBorder <> Value then
  begin
    FColorInnerBorder := Value;
    Repaint;
  end;
end;

procedure TPixieSvgView.SetColorCheckers(Value: TAlphaColor);
begin
  if FColorCheckers <> Value then
  begin
    FColorCheckers := Value;
    Repaint;
  end;
end;

procedure TPixieSvgView.SetCheckersSize(Value: Integer);
begin
  if Value < 1 then Value := 1;
  if FCheckersSize <> Value then
  begin
    FCheckersSize := Value;
    Repaint;
  end;
end;

procedure TPixieSvgView.SetZoom(const Value: Double);
var
  NewZoom: Double;
begin
  NewZoom := Value;
  if NewZoom < 0.25 then NewZoom := 0.25;
  if NewZoom > 4.0 then NewZoom := 4.0;
  if FZoom = NewZoom then Exit;
  FZoom := NewZoom;
  Repaint;
end;

function TPixieSvgView.GetImageWidth: Single;
begin
  EnsureParsed;
  Result := FSvgW;
end;

function TPixieSvgView.GetImageHeight: Single;
begin
  EnsureParsed;
  Result := FSvgH;
end;

procedure TPixieSvgView.EnsureParsed;
begin
  if not FParsed then
    ParseSvg;
end;

function AlphaColorToWebColor(C: TAlphaColor): TPixieWebColor;
begin
  Result := TPixieWebColor.Create(
    Byte(C shr 16), Byte(C shr 8), Byte(C));
end;

procedure TPixieSvgView.DrawCheckerboard(X, Y, W, H: Single;
  const C1, C2: TPixieWebColor; CellSize: Integer);
var
  Row, Col, Cols, Rows: Integer;
  CX, CY, CW, CH: Single;
begin
  FPixieCanvas.FillRect(X, Y, W, H, C1);
  Cols := Ceil(W / CellSize);
  Rows := Ceil(H / CellSize);
  for Row := 0 to Rows - 1 do
    for Col := 0 to Cols - 1 do
      if Odd(Row + Col) then
      begin
        CX := X + Col * CellSize;
        CY := Y + Row * CellSize;
        CW := Min(CellSize, X + W - CX);
        CH := Min(CellSize, Y + H - CY);
        if (CW > 0) and (CH > 0) then
          FPixieCanvas.FillRect(CX, CY, CW, CH, C2);
      end;
end;

procedure TPixieSvgView.LinesChanged(Sender: TObject);
begin
  FParsed := False;
  Repaint;
end;

procedure TPixieSvgView.ParseSvg;
var
  Xml: string;
  Utf8: UTF8String;
begin
  FParsed := True;
  FSvgW := 0;
  FSvgH := 0;
  FRenderer.ClearDocument;
  Xml := FLines.Text;
  if Xml = '' then Exit;
  Utf8 := UTF8String(Xml);
  FRenderer.ParseSvg(Pointer(Utf8), Length(Utf8), FSvgW, FSvgH);
end;

procedure TPixieSvgView.Paint;
var
  CW, CH: Single;
  Sx, Sy, Scale, DstW, DstH, OffX, OffY: Single;
  BgColor, InnerColor, Inner2Color, BorderColor: TPixieWebColor;
begin
  if (FPixieCanvas = nil) or (Canvas = nil) then Exit;
  CW := Width;
  CH := Height;

  FPixieCanvas.SetViewSize(Round(CW), Round(CH), 1);
  FPixieCanvas.BeginPaint(PtrUInt(Pointer(Canvas)));
  try
    // Outer background (light grey default for FMX)
    BgColor := TPixieWebColor.Create($F0, $F0, $F0);
    FPixieCanvas.FillRect(0, 0, CW, CH, BgColor);

    if not FParsed then
      ParseSvg;
    if (FSvgW < 0.01) or (FSvgH < 0.01) then Exit;

    // Calculate proportional scale with zoom
    Sx := CW / FSvgW;
    Sy := CH / FSvgH;
    Scale := Min(Sx, Sy) * FZoom;
    DstW := FSvgW * Scale;
    DstH := FSvgH * Scale;

    OffX := 0;
    OffY := 0;
    case FAlignment of
      saCenterHorz:
        OffX := (CW - DstW) * 0.5;
      saCenterVert:
        OffY := (CH - DstH) * 0.5;
      saCenterBoth:
        begin OffX := (CW - DstW) * 0.5; OffY := (CH - DstH) * 0.5; end;
    end;

    // Inner area background and checkerboard
    if FColorCheckers <> claNull then
    begin
      InnerColor := AlphaColorToWebColor(FColorInner);
      Inner2Color := AlphaColorToWebColor(FColorCheckers);
      DrawCheckerboard(OffX, OffY, DstW, DstH, InnerColor, Inner2Color,
        FCheckersSize);
    end
    else if FColorInner <> claNull then
    begin
      InnerColor := AlphaColorToWebColor(FColorInner);
      FPixieCanvas.FillRect(OffX, OffY, DstW, DstH, InnerColor);
    end;

    // Inner border
    if FColorInnerBorder <> claNull then
    begin
      BorderColor := AlphaColorToWebColor(FColorInnerBorder);
      FPixieCanvas.FillRect(OffX, OffY, DstW, 1, BorderColor);
      FPixieCanvas.FillRect(OffX, OffY + DstH - 1, DstW, 1, BorderColor);
      FPixieCanvas.FillRect(OffX, OffY, 1, DstH, BorderColor);
      FPixieCanvas.FillRect(OffX + DstW - 1, OffY, 1, DstH, BorderColor);
    end;

    FRenderer.RenderToRect(OffX, OffY, DstW, DstH);
  finally
    FPixieCanvas.EndPaint;
  end;
end;

procedure TPixieSvgView.SaveAsPng(const FileName: string;
  Width, Height: Integer);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    SaveAsPng(Stream, Width, Height);
  finally
    Stream.Free;
  end;
end;

procedure TPixieSvgView.SaveAsPng(Stream: TStream; Width, Height: Integer);
var
  EffW, EffH: Integer;
begin
  EnsureParsed;
  if (FSvgW < 0.01) or (FSvgH < 0.01) then Exit;
  EffW := Width;
  EffH := Height;
  if EffW <= 0 then EffW := Round(FSvgW);
  if EffH <= 0 then EffH := Round(FSvgH);
  FPixieCanvas.BeginOffscreen(EffW, EffH, TPixieWebColor.Transparent);
  try
    FRenderer.RenderToRect(0, 0, EffW, EffH);
    FPixieCanvas.SaveAsPng(Stream);
  finally
    FPixieCanvas.EndOffscreen;
  end;
end;

procedure TPixieSvgView.SaveAsBmp(const FileName: string;
  Width, Height: Integer);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    SaveAsBmp(Stream, Width, Height);
  finally
    Stream.Free;
  end;
end;

procedure TPixieSvgView.SaveAsBmp(Stream: TStream; Width, Height: Integer);
var
  EffW, EffH: Integer;
begin
  EnsureParsed;
  if (FSvgW < 0.01) or (FSvgH < 0.01) then Exit;
  EffW := Width;
  EffH := Height;
  if EffW <= 0 then EffW := Round(FSvgW);
  if EffH <= 0 then EffH := Round(FSvgH);
  FPixieCanvas.BeginOffscreen(EffW, EffH, TPixieWebColor.Transparent);
  try
    FRenderer.RenderToRect(0, 0, EffW, EffH);
    FPixieCanvas.SaveAsBmp(Stream);
  finally
    FPixieCanvas.EndOffscreen;
  end;
end;

end.
