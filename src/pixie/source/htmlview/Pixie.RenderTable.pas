unit Pixie.RenderTable;

// Table layout — the table render item owns a table grid and implements
// the CSS table layout algorithm: column width distribution, row height
// calculation, cell placement, captions, and border collapse/separate.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Math,
  Pixie.Types, Pixie.CssLength, Pixie.CssProperties,
  Pixie.Element, Pixie.FormattingContext,
  Pixie.Container, Pixie.RenderItem, Pixie.Table;

type
  { TPixieRenderTable }
  TPixieRenderTable = class(TPixieRenderItem)
  protected
    FGrid: TPixieTableGrid;
    FBorderSpacingX: TPixiePixel;
    FBorderSpacingY: TPixiePixel;
    function _Render(X, Y: TPixiePixel;
      const CbContext: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext;
      SecondPass: Boolean): TPixiePixel; override;
  public
    constructor Create(ASrcEl: TPixieElement); override;
    destructor Destroy; override;
    function Clone: TPixieRenderItem; override;
    function Init: TPixieRenderItem; override;
    procedure DrawChildren(Hdc: PtrUInt; X, Y: TPixiePixel;
      Clip: PPixiePosition; Flag: TPixieDrawFlag;
      ZIndex: Integer); override;
    function GetChildByPoint(X, Y, ClientX, ClientY: TPixiePixel;
      Flag: TPixieDrawFlag; ZIndex: Integer;
      Check: TPixieRenderItemCheckFunc): TPixieElement; override;
    function GetTextByPoint(X, Y: TPixiePixel): TPixieElement; override;
    function GetNearestTextByPoint(X, Y: TPixiePixel): TPixieElement; override;
    function GetDrawVerticalOffset: TPixiePixel; override;
    function GetDrawBottomOffset: TPixiePixel; override;
  end;

  { TPixieRenderTablePart — thead/tbody/tfoot }
  TPixieRenderTablePart = class(TPixieRenderItem)
  public
    constructor Create(ASrcEl: TPixieElement); override;
    function Clone: TPixieRenderItem; override;
  end;

  { TPixieRenderTableRow — tr }
  TPixieRenderTableRow = class(TPixieRenderItem)
  public
    constructor Create(ASrcEl: TPixieElement); override;
    function Clone: TPixieRenderItem; override;
    procedure GetInlineBoxes(Boxes: TPixiePositionVector); override;
  end;

implementation

uses
  SysUtils,
  Pixie.StringId, Pixie.Utils,
  Pixie.Document;

procedure ApplyColWidths(TableEl: TPixieElement; Grid: TPixieTableGrid);
var
  I, J, ColIdx, Span, K, Code: Integer;
  Child, ColEl: TPixieElement;
  WidthStr, Trimmed: string;
  X: Single;
  IsPct: Boolean;
  Len: TPixieCssLength;
begin
  ColIdx := 0;
  for I := 0 to TableEl.Children.Count - 1 do
  begin
    Child := TableEl.Children[I];
    if Child.GetTag <> Ord(psid_colgroup) then
      Continue;

    for J := 0 to Child.Children.Count - 1 do
    begin
      ColEl := Child.Children[J];
      if ColEl.GetTag <> Ord(psid_col) then
        Continue;

      Span := StrToIntDef(ColEl.GetAttr('span', '1'), 1);
      if Span < 1 then
        Span := 1;

      WidthStr := ColEl.GetAttr('width');
      if WidthStr <> '' then
      begin
        Trimmed := PixieTrim(WidthStr);
        IsPct := False;
        if (Trimmed <> '') and (Trimmed[Length(Trimmed)] = '%') then
        begin
          IsPct := True;
          Trimmed := Copy(Trimmed, 1, Length(Trimmed) - 1);
        end;
        Trimmed := PixieExtractFloat(Trimmed);
        System.Val(Trimmed, X, Code);
        if Code = 0 then
        begin
          if IsPct then
            Len := TPixieCssLength.Create(X, cssUnitsPercentage)
          else
            Len := TPixieCssLength.Create(X, cssUnitsPx);
          for K := 0 to Span - 1 do
            if (ColIdx + K < Grid.ColsCount) and
               Grid.GetColumnPtr(ColIdx + K)^.CssWidth.IsPredefined then
              Grid.GetColumnPtr(ColIdx + K)^.CssWidth := Len;
        end;
      end;

      ColIdx := ColIdx + Span;
    end;
  end;
end;

{ TPixieRenderTable }

constructor TPixieRenderTable.Create(ASrcEl: TPixieElement);
begin
  inherited Create(ASrcEl);
  FGrid := nil;
  FBorderSpacingX := 0;
  FBorderSpacingY := 0;
end;

destructor TPixieRenderTable.Destroy;
begin
  FGrid.Free;
  inherited;
end;

function TPixieRenderTable.Clone: TPixieRenderItem;
begin
  Result := TPixieRenderTable.Create(FElement);
end;

