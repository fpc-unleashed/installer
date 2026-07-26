unit Pixie.ApngDecode;

// Pure-Pascal APNG (Animated PNG) decoder. Produces a list of fully-
// composited BGRA frames (full canvas size) with per-frame delay-ms
// and a num_plays loop count, matching the TPixieRawAnimation contract
// that Pixie.GifDecode also emits.
//
// Supports:
//   - Colour types 0 (gray), 2 (RGB), 3 (palette), 4 (gray+alpha),
//     6 (RGBA) at bit depths 1/2/4/8/16. 16-bit samples are truncated
//     to 8-bit.
//   - tRNS (palette per-entry alpha; gray/RGB single transparent value).
//   - PNG scanline filtering (None/Sub/Up/Average/Paeth) per RFC 2083.
//   - APNG dispose_op (NONE/BACKGROUND/PREVIOUS) and blend_op
//     (SOURCE/OVER, Porter-Duff source-over).
//   - fcTL before-IDAT vs after-IDAT (FirstFrameIsDefault).
//
// Does NOT support: Adam7-interlaced frames (rejected; caller falls
// back to the static PNG decoder).

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes,
  Pixie.AnimatedImage;

// Decode an APNG stream. Returns False if the stream isn't a valid
// APNG or decoding fails before any frame is produced. On True,
// Data.Frames is populated with at least one frame.
function PixieDecodeApng(Stream: TStream;
  out Data: TPixieRawAnimation): Boolean;

// Cheap peek: PNG signature + scan chunk headers until we see acTL
// (returns True) or IDAT/IEND (returns False). Restores stream
// position before returning.
function PixieIsApngStream(Stream: TStream): Boolean;

implementation

uses
  Math, Pixie.Encoding;

const
  cPngSignature: array[0..7] of Byte =
    ($89, $50, $4E, $47, $0D, $0A, $1A, $0A);

  // APNG dispose_op values
  cApngDisposeNone       = 0;
  cApngDisposeBackground = 1;
  cApngDisposePrevious   = 2;

  // APNG blend_op values
  cApngBlendSource = 0;
  cApngBlendOver   = 1;

  // PNG colour types
  cPngColorGray      = 0;
  cPngColorRgb       = 2;
  cPngColorPalette   = 3;
  cPngColorGrayAlpha = 4;
  cPngColorRgba      = 6;

  // Sniff bound: scan at most this many chunks before giving up.
  cApngSniffMaxChunks = 32;

type
  TPixiePngPaletteEntry = record
    R, G, B, A: Byte;
  end;
  TPixiePngPalette = array[0..255] of TPixiePngPaletteEntry;

  TPixieApngFrameCtl = record
    Width, Height: Integer;
    OffsetX, OffsetY: Integer;
    DelayMs: Integer;
    DisposeOp: Byte;
    BlendOp: Byte;
  end;

  TPixieApngContext = record
    Width, Height: Integer;
    BitDepth: Byte;
    ColorType: Byte;
    Interlace: Byte;
    HasPalette: Boolean;
    Palette: TPixiePngPalette;
    PaletteCount: Integer;
    HasGrayTrns: Boolean;
    GrayTrns: Word;          // 16-bit value (single-channel)
    HasRgbTrns: Boolean;
    RgbTrnsR, RgbTrnsG, RgbTrnsB: Word;
    NumPlays: Integer;
    FirstFrameIsDefault: Boolean;
    Canvas: TBytes;          // running displayed frame (BGRA)
    PrevCanvas: TBytes;      // snapshot for dispose_op = PREVIOUS
  end;

// ---------------------------------------------------------------------------
// Stream + chunk helpers
// ---------------------------------------------------------------------------

function ReadU32Be(Stream: TStream; out Value: LongWord): Boolean;
var
  Bytes: array[0..3] of Byte;
begin
  Result := Stream.Read(Bytes, 4) = 4;
  if Result then
    Value := (LongWord(Bytes[0]) shl 24) or (LongWord(Bytes[1]) shl 16)
      or (LongWord(Bytes[2]) shl 8) or LongWord(Bytes[3]);
