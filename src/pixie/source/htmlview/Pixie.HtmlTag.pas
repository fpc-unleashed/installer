unit Pixie.HtmlTag;

// Concrete HTML element with attributes, style, and selector matching.
//
// This is the main element type. It stores tag name, id, classes,
// attributes, inline style, and pseudo-classes. Implements all virtual
// methods from TPixieElement including selector matching, style
// application, compute_styles, mouse events, and drawing.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Generics.Collections,
  Pixie.Types, Pixie.StringId, Pixie.Utils,
  Pixie.CssLength, Pixie.WebColor, Pixie.Borders,
  Pixie.Background, Pixie.FontDescription,
  Pixie.CssTokenizer, Pixie.CssParser,
  Pixie.Style, Pixie.CssSelector, Pixie.Stylesheet,
  Pixie.CssProperties, Pixie.Container,
  Pixie.Element;

type
  { TPixieHtmlTag }

  TPixieHtmlTag = class(TPixieElement)
  protected
    FTag: Integer;
    FId: Integer;
    FStrClasses: TPixieStringVector;
    FClasses: TPixieIntVector;
    FStyle: TPixieStyle;
    FAttrs: TPixieStringMap;
    FPseudoClasses: TPixieIntVector;

  public
    procedure SelectAll(const Selector: TPixieCssSelector;
      Res: TPixieElementList); override;
    constructor Create(ADoc: TObject); overload;
    constructor CreateAnonymous(AParent: TPixieElement;
      const AStyle: string = 'display: block'); overload;
    destructor Destroy; override;

    // get_property overloads
    function GetPropertyInt(Name: Integer; IsInherited: Boolean;
      DefaultVal: Integer; MemberOffset: PtrUInt): Integer;
    function GetPropertyLength(Name: Integer; IsInherited: Boolean;
      const DefaultVal: TPixieCssLength;
      MemberOffset: PtrUInt): TPixieCssLength;
    function GetPropertyColor(Name: Integer; IsInherited: Boolean;
      DefaultVal: TPixieWebColor;
      MemberOffset: PtrUInt): TPixieWebColor;
    function GetPropertyString(Name: Integer; IsInherited: Boolean;
      const DefaultVal: string; MemberOffset: PtrUInt): string;
    function GetPropertyFloat(Name: Integer; IsInherited: Boolean;
      DefaultVal: Single; MemberOffset: PtrUInt): Single;
    function GetPropertyIntVector(Name: Integer; IsInherited: Boolean;
      DefaultVal: TPixieIntVector;
      MemberOffset: PtrUInt): TPixieIntVector;
    function GetPropertyLengthVector(Name: Integer; IsInherited: Boolean;
      DefaultVal: TPixieLengthVector;
      MemberOffset: PtrUInt): TPixieLengthVector;
    function GetPropertySizeVector(Name: Integer; IsInherited: Boolean;
      DefaultVal: TPixieSizeVector;
      MemberOffset: PtrUInt): TPixieSizeVector;
    function GetCustomProperty(Name: Integer;
      var Tokens: TPixieCssTokenList): Boolean;

    // Overrides from TPixieElement
    function AppendChild(El: TPixieElement): Boolean; override;
    function InsertBefore(NewChild, RefChild: TPixieElement): Boolean; override;
    function RemoveChild(El: TPixieElement): Boolean; override;
    procedure ClearRecursive; override;

    function GetId: Integer; override;
    function GetTag: Integer; override;
    function GetTagName: string; override;
    procedure SetTagName(const ATag: string); override;
    procedure SetData(const AData: string); override;
    procedure SetAttr(const AName, AVal: string); override;
    function GetAttr(const AName: string;
      const ADef: string = ''): string; override;

    procedure ApplyStylesheet(
      Stylesheet: TPixieStylesheet); override;
    procedure RefreshStyles; override;
    procedure ComputeStyles(Recursive: Boolean = True); override;

    function Select(const SelectorList: TPixieCssSelectorList;
      ApplyPseudo: Boolean = True): Integer; override;
    function SelectSel(const Selector: TPixieCssSelector;
      ApplyPseudo: Boolean = True): Integer; override;
    function SelectCompound(
      const Selector: TPixieCompoundSelector;
      ApplyPseudo: Boolean = True): Integer; override;

    function SelectPseudoClass(
      const Sel: TPixieAttrSelector): Integer;
    function SelectAttribute(
      const Sel: TPixieAttrSelector): Integer;

    // Form-control disabled state (drives :disabled/:enabled and the owner
    // drawn controls). A control is disabled by its own disabled attribute
    // or by an ancestor <fieldset disabled> (except inside its first legend).
    function IsDisableableType: Boolean;
    function IsEffectivelyDisabled: Boolean;

    function FindAncestor(const Selector: TPixieCssSelector;
      ApplyPseudo: Boolean = True;
      IsPseudo: PBoolean = nil): TPixieElement; override;
    function FindAdjacentSibling(El: TPixieElement;
      const Selector: TPixieCssSelector;
      ApplyPseudo: Boolean = True;
      IsPseudo: PBoolean = nil): TPixieElement; override;
    function FindSibling(El: TPixieElement;
      const Selector: TPixieCssSelector;
      ApplyPseudo: Boolean = True;
      IsPseudo: PBoolean = nil): TPixieElement; override;

    function SetPseudoClass(Cls: Integer;
      Add: Boolean): Boolean; override;
    function IsWhiteSpace: Boolean; override;
    function IsBody: Boolean; override;
    function IsBreak: Boolean; override;
    function IsReplaced: Boolean; override;

    function OnMouseOver: Boolean; override;
    function OnMouseLeave: Boolean; override;
    function OnLButtonDown: Boolean; override;
    function OnLButtonUp(IsClick: Boolean = True): Boolean; override;
    procedure OnClick; override;

    procedure GetText(var Text: string); override;
    procedure SetTextContent(const AText: string); override;
    procedure ResetStyle; override;
    procedure ParseAttributes; override;
    procedure GetContentSize(var Sz: TPixieSize;
      MaxWidth: TPixiePixel); override;
    procedure AddStyle(const AStyle: TPixieStyle); override;

    procedure Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
      Clip: PPixiePosition; Ri: Pointer); override;
    procedure DrawBackground(Hdc: PtrUInt; X, Y: TPixiePixel;
      Clip: PPixiePosition; Ri: Pointer); override;

    function IsNthChild(El: TPixieElement; Num, Off: Integer;
      OfType: Boolean;
      SelectorList: TPixieCssSelectorList = nil): Boolean; override;
    function IsNthLastChild(El: TPixieElement; Num, Off: Integer;
      OfType: Boolean;
      SelectorList: TPixieCssSelectorList = nil): Boolean; override;
    function IsOnlyChild(El: TPixieElement;
      OfType: Boolean): Boolean; override;
    function GetBackground(
      OwnOnly: Boolean = False): TPixieBackground; override;

    function DumpGetName: string; override;

    // Access to internal style for var() substitution
    property Style: TPixieStyle read FStyle;
    property Tag: Integer read FTag write FTag;
    property Attrs: TPixieStringMap read FAttrs;
    property Classes: TPixieIntVector read FClasses;
    property StrClasses: TPixieStringVector read FStrClasses;

    function GetDocContainer: TPixieContainer;

  protected
    procedure DrawListMarker(Hdc: PtrUInt;
      const Pos: TPixiePosition; Ri: Pointer);
    function GetListMarkerText(Index: Integer): string;
    function GetElementBefore(
      DoCreate: Boolean): TPixieElement;
    function GetElementAfter(
      DoCreate: Boolean): TPixieElement;

    procedure MapToPixelLengthProperty(PropName: Integer;
      const AttrValue: string);
    procedure MapToPixelLengthPropertyWithDefault(PropName: Integer;
      const AttrValue: string; DefaultVal: Integer);
    procedure MapToDimensionProperty(PropName: Integer;
      const AttrValue: string);
    procedure MapToDimensionPropertyIgnoreZero(PropName: Integer;
      const AttrValue: string);
    procedure MapAlignToTextAlign(const AttrValue: string);

  private
    procedure HandleCounterProperties(const AStyle: TPixieStyle);

    function GetDocumentMode: TPixieDocumentMode;
    function MatchDocLang(const Lang: string): Boolean;

    function ParseNonNegativeInteger(const S: string;
      out N: Integer): Boolean;
    function ParseDimensionValue(const S: string;
      out X: Single; out IsPercent: Boolean): Boolean;
    function ParseNonzeroDimensionValue(const S: string;
      out X: Single; out IsPercent: Boolean): Boolean;
  end;

implementation

uses
  Pixie.NumCvt, Pixie.Document, Pixie.ElText, Pixie.ElBeforeAfter,
  Pixie.RenderItem;

{ Helpers }

function ListContainsInt(List: TPixieIntVector;
  Val: Integer): Boolean;
var
  I: Integer;
begin
  for I := 0 to List.Count - 1 do
    if List[I] = Val then
      Exit(True);
  Result := False;
end;

function ListContainsIntSorted(List: TPixieIntVector;
  Val: Integer): Boolean;
var
  Lo, Hi, Mid, MidVal: Integer;
begin
  Lo := 0;
  Hi := List.Count - 1;
  while Lo <= Hi do
  begin
    Mid := Lo + (Hi - Lo) div 2;
    MidVal := List[Mid];
    if MidVal = Val then
      Exit(True)
    else if MidVal < Val then
      Lo := Mid + 1
    else
      Hi := Mid - 1;
  end;
  Result := False;
end;

procedure SortIntVector(List: TPixieIntVector);
var
  I, J, Tmp: Integer;
begin
  // Insertion sort for small lists
  for I := 1 to List.Count - 1 do
  begin
    Tmp := List[I];
    J := I - 1;
    while (J >= 0) and (List[J] > Tmp) do
    begin
      List[J + 1] := List[J];
      Dec(J);
    end;
    List[J + 1] := Tmp;
  end;
