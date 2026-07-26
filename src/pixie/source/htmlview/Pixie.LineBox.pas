unit Pixie.LineBox;

// Line box — manages inline layout within a single line.
// Handles whitespace collapsing, text alignment, vertical alignment,
// and inline box tracking across lines.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Generics.Collections, Math,
  Pixie.Types, Pixie.CssLength, Pixie.CssProperties,
  Pixie.Element, Pixie.Container, Pixie.RenderItem;

type
  { TPixieLineContext }
  TPixieLineContext = record
    CalculatedTop: TPixiePixel;
    Top: TPixiePixel;
    Left: TPixiePixel;
    Right: TPixiePixel;
    function Width: TPixiePixel;
    procedure FixTop;
    procedure Init;
  end;

  { TPixieLineBoxItemType }
  TPixieLineBoxItemType = (
    lbiTextPart,
    lbiInlineStart,
    lbiInlineContinue,
    lbiInlineEnd
  );

  TPixieLineBoxItem = class;
  TPixieLineBoxItemList = TObjectList<TPixieLineBoxItem>;

  { TPixieLineBoxItem — base: wraps a render item for inline layout }
  TPixieLineBoxItem = class
  protected
    FElement: TPixieRenderItem;       // not owned
    FRenderedMinWidth: TPixiePixel;
    FItemsTop: TPixiePixel;
    FItemsBottom: TPixiePixel;
  public
    constructor Create(AElement: TPixieRenderItem);
    function GetEl: TPixieRenderItem;
    function GetItemType: TPixieLineBoxItemType; virtual;

    function Pos: PPixiePosition; virtual;
    procedure PlaceTo(X, Y: TPixiePixel); virtual;
    function Width: TPixiePixel; virtual;
    function Height: TPixiePixel; virtual;
    function Top: TPixiePixel; virtual;
    function Bottom: TPixiePixel; virtual;
    function Right: TPixiePixel; virtual;
    function Left: TPixiePixel; virtual;
    procedure YShift(Delta: TPixiePixel); virtual;

    function GetRenderedMinWidth: TPixiePixel; virtual;
    procedure SetRenderedMinWidth(Value: TPixiePixel); virtual;
    function GetIntrinsicMinWidth: TPixiePixel; virtual;

    procedure ResetItemsHeight;
    procedure AddItemHeight(ItemTop, ItemBottom: TPixiePixel);
    function GetItemsTop: TPixiePixel;
    function GetItemsBottom: TPixiePixel;
  end;

  { TPixieLbiStart — inline start marker }
  TPixieLbiStart = class(TPixieLineBoxItem)
  protected
    FPos: TPixiePosition;
  public
    constructor Create(AElement: TPixieRenderItem);
    function GetItemType: TPixieLineBoxItemType; override;
    function Pos: PPixiePosition; override;
    procedure PlaceTo(X, Y: TPixiePixel); override;
    function Width: TPixiePixel; override;
    function Height: TPixiePixel; override;
    function Top: TPixiePixel; override;
    function Bottom: TPixiePixel; override;
    function Right: TPixiePixel; override;
    function Left: TPixiePixel; override;
    function GetRenderedMinWidth: TPixiePixel; override;
    function GetIntrinsicMinWidth: TPixiePixel; override;
    procedure YShift(Delta: TPixiePixel); override;
  end;

  { TPixieLbiEnd — inline end marker }
  TPixieLbiEnd = class(TPixieLbiStart)
  public
    constructor Create(AElement: TPixieRenderItem);
    function GetItemType: TPixieLineBoxItemType; override;
    procedure PlaceTo(X, Y: TPixiePixel); override;
    function Right: TPixiePixel; override;
    function Left: TPixiePixel; override;
    procedure YShift(Delta: TPixiePixel); override;
  end;

  { TPixieLbiContinue — inline continue marker (zero width) }
  TPixieLbiContinue = class(TPixieLbiStart)
  public
    constructor Create(AElement: TPixieRenderItem);
    function GetItemType: TPixieLineBoxItemType; override;
    procedure PlaceTo(X, Y: TPixiePixel); override;
    function Right: TPixiePixel; override;
    function Left: TPixiePixel; override;
    function Width: TPixiePixel; override;
  end;

  { TPixieLineBox }
  TPixieLineBox = class
  private
    FTop: TPixiePixel;
    FLeft: TPixiePixel;
    FRight: TPixiePixel;
    FHeight: TPixiePixel;
    FWidth: TPixiePixel;
    FDefaultLineHeight: TPixieCssLineHeight;
    FFontMetrics: TPixieFontMetrics;
    FBaseline: TPixiePixel;
    FTextAlign: TPixieTextAlign;
    FMinWidth: TPixiePixel;
    FSuppressStrut: Boolean;
    FItems: TPixieLineBoxItemList;

    function HaveLastSpace: Boolean;
  public
    function IsBreakOnly: Boolean;
    constructor Create(ATop, ALeft, ARight: TPixiePixel;
      const ALineHeight: TPixieCssLineHeight;
      const AFm: TPixieFontMetrics; AAlign: TPixieTextAlign;
      ASuppressStrut: Boolean = False);
    destructor Destroy; override;

    function Bottom: TPixiePixel;
    function Top: TPixiePixel;
    function Right: TPixiePixel;
    function Left: TPixiePixel;
    function Height: TPixiePixel;
    function Width: TPixiePixel;
    function LineRight: TPixiePixel;
    function MinWidth: TPixiePixel;
    function IntrinsicMinWidth: TPixiePixel;
    function Baseline: TPixiePixel;
    function TopMargin: TPixiePixel;
    function BottomMargin: TPixiePixel;

    procedure AddItem(Item: TPixieLineBoxItem);
    function CanHold(Item: TPixieLineBoxItem; Ws: TPixieWhiteSpace): Boolean;
    function IsEmpty: Boolean;
    procedure YShift(Delta: TPixiePixel);
    function Finish(LastBox: Boolean;
      const CbContext: TPixieContainingBlockContext): TPixieLineBoxItemList;
    function NewWidth(ALeft, ARight: TPixiePixel): TPixieLineBoxItemList;
    function GetLastTextPart: TPixieRenderItem;
    function GetFirstTextPart: TPixieRenderItem;
    function EndsWithBreak: Boolean;

    property Items: TPixieLineBoxItemList read FItems;
  end;

