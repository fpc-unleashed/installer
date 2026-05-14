{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit zip_util;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

type
  // Percent: 0..100; reports as bytes are extracted across the whole archive
  TZipProgress = procedure(Percent: Integer; const Status: string) of object;

// extract every entry of ZipPath into DestDir (creates DestDir if needed).
// callback fires per-file based on byte progress; pass nil to skip reporting.
function ExtractZip(const ZipPath, DestDir: string;
  OnProgress: TZipProgress): Boolean;

implementation

uses
  Zipper;

type
  // bridge wraps the Zipper progress signature into our simpler callback
  TProgressBridge = class
    Cb: TZipProgress;
    LastPct: Integer;
    procedure OnProgressEx(Sender: TObject; const ATotPos, ATotSize: Int64);
  end;

procedure TProgressBridge.OnProgressEx(Sender: TObject;
  const ATotPos, ATotSize: Int64);
begin
  if (ATotSize <= 0) or not Assigned(Cb) then Exit;
  var pct := Round(ATotPos * 100 / ATotSize);
  if pct > 100 then pct := 100;
  if pct < 0 then pct := 0;
  if pct = LastPct then Exit;
  LastPct := pct;
  Cb(pct, Format('%.1f / %.1f MB', [ATotPos / (1024*1024), ATotSize / (1024*1024)]));
end;

function ExtractZip(const ZipPath, DestDir: string;
  OnProgress: TZipProgress): Boolean;
begin
  Result := False;
  if not DirectoryExists(DestDir) then
    if not ForceDirectories(DestDir) then Exit;

  // LIFO: UnZip frees first, then Bridge - safe because UnZip drops its
  // OnProgressEx handler before destruction
  var Bridge := autofree TProgressBridge.Create;
  var UnZip := autofree TUnZipper.Create;
  Bridge.Cb := OnProgress;
  Bridge.LastPct := -1;
  UnZip.FileName := ZipPath;
  UnZip.OutputPath := DestDir;
  UnZip.OnProgressEx := @Bridge.OnProgressEx;
  try
    UnZip.UnZipAllFiles;
    Result := True;
  except
    on E: Exception do Result := False;
  end;
end;

end.
