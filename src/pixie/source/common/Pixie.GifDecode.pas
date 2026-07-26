unit Pixie.GifDecode;

// Pure-Pascal GIF87a / GIF89a decoder. Produces a list of fully-composited
// BGRA frames (full canvas size) with per-frame delay-ms and a Netscape
// loop count. Disposal modes 0/1/2/3, local + global palettes, transparency,
// and 4-pass interlace are all handled at decode time so callers see a
// sequence of independent frames ready to upload as platform bitmaps.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes,
  Pixie.AnimatedImage;

// Decode a GIF stream. Returns False if the stream isn't a valid GIF or
// decoding fails before any frame is produced. On True, Data.Frames is
// populated with at least one frame.
function PixieDecodeGif(Stream: TStream;
  out Data: TPixieRawAnimation): Boolean;

// Cheap 6-byte magic peek. Restores stream position before returning so
// callers can immediately fall through to other decoders on a miss.
function PixieIsGifStream(Stream: TStream): Boolean;

implementation

const
  // LZW limits (12-bit codes, 4096-entry dictionary)
  cGifMaxCodeSize = 12;
  cGifMaxDictSize = 1 shl cGifMaxCodeSize;

  // Top-level block introducers
  cGifBlockImageDescriptor = $2C;
  cGifBlockExtension       = $21;
  cGifBlockTrailer         = $3B;

  // Extension labels
  cGifExtGraphicControl    = $F9;
  cGifExtApplication       = $FF;

  // Logical Screen Descriptor packed flags
  cGifMaskGlobalPalette    = $80;
  cGifMaskPaletteSize      = $07;

  // Image Descriptor packed flags
  cGifMaskLocalPalette     = $80;
  cGifMaskInterlace        = $40;

  // GCE packed flags
  cGifMaskTransparent      = $01;

type
  TPixiePaletteEntry = record
    R, G, B: Byte;
  end;
  TPixiePalette = array[0..255] of TPixiePaletteEntry;

  TPixieGifContext = record
    Stream: TStream;
    Width, Height: Integer;
    HasGlobalPalette: Boolean;
    GlobalPalette: TPixiePalette;
    Loops: Integer;
    Canvas: TBytes;          // running displayed frame (BGRA)
    PrevCanvas: TBytes;      // snapshot for disposal-mode-3
    PendingDelayMs: Integer;
    PendingDisposal: Integer;
    PendingTransparent: Integer;   // -1 = none
    PendingHasGce: Boolean;
  end;

// ---------------------------------------------------------------------------
// Stream helpers
// ---------------------------------------------------------------------------

function ReadByte(Stream: TStream; out B: Byte): Boolean;
begin
  B := 0;
  Result := Stream.Read(B, 1) = 1;
end;

function ReadWord(Stream: TStream; out W: Word): Boolean;
var
  Lo, Hi: Byte;
begin
  Result := ReadByte(Stream, Lo) and ReadByte(Stream, Hi);
  if Result then
    W := Lo or (Hi shl 8);
end;

function ReadSubBlocks(Stream: TStream; out Buf: TBytes): Integer;
var
  Size: Byte;
begin
  Result := 0;
  SetLength(Buf, 0);
  while ReadByte(Stream, Size) and (Size > 0) do
  begin
    SetLength(Buf, Result + Size);
    if Stream.Read(Buf[Result], Size) <> Size then Exit;
    Inc(Result, Size);
  end;
end;

procedure SkipSubBlocks(Stream: TStream);
var
  Size: Byte;
begin
  while ReadByte(Stream, Size) and (Size > 0) do
    Stream.Seek(Size, soCurrent);
end;

function ReadPalette(Stream: TStream; Size: Integer;
  out Pal: TPixiePalette): Boolean;
var
  I: Integer;
  Triplet: array[0..2] of Byte;
begin
  Result := True;
  FillChar(Triplet, SizeOf(Triplet), 0);
  for I := 0 to Size - 1 do
  begin
    if Stream.Read(Triplet, 3) <> 3 then
    begin
      Result := False;
      Exit;
    end;
    Pal[I].R := Triplet[0];
    Pal[I].G := Triplet[1];
    Pal[I].B := Triplet[2];
  end;
end;

// ---------------------------------------------------------------------------
// LZW decoder
// ---------------------------------------------------------------------------

