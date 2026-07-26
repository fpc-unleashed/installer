unit Pixie.ElTextInput;

// Owner-drawn <input type="text">, <input type="password"> and <textarea>
// elements. All are replaced elements with editable text, caret, selection,
// and clipboard support.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Math,
  Pixie.Types, Pixie.WebColor, Pixie.Borders,
  Pixie.Container,
  Pixie.Element, Pixie.HtmlTag;

type
  { TPixieElTextBase — abstract base for editable text elements }

  TPixieElTextBase = class(TPixieHtmlTag)
  protected
    FValue: string;
    FCaretPos: Integer;       // byte position 0..Length(FValue)
    FSelStart: Integer;       // selection start (-1 = no selection)
    FSelEnd: Integer;         // selection end
    FScrollX: TPixiePixel;        // horizontal scroll offset
    FPassword: Boolean;       // show bullets
    FPlaceholder: string;     // placeholder text
    FReadOnly: Boolean;
    FMaxLength: Integer;      // -1 = unlimited
    FMultiLine: Boolean;
    FScrollY: TPixiePixel;        // vertical scroll (textarea)
    FCaretMoved: Boolean;     // AdjustScroll needed
    FUndoValue: string;       // previous value for Ctrl+Z
    FUndoCaret: Integer;      // previous caret position
    FUndoSaved: Boolean;      // undo snapshot available
    FWordSelecting: Boolean;  // drag extends by whole words
    FWordSelStart: Integer;   // anchor word start byte pos
    FWordSelEnd: Integer;     // anchor word end byte pos
    FSbDragging: Boolean;     // dragging the textarea scrollbar thumb
    FSbDragOffset: TPixiePixel; // cursor offset within thumb at grab
    procedure SaveUndo;

    // Per-line advance = CSS line-height; glyphs sit centred within it.
    function LineAdvance: TPixiePixel;

    // Vertical scrollbar (multiline overflow). Metrics returns False when
    // no scrollbar is needed; all coordinates are local to the content box.
    function ScrollbarMetrics(VisibleW, VisibleH: TPixiePixel;
      out SbX, SbW, ThumbY, ThumbH, MaxScrollY: TPixiePixel): Boolean;
    procedure ScrollToThumbTop(ThumbTop, VisibleW, VisibleH: TPixiePixel);

    function DisplayText: string;
    function IsDisabled: Boolean;
    procedure InsertText(const S: string);
    procedure DeleteSelection;
    procedure DeleteChar(Forward: Boolean);
    procedure MoveCaret(Direction: Integer; Shift: Boolean);
    procedure MoveCaretWord(Direction: Integer; Shift: Boolean);
    procedure MoveCaretHome(Shift: Boolean);
    procedure MoveCaretEnd(Shift: Boolean);
    procedure SelectAll; reintroduce;
    procedure SelectWordAtCaret;
    function FindWordBounds(BytePos: Integer; out WS, WE: Integer): Boolean;
    procedure ClearSelection;
    function HasSelection: Boolean;
    function GetSelectedText: string;

    // Line helpers (multiline)
    procedure CaretToLineCol(out Line, Col: Integer);
    function GetLineStart(Line: Integer): Integer;
    function GetLineEnd(Line: Integer): Integer;
    function GetLineCount: Integer;
    function GetLineText(Line: Integer): string;

    // Coordinate mapping
    function DocToLocal(DocX, DocY: TPixiePixel;
      out LocalX, LocalY: TPixiePixel): Boolean;
    function ClickToCaret(RelX, RelY: TPixiePixel): Integer;
    function CaretToPixelXY(out PxX, PxY: TPixiePixel): Boolean;
    procedure AdjustScroll(ContentW, ContentH: TPixiePixel);

    // Horizontal shift for text-align (right/centre). Zero for left/justify
    // and when the line overflows the content box (left origin + scroll).
    function AlignDX(const LineStr: string): TPixiePixel;

    // Drawing
    procedure DrawContent(Cv: TObject; P: TPixiePosition;
      Pad: TPixieMargins; IsFocused: Boolean; Ri: Pointer);
  public
    constructor Create(ADoc: TObject);

    function IsReplaced: Boolean; override;
    procedure ParseAttributes; override;
    procedure Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
      Clip: PPixiePosition; Ri: Pointer); override;
    function CreateRenderItem(ParentRi: Pointer): Pointer; override;
    procedure OnClick; override;
    function OnLButtonDown: Boolean; override;
    function OnLButtonDblClick: Boolean; override;
    function OnMouseDrag(X, Y: TPixiePixel): Boolean; override;
    function CursorForPoint(DocX, DocY: TPixiePixel): string; override;

    // Focus and keyboard
    procedure OnFocus; override;
    procedure OnBlur; override;
    function OnKeyDown(Key: Word; Shift: TShiftState): Boolean; override;
    function OnUTF8KeyPress(const UTF8Char: string): Boolean; override;
    function IsFocusable: Boolean; override;

    function GetCaretDocPos(out X, Y, H: TPixiePixel): Boolean;

    property Value: string read FValue write FValue;
  end;

  { TPixieElTextInput — <input type="text|password"> }

  TPixieElTextInput = class(TPixieElTextBase)
  public
    procedure ParseAttributes; override;
    procedure GetContentSize(var Sz: TPixieSize;
      MaxWidth: TPixiePixel); override;
    function DumpGetName: string; override;
  end;

  { TPixieElTextArea — <textarea> }

  TPixieElTextArea = class(TPixieElTextBase)
  private
    FRows: Integer;
    FCols: Integer;
  public
    constructor Create(ADoc: TObject);
    procedure ParseAttributes; override;
    procedure GetContentSize(var Sz: TPixieSize;
      MaxWidth: TPixiePixel); override;
    function OnKeyDown(Key: Word; Shift: TShiftState): Boolean; override;
    function OnMouseWheel(Delta: Integer): Boolean; override;
    function DumpGetName: string; override;
  end;

implementation

uses
  Pixie.Clipboard, Pixie.StringId, Pixie.Style, Pixie.Background,
  Pixie.Canvas, Pixie.NativeContainer,
  Pixie.Document, Pixie.RenderItem, Pixie.RenderInput,
  Pixie.RenderTable, Pixie.Utf8;

// Virtual key constants — values are the same in LCLType, Windows,
// and System.UITypes (FPC and Delphi). Defined here to avoid
// depending on any of those units.
const
  VK_BACK   = $08;
  VK_RETURN = $0D;
  VK_END    = $23;
  VK_HOME   = $24;
  VK_LEFT   = $25;
  VK_UP     = $26;
  VK_RIGHT  = $27;
  VK_DOWN   = $28;
  VK_DELETE = $2E;

  // Textarea vertical scrollbar geometry
  PixieTextScrollbarWidth = 10;
  PixieTextScrollbarMinThumb = 24;

function GetCanvas(Tag: TPixieHtmlTag): TPixieCanvas;
var
  Cont: TPixieContainer;
begin
  Result := nil;
  Cont := Tag.GetDocContainer;
  if (Cont <> nil) and (Cont is TPixieNativeContainer) then
    Result := TPixieNativeContainer(Cont).Canvas;
end;

function GetNativeContainer(Tag: TPixieHtmlTag): TPixieNativeContainer;
var
  Cont: TPixieContainer;
