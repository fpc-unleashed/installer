unit Pixie.RenderInlineContext;

// Inline formatting context — lays out inline elements in line boxes,
// handles whitespace collapsing, text wrapping, and vertical alignment.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Generics.Collections, Math,
  Pixie.Types, Pixie.CssLength, Pixie.CssProperties,
  Pixie.Element, Pixie.FormattingContext,
  Pixie.Container, Pixie.RenderItem, Pixie.RenderBlock,
  Pixie.LineBox, Pixie.Iterators;

type
  TPixieLineBoxList = TObjectList<TPixieLineBox>;

  { TPixieRenderInlineContext }
  TPixieRenderInlineContext = class(TPixieRenderBlock)
  private
    FLineBoxes: TPixieLineBoxList;
    FMaxLineWidth: TPixiePixel;

    // Iteration state (FPC has no closures)
    FIterSkipSpaces: Boolean;
    FIterWasSpace: Boolean;
    FIterSelfSize: TPixieContainingBlockContext;
    FIterFmtCtx: TPixieFormattingContext;
    FSuppressStrut: Boolean;

    function FinishLastBox(EndOfRender: Boolean;
      const SelfSize: TPixieContainingBlockContext): TPixieLineBoxItemList;
    procedure PlaceInline(Item: TPixieLineBoxItem;
      const SelfSize: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext);
    function NewBox(Item: TPixieLineBoxItem; var LineCtx: TPixieLineContext;
      const SelfSize: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext): TPixiePixel;

    procedure InlineIterCallback(El: TPixieRenderItem;
      ItemType: TPixieIteratorItemType);
  protected
    function _RenderContent(X, Y: TPixiePixel; SecondPass: Boolean;
      const SelfSize: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext): TPixiePixel; override;
    procedure FixLineWidth(Flt: TPixieElementFloat;
      const SelfSize: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext); override;
  public
    constructor Create(ASrcEl: TPixieElement); override;
    destructor Destroy; override;
    function Clone: TPixieRenderItem; override;
    function GetFirstBaseline: TPixiePixel; override;
    function GetLastBaseline: TPixiePixel; override;
    procedure ApplyVerticalAlign; override;
  end;

implementation

uses
  Pixie.Document;

{ TPixieRenderInlineContext }

constructor TPixieRenderInlineContext.Create(ASrcEl: TPixieElement);
begin
  inherited Create(ASrcEl);
  FLineBoxes := TPixieLineBoxList.Create(True);
  FMaxLineWidth := 0;
end;

destructor TPixieRenderInlineContext.Destroy;
begin
  FLineBoxes.Free;
  inherited;
end;

function TPixieRenderInlineContext.Clone: TPixieRenderItem;
begin
  Result := TPixieRenderInlineContext.Create(FElement);
end;

// --- Iteration callback ---

procedure TPixieRenderInlineContext.InlineIterCallback(El: TPixieRenderItem;
  ItemType: TPixieIteratorItemType);
begin
  case ItemType of
    iitChild:
    begin
      if FIterSkipSpaces then
      begin
        if El.SrcEl.IsWhiteSpace then
        begin
          if FIterWasSpace then
          begin
            El.SetSkip(True);
            Exit;
          end
          else
            FIterWasSpace := True;
        end
        else
          FIterWasSpace := El.SrcEl.IsBreak;
      end;
      PlaceInline(TPixieLineBoxItem.Create(El), FIterSelfSize, FIterFmtCtx);
    end;
    iitStartParent:
    begin
      El.ClearInlineBoxes;
      PlaceInline(TPixieLbiStart.Create(El), FIterSelfSize, FIterFmtCtx);
    end;
    iitEndParent:
      PlaceInline(TPixieLbiEnd.Create(El), FIterSelfSize, FIterFmtCtx);
  end;
end;

// --- _RenderContent ---

function TPixieRenderInlineContext._RenderContent(X, Y: TPixiePixel;
  SecondPass: Boolean;
  const SelfSize: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext): TPixiePixel;
var
  Ws: TPixieWhiteSpace;
  OldTop: TPixiePixel;
  Doc: TObject;
