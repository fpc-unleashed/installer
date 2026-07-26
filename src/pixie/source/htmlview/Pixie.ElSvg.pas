unit Pixie.ElSvg;

// Inline <svg> element — renders SVG content embedded in HTML.
// Serializes the DOM subtree back to XML and renders via TPixieSvgCanvasRenderer.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Generics.Collections,
  Pixie.Types, Pixie.CssLength, Pixie.Background,
  Pixie.Container,
  Pixie.Element, Pixie.HtmlTag,
  Pixie.SvgRenderer.Canvas;

type
  { TPixieElSvg }

  TPixieElSvg = class(TPixieHtmlTag)
  private
    FRenderer: TPixieSvgCanvasRenderer;
    FSvgWidth: Single;
    FSvgHeight: Single;
    FParsed: Boolean;
    procedure EnsureParsed;
    procedure SerializeElement(El: TPixieElement; var S: string);
    procedure SerializeChildren(El: TPixieElement; var S: string);
  public
    constructor Create(ADoc: TObject);
    destructor Destroy; override;

    function IsReplaced: Boolean; override;
    procedure ParseAttributes; override;
    procedure GetContentSize(var Sz: TPixieSize;
      MaxWidth: TPixiePixel); override;
    procedure Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
      Clip: PPixiePosition; Ri: Pointer); override;
    function CreateRenderItem(ParentRi: Pointer): Pointer; override;
  end;

implementation

uses
  Pixie.StringId, Pixie.Canvas, Pixie.Style,
  Pixie.RenderItem, Pixie.RenderImage,
  Pixie.NativeContainer;

function XmlEscape(const S: string): string;
var
  I: Integer;
  Ch: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    Ch := S[I];
    case Ch of
      '&': Result := Result + '&amp;';
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '"': Result := Result + '&quot;';
    else
      Result := Result + Ch;
    end;
  end;
end;

{ TPixieElSvg }

constructor TPixieElSvg.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
  FCss.Display := displayInlineBlock;
  FRenderer := nil;
  FParsed := False;
end;

destructor TPixieElSvg.Destroy;
begin
  FRenderer.Free;
  inherited Destroy;
end;

function TPixieElSvg.IsReplaced: Boolean;
begin
  Result := True;
end;

procedure TPixieElSvg.SerializeElement(El: TPixieElement; var S: string);
var
  Tag: TPixieHtmlTag;
  Pair: TPair<string, string>;
  TagName, AttrName: string;
  I: Integer;
  Prop: TPixiePropertyValue;
begin
  if not (El is TPixieHtmlTag) then
  begin
    // Text node
    S := S + XmlEscape(El.GetDisplayText);
    Exit;
  end;

  Tag := TPixieHtmlTag(El);
  TagName := Tag.GetTagName;
  if TagName = '' then Exit;

  S := S + '<' + TagName;
  for Pair in Tag.Attrs do
    S := S + ' ' + Pair.Key + '="' +
      XmlEscape(PixieResolveCssVars(Pair.Value, Tag)) + '"';

  // Surface CSS-set SVG presentation properties as XML attributes if the
  // element doesn't already carry them as presentation attributes (which
  // win per SVG 1.1 cascade order). Attribute name is derived from the
  // psid identifier — PixieStr(Ord(psid_stroke_width)) returns
  // "stroke-width", matching the SVG attribute spelling.
  for I := Low(PixieSvgPresentationPropIds) to
           High(PixieSvgPresentationPropIds) do
  begin
    AttrName := PixieStr(Ord(PixieSvgPresentationPropIds[I]));
    if Tag.Attrs.ContainsKey(AttrName) then
      Continue;
    Prop := Tag.Style.GetProperty(Ord(PixieSvgPresentationPropIds[I]));
    if Prop.Kind = pkString then
      S := S + ' ' + AttrName + '="' +
        XmlEscape(PixieResolveCssVars(Prop.StrVal, Tag)) + '"';
  end;

  if Tag.Children.Count = 0 then
    S := S + '/>'
  else
  begin
    S := S + '>';
    SerializeChildren(Tag, S);
    S := S + '</' + TagName + '>';
  end;
end;

procedure TPixieElSvg.SerializeChildren(El: TPixieElement; var S: string);
var
  I: Integer;
begin
  for I := 0 to El.Children.Count - 1 do
    SerializeElement(El.Children[I], S);
end;

procedure TPixieElSvg.EnsureParsed;
var
  Xml: string;
  Utf8: UTF8String;
  Cont: TPixieContainer;
  Canvas: TPixieCanvas;
begin
  if FParsed then Exit;
  FParsed := True;

  Cont := GetDocContainer;
  if not (Cont is TPixieNativeContainer) then Exit;
  Canvas := TPixieNativeContainer(Cont).Canvas;

  // Serialize this <svg> element and its children to XML
  Xml := '';
  SerializeElement(Self, Xml);
  if Xml = '' then Exit;

  // Add xmlns if missing
  if Pos('xmlns', Xml) = 0 then
    Xml := StringReplace(Xml, '<svg ', '<svg xmlns="http://www.w3.org/2000/svg" ', []);

  Utf8 := UTF8Encode(Xml);

  FRenderer := TPixieSvgCanvasRenderer.Create(Canvas);
  if not FRenderer.ParseSvg(@Utf8[1], Length(Utf8), FSvgWidth, FSvgHeight) then
    FreeAndNil(FRenderer);
end;

procedure TPixieElSvg.ParseAttributes;
begin
  // SVG width/height attributes are presentation attributes — they set the
  // intrinsic content size (via GetContentSize) but must NOT be promoted to
  // CSS properties, otherwise they override author CSS like
  // `header .home svg { width: 3rem }`. The renderer reads them itself.
  inherited ParseAttributes;
end;

procedure TPixieElSvg.GetContentSize(var Sz: TPixieSize;
  MaxWidth: TPixiePixel);
begin
  EnsureParsed;
  Sz.Width := FSvgWidth;
  Sz.Height := FSvgHeight;
end;

procedure TPixieElSvg.Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
  Clip: PPixiePosition; Ri: Pointer);
var
  RenderIt: TPixieRenderItem;
  P: TPixiePosition;
begin
  inherited Draw(Hdc, X, Y, Clip, Ri);

  EnsureParsed;
  if FRenderer = nil then Exit;

  RenderIt := TPixieRenderItem(Ri);
  P := RenderIt.Pos;
  P.X := P.X + X;
  P.Y := P.Y + Y;
  P.DoRound;

  if (Clip <> nil) and (not P.DoesIntersect(Clip^)) then
    Exit;
  if (P.Width <= 0) or (P.Height <= 0) then
    Exit;

  // Pass the inherited CSS color to the SVG renderer so that
  // fill="currentColor" and stroke="currentColor" resolve correctly.
  FRenderer.SetCurrentColor(FCss.Color);

  FRenderer.RenderToRect(P.X, P.Y, P.Width, P.Height);
end;

function TPixieElSvg.CreateRenderItem(ParentRi: Pointer): Pointer;
var
  Ret: TPixieRenderImage;
begin
  Ret := TPixieRenderImage.Create(Self);
  Ret.SetParent(TPixieRenderItem(ParentRi));
  Result := Ret;
end;

end.
