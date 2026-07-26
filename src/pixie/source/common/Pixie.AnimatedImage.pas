unit Pixie.AnimatedImage;

// Frame-store types for animated raster images (GIF in Phase 1, APNG in
// Phase 2). One TPixieAnimatedImage is the decoded result for a single
// source URL: a list of pre-composited frames plus playback metadata.
//
// Ownership of the platform image handles is shared: the originating
// canvas owns the underlying bitmaps; the holder of this object
// (TPixieNativeContainer.FAnimations) must call Canvas.FreeImage on
// every frame handle and then ClearFrames before Free. The destructor
// asserts the list has been cleared to catch misuse.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections,
  Pixie.Types;

type
  // Raw decoded frame, prior to platform upload. Producer: a software
  // decoder (Pixie.GifDecode, Pixie.ApngDecode). Consumer:
  // TPixieCanvas.LoadAnimatedFromStream, which uploads each frame to a
  // native image handle and discards the Pixels buffer.
  TPixieRawAnimFrame = record
    Pixels: TBytes;      // BGRA, Width * Height * 4 bytes
    DelayMs: Integer;
  end;

  TPixieRawAnimFrameArray = array of TPixieRawAnimFrame;

  TPixieRawAnimation = record
    Width: Integer;
    Height: Integer;
    Loops: Integer;      // 0 = infinite; N > 0 = play N times then freeze
    Frames: TPixieRawAnimFrameArray;
  end;

  TPixieAnimFrame = record
    Handle: PtrUInt;
    DelayMs: Integer;
  end;

  TPixieAnimFrameList = TList<TPixieAnimFrame>;

  { TPixieAnimatedImage }

  TPixieAnimatedImage = class
  private
    FFrames: TPixieAnimFrameList;
    FLoops: Integer;
    FWidth: Integer;
    FHeight: Integer;
    function GetFrameCount: Integer;
    function GetFrame(Index: Integer): TPixieAnimFrame;
    function GetTotalDurationMs: Integer;
  public
    constructor Create;
    destructor Destroy; override;

    procedure AddFrame(Handle: PtrUInt; DelayMs: Integer);
    procedure ClearFrames;

    property FrameCount: Integer read GetFrameCount;
    property Frames[Index: Integer]: TPixieAnimFrame read GetFrame;
    property Loops: Integer read FLoops write FLoops;
    property Width: Integer read FWidth write FWidth;
    property Height: Integer read FHeight write FHeight;
    property TotalDurationMs: Integer read GetTotalDurationMs;
  end;

  TPixieAnimatedImageMap = TObjectDictionary<string, TPixieAnimatedImage>;

  { TPixieAnimationCursor }
  // Per-element playback state. Owns no native handles; just iterates the
  // referenced TPixieAnimatedImage's frame list against wall-clock deadlines.
  // The view core owns the cursor list and walks it from a 30 Hz timer.

  TPixieAnimationCursor = class
  private
    FImage: TPixieAnimatedImage;
    FElement: TObject;
    FCurrentFrame: Integer;
    FNextDeadlineMs: UInt64;
    FCompletedLoops: Integer;
    FFinished: Boolean;
    FPausedAtMs: UInt64;     // 0 = not paused
  public
    constructor Create(AImage: TPixieAnimatedImage; AElement: TObject;
      NowMs: UInt64);

    // Returns True if the current frame index changed this tick.
    function Tick(NowMs: UInt64): Boolean;

    // Pause snapshots wall-clock; Resume shifts FNextDeadlineMs by the
    // elapsed paused duration so animations don't burst-replay missed
    // time when the host becomes visible again. Both are idempotent.
    procedure Pause(NowMs: UInt64);
    procedure Resume(NowMs: UInt64);

    function CurrentFrameHandle: PtrUInt;

    property Image: TPixieAnimatedImage read FImage;
    property Element: TObject read FElement;
    property CurrentFrame: Integer read FCurrentFrame;
    property Finished: Boolean read FFinished;
  end;

  TPixieAnimationCursorList = TObjectList<TPixieAnimationCursor>;

// Shared frame-bookkeeping helpers used by every animated-raster
// decoder (currently GIF and APNG). Canvas is a full-size BGRA buffer
// the decoder mutates as it composites each frame.

procedure PixieSnapshotCanvas(const Canvas: TBytes; var Prev: TBytes);

// Clears a BGRA sub-rectangle to transparent (zero). Used for GIF
// disposal-2 and APNG dispose_op=BACKGROUND. Off-canvas rows are
// skipped silently.
procedure PixieClearCanvasRect(var Canvas: TBytes;
  CanvasW, CanvasH, Left, Top, W, H: Integer);