implementation

const
  LineWidthTolerance = 0.5; // subpixel tolerance for line-fit checks (absorbs
    // FP rounding accumulated across multiple inline-block items in a single
    // line, e.g. table cell sized to its max-content where item widths +
    // cell padding round just over the cell's content width)

// --- Helper types (implementation only) ---

type
  TVaContext = record
    LineHeight: TPixiePixel;
    Baseline: TPixiePixel;
    Fm: TPixieFontMetrics;
    StartLbi: TPixieLineBoxItem;
  end;
  TVaContextList = TList<TVaContext>;

  TItemsDimensions = record
    Top: TPixiePixel;
    Bottom: TPixiePixel;
    Count: Integer;
    MaxHeight: TPixiePixel;
    procedure Init;
    procedure AddItem(Item: TPixieLineBoxItem);
    function Height: TPixiePixel;
  end;

  TInlineItemBox = record
    Element: TPixieRenderItem;
    Box: TPixiePosition;
  end;
  TInlineItemBoxList = TList<TInlineItemBox>;

procedure TItemsDimensions.Init;
begin
  Top := 0;
  Bottom := 0;
  Count := 0;
  MaxHeight := 0;
end;

procedure TItemsDimensions.AddItem(Item: TPixieLineBoxItem);
begin
  Top := Min(Top, Item.Top);
  Bottom := Max(Bottom, Item.Bottom);
  MaxHeight := Max(MaxHeight, Item.Height);
  Inc(Count);
end;

function TItemsDimensions.Height: TPixiePixel;
begin
  Result := Bottom - Top;
end;

function CalcVaBaseline(const Current: TVaContext;
  Va: TPixieVerticalAlign; const NewFont: TPixieFontMetrics;
  ATop, ABottom: TPixiePixel): TPixiePixel;
begin
  case Va of
    vaSuper:
      Result := Current.Baseline - Current.Fm.SuperShift;
    vaSub:
      Result := Current.Baseline + Current.Fm.SubShift;
    vaMiddle:
      Result := Current.Baseline - Current.Fm.XHeight / 2;
    vaTextTop:
      Result := Current.Baseline - (Current.Fm.Height - Current.Fm.BaseLine) +
                NewFont.Height - NewFont.BaseLine;
    vaTextBottom:
      Result := Current.Baseline + Current.Fm.BaseLine - NewFont.BaseLine;
    vaBottom:
      Result := ABottom - NewFont.BaseLine;
    vaTop:
      Result := ATop + NewFont.Height - NewFont.BaseLine;
  else
    Result := Current.Baseline;
  end;
end;

// ============================================================
// TPixieLineContext
// ============================================================

function TPixieLineContext.Width: TPixiePixel;
begin
  Result := Right - Left;
end;

procedure TPixieLineContext.FixTop;
begin
  CalculatedTop := Top;
end;

procedure TPixieLineContext.Init;
begin
  CalculatedTop := 0;
  Top := 0;
  Left := 0;
  Right := 0;
end;

// ============================================================
// TPixieLineBoxItem (base — text_part)
// ============================================================

constructor TPixieLineBoxItem.Create(AElement: TPixieRenderItem);
begin
  inherited Create;
  FElement := AElement;
  FRenderedMinWidth := 0;
  FItemsTop := 0;
  FItemsBottom := 0;
end;

function TPixieLineBoxItem.GetEl: TPixieRenderItem;
begin
  Result := FElement;
end;

function TPixieLineBoxItem.GetItemType: TPixieLineBoxItemType;
begin
  Result := lbiTextPart;
end;

function TPixieLineBoxItem.Pos: PPixiePosition;
begin
  Result := @FElement.FPos;
end;

procedure TPixieLineBoxItem.PlaceTo(X, Y: TPixiePixel);
begin
  FElement.FPos.X := X + FElement.ContentOffsetLeft;
  FElement.FPos.Y := Y + FElement.ContentOffsetTop;
end;

function TPixieLineBoxItem.Width: TPixiePixel;
begin
  Result := FElement.Width;
end;

function TPixieLineBoxItem.Height: TPixiePixel;
begin
  Result := FElement.Height;
end;

function TPixieLineBoxItem.Top: TPixiePixel;
begin
  Result := FElement.Top;
end;

function TPixieLineBoxItem.Bottom: TPixiePixel;
begin
  Result := FElement.Bottom;
end;

function TPixieLineBoxItem.Right: TPixiePixel;
begin
  Result := FElement.Right;
end;

function TPixieLineBoxItem.Left: TPixiePixel;
begin
  Result := FElement.Left;
end;

procedure TPixieLineBoxItem.YShift(Delta: TPixiePixel);
begin
  FElement.YShift(Delta);
end;

function TPixieLineBoxItem.GetRenderedMinWidth: TPixiePixel;
begin
  Result := FRenderedMinWidth;
end;

procedure TPixieLineBoxItem.SetRenderedMinWidth(Value: TPixiePixel);
begin
  FRenderedMinWidth := Value;
