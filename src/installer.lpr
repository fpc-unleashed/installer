{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

program installer;

{$mode unleashed}

uses
  {$ifdef UNIX}
  // cthreads MUST be the first unit in the main program on unix-like
  // OSes -- without it TThread (used by TInstallThread + TBranchFetchThread)
  // hits "This binary has no thread support compiled in" with Runtime
  // error 232 at startup.
  cthreads, {$endif}
  Interfaces, Forms, main_form;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  application.scaled := true;
  application.title := 'FPC Unleashed Installer';
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