end;

function ReadU16Be(const Bytes: array of Byte; Offset: Integer): Word;
begin
  Result := (Word(Bytes[Offset]) shl 8) or Word(Bytes[Offset + 1]);
end;

function ReadU32BeFromBuf(const Bytes: TBytes; Offset: Integer): LongWord;
begin
  Result := (LongWord(Bytes[Offset]) shl 24)
    or (LongWord(Bytes[Offset + 1]) shl 16)
    or (LongWord(Bytes[Offset + 2]) shl 8)
    or LongWord(Bytes[Offset + 3]);
end;

function MatchesType(const Bytes: array of Byte;
  C0, C1, C2, C3: AnsiChar): Boolean;
begin
  Result := (Bytes[0] = Byte(C0)) and (Bytes[1] = Byte(C1))
    and (Bytes[2] = Byte(C2)) and (Bytes[3] = Byte(C3));
end;

function ReadSignature(Stream: TStream): Boolean;
var
  Sig: array[0..7] of Byte;
  I: Integer;
begin
  Result := False;
  if Stream.Read(Sig, 8) <> 8 then Exit;
  for I := 0 to 7 do
    if Sig[I] <> cPngSignature[I] then Exit;
  Result := True;
end;

// ---------------------------------------------------------------------------
// PNG scanline unfilter (RFC 2083 §6)
// ---------------------------------------------------------------------------

function PaethPredictor(A, B, C: Integer): Integer;
var
  P, Pa, Pb, Pc: Integer;
begin
  P := A + B - C;
  Pa := Abs(P - A);
  Pb := Abs(P - B);
  Pc := Abs(P - C);
  if (Pa <= Pb) and (Pa <= Pc) then
    Result := A
  else if Pb <= Pc then
    Result := B
  else
    Result := C;
end;

// Unfilters an interlace-free PNG image plane. Input layout:
//   [filter byte | scanline bytes] * Rows
// Output layout (Recon): RowBytes * Rows, no filter bytes.
// Bpp = bytes-per-pixel for filtering purposes (1 for sub-8-bit packed).
function UnfilterScanlines(const Raw: TBytes; Rows, RowBytes, Bpp: Integer;
  out Recon: TBytes): Boolean;
var
  Y, X: Integer;
  SrcIdx, DstIdx, PrevDstIdx: Integer;
  Filter: Byte;
  Left, Up, UpLeft: Integer;
begin
  Result := False;
  if Length(Raw) <> (RowBytes + 1) * Rows then Exit;
  SetLength(Recon, RowBytes * Rows);

  SrcIdx := 0;
  DstIdx := 0;
  PrevDstIdx := -RowBytes;
  for Y := 0 to Rows - 1 do
  begin
    Filter := Raw[SrcIdx];
    Inc(SrcIdx);

    for X := 0 to RowBytes - 1 do
    begin
      if X >= Bpp then
        Left := Recon[DstIdx + X - Bpp]
      else
        Left := 0;

      if Y > 0 then
        Up := Recon[PrevDstIdx + X]
      else
        Up := 0;

      if (Y > 0) and (X >= Bpp) then
        UpLeft := Recon[PrevDstIdx + X - Bpp]
      else
        UpLeft := 0;

      case Filter of
        0: Recon[DstIdx + X] := Raw[SrcIdx + X];
        1: Recon[DstIdx + X] := Byte(Raw[SrcIdx + X] + Left);
        2: Recon[DstIdx + X] := Byte(Raw[SrcIdx + X] + Up);
        3: Recon[DstIdx + X] := Byte(Raw[SrcIdx + X] + ((Left + Up) shr 1));
        4: Recon[DstIdx + X] :=
             Byte(Raw[SrcIdx + X] + PaethPredictor(Left, Up, UpLeft));
      else
        Exit;
      end;
    end;
    Inc(SrcIdx, RowBytes);
    PrevDstIdx := DstIdx;
    Inc(DstIdx, RowBytes);
  end;
  Result := True;
end;

// ---------------------------------------------------------------------------
// Colour-type → BGRA conversion
// ---------------------------------------------------------------------------

