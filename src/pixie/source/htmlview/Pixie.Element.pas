unit Pixie.Element;

// Abstract DOM element base class.
//
// This is the base class for all DOM nodes. It holds:
//  - parent/children references (non-owning)
//  - CSS properties (owned)
//  - render item list (Pointer for Phase 5)
//  - used selector tracking
//  - counter values
// The document owns all element instances; elements do not free each other.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections,
  Pixie.Types, Pixie.StringId, Pixie.Utils,
  Pixie.CssProperties, Pixie.Style,
  Pixie.CssSelector, Pixie.Stylesheet,
  Pixie.Container, Pixie.Background;

type
  TPixieElement = class;
  TPixieElementList = TObjectList<TPixieElement>;
  TPixiePointerList = TList<Pointer>;
  TPixieIntIntMap = TDictionary<Integer, Integer>;

  { TPixieElement }

  TPixieElement = class
  protected
    FParent: TPixieElement;
    FDoc: TObject;
    FChildren: TPixieElementList;
    FCss: TPixieCssProperties;
    FRenders: TPixiePointerList;
    FUsedStyles: TPixieUsedSelectorList;
    FCounterValues: TPixieIntIntMap;

    function AddBeforeAfter(IsBefore: Boolean): TPixieElement;

  private
    function GetSiblingsBefore: TPixieElementList;
    function FindCounter(CounterNameId: Integer;
      out FoundEl: TPixieElement; out FoundValue: Integer): Boolean;
  public
    procedure SelectAll(const Selector: TPixieCssSelector;
      Res: TPixieElementList); virtual;
    constructor Create(ADoc: TObject);
    destructor Destroy; override;

    // CSS properties
    function Css: TPixieCssProperties; inline;
    function CssW: TPixieCssProperties; inline;

    // Flow/display helpers
    function InNormalFlow: Boolean; inline;
    function IsInline: Boolean;
    function IsInlineBox: Boolean;
    function IsBlockBox: Boolean;
    function IsPositioned: Boolean; inline;
    function IsFloat_: Boolean; inline;
    function IsBlockFormattingContext: Boolean;
    function IsRoot: Boolean; inline;
    function IsTableSkip: Boolean;

    // Navigation
    function Parent: TPixieElement; inline;
    procedure SetParent(El: TPixieElement); inline;
    function GetDocument: TObject; inline;
    function Children: TPixieElementList; inline;

    // Virtual methods — stubs in base class
    function AppendChild(El: TPixieElement): Boolean; virtual;
    function InsertBefore(NewChild, RefChild: TPixieElement): Boolean; virtual;
    function RemoveChild(El: TPixieElement): Boolean; virtual;
    procedure ClearRecursive; virtual;

    function GetId: Integer; virtual;
    function GetTag: Integer; virtual;
    function GetTagName: string; virtual;
    procedure SetTagName(const ATag: string); virtual;
    procedure SetData(const AData: string); virtual;
    procedure SetAttr(const AName, AVal: string); virtual;
    function GetAttr(const AName: string;
      const ADef: string = ''): string; virtual;

    procedure ApplyStylesheet(
      Stylesheet: TPixieStylesheet); virtual;
    procedure RefreshStyles; virtual;
    procedure ComputeStyles(Recursive: Boolean = True); virtual;

    function Select(const SelectorList: TPixieCssSelectorList;
      ApplyPseudo: Boolean = True): Integer; virtual;
    function SelectSel(const Selector: TPixieCssSelector;
      ApplyPseudo: Boolean = True): Integer; virtual;
    function SelectCompound(
      const Selector: TPixieCompoundSelector;
      ApplyPseudo: Boolean = True): Integer; virtual;

    function FindAncestor(const Selector: TPixieCssSelector;
      ApplyPseudo: Boolean = True;
      IsPseudo: PBoolean = nil): TPixieElement; virtual;
    function IsAncestor(El: TPixieElement): Boolean; virtual;
    function FindAdjacentSibling(El: TPixieElement;
      const Selector: TPixieCssSelector;
      ApplyPseudo: Boolean = True;
      IsPseudo: PBoolean = nil): TPixieElement; virtual;
    function FindSibling(El: TPixieElement;
      const Selector: TPixieCssSelector;
      ApplyPseudo: Boolean = True;
      IsPseudo: PBoolean = nil): TPixieElement; virtual;

    function SetPseudoClass(Cls: Integer;
      Add: Boolean): Boolean; virtual;
    function IsWhiteSpace: Boolean; virtual;
    function IsSpace: Boolean; virtual;
    function IsComment: Boolean; virtual;
    function IsBody: Boolean; virtual;
    function IsBreak: Boolean; virtual;
    function IsText: Boolean; virtual;
    function IsReplaced: Boolean; virtual;

    function OnMouseOver: Boolean; virtual;
    function OnMouseLeave: Boolean; virtual;
    function OnLButtonDown: Boolean; virtual;
    function OnLButtonUp(IsClick: Boolean = True): Boolean; virtual;
    function OnLButtonDblClick: Boolean; virtual;
    procedure OnClick; virtual;

    // Focus and keyboard
    procedure OnFocus; virtual;
    procedure OnBlur; virtual;
    function OnKeyDown(Key: Word; Shift: TShiftState): Boolean; virtual;
    function OnUTF8KeyPress(const UTF8Char: string): Boolean; virtual;
    function IsFocusable: Boolean; virtual;
    function OnMouseDrag(X, Y: TPixiePixel): Boolean; virtual;
    function OnMouseWheel(Delta: Integer): Boolean; virtual;
    // CSS cursor for a document point; overridable for sub-element regions.
    function CursorForPoint(DocX, DocY: TPixiePixel): string; virtual;

    procedure GetText(var Text: string); virtual;
    function GetDisplayText: string; virtual;
    function GetTextContent: string; virtual;
    procedure SetTextContent(const AText: string); virtual;
    procedure ParseAttributes; virtual;
    procedure GetContentSize(var Sz: TPixieSize;
      MaxWidth: TPixiePixel); virtual;
    procedure AddStyle(const AStyle: TPixieStyle); virtual;
    procedure Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
      Clip: PPixiePosition; Ri: Pointer); virtual;
    procedure DrawBackground(Hdc: PtrUInt; X, Y: TPixiePixel;
      Clip: PPixiePosition; Ri: Pointer); virtual;

    function IsNthChild(El: TPixieElement; Num, Off: Integer;
      OfType: Boolean;
      SelectorList: TPixieCssSelectorList = nil): Boolean; virtual;
    function IsNthLastChild(El: TPixieElement; Num, Off: Integer;
      OfType: Boolean;
      SelectorList: TPixieCssSelectorList = nil): Boolean; virtual;
    function IsOnlyChild(El: TPixieElement;
      OfType: Boolean): Boolean; virtual;
    function GetBackground(
      OwnOnly: Boolean = False): TPixieBackground; virtual;

    function CreateRenderItem(ParentRi: Pointer): Pointer; virtual;

    // Pseudo-elements
    function AddPseudoBefore: TPixieElement;
    function AddPseudoAfter: TPixieElement;

    // Counters
    function GetCounterValue(
      const CounterName: string;
      const CounterStyle: string = ''): string;
    function GetCountersValue(
      const Params: TPixieStringVector): string;
    procedure IncrementCounter(CounterNameId: Integer;
      Increment: Integer = 1);
    procedure ResetCounter(CounterNameId: Integer;
      Value: Integer = 0);

    // Render tracking
    procedure AddRender(Ri: Pointer);
    procedure ClearRenders;
    function GetRenderItem: Pointer;
    procedure ClearUsedStyles;
    procedure ResetStyle; virtual;
    procedure ClearCounterValues;
    function RequiresStylesUpdate: Boolean;
    function FindStylesChanges(
      RedrawBoxes: TPixiePositionVector): Boolean;

    // Dump
    function DumpGetName: string; virtual;

    // Used styles access (for refresh)
    property UsedStyles: TPixieUsedSelectorList read FUsedStyles;
    property CounterValues: TPixieIntIntMap
      read FCounterValues;
  end;

  TPixieCreateBeforeAfterFunc = function(ADoc: TObject;
    IsBefore: Boolean): TPixieElement;

