unit Pixie.FormattingContext;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Generics.Collections, Math,
  Pixie.Types;

type
  TPixieFloatedBoxList = TList<TPixieFloatedBox>;

  { TPixieFormattingContext }
  TPixieFormattingContext = class
  private
    FFloatsLeft: TPixieFloatedBoxList;
    FFloatsRight: TPixieFloatedBoxList;
    FCacheLineLeft: TPixiePixelPixelCache;
    FCacheLineRight: TPixiePixelPixelCache;
    FCurrentTop: TPixiePixel;
    FCurrentLeft: TPixiePixel;
  public
    constructor Create;
    destructor Destroy; override;

    // Coordinate translation
    procedure PushPosition(X, Y: TPixiePixel);
    procedure PopPosition(X, Y: TPixiePixel);

    // Float management
    procedure AddFloat(const Fb: TPixieFloatedBox);
    procedure ClearFloats(Context: Integer);

    // Line queries
    function GetLineLeft(Y: TPixiePixel): TPixiePixel;
    function GetLineRight(Y, DefRight: TPixiePixel): TPixiePixel;
    procedure GetLineLeftRight(Y, DefRight: TPixiePixel; out LnLeft, LnRight: TPixiePixel);
    function FindNextLineTop(Top, Width, DefRight: TPixiePixel): TPixiePixel;

    // Float height queries
    function GetFloatsHeight(ElFloat: TPixieElementFloat = efNone): TPixiePixel;
    function GetLeftFloatsHeight: TPixiePixel;
    function GetRightFloatsHeight: TPixiePixel;

    // Cleared top
    function GetClearedTop(ClearSide: TPixieElementClear;
      FloatSide: TPixieElementFloat; LineTop: TPixiePixel): TPixiePixel;

    // Update stubs (need render_item in Phase 5 Group 2+)
    procedure UpdateFloats(Dy: TPixiePixel; Parent: Pointer);
    procedure ApplyRelativeShift(const ContainingBlockSize: TPixieContainingBlockContext);

    // Min width queries
    function FindMinLeft(Y: TPixiePixel; ContextIdx: Integer): TPixiePixel;
    function FindMinRight(Y, Right: TPixiePixel; ContextIdx: Integer): TPixiePixel;

    // Direct access for tests
    property FloatsLeft: TPixieFloatedBoxList read FFloatsLeft;
    property FloatsRight: TPixieFloatedBoxList read FFloatsRight;
  end;

implementation

uses
  Pixie.Element, Pixie.RenderItem;

{ TPixieFormattingContext }

constructor TPixieFormattingContext.Create;
begin
  inherited Create;
  FFloatsLeft := TPixieFloatedBoxList.Create;
  FFloatsRight := TPixieFloatedBoxList.Create;
  FCacheLineLeft.Init;
  FCacheLineRight.Init;
  FCurrentTop := 0;
  FCurrentLeft := 0;
end;

destructor TPixieFormattingContext.Destroy;
begin
  FFloatsRight.Free;
  FFloatsLeft.Free;
  inherited;
end;

procedure TPixieFormattingContext.PushPosition(X, Y: TPixiePixel);
begin
  FCurrentLeft := FCurrentLeft + X;
  FCurrentTop := FCurrentTop + Y;
end;

procedure TPixieFormattingContext.PopPosition(X, Y: TPixiePixel);
begin
  FCurrentLeft := FCurrentLeft - X;
  FCurrentTop := FCurrentTop - Y;
end;

procedure TPixieFormattingContext.AddFloat(const Fb: TPixieFloatedBox);
var
  NewFb: TPixieFloatedBox;
  I: Integer;
  Inserted: Boolean;
