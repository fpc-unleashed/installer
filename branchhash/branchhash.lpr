program branchhash;

{$mode unleashed}

uses SysUtils, Windows;

function Murmur3_32(const s: String; Seed: LongWord = 0): LongWord;
const
  C1: LongWord = $cc9e2d51;
  C2: LongWord = $1b873593;

  function rotl(x: LongWord; r: Byte): LongWord; inline;
  begin
    result := (x shl r) or (x shr (32 - r));
  end;

begin
  {$push}{$Q-}{$R-}

  result := Seed;
  var len := length(s);
  var i := 1;
  while i + 3 <= len do begin
    var k: LongWord := LongWord(Byte(s[i])) or (LongWord(Byte(s[i+1])) shl 8) or (LongWord(Byte(s[i+2])) shl 16) or (LongWord(Byte(s[i+3])) shl 24);
    result := rotl(result xor (rotl(k*C1, 15)*C2), 13)*5+$e6546b64;
    inc(i, 4);
  end;
  var rem := len-i+1;
  if rem > 0 then begin
    var k: LongWord := LongWord(Byte(s[i]));
    if rem >= 2 then k := k or (LongWord(Byte(s[i+1])) shl 8);
    if rem >= 3 then k := k or (LongWord(Byte(s[i+2])) shl 16);
    result := result xor (rotl(k*C1, 15)*C2);
  end;
  result := result xor LongWord(len);
  result := result xor (result shr 16);
  result := result*LongWord($85ebca6b);
  result := result xor (result shr 13);
  result := result*LongWord($c2b2ae35);
  result := result xor (result shr 16);

  {$pop}
end;

const
  AnsiReset  = #27'[0m';
  AnsiRed    = #27'[31m';

begin
  var ldef := 3; // default len
  var lmax := 9; // max len

  if ParamCount < 1 then begin
    writeln(AnsiRed+'<string> [optional <len 2-9> / default len '+IntToStr(ldef)+']'+AnsiReset);
    halt(1);
  end else begin
    var s := LowerCase(HexStr(Murmur3_32(argv[1]), 8));

    var len := if ParamCount >= 2 then StrToIntDef(ParamStr(2), ldef) else ldef;
    len -= 1; // leave 1 for hash len
    if len < 1 then len := 1 else if len > lmax then len := lmax;

    s := IntToStr(len)+copy(s, 1, len);
    writeln(s);
  end;
end.