end;

procedure SortSelectorList(List: TPixieCssSelectorList);
var
  I, J, Cmp: Integer;
  Tmp: TPixieCssSelector;
  SaveOwns: Boolean;
begin
  // Insertion sort by specificity ascending, then order ascending.
  // Same ordering as TPixieStylesheet.SortSelectors.
  SaveOwns := List.OwnsObjects;
  List.OwnsObjects := False;
  try
    for I := 1 to List.Count - 1 do
    begin
      Tmp := List[I];
      J := I - 1;
      while J >= 0 do
      begin
        Cmp := List[J].Specificity.Compare(Tmp.Specificity);
        if (Cmp > 0) or ((Cmp = 0) and (List[J].Order > Tmp.Order)) then
        begin
          List[J + 1] := List[J];
          Dec(J);
        end
        else
          Break;
      end;
      List[J + 1] := Tmp;
    end;
  finally
    List.OwnsObjects := SaveOwns;
  end;
end;

{ TPixieHtmlTag }

constructor TPixieHtmlTag.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
  FTag := -1;
  FId := -1;
  FStrClasses := TPixieStringVector.Create;
  FClasses := TPixieIntVector.Create;
  FStyle := TPixieStyle.Create;
  FAttrs := TPixieStringMap.Create;
  FPseudoClasses := TPixieIntVector.Create;
end;

constructor TPixieHtmlTag.CreateAnonymous(AParent: TPixieElement;
  const AStyle: string);
var
  St: TPixieStyle;
begin
  Create(AParent.GetDocument);
  St := TPixieStyle.Create;
  try
    St.Add(AStyle);
    AddStyle(St);
  finally
    St.Free;
  end;
  SetParent(AParent);
  ComputeStyles;
end;

destructor TPixieHtmlTag.Destroy;
begin
  FPseudoClasses.Free;
  FAttrs.Free;
  FStyle.Free;
  FClasses.Free;
  FStrClasses.Free;
  inherited Destroy;
end;

// get_property implementations
// These implement get_property using offset-based
// field access into TPixieCssProperties for parent inheritance.

function TPixieHtmlTag.GetPropertyInt(Name: Integer; IsInherited: Boolean;
  DefaultVal: Integer; MemberOffset: PtrUInt): Integer;
var
  Prop: TPixiePropertyValue;
  Par: TPixieElement;
begin
  Prop := FStyle.GetProperty(Name);
  if Prop.Kind = pkInt then
    Exit(Prop.IntVal);
  if IsInherited or (Prop.Kind = pkInherit) then
  begin
    Par := Parent;
    if Par <> nil then
      Exit(PInteger(PByte(Par.Css) + MemberOffset)^);
  end;
  Result := DefaultVal;
end;

function TPixieHtmlTag.GetPropertyLength(Name: Integer;
  IsInherited: Boolean; const DefaultVal: TPixieCssLength;
  MemberOffset: PtrUInt): TPixieCssLength;
var
  Prop: TPixiePropertyValue;
  Par: TPixieElement;
begin
  Prop := FStyle.GetProperty(Name);
  if Prop.Kind = pkCssLength then
    Exit(Prop.LengthVal);
  if IsInherited or (Prop.Kind = pkInherit) then
  begin
    Par := Parent;
    if Par <> nil then
      Exit(PPixieCssLength(PByte(Par.Css) + MemberOffset)^);
  end;
  Result := DefaultVal;
end;

function TPixieHtmlTag.GetPropertyColor(Name: Integer;
  IsInherited: Boolean; DefaultVal: TPixieWebColor;
  MemberOffset: PtrUInt): TPixieWebColor;
var
  Prop: TPixiePropertyValue;
  Par: TPixieElement;
begin
  Prop := FStyle.GetProperty(Name);
  if Prop.Kind = pkColor then
    Exit(Prop.ColorVal);
  if IsInherited or (Prop.Kind = pkInherit) then
  begin
    Par := Parent;
    if Par <> nil then
      Exit(PPixieWebColor(PByte(Par.Css) + MemberOffset)^);
  end;
  Result := DefaultVal;
end;

function TPixieHtmlTag.GetPropertyString(Name: Integer;
  IsInherited: Boolean; const DefaultVal: string;
  MemberOffset: PtrUInt): string;
var
  Prop: TPixiePropertyValue;
  Par: TPixieElement;
begin
  Prop := FStyle.GetProperty(Name);
  if Prop.Kind = pkString then
    Exit(Prop.StrVal);
  if IsInherited or (Prop.Kind = pkInherit) then
  begin
    Par := Parent;
    if Par <> nil then
      Exit(PString(PByte(Par.Css) + MemberOffset)^);
  end;
  Result := DefaultVal;
end;

function TPixieHtmlTag.GetPropertyFloat(Name: Integer;
  IsInherited: Boolean; DefaultVal: Single;
  MemberOffset: PtrUInt): Single;
var
  Prop: TPixiePropertyValue;
  Par: TPixieElement;
begin
  Prop := FStyle.GetProperty(Name);
  if Prop.Kind = pkFloat then
    Exit(Prop.FloatVal);
  if IsInherited or (Prop.Kind = pkInherit) then
  begin
    Par := Parent;
    if Par <> nil then
      Exit(PSingle(PByte(Par.Css) + MemberOffset)^);
  end;
  Result := DefaultVal;
end;

function TPixieHtmlTag.GetPropertyIntVector(Name: Integer;
  IsInherited: Boolean; DefaultVal: TPixieIntVector;
  MemberOffset: PtrUInt): TPixieIntVector;
var
  Prop: TPixiePropertyValue;
begin
  Prop := FStyle.GetProperty(Name);
  if Prop.Kind = pkIntVector then
    Exit(Prop.IntVecVal);
  // IntVectors are not inherited through offset (complex ownership)
  Result := DefaultVal;
end;

function TPixieHtmlTag.GetPropertyLengthVector(Name: Integer;
  IsInherited: Boolean; DefaultVal: TPixieLengthVector;
  MemberOffset: PtrUInt): TPixieLengthVector;
var
  Prop: TPixiePropertyValue;
begin
  Prop := FStyle.GetProperty(Name);
  if Prop.Kind = pkLengthVector then
    Exit(Prop.LengthVecVal);
  Result := DefaultVal;
end;

function TPixieHtmlTag.GetPropertySizeVector(Name: Integer;
  IsInherited: Boolean; DefaultVal: TPixieSizeVector;
  MemberOffset: PtrUInt): TPixieSizeVector;
var
  Prop: TPixiePropertyValue;
begin
  Prop := FStyle.GetProperty(Name);
  if Prop.Kind = pkSizeVector then
    Exit(Prop.SizeVecVal);
  Result := DefaultVal;
end;

function TPixieHtmlTag.GetCustomProperty(Name: Integer;
  var Tokens: TPixieCssTokenList): Boolean;
var
  Prop: TPixiePropertyValue;
  ParTag: TPixieHtmlTag;
begin
  Prop := FStyle.GetProperty(Name);
  if Prop.Kind = pkTokenVector then
  begin
    Tokens := Prop.TokenVecVal;
    Exit(True);
  end;
  if (Parent <> nil) and (Parent is TPixieHtmlTag) then
  begin
    ParTag := TPixieHtmlTag(Parent);
    Exit(ParTag.GetCustomProperty(Name, Tokens));
  end;
  Tokens := nil;
  Exit(False);
end;

// Children

function TPixieHtmlTag.AppendChild(El: TPixieElement): Boolean;
begin
  if El <> nil then
  begin
    El.SetParent(Self);
    FChildren.Add(El);
    Result := True;
  end
  else
    Result := False;
end;

function TPixieHtmlTag.InsertBefore(NewChild,
  RefChild: TPixieElement): Boolean;
var
  Idx: Integer;
begin
  if NewChild = nil then
    Exit(False);
  if RefChild = nil then
    Exit(AppendChild(NewChild));
  Idx := FChildren.IndexOf(RefChild);
  if Idx < 0 then
    Exit(False);
  NewChild.SetParent(Self);
  FChildren.Insert(Idx, NewChild);
  Result := True;
end;

function TPixieHtmlTag.RemoveChild(El: TPixieElement): Boolean;
var
  Idx: Integer;
begin
  if (El <> nil) and (El.Parent = Self) then
  begin
    El.SetParent(nil);
    Idx := FChildren.IndexOf(El);
    if Idx >= 0 then
      FChildren.Delete(Idx);
    Result := True;
  end
  else
    Result := False;
end;

procedure TPixieHtmlTag.ClearRecursive;
var
  I: Integer;
  Doc: TPixieDocument;
begin
  if FChildren.Count = 0 then Exit;
  Doc := TPixieDocument(FDoc);
  for I := FChildren.Count - 1 downto 0 do
    Doc.UnregisterElement(FChildren[I]);
  FChildren.Clear;
end;

// Tag/ID/attrs

function TPixieHtmlTag.GetId: Integer;
begin
  Result := FId;
end;

function TPixieHtmlTag.GetTag: Integer;
begin
  Result := FTag;
end;

function TPixieHtmlTag.GetTagName: string;
begin
  Result := PixieStr(FTag);
end;

procedure TPixieHtmlTag.SetTagName(const ATag: string);
begin
  FTag := PixieId(PixieLowerCase(ATag));
end;

procedure TPixieHtmlTag.SetData(const AData: string);
begin
  // html_tag ignores set_data
end;

procedure TPixieHtmlTag.SetAttr(const AName, AVal: string);
var
  Name, Val: string;
  Tokens: TPixieStringVector;
  I: Integer;
