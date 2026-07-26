unit Pixie.Matrix;

// 2D affine transform [A B C D E F] mapping (x,y) -> (A*x + C*y + E,
// B*x + D*y + F). Column-vector convention matching the platform canvas
// ConcatMatrix(A,B,C,D,E,F) and the SVG transform spec. Shared by the SVG
// renderer and the HTML CSS-transform engine.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

type
  { TPixieMatrix }
  TPixieMatrix = record
    A, B, C, D, E, F: Single;
    class function Identity: TPixieMatrix; static;
    // Returns Self composed with M (Self applied after M), so building a CSS
    // transform list left-to-right with R := R.Multiply(Func) yields a matrix
    // whose leftmost function is the outermost — matching CSS semantics.
    function Multiply(const M: TPixieMatrix): TPixieMatrix;
    // Maps a point through the matrix.
    procedure Apply(X, Y: Single; out OX, OY: Single);
    // Inverse of the affine transform; False when (near-)singular.
    function Invert(out Inv: TPixieMatrix): Boolean;
    function IsIdentity: Boolean;
    class function CreateTranslate(TX, TY: Single): TPixieMatrix; static;
    class function CreateScale(SX, SY: Single): TPixieMatrix; static;
    // Angles are in degrees.
    class function CreateRotate(AngleDeg: Single): TPixieMatrix; static;
    class function CreateRotateAt(AngleDeg, CX, CY: Single): TPixieMatrix; static;
    class function CreateSkew(AngleXDeg, AngleYDeg: Single): TPixieMatrix; static;
  end;

implementation

uses
  Math;

const
  DegToRad = Pi / 180.0;

class function TPixieMatrix.Identity: TPixieMatrix;
begin
  Result.A := 1; Result.B := 0;
  Result.C := 0; Result.D := 1;
  Result.E := 0; Result.F := 0;
end;

function TPixieMatrix.Multiply(const M: TPixieMatrix): TPixieMatrix;
begin
  Result.A := A * M.A + C * M.B;
  Result.B := B * M.A + D * M.B;
  Result.C := A * M.C + C * M.D;
  Result.D := B * M.C + D * M.D;
  Result.E := A * M.E + C * M.F + E;
  Result.F := B * M.E + D * M.F + F;
end;

procedure TPixieMatrix.Apply(X, Y: Single; out OX, OY: Single);
begin
  OX := A * X + C * Y + E;
  OY := B * X + D * Y + F;
end;

function TPixieMatrix.Invert(out Inv: TPixieMatrix): Boolean;
var
  Det: Single;
begin
  Det := A * D - B * C;
  if Abs(Det) < 1e-9 then
    Exit(False);
  Inv.A := D / Det;
  Inv.B := -B / Det;
  Inv.C := -C / Det;
  Inv.D := A / Det;
  Inv.E := (C * F - D * E) / Det;
  Inv.F := (B * E - A * F) / Det;
  Result := True;
end;

function TPixieMatrix.IsIdentity: Boolean;
begin
  Result := (A = 1) and (B = 0) and (C = 0) and (D = 1) and (E = 0) and (F = 0);
end;

class function TPixieMatrix.CreateTranslate(TX, TY: Single): TPixieMatrix;
begin
  Result := Identity;
  Result.E := TX;
  Result.F := TY;
end;

class function TPixieMatrix.CreateScale(SX, SY: Single): TPixieMatrix;
begin
  Result := Identity;
  Result.A := SX;
  Result.D := SY;
end;

class function TPixieMatrix.CreateRotate(AngleDeg: Single): TPixieMatrix;
var
  Rad, S, C: Single;
begin
  Rad := AngleDeg * DegToRad;
  S := Sin(Rad);
  C := Cos(Rad);
  Result.A := C;  Result.B := S;
  Result.C := -S; Result.D := C;
  Result.E := 0;  Result.F := 0;
end;

class function TPixieMatrix.CreateRotateAt(AngleDeg, CX, CY: Single): TPixieMatrix;
begin
  Result := CreateTranslate(CX, CY).Multiply(
    CreateRotate(AngleDeg)).Multiply(
    CreateTranslate(-CX, -CY));
end;

class function TPixieMatrix.CreateSkew(AngleXDeg, AngleYDeg: Single): TPixieMatrix;
begin
  Result := Identity;
  Result.C := Tan(AngleXDeg * DegToRad);
  Result.B := Tan(AngleYDeg * DegToRad);
end;

end.
