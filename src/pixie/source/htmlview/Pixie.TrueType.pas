unit Pixie.TrueType;

// TrueType font file parser for PDF export.
// Reads .ttf files, extracts metrics, character-to-glyph mapping, and
// advance widths needed for PDF text measurement and font embedding.
// Also provides platform font file discovery (Windows registry, Linux/macOS paths).

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections;

type
  TPixieGlyphIdSet = TDictionary<UInt16, Boolean>;
  TPixieGlyphMap = TDictionary<UInt16, UInt32>;

  { TPixieTrueTypeFont }

  TPixieTrueTypeFont = class
  private
    FData: TBytes;
    FUnitsPerEm: UInt16;
    FAscent: Int16;
    FDescent: Int16;
    FLineGap: Int16;
    FCapHeight: Int16;
    FXHeight: Int16;
    FWeightClass: UInt16;
    FItalicAngle: Single;
    FBBoxXMin: Int16;
    FBBoxYMin: Int16;
    FBBoxXMax: Int16;
    FBBoxYMax: Int16;
    FNumGlyphs: UInt16;
    FNumberOfHMetrics: UInt16;
    FFamilyName: string;
    FPostScriptName: string;
    FFsSelection: UInt16;

    // Offset to the table directory (0 for plain TTF, font offset for TTC)
    FTableBase: UInt32;

    // Table offsets and lengths
    FCmapOffset: UInt32;
    FCmapLength: UInt32;
    FHmtxOffset: UInt32;
    FHmtxLength: UInt32;
    FLocaOffset: UInt32;
    FLocaLength: UInt32;
    FGlyfOffset: UInt32;
    FGlyfLength: UInt32;
    FIndexToLocFormat: Int16;

    // cmap subtable offsets (relative to start of file)
    FCmapFmt4Offset: UInt32;
    FCmapFmt12Offset: UInt32;

    function ReadU16(Offset: UInt32): UInt16;
    function ReadI16(Offset: UInt32): Int16;
    function ReadU32(Offset: UInt32): UInt32;
    function ReadFixed(Offset: UInt32): Single;
    function FindTable(const Tag: AnsiString;
      out TblOffset, TblLength: UInt32): Boolean;
    function ParseHead: Boolean;
    function ParseHhea: Boolean;
    function ParseMaxp: Boolean;
    function ParseOS2: Boolean;
    function ParseName: Boolean;
    function ParsePost: Boolean;
    function ParseCmap: Boolean;
    function CharToGlyphFmt4(Codepoint: UInt32): UInt16;
    function CharToGlyphFmt12(Codepoint: UInt32): UInt16;
    function GetGlyphDataRange(GlyphId: UInt16;
      out GlyfOff, GlyfLen: UInt32): Boolean;
    procedure CollectCompositeGlyphs(GlyphId: UInt16;
      GlyphSet: TPixieGlyphIdSet; Depth: Integer);
    procedure WriteU16BE(Stream: TMemoryStream; V: UInt16);
    procedure WriteU32BE(Stream: TMemoryStream; V: UInt32);
    function CalcTableChecksum(const Data: TBytes;
      Offset, Len: UInt32): UInt32;
    function BuildSubsetCmap(UsedGlyphs: TPixieGlyphMap): TBytes;
    function AssembleTtfFile(const Tables: array of AnsiString;
      const TableData: array of TBytes): TBytes;
  public
    constructor Create;
    destructor Destroy; override;

    function LoadFromFile(const FileName: string): Boolean;
    function LoadFromStream(Stream: TStream): Boolean;

    function CharToGlyph(Codepoint: UInt32): UInt16;
    function HasGlyphOutline(GlyphId: UInt16): Boolean;
    function GetGlyphWidth(GlyphId: UInt16): UInt16;
    function GetFullData: TBytes;
    function BuildSubsetFont(UsedGlyphs: TPixieGlyphMap): TBytes;

    property UnitsPerEm: UInt16 read FUnitsPerEm;
    property Ascent: Int16 read FAscent;
    property Descent: Int16 read FDescent;
    property LineGap: Int16 read FLineGap;
    property CapHeight: Int16 read FCapHeight;
    property XHeight: Int16 read FXHeight;
    property WeightClass: UInt16 read FWeightClass;
    property ItalicAngle: Single read FItalicAngle;
    property BBoxXMin: Int16 read FBBoxXMin;
    property BBoxYMin: Int16 read FBBoxYMin;
    property BBoxXMax: Int16 read FBBoxXMax;
    property BBoxYMax: Int16 read FBBoxYMax;
    property NumGlyphs: UInt16 read FNumGlyphs;
    property FamilyName: string read FFamilyName;
    property PostScriptName: string read FPostScriptName;
    property FsSelection: UInt16 read FFsSelection;
  end;

  TPixieTrueTypeFontCache = TObjectDictionary<string, TPixieTrueTypeFont>;

// Find a font file on the current platform.
// Weight: CSS weight (100..900), Italic: true for italic.
// Returns empty string if not found.
function PixieFindFontFile(const Family: string;
  Weight: Integer; Italic: Boolean): string;

implementation

{$IFDEF MSWINDOWS}
uses
  {$IFDEF FPC}Registry{$ELSE}Winapi.Windows, System.Win.Registry{$ENDIF};
{$ENDIF}

// ---------------------------------------------------------------------------
// Big-endian readers
// ---------------------------------------------------------------------------

function TPixieTrueTypeFont.ReadU16(Offset: UInt32): UInt16;
begin
  if Offset + 1 >= UInt32(Length(FData)) then
    Exit(0);
  Result := (UInt16(FData[Offset]) shl 8) or UInt16(FData[Offset + 1]);
end;

function TPixieTrueTypeFont.ReadI16(Offset: UInt32): Int16;
begin
  Result := Int16(ReadU16(Offset));
end;

function TPixieTrueTypeFont.ReadU32(Offset: UInt32): UInt32;
begin
  if Offset + 3 >= UInt32(Length(FData)) then
    Exit(0);
  Result := (UInt32(FData[Offset]) shl 24) or
            (UInt32(FData[Offset + 1]) shl 16) or
            (UInt32(FData[Offset + 2]) shl 8) or
            UInt32(FData[Offset + 3]);