begin
  Name := AName;
  FAttrs.AddOrSetValue(Name, AVal);

  Name := PixieLowerCase(Name);
  if Name = 'class' then
  begin
    Val := AVal;
    // In quirks mode, class names are case-insensitive
    // We access document mode through FDoc, cast in implementation
    if GetDocumentMode = dmQuirks then
      Val := PixieLowerCase(Val);

    FStrClasses.Clear;
    FClasses.Clear;
    Tokens := TPixieStringVector.Create;
    try
      PixieSplitString(Val, Tokens);
      for I := 0 to Tokens.Count - 1 do
      begin
        FStrClasses.Add(Tokens[I]);
        FClasses.Add(PixieId(Tokens[I]));
      end;
    finally
      Tokens.Free;
    end;
    SortIntVector(FClasses);
  end
  else if Name = 'id' then
  begin
    Val := AVal;
    if GetDocumentMode = dmQuirks then
      Val := PixieLowerCase(Val);
    FId := PixieId(Val);
  end;
end;

function TPixieHtmlTag.GetAttr(const AName: string;
  const ADef: string): string;
var
  Val: string;
begin
  if FAttrs.TryGetValue(AName, Val) then
    Result := Val
  else
    Result := ADef;
end;

function TPixieHtmlTag.GetDocumentMode: TPixieDocumentMode;
begin
  if FDoc <> nil then
  begin
    Assert(FDoc is TPixieDocument);
    Result := TPixieDocument(FDoc).Mode;
  end
  else
    Result := dmNoQuirks;
end;

// Select

function TPixieHtmlTag.Select(
  const SelectorList: TPixieCssSelectorList;
  ApplyPseudo: Boolean): Integer;
var
  I, Res: Integer;
begin
  for I := 0 to SelectorList.Count - 1 do
  begin
    Res := SelectSel(SelectorList[I], ApplyPseudo);
    if Res <> SelectNoMatch then
      Exit(Res);
  end;
  Result := SelectNoMatch;
end;

function TPixieHtmlTag.SelectSel(const Selector: TPixieCssSelector;
  ApplyPseudo: Boolean): Integer;
var
  RightRes, Res: Integer;
  Par: TPixieElement;
  IsPseudo: Boolean;
  AncResult: TPixieElement;
begin
  RightRes := SelectCompound(Selector.Right, ApplyPseudo);
  if RightRes = SelectNoMatch then
    Exit(SelectNoMatch);

  Par := Parent;
  if Selector.Left <> nil then
  begin
    if Par = nil then
      Exit(SelectNoMatch);

    case Selector.Combinator of
      PixieCombinatorDescendant:
      begin
        IsPseudo := False;
        AncResult := FindAncestor(Selector.Left, ApplyPseudo, @IsPseudo);
        if AncResult = nil then
          Exit(SelectNoMatch);
        if IsPseudo then
          RightRes := RightRes or SelectMatchPseudoClass;
      end;
      PixieCombinatorChild:
      begin
        Res := Par.SelectSel(Selector.Left, ApplyPseudo);
        if Res = SelectNoMatch then
          Exit(SelectNoMatch);
        if RightRes <> SelectMatchPseudoClass then
          RightRes := RightRes or Res;
      end;
      PixieCombinatorAdjacentSibling:
      begin
        IsPseudo := False;
        AncResult := Par.FindAdjacentSibling(Self,
          Selector.Left, ApplyPseudo, @IsPseudo);
        if AncResult = nil then
          Exit(SelectNoMatch);
        if IsPseudo then
          RightRes := RightRes or SelectMatchPseudoClass;
      end;
      PixieCombinatorGeneralSibling:
      begin
        IsPseudo := False;
        AncResult := Par.FindSibling(Self,
          Selector.Left, ApplyPseudo, @IsPseudo);
        if AncResult = nil then
          Exit(SelectNoMatch);
        if IsPseudo then
          RightRes := RightRes or SelectMatchPseudoClass;
      end;
    else
      RightRes := SelectNoMatch;
    end;
  end;
  Result := RightRes;
end;

function TPixieHtmlTag.SelectCompound(
  const Selector: TPixieCompoundSelector;
  ApplyPseudo: Boolean): Integer;
var
  Res, I: Integer;
  Attr: TPixieAttrSelector;
begin
  if (Selector.Tag <> PixieId('*')) and (Selector.Tag <> FTag) then
    Exit(SelectNoMatch);

  Res := SelectMatch;

  for I := 0 to Selector.Attrs.Count - 1 do
  begin
    Attr := Selector.Attrs[I];
    if Attr.SelectType = selectClass then
    begin
      if not ListContainsIntSorted(FClasses, Attr.Name) then
        Exit(SelectNoMatch);
    end
    else if Attr.SelectType = selectId then
    begin
      if Attr.Name <> FId then
        Exit(SelectNoMatch);
    end
    else if Attr.SelectType = selectPseudoElement then
    begin
      if Attr.Name = Ord(psid_after) then
      begin
        if (Selector.Attrs.Count = 1) and
           (Selector.Tag = PixieId('*')) and
           (FTag <> Ord(psid__tag_after)) then
          Exit(SelectNoMatch);
        Res := Res or SelectMatchWithAfter;
      end
      else if Attr.Name = Ord(psid_before) then
      begin
        if (Selector.Attrs.Count = 1) and
           (Selector.Tag = PixieId('*')) and
           (FTag <> Ord(psid__tag_before)) then
          Exit(SelectNoMatch);
        Res := Res or SelectMatchWithBefore;
      end
      else
        Exit(SelectNoMatch);
    end
    else if Attr.SelectType = Pixie.CssSelector.selectPseudoClass then
    begin
      if ApplyPseudo then
      begin
        if SelectPseudoClass(Attr) = SelectNoMatch then
          Exit(SelectNoMatch);
      end
      else
        Res := Res or SelectMatchPseudoClass;
    end
    else
    begin
      // Attribute selector
      if SelectAttribute(Attr) = SelectNoMatch then
        Exit(SelectNoMatch);
    end;
  end;
  Result := Res;
end;

function TPixieHtmlTag.SelectPseudoClass(
  const Sel: TPixieAttrSelector): Integer;
var
  Par: TPixieElement;
  Num, Off: Integer;
begin
  Par := Parent;

  case Sel.Name of
    Ord(psid_only_child):
      if (Par = nil) or
         not Par.IsOnlyChild(Self, False) then
        Exit(SelectNoMatch);
    Ord(psid_only_of_type):
      if (Par = nil) or
         not Par.IsOnlyChild(Self, True) then
        Exit(SelectNoMatch);
    Ord(psid_first_child):
      if (Par = nil) or
         not Par.IsNthChild(Self, 0, 1, False) then
        Exit(SelectNoMatch);
    Ord(psid_first_of_type):
      if (Par = nil) or
         not Par.IsNthChild(Self, 0, 1, True) then
        Exit(SelectNoMatch);
    Ord(psid_last_child):
      if (Par = nil) or
         not Par.IsNthLastChild(Self, 0, 1, False) then
        Exit(SelectNoMatch);
    Ord(psid_last_of_type):
      if (Par = nil) or
         not Par.IsNthLastChild(Self, 0, 1, True) then
        Exit(SelectNoMatch);
    Ord(psid_nth_child),
    Ord(psid_nth_of_type),
    Ord(psid_nth_last_child),
    Ord(psid_nth_last_of_type):
    begin
      if Par = nil then
        Exit(SelectNoMatch);
      Num := Sel.A;
      Off := Sel.B;
      if (Num = 0) and (Off = 0) then
        Exit(SelectNoMatch);
      case Sel.Name of
        Ord(psid_nth_child):
          if not Par.IsNthChild(Self, Num, Off, False,
            Sel.SelectorList) then
            Exit(SelectNoMatch);
        Ord(psid_nth_of_type):
          if not Par.IsNthChild(Self, Num, Off, True) then
            Exit(SelectNoMatch);
        Ord(psid_nth_last_child):
          if not Par.IsNthLastChild(Self, Num, Off, False,
            Sel.SelectorList) then
            Exit(SelectNoMatch);
        Ord(psid_nth_last_of_type):
          if not Par.IsNthLastChild(Self, Num, Off, True) then
            Exit(SelectNoMatch);
      end;
    end;
    Ord(psid_is):
      if (Sel.SelectorList = nil) or
         (Select(Sel.SelectorList, True) = SelectNoMatch) then
        Exit(SelectNoMatch);
    Ord(psid_not):
      if (Sel.SelectorList <> nil) and
         (Select(Sel.SelectorList, True) <> SelectNoMatch) then
        Exit(SelectNoMatch);
    Ord(psid_lang):
      if not MatchDocLang(Sel.Value) then
        Exit(SelectNoMatch);
    Ord(psid_disabled):
      if not IsEffectivelyDisabled then
        Exit(SelectNoMatch);
    Ord(psid_enabled):
      if (not IsDisableableType) or IsEffectivelyDisabled then
        Exit(SelectNoMatch);
  else
    // Simple pseudo-classes: :hover, :active, :focus, etc.
    if not ListContainsInt(FPseudoClasses, Sel.Name) then
      Exit(SelectNoMatch);
  end;
  Result := SelectMatch;
end;

function TPixieHtmlTag.IsDisableableType: Boolean;
begin
  case FTag of
    Ord(psid_button), Ord(psid_input), Ord(psid_select),
    Ord(psid_textarea), Ord(psid_option), Ord(psid_optgroup),
    Ord(psid_fieldset):
      Result := True;
  else
    Result := False;
  end;
end;

function TPixieHtmlTag.IsEffectivelyDisabled: Boolean;
var
  Node, Prev, Legend: TPixieElement;
  I: Integer;
