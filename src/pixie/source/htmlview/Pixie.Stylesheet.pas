unit Pixie.Stylesheet;

// CSS stylesheet container: parses CSS text into a sorted list of selectors
// with attached styles and media queries.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Generics.Collections,
  Pixie.Types, Pixie.StringId, Pixie.Utils,
  Pixie.CssTokenizer, Pixie.CssParser,
  Pixie.CssSelector, Pixie.Style, Pixie.MediaQuery,
  Pixie.FontFace;

type
  TPixieSelectorIndexMap = TDictionary<Integer, TPixieCssSelectorList>;

  { TPixieStylesheet }

  TPixieStylesheet = class
  private
    FSelectors: TPixieCssSelectorList;
    FStyles: TPixieStyleList;
    FMediaQueries: TPixieMediaQueryListListObjList;
    FMqLists: TPixieMediaQueryListObjList;
    FOrder: Integer;

    // Selector hash indices (non-owning lists, selectors owned by FSelectors)
    FTagIndex: TPixieSelectorIndexMap;
    FClassIndex: TPixieSelectorIndexMap;
    FIdIndex: TPixieSelectorIndexMap;
    FUniversalList: TPixieCssSelectorList;
    FIsIndexed: Boolean;

    procedure AddSelector(Sel: TPixieCssSelector);
    function ParseStyleRule(Rule: TPixieCssRawRule;
      const BaseUrl: string; Mode: TPixieDocumentMode;
      Media: TPixieMediaQueryListList): Boolean;
    procedure ParseMediaRule(Rule: TPixieCssRawRule;
      const BaseUrl: string; Mode: TPixieDocumentMode;
      Media: TPixieMediaQueryListList);
    procedure ClearIndex;
    procedure AddToIndexMap(Map: TPixieSelectorIndexMap;
      Key: Integer; Sel: TPixieCssSelector);
  public
    constructor Create;
    destructor Destroy; override;

    procedure ParseCssStylesheet(const Input: string;
      const BaseUrl: string; Mode: TPixieDocumentMode;
      Media: TPixieMediaQueryListList = nil; TopLevel: Boolean = True); overload;
    procedure ParseCssStylesheet(Tokens: TPixieCssTokenList;
      const BaseUrl: string; Mode: TPixieDocumentMode;
      Media: TPixieMediaQueryListList = nil; TopLevel: Boolean = True); overload;
    procedure SortSelectors;
    procedure BuildIndex;

    function GetCandidatesByTag(Tag: Integer): TPixieCssSelectorList;
    function GetCandidatesByClass(ClassId: Integer): TPixieCssSelectorList;
    function GetCandidatesById(Id: Integer): TPixieCssSelectorList;
    function GetUniversalCandidates: TPixieCssSelectorList;

    procedure ApplyMediaFeatures(
      const Features: TPixieMediaFeatures);
    function WouldMediaChange(
      const OldFeatures, NewFeatures: TPixieMediaFeatures): Boolean;

    property Selectors: TPixieCssSelectorList read FSelectors;
    property IsIndexed: Boolean read FIsIndexed;
  public
    // Non-owning: set by the document before parsing, receives @font-face entries
    FontFaces: TPixieFontFaceEntryList;
  end;

implementation

{ TPixieStylesheet }

constructor TPixieStylesheet.Create;
begin
  inherited Create;
  FSelectors := TPixieCssSelectorList.Create;
  FStyles := TPixieStyleList.Create;
  FMediaQueries := TPixieMediaQueryListListObjList.Create;
  FMqLists := TPixieMediaQueryListObjList.Create;
  FOrder := 0;
  FTagIndex := nil;
  FClassIndex := nil;
  FIdIndex := nil;
  FUniversalList := nil;
  FIsIndexed := False;
end;

destructor TPixieStylesheet.Destroy;
var
  I: Integer;
