unit Pixie.ElProgress;

// Owner-drawn <progress> and <meter> elements. Both are replaced elements
// that draw a rounded track bar with a value-proportional filled portion.
// <progress> shows task completion (single value/max); <meter> shows a
// scalar measurement within a known range and colours the fill green/yellow/
// red according to the low/high/optimum thresholds (HTML rendering spec).

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils,
  Pixie.Types, Pixie.WebColor,
  Pixie.Container,
  Pixie.Element, Pixie.HtmlTag;

type
  { TPixieElProgress }

  TPixieElProgress = class(TPixieHtmlTag)
  public
    function IsReplaced: Boolean; override;
    procedure GetContentSize(var Sz: TPixieSize;
      MaxWidth: TPixiePixel); override;
    procedure Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
      Clip: PPixiePosition; Ri: Pointer); override;
    function CreateRenderItem(ParentRi: Pointer): Pointer; override;
    function DumpGetName: string; override;
  end;

  { TPixieElMeter }

  TPixieElMeter = class(TPixieHtmlTag)
  public
    function IsReplaced: Boolean; override;
    procedure GetContentSize(var Sz: TPixieSize;
      MaxWidth: TPixiePixel); override;
    procedure Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
      Clip: PPixiePosition; Ri: Pointer); override;
    function CreateRenderItem(ParentRi: Pointer): Pointer; override;
    function DumpGetName: string; override;
  end;

implementation

uses
  Math,
  Pixie.Utils, Pixie.Borders,
  Pixie.Canvas, Pixie.NativeContainer,
  Pixie.RenderItem, Pixie.RenderInput;

const
  GaugeDefaultWidth = 160;
  GaugeDefaultHeight = 16;

function GetCanvas(Tag: TPixieHtmlTag): TPixieCanvas;
var
  Cont: TPixieContainer;
begin
  Result := nil;
  Cont := Tag.GetDocContainer;
  if (Cont <> nil) and (Cont is TPixieNativeContainer) then
    Result := TPixieNativeContainer(Cont).Canvas;
end;

// Parse a floating-point attribute. Returns Default and Present=False when the
// attribute is absent or not a valid number; otherwise the parsed value with
// Present=True. Uses System.Val so the decimal point is locale-independent.
function AttrFloat(Tag: TPixieHtmlTag; const Name: string;
  Default: Single; out Present: Boolean): Single;
var
  Stripped: string;
  Code: Integer;
begin
  Result := Default;
  Present := False;
  Stripped := PixieExtractFloat(PixieTrim(Tag.GetAttr(Name)));
  if Stripped = '' then Exit;
  System.Val(Stripped, Result, Code);
  if Code <> 0 then
  begin
    Result := Default;
    Exit;
  end;
  Present := True;
end;

// Resolve the bar geometry shared by both elements from the render item.
function GaugeRect(Ri: Pointer; X, Y: TPixiePixel;
  out P: TPixiePosition): Boolean;
var
  RenderIt: TPixieRenderItem;
begin
  RenderIt := TPixieRenderItem(Ri);
  P := RenderIt.Pos;
  P.X := P.X + X;
  P.Y := P.Y + Y;
  Result := (P.Width > 0) and (P.Height > 0);
end;

procedure DrawTrack(Cv: TPixieCanvas; const P: TPixiePosition; Radius: Single);
begin
  Cv.FillRoundedRect(P.X, P.Y, P.Width, P.Height, Radius,
    TPixieWebColor.Create(230, 230, 230));
end;

// Clip subsequent drawing to the rounded "pill" (stadium) outline of the bar.
// Caller must SaveState first and RestoreState afterwards.
procedure ClipToPill(Cv: TPixieCanvas; X, Y, W, H: Single);
const
  Kappa = 0.5522847498;
var
  R, K: Single;
