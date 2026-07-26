unit Pixie.WebP;

// WebP decoding via the self-contained pure-Pascal decoder (Pixie.WebP.Decoder).
// Decode-only: no encoding, no incremental. No external runtime dependency.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

// Decode WebP data to premultiplied BGRA pixels.
// Caller must free the returned Pixels with PixieWebPFreePixels.
function PixieWebPDecode(Data: Pointer; DataSize: Integer;
  out Width, Height: Integer; out Pixels: Pointer): Boolean;

procedure PixieWebPFreePixels(Pixels: Pointer);

implementation

uses
  SysUtils, Pixie.WebP.Decoder;

function PixieWebPDecode(Data: Pointer; DataSize: Integer;
  out Width, Height: Integer; out Pixels: Pointer): Boolean;
var
  Raw: PByte;
  I, Count: Integer;
  P: PByte;
  A: Byte;
begin
  Result := False;
  Pixels := nil;
  Width := 0;
  Height := 0;
  if (Data = nil) or (DataSize <= 0) then Exit;

  // Decode to straight-alpha BGRA (decoder allocates with GetMem).
  Raw := WebPDecodeBGRA(PByte(Data), NativeUInt(DataSize), Width, Height);
  if Raw = nil then Exit;

  // Premultiply alpha in-place; backends consume premultiplied BGRA.
  Count := Width * Height;
  P := Raw;
  for I := 0 to Count - 1 do
  begin
    A := P[3];
    if A = 0 then
    begin
      P[0] := 0;
      P[1] := 0;
      P[2] := 0;
    end
    else if A < 255 then
    begin
      P[0] := (P[0] * A + 127) div 255;
      P[1] := (P[1] * A + 127) div 255;
      P[2] := (P[2] * A + 127) div 255;
    end;
    Inc(P, 4);
  end;

  Pixels := Raw;
  Result := True;
end;

procedure PixieWebPFreePixels(Pixels: Pointer);
begin
  if Pixels <> nil then
    FreeMem(Pixels);
end;

end.
