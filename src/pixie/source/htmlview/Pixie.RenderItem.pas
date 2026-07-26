unit Pixie.RenderItem;

// Base render item — the foundation for all render tree nodes.
//
// The render tree mirrors the DOM tree but with layout-specific nodes.
// Each render item holds computed margins/padding/borders and position.
// Subclasses (RenderBlock, RenderInlineContext, RenderFlex, etc.)
// override _Render to implement specific layout algorithms.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Generics.Collections, Math,
  Pixie.Types, Pixie.CssLength, Pixie.CssProperties, Pixie.WebColor,
  Pixie.Element, Pixie.FormattingContext, Pixie.ScrollView,
  Pixie.Container, Pixie.Matrix;

type
  TPixieRenderItem = class;
  TPixieRenderItemList = TObjectList<TPixieRenderItem>;
  TPixieRenderItemVector = TList<TPixieRenderItem>; // non-owning

  { TPixieRenderItem }
  TPixieRenderItem = class
  protected
    function _Render(X, Y: TPixiePixel;
      const CbContext: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext;
      SecondPass: Boolean): TPixiePixel; virtual;

  public
    FElement: TPixieElement;           // non-owning
    FParent: TPixieRenderItem;         // non-owning (weak)
    FChildren: TPixieRenderItemList;   // owns children
    FMargins: TPixieMargins;
    FPadding: TPixieMargins;
    FBorders: TPixieMargins;
    FPos: TPixiePosition;
    FSkip: Boolean;
    FLayoutPositioned: Boolean;          // True if positioned during layout
    FStickyShiftX: TPixiePixel;          // last position:sticky paint shift
    FStickyShiftY: TPixiePixel;          // (kept current for hit-testing)
    FRelShiftDone: Boolean;              // True after ApplyRelativeShift ran
    FPositioned: TPixieRenderItemVector; // non-owning
    FScrollView: TPixieScrollView;       // owned, can be nil
    FIntrinsicMinWidth: TPixiePixel;     // CSS min-content width; 0 = unknown

    function CalculateContainingBlockContext(
      const CbContext: TPixieContainingBlockContext): TPixieContainingBlockContext;
    procedure CalcCbLength(const Len: TPixieCssLength;
      PercentBase: TPixiePixel; var OutValue: TPixieTypedPixel);
    constructor Create(ASrcEl: TPixieElement); virtual;
    destructor Destroy; override;

    // Scroll helpers
    function GetScrollLeft: TPixiePixel; inline;
    function GetScrollTop: TPixiePixel; inline;
    procedure ScrollBox(var Box: TPixiePosition); inline;
    function HScroll(Dx: TPixiePixel): TPixiePixel; inline;
    function VScroll(Dy: TPixiePixel): TPixiePixel; inline;
    function IsHScrollable(Dx: TPixiePixel): Boolean; inline;
    function IsVScrollable(Dy: TPixiePixel): Boolean; inline;

    // Tree access
    function GetChildren: TPixieRenderItemList; inline;
    property Pos: TPixiePosition read FPos write FPos;
    function GetSkip: Boolean; inline;
    procedure SetSkip(Value: Boolean); inline;
    function GetParent: TPixieRenderItem; inline;
    procedure SetParent(Value: TPixieRenderItem); inline;
    // Position translated into document coordinates by accumulating
    // every ancestor's Pos.
    function AbsolutePos: TPixiePosition;
    function SrcEl: TPixieElement; inline;
    function Css: TPixieCssProperties; inline;
    procedure AddChild(Ri: TPixieRenderItem);
    function IsRoot: Boolean; inline;

    // Placement helper
    function CalcPlacement(AX: TPixiePixel = 0;
      AY: TPixiePixel = 0): TPixiePosition; inline;

    // Outer box accessors (content + margin + padding + border)
    function Left: TPixiePixel; inline;
    function Right: TPixiePixel; inline;
    function Top: TPixiePixel; inline;
    function Bottom: TPixiePixel; inline;
    function Width: TPixiePixel; inline;
    function Height: TPixiePixel; inline;

    // Padding accessors
    function PaddingLeft: TPixiePixel; inline;
    function PaddingRight: TPixiePixel; inline;
    function PaddingTop: TPixiePixel; inline;
    function PaddingBottom: TPixiePixel; inline;

    // Border accessors
    function BorderLeft: TPixiePixel; inline;
    function BorderRight: TPixiePixel; inline;
    function BorderTop: TPixiePixel; inline;
    function BorderBottom: TPixiePixel; inline;

    // Margin accessors
    function MarginLeft: TPixiePixel; inline;
    function MarginRight: TPixiePixel; inline;
    function MarginTop: TPixiePixel; inline;
    function MarginBottom: TPixiePixel; inline;

    // Margins/padding/borders record access
    function GetMargins: TPixieMargins; inline;
    function GetPaddings: TPixieMargins; inline;
    procedure SetPaddings(const Value: TPixieMargins); inline;
    function GetBorders: TPixieMargins; inline;

    // Content offset (margin + padding + border)
    function ContentOffsetTop: TPixiePixel; inline;
    function ContentOffsetBottom: TPixiePixel; inline;
    function ContentOffsetLeft: TPixiePixel; inline;
    function ContentOffsetRight: TPixiePixel; inline;
    function ContentOffsetWidth: TPixiePixel; inline;
    function ContentOffsetHeight: TPixiePixel; inline;

    // Render offset (box-sizing aware)
    function RenderOffsetLeft: TPixiePixel; inline;
    function RenderOffsetRight: TPixiePixel; inline;
    function RenderOffsetWidth: TPixiePixel; inline;
    function RenderOffsetTop: TPixiePixel; inline;
    function RenderOffsetBottom: TPixiePixel; inline;
    function RenderOffsetHeight: TPixiePixel; inline;

    // Box sizing adjustment
    function BoxSizingLeft: TPixiePixel; inline;
    function BoxSizingRight: TPixiePixel; inline;
    function BoxSizingWidth: TPixiePixel; inline;
    function BoxSizingTop: TPixiePixel; inline;
    function BoxSizingBottom: TPixiePixel; inline;
    function BoxSizingHeight: TPixiePixel; inline;

    // Collapse helpers
    function CollapseTopMargin: Boolean;
    function CollapseBottomMargin: Boolean;
    function IsVisible: Boolean; inline;
    function IsFlexItem: Boolean;
    function IsGridItem: Boolean;

    // CSS min-content width; falls back to FPos.Width when not computed.
    function GetIntrinsicMinWidth: TPixiePixel; virtual;

    // Core render pipeline
    function Render(X, Y: TPixiePixel;
      const CbContext: TPixieContainingBlockContext;
      FmtCtx: TPixieFormattingContext;
      SecondPass: Boolean = False): TPixiePixel;
    procedure CalcOutlines(ParentWidth: TPixiePixel);
    function CalcAutoMargins(ParentWidth: TPixiePixel): TPixiePixel;
    procedure ApplyRelativeShift(
      const CbContext: TPixieContainingBlockContext);
    // Builds the element's CSS transform matrix in draw coordinates (BaseX/
    // BaseY = the parent's draw origin). False when the element has no
    // transform. Composed about transform-origin.
    function BuildTransformMatrix(BaseX, BaseY: TPixiePixel;
      out M: TPixieMatrix): Boolean;
    // Maps a hit-test point (in this element's parent-content frame, i.e.
    // Base=0) back through the inverse of this element's transform, so the
    // point can be tested against the untransformed layout. No-op when the
    // element has no transform or the matrix is singular.
    procedure MapPointInverse(var X, Y: TPixiePixel);
    procedure GetRelativeOffset(
      const CbContext: TPixieContainingBlockContext;
      out DX, DY: TPixiePixel);

    // Split inlines
    function SplitInlines: TPixieSplitResult;

    // Positioned elements
    function FetchPositioned: Boolean;
    procedure RenderPositioned(Rt: TPixieRenderType = rtAll);
    procedure AddPositioned(El: TPixieRenderItem);
    function ElementStaticOffset(
      El: TPixieRenderItem): TPixiePointF;

    // Drawing
    procedure DrawStackingContext(Hdc: PtrUInt; X, Y: TPixiePixel;
      Clip: PPixiePosition; WithPositioned: Boolean);
    procedure DrawChildren(Hdc: PtrUInt; X, Y: TPixiePixel;
      Clip: PPixiePosition; Flag: TPixieDrawFlag;
      ZIndex: Integer); virtual;
    // Overflow scrollbar thumbs; Box is the content box in screen coords.
    procedure DrawScrollbars(Hdc: PtrUInt; Cont: TPixieContainer;
      const Box: TPixiePosition);
    // position:sticky paint offset. Origin is this item's parent content box
    // origin in screen coords (the same origin children are drawn at). Returns
    // the clamped shift (DX,DY) that keeps the item pinned to its inset while
    // staying within its containing block.
    procedure ComputeStickyShift(Cont: TPixieContainer;
      OriginX, OriginY: TPixiePixel; out DX, DY: TPixiePixel);

    // Hit testing
    function GetChildByPoint(X, Y, ClientX, ClientY: TPixiePixel;
      Flag: TPixieDrawFlag; ZIndex: Integer;
      Check: TPixieRenderItemCheckFunc): TPixieElement; virtual;
    function GetElementByPoint(X, Y, ClientX, ClientY: TPixiePixel;
      Check: TPixieRenderItemCheckFunc): TPixieElement;
    function GetTextByPoint(X, Y: TPixiePixel): TPixieElement; virtual;
    function GetNearestTextByPoint(X, Y: TPixiePixel): TPixieElement; virtual;
    function IsPointInside(X, Y: TPixiePixel): Boolean;

    // Document size / redraw
    procedure CalcDocumentSize(var Sz: TPixieSize;
      X: TPixiePixel = 0; Y: TPixiePixel = 0);
    procedure GetRedrawBox(var APos: TPixiePosition;
      X: TPixiePixel = 0; Y: TPixiePixel = 0);
    procedure GetRenderingBoxes(Boxes: TPixiePositionVector);

    // Virtual methods (stubs/defaults)
    function Init: TPixieRenderItem; virtual;
    procedure ApplyVerticalAlign; virtual;
    function GetFirstBaseline: TPixiePixel; virtual;
    function GetLastBaseline: TPixiePixel; virtual;
    function Clone: TPixieRenderItem; virtual;
    procedure GetInlineBoxes(Boxes: TPixiePositionVector); virtual;
    procedure AddInlineBox(const Box: TPixiePosition); virtual;
    procedure ClearInlineBoxes; virtual;
    function GetDrawVerticalOffset: TPixiePixel; virtual;
    function GetDrawBottomOffset: TPixiePixel; virtual;
    procedure YShift(Delta: TPixiePixel); virtual;

    // Debug
    procedure Dump(var Output: string; Indent: Integer = 0);
  end;

implementation

uses
  Pixie.Document, Pixie.Borders, Pixie.Background;

const
  // Half-extent used to leave one axis effectively unbounded when only the
  // other axis has a non-visible overflow (e.g. overflow-x:auto clips X but
  // must not clip content height).
  ClipUnboundedExtent = 1000000;

{ TPixieRenderItem }

constructor TPixieRenderItem.Create(ASrcEl: TPixieElement);
var
  Doc: TPixieDocument;
  Fm: TPixieFontMetrics;
begin
  inherited Create;
  FElement := ASrcEl;
  FParent := nil;
  FChildren := TPixieRenderItemList.Create(True);
  FSkip := False;
  FLayoutPositioned := False;
  FStickyShiftX := 0;
  FStickyShiftY := 0;
  FRelShiftDone := False;
  FPositioned := nil;
  FScrollView := nil;
  FIntrinsicMinWidth := 0;
  FPos.Clear;
  FMargins.Init;
  FPadding.Init;
  FBorders.Init;

  if FElement <> nil then
  begin
    Assert(FElement.GetDocument is TPixieDocument);
    Doc := TPixieDocument(FElement.GetDocument);
    Fm := FElement.Css.FontMetrics;

    FMargins.Left   := Doc.ToPixels(FElement.Css.CssMargins.Left, Fm, 0);
    FMargins.Right  := Doc.ToPixels(FElement.Css.CssMargins.Right, Fm, 0);
    FMargins.Top    := Doc.ToPixels(FElement.Css.CssMargins.Top, Fm, 0);
    FMargins.Bottom := Doc.ToPixels(FElement.Css.CssMargins.Bottom, Fm, 0);

    // CSS spec: margins do not apply to table-internal elements
    if FElement.Css.Display in [displayTableCell, displayTableRow,
       displayTableRowGroup, displayTableHeaderGroup,
       displayTableFooterGroup, displayTableColumn,
       displayTableColumnGroup] then
      FMargins.Init;

    FPadding.Left   := Doc.ToPixels(FElement.Css.CssPadding.Left, Fm, 0);
    FPadding.Right  := Doc.ToPixels(FElement.Css.CssPadding.Right, Fm, 0);
    FPadding.Top    := Doc.ToPixels(FElement.Css.CssPadding.Top, Fm, 0);
    FPadding.Bottom := Doc.ToPixels(FElement.Css.CssPadding.Bottom, Fm, 0);

    FBorders.Left   := Doc.ToPixels(FElement.Css.CssBorders.Left.Width, Fm, 0);
    FBorders.Right  := Doc.ToPixels(FElement.Css.CssBorders.Right.Width, Fm, 0);
    FBorders.Top    := Doc.ToPixels(FElement.Css.CssBorders.Top.Width, Fm, 0);
    FBorders.Bottom := Doc.ToPixels(FElement.Css.CssBorders.Bottom.Width, Fm, 0);
  end;
end;

