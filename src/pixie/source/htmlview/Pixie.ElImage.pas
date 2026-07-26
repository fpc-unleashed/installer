unit Pixie.ElImage;

// Image element (<img>).

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils,
  Pixie.Types, Pixie.CssLength, Pixie.Background,
  Pixie.AnimatedImage, Pixie.Container,
  Pixie.Element, Pixie.HtmlTag;

type
  { TPixieElImage }

  TPixieElImage = class(TPixieHtmlTag)
  private
    FSrc: string;
    FAlt: string;
    FAnimCursor: TPixieAnimationCursor; // weak ref; owned by view core
    FAnimSrc: string;                   // src the cursor was bound to
    procedure ReleaseAnimationCursor;
    procedure EnsureAnimationCursor;
    procedure MapImageAlign(const AttrValue: string);
  public
    constructor Create(ADoc: TObject);
    destructor Destroy; override;

    function IsReplaced: Boolean; override;
    procedure ParseAttributes; override;
    procedure ComputeStyles(Recursive: Boolean = True); override;
    procedure GetContentSize(var Sz: TPixieSize;
      MaxWidth: TPixiePixel); override;
    procedure Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
      Clip: PPixiePosition; Ri: Pointer); override;
    function CreateRenderItem(ParentRi: Pointer): Pointer; override;
    function DumpGetName: string; override;
  end;

  { TPixieElVideo — <video>/<audio>. Pixie cannot play media, so the element is
    treated as a replaced box (reserving its width/height and showing the
    poster, if any). Its fallback content (<source>/<img>/<track>/text) is NOT
    rendered — browsers only show that when the media element is unsupported, so
    rendering it produces a spurious image. Reusing TPixieElImage gives the
    replaced behaviour, the width/height presentation hints, and — crucially —
    no recursion into children (TPixieElImage.CreateRenderItem builds no child
    render items). }
  TPixieElVideo = class(TPixieElImage)
  public
    procedure ParseAttributes; override;
    function DumpGetName: string; override;
  end;

implementation

uses
  Pixie.StringId, Pixie.RenderItem, Pixie.RenderImage;

{ TPixieElImage }

constructor TPixieElImage.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
  FCss.Display := displayInlineBlock;
  FAnimCursor := nil;
end;

destructor TPixieElImage.Destroy;
begin
  ReleaseAnimationCursor;
  inherited Destroy;
end;

procedure TPixieElImage.ReleaseAnimationCursor;
var
  Cont: TPixieContainer;
begin
  if FAnimCursor = nil then Exit;
  Cont := GetDocContainer;
  if Cont <> nil then
    Cont.ReleaseAnimationCursor(FAnimCursor);
  FAnimCursor := nil;
  FAnimSrc := '';
end;

procedure TPixieElImage.EnsureAnimationCursor;
var
  Cont: TPixieContainer;
  AnimImg: TPixieAnimatedImage;
begin
  if FSrc = '' then
  begin
    ReleaseAnimationCursor;
    Exit;
  end;
  if (FAnimCursor <> nil) and (FAnimSrc = FSrc) then Exit;
  if FAnimCursor <> nil then
    ReleaseAnimationCursor;
  Cont := GetDocContainer;
  if Cont = nil then Exit;
  AnimImg := Cont.GetAnimatedImage(FSrc, '');
  if AnimImg = nil then Exit;
  FAnimCursor := Cont.AcquireAnimationCursor(Self, AnimImg);
  if FAnimCursor <> nil then
    FAnimSrc := FSrc;
end;

function TPixieElImage.IsReplaced: Boolean;
begin
  Result := True;
end;

// Map the legacy presentational <img align="..."> attribute. The left
// and right values float the image; the remaining values set the
// vertical alignment relative to the surrounding inline content. The
// non-standard Netscape values (texttop, absmiddle, absbottom) are
// honoured the way browsers do for backwards compatibility.
procedure TPixieElImage.MapImageAlign(const AttrValue: string);
begin
  if SameText(AttrValue, 'left') then
    Style.AddProperty(Ord(psid_float), 'left')
  else if SameText(AttrValue, 'right') then
    Style.AddProperty(Ord(psid_float), 'right')
  else if SameText(AttrValue, 'top') then
    Style.AddProperty(Ord(psid_vertical_align), 'top')
  else if SameText(AttrValue, 'texttop') then
    Style.AddProperty(Ord(psid_vertical_align), 'text-top')
  else if SameText(AttrValue, 'middle') or SameText(AttrValue, 'absmiddle') or
          SameText(AttrValue, 'center') then
    Style.AddProperty(Ord(psid_vertical_align), 'middle')
  else if SameText(AttrValue, 'bottom') or SameText(AttrValue, 'absbottom') then
    Style.AddProperty(Ord(psid_vertical_align), 'bottom')
  else if SameText(AttrValue, 'baseline') then
    Style.AddProperty(Ord(psid_vertical_align), 'baseline');
end;

procedure TPixieElImage.ParseAttributes;
var
  Val: string;
