unit Pixie.WebColor;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Math, Generics.Collections, Pixie.Types, Pixie.Utils;

type
  { TPixieWebColor }
  TPixieWebColor = record
    Red: Byte;
    Green: Byte;
    Blue: Byte;
    Alpha: Byte;
    IsCurrentColor: Boolean;
    class function Create(R, G, B: Byte; A: Byte = 255): TPixieWebColor; static;
    class function CreateCurrentColor: TPixieWebColor; static;
    class function Transparent: TPixieWebColor; static;
    class function Black: TPixieWebColor; static;
    class function White: TPixieWebColor; static;
    class function CurrentColor: TPixieWebColor; static;
    class operator Equal(const A, B: TPixieWebColor): Boolean;
    class operator NotEqual(const A, B: TPixieWebColor): Boolean;
    function ToString: string;
  end;
  PPixieWebColor = ^TPixieWebColor;
  TPixieColorMap = TDictionary<string, TPixieWebColor>;

function PixieParseHashColorString(const S: string; out Color: TPixieWebColor): Boolean;
function PixieParseNamedColor(const Name: string; out Color: TPixieWebColor): Boolean;
function PixieParseColorString(const S: string; out Color: TPixieWebColor): Boolean;
procedure PixieHslToRgb(Hue, Sat, Light: Single; out R, G, B: Single);
procedure PixieRgbToHsl(R, G, B: Byte; out H, S, L: Single);
function PixieColorBlend(const A, B: TPixieWebColor; T: Single): TPixieWebColor;
function PixieColorLuminance(const C: TPixieWebColor): Single;
function PixieColorWithAlpha(const C: TPixieWebColor; A: Byte): TPixieWebColor;

implementation

type
  TDefColor = record
    Name: string;
    Hex: string;
  end;

var
  ColorMap: TPixieColorMap;

