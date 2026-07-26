unit Pixie.PdfWriter;

// Low-level PDF object model and file writer.
// Produces valid PDF 1.4 files with Flate-compressed streams
// and cross-reference table.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections;

type
  { TPixiePdfDictEntry }

  TPixiePdfDictEntry = record
    Key: AnsiString;
    Value: AnsiString;
    class function Create(const AKey, AValue: AnsiString): TPixiePdfDictEntry; static;
  end;

  TPixiePdfDictEntryList = TList<TPixiePdfDictEntry>;

  { TPixiePdfObject }

  TPixiePdfObject = class
  private
    FId: Integer;
    FDict: TPixiePdfDictEntryList;
    FStream: TBytes;
    FCompressStream: Boolean;
  public
    constructor Create(AId: Integer);
    destructor Destroy; override;

    procedure AddEntry(const Key, Value: AnsiString);
    procedure SetEntry(const Key, Value: AnsiString);
    function GetEntry(const Key: AnsiString): AnsiString;
    procedure SetStream(const Data: TBytes; Compress: Boolean = True);
    procedure AppendStream(const Data: TBytes);

    property Id: Integer read FId;
    property CompressStream: Boolean read FCompressStream write FCompressStream;
    function HasStream: Boolean;
    function StreamLength: Integer;
    function StreamData: TBytes;
  end;

  TPixiePdfObjectList = TObjectList<TPixiePdfObject>;
  TPixieIntVector = TList<Integer>;
  TPixieInt64Vector = TList<Int64>;

  { TPixiePdfWriter }

  TPixiePdfWriter = class
  private
    FObjects: TPixiePdfObjectList;
    FPages: TPixieIntVector; // page object IDs
    FRootId: Integer;
    FPagesId: Integer;
    FInfoId: Integer;
    FTitle: string;
    FAuthor: string;

    function CompressData(const Input: TBytes): TBytes;
    procedure WriteObj(Stream: TStream; Obj: TPixiePdfObject;
      var Offsets: TPixieInt64Vector);
    procedure WriteAnsi(Stream: TStream; const S: AnsiString);
  public
    constructor Create;
    destructor Destroy; override;

    function AllocObject: TPixiePdfObject;
    function AllocPage(Width, Height: Single): TPixiePdfObject;
    procedure Write(Stream: TStream);

    property Title: string read FTitle write FTitle;
    property Author: string read FAuthor write FAuthor;
    property Pages: TPixieIntVector read FPages;
  end;

// Utility: format a Single as PDF number (no trailing zeros, decimal point)
function PdfFloat(V: Single): AnsiString;
function PdfRef(Id: Integer): AnsiString;
function PdfName(const S: AnsiString): AnsiString;
function PdfString(const S: string): AnsiString;
function PdfHexString(const S: AnsiString): AnsiString;
function PdfArray(const Items: array of AnsiString): AnsiString;
function PdfDict(const Entries: array of TPixiePdfDictEntry): AnsiString;
function PdfRect(X1, Y1, X2, Y2: Single): AnsiString;

implementation

uses
  {$IFDEF FPC}
  zstream;
  {$ELSE}
  System.ZLib;
  {$ENDIF}

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

function PdfFloat(V: Single): AnsiString;
var
  S: string;
  I: Integer;
begin
  // Format with up to 8 decimal places, no trailing zeros
  S := FormatFloat('0.########', V);
  // Ensure decimal separator is always '.'
  for I := 1 to Length(S) do
    if S[I] = ',' then S[I] := '.';
  Result := AnsiString(S);
end;

function PdfRef(Id: Integer): AnsiString;
begin
  Result := AnsiString(IntToStr(Id)) + ' 0 R';
end;

function PdfName(const S: AnsiString): AnsiString;
begin
  Result := '/' + S;
end;

function OctalEscape(V: Byte): AnsiString;
begin
  SetLength(Result, 4);
  Result[1] := '\';
  Result[2] := AnsiChar(Ord('0') + (V div 64));
  Result[3] := AnsiChar(Ord('0') + (V div 8) mod 8);
  Result[4] := AnsiChar(Ord('0') + V mod 8);
end;

function PdfString(const S: string): AnsiString;
var
  I: Integer;
  C: Char;
  NeedsUnicode: Boolean;
  U: UnicodeString;
  W: Word;