destructor TPixieRenderItem.Destroy;
begin
  FScrollView.Free;
  FPositioned.Free;
  FChildren.Free;
  inherited Destroy;
end;

// --- Scroll helpers ---

function TPixieRenderItem.GetScrollLeft: TPixiePixel;
begin
  if FScrollView <> nil then
    Result := FScrollView.GetLeft
  else
    Result := 0;
end;

function TPixieRenderItem.GetScrollTop: TPixiePixel;
begin
  if FScrollView <> nil then
    Result := FScrollView.GetTop
  else
    Result := 0;
end;

procedure TPixieRenderItem.ScrollBox(var Box: TPixiePosition);
begin
  if FScrollView <> nil then
  begin
    Box.X := Box.X - FScrollView.GetLeft;
    Box.Y := Box.Y - FScrollView.GetTop;
  end;
end;

function TPixieRenderItem.HScroll(Dx: TPixiePixel): TPixiePixel;
begin
  if FScrollView <> nil then
    Result := FScrollView.HScroll(Dx)
  else
    Result := 0;
end;

function TPixieRenderItem.VScroll(Dy: TPixiePixel): TPixiePixel;
begin
  if FScrollView <> nil then
    Result := FScrollView.VScroll(Dy)
  else
    Result := 0;
end;

function TPixieRenderItem.IsHScrollable(Dx: TPixiePixel): Boolean;
begin
  if FScrollView <> nil then
    Result := FScrollView.IsHScrollable(Dx)
  else
    Result := False;
end;

function TPixieRenderItem.IsVScrollable(Dy: TPixiePixel): Boolean;
begin
  if FScrollView <> nil then
    Result := FScrollView.IsVScrollable(Dy)
  else
    Result := False;
end;

// --- Tree access ---

function TPixieRenderItem.GetChildren: TPixieRenderItemList;
begin
  Result := FChildren;
end;

function TPixieRenderItem.GetSkip: Boolean;
begin
  Result := FSkip;
end;

procedure TPixieRenderItem.SetSkip(Value: Boolean);
begin
  FSkip := Value;
end;

function TPixieRenderItem.GetParent: TPixieRenderItem;
begin
  Result := FParent;
end;

procedure TPixieRenderItem.SetParent(Value: TPixieRenderItem);
begin
  FParent := Value;
end;

function TPixieRenderItem.AbsolutePos: TPixiePosition;
var
  Walk: TPixieRenderItem;
begin
  Result := FPos;
  Walk := FParent;
  while Walk <> nil do
  begin
    Result.X := Result.X + Walk.Pos.X;
    Result.Y := Result.Y + Walk.Pos.Y;
    Walk := Walk.GetParent;
  end;
end;

function TPixieRenderItem.SrcEl: TPixieElement;
begin
  Result := FElement;
end;

function TPixieRenderItem.Css: TPixieCssProperties;
begin
  Result := FElement.Css;
end;

procedure TPixieRenderItem.AddChild(Ri: TPixieRenderItem);
begin
  FChildren.Add(Ri);
  Ri.FParent := Self;
end;

function TPixieRenderItem.IsRoot: Boolean;
begin
  Result := FParent = nil;
end;

function TPixieRenderItem.CalcPlacement(AX, AY: TPixiePixel): TPixiePosition;
begin
  Result := FPos;
  Result.X := Result.X + AX - GetScrollLeft;
  Result.Y := Result.Y + AY - GetScrollTop;
end;

// --- Outer box accessors ---

function TPixieRenderItem.Left: TPixiePixel;
begin
  Result := FPos.X - FMargins.Left - FPadding.Left - FBorders.Left;
end;

function TPixieRenderItem.Right: TPixiePixel;
begin
  Result := Left + Width;
end;

function TPixieRenderItem.Top: TPixiePixel;
begin
  Result := FPos.Y - FMargins.Top - FPadding.Top - FBorders.Top;
end;

function TPixieRenderItem.Bottom: TPixiePixel;
begin
  Result := Top + Height;
end;

function TPixieRenderItem.Width: TPixiePixel;
begin
  Result := FPos.Width + FMargins.Width + FPadding.Width + FBorders.Width;
end;

function TPixieRenderItem.Height: TPixiePixel;
begin
  Result := FPos.Height + FMargins.Height + FPadding.Height + FBorders.Height;
end;

// --- Padding ---

function TPixieRenderItem.PaddingLeft: TPixiePixel;
begin
  Result := FPadding.Left;
end;

function TPixieRenderItem.PaddingRight: TPixiePixel;
begin
  Result := FPadding.Right;
end;

function TPixieRenderItem.PaddingTop: TPixiePixel;
begin
  Result := FPadding.Top;
end;

function TPixieRenderItem.PaddingBottom: TPixiePixel;
begin
  Result := FPadding.Bottom;
end;

// --- Borders ---

function TPixieRenderItem.BorderLeft: TPixiePixel;
begin
  Result := FBorders.Left;
end;

function TPixieRenderItem.BorderRight: TPixiePixel;
begin
  Result := FBorders.Right;
end;

function TPixieRenderItem.BorderTop: TPixiePixel;
begin
  Result := FBorders.Top;
end;

function TPixieRenderItem.BorderBottom: TPixiePixel;
begin
  Result := FBorders.Bottom;
end;

// --- Margins ---

function TPixieRenderItem.MarginLeft: TPixiePixel;
begin
  Result := FMargins.Left;
end;

function TPixieRenderItem.MarginRight: TPixiePixel;
begin
  Result := FMargins.Right;
end;

function TPixieRenderItem.MarginTop: TPixiePixel;
begin
  Result := FMargins.Top;
end;

function TPixieRenderItem.MarginBottom: TPixiePixel;
begin
  Result := FMargins.Bottom;
end;

// --- Record access ---

function TPixieRenderItem.GetMargins: TPixieMargins;
begin
  Result := FMargins;
end;

function TPixieRenderItem.GetPaddings: TPixieMargins;
begin
  Result := FPadding;
end;

procedure TPixieRenderItem.SetPaddings(const Value: TPixieMargins);
begin
  FPadding := Value;
end;

function TPixieRenderItem.GetBorders: TPixieMargins;
begin
  Result := FBorders;
end;

// --- Content offset ---

function TPixieRenderItem.ContentOffsetTop: TPixiePixel;
begin
  Result := FMargins.Top + FPadding.Top + FBorders.Top;
end;

function TPixieRenderItem.ContentOffsetBottom: TPixiePixel;
begin
  Result := FMargins.Bottom + FPadding.Bottom + FBorders.Bottom;
end;

function TPixieRenderItem.ContentOffsetLeft: TPixiePixel;
begin
  Result := FMargins.Left + FPadding.Left + FBorders.Left;
end;

function TPixieRenderItem.ContentOffsetRight: TPixiePixel;
begin
  Result := FMargins.Right + FPadding.Right + FBorders.Right;
end;

function TPixieRenderItem.ContentOffsetWidth: TPixiePixel;
begin
  Result := ContentOffsetLeft + ContentOffsetRight;
end;

function TPixieRenderItem.ContentOffsetHeight: TPixiePixel;
begin
  Result := ContentOffsetTop + ContentOffsetBottom;
end;

function TPixieRenderItem.GetIntrinsicMinWidth: TPixiePixel;
begin
  if FIntrinsicMinWidth > 0 then
    Result := FIntrinsicMinWidth
  else
    Result := FPos.Width;
end;

// --- Render offset (box-sizing aware) ---

function TPixieRenderItem.RenderOffsetLeft: TPixiePixel;
begin
  if Css.BoxSizing = bxContentBox then
    Result := FMargins.Left + FBorders.Left + FPadding.Left
  else
    Result := FMargins.Left;
end;

function TPixieRenderItem.RenderOffsetRight: TPixiePixel;
begin
  if Css.BoxSizing = bxContentBox then
    Result := FMargins.Right + FBorders.Right + FPadding.Right
  else
    Result := FMargins.Right;
end;

function TPixieRenderItem.RenderOffsetWidth: TPixiePixel;
begin
  Result := RenderOffsetLeft + RenderOffsetRight;
end;

function TPixieRenderItem.RenderOffsetTop: TPixiePixel;
begin
  if Css.BoxSizing = bxContentBox then
    Result := FMargins.Top + FBorders.Top + FPadding.Top
  else
    Result := FMargins.Top;
end;

function TPixieRenderItem.RenderOffsetBottom: TPixiePixel;
begin
  if Css.BoxSizing = bxContentBox then
    Result := FMargins.Bottom + FBorders.Bottom + FPadding.Bottom
  else
    Result := FMargins.Bottom;
end;

function TPixieRenderItem.RenderOffsetHeight: TPixiePixel;
begin
  Result := RenderOffsetTop + RenderOffsetBottom;
end;

// --- Box sizing adjustment ---

function TPixieRenderItem.BoxSizingLeft: TPixiePixel;
begin
  if Css.BoxSizing = bxBorderBox then
    Result := FPadding.Left + FBorders.Left
  else
    Result := 0;
end;

function TPixieRenderItem.BoxSizingRight: TPixiePixel;
begin
  if Css.BoxSizing = bxBorderBox then
    Result := FPadding.Right + FBorders.Right
  else
    Result := 0;
end;

function TPixieRenderItem.BoxSizingWidth: TPixiePixel;
begin
  Result := BoxSizingLeft + BoxSizingRight;
end;

function TPixieRenderItem.BoxSizingTop: TPixiePixel;
begin
  if Css.BoxSizing = bxBorderBox then
    Result := FPadding.Top + FBorders.Top
  else
    Result := 0;
end;

function TPixieRenderItem.BoxSizingBottom: TPixiePixel;
begin
  if Css.BoxSizing = bxBorderBox then
    Result := FPadding.Bottom + FBorders.Bottom
  else
    Result := 0;
end;

function TPixieRenderItem.BoxSizingHeight: TPixiePixel;
begin
  Result := BoxSizingTop + BoxSizingBottom;
end;

// --- Collapse / visibility helpers ---

function TPixieRenderItem.CollapseTopMargin: Boolean;
begin
  Result := (FBorders.Top = 0) and
            (FPadding.Top = 0) and
            FElement.InNormalFlow and
            (FElement.Css.Float_ = efNone) and
            (FMargins.Top >= 0) and
            (not IsFlexItem) and
            (not IsGridItem) and
            (not IsRoot) and
            (not (Css.Overflow in [ovHidden, ovScroll, ovAuto]));
end;

function TPixieRenderItem.CollapseBottomMargin: Boolean;
begin
  Result := (FBorders.Bottom = 0) and
            (FPadding.Bottom = 0) and
            FElement.InNormalFlow and
            (FElement.Css.Float_ = efNone) and
            (FMargins.Bottom >= 0) and
            (not IsRoot) and
            (not (Css.Overflow in [ovHidden, ovScroll, ovAuto]));
end;

function TPixieRenderItem.IsVisible: Boolean;
begin
  Result := not (FSkip or
    (FElement.Css.Display = displayNone) or
    (FElement.Css.Visibility <> visVisible));
end;

function TPixieRenderItem.IsFlexItem: Boolean;
var
  Par: TPixieRenderItem;
begin
  Par := FParent;
  if (Par <> nil) and
     (Par.Css.Display in [displayInlineFlex, displayFlex]) then
    Exit(True);
  Result := False;
end;

function TPixieRenderItem.IsGridItem: Boolean;
var
  Par: TPixieRenderItem;
begin
  Par := FParent;
  if (Par <> nil) and
     (Par.Css.Display in [displayGrid, displayInlineGrid]) then
    Exit(True);
  Result := False;
end;

// --- Core render pipeline ---

function TPixieRenderItem.Render(X, Y: TPixiePixel;
  const CbContext: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext; SecondPass: Boolean): TPixiePixel;
var
  CLeft, CTop: TPixiePixel;
  Fmt: TPixieFormattingContext;
begin
  // CSS Sizing 3: percentages on margin/padding/border resolve to zero
  // during intrinsic (min/max-content) sizing. In SizeModeExact*
  // CbContext.Width holds the element's own exact size (not the parent
  // CB width), so re-resolving percentages against it would use the
  // wrong base; preserve the values computed during the prior non-exact
  // pass that set them from the actual parent CB.
  if (CbContext.SizeMode and SizeModeContent) <> 0 then
    CalcOutlines(0)
  else if (CbContext.SizeMode and SizeModeExactEither) = 0 then
    CalcOutlines(CbContext.Width.Value);

  FPos.Clear;
  FPos.MoveTo(X, Y);
  FRelShiftDone := False;

  CLeft := ContentOffsetLeft;
  CTop := ContentOffsetTop;

  FPos.X := FPos.X + CLeft;
  FPos.Y := FPos.Y + CTop;

  if FElement.IsBlockFormattingContext or (FmtCtx = nil) then
  begin
    Fmt := TPixieFormattingContext.Create;
    try
      Result := _Render(X, Y, CbContext, Fmt, SecondPass);
      Fmt.ApplyRelativeShift(CbContext);
    finally
      Fmt.Free;
    end;
  end
  else
  begin
    FmtCtx.PushPosition(X + CLeft, Y + CTop);
    Result := _Render(X, Y, CbContext, FmtCtx, SecondPass);
    FmtCtx.PopPosition(X + CLeft, Y + CTop);
  end;
end;

function TPixieRenderItem._Render(X, Y: TPixiePixel;
  const CbContext: TPixieContainingBlockContext;
  FmtCtx: TPixieFormattingContext; SecondPass: Boolean): TPixiePixel;
begin
  Result := 0;
end;