begin
  Result := nil;
  Cont := Tag.GetDocContainer;
  if (Cont <> nil) and (Cont is TPixieNativeContainer) then
    Result := TPixieNativeContainer(Cont);
end;

{ UTF-8 navigation helpers }

function UTF8NextCharPos(const S: string; BytePos: Integer): Integer;
var
  B: Byte;
  Len: Integer;
begin
  Len := Length(S);
  if BytePos >= Len then
    Exit(Len);
  B := Byte(S[BytePos + 1]);
  if B < $80 then
    Result := BytePos + 1
  else if B < $E0 then
    Result := Min(BytePos + 2, Len)
  else if B < $F0 then
    Result := Min(BytePos + 3, Len)
  else
    Result := Min(BytePos + 4, Len);
end;

function UTF8PrevCharPos(const S: string; BytePos: Integer): Integer;
var
  I: Integer;
begin
  if BytePos <= 0 then
    Exit(0);
  I := BytePos - 1;
  while (I > 0) and ((Byte(S[I + 1]) and $C0) = $80) do
    Dec(I);
  Result := I;
end;

function UTF8CharCount(const S: string): Integer;
var
  I, Len: Integer;
begin
  Result := 0;
  I := 1;
  Len := Length(S);
  while I <= Len do
  begin
    Inc(Result);
    if Byte(S[I]) < $80 then
      Inc(I)
    else if Byte(S[I]) < $E0 then
      Inc(I, 2)
    else if Byte(S[I]) < $F0 then
      Inc(I, 3)
    else
      Inc(I, 4);
  end;
end;

{ TPixieElTextBase }

constructor TPixieElTextBase.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
  FValue := '';
  FCaretPos := 0;
  FSelStart := -1;
  FSelEnd := -1;
  FScrollX := 0;
  FScrollY := 0;
  FPassword := False;
  FPlaceholder := '';
  FReadOnly := False;
  FMaxLength := -1;
  FMultiLine := False;
end;

function TPixieElTextBase.IsReplaced: Boolean;
begin
  Result := True;
end;

function TPixieElTextBase.IsFocusable: Boolean;
begin
  Result := not IsDisabled;
end;

function TPixieElTextBase.IsDisabled: Boolean;
begin
  Result := IsEffectivelyDisabled;
end;

function TPixieElTextBase.DisplayText: string;
var
  I, Len: Integer;
begin
  if FPassword then
  begin
    Len := UTF8CharCount(FValue);
    Result := '';
    for I := 1 to Len do
      Result := Result + {$IFDEF FPC}#$E2#$80#$A2{$ELSE}#$2022{$ENDIF}; // ● // U+2022 BULLET
  end
  else
    Result := FValue;
end;

// ---------------------------------------------------------------------------
// Line helpers — work on FValue, lines separated by #10
// ---------------------------------------------------------------------------

procedure TPixieElTextBase.CaretToLineCol(out Line, Col: Integer);
var
  I, LineStart: Integer;
begin
  Line := 0;
  LineStart := 0;
  for I := 1 to FCaretPos do
    if FValue[I] = #10 then
    begin
      Inc(Line);
      LineStart := I;
    end;
  Col := FCaretPos - LineStart;
end;

function TPixieElTextBase.GetLineStart(Line: Integer): Integer;
var
  I, CurLine: Integer;
begin
  if Line <= 0 then
    Exit(0);
  CurLine := 0;
  for I := 1 to Length(FValue) do
    if FValue[I] = #10 then
    begin
      Inc(CurLine);
      if CurLine = Line then
        Exit(I); // byte offset just past the #10
    end;
  Result := Length(FValue);
end;

function TPixieElTextBase.GetLineEnd(Line: Integer): Integer;
var
  I, CurLine: Integer;
begin
  CurLine := 0;
  for I := 1 to Length(FValue) do
    if FValue[I] = #10 then
    begin
      if CurLine = Line then
        Exit(I - 1);
      Inc(CurLine);
    end;
  Result := Length(FValue);
end;

function TPixieElTextBase.GetLineCount: Integer;
var
  I: Integer;
begin
  Result := 1;
  for I := 1 to Length(FValue) do
    if FValue[I] = #10 then
      Inc(Result);
end;

function TPixieElTextBase.GetLineText(Line: Integer): string;
var
  LS, LE: Integer;
begin
  LS := GetLineStart(Line);
  LE := GetLineEnd(Line);
  Result := Copy(FValue, LS + 1, LE - LS);
end;

// ---------------------------------------------------------------------------
// Coordinate mapping
// ---------------------------------------------------------------------------

function TPixieElTextBase.DocToLocal(DocX, DocY: TPixiePixel;
  out LocalX, LocalY: TPixiePixel): Boolean;
var
  Ri, Cur: TPixieRenderItem;
  Chain: array of TPixieRenderItem;
  Count, I: Integer;
begin
  // Replicate the coordinate transform that GetChildByPoint does:
  // at each level, subtract the element's Pos from the point.
  // This gives coordinates relative to the element's content box.
  Ri := TPixieRenderItem(GetRenderItem);
  if Ri = nil then
  begin
    LocalX := DocX;
    LocalY := DocY;
    Exit(False);
  end;

  // Build chain from root to self (inclusive)
  Count := 0;
  Cur := Ri;
  while Cur <> nil do
  begin
    Inc(Count);
    Cur := Cur.GetParent;
  end;

  SetLength(Chain, Count);
  Cur := Ri;
  for I := Count - 1 downto 0 do
  begin
    Chain[I] := Cur;
    Cur := Cur.GetParent;
  end;

  // Transform: subtract each element's Pos going root -> self.
  // Skip tbody/tr render items because table cell positions are
  // relative to the table content area, not to their parent tr/tbody.
  LocalX := DocX;
  LocalY := DocY;
  for I := 0 to Count - 1 do
  begin
    if (Chain[I] is TPixieRenderTablePart) or
       (Chain[I] is TPixieRenderTableRow) then
      Continue;
    LocalX := LocalX - Chain[I].Pos.X;
    LocalY := LocalY - Chain[I].Pos.Y;
  end;

  Result := True;
end;

function TPixieElTextBase.LineAdvance: TPixiePixel;
begin
  Result := FCss.LineHeight.ComputedValue;
  if Result <= 0 then
    Result := FCss.FontMetrics.Height;
end;

function TPixieElTextBase.ScrollbarMetrics(VisibleW, VisibleH: TPixiePixel;
  out SbX, SbW, ThumbY, ThumbH, MaxScrollY: TPixiePixel): Boolean;
var
  ContentH, Range: TPixiePixel;
begin
  Result := False;
  if not FMultiLine then
    Exit;
  ContentH := GetLineCount * LineAdvance;
  MaxScrollY := ContentH - VisibleH;
  if MaxScrollY <= 0 then
    Exit;

  SbW := PixieTextScrollbarWidth;
  SbX := VisibleW - SbW;
  ThumbH := VisibleH * VisibleH / ContentH;
  if ThumbH < PixieTextScrollbarMinThumb then
    ThumbH := PixieTextScrollbarMinThumb;
  if ThumbH > VisibleH then
    ThumbH := VisibleH;
  Range := VisibleH - ThumbH;
  if Range > 0 then
    ThumbY := (FScrollY / MaxScrollY) * Range
  else
    ThumbY := 0;
  Result := True;
end;

procedure TPixieElTextBase.ScrollToThumbTop(
  ThumbTop, VisibleW, VisibleH: TPixiePixel);
