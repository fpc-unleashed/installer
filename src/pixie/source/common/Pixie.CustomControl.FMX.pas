unit Pixie.CustomControl.FMX;

// TPixieFmxCustomControl — interactive base for Pixie components (FMX).
// Adds HitTest, cursor management.
// Mirrors the Lazarus TPixieCustomControl and VCL TPixieVclCustomControl.

interface

uses
  System.Classes, System.UITypes,
  FMX.Controls, FMX.Types,
  Pixie.Types, Pixie.ControlBase.FMX;

type
  { TPixieFmxCustomControl }

  TPixieFmxCustomControl = class(TPixieFmxControlBase)
  protected
    procedure SetPixieCursor(ACursor: TPixieCursorKind);
  public
    constructor Create(AOwner: TComponent); override;
  end;

implementation

const
  CursorMap: array[TPixieCursorKind] of TCursor = (
    crDefault, crHandPoint, crIBeam, crCross, crSizeAll);

constructor TPixieFmxCustomControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  HitTest := True;
end;

procedure TPixieFmxCustomControl.SetPixieCursor(ACursor: TPixieCursorKind);
begin
  Self.Cursor := CursorMap[ACursor];
end;

end.
