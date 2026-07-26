unit Pixie.FlexItem;

// Flex item + flex line: both live here to avoid circular dependency.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Generics.Collections,
  Pixie.Types;

type
  TPixieFlexLine = class;

  { TPixieFlexItem — base class for flex items }
  TPixieFlexItem = class
  public
    El: Pointer;

    // All sizes are outer/margin-box sizes
    BaseSize: TPixiePixel;
    MinSize: TPixiePixel;
    MaxSize: TPixieDefValue;
    MainSize: TPixiePixel;

    Grow: Integer;     // flex-grow * 1000
    Shrink: Integer;   // flex-shrink * 1000
    ScaledFlexShrinkFactor: TPixiePixel;

    Frozen: Boolean;
    ClampState: TPixieFlexClampState;

    Order: Integer;
    SrcOrder: Integer;

    AutoMarginMainStart: TPixieDefValue;
    AutoMarginMainEnd: TPixieDefValue;
    AutoMarginCrossStart: Boolean;
    AutoMarginCrossEnd: Boolean;

    Align: Integer; // enum ordinal + flags

    constructor Create(AEl: Pointer);
    destructor Destroy; override;

    function CompareTo(Other: TPixieFlexItem): Integer;

    procedure Init(const SelfSize: TPixieContainingBlockContext;
      FmtCtx: Pointer; AlignItems: Integer);
    procedure Place(var Ln: TPixieFlexLine; AMainPos: TPixiePixel;
      const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer);
    function GetFirstBaseline(AType: TPixieBaselineType): TPixiePixel;
    function GetLastBaseline(AType: TPixieBaselineType): TPixiePixel;

    procedure ApplyMainAutoMargins; virtual; abstract;
    function ApplyCrossAutoMargins(ACrossStart, ACrossSize: TPixiePixel): Boolean; virtual; abstract;
    procedure SetMainPosition(Pos: TPixiePixel); virtual; abstract;
    procedure SetCrossPosition(Pos: TPixiePixel); virtual; abstract;
    function GetElMainSize: TPixiePixel; virtual; abstract;
    function GetElCrossSize: TPixiePixel; virtual; abstract;
  protected
    procedure DirectionSpecificInit(const SelfSize: TPixieContainingBlockContext;
      FmtCtx: Pointer); virtual; abstract;
    procedure AlignStretch(var Ln: TPixieFlexLine;
      const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer); virtual; abstract;
    procedure AlignBaseline(var Ln: TPixieFlexLine;
      const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer); virtual; abstract;
    // Re-resolve an item's explicit cross-axis size against the now-known line
    // cross size. Default does nothing; only column-direction items need it
    // (their percentage/calc width resolves to zero in the intrinsic cross-size
    // measure, so a non-stretch item would otherwise keep its content width).
    procedure RenderCrossFromCss(var Ln: TPixieFlexLine;
      const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer); virtual;
  end;

  { TPixieFlexItemRow — row direction flex item }
  TPixieFlexItemRow = class(TPixieFlexItem)
  public
    procedure ApplyMainAutoMargins; override;
    function ApplyCrossAutoMargins(ACrossStart, ACrossSize: TPixiePixel): Boolean; override;
    procedure SetMainPosition(Pos: TPixiePixel); override;
    procedure SetCrossPosition(Pos: TPixiePixel); override;
    function GetElMainSize: TPixiePixel; override;
    function GetElCrossSize: TPixiePixel; override;
  protected
    procedure DirectionSpecificInit(const SelfSize: TPixieContainingBlockContext;
      FmtCtx: Pointer); override;
    procedure AlignStretch(var Ln: TPixieFlexLine;
      const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer); override;
    procedure AlignBaseline(var Ln: TPixieFlexLine;
      const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer); override;
  end;

  { TPixieFlexItemColumn — column direction flex item }
  TPixieFlexItemColumn = class(TPixieFlexItem)
  public
    procedure ApplyMainAutoMargins; override;
    function ApplyCrossAutoMargins(ACrossStart, ACrossSize: TPixiePixel): Boolean; override;
    procedure SetMainPosition(Pos: TPixiePixel); override;
    procedure SetCrossPosition(Pos: TPixiePixel); override;
    function GetElMainSize: TPixiePixel; override;
    function GetElCrossSize: TPixiePixel; override;
  protected
    procedure DirectionSpecificInit(const SelfSize: TPixieContainingBlockContext;
      FmtCtx: Pointer); override;
    procedure AlignStretch(var Ln: TPixieFlexLine;
      const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer); override;
    procedure AlignBaseline(var Ln: TPixieFlexLine;
      const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer); override;
    procedure RenderCrossFromCss(var Ln: TPixieFlexLine;
      const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer); override;
  end;

  TPixieFlexItemList = TObjectList<TPixieFlexItem>;

  { TPixieFlexLine — a single line of flex items }
  TPixieFlexLine = class
  public
    Items: TPixieFlexItemList;
    CrossStart: TPixiePixel;
    MainSize: TPixiePixel;
    CrossSize: TPixiePixel;
    BaseSize: TPixiePixel;
    NumAutoMarginMainStart: Integer;
    NumAutoMarginMainEnd: Integer;
    FirstBaseline: TPixieBaseline;
    LastBaseline: TPixieBaseline;
    ReverseMain: Boolean;
    ReverseCross: Boolean;
    MainGap: TPixiePixel;

    constructor Create(AReverseMain, AReverseCross: Boolean);
    destructor Destroy; override;

    procedure Init(ContainerMainSize: TPixiePixel; FitContainer: Boolean;
      IsRowDirection: Boolean;
      const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer);
    function DistributeMainAutoMargins(FreeMainSize: TPixiePixel): Boolean;
    function CalculateItemsPosition(ContainerMainSize: TPixiePixel;
      JustifyContent: TPixieFlexJustifyContent;
      IsRowDirection: Boolean;
      const SelfSize: TPixieContainingBlockContext;
      FmtCtx: Pointer): TPixiePixel;

    procedure DistributeFreeSpace(ContainerMainSize: TPixiePixel);
    procedure DistributeFreeSpaceGrow(ContainerMainSize: TPixiePixel);
    procedure DistributeFreeSpaceShrink(ContainerMainSize: TPixiePixel);
    function FixMinMaxViolations: Boolean;
    function TotalMainGap: TPixiePixel;
  end;

