unit Pixie.RenderBlock;

// Block-level render item — the base for block context, inline context,
// flex and table layout.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Math, Generics.Collections,
  Pixie.Types, Pixie.CssLength, Pixie.CssProperties,
  Pixie.Element, Pixie.FormattingContext,
  Pixie.Container, Pixie.RenderItem;

type
  TPixieRenderItemClass = class of TPixieRenderItem;

  { TPixieRenderBlock }
  TPixieRenderBlock = class(TPixieRenderItem)
  protected
    function _RenderContent(X, Y: TPixiePixel; SecondPass: Boolean;
      const SelfSize: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext): TPixiePixel; virtual;
    function _Render(X, Y: TPixiePixel;
      const CbContext: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext;
      SecondPass: Boolean): TPixiePixel; override;
    function PlaceFloat(El: TPixieRenderItem; FloatTop: TPixiePixel;
      const SelfSize: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext): TPixiePixel;
    procedure FixLineWidth(Flt: TPixieElementFloat;
      const SelfSize: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext); virtual;
  public
    constructor Create(ASrcEl: TPixieElement); override;
    function Clone: TPixieRenderItem; override;
    function Init: TPixieRenderItem; override;
  end;

var
  PixieRenderBlockContextClass: TPixieRenderItemClass;
  PixieRenderInlineContextClass: TPixieRenderItemClass;
  PixieRenderGridClass: TPixieRenderItemClass;

implementation

uses
  Pixie.Document, Pixie.HtmlTag;

{ TPixieRenderBlock }

constructor TPixieRenderBlock.Create(ASrcEl: TPixieElement);
begin
  inherited Create(ASrcEl);
end;

function TPixieRenderBlock.Clone: TPixieRenderItem;
begin
  Result := TPixieRenderBlock.Create(FElement);
end;

function TPixieRenderBlock._RenderContent(X, Y: TPixiePixel; SecondPass: Boolean;
  const SelfSize: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext): TPixiePixel;
begin
  Result := 0;
end;

procedure TPixieRenderBlock.FixLineWidth(Flt: TPixieElementFloat;
  const SelfSize: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext);
begin
  // no-op in base class; overridden by RenderInlineContext
end;

// --- PlaceFloat ---

function TPixieRenderBlock.PlaceFloat(El: TPixieRenderItem; FloatTop: TPixiePixel;
  const SelfSize: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext): TPixiePixel;
var
  LineTop, LineLeft, LineRight: TPixiePixel;
  MinRenderedWidth: TPixiePixel;
  Fb: TPixieFloatedBox;
  NewTop: TPixiePixel;
