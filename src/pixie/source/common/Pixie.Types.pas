unit Pixie.Types;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Generics.Collections, Math;

{$IFNDEF FPC}
type
  PtrUInt = NativeUInt;
  PtrInt = NativeInt;
{$ENDIF}

const
  SPixieBinaryContent = 'Binary content';

type
  EPixieBinaryContent = class(Exception);

function PixieIsBinaryString(const S: string): Boolean;

type
  TPixiePixel = Single;
  ucode_t = UInt32;

  // Document mode
  TPixieDocumentMode = (
    dmNoQuirks,
    dmQuirks,
    dmLimitedQuirks
  );

  // Text decoration line (flags - use integer constants)
  // style_text_decoration_line_strings = 'none;underline;overline;line-through'

  // Text decoration style
  // 'solid;double;dotted;dashed;wavy'
  TPixieTextDecorationStyle = (
    tdsSOlid,
    tdsDouble,
    tdsDotted,
    tdsDashed,
    tdsWavy
  );

  // Text decoration thickness
  // 'auto;from-font'
  TPixieTextDecorationThickness = (
    tdtAuto,
    tdtFromFont
  );

  // Text emphasis position (flags - use integer constants)
  // 'over;under;left;right'

  // Display
  // 'none;block;inline;inline-block;inline-table;list-item;table;table-caption;table-cell;table-column;table-column-group;table-footer-group;table-header-group;table-row;table-row-group;inline-text;flex;inline-flex'
  TPixieDisplay = (
    displayNone,
    displayBlock,
    displayInline,
    displayInlineBlock,
    displayInlineTable,
    displayListItem,
    displayTable,
    displayTableCaption,
    displayTableCell,
    displayTableColumn,
    displayTableColumnGroup,
    displayTableFooterGroup,
    displayTableHeaderGroup,
    displayTableRow,
    displayTableRowGroup,
    displayInlineText,
    displayFlex,
    displayInlineFlex,
    displayGrid,
    displayInlineGrid,
    displayFlowRoot
  );

  // Font size
  // 'xx-small;x-small;small;medium;large;x-large;xx-large;smaller;larger'
  TPixieFontSize = (
    fsXXSmall,
    fsXSmall,
    fsSmall,
    fsMedium,
    fsLarge,
    fsXLarge,
    fsXXLarge,
    fsSmaller,
    fsLarger
  );

  // Font style
  // 'normal;italic'
  TPixieFontStyle = (
    fstNormal,
    fstItalic
  );

  // Font variant
  // 'normal;small-caps'
  TPixieFontVariant = (
    fvNormal,
    fvSmallCaps
  );

  // Font weight
  // 'normal;bold;bolder;lighter'
  TPixieFontWeight = (
    fwNormal,
    fwBold,
    fwBolder,
    fwLighter
  );

  // List style type
  // 'none;circle;disc;square;armenian;cjk-ideographic;decimal;decimal-leading-zero;georgian;hebrew;hiragana;hiragana-iroha;katakana;katakana-iroha;lower-alpha;lower-greek;lower-latin;lower-roman;upper-alpha;upper-latin;upper-roman'
  TPixieListStyleType = (
    lstNone,
    lstCircle,
    lstDisc,
    lstSquare,
    lstArmenian,
    lstCjkIdeographic,
    lstDecimal,
    lstDecimalLeadingZero,
    lstGeorgian,
    lstHebrew,
    lstHiragana,
    lstHiraganaIroha,
    lstKatakana,
    lstKatakanaIroha,
    lstLowerAlpha,
    lstLowerGreek,
    lstLowerLatin,
    lstLowerRoman,
    lstUpperAlpha,
    lstUpperLatin,
    lstUpperRoman
  );

  // List style position
  // 'inside;outside'
  TPixieListStylePosition = (
    lspInside,
    lspOutside
  );

  // Vertical align
  // 'baseline;sub;super;top;text-top;middle;bottom;text-bottom'
  TPixieVerticalAlign = (
    vaBaseline,
    vaSub,
    vaSuper,
    vaTop,
    vaTextTop,
    vaMiddle,
    vaBottom,
    vaTextBottom
  );

  // Border width
  // 'thin;medium;thick'
  TPixieBorderWidth = (
    bwThin,
    bwMedium,
    bwThick
  );

  // Border style
  // 'none;hidden;dotted;dashed;solid;double;groove;ridge;inset;outset'
  TPixieBorderStyle = (
    bsNone,
    bsHidden,
    bsDotted,
    bsDashed,
    bsSolid,
    bsDouble,
    bsGroove,
    bsRidge,
    bsInset,
    bsOutset
  );

  // SVG stroke line cap
  TPixieLineCap = (lcButt, lcRound, lcSquare);

  // SVG stroke line join
  TPixieLineJoin = (ljMiter, ljRound, ljBevel);

  // Element float
  // 'none;left;right'
  TPixieElementFloat = (
    efNone,
    efLeft,
    efRight
  );

  // Element clear
  // 'none;left;right;both'
  TPixieElementClear = (
    ecNone,
    ecLeft,
    ecRight,
    ecBoth
  );

  // CSS units
  // 'none;%;in;cm;mm;em;ex;pt;pc;px;vw;vh;vmin;vmax;rem;ch;fr;cqw;cqh;cqi;cqb;cqmin;cqmax'
  TPixieCssUnits = (
    cssUnitsNone,
    cssUnitsPercentage,
    cssUnitsIn,
    cssUnitsCm,
    cssUnitsMm,
    cssUnitsEm,
    cssUnitsEx,
    cssUnitsPt,
    cssUnitsPc,
    cssUnitsPx,
    cssUnitsVw,
    cssUnitsVh,
    cssUnitsVmin,
    cssUnitsVmax,
    cssUnitsRem,
    cssUnitsCh,
    cssUnitsFr,
    cssUnitsCqw,
    cssUnitsCqh,
    cssUnitsCqi,
    cssUnitsCqb,
    cssUnitsCqmin,
    cssUnitsCqmax,
    cssUnitsCalc
  );

  // Background attachment
  // 'scroll;fixed'
  TPixieBackgroundAttachment = (
    baScroll,
    baFixed
  );

  // Background repeat
  // 'repeat;repeat-x;repeat-y;no-repeat'
  TPixieBackgroundRepeat = (
    brRepeat,
    brRepeatX,
    brRepeatY,
    brNoRepeat
  );

  // Background box
  // 'border-box;padding-box;content-box'
  TPixieBackgroundBox = (
    bbBorder,
    bbPadding,
    bbContent
  );

  // Background position
  // 'left;right;top;bottom;center'
  TPixieBackgroundPosition = (
    bpLeft,
    bpRight,
    bpTop,
    bpBottom,
    bpCenter
  );

  // Element position
  // 'static;relative;absolute;fixed'
  TPixieElementPosition = (
    epStatic,
    epRelative,
    epAbsolute,
    epFixed,
    epSticky
  );

  // Text align
  // 'left;right;center;justify;-webkit-center'
  TPixieTextAlign = (
    taLeft,
    taRight,
    taCenter,
    taJustify,
    taBlockCenter,
    taBlockLeft,
    taBlockRight
  );

  // Text transform
  // 'none;capitalize;uppercase;lowercase'
  TPixieTextTransform = (
    ttNone,
    ttCapitalize,
    ttUppercase,
    ttLowercase
  );

  // White space
  // 'normal;nowrap;pre;pre-line;pre-wrap'
  TPixieWhiteSpace = (
    wsNormal,
    wsNowrap,
    wsPre,
    wsPreLine,
    wsPreWrap
  );

  // Overflow wrap
  // 'normal;break-word;anywhere'
  TPixieOverflowWrap = (
    owNormal,
    owBreakWord,
    owAnywhere
  );

  // Overflow
  // 'visible;hidden;scroll;auto;no-display;no-content'
  TPixieOverflow = (
    ovVisible,
    ovHidden,
    ovScroll,
    ovAuto,
    ovNoDisplay,
    ovNoContent
  );

  // Background size
  // 'auto;cover;contain'
  TPixieBackgroundSize = (
    bszAuto,
    bszCover,
    bszContain
  );

  // Visibility
  // 'visible;hidden;collapse'
  TPixieVisibility = (
    visVisible,
    visHidden,
    visCollapse
  );

  // User select
  // 'auto;text;none;all'
  TPixieUserSelect = (
    usAuto,
    usText,
    usNone,
    usAll
  );

  // Border collapse
  // 'collapse;separate'
  TPixieBorderCollapse = (
    bcCollapse,
    bcSeparate
  );

  // Table layout
  // 'auto;fixed'
  TPixieTableLayout = (
    tlAuto,
    tlFixed
  );

  // Content property
  // 'none;normal;open-quote;close-quote;no-open-quote;no-close-quote'
  TPixieContentProperty = (
    cpNone,
    cpNormal,
    cpOpenQuote,
    cpCloseQuote,
    cpNoOpenQuote,
    cpNoCloseQuote
  );

  // Appearance
  // 'none;auto;menulist-button;textfield;button;checkbox;listbox;menulist;meter;progress-bar;push-button;radio;searchfield;slider-horizontal;square-button;textarea'
  TPixieAppearance = (
    appNone,
    appAuto,
    appMenulistButton,
    appTextfield,
    appButton,
    appCheckbox,
    appListbox,
    appMenulist,
    appMeter,
    appProgressBar,
    appPushButton,
    appRadio,
    appSearchfield,
    appSliderHorizontal,
    appSquareButton,
    appTextarea
  );

  // Box sizing
  // 'content-box;border-box'
  TPixieBoxSizing = (
    bxContentBox,
    bxBorderBox
  );

  // Media type
  // 'all;print;screen;tty;tv;projection;handheld;braille;embossed;aural;speech'
  TPixieMediaType = (
    mtUnknown,
    mtAll,
    mtPrint,
    mtScreen,
    mtFirstDeprecated
  );

  // Flex direction
  // 'row;row-reverse;column;column-reverse'
  TPixieFlexDirection = (
    fdRow,
    fdRowReverse,
    fdColumn,
    fdColumnReverse
  );

  // Flex wrap
  // 'nowrap;wrap;wrap-reverse'
  TPixieFlexWrap = (
    fwrNowrap,
    fwrWrap,
    fwrWrapReverse
  );

  // Flex justify content
  // 'normal;flex-start;flex-end;center;space-between;space-around;start;end;left;right;space-evenly;stretch'
  TPixieFlexJustifyContent = (
    fjcNormal,
    fjcFlexStart,
    fjcFlexEnd,
    fjcCenter,
    fjcSpaceBetween,
    fjcSpaceAround,
    fjcStart,
    fjcEnd,
    fjcLeft,
    fjcRight,
    fjcSpaceEvenly,
    fjcStretch
  );

  // Flex align items (values 0..10 are enum, higher values are flags)
  // 'auto;normal;stretch;baseline;center;start;end;self-start;self-end;flex-start;flex-end'
  TPixieFlexAlignItems = (
    faiAuto,
    faiNormal,
    faiStretch,
    faiBaseline,
    faiCenter,
    faiStart,
    faiEnd,
    faiSelfStart,
    faiSelfEnd,
    faiFlexStart,
    faiFlexEnd
  );

  // Flex align content
  // 'flex-start;start;flex-end;end;center;space-between;space-around;stretch'
  TPixieFlexAlignContent = (
    facFlexStart,
    facStart,
    facFlexEnd,
    facEnd,
    facCenter,
    facSpaceBetween,
    facSpaceAround,
    facStretch
  );

  // Flex basis
  // 'auto;content;fit-content;min-content;max-content'
  TPixieFlexBasis = (
    fbAuto,
    fbContent,
    fbFitContent,
    fbMinContent,
    fbMaxContent
  );

  // Caption side
  // 'top;bottom'
  TPixieCaptionSide = (
    csTop,
    csBottom
  );

  // Draw flag
  TPixieDrawFlag = (
    dfRoot,
    dfBlock,
    dfFloats,
    dfInlines,
    dfPositioned
  );

  // Render type
  TPixieRenderType = (
    rtAll,
    rtNoFixed,
    rtFixedOnly
  );

  // Baseline type
  TPixieBaselineType = (
    btNone,
    btTop,
    btBottom
  );

  // Flex clamp state (used by flex free-space distribution)
  TPixieFlexClampState = (
    fcsUnclamped,
    fcsInflexible,
    fcsMinViolation,
    fcsMaxViolation
  );

  // CBC value type
  TPixieCbcValueType = (
    cbcAbsolute,
    cbcPercentage,
    cbcAuto,
    cbcNone
  );