implementation

uses
  Math,
  Pixie.CssLength, Pixie.CssProperties,
  Pixie.Element, Pixie.FormattingContext,
  Pixie.RenderItem, Pixie.RenderBlock;

{ TPixieFlexLine }

constructor TPixieFlexLine.Create(AReverseMain, AReverseCross: Boolean);
begin
  inherited Create;
  Items := TPixieFlexItemList.Create(True);
  CrossStart := 0;
  MainSize := 0;
  CrossSize := 0;
  BaseSize := 0;
  NumAutoMarginMainStart := 0;
  NumAutoMarginMainEnd := 0;
  FirstBaseline.Init;
  LastBaseline.Init;
  ReverseMain := AReverseMain;
  ReverseCross := AReverseCross;
  MainGap := 0;
end;

destructor TPixieFlexLine.Destroy;
begin
  Items.Free;
  inherited;
end;

procedure TPixieFlexLine.Init(ContainerMainSize: TPixiePixel;
  FitContainer: Boolean; IsRowDirection: Boolean;
  const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer);
var
  I: Integer;
  Item: TPixieFlexItem;
  Ri: TPixieRenderItem;
  FirstBaselineTop, FirstBaselineBottom: TPixiePixel;
  LastBaselineTop, LastBaselineBottom: TPixiePixel;
  FirstBaselineTopSet, FirstBaselineBottomSet: Boolean;
  LastBaselineTopSet, LastBaselineBottomSet: Boolean;
  NonBaselineHeight: TPixiePixel;
  MaxCrossSize: TPixiePixel;
  MaxCrossSizeSet: Boolean;
  TopVal, BottomVal: TPixiePixel;
  ElRetWidth: TPixiePixel;
begin
  if not FitContainer then
    DistributeFreeSpace(ContainerMainSize - TotalMainGap);

  CrossSize := 0;
  MainSize := 0;
  FirstBaseline.SetValues(0, btNone);
  LastBaseline.SetValues(0, btNone);

  if IsRowDirection then
  begin
    FirstBaselineTop := 0;
    FirstBaselineBottom := 0;
    LastBaselineTop := 0;
    LastBaselineBottom := 0;
    FirstBaselineTopSet := False;
    FirstBaselineBottomSet := False;
    LastBaselineTopSet := False;
    LastBaselineBottomSet := False;
    NonBaselineHeight := 0;

    // Calculate maximum cross size
    MaxCrossSizeSet := False;
    MaxCrossSize := 0;
    if SelfSize.Height.ValueType <> cbcAuto then
    begin
      MaxCrossSize := SelfSize.Height.Value;
      MaxCrossSizeSet := True;
    end;
    if SelfSize.MaxHeight.ValueType <> cbcNone then
    begin
      if not MaxCrossSizeSet then
      begin
        MaxCrossSize := SelfSize.MaxHeight.Value;
        MaxCrossSizeSet := True;
      end
      else
        MaxCrossSize := Max(MaxCrossSize, SelfSize.MaxHeight.Value);
    end;

    // Render items, find cross_size and baselines
    for I := 0 to Items.Count - 1 do
    begin
      Item := Items[I];
      Assert(TObject(Item.El) is TPixieRenderItem);
      Ri := TPixieRenderItem(Item.El);
      Assert(TObject(FmtCtx) is TPixieFormattingContext);
      Ri.Render(0, 0,
        SelfSize.NewWidth(Item.MainSize - Ri.RenderOffsetWidth,
          SizeModeExactWidth),
        TPixieFormattingContext(FmtCtx));

      if (Item.Align and $FF) = Ord(faiBaseline) then
      begin
        if (Item.Align and FlexAlignItemsLast) <> 0 then
        begin
          LastBaseline.BaselineType := btBottom;
          if ReverseCross then
            LastBaseline.BaselineType := btTop;

          TopVal := -Ri.GetLastBaseline;
          BottomVal := TopVal + Ri.Height;

          if not LastBaselineTopSet then
          begin
            LastBaselineTop := TopVal;
            LastBaselineTopSet := True;
          end
          else
            LastBaselineTop := Min(LastBaselineTop, TopVal);

          if not LastBaselineBottomSet then
          begin
            LastBaselineBottom := BottomVal;
            LastBaselineBottomSet := True;
          end
          else
            LastBaselineBottom := Max(LastBaselineBottom, BottomVal);
        end
        else
        begin
          FirstBaseline.BaselineType := btTop;
          if ReverseCross then
            FirstBaseline.BaselineType := btBottom;

          TopVal := -Ri.GetFirstBaseline;
          BottomVal := TopVal + Ri.Height;

          if not FirstBaselineTopSet then
          begin
            FirstBaselineTop := TopVal;
            FirstBaselineTopSet := True;
          end
          else
            FirstBaselineTop := Min(FirstBaselineTop, TopVal);

          if not FirstBaselineBottomSet then
          begin
            FirstBaselineBottom := BottomVal;
            FirstBaselineBottomSet := True;
          end
          else
            FirstBaselineBottom := Max(FirstBaselineBottom, BottomVal);
        end;
      end
      else
        NonBaselineHeight := Max(NonBaselineHeight, Ri.Height);

      MainSize := MainSize + Ri.Width;
    end;

    CrossSize := Max(FirstBaselineBottom - FirstBaselineTop,
      LastBaselineBottom - LastBaselineTop);
    CrossSize := Max(CrossSize, NonBaselineHeight);
    if MaxCrossSizeSet and (CrossSize > MaxCrossSize) then
      CrossSize := MaxCrossSize;

    FirstBaseline.CalcFromPositions(FirstBaselineTop, FirstBaselineBottom);
    LastBaseline.CalcFromPositions(LastBaselineTop, LastBaselineBottom);
  end
  else
  begin
    // Column direction
    MaxCrossSizeSet := False;
    MaxCrossSize := 0;
    if SelfSize.Width.ValueType <> cbcAuto then
    begin
      MaxCrossSize := SelfSize.Width.Value;
      MaxCrossSizeSet := True;
    end;
    if SelfSize.MaxWidth.ValueType <> cbcNone then
    begin
      if not MaxCrossSizeSet then
      begin
        MaxCrossSize := SelfSize.MaxWidth.Value;
        MaxCrossSizeSet := True;
      end
      else
        MaxCrossSize := Max(MaxCrossSize, SelfSize.MaxWidth.Value);
    end;

    for I := 0 to Items.Count - 1 do
    begin
      Item := Items[I];
      Assert(TObject(Item.El) is TPixieRenderItem);
      Ri := TPixieRenderItem(Item.El);
      Assert(TObject(FmtCtx) is TPixieFormattingContext);
      ElRetWidth := Ri.Render(0, 0, SelfSize, TPixieFormattingContext(FmtCtx));
      Ri.Render(0, 0,
        SelfSize.NewWidthHeight(
          ElRetWidth - Ri.ContentOffsetWidth,
          Item.MainSize - Ri.ContentOffsetHeight,
          SizeModeExactWidth or SizeModeExactHeight),
        TPixieFormattingContext(FmtCtx));
      MainSize := MainSize + Ri.Height;
      CrossSize := Max(CrossSize, Ri.Width);
    end;
    if MaxCrossSizeSet and (CrossSize > MaxCrossSize) then
      CrossSize := MaxCrossSize;
  end;
