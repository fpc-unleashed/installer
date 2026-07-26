unit Pixie.CssLength;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Math, Generics.Collections, Pixie.Types, Pixie.Utils;

const
  // from_token options (flags)
  clfLength           = 1;
  clfPercentage       = 2;
  clfLengthPercentage = 3;
  clfNumber           = 4;
  clfInteger          = 8;
  clfPositive         = 16;

  // Sentinel predefined value for minmax() in grid template vectors.
  // When a TPixieCssLength has IsPredefined=True and Predef=CssGridMinmaxMarker,
  // the FValue field holds the min length value and FUnits the min units.
  // The NEXT entry in the vector contains the max length.
  CssGridMinmaxMarker = $7FFE;

type
  // CSS math function applied to a length: min(), max() and clamp().
  // mkNone means a plain length or a linear calc() (FCalcPercent dual form).
  TPixieMathKind = (mkNone, mkMin, mkMax, mkClamp);

  { TPixieCssLength }
  TPixieCssLength = record
  private
    FValue: Single;
    FCalcPercent: Single;
    FPredef: Integer;
    FUnits: TPixieCssUnits;
    FIsPredefined: Boolean;
    // min()/max()/clamp() storage. Each argument reduces to a linear term
    // (px part + percentage coefficient) that resolves against the percentage
    // basis at layout time, so the function as a whole stays representable as
    // a small fixed set of such terms. Term 0 reuses FValue/FCalcPercent.
    FMathKind: TPixieMathKind;
    FMathCount: Integer;
    FMathPx: array[1..2] of Single;
    FMathPct: array[1..2] of Single;
  public
    class function Create(AValue: Single; AUnits: TPixieCssUnits = cssUnitsPx): TPixieCssLength; static;
    class function CreateCalc(AAbsolutePx, APercentCoeff: Single): TPixieCssLength; static;
    class function CreateMath(AKind: TPixieMathKind;
      const APx, APct: array of Single): TPixieCssLength; static;
    class function PredefValue(AVal: Integer = 0): TPixieCssLength; static;
    function IsPredefined: Boolean;
    function IsCalc: Boolean;
    function IsMath: Boolean;
    function PercentRelative: Boolean;
    function Predef: Integer;
    function Val: Single;
    function CalcPercentCoeff: Single;
    function Units: TPixieCssUnits;
    function CalcPercent(AWidth: TPixiePixel): TPixiePixel;
    procedure SetValue(AVal: Single; AUnits: TPixieCssUnits);
    procedure SetPredef(AVal: Integer);
    function ToString: string;
  end;
  PPixieCssLength = ^TPixieCssLength;

  { TPixieCssMargins }
  TPixieCssMargins = record
    Left: TPixieCssLength;
    Right: TPixieCssLength;
    Top: TPixieCssLength;
    Bottom: TPixieCssLength;
    function ToString: string;
  end;

  { TPixieCssSize }
  TPixieCssSize = record
    Width: TPixieCssLength;
    Height: TPixieCssLength;
    class function Create(AWidth, AHeight: TPixieCssLength): TPixieCssSize; static;
  end;

  { TPixieCssOffsets }
  TPixieCssOffsets = record
    Left: TPixieCssLength;
    Top: TPixieCssLength;
    Right: TPixieCssLength;
    Bottom: TPixieCssLength;
    function ToString: string;
  end;

  TPixieLengthVector = TList<TPixieCssLength>;
  TPixieSizeVector = TList<TPixieCssSize>;

implementation

{ TPixieCssLength }

class function TPixieCssLength.Create(AValue: Single; AUnits: TPixieCssUnits): TPixieCssLength;
begin
  Result.FValue := AValue;
  Result.FCalcPercent := 0;
  Result.FPredef := 0;
  Result.FUnits := AUnits;
  Result.FIsPredefined := False;
  Result.FMathKind := mkNone;
  Result.FMathCount := 0;
end;

class function TPixieCssLength.CreateCalc(AAbsolutePx, APercentCoeff: Single): TPixieCssLength;
begin
  Result.FMathKind := mkNone;
  Result.FMathCount := 0;
  if APercentCoeff = 0 then
  begin
    Result.FValue := AAbsolutePx;
    Result.FCalcPercent := 0;
    Result.FPredef := 0;
    Result.FUnits := cssUnitsPx;
    Result.FIsPredefined := False;
  end
  else if AAbsolutePx = 0 then
  begin
    Result.FValue := APercentCoeff;
    Result.FCalcPercent := 0;
    Result.FPredef := 0;
    Result.FUnits := cssUnitsPercentage;
    Result.FIsPredefined := False;
  end
  else
  begin
    Result.FValue := AAbsolutePx;
    Result.FCalcPercent := APercentCoeff;
    Result.FPredef := 0;
    Result.FUnits := cssUnitsCalc;
    Result.FIsPredefined := False;
  end;
end;

class function TPixieCssLength.CreateMath(AKind: TPixieMathKind;
  const APx, APct: array of Single): TPixieCssLength;
var
  I: Integer;
begin
  Result.FValue := APx[0];
  Result.FCalcPercent := APct[0];
  Result.FPredef := 0;
  Result.FUnits := cssUnitsCalc;
  Result.FIsPredefined := False;
  Result.FMathKind := AKind;
  Result.FMathCount := Length(APx);
  // Zero the extra slots first so a folded 1- or 2-term min()/max() leaves the
  // unused terms clear (the copy loop below only fills the supplied ones).
  Result.FMathPx[1] := 0;  Result.FMathPct[1] := 0;
  Result.FMathPx[2] := 0;  Result.FMathPct[2] := 0;
  for I := 1 to High(APx) do
  begin
    Result.FMathPx[I] := APx[I];
    Result.FMathPct[I] := APct[I];
  end;
