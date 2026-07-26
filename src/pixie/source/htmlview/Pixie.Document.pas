unit Pixie.Document;

// Document class — owns DOM tree, manages stylesheet application,
// style computation, font caching, unit conversion, and rendering.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections,
  Pixie.Types, Pixie.CssLength, Pixie.WebColor,
  Pixie.FontDescription,
  Pixie.Container, Pixie.Element,
  Pixie.Style, Pixie.Stylesheet, Pixie.FontFace,
  Pixie.MediaQuery, Pixie.CssProperties;

type
  TPixieDocumentChangeEvent = procedure(Sender: TObject) of object;

  TPixieCssText = record
    Text: string;
    BaseUrl: string;
    Media: string;
  end;
  TPixieCssTextList = TList<TPixieCssText>;

  TPixieFontItem = record
    Font: PtrUInt;
    Metrics: TPixieFontMetrics;
  end;
  TPixieFontsMap = TDictionary<string, TPixieFontItem>;
  TPixieSelectionSet = TDictionary<Pointer, Boolean>;

  { TPixieDocument }

  TPixieDocument = class
  private
    FRoot: TPixieElement;
    FRootRender: Pointer;
    FContainer: TPixieContainer;
    FFonts: TPixieFontsMap;
    FCss: TPixieCssTextList;
    FStyles: TPixieStylesheet;
    FDefColor: TPixieWebColor;
    FMasterCss: TPixieStylesheet;
    FUserCss: TPixieStylesheet;
    FFontFaceRegistry: TPixieFontFaceRegistry;
    FSize: TPixieSize;
    FFixedBoxes: TPixiePositionVector;
    FOverElement: TPixieElement;
    FActiveElement: TPixieElement;
    FMedia: TPixieMediaFeatures;
    FLang: string;
    FCulture: string;
    FMode: TPixieDocumentMode;
    FAllElements: TPixieElementList;
    FTabularElements: TPixiePointerList; // non-owning list of TPixieRenderItem

    // Focus state
    FFocusedElement: TPixieElement;
    FLastMouseX: TPixiePixel;
    FLastMouseY: TPixiePixel;
    FOnChange: TPixieDocumentChangeEvent;

    // Update batching
    FUpdateCount: Integer;
    FUpdateDirty: Boolean;
    FRebuilding: Boolean;
    FRenderTreeDirty: Boolean;

    // Selection state
    FSelAnchor: TPixieElement;
    FSelFocus: TPixieElement;
    FSelAnchorOffset: Integer;
    FSelFocusOffset: Integer;
    FSelAnchorIdx: Integer;
    FSelFocusIdx: Integer;
    FSelecting: Boolean;
    FSelMap: TPixieSelectionSet;
    FWordSelAnchor: TPixieElement;

    function RenderAbsoluteX(Ri: Pointer): TPixiePixel;
    function ComputeTextOffset(El: TPixieElement;
      X: TPixiePixel): Integer;

    function AddFont(const Descr: TPixieFontDescription;
      out Metrics: TPixieFontMetrics): PtrUInt;
    procedure BuildSelectedElements;
    procedure RebuildRenderItems;
    procedure RebuildRenderTree;

  public
    constructor Create(AContainer: TPixieContainer);
    destructor Destroy; override;

    // Static factory
    class function CreateFromString(const Str: string;
      AContainer: TPixieContainer;
      const MasterStyles: string = '';
      const UserStyles: string = ''): TPixieDocument; static;

    // Accessors
    property Container: TPixieContainer read FContainer;
    property FontFaceRegistry: TPixieFontFaceRegistry read FFontFaceRegistry;
    property Mode: TPixieDocumentMode read FMode;
    property DefColor: TPixieWebColor read FDefColor;
    function Root: TPixieElement;

    // Font management
    function GetFont(const Descr: TPixieFontDescription;
      out Metrics: TPixieFontMetrics): PtrUInt;

    // Unit conversion
    procedure CvtUnits(var Val: TPixieCssLength;
      const Metrics: TPixieFontMetrics; Size: TPixiePixel);
    function ToPixels(const Val: TPixieCssLength;
      const Metrics: TPixieFontMetrics; Size: TPixiePixel): TPixiePixel;

    // Document size
    function Width: TPixiePixel;
    function Height: TPixiePixel;

    // CSS management
    procedure AddStylesheet(const Str, BaseUrl, Media: string);
    function CreateElement(const TagName: string;
      Attrs: TPixieStringMap): TPixieElement;

    // Media queries
    function CheckMediaChanged: Boolean;
    function MatchLang(const Lang: string): Boolean;

    // Render tree access
    function RootRender: Pointer;
    procedure AddFixedBox(const Box: TPixiePosition);
    procedure AddTabular(Ri: TObject);
    procedure MarkRenderTreeDirty;

    // Rendering (Phase 5 stubs)
    function Render(MaxWidth: TPixiePixel): TPixiePixel;
    procedure Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
      Clip: PPixiePosition);

    // Mouse events (Phase 5 stubs)
    function OnMouseOver(X, Y, ClientX, ClientY: TPixiePixel;
      RedrawBoxes: TPixiePositionVector): Boolean;
    function OnMouseLeave(
      RedrawBoxes: TPixiePositionVector): Boolean;
    function OnLButtonDown(X, Y, ClientX, ClientY: TPixiePixel;
      RedrawBoxes: TPixiePositionVector): Boolean;
    function OnLButtonUp(X, Y, ClientX, ClientY: TPixiePixel;
      RedrawBoxes: TPixiePositionVector): Boolean;

    // Table fix-up (Phase 5 stub)
    procedure FixTablesLayout;

    // Element registration
    procedure RegisterElement(El: TPixieElement);
    procedure UnregisterElement(El: TPixieElement);

    // Focus management
    procedure SetFocus(El: TPixieElement);
    function FocusedElement: TPixieElement;
    function DispatchKeyDown(Key: Word; Shift: TShiftState): Boolean;
    function DispatchUTF8KeyPress(const UTF8Char: string): Boolean;
    function FocusNext: Boolean;
    function FocusPrev: Boolean;
    function DispatchDblClick: Boolean;
    function DispatchMouseDrag(X, Y: TPixiePixel): Boolean;
    function DispatchMouseWheel(X, Y: TPixiePixel;
      Delta: Integer): Boolean;
    function GetFocusedCaretPos(out X, Y, H: TPixiePixel): Boolean;
    property ActiveElement: TPixieElement read FActiveElement;
    property LastMouseX: TPixiePixel read FLastMouseX;
    property LastMouseY: TPixiePixel read FLastMouseY;

    // DOM mutation API
    function CreateTextNode(const AText: string): TPixieElement;
    function GetElementById(const Id: string): TPixieElement;
    function FindAnchorTarget(const Name: string): TPixieElement;
    function QuerySelector(
      const Selector: string): TPixieElement;
    function QuerySelectorAll(
      const Selector: string): TPixieElementList;
    procedure SetInnerHtml(Parent: TPixieElement;
      const Html: string);
    procedure RemoveElement(El: TPixieElement);
    procedure SetElementText(El: TPixieElement;
      const AText: string);
    procedure Rebuild;
    procedure BeginUpdate;
    procedure EndUpdate;
    procedure Changed;
    property OnChange: TPixieDocumentChangeEvent
      read FOnChange write FOnChange;

    // Text selection
    procedure SelectionStart(X, Y, ClientX, ClientY: TPixiePixel);
    function SelectionMove(X, Y, ClientX, ClientY: TPixiePixel): Boolean;
    function SelectionMoveWord(X, Y, ClientX, ClientY: TPixiePixel): Boolean;
    function SelectWord(X, Y: TPixiePixel): Boolean;
    procedure SelectionEnd;
    procedure SelectAll;
    procedure ClearSelection;
    function HasSelection: Boolean;
    function HasRangeSelection: Boolean;
    function IsSelected(El: TPixieElement): Boolean;
    function IsSelectedPartial(El: TPixieElement;
      out StartOff, EndOff: Integer): Boolean;
    function GetSelectedText: string;
  end;

implementation

uses
  Pixie.StringId, Pixie.Utils,
  Pixie.HtmlParser, Pixie.MasterCss,
  Pixie.CssTokenizer, Pixie.CssParser, Pixie.CssSelector,
  Pixie.HtmlTag,
  Pixie.ElText, Pixie.ElImage, Pixie.ElSvg,
  Pixie.ElInput, Pixie.ElTextInput, Pixie.ElProgress, Pixie.ElRange,
  Pixie.ElTable, Pixie.ElAnchor, Pixie.ElMisc, Pixie.ElDetails,
  Pixie.ElBeforeAfter,
  Pixie.RenderItem, Pixie.RenderBlock,
  Pixie.RenderInline, Pixie.RenderTable;

{ TPixieDocument }

