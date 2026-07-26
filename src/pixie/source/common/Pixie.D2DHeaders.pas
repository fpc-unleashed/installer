unit Pixie.D2DHeaders;

// Consolidated DirectX/Direct2D/DirectWrite/WIC declarations for Pixie.
// Only declarations needed by Pixie.Canvas.D2D.pas are included.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Windows, ActiveX;

// =========================================================================
// Section 1 -- Base type aliases
// =========================================================================

type
  FLOAT = Single;
  PFLOAT = ^FLOAT;
  PUINT16 = ^UINT16;
  TIID = TGUID;

  DXGI_FORMAT = type Integer;
  TDxgiFormat = DXGI_FORMAT;

  WICPixelFormatGUID = TGuid;
  REFWICPixelFormatGUID = PGuid;

// Forward + opaque interface declarations are in the main type block
// (Section 13) to satisfy FPC's requirement that forward declarations
// and full declarations are in the same type section.

// =========================================================================
// Section 3 -- Opaque types for DeviceContext chain
// =========================================================================

type
  // Enum types (not directly used by Pixie but needed for vtable signatures)
  TD2d1ColorSpace = type Integer;
  TD2d1BufferPrecision = type Integer;
  TD2d1InterpolationMode = type Integer;
  TD2d1CompositeMode = type Integer;
  TD2d1PrimitiveBlend = type Integer;
  TD2d1UnitMode = type Integer;
  TD2d1ColorInterpolationMode = type Integer;
  TD2d1ImageSourceLoadingOptions = type Integer;
  TD2d1ImageSourceFromDxgiOptions = type Integer;
  TD2d1SpriteOptions = type Integer;
  TD2d1ColorBitmapGlyphSnapOption = type Integer;
  TDwriteGlyphImageFormats = type Integer;
  TDxgiColorSpaceType = type Integer;
  TD2d1CompatibleRenderTargetOptions = type Integer;
  TD2d1OpacityMaskContent = type Integer;
  TD2d1LayerOptions = type Integer;
  TD2d1GeometryRelation = type Integer;
  TD2d1GeometrySimplificationOption = type Integer;
  TD2d1CombineMode = type Integer;
  TD2d1PathSegment = type Integer;
  TD2d1DebugLevel = type Integer;

  // Record pointer types (opaque -- Pixie never dereferences these)
  PD2d1BitmapProperties1 = Pointer;
  PD2d1RenderingControls = Pointer;
  PD2d1ImageBrushProperties = Pointer;
  PD2d1BitmapBrushProperties1 = Pointer;
  PD2d1LayerParameters1 = Pointer;
  PD2d1EffectInputDescription = Pointer;
  PD2d1InkPoint = Pointer;
  PD2d1InkStyleProperties = Pointer;
  PD2d1GradientMeshPatch = Pointer;
  PD2d1TransformedImageSourceProperties = Pointer;
  PD2d1SimpleColorProfile = Pointer;
  PD2d1Matrix4x4F = Pointer;
  PDwriteGlyphOffset = ^TDwriteGlyphOffset;
  TDwriteGlyphOffset = record
    advanceOffset: FLOAT;
    ascenderOffset: FLOAT;
  end;

  PDwriteGlyphRun = ^TDwriteGlyphRun;
  TDwriteGlyphRun = record
    fontFace: Pointer;       // IDWriteFontFace (raw pointer to avoid forward ref)
    fontEmSize: FLOAT;
    glyphCount: UINT32;
    glyphIndices: PUINT16;
    glyphAdvances: PSingle;
    glyphOffsets: PDwriteGlyphOffset;
    isSideways: BOOL;
    bidiLevel: UINT32;
  end;
  PDwriteGlyphRunDescription = Pointer;
  PDwriteMatrix = Pointer;

  // Constants used as default parameter values in DeviceContext methods
const
  D2D1_INTERPOLATION_MODE_LINEAR = 1;
  D2D1_COMPOSITE_MODE_SOURCE_OVER = 0;
  D2D1_COLOR_BITMAP_GLYPH_SNAP_OPTION_DEFAULT = 0;

// =========================================================================
// Section 4 -- DXGI_FORMAT constants
// =========================================================================

const
  DXGI_FORMAT_UNKNOWN = 0;
  DXGI_FORMAT_R32G32B32A32_TYPELESS = 1;
  DXGI_FORMAT_R32G32B32A32_FLOAT = 2;
  DXGI_FORMAT_R32G32B32A32_UINT = 3;
  DXGI_FORMAT_R32G32B32A32_SINT = 4;
  DXGI_FORMAT_R32G32B32_TYPELESS = 5;
  DXGI_FORMAT_R32G32B32_FLOAT = 6;
  DXGI_FORMAT_R32G32B32_UINT = 7;
  DXGI_FORMAT_R32G32B32_SINT = 8;
  DXGI_FORMAT_R16G16B16A16_TYPELESS = 9;
  DXGI_FORMAT_R16G16B16A16_FLOAT = 10;
  DXGI_FORMAT_R16G16B16A16_UNORM = 11;
  DXGI_FORMAT_R16G16B16A16_UINT = 12;
  DXGI_FORMAT_R16G16B16A16_SNORM = 13;
  DXGI_FORMAT_R16G16B16A16_SINT = 14;
  DXGI_FORMAT_R32G32_TYPELESS = 15;
  DXGI_FORMAT_R32G32_FLOAT = 16;
  DXGI_FORMAT_R32G32_UINT = 17;
  DXGI_FORMAT_R32G32_SINT = 18;
  DXGI_FORMAT_R32G8X24_TYPELESS = 19;
  DXGI_FORMAT_D32_FLOAT_S8X24_UINT = 20;
  DXGI_FORMAT_R32_FLOAT_X8X24_TYPELESS = 21;
  DXGI_FORMAT_X32_TYPELESS_G8X24_UINT = 22;
  DXGI_FORMAT_R10G10B10A2_TYPELESS = 23;
  DXGI_FORMAT_R10G10B10A2_UNORM = 24;
  DXGI_FORMAT_R10G10B10A2_UINT = 25;
  DXGI_FORMAT_R11G11B10_FLOAT = 26;
  DXGI_FORMAT_R8G8B8A8_TYPELESS = 27;
  DXGI_FORMAT_R8G8B8A8_UNORM = 28;
  DXGI_FORMAT_R8G8B8A8_UNORM_SRGB = 29;
  DXGI_FORMAT_R8G8B8A8_UINT = 30;
  DXGI_FORMAT_R8G8B8A8_SNORM = 31;
  DXGI_FORMAT_R8G8B8A8_SINT = 32;
  DXGI_FORMAT_R16G16_TYPELESS = 33;
  DXGI_FORMAT_R16G16_FLOAT = 34;
  DXGI_FORMAT_R16G16_UNORM = 35;
  DXGI_FORMAT_R16G16_UINT = 36;
  DXGI_FORMAT_R16G16_SNORM = 37;
  DXGI_FORMAT_R16G16_SINT = 38;
  DXGI_FORMAT_R32_TYPELESS = 39;
  DXGI_FORMAT_D32_FLOAT = 40;
  DXGI_FORMAT_R32_FLOAT = 41;
  DXGI_FORMAT_R32_UINT = 42;
  DXGI_FORMAT_R32_SINT = 43;
  DXGI_FORMAT_R24G8_TYPELESS = 44;
  DXGI_FORMAT_D24_UNORM_S8_UINT = 45;
  DXGI_FORMAT_R24_UNORM_X8_TYPELESS = 46;
  DXGI_FORMAT_X24_TYPELESS_G8_UINT = 47;
  DXGI_FORMAT_R8G8_TYPELESS = 48;
  DXGI_FORMAT_R8G8_UNORM = 49;
  DXGI_FORMAT_R8G8_UINT = 50;
  DXGI_FORMAT_R8G8_SNORM = 51;
  DXGI_FORMAT_R8G8_SINT = 52;
  DXGI_FORMAT_R16_TYPELESS = 53;
  DXGI_FORMAT_R16_FLOAT = 54;
  DXGI_FORMAT_D16_UNORM = 55;
  DXGI_FORMAT_R16_UNORM = 56;
  DXGI_FORMAT_R16_UINT = 57;
  DXGI_FORMAT_R16_SNORM = 58;
  DXGI_FORMAT_R16_SINT = 59;
  DXGI_FORMAT_R8_TYPELESS = 60;
  DXGI_FORMAT_R8_UNORM = 61;
  DXGI_FORMAT_R8_UINT = 62;
  DXGI_FORMAT_R8_SNORM = 63;
  DXGI_FORMAT_R8_SINT = 64;
  DXGI_FORMAT_A8_UNORM = 65;
  DXGI_FORMAT_R1_UNORM = 66;
  DXGI_FORMAT_R9G9B9E5_SHAREDEXP = 67;
  DXGI_FORMAT_R8G8_B8G8_UNORM = 68;
  DXGI_FORMAT_G8R8_G8B8_UNORM = 69;
  DXGI_FORMAT_BC1_TYPELESS = 70;
  DXGI_FORMAT_BC1_UNORM = 71;
  DXGI_FORMAT_BC1_UNORM_SRGB = 72;
  DXGI_FORMAT_BC2_TYPELESS = 73;
  DXGI_FORMAT_BC2_UNORM = 74;
  DXGI_FORMAT_BC2_UNORM_SRGB = 75;
  DXGI_FORMAT_BC3_TYPELESS = 76;
  DXGI_FORMAT_BC3_UNORM = 77;
  DXGI_FORMAT_BC3_UNORM_SRGB = 78;
  DXGI_FORMAT_BC4_TYPELESS = 79;
  DXGI_FORMAT_BC4_UNORM = 80;
  DXGI_FORMAT_BC4_SNORM = 81;
  DXGI_FORMAT_BC5_TYPELESS = 82;
  DXGI_FORMAT_BC5_UNORM = 83;
  DXGI_FORMAT_BC5_SNORM = 84;
  DXGI_FORMAT_B5G6R5_UNORM = 85;
  DXGI_FORMAT_B5G5R5A1_UNORM = 86;
  DXGI_FORMAT_B8G8R8A8_UNORM = 87;
  DXGI_FORMAT_B8G8R8X8_UNORM = 88;
  DXGI_FORMAT_R10G10B10_XR_BIAS_A2_UNORM = 89;
  DXGI_FORMAT_B8G8R8A8_TYPELESS = 90;
  DXGI_FORMAT_B8G8R8A8_UNORM_SRGB = 91;
  DXGI_FORMAT_B8G8R8X8_TYPELESS = 92;
  DXGI_FORMAT_B8G8R8X8_UNORM_SRGB = 93;
  DXGI_FORMAT_BC6H_TYPELESS = 94;
  DXGI_FORMAT_BC6H_UF16 = 95;
  DXGI_FORMAT_BC6H_SF16 = 96;
  DXGI_FORMAT_BC7_TYPELESS = 97;
  DXGI_FORMAT_BC7_UNORM = 98;
  DXGI_FORMAT_BC7_UNORM_SRGB = 99;
  DXGI_FORMAT_FORCE_UINT = $FFFFFFFF;

// =========================================================================
// Section 4b -- D2D error codes
// =========================================================================

const
  D2DERR_RECREATE_TARGET = HResult($8899000C);

// =========================================================================
// Section 5 -- D2D1 enum types + const blocks
// =========================================================================

type
  DWRITE_MEASURING_MODE = type Integer;
  TDwriteMeasuringMode = DWRITE_MEASURING_MODE;

const
  DWRITE_MEASURING_MODE_NATURAL = 0;
  DWRITE_MEASURING_MODE_GDI_CLASSIC = 1;
  DWRITE_MEASURING_MODE_GDI_NATURAL = 2;

type
  D2D1_ALPHA_MODE = type Integer;
  TD2d1AlphaMode = D2D1_ALPHA_MODE;

const
  D2D1_ALPHA_MODE_UNKNOWN = 0;
  D2D1_ALPHA_MODE_PREMULTIPLIED = 1;
  D2D1_ALPHA_MODE_STRAIGHT = 2;
  D2D1_ALPHA_MODE_IGNORE = 3;

type
  D2D1_GAMMA = type Integer;
  TD2d1Gamma = D2D1_GAMMA;

const
  D2D1_GAMMA_2_2 = 0;
  D2D1_GAMMA_1_0 = 1;

type
  D2D1_EXTEND_MODE = type Integer;
  TD2d1ExtendMode = D2D1_EXTEND_MODE;

const
  D2D1_EXTEND_MODE_CLAMP = 0;
  D2D1_EXTEND_MODE_WRAP = 1;
  D2D1_EXTEND_MODE_MIRROR = 2;

type
  D2D1_ANTIALIAS_MODE = type Integer;
  TD2d1AntialiasMode = D2D1_ANTIALIAS_MODE;

const
  D2D1_ANTIALIAS_MODE_PER_PRIMITIVE = 0;
  D2D1_ANTIALIAS_MODE_ALIASED = 1;

type
  D2D1_TEXT_ANTIALIAS_MODE = type Integer;
  TD2d1TextAntialiasMode = D2D1_TEXT_ANTIALIAS_MODE;

