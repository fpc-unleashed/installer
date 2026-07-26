unit Pixie.RenderFlex;

// Flexbox layout — arranges flex items along main/cross axes with
// wrapping, alignment, and flexible length distribution.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Generics.Collections, Math,
  Pixie.Types, Pixie.CssLength, Pixie.CssProperties,
  Pixie.Element, Pixie.FormattingContext,
  Pixie.RenderItem, Pixie.RenderBlock,
  Pixie.FlexItem;

type
  TPixieFlexLineList = TObjectList<TPixieFlexLine>;

  { TPixieRenderFlex }
  TPixieRenderFlex = class(TPixieRenderBlock)
  private
    FLines: TPixieFlexLineList;

    function GetLines(const SelfSize: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext;
      IsRowDirection: Boolean; ContainerMainSize: TPixiePixel;
      SingleLine: Boolean): TPixieFlexLineList;
  protected
    function _RenderContent(X, Y: TPixiePixel; SecondPass: Boolean;
      const SelfSize: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext): TPixiePixel; override;
  public
    constructor Create(ASrcEl: TPixieElement); override;
    destructor Destroy; override;
    function Clone: TPixieRenderItem; override;
    function Init: TPixieRenderItem; override;
    function GetFirstBaseline: TPixiePixel; override;
    function GetLastBaseline: TPixiePixel; override;
  end;

implementation

uses
  Pixie.HtmlTag, Pixie.Document;

// --- Helpers (must be before _RenderContent which calls them) ---

procedure ReverseList(List: TPixieFlexItemList);
var
  I, J: Integer;
begin
  I := 0;
  J := List.Count - 1;
  List.OwnsObjects := False;
  while I < J do
  begin
    List.Exchange(I, J);
    Inc(I);
    Dec(J);
  end;
  List.OwnsObjects := True;
end;

procedure ReverseObjList(List: TPixieFlexLineList);
var
  I, J: Integer;
begin
  I := 0;
  J := List.Count - 1;
  List.OwnsObjects := False;
  while I < J do
  begin
    List.Exchange(I, J);
    Inc(I);
    Dec(J);
  end;
  List.OwnsObjects := True;
end;

{ TPixieRenderFlex }

constructor TPixieRenderFlex.Create(ASrcEl: TPixieElement);
begin
  inherited Create(ASrcEl);
  FLines := TPixieFlexLineList.Create(True);
end;

destructor TPixieRenderFlex.Destroy;
begin
  FLines.Free;
  inherited;
end;

function TPixieRenderFlex.Clone: TPixieRenderItem;
begin
  Result := TPixieRenderFlex.Create(FElement);
end;

// --- Init ---

function TPixieRenderFlex.Init: TPixieRenderItem;
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
    // Find last non-space
    Last := Inlines.Count - 1;
    while (Last >= 0) and Inlines[Last].SrcEl.IsSpace do
      Dec(Last);
    if Last < 0 then
    begin
      // Free orphaned whitespace-only inlines
      for K := 0 to Inlines.Count - 1 do
        Inlines[K].Free;
      Inlines.Clear;
      Exit;
    end;
    // Free trailing spaces
    for K := Inlines.Count - 1 downto Last + 1 do
    begin
      Inlines[K].Free;
      Inlines.Delete(K);
    end;
    // Wrap in anonymous block
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
  Inlines := TPixieRenderItemList.Create(False); // non-owning
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
          El.Free; // Free leading whitespace
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
          // Wrap non-block, non-inline-text in anonymous block
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

    // Transfer children
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

// --- _RenderContent ---

function TPixieRenderFlex._RenderContent(X, Y: TPixiePixel;
  SecondPass: Boolean;
  const SelfSize: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext): TPixiePixel;
var
  IsRowDirection, Reverse, SingleLine, FitContainer: Boolean;
  ContainerMainSize: TPixiePixel;
  SumCrossSize, SumMainSize, RetWidth: TPixiePixel;
  FreeCrossSize: TPixiePixel;
  IsWrapReverse: Boolean;
  AlignContent: TPixieFlexAlignContent;
  JustifyContent: TPixieFlexJustifyContent;
  LinePos, AddBeforeLine, AddAfterLine: TPixiePixel;
  Add: TPixiePixel;
  CrossGap: TPixiePixel;
  I, J: Integer;
  Ln: TPixieFlexLine;
  El: TPixieRenderItem;
  ItemHeight: TPixiePixel;
  MinSum, MaxMin, ItemMin: TPixiePixel;
