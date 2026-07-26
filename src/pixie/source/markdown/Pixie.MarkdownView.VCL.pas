unit Pixie.MarkdownView.VCL;

// TPixieMarkdownView — Delphi VCL visual component that renders
// Markdown content. Converts Markdown to HTML via Pixie.Markdown, then
// renders through the existing HTML engine.

interface

uses
  System.Classes, System.SysUtils,
  Pixie.HtmlView.VCL.Base, Pixie.Markdown;

type
  { TPixieMarkdownView }

  TPixieMarkdownView = class(TPixieHtmlViewBase)
  {$I Pixie.MarkdownView.inc}
  end;

implementation

{$I Pixie.MarkdownView.impl.inc}

end.
