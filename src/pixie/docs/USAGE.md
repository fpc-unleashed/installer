# Pixie HTML View — Usage Guide

Pixie is a lightweight HTML/CSS rendering engine for Free Pascal and Delphi. It provides five visual components: `TPixieHtmlView` (HTML rendering with mouse interaction, text selection, focus, and form controls), `TPixieMarkdownView` (CommonMark + GFM Markdown, rendered through the HTML engine), `TPixieSvgView` (proportional SVG display with alignment), `TPixiePaintBox` (drawing surface with a TCanvas-like stateful API), and `TPixieTagBar` (interactive coloured tag pills).

## Installation

### Lazarus (Free Pascal)

The package is located in `package/Pixie.Package.Lazarus.lpk`. Install it into the Lazarus IDE to add the components to the **Pixie** component palette tab.

### Delphi (VCL)

Open `package/Pixie.Package.Delphi.VCL.dpk` in the Delphi IDE and install it. Or add `source/common` plus the per-component folders you need (`source/htmlview`, `source/markdown`, `source/svgview`, `source/paintbox`, `source/tagbar`) to the unit search path and use the `Pixie.*.VCL` units directly.

### Delphi (FMX)

Open `package/Pixie.Package.Delphi.FMX.dpk` in the Delphi IDE and install it. Or add `source/common` plus the per-component folders you need to the unit search path and use the `Pixie.*.FMX` units directly. The FMX backend supports Windows, macOS, iOS, and Android.

## Quick Start

Drop a `TPixieHtmlView` onto a form and load HTML:

```pascal
PixieHtmlView1.LoadFromString(
  '<h1>Hello</h1><p>This is <b>Pixie</b>.</p>');
```

Or assign multi-line HTML via the `Lines` property in the Object Inspector.

## Rendering Pipeline

```
HTML string
  -> HTML5 parser (tokeniser + tree builder)
  -> DOM tree (TPixieElement nodes)
  -> CSS cascade and style computation
  -> Render tree construction
  -> Layout (block, inline, table, flex, grid)
  -> Drawing via platform canvas
```

All drawing uses sub-pixel rendering, alpha blending, and hardware acceleration where available. Five platform backends are used transparently:

| Platform | Drawing | Text | Images |
|----------|---------|------|--------|
| Windows (Lazarus, Delphi VCL) | Direct2D | DirectWrite | WIC |
| Delphi FMX (Windows, macOS, iOS, Android) | FMX Canvas | FMX TextLayout | FMX Bitmap |
| Linux (GTK2, GTK3) | Cairo | PangoCairo | FPImage |
| macOS (Lazarus) | Core Graphics | Core Text | ImageIO |
| Qt5 / Qt6 (any platform) | QPainter | QFontMetrics | QImage |

## Properties

### Published Properties

| Property | Type | Description |
|----------|------|-------------|
| `Lines` | `TStrings` | HTML content. Setting this rebuilds the document. |
| `BaseUrl` | `string` | Base URL for resolving relative image/CSS paths. |
| `UserCss` | `string` | Additional CSS applied after the built-in user-agent stylesheet. |
| `Zoom` | `Double` | Zoom factor, clamped to 0.25 .. 4.0. Default: 1.0. |
| `Color` | `TColor` | Background colour when no document is loaded or outside the HTML body. |

### Public Properties

| Property | Type | Access | Description |
|----------|------|--------|-------------|
| `Document` | `TPixieDocument` | read-only | The parsed DOM document. `nil` if no HTML is loaded. |
| `ContentHeight` | `TPixiePixel` | read-only | Total content height in virtual (pre-zoom) pixels. |
| `ScrollY` | `TPixiePixel` | read/write | Vertical scroll offset in virtual pixels. |

## Events

### OnAnchorClick

```pascal
procedure(Sender: TObject; El: TObject; const Url: string) of object;
```

Fired when the user clicks an `<a href="...">` element. `El` is the clicked anchor as a `TPixieHtmlTag` (cast from `TObject`) — use it to read attributes such as `target`, `id`, or `class` via `GetAttr`. The `Url` is resolved against `BaseUrl`. Use this to open links in an external browser or navigate internally. The parameter order mirrors `OnElementClick` (`Sender, El`), extended with the resolved `Url`.

### OnElementClick