end;

function TPixieTrueTypeFont.ReadFixed(Offset: UInt32): Single;
var
  IntPart: Int16;
  FracPart: UInt16;
begin
  IntPart := ReadI16(Offset);
  FracPart := ReadU16(Offset + 2);
  Result := IntPart + FracPart / 65536.0;
end;

// ---------------------------------------------------------------------------
// Table directory
// ---------------------------------------------------------------------------

function TPixieTrueTypeFont.FindTable(const Tag: AnsiString;
  out TblOffset, TblLength: UInt32): Boolean;
var
  NumTables, I: UInt16;
  Offset: UInt32;
  T: AnsiString;
begin
  Result := False;
  TblOffset := 0;
  TblLength := 0;
  if Length(FData) < Integer(FTableBase) + 12 then Exit;

  NumTables := ReadU16(FTableBase + 4);
  SetLength(T, 4);
  for I := 0 to NumTables - 1 do
  begin
    Offset := FTableBase + 12 + UInt32(I) * 16;
    if Offset + 15 >= UInt32(Length(FData)) then Exit;
    T[1] := AnsiChar(FData[Offset]);
    T[2] := AnsiChar(FData[Offset + 1]);
    T[3] := AnsiChar(FData[Offset + 2]);
    T[4] := AnsiChar(FData[Offset + 3]);
    if T = Tag then
    begin
      TblOffset := ReadU32(Offset + 8);
      TblLength := ReadU32(Offset + 12);
      Result := True;
      Exit;
    end;
  end;
end;

// ---------------------------------------------------------------------------
// Table parsers
// ---------------------------------------------------------------------------

function TPixieTrueTypeFont.ParseHead: Boolean;
var
  Offset, Len: UInt32;
begin
  Result := FindTable('head', Offset, Len);
  if not Result then Exit;
  if Len < 54 then Exit(False);

  FUnitsPerEm := ReadU16(Offset + 18);
  FBBoxXMin := ReadI16(Offset + 36);
  FBBoxYMin := ReadI16(Offset + 38);
  FBBoxXMax := ReadI16(Offset + 40);
  FBBoxYMax := ReadI16(Offset + 42);
  FIndexToLocFormat := ReadI16(Offset + 50);
end;

function TPixieTrueTypeFont.ParseHhea: Boolean;
var
  Offset, Len: UInt32;
begin
  Result := FindTable('hhea', Offset, Len);
  if not Result then Exit;
  if Len < 36 then Exit(False);

  FAscent := ReadI16(Offset + 4);
  FDescent := ReadI16(Offset + 6);
  FLineGap := ReadI16(Offset + 8);
  FNumberOfHMetrics := ReadU16(Offset + 34);
end;

function TPixieTrueTypeFont.ParseMaxp: Boolean;
var
  Offset, Len: UInt32;
begin
  Result := FindTable('maxp', Offset, Len);
  if not Result then Exit;
  if Len < 6 then Exit(False);

  FNumGlyphs := ReadU16(Offset + 4);
end;

function TPixieTrueTypeFont.ParseOS2: Boolean;
var
  Offset, Len: UInt32;
  Version: UInt16;
begin
  Result := FindTable('OS/2', Offset, Len);
  if not Result then
  begin
    // OS/2 is optional; fill defaults
    FWeightClass := 400;
    FCapHeight := 0;
    FXHeight := 0;
    FFsSelection := 0;
    Result := True;
    Exit;
  end;

  FWeightClass := ReadU16(Offset + 4);
  FFsSelection := ReadU16(Offset + 62);

  Version := ReadU16(Offset);
  if (Version >= 2) and (Len >= 96) then
  begin
    FXHeight := ReadI16(Offset + 86);
    FCapHeight := ReadI16(Offset + 88);
  end
  else
  begin
    FXHeight := 0;
    FCapHeight := 0;
  end;
end;

function TPixieTrueTypeFont.ParseName: Boolean;
var
  Offset, Len: UInt32;
  Count, StringOffset: UInt16;
  I: Integer;
  PlatformId, EncodingId, NameId, NameLen, NameOff: UInt16;
  RecOffset, StrStart: UInt32;
  S: string;
  J: Integer;
begin
  Result := FindTable('name', Offset, Len);
  if not Result then Exit;
  if Len < 6 then Exit(False);

  Count := ReadU16(Offset + 2);
  StringOffset := ReadU16(Offset + 4);
  StrStart := Offset + StringOffset;

  for I := 0 to Count - 1 do
  begin
    RecOffset := Offset + 6 + UInt32(I) * 12;
    if RecOffset + 11 >= UInt32(Length(FData)) then Break;

    PlatformId := ReadU16(RecOffset);
    EncodingId := ReadU16(RecOffset + 2);
    NameId := ReadU16(RecOffset + 6);
    NameLen := ReadU16(RecOffset + 8);
    NameOff := ReadU16(RecOffset + 10);

    // Platform 3 (Windows), Encoding 1 (UCS-2)
    if (PlatformId = 3) and (EncodingId = 1) then
    begin
      if (NameId = 1) or (NameId = 6) then
      begin
        S := '';
        J := 0;
        while J < NameLen do
        begin
          S := S + Char(
            (UInt16(FData[StrStart + NameOff + UInt32(J)]) shl 8) or
            UInt16(FData[StrStart + NameOff + UInt32(J) + 1]));
          Inc(J, 2);
        end;
        if (NameId = 1) and (FFamilyName = '') then
          FFamilyName := S
        else if (NameId = 6) and (FPostScriptName = '') then
          FPostScriptName := S;
      end;
    end
    // Platform 1 (Macintosh), Encoding 0 (Roman) — fallback
    else if (PlatformId = 1) and (EncodingId = 0) then
    begin
      if (NameId = 1) or (NameId = 6) then
      begin
        S := '';
        for J := 0 to NameLen - 1 do
          S := S + Char(FData[StrStart + NameOff + UInt32(J)]);
        if (NameId = 1) and (FFamilyName = '') then
          FFamilyName := S
        else if (NameId = 6) and (FPostScriptName = '') then
          FPostScriptName := S;
      end;
    end;
  end;