begin
  // Determine direction
  IsRowDirection := True;
  Reverse := False;
  ContainerMainSize := SelfSize.RenderWidth.Value;

  case Css.FlexDirection of
    fdColumn:
    begin
      IsRowDirection := False;
      Reverse := False;
    end;
    fdColumnReverse:
    begin
      IsRowDirection := False;
      Reverse := True;
    end;
    fdRow:
    begin
      IsRowDirection := True;
      Reverse := False;
    end;
    fdRowReverse:
    begin
      IsRowDirection := True;
      Reverse := True;
    end;
  end;

  SingleLine := Css.FlexWrap = fwrNowrap;
  FitContainer := False;

  if not IsRowDirection then
  begin
    if SelfSize.Height.ValueType <> cbcAuto then
      ContainerMainSize := SelfSize.Height.Value - BoxSizingHeight
    else
    begin
      ContainerMainSize := 0;
      SingleLine := True;
      FitContainer := True;
    end;
    // CSS 2.1 § 10.7: max-height clamps first, min-height enforces the
    // floor afterwards so min-height wins on conflict. Neither bound
    // flips wrap mode (flex-wrap controls that on its own).
    if (SelfSize.MaxHeight.ValueType <> cbcNone) and
       (SelfSize.MaxHeight.Value < ContainerMainSize) then
      ContainerMainSize := SelfSize.MaxHeight.Value;
    if (SelfSize.MinHeight.ValueType <> cbcNone) and
       (SelfSize.MinHeight.Value > ContainerMainSize) then
      ContainerMainSize := SelfSize.MinHeight.Value;
  end;

  // Split flex items into lines
  FLines.Free;
  FLines := GetLines(SelfSize, FmtCtx, IsRowDirection, ContainerMainSize, SingleLine);

  SumCrossSize := 0;
  SumMainSize := 0;
  RetWidth := 0;
  FIntrinsicMinWidth := 0;

  // Resolve flexible lengths
  for I := 0 to FLines.Count - 1 do
  begin
    Ln := FLines[I];
    if IsRowDirection then
    begin
      RetWidth := RetWidth + Ln.BaseSize;
      // CSS min-content: nowrap → sum of items + gaps; wrap → largest item
      MinSum := 0;
      MaxMin := 0;
      for J := 0 to Ln.Items.Count - 1 do
      begin
        ItemMin := Ln.Items[J].MinSize;
        MinSum := MinSum + ItemMin;
        if ItemMin > MaxMin then
          MaxMin := ItemMin;
      end;
      if SingleLine then
        FIntrinsicMinWidth := Max(FIntrinsicMinWidth, MinSum + Ln.TotalMainGap)
      else
        FIntrinsicMinWidth := Max(FIntrinsicMinWidth, MaxMin);
    end;
    Ln.Init(ContainerMainSize, FitContainer, IsRowDirection, SelfSize, FmtCtx);
    SumCrossSize := SumCrossSize + Ln.CrossSize;
    SumMainSize := Max(SumMainSize, Ln.MainSize);
    if Reverse then
      ReverseList(Ln.Items);
  end;

  FreeCrossSize := 0;
  IsWrapReverse := Css.FlexWrap = fwrWrapReverse;
  if ContainerMainSize = 0 then
    ContainerMainSize := SumMainSize;

  // Cross-axis gap between lines
  if IsRowDirection then
  begin
    CrossGap := Css.RowGap.Val;
    if Css.RowGap.IsPredefined or (CrossGap < 0) then
      CrossGap := 0;
  end
  else
  begin
    CrossGap := Css.ColumnGap.Val;
    if Css.ColumnGap.IsPredefined or (CrossGap < 0) then
      CrossGap := 0;
  end;
  if FLines.Count > 1 then
    SumCrossSize := SumCrossSize + CrossGap * (FLines.Count - 1);

  // Calculate free cross size
  if IsRowDirection then
  begin
    if SelfSize.Height.ValueType <> cbcAuto then
      FreeCrossSize := SelfSize.Height.Value - BoxSizingHeight - SumCrossSize;
  end
  else
  begin
    FreeCrossSize := SelfSize.RenderWidth.Value - SumCrossSize;
    RetWidth := SumCrossSize;
  end;

  // Fix align-content property
  AlignContent := Css.FlexAlignContent;
  if AlignContent = facSpaceBetween then
  begin
    if (FLines.Count = 1) or (FreeCrossSize < 0) then
      AlignContent := facFlexStart;
  end;
  if AlignContent = facSpaceAround then
  begin
    if (FLines.Count = 1) or (FreeCrossSize < 0) then
      AlignContent := facCenter;
  end;

  // Distribute free cross size for stretch
  if (Css.FlexAlignContent = facStretch) and (FreeCrossSize > 0) and
     (FLines.Count > 0) then
  begin
    Add := FreeCrossSize / FLines.Count;
    if Add > 0 then
    begin
      for I := 0 to FLines.Count - 1 do
      begin
        Ln := FLines[I];
        Ln.CrossSize := Ln.CrossSize + Add;
        FreeCrossSize := FreeCrossSize - Add;
      end;
    end;
    if FLines.Count > 0 then
    begin
      while FreeCrossSize > 0 do
      begin
        for I := 0 to FLines.Count - 1 do
        begin
          Ln := FLines[I];
          Ln.CrossSize := Ln.CrossSize + 1;
          FreeCrossSize := FreeCrossSize - 1;
          if FreeCrossSize <= 0 then
            Break;
        end;
      end;
    end;
  end;

  // Reverse lines for wrap-reverse
  if Css.FlexWrap = fwrWrapReverse then
    ReverseObjList(FLines);

  // Align flex lines
  LinePos := 0;
  AddBeforeLine := 0;
  AddAfterLine := 0;

  case AlignContent of
    facFlexStart:
      if IsWrapReverse then
        LinePos := FreeCrossSize;
    facFlexEnd:
      if not IsWrapReverse then
        LinePos := FreeCrossSize;
    facEnd:
      LinePos := FreeCrossSize;
    facCenter:
      LinePos := FreeCrossSize / 2;
    facSpaceBetween:
      if FLines.Count > 1 then
        AddAfterLine := FreeCrossSize / (FLines.Count - 1);
    facSpaceAround:
      if FLines.Count > 0 then
      begin
        AddBeforeLine := FreeCrossSize / (FLines.Count * 2);
        AddAfterLine := AddBeforeLine;
      end;
  else
    // Default: flex-start behavior
    if IsWrapReverse then
      LinePos := FreeCrossSize;
  end;

  for I := 0 to FLines.Count - 1 do
  begin
    Ln := FLines[I];
    LinePos := LinePos + AddBeforeLine;
    if (I > 0) and (CrossGap > 0) then
      LinePos := LinePos + CrossGap;
    Ln.CrossStart := LinePos;
    LinePos := LinePos + Ln.CrossSize + AddAfterLine;
  end;

  // Fix justify-content for column direction
  JustifyContent := Css.FlexJustifyContent;
  if (JustifyContent in [fjcRight, fjcLeft]) and
     (not IsRowDirection) then
    JustifyContent := fjcStart;

  // Place items in lines
  for I := 0 to FLines.Count - 1 do
  begin
    Ln := FLines[I];
    ItemHeight := Ln.CalculateItemsPosition(ContainerMainSize,
      JustifyContent, IsRowDirection, SelfSize, FmtCtx);
    FPos.Height := Max(FPos.Height, ItemHeight);
  end;

  // Render absolutely/fixed-positioned children (out of flex flow)
  for I := 0 to FChildren.Count - 1 do
  begin
    El := FChildren[I];
    if El.SrcEl.Css.ElPosition in [epAbsolute, epFixed] then
      El.Render(0, 0, SelfSize, FmtCtx);
  end;

  // Calculate final position
  FPos.MoveTo(X, Y);
  FPos.X := FPos.X + ContentOffsetLeft;
  FPos.Y := FPos.Y + ContentOffsetTop;

  Result := RetWidth;
