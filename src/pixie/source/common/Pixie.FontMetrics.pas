unit Pixie.FontMetrics;

// Hardcoded font metrics table for platforms where direct TrueType file access
// is unavailable (e.g. iOS, Android). Values are raw units-per-em from font
// hhea/OS2 tables — multiply by (fontSize / UnitsPerEm) to get pixel values.
//
// Sources: Capsize metrics collection (seek-oss/capsize), CoreText extraction,
// TrueType hhea/OS2 tables from font files.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

type
  TPixieFontMetricsEntry = record
    Family: string;
    UnitsPerEm: Integer;
    Ascent: Integer;
    Descent: Integer;
    LineGap: Integer;
    XHeight: Integer;
    CapHeight: Integer;
  end;

  TPixieFontCategory = (fmcSansSerif, fmcSerif, fmcMonospace);

// Look up metrics for a font family (case-insensitive).
// Returns True and fills Entry if found, False otherwise.
function PixieLookupFontMetrics(const Family: string;
  out Entry: TPixieFontMetricsEntry): Boolean;

// Returns generic fallback metrics for a font category.
procedure PixieDefaultFontMetrics(Category: TPixieFontCategory;
  out Entry: TPixieFontMetricsEntry);

implementation

uses
  SysUtils;

const
  FontMetricsCount = 71;

  FontMetrics: array[0..FontMetricsCount - 1] of TPixieFontMetricsEntry = (
    // -----------------------------------------------------------------------
    // Windows system fonts
    // -----------------------------------------------------------------------
    (Family: 'segoe ui';            UnitsPerEm: 2048; Ascent: 2210; Descent:  514; LineGap:   0; XHeight: 1024; CapHeight: 1434),
    (Family: 'tahoma';              UnitsPerEm: 2048; Ascent: 2049; Descent:  423; LineGap:   0; XHeight: 1117; CapHeight: 1489),
    (Family: 'trebuchet ms';        UnitsPerEm: 2048; Ascent: 1923; Descent:  455; LineGap:   0; XHeight: 1071; CapHeight: 1465),
    (Family: 'calibri';             UnitsPerEm: 2048; Ascent: 1536; Descent:  512; LineGap: 452; XHeight:  951; CapHeight: 1294),
    (Family: 'candara';             UnitsPerEm: 2048; Ascent: 1484; Descent:  564; LineGap: 452; XHeight:  950; CapHeight: 1308),
    (Family: 'cambria';             UnitsPerEm: 2048; Ascent: 1946; Descent:  455; LineGap:   0; XHeight:  956; CapHeight: 1365),
    (Family: 'consolas';            UnitsPerEm: 2048; Ascent: 1521; Descent:  527; LineGap: 350; XHeight: 1004; CapHeight: 1307),
    (Family: 'impact';              UnitsPerEm: 2048; Ascent: 2066; Descent:  432; LineGap:   0; XHeight: 1327; CapHeight: 1619),
    (Family: 'comic sans ms';       UnitsPerEm: 2048; Ascent: 2257; Descent:  597; LineGap:   0; XHeight: 1105; CapHeight: 1554),
    (Family: 'palatino linotype';   UnitsPerEm: 2048; Ascent: 1499; Descent:  582; LineGap: 682; XHeight: 1062; CapHeight: 1466),

    // -----------------------------------------------------------------------
    // Cross-platform fonts
    // -----------------------------------------------------------------------
    (Family: 'arial';               UnitsPerEm: 2048; Ascent: 1854; Descent:  434; LineGap:  67; XHeight: 1062; CapHeight: 1467),
    (Family: 'helvetica';           UnitsPerEm: 2048; Ascent: 1577; Descent:  471; LineGap:   0; XHeight: 1071; CapHeight: 1469),
    (Family: 'times new roman';     UnitsPerEm: 2048; Ascent: 1825; Descent:  443; LineGap:  87; XHeight:  916; CapHeight: 1356),
    (Family: 'georgia';             UnitsPerEm: 2048; Ascent: 1878; Descent:  449; LineGap:   0; XHeight:  986; CapHeight: 1419),
    (Family: 'verdana';             UnitsPerEm: 2048; Ascent: 2059; Descent:  430; LineGap:   0; XHeight: 1117; CapHeight: 1489),
    (Family: 'courier new';         UnitsPerEm: 2048; Ascent: 1705; Descent:  615; LineGap:   0; XHeight:  866; CapHeight: 1170),

    // -----------------------------------------------------------------------
    // Apple system fonts
    // -----------------------------------------------------------------------
    (Family: 'sf pro';              UnitsPerEm: 2048; Ascent: 1577; Descent:  471; LineGap:   0; XHeight: 1071; CapHeight: 1469),
    (Family: 'sf pro text';         UnitsPerEm: 2048; Ascent: 1577; Descent:  471; LineGap:   0; XHeight: 1071; CapHeight: 1469),
    (Family: 'sf pro display';      UnitsPerEm: 2048; Ascent: 1577; Descent:  471; LineGap:   0; XHeight: 1071; CapHeight: 1469),
    (Family: 'sf pro rounded';      UnitsPerEm: 2048; Ascent: 1577; Descent:  471; LineGap:   0; XHeight: 1071; CapHeight: 1469),
    (Family: 'sf compact';          UnitsPerEm: 2048; Ascent: 1577; Descent:  471; LineGap:   0; XHeight: 1071; CapHeight: 1469),
    (Family: 'sf compact rounded';  UnitsPerEm: 2048; Ascent: 1577; Descent:  471; LineGap:   0; XHeight: 1071; CapHeight: 1469),
    (Family: 'sf mono';             UnitsPerEm: 2048; Ascent: 1577; Descent:  471; LineGap:   0; XHeight: 1071; CapHeight: 1469),
    (Family: 'new york';            UnitsPerEm: 2048; Ascent: 1577; Descent:  471; LineGap:   0; XHeight: 1071; CapHeight: 1469),
    (Family: 'helvetica neue';      UnitsPerEm: 1000; Ascent:  952; Descent:  213; LineGap:  28; XHeight:  517; CapHeight:  714),
    (Family: 'menlo';               UnitsPerEm: 2048; Ascent: 1901; Descent:  483; LineGap:   0; XHeight: 1120; CapHeight: 1493),
    (Family: 'monaco';              UnitsPerEm: 2048; Ascent: 2048; Descent:  512; LineGap: 171; XHeight: 1117; CapHeight: 1552),
    (Family: 'avenir';              UnitsPerEm: 1000; Ascent:  880; Descent:  120; LineGap:   0; XHeight:  468; CapHeight:  708),
    (Family: 'avenir next';         UnitsPerEm: 1000; Ascent:  880; Descent:  120; LineGap:   0; XHeight:  468; CapHeight:  708),
    (Family: 'futura';              UnitsPerEm: 2048; Ascent: 2127; Descent:  532; LineGap:  61; XHeight:  988; CapHeight: 1559),
    (Family: 'baskerville';         UnitsPerEm: 2048; Ascent: 1839; Descent:  504; LineGap:   0; XHeight:  819; CapHeight: 1370),
    (Family: 'palatino';            UnitsPerEm: 2048; Ascent: 1685; Descent:  568; LineGap:   0; XHeight:  965; CapHeight: 1423),
    (Family: 'pingfang sc';         UnitsPerEm: 1000; Ascent: 1060; Descent:  340; LineGap:   0; XHeight:  600; CapHeight:  860),
    (Family: 'pingfang tc';         UnitsPerEm: 1000; Ascent: 1060; Descent:  340; LineGap:   0; XHeight:  600; CapHeight:  860),
    (Family: 'pingfang hk';         UnitsPerEm: 1000; Ascent: 1060; Descent:  340; LineGap:   0; XHeight:  600; CapHeight:  860),
    (Family: 'hiragino sans';       UnitsPerEm: 1000; Ascent:  880; Descent:  120; LineGap: 500; XHeight:  545; CapHeight:  766),

    // -----------------------------------------------------------------------
    // Google / Android fonts
    // -----------------------------------------------------------------------
    (Family: 'roboto';              UnitsPerEm: 2048; Ascent: 1900; Descent:  500; LineGap:   0; XHeight: 1082; CapHeight: 1456),
    (Family: 'open sans';           UnitsPerEm: 2048; Ascent: 2189; Descent:  600; LineGap:   0; XHeight: 1096; CapHeight: 1462),
    (Family: 'noto sans';           UnitsPerEm: 1000; Ascent: 1069; Descent:  293; LineGap:   0; XHeight:  536; CapHeight:  714),
    (Family: 'noto serif';          UnitsPerEm: 1000; Ascent: 1069; Descent:  293; LineGap:   0; XHeight:  536; CapHeight:  714),
    (Family: 'inter';               UnitsPerEm: 2048; Ascent: 1984; Descent:  494; LineGap:   0; XHeight: 1118; CapHeight: 1490),
    (Family: 'lato';                UnitsPerEm: 2000; Ascent: 1974; Descent:  426; LineGap:   0; XHeight: 1013; CapHeight: 1433),

    // -----------------------------------------------------------------------
    // Linux system fonts
    // -----------------------------------------------------------------------

    // DejaVu (default on Debian, Ubuntu, Fedora, etc.)
    (Family: 'dejavu sans';         UnitsPerEm: 2048; Ascent: 1901; Descent:  483; LineGap:   0; XHeight: 1120; CapHeight: 1493),
    (Family: 'dejavu serif';        UnitsPerEm: 2048; Ascent: 1901; Descent:  483; LineGap:   0; XHeight: 1063; CapHeight: 1493),
    (Family: 'dejavu sans mono';    UnitsPerEm: 2048; Ascent: 1901; Descent:  483; LineGap:   0; XHeight: 1120; CapHeight: 1493),

    // Liberation (metrically compatible with Arial/Times/Courier)
    (Family: 'liberation sans';     UnitsPerEm: 2048; Ascent: 1854; Descent:  434; LineGap:  67; XHeight: 1082; CapHeight: 1409),
    (Family: 'liberation serif';    UnitsPerEm: 2048; Ascent: 1825; Descent:  443; LineGap:  87; XHeight:  940; CapHeight: 1341),
    (Family: 'liberation mono';     UnitsPerEm: 2048; Ascent: 1705; Descent:  615; LineGap:   0; XHeight: 1082; CapHeight: 1349),

    // Cantarell (GNOME default)
    (Family: 'cantarell';           UnitsPerEm: 2048; Ascent: 2240; Descent:  660; LineGap:   0; XHeight: 1100; CapHeight: 1470),

    // Ubuntu
    (Family: 'ubuntu';              UnitsPerEm: 1000; Ascent:  932; Descent:  189; LineGap:   0; XHeight:  518; CapHeight:  693),
    (Family: 'ubuntu mono';         UnitsPerEm: 1000; Ascent:  932; Descent:  189; LineGap:   0; XHeight:  518; CapHeight:  693),

    // Droid (older Android/Linux default)
    (Family: 'droid sans';          UnitsPerEm: 2048; Ascent: 1900; Descent:  500; LineGap:   0; XHeight: 1082; CapHeight: 1456),
    (Family: 'droid serif';         UnitsPerEm: 2048; Ascent: 1638; Descent:  410; LineGap:   0; XHeight:  948; CapHeight: 1340),
    (Family: 'droid sans mono';     UnitsPerEm: 2048; Ascent: 1900; Descent:  500; LineGap:   0; XHeight: 1065; CapHeight: 1462),

    // GNU FreeFont
    (Family: 'freesans';            UnitsPerEm: 1000; Ascent:  900; Descent:  200; LineGap:  67; XHeight:  523; CapHeight:  729),
    (Family: 'freeserif';           UnitsPerEm: 1000; Ascent:  900; Descent:  200; LineGap:  67; XHeight:  450; CapHeight:  662),
    (Family: 'freemono';            UnitsPerEm: 1000; Ascent:  800; Descent:  200; LineGap:   0; XHeight:  426; CapHeight:  563),

    // Other popular Linux / web fonts (Capsize data)
    (Family: 'fira sans';           UnitsPerEm: 1000; Ascent:  935; Descent:  265; LineGap:   0; XHeight:  527; CapHeight:  689),
    (Family: 'fira mono';           UnitsPerEm: 1000; Ascent:  935; Descent:  265; LineGap:   0; XHeight:  527; CapHeight:  689),
    (Family: 'fira code';           UnitsPerEm: 2000; Ascent: 1980; Descent:  644; LineGap:   0; XHeight: 1053; CapHeight: 1377),
    (Family: 'pt sans';             UnitsPerEm: 1000; Ascent: 1018; Descent:  276; LineGap:   0; XHeight:  500; CapHeight:  700),
    (Family: 'pt serif';            UnitsPerEm: 1000; Ascent: 1039; Descent:  286; LineGap:   0; XHeight:  500; CapHeight:  700),
    (Family: 'pt mono';             UnitsPerEm: 1000; Ascent:  885; Descent:  235; LineGap:   0; XHeight:  500; CapHeight:  700),
    (Family: 'source code pro';     UnitsPerEm: 1000; Ascent:  984; Descent:  273; LineGap:   0; XHeight:  486; CapHeight:  660),
    (Family: 'source sans 3';       UnitsPerEm: 1000; Ascent: 1024; Descent:  400; LineGap:   0; XHeight:  486; CapHeight:  660),
    (Family: 'source serif 4';      UnitsPerEm: 1000; Ascent: 1036; Descent:  335; LineGap:   0; XHeight:  475; CapHeight:  670),
    (Family: 'noto mono';           UnitsPerEm: 2048; Ascent: 1900; Descent:  500; LineGap:   0; XHeight: 1098; CapHeight: 1462),
    (Family: 'noto sans mono';      UnitsPerEm: 1000; Ascent: 1069; Descent:  293; LineGap:   0; XHeight:  536; CapHeight:  714),

    // Nimbus / URW (Ghostscript fonts, common on Linux)
    (Family: 'nimbus sans';         UnitsPerEm: 1000; Ascent:  729; Descent:  271; LineGap: 200; XHeight:  516; CapHeight:  718),
    (Family: 'nimbus roman';        UnitsPerEm: 1000; Ascent:  683; Descent:  317; LineGap: 200; XHeight:  450; CapHeight:  662),
    (Family: 'nimbus mono ps';      UnitsPerEm: 1000; Ascent:  603; Descent:  397; LineGap: 200; XHeight:  417; CapHeight:  559)
  );

