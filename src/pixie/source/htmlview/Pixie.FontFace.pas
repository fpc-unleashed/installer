unit Pixie.FontFace;

// @font-face registry: stores parsed @font-face descriptors and tracks
// which custom fonts have been loaded.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Generics.Collections,
  Pixie.Types, Pixie.CssTokenizer;

type
  TPixieFontFaceSrc = record
    Url: string;
    Format: string; // 'truetype', 'woff', 'woff2', etc. or '' if unspecified
  end;
  TPixieFontFaceSrcList = TList<TPixieFontFaceSrc>;

  TPixieFontFaceEntry = class
  public
    Family: string;
    Weight: Integer;
    Style: TPixieFontStyle;
    Sources: TPixieFontFaceSrcList;
    BaseUrl: string;
    Loaded: Boolean;
    LoadFailed: Boolean;
    InstalledHandle: PtrUInt;
    InternalName: string; // actual family name from TTF name table

    constructor Create;
    destructor Destroy; override;
  end;
  TPixieFontFaceEntryList = TObjectList<TPixieFontFaceEntry>;

  TPixieFontFaceRegistry = class
  private
    FEntries: TPixieFontFaceEntryList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(Entry: TPixieFontFaceEntry);
    property Entries: TPixieFontFaceEntryList read FEntries;
  end;

// Parse an @font-face block's token list into a TPixieFontFaceEntry.
// Returns nil if the block is missing required descriptors (font-family, src).
function PixieParseFontFaceRule(BlockTokens: TPixieCssTokenList;
  const BaseUrl: string): TPixieFontFaceEntry;

// Extract the family name (name ID 1) from raw TTF data.
function PixieGetTtfFamilyName(Data: Pointer; Size: Integer): string;

implementation

uses
  Pixie.Utils, Pixie.CssParser;

{ TPixieFontFaceEntry }

constructor TPixieFontFaceEntry.Create;
begin
  inherited Create;
  Sources := TPixieFontFaceSrcList.Create;
  Weight := 400;
  Style := fstNormal;
end;

destructor TPixieFontFaceEntry.Destroy;
begin
  Sources.Free;
  inherited Destroy;
end;

{ TPixieFontFaceRegistry }

constructor TPixieFontFaceRegistry.Create;
begin
  inherited Create;
  FEntries := TPixieFontFaceEntryList.Create(True);
end;

destructor TPixieFontFaceRegistry.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

procedure TPixieFontFaceRegistry.Add(Entry: TPixieFontFaceEntry);
begin
  FEntries.Add(Entry);
end;

{ Parse helpers }