var
  SbX, SbW, ThumbY, ThumbH, MaxScrollY, Range: TPixiePixel;
begin
  if not ScrollbarMetrics(VisibleW, VisibleH,
    SbX, SbW, ThumbY, ThumbH, MaxScrollY) then
    Exit;
  Range := VisibleH - ThumbH;
  if Range <= 0 then
    FScrollY := 0
  else
    FScrollY := (ThumbTop / Range) * MaxScrollY;
  if FScrollY < 0 then
    FScrollY := 0;
  if FScrollY > MaxScrollY then
    FScrollY := MaxScrollY;
end;

function TPixieElTextBase.CaretToPixelXY(
  out PxX, PxY: TPixiePixel): Boolean;
var
  Cv: TPixieCanvas;
  Line, Col, I, CharCount: Integer;
  LineH: TPixiePixel;
  LineStr: string;
  ColText: string;
begin
  Cv := GetCanvas(Self);
  if Cv = nil then
  begin
    PxX := 0;
    PxY := 0;
    Exit(False);
  end;

  LineH := LineAdvance;

  if FMultiLine then
  begin
    CaretToLineCol(Line, Col);
    LineStr := GetLineText(Line);
    ColText := Copy(LineStr, 1, Col);
    PxX := Cv.MeasureText(ColText, FCss.Font) - FScrollX;
    PxY := Line * LineH - FScrollY;
  end
  else
  begin
    if FPassword then
    begin
      CharCount := UTF8CharCount(Copy(FValue, 1, FCaretPos));
      ColText := '';
      for I := 1 to CharCount do
        ColText := ColText + {$IFDEF FPC}#$E2#$80#$A2{$ELSE}#$2022{$ENDIF}; // ●
    end
    else
      ColText := Copy(FValue, 1, FCaretPos);
    PxX := Cv.MeasureText(ColText, FCss.Font) - FScrollX;
    PxY := 0;
  end;
  Result := True;
end;

function TPixieElTextBase.GetCaretDocPos(out X, Y, H: TPixiePixel): Boolean;
var
  PxX, PxY: TPixiePixel;
  Ri, Cur: TPixieRenderItem;
begin
  Result := CaretToPixelXY(PxX, PxY);
  if not Result then Exit;

  Ri := TPixieRenderItem(GetRenderItem);
  if Ri = nil then Exit(False);

  // Accumulate positions from self to root (reverse of DocToLocal)
  X := PxX;
  Y := PxY;
  Cur := Ri;
  while Cur <> nil do
  begin
    if not (Cur is TPixieRenderTablePart) and
       not (Cur is TPixieRenderTableRow) then
    begin
      X := X + Cur.Pos.X;
      Y := Y + Cur.Pos.Y;
    end;
    Cur := Cur.GetParent;
  end;

  H := FCss.FontMetrics.Height;
end;

function TPixieElTextBase.ClickToCaret(
  RelX, RelY: TPixiePixel): Integer;
var
  Cv: TPixieCanvas;
  LineH: TPixiePixel;
  TargetLine, NumLines: Integer;
  LineStr: string;
  LS, I, BestPos, Len: Integer;
  MeasW, BestDist, Dist, AdjX: TPixiePixel;
begin
  Cv := GetCanvas(Self);
  if Cv = nil then
    Exit(0);

  LineH := LineAdvance;

  if FMultiLine then
  begin
    // Determine which line was clicked
    TargetLine := Trunc((RelY + FScrollY) / LineH);
    NumLines := GetLineCount;
    if TargetLine < 0 then
      TargetLine := 0;
    if TargetLine >= NumLines then
      TargetLine := NumLines - 1;

    LineStr := GetLineText(TargetLine);
    LS := GetLineStart(TargetLine);
    AdjX := RelX + FScrollX - AlignDX(LineStr);
  end
  else
  begin
    LineStr := DisplayText;
    LS := 0;
    AdjX := RelX + FScrollX - AlignDX(LineStr);
  end;

  // Find closest character boundary within the line
  Len := Length(LineStr);
  BestPos := 0;
  BestDist := Abs(AdjX);

  I := 0;
  while I < Len do
  begin
    I := UTF8NextCharPos(LineStr, I);
    MeasW := Cv.MeasureText(Copy(LineStr, 1, I), FCss.Font);
    Dist := Abs(AdjX - MeasW);
    if Dist < BestDist then
    begin
      BestDist := Dist;
      BestPos := I;
    end;
  end;

  // Map back to FValue byte position
  if FPassword and (not FMultiLine) then
  begin
    Result := 0;
    for I := 1 to BestPos div 3 do
      Result := UTF8NextCharPos(FValue, Result);
  end
  else
    Result := LS + BestPos;
end;

procedure TPixieElTextBase.AdjustScroll(ContentW, ContentH: TPixiePixel);
var
  PxX, PxY: TPixiePixel;
  LineH, Margin: TPixiePixel;
begin
  if not CaretToPixelXY(PxX, PxY) then
    Exit;

  LineH := LineAdvance;
  Margin := 4;

  // Horizontal scroll
  if PxX > ContentW - Margin then
    FScrollX := FScrollX + (PxX - ContentW + Margin);
  if PxX < Margin then
    FScrollX := FScrollX + (PxX - Margin);
  if FScrollX < 0 then
    FScrollX := 0;

  // Vertical scroll (multiline only)
  if FMultiLine then
  begin
    if PxY < 0 then
      FScrollY := FScrollY + PxY;
    if PxY + LineH > ContentH then
      FScrollY := FScrollY + (PxY + LineH - ContentH);
    if FScrollY < 0 then
      FScrollY := 0;
  end;
end;

// ---------------------------------------------------------------------------
// Editing
// ---------------------------------------------------------------------------