constructor TPixieDocument.Create(AContainer: TPixieContainer);
begin
  inherited Create;
  FContainer := AContainer;
  FFonts := TPixieFontsMap.Create;
  FCss := TPixieCssTextList.Create;
  FStyles := TPixieStylesheet.Create;
  FMasterCss := TPixieStylesheet.Create;
  FUserCss := TPixieStylesheet.Create;
  FFixedBoxes := TPixiePositionVector.Create;
  FTabularElements := TPixiePointerList.Create;
  FAllElements := TPixieElementList.Create(True); // owns elements
  FSelMap := TPixieSelectionSet.Create;
  FFontFaceRegistry := TPixieFontFaceRegistry.Create;
  FSize.Width := 0;
  FSize.Height := 0;
  FDefColor := TPixieWebColor.Black;
  FMode := dmNoQuirks;
  FRoot := nil;
  FRootRender := nil;
  FOverElement := nil;
  FActiveElement := nil;
  FFocusedElement := nil;
  FSelAnchor := nil;
  FSelFocus := nil;
  FSelAnchorOffset := 0;
  FSelFocusOffset := 0;
  FSelAnchorIdx := -1;
  FSelFocusIdx := -1;
  FSelecting := False;
  FWordSelAnchor := nil;
end;

destructor TPixieDocument.Destroy;
var
  I: Integer;
  Pair: TPair<string, TPixieFontItem>;
begin
  FOverElement := nil;
  FActiveElement := nil;
  FFocusedElement := nil;
  FSelAnchor := nil;
  FSelFocus := nil;
  FRoot := nil;

  // Free render tree (root owns all children via OwnsObjects)
  if FRootRender <> nil then
  begin
    TObject(FRootRender).Free;
    FRootRender := nil;
  end;

  // Delete fonts via container
  if FContainer <> nil then
  begin
    for Pair in FFonts do
      FContainer.DeleteFont(Pair.Value.Font);
    // Uninstall @font-face fonts
    for I := 0 to FFontFaceRegistry.Entries.Count - 1 do
      if FFontFaceRegistry.Entries[I].Loaded and
         (FFontFaceRegistry.Entries[I].InstalledHandle <> 0) then
        FContainer.UninstallFont(FFontFaceRegistry.Entries[I].InstalledHandle);
  end;

  FFontFaceRegistry.Free;
  FSelMap.Free;
  FAllElements.Free;
  FTabularElements.Free;
  FFixedBoxes.Free;
  FUserCss.Free;
  FMasterCss.Free;
  FStyles.Free;
  FCss.Free;
  FFonts.Free;
  inherited Destroy;
end;

type
  PSplitTextContext = ^TSplitTextContext;
  TSplitTextContext = record
    Doc: TPixieDocument;
    Elements: TPixieElementList;
  end;

// Callback for SplitText
procedure TextSplitCallback(const Text: string;
  Kind: TPixieTextPieceKind; UserData: Pointer);
var
  Ctx: PSplitTextContext;
  El: TPixieElement;
begin
  Ctx := PSplitTextContext(UserData);
  case Kind of
    tpWord:
      El := TPixieElText.Create(Text, Ctx^.Doc);
    tpSpace:
      El := TPixieElSpace.Create(Text, Ctx^.Doc);
  else
    Exit;
  end;
  Ctx^.Doc.RegisterElement(El);
  Ctx^.Elements.Add(El);
end;

// --- Factory ---

procedure CreateNode(Doc: TPixieDocument; Node: TPixieHtmlNode;
  Elements: TPixieElementList; ParseTextNode, ProcessRoot: Boolean);
var
  I, J: Integer;
  El: TPixieElement;
  ChildList: TPixieElementList;
  Attrs: TPixieStringMap;
  Attr: TPixieHtmlAttribute;
  SplitCtx: TSplitTextContext;
begin
  case Node.NodeType of
    hntElement:
    begin
      if ProcessRoot then
      begin
        // Collect attributes
        Attrs := TPixieStringMap.Create;
        try
          for I := 0 to Node.Attributes.Count - 1 do
          begin
            Attr := Node.Attributes[I];
            Attrs.AddOrSetValue(Attr.Name, Attr.Value);
          end;

          El := Doc.CreateElement(Node.Tag, Attrs);
        finally
          Attrs.Free;
        end;

        if El = nil then
          Exit;

        // Disable text splitting inside script
        if Node.Tag = 'script' then
          ParseTextNode := False;

        // Process children
        ChildList := TPixieElementList.Create(False);
        try
          for I := 0 to Node.Children.Count - 1 do
          begin
            ChildList.Clear;
            CreateNode(Doc, Node.Children[I], ChildList,
              ParseTextNode, True);
            for J := 0 to ChildList.Count - 1 do
              El.AppendChild(ChildList[J]);
          end;
        finally
          ChildList.Free;
        end;

        Elements.Add(El);
      end
      else
      begin
        // Skip this node, process children directly
        for I := 0 to Node.Children.Count - 1 do
          CreateNode(Doc, Node.Children[I], Elements,
            ParseTextNode, True);
      end;
    end;

    hntText:
    begin
      if not ParseTextNode then
      begin
        // Raw text (inside script/style)
        El := TPixieElText.Create(Node.Text, Doc);
        Doc.RegisterElement(El);
        Elements.Add(El);
      end
      else
      begin
        // Split text into words and spaces
        if Doc.Container <> nil then
        begin
          SplitCtx.Doc := Doc;
          SplitCtx.Elements := Elements;
          Doc.Container.SplitText(Node.Text,
            @TextSplitCallback, @SplitCtx);
        end
        else
        begin
          // Fallback: single text node
          El := TPixieElText.Create(Node.Text, Doc);
          Doc.RegisterElement(El);
          Elements.Add(El);
        end;
      end;
    end;

    hntWhitespace:
    begin
      // Split whitespace into individual characters so that
      // newlines are preserved in pre/pre-wrap/pre-line modes
      if Doc.Container <> nil then
      begin
        SplitCtx.Doc := Doc;
        SplitCtx.Elements := Elements;
        Doc.Container.SplitText(Node.Text,
          @TextSplitCallback, @SplitCtx);
      end
      else
      begin
        El := TPixieElSpace.Create(Node.Text, Doc);
        Doc.RegisterElement(El);
        Elements.Add(El);
      end;
    end;

    hntCData:
    begin
      El := TPixieElCData.Create(Doc);
      El.SetData(Node.Text);
      Doc.RegisterElement(El);
      Elements.Add(El);
    end;

    hntComment:
    begin
      El := TPixieElComment.Create(Doc);
      El.SetData(Node.Text);
      Doc.RegisterElement(El);
      Elements.Add(El);
    end;
  end;
end;

class function TPixieDocument.CreateFromString(const Str: string;
  AContainer: TPixieContainer; const MasterStyles: string;
  const UserStyles: string): TPixieDocument;
var
  Doc: TPixieDocument;
  ParsedHtml: TPixieHtmlNode;
  RootElements: TPixieElementList;
  I: Integer;
  CssEntry: TPixieCssText;
  MqList: TPixieMediaQueryList;
  MqLL: TPixieMediaQueryListList;
  ActualMaster: string;
begin
  Doc := TPixieDocument.Create(AContainer);
  try
    // Parse HTML
    ParsedHtml := PixieParseHtml(Str);
    try
      // Set quirks mode from DOCTYPE
      case ParsedHtml.QuirksMode of
        hqNoQuirks:       Doc.FMode := dmNoQuirks;
        hqQuirks:         Doc.FMode := dmQuirks;
        hqLimitedQuirks:  Doc.FMode := dmLimitedQuirks;
      end;

      // Convert parse tree to DOM elements
      RootElements := TPixieElementList.Create(False);
      try
        // Find the root element node (skip the document node)
        for I := 0 to ParsedHtml.Children.Count - 1 do
          if ParsedHtml.Children[I].NodeType = hntElement then
          begin
            CreateNode(Doc, ParsedHtml.Children[I], RootElements,
              True, True);
          end;

        if RootElements.Count > 0 then
          Doc.FRoot := RootElements[RootElements.Count - 1];
      finally
        RootElements.Free;
      end;
    finally
      ParsedHtml.Free;
    end;

    // Parse master CSS
    if MasterStyles <> '' then
      ActualMaster := MasterStyles
    else
      ActualMaster := PixieMasterCss;

    if ActualMaster <> '' then
    begin
      Doc.FMasterCss.ParseCssStylesheet(ActualMaster, '',
        Doc.FMode);
      if Doc.FMode = dmQuirks then
        Doc.FMasterCss.ParseCssStylesheet(PixieQuirksCss, '',
          Doc.FMode);
      Doc.FMasterCss.SortSelectors;
    end;

    // Parse user CSS
    if UserStyles <> '' then
    begin
      Doc.FUserCss.ParseCssStylesheet(UserStyles, '', Doc.FMode);
      Doc.FUserCss.SortSelectors;
    end;

    // Process the element tree
    if Doc.FRoot <> nil then
    begin
      if Doc.FContainer <> nil then
        Doc.FContainer.GetMediaFeatures(Doc.FMedia);

      Doc.FRoot.SetPseudoClass(Ord(psid_root), True);

      // Apply master CSS
      Doc.FRoot.ApplyStylesheet(Doc.FMasterCss);

      // Parse element attributes
      Doc.FRoot.ParseAttributes;

      // Parse linked stylesheets (collected during ParseAttributes)
      Doc.FStyles.FontFaces := Doc.FFontFaceRegistry.Entries;
      for I := 0 to Doc.FCss.Count - 1 do
      begin
        CssEntry := Doc.FCss[I];
        MqLL := nil;
        if CssEntry.Media <> '' then
        begin
          MqList := TPixieMediaQueryList.ParseFromString(
            CssEntry.Media);
          if MqList <> nil then
          begin
            MqLL := TPixieMediaQueryListList.Create;
            MqLL.Add(MqList);
          end;
        end;
        Doc.FStyles.ParseCssStylesheet(CssEntry.Text,
          CssEntry.BaseUrl, Doc.FMode, MqLL);
      end;
      Doc.FStyles.FontFaces := nil;
      Doc.FStyles.SortSelectors;

      // Apply media features
      Doc.FMasterCss.ApplyMediaFeatures(Doc.FMedia);
      Doc.FStyles.ApplyMediaFeatures(Doc.FMedia);
      Doc.FUserCss.ApplyMediaFeatures(Doc.FMedia);

      // Apply parsed styles
      Doc.FRoot.ApplyStylesheet(Doc.FStyles);

      // Apply user styles
      Doc.FRoot.ApplyStylesheet(Doc.FUserCss);

      // Compute styles
      Doc.FRoot.ComputeStyles;

      // Render tree creation, table fix-up, context init
      Doc.RebuildRenderItems;
    end;

    Result := Doc;
  except
    Doc.Free;
    raise;
  end;
