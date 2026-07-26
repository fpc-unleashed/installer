unit Pixie.Register.Delphi.FMX;

{$R Pixie.Icons.dcr}

interface

procedure Register;

implementation

uses
  Classes, Pixie.HtmlView.FMX, Pixie.MarkdownView.FMX, Pixie.PaintBox.FMX,
  Pixie.SvgView.FMX, Pixie.TagBar.FMX;

procedure Register;
begin
  RegisterComponents('Pixie',
    [TPixieHtmlView, TPixieMarkdownView, TPixiePaintBox,
     TPixieSvgView, TPixieTagBar]);
end;

end.
