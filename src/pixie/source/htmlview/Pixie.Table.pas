unit Pixie.Table;

// Table grid data structure for table layout.
//
// Stores a 2D grid of table cells, column/row metadata, and implements
// width/height distribution algorithms. Render items are stored as Pointer
// to avoid circular dependencies with Phase 5 render item types.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Math, Generics.Collections,
  Pixie.Types, Pixie.CssLength;

type
  { TPixieTableRow }
  TPixieTableRow = record
    Height: TPixiePixel;
    BorderTop: TPixiePixel;
    BorderBottom: TPixiePixel;
    Top: TPixiePixel;
    Bottom: TPixiePixel;
    MinHeight: TPixiePixel;
    ElRow: Pointer;
    CssHeight: TPixieCssLength;
    procedure Init;
    procedure InitWithRow(AHeight: TPixiePixel; ARow: Pointer;
      const ACssHeight: TPixieCssLength);
  end;

  { TPixieTableColumn }
  TPixieTableColumn = record
    MinWidth: TPixiePixel;
    MaxWidth: TPixiePixel;
    Width: TPixiePixel;
    BorderLeft: TPixiePixel;
    BorderRight: TPixiePixel;
    Left: TPixiePixel;
    Right: TPixiePixel;
    CssWidth: TPixieCssLength;
    procedure Init;
    procedure InitWithWidths(AMinW, AMaxW: TPixiePixel);
  end;

  { TPixieTableCell }
  TPixieTableCell = record
    El: Pointer;
    Colspan: Integer;
    Rowspan: Integer;
    MinWidth: TPixiePixel;
    MinHeight: TPixiePixel;
    MaxWidth: TPixiePixel;
    MaxHeight: TPixiePixel;
    Width: TPixiePixel;
    Height: TPixiePixel;
    Borders: TPixieMargins;
    CssWidth: TPixieCssLength;
    CssHeight: TPixieCssLength;
    procedure Init;
  end;
  PPixieTableCell = ^TPixieTableCell;

  PPixieTableColumn = ^TPixieTableColumn;
  PPixieTableRow = ^TPixieTableRow;

  // Subclassed to expose Ptr() for direct record access (FPC 3.2.2 compat)
  TPixieTableRowList = class(TList<TPixieTableRow>)
    function Ptr(I: Integer): PPixieTableRow; inline;
  end;
  TPixieTableColumnList = class(TList<TPixieTableColumn>)
    function Ptr(I: Integer): PPixieTableColumn; inline;
  end;
  TPixieTableCellList = class(TList<TPixieTableCell>)
    function Ptr(I: Integer): PPixieTableCell; inline;
  end;
  TPixieTableCellGrid = TObjectList<TPixieTableCellList>;
  TPixiePointerList = TList<Pointer>;

  TPixieColumnField = (cfMinWidth, cfMaxWidth, cfWidth);

  { TPixieTableGrid }
  TPixieTableGrid = class
  private
    FRowsCount: Integer;
    FColsCount: Integer;
    FCells: TPixieTableCellGrid;
    FColumns: TPixieTableColumnList;
    FRows: TPixieTableRowList;
    FCaptions: TPixiePointerList;
    FTopCaptionsHeight: TPixiePixel;
    FBottomCaptionsHeight: TPixiePixel;
    FHasPercentColumns: Boolean;

    function GetColumnField(const Col: TPixieTableColumn;
      Field: TPixieColumnField): TPixiePixel;
    procedure SetColumnField(var Col: TPixieTableColumn;
      Field: TPixieColumnField; Val: TPixiePixel);
    procedure DistributeWidthByField(AWidth: TPixiePixel;
      Start, End_: Integer; Field: TPixieColumnField);

  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    procedure BeginRow(Row: Pointer; const ACssHeight: TPixieCssLength);
    procedure AddCell(El: Pointer; AColspan, ARowspan: Integer;
      const ABorders: TPixieMargins;
      const ACssWidth, ACssHeight: TPixieCssLength);
    function IsRowspanned(R, C: Integer): Boolean;
    procedure Finish;

    function GetCell(Col, Row: Integer): PPixieTableCell;
    function GetColumn(C: Integer): TPixieTableColumn;
    function GetColumnPtr(C: Integer): PPixieTableColumn;
    procedure SetColumn(C: Integer; const Col: TPixieTableColumn);
    function GetRow(R: Integer): TPixieTableRow;
    procedure SetRow(R: Integer; const ARow: TPixieTableRow);

    procedure DistributeMaxWidth(AWidth: TPixiePixel; Start, End_: Integer);
    procedure DistributeMinWidth(AWidth: TPixiePixel; Start, End_: Integer);
    procedure DistributeWidth(AWidth: TPixiePixel; Start, End_: Integer);
    procedure DistributeBeyondMax(AWidth: TPixiePixel; Start, End_: Integer);
    function CalcTableWidth(BlockWidth: TPixiePixel; IsAuto: Boolean;
      IsFixedLayout: Boolean;
      out MinTableWidth, MaxTableWidth: TPixiePixel): TPixiePixel;
    procedure CalcHorizontalPositions(const TableBorders: TPixieMargins;
      Bc: TPixieBorderCollapse; BdrSpaceX: TPixiePixel);
    procedure CalcVerticalPositions(const TableBorders: TPixieMargins;
      Bc: TPixieBorderCollapse; BdrSpaceY: TPixiePixel);
    procedure CalcRowsHeight(BlockHeight, BorderSpacingY: TPixiePixel);

    function GetCaptions: TPixiePointerList;

    property RowsCount: Integer read FRowsCount;
    property HasPercentColumns: Boolean read FHasPercentColumns;
    property ColsCount: Integer read FColsCount;
    property TopCaptionsHeight: TPixiePixel read FTopCaptionsHeight
      write FTopCaptionsHeight;
    property BottomCaptionsHeight: TPixiePixel read FBottomCaptionsHeight
      write FBottomCaptionsHeight;
  end;