const
  DefColors: array[0..148] of TDefColor = (
    (Name: 'transparent'; Hex: '00000000'),
    (Name: 'aliceblue'; Hex: 'F0F8FF'),
    (Name: 'antiquewhite'; Hex: 'FAEBD7'),
    (Name: 'aqua'; Hex: '00FFFF'),
    (Name: 'aquamarine'; Hex: '7FFFD4'),
    (Name: 'azure'; Hex: 'F0FFFF'),
    (Name: 'beige'; Hex: 'F5F5DC'),
    (Name: 'bisque'; Hex: 'FFE4C4'),
    (Name: 'black'; Hex: '000000'),
    (Name: 'blanchedalmond'; Hex: 'FFEBCD'),
    (Name: 'blue'; Hex: '0000FF'),
    (Name: 'blueviolet'; Hex: '8A2BE2'),
    (Name: 'brown'; Hex: 'A52A2A'),
    (Name: 'burlywood'; Hex: 'DEB887'),
    (Name: 'cadetblue'; Hex: '5F9EA0'),
    (Name: 'chartreuse'; Hex: '7FFF00'),
    (Name: 'chocolate'; Hex: 'D2691E'),
    (Name: 'coral'; Hex: 'FF7F50'),
    (Name: 'cornflowerblue'; Hex: '6495ED'),
    (Name: 'cornsilk'; Hex: 'FFF8DC'),
    (Name: 'crimson'; Hex: 'DC143C'),
    (Name: 'cyan'; Hex: '00FFFF'),
    (Name: 'darkblue'; Hex: '00008B'),
    (Name: 'darkcyan'; Hex: '008B8B'),
    (Name: 'darkgoldenrod'; Hex: 'B8860B'),
    (Name: 'darkgray'; Hex: 'A9A9A9'),
    (Name: 'darkgrey'; Hex: 'A9A9A9'),
    (Name: 'darkgreen'; Hex: '006400'),
    (Name: 'darkkhaki'; Hex: 'BDB76B'),
    (Name: 'darkmagenta'; Hex: '8B008B'),
    (Name: 'darkolivegreen'; Hex: '556B2F'),
    (Name: 'darkorange'; Hex: 'FF8C00'),
    (Name: 'darkorchid'; Hex: '9932CC'),
    (Name: 'darkred'; Hex: '8B0000'),
    (Name: 'darksalmon'; Hex: 'E9967A'),
    (Name: 'darkseagreen'; Hex: '8FBC8F'),
    (Name: 'darkslateblue'; Hex: '483D8B'),
    (Name: 'darkslategray'; Hex: '2F4F4F'),
    (Name: 'darkslategrey'; Hex: '2F4F4F'),
    (Name: 'darkturquoise'; Hex: '00CED1'),
    (Name: 'darkviolet'; Hex: '9400D3'),
    (Name: 'deeppink'; Hex: 'FF1493'),
    (Name: 'deepskyblue'; Hex: '00BFFF'),
    (Name: 'dimgray'; Hex: '696969'),
    (Name: 'dimgrey'; Hex: '696969'),
    (Name: 'dodgerblue'; Hex: '1E90FF'),
    (Name: 'firebrick'; Hex: 'B22222'),
    (Name: 'floralwhite'; Hex: 'FFFAF0'),
    (Name: 'forestgreen'; Hex: '228B22'),
    (Name: 'fuchsia'; Hex: 'FF00FF'),
    (Name: 'gainsboro'; Hex: 'DCDCDC'),
    (Name: 'ghostwhite'; Hex: 'F8F8FF'),
    (Name: 'gold'; Hex: 'FFD700'),
    (Name: 'goldenrod'; Hex: 'DAA520'),
    (Name: 'gray'; Hex: '808080'),
    (Name: 'grey'; Hex: '808080'),
    (Name: 'green'; Hex: '008000'),
    (Name: 'greenyellow'; Hex: 'ADFF2F'),
    (Name: 'honeydew'; Hex: 'F0FFF0'),
    (Name: 'hotpink'; Hex: 'FF69B4'),
    (Name: 'indianred'; Hex: 'CD5C5C'),
    (Name: 'indigo'; Hex: '4B0082'),
    (Name: 'ivory'; Hex: 'FFFFF0'),
    (Name: 'khaki'; Hex: 'F0E68C'),
    (Name: 'lavender'; Hex: 'E6E6FA'),
    (Name: 'lavenderblush'; Hex: 'FFF0F5'),
    (Name: 'lawngreen'; Hex: '7CFC00'),
    (Name: 'lemonchiffon'; Hex: 'FFFACD'),
    (Name: 'lightblue'; Hex: 'ADD8E6'),
    (Name: 'lightcoral'; Hex: 'F08080'),
    (Name: 'lightcyan'; Hex: 'E0FFFF'),
    (Name: 'lightgoldenrodyellow'; Hex: 'FAFAD2'),
    (Name: 'lightgray'; Hex: 'D3D3D3'),
    (Name: 'lightgrey'; Hex: 'D3D3D3'),
    (Name: 'lightgreen'; Hex: '90EE90'),
    (Name: 'lightpink'; Hex: 'FFB6C1'),
    (Name: 'lightsalmon'; Hex: 'FFA07A'),
    (Name: 'lightseagreen'; Hex: '20B2AA'),
    (Name: 'lightskyblue'; Hex: '87CEFA'),
    (Name: 'lightslategray'; Hex: '778899'),
    (Name: 'lightslategrey'; Hex: '778899'),
    (Name: 'lightsteelblue'; Hex: 'B0C4DE'),
    (Name: 'lightyellow'; Hex: 'FFFFE0'),
    (Name: 'lime'; Hex: '00FF00'),
    (Name: 'limegreen'; Hex: '32CD32'),
    (Name: 'linen'; Hex: 'FAF0E6'),
    (Name: 'magenta'; Hex: 'FF00FF'),
    (Name: 'maroon'; Hex: '800000'),
    (Name: 'mediumaquamarine'; Hex: '66CDAA'),
    (Name: 'mediumblue'; Hex: '0000CD'),
    (Name: 'mediumorchid'; Hex: 'BA55D3'),
    (Name: 'mediumpurple'; Hex: '9370D8'),
    (Name: 'mediumseagreen'; Hex: '3CB371'),
    (Name: 'mediumslateblue'; Hex: '7B68EE'),
    (Name: 'mediumspringgreen'; Hex: '00FA9A'),
    (Name: 'mediumturquoise'; Hex: '48D1CC'),
    (Name: 'mediumvioletred'; Hex: 'C71585'),
    (Name: 'midnightblue'; Hex: '191970'),
    (Name: 'mintcream'; Hex: 'F5FFFA'),
    (Name: 'mistyrose'; Hex: 'FFE4E1'),
    (Name: 'moccasin'; Hex: 'FFE4B5'),
    (Name: 'navajowhite'; Hex: 'FFDEAD'),
    (Name: 'navy'; Hex: '000080'),
    (Name: 'oldlace'; Hex: 'FDF5E6'),
    (Name: 'olive'; Hex: '808000'),
    (Name: 'olivedrab'; Hex: '6B8E23'),
    (Name: 'orange'; Hex: 'FFA500'),
    (Name: 'orangered'; Hex: 'FF4500'),
    (Name: 'orchid'; Hex: 'DA70D6'),
    (Name: 'palegoldenrod'; Hex: 'EEE8AA'),
    (Name: 'palegreen'; Hex: '98FB98'),
    (Name: 'paleturquoise'; Hex: 'AFEEEE'),
    (Name: 'palevioletred'; Hex: 'D87093'),
    (Name: 'papayawhip'; Hex: 'FFEFD5'),
    (Name: 'peachpuff'; Hex: 'FFDAB9'),
    (Name: 'peru'; Hex: 'CD853F'),
    (Name: 'pink'; Hex: 'FFC0CB'),
    (Name: 'plum'; Hex: 'DDA0DD'),
    (Name: 'powderblue'; Hex: 'B0E0E6'),
    (Name: 'purple'; Hex: '800080'),
    (Name: 'rebeccapurple'; Hex: '663399'),
    (Name: 'red'; Hex: 'FF0000'),
    (Name: 'rosybrown'; Hex: 'BC8F8F'),
    (Name: 'royalblue'; Hex: '4169E1'),
    (Name: 'saddlebrown'; Hex: '8B4513'),
    (Name: 'salmon'; Hex: 'FA8072'),
    (Name: 'sandybrown'; Hex: 'F4A460'),
    (Name: 'seagreen'; Hex: '2E8B57'),
    (Name: 'seashell'; Hex: 'FFF5EE'),
    (Name: 'sienna'; Hex: 'A0522D'),
    (Name: 'silver'; Hex: 'C0C0C0'),
    (Name: 'skyblue'; Hex: '87CEEB'),
    (Name: 'slateblue'; Hex: '6A5ACD'),
    (Name: 'slategray'; Hex: '708090'),
    (Name: 'slategrey'; Hex: '708090'),
    (Name: 'snow'; Hex: 'FFFAFA'),
    (Name: 'springgreen'; Hex: '00FF7F'),
    (Name: 'steelblue'; Hex: '4682B4'),
    (Name: 'tan'; Hex: 'D2B48C'),
    (Name: 'teal'; Hex: '008080'),
    (Name: 'thistle'; Hex: 'D8BFD8'),
    (Name: 'tomato'; Hex: 'FF6347'),
    (Name: 'turquoise'; Hex: '40E0D0'),
    (Name: 'violet'; Hex: 'EE82EE'),
    (Name: 'wheat'; Hex: 'F5DEB3'),
    (Name: 'white'; Hex: 'FFFFFF'),
    (Name: 'whitesmoke'; Hex: 'F5F5F5'),
    (Name: 'yellow'; Hex: 'FFFF00'),
    (Name: 'yellowgreen'; Hex: '9ACD32')
  );