begin
  FLineBoxes.Clear;
  FMaxLineWidth := 0;

  // In limited quirks / quirks mode, suppress the strut in table cells
  // so images don't get extra descent space below them.
  // Also applies to anonymous blocks created inside table cells when
  // inline content is split by block-level elements.
  FSuppressStrut := False;
  if (SrcEl.Css.Display = displayTableCell) or
     ((SrcEl.Parent <> nil) and
      (SrcEl.Parent.Css.Display = displayTableCell)) then
  begin
    Doc := SrcEl.GetDocument;
    if (Doc <> nil) and (Doc is TPixieDocument) then
      FSuppressStrut := TPixieDocument(Doc).Mode <> dmNoQuirks;
  end;

  Ws := SrcEl.Css.WhiteSpace;
  FIterSkipSpaces := Ws in [wsNormal, wsNowrap, wsPreLine];
  // CSS Text 3: white space at the beginning of an inline formatting
  // context is removed. Seed FIterWasSpace so a leading whitespace-only
  // text node is dropped (otherwise it creates a phantom line box that
  // breaks vertical-align: middle on table-cells).
  FIterWasSpace := FIterSkipSpaces;
  FIterSelfSize := SelfSize;
  FIterFmtCtx := FmtCtx;

  PixieIterateElements(Self, True,
    @PixieGoInsideInline, @PixieSelectInline,
    InlineIterCallback);

  FinishLastBox(True, SelfSize).Free;

  if FLineBoxes.Count > 0 then
  begin
    if CollapseTopMargin then
    begin
      OldTop := FMargins.Top;
      FMargins.Top := Max(FLineBoxes[0].TopMargin, FMargins.Top);
      if FMargins.Top <> OldTop then
        FmtCtx.UpdateFloats(FMargins.Top - OldTop, Self);
    end;
    if CollapseBottomMargin then
    begin
      FMargins.Bottom := Max(FLineBoxes[FLineBoxes.Count - 1].BottomMargin,
        FMargins.Bottom);
      FPos.Height := FLineBoxes[FLineBoxes.Count - 1].Bottom -
        FLineBoxes[FLineBoxes.Count - 1].BottomMargin;
    end
    else
      FPos.Height := FLineBoxes[FLineBoxes.Count - 1].Bottom;
  end;

  Result := FMaxLineWidth;
end;

// --- FinishLastBox ---

function TPixieRenderInlineContext.FinishLastBox(EndOfRender: Boolean;
  const SelfSize: TPixieContainingBlockContext): TPixieLineBoxItemList;
begin
  if FLineBoxes.Count > 0 then
  begin
    Result := FLineBoxes[FLineBoxes.Count - 1].Finish(EndOfRender, SelfSize);
    if FLineBoxes[FLineBoxes.Count - 1].IsEmpty and EndOfRender and
       (not FLineBoxes[FLineBoxes.Count - 1].IsBreakOnly) then
      FLineBoxes.Delete(FLineBoxes.Count - 1)
    else
      FMaxLineWidth := Max(FMaxLineWidth,
        FLineBoxes[FLineBoxes.Count - 1].Left +
        FLineBoxes[FLineBoxes.Count - 1].MinWidth);
  end
  else
    Result := TPixieLineBoxItemList.Create(True);
end;

// --- NewBox ---

function TPixieRenderInlineContext.NewBox(Item: TPixieLineBoxItem;
  var LineCtx: TPixieLineContext;
  const SelfSize: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext): TPixiePixel;
var
  Items: TPixieLineBoxItemList;
  LineTop: TPixiePixel;
  FirstLineMargin, TextIndent: TPixiePixel;
  SzFont: TPixiePixel;
  I: Integer;
  RequiredWidth: TPixiePixel;
