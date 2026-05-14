{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit download_util;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

type
  // Percent: 0..100, or -1 when total size is unknown
  TDownloadProgress = procedure(Percent: Integer; const Status: string) of object;

// downloads URL to DestPath via WinINet; progress callback throttled per-chunk
function DownloadFile(const URL, DestPath: string; OnProgress: TDownloadProgress): Boolean;

implementation

uses
  Windows, WinInet;

const
  CHUNK_SIZE   = 32 * 1024;
  AGENT        = 'UnleashedInstaller/1.0';
  // cap progress events to ~1 per 256 KB to keep Synchronize traffic sane
  REPORT_EVERY = 256 * 1024;

function HumanMB(B: Int64): string;
begin
  Result := Format('%.1f MB', [B / (1024*1024)]);
end;

function DownloadFile(const URL, DestPath: string; OnProgress: TDownloadProgress): Boolean;
var
  Buf: array[0..CHUNK_SIZE-1] of Byte;
  Stream: TFileStream;
begin
  Result := False;

  var Session := InternetOpen(AGENT, INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if Session = nil then begin
    if Assigned(OnProgress) then OnProgress(-1, 'WinINet init failed');
    Exit;
  end;
  try
    var Connection := InternetOpenUrl(Session, PChar(URL), nil, 0,
      INTERNET_FLAG_NO_UI or INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE or INTERNET_FLAG_KEEP_CONNECTION, 0);
    if Connection = nil then begin
      if Assigned(OnProgress) then OnProgress(-1, 'cannot open URL');
      Exit;
    end;
    try
      // codeload often uses Transfer-Encoding: chunked and skips Content-Length;
      // fall back to indeterminate "X MB downloaded" reporting in that case
      var ContentLength: Int64 := -1;
      var CLBuf: DWORD;
      var CLSize: DWORD := SizeOf(CLBuf);
      var CLIndex: DWORD := 0;
      if HttpQueryInfo(Connection, HTTP_QUERY_CONTENT_LENGTH or HTTP_QUERY_FLAG_NUMBER, @CLBuf, @CLSize, @CLIndex) then
        ContentLength := CLBuf;

      try
        Stream := autofree TFileStream.Create(DestPath, fmCreate);
      except
        if Assigned(OnProgress) then OnProgress(-1, 'cannot create '+DestPath);
        Exit;
      end;

      var Total: Int64 := 0;
      var LastPct: Integer := -2;
      var LastReportTotal: Int64 := 0;
      if Assigned(OnProgress) then begin
        if ContentLength > 0 then OnProgress(0, '0 / '+HumanMB(ContentLength))
        else OnProgress(-1, 'starting download...');
      end;

      repeat
        var BytesRead: DWORD;
        if not InternetReadFile(Connection, @Buf[0], CHUNK_SIZE, BytesRead) then begin
          if Assigned(OnProgress) then OnProgress(-1, 'read failed');
          Exit;
        end;
        if BytesRead = 0 then Break;
        Stream.WriteBuffer(Buf[0], BytesRead);
        Inc(Total, BytesRead);

        if Assigned(OnProgress) and ((Total-LastReportTotal >= REPORT_EVERY) or (BytesRead < CHUNK_SIZE)) then begin
          LastReportTotal := Total;
          if ContentLength > 0 then begin
            var Pct: Integer := Round(Total * 100 / ContentLength);
            if Pct > 100 then Pct := 100;
            if Pct <> LastPct then begin
              LastPct := Pct;
              OnProgress(Pct, HumanMB(Total)+' / '+HumanMB(ContentLength));
            end;
          end else
            OnProgress(-1, HumanMB(Total)+' downloaded');
        end;
      until False;

      if Assigned(OnProgress) then begin
        if ContentLength > 0 then OnProgress(100, 'download complete')
        else OnProgress(-1, HumanMB(Total)+' downloaded');
      end;
      Result := True;
    finally
      InternetCloseHandle(Connection);
    end;
  finally
    InternetCloseHandle(Session);
  end;
end;

end.