// Per-scanline expansion of sub-8-bit packed samples to one sample per
// byte (colour types 0 and 3 with bit depth 1/2/4). In-place not
// supported; Result is fresh array (W samples per row, RowBytes
// remains W bytes after).
procedure UnpackSubByteScanlines(const Packed_: TBytes;
  Rows, W, BitDepth: Integer; out Plain: TBytes);
var
  SrcRowBytes, Y, X, ByteIdx, BitIdx, SrcOff, DstOff: Integer;
  B, Mask, Sample, SamplesPerByte: Integer;
begin
  SamplesPerByte := 8 div BitDepth;
  Mask := (1 shl BitDepth) - 1;
  SrcRowBytes := (W * BitDepth + 7) div 8;

  SetLength(Plain, Rows * W);
  for Y := 0 to Rows - 1 do
  begin
    SrcOff := Y * SrcRowBytes;
    DstOff := Y * W;
    for X := 0 to W - 1 do
    begin
      ByteIdx := X div SamplesPerByte;
      BitIdx := X mod SamplesPerByte;
      B := Packed_[SrcOff + ByteIdx];
      Sample := (B shr ((SamplesPerByte - 1 - BitIdx) * BitDepth)) and Mask;
      Plain[DstOff + X] := Byte(Sample);
    end;
  end;
end;

// Convert a decoded scanline plane (post-filter, post-bitdepth-unpack)
// to a sub-rect BGRA buffer (W * H * 4 bytes).
function DecodedPlaneToBgra(const Ctx: TPixieApngContext;
  const Plane: TBytes; W, H: Integer; out Bgra: TBytes): Boolean;
var
  PixelCount, I, J, Idx, BgraIdx: Integer;
  R, G, B, A, Gray: Byte;
  PalIdx: Byte;
  Entry: TPixiePngPaletteEntry;
  GrayWord, RWord, GWord, BWord: Word;
