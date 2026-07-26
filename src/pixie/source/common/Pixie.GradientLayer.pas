unit Pixie.GradientLayer;

// Computed gradient layer types (colour stops, linear/radial/conic geometry)
// shared by the canvas interface and all rendering backends.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Generics.Collections,
  Pixie.Types, Pixie.WebColor;

type
  TPixieColorSpace = (
    csNone,
    // rectangular
    csSrgb, csSrgbLinear, csDisplayP3, csA98Rgb, csProphotoRgb, csRec2020,
    csLab, csOklab, csXyz, csXyzD50, csXyzD65,
    // polar (csHsl marks start of polar spaces)
    csHsl, csHwb, csLch, csOklch
  );

  TPixieHueInterpolation = (hiNone, hiShorter, hiLonger,
    hiIncreasing, hiDecreasing);

  { TPixieColorPoint - normalized color stop for computed gradient layers }
  TPixieColorPoint = record
    Offset: Single;
    Color: TPixieWebColor;
    Hint: Single;
    HasHint: Boolean;
    class function Create(AOffset: Single;
      const AColor: TPixieWebColor): TPixieColorPoint; static;
  end;

  TPixieColorPointList = TList<TPixieColorPoint>;

  { TPixieGradientTransform — brush-to-user-space affine transform for
    objectBoundingBox gradients (maps normalised 0-1 coords to user space) }
  TPixieGradientTransform = record
    M11, M12, M21, M22, DX, DY: Single;
  end;

  { TPixieGradientBase - base for computed gradient layers }
  TPixieGradientBase = class
  public
    ColorPoints: TPixieColorPointList;
    ColorSpace: TPixieColorSpace;
    HueInterpolation: TPixieHueInterpolation;
    HasBrushTransform: Boolean;
    BrushTransform: TPixieGradientTransform;

    constructor Create;
    destructor Destroy; override;

    procedure ColorPointsTransparentFix;
  end;

  { TPixieLinearGradientLayer }
  TPixieLinearGradientLayer = class(TPixieGradientBase)
  public
    StartPt: TPixiePointF;
    EndPt: TPixiePointF;
  end;

  { TPixieRadialGradientLayer }
  TPixieRadialGradientLayer = class(TPixieGradientBase)
  public
    Position: TPixiePointF;
    Radius: TPixiePointF;
  end;

  { TPixieConicGradientLayer }
  TPixieConicGradientLayer = class(TPixieGradientBase)
  public
    Position: TPixiePointF;
    Angle: Single;
    Radius: Single;
  end;

implementation

{ TPixieColorPoint }

class function TPixieColorPoint.Create(AOffset: Single;
  const AColor: TPixieWebColor): TPixieColorPoint;
begin
  Result.Offset := AOffset;
  Result.Color := AColor;
  Result.Hint := 0;
  Result.HasHint := False;
end;

{ TPixieGradientBase }

constructor TPixieGradientBase.Create;
begin
  inherited Create;
  ColorPoints := TPixieColorPointList.Create;
  ColorSpace := csNone;
  HueInterpolation := hiNone;
end;

destructor TPixieGradientBase.Destroy;
begin
  ColorPoints.Free;
  inherited;
end;

procedure TPixieGradientBase.ColorPointsTransparentFix;
var
  I, Cnt: Integer;
  Cpt: TPixieColorPoint;
begin
  I := 0;
  while I < ColorPoints.Count do
  begin
    Cnt := ColorPoints.Count;
    if ColorPoints[I].Color.Alpha = 0 then
    begin
      if I = 0 then
      begin
        if I + 1 < Cnt then
        begin
          Cpt := ColorPoints[I];
          Cpt.Color := ColorPoints[I + 1].Color;
          Cpt.Color.Alpha := 0;
          ColorPoints[I] := Cpt;
        end;
      end
      else if I + 1 = Cnt then
      begin
        Cpt := ColorPoints[I];
        Cpt.Color := ColorPoints[I - 1].Color;
        Cpt.Color.Alpha := 0;
        ColorPoints[I] := Cpt;
      end
      else
      begin
        // Split: insert copy with previous color's RGB before current
        Cpt.Color := ColorPoints[I - 1].Color;
        Cpt.Color.Alpha := 0;
        Cpt.Offset := ColorPoints[I].Offset;
        Cpt.Hint := 0;
        Cpt.HasHint := False;
        ColorPoints.Insert(I, Cpt);
        // Fix current (now at I+1) to use next color's RGB
        Cpt := ColorPoints[I + 1];
        Cpt.Color := ColorPoints[I + 2].Color;
        Cpt.Color.Alpha := 0;
        ColorPoints[I + 1] := Cpt;
        Inc(I); // skip the newly inserted one
      end;
    end;
    Inc(I);
  end;
end;

end.
