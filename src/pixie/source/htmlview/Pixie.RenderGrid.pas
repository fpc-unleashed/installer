unit Pixie.RenderGrid;

// CSS Grid layout — arranges grid items in a 2D grid of tracks.
// Follows the same architecture as Pixie.RenderFlex.pas.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Generics.Collections, Math,
  Pixie.Types, Pixie.CssLength, Pixie.CssProperties,
  Pixie.Element, Pixie.FormattingContext,
  Pixie.RenderItem, Pixie.RenderBlock,
  Pixie.GridItem;

type
  { TPixieRenderGrid }
  TPixieRenderGrid = class(TPixieRenderBlock)
  private
    FItems: TPixieGridItemList;
    FColTracks: TPixieGridTrackList;
    FRowTracks: TPixieGridTrackList;
    FOccupancy: TPixieGridOccupancy;

    procedure CollectItems;
    procedure DetermineExplicitGrid;
    procedure AutoPlace;
    procedure ResolveColumnTracks(ContainerWidth: TPixiePixel);
    procedure RenderItemsAtColumnWidths(
      const SelfSize: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext);
    procedure ResolveRowTracks(ContainerHeight: TPixiePixel; HeightIsAuto: Boolean);
    procedure PositionItems;

    function TrackPosition(Tracks: TPixieGridTrackList; Index: Integer): TPixiePixel;
    function TrackSpanSize(Tracks: TPixieGridTrackList; Start, End_: Integer): TPixiePixel;
    function GapVal(const Gap: TPixieCssLength): TPixiePixel;

  protected
    function _RenderContent(X, Y: TPixiePixel; SecondPass: Boolean;
      const SelfSize: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext): TPixiePixel; override;
  public
    constructor Create(ASrcEl: TPixieElement); override;
    destructor Destroy; override;
    function Clone: TPixieRenderItem; override;
    function Init: TPixieRenderItem; override;
  end;

implementation

uses
  Pixie.HtmlTag, Pixie.Document;

{ TPixieRenderGrid }

constructor TPixieRenderGrid.Create(ASrcEl: TPixieElement);
begin
  inherited Create(ASrcEl);
  FItems := nil;
  FColTracks := nil;
  FRowTracks := nil;
  FOccupancy := nil;
end;

destructor TPixieRenderGrid.Destroy;
begin
  FItems.Free;
  FColTracks.Free;
  FRowTracks.Free;
  FOccupancy.Free;
  inherited;
end;

function TPixieRenderGrid.Clone: TPixieRenderItem;
begin
  Result := TPixieRenderGrid.Create(FElement);
end;

// --- Init (same pattern as RenderFlex.Init) ---

function TPixieRenderGrid.Init: TPixieRenderItem;
var
  NewChildren: TPixieRenderItemList;
  Inlines: TPixieRenderItemList;
  I: Integer;
  El, InitResult: TPixieRenderItem;
  AnonEl: TPixieHtmlTag;
  AnonRi: TPixieRenderBlock;
  Doc: TPixieDocument;

  procedure ConvertInlines;
  var
    K, Last: Integer;
    InitResult: TPixieRenderItem;
  begin
    if Inlines.Count = 0 then
      Exit;
    Last := Inlines.Count - 1;
    while (Last >= 0) and Inlines[Last].SrcEl.IsSpace do
      Dec(Last);
    if Last < 0 then
    begin
      for K := 0 to Inlines.Count - 1 do
        Inlines[K].Free;
      Inlines.Clear;
      Exit;
    end;
    for K := Inlines.Count - 1 downto Last + 1 do
    begin
      Inlines[K].Free;
      Inlines.Delete(K);
    end;
    AnonEl := TPixieHtmlTag.CreateAnonymous(SrcEl);
    Doc.RegisterElement(AnonEl);
    AnonRi := TPixieRenderBlock.Create(AnonEl);
    for K := 0 to Inlines.Count - 1 do
      AnonRi.AddChild(Inlines[K]);
    AnonRi.SetParent(Self);
    InitResult := AnonRi.Init;
    if InitResult <> AnonRi then
      AnonRi.Free;
    NewChildren.Add(InitResult);
    Inlines.Clear;
  end;