const
  // Text decoration line flags
  TextDecorationLineNone       = $00;
  TextDecorationLineUnderline  = $01;
  TextDecorationLineOverline   = $02;
  TextDecorationLineLineThrough = $04;

  // Text emphasis position flags
  TextEmphasisPositionOver  = $00;
  TextEmphasisPositionUnder = $01;
  TextEmphasisPositionLeft  = $02;
  TextEmphasisPositionRight = $04;

  // Select result flags
  SelectNoMatch          = $00;
  SelectMatch            = $01;
  SelectMatchPseudoClass = $02;
  SelectMatchWithBefore  = $10;
  SelectMatchWithAfter   = $20;

  // Size mode flags
  SizeModeNormal      = $00;
  SizeModeExactWidth  = $01;
  SizeModeExactHeight = $02;
  SizeModeExactEither = SizeModeExactWidth or SizeModeExactHeight;
  SizeModeContent     = $04;

  // Width/height predefined keyword indices (match AddLengthProperty
  // keyword strings in Pixie.Style.pas; widAuto doubles as 'none' for max-*)
  widAuto       = 0;  // also 'none' for max-width/max-height
  widFitContent = 1;
  widMinContent = 2;  // parsed but layout treats as auto (stub)
  widMaxContent = 3;  // parsed but layout treats as auto (stub)

  // Flex align items flags (combined with enum ordinals)
  FlexAlignItemsFirst  = $100;
  FlexAlignItemsLast   = $200;
  FlexAlignItemsUnsafe = $400;
  FlexAlignItemsSafe   = $800;

  // Border width values
  BorderWidthThinValue: TPixiePixel   = 1;
  BorderWidthMediumValue: TPixiePixel = 3;
  BorderWidthThickValue: TPixiePixel  = 5;

  // Keyword strings (semicolon-delimited, same order as enums)
  StyleDisplayStrings = 'none;block;inline;inline-block;inline-table;list-item;table;table-caption;table-cell;table-column;table-column-group;table-footer-group;table-header-group;table-row;table-row-group;inline-text;flex;inline-flex;grid;inline-grid;flow-root';
  FontSizeStrings = 'xx-small;x-small;small;medium;large;x-large;xx-large;smaller;larger';
  LineHeightStrings = 'normal';
  FontStyleStrings = 'normal;italic';
  // CSS 2.1 values first (fvNormal, fvSmallCaps), then CSS Fonts L3 caps
  // keywords that all collapse to fvSmallCaps in the canvas layer.
  FontVariantStrings = 'normal;small-caps;all-small-caps;petite-caps;all-petite-caps;unicase;titling-caps';
  FontWeightStrings = 'normal;bold;bolder;lighter';
  FontSystemFamilyNameStrings = 'caption;icon;menu;message-box;small-caption;status-bar';
  ListStyleTypeStrings = 'none;circle;disc;square;armenian;cjk-ideographic;decimal;decimal-leading-zero;georgian;hebrew;hiragana;hiragana-iroha;katakana;katakana-iroha;lower-alpha;lower-greek;lower-latin;lower-roman;upper-alpha;upper-latin;upper-roman';
  ListStylePositionStrings = 'inside;outside';
  VerticalAlignStrings = 'baseline;sub;super;top;text-top;middle;bottom;text-bottom';
  BorderWidthStrings = 'thin;medium;thick';
  BorderStyleStrings = 'none;hidden;dotted;dashed;solid;double;groove;ridge;inset;outset';
  ElementFloatStrings = 'none;left;right';
  ElementClearStrings = 'none;left;right;both';
  CssUnitsStrings = 'none;%;in;cm;mm;em;ex;pt;pc;px;vw;vh;vmin;vmax;rem;ch;fr;cqw;cqh;cqi;cqb;cqmin;cqmax';
  BackgroundAttachmentStrings = 'scroll;fixed';
  BackgroundRepeatStrings = 'repeat;repeat-x;repeat-y;no-repeat';
  BackgroundBoxStrings = 'border-box;padding-box;content-box';
  BackgroundPositionStrings = 'left;right;top;bottom;center';
  ElementPositionStrings = 'static;relative;absolute;fixed;sticky';
  SPixieBlockCenter = '-webkit-center';
  SPixieBlockLeft = '-webkit-left';
  SPixieBlockRight = '-webkit-right';
  TextAlignStrings = 'left;right;center;justify;' + SPixieBlockCenter +
    ';' + SPixieBlockLeft + ';' + SPixieBlockRight;
  TextTransformStrings = 'none;capitalize;uppercase;lowercase';
  WhiteSpaceStrings = 'normal;nowrap;pre;pre-line;pre-wrap';
  OverflowWrapStrings = 'normal;break-word;anywhere';
  OverflowStrings = 'visible;hidden;scroll;auto;no-display;no-content';
  BackgroundSizeStrings = 'auto;cover;contain';
  VisibilityStrings = 'visible;hidden;collapse';
  UserSelectStrings = 'auto;text;none;all';
  BorderCollapseStrings = 'collapse;separate';
  TableLayoutStrings = 'auto;fixed';
  ContentPropertyStrings = 'none;normal;open-quote;close-quote;no-open-quote;no-close-quote';
  AppearanceStrings = 'none;auto;menulist-button;textfield;button;checkbox;listbox;menulist;meter;progress-bar;push-button;radio;searchfield;slider-horizontal;square-button;textarea';
  BoxSizingStrings = 'content-box;border-box';
  DeprecatedMediaTypeStrings = 'tty;tv;projection;handheld;braille;embossed;aural;speech';
  MediaTypeStrings = 'all;print;screen;' + DeprecatedMediaTypeStrings;
  FlexDirectionStrings = 'row;row-reverse;column;column-reverse';
  FlexWrapStrings = 'nowrap;wrap;wrap-reverse';
  FlexJustifyContentStrings = 'normal;flex-start;flex-end;center;space-between;space-around;start;end;left;right;space-evenly;stretch';
  SelfPositionStrings = 'center;start;end;self-start;self-end;flex-start;flex-end';
  FlexAlignItemsStrings = 'auto;normal;stretch;baseline;' + SelfPositionStrings;
  FlexAlignContentStrings = 'flex-start;start;flex-end;end;center;space-between;space-around;stretch';
  FlexBasisStrings = 'auto;content;fit-content;min-content;max-content';
  CaptionSideStrings = 'top;bottom';
  TextDecorationLineStrings = 'none;underline;overline;line-through';
  TextDecorationStyleStrings = 'solid;double;dotted;dashed;wavy';
  TextDecorationThicknessStrings = 'auto;from-font';
  TextEmphasisPositionStrings = 'over;under;left;right';

  // Background position percentages
  BackgroundPositionPercentages: array[TPixieBackgroundPosition] of Single = (0, 100, 0, 100, 50);

  // Border width values array
  BorderWidthValues: array[TPixieBorderWidth] of TPixiePixel = (1, 3, 5);