// Restores Canvas from a prior snapshot (GIF disposal-3 / APNG
// dispose_op=PREVIOUS). No-op if sizes don't match.
procedure PixieRestoreCanvas(var Canvas: TBytes; const Prev: TBytes);

// Appends a frame: full BGRA copy of Canvas plus DelayMs.
procedure PixieEmitFrame(const Canvas: TBytes; DelayMs: Integer;
  var Frames: TPixieRawAnimFrameArray);

// Composite a W*H sub-image (straight-alpha BGRA) onto a full-size BGRA canvas
// at (OffsetX, OffsetY). BlendOver = True does Porter-Duff source-over;
// BlendOver = False overwrites the destination (source). Shared by the APNG and
// animated-WebP compositors. The caller must ensure the rect fits the canvas.
procedure PixieBlendFrameBgra(var Canvas: TBytes; CanvasW: Integer;
  const SubBgra: TBytes; OffsetX, OffsetY, W, H: Integer; BlendOver: Boolean);

implementation

procedure PixieSnapshotCanvas(const Canvas: TBytes; var Prev: TBytes);
begin
  SetLength(Prev, Length(Canvas));
  if Length(Canvas) > 0 then
    Move(Canvas[0], Prev[0], Length(Canvas));
end;

procedure PixieClearCanvasRect(var Canvas: TBytes;
  CanvasW, CanvasH, Left, Top, W, H: Integer);
var
  Y, DstY, RowStart: Integer;
begin
  for Y := 0 to H - 1 do
  begin
    DstY := Top + Y;
    if (DstY < 0) or (DstY >= CanvasH) then Continue;
    RowStart := (DstY * CanvasW + Left) * 4;
    FillChar(Canvas[RowStart], W * 4, 0);
  end;
end;

procedure PixieRestoreCanvas(var Canvas: TBytes; const Prev: TBytes);
begin
  if (Length(Prev) > 0) and (Length(Prev) = Length(Canvas)) then
    Move(Prev[0], Canvas[0], Length(Canvas));
end;

procedure PixieEmitFrame(const Canvas: TBytes; DelayMs: Integer;
  var Frames: TPixieRawAnimFrameArray);
var
  Idx: Integer;
begin
  Idx := Length(Frames);
  SetLength(Frames, Idx + 1);
  SetLength(Frames[Idx].Pixels, Length(Canvas));
  if Length(Canvas) > 0 then
    Move(Canvas[0], Frames[Idx].Pixels[0], Length(Canvas));
  Frames[Idx].DelayMs := DelayMs;
end;

procedure PixieBlendFrameBgra(var Canvas: TBytes; CanvasW: Integer;
  const SubBgra: TBytes; OffsetX, OffsetY, W, H: Integer; BlendOver: Boolean);
var
  Y, X, SrcRowBase, DstRowBase, SrcIdx, DstIdx: Integer;
  Sr, Sg, Sb, Sa, Dr, Dg, Db, Da: Integer;
  OutA, OutR, OutG, OutB, InvSrcA: Integer;
begin
  for Y := 0 to H - 1 do
  begin
    SrcRowBase := Y * W * 4;
    DstRowBase := ((OffsetY + Y) * CanvasW + OffsetX) * 4;
    for X := 0 to W - 1 do
    begin
      SrcIdx := SrcRowBase + X * 4;
      DstIdx := DstRowBase + X * 4;
      Sb := SubBgra[SrcIdx];
      Sg := SubBgra[SrcIdx + 1];
      Sr := SubBgra[SrcIdx + 2];
      Sa := SubBgra[SrcIdx + 3];

      if not BlendOver then
      begin
        Canvas[DstIdx]     := Byte(Sb);
        Canvas[DstIdx + 1] := Byte(Sg);
        Canvas[DstIdx + 2] := Byte(Sr);
        Canvas[DstIdx + 3] := Byte(Sa);
      end
      else if Sa = $FF then
      begin
        Canvas[DstIdx]     := Byte(Sb);
        Canvas[DstIdx + 1] := Byte(Sg);
        Canvas[DstIdx + 2] := Byte(Sr);
        Canvas[DstIdx + 3] := $FF;
      end
      else if Sa > 0 then
      begin
        // Porter-Duff source-over, straight-alpha.
        Db := Canvas[DstIdx];
        Dg := Canvas[DstIdx + 1];
        Dr := Canvas[DstIdx + 2];
        Da := Canvas[DstIdx + 3];
        InvSrcA := $FF - Sa;
        OutA := Sa + (Da * InvSrcA + 127) div 255;
        if OutA = 0 then
        begin
          Canvas[DstIdx]     := 0;
          Canvas[DstIdx + 1] := 0;
          Canvas[DstIdx + 2] := 0;
          Canvas[DstIdx + 3] := 0;
        end
        else
        begin
          OutR := (Sr * Sa + Dr * Da * InvSrcA div 255 + OutA div 2) div OutA;
          OutG := (Sg * Sa + Dg * Da * InvSrcA div 255 + OutA div 2) div OutA;
          OutB := (Sb * Sa + Db * Da * InvSrcA div 255 + OutA div 2) div OutA;
          Canvas[DstIdx]     := Byte(OutB);
          Canvas[DstIdx + 1] := Byte(OutG);
          Canvas[DstIdx + 2] := Byte(OutR);
          Canvas[DstIdx + 3] := Byte(OutA);
        end;
      end;
      // Sa = 0 with BlendOver: leave destination untouched.
    end;
  end;