begin
  Assert(SrcEl.GetDocument is TPixieDocument);
  Doc := TPixieDocument(SrcEl.GetDocument);
  NewChildren := TPixieRenderItemList.Create(True);
  Inlines := TPixieRenderItemList.Create(False);
  try
    for I := 0 to FChildren.Count - 1 do
    begin
      El := FChildren[I];
      if El.SrcEl.Css.Display = displayInlineText then
      begin
        if Inlines.Count > 0 then
          Inlines.Add(El)
        else if not El.SrcEl.IsWhiteSpace then
          Inlines.Add(El)
        else
          El.Free;
      end
      else
      begin
        ConvertInlines;
        if El.SrcEl.IsBlockBox then
        begin
          El.SetParent(Self);
          InitResult := El.Init;
          if InitResult <> El then
            El.Free;
          NewChildren.Add(InitResult);
        end
        else
        begin
          AnonEl := TPixieHtmlTag.CreateAnonymous(El.SrcEl);
          Doc.RegisterElement(AnonEl);
          AnonRi := TPixieRenderBlock.Create(AnonEl);
          InitResult := El.Init;
          if InitResult <> El then
            El.Free;
          AnonRi.AddChild(InitResult);
          AnonRi.SetParent(Self);
          InitResult := AnonRi.Init;
          if InitResult <> AnonRi then
            AnonRi.Free;
          NewChildren.Add(InitResult);
        end;
      end;
    end;
    ConvertInlines;

    FChildren.OwnsObjects := False;
    FChildren.Clear;
    FChildren.OwnsObjects := True;

    NewChildren.OwnsObjects := False;
    for I := 0 to NewChildren.Count - 1 do
      FChildren.Add(NewChildren[I]);
  finally
    Inlines.Free;
    NewChildren.Free;
  end;

  SrcEl.AddRender(Self);
  Result := Self;
end;

// --- Helpers ---

function TPixieRenderGrid.GapVal(const Gap: TPixieCssLength): TPixiePixel;
begin
  if Gap.IsPredefined or (Gap.Val < 0) then
    Result := 0
  else
    Result := Gap.Val;
end;

function TPixieRenderGrid.TrackPosition(Tracks: TPixieGridTrackList;
  Index: Integer): TPixiePixel;
begin
  if (Index >= 0) and (Index < Tracks.Count) then
    Result := Tracks[Index].Position
  else if Tracks.Count > 0 then
    Result := Tracks[Tracks.Count - 1].Position + Tracks[Tracks.Count - 1].Base
  else
    Result := 0;
end;

function TPixieRenderGrid.TrackSpanSize(Tracks: TPixieGridTrackList;
  Start, End_: Integer): TPixiePixel;
var
  I: Integer;
  Gap: TPixiePixel;
begin
  Result := 0;
  if Tracks = FColTracks then
    Gap := GapVal(Css.ColumnGap)
  else
    Gap := GapVal(Css.RowGap);

  for I := Start to End_ - 1 do
    if (I >= 0) and (I < Tracks.Count) then
    begin
      Result := Result + Tracks[I].Base;
      if I > Start then
        Result := Result + Gap;
    end;
end;

// --- CollectItems ---

procedure TPixieRenderGrid.CollectItems;
var
  I: Integer;
  Ri: TPixieRenderItem;
  Item: TPixieGridItem;
  Css: TPixieCssProperties;
  LineVal: Single;
begin
  if FItems = nil then
    FItems := TPixieGridItemList.Create(True)
  else
    FItems.Clear;

  for I := 0 to FChildren.Count - 1 do
  begin
    Ri := FChildren[I];
    if Ri.SrcEl.Css.Display = displayNone then
      Continue;

    Item := TPixieGridItem.Create(Ri, I);
    Css := Ri.SrcEl.Css;

    // Read column placement
    if not Css.GridColumnStart.IsPredefined then
    begin
      LineVal := Css.GridColumnStart.Val;
      if LineVal > 0 then
        Item.Placement.ColStart := Round(LineVal) - 1  // 1-based to 0-based
      else if LineVal < 0 then
        Item.Placement.ColStart := Round(LineVal);      // negative = span
    end;

    if not Css.GridColumnEnd.IsPredefined then
    begin
      LineVal := Css.GridColumnEnd.Val;
      if LineVal > 0 then
        Item.Placement.ColEnd := Round(LineVal) - 1
      else if LineVal < 0 then
        Item.Placement.ColEnd := Round(LineVal);
    end;

    // Read row placement
    if not Css.GridRowStart.IsPredefined then
    begin
      LineVal := Css.GridRowStart.Val;
      if LineVal > 0 then
        Item.Placement.RowStart := Round(LineVal) - 1
      else if LineVal < 0 then
        Item.Placement.RowStart := Round(LineVal);
    end;

    if not Css.GridRowEnd.IsPredefined then
    begin
      LineVal := Css.GridRowEnd.Val;
      if LineVal > 0 then
        Item.Placement.RowEnd := Round(LineVal) - 1
      else if LineVal < 0 then
        Item.Placement.RowEnd := Round(LineVal);
    end;

    FItems.Add(Item);
  end;
end;

// --- DetermineExplicitGrid ---

procedure TPixieRenderGrid.DetermineExplicitGrid;
var
  I: Integer;
  Track: TPixieGridTrack;