begin
  Result := False;
  PixelCount := W * H;
  SetLength(Bgra, PixelCount * 4);

  case Ctx.ColorType of
    cPngColorGray:
    begin
      // tRNS for gray compares against the full sample value, so the
      // <=8bpp branch unpacks sub-8-bit samples first and the 16bpp
      // branch keeps both bytes for the comparison.
      if Ctx.BitDepth <= 8 then
      begin
        if Length(Plane) <> PixelCount then Exit;
        for I := 0 to PixelCount - 1 do
        begin
          BgraIdx := I * 4;
          Gray := Plane[I];
          // Expand sub-8-bit grays to full 8-bit range so 4-bit "F"
          // maps to 255, not 15.
          if Ctx.BitDepth < 8 then
            Gray := Byte((Integer(Gray) * 255) div ((1 shl Ctx.BitDepth) - 1));
          Bgra[BgraIdx] := Gray;
          Bgra[BgraIdx + 1] := Gray;
          Bgra[BgraIdx + 2] := Gray;
          if Ctx.HasGrayTrns and (Word(Plane[I]) = Ctx.GrayTrns) then
            Bgra[BgraIdx + 3] := 0
          else
            Bgra[BgraIdx + 3] := $FF;
        end;
      end
      else
      begin
        if Length(Plane) <> PixelCount * 2 then Exit;
        for I := 0 to PixelCount - 1 do
        begin
          BgraIdx := I * 4;
          Gray := Plane[I * 2];
          GrayWord := (Word(Plane[I * 2]) shl 8) or Plane[I * 2 + 1];
          Bgra[BgraIdx] := Gray;
          Bgra[BgraIdx + 1] := Gray;
          Bgra[BgraIdx + 2] := Gray;
          if Ctx.HasGrayTrns and (GrayWord = Ctx.GrayTrns) then
            Bgra[BgraIdx + 3] := 0
          else
            Bgra[BgraIdx + 3] := $FF;
        end;
      end;
    end;

    cPngColorRgb:
    begin
      if Ctx.BitDepth = 8 then
      begin
        if Length(Plane) <> PixelCount * 3 then Exit;
        for I := 0 to PixelCount - 1 do
        begin
          BgraIdx := I * 4;
          R := Plane[I * 3];
          G := Plane[I * 3 + 1];
          B := Plane[I * 3 + 2];
          Bgra[BgraIdx] := B;
          Bgra[BgraIdx + 1] := G;
          Bgra[BgraIdx + 2] := R;
          if Ctx.HasRgbTrns
            and (Word(R) = Ctx.RgbTrnsR)
            and (Word(G) = Ctx.RgbTrnsG)
            and (Word(B) = Ctx.RgbTrnsB) then
            Bgra[BgraIdx + 3] := 0
          else
            Bgra[BgraIdx + 3] := $FF;
        end;
      end
      else
      begin
        if Length(Plane) <> PixelCount * 6 then Exit;
        for I := 0 to PixelCount - 1 do
        begin
          BgraIdx := I * 4;
          Idx := I * 6;
          R := Plane[Idx];
          G := Plane[Idx + 2];
          B := Plane[Idx + 4];
          RWord := (Word(Plane[Idx]) shl 8) or Plane[Idx + 1];
          GWord := (Word(Plane[Idx + 2]) shl 8) or Plane[Idx + 3];
          BWord := (Word(Plane[Idx + 4]) shl 8) or Plane[Idx + 5];
          Bgra[BgraIdx] := B;
          Bgra[BgraIdx + 1] := G;
          Bgra[BgraIdx + 2] := R;
          if Ctx.HasRgbTrns
            and (RWord = Ctx.RgbTrnsR)
            and (GWord = Ctx.RgbTrnsG)
            and (BWord = Ctx.RgbTrnsB) then
            Bgra[BgraIdx + 3] := 0
          else
            Bgra[BgraIdx + 3] := $FF;
        end;
      end;
    end;

    cPngColorPalette:
    begin
      if not Ctx.HasPalette then Exit;
      if Length(Plane) <> PixelCount then Exit;
      for I := 0 to PixelCount - 1 do
      begin
        BgraIdx := I * 4;
        PalIdx := Plane[I];
        if PalIdx >= Ctx.PaletteCount then
        begin
          Bgra[BgraIdx]     := 0;
          Bgra[BgraIdx + 1] := 0;
          Bgra[BgraIdx + 2] := 0;
          Bgra[BgraIdx + 3] := 0;
          Continue;
        end;
        Entry := Ctx.Palette[PalIdx];
        Bgra[BgraIdx]     := Entry.B;
        Bgra[BgraIdx + 1] := Entry.G;
        Bgra[BgraIdx + 2] := Entry.R;
        Bgra[BgraIdx + 3] := Entry.A;
      end;
    end;

    cPngColorGrayAlpha:
    begin
      if Ctx.BitDepth = 8 then
      begin
        if Length(Plane) <> PixelCount * 2 then Exit;
        for I := 0 to PixelCount - 1 do
        begin
          BgraIdx := I * 4;
          Gray := Plane[I * 2];
          A := Plane[I * 2 + 1];
          Bgra[BgraIdx]     := Gray;
          Bgra[BgraIdx + 1] := Gray;
          Bgra[BgraIdx + 2] := Gray;
          Bgra[BgraIdx + 3] := A;
        end;
      end
      else
      begin
        if Length(Plane) <> PixelCount * 4 then Exit;
        for I := 0 to PixelCount - 1 do
        begin
          BgraIdx := I * 4;
          Gray := Plane[I * 4];
          A := Plane[I * 4 + 2];
          Bgra[BgraIdx]     := Gray;
          Bgra[BgraIdx + 1] := Gray;
          Bgra[BgraIdx + 2] := Gray;
          Bgra[BgraIdx + 3] := A;
        end;
      end;
    end;

    cPngColorRgba:
    begin
      if Ctx.BitDepth = 8 then
      begin
        if Length(Plane) <> PixelCount * 4 then Exit;
        for I := 0 to PixelCount - 1 do
        begin
          BgraIdx := I * 4;
          Bgra[BgraIdx]     := Plane[I * 4 + 2];
          Bgra[BgraIdx + 1] := Plane[I * 4 + 1];
          Bgra[BgraIdx + 2] := Plane[I * 4];
          Bgra[BgraIdx + 3] := Plane[I * 4 + 3];
        end;
      end
      else
      begin
        if Length(Plane) <> PixelCount * 8 then Exit;
        for I := 0 to PixelCount - 1 do
        begin
          BgraIdx := I * 4;
          J := I * 8;
          Bgra[BgraIdx]     := Plane[J + 4];
          Bgra[BgraIdx + 1] := Plane[J + 2];
          Bgra[BgraIdx + 2] := Plane[J];
          Bgra[BgraIdx + 3] := Plane[J + 6];
        end;
      end;
    end;
  else
    Exit;
  end;
  Result := True;