begin
  // Check whether the string contains non-ASCII characters
  NeedsUnicode := False;
  for I := 1 to Length(S) do
    if Ord(S[I]) > 127 then
    begin
      NeedsUnicode := True;
      Break;
    end;

  if NeedsUnicode then
  begin
    // PDF text strings with non-PDFDocEncoding chars must use
    // UTF-16BE with a BOM prefix (PDF spec ISO 32000-1 7.9.2.2)
    U := {$IFDEF FPC}UTF8Decode(S){$ELSE}S{$ENDIF};
    Result := '<FEFF';
    for I := 1 to Length(U) do
    begin
      W := Ord(U[I]);
      Result := Result + AnsiString(IntToHex(W, 4));
    end;
    Result := Result + '>';
  end
  else
  begin
    Result := '(';
    for I := 1 to Length(S) do
    begin
      C := S[I];
      case C of
        '(': Result := Result + '\(';
        ')': Result := Result + '\)';
        '\': Result := Result + '\\';
      else
        Result := Result + AnsiChar(C);
      end;
    end;
    Result := Result + ')';
  end;
end;

function PdfHexString(const S: AnsiString): AnsiString;
var
  I: Integer;
begin
  Result := '<';
  for I := 1 to Length(S) do
    Result := Result + AnsiString(LowerCase(IntToHex(Byte(S[I]), 2)));
  Result := Result + '>';
end;

function PdfArray(const Items: array of AnsiString): AnsiString;
var
  I: Integer;
begin
  Result := '[';
  for I := Low(Items) to High(Items) do
  begin
    if I > Low(Items) then
      Result := Result + ' ';
    Result := Result + Items[I];
  end;
  Result := Result + ']';
end;

function PdfDict(const Entries: array of TPixiePdfDictEntry): AnsiString;
var
  I: Integer;
begin
  Result := '<< ';
  for I := Low(Entries) to High(Entries) do
    Result := Result + PdfName(Entries[I].Key) + ' ' + Entries[I].Value + ' ';
  Result := Result + '>>';
end;

function PdfRect(X1, Y1, X2, Y2: Single): AnsiString;
begin
  Result := PdfArray([PdfFloat(X1), PdfFloat(Y1), PdfFloat(X2), PdfFloat(Y2)]);
end;

// ---------------------------------------------------------------------------
// TPixiePdfDictEntry
// ---------------------------------------------------------------------------

class function TPixiePdfDictEntry.Create(
  const AKey, AValue: AnsiString): TPixiePdfDictEntry;
begin
  Result.Key := AKey;
  Result.Value := AValue;
end;

// ---------------------------------------------------------------------------
// TPixiePdfObject
// ---------------------------------------------------------------------------

constructor TPixiePdfObject.Create(AId: Integer);
begin
  inherited Create;
  FId := AId;
  FDict := TPixiePdfDictEntryList.Create;
  FCompressStream := True;
end;

destructor TPixiePdfObject.Destroy;
begin
  FDict.Free;
  inherited;
end;

procedure TPixiePdfObject.AddEntry(const Key, Value: AnsiString);
begin
  FDict.Add(TPixiePdfDictEntry.Create(Key, Value));
end;

procedure TPixiePdfObject.SetEntry(const Key, Value: AnsiString);
var
  I: Integer;
  Entry: TPixiePdfDictEntry;
begin
  for I := 0 to FDict.Count - 1 do
  begin
    if FDict[I].Key = Key then
    begin
      Entry := FDict[I];
      Entry.Value := Value;
      FDict[I] := Entry;
      Exit;
    end;
  end;
  AddEntry(Key, Value);
end;

function TPixiePdfObject.GetEntry(const Key: AnsiString): AnsiString;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to FDict.Count - 1 do
    if FDict[I].Key = Key then
      Exit(FDict[I].Value);
end;

procedure TPixiePdfObject.SetStream(const Data: TBytes; Compress: Boolean);
begin
  FStream := Data;
  FCompressStream := Compress;
end;

procedure TPixiePdfObject.AppendStream(const Data: TBytes);
var
  OldLen: Integer;
begin
  OldLen := Length(FStream);
  SetLength(FStream, OldLen + Length(Data));
  if Length(Data) > 0 then
    Move(Data[0], FStream[OldLen], Length(Data));