function HexToByte(C1, C2: Integer): Byte; inline;
begin
  Result := Byte(PixieDigitValue(C1) * 16 + PixieDigitValue(C2));
end;

function ParseHexColor(const Hex: string): TPixieWebColor;
begin
  Result := TPixieWebColor.Create(
    HexToByte(Ord(Hex[1]), Ord(Hex[2])),
    HexToByte(Ord(Hex[3]), Ord(Hex[4])),
    HexToByte(Ord(Hex[5]), Ord(Hex[6])));
  if Length(Hex) >= 8 then
    Result.Alpha := HexToByte(Ord(Hex[7]), Ord(Hex[8]));
end;

{ TPixieWebColor }

class function TPixieWebColor.Create(R, G, B: Byte; A: Byte): TPixieWebColor;
begin
  Result.Red := R;
  Result.Green := G;
  Result.Blue := B;
  Result.Alpha := A;
  Result.IsCurrentColor := False;
end;

class function TPixieWebColor.CreateCurrentColor: TPixieWebColor;
begin
  Result.Red := 0;
  Result.Green := 0;
  Result.Blue := 0;
  Result.Alpha := 255;
  Result.IsCurrentColor := True;
end;

class function TPixieWebColor.Transparent: TPixieWebColor;
begin
  Result := TPixieWebColor.Create(0, 0, 0, 0);
