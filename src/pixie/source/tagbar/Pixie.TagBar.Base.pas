unit Pixie.TagBar.Base;

// TPixieTagBarCore — platform-independent tag bar logic.
// Contains data management, layout, painting, and input handling.
// Concrete wrappers (Lazarus, VCL, FMX) create a core instance and wire
// host callbacks for platform-specific operations.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Math, DateUtils, Generics.Collections,
  Pixie.Types, Pixie.WebColor, Pixie.Borders, Pixie.Canvas,
  Pixie.TagBar.Colors, Pixie.TagBar.Render;

type
  { Tag definition }
  TPixieTagDef = record
    ID: Integer;
    Text: string;
    Color: TPixieWebColor;
    LeadIcon: string;
    TrailIcon: string;
  end;

  TPixieTagDefList = TList<TPixieTagDef>;
  TPixieTagIdSet = TDictionary<Integer, Boolean>;

  { Options }
  TPixieTagBarOption = (
    tboShowAll,
    tboShowDismiss,
    tboAllowCheck,
    tboAllowCreate,
    tboAllowEdit,
    tboReadOnly,
    tboAlwaysChecked,
    tboShowColorSwatch
  );
  TPixieTagBarOptions = set of TPixieTagBarOption;

  { Inline editing mode }
  TPixieTagEditMode = (temNone, temAddNew, temRename);

  { Scrolling mode }
  TPixieTagBarScrollMode = (smNone, smVertical, smHorizontal, smAuto);
  TPixieTagBarScrollAxis = (saHorizontal, saVertical);

  { Layout record — position and metrics of each rendered pill }
  TPixieTagPillLayout = record
    X, Y: Single;
    TagIndex: Integer;    // index in FTags, -1 for add/edit pill
    IsAddButton: Boolean;
    Metrics: TPixieTagPillMetrics;
  end;
  TPixieTagLayoutList = TList<TPixieTagPillLayout>;

  { Events }
  TPixieTagCheckedEvent = procedure(Sender: TObject; ID: Integer;
    Checked: Boolean) of object;
  TPixieTagAddingEvent = procedure(Sender: TObject; const Text: string;
    Color: TPixieWebColor; var Allow: Boolean) of object;
  TPixieTagDeletingEvent = procedure(Sender: TObject; ID: Integer;
    var Allow: Boolean) of object;
  TPixieTagChangingEvent = procedure(Sender: TObject; ID: Integer;
    const NewText: string; NewColor: TPixieWebColor;
    var Allow: Boolean) of object;

  { Host callback types }
  TPixieTagBarHostNotify = procedure of object;
  TPixieTagBarHostSetCursor = procedure(ACursor: TPixieCursorKind) of object;
  TPixieTagBarHostGetInt = function: Integer of object;
  TPixieTagBarHostGetFloat = function: Single of object;
  TPixieTagBarHostGetColor = function: TPixieWebColor of object;
  TPixieTagBarHostGetBool = function: Boolean of object;
  TPixieTagBarHostSetInt = procedure(H: Integer) of object;
  TPixieTagBarHostSetBool = procedure(AEnabled: Boolean) of object;

const
  { Convenience presets }
  TagBarAssignOpts: TPixieTagBarOptions =
    [tboShowAll, tboAllowCheck, tboAllowCreate];
  TagBarFilterOpts: TPixieTagBarOptions =
    [tboShowAll, tboAllowCheck];
  TagBarDisplayOpts: TPixieTagBarOptions =
    [tboReadOnly];
  TagBarEditorOpts: TPixieTagBarOptions =
    [tboShowAll, tboAllowCheck, tboAllowCreate, tboAllowEdit,
     tboShowDismiss];
  TagBarSettingsOpts: TPixieTagBarOptions =
    [tboShowAll, tboAllowCreate, tboAllowEdit, tboShowDismiss,
     tboAlwaysChecked, tboShowColorSwatch];

  { Virtual key codes (platform-neutral) }
  tbVK_RETURN = 13;
  tbVK_ESCAPE = 27;
  tbVK_BACK   = 8;
  tbVK_DELETE = 46;
  tbVK_LEFT   = 37;
  tbVK_RIGHT  = 39;
  tbVK_HOME   = 36;
  tbVK_END    = 35;
  tbVK_PRIOR  = 33;
  tbVK_NEXT   = 34;
  tbVK_SPACE  = 32;
  tbVK_F2     = 113;

  { Scrollbar dimensions }
  tbScrollbarWidth     = 4;
  tbScrollbarMargin    = 2;
  tbScrollbarMinThumb  = 16;
  tbScrollWheelStep    = 40;