type
  TLzwEntry = record
    Prefix: Integer;
    Suffix: Byte;
    First: Byte;
    Len: Integer;
  end;
  TLzwDict = array[0..cGifMaxDictSize - 1] of TLzwEntry;
  TLzwStack = array[0..cGifMaxDictSize - 1] of Byte;

// Walk Dict[StartCode] prefix chain into Stack and return its length.
// FirstChar receives the first character of the emitted string.
procedure EmitDictString(const Dict: TLzwDict; StartCode: Integer;
  var Stack: TLzwStack; out Len: Integer; out FirstChar: Byte);
var
  I, StackIdx: Integer;
begin
  Len := Dict[StartCode].Len;
  StackIdx := Len;
  I := StartCode;
  while I >= 0 do
  begin
    Dec(StackIdx);
    Stack[StackIdx] := Dict[I].Suffix;
    I := Dict[I].Prefix;
  end;
  FirstChar := Dict[StartCode].First;
end;

function DecodeLzw(const CompData: TBytes; MinCodeSize: Integer;
  OutPixels: PByte; PixelCount: Integer): Boolean;
var
  Dict: TLzwDict;
  Stack: TLzwStack;
  ClearCode, EoiCode, NextCode: Integer;
  CodeSize, BitBuffer, BitCount: Integer;
  PrevCode, Code, EntryLen: Integer;
  FirstChar: Byte;
  CompIdx, CompLen: Integer;
  OutIdx, I: Integer;
  DictEntry: ^TLzwEntry;
begin
  Result := False;
  if (MinCodeSize < 2) or (MinCodeSize > 8) then Exit;

  ClearCode := 1 shl MinCodeSize;
  EoiCode := ClearCode + 1;
  CodeSize := MinCodeSize + 1;
  NextCode := EoiCode + 1;

  for I := 0 to ClearCode - 1 do
  begin
    Dict[I].Prefix := -1;
    Dict[I].Suffix := Byte(I);
    Dict[I].First := Byte(I);
    Dict[I].Len := 1;
  end;

  BitBuffer := 0;
  BitCount := 0;
  CompIdx := 0;
  CompLen := Length(CompData);
  OutIdx := 0;
  PrevCode := -1;

  while True do
  begin
    while BitCount < CodeSize do
    begin
      if CompIdx >= CompLen then Exit;
      BitBuffer := BitBuffer or (CompData[CompIdx] shl BitCount);
      Inc(CompIdx);
      Inc(BitCount, 8);
    end;

    Code := BitBuffer and ((1 shl CodeSize) - 1);
    BitBuffer := BitBuffer shr CodeSize;
    Dec(BitCount, CodeSize);

    if Code = ClearCode then
    begin
      CodeSize := MinCodeSize + 1;
      NextCode := EoiCode + 1;
      PrevCode := -1;
      Continue;
    end;

    if Code = EoiCode then
    begin
      Result := OutIdx > 0;
      Exit;
    end;

    if Code < NextCode then
      EmitDictString(Dict, Code, Stack, EntryLen, FirstChar)
    else if Code = NextCode then
    begin
      // KwKwK: prev string + first-char-of-prev
      if PrevCode < 0 then Exit;
      EmitDictString(Dict, PrevCode, Stack, EntryLen, FirstChar);
      Stack[EntryLen] := FirstChar;
      Inc(EntryLen);
    end
    else
      Exit;

    if OutIdx + EntryLen > PixelCount then
      EntryLen := PixelCount - OutIdx;
    for I := 0 to EntryLen - 1 do
    begin
      OutPixels[OutIdx] := Stack[I];
      Inc(OutIdx);
    end;
    if OutIdx >= PixelCount then
    begin
      Result := True;
      Exit;
    end;

    if (PrevCode >= 0) and (NextCode < cGifMaxDictSize) then
    begin
      DictEntry := @Dict[NextCode];
      DictEntry.Prefix := PrevCode;
      DictEntry.Suffix := FirstChar;
      DictEntry.First := Dict[PrevCode].First;
      DictEntry.Len := Dict[PrevCode].Len + 1;
      Inc(NextCode);
      if (NextCode = (1 shl CodeSize)) and (CodeSize < cGifMaxCodeSize) then
        Inc(CodeSize);
    end;

    PrevCode := Code;
  end;
end;

// ---------------------------------------------------------------------------
// Interlace de-interleaver
// ---------------------------------------------------------------------------

