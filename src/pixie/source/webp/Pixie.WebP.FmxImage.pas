unit Pixie.WebP.FmxImage;

// FMX integration: registers a TCustomBitmapCodec so FMX TImage / TBitmap
// load .webp directly, e.g. Image1.Bitmap.LoadFromFile('photo.webp').
// Delphi/FMX only. Read-only. Decoding uses Pixie.WebP.Decoder.

interface

implementation

uses
  System.Classes, System.SysUtils, System.Types, System.UITypes,
  FMX.Types, FMX.Graphics, FMX.Surfaces,
  Pixie.WebP.Decoder;

type
  TWebPCodec = class(TCustomBitmapCodec)
  public
    class function GetImageSize(const AFileName: string): TPointF; override;
    class function IsValid(const AStream: TStream): Boolean; override;
    function LoadFromFile(const AFileName: string; const ABitmap: TBitmapSurface;
      const AMaxSizeLimit: Cardinal = 0): Boolean; override;
    function LoadFromStream(const AStream: TStream; const ABitmap: TBitmapSurface;
      const AMaxSizeLimit: Cardinal = 0): Boolean; override;
    function LoadThumbnailFromFile(const AFileName: string;
      const AFitWidth, AFitHeight: Single; const UseEmbedded: Boolean;
      const ABitmap: TBitmapSurface): Boolean; override;
    function SaveToFile(const AFileName: string; const ABitmap: TBitmapSurface;
      const ASaveParams: PBitmapCodecSaveParams = nil): Boolean; override;
    function SaveToStream(const AStream: TStream; const ABitmap: TBitmapSurface;
      const AExtension: string;
      const ASaveParams: PBitmapCodecSaveParams = nil): Boolean; override;
  end;

function ReadStreamBytes(const AStream: TStream; out Buf: TBytes): Integer;
begin
  Result := AStream.Size - AStream.Position;
  if Result < 0 then Result := 0;
  SetLength(Buf, Result);
  if Result > 0 then
    AStream.ReadBuffer(Buf[0], Result);
end;

class function TWebPCodec.GetImageSize(const AFileName: string): TPointF;
var
  Buf: TBytes;
  Size, W, H: Integer;
  FS: TFileStream;
begin
  Result := TPointF.Create(0, 0);
  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    Size := ReadStreamBytes(FS, Buf);
  finally
    FS.Free;
  end;
  if (Size > 0) and WebPGetInfo(@Buf[0], NativeUInt(Size), W, H) then
    Result := TPointF.Create(W, H);
end;

class function TWebPCodec.IsValid(const AStream: TStream): Boolean;
var
  Hdr: array[0..11] of Byte;
  SavePos: Int64;
begin
  Result := False;
  SavePos := AStream.Position;
  try
    if AStream.Read(Hdr, SizeOf(Hdr)) = SizeOf(Hdr) then
      Result := (Hdr[0] = Ord('R')) and (Hdr[1] = Ord('I')) and
                (Hdr[2] = Ord('F')) and (Hdr[3] = Ord('F')) and
                (Hdr[8] = Ord('W')) and (Hdr[9] = Ord('E')) and
                (Hdr[10] = Ord('B')) and (Hdr[11] = Ord('P'));
  finally
    AStream.Position := SavePos;
  end;
end;

function TWebPCodec.LoadFromStream(const AStream: TStream;
  const ABitmap: TBitmapSurface; const AMaxSizeLimit: Cardinal): Boolean;
var
  Buf: TBytes;
  Size, W, H, Y: Integer;
  Raw, P: PByte;
begin
  Result := False;
  Size := ReadStreamBytes(AStream, Buf);
  if Size <= 0 then Exit;
  Raw := WebPDecodeBGRA(@Buf[0], NativeUInt(Size), W, H);
  if (Raw = nil) or (W <= 0) or (H <= 0) then Exit;
  try
    ABitmap.SetSize(W, H, TPixelFormat.BGRA);
    P := Raw;
    for Y := 0 to H - 1 do
    begin
      Move(P^, ABitmap.Scanline[Y]^, W * 4);
      Inc(P, W * 4);
    end;
    Result := True;
  finally
    FreeMem(Raw);
  end;
end;

function TWebPCodec.LoadFromFile(const AFileName: string;
  const ABitmap: TBitmapSurface; const AMaxSizeLimit: Cardinal): Boolean;
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := LoadFromStream(FS, ABitmap, AMaxSizeLimit);
  finally
    FS.Free;
  end;
end;

function TWebPCodec.LoadThumbnailFromFile(const AFileName: string;
  const AFitWidth, AFitHeight: Single; const UseEmbedded: Boolean;
  const ABitmap: TBitmapSurface): Boolean;
begin
  // No embedded thumbnail in WebP; just decode the full image.
  Result := LoadFromFile(AFileName, ABitmap);
end;

function TWebPCodec.SaveToFile(const AFileName: string;
  const ABitmap: TBitmapSurface; const ASaveParams: PBitmapCodecSaveParams): Boolean;
begin
  Result := False; // read-only: no WebP encoder
end;

function TWebPCodec.SaveToStream(const AStream: TStream;
  const ABitmap: TBitmapSurface; const AExtension: string;
  const ASaveParams: PBitmapCodecSaveParams): Boolean;
begin
  Result := False; // read-only: no WebP encoder
end;

initialization
  TBitmapCodecManager.RegisterBitmapCodecClass('.webp', 'WebP Image',
    False, TWebPCodec);

end.