begin
  ClearIndex;
  // MqLL.Lists are non-owning, so disable ownership before freeing
  for I := 0 to FMediaQueries.Count - 1 do
    FMediaQueries[I].Lists.OwnsObjects := False;
  FMediaQueries.Free;
  FMqLists.Free;
  FSelectors.Free;
  FStyles.Free;
  inherited;
end;

procedure TPixieStylesheet.AddSelector(Sel: TPixieCssSelector);
begin
  Sel.Order := FOrder;
  Inc(FOrder);
  FSelectors.Add(Sel);
end;

function TPixieStylesheet.ParseStyleRule(Rule: TPixieCssRawRule;
  const BaseUrl: string; Mode: TPixieDocumentMode;
  Media: TPixieMediaQueryListList): Boolean;
var
  Prelude: TPixieCssTokenList;
  List: TPixieCssSelectorList;
  NewStyle: TPixieStyle;
  I: Integer;
  Sel: TPixieCssSelector;
begin
  // Componentize prelude tokens for selector parsing
  Prelude := TPixieCssTokenList.Create;
  try
    PixieCssTokenListCopy(Rule.Prelude, Prelude);
    PixieCssComponentize(Prelude);

    List := PixieParseSelectorList(Prelude, PixieSelectorStrict, Mode);
  finally
    Prelude.Free;
  end;

  try
    if List.Count = 0 then
      Exit(False);

    // Create a new style and parse the rule's block contents into it
    NewStyle := TPixieStyle.Create;
    FStyles.Add(NewStyle);

    if Rule.Block <> nil then
      NewStyle.Add(Rule.Block.Value, BaseUrl);

    // Attach style and media to each selector, then add to our list
    // Transfer ownership of selectors from List to FSelectors
    List.OwnsObjects := False;
    for I := 0 to List.Count - 1 do
    begin
      Sel := List[I];
      Sel.Style := NewStyle;
      Sel.MediaQuery := Media;
      Sel.CalcSpecificity;
      AddSelector(Sel);
    end;

    Result := True;
  finally
    List.Free;
  end;
end;

procedure TPixieStylesheet.ParseMediaRule(Rule: TPixieCssRawRule;
  const BaseUrl: string; Mode: TPixieDocumentMode;
  Media: TPixieMediaQueryListList);
var
  MqList: TPixieMediaQueryList;
  MqLL: TPixieMediaQueryListList;
  I: Integer;
begin
  if Rule.Block = nil then
    Exit;

  // Parse the @media prelude as a media query list
  MqList := TPixieMediaQueryList.Parse(Rule.Prelude);
  FMqLists.Add(MqList); // stylesheet owns all MqList objects

  // Build a MqLL combining parent media queries with this one.
  // MqLL.Lists is non-owning — MqList objects are owned by FMqLists.
  MqLL := TPixieMediaQueryListList.Create;
  MqLL.Lists.OwnsObjects := False;
  FMediaQueries.Add(MqLL);

  if Media <> nil then
    for I := 0 to Media.Lists.Count - 1 do
      MqLL.Lists.Add(Media.Lists[I]);

  MqLL.Lists.Add(MqList);

  ParseCssStylesheet(Rule.Block.Value, BaseUrl, Mode, MqLL, False);
end;

// Parse from string input
procedure TPixieStylesheet.ParseCssStylesheet(const Input: string;
  const BaseUrl: string; Mode: TPixieDocumentMode;
  Media: TPixieMediaQueryListList; TopLevel: Boolean);
var
  Tokens: TPixieCssTokenList;
begin
  Tokens := PixieCssTokenize(Input);
  try
    ParseCssStylesheet(Tokens, BaseUrl, Mode, Media, TopLevel);
  finally
    Tokens.Free;
  end;
end;

// Parse from token list
procedure TPixieStylesheet.ParseCssStylesheet(Tokens: TPixieCssTokenList;
  const BaseUrl: string; Mode: TPixieDocumentMode;
  Media: TPixieMediaQueryListList; TopLevel: Boolean);
var
  Rules: TPixieCssRawRuleList;
  Rule: TPixieCssRawRule;
  I: Integer;
  RuleName: Integer;
  Entry: TPixieFontFaceEntry;
