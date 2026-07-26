unit Pixie.WebP.LclImage;

// LCL integration: registers a TGraphic so TPicture / TImage load WebP
// directly, e.g. Image1.Picture.LoadFromFile('photo.webp'). Read-only.
// Decoding goes through the FPImage reader in Pixie.WebP.Reader.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Classes, SysUtils, Graphics, FPimage, Pixie.WebP.Reader;

type
  TWebPImage = class(TFPImageBitmap)
  protected
    class function GetReaderClass: TFPCustomImageReaderClass; override;
    class function GetWriterClass: TFPCustomImageWriterClass; override;
  public
    class function GetFileExtensions: string; override;
    class function IsStreamFormatSupported(Stream: TStream): Boolean; override;
  end;

implementation

class function TWebPImage.GetReaderClass: TFPCustomImageReaderClass;
begin
  Result := TFPReaderWebP;
end;

class function TWebPImage.GetWriterClass: TFPCustomImageWriterClass;
begin
  Result := nil; // read-only: no WebP encoder
end;

class function TWebPImage.GetFileExtensions: string;
begin
  Result := 'webp';
end;

class function TWebPImage.IsStreamFormatSupported(Stream: TStream): Boolean;
var
  Hdr: array[0..11] of Byte;
  SavePos: Int64;
begin
  Result := False;
  SavePos := Stream.Position;
  try
    if Stream.Read(Hdr, SizeOf(Hdr)) = SizeOf(Hdr) then
      Result := (Hdr[0] = Ord('R')) and (Hdr[1] = Ord('I')) and
                (Hdr[2] = Ord('F')) and (Hdr[3] = Ord('F')) and
                (Hdr[8] = Ord('W')) and (Hdr[9] = Ord('E')) and
                (Hdr[10] = Ord('B')) and (Hdr[11] = Ord('P'));
  finally
    Stream.Position := SavePos;
  end;
end;

initialization
  TPicture.RegisterFileFormat('webp', 'WebP Image', TWebPImage);

finalization
  TPicture.UnregisterGraphicClass(TWebPImage);

end.