var
  PixieCreateBeforeAfterFunc: TPixieCreateBeforeAfterFunc;

implementation

uses
  Pixie.Document, Pixie.RenderItem, Pixie.RenderBlock,
  Pixie.RenderInline, Pixie.RenderImage, Pixie.RenderTable,
  Pixie.RenderFlex, Pixie.RenderGrid, Pixie.NumCvt;

function FormatCounterValue(Value: Integer;
  const Style: string): string;
var
  Idx: Integer;
begin
  if Style = '' then
    Exit(IntToStr(Value));
  Idx := PixieValueIndex(Style, ListStyleTypeStrings);
  if Idx >= 0 then
    Result := PixieFormatListCounter(Value, TPixieListStyleType(Idx))
  else
    Result := IntToStr(Value);
end;

{ TPixieElement }

constructor TPixieElement.Create(ADoc: TObject);
begin
  inherited Create;
  FDoc := ADoc;
  FParent := nil;
  FChildren := TPixieElementList.Create(False); // non-owning
  FCss := TPixieCssProperties.Create;
  FRenders := TPixiePointerList.Create;
  FUsedStyles := nil;
  FCounterValues := nil;
end;

destructor TPixieElement.Destroy;
begin
  FCounterValues.Free;
  FUsedStyles.Free;
  FRenders.Free;
  FCss.Free;
  FChildren.Free;
  inherited Destroy;