begin
  if FColTracks = nil then
    FColTracks := TPixieGridTrackList.Create
  else
    FColTracks.Clear;
  if FRowTracks = nil then
    FRowTracks := TPixieGridTrackList.Create
  else
    FRowTracks.Clear;

  // Build column tracks from template
  if Css.GridTemplateColumns <> nil then
  begin
    I := 0;
    while I < Css.GridTemplateColumns.Count do
    begin
      if Css.GridTemplateColumns[I].IsPredefined and
         (Css.GridTemplateColumns[I].Predef = CssGridMinmaxMarker) and
         (I + 2 < Css.GridTemplateColumns.Count) then
      begin
        // minmax(min, max) encoded as marker + min + max
        Track.HasMinmax := True;
        Track.MinSize := Css.GridTemplateColumns[I + 1];
        Track.MaxSize := Css.GridTemplateColumns[I + 2];
        Track.Size := Track.MaxSize; // use max as default size
        Track.Base := 0;
        Track.Position := 0;
        FColTracks.Add(Track);
        Inc(I, 3);
      end
      else
      begin
        Track.HasMinmax := False;
        Track.Size := Css.GridTemplateColumns[I];
        Track.Base := 0;
        Track.Position := 0;
        FColTracks.Add(Track);
        Inc(I);
      end;
    end;
  end;

  // Build row tracks from template
  if Css.GridTemplateRows <> nil then
  begin
    I := 0;
    while I < Css.GridTemplateRows.Count do
    begin
      if Css.GridTemplateRows[I].IsPredefined and
         (Css.GridTemplateRows[I].Predef = CssGridMinmaxMarker) and
         (I + 2 < Css.GridTemplateRows.Count) then
      begin
        Track.HasMinmax := True;
        Track.MinSize := Css.GridTemplateRows[I + 1];
        Track.MaxSize := Css.GridTemplateRows[I + 2];
        Track.Size := Track.MaxSize;
        Track.Base := 0;
        Track.Position := 0;
        FRowTracks.Add(Track);
        Inc(I, 3);
      end
      else
      begin
        Track.HasMinmax := False;
        Track.Size := Css.GridTemplateRows[I];
        Track.Base := 0;
        Track.Position := 0;
        FRowTracks.Add(Track);
        Inc(I);
      end;
    end;
  end;
end;

// --- AutoPlace ---

procedure TPixieRenderGrid.AutoPlace;
var
  I, NumCols, NumRows: Integer;
  Item: TPixieGridItem;
  P: TPixieGridPlacement;
  CursorRow, CursorCol: Integer;
  Col, Row: Integer;
  ColSpan, RowSpan: Integer;
  Track: TPixieGridTrack;
  Found: Boolean;