begin
  FSrc := GetAttr('src');
  FAlt := GetAttr('alt');

  Val := GetAttr('width');
  if Val <> '' then
    MapToDimensionProperty(Ord(psid_width), Val);

  Val := GetAttr('height');
  if Val <> '' then
    MapToDimensionProperty(Ord(psid_height), Val);

  Val := GetAttr('hspace');
  if Val <> '' then
  begin
    MapToPixelLengthProperty(Ord(psid_margin_left), Val);
    MapToPixelLengthProperty(Ord(psid_margin_right), Val);
  end;

  Val := GetAttr('vspace');
  if Val <> '' then
  begin
    MapToPixelLengthProperty(Ord(psid_margin_top), Val);
    MapToPixelLengthProperty(Ord(psid_margin_bottom), Val);
  end;

  Val := GetAttr('align');
  if Val <> '' then
    MapImageAlign(Val);

  inherited ParseAttributes;
end;

procedure TPixieElImage.ComputeStyles(Recursive: Boolean);
var
  Cont: TPixieContainer;
  ForceLoad: Boolean;
begin
  inherited ComputeStyles(Recursive);

  if FSrc <> '' then
  begin
    Cont := GetDocContainer;
    if Cont <> nil then
    begin
      ForceLoad := (not FCss.CssWidth.IsPredefined) and
                   (not FCss.CssHeight.IsPredefined);
      Cont.LoadImage(FSrc, '', ForceLoad);
    end;
    EnsureAnimationCursor;
  end
  else
    ReleaseAnimationCursor;
end;

procedure TPixieElImage.GetContentSize(var Sz: TPixieSize;
  MaxWidth: TPixiePixel);
var
  Cont: TPixieContainer;
begin
  Sz.Width := 0;
  Sz.Height := 0;
  Cont := GetDocContainer;
  if Cont <> nil then
  begin
    Cont.GetImageSize(FSrc, '', Sz);
    if (Sz.Width = 0) and (Sz.Height = 0) and (FAlt <> '') and
       (FCss.Font <> 0) then
    begin
      Sz.Width := Cont.TextWidth(FAlt, FCss.Font);
      Sz.Height := FCss.FontMetrics.Height;
    end;
  end;
end;

procedure TPixieElImage.Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
  Clip: PPixiePosition; Ri: Pointer);
var
  RenderIt: TPixieRenderItem;
  P: TPixiePosition;
  Layer: TPixieBackgroundLayer;
  Cont: TPixieContainer;
  Sz: TPixieSize;
  FrameHandle: PtrUInt;
begin
  inherited Draw(Hdc, X, Y, Clip, Ri);

  RenderIt := TPixieRenderItem(Ri);
  P := RenderIt.Pos;
  P.X := P.X + X;
  P.Y := P.Y + Y;
  P.DoRound;

  if (Clip <> nil) and (not P.DoesIntersect(Clip^)) then
    Exit;
  if (P.Width <= 0) or (P.Height <= 0) then
    Exit;

  Cont := GetDocContainer;
  if Cont = nil then
    Exit;

  // Check whether the image is available
  Sz.Width := 0;
  Sz.Height := 0;
  Cont.GetImageSize(FSrc, '', Sz);

  if (Sz.Width > 0) or (Sz.Height > 0) then
  begin
    // Image loaded — draw it
    Layer.Init;
    Layer.ClipBox := P;
    Layer.OriginBox := P;
    Layer.BorderBox := P;
    Layer.BorderBox.X := Layer.BorderBox.X - RenderIt.GetPaddings.Left - RenderIt.GetBorders.Left;
    Layer.BorderBox.Y := Layer.BorderBox.Y - RenderIt.GetPaddings.Top - RenderIt.GetBorders.Top;
    Layer.BorderBox.Width := Layer.BorderBox.Width + RenderIt.GetPaddings.Width + RenderIt.GetBorders.Width;
    Layer.BorderBox.Height := Layer.BorderBox.Height + RenderIt.GetPaddings.Height + RenderIt.GetBorders.Height;
    Layer.Repeat_ := brNoRepeat;
    Layer.BorderRadius := FCss.CssBorders.Radius.CalcPercents(
      Layer.BorderBox.Width, Layer.BorderBox.Height);
    FrameHandle := 0;
    if FAnimCursor <> nil then
      FrameHandle := FAnimCursor.CurrentFrameHandle;
    Cont.DrawImage(Hdc, Layer, FSrc, '', FrameHandle);
  end
  else if (FAlt <> '') and (FCss.Font <> 0) then
  begin
    // Image missing — draw alt text
    Cont.DrawText(Hdc, FAlt, FCss.Font, FCss.Color, P);
  end;
end;

function TPixieElImage.CreateRenderItem(ParentRi: Pointer): Pointer;
var
  Ret: TPixieRenderImage;
begin
  Ret := TPixieRenderImage.Create(Self);
  Ret.SetParent(TPixieRenderItem(ParentRi));
  Result := Ret;
end;

function TPixieElImage.DumpGetName: string;
begin
  Result := 'img src="' + FSrc + '"';
end;

{ TPixieElVideo }

procedure TPixieElVideo.ParseAttributes;
begin
  inherited ParseAttributes;
  // <video>/<audio> carry no src attribute (sources live in <source> children);
  // use the poster image, when present, as the placeholder.
  if FSrc = '' then
    FSrc := GetAttr('poster');
end;

function TPixieElVideo.DumpGetName: string;
begin
  Result := GetTagName;
  if FSrc <> '' then
    Result := Result + ' poster="' + FSrc + '"';
end;

end.