end;

function TPixieElement.Css: TPixieCssProperties;
begin
  Result := FCss;
end;

function TPixieElement.CssW: TPixieCssProperties;
begin
  Result := FCss;
end;

// Inline helper functions

function TPixieElement.InNormalFlow: Boolean;
begin
  Result := (FCss.Display <> displayNone) and
            (not (FCss.ElPosition in [epAbsolute, epFixed]));
end;

function TPixieElement.IsInline: Boolean;
begin
  Result := FCss.Display in [displayInline, displayInlineTable,
    displayInlineBlock, displayInlineText, displayInlineFlex,
    displayInlineGrid];
end;

function TPixieElement.IsInlineBox: Boolean;
begin
  Result := FCss.Display in [displayInlineTable, displayInlineBlock,
    displayInlineFlex, displayInlineGrid];
end;

function TPixieElement.IsBlockBox: Boolean;
begin
  Result := FCss.Display in [displayBlock, displayFlex, displayGrid,
    displayFlowRoot, displayTable, displayListItem];
end;

function TPixieElement.IsPositioned: Boolean;
begin
  Result := FCss.ElPosition > epStatic;
end;

function TPixieElement.IsFloat_: Boolean;
begin
  Result := FCss.Float_ <> efNone;
end;

function TPixieElement.IsBlockFormattingContext: Boolean;
var
  Par: TPixieElement;
begin
  if FCss.Display = displayBlock then
  begin
    Par := Parent;
    if (Par <> nil) and
       (Par.Css.Display in [displayInlineFlex, displayFlex, displayGrid,
        displayInlineGrid]) then
      Exit(True);
  end;
  if (FCss.Display in [displayInlineBlock, displayTableCell,
        displayInlineFlex, displayFlex, displayGrid, displayInlineGrid,
        displayFlowRoot, displayTableCaption]) or
     IsRoot or
     (FCss.Float_ <> efNone) or
     (FCss.ElPosition in [epAbsolute, epFixed]) or
     (FCss.Overflow > ovVisible) then
    Exit(True);
  Result := False;
end;

function TPixieElement.IsRoot: Boolean;
begin
  Result := FParent = nil;
end;

function TPixieElement.IsTableSkip: Boolean;
begin
  Result := IsSpace or IsComment or (FCss.Display = displayNone);
end;

function TPixieElement.Parent: TPixieElement;
begin
  Result := FParent;
end;

procedure TPixieElement.SetParent(El: TPixieElement);
begin
  FParent := El;
end;

function TPixieElement.GetDocument: TObject;
begin
  Result := FDoc;
end;

function TPixieElement.Children: TPixieElementList;
begin
  Result := FChildren;
end;

// Virtual stubs — base class returns default values

function TPixieElement.AppendChild(El: TPixieElement): Boolean;
begin
  Result := False;
end;