end;

function TPixieLineBoxItem.GetIntrinsicMinWidth: TPixiePixel;
begin
  Result := FElement.GetIntrinsicMinWidth;
end;

procedure TPixieLineBoxItem.ResetItemsHeight;
begin
  FItemsTop := 0;
  FItemsBottom := 0;
end;

procedure TPixieLineBoxItem.AddItemHeight(ItemTop, ItemBottom: TPixiePixel);
begin
  FItemsTop := Min(FItemsTop, ItemTop);
  FItemsBottom := Max(FItemsBottom, ItemBottom);
end;

function TPixieLineBoxItem.GetItemsTop: TPixiePixel;
begin
  Result := FItemsTop;
end;

function TPixieLineBoxItem.GetItemsBottom: TPixiePixel;
begin
  Result := FItemsBottom;
end;

// ============================================================
// TPixieLbiStart (inline_start)
// ============================================================

constructor TPixieLbiStart.Create(AElement: TPixieRenderItem);
begin
  inherited Create(AElement);
  FPos.Clear;
  FPos.Height := FElement.SrcEl.Css.FontMetrics.Height;
  FPos.Width := FElement.ContentOffsetLeft;
end;

function TPixieLbiStart.GetItemType: TPixieLineBoxItemType;
begin
  Result := lbiInlineStart;
end;

function TPixieLbiStart.Pos: PPixiePosition;
begin
  Result := @FPos;
end;

procedure TPixieLbiStart.PlaceTo(X, Y: TPixiePixel);
begin
  FPos.X := X + FElement.ContentOffsetLeft;
  FPos.Y := Y;
end;

function TPixieLbiStart.Width: TPixiePixel;
begin
  Result := FPos.Width;
end;

function TPixieLbiStart.Height: TPixiePixel;
begin
  Result := FPos.Height;
end;

function TPixieLbiStart.Top: TPixiePixel;
begin
  Result := FPos.Y;
end;

function TPixieLbiStart.Bottom: TPixiePixel;
begin
  Result := FPos.Y + FPos.Height;
end;

function TPixieLbiStart.Right: TPixiePixel;
begin
  Result := FPos.X;
end;

function TPixieLbiStart.Left: TPixiePixel;
begin
  Result := FPos.X - FElement.ContentOffsetLeft;
end;

function TPixieLbiStart.GetRenderedMinWidth: TPixiePixel;
begin
  Result := Width;
end;

function TPixieLbiStart.GetIntrinsicMinWidth: TPixiePixel;
begin
  Result := GetRenderedMinWidth;
end;

procedure TPixieLbiStart.YShift(Delta: TPixiePixel);
begin
  // Shift only the marker's own position, not the element's inline boxes.
  // Inline elements that span multiple lines have start/continue markers
  // in different line boxes; calling FElement.YShift would shift ALL boxes
  // from each line, causing over-shifting.
  FPos.Y := FPos.Y + Delta;
end;

// ============================================================
// TPixieLbiEnd (inline_end)
// ============================================================

constructor TPixieLbiEnd.Create(AElement: TPixieRenderItem);
begin
  inherited Create(AElement);
  FPos.Clear;
  FPos.Height := FElement.SrcEl.Css.FontMetrics.Height;
  FPos.Width := FElement.ContentOffsetRight;
end;

function TPixieLbiEnd.GetItemType: TPixieLineBoxItemType;
begin
  Result := lbiInlineEnd;
end;

procedure TPixieLbiEnd.PlaceTo(X, Y: TPixiePixel);
begin
  FPos.X := X;
  FPos.Y := Y;
end;

function TPixieLbiEnd.Right: TPixiePixel;
begin
  Result := FPos.X + FPos.Width;
end;

function TPixieLbiEnd.Left: TPixiePixel;
begin
  Result := FPos.X;
end;

procedure TPixieLbiEnd.YShift(Delta: TPixiePixel);
begin
  // no-op: end markers don't shift
end;

// ============================================================
// TPixieLbiContinue (inline_continue — zero width)
// ============================================================

constructor TPixieLbiContinue.Create(AElement: TPixieRenderItem);
begin
  inherited Create(AElement);
  FPos.Clear;
  FPos.Height := FElement.SrcEl.Css.FontMetrics.Height;
  FPos.Width := 0;
end;

function TPixieLbiContinue.GetItemType: TPixieLineBoxItemType;
begin
  Result := lbiInlineContinue;
end;

procedure TPixieLbiContinue.PlaceTo(X, Y: TPixiePixel);
begin
  FPos.X := X;
  FPos.Y := Y;
end;

function TPixieLbiContinue.Right: TPixiePixel;
begin
  Result := FPos.X;
end;

function TPixieLbiContinue.Left: TPixiePixel;
begin
  Result := FPos.X;
end;

function TPixieLbiContinue.Width: TPixiePixel;
begin
  Result := 0;
end;

// ============================================================
// TPixieLineBox
// ============================================================

constructor TPixieLineBox.Create(ATop, ALeft, ARight: TPixiePixel;
  const ALineHeight: TPixieCssLineHeight;
  const AFm: TPixieFontMetrics; AAlign: TPixieTextAlign;
  ASuppressStrut: Boolean);
begin
  inherited Create;
  FTop := ATop;
  FLeft := ALeft;
  FRight := ARight;
  FHeight := 0;
  FWidth := 0;
  FDefaultLineHeight := ALineHeight;
  FFontMetrics := AFm;
  FBaseline := 0;
  FTextAlign := AAlign;
  FMinWidth := 0;
  FSuppressStrut := ASuppressStrut;
  FItems := TPixieLineBoxItemList.Create(True);
