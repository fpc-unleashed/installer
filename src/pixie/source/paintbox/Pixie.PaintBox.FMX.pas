unit Pixie.PaintBox.FMX;

// TPixiePaintBox — Delphi FMX simple drawing surface.
// Renders via FMX canvas, fires OnPaint with TPixieDrawingCanvas.

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  FMX.Controls, FMX.Types, FMX.Graphics,
  Pixie.Types, Pixie.WebColor, Pixie.Canvas, Pixie.Canvas.FMX,
  Pixie.DrawingCanvas;

type
  { TPixiePaintBox }

  TPixiePaintBox = class(TControl)
  private
    FPixieCanvas: TPixieCanvas;
    FDrawingCanvas: TPixieDrawingCanvas;
    FOnPaint: TPixiePaintEvent;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property OnPaint: TPixiePaintEvent read FOnPaint write FOnPaint;

    property Align;
    property Anchors;
    property Size;
    property Visible;

    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseMove;
    property OnMouseUp;
    property OnResized;
  end;

implementation

constructor TPixiePaintBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 200;
  Height := 150;
  FPixieCanvas := TPixieFmxCanvas.Create;
  FDrawingCanvas := TPixieDrawingCanvas.Create;
end;

destructor TPixiePaintBox.Destroy;
begin
  FDrawingCanvas.Free;
  FPixieCanvas.Free;
  inherited Destroy;
end;

procedure TPixiePaintBox.Paint;
var
  BgColor: TPixieWebColor;
begin
  if (FPixieCanvas = nil) or (Canvas = nil) then Exit;
  FPixieCanvas.SetViewSize(Round(Width), Round(Height), 1);
  FPixieCanvas.BeginPaint(PtrUInt(Pointer(Canvas)));
  try
    BgColor := TPixieWebColor.Create($FF, $FF, $FF);
    FPixieCanvas.FillRect(0, 0, Width, Height, BgColor);
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
