unit Pixie.RenderInline;

// Inline element render item — wraps inline containers (<span> etc.)
// that can span multiple lines via inline boxes.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Pixie.Types, Pixie.Element, Pixie.RenderItem;

type
  { TPixieRenderInline }
  TPixieRenderInline = class(TPixieRenderItem)
  protected
    FBoxes: TPixiePositionVector;
  public
    constructor Create(ASrcEl: TPixieElement); override;
    destructor Destroy; override;
    function Clone: TPixieRenderItem; override;

    procedure GetInlineBoxes(Boxes: TPixiePositionVector); override;
    procedure AddInlineBox(const Box: TPixiePosition); override;
    procedure ClearInlineBoxes; override;

    function GetFirstBaseline: TPixiePixel; override;
    function GetLastBaseline: TPixiePixel; override;

    procedure YShift(Delta: TPixiePixel); override;
  end;

implementation

{ TPixieRenderInline }

constructor TPixieRenderInline.Create(ASrcEl: TPixieElement);
begin
  inherited Create(ASrcEl);
  FBoxes := TPixiePositionVector.Create;
end;

destructor TPixieRenderInline.Destroy;
begin
  FBoxes.Free;
  inherited Destroy;
end;

function TPixieRenderInline.Clone: TPixieRenderItem;
begin
  Result := TPixieRenderInline.Create(FElement);
end;

procedure TPixieRenderInline.GetInlineBoxes(Boxes: TPixiePositionVector);
var
  I: Integer;
begin
  Boxes.Clear;
  for I := 0 to FBoxes.Count - 1 do
    Boxes.Add(FBoxes[I]);
end;

procedure TPixieRenderInline.AddInlineBox(const Box: TPixiePosition);
begin
  FBoxes.Add(Box);
end;

procedure TPixieRenderInline.ClearInlineBoxes;
begin
  FBoxes.Clear;
end;

function TPixieRenderInline.GetFirstBaseline: TPixiePixel;
begin
  Result := SrcEl.Css.FontMetrics.Height - SrcEl.Css.FontMetrics.BaseLine;
end;

function TPixieRenderInline.GetLastBaseline: TPixiePixel;
begin
  Result := SrcEl.Css.FontMetrics.Height - SrcEl.Css.FontMetrics.BaseLine;
end;

procedure TPixieRenderInline.YShift(Delta: TPixiePixel);
var
  I: Integer;
  Tmp: TPixiePosition;
begin
  if Css.Display = displayInlineText then
    inherited YShift(Delta);
  for I := 0 to FBoxes.Count - 1 do
  begin
    Tmp := FBoxes[I];
    Tmp.Y := Tmp.Y + Delta;
    FBoxes[I] := Tmp;
  end;
end;

end.