end;

// ---------------------------------------------------------------------------
// APNG compositor
// ---------------------------------------------------------------------------

// Caller (FlushFrame) has already verified the rectangle fits within
// the canvas, so no per-pixel bounds check.
procedure CompositeFrame(var Ctx: TPixieApngContext;
  const SubBgra: TBytes; OffsetX, OffsetY, W, H: Integer; BlendOp: Byte);
begin
  PixieBlendFrameBgra(Ctx.Canvas, Ctx.Width, SubBgra, OffsetX, OffsetY, W, H,
    BlendOp = cApngBlendOver);
end;

procedure ApplyDispose(var Ctx: TPixieApngContext;
  OffsetX, OffsetY, W, H: Integer; DisposeOp: Byte);
begin
  case DisposeOp of
    cApngDisposeBackground:
      PixieClearCanvasRect(Ctx.Canvas, Ctx.Width, Ctx.Height,
        OffsetX, OffsetY, W, H);
    cApngDisposePrevious:
      PixieRestoreCanvas(Ctx.Canvas, Ctx.PrevCanvas);
  end;
end;

// ---------------------------------------------------------------------------
// Per-frame decode (inflate + unfilter + colour-convert)
// ---------------------------------------------------------------------------

function DecodeFrameToBgra(const Ctx: TPixieApngContext;
  const Comp: TBytes; W, H: Integer; out Bgra: TBytes): Boolean;
var
  Channels, Bpp, RowBytes, RawSize: Integer;
  Raw, Recon, Plane: TBytes;
begin
  Result := False;
  SetLength(Bgra, 0);
  if (W <= 0) or (H <= 0) then Exit;

  case Ctx.ColorType of
    cPngColorGray, cPngColorPalette: Channels := 1;
    cPngColorRgb:                    Channels := 3;
    cPngColorGrayAlpha:              Channels := 2;
    cPngColorRgba:                   Channels := 4;
  else
    Exit;
  end;

  // For filter calculations, sub-8-bit channels round bpp up to 1.
  Bpp := Max(1, (Channels * Ctx.BitDepth + 7) div 8);
  RowBytes := (W * Channels * Ctx.BitDepth + 7) div 8;
  RawSize := (RowBytes + 1) * H;

  if not PixieInflateZlib(Comp, Raw, RawSize) then Exit;
  if not UnfilterScanlines(Raw, H, RowBytes, Bpp, Recon) then Exit;

  if (Ctx.BitDepth < 8) and
     ((Ctx.ColorType = cPngColorGray) or (Ctx.ColorType = cPngColorPalette)) then
    UnpackSubByteScanlines(Recon, H, W, Ctx.BitDepth, Plane)
  else
    Plane := Recon;

  Result := DecodedPlaneToBgra(Ctx, Plane, W, H, Bgra);
end;

// ---------------------------------------------------------------------------
// Chunk-handler helpers
// ---------------------------------------------------------------------------

procedure ParseIhdr(var Ctx: TPixieApngContext; const Payload: TBytes;
  out Ok: Boolean);
