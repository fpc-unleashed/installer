unit Pixie.TagBar.Render;

// Standalone pill measurement, drawing, and hit-testing.
// No LCL dependency — works with any TPixieCanvas backend.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Math,
  Pixie.Types, Pixie.WebColor, Pixie.Borders,
  Pixie.Canvas, Pixie.TagBar.Colors;

type
  TPixieTagShape = (tsRect, tsRoundedRect, tsPill);

  TPixieTagPillState = (
    tpsRest, tpsHover, tpsPress,
    tpsChecked, tpsCheckedHover, tpsCheckedPress,
    tpsInactive, tpsEditing
  );

  TPixieTagPillOption = (tpoShowDismiss, tpoIsAddButton, tpoEditing,
    tpoShowColorSwatch);
  TPixieTagPillOptions = set of TPixieTagPillOption;

  TPixieTagHitZone = (thzNone, thzPill, thzLeadIcon, thzDismiss);

  TPixieTagPillMetrics = record
    TotalWidth: Single;
    TotalHeight: Single;
    TextX: Single;
    TextWidth: Single;
    SepX: Single;            // Separator X offset (0 = no split)
    SuffixTextX: Single;     // Suffix text X offset
    SuffixTextWidth: Single; // Suffix text width
    PrefixText: string;      // Prefix part (before colon), empty if no split
    SuffixText: string;      // Suffix part (after colon), empty if no split
    LeadIconRect: TPixiePosition;
    TrailIconRect: TPixiePosition;
    DismissRect: TPixiePosition;
    ContentRect: TPixiePosition;
  end;

function MeasureTagPill(
  Canvas: TPixieCanvas;
  Font: TPixieFontHandle;
  const Text: string;
  const LeadIcon: string;
  const TrailIcon: string;
  PillHeight: Single;
  Options: TPixieTagPillOptions;
  Shape: TPixieTagShape = tsPill): TPixieTagPillMetrics;

procedure DrawTagPill(
  Canvas: TPixieCanvas;
  Font: TPixieFontHandle;
  const FontMetrics: TPixieFontMetrics;
  const Text: string;
  const LeadIcon: string;
  const TrailIcon: string;
  X, Y, PillHeight: Single;
  const Base: TPixieWebColor;
  const BgColor: TPixieWebColor;
  State: TPixieTagPillState;
  Shape: TPixieTagShape;
  Options: TPixieTagPillOptions;
  const Metrics: TPixieTagPillMetrics);

function HitTestTagPill(LocalX, LocalY: Single;
  const M: TPixieTagPillMetrics): TPixieTagHitZone;

implementation

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

function MeasureTagPill(
  Canvas: TPixieCanvas;
  Font: TPixieFontHandle;
  const Text: string;
  const LeadIcon: string;
  const TrailIcon: string;
  PillHeight: Single;
  Options: TPixieTagPillOptions;
  Shape: TPixieTagShape): TPixieTagPillMetrics;
var
  PadH, DismW, Gap, InnerPad, CurX, TextW, LeadW, TrailW: Single;
  Part1W, Part2W: Single;
  ColonPos: Integer;
  Part1, Part2: string;
  HasColon: Boolean;