end;

function TPixieTrueTypeFont.ParsePost: Boolean;
var
  Offset, Len: UInt32;
begin
  Result := FindTable('post', Offset, Len);
  if not Result then
  begin
    FItalicAngle := 0;
    Result := True;
    Exit;
  end;
  if Len < 32 then Exit(False);

  FItalicAngle := ReadFixed(Offset + 4);
end;

function TPixieTrueTypeFont.ParseCmap: Boolean;
var
  Offset, Len: UInt32;
  NumSubtables, I: UInt16;
  PlatformId, EncodingId: UInt16;
  SubOffset: UInt32;
  Format: UInt16;
begin
  Result := FindTable('cmap', Offset, Len);
  if not Result then Exit;

  FCmapOffset := Offset;
  FCmapLength := Len;
  FCmapFmt4Offset := 0;
  FCmapFmt12Offset := 0;

  NumSubtables := ReadU16(Offset + 2);
  for I := 0 to NumSubtables - 1 do
  begin
    PlatformId := ReadU16(Offset + 4 + UInt32(I) * 8);
    EncodingId := ReadU16(Offset + 4 + UInt32(I) * 8 + 2);
    SubOffset := ReadU32(Offset + 4 + UInt32(I) * 8 + 4);

    Format := ReadU16(Offset + SubOffset);

    // Platform 3 (Windows): encoding 1 = BMP (format 4), encoding 10 = full Unicode (format 12)
    if PlatformId = 3 then
    begin
      if (EncodingId = 1) and (Format = 4) and (FCmapFmt4Offset = 0) then
        FCmapFmt4Offset := Offset + SubOffset
      else if (EncodingId = 10) and (Format = 12) and (FCmapFmt12Offset = 0) then
        FCmapFmt12Offset := Offset + SubOffset;
    end
    // Platform 0 (Unicode)
    else if PlatformId = 0 then
    begin
      if (Format = 4) and (FCmapFmt4Offset = 0) then
        FCmapFmt4Offset := Offset + SubOffset
      else if (Format = 12) and (FCmapFmt12Offset = 0) then
        FCmapFmt12Offset := Offset + SubOffset;
    end;
  end;

  Result := (FCmapFmt4Offset <> 0) or (FCmapFmt12Offset <> 0);
end;

// ---------------------------------------------------------------------------
// cmap lookup
// ---------------------------------------------------------------------------

function TPixieTrueTypeFont.CharToGlyphFmt4(Codepoint: UInt32): UInt16;
var
  Base: UInt32;
  SegCount, I: UInt16;
  EndCode, StartCode, IdDelta, IdRangeOffset: UInt16;
  EndCodesBase, StartCodesBase, IdDeltaBase, IdRangeBase: UInt32;
  GlyphIndex: UInt16;
  Offset: UInt32;
begin
  Result := 0;
  if (FCmapFmt4Offset = 0) or (Codepoint > $FFFF) then Exit;

  Base := FCmapFmt4Offset;
  SegCount := ReadU16(Base + 6) div 2;

  EndCodesBase := Base + 14;
  StartCodesBase := EndCodesBase + UInt32(SegCount) * 2 + 2; // +2 for reservedPad
  IdDeltaBase := StartCodesBase + UInt32(SegCount) * 2;
  IdRangeBase := IdDeltaBase + UInt32(SegCount) * 2;

  for I := 0 to SegCount - 1 do
  begin
    EndCode := ReadU16(EndCodesBase + UInt32(I) * 2);
    if EndCode < Codepoint then Continue;

    StartCode := ReadU16(StartCodesBase + UInt32(I) * 2);
    if StartCode > Codepoint then Exit;

    IdRangeOffset := ReadU16(IdRangeBase + UInt32(I) * 2);
    IdDelta := ReadU16(IdDeltaBase + UInt32(I) * 2);

    if IdRangeOffset = 0 then
      Result := UInt16((Codepoint + IdDelta) and $FFFF)
    else
    begin
      Offset := IdRangeBase + UInt32(I) * 2 +
        IdRangeOffset + (Codepoint - StartCode) * 2;
      GlyphIndex := ReadU16(Offset);
      if GlyphIndex <> 0 then
        Result := UInt16((GlyphIndex + IdDelta) and $FFFF);
    end;
    Exit;
  end;
end;

function TPixieTrueTypeFont.CharToGlyphFmt12(Codepoint: UInt32): UInt16;
var
  Base: UInt32;
  NumGroups, I: UInt32;
  GroupBase, StartChar, EndChar, StartGlyph: UInt32;
begin
  Result := 0;
  if FCmapFmt12Offset = 0 then Exit;

  Base := FCmapFmt12Offset;
  NumGroups := ReadU32(Base + 12);

  for I := 0 to NumGroups - 1 do
  begin
    GroupBase := Base + 16 + I * 12;
    StartChar := ReadU32(GroupBase);
    EndChar := ReadU32(GroupBase + 4);
    StartGlyph := ReadU32(GroupBase + 8);

    if Codepoint < StartChar then Exit;
    if Codepoint <= EndChar then
    begin
      Result := UInt16(StartGlyph + (Codepoint - StartChar));
      Exit;
    end;
  end;
end;

// ---------------------------------------------------------------------------
// Public methods
// ---------------------------------------------------------------------------

constructor TPixieTrueTypeFont.Create;
begin
  inherited Create;
end;

destructor TPixieTrueTypeFont.Destroy;
begin
  inherited;
end;

function TPixieTrueTypeFont.LoadFromFile(const FileName: string): Boolean;
var
  Stream: TFileStream;
begin
  Result := False;
  if not FileExists(FileName) then Exit;
  try
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      Result := LoadFromStream(Stream);
    finally
      Stream.Free;
    end;
  except
    Result := False;
  end;
