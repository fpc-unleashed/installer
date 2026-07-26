unit Pixie.ElInput;

// Owner-drawn <input type="checkbox">, <input type="radio"> and <button>
// elements. All are replaced elements that draw their own visuals.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils,
  Pixie.Types, Pixie.WebColor,
  Pixie.Container,
  Pixie.Element, Pixie.HtmlTag;

type
  { TPixieElCheckbox }

  TPixieElCheckbox = class(TPixieHtmlTag)
  private
    FChecked: Boolean;
  public
    constructor Create(ADoc: TObject);

    procedure Toggle;
    function IsReplaced: Boolean; override;
    procedure ParseAttributes; override;
    procedure GetContentSize(var Sz: TPixieSize;
      MaxWidth: TPixiePixel); override;
    procedure Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
      Clip: PPixiePosition; Ri: Pointer); override;
    procedure OnClick; override;
    function CreateRenderItem(ParentRi: Pointer): Pointer; override;
    function DumpGetName: string; override;

    property Checked: Boolean read FChecked;
  end;

  { TPixieElLabel }

  TPixieElLabel = class(TPixieHtmlTag)
  public
    procedure OnClick; override;
  end;

  { TPixieElRadio }

  TPixieElRadio = class(TPixieHtmlTag)
  private
    FChecked: Boolean;
    procedure UncheckSiblings;
  public
    constructor Create(ADoc: TObject);

    procedure Toggle;
    function IsReplaced: Boolean; override;
    procedure ParseAttributes; override;
    procedure GetContentSize(var Sz: TPixieSize;
      MaxWidth: TPixiePixel); override;
    procedure Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
      Clip: PPixiePosition; Ri: Pointer); override;
    procedure OnClick; override;
    function CreateRenderItem(ParentRi: Pointer): Pointer; override;
    function DumpGetName: string; override;

    property Checked: Boolean read FChecked;
  end;

  { TPixieElButton }

  TPixieElButton = class(TPixieHtmlTag)
  public
    function IsReplaced: Boolean; override;
    procedure ParseAttributes; override;
    procedure GetContentSize(var Sz: TPixieSize;
      MaxWidth: TPixiePixel); override;
    procedure Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
      Clip: PPixiePosition; Ri: Pointer); override;
    procedure OnClick; override;
    function CreateRenderItem(ParentRi: Pointer): Pointer; override;
    function DumpGetName: string; override;
  end;

  { TPixieElInputButton — <input type="submit|button|reset"> }

  TPixieElInputButton = class(TPixieElButton)
  public
    procedure GetText(var Text: string); override;
  end;

implementation

uses
  Math,
  Pixie.StringId, Pixie.Style, Pixie.Borders, Pixie.Background,
  Pixie.Canvas, Pixie.NativeContainer,
  Pixie.RenderItem, Pixie.RenderInput,
  Pixie.Document;

const
  InputIntrinsicSize = 16;

var
  InputClickInProgress: Boolean = False;

function FindFirstInput(El: TPixieElement): TPixieElement;
var
  I: Integer;
  Ch, Found: TPixieElement;
begin
  Result := nil;
  for I := 0 to El.Children.Count - 1 do
  begin
    Ch := El.Children[I];
    if (Ch is TPixieElCheckbox) or (Ch is TPixieElRadio) then
      Exit(Ch);
    Found := FindFirstInput(Ch);
    if Found <> nil then
      Exit(Found);
  end;
end;

function GetCanvas(Tag: TPixieHtmlTag): TPixieCanvas;
var
  Cont: TPixieContainer;
begin
  Result := nil;
  Cont := Tag.GetDocContainer;
  if (Cont <> nil) and (Cont is TPixieNativeContainer) then
    Result := TPixieNativeContainer(Cont).Canvas;
end;

{ TPixieElCheckbox }

constructor TPixieElCheckbox.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
  FChecked := False;
end;

function TPixieElCheckbox.IsReplaced: Boolean;
begin
  Result := True;
end;