end;

function TPixiePdfObject.HasStream: Boolean;
begin
  Result := Length(FStream) > 0;
end;

function TPixiePdfObject.StreamLength: Integer;
begin
  Result := Length(FStream);
end;

function TPixiePdfObject.StreamData: TBytes;
begin
  Result := FStream;
end;

// ---------------------------------------------------------------------------
// TPixiePdfWriter
// ---------------------------------------------------------------------------

constructor TPixiePdfWriter.Create;
var
  Root, PagesObj: TPixiePdfObject;
begin
  inherited Create;
  FObjects := TPixiePdfObjectList.Create(True);
  FPages := TPixieIntVector.Create;

  // Object 0 is reserved (free entry in xref)
  // Allocate catalog (root) and pages objects
  Root := AllocObject;     // id = 1
  PagesObj := AllocObject; // id = 2

  FRootId := Root.Id;
  FPagesId := PagesObj.Id;

  Root.AddEntry('Type', '/Catalog');
  Root.AddEntry('Pages', PdfRef(FPagesId));

  PagesObj.AddEntry('Type', '/Pages');
end;

destructor TPixiePdfWriter.Destroy;
begin
  FPages.Free;
  FObjects.Free;
  inherited;
end;

function TPixiePdfWriter.AllocObject: TPixiePdfObject;
begin
  // IDs are 1-based (index 0 = id 1, etc.)
  Result := TPixiePdfObject.Create(FObjects.Count + 1);
  FObjects.Add(Result);
end;

function TPixiePdfWriter.AllocPage(Width, Height: Single): TPixiePdfObject;
begin
  Result := AllocObject;
  Result.AddEntry('Type', '/Page');
  Result.AddEntry('Parent', PdfRef(FPagesId));
  Result.AddEntry('MediaBox', PdfRect(0, 0, Width, Height));
  FPages.Add(Result.Id);
end;

function TPixiePdfWriter.CompressData(const Input: TBytes): TBytes;
var
{$IFDEF FPC}
  OutStream: TMemoryStream;
  Compressor: TCompressionStream;
{$ELSE}
  OutBuf: Pointer;
  OutLen: Integer;
{$ENDIF}
begin
  if Length(Input) = 0 then
  begin
    Result := nil;
    Exit;
  end;

{$IFDEF FPC}
  OutStream := TMemoryStream.Create;
  try
    Compressor := TCompressionStream.Create(clDefault, OutStream);
    try
      Compressor.Write(Input[0], Length(Input));
    finally
      Compressor.Free;
    end;
    SetLength(Result, OutStream.Size);
    if OutStream.Size > 0 then
    begin
      OutStream.Position := 0;
      OutStream.Read(Result[0], OutStream.Size);
    end;
  finally
    OutStream.Free;
  end;
{$ELSE}
  ZCompress(@Input[0], Length(Input), OutBuf, OutLen);
  try
    SetLength(Result, OutLen);
    if OutLen > 0 then
      Move(OutBuf^, Result[0], OutLen);
  finally
    FreeMem(OutBuf);
  end;
{$ENDIF}
end;

procedure TPixiePdfWriter.WriteAnsi(Stream: TStream; const S: AnsiString);
begin
  if Length(S) > 0 then
    Stream.Write(S[1], Length(S));
end;

procedure TPixiePdfWriter.WriteObj(Stream: TStream; Obj: TPixiePdfObject;
  var Offsets: TPixieInt64Vector);
var
  I: Integer;
  StreamData, CompressedData: TBytes;
  UseFilter: Boolean;
  Line: AnsiString;
