unit Pixie.Borders;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Math, Pixie.Types, Pixie.CssLength, Pixie.WebColor, Pixie.Utils;

type
  { TPixieCssBorder }
  TPixieCssBorder = record
    Width: TPixieCssLength;
    Style: TPixieBorderStyle;
    Color: TPixieWebColor;
    procedure Init;
    function ToString: string;
  end;

  { TPixieBorder }
  TPixieBorder = record
    Width: TPixiePixel;
    Style: TPixieBorderStyle;
    Color: TPixieWebColor;
    procedure Init;
    procedure InitFromCss(const CssBorder: TPixieCssBorder);
  end;

  { TPixieBorderRadiuses }
  TPixieBorderRadiuses = record
    TopLeftX: TPixiePixel;
    TopLeftY: TPixiePixel;
    TopRightX: TPixiePixel;
    TopRightY: TPixiePixel;
    BottomRightX: TPixiePixel;
    BottomRightY: TPixiePixel;
    BottomLeftX: TPixiePixel;
    BottomLeftY: TPixiePixel;
    procedure Init;
    procedure FixValues; overload;
    procedure FixValues(AWidth, AHeight: TPixiePixel); overload;
    function HasRadius: Boolean;
    procedure AddMargins(const Mg: TPixieMargins);
    procedure SubMargins(const Mg: TPixieMargins);
  end;

  { TPixieCssBorderRadius }
  TPixieCssBorderRadius = record
    TopLeftX: TPixieCssLength;
    TopLeftY: TPixieCssLength;
    TopRightX: TPixieCssLength;
    TopRightY: TPixieCssLength;
    BottomRightX: TPixieCssLength;
    BottomRightY: TPixieCssLength;
    BottomLeftX: TPixieCssLength;
    BottomLeftY: TPixieCssLength;
    function CalcPercents(AWidth, AHeight: TPixiePixel): TPixieBorderRadiuses;
  end;

  { TPixieCssBorders }
  TPixieCssBorders = record
    Left: TPixieCssBorder;
    Top: TPixieCssBorder;
    Right: TPixieCssBorder;
    Bottom: TPixieCssBorder;
    Radius: TPixieCssBorderRadius;
    function IsVisible: Boolean;
    function ToString: string;
  end;

  { TPixieBorders }
  TPixieBorders = record
    Left: TPixieBorder;
    Top: TPixieBorder;
    Right: TPixieBorder;
    Bottom: TPixieBorder;
    Radius: TPixieBorderRadiuses;
    procedure Init;
    procedure InitUniform(AWidth: TPixiePixel; AStyle: TPixieBorderStyle;
      AColor: TPixieWebColor);
    procedure InitFromCss(const CssBorders: TPixieCssBorders);
    function IsVisible: Boolean;
    procedure ResolveOutsetInset;
  end;

implementation

{ TPixieCssBorder }

procedure TPixieCssBorder.Init;
begin
  Self := Default(TPixieCssBorder);
end;

function TPixieCssBorder.ToString: string;
begin
  Result := Width.ToString + '/' + PixieIndexValue(Ord(Style), BorderStyleStrings) + '/' + Color.ToString;
end;

{ TPixieBorder }

procedure TPixieBorder.Init;
begin
  Self := Default(TPixieBorder);
end;

procedure TPixieBorder.InitFromCss(const CssBorder: TPixieCssBorder);
begin
  Width := CssBorder.Width.Val;
  Style := CssBorder.Style;
  Color := CssBorder.Color;
end;

{ TPixieBorderRadiuses }

procedure TPixieBorderRadiuses.Init;
begin
  Self := Default(TPixieBorderRadiuses);
end;

procedure TPixieBorderRadiuses.FixValues;
begin
  if TopLeftX < 0 then TopLeftX := 0;
  if TopLeftY < 0 then TopLeftY := 0;
  if TopRightX < 0 then TopRightX := 0;
  if TopRightY < 0 then TopRightY := 0;
  if BottomRightX < 0 then BottomRightX := 0;
  if BottomRightY < 0 then BottomRightY := 0;
  if BottomLeftX < 0 then BottomLeftX := 0;
  if BottomLeftY < 0 then BottomLeftY := 0;