end;

procedure TPixieFlexLine.DistributeFreeSpace(ContainerMainSize: TPixiePixel);
begin
  if MainSize < ContainerMainSize then
    DistributeFreeSpaceGrow(ContainerMainSize)
  else
    DistributeFreeSpaceShrink(ContainerMainSize);
end;

procedure TPixieFlexLine.DistributeFreeSpaceGrow(ContainerMainSize: TPixiePixel);
var
  InitialFreeSpace: TPixiePixel;
  AllInflexible: Boolean;
  SumFlexGrowFactor: Integer;
  RemainingFreeSpace: TPixiePixel;
  AdjustedFreeSpace: TPixiePixel;
  I: Integer;
  Item: TPixieFlexItem;
begin
  InitialFreeSpace := ContainerMainSize;
  AllInflexible := True;

  for I := 0 to Items.Count - 1 do
  begin
    Item := Items[I];
    if (Item.Grow = 0) or (Item.BaseSize > Item.MainSize) then
    begin
      Item.Frozen := True;
      Item.ClampState := fcsInflexible;
      InitialFreeSpace := InitialFreeSpace - Item.MainSize;
    end
    else
    begin
      InitialFreeSpace := InitialFreeSpace - Item.BaseSize;
      AllInflexible := False;
    end;
  end;

  if AllInflexible then
    Exit;

  while True do
  begin
    SumFlexGrowFactor := 0;
    RemainingFreeSpace := ContainerMainSize;

    for I := 0 to Items.Count - 1 do
    begin
      Item := Items[I];
      if Item.Frozen then
        RemainingFreeSpace := RemainingFreeSpace - Item.MainSize
      else
      begin
        RemainingFreeSpace := RemainingFreeSpace - Item.BaseSize;
        SumFlexGrowFactor := SumFlexGrowFactor + Item.Grow;
      end;
    end;

    if SumFlexGrowFactor < 1000 then
    begin
      AdjustedFreeSpace := InitialFreeSpace * SumFlexGrowFactor / 1000;
      if AdjustedFreeSpace < RemainingFreeSpace then
        RemainingFreeSpace := AdjustedFreeSpace;
    end;

    if RemainingFreeSpace <> 0 then
    begin
      for I := 0 to Items.Count - 1 do
      begin
        Item := Items[I];
        if not Item.Frozen then
          Item.MainSize := Item.BaseSize +
            RemainingFreeSpace * Item.Grow / SumFlexGrowFactor;
      end;
    end;

    if FixMinMaxViolations then
      Break;
  end;
end;

procedure TPixieFlexLine.DistributeFreeSpaceShrink(ContainerMainSize: TPixiePixel);
var
  InitialFreeSpace: TPixiePixel;
  AllInflexible: Boolean;
  SumFlexShrinkFactor: Integer;
  SumScaledFlexShrinkFactor: TPixiePixel;
  RemainingFreeSpace: TPixiePixel;
  AdjustedFreeSpace: TPixiePixel;
  I: Integer;
  Item: TPixieFlexItem;
begin
  InitialFreeSpace := ContainerMainSize;
  AllInflexible := True;

  for I := 0 to Items.Count - 1 do
  begin
    Item := Items[I];
    if (Item.Shrink = 0) or (Item.BaseSize < Item.MainSize) then
    begin
      Item.Frozen := True;
      Item.ClampState := fcsInflexible;
      InitialFreeSpace := InitialFreeSpace - Item.MainSize;
    end
    else
    begin
      InitialFreeSpace := InitialFreeSpace - Item.BaseSize;
      AllInflexible := False;
    end;
  end;

  if AllInflexible then
    Exit;

  while True do
  begin
    SumFlexShrinkFactor := 0;
    SumScaledFlexShrinkFactor := 0;
    RemainingFreeSpace := ContainerMainSize;

    for I := 0 to Items.Count - 1 do
    begin
      Item := Items[I];
      if Item.Frozen then
        RemainingFreeSpace := RemainingFreeSpace - Item.MainSize
      else
      begin
        RemainingFreeSpace := RemainingFreeSpace - Item.BaseSize;
        SumFlexShrinkFactor := SumFlexShrinkFactor + Item.Shrink;
        SumScaledFlexShrinkFactor := SumScaledFlexShrinkFactor +
          Item.ScaledFlexShrinkFactor;
      end;
    end;

    if SumFlexShrinkFactor < 1000 then
    begin
      AdjustedFreeSpace := InitialFreeSpace * SumFlexShrinkFactor / 1000;
      if AdjustedFreeSpace > RemainingFreeSpace then
        RemainingFreeSpace := AdjustedFreeSpace;
    end;

    if (RemainingFreeSpace <> 0) and (SumScaledFlexShrinkFactor <> 0) then
    begin
      for I := 0 to Items.Count - 1 do
      begin
        Item := Items[I];
        if not Item.Frozen then
          Item.MainSize := Item.BaseSize +
            RemainingFreeSpace * Item.ScaledFlexShrinkFactor /
            SumScaledFlexShrinkFactor;
      end;
    end;

    if FixMinMaxViolations then
      Break;
  end;