begin
  Items := FinishLastBox(False, SelfSize);
  try
    LineTop := 0;
    if FLineBoxes.Count > 0 then
      LineTop := FLineBoxes[FLineBoxes.Count - 1].Bottom;
    LineCtx.Top := FmtCtx.GetClearedTop(Item.GetEl.SrcEl.Css.Clear_,
      Item.GetEl.SrcEl.Css.Float_, LineTop);

    LineCtx.Left := 0;
    LineCtx.Right := SelfSize.RenderWidth.Value;
    LineCtx.FixTop;
    FmtCtx.GetLineLeftRight(LineCtx.Top, SelfSize.RenderWidth.Value,
      LineCtx.Left, LineCtx.Right);

    if Item.GetEl.SrcEl.IsInline or Item.GetEl.SrcEl.IsBlockFormattingContext then
    begin
      // CSS 2.1 § 9.5: a box establishing a new BFC must not overlap
      // floats. The rendered Width may have shrunk to the squeezed
      // line space; RenderedMinWidth is the box's true intrinsic width.
      RequiredWidth := Max(Item.GetEl.Width, Item.GetRenderedMinWidth);
      if RequiredWidth > LineCtx.Width then
      begin
        LineCtx.Top := FmtCtx.FindNextLineTop(LineCtx.Top,
          RequiredWidth, SelfSize.RenderWidth.Value);
        LineCtx.Left := 0;
        LineCtx.Right := SelfSize.RenderWidth.Value;
        LineCtx.FixTop;
        FmtCtx.GetLineLeftRight(LineCtx.Top, SelfSize.RenderWidth.Value,
          LineCtx.Left, LineCtx.Right);
        if Item.GetEl.SrcEl.IsBlockFormattingContext then
          Item.GetEl.Render(LineCtx.Left, LineCtx.Top,
            SelfSize.NewWidth(LineCtx.Width), FmtCtx);
      end;
    end;

    FirstLineMargin := 0;
    TextIndent := 0;
    if FLineBoxes.Count = 0 then
    begin
      if (SrcEl.Css.ListStyleType <> lstNone) and
         (SrcEl.Css.ListStylePosition = lspInside) then
      begin
        SzFont := SrcEl.Css.FontSize;
        FirstLineMargin := SzFont;
      end;
      if SrcEl.Css.CssTextIndent.Val <> 0 then
        TextIndent := SrcEl.Css.CssTextIndent.CalcPercent(SelfSize.Width.Value);
    end;

    FLineBoxes.Add(TPixieLineBox.Create(
      LineCtx.Top,
      LineCtx.Left + FirstLineMargin + TextIndent,
      LineCtx.Right,
      Css.LineHeight,
      Css.FontMetrics,
      Css.TextAlign,
      FSuppressStrut));

    // Re-add overflow items from the finished line box
    for I := 0 to Items.Count - 1 do
    begin
      Items.OwnsObjects := False;
      FLineBoxes[FLineBoxes.Count - 1].AddItem(Items[I]);
    end;
    Items.OwnsObjects := False;
  finally
    Items.Free;
  end;

  Result := LineCtx.Top;
end;

// --- PlaceInline ---

procedure TPixieRenderInlineContext.PlaceInline(Item: TPixieLineBoxItem;
  const SelfSize: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext);
var
  LineCtx: TPixieLineContext;
  LineTop: TPixiePixel;
  Ret: TPixiePixel;
  MinRenderedWidth: TPixiePixel;
  AddBox: Boolean;
  Shift, PrevMargin: TPixiePixel;
  Sz: TPixieSize;
begin
  if Item.GetEl.SrcEl.Css.Display = displayNone then
  begin
    Item.Free;
    Exit;
  end;

  if Item.GetEl.SrcEl.IsFloat_ then
  begin
    LineTop := 0;
    if FLineBoxes.Count > 0 then
    begin
      // A float that follows a <br> belongs on the new line the break opened,
      // not back up on the line the break closed; otherwise it floats up to
      // the top of the block and the inline content meant to sit beside it
      // drops below instead.
      if FLineBoxes[FLineBoxes.Count - 1].EndsWithBreak then
        LineTop := FLineBoxes[FLineBoxes.Count - 1].Bottom
      else
        LineTop := FLineBoxes[FLineBoxes.Count - 1].Top;
    end;
    Ret := PlaceFloat(Item.GetEl, LineTop, SelfSize, FmtCtx);
    if Ret > FMaxLineWidth then
      FMaxLineWidth := Ret;
    Item.Free;
    Exit;
  end;

  LineCtx.Init;
  if FLineBoxes.Count > 0 then
    LineCtx.Top := FLineBoxes[FLineBoxes.Count - 1].Top;
  LineCtx.Right := SelfSize.RenderWidth.Value;
  LineCtx.FixTop;
  FmtCtx.GetLineLeftRight(LineCtx.Top, SelfSize.RenderWidth.Value,
    LineCtx.Left, LineCtx.Right);

  if Item.GetItemType = lbiTextPart then
  begin
    if Item.GetEl.SrcEl.IsInlineBox then
    begin
      MinRenderedWidth := Item.GetEl.Render(LineCtx.Left, LineCtx.Top,
        SelfSize.NewWidth(LineCtx.Right), FmtCtx);
      if (MinRenderedWidth < Item.GetEl.Width) and
         Item.GetEl.SrcEl.Css.CssWidth.IsPredefined then
        Item.GetEl.Render(LineCtx.Left, LineCtx.Top,
          SelfSize.NewWidth(MinRenderedWidth), FmtCtx);
      Item.SetRenderedMinWidth(MinRenderedWidth);
    end
    else if Item.GetEl.SrcEl.Css.Display = displayInlineText then
    begin
      Item.GetEl.SrcEl.GetContentSize(Sz, LineCtx.Right);
      Item.GetEl.FPos.Width := Sz.Width;
      Item.GetEl.FPos.Height := Sz.Height;
      Item.SetRenderedMinWidth(Sz.Width);
    end;
  end;

  AddBox := True;
  if FLineBoxes.Count > 0 then
  begin
    if FLineBoxes[FLineBoxes.Count - 1].CanHold(Item,
       SrcEl.Css.WhiteSpace) then
      AddBox := False;
    // CSS 2.1 § 9.5: a BFC item that doesn't fit the current line's
    // float-narrowed space must go to a fresh line box so NewBox's
    // clear-floats logic can push it past them.
    if (not AddBox) and Item.GetEl.SrcEl.IsBlockFormattingContext and
       (Item.GetRenderedMinWidth >
        FLineBoxes[FLineBoxes.Count - 1].LineRight -
        FLineBoxes[FLineBoxes.Count - 1].Left) then
      AddBox := True;
  end;
  if AddBox then
    NewBox(Item, LineCtx, SelfSize, FmtCtx)
  else if FLineBoxes.Count > 0 then
    LineCtx.Top := FLineBoxes[FLineBoxes.Count - 1].Top;

  if LineCtx.Top <> LineCtx.CalculatedTop then
  begin
    LineCtx.Left := 0;
    LineCtx.Right := SelfSize.RenderWidth.Value;
    LineCtx.FixTop;
    FmtCtx.GetLineLeftRight(LineCtx.Top, SelfSize.RenderWidth.Value,
      LineCtx.Left, LineCtx.Right);
  end;

  // Block-in-inline margin collapse
  if not Item.GetEl.SrcEl.IsInline then
  begin
    if FLineBoxes.Count = 1 then
    begin
      if CollapseTopMargin then
      begin
        Shift := Item.GetEl.MarginTop;
        if Shift >= 0 then
        begin
          LineCtx.Top := LineCtx.Top - Shift;
          FLineBoxes[FLineBoxes.Count - 1].YShift(-Shift);
        end;
      end;
    end
    else
    begin
      PrevMargin := FLineBoxes[FLineBoxes.Count - 2].BottomMargin;
      if PrevMargin > Item.GetEl.MarginTop then
        Shift := Item.GetEl.MarginTop
      else
        Shift := PrevMargin;
      if Shift >= 0 then
      begin
        LineCtx.Top := LineCtx.Top - Shift;
        FLineBoxes[FLineBoxes.Count - 1].YShift(-Shift);
      end;
    end;
  end;

  FLineBoxes[FLineBoxes.Count - 1].AddItem(Item);
