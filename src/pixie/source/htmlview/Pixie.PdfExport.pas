unit Pixie.PdfExport;

// Public API for exporting HTML content to PDF files.
// Works with both Delphi and Free Pascal; no external dependencies
// beyond zlib (ships with both compilers).

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Math, Generics.Collections,
  Pixie.Types, Pixie.Html, Pixie.Utils, Pixie.NativeContainer, Pixie.TrueType, Pixie.PdfWriter,
  Pixie.Canvas.Pdf;

type
  TPixiePdfPageSize = (ppsA4, ppsA3, ppsLetter, ppsLegal, ppsCustom);

  { TPixiePdfMargins }

  TPixiePdfMargins = record
    Left: Single;   // points (1 pt = 1/72 inch)
    Top: Single;
    Right: Single;
    Bottom: Single;
    class function Create(ALeft, ATop, ARight, ABottom: Single): TPixiePdfMargins; static;
  end;

  { TPixiePdfExport }

  TPixiePdfExport = class
  private
    FPageSize: TPixiePdfPageSize;
    FMargins: TPixiePdfMargins;
    FCustomWidth: Single;
    FCustomHeight: Single;
    FTitle: string;
    FAuthor: string;
    FUserCss: string;
    FBaseUrl: string;
    FOnFetchUrl: TPixieFetchUrlEvent;
    procedure GetPageDimensions(out W, H: Single);
  public
    constructor Create;
    destructor Destroy; override;

    procedure SaveToFile(const Html: string; const FileName: string);
    procedure SaveToStream(const Html: string; Stream: TStream);

    property PageSize: TPixiePdfPageSize read FPageSize write FPageSize;
    property Margins: TPixiePdfMargins read FMargins write FMargins;
    property CustomWidth: Single read FCustomWidth write FCustomWidth;
    property CustomHeight: Single read FCustomHeight write FCustomHeight;
    property Title: string read FTitle write FTitle;
    property Author: string read FAuthor write FAuthor;
    property UserCss: string read FUserCss write FUserCss;
    property BaseUrl: string read FBaseUrl write FBaseUrl;
    property OnFetchUrl: TPixieFetchUrlEvent read FOnFetchUrl write FOnFetchUrl;
  end;

implementation

uses
  Pixie.Borders,
  Pixie.MasterCss, Pixie.Document,
  Pixie.RenderItem, Pixie.SvgToPdf,
  // These units register their class variables in initialization sections;
  // without them block/inline layout and grid layout don't work.
  Pixie.RenderBlockContext, Pixie.RenderInlineContext, Pixie.RenderGrid;

type
  TPixiePageBreakList = TList<Single>;

// ---------------------------------------------------------------------------
// TPixiePdfMargins
// ---------------------------------------------------------------------------

class function TPixiePdfMargins.Create(
  ALeft, ATop, ARight, ABottom: Single): TPixiePdfMargins;
begin
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Right := ARight;
  Result.Bottom := ABottom;
end;

// ---------------------------------------------------------------------------
// Page break computation
// ---------------------------------------------------------------------------

const
  // Maximum recursion depth for collecting break candidates in the render
  // tree. Deeper nesting (e.g. body > .document > .container > .section)
  // needs deeper recursion; too deep risks splitting leaf-level content.
  MaxBreakDepth = 3;

// Collect break candidates from direct children of a render item.
// Each candidate is a child's margin-box Top or Bottom — breaking at Top
// puts the child entirely on the next page with its full decoration intact.
// Uses margin-box boundaries so breaks never split border/padding from content.
// Does NOT recurse into children that have borders or padding, since
// splitting inside a decorated container would separate the decoration
// from its content.
procedure CollectBreakCandidates(Ri: TPixieRenderItem;
  Candidates: TPixiePageBreakList; Depth: Integer; OffsetY: Single);
var
  I: Integer;
  Children: TPixieRenderItemList;
  Child: TPixieRenderItem;
  HasDecoration: Boolean;