end;

function TPixieTrueTypeFont.LoadFromStream(Stream: TStream): Boolean;
begin
  Result := False;
  try
    SetLength(FData, Stream.Size);
    Stream.Position := 0;
    if Stream.Read(FData[0], Length(FData)) <> Length(FData) then Exit;

    // Detect TTC (TrueType Collection) — use first font
    FTableBase := 0;
    if (Length(FData) >= 16) and
       (FData[0] = Ord('t')) and (FData[1] = Ord('t')) and
       (FData[2] = Ord('c')) and (FData[3] = Ord('f')) then
    begin
      if ReadU32(8) = 0 then Exit; // numFonts = 0
      FTableBase := ReadU32(12);   // offset to first font
    end;

    if not ParseHead then Exit;
    if not ParseHhea then Exit;
    if not ParseMaxp then Exit;
    if not ParseOS2 then Exit;
    ParseName;
    ParsePost;
    if not ParseCmap then Exit;

    // Cache table offsets
    FindTable('hmtx', FHmtxOffset, FHmtxLength);
    FindTable('loca', FLocaOffset, FLocaLength);
    FindTable('glyf', FGlyfOffset, FGlyfLength);

    Result := (FUnitsPerEm > 0) and (FNumGlyphs > 0);
  except
    Result := False;
  end;
end;

function TPixieTrueTypeFont.CharToGlyph(Codepoint: UInt32): UInt16;
begin
  // Try format 12 first (full Unicode), fall back to format 4 (BMP)
  if FCmapFmt12Offset <> 0 then
  begin
    Result := CharToGlyphFmt12(Codepoint);
    if Result <> 0 then Exit;
  end;
  Result := CharToGlyphFmt4(Codepoint);
end;

// Returns true if the glyph has outline data in the 'glyf' table.
// Rejects bitmap-only emoji fonts (CBDT/SBIX with empty glyf entries).
// COLR/CPAL colour fonts that also have base outlines will pass — PDF
// renders the monochrome outline, which is acceptable fallback behaviour.
function TPixieTrueTypeFont.HasGlyphOutline(GlyphId: UInt16): Boolean;
var
  GlyfOff, GlyfLen: UInt32;
begin
  Result := GetGlyphDataRange(GlyphId, GlyfOff, GlyfLen);
end;

function TPixieTrueTypeFont.GetGlyphWidth(GlyphId: UInt16): UInt16;
var
  Offset: UInt32;
begin
  Result := 0;
  if FHmtxOffset = 0 then Exit;
  if GlyphId < FNumberOfHMetrics then
    Offset := FHmtxOffset + UInt32(GlyphId) * 4
  else if FNumberOfHMetrics > 0 then
    Offset := FHmtxOffset + UInt32(FNumberOfHMetrics - 1) * 4
  else
    Exit;
  Result := ReadU16(Offset);
end;

function TPixieTrueTypeFont.GetFullData: TBytes;
begin
  Result := FData;
end;

// ---------------------------------------------------------------------------
// Glyph subsetting helpers
// ---------------------------------------------------------------------------

// Range/overflow checks off for low-level byte manipulation
{$IFOPT R+}{$DEFINE RESTORE_R}{$R-}{$ENDIF}
{$IFOPT Q+}{$DEFINE RESTORE_Q}{$Q-}{$ENDIF}
procedure TPixieTrueTypeFont.WriteU16BE(Stream: TMemoryStream; V: UInt16);
var
  Buf: array[0..1] of Byte;
begin
  Buf[0] := Byte(V shr 8);
  Buf[1] := Byte(V);
  Stream.Write(Buf, 2);
end;

procedure TPixieTrueTypeFont.WriteU32BE(Stream: TMemoryStream; V: UInt32);
var
  Buf: array[0..3] of Byte;
begin
  Buf[0] := Byte(V shr 24);
  Buf[1] := Byte(V shr 16);
  Buf[2] := Byte(V shr 8);
  Buf[3] := Byte(V);
  Stream.Write(Buf, 4);
end;

function TPixieTrueTypeFont.CalcTableChecksum(const Data: TBytes;
  Offset, Len: UInt32): UInt32;
var
  Sum, I, Cnt, V: UInt32;
begin
  Sum := 0;
  Cnt := (Len + 3) div 4;
  for I := 0 to Cnt - 1 do
  begin
    V := (UInt32(Data[Offset + I * 4]) shl 24) or
         (UInt32(Data[Offset + I * 4 + 1]) shl 16) or
         (UInt32(Data[Offset + I * 4 + 2]) shl 8) or
         UInt32(Data[Offset + I * 4 + 3]);
    Sum := Sum + V;
  end;
  Result := Sum;
end;
{$IFDEF RESTORE_R}{$R+}{$UNDEF RESTORE_R}{$ENDIF}
{$IFDEF RESTORE_Q}{$Q+}{$UNDEF RESTORE_Q}{$ENDIF}

function TPixieTrueTypeFont.GetGlyphDataRange(GlyphId: UInt16;
  out GlyfOff, GlyfLen: UInt32): Boolean;
var
  Off1, Off2: UInt32;
begin
  Result := False;
  GlyfOff := 0;
  GlyfLen := 0;
  if (FLocaOffset = 0) or (FGlyfOffset = 0) then Exit;
  if GlyphId >= FNumGlyphs then Exit;

  if FIndexToLocFormat = 0 then
  begin
    // Short format: UInt16 values, multiply by 2
    Off1 := UInt32(ReadU16(FLocaOffset + UInt32(GlyphId) * 2)) * 2;
    Off2 := UInt32(ReadU16(FLocaOffset + UInt32(GlyphId + 1) * 2)) * 2;
  end
  else
  begin
    // Long format: UInt32 values
    Off1 := ReadU32(FLocaOffset + UInt32(GlyphId) * 4);
    Off2 := ReadU32(FLocaOffset + UInt32(GlyphId + 1) * 4);
  end;

  if Off2 <= Off1 then Exit; // empty glyph
  GlyfOff := FGlyfOffset + Off1;
  GlyfLen := Off2 - Off1;
  Result := True;