end;

function TPixieFlexLine.TotalMainGap: TPixiePixel;
begin
  if (MainGap > 0) and (Items.Count > 1) then
    Result := MainGap * (Items.Count - 1)
  else
    Result := 0;
end;

function TPixieFlexLine.FixMinMaxViolations: Boolean;
var
  TotalViolation: TPixiePixel;
  AllFrozen: Boolean;
  StateToFreeze: TPixieFlexClampState;
  I: Integer;
  Item: TPixieFlexItem;
begin
  TotalViolation := 0;

  for I := 0 to Items.Count - 1 do
  begin
    Item := Items[I];
    if not Item.Frozen then
    begin
      if Item.MainSize < Item.MinSize then
      begin
        TotalViolation := TotalViolation + (Item.MinSize - Item.MainSize);
        Item.MainSize := Item.MinSize;
        Item.ClampState := fcsMinViolation;
      end
      else if (not Item.MaxSize.IsDefault) and (Item.MainSize > Item.MaxSize.Value) then
      begin
        TotalViolation := TotalViolation + (Item.MaxSize.Value - Item.MainSize);
        Item.MainSize := Item.MaxSize.Value;
        Item.ClampState := fcsMaxViolation;
      end;
    end;
  end;

  if TotalViolation = 0 then
  begin
    for I := 0 to Items.Count - 1 do
      Items[I].Frozen := True;
    Result := True;
    Exit;
  end;

  AllFrozen := True;

  if TotalViolation > 0 then
    StateToFreeze := fcsMinViolation
  else
    StateToFreeze := fcsMaxViolation;

  for I := 0 to Items.Count - 1 do
  begin
    Item := Items[I];
    if not Item.Frozen then
    begin
      if Item.ClampState = StateToFreeze then
        Item.Frozen := True
      else
      begin
        AllFrozen := False;
        Item.ClampState := fcsUnclamped;
      end;
    end;
  end;

  Result := AllFrozen;
end;

function TPixieFlexLine.DistributeMainAutoMargins(FreeMainSize: TPixiePixel): Boolean;
var
  Add: TPixiePixel;
  DistributeStep: TPixiePixel;
  I: Integer;
  Item: TPixieFlexItem;
begin
  Result := False;
  if (FreeMainSize <= 0) or
     ((NumAutoMarginMainStart = 0) and (NumAutoMarginMainEnd = 0)) then
    Exit;

  Add := FreeMainSize / (Items.Count * 2);
  for I := 0 to Items.Count - 1 do
  begin
    Item := Items[I];
    if not Item.AutoMarginMainStart.IsDefault then
    begin
      Item.AutoMarginMainStart.SetValue(Add);
      Item.MainSize := Item.MainSize + Add;
      MainSize := MainSize + Add;
      FreeMainSize := FreeMainSize - Add;
    end;
    if not Item.AutoMarginMainEnd.IsDefault then
    begin
      Item.AutoMarginMainEnd.SetValue(Add);
      Item.MainSize := Item.MainSize + Add;
      MainSize := MainSize + Add;
      FreeMainSize := FreeMainSize - Add;
    end;
  end;

  DistributeStep := 1;
  while FreeMainSize > 0 do
  begin
    for I := 0 to Items.Count - 1 do
    begin
      Item := Items[I];
      if not Item.AutoMarginMainStart.IsDefault then
      begin
        Item.AutoMarginMainStart.SetValue(Item.AutoMarginMainStart.Value + DistributeStep);
        FreeMainSize := FreeMainSize - DistributeStep;
        if FreeMainSize < DistributeStep then
          Break;
      end;
      if not Item.AutoMarginMainEnd.IsDefault then
      begin
        Item.AutoMarginMainEnd.SetValue(Item.AutoMarginMainEnd.Value + DistributeStep);
        FreeMainSize := FreeMainSize - DistributeStep;
        if FreeMainSize < DistributeStep then
          Break;
      end;
    end;
  end;

  Result := True;
end;

function TPixieFlexLine.CalculateItemsPosition(ContainerMainSize: TPixiePixel;
  JustifyContent: TPixieFlexJustifyContent;
  IsRowDirection: Boolean;
  const SelfSize: TPixieContainingBlockContext;
  FmtCtx: Pointer): TPixiePixel;
var
  FreeMainSize: TPixiePixel;
  MainPos: TPixiePixel;
  AddBeforeItem: TPixiePixel;
  AddAfterItem: TPixiePixel;
  ItemRemainder: TPixiePixel;
  DistributeStep: TPixiePixel;
  Height: TPixiePixel;
  Gap: TPixiePixel;
  I: Integer;
  Item: TPixieFlexItem;