const
  D2D1_TEXT_ANTIALIAS_MODE_DEFAULT = 0;
  D2D1_TEXT_ANTIALIAS_MODE_CLEARTYPE = 1;
  D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE = 2;
  D2D1_TEXT_ANTIALIAS_MODE_ALIASED = 3;

type
  D2D1_BITMAP_INTERPOLATION_MODE = type Integer;
  TD2d1BitmapInterpolationMode = D2D1_BITMAP_INTERPOLATION_MODE;

const
  D2D1_BITMAP_INTERPOLATION_MODE_NEAREST_NEIGHBOR = 0;
  D2D1_BITMAP_INTERPOLATION_MODE_LINEAR = 1;

type
  D2D1_DRAW_TEXT_OPTIONS = type Integer;
  TD2d1DrawTextOptions = D2D1_DRAW_TEXT_OPTIONS;

const
  D2D1_DRAW_TEXT_OPTIONS_NONE = $00000000;
  D2D1_DRAW_TEXT_OPTIONS_NO_SNAP = $00000001;
  D2D1_DRAW_TEXT_OPTIONS_CLIP = $00000002;
  D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT = $00000003;

type
  D2D1_ARC_SIZE = type Integer;
  TD2d1ArcSize = D2D1_ARC_SIZE;

const
  D2D1_ARC_SIZE_SMALL = 0;
  D2D1_ARC_SIZE_LARGE = 1;

type
  D2D1_CAP_STYLE = type Integer;
  TD2d1CapStyle = D2D1_CAP_STYLE;

const
  D2D1_CAP_STYLE_FLAT = 0;
  D2D1_CAP_STYLE_SQUARE = 1;
  D2D1_CAP_STYLE_ROUND = 2;
  D2D1_CAP_STYLE_TRIANGLE = 3;

type
  D2D1_DASH_STYLE = type Integer;
  TD2d1DashStyle = D2D1_DASH_STYLE;

const
  D2D1_DASH_STYLE_SOLID = 0;
  D2D1_DASH_STYLE_DASH = 1;
  D2D1_DASH_STYLE_DOT = 2;
  D2D1_DASH_STYLE_DASH_DOT = 3;
  D2D1_DASH_STYLE_DASH_DOT_DOT = 4;
  D2D1_DASH_STYLE_CUSTOM = 5;

type
  D2D1_LINE_JOIN = type Integer;
  TD2d1LineJoin = D2D1_LINE_JOIN;

const
  D2D1_LINE_JOIN_MITER = 0;
  D2D1_LINE_JOIN_BEVEL = 1;
  D2D1_LINE_JOIN_ROUND = 2;
  D2D1_LINE_JOIN_MITER_OR_BEVEL = 3;

type
  D2D1_FIGURE_BEGIN = type Integer;
  TD2d1FigureBegin = D2D1_FIGURE_BEGIN;

const
  D2D1_FIGURE_BEGIN_FILLED = 0;
  D2D1_FIGURE_BEGIN_HOLLOW = 1;

type
  D2D1_FIGURE_END = type Integer;
  TD2d1FigureEnd = D2D1_FIGURE_END;

const
  D2D1_FIGURE_END_OPEN = 0;
  D2D1_FIGURE_END_CLOSED = 1;

type
  D2D1_SWEEP_DIRECTION = type Integer;
  TD2d1SweepDirection = D2D1_SWEEP_DIRECTION;

const
  D2D1_SWEEP_DIRECTION_COUNTER_CLOCKWISE = 0;
  D2D1_SWEEP_DIRECTION_CLOCKWISE = 1;

type
  D2D1_FILL_MODE = type Integer;
  TD2d1FillMode = D2D1_FILL_MODE;

const
  D2D1_FILL_MODE_ALTERNATE = 0;
  D2D1_FILL_MODE_WINDING = 1;

type
  D2D1_RENDER_TARGET_TYPE = type Integer;
  TD2d1RenderTargetType = D2D1_RENDER_TARGET_TYPE;

const
  D2D1_RENDER_TARGET_TYPE_DEFAULT = 0;
  D2D1_RENDER_TARGET_TYPE_SOFTWARE = 1;
  D2D1_RENDER_TARGET_TYPE_HARDWARE = 2;

type
  D2D1_FEATURE_LEVEL = type Integer;
  TD2d1FeatureLevel = D2D1_FEATURE_LEVEL;

const
  D2D1_FEATURE_LEVEL_DEFAULT = 0;
  D2D1_FEATURE_LEVEL_9 = $9100;
  D2D1_FEATURE_LEVEL_10 = $A000;

type
  D2D1_RENDER_TARGET_USAGE = type Integer;
  TD2d1RenderTargetUsage = D2D1_RENDER_TARGET_USAGE;

const
  D2D1_RENDER_TARGET_USAGE_NONE = $00000000;
  D2D1_RENDER_TARGET_USAGE_FORCE_BITMAP_REMOTING = $00000001;
  D2D1_RENDER_TARGET_USAGE_GDI_COMPATIBLE = $00000002;

type
  D2D1_FACTORY_TYPE = type Integer;
  TD2d1FactoryType = D2D1_FACTORY_TYPE;

const
  D2D1_FACTORY_TYPE_SINGLE_THREADED = 0;
  D2D1_FACTORY_TYPE_MULTI_THREADED = 1;

// =========================================================================
// Section 6 -- DWrite enum types + const blocks
// =========================================================================

type
  DWRITE_FONT_WEIGHT = type Integer;
  TDwriteFontWeight = DWRITE_FONT_WEIGHT;

const
  DWRITE_FONT_WEIGHT_THIN = 100;
  DWRITE_FONT_WEIGHT_EXTRA_LIGHT = 200;
  DWRITE_FONT_WEIGHT_ULTRA_LIGHT = 200;
  DWRITE_FONT_WEIGHT_LIGHT = 300;
  DWRITE_FONT_WEIGHT_SEMI_LIGHT = 350;
  DWRITE_FONT_WEIGHT_NORMAL = 400;
  DWRITE_FONT_WEIGHT_REGULAR = 400;
  DWRITE_FONT_WEIGHT_MEDIUM = 500;
  DWRITE_FONT_WEIGHT_DEMI_BOLD = 600;
  DWRITE_FONT_WEIGHT_SEMI_BOLD = 600;
  DWRITE_FONT_WEIGHT_BOLD = 700;
  DWRITE_FONT_WEIGHT_EXTRA_BOLD = 800;
  DWRITE_FONT_WEIGHT_ULTRA_BOLD = 800;
  DWRITE_FONT_WEIGHT_BLACK = 900;
  DWRITE_FONT_WEIGHT_HEAVY = 900;
  DWRITE_FONT_WEIGHT_EXTRA_BLACK = 950;
  DWRITE_FONT_WEIGHT_ULTRA_BLACK = 950;

type
  DWRITE_FONT_STRETCH = type Integer;
  TDwriteFontStretch = DWRITE_FONT_STRETCH;

const
  DWRITE_FONT_STRETCH_UNDEFINED = 0;
  DWRITE_FONT_STRETCH_ULTRA_CONDENSED = 1;
  DWRITE_FONT_STRETCH_EXTRA_CONDENSED = 2;
  DWRITE_FONT_STRETCH_CONDENSED = 3;
  DWRITE_FONT_STRETCH_SEMI_CONDENSED = 4;
  DWRITE_FONT_STRETCH_NORMAL = 5;
  DWRITE_FONT_STRETCH_MEDIUM = 5;
  DWRITE_FONT_STRETCH_SEMI_EXPANDED = 6;
  DWRITE_FONT_STRETCH_EXPANDED = 7;
  DWRITE_FONT_STRETCH_EXTRA_EXPANDED = 8;
  DWRITE_FONT_STRETCH_ULTRA_EXPANDED = 9;

type
  DWRITE_FONT_STYLE = type Integer;
  TDwriteFontStyle = DWRITE_FONT_STYLE;

const
  DWRITE_FONT_STYLE_NORMAL = 0;
  DWRITE_FONT_STYLE_OBLIQUE = 1;
  DWRITE_FONT_STYLE_ITALIC = 2;

type
  DWRITE_WORD_WRAPPING = type Integer;
  TDwriteWordWrapping = DWRITE_WORD_WRAPPING;

const
  DWRITE_WORD_WRAPPING_WRAP = 0;
  DWRITE_WORD_WRAPPING_NO_WRAP = 1;
  DWRITE_WORD_WRAPPING_EMERGENCY_BREAK = 2;
  DWRITE_WORD_WRAPPING_WHOLE_WORD = 3;
  DWRITE_WORD_WRAPPING_CHARACTER = 4;

type
  DWRITE_FACTORY_TYPE = type Integer;
  TDwriteFactoryType = DWRITE_FACTORY_TYPE;

const
  DWRITE_FACTORY_TYPE_SHARED = 0;
  DWRITE_FACTORY_TYPE_ISOLATED = 1;

// =========================================================================
// Section 7 -- WIC enum types + const blocks
// =========================================================================

type
  WICDecodeOptions = type Integer;
  TWicdecodeoptions = WICDecodeOptions;

  WICBitmapCreateCacheOption = type Integer;
  TWicbitmapcreatecacheoption = WICBitmapCreateCacheOption;

  WICBitmapAlphaChannelOption = type Integer;
  TWicbitmapalphachanneloption = WICBitmapAlphaChannelOption;

  WICBitmapDitherType = type Integer;
  TWicbitmapdithertype = WICBitmapDitherType;

const
  WICBitmapDitherTypeNone = $0;
  WICBitmapDitherTypeSolid = $0;
  WICBitmapDitherTypeOrdered4x4 = $1;
  WICBitmapDitherTypeOrdered8x8 = $2;
  WICBitmapDitherTypeOrdered16x16 = $3;
  WICBitmapDitherTypeSpiral4x4 = $4;
  WICBitmapDitherTypeSpiral8x8 = $5;
  WICBitmapDitherTypeDualSpiral4x4 = $6;
  WICBitmapDitherTypeDualSpiral8x8 = $7;
  WICBitmapDitherTypeErrorDiffusion = $8;

  WICBitmapCacheOnDemand = 0;
  WICBitmapCacheOnLoad = 1;
  WICBitmapNoCache = 2;

  WICBitmapLockRead  = $01;
  WICBitmapLockWrite = $02;

type
  WICBitmapPaletteType = type Integer;
  TWicbitmappalettetype = WICBitmapPaletteType;

const
  WICBitmapPaletteTypeCustom = $0;
  WICBitmapPaletteTypeMedianCut = $1;
  WICBitmapPaletteTypeFixedBW = $2;
  WICBitmapPaletteTypeFixedHalftone8 = $3;
  WICBitmapPaletteTypeFixedHalftone27 = $4;
  WICBitmapPaletteTypeFixedHalftone64 = $5;
  WICBitmapPaletteTypeFixedHalftone125 = $6;
  WICBitmapPaletteTypeFixedHalftone216 = $7;
  WICBitmapPaletteTypeFixedWebPalette = WICBitmapPaletteTypeFixedHalftone216;
  WICBitmapPaletteTypeFixedHalftone252 = $8;
  WICBitmapPaletteTypeFixedHalftone256 = $9;
  WICBitmapPaletteTypeFixedGray4 = $A;
  WICBitmapPaletteTypeFixedGray16 = $B;
  WICBitmapPaletteTypeFixedGray256 = $C;

// =========================================================================
// Section 8 -- Geometric records (from DCommon)
// =========================================================================

type
  D2D_POINT_2F = record
    x: FLOAT;
    y: FLOAT;
  end;
  TD2dPoint2f = D2D_POINT_2F;

  D2D_POINT_2U = record
    x: UINT32;
    y: UINT32;
  end;
  TD2dPoint2u = D2D_POINT_2U;

  D2D_RECT_F = record
    left: FLOAT;
    top: FLOAT;
    right: FLOAT;
    bottom: FLOAT;
  end;
  TD2dRectF = D2D_RECT_F;

  D2D_RECT_U = record
    left: UINT32;
    top: UINT32;
    right: UINT32;
    bottom: UINT32;
  end;
  TD2dRectU = D2D_RECT_U;

  D2D_SIZE_F = record
    width: FLOAT;
    height: FLOAT;
  end;
  TD2dSizeF = D2D_SIZE_F;

  D2D_SIZE_U = record
    width: UINT32;
    height: UINT32;
  end;
  TD2dSizeU = D2D_SIZE_U;

  D2D_MATRIX_3X2_F = record
  case Byte of
    0: (m11, m12, m21, m22, dx, dy: FLOAT);
    1: (_11, _12, _21, _22, _31, _32: FLOAT);
    2: (m: array[0..2, 0..1] of FLOAT);
  end;
  TD2dMatrix3x2F = D2D_MATRIX_3X2_F;

  // D2D1 aliases
  D2D1_POINT_2F = TD2dPoint2f;
  TD2d1Point2f = D2D1_POINT_2F;
  PD2d1Point2f = ^TD2d1Point2f;

  D2D1_POINT_2U = TD2dPoint2u;
  TD2d1Point2u = D2D1_POINT_2U;

  D2D1_RECT_F = TD2dRectF;
  TD2d1RectF = D2D1_RECT_F;
  PD2d1RectF = ^TD2d1RectF;

  D2D1_RECT_U = TD2dRectU;
  TD2d1RectU = D2D1_RECT_U;

  D2D1_SIZE_F = TD2dSizeF;
  TD2d1SizeF = D2D1_SIZE_F;
  PD2d1SizeF = ^TD2d1SizeF;

  D2D1_SIZE_U = TD2dSizeU;
  TD2d1SizeU = D2D1_SIZE_U;
  PD2d1SizeU = ^TD2d1SizeU;

  D2D1_MATRIX_3X2_F = TD2dMatrix3x2F;
  TD2d1Matrix3x2F = D2D1_MATRIX_3X2_F;
  PD2d1Matrix3x2F = ^TD2d1Matrix3x2F;