end;

// --- FixLineWidth ---

procedure TPixieRenderInlineContext.FixLineWidth(Flt: TPixieElementFloat;
  const SelfSize: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext);
var
  ElFront: TPixieRenderItem;
  WasCleared: Boolean;
  Items: TPixieLineBoxItemList;
  LineTop, LineLeft, LineRight: TPixiePixel;
  NewLeft, NewRight: TPixiePixel;
  FirstLineMargin, TextIndent: TPixiePixel;
  SzFont: TPixiePixel;
  I: Integer;
  Lbi: TPixieLineBoxItem;
  LastBox: TPixieLineBox;
begin
  if FLineBoxes.Count = 0 then
    Exit;

  LastBox := FLineBoxes[FLineBoxes.Count - 1];
  NewLeft := 0;
  NewRight := SelfSize.RenderWidth.Value;
  FmtCtx.GetLineLeftRight(LastBox.Top, SelfSize.RenderWidth.Value,
    NewLeft, NewRight);

  // Skip the re-render when the new bounds don't tighten the line, or
  // when the content's CSS min-content still fits — re-flowing flex items
  // with margin: auto would only redistribute slack space.
  FirstLineMargin := 0;
  TextIndent := 0;
  if FLineBoxes.Count = 1 then
  begin
    if (SrcEl.Css.ListStyleType <> lstNone) and
       (SrcEl.Css.ListStylePosition = lspInside) then
      FirstLineMargin := SrcEl.Css.FontSize;
    if SrcEl.Css.CssTextIndent.Val <> 0 then
      TextIndent := SrcEl.Css.CssTextIndent.CalcPercent(SelfSize.Width.Value);
  end;
  if (NewLeft <= LastBox.Left - FirstLineMargin - TextIndent) and
     (NewRight >= LastBox.LineRight) then
    Exit;
  if (LastBox.Left >= NewLeft) and
     (LastBox.Left + LastBox.IntrinsicMinWidth <= NewRight) then
    Exit;

  ElFront := LastBox.GetFirstTextPart;
  WasCleared := False;

  if (ElFront <> nil) and (ElFront.SrcEl.Css.Clear_ <> ecNone) then
  begin
    if ElFront.SrcEl.Css.Clear_ = ecBoth then
      WasCleared := True
    else if (Flt = efLeft) and (ElFront.SrcEl.Css.Clear_ = ecLeft) then
      WasCleared := True
    else if (Flt = efRight) and (ElFront.SrcEl.Css.Clear_ = ecRight) then
      WasCleared := True;
  end;

  if not WasCleared then
  begin
    // Copy items out before deleting the line box (which owns its Items list)
    Items := TPixieLineBoxItemList.Create(False);
    try
      FLineBoxes[FLineBoxes.Count - 1].Items.OwnsObjects := False;
      for I := 0 to FLineBoxes[FLineBoxes.Count - 1].Items.Count - 1 do
        Items.Add(FLineBoxes[FLineBoxes.Count - 1].Items[I]);
      FLineBoxes.Delete(FLineBoxes.Count - 1);

      for I := 0 to Items.Count - 1 do
        PlaceInline(Items[I], SelfSize, FmtCtx);
    finally
      Items.Free;
    end;
  end
  else
  begin
    LineTop := FLineBoxes[FLineBoxes.Count - 1].Top;
    LineLeft := 0;
    LineRight := SelfSize.RenderWidth.Value;
    FmtCtx.GetLineLeftRight(LineTop, SelfSize.RenderWidth.Value,
      LineLeft, LineRight);

    if FLineBoxes.Count = 1 then
    begin
      if (SrcEl.Css.ListStyleType <> lstNone) and
         (SrcEl.Css.ListStylePosition = lspInside) then
      begin
        SzFont := SrcEl.Css.FontSize;
        LineLeft := LineLeft + SzFont;
      end;
      if SrcEl.Css.CssTextIndent.Val <> 0 then
        LineLeft := LineLeft + SrcEl.Css.CssTextIndent.CalcPercent(SelfSize.Width.Value);
    end;

    Items := FLineBoxes[FLineBoxes.Count - 1].NewWidth(LineLeft, LineRight);
    try
      for I := 0 to Items.Count - 1 do
      begin
        Lbi := Items[I];
        Items.OwnsObjects := False;
        PlaceInline(Lbi, SelfSize, FmtCtx);
      end;
      Items.OwnsObjects := False;
    finally
      Items.Free;
    end;
  end;