begin
  FillChar(Track, SizeOf(Track), 0);

  if FOccupancy = nil then
    FOccupancy := TPixieGridOccupancy.Create
  else
    FOccupancy.Clear;
  NumCols := FColTracks.Count;
  if NumCols < 1 then
    NumCols := 1;
  NumRows := FRowTracks.Count;

  // Resolve span values to absolute positions where possible
  for I := 0 to FItems.Count - 1 do
  begin
    Item := FItems[I];
    P := Item.Placement;

    // Resolve column span: if start is definite and end is span
    if (P.ColStart >= 0) and (P.ColEnd < 0) then
    begin
      P.ColEnd := P.ColStart + Abs(Round(P.ColEnd));
      if P.ColEnd < P.ColStart + 1 then
        P.ColEnd := P.ColStart + 1;
    end
    else if (P.ColEnd >= 0) and (P.ColStart < 0) and (P.ColStart <> -1) then
    begin
      // end is definite, start is span
      P.ColStart := P.ColEnd - Abs(Round(P.ColStart));
      if P.ColStart < 0 then
        P.ColStart := 0;
    end
    else if (P.ColStart >= 0) and (P.ColEnd = -1) then
      P.ColEnd := P.ColStart + 1  // default span 1
    else if (P.ColStart < 0) and (P.ColEnd < 0) and
            (P.ColStart <> -1) and (P.ColEnd <> -1) then
    begin
      // both are spans — treat as auto with span from start
      P.ColEnd := P.ColStart; // keep negative for later
      P.ColStart := -1;
    end;

    // Resolve row span
    if (P.RowStart >= 0) and (P.RowEnd < 0) then
    begin
      P.RowEnd := P.RowStart + Abs(Round(P.RowEnd));
      if P.RowEnd < P.RowStart + 1 then
        P.RowEnd := P.RowStart + 1;
    end
    else if (P.RowEnd >= 0) and (P.RowStart < 0) and (P.RowStart <> -1) then
    begin
      P.RowStart := P.RowEnd - Abs(Round(P.RowStart));
      if P.RowStart < 0 then
        P.RowStart := 0;
    end
    else if (P.RowStart >= 0) and (P.RowEnd = -1) then
      P.RowEnd := P.RowStart + 1
    else if (P.RowStart < 0) and (P.RowEnd < 0) and
            (P.RowStart <> -1) and (P.RowEnd <> -1) then
    begin
      P.RowEnd := P.RowStart;
      P.RowStart := -1;
    end;

    Item.Placement := P;
  end;

  // Phase A: Place items with definite row AND column
  for I := 0 to FItems.Count - 1 do
  begin
    Item := FItems[I];
    P := Item.Placement;
    if (P.RowStart >= 0) and (P.ColStart >= 0) and
       (P.RowEnd > P.RowStart) and (P.ColEnd > P.ColStart) then
    begin
      // Expand grid if needed
      while FColTracks.Count < P.ColEnd do
      begin
        Track.Size := TPixieCssLength.PredefValue(0); // auto
        Track.Base := 0;
        Track.Position := 0;
        FColTracks.Add(Track);
      end;
      while FRowTracks.Count < P.RowEnd do
      begin
        Track.Size := TPixieCssLength.PredefValue(0);
        Track.Base := 0;
        Track.Position := 0;
        FRowTracks.Add(Track);
      end;
      FOccupancy.Mark(P.RowStart, P.ColStart, P.RowEnd, P.ColEnd);
      NumCols := Max(NumCols, FColTracks.Count);
      NumRows := Max(NumRows, FRowTracks.Count);
    end;
  end;

  // Phase B: Place items with definite row only
  for I := 0 to FItems.Count - 1 do
  begin
    Item := FItems[I];
    P := Item.Placement;
    if (P.RowStart >= 0) and (P.RowEnd > P.RowStart) and (P.ColStart < 0) then
    begin
      if P.ColEnd < 0 then
        ColSpan := Abs(Round(P.ColEnd))
      else
        ColSpan := 1;
      if ColSpan < 1 then
        ColSpan := 1;

      Col := FOccupancy.FindFreeColumn(P.RowStart, ColSpan, NumCols);
      P.ColStart := Col;
      P.ColEnd := Col + ColSpan;

      while FColTracks.Count < P.ColEnd do
      begin
        Track.Size := TPixieCssLength.PredefValue(0);
        Track.Base := 0;
        Track.Position := 0;
        FColTracks.Add(Track);
      end;
      while FRowTracks.Count < P.RowEnd do
      begin
        Track.Size := TPixieCssLength.PredefValue(0);
        Track.Base := 0;
        Track.Position := 0;
        FRowTracks.Add(Track);
      end;
      FOccupancy.Mark(P.RowStart, P.ColStart, P.RowEnd, P.ColEnd);
      NumCols := Max(NumCols, FColTracks.Count);
      NumRows := Max(NumRows, FRowTracks.Count);
      Item.Placement := P;
    end;
  end;

  // Phase C: Cursor-based auto-placement for remaining items
  CursorRow := 0;
  CursorCol := 0;
  for I := 0 to FItems.Count - 1 do
  begin
    Item := FItems[I];
    P := Item.Placement;
    if (P.RowStart >= 0) and (P.ColStart >= 0) and
       (P.RowEnd > P.RowStart) and (P.ColEnd > P.ColStart) then
      Continue; // Already placed

    // Determine spans — prefer start's span if it's a span value
    if (P.ColStart < -1) then
      ColSpan := Max(1, Abs(P.ColStart))
    else if (P.ColEnd < -1) then
      ColSpan := Max(1, Abs(P.ColEnd))
    else if (P.ColStart >= 0) and (P.ColEnd > P.ColStart) then
      ColSpan := P.ColEnd - P.ColStart
    else
      ColSpan := 1;

    if (P.RowStart < -1) then
      RowSpan := Max(1, Abs(P.RowStart))
    else if (P.RowEnd < -1) then
      RowSpan := Max(1, Abs(P.RowEnd))
    else if (P.RowStart >= 0) and (P.RowEnd > P.RowStart) then
      RowSpan := P.RowEnd - P.RowStart
    else
      RowSpan := 1;

    // Scan for free space starting from cursor
    Found := False;
    Row := CursorRow;
    while not Found do
    begin
      Col := CursorCol;
      while Col + ColSpan <= Max(NumCols, ColSpan) do
      begin
        if not FOccupancy.IsOccupied(Row, Col, Row + RowSpan, Col + ColSpan) then
        begin
          P.RowStart := Row;
          P.ColStart := Col;
          P.RowEnd := Row + RowSpan;
          P.ColEnd := Col + ColSpan;
          Found := True;
          Break;
        end;
        Inc(Col);
      end;
      if not Found then
      begin
        Inc(Row);
        CursorCol := 0;
      end
      else
        CursorCol := Col;
      if Row > NumRows + FItems.Count then
        Break; // Safety limit
    end;

    if not Found then
    begin
      P.RowStart := Row;
      P.ColStart := 0;
      P.RowEnd := Row + RowSpan;
      P.ColEnd := ColSpan;
    end;

    // Expand tracks
    while FColTracks.Count < P.ColEnd do
    begin
      Track.Size := TPixieCssLength.PredefValue(0);
      Track.Base := 0;
      Track.Position := 0;
      FColTracks.Add(Track);
    end;
    while FRowTracks.Count < P.RowEnd do
    begin
      Track.Size := TPixieCssLength.PredefValue(0);
      Track.Base := 0;
      Track.Position := 0;
      FRowTracks.Add(Track);
    end;
    FOccupancy.Mark(P.RowStart, P.ColStart, P.RowEnd, P.ColEnd);
    NumCols := Max(NumCols, FColTracks.Count);
    NumRows := Max(NumRows, FRowTracks.Count);
    CursorRow := P.RowStart;
    Item.Placement := P;
  end;
