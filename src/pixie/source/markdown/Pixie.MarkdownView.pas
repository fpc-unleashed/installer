unit Pixie.MarkdownView;

// TPixieMarkdownView — Lazarus visual component that renders Markdown
// content. Converts Markdown to HTML via Pixie.Markdown, then renders
// through the existing HTML engine. Sibling of TPixieHtmlView via the
// shared TPixieHtmlViewBase abstract control.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Classes, SysUtils,
  Pixie.HtmlView.Base, Pixie.Markdown;

type
  { TPixieMarkdownView }

  TPixieMarkdownView = class(TPixieHtmlViewBase)
  {$I Pixie.MarkdownView.inc}
  end;

implementation

{$I Pixie.MarkdownView.impl.inc}

end.
