unit Pixie.HtmlView.VCL.Base;

// TPixieHtmlViewBase — abstract Delphi VCL visual control wrapping the
// Pixie HTML rendering engine. Content-source-agnostic: provides paint,
// scrolling, mouse, keyboard, IME, and property forwarding, but exposes
// no public content loaders. Concrete subclasses (TPixieHtmlView,
// TPixieMarkdownView) decide which loaders to expose.

interface

uses
  SysUtils, Classes, Math, Windows, Messages,
  Vcl.Controls, Vcl.Graphics, Vcl.Forms, Vcl.ExtCtrls,
  Pixie.Types, Pixie.WebColor, Pixie.Document,
  Pixie.Canvas, Pixie.NativeContainer,
  Pixie.CustomControl.VCL,
  Pixie.HtmlView.Core;

type
  { TPixieHtmlViewBase }

  TPixieHtmlViewBase = class(TPixieVclCustomControl)
  private
    FCore: TPixieHtmlViewCore;
    FCaretTimer: TTimer;
    FBorderStyle: TBorderStyle;

    procedure DoCaretTimer(Sender: TObject);
    procedure SetBorderStyle(Value: TBorderStyle);
    procedure CMShowingChanged(var Msg: TMessage); message CM_SHOWINGCHANGED;
    procedure WMGetDlgCode(var Msg: TWMGetDlgCode); message WM_GETDLGCODE;
    procedure WMIMEStartComposition(var Msg: TMessage); message WM_IME_STARTCOMPOSITION;
    procedure UpdateIMEPosition;

    // Host callbacks
    procedure HostInvalidate;
    procedure HostInvalidateRect(const R: TPixiePosition);
    procedure HostSetCursor(ACursor: TPixieCursorKind);
    procedure HostSetFocus;
    function HostGetViewWidth: TPixiePixel;
    function HostGetViewHeight: TPixiePixel;
    function HostGetScaleFactor: Single;
    function HostGetBackgroundColor: TPixieWebColor;
    procedure HostCopyToClipboard(const Text: string);
    function HostGetTickCount: UInt64;
    procedure HostResetCaret;
    procedure HostUpdateIME;

    // Property forwarding
    function GetDocument: TPixieDocument;
    function GetContentHeight: TPixiePixel;
    function GetScrollY: TPixiePixel;
    procedure SetScrollY(Value: TPixiePixel);
    function GetBaseUrl: string;
    procedure SetBaseUrl(const Value: string);
    function GetUserCss: string;
    procedure SetUserCss(const Value: string);
    function GetZoom: Double;
    procedure SetZoom(const Value: Double);
    function GetColorScheme: TPixieColorScheme;
    procedure SetColorScheme(Value: TPixieColorScheme);
    function GetScrollbar: TPixieScrollbarSettings;
    function GetAutoScrollSpeed: Integer;
    procedure SetAutoScrollSpeed(Value: Integer);
    function GetAutoScrollEdge: Integer;
    procedure SetAutoScrollEdge(Value: Integer);
    function GetAutoScrollAccelThreshold: Integer;
    procedure SetAutoScrollAccelThreshold(Value: Integer);
    function GetAutoScrollAccelMax: Integer;
    procedure SetAutoScrollAccelMax(Value: Integer);
    function GetOnAnchorClick: TPixieAnchorClickEvent;
    procedure SetOnAnchorClick(Value: TPixieAnchorClickEvent);
    function GetOnElementClick: TPixieElementClickEvent;
    procedure SetOnElementClick(Value: TPixieElementClickEvent);
    function GetOnFetchUrl: TPixieFetchUrlEvent;
    procedure SetOnFetchUrl(Value: TPixieFetchUrlEvent);
    function GetOnBeforeParse: TNotifyEvent;
    procedure SetOnBeforeParse(Value: TNotifyEvent);
    function GetOnAfterParse: TNotifyEvent;
    procedure SetOnAfterParse(Value: TNotifyEvent);
    function GetOnBeforePaint: TNotifyEvent;
    procedure SetOnBeforePaint(Value: TNotifyEvent);
    function GetOnAfterPaint: TNotifyEvent;
    procedure SetOnAfterPaint(Value: TNotifyEvent);
    function GetOnScrollChanged: TNotifyEvent;
    procedure SetOnScrollChanged(Value: TNotifyEvent);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Loaded; override;
    procedure DoPaint; override;
    procedure DoMouseLeave; override;
    procedure Resize; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyPress(var Key: Char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;

    // Loaders — protected so leaves choose which to publish/expose
    procedure CoreLoadFromString(const AHtml: string;
      const ABaseUrl: string = '');
    procedure CoreLoadFromFile(const AFileName: string;
      const ABaseUrl: string = '');
    procedure CoreLoadFromStream(AStream: TStream;
      const ABaseUrl: string = '');

    // Image export — protected so leaves expose the appropriate names
    procedure CoreSaveAsPng(const FileName: string;
      Width: Integer; Height: Integer = 0); overload;
    procedure CoreSaveAsPng(Stream: TStream;
      Width: Integer; Height: Integer = 0); overload;
    procedure CoreSaveAsBmp(const FileName: string;
      Width: Integer; Height: Integer = 0); overload;
    procedure CoreSaveAsBmp(Stream: TStream;
      Width: Integer; Height: Integer = 0); overload;

    // Lines accessor — protected so leaves can publish the property
    function GetLines: TStrings;
    procedure SetLines(const Value: TStrings);

    property Core: TPixieHtmlViewCore read FCore;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure RegisterImage(const Name: string; Stream: TStream);
    procedure UnregisterImage(const Name: string);

    property Document: TPixieDocument read GetDocument;
    property Scrollbar: TPixieScrollbarSettings read GetScrollbar;
    property ContentHeight: TPixiePixel read GetContentHeight;
    property ScrollY: TPixiePixel read GetScrollY write SetScrollY;
    property AutoScrollSpeed: Integer read GetAutoScrollSpeed
      write SetAutoScrollSpeed;
    property AutoScrollEdge: Integer read GetAutoScrollEdge
      write SetAutoScrollEdge;
    property AutoScrollAccelThreshold: Integer read GetAutoScrollAccelThreshold
      write SetAutoScrollAccelThreshold;
    property AutoScrollAccelMax: Integer read GetAutoScrollAccelMax
      write SetAutoScrollAccelMax;
  published
    property BorderStyle: TBorderStyle read FBorderStyle
      write SetBorderStyle default bsSingle;
    property TabOrder;
    property TabStop;
    property BaseUrl: string read GetBaseUrl write SetBaseUrl;
    property UserCss: string read GetUserCss write SetUserCss;
    property Zoom: Double read GetZoom write SetZoom;
    property ColorScheme: TPixieColorScheme read GetColorScheme
      write SetColorScheme default pcsAuto;
    property OnAnchorClick: TPixieAnchorClickEvent
      read GetOnAnchorClick write SetOnAnchorClick;
    property OnElementClick: TPixieElementClickEvent
      read GetOnElementClick write SetOnElementClick;
    property OnFetchUrl: TPixieFetchUrlEvent
      read GetOnFetchUrl write SetOnFetchUrl;
    property OnBeforeParse: TNotifyEvent
      read GetOnBeforeParse write SetOnBeforeParse;
    property OnAfterParse: TNotifyEvent
      read GetOnAfterParse write SetOnAfterParse;
    property OnBeforePaint: TNotifyEvent
      read GetOnBeforePaint write SetOnBeforePaint;
    property OnAfterPaint: TNotifyEvent
      read GetOnAfterPaint write SetOnAfterPaint;
    property OnScrollChanged: TNotifyEvent
      read GetOnScrollChanged write SetOnScrollChanged;

    property Align;
    property Anchors;
    property Color;
    property Constraints;
    property Enabled;
    property PopupMenu;
    property Visible;

    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseMove;
    property OnMouseUp;
    property OnMouseWheel;
    property OnResize;
  end;

implementation

uses
  Vcl.Clipbrd, Winapi.Imm;

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

constructor TPixieHtmlViewBase.Create(AOwner: TComponent);
begin
  FCore := nil;
  inherited Create(AOwner);
  FBorderStyle := bsSingle;
  Color := clWhite;
  Width := 400;
  Height := 300;

  FCore := TPixieHtmlViewCore.Create(PixieCanvas);
  FCore.Owner := Self;
  FCore.OnHostInvalidate := HostInvalidate;
  FCore.OnHostInvalidateRect := HostInvalidateRect;
  FCore.OnHostSetCursor := HostSetCursor;
  FCore.OnHostSetFocus := HostSetFocus;
  FCore.OnHostGetViewWidth := HostGetViewWidth;
  FCore.OnHostGetViewHeight := HostGetViewHeight;
  FCore.OnHostGetScaleFactor := HostGetScaleFactor;
  FCore.OnHostGetBackgroundColor := HostGetBackgroundColor;
  FCore.OnHostCopyToClipboard := HostCopyToClipboard;
  FCore.OnHostGetTickCount := HostGetTickCount;
  FCore.OnHostResetCaret := HostResetCaret;
  FCore.OnHostUpdateIME := HostUpdateIME;

  FCaretTimer := TTimer.Create(Self);
  FCaretTimer.Interval := 530;
  FCaretTimer.OnTimer := DoCaretTimer;
  FCaretTimer.Enabled := True;
end;

destructor TPixieHtmlViewBase.Destroy;
begin
  FreeAndNil(FCaretTimer);
  FreeAndNil(FCore);
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Border style
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewBase.SetBorderStyle(Value: TBorderStyle);
begin
  if FBorderStyle <> Value then
  begin
    FBorderStyle := Value;
    RecreateWnd;
  end;
end;

procedure TPixieHtmlViewBase.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  if FBorderStyle = bsSingle then
    Params.ExStyle := Params.ExStyle or WS_EX_CLIENTEDGE;
end;

// ---------------------------------------------------------------------------
// Host callbacks
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewBase.HostInvalidate;
begin
  Invalidate;
end;

procedure TPixieHtmlViewBase.HostInvalidateRect(const R: TPixiePosition);
var
  WinR: TRect;
begin
  if not HandleAllocated then Exit;
  WinR.Left := Floor(R.X);
  WinR.Top := Floor(R.Y);
  WinR.Right := Ceil(R.X + R.Width);
  WinR.Bottom := Ceil(R.Y + R.Height);
  Windows.InvalidateRect(Handle, @WinR, False);
end;

procedure TPixieHtmlViewBase.HostSetCursor(ACursor: TPixieCursorKind);
begin
  SetPixieCursor(ACursor);
end;

function TPixieHtmlViewBase.HostGetViewWidth: TPixiePixel;
begin
  Result := ClientWidth;
end;

function TPixieHtmlViewBase.HostGetViewHeight: TPixiePixel;
begin
  Result := ClientHeight;
end;

function TPixieHtmlViewBase.HostGetScaleFactor: Single;
begin
  Result := GetScaleFactor;
end;

function TPixieHtmlViewBase.HostGetBackgroundColor: TPixieWebColor;
begin
  Result := GetBackgroundColor;
end;

procedure TPixieHtmlViewBase.HostSetFocus;
begin
  if CanFocus then
    SetFocus;
end;

procedure TPixieHtmlViewBase.HostCopyToClipboard(const Text: string);
begin
  Clipboard.AsText := Text;
end;

function TPixieHtmlViewBase.HostGetTickCount: UInt64;
begin
  Result := GetTickCount64;
end;

procedure TPixieHtmlViewBase.HostResetCaret;
begin
  FCaretTimer.Enabled := False;
  FCaretTimer.Enabled := True;
end;

procedure TPixieHtmlViewBase.HostUpdateIME;
begin
  UpdateIMEPosition;
end;

// ---------------------------------------------------------------------------
// Property forwarding
// ---------------------------------------------------------------------------

function TPixieHtmlViewBase.GetDocument: TPixieDocument;
begin
  Result := FCore.Document;
end;

function TPixieHtmlViewBase.GetContentHeight: TPixiePixel;
begin
  Result := FCore.ContentHeight;
end;

function TPixieHtmlViewBase.GetScrollY: TPixiePixel;
begin
  Result := FCore.ScrollY;
end;

procedure TPixieHtmlViewBase.SetScrollY(Value: TPixiePixel);
begin
  FCore.ScrollY := Value;
end;

function TPixieHtmlViewBase.GetLines: TStrings;
begin
  Result := FCore.Lines;
end;

procedure TPixieHtmlViewBase.SetLines(const Value: TStrings);
begin
  FCore.Lines := Value;
end;

function TPixieHtmlViewBase.GetBaseUrl: string;
begin
  Result := FCore.BaseUrl;
end;

procedure TPixieHtmlViewBase.SetBaseUrl(const Value: string);
begin
  FCore.BaseUrl := Value;
end;

function TPixieHtmlViewBase.GetUserCss: string;
begin
  Result := FCore.UserCss;
end;

procedure TPixieHtmlViewBase.SetUserCss(const Value: string);
begin
  FCore.UserCss := Value;
end;

function TPixieHtmlViewBase.GetZoom: Double;
begin
  Result := FCore.Zoom;
end;

function TPixieHtmlViewBase.GetScrollbar: TPixieScrollbarSettings;
begin
  Result := FCore.Scrollbar;
end;

procedure TPixieHtmlViewBase.SetZoom(const Value: Double);
begin
  FCore.Zoom := Value;
end;

function TPixieHtmlViewBase.GetColorScheme: TPixieColorScheme;
begin
  Result := FCore.ColorScheme;
end;

procedure TPixieHtmlViewBase.SetColorScheme(Value: TPixieColorScheme);
begin
  FCore.ColorScheme := Value;
end;

function TPixieHtmlViewBase.GetAutoScrollSpeed: Integer;
begin
  Result := FCore.AutoScrollSpeed;
end;

procedure TPixieHtmlViewBase.SetAutoScrollSpeed(Value: Integer);
begin
  FCore.AutoScrollSpeed := Value;
end;

function TPixieHtmlViewBase.GetAutoScrollEdge: Integer;
begin
  Result := FCore.AutoScrollEdge;
end;

procedure TPixieHtmlViewBase.SetAutoScrollEdge(Value: Integer);
begin
  FCore.AutoScrollEdge := Value;
end;

function TPixieHtmlViewBase.GetAutoScrollAccelThreshold: Integer;
begin
  Result := FCore.AutoScrollAccelThreshold;
end;

procedure TPixieHtmlViewBase.SetAutoScrollAccelThreshold(Value: Integer);
begin
  FCore.AutoScrollAccelThreshold := Value;
end;

function TPixieHtmlViewBase.GetAutoScrollAccelMax: Integer;
begin
  Result := FCore.AutoScrollAccelMax;
end;

procedure TPixieHtmlViewBase.SetAutoScrollAccelMax(Value: Integer);
begin
  FCore.AutoScrollAccelMax := Value;
end;

function TPixieHtmlViewBase.GetOnAnchorClick: TPixieAnchorClickEvent;
begin
  Result := FCore.OnAnchorClick;
end;

procedure TPixieHtmlViewBase.SetOnAnchorClick(Value: TPixieAnchorClickEvent);
begin
  FCore.OnAnchorClick := Value;
end;

function TPixieHtmlViewBase.GetOnElementClick: TPixieElementClickEvent;
begin
  Result := FCore.OnElementClick;
end;

procedure TPixieHtmlViewBase.SetOnElementClick(Value: TPixieElementClickEvent);
begin
  FCore.OnElementClick := Value;
end;

function TPixieHtmlViewBase.GetOnFetchUrl: TPixieFetchUrlEvent;
begin
  Result := FCore.OnFetchUrl;
end;

procedure TPixieHtmlViewBase.SetOnFetchUrl(Value: TPixieFetchUrlEvent);
begin
  FCore.OnFetchUrl := Value;
end;

function TPixieHtmlViewBase.GetOnBeforeParse: TNotifyEvent;
begin
  Result := FCore.OnBeforeParse;
end;

procedure TPixieHtmlViewBase.SetOnBeforeParse(Value: TNotifyEvent);
begin
  FCore.OnBeforeParse := Value;
end;

function TPixieHtmlViewBase.GetOnAfterParse: TNotifyEvent;
begin
  Result := FCore.OnAfterParse;
end;

procedure TPixieHtmlViewBase.SetOnAfterParse(Value: TNotifyEvent);
begin
  FCore.OnAfterParse := Value;
end;

function TPixieHtmlViewBase.GetOnBeforePaint: TNotifyEvent;
begin
  Result := FCore.OnBeforePaint;
end;

procedure TPixieHtmlViewBase.SetOnBeforePaint(Value: TNotifyEvent);
begin
  FCore.OnBeforePaint := Value;
end;

function TPixieHtmlViewBase.GetOnAfterPaint: TNotifyEvent;
begin
  Result := FCore.OnAfterPaint;
end;

procedure TPixieHtmlViewBase.SetOnAfterPaint(Value: TNotifyEvent);
begin
  FCore.OnAfterPaint := Value;
end;

function TPixieHtmlViewBase.GetOnScrollChanged: TNotifyEvent;
begin
  Result := FCore.OnScrollChanged;
end;

procedure TPixieHtmlViewBase.SetOnScrollChanged(Value: TNotifyEvent);
begin
  FCore.OnScrollChanged := Value;
end;

// ---------------------------------------------------------------------------
// Loaders (protected — leaves expose what they need)
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewBase.CoreLoadFromString(const AHtml: string;
  const ABaseUrl: string);
begin
  FCore.LoadFromString(AHtml, ABaseUrl);
end;

procedure TPixieHtmlViewBase.CoreLoadFromFile(const AFileName: string;
  const ABaseUrl: string);
begin
  FCore.LoadFromFile(AFileName, ABaseUrl);
end;

procedure TPixieHtmlViewBase.CoreLoadFromStream(AStream: TStream;
  const ABaseUrl: string);
begin
  FCore.LoadFromStream(AStream, ABaseUrl);
end;

procedure TPixieHtmlViewBase.CoreSaveAsPng(const FileName: string;
  Width, Height: Integer);
begin
  FCore.SaveAsPng(FileName, Width, Height);
end;

procedure TPixieHtmlViewBase.CoreSaveAsPng(Stream: TStream;
  Width, Height: Integer);
begin
  FCore.SaveAsPng(Stream, Width, Height);
end;

procedure TPixieHtmlViewBase.CoreSaveAsBmp(const FileName: string;
  Width, Height: Integer);
begin
  FCore.SaveAsBmp(FileName, Width, Height);
end;

procedure TPixieHtmlViewBase.CoreSaveAsBmp(Stream: TStream;
  Width, Height: Integer);
begin
  FCore.SaveAsBmp(Stream, Width, Height);
end;

procedure TPixieHtmlViewBase.RegisterImage(const Name: string; Stream: TStream);
begin
  FCore.RegisterImage(Name, Stream);
end;

procedure TPixieHtmlViewBase.UnregisterImage(const Name: string);
begin
  FCore.UnregisterImage(Name);
end;

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewBase.WMGetDlgCode(var Msg: TWMGetDlgCode);
begin
  inherited;
  Msg.Result := Msg.Result or DLGC_WANTARROWS or DLGC_WANTTAB;
end;

// ---------------------------------------------------------------------------
// IME
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewBase.UpdateIMEPosition;
var
  DocX, DocY, H: TPixiePixel;
  Imc: HIMC;
  CompForm: TCompositionForm;
begin
  if FCore.Document = nil then Exit;
  if not FCore.Document.GetFocusedCaretPos(DocX, DocY, H) then Exit;

  Imc := ImmGetContext(Handle);
  if Imc <> 0 then
  begin
    CompForm.dwStyle := CFS_POINT;
    CompForm.ptCurrentPos.X := Round(DocX * FCore.Zoom * GetScaleFactor);
    CompForm.ptCurrentPos.Y := Round((DocY - FCore.ScrollY) * FCore.Zoom * GetScaleFactor);
    ImmSetCompositionWindow(Imc, @CompForm);
    ImmReleaseContext(Handle, Imc);
  end;
end;

procedure TPixieHtmlViewBase.WMIMEStartComposition(var Msg: TMessage);
begin
  inherited;
  UpdateIMEPosition;
end;

// ---------------------------------------------------------------------------
// Painting and layout
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewBase.Loaded;
begin
  inherited Loaded;
  FCore.HandleLoaded;
end;

procedure TPixieHtmlViewBase.DoPaint;
var
  Cr: TRect;
  Upd: TPixiePosition;
begin
  if FCore = nil then Exit;
  FCore.Canvas.SetViewSize(ClientWidth, ClientHeight, 1.0);
  Cr := Canvas.ClipRect;
  Upd := TPixiePosition.Create(Cr.Left, Cr.Top,
    Cr.Right - Cr.Left, Cr.Bottom - Cr.Top);
  FCore.HandlePaint(GetPaintHandle, Upd);
end;

procedure TPixieHtmlViewBase.DoMouseLeave;
begin
  if FCore <> nil then
    FCore.HandleMouseLeave;
end;

procedure TPixieHtmlViewBase.Resize;
begin
  inherited Resize;
  if FCore <> nil then
    FCore.HandleResize;
end;

// ---------------------------------------------------------------------------
// Caret timer
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewBase.DoCaretTimer(Sender: TObject);
begin
  FCore.HandleCaretTimer;
end;

procedure TPixieHtmlViewBase.CMShowingChanged(var Msg: TMessage);
begin
  inherited;
  if FCore = nil then Exit;
  // Showing is the composite (Visible AND parent-showing AND form-
  // showing), which catches tab-switch, form-minimise, and explicit
  // `.Visible := False` in one event — no need for CMVisibleChanged.
  if Showing then
    FCore.ResumeAnimations
  else
    FCore.PauseAnimations;
end;

// ---------------------------------------------------------------------------
// Keyboard
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewBase.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if FCore.HandleKeyDown(Key, Shift, ssCtrl in Shift) then
    Key := 0;
end;

procedure TPixieHtmlViewBase.KeyPress(var Key: Char);
var
  S: string;
begin
  inherited KeyPress(Key);
  if Ord(Key) >= 32 then
  begin
    S := Key;
    if FCore.HandleCharInput(S) then
      Key := #0;
  end;
end;

// ---------------------------------------------------------------------------
// Mouse
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewBase.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  FCore.HandleMouseDown(Button = mbLeft, ssDouble in Shift, X, Y);
end;

procedure TPixieHtmlViewBase.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  FCore.HandleMouseMove(X, Y);
end;

procedure TPixieHtmlViewBase.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FCore.HandleMouseUp(Button = mbLeft, X, Y);
end;

function TPixieHtmlViewBase.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  ClientPos: TPoint;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then Exit;
  // VCL delivers MousePos in screen coordinates; convert to client pixels.
  // HandleMouseWheel maps to document coordinates (divides by the scale).
  ClientPos := ScreenToClient(MousePos);
  Result := FCore.HandleMouseWheel(WheelDelta, ssCtrl in Shift,
    ClientPos.X, ClientPos.Y);
end;

end.