end;

// --- ApplyVerticalAlign ---

procedure TPixieRenderInlineContext.ApplyVerticalAlign;

  procedure ShiftInlineBoxes(Parent: TPixieRenderItem; Delta: TPixiePixel);
  var
    J: Integer;
    Child: TPixieRenderItem;
  begin
    for J := 0 to Parent.FChildren.Count - 1 do
    begin
      Child := Parent.FChildren[J];
      if Child.SrcEl.Css.Display = displayInline then
      begin
        Child.YShift(Delta);
        ShiftInlineBoxes(Child, Delta);
      end;
    end;
  end;

var
  Add, ContentHeight: TPixiePixel;
  I: Integer;
begin
  if FLineBoxes.Count = 0 then
    Exit;

  ContentHeight := FLineBoxes[FLineBoxes.Count - 1].Bottom;
  Add := 0;

  if FPos.Height > ContentHeight then
  begin
    case SrcEl.Css.VerticalAlign of
      vaMiddle:
        Add := (FPos.Height - ContentHeight) / 2;
      vaBottom:
        Add := FPos.Height - ContentHeight;
    else
      Add := 0;
    end;
  end;

  if Add <> 0 then
  begin
    for I := 0 to FLineBoxes.Count - 1 do
      FLineBoxes[I].YShift(Add);
    // Shift inline children's boxes exactly once (line box YShift no
    // longer shifts them because TPixieLbiStart.YShift only moves the
    // marker's own position to avoid over-shifting multi-line inlines).
    ShiftInlineBoxes(Self, Add);
  end;
end;

// --- Baselines ---

function TPixieRenderInlineContext.GetFirstBaseline: TPixiePixel;
begin
  if FLineBoxes.Count > 0 then
    Result := FLineBoxes[0].Bottom - FLineBoxes[0].Baseline + ContentOffsetTop
  else
    Result := Height - MarginBottom;
end;

function TPixieRenderInlineContext.GetLastBaseline: TPixiePixel;
var
  Last: TPixieLineBox;
begin
  if FLineBoxes.Count > 0 then
  begin
    Last := FLineBoxes[FLineBoxes.Count - 1];
    Result := Last.Bottom - Last.Baseline + ContentOffsetTop;
  end
  else
    Result := Height;
end;

initialization
  PixieRenderInlineContextClass := TPixieRenderInlineContext;

end.