begin
  // Record byte offset for xref
  while Offsets.Count < Obj.Id do
    Offsets.Add(0);
  Offsets[Obj.Id - 1] := Stream.Position;

  // Object header
  Line := AnsiString(IntToStr(Obj.Id)) + ' 0 obj' + #10;
  WriteAnsi(Stream, Line);

  // Determine stream handling
  StreamData := Obj.StreamData;
  UseFilter := False;
  if Obj.HasStream and Obj.CompressStream then
  begin
    CompressedData := CompressData(StreamData);
    if Length(CompressedData) > 0 then
    begin
      StreamData := CompressedData;
      UseFilter := True;
    end;
  end;

  // Dictionary
  WriteAnsi(Stream, '<< ');
  for I := 0 to Obj.FDict.Count - 1 do
  begin
    WriteAnsi(Stream, PdfName(Obj.FDict[I].Key));
    WriteAnsi(Stream, ' ');
    WriteAnsi(Stream, Obj.FDict[I].Value);
    WriteAnsi(Stream, ' ');
  end;

  if Obj.HasStream then
  begin
    if UseFilter then
      WriteAnsi(Stream, '/Filter /FlateDecode ');
    WriteAnsi(Stream, '/Length ' + AnsiString(IntToStr(Length(StreamData))) + ' ');
  end;

  WriteAnsi(Stream, '>>' + #10);

  // Stream
  if Obj.HasStream then
  begin
    WriteAnsi(Stream, 'stream' + #10);
    if Length(StreamData) > 0 then
      Stream.Write(StreamData[0], Length(StreamData));
    WriteAnsi(Stream, #10 + 'endstream' + #10);
  end;

  WriteAnsi(Stream, 'endobj' + #10);
end;

procedure TPixiePdfWriter.Write(Stream: TStream);
var
  I: Integer;
  Offsets: TPixieInt64Vector;
  XRefOffset: Int64;
  KidsStr, Line: AnsiString;
  InfoObj: TPixiePdfObject;
  PagesObj: TPixiePdfObject;
begin
  Offsets := TPixieInt64Vector.Create;
  try
    // Finalize pages object
    PagesObj := FObjects[FPagesId - 1]; // id is 1-based, list is 0-based
    KidsStr := '[';
    for I := 0 to FPages.Count - 1 do
    begin
      if I > 0 then KidsStr := KidsStr + ' ';
      KidsStr := KidsStr + PdfRef(FPages[I]);
    end;
    KidsStr := KidsStr + ']';
    PagesObj.SetEntry('Kids', KidsStr);
    PagesObj.SetEntry('Count', AnsiString(IntToStr(FPages.Count)));

    // Info dictionary
    if (FTitle <> '') or (FAuthor <> '') then
    begin
      InfoObj := AllocObject;
      FInfoId := InfoObj.Id;
      if FTitle <> '' then
        InfoObj.AddEntry('Title', PdfString(FTitle));
      if FAuthor <> '' then
        InfoObj.AddEntry('Author', PdfString(FAuthor));
      InfoObj.AddEntry('Producer', PdfString('Pixie PDF Export'));
      InfoObj.AddEntry('CreationDate', PdfString('D:' +
        FormatDateTime('yyyymmddhhnnss', Now)));
    end;

    // Header
    WriteAnsi(Stream, '%PDF-1.4' + #10);
    // Binary comment to signal binary content
    WriteAnsi(Stream, '%'#$E2#$E3#$CF#$D3 + #10);

    // Write all objects
    for I := 0 to FObjects.Count - 1 do
      WriteObj(Stream, FObjects[I], Offsets);

    // Cross-reference table
    XRefOffset := Stream.Position;
    WriteAnsi(Stream, 'xref' + #10);
    WriteAnsi(Stream, '0 ' + AnsiString(IntToStr(FObjects.Count + 1)) + #10);
    // Entry 0: free
    WriteAnsi(Stream, '0000000000 65535 f '#$0D#$0A);
    for I := 0 to Offsets.Count - 1 do
    begin
      Line := AnsiString(Format('%.10d 00000 n '#$0D#$0A, [Offsets[I]]));
      WriteAnsi(Stream, Line);
    end;

    // Trailer
    WriteAnsi(Stream, 'trailer' + #10);
    WriteAnsi(Stream, '<< /Size ' + AnsiString(IntToStr(FObjects.Count + 1)));
    WriteAnsi(Stream, ' /Root ' + PdfRef(FRootId));
    if FInfoId <> 0 then
      WriteAnsi(Stream, ' /Info ' + PdfRef(FInfoId));
    WriteAnsi(Stream, ' >>' + #10);

    WriteAnsi(Stream, 'startxref' + #10);
    WriteAnsi(Stream, AnsiString(IntToStr(XRefOffset)) + #10);
    WriteAnsi(Stream, '%%EOF' + #10);
  finally
    Offsets.Free;
  end;
end;

end.