function TPixieRenderTable.Init: TPixieRenderItem;
var
  I: Integer;
  El, NewChild: TPixieRenderItem;
  Fm: TPixieFontMetrics;
  Doc: TPixieDocument;

  procedure ProcessCell(Row: TPixieRenderItem; CellIdx: Integer);
  var
    C, NC: TPixieRenderItem;
    Cs, Rs: Integer;
    B: TPixieMargins;
  begin
    C := Row.FChildren[CellIdx];
    NC := C.Init;
    if NC <> C then
    begin
      Row.FChildren.OwnsObjects := False;
      Row.FChildren[CellIdx] := NC;
      Row.FChildren.OwnsObjects := True;
      C.Free;
      C := NC;
    end;
    Cs := StrToIntDef(C.SrcEl.GetAttr('colspan', '1'), 1);
    Rs := StrToIntDef(C.SrcEl.GetAttr('rowspan', '1'), 1);
    B := C.GetBorders;
    FGrid.AddCell(C, Cs, Rs, B, C.SrcEl.Css.CssWidth, C.SrcEl.Css.CssHeight);
  end;

  procedure ProcessRow(Row: TPixieRenderItem);
  var
    Idx: Integer;
  begin
    FGrid.BeginRow(Row, Row.SrcEl.Css.CssHeight);
    for Idx := 0 to Row.FChildren.Count - 1 do
    begin
      if Row.FChildren[Idx].SrcEl.Css.Display = displayTableCell then
        ProcessCell(Row, Idx);
    end;
  end;

  procedure ProcessSection(Section: TPixieRenderItem);
  var
    Idx: Integer;
  begin
    for Idx := 0 to Section.FChildren.Count - 1 do
    begin
      if Section.FChildren[Idx].SrcEl.Css.Display = displayTableRow then
        ProcessRow(Section.FChildren[Idx]);
    end;
  end;

begin
  FGrid := TPixieTableGrid.Create;

  // Pass 1: thead sections
  for I := 0 to FChildren.Count - 1 do
    if FChildren[I].SrcEl.Css.Display = displayTableHeaderGroup then
      ProcessSection(FChildren[I]);

  // Pass 2: tbody sections, bare rows, and captions
  for I := 0 to FChildren.Count - 1 do
  begin
    El := FChildren[I];
    if El.SrcEl.Css.Display = displayTableRowGroup then
      ProcessSection(El)
    else if El.SrcEl.Css.Display = displayTableRow then
      ProcessRow(El)
    else if El.SrcEl.Css.Display = displayTableCaption then
    begin
      NewChild := El.Init;
      if NewChild <> El then
      begin
        FChildren.OwnsObjects := False;
        FChildren[I] := NewChild;
        FChildren.OwnsObjects := True;
        El.Free;
      end;
      FGrid.GetCaptions.Add(NewChild);
    end;
  end;

  // Pass 3: tfoot sections
  for I := 0 to FChildren.Count - 1 do
    if FChildren[I].SrcEl.Css.Display = displayTableFooterGroup then
      ProcessSection(FChildren[I]);

  FGrid.Finish;

  // Apply <col> width attributes to grid columns
  ApplyColWidths(SrcEl, FGrid);

  // Compute border spacing
  if SrcEl.Css.BorderCollapse = bcSeparate then
  begin
    Fm := Css.FontMetrics;
    Assert(SrcEl.GetDocument is TPixieDocument);
    Doc := TPixieDocument(SrcEl.GetDocument);
    FBorderSpacingX := Doc.ToPixels(SrcEl.Css.CssBorderSpacingX, Fm, 0);
    FBorderSpacingY := Doc.ToPixels(SrcEl.Css.CssBorderSpacingY, Fm, 0);
  end
  else
  begin
    FBorderSpacingX := 0;
    FBorderSpacingY := 0;
  end;

  SrcEl.AddRender(Self);
  Result := Self;
end;

// --- _Render ---

function TPixieRenderTable._Render(X, Y: TPixiePixel;
  const CbContext: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext;
  SecondPass: Boolean): TPixiePixel;
var
  SelfSize: TPixieContainingBlockContext;
  TableWidthSpacing: TPixiePixel;
  Col, Row: Integer;
  Cell: PPixieTableCell;
  CellWidth: TPixiePixel;
  SpanCol, SpanRow: Integer;
  MinTotalWidth, MaxTotalWidth: TPixiePixel;
  TableWidth, MinTableWidth, MaxTableWidth: TPixiePixel;
  RowSpanFound: Boolean;
  H: TPixiePixel;
  TableHeightSpacing: TPixiePixel;
  BlockHeight, MinHeight, MinimumTableHeight: TPixiePixel;
  TableHeight: TPixiePixel;
  TopCaptions, BottomCaptions: TPixiePixel;
  I: Integer;
  Caption: TPixieRenderItem;
  ColRec: TPixieTableColumn;
  RowRec: TPixieTableRow;
  RowTopY, RowWidth, CellMinH: TPixiePixel;
  J: Integer;
  Part, FirstTr, LastTr: TPixieRenderItem;