begin
  Children := Ri.GetChildren;
  for I := 0 to Children.Count - 1 do
  begin
    Child := Children[I];
    if Child.GetSkip then Continue;
    if Child.Pos.Height > 0 then
    begin
      // Use margin-box boundaries so breaks don't split an element's
      // decoration (border/padding/margin) from its content
      Candidates.Add(OffsetY + Child.Top);
      Candidates.Add(OffsetY + Child.Bottom);
    end;
    // Recurse into nested blocks for finer break granularity, but
    // skip containers with visible borders or padding — breaking
    // inside those would split the decoration from the content
    if (Depth < MaxBreakDepth) and (Child.GetChildren.Count > 0) then
    begin
      HasDecoration := (Child.BorderTop > 0) or (Child.BorderBottom > 0) or
                       (Child.PaddingTop > 0) or (Child.PaddingBottom > 0);
      if not HasDecoration then
        CollectBreakCandidates(Child, Candidates, Depth + 1,
          OffsetY + Child.Pos.Y);
    end;
  end;
end;

procedure SortFloatList(List: TPixiePageBreakList);
var
  I, J: Integer;
  Tmp: Single;
begin
  // Simple insertion sort — lists are typically a few hundred items max
  for I := 1 to List.Count - 1 do
  begin
    Tmp := List[I];
    J := I - 1;
    while (J >= 0) and (List[J] > Tmp) do
    begin
      List[J + 1] := List[J];
      Dec(J);
    end;
    List[J + 1] := Tmp;
  end;
end;

// Given a deduplicated sorted list of break candidates and a nominal
// page height, compute the Y offset where each page should start.
// Break candidates are tops and bottoms of block elements; the largest
// candidate <= IdealBreak is chosen so content is not split.
procedure ComputePageBreaks(Candidates: TPixiePageBreakList;
  ContentHeightPx, TotalHeightPx: Single;
  PageStarts: TPixiePageBreakList);
var
  I: Integer;
  PageStart, IdealBreak, SafeBreak: Single;
begin
  // First page always starts at 0
  PageStart := 0;
  PageStarts.Add(0);

  while PageStart + ContentHeightPx < TotalHeightPx do
  begin
    IdealBreak := PageStart + ContentHeightPx;

    // Find the largest candidate <= IdealBreak.
    SafeBreak := IdealBreak;
    for I := Candidates.Count - 1 downto 0 do
    begin
      if Candidates[I] <= IdealBreak then
      begin
        SafeBreak := Candidates[I];
        Break;
      end;
    end;

    // Guard: if no safe break found (single item taller than page),
    // fall back to the ideal break to avoid infinite loop
    if SafeBreak <= PageStart then
      SafeBreak := IdealBreak;

    PageStart := SafeBreak;
    PageStarts.Add(PageStart);
  end;
end;

// ---------------------------------------------------------------------------
// TPixiePdfExport
// ---------------------------------------------------------------------------

constructor TPixiePdfExport.Create;
begin
  inherited Create;
  FPageSize := ppsA4;
  FMargins := TPixiePdfMargins.Create(72, 72, 72, 72); // 1 inch all sides
end;

destructor TPixiePdfExport.Destroy;
begin
  inherited;
end;

procedure TPixiePdfExport.GetPageDimensions(out W, H: Single);
begin
  case FPageSize of
    ppsA4:
    begin
      W := 595.28; // 210mm
      H := 841.89; // 297mm
    end;
    ppsA3:
    begin
      W := 841.89; // 297mm
      H := 1190.55; // 420mm
    end;
    ppsLetter:
    begin
      W := 612;   // 8.5 inch
      H := 792;   // 11 inch
    end;
    ppsLegal:
    begin
      W := 612;   // 8.5 inch
      H := 1008;  // 14 inch
    end;
    ppsCustom:
    begin
      W := FCustomWidth;
      H := FCustomHeight;
    end;
  end;
