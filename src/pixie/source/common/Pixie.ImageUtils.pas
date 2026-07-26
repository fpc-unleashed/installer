unit Pixie.ImageUtils;

// Convert TFPMemoryImage to premultiplied BGRA pixel buffer.
// Used by both NativeContainer (HTML image loading) and SvgRenderer.Canvas
// (SVG <image> element decoding) on FPC backends.

{$IFDEF FPC}
{$MODE DELPHI}

interface

uses
  FPImage;

procedure ConvertFPImageToBGRA(Img: TFPCustomImage;
  out Pixels: PByte; out W, H, Pitch: Integer);

implementation

procedure ConvertFPImageToBGRA(Img: TFPCustomImage;
  out Pixels: PByte; out W, H, Pitch: Integer);
var
  X, Y: Integer;
  Colour: TFPColor;
  Dst: PByte;
  A, R, G, B: Byte;
begin
  W := Img.Width;
  H := Img.Height;
  Pixels := nil;
  if (W <= 0) or (H <= 0) then Exit;

  Pitch := W * 4;
  GetMem(Pixels, Pitch * H);

  for Y := 0 to H - 1 do
  begin
    Dst := Pixels + Y * Pitch;
    for X := 0 to W - 1 do
    begin
      Colour := Img.Colors[X, Y];
      A := Colour.Alpha shr 8;
      if A = 0 then
      begin
        Dst^ := 0; Inc(Dst);
        Dst^ := 0; Inc(Dst);
        Dst^ := 0; Inc(Dst);
        Dst^ := 0; Inc(Dst);
      end
      else if A = 255 then
      begin
        Dst^ := Colour.Blue shr 8; Inc(Dst);
        Dst^ := Colour.Green shr 8; Inc(Dst);
        Dst^ := Colour.Red shr 8; Inc(Dst);
        Dst^ := A; Inc(Dst);
      end
      else
      begin
        R := Colour.Red shr 8;
        G := Colour.Green shr 8;
        B := Colour.Blue shr 8;
        Dst^ := B * A div 255; Inc(Dst);
        Dst^ := G * A div 255; Inc(Dst);
        Dst^ := R * A div 255; Inc(Dst);
        Dst^ := A; Inc(Dst);
      end;
    end;
  end;
end;

{$ELSE}

interface

implementation

{$ENDIF}

end.