type
  { TPixieMargins }
  TPixieMargins = record
    Left: TPixiePixel;
    Right: TPixiePixel;
    Top: TPixiePixel;
    Bottom: TPixiePixel;
    function Width: TPixiePixel;
    function Height: TPixiePixel;
    procedure Init;
  end;

  { TPixiePointF }
  TPixiePointF = record
    X: Single;
    Y: Single;
    class function Create(AX, AY: Single): TPixiePointF; static;
  end;

  { TPixieSize }
  TPixieSize = record
    Width: TPixiePixel;
    Height: TPixiePixel;
    class function Create(AWidth, AHeight: TPixiePixel): TPixieSize; static;
  end;

  { TPixiePosition }
  TPixiePosition = record
    X: TPixiePixel;
    Y: TPixiePixel;
    Width: TPixiePixel;
    Height: TPixiePixel;
    class function Create(AX, AY, AWidth, AHeight: TPixiePixel): TPixiePosition; static;
    function Right: TPixiePixel;
    function Bottom: TPixiePixel;
    function IsEmpty: Boolean;
    function DoesIntersect(const Val: TPixiePosition): Boolean;
    function Intersect(const Src: TPixiePosition): TPixiePosition;
    function IsPointInside(AX, AY: TPixiePixel): Boolean;
    procedure MoveTo(AX, AY: TPixiePixel);
    procedure Clear;
    procedure DoRound;
    procedure AddMargins(const Mg: TPixieMargins);
    procedure SubMargins(const Mg: TPixieMargins);
  end;

  PPixiePosition = ^TPixiePosition;

  { TPixieScrollValues }
  TPixieScrollValues = record
    Dx: TPixiePixel;
    Dy: TPixiePixel;
    ScrollBox: TPixiePosition;
    procedure Init;
  end;

  { TPixieFontMetrics }
  TPixieFontMetrics = record
    FontSize: TPixiePixel;
    Height: TPixiePixel;
    Ascent: TPixiePixel;
    Descent: TPixiePixel;
    XHeight: TPixiePixel;
    ChWidth: TPixiePixel;
    SubShift: TPixiePixel;
    SuperShift: TPixiePixel;
    DrawSpaces: Boolean;
    function BaseLine: TPixiePixel;
    procedure CalcShifts;
  end;

  { TPixieFontItem }
  TPixieFontItem = record
    Font: PtrUInt;
    Metrics: TPixieFontMetrics;
  end;

  { TPixieColorScheme }
  // Preferred colour scheme reported to 'prefers-color-scheme' media
  // queries. pcsAuto (the default) probes the host OS/toolkit; pcsLight
  // and pcsDark let the application force a scheme (e.g. a user toggle).
  TPixieColorScheme = (pcsAuto, pcsLight, pcsDark);

  { TPixieMediaFeatures }
  TPixieMediaFeatures = record
    MediaType: TPixieMediaType;
    Width: TPixiePixel;
    Height: TPixiePixel;
    DeviceWidth: TPixiePixel;
    DeviceHeight: TPixiePixel;
    Color: Integer;
    ColorIndex: Integer;
    Monochrome: Integer;
    Resolution: TPixiePixel;
    PrefersDark: Boolean;
    procedure Init;
  end;

  { TPixieTypedPixel }
  TPixieTypedPixel = record
    Value: TPixiePixel;
    ValueType: TPixieCbcValueType;
    class function Create(AValue: TPixiePixel; AType: TPixieCbcValueType): TPixieTypedPixel; static;
  end;

  { TPixieContainingBlockContext }
  TPixieContainingBlockContext = record
    Width: TPixieTypedPixel;
    RenderWidth: TPixieTypedPixel;
    MinWidth: TPixieTypedPixel;
    MaxWidth: TPixieTypedPixel;
    Height: TPixieTypedPixel;
    MinHeight: TPixieTypedPixel;
    MaxHeight: TPixieTypedPixel;
    ContextIdx: Integer;
    SizeMode: UInt32;
    procedure Init;
    function NewWidth(W: TPixiePixel; ASizeMode: UInt32 = SizeModeNormal): TPixieContainingBlockContext;
    function NewWidthHeight(W, H: TPixiePixel; ASizeMode: UInt32 = SizeModeNormal): TPixieContainingBlockContext;
  end;

  { TPixieFloatedBox }
  TPixieFloatedBox = record
    Pos: TPixiePosition;
    FloatSide: TPixieElementFloat;
    ClearFloats: TPixieElementClear;
    El: Pointer;
    Context: Integer;
    MinWidth: TPixiePixel;
  end;

  { TPixiePixelPixelCache }
  TPixiePixelPixelCache = record
    Hash: TPixiePixel;
    Val: TPixiePixel;
    IsValid: Boolean;
    IsDefault: Boolean;
    procedure Init;
    procedure Invalidate;
    procedure SetValue(AHash, AVal: TPixiePixel);
  end;

  { TPixieBaseline }
  TPixieBaseline = record
  private
    FValue: TPixiePixel;
    FType: TPixieBaselineType;
  public
    class function Create(AValue: TPixiePixel; AType: TPixieBaselineType): TPixieBaseline; static;
    procedure Init;
    procedure SetValues(AValue: TPixiePixel; AType: TPixieBaselineType);
    function GetOffsetFromTop(AHeight: TPixiePixel): TPixiePixel;
    function GetOffsetFromBottom(AHeight: TPixiePixel): TPixiePixel;
    procedure CalcFromPositions(ATop, ABottom: TPixiePixel);
    property Value: TPixiePixel read FValue write FValue;
    property BaselineType: TPixieBaselineType read FType write FType;
  end;

  { TPixieDefValue — a value with "is default" tracking }
  TPixieDefValue = record
  private
    FValue: TPixiePixel;
    FIsDefault: Boolean;
  public
    procedure Init(DefVal: TPixiePixel);
    procedure Reset(DefVal: TPixiePixel);
    function IsDefault: Boolean;
    procedure SetValue(NewVal: TPixiePixel);
    function Value: TPixiePixel;
    // Clamp AValue down to this value when set; no-op when default.
    procedure ClampMax(var AValue: TPixiePixel);
  end;

  // Generic collection types
  TPixieStringVector = TList<string>;
  TPixieIntVector = TList<Integer>;
  TPixiePixelVector = TList<TPixiePixel>;
  TPixieStringMap = TDictionary<string, string>;
  TPixieFontsMap = TDictionary<string, TPixieFontItem>;
  TPixiePositionVector = TList<TPixiePosition>;

  TPixieRenderItemCheckFunc = function(Ri: Pointer): Boolean of object;

  TPixieSplitResult = record
    Before: Pointer;  // TPixieRenderItem
    Block: Pointer;   // TPixieRenderItem
    After: Pointer;   // TPixieRenderItem
  end;

  // Cursor kinds for Pixie components
  TPixieCursorKind = (
    pxCurDefault, pxCurHandPoint, pxCurIBeam, pxCurCross, pxCurSizeAll);