begin
  Ok := False;
  if Length(Payload) < 13 then Exit;
  Ctx.Width := Integer(ReadU32BeFromBuf(Payload, 0));
  Ctx.Height := Integer(ReadU32BeFromBuf(Payload, 4));
  Ctx.BitDepth := Payload[8];
  Ctx.ColorType := Payload[9];
  Ctx.Interlace := Payload[12];
  if (Ctx.Width <= 0) or (Ctx.Height <= 0) then Exit;
  if Ctx.Interlace <> 0 then Exit;     // Adam7 not supported
  case Ctx.ColorType of
    cPngColorGray:
      if not (Ctx.BitDepth in [1, 2, 4, 8, 16]) then Exit;
    cPngColorRgb, cPngColorGrayAlpha, cPngColorRgba:
      if not (Ctx.BitDepth in [8, 16]) then Exit;
    cPngColorPalette:
      if not (Ctx.BitDepth in [1, 2, 4, 8]) then Exit;
  else
    Exit;
  end;
  Ok := True;
end;

procedure ParsePlte(var Ctx: TPixieApngContext; const Payload: TBytes);
var
  Count, I: Integer;
begin
  Count := Length(Payload) div 3;
  if Count > 256 then Count := 256;
  for I := 0 to Count - 1 do
  begin
    Ctx.Palette[I].R := Payload[I * 3];
    Ctx.Palette[I].G := Payload[I * 3 + 1];
    Ctx.Palette[I].B := Payload[I * 3 + 2];
    Ctx.Palette[I].A := $FF;
  end;
  Ctx.PaletteCount := Count;
  Ctx.HasPalette := True;
end;

procedure ParseTrns(var Ctx: TPixieApngContext; const Payload: TBytes);
var
  Count, I: Integer;
begin
  case Ctx.ColorType of
    cPngColorPalette:
    begin
      Count := Min(Length(Payload), Ctx.PaletteCount);
      for I := 0 to Count - 1 do
        Ctx.Palette[I].A := Payload[I];
    end;
    cPngColorGray:
    begin
      if Length(Payload) >= 2 then
      begin
        Ctx.HasGrayTrns := True;
        Ctx.GrayTrns := ReadU16Be(Payload, 0);
      end;
    end;
    cPngColorRgb:
    begin
      if Length(Payload) >= 6 then
      begin
        Ctx.HasRgbTrns := True;
        Ctx.RgbTrnsR := ReadU16Be(Payload, 0);
        Ctx.RgbTrnsG := ReadU16Be(Payload, 2);
        Ctx.RgbTrnsB := ReadU16Be(Payload, 4);
      end;
    end;
  end;
end;

procedure ParseFctl(const Payload: TBytes; out Frame: TPixieApngFrameCtl;
  out Ok: Boolean);
var
  DelayNum, DelayDen, Denom: Word;
begin
  Ok := False;
  FillChar(Frame, SizeOf(Frame), 0);
  if Length(Payload) < 26 then Exit;
  // bytes 0..3: sequence_number (ignored)
  Frame.Width := Integer(ReadU32BeFromBuf(Payload, 4));
  Frame.Height := Integer(ReadU32BeFromBuf(Payload, 8));
  Frame.OffsetX := Integer(ReadU32BeFromBuf(Payload, 12));
  Frame.OffsetY := Integer(ReadU32BeFromBuf(Payload, 16));
  DelayNum := ReadU16Be(Payload, 20);
  DelayDen := ReadU16Be(Payload, 22);
  if DelayDen = 0 then Denom := 100 else Denom := DelayDen;
  Frame.DelayMs := (Integer(DelayNum) * 1000) div Integer(Denom);
  Frame.DisposeOp := Payload[24];
  Frame.BlendOp := Payload[25];
  if (Frame.Width <= 0) or (Frame.Height <= 0) then Exit;
  Ok := True;
end;

// Frame 0 with DisposeOp = PREVIOUS is treated as DisposeOp =
// BACKGROUND per APNG spec.
function FlushFrame(var Ctx: TPixieApngContext;
  const Comp: TBytes; CompLen: Integer;
  const FrameCtl: TPixieApngFrameCtl;
  IsFirstFrame: Boolean; var Frames: TPixieRawAnimFrameArray): Boolean;
var
  CompSlice: TBytes;
  SubBgra: TBytes;
  EffectiveDispose: Byte;
