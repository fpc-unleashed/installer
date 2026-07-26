unit Pixie.PaintBox.VCL;

// TPixiePaintBox — Delphi VCL simple drawing surface.
// Renders via Direct2D/DirectWrite, fires OnPaint with TPixieDrawingCanvas.

interface

uses
  SysUtils, Classes, Windows, Messages,
  Vcl.Controls, Vcl.Graphics,
  Pixie.Types, Pixie.WebColor, Pixie.Canvas, Pixie.Canvas.D2D,
  Pixie.DrawingCanvas;

type
  { TPixiePaintBox }

  TPixiePaintBox = class(TCustomControl)
  private
    FPixieCanvas: TPixieCanvas;
    FDrawingCanvas: TPixieDrawingCanvas;
    FOnPaint: TPixiePaintEvent;
    procedure WMEraseBkgnd(var Msg: TWMEraseBkgnd); message WM_ERASEBKGND;
    function GetScaleFactor: Single;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property OnPaint: TPixiePaintEvent read FOnPaint write FOnPaint;

    property Align;
    property Anchors;
    property Color default clWhite;
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

uses
  Vcl.Forms;

constructor TPixiePaintBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Color := clWhite;
  Width := 200;
  Height := 150;
  FPixieCanvas := TPixieD2DCanvas.Create;
  FDrawingCanvas := TPixieDrawingCanvas.Create;
end;

destructor TPixiePaintBox.Destroy;
begin
  FDrawingCanvas.Free;
  FPixieCanvas.Free;
  inherited Destroy;
end;

function TPixiePaintBox.GetScaleFactor: Single;
var
  F: TCustomForm;
begin
  F := GetParentForm(Self);
  if F <> nil then
    Result := F.PixelsPerInch / 96
  else
    Result := 1.0;
end;

procedure TPixiePaintBox.WMEraseBkgnd(var Msg: TWMEraseBkgnd);
begin
  Msg.Result := 1;
end;

procedure TPixiePaintBox.Paint;
var
  BgColor: TPixieWebColor;
  Rgb: LongInt;
begin
  if FPixieCanvas = nil then Exit;
  FPixieCanvas.SetViewSize(ClientWidth, ClientHeight, GetScaleFactor);
  FPixieCanvas.BeginPaint(NativeUInt(Canvas.Handle));
  try
    Rgb := ColorToRGB(Color);
    BgColor := TPixieWebColor.Create(
      Byte(Rgb), Byte(Rgb shr 8), Byte(Rgb shr 16));
    FPixieCanvas.FillRect(0, 0, ClientWidth, ClientHeight, BgColor);
    if Assigned(FOnPaint) then
    begin
      FDrawingCanvas.Bind(FPixieCanvas);
      try
        FOnPaint(Self, FDrawingCanvas);
      finally
        FDrawingCanvas.Unbind;
      end;
    end;
  finally
    FPixieCanvas.EndPaint;
  end;
end;

end.