begin
  Result.LeadIconRect.Clear;
  Result.TrailIconRect.Clear;
  Result.DismissRect.Clear;
  Result.SepX := 0;
  Result.SuffixTextX := 0;
  Result.SuffixTextWidth := 0;
  Result.PrefixText := '';
  Result.SuffixText := '';

  if tpoIsAddButton in Options then
  begin
    TextW := Canvas.MeasureText(Text, Font);
    if Shape = tsPill then
    begin
      // Circle: width = height, text centred
      Result.TotalWidth := PillHeight;
      Result.TextX := (PillHeight - TextW) / 2;
    end
    else
    begin
      PadH := PillHeight * 0.25;
      Result.TotalWidth := PadH + TextW + PadH;
      Result.TextX := PadH;
    end;
    Result.TextWidth := TextW;
    Result.TotalHeight := PillHeight;
    Result.ContentRect := TPixiePosition.Create(0, 0,
      Result.TotalWidth, PillHeight);
    Exit;
  end;

  PadH  := PillHeight * 0.35;
  DismW := PillHeight * 0.55;
  Gap   := PillHeight * 0.2;

  // Detect colon split (suppressed during editing)
  ColonPos := 0;
  HasColon := False;
  if not (tpoEditing in Options) then
    ColonPos := Pos(':', Text);
  if ColonPos > 1 then
  begin
    Part1 := Trim(Copy(Text, 1, ColonPos - 1));
    Part2 := Trim(Copy(Text, ColonPos + 1, MaxInt));
    HasColon := (Part1 <> '') and (Part2 <> '');
  end;

  CurX := PadH;

  // Lead icon or code-drawn colour swatch
  if LeadIcon <> '' then
  begin
    LeadW := Canvas.MeasureText(LeadIcon, Font);
    Result.LeadIconRect := TPixiePosition.Create(
      CurX, 0, LeadW, PillHeight);
    CurX := CurX + LeadW + Gap;
  end
  else if tpoShowColorSwatch in Options then
  begin
    LeadW := PillHeight * 0.5;
    Result.LeadIconRect := TPixiePosition.Create(
      CurX, 0, LeadW, PillHeight);
    CurX := CurX + LeadW + Gap;
  end;

  if HasColon then
  begin
    // Two-part measurement with inner padding
    Part1W := Canvas.MeasureText(Part1, Font);
    Part2W := Canvas.MeasureText(Part2, Font);
    InnerPad := PadH * 0.7;

    Result.TextX := CurX;
    Result.TextWidth := Part1W;
    CurX := CurX + Part1W + InnerPad;

    // Separator position
    Result.SepX := CurX;
    CurX := CurX + InnerPad;

    Result.SuffixTextX := CurX;
    Result.SuffixTextWidth := Part2W;
    Result.PrefixText := Part1;
    Result.SuffixText := Part2;
    CurX := CurX + Part2W;
  end
  else
  begin
    // Single-part measurement (unchanged)
    TextW := Canvas.MeasureText(Text, Font);
    Result.TextX := CurX;
    Result.TextWidth := TextW;
    CurX := CurX + TextW;
  end;

  // Trail icon
  if TrailIcon <> '' then
  begin
    CurX := CurX + Gap;
    TrailW := Canvas.MeasureText(TrailIcon, Font);
    Result.TrailIconRect := TPixiePosition.Create(
      CurX, 0, TrailW, PillHeight);
    CurX := CurX + TrailW;
  end;

  if tpoShowDismiss in Options then
  begin
    CurX := CurX + Gap;
    Result.DismissRect := TPixiePosition.Create(
      CurX, 0, DismW, PillHeight);
    CurX := CurX + DismW;
  end;

  CurX := CurX + PadH;
  Result.TotalWidth := CurX;
  Result.TotalHeight := PillHeight;
  Result.ContentRect := TPixiePosition.Create(0, 0,
    Result.TotalWidth, PillHeight);
end;

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

procedure DrawTagPill(
  Canvas: TPixieCanvas;
  Font: TPixieFontHandle;
  const FontMetrics: TPixieFontMetrics;
  const Text: string;
  const LeadIcon: string;
  const TrailIcon: string;
  X, Y, PillHeight: Single;
  const Base: TPixieWebColor;
  const BgColor: TPixieWebColor;
  State: TPixieTagPillState;
  Shape: TPixieTagShape;
  Options: TPixieTagPillOptions;
  const Metrics: TPixieTagPillMetrics);
var
  FillColor, SufFillColor, TxtColor, SufTxtColor, BrdColor: TPixieWebColor;
  Radius, InnerRadius, LeftInner, RightInner, RightInner2: TPixieBorderRadiuses;
  Bw, R, Ri, Ri2, TextY, Arm, Cx, Cy, SepAbs: Single;
  SwSize, SwX, SwY, SwR: Single;
  IsChecked, IsOutlined, HasSuffix: Boolean;