begin
  NewFb := Fb;
  NewFb.Pos.X := NewFb.Pos.X + FCurrentLeft;
  NewFb.Pos.Y := NewFb.Pos.Y + FCurrentTop;

  if NewFb.FloatSide = efLeft then
  begin
    if FFloatsLeft.Count = 0 then
      FFloatsLeft.Add(NewFb)
    else
    begin
      Inserted := False;
      for I := 0 to FFloatsLeft.Count - 1 do
      begin
        if NewFb.Pos.Right > FFloatsLeft[I].Pos.Right then
        begin
          FFloatsLeft.Insert(I, NewFb);
          Inserted := True;
          Break;
        end;
      end;
      if not Inserted then
        FFloatsLeft.Add(NewFb);
    end;
    FCacheLineLeft.Invalidate;
  end
  else if NewFb.FloatSide = efRight then
  begin
    if FFloatsRight.Count = 0 then
      FFloatsRight.Add(NewFb)
    else
    begin
      Inserted := False;
      for I := 0 to FFloatsRight.Count - 1 do
      begin
        if NewFb.Pos.X < FFloatsRight[I].Pos.X then
        begin
          FFloatsRight.Insert(I, NewFb);
          Inserted := True;
          Break;
        end;
      end;
      if not Inserted then
        FFloatsRight.Add(NewFb);
    end;
    FCacheLineRight.Invalidate;
  end;
end;

procedure TPixieFormattingContext.ClearFloats(Context: Integer);
var
  I: Integer;
begin
  for I := FFloatsLeft.Count - 1 downto 0 do
  begin
    if FFloatsLeft[I].Context >= Context then
    begin
      FFloatsLeft.Delete(I);
      FCacheLineLeft.Invalidate;
    end;
  end;

  for I := FFloatsRight.Count - 1 downto 0 do
  begin
    if FFloatsRight[I].Context >= Context then
    begin
      FFloatsRight.Delete(I);
      FCacheLineRight.Invalidate;
    end;
  end;
end;

function TPixieFormattingContext.GetFloatsHeight(ElFloat: TPixieElementFloat): TPixiePixel;
var
  H: TPixiePixel;
  I: Integer;
  Fb: TPixieFloatedBox;
  Process: Boolean;
begin
  H := FCurrentTop;

  for I := 0 to FFloatsLeft.Count - 1 do
  begin
    Fb := FFloatsLeft[I];
    Process := False;
    case ElFloat of
      efNone:
        Process := True;
      efLeft:
        begin
          if Fb.ClearFloats in [ecLeft, ecBoth] then
            Process := True;
        end;
      efRight:
        begin
          if Fb.ClearFloats in [ecRight, ecBoth] then
            Process := True;
        end;
    end;
    if Process then
    begin
      if ElFloat = efNone then
        H := Max(H, Fb.Pos.Bottom)
      else
        H := Max(H, Fb.Pos.Y);
    end;
  end;

  for I := 0 to FFloatsRight.Count - 1 do
  begin
    Fb := FFloatsRight[I];
    Process := False;
    case ElFloat of
      efNone:
        Process := True;
      efLeft:
        begin
          if Fb.ClearFloats in [ecLeft, ecBoth] then
            Process := True;
        end;
      efRight:
        begin
          if Fb.ClearFloats in [ecRight, ecBoth] then
            Process := True;
        end;
    end;
    if Process then
    begin
      if ElFloat = efNone then
        H := Max(H, Fb.Pos.Bottom)
      else
        H := Max(H, Fb.Pos.Y);
    end;
  end;

  Result := H - FCurrentTop;
end;

function TPixieFormattingContext.GetLeftFloatsHeight: TPixiePixel;
var
  H: TPixiePixel;
  I: Integer;
begin
  H := 0;
  if FFloatsLeft.Count > 0 then
  begin
    for I := 0 to FFloatsLeft.Count - 1 do
      H := Max(H, FFloatsLeft[I].Pos.Bottom);
  end;
  Result := H - FCurrentTop;
end;

function TPixieFormattingContext.GetRightFloatsHeight: TPixiePixel;
var
  H: TPixiePixel;
  I: Integer;
begin
  H := 0;
  if FFloatsRight.Count > 0 then
  begin
    for I := 0 to FFloatsRight.Count - 1 do
      H := Max(H, FFloatsRight[I].Pos.Bottom);
  end;
  Result := H - FCurrentTop;
end;

function TPixieFormattingContext.GetLineLeft(Y: TPixiePixel): TPixiePixel;
var
  W: TPixiePixel;
  I: Integer;
  Fb: TPixieFloatedBox;
