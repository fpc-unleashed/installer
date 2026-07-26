unit Pixie.ScrollView;

// Scroll state management for overflow containers.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Math,
  Pixie.Types;

type
  TPixieScrollView = class
  protected
    FViewport: TPixiePosition;
    FScrollSize: TPixieSize;
    FLeft: TPixiePixel;
    FTop: TPixiePixel;
  public
    constructor Create(const AViewport: TPixiePosition;
      const AScrollSize: TPixieSize);

    function GetLeft: TPixiePixel;
    function GetTop: TPixiePixel;

    function GetMaxHScroll: TPixiePixel;
    function GetMaxVScroll: TPixiePixel;

    procedure SetViewport(const AViewport: TPixiePosition;
      const AScrollSize: TPixieSize);
    function IsHScrollable(DX: TPixiePixel): Boolean;
    function IsVScrollable(DY: TPixiePixel): Boolean;

    function HScroll(DX: TPixiePixel): TPixiePixel;
    function VScroll(DY: TPixiePixel): TPixiePixel;

    function IsPointInside(X, Y: TPixiePixel): Boolean;
  end;

implementation

function Clamp(V, Lo, Hi: TPixiePixel): TPixiePixel; inline;
begin
  if V < Lo then
    Result := Lo
  else if V > Hi then
    Result := Hi
  else
    Result := V;
end;

constructor TPixieScrollView.Create(const AViewport: TPixiePosition;
  const AScrollSize: TPixieSize);
begin
  inherited Create;
  FViewport := AViewport;
  FScrollSize := AScrollSize;
  FLeft := 0;
  FTop := 0;
end;

function TPixieScrollView.GetLeft: TPixiePixel;
begin
  Result := FLeft;
end;

function TPixieScrollView.GetTop: TPixiePixel;
begin
  Result := FTop;
end;

function TPixieScrollView.GetMaxHScroll: TPixiePixel;
begin
  Result := Max(0, FScrollSize.Width - FViewport.Width);
end;

function TPixieScrollView.GetMaxVScroll: TPixiePixel;
begin
  Result := Max(0, FScrollSize.Height - FViewport.Height);
end;

procedure TPixieScrollView.SetViewport(const AViewport: TPixiePosition;
  const AScrollSize: TPixieSize);
begin
  FViewport := AViewport;
  FScrollSize := AScrollSize;
  FLeft := Clamp(FLeft, 0, GetMaxHScroll);
  FTop := Clamp(FTop, 0, GetMaxVScroll);
end;

function TPixieScrollView.IsHScrollable(DX: TPixiePixel): Boolean;
begin
  if FScrollSize.Width = 0 then
    Exit(False);
  Result := FLeft <> Clamp(FLeft + DX, 0, GetMaxHScroll);
end;

function TPixieScrollView.IsVScrollable(DY: TPixiePixel): Boolean;
begin
  if FScrollSize.Height = 0 then
    Exit(False);
  Result := FTop <> Clamp(FTop + DY, 0, GetMaxVScroll);
end;

function TPixieScrollView.HScroll(DX: TPixiePixel): TPixiePixel;
var
  NewLeft: TPixiePixel;
begin
  if FScrollSize.Width = 0 then
    Exit(0);
  NewLeft := Clamp(FLeft + DX, 0, GetMaxHScroll);
  Result := NewLeft - FLeft;
  FLeft := NewLeft;
end;

function TPixieScrollView.VScroll(DY: TPixiePixel): TPixiePixel;
var
  NewTop: TPixiePixel;
begin
  if FScrollSize.Height = 0 then
    Exit(0);
  NewTop := Clamp(FTop + DY, 0, GetMaxVScroll);
  Result := NewTop - FTop;
  FTop := NewTop;
end;

function TPixieScrollView.IsPointInside(X, Y: TPixiePixel): Boolean;
begin
  Result := FViewport.IsPointInside(X, Y);
end;

end.