end;

procedure TPixieTrueTypeFont.CollectCompositeGlyphs(GlyphId: UInt16;
  GlyphSet: TPixieGlyphIdSet; Depth: Integer);
var
  GlyfOff, GlyfLen, Offset: UInt32;
  NumContours: Int16;
  Flags, CompGlyphId: UInt16;
begin
  if Depth > 10 then Exit;
  if GlyphSet.ContainsKey(GlyphId) then Exit;
  GlyphSet.AddOrSetValue(GlyphId, True);

  if not GetGlyphDataRange(GlyphId, GlyfOff, GlyfLen) then Exit;
  if GlyfLen < 10 then Exit;

  NumContours := ReadI16(GlyfOff);
  if NumContours >= 0 then Exit; // simple glyph, no components

  // Composite glyph: parse component records starting at offset 10
  Offset := GlyfOff + 10;
  repeat
    if Offset + 3 >= UInt32(Length(FData)) then Break;
    Flags := ReadU16(Offset);
    CompGlyphId := ReadU16(Offset + 2);
    Inc(Offset, 4);

    // Recurse into component
    if CompGlyphId < FNumGlyphs then
      CollectCompositeGlyphs(CompGlyphId, GlyphSet, Depth + 1);

    // Skip arguments based on flags
    if (Flags and $0001) <> 0 then
      Inc(Offset, 4) // ARG_1_AND_2_ARE_WORDS: 2 x Int16
    else
      Inc(Offset, 2); // 2 x Int8

    // Skip transform data
    if (Flags and $0008) <> 0 then
      Inc(Offset, 2)  // WE_HAVE_A_SCALE: F2Dot14
    else if (Flags and $0040) <> 0 then
      Inc(Offset, 4)  // WE_HAVE_AN_X_AND_Y_SCALE: 2 x F2Dot14
    else if (Flags and $0080) <> 0 then
      Inc(Offset, 8); // WE_HAVE_A_TWO_BY_TWO: 4 x F2Dot14
  until (Flags and $0020) = 0; // MORE_COMPONENTS
end;

function TPixieTrueTypeFont.BuildSubsetCmap(
  UsedGlyphs: TPixieGlyphMap): TBytes;
type
  TCpGlyph = record
    Codepoint: UInt32;
    GlyphId: UInt16;
  end;
  TSeg = record
    StartCode: UInt16;
    EndCode: UInt16;
    Delta: Int16;
  end;
  TSeqGroup = record
    StartCharCode: UInt32;
    EndCharCode: UInt32;
    StartGlyphId: UInt32;
  end;
var
  Stream: TMemoryStream;
  Pair: TPair<UInt16, UInt32>;
  Segments: array of TSeg;
  SegCount, BmpCount, I, J: Integer;
  SortedCps: array of TCpGlyph;
  Tmp: TCpGlyph;
  Count: Integer;
  HasSupplementary: Boolean;
  Groups: array of TSeqGroup;
  NumGroups: Integer;
  SearchRange, EntrySelector, RangeShift: UInt16;
  Pow2: UInt16;
  SegTableLen: UInt16;
  Fmt4Offset, Fmt12Offset: UInt32;
  NumTables: UInt16;