end;

class function TPixieCssLength.PredefValue(AVal: Integer): TPixieCssLength;
begin
  Result.FValue := 0;
  Result.FCalcPercent := 0;
  Result.FPredef := AVal;
  Result.FUnits := cssUnitsNone;
  Result.FIsPredefined := True;
  Result.FMathKind := mkNone;
  Result.FMathCount := 0;
end;

function TPixieCssLength.IsPredefined: Boolean;
begin
  Result := FIsPredefined;
end;

function TPixieCssLength.IsCalc: Boolean;
begin
  // A linear calc() only. min()/max()/clamp() reuse cssUnitsCalc storage but
  // are non-linear, so they report via IsMath instead (never as plain calc).
  Result := (FUnits = cssUnitsCalc) and (FMathKind = mkNone);
end;

function TPixieCssLength.IsMath: Boolean;
begin
  Result := FMathKind <> mkNone;
end;

function TPixieCssLength.PercentRelative: Boolean;
begin
  // True when the resolved value depends on the percentage basis: a raw
  // percentage, a calc() with a percentage coefficient, or any math() term
  // carrying a percentage.
  if FIsPredefined then
    Result := False
  else if FMathKind <> mkNone then
    Result := (FCalcPercent <> 0) or (FMathPct[1] <> 0) or (FMathPct[2] <> 0)
  else
    Result := (FUnits = cssUnitsPercentage) or
              ((FUnits = cssUnitsCalc) and (FCalcPercent <> 0));
end;

function TPixieCssLength.Predef: Integer;
begin
  if FIsPredefined then
    Result := FPredef
  else
    Result := 0;
end;

function TPixieCssLength.Val: Single;
begin
  if not FIsPredefined then
    Result := FValue
  else
    Result := 0;
end;

function TPixieCssLength.CalcPercentCoeff: Single;
begin
  Result := FCalcPercent;
end;

function TPixieCssLength.Units: TPixieCssUnits;
begin
  Result := FUnits;
end;

function TPixieCssLength.CalcPercent(AWidth: TPixiePixel): TPixiePixel;
var
  T0, T1, T2: TPixiePixel;
begin
  if IsPredefined then
    Exit(0);

  if FMathKind <> mkNone then
  begin
    // Resolve each stored linear term against the basis, then apply the
    // function over all of them (min()/max() may carry up to three terms:
    // a folded-px, a folded-pct and one mixed term).
    T0 := AWidth * FCalcPercent / 100 + FValue;
    T1 := AWidth * FMathPct[1] / 100 + FMathPx[1];
    T2 := AWidth * FMathPct[2] / 100 + FMathPx[2];
    case FMathKind of
      mkMin:
        begin
          Result := T0;
          if FMathCount >= 2 then Result := Min(Result, T1);
          if FMathCount >= 3 then Result := Min(Result, T2);
        end;
      mkMax:
        begin
          Result := T0;
          if FMathCount >= 2 then Result := Max(Result, T1);
          if FMathCount >= 3 then Result := Max(Result, T2);
        end;
      mkClamp:
        // clamp(min, val, max) = max(min, min(val, max))
        Result := Max(T0, Min(T1, T2));
    else
      Result := T0;
    end;
    Exit;
  end;

  if FUnits = cssUnitsCalc then
    Result := AWidth * FCalcPercent / 100 + FValue
  else if FUnits = cssUnitsPercentage then
    Result := AWidth * FValue / 100
  else
    Result := Val;
end;

procedure TPixieCssLength.SetValue(AVal: Single; AUnits: TPixieCssUnits);
begin
  FValue := AVal;
  FCalcPercent := 0;
  FIsPredefined := False;
  FUnits := AUnits;
  FMathKind := mkNone;
  FMathCount := 0;
end;

procedure TPixieCssLength.SetPredef(AVal: Integer);
begin
  FPredef := AVal;
  FCalcPercent := 0;
  FIsPredefined := True;
  FMathKind := mkNone;
  FMathCount := 0;
end;

function TPixieCssLength.ToString: string;
const
  MathNames: array[TPixieMathKind] of string = ('', 'min', 'max', 'clamp');
begin
  if FIsPredefined then
    Result := 'predef(' + IntToStr(FPredef) + ')'
  else if FMathKind <> mkNone then
    Result := MathNames[FMathKind] + '(' + IntToStr(FMathCount) + ' terms)'
  else if FUnits = cssUnitsCalc then
    Result := 'calc(' + FloatToStr(FCalcPercent) + '% + ' + FloatToStr(FValue) + 'px)'
  else
    Result := FloatToStr(FValue) + '(' + PixieIndexValue(Ord(FUnits), CssUnitsStrings) + ')';
end;

{ TPixieCssMargins }

function TPixieCssMargins.ToString: string;
begin
  Result := 'left: ' + Left.ToString +
            ', right: ' + Right.ToString +
            ', top: ' + Top.ToString +
            ', bottom: ' + Bottom.ToString;
end;

{ TPixieCssSize }

class function TPixieCssSize.Create(AWidth, AHeight: TPixieCssLength): TPixieCssSize;
begin
  Result.Width := AWidth;
  Result.Height := AHeight;
end;

{ TPixieCssOffsets }

function TPixieCssOffsets.ToString: string;
begin
  Result := 'left: ' + Left.ToString +
            ', top: ' + Top.ToString +
            ', right: ' + Right.ToString +
            ', bottom: ' + Bottom.ToString;
end;

end.