begin
  Result := False;
  if (FrameCtl.OffsetX < 0) or (FrameCtl.OffsetY < 0) then Exit;
  if FrameCtl.OffsetX + FrameCtl.Width > Ctx.Width then Exit;
  if FrameCtl.OffsetY + FrameCtl.Height > Ctx.Height then Exit;
  if CompLen <= 0 then Exit;

  SetLength(CompSlice, CompLen);
  Move(Comp[0], CompSlice[0], CompLen);

  if not DecodeFrameToBgra(Ctx, CompSlice,
    FrameCtl.Width, FrameCtl.Height, SubBgra) then Exit;

  EffectiveDispose := FrameCtl.DisposeOp;
  if IsFirstFrame and (EffectiveDispose = cApngDisposePrevious) then
    EffectiveDispose := cApngDisposeBackground;

  if EffectiveDispose = cApngDisposePrevious then
    PixieSnapshotCanvas(Ctx.Canvas, Ctx.PrevCanvas);

  CompositeFrame(Ctx, SubBgra, FrameCtl.OffsetX, FrameCtl.OffsetY,
    FrameCtl.Width, FrameCtl.Height, FrameCtl.BlendOp);

  PixieEmitFrame(Ctx.Canvas, FrameCtl.DelayMs, Frames);

  ApplyDispose(Ctx, FrameCtl.OffsetX, FrameCtl.OffsetY,
    FrameCtl.Width, FrameCtl.Height, EffectiveDispose);

  Result := True;
end;

// ---------------------------------------------------------------------------
// Public entry points
// ---------------------------------------------------------------------------

function PixieIsApngStream(Stream: TStream): Boolean;
var
  StartPos: Int64;
  Sig: array[0..7] of Byte;
  ChunkType: array[0..3] of Byte;
  Len: LongWord;
  ChunkCount: Integer;
  I: Integer;
begin
  Result := False;
  if Stream = nil then Exit;
  StartPos := Stream.Position;
  try
    if Stream.Read(Sig, 8) <> 8 then Exit;
    for I := 0 to 7 do
      if Sig[I] <> cPngSignature[I] then Exit;

    ChunkCount := 0;
    while ChunkCount < cApngSniffMaxChunks do
    begin
      if not ReadU32Be(Stream, Len) then Exit;
      if Stream.Read(ChunkType, 4) <> 4 then Exit;
      if MatchesType(ChunkType, 'a', 'c', 'T', 'L') then
      begin
        Result := True;
        Exit;
      end;
      if MatchesType(ChunkType, 'I', 'D', 'A', 'T')
        or MatchesType(ChunkType, 'I', 'E', 'N', 'D') then Exit;
      // Seek past payload + 4-byte CRC
      Stream.Seek(Int64(Len) + 4, soCurrent);
      Inc(ChunkCount);
    end;
  finally
    Stream.Position := StartPos;
  end;
end;

function PixieDecodeApng(Stream: TStream;
  out Data: TPixieRawAnimation): Boolean;
var
  Ctx: TPixieApngContext;
  StartPos: Int64;
  Len: LongWord;
  ChunkType: array[0..3] of Byte;
  Payload: TBytes;
  CompBuf: TBytesStream;
  PendingFrame: TPixieApngFrameCtl;
  HavePendingFrame: Boolean;
  IsFirstFrame: Boolean;
  SeenIdat: Boolean;
  HaveActl: Boolean;
  NumFramesDeclared: LongWord;
  TmpFrame: TPixieApngFrameCtl;
  Ok: Boolean;
  Frames: TPixieRawAnimFrameArray;
  CanvasBytes: Int64;