begin
  // Collect ALL codepoints from UsedGlyphs in a single pass
  HasSupplementary := False;
  Count := 0;
  SetLength(SortedCps, UsedGlyphs.Count);
  for Pair in UsedGlyphs do
  begin
    if (Pair.Value > 0) and (Pair.Key > 0) then
    begin
      SortedCps[Count].Codepoint := Pair.Value;
      SortedCps[Count].GlyphId := Pair.Key;
      Inc(Count);
      if Pair.Value > $FFFF then
        HasSupplementary := True;
    end;
  end;
  SetLength(SortedCps, Count);

  // Sort by codepoint (simple insertion sort — small N)
  for I := 1 to Count - 1 do
  begin
    if SortedCps[I].Codepoint < SortedCps[I - 1].Codepoint then
    begin
      Tmp := SortedCps[I];
      J := I - 1;
      while (J >= 0) and (SortedCps[J].Codepoint > Tmp.Codepoint) do
      begin
        SortedCps[J + 1] := SortedCps[J];
        Dec(J);
      end;
      SortedCps[J + 1] := Tmp;
    end;
  end;

  // Build Format 4 segments from BMP codepoints only (sorted array,
  // BMP entries come first since they have lower codepoints)
  BmpCount := 0;
  for I := 0 to Count - 1 do
    if SortedCps[I].Codepoint <= $FFFF then
      Inc(BmpCount)
    else
      Break; // sorted, so all remaining are supplementary

  SetLength(Segments, BmpCount + 1); // +1 for sentinel
  for I := 0 to BmpCount - 1 do
  begin
    Segments[I].StartCode := UInt16(SortedCps[I].Codepoint);
    Segments[I].EndCode := UInt16(SortedCps[I].Codepoint);
    Segments[I].Delta := Int16(Integer(SortedCps[I].GlyphId) -
      Integer(SortedCps[I].Codepoint));
  end;
  // Sentinel segment
  Segments[BmpCount].StartCode := $FFFF;
  Segments[BmpCount].EndCode := $FFFF;
  Segments[BmpCount].Delta := 1;
  SegCount := BmpCount + 1;

  // Compute searchRange, entrySelector, rangeShift
  Pow2 := 1;
  EntrySelector := 0;
  while Pow2 * 2 <= UInt16(SegCount) do
  begin
    Pow2 := Pow2 * 2;
    Inc(EntrySelector);
  end;
  SearchRange := Pow2 * 2;
  RangeShift := UInt16(SegCount) * 2 - SearchRange;

  // Format 4 length: 14 (header) + 4 arrays x SegCount x 2 + 2 (reservedPad)
  SegTableLen := 14 + UInt16(SegCount) * 8 + 2;

  // Determine cmap header layout
  if HasSupplementary then
    NumTables := 2
  else
    NumTables := 1;
  Fmt4Offset := 4 + UInt32(NumTables) * 8;
  Fmt12Offset := Fmt4Offset + SegTableLen;

  Stream := TMemoryStream.Create;
  try
    // cmap header
    WriteU16BE(Stream, 0);          // version
    WriteU16BE(Stream, NumTables);  // numTables
    // Encoding record 1: platform=3 (Windows), encoding=1 (BMP), -> Format 4
    WriteU16BE(Stream, 3);
    WriteU16BE(Stream, 1);
    WriteU32BE(Stream, Fmt4Offset);
    // Encoding record 2 (supplementary only): platform=3, encoding=10, -> Format 12
    if HasSupplementary then
    begin
      WriteU16BE(Stream, 3);
      WriteU16BE(Stream, 10);
      WriteU32BE(Stream, Fmt12Offset);
    end;

    // Format 4 subtable
    WriteU16BE(Stream, 4); // format
    WriteU16BE(Stream, SegTableLen); // length
    WriteU16BE(Stream, 0); // language
    WriteU16BE(Stream, UInt16(SegCount) * 2); // segCountX2
    WriteU16BE(Stream, SearchRange);
    WriteU16BE(Stream, EntrySelector);
    WriteU16BE(Stream, RangeShift);

    // endCode array
    for I := 0 to SegCount - 1 do
      WriteU16BE(Stream, Segments[I].EndCode);
    // reservedPad
    WriteU16BE(Stream, 0);
    // startCode array
    for I := 0 to SegCount - 1 do
      WriteU16BE(Stream, Segments[I].StartCode);
    // idDelta array
    for I := 0 to SegCount - 1 do
      WriteU16BE(Stream, UInt16(Segments[I].Delta));
    // idRangeOffset array (all zeros — we use delta only)
    for I := 0 to SegCount - 1 do
      WriteU16BE(Stream, 0);

    // Format 12 subtable (when supplementary-plane codepoints are present)
    if HasSupplementary then
    begin
      // Build sequential map groups from the already-sorted full array
      NumGroups := 0;
      SetLength(Groups, Count);
      if Count > 0 then
      begin
        Groups[0].StartCharCode := SortedCps[0].Codepoint;
        Groups[0].EndCharCode := SortedCps[0].Codepoint;
        Groups[0].StartGlyphId := SortedCps[0].GlyphId;
        NumGroups := 1;
        for I := 1 to Count - 1 do
        begin
          // Extend current group if consecutive codepoint and glyph
          if (SortedCps[I].Codepoint = Groups[NumGroups - 1].EndCharCode + 1) and
             (SortedCps[I].GlyphId = Groups[NumGroups - 1].StartGlyphId +
               (SortedCps[I].Codepoint - Groups[NumGroups - 1].StartCharCode)) then
            Groups[NumGroups - 1].EndCharCode := SortedCps[I].Codepoint
          else begin
            Groups[NumGroups].StartCharCode := SortedCps[I].Codepoint;
            Groups[NumGroups].EndCharCode := SortedCps[I].Codepoint;
            Groups[NumGroups].StartGlyphId := SortedCps[I].GlyphId;
            Inc(NumGroups);
          end;
        end;
      end;

      // Write Format 12 subtable header (16 bytes) + groups (12 bytes each)
      WriteU16BE(Stream, 12);                                // format
      WriteU16BE(Stream, 0);                                 // reserved
      WriteU32BE(Stream, UInt32(16 + NumGroups * 12));       // length
      WriteU32BE(Stream, 0);                                 // language
      WriteU32BE(Stream, UInt32(NumGroups));                 // numGroups
      for I := 0 to NumGroups - 1 do
      begin
        WriteU32BE(Stream, Groups[I].StartCharCode);
        WriteU32BE(Stream, Groups[I].EndCharCode);
        WriteU32BE(Stream, Groups[I].StartGlyphId);
      end;
    end;

    SetLength(Result, Stream.Size);
    Stream.Position := 0;
    Stream.Read(Result[0], Length(Result));
  finally
    Stream.Free;
  end;
end;

function TPixieTrueTypeFont.AssembleTtfFile(
  const Tables: array of AnsiString;
  const TableData: array of TBytes): TBytes;
var
  Stream: TMemoryStream;
  NumTables, I: Integer;
  SearchRange, EntrySelector, RangeShift: UInt16;
  Pow2: UInt16;
  DataOffset, PaddedLen: UInt32;
  Checksum: UInt32;
  Padded: TBytes;
begin
  NumTables := Length(Tables);
  Stream := TMemoryStream.Create;
  try
    // Offset table header
    Pow2 := 1;
    EntrySelector := 0;
    while Pow2 * 2 <= UInt16(NumTables) do
    begin
      Pow2 := Pow2 * 2;
      Inc(EntrySelector);
    end;
    SearchRange := Pow2 * 16;
    RangeShift := UInt16(NumTables) * 16 - SearchRange;

    WriteU32BE(Stream, $00010000); // sfVersion 1.0
    WriteU16BE(Stream, UInt16(NumTables));
    WriteU16BE(Stream, SearchRange);
    WriteU16BE(Stream, EntrySelector);
    WriteU16BE(Stream, RangeShift);

    // Calculate data start offset: header (12) + table records (NumTables * 16)
    DataOffset := 12 + UInt32(NumTables) * 16;

    // Write table directory records
    for I := 0 to NumTables - 1 do
    begin
      // Tag (4 bytes)
      Stream.Write(Tables[I][1], 4);
      // Pad table data to 4-byte boundary for checksum
      PaddedLen := (UInt32(Length(TableData[I])) + 3) and not UInt32(3);
      if PaddedLen > 0 then
      begin
        SetLength(Padded, PaddedLen);
        FillChar(Padded[0], PaddedLen, 0);
        if Length(TableData[I]) > 0 then
          Move(TableData[I][0], Padded[0], Length(TableData[I]));
        Checksum := CalcTableChecksum(Padded, 0, PaddedLen);
      end
      else
        Checksum := 0;
      WriteU32BE(Stream, Checksum);
      WriteU32BE(Stream, DataOffset);
      WriteU32BE(Stream, UInt32(Length(TableData[I])));
      DataOffset := DataOffset + PaddedLen;
    end;

    // Write table data (each padded to 4-byte boundary)
    for I := 0 to NumTables - 1 do
    begin
      if Length(TableData[I]) > 0 then
        Stream.Write(TableData[I][0], Length(TableData[I]));
      // Pad to 4-byte boundary
      PaddedLen := (UInt32(Length(TableData[I])) + 3) and not UInt32(3);
      PaddedLen := PaddedLen - UInt32(Length(TableData[I]));
      if PaddedLen > 0 then
      begin
        SetLength(Padded, PaddedLen);
        FillChar(Padded[0], PaddedLen, 0);
        Stream.Write(Padded[0], PaddedLen);
      end;
    end;

    SetLength(Result, Stream.Size);
    if Stream.Size > 0 then
    begin
      Stream.Position := 0;
      Stream.Read(Result[0], Length(Result));
    end;
  finally
    Stream.Free;
  end;