begin
  Result := 0;

  LineTop := FmtCtx.GetClearedTop(El.SrcEl.Css.Clear_, El.SrcEl.Css.Float_, FloatTop);
  LineLeft := 0;
  LineRight := SelfSize.RenderWidth.Value;
  FmtCtx.GetLineLeftRight(LineTop, SelfSize.RenderWidth.Value, LineLeft, LineRight);

  MinRenderedWidth := El.Render(LineLeft, LineTop, SelfSize.NewWidth(LineRight), FmtCtx);
  if (MinRenderedWidth < El.Width) and El.SrcEl.Css.CssWidth.IsPredefined then
    // The shrink-to-fit re-render must keep the float's percentage margins
    // resolved against the actual containing block (not the new tiny width),
    // so pass the content width with SizeModeExactWidth to skip CalcOutlines.
    El.Render(LineLeft, LineTop,
      SelfSize.NewWidth(MinRenderedWidth - El.ContentOffsetWidth,
                        SizeModeExactWidth),
      FmtCtx);

  // Build the floated box record
  Fb.Pos := TPixiePosition.Create(El.FPos.X - El.ContentOffsetLeft,
    El.FPos.Y - El.ContentOffsetTop, El.Width, El.Height);
  Fb.FloatSide := El.SrcEl.Css.Float_;
  Fb.ClearFloats := El.SrcEl.Css.Clear_;
  Fb.El := El;
  Fb.Context := SelfSize.ContextIdx;
  Fb.MinWidth := MinRenderedWidth;

  if El.SrcEl.Css.Float_ = efLeft then
  begin
    if El.Right > LineRight then
    begin
      NewTop := FmtCtx.FindNextLineTop(El.Top, El.Width, SelfSize.RenderWidth.Value);
      El.FPos.X := FmtCtx.GetLineLeft(NewTop) + El.ContentOffsetLeft;
      El.FPos.Y := NewTop + El.ContentOffsetTop;
      // Update Fb position
      Fb.Pos := TPixiePosition.Create(El.FPos.X - El.ContentOffsetLeft,
        El.FPos.Y - El.ContentOffsetTop, El.Width, El.Height);
    end;
    FmtCtx.AddFloat(Fb);
    FixLineWidth(efLeft, SelfSize, FmtCtx);
    Result := FmtCtx.FindMinLeft(LineTop, SelfSize.ContextIdx);
  end
  else if El.SrcEl.Css.Float_ = efRight then
  begin
    if LineLeft + El.Width > LineRight then
    begin
      NewTop := FmtCtx.FindNextLineTop(El.Top, El.Width, SelfSize.RenderWidth.Value);
      El.FPos.X := FmtCtx.GetLineRight(NewTop, SelfSize.RenderWidth.Value) -
        El.Width + El.ContentOffsetLeft;
      El.FPos.Y := NewTop + El.ContentOffsetTop;
      // Update Fb position
      Fb.Pos := TPixiePosition.Create(El.FPos.X - El.ContentOffsetLeft,
        El.FPos.Y - El.ContentOffsetTop, El.Width, El.Height);
    end
    else
    begin
      El.FPos.X := LineRight - El.Width + El.ContentOffsetLeft;
      Fb.Pos := TPixiePosition.Create(El.FPos.X - El.ContentOffsetLeft,
        El.FPos.Y - El.ContentOffsetTop, El.Width, El.Height);
    end;
    FmtCtx.AddFloat(Fb);
    FixLineWidth(efRight, SelfSize, FmtCtx);
    LineRight := FmtCtx.FindMinRight(LineTop, SelfSize.RenderWidth.Value, SelfSize.ContextIdx);
    Result := SelfSize.RenderWidth.Value - LineRight;
  end;

  // CSS 2.1 § 9.4.3: position:relative offsets are purely visual — the
  // float still occupies its un-shifted bbox in the formatting context
  // (already added above), only its rendered position moves.
  if El.SrcEl.Css.ElPosition = epRelative then
    El.ApplyRelativeShift(SelfSize);
end;

// --- _Render ---

function TPixieRenderBlock._Render(X, Y: TPixiePixel;
  const CbContext: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext;
  SecondPass: Boolean): TPixiePixel;
var
  SelfSize: TPixieContainingBlockContext;
  RetWidth: TPixiePixel;
  RequiresRerender: Boolean;
  FloatsHeight: TPixiePixel;
  ListImage, ListImageBaseUrl: string;
  ImgSz: TPixieSize;
  Doc: TPixieDocument;