// =========================================================================
// Section 9 -- D2D1 records
// =========================================================================

type
  D2D1_PIXEL_FORMAT = record
    format: TDxgiFormat;
    alphaMode: TD2d1AlphaMode;
  end;
  TD2d1PixelFormat = D2D1_PIXEL_FORMAT;
  PD2d1PixelFormat = ^TD2d1PixelFormat;

  D2D1_COLOR_F = record
    r: FLOAT;
    g: FLOAT;
    b: FLOAT;
    a: FLOAT;
  end;
  TD2d1ColorF = D2D1_COLOR_F;
  PD2d1ColorF = ^TD2d1ColorF;

  // Alias used by D2D
  D2D_COLOR_F = D2D1_COLOR_F;
  TD2D1Tag = UINT64;
  PD2D1Tag = ^TD2D1Tag;

  D2D1_BITMAP_PROPERTIES = record
    pixelFormat: TD2d1PixelFormat;
    dpiX: FLOAT;
    dpiY: FLOAT;
  end;
  TD2d1BitmapProperties = D2D1_BITMAP_PROPERTIES;
  PD2d1BitmapProperties = ^TD2d1BitmapProperties;

  D2D1_GRADIENT_STOP = record
    position: FLOAT;
    color: TD2d1ColorF;
  end;
  TD2d1GradientStop = D2D1_GRADIENT_STOP;
  PD2d1GradientStop = ^TD2d1GradientStop;

  D2D1_BRUSH_PROPERTIES = record
    opacity: FLOAT;
    transform: TD2d1Matrix3x2F;
  end;
  TD2d1BrushProperties = D2D1_BRUSH_PROPERTIES;
  PD2d1BrushProperties = ^TD2d1BrushProperties;

  D2D1_BITMAP_BRUSH_PROPERTIES = record
    extendModeX: TD2d1ExtendMode;
    extendModeY: TD2d1ExtendMode;
    interpolationMode: TD2d1BitmapInterpolationMode;
  end;
  TD2d1BitmapBrushProperties = D2D1_BITMAP_BRUSH_PROPERTIES;
  PD2d1BitmapBrushProperties = ^TD2d1BitmapBrushProperties;

  D2D1_LINEAR_GRADIENT_BRUSH_PROPERTIES = record
    startPoint: TD2d1Point2f;
    endPoint: TD2d1Point2f;
  end;
  TD2d1LinearGradientBrushProperties = D2D1_LINEAR_GRADIENT_BRUSH_PROPERTIES;
  PD2d1LinearGradientBrushProperties = ^TD2d1LinearGradientBrushProperties;

  D2D1_RADIAL_GRADIENT_BRUSH_PROPERTIES = record
    center: TD2d1Point2f;
    gradientOriginOffset: TD2d1Point2f;
    radiusX: FLOAT;
    radiusY: FLOAT;
  end;
  TD2d1RadialGradientBrushProperties = D2D1_RADIAL_GRADIENT_BRUSH_PROPERTIES;
  PD2d1RadialGradientBrushProperties = ^TD2d1RadialGradientBrushProperties;

  D2D1_ARC_SEGMENT = record
    point: TD2d1Point2f;
    size: TD2d1SizeF;
    rotationAngle: FLOAT;
    sweepDirection: TD2d1SweepDirection;
    arcSize: TD2d1ArcSize;
  end;
  TD2d1ArcSegment = D2D1_ARC_SEGMENT;
  PD2d1ArcSegment = ^TD2d1ArcSegment;

  D2D1_BEZIER_SEGMENT = record
    point1: TD2d1Point2f;
    point2: TD2d1Point2f;
    point3: TD2d1Point2f;
  end;
  TD2d1BezierSegment = D2D1_BEZIER_SEGMENT;
  PD2d1BezierSegment = ^TD2d1BezierSegment;

  D2D1_QUADRATIC_BEZIER_SEGMENT = record
    point1: TD2d1Point2f;
    point2: TD2d1Point2f;
  end;
  TD2d1QuadraticBezierSegment = D2D1_QUADRATIC_BEZIER_SEGMENT;
  PD2d1QuadraticBezierSegment = ^TD2d1QuadraticBezierSegment;

  D2D1_ELLIPSE = record
    point: TD2d1Point2f;
    radiusX: FLOAT;
    radiusY: FLOAT;
  end;
  TD2d1Ellipse = D2D1_ELLIPSE;
  PD2d1Ellipse = ^TD2d1Ellipse;

  D2D1_ROUNDED_RECT = record
    rect: TD2d1RectF;
    radiusX: FLOAT;
    radiusY: FLOAT;
  end;
  TD2d1RoundedRect = D2D1_ROUNDED_RECT;
  PD2d1RoundedRect = ^TD2d1RoundedRect;

  D2D1_STROKE_STYLE_PROPERTIES = record
    startCap: TD2d1CapStyle;
    endCap: TD2d1CapStyle;
    dashCap: TD2d1CapStyle;
    lineJoin: TD2d1LineJoin;
    miterLimit: FLOAT;
    dashStyle: TD2d1DashStyle;
    dashOffset: FLOAT;
  end;
  TD2d1StrokeStyleProperties = D2D1_STROKE_STYLE_PROPERTIES;
  PD2d1StrokeStyleProperties = ^TD2d1StrokeStyleProperties;

  D2D1_RENDER_TARGET_PROPERTIES = record
    _type: TD2d1RenderTargetType;
    pixelFormat: TD2d1PixelFormat;
    dpiX: FLOAT;
    dpiY: FLOAT;
    usage: TD2d1RenderTargetUsage;
    minLevel: TD2d1FeatureLevel;
  end;
  TD2d1RenderTargetProperties = D2D1_RENDER_TARGET_PROPERTIES;
  PD2d1RenderTargetProperties = ^TD2d1RenderTargetProperties;

  D2D1_LAYER_PARAMETERS = record
    contentBounds: TD2d1RectF;
    geometricMask: Pointer;
    maskAntialiasMode: TD2d1AntialiasMode;
    maskTransform: TD2d1Matrix3x2F;
    opacity: FLOAT;
    opacityBrush: Pointer;
    layerOptions: TD2d1LayerOptions;
  end;
  TD2d1LayerParameters = D2D1_LAYER_PARAMETERS;
  PD2d1LayerParameters = ^TD2d1LayerParameters;

  D2D1_FACTORY_OPTIONS = record
    debugLevel: TD2d1DebugLevel;
  end;
  TD2d1FactoryOptions = D2D1_FACTORY_OPTIONS;
  PD2d1FactoryOptions = ^TD2d1FactoryOptions;

  D2D1_HWND_RENDER_TARGET_PROPERTIES = record
    hwnd: HWND;
    pixelSize: TD2d1SizeU;
    presentOptions: Integer;
  end;
  TD2d1HwndRenderTargetProperties = D2D1_HWND_RENDER_TARGET_PROPERTIES;

  D2D1_DRAWING_STATE_DESCRIPTION = record
    antialiasMode: TD2d1AntialiasMode;
    textAntialiasMode: TD2d1TextAntialiasMode;
    tag1: TD2D1Tag;
    tag2: TD2D1Tag;
    transform: TD2d1Matrix3x2F;
  end;
  TD2d1DrawingStateDescription = D2D1_DRAWING_STATE_DESCRIPTION;

// =========================================================================
// Section 10 -- DWrite records
// =========================================================================

type
  DWRITE_FONT_METRICS = record
    designUnitsPerEm: UINT16;
    ascent: UINT16;
    descent: UINT16;
    lineGap: INT16;
    capHeight: UINT16;
    xHeight: UINT16;
    underlinePosition: INT16;
    underlineThickness: UINT16;
    strikethroughPosition: INT16;
    strikethroughThickness: UINT16;
  end;
  TDwriteFontMetrics = DWRITE_FONT_METRICS;
  PDwriteFontMetrics = ^TDwriteFontMetrics;

  DWRITE_TEXT_RANGE = record
    startPosition: UINT32;
    length: UINT32;
  end;
  TDwriteTextRange = DWRITE_TEXT_RANGE;
  PDwriteTextRange = ^TDwriteTextRange;

  DWRITE_TEXT_METRICS = record
    left: FLOAT;
    top: FLOAT;
    width: FLOAT;
    widthIncludingTrailingWhitespace: FLOAT;
    height: FLOAT;
    layoutWidth: FLOAT;
    layoutHeight: FLOAT;
    maxBidiReorderingDepth: UINT32;
    lineCount: UINT32;
  end;
  TDwriteTextMetrics = DWRITE_TEXT_METRICS;

  // Opaque DWrite types (used only in vtable methods Pixie doesn't call)
  TDwriteFontFaceType = type Integer;
  TDwriteFontSimulations = type Integer;
  TDwritePixelGeometry = type Integer;
  TDwriteRenderingMode = type Integer;
  TDwriteInformationalStringId = type Integer;
  TDwriteNumberSubstitutionMethod = type Integer;
  TDwriteTextAlignment = type Integer;
  TDwriteParagraphAlignment = type Integer;
  TDwriteReadingDirection = type Integer;
  TDwriteFlowDirection = type Integer;
  TDwriteLineSpacingMethod = type Integer;

  TDwriteTrimming = record
    granularity: Integer;
    delimiter: UINT32;
    delimiterCount: UINT32;
  end;
  TDwriteLineMetrics = record _pad: array[0..23] of Byte; end;
  TDwriteOverhangMetrics = record _pad: array[0..15] of Byte; end;
  TDwriteClusterMetrics = record _pad: array[0..7] of Byte; end;
  TDwriteHitTestMetrics = record _pad: array[0..35] of Byte; end;

// =========================================================================
// Section 11 -- WIC records
// =========================================================================

type
  WICRect = record
    X: Integer;
    Y: Integer;
    Width: Integer;
    Height: Integer;
  end;
  TWicrect = WICRect;
  PWicrect = ^TWicrect;

// =========================================================================
// Section 12 -- All interface declarations (single type block)
// =========================================================================

