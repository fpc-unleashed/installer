unit Pixie.RenderBlockContext;

// Block formatting context — stacks block children vertically with
// margin collapsing, float placement, and relative positioning.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Math,
  Pixie.Types, Pixie.CssLength, Pixie.CssProperties,
  Pixie.Element, Pixie.FormattingContext,
  Pixie.RenderItem, Pixie.RenderBlock;

type
  { TPixieRenderBlockContext }
  TPixieRenderBlockContext = class(TPixieRenderBlock)
  protected
    function _RenderContent(X, Y: TPixiePixel; SecondPass: Boolean;
      const SelfSize: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext): TPixiePixel; override;
  public
    constructor Create(ASrcEl: TPixieElement); override;
    function Clone: TPixieRenderItem; override;
    procedure ApplyVerticalAlign; override;
    function GetFirstBaseline: TPixiePixel; override;
    function GetLastBaseline: TPixiePixel; override;
  end;

implementation

uses
  Pixie.Document;

{ TPixieRenderBlockContext }

constructor TPixieRenderBlockContext.Create(ASrcEl: TPixieElement);
begin
  inherited Create(ASrcEl);
end;

function TPixieRenderBlockContext.Clone: TPixieRenderItem;
begin
  Result := TPixieRenderBlockContext.Create(FElement);
end;

procedure TPixieRenderBlockContext.ApplyVerticalAlign;
var
  ContentHeight, Add: TPixiePixel;
  I: Integer;
begin
  if FChildren.Count = 0 then
    Exit;
  ContentHeight := 0;
  for I := 0 to FChildren.Count - 1 do
    ContentHeight := Max(ContentHeight,
      FChildren[I].FPos.Y + FChildren[I].Height);
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
    if Add <> 0 then
      for I := 0 to FChildren.Count - 1 do
        FChildren[I].YShift(Add);
  end;
end;

function TPixieRenderBlockContext._RenderContent(X, Y: TPixiePixel;
  SecondPass: Boolean;
  const SelfSize: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext): TPixiePixel;
var
  ElPosition: TPixieElementPosition;
  RetWidth, ChildTop, LastMargin: TPixiePixel;
  IsFirst: Boolean;
  I: Integer;
  El: TPixieRenderItem;
  ElCss: TPixieCssProperties;
  ChildMargins: TPixieMargins;
  LastMarginEl: TPixieRenderItem;
  ChildX, ChildWidth, LineRight, TopMargin: TPixiePixel;
  LineLeft: TPixiePixel;
  Rw: TPixiePixel;
  MinRenderedWidth: TPixiePixel;
  NewTop, LnLeft, LnRight: TPixiePixel;
  AutoMargin: TPixiePixel;
  SavedChildTop: TPixiePixel;
  SelfCollapsed: TPixiePixel;
  PreRenderMarginTop, OldCollapse, NewCollapse, Delta: TPixiePixel;