begin
  Gap := TotalMainGap;
  FreeMainSize := ContainerMainSize - MainSize - Gap;
  DistributeMainAutoMargins(FreeMainSize);
  FreeMainSize := ContainerMainSize - MainSize - Gap;

  case JustifyContent of
    fjcLeft, fjcRight:
      if not IsRowDirection then
        JustifyContent := fjcStart;
    fjcSpaceBetween:
      if (Items.Count = 1) or (FreeMainSize < 0) then
        JustifyContent := fjcFlexStart;
    fjcSpaceAround, fjcSpaceEvenly:
      if (Items.Count = 1) or (FreeMainSize < 0) then
        JustifyContent := fjcCenter;
  end;

  MainPos := 0;
  AddBeforeItem := 0;
  AddAfterItem := 0;
  ItemRemainder := 0;

  case JustifyContent of
    fjcRight:
      MainPos := FreeMainSize;
    fjcLeft, fjcStart:
      MainPos := 0;
    fjcEnd:
      MainPos := FreeMainSize;
    fjcFlexEnd:
    begin
      if not ReverseMain then
        MainPos := FreeMainSize;
    end;
    fjcCenter:
      MainPos := FreeMainSize / 2;
    fjcSpaceBetween:
    begin
      AddAfterItem := FreeMainSize / (Items.Count - 1);
      ItemRemainder := FreeMainSize - (AddAfterItem * (Items.Count - 1));
    end;
    fjcSpaceAround:
    begin
      AddAfterItem := FreeMainSize / (Items.Count * 2);
      AddBeforeItem := AddAfterItem;
      ItemRemainder := FreeMainSize - (AddAfterItem * Items.Count * 2);
    end;
    fjcSpaceEvenly:
    begin
      AddBeforeItem := FreeMainSize / (Items.Count + 1);
      ItemRemainder := FreeMainSize - AddBeforeItem * (Items.Count + 1);
    end;
  else
    if ReverseMain then
      MainPos := FreeMainSize;
  end;

  Height := 0;
  DistributeStep := 1;

  for I := 0 to Items.Count - 1 do
  begin
    Item := Items[I];
    MainPos := MainPos + AddBeforeItem;
    if (I > 0) and (MainGap > 0) then
      MainPos := MainPos + MainGap;
    if (AddBeforeItem > 0) and (ItemRemainder > 0) then
    begin
      MainPos := MainPos + DistributeStep;
      ItemRemainder := ItemRemainder - DistributeStep;
    end;
    Item.Place(Self, MainPos, SelfSize, FmtCtx);
    MainPos := MainPos + Item.GetElMainSize + AddAfterItem;
    Assert(TObject(Item.El) is TPixieRenderItem);
    Height := Max(Height, TPixieRenderItem(Item.El).Bottom);
    if (AddAfterItem > 0) and (ItemRemainder > 0) then
    begin
      MainPos := MainPos + DistributeStep;
      ItemRemainder := ItemRemainder - DistributeStep;
    end;
  end;

  Result := Height;
end;

{ TPixieFlexItem }

constructor TPixieFlexItem.Create(AEl: Pointer);
begin
  inherited Create;
  El := AEl;
  BaseSize := 0;
  MinSize := 0;
  MaxSize.Init(0);
  MainSize := 0;
  Grow := 0;
  Shrink := 0;
  ScaledFlexShrinkFactor := 0;
  Frozen := False;
  ClampState := fcsUnclamped;
  Order := 0;
  SrcOrder := 0;
  AutoMarginMainStart.Init(0);
  AutoMarginMainEnd.Init(0);
  AutoMarginCrossStart := False;
  AutoMarginCrossEnd := False;
  Align := Ord(faiAuto);
end;

destructor TPixieFlexItem.Destroy;
begin
  inherited;
end;

function TPixieFlexItem.CompareTo(Other: TPixieFlexItem): Integer;
begin
  if Order < Other.Order then
    Result := -1
  else if Order > Other.Order then
    Result := 1
  else if SrcOrder < Other.SrcOrder then
    Result := -1
  else if SrcOrder > Other.SrcOrder then
    Result := 1
  else
    Result := 0;
end;

procedure TPixieFlexItem.Init(const SelfSize: TPixieContainingBlockContext;
  FmtCtx: Pointer; AlignItems: Integer);
var
  Ri: TPixieRenderItem;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Ri := TPixieRenderItem(El);

  Grow := Round(Ri.Css.FlexGrow * 1000);
  if Grow < 0 then
    Grow := 0;

  Shrink := Round(Ri.Css.FlexShrink * 1000);
  if Shrink < 0 then
    Shrink := 1000;

  Ri.CalcOutlines(SelfSize.RenderWidth.Value);
  Order := Ri.Css.Order;

  DirectionSpecificInit(SelfSize, FmtCtx);

  if Ri.Css.FlexAlignSelf = faiAuto then
    Align := AlignItems
  else
    Align := Ord(Ri.Css.FlexAlignSelf);

  // Clamp base_size to min/max -> main_size
  if BaseSize < MinSize then
    MainSize := MinSize
  else if (not MaxSize.IsDefault) and (BaseSize > MaxSize.Value) then
    MainSize := MaxSize.Value
  else
    MainSize := BaseSize;

  Frozen := False;
end;

procedure TPixieFlexItem.Place(var Ln: TPixieFlexLine; AMainPos: TPixiePixel;
  const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer);
begin
  ApplyMainAutoMargins;
  SetMainPosition(AMainPos);
  if not ApplyCrossAutoMargins(Ln.CrossStart, Ln.CrossSize) then
  begin
    // A non-stretch item with an explicit percentage/calc cross size was
    // measured at content width; re-resolve it against the line cross size
    // before positioning. Stretch (the case else) re-renders in AlignStretch.
    case Align and $FF of
      Ord(faiBaseline), Ord(faiFlexEnd), Ord(faiEnd), Ord(faiCenter),
      Ord(faiFlexStart), Ord(faiStart):
        RenderCrossFromCss(Ln, SelfSize, FmtCtx);
    end;
    case Align and $FF of
      Ord(faiBaseline):
        AlignBaseline(Ln, SelfSize, FmtCtx);
      Ord(faiFlexEnd):
      begin
        if Ln.ReverseCross then
          SetCrossPosition(Ln.CrossStart)
        else
          SetCrossPosition(Ln.CrossStart + Ln.CrossSize - GetElCrossSize);
      end;
      Ord(faiEnd):
        SetCrossPosition(Ln.CrossStart + Ln.CrossSize - GetElCrossSize);
      Ord(faiCenter):
        SetCrossPosition(Ln.CrossStart + Ln.CrossSize / 2 - GetElCrossSize / 2);
      Ord(faiFlexStart):
      begin
        if Ln.ReverseCross then
          SetCrossPosition(Ln.CrossStart + Ln.CrossSize - GetElCrossSize)
        else
          SetCrossPosition(Ln.CrossStart);
      end;
      Ord(faiStart):
        SetCrossPosition(Ln.CrossStart);
    else
      AlignStretch(Ln, SelfSize, FmtCtx);
    end;
  end;
end;

procedure TPixieFlexItem.RenderCrossFromCss(var Ln: TPixieFlexLine;
  const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer);
begin
  // Default: nothing. Row-direction items resolve an explicit cross-axis
  // (height) size during the measure pass already; only column items override.
end;