procedure TPixieRenderItem.CalcOutlines(ParentWidth: TPixiePixel);
begin
  FPadding.Left   := FElement.Css.CssPadding.Left.CalcPercent(ParentWidth);
  FPadding.Right  := FElement.Css.CssPadding.Right.CalcPercent(ParentWidth);

  FBorders.Left   := FElement.Css.CssBorders.Left.Width.CalcPercent(ParentWidth);
  FBorders.Right  := FElement.Css.CssBorders.Right.Width.CalcPercent(ParentWidth);

  FMargins.Left   := FElement.Css.CssMargins.Left.CalcPercent(ParentWidth);
  FMargins.Right  := FElement.Css.CssMargins.Right.CalcPercent(ParentWidth);

  FMargins.Top    := FElement.Css.CssMargins.Top.CalcPercent(ParentWidth);
  FMargins.Bottom := FElement.Css.CssMargins.Bottom.CalcPercent(ParentWidth);

  // CSS spec: margins do not apply to table-internal elements
  if FElement.Css.Display in [displayTableCell, displayTableRow,
     displayTableRowGroup, displayTableHeaderGroup,
     displayTableFooterGroup, displayTableColumn,
     displayTableColumnGroup] then
    FMargins.Init;

  FPadding.Top    := FElement.Css.CssPadding.Top.CalcPercent(ParentWidth);
  FPadding.Bottom := FElement.Css.CssPadding.Bottom.CalcPercent(ParentWidth);
end;

function TPixieRenderItem.CalcAutoMargins(ParentWidth: TPixiePixel): TPixiePixel;
var
  ElWidth, Remaining: TPixiePixel;
  CenterByParent: Boolean;
  ParentAlign: TPixieTextAlign;
begin
  Result := 0;
  if (FElement.Css.Display in [displayBlock, displayTable,
      displayFlex, displayInlineFlex,
      displayGrid, displayInlineGrid,
      displayFlowRoot]) and
     (FElement.Css.ElPosition <> epAbsolute) and
     (FElement.Css.Float_ = efNone) then
  begin
    // Browsers use -webkit-center / -webkit-left / -webkit-right to
    // align block children when align="center/left/right" is used on
    // a parent block element.
    if FElement.Parent <> nil then
      ParentAlign := FElement.Parent.Css.TextAlign
    else
      ParentAlign := taLeft;
    CenterByParent := ParentAlign in
      [taBlockCenter, taBlockLeft, taBlockRight];
    if (FElement.Css.CssMargins.Left.IsPredefined and
       FElement.Css.CssMargins.Right.IsPredefined) or CenterByParent then
    begin
      ElWidth := FPos.Width + FBorders.Left + FBorders.Right +
        FPadding.Left + FPadding.Right;
      if CenterByParent and (ParentAlign in [taBlockLeft, taBlockRight]) then
      begin
        if ElWidth <= ParentWidth then
          Remaining := ParentWidth - ElWidth
        else
          Remaining := 0;
        if ParentAlign = taBlockRight then
        begin
          FMargins.Left := Remaining;
          FMargins.Right := 0;
        end
        else
        begin
          FMargins.Left := 0;
          FMargins.Right := Remaining;
        end;
      end
      else if ElWidth <= ParentWidth then
      begin
        FMargins.Left := (ParentWidth - ElWidth) / 2;
        FMargins.Right := (ParentWidth - ElWidth) - FMargins.Left;
      end
      else
      begin
        FMargins.Left := 0;
        FMargins.Right := 0;
      end;
      Result := FMargins.Left;
    end
    else if FElement.Css.CssMargins.Left.IsPredefined and
            (not FElement.Css.CssMargins.Right.IsPredefined) then
    begin
      ElWidth := FPos.Width + FBorders.Left + FBorders.Right +
        FPadding.Left + FPadding.Right + FMargins.Right;
      FMargins.Left := ParentWidth - ElWidth;
      if FMargins.Left < 0 then
        FMargins.Left := 0;
      Result := FMargins.Left;
    end
    else if (not FElement.Css.CssMargins.Left.IsPredefined) and
            FElement.Css.CssMargins.Right.IsPredefined then
    begin
      ElWidth := FPos.Width + FBorders.Left + FBorders.Right +
        FPadding.Left + FPadding.Right + FMargins.Left;
      FMargins.Right := ParentWidth - ElWidth;
      if FMargins.Right < 0 then
        FMargins.Right := 0;
    end;
  end;
end;

procedure TPixieRenderItem.GetRelativeOffset(
  const CbContext: TPixieContainingBlockContext;
  out DX, DY: TPixiePixel);
var
  Offsets: TPixieCssOffsets;
begin
  DX := 0;
  DY := 0;
  if FElement.Css.ElPosition <> epRelative then Exit;

  Offsets := FElement.Css.CssOffsets;
  if not Offsets.Left.IsPredefined then
    DX := Offsets.Left.CalcPercent(CbContext.Width.Value)
  else if not Offsets.Right.IsPredefined then
    DX := -Offsets.Right.CalcPercent(CbContext.Width.Value);

  if not Offsets.Top.IsPredefined then
    DY := Offsets.Top.CalcPercent(CbContext.Height.Value)
  else if not Offsets.Bottom.IsPredefined then
    DY := -Offsets.Bottom.CalcPercent(CbContext.Height.Value);
end;

procedure TPixieRenderItem.ApplyRelativeShift(
  const CbContext: TPixieContainingBlockContext);
var
  DX, DY: TPixiePixel;
begin
  if FRelShiftDone then Exit;
  if FElement.Css.ElPosition = epRelative then
  begin
    GetRelativeOffset(CbContext, DX, DY);
    FPos.X := FPos.X + DX;
    FPos.Y := FPos.Y + DY;
    FRelShiftDone := True;
  end;
end;

function TPixieRenderItem.BuildTransformMatrix(BaseX, BaseY: TPixiePixel;
  out M: TPixieMatrix): Boolean;
var
  Doc: TPixieDocument;
  Ops: TPixieTransformOps;
  Fm: TPixieFontMetrics;
  BorderW, BorderH, OriginX, OriginY, TX, TY: TPixiePixel;
  I: Integer;
  Cur, MOp: TPixieMatrix;
begin
  Result := False;
  Ops := FElement.Css.TransformOps;
  if Length(Ops) = 0 then Exit;

  Assert(FElement.GetDocument is TPixieDocument);
  Doc := TPixieDocument(FElement.GetDocument);
  Fm := FElement.Css.FontMetrics;

  BorderW := FPos.Width + FPadding.Left + FPadding.Right +
    FBorders.Left + FBorders.Right;
  BorderH := FPos.Height + FPadding.Top + FPadding.Bottom +
    FBorders.Top + FBorders.Bottom;

  // transform-origin in draw coordinates (border-box top-left + resolved origin)
  OriginX := BaseX + FPos.X - FPadding.Left - FBorders.Left +
    Doc.ToPixels(FElement.Css.TransformOriginX, Fm, BorderW);
  OriginY := BaseY + FPos.Y - FPadding.Top - FBorders.Top +
    Doc.ToPixels(FElement.Css.TransformOriginY, Fm, BorderH);

  Cur := TPixieMatrix.Identity;
  for I := 0 to High(Ops) do
  begin
    case Ops[I].Func of
      ptfTranslate:
      begin
        TX := Doc.ToPixels(Ops[I].LenX, Fm, BorderW);
        TY := Doc.ToPixels(Ops[I].LenY, Fm, BorderH);
        Cur := Cur.Multiply(TPixieMatrix.CreateTranslate(TX, TY));
      end;
      ptfScale:
        Cur := Cur.Multiply(TPixieMatrix.CreateScale(Ops[I].Num[0], Ops[I].Num[1]));
      ptfRotate:
        Cur := Cur.Multiply(TPixieMatrix.CreateRotate(Ops[I].Num[0]));
      ptfSkew:
        Cur := Cur.Multiply(TPixieMatrix.CreateSkew(Ops[I].Num[0], Ops[I].Num[1]));
      ptfMatrix:
      begin
        MOp.A := Ops[I].Num[0]; MOp.B := Ops[I].Num[1]; MOp.C := Ops[I].Num[2];
        MOp.D := Ops[I].Num[3]; MOp.E := Ops[I].Num[4]; MOp.F := Ops[I].Num[5];
        Cur := Cur.Multiply(MOp);
      end;
    end;
  end;

  M := TPixieMatrix.CreateTranslate(OriginX, OriginY).Multiply(Cur).Multiply(
    TPixieMatrix.CreateTranslate(-OriginX, -OriginY));
  Result := True;
end;

procedure TPixieRenderItem.MapPointInverse(var X, Y: TPixiePixel);
var
  M, Inv: TPixieMatrix;
  OX, OY: Single;
begin
  if not BuildTransformMatrix(0, 0, M) then Exit;
  if not M.Invert(Inv) then
  begin
    // Non-invertible (e.g. scale(0)): the element collapses to zero area, so
    // move the point far out of range — nothing in its subtree is hittable.
    X := -1e20;
    Y := -1e20;
    Exit;
  end;
  Inv.Apply(X, Y, OX, OY);
  X := OX;
  Y := OY;
end;

// --- Split inlines ---

function TPixieRenderItem.SplitInlines: TPixieSplitResult;
var
  I, J: Integer;
  Child: TPixieRenderItem;
  ChildSplit: TPixieSplitResult;
  Found: Boolean;
begin
  Result.Before := nil;
  Result.Block := nil;
  Result.After := nil;

  for I := 0 to FChildren.Count - 1 do
  begin
    Child := FChildren[I];

    // Direct block child in inline context?
    if Child.SrcEl.IsBlockBox and (Child.SrcEl.Css.Float_ = efNone) and
       (not (Child.SrcEl.Css.ElPosition in [epAbsolute, epFixed])) then
    begin
      Result.Before := Clone;
      Result.Block := Child;
      Result.After := Clone;

      Assert(TObject(Result.Before) is TPixieRenderItem);
      Assert(TObject(Result.Block) is TPixieRenderItem);
      Assert(TObject(Result.After) is TPixieRenderItem);
      TPixieRenderItem(Result.Block).FParent := TPixieRenderItem(Result.Before);
      TPixieRenderItem(Result.After).FParent := TPixieRenderItem(Result.Before);

      Found := False;
      for J := 0 to FChildren.Count - 1 do
      begin
        if FChildren[J] = Child then
        begin
          Found := True;
          Continue;
        end;
        if not Found then
          TPixieRenderItem(Result.Before).AddChild(FChildren[J])
        else
          TPixieRenderItem(Result.After).AddChild(FChildren[J]);
      end;
      Exit;
    end;

    // Recurse into inline children only (block/float children handle their own layout)
    if (Child.FChildren.Count > 0) and (Child.SrcEl.Css.Display = displayInline) then
    begin
      ChildSplit := Child.SplitInlines;
      if ChildSplit.Before <> nil then
      begin
        Result.Before := Clone;
        Result.Block := ChildSplit.Block;
        Result.After := Clone;

        Assert(TObject(Result.Before) is TPixieRenderItem);
        Assert(TObject(Result.After) is TPixieRenderItem);
        Assert(TObject(ChildSplit.Before) is TPixieRenderItem);
        Assert(TObject(ChildSplit.After) is TPixieRenderItem);
        TPixieRenderItem(Result.After).FParent := TPixieRenderItem(Result.Before);

        Found := False;
        for J := 0 to FChildren.Count - 1 do
        begin
          if FChildren[J] = Child then
          begin
            Found := True;
            Continue;
          end;
          if not Found then
            TPixieRenderItem(Result.Before).AddChild(FChildren[J])
          else
            TPixieRenderItem(Result.After).AddChild(FChildren[J]);
        end;
        TPixieRenderItem(Result.Before).AddChild(
          TPixieRenderItem(ChildSplit.Before));
        TPixieRenderItem(Result.After).AddChild(
          TPixieRenderItem(ChildSplit.After));
        Exit;
      end;
    end;
  end;
end;

// --- Positioned elements ---

function TPixieRenderItem.FetchPositioned: Boolean;
var
  I: Integer;
  El: TPixieRenderItem;
  ElPos: TPixieElementPosition;
begin
  Result := False;
  if FPositioned <> nil then
    FPositioned.Clear;

  for I := 0 to FChildren.Count - 1 do
  begin
    El := FChildren[I];
    ElPos := El.SrcEl.Css.ElPosition;
    El.FLayoutPositioned := ElPos <> epStatic;
    if El.FLayoutPositioned then
      AddPositioned(El);
    if (not Result) and (ElPos in [epAbsolute, epFixed]) then
      Result := True;
    if El.FetchPositioned then
      Result := True;
  end;
end;

procedure TPixieRenderItem.AddPositioned(El: TPixieRenderItem);
var
  ElParent: TPixieRenderItem;
begin
  if (FElement.Css.ElPosition <> epStatic) or IsRoot then
  begin
    if FPositioned = nil then
      FPositioned := TPixieRenderItemVector.Create;
    FPositioned.Add(El);
  end
  else
  begin
    ElParent := FParent;
    if ElParent <> nil then
      ElParent.AddPositioned(El);
  end;
end;

function TPixieRenderItem.ElementStaticOffset(
  El: TPixieRenderItem): TPixiePointF;
var
  OffsetX, OffsetY: TPixiePixel;
  CurEl, ThisEl: TPixieRenderItem;
  Doc: TPixieDocument;