type
  { TPixieTagBarCore }

  TPixieTagBarCore = class
  private
    // Rendering
    FCanvas: TPixieCanvas;
    FFont: TPixieFontHandle;
    FFontMetrics: TPixieFontMetrics;
    FFontScale: Single;

    // Data
    FTags: TPixieTagDefList;
    FChecked: TPixieTagIdSet;
    FNextID: Integer;
    FPaletteIndex: Integer;

    // Configuration
    FPalette: TPixieTagPaletteArray;
    FOptions: TPixieTagBarOptions;
    FTagShape: TPixieTagShape;
    FAutoHeight: Boolean;
    FFontFamily: string;
    FFontSize: Single;
    FSpacingH: Single;
    FSpacingV: Single;
    FPadding: Single;
    FShowBorder: Boolean;
    FBorderColor: TPixieWebColor;
    FEmptyMessage: string;
    FEmptyMessageWidth: Single;

    // Layout cache
    FLayout: TPixieTagLayoutList;
    FLayoutValid: Boolean;
    FContentHeight: Single;
    FContentWidth: Single;
    FUpdatingHeight: Boolean;

    // Scrolling
    FScrollMode: TPixieTagBarScrollMode;
    FScrollX: Single;
    FScrollY: Single;
    FScrollDragging: Boolean;
    FScrollDragAxis: TPixieTagBarScrollAxis;
    FScrollDragOffset: Single;

    // Interaction
    FHoverIndex: Integer;
    FHoverZone: TPixieTagHitZone;
    FPressedIndex: Integer;
    FFocusIndex: Integer;

    // Inline editing
    FEditMode: TPixieTagEditMode;
    FEditTagIndex: Integer;
    FEditText: string;
    FEditCaretPos: Integer;
    FEditCaretVisible: Boolean;
    FEditColor: TPixieWebColor;

    // Double-click detection
    FLastClickTime: TDateTime;
    FLastClickIndex: Integer;

    // Events
    FOnTagChecked: TPixieTagCheckedEvent;
    FOnChanged: TNotifyEvent;
    FOnTagAdding: TPixieTagAddingEvent;
    FOnTagDeleting: TPixieTagDeletingEvent;
    FOnTagChanging: TPixieTagChangingEvent;

    // Internal helpers
    procedure RecreateFont;
    procedure InvalidateLayout;
    procedure EnsureLayout;
    procedure PerformLayout;
    function GetPillHeight: Single;
    function GetPillOptions(IsAddBtn: Boolean): TPixieTagPillOptions;
    function GetPillState(TagIndex, LayoutIndex: Integer): TPixieTagPillState;
    function LayoutHitTest(MX, MY: Integer;
      out Zone: TPixieTagHitZone): Integer;
    function NextPaletteColor: TPixieWebColor;
    function FindTagIndex(ID: Integer): Integer;

    // Scrolling
    function EffectiveScrollMode: TPixieTagBarScrollMode;
    function ViewWidth: Single;
    function ViewHeight: Single;
    function ViewExtent(Axis: TPixieTagBarScrollAxis): Single;
    function ContentExtent(Axis: TPixieTagBarScrollAxis): Single;
    function MaxScroll(Axis: TPixieTagBarScrollAxis): Single;
    function HasScrollbar(Axis: TPixieTagBarScrollAxis): Boolean;
    function ScrollOffset(Axis: TPixieTagBarScrollAxis): Single;
    procedure SetScrollOffset(Axis: TPixieTagBarScrollAxis; Value: Single);
    procedure ClampScroll;
    procedure ScrollBy(DX, DY: Single);
    procedure GetScrollThumb(Axis: TPixieTagBarScrollAxis;
      out TPos, TSize: Single);
    function HitScrollbar(Axis: TPixieTagBarScrollAxis; MX, MY: Integer;
      out OnThumb: Boolean; out TPos, TSize: Single): Boolean;
    procedure ScrollPage(Axis: TPixieTagBarScrollAxis; Down: Boolean);
    function ScrollAxisFor(Mode: TPixieTagBarScrollMode): TPixieTagBarScrollAxis;

    // Editing
    procedure BeginEdit(Mode: TPixieTagEditMode; TagIndex: Integer);
    procedure CommitEdit;
    procedure CancelEdit;
    procedure CycleTagColor(TagIndex: Integer);
    procedure ResetCaretBlink;
    procedure ToggleCheck(TagIndex: Integer);

    // Property setters
    procedure SetOptions(Value: TPixieTagBarOptions);
    procedure SetTagShape(Value: TPixieTagShape);
    procedure SetAutoHeight(Value: Boolean);
    procedure SetFontFamily(const Value: string);
    procedure SetEmptyMessage(const Value: string);
    function ShowEmptyMessage: Boolean;
    procedure SetFontSize(Value: Single);
    procedure SetScrollMode(Value: TPixieTagBarScrollMode);
  public
    { Host callbacks — set by wrapper }
    OnHostInvalidate: TPixieTagBarHostNotify;
    OnHostSetCursor: TPixieTagBarHostSetCursor;
    OnHostGetViewWidth: TPixieTagBarHostGetInt;
    OnHostGetViewHeight: TPixieTagBarHostGetInt;
    OnHostGetScaleFactor: TPixieTagBarHostGetFloat;
    OnHostGetCanvasScaleFactor: TPixieTagBarHostGetFloat;
    OnHostGetBackgroundColor: TPixieTagBarHostGetColor;
    OnHostSetFocus: TPixieTagBarHostNotify;
    OnHostIsEnabled: TPixieTagBarHostGetBool;
    OnHostIsFocused: TPixieTagBarHostGetBool;
    OnHostSetViewHeight: TPixieTagBarHostSetInt;
    OnHostSetCaretTimerEnabled: TPixieTagBarHostSetBool;

    constructor Create(ACanvas: TPixieCanvas);
    destructor Destroy; override;

    { Input handlers — called by wrapper }
    procedure HandlePaint(APaintHandle: PtrUInt);
    procedure HandleMouseDown(IsLeft: Boolean; X, Y: Integer);
    procedure HandleMouseUp(IsLeft: Boolean; X, Y: Integer);
    procedure HandleMouseMove(X, Y: Integer);
    procedure HandleMouseLeave;
    function HandleMouseWheel(WheelDelta: Integer; ShiftDown: Boolean): Boolean;
    function HandleKeyDown(var Key: Word; Shift: TShiftState): Boolean;
    function HandleCharInput(const Ch: string): Boolean;
    procedure HandleCaretTimer;
    procedure HandleResize;
    procedure HandleLoaded;
    procedure HandleExit;

    { Tag management }
    function AddTag(const Text: string): Integer; overload;
    function AddTag(const Text: string;
      Color: TPixieWebColor): Integer; overload;
    function AddTag(const Text: string; Color: TPixieWebColor;
      const ALeadIcon, ATrailIcon: string): Integer; overload;
    procedure DeleteTag(ID: Integer);
    procedure ClearTags;
    function FindTag(ID: Integer; out Tag: TPixieTagDef): Boolean;
    procedure UpdateTag(ID: Integer; const NewText: string;
      NewColor: TPixieWebColor); overload;
    procedure UpdateTag(ID: Integer; const NewText: string;
      NewColor: TPixieWebColor;
      const ALeadIcon, ATrailIcon: string); overload;
    function TagCount: Integer;
    function GetTag(Index: Integer): TPixieTagDef;

    { Selection }
    procedure CheckTag(ID: Integer; AChecked: Boolean);
    procedure CheckAll;
    procedure UncheckAll;
    function IsChecked(ID: Integer): Boolean;
    function GetCheckedIDs: TArray<Integer>;

    { Properties }
    property Options: TPixieTagBarOptions read FOptions write SetOptions;
    property TagShape: TPixieTagShape read FTagShape write SetTagShape;
    property AutoHeight: Boolean read FAutoHeight write SetAutoHeight;
    property ScrollMode: TPixieTagBarScrollMode
      read FScrollMode write SetScrollMode;
    property FontFamily: string read FFontFamily write SetFontFamily;
    property FontSize: Single read FFontSize write SetFontSize;
    property ShowBorder: Boolean read FShowBorder write FShowBorder;
    property BorderColor: TPixieWebColor read FBorderColor write FBorderColor;
    property EmptyMessage: string read FEmptyMessage write SetEmptyMessage;

    { Events }
    property OnTagChecked: TPixieTagCheckedEvent
      read FOnTagChecked write FOnTagChecked;
    property OnChanged: TNotifyEvent
      read FOnChanged write FOnChanged;
    property OnTagAdding: TPixieTagAddingEvent
      read FOnTagAdding write FOnTagAdding;
    property OnTagDeleting: TPixieTagDeletingEvent
      read FOnTagDeleting write FOnTagDeleting;
    property OnTagChanging: TPixieTagChangingEvent
      read FOnTagChanging write FOnTagChanging;
  end;

implementation

uses
  Pixie.FontDescription, Pixie.Utf8;

// =========================================================================
// Construction / destruction
// =========================================================================

constructor TPixieTagBarCore.Create(ACanvas: TPixieCanvas);
begin
  inherited Create;
  FCanvas := ACanvas;

  FTags := TPixieTagDefList.Create;
  FChecked := TPixieTagIdSet.Create;
  FLayout := TPixieTagLayoutList.Create;
  FPalette := PixieTagDefaultPalette;

  FNextID := 1;
  FPaletteIndex := 0;
  FOptions := [tboShowAll, tboAllowCheck];
  FTagShape := tsPill;
  FAutoHeight := True;
  FBorderColor := TPixieWebColor.Create($80, $80, $80);
  FFontSize := 13;
  FSpacingH := 6;
  FSpacingV := 6;
  FPadding := 4;

  FFont := 0;
  FFontScale := 0;
  FLayoutValid := False;
  FUpdatingHeight := False;
  FContentHeight := 0;
  FContentWidth := 0;

  FScrollMode := smAuto;
  FScrollX := 0;
  FScrollY := 0;
  FScrollDragging := False;
  FScrollDragAxis := saVertical;
  FScrollDragOffset := 0;

  FHoverIndex := -1;
  FHoverZone := thzNone;
  FPressedIndex := -1;
  FFocusIndex := -1;

  FEditMode := temNone;
  FEditTagIndex := -1;
  FEditCaretPos := 1;
  FEditCaretVisible := False;

  FLastClickTime := 0;
  FLastClickIndex := -1;
end;

destructor TPixieTagBarCore.Destroy;
begin
  if (FFont <> 0) and (FCanvas <> nil) then
    FCanvas.DeleteFont(FFont);
  FreeAndNil(FLayout);
  FreeAndNil(FChecked);
  FreeAndNil(FTags);
  // FCanvas is NOT owned — caller manages its lifetime
  inherited Destroy;
end;

// =========================================================================
// Internal helpers
// =========================================================================

procedure TPixieTagBarCore.RecreateFont;
var
  Descr: TPixieFontDescription;
begin
  if FCanvas = nil then Exit;
  if FFont <> 0 then
    FCanvas.DeleteFont(FFont);
  Descr.Init;
  if FFontFamily <> '' then
    Descr.Family := FFontFamily
  else
  begin
    {$IF DEFINED(MSWINDOWS)}
    Descr.Family := 'Segoe UI';
    {$ELSEIF DEFINED(DARWIN)}
    Descr.Family := 'Helvetica';
    {$ELSE}
    Descr.Family := 'DejaVu Sans';
    {$ENDIF}
  end;
  if Assigned(OnHostGetScaleFactor) then
    FFontScale := OnHostGetScaleFactor
  else
    FFontScale := 1;
  Descr.Size := FFontSize * FFontScale;
  Descr.Weight := 400;
  FFont := FCanvas.CreateFont(Descr, FFontMetrics);
  FLayoutValid := False;
