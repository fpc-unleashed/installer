unit Pixie.TagBar;

// TPixieTagBar — Lazarus visual component for coloured tag pills.
// Thin wrapper around TPixieTagBarCore (Pixie.TagBar.Base), providing
// LCL integration: painting, mouse/keyboard, focus, caret timer.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Controls, Graphics, ExtCtrls,
  LCLType,
  Pixie.Types, Pixie.WebColor, Pixie.Canvas,
  Pixie.CustomControl, Pixie.TagBar.Base,
  Pixie.TagBar.Render;

type
  { TPixieTagBar }

  TPixieTagBar = class(TPixieCustomControl)
  private
    FCore: TPixieTagBarCore;
    FCaretTimer: TTimer;

    procedure DoCaretTimer(Sender: TObject);

    // Host callbacks
    procedure HostInvalidate;
    procedure HostSetCursor(ACursor: TPixieCursorKind);
    function HostGetViewWidth: Integer;
    function HostGetViewHeight: Integer;
    function HostGetScaleFactor: Single;
    function HostGetCanvasScaleFactor: Single;
    function HostGetBackgroundColor: TPixieWebColor;
    procedure HostSetFocus;
    function HostIsEnabled: Boolean;
    function HostIsFocused: Boolean;
    procedure HostSetViewHeight(H: Integer);
    procedure HostSetCaretTimerEnabled(AEnabled: Boolean);

    // Property forwarding
    function GetOptions: TPixieTagBarOptions;
    procedure SetOptions(Value: TPixieTagBarOptions);
    function GetTagShape: TPixieTagShape;
    procedure SetTagShape(Value: TPixieTagShape);
    function GetAutoHeight: Boolean;
    procedure SetAutoHeight(Value: Boolean);
    function GetScrollMode: TPixieTagBarScrollMode;
    procedure SetScrollMode(Value: TPixieTagBarScrollMode);
    function GetShowBorder: Boolean;
    procedure SetShowBorder(Value: Boolean);
    function GetBorderColor: TPixieWebColor;
    procedure SetBorderColor(const Value: TPixieWebColor);
    function GetFontFamily: string;
    procedure SetFontFamily(const Value: string);
    function GetFontSize: Single;
    procedure SetFontSize(Value: Single);
    function GetEmptyMessage: string;
    procedure SetEmptyMessage(const Value: string);
    function GetOnTagChecked: TPixieTagCheckedEvent;
    procedure SetOnTagChecked(Value: TPixieTagCheckedEvent);
    function GetOnChanged: TNotifyEvent;
    procedure SetOnChanged(Value: TNotifyEvent);
    function GetOnTagAdding: TPixieTagAddingEvent;
    procedure SetOnTagAdding(Value: TPixieTagAddingEvent);
    function GetOnTagDeleting: TPixieTagDeletingEvent;
    procedure SetOnTagDeleting(Value: TPixieTagDeletingEvent);
    function GetOnTagChanging: TPixieTagChangingEvent;
    procedure SetOnTagChanging(Value: TPixieTagChangingEvent);
  protected
    procedure DoPaint; override;
    procedure DoMouseLeave; override;
    procedure Loaded; override;
    procedure Resize; override;
    procedure DoExit; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // Tag management (forwarded to core)
    function AddTag(const Text: string): Integer; overload;
    function AddTag(const Text: string; Color: TPixieWebColor): Integer; overload;
    function AddTag(const Text: string; Color: TPixieWebColor;
      const ALeadIcon, ATrailIcon: string): Integer; overload;
    procedure DeleteTag(ID: Integer);
    procedure ClearTags;
    function FindTag(ID: Integer; out Tag: TPixieTagDef): Boolean;
    procedure UpdateTag(ID: Integer; const NewText: string;
      NewColor: TPixieWebColor); overload;
    procedure UpdateTag(ID: Integer; const NewText: string;
      NewColor: TPixieWebColor;
      const ALeadIcon, ATrailIcon: string); overload;
    function TagCount: Integer;
    function GetTag(Index: Integer): TPixieTagDef;

    // Selection (forwarded to core)
    procedure CheckTag(ID: Integer; AChecked: Boolean);
    procedure CheckAll;
    procedure UncheckAll;
    function IsChecked(ID: Integer): Boolean;
    function GetCheckedIDs: TArray<Integer>;
  public
    property BorderColor: TPixieWebColor read GetBorderColor write SetBorderColor;
  published
    property Options: TPixieTagBarOptions read GetOptions write SetOptions;
    property TagShape: TPixieTagShape read GetTagShape write SetTagShape
      default tsPill;
    property AutoHeight: Boolean read GetAutoHeight write SetAutoHeight
      default True;
    property ScrollMode: TPixieTagBarScrollMode
      read GetScrollMode write SetScrollMode default smAuto;
    property ShowBorder: Boolean read GetShowBorder write SetShowBorder
      default False;
    property FontFamily: string read GetFontFamily write SetFontFamily;
    property FontSize: Single read GetFontSize write SetFontSize;
    property EmptyMessage: string read GetEmptyMessage write SetEmptyMessage;

    property OnTagChecked: TPixieTagCheckedEvent
      read GetOnTagChecked write SetOnTagChecked;
    property OnChanged: TNotifyEvent
      read GetOnChanged write SetOnChanged;
    property OnTagAdding: TPixieTagAddingEvent
      read GetOnTagAdding write SetOnTagAdding;
    property OnTagDeleting: TPixieTagDeletingEvent
      read GetOnTagDeleting write SetOnTagDeleting;
    property OnTagChanging: TPixieTagChangingEvent
      read GetOnTagChanging write SetOnTagChanging;

    property Align;
    property Anchors;
    property BorderSpacing;
    property Color;
    property Constraints;
    property Enabled;
    property TabOrder;
    property TabStop;
    property Visible;

    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseMove;
    property OnMouseUp;
  end;