begin
  OffsetX := 0;
  OffsetY := 0;

  if El.Css.ElPosition <> epFixed then
    ThisEl := Self
  else
  begin
    Assert(FElement.GetDocument is TPixieDocument);
    Doc := TPixieDocument(FElement.GetDocument);
    Assert(TObject(Doc.RootRender) is TPixieRenderItem);
    ThisEl := TPixieRenderItem(Doc.RootRender);
  end;

  CurEl := El.FParent;
  while (CurEl <> nil) and (CurEl <> ThisEl) do
  begin
    OffsetX := OffsetX + CurEl.FPos.X;
    OffsetY := OffsetY + CurEl.FPos.Y;
    CurEl := CurEl.FParent;
  end;

  if (El.Css.ElPosition = epFixed) or
     (IsRoot and (not FElement.IsPositioned)) then
  begin
    if ThisEl <> nil then
    begin
      OffsetX := OffsetX + ThisEl.FPos.X;
      OffsetY := OffsetY + ThisEl.FPos.Y;
    end;
  end
  else
  begin
    OffsetX := OffsetX + FPadding.Left;
    OffsetY := OffsetY + FPadding.Top;
  end;

  Result.X := OffsetX;
  Result.Y := OffsetY;
end;

// Helper for RenderPositioned: clamp height by min/max
function FixHeightMinMax(El: TPixieRenderItem;
  AHeight, CbHeight: TPixiePixel): TPixiePixel;
var
  MaxH, MinH, Val: TPixieCssLength;
begin
  Result := AHeight;
  MaxH := El.Css.CssMaxHeight;
  MinH := El.Css.CssMinHeight;
  if not MaxH.IsPredefined then
  begin
    Val := MaxH;
    if Result > Val.CalcPercent(CbHeight) then
      Result := Val.CalcPercent(CbHeight);
  end;
  if not MinH.IsPredefined then
  begin
    Val := MinH;
    if Result < Val.CalcPercent(CbHeight) then
      Result := Val.CalcPercent(CbHeight);
  end;
  Result := Result + El.ContentOffsetHeight;
end;

// Helper for RenderPositioned: clamp width by min/max
function FixWidthMinMax(El: TPixieRenderItem;
  AWidth, CbWidth: TPixiePixel): TPixiePixel;
var
  MaxW, MinW, Val: TPixieCssLength;
begin
  Result := AWidth;
  MaxW := El.Css.CssMaxWidth;
  MinW := El.Css.CssMinWidth;
  if not MaxW.IsPredefined then
  begin
    Val := MaxW;
    if Result > Val.CalcPercent(CbWidth) then
      Result := Val.CalcPercent(CbWidth);
  end;
  if not MinW.IsPredefined then
  begin
    Val := MinW;
    if Result < Val.CalcPercent(CbWidth) then
      Result := Val.CalcPercent(CbWidth);
  end;
  Result := Result + El.ContentOffsetWidth;
end;

procedure TPixieRenderItem.RenderPositioned(Rt: TPixieRenderType);
var
  Viewport: TPixiePosition;
  Doc: TPixieDocument;
  Cont: TPixieContainer;
  I, J, Divider: Integer;
  El: TPixieRenderItem;
  ElPosition: TPixieElementPosition;
  Process, NeedRender: Boolean;
  CbSize: TPixieContainingBlockContext;
  CssLeft, CssRight, CssTop, CssBottom: TPixieCssLength;
  ElWidth, ElHeight: TPixieCssLength;
  ElBottom, ElTop, ElH: TPixiePixel;
  ElRight, ElLeft, ElW: TPixiePixel;
  StaticOff: TPixiePointF;
  ElStaticX, ElStaticY: TPixiePixel;
  Remained: TPixiePixel;
  SavedPos: TPixiePosition;
  FixedPos: TPixiePosition;
begin
  Assert(FElement.GetDocument is TPixieDocument);
  Doc := TPixieDocument(FElement.GetDocument);
  Cont := Doc.Container;
  Cont.GetViewport(Viewport);

  if FPositioned = nil then
    Exit;
  for I := 0 to FPositioned.Count - 1 do
  begin
    El := FPositioned[I];
    ElPosition := El.SrcEl.Css.ElPosition;

    Process := False;
    if El.SrcEl.Css.Display <> displayNone then
    begin
      if ElPosition = epAbsolute then
      begin
        if Rt <> rtFixedOnly then
          Process := True;
      end
      else if ElPosition = epFixed then
      begin
        if Rt <> rtNoFixed then
          Process := True;
      end;
    end;

    if Process then
    begin
      CbSize.Init;
      if (ElPosition = epFixed) or
         (IsRoot and (not FElement.IsPositioned)) then
      begin
        CbSize.Height.Value := Viewport.Height;
        CbSize.Width.Value := Viewport.Width;
      end
      else
      begin
        CbSize.Height.Value := FPos.Height + FPadding.Height;
        CbSize.Width.Value := FPos.Width + FPadding.Width;
      end;

      CssLeft   := El.SrcEl.Css.CssOffsets.Left;
      CssRight  := El.SrcEl.Css.CssOffsets.Right;
      CssTop    := El.SrcEl.Css.CssOffsets.Top;
      CssBottom := El.SrcEl.Css.CssOffsets.Bottom;

      NeedRender := False;

      ElWidth  := El.SrcEl.Css.CssWidth;
      ElHeight := El.SrcEl.Css.CssHeight;

      StaticOff := ElementStaticOffset(El);
      ElStaticX := El.FPos.X + StaticOff.X;
      ElStaticY := El.FPos.Y + StaticOff.Y;

      // --- Vertical position (CSS 2.2 §10.6.4) ---
      if CssTop.IsPredefined and (not CssBottom.IsPredefined) and
         ElHeight.IsPredefined then
      begin
        // Case 1: top+height auto, bottom not auto
        if El.Css.CssMargins.Top.IsPredefined then El.FMargins.Top := 0;
        if El.Css.CssMargins.Bottom.IsPredefined then El.FMargins.Bottom := 0;
        ElH := El.Height;
        ElBottom := CssBottom.CalcPercent(CbSize.Height.Value);
        ElTop := CbSize.Height.Value - ElH - ElBottom;
      end
      else if CssTop.IsPredefined and CssBottom.IsPredefined and
              (not ElHeight.IsPredefined) then
      begin
        // Case 2: top+bottom auto, height not auto
        if El.Css.CssMargins.Top.IsPredefined then El.FMargins.Top := 0;
        if El.Css.CssMargins.Bottom.IsPredefined then El.FMargins.Bottom := 0;
        ElTop := ElStaticY - El.ContentOffsetTop;
        ElH := FixHeightMinMax(El,
          ElHeight.CalcPercent(CbSize.Height.Value), CbSize.Height.Value);
      end
      else if (not CssTop.IsPredefined) and CssBottom.IsPredefined and
              ElHeight.IsPredefined then
      begin
        // Case 3: height+bottom auto, top not auto
        if El.Css.CssMargins.Top.IsPredefined then El.FMargins.Top := 0;
        if El.Css.CssMargins.Bottom.IsPredefined then El.FMargins.Bottom := 0;
        ElH := El.Height;
        ElTop := CssTop.CalcPercent(CbSize.Height.Value);
      end
      else if CssTop.IsPredefined and (not CssBottom.IsPredefined) and
              (not ElHeight.IsPredefined) then
      begin
        // Case 4: top auto, height+bottom not auto
        if El.Css.CssMargins.Top.IsPredefined then El.FMargins.Top := 0;
        if El.Css.CssMargins.Bottom.IsPredefined then El.FMargins.Bottom := 0;
        ElH := FixHeightMinMax(El,
          ElHeight.CalcPercent(CbSize.Height.Value), CbSize.Height.Value);
        ElBottom := CssBottom.CalcPercent(CbSize.Height.Value);
        ElTop := CbSize.Height.Value - ElH - ElBottom;
      end
      else if (not CssTop.IsPredefined) and (not CssBottom.IsPredefined) and
              ElHeight.IsPredefined then
      begin
        // Case 5: height auto, top+bottom not auto
        if El.Css.CssMargins.Top.IsPredefined then El.FMargins.Top := 0;
        if El.Css.CssMargins.Bottom.IsPredefined then El.FMargins.Bottom := 0;
        ElBottom := CssBottom.CalcPercent(CbSize.Height.Value);
        ElTop := CssTop.CalcPercent(CbSize.Height.Value);
        if El.SrcEl.IsReplaced then
        begin
          ElH := El.Height - El.ContentOffsetHeight;
          Remained := (CbSize.Height.Value - ElTop - ElBottom) -
            ElH - El.ContentOffsetHeight;
          if Remained > 0 then
          begin
            Divider := 0;
            if El.Css.CssMargins.Top.IsPredefined then Inc(Divider);
            if El.Css.CssMargins.Bottom.IsPredefined then Inc(Divider);
            if Divider <> 0 then
            begin
              if El.Css.CssMargins.Top.IsPredefined then
                El.FMargins.Top := Remained / Divider;
              if El.Css.CssMargins.Bottom.IsPredefined then
                El.FMargins.Bottom := Remained / Divider;
            end;
          end;
          ElH := ElH + El.ContentOffsetHeight;
        end
        else
          ElH := CbSize.Height.Value - ElTop - ElBottom;

        if not El.Css.CssMaxHeight.IsPredefined then
        begin
          if ElH - El.ContentOffsetHeight >
             El.Css.CssMaxHeight.CalcPercent(CbSize.Height.Value) then
          begin
            Remained := ElH - El.ContentOffsetHeight -
              El.Css.CssMaxHeight.CalcPercent(CbSize.Height.Value);
            ElH := El.Css.CssMaxHeight.CalcPercent(CbSize.Height.Value);
            Divider := 0;
            if El.Css.CssMargins.Top.IsPredefined then Inc(Divider);
            if El.Css.CssMargins.Bottom.IsPredefined then Inc(Divider);
            if Divider <> 0 then
            begin
              if El.Css.CssMargins.Top.IsPredefined then
                El.FMargins.Top := Remained / Divider;
              if El.Css.CssMargins.Bottom.IsPredefined then
                El.FMargins.Bottom := Remained / Divider;
            end;
            ElH := ElH + El.ContentOffsetHeight;
          end;
        end;
      end
      else if (not CssTop.IsPredefined) and CssBottom.IsPredefined and
              (not ElHeight.IsPredefined) then
      begin
        // Case 6: bottom auto, top+height not auto
        if El.Css.CssMargins.Top.IsPredefined then El.FMargins.Top := 0;
        if El.Css.CssMargins.Bottom.IsPredefined then El.FMargins.Bottom := 0;
        ElH := FixHeightMinMax(El,
          ElHeight.CalcPercent(CbSize.Height.Value), CbSize.Height.Value);
        ElTop := CssTop.CalcPercent(CbSize.Height.Value);
      end
      else if CssTop.IsPredefined and CssBottom.IsPredefined and
              ElHeight.IsPredefined then
      begin
        // All three auto
        if El.Css.CssMargins.Top.IsPredefined then El.FMargins.Top := 0;
        if El.Css.CssMargins.Bottom.IsPredefined then El.FMargins.Bottom := 0;
        ElH := El.Height;
        ElTop := ElStaticY - El.ContentOffsetTop;
      end
      else
      begin
        // None auto
        ElH := FixHeightMinMax(El,
          ElHeight.CalcPercent(CbSize.Height.Value), CbSize.Height.Value);
        ElTop := CssTop.CalcPercent(CbSize.Height.Value);
        ElBottom := CssBottom.CalcPercent(CbSize.Height.Value);
        Remained := CbSize.Height.Value - ElH - ElTop - ElBottom;

        if El.Css.CssMargins.Top.IsPredefined and
           El.Css.CssMargins.Bottom.IsPredefined then
        begin
          El.FMargins.Top := Remained / 2;
          El.FMargins.Bottom := Remained / 2;
          ElH := ElH + El.FMargins.Top + El.FMargins.Bottom;
        end
        else
        begin
          if El.Css.CssMargins.Top.IsPredefined then
          begin
            El.FMargins.Top := Remained;
            ElH := ElH + El.FMargins.Top;
          end;
          if El.Css.CssMargins.Bottom.IsPredefined then
          begin
            El.FMargins.Bottom := Remained;
            ElH := ElH + El.FMargins.Bottom;
          end;
        end;
      end;

      El.FPos.Y := ElTop + El.ContentOffsetTop;
      if El.FPos.Height <> ElH - El.ContentOffsetHeight then
      begin
        El.FPos.Height := ElH - El.ContentOffsetHeight;
        NeedRender := True;
      end;

      // --- Horizontal position (CSS 2.2 §10.3.7) ---
      if CssLeft.IsPredefined and (not CssRight.IsPredefined) and
         ElWidth.IsPredefined then
      begin
        // Case 1
        if El.Css.CssMargins.Left.IsPredefined then El.FMargins.Left := 0;
        if El.Css.CssMargins.Right.IsPredefined then El.FMargins.Right := 0;
        ElW := El.Width;
        ElRight := CssRight.CalcPercent(CbSize.Width.Value);
        ElLeft := CbSize.Width.Value - ElW - ElRight;
      end
      else if CssLeft.IsPredefined and CssRight.IsPredefined and
              (not ElWidth.IsPredefined) then
      begin
        // Case 2
        if El.Css.CssMargins.Left.IsPredefined then El.FMargins.Left := 0;
        if El.Css.CssMargins.Right.IsPredefined then El.FMargins.Right := 0;
        ElLeft := ElStaticX - El.ContentOffsetLeft;
        ElW := FixWidthMinMax(El,
          ElWidth.CalcPercent(CbSize.Width.Value), CbSize.Width.Value);
      end
      else if (not CssLeft.IsPredefined) and CssRight.IsPredefined and
              ElWidth.IsPredefined then
      begin
        // Case 3
        if El.Css.CssMargins.Left.IsPredefined then El.FMargins.Left := 0;
        if El.Css.CssMargins.Right.IsPredefined then El.FMargins.Right := 0;
        ElW := El.Width;
        ElLeft := CssLeft.CalcPercent(CbSize.Width.Value);
      end
      else if CssLeft.IsPredefined and (not CssRight.IsPredefined) and
              (not ElWidth.IsPredefined) then
      begin
        // Case 4
        if El.Css.CssMargins.Left.IsPredefined then El.FMargins.Left := 0;
        if El.Css.CssMargins.Right.IsPredefined then El.FMargins.Right := 0;
        ElRight := CssRight.CalcPercent(CbSize.Width.Value);
        ElW := FixWidthMinMax(El,
          ElWidth.CalcPercent(CbSize.Width.Value), CbSize.Width.Value);
        ElLeft := CbSize.Width.Value - ElRight - ElW;
      end
      else if (not CssLeft.IsPredefined) and (not CssRight.IsPredefined) and
              ElWidth.IsPredefined then
      begin
        // Case 5
        if El.Css.CssMargins.Left.IsPredefined then El.FMargins.Left := 0;
        if El.Css.CssMargins.Right.IsPredefined then El.FMargins.Right := 0;
        ElLeft := CssLeft.CalcPercent(CbSize.Width.Value);
        ElRight := CssRight.CalcPercent(CbSize.Width.Value);
        if El.SrcEl.IsReplaced then
        begin
          ElW := El.Width - El.ContentOffsetWidth;
          Remained := (CbSize.Width.Value - ElLeft - ElRight) -
            ElW - El.ContentOffsetWidth;
          if Remained <> 0 then
          begin
            Divider := 0;
            if El.Css.CssMargins.Left.IsPredefined then Inc(Divider);
            if El.Css.CssMargins.Right.IsPredefined then Inc(Divider);
            if Divider <> 0 then
            begin
              if El.Css.CssMargins.Left.IsPredefined then
                El.FMargins.Left := Remained / Divider;
              if El.Css.CssMargins.Right.IsPredefined then
                El.FMargins.Right := Remained / Divider;
            end;
          end;
          ElW := ElW + El.ContentOffsetWidth;
        end
        else
          ElW := CbSize.Width.Value - ElLeft - ElRight;

        if not El.Css.CssMaxWidth.IsPredefined then
        begin
          if ElW - El.ContentOffsetWidth >
             El.Css.CssMaxWidth.CalcPercent(CbSize.Height.Value) then
          begin
            Remained := ElW - El.ContentOffsetWidth -
              El.Css.CssMaxWidth.CalcPercent(CbSize.Height.Value);
            ElW := El.Css.CssMaxWidth.CalcPercent(CbSize.Height.Value);
            Divider := 0;
            if El.Css.CssMargins.Left.IsPredefined then Inc(Divider);
            if El.Css.CssMargins.Right.IsPredefined then Inc(Divider);
            if Divider <> 0 then
            begin
              if El.Css.CssMargins.Left.IsPredefined then
                El.FMargins.Left := Remained / Divider;
              if El.Css.CssMargins.Right.IsPredefined then
                El.FMargins.Right := Remained / Divider;
            end;
            ElW := ElW + El.ContentOffsetWidth;
          end;
        end;
      end
      else if (not CssLeft.IsPredefined) and CssRight.IsPredefined and
              (not ElWidth.IsPredefined) then
      begin
        // Case 6
        if El.Css.CssMargins.Left.IsPredefined then El.FMargins.Left := 0;
        if El.Css.CssMargins.Right.IsPredefined then El.FMargins.Right := 0;
        ElLeft := CssLeft.CalcPercent(CbSize.Width.Value);
        ElW := FixWidthMinMax(El,
          ElWidth.CalcPercent(CbSize.Width.Value), CbSize.Width.Value);
      end
      else if CssLeft.IsPredefined and CssRight.IsPredefined and
              ElWidth.IsPredefined then
      begin
        // All three auto
        if El.Css.CssMargins.Left.IsPredefined then El.FMargins.Left := 0;
        if El.Css.CssMargins.Right.IsPredefined then El.FMargins.Right := 0;
        ElW := El.Width;
        ElLeft := ElStaticX - El.ContentOffsetLeft;
      end
      else
      begin
        // None auto
        ElW := FixWidthMinMax(El,
          ElWidth.CalcPercent(CbSize.Width.Value), CbSize.Width.Value);
        ElLeft := CssLeft.CalcPercent(CbSize.Width.Value);
        ElRight := CssRight.CalcPercent(CbSize.Width.Value);
        Remained := CbSize.Width.Value - ElW - ElLeft - ElRight;

        if El.Css.CssMargins.Left.IsPredefined and
           El.Css.CssMargins.Right.IsPredefined then
        begin
          El.FMargins.Left := Remained / 2;
          El.FMargins.Right := Remained / 2;
          if El.FMargins.Left < 0 then
          begin
            El.FMargins.Left := 0;
            El.FMargins.Right := Remained;
          end;
          ElW := ElW + El.FMargins.Left + El.FMargins.Right;
        end
        else
        begin
          if El.Css.CssMargins.Left.IsPredefined then
          begin
            El.FMargins.Left := Remained;
            ElW := ElW + El.FMargins.Left;
          end;
          if El.Css.CssMargins.Right.IsPredefined then
          begin
            El.FMargins.Right := Remained;
            ElW := ElW + El.FMargins.Right;
          end;
        end;
      end;

      El.FPos.X := ElLeft + El.ContentOffsetLeft;
      if El.FPos.Width <> ElW - El.ContentOffsetWidth then
      begin
        El.FPos.Width := ElW - El.ContentOffsetWidth;
        NeedRender := True;
      end;

      if ElPosition <> epFixed then
      begin
        El.FPos.X := El.FPos.X - StaticOff.X;
        El.FPos.Y := El.FPos.Y - StaticOff.Y;
      end;

      if NeedRender then
      begin
        SavedPos := El.FPos;
        El.Render(El.Left, El.Top,
          CbSize.NewWidthHeight(
            SavedPos.Width + El.BoxSizingWidth,
            SavedPos.Height + El.BoxSizingHeight,
            SizeModeExactWidth or SizeModeExactHeight), nil, True);
        El.FPos := SavedPos;
      end;

      if ElPosition = epFixed then
      begin
        FixedPos := El.Pos;
        El.GetRedrawBox(FixedPos);
        Doc.AddFixedBox(FixedPos);
      end;
    end;

    El.RenderPositioned;
  end;

  // Sort positioned by z-index (stable sort)
  if (FPositioned <> nil) and (FPositioned.Count > 1) then
  begin
    // Simple insertion sort (stable)
    for I := 1 to FPositioned.Count - 1 do
    begin
      J := I;
      while (J > 0) and
            (FPositioned[J].SrcEl.Css.ZIndex <
             FPositioned[J - 1].SrcEl.Css.ZIndex) do
      begin
        FPositioned.Exchange(J, J - 1);
        Dec(J);
      end;
    end;
  end;