type
  TPixieGifRowMap = array of Integer;

procedure DeinterlaceRowMap(H: Integer; out Map: TPixieGifRowMap);
var
  Y, Dst: Integer;
begin
  SetLength(Map, H);
  Dst := 0;
  Y := 0;
  while Y < H do begin Map[Dst] := Y; Inc(Dst); Inc(Y, 8); end;
  Y := 4;
  while Y < H do begin Map[Dst] := Y; Inc(Dst); Inc(Y, 8); end;
  Y := 2;
  while Y < H do begin Map[Dst] := Y; Inc(Dst); Inc(Y, 4); end;
  Y := 1;
  while Y < H do begin Map[Dst] := Y; Inc(Dst); Inc(Y, 2); end;
end;

// ---------------------------------------------------------------------------
// Frame composition
// ---------------------------------------------------------------------------

procedure CompositeFrame(var Ctx: TPixieGifContext;
  const Indices: TBytes; Left, Top, W, H: Integer;
  const Palette: TPixiePalette; Transparent: Integer; Interlaced: Boolean);
var
  RowMap: TPixieGifRowMap;
  Row, Col, SrcRow, DstRow, DstX, DstY, Idx: Integer;
  PalIdx: Byte;
  Entry: TPixiePaletteEntry;
begin
  if Interlaced then
    DeinterlaceRowMap(H, RowMap)
  else
  begin
    SetLength(RowMap, H);
    for Row := 0 to H - 1 do RowMap[Row] := Row;
  end;

  for SrcRow := 0 to H - 1 do
  begin
    DstRow := RowMap[SrcRow];
    DstY := Top + DstRow;
    if (DstY < 0) or (DstY >= Ctx.Height) then Continue;
    for Col := 0 to W - 1 do
    begin
      PalIdx := Indices[SrcRow * W + Col];
      if (Transparent >= 0) and (PalIdx = Byte(Transparent)) then Continue;
      DstX := Left + Col;
      if (DstX < 0) or (DstX >= Ctx.Width) then Continue;
      Idx := (DstY * Ctx.Width + DstX) * 4;
      Entry := Palette[PalIdx];
      Ctx.Canvas[Idx]     := Entry.B;
      Ctx.Canvas[Idx + 1] := Entry.G;
      Ctx.Canvas[Idx + 2] := Entry.R;
      Ctx.Canvas[Idx + 3] := $FF;
    end;
  end;
end;

procedure ApplyDisposal(var Ctx: TPixieGifContext; Disposal: Integer;
  Left, Top, W, H: Integer);
begin
  // Browsers treat GIF disposal-2's "background" as transparent
  // regardless of bgColorIndex (which is largely a display-list
  // concept).
  case Disposal of
    2: PixieClearCanvasRect(Ctx.Canvas, Ctx.Width, Ctx.Height,
         Left, Top, W, H);
    3: PixieRestoreCanvas(Ctx.Canvas, Ctx.PrevCanvas);
  end;
end;

// ---------------------------------------------------------------------------
// Block parsers
// ---------------------------------------------------------------------------

// Reads the leading sub-block size and validates it matches Expected. On
// mismatch consumes the body and any trailing sub-blocks to keep the
// stream aligned, then returns False.
function ExpectFixedBlock(Stream: TStream; Expected: Integer): Boolean;
var
  Size: Byte;
begin
  Result := False;
  if not ReadByte(Stream, Size) then Exit;
  if Size <> Expected then
  begin
    Stream.Seek(Size, soCurrent);
    SkipSubBlocks(Stream);
    Exit;
  end;
  Result := True;
end;

procedure ParseGraphicControlExt(var Ctx: TPixieGifContext);
var
  Block: array[0..3] of Byte;
  Terminator: Byte;
  Flags: Byte;
  DelayUnits: Word;
begin
  if not ExpectFixedBlock(Ctx.Stream, 4) then Exit;
  FillChar(Block, SizeOf(Block), 0);
  if Ctx.Stream.Read(Block, 4) <> 4 then Exit;
  if not ReadByte(Ctx.Stream, Terminator) then Exit;

  Flags := Block[0];
  DelayUnits := Block[1] or (Block[2] shl 8);

  Ctx.PendingHasGce := True;
  Ctx.PendingDisposal := (Flags shr 2) and $07;
  Ctx.PendingDelayMs := Integer(DelayUnits) * 10;
  if (Flags and cGifMaskTransparent) <> 0 then
    Ctx.PendingTransparent := Block[3]
  else
    Ctx.PendingTransparent := -1;