implementation

// =========================================================================
// Construction / destruction
// =========================================================================

constructor TPixieTagBar.Create(AOwner: TComponent);
begin
  FCore := nil;
  inherited Create(AOwner);
  Color := clWhite;
  Width := 300;
  Height := 36;

  FCore := TPixieTagBarCore.Create(PixieCanvas);
  FCore.OnHostInvalidate := HostInvalidate;
  FCore.OnHostSetCursor := HostSetCursor;
  FCore.OnHostGetViewWidth := HostGetViewWidth;
  FCore.OnHostGetViewHeight := HostGetViewHeight;
  FCore.OnHostGetScaleFactor := HostGetScaleFactor;
  FCore.OnHostGetCanvasScaleFactor := HostGetCanvasScaleFactor;
  FCore.OnHostGetBackgroundColor := HostGetBackgroundColor;
  FCore.OnHostSetFocus := HostSetFocus;
  FCore.OnHostIsEnabled := HostIsEnabled;
  FCore.OnHostIsFocused := HostIsFocused;
  FCore.OnHostSetViewHeight := HostSetViewHeight;
  FCore.OnHostSetCaretTimerEnabled := HostSetCaretTimerEnabled;

  FCaretTimer := TTimer.Create(Self);
  FCaretTimer.Interval := 530;
  FCaretTimer.OnTimer := DoCaretTimer;
  FCaretTimer.Enabled := False;
end;

destructor TPixieTagBar.Destroy;
begin
  FreeAndNil(FCaretTimer);
  FreeAndNil(FCore);
  inherited Destroy;
end;

// =========================================================================
// Host callbacks
// =========================================================================

procedure TPixieTagBar.HostInvalidate;
begin
  Invalidate;
end;

procedure TPixieTagBar.HostSetCursor(ACursor: TPixieCursorKind);
begin
  SetPixieCursor(ACursor);
end;

function TPixieTagBar.HostGetViewWidth: Integer;
begin
  Result := ClientWidth;
end;

function TPixieTagBar.HostGetViewHeight: Integer;
begin
  Result := ClientHeight;
end;

function TPixieTagBar.HostGetScaleFactor: Single;
begin
  Result := GetScaleFactor;
end;

function TPixieTagBar.HostGetCanvasScaleFactor: Single;
begin
  Result := GetCanvasScaleFactor;
end;

function TPixieTagBar.HostGetBackgroundColor: TPixieWebColor;
begin
  Result := GetBackgroundColor;
end;

procedure TPixieTagBar.HostSetFocus;
begin
  SetFocus;
end;