implementation

{ TPixieTableRowList }

function TPixieTableRowList.Ptr(I: Integer): PPixieTableRow;
begin
  Assert((I >= 0) and (I < Count), 'Row index out of bounds');
  Result := @{$IFDEF FPC}FItems{$ELSE}List{$ENDIF}[I];
end;

{ TPixieTableColumnList }

function TPixieTableColumnList.Ptr(I: Integer): PPixieTableColumn;
begin
  Assert((I >= 0) and (I < Count), 'Column index out of bounds');
  Result := @{$IFDEF FPC}FItems{$ELSE}List{$ENDIF}[I];
end;

{ TPixieTableCellList }

function TPixieTableCellList.Ptr(I: Integer): PPixieTableCell;
begin
  Assert((I >= 0) and (I < Count), 'Cell index out of bounds');
  Result := @{$IFDEF FPC}FItems{$ELSE}List{$ENDIF}[I];
end;

{ TPixieTableRow }

procedure TPixieTableRow.Init;
begin
  Height := 0;
  BorderTop := 0;
  BorderBottom := 0;
  Top := 0;
  Bottom := 0;
  MinHeight := 0;
  ElRow := nil;
  CssHeight.SetPredef(0);
end;

procedure TPixieTableRow.InitWithRow(AHeight: TPixiePixel; ARow: Pointer;
  const ACssHeight: TPixieCssLength);
begin
  Height := AHeight;
  BorderTop := 0;
  BorderBottom := 0;
  Top := 0;
  Bottom := 0;
  MinHeight := 0;
  ElRow := ARow;
  CssHeight := ACssHeight;
end;

{ TPixieTableColumn }

procedure TPixieTableColumn.Init;
begin
  MinWidth := 0;
  MaxWidth := 0;
  Width := 0;
  BorderLeft := 0;
  BorderRight := 0;
  Left := 0;
  Right := 0;
  CssWidth.SetPredef(0);
end;

procedure TPixieTableColumn.InitWithWidths(AMinW, AMaxW: TPixiePixel);
begin
  MinWidth := AMinW;
  MaxWidth := AMaxW;
  Width := 0;
  BorderLeft := 0;
  BorderRight := 0;
  Left := 0;
  Right := 0;
  CssWidth.SetPredef(0);
end;

{ TPixieTableCell }

