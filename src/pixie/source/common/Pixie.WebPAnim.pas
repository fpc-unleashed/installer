unit Pixie.WebPAnim;

// Animated WebP (ANMF) decoder. Produces fully-composited straight-alpha BGRA
// frames matching the TPixieRawAnimation contract that Pixie.GifDecode and
// Pixie.ApngDecode also emit, so the existing 30 Hz playback machinery handles
// it unchanged.
//
// Each ANMF frame's image data (optional ALPH + VP8/VP8L) is decoded by the
// still decoder (Pixie.WebP.Decoder): the frame payload is wrapped in a minimal
// synthetic RIFF/WEBP/VP8X container and handed to WebPDecodeBGRA. WebP's
// compositing is a strict subset of APNG's (blend over/source; dispose
// none/background -- no dispose-to-previous), so the shared APNG compositor
// (PixieBlendFrameBgra) and clear-rect helper are reused.
//
// The canvas starts transparent and dispose-to-background clears to transparent
// (the ANIM background colour is ignored, matching libwebp's WebPAnimDecoder
// and browser behaviour).

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes,
  Pixie.AnimatedImage;

// Decode an animated WebP stream. Returns False if the stream is not an
// animated WebP or no frame could be produced.
function PixieDecodeWebPAnim(Stream: TStream;
  out Data: TPixieRawAnimation): Boolean;

// Cheap peek: RIFF/WEBP magic with a VP8X chunk whose animation flag is set.
// Restores the stream position before returning.
function PixieIsWebPAnimStream(Stream: TStream): Boolean;

implementation

uses
  Pixie.WebP.Decoder;

const
  VP8X_ANIMATION_FLAG = $02;
  VP8X_ALPHA_FLAG     = $10;
  ANMF_BLEND_FLAG     = $02;    // 0 = blend over, 1 = source (overwrite)
  ANMF_DISPOSE_FLAG   = $01;    // 1 = dispose frame rect to background
  MAX_ANIM_FRAMES     = 16384;  // guard against absurd frame counts

function ReadLE16(const Buf: TBytes; Off: Integer): Integer; inline;
begin
  Result := Buf[Off] or (Integer(Buf[Off + 1]) shl 8);
end;

function ReadLE24(const Buf: TBytes; Off: Integer): Integer; inline;
begin
  Result := Buf[Off] or (Integer(Buf[Off + 1]) shl 8) or
            (Integer(Buf[Off + 2]) shl 16);
end;

function ReadLE32(const Buf: TBytes; Off: Integer): LongWord; inline;
begin
  Result := Buf[Off] or (LongWord(Buf[Off + 1]) shl 8) or
            (LongWord(Buf[Off + 2]) shl 16) or (LongWord(Buf[Off + 3]) shl 24);
end;

function FourCC(const Buf: TBytes; Off: Integer;
  C0, C1, C2, C3: AnsiChar): Boolean; inline;
begin
  Result := (Buf[Off] = Byte(C0)) and (Buf[Off + 1] = Byte(C1)) and
            (Buf[Off + 2] = Byte(C2)) and (Buf[Off + 3] = Byte(C3));
end;

// Decode one frame's image data (ALPH? + VP8/VP8L) by wrapping it in a synthetic
// RIFF/WEBP/VP8X still container and reusing the still decoder. The VP8X alpha
// flag is always set so the decoder merges an ALPH chunk when present; if there
// is no ALPH chunk the merge is simply skipped. Returns straight-alpha BGRA.
function DecodeFrame(const Buf: TBytes; PayOff, PayLen, W, H: Integer;
  out Bgra: TBytes): Boolean;
var
  Container: TBytes;
  CLen, RiffLen, DW, DH: Integer;
  Raw: PByte;
begin
  Result := False;
  if (PayLen <= 0) or (W <= 0) or (H <= 0) then Exit;
  if PayOff + PayLen > Length(Buf) then Exit;
  // RIFF(12) + VP8X chunk(8 header + 10 payload) + frame payload.
  CLen := 12 + 18 + PayLen;
  SetLength(Container, CLen);
  RiffLen := CLen - 8;
  Container[0] := Ord('R'); Container[1] := Ord('I');
  Container[2] := Ord('F'); Container[3] := Ord('F');
  Container[4] := Byte(RiffLen); Container[5] := Byte(RiffLen shr 8);
  Container[6] := Byte(RiffLen shr 16); Container[7] := Byte(RiffLen shr 24);
  Container[8] := Ord('W'); Container[9] := Ord('E');
  Container[10] := Ord('B'); Container[11] := Ord('P');
  // VP8X: FourCC, size=10, flags (alpha set), canvas W-1 / H-1 (24-bit LE).
  Container[12] := Ord('V'); Container[13] := Ord('P');
  Container[14] := Ord('8'); Container[15] := Ord('X');
  Container[16] := 10;
  Container[20] := VP8X_ALPHA_FLAG;
  Container[24] := Byte(W - 1); Container[25] := Byte((W - 1) shr 8);
  Container[26] := Byte((W - 1) shr 16);
  Container[27] := Byte(H - 1); Container[28] := Byte((H - 1) shr 8);
  Container[29] := Byte((H - 1) shr 16);
  Move(Buf[PayOff], Container[30], PayLen);

  Raw := WebPDecodeBGRA(@Container[0], CLen, DW, DH);
  if Raw = nil then Exit;
  try
    if (DW <> W) or (DH <> H) then Exit;
    SetLength(Bgra, W * H * 4);
    Move(Raw^, Bgra[0], W * H * 4);
    Result := True;
  finally
    FreeMem(Raw);
  end;
end;

function PixieDecodeWebPAnim(Stream: TStream;
  out Data: TPixieRawAnimation): Boolean;