end;

// --- Accessors ---

function TPixieDocument.Root: TPixieElement;
begin
  Result := FRoot;
end;

function TPixieDocument.Width: TPixiePixel;
begin
  Result := FSize.Width;
end;

function TPixieDocument.Height: TPixiePixel;
begin
  Result := FSize.Height;
end;

// --- Font Management ---

function TPixieDocument.AddFont(const Descr: TPixieFontDescription;
  out Metrics: TPixieFontMetrics): PtrUInt;
var
  Key: string;
  Item: TPixieFontItem;
begin
  Result := 0;
  Key := Descr.Hash;

  if not FFonts.ContainsKey(Key) then
  begin
    Item.Font := 0;
    FillChar(Item.Metrics, SizeOf(Item.Metrics), 0);

    if FContainer <> nil then
      Item.Font := FContainer.CreateFont(Descr, Self, Item.Metrics);

    FFonts.Add(Key, Item);
    Result := Item.Font;
    Metrics := Item.Metrics;
  end;
end;

function TPixieDocument.GetFont(const Descr: TPixieFontDescription;
  out Metrics: TPixieFontMetrics): PtrUInt;
var
  Key: string;
  Item: TPixieFontItem;
begin
  if Descr.Size = 0 then
  begin
    FillChar(Metrics, SizeOf(Metrics), 0);
    Exit(0);
  end;

  Key := Descr.Hash;
  if FFonts.TryGetValue(Key, Item) then
  begin
    Metrics := Item.Metrics;
    Result := Item.Font;
  end
  else
  begin
    Result := AddFont(Descr, Metrics);
  end;
end;

// --- Unit Conversion ---

function TPixieDocument.ToPixels(const Val: TPixieCssLength;
  const Metrics: TPixieFontMetrics; Size: TPixiePixel): TPixiePixel;
begin
  if Val.IsPredefined then
    Exit(0);

  case Val.Units of
    cssUnitsPercentage:
      Result := Val.CalcPercent(Size);
    cssUnitsEm:
      Result := Val.Val * Metrics.FontSize;
    cssUnitsPt:
      if FContainer <> nil then
        Result := FContainer.PtToPx(Val.Val)
      else
        Result := Val.Val * 96 / 72;
    cssUnitsIn:
      if FContainer <> nil then
        Result := FContainer.PtToPx(Val.Val * 72)
      else
        Result := Val.Val * 96;
    cssUnitsPc:
      if FContainer <> nil then
        Result := FContainer.PtToPx(Val.Val * 12)
      else
        Result := Val.Val * 96 / 6;
    cssUnitsCm:
      if FContainer <> nil then
        Result := FContainer.PtToPx(Val.Val * 72 / 2.54)
      else
        Result := Val.Val * 96 / 2.54;
    cssUnitsMm:
      if FContainer <> nil then
        Result := FContainer.PtToPx(Val.Val * 72 / 25.4)
      else
        Result := Val.Val * 96 / 25.4;
    cssUnitsVw, cssUnitsCqw, cssUnitsCqi:
      Result := FMedia.Width * Val.Val / 100;
    cssUnitsVh, cssUnitsCqh, cssUnitsCqb:
      Result := FMedia.Height * Val.Val / 100;
    cssUnitsVmin, cssUnitsCqmin:
    begin
      if FMedia.Width < FMedia.Height then
        Result := FMedia.Width * Val.Val / 100
      else
        Result := FMedia.Height * Val.Val / 100;
    end;
    cssUnitsVmax, cssUnitsCqmax:
    begin
      if FMedia.Width > FMedia.Height then
        Result := FMedia.Width * Val.Val / 100
      else
        Result := FMedia.Height * Val.Val / 100;
    end;
    cssUnitsRem:
    begin
      if FRoot <> nil then
        Result := FRoot.Css.FontSize * Val.Val
      else
        Result := Val.Val * 16;
    end;
    cssUnitsEx:
      Result := Metrics.XHeight * Val.Val;
    cssUnitsCh:
      Result := Metrics.ChWidth * Val.Val;
  else
    Result := Val.Val; // px or no unit
  end;
end;

procedure TPixieDocument.CvtUnits(var Val: TPixieCssLength;
  const Metrics: TPixieFontMetrics; Size: TPixiePixel);
begin
  if Val.IsPredefined then
    Exit;
  if Val.Units <> cssUnitsPercentage then
    Val.SetValue(ToPixels(Val, Metrics, Size), cssUnitsPx);
end;

// --- CSS Management ---

procedure TPixieDocument.AddStylesheet(
  const Str, BaseUrl, Media: string);
var
  Entry: TPixieCssText;
begin
  if Str <> '' then
  begin
    Entry.Text := Str;
    Entry.BaseUrl := BaseUrl;
    Entry.Media := Media;
    FCss.Add(Entry);
  end;
end;

function TPixieDocument.CreateElement(const TagName: string;
  Attrs: TPixieStringMap): TPixieElement;
var
  El: TPixieElement;
  Pair: TPair<string, string>;
  InputType: string;
begin
  El := nil;

  // Let container create custom elements first
  if FContainer <> nil then
  begin
    El := TPixieElement(FContainer.CreateElement(TagName, Attrs, Self));
    Assert((El = nil) or (El is TPixieElement));
  end;

  if El = nil then
  begin
    if TagName = 'br' then
      El := TPixieElBreak.Create(Self)
    else if TagName = 'p' then
      El := TPixieElPara.Create(Self)
    else if TagName = 'img' then
      El := TPixieElImage.Create(Self)
    else if (TagName = 'video') or (TagName = 'audio') then
      El := TPixieElVideo.Create(Self)
    else if TagName = 'table' then
      El := TPixieElTable.Create(Self)
    else if (TagName = 'td') or (TagName = 'th') then
      El := TPixieElTd.Create(Self)
    else if TagName = 'link' then
      El := TPixieElLink.Create(Self)
    else if TagName = 'title' then
      El := TPixieElTitle.Create(Self)
    else if TagName = 'a' then
      El := TPixieElAnchor.Create(Self)
    else if TagName = 'tr' then
      El := TPixieElTr.Create(Self)
    else if TagName = 'style' then
      El := TPixieElStyle.Create(Self)
    else if TagName = 'base' then
      El := TPixieElBase.Create(Self)
    else if TagName = 'body' then
      El := TPixieElBody.Create(Self)
    else if TagName = 'hr' then
      El := TPixieElHr.Create(Self)
    else if TagName = 'svg' then
      El := TPixieElSvg.Create(Self)
    else if TagName = 'div' then
      El := TPixieElDiv.Create(Self)
    else if TagName = 'script' then
      El := TPixieElScript.Create(Self)
    else if TagName = 'font' then
      El := TPixieElFont.Create(Self)
    else if TagName = 'ol' then
      El := TPixieElOl.Create(Self)
    else if TagName = 'ul' then
      El := TPixieElUl.Create(Self)
    else if TagName = 'details' then
      El := TPixieElDetails.Create(Self)
    else if TagName = 'summary' then
      El := TPixieElSummary.Create(Self)
    else if TagName = 'label' then
      El := TPixieElLabel.Create(Self)
    else if TagName = 'button' then
      El := TPixieElButton.Create(Self)
    else if TagName = 'textarea' then
      El := TPixieElTextArea.Create(Self)
    else if TagName = 'progress' then
      El := TPixieElProgress.Create(Self)
    else if TagName = 'meter' then
      El := TPixieElMeter.Create(Self)
    else if TagName = 'input' then
    begin
      if Attrs <> nil then
        Attrs.TryGetValue('type', InputType)
      else
        InputType := '';
      InputType := LowerCase(InputType);
      if InputType = 'checkbox' then
        El := TPixieElCheckbox.Create(Self)
      else if InputType = 'radio' then
        El := TPixieElRadio.Create(Self)
      else if InputType = 'range' then
        El := TPixieElRange.Create(Self)
      else if (InputType = '') or PixieValueInList(InputType,
              'text;password;search;email;url;tel;number') then
        El := TPixieElTextInput.Create(Self)
      else if (InputType = 'submit') or (InputType = 'button') or
              (InputType = 'reset') then
        El := TPixieElInputButton.Create(Self)
      else
        El := TPixieHtmlTag.Create(Self);
    end
    else
      El := TPixieHtmlTag.Create(Self);
  end;

  if El <> nil then
  begin
    El.SetTagName(TagName);
    if Attrs <> nil then
      for Pair in Attrs do
        El.SetAttr(Pair.Key, Pair.Value);
    RegisterElement(El);
  end;

  Result := El;
