{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit proc_util;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

type
  TLineCallback = procedure(const Line: string) of object;

// run silent, block until exit; stdout/stderr dropped; -1 on launch failure
function RunSilent(const Exe: string; const Args: array of string; const WorkDir: string = ''): Integer;

// run with stdout+stderr captured per-line; ExtraPath prepended to child PATH
function RunStream(const Exe: string; const Args: array of string; const WorkDir: string; const ExtraPath: string; OnLine: TLineCallback): Integer;

implementation

uses
  process;

{$ifdef LINUX}
// bypass FPC RTL's startup-frozen envp; live read of vars set via setenv()
function libc_getenv(name: PChar): PChar; cdecl; external 'c' name 'getenv';
{$endif}

const
  READ_BUF = 4096;

function RunSilent(const Exe: string; const Args: array of string; const WorkDir: string): Integer;
begin
  var P := autofree TProcess.Create(nil);
  P.Executable := Exe;
  for var i := Low(Args) to High(Args) do P.Parameters.Add(Args[i]);
  if WorkDir <> '' then P.CurrentDirectory := WorkDir;
  P.Options := [poNoConsole, poWaitOnExit];
  P.ShowWindow := swoHide;
  try
    P.Execute;
    Result := P.ExitStatus;
  except
    on E: Exception do Result := -1;
  end;
end;

// copy parent env, optionally prepend Prefix to PATH, scrub MAKEFLAGS/MFLAGS
procedure ApplyEnvWithPathPrefix(P: TProcess; const Prefix: string);
begin
  var pathSeen := False;
  for var i := 0 to GetEnvironmentVariableCount-1 do begin
    var envLine := GetEnvironmentString(i);
    if envLine = '' then Continue;
    var eqPos := Pos('=', envLine);
    if eqPos < 2 then Continue;
    var name := UpperCase(Copy(envLine, 1, eqPos-1));
    if (name = 'MAKEFLAGS') or (name = 'MFLAGS') then Continue;
{$ifdef LINUX}
    if name = 'PPC_CONFIG_PATH' then Continue;  // re-injected via libc_getenv below
{$endif}
    if name = 'PATH' then begin
      // PathSeparator: ';' on Windows, ':' on Unix-likes
      if Prefix <> '' then P.Environment.Add('PATH='+Prefix+PathSeparator+Copy(envLine, 6, MaxInt))
      else P.Environment.Add(envLine);
      pathSeen := True;
    end else P.Environment.Add(envLine);
  end;
  if (Prefix <> '') and (not pathSeen) then P.Environment.Add('PATH='+Prefix);
  // force empty even when parent has no MAKEFLAGS, against any wrapper that defaults it
  P.Environment.Add('MAKEFLAGS=');
  P.Environment.Add('MFLAGS=');
{$ifdef LINUX}
  // PPC_CONFIG_PATH set via libc setenv() is invisible to FPC's GetEnvironmentString
  var ppc := libc_getenv('PPC_CONFIG_PATH');
  if (ppc <> nil) and (ppc^ <> #0) then P.Environment.Add('PPC_CONFIG_PATH='+string(ppc));
{$endif}
end;

// flush completed lines from buffer (split on LF; keep trailing partial line)
procedure FlushLines(var Buf: string; OnLine: TLineCallback);
begin
  if not Assigned(OnLine) then begin Buf := ''; Exit; end;
  repeat
    var p := Pos(#10, Buf);
    if p = 0 then Break;
    var Line := Copy(Buf, 1, p-1);
    if (Length(Line) > 0) and (Line[Length(Line)] = #13) then SetLength(Line, Length(Line)-1);
    OnLine(Line);
    Delete(Buf, 1, p);
  until False;
end;

function RunStream(const Exe: string; const Args: array of string; const WorkDir: string; const ExtraPath: string; OnLine: TLineCallback): Integer;
var
  Tmp: array[0..READ_BUF-1] of Byte;
begin
  Result := -1;
  var P := autofree TProcess.Create(nil);
  P.Executable := Exe;
  for var i := Low(Args) to High(Args) do P.Parameters.Add(Args[i]);
  if WorkDir <> '' then P.CurrentDirectory := WorkDir;
  P.Options := [poUsePipes, poNoConsole];
  P.ShowWindow := swoHide;
  ApplyEnvWithPathPrefix(P, ExtraPath);

  var OutBuf := '';
  var ErrBuf := '';
  try
    P.Execute;
  except
    on E: Exception do Exit(-1);
  end;

  // drain pipes until child exits and both pipes are empty
  while P.Running or (P.Output.NumBytesAvailable > 0) or (P.Stderr.NumBytesAvailable > 0) do begin
    if P.Output.NumBytesAvailable > 0 then begin
      var N := P.Output.Read(Tmp, Length(Tmp));
      if N > 0 then begin
        SetLength(OutBuf, Length(OutBuf)+N);
        Move(Tmp, OutBuf[Length(OutBuf)-N+1], N);
        FlushLines(OutBuf, OnLine);
      end;
    end else if P.Stderr.NumBytesAvailable > 0 then begin
      var N := P.Stderr.Read(Tmp, Length(Tmp));
      if N > 0 then begin
        SetLength(ErrBuf, Length(ErrBuf)+N);
        Move(Tmp, ErrBuf[Length(ErrBuf)-N+1], N);
        FlushLines(ErrBuf, OnLine);
      end;
    end else Sleep(20);
  end;

  // emit any final partial line that didn't end with LF
  if (OutBuf <> '') and Assigned(OnLine) then OnLine(OutBuf);
  if (ErrBuf <> '') and Assigned(OnLine) then OnLine(ErrBuf);

  Result := P.ExitStatus;
end;

end.