```pascal
function(Sender: TObject; El: TObject): Boolean of object;
```

Fired when the user clicks an element. `El` is a `TPixieHtmlTag` (cast from `TObject`); clicks on text content report the containing tag. The event bubbles: it fires for the clicked element and then each ancestor up to `<body>`. Return `True` to stop propagation and suppress default handling (checkbox toggling, etc.). Anchor (`<a>`) clicks fire `OnAnchorClick` first (for `href`-bearing anchors) and then `OnElementClick`.

### OnFetchUrl

```pascal
procedure(Sender: TObject; const Url: string;
  Stream: TStream; var Success: Boolean) of object;
```

Callback for loading external resources (images, CSS `@import`). Write the fetched data to `Stream` and set `Success := True`. If not handled, the resource is skipped silently.

### OnBeforeParse / OnAfterParse

`TNotifyEvent`. Fired before and after HTML parsing. Useful for progress indication.

### OnBeforePaint / OnAfterPaint

`TNotifyEvent`. Fired before and after each paint cycle.

## Methods

### LoadFromString

```pascal
procedure LoadFromString(const AHtml: string; const ABaseUrl: string = '');
```

Sets `BaseUrl`, replaces the HTML content, and rebuilds the document in one call. This is the most common way to load content.

### LoadFromFile

```pascal
procedure LoadFromFile(const AFileName: string; const ABaseUrl: string = '');
```

Loads HTML from a file. If `ABaseUrl` is empty, it defaults to the directory containing the file.

### LoadFromStream

```pascal
procedure LoadFromStream(AStream: TStream; const ABaseUrl: string = '');
```

Loads HTML from a stream (reads the entire stream as UTF-8 text).

### RegisterImage / UnregisterImage

```pascal
procedure RegisterImage(const Name: string; Stream: TStream);
procedure UnregisterImage(const Name: string);
```

Pre-register a named image from a stream. Reference it in HTML as:

```html
<img src="#MyImage">
```

The stream data is copied internally and decoded on first use. Call `UnregisterImage` to release the cached bitmap.

## Image Sources

The `<img>` element's `src` attribute supports several prefixes:

| Prefix | Example | Description |
|--------|---------|-------------|
| `#name` | `<img src="#logo">` | Pre-registered image via `RegisterImage`. |
| `@RESNAME` | `<img src="@ICON_HELP">` | Embedded Lazarus resource (`RT_RCDATA`). |
| URL | `<img src="https://...">` | Fetched via the `OnFetchUrl` event. |
| File path | `<img src="/path/to/image.png">` | Loaded directly from disk. |