procedure TPixieTableCell.Init;
begin
  El := nil;
  Colspan := 1;
  Rowspan := 1;
  MinWidth := 0;
  MinHeight := 0;
  MaxWidth := 0;
  MaxHeight := 0;
  Width := 0;
  Height := 0;
  Borders.Init;
  CssWidth.SetPredef(0);
  CssHeight.SetPredef(0);
end;

{ TPixieTableGrid }

constructor TPixieTableGrid.Create;
begin
  inherited Create;
  FRowsCount := 0;
  FColsCount := 0;
  FTopCaptionsHeight := 0;
  FBottomCaptionsHeight := 0;
  FCells := TPixieTableCellGrid.Create(True);
  FColumns := TPixieTableColumnList.Create;
  FRows := TPixieTableRowList.Create;
  FCaptions := TPixiePointerList.Create;
end;

destructor TPixieTableGrid.Destroy;
begin
  FCaptions.Free;
  FRows.Free;
  FColumns.Free;
  FCells.Free;
  inherited Destroy;
end;

procedure TPixieTableGrid.Clear;
begin
  FRowsCount := 0;
  FColsCount := 0;
  FCells.Clear;
  FColumns.Clear;
  FRows.Clear;
end;

procedure TPixieTableGrid.BeginRow(Row: Pointer;
  const ACssHeight: TPixieCssLength);
var
  RowRec: TPixieTableRow;
  CellRow: TPixieTableCellList;
begin
  CellRow := TPixieTableCellList.Create;
  FCells.Add(CellRow);

  RowRec.InitWithRow(0, Row, ACssHeight);
  FRows.Add(RowRec);
end;

procedure TPixieTableGrid.AddCell(El: Pointer; AColspan, ARowspan: Integer;
  const ABorders: TPixieMargins;
  const ACssWidth, ACssHeight: TPixieCssLength);
var
  Cell, EmptyCell: TPixieTableCell;
  I: Integer;
begin
  Cell.Init;
  Cell.El := El;
  Cell.Colspan := AColspan;
  Cell.Rowspan := ARowspan;
  Cell.Borders := ABorders;
  Cell.CssWidth := ACssWidth;
  Cell.CssHeight := ACssHeight;

  while IsRowspanned(FCells.Count - 1, FCells.Last.Count) do
  begin
    EmptyCell.Init;
    FCells.Last.Add(EmptyCell);
  end;

  FCells.Last.Add(Cell);

  for I := 1 to AColspan - 1 do
  begin
    EmptyCell.Init;
    FCells.Last.Add(EmptyCell);
  end;
end;

function TPixieTableGrid.IsRowspanned(R, C: Integer): Boolean;
var
  Row: Integer;
begin
  Result := False;
  for Row := R - 1 downto 0 do
  begin
    if C < FCells[Row].Count then
    begin
      if FCells[Row][C].Rowspan > 1 then
      begin
        if FCells[Row][C].Rowspan >= R - Row + 1 then
        begin
          Result := True;
          Exit;
        end;
      end;
    end;
  end;
end;

procedure TPixieTableGrid.Finish;
var
  I, J, Col, Row: Integer;
  EmptyCell: TPixieTableCell;
  ColRec: TPixieTableColumn;
  ColP: PPixieTableColumn;
  RowP: PPixieTableRow;
  PC: PPixieTableCell;