end;

// --- Drawing ---

procedure TPixieRenderItem.DrawStackingContext(Hdc: PtrUInt;
  X, Y: TPixiePixel; Clip: PPixiePosition; WithPositioned: Boolean);
var
  I, Idx: Integer;
  ZIndexes: TPixieIntVector;
begin
  if not IsVisible then
    Exit;

  if WithPositioned and (FPositioned <> nil) then
  begin
    ZIndexes := TPixieIntVector.Create;
    try
      // Collect unique z-indexes
      for I := 0 to FPositioned.Count - 1 do
      begin
        Idx := FPositioned[I].SrcEl.Css.ZIndex;
        if ZIndexes.IndexOf(Idx) < 0 then
          ZIndexes.Add(Idx);
      end;
      ZIndexes.Sort;

      // Negative z-index positioned elements
      for I := 0 to ZIndexes.Count - 1 do
      begin
        if ZIndexes[I] < 0 then
          DrawChildren(Hdc, X, Y, Clip, dfPositioned, ZIndexes[I]);
      end;

      // Block children
      DrawChildren(Hdc, X, Y, Clip, dfBlock, 0);
      // Float children
      DrawChildren(Hdc, X, Y, Clip, dfFloats, 0);
      // Inline children
      DrawChildren(Hdc, X, Y, Clip, dfInlines, 0);

      // Zero z-index positioned elements
      for I := 0 to ZIndexes.Count - 1 do
      begin
        if ZIndexes[I] = 0 then
          DrawChildren(Hdc, X, Y, Clip, dfPositioned, ZIndexes[I]);
      end;

      // Positive z-index positioned elements
      for I := 0 to ZIndexes.Count - 1 do
      begin
        if ZIndexes[I] > 0 then
          DrawChildren(Hdc, X, Y, Clip, dfPositioned, ZIndexes[I]);
      end;
    finally
      ZIndexes.Free;
    end;
  end
  else
  begin
    DrawChildren(Hdc, X, Y, Clip, dfBlock, 0);
    DrawChildren(Hdc, X, Y, Clip, dfFloats, 0);
    DrawChildren(Hdc, X, Y, Clip, dfInlines, 0);
  end;
end;

procedure TPixieRenderItem.DrawChildren(Hdc: PtrUInt;
  X, Y: TPixiePixel; Clip: PPixiePosition; Flag: TPixieDrawFlag;
  ZIndex: Integer);
var
  ElPos, ClipBox, BorderBox: TPixiePosition;
  Doc: TPixieDocument;
  Cont: TPixieContainer;
  HasOpacity: Boolean;
  PseudoShiftX, PseudoShiftY: TPixiePixel;
  Offsets: TPixieCssOffsets;
  I: Integer;
  El: TPixieRenderItem;
  Process: Boolean;
  BdrRadius: TPixieBorderRadiuses;
  HasTfm: Boolean;
  TfMatrix: TPixieMatrix;
  TfBaseX, TfBaseY: TPixiePixel;