end;

const
  cNetscapeIdent: array[0..10] of AnsiChar = 'NETSCAPE2.0';

procedure ParseApplicationExt(var Ctx: TPixieGifContext);
var
  Ident: array[0..10] of Byte;
  Sub: Byte;
  Body: array[0..2] of Byte;
begin
  if not ExpectFixedBlock(Ctx.Stream, 11) then Exit;
  FillChar(Ident, SizeOf(Ident), 0);
  if Ctx.Stream.Read(Ident, 11) <> 11 then Exit;

  if CompareMem(@Ident[0], @cNetscapeIdent[0], 11) then
  begin
    // Netscape sub-blocks; loop count lives in {3, 1, lo, hi}
    FillChar(Body, SizeOf(Body), 0);
    while ReadByte(Ctx.Stream, Sub) and (Sub > 0) do
    begin
      if Sub = 3 then
      begin
        if Ctx.Stream.Read(Body, 3) <> 3 then Exit;
        if Body[0] = 1 then
          Ctx.Loops := Body[1] or (Body[2] shl 8);
      end
      else
        Ctx.Stream.Seek(Sub, soCurrent);
    end;
    Exit;
  end;

  SkipSubBlocks(Ctx.Stream);
end;

procedure ParseExtension(var Ctx: TPixieGifContext);
var
  Label_: Byte;
begin
  if not ReadByte(Ctx.Stream, Label_) then Exit;
  case Label_ of
    cGifExtGraphicControl: ParseGraphicControlExt(Ctx);
    cGifExtApplication:    ParseApplicationExt(Ctx);
  else
    // Plain text ($01), Comment ($FE), other — skip body
    SkipSubBlocks(Ctx.Stream);
  end;
end;

function ParseImageDescriptor(var Ctx: TPixieGifContext;
  var Frames: TPixieRawAnimFrameArray): Boolean;
var
  Left, Top, ImgW, ImgH: Word;
  Flags, MinCodeSize: Byte;
  HasLocal, Interlaced: Boolean;
  LocalSize: Integer;
  ActivePalette: TPixiePalette;
  CompData, Indices: TBytes;
  Disposal, Transparent: Integer;
begin
  Result := False;
  if not ReadWord(Ctx.Stream, Left) then Exit;
  if not ReadWord(Ctx.Stream, Top) then Exit;
  if not ReadWord(Ctx.Stream, ImgW) then Exit;
  if not ReadWord(Ctx.Stream, ImgH) then Exit;
  if not ReadByte(Ctx.Stream, Flags) then Exit;
  if (ImgW = 0) or (ImgH = 0) then
  begin
    // Empty frame — still consume LZW data so the stream stays aligned
    if not ReadByte(Ctx.Stream, MinCodeSize) then Exit;
    SkipSubBlocks(Ctx.Stream);
    Result := True;
    Exit;
  end;

  HasLocal := (Flags and cGifMaskLocalPalette) <> 0;
  Interlaced := (Flags and cGifMaskInterlace) <> 0;
  LocalSize := 1 shl ((Flags and cGifMaskPaletteSize) + 1);

  if HasLocal then
  begin
    if not ReadPalette(Ctx.Stream, LocalSize, ActivePalette) then Exit;
  end
  else
  begin
    if not Ctx.HasGlobalPalette then Exit;
    ActivePalette := Ctx.GlobalPalette;
  end;

  if not ReadByte(Ctx.Stream, MinCodeSize) then Exit;
  ReadSubBlocks(Ctx.Stream, CompData);

  SetLength(Indices, ImgW * ImgH);
  if not DecodeLzw(CompData, MinCodeSize, @Indices[0], ImgW * ImgH) then
    Exit;

  if Ctx.PendingHasGce then
  begin
    Disposal := Ctx.PendingDisposal;
    Transparent := Ctx.PendingTransparent;
  end
  else
  begin
    Disposal := 0;
    Transparent := -1;
  end;

  if Disposal = 3 then
    PixieSnapshotCanvas(Ctx.Canvas, Ctx.PrevCanvas);

  CompositeFrame(Ctx, Indices, Left, Top, ImgW, ImgH,
    ActivePalette, Transparent, Interlaced);

  if Ctx.PendingHasGce then
    PixieEmitFrame(Ctx.Canvas, Ctx.PendingDelayMs, Frames)
  else
    PixieEmitFrame(Ctx.Canvas, 0, Frames);

  ApplyDisposal(Ctx, Disposal, Left, Top, ImgW, ImgH);

  Ctx.PendingHasGce := False;
  Ctx.PendingDelayMs := 0;
  Ctx.PendingDisposal := 0;
  Ctx.PendingTransparent := -1;

  Result := True;