function TPixieFlexItem.GetFirstBaseline(AType: TPixieBaselineType): TPixiePixel;
var
  Ri: TPixieRenderItem;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Ri := TPixieRenderItem(El);
  if AType = btTop then
    Result := Ri.GetFirstBaseline
  else if AType = btBottom then
    Result := Ri.Height - Ri.GetFirstBaseline
  else
    Result := 0;
end;

function TPixieFlexItem.GetLastBaseline(AType: TPixieBaselineType): TPixiePixel;
var
  Ri: TPixieRenderItem;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Ri := TPixieRenderItem(El);
  if AType = btTop then
    Result := Ri.GetLastBaseline
  else if AType = btBottom then
    Result := Ri.Height - Ri.GetLastBaseline
  else
    Result := 0;
end;

{ TPixieFlexItemRow }

procedure TPixieFlexItemRow.DirectionSpecificInit(
  const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer);
var
  Ri: TPixieRenderItem;
  ContentSize: TPixiePixel;
  ContentSizeSet: Boolean;
  FlexBasisPredefined: Boolean;
  Predef: Integer;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Ri := TPixieRenderItem(El);
  Assert(TObject(FmtCtx) is TPixieFormattingContext);

  // Check auto margins
  if Ri.Css.CssMargins.Left.IsPredefined then
    AutoMarginMainStart.SetValue(0);
  if Ri.Css.CssMargins.Right.IsPredefined then
    AutoMarginMainEnd.SetValue(0);
  if Ri.Css.CssMargins.Top.IsPredefined then
    AutoMarginCrossStart := True;
  if Ri.Css.CssMargins.Bottom.IsPredefined then
    AutoMarginCrossEnd := True;

  // Min size — always stored as the outer (margin-box) main-axis size
  // so it's directly comparable with BaseSize / MaxSize.
  ContentSizeSet := False;
  ContentSize := 0;
  if Ri.Css.CssMinWidth.IsPredefined then
  begin
    ContentSize := Ri.Render(0, 0,
      SelfSize.NewWidth(Ri.ContentOffsetWidth, SizeModeContent),
      TPixieFormattingContext(FmtCtx));
    ContentSizeSet := True;
    // The automatic minimum size of a flex item is its min-content size
    // (CSS Flexbox §4.5), stored here as the outer margin-box main size.
    // GetIntrinsicMinWidth is the content-box min-content: for most items the
    // rendered width, but a wrapping nested flex container reports its widest
    // item (the render itself returns the SUM of items — max-content — even
    // after wrapping). Add the full box offset (Width - FPos.Width =
    // margins+padding+borders, box-sizing independent) to reach the margin box.
    MinSize := Ri.GetIntrinsicMinWidth + (Ri.Width - Ri.FPos.Width);
  end
  else
    MinSize := Ri.Css.CssMinWidth.CalcPercent(SelfSize.RenderWidth.Value) +
      Ri.RenderOffsetWidth;

  // Max size
  if not Ri.Css.CssMaxWidth.IsPredefined then
    MaxSize.SetValue(Ri.Css.CssMaxWidth.CalcPercent(SelfSize.RenderWidth.Value) +
      Ri.RenderOffsetWidth);

  // CSS Flex § 4.5: when min-width is auto and max-width is definite,
  // the automatic minimum is clamped to max-width. Otherwise an item whose
  // intrinsic min-content exceeds max-width (e.g. a flex-wrap container
  // whose children only wrap once it's narrower than their un-wrapped
  // natural total) overshoots its declared max-width.
  if Ri.Css.CssMinWidth.IsPredefined and
     (Ri.Css.CssMinWidth.Predef = widAuto) then
    MaxSize.ClampMax(MinSize);

  // Flex basis
  FlexBasisPredefined := Ri.Css.FlexBasis.IsPredefined;
  Predef := Ord(fbAuto);
  if FlexBasisPredefined then
    Predef := Ri.Css.FlexBasis.Predef
  else if Ri.Css.FlexBasis.Val < 0 then
    FlexBasisPredefined := True;

  if FlexBasisPredefined then
  begin
    if (Predef = Ord(fbAuto)) and Ri.Css.CssWidth.IsPredefined then
      Predef := Ord(fbMaxContent);

    case Predef of
      Ord(fbAuto):
        BaseSize := Ri.Css.CssWidth.CalcPercent(SelfSize.RenderWidth.Value) +
          Ri.RenderOffsetWidth;
      Ord(fbFitContent), Ord(fbContent):
        BaseSize := Ri.Render(0, 0,
          SelfSize.NewWidth(Ri.ContentOffsetWidth,
            SizeModeContent),
          TPixieFormattingContext(FmtCtx)) + Ri.RenderOffsetWidth;
      Ord(fbMinContent):
      begin
        if not ContentSizeSet then
          ContentSize := Ri.Render(0, 0,
            SelfSize.NewWidth(Ri.ContentOffsetWidth, SizeModeContent),
            TPixieFormattingContext(FmtCtx));
        BaseSize := ContentSize + Ri.RenderOffsetWidth;
      end;
      Ord(fbMaxContent):
      begin
        Ri.Render(0, 0,
          SelfSize.NewWidth(SelfSize.RenderWidth.Value, SizeModeContent),
          TPixieFormattingContext(FmtCtx));
        BaseSize := Ri.Width;
      end;
    else
      BaseSize := 0;
    end;
  end
  else
    BaseSize := Ri.Css.FlexBasis.CalcPercent(SelfSize.RenderWidth.Value) +
      Ri.RenderOffsetWidth;

  ScaledFlexShrinkFactor := (BaseSize - Ri.RenderOffsetWidth) * Shrink;
end;

procedure TPixieFlexItemRow.ApplyMainAutoMargins;
var
  Ri: TPixieRenderItem;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Ri := TPixieRenderItem(El);
  if not AutoMarginMainStart.IsDefault then
  begin
    Ri.FMargins.Left := AutoMarginMainStart.Value;
    Ri.FPos.X := Ri.FPos.X + AutoMarginMainStart.Value;
  end;
  if not AutoMarginMainEnd.IsDefault then
    Ri.FMargins.Right := AutoMarginMainEnd.Value;
end;