begin
  ElPos := FPos;
  ElPos.X := ElPos.X + X - GetScrollLeft;
  ElPos.Y := ElPos.Y + Y - GetScrollTop;

  Assert(FElement.GetDocument is TPixieDocument);
  Doc := TPixieDocument(FElement.GetDocument);
  Cont := Doc.Container;

  if ((FElement.Css.Overflow > ovVisible) or
      (FElement.Css.OverflowX > ovVisible)) and
     (FElement.Css.Display <> displayInline) then
  begin
    // The overflow clip edge is the padding box (CSS 2.1 §11.1.1), not the
    // content box. Include padding so content legitimately laid out in the
    // padding band is not clipped away — e.g. an absolutely positioned
    // descendant whose padding-box containing block places it at bottom/right.
    ClipBox := FPos;
    ClipBox.X := ClipBox.X + X;
    ClipBox.Y := ClipBox.Y + Y;
    ClipBox.AddMargins(FPadding);

    if FElement.Css.Overflow > ovVisible then
    begin
      // overflow / overflow-y clips both axes (rounded to border-radius)
      BorderBox := ClipBox;
      BorderBox.AddMargins(FBorders);

      BdrRadius := FElement.Css.CssBorders.Radius.CalcPercents(
        BorderBox.Width, BorderBox.Height);
      BdrRadius.SubMargins(FBorders);
    end
    else
    begin
      // overflow-x only: clip the horizontal axis, leave the vertical axis
      // effectively unbounded so taller content is not clipped.
      ClipBox.Y := ClipBox.Y - ClipUnboundedExtent;
      ClipBox.Height := ClipBox.Height + 2 * ClipUnboundedExtent;
      BdrRadius.Init;
    end;

    Cont.SetClip(ClipBox, BdrRadius);
  end;

  for I := 0 to FChildren.Count - 1 do
  begin
    El := FChildren[I];
    if El.IsVisible then
    begin
      // Apply visual relative shift for elements that became positioned
      // via pseudo-class (:active/:hover) without re-layout
      PseudoShiftX := 0;
      PseudoShiftY := 0;
      if (not El.FLayoutPositioned) and
         (El.SrcEl.Css.ElPosition = epRelative) then
      begin
        Offsets := El.SrcEl.Css.CssOffsets;
        if not Offsets.Left.IsPredefined then
          PseudoShiftX := Offsets.Left.Val
        else if not Offsets.Right.IsPredefined then
          PseudoShiftX := -Offsets.Right.Val;
        if not Offsets.Top.IsPredefined then
          PseudoShiftY := Offsets.Top.Val
        else if not Offsets.Bottom.IsPredefined then
          PseudoShiftY := -Offsets.Bottom.Val;
        El.FPos.X := El.FPos.X + PseudoShiftX;
        El.FPos.Y := El.FPos.Y + PseudoShiftY;
      end
      else if (El.SrcEl.Css.ElPosition = epSticky) and (Flag = dfPositioned) then
      begin
        // position:sticky — clamp the item against its inset and containing
        // block for the current scroll. ElPos is the parent content origin in
        // screen coords. Sticky items paint only on the positioned pass, so the
        // shift is computed there. Reuses the relative PseudoShift restore.
        El.ComputeStickyShift(Cont, ElPos.X, ElPos.Y,
          PseudoShiftX, PseudoShiftY);
        El.FStickyShiftX := PseudoShiftX;   // remember for hit-testing
        El.FStickyShiftY := PseudoShiftY;
        El.FPos.X := El.FPos.X + PseudoShiftX;
        El.FPos.Y := El.FPos.Y + PseudoShiftY;
      end;

      // CSS transform: wrap this element and its subtree in its matrix. Fixed
      // elements draw in viewport space (base 0,0); others in ElPos space.
      // Skipped on backends that cannot honour a relative matrix (PDF).
      HasTfm := El.SrcEl.Css.HasTransform and Cont.SupportsTransform;
      if HasTfm then
      begin
        if El.SrcEl.Css.ElPosition = epFixed then
        begin
          TfBaseX := 0;
          TfBaseY := 0;
        end
        else
        begin
          TfBaseX := ElPos.X;
          TfBaseY := ElPos.Y;
        end;
        if El.BuildTransformMatrix(TfBaseX, TfBaseY, TfMatrix) then
        begin
          Cont.SaveState;
          Cont.ConcatMatrix(TfMatrix.A, TfMatrix.B, TfMatrix.C,
            TfMatrix.D, TfMatrix.E, TfMatrix.F);
        end
        else
          HasTfm := False;
      end;

      HasOpacity := False;
      Process := True;
      case Flag of
        dfPositioned:
        begin
          if El.FLayoutPositioned and
             (El.SrcEl.Css.ZIndex = ZIndex) then
          begin
            HasOpacity := El.SrcEl.Css.Opacity < 1;
            if HasOpacity then Cont.PushOpacity(El.SrcEl.Css.Opacity);
            if El.SrcEl.Css.ElPosition = epFixed then
            begin
              El.SrcEl.Draw(Hdc, 0, 0, Clip, El);
              El.DrawStackingContext(Hdc, 0, 0, Clip, True);
            end
            else
            begin
              El.SrcEl.Draw(Hdc, ElPos.X, ElPos.Y, Clip, El);
              El.DrawStackingContext(Hdc, ElPos.X, ElPos.Y, Clip, True);
            end;
            if HasOpacity then Cont.PopOpacity;
            Process := False;
          end;
        end;
        dfBlock:
        begin
          if (not El.SrcEl.IsInline) and
             (El.SrcEl.Css.Float_ = efNone) and
             (not El.FLayoutPositioned) then
          begin
            HasOpacity := El.SrcEl.Css.Opacity < 1;
            if HasOpacity then Cont.PushOpacity(El.SrcEl.Css.Opacity);
            El.SrcEl.Draw(Hdc, ElPos.X, ElPos.Y, Clip, El);
          end;
        end;
        dfFloats:
        begin
          if (El.SrcEl.Css.Float_ <> efNone) and
             (not El.FLayoutPositioned) then
          begin
            HasOpacity := El.SrcEl.Css.Opacity < 1;
            if HasOpacity then Cont.PushOpacity(El.SrcEl.Css.Opacity);
            El.SrcEl.Draw(Hdc, ElPos.X, ElPos.Y, Clip, El);
            El.DrawStackingContext(Hdc, ElPos.X, ElPos.Y, Clip, False);
            if HasOpacity then Cont.PopOpacity;
            Process := False;
          end;
        end;
        dfInlines:
        begin
          if El.SrcEl.IsInline and
             (El.SrcEl.Css.Float_ = efNone) and
             (not El.FLayoutPositioned) then
          begin
            HasOpacity := El.SrcEl.Css.Opacity < 1;
            if HasOpacity then Cont.PushOpacity(El.SrcEl.Css.Opacity);
            El.SrcEl.Draw(Hdc, ElPos.X, ElPos.Y, Clip, El);
            if El.SrcEl.Css.Display in [displayInlineBlock, displayInlineFlex,
              displayInlineGrid] then
            begin
              El.DrawStackingContext(Hdc, ElPos.X, ElPos.Y, Clip, False);
              if HasOpacity then Cont.PopOpacity;
              Process := False;
            end;
          end;
        end;
      end;

      if Process then
      begin
        if Flag = dfPositioned then
        begin
          if not El.FLayoutPositioned then
            El.DrawChildren(Hdc, ElPos.X, ElPos.Y, Clip, Flag, ZIndex);
        end
        else
        begin
          if (El.SrcEl.Css.Float_ = efNone) and
             (El.SrcEl.Css.Display <> displayInlineBlock) and
             (not El.FLayoutPositioned) then
            El.DrawChildren(Hdc, ElPos.X, ElPos.Y, Clip, Flag, ZIndex);
        end;
        if HasOpacity then Cont.PopOpacity;
      end;

      if HasTfm then Cont.RestoreState;

      // Restore FPos after pseudo-relative shift
      if (PseudoShiftX <> 0) or (PseudoShiftY <> 0) then
      begin
        El.FPos.X := El.FPos.X - PseudoShiftX;
        El.FPos.Y := El.FPos.Y - PseudoShiftY;
      end;
    end;
  end;

  if ((FElement.Css.Overflow > ovVisible) or
      (FElement.Css.OverflowX > ovVisible)) and
     (FElement.Css.Display <> displayInline) then
    Cont.DelClip;

  // Draw scrollbar thumbs once per element, after content and outside the
  // clip, on the inline pass (the last of the normal content passes).
  if (Flag = dfInlines) and (FScrollView <> nil) then
  begin
    ClipBox := FPos;
    ClipBox.X := ClipBox.X + X;
    ClipBox.Y := ClipBox.Y + Y;
    DrawScrollbars(Hdc, Cont, ClipBox);
  end;
end;

procedure TPixieRenderItem.ComputeStickyShift(Cont: TPixieContainer;
  OriginX, OriginY: TPixiePixel; out DX, DY: TPixiePixel);
var
  Offsets: TPixieCssOffsets;
  MbTop, MbBottom, MbLeft, MbRight: TPixiePixel;   // element margin box, screen
  CbTop, CbBottom, CbLeft, CbRight: TPixiePixel;   // containing block, screen
  Inset, Lo, Hi: TPixiePixel;
  Viewport: TPixiePosition;
  HaveViewport: Boolean;
begin
  DX := 0;
  DY := 0;
  if FParent = nil then Exit;
  Offsets := FElement.Css.CssOffsets;

  // Element margin box in screen coords (FPos is the content box; the inset is
  // measured to the margin edge and the item is constrained by its full box).
  MbTop    := OriginY + FPos.Y - (FMargins.Top + FBorders.Top + FPadding.Top);
  MbBottom := OriginY + FPos.Y + FPos.Height +
              FMargins.Bottom + FBorders.Bottom + FPadding.Bottom;
  MbLeft   := OriginX + FPos.X - (FMargins.Left + FBorders.Left + FPadding.Left);
  MbRight  := OriginX + FPos.X + FPos.Width +
              FMargins.Right + FBorders.Right + FPadding.Right;

  // Containing block = parent content box, in screen coords. OriginX/Y is the
  // parent content origin this item's FPos is measured from.
  CbTop    := OriginY;
  CbBottom := OriginY + FParent.FPos.Height;
  CbLeft   := OriginX;
  CbRight  := OriginX + FParent.FPos.Width;
  HaveViewport := False;

  // Vertical — top wins over bottom when both are set (CSS).
  if not Offsets.Top.IsPredefined then
  begin
    Inset := Offsets.Top.Val;
    if MbTop < Inset then
    begin
      DY := Inset - MbTop;                      // pin down to the inset
      Hi := CbBottom - MbBottom;                // but stay inside the parent
      if DY > Hi then DY := Hi;
      if DY < 0 then DY := 0;
    end;
  end
  else if (not Offsets.Bottom.IsPredefined) and (Cont <> nil) then
  begin
    Cont.GetViewport(Viewport);
    HaveViewport := True;
    Inset := Viewport.Height - Offsets.Bottom.Val;
    if MbBottom > Inset then
    begin
      DY := Inset - MbBottom;                   // pin up (negative)
      Lo := CbTop - MbTop;
      if DY < Lo then DY := Lo;
      if DY > 0 then DY := 0;
    end;
  end;

  // Horizontal — left wins over right.
  if not Offsets.Left.IsPredefined then
  begin
    Inset := Offsets.Left.Val;
    if MbLeft < Inset then
    begin
      DX := Inset - MbLeft;
      Hi := CbRight - MbRight;
      if DX > Hi then DX := Hi;
      if DX < 0 then DX := 0;
    end;
  end
  else if (not Offsets.Right.IsPredefined) and (Cont <> nil) then
  begin
    if not HaveViewport then Cont.GetViewport(Viewport);
    Inset := Viewport.Width - Offsets.Right.Val;
    if MbRight > Inset then
    begin
      DX := Inset - MbRight;
      Lo := CbLeft - MbLeft;
      if DX < Lo then DX := Lo;
      if DX > 0 then DX := 0;
    end;
  end;
end;

procedure TPixieRenderItem.DrawScrollbars(Hdc: PtrUInt;
  Cont: TPixieContainer; const Box: TPixiePosition);
const
  SbW = 10;
  MinThumb = 24;
var
  MaxV, MaxH, ThumbStart, ThumbSize, Rad: TPixiePixel;
  ThumbColor: TPixieWebColor;

  // Thumb size and offset (0-based) along one axis of the given extent.
  procedure ThumbMetrics(Extent, MaxScroll, Offset: TPixiePixel;
    out AStart, ASize: TPixiePixel);
  var
    Range: TPixiePixel;
  begin
    ASize := Extent * Extent / (Extent + MaxScroll);
    if ASize < MinThumb then ASize := MinThumb;
    if ASize > Extent then ASize := Extent;
    Range := Extent - ASize;
    if Range > 0 then
      AStart := (Offset / MaxScroll) * Range
    else
      AStart := 0;
  end;

  // Fill a rounded thumb rect through the existing solid-fill path.
  procedure FillThumb(const R: TPixiePosition);
  var
    Layer: TPixieBackgroundLayer;
  begin
    Layer.Init;
    Layer.BorderBox := R;
    Layer.ClipBox := R;
    Layer.BorderRadius.TopLeftX := Rad;     Layer.BorderRadius.TopLeftY := Rad;
    Layer.BorderRadius.TopRightX := Rad;    Layer.BorderRadius.TopRightY := Rad;
    Layer.BorderRadius.BottomRightX := Rad; Layer.BorderRadius.BottomRightY := Rad;
    Layer.BorderRadius.BottomLeftX := Rad;  Layer.BorderRadius.BottomLeftY := Rad;
    Cont.DrawSolidFill(Hdc, Layer, ThumbColor);
  end;

begin
  if FScrollView = nil then
    Exit;
  Rad := (SbW - 4) / 2;
  ThumbColor := TPixieWebColor.Create(128, 128, 128, 160);

  MaxV := FScrollView.GetMaxVScroll;
  if MaxV > 0 then
  begin
    ThumbMetrics(Box.Height, MaxV, FScrollView.GetTop, ThumbStart, ThumbSize);
    FillThumb(TPixiePosition.Create(Box.X + Box.Width - SbW + 2,
      Box.Y + ThumbStart, SbW - 4, ThumbSize));
  end;

  MaxH := FScrollView.GetMaxHScroll;
  if MaxH > 0 then
  begin
    ThumbMetrics(Box.Width, MaxH, FScrollView.GetLeft, ThumbStart, ThumbSize);
    FillThumb(TPixiePosition.Create(Box.X + ThumbStart,
      Box.Y + Box.Height - SbW + 2, ThumbSize, SbW - 4));
  end;
end;

// --- Hit testing ---

function TPixieRenderItem.GetChildByPoint(X, Y, ClientX, ClientY: TPixiePixel;
  Flag: TPixieDrawFlag; ZIndex: Integer;
  Check: TPixieRenderItemCheckFunc): TPixieElement;
var
  ElPos: TPixiePosition;
  I: Integer;
  El: TPixieRenderItem;
  Ret: TPixieElement;
  Process: Boolean;
  ChildX, ChildY: TPixiePixel;