end;

// --- Media Queries ---

function TPixieDocument.CheckMediaChanged: Boolean;
var
  NewMedia: TPixieMediaFeatures;
begin
  Result := False;
  if FContainer = nil then
    Exit;

  FContainer.GetMediaFeatures(NewMedia);
  Result := FStyles.WouldMediaChange(FMedia, NewMedia) or
            FMasterCss.WouldMediaChange(FMedia, NewMedia) or
            FUserCss.WouldMediaChange(FMedia, NewMedia);
end;

function TPixieDocument.MatchLang(const Lang: string): Boolean;
var
  DocLang: string;
begin
  DocLang := FLang;
  if DocLang = '' then
    Exit(False);

  if SameText(Lang, DocLang) then
    Exit(True);

  // Check prefix match (e.g. "en" matches "en-US")
  if (Length(Lang) < Length(DocLang)) and
     (DocLang[Length(Lang) + 1] = '-') and
     (StrLIComp(PChar(Lang), PChar(DocLang), Length(Lang)) = 0) then
    Exit(True);

  // Check culture match
  if (FCulture <> '') and
     SameText(Lang, FCulture) then
    Exit(True);

  Result := False;
end;

// --- Render tree access ---

function TPixieDocument.RootRender: Pointer;
begin
  Result := FRootRender;
end;

procedure TPixieDocument.AddFixedBox(const Box: TPixiePosition);
begin
  FFixedBoxes.Add(Box);
end;

procedure TPixieDocument.AddTabular(Ri: TObject);
begin
  FTabularElements.Add(Ri);
end;

// --- Rendering (Phase 5 stubs) ---

procedure TPixieDocument.MarkRenderTreeDirty;
begin
  if FRebuilding or FRenderTreeDirty then
    Exit;
  FRenderTreeDirty := True;
  // Ask the host to relayout (sets NeedsLayout) and repaint. The render
  // tree itself is rebuilt lazily at the start of the next Render so the
  // current tree stays valid for the remainder of style recomputation.
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TPixieDocument.RebuildRenderItems;
var
  Ri: TPixieRenderItem;
begin
  FRootRender := FRoot.CreateRenderItem(nil);
  FixTablesLayout;
  if FRootRender <> nil then
  begin
    Ri := TPixieRenderItem(FRootRender);
    FRootRender := Ri.Init;
    if TPixieRenderItem(FRootRender) <> Ri then
      Ri.Free;
  end;
end;

procedure TPixieDocument.RebuildRenderTree;
var
  I: Integer;
  El: TPixieElement;
begin
  FRenderTreeDirty := False;
  if FRoot = nil then
    Exit;

  FRebuilding := True;
  try
    for I := 0 to FAllElements.Count - 1 do
      FAllElements[I].ClearRenders;

    if FRootRender <> nil then
    begin
      TObject(FRootRender).Free;
      FRootRender := nil;
    end;

    FFixedBoxes.Clear;
    FTabularElements.Clear;

    // Remove anonymous table wrappers from the previous render tree;
    // FixTablesLayout re-creates them. DOM nodes and ::before/::after
    // pseudo-elements are left untouched — their computed styles are
    // already current, so we must not strip them here.
    for I := FAllElements.Count - 1 downto 0 do
    begin
      El := FAllElements[I];
      if (El is TPixieHtmlTag) and (El.GetTag = -1) then
        FAllElements.Delete(I);
    end;

    RebuildRenderItems;
  finally
    FRebuilding := False;
  end;
end;

function TPixieDocument.Render(MaxWidth: TPixiePixel): TPixiePixel;
var
  Viewport: TPixiePosition;
  CbContext: TPixieContainingBlockContext;
  Ri: TPixieRenderItem;
begin
  Result := 0;
  if FRoot = nil then
    Exit;

  // A dynamic style change (e.g. :hover toggling display) may have altered
  // the render-tree structure; rebuild it before laying out.
  if FRenderTreeDirty then
    RebuildRenderTree;

  if FRootRender = nil then
    Exit;

  FContainer.GetViewport(Viewport);
  CbContext.Init;
  CbContext.Width.Value := MaxWidth;
  CbContext.Width.ValueType := cbcAbsolute;
  CbContext.Height.Value := Viewport.Height;
  CbContext.Height.ValueType := cbcAbsolute;

  Assert(TObject(FRootRender) is TPixieRenderItem);
  Ri := TPixieRenderItem(FRootRender);

  Result := Ri.Render(0, 0, CbContext, nil);
  if Ri.FetchPositioned then
  begin
    FFixedBoxes.Clear;
    Ri.RenderPositioned;
  end;
  FSize.Width := 0;
  FSize.Height := 0;
  Ri.CalcDocumentSize(FSize);
end;

procedure TPixieDocument.Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
  Clip: PPixiePosition);
var
  Ri: TPixieRenderItem;
begin
  if (FRoot <> nil) and (FRootRender <> nil) then
  begin
    Assert(TObject(FRootRender) is TPixieRenderItem);
    Ri := TPixieRenderItem(FRootRender);
    FRoot.Draw(Hdc, X, Y, Clip, Ri);
    Ri.DrawStackingContext(Hdc, X, Y, Clip, True);
  end;
end;

function TPixieDocument.OnMouseOver(X, Y, ClientX, ClientY: TPixiePixel;
  RedrawBoxes: TPixiePositionVector): Boolean;
var
  OverEl, El, Walk: TPixieElement;
  IsAncestor: Boolean;
begin
  Result := False;
  if (FRoot = nil) or (FRootRender = nil) then
    Exit;

  OverEl := TPixieRenderItem(FRootRender).GetElementByPoint(
    X, Y, ClientX, ClientY, nil);

  if OverEl <> FOverElement then
  begin
    // Remove :hover only from elements that are NOT ancestors of the new element
    if FOverElement <> nil then
    begin
      El := FOverElement;
      while El <> nil do
      begin
        IsAncestor := False;
        if OverEl <> nil then
        begin
          Walk := OverEl;
          while Walk <> nil do
          begin
            if Walk = El then
            begin
              IsAncestor := True;
              Break;
            end;
            Walk := Walk.Parent;
          end;
        end;
        if not IsAncestor then
        begin
          if El.SetPseudoClass(Ord(psid_hover), False) then
            Result := True;
          if El.SetPseudoClass(Ord(psid_active), False) then
            Result := True;
        end;
        El := El.Parent;
      end;
      FContainer.OnMouseEvent(FOverElement, meLeave);
    end;

    // Add :hover only to elements that are NOT ancestors of the old element
    if OverEl <> nil then
    begin
      El := OverEl;
      while El <> nil do
      begin
        IsAncestor := False;
        if FOverElement <> nil then
        begin
          Walk := FOverElement;
          while Walk <> nil do
          begin
            if Walk = El then
            begin
              IsAncestor := True;
              Break;
            end;
            Walk := Walk.Parent;
          end;
        end;
        if not IsAncestor then
        begin
          if El.SetPseudoClass(Ord(psid_hover), True) then
            Result := True;
        end;
        El := El.Parent;
      end;
      FContainer.OnMouseEvent(OverEl, meEnter);
    end;

    FOverElement := OverEl;
  end;

  if OverEl <> nil then
    FContainer.SetCursor(OverEl.CursorForPoint(X, Y))
  else
    FContainer.SetCursor('auto');

  if Result and (FRoot <> nil) then
    FRoot.FindStylesChanges(RedrawBoxes);
end;

function TPixieDocument.OnMouseLeave(
  RedrawBoxes: TPixiePositionVector): Boolean;
begin
  Result := False;

  if FOverElement <> nil then
  begin
    if FOverElement.OnMouseLeave then
      Result := True;
    FContainer.OnMouseEvent(FOverElement, meLeave);
    FOverElement := nil;
  end;

  if FActiveElement <> nil then
  begin
    if FActiveElement.OnLButtonUp(False) then
      Result := True;
    FActiveElement := nil;
  end;

  FContainer.SetCursor('auto');

  if Result and (FRoot <> nil) then
    FRoot.FindStylesChanges(RedrawBoxes);
end;

function TPixieDocument.OnLButtonDown(
  X, Y, ClientX, ClientY: TPixiePixel;
  RedrawBoxes: TPixiePositionVector): Boolean;
var
  OverEl: TPixieElement;
begin
  Result := False;
  if (FRoot = nil) or (FRootRender = nil) then
    Exit;

  OverEl := TPixieRenderItem(FRootRender).GetElementByPoint(
    X, Y, ClientX, ClientY, nil);

  // Store coordinates for text input click handling
  FLastMouseX := X;
  FLastMouseY := Y;

  // Blur focused element when clicking outside focusable elements
  if (OverEl = nil) or (not OverEl.IsFocusable) then
    SetFocus(nil);

  if OverEl <> nil then
  begin
    if OverEl.OnLButtonDown then
      Result := True;
  end;

  FActiveElement := OverEl;

  if Result and (FRoot <> nil) then
    FRoot.FindStylesChanges(RedrawBoxes);