procedure TPixieElTextBase.ParseAttributes;
begin
  if GetAttr('disabled', #1) <> #1 then
    SetPseudoClass(Ord(psid_disabled), True);
  FReadOnly := GetAttr('readonly', #1) <> #1;
  inherited ParseAttributes;
end;

procedure TPixieElTextBase.SaveUndo;
begin
  FUndoValue := FValue;
  FUndoCaret := FCaretPos;
  FUndoSaved := True;
end;

procedure TPixieElTextBase.InsertText(const S: string);
var
  I, Cur, MaxChars: Integer;
  TotalChars: Integer;
begin
  if FReadOnly or IsDisabled then
    Exit;
  SaveUndo;
  if HasSelection then
    DeleteSelection;

  if FMaxLength >= 0 then
  begin
    TotalChars := UTF8CharCount(FValue);
    MaxChars := FMaxLength - TotalChars;
    if MaxChars <= 0 then
      Exit;
    Cur := 0;
    for I := 1 to Min(MaxChars, UTF8CharCount(S)) do
      Cur := UTF8NextCharPos(S, Cur);
    if Cur < Length(S) then
    begin
      FValue := Copy(FValue, 1, FCaretPos) + Copy(S, 1, Cur) +
        Copy(FValue, FCaretPos + 1, Length(FValue) - FCaretPos);
      FCaretPos := FCaretPos + Cur;
      Exit;
    end;
  end;

  FValue := Copy(FValue, 1, FCaretPos) + S +
    Copy(FValue, FCaretPos + 1, Length(FValue) - FCaretPos);
  FCaretPos := FCaretPos + Length(S);
  FCaretMoved := True;
end;

procedure TPixieElTextBase.DeleteSelection;
var
  Lo, Hi: Integer;
begin
  if not HasSelection then
    Exit;
  Lo := Min(FSelStart, FSelEnd);
  Hi := Max(FSelStart, FSelEnd);
  FValue := Copy(FValue, 1, Lo) +
    Copy(FValue, Hi + 1, Length(FValue) - Hi);
  FCaretPos := Lo;
  FCaretMoved := True;
  ClearSelection;
end;

procedure TPixieElTextBase.DeleteChar(Forward: Boolean);
var
  NewPos: Integer;
begin
  if FReadOnly or IsDisabled then
    Exit;
  SaveUndo;
  if HasSelection then
  begin
    DeleteSelection;
    Exit;
  end;
  if Forward then
  begin
    if FCaretPos >= Length(FValue) then
      Exit;
    NewPos := UTF8NextCharPos(FValue, FCaretPos);
    FValue := Copy(FValue, 1, FCaretPos) +
      Copy(FValue, NewPos + 1, Length(FValue) - NewPos);
  end
  else
  begin
    if FCaretPos <= 0 then
      Exit;
    NewPos := UTF8PrevCharPos(FValue, FCaretPos);
    FValue := Copy(FValue, 1, NewPos) +
      Copy(FValue, FCaretPos + 1, Length(FValue) - FCaretPos);
    FCaretPos := NewPos;
  end;
  FCaretMoved := True;
end;

procedure TPixieElTextBase.MoveCaret(Direction: Integer; Shift: Boolean);
var
  NewPos: Integer;
begin
  NewPos := FCaretPos;
  if Direction < 0 then
    NewPos := UTF8PrevCharPos(FValue, FCaretPos)
  else if Direction > 0 then
    NewPos := UTF8NextCharPos(FValue, FCaretPos);

  if Shift then
  begin
    if FSelStart < 0 then
      FSelStart := FCaretPos;
    FSelEnd := NewPos;
  end
  else
    ClearSelection;
  FCaretPos := NewPos;
  FCaretMoved := True;
end;

procedure TPixieElTextBase.MoveCaretWord(Direction: Integer;
  Shift: Boolean);

  function IsBreak(BytePos: Integer): Boolean;
  var
    B: Byte;
  begin
    if (BytePos < 0) or (BytePos >= Length(FValue)) then
      Exit(True);
    B := Byte(FValue[BytePos + 1]);
    if B >= $80 then
      Exit(False);
    Result := (B <= 32) or (B = Ord(',')) or (B = Ord('.')) or
      (B = Ord('!')) or (B = Ord('?')) or (B = Ord(';')) or
      (B = Ord(':')) or (B = Ord('"')) or (B = Ord('''')) or
      (B = Ord('(')) or (B = Ord(')')) or (B = Ord('/'));
  end;

var
  NewPos, Prev: Integer;
begin
  NewPos := FCaretPos;
  if Direction < 0 then
  begin
    // Skip breaks, then skip word chars
    while (NewPos > 0) and IsBreak(UTF8PrevCharPos(FValue, NewPos)) do
      NewPos := UTF8PrevCharPos(FValue, NewPos);
    while NewPos > 0 do
    begin
      Prev := UTF8PrevCharPos(FValue, NewPos);
      if IsBreak(Prev) then Break;
      NewPos := Prev;
    end;
  end
  else
  begin
    // Skip word chars, then skip breaks
    while (NewPos < Length(FValue)) and not IsBreak(NewPos) do
      NewPos := UTF8NextCharPos(FValue, NewPos);
    while (NewPos < Length(FValue)) and IsBreak(NewPos) do
      NewPos := UTF8NextCharPos(FValue, NewPos);
  end;

  if Shift then
  begin
    if FSelStart < 0 then
      FSelStart := FCaretPos;
    FSelEnd := NewPos;
  end
  else
    ClearSelection;
  FCaretPos := NewPos;
  FCaretMoved := True;
end;

procedure TPixieElTextBase.MoveCaretHome(Shift: Boolean);
var
  Target: Integer;
  Line, Col: Integer;
begin
  if FMultiLine then
  begin
    CaretToLineCol(Line, Col);
    Target := GetLineStart(Line);
  end
  else
    Target := 0;

  if Shift then
  begin
    if FSelStart < 0 then
      FSelStart := FCaretPos;
    FSelEnd := Target;
  end
  else
    ClearSelection;
  FCaretPos := Target;
  FCaretMoved := True;
end;

procedure TPixieElTextBase.MoveCaretEnd(Shift: Boolean);
var
  Target: Integer;
  Line, Col: Integer;
begin
  if FMultiLine then
  begin
    CaretToLineCol(Line, Col);
    Target := GetLineEnd(Line);
  end
  else
    Target := Length(FValue);

  if Shift then
  begin
    if FSelStart < 0 then
      FSelStart := FCaretPos;
    FSelEnd := Target;
  end
  else
    ClearSelection;
  FCaretPos := Target;
  FCaretMoved := True;
end;

procedure TPixieElTextBase.SelectAll;
begin
  FSelStart := 0;
  FSelEnd := Length(FValue);
end;

function TPixieElTextBase.FindWordBounds(BytePos: Integer;
  out WS, WE: Integer): Boolean;

  function IsBreak(P: Integer): Boolean;
  var
    B: Byte;
  begin
    if (P < 0) or (P >= Length(FValue)) then
      Exit(True);
    B := Byte(FValue[P + 1]);
    if B >= $80 then
      Exit(False);
    Result := (B <= 32) or (B = Ord(',')) or (B = Ord('.')) or
      (B = Ord('!')) or (B = Ord('?')) or (B = Ord(';')) or
      (B = Ord(':')) or (B = Ord('"')) or (B = Ord('''')) or
      (B = Ord('(')) or (B = Ord(')')) or (B = Ord('/'));
  end;

var
  Prev: Integer;
begin
  Result := False;
  if Length(FValue) = 0 then Exit;

  WS := BytePos;
  WE := BytePos;

  // If at a break char, try the char before
  if IsBreak(WE) then
  begin
    if WS <= 0 then Exit;
    WS := UTF8PrevCharPos(FValue, WS);
    if IsBreak(WS) then Exit;
    WE := WS;
  end;

  // Scan backward
  while WS > 0 do
  begin
    Prev := UTF8PrevCharPos(FValue, WS);
    if IsBreak(Prev) then Break;
    WS := Prev;
  end;

  // Scan forward
  while (WE < Length(FValue)) and not IsBreak(WE) do
    WE := UTF8NextCharPos(FValue, WE);

  Result := WS <> WE;
end;

procedure TPixieElTextBase.SelectWordAtCaret;
var
  WS, WE: Integer;
begin
  if FindWordBounds(FCaretPos, WS, WE) then
  begin
    FSelStart := WS;
    FSelEnd := WE;
    FCaretPos := WE;
    FCaretMoved := True;
  end;
end;

procedure TPixieElTextBase.ClearSelection;
begin
  FSelStart := -1;
  FSelEnd := -1;
end;

function TPixieElTextBase.HasSelection: Boolean;
begin
  Result := (FSelStart >= 0) and (FSelEnd >= 0) and
    (FSelStart <> FSelEnd);
end;

function TPixieElTextBase.GetSelectedText: string;
var
  Lo, Hi: Integer;
begin
  if not HasSelection then
    Exit('');
  Lo := Min(FSelStart, FSelEnd);
  Hi := Max(FSelStart, FSelEnd);
  Result := Copy(FValue, Lo + 1, Hi - Lo);
end;

// ---------------------------------------------------------------------------
// Focus / keyboard
// ---------------------------------------------------------------------------

procedure TPixieElTextBase.OnFocus;
begin
  // Caret is positioned by OnLButtonDown when clicking.
  // Only reset to end when focus comes from non-click (e.g. tab).
  if FSelStart < 0 then
    FCaretPos := Length(FValue);
end;

procedure TPixieElTextBase.OnBlur;
begin
  ClearSelection;
end;

function TPixieElTextBase.OnKeyDown(Key: Word;
  Shift: TShiftState): Boolean;
var
  ClipText: string;
begin
  Result := False;
  if IsDisabled then
    Exit;

  case Key of
    VK_LEFT:
    begin
      if ssCtrl in Shift then
        MoveCaretWord(-1, ssShift in Shift)
      else
        MoveCaret(-1, ssShift in Shift);
      Result := True;
    end;
    VK_RIGHT:
    begin
      if ssCtrl in Shift then
        MoveCaretWord(1, ssShift in Shift)
      else
        MoveCaret(1, ssShift in Shift);
      Result := True;
    end;
    VK_HOME:
    begin
      MoveCaretHome(ssShift in Shift);
      Result := True;
    end;
    VK_END:
    begin
      MoveCaretEnd(ssShift in Shift);
      Result := True;
    end;
    VK_BACK:
    begin
      DeleteChar(False);
      Result := True;
    end;
    VK_DELETE:
    begin
      DeleteChar(True);
      Result := True;
    end;
    Ord('A'):
      if ssCtrl in Shift then
      begin
        SelectAll;
        Result := True;
      end;
    Ord('C'):
      if (ssCtrl in Shift) and HasSelection and (not FPassword) then
      begin
        PixieClipboardSetText(GetSelectedText);
        Result := True;
      end;
    Ord('V'):
      if (ssCtrl in Shift) and (not FReadOnly) then
      begin
        ClipText := PixieClipboardGetText;
        if not FMultiLine then
        begin
          ClipText := StringReplace(ClipText, #13#10, ' ', [rfReplaceAll]);
          ClipText := StringReplace(ClipText, #10, ' ', [rfReplaceAll]);
          ClipText := StringReplace(ClipText, #13, ' ', [rfReplaceAll]);
        end;
        InsertText(ClipText);
        Result := True;
      end;
    Ord('X'):
      if (ssCtrl in Shift) and HasSelection and (not FReadOnly) and
         (not FPassword) then
      begin
        PixieClipboardSetText(GetSelectedText);
        SaveUndo;
        DeleteSelection;
        Result := True;
      end;
    Ord('Z'):
      if (ssCtrl in Shift) and FUndoSaved then
      begin
        FValue := FUndoValue;
        FCaretPos := FUndoCaret;
        FCaretMoved := True;
        FUndoSaved := False;
        ClearSelection;
        Result := True;
      end;
  end;
end;

function TPixieElTextBase.OnUTF8KeyPress(
  const UTF8Char: string): Boolean;
begin
  Result := False;
  if IsDisabled or FReadOnly then
    Exit;
  if (Length(UTF8Char) = 1) and (Byte(UTF8Char[1]) < 32) then
    Exit;
  InsertText(UTF8Char);
  Result := True;
end;

// ---------------------------------------------------------------------------
// Mouse
// ---------------------------------------------------------------------------

function TPixieElTextBase.OnLButtonDown: Boolean;
var
  Doc: TPixieDocument;
  LocalX, LocalY: TPixiePixel;
  Ri: TPixieRenderItem;
  SbX, SbW, ThumbY, ThumbH, MaxScrollY: TPixiePixel;
begin
  Result := inherited OnLButtonDown;
  if IsDisabled then
    Exit;

  FWordSelecting := False;
  FSbDragging := False;
  Doc := TPixieDocument(FDoc);
  Doc.SetFocus(Self);
  DocToLocal(Doc.LastMouseX, Doc.LastMouseY, LocalX, LocalY);

  // Clicking the scrollbar grabs the thumb (or jumps to the click) instead
  // of moving the text caret.
  Ri := TPixieRenderItem(GetRenderItem);
  if (Ri <> nil) and
     ScrollbarMetrics(Ri.Pos.Width, Ri.Pos.Height,
       SbX, SbW, ThumbY, ThumbH, MaxScrollY) and (LocalX >= SbX) then
  begin
    FSbDragging := True;
    if (LocalY >= ThumbY) and (LocalY < ThumbY + ThumbH) then
      FSbDragOffset := LocalY - ThumbY
    else
      FSbDragOffset := ThumbH / 2;
    ScrollToThumbTop(LocalY - FSbDragOffset, Ri.Pos.Width, Ri.Pos.Height);
    Exit(True);
  end;

  FCaretPos := ClickToCaret(LocalX, LocalY);
  FCaretMoved := True;
  ClearSelection;
  FSelStart := FCaretPos;
  Result := True;
end;

function TPixieElTextBase.OnLButtonDblClick: Boolean;
begin
  Result := False;
  if IsDisabled then Exit;
  SelectWordAtCaret;
  if HasSelection then
  begin
    FWordSelecting := True;
    FWordSelStart := FSelStart;
    FWordSelEnd := FSelEnd;
  end;
  Result := HasSelection;
end;

function TPixieElTextBase.OnMouseDrag(X, Y: TPixiePixel): Boolean;
var
  LocalX, LocalY: TPixiePixel;
  NewPos, WS, WE: Integer;
  Ri: TPixieRenderItem;
begin
  Result := False;
  if IsDisabled then
    Exit;

  DocToLocal(X, Y, LocalX, LocalY);

  if FSbDragging then
  begin
    Ri := TPixieRenderItem(GetRenderItem);
    if Ri <> nil then
      ScrollToThumbTop(LocalY - FSbDragOffset, Ri.Pos.Width, Ri.Pos.Height);
    Exit(True);
  end;

  NewPos := ClickToCaret(LocalX, LocalY);

  if FWordSelecting then
  begin
    // Extend selection by whole words from the anchor word
    if FindWordBounds(NewPos, WS, WE) then
    begin
      if NewPos < FWordSelStart then
      begin
        FSelStart := FWordSelEnd;
        FSelEnd := WS;
        FCaretPos := WS;
      end
      else
      begin
        FSelStart := FWordSelStart;
        FSelEnd := WE;
        FCaretPos := WE;
      end;
    end
    else
    begin
      // Dragged onto a break char — extend to that position
      if NewPos < FWordSelStart then
      begin
        FSelStart := FWordSelEnd;
        FSelEnd := NewPos;
        FCaretPos := NewPos;
      end
      else
      begin
        FSelStart := FWordSelStart;
        FSelEnd := NewPos;
        FCaretPos := NewPos;
      end;
    end;
    FCaretMoved := True;
    Result := True;
  end
  else if NewPos <> FCaretPos then
  begin
    FSelEnd := NewPos;
    FCaretPos := NewPos;
    FCaretMoved := True;
    Result := True;
  end;
end;

function TPixieElTextBase.CursorForPoint(DocX, DocY: TPixiePixel): string;
var
  LocalX, LocalY: TPixiePixel;
  Ri: TPixieRenderItem;
  SbX, SbW, ThumbY, ThumbH, MaxScrollY: TPixiePixel;
begin
  Ri := TPixieRenderItem(GetRenderItem);
  if (Ri <> nil) and DocToLocal(DocX, DocY, LocalX, LocalY) and
     ScrollbarMetrics(Ri.Pos.Width, Ri.Pos.Height,
       SbX, SbW, ThumbY, ThumbH, MaxScrollY) and (LocalX >= SbX) then
    Result := 'default'
  else
    Result := inherited CursorForPoint(DocX, DocY);
end;

procedure TPixieElTextBase.OnClick;
begin
  inherited OnClick;
end;

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

function TPixieElTextBase.AlignDX(const LineStr: string): TPixiePixel;
var
  Cv: TPixieCanvas;
  Ri: TPixieRenderItem;
  ContentW, LineW: TPixiePixel;
begin
  Result := 0;
  if not (FCss.TextAlign in
     [taRight, taCenter, taBlockRight, taBlockCenter]) then
    Exit;
  Cv := GetCanvas(Self);
  Ri := TPixieRenderItem(GetRenderItem);
  if (Cv = nil) or (Ri = nil) then
    Exit;
  ContentW := Ri.Pos.Width;
  LineW := Cv.MeasureText(LineStr, FCss.Font);
  // Overflowing text keeps the left origin so horizontal scroll can work.
  if LineW >= ContentW then
    Exit;
  case FCss.TextAlign of
    taRight, taBlockRight: Result := ContentW - LineW;
    taCenter, taBlockCenter: Result := (ContentW - LineW) / 2;
  end;
end;

procedure TPixieElTextBase.DrawContent(Cv: TObject;
  P: TPixiePosition; Pad: TPixieMargins;
  IsFocused: Boolean; Ri: Pointer);
var
  Canvas: TPixieCanvas;
  Cont: TPixieNativeContainer;
  BX, BY, BW, BH: TPixiePixel;
  BorderW: TPixiePixel;
  LineH, TextDY: TPixiePixel;
  SbX, SbW, ThumbY, ThumbH, MaxScrollY, ThumbRad: TPixiePixel;
  SbRad: TPixieBorderRadiuses;
  SbColor: TPixieWebColor;
  BorderColor, BgColor, TextColor, PlaceholderColor: TPixieWebColor;
  FocusColor: TPixieWebColor;
  SelColor, SelTextColor: TPixieWebColor;
  Rad: TPixieBorderRadiuses;
  ClipPos: TPixiePosition;
  ShowCaret: Boolean;
  NoRadius: TPixieBorderRadiuses;
  CaretPxX, CaretPxY: TPixiePixel;
  HasCssBorder, HasCssBg: Boolean;
  // Multiline vars
  NumLines, L: Integer;
  LineStr: string;
  LS, LE: Integer;
  SelLo, SelHi: Integer;
  SelStartPx, SelEndPx, LineY: TPixiePixel;
  SelLineStart, SelLineEnd: Integer;
  // Single-line vars
  Disp: string;
  // Caret alignment
  CaretLine, CaretCol: Integer;
  CaretDX: TPixiePixel;
begin
  Canvas := TPixieCanvas(Cv);
  Cont := GetNativeContainer(Self);
  LineH := LineAdvance;
  TextDY := (LineH - FCss.FontMetrics.Height) / 2;

  // Calculate padding box
  BX := P.X - Pad.Left;
  BY := P.Y - Pad.Top;
  BW := P.Width + Pad.Left + Pad.Right;
  BH := P.Height + Pad.Top + Pad.Bottom;

  // Detect explicit CSS border/background — check both computed values and
  // whether the cascade set the property at all (catches border:0 and
  // background:transparent which produce initial-like values).
  HasCssBorder := (FCss.CssBorders.Left.Style > bsHidden) or
    (Style.GetProperty(Ord(psid_border_left_style)).Kind <> pkInvalid);
  HasCssBg := (FCss.Bg.Color.Alpha > 0) or
    (Style.GetProperty(Ord(psid_background_color)).Kind <> pkInvalid);

  // Border colour — author CSS wins, else disabled/enabled defaults
  if HasCssBorder then
    BorderColor := FCss.CssBorders.Left.Color
  else if IsDisabled then
    BorderColor := TPixieWebColor.Create(204, 204, 204)
  else
    BorderColor := TPixieWebColor.Create(153, 153, 153);

  // Background colour — author CSS wins, else disabled/enabled defaults
  if HasCssBg then
    BgColor := FCss.Bg.Color
  else if IsDisabled then
    BgColor := TPixieWebColor.Create(245, 245, 245)
  else
    BgColor := TPixieWebColor.Create(255, 255, 255);

  // Text colour
  if IsDisabled then
    TextColor := TPixieWebColor.Create(153, 153, 153)
  else
    TextColor := FCss.Color;

  // Border radius — CSS or default 3px
  if not FCss.CssBorders.Radius.TopLeftX.IsPredefined then
    Rad := FCss.CssBorders.Radius.CalcPercents(BW, BH)
  else
  begin
    Rad.Init;
    Rad.TopLeftX := 3; Rad.TopLeftY := 3;
    Rad.TopRightX := 3; Rad.TopRightY := 3;
    Rad.BottomRightX := 3; Rad.BottomRightY := 3;
    Rad.BottomLeftX := 3; Rad.BottomLeftY := 3;
  end;

  // Border width
  if HasCssBorder then
    BorderW := Max(1, FCss.CssBorders.Left.Width.Val)
  else
    BorderW := 1;

  PlaceholderColor := TPixieWebColor.Create(153, 153, 153);
  SelColor := TPixieWebColor.Create(51, 102, 204);
  SelTextColor := TPixieWebColor.Create(255, 255, 255);
  FocusColor := TPixieWebColor.Create(0, 112, 201);

  // Draw border and background — skip when CSS handles it via DrawBackground
  if not (HasCssBorder or HasCssBg) or IsDisabled then
  begin
    if IsFocused and (not IsDisabled) then
    begin
      // Focused: 2px blue border replaces the default grey
      Canvas.FillRoundedRect(BX, BY, BW, BH, Rad, FocusColor);
      Canvas.FillRoundedRect(BX + 2, BY + 2, BW - 4, BH - 4,
        Rad, BgColor);
    end
    else
    begin
      Canvas.FillRoundedRect(BX, BY, BW, BH, Rad, BorderColor);
      Canvas.FillRoundedRect(BX + BorderW, BY + BorderW,
        BW - BorderW * 2, BH - BorderW * 2, Rad, BgColor);
    end;
  end;

  // Adjust scroll only when caret moved (not on wheel scroll)
  if FCaretMoved then
  begin
    AdjustScroll(P.Width, P.Height);
    FCaretMoved := False;
  end;

  // Clip to content area
  ClipPos := TPixiePosition.Create(P.X, P.Y, P.Width, P.Height);
  Canvas.SaveState;
  NoRadius.Init;
  Canvas.SetClipRect(ClipPos, NoRadius);

  if FMultiLine then
  begin
    // --- Multiline rendering ---
    NumLines := GetLineCount;

    if (FValue = '') and (FPlaceholder <> '') then
      Canvas.DrawText(FPlaceholder, FCss.Font, PlaceholderColor,
        P.X + AlignDX(FPlaceholder), P.Y + TextDY, P.Width, LineH)
    else
    begin
      if HasSelection and IsFocused then
      begin
        SelLo := Min(FSelStart, FSelEnd);
        SelHi := Max(FSelStart, FSelEnd);
      end
      else
      begin
        SelLo := -1;
        SelHi := -1;
      end;

      for L := 0 to NumLines - 1 do
      begin
        LineY := P.Y + L * LineH - FScrollY;
        // Skip lines outside visible area
        if LineY + LineH < P.Y then
          Continue;
        if LineY > P.Y + P.Height then
          Break;

        LS := GetLineStart(L);
        LE := GetLineEnd(L);
        LineStr := Copy(FValue, LS + 1, LE - LS);

        // Draw line text (normal colour)
        Canvas.DrawText(LineStr, FCss.Font, TextColor,
          P.X - FScrollX + AlignDX(LineStr), LineY + TextDY,
          P.Width + FScrollX + 100, LineH);

        // Draw selection highlight and white text on top
        if (SelLo >= 0) and (SelLo < LE) and (SelHi > LS) then
        begin
          SelLineStart := Max(SelLo, LS) - LS;
          SelLineEnd := Min(SelHi, LE) - LS;
          SelStartPx := Canvas.MeasureText(
            Copy(LineStr, 1, SelLineStart), FCss.Font);
          SelEndPx := Canvas.MeasureText(
            Copy(LineStr, 1, SelLineEnd), FCss.Font);
          if SelHi > LE then
            SelEndPx := SelEndPx + FCss.FontMetrics.ChWidth * 0.5;
          Canvas.FillRect(
            P.X + SelStartPx - FScrollX + AlignDX(LineStr), LineY,
            SelEndPx - SelStartPx, LineH, SelColor);
          // Redraw selected portion in white
          Canvas.DrawText(
            Copy(LineStr, SelLineStart + 1, SelLineEnd - SelLineStart),
            FCss.Font, SelTextColor,
            P.X + SelStartPx - FScrollX + AlignDX(LineStr), LineY + TextDY,
            SelEndPx - SelStartPx + 100, LineH);
        end;
      end;
    end;
  end
  else
  begin
    // --- Single-line rendering ---
    Disp := DisplayText;
    if (Disp = '') and (FPlaceholder <> '') then
      Canvas.DrawText(FPlaceholder, FCss.Font, PlaceholderColor,
        P.X + AlignDX(FPlaceholder), P.Y + TextDY, P.Width, LineH)
    else if Disp <> '' then
    begin
      // Draw full text in normal colour
      Canvas.DrawText(Disp, FCss.Font, TextColor,
        P.X - FScrollX + AlignDX(Disp), P.Y + TextDY,
        P.Width + FScrollX + 100, LineH);

      // Selection highlight + white text on top
      if HasSelection and IsFocused then
      begin
        SelLo := Min(FSelStart, FSelEnd);
        SelHi := Max(FSelStart, FSelEnd);
        if FPassword then
        begin
          SelStartPx := Canvas.MeasureText(
            Copy(Disp, 1, UTF8CharCount(Copy(FValue, 1, SelLo)) * 3),
            FCss.Font);
          SelEndPx := Canvas.MeasureText(
            Copy(Disp, 1, UTF8CharCount(Copy(FValue, 1, SelHi)) * 3),
            FCss.Font);
        end
        else
        begin
          SelStartPx := Canvas.MeasureText(
            Copy(Disp, 1, SelLo), FCss.Font);
          SelEndPx := Canvas.MeasureText(
            Copy(Disp, 1, SelHi), FCss.Font);
        end;
        Canvas.FillRect(
          P.X + SelStartPx - FScrollX + AlignDX(Disp), P.Y,
          SelEndPx - SelStartPx, LineH, SelColor);
        // Redraw selected portion in white
        if FPassword then
          Canvas.DrawText(
            Copy(Disp,
              UTF8CharCount(Copy(FValue, 1, SelLo)) * 3 + 1,
              (UTF8CharCount(Copy(FValue, 1, SelHi)) -
               UTF8CharCount(Copy(FValue, 1, SelLo))) * 3),
            FCss.Font, SelTextColor,
            P.X + SelStartPx - FScrollX + AlignDX(Disp), P.Y + TextDY,
            SelEndPx - SelStartPx + 100, LineH)
        else
          Canvas.DrawText(
            Copy(Disp, SelLo + 1, SelHi - SelLo),
            FCss.Font, SelTextColor,
            P.X + SelStartPx - FScrollX + AlignDX(Disp), P.Y + TextDY,
            SelEndPx - SelStartPx + 100, LineH);
      end;
    end;
  end;

  // Draw caret
  ShowCaret := IsFocused and (not IsDisabled) and
    (Cont <> nil) and Cont.CaretVisible;
  if ShowCaret then
  begin
    CaretToPixelXY(CaretPxX, CaretPxY);
    if FMultiLine then
    begin
      CaretToLineCol(CaretLine, CaretCol);
      CaretDX := AlignDX(GetLineText(CaretLine));
    end
    else
      CaretDX := AlignDX(DisplayText);
    Canvas.DrawLine(
      P.X + CaretPxX + CaretDX, P.Y + CaretPxY + TextDY + 1,
      P.X + CaretPxX + CaretDX, P.Y + CaretPxY + TextDY + FCss.FontMetrics.Height - 1,
      TextColor, 1);
  end;

  // Vertical scrollbar thumb when the content overflows
  if ScrollbarMetrics(P.Width, P.Height, SbX, SbW, ThumbY, ThumbH,
    MaxScrollY) then
  begin
    ThumbRad := (SbW - 4) / 2;
    SbRad.Init;
    SbRad.TopLeftX := ThumbRad;     SbRad.TopLeftY := ThumbRad;
    SbRad.TopRightX := ThumbRad;    SbRad.TopRightY := ThumbRad;
    SbRad.BottomRightX := ThumbRad; SbRad.BottomRightY := ThumbRad;
    SbRad.BottomLeftX := ThumbRad;  SbRad.BottomLeftY := ThumbRad;
    SbColor := TPixieWebColor.Create(160, 160, 160);
    Canvas.FillRoundedRect(P.X + SbX + 2, P.Y + ThumbY,
      SbW - 4, ThumbH, SbRad, SbColor);
  end;

  Canvas.RestoreState;
end;

procedure TPixieElTextBase.Draw(Hdc: PtrUInt; X, Y: TPixiePixel;
  Clip: PPixiePosition; Ri: Pointer);
var
  RenderIt: TPixieRenderItem;
  P: TPixiePosition;
  Pad: TPixieMargins;
  Cv: TPixieCanvas;
  IsFocused: Boolean;
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

  Pad := RenderIt.GetPaddings;
  IsFocused := FPseudoClasses.IndexOf(Ord(psid_focus)) >= 0;

  DrawContent(Cv, P, Pad, IsFocused, Ri);
end;

function TPixieElTextBase.CreateRenderItem(
  ParentRi: Pointer): Pointer;
var
  Ret: TPixieRenderInput;
begin
  Ret := TPixieRenderInput.Create(Self);
  Ret.SetParent(TPixieRenderItem(ParentRi));
  Result := Ret;
end;

{ TPixieElTextInput }

procedure TPixieElTextInput.ParseAttributes;
var
  TypeStr, MaxLenStr: string;
  Code: Integer;
begin
  TypeStr := LowerCase(GetAttr('type', 'text'));
  FPassword := TypeStr = 'password';
  FMultiLine := False;
  FValue := GetAttr('value', '');
  FPlaceholder := GetAttr('placeholder', '');
  MaxLenStr := GetAttr('maxlength', '');
  if MaxLenStr <> '' then
  begin
    Val(MaxLenStr, FMaxLength, Code);
    if Code <> 0 then
      FMaxLength := -1;
  end
  else
    FMaxLength := -1;
  inherited ParseAttributes;
end;

procedure TPixieElTextInput.GetContentSize(var Sz: TPixieSize;
  MaxWidth: TPixiePixel);
var
  Cv: TPixieCanvas;
  SizeAttr: string;
  CharCount, Code: Integer;
begin
  SizeAttr := GetAttr('size', '');
  if SizeAttr <> '' then
  begin
    Val(SizeAttr, CharCount, Code);
    if (Code <> 0) or (CharCount < 1) then
      CharCount := 20;
  end
  else
    CharCount := 20;

  Cv := GetCanvas(Self);
  if Cv <> nil then
    Sz.Width := Cv.MeasureText(StringOfChar('0', CharCount), FCss.Font)
  else
    Sz.Width := CharCount * FCss.FontMetrics.ChWidth;
  Sz.Height := FCss.IntrinsicLineHeight;
end;

function TPixieElTextInput.DumpGetName: string;
begin
  if FPassword then
    Result := 'input type="password"'
  else
    Result := 'input type="text"';
end;

{ TPixieElTextArea }

constructor TPixieElTextArea.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
  FMultiLine := True;
  FRows := 2;
  FCols := 20;
end;

procedure TPixieElTextArea.ParseAttributes;
var
  S: string;
  Code: Integer;
  I: Integer;
  Ch: TPixieElement;
begin
  S := GetAttr('rows', '');
  if S <> '' then
  begin
    Val(S, FRows, Code);
    if (Code <> 0) or (FRows < 1) then
      FRows := 2;
  end;
  S := GetAttr('cols', '');
  if S <> '' then
  begin
    Val(S, FCols, Code);
    if (Code <> 0) or (FCols < 1) then
      FCols := 20;
  end;

  // Value from child text content
  FValue := '';
  for I := 0 to Children.Count - 1 do
  begin
    Ch := Children[I];
    Ch.GetText(FValue);
  end;
  if (Length(FValue) > 0) and (FValue[1] = #10) then
    Delete(FValue, 1, 1);
  FPlaceholder := GetAttr('placeholder', '');
  inherited ParseAttributes;
end;

procedure TPixieElTextArea.GetContentSize(var Sz: TPixieSize;
  MaxWidth: TPixiePixel);
var
  Cv: TPixieCanvas;
begin
  Cv := GetCanvas(Self);
  if Cv <> nil then
    Sz.Width := Cv.MeasureText(StringOfChar('0', FCols), FCss.Font)
  else
    Sz.Width := FCols * FCss.FontMetrics.ChWidth;
  Sz.Height := FRows * LineAdvance;
end;

function TPixieElTextArea.OnKeyDown(Key: Word;
  Shift: TShiftState): Boolean;
var
  Line, Col: Integer;
  TargetLine: Integer;
  TargetLS, TargetLE: Integer;
  NewPos: Integer;
  Cv: TPixieCanvas;
  CurLineText: string;
  TargetLineText: string;
  CurXPx, TestPx: TPixiePixel;
  I, BestPos: Integer;
  BestDist, Dist: TPixiePixel;
  IsShift: Boolean;
begin
  IsShift := ssShift in Shift;

  case Key of
    VK_RETURN:
    begin
      if (not FReadOnly) and (not IsDisabled) then
      begin
        InsertText(#10);
        Result := True;
      end
      else
        Result := False;
    end;

    VK_UP, VK_DOWN:
    begin
      CaretToLineCol(Line, Col);

      if Key = VK_UP then
        TargetLine := Line - 1
      else
        TargetLine := Line + 1;

      if (TargetLine < 0) or (TargetLine >= GetLineCount) then
        Exit(True); // consume but do nothing at boundaries

      // Measure current X pixel position of caret within current line
      Cv := GetCanvas(Self);
      if Cv = nil then
        Exit(True);

      CurLineText := GetLineText(Line);
      CurXPx := Cv.MeasureText(Copy(CurLineText, 1, Col), FCss.Font);

      // Find closest byte position in target line
      TargetLS := GetLineStart(TargetLine);
      TargetLE := GetLineEnd(TargetLine);
      TargetLineText := Copy(FValue, TargetLS + 1, TargetLE - TargetLS);

      BestPos := 0;
      BestDist := Abs(CurXPx);
      I := 0;
      while I < Length(TargetLineText) do
      begin
        I := UTF8NextCharPos(TargetLineText, I);
        TestPx := Cv.MeasureText(Copy(TargetLineText, 1, I), FCss.Font);
        Dist := Abs(CurXPx - TestPx);
        if Dist < BestDist then
        begin
          BestDist := Dist;
          BestPos := I;
        end;
      end;

      NewPos := TargetLS + BestPos;

      if IsShift then
      begin
        if FSelStart < 0 then
          FSelStart := FCaretPos;
        FSelEnd := NewPos;
      end
      else
        ClearSelection;

      FCaretPos := NewPos;
      FCaretMoved := True;
      Result := True;
    end;

    VK_HOME:
    begin
      if ssCtrl in Shift then
      begin
        // Ctrl+Home = start of text
        NewPos := 0;
        if IsShift then
        begin
          if FSelStart < 0 then
            FSelStart := FCaretPos;
          FSelEnd := NewPos;
        end
        else
          ClearSelection;
        FCaretPos := NewPos;
        FCaretMoved := True;
      end
      else
        MoveCaretHome(IsShift);
      Result := True;
    end;

    VK_END:
    begin
      if ssCtrl in Shift then
      begin
        // Ctrl+End = end of text
        NewPos := Length(FValue);
        if IsShift then
        begin
          if FSelStart < 0 then
            FSelStart := FCaretPos;
          FSelEnd := NewPos;
        end
        else
          ClearSelection;
        FCaretPos := NewPos;
        FCaretMoved := True;
      end
      else
        MoveCaretEnd(IsShift);
      Result := True;
    end;
  else
    Result := inherited OnKeyDown(Key, Shift);
  end;
end;

function TPixieElTextArea.OnMouseWheel(Delta: Integer): Boolean;
var
  Ri: TPixieRenderItem;
  SbX, SbW, ThumbY, ThumbH, MaxScrollY: TPixiePixel;
begin
  Result := False;
  Ri := TPixieRenderItem(GetRenderItem);
  if (Ri = nil) or not ScrollbarMetrics(Ri.Pos.Width, Ri.Pos.Height,
    SbX, SbW, ThumbY, ThumbH, MaxScrollY) then
    Exit;

  if Delta > 0 then
    FScrollY := FScrollY - 3 * LineAdvance
  else
    FScrollY := FScrollY + 3 * LineAdvance;

  if FScrollY < 0 then
    FScrollY := 0;
  if FScrollY > MaxScrollY then
    FScrollY := MaxScrollY;

  Result := True;
end;

function TPixieElTextArea.DumpGetName: string;
begin
  Result := 'textarea';
end;

end.
