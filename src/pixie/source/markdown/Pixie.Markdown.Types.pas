unit Pixie.Markdown.Types;

// AST node types for the Markdown parser/writer pipeline.
//
// A single TPixieMdNode class holds all node kinds via a Kind discriminator
// and a flat set of optional fields. This keeps construction and traversal
// simple at the cost of a few unused fields per node — acceptable since
// node counts in real documents stay modest.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Classes, SysUtils, Generics.Collections;

type
  TPixieMdOption = (
    moAllowRawHtml,        // pass HTML through verbatim
    moStripFrontMatter,    // strip --- ... --- YAML at top of document
    moAutoHeadingIds,      // generate id="..." on <h*>
    moGfmTables,           // | a | b | tables
    moGfmStrikethrough,    // ~~text~~
    moGfmTaskLists,        // - [x] item
    moGfmAutolinks         // bare http://example.com URLs
  );
  TPixieMdOptions = set of TPixieMdOption;

const
  DefaultPixieMdOptions = [moAllowRawHtml, moStripFrontMatter,
    moAutoHeadingIds, moGfmTables, moGfmStrikethrough, moGfmTaskLists,
    moGfmAutolinks];

type
  TPixieMdNodeKind = (
    // Block
    mnDocument,
    mnHeading,           // HeadingLevel + HeadingId
    mnParagraph,
    mnBlockQuote,
    mnList,              // ListOrdered + ListStart + ListTight
    mnListItem,          // IsTaskItem + TaskChecked
    mnCodeBlock,         // CodeLang + Literal
    mnHtmlBlock,         // Literal
    mnThematicBreak,
    mnTable,
    mnTableRow,          // IsHeaderRow
    mnTableCell,         // CellAlignment
    // Inline
    mnText,              // Literal
    mnEmph,
    mnStrong,
    mnCodeSpan,          // Literal
    mnLink,              // LinkUrl + LinkTitle
    mnImage,             // LinkUrl + LinkTitle + ImageAlt
    mnLineBreak,         // hard break (<br>)
    mnSoftBreak,         // soft break (newline -> space in HTML)
    mnRawHtml,           // Literal (inline raw HTML)
    mnStrikethrough);

  TPixieMdCellAlign = (
    maNone,
    maLeft,
    maRight,
    maCenter);

  TPixieMdNode = class;
  TPixieMdNodeList = TObjectList<TPixieMdNode>;

  TPixieMdNode = class
  private
    FChildren: TPixieMdNodeList;
    function GetChildren: TPixieMdNodeList;
    function GetChildCount: Integer;
  public
    Kind: TPixieMdNodeKind;

    // Heading
    HeadingLevel: Integer;       // 1-6
    HeadingId: string;

    // List
    ListOrdered: Boolean;
    ListStart: Integer;
    ListTight: Boolean;

    // ListItem (task list)
    IsTaskItem: Boolean;
    TaskChecked: Boolean;

    // CodeBlock
    CodeLang: string;

    // Link / Image
    LinkUrl: string;
    LinkTitle: string;
    ImageAlt: string;            // image only

    // Text / RawHtml / HtmlBlock / CodeBlock / CodeSpan
    Literal: string;

    // TableRow
    IsHeaderRow: Boolean;
    // TableCell
    CellAlignment: TPixieMdCellAlign;

    constructor Create(AKind: TPixieMdNodeKind);
    destructor Destroy; override;

    procedure AddChild(Node: TPixieMdNode);
    function HasChildren: Boolean;

    property Children: TPixieMdNodeList read GetChildren;
    property ChildCount: Integer read GetChildCount;
  end;

implementation

constructor TPixieMdNode.Create(AKind: TPixieMdNodeKind);
begin
  inherited Create;
  Kind := AKind;
  HeadingLevel := 0;
  ListOrdered := False;
  ListStart := 1;
  ListTight := True;
  IsTaskItem := False;
  TaskChecked := False;
  IsHeaderRow := False;
  CellAlignment := maNone;
  FChildren := nil;
end;

destructor TPixieMdNode.Destroy;
begin
  FreeAndNil(FChildren);
  inherited Destroy;
end;

function TPixieMdNode.GetChildren: TPixieMdNodeList;
begin
  if FChildren = nil then
    FChildren := TPixieMdNodeList.Create(True);
  Result := FChildren;
end;

function TPixieMdNode.GetChildCount: Integer;
begin
  if FChildren = nil then
    Result := 0
  else
    Result := FChildren.Count;
end;

function TPixieMdNode.HasChildren: Boolean;
begin
  Result := (FChildren <> nil) and (FChildren.Count > 0);
end;

procedure TPixieMdNode.AddChild(Node: TPixieMdNode);
begin
  Children.Add(Node);
end;

end.