end;

procedure TPixieTagBarCore.InvalidateLayout;
begin
  FLayoutValid := False;
  if Assigned(OnHostInvalidate) then
    OnHostInvalidate;
end;

procedure TPixieTagBarCore.EnsureLayout;
begin
  if not FLayoutValid then
    PerformLayout;
end;

function TPixieTagBarCore.GetPillHeight: Single;
begin
  Result := Round(FFontMetrics.Height * 1.7);
end;

function TPixieTagBarCore.GetPillOptions(IsAddBtn: Boolean): TPixieTagPillOptions;
begin
  Result := [];
  if IsAddBtn then
  begin
    Include(Result, tpoIsAddButton);
    Exit;
  end;
  if tboShowDismiss in FOptions then
    Include(Result, tpoShowDismiss);
  if tboShowColorSwatch in FOptions then
    Include(Result, tpoShowColorSwatch);
end;

function TPixieTagBarCore.GetPillState(TagIndex, LayoutIndex: Integer): TPixieTagPillState;
var
  TagChecked, HostEnabled: Boolean;
begin
  if tboReadOnly in FOptions then
    Exit(tpsRest);

  HostEnabled := True;
  if Assigned(OnHostIsEnabled) then
    HostEnabled := OnHostIsEnabled;
  if not HostEnabled then
    Exit(tpsInactive);

  if (FEditMode = temRename) and (TagIndex = FEditTagIndex) then
    Exit(tpsEditing);

  TagChecked := (tboAlwaysChecked in FOptions) or
    ((TagIndex >= 0) and (TagIndex < FTags.Count) and
     FChecked.ContainsKey(FTags[TagIndex].ID));

  if TagChecked then
  begin
    if LayoutIndex = FPressedIndex then
      Result := tpsCheckedPress
    else if LayoutIndex = FHoverIndex then
      Result := tpsCheckedHover
    else
      Result := tpsChecked;
  end
  else
  begin
    if LayoutIndex = FPressedIndex then
      Result := tpsPress
    else if LayoutIndex = FHoverIndex then
      Result := tpsHover
    else
      Result := tpsRest;
  end;
end;

function TPixieTagBarCore.LayoutHitTest(MX, MY: Integer;
  out Zone: TPixieTagHitZone): Integer;
var
  I: Integer;
  L: TPixieTagPillLayout;
  WX, WY, LocalX, LocalY: Single;
begin
  Zone := thzNone;
  WX := MX + FScrollX;
  WY := MY + FScrollY;
  for I := FLayout.Count - 1 downto 0 do
  begin
    L := FLayout[I];
    LocalX := WX - L.X;
    LocalY := WY - L.Y;
    Zone := HitTestTagPill(LocalX, LocalY, L.Metrics);
    if Zone <> thzNone then
      Exit(I);
  end;
  Result := -1;
end;

function TPixieTagBarCore.NextPaletteColor: TPixieWebColor;
begin
  if Length(FPalette) = 0 then
    FPalette := PixieTagDefaultPalette;
  Result := FPalette[FPaletteIndex mod Length(FPalette)];
  Inc(FPaletteIndex);
end;