end;

function TPixieTrueTypeFont.BuildSubsetFont(
  UsedGlyphs: TPixieGlyphMap): TBytes;
var
  GlyphSet: TPixieGlyphIdSet;
  Pair: TPair<UInt16, UInt32>;
  GlyfStream, LocaStream: TMemoryStream;
  GlyfOff, GlyfLen, LocaPos: UInt32;
  I: Integer;
  PadByte: Byte;
  GlyfData, LocaData: TBytes;
  CmapData: TBytes;
  HeadData: TBytes;
  TableTags: array of AnsiString;
  TableDatas: array of TBytes;
  TblOff, TblLen: UInt32;
  NumTables: Integer;

  procedure AddTable(const Tag: AnsiString; const Data: TBytes);
  begin
    if NumTables >= Length(TableTags) then
    begin
      SetLength(TableTags, NumTables + 8);
      SetLength(TableDatas, NumTables + 8);
    end;
    TableTags[NumTables] := Tag;
    TableDatas[NumTables] := Data;
    Inc(NumTables);
  end;

  procedure CopyOrigTable(const Tag: AnsiString);
  var
    Buf: TBytes;
  begin
    if FindTable(Tag, TblOff, TblLen) and (TblLen > 0) then
    begin
      SetLength(Buf, TblLen);
      Move(FData[TblOff], Buf[0], TblLen);
      AddTable(Tag, Buf);
    end;
  end;

begin
  // Fallback: if loca/glyf not available (CFF font), return full data
  if (FLocaOffset = 0) or (FGlyfOffset = 0) then
    Exit(GetFullData);

  // 1. Expand used glyph set with composites
  GlyphSet := TPixieGlyphIdSet.Create;
  try
    // Always include .notdef (glyph 0)
    GlyphSet.Add(0, True);
    for Pair in UsedGlyphs do
      CollectCompositeGlyphs(Pair.Key, GlyphSet, 0);

    // Verify all requested glyphs have data in the original font.
    // If any are missing, fall back to full font (don't subset).
    for Pair in UsedGlyphs do
    begin
      if not GlyphSet.ContainsKey(Pair.Key) then
        Exit(GetFullData);
      if not GetGlyphDataRange(Pair.Key, GlyfOff, GlyfLen) then
      begin
        // Glyph has metrics but no outline (e.g. space) — that's OK.
        // But if the glyph should have outline data, something is wrong.
        // We can't distinguish, so just verify it's in the set.
      end;
    end;

    // 2. Build new glyf and loca tables
    GlyfStream := TMemoryStream.Create;
    LocaStream := TMemoryStream.Create;
    try
      for I := 0 to FNumGlyphs - 1 do
      begin
        // Write loca entry (long format, UInt32)
        LocaPos := UInt32(GlyfStream.Size);
        WriteU32BE(LocaStream, LocaPos);

        if GlyphSet.ContainsKey(UInt16(I)) and
           GetGlyphDataRange(UInt16(I), GlyfOff, GlyfLen) and
           (GlyfOff + GlyfLen <= UInt32(Length(FData))) then
        begin
          // Copy glyph data
          GlyfStream.Write(FData[GlyfOff], GlyfLen);
          // Pad to 4-byte boundary for loca long format alignment
          PadByte := 0;
          while (GlyfStream.Size and 3) <> 0 do
            GlyfStream.Write(PadByte, 1);
        end;
        // else: unused glyph — loca[i] == loca[i+1] means zero-length
      end;
      // Final loca entry (points past end of glyf)
      WriteU32BE(LocaStream, UInt32(GlyfStream.Size));

      SetLength(GlyfData, GlyfStream.Size);
      if GlyfStream.Size > 0 then
      begin
        GlyfStream.Position := 0;
        GlyfStream.Read(GlyfData[0], Length(GlyfData));
      end;

      SetLength(LocaData, LocaStream.Size);
      if LocaStream.Size > 0 then
      begin
        LocaStream.Position := 0;
        LocaStream.Read(LocaData[0], Length(LocaData));
      end;
    finally
      LocaStream.Free;
      GlyfStream.Free;
    end;
  finally
    GlyphSet.Free;
  end;

  // 3. Build minimal cmap for used codepoints
  CmapData := BuildSubsetCmap(UsedGlyphs);

  // 4. Copy head table and patch indexToLocFormat to 1 (long)
  if FindTable('head', TblOff, TblLen) and (TblLen >= 54) then
  begin
    SetLength(HeadData, TblLen);
    Move(FData[TblOff], HeadData[0], TblLen);
    // Patch indexToLocFormat at offset 50 to 1 (long format)
    HeadData[50] := 0;
    HeadData[51] := 1;
    // Clear checksumAdjustment at offset 8
    HeadData[8] := 0;
    HeadData[9] := 0;
    HeadData[10] := 0;
    HeadData[11] := 0;
  end
  else
    Exit(GetFullData);

  // 5. Assemble tables
  NumTables := 0;
  SetLength(TableTags, 16);
  SetLength(TableDatas, 16);

  AddTable('cmap', CmapData);
  AddTable('glyf', GlyfData);
  AddTable('head', HeadData);
  CopyOrigTable('hhea');
  CopyOrigTable('hmtx');
  AddTable('loca', LocaData);
  CopyOrigTable('maxp');
  CopyOrigTable('name');
  CopyOrigTable('OS/2');
  CopyOrigTable('post');

  SetLength(TableTags, NumTables);
  SetLength(TableDatas, NumTables);

  Result := AssembleTtfFile(TableTags, TableDatas);