begin
  // Register external media query (e.g. <style media="...">) for tracking
  if (Media <> nil) and (FMediaQueries.IndexOf(Media) < 0) then
  begin
    Media.Lists.OwnsObjects := False;
    for I := 0 to Media.Lists.Count - 1 do
      FMqLists.Add(Media.Lists[I]);
    FMediaQueries.Add(Media);
  end;

  Rules := PixieCssParseStylesheet(Tokens, TopLevel);
  try
    for I := 0 to Rules.Count - 1 do
    begin
      Rule := Rules[I];

      if Rule.RuleType = cssRuleQualified then
      begin
        ParseStyleRule(Rule, BaseUrl, Mode, Media);
        Continue;
      end;

      // At-rule
      RuleName := PixieId(PixieLowerCase(Rule.Name));

      if RuleName = Ord(psid_charset) then
        // @charset: ignored per spec
        Continue;

      if RuleName = Ord(psid_import) then
        // @import: requires document container for fetching — skip for now
        Continue;

      if RuleName = Ord(psid_media) then
      begin
        ParseMediaRule(Rule, BaseUrl, Mode, Media);
        Continue;
      end;

      if RuleName = Ord(psid_layer) then
      begin
        if Rule.Block <> nil then
          ParseCssStylesheet(Rule.Block.Value, BaseUrl, Mode, Media, False);
        Continue;
      end;

      if RuleName = Ord(psid_supports) then
      begin
        if Rule.Block <> nil then
          ParseCssStylesheet(Rule.Block.Value, BaseUrl, Mode, Media, False);
        Continue;
      end;

      if RuleName = Ord(psid_font_face) then
      begin
        if (Rule.Block <> nil) and (FontFaces <> nil) then
        begin
          Entry := PixieParseFontFaceRule(Rule.Block.Value, BaseUrl);
          if Entry <> nil then
            FontFaces.Add(Entry);
        end;
        Continue;
      end;

      // Unknown at-rules: ignored
    end;
  finally
    Rules.Free;
  end;
end;

procedure TPixieStylesheet.ClearIndex;
var
  Pair: TPair<Integer, TPixieCssSelectorList>;
begin
  if FTagIndex <> nil then
  begin
    for Pair in FTagIndex do
      Pair.Value.Free;
    FreeAndNil(FTagIndex);
  end;
  if FClassIndex <> nil then
  begin
    for Pair in FClassIndex do
      Pair.Value.Free;
    FreeAndNil(FClassIndex);
  end;
  if FIdIndex <> nil then
  begin
    for Pair in FIdIndex do
      Pair.Value.Free;
    FreeAndNil(FIdIndex);
  end;
  FreeAndNil(FUniversalList);
  FIsIndexed := False;
end;

procedure TPixieStylesheet.AddToIndexMap(Map: TPixieSelectorIndexMap;
  Key: Integer; Sel: TPixieCssSelector);
var
  List: TPixieCssSelectorList;
begin
  if not Map.TryGetValue(Key, List) then
  begin
    List := TPixieCssSelectorList.Create(False); // non-owning
    Map.Add(Key, List);
  end;
  List.Add(Sel);
end;

procedure TPixieStylesheet.BuildIndex;
var
  I, J: Integer;
  Sel: TPixieCssSelector;
  Attr: TPixieAttrSelector;
  Bucketed: Boolean;