function UnquoteStr(const S: string): string;
begin
  Result := S;
  if Length(Result) >= 2 then
    if ((Result[1] = '''') or (Result[1] = '"')) and
       (Result[Length(Result)] = Result[1]) then
      Result := Copy(Result, 2, Length(Result) - 2);
end;

procedure ParseSrcDescriptor(Tokens: TPixieCssTokenList;
  Sources: TPixieFontFaceSrcList);
var
  I: Integer;
  Tok, Next: TPixieCssToken;
  Src: TPixieFontFaceSrc;
  HaveUrl: Boolean;
begin
  I := 0;
  while I < Tokens.Count do
  begin
    Tok := Tokens[I];

    // url() token — raw URL without quotes
    if Tok.TokenType = cssTokenUrl then
    begin
      Src.Url := Tok.Str;
      Src.Format := '';
      HaveUrl := True;
      Inc(I);
    end
    // url("...") as function token
    else if (Tok.TokenType = cssTokenCvFunction) and
            PixieStrEqualNoCase(Tok.Str, 'url') and
            (Tok.Value <> nil) and (Tok.Value.Count > 0) then
    begin
      Src.Url := UnquoteStr(Tok.Value[0].Str);
      Src.Format := '';
      HaveUrl := True;
      Inc(I);
    end
    else
    begin
      HaveUrl := False;
      Inc(I);
    end;

    if not HaveUrl then
      Continue;

    // Skip whitespace, look for format()
    while (I < Tokens.Count) and
          (Tokens[I].TokenType = cssTokenWhitespace) do
      Inc(I);

    if (I < Tokens.Count) then
    begin
      Next := Tokens[I];
      if (Next.TokenType = cssTokenCvFunction) and
         PixieStrEqualNoCase(Next.Str, 'format') and
         (Next.Value <> nil) and (Next.Value.Count > 0) then
      begin
        Src.Format := PixieLowerCase(UnquoteStr(Next.Value[0].Str));
        Inc(I);
      end;
    end;

    Sources.Add(Src);

    // Skip to next comma (next source in the list)
    while (I < Tokens.Count) and (Tokens[I].TokenType <> Ord(',')) do
      Inc(I);
    if (I < Tokens.Count) then
      Inc(I); // skip comma
  end;
end;

function PixieParseFontFaceRule(BlockTokens: TPixieCssTokenList;
  const BaseUrl: string): TPixieFontFaceEntry;
var
  Decls: TPixieCssRawDeclarationList;
  Rules: TPixieCssRawRuleList;
  I: Integer;
  Decl: TPixieCssRawDeclaration;
  DeclName, Val: string;
  Entry: TPixieFontFaceEntry;
  WeightVal: Integer;
begin
  Result := nil;
  Decls := TPixieCssRawDeclarationList.Create;
  Rules := TPixieCssRawRuleList.Create(True);
  try
    PixieCssParseStyleBlockContents(BlockTokens, Decls, Rules);

    Entry := TPixieFontFaceEntry.Create;
    Entry.BaseUrl := BaseUrl;

    for I := 0 to Decls.Count - 1 do
    begin
      Decl := Decls[I];
      DeclName := PixieLowerCase(Decl.Name);

      if DeclName = 'font-family' then
      begin
        if (Decl.Value <> nil) and (Decl.Value.Count > 0) then
          Entry.Family := UnquoteStr(Decl.Value[0].Str);
      end
      else if DeclName = 'src' then
      begin
        if Decl.Value <> nil then
          ParseSrcDescriptor(Decl.Value, Entry.Sources);
      end
      else if DeclName = 'font-weight' then
      begin
        if (Decl.Value <> nil) and (Decl.Value.Count > 0) then
        begin
          Val := PixieLowerCase(Decl.Value[0].Str);
          if Val = 'normal' then
            Entry.Weight := 400
          else if Val = 'bold' then
            Entry.Weight := 700
          else
          begin
            WeightVal := StrToIntDef(Val, 0);
            if (Decl.Value[0].TokenType = cssTokenNumber) then
              WeightVal := Round(Decl.Value[0].Number);
            if (WeightVal >= 1) and (WeightVal <= 1000) then
              Entry.Weight := WeightVal;
          end;
        end;
      end
      else if DeclName = 'font-style' then
      begin
        if (Decl.Value <> nil) and (Decl.Value.Count > 0) then
        begin
          Val := PixieLowerCase(Decl.Value[0].Str);
          if (Val = 'italic') or (Val = 'oblique') then
            Entry.Style := fstItalic
          else
            Entry.Style := fstNormal;
        end;
      end;
    end;

    if (Entry.Family = '') or (Entry.Sources.Count = 0) then
    begin
      Entry.Free;
      Exit;
    end;

    Result := Entry;
  finally
    for I := 0 to Decls.Count - 1 do
      Decls[I].Value.Free;
    Decls.Free;
    Rules.Free;
  end;
end;

function PixieGetTtfFamilyName(Data: Pointer; Size: Integer): string;
var
  P: PByte;
  NumTables, I: Integer;
  Tag: LongWord;
  TableOff, TableLen: LongWord;
  NameOff, Count, StrStart: Integer;
  RecOff, PlatId, EncId, NameId, NLen, NOff: Integer;
  J: Integer;
begin
  Result := '';
  P := PByte(Data);
  if Size < 12 then Exit;

  // Find 'name' table in the table directory
  NumTables := (P[4] shl 8) or P[5];
  TableOff := 0;
  TableLen := 0;
  for I := 0 to NumTables - 1 do
  begin
    if 12 + I * 16 + 15 >= Size then Exit;
    Tag := (LongWord(P[12 + I * 16]) shl 24) or
           (LongWord(P[12 + I * 16 + 1]) shl 16) or
           (LongWord(P[12 + I * 16 + 2]) shl 8) or
           LongWord(P[12 + I * 16 + 3]);
    if Tag = $6E616D65 then // 'name'
    begin
      TableOff := (LongWord(P[12 + I * 16 + 8]) shl 24) or
                  (LongWord(P[12 + I * 16 + 9]) shl 16) or
                  (LongWord(P[12 + I * 16 + 10]) shl 8) or
                  LongWord(P[12 + I * 16 + 11]);
      TableLen := (LongWord(P[12 + I * 16 + 12]) shl 24) or
                  (LongWord(P[12 + I * 16 + 13]) shl 16) or
                  (LongWord(P[12 + I * 16 + 14]) shl 8) or
                  LongWord(P[12 + I * 16 + 15]);
      Break;
    end;
  end;
  if (TableOff = 0) or (Integer(TableOff + 6) > Size) then Exit;

  Count := (P[TableOff + 2] shl 8) or P[TableOff + 3];
  StrStart := Integer(TableOff) +
    ((P[TableOff + 4] shl 8) or P[TableOff + 5]);

  for I := 0 to Count - 1 do
  begin
    RecOff := Integer(TableOff) + 6 + I * 12;
    if RecOff + 11 >= Size then Break;

    PlatId := (P[RecOff] shl 8) or P[RecOff + 1];
    EncId := (P[RecOff + 2] shl 8) or P[RecOff + 3];
    NameId := (P[RecOff + 6] shl 8) or P[RecOff + 7];
    NLen := (P[RecOff + 8] shl 8) or P[RecOff + 9];
    NOff := (P[RecOff + 10] shl 8) or P[RecOff + 11];

    if NameId <> 1 then Continue; // family name

    // Platform 3 (Windows), Encoding 1 (UCS-2)
    if (PlatId = 3) and (EncId = 1) then
    begin
      if StrStart + NOff + NLen > Size then Continue;
      // Length is known (one char per UCS-2 pair), so size the result once
      // and fill by index instead of reallocating on every concatenation.
      SetLength(Result, NLen div 2);
      for J := 0 to (NLen div 2) - 1 do
        Result[J + 1] := Char(
          (P[StrStart + NOff + J * 2] shl 8) or P[StrStart + NOff + J * 2 + 1]);
      Exit;
    end;

    // Platform 1 (Mac), Encoding 0 (Roman) — fallback
    if (PlatId = 1) and (EncId = 0) and (Result = '') then
    begin
      if StrStart + NOff + NLen > Size then Continue;
      SetLength(Result, NLen);
      for J := 0 to NLen - 1 do
        Result[J + 1] := Char(P[StrStart + NOff + J]);
    end;
  end;
end;

end.