type
  // Forward declarations (full bodies follow below)
  ID2D1Factory = interface;
  ID2D1Resource = interface;
  ID2D1Image = interface;
  ID2D1Bitmap = interface;
  ID2D1GradientStopCollection = interface;
  ID2D1Brush = interface;
  ID2D1SolidColorBrush = interface;
  ID2D1LinearGradientBrush = interface;
  ID2D1RadialGradientBrush = interface;
  ID2D1StrokeStyle = interface;
  ID2D1Geometry = interface;
  ID2D1SimplifiedGeometrySink = interface;
  ID2D1GeometrySink = interface;
  ID2D1PathGeometry = interface;
  ID2D1RenderTarget = interface;
  ID2D1DCRenderTarget = interface;
  IDWriteFontCollection = interface;
  IDWriteFontList = interface;
  IDWriteFontFamily = interface;
  IDWriteFont = interface;
  IDWriteTextFormat = interface;
  IDWriteTextLayout = interface;
  IDWriteFactory = interface;
  IWICBitmapSource = interface;
  IWICBitmapFrameDecode = interface;
  IWICBitmapDecoder = interface;
  IWICFormatConverter = interface;
  IWICImagingFactory = interface;
  IWICBitmap = interface;
  ID2D1DeviceContext = interface;
  ID2D1DeviceContext1 = interface;
  ID2D1DeviceContext2 = interface;
  ID2D1DeviceContext3 = interface;
  ID2D1DeviceContext4 = interface;

  // Opaque D2D1 interfaces (used only as parameter types)
  ID2D1BitmapBrush = interface;
  ID2D1BitmapRenderTarget = interface end;
  ID2D1Layer = interface end;
  ID2D1Mesh = interface end;
  ID2D1DrawingStateBlock = interface end;
  ID2D1RectangleGeometry = interface end;
  ID2D1RoundedRectangleGeometry = interface end;
  ID2D1EllipseGeometry = interface end;
  ID2D1GeometryGroup = interface end;
  ID2D1TransformedGeometry = interface end;
  ID2D1HwndRenderTarget = interface end;
  ID2D1TessellationSink = interface end;

  // Opaque D2D1_1/2/3 interfaces
  ID2D1Bitmap1 = interface end;
  ID2D1ColorContext = interface end;
  ID2D1ColorContext1 = interface end;
  ID2D1Effect = interface end;
  ID2D1GradientStopCollection1 = interface end;
  ID2D1ImageBrush = interface end;
  ID2D1BitmapBrush1 = interface end;
  ID2D1CommandList = interface end;
  ID2D1GdiMetafile = interface end;
  ID2D1Device = interface end;
  ID2D1GeometryRealization = interface end;
  ID2D1Ink = interface end;
  ID2D1InkStyle = interface end;
  ID2D1GradientMesh = interface end;
  ID2D1ImageSource = interface end;
  ID2D1ImageSourceFromWic = interface end;
  ID2D1TransformedImageSource = interface end;
  ID2D1LookupTable3D = interface end;
  ID2D1SpriteBatch = interface end;
  ID2D1SvgGlyphStyle = interface end;

  // IDWriteFontFace — expanded for GetGlyphRunOutline (text stroke support)
  IDWriteFontFace = interface(IUnknown)
  ['{5f49804d-7024-4d43-bfa9-d25984f53849}']
    function GetType: Integer; stdcall;
    function GetFiles(var numberOfFiles: UINT32;
      fontFiles: Pointer): HResult; stdcall;
    function GetIndex: UINT32; stdcall;
    function GetSimulations: Integer; stdcall;
    function IsSymbolFont: BOOL; stdcall;
    procedure GetMetrics(metrics: Pointer); stdcall;
    function GetGlyphCount: UINT16; stdcall;
    function GetDesignGlyphMetrics(glyphIndices: PUINT16;
      glyphCount: UINT32; glyphMetrics: Pointer;
      isSideways: BOOL): HResult; stdcall;
    function GetGlyphIndices(codePoints: PUINT32;
      codePointCount: UINT32;
      glyphIndices: PUINT16): HResult; stdcall;
    function TryGetFontTable(openTypeTableTag: UINT32;
      out tableData: Pointer; out tableSize: UINT32;
      out tableContext: Pointer; out exists: BOOL): HResult; stdcall;
    procedure ReleaseFontTable(tableContext: Pointer); stdcall;
    function GetGlyphRunOutline(emSize: FLOAT;
      glyphIndices: PUINT16; glyphAdvances: PSingle;
      glyphOffsets: Pointer; glyphCount: UINT32;
      isSideways: BOOL; isRightToLeft: BOOL;
      geometrySink: ID2D1SimplifiedGeometrySink): HResult; stdcall;
    function GetRecommendedRenderingMode(emSize: FLOAT;
      pixelsPerDip: FLOAT; measuringMode: TDwriteMeasuringMode;
      renderingParams: IUnknown;
      out renderingMode: Integer): HResult; stdcall;
    function GetGdiCompatibleMetrics(emSize: FLOAT;
      pixelsPerDip: FLOAT; transform: Pointer;
      metrics: Pointer): HResult; stdcall;
    function GetGdiCompatibleGlyphMetrics(emSize: FLOAT;
      pixelsPerDip: FLOAT; transform: Pointer;
      useGdiNatural: BOOL; glyphIndices: PUINT16;
      glyphCount: UINT32; glyphMetrics: Pointer;
      isSideways: BOOL): HResult; stdcall;
  end;
  IDWriteLocalizedStrings = interface end;
  IDWriteFontCollectionLoader = interface end;
  IDWriteFontFileLoader = interface end;
  IDWriteFontFile = interface end;
  IDWriteRenderingParams = interface end;
  IDWriteInlineObject = interface end;
  IDWriteTypography = interface end;
  IDWriteTextRenderer = interface end;
  IDWriteTextAnalyzer = interface end;
  IDWriteNumberSubstitution = interface end;
  IDWriteGlyphRunAnalysis = interface end;
  IDWriteGdiInterop = interface end;

  // Opaque WIC interfaces
  IWICPalette = interface end;
  IWICColorContext = interface end;
  IWICBitmapDecoderInfo = interface end;
  IWICMetadataQueryReader = interface end;
  IWICMetadataQueryWriter = interface end;
  IWICComponentInfo = interface end;
  IWICBitmapScaler = interface end;
  IWICBitmapClipper = interface end;
  IWICBitmapFlipRotator = interface end;
  IWICColorTransform = interface end;
  IWICBitmapEncoder = interface end;
  IWICFastMetadataEncoder = interface end;
  IWICBitmapLock = interface(IUnknown)
  ['{00000123-a8f2-4877-ba0a-fd2b6645fb94}']
    function GetSize(out puiWidth: UINT; out puiHeight: UINT): HResult; stdcall;
    function GetStride(out pcbStride: UINT): HResult; stdcall;
    function GetDataPointer(out pcbBufferSize: UINT; out ppbData: PByte): HResult; stdcall;
    function GetPixelFormat(out pPixelFormat: WICPixelFormatGUID): HResult; stdcall;
  end;
  IWICStream = interface end;
  IWICBitmapFrameEncode = interface end;

  // Opaque DXGI interfaces
  IDXGISurface = interface end;


  // --- Full interface declarations follow ---

  ID2D1Resource = interface(IUnknown)
  ['{2cd90691-12e2-11dc-9fed-001143a055f9}']
    procedure GetFactory(out factory: ID2D1Factory); stdcall;
  end;

  ID2D1Image = interface(ID2D1Resource)
  ['{65019f75-8da2-497c-b32c-dfa34e48ede6}']
  end;

  ID2D1Bitmap = interface(ID2D1Image)
  ['{a2296057-ea42-4099-983b-539fb6505426}']
    procedure GetSize(out size: TD2d1SizeF); stdcall;
    procedure GetPixelSize(out pixelSize: TD2d1SizeU); stdcall;
    procedure GetPixelFormat(out pixelFormat: TD2d1PixelFormat); stdcall;
    procedure GetDpi(out dpiX: FLOAT; out dpiY: FLOAT); stdcall;
    function CopyFromBitmap(const destPoint: TD2d1Point2u;
      bitmap: ID2D1Bitmap; const srcRect: TD2d1RectU): HResult; stdcall;
    function CopyFromRenderTarget(const destPoint: TD2d1Point2u;
      renderTarget: ID2D1RenderTarget; const srcRect: TD2d1RectU): HResult; stdcall;
    function CopyFromMemory(const dstRect: TD2d1RectU;
      srcData: Pointer; pitch: UINT32): HResult; stdcall;
  end;

  ID2D1GradientStopCollection = interface(ID2D1Resource)
  ['{2cd906a7-12e2-11dc-9fed-001143a055f9}']
    function GetGradientStopCount: UINT32; stdcall;
    procedure GetGradientStops(var gradientStops: TD2d1GradientStop;
      gradientStopsCount: UINT); stdcall;
    function GetColorInterpolationGamma: TD2d1Gamma; stdcall;
    function GetExtendMode: TD2d1ExtendMode; stdcall;
  end;

  ID2D1Brush = interface(ID2D1Resource)
  ['{2cd906a8-12e2-11dc-9fed-001143a055f9}']
    procedure SetOpacity(opacity: FLOAT); stdcall;
    procedure SetTransform(const transform: TD2d1Matrix3x2F); stdcall;
    function GetOpacity: FLOAT; stdcall;
    procedure GetTransform(out transform: TD2d1Matrix3x2F); stdcall;
  end;

  ID2D1SolidColorBrush = interface(ID2D1Brush)
  ['{2cd906a9-12e2-11dc-9fed-001143a055f9}']
    procedure SetColor(const color: TD2d1ColorF); stdcall;
    function GetColor: TD2d1ColorF; stdcall;
  end;

  ID2D1LinearGradientBrush = interface(ID2D1Brush)
  ['{2cd906ab-12e2-11dc-9fed-001143a055f9}']
    procedure SetStartPoint(startPoint: TD2d1Point2f); stdcall;
    procedure SetEndPoint(endPoint: TD2d1Point2f); stdcall;
    function GetStartPoint: TD2d1Point2f; stdcall;
    function GetEndPoint: TD2d1Point2f; stdcall;
    procedure GetGradientStopCollection(
      out gradientStopCollection: ID2D1GradientStopCollection); stdcall;
  end;

  ID2D1RadialGradientBrush = interface(ID2D1Brush)
  ['{2cd906ac-12e2-11dc-9fed-001143a055f9}']
    procedure SetCenter(center: TD2d1Point2f); stdcall;
    procedure SetGradientOriginOffset(gradientOriginOffset: TD2d1Point2f); stdcall;
    procedure SetRadiusX(radiusX: FLOAT); stdcall;
    procedure SetRadiusY(radiusY: FLOAT); stdcall;
    function GetCenter: TD2d1Point2f; stdcall;
    function GetGradientOriginOffset: TD2d1Point2f; stdcall;
    function GetRadiusX: FLOAT; stdcall;
    function GetRadiusY: FLOAT; stdcall;
    procedure GetGradientStopCollection(
      out gradientStopCollection: ID2D1GradientStopCollection); stdcall;
  end;

  ID2D1BitmapBrush = interface(ID2D1Brush)
  ['{2cd906aa-12e2-11dc-9fed-001143a055f9}']
  end;

  ID2D1StrokeStyle = interface(ID2D1Resource)
  ['{2cd9069d-12e2-11dc-9fed-001143a055f9}']
    function GetStartCap: TD2d1CapStyle; stdcall;
    function GetEndCap: TD2d1CapStyle; stdcall;
    function GetDashCap: TD2d1CapStyle; stdcall;
    function GetMiterLimit: FLOAT; stdcall;
    function GetLineJoin: TD2d1LineJoin; stdcall;
    function GetDashOffset: FLOAT; stdcall;
    function GetDashStyle: TD2d1DashStyle; stdcall;
    function GetDashesCount: UINT32; stdcall;
    procedure GetDashes(var dashes: FLOAT; dashesCount: UINT); stdcall;
  end;

  ID2D1Geometry = interface(ID2D1Resource)
  ['{2cd906a1-12e2-11dc-9fed-001143a055f9}']
    function GetBounds(const worldTransform: TD2d1Matrix3x2F;
      out bounds: TD2d1RectF): HResult; stdcall;
    function GetWidenedBounds(strokeWidth: FLOAT; strokeStyle: ID2D1StrokeStyle;
      const worldTransform: TD2d1Matrix3x2F; flatteningTolerance: FLOAT;
      out bounds: TD2d1RectF): HResult; stdcall;
    function StrokeContainsPoint(point: TD2d1Point2f; strokeWidth: FLOAT;
      strokeStyle: ID2D1StrokeStyle; const worldTransform: TD2d1Matrix3x2F;
      flatteningTolerance: FLOAT; out contains: BOOL): HResult; stdcall;
    function FillContainsPoint(point: TD2d1Point2f;
      const worldTransform: TD2d1Matrix3x2F; flatteningTolerance: FLOAT;
      out contains: BOOL): HResult; stdcall;
    function CompareWithGeometry(inputGeometry: ID2D1Geometry;
      const inputGeometryTransform: TD2d1Matrix3x2F; flatteningTolerance: FLOAT;
      out relation: TD2d1GeometryRelation): HResult; stdcall;
    function Simplify(simplificationOption: TD2d1GeometrySimplificationOption;
      const worldTransform: TD2d1Matrix3x2F; flatteningTolerance: FLOAT;
      geometrySink: ID2D1SimplifiedGeometrySink): HResult; stdcall;
    function Tessellate(const worldTransform: TD2d1Matrix3x2F;
      flatteningTolerance: FLOAT;
      tessellationSink: ID2D1TessellationSink): HResult; stdcall;
    function CombineWithGeometry(inputGeometry: ID2D1Geometry;
      combineMode: TD2d1CombineMode;
      const inputGeometryTransform: TD2d1Matrix3x2F; flatteningTolerance: FLOAT;
      geometrySink: ID2D1SimplifiedGeometrySink): HResult; stdcall;
    function Outline(const worldTransform: TD2d1Matrix3x2F;
      flatteningTolerance: FLOAT;
      geometrySink: ID2D1SimplifiedGeometrySink): HResult; stdcall;
    function ComputeArea(const worldTransform: TD2d1Matrix3x2F;
      flatteningTolerance: FLOAT; out area: FLOAT): HResult; stdcall;
    function ComputeLength(const worldTransform: TD2d1Matrix3x2F;
      flatteningTolerance: FLOAT; out length: FLOAT): HResult; stdcall;
    function ComputePointAtLength(length: FLOAT;
      const worldTransform: TD2d1Matrix3x2F; flatteningTolerance: FLOAT;
      out point: TD2d1Point2f;
      out unitTangentVector: TD2d1Point2f): HResult; stdcall;
    function Widen(strokeWidth: FLOAT; strokeStyle: ID2D1StrokeStyle;
      const worldTransform: TD2d1Matrix3x2F; flatteningTolerance: FLOAT;
      geometrySink: ID2D1SimplifiedGeometrySink): HResult; stdcall;
  end;

  ID2D1SimplifiedGeometrySink = interface(IUnknown)
  ['{2cd9069e-12e2-11dc-9fed-001143a055f9}']
    procedure SetFillMode(fillMode: TD2d1FillMode); stdcall;
    procedure SetSegmentFlags(vertexFlags: TD2d1PathSegment); stdcall;
    procedure BeginFigure(startPoint: TD2d1Point2f;
      figureBegin: TD2d1FigureBegin); stdcall;
    procedure AddLines(points: PD2d1Point2f; pointsCount: UINT); stdcall;
    procedure AddBeziers(beziers: PD2d1BezierSegment;
      beziersCount: UINT); stdcall;
    procedure EndFigure(figureEnd: TD2d1FigureEnd); stdcall;
    function Close: HResult; stdcall;
  end;

  ID2D1GeometrySink = interface(ID2D1SimplifiedGeometrySink)
  ['{2cd9069f-12e2-11dc-9fed-001143a055f9}']
    procedure AddLine(point: TD2d1Point2f); stdcall;
    procedure AddBezier(const bezier: TD2d1BezierSegment); stdcall;
    procedure AddQuadraticBezier(
      const bezier: TD2d1QuadraticBezierSegment); stdcall;
    procedure AddQuadraticBeziers(beziers: PD2d1QuadraticBezierSegment;
      beziersCount: UINT); stdcall;
    procedure AddArc(const arc: TD2d1ArcSegment); stdcall;
  end;

  ID2D1PathGeometry = interface(ID2D1Geometry)
  ['{2cd906a5-12e2-11dc-9fed-001143a055f9}']
    function Open(out geometrySink: ID2D1GeometrySink): HResult; stdcall;
    function Stream(geometrySink: ID2D1GeometrySink): HResult; stdcall;
    function GetSegmentCount(out count: UINT32): HResult; stdcall;
    function GetFigureCount(out count: UINT32): HResult; stdcall;
  end;

  // ID2D1RenderTarget -- 53 own methods
  ID2D1RenderTarget = interface(ID2D1Resource)
  ['{2cd90694-12e2-11dc-9fed-001143a055f9}']
    function CreateBitmap(size: TD2d1SizeU; srcData: Pointer; pitch: UINT32;
      const bitmapProperties: PD2d1BitmapProperties;
      out bitmap: ID2D1Bitmap): HResult; stdcall;
    function CreateBitmapFromWicBitmap(wicBitmapSource: IWICBitmapSource;
      const bitmapProperties: PD2d1BitmapProperties;
      out bitmap: ID2D1Bitmap): HResult; stdcall;
    function CreateSharedBitmap(const riid: TIID; data: Pointer;
      const bitmapProperties: PD2d1BitmapProperties;
      out bitmap: ID2D1Bitmap): HResult; stdcall;
    function CreateBitmapBrush(bitmap: ID2D1Bitmap;
      const bitmapBrushProperties: PD2d1BitmapBrushProperties;
      const brushProperties: PD2d1BrushProperties;
      out bitmapBrush: ID2D1BitmapBrush): HResult; stdcall;
    function CreateSolidColorBrush(const color: TD2d1ColorF;
      const brushProperties: PD2d1BrushProperties;
      out solidColorBrush: ID2D1SolidColorBrush): HResult; stdcall;
    function CreateGradientStopCollection(const gradientStops: PD2d1GradientStop;
      gradientStopsCount: UINT; colorInterpolationGamma: TD2d1Gamma;
      extendMode: TD2d1ExtendMode;
      out gradientStopCollection: ID2D1GradientStopCollection): HResult; stdcall;
    function CreateLinearGradientBrush(
      const linearGradientBrushProperties: PD2d1LinearGradientBrushProperties;
      const brushProperties: PD2d1BrushProperties;
      gradientStopCollection: ID2D1GradientStopCollection;
      out linearGradientBrush: ID2D1LinearGradientBrush): HResult; stdcall;
    function CreateRadialGradientBrush(
      const radialGradientBrushProperties: PD2d1RadialGradientBrushProperties;
      const brushProperties: PD2d1BrushProperties;
      gradientStopCollection: ID2D1GradientStopCollection;
      out radialGradientBrush: ID2D1RadialGradientBrush): HResult; stdcall;
    function CreateCompatibleRenderTarget(const desiredSize: PD2d1SizeF;
      const desiredPixelSize: PD2d1SizeU;
      const desiredFormat: PD2d1PixelFormat;
      options: TD2d1CompatibleRenderTargetOptions;
      out bitmapRenderTarget: ID2D1BitmapRenderTarget): HResult; stdcall;
    function CreateLayer(const size: PD2d1SizeF;
      out layer: ID2D1Layer): HResult; stdcall;
    function CreateMesh(out mesh: ID2D1Mesh): HResult; stdcall;
    procedure DrawLine(point0: TD2d1Point2f; point1: TD2d1Point2f;
      brush: ID2D1Brush; strokeWidth: FLOAT = 1.0;
      strokeStyle: ID2D1StrokeStyle = nil); stdcall;
    procedure DrawRectangle(const rect: PD2d1RectF; brush: ID2D1Brush;
      strokeWidth: FLOAT = 1.0;
      strokeStyle: ID2D1StrokeStyle = nil); stdcall;
    procedure FillRectangle(const rect: PD2d1RectF;
      brush: ID2D1Brush); stdcall;
    procedure DrawRoundedRectangle(const roundedRect: PD2d1RoundedRect;
      brush: ID2D1Brush; strokeWidth: FLOAT = 1.0;
      strokeStyle: ID2D1StrokeStyle = nil); stdcall;
    procedure FillRoundedRectangle(const roundedRect: PD2d1RoundedRect;
      brush: ID2D1Brush); stdcall;
    procedure DrawEllipse(const ellipse: PD2d1Ellipse; brush: ID2D1Brush;
      strokeWidth: FLOAT = 1.0;
      strokeStyle: ID2D1StrokeStyle = nil); stdcall;
    procedure FillEllipse(const ellipse: PD2d1Ellipse;
      brush: ID2D1Brush); stdcall;
    procedure DrawGeometry(geometry: ID2D1Geometry; brush: ID2D1Brush;
      strokeWidth: FLOAT = 1.0;
      strokeStyle: ID2D1StrokeStyle = nil); stdcall;
    procedure FillGeometry(geometry: ID2D1Geometry; brush: ID2D1Brush;
      opacityBrush: ID2D1Brush = nil); stdcall;
    procedure FillMesh(mesh: ID2D1Mesh; brush: ID2D1Brush); stdcall;
    procedure FillOpacityMask(opacityMask: ID2D1Bitmap; brush: ID2D1Brush;
      content: TD2d1OpacityMaskContent;
      destinationRectangle: PD2d1RectF = nil;
      sourceRectangle: PD2d1RectF = nil); stdcall;
    procedure DrawBitmap(bitmap: ID2D1Bitmap;
      destinationRectangle: PD2d1RectF = nil; opacity: FLOAT = 1.0;
      interpolationMode: TD2d1BitmapInterpolationMode = D2D1_BITMAP_INTERPOLATION_MODE_LINEAR;
      sourceRectangle: PD2d1RectF = nil); stdcall;
    procedure DrawText(_string: PWCHAR; stringLength: UINT;
      textFormat: IDWriteTextFormat; const layoutRect: PD2d1RectF;
      defaultForegroundBrush: ID2D1Brush;
      options: TD2d1DrawTextOptions = D2D1_DRAW_TEXT_OPTIONS_NONE;
      measuringMode: TDwriteMeasuringMode = DWRITE_MEASURING_MODE_NATURAL); stdcall;
    procedure DrawTextLayout(origin: TD2d1Point2f;
      textLayout: IDWriteTextLayout; defaultForegroundBrush: ID2D1Brush;
      options: TD2d1DrawTextOptions = D2D1_DRAW_TEXT_OPTIONS_NONE); stdcall;
    procedure DrawGlyphRun(baselineOrigin: TD2d1Point2f;
      const glyphRun: PDwriteGlyphRun; foregroundBrush: ID2D1Brush;
      measuringMode: TDwriteMeasuringMode = DWRITE_MEASURING_MODE_NATURAL); stdcall;
    procedure SetTransform(const transform: PD2d1Matrix3x2F); stdcall;
    procedure GetTransform(out transform: TD2d1Matrix3x2F); stdcall;
    procedure SetAntialiasMode(antialiasMode: TD2d1AntialiasMode); stdcall;
    function GetAntialiasMode: TD2d1AntialiasMode; stdcall;
    procedure SetTextAntialiasMode(
      textAntialiasMode: TD2d1TextAntialiasMode); stdcall;
    function GetTextAntialiasMode: TD2d1TextAntialiasMode; stdcall;
    procedure SetTextRenderingParams(
      textRenderingParams: IDWriteRenderingParams); stdcall;
    procedure GetTextRenderingParams(
      out textRenderingParams: IDWriteRenderingParams); stdcall;
    procedure SetTags(tag1: TD2D1Tag; tag2: TD2D1Tag); stdcall;
    procedure GetTags(out tag1: TD2D1Tag; out tag2: TD2D1Tag); stdcall;
    procedure PushLayer(const layerParameters: PD2d1LayerParameters;
      layer: ID2D1Layer); stdcall;
    procedure PopLayer; stdcall;
    function Flush(out tag1: TD2D1Tag; out tag2: TD2D1Tag): HResult; stdcall;
    procedure SaveDrawingState(
      var drawingStateBlock: ID2D1DrawingStateBlock); stdcall;
    procedure RestoreDrawingState(
      drawingStateBlock: ID2D1DrawingStateBlock); stdcall;
    procedure PushAxisAlignedClip(const clipRect: PD2d1RectF;
      antialiasMode: TD2d1AntialiasMode); stdcall;
    procedure PopAxisAlignedClip; stdcall;
    procedure Clear(const clearColor: TD2d1ColorF); stdcall;
    procedure BeginDraw; stdcall;
    function EndDraw(tag1: PD2D1Tag = nil;
      tag2: PD2D1Tag = nil): HResult; stdcall;
    function GetPixelFormat: TD2d1PixelFormat; stdcall;
    procedure SetDpi(dpiX: FLOAT; dpiY: FLOAT); stdcall;
    procedure GetDpi(out dpiX: FLOAT; out dpiY: FLOAT); stdcall;
    function GetSize: TD2d1SizeF; stdcall;
    function GetPixelSize: TD2d1SizeU; stdcall;
    function GetMaximumBitmapSize: UINT32; stdcall;
    function IsSupported(
      const renderTargetProperties: PD2d1RenderTargetProperties): BOOL; stdcall;
  end;

  ID2D1DCRenderTarget = interface(ID2D1RenderTarget)
  ['{1c51bc64-de61-46fd-9899-63a5d8f03950}']
    function BindDC(const hDC: HDC; const pSubRect: TRect): HResult; stdcall;
  end;

  ID2D1Factory = interface(IUnknown)
  ['{06152247-6f50-465a-9245-118bfd3b6007}']
    function ReloadSystemMetrics: HResult; stdcall;
    procedure GetDesktopDpi(out dpiX: FLOAT; out dpiY: FLOAT); stdcall;
    function CreateRectangleGeometry(const rectangle: TD2d1RectF;
      out rectangleGeometry: ID2D1RectangleGeometry): HResult; stdcall;
    function CreateRoundedRectangleGeometry(
      const roundedRectangle: TD2d1RoundedRect;
      out roundedRectangleGeometry: ID2D1RoundedRectangleGeometry): HResult; stdcall;
    function CreateEllipseGeometry(const ellipse: TD2d1Ellipse;
      out ellipseGeometry: ID2D1EllipseGeometry): HResult; stdcall;
    function CreateGeometryGroup(fillMode: TD2d1FillMode;
      geometries: Pointer; geometriesCount: UINT;
      out geometryGroup: ID2D1GeometryGroup): HResult; stdcall;
    function CreateTransformedGeometry(sourceGeometry: ID2D1Geometry;
      const transform: TD2d1Matrix3x2F;
      out transformedGeometry: ID2D1TransformedGeometry): HResult; stdcall;
    function CreatePathGeometry(
      out pathGeometry: ID2D1PathGeometry): HResult; stdcall;
    function CreateStrokeStyle(
      const strokeStyleProperties: TD2d1StrokeStyleProperties;
      const dashes: PFLOAT; dashesCount: UINT;
      out strokeStyle: ID2D1StrokeStyle): HResult; stdcall;
    function CreateDrawingStateBlock(
      const drawingStateDescription: TD2d1DrawingStateDescription;
      textRenderingParams: IDWriteRenderingParams;
      out drawingStateBlock: ID2D1DrawingStateBlock): HResult; stdcall;
    function CreateWicBitmapRenderTarget(target: IWICBitmap;
      const renderTargetProperties: TD2d1RenderTargetProperties;
      out renderTarget: ID2D1RenderTarget): HResult; stdcall;
    function CreateHwndRenderTarget(
      const renderTargetProperties: TD2d1RenderTargetProperties;
      const hwndRenderTargetProperties: TD2d1HwndRenderTargetProperties;
      out hwndRenderTarget: ID2D1HwndRenderTarget): HResult; stdcall;
    function CreateDxgiSurfaceRenderTarget(dxgiSurface: IDXGISurface;
      const renderTargetProperties: TD2d1RenderTargetProperties;
      out renderTarget: ID2D1RenderTarget): HResult; stdcall;
    function CreateDCRenderTarget(
      const renderTargetProperties: TD2d1RenderTargetProperties;
      out dcRenderTarget: ID2D1DCRenderTarget): HResult; stdcall;
  end;