function TPixieFlexItemRow.ApplyCrossAutoMargins(ACrossStart, ACrossSize: TPixiePixel): Boolean;
var
  Ri: TPixieRenderItem;
  MarginsNum: Integer;
  Margin: TPixiePixel;
begin
  Result := False;
  if not (AutoMarginCrossEnd or AutoMarginCrossStart) then
    Exit;
  Assert(TObject(El) is TPixieRenderItem);
  Ri := TPixieRenderItem(El);
  MarginsNum := 0;
  if AutoMarginCrossEnd then
    Inc(MarginsNum);
  if AutoMarginCrossStart then
    Inc(MarginsNum);
  Margin := (ACrossSize - Ri.Height) / MarginsNum;
  if AutoMarginCrossStart then
    Ri.FMargins.Top := Margin;
  if AutoMarginCrossEnd then
    Ri.FMargins.Bottom := Margin;
  Ri.FPos.Y := ACrossStart + Ri.ContentOffsetTop;
  Result := True;
end;

procedure TPixieFlexItemRow.SetMainPosition(Pos: TPixiePixel);
var
  Ri: TPixieRenderItem;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Ri := TPixieRenderItem(El);
  Ri.FPos.X := Pos + Ri.ContentOffsetLeft;
end;

procedure TPixieFlexItemRow.SetCrossPosition(Pos: TPixiePixel);
var
  Ri: TPixieRenderItem;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Ri := TPixieRenderItem(El);
  Ri.FPos.Y := Pos + Ri.ContentOffsetTop;
end;

function TPixieFlexItemRow.GetElMainSize: TPixiePixel;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Result := TPixieRenderItem(El).Width;
end;

function TPixieFlexItemRow.GetElCrossSize: TPixiePixel;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Result := TPixieRenderItem(El).Height;
end;

procedure TPixieFlexItemRow.AlignStretch(var Ln: TPixieFlexLine;
  const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer);
var
  Ri: TPixieRenderItem;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Ri := TPixieRenderItem(El);
  Assert(TObject(FmtCtx) is TPixieFormattingContext);
  SetCrossPosition(Ln.CrossStart);
  if Ri.Css.CssHeight.IsPredefined then
  begin
    Ri.Render(Ri.Left, Ri.Top,
      SelfSize.NewWidthHeight(
        Ri.FPos.Width + Ri.BoxSizingWidth,
        Ln.CrossSize - Ri.ContentOffsetHeight + Ri.BoxSizingHeight,
        SizeModeExactWidth or SizeModeExactHeight),
      TPixieFormattingContext(FmtCtx));
    ApplyMainAutoMargins;
  end;
end;

procedure TPixieFlexItemRow.AlignBaseline(var Ln: TPixieFlexLine;
  const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer);
var
  Ri: TPixieRenderItem;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Ri := TPixieRenderItem(El);
  if (Align and FlexAlignItemsLast) <> 0 then
    SetCrossPosition(Ln.CrossStart +
      Ln.LastBaseline.GetOffsetFromTop(Ln.CrossSize) - Ri.GetLastBaseline)
  else
    SetCrossPosition(Ln.CrossStart +
      Ln.FirstBaseline.GetOffsetFromTop(Ln.CrossSize) - Ri.GetFirstBaseline);
end;

{ TPixieFlexItemColumn }

procedure TPixieFlexItemColumn.DirectionSpecificInit(
  const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer);
var
  Ri: TPixieRenderItem;
  FlexBasisPredefined: Boolean;
  Predef: Integer;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Ri := TPixieRenderItem(El);
  Assert(TObject(FmtCtx) is TPixieFormattingContext);

  // Check auto margins (swapped vs row: main=Y, cross=X)
  if Ri.Css.CssMargins.Top.IsPredefined then
    AutoMarginMainStart.SetValue(0);
  if Ri.Css.CssMargins.Bottom.IsPredefined then
    AutoMarginMainEnd.SetValue(0);
  if Ri.Css.CssMargins.Left.IsPredefined then
    AutoMarginCrossStart := True;
  if Ri.Css.CssMargins.Right.IsPredefined then
    AutoMarginCrossEnd := True;

  // Min size — always stored as the outer (margin-box) main-axis size
  // so it's directly comparable with BaseSize / MaxSize.
  if Ri.Css.CssMinHeight.IsPredefined then
  begin
    Ri.Render(0, 0, SelfSize.NewWidth(SelfSize.RenderWidth.Value, SizeModeContent),
      TPixieFormattingContext(FmtCtx));
    // Ri.Height is already the outer (margin-box) main size; adding
    // RenderOffsetHeight again would double-count the vertical margins/
    // padding/border (cf. the row variant using content size + offset once).
    MinSize := Ri.Height;
  end
  else
    MinSize := Ri.Css.CssMinHeight.CalcPercent(SelfSize.Height.Value) +
      Ri.RenderOffsetHeight;

  // Max size
  if not Ri.Css.CssMaxHeight.IsPredefined then
    MaxSize.SetValue(Ri.Css.CssMaxHeight.CalcPercent(SelfSize.Height.Value) +
      Ri.RenderOffsetHeight);

  // Same auto-min clamp as the row variant (CSS Flex § 4.5).
  if Ri.Css.CssMinHeight.IsPredefined and
     (Ri.Css.CssMinHeight.Predef = widAuto) then
    MaxSize.ClampMax(MinSize);

  // Flex basis
  FlexBasisPredefined := Ri.Css.FlexBasis.IsPredefined;
  Predef := Ord(fbAuto);
  if FlexBasisPredefined then
    Predef := Ri.Css.FlexBasis.Predef
  else if Ri.Css.FlexBasis.Val < 0 then
    FlexBasisPredefined := True;

  if FlexBasisPredefined then
  begin
    if (Predef = Ord(fbAuto)) and Ri.Css.CssHeight.IsPredefined then
      Predef := Ord(fbFitContent);

    case Predef of
      Ord(fbAuto):
        BaseSize := Ri.Css.CssHeight.CalcPercent(SelfSize.Height.Value) +
          Ri.RenderOffsetHeight;
      Ord(fbMaxContent), Ord(fbFitContent):
      begin
        Ri.Render(0, 0, SelfSize, TPixieFormattingContext(FmtCtx));
        // Ri.Height is already the outer (margin-box) main size — the row
        // variant uses Ri.Width directly. Adding RenderOffsetHeight again
        // double-counts the item's vertical margins/padding/border.
        BaseSize := Ri.Height;
      end;
      Ord(fbMinContent):
        BaseSize := MinSize;
    else
      BaseSize := 0;
    end;
  end
  else
  begin
    if Ri.Css.FlexBasis.Units = cssUnitsPercentage then
    begin
      if SelfSize.Height.ValueType = cbcAbsolute then
        BaseSize := Ri.Css.FlexBasis.CalcPercent(SelfSize.Height.Value) +
          Ri.RenderOffsetHeight
      else
        BaseSize := 0;
    end
    else
      BaseSize := Round(Ri.Css.FlexBasis.Val) + Ri.RenderOffsetHeight;
  end;

  ScaledFlexShrinkFactor := (BaseSize - Ri.RenderOffsetHeight) * Shrink;
