{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit pixie.package.lazarus;

{$warn 5023 off : no warning about unused units}
interface

uses
  Pixie.Background, Pixie.Borders, Pixie.GradientLayer, Pixie.DataUri, Pixie.Encoding, Pixie.ImageUtils, Pixie.AnimatedImage, Pixie.GifDecode, Pixie.ApngDecode, Pixie.Canvas, Pixie.WebP, 
  Pixie.WebP.Decoder, Pixie.WebPAnim, Pixie.Clipboard, Pixie.Container, Pixie.CssLength, Pixie.CssParser, Pixie.CssProperties, Pixie.CssSelector, Pixie.CssTokenizer, Pixie.Document, Pixie.ElAnchor, 
  Pixie.ElBeforeAfter, Pixie.ElDetails, Pixie.Element, Pixie.ElImage, Pixie.ElSvg, Pixie.ElInput, Pixie.ElProgress, Pixie.ElRange, Pixie.ElMisc, Pixie.ElTable, Pixie.ElText, Pixie.ElTextInput, 
  Pixie.FlexItem, Pixie.FontDescription, Pixie.FormattingContext, Pixie.Gradient, Pixie.GridItem, Pixie.Html, Pixie.Utils, Pixie.HtmlEntities, Pixie.HtmlParser, Pixie.HtmlTag, Pixie.HtmlView.Core, 
  Pixie.HtmlView.Base, Pixie.HtmlView, Pixie.Iterators, Pixie.LineBox, Pixie.Markdown, Pixie.Markdown.Css, Pixie.Markdown.HtmlWriter, Pixie.Markdown.InlineParser, Pixie.Markdown.Parser, 
  Pixie.Markdown.Types, Pixie.MarkdownView, Pixie.MasterCss, Pixie.Matrix, Pixie.MediaQuery, Pixie.NativeContainer, Pixie.NumCvt, Pixie.Register.Lazarus, Pixie.RenderBlock, Pixie.RenderBlockContext, 
  Pixie.RenderFlex, Pixie.RenderGrid, Pixie.RenderImage, Pixie.RenderInline, Pixie.RenderInlineContext, Pixie.RenderInput, Pixie.RenderItem, Pixie.RenderTable, Pixie.ScrollView, Pixie.SimpleXml, 
  Pixie.StringId, Pixie.Style, Pixie.Stylesheet, Pixie.FontFace, Pixie.SvgRenderer, Pixie.SvgRenderer.Canvas, Pixie.SvgToPdf, Pixie.TrueType, Pixie.PdfWriter, Pixie.Canvas.Pdf, Pixie.PdfExport, 
  Pixie.Table, Pixie.Types, Pixie.Url, Pixie.Utf8, Pixie.WebColor, Pixie.ControlBase, Pixie.CustomControl, Pixie.DrawingCanvas, Pixie.PaintBox, Pixie.SvgView, Pixie.TagBar, Pixie.TagBar.Base, 
  Pixie.TagBar.Render, Pixie.TagBar.Colors, LazarusPackageIntf;

implementation

procedure register;
begin
  registerunit('Pixie.Register.Lazarus', @pixie.register.lazarus.register);
end;

initialization
  registerpackage('Pixie.Package.Lazarus', @register);
end.