implementation

function PixieIsBinaryString(const S: string): Boolean;
var
  I, Limit: Integer;
  C: Integer;
begin
  Limit := Length(S);
  if Limit > 4096 then
    Limit := 4096;
  for I := 1 to Limit do
  begin
    C := Ord(S[I]);
    if (C < 9) or ((C > 13) and (C < 32)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TPixieMargins }

function TPixieMargins.Width: TPixiePixel;
begin
  Result := Left + Right;
end;

function TPixieMargins.Height: TPixiePixel;
begin
  Result := Top + Bottom;
end;

procedure TPixieMargins.Init;
begin
  Left := 0;
  Right := 0;
  Top := 0;
  Bottom := 0;
end;

{ TPixiePointF }

class function TPixiePointF.Create(AX, AY: Single): TPixiePointF;
begin
  Result.X := AX;
  Result.Y := AY;
end;

{ TPixieSize }

class function TPixieSize.Create(AWidth, AHeight: TPixiePixel): TPixieSize;
begin
  Result.Width := AWidth;
  Result.Height := AHeight;
end;

{ TPixiePosition }

class function TPixiePosition.Create(AX, AY, AWidth, AHeight: TPixiePixel): TPixiePosition;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.Width := AWidth;
  Result.Height := AHeight;
end;