end;

function TPixieDocument.OnLButtonUp(
  X, Y, ClientX, ClientY: TPixiePixel;
  RedrawBoxes: TPixiePositionVector): Boolean;
var
  OverEl, Walker: TPixieElement;
  IsClick: Boolean;
begin
  Result := False;
  if (FRoot = nil) or (FRootRender = nil) then
    Exit;

  OverEl := TPixieRenderItem(FRootRender).GetElementByPoint(
    X, Y, ClientX, ClientY, nil);

  // Click is valid if mouse-up is on the same element as mouse-down,
  // or on an ancestor/descendant (handles text nodes inside anchors
  // and style recomputations that shift element boundaries)
  IsClick := (OverEl <> nil) and (OverEl = FActiveElement);
  if (not IsClick) and (OverEl <> nil) and (FActiveElement <> nil) then
  begin
    // Check if OverEl is an ancestor of FActiveElement
    Walker := FActiveElement.Parent;
    while Walker <> nil do
    begin
      if Walker = OverEl then
      begin
        IsClick := True;
        Break;
      end;
      Walker := Walker.Parent;
    end;
    // Check if FActiveElement is an ancestor of OverEl
    if not IsClick then
    begin
      Walker := OverEl.Parent;
      while Walker <> nil do
      begin
        if Walker = FActiveElement then
        begin
          IsClick := True;
          Break;
        end;
        Walker := Walker.Parent;
      end;
    end;
  end;

  if OverEl <> nil then
  begin
    if OverEl.OnLButtonUp(IsClick) then
      Result := True;
  end;

  if (FActiveElement <> nil) and (FActiveElement <> OverEl) then
  begin
    if FActiveElement.OnLButtonUp(False) then
      Result := True;
  end;

  FActiveElement := nil;

  if Result and (FRoot <> nil) then
    FRoot.FindStylesChanges(RedrawBoxes);
end;

procedure FixTableChildren(Doc: TPixieDocument; ElPtr: TPixieRenderItem;
  Disp: TPixieDisplay; const DispStr: string); forward;
procedure FixTableParent(Doc: TPixieDocument; ElPtr: TPixieRenderItem;
  Disp: TPixieDisplay; const DispStr: string); forward;

procedure FixTableChildren(Doc: TPixieDocument; ElPtr: TPixieRenderItem;
  Disp: TPixieDisplay; const DispStr: string);
var
  Tmp: TPixieRenderItemVector;
  FirstIdx, CurIdx: Integer;
  AnonTag: TPixieHtmlTag;
  AnonRi: TPixieRenderItem;
  Child: TPixieRenderItem;

  procedure FlushElements;
  var
    K: Integer;
  begin
    AnonTag := TPixieHtmlTag.CreateAnonymous(ElPtr.SrcEl,
      'display:' + DispStr);
    Doc.RegisterElement(AnonTag);

    if AnonTag.Css.Display = displayTableCell then
    begin
      AnonTag.SetTagName('table_cell');
      AnonRi := TPixieRenderBlock.Create(AnonTag);
    end
    else if AnonTag.Css.Display = displayTableRow then
      AnonRi := TPixieRenderTableRow.Create(AnonTag)
    else
      AnonRi := TPixieRenderTablePart.Create(AnonTag);

    for K := 0 to Tmp.Count - 1 do
      AnonRi.AddChild(Tmp[K]);
    Doc.AddTabular(AnonRi);
    AnonRi.SetParent(ElPtr);

    // Remove wrapped children from parent, then insert the anonymous wrapper
    ElPtr.FChildren.OwnsObjects := False;
    for K := 0 to Tmp.Count - 1 do
      ElPtr.FChildren.Remove(Tmp[K]);
    if FirstIdx > ElPtr.FChildren.Count then
      FirstIdx := ElPtr.FChildren.Count;
    ElPtr.FChildren.Insert(FirstIdx, AnonRi);
    ElPtr.FChildren.OwnsObjects := True;
    CurIdx := FirstIdx + 1;
    FirstIdx := CurIdx;
    Tmp.Clear;
  end;

begin
  Tmp := TPixieRenderItemVector.Create;
  try
    FirstIdx := 0;
    CurIdx := 0;
    while CurIdx < ElPtr.FChildren.Count do
    begin
      Child := ElPtr.FChildren[CurIdx];
      if (Child.SrcEl.Css.Display <> Disp) and
         not ((Disp = displayTableRowGroup) and
              (Child.SrcEl.Css.Display in
                [displayTableHeaderGroup, displayTableFooterGroup])) then
      begin
        if (not Child.SrcEl.IsTableSkip) or
           (Child.SrcEl.IsTableSkip and (Tmp.Count > 0)) then
        begin
          if (Disp <> displayTableRowGroup) or
             (Child.SrcEl.Css.Display <> displayTableCaption) then
          begin
            if Tmp.Count = 0 then
              FirstIdx := CurIdx;
            Tmp.Add(Child);
          end;
        end;
        Inc(CurIdx);
      end
      else if Tmp.Count > 0 then
        FlushElements
      else
        Inc(CurIdx);
    end;
    if Tmp.Count > 0 then
      FlushElements;
  finally
    Tmp.Free;
  end;
end;

procedure FixTableParent(Doc: TPixieDocument; ElPtr: TPixieRenderItem;
  Disp: TPixieDisplay; const DispStr: string);
var
  ParentRi: TPixieRenderItem;
  ThisIdx, FirstIdx, LastIdx, CurIdx: Integer;
  ElDisp: TPixieDisplay;
  AnonTag: TPixieHtmlTag;
  AnonRi: TPixieRenderItem;
  I: Integer;
begin
  ParentRi := ElPtr.GetParent;
  if ParentRi = nil then Exit;
  if ParentRi.SrcEl.Css.Display = Disp then Exit;
  if (Disp = displayTableRowGroup) and
     (ParentRi.SrcEl.Css.Display in
       [displayTableHeaderGroup, displayTableFooterGroup]) then Exit;

  // Find this element in parent's children
  ThisIdx := ParentRi.FChildren.IndexOf(ElPtr);
  if ThisIdx < 0 then Exit;

  ElDisp := ElPtr.SrcEl.Css.Display;
  FirstIdx := ThisIdx;
  LastIdx := ThisIdx;

  // Find first element with same display
  CurIdx := ThisIdx - 1;
  while CurIdx >= 0 do
  begin
    if ParentRi.FChildren[CurIdx].SrcEl.IsTableSkip or
       (ParentRi.FChildren[CurIdx].SrcEl.Css.Display = ElDisp) then
      FirstIdx := CurIdx
    else
      Break;
    Dec(CurIdx);
  end;

  // Find last element with same display
  CurIdx := ThisIdx + 1;
  while CurIdx < ParentRi.FChildren.Count do
  begin
    if ParentRi.FChildren[CurIdx].SrcEl.IsTableSkip or
       (ParentRi.FChildren[CurIdx].SrcEl.Css.Display = ElDisp) then
      LastIdx := CurIdx
    else
      Break;
    Inc(CurIdx);
  end;

  // Create anonymous wrapper
  AnonTag := TPixieHtmlTag.CreateAnonymous(ParentRi.SrcEl,
    'display:' + DispStr);
  Doc.RegisterElement(AnonTag);

  if AnonTag.Css.Display in [displayTable, displayInlineTable] then
    AnonRi := TPixieRenderTable.Create(AnonTag)
  else if AnonTag.Css.Display = displayTableRow then
    AnonRi := TPixieRenderTableRow.Create(AnonTag)
  else
    AnonRi := TPixieRenderTablePart.Create(AnonTag);

  // Move children to anon item
  for I := FirstIdx to LastIdx do
    AnonRi.AddChild(ParentRi.FChildren[I]);

  // Replace range in parent with the anon wrapper
  ParentRi.FChildren.OwnsObjects := False;
  for I := LastIdx downto FirstIdx do
    ParentRi.FChildren.Delete(I);
  ParentRi.FChildren.Insert(FirstIdx, AnonRi);
  ParentRi.FChildren.OwnsObjects := True;

  Doc.AddTabular(AnonRi);
  AnonRi.SetParent(ParentRi);
end;

procedure TPixieDocument.FixTablesLayout;
var
  I, PrevCount: Integer;
  ElPtr: TPixieRenderItem;
  ParentRi: TPixieRenderItem;
