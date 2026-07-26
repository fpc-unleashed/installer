unit Pixie.ElMisc;

// Simple HTML element types.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Math, Generics.Collections,
  Pixie.Types, Pixie.CssProperties,
  Pixie.Style, Pixie.Stylesheet,
  Pixie.Element, Pixie.HtmlTag;

type
  { TPixieElBody }

  TPixieElBody = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject);
    procedure ParseAttributes; override;
    procedure ComputeStyles(Recursive: Boolean = True); override;
    function IsBody: Boolean; override;
  end;

  { TPixieElBreak }

  TPixieElBreak = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject);
    function IsBreak: Boolean; override;
  end;

  { TPixieElDiv }

  TPixieElDiv = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject);
    procedure ParseAttributes; override;
  end;

  { TPixieElPara }

  TPixieElPara = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject);
    procedure ParseAttributes; override;
  end;

  { TPixieElFont }

  TPixieElFont = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject);
    procedure ParseAttributes; override;
  end;

  { TPixieElLink }

  TPixieElLink = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject);
    procedure ParseAttributes; override;
  end;

  { TPixieElTitle }

  TPixieElTitle = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject);
    procedure ParseAttributes; override;
  end;

  { TPixieElOl }

  TPixieElOl = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject);
    procedure ParseAttributes; override;
  end;

  { TPixieElUl }

  TPixieElUl = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject);
    procedure ParseAttributes; override;
  end;

  { TPixieElHr }

  TPixieElHr = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject);
    procedure ParseAttributes; override;
  end;

  { TPixieElBase }

  TPixieElBase = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject);
    procedure ParseAttributes; override;
  end;

  // --- The following inherit from TPixieElement, NOT TPixieHtmlTag ---

  { TPixieElScript }

  TPixieElScript = class(TPixieElement)
  private
    FText: string;
  public
    constructor Create(ADoc: TObject);
    function AppendChild(El: TPixieElement): Boolean; override;
    function CreateRenderItem(ParentRi: Pointer): Pointer; override;
    function GetTag: Integer; override;
    function GetTagName: string; override;
    procedure ParseAttributes; override;
  end;

  { TPixieElStyle }

  TPixieElStyle = class(TPixieElement)
  private
    FChildElements: TPixieElementList;
  public
    constructor Create(ADoc: TObject);
    destructor Destroy; override;
    function AppendChild(El: TPixieElement): Boolean; override;
    function GetTag: Integer; override;
    function GetTagName: string; override;
    procedure ParseAttributes; override;
    procedure ComputeStyles(Recursive: Boolean = True); override;
  end;

  { TPixieElCData }

  TPixieElCData = class(TPixieElement)
  private
    FText: string;
  public
    constructor Create(ADoc: TObject);
    procedure GetText(var Text: string); override;
    procedure SetData(const AData: string); override;
  end;

  { TPixieElComment }

  TPixieElComment = class(TPixieElement)
  private
    FText: string;
  public
    constructor Create(ADoc: TObject);
    function IsComment: Boolean; override;
    procedure GetText(var Text: string); override;
    procedure SetData(const AData: string); override;
    function CreateRenderItem(ParentRi: Pointer): Pointer; override;
  end;

implementation

uses
  Pixie.StringId, Pixie.Utils, Pixie.Container, Pixie.Document;

{ TPixieElBody }

constructor TPixieElBody.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

procedure TPixieElBody.ParseAttributes;
var
  Val: string;
begin
  inherited;

  Val := GetAttr('bgcolor');
  if Val <> '' then
    FStyle.AddProperty(Ord(psid_background_color), Val);

  Val := GetAttr('text');
  if Val <> '' then
    FStyle.AddProperty(Ord(psid_color), Val);
end;

procedure TPixieElBody.ComputeStyles(Recursive: Boolean);
begin
  inherited ComputeStyles(Recursive);

  // CSS Overflow § 3.3: a non-visible overflow value on <body> propagates
  // to the viewport (body's used value becomes visible) when <html>
  // itself has overflow: visible. Without this, body's own overflow
  // turns it into a fixed-height scroll container that clips its content.
  if (FCss.Overflow <> ovVisible) and
     (Parent <> nil) and (Parent.Css.Overflow = ovVisible) then
    FCss.Overflow := ovVisible;
end;

function TPixieElBody.IsBody: Boolean;
begin
  Result := True;
end;

{ TPixieElBreak }

constructor TPixieElBreak.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

function TPixieElBreak.IsBreak: Boolean;
begin
  Result := True;
end;

{ TPixieElDiv }

constructor TPixieElDiv.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

procedure TPixieElDiv.ParseAttributes;
var
  Val: string;
