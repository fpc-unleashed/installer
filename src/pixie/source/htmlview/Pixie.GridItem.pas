unit Pixie.GridItem;

// Grid item + track + occupancy data structures for CSS Grid layout.
// Mirrors the pattern of Pixie.FlexItem.pas for flexbox.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Generics.Collections,
  Pixie.Types, Pixie.CssLength;

type
  { TPixieGridTrack — a single column or row track }
  TPixieGridTrack = record
    // Definition (from CSS)
    Size: TPixieCssLength;    // track size definition (px, %, fr, auto=predefined)
    MinSize: TPixieCssLength; // minmax() min bound
    MaxSize: TPixieCssLength; // minmax() max bound
    HasMinmax: Boolean;       // True if minmax() was used
    // Computed (from layout)
    Base: TPixiePixel;            // resolved base size in pixels
    Position: TPixiePixel;        // start position in pixels
  end;
  TPixieGridTrackList = TList<TPixieGridTrack>;

  { TPixieGridPlacement — resolved row/column placement for one item }
  TPixieGridPlacement = record
    RowStart: Integer;        // 0-based row index
    RowEnd: Integer;          // 0-based exclusive end
    ColStart: Integer;        // 0-based column index
    ColEnd: Integer;          // 0-based exclusive end
    procedure Init;
  end;

  { TPixieGridItem — one child in the grid }
  TPixieGridItem = class
  public
    El: Pointer;              // TPixieRenderItem (weak ref)
    Placement: TPixieGridPlacement;
    SrcOrder: Integer;
    constructor Create(AEl: Pointer; AOrder: Integer);
  end;
  TPixieGridItemList = TObjectList<TPixieGridItem>;

  { TPixieGridOccupancy — 2D boolean grid for auto-placement }
  TPixieGridOccupancy = class
  private
    FCells: array of array of Boolean;
    FRows: Integer;
    FCols: Integer;
    procedure EnsureSize(ARows, ACols: Integer);
  public
    constructor Create;
    procedure Clear;
    procedure Mark(R1, C1, R2, C2: Integer);
    function IsOccupied(R1, C1, R2, C2: Integer): Boolean;
    function FindFreeColumn(Row, ColSpan, NumCols: Integer): Integer;
    property Rows: Integer read FRows;
    property Cols: Integer read FCols;
  end;

implementation

{ TPixieGridPlacement }

procedure TPixieGridPlacement.Init;
begin
  RowStart := -1;
  RowEnd := -1;
  ColStart := -1;
  ColEnd := -1;
end;

{ TPixieGridItem }

constructor TPixieGridItem.Create(AEl: Pointer; AOrder: Integer);
begin
  inherited Create;
  El := AEl;
  SrcOrder := AOrder;
  Placement.Init;
end;

{ TPixieGridOccupancy }

constructor TPixieGridOccupancy.Create;
begin
  inherited Create;
  FRows := 0;
  FCols := 0;
end;

procedure TPixieGridOccupancy.Clear;
begin
  SetLength(FCells, 0);
  FRows := 0;
  FCols := 0;
end;

procedure TPixieGridOccupancy.EnsureSize(ARows, ACols: Integer);
var
  OldRows, OldCols, R, C: Integer;
begin
  if (ARows <= FRows) and (ACols <= FCols) then
    Exit;

  OldRows := FRows;
  OldCols := FCols;

  if ARows > FRows then
    FRows := ARows;
  if ACols > FCols then
    FCols := ACols;

  SetLength(FCells, FRows, FCols);

  // Zero-initialise new cells
  for R := 0 to FRows - 1 do
    for C := 0 to FCols - 1 do
      if (R >= OldRows) or (C >= OldCols) then
        FCells[R][C] := False;
end;

procedure TPixieGridOccupancy.Mark(R1, C1, R2, C2: Integer);
var
  R, C: Integer;
begin
  EnsureSize(R2, C2);
  for R := R1 to R2 - 1 do
    for C := C1 to C2 - 1 do
      FCells[R][C] := True;
end;

function TPixieGridOccupancy.IsOccupied(R1, C1, R2, C2: Integer): Boolean;
var
  R, C: Integer;
begin
  Result := False;
  for R := R1 to R2 - 1 do
    for C := C1 to C2 - 1 do
      if (R < FRows) and (C < FCols) and FCells[R][C] then
        Exit(True);
end;

function TPixieGridOccupancy.FindFreeColumn(Row, ColSpan, NumCols: Integer): Integer;
var
  C: Integer;
begin
  for C := 0 to NumCols - ColSpan do
    if not IsOccupied(Row, C, Row + 1, C + ColSpan) then
      Exit(C);
  // No free column found in existing columns — expand
  Result := NumCols;
end;

end.
