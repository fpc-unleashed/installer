{ Unleashed Installer - (c) 2026 fpc-unleashed. See LICENSE. }

unit about_form;

{$mode unleashed}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls;

type
  TAboutForm = class(TForm)
    pnlHead: TPanel;
    lblTitle: TLabel;
    lblBlurb: TLabel;
    pnlFoot: TPanel;
    btnClose: TButton;
    memLicense: TMemo;
    procedure FormCreate(Sender: TObject);
  end;

procedure ShowAbout(aOwner: TComponent; const aTitle: string);

implementation

{$R *.lfm}

// Keep in sync with installer/LICENSE.
const
  LICENSE_TEXT =
    '''
    Unleashed Installer License

    Copyright (c) 2026 fpc-unleashed.

    This software is the official installer for the fpc-unleashed
    project (https://github.com/fpc-unleashed). The source is published
    so users can audit what the installer does.

    YOU MAY, FREE OF CHARGE:
      1. Run the installer binary released by fpc-unleashed, or build
         it yourself from this source.
      2. Read this source code for understanding or auditing.

    YOU MAY NOT, WITHOUT WRITTEN PERMISSION FROM fpc-unleashed:
      1. Copy, modify, merge, redistribute, or sublicense any part of
         the source or binary-in original or modified form.
      2. Create forks, branches, ports, or derivative works, even if
         URLs, names, configuration, or branding are changed. This
         installer is the fpc-unleashed installer; it is not licensed
         for use by any other project, including forks of fpc-unleashed
         itself.
      3. Use the names "Unleashed", "FPC Unleashed", or any
         confusingly similar name in derived works, packaging, or
         marketing materials.

    There is no permitted fork.

    THIRD-PARTY COMPONENTS

    The installer binary statically links the FPC Runtime Library and
    the Lazarus Component Library, both distributed under the Modified
    LGPL with linking exception. Those licenses apply only to those
    components and do not grant additional rights to the source or
    binary of this installer.

    NO WARRANTY

    THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR
    ANY CLAIM, DAMAGES, OR OTHER LIABILITY ARISING FROM THE USE OF
    THIS SOFTWARE.
    ''';

procedure TAboutForm.FormCreate(Sender: TObject);
begin
  memLicense.Lines.Text := LICENSE_TEXT;
end;

procedure ShowAbout(aOwner: TComponent; const aTitle: string);
begin
  var dlg := autofree TAboutForm.Create(aOwner);
  dlg.lblTitle.Caption := aTitle;
  dlg.ShowModal;
end;

end.