// =========================================================================
// Section 14 -- DWrite interfaces
// =========================================================================

  IDWriteFontCollection = interface(IUnknown)
  ['{a84cee02-3eea-4eee-a827-87c1a02a0fcc}']
    function GetFontFamilyCount: UINT32; stdcall;
    function GetFontFamily(index: UINT32;
      out fontFamily: IDWriteFontFamily): HResult; stdcall;
    function FindFamilyName(const familyName: PWCHAR;
      out index: UINT32; out exists: BOOL): HResult; stdcall;
    function GetFontFromFontFace(fontFace: IDWriteFontFace;
      out font: IDWriteFont): HResult; stdcall;
  end;

  IDWriteFontList = interface(IUnknown)
  ['{1a0d8438-1d97-4ec1-aef9-a2fb86ed6acb}']
    function GetFontCollection(
      out fontCollection: IDWriteFontCollection): HResult; stdcall;
    function GetFontCount: UINT32; stdcall;
    function GetFont(index: UINT32;
      out font: IDWriteFont): HResult; stdcall;
  end;

  IDWriteFontFamily = interface(IDWriteFontList)
  ['{da20d8ef-812a-4c43-9802-62ec4abd7add}']
    function GetFamilyNames(
      out names: IDWriteLocalizedStrings): HResult; stdcall;
    function GetFirstMatchingFont(weight: TDwriteFontWeight;
      stretch: TDwriteFontStretch; style: TDwriteFontStyle;
      out matchingFont: IDWriteFont): HResult; stdcall;
    function GetMatchingFonts(weight: TDwriteFontWeight;
      stretch: TDwriteFontStretch; style: TDwriteFontStyle;
      out matchingFonts: IDWriteFontList): HResult; stdcall;
  end;

  IDWriteFont = interface(IUnknown)
  ['{acd16696-8c14-4f5d-877e-fe3fc1d32737}']
    function GetFontFamily(
      out fontFamily: IDWriteFontFamily): HResult; stdcall;
    function GetWeight: TDwriteFontWeight; stdcall;
    function GetStretch: TDwriteFontStretch; stdcall;
    function GetStyle: TDwriteFontStyle; stdcall;
    function IsSymbolFont: BOOL; stdcall;
    function GetFaceNames(
      out names: IDWriteLocalizedStrings): HResult; stdcall;
    function GetInformationalStrings(
      informationalStringID: TDwriteInformationalStringId;
      out informationalStrings: IDWriteLocalizedStrings;
      out exists: BOOL): HResult; stdcall;
    function GetSimulations: TDwriteFontSimulations; stdcall;
    procedure GetMetrics(out fontMetrics: TDwriteFontMetrics); stdcall;
    function HasCharacter(unicodeValue: UINT32;
      out exists: BOOL): HResult; stdcall;
    function CreateFontFace(
      out fontFace: IDWriteFontFace): HResult; stdcall;
  end;

  IDWriteTextFormat = interface(IUnknown)
  ['{9c906818-31d7-4fd3-a151-7c5e225db55a}']
    function SetTextAlignment(
      textAlignment: TDwriteTextAlignment): HResult; stdcall;
    function SetParagraphAlignment(
      paragraphAlignment: TDwriteParagraphAlignment): HResult; stdcall;
    function SetWordWrapping(
      wordWrapping: TDwriteWordWrapping): HResult; stdcall;
    function SetReadingDirection(
      readingDirection: TDwriteReadingDirection): HResult; stdcall;
    function SetFlowDirection(
      flowDirection: TDwriteFlowDirection): HResult; stdcall;
    function SetIncrementalTabStop(
      incrementalTabStop: FLOAT): HResult; stdcall;
    function SetTrimming(const trimmingOptions: TDwriteTrimming;
      trimmingSign: IDWriteInlineObject): HResult; stdcall;
    function SetLineSpacing(lineSpacingMethod: TDwriteLineSpacingMethod;
      lineSpacing: FLOAT; baseline: FLOAT): HResult; stdcall;
    function GetTextAlignment: TDwriteTextAlignment; stdcall;
    function GetParagraphAlignment: TDwriteParagraphAlignment; stdcall;
    function GetWordWrapping: TDwriteWordWrapping; stdcall;
    function GetReadingDirection: TDwriteReadingDirection; stdcall;
    function GetFlowDirection: TDwriteFlowDirection; stdcall;
    function GetIncrementalTabStop: FLOAT; stdcall;
    function GetTrimming(out trimmingOptions: TDwriteTrimming;
      out trimmingSign: IDWriteInlineObject): HResult; stdcall;
    function GetLineSpacing(out lineSpacingMethod: TDwriteLineSpacingMethod;
      out lineSpacing: FLOAT; out baseline: FLOAT): HResult; stdcall;
    function GetFontCollection(
      out fontCollection: IDWriteFontCollection): HResult; stdcall;
    function GetFontFamilyNameLength: UINT32; stdcall;
    function GetFontFamilyName(var fontFamilyName: WCHAR;
      nameSize: UINT32): HResult; stdcall;
    function GetFontWeight: TDwriteFontWeight; stdcall;
    function GetFontStyle: TDwriteFontStyle; stdcall;
    function GetFontStretch: TDwriteFontStretch; stdcall;
    function GetFontSize: FLOAT; stdcall;
    function GetLocaleNameLength: UINT32; stdcall;
    function GetLocaleName(var localeName: WCHAR;
      nameSize: UINT32): HResult; stdcall;
  end;

  IDWriteTextLayout = interface(IDWriteTextFormat)
  ['{53737037-6d14-410b-9bfe-0b182bb70961}']
    function SetMaxWidth(maxWidth: FLOAT): HResult; stdcall;
    function SetMaxHeight(maxHeight: FLOAT): HResult; stdcall;
    function SetFontCollection(fontCollection: IDWriteFontCollection;
      textRange: TDwriteTextRange): HResult; stdcall;
    function SetFontFamilyName(fontFamilyName: PWCHAR;
      textRange: TDwriteTextRange): HResult; stdcall;
    function SetFontWeight(fontWeight: TDwriteFontWeight;
      textRange: TDwriteTextRange): HResult; stdcall;
    function SetFontStyle(fontStyle: TDwriteFontStyle;
      textRange: TDwriteTextRange): HResult; stdcall;
    function SetFontStretch(fontStretch: TDwriteFontStretch;
      textRange: TDwriteTextRange): HResult; stdcall;
    function SetFontSize(fontSize: FLOAT;
      textRange: TDwriteTextRange): HResult; stdcall;
    function SetUnderline(hasUnderline: BOOL;
      textRange: TDwriteTextRange): HResult; stdcall;
    function SetStrikethrough(hasStrikethrough: BOOL;
      textRange: TDwriteTextRange): HResult; stdcall;
    function SetDrawingEffect(drawingEffect: IUnknown;
      textRange: TDwriteTextRange): HResult; stdcall;
    function SetInlineObject(inlineObject: IDWriteInlineObject;
      textRange: TDwriteTextRange): HResult; stdcall;
    function SetTypography(typography: IDWriteTypography;
      textRange: TDwriteTextRange): HResult; stdcall;
    function SetLocaleName(const localeName: PWCHAR;
      textRange: TDwriteTextRange): HResult; stdcall;
    function GetMaxWidth: FLOAT; stdcall;
    function GetMaxHeight: FLOAT; stdcall;
    function _GetFontCollection(currentPosition: UINT32;
      out fontCollection: IDWriteFontCollection;
      out textRange: TDwriteTextRange): HResult; stdcall;
    function _GetFontFamilyNameLength(currentPosition: UINT32;
      nameLength: PUINT32; textRange: PDwriteTextRange): HResult; stdcall;
    function _GetFontFamilyName(currentPosition: UINT32;
      var fontFamilyName: WCHAR; nameSize: UINT32;
      var textRange: TDwriteTextRange): HResult; stdcall;
    function _GetFontWeight(currentPosition: UINT32;
      var fontWeight: TDwriteFontWeight;
      var textRange: TDwriteTextRange): HResult; stdcall;
    function _GetFontStyle(currentPosition: UINT32;
      var fontStyle: TDwriteFontStyle;
      var textRange: TDwriteTextRange): HResult; stdcall;
    function _GetFontStretch(currentPosition: UINT32;
      var fontStretch: TDwriteFontStretch;
      var textRange: TDwriteTextRange): HResult; stdcall;
    function _GetFontSize(currentPosition: UINT32;
      var fontSize: FLOAT;
      var textRange: TDwriteTextRange): HResult; stdcall;
    function GetUnderline(currentPosition: UINT32;
      out hasUnderline: BOOL;
      out textRange: TDwriteTextRange): HResult; stdcall;
    function GetStrikethrough(currentPosition: UINT32;
      out hasStrikethrough: BOOL;
      out textRange: TDwriteTextRange): HResult; stdcall;
    function GetDrawingEffect(currentPosition: UINT32;
      out drawingEffect: IUnknown;
      out textRange: TDwriteTextRange): HResult; stdcall;
    function GetInlineObject(currentPosition: UINT32;
      out inlineObject: IDWriteInlineObject;
      out textRange: TDwriteTextRange): HResult; stdcall;
    function GetTypography(currentPosition: UINT32;
      out typography: IDWriteTypography;
      out textRange: TDwriteTextRange): HResult; stdcall;
    function _GetLocaleNameLength(currentPosition: UINT32;
      out nameLength: UINT32;
      out textRange: TDwriteTextRange): HResult; stdcall;
    function _GetLocaleName(currentPosition: UINT32;
      var localeName: WCHAR; nameSize: UINT32;
      out textRange: TDwriteTextRange): HResult; stdcall;
    function Draw(clientDrawingContext: Pointer;
      renderer: IDWriteTextRenderer;
      originX: FLOAT; originY: FLOAT): HResult; stdcall;
    function GetLineMetrics(var lineMetrics: TDwriteLineMetrics;
      maxLineCount: UINT32;
      out actualLineCount: UINT32): HResult; stdcall;
    function GetMetrics(
      out textMetrics: TDwriteTextMetrics): HResult; stdcall;
    function GetOverhangMetrics(
      out overhangs: TDwriteOverhangMetrics): HResult; stdcall;
    function GetClusterMetrics(var clusterMetrics: TDwriteClusterMetrics;
      maxClusterCount: UINT32;
      out actualClusterCount: UINT32): HResult; stdcall;
    function DetermineMinWidth(out minWidth: FLOAT): HResult; stdcall;
    function HitTestPoint(pointX: FLOAT; pointY: FLOAT;
      out isTrailingHit: BOOL; out isInside: BOOL;
      out hitTestMetrics: TDwriteHitTestMetrics): HResult; stdcall;
    function HitTestTextPosition(textPosition: UINT32;
      isTrailingHit: BOOL; out pointX: FLOAT; out pointY: FLOAT;
      out hitTestMetrics: TDwriteHitTestMetrics): HResult; stdcall;
    function HitTestTextRange(textPosition: UINT32; textLength: UINT32;
      originX: FLOAT; originY: FLOAT;
      var hitTestMetrics: TDwriteHitTestMetrics;
      maxHitTestMetricsCount: UINT32;
      out actualHitTestMetricsCount: UINT32): HResult; stdcall;
  end;

  IDWriteFactory = interface(IUnknown)
  ['{b859ee5a-d838-4b5b-a2e8-1adc7d93db48}']
    function GetSystemFontCollection(
      out fontCollection: IDWriteFontCollection;
      checkForUpdates: BOOL = FALSE): HResult; stdcall;
    function CreateCustomFontCollection(
      collectionLoader: IDWriteFontCollectionLoader;
      collectionKey: Pointer; collectionKeySize: UINT32;
      out fontCollection: IDWriteFontCollection): HResult; stdcall;
    function RegisterFontCollectionLoader(
      fontCollectionLoader: IDWriteFontCollectionLoader): HResult; stdcall;
    function UnregisterFontCollectionLoader(
      fontCollectionLoader: IDWriteFontCollectionLoader): HResult; stdcall;
    function CreateFontFileReference(const filePath: PWCHAR;
      const lastWriteTime: Pointer;
      out fontFile: IDWriteFontFile): HResult; stdcall;
    function CreateCustomFontFileReference(
      fontFileReferenceKey: Pointer; fontFileReferenceKeySize: UINT32;
      fontFileLoader: IDWriteFontFileLoader;
      out fontFile: IDWriteFontFile): HResult; stdcall;
    function CreateFontFace(fontFaceType: TDwriteFontFaceType;
      numberOfFiles: UINT32; const fontFiles: IDWriteFontFile;
      faceIndex: UINT32; fontFaceSimulationFlags: TDwriteFontSimulations;
      out fontFace: IDWriteFontFace): HResult; stdcall;
    function CreateRenderingParams(
      out renderingParams: IDWriteRenderingParams): HResult; stdcall;
    function CreateMonitorRenderingParams(monitor: HMONITOR;
      out renderingParams: IDWriteRenderingParams): HResult; stdcall;
    function CreateCustomRenderingParams(gamma: FLOAT;
      enhancedContrast: FLOAT; clearTypeLevel: FLOAT;
      pixelGeometry: TDwritePixelGeometry;
      renderingMode: TDwriteRenderingMode;
      out renderingParams: IDWriteRenderingParams): HResult; stdcall;
    function RegisterFontFileLoader(
      fontFileLoader: IDWriteFontFileLoader): HResult; stdcall;
    function UnregisterFontFileLoader(
      fontFileLoader: IDWriteFontFileLoader): HResult; stdcall;
    function CreateTextFormat(const fontFamilyName: PWCHAR;
      fontCollection: IDWriteFontCollection;
      fontWeight: TDwriteFontWeight; fontStyle: TDwriteFontStyle;
      fontStretch: TDwriteFontStretch; fontSize: FLOAT;
      const localeName: PWCHAR;
      out textFormat: IDWriteTextFormat): HResult; stdcall;
    function CreateTypography(
      out typography: IDWriteTypography): HResult; stdcall;
    function GetGdiInterop(
      out gdiInterop: IDWriteGdiInterop): HResult; stdcall;
    function CreateTextLayout(_string: PWCHAR; stringLength: UINT32;
      textFormat: IDWriteTextFormat; maxWidth: FLOAT; maxHeight: FLOAT;
      out textLayout: IDWriteTextLayout): HResult; stdcall;
    function CreateGdiCompatibleTextLayout(const _string: PWCHAR;
      stringLength: UINT32; textFormat: IDWriteTextFormat;
      layoutWidth: FLOAT; layoutHeight: FLOAT; pixelsPerDip: FLOAT;
      const transform: PDwriteMatrix; useGdiNatural: BOOL;
      out textLayout: IDWriteTextLayout): HResult; stdcall;
    function CreateEllipsisTrimmingSign(textFormat: IDWriteTextFormat;
      out trimmingSign: IDWriteInlineObject): HResult; stdcall;
    function CreateTextAnalyzer(
      out textAnalyzer: IDWriteTextAnalyzer): HResult; stdcall;
    function CreateNumberSubstitution(
      substitutionMethod: TDwriteNumberSubstitutionMethod;
      const localeName: PWCHAR; ignoreUserOverride: BOOL;
      out numberSubstitution: IDWriteNumberSubstitution): HResult; stdcall;
    function CreateGlyphRunAnalysis(const glyphRun: PDwriteGlyphRun;
      pixelsPerDip: FLOAT; const transform: PDwriteMatrix;
      renderingMode: TDwriteRenderingMode;
      measuringMode: TDwriteMeasuringMode;
      baselineOriginX: FLOAT; baselineOriginY: FLOAT;
      out glyphRunAnalysis: IDWriteGlyphRunAnalysis): HResult; stdcall;
  end;

