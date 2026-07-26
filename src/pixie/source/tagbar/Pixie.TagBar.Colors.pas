unit Pixie.TagBar.Colors;

// Colour palette and state derivation for tag pills.
// Pure math — no LCL dependency.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Math, Pixie.Types, Pixie.WebColor;

type
  TPixieTagPaletteArray = array of TPixieWebColor;

{ HSL conversion }
procedure PixieTagRgbToHsl(R, G, B: Byte; out H, S, L: Single);
function PixieTagHslToColor(H, S, L: Single; A: Byte = 255): TPixieWebColor;

{ Colour manipulation }
function PixieTagBlend(const A, B: TPixieWebColor; T: Single): TPixieWebColor;
function PixieTagWithAlpha(const C: TPixieWebColor; A: Byte): TPixieWebColor;
function PixieTagLuminance(const C: TPixieWebColor): Single;

{ State derivation — all work from the tag's base colour }
function PixieTagRestFill(const Base: TPixieWebColor): TPixieWebColor;
function PixieTagHoverFill(const Base: TPixieWebColor): TPixieWebColor;
function PixieTagPressFill(const Base: TPixieWebColor): TPixieWebColor;
function PixieTagCheckedFill(const Base: TPixieWebColor): TPixieWebColor;
function PixieTagInactiveFill(const Base: TPixieWebColor): TPixieWebColor;
function PixieTagTextColor(const Base: TPixieWebColor;
  Checked: Boolean): TPixieWebColor;
function PixieTagBorderColor(const Base: TPixieWebColor): TPixieWebColor;
function PixieTagOutlineColor(const Base: TPixieWebColor): TPixieWebColor;
function PixieTagMutedTextColor(const Bg: TPixieWebColor): TPixieWebColor;

{ Scrollbar colours — semi-transparent grey, dark on light backgrounds and
  light on dark backgrounds }
function PixieScrollbarThumbColor(const Bg: TPixieWebColor): TPixieWebColor;
function PixieScrollbarTrackColor(const Bg: TPixieWebColor): TPixieWebColor;

{ Default palette — 8 well-separated hues }
function PixieTagDefaultPalette: TPixieTagPaletteArray;

implementation

// ---------------------------------------------------------------------------
// Delegating to Pixie.WebColor general-purpose functions
// ---------------------------------------------------------------------------

procedure PixieTagRgbToHsl(R, G, B: Byte; out H, S, L: Single);
begin
  PixieRgbToHsl(R, G, B, H, S, L);
end;

function PixieTagHslToColor(H, S, L: Single; A: Byte): TPixieWebColor;
var
  Rf, Gf, Bf: Single;
begin
  PixieHslToRgb(H, S, L, Rf, Gf, Bf);
  Result := TPixieWebColor.Create(
    Byte(EnsureRange(Round(Rf * 255), 0, 255)),
    Byte(EnsureRange(Round(Gf * 255), 0, 255)),
    Byte(EnsureRange(Round(Bf * 255), 0, 255)),
    A);
end;

function PixieTagBlend(const A, B: TPixieWebColor; T: Single): TPixieWebColor;
begin
  Result := PixieColorBlend(A, B, T);
end;

function PixieTagWithAlpha(const C: TPixieWebColor; A: Byte): TPixieWebColor;
begin
  Result := PixieColorWithAlpha(C, A);
end;

function PixieTagLuminance(const C: TPixieWebColor): Single;
begin
  Result := PixieColorLuminance(C);
end;

// ---------------------------------------------------------------------------
// State derivation
// ---------------------------------------------------------------------------

function PixieTagRestFill(const Base: TPixieWebColor): TPixieWebColor;
var
  H, S, L: Single;
begin
  PixieTagRgbToHsl(Base.Red, Base.Green, Base.Blue, H, S, L);
  S := Min(S, 45);
  L := 92;
  Result := PixieTagHslToColor(H, S, L);
end;

function PixieTagHoverFill(const Base: TPixieWebColor): TPixieWebColor;
var
  H, S, L: Single;
begin
  PixieTagRgbToHsl(Base.Red, Base.Green, Base.Blue, H, S, L);
  S := Min(S, 55);
  L := 85;
  Result := PixieTagHslToColor(H, S, L);
end;

function PixieTagPressFill(const Base: TPixieWebColor): TPixieWebColor;
var
  H, S, L: Single;
begin
  PixieTagRgbToHsl(Base.Red, Base.Green, Base.Blue, H, S, L);
  S := Min(S, 60);
  L := 75;
  Result := PixieTagHslToColor(H, S, L);
end;

function PixieTagCheckedFill(const Base: TPixieWebColor): TPixieWebColor;
begin
  Result := Base;
end;

function PixieTagInactiveFill(const Base: TPixieWebColor): TPixieWebColor;
var
  H, S, L: Single;
begin
  PixieTagRgbToHsl(Base.Red, Base.Green, Base.Blue, H, S, L);
  S := 10;
  L := 90;
  Result := PixieTagHslToColor(H, S, L);
end;

function PixieTagTextColor(const Base: TPixieWebColor;
  Checked: Boolean): TPixieWebColor;
var
  H, S, L: Single;
begin
  if Checked then
  begin
    if PixieTagLuminance(Base) > 0.5 then
      Result := TPixieWebColor.Create(30, 30, 30)
    else
      Result := TPixieWebColor.White;
  end
  else
  begin
    PixieTagRgbToHsl(Base.Red, Base.Green, Base.Blue, H, S, L);
    S := Min(S, 70);
    L := 25;
    Result := PixieTagHslToColor(H, S, L);
  end;
end;

function PixieTagBorderColor(const Base: TPixieWebColor): TPixieWebColor;
begin
  Result := PixieTagWithAlpha(Base, 80);
end;

// Stronger border for outlined unchecked pills, where the border is the
// primary visual cue rather than a soft frame around a tinted fill.
function PixieTagOutlineColor(const Base: TPixieWebColor): TPixieWebColor;
begin
  Result := PixieTagWithAlpha(Base, 200);
end;

function PixieTagMutedTextColor(const Bg: TPixieWebColor): TPixieWebColor;
begin
  Result := PixieTagBlend(TPixieWebColor.Black, Bg, 0.5);
end;

function PixieScrollbarThumbColor(const Bg: TPixieWebColor): TPixieWebColor;
begin
  if PixieTagLuminance(Bg) > 0.5 then
    Result := TPixieWebColor.Create($80, $80, $80, $A0)
  else
    Result := TPixieWebColor.Create($D0, $D0, $D0, $A0);
end;

function PixieScrollbarTrackColor(const Bg: TPixieWebColor): TPixieWebColor;
begin
  if PixieTagLuminance(Bg) > 0.5 then
    Result := TPixieWebColor.Create($80, $80, $80, $18)
  else
    Result := TPixieWebColor.Create($D0, $D0, $D0, $18);
end;

// ---------------------------------------------------------------------------
// Default palette
// ---------------------------------------------------------------------------

function PixieTagDefaultPalette: TPixieTagPaletteArray;
begin
  Result := nil;
  SetLength(Result, 8);
  Result[0] := TPixieWebColor.Create($21, $96, $F3); // Blue
  Result[1] := TPixieWebColor.Create($4C, $AF, $50); // Green
  Result[2] := TPixieWebColor.Create($FF, $98, $00); // Orange
  Result[3] := TPixieWebColor.Create($9C, $27, $B0); // Purple
  Result[4] := TPixieWebColor.Create($00, $96, $88); // Teal
  Result[5] := TPixieWebColor.Create($F4, $43, $36); // Red
  Result[6] := TPixieWebColor.Create($79, $55, $48); // Brown
  Result[7] := TPixieWebColor.Create($60, $7D, $8B); // Blue-grey
end;

end.