begin
  if FGrid = nil then
    Exit(0);

  SelfSize := CalculateContainingBlockContext(CbContext);

  // Calculate table horizontal spacing
  TableWidthSpacing := 0;
  if SrcEl.Css.BorderCollapse = bcSeparate then
    TableWidthSpacing := FBorderSpacingX * (FGrid.ColsCount + 1)
  else
  begin
    if FGrid.ColsCount > 0 then
    begin
      TableWidthSpacing := TableWidthSpacing -
        Min(BorderLeft, FGrid.GetColumn(0).BorderLeft);
      TableWidthSpacing := TableWidthSpacing -
        Min(BorderRight, FGrid.GetColumn(FGrid.ColsCount - 1).BorderRight);
    end;
    for Col := 1 to FGrid.ColsCount - 1 do
      TableWidthSpacing := TableWidthSpacing -
        Min(FGrid.GetColumn(Col).BorderLeft,
            FGrid.GetColumn(Col - 1).BorderRight);
  end;

  // Calculate min/max cell widths
  if (FGrid.ColsCount = 1) and (SelfSize.Width.ValueType <> cbcAuto) then
  begin
    for Row := 0 to FGrid.RowsCount - 1 do
    begin
      Cell := FGrid.GetCell(0, Row);
      if (Cell <> nil) and (Cell^.El <> nil) then
      begin
        Assert(TObject(Cell^.El) is TPixieRenderItem);
        Cell^.MinWidth := TPixieRenderItem(Cell^.El).Render(0, 0,
          SelfSize.NewWidth(SelfSize.RenderWidth.Value - TableWidthSpacing), FmtCtx);
        Cell^.MaxWidth := Cell^.MinWidth;
        TPixieRenderItem(Cell^.El).FPos.Width :=
          Cell^.MinWidth - TPixieRenderItem(Cell^.El).ContentOffsetLeft -
          TPixieRenderItem(Cell^.El).ContentOffsetRight;
      end;
    end;
  end
  else
  begin
    for Row := 0 to FGrid.RowsCount - 1 do
    begin
      for Col := 0 to FGrid.ColsCount - 1 do
      begin
        Cell := FGrid.GetCell(Col, Row);
        if (Cell <> nil) and (Cell^.El <> nil) then
        begin
          ColRec := FGrid.GetColumn(Col);
          if (not ColRec.CssWidth.IsPredefined) and
             (ColRec.CssWidth.Units <> cssUnitsPercentage) then
          begin
            CellWidth := ColRec.CssWidth.CalcPercent(SelfSize.Width.Value);
            H := TPixieRenderItem(Cell^.El).Render(0, 0,
              SelfSize.NewWidth(CellWidth), FmtCtx);
            Cell^.MinWidth := Max(CellWidth, H);
            Cell^.MaxWidth := Cell^.MinWidth;
            TPixieRenderItem(Cell^.El).FPos.Width :=
              Cell^.MinWidth - TPixieRenderItem(Cell^.El).ContentOffsetLeft -
              TPixieRenderItem(Cell^.El).ContentOffsetRight;
          end
          else
          begin
            // Min content width
            Cell^.MinWidth := TPixieRenderItem(Cell^.El).Render(0, 0,
              SelfSize.NewWidth(TPixieRenderItem(Cell^.El).ContentOffsetWidth,
                SizeModeContent), FmtCtx);
            // Max content width
            Cell^.MaxWidth := TPixieRenderItem(Cell^.El).Render(0, 0,
              SelfSize.NewWidth(SelfSize.RenderWidth.Value - TableWidthSpacing,
                SizeModeContent), FmtCtx);
          end;
        end;
      end;
    end;
  end;

  // Per-column min/max from single-span cells
  for Col := 0 to FGrid.ColsCount - 1 do
  begin
    ColRec := FGrid.GetColumn(Col);
    ColRec.MaxWidth := 0;
    ColRec.MinWidth := 0;
    for Row := 0 to FGrid.RowsCount - 1 do
    begin
      Cell := FGrid.GetCell(Col, Row);
      if (Cell <> nil) and (Cell^.El <> nil) and (Cell^.Colspan <= 1) then
      begin
        ColRec.MaxWidth := Max(ColRec.MaxWidth, Cell^.MaxWidth);
        ColRec.MinWidth := Max(ColRec.MinWidth, Cell^.MinWidth);
      end;
    end;
    FGrid.SetColumn(Col, ColRec);
  end;

  // Colspan distribution
  for Col := 0 to FGrid.ColsCount - 1 do
  begin
    for Row := 0 to FGrid.RowsCount - 1 do
    begin
      Cell := FGrid.GetCell(Col, Row);
      if (Cell <> nil) and (Cell^.El <> nil) and (Cell^.Colspan > 1) then
      begin
        MaxTotalWidth := FGrid.GetColumn(Col).MaxWidth;
        MinTotalWidth := FGrid.GetColumn(Col).MinWidth;
        for I := Col + 1 to Col + Cell^.Colspan - 1 do
        begin
          if I < FGrid.ColsCount then
          begin
            MaxTotalWidth := MaxTotalWidth + FGrid.GetColumn(I).MaxWidth;
            MinTotalWidth := MinTotalWidth + FGrid.GetColumn(I).MinWidth;
          end;
        end;
        if MinTotalWidth < Cell^.MinWidth then
          FGrid.DistributeMinWidth(Cell^.MinWidth - MinTotalWidth,
            Col, Col + Cell^.Colspan - 1);
        if MaxTotalWidth < Cell^.MaxWidth then
          FGrid.DistributeMaxWidth(Cell^.MaxWidth - MaxTotalWidth,
            Col, Col + Cell^.Colspan - 1);
      end;
    end;
  end;

  // Calculate table width
  TableWidth := 0;
  MinTableWidth := 0;
  MaxTableWidth := 0;

  if SelfSize.Width.ValueType = cbcAbsolute then
    TableWidth := FGrid.CalcTableWidth(
      SelfSize.RenderWidth.Value - TableWidthSpacing, False,
      SrcEl.Css.TableLayout = tlFixed,
      MinTableWidth, MaxTableWidth)
  else
    TableWidth := FGrid.CalcTableWidth(
      SelfSize.RenderWidth.Value - TableWidthSpacing,
      SelfSize.Width.ValueType = cbcAuto,
      SrcEl.Css.TableLayout = tlFixed,
      MinTableWidth, MaxTableWidth);

  MinTableWidth := MinTableWidth + TableWidthSpacing;
  MaxTableWidth := MaxTableWidth + TableWidthSpacing;
  TableWidth := TableWidth + TableWidthSpacing;
  FGrid.CalcHorizontalPositions(FBorders, SrcEl.Css.BorderCollapse,
    FBorderSpacingX);

  RowSpanFound := False;

  // Render cells with computed width
  for Row := 0 to FGrid.RowsCount - 1 do
  begin
    RowRec := FGrid.GetRow(Row);
    RowRec.Height := 0;
    FGrid.SetRow(Row, RowRec);

    for Col := 0 to FGrid.ColsCount - 1 do
    begin
      Cell := FGrid.GetCell(Col, Row);
      if (Cell <> nil) and (Cell^.El <> nil) then
      begin
        SpanCol := Col + Cell^.Colspan - 1;
        if SpanCol >= FGrid.ColsCount then
          SpanCol := FGrid.ColsCount - 1;
        CellWidth := FGrid.GetColumn(SpanCol).Right - FGrid.GetColumn(Col).Left;

        TPixieRenderItem(Cell^.El).Render(FGrid.GetColumn(Col).Left, 0,
          SelfSize.NewWidth(CellWidth), FmtCtx, True);
        TPixieRenderItem(Cell^.El).FPos.Width :=
          CellWidth - TPixieRenderItem(Cell^.El).ContentOffsetLeft -
          TPixieRenderItem(Cell^.El).ContentOffsetRight;

        // Apply cell CSS height as minimum (border-box equivalent,
        // because cell placement subtracts ContentOffset from Row.Height)
        CellMinH := 0;
        if (not Cell^.CssHeight.IsPredefined) and
           (Cell^.CssHeight.Units <> cssUnitsPercentage) then
        begin
          CellMinH := Cell^.CssHeight.Val;
          // In quirks mode, height on table cells acts as border-box
          // (includes padding); in standards mode, add padding+border
          if (TPixieDocument(SrcEl.GetDocument).Mode <> dmQuirks) and
             (TPixieRenderItem(Cell^.El).Css.BoxSizing <> bxBorderBox) then
            CellMinH := CellMinH +
              TPixieRenderItem(Cell^.El).ContentOffsetHeight;
        end;

        if Cell^.Rowspan <= 1 then
        begin
          RowRec := FGrid.GetRow(Row);
          RowRec.Height := Max(RowRec.Height,
            Max(TPixieRenderItem(Cell^.El).Height, CellMinH));
          FGrid.SetRow(Row, RowRec);
        end
        else
          RowSpanFound := True;
      end;
    end;
  end;

  // Handle rowspan heights
  if RowSpanFound then
  begin
    for Col := 0 to FGrid.ColsCount - 1 do
    begin
      for Row := 0 to FGrid.RowsCount - 1 do
      begin
        Cell := FGrid.GetCell(Col, Row);
        if (Cell <> nil) and (Cell^.El <> nil) then
        begin
          SpanRow := Row + Cell^.Rowspan - 1;
          if SpanRow >= FGrid.RowsCount then
            SpanRow := FGrid.RowsCount - 1;
          if SpanRow <> Row then
          begin
            H := 0;
            for I := Row to SpanRow do
              H := H + FGrid.GetRow(I).Height;
            if H < TPixieRenderItem(Cell^.El).Height then
            begin
              RowRec := FGrid.GetRow(SpanRow);
              RowRec.Height := RowRec.Height +
                TPixieRenderItem(Cell^.El).Height - H;
              FGrid.SetRow(SpanRow, RowRec);
            end;
          end;
        end;
      end;
    end;
  end;

  // Vertical spacing
  TableHeightSpacing := 0;
  if SrcEl.Css.BorderCollapse = bcSeparate then
    TableHeightSpacing := FBorderSpacingY * (FGrid.RowsCount + 1)
  else
  begin
    if FGrid.RowsCount > 0 then
    begin
      TableHeightSpacing := TableHeightSpacing -
        Min(BorderTop, FGrid.GetRow(0).BorderTop);
      TableHeightSpacing := TableHeightSpacing -
        Min(BorderBottom, FGrid.GetRow(FGrid.RowsCount - 1).BorderBottom);
    end;
    for Row := 1 to FGrid.RowsCount - 1 do
      TableHeightSpacing := TableHeightSpacing -
        Min(FGrid.GetRow(Row).BorderTop, FGrid.GetRow(Row - 1).BorderBottom);
  end;

  // Calculate block height
  BlockHeight := 0;
  if (SelfSize.Height.ValueType <> cbcAuto) and (SelfSize.Height.Value > 0) then
    BlockHeight := SelfSize.Height.Value - (FPadding.Height + FBorders.Height);

  // Calculate minimum height
  MinHeight := 0;
  if (not SrcEl.Css.CssMinHeight.IsPredefined) and
     (SrcEl.Css.CssMinHeight.Units = cssUnitsPercentage) then
    MinHeight := SrcEl.Css.CssMinHeight.CalcPercent(CbContext.Height.Value)
  else
    MinHeight := SrcEl.Css.CssMinHeight.Val;

  MinimumTableHeight := Max(BlockHeight, MinHeight);

  FGrid.CalcRowsHeight(MinimumTableHeight - TableHeightSpacing, FBorderSpacingY);
  FGrid.CalcVerticalPositions(FBorders, SrcEl.Css.BorderCollapse, FBorderSpacingY);

  TableHeight := 0;

  // Place cells vertically
  for Col := 0 to FGrid.ColsCount - 1 do
  begin
    for Row := 0 to FGrid.RowsCount - 1 do
    begin
      Cell := FGrid.GetCell(Col, Row);
      if (Cell <> nil) and (Cell^.El <> nil) then
      begin
        SpanRow := Row + Cell^.Rowspan - 1;
        if SpanRow >= FGrid.RowsCount then
          SpanRow := FGrid.RowsCount - 1;
        TPixieRenderItem(Cell^.El).FPos.Y :=
          FGrid.GetRow(Row).Top + TPixieRenderItem(Cell^.El).ContentOffsetTop;
        TPixieRenderItem(Cell^.El).FPos.Height :=
          FGrid.GetRow(SpanRow).Bottom - FGrid.GetRow(Row).Top -
          TPixieRenderItem(Cell^.El).ContentOffsetTop -
          TPixieRenderItem(Cell^.El).ContentOffsetBottom;
        TableHeight := Max(TableHeight, FGrid.GetRow(SpanRow).Bottom);
        TPixieRenderItem(Cell^.El).ApplyVerticalAlign;
      end;
    end;
  end;

  if SrcEl.Css.BorderCollapse = bcCollapse then
  begin
    if FGrid.RowsCount > 0 then
      TableHeight := TableHeight -
        Min(BorderBottom, FGrid.GetRow(FGrid.RowsCount - 1).BorderBottom);
  end
  else
    TableHeight := TableHeight + FBorderSpacingY;

  // Render captions
  TopCaptions := -BorderTop;
  for I := 0 to FGrid.GetCaptions.Count - 1 do
  begin
    Assert(TObject(FGrid.GetCaptions[I]) is TPixieRenderItem);
    Caption := TPixieRenderItem(FGrid.GetCaptions[I]);
    if Caption.Css.CaptionSide = csTop then
    begin
      Caption.Render(-BorderLeft, TopCaptions,
        SelfSize.NewWidth(TableWidth + BorderLeft + BorderRight), FmtCtx);
      TopCaptions := TopCaptions + Caption.Height;
    end;
  end;

  if TopCaptions <> 0 then
  begin
    TopCaptions := TopCaptions + BorderTop;
    FGrid.TopCaptionsHeight := TopCaptions;

    // Move cells down
    for Row := 0 to FGrid.RowsCount - 1 do
    begin
      RowRec := FGrid.GetRow(Row);
      if RowRec.ElRow <> nil then
      begin
        Assert(TObject(RowRec.ElRow) is TPixieRenderItem);
        TPixieRenderItem(RowRec.ElRow).FPos.Y :=
          TPixieRenderItem(RowRec.ElRow).FPos.Y + TopCaptions;
      end;
      for Col := 0 to FGrid.ColsCount - 1 do
      begin
        Cell := FGrid.GetCell(Col, Row);
        if (Cell <> nil) and (Cell^.El <> nil) then
          TPixieRenderItem(Cell^.El).FPos.Y :=
            TPixieRenderItem(Cell^.El).FPos.Y + TopCaptions;
      end;
    end;
  end;

  BottomCaptions := 0;
  for I := 0 to FGrid.GetCaptions.Count - 1 do
  begin
    Caption := TPixieRenderItem(FGrid.GetCaptions[I]);
    if Caption.Css.CaptionSide = csBottom then
    begin
      Caption.Render(-BorderLeft,
        TableHeight + TopCaptions + BottomCaptions,
        SelfSize.NewWidth(TableWidth + BorderLeft + BorderRight), FmtCtx);
      BottomCaptions := BottomCaptions + Caption.Height;
    end;
  end;
  FGrid.BottomCaptionsHeight := BottomCaptions;

  // Position tr render items (FPos relative to table content area)
  if (FGrid.ColsCount > 0) and (FGrid.RowsCount > 0) then
  begin
    if SrcEl.Css.BorderCollapse = bcSeparate then
    begin
      // In separate mode, rows are inset by border-spacing from the table edge.
      // Use grid positions which already account for border-spacing.
      RowWidth := FGrid.GetColumn(FGrid.ColsCount - 1).Right -
        FGrid.GetColumn(0).Left;
      for Row := 0 to FGrid.RowsCount - 1 do
      begin
        RowRec := FGrid.GetRow(Row);
        if RowRec.ElRow <> nil then
        begin
          TPixieRenderItem(RowRec.ElRow).FPos.X := FBorderSpacingX;
          TPixieRenderItem(RowRec.ElRow).FPos.Y := TopCaptions + RowRec.Top;
          TPixieRenderItem(RowRec.ElRow).FPos.Width := RowWidth;
          TPixieRenderItem(RowRec.ElRow).FPos.Height := RowRec.Height;
        end;
      end;
    end
    else
    begin
      // Collapsed mode: sum of column widths, stacked from top
      RowWidth := 0;
      for Col := 0 to FGrid.ColsCount - 1 do
        RowWidth := RowWidth + FGrid.GetColumn(Col).Width;
      RowTopY := TopCaptions;
      for Row := 0 to FGrid.RowsCount - 1 do
      begin
        RowRec := FGrid.GetRow(Row);
        if RowRec.ElRow <> nil then
        begin
          TPixieRenderItem(RowRec.ElRow).FPos.X := 0;
          TPixieRenderItem(RowRec.ElRow).FPos.Y := RowTopY;
          TPixieRenderItem(RowRec.ElRow).FPos.Width := RowWidth;
          TPixieRenderItem(RowRec.ElRow).FPos.Height := RowRec.Height;
        end;
        RowTopY := RowTopY + RowRec.Height;
      end;
    end;
  end;

  // Position tbody/thead/tfoot render items from their child tr rows
  for I := 0 to FChildren.Count - 1 do
  begin
    Part := FChildren[I];
    if Part.SrcEl.Css.Display in [displayTableRowGroup,
       displayTableHeaderGroup, displayTableFooterGroup] then
    begin
      // Find first and last tr children (skip non-row children like text nodes)
      FirstTr := nil;
      LastTr := nil;
      for J := 0 to Part.GetChildren.Count - 1 do
      begin
        if Part.GetChildren[J].SrcEl.Css.Display = displayTableRow then
        begin
          if FirstTr = nil then
            FirstTr := Part.GetChildren[J];
          LastTr := Part.GetChildren[J];
        end;
      end;
      if FirstTr <> nil then
      begin
        Part.FPos.X := FirstTr.FPos.X;
        Part.FPos.Y := FirstTr.FPos.Y;
        Part.FPos.Width := FirstTr.FPos.Width;
        Part.FPos.Height := (LastTr.FPos.Y + LastTr.FPos.Height) - FirstTr.FPos.Y;
      end;
    end;
  end;

  FPos.MoveTo(X + ContentOffsetLeft, Y + ContentOffsetTop);
  FPos.Width := TableWidth;
  FPos.Height := TableHeight + TopCaptions + BottomCaptions;

  if SelfSize.Width.ValueType <> cbcAbsolute then
  begin
    if FGrid.HasPercentColumns then
      Result := TableWidth + ContentOffsetWidth
    else
      Result := Min(TableWidth, MaxTableWidth) + ContentOffsetWidth;
  end
  else
    Result := TableWidth + ContentOffsetWidth;