begin
  Y := Y + FCurrentTop;

  if FCacheLineLeft.IsValid and (FCacheLineLeft.Hash = Y) then
  begin
    W := FCacheLineLeft.Val - FCurrentLeft;
    if W < 0 then
      Result := 0
    else
      Result := W;
    Exit;
  end;

  W := 0;
  for I := 0 to FFloatsLeft.Count - 1 do
  begin
    Fb := FFloatsLeft[I];
    if (Y >= Fb.Pos.Y) and (Y < Fb.Pos.Bottom) then
    begin
      W := Max(W, Fb.Pos.Right);
      if W < Fb.Pos.Right then
        Break;
    end;
  end;
  FCacheLineLeft.SetValue(Y, W);
  W := W - FCurrentLeft;
  if W < 0 then
    Result := 0
  else
    Result := W;
end;

function TPixieFormattingContext.GetLineRight(Y, DefRight: TPixiePixel): TPixiePixel;
var
  W: TPixiePixel;
  I: Integer;
  Fb: TPixieFloatedBox;
begin
  Y := Y + FCurrentTop;
  DefRight := DefRight + FCurrentLeft;

  if FCacheLineRight.IsValid and (FCacheLineRight.Hash = Y) then
  begin
    if FCacheLineRight.IsDefault then
    begin
      Result := DefRight - FCurrentLeft;
      Exit;
    end
    else
    begin
      W := Min(FCacheLineRight.Val, DefRight) - FCurrentLeft;
      if W < 0 then
        Result := 0
      else
        Result := W;
      Exit;
    end;
  end;

  W := DefRight;
  FCacheLineRight.IsDefault := True;
  for I := 0 to FFloatsRight.Count - 1 do
  begin
    Fb := FFloatsRight[I];
    if (Y >= Fb.Pos.Y) and (Y < Fb.Pos.Bottom) then
    begin
      W := Min(W, Fb.Pos.X);
      FCacheLineRight.IsDefault := False;
      if W > Fb.Pos.X then
        Break;
    end;
  end;
  FCacheLineRight.SetValue(Y, W);
  W := W - FCurrentLeft;
  if W < 0 then
    Result := 0
  else
    Result := W;
end;

procedure TPixieFormattingContext.GetLineLeftRight(Y, DefRight: TPixiePixel;
  out LnLeft, LnRight: TPixiePixel);
begin
  LnLeft := GetLineLeft(Y);
  LnRight := GetLineRight(Y, DefRight);
end;

function TPixieFormattingContext.FindNextLineTop(Top, Width, DefRight: TPixiePixel): TPixiePixel;
var
  NewTop: TPixiePixel;
  Points: TPixiePixelVector;
  I: Integer;
  Fb: TPixieFloatedBox;
  Pt, PosLeft, PosRight: TPixiePixel;
begin
  Top := Top + FCurrentTop;
  DefRight := DefRight + FCurrentLeft;

  NewTop := Top;
  Points := TPixiePixelVector.Create;
  try
    // Collect Y coordinates from left floats
    for I := 0 to FFloatsLeft.Count - 1 do
    begin
      Fb := FFloatsLeft[I];
      if Fb.Pos.Y >= Top then
        Points.Add(Fb.Pos.Y);
      if Fb.Pos.Bottom >= Top then
        Points.Add(Fb.Pos.Bottom);
    end;

    // Collect Y coordinates from right floats
    for I := 0 to FFloatsRight.Count - 1 do
    begin
      Fb := FFloatsRight[I];
      if Fb.Pos.Y >= Top then
        Points.Add(Fb.Pos.Y);
      if Fb.Pos.Bottom >= Top then
        Points.Add(Fb.Pos.Bottom);
    end;

    if Points.Count > 0 then
    begin
      Points.Sort;
      NewTop := Points[Points.Count - 1];

      for I := 0 to Points.Count - 1 do
      begin
        Pt := Points[I];
        // Skip duplicates
        if (I > 0) and (Pt = Points[I - 1]) then
          Continue;
        PosLeft := 0;
        PosRight := DefRight;
        GetLineLeftRight(Pt - FCurrentTop, DefRight - FCurrentLeft, PosLeft, PosRight);

        if PosRight - PosLeft >= Width then
        begin
          NewTop := Pt;
          Break;
        end;
      end;
    end;
  finally
    Points.Free;
  end;

  Result := NewTop - FCurrentTop;
end;