end;

// --- Track sizing ---

procedure TPixieRenderGrid.ResolveColumnTracks(ContainerWidth: TPixiePixel);
var
  I, J: Integer;
  T: TPixieGridTrack;
  TotalFixed, TotalFr, FrSpace, Pos, Gap: TPixiePixel;
  TotalGaps: TPixiePixel;
begin
  Gap := GapVal(Css.ColumnGap);
  TotalGaps := 0;
  if FColTracks.Count > 1 then
    TotalGaps := Gap * (FColTracks.Count - 1);

  TotalFixed := 0;
  TotalFr := 0;

  // First pass: resolve fixed and percentage tracks, sum fr
  for I := 0 to FColTracks.Count - 1 do
  begin
    T := FColTracks[I];
    if T.HasMinmax then
    begin
      // minmax: resolve min as base, max determines growth.
      // Content-based min (predefined) preserves size from previous pass.
      if T.MinSize.IsPredefined then
        { keep T.Base from content sizing }
      else if T.MinSize.Units = cssUnitsPercentage then
        T.Base := ContainerWidth * T.MinSize.Val / 100
      else
        T.Base := T.MinSize.Val;
      // Count fr from max; otherwise count base as fixed
      if (not T.MaxSize.IsPredefined) and (T.MaxSize.Units = cssUnitsFr) then
        TotalFr := TotalFr + T.MaxSize.Val
      else
        TotalFixed := TotalFixed + T.Base;
    end
    else if T.Size.IsPredefined then
    begin
      // auto — preserve content-based size from previous pass
      TotalFixed := TotalFixed + T.Base;
    end
    else if T.Size.Units = cssUnitsFr then
    begin
      T.Base := 0;
      TotalFr := TotalFr + T.Size.Val;
    end
    else if T.Size.Units = cssUnitsPercentage then
    begin
      T.Base := ContainerWidth * T.Size.Val / 100;
      TotalFixed := TotalFixed + T.Base;
    end
    else
    begin
      T.Base := T.Size.Val;
      TotalFixed := TotalFixed + T.Base;
    end;
    FColTracks[I] := T;
  end;

  // Size auto tracks from item content (use minimum content size)
  for I := 0 to FItems.Count - 1 do
  begin
    if (FItems[I].Placement.ColEnd - FItems[I].Placement.ColStart = 1) then
    begin
      J := FItems[I].Placement.ColStart;
      if (J >= 0) and (J < FColTracks.Count) then
      begin
        T := FColTracks[J];
        if T.Size.IsPredefined then
        begin
          // For auto tracks, will be sized after rendering items
          // Set initial size to 0; actual sizing happens in RenderItemsAtColumnWidths
        end;
        FColTracks[J] := T;
      end;
    end;
  end;

  // Distribute fr space
  FrSpace := ContainerWidth - TotalFixed - TotalGaps;
  if FrSpace < 0 then
    FrSpace := 0;

  if TotalFr > 0 then
  begin
    for I := 0 to FColTracks.Count - 1 do
    begin
      T := FColTracks[I];
      if T.HasMinmax and (not T.MaxSize.IsPredefined) and
         (T.MaxSize.Units = cssUnitsFr) then
      begin
        T.Base := Max(T.Base, FrSpace * T.MaxSize.Val / TotalFr);
        TotalFixed := TotalFixed + T.Base;
      end
      else if (not T.HasMinmax) and (not T.Size.IsPredefined) and
              (T.Size.Units = cssUnitsFr) then
      begin
        T.Base := FrSpace * T.Size.Val / TotalFr;
        TotalFixed := TotalFixed + T.Base;
      end;
      FColTracks[I] := T;
    end;
  end;

  // Clamp minmax tracks to [min, max]
  for I := 0 to FColTracks.Count - 1 do
  begin
    T := FColTracks[I];
    if T.HasMinmax then
    begin
      // Enforce min
      if not T.MinSize.IsPredefined then
      begin
        if T.MinSize.Units = cssUnitsPercentage then
        begin
          if T.Base < ContainerWidth * T.MinSize.Val / 100 then
            T.Base := ContainerWidth * T.MinSize.Val / 100;
        end
        else if T.Base < T.MinSize.Val then
          T.Base := T.MinSize.Val;
      end;
      // Enforce max (if not fr — fr is handled above)
      if (not T.MaxSize.IsPredefined) and (T.MaxSize.Units <> cssUnitsFr) then
      begin
        if T.MaxSize.Units = cssUnitsPercentage then
        begin
          if T.Base > ContainerWidth * T.MaxSize.Val / 100 then
            T.Base := ContainerWidth * T.MaxSize.Val / 100;
        end
        else if T.Base > T.MaxSize.Val then
          T.Base := T.MaxSize.Val;
      end;
      FColTracks[I] := T;
    end;
  end;

  // Compute positions
  Pos := 0;
  for I := 0 to FColTracks.Count - 1 do
  begin
    T := FColTracks[I];
    T.Position := Pos;
    FColTracks[I] := T;
    Pos := Pos + T.Base;
    if I < FColTracks.Count - 1 then
      Pos := Pos + Gap;
  end;