end;

{ TPixieAnimatedImage }

constructor TPixieAnimatedImage.Create;
begin
  inherited Create;
  FFrames := TPixieAnimFrameList.Create;
end;

destructor TPixieAnimatedImage.Destroy;
begin
  Assert(FFrames.Count = 0,
    'TPixieAnimatedImage destroyed with live frame handles — '
    + 'holder must call ClearFrames after FreeImage on each.');
  FFrames.Free;
  inherited Destroy;
end;

procedure TPixieAnimatedImage.AddFrame(Handle: PtrUInt; DelayMs: Integer);
var
  Frame: TPixieAnimFrame;
begin
  if DelayMs < 20 then
    DelayMs := 20;
  Frame.Handle := Handle;
  Frame.DelayMs := DelayMs;
  FFrames.Add(Frame);
end;

procedure TPixieAnimatedImage.ClearFrames;
begin
  FFrames.Clear;
end;

function TPixieAnimatedImage.GetFrameCount: Integer;
begin
  Result := FFrames.Count;
end;

function TPixieAnimatedImage.GetFrame(Index: Integer): TPixieAnimFrame;
begin
  Result := FFrames[Index];
end;

function TPixieAnimatedImage.GetTotalDurationMs: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FFrames.Count - 1 do
    Inc(Result, FFrames[I].DelayMs);
end;

{ TPixieAnimationCursor }

constructor TPixieAnimationCursor.Create(AImage: TPixieAnimatedImage;
  AElement: TObject; NowMs: UInt64);
begin
  inherited Create;
  FImage := AImage;
  FElement := AElement;
  if (FImage <> nil) and (FImage.FrameCount > 0) then
    FNextDeadlineMs := NowMs + UInt64(FImage.Frames[0].DelayMs);
end;

function TPixieAnimationCursor.Tick(NowMs: UInt64): Boolean;
var
  Frame: TPixieAnimFrame;
begin
  Result := False;
  if FFinished or (FImage = nil) or (FImage.FrameCount <= 1) then Exit;
  if NowMs < FNextDeadlineMs then Exit;

  if FCurrentFrame >= FImage.FrameCount - 1 then
  begin
    Inc(FCompletedLoops);
    // Image.Loops: 0 = infinite; N>0 = play N times then freeze on last frame
    if (FImage.Loops > 0) and (FCompletedLoops >= FImage.Loops) then
    begin
      FFinished := True;
      Exit;
    end;
    FCurrentFrame := 0;
  end
  else
    Inc(FCurrentFrame);

  Frame := FImage.Frames[FCurrentFrame];
  FNextDeadlineMs := NowMs + UInt64(Frame.DelayMs);
  Result := True;
end;

procedure TPixieAnimationCursor.Pause(NowMs: UInt64);
begin
  if FPausedAtMs = 0 then
    FPausedAtMs := NowMs;
end;

procedure TPixieAnimationCursor.Resume(NowMs: UInt64);
begin
  if FPausedAtMs = 0 then Exit;
  if NowMs > FPausedAtMs then
    FNextDeadlineMs := FNextDeadlineMs + (NowMs - FPausedAtMs);
  FPausedAtMs := 0;
end;

function TPixieAnimationCursor.CurrentFrameHandle: PtrUInt;
begin
  Result := 0;
  if (FImage = nil) or (FImage.FrameCount = 0) then Exit;
  if (FCurrentFrame < 0) or (FCurrentFrame >= FImage.FrameCount) then Exit;
  Result := FImage.Frames[FCurrentFrame].Handle;
end;

end.