begin
  if FElement.Css.Overflow > ovVisible then
  begin
    if not FPos.IsPointInside(X, Y) then
      Exit(nil);
  end;

  Result := nil;

  ElPos := FPos;
  ElPos.X := X - ElPos.X + GetScrollLeft;
  ElPos.Y := Y - ElPos.Y + GetScrollTop;

  for I := FChildren.Count - 1 downto 0 do
  begin
    El := FChildren[I];
    if El.IsVisible and (El.SrcEl.Css.Display <> displayInlineText) then
    begin
      Process := True;
      // Undo the child's CSS transform (Base=0 frame) for the non-fixed paths.
      // Fixed elements use ClientX/ClientY and are left as a stacking-context
      // edge.
      ChildX := ElPos.X;
      ChildY := ElPos.Y;
      // position:sticky moved the item by its paint shift; map the query back
      // into the item's unshifted frame so the hit region follows it.
      if El.SrcEl.Css.ElPosition = epSticky then
      begin
        ChildX := ChildX - El.FStickyShiftX;
        ChildY := ChildY - El.FStickyShiftY;
      end;
      if El.SrcEl.Css.HasTransform and
         (El.SrcEl.Css.ElPosition <> epFixed) then
        El.MapPointInverse(ChildX, ChildY);
      case Flag of
        dfPositioned:
        begin
          if El.FLayoutPositioned and
             (El.SrcEl.Css.ZIndex = ZIndex) then
          begin
            if El.SrcEl.Css.ElPosition = epFixed then
            begin
              Ret := El.GetElementByPoint(ClientX, ClientY,
                ClientX, ClientY, Check);
              if (Ret = nil) and El.IsPointInside(ClientX, ClientY) then
              begin
                if (not Assigned(Check)) or Check(El) then
                  Ret := El.SrcEl;
              end;
            end
            else
            begin
              Ret := El.GetElementByPoint(ChildX, ChildY,
                ClientX, ClientY, Check);
              if (Ret = nil) and El.IsPointInside(ChildX, ChildY) then
              begin
                if (not Assigned(Check)) or Check(El) then
                  Ret := El.SrcEl;
              end;
            end;
            Process := False;
            if Ret <> nil then Exit(Ret);
          end;
        end;
        dfBlock:
        begin
          if (not El.SrcEl.IsInline) and
             (El.SrcEl.Css.Float_ = efNone) and
             (not El.FLayoutPositioned) then
          begin
            Ret := El.GetChildByPoint(ChildX, ChildY,
              ClientX, ClientY, Flag, ZIndex, Check);
            if (Ret = nil) and El.IsPointInside(ChildX, ChildY) then
            begin
              if (not Assigned(Check)) or Check(El) then
                Ret := El.SrcEl;
            end;
            Process := False;
            if Ret <> nil then Exit(Ret);
          end;
        end;
        dfFloats:
        begin
          if (El.SrcEl.Css.Float_ <> efNone) and
             (not El.FLayoutPositioned) then
          begin
            Ret := El.GetElementByPoint(ChildX, ChildY,
              ClientX, ClientY, Check);
            if (Ret = nil) and El.IsPointInside(ChildX, ChildY) then
              Ret := El.SrcEl;
            Process := False;
            if Ret <> nil then Exit(Ret);
          end;
        end;
        dfInlines:
        begin
          if El.SrcEl.IsInline and
             (El.SrcEl.Css.Float_ = efNone) and
             (not El.FLayoutPositioned) then
          begin
            if El.SrcEl.Css.Display in [displayInlineBlock, displayInlineTable,
              displayInlineFlex, displayInlineGrid] then
            begin
              Ret := El.GetElementByPoint(ChildX, ChildY,
                ClientX, ClientY, Check);
              Process := False;
              if Ret <> nil then Exit(Ret);
            end
            else if El.SrcEl.Css.Display = displayInline then
            begin
              // Check children first (e.g. inline-block inside inline)
              Ret := El.GetElementByPoint(ChildX, ChildY,
                ClientX, ClientY, Check);
              Process := False;
              if Ret <> nil then Exit(Ret);
            end;
            if El.IsPointInside(ChildX, ChildY) then
            begin
              if (not Assigned(Check)) or Check(El) then
                Exit(El.SrcEl);
            end;
          end;
        end;
      end;

      if Process and (not El.FLayoutPositioned) then
      begin
        if Flag = dfPositioned then
        begin
          Ret := El.GetChildByPoint(ChildX, ChildY,
            ClientX, ClientY, Flag, ZIndex, Check);
          if Ret <> nil then
          begin
            if not Assigned(Check) then
              Exit(Ret)
            else if Check(El) then
              Exit(Ret);
          end;
        end
        else
        begin
          if (El.SrcEl.Css.Float_ = efNone) and
             (not (El.SrcEl.Css.Display in [displayInlineBlock,
              displayInlineFlex, displayInlineGrid])) then
          begin
            Ret := El.GetChildByPoint(ChildX, ChildY,
              ClientX, ClientY, Flag, ZIndex, Check);
            if Ret <> nil then
            begin
              if not Assigned(Check) then
                Exit(Ret)
              else if Check(El) then
                Exit(Ret);
            end;
          end;
        end;
      end;
    end;
  end;
end;

function TPixieRenderItem.GetElementByPoint(X, Y, ClientX, ClientY: TPixiePixel;
  Check: TPixieRenderItemCheckFunc): TPixieElement;
var
  I, Idx: Integer;
  ZIndexes: TPixieIntVector;
  Ret: TPixieElement;
begin
  if not IsVisible then
    Exit(nil);

  Result := nil;

  ZIndexes := TPixieIntVector.Create;
  try
    // Collect unique z-indexes
    if FPositioned <> nil then
    for I := 0 to FPositioned.Count - 1 do
    begin
      Idx := FPositioned[I].SrcEl.Css.ZIndex;
      if ZIndexes.IndexOf(Idx) < 0 then
        ZIndexes.Add(Idx);
    end;
    ZIndexes.Sort;

    // Positive z-index (reverse)
    for I := ZIndexes.Count - 1 downto 0 do
    begin
      if ZIndexes[I] > 0 then
      begin
        Ret := GetChildByPoint(X, Y, ClientX, ClientY,
          dfPositioned, ZIndexes[I], Check);
        if Ret <> nil then Exit(Ret);
      end;
    end;

    // Zero z-index
    for I := 0 to ZIndexes.Count - 1 do
    begin
      if ZIndexes[I] = 0 then
      begin
        Ret := GetChildByPoint(X, Y, ClientX, ClientY,
          dfPositioned, ZIndexes[I], Check);
        if Ret <> nil then Exit(Ret);
      end;
    end;

    // Inlines
    Ret := GetChildByPoint(X, Y, ClientX, ClientY,
      dfInlines, 0, Check);
    if Ret <> nil then Exit(Ret);

    // Floats
    Ret := GetChildByPoint(X, Y, ClientX, ClientY,
      dfFloats, 0, Check);
    if Ret <> nil then Exit(Ret);

    // Blocks
    Ret := GetChildByPoint(X, Y, ClientX, ClientY,
      dfBlock, 0, Check);
    if Ret <> nil then Exit(Ret);

    // Negative z-index (reverse)
    for I := ZIndexes.Count - 1 downto 0 do
    begin
      if ZIndexes[I] < 0 then
      begin
        Ret := GetChildByPoint(X, Y, ClientX, ClientY,
          dfPositioned, ZIndexes[I], Check);
        if Ret <> nil then Exit(Ret);
      end;
    end;
  finally
    ZIndexes.Free;
  end;

  // Check self
  if FElement.Css.ElPosition = epFixed then
  begin
    if IsPointInside(ClientX, ClientY) then
    begin
      if (not Assigned(Check)) or Check(Self) then
        Result := FElement;
    end;
  end
  else
  begin
    if IsPointInside(X, Y) then
    begin
      if (not Assigned(Check)) or Check(Self) then
        Result := FElement;
    end;
  end;
end;

function TPixieRenderItem.GetTextByPoint(X, Y: TPixiePixel): TPixieElement;
var
  LocalX, LocalY, ChildX, ChildY: TPixiePixel;
  I: Integer;
  El: TPixieRenderItem;
  Ret: TPixieElement;
begin
  Result := nil;
  if not IsVisible then Exit;

  // Respect overflow clipping
  if FElement.Css.Overflow > ovVisible then
  begin
    if not FPos.IsPointInside(X, Y) then
      Exit;
  end;

  // Transform point to local coordinate space
  LocalX := X - FPos.X + GetScrollLeft;
  LocalY := Y - FPos.Y + GetScrollTop;

  for I := FChildren.Count - 1 downto 0 do
  begin
    El := FChildren[I];
    if not El.IsVisible then Continue;

    // Undo the child's CSS transform so it is tested against its untransformed
    // layout (the point is in this element's content frame, i.e. Base=0).
    ChildX := LocalX;
    ChildY := LocalY;
    if El.SrcEl.Css.HasTransform then
      El.MapPointInverse(ChildX, ChildY);

    if El.SrcEl.Css.Display = displayInlineText then
    begin
      if El.IsPointInside(ChildX, ChildY) then
        Exit(El.SrcEl);
    end
    else
    begin
      Ret := El.GetTextByPoint(ChildX, ChildY);
      if Ret <> nil then
        Exit(Ret);
    end;
  end;
end;

