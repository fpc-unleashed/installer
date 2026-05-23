{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit hash_util;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

// returns SHA256 of the file as a hex string in upper case
function SHA256OfFile(const Path: string): string;

implementation

uses
  fpsha256;

const
  CHUNK_SIZE = 64*1024;

function SHA256OfFile(const Path: string): string;
var
  SHA: TSHA256;
  Buf: array[0..CHUNK_SIZE-1] of Byte;
  N: LongInt;
  Hex: AnsiString;
begin
  Result := '';
  var Stream := autofree TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  // TSHA256 is an advanced record -- no Create/Free
  SHA.Init;
  repeat
    N := Stream.Read(Buf[0], Length(Buf));
    if N > 0 then SHA.Update(@Buf[0], N);
  until N <= 0;
  SHA.Final;
  SHA.OutputHexa(Hex);
  Result := UpperCase(Hex);
end;

end.
