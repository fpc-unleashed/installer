unit Pixie.CustomControl.VCL;

// TPixieVclCustomControl — interactive base for Pixie components (VCL).
// Adds focus, keyboard scaffolding, cursor management, and DoMouseLeave.
// Mirrors the Lazarus TPixieCustomControl.

interface

uses
  Classes, Messages, Vcl.Controls,
  Pixie.Types, Pixie.ControlBase.VCL;

type
  { TPixieVclCustomControl }

  TPixieVclCustomControl = class(TPixieVclControlBase)
  protected
    procedure CMMouseLeave(var Msg: TMessage); message CM_MOUSELEAVE;
    procedure DoMouseLeave; virtual;
    procedure SetPixieCursor(ACursor: TPixieCursorKind);
  public
    constructor Create(AOwner: TComponent); override;
  end;

implementation

const
  CursorMap: array[TPixieCursorKind] of TCursor = (
    crDefault, crHandPoint, crIBeam, crCross, crSizeAll);

constructor TPixieVclCustomControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
end;

procedure TPixieVclCustomControl.CMMouseLeave(var Msg: TMessage);
begin
  inherited;
  DoMouseLeave;
end;

procedure TPixieVclCustomControl.DoMouseLeave;
begin
end;

procedure TPixieVclCustomControl.SetPixieCursor(ACursor: TPixieCursorKind);
begin
  Self.Cursor := CursorMap[ACursor];
end;

end.
