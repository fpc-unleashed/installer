unit Pixie.SvgView;

// TPixieSvgView — displays SVG content rendered via TPixieCanvas.
// Scales proportionally and supports alignment options.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Controls, Graphics, Math,
  Pixie.Types, Pixie.WebColor, Pixie.Canvas,
  Pixie.SvgRenderer, Pixie.SvgRenderer.Canvas,
  Pixie.ControlBase;

type
  TPixieSvgAlign = (
    saTopLeft,
    saCenterHorz,
    saCenterVert,
    saCenterBoth
  );

  { TPixieSvgView }

  TPixieSvgView = class(TPixieControlBase)
  private
    FLines: TStringList;
    FRenderer: TPixieSvgCanvasRenderer;
    FAlignment: TPixieSvgAlign;
    FSvgW: Single;
    FSvgH: Single;
    FParsed: Boolean;
    FColorInner: TColor;
    FColorInnerBorder: TColor;
    FColorCheckers: TColor;
    FCheckersSize: Integer;
    FZoom: Double;

    procedure LinesChanged(Sender: TObject);
    procedure ParseSvg;
    procedure EnsureParsed;
    function GetLines: TStrings;
    procedure SetLines(Value: TStrings);
    procedure SetAlignment(Value: TPixieSvgAlign);
    procedure SetColorInner(Value: TColor);
    procedure SetColorInnerBorder(Value: TColor);
    procedure SetColorCheckers(Value: TColor);
    procedure SetCheckersSize(Value: Integer);
    procedure SetZoom(const Value: Double);
    function GetImageWidth: Single;
    function GetImageHeight: Single;
    procedure DrawCheckerboard(X, Y, W, H: Single;
      const C1, C2: TPixieWebColor; CellSize: Integer);
  protected
    procedure DoPaint; override;
    procedure Resize; override;
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
    property ColorInner: TColor
      read FColorInner write SetColorInner default clNone;
    property ColorInnerBorder: TColor
      read FColorInnerBorder write SetColorInnerBorder default clNone;
    property ColorCheckers: TColor
      read FColorCheckers write SetColorCheckers default clNone;
    property CheckersSize: Integer
      read FCheckersSize write SetCheckersSize default 8;
    property Zoom: Double
      read FZoom write SetZoom;

    property Align;
    property Anchors;
    property BorderSpacing;
    property Color default clNone;
    property Constraints;
    property Enabled;
    property Visible;

    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseMove;
    property OnMouseUp;
    property OnResize;
  end;

implementation

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

constructor TPixieSvgView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle - [csOpaque];
  Color := clNone;
  Width := 100;
  Height := 100;

  FLines := TStringList.Create;
  FLines.OnChange := LinesChanged;
  FRenderer := TPixieSvgCanvasRenderer.Create(PixieCanvas);
  FAlignment := saCenterBoth;
  FSvgW := 0;
  FSvgH := 0;
  FParsed := False;
  FColorInner := clNone;
  FColorInnerBorder := clNone;
  FColorCheckers := clNone;
  FCheckersSize := 8;
  FZoom := 1.0;
end;

destructor TPixieSvgView.Destroy;
begin
  FreeAndNil(FRenderer);
  FreeAndNil(FLines);
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Properties
// ---------------------------------------------------------------------------

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
    Invalidate;
  end;
end;

procedure TPixieSvgView.SetColorInner(Value: TColor);
begin
  if FColorInner <> Value then
  begin
    FColorInner := Value;
    Invalidate;
  end;
end;

procedure TPixieSvgView.SetColorInnerBorder(Value: TColor);
begin
  if FColorInnerBorder <> Value then
  begin
    FColorInnerBorder := Value;
    Invalidate;
  end;
end;

procedure TPixieSvgView.SetColorCheckers(Value: TColor);
begin
  if FColorCheckers <> Value then
  begin
    FColorCheckers := Value;
    Invalidate;
  end;
end;

procedure TPixieSvgView.SetCheckersSize(Value: Integer);
begin
  if Value < 1 then Value := 1;
  if FCheckersSize <> Value then
  begin
    FCheckersSize := Value;
    Invalidate;
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
  Invalidate;
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

procedure TPixieSvgView.DrawCheckerboard(X, Y, W, H: Single;
  const C1, C2: TPixieWebColor; CellSize: Integer);
var
  Row, Col, Cols, Rows: Integer;
  CX, CY, CW, CH: Single;
begin
  PixieCanvas.FillRect(X, Y, W, H, C1);
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
          PixieCanvas.FillRect(CX, CY, CW, CH, C2);
      end;