begin
  FRowsCount := FCells.Count;
  FColsCount := 0;
  for I := 0 to FCells.Count - 1 do
  begin
    if FCells[I].Count > FColsCount then
      FColsCount := FCells[I].Count;
  end;

  // Pad short rows
  for I := 0 to FCells.Count - 1 do
  begin
    for J := FCells[I].Count to FColsCount - 1 do
    begin
      EmptyCell.Init;
      FCells[I].Add(EmptyCell);
    end;
  end;

  // Create columns
  FColumns.Clear;
  for I := 0 to FColsCount - 1 do
  begin
    ColRec.InitWithWidths(0, 0);
    FColumns.Add(ColRec);
  end;

  // Scan borders and propagate CssWidth
  for Col := 0 to FColsCount - 1 do
  begin
    for Row := 0 to FRowsCount - 1 do
    begin
      PC := GetCell(Col, Row);
      if (PC <> nil) and (PC^.El <> nil) then
      begin
        // Minimum left border
        ColP := FColumns.Ptr(Col);
        if ColP^.BorderLeft <> 0 then
          ColP^.BorderLeft := Min(ColP^.BorderLeft, PC^.Borders.Left)
        else
          ColP^.BorderLeft := PC^.Borders.Left;
        // Minimum right border
        if ColP^.BorderRight <> 0 then
          ColP^.BorderRight := Min(ColP^.BorderRight, PC^.Borders.Right)
        else
          ColP^.BorderRight := PC^.Borders.Right;

        // Minimum top border
        RowP := FRows.Ptr(Row);
        if RowP^.BorderTop <> 0 then
          RowP^.BorderTop := Min(RowP^.BorderTop, PC^.Borders.Top)
        else
          RowP^.BorderTop := PC^.Borders.Top;
        // Minimum bottom border
        if RowP^.BorderBottom <> 0 then
          RowP^.BorderBottom := Min(RowP^.BorderBottom, PC^.Borders.Bottom)
        else
          RowP^.BorderBottom := PC^.Borders.Bottom;
      end;

      // Propagate CssWidth from single-colspan cells
      if (PC <> nil) and (PC^.El <> nil) and (PC^.Colspan <= 1) then
      begin
        if (not PC^.CssWidth.IsPredefined) then
        begin
          if FColumns.Ptr(Col)^.CssWidth.IsPredefined then
            FColumns.Ptr(Col)^.CssWidth := PC^.CssWidth;
        end;
      end;
    end;
  end;
end;

function TPixieTableGrid.GetCell(Col, Row: Integer): PPixieTableCell;
begin
  if (Col >= 0) and (Col < FColsCount) and (Row >= 0) and (Row < FRowsCount) then
    Result := FCells[Row].Ptr(Col)
  else
    Result := nil;
end;

function TPixieTableGrid.GetColumn(C: Integer): TPixieTableColumn;
begin
  Result := FColumns[C];
end;

function TPixieTableGrid.GetColumnPtr(C: Integer): PPixieTableColumn;
begin
  Result := FColumns.Ptr(C);
end;

procedure TPixieTableGrid.SetColumn(C: Integer; const Col: TPixieTableColumn);
begin
  FColumns[C] := Col;
end;

function TPixieTableGrid.GetRow(R: Integer): TPixieTableRow;
begin
  Result := FRows[R];
end;

procedure TPixieTableGrid.SetRow(R: Integer; const ARow: TPixieTableRow);
begin
  FRows[R] := ARow;
end;

function TPixieTableGrid.GetCaptions: TPixiePointerList;
begin
  Result := FCaptions;
end;

function TPixieTableGrid.GetColumnField(const Col: TPixieTableColumn;
  Field: TPixieColumnField): TPixiePixel;
begin
  case Field of
    cfMinWidth: Result := Col.MinWidth;
    cfMaxWidth: Result := Col.MaxWidth;
    cfWidth:    Result := Col.Width;
  else
    Result := 0;
  end;
end;

procedure TPixieTableGrid.SetColumnField(var Col: TPixieTableColumn;
  Field: TPixieColumnField; Val: TPixiePixel);
begin
  case Field of
    cfMinWidth: Col.MinWidth := Val;
    cfMaxWidth: Col.MaxWidth := Val;
    cfWidth:    Col.Width := Val;
  end;
end;

procedure TPixieTableGrid.DistributeWidthByField(AWidth: TPixiePixel;
  Start, End_: Integer; Field: TPixieColumnField);
var
  ColsWidth, Add, AddedWidth: TPixiePixel;
  Col: Integer;
begin
  if not ((Start >= 0) and (Start < FColsCount) and
          (End_ >= 0) and (End_ < FColsCount)) then
    Exit;

  ColsWidth := 0;
  for Col := Start to End_ do
    ColsWidth := ColsWidth + FColumns[Col].MaxWidth;

  Add := AWidth / (End_ - Start + 1);
  AddedWidth := 0;
  for Col := Start to End_ do
  begin
    if ColsWidth <> 0 then
      Add := AWidth * (FColumns[Col].MaxWidth / ColsWidth);
    AddedWidth := AddedWidth + Add;
    SetColumnField(FColumns.Ptr(Col)^, Field,
      GetColumnField(FColumns.Ptr(Col)^, Field) + Add);
  end;
  if AddedWidth < AWidth then
    SetColumnField(FColumns.Ptr(Start)^, Field,
      GetColumnField(FColumns.Ptr(Start)^, Field) + (AWidth - AddedWidth));
