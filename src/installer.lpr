{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

program installer;

{$mode unleashed}

uses
  Interfaces,
  Forms,
  main_form;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Title := 'FPC Unleashed Installer';
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