end;

destructor TPixieLineBox.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TPixieLineBox.Bottom: TPixiePixel;
begin
  Result := FTop + FHeight;
end;

function TPixieLineBox.Top: TPixiePixel;
begin
  Result := FTop;
end;

function TPixieLineBox.Right: TPixiePixel;
begin
  Result := FLeft + FWidth;
end;

function TPixieLineBox.Left: TPixiePixel;
begin
  Result := FLeft;
end;

function TPixieLineBox.Height: TPixiePixel;
begin
  Result := FHeight;
end;

function TPixieLineBox.Width: TPixiePixel;
begin
  Result := FWidth;
end;

function TPixieLineBox.LineRight: TPixiePixel;
begin
  Result := FRight;
end;

function TPixieLineBox.MinWidth: TPixiePixel;
begin
  Result := FMinWidth;
end;

function TPixieLineBox.IntrinsicMinWidth: TPixiePixel;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FItems.Count - 1 do
    Result := Result + FItems[I].GetIntrinsicMinWidth;
end;

function TPixieLineBox.Baseline: TPixiePixel;
begin
  Result := FBaseline;
end;

function TPixieLineBox.TopMargin: TPixiePixel;
begin
  Result := 0;
end;

function TPixieLineBox.BottomMargin: TPixiePixel;
begin
  Result := 0;
end;

// --- AddItem ---

procedure TPixieLineBox.AddItem(Item: TPixieLineBoxItem);
var
  DoAdd: Boolean;
begin
  Item.GetEl.SetSkip(False);
  DoAdd := True;

  case Item.GetItemType of
    lbiTextPart:
      if Item.GetEl.SrcEl.IsWhiteSpace then
        DoAdd := (not IsEmpty) and (not HaveLastSpace);
    lbiInlineStart,
    lbiInlineEnd,
    lbiInlineContinue:
      DoAdd := True;
  end;

  if DoAdd then
  begin
    Item.PlaceTo(FLeft + FWidth, FTop);
    FWidth := FWidth + Item.Width;
    FHeight := Max(FHeight, Item.GetEl.Height);
    FItems.Add(Item);
  end
  else
  begin
    Item.GetEl.SetSkip(True);
    Item.Free;
  end;
end;

// --- CanHold ---

function TPixieLineBox.CanHold(Item: TPixieLineBoxItem; Ws: TPixieWhiteSpace): Boolean;
var
  LastEl: TPixieRenderItem;
begin
  if not Item.GetEl.SrcEl.IsInline then
    Exit(False);

  if Item.GetItemType = lbiTextPart then
  begin
    // Force new line on floats clearing
    if Item.GetEl.SrcEl.IsBreak and (Item.GetEl.Css.Clear_ <> ecNone) then
      Exit(False);

    LastEl := GetLastTextPart;

    // The first word can always be held
    if LastEl = nil then
      Exit(True);

    // Force new line if last placed element was a line break (non-clearing)
    if (LastEl <> nil) and LastEl.SrcEl.IsBreak and (LastEl.Css.Clear_ = ecNone) then
      Exit(False);

    // Line break should stay in current line box
    if Item.GetEl.SrcEl.IsBreak then
      Exit(True);

    if (Ws in [wsNowrap, wsPre]) or
       ((Ws = wsPreWrap) and Item.GetEl.SrcEl.IsSpace) then
      Exit(True);

    if FLeft + FWidth + Item.Width > FRight + LineWidthTolerance then
      Exit(False);
  end;

  Result := True;
end;

// --- IsEmpty ---

function TPixieLineBox.IsEmpty: Boolean;
var
  I: Integer;
begin
  if FItems.Count = 0 then
    Exit(True);

  if (FItems.Count = 1) and
     FItems[0].GetEl.SrcEl.IsBreak and
     (FItems[0].GetEl.SrcEl.Css.Clear_ <> ecNone) then
    Exit(True);

  for I := 0 to FItems.Count - 1 do
  begin
    if FItems[I].GetItemType = lbiTextPart then
    begin
      if (not FItems[I].GetEl.GetSkip) and (not FItems[I].GetEl.SrcEl.IsBreak) then
        Exit(False);
    end;
  end;
  Result := True;
end;

// --- HaveLastSpace ---

function TPixieLineBox.HaveLastSpace: Boolean;
var
  LastEl: TPixieRenderItem;
begin
  LastEl := GetLastTextPart;
  if LastEl <> nil then
    Result := LastEl.SrcEl.IsWhiteSpace or LastEl.SrcEl.IsBreak
  else
    Result := False;
end;

// --- IsBreakOnly ---

function TPixieLineBox.IsBreakOnly: Boolean;
var
  I: Integer;
  BreakFound: Boolean;
begin
  if FItems.Count = 0 then
    Exit(False);

  BreakFound := False;
  for I := FItems.Count - 1 downto 0 do
  begin
    if FItems[I].GetItemType = lbiTextPart then
    begin
      if FItems[I].GetEl.SrcEl.IsBreak then
        BreakFound := True
      else if not FItems[I].GetEl.GetSkip then
        Exit(False);
    end;
  end;
  Result := BreakFound;
end;

// --- YShift ---

procedure TPixieLineBox.YShift(Delta: TPixiePixel);
var
  I: Integer;
begin
  FTop := FTop + Delta;
  for I := 0 to FItems.Count - 1 do
    FItems[I].YShift(Delta);
end;

// --- GetFirstTextPart / GetLastTextPart ---

function TPixieLineBox.GetFirstTextPart: TPixieRenderItem;
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do
    if FItems[I].GetItemType = lbiTextPart then
      Exit(FItems[I].GetEl);
  Result := nil;