begin
  // Process top-down by table hierarchy level so that anonymous wrappers
  // created by parent elements exist before children try to fix their own
  // parents. Repeat until no new anonymous objects are generated (handles
  // orphan cells that need a full table/row-group/row chain built bottom-up).
  repeat
    PrevCount := FTabularElements.Count;

    for I := 0 to FTabularElements.Count - 1 do
    begin
      Assert(TObject(FTabularElements[I]) is TPixieRenderItem);
      ElPtr := TPixieRenderItem(FTabularElements[I]);
      if ElPtr.SrcEl.Css.Display in [displayInlineTable, displayTable] then
        FixTableChildren(Self, ElPtr, displayTableRowGroup,
          'table-row-group');
    end;

    // Pass 2: Row-groups -> ensure parent is table, wrap non-row children
    for I := 0 to FTabularElements.Count - 1 do
    begin
      ElPtr := TPixieRenderItem(FTabularElements[I]);
      if ElPtr.SrcEl.Css.Display in [displayTableFooterGroup,
        displayTableRowGroup, displayTableHeaderGroup] then
      begin
        ParentRi := ElPtr.GetParent;
        if ParentRi <> nil then
        begin
          if ParentRi.SrcEl.Css.Display <> displayInlineTable then
            FixTableParent(Self, ElPtr, displayTable, 'table');
        end;
        FixTableChildren(Self, ElPtr, displayTableRow, 'table-row');
      end;
    end;

    // Pass 3: Rows -> ensure parent is row-group, wrap non-cell children
    for I := 0 to FTabularElements.Count - 1 do
    begin
      ElPtr := TPixieRenderItem(FTabularElements[I]);
      if ElPtr.SrcEl.Css.Display = displayTableRow then
      begin
        FixTableParent(Self, ElPtr, displayTableRowGroup,
          'table-row-group');
        FixTableChildren(Self, ElPtr, displayTableCell, 'table-cell');
      end;
    end;

    // Pass 4: Cells -> ensure parent is row
    for I := 0 to FTabularElements.Count - 1 do
    begin
      ElPtr := TPixieRenderItem(FTabularElements[I]);
      if ElPtr.SrcEl.Css.Display = displayTableCell then
        FixTableParent(Self, ElPtr, displayTableRow, 'table-row');
    end;
  until FTabularElements.Count = PrevCount;
end;

// --- Element registration ---

procedure TPixieDocument.RegisterElement(El: TPixieElement);
begin
  FAllElements.Add(El);
end;

procedure TPixieDocument.UnregisterElement(El: TPixieElement);
var
  I, Idx: Integer;
begin
  // Recursively unregister children first
  for I := El.Children.Count - 1 downto 0 do
    UnregisterElement(El.Children[I]);

  // Clear document-level references
  if FOverElement = El then FOverElement := nil;
  if FActiveElement = El then FActiveElement := nil;
  if FFocusedElement = El then FFocusedElement := nil;
  if FSelAnchor = El then FSelAnchor := nil;
  if FSelFocus = El then FSelFocus := nil;
  if FWordSelAnchor = El then FWordSelAnchor := nil;

  // Remove from FAllElements and free
  Idx := FAllElements.IndexOf(El);
  if Idx >= 0 then
    FAllElements.Delete(Idx);
end;

// --- Focus management ---

procedure TPixieDocument.SetFocus(El: TPixieElement);
begin
  if El = FFocusedElement then
    Exit;

  if FFocusedElement <> nil then
  begin
    FFocusedElement.SetPseudoClass(Ord(psid_focus), False);
    FFocusedElement.OnBlur;
    FFocusedElement.FindStylesChanges(nil);
  end;

  FFocusedElement := El;

  if FFocusedElement <> nil then
  begin
    FFocusedElement.SetPseudoClass(Ord(psid_focus), True);
    FFocusedElement.OnFocus;
    FFocusedElement.FindStylesChanges(nil);
  end;
end;

function TPixieDocument.FocusedElement: TPixieElement;
begin
  Result := FFocusedElement;
end;

function TPixieDocument.GetFocusedCaretPos(out X, Y, H: TPixiePixel): Boolean;
begin
  if FFocusedElement is TPixieElTextBase then
    Result := TPixieElTextBase(FFocusedElement).GetCaretDocPos(X, Y, H)
  else
    Result := False;
end;

function TPixieDocument.DispatchKeyDown(Key: Word;
  Shift: TShiftState): Boolean;
begin
  if FFocusedElement <> nil then
    Result := FFocusedElement.OnKeyDown(Key, Shift)
  else
    Result := False;
end;

function TPixieDocument.DispatchUTF8KeyPress(
  const UTF8Char: string): Boolean;
begin
  if FFocusedElement <> nil then
    Result := FFocusedElement.OnUTF8KeyPress(UTF8Char)
  else
    Result := False;
end;

function TPixieDocument.FocusNext: Boolean;
var
  I, Start: Integer;
begin
  Result := False;
  if FAllElements.Count = 0 then Exit;

  if FFocusedElement <> nil then
    Start := FAllElements.IndexOf(FFocusedElement) + 1
  else
    Start := 0;

  for I := Start to FAllElements.Count - 1 do
    if FAllElements[I].IsFocusable then
    begin
      SetFocus(FAllElements[I]);
      Exit(True);
    end;
  // Wrap around
  for I := 0 to Start - 1 do
    if FAllElements[I].IsFocusable then
    begin
      SetFocus(FAllElements[I]);
      Exit(True);
    end;
end;

function TPixieDocument.FocusPrev: Boolean;
var
  I, Start: Integer;
begin
  Result := False;
  if FAllElements.Count = 0 then Exit;

  if FFocusedElement <> nil then
    Start := FAllElements.IndexOf(FFocusedElement) - 1
  else
    Start := FAllElements.Count - 1;

  for I := Start downto 0 do
    if FAllElements[I].IsFocusable then
    begin
      SetFocus(FAllElements[I]);
      Exit(True);
    end;
  // Wrap around
  for I := FAllElements.Count - 1 downto Start + 1 do
    if FAllElements[I].IsFocusable then
    begin
      SetFocus(FAllElements[I]);
      Exit(True);
    end;
end;

function TPixieDocument.DispatchDblClick: Boolean;
begin
  if FFocusedElement <> nil then
    Result := FFocusedElement.OnLButtonDblClick
  else
    Result := False;
end;

function TPixieDocument.DispatchMouseDrag(
  X, Y: TPixiePixel): Boolean;
begin
  if FFocusedElement <> nil then
    Result := FFocusedElement.OnMouseDrag(X, Y)
  else
    Result := False;
end;

function TPixieDocument.DispatchMouseWheel(
  X, Y: TPixiePixel; Delta: Integer): Boolean;
var
  El: TPixieElement;
  Ri: TPixieRenderItem;
  Dy: TPixiePixel;
begin
  Result := False;
  if (FRoot = nil) or (FRootRender = nil) then
    Exit;
  El := TPixieRenderItem(FRootRender).GetElementByPoint(
    X, Y, X, Y, nil);
  if El = nil then
    Exit;

  // Element-level handler first (e.g. textarea owns its own scrolling)
  if El.OnMouseWheel(Delta) then
    Exit(True);

  // Otherwise scroll the nearest overflow ancestor that can still move.
  // Wheel up (Delta > 0) moves content toward the top, i.e. decreases the
  // scroll offset. Stops at the limit so the page can take over (chaining).
  Dy := -(Delta / 120) * 40;
  Ri := TPixieRenderItem(El.GetRenderItem);
  while Ri <> nil do
  begin
    if Ri.IsVScrollable(Dy) then
    begin
      Ri.VScroll(Dy);
      Exit(True);
    end;
    // Horizontal-only container (no vertical overflow): the plain wheel
    // scrolls it sideways, as browsers do.
    if (not Ri.IsVScrollable(-Dy)) and Ri.IsHScrollable(Dy) then
    begin
      Ri.HScroll(Dy);
      Exit(True);
    end;
    Ri := Ri.GetParent;
  end;
end;

// --- Text selection ---

function TPixieDocument.RenderAbsoluteX(Ri: Pointer): TPixiePixel;
var
  P: TPixieRenderItem;
begin
  Result := 0;
  P := TPixieRenderItem(Ri);
  while P <> nil do
  begin
    Result := Result + P.FPos.X - P.GetScrollLeft;
    P := P.FParent;
  end;
end;

function TPixieDocument.ComputeTextOffset(
  El: TPixieElement; X: TPixiePixel): Integer;
var
  Ri: TPixieRenderItem;
  LocalX: TPixiePixel;
  HFont: PtrUInt;
begin
  Result := 0;
  Ri := TPixieRenderItem(El.GetRenderItem);
  if (Ri <> nil) and (El.Parent <> nil) then
  begin
    HFont := El.Parent.Css.Font;
    if HFont <> 0 then
    begin
      LocalX := X - RenderAbsoluteX(Ri);
      Result := FContainer.TextOffsetAtX(
        El.GetDisplayText, HFont, LocalX);
    end;
  end;
end;

procedure TPixieDocument.SelectionStart(
  X, Y, ClientX, ClientY: TPixiePixel);
var
  El: TPixieElement;
begin
  if (FRoot = nil) or (FRootRender = nil) then
    Exit;

  El := TPixieRenderItem(FRootRender).GetTextByPoint(X, Y);
  if El = nil then
    El := TPixieRenderItem(FRootRender).GetNearestTextByPoint(X, Y);

  FSelAnchor := El;
  FSelFocus := nil;
  FSelAnchorOffset := 0;
  FSelFocusOffset := 0;
  FSelMap.Clear;
  FSelecting := True;

  if El <> nil then
    FSelAnchorOffset := ComputeTextOffset(El, X);
end;

function TPixieDocument.SelectionMove(
  X, Y, ClientX, ClientY: TPixiePixel): Boolean;
var
  El: TPixieElement;
  NewOffset: Integer;