function LowerCaseFontName(const S: string): string;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    if (Result[I] >= 'A') and (Result[I] <= 'Z') then
      Result[I] := Chr(Ord(Result[I]) + 32);
end;

function PixieLookupFontMetrics(const Family: string;
  out Entry: TPixieFontMetricsEntry): Boolean;
var
  I: Integer;
  Key: string;
begin
  Key := LowerCaseFontName(Trim(Family));
  for I := 0 to FontMetricsCount - 1 do
    if FontMetrics[I].Family = Key then
    begin
      Entry := FontMetrics[I];
      Result := True;
      Exit;
    end;
  Result := False;
end;

procedure PixieDefaultFontMetrics(Category: TPixieFontCategory;
  out Entry: TPixieFontMetricsEntry);
begin
  Entry.Family := '';
  Entry.UnitsPerEm := 2048;
  case Category of
    fmcSansSerif:
      begin
        // Based on Arial
        Entry.Ascent    := 1854;
        Entry.Descent   :=  434;
        Entry.LineGap   :=   67;
        Entry.XHeight   := 1062;
        Entry.CapHeight := 1467;
      end;
    fmcSerif:
      begin
        // Based on Times New Roman
        Entry.Ascent    := 1825;
        Entry.Descent   :=  443;
        Entry.LineGap   :=   87;
        Entry.XHeight   :=  916;
        Entry.CapHeight := 1356;
      end;
    fmcMonospace:
      begin
        // Based on Courier New
        Entry.Ascent    := 1705;
        Entry.Descent   :=  615;
        Entry.LineGap   :=    0;
        Entry.XHeight   :=  866;
        Entry.CapHeight := 1170;
      end;
  end;
end;

end.