begin
  Val := GetAttr('align');
  if Val <> '' then
    MapAlignToTextAlign(Val);
  inherited ParseAttributes;
end;

{ TPixieElPara }

constructor TPixieElPara.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

procedure TPixieElPara.ParseAttributes;
var
  Val: string;
begin
  Val := GetAttr('align');
  if Val <> '' then
    MapAlignToTextAlign(Val);
  inherited ParseAttributes;
end;

{ TPixieElFont }

constructor TPixieElFont.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

procedure TPixieElFont.ParseAttributes;
var
  Val, SizeStr: string;
  Sz, Offset: Integer;
begin
  Val := GetAttr('color');
  if Val <> '' then
    FStyle.AddProperty(Ord(psid_color), Val);

  Val := GetAttr('face');
  if Val <> '' then
    FStyle.AddProperty(Ord(psid_font_family), Val);

  Val := GetAttr('size');
  if Val <> '' then
  begin
    if (Length(Val) > 0) and ((Val[1] = '+') or (Val[1] = '-')) then
    begin
      // Relative size
      Offset := StrToIntDef(Val, 0);
      Sz := 3 + Offset;
    end
    else
      Sz := StrToIntDef(Val, 3);

    if Sz <= 1 then
      SizeStr := 'x-small'
    else if Sz = 2 then
      SizeStr := 'small'
    else if Sz = 3 then
      SizeStr := 'medium'
    else if Sz = 4 then
      SizeStr := 'large'
    else if Sz = 5 then
      SizeStr := 'x-large'
    else
      SizeStr := 'xx-large';

    FStyle.AddProperty(Ord(psid_font_size), SizeStr);
  end;

  inherited ParseAttributes;
end;

{ TPixieElLink }

constructor TPixieElLink.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

procedure TPixieElLink.ParseAttributes;
var
  Rel, Href, Media, CssText, BaseUrl: string;
  Cont: TPixieContainer;
  Processed: Boolean;
begin
  Processed := False;
  Rel := GetAttr('rel');

  if SameText(Rel, 'stylesheet') then
  begin
    Href := GetAttr('href');
    if Href <> '' then
    begin
      Media := GetAttr('media');
      CssText := '';
      BaseUrl := '';
      Cont := GetDocContainer;
      if Cont <> nil then
      begin
        Cont.ImportCss(CssText, Href, BaseUrl);
        if CssText <> '' then
        begin
          if FDoc <> nil then
          begin
            Assert(FDoc is TPixieDocument);
            TPixieDocument(FDoc).AddStylesheet(CssText, BaseUrl,
              Media);
          end;
          Processed := True;
        end;
      end;
    end;
  end;

  if not Processed then
  begin
    Cont := GetDocContainer;
    if Cont <> nil then
      Cont.Link(FDoc, Self);
  end;

  inherited ParseAttributes;
end;

{ TPixieElTitle }

constructor TPixieElTitle.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

procedure TPixieElTitle.ParseAttributes;
var
  Txt: string;
  Cont: TPixieContainer;
begin
  Txt := '';
  GetText(Txt);
  Cont := GetDocContainer;
  if Cont <> nil then
    Cont.SetCaption(Txt);
  inherited ParseAttributes;
end;

{ TPixieElOl }

constructor TPixieElOl.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

procedure TPixieElOl.ParseAttributes;
var
  Val: string;
begin
  Val := GetAttr('type');
  if Val <> '' then
  begin
    if Val = '1' then
      FStyle.AddProperty(Ord(psid_list_style_type), 'decimal')
    else if Val = 'a' then
      FStyle.AddProperty(Ord(psid_list_style_type), 'lower-alpha')
    else if Val = 'A' then
      FStyle.AddProperty(Ord(psid_list_style_type), 'upper-alpha')
    else if Val = 'i' then
      FStyle.AddProperty(Ord(psid_list_style_type), 'lower-roman')
    else if Val = 'I' then
      FStyle.AddProperty(Ord(psid_list_style_type), 'upper-roman');
  end;
  Val := GetAttr('align');
  if Val <> '' then
    MapAlignToTextAlign(Val);
  inherited ParseAttributes;
end;

{ TPixieElUl }

constructor TPixieElUl.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

procedure TPixieElUl.ParseAttributes;
var
  Val: string;
begin
  Val := GetAttr('type');
  if Val <> '' then
  begin
    if SameText(Val, 'disc') then
      FStyle.AddProperty(Ord(psid_list_style_type), 'disc')
    else if SameText(Val, 'circle') then
      FStyle.AddProperty(Ord(psid_list_style_type), 'circle')
    else if SameText(Val, 'square') then
      FStyle.AddProperty(Ord(psid_list_style_type), 'square');
  end;
  Val := GetAttr('align');
  if Val <> '' then
    MapAlignToTextAlign(Val);
  inherited ParseAttributes;
