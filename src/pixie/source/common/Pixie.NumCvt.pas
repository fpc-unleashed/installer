unit Pixie.NumCvt;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Pixie.Types;

function PixieToLatinLower(Value: Integer): string;
function PixieToLatinUpper(Value: Integer): string;
function PixieToGreekLower(Value: Integer): string;
function PixieToRomanLower(Value: Integer): string;
function PixieToRomanUpper(Value: Integer): string;

// Format a counter value using the given list style type.
function PixieFormatListCounter(Value: Integer;
  Style: TPixieListStyleType): string;

implementation

uses
  SysUtils, Pixie.Utf8;

const
  LatinLower: array[0..25] of Char = (
    'a','b','c','d','e','f','g','h','i','j','k','l','m',
    'n','o','p','q','r','s','t','u','v','w','x','y','z'
  );

  LatinUpper: array[0..25] of Char = (
    'A','B','C','D','E','F','G','H','I','J','K','L','M',
    'N','O','P','Q','R','S','T','U','V','W','X','Y','Z'
  );

  // Greek lowercase: alpha(U+03B1) through omega(U+03C9), skipping final sigma(U+03C2)
  GreekLowerCodes: array[0..23] of UInt32 = (
    $03B1, $03B2, $03B3, $03B4, $03B5, $03B6, $03B7, $03B8,
    $03B9, $03BA, $03BB, $03BC, $03BD, $03BE, $03BF, $03C0,
    $03C1, $03C3, $03C4, $03C5, $03C6, $03C7, $03C8, $03C9
  );

function ToMappedAlphaChar(Num: Integer; const Map: array of Char): string;
var
  Dividend, Modulo, MapSize: Integer;
begin
  Result := '';
  Dividend := Num;
  MapSize := Length(Map);

  while Dividend > 0 do
  begin
    Modulo := (Dividend - 1) mod MapSize;
    Result := Map[Modulo] + Result;
    Dividend := (Dividend - Modulo) div MapSize;
  end;
end;

function ToMappedAlphaUnicode(Num: Integer; const Map: array of UInt32): string;
var
  Dividend, Modulo, MapSize: Integer;
  Ch: string;
begin
  Result := '';
  Dividend := Num;
  MapSize := Length(Map);

  while Dividend > 0 do
  begin
    Modulo := (Dividend - 1) mod MapSize;
    Ch := '';
    AppendUtf8Char(Ch, Map[Modulo]);
    Result := Ch + Result;
    Dividend := (Dividend - Modulo) div MapSize;
  end;
end;

function PixieToLatinLower(Value: Integer): string;
begin
  Result := ToMappedAlphaChar(Value, LatinLower);
end;

function PixieToLatinUpper(Value: Integer): string;
begin
  Result := ToMappedAlphaChar(Value, LatinUpper);
end;

function PixieToGreekLower(Value: Integer): string;
begin
  Result := ToMappedAlphaUnicode(Value, GreekLowerCodes);
end;

type
  TRomanData = record
    Value: Integer;
    Numeral: string;
  end;

function PixieToRomanLower(Value: Integer): string;
const
  RomanData: array[0..12] of TRomanData = (
    (Value: 1000; Numeral: 'm'),
    (Value: 900;  Numeral: 'cm'),
    (Value: 500;  Numeral: 'd'),
    (Value: 400;  Numeral: 'cd'),
    (Value: 100;  Numeral: 'c'),
    (Value: 90;   Numeral: 'xc'),
    (Value: 50;   Numeral: 'l'),
    (Value: 40;   Numeral: 'xl'),
    (Value: 10;   Numeral: 'x'),
    (Value: 9;    Numeral: 'ix'),
    (Value: 5;    Numeral: 'v'),
    (Value: 4;    Numeral: 'iv'),
    (Value: 1;    Numeral: 'i')
  );
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(RomanData) do
    while Value >= RomanData[I].Value do
    begin
      Result := Result + RomanData[I].Numeral;
      Dec(Value, RomanData[I].Value);
    end;
end;

function PixieToRomanUpper(Value: Integer): string;
const
  RomanData: array[0..12] of TRomanData = (
    (Value: 1000; Numeral: 'M'),
    (Value: 900;  Numeral: 'CM'),
    (Value: 500;  Numeral: 'D'),
    (Value: 400;  Numeral: 'CD'),
    (Value: 100;  Numeral: 'C'),
    (Value: 90;   Numeral: 'XC'),
    (Value: 50;   Numeral: 'L'),
    (Value: 40;   Numeral: 'XL'),
    (Value: 10;   Numeral: 'X'),
    (Value: 9;    Numeral: 'IX'),
    (Value: 5;    Numeral: 'V'),
    (Value: 4;    Numeral: 'IV'),
    (Value: 1;    Numeral: 'I')
  );
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(RomanData) do
    while Value >= RomanData[I].Value do
    begin
      Result := Result + RomanData[I].Numeral;
      Dec(Value, RomanData[I].Value);
    end;
end;

function PixieFormatListCounter(Value: Integer;
  Style: TPixieListStyleType): string;
begin
  case Style of
    lstDecimal:
      Result := IntToStr(Value);
    lstDecimalLeadingZero:
    begin
      Result := IntToStr(Value);
      if Length(Result) = 1 then
        Result := '0' + Result;
    end;
    lstLowerLatin, lstLowerAlpha:
      Result := PixieToLatinLower(Value);
    lstLowerGreek:
      Result := PixieToGreekLower(Value);
    lstUpperAlpha, lstUpperLatin:
      Result := PixieToLatinUpper(Value);
    lstLowerRoman:
      Result := PixieToRomanLower(Value);
    lstUpperRoman:
      Result := PixieToRomanUpper(Value);
  else
    Result := IntToStr(Value);
  end;
end;

end.