end;

procedure TPixieFlexItemColumn.ApplyMainAutoMargins;
var
  Ri: TPixieRenderItem;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Ri := TPixieRenderItem(El);
  if not AutoMarginMainStart.IsDefault then
  begin
    Ri.FMargins.Top := AutoMarginMainStart.Value;
    Ri.FPos.Y := Ri.FPos.Y + AutoMarginMainStart.Value;
  end;
  if not AutoMarginMainEnd.IsDefault then
    Ri.FMargins.Bottom := AutoMarginMainEnd.Value;
end;

function TPixieFlexItemColumn.ApplyCrossAutoMargins(ACrossStart, ACrossSize: TPixiePixel): Boolean;
var
  Ri: TPixieRenderItem;
  MarginsNum: Integer;
  Margin: TPixiePixel;
begin
  Result := False;
  if not (AutoMarginCrossEnd or AutoMarginCrossStart) then
    Exit;
  Assert(TObject(El) is TPixieRenderItem);
  Ri := TPixieRenderItem(El);
  MarginsNum := 0;
  if AutoMarginCrossEnd then
    Inc(MarginsNum);
  if AutoMarginCrossStart then
    Inc(MarginsNum);
  Margin := (ACrossSize - Ri.Width) / MarginsNum;
  if AutoMarginCrossStart then
    Ri.FMargins.Left := Margin;
  if AutoMarginCrossEnd then
    Ri.FMargins.Right := Margin;
  Ri.FPos.X := ACrossStart + Ri.ContentOffsetLeft;
  Result := True;
end;

procedure TPixieFlexItemColumn.SetMainPosition(Pos: TPixiePixel);
var
  Ri: TPixieRenderItem;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Ri := TPixieRenderItem(El);
  Ri.FPos.Y := Pos + Ri.ContentOffsetTop;
end;

procedure TPixieFlexItemColumn.SetCrossPosition(Pos: TPixiePixel);
var
  Ri: TPixieRenderItem;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Ri := TPixieRenderItem(El);
  Ri.FPos.X := Pos + Ri.ContentOffsetLeft;
end;

function TPixieFlexItemColumn.GetElMainSize: TPixiePixel;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Result := TPixieRenderItem(El).Height;
end;

function TPixieFlexItemColumn.GetElCrossSize: TPixiePixel;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Result := TPixieRenderItem(El).Width;
end;

procedure TPixieFlexItemColumn.AlignStretch(var Ln: TPixieFlexLine;
  const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer);
var
  Ri: TPixieRenderItem;
  Mode: UInt32;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Ri := TPixieRenderItem(El);
  Assert(TObject(FmtCtx) is TPixieFormattingContext);
  if not Ri.Css.CssWidth.IsPredefined then
    Mode := SizeModeExactHeight
  else
    Mode := SizeModeExactWidth or SizeModeExactHeight;
  Ri.Render(Ln.CrossStart,
    Ri.FPos.Y - Ri.ContentOffsetTop,
    SelfSize.NewWidthHeight(
      Ln.CrossSize - Ri.ContentOffsetWidth + Ri.BoxSizingWidth,
      MainSize - Ri.ContentOffsetHeight + Ri.BoxSizingHeight,
      Mode),
    TPixieFormattingContext(FmtCtx));
  ApplyMainAutoMargins;
end;

procedure TPixieFlexItemColumn.RenderCrossFromCss(var Ln: TPixieFlexLine;
  const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer);
var
  Ri: TPixieRenderItem;
begin
  Assert(TObject(El) is TPixieRenderItem);
  Ri := TPixieRenderItem(El);
  // Only an explicit (non-auto) width needs re-resolving; an auto-width item
  // keeps the content width it was measured at. Render width from CSS (so a
  // percentage/calc resolves against the line cross size) with the main-axis
  // height pinned — mirroring AlignStretch's explicit-width branch, but this
  // path never forces an auto-width item to fill the line.
  if Ri.Css.CssWidth.IsPredefined then Exit;
  Assert(TObject(FmtCtx) is TPixieFormattingContext);
  Ri.Render(Ri.FPos.X - Ri.ContentOffsetLeft,
    Ri.FPos.Y - Ri.ContentOffsetTop,
    SelfSize.NewWidthHeight(
      Ln.CrossSize - Ri.ContentOffsetWidth + Ri.BoxSizingWidth,
      MainSize - Ri.ContentOffsetHeight + Ri.BoxSizingHeight,
      SizeModeExactHeight),
    TPixieFormattingContext(FmtCtx));
end;

procedure TPixieFlexItemColumn.AlignBaseline(var Ln: TPixieFlexLine;
  const SelfSize: TPixieContainingBlockContext; FmtCtx: Pointer);
begin
  // Column direction: baseline falls back to start/end
  if (Align and FlexAlignItemsLast) <> 0 then
  begin
    if Ln.ReverseCross then
      SetCrossPosition(Ln.CrossStart)
    else
      SetCrossPosition(Ln.CrossStart + Ln.CrossSize - GetElCrossSize);
  end
  else
  begin
    if not Ln.ReverseCross then
      SetCrossPosition(Ln.CrossStart)
    else
      SetCrossPosition(Ln.CrossStart + Ln.CrossSize - GetElCrossSize);
  end;
end;

end.
