unit Pixie.CustomControl;

// TPixieCustomControl — interactive base for Pixie components (Lazarus).
// Adds focus, keyboard scaffolding, cursor management, and DoMouseLeave.
// Subclasses: TPixieHtmlView.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Controls, LMessages,
  Pixie.Types, Pixie.ControlBase;

type
  { TPixieCustomControl }

  TPixieCustomControl = class(TPixieControlBase)
  protected
    procedure CMMouseLeave(var Msg: TLMessage); message CM_MOUSELEAVE;
    procedure DoMouseLeave; virtual;
    procedure SetPixieCursor(ACursor: TPixieCursorKind);
  public
    constructor Create(AOwner: TComponent); override;
  end;

implementation

const
  CursorMap: array[TPixieCursorKind] of TCursor = (
    crDefault, crHandPoint, crIBeam, crCross, crSizeAll);

constructor TPixieCustomControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
end;

procedure TPixieCustomControl.CMMouseLeave(var Msg: TLMessage);
begin
  inherited;
  DoMouseLeave;
end;

procedure TPixieCustomControl.DoMouseLeave;
begin
end;

procedure TPixieCustomControl.SetPixieCursor(ACursor: TPixieCursorKind);
begin
  Self.Cursor := CursorMap[ACursor];
end;

end.