// =========================================================================
// Section 15 -- WIC interfaces
// =========================================================================

  IWICBitmapSource = interface(IUnknown)
  ['{00000120-a8f2-4877-ba0a-fd2b6645fb94}']
    function GetSize(var puiWidth: UINT;
      var puiHeight: UINT): HResult; stdcall;
    function GetPixelFormat(
      var pPixelFormat: WICPixelFormatGUID): HResult; stdcall;
    function GetResolution(var pDpiX: Double;
      var pDpiY: Double): HResult; stdcall;
    function CopyPalette(pIPalette: IWICPalette): HResult; stdcall;
    function CopyPixels(prc: PWicrect; cbStride: UINT;
      cbBufferSize: UINT; pbBuffer: PByte): HResult; stdcall;
  end;

  IWICBitmapFrameDecode = interface(IWICBitmapSource)
  ['{3B16811B-6A43-4ec9-A813-3D930C13B940}']
    function GetMetadataQueryReader(
      out ppIMetadataQueryReader: IWICMetadataQueryReader): HResult; stdcall;
    function GetColorContexts(cCount: UINT;
      ppIColorContexts: Pointer;
      var pcActualCount: UINT): HResult; stdcall;
    function GetThumbnail(
      out ppIThumbnail: IWICBitmapSource): HResult; stdcall;
  end;

  IWICBitmapDecoder = interface(IUnknown)
  ['{9EDDE9E7-8DEE-47ea-99DF-E6FAF2ED44BF}']
    function QueryCapability(pIStream: IStream;
      out pdwCapability: DWORD): HResult; stdcall;
    function Initialize(pIStream: IStream;
      cacheOptions: TWicdecodeoptions): HResult; stdcall;
    function GetContainerFormat(
      var pguidContainerFormat: TGuid): HResult; stdcall;
    function GetDecoderInfo(
      out ppIDecoderInfo: IWICBitmapDecoderInfo): HResult; stdcall;
    function CopyPalette(pIPalette: IWICPalette): HResult; stdcall;
    function GetMetadataQueryReader(
      out ppIMetadataQueryReader: IWICMetadataQueryReader): HResult; stdcall;
    function GetPreview(
      out ppIBitmapSource: IWICBitmapSource): HResult; stdcall;
    function GetColorContexts(cCount: UINT;
      ppIColorContexts: Pointer;
      var pcActualCount: UINT): HResult; stdcall;
    function GetThumbnail(
      out ppIThumbnail: IWICBitmapSource): HResult; stdcall;
    function GetFrameCount(var pCount: UINT): HResult; stdcall;
    function GetFrame(index: UINT;
      out ppIBitmapFrame: IWICBitmapFrameDecode): HResult; stdcall;
  end;

  IWICFormatConverter = interface(IWICBitmapSource)
  ['{00000301-a8f2-4877-ba0a-fd2b6645fb94}']
    function Initialize(pISource: IWICBitmapSource;
      const dstFormat: WICPixelFormatGUID;
      dither: TWicbitmapdithertype;
      const pIPalette: IWICPalette;
      alphaThresholdPercent: Double;
      paletteTranslate: TWicbitmappalettetype): HResult; stdcall;
    function CanConvert(srcPixelFormat: REFWICPixelFormatGUID;
      dstPixelFormat: REFWICPixelFormatGUID;
      var pfCanConvert: BOOL): HResult; stdcall;
  end;

  IWICBitmap = interface(IWICBitmapSource)
  ['{00000121-a8f2-4877-ba0a-fd2b6645fb94}']
    function Lock(const prcLock: PWicrect; flags: DWORD;
      out ppILock: IWICBitmapLock): HResult; stdcall;
    function SetPalette(pIPalette: IWICPalette): HResult; stdcall;
    function SetResolution(dpiX: Double; dpiY: Double): HResult; stdcall;
  end;

  IWICImagingFactory = interface(IUnknown)
  ['{ec5ec8a9-c395-4314-9c77-54d7a935ff70}']
    function CreateDecoderFromFilename(wzFilename: LPCWSTR;
      const pguidVendor: TGuid; dwDesiredAccess: DWORD;
      metadataOptions: TWicdecodeoptions;
      out ppIDecoder: IWICBitmapDecoder): HResult; stdcall;
    function CreateDecoderFromStream(pIStream: IStream;
      const pguidVendor: TGuid; metadataOptions: TWicdecodeoptions;
      out ppIDecoder: IWICBitmapDecoder): HResult; stdcall;
    function CreateDecoderFromFileHandle(hFile: ULONG_PTR;
      const pguidVendor: TGuid; metadataOptions: TWicdecodeoptions;
      out ppIDecoder: IWICBitmapDecoder): HResult; stdcall;
    function CreateComponentInfo(clsidComponent: TGuid;
      out ppIInfo: IWICComponentInfo): HResult; stdcall;
    function CreateDecoder(const guidContainerFormat: TGuid;
      const pguidVendor: TGuid;
      out ppIDecoder: IWICBitmapDecoder): HResult; stdcall;
    function CreateEncoder(const guidContainerFormat: TGuid;
      const pguidVendor: TGuid;
      out ppIEncoder: IWICBitmapEncoder): HResult; stdcall;
    function CreatePalette(
      out ppIPalette: IWICPalette): HResult; stdcall;
    function CreateFormatConverter(
      out ppIFormatConverter: IWICFormatConverter): HResult; stdcall;
    function CreateBitmapScaler(
      out ppIBitmapScaler: IWICBitmapScaler): HResult; stdcall;
    function CreateBitmapClipper(
      out ppIBitmapClipper: IWICBitmapClipper): HResult; stdcall;
    function CreateBitmapFlipRotator(
      out ppIBitmapFlipRotator: IWICBitmapFlipRotator): HResult; stdcall;
    function CreateStream(
      out ppIWICStream: IWICStream): HResult; stdcall;
    function CreateColorContext(
      out ppIWICColorContext: IWICColorContext): HResult; stdcall;
    function CreateColorTransformer(
      out ppIWICColorTransform: IWICColorTransform): HResult; stdcall;
    function CreateBitmap(uiWidth: UINT; uiHeight: UINT;
      pixelFormat: REFWICPixelFormatGUID;
      option: TWicbitmapcreatecacheoption;
      out ppIBitmap: IWICBitmap): HResult; stdcall;
    function CreateBitmapFromSource(piBitmapSource: IWICBitmapSource;
      option: TWicbitmapcreatecacheoption;
      out ppIBitmap: IWICBitmap): HResult; stdcall;
    function CreateBitmapFromSourceRect(piBitmapSource: IWICBitmapSource;
      x: UINT; y: UINT; width: UINT; height: UINT;
      out ppIBitmap: IWICBitmap): HResult; stdcall;
    function CreateBitmapFromMemory(uiWidth: UINT; uiHeight: UINT;
      pixelFormat: REFWICPixelFormatGUID;
      cbStride: UINT; cbBufferSize: UINT; pbBuffer: PByte;
      out ppIBitmap: IWICBitmap): HResult; stdcall;
    function CreateBitmapFromHBITMAP(hBitmap: HBITMAP;
      hPalette: HPALETTE; options: TWicbitmapalphachanneloption;
      out ppIBitmap: IWICBitmap): HResult; stdcall;
    function CreateBitmapFromHICON(hIcon: HICON;
      out ppIBitmap: IWICBitmap): HResult; stdcall;
    function CreateComponentEnumerator(componentTypes: DWORD;
      options: DWORD;
      out ppIEnumUnknown: IEnumUnknown): HResult; stdcall;
    function CreateFastMetadataEncoderFromDecoder(
      pIDecoder: IWICBitmapDecoder;
      out ppIFastEncoder: IWICFastMetadataEncoder): HResult; stdcall;
    function CreateFastMetadataEncoderFromFrameDecode(
      pIFrameDecoder: IWICBitmapFrameDecode;
      out ppIFastEncoder: IWICFastMetadataEncoder): HResult; stdcall;
    function CreateQueryWriter(const guidMetadataFormat: TGuid;
      const pguidVendor: TGuid;
      out ppIQueryWriter: IWICMetadataQueryWriter): HResult; stdcall;
    function CreateQueryWriterFromReader(
      pIQueryReader: IWICMetadataQueryReader;
      const pguidVendor: TGuid;
      out ppIQueryWriter: IWICMetadataQueryWriter): HResult; stdcall;
  end;

