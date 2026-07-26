unit Pixie.WebP.Reader;

// FPImage reader for WebP. Registers a TFPCustomImageReader so that
// TFPCustomImage / TLazIntfImage (and, via Pixie.WebP.LclImage, TPicture /
// TImage) can load WebP images. Depends only on the FPImage RTL package and
// the self-contained Pixie.WebP.Decoder — no LCL, no Pixie engine.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Classes, SysUtils, FPimage;

type
  TFPReaderWebP = class(TFPCustomImageReader)
  protected
    function InternalCheck(Stream: TStream): Boolean; override;
    procedure InternalRead(Stream: TStream; Img: TFPCustomImage); override;
  end;

implementation

uses
  Pixie.WebP.Decoder;

function TFPReaderWebP.InternalCheck(Stream: TStream): Boolean;
var
  Hdr: array[0..11] of Byte;
  SavePos: Int64;
begin
  Result := False;
  if Stream = nil then
    Exit;
  SavePos := Stream.Position;
  try
    if Stream.Read(Hdr, SizeOf(Hdr)) < SizeOf(Hdr) then
      Exit;
    // RIFF <4-byte size> WEBP
    Result := (Hdr[0] = Ord('R')) and (Hdr[1] = Ord('I')) and
              (Hdr[2] = Ord('F')) and (Hdr[3] = Ord('F')) and
              (Hdr[8] = Ord('W')) and (Hdr[9] = Ord('E')) and
              (Hdr[10] = Ord('B')) and (Hdr[11] = Ord('P'));
  finally
    Stream.Position := SavePos;
  end;
end;

procedure TFPReaderWebP.InternalRead(Stream: TStream; Img: TFPCustomImage);
var
  Buf: TBytes;
  Size: Integer;
  Raw, P: PByte;
  W, H, X, Y: Integer;
  C: TFPColor;
begin
  Size := Stream.Size - Stream.Position;
  if Size <= 0 then
    raise Exception.Create('WebP: empty stream');
  SetLength(Buf, Size);
  Stream.ReadBuffer(Buf[0], Size);

  // Straight-alpha BGRA; the decoder allocates the buffer with GetMem.
  Raw := WebPDecodeBGRA(@Buf[0], NativeUInt(Size), W, H);
  if (Raw = nil) or (W <= 0) or (H <= 0) then
    raise Exception.Create('WebP: decode failed');
  try
    Img.SetSize(W, H);
    P := Raw;
    for Y := 0 to H - 1 do
      for X := 0 to W - 1 do
      begin
        // 8-bit BGRA -> 16-bit FPColor (x * 257 maps 255 -> 65535).
        C.Blue  := P[0] * 257;
        C.Green := P[1] * 257;
        C.Red   := P[2] * 257;
        C.Alpha := P[3] * 257;
        Img.Colors[X, Y] := C;
        Inc(P, 4);
      end;
  finally
    FreeMem(Raw);
  end;
end;

initialization
  ImageHandlers.RegisterImageReader('WebP Image', 'webp', TFPReaderWebP);

end.