end;

procedure TPixieTableGrid.DistributeMaxWidth(AWidth: TPixiePixel;
  Start, End_: Integer);
begin
  DistributeWidthByField(AWidth, Start, End_, cfMaxWidth);
end;

procedure TPixieTableGrid.DistributeMinWidth(AWidth: TPixiePixel;
  Start, End_: Integer);
begin
  DistributeWidthByField(AWidth, Start, End_, cfMinWidth);
end;

procedure TPixieTableGrid.DistributeWidth(AWidth: TPixiePixel;
  Start, End_: Integer);
var
  Step, Col: Integer;
  DistCols: TPixieIntVector;
  ColsWidth, Add, AddedWidth: TPixiePixel;
  ColP: PPixieTableColumn;
begin
  if not ((Start >= 0) and (Start < FColsCount) and
          (End_ >= 0) and (End_ < FColsCount)) then
    Exit;

  DistCols := TPixieIntVector.Create;
  try
    for Step := 0 to 2 do
    begin
      DistCols.Clear;

      case Step of
        0: begin
          // Auto columns (css_width predefined)
          for Col := Start to End_ do
          begin
            if FColumns[Col].CssWidth.IsPredefined then
              DistCols.Add(Col);
          end;
        end;
        1: begin
          // Percentage columns
          for Col := Start to End_ do
          begin
            if (not FColumns[Col].CssWidth.IsPredefined) and
               (FColumns[Col].CssWidth.Units = cssUnitsPercentage) then
              DistCols.Add(Col);
          end;
        end;
        2: begin
          // All columns
          for Col := Start to End_ do
            DistCols.Add(Col);
        end;
      end;

      AddedWidth := 0;

      if (DistCols.Count > 0) or (Step = 2) then
      begin
        ColsWidth := 0;
        for Col := 0 to DistCols.Count - 1 do
          ColsWidth := ColsWidth + FColumns[DistCols[Col]].MaxWidth -
            FColumns[DistCols[Col]].MinWidth;

        if ColsWidth <> 0 then
        begin
          for Col := 0 to DistCols.Count - 1 do
          begin
            Add := AWidth * ((FColumns[DistCols[Col]].MaxWidth -
              FColumns[DistCols[Col]].MinWidth) / ColsWidth);
            ColP := FColumns.Ptr(DistCols[Col]);
            if ColP^.Width + Add >= ColP^.MinWidth then
            begin
              ColP^.Width := ColP^.Width + Add;
              AddedWidth := AddedWidth + Add;
            end
            else
            begin
              if Add <> 0 then
                AddedWidth := AddedWidth +
                  (ColP^.Width - ColP^.MinWidth) * (Add / Abs(Add));
              ColP^.Width := ColP^.MinWidth;
            end;
          end;
          if (AddedWidth < AWidth) and (Step > 0) then
          begin
            FColumns.Ptr(DistCols[0])^.Width :=
              FColumns.Ptr(DistCols[0])^.Width + (AWidth - AddedWidth);
            AddedWidth := AWidth;
          end;
        end
        else
        begin
          FColumns.Ptr(DistCols[DistCols.Count - 1])^.Width :=
            FColumns.Ptr(DistCols[DistCols.Count - 1])^.Width + AWidth;
          AddedWidth := AWidth;
        end;
      end;

      if AddedWidth = AWidth then
        Break
      else
        AWidth := AWidth - AddedWidth;
    end;
  finally
    DistCols.Free;
  end;
end;

// Spread excess width across auto columns by MaxWidth ratio. Without
// this, a rigid auto column (MaxWidth == MinWidth, e.g. a cell holding
// a single image with no break opportunity) would never grow past its
// content size, while flexible neighbours hog all remaining space.
procedure TPixieTableGrid.DistributeBeyondMax(AWidth: TPixiePixel;
  Start, End_: Integer);
var
  Col, LastAuto: Integer;
  ColP: PPixieTableColumn;
  TotalMax, Add, AddedWidth: TPixiePixel;