Supported raster formats: PNG, JPEG, BMP, GIF (all platforms); TIFF and ICO additionally on Windows and macOS for file-based loading. SVG is supported on all platforms via the built-in vector renderer (see [Known Limitations](#known-limitations) for details).

## Built-in Keyboard and Mouse Behaviour

| Input | Action |
|-------|--------|
| Tab / Shift+Tab | Cycle focus between text inputs, buttons, checkboxes |
| Ctrl+C (Cmd+C on macOS) | Copy selected text to clipboard |
| Ctrl+0 (Cmd+0) | Reset zoom to 100% |
| Ctrl+Mouse wheel | Zoom in/out |
| Arrow Up/Down | Scroll by 40 px |
| Page Up/Down | Scroll by one viewport height |
| Mouse wheel | Scroll 40 px per notch (or scroll a focused textarea) |
| Click + drag | Text selection |
| Double-click | Select word |

CSS `cursor` values are mapped automatically: `pointer` to hand cursor, `text` to I-beam, `crosshair` and `move` to their OS equivalents.

## DOM Access

Access the DOM via `HtmlView.Document`:

```pascal
var
  El: TPixieElement;
begin
  El := PixieHtmlView1.Document.GetElementById('status');
  if El <> nil then
    ShowMessage(El.GetTextContent);
end;
```

### Finding Elements

```pascal
// By ID
El := Doc.GetElementById('myId');

// First match for a CSS selector
El := Doc.QuerySelector('div.content > p:first-child');

// All matches
List := Doc.QuerySelectorAll('input[type="text"]');
```

### Reading Element Data

```pascal
// Tag name and attributes
S := El.GetTagName;                      // e.g. 'div'
S := El.GetAttr('href', '');             // attribute value or default

// Text content (recursive)
S := El.GetTextContent;

// Computed CSS properties
Css := El.Css;
Display := Css.Display;                  // e.g. displayBlock
Color := Css.Color;                      // TPixieWebColor
```

### Tree Navigation

```pascal
ParentEl := El.Parent;
ChildList := El.Children;               // TObjectList<TPixieElement>
for I := 0 to ChildList.Count - 1 do
  ProcessChild(ChildList[I]);
```

## DOM Mutation

You can modify the document tree after it has been parsed. High-level methods on `TPixieDocument` automatically rebuild the render tree, so changes take effect immediately.

### Creating Elements

```pascal
var
  Doc: TPixieDocument;
  Span, TextNode: TPixieElement;
begin
  Doc := PixieHtmlView1.Document;

  // Create an element (pass nil for no attributes)
  Span := Doc.CreateElement('span', nil);
  Span.SetAttr('class', 'highlight');

  // Create a text node
  TextNode := Doc.CreateTextNode('Hello world');

  // Build the subtree
  Span.AppendChild(TextNode);

  // Attach to the document
  Doc.GetElementById('container').AppendChild(Span);

  // Apply changes
  Doc.Rebuild;
end;
```

### Inserting Elements

```pascal
// Insert NewChild before RefChild in the same parent
Parent.InsertBefore(NewChild, RefChild);

// Append at the end
Parent.AppendChild(NewChild);
```

### Removing Elements

```pascal
// Detaches from parent, unregisters (frees) the element
// and all descendants, then rebuilds automatically
Doc.RemoveElement(El);
```

### Replacing Content

```pascal
// Replace all children with new HTML (auto-rebuild)
Doc.SetInnerHtml(ContainerEl, '<p>New content</p>');
```

### Modifying Text

```pascal
// Replace all children with a text node (auto-rebuild)
Doc.SetElementText(StatusEl, 'Done');
```

### Modifying Attributes

```pascal
El.SetAttr('class', 'active');
El.SetAttr('style', 'color: red; font-weight: bold');
Doc.Rebuild;  // required for changes to take effect
```

### Batching Multiple Changes

When making several mutations at once, wrap them in `BeginUpdate`/`EndUpdate` to defer the rebuild until the end:

```pascal
Doc.BeginUpdate;
try
  El := Doc.CreateElement('li', nil);
  El.AppendChild(Doc.CreateTextNode('Item'));
  ListEl.AppendChild(El);
  Doc.SetElementText(CountEl, '3 items');
finally
  Doc.EndUpdate;  // single rebuild happens here
end;
```

### Low-Level API

The low-level `RemoveChild`, `UnregisterElement`, and `Rebuild` methods are still available for advanced use cases. Prefer the high-level methods above for most tasks.

## Supported HTML

### Elements

- **Structural:** `html`, `head`, `body`, `div`, `span`, `section`, `article`, `nav`, `aside`, `header`, `footer`, `main`
- **Text:** `p`, `br`, `hr`, `pre`, `blockquote`, `code`, `em`, `strong`, `b`, `i`, `u`, `s`, `sub`, `sup`, `small`, `mark`, `abbr`, `q`, `cite`, `kbd`, `var`, `samp`
- **Headings:** `h1` through `h6`
- **Links:** `a`
- **Images:** `img` (raster and SVG)
- **Lists:** `ul`, `ol`, `li`, `dl`, `dt`, `dd`
- **Tables:** `table`, `thead`, `tbody`, `tfoot`, `tr`, `th`, `td`, `caption`, `colgroup`, `col`
- **Forms:** `input` (text, password, checkbox, radio), `textarea`, `button`
- **Semantic HTML5:** `figure`, `figcaption`, `details`, `summary`, `time`, `address`
- **Other:** `style`, `title`, `meta`, `link`

### Parser

Full HTML5 tokeniser (68 states) and tree builder (23 insertion modes) with:

- 2125 named character entities plus numeric references
- Automatic tag closing and implicit element insertion
- Adoption agency algorithm for misnested formatting tags
- Foster parenting for misplaced table content
- SVG and MathML foreign content
- Quirks mode detection

## Supported CSS

### Selectors

Type, class (`.`), ID (`#`), universal (`*`), attribute selectors (`[attr]`, `[attr=val]`, `[attr~=val]`, `[attr|=val]`, `[attr^=val]`, `[attr$=val]`, `[attr*=val]`), combinators (descendant, child `>`, adjacent sibling `+`, general sibling `~`).

Pseudo-classes: `:first-child`, `:last-child`, `:nth-child()`, `:nth-of-type()`, `:not()`, `:is()`, `:hover`, `:active`, `:focus`, `:checked`, `:disabled`, `:link`, `:visited`, `:lang()`.

Pseudo-elements: `::before`, `::after` (with `content` property).

### Layout

| Mode | Properties |
|------|------------|
| **Block** | Margin collapse, percentage sizing, min/max constraints |
| **Inline** | Line boxes, `vertical-align`, `text-align` |
| **Flexbox** | `flex-direction`, `flex-wrap`, `justify-content`, `align-items`, `align-self`, `align-content`, `flex-grow`/`shrink`/`basis`, `order`, `gap` |
| **CSS Grid** | `grid-template-columns`/`rows` (px, %, fr, auto, `minmax()`), `grid-column`/`row` placement, `span`, `justify-items`/`self`, `align-items`/`self`, `gap`, auto-placement |
| **Table** | `border-collapse`, `border-spacing`, `colspan`, `rowspan`, `caption-side` |
| **Float** | `float`, `clear` |
| **Positioning** | `static`, `relative`, `absolute`, `fixed`, `z-index` |

### Properties

**Box model:** `margin`, `padding`, `border`, `width`, `height`, `min-width`, `max-width`, `min-height`, `max-height`, `box-sizing`, `display`, `overflow`.

**Typography:** `font-family`, `font-size`, `font-weight`, `font-style`, `font-variant`, `line-height`, `text-align`, `text-decoration`, `text-transform`, `text-indent`, `letter-spacing`, `word-spacing`, `white-space`, `vertical-align`.

**Colours and backgrounds:** `color`, `background` (shorthand and individual properties), `background-image` (url, `linear-gradient()`, `radial-gradient()`, `conic-gradient()` and repeating variants), `background-size`, `background-position`, `background-repeat`, `background-clip`, `background-origin`, `opacity`.

**Borders:** `border-width`, `border-style`, `border-color`, `border-radius` (all sides and shorthands).

**Lists:** `list-style-type` (disc, circle, square, decimal, roman, alpha, greek), `list-style-position`, CSS counters (`counter-reset`, `counter-increment`, `content`).

**Custom properties:** `var()` with `--*` custom property detection.

### At-rules

`@media` with Media Queries Level 4 (range syntax, `min-`/`max-` prefixes). Supported features: `width`, `height`, `device-width`, `device-height`, `color`, `color-index`, `monochrome`, `orientation`, `resolution`, `aspect-ratio`.

## Form Controls

Pixie includes owner-drawn form controls that do not rely on native OS widgets:

| Control | HTML | Features |
|---------|------|----------|
| Text input | `<input type="text">` | Caret, selection, clipboard, undo |
| Password | `<input type="password">` | Masked display (bullet characters) |
| Textarea | `<textarea>` | Multi-line editing, scroll |
| Checkbox | `<input type="checkbox">` | Toggle on click, `:checked` pseudo-class |
| Radio | `<input type="radio">` | Grouped by `name` attribute |
| Button | `<button>` | Click handling, `:active` feedback |

All controls support `:focus`, `:checked`, `:disabled` pseudo-classes, Tab/Shift+Tab focus cycling, and CSS styling.

## PDF Export

Pixie can export any HTML content to a multi-page PDF document using `TPixiePdfExport`. The export uses its own PDF rendering canvas, independent of the on-screen component, so it works without a GUI.

### Basic Usage

```pascal
uses Pixie.PdfExport;

var
  Pdf: TPixiePdfExport;
begin
  Pdf := TPixiePdfExport.Create;
  try
    Pdf.Title := 'My Report';
    Pdf.Author := 'My Application';
    Pdf.SaveToFile('<h1>Hello</h1><p>World</p>', 'report.pdf');
  finally
    Pdf.Free;
  end;
end;
```

### Exporting from TPixieHtmlView

```pascal
var
  Pdf: TPixiePdfExport;
begin
  Pdf := TPixiePdfExport.Create;
  try
    Pdf.SaveToFile(PixieHtmlView1.Lines.Text, 'output.pdf');
  finally
    Pdf.Free;
  end;
end;
```

### Exporting Markdown

`TPixiePdfExport` takes HTML, so first convert the Markdown source:

```pascal
uses Pixie.Markdown, Pixie.PdfExport;

var
  Pdf: TPixiePdfExport;
  Html: string;
begin
  Html := PixieMarkdownToHtmlDocument(
    PixieMarkdownReadFile('article.md'), 'Article');
  Pdf := TPixiePdfExport.Create;
  try
    Pdf.BaseUrl := ExtractFilePath('article.md');  // for relative images
    Pdf.SaveToFile(Html, 'article.pdf');
  finally
    Pdf.Free;
  end;
end;
```

### Saving to a Stream

```pascal
var
  Pdf: TPixiePdfExport;
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    Pdf := TPixiePdfExport.Create;
    try
      Pdf.SaveToStream('<h1>Hello</h1>', Stream);
    finally
      Pdf.Free;
    end;
    // use Stream...
  finally
    Stream.Free;
  end;
end;
```

### Page Size and Margins

```pascal
Pdf := TPixiePdfExport.Create;
Pdf.PageSize := ppsLetter;    // ppsA4 (default), ppsLetter, ppsLegal, ppsCustom
Pdf.Margins.Top := 54;        // in points (72 points = 1 inch)
Pdf.Margins.Bottom := 54;
Pdf.Margins.Left := 72;
Pdf.Margins.Right := 72;
```

For custom page sizes:

```pascal
Pdf.PageSize := ppsCustom;
Pdf.CustomWidth := 400;       // points
Pdf.CustomHeight := 600;      // points
```

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `PageSize` | `TPixiePdfPageSize` | `ppsA4` | Page size preset |
| `CustomWidth` | `Single` | 0 | Custom page width in points (when `PageSize = ppsCustom`) |
| `CustomHeight` | `Single` | 0 | Custom page height in points (when `PageSize = ppsCustom`) |
| `Margins.Top` | `Single` | 72 | Top margin in points |
| `Margins.Bottom` | `Single` | 72 | Bottom margin in points |
| `Margins.Left` | `Single` | 72 | Left margin in points |
| `Margins.Right` | `Single` | 72 | Right margin in points |
| `Title` | `string` | — | PDF document title metadata |
| `Author` | `string` | — | PDF document author metadata |

### What Is Supported

- Text with fonts, sizes, weights, styles, colours
- TrueType font embedding with glyph subsetting (searchable/selectable text)
- Tables, lists, flexbox, CSS Grid layouts
- Borders (solid, dashed, dotted) with border-radius
- Background colours and images
- Linear and radial gradients
- Opacity
- Multi-page output with automatic page breaks

### Limitations

- Conic gradients are rendered as solid colour fills
- Gradient opacity uses average alpha across all stops rather than per-stop alpha
- SVG images in PDF output are rendered as vector Form XObjects
- Non-BMP characters (emoji) are not included in font subsets
- Form controls are rendered but not interactive in PDF output

## Markdown

`TPixieMarkdownView` renders CommonMark + GFM Markdown by converting it to HTML and feeding it through the HtmlView engine. The output is the same fully-styled, selectable, interactive document — just authored in Markdown.

Supported syntax: ATX and setext headings, paragraphs (with lazy continuation), thematic breaks, fenced code (`` ``` `` / `~~~` with language info) and indented code, blockquotes (nested), ordered/unordered/nested lists with tight/loose distinction, GFM tables with column alignment, GFM task lists (`- [x]` / `- [ ]`), CommonMark link reference definitions, autolinks (`<https://...>`, bare URLs as a GFM extension), images, raw HTML blocks and inline raw HTML, hard breaks, soft breaks, GFM strikethrough (`~~text~~`), full inline emphasis with the CommonMark left/right-flanking delimiter algorithm, backslash escapes, and HTML entity references. URL destinations are percent-encoded for output.

### Loading Markdown

```pascal
PixieMarkdownView1.LoadMarkdownFromString(
  '# Hello' + sLineBreak + sLineBreak + 'Some *emphasised* text.');

PixieMarkdownView1.LoadMarkdownFromFile('README.md');

PixieMarkdownView1.LoadMarkdownFromStream(Stream, BaseUrl);
```

`LoadMarkdownFromFile` derives the base URL from the file path so relative image references in the Markdown resolve to files next to it.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `Markdown` | `TStrings` | Markdown source. Setting it rebuilds the rendered output. |
| `UseDefaultStyles` | `Boolean` | When `True` (default), prepends a GitHub-flavoured stylesheet to the rendered HTML. Toggle off to style the output entirely from your own CSS. |

The view inherits all of `TPixieHtmlView`'s behaviour — events, scrolling, zoom, copy/paste, focus, the lot.

### Conversion Without a Component

For headless use (PDF export, server-side generation, command-line tools), the conversion helpers in `Pixie.Markdown` work without any view:

```pascal
uses Pixie.Markdown;

// Body fragment only
Html := PixieMarkdownToHtml(MdText);

// Full <html><head><style>...</style></head><body>...</body></html>
Html := PixieMarkdownToHtmlDocument(MdText, 'Page Title');

// UTF-8 file readers (BOM-aware)
MdText := PixieMarkdownReadFile('article.md');

// Default GitHub-style stylesheet, useful if rolling your own document
Css := PixieDefaultMarkdownCss;
```

### Options

`TPixieMdOptions` is a set type controlling parser behaviour. The defaults enable everything; pass a tighter set for stricter parsing:

| Option | Description |
|--------|-------------|
| `moAllowRawHtml` | Pass HTML blocks and inline HTML through to the output. |
| `moStripFrontMatter` | Strip a leading `--- ... ---` YAML block before parsing. |
| `moAutoHeadingIds` | Generate GitHub-style `id="..."` attributes on headings (with deduplication). |
| `moGfmTables` | Recognise `| col | col |` tables. |
| `moGfmStrikethrough` | Recognise `~~text~~`. |
| `moGfmTaskLists` | Recognise `- [x]` / `- [ ]`. |
| `moGfmAutolinks` | Auto-link bare http(s) URLs in plain text. |

```pascal
// Strict CommonMark, no GFM
Html := PixieMarkdownToHtml(MdText, [moAllowRawHtml]);
```

## Known Limitations

### SVG Support

SVG rendering uses a single built-in renderer (`TPixieSvgCanvasRenderer`) on all platforms. SVG elements are drawn as native vector graphics through each backend's canvas path API — no rasterisation and no external dependencies. This ensures consistent rendering across Windows, Linux, macOS, Qt, FMX, and PDF export.

Supported SVG features: rect, circle, ellipse, line, polyline, polygon, path commands (M/L/H/V/C/S/Q/T/A/Z), text, `use`/`symbol`, `clipPath`, linearGradient, radialGradient, opacity, viewBox clipping, and transforms.

Not yet supported: spreadMethod (reflect/repeat), masks, filters, embedded images, CSS `style` selectors, `tspan`/`textPath`.

### Conic Gradients

`conic-gradient()` is rendered natively on Windows (via Direct2D) and Qt5/Qt6 (via `QConicalGradient`). On Linux and macOS it is approximated using 360 pie-sector triangles, which may show minor banding artefacts on large areas.

### CSS Features Not Supported

- `grid-template-areas`, `repeat()`, named grid lines, `grid-auto-flow: column | dense`, `subgrid`
- CSS animations and transitions
- `@font-face` (custom web fonts)
- `@keyframes`
- `calc()` expressions
- `position: sticky`
- CSS transforms (`transform`, `rotate`, `scale`, `translate`)
- CSS filters (`filter`, `backdrop-filter`)
- `box-shadow`, `text-shadow`
- Multi-column layout (`columns`)
- `clip-path`, `mask`
- `writing-mode` (vertical text)

### HTML Features Not Supported

- `<video>`, `<audio>`, `<canvas>`, `<iframe>`
- `<select>`, `<option>` (dropdown lists)
- `<input type="range|date|file|color|number">`
- `<form>` submission
- JavaScript execution
- `contenteditable`

### Other Limitations

- No network stack — external resources (images, CSS) must be provided via the `OnFetchUrl` callback.
- `Document.Rebuild` resets focus, hover, and active state.
- Opacity layer stack is limited to 16 levels on Linux (Cairo backend).