end;

class function TPixieWebColor.Black: TPixieWebColor;
begin
  Result := TPixieWebColor.Create(0, 0, 0, 255);
end;

class function TPixieWebColor.White: TPixieWebColor;
begin
  Result := TPixieWebColor.Create(255, 255, 255, 255);
end;

class function TPixieWebColor.CurrentColor: TPixieWebColor;
begin
  Result := CreateCurrentColor;
end;

class operator TPixieWebColor.Equal(const A, B: TPixieWebColor): Boolean;
begin
  Result := (A.Red = B.Red) and (A.Green = B.Green) and (A.Blue = B.Blue) and (A.Alpha = B.Alpha);
end;

class operator TPixieWebColor.NotEqual(const A, B: TPixieWebColor): Boolean;
begin
  Result := not (A = B);
end;

function TPixieWebColor.ToString: string;
begin
  if Alpha <> 0 then
    Result := Format('%.2X%.2X%.2X%.2X', [Red, Green, Blue, Alpha])
  else
    Result := Format('%.2X%.2X%.2X', [Red, Green, Blue]);
end;

function PixieParseHashColorString(const S: string; out Color: TPixieWebColor): Boolean;
var
  Hex: string;
  Len, I, Off: Integer;
begin
  Result := False;
  Hex := S;

  // Strip leading '#'
  if (Hex <> '') and (Hex[1] = '#') then
  begin
    Off := 2;
    Len := Length(Hex) - 1;
  end
  else
  begin
    Off := 1;
    Len := Length(Hex);
  end;

  if not ((Len = 3) or (Len = 4) or (Len = 6) or (Len = 8)) then
    Exit;

  for I := Off to Off + Len - 1 do
    if not PixieIsHexDigit(Ord(Hex[I])) then
      Exit;

  if (Len = 3) or (Len = 4) then
  begin
    Color := TPixieWebColor.Create(
      HexToByte(Ord(Hex[Off]), Ord(Hex[Off])),
      HexToByte(Ord(Hex[Off + 1]), Ord(Hex[Off + 1])),
      HexToByte(Ord(Hex[Off + 2]), Ord(Hex[Off + 2])));
    if Len = 4 then
      Color.Alpha := HexToByte(Ord(Hex[Off + 3]), Ord(Hex[Off + 3]));
  end
  else
  begin
    Color := TPixieWebColor.Create(
      HexToByte(Ord(Hex[Off]), Ord(Hex[Off + 1])),
      HexToByte(Ord(Hex[Off + 2]), Ord(Hex[Off + 3])),
      HexToByte(Ord(Hex[Off + 4]), Ord(Hex[Off + 5])));
    if Len = 8 then
      Color.Alpha := HexToByte(Ord(Hex[Off + 6]), Ord(Hex[Off + 7]));
  end;
  Result := True;
end;

function PixieParseNamedColor(const Name: string; out Color: TPixieWebColor): Boolean;
begin
  Result := ColorMap.TryGetValue(PixieLowerCase(Name), Color);
end;

function PixieParseColorString(const S: string; out Color: TPixieWebColor): Boolean;
var
  Trimmed: string;
begin
  Trimmed := PixieTrim(S);
  if Trimmed = '' then
    Exit(False);

  if PixieEqualI(Trimmed, 'currentcolor') then
  begin
    Color := TPixieWebColor.CurrentColor;
    Exit(True);
  end;

  if PixieParseHashColorString(Trimmed, Color) then
    Exit(True);

  Result := PixieParseNamedColor(Trimmed, Color);
end;