end;

// --- DrawChildren ---

procedure TPixieRenderTable.DrawChildren(Hdc: PtrUInt; X, Y: TPixiePixel;
  Clip: PPixiePosition; Flag: TPixieDrawFlag;
  ZIndex: Integer);
var
  P: TPixiePosition;
  Row, Col, I: Integer;
  Cell: PPixieTableCell;
  Caption: TPixieRenderItem;
  RowRec: TPixieTableRow;
begin
  if FGrid = nil then
    Exit;

  P := FPos;
  P.X := P.X + X;
  P.Y := P.Y + Y;

  // Draw captions
  for I := 0 to FGrid.GetCaptions.Count - 1 do
  begin
    Assert(TObject(FGrid.GetCaptions[I]) is TPixieRenderItem);
    Caption := TPixieRenderItem(FGrid.GetCaptions[I]);
    if Flag = dfBlock then
      Caption.SrcEl.Draw(Hdc, P.X, P.Y, Clip, Caption);
    Caption.DrawChildren(Hdc, P.X, P.Y, Clip, Flag, ZIndex);
  end;

  // Draw row backgrounds, then cells
  for Row := 0 to FGrid.RowsCount - 1 do
  begin
    RowRec := FGrid.GetRow(Row);
    if Flag = dfBlock then
    begin
      if RowRec.ElRow <> nil then
      begin
        Assert(TObject(RowRec.ElRow) is TPixieRenderItem);
        TPixieRenderItem(RowRec.ElRow).SrcEl.DrawBackground(
          Hdc, P.X, P.Y, Clip, TPixieRenderItem(RowRec.ElRow));
      end;
    end;
    for Col := 0 to FGrid.ColsCount - 1 do
    begin
      Cell := FGrid.GetCell(Col, Row);
      if (Cell <> nil) and (Cell^.El <> nil) then
      begin
        Assert(TObject(Cell^.El) is TPixieRenderItem);
        if Flag = dfBlock then
          TPixieRenderItem(Cell^.El).SrcEl.Draw(
            Hdc, P.X, P.Y, Clip, TPixieRenderItem(Cell^.El));
        TPixieRenderItem(Cell^.El).DrawChildren(
          Hdc, P.X, P.Y, Clip, Flag, ZIndex);
      end;
    end;
  end;