end;

// ---------------------------------------------------------------------------
// Public entry points
// ---------------------------------------------------------------------------

function PixieIsGifStream(Stream: TStream): Boolean;
var
  Header: array[0..5] of Byte;
  StartPos: Int64;
begin
  Result := False;
  if Stream = nil then Exit;
  StartPos := Stream.Position;
  FillChar(Header, SizeOf(Header), 0);
  try
    if Stream.Read(Header, 6) <> 6 then Exit;
    Result :=
      (Header[0] = Ord('G')) and (Header[1] = Ord('I')) and
      (Header[2] = Ord('F')) and (Header[3] = Ord('8')) and
      ((Header[4] = Ord('7')) or (Header[4] = Ord('9'))) and
      (Header[5] = Ord('a'));
  finally
    Stream.Position := StartPos;
  end;
end;

function PixieDecodeGif(Stream: TStream;
  out Data: TPixieRawAnimation): Boolean;
var
  Ctx: TPixieGifContext;
  Header: array[0..5] of Byte;
  LsdW, LsdH: Word;
  Packed_, BgIdx, AspectRatio: Byte;
  GlobalSize: Integer;
  Block: Byte;
  Frames: TPixieRawAnimFrameArray;
  StartPos: Int64;
begin
  Result := False;
  Data.Width := 0;
  Data.Height := 0;
  Data.Loops := 0;
  SetLength(Data.Frames, 0);

  if Stream = nil then Exit;
  StartPos := Stream.Position;

  FillChar(Header, SizeOf(Header), 0);
  if Stream.Read(Header, 6) <> 6 then Exit;
  if (Header[0] <> Ord('G')) or (Header[1] <> Ord('I')) or
     (Header[2] <> Ord('F')) or (Header[3] <> Ord('8')) or
     ((Header[4] <> Ord('7')) and (Header[4] <> Ord('9'))) or
     (Header[5] <> Ord('a')) then
  begin
    Stream.Position := StartPos;
    Exit;
  end;

  if not ReadWord(Stream, LsdW) then Exit;
  if not ReadWord(Stream, LsdH) then Exit;
  if not ReadByte(Stream, Packed_) then Exit;
  if not ReadByte(Stream, BgIdx) then Exit;
  if not ReadByte(Stream, AspectRatio) then Exit;

  FillChar(Ctx, SizeOf(Ctx), 0);
  Ctx.Stream := Stream;
  Ctx.Width := LsdW;
  Ctx.Height := LsdH;
  Ctx.Loops := 1;
  Ctx.PendingTransparent := -1;

  if (Packed_ and cGifMaskGlobalPalette) <> 0 then
  begin
    GlobalSize := 1 shl ((Packed_ and cGifMaskPaletteSize) + 1);
    if not ReadPalette(Stream, GlobalSize, Ctx.GlobalPalette) then Exit;
    Ctx.HasGlobalPalette := True;
  end;

  if (Ctx.Width <= 0) or (Ctx.Height <= 0) then Exit;
  SetLength(Ctx.Canvas, Ctx.Width * Ctx.Height * 4);
  FillChar(Ctx.Canvas[0], Length(Ctx.Canvas), 0);

  SetLength(Frames, 0);

  while ReadByte(Stream, Block) do
  begin
    case Block of
      cGifBlockImageDescriptor:
        if not ParseImageDescriptor(Ctx, Frames) then Break;
      cGifBlockExtension:
        ParseExtension(Ctx);
      cGifBlockTrailer:
        Break;
      $00:
        ; // benign filler some encoders emit
    else
      Break;
    end;
  end;

  if Length(Frames) = 0 then Exit;

  Data.Width := Ctx.Width;
  Data.Height := Ctx.Height;
  Data.Loops := Ctx.Loops;
  Data.Frames := Frames;
  Result := True;
end;

end.