begin
  Result := False;
  if not IsDisableableType then
    Exit;

  // Own disabled attribute.
  if GetAttr('disabled', #1) <> #1 then
    Exit(True);

  // Disabled by an ancestor <fieldset disabled>, unless this element sits
  // inside that fieldset's first <legend>.
  Prev := Self;
  Node := Parent;
  while Node <> nil do
  begin
    if (Node.GetTag = Ord(psid_fieldset)) and (Node is TPixieHtmlTag) and
       (TPixieHtmlTag(Node).GetAttr('disabled', #1) <> #1) then
    begin
      Legend := nil;
      for I := 0 to Node.Children.Count - 1 do
        if Node.Children[I].GetTag = Ord(psid_legend) then
        begin
          Legend := Node.Children[I];
          Break;
        end;
      if Prev <> Legend then
        Exit(True);
    end;
    Prev := Node;
    Node := Node.Parent;
  end;
end;

function TPixieHtmlTag.SelectAttribute(
  const Sel: TPixieAttrSelector): Integer;
var
  AttrVal, SelVal: string;
  Tokens: TPixieStringVector;
  I: Integer;
begin
  if not FAttrs.TryGetValue(PixieStr(Sel.Name), AttrVal) then
    Exit(SelectNoMatch);

  if Sel.CaselessMatch then
    AttrVal := PixieLowerCase(AttrVal);

  SelVal := Sel.Value;

  case Sel.Matcher of
    PixieAttrExists:
      Exit(SelectMatch);
    PixieAttrEquals:
      if AttrVal = SelVal then
        Exit(SelectMatch);
    PixieAttrContainsString: // *=
      if (SelVal <> '') and (Pos(SelVal, AttrVal) > 0) then
        Exit(SelectMatch);
    PixieAttrContainsWord: // ~=
    begin
      if SelVal <> '' then
      begin
        Tokens := TPixieStringVector.Create;
        try
          PixieSplitString(AttrVal, Tokens);
          for I := 0 to Tokens.Count - 1 do
            if Tokens[I] = SelVal then
              Exit(SelectMatch);
        finally
          Tokens.Free;
        end;
      end;
    end;
    PixieAttrStartsWithString: // ^=
      if (SelVal <> '') and PixieMatch(AttrVal, 1, SelVal) then
        Exit(SelectMatch);
    PixieAttrStartsWithHyphen: // |=
      if (AttrVal = SelVal) or
         PixieMatch(AttrVal, 1, SelVal + '-') then
        Exit(SelectMatch);
    PixieAttrEndsWithString: // $=
      if (SelVal <> '') and
         (Length(AttrVal) >= Length(SelVal)) and
         PixieMatch(AttrVal,
           Length(AttrVal) - Length(SelVal) + 1, SelVal) then
        Exit(SelectMatch);
  end;
  Result := SelectNoMatch;
end;

// Ancestor/sibling searching

function TPixieHtmlTag.FindAncestor(const Selector: TPixieCssSelector;
  ApplyPseudo: Boolean; IsPseudo: PBoolean): TPixieElement;
var
  Par: TPixieElement;
  Res: Integer;
begin
  Par := Parent;
  if Par = nil then
    Exit(nil);

  Res := Par.SelectSel(Selector, ApplyPseudo);
  if Res <> SelectNoMatch then
  begin
    if IsPseudo <> nil then
      IsPseudo^ := (Res and SelectMatchPseudoClass) <> 0;
    Exit(Par);
  end;
  Result := Par.FindAncestor(Selector, ApplyPseudo, IsPseudo);
end;

function TPixieHtmlTag.FindAdjacentSibling(El: TPixieElement;
  const Selector: TPixieCssSelector; ApplyPseudo: Boolean;
  IsPseudo: PBoolean): TPixieElement;
var
  I, Res: Integer;
  Prev: TPixieElement;
begin
  Prev := nil;
  for I := 0 to FChildren.Count - 1 do
  begin
    if FChildren[I].Css.Display <> displayInlineText then
    begin
      if FChildren[I] = El then
      begin
        if Prev <> nil then
        begin
          Res := Prev.SelectSel(Selector, ApplyPseudo);
          if Res <> SelectNoMatch then
          begin
            if IsPseudo <> nil then
              IsPseudo^ := (Res and SelectMatchPseudoClass) <> 0;
            Exit(Prev);
          end;
        end;
        Exit(nil);
      end
      else
        Prev := FChildren[I];
    end;
  end;
  Result := nil;
end;

function TPixieHtmlTag.FindSibling(El: TPixieElement;
  const Selector: TPixieCssSelector; ApplyPseudo: Boolean;
  IsPseudo: PBoolean): TPixieElement;
var
  I, Res: Integer;
  Ret: TPixieElement;
begin
  Ret := nil;
  for I := 0 to FChildren.Count - 1 do
  begin
    if FChildren[I].Css.Display <> displayInlineText then
    begin
      if FChildren[I] = El then
        Exit(Ret)
      else if Ret = nil then
      begin
        Res := FChildren[I].SelectSel(Selector, ApplyPseudo);
        if Res <> SelectNoMatch then
        begin
          if IsPseudo <> nil then
            IsPseudo^ := (Res and SelectMatchPseudoClass) <> 0;
          Ret := FChildren[I];
        end;
      end;
    end;
  end;
  Result := nil;
end;

// Apply stylesheet

procedure TPixieHtmlTag.ApplyStylesheet(Stylesheet: TPixieStylesheet);
var
  I, Apply: Integer;
  Sel: TPixieCssSelector;
  Us: TPixieUsedSelector;
  ContentProp: TPixiePropertyValue;
  ContentNone, DoCreate: Boolean;
  BeforeAfterEl: TPixieElement;
  Candidates: TPixieCssSelectorList;
  Bucket: TPixieCssSelectorList;

  procedure ApplyCandidate(Sel: TPixieCssSelector);
  begin
    Apply := SelectSel(Sel, False);
    if Apply <> SelectNoMatch then
    begin
      Us := TPixieUsedSelector.Create(Sel, False);

      if Sel.IsMediaValid then
      begin
        // Check for ::before/::after pseudo-elements
        if (Apply and (SelectMatchWithAfter or SelectMatchWithBefore)) <> 0 then
        begin
          // When pseudo-class is also present, verify it actually matches
          if ((Apply and SelectMatchPseudoClass) = 0) or
             (SelectSel(Sel, True) <> SelectNoMatch) then
          begin
            Assert(Sel.Style is TPixieStyle);
            ContentProp := TPixieStyle(Sel.Style).GetProperty(
              Ord(psid_content));
            ContentNone := (ContentProp.Kind = pkString) and
              (ContentProp.StrVal = 'none');
            DoCreate := not ContentNone and
              ((Sel.Right.Attrs.Count > 1) or
               (Sel.Right.Tag <> PixieId('*')));

            if (Apply and SelectMatchWithAfter) <> 0 then
              BeforeAfterEl := GetElementAfter(DoCreate)
            else
              BeforeAfterEl := GetElementBefore(DoCreate);

            if BeforeAfterEl <> nil then
            begin
              if not ContentNone then
                BeforeAfterEl.AddStyle(TPixieStyle(Sel.Style))
              else
                BeforeAfterEl.Parent.RemoveChild(BeforeAfterEl);
            end;

            Us.Used := True;
          end;
        end
        else if (Apply and SelectMatchPseudoClass) <> 0 then
        begin
          if SelectSel(Sel, True) <> SelectNoMatch then
          begin
            AddStyle(TPixieStyle(Sel.Style));
            Us.Used := True;
          end;
        end
        else
        begin
          AddStyle(TPixieStyle(Sel.Style));
          Us.Used := True;
        end;
      end;

      if FUsedStyles = nil then
        FUsedStyles := TPixieUsedSelectorList.Create;
      FUsedStyles.Add(Us);
    end;
  end;

begin
  if Stylesheet.IsIndexed then
  begin
    // Index-based lookup: collect candidates from relevant buckets
    Candidates := TPixieCssSelectorList.Create(False); // non-owning
    try
      // Tag bucket
      Bucket := Stylesheet.GetCandidatesByTag(FTag);
      if Bucket <> nil then
        for I := 0 to Bucket.Count - 1 do
          Candidates.Add(Bucket[I]);

      // Class buckets
      for I := 0 to FClasses.Count - 1 do
      begin
        Bucket := Stylesheet.GetCandidatesByClass(FClasses[I]);
        if Bucket <> nil then
          Candidates.AddRange(Bucket);
      end;

      // ID bucket
      if FId >= 0 then
      begin
        Bucket := Stylesheet.GetCandidatesById(FId);
        if Bucket <> nil then
          for I := 0 to Bucket.Count - 1 do
            Candidates.Add(Bucket[I]);
      end;

      // Universal bucket
      Bucket := Stylesheet.GetUniversalCandidates;
      if Bucket <> nil then
        for I := 0 to Bucket.Count - 1 do
          Candidates.Add(Bucket[I]);

      // Sort by specificity then order to maintain correct cascade
      SortSelectorList(Candidates);

      // Process candidates
      for I := 0 to Candidates.Count - 1 do
        ApplyCandidate(Candidates[I]);
    finally
      Candidates.Free;
    end;
  end
  else
  begin
    // Fallback: linear scan when index not built
    for I := 0 to Stylesheet.Selectors.Count - 1 do
    begin
      Sel := Stylesheet.Selectors[I];

      // Quick-reject optimization
      if (Sel.Right.Tag <> PixieId('*')) and
         (Sel.Right.Tag <> FTag) then
        Continue;
      if Sel.Right.Attrs.Count > 0 then
      begin
        if (Sel.Right.Attrs[0].SelectType = selectClass) and
           not ListContainsIntSorted(FClasses, Sel.Right.Attrs[0].Name) then
          Continue;
      end;

      ApplyCandidate(Sel);
    end;
  end;

  for I := 0 to FChildren.Count - 1 do
    if FChildren[I].Css.Display <> displayInlineText then
      FChildren[I].ApplyStylesheet(Stylesheet);
end;

// Compute styles

procedure TPixieHtmlTag.ComputeStyles(Recursive: Boolean);
var
  StyleAttr: string;
  I: Integer;
  OldDisplay: TPixieDisplay;
begin
  OldDisplay := FCss.Display;

  StyleAttr := GetAttr('style');
  if StyleAttr <> '' then
    FStyle.Add(StyleAttr);

  FStyle.SubstVars(Self);
  FCss.Compute(Self, FDoc);

  // A change in display (e.g. :hover toggling display:none/block) alters the
  // render-tree structure, so a repaint alone is not enough — flag the
  // document for a render-tree rebuild before the next layout.
  if (FCss.Display <> OldDisplay) and (FDoc <> nil) then
    TPixieDocument(FDoc).MarkRenderTreeDirty;

  if Recursive then
    for I := 0 to FChildren.Count - 1 do
      FChildren[I].ComputeStyles;
end;

// Refresh styles

procedure TPixieHtmlTag.RefreshStyles;
var
  I, Apply: Integer;
  USel: TPixieUsedSelector;
  BeforeAfterEl: TPixieElement;
begin
  for I := 0 to FChildren.Count - 1 do
    if FChildren[I].Css.Display <> displayInlineText then
      FChildren[I].RefreshStyles;

  FStyle.Clear;
  ParseAttributes;

  if FUsedStyles = nil then
    FUsedStyles := TPixieUsedSelectorList.Create;
  for I := 0 to FUsedStyles.Count - 1 do
  begin
    USel := FUsedStyles[I];
    USel.Used := False;

    if USel.Selector.IsMediaValid then
    begin
      Apply := SelectSel(USel.Selector, False);
      if Apply <> SelectNoMatch then
      begin
        Assert(USel.Selector.Style is TPixieStyle);
        if (Apply and SelectMatchPseudoClass) <> 0 then
        begin
          if SelectSel(USel.Selector, True) <> SelectNoMatch then
          begin
            if (Apply and SelectMatchWithAfter) <> 0 then
            begin
              BeforeAfterEl := GetElementAfter(False);
              if BeforeAfterEl <> nil then
                BeforeAfterEl.AddStyle(
                  TPixieStyle(USel.Selector.Style));
            end
            else if (Apply and SelectMatchWithBefore) <> 0 then
            begin
              BeforeAfterEl := GetElementBefore(False);
              if BeforeAfterEl <> nil then
                BeforeAfterEl.AddStyle(
                  TPixieStyle(USel.Selector.Style));
            end
            else
            begin
              AddStyle(TPixieStyle(USel.Selector.Style));
              USel.Used := True;
            end;
          end;
        end
        else if (Apply and SelectMatchWithAfter) <> 0 then
        begin
          BeforeAfterEl := GetElementAfter(False);
          if BeforeAfterEl <> nil then
            BeforeAfterEl.AddStyle(
              TPixieStyle(USel.Selector.Style));
        end
        else if (Apply and SelectMatchWithBefore) <> 0 then
        begin
          BeforeAfterEl := GetElementBefore(False);
          if BeforeAfterEl <> nil then
            BeforeAfterEl.AddStyle(
              TPixieStyle(USel.Selector.Style));
        end
        else
        begin
          AddStyle(TPixieStyle(USel.Selector.Style));
          USel.Used := True;
        end;
      end;
    end;
  end;
end;

// Mouse events

function TPixieHtmlTag.OnMouseOver: Boolean;
var
  El: TPixieElement;
begin
  Result := False;
  El := Self;
  while El <> nil do
  begin
    if El.SetPseudoClass(Ord(psid_hover), True) then
      Result := True;
    El := El.Parent;
  end;
end;

function TPixieHtmlTag.OnMouseLeave: Boolean;
var
  El: TPixieElement;
begin
  Result := False;
  El := Self;
  while El <> nil do
  begin
    if El.SetPseudoClass(Ord(psid_hover), False) then
      Result := True;
    if El.SetPseudoClass(Ord(psid_active), False) then
      Result := True;
    El := El.Parent;
  end;
end;

function TPixieHtmlTag.OnLButtonDown: Boolean;
var
  El: TPixieElement;
begin
  Result := False;
  El := Self;
  while El <> nil do
  begin
    if El.SetPseudoClass(Ord(psid_active), True) then
      Result := True;
    El := El.Parent;
  end;
end;

function TPixieHtmlTag.OnLButtonUp(IsClick: Boolean): Boolean;
var
  El: TPixieElement;
begin
  Result := False;
  El := Self;
  while El <> nil do
  begin
    if El.SetPseudoClass(Ord(psid_active), False) then
      Result := True;
    El := El.Parent;
  end;
  if IsClick then
    OnClick;
end;

procedure TPixieHtmlTag.OnClick;
var
  Container: TPixieContainer;
  Par: TPixieElement;
begin
  if not IsRoot then
  begin
    Container := GetDocContainer;
    if (Container = nil) or
       not Container.OnElementClick(Self) then
    begin
      Par := Parent;
      if Par <> nil then
        Par.OnClick;
    end;
  end;
end;

// Pseudo-class handling

function TPixieHtmlTag.SetPseudoClass(Cls: Integer;
  Add: Boolean): Boolean;
var
  I: Integer;
begin
  Result := False;
  if Add then
  begin
    if not ListContainsInt(FPseudoClasses, Cls) then
    begin
      FPseudoClasses.Add(Cls);
      Result := True;
    end;
  end
  else
  begin
    I := FPseudoClasses.IndexOf(Cls);
    if I >= 0 then
    begin
      FPseudoClasses.Delete(I);
      Result := True;
    end;
  end;
end;

// Properties

function TPixieHtmlTag.IsWhiteSpace: Boolean;
begin
  Result := False;
end;

function TPixieHtmlTag.IsBody: Boolean;
begin
  Result := False;
end;

function TPixieHtmlTag.IsBreak: Boolean;
begin
  Result := False;
end;

function TPixieHtmlTag.IsReplaced: Boolean;
begin
  Result := False;
end;

// Text

procedure TPixieHtmlTag.GetText(var Text: string);
var
  I: Integer;
begin
  for I := 0 to FChildren.Count - 1 do
    FChildren[I].GetText(Text);
end;

procedure TPixieHtmlTag.SetTextContent(const AText: string);
var
  TextEl: TPixieElement;
begin
  ClearRecursive;
  if AText <> '' then
  begin
    TextEl := TPixieElText.Create(AText, FDoc);
    TPixieDocument(FDoc).RegisterElement(TextEl);
    AppendChild(TextEl);
  end;
end;

procedure TPixieHtmlTag.ResetStyle;
begin
  FStyle.Clear;
end;

procedure TPixieHtmlTag.ParseAttributes;
var
  I: Integer;
begin
  for I := 0 to FChildren.Count - 1 do
    FChildren[I].ParseAttributes;
end;

procedure TPixieHtmlTag.GetContentSize(var Sz: TPixieSize;
  MaxWidth: TPixiePixel);
begin
  Sz.Height := 0;
  if FCss.Display = displayBlock then
    Sz.Width := MaxWidth
  else
    Sz.Width := 0;
end;

procedure TPixieHtmlTag.AddStyle(const AStyle: TPixieStyle);
begin
  FStyle.Combine(AStyle);
  HandleCounterProperties(AStyle);
end;

// Draw (stub for Phase 4 — full implementation in Phase 5)

procedure TPixieHtmlTag.Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
  Clip: PPixiePosition; Ri: Pointer);
var
  Pos, BorderBox: TPixiePosition;
  RiObj: TPixieRenderItem;
  BdrRadius: TPixieBorderRadiuses;
  Doc: TPixieDocument;
begin
  Assert(TObject(Ri) is TPixieRenderItem);
  Assert(FDoc is TPixieDocument);
  RiObj := TPixieRenderItem(Ri);
  Pos := RiObj.Pos;
  Pos.X := Pos.X + X;
  Pos.Y := Pos.Y + Y;

  DrawBackground(Hdc, X, Y, Clip, Ri);

  if (FCss.Display = displayListItem) and
     ((FCss.ListStyleType <> lstNone) or
      (FCss.ListStyleImage <> '')) then
  begin
    if FCss.Overflow > ovVisible then
    begin
      BorderBox := Pos;
      BorderBox.AddMargins(RiObj.GetPaddings);
      BorderBox.AddMargins(RiObj.GetBorders);

      BdrRadius := FCss.CssBorders.Radius.CalcPercents(
        BorderBox.Width, BorderBox.Height);
      BdrRadius.SubMargins(RiObj.GetBorders);
      BdrRadius.SubMargins(RiObj.GetPaddings);

      Doc := TPixieDocument(FDoc);
      Doc.Container.SetClip(Pos, BdrRadius);
    end;

    DrawListMarker(Hdc, Pos, Ri);

    if FCss.Overflow > ovVisible then
    begin
      Doc := TPixieDocument(FDoc);
      Doc.Container.DelClip;
    end;
  end;
end;

procedure TPixieHtmlTag.DrawBackground(Hdc: PtrUInt; X, Y: TPixiePixel;
  Clip: PPixiePosition; Ri: Pointer);
var
  Pos, BorderBox, OutlineBox, ContentBox: TPixiePosition;
  RiObj: TPixieRenderItem;
  VOffset, BOffset: TPixiePixel;
  Bg: TPixieBackground;
  NumLayers, I: Integer;
  Layer: TPixieBackgroundLayer;
  Bdr: TPixieCssBorders;
  Borders: TPixieBorders;
  Doc: TPixieDocument;
  Boxes: TPixiePositionVector;
  Box: TPixiePosition;
  CssBdr: TPixieCssBorders;
  J: Integer;
  DecColor: TPixieWebColor;
  DecSegStart, BoxRight, BoxBottom: TPixiePixel;
  HasTextContent: Boolean;
  OutlineRadius: TPixieBorderRadiuses;
  OutlineGrow: TPixieMargins;

  procedure DrawDecSegment(SegX1, SegX2: TPixiePixel);
  var
    DecY: TPixiePixel;
  begin
    if SegX2 <= SegX1 then
      Exit;
    if (FCss.TextDecorationLine and TextDecorationLineUnderline) <> 0 then
    begin
      DecY := ContentBox.Y + FCss.FontMetrics.Ascent + 2;
      Doc.Container.DrawLine(Hdc,
        SegX1, DecY, SegX2, DecY,
        DecColor, 1, FCss.TextDecorationStyle);
    end;
    if (FCss.TextDecorationLine and TextDecorationLineOverline) <> 0 then
    begin
      DecY := ContentBox.Y;
      Doc.Container.DrawLine(Hdc,
        SegX1, DecY, SegX2, DecY,
        DecColor, 1, FCss.TextDecorationStyle);
    end;
    if (FCss.TextDecorationLine and TextDecorationLineLineThrough) <> 0 then
    begin
      DecY := ContentBox.Y + FCss.FontMetrics.Ascent - FCss.FontMetrics.XHeight / 2;
      Doc.Container.DrawLine(Hdc,
        SegX1, DecY, SegX2, DecY,
        DecColor, 1, FCss.TextDecorationStyle);
    end;
  end;

  function ChildOnLine(Child: TPixieRenderItem): Boolean;
  var
    CY: TPixiePixel;
  begin
    CY := Child.FPos.Y + Y;
    Result := (CY < BoxBottom) and (CY + Child.FPos.Height > ContentBox.Y);
  end;

  procedure DrawDecLines(Ri: TPixieRenderItem);
  var
    K: Integer;
    Child, Sibling: TPixieRenderItem;
    ChildLeft, ChildRight: TPixiePixel;
    SibLeft: TPixiePixel;
  begin
    for K := 0 to Ri.FChildren.Count - 1 do
    begin
      Child := Ri.FChildren[K];
      ChildLeft := Child.FPos.X + X;
      ChildRight := ChildLeft + Child.FPos.Width;
      // Skip children outside this content box fragment (X and Y)
      if (ChildRight <= ContentBox.X) or (ChildLeft >= BoxRight) or
         not ChildOnLine(Child) then
        Continue;
      if Child.SrcEl.IsReplaced then
      begin
        // Expand gap to include implicit whitespace between the
        // replaced element and its next neighbour on the same line.
        if K + 1 < Ri.FChildren.Count then
        begin
          Sibling := Ri.FChildren[K + 1];
          if ChildOnLine(Sibling) then
          begin
            SibLeft := Sibling.FPos.X + X;
            if SibLeft > ChildRight then
              ChildRight := SibLeft;
          end
          else
            // Next child is on a different line — extend gap to line end
            ChildRight := BoxRight;
        end
        else
          // No next child — extend gap to line end
          ChildRight := BoxRight;
        // Draw decoration segment before this replaced element
        DrawDecSegment(DecSegStart, ChildLeft);
        DecSegStart := ChildRight;
      end
      else if Child.SrcEl.Css.Display = displayInline then
        // Recurse into inline children to find nested replaced elements
        DrawDecLines(Child);
    end;
  end;
begin
  Assert(TObject(Ri) is TPixieRenderItem);
  Assert(FDoc is TPixieDocument);
  RiObj := TPixieRenderItem(Ri);
  Doc := TPixieDocument(FDoc);

  if not (FCss.Display in [displayInline, displayTableRow]) then
  begin
    // Block-level drawing
    Pos := RiObj.Pos;
    Pos.X := Pos.X + X;
    Pos.Y := Pos.Y + Y;

    BorderBox := Pos;
    BorderBox.AddMargins(RiObj.GetPaddings);
    BorderBox.AddMargins(RiObj.GetBorders);

    if ((Clip = nil) or BorderBox.DoesIntersect(Clip^)) or IsRoot then
    begin
      VOffset := RiObj.GetDrawVerticalOffset;
      BOffset := RiObj.GetDrawBottomOffset;
      Pos.Y := Pos.Y + VOffset;
      Pos.Height := Pos.Height - VOffset - BOffset;
      BorderBox.Y := BorderBox.Y + VOffset;
      BorderBox.Height := BorderBox.Height - VOffset - BOffset;

      Bg := GetBackground;
      if Bg <> nil then
      begin
        NumLayers := Bg.GetLayersNumber;
        for I := NumLayers - 1 downto 0 do
        begin
          if not Bg.GetLayer(I, Pos, Self, RiObj, Layer, Clip) then
            Continue;

          if IsRoot and (Clip <> nil) then
          begin
            Layer.ClipBox := Clip^;
            Layer.BorderBox := Clip^;
            // OriginBox already set by GetLayer (incl. fixed attachment)
          end;

          Layer.BorderBox.DoRound;
          Layer.ClipBox.DoRound;
          Layer.OriginBox.DoRound;

          // Nudge back a sub-pixel rounding overflow, but only for images
          // that fit the clip — oversized ones (background-size: cover) are
          // meant to overflow and be clipped per their position.
          if (Layer.OriginBox.Width <= Layer.ClipBox.Width) and
             (Layer.OriginBox.X + Layer.OriginBox.Width >
              Layer.ClipBox.X + Layer.ClipBox.Width) then
            Layer.OriginBox.X :=
              Layer.ClipBox.X + Layer.ClipBox.Width - Layer.OriginBox.Width;
          if (Layer.OriginBox.Height <= Layer.ClipBox.Height) and
             (Layer.OriginBox.Y + Layer.OriginBox.Height >
              Layer.ClipBox.Y + Layer.ClipBox.Height) then
            Layer.OriginBox.Y :=
              Layer.ClipBox.Y + Layer.ClipBox.Height - Layer.OriginBox.Height;

          Bg.DrawLayer(Hdc, I, Layer, Doc.Container, FCss.Color);
        end;
      end;

      Bdr := FCss.CssBorders;
      if Bdr.IsVisible then
      begin
        BorderBox.DoRound;
        Borders.InitFromCss(Bdr);
        Borders.Radius := Bdr.Radius.CalcPercents(
          BorderBox.Width, BorderBox.Height);
        Doc.Container.DrawBorders(Hdc, Borders, BorderBox, IsRoot);
      end;

      // Draw outline (outside border box, does not affect layout)
      if (FCss.OutlineStyle > bsHidden) and (FCss.OutlineWidth > 0) then
      begin
        Borders.InitUniform(FCss.OutlineWidth, FCss.OutlineStyle,
          FCss.OutlineColor);
        OutlineBox := BorderBox;
        OutlineBox.X := OutlineBox.X - FCss.OutlineWidth;
        OutlineBox.Y := OutlineBox.Y - FCss.OutlineWidth;
        OutlineBox.Width := OutlineBox.Width + FCss.OutlineWidth * 2;
        OutlineBox.Height := OutlineBox.Height + FCss.OutlineWidth * 2;
        OutlineBox.DoRound;
        // The outline follows the rounded border edge: take the element's
        // border-radius (which applies even with no border) and grow each
        // corner by the outline width so the stroke stays concentric.
        OutlineRadius := FCss.CssBorders.Radius.CalcPercents(
          BorderBox.Width, BorderBox.Height);
        if OutlineRadius.HasRadius then
        begin
          OutlineGrow.Init;
          OutlineGrow.Left := FCss.OutlineWidth;
          OutlineGrow.Right := FCss.OutlineWidth;
          OutlineGrow.Top := FCss.OutlineWidth;
          OutlineGrow.Bottom := FCss.OutlineWidth;
          OutlineRadius.AddMargins(OutlineGrow);
          Borders.Radius := OutlineRadius;
        end;
        Doc.Container.DrawBorders(Hdc, Borders, OutlineBox, False);
      end;
    end;
  end
  else
  begin
    // Inline element drawing
    Bg := GetBackground;

    Boxes := TPixiePositionVector.Create;
    try
      RiObj.GetInlineBoxes(Boxes);

      // Check once whether any child is non-replaced, non-space text
      HasTextContent := False;
      for I := 0 to FChildren.Count - 1 do
        if not FChildren[I].IsReplaced and
           not FChildren[I].IsSpace then
        begin
          HasTextContent := True;
          Break;
        end;

      for J := 0 to Boxes.Count - 1 do
      begin
        Box := Boxes[J];
        Box.X := Box.X + X;
        Box.Y := Box.Y + Y;
        // Inline boxes include margins for layout; shrink to border box
        // so background and border do not extend into the margin area.
        Box.SubMargins(RiObj.GetMargins);

        if (Clip = nil) or Box.DoesIntersect(Clip^) then
        begin
          ContentBox := Box;
          ContentBox.SubMargins(RiObj.GetBorders);
          ContentBox.SubMargins(RiObj.GetPaddings);

          FillChar(CssBdr, SizeOf(CssBdr), 0);

          // Set left borders radius for the first box
          if J = 0 then
          begin
            CssBdr.Radius.BottomLeftX := FCss.CssBorders.Radius.BottomLeftX;
            CssBdr.Radius.BottomLeftY := FCss.CssBorders.Radius.BottomLeftY;
            CssBdr.Radius.TopLeftX := FCss.CssBorders.Radius.TopLeftX;
            CssBdr.Radius.TopLeftY := FCss.CssBorders.Radius.TopLeftY;
          end;

          // Set right borders radius for the last box
          if J = Boxes.Count - 1 then
          begin
            CssBdr.Radius.BottomRightX := FCss.CssBorders.Radius.BottomRightX;
            CssBdr.Radius.BottomRightY := FCss.CssBorders.Radius.BottomRightY;
            CssBdr.Radius.TopRightX := FCss.CssBorders.Radius.TopRightX;
            CssBdr.Radius.TopRightY := FCss.CssBorders.Radius.TopRightY;
          end;

          CssBdr.Top := FCss.CssBorders.Top;
          CssBdr.Bottom := FCss.CssBorders.Bottom;
          if J = 0 then
            CssBdr.Left := FCss.CssBorders.Left;
          if J = Boxes.Count - 1 then
            CssBdr.Right := FCss.CssBorders.Right;

          if Bg <> nil then
          begin
            NumLayers := Bg.GetLayersNumber;
            for I := NumLayers - 1 downto 0 do
            begin
              if not Bg.GetLayer(I, ContentBox, Self, RiObj, Layer) then
                Continue;
              Layer.BorderRadius := CssBdr.Radius.CalcPercents(
                Box.Width, Box.Height);
              Layer.BorderBox.DoRound;
              Layer.ClipBox.DoRound;
              Layer.OriginBox.DoRound;
              Bg.DrawLayer(Hdc, I, Layer, Doc.Container, FCss.Color);
            end;
          end;

          if CssBdr.IsVisible then
          begin
            Borders.InitFromCss(CssBdr);
            Borders.Radius := CssBdr.Radius.CalcPercents(
              Box.Width, Box.Height);
            Box.DoRound;
            Doc.Container.DrawBorders(Hdc, Borders, Box, False);
          end;

          // Draw text-decoration lines skipping replaced elements
          if HasTextContent and (FCss.TextDecorationLine <> TextDecorationLineNone) then
          begin
            if FCss.TextDecorationColor.IsCurrentColor then
              DecColor := FCss.Color
            else
              DecColor := FCss.TextDecorationColor;
            BoxRight := ContentBox.X + ContentBox.Width;
            BoxBottom := ContentBox.Y + ContentBox.Height;
            DecSegStart := ContentBox.X;
            DrawDecLines(RiObj);
            DrawDecSegment(DecSegStart, BoxRight);
          end;
        end;
      end;
    finally
      Boxes.Free;
    end;
  end;
end;

// Nth-child

function TPixieHtmlTag.IsNthChild(El: TPixieElement;
  Num, Off: Integer; OfType: Boolean;
  SelectorList: TPixieCssSelectorList): Boolean;
var
  Idx, I, ChildTag: Integer;
  Child: TPixieElement;
begin
  Idx := 1;
  for I := 0 to FChildren.Count - 1 do
  begin
    Child := FChildren[I];
    if Child.Css.Display = displayInlineText then
      Continue;
    // Skip ::before/::after pseudo-elements — they are not real DOM children
    ChildTag := Child.GetTag;
    if (ChildTag = Ord(psid__tag_before)) or
       (ChildTag = Ord(psid__tag_after)) then
      Continue;
    if (not OfType and ((SelectorList = nil) or (SelectorList.Count = 0))) or
       (OfType and (ChildTag = El.GetTag)) or
       ((SelectorList <> nil) and (SelectorList.Count > 0) and
        (Child.Select(SelectorList) <> SelectNoMatch)) then
    begin
      if El = Child then
      begin
        if Num <> 0 then
        begin
          if ((Idx - Off) * Num >= 0) and ((Idx - Off) mod Num = 0) then
            Exit(True);
        end
        else if Idx = Off then
          Exit(True);
        Exit(False);
      end;
      Inc(Idx);
    end;
    if El = Child then
      Break;
  end;
  Result := False;
end;

function TPixieHtmlTag.IsNthLastChild(El: TPixieElement;
  Num, Off: Integer; OfType: Boolean;
  SelectorList: TPixieCssSelectorList): Boolean;
var
  Idx, I, ChildTag: Integer;
  Child: TPixieElement;
begin
  Idx := 1;
  for I := FChildren.Count - 1 downto 0 do
  begin
    Child := FChildren[I];
    if Child.Css.Display = displayInlineText then
      Continue;
    // Skip ::before/::after pseudo-elements — they are not real DOM children
    ChildTag := Child.GetTag;
    if (ChildTag = Ord(psid__tag_before)) or
       (ChildTag = Ord(psid__tag_after)) then
      Continue;
    if (not OfType and ((SelectorList = nil) or (SelectorList.Count = 0))) or
       (OfType and (ChildTag = El.GetTag)) or
       ((SelectorList <> nil) and (SelectorList.Count > 0) and
        (Child.Select(SelectorList) <> SelectNoMatch)) then
    begin
      if El = Child then
      begin
        if Num <> 0 then
        begin
          if ((Idx - Off) * Num >= 0) and ((Idx - Off) mod Num = 0) then
            Exit(True);
        end
        else if Idx = Off then
          Exit(True);
        Exit(False);
      end;
      Inc(Idx);
    end;
    if El = Child then
      Break;
  end;
  Result := False;
end;

function TPixieHtmlTag.IsOnlyChild(El: TPixieElement;
  OfType: Boolean): Boolean;
var
  ChildCount, I, ChildTag: Integer;
  Child: TPixieElement;
begin
  ChildCount := 0;
  for I := 0 to FChildren.Count - 1 do
  begin
    Child := FChildren[I];
    if Child.Css.Display = displayInlineText then
      Continue;
    // Skip ::before/::after pseudo-elements — they are not real DOM children
    ChildTag := Child.GetTag;
    if (ChildTag = Ord(psid__tag_before)) or
       (ChildTag = Ord(psid__tag_after)) then
      Continue;
    if not OfType or (ChildTag = El.GetTag) then
      Inc(ChildCount);
    if ChildCount > 1 then
      Break;
  end;
  Result := ChildCount <= 1;
end;

// Background

function TPixieHtmlTag.GetBackground(OwnOnly: Boolean): TPixieBackground;
var
  I: Integer;
  Par: TPixieElement;
begin
  if OwnOnly then
  begin
    if FCss.Bg.IsEmpty then
      Exit(nil);
    Exit(FCss.Bg);
  end;

  if FCss.Bg.IsEmpty then
  begin
    // If root element, try to get background from body
    if IsRoot then
    begin
      for I := 0 to FChildren.Count - 1 do
        if FChildren[I].IsBody then
          Exit(FChildren[I].GetBackground(True));
    end;
    Exit(nil);
  end;

  if IsBody then
  begin
    Par := Parent;
    if (Par <> nil) and (Par.GetBackground(True) = nil) then
      Exit(nil); // parent of body will draw background
  end;

  Result := FCss.Bg;
end;

// Before/after element helpers

function TPixieHtmlTag.GetElementBefore(
  DoCreate: Boolean): TPixieElement;
begin
  if FChildren.Count > 0 then
    if FChildren[0].GetTag = Ord(psid__tag_before) then
      Exit(FChildren[0]);
  if DoCreate then
    Exit(AddPseudoBefore);
  Result := nil;
end;

function TPixieHtmlTag.GetElementAfter(
  DoCreate: Boolean): TPixieElement;
begin
  if FChildren.Count > 0 then
    if FChildren[FChildren.Count - 1].GetTag =
       Ord(psid__tag_after) then
      Exit(FChildren[FChildren.Count - 1]);
  if DoCreate then
    Exit(AddPseudoAfter);
  Result := nil;
end;

// Counter handling

procedure TPixieHtmlTag.HandleCounterProperties(
  const AStyle: TPixieStyle);
var
  Prop: TPixiePropertyValue;
  Vec: TPixieStringVector;
  I, Val: Integer;
  Name: string;
begin
  // Process counters from the incoming style only, not the combined
  // FStyle — otherwise counters are re-processed each time a new
  // selector matches the same element.

  // counter-reset: name [value] name [value] ...
  Prop := AStyle.GetProperty(Ord(psid_counter_reset));
  if (Prop.Kind = pkStringVector) and (Prop.StringVecVal <> nil) then
  begin
    Vec := Prop.StringVecVal;
    I := 0;
    while I < Vec.Count do
    begin
      Name := Vec[I];
      Inc(I);
      if (I < Vec.Count) and TryStrToInt(Vec[I], Val) then
        Inc(I)
      else
        Val := 0;
      ResetCounter(PixieId(Name), Val);
    end;
    Exit;
  end;

  // counter-increment: name [value] name [value] ...
  Prop := AStyle.GetProperty(Ord(psid_counter_increment));
  if (Prop.Kind = pkStringVector) and (Prop.StringVecVal <> nil) then
  begin
    Vec := Prop.StringVecVal;
    I := 0;
    while I < Vec.Count do
    begin
      Name := Vec[I];
      Inc(I);
      if (I < Vec.Count) and TryStrToInt(Vec[I], Val) then
        Inc(I)
      else
        Val := 1;
      IncrementCounter(PixieId(Name), Val);
    end;
  end;
end;

// HTML dimension parsing helpers

function TPixieHtmlTag.ParseNonNegativeInteger(const S: string;
  out N: Integer): Boolean;
var
  Stripped: string;
  Code: Integer;
begin
  Stripped := PixieExtractInteger(PixieTrim(S));
  if Stripped = '' then
    Exit(False);
  System.Val(Stripped, N, Code);
  Result := Code = 0;
end;

function TPixieHtmlTag.ParseDimensionValue(const S: string;
  out X: Single; out IsPercent: Boolean): Boolean;
var
  Trimmed, Stripped: string;
  Code: Integer;
begin
  Trimmed := PixieTrim(S);
  IsPercent := False;
  if Trimmed = '' then
    Exit(False);
  if Trimmed[Length(Trimmed)] = '%' then
  begin
    IsPercent := True;
    Trimmed := Copy(Trimmed, 1, Length(Trimmed) - 1);
  end;
  Stripped := PixieExtractFloat(Trimmed);
  if Stripped = '' then
    Exit(False);
  System.Val(Stripped, X, Code);
  Result := (Code = 0) and (X >= 0);
end;

function TPixieHtmlTag.ParseNonzeroDimensionValue(const S: string;
  out X: Single; out IsPercent: Boolean): Boolean;
begin
  Result := ParseDimensionValue(S, X, IsPercent) and (X <> 0);
end;

procedure TPixieHtmlTag.MapToPixelLengthProperty(PropName: Integer;
  const AttrValue: string);
var
  N: Integer;
  Tok: TPixieCssToken;
  Tokens: TPixieCssTokenList;
begin
  if ParseNonNegativeInteger(AttrValue, N) then
  begin
    Tok := TPixieCssToken.Create;
    Tok.TokenType := cssTokenDimension;
    Tok.Number := N;
    Tok.NumberType := cssNumberInteger;
    Tok.Str := 'px';
    Tokens := TPixieCssTokenList.Create;
    try
      Tokens.Add(Tok);
      FStyle.AddProperty(PropName, Tokens);
    finally
      Tokens.Free;
    end;
  end;
end;

procedure TPixieHtmlTag.MapToPixelLengthPropertyWithDefault(
  PropName: Integer; const AttrValue: string; DefaultVal: Integer);
var
  N: Integer;
  Tok: TPixieCssToken;
  Tokens: TPixieCssTokenList;
begin
  N := DefaultVal;
  ParseNonNegativeInteger(AttrValue, N);
  Tok := TPixieCssToken.Create;
  Tok.TokenType := cssTokenDimension;
  Tok.Number := N;
  Tok.NumberType := cssNumberInteger;
  Tok.Str := 'px';
  Tokens := TPixieCssTokenList.Create;
  try
    Tokens.Add(Tok);
    FStyle.AddProperty(PropName, Tokens);
  finally
    Tokens.Free;
  end;
end;

procedure TPixieHtmlTag.MapToDimensionProperty(PropName: Integer;
  const AttrValue: string);
var
  X: Single;
  IsPct: Boolean;
  Tok: TPixieCssToken;
  Tokens: TPixieCssTokenList;
begin
  if not ParseDimensionValue(AttrValue, X, IsPct) then
    Exit;
  Tok := TPixieCssToken.Create;
  if IsPct then
  begin
    Tok.TokenType := cssTokenPercentage;
    Tok.Number := X;
    Tok.NumberType := cssNumberNumber;
  end
  else
  begin
    Tok.TokenType := cssTokenDimension;
    Tok.Number := X;
    Tok.NumberType := cssNumberNumber;
    Tok.Str := 'px';
  end;
  Tokens := TPixieCssTokenList.Create;
  try
    Tokens.Add(Tok);
    FStyle.AddProperty(PropName, Tokens);
  finally
    Tokens.Free;
  end;
end;

procedure TPixieHtmlTag.MapToDimensionPropertyIgnoreZero(
  PropName: Integer; const AttrValue: string);
var
  X: Single;
  IsPct: Boolean;
  Tok: TPixieCssToken;
  Tokens: TPixieCssTokenList;
begin
  if not ParseNonzeroDimensionValue(AttrValue, X, IsPct) then
    Exit;
  Tok := TPixieCssToken.Create;
  if IsPct then
  begin
    Tok.TokenType := cssTokenPercentage;
    Tok.Number := X;
    Tok.NumberType := cssNumberNumber;
  end
  else
  begin
    Tok.TokenType := cssTokenDimension;
    Tok.Number := X;
    Tok.NumberType := cssNumberNumber;
    Tok.Str := 'px';
  end;
  Tokens := TPixieCssTokenList.Create;
  try
    Tokens.Add(Tok);
    FStyle.AddProperty(PropName, Tokens);
  finally
    Tokens.Free;
  end;
end;

procedure TPixieHtmlTag.MapAlignToTextAlign(const AttrValue: string);
begin
  if SameText(AttrValue, 'center') then
    FStyle.AddProperty(Ord(psid_text_align), SPixieBlockCenter)
  else if SameText(AttrValue, 'left') then
    FStyle.AddProperty(Ord(psid_text_align), SPixieBlockLeft)
  else if SameText(AttrValue, 'right') then
    FStyle.AddProperty(Ord(psid_text_align), SPixieBlockRight)
  else
    FStyle.AddProperty(Ord(psid_text_align), AttrValue);
end;

// List marker text

function TPixieHtmlTag.GetListMarkerText(Index: Integer): string;
begin
  Result := PixieFormatListCounter(Index, FCss.ListStyleType);
end;

procedure TPixieHtmlTag.DrawListMarker(Hdc: PtrUInt;
  const Pos: TPixiePosition; Ri: Pointer);
var
  Lm: TPixieListMarker;
  ImgSz: TPixieSize;
  Doc: TPixieDocument;
  RiObj: TPixieRenderItem;
  LnHeight, SzFont: TPixiePixel;
  LiBaseline, TwSpace, Tw: TPixiePixel;
  MarkerText: string;
  TextPos: TPixiePosition;
begin
  Assert(FDoc is TPixieDocument);
  Assert(TObject(Ri) is TPixieRenderItem);
  Doc := TPixieDocument(FDoc);
  RiObj := TPixieRenderItem(Ri);
  ImgSz.Width := 0;
  ImgSz.Height := 0;

  if FCss.ListStyleImage <> '' then
  begin
    Lm.Image := FCss.ListStyleImage;
    Lm.BaseUrl := FCss.ListStyleImageBaseUrl;
    Doc.Container.GetImageSize(Lm.Image, Lm.BaseUrl, ImgSz);
  end
  else
    Lm.BaseUrl := '';

  LnHeight := FCss.LineHeight.ComputedValue;
  SzFont := FCss.FontSize;
  Lm.Pos.X := Pos.X;
  Lm.Pos.Width := SzFont / 3;
  Lm.Color := FCss.Color;
  Lm.MarkerType := FCss.ListStyleType;
  Lm.Font := FCss.Font;

  if FCss.ListStyleType >= lstArmenian then
  begin
    LiBaseline := Pos.Y + RiObj.GetFirstBaseline - RiObj.ContentOffsetTop;
    Lm.Pos.Y := LiBaseline - FCss.FontMetrics.Ascent;
    Lm.Pos.Height := FCss.FontMetrics.Height;
    Lm.Index := StrToIntDef(GetAttr('list_index', '0'), 0);
  end
  else
  begin
    Lm.Pos.Height := SzFont / 3;
    Lm.Pos.Y := Pos.Y + LnHeight / 2 - Lm.Pos.Height / 2;
    Lm.Index := -1;
  end;

  if (ImgSz.Width <> 0) and (ImgSz.Height <> 0) then
  begin
    if Lm.Pos.Y + ImgSz.Height > Pos.Y + Pos.Height then
      Lm.Pos.Y := Pos.Y + Pos.Height - ImgSz.Height;
    if ImgSz.Width > Lm.Pos.Width then
      Lm.Pos.X := Lm.Pos.X - (ImgSz.Width - Lm.Pos.Width);
    Lm.Pos.Width := ImgSz.Width;
    Lm.Pos.Height := ImgSz.Height;
  end;

  if FCss.ListStylePosition = lspOutside then
  begin
    if FCss.ListStyleType >= lstArmenian then
    begin
      if Lm.Font <> 0 then
      begin
        TwSpace := Doc.Container.TextWidth(' ', Lm.Font);
        Lm.Pos.X := Pos.X - TwSpace * 2;
        Lm.Pos.Width := TwSpace;
      end
      else
        Lm.Pos.Width := 0;
    end
    else
      Lm.Pos.X := Lm.Pos.X - SzFont;
  end;

  if FCss.ListStyleType >= lstArmenian then
  begin
    MarkerText := GetListMarkerText(Lm.Index);
    if MarkerText = '' then
      Doc.Container.DrawListMarker(Hdc, Lm)
    else if Lm.Font <> 0 then
    begin
      MarkerText := MarkerText + '.';
      Tw := Doc.Container.TextWidth(PChar(MarkerText), Lm.Font);
      TextPos := Lm.Pos;
      TextPos.MoveTo(TextPos.Right - Tw, TextPos.Y);
      TextPos.Width := Tw;
      TextPos.DoRound;
      Doc.Container.DrawText(Hdc, PChar(MarkerText), Lm.Font, Lm.Color,
        TextPos);
    end;
  end
  else
    Doc.Container.DrawListMarker(Hdc, Lm);
end;

// Dump

function TPixieHtmlTag.DumpGetName: string;
begin
  if FTag = -1 then
    Result := 'anon [html_tag]'
  else
    Result := PixieStr(FTag) + ' [html_tag]';
end;

// Select all / select one

procedure TPixieHtmlTag.SelectAll(const Selector: TPixieCssSelector;
  Res: TPixieElementList);
var
  I: Integer;
begin
  if SelectSel(Selector) <> SelectNoMatch then
    Res.Add(Self);
  for I := 0 to FChildren.Count - 1 do
    FChildren[I].SelectAll(Selector, Res);
end;

// Document access helpers — stubs until Pixie.Document is in implementation uses

function TPixieHtmlTag.GetDocContainer: TPixieContainer;
begin
  if FDoc <> nil then
  begin
    Assert(FDoc is TPixieDocument);
    Result := TPixieDocument(FDoc).Container;
  end
  else
    Result := nil;
end;

function TPixieHtmlTag.MatchDocLang(const Lang: string): Boolean;
begin
  if FDoc <> nil then
  begin
    Assert(FDoc is TPixieDocument);
    Result := TPixieDocument(FDoc).MatchLang(Lang);
  end
  else
    Result := False;
end;

end.
