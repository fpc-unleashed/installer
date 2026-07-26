{ Unleashed Pascal Installer - (c) 2026 Unleashed Pascal. See LICENSE. }

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
  application.title := 'Unleashed Pascal Installer';
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
