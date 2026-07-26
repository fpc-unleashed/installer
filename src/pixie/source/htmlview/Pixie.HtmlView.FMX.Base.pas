unit Pixie.HtmlView.FMX.Base;

// TPixieHtmlViewBase — abstract Delphi FMX visual control wrapping the
// Pixie HTML rendering engine. Content-source-agnostic: provides paint,
// scrolling, mouse, keyboard, IME, and property forwarding, but exposes
// no public content loaders. Concrete subclasses (TPixieHtmlView,
// TPixieMarkdownView) decide which loaders to expose.

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  System.Rtti,
  FMX.Controls, FMX.Graphics, FMX.Types, FMX.Platform,
  FMX.Text, FMX.Forms,
  Pixie.Types, Pixie.WebColor, Pixie.Document,
  Pixie.Canvas, Pixie.NativeContainer,
  Pixie.CustomControl.FMX,
  Pixie.HtmlView.Core;

type
  { TPixieHtmlViewBase }

  TPixieHtmlViewBase = class(TPixieFmxCustomControl, ITextInput)
  private
    FCore: TPixieHtmlViewCore;
    FCaretTimer: TTimer;
    FTextService: TTextService;
    FLastMouseX: Single;
    FLastMouseY: Single;

    procedure DoCaretTimer(Sender: TObject);
    procedure ClipboardCopy(const S: string);

    // ITextInput
    function GetTextService: TTextService;
    function GetTargetClausePointF: TPointF;
    procedure StartIMEInput;
    procedure EndIMEInput;
    procedure IMEStateUpdated;
    function GetSelection: string;
    function GetSelectionRect: TRectF;
    function GetSelectionBounds: TRect;
    function GetSelectionPointSize: TSizeF;
    function HasText: Boolean;

    // Host callbacks
    procedure HostInvalidate;
    procedure HostInvalidateRect(const R: TPixiePosition);
    procedure HostSetCursor(ACursor: TPixieCursorKind);
    procedure HostSetFocus;
    function HostGetViewWidth: TPixiePixel;
    function HostGetViewHeight: TPixiePixel;
    function HostGetBackgroundColor: TPixieWebColor;
    procedure HostCopyToClipboard(const Text: string);
    function HostGetTickCount: UInt64;
    procedure HostResetCaret;

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
    procedure Loaded; override;
    procedure DoPaint; override;
    procedure DoMouseLeave; override;
    procedure Resize; override;
    procedure VisibleChanged; override;
    procedure DialogKey(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure KeyDown(var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer;
      var Handled: Boolean); override;

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
    property ClipChildren default True;
    property ClipParent default False;
    property Enabled;
    property Height;
    property HitTest default True;
    property Locked default False;
    property Margins;
    property Opacity;
    property Padding;
    property PopupMenu;
    property Position;
    property RotationAngle;
    property RotationCenter;
    property Scale;
    property Size;
    property TabOrder;
    property Visible;
    property Width;

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

// ---------------------------------------------------------------------------
// Clipboard helpers via FMX platform services
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewBase.ClipboardCopy(const S: string);
var
  Svc: IFMXClipboardService;
begin
  if TPlatformServices.Current.SupportsPlatformService(
    IFMXClipboardService, Svc) then
    Svc.SetClipboard(TValue.From<string>(S));
end;

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

constructor TPixieHtmlViewBase.Create(AOwner: TComponent);
var
  TextSvc: IFMXTextService;
begin
  FCore := nil;
  FTextService := nil;
  FLastMouseX := 0;
  FLastMouseY := 0;

  inherited Create(AOwner);
  ClipChildren := True;
  AutoCapture := True;
  Width := 400;
  Height := 300;
  CanFocus := True;

  if not (csDesigning in ComponentState) then
    if TPlatformServices.Current.SupportsPlatformService(
      IFMXTextService, TextSvc) then
      FTextService := TextSvc.GetTextServiceClass.Create(Self, False);

  FCore := TPixieHtmlViewCore.Create(PixieCanvas);
  FCore.Owner := Self;
  FCore.OnHostInvalidate := HostInvalidate;
  FCore.OnHostInvalidateRect := HostInvalidateRect;
  FCore.OnHostSetCursor := HostSetCursor;
  FCore.OnHostSetFocus := HostSetFocus;
  FCore.OnHostGetViewWidth := HostGetViewWidth;
  FCore.OnHostGetViewHeight := HostGetViewHeight;
  FCore.OnHostGetBackgroundColor := HostGetBackgroundColor;
  FCore.OnHostCopyToClipboard := HostCopyToClipboard;
  FCore.OnHostGetTickCount := HostGetTickCount;
  FCore.OnHostResetCaret := HostResetCaret;

  FCaretTimer := TTimer.Create(Self);
  FCaretTimer.Interval := 530;
  FCaretTimer.OnTimer := DoCaretTimer;
  FCaretTimer.Enabled := True;
end;

destructor TPixieHtmlViewBase.Destroy;
begin
  FreeAndNil(FCaretTimer);
  FreeAndNil(FTextService);
  FreeAndNil(FCore);
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Host callbacks
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewBase.HostInvalidate;
begin
  InvalidateRect(LocalRect);
end;

procedure TPixieHtmlViewBase.HostInvalidateRect(const R: TPixiePosition);
var
  Rf: TRectF;
begin
  Rf.Left := R.X;
  Rf.Top := R.Y;
  Rf.Right := R.X + R.Width;
  Rf.Bottom := R.Y + R.Height;
  inherited InvalidateRect(Rf);
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
  Result := Width;
end;

function TPixieHtmlViewBase.HostGetViewHeight: TPixiePixel;
begin
  Result := Height;
end;

function TPixieHtmlViewBase.HostGetBackgroundColor: TPixieWebColor;
begin
  Result := GetBackgroundColor;
end;

procedure TPixieHtmlViewBase.HostCopyToClipboard(const Text: string);
begin
  ClipboardCopy(Text);
end;

function TPixieHtmlViewBase.HostGetTickCount: UInt64;
begin
  Result := UInt64(TThread.GetTickCount);
end;

procedure TPixieHtmlViewBase.HostResetCaret;
begin
  FCaretTimer.Enabled := False;
  FCaretTimer.Enabled := True;
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

function TPixieHtmlViewBase.GetScrollbar: TPixieScrollbarSettings;
begin
  Result := FCore.Scrollbar;
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
// ITextInput
// ---------------------------------------------------------------------------

function TPixieHtmlViewBase.GetTextService: TTextService;
begin
  Result := FTextService;
end;

function TPixieHtmlViewBase.GetTargetClausePointF: TPointF;
var
  DocX, DocY, H: TPixiePixel;
begin
  Result := TPointF.Zero;
  if (FCore.Document <> nil) and
     FCore.Document.GetFocusedCaretPos(DocX, DocY, H) then
  begin
    Result.X := DocX * FCore.Zoom;
    Result.Y := (DocY - FCore.ScrollY + H) * FCore.Zoom + 2;
    Result := LocalToAbsolute(Result);
  end;
end;

procedure TPixieHtmlViewBase.StartIMEInput;
begin
end;

procedure TPixieHtmlViewBase.EndIMEInput;
begin
end;

procedure TPixieHtmlViewBase.IMEStateUpdated;
begin
  Repaint;
end;

function TPixieHtmlViewBase.GetSelection: string;
begin
  if (FCore.Document <> nil) and FCore.Document.HasSelection then
    Result := FCore.Document.GetSelectedText
  else
    Result := '';
end;

function TPixieHtmlViewBase.GetSelectionRect: TRectF;
var
  DocX, DocY, H: TPixiePixel;
begin
  if (FCore.Document <> nil) and
     FCore.Document.GetFocusedCaretPos(DocX, DocY, H) then
  begin
    Result.Left := DocX * FCore.Zoom;
    Result.Top := (DocY - FCore.ScrollY) * FCore.Zoom;
    Result.Right := Result.Left + 2;
    Result.Bottom := Result.Top + H * FCore.Zoom;
  end
  else
    Result := TRectF.Empty;
end;

function TPixieHtmlViewBase.GetSelectionBounds: TRect;
begin
  Result := TRect.Create(
    TPoint.Create(Round(LocalRect.Left), Round(LocalRect.Top)),
    Round(LocalRect.Width), Round(LocalRect.Height));
end;

function TPixieHtmlViewBase.GetSelectionPointSize: TSizeF;
begin
  Result := TSizeF.Create(LocalRect.Width, LocalRect.Height);
end;

function TPixieHtmlViewBase.HasText: Boolean;
begin
  Result := FCore.Document <> nil;
end;

// ---------------------------------------------------------------------------
// Focus — text service enter/exit for IME
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewBase.DoEnter;
var
  Form: TCommonCustomForm;
begin
  inherited;
  if (FTextService <> nil) and (Root <> nil) and
     (Root.GetObject is TCommonCustomForm) then
  begin
    Form := TCommonCustomForm(Root.GetObject);
    FTextService.EnterControl(Form.Handle);
  end;
end;

procedure TPixieHtmlViewBase.DoExit;
var
  Form: TCommonCustomForm;
begin
  if (FTextService <> nil) and (Root <> nil) and
     (Root.GetObject is TCommonCustomForm) then
  begin
    Form := TCommonCustomForm(Root.GetObject);
    FTextService.ExitControl(Form.Handle);
  end;
  inherited;
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
  Upd: TPixiePosition;
begin
  if FCore = nil then Exit;
  // FMX always paints the full viewport; partial-repaint dirty-rect
  // plumbing is deferred (FMX Canvas.ClipRect coord-space mismatches
  // logical Width/Height and needs separate handling).
  Upd := TPixiePosition.Create(0, 0, Width, Height);
  FCore.HandlePaint(GetPaintHandle, Upd);
end;

procedure TPixieHtmlViewBase.DoMouseLeave;
begin
  inherited;
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

procedure TPixieHtmlViewBase.VisibleChanged;
begin
  inherited VisibleChanged;
  if FCore = nil then Exit;
  if Visible then
    FCore.ResumeAnimations
  else
    FCore.PauseAnimations;
end;

// ---------------------------------------------------------------------------
// Keyboard
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewBase.DialogKey(var Key: Word; Shift: TShiftState);
begin
  if (Key = vkTab) and (FCore.Document <> nil) then
  begin
    if FCore.HandleKeyDown(Key, Shift,
      {$IFDEF MACOS}ssCommand{$ELSE}ssCtrl{$ENDIF} in Shift) then
    begin
      Key := 0;
      Exit;
    end;
  end;
  inherited;
end;

procedure TPixieHtmlViewBase.KeyDown(var Key: Word; var KeyChar: WideChar;
  Shift: TShiftState);
var
  S: string;
  CtrlDown: Boolean;
begin
  inherited KeyDown(Key, KeyChar, Shift);

  {$IFDEF MACOS}
  CtrlDown := ssCommand in Shift;
  {$ELSE}
  CtrlDown := ssCtrl in Shift;
  {$ENDIF}

  // Dispatch virtual key to core
  if (Key <> 0) and FCore.HandleKeyDown(Key, Shift, CtrlDown) then
  begin
    Key := 0;
    KeyChar := #0;
    Exit;
  end;

  // Printable character input for focused text elements
  if KeyChar >= ' ' then
  begin
    S := KeyChar;
    if FCore.HandleCharInput(S) then
    begin
      Key := 0;
      KeyChar := #0;
    end;
  end;
end;

// ---------------------------------------------------------------------------
// Mouse
// ---------------------------------------------------------------------------

procedure TPixieHtmlViewBase.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  inherited MouseDown(Button, Shift, X, Y);
  FLastMouseX := X;
  FLastMouseY := Y;
  FCore.HandleMouseDown(Button = TMouseButton.mbLeft, ssDouble in Shift,
    Round(X), Round(Y));
end;

procedure TPixieHtmlViewBase.MouseMove(Shift: TShiftState; X, Y: Single);
begin
  inherited MouseMove(Shift, X, Y);
  // Track the cursor in client pixels so the wheel can target the element
  // under it; HandleMouseWheel converts to document coordinates itself.
  FLastMouseX := X;
  FLastMouseY := Y;
  FCore.HandleMouseMove(Round(X), Round(Y));
end;

procedure TPixieHtmlViewBase.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FCore.HandleMouseUp(Button = TMouseButton.mbLeft, Round(X), Round(Y));
end;

procedure TPixieHtmlViewBase.MouseWheel(Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
var
  CtrlDown: Boolean;
begin
  inherited MouseWheel(Shift, WheelDelta, Handled);
  if Handled then Exit;

  {$IFDEF MACOS}
  CtrlDown := ssCommand in Shift;
  {$ELSE}
  CtrlDown := ssCtrl in Shift;
  {$ENDIF}

  Handled := FCore.HandleMouseWheel(WheelDelta, CtrlDown,
    Round(FLastMouseX), Round(FLastMouseY));
end;

end.