end;

procedure TPixieRenderGrid.RenderItemsAtColumnWidths(
  const SelfSize: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext);
var
  I, J: Integer;
  Item: TPixieGridItem;
  Ri: TPixieRenderItem;
  ColWidth: TPixiePixel;
  T: TPixieGridTrack;
begin
  // First pass: render items to determine content-based track sizes.
  // Auto and minmax(content) tracks start with Base=0, so items in those
  // tracks are rendered with unconstrained width (SelfSize width) first
  // to measure their natural content size.
  for I := 0 to FItems.Count - 1 do
  begin
    Item := FItems[I];
    Ri := TPixieRenderItem(Item.El);

    // Check if any spanned column is content-sized (auto or minmax-content)
    if (Item.Placement.ColEnd - Item.Placement.ColStart = 1) then
    begin
      J := Item.Placement.ColStart;
      if (J >= 0) and (J < FColTracks.Count) then
      begin
        T := FColTracks[J];
        if T.Size.IsPredefined and (T.Base = 0) then
        begin
          // Content-sized track: render in content mode to measure
          // natural (intrinsic) width without stretching to container
          Ri.Render(0, 0,
            SelfSize.NewWidth(SelfSize.RenderWidth.Value - Ri.RenderOffsetWidth,
              SizeModeContent),
            FmtCtx);
          if Ri.Width > T.Base then
          begin
            T.Base := Ri.Width;
            FColTracks[J] := T;
          end;
          Continue;
        end;
      end;
    end;

    ColWidth := TrackSpanSize(FColTracks, Item.Placement.ColStart, Item.Placement.ColEnd);
    Ri.Render(0, 0,
      SelfSize.NewWidth(ColWidth - Ri.RenderOffsetWidth, SizeModeExactWidth),
      FmtCtx);

    // Update auto column tracks from rendered width (single-column items)
    if Item.Placement.ColEnd - Item.Placement.ColStart = 1 then
    begin
      J := Item.Placement.ColStart;
      if (J >= 0) and (J < FColTracks.Count) then
      begin
        T := FColTracks[J];
        if T.Size.IsPredefined and (Ri.Width > T.Base) then
        begin
          T.Base := Ri.Width;
          FColTracks[J] := T;
        end;
      end;
    end;

    // Update auto row tracks from rendered height (single-row items)
    if Item.Placement.RowEnd - Item.Placement.RowStart = 1 then
    begin
      J := Item.Placement.RowStart;
      if (J >= 0) and (J < FRowTracks.Count) then
      begin
        T := FRowTracks[J];
        if (T.Size.IsPredefined or (T.Size.Units = cssUnitsFr)) and
           (Ri.Height > T.Base) then
        begin
          T.Base := Ri.Height;
          FRowTracks[J] := T;
        end;
      end;
    end;
  end;
end;

procedure TPixieRenderGrid.ResolveRowTracks(ContainerHeight: TPixiePixel;
  HeightIsAuto: Boolean);
var
  I: Integer;
  T: TPixieGridTrack;
  TotalFixed, TotalFr, FrSpace, Pos, Gap: TPixiePixel;
  TotalGaps: TPixiePixel;