function TPixiePosition.Right: TPixiePixel;
begin
  Result := X + Width;
end;

function TPixiePosition.Bottom: TPixiePixel;
begin
  Result := Y + Height;
end;

function TPixiePosition.IsEmpty: Boolean;
begin
  Result := (Width = 0) and (Height = 0);
end;

function TPixiePosition.DoesIntersect(const Val: TPixiePosition): Boolean;
begin
  Result :=
    ((X <= Val.Right) and (Right >= Val.X) and (Bottom >= Val.Y) and (Y <= Val.Bottom)) or
    ((Val.X <= Right) and (Val.Right >= X) and (Val.Bottom >= Y) and (Val.Y <= Bottom));
end;

function TPixiePosition.Intersect(const Src: TPixiePosition): TPixiePosition;
var
  DestX, DestY, DestX2, DestY2: TPixiePixel;
begin
  DestX := Max(Src.X, X);
  DestY := Max(Src.Y, Y);
  DestX2 := Min(Src.Right, Right);
  DestY2 := Min(Src.Bottom, Bottom);

  if (DestX2 > DestX) and (DestY2 > DestY) then
  begin
    Result.X := DestX;
    Result.Y := DestY;
    Result.Width := DestX2 - DestX;
    Result.Height := DestY2 - DestY;
  end
  else
  begin
    Result.X := 0;
    Result.Y := 0;
    Result.Width := 0;
    Result.Height := 0;
  end;