end;

procedure TPixiePdfExport.SaveToStream(const Html: string; Stream: TStream);
var
  Writer: TPixiePdfWriter;
  FontCache: TPixieTrueTypeFontCache;
  Canvas: TPixiePdfCanvas;
  Container: TPixieNativeContainer;
  Doc: TPixieDocument;
  PageW, PageH: Single;
  ContentWidthPt, ContentHeightPt: Single;
  ContentWidthPx, ContentHeightPx: Single;
  TotalHeightPx: Single;
  PageIdx: Integer;
  ClipPos: TPixiePosition;
  ClipRadius: TPixieBorderRadiuses;
  MarginXPx, MarginYPx: Single;
  PageStart, PageClipH: Single;
  Bottoms, PageStarts: TPixiePageBreakList;
  RootRi: TPixieRenderItem;

  procedure SaveSvgToStream;
  var
    SvgUtf8: UTF8String;
    SvgFontCache: TPixieTrueTypeFontCache;
    SvgWriter: TPixiePdfWriter;
    SvgRenderer: TPixieSvgRenderer;
    SvgW, SvgH, Scale, ImgW, ImgH, ImgX, ImgY: Single;
    ObjId: Integer;
    PageObj, ContentObj: TPixiePdfObject;
    ContentBuf: AnsiString;
    ContentBytes: TBytes;
  begin
    SvgUtf8 := UTF8Encode(Html);
    SvgFontCache := TPixieTrueTypeFontCache.Create([doOwnsValues]);
    SvgWriter := TPixiePdfWriter.Create;
    try
      SvgWriter.Title := FTitle;
      SvgWriter.Author := FAuthor;

      SvgRenderer := TPixieSvgRenderer.Create(SvgWriter, SvgFontCache);
      try
        ObjId := SvgRenderer.RenderToFormXObject(
          @SvgUtf8[1], Length(SvgUtf8), SvgW, SvgH);
      finally
        SvgRenderer.Free;
      end;

      if (ObjId <> 0) and (SvgW > 0) and (SvgH > 0) then
      begin
        ContentWidthPt := PageW - FMargins.Left - FMargins.Right;
        ContentHeightPt := PageH - FMargins.Top - FMargins.Bottom;

        // Fit SVG into content area preserving aspect ratio
        Scale := Min(ContentWidthPt / SvgW, ContentHeightPt / SvgH);
        ImgW := SvgW * Scale;
        ImgH := SvgH * Scale;
        // Centre on page
        ImgX := FMargins.Left + (ContentWidthPt - ImgW) / 2;
        ImgY := FMargins.Top + (ContentHeightPt - ImgH) / 2;

        PageObj := SvgWriter.AllocPage(PageW, PageH);

        // Build content stream: draw Form XObject scaled to fit
        ContentBuf :=
          'q' + #10 +
          PdfFloat(ImgW) + ' 0 0 ' + PdfFloat(ImgH) + ' ' +
          PdfFloat(ImgX) + ' ' + PdfFloat(PageH - ImgY - ImgH) +
          ' cm' + #10 +
          '/Im1 Do' + #10 +
          'Q' + #10;
        SetLength(ContentBytes, Length(ContentBuf));
        Move(ContentBuf[1], ContentBytes[0], Length(ContentBuf));

        ContentObj := SvgWriter.AllocObject;
        ContentObj.SetStream(ContentBytes, True);
        PageObj.AddEntry('Contents', PdfRef(ContentObj.Id));
        PageObj.AddEntry('Resources',
          '<< /XObject << /Im1 ' + PdfRef(ObjId) + ' >> >>');
      end;

      SvgWriter.Write(Stream);
    finally
      SvgWriter.Free;
      SvgFontCache.Free;
    end;
  end;