begin
  R := H / 2;
  if R > W / 2 then R := W / 2;
  K := R * Kappa;
  Cv.BeginPath;
  Cv.MoveTo(X + R, Y);
  Cv.LineTo(X + W - R, Y);
  Cv.CurveTo(X + W - R + K, Y, X + W, Y + R - K, X + W, Y + R);
  Cv.CurveTo(X + W, Y + R + K, X + W - R + K, Y + H, X + W - R, Y + H);
  Cv.LineTo(X + R, Y + H);
  Cv.CurveTo(X + R - K, Y + H, X, Y + R + K, X, Y + R);
  Cv.CurveTo(X, Y + R - K, X + R - K, Y, X + R, Y);
  Cv.ClosePath;
  Cv.ClipPath;
end;

// Fill the bar with diagonal candy-stripes — a static stand-in for the
// browser's animated indeterminate sweep. Stripes are clipped to the pill so
// the rounded ends stay clean.
procedure DrawIndeterminateStripes(Cv: TPixieCanvas; const P: TPixiePosition;
  Color: TPixieWebColor);
var
  StripeW, Period, SX: Single;
begin
  Cv.SaveState;
  try
    ClipToPill(Cv, P.X, P.Y, P.Width, P.Height);
    StripeW := P.Height * 0.6;
    Period := StripeW * 2;
    SX := P.X - P.Height;
    while SX < P.X + P.Width + P.Height do
    begin
      Cv.BeginPath;
      Cv.MoveTo(SX, P.Y + P.Height);
      Cv.LineTo(SX + P.Height, P.Y);
      Cv.LineTo(SX + P.Height + StripeW, P.Y);
      Cv.LineTo(SX + StripeW, P.Y + P.Height);
      Cv.ClosePath;
      Cv.FillPath(Color);
      SX := SX + Period;
    end;
  finally
    Cv.RestoreState;
  end;
end;

// Draw the value portion as a rounded pill from the left edge.
procedure DrawValueBar(Cv: TPixieCanvas; const P: TPixiePosition;
  Fraction, Radius: Single; Color: TPixieWebColor);
var
  FillW: Single;
begin
  if Fraction <= 0 then Exit;
  if Fraction > 1 then Fraction := 1;
  FillW := P.Width * Fraction;
  // Keep the pill at least as wide as its rounded ends so a tiny value still
  // renders as a visible dot rather than collapsing.
  if FillW < 2 * Radius then
    FillW := 2 * Radius;
  if FillW > P.Width then
    FillW := P.Width;
  Cv.FillRoundedRect(P.X, P.Y, FillW, P.Height, Radius, Color);
end;

{ TPixieElProgress }

function TPixieElProgress.IsReplaced: Boolean;
begin
  Result := True;
end;

procedure TPixieElProgress.GetContentSize(var Sz: TPixieSize;
  MaxWidth: TPixiePixel);
begin
  Sz.Width := GaugeDefaultWidth;
  Sz.Height := GaugeDefaultHeight;
end;

procedure TPixieElProgress.Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
  Clip: PPixiePosition; Ri: Pointer);
var
  P: TPixiePosition;
  Cv: TPixieCanvas;
  Radius, MaxV, Val: Single;
  ValPresent, MaxPresent: Boolean;
begin
  inherited Draw(Hdc, X, Y, Clip, Ri);

  Cv := GetCanvas(Self);
  if Cv = nil then Exit;
  if not GaugeRect(Ri, X, Y, P) then Exit;
  if (Clip <> nil) and (not P.DoesIntersect(Clip^)) then Exit;

  Radius := P.Height / 2;
  DrawTrack(Cv, P, Radius);

  MaxV := AttrFloat(Self, 'max', 1, MaxPresent);
  if MaxV <= 0 then MaxV := 1;
  Val := AttrFloat(Self, 'value', 0, ValPresent);

  if ValPresent then
    DrawValueBar(Cv, P, Val / MaxV, Radius,
      TPixieWebColor.Create(0, 112, 201))
  else
    DrawIndeterminateStripes(Cv, P, TPixieWebColor.Create(0, 112, 201));
end;

function TPixieElProgress.CreateRenderItem(ParentRi: Pointer): Pointer;
var
  Ret: TPixieRenderInput;