end;

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

procedure TPixieSvgView.LoadFromFile(const FileName: string);
begin
  FLines.LoadFromFile(FileName);
end;

procedure TPixieSvgView.LoadFromStream(Stream: TStream);
begin
  FLines.LoadFromStream(Stream);
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
// SVG parsing
// ---------------------------------------------------------------------------

procedure TPixieSvgView.LinesChanged(Sender: TObject);
begin
  FParsed := False;
  Invalidate;
end;

procedure TPixieSvgView.ParseSvg;
var
  Xml: string;
begin
  FParsed := True;
  FSvgW := 0;
  FSvgH := 0;
  FRenderer.ClearDocument;

  Xml := FLines.Text;
  if Xml = '' then Exit;

  FRenderer.ParseSvg(Pointer(Xml), Length(Xml) * SizeOf(Char), FSvgW, FSvgH);
end;

// ---------------------------------------------------------------------------
// Painting
// ---------------------------------------------------------------------------

procedure TPixieSvgView.Resize;
begin
  inherited Resize;
  Invalidate;
end;

procedure TPixieSvgView.DoPaint;
var
  CW, CH: Single;
  Sx, Sy, Scale, DstW, DstH, OffX, OffY: Single;
  BgColor, InnerColor, Inner2Color, BorderColor: TPixieWebColor;
begin
  CW := ClientWidth;
  CH := ClientHeight;

  PixieCanvas.SetViewSize(Round(CW), Round(CH), GetCanvasScaleFactor);
  PixieCanvas.BeginPaint(GetPaintHandle);
  try
    // Outer background: use parent colour when Color = clNone
    if Color = clNone then
      BgColor := GetBackgroundColor(ColorToRGB(clBtnFace))
    else
      BgColor := GetBackgroundColor;
    PixieCanvas.FillRect(0, 0, CW, CH, BgColor);

    // Parse if needed
    if not FParsed then
      ParseSvg;

    if (FSvgW < 0.01) or (FSvgH < 0.01) then Exit;

    // Calculate proportional scale with zoom
    Sx := CW / FSvgW;
    Sy := CH / FSvgH;
    Scale := Min(Sx, Sy) * FZoom;
    DstW := FSvgW * Scale;
    DstH := FSvgH * Scale;

    // Alignment offset
    OffX := 0;
    OffY := 0;
    case FAlignment of
      saCenterHorz:
        OffX := (CW - DstW) * 0.5;
      saCenterVert:
        OffY := (CH - DstH) * 0.5;
      saCenterBoth:
        begin
          OffX := (CW - DstW) * 0.5;
          OffY := (CH - DstH) * 0.5;
        end;
    end;

    // Inner area background and checkerboard
    if FColorCheckers <> clNone then
    begin
      InnerColor := GetBackgroundColor(ColorToRGB(FColorInner));
      Inner2Color := GetBackgroundColor(ColorToRGB(FColorCheckers));
      DrawCheckerboard(OffX, OffY, DstW, DstH, InnerColor, Inner2Color,
        FCheckersSize);
    end
    else if FColorInner <> clNone then
    begin
      InnerColor := GetBackgroundColor(ColorToRGB(FColorInner));
      PixieCanvas.FillRect(OffX, OffY, DstW, DstH, InnerColor);
    end;

    // Inner border
    if FColorInnerBorder <> clNone then
    begin
      BorderColor := GetBackgroundColor(ColorToRGB(FColorInnerBorder));
      PixieCanvas.FillRect(OffX, OffY, DstW, 1, BorderColor);
      PixieCanvas.FillRect(OffX, OffY + DstH - 1, DstW, 1, BorderColor);
      PixieCanvas.FillRect(OffX, OffY, 1, DstH, BorderColor);
      PixieCanvas.FillRect(OffX + DstW - 1, OffY, 1, DstH, BorderColor);
    end;

    FRenderer.RenderToRect(OffX, OffY, DstW, DstH);
  finally
    PixieCanvas.EndPaint;
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
  PixieCanvas.BeginOffscreen(EffW, EffH, TPixieWebColor.Transparent);
  try
    FRenderer.RenderToRect(0, 0, EffW, EffH);
    PixieCanvas.SaveAsPng(Stream);
  finally
    PixieCanvas.EndOffscreen;
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
  PixieCanvas.BeginOffscreen(EffW, EffH, TPixieWebColor.Transparent);
  try
    FRenderer.RenderToRect(0, 0, EffW, EffH);
    PixieCanvas.SaveAsBmp(Stream);
  finally
    PixieCanvas.EndOffscreen;
  end;
end;

end.