end;

function TPixieLineBox.GetLastTextPart: TPixieRenderItem;
var
  I: Integer;
begin
  for I := FItems.Count - 1 downto 0 do
    if FItems[I].GetItemType = lbiTextPart then
      Exit(FItems[I].GetEl);
  Result := nil;
end;

// True when this line ends with a non-clearing line break — i.e. a normal
// inline item placed next would start a fresh line (mirrors the break check
// in CanHold). Used to place a float that follows a <br> on the new line
// rather than back up on the line the <br> closed.
function TPixieLineBox.EndsWithBreak: Boolean;
var
  LastEl: TPixieRenderItem;
begin
  LastEl := GetLastTextPart;
  Result := (LastEl <> nil) and LastEl.SrcEl.IsBreak and
            (LastEl.SrcEl.Css.Clear_ = ecNone);
end;

// --- NewWidth ---

function TPixieLineBox.NewWidth(ALeft, ARight: TPixiePixel): TPixieLineBoxItemList;
var
  AddX: TPixiePixel;
  I, RemoveFrom: Integer;
  RetItems: TPixieLineBoxItemList;
begin
  RetItems := TPixieLineBoxItemList.Create(True);
  AddX := ALeft - FLeft;
  if AddX <> 0 then
  begin
    FLeft := ALeft;
    FRight := ARight;
    FWidth := 0;
    RemoveFrom := -1;

    // Skip first item (index 0), start from 1
    I := 1;
    while I < FItems.Count do
    begin
      if not FItems[I].GetEl.GetSkip then
      begin
        if FLeft + FWidth + FItems[I].Width > FRight + LineWidthTolerance then
        begin
          RemoveFrom := I;
          Break;
        end;
        FItems[I].Pos^.X := FItems[I].Pos^.X + AddX;
        FWidth := FWidth + FItems[I].GetEl.Width;
      end;
      Inc(I);
    end;

    if RemoveFrom >= 0 then
    begin
      // Move overflow items to return list
      FItems.OwnsObjects := False;
      for I := RemoveFrom to FItems.Count - 1 do
        RetItems.Add(FItems[I]);
      // Remove them from FItems
      while FItems.Count > RemoveFrom do
        FItems.Delete(FItems.Count - 1);
      FItems.OwnsObjects := True;
    end;
  end;
  Result := RetItems;
end;

// --- Finish ---

function TPixieLineBox.Finish(LastBox: Boolean;
  const CbContext: TPixieContainingBlockContext): TPixieLineBoxItemList;
var
  RetItems: TPixieLineBoxItemList;
  I, J, Counter: Integer;
  SpacingX: TPixiePixel;
  ShiftX: TPixiePixel;
  Offj, Cixx: Single;
  HasLineHeight: Boolean;
  LineHeightVal: TPixiePixel;
  CurrentContext: TVaContext;
  Contexts: TVaContextList;
  LineMaxHeight, TopAlignedMaxHeight, BottomAlignedMaxHeight,
    InlineBoxesDims: TItemsDimensions;
  Bl, ContentOffset, TopShift, ElH: TPixiePixel;
  IsTopBottomBox, Ignore, HasTextContent: Boolean;
  TopDownHeight: TPixiePixel;
  Diff1, Diff2: TPixiePixel;
  TopShiftCorrection: TPixiePixel;
  RelDX, RelDY: TPixiePixel;
  Inlines: TInlineItemBoxList;
  InlBox: TInlineItemBox;
  Lbi: TPixieLineBoxItem;
