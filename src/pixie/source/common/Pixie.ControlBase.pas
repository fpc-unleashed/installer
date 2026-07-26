unit Pixie.ControlBase;

// TPixieControlBase — abstract base for all Pixie visual components (Lazarus).
// Creates a platform-specific TPixieCanvas and provides the Paint lifecycle.
// Subclasses override DoPaint to render their content.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Controls, Graphics, Forms, LMessages,
  Pixie.Types, Pixie.WebColor, Pixie.Canvas
  {$IF DEFINED(LCLqt) or DEFINED(LCLqt5) or DEFINED(LCLqt6)}
    , Pixie.Canvas.Qt
  {$ELSEIF DEFINED(MSWINDOWS)}
    , Pixie.Canvas.D2D
  {$ELSEIF DEFINED(DARWIN)}
    , Pixie.Canvas.CG
  {$ELSEIF DEFINED(UNIX)}
    , Pixie.Canvas.Cairo
  {$ENDIF};

type
  { TPixieControlBase }

  TPixieControlBase = class(TCustomControl)
  private
    FPixieCanvas: TPixieCanvas;
    procedure WMEraseBkgnd(var Msg: TLMEraseBkgnd); message LM_ERASEBKGND;
  protected
    procedure CreatePixieCanvas; virtual;
    function GetScaleFactor: Single; virtual;
    function GetBackgroundColor: TPixieWebColor; overload; virtual;
    function GetBackgroundColor(AColor: TColor): TPixieWebColor; overload;
    function GetPaintHandle: PtrUInt; virtual;
    procedure Paint; override;
    procedure DoPaint; virtual; abstract;
    property PixieCanvas: TPixieCanvas read FPixieCanvas;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

implementation

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

constructor TPixieControlBase.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  CreatePixieCanvas;
end;

destructor TPixieControlBase.Destroy;
begin
  FreeAndNil(FPixieCanvas);
  inherited Destroy;
end;

procedure TPixieControlBase.CreatePixieCanvas;
begin
  {$IF DEFINED(LCLqt) or DEFINED(LCLqt5) or DEFINED(LCLqt6)}
  FPixieCanvas := TPixieQtCanvas.Create;
  {$ELSEIF DEFINED(MSWINDOWS)}
  FPixieCanvas := TPixieD2DCanvas.Create;
  {$ELSEIF DEFINED(DARWIN)}
  FPixieCanvas := TPixieCGCanvas.Create;
  {$ELSEIF DEFINED(UNIX)}
  FPixieCanvas := TPixieCairoCanvas.Create;
  {$ENDIF}
end;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function TPixieControlBase.GetScaleFactor: Single;
var
  F: TCustomForm;
begin
  // Layout scale is PPI/96 on every widgetset because (PPI * CanvasScaleFactor)
  // is the unified effective DPI. Each widgetset splits fractional display
  // scaling differently between PPI and CanvasScaleFactor (e.g. GTK3 reports
  // PPI=144/CSF=1.0, Qt5/6 reports PPI=96/CSF=1.5), but the product is the
  // same and PPI/96 yields the correct layout multiplier regardless: the
  // canvas-level CanvasScaleFactor handles the rest of the upscale.
  F := GetParentForm(Self);
  if F <> nil then
    Result := F.PixelsPerInch / 96
  else
    Result := Screen.PixelsPerInch / 96;
end;

function TPixieControlBase.GetBackgroundColor: TPixieWebColor;
begin
  Result := GetBackgroundColor(Self.Color);
end;

function TPixieControlBase.GetBackgroundColor(AColor: TColor): TPixieWebColor;
var
  Rgb: LongInt;
begin
  Rgb := ColorToRGB(AColor);
  Result := TPixieWebColor.Create(
    Byte(Rgb), Byte(Rgb shr 8), Byte(Rgb shr 16));
end;

function TPixieControlBase.GetPaintHandle: PtrUInt;
begin
  Result := PtrUInt(inherited Canvas.Handle);
end;

// ---------------------------------------------------------------------------
// Painting
// ---------------------------------------------------------------------------

procedure TPixieControlBase.Paint;
begin
  if FPixieCanvas = nil then
  begin
    inherited Canvas.Brush.Color := Self.Color;
    inherited Canvas.FillRect(ClientRect);
    Exit;
  end;
  DoPaint;
end;

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

procedure TPixieControlBase.WMEraseBkgnd(var Msg: TLMEraseBkgnd);
begin
  Msg.Result := 1;
end;

end.