begin
  Gap := GapVal(Css.RowGap);
  TotalGaps := 0;
  if FRowTracks.Count > 1 then
    TotalGaps := Gap * (FRowTracks.Count - 1);

  TotalFixed := 0;
  TotalFr := 0;

  for I := 0 to FRowTracks.Count - 1 do
  begin
    T := FRowTracks[I];
    if T.Size.IsPredefined then
      // auto: already sized from content in RenderItemsAtColumnWidths
      TotalFixed := TotalFixed + T.Base
    else if T.Size.Units = cssUnitsFr then
    begin
      if HeightIsAuto then
      begin
        // fr rows behave as auto when container height is auto
        TotalFixed := TotalFixed + T.Base;
      end
      else
      begin
        TotalFr := TotalFr + T.Size.Val;
      end;
    end
    else if T.Size.Units = cssUnitsPercentage then
    begin
      if not HeightIsAuto then
        T.Base := ContainerHeight * T.Size.Val / 100
      else
        T.Base := 0;
      TotalFixed := TotalFixed + T.Base;
    end
    else
    begin
      T.Base := T.Size.Val;
      TotalFixed := TotalFixed + T.Base;
    end;
    FRowTracks[I] := T;
  end;

  // Distribute fr space for rows
  if (TotalFr > 0) and not HeightIsAuto then
  begin
    FrSpace := ContainerHeight - TotalFixed - TotalGaps;
    if FrSpace < 0 then
      FrSpace := 0;
    for I := 0 to FRowTracks.Count - 1 do
    begin
      T := FRowTracks[I];
      if (not T.Size.IsPredefined) and (T.Size.Units = cssUnitsFr) then
        T.Base := Max(T.Base, FrSpace * T.Size.Val / TotalFr);
      FRowTracks[I] := T;
    end;
  end;

  // Compute positions
  Pos := 0;
  for I := 0 to FRowTracks.Count - 1 do
  begin
    T := FRowTracks[I];
    T.Position := Pos;
    FRowTracks[I] := T;
    Pos := Pos + T.Base;
    if I < FRowTracks.Count - 1 then
      Pos := Pos + Gap;
  end;
end;

// --- PositionItems ---

procedure TPixieRenderGrid.PositionItems;
var
  I: Integer;
  Item: TPixieGridItem;
  Ri: TPixieRenderItem;
  CellX, CellY, CellW, CellH: TPixiePixel;
  ItemW, ItemH: TPixiePixel;
  AlignI, JustifyI: Integer;
begin
  for I := 0 to FItems.Count - 1 do
  begin
    Item := FItems[I];
    Ri := TPixieRenderItem(Item.El);

    CellX := TrackPosition(FColTracks, Item.Placement.ColStart);
    CellY := TrackPosition(FRowTracks, Item.Placement.RowStart);
    CellW := TrackSpanSize(FColTracks, Item.Placement.ColStart, Item.Placement.ColEnd);
    CellH := TrackSpanSize(FRowTracks, Item.Placement.RowStart, Item.Placement.RowEnd);
    ItemW := Ri.Width;
    ItemH := Ri.Height;

    // Resolve justify (horizontal alignment within cell)
    JustifyI := Ord(Ri.SrcEl.Css.JustifySelf);
    if JustifyI = Ord(faiAuto) then
      JustifyI := Ord(Css.JustifyItems);
    if JustifyI = Ord(faiNormal) then
      JustifyI := Ord(faiStretch);

    // Resolve align (vertical alignment within cell)
    AlignI := Ord(Ri.SrcEl.Css.FlexAlignSelf);
    if AlignI = Ord(faiAuto) then
      AlignI := Ord(Css.FlexAlignItems);
    if AlignI = Ord(faiNormal) then
      AlignI := Ord(faiStretch);

    // Apply horizontal alignment
    case AlignI and $FF of
      Ord(faiStretch):
        Ri.FPos.Y := CellY + Ri.ContentOffsetTop;
      Ord(faiCenter):
        Ri.FPos.Y := CellY + (CellH - ItemH) / 2 + Ri.ContentOffsetTop;
      Ord(faiEnd), Ord(faiFlexEnd), Ord(faiSelfEnd):
        Ri.FPos.Y := CellY + CellH - ItemH + Ri.ContentOffsetTop;
    else // start, flex-start, self-start, baseline
      Ri.FPos.Y := CellY + Ri.ContentOffsetTop;
    end;

    case JustifyI and $FF of
      Ord(faiStretch):
        Ri.FPos.X := CellX + Ri.ContentOffsetLeft;
      Ord(faiCenter):
        Ri.FPos.X := CellX + (CellW - ItemW) / 2 + Ri.ContentOffsetLeft;
      Ord(faiEnd), Ord(faiFlexEnd), Ord(faiSelfEnd):
        Ri.FPos.X := CellX + CellW - ItemW + Ri.ContentOffsetLeft;
    else
      Ri.FPos.X := CellX + Ri.ContentOffsetLeft;
    end;
  end;
end;

// --- _RenderContent ---

function TPixieRenderGrid._RenderContent(X, Y: TPixiePixel;
  SecondPass: Boolean;
  const SelfSize: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext): TPixiePixel;
var
  ContainerWidth, ContainerHeight: TPixiePixel;
  HeightIsAuto: Boolean;
  TotalHeight, RetWidth: TPixiePixel;
  I, RowIdx: Integer;
  T: TPixieGridTrack;
  Ri: TPixieRenderItem;
  Item: TPixieGridItem;
  CellW, CellH: TPixiePixel;
  Mode: UInt32;
  JustifyI, AlignI: Integer;
  RowsChanged: Boolean;
