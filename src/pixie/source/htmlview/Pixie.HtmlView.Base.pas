unit Pixie.HtmlView.Base;

// TPixieHtmlViewBase — abstract Lazarus visual control that wraps the
// Pixie HTML rendering engine. Content-source-agnostic: provides paint,
// scrolling, mouse, keyboard, IME, and property forwarding, but exposes
// no public content loaders. Concrete subclasses (TPixieHtmlView,
// TPixieMarkdownView) decide which loaders to expose.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Math, Controls, Graphics, Forms, ExtCtrls,
  LMessages, LCLType, LCLIntf,
  Pixie.Types, Pixie.WebColor, Pixie.Document,
  Pixie.Canvas, Pixie.NativeContainer,
  Pixie.CustomControl, Pixie.HtmlView.Core
  {$IFDEF MSWINDOWS}
    , JwaWinUser
  {$ENDIF};

{$IF NOT DECLARED(LM_IM_QUERY)}
const
  LM_IM_QUERY = LM_IM_COMPOSITION + 1;
{$ENDIF}

type
  { TPixieHtmlViewBase }

  TPixieHtmlViewBase = class(TPixieCustomControl)
  private
    FCore: TPixieHtmlViewCore;
    FCaretTimer: TTimer;

    procedure DoCaretTimer(Sender: TObject);
    procedure CMShowingChanged(var Msg: TLMessage); message CM_SHOWINGCHANGED;
    {$IFDEF MSWINDOWS}
    procedure WMIMEStartComposition(var Msg: TLMessage); message WM_IME_STARTCOMPOSITION;
    {$ENDIF}
    {$IF DEFINED(LCLqt) or DEFINED(LCLqt5) or DEFINED(LCLqt6)}
    procedure LMIMQuery(var Msg: TLMessage); message LM_IM_QUERY;
    {$ENDIF}
    {$IFDEF WITH_GTK2_IM}
    procedure LMIMComposition(var Msg: TLMessage); message LM_IM_COMPOSITION;
    {$ENDIF}
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
    procedure DoPaint; override;
    procedure DoMouseLeave; override;
    procedure Loaded; override;
    procedure Resize; override;
    {$IF DEFINED(LCLGTK2) or DEFINED(LCLGTK3)}
    procedure DoEnter; override;
    procedure DoExit; override;
    {$ENDIF}
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
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
    property BorderSpacing;
    property BorderStyle default bsSingle;
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
  Clipbrd
  {$IFDEF MSWINDOWS}
  , Windows, imm
  {$ENDIF}
  {$IFDEF LCLGTK2}
  , Glib2, Gdk2, Gtk2
  {$IFDEF WITH_GTK2_IM}
  , Gtk2Globals
  {$ENDIF}
  {$ENDIF}
  {$IFDEF LCLGTK3}
  , LazGdk3, LazGtk3, LazGLib2, LazGObject2, Gtk3Widgets
  {$ENDIF};

const
  ssCtrlOS = {$IFDEF DARWIN}ssMeta{$ELSE}ssCtrl{$ENDIF};

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

constructor TPixieHtmlViewBase.Create(AOwner: TComponent);
begin
  FCore := nil;
  inherited Create(AOwner);
  BorderStyle := bsSingle;
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
  LCLIntf.InvalidateRect(Handle, @WinR, False);
end;

procedure TPixieHtmlViewBase.HostSetCursor(ACursor: TPixieCursorKind);
begin
  SetPixieCursor(ACursor);
end;

procedure TPixieHtmlViewBase.HostSetFocus;
begin
  SetFocus;
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

procedure TPixieHtmlViewBase.DoMouseLeave;
begin
  if FCore <> nil then
    FCore.HandleMouseLeave;
end;

// ---------------------------------------------------------------------------
// IME
// ---------------------------------------------------------------------------

{$IF DEFINED(LCLGTK2) or DEFINED(LCLGTK3)}
{$IFNDEF WITH_GTK2_IM}
var
  PixieGtkIMContext: PGtkIMContext = nil;
  PixieGtkIMEOwner: TPixieHtmlViewBase = nil;
{$ENDIF}
{$ENDIF}

procedure TPixieHtmlViewBase.UpdateIMEPosition;
var
  DocX, DocY, H: TPixiePixel;
  ClientX, ClientY: Integer;
  {$IFDEF MSWINDOWS}
  Imc: HIMC;
  CompForm: COMPOSITIONFORM;
  {$ENDIF}
  {$IF DEFINED(LCLGTK2) or DEFINED(LCLGTK3)}
  Area: TGdkRectangle;
  {$ENDIF}
begin
  if FCore.Document = nil then Exit;
  if not FCore.Document.GetFocusedCaretPos(DocX, DocY, H) then Exit;

  ClientX := Round(DocX * FCore.Zoom * GetScaleFactor);
  ClientY := Round((DocY - FCore.ScrollY) * FCore.Zoom * GetScaleFactor);

  {$IFDEF MSWINDOWS}
  Imc := ImmGetContext(Handle);
  if Imc <> 0 then
  begin
    CompForm.dwStyle := CFS_POINT;
    CompForm.ptCurrentPos.X := ClientX;
    CompForm.ptCurrentPos.Y := ClientY;
    ImmSetCompositionWindow(Imc, @CompForm);
    ImmReleaseContext(Handle, Imc);
  end;
  {$ENDIF}

  {$IF DEFINED(LCLGTK2) or DEFINED(LCLGTK3)}
  Area.x := ClientX;
  Area.y := ClientY;
  Area.width := 1;
  Area.height := Round(H * FCore.Zoom);
  {$IFDEF WITH_GTK2_IM}
  if im_context <> nil then
    gtk_im_context_set_cursor_location(im_context, @Area);
  {$ELSE}
  if PixieGtkIMContext <> nil then
    gtk_im_context_set_cursor_location(PixieGtkIMContext, @Area);
  {$ENDIF}
  {$ENDIF}