procedure TPixieElCheckbox.ParseAttributes;
begin
  FChecked := GetAttr('checked', #1) <> #1;
  if FChecked then
    SetPseudoClass(Ord(psid_checked), True);

  if GetAttr('disabled', #1) <> #1 then
    SetPseudoClass(Ord(psid_disabled), True);

  inherited ParseAttributes;
end;

procedure TPixieElCheckbox.GetContentSize(var Sz: TPixieSize;
  MaxWidth: TPixiePixel);
begin
  Sz.Width := InputIntrinsicSize;
  Sz.Height := InputIntrinsicSize;
end;

procedure TPixieElCheckbox.Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
  Clip: PPixiePosition; Ri: Pointer);
var
  RenderIt: TPixieRenderItem;
  P: TPixiePosition;
  Cv: TPixieCanvas;
  FillColor, StrokeColor: TPixieWebColor;
  CX, CY, W, H, S, Inset: Single;
  Rad: TPixieBorderRadiuses;
  IsDisabled: Boolean;
begin
  inherited Draw(Hdc, X, Y, Clip, Ri);

  Cv := GetCanvas(Self);
  if Cv = nil then Exit;

  RenderIt := TPixieRenderItem(Ri);
  P := RenderIt.Pos;
  P.X := P.X + X;
  P.Y := P.Y + Y;

  if (Clip <> nil) and (not P.DoesIntersect(Clip^)) then
    Exit;
  if (P.Width <= 0) or (P.Height <= 0) then
    Exit;

  CX := P.X;
  CY := P.Y;
  W := P.Width;
  H := P.Height;
  S := W / 24; // scale factor from 24x24 viewBox

  IsDisabled := IsEffectivelyDisabled;

  if FChecked then
  begin
    if IsDisabled then
    begin
      FillColor := TPixieWebColor.Create(140, 140, 140);
      StrokeColor := TPixieWebColor.Create(120, 120, 120);
    end
    else
    begin
      FillColor := TPixieWebColor.Create(0, 112, 201);   // #0070c9
      StrokeColor := TPixieWebColor.Create(0, 97, 169);   // #0061a9
    end;
  end
  else
  begin
    if IsDisabled then
    begin
      FillColor := TPixieWebColor.Create(160, 160, 160);
      StrokeColor := TPixieWebColor.Create(140, 140, 140);
    end
    else
    begin
      FillColor := TPixieWebColor.Create(192, 192, 192);  // #c0c0c0
      StrokeColor := TPixieWebColor.Create(160, 160, 160); // #a0a0a0
    end;
  end;

  Inset := 3 * S;

  // Stroke rect (slightly larger)
  Rad.Init;
  Rad.TopLeftX := 4 * S; Rad.TopLeftY := 4 * S;
  Rad.TopRightX := 4 * S; Rad.TopRightY := 4 * S;
  Rad.BottomRightX := 4 * S; Rad.BottomRightY := 4 * S;
  Rad.BottomLeftX := 4 * S; Rad.BottomLeftY := 4 * S;
  Cv.FillRoundedRect(CX + Inset - S * 0.5, CY + Inset - S * 0.5,
    W - 2 * Inset + S, H - 2 * Inset + S, Rad, StrokeColor);

  // Fill rect (inset by stroke width)
  Cv.FillRoundedRect(CX + Inset + S * 0.5, CY + Inset + S * 0.5,
    W - 2 * Inset - S, H - 2 * Inset - S, Rad, FillColor);

  // Checkmark when checked (white polyline: 7,12 -> 10,15 -> 17,8)
  if FChecked then
  begin
    Cv.StrokePolyline([CX + 7 * S, CY + 12 * S,
                        CX + 10 * S, CY + 15 * S,
                        CX + 17 * S, CY + 8 * S],
                       TPixieWebColor.Create(255, 255, 255), 2 * S);
  end;
end;

procedure TPixieElCheckbox.Toggle;
var
  IsDisabled: Boolean;
begin
  IsDisabled := IsEffectivelyDisabled;
  if not IsDisabled then
  begin
    FChecked := not FChecked;
    SetPseudoClass(Ord(psid_checked), FChecked);
  end;
end;

procedure TPixieElCheckbox.OnClick;
begin
  Toggle;
  InputClickInProgress := True;
  try
    inherited OnClick;
  finally
    InputClickInProgress := False;
  end;
end;

function TPixieElCheckbox.CreateRenderItem(ParentRi: Pointer): Pointer;
var
  Ret: TPixieRenderInput;
begin
  Ret := TPixieRenderInput.Create(Self);
  Ret.SetParent(TPixieRenderItem(ParentRi));
  Result := Ret;
end;

function TPixieElCheckbox.DumpGetName: string;
begin
  Result := 'input type="checkbox"';
  if FChecked then
    Result := Result + ' checked';
end;

{ TPixieElLabel }

procedure TPixieElLabel.OnClick;
var
  Input: TPixieElement;
  ForId: string;
begin
  if not InputClickInProgress then
  begin
    // <label for="..."> targets the (sibling/cousin) input by id;
    // descendant lookup is only the fallback.
    Input := nil;
    ForId := GetAttr('for', '');
    if (ForId <> '') and (FDoc is TPixieDocument) then
      Input := TPixieDocument(FDoc).GetElementById(ForId);
    if Input = nil then
      Input := FindFirstInput(Self);
    if Input is TPixieElCheckbox then
      TPixieElCheckbox(Input).Toggle
    else if Input is TPixieElRadio then
      TPixieElRadio(Input).Toggle;
  end;
  inherited OnClick;
end;

{ TPixieElRadio }

constructor TPixieElRadio.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
  FChecked := False;
end;

function TPixieElRadio.IsReplaced: Boolean;
begin
  Result := True;
end;

procedure TPixieElRadio.ParseAttributes;
begin
  FChecked := GetAttr('checked', #1) <> #1;
  if FChecked then
    SetPseudoClass(Ord(psid_checked), True);

  if GetAttr('disabled', #1) <> #1 then
    SetPseudoClass(Ord(psid_disabled), True);

  inherited ParseAttributes;
end;

procedure TPixieElRadio.GetContentSize(var Sz: TPixieSize;
  MaxWidth: TPixiePixel);
begin
  Sz.Width := InputIntrinsicSize;
  Sz.Height := InputIntrinsicSize;
end;

procedure TPixieElRadio.Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
  Clip: PPixiePosition; Ri: Pointer);
var
  RenderIt: TPixieRenderItem;
  P: TPixiePosition;
  Cv: TPixieCanvas;
  FillColor, StrokeColor: TPixieWebColor;
  CX, CY, W, H, S, R: Single;
  IsDisabled: Boolean;
begin
  inherited Draw(Hdc, X, Y, Clip, Ri);

  Cv := GetCanvas(Self);
  if Cv = nil then Exit;

  RenderIt := TPixieRenderItem(Ri);
  P := RenderIt.Pos;
  P.X := P.X + X;
  P.Y := P.Y + Y;

  if (Clip <> nil) and (not P.DoesIntersect(Clip^)) then
    Exit;
  if (P.Width <= 0) or (P.Height <= 0) then
    Exit;

  CX := P.X;
  CY := P.Y;
  W := P.Width;
  H := P.Height;
  S := W / 24; // scale factor from 24x24 viewBox

  IsDisabled := IsEffectivelyDisabled;

  if FChecked then
  begin
    if IsDisabled then
    begin
      FillColor := TPixieWebColor.Create(140, 140, 140);
      StrokeColor := TPixieWebColor.Create(120, 120, 120);
    end
    else
    begin
      FillColor := TPixieWebColor.Create(0, 112, 201);   // #0070c9
      StrokeColor := TPixieWebColor.Create(0, 97, 169);   // #0061a9
    end;
  end
  else
  begin
    if IsDisabled then
    begin
      FillColor := TPixieWebColor.Create(160, 160, 160);
      StrokeColor := TPixieWebColor.Create(140, 140, 140);
    end
    else
    begin
      FillColor := TPixieWebColor.Create(192, 192, 192);  // #c0c0c0
      StrokeColor := TPixieWebColor.Create(160, 160, 160); // #a0a0a0
    end;
  end;

  // Stroke circle (radius 9.5 in viewBox units)
  R := 9.5 * S;
  Cv.FillEllipse(CX + W / 2 - R, CY + H / 2 - R, R * 2, R * 2, StrokeColor);

  // Fill circle (radius 8.5 in viewBox units)
  R := 8.5 * S;
  Cv.FillEllipse(CX + W / 2 - R, CY + H / 2 - R, R * 2, R * 2, FillColor);

  // White inner dot when checked (radius 4 in viewBox units)
  if FChecked then
  begin
    R := 4 * S;
    Cv.FillEllipse(CX + W / 2 - R, CY + H / 2 - R, R * 2, R * 2,
      TPixieWebColor.Create(255, 255, 255));
  end;
end;

procedure UncheckRadiosInTree(Root, Skip: TPixieElement;
  const GroupName: string);
var
  I: Integer;
  Ch: TPixieElement;
begin
  for I := 0 to Root.Children.Count - 1 do
  begin
    Ch := Root.Children[I];
    if (Ch <> Skip) and (Ch is TPixieElRadio) then
    begin
      if (GroupName = '') or
         (TPixieElRadio(Ch).GetAttr('name') = GroupName) then
      begin
        TPixieElRadio(Ch).FChecked := False;
        Ch.SetPseudoClass(Ord(psid_checked), False);
      end;
    end;
    UncheckRadiosInTree(Ch, Skip, GroupName);
  end;
end;

procedure TPixieElRadio.UncheckSiblings;
var
  Root: TPixieElement;
  MyName: string;
begin
  // Walk up to the document root
  Root := Self;
  while Root.Parent <> nil do
    Root := Root.Parent;

  MyName := GetAttr('name');
  UncheckRadiosInTree(Root, Self, MyName);
end;

procedure TPixieElRadio.Toggle;
var
  IsDisabled: Boolean;
begin
  IsDisabled := IsEffectivelyDisabled;
  if (not IsDisabled) and (not FChecked) then
  begin
    UncheckSiblings;
    FChecked := True;
    SetPseudoClass(Ord(psid_checked), True);
  end;
end;

procedure TPixieElRadio.OnClick;
begin
  Toggle;
  InputClickInProgress := True;
  try
    inherited OnClick;
  finally
    InputClickInProgress := False;
  end;
end;

function TPixieElRadio.CreateRenderItem(ParentRi: Pointer): Pointer;
var
  Ret: TPixieRenderInput;
begin
  Ret := TPixieRenderInput.Create(Self);
  Ret.SetParent(TPixieRenderItem(ParentRi));
  Result := Ret;
end;

function TPixieElRadio.DumpGetName: string;
begin
  Result := 'input type="radio"';
  if FChecked then
    Result := Result + ' checked';
end;

{ TPixieElButton }

function TPixieElButton.IsReplaced: Boolean;
begin
  Result := True;
end;

procedure TPixieElButton.ParseAttributes;
begin
  if GetAttr('disabled', #1) <> #1 then
    SetPseudoClass(Ord(psid_disabled), True);

  inherited ParseAttributes;
end;

procedure TPixieElButton.GetContentSize(var Sz: TPixieSize;
  MaxWidth: TPixiePixel);
var
  Cv: TPixieCanvas;
  Cont: TPixieContainer;
  Label_: string;
  TextW: TPixiePixel;
begin
  Label_ := '';
  GetText(Label_);
  Label_ := Trim(Label_);
  if Label_ = '' then
    Label_ := 'Button';

  if FCss.TextTransform <> ttNone then
  begin
    Cont := GetDocContainer;
    if Cont <> nil then
      Cont.TransformText(Label_, FCss.TextTransform);
  end;

  Cv := GetCanvas(Self);
  if Cv <> nil then
    TextW := Cv.MeasureText(Label_, FCss.Font)
  else
    TextW := Length(Label_) * FCss.FontMetrics.ChWidth;

  Sz.Width := TextW;
  Sz.Height := FCss.IntrinsicLineHeight;
end;

procedure TPixieElButton.Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
  Clip: PPixiePosition; Ri: Pointer);
var
  RenderIt: TPixieRenderItem;
  P: TPixiePosition;
  Pad: TPixieMargins;
  Cv: TPixieCanvas;
  Cont: TPixieContainer;
  FillColor, StrokeColor, TextColor: TPixieWebColor;
  Rad: TPixieBorderRadiuses;
  BorderW: TPixiePixel;
  IsDisabled, IsActive, IsHover: Boolean;
  HasCssBorder, HasCssBg: Boolean;
  Label_: string;
  TextW, TextX, TextY: TPixiePixel;
  BX, BY, BW, BH: TPixiePixel;
begin
  inherited Draw(Hdc, X, Y, Clip, Ri);

  Cv := GetCanvas(Self);
  if Cv = nil then Exit;

  RenderIt := TPixieRenderItem(Ri);
  P := RenderIt.Pos;
  P.X := P.X + X;
  P.Y := P.Y + Y;

  if (Clip <> nil) and (not P.DoesIntersect(Clip^)) then
    Exit;
  if (P.Width <= 0) or (P.Height <= 0) then
    Exit;

  // Expand from content box to padding box for background drawing
  Pad := RenderIt.GetPaddings;
  BX := P.X - Pad.Left;
  BY := P.Y - Pad.Top;
  BW := P.Width + Pad.Left + Pad.Right;
  BH := P.Height + Pad.Top + Pad.Bottom;

  IsDisabled := IsEffectivelyDisabled;
  IsActive := FPseudoClasses.IndexOf(Ord(psid_active)) >= 0;
  IsHover := FPseudoClasses.IndexOf(Ord(psid_hover)) >= 0;

  // Detect explicit CSS border/background — check both computed values
  // and whether the cascade set the property at all (catches border:0
  // and background:transparent which produce initial-like values).
  HasCssBorder := (FCss.CssBorders.Left.Style > bsHidden) or
    (Style.GetProperty(Ord(psid_border_left_style)).Kind <> pkInvalid);
  HasCssBg := (FCss.Bg.Color.Alpha > 0) or
    (Style.GetProperty(Ord(psid_background_color)).Kind <> pkInvalid);

  // Determine colours — CSS overrides when available
  if IsDisabled then
  begin
    if HasCssBg then
      FillColor := FCss.Bg.Color
    else
      FillColor := TPixieWebColor.Create(239, 239, 239);
    if HasCssBorder then
      StrokeColor := FCss.CssBorders.Left.Color
    else
      StrokeColor := TPixieWebColor.Create(206, 206, 206);
    TextColor := TPixieWebColor.Create(169, 169, 169);
  end
  else if HasCssBg or HasCssBorder then
  begin
    // CSS-styled button
    if HasCssBg then
      FillColor := FCss.Bg.Color
    else
      FillColor := TPixieWebColor.Create(0, 112, 201);
    if HasCssBorder then
      StrokeColor := FCss.CssBorders.Left.Color
    else
      StrokeColor := FillColor;
    TextColor := FCss.Color;
  end
  else if IsActive then
  begin
    FillColor := TPixieWebColor.Create(200, 200, 200);
    StrokeColor := TPixieWebColor.Create(150, 150, 150);
    TextColor := TPixieWebColor.Create(0, 0, 0);
  end
  else if IsHover then
  begin
    FillColor := TPixieWebColor.Create(228, 228, 228);
    StrokeColor := TPixieWebColor.Create(170, 170, 170);
    TextColor := TPixieWebColor.Create(0, 0, 0);
  end
  else
  begin
    FillColor := TPixieWebColor.Create(239, 239, 239);
    StrokeColor := TPixieWebColor.Create(185, 185, 185);
    TextColor := TPixieWebColor.Create(0, 0, 0);
  end;

  // Author `color` wins for the text even without an explicit background or
  // border (browsers honour it on the native button chrome). Disabled buttons
  // keep the greyed-out system colour set above.
  if not IsDisabled then
    TextColor := FCss.Color;

  // Border radius — CSS or default 4px
  if not FCss.CssBorders.Radius.TopLeftX.IsPredefined then
    Rad := FCss.CssBorders.Radius.CalcPercents(BW, BH)
  else
  begin
    Rad.Init;
    Rad.TopLeftX := 2; Rad.TopLeftY := 2;
    Rad.TopRightX := 2; Rad.TopRightY := 2;
    Rad.BottomRightX := 2; Rad.BottomRightY := 2;
    Rad.BottomLeftX := 2; Rad.BottomLeftY := 2;
  end;

  // Border width
  if HasCssBorder then
    BorderW := Max(1, FCss.CssBorders.Left.Width.Val)
  else
    BorderW := 1;

  // Draw border + fill — skip when CSS handles it via DrawBackground
  if not (HasCssBg or HasCssBorder) or IsDisabled then
  begin
    Cv.FillRoundedRect(BX, BY, BW, BH, Rad, StrokeColor);
    Cv.FillRoundedRect(BX + BorderW, BY + BorderW,
      BW - BorderW * 2, BH - BorderW * 2, Rad, FillColor);
  end;

  // Text centred in the full padding box
  Label_ := '';
  GetText(Label_);
  Label_ := Trim(Label_);
  // Only use default "Button" label for the native appearance
  if (Label_ = '') and not (HasCssBg or HasCssBorder) then
    Label_ := 'Button';

  if (Label_ <> '') and (FCss.TextTransform <> ttNone) then
  begin
    Cont := GetDocContainer;
    if Cont <> nil then
      Cont.TransformText(Label_, FCss.TextTransform);
  end;

  if Label_ <> '' then
  begin
    TextW := Cv.MeasureText(Label_, FCss.Font);
    // Buttons centre their label by default, but honour an explicit
    // text-align set on the element (within the content box).
    if Style.GetProperty(Ord(psid_text_align)).Kind <> pkInvalid then
    begin
      case FCss.TextAlign of
        taRight, taBlockRight: TextX := P.X + P.Width - TextW;
        taLeft, taBlockLeft, taJustify: TextX := P.X;
      else
        TextX := BX + (BW - TextW) / 2;
      end;
    end
    else
      TextX := BX + (BW - TextW) / 2;
    // Honour text-indent — used as the a11y hack for icon-only buttons.
    TextX := TextX + FCss.CssTextIndent.CalcPercent(BW);
    TextY := BY + (BH - FCss.FontMetrics.Height) / 2;

    Cv.DrawText(Label_, FCss.Font, TextColor,
      TextX, TextY, BW, BH);
  end;
end;

procedure TPixieElButton.OnClick;
var
  IsDisabled: Boolean;
begin
  IsDisabled := IsEffectivelyDisabled;
  if not IsDisabled then
    inherited OnClick;
end;

function TPixieElButton.CreateRenderItem(ParentRi: Pointer): Pointer;
var
  Ret: TPixieRenderInput;
begin
  Ret := TPixieRenderInput.Create(Self);
  Ret.SetParent(TPixieRenderItem(ParentRi));
  Result := Ret;
end;

function TPixieElButton.DumpGetName: string;
begin
  Result := 'button';
end;

{ TPixieElInputButton }

procedure TPixieElInputButton.GetText(var Text: string);
const
  NoValue = #1;
var
  Val: string;
begin
  Val := GetAttr('value', NoValue);
  if Val <> NoValue then
    Text := Text + Val  // value="" -> empty label, value="Go" -> "Go"
  else
  begin
    Val := GetAttr('type');
    if SameText(Val, 'reset') then
      Text := Text + 'Reset'
    else if not SameText(Val, 'button') then
      Text := Text + 'Submit';
  end;
end;

end.