end;

procedure TPixieBorderRadiuses.FixValues(AWidth, AHeight: TPixiePixel);
var
  HalfWidth, HalfHeight, Factor: TPixiePixel;
begin
  FixValues;
  HalfWidth := AWidth / 2;
  HalfHeight := AHeight / 2;

  if (TopLeftX > HalfWidth) or (TopLeftY > HalfHeight) then
  begin
    Factor := 1;
    if TopLeftX > 0 then Factor := HalfWidth / TopLeftX;
    if TopLeftY > 0 then Factor := Min(Factor, HalfHeight / TopLeftY);
    TopLeftX := TopLeftX * Factor;
    TopLeftY := TopLeftY * Factor;
  end;
  if (TopRightX > HalfWidth) or (TopRightY > HalfHeight) then
  begin
    Factor := 1;
    if TopRightX > 0 then Factor := HalfWidth / TopRightX;
    if TopRightY > 0 then Factor := Min(Factor, HalfHeight / TopRightY);
    TopRightX := TopRightX * Factor;
    TopRightY := TopRightY * Factor;
  end;
  if (BottomRightX > HalfWidth) or (BottomRightY > HalfHeight) then
  begin
    Factor := 1;
    if BottomRightX > 0 then Factor := HalfWidth / BottomRightX;
    if BottomRightY > 0 then Factor := Min(Factor, HalfHeight / BottomRightY);
    BottomRightX := BottomRightX * Factor;
    BottomRightY := BottomRightY * Factor;
  end;
  if (BottomLeftX > HalfWidth) or (BottomLeftY > HalfHeight) then
  begin
    Factor := 1;
    if BottomLeftX > 0 then Factor := HalfWidth / BottomLeftX;
    if BottomLeftY > 0 then Factor := Min(Factor, HalfHeight / BottomLeftY);
    BottomLeftX := BottomLeftX * Factor;
    BottomLeftY := BottomLeftY * Factor;
  end;
end;

function TPixieBorderRadiuses.HasRadius: Boolean;
begin
  Result := (TopLeftX > 0) or (TopLeftY > 0) or
            (TopRightX > 0) or (TopRightY > 0) or
            (BottomRightX > 0) or (BottomRightY > 0) or
            (BottomLeftX > 0) or (BottomLeftY > 0);
end;

procedure TPixieBorderRadiuses.AddMargins(const Mg: TPixieMargins);
begin
  TopLeftX := TopLeftX + Mg.Left;
  TopLeftY := TopLeftY + Mg.Top;
  TopRightX := TopRightX + Mg.Right;
  TopRightY := TopRightY + Mg.Top;
  BottomRightX := BottomRightX + Mg.Right;
  BottomRightY := BottomRightY + Mg.Bottom;
  BottomLeftX := BottomLeftX + Mg.Left;
  BottomLeftY := BottomLeftY + Mg.Bottom;
  FixValues;
end;

procedure TPixieBorderRadiuses.SubMargins(const Mg: TPixieMargins);
begin
  TopLeftX := TopLeftX - Mg.Left;
  TopLeftY := TopLeftY - Mg.Top;
  TopRightX := TopRightX - Mg.Right;
  TopRightY := TopRightY - Mg.Top;
  BottomRightX := BottomRightX - Mg.Right;
  BottomRightY := BottomRightY - Mg.Bottom;
  BottomLeftX := BottomLeftX - Mg.Left;
  BottomLeftY := BottomLeftY - Mg.Bottom;
  FixValues;
end;

{ TPixieCssBorderRadius }

