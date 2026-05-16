{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit proc_util;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

type
  TLineCallback = procedure(const Line: string) of object;

// run a process with no console window, block until it exits, return exit code.
// stdout/stderr are dropped. returns -1 on launch failure.
function RunSilent(const Exe: string; const Args: array of string; const WorkDir: string = ''): Integer;

// run a process with stdout+stderr captured line-by-line. each completed line
// is delivered to OnLine. blocks until exit. ExtraPath is prepended to PATH
// in the child env (use '' to inherit parent env unchanged). returns exit code,
// or -1 on launch failure.
function RunStream(const Exe: string; const Args: array of string; const WorkDir: string; const ExtraPath: string; OnLine: TLineCallback): Integer;

implementation

uses
  process;

{$ifdef LINUX}
// Live read of an env var via libc -- bypasses FPC RTL's startup-frozen
// envp cache. Variables set via libc setenv() inside this process are
// invisible to FPC's GetEnvironmentString/GetEnvironmentVariableCount
// (which capture envp at process start), so we go straight to libc to
// see them.
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

// Copy parent env, optionally prepend Prefix to PATH, always strip
// MAKEFLAGS/MFLAGS. An inherited MAKEFLAGS would otherwise feed unknown
// flag letters back into our `make` and kill it. Empty P.Environment
// means "inherit"; we want "inherit minus MAKEFLAGS" so this always
// populates explicitly.
procedure ApplyEnvWithPathPrefix(P: TProcess; const Prefix: string);
begin
  var pathSeen := False;
  for var i := 0 to GetEnvironmentVariableCount-1 do begin
    var envLine := GetEnvironmentString(i);
    if envLine = '' then Continue;
    var eqPos := Pos('=', envLine);
    if eqPos < 2 then Continue;       // malformed -- no name=value
    var name := UpperCase(Copy(envLine, 1, eqPos-1));
    if (name = 'MAKEFLAGS') or (name = 'MFLAGS') then Continue;                       // scrub: don't propagate to child make
{$ifdef LINUX}
    if name = 'PPC_CONFIG_PATH' then Continue;                       // re-injected via libc_getenv below
{$endif}
    if name = 'PATH' then begin
      // PathSeparator: ';' on Windows, ':' on Unix-likes
      if Prefix <> '' then P.Environment.Add('PATH='+Prefix+PathSeparator+Copy(envLine, 6, MaxInt)) else
        P.Environment.Add(envLine);
      pathSeen := True;
    end else
      P.Environment.Add(envLine);
  end;
  if (Prefix <> '') and (not pathSeen) then P.Environment.Add('PATH='+Prefix);
  // Belt + suspenders: even if parent's env has no MAKEFLAGS at all,
  // explicitly set it empty so any "inherited" semantic somewhere up
  // the stack (libtool wrappers, ccache shims, ...) reads "" instead
  // of mistakenly pulling some default.
  P.Environment.Add('MAKEFLAGS=');
  P.Environment.Add('MFLAGS=');
{$ifdef LINUX}
  // PPC_CONFIG_PATH is set in our process via libc setenv() (in
  // install_pipeline, to override the user's stale ~/.fpc.cfg). FPC's
  // own GetEnvironmentString doesn't see that change (envp frozen at
  // startup), so we read via libc and explicitly add to child env.
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
    end else
      Sleep(20);
  end;

  // emit any final partial line that didn't end with LF
  if (OutBuf <> '') and Assigned(OnLine) then OnLine(OutBuf);
  if (ErrBuf <> '') and Assigned(OnLine) then OnLine(ErrBuf);

  Result := P.ExitStatus;
end;

end.