begin
  Ret := TPixieRenderInput.Create(Self);
  Ret.SetParent(TPixieRenderItem(ParentRi));
  Result := Ret;
end;

function TPixieElProgress.DumpGetName: string;
begin
  Result := 'progress';
end;

{ TPixieElMeter }

function TPixieElMeter.IsReplaced: Boolean;
begin
  Result := True;
end;

procedure TPixieElMeter.GetContentSize(var Sz: TPixieSize;
  MaxWidth: TPixiePixel);
begin
  Sz.Width := GaugeDefaultWidth;
  Sz.Height := GaugeDefaultHeight;
end;

// HTML rendering spec gauge colouring: the optimum point relative to the low
// and high boundaries defines which region is optimal (green); the adjacent
// region is suboptimal (yellow) and the far one is the worst (red). When the
// optimum sits in the middle band there is no red region.
function MeterColor(Val, Low, High, Optimum: Single): TPixieWebColor;
var
  Green, Yellow, Red: TPixieWebColor;
begin
  Green := TPixieWebColor.Create(84, 179, 40);
  Yellow := TPixieWebColor.Create(250, 196, 55);
  Red := TPixieWebColor.Create(217, 83, 79);

  if Optimum < Low then
  begin
    // Lower is better.
    if Val <= Low then Result := Green
    else if Val <= High then Result := Yellow
    else Result := Red;
  end
  else if Optimum > High then
  begin
    // Higher is better.
    if Val >= High then Result := Green
    else if Val >= Low then Result := Yellow
    else Result := Red;
  end
  else
  begin
    // Middle is better.
    if (Val >= Low) and (Val <= High) then Result := Green
    else Result := Yellow;
  end;
end;

procedure TPixieElMeter.Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
  Clip: PPixiePosition; Ri: Pointer);
var
  P: TPixiePosition;
  Cv: TPixieCanvas;
  Radius, Val, MinV, MaxV, Low, High, Optimum, Frac: Single;
  Dummy: Boolean;
begin
  inherited Draw(Hdc, X, Y, Clip, Ri);

  Cv := GetCanvas(Self);
  if Cv = nil then Exit;
  if not GaugeRect(Ri, X, Y, P) then Exit;
  if (Clip <> nil) and (not P.DoesIntersect(Clip^)) then Exit;

  MinV := AttrFloat(Self, 'min', 0, Dummy);
  MaxV := AttrFloat(Self, 'max', 1, Dummy);
  if MaxV < MinV then MaxV := MinV;

  Val := AttrFloat(Self, 'value', 0, Dummy);
  if Val < MinV then Val := MinV;
  if Val > MaxV then Val := MaxV;

  // low/high default to the range ends; optimum to the midpoint. Each is
  // clamped into [min, max] and ordered (min <= low <= high <= max).
  Low := AttrFloat(Self, 'low', MinV, Dummy);
  Low := Max(MinV, Min(Low, MaxV));
  High := AttrFloat(Self, 'high', MaxV, Dummy);
  High := Max(Low, Min(High, MaxV));
  Optimum := AttrFloat(Self, 'optimum', (MinV + MaxV) / 2, Dummy);
  Optimum := Max(MinV, Min(Optimum, MaxV));

  Radius := P.Height / 2;
  DrawTrack(Cv, P, Radius);

  if MaxV > MinV then
    Frac := (Val - MinV) / (MaxV - MinV)
  else
    Frac := 0;

  DrawValueBar(Cv, P, Frac, Radius, MeterColor(Val, Low, High, Optimum));
end;

function TPixieElMeter.CreateRenderItem(ParentRi: Pointer): Pointer;
var
  Ret: TPixieRenderInput;
begin
  Ret := TPixieRenderInput.Create(Self);
  Ret.SetParent(TPixieRenderItem(ParentRi));
  Result := Ret;
end;

function TPixieElMeter.DumpGetName: string;
begin
  Result := 'meter';
end;

end.