end;

function TPixiePosition.IsPointInside(AX, AY: TPixiePixel): Boolean;
begin
  Result := (AX >= X) and (AX < Right) and (AY >= Y) and (AY < Bottom);
end;

procedure TPixiePosition.MoveTo(AX, AY: TPixiePixel);
begin
  X := AX;
  Y := AY;
end;

procedure TPixiePosition.Clear;
begin
  X := 0;
  Y := 0;
  Width := 0;
  Height := 0;
end;

procedure TPixiePosition.DoRound;
var
  R, B: TPixiePixel;
begin
  R := Round(X + Width);
  B := Round(Y + Height);
  X := Round(X);
  Y := Round(Y);
  Width := R - X;
  Height := B - Y;
end;

procedure TPixiePosition.AddMargins(const Mg: TPixieMargins);
begin
  X := X - Mg.Left;
  Y := Y - Mg.Top;
  Width := Width + Mg.Left + Mg.Right;
  Height := Height + Mg.Top + Mg.Bottom;
end;

procedure TPixiePosition.SubMargins(const Mg: TPixieMargins);
begin
  X := X + Mg.Left;
  Y := Y + Mg.Top;
  Width := Width - Mg.Left - Mg.Right;
  Height := Height - Mg.Top - Mg.Bottom;