function TPixieFormattingContext.GetClearedTop(ClearSide: TPixieElementClear;
  FloatSide: TPixieElementFloat; LineTop: TPixiePixel): TPixiePixel;
var
  Fh: TPixiePixel;
begin
  Result := LineTop;
  case ClearSide of
    ecLeft:
      begin
        Fh := GetLeftFloatsHeight;
        if (Fh <> 0) and (Fh > LineTop) then
          Result := Fh;
      end;
    ecRight:
      begin
        Fh := GetRightFloatsHeight;
        if (Fh <> 0) and (Fh > LineTop) then
          Result := Fh;
      end;
    ecBoth:
      begin
        Fh := GetFloatsHeight(efNone);
        if (Fh <> 0) and (Fh > LineTop) then
          Result := Fh;
      end;
  else
    begin
      if FloatSide <> efNone then
      begin
        Fh := GetFloatsHeight(FloatSide);
        if (Fh <> 0) and (Fh > LineTop) then
          Result := Fh;
      end;
    end;
  end;
end;

procedure TPixieFormattingContext.UpdateFloats(Dy: TPixiePixel; Parent: Pointer);
var
  I: Integer;
  Fb: TPixieFloatedBox;
  ParentEl: TPixieElement;
  ResetCache: Boolean;
begin
  Assert(TObject(Parent) is TPixieRenderItem);
  ParentEl := TPixieRenderItem(Parent).SrcEl;
  ResetCache := False;
  for I := 0 to FFloatsLeft.Count - 1 do
  begin
    Fb := FFloatsLeft[I];
    Assert(TObject(Fb.El) is TPixieRenderItem);
    if TPixieRenderItem(Fb.El).SrcEl.IsAncestor(ParentEl) then
    begin
      ResetCache := True;
      Fb.Pos.Y := Fb.Pos.Y + Dy;
      FFloatsLeft[I] := Fb;
    end;
  end;
  if ResetCache then
    FCacheLineLeft.Invalidate;
  ResetCache := False;
  for I := 0 to FFloatsRight.Count - 1 do
  begin
    Fb := FFloatsRight[I];
    if TPixieRenderItem(Fb.El).SrcEl.IsAncestor(ParentEl) then
    begin
      ResetCache := True;
      Fb.Pos.Y := Fb.Pos.Y + Dy;
      FFloatsRight[I] := Fb;
    end;
  end;
  if ResetCache then
    FCacheLineRight.Invalidate;
end;

procedure TPixieFormattingContext.ApplyRelativeShift(
  const ContainingBlockSize: TPixieContainingBlockContext);
begin
  // Stub — requires render_item.apply_relative_shift (Phase 5 Group 2+)
end;

function TPixieFormattingContext.FindMinLeft(Y: TPixiePixel; ContextIdx: Integer): TPixiePixel;
var
  MinLeft: TPixiePixel;
  I: Integer;
  Fb: TPixieFloatedBox;
begin
  Y := Y + FCurrentTop;
  MinLeft := FCurrentLeft;
  for I := 0 to FFloatsLeft.Count - 1 do
  begin
    Fb := FFloatsLeft[I];
    if (Y >= Fb.Pos.Y) and (Y < Fb.Pos.Bottom) and (Fb.Context = ContextIdx) then
      MinLeft := MinLeft + Fb.MinWidth;
  end;
  if MinLeft < FCurrentLeft then
    Result := 0
  else
    Result := MinLeft - FCurrentLeft;
end;

function TPixieFormattingContext.FindMinRight(Y, Right: TPixiePixel; ContextIdx: Integer): TPixiePixel;
var
  MinRight: TPixiePixel;
  I: Integer;
  Fb: TPixieFloatedBox;
begin
  Y := Y + FCurrentTop;
  MinRight := Right + FCurrentLeft;
  for I := 0 to FFloatsRight.Count - 1 do
  begin
    Fb := FFloatsRight[I];
    if (Y >= Fb.Pos.Y) and (Y < Fb.Pos.Bottom) and (Fb.Context = ContextIdx) then
      MinRight := MinRight - Fb.MinWidth;
  end;
  if MinRight < FCurrentLeft then
    Result := 0
  else
    Result := MinRight - FCurrentLeft;
end;

end.