begin
  Result := False;
  Data.Width := 0;
  Data.Height := 0;
  Data.Loops := 0;
  SetLength(Data.Frames, 0);

  if Stream = nil then Exit;
  StartPos := Stream.Position;

  if not ReadSignature(Stream) then
  begin
    Stream.Position := StartPos;
    Exit;
  end;

  FillChar(Ctx, SizeOf(Ctx), 0);
  FillChar(PendingFrame, SizeOf(PendingFrame), 0);
  FillChar(TmpFrame, SizeOf(TmpFrame), 0);
  HavePendingFrame := False;
  IsFirstFrame := True;
  SeenIdat := False;
  HaveActl := False;
  NumFramesDeclared := 0;
  SetLength(Frames, 0);

  CompBuf := TBytesStream.Create;
  try
    while True do
    begin
      if not ReadU32Be(Stream, Len) then Break;
      if Stream.Read(ChunkType, 4) <> 4 then Break;
      SetLength(Payload, Len);
      if Len > 0 then
        if LongWord(Stream.Read(Payload[0], Len)) <> Len then Break;

      if MatchesType(ChunkType, 'I', 'H', 'D', 'R') then
      begin
        ParseIhdr(Ctx, Payload, Ok);
        if not Ok then Exit;
        CanvasBytes := Int64(Ctx.Width) * Int64(Ctx.Height) * 4;
        if CanvasBytes > High(Integer) then Exit;
        SetLength(Ctx.Canvas, Integer(CanvasBytes));
        FillChar(Ctx.Canvas[0], Length(Ctx.Canvas), 0);
      end
      else if MatchesType(ChunkType, 'P', 'L', 'T', 'E') then
        ParsePlte(Ctx, Payload)
      else if MatchesType(ChunkType, 't', 'R', 'N', 'S') then
        ParseTrns(Ctx, Payload)
      else if MatchesType(ChunkType, 'a', 'c', 'T', 'L') then
      begin
        if Length(Payload) < 8 then Exit;
        NumFramesDeclared := ReadU32BeFromBuf(Payload, 0);
        Ctx.NumPlays := Integer(ReadU32BeFromBuf(Payload, 4));
        HaveActl := True;
      end
      else if MatchesType(ChunkType, 'f', 'c', 'T', 'L') then
      begin
        if HavePendingFrame then
        begin
          if not FlushFrame(Ctx, CompBuf.Bytes, Integer(CompBuf.Size),
            PendingFrame, IsFirstFrame, Frames) then Exit;
          IsFirstFrame := False;
          HavePendingFrame := False;
          CompBuf.Size := 0;
        end;
        ParseFctl(Payload, TmpFrame, Ok);
        if not Ok then Exit;
        PendingFrame := TmpFrame;
        HavePendingFrame := True;
        if not SeenIdat then
          Ctx.FirstFrameIsDefault := True;
      end
      else if MatchesType(ChunkType, 'I', 'D', 'A', 'T') then
      begin
        SeenIdat := True;
        // IDAT bytes belong to the first animated frame only when fcTL
        // came first; otherwise they describe the static fallback that
        // non-APNG viewers see, and we discard them.
        if HavePendingFrame and Ctx.FirstFrameIsDefault
          and (Length(Payload) > 0) then
          CompBuf.WriteBuffer(Payload[0], Length(Payload));
      end
      else if MatchesType(ChunkType, 'f', 'd', 'A', 'T') then
      begin
        // First 4 bytes are sequence_number; payload follows.
        if HavePendingFrame and (Length(Payload) > 4) then
          CompBuf.WriteBuffer(Payload[4], Length(Payload) - 4);
      end
      else if MatchesType(ChunkType, 'I', 'E', 'N', 'D') then
      begin
        if HavePendingFrame then
        begin
          if not FlushFrame(Ctx, CompBuf.Bytes, Integer(CompBuf.Size),
            PendingFrame, IsFirstFrame, Frames) then Exit;
          HavePendingFrame := False;
        end;
        Break;
      end;

      Stream.Seek(4, soCurrent);  // CRC
    end;
  finally
    CompBuf.Free;
  end;

  if not HaveActl then Exit;
  if Length(Frames) = 0 then Exit;
  if (NumFramesDeclared > 0)
    and (LongWord(Length(Frames)) > NumFramesDeclared) then
    SetLength(Frames, NumFramesDeclared);

  Data.Width := Ctx.Width;
  Data.Height := Ctx.Height;
  Data.Loops := Ctx.NumPlays;
  Data.Frames := Frames;
  Result := True;
end;

end.