end;

// --- GetChildByPoint ---
// Same grid-iteration approach as DrawChildren: iterate cells and captions
// directly, bypassing the tbody/tr hierarchy, because cell FPos is relative
// to the table content area.

function TPixieRenderTable.GetChildByPoint(X, Y, ClientX, ClientY: TPixiePixel;
  Flag: TPixieDrawFlag; ZIndex: Integer;
  Check: TPixieRenderItemCheckFunc): TPixieElement;
var
  LocalX, LocalY, ChildX, ChildY: TPixiePixel;
  Row, Col, I: Integer;
  Cell: PPixieTableCell;
  Caption: TPixieRenderItem;
  CellRi: TPixieRenderItem;
  Ret: TPixieElement;
begin
  Result := nil;
  if FGrid = nil then Exit;

  if FElement.Css.Overflow > ovVisible then
    if not FPos.IsPointInside(X, Y) then
      Exit;

  // Transform to table content area coordinates
  LocalX := X - FPos.X + GetScrollLeft;
  LocalY := Y - FPos.Y + GetScrollTop;

  // Check captions (reverse order — top-most first)
  for I := FGrid.GetCaptions.Count - 1 downto 0 do
  begin
    Caption := TPixieRenderItem(FGrid.GetCaptions[I]);
    ChildX := LocalX;
    ChildY := LocalY;
    if Caption.SrcEl.Css.HasTransform then
      Caption.MapPointInverse(ChildX, ChildY);
    Ret := Caption.GetElementByPoint(ChildX, ChildY,
      ClientX, ClientY, Check);
    if Ret <> nil then Exit(Ret);
  end;

  // Check cells directly (bypassing tbody/tr hierarchy)
  for Row := FGrid.RowsCount - 1 downto 0 do
  begin
    for Col := FGrid.ColsCount - 1 downto 0 do
    begin
      Cell := FGrid.GetCell(Col, Row);
      if (Cell <> nil) and (Cell^.El <> nil) then
      begin
        CellRi := TPixieRenderItem(Cell^.El);
        ChildX := LocalX;
        ChildY := LocalY;
        if CellRi.SrcEl.Css.HasTransform then
          CellRi.MapPointInverse(ChildX, ChildY);
        Ret := CellRi.GetElementByPoint(ChildX, ChildY,
          ClientX, ClientY, Check);
        if Ret <> nil then Exit(Ret);
        if CellRi.IsPointInside(ChildX, ChildY) then
        begin
          if (not Assigned(Check)) or Check(CellRi) then
            Exit(CellRi.SrcEl);
        end;
      end;
    end;
  end;
