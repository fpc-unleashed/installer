unit Pixie.MasterCss;

// Built-in user-agent stylesheet applied to all documents before author styles.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

const
  PixieMasterCss =
    'html {' +
    '  display: block;' +
    '  color: black;' +
    '}' +

    'head {' +
    '  display: none' +
    '}' +

    'meta {' +
    '  display: none' +
    '}' +

    'title {' +
    '  display: none' +
    '}' +

    'link {' +
    '  display: none' +
    '}' +

    'style {' +
    '  display: none' +
    '}' +

    'script {' +
    '  display: none' +
    '}' +

    'body {' +
    '  display:block;' +
    '  margin:8px;' +
    '}' +

    'p {' +
    '  display:block;' +
    '  margin-top:1em;' +
    '  margin-bottom:1em;' +
    '}' +

    'b, strong {' +
    '  display:inline;' +
    '  font-weight:bold;' +
    '}' +

    'i, em, cite {' +
    '  display:inline;' +
    '  font-style:italic;' +
    '}' +

    'ins, u {' +
    '  text-decoration:underline' +
    '}' +

    'del, s, strike {' +
    '  text-decoration:line-through' +
    '}' +

    'center {' +
    '  text-align:-webkit-center;' +
    '  display:block;' +
    '}' +

    'a:link {' +
    '  text-decoration: underline;' +
    '  color: #00f;' +
    '  cursor: pointer;' +
    '}' +

    'h1, h2, h3, h4, h5, h6, div {' +
    '  display:block;' +
    '}' +

    'h1 {' +
    '  font-weight:bold;' +
    '  margin-top:0.67em;' +
    '  margin-bottom:0.67em;' +
    '  font-size: 2em;' +
    '}' +

    'h2 {' +
    '  font-weight:bold;' +
    '  margin-top:0.83em;' +
    '  margin-bottom:0.83em;' +
    '  font-size: 1.5em;' +
    '}' +

    'h3 {' +
    '  font-weight:bold;' +
    '  margin-top:1em;' +
    '  margin-bottom:1em;' +
    '  font-size:1.17em;' +
    '}' +

    'h4 {' +
    '  font-weight:bold;' +
    '  margin-top:1.33em;' +
    '  margin-bottom:1.33em' +
    '}' +

    'h5 {' +
    '  font-weight:bold;' +
    '  margin-top:1.67em;' +
    '  margin-bottom:1.67em;' +
    '  font-size:.83em;' +
    '}' +

    'h6 {' +
    '  font-weight:bold;' +
    '  margin-top:2.33em;' +
    '  margin-bottom:2.33em;' +
    '  font-size:.67em;' +
    '}' +

    'br {' +
    '  display:inline-block;' +
    '}' +

    'br[clear="all"] {' +
    '  clear:both;' +
    '}' +

    'br[clear="left"] {' +
    '  clear:left;' +
    '}' +

    'br[clear="right"] {' +
    '  clear:right;' +
    '}' +

    'span {' +
    '  display:inline' +
    '}' +

    'img {' +
    '  display: inline-block;' +
    '}' +

    'img[align="right"] {' +
    '  float: right;' +
    '}' +

    'img[align="left"] {' +
    '  float: left;' +
    '}' +

    'hr {' +
    '  display: block;' +
    '  margin-top: 0.5em;' +
    '  margin-bottom: 0.5em;' +
    '  margin-left: auto;' +
    '  margin-right: auto;' +
    '  border-style: inset;' +
    '  border-width: 1px' +
    '}' +

    'table {' +
    '  display: table;' +
    '  border-collapse: separate;' +
    '  border-spacing: 2px;' +
    '  border-top-color:gray;' +
    '  border-left-color:gray;' +
    '  border-bottom-color:black;' +
    '  border-right-color:black;' +
    '}' +

    'tbody {' +
    '  display:table-row-group;' +
    '  vertical-align:middle;' +
    '}' +

    'thead {' +
    '  display:table-header-group;' +
    '  vertical-align:middle;' +
    '}' +

    'tfoot {' +
    '  display:table-footer-group;' +
    '  vertical-align:middle;' +
    '}' +

    'tr {' +
    '  display: table-row;' +
    '  vertical-align: inherit;' +
    '  border-color: inherit;' +
    '}' +

    'td, th {' +
    '  display: table-cell;' +
    '  vertical-align: inherit;' +
    '  border-width:1px;' +
    '  padding:1px;' +
    '}' +

    'th {' +
    '  font-weight: bold;' +
    '}' +

    'table[border] {' +
    '  border-style:outset;' +
    '}' +

    'table[border^="0"] {' +
    '  border-style:none;' +
    '}' +

    'table[border] td, table[border] th {' +
    '  border-style:inset;' +
    '}' +

    'table[border^="0"] td, table[border^="0"] th {' +
    '  border-style:none;' +
    '}' +

    'table[align=left] {' +
    '  float: left;' +
    '}' +

    'table[align=right] {' +
    '  float: right;' +
    '}' +

    'table[align=center] {' +
    '  margin-left: auto;' +
    '  margin-right: auto;' +
    '}' +

    'colgroup {' +
    '  display: table-column-group;' +
    '}' +

    'col {' +
    '  display: table-column;' +
    '}' +

    'caption {' +
    '  display: table-caption;' +
    '  text-align: center;' +
    '}' +

    'td[nowrap], th[nowrap] {' +
    '  white-space:nowrap;' +
    '}' +

    'tt, code, kbd, samp {' +
    '  font-family: monospace' +
    '}' +

    'pre, xmp, plaintext, listing {' +
    '  display: block;' +
    '  font-family: monospace;' +
    '  white-space: pre;' +
    '  margin: 1em 0' +
    '}' +

    'ul, menu, dir {' +
    '  display: block;' +
    '  list-style-type: disc;' +
    '  margin-top: 1em;' +
    '  margin-bottom: 1em;' +
    '  margin-left: 0;' +
    '  margin-right: 0;' +
    '  padding-left: 40px' +
    '}' +

    'ol {' +
    '  display: block;' +
    '  list-style-type: decimal;' +
    '  margin-top: 1em;' +
    '  margin-bottom: 1em;' +
    '  margin-left: 0;' +
    '  margin-right: 0;' +
    '  padding-left: 40px' +
    '}' +

    'li {' +
    '  display: list-item;' +
    '}' +

    'ul ul, ol ul {' +
    '  list-style-type: circle;' +
    '}' +

    'ol ol ul, ol ul ul, ul ol ul, ul ul ul {' +
    '  list-style-type: square;' +
    '}' +

    'dd {' +
    '  display: block;' +
    '  margin-left: 40px;' +
    '}' +

    'dl {' +
    '  display: block;' +
    '  margin-top: 1em;' +
    '  margin-bottom: 1em;' +
    '  margin-left: 0;' +
    '  margin-right: 0;' +
    '}' +

    'dt {' +
    '  display: block;' +
    '}' +

    'ol ul, ul ol, ul ul, ol ol {' +
    '  margin-top: 0;' +
    '  margin-bottom: 0' +
    '}' +

    'blockquote {' +
    '  display: block;' +
    '  margin-top: 1em;' +
    '  margin-bottom: 1em;' +
    '  margin-left: 40px;' +
    '  margin-right: 40px;' +
    '}' +

    'fieldset {' +
    '  display: block;' +
    '  margin-left: 2px;' +
    '  margin-right: 2px;' +
    '  padding-top: 0.35em;' +
    '  padding-bottom: 0.625em;' +
    '  padding-left: 0.75em;' +
    '  padding-right: 0.75em;' +
    '  border: 2px groove #c0c0c0;' +
    '}' +

    'legend {' +
    '  display: block;' +
    '  padding-left: 2px;' +
    '  padding-right: 2px;' +
    '}' +

    'form {' +
    '  display: block;' +
    '  margin-top: 0em;' +
    '}' +

    'option, datalist {' +
    '  display: none;' +
    '}' +

    'input, textarea, keygen, select, button, isindex {' +
    '  font-family: sans-serif;' +
    '  margin: 0em;' +
    '  color: initial;' +
    '  line-height: normal;' +
    '  text-transform: none;' +
    '  text-indent: 0;' +
    '  text-shadow: none;' +
    '  display: inline-block;' +
    '  box-sizing: border-box;' +
    '}' +

    'input[type="hidden"] {' +
    '  display: none;' +
    '}' +

    'input[type="checkbox"], input[type="radio"] {' +
    '  vertical-align: middle;' +
    '}' +

    'progress, meter {' +
    '  display: inline-block;' +
    '  vertical-align: -0.2em;' +
    '}' +

    'button, input[type="submit"], input[type="button"], input[type="reset"] {' +
    '  font-size: 13.333px;' +
    '  padding: 4px 14px;' +
    '  cursor: default;' +
    '  vertical-align: middle;' +
    '}' +

    'input[type="text"], input[type="password"] {' +
    '  padding: 2px 4px;' +
    '  cursor: text;' +
    '  vertical-align: middle;' +
    '}' +

    'textarea {' +
    '  padding: 4px;' +
    '  cursor: text;' +
    '  vertical-align: middle;' +
    '}' +

    'address {' +
    '  display: block;' +
    '  font-style: italic;' +
    '}' +

    'article, aside, footer, header, hgroup, nav, section {' +
    '  display: block;' +
    '}' +

    'sub {' +
    '  vertical-align: sub;' +
    '  font-size: smaller;' +
    '}' +

    'sup {' +
    '  vertical-align: super;' +
    '  font-size: smaller;' +
    '}' +

    'small {' +
    '  font-size: smaller;' +
    '}' +

    'dfn, var {' +
    '  font-style: italic;' +
    '}' +

    'abbr[title] {' +
    '  text-decoration: underline dotted;' +
    '}' +

    'mark {' +
    '  background-color: yellow;' +
    '  color: black;' +
    '}' +

    'q::before {' +
    '  content: "\201C";' +
    '}' +

    'q::after {' +
    '  content: "\201D";' +
    '}' +

    'figure {' +
    '  display: block;' +
    '  margin-top: 1em;' +
    '  margin-bottom: 1em;' +
    '  margin-left: 40px;' +
    '  margin-right: 40px;' +
    '}' +

    'figcaption {' +
    '  display: block;' +
    '}' +

    'details {' +
    '  display: block;' +
    '}' +

    'summary {' +
    '  display: block;' +
    '  cursor: pointer;' +
    '}' +

    'summary::before {' +
    '  content: "\25B8 ";' +
    '}' +

    'details[open] > summary::before {' +
    '  content: "\25BE ";' +
    '}';

  // Quirks mode: table cells, table headers, and captions do not inherit
  // font-size from the body — they reset to medium. This matches browser
  // behaviour for documents in quirks mode.
  PixieQuirksCss =
    'table, td, th, caption {' +
    '  font-size: medium;' +
    '}';

implementation

end.
