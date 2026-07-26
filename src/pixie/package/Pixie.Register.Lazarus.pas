unit Pixie.Register.Lazarus;

{$MODE DELPHI}

{$R Pixie.IDE.Icons.res}

interface

procedure Register;

implementation

uses
  Classes, Pixie.HtmlView, Pixie.MarkdownView, Pixie.PaintBox,
  Pixie.SvgView, Pixie.TagBar;

procedure Register;
begin
  RegisterComponents('Pixie',
    [TPixieHtmlView, TPixieMarkdownView, TPixiePaintBox,
     TPixieSvgView, TPixieTagBar]);
end;

end.
