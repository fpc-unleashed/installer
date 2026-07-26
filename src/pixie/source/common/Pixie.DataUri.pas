unit Pixie.DataUri;

// Decode data: URIs (base64 or URL-encoded) into a TMemoryStream.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes;

function DecodeDataUri(const Src: string;
  out Stream: TMemoryStream): Boolean;

implementation

uses
  {$IFDEF FPC}Base64{$ELSE}System.NetEncoding{$ENDIF},
  Pixie.Utils;

procedure WritePercentDecoded(Stream: TMemoryStream;
  const Src: string; StartIndex: Integer);
var
  I, N, BufLen: Integer;
  Buf: array of Byte;
  C1, C2: Integer;
begin
  N := Length(Src);
  // Upper bound: every char takes one output byte (percent-escapes shrink 3:1)
  SetLength(Buf, N - StartIndex + 1);
  BufLen := 0;
  I := StartIndex;
  while I <= N do
  begin
    if (Src[I] = '%') and (I + 2 <= N) then
    begin
      C1 := Ord(Src[I + 1]);
      C2 := Ord(Src[I + 2]);
      if PixieIsHexDigit(C1) and PixieIsHexDigit(C2) then
      begin
        Buf[BufLen] := Byte((PixieDigitValue(C1) shl 4) or PixieDigitValue(C2));
        Inc(BufLen);
        Inc(I, 3);
        Continue;
      end;
    end;
    if Src[I] = '+' then
      Buf[BufLen] := Ord(' ')
    else
      Buf[BufLen] := Byte(Ord(Src[I]));
    Inc(BufLen);
    Inc(I);
  end;
  if BufLen > 0 then
    Stream.Write(Buf[0], BufLen);
end;

{$IFDEF FPC}
type
  TReadOnlyStream = class(TCustomMemoryStream)
  public
    constructor Create(P: Pointer; ASize: Integer);
  end;

constructor TReadOnlyStream.Create(P: Pointer; ASize: Integer);
begin
  inherited Create;
  SetPointer(P, ASize);
end;
{$ENDIF}

function DecodeDataUri(const Src: string;
  out Stream: TMemoryStream): Boolean;
var
  Marker, DataLen, CommaPos: Integer;
{$IFDEF FPC}
  Input: TReadOnlyStream;
  Decoder: TBase64DecodingStream;
  Buf: array[0..4095] of Byte;
  Count: Integer;
{$ELSE}
  Bytes: TBytes;
{$ENDIF}
begin
  Result := False;
  Stream := nil;

  // Find ;base64, marker
  Marker := Pos(';base64,', Src);
  if Marker = 0 then
  begin
    // No base64 — treat as URL-encoded payload after first comma.
    // Format: data:[<mediatype>][;<param>=<value>...],<data>
    if (Length(Src) < 6) or (Copy(Src, 1, 5) <> 'data:') then Exit;
    CommaPos := Pos(',', Src);
    if CommaPos = 0 then Exit;
    Stream := TMemoryStream.Create;
    try
      WritePercentDecoded(Stream, Src, CommaPos + 1);
      Result := Stream.Size > 0;
      if Result then
        Stream.Position := 0
      else
        FreeAndNil(Stream);
    except
      FreeAndNil(Stream);
      Result := False;
    end;
    Exit;
  end;

  DataLen := Length(Src) - Marker - 7;
  if DataLen <= 0 then Exit;

  Stream := TMemoryStream.Create;
  try
  {$IFDEF FPC}
    // Point directly into Src buffer — no copy (safe: Src is const)
    Input := TReadOnlyStream.Create(@Src[Marker + 8], DataLen);
    try
      Decoder := TBase64DecodingStream.Create(Input);
      try
        repeat
          Count := Decoder.Read(Buf, SizeOf(Buf));
          if Count > 0 then
            Stream.Write(Buf, Count);
        until Count = 0;
      finally
        Decoder.Free;
      end;
    finally
      Input.Free;
    end;
  {$ELSE}
    Bytes := TNetEncoding.Base64.DecodeStringToBytes(
      Copy(Src, Marker + 8, MaxInt));
    if Length(Bytes) > 0 then
      Stream.Write(Bytes[0], Length(Bytes));
  {$ENDIF}
    Result := Stream.Size > 0;
    if Result then
      Stream.Position := 0
    else
      FreeAndNil(Stream);
  except
    FreeAndNil(Stream);
    Result := False;
  end;
end;

end.