end;

// --- GetTextByPoint ---
// Iterate cells directly from the grid (like DrawChildren) because cell
// FPos is relative to the table content area, not to the parent tr/tbody.
// The generic implementation walks tbody -> tr -> td and over-subtracts
// coordinates at each level, returning wrong text nodes.

function TPixieRenderTable.GetTextByPoint(X, Y: TPixiePixel): TPixieElement;
var
  LocalX, LocalY, ChildX, ChildY: TPixiePixel;
  Row, Col, I: Integer;
  Cell: PPixieTableCell;
  Caption, CellRi: TPixieRenderItem;
  Ret: TPixieElement;
begin
  Result := nil;
  if not IsVisible then Exit;
  if FGrid = nil then Exit;

  if FElement.Css.Overflow > ovVisible then
    if not FPos.IsPointInside(X, Y) then
      Exit;

  // Transform to table content area coordinates
  LocalX := X - FPos.X + GetScrollLeft;
  LocalY := Y - FPos.Y + GetScrollTop;

  // Check captions
  for I := FGrid.GetCaptions.Count - 1 downto 0 do
  begin
    Caption := TPixieRenderItem(FGrid.GetCaptions[I]);
    ChildX := LocalX;
    ChildY := LocalY;
    if Caption.SrcEl.Css.HasTransform then
      Caption.MapPointInverse(ChildX, ChildY);
    Ret := Caption.GetTextByPoint(ChildX, ChildY);
    if Ret <> nil then
      Exit(Ret);
  end;

  // Check cells directly (bypassing tbody/tr hierarchy)
  for Row := FGrid.RowsCount - 1 downto 0 do
  begin
    for Col := FGrid.ColsCount - 1 downto 0 do
    begin
      Cell := FGrid.GetCell(Col, Row);
      if (Cell <> nil) and (Cell^.El <> nil) then
      begin
        CellRi := TPixieRenderItem(Cell^.El);
        ChildX := LocalX;
        ChildY := LocalY;
        if CellRi.SrcEl.Css.HasTransform then
          CellRi.MapPointInverse(ChildX, ChildY);
        Ret := CellRi.GetTextByPoint(ChildX, ChildY);
        if Ret <> nil then
          Exit(Ret);
      end;
    end;
  end;