begin
  RetItems := TPixieLineBoxItemList.Create(True);

  // --- Trailing space/marker removal ---

  if not LastBox then
  begin
    while FItems.Count > 0 do
    begin
      if FItems[FItems.Count - 1].GetItemType = lbiTextPart then
      begin
        if FItems[FItems.Count - 1].GetEl.SrcEl.IsBreak or
           FItems[FItems.Count - 1].GetEl.SrcEl.IsWhiteSpace then
        begin
          FWidth := FWidth - FItems[FItems.Count - 1].Width;
          FItems[FItems.Count - 1].GetEl.SetSkip(True);
          FItems.Delete(FItems.Count - 1); // owned, will free
        end
        else
          Break;
      end
      else if FItems[FItems.Count - 1].GetItemType = lbiInlineStart then
      begin
        FWidth := FWidth - FItems[FItems.Count - 1].Width;
        // Move to ret_items — transfer ownership
        FItems.OwnsObjects := False;
        RetItems.Add(FItems[FItems.Count - 1]);
        FItems.Delete(FItems.Count - 1);
        FItems.OwnsObjects := True;
      end
      else
        Break;
    end;
  end
  else
  begin
    // Last box: remove trailing whitespace (may be between text and inline_end)
    I := FItems.Count - 1;
    while I >= 0 do
    begin
      if FItems[I].GetItemType = lbiTextPart then
      begin
        if FItems[I].GetEl.SrcEl.IsWhiteSpace then
        begin
          FItems[I].GetEl.SetSkip(True);
          FWidth := FWidth - FItems[I].Width;
          // Shift items to the right of this one
          if I < FItems.Count - 1 then
          begin
            for J := I + 1 to FItems.Count - 1 do
              FItems[J].Pos^.X := FItems[J].Pos^.X - FItems[I].Width;
          end;
          FItems.Delete(I); // owned, will free
          // Don't decrement — I now points to next item (or beyond)
          Dec(I);
        end
        else
          Break;
      end
      else
        Dec(I);
    end;
  end;

  // --- Empty line ---

  if IsEmpty or ((not IsEmpty) and LastBox and IsBreakOnly) then
  begin
    // Default: use block container's strut
    FHeight := FDefaultLineHeight.ComputedValue;
    FBaseline := FFontMetrics.BaseLine;
    // Quirks mode: suppress the strut and use the <br>'s own line-height;
    // empty lines without a <br> get zero height
    if FSuppressStrut then
    begin
      FHeight := 0;
      FBaseline := 0;
      for I := 0 to FItems.Count - 1 do
        if FItems[I].GetEl.SrcEl.IsBreak then
        begin
          FHeight := FItems[I].GetEl.Css.LineHeight.ComputedValue;
          FBaseline := FItems[I].GetEl.Css.FontMetrics.BaseLine;
          Break;
        end;
    end;
    Result := RetItems;
    Exit;
  end;

  // --- Text alignment ---

  SpacingX := 0;
  ShiftX := 0;

  case FTextAlign of
    taRight, taBlockRight:
      if FWidth < (FRight - FLeft) then
        ShiftX := (FRight - FLeft) - FWidth;
    taCenter, taBlockCenter:
      if FWidth < (FRight - FLeft) then
        ShiftX := ((FRight - FLeft) - FWidth) / 2;
    taJustify:
      if FWidth < (FRight - FLeft) then
      begin
        ShiftX := 0;
        SpacingX := (FRight - FLeft) - FWidth;
        if SpacingX > FWidth / 4 then
          SpacingX := 0;
      end;
  else
    ShiftX := 0;
  end;

  Counter := 0;
  if FItems.Count > 1 then
    Offj := SpacingX / (FItems.Count - 1)
  else
    Offj := 0;
  Cixx := 0;

  HasLineHeight := not FDefaultLineHeight.CssValue.IsPredefined;
  if HasLineHeight then
    LineHeightVal := FDefaultLineHeight.ComputedValue
  else
    LineHeightVal := 0;

  HasTextContent := False;

  CurrentContext.Baseline := 0;
  CurrentContext.Fm := FFontMetrics;
  CurrentContext.StartLbi := nil;
  CurrentContext.LineHeight := FDefaultLineHeight.ComputedValue;

  FMinWidth := 0;

  LineMaxHeight.Init;
  TopAlignedMaxHeight.Init;
  BottomAlignedMaxHeight.Init;
  InlineBoxesDims.Init;

  Contexts := TVaContextList.Create;
  try

  // ========================
  // First pass
  // ========================

  for I := 0 to FItems.Count - 1 do
  begin
    Lbi := FItems[I];

    // Text-align justify spacing
    FMinWidth := FMinWidth + Lbi.GetRenderedMinWidth;
    if (SpacingX <> 0) and (Counter > 0) then
    begin
      Cixx := Cixx + Offj;
      if (Counter + 1) = FItems.Count then
        Cixx := Cixx + 0.99;
      Lbi.Pos^.X := Lbi.Pos^.X + Trunc(Cixx);
    end;
    Inc(Counter);

    if ((FTextAlign = taRight) or (SpacingX <> 0)) and (Counter = FItems.Count) then
    begin
      // Forcibly justify last element to the right side
      Lbi.Pos^.X := FRight - Lbi.Pos^.Width - Lbi.GetEl.ContentOffsetRight;
    end
    else if ShiftX <> 0 then
      Lbi.Pos^.X := Lbi.Pos^.X + ShiftX;

    // Calculate new baseline for inline start/continue
    if (Lbi.GetItemType = lbiInlineStart) or (Lbi.GetItemType = lbiInlineContinue) then
    begin
      Contexts.Add(CurrentContext);
      if (Lbi.GetEl.Css.VerticalAlign = vaTop) or (Lbi.GetEl.Css.VerticalAlign = vaBottom) then
      begin
        CurrentContext.Baseline := 0;
        CurrentContext.StartLbi := Lbi;
        CurrentContext.StartLbi.ResetItemsHeight;
      end
      else if CurrentContext.StartLbi <> nil then
      begin
        CurrentContext.Baseline := CalcVaBaseline(CurrentContext,
          Lbi.GetEl.Css.VerticalAlign,
          Lbi.GetEl.Css.FontMetrics,
          CurrentContext.StartLbi.Top, CurrentContext.StartLbi.Bottom);
      end
      else
      begin
        CurrentContext.StartLbi := nil;
        CurrentContext.Baseline := CalcVaBaseline(CurrentContext,
          Lbi.GetEl.Css.VerticalAlign,
          Lbi.GetEl.Css.FontMetrics,
          LineMaxHeight.Top, LineMaxHeight.Bottom);
      end;
      CurrentContext.Fm := Lbi.GetEl.Css.FontMetrics;
      CurrentContext.LineHeight := Lbi.GetEl.Css.LineHeight.ComputedValue;
    end;

    Bl := CurrentContext.Baseline;
    ContentOffset := 0;
    IsTopBottomBox := False;
    Ignore := False;

    // Align element by baseline
    if not (Lbi.GetEl.SrcEl.Css.Display in [displayInlineText,
            displayInline]) then
    begin
      ContentOffset := Lbi.GetEl.ContentOffsetTop;
      case Lbi.GetEl.Css.VerticalAlign of
        vaBottom, vaTop:
          begin
            Bl := 0;
            IsTopBottomBox := True;
          end;
        vaTextBottom:
          begin
            Lbi.Pos^.Y := Bl + CurrentContext.Fm.BaseLine - Lbi.GetEl.Height + ContentOffset;
            Ignore := True;
          end;
        vaTextTop:
          begin
            Lbi.Pos^.Y := Bl - CurrentContext.Fm.Ascent + ContentOffset;
            Ignore := True;
          end;
        vaMiddle:
          begin
            if Lbi.GetEl.SrcEl.IsReplaced then
            begin
              // Replaced elements (buttons, inputs): center the border box
              ElH := Lbi.GetEl.Height - Lbi.GetEl.MarginTop - Lbi.GetEl.MarginBottom;
              Lbi.Pos^.Y := Bl - CurrentContext.Fm.XHeight / 2 -
                ElH / 2 + ContentOffset - Lbi.GetEl.MarginTop;
            end
            else
              Lbi.Pos^.Y := Bl - CurrentContext.Fm.XHeight / 2 -
                Lbi.GetEl.Height / 2 + ContentOffset;
            Ignore := True;
          end;
      else
        Bl := CalcVaBaseline(CurrentContext,
          Lbi.GetEl.Css.VerticalAlign,
          Lbi.GetEl.Css.FontMetrics,
          LineMaxHeight.Top, LineMaxHeight.Bottom);
      end;
    end;

    if not Ignore then
      Lbi.Pos^.Y := Bl - Lbi.GetEl.GetLastBaseline + ContentOffset;

    if IsTopBottomBox then
    begin
      case Lbi.GetEl.Css.VerticalAlign of
        vaTop:
          TopAlignedMaxHeight.AddItem(Lbi);
        vaBottom:
          BottomAlignedMaxHeight.AddItem(Lbi);
      end;
    end
    else if CurrentContext.StartLbi <> nil then
    begin
      CurrentContext.StartLbi.AddItemHeight(Lbi.Top, Lbi.Bottom);
      case CurrentContext.StartLbi.GetEl.Css.VerticalAlign of
        vaTop:
          TopAlignedMaxHeight.AddItem(Lbi);
        vaBottom:
          BottomAlignedMaxHeight.AddItem(Lbi);
      end;
    end
    else
    begin
      if not Lbi.GetEl.SrcEl.IsInlineBox then
      begin
        LineMaxHeight.AddItem(Lbi);
        if Lbi.GetItemType = lbiTextPart then
          HasTextContent := True;
      end
      else
        InlineBoxesDims.AddItem(Lbi);
    end;

    if (not Lbi.GetEl.SrcEl.IsInlineBox) and
       (not Lbi.GetEl.Css.LineHeight.CssValue.IsPredefined) then
    begin
      if HasLineHeight then
        LineHeightVal := Max(LineHeightVal, Lbi.GetEl.Css.LineHeight.ComputedValue)
      else
      begin
        HasLineHeight := True;
        LineHeightVal := Lbi.GetEl.Css.LineHeight.ComputedValue;
      end;
    end;

    if Lbi.GetItemType = lbiInlineEnd then
    begin
      if Contexts.Count > 0 then
      begin
        CurrentContext := Contexts[Contexts.Count - 1];
        Contexts.Delete(Contexts.Count - 1);
      end;
    end;
  end;

  // ========================
  // Height calculation
  // ========================

  TopShift := 0;

  if HasLineHeight then
  begin
    FHeight := LineHeightVal;
    if (LineMaxHeight.Count <> 0) and (HasTextContent or not FSuppressStrut) then
    begin
      TopShift := Abs(LineMaxHeight.Top);
      TopShiftCorrection := (LineHeightVal - LineMaxHeight.Height) / 2;
      FBaseline := LineHeightVal - (TopShiftCorrection + LineMaxHeight.Height) + LineMaxHeight.Bottom;
      TopShift := TopShift + TopShiftCorrection;
      if InlineBoxesDims.Count > 0 then
      begin
        Diff2 := Abs(InlineBoxesDims.Top) - Abs(TopShift);
        if Diff2 > 0 then
        begin
          FHeight := FHeight + Diff2;
          TopShift := TopShift + Diff2;
          FBaseline := FBaseline + Diff2;
        end;
        Diff1 := InlineBoxesDims.Bottom - (LineMaxHeight.Bottom + TopShiftCorrection);
        if Diff1 > 0 then
          FHeight := FHeight + Diff1;
      end;
    end
    else if InlineBoxesDims.Count <> 0 then
    begin
      // The strut (CSS2 §10.8.1) is an imaginary zero-width inline box
      // with the block container's font and line-height.  Even when no text
      // items remain on the line (e.g. trailing <br> was removed), the
      // strut still contributes to the line box height.
      // In limited quirks / quirks mode, the strut is suppressed for lines
      // inside table cells that contain only replaced elements (images).
      if FSuppressStrut then
      begin
        TopShift := Abs(InlineBoxesDims.Top);
        FBaseline := InlineBoxesDims.Bottom;
        FHeight := TopShift + FBaseline;
      end
      else
      begin
        TopShiftCorrection := (LineHeightVal - FFontMetrics.Height) / 2;
        TopShift := Max(Abs(InlineBoxesDims.Top),
          FFontMetrics.Ascent + TopShiftCorrection);
        FBaseline := Max(InlineBoxesDims.Bottom,
          FFontMetrics.Descent + TopShiftCorrection);
        FHeight := TopShift + FBaseline;
      end;
    end
    else
      TopShift := 0;

    TopDownHeight := Max(TopAlignedMaxHeight.MaxHeight, BottomAlignedMaxHeight.MaxHeight);
    if TopDownHeight > FHeight then
    begin
      if BottomAlignedMaxHeight.Count > 0 then
        TopShift := TopShift + BottomAlignedMaxHeight.Height - FHeight;
      FHeight := TopDownHeight;
    end;

  end
  else
  begin
    // No explicit line-height — add inline boxes dimensions
    if FSuppressStrut and (not HasTextContent) and (InlineBoxesDims.Count > 0) then
    begin
      // Quirks mode table cell with only replaced elements:
      // ignore inline marker dimensions, use only replaced element dims
      FHeight := Max(InlineBoxesDims.Height,
        Max(TopAlignedMaxHeight.Height, BottomAlignedMaxHeight.Height));
      TopShift := Abs(InlineBoxesDims.Top);
      FBaseline := InlineBoxesDims.Bottom;
    end
    else
    begin
      LineMaxHeight.Top := Min(LineMaxHeight.Top, InlineBoxesDims.Top);
      LineMaxHeight.Bottom := Max(LineMaxHeight.Bottom, InlineBoxesDims.Bottom);

      FHeight := Max(LineMaxHeight.Height,
        Max(TopAlignedMaxHeight.Height, BottomAlignedMaxHeight.Height));

      TopShift := -Min(LineMaxHeight.Top,
        LineMaxHeight.Bottom - BottomAlignedMaxHeight.Height);
      FBaseline := LineMaxHeight.Bottom;
    end;
  end;

  // ========================
  // Second pass
  // ========================

  Inlines := TInlineItemBoxList.Create;
  try

  Contexts.Clear;
  CurrentContext.Baseline := 0;
  CurrentContext.Fm := FFontMetrics;
  CurrentContext.StartLbi := nil;

  for I := 0 to FItems.Count - 1 do
  begin
    Lbi := FItems[I];

    if (Lbi.GetItemType = lbiInlineStart) or (Lbi.GetItemType = lbiInlineContinue) then
    begin
      Contexts.Add(CurrentContext);
      CurrentContext.Fm := Lbi.GetEl.Css.FontMetrics;

      if Lbi.GetEl.Css.VerticalAlign = vaTop then
      begin
        CurrentContext.Baseline := FTop - Lbi.GetItemsTop;
        CurrentContext.StartLbi := Lbi;
      end
      else if Lbi.GetEl.Css.VerticalAlign = vaBottom then
      begin
        CurrentContext.Baseline := FTop + FHeight - Lbi.GetItemsBottom;
        CurrentContext.StartLbi := Lbi;
      end;
    end
    else if Lbi.GetItemType = lbiInlineEnd then
    begin
      if Contexts.Count > 0 then
      begin
        CurrentContext := Contexts[Contexts.Count - 1];
        Contexts.Delete(Contexts.Count - 1);
      end;
    end;

    if CurrentContext.StartLbi <> nil then
    begin
      Lbi.Pos^.Y := CurrentContext.Baseline - Lbi.GetEl.GetLastBaseline +
        Lbi.GetEl.ContentOffsetTop;
    end
    else if ((Lbi.GetEl.Css.VerticalAlign = vaTop) or (Lbi.GetEl.Css.VerticalAlign = vaBottom)) and
            (Lbi.GetItemType = lbiTextPart) then
    begin
      if Lbi.GetEl.Css.VerticalAlign = vaTop then
        Lbi.Pos^.Y := FTop + Lbi.GetEl.ContentOffsetTop
      else
        Lbi.Pos^.Y := FTop + FHeight - (Lbi.Bottom - Lbi.Top) + Lbi.GetEl.ContentOffsetBottom;
    end
    else
    begin
      // Move element to the correct position
      Lbi.Pos^.Y := Lbi.Pos^.Y + FTop + TopShift;
    end;

    Lbi.GetEl.ApplyRelativeShift(CbContext);

    // The inline start/continue marker carries its own FPos, which is what the
    // inline background/border boxes are built from below. ApplyRelativeShift
    // only moves the element's FPos (used by the text fragments), so for a
    // position:relative inline the text shifts but the pill stays put. Shift
    // the marker by the same offset so the box follows its text.
    if (Lbi.GetItemType = lbiInlineStart) or
       (Lbi.GetItemType = lbiInlineContinue) then
    begin
      Lbi.GetEl.GetRelativeOffset(CbContext, RelDX, RelDY);
      Lbi.Pos^.X := Lbi.Pos^.X + RelDX;
      Lbi.Pos^.Y := Lbi.Pos^.Y + RelDY;
    end;

    // Build inline box positions
    if (Lbi.GetItemType = lbiInlineStart) or (Lbi.GetItemType = lbiInlineContinue) then
    begin
      if Lbi.GetItemType = lbiInlineStart then
        Lbi.GetEl.ClearInlineBoxes;

      InlBox.Element := Lbi.GetEl;
      InlBox.Box.X := Lbi.Left;
      InlBox.Box.Y := Lbi.Top - Lbi.GetEl.ContentOffsetTop;
      InlBox.Box.Height := Lbi.Bottom - Lbi.Top + Lbi.GetEl.ContentOffsetHeight;
      InlBox.Box.Width := 0;
      Inlines.Add(InlBox);
    end
    else if Lbi.GetItemType = lbiInlineEnd then
    begin
      if Inlines.Count > 0 then
      begin
        InlBox := Inlines[Inlines.Count - 1];
        InlBox.Box.Width := Lbi.Right - InlBox.Box.X;
        InlBox.Element.AddInlineBox(InlBox.Box);
        Inlines.Delete(Inlines.Count - 1);
      end;
    end;
  end;

  // Close unclosed inline containers — produce continue markers for next line
  for I := Inlines.Count - 1 downto 0 do
  begin
    InlBox := Inlines[I];
    InlBox.Box.Width := FItems[FItems.Count - 1].Right - InlBox.Box.X;
    InlBox.Element.AddInlineBox(InlBox.Box);

    RetItems.Insert(0, TPixieLbiContinue.Create(InlBox.Element));
  end;

  finally
    Inlines.Free;
  end;

  finally
    Contexts.Free;
  end;

  Result := RetItems;
end;

end.