function TPixieElement.InsertBefore(NewChild,
  RefChild: TPixieElement): Boolean;
begin
  Result := False;
end;

function TPixieElement.RemoveChild(El: TPixieElement): Boolean;
begin
  Result := False;
end;

procedure TPixieElement.ClearRecursive;
begin
end;

function TPixieElement.GetId: Integer;
begin
  Result := -1;
end;

function TPixieElement.GetTag: Integer;
begin
  Result := -1;
end;

function TPixieElement.GetTagName: string;
begin
  Result := '';
end;

procedure TPixieElement.SetTagName(const ATag: string);
begin
end;

procedure TPixieElement.SetData(const AData: string);
begin
end;

procedure TPixieElement.SetAttr(const AName, AVal: string);
begin
end;

function TPixieElement.GetAttr(const AName: string;
  const ADef: string): string;
begin
  Result := ADef;
end;

procedure TPixieElement.ApplyStylesheet(Stylesheet: TPixieStylesheet);
begin
end;

procedure TPixieElement.RefreshStyles;
begin
end;

procedure TPixieElement.ComputeStyles(Recursive: Boolean);
begin
end;

function TPixieElement.Select(
  const SelectorList: TPixieCssSelectorList;
  ApplyPseudo: Boolean): Integer;
begin
  Result := SelectNoMatch;
end;

function TPixieElement.SelectSel(const Selector: TPixieCssSelector;
  ApplyPseudo: Boolean): Integer;
begin
  Result := SelectNoMatch;
end;

function TPixieElement.SelectCompound(
  const Selector: TPixieCompoundSelector;
  ApplyPseudo: Boolean): Integer;
begin
  Result := SelectNoMatch;
end;

function TPixieElement.FindAncestor(const Selector: TPixieCssSelector;
  ApplyPseudo: Boolean; IsPseudo: PBoolean): TPixieElement;
begin
  Result := nil;
end;

function TPixieElement.IsAncestor(El: TPixieElement): Boolean;
var
  Par: TPixieElement;
begin
  Par := Parent;
  while (Par <> nil) and (Par <> El) do
    Par := Par.Parent;
  Result := Par <> nil;
end;

function TPixieElement.FindAdjacentSibling(El: TPixieElement;
  const Selector: TPixieCssSelector; ApplyPseudo: Boolean;
  IsPseudo: PBoolean): TPixieElement;
begin
  Result := nil;
end;

function TPixieElement.FindSibling(El: TPixieElement;
  const Selector: TPixieCssSelector; ApplyPseudo: Boolean;
  IsPseudo: PBoolean): TPixieElement;
begin
  Result := nil;
end;

function TPixieElement.SetPseudoClass(Cls: Integer;
  Add: Boolean): Boolean;
begin
  Result := False;
end;

function TPixieElement.IsWhiteSpace: Boolean;
begin
  Result := False;
end;

function TPixieElement.IsSpace: Boolean;
begin
  Result := False;
end;

function TPixieElement.IsComment: Boolean;
begin
  Result := False;
end;

function TPixieElement.IsBody: Boolean;
begin
  Result := False;
end;

function TPixieElement.IsBreak: Boolean;
begin
  Result := False;
end;

function TPixieElement.IsText: Boolean;
begin
  Result := False;
end;

function TPixieElement.IsReplaced: Boolean;
begin
  Result := False;
end;

function TPixieElement.OnMouseOver: Boolean;
begin
  Result := False;
end;

function TPixieElement.OnMouseLeave: Boolean;
begin
  Result := False;
end;

function TPixieElement.OnLButtonDown: Boolean;
begin
  Result := False;
end;

function TPixieElement.OnLButtonUp(IsClick: Boolean): Boolean;
begin
  Result := False;
end;

function TPixieElement.OnLButtonDblClick: Boolean;
begin
  Result := False;
end;

procedure TPixieElement.OnClick;
begin
end;

procedure TPixieElement.OnFocus;
begin
end;

procedure TPixieElement.OnBlur;
begin
end;

function TPixieElement.OnKeyDown(Key: Word; Shift: TShiftState): Boolean;
begin
  Result := False;
end;

function TPixieElement.OnUTF8KeyPress(const UTF8Char: string): Boolean;
begin
  Result := False;