begin
  SelfSize := CalculateContainingBlockContext(CbContext);

  // Render content
  RetWidth := _RenderContent(X, Y, SecondPass, SelfSize, FmtCtx);

  // List item minimum height
  if SrcEl.Css.Display = displayListItem then
  begin
    if FPos.Height = 0 then
      FPos.Height := Css.LineHeight.ComputedValue;
  end;

  RequiresRerender := False;

  // Set block width
  if (CbContext.SizeMode and SizeModeContent) = 0 then
  begin
    if SelfSize.Width.ValueType = cbcAbsolute then
    begin
      RetWidth := SelfSize.RenderWidth.Value;
      FPos.Width := RetWidth;
    end
    else
      FPos.Width := SelfSize.RenderWidth.Value;
  end
  else
  begin
    // Intrinsic sizing: a definite CSS width is the box's contribution,
    // not the content width. Without this, an empty element with
    // `width: 1em` (e.g. a div whose only purpose is to show a
    // background-image) collapses to 0 during the parent's track sizing.
    if SelfSize.Width.ValueType = cbcAbsolute then
    begin
      FPos.Width := SelfSize.Width.Value;
      RetWidth := SelfSize.Width.Value;
    end
    else
      FPos.Width := RetWidth;
  end;

  // fit-content shrink-to-fit: use content width clamped to available space
  if (CbContext.SizeMode and SizeModeContent) = 0 then
  begin
    if SrcEl.Css.CssWidth.IsPredefined and
       (SrcEl.Css.CssWidth.Predef = widFitContent) and
       (RetWidth < FPos.Width) then
    begin
      FPos.Width := RetWidth;
      RequiresRerender := True;
    end;
  end;

  // Fix width with max-width
  if SelfSize.MaxWidth.ValueType <> cbcNone then
  begin
    if FPos.Width > SelfSize.MaxWidth.Value then
    begin
      FPos.Width := SelfSize.MaxWidth.Value;
      RequiresRerender := True;
    end;
  end;

  // Fix width with min-width
  if SelfSize.MinWidth.ValueType <> cbcNone then
  begin
    if FPos.Width < SelfSize.MinWidth.Value then
    begin
      FPos.Width := SelfSize.MinWidth.Value;
      RequiresRerender := True;
    end;
  end
  else if FPos.Width < 0 then
    FPos.Width := 0;

  // Re-render content if required
  if RequiresRerender and (not SecondPass) and (not IsRoot) then
  begin
    if SrcEl.IsBlockFormattingContext then
      FmtCtx.ClearFloats(-1)
    else
      FmtCtx.ClearFloats(SelfSize.ContextIdx);
    _RenderContent(X, Y, True, SelfSize.NewWidth(FPos.Width), FmtCtx);
  end;

  // Set block height
  if (SelfSize.Height.ValueType <> cbcAuto) and
     ((CbContext.SizeMode and SizeModeContent) = 0) then
  begin
    if SrcEl.Css.Display = displayTableCell then
      // CSS 2.1 § 17.5.3: declared height on a table cell is a minimum;
      // content (already placed via _RenderContent) can grow it taller.
      FPos.Height := Max(FPos.Height,
        SelfSize.Height.Value - BoxSizingHeight)
    else
    begin
      if (SelfSize.Height.ValueType <> cbcPercentage) or
         (SelfSize.Height.Value > 0) then
        FPos.Height := SelfSize.Height.Value;
      FPos.Height := FPos.Height - BoxSizingHeight;
    end;
  end
  else if SrcEl.IsBlockFormattingContext then
  begin
    FloatsHeight := FmtCtx.GetFloatsHeight;
    if FloatsHeight > FPos.Height then
      FPos.Height := FloatsHeight;
  end;

  // Content-sizing height: a definite CSS height is the box's
  // contribution, regardless of content (mirrors the width logic above).
  if (CbContext.SizeMode and SizeModeContent) <> 0 then
  begin
    if SelfSize.Height.ValueType = cbcAbsolute then
      FPos.Height := SelfSize.Height.Value;
  end;

  if FPos.Height < 0 then
    FPos.Height := 0;

  // CSS Sizing 4 § 3: aspect-ratio derives the missing dimension when
  // width is definite and height is auto. Computed after the explicit
  // height has been applied so an explicit `height` still wins, but
  // before min/max clamping (which the derived size must still respect).
  if (SrcEl.Css.AspectRatio > 0) and
     SrcEl.Css.CssHeight.IsPredefined and (FPos.Width > 0) then
    FPos.Height := FPos.Width / SrcEl.Css.AspectRatio;

  // CSS 2.1 § 10.7: max-height clamps first, min-height enforces the
  // floor afterwards so min-height wins on conflict.
  if SelfSize.MaxHeight.ValueType <> cbcNone then
  begin
    if FPos.Height > SelfSize.MaxHeight.Value then
      FPos.Height := SelfSize.MaxHeight.Value;
  end;

  if SelfSize.MinHeight.ValueType <> cbcNone then
  begin
    if FPos.Height < SelfSize.MinHeight.Value then
      FPos.Height := SelfSize.MinHeight.Value;
  end;

  // Calculate final position
  FPos.MoveTo(X, Y);
  FPos.X := FPos.X + ContentOffsetLeft;
  FPos.Y := FPos.Y + ContentOffsetTop;

  // List-style-image height
  if SrcEl.Css.Display = displayListItem then
  begin
    ListImage := SrcEl.Css.ListStyleImage;
    if ListImage <> '' then
    begin
      Assert(SrcEl.GetDocument is TPixieDocument);
      Doc := TPixieDocument(SrcEl.GetDocument);
      if Doc.Container <> nil then
      begin
        ListImageBaseUrl := SrcEl.Css.ListStyleImageBaseUrl;
        Doc.Container.GetImageSize(ListImage, ListImageBaseUrl, ImgSz);
        if FPos.Height < ImgSz.Height then
          FPos.Height := ImgSz.Height;
      end;
    end;
  end;

  Result := RetWidth + ContentOffsetWidth;