end;

// --- GetNearestTextByPoint ---
// Same approach: iterate cells from the grid directly with a recursive
// search, computing distances in table-local coordinates.

function TPixieRenderTable.GetNearestTextByPoint(
  X, Y: TPixiePixel): TPixieElement;
var
  Best: TPixieElement;
  BestDist: TPixiePixel;

  procedure Search(Ri: TPixieRenderItem; PX, PY: TPixiePixel);
  var
    LocalX, LocalY, ChildX, ChildY, DX, DY, Dist: TPixiePixel;
    I: Integer;
    El: TPixieRenderItem;
    P: TPixiePosition;
  begin
    if not Ri.IsVisible then Exit;

    if Ri.FElement.Css.Overflow > ovVisible then
      if not Ri.FPos.IsPointInside(PX, PY) then
        Exit;

    LocalX := PX - Ri.FPos.X + Ri.GetScrollLeft;
    LocalY := PY - Ri.FPos.Y + Ri.GetScrollTop;

    for I := 0 to Ri.FChildren.Count - 1 do
    begin
      El := Ri.FChildren[I];
      if not El.IsVisible then Continue;

      ChildX := LocalX;
      ChildY := LocalY;
      if El.SrcEl.Css.HasTransform then
        El.MapPointInverse(ChildX, ChildY);

      if El.SrcEl.Css.Display = displayInlineText then
      begin
        P := El.FPos;
        if ChildX < P.X then DX := P.X - ChildX
        else if ChildX > P.X + P.Width then DX := ChildX - (P.X + P.Width)
        else DX := 0;
        if ChildY < P.Y then DY := P.Y - ChildY
        else if ChildY > P.Y + P.Height then DY := ChildY - (P.Y + P.Height)
        else DY := 0;
        Dist := DY * 10000 + DX;
        if (Best = nil) or (Dist < BestDist) then
        begin
          Best := El.SrcEl;
          BestDist := Dist;
        end;
      end
      else
        Search(El, ChildX, ChildY);
    end;
  end;