begin
  ClearIndex;

  FTagIndex := TPixieSelectorIndexMap.Create;
  FClassIndex := TPixieSelectorIndexMap.Create;
  FIdIndex := TPixieSelectorIndexMap.Create;
  FUniversalList := TPixieCssSelectorList.Create(False); // non-owning

  for I := 0 to FSelectors.Count - 1 do
  begin
    Sel := FSelectors[I];
    Bucketed := False;

    // Priority: ID > class > tag > universal
    // Check rightmost compound selector's attrs for ID
    for J := 0 to Sel.Right.Attrs.Count - 1 do
    begin
      Attr := Sel.Right.Attrs[J];
      if Attr.SelectType = selectId then
      begin
        AddToIndexMap(FIdIndex, Attr.Name, Sel);
        Bucketed := True;
        Break;
      end;
    end;

    if not Bucketed then
    begin
      // Check for class
      for J := 0 to Sel.Right.Attrs.Count - 1 do
      begin
        Attr := Sel.Right.Attrs[J];
        if Attr.SelectType = selectClass then
        begin
          AddToIndexMap(FClassIndex, Attr.Name, Sel);
          Bucketed := True;
          Break;
        end;
      end;
    end;

    if not Bucketed then
    begin
      // Check for tag (not universal *)
      if Sel.Right.Tag <> PixieStarId then
      begin
        AddToIndexMap(FTagIndex, Sel.Right.Tag, Sel);
        Bucketed := True;
      end;
    end;

    if not Bucketed then
      FUniversalList.Add(Sel);
  end;

  FIsIndexed := True;
end;

function TPixieStylesheet.GetCandidatesByTag(Tag: Integer): TPixieCssSelectorList;
begin
  if (FTagIndex <> nil) and FTagIndex.TryGetValue(Tag, Result) then
    Exit;
  Result := nil;
end;

function TPixieStylesheet.GetCandidatesByClass(ClassId: Integer): TPixieCssSelectorList;
begin
  if (FClassIndex <> nil) and FClassIndex.TryGetValue(ClassId, Result) then
    Exit;
  Result := nil;
end;

function TPixieStylesheet.GetCandidatesById(Id: Integer): TPixieCssSelectorList;
begin
  if (FIdIndex <> nil) and FIdIndex.TryGetValue(Id, Result) then
    Exit;
  Result := nil;
end;

function TPixieStylesheet.GetUniversalCandidates: TPixieCssSelectorList;
begin
  Result := FUniversalList;
end;

procedure TPixieStylesheet.SortSelectors;
var
  I, J: Integer;
  Tmp: TPixieCssSelector;
  Cmp: Integer;
begin
  // Simple insertion sort — selector lists are typically small enough.
  // Sort by specificity ascending, then by order ascending.
  FSelectors.OwnsObjects := False;
  try
    for I := 1 to FSelectors.Count - 1 do
    begin
      Tmp := FSelectors[I];
      J := I - 1;
      while J >= 0 do
      begin
        Cmp := FSelectors[J].Specificity.Compare(Tmp.Specificity);
        if (Cmp > 0) or ((Cmp = 0) and (FSelectors[J].Order > Tmp.Order)) then
        begin
          FSelectors[J + 1] := FSelectors[J];
          Dec(J);
        end
        else
          Break;
      end;
      FSelectors[J + 1] := Tmp;
    end;
  finally
    FSelectors.OwnsObjects := True;
  end;

  BuildIndex;
end;

procedure TPixieStylesheet.ApplyMediaFeatures(
  const Features: TPixieMediaFeatures);
var
  I: Integer;
begin
  for I := 0 to FMediaQueries.Count - 1 do
    FMediaQueries[I].ApplyMediaFeatures(Features);
end;

function TPixieStylesheet.WouldMediaChange(
  const OldFeatures, NewFeatures: TPixieMediaFeatures): Boolean;
var
  I: Integer;
  OldMatch, NewMatch: Boolean;
  MqLL: TPixieMediaQueryListList;
  J: Integer;
begin
  Result := False;
  for I := 0 to FMediaQueries.Count - 1 do
  begin
    MqLL := FMediaQueries[I];
    OldMatch := True;
    NewMatch := True;
    for J := 0 to MqLL.Lists.Count - 1 do
    begin
      if not MqLL.Lists[J].Check(OldFeatures) then
        OldMatch := False;
      if not MqLL.Lists[J].Check(NewFeatures) then
        NewMatch := False;
    end;
    if OldMatch <> NewMatch then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

end.