end;

// --- Init ---

function TPixieRenderBlock.Init: TPixieRenderItem;
var
  I, J, Val: Integer;
  El, Child, NewChild: TPixieRenderItem;
  Split: TPixieSplitResult;
  HasBlockLevel, HasInlines, NotWsAdded: Boolean;
  Ret: TPixieRenderItem;
  NewChildren: TPixieRenderItemList;
  Inlines: TPixieRenderItemList;
  AnonEl: TPixieHtmlTag;
  AnonRi: TPixieRenderBlock;
  P: TPixieElement;
  Doc: TPixieDocument;
begin
  // Step 1 — List item index
  if (SrcEl.Css.Display = displayListItem) and
     (SrcEl.Css.ListStyleType >= lstArmenian) then
  begin
    P := SrcEl.Parent;
    if P <> nil then
    begin
      Val := StrToIntDef(P.GetAttr('start', '1'), 1);
      for I := 0 to P.Children.Count - 1 do
      begin
        if P.Children[I] = SrcEl then
        begin
          SrcEl.SetAttr('list_index', IntToStr(Val));
          Break;
        end
        else if P.Children[I].Css.Display = displayListItem then
          Inc(Val);
      end;
    end;
  end;

  // Step 2 — Split inlines containing blocks
  I := 0;
  while I < FChildren.Count do
  begin
    El := FChildren[I];
    if (El.SrcEl.Css.Display = displayInline) and (El.FChildren.Count > 0) then
    begin
      Split := El.SplitInlines;
      if Split.Before <> nil then
      begin
        Assert(TObject(Split.Before) is TPixieRenderItem);
        Assert(TObject(Split.Block) is TPixieRenderItem);
        Assert(TObject(Split.After) is TPixieRenderItem);

        // Remove the old child without freeing (we'll free it below)
        FChildren.OwnsObjects := False;
        FChildren.Delete(I);
        FChildren.OwnsObjects := True;

        // Insert Before, Block, After at position I
        FChildren.Insert(I, TPixieRenderItem(Split.After));
        FChildren.Insert(I, TPixieRenderItem(Split.Block));
        FChildren.Insert(I, TPixieRenderItem(Split.Before));

        TPixieRenderItem(Split.Before).SetParent(Self);
        TPixieRenderItem(Split.Block).SetParent(Self);
        TPixieRenderItem(Split.After).SetParent(Self);

        // Detach children from El before freeing (they've been moved
        // to Before/Block/After by SplitInlines)
        El.FChildren.OwnsObjects := False;
        El.FChildren.Clear;
        El.FChildren.OwnsObjects := True;
        El.Free;

        Continue; // re-examine at index I
      end;
    end;
    Inc(I);
  end;

  // Step 3 — Categorize children
  HasBlockLevel := False;
  HasInlines := False;
  for I := 0 to FChildren.Count - 1 do
  begin
    El := FChildren[I];
    if not El.SrcEl.IsFloat_ then
    begin
      if El.SrcEl.IsBlockBox then
        HasBlockLevel := True
      else if El.SrcEl.IsInline then
        HasInlines := True;
    end;
    if HasBlockLevel and HasInlines then
      Break;
  end;

  // Step 4 — Create context
  Assert(SrcEl.GetDocument is TPixieDocument);
  Doc := TPixieDocument(SrcEl.GetDocument);

  if HasBlockLevel then
  begin
    // Create a block context wrapper
    if PixieRenderBlockContextClass <> nil then
      Ret := PixieRenderBlockContextClass.Create(SrcEl)
    else
      Ret := TPixieRenderBlock.Create(SrcEl);
    Ret.SetParent(FParent);

    NewChildren := TPixieRenderItemList.Create(True);
    Inlines := TPixieRenderItemList.Create(False); // non-owning temp list
    try
      NotWsAdded := False;

      for I := 0 to FChildren.Count - 1 do
      begin
        El := FChildren[I];
        if El.SrcEl.IsInline then
        begin
          Inlines.Add(El);
          if not El.SrcEl.IsWhiteSpace then
            NotWsAdded := True;
        end
        else
        begin
          if NotWsAdded then
          begin
            // Wrap accumulated inlines in an anonymous block
            AnonEl := TPixieHtmlTag.CreateAnonymous(SrcEl);
            Doc.RegisterElement(AnonEl);
            AnonRi := TPixieRenderBlock.Create(AnonEl);
            for J := 0 to Inlines.Count - 1 do
              AnonRi.AddChild(Inlines[J]);
            AnonRi.SetParent(Ret);
            NewChildren.Add(AnonRi);
            NotWsAdded := False;
          end
          else
          begin
            // Free orphaned whitespace-only inlines
            for J := 0 to Inlines.Count - 1 do
              Inlines[J].Free;
          end;
          // Block child goes directly
          El.SetParent(Ret);
          NewChildren.Add(El);
          Inlines.Clear;
        end;
      end;

      // Handle trailing inlines
      if (Inlines.Count > 0) then
      begin
        if NotWsAdded then
        begin
          AnonEl := TPixieHtmlTag.CreateAnonymous(SrcEl);
          Doc.RegisterElement(AnonEl);
          AnonRi := TPixieRenderBlock.Create(AnonEl);
          for J := 0 to Inlines.Count - 1 do
            AnonRi.AddChild(Inlines[J]);
          AnonRi.SetParent(Ret);
          NewChildren.Add(AnonRi);
        end
        else
        begin
          // Free orphaned trailing whitespace-only inlines
          for J := 0 to Inlines.Count - 1 do
            Inlines[J].Free;
        end;
      end;

      // Transfer children: detach from FChildren without freeing
      FChildren.OwnsObjects := False;
      FChildren.Clear;
      FChildren.OwnsObjects := True;

      // Move new children to Ret
      Ret.FChildren.OwnsObjects := False;
      Ret.FChildren.Clear;
      Ret.FChildren.OwnsObjects := True;
      for I := 0 to NewChildren.Count - 1 do
        Ret.FChildren.Add(NewChildren[I]);

      // Prevent NewChildren from freeing the items we transferred
      NewChildren.OwnsObjects := False;
    finally
      Inlines.Free;
      NewChildren.Free;
    end;
  end
  else
  begin
    // Pure inlines or empty — create inline context
    if PixieRenderInlineContextClass <> nil then
      Ret := PixieRenderInlineContextClass.Create(SrcEl)
    else
      Ret := TPixieRenderBlock.Create(SrcEl);
    Ret.SetParent(FParent);

    // Transfer all children
    FChildren.OwnsObjects := False;
    for I := 0 to FChildren.Count - 1 do
    begin
      El := FChildren[I];
      El.SetParent(Ret);
      Ret.FChildren.Add(El);
    end;
    FChildren.Clear;
    FChildren.OwnsObjects := True;
  end;

  // Step 5 — Register and recurse
  Ret.SrcEl.AddRender(Ret);

  for I := 0 to Ret.FChildren.Count - 1 do
  begin
    Child := Ret.FChildren[I];
    NewChild := Child.Init;
    if NewChild <> Child then
    begin
      Ret.FChildren.OwnsObjects := False;
      Ret.FChildren[I] := NewChild;
      Ret.FChildren.OwnsObjects := True;
      Child.Free;
    end;
  end;

  Result := Ret;
end;

initialization
  PixieRenderBlockContextClass := nil;
  PixieRenderInlineContextClass := nil;
  PixieRenderGridClass := nil;

end.