var
  LocalX, LocalY, ChildX, ChildY: TPixiePixel;
  Row, Col, I: Integer;
  Cell: PPixieTableCell;
  Caption, CellRi: TPixieRenderItem;
begin
  Result := nil;
  if not IsVisible then Exit;
  if FGrid = nil then Exit;

  if FElement.Css.Overflow > ovVisible then
    if not FPos.IsPointInside(X, Y) then
      Exit;

  LocalX := X - FPos.X + GetScrollLeft;
  LocalY := Y - FPos.Y + GetScrollTop;

  Best := nil;
  BestDist := 0;

  // Search captions
  for I := 0 to FGrid.GetCaptions.Count - 1 do
  begin
    Caption := TPixieRenderItem(FGrid.GetCaptions[I]);
    ChildX := LocalX;
    ChildY := LocalY;
    if Caption.SrcEl.Css.HasTransform then
      Caption.MapPointInverse(ChildX, ChildY);
    Search(Caption, ChildX, ChildY);
  end;

  // Search cells directly (bypassing tbody/tr hierarchy)
  for Row := 0 to FGrid.RowsCount - 1 do
  begin
    for Col := 0 to FGrid.ColsCount - 1 do
    begin
      Cell := FGrid.GetCell(Col, Row);
      if (Cell <> nil) and (Cell^.El <> nil) then
      begin
        CellRi := TPixieRenderItem(Cell^.El);
        ChildX := LocalX;
        ChildY := LocalY;
        if CellRi.SrcEl.Css.HasTransform then
          CellRi.MapPointInverse(ChildX, ChildY);
        Search(CellRi, ChildX, ChildY);
      end;
    end;
  end;

  Result := Best;
end;

// --- GetDrawVerticalOffset ---

function TPixieRenderTable.GetDrawVerticalOffset: TPixiePixel;
begin
  if FGrid <> nil then
    Result := FGrid.TopCaptionsHeight
  else
    Result := 0;
end;

function TPixieRenderTable.GetDrawBottomOffset: TPixiePixel;
begin
  if FGrid <> nil then
    Result := FGrid.BottomCaptionsHeight
  else
    Result := 0;
end;

{ TPixieRenderTablePart }

constructor TPixieRenderTablePart.Create(ASrcEl: TPixieElement);
begin
  inherited Create(ASrcEl);
end;

function TPixieRenderTablePart.Clone: TPixieRenderItem;
begin
  Result := TPixieRenderTablePart.Create(FElement);
end;

{ TPixieRenderTableRow }

constructor TPixieRenderTableRow.Create(ASrcEl: TPixieElement);
begin
  inherited Create(ASrcEl);
end;

function TPixieRenderTableRow.Clone: TPixieRenderItem;
begin
  Result := TPixieRenderTableRow.Create(FElement);
end;

procedure TPixieRenderTableRow.GetInlineBoxes(Boxes: TPixiePositionVector);
var
  I: Integer;
  El: TPixieRenderItem;
  P: TPixiePosition;
begin
  for I := 0 to FChildren.Count - 1 do
  begin
    El := FChildren[I];
    if El.SrcEl.Css.Display = displayTableCell then
    begin
      P.X := El.Left + El.MarginLeft;
      P.Y := El.Top - FPadding.Top - FBorders.Top;
      P.Width := El.Right - P.X - El.MarginRight - El.MarginLeft;
      P.Height := El.Height + FPadding.Top + FPadding.Bottom +
        FBorders.Top + FBorders.Bottom;
      Boxes.Add(P);
    end;
  end;
end;

end.