procedure PixieHslToRgb(Hue, Sat, Light: Single; out R, G, B: Single);
var
  H, S, L, K, A: Single;

  function F(N: Single): Single;
  begin
    K := N + H / 30;
    K := K - Floor(K / 12) * 12;
    A := S * Min(L, 1 - L);
    Result := L - A * Max(-1, Min(Min(K - 3, 9 - K), 1));
  end;

begin
  H := Hue;
  H := H - Floor(H / 360) * 360;
  if H < 0 then
    H := H + 360;

  S := Sat / 100;
  L := Light / 100;

  R := F(0);
  G := F(8);
  B := F(4);
end;

procedure InitColorMap;
var
  I: Integer;
  Hex: string;
  Clr: TPixieWebColor;
begin
  ColorMap := TPixieColorMap.Create;
  for I := 0 to High(DefColors) do
  begin
    Hex := DefColors[I].Hex;
    if Length(Hex) = 8 then
      Clr := TPixieWebColor.Create(
        HexToByte(Ord(Hex[1]), Ord(Hex[2])),
        HexToByte(Ord(Hex[3]), Ord(Hex[4])),
        HexToByte(Ord(Hex[5]), Ord(Hex[6])),
        HexToByte(Ord(Hex[7]), Ord(Hex[8])))
    else
      Clr := TPixieWebColor.Create(
        HexToByte(Ord(Hex[1]), Ord(Hex[2])),
        HexToByte(Ord(Hex[3]), Ord(Hex[4])),
        HexToByte(Ord(Hex[5]), Ord(Hex[6])));
    if not ColorMap.ContainsKey(DefColors[I].Name) then
      ColorMap.Add(DefColors[I].Name, Clr);
  end;
end;

// ---------------------------------------------------------------------------
// Colour utilities
// ---------------------------------------------------------------------------

procedure PixieRgbToHsl(R, G, B: Byte; out H, S, L: Single);
var
  Rf, Gf, Bf, MaxC, MinC, Delta: Single;
begin
  Rf := R / 255;
  Gf := G / 255;
  Bf := B / 255;
  MaxC := Max(Rf, Max(Gf, Bf));
  MinC := Min(Rf, Min(Gf, Bf));
  L := (MaxC + MinC) / 2;

  if MaxC = MinC then
  begin
    H := 0;
    S := 0;
  end
  else
  begin
    Delta := MaxC - MinC;
    if L > 0.5 then
      S := Delta / (2 - MaxC - MinC)
    else
      S := Delta / (MaxC + MinC);

    if MaxC = Rf then
    begin
      H := (Gf - Bf) / Delta;
      if Gf < Bf then
        H := H + 6;
    end
    else if MaxC = Gf then
      H := (Bf - Rf) / Delta + 2
    else
      H := (Rf - Gf) / Delta + 4;

    H := H * 60;
  end;

  S := S * 100;
  L := L * 100;
end;

function PixieColorBlend(const A, B: TPixieWebColor; T: Single): TPixieWebColor;
var
  Tc: Single;
begin
  Tc := EnsureRange(T, 0, 1);
  Result := TPixieWebColor.Create(
    Byte(Round(A.Red   + (B.Red   - A.Red)   * Tc)),
    Byte(Round(A.Green + (B.Green - A.Green) * Tc)),
    Byte(Round(A.Blue  + (B.Blue  - A.Blue)  * Tc)),
    Byte(Round(A.Alpha + (B.Alpha - A.Alpha) * Tc)));
end;

function PixieColorLuminance(const C: TPixieWebColor): Single;

  function Linearize(V: Byte): Single;
  var
    Sv: Single;
  begin
    Sv := V / 255;
    if Sv <= 0.04045 then
      Result := Sv / 12.92
    else
      Result := Power((Sv + 0.055) / 1.055, 2.4);
  end;

begin
  Result := 0.2126 * Linearize(C.Red) +
            0.7152 * Linearize(C.Green) +
            0.0722 * Linearize(C.Blue);
end;

function PixieColorWithAlpha(const C: TPixieWebColor; A: Byte): TPixieWebColor;
begin
  Result := TPixieWebColor.Create(C.Red, C.Green, C.Blue, A);
end;

initialization
  InitColorMap;

finalization
  ColorMap.Free;

end.
