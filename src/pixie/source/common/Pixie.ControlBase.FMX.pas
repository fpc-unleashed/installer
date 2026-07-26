unit Pixie.ControlBase.FMX;

// TPixieFmxControlBase — abstract base for all Pixie visual components (FMX).
// Creates a TPixieFmxCanvas and provides the Paint lifecycle.
// Mirrors the Lazarus TPixieControlBase and VCL TPixieVclControlBase.

interface

uses
  System.SysUtils, System.Classes,
  FMX.Controls, FMX.Types, FMX.Graphics,
  Pixie.Types, Pixie.WebColor, Pixie.Canvas, Pixie.Canvas.FMX;

type
  { TPixieFmxControlBase }

  TPixieFmxControlBase = class(TControl)
  private
    FPixieCanvas: TPixieCanvas;
  protected
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

constructor TPixieFmxControlBase.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPixieCanvas := TPixieFmxCanvas.Create;
end;

destructor TPixieFmxControlBase.Destroy;
begin
  FreeAndNil(FPixieCanvas);
  inherited Destroy;
end;

function TPixieFmxControlBase.GetBackgroundColor: TPixieWebColor;
begin
  Result := TPixieWebColor.White;
end;

function TPixieFmxControlBase.GetPaintHandle: PtrUInt;
begin
  Result := PtrUInt(Pointer(Canvas));
end;

procedure TPixieFmxControlBase.Paint;
begin
  if (FPixieCanvas = nil) or (Canvas = nil) then
    Exit;
  DoPaint;
end;

end.