function TPixieTagBar.HostIsEnabled: Boolean;
begin
  Result := Enabled;
end;

function TPixieTagBar.HostIsFocused: Boolean;
begin
  Result := Focused;
end;

procedure TPixieTagBar.HostSetViewHeight(H: Integer);
begin
  ClientHeight := H;
end;

procedure TPixieTagBar.HostSetCaretTimerEnabled(AEnabled: Boolean);
begin
  FCaretTimer.Enabled := AEnabled;
end;

// =========================================================================
// Painting
// =========================================================================

procedure TPixieTagBar.DoPaint;
begin
  if FCore <> nil then
    FCore.HandlePaint(GetPaintHandle);
end;

// =========================================================================
// Mouse handling
// =========================================================================

procedure TPixieTagBar.DoMouseLeave;
begin
  if FCore <> nil then
    FCore.HandleMouseLeave;
end;

procedure TPixieTagBar.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  FCore.HandleMouseDown(Button = mbLeft, X, Y);
end;

procedure TPixieTagBar.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  FCore.HandleMouseMove(X, Y);
end;

procedure TPixieTagBar.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FCore.HandleMouseUp(Button = mbLeft, X, Y);
end;

function TPixieTagBar.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then Exit;
  Result := FCore.HandleMouseWheel(WheelDelta, ssShift in Shift);
end;

// =========================================================================
// Keyboard handling
// =========================================================================

procedure TPixieTagBar.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if FCore.HandleKeyDown(Key, Shift) then
    Key := 0;
end;

procedure TPixieTagBar.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  inherited UTF8KeyPress(UTF8Key);
  if FCore.HandleCharInput(UTF8Key) then
    UTF8Key := '';
end;

// =========================================================================
// Lifecycle
// =========================================================================

procedure TPixieTagBar.DoCaretTimer(Sender: TObject);
begin
  FCore.HandleCaretTimer;
end;

procedure TPixieTagBar.Loaded;
begin
  inherited Loaded;
  FCore.HandleLoaded;
end;

procedure TPixieTagBar.Resize;
begin
  inherited Resize;
  if FCore <> nil then
    FCore.HandleResize;
end;

procedure TPixieTagBar.DoExit;
begin
  FCore.HandleExit;
  inherited DoExit;
end;

// =========================================================================
// Property forwarding
// =========================================================================

function TPixieTagBar.GetOptions: TPixieTagBarOptions;
begin
  Result := FCore.Options;
end;

procedure TPixieTagBar.SetOptions(Value: TPixieTagBarOptions);
begin
  FCore.Options := Value;
end;

function TPixieTagBar.GetTagShape: TPixieTagShape;
begin
  Result := FCore.TagShape;
end;

procedure TPixieTagBar.SetTagShape(Value: TPixieTagShape);
begin
  FCore.TagShape := Value;
end;

function TPixieTagBar.GetAutoHeight: Boolean;
begin
  Result := FCore.AutoHeight;
end;

procedure TPixieTagBar.SetAutoHeight(Value: Boolean);
begin
  FCore.AutoHeight := Value;
end;

function TPixieTagBar.GetScrollMode: TPixieTagBarScrollMode;
begin
  Result := FCore.ScrollMode;
end;

procedure TPixieTagBar.SetScrollMode(Value: TPixieTagBarScrollMode);
begin
  FCore.ScrollMode := Value;
end;

function TPixieTagBar.GetShowBorder: Boolean;
begin
  Result := FCore.ShowBorder;
end;

procedure TPixieTagBar.SetShowBorder(Value: Boolean);
begin
  FCore.ShowBorder := Value;
  Invalidate;
end;

function TPixieTagBar.GetBorderColor: TPixieWebColor;
begin
  Result := FCore.BorderColor;
end;

procedure TPixieTagBar.SetBorderColor(const Value: TPixieWebColor);
begin
  FCore.BorderColor := Value;
  Invalidate;
end;

function TPixieTagBar.GetFontFamily: string;
begin
  Result := FCore.FontFamily;
end;

procedure TPixieTagBar.SetFontFamily(const Value: string);
begin
  FCore.FontFamily := Value;
end;

function TPixieTagBar.GetFontSize: Single;
begin
  Result := FCore.FontSize;
end;