function TPixieTagBarCore.FindTagIndex(ID: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to FTags.Count - 1 do
    if FTags[I].ID = ID then
      Exit(I);
  Result := -1;
end;

// =========================================================================
// Scrolling helpers
// =========================================================================

function TPixieTagBarCore.ViewWidth: Single;
begin
  if Assigned(OnHostGetViewWidth) then
    Result := OnHostGetViewWidth
  else
    Result := 300;
end;

function TPixieTagBarCore.ViewHeight: Single;
begin
  if Assigned(OnHostGetViewHeight) then
    Result := OnHostGetViewHeight
  else
    Result := 36;
end;

function TPixieTagBarCore.EffectiveScrollMode: TPixieTagBarScrollMode;
var
  PillH: Single;
begin
  if FAutoHeight then
    Exit(smNone);
  if FScrollMode = smAuto then
  begin
    PillH := GetPillHeight;
    if (PillH > 0) and (ViewHeight < PillH * 1.5) then
      Result := smHorizontal
    else
      Result := smVertical;
  end
  else
    Result := FScrollMode;
end;

function TPixieTagBarCore.ViewExtent(Axis: TPixieTagBarScrollAxis): Single;
begin
  if Axis = saVertical then
    Result := ViewHeight
  else
    Result := ViewWidth;
end;

function TPixieTagBarCore.ContentExtent(Axis: TPixieTagBarScrollAxis): Single;
begin
  if Axis = saVertical then
    Result := FContentHeight
  else
    Result := FContentWidth;
end;

function TPixieTagBarCore.MaxScroll(Axis: TPixieTagBarScrollAxis): Single;
var
  Mode: TPixieTagBarScrollMode;
begin
  Mode := EffectiveScrollMode;
  if ((Axis = saVertical) and (Mode = smVertical)) or
     ((Axis = saHorizontal) and (Mode = smHorizontal)) then
    Result := Max(0, ContentExtent(Axis) - ViewExtent(Axis))
  else
    Result := 0;
end;

function TPixieTagBarCore.HasScrollbar(Axis: TPixieTagBarScrollAxis): Boolean;
begin
  Result := MaxScroll(Axis) > 0.5;
end;

function TPixieTagBarCore.ScrollOffset(Axis: TPixieTagBarScrollAxis): Single;
begin
  if Axis = saVertical then Result := FScrollY else Result := FScrollX;
end;

procedure TPixieTagBarCore.SetScrollOffset(Axis: TPixieTagBarScrollAxis;
  Value: Single);
begin
  if Axis = saVertical then FScrollY := Value else FScrollX := Value;
end;

procedure TPixieTagBarCore.ClampScroll;
var
  MaxX, MaxY: Single;
begin
  MaxX := MaxScroll(saHorizontal);
  MaxY := MaxScroll(saVertical);
  FScrollX := EnsureRange(FScrollX, 0, MaxX);
  FScrollY := EnsureRange(FScrollY, 0, MaxY);
end;

procedure TPixieTagBarCore.ScrollBy(DX, DY: Single);
var
  OldX, OldY: Single;
begin
  OldX := FScrollX;
  OldY := FScrollY;
  FScrollX := FScrollX + DX;
  FScrollY := FScrollY + DY;
  ClampScroll;
  if (FScrollX <> OldX) or (FScrollY <> OldY) then
    if Assigned(OnHostInvalidate) then
      OnHostInvalidate;
end;

procedure TPixieTagBarCore.GetScrollThumb(Axis: TPixieTagBarScrollAxis;
  out TPos, TSize: Single);
var
  Track, Content, View, Off, MaxOff: Single;
begin
  View := ViewExtent(Axis);
  Track := View - tbScrollbarMargin * 2;
  Content := ContentExtent(Axis);
  if Content <= 0 then
  begin
    TPos := tbScrollbarMargin;
    TSize := Track;
    Exit;
  end;
  TSize := Track * (View / Content);
  if TSize < tbScrollbarMinThumb then TSize := tbScrollbarMinThumb;
  if TSize > Track then TSize := Track;
  MaxOff := MaxScroll(Axis);
  Off := ScrollOffset(Axis);
  if MaxOff > 0 then
    TPos := tbScrollbarMargin + (Off / MaxOff) * (Track - TSize)
  else
    TPos := tbScrollbarMargin;
end;

function TPixieTagBarCore.HitScrollbar(Axis: TPixieTagBarScrollAxis;
  MX, MY: Integer; out OnThumb: Boolean; out TPos, TSize: Single): Boolean;
var
  Gutter, MainCoord: Single;
begin
  OnThumb := False;
  TPos := 0;
  TSize := 0;
  if not HasScrollbar(Axis) then Exit(False);
  if Axis = saVertical then
  begin
    Gutter := ViewWidth - tbScrollbarWidth - tbScrollbarMargin;
    Result := MX >= Gutter - tbScrollbarMargin;
    MainCoord := MY;
  end
  else
  begin
    Gutter := ViewHeight - tbScrollbarWidth - tbScrollbarMargin;
    Result := MY >= Gutter - tbScrollbarMargin;
    MainCoord := MX;
  end;
  if not Result then Exit;
  GetScrollThumb(Axis, TPos, TSize);
  OnThumb := (MainCoord >= TPos) and (MainCoord <= TPos + TSize);
end;

procedure TPixieTagBarCore.ScrollPage(Axis: TPixieTagBarScrollAxis;
  Down: Boolean);
var
  Step: Single;
begin
  Step := ViewExtent(Axis);
  if not Down then Step := -Step;
  if Axis = saVertical then
    ScrollBy(0, Step)
  else
    ScrollBy(Step, 0);
end;

function TPixieTagBarCore.ScrollAxisFor(
  Mode: TPixieTagBarScrollMode): TPixieTagBarScrollAxis;
begin
  if Mode = smHorizontal then Result := saHorizontal else Result := saVertical;
end;

// =========================================================================
// Layout engine
// =========================================================================

procedure TPixieTagBarCore.PerformLayout;
var
  I: Integer;
  Tag: TPixieTagDef;
  PillH, Pad, SpH, SpV, MaxW, CurX, CurY, Scale, MaxX: Single;
  PillText: string;
  PillOpts: TPixieTagPillOptions;
  M: TPixieTagPillMetrics;
  L: TPixieTagPillLayout;
  NewH: Integer;
  NoWrap: Boolean;
begin
  FLayout.Clear;
  if (FCanvas = nil) or (FFont = 0) then
  begin
    FLayoutValid := True;
    FContentHeight := 0;
    FContentWidth := 0;
    Exit;
  end;

  if Assigned(OnHostGetScaleFactor) then
    Scale := OnHostGetScaleFactor
  else
    Scale := 1;
  PillH := GetPillHeight;
  Pad := FPadding * Scale;
  SpH := FSpacingH * Scale;
  SpV := FSpacingV * Scale;
  if Assigned(OnHostGetViewWidth) then
    MaxW := OnHostGetViewWidth
  else
    MaxW := 300;

  NoWrap := EffectiveScrollMode = smHorizontal;

  CurX := Pad;
  CurY := Pad;
  MaxX := Pad;

  FEmptyMessageWidth := 0;
  if ShowEmptyMessage then
  begin
    FEmptyMessageWidth := FCanvas.MeasureText(FEmptyMessage, FFont);
    CurX := CurX + FEmptyMessageWidth + SpH;
  end;

  // Visible tags
  for I := 0 to FTags.Count - 1 do
  begin
    Tag := FTags[I];

    // Skip unchecked tags when not showing all
    if not (tboShowAll in FOptions) and not FChecked.ContainsKey(Tag.ID) then
      Continue;

    // Use edit text if renaming this tag
    if (FEditMode = temRename) and (I = FEditTagIndex) then
    begin
      PillText := FEditText;
      PillOpts := GetPillOptions(False) + [tpoEditing];
    end
    else
    begin
      PillText := Tag.Text;
      PillOpts := GetPillOptions(False);
    end;
    M := MeasureTagPill(FCanvas, FFont, PillText,
      Tag.LeadIcon, Tag.TrailIcon, PillH, PillOpts);

    // Wrap to next row if needed (suppressed in horizontal-scroll mode)
    if not NoWrap and
       (CurX + M.TotalWidth > MaxW - Pad) and (CurX > Pad + 0.5) then
    begin
      CurX := Pad;
      CurY := CurY + PillH + SpV;
    end;

    L.X := CurX;
    L.Y := CurY;
    L.TagIndex := I;
    L.IsAddButton := False;
    L.Metrics := M;
    FLayout.Add(L);

    CurX := CurX + M.TotalWidth;
    if CurX > MaxX then MaxX := CurX;
    CurX := CurX + SpH;
  end;

  // Add-new edit pill
  if FEditMode = temAddNew then
  begin
    PillOpts := [tpoEditing];
    M := MeasureTagPill(FCanvas, FFont, FEditText, '', '', PillH, PillOpts);
    // Minimum width for empty text
    if M.TotalWidth < PillH * 1.5 then
    begin
      M.TextWidth := M.TextWidth + (PillH * 1.5 - M.TotalWidth);
      M.TotalWidth := PillH * 1.5;
      M.ContentRect.Width := M.TotalWidth;
    end;

    if not NoWrap and
       (CurX + M.TotalWidth > MaxW - Pad) and (CurX > Pad + 0.5) then
    begin
      CurX := Pad;
      CurY := CurY + PillH + SpV;
    end;

    L.X := CurX;
    L.Y := CurY;
    L.TagIndex := -1;
    L.IsAddButton := False;
    L.Metrics := M;
    FLayout.Add(L);
    CurX := CurX + M.TotalWidth;
    if CurX > MaxX then MaxX := CurX;
    CurX := CurX + SpH;
  end;

  // "+" add button
  if (tboAllowCreate in FOptions) and (FEditMode <> temAddNew) then
  begin
    PillOpts := [tpoIsAddButton];
    M := MeasureTagPill(FCanvas, FFont, '+', '', '', PillH, PillOpts, FTagShape);

    if not NoWrap and
       (CurX + M.TotalWidth > MaxW - Pad) and (CurX > Pad + 0.5) then
    begin
      CurX := Pad;
      CurY := CurY + PillH + SpV;
    end;

    L.X := CurX;
    L.Y := CurY;
    L.TagIndex := -1;
    L.IsAddButton := True;
    L.Metrics := M;
    FLayout.Add(L);
    CurX := CurX + M.TotalWidth;
    if CurX > MaxX then MaxX := CurX;
  end;

  FContentHeight := CurY + PillH + Pad;
  FContentWidth := MaxX + Pad;
  FLayoutValid := True;
  ClampScroll;

  // Auto-height adjustment
  if FAutoHeight and not FUpdatingHeight then
  begin
    NewH := Max(Round(FContentHeight), Round(PillH + 2 * Pad));
    if Assigned(OnHostGetViewHeight) then
    begin
      if Abs(OnHostGetViewHeight - NewH) > 1 then
      begin
        FUpdatingHeight := True;
        try
          if Assigned(OnHostSetViewHeight) then
            OnHostSetViewHeight(NewH);
        finally
          FUpdatingHeight := False;
        end;
      end;
    end;
  end;
end;

// =========================================================================
// Painting
// =========================================================================

procedure TPixieTagBarCore.HandlePaint(APaintHandle: PtrUInt);
var
  I: Integer;
  L: TPixieTagPillLayout;
  PillH, CaretX, CaretY1, CaretY2, OX, OY: Single;
  State: TPixieTagPillState;
  BaseColor: TPixieWebColor;
  PillText: string;
  PillLeadIcon, PillTrailIcon: string;
  PillOpts: TPixieTagPillOptions;
  FocusColor: TPixieWebColor;
  EditIdx: Integer;
  ViewW, ViewH: Integer;
  ScaleFactor, CanvasScale: Single;
  BgColor: TPixieWebColor;
  HostFocused: Boolean;
  ClipPos: TPixiePosition;
  ClipRadius: TPixieBorderRadiuses;
  ThumbX, ThumbY, ThumbW, ThumbH, GutterX, GutterY: Single;
  TrackColor, ThumbColor: TPixieWebColor;
begin
  if FCanvas = nil then Exit;

  // Lazy font creation or scale change
  if Assigned(OnHostGetScaleFactor) then
    ScaleFactor := OnHostGetScaleFactor
  else
    ScaleFactor := 1;
  if (FFont = 0) or (Abs(ScaleFactor - FFontScale) > 0.01) then
    RecreateFont;

  if Assigned(OnHostGetViewWidth) then
    ViewW := OnHostGetViewWidth
  else
    ViewW := 300;
  if Assigned(OnHostGetViewHeight) then
    ViewH := OnHostGetViewHeight
  else
    ViewH := 36;
  if Assigned(OnHostGetCanvasScaleFactor) then
    CanvasScale := OnHostGetCanvasScaleFactor
  else
    CanvasScale := 1;
  if Assigned(OnHostGetBackgroundColor) then
    BgColor := OnHostGetBackgroundColor
  else
    BgColor := TPixieWebColor.White;

  FCanvas.SetViewSize(ViewW, ViewH, CanvasScale);
  FCanvas.BeginPaint(APaintHandle);
  try
    // Background
    FCanvas.FillRect(0, 0, ViewW, ViewH, BgColor);

    // Layout
    EnsureLayout;

    PillH := GetPillHeight;
    EditIdx := -1;

    if ShowEmptyMessage then
      FCanvas.DrawText(FEmptyMessage, FFont,
        PixieTagMutedTextColor(BgColor),
        FPadding * ScaleFactor, (ViewH - FFontMetrics.Height) / 2,
        FEmptyMessageWidth, FFontMetrics.Height);

    // Clip pills + caret + focus ring to the viewport so scrolled content
    // does not draw under the border or the scrollbar gutter.
    OX := -FScrollX;
    OY := -FScrollY;
    ClipPos := TPixiePosition.Create(0, 0, ViewW, ViewH);
    ClipRadius.Init;
    FCanvas.SaveState;
    try
      FCanvas.SetClipRect(ClipPos, ClipRadius);

      // Draw pills
      for I := 0 to FLayout.Count - 1 do
      begin
        L := FLayout[I];

        if L.IsAddButton then
        begin
          BaseColor := TPixieWebColor.Create($60, $7D, $8B);
          PillText := '+';
          PillLeadIcon := '';
          PillTrailIcon := '';
          PillOpts := [tpoIsAddButton];
          if I = FHoverIndex then
            State := tpsHover
          else
            State := tpsRest;
        end
        else if (L.TagIndex = -1) and (FEditMode = temAddNew) then
        begin
          BaseColor := FEditColor;
          PillText := FEditText;
          PillLeadIcon := '';
          PillTrailIcon := '';
          PillOpts := [tpoEditing];
          State := tpsEditing;
          EditIdx := I;
        end
        else if L.TagIndex >= 0 then
        begin
          BaseColor := FTags[L.TagIndex].Color;
          PillLeadIcon := FTags[L.TagIndex].LeadIcon;
          PillTrailIcon := FTags[L.TagIndex].TrailIcon;
          if (FEditMode = temRename) and (L.TagIndex = FEditTagIndex) then
          begin
            PillText := FEditText;
            PillOpts := GetPillOptions(False) + [tpoEditing];
            EditIdx := I;
          end
          else
          begin
            PillText := FTags[L.TagIndex].Text;
            PillOpts := GetPillOptions(False);
          end;
          State := GetPillState(L.TagIndex, I);
        end
        else
          Continue;

        DrawTagPill(FCanvas, FFont, FFontMetrics, PillText,
          PillLeadIcon, PillTrailIcon,
          L.X + OX, L.Y + OY, PillH, BaseColor, BgColor, State, FTagShape,
          PillOpts, L.Metrics);
      end;

      // Caret
      if (FEditMode <> temNone) and FEditCaretVisible and (EditIdx >= 0) then
      begin
        L := FLayout[EditIdx];
        CaretX := L.X + OX + L.Metrics.TextX +
          FCanvas.MeasureText(Copy(FEditText, 1, FEditCaretPos - 1), FFont);
        CaretY1 := L.Y + OY + (PillH - FFontMetrics.Height) / 2;
        CaretY2 := CaretY1 + FFontMetrics.Height;

        if FEditMode = temAddNew then
          BaseColor := FEditColor
        else if (FEditTagIndex >= 0) and (FEditTagIndex < FTags.Count) then
          BaseColor := FTags[FEditTagIndex].Color
        else
          BaseColor := TPixieWebColor.Black;

        FCanvas.DrawLine(CaretX, CaretY1, CaretX, CaretY2,
          PixieTagTextColor(BaseColor, False), 1.0);
      end;

      // Focus ring
      HostFocused := False;
      if Assigned(OnHostIsFocused) then
        HostFocused := OnHostIsFocused;
      if HostFocused and (FFocusIndex >= 0) and (FFocusIndex < FLayout.Count) then
      begin
        L := FLayout[FFocusIndex];
        FocusColor := TPixieWebColor.Create($33, $99, $FF, $AA);
        FCanvas.DrawRect(L.X + OX - 1, L.Y + OY - 1,
          L.Metrics.TotalWidth + 2, PillH + 2, FocusColor, 1.5);
      end;
    finally
      FCanvas.RestoreState;
    end;

    // Scrollbars (overlay, drawn after clip is released)
    if HasScrollbar(saVertical) then
    begin
      TrackColor := PixieScrollbarTrackColor(BgColor);
      ThumbColor := PixieScrollbarThumbColor(BgColor);
      GetScrollThumb(saVertical, ThumbY, ThumbH);
      GutterX := ViewW - tbScrollbarWidth - tbScrollbarMargin;
      FCanvas.FillRect(GutterX, tbScrollbarMargin,
        tbScrollbarWidth, ViewH - tbScrollbarMargin * 2, TrackColor);
      FCanvas.FillRoundedRect(GutterX, ThumbY,
        tbScrollbarWidth, ThumbH, tbScrollbarWidth / 2, ThumbColor);
    end;
    if HasScrollbar(saHorizontal) then
    begin
      TrackColor := PixieScrollbarTrackColor(BgColor);
      ThumbColor := PixieScrollbarThumbColor(BgColor);
      GetScrollThumb(saHorizontal, ThumbX, ThumbW);
      GutterY := ViewH - tbScrollbarWidth - tbScrollbarMargin;
      FCanvas.FillRect(tbScrollbarMargin, GutterY,
        ViewW - tbScrollbarMargin * 2, tbScrollbarWidth, TrackColor);
      FCanvas.FillRoundedRect(ThumbX, GutterY,
        ThumbW, tbScrollbarWidth, tbScrollbarWidth / 2, ThumbColor);
    end;

    // 1px border around entire control
    if FShowBorder then
      FCanvas.DrawRect(0, 0, ViewW, ViewH, FBorderColor, 1.0);
  finally
    FCanvas.EndPaint;
  end;
end;

// =========================================================================
// Mouse handling
// =========================================================================

procedure TPixieTagBarCore.HandleMouseDown(IsLeft: Boolean; X, Y: Integer);
var
  HitIdx: Integer;
  Zone: TPixieTagHitZone;
  L: TPixieTagPillLayout;
  TagIdx, TagID: Integer;
  Allow, OnThumb: Boolean;
  ClickTime: TDateTime;
  Axis: TPixieTagBarScrollAxis;
  TPos, TSize, MainCoord: Single;
begin
  if not IsLeft then Exit;

  if Assigned(OnHostSetFocus) then
    OnHostSetFocus;

  // Scrollbar interaction (active even when read-only)
  for Axis := Low(TPixieTagBarScrollAxis) to High(TPixieTagBarScrollAxis) do
    if HitScrollbar(Axis, X, Y, OnThumb, TPos, TSize) then
    begin
      if OnThumb then
      begin
        FScrollDragging := True;
        FScrollDragAxis := Axis;
        if Axis = saVertical then
          FScrollDragOffset := Y - TPos
        else
          FScrollDragOffset := X - TPos;
      end
      else
      begin
        if Axis = saVertical then MainCoord := Y else MainCoord := X;
        ScrollPage(Axis, MainCoord >= TPos);
      end;
      Exit;
    end;

  if tboReadOnly in FOptions then Exit;

  HitIdx := LayoutHitTest(X, Y, Zone);
  FPressedIndex := HitIdx;

  if HitIdx < 0 then
  begin
    if FEditMode <> temNone then
      CommitEdit;
    if Assigned(OnHostInvalidate) then
      OnHostInvalidate;
    Exit;
  end;

  L := FLayout[HitIdx];
  TagIdx := L.TagIndex;

  // Dismiss button
  if (Zone = thzDismiss) and (TagIdx >= 0) and (TagIdx < FTags.Count) then
  begin
    TagID := FTags[TagIdx].ID;
    Allow := True;
    if Assigned(FOnTagDeleting) then
      FOnTagDeleting(Self, TagID, Allow);
    if Allow then
    begin
      DeleteTag(TagID);
      FPressedIndex := -1;
    end;
    Exit;
  end;

  // Colour dot — cycle colour
  if (Zone = thzLeadIcon) and (tboAllowEdit in FOptions) and
     (TagIdx >= 0) and (TagIdx < FTags.Count) then
  begin
    CycleTagColor(TagIdx);
    FPressedIndex := -1;
    Exit;
  end;

  // "+" add button
  if L.IsAddButton then
  begin
    BeginEdit(temAddNew, -1);
    FPressedIndex := -1;
    Exit;
  end;

  // Double-click detection for rename
  ClickTime := Now;
  if (tboAllowEdit in FOptions) and (TagIdx >= 0) and
     (TagIdx = FLastClickIndex) and
     (MilliSecondsBetween(ClickTime, FLastClickTime) < 400) then
  begin
    BeginEdit(temRename, TagIdx);
    FPressedIndex := -1;
    FLastClickTime := 0;
    Exit;
  end;
  FLastClickTime := ClickTime;
  FLastClickIndex := TagIdx;

  if Assigned(OnHostInvalidate) then
    OnHostInvalidate;
end;

procedure TPixieTagBarCore.HandleMouseUp(IsLeft: Boolean; X, Y: Integer);
var
  HitIdx: Integer;
  Zone: TPixieTagHitZone;
  L: TPixieTagPillLayout;
begin
  if not IsLeft then Exit;

  if FScrollDragging then
  begin
    FScrollDragging := False;
    if Assigned(OnHostInvalidate) then
      OnHostInvalidate;
    Exit;
  end;

  HitIdx := LayoutHitTest(X, Y, Zone);

  // Toggle check if same pill, zone is pill body, and check allowed
  if (HitIdx >= 0) and (HitIdx = FPressedIndex) and (Zone = thzPill) and
     (tboAllowCheck in FOptions) and (FEditMode = temNone) then
  begin
    L := FLayout[HitIdx];
    if (L.TagIndex >= 0) and (L.TagIndex < FTags.Count) and
       not L.IsAddButton then
      ToggleCheck(L.TagIndex);
  end;

  FPressedIndex := -1;
  if Assigned(OnHostInvalidate) then
    OnHostInvalidate;
end;

procedure TPixieTagBarCore.HandleMouseMove(X, Y: Integer);
var
  HitIdx: Integer;
  Zone: TPixieTagHitZone;
  Track, TPos, TSize, NewThumb, NewScroll, MaxOff, MainCoord: Single;
begin
  if FScrollDragging then
  begin
    Track := ViewExtent(FScrollDragAxis) - tbScrollbarMargin * 2;
    GetScrollThumb(FScrollDragAxis, TPos, TSize);
    if FScrollDragAxis = saVertical then MainCoord := Y else MainCoord := X;
    NewThumb := EnsureRange(MainCoord - FScrollDragOffset,
      tbScrollbarMargin, tbScrollbarMargin + Track - TSize);
    MaxOff := MaxScroll(FScrollDragAxis);
    if (Track - TSize) > 0 then
      NewScroll := (NewThumb - tbScrollbarMargin) / (Track - TSize) * MaxOff
    else
      NewScroll := 0;
    if NewScroll <> ScrollOffset(FScrollDragAxis) then
    begin
      SetScrollOffset(FScrollDragAxis, NewScroll);
      if Assigned(OnHostInvalidate) then
        OnHostInvalidate;
    end;
    Exit;
  end;

  HitIdx := LayoutHitTest(X, Y, Zone);

  if (HitIdx <> FHoverIndex) or (Zone <> FHoverZone) then
  begin
    FHoverIndex := HitIdx;
    FHoverZone := Zone;

    if Assigned(OnHostSetCursor) then
    begin
      if (Zone = thzDismiss) or
         ((Zone = thzLeadIcon) and (tboAllowEdit in FOptions)) then
        OnHostSetCursor(pxCurHandPoint)
      else if (HitIdx >= 0) and FLayout[HitIdx].IsAddButton then
        OnHostSetCursor(pxCurHandPoint)
      else
        OnHostSetCursor(pxCurDefault);
    end;

    if Assigned(OnHostInvalidate) then
      OnHostInvalidate;
  end;
end;

procedure TPixieTagBarCore.HandleMouseLeave;
begin
  // Drop any in-flight thumb drag — MouseUp may not fire if the mouse
  // leaves the control before release.
  FScrollDragging := False;
  if FHoverIndex <> -1 then
  begin
    FHoverIndex := -1;
    FHoverZone := thzNone;
    if Assigned(OnHostInvalidate) then
      OnHostInvalidate;
  end;
end;

function TPixieTagBarCore.HandleMouseWheel(WheelDelta: Integer;
  ShiftDown: Boolean): Boolean;
var
  Step: Single;
  Axis: TPixieTagBarScrollAxis;
begin
  Result := False;
  if EffectiveScrollMode = smNone then Exit;

  // Shift inverts the active axis
  Axis := ScrollAxisFor(EffectiveScrollMode);
  if ShiftDown then
    if Axis = saVertical then Axis := saHorizontal else Axis := saVertical;

  if MaxScroll(Axis) <= 0 then Exit;
  Step := -(WheelDelta / 120) * tbScrollWheelStep;
  if Axis = saVertical then ScrollBy(0, Step) else ScrollBy(Step, 0);
  Result := True;
end;

// =========================================================================
// Keyboard handling
// =========================================================================

function TPixieTagBarCore.HandleKeyDown(var Key: Word;
  Shift: TShiftState): Boolean;
var
  OldPos, Idx, TagID: Integer;
  Allow: Boolean;
begin
  Result := False;

  // --- Editing mode ---
  if FEditMode <> temNone then
  begin
    case Key of
      tbVK_RETURN:
        begin
          CommitEdit;
          Result := True;
        end;
      tbVK_ESCAPE:
        begin
          CancelEdit;
          Result := True;
        end;
      tbVK_BACK:
        if FEditCaretPos > 1 then
        begin
          OldPos := FEditCaretPos;
          PrevUtf8Char(FEditText, FEditCaretPos);
          Delete(FEditText, FEditCaretPos, OldPos - FEditCaretPos);
          ResetCaretBlink;
          InvalidateLayout;
          Result := True;
        end;
      tbVK_DELETE:
        if FEditCaretPos <= Length(FEditText) then
        begin
          Idx := FEditCaretPos;
          ReadUtf8Char(FEditText, Idx);
          Delete(FEditText, FEditCaretPos, Idx - FEditCaretPos);
          InvalidateLayout;
          Result := True;
        end;
      tbVK_LEFT:
        if FEditCaretPos > 1 then
        begin
          PrevUtf8Char(FEditText, FEditCaretPos);
          ResetCaretBlink;
          if Assigned(OnHostInvalidate) then
            OnHostInvalidate;
          Result := True;
        end;
      tbVK_RIGHT:
        if FEditCaretPos <= Length(FEditText) then
        begin
          ReadUtf8Char(FEditText, FEditCaretPos);
          ResetCaretBlink;
          if Assigned(OnHostInvalidate) then
            OnHostInvalidate;
          Result := True;
        end;
      tbVK_HOME:
        begin
          FEditCaretPos := 1;
          ResetCaretBlink;
          if Assigned(OnHostInvalidate) then
            OnHostInvalidate;
          Result := True;
        end;
      tbVK_END:
        begin
          FEditCaretPos := Length(FEditText) + 1;
          ResetCaretBlink;
          if Assigned(OnHostInvalidate) then
            OnHostInvalidate;
          Result := True;
        end;
    end;
    Exit;
  end;

  // --- Navigation mode ---
  case Key of
    tbVK_PRIOR:
      if EffectiveScrollMode <> smNone then
      begin
        ScrollPage(ScrollAxisFor(EffectiveScrollMode), False);
        Result := True;
      end;
    tbVK_NEXT:
      if EffectiveScrollMode <> smNone then
      begin
        ScrollPage(ScrollAxisFor(EffectiveScrollMode), True);
        Result := True;
      end;
    tbVK_HOME:
      if (FScrollX <> 0) or (FScrollY <> 0) then
      begin
        ScrollBy(-FScrollX, -FScrollY);
        Result := True;
      end;
    tbVK_END:
      if (MaxScroll(saHorizontal) > 0) or (MaxScroll(saVertical) > 0) then
      begin
        ScrollBy(MaxScroll(saHorizontal) - FScrollX,
          MaxScroll(saVertical) - FScrollY);
        Result := True;
      end;
    tbVK_LEFT:
      if EffectiveScrollMode = smHorizontal then
      begin
        if MaxScroll(saHorizontal) > 0 then
        begin
          ScrollBy(-tbScrollWheelStep, 0);
          Result := True;
        end;
      end
      else if FFocusIndex > 0 then
      begin
        Dec(FFocusIndex);
        if Assigned(OnHostInvalidate) then
          OnHostInvalidate;
        Result := True;
      end;
    tbVK_RIGHT:
      if EffectiveScrollMode = smHorizontal then
      begin
        if MaxScroll(saHorizontal) > 0 then
        begin
          ScrollBy(tbScrollWheelStep, 0);
          Result := True;
        end;
      end
      else if FFocusIndex < FLayout.Count - 1 then
      begin
        Inc(FFocusIndex);
        if Assigned(OnHostInvalidate) then
          OnHostInvalidate;
        Result := True;
      end;
    tbVK_SPACE, tbVK_RETURN:
      if (tboAllowCheck in FOptions) and
         (FFocusIndex >= 0) and (FFocusIndex < FLayout.Count) then
      begin
        Idx := FLayout[FFocusIndex].TagIndex;
        if (Idx >= 0) and (Idx < FTags.Count) and
           not FLayout[FFocusIndex].IsAddButton then
        begin
          ToggleCheck(Idx);
          if Assigned(OnHostInvalidate) then
            OnHostInvalidate;
          Result := True;
        end
        else if FLayout[FFocusIndex].IsAddButton then
        begin
          BeginEdit(temAddNew, -1);
          Result := True;
        end;
      end;
    tbVK_DELETE:
      if (tboShowDismiss in FOptions) and
         (FFocusIndex >= 0) and (FFocusIndex < FLayout.Count) then
      begin
        Idx := FLayout[FFocusIndex].TagIndex;
        if (Idx >= 0) and (Idx < FTags.Count) then
        begin
          TagID := FTags[Idx].ID;
          Allow := True;
          if Assigned(FOnTagDeleting) then
            FOnTagDeleting(Self, TagID, Allow);
          if Allow then
          begin
            DeleteTag(TagID);
            if FFocusIndex >= FLayout.Count then
              FFocusIndex := FLayout.Count - 1;
          end;
          Result := True;
        end;
      end;
    tbVK_F2:
      if (tboAllowEdit in FOptions) and
         (FFocusIndex >= 0) and (FFocusIndex < FLayout.Count) then
      begin
        Idx := FLayout[FFocusIndex].TagIndex;
        if (Idx >= 0) and (Idx < FTags.Count) then
        begin
          BeginEdit(temRename, Idx);
          Result := True;
        end;
      end;
  end;
end;

function TPixieTagBarCore.HandleCharInput(const Ch: string): Boolean;
var
  Len: Integer;
begin
  Result := False;
  if FEditMode = temNone then Exit;
  if (Length(Ch) = 0) or (Ord(Ch[1]) < 32) then Exit;

  Len := Length(Ch);
  Insert(Ch, FEditText, FEditCaretPos);
  Inc(FEditCaretPos, Len);
  ResetCaretBlink;
  InvalidateLayout;
  Result := True;
end;

// =========================================================================
// Caret timer
// =========================================================================

procedure TPixieTagBarCore.HandleCaretTimer;
begin
  if FEditMode <> temNone then
  begin
    FEditCaretVisible := not FEditCaretVisible;
    if Assigned(OnHostInvalidate) then
      OnHostInvalidate;
  end;
end;

// =========================================================================
// Lifecycle handlers
// =========================================================================

procedure TPixieTagBarCore.HandleResize;
begin
  if not FUpdatingHeight then
    InvalidateLayout;
end;

procedure TPixieTagBarCore.HandleLoaded;
begin
  InvalidateLayout;
end;

procedure TPixieTagBarCore.HandleExit;
begin
  if FEditMode <> temNone then
    CommitEdit;
end;

// =========================================================================
// Inline editing
// =========================================================================

procedure TPixieTagBarCore.BeginEdit(Mode: TPixieTagEditMode;
  TagIndex: Integer);
begin
  if FEditMode <> temNone then
    CommitEdit;

  FEditMode := Mode;
  FEditTagIndex := TagIndex;

  case Mode of
    temAddNew:
      begin
        FEditText := '';
        FEditColor := NextPaletteColor;
      end;
    temRename:
      if (TagIndex >= 0) and (TagIndex < FTags.Count) then
      begin
        FEditText := FTags[TagIndex].Text;
        FEditColor := FTags[TagIndex].Color;
      end;
  end;

  FEditCaretPos := Length(FEditText) + 1;
  FEditCaretVisible := True;
  if Assigned(OnHostSetCaretTimerEnabled) then
    OnHostSetCaretTimerEnabled(True);
  InvalidateLayout;
end;

procedure TPixieTagBarCore.CommitEdit;
var
  Allow: Boolean;
  Tag: TPixieTagDef;
  TrimmedText: string;
begin
  if FEditMode = temNone then Exit;

  TrimmedText := Trim(FEditText);

  case FEditMode of
    temAddNew:
      if TrimmedText <> '' then
      begin
        Allow := True;
        if Assigned(FOnTagAdding) then
          FOnTagAdding(Self, TrimmedText, FEditColor, Allow);
        if Allow then
          AddTag(TrimmedText, FEditColor);
      end;
    temRename:
      if (FEditTagIndex >= 0) and (FEditTagIndex < FTags.Count) and
         (TrimmedText <> '') then
      begin
        Allow := True;
        if Assigned(FOnTagChanging) then
          FOnTagChanging(Self, FTags[FEditTagIndex].ID,
            TrimmedText, FTags[FEditTagIndex].Color, Allow);
        if Allow then
        begin
          Tag := FTags[FEditTagIndex];
          Tag.Text := TrimmedText;
          FTags[FEditTagIndex] := Tag;
          if Assigned(FOnChanged) then
            FOnChanged(Self);
        end;
      end;
  end;

  FEditMode := temNone;
  FEditTagIndex := -1;
  FEditText := '';
  if Assigned(OnHostSetCaretTimerEnabled) then
    OnHostSetCaretTimerEnabled(False);
  FEditCaretVisible := False;
  InvalidateLayout;
end;

procedure TPixieTagBarCore.CancelEdit;
begin
  FEditMode := temNone;
  FEditTagIndex := -1;
  FEditText := '';
  if Assigned(OnHostSetCaretTimerEnabled) then
    OnHostSetCaretTimerEnabled(False);
  FEditCaretVisible := False;
  InvalidateLayout;
end;

procedure TPixieTagBarCore.ResetCaretBlink;
begin
  FEditCaretVisible := True;
  if Assigned(OnHostSetCaretTimerEnabled) then
  begin
    OnHostSetCaretTimerEnabled(False);
    OnHostSetCaretTimerEnabled(True);
  end;
end;

procedure TPixieTagBarCore.ToggleCheck(TagIndex: Integer);
var
  TagID: Integer;
  WasChecked: Boolean;
begin
  if (TagIndex < 0) or (TagIndex >= FTags.Count) then Exit;
  TagID := FTags[TagIndex].ID;
  WasChecked := FChecked.ContainsKey(TagID);
  if WasChecked then
    FChecked.Remove(TagID)
  else
    FChecked.AddOrSetValue(TagID, True);
  if Assigned(FOnTagChecked) then
    FOnTagChecked(Self, TagID, not WasChecked);
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TPixieTagBarCore.CycleTagColor(TagIndex: Integer);
var
  Tag: TPixieTagDef;
  I, BestIdx: Integer;
  Dist, BestDist: Single;
  NewColor: TPixieWebColor;
  Allow: Boolean;
begin
  if (TagIndex < 0) or (TagIndex >= FTags.Count) then Exit;

  Tag := FTags[TagIndex];

  // Find closest palette colour
  if Length(FPalette) = 0 then
    FPalette := PixieTagDefaultPalette;

  BestIdx := 0;
  BestDist := MaxSingle;
  for I := 0 to High(FPalette) do
  begin
    Dist := Sqr(Tag.Color.Red - FPalette[I].Red) +
            Sqr(Tag.Color.Green - FPalette[I].Green) +
            Sqr(Tag.Color.Blue - FPalette[I].Blue);
    if Dist < BestDist then
    begin
      BestDist := Dist;
      BestIdx := I;
    end;
  end;

  // Advance to next
  NewColor := FPalette[(BestIdx + 1) mod Length(FPalette)];

  Allow := True;
  if Assigned(FOnTagChanging) then
    FOnTagChanging(Self, Tag.ID, Tag.Text, NewColor, Allow);
  if Allow then
  begin
    Tag.Color := NewColor;
    FTags[TagIndex] := Tag;
    if Assigned(FOnChanged) then
      FOnChanged(Self);
    if Assigned(OnHostInvalidate) then
      OnHostInvalidate;
  end;
end;

// =========================================================================
// Property setters
// =========================================================================

procedure TPixieTagBarCore.SetOptions(Value: TPixieTagBarOptions);
begin
  if FOptions <> Value then
  begin
    FOptions := Value;
    InvalidateLayout;
  end;
end;

procedure TPixieTagBarCore.SetTagShape(Value: TPixieTagShape);
begin
  if FTagShape <> Value then
  begin
    FTagShape := Value;
    InvalidateLayout;
  end;
end;

procedure TPixieTagBarCore.SetAutoHeight(Value: Boolean);
begin
  if FAutoHeight <> Value then
  begin
    FAutoHeight := Value;
    InvalidateLayout;
  end;
end;

procedure TPixieTagBarCore.SetScrollMode(Value: TPixieTagBarScrollMode);
begin
  if FScrollMode <> Value then
  begin
    FScrollMode := Value;
    FScrollX := 0;
    FScrollY := 0;
    InvalidateLayout;
  end;
end;

procedure TPixieTagBarCore.SetEmptyMessage(const Value: string);
begin
  if FEmptyMessage <> Value then
  begin
    FEmptyMessage := Value;
    InvalidateLayout;
  end;
end;

function TPixieTagBarCore.ShowEmptyMessage: Boolean;
begin
  Result := (FTags.Count = 0) and (FEmptyMessage <> '') and
    (FEditMode <> temAddNew);
end;

procedure TPixieTagBarCore.SetFontFamily(const Value: string);
begin
  if FFontFamily <> Value then
  begin
    FFontFamily := Value;
    if FFont <> 0 then
    begin
      RecreateFont;
      if Assigned(OnHostInvalidate) then
        OnHostInvalidate;
    end;
  end;
end;

procedure TPixieTagBarCore.SetFontSize(Value: Single);
begin
  if FFontSize <> Value then
  begin
    FFontSize := Value;
    if FFont <> 0 then
    begin
      RecreateFont;
      if Assigned(OnHostInvalidate) then
        OnHostInvalidate;
    end;
  end;
end;

// =========================================================================
// Public API — Tag management
// =========================================================================

function TPixieTagBarCore.AddTag(const Text: string): Integer;
begin
  Result := AddTag(Text, NextPaletteColor);
end;

function TPixieTagBarCore.AddTag(const Text: string;
  Color: TPixieWebColor): Integer;
begin
  Result := AddTag(Text, Color, '', '');
end;

function TPixieTagBarCore.AddTag(const Text: string; Color: TPixieWebColor;
  const ALeadIcon, ATrailIcon: string): Integer;
var
  Tag: TPixieTagDef;
begin
  Tag.ID := FNextID;
  Inc(FNextID);
  Tag.Text := Text;
  Tag.Color := Color;
  Tag.LeadIcon := ALeadIcon;
  Tag.TrailIcon := ATrailIcon;
  FTags.Add(Tag);
  Result := Tag.ID;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
  InvalidateLayout;
end;

procedure TPixieTagBarCore.DeleteTag(ID: Integer);
var
  I: Integer;
begin
  I := FindTagIndex(ID);
  if I >= 0 then
  begin
    FTags.Delete(I);
    FChecked.Remove(ID);
    if Assigned(FOnChanged) then
      FOnChanged(Self);
    InvalidateLayout;
  end;
end;

procedure TPixieTagBarCore.ClearTags;
begin
  FTags.Clear;
  FChecked.Clear;
  FNextID := 1;
  FPaletteIndex := 0;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
  InvalidateLayout;
end;

function TPixieTagBarCore.FindTag(ID: Integer;
  out Tag: TPixieTagDef): Boolean;
var
  I: Integer;
begin
  I := FindTagIndex(ID);
  Result := I >= 0;
  if Result then
    Tag := FTags[I];
end;

procedure TPixieTagBarCore.UpdateTag(ID: Integer; const NewText: string;
  NewColor: TPixieWebColor);
var
  I: Integer;
  Tag: TPixieTagDef;
begin
  I := FindTagIndex(ID);
  if I >= 0 then
  begin
    Tag := FTags[I];
    Tag.Text := NewText;
    Tag.Color := NewColor;
    FTags[I] := Tag;
    if Assigned(FOnChanged) then
      FOnChanged(Self);
    InvalidateLayout;
  end;
end;

procedure TPixieTagBarCore.UpdateTag(ID: Integer; const NewText: string;
  NewColor: TPixieWebColor; const ALeadIcon, ATrailIcon: string);
var
  I: Integer;
  Tag: TPixieTagDef;
begin
  I := FindTagIndex(ID);
  if I >= 0 then
  begin
    Tag := FTags[I];
    Tag.Text := NewText;
    Tag.Color := NewColor;
    Tag.LeadIcon := ALeadIcon;
    Tag.TrailIcon := ATrailIcon;
    FTags[I] := Tag;
    if Assigned(FOnChanged) then
      FOnChanged(Self);
    InvalidateLayout;
  end;
end;

function TPixieTagBarCore.TagCount: Integer;
begin
  Result := FTags.Count;
end;

function TPixieTagBarCore.GetTag(Index: Integer): TPixieTagDef;
begin
  if (Index < 0) or (Index >= FTags.Count) then
    raise ERangeError.CreateFmt('TPixieTagBarCore.GetTag: index %d out of range (0..%d)',
      [Index, FTags.Count - 1]);
  Result := FTags[Index];
end;

// =========================================================================
// Public API — Selection
// =========================================================================

procedure TPixieTagBarCore.CheckTag(ID: Integer; AChecked: Boolean);
begin
  if FindTagIndex(ID) < 0 then Exit;
  if AChecked then
    FChecked.AddOrSetValue(ID, True)
  else
    FChecked.Remove(ID);
  InvalidateLayout;
end;

procedure TPixieTagBarCore.CheckAll;
var
  I: Integer;
begin
  for I := 0 to FTags.Count - 1 do
    FChecked.AddOrSetValue(FTags[I].ID, True);
  InvalidateLayout;
end;

procedure TPixieTagBarCore.UncheckAll;
begin
  FChecked.Clear;
  InvalidateLayout;
end;

function TPixieTagBarCore.IsChecked(ID: Integer): Boolean;
begin
  Result := FChecked.ContainsKey(ID);
end;

function TPixieTagBarCore.GetCheckedIDs: TArray<Integer>;
var
  I, Count: Integer;
begin
  SetLength(Result, FChecked.Count);
  Count := 0;
  for I := 0 to FTags.Count - 1 do
    if FChecked.ContainsKey(FTags[I].ID) then
    begin
      Result[Count] := FTags[I].ID;
      Inc(Count);
    end;
  SetLength(Result, Count);
end;

end.
