unit Pixie.ElRange;

// Owner-drawn, interactive <input type="range"> slider. Like the text input it
// is a focusable replaced element: clicks and drags along the track map to a
// value (snapped to step), and arrow / Home / End / PageUp-Down keys nudge it.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes,
  Pixie.Types, Pixie.WebColor,
  Pixie.Container,
  Pixie.Element, Pixie.HtmlTag;

type
  { TPixieElRange }

  TPixieElRange = class(TPixieHtmlTag)
  private
    FMin, FMax, FStep, FValue: Single;
    FStepAny: Boolean;
    procedure ClampValue;
    function ArrowStep: Single;
    procedure SetValueFromLocalX(LocalX: TPixiePixel);
    function LocalMouseX(DocX: TPixiePixel): TPixiePixel;
  public
    function IsReplaced: Boolean; override;
    function IsFocusable: Boolean; override;
    procedure ParseAttributes; override;
    procedure GetContentSize(var Sz: TPixieSize;
      MaxWidth: TPixiePixel); override;
    procedure Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
      Clip: PPixiePosition; Ri: Pointer); override;
    function OnLButtonDown: Boolean; override;
    function OnMouseDrag(X, Y: TPixiePixel): Boolean; override;
    function OnKeyDown(Key: Word; Shift: TShiftState): Boolean; override;
    function CreateRenderItem(ParentRi: Pointer): Pointer; override;
    function DumpGetName: string; override;
  end;

implementation

uses
  Math,
  Pixie.Utils, Pixie.StringId,
  Pixie.Canvas, Pixie.NativeContainer,
  Pixie.RenderItem, Pixie.RenderInput, Pixie.Document;

const
  RangeDefaultWidth = 160;
  RangeDefaultHeight = 16;

  VK_PRIOR = $21;
  VK_NEXT  = $22;
  VK_END   = $23;
  VK_HOME  = $24;
  VK_LEFT  = $25;
  VK_UP    = $26;
  VK_RIGHT = $27;
  VK_DOWN  = $28;

function GetCanvas(Tag: TPixieHtmlTag): TPixieCanvas;
var
  Cont: TPixieContainer;
begin
  Result := nil;
  Cont := Tag.GetDocContainer;
  if (Cont <> nil) and (Cont is TPixieNativeContainer) then
    Result := TPixieNativeContainer(Cont).Canvas;
end;

// Parse a numeric attribute, falling back to Default when absent/invalid.
function AttrFloat(Tag: TPixieHtmlTag; const Name: string;
  Default: Single): Single;
var
  Stripped: string;
  Code: Integer;
begin
  Result := Default;
  Stripped := PixieExtractFloat(PixieTrim(Tag.GetAttr(Name)));
  if Stripped = '' then Exit;
  System.Val(Stripped, Result, Code);
  if Code <> 0 then Result := Default;
end;

{ TPixieElRange }

function TPixieElRange.IsReplaced: Boolean;
begin
  Result := True;
end;

function TPixieElRange.IsFocusable: Boolean;
begin
  Result := True;
end;

procedure TPixieElRange.ParseAttributes;
begin
  if GetAttr('disabled', #1) <> #1 then
    SetPseudoClass(Ord(psid_disabled), True);

  FMin := AttrFloat(Self, 'min', 0);
  FMax := AttrFloat(Self, 'max', 100);
  if FMax < FMin then FMax := FMin;

  FStepAny := SameText(PixieTrim(GetAttr('step')), 'any');
  FStep := AttrFloat(Self, 'step', 1);
  if FStep <= 0 then FStep := 1;

  // value defaults to the midpoint of the range when the attribute is absent.
  FValue := AttrFloat(Self, 'value', FMin + (FMax - FMin) / 2);
  ClampValue;

  inherited ParseAttributes;
end;

procedure TPixieElRange.ClampValue;
begin
  if not FStepAny then
    FValue := FMin + Round((FValue - FMin) / FStep) * FStep;
  if FValue < FMin then FValue := FMin;
  if FValue > FMax then FValue := FMax;
end;

// Per-keypress increment: the step for a stepped slider, else a 1/100 nudge.
function TPixieElRange.ArrowStep: Single;
begin
  if FStepAny then
  begin
    Result := (FMax - FMin) / 100;
    if Result <= 0 then Result := 1;
  end
  else
    Result := FStep;
end;

function TPixieElRange.LocalMouseX(DocX: TPixiePixel): TPixiePixel;
var
  Ri: TPixieRenderItem;
begin
  Ri := TPixieRenderItem(GetRenderItem);
  if Ri = nil then
    Result := DocX
  else
    Result := DocX - Ri.AbsolutePos.X;
end;

procedure TPixieElRange.SetValueFromLocalX(LocalX: TPixiePixel);
var
  Ri: TPixieRenderItem;
  ThumbR, TrackW, Frac: TPixiePixel;
begin
  Ri := TPixieRenderItem(GetRenderItem);
  if Ri = nil then Exit;
  ThumbR := Ri.Pos.Height / 2;
  TrackW := Ri.Pos.Width - 2 * ThumbR;
  if TrackW <= 0 then Exit;
  Frac := (LocalX - ThumbR) / TrackW;
  if Frac < 0 then Frac := 0;
  if Frac > 1 then Frac := 1;
  FValue := FMin + Frac * (FMax - FMin);
  ClampValue;
end;

procedure TPixieElRange.GetContentSize(var Sz: TPixieSize;
  MaxWidth: TPixiePixel);
begin
  Sz.Width := RangeDefaultWidth;
  Sz.Height := RangeDefaultHeight;
end;

procedure TPixieElRange.Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
  Clip: PPixiePosition; Ri: Pointer);
