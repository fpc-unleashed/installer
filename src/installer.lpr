{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

program installer;

{$mode unleashed}

uses
  {$ifdef UNIX}
  // cthreads must be first on unix: without it TThread hits "no thread support" RTE 232 at startup
  cthreads,
  {$endif}
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
