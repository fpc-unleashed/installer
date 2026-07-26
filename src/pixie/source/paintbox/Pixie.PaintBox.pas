unit Pixie.PaintBox;

// TPixiePaintBox — simple drawing surface that exposes TPixieDrawingCanvas
// via an OnPaint event.  Inherits from TPixieControlBase (no focus).

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Controls, Graphics,
  Pixie.Types, Pixie.Canvas, Pixie.ControlBase, Pixie.DrawingCanvas;

type
  { TPixiePaintBox }

  TPixiePaintBox = class(TPixieControlBase)
  private
    FDrawingCanvas: TPixieDrawingCanvas;
    FOnPaint: TPixiePaintEvent;
  protected
    procedure DoPaint; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property OnPaint: TPixiePaintEvent read FOnPaint write FOnPaint;

    property Align;
    property Anchors;
    property BorderSpacing;
    property Color;
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
    property OnMouseWheel;
    property OnResize;
  end;

implementation

constructor TPixiePaintBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDrawingCanvas := TPixieDrawingCanvas.Create;
  Color := clWhite;
  Width := 200;
  Height := 150;
end;

destructor TPixiePaintBox.Destroy;
begin
  FDrawingCanvas.Free;
  inherited Destroy;
end;

procedure TPixiePaintBox.Resize;
begin
  inherited Resize;
  Invalidate;
end;

procedure TPixiePaintBox.DoPaint;
begin
  PixieCanvas.SetViewSize(ClientWidth, ClientHeight, GetCanvasScaleFactor);
  PixieCanvas.BeginPaint(GetPaintHandle);
  try
    PixieCanvas.FillRect(0, 0, ClientWidth, ClientHeight, GetBackgroundColor);
    if Assigned(FOnPaint) then
    begin
      FDrawingCanvas.Bind(PixieCanvas);
      try
        FOnPaint(Self, FDrawingCanvas);
      finally
        FDrawingCanvas.Unbind;
      end;
    end;
  finally
    PixieCanvas.EndPaint;
  end;
end;

end.