end;

// ---------------------------------------------------------------------------
// Font file discovery
// ---------------------------------------------------------------------------

{$IFDEF MSWINDOWS}
function NormalizeFamilyName(const Name: string): string;
begin
  Result := LowerCase(Trim(Name));
end;

function MatchFontEntry(const EntryName, Family: string;
  Weight: Integer; Italic: Boolean): Integer;
var
  Lower, FamilyLower: string;
  Score: Integer;
  IsBold, IsItalic: Boolean;
begin
  // Score: higher = better match. 0 = no match.
  Result := 0;
  Lower := LowerCase(EntryName);
  FamilyLower := LowerCase(Family);

  // Entry must start with the family name
  if Pos(FamilyLower, Lower) <> 1 then Exit;

  Score := 1;
  IsBold := (Pos('bold', Lower) > Length(FamilyLower));
  IsItalic := (Pos('italic', Lower) > 0) or (Pos('oblique', Lower) > 0);

  // Match italic
  if Italic = IsItalic then
    Inc(Score, 10)
  else
    Dec(Score, 5);

  // Match weight
  if Weight >= 700 then
  begin
    if IsBold then Inc(Score, 10) else Dec(Score, 5);
  end
  else
  begin
    if not IsBold then Inc(Score, 10) else Dec(Score, 5);
  end;

  // Prefer entries that are exactly the family + style, not substrings
  if Length(Lower) < Length(FamilyLower) + 20 then
    Inc(Score, 2);

  Result := Score;
end;

function PixieFindFontFileWindows(const Family: string;
  Weight: Integer; Italic: Boolean): string;
var
  Reg: TRegistry;
  ValueNames: TStringList;
  I, Score, BestScore: Integer;
  BestFile, FileName, FontDir: string;
begin
  Result := '';
  FontDir := GetEnvironmentVariable('SystemRoot') + '\Fonts\';

  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if not Reg.OpenKeyReadOnly(
      'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts') then Exit;

    ValueNames := TStringList.Create;
    try
      Reg.GetValueNames(ValueNames);
      BestScore := 0;
      BestFile := '';

      for I := 0 to ValueNames.Count - 1 do
      begin
        Score := MatchFontEntry(ValueNames[I], Family, Weight, Italic);
        if Score > BestScore then
        begin
          BestScore := Score;
          FileName := Reg.ReadString(ValueNames[I]);
          // If not an absolute path, prepend Windows font dir
          if (Length(FileName) < 2) or (FileName[2] <> ':') then
            FileName := FontDir + FileName;
          BestFile := FileName;
        end;
      end;

      if (BestFile <> '') and FileExists(BestFile) then
        Result := BestFile;
    finally
      ValueNames.Free;
    end;
  finally
    Reg.Free;
  end;
end;
{$ENDIF}

{$IF DEFINED(LINUX) OR DEFINED(DARWIN)}
function ScanFontDirs(const Family: string; Weight: Integer;
  Italic: Boolean; const Dirs: array of string): string;
var
  I: Integer;
  Font: TPixieTrueTypeFont;
  BestFile: string;
  BestScore, Score: Integer;

  procedure ScanDir(const Dir: string);
  var
    SR: TSearchRec;
    FullPath, Ext: string;
  begin
    if not DirectoryExists(Dir) then Exit;

    if FindFirst(Dir + '/*', faAnyFile, SR) = 0 then
    try
      repeat
        if (SR.Name = '.') or (SR.Name = '..') then Continue;
        FullPath := Dir + '/' + SR.Name;
        if (SR.Attr and faDirectory) <> 0 then
        begin
          ScanDir(FullPath);
          Continue;
        end;

        Ext := LowerCase(ExtractFileExt(SR.Name));
        if (Ext <> '.ttf') and (Ext <> '.otf') and (Ext <> '.ttc') then Continue;

        Font := TPixieTrueTypeFont.Create;
        try
          if Font.LoadFromFile(FullPath) then
          begin
            if LowerCase(Font.FamilyName) = LowerCase(Family) then
            begin
              Score := 1;
              // Check weight
              if Abs(Integer(Font.WeightClass) - Weight) < 100 then
                Inc(Score, 10);
              // Check italic
              if Italic = ((Font.FsSelection and 1) <> 0) then
                Inc(Score, 10);
              if Score > BestScore then
              begin
                BestScore := Score;
                BestFile := FullPath;
              end;
            end;
          end;
        finally
          Font.Free;
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;
begin
  BestScore := 0;
  BestFile := '';

  for I := Low(Dirs) to High(Dirs) do
    ScanDir(Dirs[I]);

  Result := BestFile;
end;
{$ENDIF}

function PixieFindFontFile(const Family: string;
  Weight: Integer; Italic: Boolean): string;
begin
  {$IFDEF MSWINDOWS}
  Result := PixieFindFontFileWindows(Family, Weight, Italic);
  {$ENDIF}
  {$IFDEF LINUX}
  Result := ScanFontDirs(Family, Weight, Italic, [
    '/usr/share/fonts',
    '/usr/local/share/fonts',
    ExpandFileName('~/.local/share/fonts')
  ]);
  {$ENDIF}
  {$IFDEF DARWIN}
  Result := ScanFontDirs(Family, Weight, Italic, [
    '/System/Library/Fonts',
    '/System/Library/Fonts/Supplemental',
    '/Library/Fonts',
    ExpandFileName('~/Library/Fonts')
  ]);
  {$ENDIF}
end;

end.