begin
  ContainerWidth := SelfSize.RenderWidth.Value;
  HeightIsAuto := (SelfSize.Height.ValueType = cbcAuto) and
                  (SelfSize.MinHeight.ValueType = cbcNone);
  if SelfSize.Height.ValueType <> cbcAuto then
    ContainerHeight := SelfSize.Height.Value - BoxSizingHeight
  else if SelfSize.MinHeight.ValueType <> cbcNone then
    ContainerHeight := SelfSize.MinHeight.Value - BoxSizingHeight
  else
    ContainerHeight := 0;

  // 1. Collect grid items from children
  CollectItems;

  // 2. Determine explicit grid from templates
  DetermineExplicitGrid;

  // 3. Auto-placement
  AutoPlace;

  // 4. Resolve column tracks
  ResolveColumnTracks(ContainerWidth);

  // 5. Render items at column widths (determines content heights)
  RenderItemsAtColumnWidths(SelfSize, FmtCtx);

  // If auto columns grew, recompute column positions
  ResolveColumnTracks(ContainerWidth);

  // 6. Resolve row tracks
  ResolveRowTracks(ContainerHeight, HeightIsAuto);

  RowsChanged := False;

  // Re-render items at resolved cell sizes
  for I := 0 to FItems.Count - 1 do
  begin
    Item := FItems[I];
    Ri := TPixieRenderItem(Item.El);
    CellW := TrackSpanSize(FColTracks, Item.Placement.ColStart, Item.Placement.ColEnd);
    CellH := TrackSpanSize(FRowTracks, Item.Placement.RowStart, Item.Placement.RowEnd);

    // Resolve justify-self for this item
    JustifyI := Ord(Ri.SrcEl.Css.JustifySelf);
    if JustifyI = Ord(faiAuto) then
      JustifyI := Ord(Css.JustifyItems);
    if JustifyI = Ord(faiNormal) then
      JustifyI := Ord(faiStretch);

    // Resolve align-self for this item (cross-axis = vertical for grid)
    AlignI := Ord(Ri.SrcEl.Css.FlexAlignSelf);
    if AlignI = Ord(faiAuto) then
      AlignI := Ord(Css.FlexAlignItems);
    if AlignI = Ord(faiNormal) then
      AlignI := Ord(faiStretch);

    Mode := 0;
    // Only stretch auto-height items to cell height when align is stretch.
    // For center/start/end, keep content height so PositionItems can offset.
    if Ri.SrcEl.Css.CssHeight.IsPredefined and
       ((AlignI and $FF) = Ord(faiStretch)) then
      Mode := Mode or SizeModeExactHeight;

    if Ri.SrcEl.Css.CssWidth.IsPredefined and
       ((JustifyI and $FF) <> Ord(faiStretch)) then
    begin
      // Non-stretch justify: render at content width, then center/end
      Ri.Render(0, 0,
        SelfSize.NewWidthHeight(
          CellW - Ri.RenderOffsetWidth,
          CellH - Ri.RenderOffsetHeight,
          Mode or SizeModeContent),
        FmtCtx);
    end
    else
    begin
      if Ri.SrcEl.Css.CssWidth.IsPredefined then
        Mode := Mode or SizeModeExactWidth;
      Ri.Render(0, 0,
        SelfSize.NewWidthHeight(
          CellW - Ri.RenderOffsetWidth,
          CellH - Ri.RenderOffsetHeight,
          Mode),
        FmtCtx);
    end;

    // First-pass row sizing used SizeModeContent and ignored explicit CSS
    // heights. Now that the item has been rendered with proper modes,
    // grow auto/fr row tracks to fit any items that ended up taller.
    if Item.Placement.RowEnd - Item.Placement.RowStart = 1 then
    begin
      RowIdx := Item.Placement.RowStart;
      if (RowIdx >= 0) and (RowIdx < FRowTracks.Count) then
      begin
        T := FRowTracks[RowIdx];
        if (T.Size.IsPredefined or (T.Size.Units = cssUnitsFr)) and
           (Ri.Height > T.Base) then
        begin
          T.Base := Ri.Height;
          FRowTracks[RowIdx] := T;
          RowsChanged := True;
        end;
      end;
    end;
  end;

  if RowsChanged then
    ResolveRowTracks(ContainerHeight, HeightIsAuto);

  // 7. Position items in their cells
  PositionItems;

  // Calculate total height
  if FRowTracks.Count > 0 then
  begin
    T := FRowTracks[FRowTracks.Count - 1];
    TotalHeight := T.Position + T.Base;
  end
  else
    TotalHeight := 0;

  FPos.Height := TotalHeight;

  // Calculate return width (min content width)
  RetWidth := 0;
  if FColTracks.Count > 0 then
  begin
    T := FColTracks[FColTracks.Count - 1];
    RetWidth := T.Position + T.Base;
  end;

  Result := RetWidth;
end;

initialization
  PixieRenderGridClass := TPixieRenderGrid;

end.