begin
  GetPageDimensions(PageW, PageH);

  // Standalone SVG — render directly via SVG-to-PDF
  if PixieIsLikelySvg(Html) then
  begin
    SaveSvgToStream;
    Exit;
  end;

  ContentWidthPt := PageW - FMargins.Left - FMargins.Right;
  ContentHeightPt := PageH - FMargins.Top - FMargins.Bottom;

  // Convert to CSS pixels (96 dpi)
  ContentWidthPx := ContentWidthPt * 96.0 / 72.0;
  ContentHeightPx := ContentHeightPt * 96.0 / 72.0;
  MarginXPx := FMargins.Left * 96.0 / 72.0;
  MarginYPx := FMargins.Top * 96.0 / 72.0;

  FontCache := TPixieTrueTypeFontCache.Create([doOwnsValues]);
  Writer := TPixiePdfWriter.Create;
  try
    Writer.Title := FTitle;
    Writer.Author := FAuthor;

    Canvas := TPixiePdfCanvas.Create(Writer, FontCache);
    try
      Container := TPixieNativeContainer.Create(Canvas);
      try
        Container.DefaultFontSize := 16;
        Container.MediaType := mtPrint;
        Container.ViewportWidth := ContentWidthPx;
        Container.ViewportHeight := ContentHeightPx;
        Container.BaseUrl := FBaseUrl;
        Container.OnFetchUrlEvent := FOnFetchUrl;

        // Create and render the document
        Doc := TPixieDocument.CreateFromString(Html, Container,
          PixieMasterCss, FUserCss);
        try
          Canvas.BeginPaint(0);

          // Layout at content width
          Doc.Render(ContentWidthPx);
          TotalHeightPx := Doc.Height;
          if TotalHeightPx <= 0 then
            TotalHeightPx := 1;

          // Compute smart page breaks
          Bottoms := TPixiePageBreakList.Create;
          PageStarts := TPixiePageBreakList.Create;
          try
            if TotalHeightPx > ContentHeightPx then
            begin
              // Walk render tree to find safe break points
              RootRi := TPixieRenderItem(Doc.RootRender);
              if RootRi <> nil then
                CollectBreakCandidates(RootRi, Bottoms, 0, 0);

              SortFloatList(Bottoms);
              ComputePageBreaks(Bottoms, ContentHeightPx,
                TotalHeightPx, PageStarts);
            end
            else
              PageStarts.Add(0);

            // Render each page
            ClipRadius.Init;
            for PageIdx := 0 to PageStarts.Count - 1 do
            begin
              Canvas.BeginPage(PageW, PageH);
              PageStart := PageStarts[PageIdx];

              // Clip height: distance to next page start, or remaining content
              if PageIdx + 1 < PageStarts.Count then
                PageClipH := Min(ContentHeightPx,
                  PageStarts[PageIdx + 1] - PageStart)
              else
                PageClipH := Min(ContentHeightPx,
                  TotalHeightPx - PageStart);

              Canvas.SaveState;

              // Clip to content area
              ClipPos := TPixiePosition.Create(
                MarginXPx, MarginYPx,
                ContentWidthPx, PageClipH);
              Canvas.SetClipRect(ClipPos, ClipRadius);

              // Draw with offset: margin + page scroll
              Doc.Draw(0, MarginXPx, MarginYPx - PageStart, @ClipPos);

              Canvas.RestoreState;
              Canvas.EndPage;
            end;
          finally
            PageStarts.Free;
            Bottoms.Free;
          end;

          Canvas.EndPaint;
        finally
          Doc.Free;
        end;
      finally
        Container.Free;
      end;
    finally
      Canvas.Free;
    end;

    Writer.Write(Stream);
  finally
    Writer.Free;
    FontCache.Free;
  end;
end;

procedure TPixiePdfExport.SaveToFile(const Html: string;
  const FileName: string);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    SaveToStream(Html, Stream);
  finally
    Stream.Free;
  end;
end;

end.