var
  RenderIt: TPixieRenderItem;
  P: TPixiePosition;
  Cv: TPixieCanvas;
  CY, ThumbR, Th, TrackY, TrackLeft, TrackW, Frac, ThumbCX: TPixiePixel;
  TrackColor, FillColor, ThumbFill, ThumbBorder: TPixieWebColor;
  IsDisabled: Boolean;
begin
  inherited Draw(Hdc, X, Y, Clip, Ri);

  Cv := GetCanvas(Self);
  if Cv = nil then Exit;

  RenderIt := TPixieRenderItem(Ri);
  P := RenderIt.Pos;
  P.X := P.X + X;
  P.Y := P.Y + Y;
  if (Clip <> nil) and (not P.DoesIntersect(Clip^)) then Exit;
  if (P.Width <= 0) or (P.Height <= 0) then Exit;

  IsDisabled := IsEffectivelyDisabled;

  if IsDisabled then
  begin
    TrackColor := TPixieWebColor.Create(220, 220, 220);
    FillColor := TPixieWebColor.Create(190, 190, 190);
    ThumbFill := TPixieWebColor.Create(235, 235, 235);
    ThumbBorder := TPixieWebColor.Create(190, 190, 190);
  end
  else
  begin
    TrackColor := TPixieWebColor.Create(200, 200, 200);
    FillColor := TPixieWebColor.Create(0, 112, 201);
    ThumbFill := TPixieWebColor.Create(255, 255, 255);
    ThumbBorder := TPixieWebColor.Create(150, 150, 150);
  end;

  ThumbR := P.Height / 2;
  CY := P.Y + P.Height / 2;
  Th := Max(2, P.Height * 0.25);
  TrackY := CY - Th / 2;
  TrackLeft := P.X + ThumbR;
  TrackW := P.Width - 2 * ThumbR;
  if TrackW < 0 then TrackW := 0;

  if FMax > FMin then
    Frac := (FValue - FMin) / (FMax - FMin)
  else
    Frac := 0;
  if Frac < 0 then Frac := 0;
  if Frac > 1 then Frac := 1;
  ThumbCX := TrackLeft + Frac * TrackW;

  // Track, then the filled portion up to the thumb.
  Cv.FillRoundedRect(P.X, TrackY, P.Width, Th, Th / 2, TrackColor);
  if ThumbCX - P.X > 0 then
    Cv.FillRoundedRect(P.X, TrackY, ThumbCX - P.X, Th, Th / 2, FillColor);

  // Thumb: a bordered circle (border ring + inner fill).
  Cv.FillEllipse(ThumbCX - ThumbR, CY - ThumbR, ThumbR * 2, ThumbR * 2,
    ThumbBorder);
  if ThumbR > 1 then
    Cv.FillEllipse(ThumbCX - (ThumbR - 1), CY - (ThumbR - 1),
      (ThumbR - 1) * 2, (ThumbR - 1) * 2, ThumbFill);
end;

function TPixieElRange.OnLButtonDown: Boolean;
var
  Doc: TPixieDocument;
begin
  Result := False;
  if IsEffectivelyDisabled then Exit;
  if not (FDoc is TPixieDocument) then Exit;
  Doc := TPixieDocument(FDoc);
  Doc.SetFocus(Self);
  SetValueFromLocalX(LocalMouseX(Doc.LastMouseX));
  Result := True;
end;

function TPixieElRange.OnMouseDrag(X, Y: TPixiePixel): Boolean;
begin
  Result := False;
  if IsEffectivelyDisabled then Exit;
  SetValueFromLocalX(LocalMouseX(X));
  Result := True;
end;

function TPixieElRange.OnKeyDown(Key: Word; Shift: TShiftState): Boolean;
begin
  Result := False;
  if IsEffectivelyDisabled then Exit;
  case Key of
    VK_LEFT, VK_DOWN:  FValue := FValue - ArrowStep;
    VK_RIGHT, VK_UP:   FValue := FValue + ArrowStep;
    VK_NEXT:           FValue := FValue - (FMax - FMin) / 10;
    VK_PRIOR:          FValue := FValue + (FMax - FMin) / 10;
    VK_HOME:           FValue := FMin;
    VK_END:            FValue := FMax;
  else
    Exit(False);
  end;
  ClampValue;
  Result := True;
end;

function TPixieElRange.CreateRenderItem(ParentRi: Pointer): Pointer;
var
  Ret: TPixieRenderInput;
begin
  Ret := TPixieRenderInput.Create(Self);
  Ret.SetParent(TPixieRenderItem(ParentRi));
  Result := Ret;
end;

function TPixieElRange.DumpGetName: string;
begin
  Result := 'input type="range"';
end;

end.