end;

function TPixieElement.IsFocusable: Boolean;
begin
  Result := False;
end;

function TPixieElement.OnMouseDrag(X, Y: TPixiePixel): Boolean;
begin
  Result := False;
end;

function TPixieElement.OnMouseWheel(Delta: Integer): Boolean;
begin
  Result := False;
end;

function TPixieElement.CursorForPoint(DocX, DocY: TPixiePixel): string;
begin
  Result := Css.Cursor;
end;

procedure TPixieElement.GetText(var Text: string);
begin
end;

function TPixieElement.GetDisplayText: string;
begin
  Result := '';
end;

function TPixieElement.GetTextContent: string;
begin
  Result := '';
  GetText(Result);
end;

procedure TPixieElement.SetTextContent(const AText: string);
begin
  // Base class stub — overridden in TPixieHtmlTag
end;

procedure TPixieElement.ParseAttributes;
begin
end;

procedure TPixieElement.GetContentSize(var Sz: TPixieSize;
  MaxWidth: TPixiePixel);
begin
end;

procedure TPixieElement.AddStyle(const AStyle: TPixieStyle);
begin
end;

procedure TPixieElement.Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
  Clip: PPixiePosition; Ri: Pointer);
begin
end;

procedure TPixieElement.DrawBackground(Hdc: PtrUInt; X, Y: TPixiePixel;
  Clip: PPixiePosition; Ri: Pointer);
begin
end;

function TPixieElement.IsNthChild(El: TPixieElement;
  Num, Off: Integer; OfType: Boolean;
  SelectorList: TPixieCssSelectorList): Boolean;
begin
  Result := False;
end;

function TPixieElement.IsNthLastChild(El: TPixieElement;
  Num, Off: Integer; OfType: Boolean;
  SelectorList: TPixieCssSelectorList): Boolean;
begin
  Result := False;
end;

function TPixieElement.IsOnlyChild(El: TPixieElement;
  OfType: Boolean): Boolean;
begin
  Result := False;
end;

function TPixieElement.GetBackground(OwnOnly: Boolean): TPixieBackground;
begin
  Result := nil;
end;

function TPixieElement.CreateRenderItem(ParentRi: Pointer): Pointer;
var
  Ret: TPixieRenderItem;
  Disp: TPixieDisplay;
  I: Integer;
  ChildRi: TPixieRenderItem;
  Doc: TPixieDocument;
begin
  Ret := nil;
  Disp := FCss.Display;

  case Disp of
    displayTableColumn, displayTableColumnGroup,
    displayTableFooterGroup, displayTableHeaderGroup,
    displayTableRowGroup:
      Ret := TPixieRenderTablePart.Create(Self);
    displayTableRow:
      Ret := TPixieRenderTableRow.Create(Self);
    displayBlock, displayTableCell, displayTableCaption,
    displayListItem, displayInlineBlock, displayFlowRoot:
      Ret := TPixieRenderBlock.Create(Self);
    displayTable, displayInlineTable:
      Ret := TPixieRenderTable.Create(Self);
    displayInline, displayInlineText:
      Ret := TPixieRenderInline.Create(Self);
    displayFlex, displayInlineFlex:
      Ret := TPixieRenderFlex.Create(Self);
    displayGrid, displayInlineGrid:
      Ret := PixieRenderGridClass.Create(Self);
  end;

  if Ret <> nil then
  begin
    // Register tabular elements
    if Disp in [displayTable, displayInlineTable,
      displayTableCaption, displayTableCell,
      displayTableColumn, displayTableColumnGroup,
      displayTableFooterGroup, displayTableHeaderGroup,
      displayTableRow, displayTableRowGroup] then
    begin
      Assert(FDoc is TPixieDocument);
      Doc := TPixieDocument(FDoc);
      Doc.AddTabular(Ret);
    end;

    if ParentRi <> nil then
      Assert(TObject(ParentRi) is TPixieRenderItem);
    Ret.SetParent(TPixieRenderItem(ParentRi));
    for I := 0 to FChildren.Count - 1 do
    begin
      ChildRi := TPixieRenderItem(FChildren[I].CreateRenderItem(Ret));
      if ChildRi <> nil then
        Ret.AddChild(ChildRi);
    end;
  end;
  Result := Ret;
