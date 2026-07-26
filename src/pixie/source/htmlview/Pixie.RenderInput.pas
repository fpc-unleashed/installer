unit Pixie.RenderInput;

// Render item for <input type="checkbox"> and <input type="radio"> —
// replaced elements with intrinsic size, no aspect ratio logic needed.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Pixie.Types, Pixie.CssLength, Pixie.CssProperties,
  Pixie.Element, Pixie.FormattingContext, Pixie.RenderItem;

type
  { TPixieRenderInput }
  TPixieRenderInput = class(TPixieRenderItem)
  protected
    function _Render(X, Y: TPixiePixel;
      const CbContext: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext;
      SecondPass: Boolean): TPixiePixel; override;
  public
    constructor Create(ASrcEl: TPixieElement); override;
    function Clone: TPixieRenderItem; override;
  end;

implementation

uses
  Pixie.Document;

{ TPixieRenderInput }

constructor TPixieRenderInput.Create(ASrcEl: TPixieElement);
begin
  inherited Create(ASrcEl);
end;

function TPixieRenderInput.Clone: TPixieRenderItem;
begin
  Result := TPixieRenderInput.Create(FElement);
end;

function TPixieRenderInput._Render(X, Y: TPixiePixel;
  const CbContext: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext;
  SecondPass: Boolean): TPixiePixel;
var
  ParentWidth: TPixiePixel;
  SelfSize: TPixieContainingBlockContext;
  Sz: TPixieSize;
begin
  ParentWidth := CbContext.Width.Value;

  // CalcOutlines must precede CalculateContainingBlockContext so that
  // BoxSizingWidth/Height use the actual padding and border values.
  CalcOutlines(ParentWidth);

  SelfSize := CalculateContainingBlockContext(CbContext);

  FPos.MoveTo(X, Y);

  SrcEl.GetContentSize(Sz, ParentWidth);

  // Use CSS width if set (box-sizing aware), else intrinsic
  if SelfSize.RenderWidth.ValueType <> cbcAuto then
    FPos.Width := SelfSize.RenderWidth.Value
  else
    FPos.Width := Sz.Width;

  // Use CSS height if set (box-sizing aware), else intrinsic
  if (SelfSize.Height.ValueType <> cbcAuto) and
     (SelfSize.Height.Value > 0) then
    FPos.Height := SelfSize.Height.Value - BoxSizingHeight
  else
    FPos.Height := Sz.Height;

  FPos.X := FPos.X + ContentOffsetLeft;
  FPos.Y := FPos.Y + ContentOffsetTop;

  Result := FPos.Width + ContentOffsetLeft + ContentOffsetRight;
end;

end.