// =========================================================================
// Section 16 -- DeviceContext chain
// =========================================================================

  // ID2D1DeviceContext -- 35 own methods (inherits ID2D1RenderTarget)
  ID2D1DeviceContext = interface(ID2D1RenderTarget)
  ['{e8f7fe7a-191c-466d-ad95-975678bda998}']
    function _DC_CreateBitmap(size: TD2d1SizeU; sourceData: Pointer;
      pitch: UINT32; const bitmapProperties: PD2d1BitmapProperties1;
      out bitmap: ID2D1Bitmap1): HResult; stdcall;
    function _DC_CreateBitmapFromWicBitmap(wicBitmapSource: IWICBitmapSource;
      const bitmapProperties: PD2d1BitmapProperties1;
      out bitmap: ID2D1Bitmap1): HResult; stdcall;
    function CreateColorContext(space: TD2d1ColorSpace;
      const profile: PByte; profileSize: UINT32;
      out colorContext: ID2D1ColorContext): HResult; stdcall;
    function CreateColorContextFromFilename(filename: PWCHAR;
      out colorContext: ID2D1ColorContext): HResult; stdcall;
    function CreateColorContextFromWicColorContext(
      wicColorContext: IWICColorContext;
      out colorContext: ID2D1ColorContext): HResult; stdcall;
    function CreateBitmapFromDxgiSurface(surface: IDXGISurface;
      const bitmapProperties: PD2d1BitmapProperties1;
      out bitmap: ID2D1Bitmap1): HResult; stdcall;
    function CreateEffect(const effectId: PGUID;
      out effect: ID2D1Effect): HResult; stdcall;
    function _DC_CreateGradientStopCollection(
      const straightAlphaGradientStops: PD2d1GradientStop;
      straightAlphaGradientStopsCount: UINT32;
      preInterpolationSpace: TD2d1ColorSpace;
      postInterpolationSpace: TD2d1ColorSpace;
      bufferPrecision: TD2d1BufferPrecision;
      extendMode: TD2d1ExtendMode;
      colorInterpolationMode: TD2d1ColorInterpolationMode;
      out gradientStopCollection1: ID2D1GradientStopCollection1): HResult; stdcall;
    function CreateImageBrush(image: ID2D1Image;
      const imageBrushProperties: PD2d1ImageBrushProperties;
      const brushProperties: PD2d1BrushProperties;
      out imageBrush: ID2D1ImageBrush): HResult; stdcall;
    function _DC_CreateBitmapBrush(bitmap: ID2D1Bitmap;
      const bitmapBrushProperties: PD2d1BitmapBrushProperties1;
      const brushProperties: PD2d1BrushProperties;
      out bitmapBrush: ID2D1BitmapBrush1): HResult; stdcall;
    function CreateCommandList(
      out commandList: ID2D1CommandList): HResult; stdcall;
    function IsDxgiFormatSupported(format: TDxgiFormat): BOOL; stdcall;
    function IsBufferPrecisionSupported(
      bufferPrecision: TD2d1BufferPrecision): BOOL; stdcall;
    function GetImageLocalBounds(image: ID2D1Image;
      out localBounds: TD2d1RectF): HResult; stdcall;
    function GetImageWorldBounds(image: ID2D1Image;
      out worldBounds: TD2d1RectF): HResult; stdcall;
    function GetGlyphRunWorldBounds(baselineOrigin: TD2d1Point2f;
      glyphRun: PDwriteGlyphRun; measuringMode: TDwriteMeasuringMode;
      out bounds: TD2d1RectF): HResult; stdcall;
    procedure GetDevice(out device: ID2D1Device); stdcall;
    procedure SetTarget(image: ID2D1Image); stdcall;
    procedure GetTarget(out image: ID2D1Image); stdcall;
    procedure SetRenderingControls(
      const renderingControls: PD2d1RenderingControls); stdcall;
    procedure GetRenderingControls(
      renderingControls: Pointer); stdcall;
    procedure SetPrimitiveBlend(
      primitiveBlend: TD2d1PrimitiveBlend); stdcall;
    function GetPrimitiveBlend: TD2d1PrimitiveBlend; stdcall;
    procedure SetUnitMode(unitMode: TD2d1UnitMode); stdcall;
    function GetUnitMode: TD2d1UnitMode; stdcall;
    procedure _DC_DrawGlyphRun(baselineOrigin: TD2d1Point2f;
      glyphRun: PDwriteGlyphRun;
      glyphRunDescription: PDwriteGlyphRunDescription;
      foregroundBrush: ID2D1Brush;
      measuringMode: TDwriteMeasuringMode = DWRITE_MEASURING_MODE_NATURAL); stdcall;
    procedure DrawImage(image: ID2D1Image;
      const targetOffset: PD2d1Point2f = nil;
      const imageRectangle: PD2d1RectF = nil;
      interpolationMode: TD2d1InterpolationMode = D2D1_INTERPOLATION_MODE_LINEAR;
      compositeMode: TD2d1CompositeMode = D2D1_COMPOSITE_MODE_SOURCE_OVER); stdcall;
    procedure _DC_DrawGdiMetafile(gdiMetafile: ID2D1GdiMetafile;
      const targetOffset: PD2d1Point2f = nil); stdcall;
    procedure _DC_DrawBitmap(bitmap: ID2D1Bitmap;
      const destinationRectangle: PD2d1RectF; opacity: FLOAT;
      interpolationMode: TD2d1InterpolationMode;
      const sourceRectangle: PD2d1RectF = nil;
      const perspectiveTransform: PD2d1Matrix4x4F = nil); stdcall;
    procedure _DC_PushLayer(const layerParameters: PD2d1LayerParameters1;
      layer: ID2D1Layer); stdcall;
    function InvalidateEffectInputRectangle(effect: ID2D1Effect;
      input: UINT32; const inputRectangle: PD2d1RectF): HResult; stdcall;
    function GetEffectInvalidRectangleCount(effect: ID2D1Effect;
      out rectangleCount: UINT32): HResult; stdcall;
    function GetEffectInvalidRectangles(effect: ID2D1Effect;
      out rectangles: PD2d1RectF;
      rectanglesCount: UINT32): HResult; stdcall;
    function GetEffectRequiredInputRectangles(renderEffect: ID2D1Effect;
      const renderImageRectangle: PD2d1RectF;
      const inputDescriptions: PD2d1EffectInputDescription;
      out requiredInputRects: TD2d1RectF;
      inputCount: UINT32): HResult; stdcall;
    procedure _DC_FillOpacityMask(opacityMask: ID2D1Bitmap;
      brush: ID2D1Brush;
      const destinationRectangle: PD2d1RectF = nil;
      const sourceRectangle: PD2d1RectF = nil); stdcall;
  end;

  // ID2D1DeviceContext1 -- 3 own methods
  ID2D1DeviceContext1 = interface(ID2D1DeviceContext)
  ['{d37f57e4-6908-459f-a199-e72f24f79987}']
    function CreateFilledGeometryRealization(geometry: ID2D1Geometry;
      flatteningTolerance: FLOAT;
      out geometryRealization: ID2D1GeometryRealization): HResult; stdcall;
    function CreateStrokedGeometryRealization(geometry: ID2D1Geometry;
      flatteningTolerance: FLOAT; strokeWidth: FLOAT;
      strokeStyle: ID2D1StrokeStyle;
      out geometryRealization: ID2D1GeometryRealization): HResult; stdcall;
    procedure DrawGeometryRealization(
      geometryRealization: ID2D1GeometryRealization;
      brush: ID2D1Brush); stdcall;
  end;

  // ID2D1DeviceContext2 -- 11 own methods
  ID2D1DeviceContext2 = interface(ID2D1DeviceContext1)
  ['{394ea6a3-0c34-4321-950b-6ca20f0be6c7}']
    function CreateInk(const startPoint: PD2d1InkPoint;
      out ink: ID2D1Ink): HResult; stdcall;
    function CreateInkStyle(const inkStyleProperties: PD2d1InkStyleProperties;
      out inkStyle: ID2D1InkStyle): HResult; stdcall;
    function CreateGradientMesh(const patches: PD2d1GradientMeshPatch;
      patchesCount: UINT32;
      out gradientMesh: ID2D1GradientMesh): HResult; stdcall;
    function CreateImageSourceFromWic(wicBitmapSource: IWICBitmapSource;
      loadingOptions: TD2d1ImageSourceLoadingOptions;
      alphaMode: TD2d1AlphaMode;
      out imageSource: ID2D1ImageSourceFromWic): HResult; stdcall;
    function CreateLookupTable3D(precision: TD2d1BufferPrecision;
      const extents: PUint32; const data: PByte; dataCount: UINT32;
      const strides: PUint32;
      out lookupTable: ID2D1LookupTable3D): HResult; stdcall;
    function CreateImageSourceFromDxgi(surfaces: IDXGISurface;
      surfaceCount: UINT32; colorSpace: TDxgiColorSpaceType;
      options: TD2d1ImageSourceFromDxgiOptions;
      out imageSource: ID2D1ImageSource): HResult; stdcall;
    function GetGradientMeshWorldBounds(gradientMesh: ID2D1GradientMesh;
      out pBounds: TD2d1RectF): HResult; stdcall;
    procedure DrawInk(ink: ID2D1Ink; brush: ID2D1Brush;
      inkStyle: ID2D1InkStyle); stdcall;
    procedure DrawGradientMesh(
      gradientMesh: ID2D1GradientMesh); stdcall;
    procedure _DC2_DrawGdiMetafile(gdiMetafile: ID2D1GdiMetafile;
      const destinationRectangle: PD2d1RectF;
      const sourceRectangle: PD2d1RectF); stdcall;
    function CreateTransformedImageSource(imageSource: ID2D1ImageSource;
      const properties: PD2d1TransformedImageSourceProperties;
      out transformedImageSource: ID2D1TransformedImageSource): HResult; stdcall;
  end;

  // ID2D1DeviceContext3 -- 2 own methods
  ID2D1DeviceContext3 = interface(ID2D1DeviceContext2)
  ['{235a7496-8351-414c-bcd4-6672ab2d8e00}']
    function CreateSpriteBatch(
      out spriteBatch: ID2D1SpriteBatch): HResult; stdcall;
    procedure DrawSpriteBatch(spriteBatch: ID2D1SpriteBatch;
      startIndex: UINT32; spriteCount: UINT32; bitmap: ID2D1Bitmap;
      interpolationMode: TD2d1BitmapInterpolationMode;
      spriteOptions: TD2d1SpriteOptions); stdcall;
  end;

  // ID2D1DeviceContext4 -- 7 own methods
  ID2D1DeviceContext4 = interface(ID2D1DeviceContext3)
  ['{8c427831-3d90-4476-b647-c4fae349e4db}']
    function CreateSvgGlyphStyle(
      out svgGlyphStyle: ID2D1SvgGlyphStyle): HResult; stdcall;
    procedure _DC4_DrawText(const _string: PWCHAR; stringLength: UINT32;
      textFormat: IDWriteTextFormat; const layoutRect: PD2d1RectF;
      defaultFillBrush: ID2D1Brush; svgGlyphStyle: ID2D1SvgGlyphStyle;
      colorPaletteIndex: UINT32;
      options: TD2d1DrawTextOptions = D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT;
      measuringMode: TDwriteMeasuringMode = DWRITE_MEASURING_MODE_NATURAL); stdcall;
    procedure _DC4_DrawTextLayout(origin: TD2d1Point2f;
      textLayout: IDWriteTextLayout; defaultFillBrush: ID2D1Brush;
      svgGlyphStyle: ID2D1SvgGlyphStyle; colorPaletteIndex: UINT32;
      options: TD2d1DrawTextOptions = D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT); stdcall;
    procedure DrawColorBitmapGlyphRun(
      glyphImageFormat: TDwriteGlyphImageFormats;
      baselineOrigin: TD2d1Point2f; const glyphRun: PDwriteGlyphRun;
      measuringMode: TDwriteMeasuringMode = DWRITE_MEASURING_MODE_NATURAL;
      bitmapSnapOption: TD2d1ColorBitmapGlyphSnapOption = D2D1_COLOR_BITMAP_GLYPH_SNAP_OPTION_DEFAULT); stdcall;
    procedure DrawSvgGlyphRun(baselineOrigin: TD2d1Point2f;
      glyphRun: PDwriteGlyphRun; defaultFillBrush: ID2D1Brush;
      svgGlyphStyle: ID2D1SvgGlyphStyle; colorPaletteIndex: UINT32 = 0;
      measuringMode: TDwriteMeasuringMode = DWRITE_MEASURING_MODE_NATURAL); stdcall;
    function GetColorBitmapGlyphImage(
      glyphImageFormat: TDwriteGlyphImageFormats;
      glyphOrigin: TD2d1Point2f; fontFace: IDWriteFontFace;
      fontEmSize: FLOAT; glyphIndex: UINT16; isSideways: BOOL;
      const worldTransform: PD2d1Matrix3x2F; dpiX: FLOAT; dpiY: FLOAT;
      out glyphTransform: TD2d1Matrix3x2F;
      out glyphImage: ID2D1Image): HResult; stdcall;
    function GetSvgGlyphImage(glyphOrigin: TD2d1Point2f;
      fontFace: IDWriteFontFace; fontEmSize: FLOAT;
      glyphIndex: UINT16; isSideways: BOOL;
      const worldTransform: PD2d1Matrix3x2F;
      defaultFillBrush: ID2D1Brush; svgGlyphStyle: ID2D1SvgGlyphStyle;
      colorPaletteIndex: UINT32;
      out glyphTransform: TD2d1Matrix3x2F;
      out glyphImage: ID2D1CommandList): HResult; stdcall;
  end;

// =========================================================================
// Section 17 -- GUID constants
// =========================================================================

const
  IID_ID2D1Factory: TGUID = '{06152247-6f50-465a-9245-118bfd3b6007}';
  IID_IDWriteFactory: TGUID = '{b859ee5a-d838-4b5b-a2e8-1adc7d93db48}';
  IID_IWICImagingFactory: TGUID = '{ec5ec8a9-c395-4314-9c77-54d7a935ff70}';
  CLSID_WICImagingFactory: TGUID = '{CACAF262-9370-4615-A13B-9F5539DA4C0A}';
  GUID_WICPixelFormat32bppPBGRA: TGUID = '{6FDDC324-4E03-4BFE-B185-3D77768DC910}';

// =========================================================================
// Section 19 -- External functions
// =========================================================================

function D2D1CreateFactory(factoryType: TD2d1FactoryType;
  const riid: TIID; const pFactoryOptions: PD2d1FactoryOptions;
  out ppIFactory: ID2D1Factory): HResult;
  stdcall; external 'd2d1.dll';

function DWriteCreateFactory(factoryType: TDwriteFactoryType;
  const iid: TIID; out factory: IUnknown): HResult;
  stdcall; external 'DWrite.dll';

implementation

end.
