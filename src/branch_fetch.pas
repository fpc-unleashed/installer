{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit branch_fetch;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

type
  TBranchFetchThread = class(TThread)
  private
    FOwner, FRepo: string;
    FBranches: TStringList;
    FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const AOwner, ARepo: string; AOnDone: TNotifyEvent);
    destructor Destroy; override;
    property Owner: string read FOwner;
    property Repo: string read FRepo;
    // safe to read on main thread inside OnTerminate
    property Branches: TStringList read FBranches;
    property ErrorMsg: string read FError;
  end;

implementation

uses
  Windows, WinInet, fpjson, jsonparser;

const
  AGENT      = 'UnleashedInstaller/1.0';
  HEADERS    = 'Accept: application/vnd.github+json'#13#10;
  CHUNK_SIZE = 4096;

constructor TBranchFetchThread.Create(const AOwner, ARepo: string; AOnDone: TNotifyEvent);
begin
  inherited Create(True);
  FOwner := AOwner;
  FRepo := ARepo;
  FBranches := TStringList.Create;
  // FreeOnTerminate frees us after OnTerminate returns; callback must NOT free us
  FreeOnTerminate := True;
  OnTerminate := AOnDone;
  Start;
end;

destructor TBranchFetchThread.Destroy;
begin
  FBranches.Free;
  inherited Destroy;
end;

// WinINet HTTPS GET; curl.exe only shipped with Windows 10 1803+
function HttpGet(const URL: string; out Body: string): Boolean;
var
  Buf: array[0..CHUNK_SIZE-1] of Byte;
  BytesRead: DWORD;
begin
  Result := False;
  Body := '';
  var Session := InternetOpen(AGENT, INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if Session = nil then Exit;
  try
    var Connection := InternetOpenUrl(Session, PChar(URL), PChar(HEADERS), Length(HEADERS),
      INTERNET_FLAG_NO_UI or INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE or INTERNET_FLAG_KEEP_CONNECTION, 0);
    if Connection = nil then Exit;
    try
      var Stream := autofree TMemoryStream.Create;
      repeat
        if not InternetReadFile(Connection, @Buf[0], CHUNK_SIZE, BytesRead) then Exit;
        if BytesRead = 0 then Break;
        Stream.Write(Buf[0], BytesRead);
      until False;

      if Stream.Size > 0 then begin
        SetLength(Body, Stream.Size);
        Move(PByte(Stream.Memory)^, Body[1], Stream.Size);
      end;
      Result := True;
    finally
      InternetCloseHandle(Connection);
    end;
  finally
    InternetCloseHandle(Session);
  end;
end;

procedure TBranchFetchThread.Execute;
begin
  try
    var Url := Format('https://api.github.com/repos/%s/%s/branches?per_page=100', [FOwner, FRepo]);
    var Body: string;
    if not HttpGet(Url, Body) then begin
      FError := 'WinINet HTTP GET failed';
      Exit;
    end;

    var J := autofree GetJSON(Body);
    if not (J is TJSONArray) then begin
      FError := 'unexpected response: '+Copy(Body, 1, 200);
      Exit;
    end;
    var Arr := TJSONArray(J);
    // "name=sha" -> Names[i] for combo, Values[name] for head sha lookup
    for var i := 0 to Arr.Count-1 do begin
      var Obj := Arr.Objects[i];
      if Obj <> nil then FBranches.Add(Obj.Get('name', '')+'='+TJSONObject(Obj.Find('commit')).Get('sha', ''));
    end;
  except
    on E: Exception do FError := E.ClassName+': '+E.Message;
  end;
end;

end.