procedure TPixieTagBar.SetFontSize(Value: Single);
begin
  FCore.FontSize := Value;
end;

function TPixieTagBar.GetEmptyMessage: string;
begin
  Result := FCore.EmptyMessage;
end;

procedure TPixieTagBar.SetEmptyMessage(const Value: string);
begin
  FCore.EmptyMessage := Value;
end;

function TPixieTagBar.GetOnTagChecked: TPixieTagCheckedEvent;
begin
  Result := FCore.OnTagChecked;
end;

procedure TPixieTagBar.SetOnTagChecked(Value: TPixieTagCheckedEvent);
begin
  FCore.OnTagChecked := Value;
end;

function TPixieTagBar.GetOnChanged: TNotifyEvent;
begin
  Result := FCore.OnChanged;
end;

procedure TPixieTagBar.SetOnChanged(Value: TNotifyEvent);
begin
  FCore.OnChanged := Value;
end;

function TPixieTagBar.GetOnTagAdding: TPixieTagAddingEvent;
begin
  Result := FCore.OnTagAdding;
end;

procedure TPixieTagBar.SetOnTagAdding(Value: TPixieTagAddingEvent);
begin
  FCore.OnTagAdding := Value;
end;

function TPixieTagBar.GetOnTagDeleting: TPixieTagDeletingEvent;
begin
  Result := FCore.OnTagDeleting;
end;

procedure TPixieTagBar.SetOnTagDeleting(Value: TPixieTagDeletingEvent);
begin
  FCore.OnTagDeleting := Value;
end;

function TPixieTagBar.GetOnTagChanging: TPixieTagChangingEvent;
begin
  Result := FCore.OnTagChanging;
end;

procedure TPixieTagBar.SetOnTagChanging(Value: TPixieTagChangingEvent);
begin
  FCore.OnTagChanging := Value;
end;

// =========================================================================
// Public API forwarding — Tag management
// =========================================================================

function TPixieTagBar.AddTag(const Text: string): Integer;
begin
  Result := FCore.AddTag(Text);
end;

function TPixieTagBar.AddTag(const Text: string;
  Color: TPixieWebColor): Integer;
begin
  Result := FCore.AddTag(Text, Color);
end;

function TPixieTagBar.AddTag(const Text: string; Color: TPixieWebColor;
  const ALeadIcon, ATrailIcon: string): Integer;
begin
  Result := FCore.AddTag(Text, Color, ALeadIcon, ATrailIcon);
end;

procedure TPixieTagBar.DeleteTag(ID: Integer);
begin
  FCore.DeleteTag(ID);
end;

procedure TPixieTagBar.ClearTags;
begin
  FCore.ClearTags;
end;

function TPixieTagBar.FindTag(ID: Integer; out Tag: TPixieTagDef): Boolean;
begin
  Result := FCore.FindTag(ID, Tag);
end;

procedure TPixieTagBar.UpdateTag(ID: Integer; const NewText: string;
  NewColor: TPixieWebColor);
begin
  FCore.UpdateTag(ID, NewText, NewColor);
end;

procedure TPixieTagBar.UpdateTag(ID: Integer; const NewText: string;
  NewColor: TPixieWebColor; const ALeadIcon, ATrailIcon: string);
begin
  FCore.UpdateTag(ID, NewText, NewColor, ALeadIcon, ATrailIcon);
end;

function TPixieTagBar.TagCount: Integer;
begin
  Result := FCore.TagCount;
end;

function TPixieTagBar.GetTag(Index: Integer): TPixieTagDef;
begin
  Result := FCore.GetTag(Index);
end;

// =========================================================================
// Public API forwarding — Selection
// =========================================================================

procedure TPixieTagBar.CheckTag(ID: Integer; AChecked: Boolean);
begin
  FCore.CheckTag(ID, AChecked);
end;

procedure TPixieTagBar.CheckAll;
begin
  FCore.CheckAll;
end;

procedure TPixieTagBar.UncheckAll;
begin
  FCore.UncheckAll;
end;

function TPixieTagBar.IsChecked(ID: Integer): Boolean;
begin
  Result := FCore.IsChecked(ID);
end;

function TPixieTagBar.GetCheckedIDs: TArray<Integer>;
begin
  Result := FCore.GetCheckedIDs;
end;

end.
