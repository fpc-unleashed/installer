unit Pixie.FontDescription;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Pixie.Types, Pixie.CssLength, Pixie.WebColor;

type
  { TPixieFontDescription }
  TPixieFontDescription = record
    Family: string;
    Size: TPixiePixel;
    Style: TPixieFontStyle;
    Variant: TPixieFontVariant;
    Weight: Integer;
    DecorationLine: Integer;
    DecorationThickness: TPixieCssLength;
    DecorationStyle: TPixieTextDecorationStyle;
    DecorationColor: TPixieWebColor;
    EmphasisStyle: string;
    EmphasisColor: TPixieWebColor;
    EmphasisPosition: Integer;
    procedure Init;
    function Hash: string;
  end;

// Splits a CSS font-family list (e.g. "Consolas, monospace") into
// individual names, maps generic families to platform fonts, and
// calls CheckFont for each until one succeeds. Returns the resolved
// name, or the platform default if nothing matched.
type
  TPixieFontCheckFunc = function(const Name: string): Boolean;

function PixieResolveFontFamily(const CssFamily: string;
  CheckFont: TPixieFontCheckFunc): string;

// Returns True if the first name in a CSS font-family list is the generic
// "monospace" keyword. Used by the CSS cascade to replicate Chrome's quirk
// where keyword font sizes resolve against a 13px base in a monospace
// context.
function PixieFontFamilyIsMonospace(const CssFamily: string): Boolean;

const
  PixieSmallCapsScale = 0.8;

implementation

function MapGenericFamily(const Name: string): string;
var
  Lower: string;
begin
  Lower := LowerCase(Name);
  {$IFDEF MSWINDOWS}
  if Lower = 'monospace' then Exit('Consolas');
  if Lower = 'sans-serif' then Exit('Segoe UI');
  if Lower = 'serif' then Exit('Times New Roman');
  if Lower = 'cursive' then Exit('Comic Sans MS');
  if Lower = 'fantasy' then Exit('Impact');
  if Lower = 'system-ui' then Exit('Segoe UI');
  {$ENDIF}
  {$IFDEF DARWIN}
  if Lower = 'monospace' then Exit('Menlo');
  if Lower = 'sans-serif' then Exit('Helvetica');
  if Lower = 'serif' then Exit('Times');
  if Lower = 'cursive' then Exit('Apple Chancery');
  if Lower = 'fantasy' then Exit('Papyrus');
  if Lower = 'system-ui' then Exit('.AppleSystemUIFont');
  {$ENDIF}
  {$IF DEFINED(LINUX)}
  if Lower = 'monospace' then Exit('DejaVu Sans Mono');
  if Lower = 'sans-serif' then Exit('DejaVu Sans');
  if Lower = 'serif' then Exit('DejaVu Serif');
  if Lower = 'cursive' then Exit('DejaVu Sans');
  if Lower = 'fantasy' then Exit('DejaVu Sans');
  if Lower = 'system-ui' then Exit('DejaVu Sans');
  {$ENDIF}
  Result := Name;
end;

// Maps legacy bitmap font names to their TrueType equivalents on
// Windows. DirectWrite does not support bitmap .fon fonts, so names
// like "Courier" and "MS Sans Serif" are invisible to it. Both
// Chromium (AlternateFamilyName) and Firefox (sDirectWriteSubs)
// carry the same mappings. macOS and Linux need no aliases: CoreText
// finds the real fonts, and fontconfig handles substitution via
// 30-metric-aliases.conf.
function MapLegacyAlias(const Name: string): string;
{$IFDEF MSWINDOWS}
var
  Lower: string;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  Lower := LowerCase(Name);
  if Lower = 'courier' then Exit('Courier New');
  if Lower = 'helvetica' then Exit('Arial');
  if Lower = 'times' then Exit('Times New Roman');
  if Lower = 'ms sans serif' then Exit('Microsoft Sans Serif');
  if Lower = 'ms serif' then Exit('Times New Roman');
  {$ENDIF}
  Result := '';
end;

function PixieResolveFontFamily(const CssFamily: string;
  CheckFont: TPixieFontCheckFunc): string;
var
  I, Start, Len, Count: Integer;
  Part, Mapped: string;
  Parts: array of string;
begin
  // Split on commas
  Len := Length(CssFamily);
  Count := 1;
  for I := 1 to Len do
    if CssFamily[I] = ',' then Inc(Count);
  SetLength(Parts, Count);
  Count := 0;
  Start := 1;
  for I := 1 to Len + 1 do
    if (I > Len) or (CssFamily[I] = ',') then
    begin
      Part := Trim(Copy(CssFamily, Start, I - Start));
      // Strip quotes
      if (Length(Part) >= 2) and
         ((Part[1] = '''') or (Part[1] = '"')) then
        Part := Copy(Part, 2, Length(Part) - 2);
      Parts[Count] := Part;
      Inc(Count);
      Start := I + 1;
    end;

  // Try each family
  for I := 0 to Count - 1 do
  begin
    Mapped := MapGenericFamily(Parts[I]);
    if (Mapped <> '') and CheckFont(Mapped) then
      Exit(Mapped);
    // Try legacy alias (e.g. Courier -> Courier New)
    if Mapped <> '' then
    begin
      Part := MapLegacyAlias(Mapped);
      if (Part <> '') and CheckFont(Part) then
        Exit(Part);
    end;
  end;

  // Platform default fallback
  {$IFDEF MSWINDOWS}
  Result := 'Segoe UI';
  if not CheckFont(Result) then Result := 'Arial';
  {$ENDIF}
  {$IFDEF DARWIN}
  Result := 'Helvetica';
  {$ENDIF}
  {$IF DEFINED(LINUX)}
  Result := 'DejaVu Sans';
  {$ENDIF}
end;

function PixieFontFamilyIsMonospace(const CssFamily: string): Boolean;
var
  I, J, Len: Integer;
begin
  Len := Length(CssFamily);
  I := 1;
  while (I <= Len) and ((CssFamily[I] = ' ') or (CssFamily[I] = #9) or
                        (CssFamily[I] = '"') or (CssFamily[I] = '''')) do
    Inc(I);
  J := I;
  while (J <= Len) and (CssFamily[J] <> ',') and (CssFamily[J] <> '"') and
        (CssFamily[J] <> '''') do
    Inc(J);
  Result := SameText(Trim(Copy(CssFamily, I, J - I)), 'monospace');
end;

{ TPixieFontDescription }

procedure TPixieFontDescription.Init;
begin
  Family := '';
  Size := 0;
  Style := fstNormal;
  Variant := fvNormal;
  Weight := 400;
  DecorationLine := TextDecorationLineNone;
  DecorationStyle := tdsSOlid;
  DecorationColor := TPixieWebColor.CurrentColor;
  EmphasisStyle := '';
  EmphasisColor := TPixieWebColor.CurrentColor;
  EmphasisPosition := TextEmphasisPositionOver;
end;

function TPixieFontDescription.Hash: string;
begin
  // Decoration is not part of font identity — drawn at element level
  Result := Family +
    ':sz=' + FloatToStr(Size) +
    ':st=' + IntToStr(Ord(Style)) +
    ':va=' + IntToStr(Ord(Variant)) +
    ':w=' + IntToStr(Weight) +
    ':ephs=' + EmphasisStyle +
    ':ephc=' + EmphasisColor.ToString +
    ':ephp=' + IntToStr(EmphasisPosition);
end;

end.
