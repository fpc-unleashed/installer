unit Pixie.Clipboard;

// Text clipboard, picked by platform define rather than FRAMEWORK_VCL/FMX
// (which only exist in RAD Studio 11.1+) so it works on all Delphi. (#254)

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

function PixieClipboardGetText: string;
procedure PixieClipboardSetText(const Text: string);

implementation

uses
{$IF DEFINED(FPC)}
  Clipbrd;
{$ELSEIF DEFINED(MSWINDOWS)}
  Winapi.Windows;
{$ELSE}
  System.Rtti, FMX.Platform;
{$IFEND}

function PixieClipboardGetText: string;
{$IF DEFINED(FPC)}
begin
  Result := Clipboard.AsText;
end;
{$ELSEIF DEFINED(MSWINDOWS)}
var
  H: THandle;
  P: PWideChar;
begin
  Result := '';
  if OpenClipboard(0) then
  try
    H := GetClipboardData(CF_UNICODETEXT);
    if H <> 0 then
    begin
      P := GlobalLock(H);
      if P <> nil then
      try
        Result := P;
      finally
        GlobalUnlock(H);
      end;
    end;
  finally
    CloseClipboard;
  end;
end;
{$ELSE}
var
  Svc: IFMXClipboardService;
  V: TValue;
begin
  Result := '';
  if TPlatformServices.Current.SupportsPlatformService(
    IFMXClipboardService, Svc) then
  begin
    V := Svc.GetClipboard;
    if not V.IsEmpty and V.IsType<string> then
      Result := V.AsString;
  end;
end;
{$IFEND}

procedure PixieClipboardSetText(const Text: string);
{$IF DEFINED(FPC)}
begin
  Clipboard.AsText := Text;
end;
{$ELSEIF DEFINED(MSWINDOWS)}
var
  H: THandle;
  P: PWideChar;
  ByteCount: Integer;
begin
  if OpenClipboard(0) then
  try
    EmptyClipboard;
    ByteCount := (Length(Text) + 1) * SizeOf(WideChar);
    H := GlobalAlloc(GMEM_MOVEABLE, ByteCount);
    if H <> 0 then
    begin
      P := GlobalLock(H);
      if P <> nil then
      begin
        Move(PWideChar(Text)^, P^, ByteCount);
        GlobalUnlock(H);
        if SetClipboardData(CF_UNICODETEXT, H) = 0 then
          GlobalFree(H);
      end
      else
        GlobalFree(H);
    end;
  finally
    CloseClipboard;
  end;
end;
{$ELSE}
var
  Svc: IFMXClipboardService;
begin
  if TPlatformServices.Current.SupportsPlatformService(
    IFMXClipboardService, Svc) then
    Svc.SetClipboard(TValue.From<string>(Text));
end;
{$IFEND}

end.