end;

// --- GetLines ---

function TPixieRenderFlex.GetLines(const SelfSize: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext;
  IsRowDirection: Boolean; ContainerMainSize: TPixiePixel;
  SingleLine: Boolean): TPixieFlexLineList;
var
  ReverseMain, ReverseCross: Boolean;
  Line: TPixieFlexLine;
  I: Integer;
  El: TPixieRenderItem;
  Item: TPixieFlexItem;
  SrcOrderIdx: Integer;
  SortRequired: Boolean;
  PrevOrder: Integer;
  PrevOrderSet: Boolean;
  Items: TPixieFlexItemList;
  J, MinIdx: Integer;
  MainGap: TPixiePixel;
begin
  ReverseCross := Css.FlexWrap = fwrWrapReverse;

  if IsRowDirection then
  begin
    ReverseMain := Css.FlexDirection = fdRowReverse;
    MainGap := Css.ColumnGap.Val;
    if Css.ColumnGap.IsPredefined or (MainGap < 0) then
      MainGap := 0;
  end
  else
  begin
    ReverseMain := Css.FlexDirection = fdColumnReverse;
    MainGap := Css.RowGap.Val;
    if Css.RowGap.IsPredefined or (MainGap < 0) then
      MainGap := 0;
  end;

  // Create and init all flex items
  Items := TPixieFlexItemList.Create(True);
  SrcOrderIdx := 0;
  SortRequired := False;
  PrevOrderSet := False;
  PrevOrder := 0;

  for I := 0 to FChildren.Count - 1 do
  begin
    El := FChildren[I];

    // Absolutely/fixed-positioned children are out-of-flow and do not
    // participate in flex layout (CSS Flexbox §4.1).
    if El.SrcEl.Css.ElPosition in [epAbsolute, epFixed] then
      Continue;

    if IsRowDirection then
      Item := TPixieFlexItemRow.Create(El)
    else
      Item := TPixieFlexItemColumn.Create(El);
    Item.Init(SelfSize, FmtCtx, Ord(Css.FlexAlignItems));
    Item.SrcOrder := SrcOrderIdx;
    Inc(SrcOrderIdx);

    if not PrevOrderSet then
    begin
      PrevOrder := Item.Order;
      PrevOrderSet := True;
    end
    else if (not SortRequired) and (Item.Order <> PrevOrder) then
      SortRequired := True;

    Items.Add(Item);
  end;

  // Sort by order, then src_order (selection sort — typically small lists)
  if SortRequired then
  begin
    for I := 0 to Items.Count - 2 do
    begin
      MinIdx := I;
      for J := I + 1 to Items.Count - 1 do
      begin
        if Items[J].CompareTo(Items[MinIdx]) < 0 then
          MinIdx := J;
      end;
      if MinIdx <> I then
        Items.Exchange(I, MinIdx);
    end;
  end;

  // Split items into lines
  Result := TPixieFlexLineList.Create(True);
  Line := TPixieFlexLine.Create(ReverseMain, ReverseCross);
  Line.MainGap := MainGap;

  for I := 0 to Items.Count - 1 do
  begin
    Item := Items[I];
    // <br> as a flex child forces a new flex line and is itself dropped
    // (matches Chrome — strict spec wraps the run + <br> + run into one
    // anonymous flex item with internal inline formatting; the visible
    // effect is the same).
    if (TPixieRenderItem(Item.El).SrcEl <> nil) and
       TPixieRenderItem(Item.El).SrcEl.IsBreak then
    begin
      if Line.Items.Count > 0 then
      begin
        Result.Add(Line);
        Line := TPixieFlexLine.Create(ReverseMain, ReverseCross);
        Line.MainGap := MainGap;
      end;
      Items.OwnsObjects := True;
      Items[I] := nil;
      Continue;
    end;
    // Allow ~0.5px slack to swallow floating-point rounding when sibling
    // percentage widths sum to exactly 100% (e.g. 33.3333% + 66.6667%).
    // Without this, the slightly-over-100% rounded total trips a spurious
    // wrap that real browsers don't.
    // 0.01px tolerance to absorb single-precision rounding when sibling
    // percentages sum to exactly 100% (e.g. 33.3333% + 66.6667% on a 400px
    // container yields 400.000015 — the wrap below would fire spuriously
    // and Edge does not wrap that). The threshold is far below any visible
    // overshoot, so legitimate overflows (e.g. 0.1px+) still wrap.
    if (Line.Items.Count > 0) and (not SingleLine) and
       (Line.MainSize + MainGap + Item.MainSize > ContainerMainSize + 0.01) then
    begin
      Result.Add(Line);
      Line := TPixieFlexLine.Create(ReverseMain, ReverseCross);
      Line.MainGap := MainGap;
    end;
    if Line.Items.Count > 0 then
    begin
      Line.BaseSize := Line.BaseSize + MainGap;
      Line.MainSize := Line.MainSize + MainGap;
    end;
    Line.BaseSize := Line.BaseSize + Item.BaseSize;
    Line.MainSize := Line.MainSize + Item.MainSize;
    if not Item.AutoMarginMainStart.IsDefault then
      Line.NumAutoMarginMainStart := Line.NumAutoMarginMainStart + 1;
    if not Item.AutoMarginMainEnd.IsDefault then
      Line.NumAutoMarginMainEnd := Line.NumAutoMarginMainEnd + 1;
    // Transfer item ownership from Items to Line.Items
    Items.OwnsObjects := False;
    Items[I] := nil;
    Items.OwnsObjects := True;
    Line.Items.Add(Item);
  end;

  if Line.Items.Count > 0 then
    Result.Add(Line)
  else
    Line.Free;

  Items.Free;