begin
  if not ((Start >= 0) and (Start < FColsCount) and
          (End_ >= 0) and (End_ < FColsCount)) then
    Exit;

  TotalMax := 0;
  LastAuto := -1;
  for Col := Start to End_ do
    if FColumns[Col].CssWidth.IsPredefined then
    begin
      LastAuto := Col;
      TotalMax := TotalMax + FColumns[Col].MaxWidth;
    end;

  if (LastAuto < 0) or (TotalMax <= 0) then
  begin
    DistributeWidth(AWidth, Start, End_);
    Exit;
  end;

  AddedWidth := 0;
  for Col := Start to End_ do
    if FColumns[Col].CssWidth.IsPredefined then
    begin
      Add := AWidth * (FColumns[Col].MaxWidth / TotalMax);
      ColP := FColumns.Ptr(Col);
      ColP^.Width := ColP^.Width + Add;
      AddedWidth := AddedWidth + Add;
    end;
  if AddedWidth < AWidth then
  begin
    ColP := FColumns.Ptr(LastAuto);
    ColP^.Width := ColP^.Width + (AWidth - AddedWidth);
  end;
end;

function TPixieTableGrid.CalcTableWidth(BlockWidth: TPixiePixel; IsAuto: Boolean;
  IsFixedLayout: Boolean;
  out MinTableWidth, MaxTableWidth: TPixiePixel): TPixiePixel;
var
  CurWidth, MaxW, MinW, FixedWidth, Percent, Scale: TPixiePixel;
  Col, ColsNoWidth: Integer;
  ColP: PPixieTableColumn;
  Excess, ScaledPct, NeededBase: TPixiePixel;
  RemainingWidth: TPixiePixel;