begin
  RetWidth := 0;
  ChildTop := 0;
  LastMargin := 0;
  LastMarginEl := nil;
  IsFirst := True;

  for I := 0 to FChildren.Count - 1 do
  begin
    El := FChildren[I];
    ElCss := El.SrcEl.Css;

    // Skip absolute/fixed on second pass
    if SecondPass then
    begin
      ElPosition := ElCss.ElPosition;
      if ElPosition in [epAbsolute, epFixed] then
        Continue;
    end;

    if ElCss.Float_ <> efNone then
    begin
      Rw := PlaceFloat(El, ChildTop, SelfSize, FmtCtx);
      if Rw > RetWidth then
        RetWidth := Rw;
    end
    else if ElCss.Display <> displayNone then
    begin
      if ElCss.ElPosition in [epAbsolute, epFixed] then
      begin
        MinRenderedWidth := El.Render(0, ChildTop, SelfSize, FmtCtx);
        if (MinRenderedWidth < El.Width) and ElCss.CssWidth.IsPredefined then
          El.Render(0, ChildTop, SelfSize.NewWidth(MinRenderedWidth), FmtCtx);
      end
      else
      begin
        ChildTop := FmtCtx.GetClearedTop(ElCss.Clear_, ElCss.Float_, ChildTop);
        ChildX := 0;
        ChildWidth := SelfSize.RenderWidth.Value;
        LineRight := SelfSize.RenderWidth.Value;
        TopMargin := FMargins.Top;

        El.CalcOutlines(SelfSize.Width.Value);

        // Adjust width for replaced/BFC/table elements with floats
        if El.SrcEl.IsReplaced or
           El.SrcEl.IsBlockFormattingContext or
           (ElCss.Display = displayTable) then
        begin
          LineLeft := 0;
          FmtCtx.GetLineLeftRight(ChildTop, ChildWidth, LineLeft, LineRight);
          if LineLeft <> ChildX then
            ChildX := LineLeft - El.MarginLeft;
          if LineRight <> SelfSize.RenderWidth.Value then
            LineRight := LineRight + El.MarginRight;
          if El.Css.CssWidth.IsPredefined then
            ChildWidth := LineRight - LineLeft;
        end;

        // Collapse top margin
        SavedChildTop := ChildTop;
        ChildMargins := El.GetMargins;
        PreRenderMarginTop := ChildMargins.Top;
        if IsFirst and CollapseTopMargin then
        begin
          if ChildMargins.Top > 0 then
          begin
            ChildTop := ChildTop - ChildMargins.Top;
            if ChildMargins.Top > GetMargins.Top then
              TopMargin := ChildMargins.Top;
          end;
        end
        else
        begin
          if ChildMargins.Top > 0 then
          begin
            if LastMargin > ChildMargins.Top then
              ChildTop := ChildTop - ChildMargins.Top
            else
              ChildTop := ChildTop - LastMargin;
          end;
        end;

        Rw := El.Render(ChildX, ChildTop, SelfSize.NewWidth(ChildWidth), FmtCtx);
        // Table auto-width re-render
        if (ElCss.Display = displayTable) and (Rw < ChildWidth) and
           ElCss.CssWidth.IsPredefined then
          El.Render(ChildX, ChildTop, SelfSize.NewWidth(Rw), FmtCtx);
        ChildMargins := El.GetMargins;

        // Post-render parent-child margin propagation fix:
        // If the child's top margin grew during render (its first child's
        // margin collapsed through), retroactively apply sibling collapsing.
        if ChildMargins.Top > PreRenderMarginTop then
        begin
          if IsFirst and CollapseTopMargin then
          begin
            Delta := ChildMargins.Top - PreRenderMarginTop;
            El.FPos.Y := El.FPos.Y - Delta;
            ChildTop := ChildTop - Delta;
            if ChildMargins.Top > TopMargin then
              TopMargin := ChildMargins.Top;
          end
          else if not IsFirst then
          begin
            if PreRenderMarginTop > 0 then
              OldCollapse := Min(LastMargin, PreRenderMarginTop)
            else
              OldCollapse := 0;
            NewCollapse := Min(LastMargin, ChildMargins.Top);
            Delta := NewCollapse - OldCollapse;
            if Delta > 0 then
            begin
              El.FPos.Y := El.FPos.Y - Delta;
              ChildTop := ChildTop - Delta;
            end;
          end;
        end;

        // Move block if it overflows float area
        if El.SrcEl.IsReplaced or
           El.SrcEl.IsBlockFormattingContext or
           (ElCss.Display = displayTable) then
        begin
          if El.Right > LineRight then
          begin
            LnLeft := 0;
            LnRight := El.Width;
            NewTop := FmtCtx.FindNextLineTop(ChildTop, El.Width, LnRight);
            if NewTop <> ChildTop then
            begin
              ChildTop := NewTop;
              FmtCtx.GetLineLeftRight(ChildTop, El.Width, LnLeft, LnRight);
              El.FPos.X := LnLeft + El.ContentOffsetLeft;
              El.FPos.Y := ChildTop + El.ContentOffsetTop;
              ChildTop := ChildTop - ChildMargins.Top;
              // Rollback top margin collapse
              if IsFirst and CollapseTopMargin then
                TopMargin := FMargins.Top;
            end;
          end;
        end;

        AutoMargin := El.CalcAutoMargins(ChildWidth);
        if AutoMargin <> 0 then
          El.FPos.X := El.FPos.X + AutoMargin;

        if Rw > RetWidth then
          RetWidth := Rw;

        FMargins.Top := TopMargin;

        // Self-collapsing elements: zero content, padding, and borders.
        // Their top and bottom margins collapse through each other and
        // merge with the adjacent sibling margins (CSS2 8.3.1).
        if (El.FPos.Height = 0) and
           (El.FPadding.Height = 0) and
           (El.FBorders.Height = 0) then
        begin
          ChildTop := SavedChildTop;
          SelfCollapsed := ChildMargins.Top;
          if ChildMargins.Bottom > SelfCollapsed then
            SelfCollapsed := ChildMargins.Bottom;
          if SelfCollapsed > LastMargin then
            LastMargin := SelfCollapsed;
        end
        else
        begin
          ChildTop := ChildTop + El.Height;
          LastMargin := ChildMargins.Bottom;
          LastMarginEl := El;
          IsFirst := False;
        end;

        if ElCss.ElPosition = epRelative then
          El.ApplyRelativeShift(SelfSize);
      end;
    end;
  end;

  // CSS 2.1 § 17.5.3: declared height on a table cell is a minimum, not
  // exact — leave FPos.Height at the natural content height here so the
  // outer _Render pass can apply the declared value as a floor.
  if (SelfSize.Height.ValueType <> cbcAuto) and (SelfSize.Height.Value > 0) and
     (SrcEl.Css.Display <> displayTableCell) then
    FPos.Height := SelfSize.Height.Value
  else
  begin
    FPos.Height := ChildTop;
    if CollapseBottomMargin then
    begin
      FPos.Height := FPos.Height - LastMargin;
      if FMargins.Bottom < LastMargin then
        FMargins.Bottom := LastMargin;
      if LastMarginEl <> nil then
        LastMarginEl.FMargins.Bottom := 0;
    end;
  end;

  Result := RetWidth;
end;

function TPixieRenderBlockContext.GetFirstBaseline: TPixiePixel;
var
  I: Integer;
  Item: TPixieRenderItem;
begin
  for I := 0 to FChildren.Count - 1 do
  begin
    Item := FChildren[I];
    if Item.SrcEl.InNormalFlow then
      Exit(ContentOffsetTop + Item.Top + Item.GetFirstBaseline);
  end;
  Result := Height - MarginBottom;
end;

function TPixieRenderBlockContext.GetLastBaseline: TPixiePixel;
var
  I: Integer;
  Item: TPixieRenderItem;
begin
  for I := FChildren.Count - 1 downto 0 do
  begin
    Item := FChildren[I];
    if Item.SrcEl.InNormalFlow then
      Exit(ContentOffsetTop + Item.Top + Item.GetLastBaseline);
  end;
  Result := Height - MarginBottom;
end;

initialization
  PixieRenderBlockContextClass := TPixieRenderBlockContext;

end.