end;

{ TPixieElHr }

constructor TPixieElHr.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

procedure TPixieElHr.ParseAttributes;
var
  ColorVal, SizeVal, WidthVal: string;
  HasNoshade, HasColor: Boolean;
  Sz: Integer;
begin
  ColorVal := GetAttr('color');
  SizeVal := GetAttr('size');
  WidthVal := GetAttr('width');
  HasNoshade := GetAttr('noshade', #1) <> #1;
  HasColor := ColorVal <> '';

  if HasNoshade or HasColor then
    FStyle.AddProperty(Ord(psid_border_style), 'solid');

  if HasColor then
  begin
    FStyle.AddProperty(Ord(psid_border_color), ColorVal);
    FStyle.AddProperty(Ord(psid_background_color), ColorVal);
  end;

  if SizeVal <> '' then
  begin
    Sz := StrToIntDef(SizeVal, -1);
    if Sz >= 1 then
    begin
      // Total height = size; subtract 2px for top+bottom borders
      MapToPixelLengthProperty(Ord(psid_height), IntToStr(Max(Sz - 2, 0)));
      // size=1 with noshade/color: remove bottom border for 1px total
      if (Sz = 1) and (HasNoshade or HasColor) then
        MapToPixelLengthProperty(Ord(psid_border_bottom_width), '0');
    end;
  end;

  // width -> can be percentage or pixel
  if WidthVal <> '' then
    MapToDimensionProperty(Ord(psid_width), WidthVal);

  inherited ParseAttributes;
end;

{ TPixieElBase }

constructor TPixieElBase.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

procedure TPixieElBase.ParseAttributes;
var
  Href: string;
  Cont: TPixieContainer;
begin
  Href := GetAttr('href');
  if Href <> '' then
  begin
    Cont := GetDocContainer;
    if Cont <> nil then
      Cont.SetBaseUrl(Href);
  end;
  inherited ParseAttributes;
end;

{ TPixieElScript }

constructor TPixieElScript.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

function TPixieElScript.AppendChild(El: TPixieElement): Boolean;
var
  Txt: string;
begin
  Txt := '';
  El.GetText(Txt);
  FText := FText + Txt;
  Result := True;
end;

function TPixieElScript.CreateRenderItem(ParentRi: Pointer): Pointer;
begin
  Result := nil;
end;

function TPixieElScript.GetTag: Integer;
begin
  Result := Ord(psid_script);
end;

function TPixieElScript.GetTagName: string;
begin
  Result := 'script';
end;

procedure TPixieElScript.ParseAttributes;
begin
  // Script execution not implemented
end;

{ TPixieElStyle }

constructor TPixieElStyle.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
  FChildElements := TPixieElementList.Create(False);
end;

destructor TPixieElStyle.Destroy;
begin
  FChildElements.Free;
  inherited Destroy;
end;

function TPixieElStyle.AppendChild(El: TPixieElement): Boolean;
begin
  if El.IsText then
  begin
    FChildElements.Add(El);
    Result := True;
  end
  else
    Result := False;
end;

function TPixieElStyle.GetTag: Integer;
begin
  Result := Ord(psid_style);
end;

function TPixieElStyle.GetTagName: string;
begin
  Result := 'style';
end;

procedure TPixieElStyle.ParseAttributes;
var
  Txt, Media: string;
  I: Integer;
begin
  Txt := '';
  for I := 0 to FChildElements.Count - 1 do
    FChildElements[I].GetText(Txt);

  if (Txt <> '') and (FDoc <> nil) then
  begin
    Assert(FDoc is TPixieDocument);
    Media := '';
    // Style elements can have a media attribute
    // but TPixieElStyle inherits from TPixieElement which has no GetAttr,
    // so media filtering happens at parse time in Document
    TPixieDocument(FDoc).AddStylesheet(Txt, '', Media);
  end;
end;

procedure TPixieElStyle.ComputeStyles(Recursive: Boolean);
begin
  FCss.Display := displayNone;
end;

{ TPixieElCData }

constructor TPixieElCData.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

procedure TPixieElCData.GetText(var Text: string);
begin
  Text := Text + FText;
end;

procedure TPixieElCData.SetData(const AData: string);
begin
  FText := FText + AData;
end;

{ TPixieElComment }

constructor TPixieElComment.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

function TPixieElComment.IsComment: Boolean;
begin
  Result := True;
end;

procedure TPixieElComment.GetText(var Text: string);
begin
  Text := Text + FText;
end;

procedure TPixieElComment.SetData(const AData: string);
begin
  FText := FText + AData;
end;

function TPixieElComment.CreateRenderItem(ParentRi: Pointer): Pointer;
begin
  Result := nil;
end;

end.