var
  Buf: TBytes;
  Size, Pos, ChunkSize, Padded: Integer;
  StartPos: Int64;
  CanvasW, CanvasH, Loops: Integer;
  HaveCanvas, IsAnim: Boolean;
  Canvas: TBytes;
  FrameX, FrameY, FrameW, FrameH, Duration, Flags: Integer;
  BlendOver: Boolean;
  Sub: TBytes;
  Frames: TPixieRawAnimFrameArray;
  Flags32: LongWord;
begin
  Result := False;
  Data.Width := 0; Data.Height := 0; Data.Loops := 0;
  SetLength(Data.Frames, 0);
  if Stream = nil then Exit;

  StartPos := Stream.Position;
  Size := Integer(Stream.Size - StartPos);
  if Size < 21 then Exit;
  SetLength(Buf, Size);
  if Stream.Read(Buf[0], Size) <> Size then
  begin
    Stream.Position := StartPos;
    Exit;
  end;
  Stream.Position := StartPos;

  if not FourCC(Buf, 0, 'R', 'I', 'F', 'F') then Exit;
  if not FourCC(Buf, 8, 'W', 'E', 'B', 'P') then Exit;

  CanvasW := 0; CanvasH := 0; Loops := 0;
  HaveCanvas := False; IsAnim := False;
  SetLength(Canvas, 0);
  SetLength(Frames, 0);

  Pos := 12;
  while Pos + 8 <= Size do
  begin
    ChunkSize := Integer(ReadLE32(Buf, Pos + 4));
    if (ChunkSize < 0) or (Pos + 8 + ChunkSize > Size) then Break;

    if FourCC(Buf, Pos, 'V', 'P', '8', 'X') then
    begin
      if ChunkSize >= 10 then
      begin
        Flags32 := ReadLE32(Buf, Pos + 8);
        IsAnim := (Flags32 and VP8X_ANIMATION_FLAG) <> 0;
        CanvasW := ReadLE24(Buf, Pos + 12) + 1;
        CanvasH := ReadLE24(Buf, Pos + 12 + 3) + 1;
        HaveCanvas := True;
      end;
    end
    else if FourCC(Buf, Pos, 'A', 'N', 'I', 'M') then
    begin
      if ChunkSize >= 6 then
        Loops := ReadLE16(Buf, Pos + 8 + 4);   // bg colour (4) then loop count
    end
    else if FourCC(Buf, Pos, 'A', 'N', 'M', 'F') then
    begin
      if (not HaveCanvas) or (not IsAnim) then Break;
      if ChunkSize < 17 then Break;
      FrameX := ReadLE24(Buf, Pos + 8) * 2;
      FrameY := ReadLE24(Buf, Pos + 8 + 3) * 2;
      FrameW := ReadLE24(Buf, Pos + 8 + 6) + 1;
      FrameH := ReadLE24(Buf, Pos + 8 + 9) + 1;
      Duration := ReadLE24(Buf, Pos + 8 + 12);
      Flags := Buf[Pos + 8 + 15];
      BlendOver := (Flags and ANMF_BLEND_FLAG) = 0;

      if (FrameX < 0) or (FrameY < 0) or
         (FrameX + FrameW > CanvasW) or (FrameY + FrameH > CanvasH) then Break;
      if Length(Frames) >= MAX_ANIM_FRAMES then Break;

      if Length(Canvas) = 0 then
      begin
        SetLength(Canvas, CanvasW * CanvasH * 4);
        FillChar(Canvas[0], Length(Canvas), 0);   // transparent
      end;

      if not DecodeFrame(Buf, Pos + 8 + 16, ChunkSize - 16,
        FrameW, FrameH, Sub) then Break;

      PixieBlendFrameBgra(Canvas, CanvasW, Sub, FrameX, FrameY,
        FrameW, FrameH, BlendOver);
      PixieEmitFrame(Canvas, Duration, Frames);

      if (Flags and ANMF_DISPOSE_FLAG) <> 0 then
        PixieClearCanvasRect(Canvas, CanvasW, CanvasH,
          FrameX, FrameY, FrameW, FrameH);
    end;

    Padded := ChunkSize + (ChunkSize and 1);     // chunks are even-padded
    Inc(Pos, 8 + Padded);
  end;

  if (not IsAnim) or (Length(Frames) = 0) then Exit;
  Data.Width := CanvasW;
  Data.Height := CanvasH;
  Data.Loops := Loops;
  Data.Frames := Frames;
  Result := True;
end;

function PixieIsWebPAnimStream(Stream: TStream): Boolean;
var
  StartPos: Int64;
  Hdr: array[0..23] of Byte;
begin
  Result := False;
  if Stream = nil then Exit;
  StartPos := Stream.Position;
  try
    if Stream.Read(Hdr, 24) <> 24 then Exit;
    if (Hdr[0] <> Ord('R')) or (Hdr[1] <> Ord('I')) or
       (Hdr[2] <> Ord('F')) or (Hdr[3] <> Ord('F')) then Exit;
    if (Hdr[8] <> Ord('W')) or (Hdr[9] <> Ord('E')) or
       (Hdr[10] <> Ord('B')) or (Hdr[11] <> Ord('P')) then Exit;
    // First chunk must be VP8X for an extended (animated) file.
    if (Hdr[12] <> Ord('V')) or (Hdr[13] <> Ord('P')) or
       (Hdr[14] <> Ord('8')) or (Hdr[15] <> Ord('X')) then Exit;
    Result := (Hdr[20] and VP8X_ANIMATION_FLAG) <> 0;
  finally
    Stream.Position := StartPos;
  end;
end;

end.