begin
  MinTableWidth := 0;
  MaxTableWidth := 0;
  FHasPercentColumns := False;

  if IsFixedLayout then
  begin
    FixedWidth := 0;
    ColsNoWidth := 0;
    for Col := 0 to FColsCount - 1 do
    begin
      ColP := FColumns.Ptr(Col);
      if not ColP^.CssWidth.IsPredefined then
      begin
        if ColP^.CssWidth.Units = cssUnitsPercentage then
        begin
          FHasPercentColumns := True;
          ColP^.Width := ColP^.CssWidth.CalcPercent(BlockWidth);
        end else
          ColP^.Width := ColP^.CssWidth.Val;
        FixedWidth := FixedWidth + ColP^.Width;
      end else
      begin
        ColP^.Width := 0;
        Inc(ColsNoWidth);
      end;
    end;
    if (ColsNoWidth > 0) and (FixedWidth < BlockWidth) then
    begin
      RemainingWidth := (BlockWidth - FixedWidth) / ColsNoWidth;
      for Col := 0 to FColsCount - 1 do
      begin
        ColP := FColumns.Ptr(Col);
        if ColP^.CssWidth.IsPredefined then
          ColP^.Width := RemainingWidth;
      end;
    end;
    MinTableWidth := BlockWidth;
    MaxTableWidth := BlockWidth;
    Result := BlockWidth;
    Exit;
  end;

  CurWidth := 0;
  MaxW := 0;
  MinW := 0;

  for Col := 0 to FColsCount - 1 do
  begin
    MinTableWidth := MinTableWidth + FColumns[Col].MinWidth;
    MaxTableWidth := MaxTableWidth + FColumns[Col].MaxWidth;

    ColP := FColumns.Ptr(Col);
    if not ColP^.CssWidth.IsPredefined then
    begin
      if ColP^.CssWidth.Units = cssUnitsPercentage then
        FHasPercentColumns := True;
      ColP^.Width := ColP^.CssWidth.CalcPercent(BlockWidth);
      if ColP^.Width < ColP^.MinWidth then
        ColP^.Width := ColP^.MinWidth;
    end
    else
    begin
      ColP^.Width := ColP^.MinWidth;
      MaxW := MaxW + ColP^.MaxWidth;
      MinW := MinW + ColP^.MinWidth;
    end;
    CurWidth := CurWidth + ColP^.Width;
  end;

  if CurWidth = BlockWidth then
  begin
    Result := CurWidth;
    Exit;
  end;

  if CurWidth < BlockWidth then
  begin
    if CurWidth - MinW + MaxW <= BlockWidth then
    begin
      CurWidth := 0;
      for Col := 0 to FColsCount - 1 do
      begin
        ColP := FColumns.Ptr(Col);
        if ColP^.CssWidth.IsPredefined then
          ColP^.Width := ColP^.MaxWidth;
        CurWidth := CurWidth + ColP^.Width;
      end;
      if (CurWidth = BlockWidth) or (IsAuto and not FHasPercentColumns) then
      begin
        Result := CurWidth;
        Exit;
      end;
      DistributeBeyondMax(BlockWidth - CurWidth, 0, FColsCount - 1);
    end
    else
      DistributeWidth(BlockWidth - CurWidth, 0, FColsCount - 1);
    CurWidth := 0;
    for Col := 0 to FColsCount - 1 do
      CurWidth := CurWidth + FColumns[Col].Width;
  end
  else
  begin
    // Table wider than block — rescale percentage columns
    FixedWidth := 0;
    Percent := 0;
    for Col := 0 to FColsCount - 1 do
    begin
      if (not FColumns[Col].CssWidth.IsPredefined) and
         (FColumns[Col].CssWidth.Units = cssUnitsPercentage) then
        Percent := Percent + FColumns[Col].CssWidth.Val
      else
        FixedWidth := FixedWidth + FColumns[Col].Width;
    end;

    if Percent > 0 then
    begin
      Scale := 100.0 / Percent;

      // Find the minimum base that keeps percentage columns proportional
      // while satisfying all minWidth constraints
      NeededBase := BlockWidth - FixedWidth;
      for Col := 0 to FColsCount - 1 do
      begin
        ColP := FColumns.Ptr(Col);
        if (not ColP^.CssWidth.IsPredefined) and
           (ColP^.CssWidth.Units = cssUnitsPercentage) then
        begin
          ScaledPct := ColP^.CssWidth.Val * Scale;
          if ScaledPct > 0 then
          begin
            Excess := ColP^.MinWidth * 100 / ScaledPct;
            if Excess > NeededBase then
              NeededBase := Excess;
          end;
        end;
      end;

      // Redistribute using the adjusted base
      CurWidth := FixedWidth;
      for Col := 0 to FColsCount - 1 do
      begin
        ColP := FColumns.Ptr(Col);
        if (not ColP^.CssWidth.IsPredefined) and
           (ColP^.CssWidth.Units = cssUnitsPercentage) then
        begin
          ColP^.Width := ColP^.CssWidth.Val * Scale / 100 * NeededBase;
          CurWidth := CurWidth + ColP^.Width;
        end;
      end;
    end;
  end;

  Result := CurWidth;
end;

procedure TPixieTableGrid.CalcHorizontalPositions(
  const TableBorders: TPixieMargins; Bc: TPixieBorderCollapse;
  BdrSpaceX: TPixiePixel);
var
  I: Integer;
  L: TPixiePixel;
  ColP: PPixieTableColumn;
begin
  if Bc = bcSeparate then
  begin
    // Round to prevent sub-pixel gaps between adjacent cells
    L := BdrSpaceX;
    for I := 0 to FColsCount - 1 do
    begin
      ColP := FColumns.Ptr(I);
      ColP^.Left := Round(L);
      ColP^.Right := Round(L + ColP^.Width);
      L := ColP^.Right + BdrSpaceX;
    end;
  end
  else
  begin
    L := 0;
    if FColsCount > 0 then
      L := L - Min(TableBorders.Left, FColumns[0].BorderLeft);
    for I := 0 to FColsCount - 1 do
    begin
      if I > 0 then
        L := L - Min(FColumns[I - 1].BorderRight, FColumns[I].BorderLeft);
      ColP := FColumns.Ptr(I);
      ColP^.Left := Round(L);
      ColP^.Right := Round(L + ColP^.Width);
      L := ColP^.Right;
    end;
  end;
end;

procedure TPixieTableGrid.CalcVerticalPositions(
  const TableBorders: TPixieMargins; Bc: TPixieBorderCollapse;
  BdrSpaceY: TPixiePixel);