end;

{ TPixieScrollValues }

procedure TPixieScrollValues.Init;
begin
  Dx := 0;
  Dy := 0;
  ScrollBox.Clear;
end;

{ TPixieFontMetrics }

function TPixieFontMetrics.BaseLine: TPixiePixel;
begin
  Result := Descent;
end;

procedure TPixieFontMetrics.CalcShifts;
begin
  SubShift := Ascent * 0.25;
  SuperShift := Ascent * 0.35;
end;

{ TPixieMediaFeatures }

procedure TPixieMediaFeatures.Init;
begin
  MediaType := mtUnknown;
  Width := 0;
  Height := 0;
  DeviceWidth := 0;
  DeviceHeight := 0;
  Color := 0;
  ColorIndex := 0;
  Monochrome := 0;
  Resolution := 0;
  // No-preference browsers resolve 'prefers-color-scheme' to light, so a
  // light-by-default stylesheet matches and dark-default themes show light.
  PrefersDark := False;
end;

{ TPixieTypedPixel }

class function TPixieTypedPixel.Create(AValue: TPixiePixel; AType: TPixieCbcValueType): TPixieTypedPixel;
begin
  Result.Value := AValue;
  Result.ValueType := AType;
end;

{ TPixieContainingBlockContext }

procedure TPixieContainingBlockContext.Init;
begin
  Width := TPixieTypedPixel.Create(0, cbcAuto);
  RenderWidth := TPixieTypedPixel.Create(0, cbcAuto);
  MinWidth := TPixieTypedPixel.Create(0, cbcNone);
  MaxWidth := TPixieTypedPixel.Create(0, cbcNone);
  Height := TPixieTypedPixel.Create(0, cbcAuto);
  MinHeight := TPixieTypedPixel.Create(0, cbcNone);
  MaxHeight := TPixieTypedPixel.Create(0, cbcNone);
  ContextIdx := 0;
  SizeMode := SizeModeNormal;