begin
  // Compute colours from state
  IsChecked := State in [tpsChecked, tpsCheckedHover, tpsCheckedPress];
  IsOutlined := State in [tpsRest, tpsHover, tpsPress];
  HasSuffix := Metrics.SepX > 0;
  // Outlined-at-rest single-part pills show through to the bar background;
  // skip the HSL round-trip in PixieTagRestFill since we'd overwrite it.
  // Split (HasSuffix) pills keep the rest tint on the prefix half so the
  // key:value visual stays legible.
  if IsOutlined and (State = tpsRest) and not HasSuffix then
    FillColor := BgColor
  else
    case State of
      tpsRest:         FillColor := PixieTagRestFill(Base);
      tpsHover:        FillColor := PixieTagHoverFill(Base);
      tpsPress:        FillColor := PixieTagPressFill(Base);
      tpsChecked:      FillColor := PixieTagCheckedFill(Base);
      tpsCheckedHover: FillColor := PixieTagBlend(Base, TPixieWebColor.White, 0.15);
      tpsCheckedPress: FillColor := PixieTagBlend(Base, TPixieWebColor.Black, 0.15);
      tpsInactive:     FillColor := PixieTagInactiveFill(Base);
      tpsEditing:      FillColor := PixieTagRestFill(Base);
    end;
  TxtColor := PixieTagTextColor(Base, IsChecked);
  if IsOutlined then
    BrdColor := PixieTagOutlineColor(Base)
  else
    BrdColor := PixieTagBorderColor(Base);

  // Compute radii from shape
  case Shape of
    tsRect:        R := 0;
    tsRoundedRect: R := PillHeight * 0.2;
    tsPill:        R := PillHeight / 2;
  end;

  Radius.TopLeftX := R;     Radius.TopLeftY := R;
  Radius.TopRightX := R;    Radius.TopRightY := R;
  Radius.BottomRightX := R; Radius.BottomRightY := R;
  Radius.BottomLeftX := R;  Radius.BottomLeftY := R;

  if IsOutlined then
    Bw := 1.5
  else
    Bw := 1.0;
  Ri := Max(R - Bw, 0);

  // Border (outer rounded rect — always one continuous shape)
  Canvas.FillRoundedRect(X, Y,
    Metrics.TotalWidth, PillHeight, Radius, BrdColor);

  if HasSuffix then
  begin
    SepAbs := Metrics.SepX; // relative to pill left

    // Suffix colours: unfilled (background) with dark text
    SufFillColor := TPixieWebColor.White;
    SufTxtColor := PixieTagTextColor(Base, False);

    // Left half fill: rounded left corners, square right corners
    LeftInner.TopLeftX := Ri;     LeftInner.TopLeftY := Ri;
    LeftInner.BottomLeftX := Ri;  LeftInner.BottomLeftY := Ri;
    LeftInner.TopRightX := 0;     LeftInner.TopRightY := 0;
    LeftInner.BottomRightX := 0;  LeftInner.BottomRightY := 0;
    Canvas.FillRoundedRect(X + Bw, Y + Bw,
      SepAbs - Bw, PillHeight - 2 * Bw,
      LeftInner, FillColor);

    // Right half: square left corners, rounded right corners
    RightInner.TopLeftX := 0;      RightInner.TopLeftY := 0;
    RightInner.BottomLeftX := 0;   RightInner.BottomLeftY := 0;
    RightInner.TopRightX := Ri;    RightInner.TopRightY := Ri;
    RightInner.BottomRightX := Ri; RightInner.BottomRightY := Ri;

    if IsChecked then
    begin
      // Checked: inner coloured border + hollow centre
      // Draw fill colour as inner border
      Canvas.FillRoundedRect(X + SepAbs, Y + Bw,
        Metrics.TotalWidth - SepAbs - Bw, PillHeight - 2 * Bw,
        RightInner, FillColor);
      // Hollow interior inset by inner border width
      Ri2 := Max(Ri - 2 * Bw, 0);
      RightInner2.TopLeftX := 0;       RightInner2.TopLeftY := 0;
      RightInner2.BottomLeftX := 0;    RightInner2.BottomLeftY := 0;
      RightInner2.TopRightX := Ri2;    RightInner2.TopRightY := Ri2;
      RightInner2.BottomRightX := Ri2; RightInner2.BottomRightY := Ri2;
      Canvas.FillRoundedRect(X + SepAbs, Y + 3 * Bw,
        Metrics.TotalWidth - SepAbs - 3 * Bw, PillHeight - 6 * Bw,
        RightInner2, SufFillColor);
    end
    else
      // Unchecked: plain hollow
      Canvas.FillRoundedRect(X + SepAbs, Y + Bw,
        Metrics.TotalWidth - SepAbs - Bw, PillHeight - 2 * Bw,
        RightInner, SufFillColor);
  end
  else
  begin
    InnerRadius.TopLeftX := Ri;     InnerRadius.TopLeftY := Ri;
    InnerRadius.TopRightX := Ri;    InnerRadius.TopRightY := Ri;
    InnerRadius.BottomRightX := Ri; InnerRadius.BottomRightY := Ri;
    InnerRadius.BottomLeftX := Ri;  InnerRadius.BottomLeftY := Ri;
    Canvas.FillRoundedRect(X + Bw, Y + Bw,
      Metrics.TotalWidth - 2 * Bw, PillHeight - 2 * Bw,
      InnerRadius, FillColor);
  end;

  // Lead icon or code-drawn colour swatch
  if not Metrics.LeadIconRect.IsEmpty then
  begin
    if (LeadIcon = '') and (tpoShowColorSwatch in Options) then
    begin
      // Darker outline keeps the swatch visible on near-white tag colours.
      SwSize := Metrics.LeadIconRect.Width;
      SwX := X + Metrics.LeadIconRect.X;
      SwY := Y + (PillHeight - SwSize) / 2;
      SwR := SwSize * 0.2;
      Canvas.FillRoundedRect(SwX, SwY, SwSize, SwSize,
        SwR, PixieTagBlend(Base, TPixieWebColor.Black, 0.15));
      Canvas.FillRoundedRect(SwX + 1, SwY + 1, SwSize - 2, SwSize - 2,
        Max(SwR - 1, 0), Base);
    end
    else if LeadIcon <> '' then
    begin
      TextY := Y + (PillHeight - FontMetrics.Height) / 2;
      Canvas.DrawText(LeadIcon, Font, TxtColor,
        X + Metrics.LeadIconRect.X, TextY,
        Metrics.LeadIconRect.Width, FontMetrics.Height);
    end;
  end;

  // Text
  TextY := Y + (PillHeight - FontMetrics.Height) / 2;
  if HasSuffix then
  begin
    // Prefix text
    Canvas.DrawText(Metrics.PrefixText, Font, TxtColor,
      X + Metrics.TextX, TextY,
      Metrics.TextWidth, FontMetrics.Height);
    // Suffix text
    Canvas.DrawText(Metrics.SuffixText, Font, SufTxtColor,
      X + Metrics.SuffixTextX, TextY,
      Metrics.SuffixTextWidth, FontMetrics.Height);
  end
  else
    Canvas.DrawText(Text, Font, TxtColor,
      X + Metrics.TextX, TextY,
      Metrics.TextWidth, FontMetrics.Height);

  // Trail icon (in suffix half if split)
  if not Metrics.TrailIconRect.IsEmpty then
  begin
    TextY := Y + (PillHeight - FontMetrics.Height) / 2;
    if HasSuffix then
      Canvas.DrawText(TrailIcon, Font, SufTxtColor,
        X + Metrics.TrailIconRect.X, TextY,
        Metrics.TrailIconRect.Width, FontMetrics.Height)
    else
      Canvas.DrawText(TrailIcon, Font, TxtColor,
        X + Metrics.TrailIconRect.X, TextY,
        Metrics.TrailIconRect.Width, FontMetrics.Height);
  end;

  // Dismiss cross (in suffix half if split)
  if tpoShowDismiss in Options then
  begin
    Cx := X + Metrics.DismissRect.X + Metrics.DismissRect.Width / 2;
    Cy := Y + PillHeight / 2;
    Arm := Min(Metrics.DismissRect.Width, PillHeight) * 0.18;
    if HasSuffix then
    begin
      Canvas.DrawLine(Cx - Arm, Cy - Arm, Cx + Arm, Cy + Arm,
        SufTxtColor, 1.5);
      Canvas.DrawLine(Cx + Arm, Cy - Arm, Cx - Arm, Cy + Arm,
        SufTxtColor, 1.5);
    end
    else
    begin
      Canvas.DrawLine(Cx - Arm, Cy - Arm, Cx + Arm, Cy + Arm,
        TxtColor, 1.5);
      Canvas.DrawLine(Cx + Arm, Cy - Arm, Cx - Arm, Cy + Arm,
        TxtColor, 1.5);
    end;
  end;
end;

// ---------------------------------------------------------------------------
// Hit testing (coordinates relative to pill origin)
// ---------------------------------------------------------------------------

function HitTestTagPill(LocalX, LocalY: Single;
  const M: TPixieTagPillMetrics): TPixieTagHitZone;
begin
  // Outside content rect?
  if not M.ContentRect.IsPointInside(LocalX, LocalY) then
    Exit(thzNone);

  // Dismiss zone first (rightmost)
  if not M.DismissRect.IsEmpty and
     M.DismissRect.IsPointInside(LocalX, LocalY) then
    Exit(thzDismiss);

  // Lead icon
  if not M.LeadIconRect.IsEmpty and
     M.LeadIconRect.IsPointInside(LocalX, LocalY) then
    Exit(thzLeadIcon);

  Result := thzPill;
end;

end.