end;

{$IFDEF MSWINDOWS}
procedure TPixieHtmlViewBase.WMIMEStartComposition(var Msg: TLMessage);
begin
  inherited;
  UpdateIMEPosition;
end;
{$ENDIF}

{$IF DEFINED(LCLqt) or DEFINED(LCLqt5) or DEFINED(LCLqt6)}
procedure TPixieHtmlViewBase.LMIMQuery(var Msg: TLMessage);
var
  DocX, DocY, H: TPixiePixel;
  P: ^TPoint;
begin
  if (Msg.LParam <> 0) and (FCore.Document <> nil) and
     FCore.Document.GetFocusedCaretPos(DocX, DocY, H) then
  begin
    P := Pointer(Msg.LParam);
    P^.X := Round(DocX * FCore.Zoom);
    P^.Y := Round((DocY - FCore.ScrollY) * FCore.Zoom);
  end;
end;
{$ENDIF}

{$IFDEF WITH_GTK2_IM}
procedure TPixieHtmlViewBase.LMIMComposition(var Msg: TLMessage);
var
  S: string;
begin
  if (Msg.WParam and GTK_IM_FLAG_COMMIT) <> 0 then
  begin
    S := PChar(Msg.LParam);
    if FCore.HandleCharInput(S) then
      UpdateIMEPosition;
  end;
end;
{$ENDIF}

{$IF DEFINED(LCLGTK2) or DEFINED(LCLGTK3)}
{$IFNDEF WITH_GTK2_IM}
procedure PixieGtkIMCommitCb(Context: PGtkIMContext; Str: PGChar;
  Data: Pointer); cdecl;
var
  S: string;
begin
  if PixieGtkIMEOwner <> nil then
  begin
    S := Str;
    PixieGtkIMEOwner.FCore.HandleCharInput(S);
    PixieGtkIMEOwner.UpdateIMEPosition;
  end;
end;
{$ENDIF}
{$ENDIF}

{$IF DEFINED(LCLGTK2) or DEFINED(LCLGTK3)}
procedure TPixieHtmlViewBase.DoEnter;
{$IFNDEF WITH_GTK2_IM}
var
  GdkWin: PGdkWindow;
  ParentForm: TCustomForm;
{$ENDIF}
begin
  inherited;

  {$IFNDEF WITH_GTK2_IM}
  ParentForm := GetParentForm(Self);
  if ParentForm = nil then Exit;

  {$IFDEF LCLGTK2}
  GdkWin := PGtkWidget(ParentForm.Handle)^.window;
  {$ELSE}
  if TGtk3Widget(ParentForm.Handle) = nil then Exit;
  GdkWin := gtk_widget_get_window(TGtk3Widget(ParentForm.Handle).Widget);
  {$ENDIF}
  if GdkWin = nil then Exit;

  if PixieGtkIMContext = nil then
  begin
    PixieGtkIMContext := PGtkIMContext(gtk_im_multicontext_new());
    {$IFDEF LCLGTK2}
    g_signal_connect(PixieGtkIMContext, 'commit',
      TGCallback(@PixieGtkIMCommitCb), nil);
    {$ELSE}
    g_signal_connect_data(PixieGtkIMContext, 'commit',
      TGCallback(@PixieGtkIMCommitCb), nil, nil, G_CONNECT_DEFAULT);
    {$ENDIF}
  end;

  gtk_im_context_set_client_window(PixieGtkIMContext, GdkWin);
  gtk_im_context_focus_in(PixieGtkIMContext);
  PixieGtkIMEOwner := Self;
  {$ENDIF}

  UpdateIMEPosition;
end;

procedure TPixieHtmlViewBase.DoExit;
begin
  {$IFNDEF WITH_GTK2_IM}
  if PixieGtkIMContext <> nil then
  begin
    gtk_im_context_focus_out(PixieGtkIMContext);
    gtk_im_context_reset(PixieGtkIMContext);
  end;
  PixieGtkIMEOwner := nil;
  {$ENDIF}
  inherited;
end;
{$ENDIF}

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
  FCore.Canvas.SetViewSize(ClientWidth, ClientHeight, GetCanvasScaleFactor);
  Cr := Canvas.ClipRect;
  Upd := TPixiePosition.Create(Cr.Left, Cr.Top,
    Cr.Right - Cr.Left, Cr.Bottom - Cr.Top);
  FCore.HandlePaint(GetPaintHandle, Upd);
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

procedure TPixieHtmlViewBase.CMShowingChanged(var Msg: TLMessage);
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
  if FCore.HandleKeyDown(Key, Shift, ssCtrlOS in Shift) then
    Key := 0;
end;

procedure TPixieHtmlViewBase.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  inherited UTF8KeyPress(UTF8Key);
  if FCore.HandleCharInput(UTF8Key) then
    UTF8Key := '';
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
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then Exit;
  // MousePos is already in client pixels (LCL); HandleMouseWheel converts
  // to document coordinates itself (divides by the effective scale).
  Result := FCore.HandleMouseWheel(WheelDelta, ssCtrl in Shift,
    MousePos.X, MousePos.Y);
end;

end.
