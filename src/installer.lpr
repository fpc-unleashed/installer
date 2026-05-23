{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

program installer;

{$mode unleashed}

uses
  {$ifdef UNIX}
  // must be first on unix; without it TThread aborts with "no thread support" at startup
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