begin
  Result := False;
  if (not FSelecting) or (FSelAnchor = nil) then
    Exit;
  if (FRoot = nil) or (FRootRender = nil) then
    Exit;

  El := TPixieRenderItem(FRootRender).GetTextByPoint(X, Y);
  if El = nil then
    El := TPixieRenderItem(FRootRender).GetNearestTextByPoint(X, Y);

  if El <> nil then
  begin
    NewOffset := ComputeTextOffset(El, X);

    if (El <> FSelFocus) or (NewOffset <> FSelFocusOffset) then
    begin
      FSelFocus := El;
      FSelFocusOffset := NewOffset;
      BuildSelectedElements;
      Result := True;
    end;
  end;
end;

function TPixieDocument.SelectionMoveWord(
  X, Y, ClientX, ClientY: TPixiePixel): Boolean;
var
  El: TPixieElement;
  AnchorIdx, ElIdx: Integer;
begin
  Result := False;
  if (not FSelecting) or (FWordSelAnchor = nil) then
    Exit;
  if (FRoot = nil) or (FRootRender = nil) then
    Exit;

  El := TPixieRenderItem(FRootRender).GetTextByPoint(X, Y);
  if El = nil then
    El := TPixieRenderItem(FRootRender).GetNearestTextByPoint(X, Y);
  if El = nil then
    Exit;

  AnchorIdx := FAllElements.IndexOf(FWordSelAnchor);
  ElIdx := FAllElements.IndexOf(El);
  if (AnchorIdx < 0) or (ElIdx < 0) then
    Exit;

  if ElIdx < AnchorIdx then
  begin
    FSelAnchor := El;
    FSelFocus := FWordSelAnchor;
  end
  else if ElIdx > AnchorIdx then
  begin
    FSelAnchor := FWordSelAnchor;
    FSelFocus := El;
  end
  else
  begin
    FSelAnchor := FWordSelAnchor;
    FSelFocus := FWordSelAnchor;
  end;

  FSelAnchorOffset := 0;
  FSelFocusOffset := Length(FSelFocus.GetDisplayText);

  BuildSelectedElements;
  Result := True;
end;

function TPixieDocument.SelectWord(X, Y: TPixiePixel): Boolean;
var
  El: TPixieElement;
begin
  Result := False;
  if (FRoot = nil) or (FRootRender = nil) then
    Exit;

  El := TPixieRenderItem(FRootRender).GetTextByPoint(X, Y);
  if (El <> nil) and (not El.IsSpace) then
  begin
    ClearSelection;
    FSelAnchor := El;
    FSelFocus := El;
    FSelAnchorOffset := 0;
    FSelFocusOffset := Length(El.GetDisplayText);
    FWordSelAnchor := El;
    FSelecting := True;
    FSelMap.AddOrSetValue(Pointer(El), True);
    Result := True;
  end;
end;

procedure TPixieDocument.SelectionEnd;
begin
  FSelecting := False;
end;

procedure TPixieDocument.SelectAll;
var
  I: Integer;
  First, Last: TPixieElement;
begin
  First := nil;
  Last := nil;
  for I := 0 to FAllElements.Count - 1 do
    if FAllElements[I].IsText then
    begin
      if First = nil then
        First := FAllElements[I];
      Last := FAllElements[I];
    end;
  if (First <> nil) and (First <> Last) then
  begin
    FSelAnchor := First;
    FSelFocus := Last;
    FSelAnchorOffset := 0;
    FSelFocusOffset := Length(Last.GetDisplayText);
    BuildSelectedElements;
  end;
end;

procedure TPixieDocument.ClearSelection;
begin
  FSelMap.Clear;
  FSelAnchor := nil;
  FSelFocus := nil;
  FSelAnchorOffset := 0;
  FSelFocusOffset := 0;
  FSelAnchorIdx := -1;
  FSelFocusIdx := -1;
  FSelecting := False;
  FWordSelAnchor := nil;
end;

function TPixieDocument.HasSelection: Boolean;
begin
  Result := FSelMap.Count > 0;
end;

function TPixieDocument.HasRangeSelection: Boolean;
begin
  Result := (FSelMap.Count > 0) and
    ((FSelAnchor <> FSelFocus) or (FSelAnchorOffset <> FSelFocusOffset));
end;

function TPixieDocument.IsSelected(El: TPixieElement): Boolean;
begin
  Result := FSelMap.ContainsKey(Pointer(El));
end;

function TPixieDocument.IsSelectedPartial(El: TPixieElement;
  out StartOff, EndOff: Integer): Boolean;
var
  TxtLen: Integer;
  IsFirst, IsLast: Boolean;
begin
  Result := False;
  StartOff := 0;
  EndOff := 0;
  if not FSelMap.ContainsKey(Pointer(El)) then
    Exit;
  if (FSelAnchor = nil) or (FSelFocus = nil) then
    Exit;

  if FSelAnchor = FSelFocus then
  begin
    // Same node — partial within it
    if El = FSelAnchor then
    begin
      StartOff := FSelAnchorOffset;
      EndOff := FSelFocusOffset;
      if StartOff > EndOff then
      begin
        StartOff := FSelFocusOffset;
        EndOff := FSelAnchorOffset;
      end;
      Result := StartOff <> EndOff;
    end
    else
    begin
      TxtLen := Length(El.GetDisplayText);
      StartOff := 0;
      EndOff := TxtLen;
      Result := TxtLen > 0;
    end;
    Exit;
  end;

  // Use pointer comparison + cached indices to determine role.
  // FSelMap contains exactly elements in [Lo..Hi], so any element
  // that is neither anchor nor focus is an interior node.
  if FSelAnchorIdx <= FSelFocusIdx then
  begin
    IsFirst := (El = FSelAnchor);
    IsLast := (El = FSelFocus);
  end
  else
  begin
    IsFirst := (El = FSelFocus);
    IsLast := (El = FSelAnchor);
  end;

  if IsFirst and IsLast then
  begin
    // Anchor and focus are the same but we already handled that above,
    // so this means El matched both — treat as full selection
    StartOff := 0;
    EndOff := Length(El.GetDisplayText);
  end
  else if IsFirst then
  begin
    if FSelAnchorIdx <= FSelFocusIdx then
      StartOff := FSelAnchorOffset
    else
      StartOff := FSelFocusOffset;
    EndOff := Length(El.GetDisplayText);
  end
  else if IsLast then
  begin
    StartOff := 0;
    if FSelAnchorIdx <= FSelFocusIdx then
      EndOff := FSelFocusOffset
    else
      EndOff := FSelAnchorOffset;
  end
  else
  begin
    // Interior node — fully selected
    StartOff := 0;
    EndOff := Length(El.GetDisplayText);
  end;

  Result := StartOff < EndOff;
end;

procedure TPixieDocument.BuildSelectedElements;
var
  IdxA, IdxF, Lo, Hi, I: Integer;
  El: TPixieElement;
begin
  FSelMap.Clear;
  if (FSelAnchor = nil) or (FSelFocus = nil) then
    Exit;

  IdxA := FAllElements.IndexOf(FSelAnchor);
  IdxF := FAllElements.IndexOf(FSelFocus);
  if (IdxA < 0) or (IdxF < 0) then
    Exit;

  // Cache indices for O(1) lookups in IsSelectedPartial
  FSelAnchorIdx := IdxA;
  FSelFocusIdx := IdxF;

  if IdxA <= IdxF then
  begin
    Lo := IdxA;
    Hi := IdxF;
  end
  else
  begin
    Lo := IdxF;
    Hi := IdxA;
  end;

  for I := Lo to Hi do
  begin
    El := FAllElements[I];
    // 'user-select: none' (inherited, resolved onto each text node) opts a run
    // out of selection. Enforcing it here — the single point feeding both the
    // highlight paint and clipboard copy — covers drag-through, Select All and
    // table cells alike, regardless of which hit-test endpoint was used.
    if El.IsText and (El.Parent <> nil) and
       (El.Parent.Css.Display <> displayNone) and
       (El.Css.UserSelect <> usNone) then
      FSelMap.AddOrSetValue(Pointer(El), True);
  end;
end;

function TPixieDocument.GetSelectedText: string;

  function FindBlockAncestor(El: TPixieElement): TPixieElement;
  begin
    Result := El.Parent;
    while (Result <> nil) and not Result.IsBlockBox do
      Result := Result.Parent;
  end;

var
  I, StartOff, EndOff: Integer;
  El, LastBlock, CurBlock: TPixieElement;
  Txt: string;