end;

function TPixieElement.DumpGetName: string;
begin
  Result := 'element';
end;

// Pseudo-element helpers

function TPixieElement.AddPseudoBefore: TPixieElement;
begin
  Result := AddBeforeAfter(True);
end;

function TPixieElement.AddPseudoAfter: TPixieElement;
begin
  Result := AddBeforeAfter(False);
end;

function TPixieElement.AddBeforeAfter(
  IsBefore: Boolean): TPixieElement;
begin
  if not Assigned(PixieCreateBeforeAfterFunc) then
    Exit(nil);
  Result := PixieCreateBeforeAfterFunc(FDoc, IsBefore);
  if Result = nil then
    Exit;
  if IsBefore and (FChildren.Count > 0) then
    InsertBefore(Result, FChildren[0])
  else
    AppendChild(Result);
end;

// Counter implementation

function TPixieElement.GetCounterValue(
  const CounterName: string;
  const CounterStyle: string): string;
var
  FoundEl: TPixieElement;
  FoundValue: Integer;
begin
  if FindCounter(PixieId(CounterName), FoundEl, FoundValue) then
    Result := FormatCounterValue(FoundValue, CounterStyle)
  else
    Result := FormatCounterValue(0, CounterStyle);
end;

function TPixieElement.GetCountersValue(
  const Params: TPixieStringVector): string;
var
  CounterNameId: Integer;
  Delims, CounterStyle: string;
  Values: TPixieStringVector;
  Siblings: TPixieElementList;
  Current, Sib: TPixieElement;
  Val: Integer;
  I, J: Integer;
begin
  Result := '';
  if Params.Count < 2 then
    Exit;

  CounterNameId := PixieId(Params[0]);
  Delims := Params[1];
  Delims := PixieTrim(Delims, '"''');
  if Params.Count >= 3 then
    CounterStyle := PixieTrim(Params[2])
  else
    CounterStyle := '';

  Values := TPixieStringVector.Create;
  try
    // Collect all counter instances in scope: walk ancestors and
    // check preceding siblings at each level (CSS counter scoping
    // extends to following siblings and their descendants).
    Current := Self;
    while Current <> nil do
    begin
      if (Current.FCounterValues <> nil) and
         Current.FCounterValues.TryGetValue(CounterNameId, Val) then
        Values.Add(FormatCounterValue(Val, CounterStyle))
      else
      begin
        Siblings := Current.GetSiblingsBefore;
        try
          for J := Siblings.Count - 1 downto 0 do
          begin
            Sib := Siblings[J];
            if (Sib.GetTag = Ord(psid__tag_before)) or
               (Sib.GetTag = Ord(psid__tag_after)) then
              Continue;
            if (Sib.FCounterValues <> nil) and
               Sib.FCounterValues.TryGetValue(CounterNameId, Val) then
            begin
              Values.Add(FormatCounterValue(Val, CounterStyle));
              Break;
            end;
          end;
        finally
          Siblings.Free;
        end;
      end;
      Current := Current.Parent;
    end;

    if Values.Count = 0 then
      Result := FormatCounterValue(0, CounterStyle)
    else
    begin
      // Reverse the values (collected from child to root)
      Result := '';
      for I := Values.Count - 1 downto 0 do
      begin
        if Result <> '' then
          Result := Result + Delims;
        Result := Result + Values[I];
      end;
    end;
  finally
    Values.Free;
  end;
end;

function TPixieElement.FindCounter(CounterNameId: Integer;
  out FoundEl: TPixieElement; out FoundValue: Integer): Boolean;
var
  Current: TPixieElement;
  Val: Integer;
begin
  // Walk ancestors only — CSS spec says counter-increment looks for
  // the innermost counter set by counter-reset on self or an ancestor.
  Current := Self;
  while Current <> nil do
  begin
    if (Current.FCounterValues <> nil) and
       Current.FCounterValues.TryGetValue(CounterNameId, Val) then
    begin
      FoundEl := Current;
      FoundValue := Val;
      Exit(True);
    end;
    Current := Current.Parent;
  end;

  FoundEl := nil;
  FoundValue := 0;
  Result := False;
