unit Pixie.Markdown;

// Public Markdown -> HTML conversion API. Runs the full pipeline:
// block parser, inline parser, then HTML writer.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Classes, Pixie.Markdown.Types;

type
  // Re-export so callers only need Pixie.Markdown.
  TPixieMdOption = Pixie.Markdown.Types.TPixieMdOption;
  TPixieMdOptions = Pixie.Markdown.Types.TPixieMdOptions;

function PixieMarkdownToHtml(const Md: string;
  Options: TPixieMdOptions = DefaultPixieMdOptions): string;

function PixieMarkdownToHtmlDocument(const Md: string;
  const Title: string = '';
  Options: TPixieMdOptions = DefaultPixieMdOptions): string;

// GitHub-flavoured default stylesheet for rendered Markdown.
function PixieDefaultMarkdownCss: string;

// Reads a stream from its current position to end as UTF-8, strips a
// leading BOM if present.
function PixieMarkdownReadStream(AStream: TStream): string;

// Reads a UTF-8 encoded Markdown file. Strips a leading BOM if present.
function PixieMarkdownReadFile(const AFileName: string): string;

implementation

uses
  SysUtils,
  Pixie.Markdown.Parser, Pixie.Markdown.InlineParser,
  Pixie.Markdown.HtmlWriter, Pixie.Markdown.Css;

type
  TPixieMdLinkRefMap = Pixie.Markdown.Parser.TPixieMdLinkRefMap;

function PixieMarkdownToHtml(const Md: string;
  Options: TPixieMdOptions): string;
var
  Doc: TPixieMdNode;
  RefDefs: TPixieMdLinkRefMap;
begin
  RefDefs := TPixieMdLinkRefMap.Create;
  try
    Doc := TPixieMdParser.ParseBlocks(Md, RefDefs, Options);
    try
      TPixieMdInlineParser.ParseInlinesIntoBlocks(Doc, RefDefs, Options);
      Result := TPixieMdHtmlWriter.Write(Doc, Options);
    finally
      Doc.Free;
    end;
  finally
    RefDefs.Free;
  end;
end;

function PixieDefaultMarkdownCss: string;
begin
  Result := Pixie.Markdown.Css.PixieDefaultMarkdownCss;
end;

function PixieMarkdownReadStream(AStream: TStream): string;
var
  Bytes: TBytes;
  N: Int64;
begin
  N := AStream.Size - AStream.Position;
  SetLength(Bytes, N);
  if N > 0 then
    AStream.ReadBuffer(Bytes[0], N);
  {$IFDEF FPC}
  // FPC string = UTF-8 AnsiString — use raw bytes directly
  if (N >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    SetString(Result, PAnsiChar(@Bytes[3]), N - 3)
  else if N > 0 then
    SetString(Result, PAnsiChar(@Bytes[0]), N)
  else
    Result := '';
  {$ELSE}
  if (N >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    Result := TEncoding.UTF8.GetString(Bytes, 3, N - 3)
  else
    Result := TEncoding.UTF8.GetString(Bytes);
  {$ENDIF}
end;

function PixieMarkdownReadFile(const AFileName: string): string;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := PixieMarkdownReadStream(Stream);
  finally
    Stream.Free;
  end;
end;

function PixieMarkdownToHtmlDocument(const Md: string;
  const Title: string;
  Options: TPixieMdOptions): string;
var
  T: string;
begin
  if Title <> '' then
    T := '<title>' + PixieMdHtmlEscapeAttr(Title) + '</title>'
  else
    T := '';
  Result :=
    '<!DOCTYPE html><html><head>' + T +
    '<style>' + PixieDefaultMarkdownCss + '</style>' +
    '</head><body>' +
    PixieMarkdownToHtml(Md, Options) +
    '</body></html>';
end;

end.