begin
  Result := '';
  LastBlock := nil;
  for I := 0 to FAllElements.Count - 1 do
  begin
    El := FAllElements[I];
    if El.IsText and IsSelectedPartial(El, StartOff, EndOff) then
    begin
      CurBlock := FindBlockAncestor(El);
      if (LastBlock <> nil) and (CurBlock <> LastBlock) and (Result <> '') and
         (Result[Length(Result)] <> #10) then
        Result := Result + #10;
      LastBlock := CurBlock;
      Txt := El.GetDisplayText;
      if (StartOff = 0) and (EndOff >= Length(Txt)) then
        El.GetText(Result)
      else
        Result := Result + Copy(Txt, StartOff + 1, EndOff - StartOff);
    end;
  end;
end;

// --- DOM Mutation API ---

function TPixieDocument.CreateTextNode(
  const AText: string): TPixieElement;
var
  El: TPixieElement;
begin
  El := TPixieElText.Create(AText, Self);
  RegisterElement(El);
  Result := El;
end;

function TPixieDocument.GetElementById(
  const Id: string): TPixieElement;
var
  I, IdNum: Integer;
  El: TPixieElement;
begin
  IdNum := PixieId(Id);
  for I := 0 to FAllElements.Count - 1 do
  begin
    El := FAllElements[I];
    if El.GetId = IdNum then
      Exit(El);
  end;
  Result := nil;
end;

function TPixieDocument.FindAnchorTarget(
  const Name: string): TPixieElement;
var
  I: Integer;
  El: TPixieElement;
begin
  // First try id attribute (HTML5 standard)
  Result := GetElementById(Name);
  if Result <> nil then
    Exit;
  // Fall back to <a name="..."> (legacy HTML)
  for I := 0 to FAllElements.Count - 1 do
  begin
    El := FAllElements[I];
    if El.GetAttr('name') = Name then
      Exit(El);
  end;
  Result := nil;
end;

function TPixieDocument.QuerySelector(
  const Selector: string): TPixieElement;
var
  Tokens: TPixieCssTokenList;
  Selectors: TPixieCssSelectorList;
  I, J: Integer;
  El: TPixieElement;
begin
  Result := nil;
  if (FRoot = nil) or (Selector = '') then
    Exit;

  Tokens := PixieCssNormalizeStr(Selector, cssCssNormComponentize);
  try
    Selectors := PixieParseSelectorList(Tokens,
      PixieSelectorStrict, FMode);
    if Selectors = nil then
      Exit;
    try
      for I := 0 to FAllElements.Count - 1 do
      begin
        El := FAllElements[I];
        for J := 0 to Selectors.Count - 1 do
          if El.SelectSel(Selectors[J], False) <> SelectNoMatch then
            Exit(El);
      end;
    finally
      Selectors.Free;
    end;
  finally
    Tokens.Free;
  end;
end;

function TPixieDocument.QuerySelectorAll(
  const Selector: string): TPixieElementList;
var
  Tokens: TPixieCssTokenList;
  Selectors: TPixieCssSelectorList;
  I, J: Integer;
  El: TPixieElement;
begin
  Result := TPixieElementList.Create(False);
  if (FRoot = nil) or (Selector = '') then
    Exit;

  Tokens := PixieCssNormalizeStr(Selector, cssCssNormComponentize);
  try
    Selectors := PixieParseSelectorList(Tokens,
      PixieSelectorStrict, FMode);
    if Selectors = nil then
      Exit;
    try
      for I := 0 to FAllElements.Count - 1 do
      begin
        El := FAllElements[I];
        for J := 0 to Selectors.Count - 1 do
          if El.SelectSel(Selectors[J], False) <> SelectNoMatch then
          begin
            Result.Add(El);
            Break;
          end;
      end;
    finally
      Selectors.Free;
    end;
  finally
    Tokens.Free;
  end;
end;

procedure TPixieDocument.SetInnerHtml(Parent: TPixieElement;
  const Html: string);
var
  ParsedFragment: TPixieHtmlNode;
  ChildList: TPixieElementList;
  I: Integer;
  ContextTag: string;
begin
  if Parent = nil then
    Exit;

  // Clear existing children
  Parent.ClearRecursive;

  if Html = '' then
    Exit;

  // Determine context tag for fragment parsing
  ContextTag := Parent.GetTagName;
  if ContextTag = '' then
    ContextTag := 'div';

  // Parse HTML fragment
  ParsedFragment := PixieParseFragment(Html, ContextTag);
  try
    ChildList := TPixieElementList.Create(False);
    try
      // The fragment result is a document node wrapping html>head+body.
      // Pass ProcessRoot=False to skip the <html> wrapper and collect
      // only its content children.
      for I := 0 to ParsedFragment.Children.Count - 1 do
        CreateNode(Self, ParsedFragment.Children[I], ChildList,
          True, False);

      for I := 0 to ChildList.Count - 1 do
        Parent.AppendChild(ChildList[I]);
    finally
      ChildList.Free;
    end;
  finally
    ParsedFragment.Free;
  end;
  Changed;
end;

procedure TPixieDocument.RemoveElement(El: TPixieElement);
begin
  if El = nil then Exit;
  if El.Parent <> nil then
    El.Parent.RemoveChild(El);
  UnregisterElement(El);
  Changed;
end;

procedure TPixieDocument.SetElementText(El: TPixieElement;
  const AText: string);
begin
  if El = nil then Exit;
  El.SetTextContent(AText);
  Changed;
end;

procedure TPixieDocument.BeginUpdate;
begin
  Inc(FUpdateCount);
end;

procedure TPixieDocument.EndUpdate;
begin
  Dec(FUpdateCount);
  if (FUpdateCount = 0) and FUpdateDirty then
  begin
    FUpdateDirty := False;
    Rebuild;
  end;
end;

procedure TPixieDocument.Changed;
begin
  if FRebuilding then Exit;
  if FUpdateCount = 0 then
    Rebuild
  else
    FUpdateDirty := True;
end;

procedure TPixieDocument.Rebuild;
var
  I, J: Integer;
  El: TPixieElement;
  CssEntry: TPixieCssText;
  MqList: TPixieMediaQueryList;
  MqLL: TPixieMediaQueryListList;
begin
  if FRoot = nil then
    Exit;

  FRebuilding := True;
  try

  // 1. Clear FRenders on all elements (prevent dangling pointers)
  for I := 0 to FAllElements.Count - 1 do
    FAllElements[I].ClearRenders;

  // 2. Free old render tree
  if FRootRender <> nil then
  begin
    TObject(FRootRender).Free;
    FRootRender := nil;
  end;

  // 3. Clear state
  FFixedBoxes.Clear;
  FTabularElements.Clear;
  FOverElement := nil;
  FActiveElement := nil;
  FFocusedElement := nil;
  FSelAnchor := nil;
  FSelFocus := nil;
  FSelAnchorOffset := 0;
  FSelFocusOffset := 0;
  FSelAnchorIdx := -1;
  FSelFocusIdx := -1;
  FSelecting := False;
  FWordSelAnchor := nil;
  FSelMap.Clear;

  // 4. Remove and free ::before/::after pseudo-elements and anonymous wrappers
  for I := FAllElements.Count - 1 downto 0 do
  begin
    El := FAllElements[I];
    if (El.GetTag = Ord(psid__tag_before)) or
       (El.GetTag = Ord(psid__tag_after)) then
    begin
      if El.Parent <> nil then
        El.Parent.RemoveChild(El);
      UnregisterElement(El);
    end
    else if (El is TPixieHtmlTag) and (El.GetTag = -1) then
    begin
      // Anonymous wrapper element from previous render tree — remove
      FAllElements.Delete(I);
    end;
  end;

  // 5. Clear used styles, reset accumulated styles and counters
  //    Also clear pseudo-element children (not in FAllElements)
  for I := 0 to FAllElements.Count - 1 do
  begin
    El := FAllElements[I];
    El.ClearUsedStyles;
    El.ResetStyle;
    El.ClearCounterValues;
    for J := 0 to El.Children.Count - 1 do
      if (El.Children[J].GetTag = Ord(psid__tag_before)) or
         (El.Children[J].GetTag = Ord(psid__tag_after)) then
      begin
        El.Children[J].ClearUsedStyles;
        El.Children[J].ResetStyle;
      end;
  end;

  // 6. Re-create FStyles and re-collect from <style>/<link>
  FStyles.Free;
  FStyles := TPixieStylesheet.Create;
  FCss.Clear;

  // 7. Re-apply master CSS
  FRoot.SetPseudoClass(Ord(psid_root), True);
  FRoot.ApplyStylesheet(FMasterCss);

  // 8. Re-parse element attributes (collects stylesheets)
  FRoot.ParseAttributes;

  // 9. Parse collected stylesheets
  for I := 0 to FCss.Count - 1 do
  begin
    CssEntry := FCss[I];
    MqLL := nil;
    if CssEntry.Media <> '' then
    begin
      MqList := TPixieMediaQueryList.ParseFromString(
        CssEntry.Media);
      if MqList <> nil then
      begin
        MqLL := TPixieMediaQueryListList.Create;
        MqLL.Add(MqList);
      end;
    end;
    FStyles.ParseCssStylesheet(CssEntry.Text,
      CssEntry.BaseUrl, FMode, MqLL);
  end;
  FStyles.SortSelectors;

  // 10. Apply media features
  if FContainer <> nil then
    FContainer.GetMediaFeatures(FMedia);
  FMasterCss.ApplyMediaFeatures(FMedia);
  FStyles.ApplyMediaFeatures(FMedia);
  FUserCss.ApplyMediaFeatures(FMedia);

  // 11. Apply document styles
  FRoot.ApplyStylesheet(FStyles);

  // 12. Apply user CSS
  FRoot.ApplyStylesheet(FUserCss);

  // 13. Compute styles
  FRoot.ComputeStyles;

  // 14-16. Create render tree, fix tables, init block contexts
  RebuildRenderItems;

  // 17. Notify view
  if Assigned(FOnChange) then
    FOnChange(Self);

  finally
    FRebuilding := False;
  end;
end;

end.
