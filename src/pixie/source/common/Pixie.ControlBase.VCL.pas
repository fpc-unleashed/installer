unit Pixie.ControlBase.VCL;

// TPixieVclControlBase — abstract base for all Pixie visual components (VCL).
// Creates a D2D TPixieCanvas and provides the Paint lifecycle.
// Mirrors the Lazarus TPixieControlBase.

interface

uses
  SysUtils, Classes, Windows, Messages,
  Vcl.Controls, Vcl.Graphics, Vcl.Forms,
  Pixie.Types, Pixie.WebColor, Pixie.Canvas, Pixie.Canvas.D2D;

type
  { TPixieVclControlBase }

  TPixieVclControlBase = class(TCustomControl)
  private
    FPixieCanvas: TPixieCanvas;
    procedure WMEraseBkgnd(var Msg: TWMEraseBkgnd); message WM_ERASEBKGND;
  protected
    function GetScaleFactor: Single; virtual;
    function GetCanvasScaleFactor: Single; virtual;
    function GetBackgroundColor: TPixieWebColor; virtual;
    function GetPaintHandle: PtrUInt; virtual;
    procedure Paint; override;
    procedure DoPaint; virtual; abstract;
    property PixieCanvas: TPixieCanvas read FPixieCanvas;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

implementation

constructor TPixieVclControlBase.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FPixieCanvas := TPixieD2DCanvas.Create;
end;

destructor TPixieVclControlBase.Destroy;
begin
  FreeAndNil(FPixieCanvas);
  inherited Destroy;
end;

function TPixieVclControlBase.GetScaleFactor: Single;
var
  F: TCustomForm;
begin
  F := GetParentForm(Self);
  if F <> nil then
    Result := F.PixelsPerInch / 96
  else
    Result := 1.0;
end;

function TPixieVclControlBase.GetCanvasScaleFactor: Single;
begin
  Result := 1.0;
end;

function TPixieVclControlBase.GetBackgroundColor: TPixieWebColor;
var
  Rgb: Integer;
begin
  Rgb := ColorToRGB(Self.Color);
  Result := TPixieWebColor.Create(
    Byte(Rgb), Byte(Rgb shr 8), Byte(Rgb shr 16));
end;

function TPixieVclControlBase.GetPaintHandle: PtrUInt;
begin
  Result := PtrUInt(inherited Canvas.Handle);
end;

procedure TPixieVclControlBase.Paint;
begin
  if FPixieCanvas = nil then
  begin
    inherited Canvas.Brush.Color := Self.Color;
    inherited Canvas.FillRect(ClientRect);
    Exit;
  end;
  DoPaint;
end;

procedure TPixieVclControlBase.WMEraseBkgnd(var Msg: TWMEraseBkgnd);
begin
  Msg.Result := 1;
end;

end.