end;

function TPixieContainingBlockContext.NewWidth(W: TPixiePixel; ASizeMode: UInt32): TPixieContainingBlockContext;
begin
  Result := Self;
  Result.RenderWidth.Value := W - (Result.Width.Value - Result.RenderWidth.Value);
  Result.Width.Value := W;
  // SizeModeContent stays sticky down the tree so percentage padding
  // resolves to zero in intrinsic-sizing passes (CSS Sizing 3).
  Result.SizeMode := ASizeMode or (Self.SizeMode and SizeModeContent);
end;

function TPixieContainingBlockContext.NewWidthHeight(W, H: TPixiePixel; ASizeMode: UInt32): TPixieContainingBlockContext;
begin
  Result := Self;
  Result.RenderWidth.Value := W - (Result.Width.Value - Result.RenderWidth.Value);
  Result.Width.Value := W;
  Result.Height.Value := H;
  Result.SizeMode := ASizeMode or (Self.SizeMode and SizeModeContent);
end;

{ TPixiePixelPixelCache }

procedure TPixiePixelPixelCache.Init;
begin
  Hash := 0;
  Val := 0;
  IsValid := False;
  IsDefault := False;
end;

procedure TPixiePixelPixelCache.Invalidate;
begin
  IsValid := False;
  IsDefault := False;
end;

procedure TPixiePixelPixelCache.SetValue(AHash, AVal: TPixiePixel);
begin
  Hash := AHash;
  Val := AVal;
  IsValid := True;
end;

{ TPixieBaseline }

class function TPixieBaseline.Create(AValue: TPixiePixel; AType: TPixieBaselineType): TPixieBaseline;
begin
  Result.FValue := AValue;
  Result.FType := AType;
end;

procedure TPixieBaseline.Init;
begin
  FValue := 0;
  FType := btNone;
end;

procedure TPixieBaseline.SetValues(AValue: TPixiePixel; AType: TPixieBaselineType);
begin
  FValue := AValue;
  FType := AType;
end;

function TPixieBaseline.GetOffsetFromTop(AHeight: TPixiePixel): TPixiePixel;
begin
  if FType = btTop then
    Result := FValue
  else
    Result := AHeight - FValue;
end;

function TPixieBaseline.GetOffsetFromBottom(AHeight: TPixiePixel): TPixiePixel;
begin
  if FType = btBottom then
    Result := FValue
  else
    Result := AHeight - FValue;
end;

procedure TPixieBaseline.CalcFromPositions(ATop, ABottom: TPixiePixel);
begin
  if FType = btTop then
    FValue := -ATop
  else if FType = btBottom then
    FValue := ABottom;
end;

{ TPixieDefValue }

procedure TPixieDefValue.Init(DefVal: TPixiePixel);
begin
  FValue := DefVal;
  FIsDefault := True;
end;

procedure TPixieDefValue.Reset(DefVal: TPixiePixel);
begin
  FValue := DefVal;
  FIsDefault := True;
end;

function TPixieDefValue.IsDefault: Boolean;
begin
  Result := FIsDefault;
end;

procedure TPixieDefValue.SetValue(NewVal: TPixiePixel);
begin
  FValue := NewVal;
  FIsDefault := False;
end;

function TPixieDefValue.Value: TPixiePixel;
begin
  Result := FValue;
end;

procedure TPixieDefValue.ClampMax(var AValue: TPixiePixel);
begin
  if (not FIsDefault) and (AValue > FValue) then
    AValue := FValue;
end;

end.
