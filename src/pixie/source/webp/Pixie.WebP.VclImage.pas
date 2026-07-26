unit Pixie.WebP.VclImage;

// VCL integration: registers a TGraphic so TPicture / TImage load WebP
// directly, e.g. Image1.Picture.LoadFromFile('photo.webp'). Read-only.
// Delphi/VCL only. Decoding uses the self-contained Pixie.WebP.Decoder.

interface

uses
  Classes, SysUtils, Graphics;

type
  TWebPImage = class(TBitmap)
  public
    procedure LoadFromStream(Stream: TStream); override;
  end;

implementation

uses
  Pixie.WebP.Decoder;

procedure TWebPImage.LoadFromStream(Stream: TStream);
var
  Buf: TBytes;
  Size, W, H, Y: Integer;
  Raw, P: PByte;
begin
  Size := Stream.Size - Stream.Position;
  if Size <= 0 then
    raise Exception.Create('WebP: empty stream');
  SetLength(Buf, Size);
  Stream.ReadBuffer(Buf[0], Size);

  // Straight-alpha BGRA, top-down rows; decoder allocates via GetMem.
  Raw := WebPDecodeBGRA(@Buf[0], NativeUInt(Size), W, H);
  if (Raw = nil) or (W <= 0) or (H <= 0) then
    raise Exception.Create('WebP: decode failed');
  try
    PixelFormat := pf32bit;
    SetSize(W, H);
    P := Raw;
    for Y := 0 to H - 1 do
    begin
      // VCL ScanLine[0] is the top row and pf32bit is BGRA — matches WebP.
      Move(P^, ScanLine[Y]^, W * 4);
      Inc(P, W * 4);
    end;
    AlphaFormat := afDefined;
  finally
    FreeMem(Raw);
  end;
end;

initialization
  TPicture.RegisterFileFormat('webp', 'WebP Image', TWebPImage);

finalization
  TPicture.UnregisterGraphicClass(TWebPImage);

end.