function TPixieCssBorderRadius.CalcPercents(AWidth, AHeight: TPixiePixel): TPixieBorderRadiuses;
begin
  Result.BottomLeftX := BottomLeftX.CalcPercent(AWidth);
  Result.BottomLeftY := BottomLeftY.CalcPercent(AHeight);
  Result.TopLeftX := TopLeftX.CalcPercent(AWidth);
  Result.TopLeftY := TopLeftY.CalcPercent(AHeight);
  Result.TopRightX := TopRightX.CalcPercent(AWidth);
  Result.TopRightY := TopRightY.CalcPercent(AHeight);
  Result.BottomRightX := BottomRightX.CalcPercent(AWidth);
  Result.BottomRightY := BottomRightY.CalcPercent(AHeight);
  Result.FixValues(AWidth, AHeight);
end;

{ TPixieCssBorders }

function TPixieCssBorders.IsVisible: Boolean;
begin
  Result := (Left.Width.Val <> 0) or (Right.Width.Val <> 0) or
            (Top.Width.Val <> 0) or (Bottom.Width.Val <> 0);
end;

function TPixieCssBorders.ToString: string;
begin
  Result := 'left: ' + Left.ToString +
            ', top: ' + Top.ToString +
            ', right: ' + Right.ToString +
            ', bottom: ' + Bottom.ToString;
end;

{ TPixieBorders }

procedure TPixieBorders.Init;
begin
  Left.Init;
  Top.Init;
  Right.Init;
  Bottom.Init;
  Radius.Init;
end;

procedure TPixieBorders.InitUniform(AWidth: TPixiePixel;
  AStyle: TPixieBorderStyle; AColor: TPixieWebColor);
begin
  Init;
  Left.Width := AWidth;   Left.Style := AStyle;   Left.Color := AColor;
  Right.Width := AWidth;  Right.Style := AStyle;  Right.Color := AColor;
  Top.Width := AWidth;    Top.Style := AStyle;    Top.Color := AColor;
  Bottom.Width := AWidth; Bottom.Style := AStyle; Bottom.Color := AColor;
end;

procedure TPixieBorders.InitFromCss(const CssBorders: TPixieCssBorders);
begin
  Left.InitFromCss(CssBorders.Left);
  Right.InitFromCss(CssBorders.Right);
  Top.InitFromCss(CssBorders.Top);
  Bottom.InitFromCss(CssBorders.Bottom);
end;

function TPixieBorders.IsVisible: Boolean;
begin
  Result := (Left.Width <> 0) or (Right.Width <> 0) or
            (Top.Width <> 0) or (Bottom.Width <> 0);
end;

procedure TPixieBorders.ResolveOutsetInset;

  procedure ResolveSide(var Side: TPixieBorder; UseDark: Boolean);
  var
    C: TPixieWebColor;
  begin
    C := Side.Color;
    Side.Style := bsSolid;
    if UseDark then
      Side.Color := TPixieWebColor.Create(C.Red div 2, C.Green div 2, C.Blue div 2, C.Alpha)
    else
      Side.Color := TPixieWebColor.Create(
        C.Red + (255 - C.Red) div 2, C.Green + (255 - C.Green) div 2,
        C.Blue + (255 - C.Blue) div 2, C.Alpha);
  end;

begin
  if not (Top.Style in [bsOutset, bsInset]) and
     not (Left.Style in [bsOutset, bsInset]) and
     not (Bottom.Style in [bsOutset, bsInset]) and
     not (Right.Style in [bsOutset, bsInset]) then
    Exit;
  // Outset: light top/left, dark bottom/right. Inset: opposite.
  if Top.Style in [bsOutset, bsInset] then
    ResolveSide(Top, Top.Style = bsInset);
  if Left.Style in [bsOutset, bsInset] then
    ResolveSide(Left, Left.Style = bsInset);
  if Bottom.Style in [bsOutset, bsInset] then
    ResolveSide(Bottom, Bottom.Style = bsOutset);
  if Right.Style in [bsOutset, bsInset] then
    ResolveSide(Right, Right.Style = bsOutset);
end;

end.