var
  I: Integer;
  T: TPixiePixel;
  RowP: PPixieTableRow;
begin
  if Bc = bcSeparate then
  begin
    T := BdrSpaceY;
    for I := 0 to FRowsCount - 1 do
    begin
      RowP := FRows.Ptr(I);
      RowP^.Top := Round(T);
      RowP^.Bottom := Round(T + RowP^.Height);
      T := RowP^.Bottom + BdrSpaceY;
    end;
  end
  else
  begin
    T := 0;
    if FRowsCount > 0 then
      T := T - Min(TableBorders.Top, FRows[0].BorderTop);
    for I := 0 to FRowsCount - 1 do
    begin
      if I > 0 then
        T := T - Min(FRows[I - 1].BorderBottom, FRows[I].BorderTop);
      RowP := FRows.Ptr(I);
      RowP^.Top := Round(T);
      RowP^.Bottom := Round(T + RowP^.Height);
      T := RowP^.Bottom;
    end;
  end;
end;

procedure TPixieTableGrid.CalcRowsHeight(BlockHeight,
  BorderSpacingY: TPixiePixel);
var
  MinTableHeight, ExtraHeight, ExtraRowHeight: TPixiePixel;
  AutoCount, I: Integer;
  RowP: PPixieTableRow;
begin
  MinTableHeight := 0;

  // Apply CSS non-percentage heights
  for I := 0 to FRows.Count - 1 do
  begin
    RowP := FRows.Ptr(I);
    if not RowP^.CssHeight.IsPredefined then
    begin
      if RowP^.CssHeight.Units <> cssUnitsPercentage then
      begin
        if RowP^.Height < RowP^.CssHeight.Val then
          RowP^.Height := RowP^.CssHeight.Val;
      end;
    end;
    RowP^.MinHeight := RowP^.Height;
    MinTableHeight := MinTableHeight + RowP^.Height;
  end;

  if BlockHeight > MinTableHeight then
  begin
    ExtraHeight := BlockHeight - MinTableHeight;
    AutoCount := 0;

    // Expand percentage rows
    for I := 0 to FRows.Count - 1 do
    begin
      RowP := FRows.Ptr(I);
      if (not RowP^.CssHeight.IsPredefined) and
         (RowP^.CssHeight.Units = cssUnitsPercentage) then
      begin
        RowP^.Height := RowP^.CssHeight.CalcPercent(BlockHeight);
        if RowP^.Height < RowP^.MinHeight then
          RowP^.Height := RowP^.MinHeight;
        ExtraHeight := ExtraHeight - (RowP^.Height - RowP^.MinHeight);
        if ExtraHeight <= 0 then
          Break;
      end
      else if RowP^.CssHeight.IsPredefined then
        Inc(AutoCount);
    end;

    if ExtraHeight > 0 then
    begin
      if AutoCount > 0 then
      begin
        ExtraRowHeight := ExtraHeight / AutoCount;
        for I := 0 to FRows.Count - 1 do
        begin
          if FRows.Ptr(I)^.CssHeight.IsPredefined then
            FRows.Ptr(I)^.Height := FRows.Ptr(I)^.Height + ExtraRowHeight;
        end;
      end
      else
      begin
        if FRows.Count > 0 then
        begin
          ExtraRowHeight := ExtraHeight / FRows.Count;
          for I := 0 to FRows.Count - 1 do
            FRows.Ptr(I)^.Height := FRows.Ptr(I)^.Height + ExtraRowHeight;
        end;
      end;
    end
    else if ExtraHeight < 0 then
    begin
      ExtraHeight := -ExtraHeight;
      for I := FRows.Count - 1 downto 0 do
      begin
        if ExtraHeight <= 0 then
          Break;
        RowP := FRows.Ptr(I);
        if RowP^.Height > RowP^.MinHeight then
        begin
          if RowP^.Height - ExtraHeight >= RowP^.MinHeight then
          begin
            RowP^.Height := RowP^.Height - ExtraHeight;
            ExtraHeight := 0;
          end
          else
          begin
            ExtraHeight := ExtraHeight - (RowP^.Height - RowP^.MinHeight);
            RowP^.Height := RowP^.MinHeight;
          end;
        end;
      end;
    end;
  end;
end;

end.