end;

function TPixieElement.GetSiblingsBefore: TPixieElementList;
var
  I: Integer;
begin
  Result := TPixieElementList.Create(False);
  if FParent <> nil then
    for I := 0 to FParent.FChildren.Count - 1 do
    begin
      if FParent.FChildren[I] = Self then
        Break;
      Result.Add(FParent.FChildren[I]);
    end;
end;

procedure TPixieElement.IncrementCounter(CounterNameId: Integer;
  Increment: Integer);
var
  FoundEl, TargetEl: TPixieElement;
  FoundValue: Integer;
begin
  if FindCounter(CounterNameId, FoundEl, FoundValue) then
  begin
    if FoundEl.FCounterValues = nil then
      FoundEl.FCounterValues := TPixieIntIntMap.Create;
    FoundEl.FCounterValues.AddOrSetValue(CounterNameId,
      FoundValue + Increment);
  end
  else
  begin
    // No counter in scope — auto-create on the parent element so
    // that sibling elements can find and increment the same counter.
    // For pseudo-elements the parent is the host element, go one
    // level higher so siblings of the host share the counter.
    if (GetTag = Ord(psid__tag_before)) or
       (GetTag = Ord(psid__tag_after)) then
      TargetEl := Parent
    else
      TargetEl := Self;
    if (TargetEl <> nil) and (TargetEl.FParent <> nil) then
      TargetEl := TargetEl.FParent;
    if TargetEl <> nil then
    begin
      if TargetEl.FCounterValues = nil then
        TargetEl.FCounterValues := TPixieIntIntMap.Create;
      TargetEl.FCounterValues.AddOrSetValue(CounterNameId, Increment);
    end;
  end;
end;

procedure TPixieElement.ResetCounter(CounterNameId: Integer;
  Value: Integer);
begin
  if FCounterValues = nil then
    FCounterValues := TPixieIntIntMap.Create;
  FCounterValues.AddOrSetValue(CounterNameId, Value);
end;

// Render tracking

procedure TPixieElement.AddRender(Ri: Pointer);
begin
  FRenders.Add(Ri);
end;

procedure TPixieElement.ClearRenders;
begin
  FRenders.Clear;
end;

function TPixieElement.GetRenderItem: Pointer;
begin
  if FRenders.Count = 0 then
    Result := nil
  else
    Result := FRenders[0];
end;

procedure TPixieElement.ClearUsedStyles;
begin
  FreeAndNil(FUsedStyles);
end;

procedure TPixieElement.ResetStyle;
begin
  // Base class stub — overridden in TPixieHtmlTag
end;

procedure TPixieElement.ClearCounterValues;
begin
  FreeAndNil(FCounterValues);
end;

function TPixieElement.RequiresStylesUpdate: Boolean;
var
  I, Res: Integer;
  UsedSel: TPixieUsedSelector;
begin
  if FUsedStyles = nil then
    Exit(False);
  for I := 0 to FUsedStyles.Count - 1 do
  begin
    UsedSel := FUsedStyles[I];
    if UsedSel.Selector.IsMediaValid then
    begin
      Res := SelectSel(UsedSel.Selector, True);
      if ((Res = SelectNoMatch) and UsedSel.Used) or
         ((Res = SelectMatch) and not UsedSel.Used) then
        Exit(True);
    end;
  end;
  Result := False;
end;

function TPixieElement.FindStylesChanges(
  RedrawBoxes: TPixiePositionVector): Boolean;
var
  I: Integer;
  El: TPixieElement;
begin
  if FCss.Display = displayInlineText then
    Exit(False);

  Result := False;

  if RequiresStylesUpdate then
  begin
    // Render box collection deferred to Phase 5
    RefreshStyles;
    ComputeStyles;
    Result := True;
  end;

  for I := 0 to FChildren.Count - 1 do
  begin
    El := FChildren[I];
    if El.FindStylesChanges(RedrawBoxes) then
      Result := True;
  end;
end;

// Select all / select one

procedure TPixieElement.SelectAll(
  const Selector: TPixieCssSelector; Res: TPixieElementList);
begin
  // Base implementation: do nothing
end;

end.