function TPixieRenderItem.GetNearestTextByPoint(
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

    // Respect overflow clipping
    if Ri.FElement.Css.Overflow > ovVisible then
      if not Ri.FPos.IsPointInside(PX, PY) then
        Exit;

    // Transform to local coordinates
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
        // Compute gap from point to bounding box
        if ChildX < P.X then
          DX := P.X - ChildX
        else if ChildX > P.X + P.Width then
          DX := ChildX - (P.X + P.Width)
        else
          DX := 0;

        if ChildY < P.Y then
          DY := P.Y - ChildY
        else if ChildY > P.Y + P.Height then
          DY := ChildY - (P.Y + P.Height)
        else
          DY := 0;

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

begin
  Best := nil;
  BestDist := 0;
  Search(Self, X, Y);
  Result := Best;
end;

function TPixieRenderItem.IsPointInside(X, Y: TPixiePixel): Boolean;
var
  P: TPixiePosition;
  Boxes: TPixiePositionVector;
  Offsets: TPixieCssOffsets;
  I: Integer;
begin
  if not (FElement.Css.Display in [displayInline, displayTableRow]) then
  begin
    P := FPos;
    P.AddMargins(FPadding);
    P.AddMargins(FBorders);
    // Account for pseudo-relative shift (position changed via :active/:hover
    // without re-layout — FPos doesn't include the offset yet)
    if (not FLayoutPositioned) and (FElement.Css.ElPosition = epRelative) then
    begin
      Offsets := FElement.Css.CssOffsets;
      if not Offsets.Left.IsPredefined then
        P.X := P.X + Offsets.Left.Val
      else if not Offsets.Right.IsPredefined then
        P.X := P.X - Offsets.Right.Val;
      if not Offsets.Top.IsPredefined then
        P.Y := P.Y + Offsets.Top.Val
      else if not Offsets.Bottom.IsPredefined then
        P.Y := P.Y - Offsets.Bottom.Val;
    end;
    Result := P.IsPointInside(X, Y);
  end
  else
  begin
    Boxes := TPixiePositionVector.Create;
    try
      GetInlineBoxes(Boxes);
      for I := 0 to Boxes.Count - 1 do
      begin
        if Boxes[I].IsPointInside(X, Y) then
          Exit(True);
      end;
      Result := False;
    finally
      Boxes.Free;
    end;
  end;
end;

// --- Document size / redraw ---

procedure TPixieRenderItem.CalcDocumentSize(var Sz: TPixieSize;
  X: TPixiePixel; Y: TPixiePixel);
var
  I: Integer;
  ChildSize: TPixieSize;
  Boxes: TPixiePositionVector;
begin
  if not (Css.Display in [displayInline, displayTableRow]) then
  begin
    if IsVisible then
    begin
      if FElement.Css.ElPosition <> epFixed then
      begin
        Sz.Width := Max(Sz.Width, X + Right);
        Sz.Height := Max(Sz.Height, Y + Bottom);
      end;

      if FElement.Css.Overflow in [ovScroll, ovAuto] then
      begin
        ChildSize.Width := 0;
        ChildSize.Height := 0;
        for I := 0 to FChildren.Count - 1 do
          FChildren[I].CalcDocumentSize(ChildSize, 0, 0);
        if FScrollView = nil then
          FScrollView := TPixieScrollView.Create(FPos, ChildSize)
        else
          FScrollView.SetViewport(FPos, ChildSize);
      end
      else
      begin
        if (FElement.Css.Overflow = ovVisible) and
           (FElement.Css.Display <> displayTable) then
        begin
          for I := 0 to FChildren.Count - 1 do
            FChildren[I].CalcDocumentSize(Sz, X + FPos.X, Y + FPos.Y);
        end
        else
        begin
          ChildSize.Width := 0;
          ChildSize.Height := 0;
          for I := 0 to FChildren.Count - 1 do
            FChildren[I].CalcDocumentSize(ChildSize, 0, 0);
        end;
      end;
    end;
  end
  else
  begin
    Boxes := TPixiePositionVector.Create;
    try
      GetInlineBoxes(Boxes);
      for I := 0 to Boxes.Count - 1 do
      begin
        Sz.Width := Max(Sz.Width, X + Boxes[I].X + Boxes[I].Width);
        Sz.Height := Max(Sz.Height, Y + Boxes[I].Y + Boxes[I].Height);
      end;
    finally
      Boxes.Free;
    end;
  end;
end;

procedure TPixieRenderItem.GetRedrawBox(var APos: TPixiePosition;
  X: TPixiePixel; Y: TPixiePixel);
var
  PLeft, PRight, PTop, PBottom: TPixiePixel;
  I: Integer;
  Sub: TPixiePosition;
  M: TPixieMatrix;
  CX, CY, MinX, MinY, MaxX, MaxY: Single;

  procedure FoldCorner(BX, BY: Single);
  begin
    M.Apply(BX, BY, CX, CY);
    if CX < MinX then MinX := CX;
    if CX > MaxX then MaxX := CX;
    if CY < MinY then MinY := CY;
    if CY > MaxY then MaxY := CY;
  end;

begin
  if not IsVisible then Exit;

  if FElement.Css.HasTransform and BuildTransformMatrix(X, Y, M) then
  begin
    // Build the untransformed subtree border box, then union the AABB of its
    // four transformed corners so partial repaints cover the transformed pixels.
    // A nested transformed child folds its own AABB into Sub, which this matrix
    // then re-folds — AABB-of-AABB over-estimates but only ever over-paints, so
    // it stays correct (never leaves trails); do not tighten it to child-local
    // geometry, which would risk under-covering rotated nested content.
    Sub.X := X + FPos.X - FPadding.Left - FBorders.Left;
    Sub.Y := Y + FPos.Y - FPadding.Top - FBorders.Top;
    Sub.Width := FPos.Width + FPadding.Left + FPadding.Right +
      FBorders.Left + FBorders.Right;
    Sub.Height := FPos.Height + FPadding.Top + FPadding.Bottom +
      FBorders.Top + FBorders.Bottom;

    if FElement.Css.Overflow = ovVisible then
      for I := 0 to FChildren.Count - 1 do
        if FChildren[I].SrcEl.Css.ElPosition <> epFixed then
          FChildren[I].GetRedrawBox(Sub, X + FPos.X, Y + FPos.Y);

    M.Apply(Sub.X, Sub.Y, CX, CY);
    MinX := CX; MaxX := CX; MinY := CY; MaxY := CY;
    FoldCorner(Sub.Right, Sub.Y);
    FoldCorner(Sub.X, Sub.Bottom);
    FoldCorner(Sub.Right, Sub.Bottom);

    PLeft   := Min(APos.X, MinX);
    PRight  := Max(APos.Right, MaxX);
    PTop    := Min(APos.Y, MinY);
    PBottom := Max(APos.Bottom, MaxY);
    APos.X := PLeft;
    APos.Y := PTop;
    APos.Width := PRight - PLeft;
    APos.Height := PBottom - PTop;
    Exit;
  end;

  PLeft   := Min(APos.X, X + FPos.X - FPadding.Left - FBorders.Left);
  PRight  := Max(APos.Right, X + FPos.Right + FPadding.Left + FBorders.Left);
  PTop    := Min(APos.Y, Y + FPos.Y - FPadding.Top - FBorders.Top);
  PBottom := Max(APos.Bottom, Y + FPos.Bottom + FPadding.Bottom + FBorders.Bottom);

  APos.X := PLeft;
  APos.Y := PTop;
  APos.Width := PRight - PLeft;
  APos.Height := PBottom - PTop;

  if FElement.Css.Overflow = ovVisible then
  begin
    for I := 0 to FChildren.Count - 1 do
    begin
      if FChildren[I].SrcEl.Css.ElPosition <> epFixed then
        FChildren[I].GetRedrawBox(APos, X + FPos.X, Y + FPos.Y);
    end;
  end;
end;

procedure TPixieRenderItem.GetRenderingBoxes(Boxes: TPixiePositionVector);
var
  P: TPixiePosition;
  CurEl: TPixieRenderItem;
  AddX, AddY: TPixiePixel;
  I: Integer;
  Doc: TPixieDocument;
  Cont: TPixieContainer;
  Viewport: TPixiePosition;
begin
  if FElement.Css.Display in [displayInline, displayTableRow] then
  begin
    GetInlineBoxes(Boxes);
    for I := 0 to Boxes.Count - 1 do
    begin
      P := Boxes[I];
      ScrollBox(P);
      Boxes[I] := P;
    end;
  end
  else
  begin
    P := FPos;
    P.AddMargins(FPadding);
    P.AddMargins(FBorders);
    Boxes.Add(P);
  end;

  Assert(FElement.GetDocument is TPixieDocument);
  Doc := TPixieDocument(FElement.GetDocument);
  Cont := Doc.Container;

  if FElement.Css.ElPosition <> epFixed then
  begin
    CurEl := FParent;
    AddX := 0;
    AddY := 0;
    while CurEl <> nil do
    begin
      if CurEl.Css.ElPosition = epFixed then
      begin
        Cont.GetViewport(Viewport);
        AddX := AddX + CurEl.FPos.X + Viewport.X - CurEl.GetScrollLeft;
        AddY := AddY + CurEl.FPos.Y + Viewport.Y - CurEl.GetScrollTop;
        Break;
      end;
      AddX := AddX + CurEl.FPos.X - CurEl.GetScrollLeft;
      AddY := AddY + CurEl.FPos.Y - CurEl.GetScrollTop;
      CurEl := CurEl.FParent;
    end;
    for I := 0 to Boxes.Count - 1 do
    begin
      P := Boxes[I];
      P.X := P.X + AddX;
      P.Y := P.Y + AddY;
      Boxes[I] := P;
    end;
  end
  else
  begin
    Cont.GetViewport(Viewport);
    for I := 0 to Boxes.Count - 1 do
    begin
      P := Boxes[I];
      P.X := P.X + Viewport.X;
      P.Y := P.Y + Viewport.Y;
      Boxes[I] := P;
    end;
  end;
end;

// --- Containing block context ---

// CSS Sizing 3 § 2.4: a percentage height resolves to 'auto' when the
// containing block's height is itself indefinite (propagated through
// auto-height ancestors). Without this guard, height:100% on any
// descendant cascades unchanged from the initial containing block down
// through every auto-height ancestor and stretches to the viewport.
function PercentAgainstAutoParent(const Len: TPixieCssLength;
  const HCtx: TPixieTypedPixel): Boolean; inline;
begin
  Result := (not Len.IsPredefined) and
    (Len.Units = cssUnitsPercentage) and
    (HCtx.ValueType = cbcAuto);
end;

procedure TPixieRenderItem.CalcCbLength(const Len: TPixieCssLength;
  PercentBase: TPixiePixel; var OutValue: TPixieTypedPixel);
var
  Doc: TPixieDocument;
begin
  if not Len.IsPredefined then
  begin
    if Len.Units = cssUnitsCalc then
    begin
      OutValue.Value := Len.CalcPercent(PercentBase);
      // calc()/min()/max()/clamp() count as percentage-derived when any term
      // references the percentage basis, so the used value tracks the CB.
      if Len.PercentRelative then
        OutValue.ValueType := cbcPercentage
      else
        OutValue.ValueType := cbcAbsolute;
    end
    else if Len.Units = cssUnitsPercentage then
    begin
      OutValue.Value := Len.CalcPercent(PercentBase);
      OutValue.ValueType := cbcPercentage;
    end
    else
    begin
      Assert(FElement.GetDocument is TPixieDocument);
      Doc := TPixieDocument(FElement.GetDocument);
      OutValue.Value := Doc.ToPixels(Len, Css.FontMetrics, 0);
      OutValue.ValueType := cbcAbsolute;
    end;
  end;
end;

function TPixieRenderItem.CalculateContainingBlockContext(
  const CbContext: TPixieContainingBlockContext): TPixieContainingBlockContext;
var
  Par: TPixieRenderItem;
  CssW, CssH: TPixieCssLength;
  UseWidth, UseHeight: Boolean;
begin
  Result.Init;
  Result.ContextIdx := CbContext.ContextIdx + 1;
  Result.SizeMode := CbContext.SizeMode and SizeModeContent;
  Result.Width.Value := CbContext.Width.Value - ContentOffsetWidth;
  Result.MaxWidth.Value := Result.Width.Value;
  if not (FElement.Css.ElPosition in [epAbsolute, epFixed]) then
    Result.Height.Value := CbContext.Height.Value - ContentOffsetHeight;

  // Width/height from CSS (skip for table-cell, except height for
  // percentage resolution: children need the cell's declared height)
  if FElement.Css.Display = displayTableCell then
  begin
    CssH := Css.CssHeight;
    if (not CssH.IsPredefined) and (CssH.Units <> cssUnitsPercentage) then
    begin
      CalcCbLength(CssH, CbContext.Height.Value, Result.Height);
      // In quirks mode, td height acts as border-box — subtract padding
      // so that FPos.Height + padding = declared height
      if (Result.Height.ValueType <> cbcAuto) and
         (Css.BoxSizing <> bxBorderBox) and
         (FElement.GetDocument is TPixieDocument) and
         (TPixieDocument(FElement.GetDocument).Mode = dmQuirks) then
        Result.Height.Value := Result.Height.Value - ContentOffsetHeight;
    end;
  end
  else
  begin
    Par := FParent;

    // --- Width ---
    if (CbContext.SizeMode and SizeModeExactWidth) <> 0 then
    begin
      Result.Width.Value := CbContext.Width.Value;
      Result.Width.ValueType := cbcAbsolute;
    end
    else
    begin
      UseWidth := True;
      CssW := Css.CssWidth;
      if (Par <> nil) and
         (Par.Css.Display in [displayFlex, displayInlineFlex]) then
      begin
        if (not Css.FlexBasis.IsPredefined) and
           (Css.FlexBasis.Val >= 0) then
        begin
          if Par.Css.FlexDirection in [fdRow, fdRowReverse] then
          begin
            Result.Width.ValueType := cbcAuto;
            Result.Width.Value := 0;
            UseWidth := False;
          end;
        end;
      end;
      if UseWidth then
        CalcCbLength(CssW, CbContext.Width.Value, Result.Width);
    end;

    // --- Height ---
    if (CbContext.SizeMode and SizeModeExactHeight) <> 0 then
    begin
      Result.Height.Value := CbContext.Height.Value;
      Result.Height.ValueType := cbcAbsolute;
    end
    else
    begin
      UseHeight := True;
      CssH := Css.CssHeight;
      if (Par <> nil) and
         (Par.Css.Display in [displayFlex, displayInlineFlex]) then
      begin
        if (not Css.FlexBasis.IsPredefined) and
           (Css.FlexBasis.Val >= 0) then
        begin
          if Par.Css.FlexDirection in [fdColumn, fdColumnReverse] then
          begin
            Result.Height.ValueType := cbcAuto;
            Result.Height.Value := 0;
            UseHeight := False;
          end;
        end;
      end;
      if UseHeight and not PercentAgainstAutoParent(CssH, CbContext.Height) then
        CalcCbLength(CssH, CbContext.Height.Value, Result.Height);

      // CSS Sizing 4 § 3: when aspect-ratio derives a definite height from a
      // definite width, surface it as the children's containing-block
      // height so percentage descendants resolve against it instead of
      // falling through the indefinite-parent rule. Sibling to the FPos
      // derivation in TPixieRenderBlock.Render (which sizes this box).
      if (FElement.Css.AspectRatio > 0) and
         (Result.Height.ValueType = cbcAuto) and
         (Result.Width.ValueType <> cbcAuto) and
         (Result.Width.Value > 0) then
      begin
        Result.Height.Value := Result.Width.Value / FElement.Css.AspectRatio;
        Result.Height.ValueType := cbcAbsolute;
      end;
    end;

    // Adjust for table/root
    if (Result.Width.ValueType <> cbcAuto) and
       ((FElement.Css.Display = displayTable) or FElement.IsRoot) then
      Result.Width.Value := Result.Width.Value - ContentOffsetWidth;
    if (Result.Height.ValueType <> cbcAuto) and
       ((FElement.Css.Display = displayTable) or FElement.IsRoot) then
      Result.Height.Value := Result.Height.Value - ContentOffsetHeight;
  end;

  Result.RenderWidth := Result.Width;

  // Min/max — skip when size is already definitive: flex/grid pass exact
  // values with min/max already applied against the correct container
  // reference, so re-resolving percentage min/max against the narrowed
  // item width would produce wrong results (e.g. max-width:33% of the
  // item width instead of 33% of the container width).
  if (CbContext.SizeMode and SizeModeExactWidth) = 0 then
  begin
    CalcCbLength(FElement.Css.CssMinWidth, CbContext.Width.Value, Result.MinWidth);
    CalcCbLength(FElement.Css.CssMaxWidth, CbContext.Width.Value, Result.MaxWidth);
  end;
  if (CbContext.SizeMode and SizeModeExactHeight) = 0 then
  begin
    if not PercentAgainstAutoParent(FElement.Css.CssMinHeight, CbContext.Height) then
      CalcCbLength(FElement.Css.CssMinHeight, CbContext.Height.Value, Result.MinHeight);
    if not PercentAgainstAutoParent(FElement.Css.CssMaxHeight, CbContext.Height) then
      CalcCbLength(FElement.Css.CssMaxHeight, CbContext.Height.Value, Result.MaxHeight);
  end;

  // Fix box sizing
  if Result.Width.ValueType <> cbcAuto then
    Result.RenderWidth.Value := Result.Width.Value - BoxSizingWidth;
  if Result.MinWidth.ValueType <> cbcNone then
    Result.MinWidth.Value := Result.MinWidth.Value - BoxSizingWidth;
  if Result.MaxWidth.ValueType <> cbcNone then
    Result.MaxWidth.Value := Result.MaxWidth.Value - BoxSizingWidth;
  if Result.MinHeight.ValueType <> cbcNone then
    Result.MinHeight.Value := Result.MinHeight.Value - BoxSizingHeight;
  if Result.MaxHeight.ValueType <> cbcNone then
    Result.MaxHeight.Value := Result.MaxHeight.Value - BoxSizingHeight;
end;

// --- Virtual stubs ---

function TPixieRenderItem.Init: TPixieRenderItem;
var
  I: Integer;
  Child, NewChild: TPixieRenderItem;
begin
  FElement.AddRender(Self);

  for I := 0 to FChildren.Count - 1 do
  begin
    Child := FChildren[I];
    NewChild := Child.Init;
    if NewChild <> Child then
    begin
      FChildren.OwnsObjects := False;
      FChildren[I] := NewChild;
      FChildren.OwnsObjects := True;
      Child.Free;
    end;
  end;

  Result := Self;
end;

procedure TPixieRenderItem.ApplyVerticalAlign;
begin
  // no-op in base class
end;

function TPixieRenderItem.GetFirstBaseline: TPixiePixel;
begin
  Result := Height - MarginBottom;
end;

function TPixieRenderItem.GetLastBaseline: TPixiePixel;
begin
  Result := Height - MarginBottom;
end;

function TPixieRenderItem.Clone: TPixieRenderItem;
begin
  Result := TPixieRenderItem.Create(FElement);
end;

procedure TPixieRenderItem.GetInlineBoxes(Boxes: TPixiePositionVector);
begin
  // no-op
end;

procedure TPixieRenderItem.AddInlineBox(const Box: TPixiePosition);
begin
  // no-op
end;

procedure TPixieRenderItem.ClearInlineBoxes;
begin
  // no-op
end;

function TPixieRenderItem.GetDrawVerticalOffset: TPixiePixel;
begin
  Result := 0;
end;

function TPixieRenderItem.GetDrawBottomOffset: TPixiePixel;
begin
  Result := 0;
end;

procedure TPixieRenderItem.YShift(Delta: TPixiePixel);
begin
  FPos.Y := FPos.Y + Delta;
end;

// --- Debug ---

procedure TPixieRenderItem.Dump(var Output: string; Indent: Integer);
var
  Prefix: string;
  I: Integer;
begin
  Prefix := StringOfChar(' ', Indent * 2);
  Output := Output + Prefix + FElement.DumpGetName;
  Output := Output + ' pos=' + IntToStr(Round(FPos.X)) + ',' +
    IntToStr(Round(FPos.Y)) + ',' + IntToStr(Round(FPos.Width)) + ',' +
    IntToStr(Round(FPos.Height));
  Output := Output + #10;

  for I := 0 to FChildren.Count - 1 do
    FChildren[I].Dump(Output, Indent + 1);
end;

end.