end;

// --- Baselines ---

function TPixieRenderFlex.GetFirstBaseline: TPixiePixel;
var
  FirstLine: TPixieFlexLine;
begin
  if Css.FlexDirection in [fdRow, fdRowReverse] then
  begin
    if FLines.Count > 0 then
    begin
      FirstLine := FLines[0];
      if FirstLine.FirstBaseline.BaselineType <> btNone then
        Exit(FirstLine.CrossStart +
          FirstLine.FirstBaseline.GetOffsetFromTop(FirstLine.CrossSize) +
          ContentOffsetTop);
      if FirstLine.LastBaseline.BaselineType <> btNone then
        Exit(FirstLine.CrossStart +
          FirstLine.LastBaseline.GetOffsetFromTop(FirstLine.CrossSize) +
          ContentOffsetTop);
    end;
  end;
  if (FLines.Count > 0) and (FLines[0].Items.Count > 0) then
  begin
    Assert(TObject(FLines[0].Items[0].El) is TPixieRenderItem);
    Exit(TPixieRenderItem(FLines[0].Items[0].El).GetFirstBaseline + ContentOffsetTop);
  end;
  Result := Height;
end;

function TPixieRenderFlex.GetLastBaseline: TPixiePixel;
var
  FirstLine: TPixieFlexLine;
begin
  if Css.FlexDirection in [fdRow, fdRowReverse] then
  begin
    if FLines.Count > 0 then
    begin
      FirstLine := FLines[0];
      if FirstLine.LastBaseline.BaselineType <> btNone then
        Exit(FirstLine.CrossStart +
          FirstLine.LastBaseline.GetOffsetFromTop(FirstLine.CrossSize) +
          ContentOffsetTop);
      if FirstLine.FirstBaseline.BaselineType <> btNone then
        Exit(FirstLine.CrossStart +
          FirstLine.FirstBaseline.GetOffsetFromTop(FirstLine.CrossSize) +
          ContentOffsetTop);
    end;
  end;
  if (FLines.Count > 0) and (FLines[0].Items.Count > 0) then
  begin
    Assert(TObject(FLines[0].Items[0].El) is TPixieRenderItem);
    Exit(TPixieRenderItem(FLines[0].Items[0].El).GetLastBaseline + ContentOffsetTop);
  end;
  Result := Height;
end;

end.
