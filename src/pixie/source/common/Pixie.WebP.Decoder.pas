{ Pixie.WebP.Decoder - pure-Pascal WebP (VP8 / VP8L) decoder.
  Decode-only. Output is straight-alpha BGRA. }

unit Pixie.WebP.Decoder;

{$IFDEF FPC}
  {$MODE DELPHI}{$H+}{$inline on}
{$ENDIF}
{$R-}{$Q-}

interface

// All output buffers allocated with GetMem; caller frees with FreeMem.
function WebPGetInfo(Data: PByte; DataSize: NativeUInt;
  out Width, Height: Integer): Boolean;
function WebPDecodeRGBA(Data: PByte; DataSize: NativeUInt;
  out Width, Height: Integer): PByte;
function WebPDecodeARGB(Data: PByte; DataSize: NativeUInt;
  out Width, Height: Integer): PByte;
function WebPDecodeBGRA(Data: PByte; DataSize: NativeUInt;
  out Width, Height: Integer): PByte;
function WebPDecodeRGB(Data: PByte; DataSize: NativeUInt;
  out Width, Height: Integer): PByte;
function WebPDecodeBGR(Data: PByte; DataSize: NativeUInt;
  out Width, Height: Integer): PByte;

implementation
{$POINTERMATH ON}

uses SysUtils;

// ============================================================
// TYPES
// ============================================================
type
  {$IF NOT DECLARED(PInt16)}
  PInt16  = ^Int16;
  {$IFEND}
  {$IF NOT DECLARED(PUInt32)}
  PUInt32 = ^UInt32;
  {$IFEND}
  TCSMode = (csmRGBA, csmARGB, csmBGRA, csmRGB, csmBGR);

// ============================================================
// CONSTANTS
// ============================================================
const
  BPS      = 32;                    // YUV reconstruction buffer stride
  YUV_SIZE = BPS * 17 + BPS * 9;   // = 832
  Y_OFF    = BPS * 1 + 8;           // = 40
  U_OFF    = Y_OFF + BPS * 16 + BPS * 1;  // = 584
  V_OFF    = U_OFF + 16;            // = 600

  NUM_MB_SEGMENTS       = 4;
  NUM_TYPES             = 4;
  NUM_BANDS             = 8;
  NUM_CTX               = 3;
  NUM_PROBAS            = 11;
  MB_FEATURE_TREE_PROBS = 3;
  NUM_REF_LF_DELTAS     = 4;
  NUM_MODE_LF_DELTAS    = 4;
  MAX_NUM_PARTITIONS    = 8;

  // 4x4 intra block modes
  B_DC_PRED = 0;  B_TM_PRED = 1;  B_VE_PRED = 2;  B_HE_PRED = 3;
  B_RD_PRED = 4;  B_VR_PRED = 5;  B_LD_PRED = 6;  B_VL_PRED = 7;
  B_HD_PRED = 8;  B_HU_PRED = 9;
  NUM_BMODES = 10;

  // 16x16 / UV intra modes — MUST match B_*_PRED values so that
  // I16x16 mode values stored as I4x4 top/left context use correct kBModesProba rows.
  // C: DC_PRED=B_DC_PRED=0, TM_PRED=B_TM_PRED=1, V_PRED=B_VE_PRED=2, H_PRED=B_HE_PRED=3
  DC_PRED = 0;  TM_PRED = 1;  V_PRED = 2;  H_PRED = 3;  B_PRED = 4;

  FIXED_TABLE_SIZE = 630 * 3 + 410;  // = 2300  (VP8L Huffman)

// ============================================================
// VP8 PROBABILITY / QUANTIZATION TABLES
// ============================================================
const
  CoeffsProba0: array[0..3,0..7,0..2,0..10] of Byte = (
  ((( 128,128,128,128,128,128,128,128,128,128,128),
    ( 128,128,128,128,128,128,128,128,128,128,128),
    ( 128,128,128,128,128,128,128,128,128,128,128)),
   (( 253,136,254,255,228,219,128,128,128,128,128),
    ( 189,129,242,255,227,213,255,219,128,128,128),
    ( 106,126,227,252,214,209,255,255,128,128,128)),
   ((   1, 98,248,255,236,226,255,255,128,128,128),
    ( 181,133,238,254,221,234,255,154,128,128,128),
    (  78,134,202,247,198,180,255,219,128,128,128)),
   ((   1,185,249,255,243,255,128,128,128,128,128),
    ( 184,150,247,255,236,224,128,128,128,128,128),
    (  77,110,216,255,236,230,128,128,128,128,128)),
   ((   1,101,251,255,241,255,128,128,128,128,128),
    ( 170,139,241,252,236,209,255,255,128,128,128),
    (  37,116,196,243,228,255,255,255,128,128,128)),
   ((   1,204,254,255,245,255,128,128,128,128,128),
    ( 207,160,250,255,238,128,128,128,128,128,128),
    ( 102,103,231,255,211,171,128,128,128,128,128)),
   ((   1,152,252,255,240,255,128,128,128,128,128),
    ( 177,135,243,255,234,225,128,128,128,128,128),
    (  80,129,211,255,194,224,128,128,128,128,128)),
   ((   1,  1,255,128,128,128,128,128,128,128,128),
    ( 246,  1,255,128,128,128,128,128,128,128,128),
    ( 255,128,128,128,128,128,128,128,128,128,128))),
  ((( 198, 35,237,223,193,187,162,160,145,155, 62),
    ( 131, 45,198,221,172,176,220,157,252,221,  1),
    (  68, 47,146,208,149,167,221,162,255,223,128)),
   ((   1,149,241,255,221,224,255,255,128,128,128),
    ( 184,141,234,253,222,220,255,199,128,128,128),
    (  81, 99,181,242,176,190,249,202,255,255,128)),
   ((   1,129,232,253,214,197,242,196,255,255,128),
    (  99,121,210,250,201,198,255,202,128,128,128),
    (  23, 91,163,242,170,187,247,210,255,255,128)),
   ((   1,200,246,255,234,255,128,128,128,128,128),
    ( 109,178,241,255,231,245,255,255,128,128,128),
    (  44,130,201,253,205,192,255,255,128,128,128)),
   ((   1,132,239,251,219,209,255,165,128,128,128),
    (  94,136,225,251,218,190,255,255,128,128,128),
    (  22,100,174,245,186,161,255,199,128,128,128)),
   ((   1,182,249,255,232,235,128,128,128,128,128),
    ( 124,143,241,255,227,234,128,128,128,128,128),
    (  35, 77,181,251,193,211,255,205,128,128,128)),
   ((   1,157,247,255,236,231,255,255,128,128,128),
    ( 121,141,235,255,225,227,255,255,128,128,128),
    (  45, 99,188,251,195,217,255,224,128,128,128)),
   ((   1,  1,251,255,213,255,128,128,128,128,128),
    ( 203,  1,248,255,255,128,128,128,128,128,128),
    ( 137,  1,177,255,224,255,128,128,128,128,128))),
  ((( 253,  9,248,251,207,208,255,192,128,128,128),
    ( 175, 13,224,243,193,185,249,198,255,255,128),
    (  73, 17,171,221,161,179,236,167,255,234,128)),
   ((   1, 95,247,253,212,183,255,255,128,128,128),
    ( 239, 90,244,250,211,209,255,255,128,128,128),
    ( 155, 77,195,248,188,195,255,255,128,128,128)),
   ((   1, 24,239,251,218,219,255,205,128,128,128),
    ( 201, 51,219,255,196,186,128,128,128,128,128),
    (  69, 46,190,239,201,218,255,228,128,128,128)),
   ((   1,191,251,255,255,128,128,128,128,128,128),
    ( 223,165,249,255,213,255,128,128,128,128,128),
    ( 141,124,248,255,255,128,128,128,128,128,128)),
   ((   1, 16,248,255,255,128,128,128,128,128,128),
    ( 190, 36,230,255,236,255,128,128,128,128,128),
    ( 149,  1,255,128,128,128,128,128,128,128,128)),
   ((   1,226,255,128,128,128,128,128,128,128,128),
    ( 247,192,255,128,128,128,128,128,128,128,128),
    ( 240,128,255,128,128,128,128,128,128,128,128)),
   ((   1,134,252,255,255,128,128,128,128,128,128),
    ( 213, 62,250,255,255,128,128,128,128,128,128),
    (  55, 93,255,128,128,128,128,128,128,128,128)),
   (( 128,128,128,128,128,128,128,128,128,128,128),
    ( 128,128,128,128,128,128,128,128,128,128,128),
    ( 128,128,128,128,128,128,128,128,128,128,128))),
  ((( 202, 24,213,235,186,191,220,160,240,175,255),
    ( 126, 38,182,232,169,184,228,174,255,187,128),
    (  61, 46,138,219,151,178,240,170,255,216,128)),
   ((   1,112,230,250,199,191,247,159,255,255,128),
    ( 166,109,228,252,211,215,255,174,128,128,128),
    (  39, 77,162,232,172,180,245,178,255,255,128)),
   ((   1, 52,220,246,198,199,249,220,255,255,128),
    ( 124, 74,191,243,183,193,250,221,255,255,128),
    (  24, 71,130,219,154,170,243,182,255,255,128)),
   ((   1,182,225,249,219,240,255,224,128,128,128),
    ( 149,150,226,252,216,205,255,171,128,128,128),
    (  28,108,170,242,183,194,254,223,255,255,128)),
   ((   1, 81,230,252,204,203,255,192,128,128,128),
    ( 123,102,209,247,188,196,255,233,128,128,128),
    (  20, 95,153,243,164,173,255,203,128,128,128)),
   ((   1,222,248,255,216,213,128,128,128,128,128),
    ( 168,175,246,252,235,205,255,255,128,128,128),
    (  47,116,215,255,211,212,255,255,128,128,128)),
   ((   1,121,236,253,212,214,255,255,128,128,128),
    ( 141, 84,213,252,201,202,255,219,128,128,128),
    (  42, 80,160,240,162,185,255,205,128,128,128)),
   ((   1,  1,255,128,128,128,128,128,128,128,128),
    ( 244,  1,255,128,128,128,128,128,128,128,128),
    ( 238,  1,255,128,128,128,128,128,128,128,128)))
  );

  CoeffsUpdateProba: array[0..3,0..7,0..2,0..10] of Byte = (
  (((255,255,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255)),
   ((176,246,255,255,255,255,255,255,255,255,255),
    (223,241,252,255,255,255,255,255,255,255,255),
    (249,253,253,255,255,255,255,255,255,255,255)),
   ((255,244,252,255,255,255,255,255,255,255,255),
    (234,254,254,255,255,255,255,255,255,255,255),
    (253,255,255,255,255,255,255,255,255,255,255)),
   ((255,246,254,255,255,255,255,255,255,255,255),
    (239,253,254,255,255,255,255,255,255,255,255),
    (254,255,254,255,255,255,255,255,255,255,255)),
   ((255,248,254,255,255,255,255,255,255,255,255),
    (251,255,254,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255)),
   ((255,253,254,255,255,255,255,255,255,255,255),
    (251,254,254,255,255,255,255,255,255,255,255),
    (254,255,254,255,255,255,255,255,255,255,255)),
   ((255,254,253,255,254,255,255,255,255,255,255),
    (250,255,254,255,254,255,255,255,255,255,255),
    (254,255,255,255,255,255,255,255,255,255,255)),
   ((255,255,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255))),
  (((217,255,255,255,255,255,255,255,255,255,255),
    (225,252,241,253,255,255,254,255,255,255,255),
    (234,250,241,250,253,255,253,254,255,255,255)),
   ((255,254,255,255,255,255,255,255,255,255,255),
    (223,254,254,255,255,255,255,255,255,255,255),
    (238,253,254,254,255,255,255,255,255,255,255)),
   ((255,248,254,255,255,255,255,255,255,255,255),
    (249,254,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255)),
   ((255,253,255,255,255,255,255,255,255,255,255),
    (247,254,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255)),
   ((255,253,254,255,255,255,255,255,255,255,255),
    (252,255,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255)),
   ((255,254,254,255,255,255,255,255,255,255,255),
    (253,255,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255)),
   ((255,254,253,255,255,255,255,255,255,255,255),
    (250,255,255,255,255,255,255,255,255,255,255),
    (254,255,255,255,255,255,255,255,255,255,255)),
   ((255,255,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255))),
  (((186,251,250,255,255,255,255,255,255,255,255),
    (234,251,244,254,255,255,255,255,255,255,255),
    (251,251,243,253,254,255,254,255,255,255,255)),
   ((255,253,254,255,255,255,255,255,255,255,255),
    (236,253,254,255,255,255,255,255,255,255,255),
    (251,253,253,254,254,255,255,255,255,255,255)),
   ((255,254,254,255,255,255,255,255,255,255,255),
    (254,254,254,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255)),
   ((255,254,255,255,255,255,255,255,255,255,255),
    (254,254,255,255,255,255,255,255,255,255,255),
    (254,255,255,255,255,255,255,255,255,255,255)),
   ((255,255,255,255,255,255,255,255,255,255,255),
    (254,255,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255)),
   ((255,255,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255)),
   ((255,255,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255)),
   ((255,255,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255))),
  (((248,255,255,255,255,255,255,255,255,255,255),
    (250,254,252,254,255,255,255,255,255,255,255),
    (248,254,249,253,255,255,255,255,255,255,255)),
   ((255,253,253,255,255,255,255,255,255,255,255),
    (246,253,253,255,255,255,255,255,255,255,255),
    (252,254,251,254,254,255,255,255,255,255,255)),
   ((255,254,252,255,255,255,255,255,255,255,255),
    (248,254,253,255,255,255,255,255,255,255,255),
    (253,255,254,254,255,255,255,255,255,255,255)),
   ((255,251,254,255,255,255,255,255,255,255,255),
    (245,251,254,255,255,255,255,255,255,255,255),
    (253,253,254,255,255,255,255,255,255,255,255)),
   ((255,251,253,255,255,255,255,255,255,255,255),
    (252,253,254,255,255,255,255,255,255,255,255),
    (255,254,255,255,255,255,255,255,255,255,255)),
   ((255,252,255,255,255,255,255,255,255,255,255),
    (249,255,254,255,255,255,255,255,255,255,255),
    (255,255,254,255,255,255,255,255,255,255,255)),
   ((255,255,253,255,255,255,255,255,255,255,255),
    (250,255,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255)),
   ((255,255,255,255,255,255,255,255,255,255,255),
    (254,255,255,255,255,255,255,255,255,255,255),
    (255,255,255,255,255,255,255,255,255,255,255)))
  );

  kBands: array[0..16] of Byte =
    (0,1,2,3,6,4,5,6,6,6,6,6,6,6,6,7,0);

  kBModesProba: array[0..NUM_BMODES-1,0..NUM_BMODES-1,0..NUM_BMODES-2] of Byte = (
  (( 231,120, 48, 89,115,113,120,152,112),
   ( 152,179, 64,126,170,118, 46, 70, 95),
   ( 175, 69,143, 80, 85, 82, 72,155,103),
   (  56, 58, 10,171,218,189, 17, 13,152),
   ( 114, 26, 17,163, 44,195, 21, 10,173),
   ( 121, 24, 80,195, 26, 62, 44, 64, 85),
   ( 144, 71, 10, 38,171,213,144, 34, 26),
   ( 170, 46, 55, 19,136,160, 33,206, 71),
   (  63, 20,  8,114,114,208, 12,  9,226),
   (  81, 40, 11, 96,182, 84, 29, 16, 36)),
  (( 134,183, 89,137, 98,101,106,165,148),
   (  72,187,100,130,157,111, 32, 75, 80),
   (  66,102,167, 99, 74, 62, 40,234,128),
   (  41, 53,  9,178,241,141, 26,  8,107),
   (  74, 43, 26,146, 73,166, 49, 23,157),
   (  65, 38,105,160, 51, 52, 31,115,128),
   ( 104, 79, 12, 27,217,255, 87, 17,  7),
   (  87, 68, 71, 44,114, 51, 15,186, 23),
   (  47, 41, 14,110,182,183, 21, 17,194),
   (  66, 45, 25,102,197,189, 23, 18, 22)),
  ((  88, 88,147,150, 42, 46, 45,196,205),
   (  43, 97,183,117, 85, 38, 35,179, 61),
   (  39, 53,200, 87, 26, 21, 43,232,171),
   (  56, 34, 51,104,114,102, 29, 93, 77),
   (  39, 28, 85,171, 58,165, 90, 98, 64),
   (  34, 22,116,206, 23, 34, 43,166, 73),
   ( 107, 54, 32, 26, 51,  1, 81, 43, 31),
   (  68, 25,106, 22, 64,171, 36,225,114),
   (  34, 19, 21,102,132,188, 16, 76,124),
   (  62, 18, 78, 95, 85, 57, 50, 48, 51)),
  (( 193,101, 35,159,215,111, 89, 46,111),
   (  60,148, 31,172,219,228, 21, 18,111),
   ( 112,113, 77, 85,179,255, 38,120,114),
   (  40, 42,  1,196,245,209, 10, 25,109),
   (  88, 43, 29,140,166,213, 37, 43,154),
   (  61, 63, 30,155, 67, 45, 68,  1,209),
   ( 100, 80,  8, 43,154,  1, 51, 26, 71),
   ( 142, 78, 78, 16,255,128, 34,197,171),
   (  41, 40,  5,102,211,183,  4,  1,221),
   (  51, 50, 17,168,209,192, 23, 25, 82)),
  (( 138, 31, 36,171, 27,166, 38, 44,229),
   (  67, 87, 58,169, 82,115, 26, 59,179),
   (  63, 59, 90,180, 59,166, 93, 73,154),
   (  40, 40, 21,116,143,209, 34, 39,175),
   (  47, 15, 16,183, 34,223, 49, 45,183),
   (  46, 17, 33,183,  6, 98, 15, 32,183),
   (  57, 46, 22, 24,128,  1, 54, 17, 37),
   (  65, 32, 73,115, 28,128, 23,128,205),
   (  40,  3,  9,115, 51,192, 18,  6,223),
   (  87, 37,  9,115, 59, 77, 64, 21, 47)),
  (( 104, 55, 44,218,  9, 54, 53,130,226),
   (  64, 90, 70,205, 40, 41, 23, 26, 57),
   (  54, 57,112,184,  5, 41, 38,166,213),
   (  30, 34, 26,133,152,116, 10, 32,134),
   (  39, 19, 53,221, 26,114, 32, 73,255),
   (  31,  9, 65,234,  2, 15,  1,118, 73),
   (  75, 32, 12, 51,192,255,160, 43, 51),
   (  88, 31, 35, 67,102, 85, 55,186, 85),
   (  56, 21, 23,111, 59,205, 45, 37,192),
   (  55, 38, 70,124, 73,102,  1, 34, 98)),
  (( 125, 98, 42, 88,104, 85,117,175, 82),
   (  95, 84, 53, 89,128,100,113,101, 45),
   (  75, 79,123, 47, 51,128, 81,171,  1),
   (  57, 17,  5, 71,102, 57, 53, 41, 49),
   (  38, 33, 13,121, 57, 73, 26,  1, 85),
   (  41, 10, 67,138, 77,110, 90, 47,114),
   ( 115, 21,  2, 10,102,255,166, 23,  6),
   ( 101, 29, 16, 10, 85,128,101,196, 26),
   (  57, 18, 10,102,102,213, 34, 20, 43),
   ( 117, 20, 15, 36,163,128, 68,  1, 26)),
  (( 102, 61, 71, 37, 34, 53, 31,243,192),
   (  69, 60, 71, 38, 73,119, 28,222, 37),
   (  68, 45,128, 34,  1, 47, 11,245,171),
   (  62, 17, 19, 70,146, 85, 55, 62, 70),
   (  37, 43, 37,154,100,163, 85,160,  1),
   (  63,  9, 92,136, 28, 64, 32,201, 85),
   (  75, 15,  9,  9, 64,255,184,119, 16),
   (  86,  6, 28,  5, 64,255, 25,248,  1),
   (  56,  8, 17,132,137,255, 55,116,128),
   (  58, 15, 20, 82,135, 57, 26,121, 40)),
  (( 164, 50, 31,137,154,133, 25, 35,218),
   (  51,103, 44,131,131,123, 31,  6,158),
   (  86, 40, 64,135,148,224, 45,183,128),
   (  22, 26, 17,131,240,154, 14,  1,209),
   (  45, 16, 21, 91, 64,222,  7,  1,197),
   (  56, 21, 39,155, 60,138, 23,102,213),
   (  83, 12, 13, 54,192,255, 68, 47, 28),
   (  85, 26, 85, 85,128,128, 32,146,171),
   (  18, 11,  7, 63,144,171,  4,  4,246),
   (  35, 27, 10,146,174,171, 12, 26,128)),
  (( 190, 80, 35, 99,180, 80,126, 54, 45),
   (  85,126, 47, 87,176, 51, 41, 20, 32),
   ( 101, 75,128,139,118,146,116,128, 85),
   (  56, 41, 15,176,236, 85, 37,  9, 62),
   (  71, 30, 17,119,118,255, 17, 18,138),
   ( 101, 38, 60,138, 55, 70, 43, 26,142),
   ( 146, 36, 19, 30,171,255, 97, 27, 20),
   ( 138, 45, 61, 62,219,  1, 81,188, 64),
   (  32, 41, 20,117,151,142, 20, 21,163),
   ( 112, 19, 12, 61,195,128, 48,  4, 24))
  );

  kDcTable: array[0..127] of Byte = (
    4,  5,  6,  7,  8,  9, 10, 10,
   11, 12, 13, 14, 15, 16, 17, 17,
   18, 19, 20, 20, 21, 21, 22, 22,
   23, 23, 24, 25, 25, 26, 27, 28,
   29, 30, 31, 32, 33, 34, 35, 36,
   37, 37, 38, 39, 40, 41, 42, 43,
   44, 45, 46, 46, 47, 48, 49, 50,
   51, 52, 53, 54, 55, 56, 57, 58,
   59, 60, 61, 62, 63, 64, 65, 66,
   67, 68, 69, 70, 71, 72, 73, 74,
   75, 76, 76, 77, 78, 79, 80, 81,
   82, 83, 84, 85, 86, 87, 88, 89,
   91, 93, 95, 96, 98,100,101,102,
  104,106,108,110,112,114,116,118,
  122,124,126,128,130,132,134,136,
  138,140,143,145,148,151,154,157);

  kAcTable: array[0..127] of Word = (
    4,  5,  6,  7,  8,  9, 10, 11,
   12, 13, 14, 15, 16, 17, 18, 19,
   20, 21, 22, 23, 24, 25, 26, 27,
   28, 29, 30, 31, 32, 33, 34, 35,
   36, 37, 38, 39, 40, 41, 42, 43,
   44, 45, 46, 47, 48, 49, 50, 51,
   52, 53, 54, 55, 56, 57, 58, 60,
   62, 64, 66, 68, 70, 72, 74, 76,
   78, 80, 82, 84, 86, 88, 90, 92,
   94, 96, 98,100,102,104,106,108,
  110,112,114,116,119,122,125,128,
  131,134,137,140,143,146,149,152,
  155,158,161,164,167,170,173,177,
  181,185,189,193,197,201,205,209,
  213,217,221,225,229,234,239,245,
  249,254,259,264,269,274,279,284);

  // Zigzag scan order for 4x4 block
  kZigzag: array[0..15] of Byte =
    (0,1,4,8, 5,2,3,6, 9,12,13,10, 7,11,14,15);

  // Byte offsets of each 4x4 sub-block in the YUV reconstruction buffer
  // BPS=32; sub-block row i starts at i*4*BPS = i*128
  kScan: array[0..15] of Integer = (
      0,  4,  8, 12,
    128,132,136,140,
    256,260,264,268,
    384,388,392,396);

  // Category probability tables for large residual values
  kCat3: array[0..3] of Byte = (173,148,140,  0);
  kCat4: array[0..4] of Byte = (176,155,140,135,  0);
  kCat5: array[0..5] of Byte = (180,157,141,134,130,  0);
  kCat6: array[0..11] of Byte = (254,254,243,230,196,177,153,140,133,130,129,0);

  // VP8L distance-to-plane offset table (kCodeToPlane[120])
  kCodeToPlane: array[0..119] of Integer = (
    $18,  $07,  $17,  $19,  $28,  $06,  $27,  $29,
    $16,  $1a,  $26,  $2a,  $38,  $05,  $37,  $39,
    $15,  $1b,  $36,  $3a,  $25,  $2b,  $48,  $04,
    $47,  $49,  $14,  $1c,  $35,  $3b,  $46,  $4a,
    $24,  $2c,  $58,  $45,  $4b,  $34,  $3c,  $03,
    $57,  $59,  $13,  $1d,  $56,  $5a,  $23,  $2d,
    $44,  $4c,  $55,  $5b,  $33,  $3d,  $68,  $02,
    $67,  $69,  $12,  $1e,  $66,  $6a,  $22,  $2e,
    $54,  $5c,  $43,  $4d,  $65,  $6b,  $32,  $3e,
    $78,  $01,  $77,  $79,  $53,  $5d,  $11,  $1f,
    $64,  $6c,  $42,  $4e,  $76,  $7a,  $21,  $2f,
    $75,  $7b,  $31,  $3f,  $63,  $6d,  $52,  $5e,
    $00,  $74,  $7c,  $41,  $4f,  $10,  $20,  $62,
    $6e,  $30,  $73,  $7d,  $51,  $5f,  $40,  $72,
    $7e,  $61,  $6f,  $50,  $71,  $7f,  $60,  $70);

  // Huffman code length reorder for VP8L canonical codes
  kCodeLengthCodeOrder: array[0..18] of Byte =
    (17,18,0,1,2,3,4,5,16,6,7,8,9,10,11,12,13,14,15);

  // Alphabet sizes for the 5 Huffman code groups in VP8L
  kAlphabetSize: array[0..4] of Integer = (280, 256, 256, 256, 40);

// ============================================================
// RECORD TYPES  (after consts so sizes are known)
// ============================================================
type
  TVP8BandProbas = record
    Probas: array[0..NUM_CTX-1, 0..NUM_PROBAS-1] of Byte;
  end;

  // One row of band-pointers (17 entries: bands 0..16, with kBands mapping)
  TBandPtrsRow = array[0..16] of ^TVP8BandProbas;

  TVP8Proba = record
    Bands:    array[0..NUM_TYPES-1, 0..NUM_BANDS-1] of TVP8BandProbas;
    BandsPtr: array[0..NUM_TYPES-1] of TBandPtrsRow;
  end;

  TVP8QuantMatrix = record
    Y1Mat:   array[0..1] of Integer;
    Y2Mat:   array[0..1] of Integer;
    UVMat:   array[0..1] of Integer;
    UVQuant: Integer;
  end;

  TVP8SegmentHeader = record
    UseSegment:    Boolean;
    UpdateMap:     Boolean;
    AbsoluteDelta: Boolean;
    Quantizer:     array[0..NUM_MB_SEGMENTS-1] of Integer;
    FilterStrength:array[0..NUM_MB_SEGMENTS-1] of Integer;
    SegProbs:      array[0..MB_FEATURE_TREE_PROBS-1] of Byte; // segment map probs
  end;

  TVP8MB = record
    NZ:   Byte;   // non-zero AC flags (Y0..Y3, U0,U1, V0,V1)
    NZDC: Byte;   // non-zero DC flags
  end;
  PVP8MB = ^TVP8MB;

  TVP8MBData = record
    Coeffs:   array[0..383] of Int16;  // 24 blocks * 16 = 384
    IsI4x4:   Boolean;
    IModes:   array[0..15] of Byte;    // per-4x4-block modes
    UVMode:   Byte;
    NonZeroY: Cardinal;
    NonZeroUV:Cardinal;
    Skip:     Boolean;
    Segment:  Byte;
  end;
  PVP8MBData = ^TVP8MBData;

  // Huffman code entry used by VP8L
  THuffmanCode = record
    Bits:  Byte;   // code length (0 = invalid)
    Value: Word;   // symbol value
  end;
  PHuffmanCode = ^THuffmanCode;

  THuffmanCode32 = record
    Bits:  Byte;
    Value: Cardinal;
  end;

// ============================================================
// HELPER FUNCTIONS
// ============================================================

// Arithmetic right shift by n bits (FPC's shr is logical/unsigned).
// Equivalent to C's (v >> n) for signed int32.
// Uses the identity: sar(v,n) = ~(~v >> n) for negative v, v>>n for positive v.
function SarI(v, n: Integer): Integer; inline;
begin
  if v >= 0 then Result := v shr n
  else Result := not (not v shr n);
end;

function Clip8b(v: Integer): Byte; inline;
begin
  if v < 0 then Result := 0
  else if v > 255 then Result := 255
  else Result := Byte(v);
end;

function ClipMax(v, M: Integer): Integer; inline;
begin
  if v < 0 then Result := 0
  else if v > M then Result := M
  else Result := v;
end;

// YUV → RGB conversion (fixed-point coefficients).
function MultHi(v, c: Integer): Integer; inline;
begin
  Result := (v * c) shr 8;
end;

function VP8Clip8(v: Integer): Byte; inline;
// YUV_FIX2=6, YUV_MASK2=$3FFF
begin
  if (v and (not $3FFF)) = 0 then
    Result := Byte(v shr 6)
  else if v < 0 then
    Result := 0
  else
    Result := 255;
end;

function YuvToR(y, v: Integer): Byte; inline;
begin
  Result := VP8Clip8(MultHi(y, 19077) + MultHi(v, 26149) - 14234);
end;

function YuvToG(y, u, v: Integer): Byte; inline;
begin
  Result := VP8Clip8(MultHi(y, 19077) - MultHi(u, 6419) - MultHi(v, 13320) + 8708);
end;

function YuvToB(y, u: Integer): Byte; inline;
begin
  Result := VP8Clip8(MultHi(y, 19077) + MultHi(u, 33050) - 17685);
end;

// ============================================================
// VP8L BIT READER  (LSB-first, 64-bit accumulator)
// ============================================================
type
  TVP8LBitReader = record
    Val:       UInt64;
    Available: Integer;
    Buf:       PByte;
    BufEnd:    PByte;
    Eos:       Boolean;
  end;

procedure VP8LFillBitWindow(var BR: TVP8LBitReader); inline;
begin
  while (BR.Available <= 56) and (BR.Buf < BR.BufEnd) do
  begin
    BR.Val := BR.Val or (UInt64(BR.Buf^) shl BR.Available);
    Inc(BR.Buf);
    Inc(BR.Available, 8);
  end;
  if (BR.Buf >= BR.BufEnd) and (BR.Available < 0) then
    BR.Eos := True;
end;

procedure VP8LInitBitReader(var BR: TVP8LBitReader; Data: PByte; Size: NativeUInt);
begin
  BR.Val       := 0;
  BR.Available := 0;
  BR.Buf       := Data;
  BR.BufEnd    := Data + Size;
  BR.Eos       := (Size = 0);
  VP8LFillBitWindow(BR);
end;

function VP8LReadBits(var BR: TVP8LBitReader; N: Integer): Cardinal; inline;
begin
  if N = 0 then begin Result := 0; Exit; end;
  Result := Cardinal(BR.Val) and Cardinal((UInt64(1) shl N) - 1);
  BR.Val := BR.Val shr N;
  Dec(BR.Available, N);
  if BR.Available <= 32 then VP8LFillBitWindow(BR);
end;

// ============================================================
// VP8 BOOLEAN BIT READER  (MSB-first, range coder)
//   range starts at 254; split = (range * prob) >> 8
// ============================================================
type
  TVP8Rd = record
    Val:    UInt64;   // accumulated bit window
    Range:  UInt32;   // current range [127..254]
    Bits:   Integer;  // valid bits in Val (>= 0)
    Buf:    PByte;
    BufEnd: PByte;
    Eof:    Boolean;
  end;

procedure VP8RdLoadByte(var R: TVP8Rd); inline;
begin
  if R.Buf < R.BufEnd then
  begin
    R.Val := (R.Val shl 8) or R.Buf^;
    Inc(R.Buf);
  end else
  begin
    R.Eof := True;
    R.Val := R.Val shl 8;
  end;
  Inc(R.Bits, 8);
end;

procedure VP8RdInit(var R: TVP8Rd; Data: PByte; Size: NativeUInt);
begin
  R.Val    := 0;
  R.Range  := 254;
  R.Bits   := -8;
  R.Buf    := Data;
  R.BufEnd := Data + Size;
  R.Eof    := (Size = 0);
  VP8RdLoadByte(R);   // Bits = 0 after this
end;

function VP8RdGetBit(var R: TVP8Rd; Prob: Integer): Integer; inline;
var
  split: UInt32;
begin
  if R.Bits < 0 then VP8RdLoadByte(R);
  split := (R.Range * UInt32(Prob)) shr 8;
  if (R.Val shr R.Bits) > split then
  begin
    Dec(R.Range, split + 1);
    Dec(R.Val, UInt64(split + 1) shl R.Bits);
    Result := 1;
  end else
  begin
    R.Range := split;
    Result := 0;
  end;
  // Normalize: keep Range in [127..254]
  while R.Range < 127 do
  begin
    R.Range := R.Range * 2 + 1;
    Dec(R.Bits);
    if R.Bits < 0 then
      VP8RdLoadByte(R);
  end;
end;

function VP8RdGet(var R: TVP8Rd): Integer; inline;
begin
  Result := VP8RdGetBit(R, 128);
end;

// Specialized signed-value read: returns v if sign=0, -v if sign=1.
//   Uses prob=128 with a simplified update: unlike VP8RdGetBit(128) it does NOT
//   normalize Range afterward; it unconditionally decrements Bits by 1 and sets
//   Range |= 1. The two diverge only for Range=254 with sign=0:
//     VP8RdGetBit gives Range=127, Bits unchanged;
//     VP8RdGetSigned gives Range=255, Bits-=1.
function VP8RdGetSigned(var R: TVP8Rd; v: Integer): Integer; inline;
var
  pos: Integer;
  split, value: UInt32;
  mask: Integer;
begin
  if R.Bits < 0 then VP8RdLoadByte(R);
  pos   := R.Bits;                              // save original Bits position
  split := R.Range shr 1;
  value := UInt32(R.Val shr pos);
  // SarI: arithmetic right shift gives 0 or -1 (FPC shr is logical → wrong)
  mask  := SarI(Integer(split) - Integer(value), 31);
  R.Bits := pos - 1;                            // decrement by 1 (may become -1)
  Inc(R.Range, UInt32(mask));                   // range-1 if bit=1 (mask=-1), range if bit=0
  R.Range := R.Range or 1;                      // always ensure lowest bit set
  Dec(R.Val, UInt64((split + 1) and UInt32(mask)) shl pos);  // use original pos, not decremented
  Result := (v xor mask) - mask;                // v if mask=0, -v if mask=-1
end;

function VP8RdGetValue(var R: TVP8Rd; N: Integer): Cardinal; inline;
var i: Integer;
begin
  Result := 0;
  for i := N - 1 downto 0 do
    if VP8RdGetBit(R, 128) <> 0 then
      Result := Result or (Cardinal(1) shl i);
end;

function VP8RdGetSignedValue(var R: TVP8Rd; N: Integer): Integer; inline;
var v: Cardinal;
begin
  v := VP8RdGetValue(R, N);
  if VP8RdGetBit(R, 128) <> 0 then
    Result := -Integer(v)
  else
    Result := Integer(v);
end;

// ============================================================
// VP8L HUFFMAN TABLE BUILDER
// ============================================================
const
  HUFFMAN_TABLE_BITS    = 8;                              // root table bits
  HUFFMAN_TABLE_MASK    = (1 shl HUFFMAN_TABLE_BITS) - 1;
  MAX_ALLOWED_CODE_LEN  = 15;

// Build a 2-level canonical Huffman lookup table. The first 1<<RootBits entries
// are the root table; entries whose code is longer than RootBits point at a secondary
// table appended directly after. Tables are laid out consecutively so a
// caller can place several of them in one buffer. Returns the total number of
// THuffmanCode entries written, or 0 on error. Sorted is scratch space of at
// least CodeLengthsSize Words.
function GetNextKey(Key, Len: Integer): Integer; inline;
var Step: Integer;
begin
  Step := 1 shl (Len - 1);
  while (Key and Step) <> 0 do Step := Step shr 1;
  if Step <> 0 then Result := (Key and (Step - 1)) + Step
  else Result := Key;
end;

procedure ReplicateValue(Table: PHuffmanCode; Step, Last: Integer;
  const Code: THuffmanCode); inline;
begin
  repeat
    Dec(Last, Step);
    Table[Last] := Code;
  until Last <= 0;
end;

function NextTableBitSize(const Count: array of Integer;
  Len, RootBits: Integer): Integer;
var Left: Integer;
begin
  Left := 1 shl (Len - RootBits);
  while Len < MAX_ALLOWED_CODE_LEN do
  begin
    Dec(Left, Count[Len]);
    if Left <= 0 then Break;
    Inc(Len);
    Left := Left shl 1;
  end;
  Result := Len - RootBits;
end;

function VP8LBuildHuffmanTable(RootTable: PHuffmanCode; RootBits: Integer;
  CodeLengths: PInteger; CodeLengthsSize: Integer;
  Sorted: PWord): Integer;
var
  Table:                      PHuffmanCode;
  TotalSize, Len, Symbol:     Integer;
  Count:                      array[0..MAX_ALLOWED_CODE_LEN] of Integer;
  Offset:                     array[0..MAX_ALLOWED_CODE_LEN] of Integer;
  Step, Low, Mask, Key:       Integer;
  TableBits, TableSize:       Integer;
  NumOpen:                    Integer;
  Code:                       THuffmanCode;
begin
  Result := 0;
  Table := RootTable;
  TotalSize := 1 shl RootBits;
  FillChar(Count, SizeOf(Count), 0);
  for Symbol := 0 to CodeLengthsSize - 1 do
  begin
    if CodeLengths[Symbol] > MAX_ALLOWED_CODE_LEN then Exit;
    Inc(Count[CodeLengths[Symbol]]);
  end;
  if Count[0] = CodeLengthsSize then Exit;     // all lengths zero
  // Generate offsets into the sorted symbol table, by code length.
  Offset[1] := 0;
  for Len := 1 to MAX_ALLOWED_CODE_LEN - 1 do
  begin
    if Count[Len] > (1 shl Len) then Exit;
    Offset[Len + 1] := Offset[Len] + Count[Len];
  end;
  // Sort symbols by length, then by symbol order within each length.
  for Symbol := 0 to CodeLengthsSize - 1 do
  begin
    Len := CodeLengths[Symbol];
    if Len > 0 then
    begin
      Sorted[Offset[Len]] := Word(Symbol);
      Inc(Offset[Len]);
    end;
  end;
  // Special case: only one symbol -> a zero-length code that consumes nothing.
  if Offset[MAX_ALLOWED_CODE_LEN] = 1 then
  begin
    Code.Bits  := 0;
    Code.Value := Sorted[0];
    ReplicateValue(@Table[0], 1, TotalSize, Code);
    Result := TotalSize;
    Exit;
  end;

  Low      := -1;
  Mask     := TotalSize - 1;
  Key      := 0;
  NumOpen  := 1 shl RootBits;
  TableBits := RootBits;
  TableSize := 1 shl TableBits;
  Symbol   := 0;
  // Fill the root table.
  Len := 1; Step := 2;
  while Len <= RootBits do
  begin
    NumOpen := NumOpen shl 1;
    Dec(NumOpen, Count[Len]);
    if NumOpen < 0 then Exit;
    while Count[Len] > 0 do
    begin
      Code.Bits  := Byte(Len);
      Code.Value := Sorted[Symbol]; Inc(Symbol);
      ReplicateValue(@Table[Key], Step, TableSize, Code);
      Key := GetNextKey(Key, Len);
      Dec(Count[Len]);
    end;
    Inc(Len); Step := Step shl 1;
  end;
  // Fill the 2nd-level tables and add the pointer entries to the root table.
  Len := RootBits + 1; Step := 2;
  while Len <= MAX_ALLOWED_CODE_LEN do
  begin
    NumOpen := NumOpen shl 1;
    Dec(NumOpen, Count[Len]);
    if NumOpen < 0 then Exit;
    while Count[Len] > 0 do
    begin
      if (Key and Mask) <> Low then
      begin
        Inc(Table, TableSize);
        TableBits := NextTableBitSize(Count, Len, RootBits);
        TableSize := 1 shl TableBits;
        Inc(TotalSize, TableSize);
        Low := Key and Mask;
        RootTable[Low].Bits  := Byte(TableBits + RootBits);
        RootTable[Low].Value := Word((Table - RootTable) - Low);
      end;
      Code.Bits  := Byte(Len - RootBits);
      Code.Value := Sorted[Symbol]; Inc(Symbol);
      ReplicateValue(@Table[Key shr RootBits], Step, TableSize, Code);
      Key := GetNextKey(Key, Len);
      Dec(Count[Len]);
    end;
    Inc(Len); Step := Step shl 1;
  end;
  Result := TotalSize;
end;

// Read one symbol via a 2-level table.
function VP8LReadSymbol(Table: PHuffmanCode; var BR: TVP8LBitReader): Integer; inline;
var
  Val:   Cardinal;
  NBits: Integer;
begin
  if BR.Available < HUFFMAN_TABLE_BITS + MAX_ALLOWED_CODE_LEN then
    VP8LFillBitWindow(BR);
  Val := Cardinal(BR.Val) and HUFFMAN_TABLE_MASK;
  Inc(Table, Val);
  NBits := Integer(Table^.Bits) - HUFFMAN_TABLE_BITS;
  if NBits > 0 then
  begin
    BR.Val := BR.Val shr HUFFMAN_TABLE_BITS;
    Dec(BR.Available, HUFFMAN_TABLE_BITS);
    Val := Cardinal(BR.Val) and ((Cardinal(1) shl NBits) - 1);
    Inc(Table, Integer(Table^.Value) + Integer(Val));
  end;
  BR.Val := BR.Val shr Table^.Bits;
  Dec(BR.Available, Table^.Bits);
  // Keep the invariant that every read leaves >32 bits buffered, so a
  // following VP8LReadBits (which doesn't pre-check) always has enough.
  if BR.Available <= 32 then VP8LFillBitWindow(BR);
  Result := Integer(Table^.Value);
end;

// ============================================================
// DECODER DATA TYPES
// ============================================================
type
  TVP8FInfo = record
    FLimit:  Integer;   // edge limit (2*level + ilevel); 0 => no filtering
    FILevel: Integer;   // interior limit
    FHev:    Integer;   // high-edge-variance threshold
    FInner:  Boolean;   // also filter the inner 4x4 edges
  end;
  PVP8FInfo = ^TVP8FInfo;

  TVP8Decoder = record
    // Main bitreader (partition 0)
    BR:          TVP8Rd;
    // AC residual partition readers
    Parts:       array[0..MAX_NUM_PARTITIONS-1] of TVP8Rd;
    NumParts:    Integer;

    // Picture dimensions
    PicWidth:    Integer;
    PicHeight:   Integer;
    MbW:         Integer;   // macroblock columns
    MbH:         Integer;   // macroblock rows

    // Headers
    KeyFrame:    Boolean;
    Profile:     Integer;
    PartLen0:    Integer;   // partition 0 byte length

    // Segment
    SegHdr:      TVP8SegmentHeader;
    // Quantization matrices (one per segment)
    DQM:         array[0..NUM_MB_SEGMENTS-1] of TVP8QuantMatrix;
    // Probability tables
    Proba:       TVP8Proba;

    // Filter (skipped — just store for parsing)
    FilterSimple:   Boolean;
    FilterLevel:    Integer;
    FilterSharpness:Integer;
    UseLFDelta:     Boolean;
    RefLFDelta:     array[0..NUM_REF_LF_DELTAS-1] of Integer;
    ModeLFDelta:    array[0..NUM_MODE_LF_DELTAS-1] of Integer;

    // Decoded output row (YUV → RGB, written row by row)
    OutputMode:  TCSMode;
    OutStride:   Integer;   // bytes per output row
    OutBpp:      Integer;   // bytes per pixel

    // YUV reconstruction buffer for current MB row
    YuvBuf:      array[0..YUV_SIZE-1] of Byte;
    // Top context rows for inter-MB prediction
    YTopBuf:     PByte;   // MbW*16 bytes  (Y top row)
    UTopBuf:     PByte;   // MbW*8 bytes
    VTopBuf:     PByte;   // MbW*8 bytes
    // Per-MB NZ info (MbW+1, index 0 = left border)
    MBInfo:      PVP8MB;
    // Current MB working data
    MBData:      TVP8MBData;
    // Skip probability
    UseSkipProba: Boolean;
    SkipP:        Byte;
    // I4x4 intra-mode context
    IntraT:       PByte;          // MbW*4 bytes: top 4x4 mode per column
    IntraL:       array[0..3] of Byte;  // left 4x4 mode per row
    // Full-frame reconstruction planes (MB-padded) for loop filter + RGB convert
    YPlane:      PByte;
    UPlane:      PByte;
    VPlane:      PByte;
    YStride:     Integer;
    UVStride:    Integer;
    // Loop filter
    FilterType:  Integer;        // 0 = none, 1 = simple, 2 = normal
    FInfo:       PVP8FInfo;       // per-MB filter strength [MbW*MbH]
    // Final output buffer
    OutBuf:      PByte;
  end;

// ============================================================
// VP8 HEADER PARSING
// ============================================================

procedure VP8ParseSegmentHeader(var BR: TVP8Rd; var Hdr: TVP8SegmentHeader);
var i: Integer;
begin
  Hdr.UseSegment := VP8RdGet(BR) <> 0;
  if not Hdr.UseSegment then
  begin
    Hdr.UpdateMap := False;
    Exit;
  end;
  Hdr.UpdateMap := VP8RdGet(BR) <> 0;
  // update_data flag is separate from update_map
  if VP8RdGet(BR) <> 0 then   // update data?
  begin
    Hdr.AbsoluteDelta := VP8RdGet(BR) <> 0; // 1=absolute, 0=delta (matches C absolute_delta)
    for i := 0 to NUM_MB_SEGMENTS-1 do
      if VP8RdGet(BR) <> 0 then
        Hdr.Quantizer[i] := VP8RdGetSignedValue(BR, 7)
      else
        Hdr.Quantizer[i] := 0;
    for i := 0 to NUM_MB_SEGMENTS-1 do
      if VP8RdGet(BR) <> 0 then
        Hdr.FilterStrength[i] := VP8RdGetSignedValue(BR, 6)
      else
        Hdr.FilterStrength[i] := 0;
  end;
  if Hdr.UpdateMap then
  begin
    for i := 0 to MB_FEATURE_TREE_PROBS-1 do
      if VP8RdGet(BR) <> 0 then
        Hdr.SegProbs[i] := Byte(VP8RdGetValue(BR, 8))
      else
        Hdr.SegProbs[i] := 255;
  end;
end;

procedure VP8ParseFilterHeader(var BR: TVP8Rd; var D: TVP8Decoder);
var i: Integer;
begin
  D.FilterSimple    := VP8RdGet(BR) <> 0;
  D.FilterLevel     := Integer(VP8RdGetValue(BR, 6));
  D.FilterSharpness := Integer(VP8RdGetValue(BR, 3));
  D.UseLFDelta      := VP8RdGet(BR) <> 0;
  if D.UseLFDelta and (VP8RdGet(BR) <> 0) then
  begin
    for i := 0 to NUM_REF_LF_DELTAS-1 do
      if VP8RdGet(BR) <> 0 then
        D.RefLFDelta[i] := VP8RdGetSignedValue(BR, 6);
    for i := 0 to NUM_MODE_LF_DELTAS-1 do
      if VP8RdGet(BR) <> 0 then
        D.ModeLFDelta[i] := VP8RdGetSignedValue(BR, 6);
  end;
end;

// Clip helper used in VP8ParseQuant
function QClip(v, M: Integer): Integer; inline;
begin
  if v < 0 then Result := 0
  else if v > M then Result := M
  else Result := v;
end;

procedure VP8ParseQuant(var BR: TVP8Rd; var D: TVP8Decoder);
var
  base_q0: Integer;
  dqy1_dc, dqy2_dc, dqy2_ac, dquv_dc, dquv_ac: Integer;
  i, q: Integer;
  m: ^TVP8QuantMatrix;
begin
  base_q0 := Integer(VP8RdGetValue(BR, 7));
  if VP8RdGet(BR) <> 0 then dqy1_dc  := VP8RdGetSignedValue(BR, 4) else dqy1_dc  := 0;
  if VP8RdGet(BR) <> 0 then dqy2_dc  := VP8RdGetSignedValue(BR, 4) else dqy2_dc  := 0;
  if VP8RdGet(BR) <> 0 then dqy2_ac  := VP8RdGetSignedValue(BR, 4) else dqy2_ac  := 0;
  if VP8RdGet(BR) <> 0 then dquv_dc  := VP8RdGetSignedValue(BR, 4) else dquv_dc  := 0;
  if VP8RdGet(BR) <> 0 then dquv_ac  := VP8RdGetSignedValue(BR, 4) else dquv_ac  := 0;
  for i := 0 to NUM_MB_SEGMENTS-1 do
  begin
    if D.SegHdr.UseSegment then
    begin
      q := D.SegHdr.Quantizer[i];
      if not D.SegHdr.AbsoluteDelta then Inc(q, base_q0);
    end else
    begin
      if i > 0 then begin D.DQM[i] := D.DQM[0]; Continue; end;
      q := base_q0;
    end;
    m := @D.DQM[i];
    m^.Y1Mat[0] := kDcTable[QClip(q + dqy1_dc, 127)];
    m^.Y1Mat[1] := kAcTable[QClip(q,           127)];
    m^.Y2Mat[0] := kDcTable[QClip(q + dqy2_dc, 127)] * 2;
    m^.Y2Mat[1] := (Integer(kAcTable[QClip(q + dqy2_ac, 127)]) * 101581) shr 16;
    if m^.Y2Mat[1] < 8 then m^.Y2Mat[1] := 8;
    m^.UVMat[0] := kDcTable[QClip(q + dquv_dc, 117)];   // max 117!
    m^.UVMat[1] := kAcTable[QClip(q + dquv_ac, 127)];
    m^.UVQuant  := q + dquv_ac;
  end;
end;

procedure VP8ParseProba(var BR: TVP8Rd; var D: TVP8Decoder);
var t, b, ctx, p: Integer;
begin
  // Copy defaults
  for t := 0 to NUM_TYPES-1 do
    for b := 0 to NUM_BANDS-1 do
      for ctx := 0 to NUM_CTX-1 do
        for p := 0 to NUM_PROBAS-1 do
          D.Proba.Bands[t,b].Probas[ctx,p] := CoeffsProba0[t,b,ctx,p];
  // Read updates
  for t := 0 to NUM_TYPES-1 do
    for b := 0 to NUM_BANDS-1 do
      for ctx := 0 to NUM_CTX-1 do
        for p := 0 to NUM_PROBAS-1 do
          if VP8RdGetBit(BR, CoeffsUpdateProba[t,b,ctx,p]) <> 0 then
            D.Proba.Bands[t,b].Probas[ctx,p] := Byte(VP8RdGetValue(BR, 8));
  // Build BandsPtr: BandsPtr[t][b] = @Bands[t][kBands[b]]
  for t := 0 to NUM_TYPES-1 do
    for b := 0 to 16 do
      D.Proba.BandsPtr[t][b] := @D.Proba.Bands[t, kBands[b]];
  // Skip probability (Paragraph 9.11)
  D.UseSkipProba := VP8RdGet(BR) <> 0;
  if D.UseSkipProba then
    D.SkipP := Byte(VP8RdGetValue(BR, 8));
end;

// ============================================================
// VP8 INTRA MODE PARSING
// ============================================================

function ParseIntra16Mode(var BR: TVP8Rd): Integer; inline;
begin
  // bit(156)? (bit(128)?TM:H) : (bit(163)?V:DC)
  if VP8RdGetBit(BR, 156) <> 0 then
  begin
    if VP8RdGetBit(BR, 128) <> 0 then Result := TM_PRED else Result := H_PRED;
  end else
  begin
    if VP8RdGetBit(BR, 163) <> 0 then Result := V_PRED else Result := DC_PRED;
  end;
end;

function ParseUVMode(var BR: TVP8Rd): Integer; inline;
begin
  if VP8RdGetBit(BR, 142) = 0 then Result := DC_PRED
  else if VP8RdGetBit(BR, 114) = 0 then Result := V_PRED
  else if VP8RdGetBit(BR, 183) <> 0 then Result := TM_PRED
  else Result := H_PRED;
end;

function ParseIntra4x4Mode(var BR: TVP8Rd;
  const Prob: array of Byte): Integer;
// Prob is kBModesProba[topMode][leftMode]
begin
  if VP8RdGetBit(BR, Prob[0]) = 0 then begin Result := B_DC_PRED; Exit; end;
  if VP8RdGetBit(BR, Prob[1]) = 0 then begin Result := B_TM_PRED; Exit; end;
  if VP8RdGetBit(BR, Prob[2]) = 0 then begin Result := B_VE_PRED; Exit; end;
  if VP8RdGetBit(BR, Prob[3]) = 0 then
  begin
    if VP8RdGetBit(BR, Prob[4]) = 0 then begin Result := B_HE_PRED; Exit; end;
    if VP8RdGetBit(BR, Prob[5]) = 0 then begin Result := B_RD_PRED; Exit; end;
    Result := B_VR_PRED;
  end else
  begin
    if VP8RdGetBit(BR, Prob[6]) = 0 then begin Result := B_LD_PRED; Exit; end;
    if VP8RdGetBit(BR, Prob[7]) = 0 then begin Result := B_VL_PRED; Exit; end;
    if VP8RdGetBit(BR, Prob[8]) = 0 then begin Result := B_HD_PRED; Exit; end;
    Result := B_HU_PRED;
  end;
end;

// ============================================================
// VP8 RESIDUAL COEFFICIENT DECODING
// ============================================================

// Decode residual coefficients for one 4x4 block.
// Matches C GetCoeffsFast exactly:
//   p[0]=EOB check, p[1]=zero/nonzero, p[2..]=value decode
//   BandsPtr[n] already incorporates kBands mapping (DO NOT apply kBands again)
// Returns position of last non-zero coeff + 1 (i.e. 0 = all-zero)
function VP8GetCoeffsFast(var BR: TVP8Rd;
  const BandsPtr: TBandPtrsRow;
  StartCtx, First: Integer;
  Dq0, Dq1: Integer;
  Coeffs: PInt16): Integer;
var
  n, v: Integer;
  p: PByte;  // points to BandsPtr[n]^.Probas[ctx, 0]
  tab: PByte;
  bit1, bit0, cat: Integer;
begin
  // p points to the 11-byte probability row for (position n, context ctx)
  // p[0]=EOB  p[1]=zero  p[2]=v>1  p[3..]=value
  n := First;
  p := @(BandsPtr[n]^.Probas[StartCtx, 0]);

  while n < 16 do
  begin
    // p[0]: is there any non-zero coeff from position n onwards? (0 = EOB)
    if VP8RdGetBit(BR, p[0]) = 0 then
    begin
      Result := n;
      Exit;
    end;
    // p[1]: is coeff at n non-zero? (0 = this coeff is zero, advance)
    while VP8RdGetBit(BR, p[1]) = 0 do
    begin
      Inc(n);
      if n = 16 then begin Result := 16; Exit; end;
      p := @(BandsPtr[n]^.Probas[0, 0]);  // ctx=0 after zero run
    end;
    // Non-zero coeff at position n; decode absolute value using p[2..10]
    if VP8RdGetBit(BR, p[2]) = 0 then
    begin
      v := 1;
      p := @(BandsPtr[n + 1]^.Probas[1, 0]);  // ctx=1 for next
    end else
    begin
      // GetLargeValue: v > 1
      if VP8RdGetBit(BR, p[3]) = 0 then
      begin
        if VP8RdGetBit(BR, p[4]) = 0 then
          v := 2
        else
          v := 3 + VP8RdGetBit(BR, p[5]);
      end else if VP8RdGetBit(BR, p[6]) = 0 then
      begin
        if VP8RdGetBit(BR, p[7]) = 0 then
          v := 5 + VP8RdGetBit(BR, 159)
        else
        begin
          v := 7 + 2 * VP8RdGetBit(BR, 165);
          v := v + VP8RdGetBit(BR, 145);
        end;
      end else
      begin
        // Cat 3..6 using kCat3456 tables
        bit1 := VP8RdGetBit(BR, p[8]);
        bit0 := VP8RdGetBit(BR, p[9 + bit1]);
        cat  := 2 * bit1 + bit0;
        case cat of
          0: tab := @kCat3[0];
          1: tab := @kCat4[0];
          2: tab := @kCat5[0];
          3: tab := @kCat6[0];
          else tab := @kCat3[0]; // unreachable
        end;
        v := 0;
        while tab^ <> 0 do
        begin
          v := v * 2 + VP8RdGetBit(BR, tab^);
          Inc(tab);
        end;
        v := v + 3 + (8 shl cat);
      end;
      p := @(BandsPtr[n + 1]^.Probas[2, 0]);  // ctx=2 for next
    end;
    // Sign bit — use VP8RdGetSigned for exact range-coder state
    v := VP8RdGetSigned(BR, v);
    // Dequantize: DC (n=0) uses Dq0, AC uses Dq1
    if n = 0 then
      Coeffs[kZigzag[0]] := Int16(v * Dq0)
    else
      Coeffs[kZigzag[n]] := Int16(v * Dq1);
    Inc(n);
    if n = 16 then Break;
    // p already set to BandsPtr[n]^.Probas[ctx_new] for next iteration
  end;
  Result := n;
end;

// Forward declaration needed: VP8TransformWHT is defined in the IDCT section below
procedure VP8TransformWHT(DC: PInt16; Out16: PInt16); forward;

// Parse residuals for one macroblock. Matches C ParseResiduals exactly.
// WHT for I16x16 is applied HERE and DCs injected into Coeffs[n*16+0].
function VP8ParseResiduals(var D: TVP8Decoder; MbX: Integer;
  var Part: TVP8Rd; PartIdx: Integer): Boolean;
var
  mb:        ^TVP8MBData;
  leftMB:    PVP8MB;   // left border  = D.MBInfo (index -1)
  topMB:     PVP8MB;   // current col  = D.MBInfo + (MbX+1)
  dqm:       ^TVP8QuantMatrix;
  dcBuf:     array[0..15] of Int16;  // Y2/WHT input (separate from Coeffs)
  dst:       PInt16;
  first:     Integer;
  acBands:   ^TBandPtrsRow;
  tnz, lnz:  Byte;
  l, nz_val: Integer;
  x, y, ch:  Integer;
  ctx:       Integer;
  nzCoeffs:  Cardinal;
  nonZeroY:  Cardinal;
  nonZeroUV: Cardinal;
  outTNZ, outLNZ: Byte;
begin
  mb      := @D.MBData;
  leftMB  := D.MBInfo;                                          // dec->mb_info - 1
  topMB   := PVP8MB(NativeUInt(D.MBInfo) + (MbX+1)*SizeOf(TVP8MB));  // dec->mb_info + mb_x
  dqm     := @D.DQM[mb^.Segment];

  FillChar(mb^.Coeffs[0], SizeOf(mb^.Coeffs), 0);
  nonZeroY  := 0;
  nonZeroUV := 0;

  // === Y2 / WHT DC block (type 1), only for I16x16 ===
  if not mb^.IsI4x4 then
  begin
    FillChar(dcBuf, SizeOf(dcBuf), 0);
    ctx := Integer(topMB^.NZDC) + Integer(leftMB^.NZDC);
    nz_val := VP8GetCoeffsFast(Part, D.Proba.BandsPtr[1], ctx, 0,
                               dqm^.Y2Mat[0], dqm^.Y2Mat[1], @dcBuf[0]);
    topMB^.NZDC  := Byte(nz_val > 0);
    leftMB^.NZDC := Byte(nz_val > 0);
    if nz_val > 1 then
    begin
      // Full WHT: inject 16 DCs into each Y block's position 0
      VP8TransformWHT(@dcBuf[0], @dcBuf[0]);  // in-place into same buffer (uses tmp)
      for y := 0 to 15 do mb^.Coeffs[y * 16] := dcBuf[y];
    end else if nz_val = 1 then
    begin
      // Simplified: all 16 DCs get the same value (dc0+3)>>3 (arithmetic shift)
      nz_val := SarI(Integer(dcBuf[0]) + 3, 3);
      for y := 0 to 15 do mb^.Coeffs[y * 16] := Int16(nz_val);
    end;
    // else all zero — Coeffs already zero
    first := 1;
    acBands := @D.Proba.BandsPtr[0];
  end else
  begin
    first := 0;
    acBands := @D.Proba.BandsPtr[3];
  end;

  // === Y luma AC blocks (type 0 for I16x16, type 3 for I4x4) ===
  // Track NZ context using C's circular-buffer approach
  tnz := topMB^.NZ  and $0F;
  lnz := leftMB^.NZ and $0F;
  dst := @mb^.Coeffs[0];
  for y := 0 to 3 do
  begin
    l := lnz and 1;
    nzCoeffs := 0;
    for x := 0 to 3 do
    begin
      ctx    := l + (tnz and 1);
      nz_val := VP8GetCoeffsFast(Part, acBands^, ctx, first,
                                 dqm^.Y1Mat[0], dqm^.Y1Mat[1], dst);
      l      := Byte(nz_val > first);
      tnz    := Byte((tnz shr 1) or (l shl 7));
      // NzCodeBits: nzCoeffs = (nzCoeffs << 2) | (nz>3 ? 3 : nz>1 ? 2 : dc_nz)
      nzCoeffs := nzCoeffs shl 2;
      if nz_val > 3 then nzCoeffs := nzCoeffs or 3
      else if nz_val > 1 then nzCoeffs := nzCoeffs or 2
      else if dst[0] <> 0 then nzCoeffs := nzCoeffs or 1;
      Inc(dst, 16);
    end;
    tnz := tnz shr 4;
    lnz := Byte((lnz shr 1) or (l shl 7));
    nonZeroY := (nonZeroY shl 8) or nzCoeffs;
  end;
  outTNZ := tnz;
  outLNZ := lnz shr 4;
  mb^.NonZeroY := nonZeroY;

  // === UV chroma blocks (type 2): 2 channels × 2×2 blocks ===
  for ch := 0 to 1 do
  begin
    nzCoeffs := 0;
    tnz := topMB^.NZ  shr (4 + ch * 2);
    lnz := leftMB^.NZ shr (4 + ch * 2);
    for y := 0 to 1 do
    begin
      l := lnz and 1;
      for x := 0 to 1 do
      begin
        ctx    := l + (tnz and 1);
        nz_val := VP8GetCoeffsFast(Part, D.Proba.BandsPtr[2], ctx, 0,
                                   dqm^.UVMat[0], dqm^.UVMat[1], dst);
        l    := Byte(nz_val > 0);
        tnz  := Byte((tnz shr 1) or (l shl 3));
        nzCoeffs := nzCoeffs shl 2;
        if nz_val > 3 then nzCoeffs := nzCoeffs or 3
        else if nz_val > 1 then nzCoeffs := nzCoeffs or 2
        else if dst[0] <> 0 then nzCoeffs := nzCoeffs or 1;
        Inc(dst, 16);
      end;
      tnz := tnz shr 2;
      lnz := Byte((lnz shr 1) or (l shl 5));
    end;
    nonZeroUV := nonZeroUV or (nzCoeffs shl (4 * ch * 2));
    outTNZ    := outTNZ or Byte((tnz shl 4) shl (ch * 2));
    outLNZ    := outLNZ or Byte((lnz and $F0) shl (ch * 2));
  end;
  mb^.NonZeroUV := nonZeroUV;

  topMB^.NZ  := outTNZ;
  leftMB^.NZ := outLNZ;

  Result := (nonZeroY or nonZeroUV) = 0;  // True if skip (all zero)
end;

// ============================================================
// VP8 DSP: IDCT
// ============================================================

// 4x4 IDCT: C[16] coefficients (PInt16), adds to Pred, stores to Dst.
// Dst and Pred may be the same pointer (in-place add).
procedure VP8TransformOne(C: PInt16; Pred: PByte; Dst: PByte; Bps: Integer);
var
  tmp: array[0..3,0..3] of Integer;
  i: Integer;
  a, b, c2, d2: Integer;
  a0, a1, a2, a3: Integer;
begin
  // Vertical pass: process each column of the 4x4 coefficient block
  for i := 0 to 3 do
  begin
    a  := C[0+i] + C[8+i];
    b  := C[0+i] - C[8+i];
    // MUL1(x) = ((x*20091)>>16)+x;  MUL2(x) = (x*35468)>>16
    // Use SarI (arithmetic) because FPC shr is logical — wrong for negative values
    c2 := SarI(C[4+i] * 35468, 16) - (SarI(C[12+i] * 20091, 16) + C[12+i]);
    d2 := (SarI(C[4+i] * 20091, 16) + C[4+i]) + SarI(C[12+i] * 35468, 16);
    tmp[i,0] := a + d2;
    tmp[i,1] := b + c2;
    tmp[i,2] := b - c2;
    tmp[i,3] := a - d2;
  end;
  // Horizontal pass (process rows of tmp → output rows)
  for i := 0 to 3 do
  begin
    a  := tmp[0,i] + tmp[2,i];
    b  := tmp[0,i] - tmp[2,i];
    c2 := SarI(tmp[1,i] * 35468, 16) - (SarI(tmp[3,i] * 20091, 16) + tmp[3,i]);
    d2 := (SarI(tmp[1,i] * 20091, 16) + tmp[1,i]) + SarI(tmp[3,i] * 35468, 16);
    // Use SarI (arithmetic right shift) because FPC's shr is logical (unsigned)
    a0 := SarI(a + d2 + 4, 3);
    a1 := SarI(b + c2 + 4, 3);
    a2 := SarI(b - c2 + 4, 3);
    a3 := SarI(a - d2 + 4, 3);
    // Add prediction and clip
    (Dst + i * Bps + 0)^ := Clip8b(Integer((Pred + i * Bps + 0)^) + a0);
    (Dst + i * Bps + 1)^ := Clip8b(Integer((Pred + i * Bps + 1)^) + a1);
    (Dst + i * Bps + 2)^ := Clip8b(Integer((Pred + i * Bps + 2)^) + a2);
    (Dst + i * Bps + 3)^ := Clip8b(Integer((Pred + i * Bps + 3)^) + a3);
  end;
end;

// WHT transform: 16 DC coefficients (PInt16 DC) → 16 DCs (PInt16 Out16)
procedure VP8TransformWHT(DC: PInt16; Out16: PInt16);
var
  tmp: array[0..15] of Integer;
  i, a0, a1, a2, a3: Integer;
begin
  for i := 0 to 3 do
  begin
    a0 := DC[0+i] + DC[12+i];
    a1 := DC[4+i] + DC[ 8+i];
    a2 := DC[4+i] - DC[ 8+i];
    a3 := DC[0+i] - DC[12+i];
    tmp[0+i]  := a0 + a1;
    tmp[8+i]  := a0 - a1;
    tmp[4+i]  := a3 + a2;
    tmp[12+i] := a3 - a2;
  end;
  for i := 0 to 3 do
  begin
    a0 := tmp[0 + i*4] + tmp[3 + i*4];
    a1 := tmp[1 + i*4] + tmp[2 + i*4];
    a2 := tmp[1 + i*4] - tmp[2 + i*4];
    a3 := tmp[0 + i*4] - tmp[3 + i*4];
    Out16[0 + i*4] := Int16(SarI(a0 + a1 + 3, 3));
    Out16[1 + i*4] := Int16(SarI(a3 + a2 + 3, 3));
    Out16[2 + i*4] := Int16(SarI(a0 - a1 + 3, 3));
    Out16[3 + i*4] := Int16(SarI(a3 - a2 + 3, 3));
  end;
end;

// ============================================================
// VP8 DSP: INTRA PREDICTION
// ============================================================

// Fill a 16x16 or 8x8 block with a constant value
procedure Fill(Dst: PByte; Val: Byte; W, H, Stride: Integer);
var r: Integer;
begin
  for r := 0 to H-1 do
    FillChar((Dst + r * Stride)^, W, Val);
end;

// ---- 16x16 luma prediction ----
procedure I16x16_DC(Dst: PByte; Top, Left: PByte; Stride: Integer);
var sum, i: Integer;
begin
  sum := 0;
  for i := 0 to 15 do begin Inc(sum, (Left + i)^); Inc(sum, (Top + i)^); end;
  Fill(Dst, Byte((sum + 16) shr 5), 16, 16, Stride);
end;

procedure I16x16_DC_Left(Dst: PByte; Left: PByte; Stride: Integer);
var sum, i: Integer;
begin
  sum := 0;
  for i := 0 to 15 do Inc(sum, (Left + i)^);
  Fill(Dst, Byte((sum + 8) shr 4), 16, 16, Stride);
end;

procedure I16x16_DC_Top(Dst: PByte; Top: PByte; Stride: Integer);
var sum, i: Integer;
begin
  sum := 0;
  for i := 0 to 15 do Inc(sum, (Top + i)^);
  Fill(Dst, Byte((sum + 8) shr 4), 16, 16, Stride);
end;

procedure I16x16_V(Dst: PByte; Top: PByte; Stride: Integer);
var r: Integer;
begin
  for r := 0 to 15 do
    Move(Top^, (Dst + r * Stride)^, 16);
end;

procedure I16x16_H(Dst: PByte; Left: PByte; Stride: Integer);
var r: Integer;
begin
  for r := 0 to 15 do
    FillChar((Dst + r * Stride)^, 16, (Left + r)^);
end;

procedure I16x16_TM(Dst: PByte; Top, Left: PByte; TopLeft: Byte; Stride: Integer);
var r, c, v: Integer;
begin
  for r := 0 to 15 do
    for c := 0 to 15 do
    begin
      v := Integer((Left + r)^) + Integer((Top + c)^) - Integer(TopLeft);
      (Dst + r * Stride + c)^ := Clip8b(v);
    end;
end;

// Predict 16x16 luma into YuvBuf (dst=@YuvBuf[Y_OFF + mbx*16])
// TopCtx: top row Y samples, LeftCtx: left column Y samples
// HasTop, HasLeft: border flags
procedure VP8PredLuma16(Mode: Integer; Dst: PByte; TopCtx, LeftCtx: PByte;
  HasTop, HasLeft: Boolean; Stride: Integer);
var topLeft: Byte;
    tmpLeft: array[0..15] of Byte;
    tmpTop:  array[0..15] of Byte;
    i: Integer;
begin
  if not HasTop  then FillChar(tmpTop,  16, 127) else Move(TopCtx^, tmpTop, 16);
  if not HasLeft then FillChar(tmpLeft, 16, 129) else Move(LeftCtx^, tmpLeft, 16);
  // Top-left corner lives at Dst[-Stride-1] in the YUV buffer.
  // For mby=0 it was initialised to 127; for mby>0,mbx=0 to 129; for mbx>0 the
  // column-rotation copies the last byte of the previous MB's top-row here.
  // Always read the buffer directly — do NOT override with 129 when HasTop=False,
  // because TM_PRED requires the actual value (127 for the first MB row, not 129).
  topLeft := (Dst - Stride - 1)^;
  case Mode of
    DC_PRED:
      if HasTop and HasLeft then I16x16_DC(Dst, @tmpTop[0], @tmpLeft[0], Stride)
      else if HasLeft        then I16x16_DC_Left(Dst, @tmpLeft[0], Stride)
      else if HasTop         then I16x16_DC_Top(Dst, @tmpTop[0], Stride)
      else                        Fill(Dst, 128, 16, 16, Stride);
    V_PRED:  I16x16_V(Dst, @tmpTop[0], Stride);
    H_PRED:  I16x16_H(Dst, @tmpLeft[0], Stride);
    TM_PRED: I16x16_TM(Dst, @tmpTop[0], @tmpLeft[0], topLeft, Stride);
  end;
end;

// ---- 8x8 chroma prediction ----
procedure I8x8_DC(Dst: PByte; Top, Left: PByte; HasTop, HasLeft: Boolean; Stride: Integer);
var sum, i: Integer;
begin
  sum := 0;
  if HasTop  then for i := 0 to 7 do Inc(sum, (Top  + i)^);
  if HasLeft then for i := 0 to 7 do Inc(sum, (Left + i)^);
  if HasTop and HasLeft then Fill(Dst, Byte((sum + 8) shr 4), 8, 8, Stride)
  else if HasTop  then Fill(Dst, Byte((sum + 4) shr 3), 8, 8, Stride)
  else if HasLeft then Fill(Dst, Byte((sum + 4) shr 3), 8, 8, Stride)
  else                 Fill(Dst, 128, 8, 8, Stride);
end;

procedure I8x8_V(Dst: PByte; Top: PByte; Stride: Integer);
var r: Integer;
begin
  for r := 0 to 7 do Move(Top^, (Dst + r * Stride)^, 8);
end;

procedure I8x8_H(Dst: PByte; Left: PByte; Stride: Integer);
var r: Integer;
begin
  for r := 0 to 7 do FillChar((Dst + r * Stride)^, 8, (Left + r)^);
end;

procedure I8x8_TM(Dst: PByte; Top, Left: PByte; TL: Byte; Stride: Integer);
var r, c, v: Integer;
begin
  for r := 0 to 7 do
    for c := 0 to 7 do
    begin
      v := Integer((Left + r)^) + Integer((Top + c)^) - Integer(TL);
      (Dst + r * Stride + c)^ := Clip8b(v);
    end;
end;

procedure VP8PredChroma8(Mode: Integer; Dst: PByte; TopCtx, LeftCtx: PByte;
  HasTop, HasLeft: Boolean; Stride: Integer);
var tmpLeft: array[0..7] of Byte;
    tmpTop:  array[0..7] of Byte;
    tl: Byte;
begin
  if not HasTop  then FillChar(tmpTop,  8, 127) else Move(TopCtx^, tmpTop, 8);
  if not HasLeft then FillChar(tmpLeft, 8, 129) else Move(LeftCtx^, tmpLeft, 8);
  tl := (Dst - Stride - 1)^;
  case Mode of
    DC_PRED: I8x8_DC(Dst, @tmpTop[0], @tmpLeft[0], HasTop, HasLeft, Stride);
    V_PRED:  I8x8_V(Dst, @tmpTop[0], Stride);
    H_PRED:  I8x8_H(Dst, @tmpLeft[0], Stride);
    TM_PRED: I8x8_TM(Dst, @tmpTop[0], @tmpLeft[0], tl, Stride);
  end;
end;

// ---- 4x4 luma intra prediction (for I4x4 macroblocks) ----
// Returns average of 4 bytes at p
function Avg4(a,b,c,d: Integer): Byte; inline;
begin Result := Byte((a+b+c+d+2) shr 2); end;

function Avg3(a,b,c: Integer): Byte; inline;
begin Result := Byte((a+2*b+c+2) shr 2); end;

function Avg2(a,b: Integer): Byte; inline;
begin Result := Byte((a+b+1) shr 1); end;

procedure I4x4_DC(Dst: PByte; Top: PByte; Left: PByte; Stride: Integer);
var s: Integer;
begin
  s := (Top+0)^ + (Top+1)^ + (Top+2)^ + (Top+3)^ +
       (Left+0)^ + (Left+1)^ + (Left+2)^ + (Left+3)^ + 4;
  Fill(Dst, Byte(s shr 3), 4, 4, Stride);
end;

procedure I4x4_TM(Dst: PByte; Top, Left: PByte; TL: Byte; Stride: Integer);
var r, c: Integer;
begin
  for r := 0 to 3 do
    for c := 0 to 3 do
      (Dst + r*Stride + c)^ := Clip8b((Left+r)^ + (Top+c)^ - TL);
end;

procedure I4x4_VE(Dst: PByte; Top: PByte; Stride: Integer);
// Vertical (extrapolate from top)
var r: Integer;
    vals: array[0..3] of Byte;
begin
  vals[0] := Avg3((Top-1)^, (Top+0)^, (Top+1)^);
  vals[1] := Avg3((Top+0)^, (Top+1)^, (Top+2)^);
  vals[2] := Avg3((Top+1)^, (Top+2)^, (Top+3)^);
  vals[3] := Avg3((Top+2)^, (Top+3)^, (Top+4)^);
  for r := 0 to 3 do
    Move(vals[0], (Dst + r*Stride)^, 4);
end;

procedure I4x4_HE(Dst: PByte; Left: PByte; TL: Byte; Stride: Integer);
var c: array[0..3] of Byte;
begin
  c[0] := Avg3(TL,         (Left+0)^, (Left+1)^);
  c[1] := Avg3((Left+0)^,  (Left+1)^, (Left+2)^);
  c[2] := Avg3((Left+1)^,  (Left+2)^, (Left+3)^);
  c[3] := Avg3((Left+2)^,  (Left+3)^, (Left+3)^); // last repeats
  FillChar((Dst + 0*Stride)^, 4, c[0]);
  FillChar((Dst + 1*Stride)^, 4, c[1]);
  FillChar((Dst + 2*Stride)^, 4, c[2]);
  FillChar((Dst + 3*Stride)^, 4, c[3]);
end;

procedure I4x4_RD(Dst: PByte; Top, Left: PByte; TL: Byte; Stride: Integer);
// DST(x,y) = Dst[y*Stride+x]
// X=TL, I=Left[0], J=Left[1], K=Left[2], L=Left[3], A..D=Top[0..3]
var X, I, J, K, L, A, B, C, D: Integer;
begin
  X := TL;          I := (Left+0)^; J := (Left+1)^;
  K := (Left+2)^;   L := (Left+3)^;
  A := (Top+0)^;    B := (Top+1)^;  C := (Top+2)^; D := (Top+3)^;
  (Dst + 3*Stride + 0)^ := Avg3(J, K, L);
  (Dst + 3*Stride + 1)^ := Avg3(I, J, K);
  (Dst + 2*Stride + 0)^ := Avg3(I, J, K);
  (Dst + 3*Stride + 2)^ := Avg3(X, I, J);
  (Dst + 2*Stride + 1)^ := Avg3(X, I, J);
  (Dst + 1*Stride + 0)^ := Avg3(X, I, J);
  (Dst + 3*Stride + 3)^ := Avg3(A, X, I);
  (Dst + 2*Stride + 2)^ := Avg3(A, X, I);
  (Dst + 1*Stride + 1)^ := Avg3(A, X, I);
  (Dst + 0*Stride + 0)^ := Avg3(A, X, I);
  (Dst + 2*Stride + 3)^ := Avg3(B, A, X);
  (Dst + 1*Stride + 2)^ := Avg3(B, A, X);
  (Dst + 0*Stride + 1)^ := Avg3(B, A, X);
  (Dst + 1*Stride + 3)^ := Avg3(C, B, A);
  (Dst + 0*Stride + 2)^ := Avg3(C, B, A);
  (Dst + 0*Stride + 3)^ := Avg3(D, C, B);
end;

procedure I4x4_LD(Dst: PByte; Top: PByte; Stride: Integer);
var t: array[0..7] of Integer;
begin
  t[0]:=(Top+0)^; t[1]:=(Top+1)^; t[2]:=(Top+2)^; t[3]:=(Top+3)^;
  t[4]:=(Top+4)^; t[5]:=(Top+5)^; t[6]:=(Top+6)^; t[7]:=(Top+7)^;
  (Dst+0*Stride+0)^:=Avg3(t[0],t[1],t[2]); (Dst+0*Stride+1)^:=Avg3(t[1],t[2],t[3]);
  (Dst+0*Stride+2)^:=Avg3(t[2],t[3],t[4]); (Dst+0*Stride+3)^:=Avg3(t[3],t[4],t[5]);
  (Dst+1*Stride+0)^:=Avg3(t[1],t[2],t[3]); (Dst+1*Stride+1)^:=Avg3(t[2],t[3],t[4]);
  (Dst+1*Stride+2)^:=Avg3(t[3],t[4],t[5]); (Dst+1*Stride+3)^:=Avg3(t[4],t[5],t[6]);
  (Dst+2*Stride+0)^:=Avg3(t[2],t[3],t[4]); (Dst+2*Stride+1)^:=Avg3(t[3],t[4],t[5]);
  (Dst+2*Stride+2)^:=Avg3(t[4],t[5],t[6]); (Dst+2*Stride+3)^:=Avg3(t[5],t[6],t[7]);
  (Dst+3*Stride+0)^:=Avg3(t[3],t[4],t[5]); (Dst+3*Stride+1)^:=Avg3(t[4],t[5],t[6]);
  (Dst+3*Stride+2)^:=Avg3(t[5],t[6],t[7]); (Dst+3*Stride+3)^:=Avg3(t[6],t[7],t[7]);
end;

procedure I4x4_VR(Dst: PByte; Top, Left: PByte; TL: Byte; Stride: Integer);
// Matches VR4_C: DST(x,y) = (Dst + y*Stride + x)^
// X=TL, I=Left[0], J=Left[1], K=Left[2]; A..D=Top[0..3]
var X, I, J, K, A, B, C, D: Integer;
begin
  X := TL;        I := (Left+0)^; J := (Left+1)^; K := (Left+2)^;
  A := (Top+0)^;  B := (Top+1)^;  C := (Top+2)^;  D := (Top+3)^;
  // DST(0,0)=DST(1,2)=Avg2(X,A)
  (Dst+0*Stride+0)^ := Avg2(X,A);  (Dst+2*Stride+1)^ := Avg2(X,A);
  // DST(1,0)=DST(2,2)=Avg2(A,B)
  (Dst+0*Stride+1)^ := Avg2(A,B);  (Dst+2*Stride+2)^ := Avg2(A,B);
  // DST(2,0)=DST(3,2)=Avg2(B,C)
  (Dst+0*Stride+2)^ := Avg2(B,C);  (Dst+2*Stride+3)^ := Avg2(B,C);
  // DST(3,0)=Avg2(C,D)
  (Dst+0*Stride+3)^ := Avg2(C,D);
  // DST(0,1)=DST(1,3)=Avg3(I,X,A)
  (Dst+1*Stride+0)^ := Avg3(I,X,A);  (Dst+3*Stride+1)^ := Avg3(I,X,A);
  // DST(1,1)=DST(2,3)=Avg3(X,A,B)
  (Dst+1*Stride+1)^ := Avg3(X,A,B);  (Dst+3*Stride+2)^ := Avg3(X,A,B);
  // DST(2,1)=DST(3,3)=Avg3(A,B,C)
  (Dst+1*Stride+2)^ := Avg3(A,B,C);  (Dst+3*Stride+3)^ := Avg3(A,B,C);
  // DST(3,1)=Avg3(B,C,D)
  (Dst+1*Stride+3)^ := Avg3(B,C,D);
  // DST(0,2)=Avg3(J,I,X)
  (Dst+2*Stride+0)^ := Avg3(J,I,X);
  // DST(0,3)=Avg3(K,J,I)
  (Dst+3*Stride+0)^ := Avg3(K,J,I);
end;

procedure I4x4_VL(Dst: PByte; Top: PByte; Stride: Integer);
var t: array[0..7] of Integer;
begin
  t[0]:=(Top+0)^; t[1]:=(Top+1)^; t[2]:=(Top+2)^; t[3]:=(Top+3)^;
  t[4]:=(Top+4)^; t[5]:=(Top+5)^; t[6]:=(Top+6)^; t[7]:=(Top+7)^;
  (Dst+0*Stride+0)^:=Avg2(t[0],t[1]); (Dst+0*Stride+1)^:=Avg2(t[1],t[2]);
  (Dst+0*Stride+2)^:=Avg2(t[2],t[3]); (Dst+0*Stride+3)^:=Avg2(t[3],t[4]);
  (Dst+1*Stride+0)^:=Avg3(t[0],t[1],t[2]); (Dst+1*Stride+1)^:=Avg3(t[1],t[2],t[3]);
  (Dst+1*Stride+2)^:=Avg3(t[2],t[3],t[4]); (Dst+1*Stride+3)^:=Avg3(t[3],t[4],t[5]);
  (Dst+2*Stride+0)^:=Avg2(t[1],t[2]); (Dst+2*Stride+1)^:=Avg2(t[2],t[3]);
  (Dst+2*Stride+2)^:=Avg2(t[3],t[4]); (Dst+2*Stride+3)^:=Avg3(t[4],t[5],t[6]);
  (Dst+3*Stride+0)^:=Avg3(t[1],t[2],t[3]); (Dst+3*Stride+1)^:=Avg3(t[2],t[3],t[4]);
  (Dst+3*Stride+2)^:=Avg3(t[3],t[4],t[5]); (Dst+3*Stride+3)^:=Avg3(t[5],t[6],t[7]);
end;

procedure I4x4_HD(Dst: PByte; Top, Left: PByte; TL: Byte; Stride: Integer);
// Matches HD4_C: DST(x,y) = (Dst + y*Stride + x)^
// X=TL, I=Left[0], J=Left[1], K=Left[2], L=Left[3]; A..C=Top[0..2], D=Top[3]
var X, I, J, K, L, A, B, C, D: Integer;
begin
  X := TL;        I := (Left+0)^; J := (Left+1)^; K := (Left+2)^; L := (Left+3)^;
  A := (Top+0)^;  B := (Top+1)^;  C := (Top+2)^;  D := (Top+3)^;
  // DST(0,0)=DST(2,1)=Avg2(I,X)
  (Dst+0*Stride+0)^ := Avg2(I,X);  (Dst+1*Stride+2)^ := Avg2(I,X);
  // DST(0,1)=DST(2,2)=Avg2(J,I)
  (Dst+1*Stride+0)^ := Avg2(J,I);  (Dst+2*Stride+2)^ := Avg2(J,I);
  // DST(0,2)=DST(2,3)=Avg2(K,J)
  (Dst+2*Stride+0)^ := Avg2(K,J);  (Dst+3*Stride+2)^ := Avg2(K,J);
  // DST(0,3)=Avg2(L,K)
  (Dst+3*Stride+0)^ := Avg2(L,K);
  // DST(3,0)=Avg3(A,B,C)
  (Dst+0*Stride+3)^ := Avg3(A,B,C);
  // DST(2,0)=Avg3(X,A,B)
  (Dst+0*Stride+2)^ := Avg3(X,A,B);
  // DST(1,0)=DST(3,1)=Avg3(I,X,A)
  (Dst+0*Stride+1)^ := Avg3(I,X,A);  (Dst+1*Stride+3)^ := Avg3(I,X,A);
  // DST(1,1)=DST(3,2)=Avg3(J,I,X)
  (Dst+1*Stride+1)^ := Avg3(J,I,X);  (Dst+2*Stride+3)^ := Avg3(J,I,X);
  // DST(1,2)=DST(3,3)=Avg3(K,J,I)
  (Dst+2*Stride+1)^ := Avg3(K,J,I);  (Dst+3*Stride+3)^ := Avg3(K,J,I);
  // DST(1,3)=Avg3(L,K,J)
  (Dst+3*Stride+1)^ := Avg3(L,K,J);
  // Note: D (Top[3]) is not used in HD4
  D := D; // suppress hint
end;

procedure I4x4_HU(Dst: PByte; Left: PByte; Stride: Integer);
var l: array[0..3] of Integer;
begin
  l[0]:=(Left+0)^; l[1]:=(Left+1)^; l[2]:=(Left+2)^; l[3]:=(Left+3)^;
  (Dst+0*Stride+0)^:=Avg2(l[0],l[1]); (Dst+0*Stride+1)^:=Avg3(l[0],l[1],l[2]);
  (Dst+0*Stride+2)^:=Avg2(l[1],l[2]); (Dst+0*Stride+3)^:=Avg3(l[1],l[2],l[3]);
  (Dst+1*Stride+0)^:=Avg2(l[1],l[2]); (Dst+1*Stride+1)^:=Avg3(l[1],l[2],l[3]);
  (Dst+1*Stride+2)^:=Avg2(l[2],l[3]); (Dst+1*Stride+3)^:=Avg3(l[2],l[3],l[3]);
  (Dst+2*Stride+0)^:=Avg2(l[2],l[3]); (Dst+2*Stride+1)^:=Avg3(l[2],l[3],l[3]);
  (Dst+2*Stride+2)^:=l[3];             (Dst+2*Stride+3)^:=l[3];
  (Dst+3*Stride+0)^:=l[3]; (Dst+3*Stride+1)^:=l[3];
  (Dst+3*Stride+2)^:=l[3]; (Dst+3*Stride+3)^:=l[3];
end;

// Predict one 4x4 block in the luma plane
// TopSamples: 8 bytes (4 top + 4 top-right) at Top[0..7]
// LeftSamples: 4 bytes at Left[0..3]
// TopLeft: single byte (top-left corner)
procedure VP8PredLuma4(Mode: Integer; Dst: PByte; Top, Left: PByte;
  TL: Byte; Stride: Integer);
begin
  case Mode of
    B_DC_PRED: I4x4_DC(Dst, Top, Left, Stride);
    B_TM_PRED: I4x4_TM(Dst, Top, Left, TL, Stride);
    B_VE_PRED: I4x4_VE(Dst, Top, Stride);
    B_HE_PRED: I4x4_HE(Dst, Left, TL, Stride);
    B_RD_PRED: I4x4_RD(Dst, Top, Left, TL, Stride);
    B_VR_PRED: I4x4_VR(Dst, Top, Left, TL, Stride);
    B_LD_PRED: I4x4_LD(Dst, Top, Stride);
    B_VL_PRED: I4x4_VL(Dst, Top, Stride);
    B_HD_PRED: I4x4_HD(Dst, Top, Left, TL, Stride);
    B_HU_PRED: I4x4_HU(Dst, Left, Stride);
  end;
end;

// ============================================================
// VP8 MACROBLOCK RECONSTRUCTION
// ============================================================

// Copy 4 bytes: used for left-context updates
procedure Copy4(Dst, Src: PByte); inline;
begin
  PCardinal(Dst)^ := PCardinal(Src)^;
end;

// Reconstruct one macroblock into YuvBuf
// D.MBData must have been populated by VP8ParseResiduals
// YBuf = @YuvBuf[Y_OFF], UBuf = @YuvBuf[U_OFF], VBuf = @YuvBuf[V_OFF]
procedure VP8ReconstructMB(var D: TVP8Decoder; MbX: Integer;
  HasTop, HasLeft: Boolean);
var
  mb:   ^TVP8MBData;
  y, x, n: Integer;
  yBase, uBase, vBase: PByte;
  topY, topU, topV: PByte;
  leftY: array[0..15] of Byte;
  leftU, leftV: array[0..7] of Byte;
  yDst, uDst, vDst: PByte;
  leftCol: array[0..15] of Byte;
begin
  mb := @D.MBData;
  yBase := @D.YuvBuf[Y_OFF];
  uBase := @D.YuvBuf[U_OFF];
  vBase := @D.YuvBuf[V_OFF];

  // Top-row context pointers
  topY := D.YTopBuf + MbX * 16;
  topU := D.UTopBuf + MbX * 8;
  topV := D.VTopBuf + MbX * 8;

  // Left-column context: read from YuvBuf border pixels
  // Left Y: column -1 of Y = yBase - 1, rows 0..15
  // Left U: column -1 of U = uBase - 1, rows 0..7
  if HasLeft then
  begin
    for y := 0 to 15 do leftY[y] := (yBase + y * BPS - 1)^;
    for y := 0 to  7 do leftU[y] := (uBase + y * BPS - 1)^;
    for y := 0 to  7 do leftV[y] := (vBase + y * BPS - 1)^;
  end else
  begin
    FillChar(leftY, 16, 129);
    FillChar(leftU,  8, 129);
    FillChar(leftV,  8, 129);
  end;

  // Luma prediction
  if not mb^.IsI4x4 then
  begin
    // I16x16: predict then apply residuals per 4x4 block
    // WHT DCs were already injected into mb^.Coeffs[n*16+0] by VP8ParseResiduals
    VP8PredLuma16(mb^.IModes[0], yBase, topY, @leftY[0], HasTop, HasLeft, BPS);
    for y := 0 to 3 do
      for x := 0 to 3 do
      begin
        n := y * 4 + x;
        yDst := yBase + kScan[n];
        VP8TransformOne(@mb^.Coeffs[n*16], yDst, yDst, BPS);
      end;
  end else
  begin
    // I4x4: predict each 4x4 sub-block independently, then apply residuals
    for n := 0 to 15 do
    begin
      x := n and 3; y := n shr 2;
      yDst := yBase + kScan[n];
      // Collect left column (4 pixels, strided BPS apart) into contiguous temp
      leftCol[0] := (yDst - 1 + 0*BPS)^;
      leftCol[1] := (yDst - 1 + 1*BPS)^;
      leftCol[2] := (yDst - 1 + 2*BPS)^;
      leftCol[3] := (yDst - 1 + 3*BPS)^;
      VP8PredLuma4(mb^.IModes[n], yDst,
                   yDst - BPS,       // top row (4+4 bytes available)
                   @leftCol[0],      // left column (contiguous 4 bytes)
                   (yDst - BPS - 1)^,
                   BPS);
      // Apply IDCT residuals
      VP8TransformOne(@mb^.Coeffs[n*16], yDst, yDst, BPS);
    end;
  end;

  // Chroma prediction (8x8 U and V)
  VP8PredChroma8(mb^.UVMode, uBase, topU, @leftU[0], HasTop, HasLeft, BPS);
  VP8PredChroma8(mb^.UVMode, vBase, topV, @leftV[0], HasTop, HasLeft, BPS);
  // Apply chroma IDCT (4 blocks each for U and V)
  for n := 0 to 3 do
  begin
    x := n and 1; y := n shr 1;
    uDst := uBase + (x*4) + (y*4*BPS);
    vDst := vBase + (x*4) + (y*4*BPS);
    VP8TransformOne(@mb^.Coeffs[(16+n)*16], uDst, uDst, BPS);
    VP8TransformOne(@mb^.Coeffs[(20+n)*16], vDst, vDst, BPS);
  end;

  // Update top-row context
  Move((yBase + 15*BPS)^, topY^, 16);
  Move((uBase +  7*BPS)^, topU^,  8);
  Move((vBase +  7*BPS)^, topV^,  8);
end;

// ============================================================
// YUV -> RGB OUTPUT CONVERSION
// ============================================================

// ============================================================
// VP8 IN-LOOP DEBLOCKING FILTER
// Clip8b (=[0,255]) and SarI (arithmetic shift) are defined above.
// ============================================================

function SClip1(V: Integer): Integer; inline;  // clamp to [-128, 127]
begin
  if V < -128 then Result := -128
  else if V > 127 then Result := 127
  else Result := V;
end;

function SClip2(V: Integer): Integer; inline;  // clamp to [-16, 15]
begin
  if V < -16 then Result := -16
  else if V > 15 then Result := 15
  else Result := V;
end;

procedure DoFilter2(P: PByte; Step: Integer); inline;
var P1, P0, Q0, Q1, A, A1, A2: Integer;
begin
  P1 := P[-2 * Step]; P0 := P[-Step]; Q0 := P[0]; Q1 := P[Step];
  A := 3 * (Q0 - P0) + SClip1(P1 - Q1);
  A1 := SClip2(SarI(A + 4, 3));
  A2 := SClip2(SarI(A + 3, 3));
  P[-Step] := Clip8b(P0 + A2);
  P[0]     := Clip8b(Q0 - A1);
end;

procedure DoFilter4(P: PByte; Step: Integer); inline;
var P1, P0, Q0, Q1, A, A1, A2, A3: Integer;
begin
  P1 := P[-2 * Step]; P0 := P[-Step]; Q0 := P[0]; Q1 := P[Step];
  A := 3 * (Q0 - P0);
  A1 := SClip2(SarI(A + 4, 3));
  A2 := SClip2(SarI(A + 3, 3));
  A3 := SarI(A1 + 1, 1);
  P[-2 * Step] := Clip8b(P1 + A3);
  P[-Step]     := Clip8b(P0 + A2);
  P[0]         := Clip8b(Q0 - A1);
  P[Step]      := Clip8b(Q1 - A3);
end;

procedure DoFilter6(P: PByte; Step: Integer); inline;
var P2, P1, P0, Q0, Q1, Q2, A, A1, A2, A3: Integer;
begin
  P2 := P[-3 * Step]; P1 := P[-2 * Step]; P0 := P[-Step];
  Q0 := P[0]; Q1 := P[Step]; Q2 := P[2 * Step];
  A := SClip1(3 * (Q0 - P0) + SClip1(P1 - Q1));
  A1 := SarI(27 * A + 63, 7);
  A2 := SarI(18 * A + 63, 7);
  A3 := SarI(9 * A + 63, 7);
  P[-3 * Step] := Clip8b(P2 + A3);
  P[-2 * Step] := Clip8b(P1 + A2);
  P[-Step]     := Clip8b(P0 + A1);
  P[0]         := Clip8b(Q0 - A1);
  P[Step]      := Clip8b(Q1 - A2);
  P[2 * Step]  := Clip8b(Q2 - A3);
end;

function NeedsFilter(P: PByte; Step, T: Integer): Boolean; inline;
var P1, P0, Q0, Q1: Integer;
begin
  P1 := P[-2 * Step]; P0 := P[-Step]; Q0 := P[0]; Q1 := P[Step];
  Result := (4 * Abs(P0 - Q0) + Abs(P1 - Q1)) <= T;
end;

function NeedsFilter2(P: PByte; Step, T, IT: Integer): Boolean; inline;
var P3, P2, P1, P0, Q0, Q1, Q2, Q3: Integer;
begin
  P3 := P[-4 * Step]; P2 := P[-3 * Step]; P1 := P[-2 * Step]; P0 := P[-Step];
  Q0 := P[0]; Q1 := P[Step]; Q2 := P[2 * Step]; Q3 := P[3 * Step];
  if (4 * Abs(P0 - Q0) + Abs(P1 - Q1)) > T then begin Result := False; Exit; end;
  Result := (Abs(P3 - P2) <= IT) and (Abs(P2 - P1) <= IT) and (Abs(P1 - P0) <= IT) and
            (Abs(Q3 - Q2) <= IT) and (Abs(Q2 - Q1) <= IT) and (Abs(Q1 - Q0) <= IT);
end;

function HevTest(P: PByte; Step, Thresh: Integer): Boolean; inline;
var P1, P0, Q0, Q1: Integer;
begin
  P1 := P[-2 * Step]; P0 := P[-Step]; Q0 := P[0]; Q1 := P[Step];
  Result := (Abs(P1 - P0) > Thresh) or (Abs(Q1 - Q0) > Thresh);
end;

// MB-edge loop: hev -> 2-tap, else 6-tap.
procedure FilterLoop26(P: PByte; HStride, VStride, Size, Thresh, IThresh, HevT: Integer);
var Thresh2, K: Integer; Q: PByte;
begin
  Thresh2 := 2 * Thresh + 1;
  Q := P;
  for K := 0 to Size - 1 do
  begin
    if NeedsFilter2(Q, HStride, Thresh2, IThresh) then
    begin
      if HevTest(Q, HStride, HevT) then DoFilter2(Q, HStride)
      else DoFilter6(Q, HStride);
    end;
    Q := Q + VStride;
  end;
end;

// Inner-edge loop: hev -> 2-tap, else 4-tap.
procedure FilterLoop24(P: PByte; HStride, VStride, Size, Thresh, IThresh, HevT: Integer);
var Thresh2, K: Integer; Q: PByte;
begin
  Thresh2 := 2 * Thresh + 1;
  Q := P;
  for K := 0 to Size - 1 do
  begin
    if NeedsFilter2(Q, HStride, Thresh2, IThresh) then
    begin
      if HevTest(Q, HStride, HevT) then DoFilter2(Q, HStride)
      else DoFilter4(Q, HStride);
    end;
    Q := Q + VStride;
  end;
end;

procedure HFilter16(P: PByte; Stride, T, IT, HevT: Integer);
begin FilterLoop26(P, 1, Stride, 16, T, IT, HevT); end;

procedure VFilter16(P: PByte; Stride, T, IT, HevT: Integer);
begin FilterLoop26(P, Stride, 1, 16, T, IT, HevT); end;

procedure HFilter16i(P: PByte; Stride, T, IT, HevT: Integer);
var K: Integer; Q: PByte;
begin
  Q := P;
  for K := 1 to 3 do begin Q := Q + 4; FilterLoop24(Q, 1, Stride, 16, T, IT, HevT); end;
end;

procedure VFilter16i(P: PByte; Stride, T, IT, HevT: Integer);
var K: Integer; Q: PByte;
begin
  Q := P;
  for K := 1 to 3 do begin Q := Q + 4 * Stride; FilterLoop24(Q, Stride, 1, 16, T, IT, HevT); end;
end;

procedure HFilter8(U, V: PByte; Stride, T, IT, HevT: Integer);
begin
  FilterLoop26(U, 1, Stride, 8, T, IT, HevT);
  FilterLoop26(V, 1, Stride, 8, T, IT, HevT);
end;

procedure VFilter8(U, V: PByte; Stride, T, IT, HevT: Integer);
begin
  FilterLoop26(U, Stride, 1, 8, T, IT, HevT);
  FilterLoop26(V, Stride, 1, 8, T, IT, HevT);
end;

procedure HFilter8i(U, V: PByte; Stride, T, IT, HevT: Integer);
begin
  FilterLoop24(U + 4, 1, Stride, 8, T, IT, HevT);
  FilterLoop24(V + 4, 1, Stride, 8, T, IT, HevT);
end;

procedure VFilter8i(U, V: PByte; Stride, T, IT, HevT: Integer);
begin
  FilterLoop24(U + 4 * Stride, Stride, 1, 8, T, IT, HevT);
  FilterLoop24(V + 4 * Stride, Stride, 1, 8, T, IT, HevT);
end;

procedure SimpleVFilter16(P: PByte; Stride, Thresh: Integer);
var I, T2: Integer;
begin
  T2 := 2 * Thresh + 1;
  for I := 0 to 15 do
    if NeedsFilter(P + I, Stride, T2) then DoFilter2(P + I, Stride);
end;

procedure SimpleHFilter16(P: PByte; Stride, Thresh: Integer);
var I, T2: Integer;
begin
  T2 := 2 * Thresh + 1;
  for I := 0 to 15 do
    if NeedsFilter(P + I * Stride, 1, T2) then DoFilter2(P + I * Stride, 1);
end;

procedure SimpleVFilter16i(P: PByte; Stride, Thresh: Integer);
var K: Integer; Q: PByte;
begin
  Q := P;
  for K := 1 to 3 do begin Q := Q + 4 * Stride; SimpleVFilter16(Q, Stride, Thresh); end;
end;

procedure SimpleHFilter16i(P: PByte; Stride, Thresh: Integer);
var K: Integer; Q: PByte;
begin
  Q := P;
  for K := 1 to 3 do begin Q := Q + 4; SimpleHFilter16(Q, Stride, Thresh); end;
end;

// Compute the per-MB filter strength.
// Keyframe-only: ref delta index 0, mode delta index 0, keyframe hev table.
procedure ComputeFInfo(const D: TVP8Decoder; Seg: Integer; IsI4x4, Skip: Boolean;
  out FI: TVP8FInfo);
var Level, ILevel: Integer;
begin
  if D.SegHdr.UseSegment then
  begin
    Level := D.SegHdr.FilterStrength[Seg];
    if not D.SegHdr.AbsoluteDelta then Inc(Level, D.FilterLevel);
  end
  else
    Level := D.FilterLevel;
  if D.UseLFDelta then
  begin
    Inc(Level, D.RefLFDelta[0]);          // intra reference
    if IsI4x4 then Inc(Level, D.ModeLFDelta[0]);
  end;
  if Level < 0 then Level := 0 else if Level > 63 then Level := 63;
  FI.FInner := IsI4x4 or (not Skip);
  if Level = 0 then
  begin
    FI.FLimit := 0; FI.FILevel := 0; FI.FHev := 0;
    Exit;
  end;
  ILevel := Level;
  if D.FilterSharpness > 0 then
  begin
    if D.FilterSharpness > 4 then ILevel := ILevel shr 2 else ILevel := ILevel shr 1;
    if ILevel > 9 - D.FilterSharpness then ILevel := 9 - D.FilterSharpness;
  end;
  if ILevel < 1 then ILevel := 1;
  FI.FILevel := ILevel;
  FI.FLimit  := 2 * Level + ILevel;
  if Level >= 40 then FI.FHev := 2
  else if Level >= 15 then FI.FHev := 1
  else FI.FHev := 0;
end;

// Filter one macroblock's edges in the reconstruction planes.
procedure DoFilterMB(const D: TVP8Decoder; MbX, MbY: Integer);
var
  FI: PVP8FInfo;
  yDst, uDst, vDst: PByte;
  Limit, ILevel, Hev: Integer;
begin
  FI := D.FInfo + (MbY * D.MbW + MbX);
  Limit := FI^.FLimit;
  if Limit = 0 then Exit;
  ILevel := FI^.FILevel;
  Hev := FI^.FHev;
  yDst := D.YPlane + (MbY * 16) * D.YStride + MbX * 16;
  uDst := D.UPlane + (MbY * 8) * D.UVStride + MbX * 8;
  vDst := D.VPlane + (MbY * 8) * D.UVStride + MbX * 8;
  if D.FilterType = 2 then       // normal (luma + chroma)
  begin
    if MbX > 0 then
    begin
      HFilter16(yDst, D.YStride, Limit + 4, ILevel, Hev);
      HFilter8(uDst, vDst, D.UVStride, Limit + 4, ILevel, Hev);
    end;
    if FI^.FInner then
    begin
      HFilter16i(yDst, D.YStride, Limit, ILevel, Hev);
      HFilter8i(uDst, vDst, D.UVStride, Limit, ILevel, Hev);
    end;
    if MbY > 0 then
    begin
      VFilter16(yDst, D.YStride, Limit + 4, ILevel, Hev);
      VFilter8(uDst, vDst, D.UVStride, Limit + 4, ILevel, Hev);
    end;
    if FI^.FInner then
    begin
      VFilter16i(yDst, D.YStride, Limit, ILevel, Hev);
      VFilter8i(uDst, vDst, D.UVStride, Limit, ILevel, Hev);
    end;
  end
  else                           // simple (luma only)
  begin
    if MbX > 0 then SimpleHFilter16(yDst, D.YStride, Limit + 4);
    if FI^.FInner then SimpleHFilter16i(yDst, D.YStride, Limit);
    if MbY > 0 then SimpleVFilter16(yDst, D.YStride, Limit + 4);
    if FI^.FInner then SimpleVFilter16i(yDst, D.YStride, Limit);
  end;
end;

// Emit one RGB(A) pixel from a Y/U/V triple.
procedure EmitPixel(Yv, Uv, Vv: Integer; Dst: PByte; Mode: TCSMode); inline;
var R, G, B: Byte;
begin
  R := YuvToR(Yv, Vv);
  G := YuvToG(Yv, Uv, Vv);
  B := YuvToB(Yv, Uv);
  case Mode of
    csmRGBA: begin Dst[0] := R; Dst[1] := G; Dst[2] := B; Dst[3] := 255; end;
    csmARGB: begin Dst[0] := 255; Dst[1] := R; Dst[2] := G; Dst[3] := B; end;
    csmBGRA: begin Dst[0] := B; Dst[1] := G; Dst[2] := R; Dst[3] := 255; end;
    csmRGB:  begin Dst[0] := R; Dst[1] := G; Dst[2] := B; end;
    csmBGR:  begin Dst[0] := B; Dst[1] := G; Dst[2] := R; end;
  end;
end;

// Fancy (bilinear) chroma upsampling for one pair of output rows. The two
// output rows share a chroma-row pair (Top = chroma row above, Cur = chroma row
// below). BotY/BotDst are nil for the single-row boundary cases.
procedure UpsampleRowPair(TopY, BotY, TopU, TopV, CurU, CurV, TopDst, BotDst: PByte;
  W: Integer; Mode: TCSMode; Bpp: Integer);
var
  LastPair, X: Integer;
  TlU, TlV, LU, LV, TU, TV, UU, VV: Integer;
  AvgU, AvgV, D12U, D12V, D03U, D03V: Integer;
begin
  LastPair := (W - 1) shr 1;
  TlU := TopU[0]; TlV := TopV[0];
  LU := CurU[0]; LV := CurV[0];
  EmitPixel(TopY[0], (3 * TlU + LU + 2) shr 2, (3 * TlV + LV + 2) shr 2, TopDst, Mode);
  if BotDst <> nil then
    EmitPixel(BotY[0], (3 * LU + TlU + 2) shr 2, (3 * LV + TlV + 2) shr 2, BotDst, Mode);
  for X := 1 to LastPair do
  begin
    TU := TopU[X]; TV := TopV[X]; UU := CurU[X]; VV := CurV[X];
    AvgU := TlU + TU + LU + UU + 8;
    AvgV := TlV + TV + LV + VV + 8;
    D12U := (AvgU + 2 * (TU + LU)) shr 3;
    D12V := (AvgV + 2 * (TV + LV)) shr 3;
    D03U := (AvgU + 2 * (TlU + UU)) shr 3;
    D03V := (AvgV + 2 * (TlV + VV)) shr 3;
    EmitPixel(TopY[2 * X - 1], (D12U + TlU) shr 1, (D12V + TlV) shr 1,
              TopDst + (2 * X - 1) * Bpp, Mode);
    EmitPixel(TopY[2 * X], (D03U + TU) shr 1, (D03V + TV) shr 1,
              TopDst + (2 * X) * Bpp, Mode);
    if BotDst <> nil then
    begin
      EmitPixel(BotY[2 * X - 1], (D03U + LU) shr 1, (D03V + LV) shr 1,
                BotDst + (2 * X - 1) * Bpp, Mode);
      EmitPixel(BotY[2 * X], (D12U + UU) shr 1, (D12V + VV) shr 1,
                BotDst + (2 * X) * Bpp, Mode);
    end;
    TlU := TU; TlV := TV; LU := UU; LV := VV;
  end;
  if (W and 1) = 0 then
  begin
    EmitPixel(TopY[W - 1], (3 * TlU + LU + 2) shr 2, (3 * TlV + LV + 2) shr 2,
              TopDst + (W - 1) * Bpp, Mode);
    if BotDst <> nil then
      EmitPixel(BotY[W - 1], (3 * LU + TlU + 2) shr 2, (3 * LV + TlV + 2) shr 2,
                BotDst + (W - 1) * Bpp, Mode);
  end;
end;

// ============================================================
// VP8 FRAME DECODE
// ============================================================

function VP8DecodeFrame(var D: TVP8Decoder): Boolean;
var
  mby, mbx: Integer;
  hasTop, hasLeft: Boolean;
  partIdx: Integer;
  mb: ^TVP8MBData;
  br: ^TVP8Rd;
  info: PVP8MB;
  y, ix, iy: Integer;
  topCtx: PByte;    // pointer into D.IntraT for current macroblock's 4 columns
  ymode: Integer;
  leftMode: Integer;  // running left context for I4x4 mode parsing
  yBase, uBase, vBase: PByte;
  j, py, CHc: Integer;
  botY, botOut: PByte;
  EffSkip: Boolean;
begin
  Result := False;

  yBase := @D.YuvBuf[Y_OFF];
  uBase := @D.YuvBuf[U_OFF];
  vBase := @D.YuvBuf[V_OFF];

  for mby := 0 to D.MbH-1 do
  begin
    hasTop := (mby > 0);

    // --- Reset left-column context for this row (mirrors VP8InitScanline) ---
    // Left col-(-1) for Y rows 0..15 and U/V rows 0..7
    for j := 0 to 15 do (yBase + j * BPS - 1)^ := 129;
    for j := 0 to  7 do begin (uBase + j * BPS - 1)^ := 129; (vBase + j * BPS - 1)^ := 129; end;

    // Top-left corner and top row initialisation
    if mby = 0 then
    begin
      // First row: no top context → fill top row + top-left with 127
      FillChar((yBase - BPS - 1)^, 16 + 4 + 1, 127);
      FillChar((uBase - BPS - 1)^, 8 + 1, 127);
      FillChar((vBase - BPS - 1)^, 8 + 1, 127);
    end else
    begin
      // Not first row: top-left corner = 129 (border value)
      (yBase - BPS - 1)^ := 129;
      (uBase - BPS - 1)^ := 129;
      (vBase - BPS - 1)^ := 129;
    end;

    // VP8InitScanline: reset left NZ and left intra context
    D.MBInfo^.NZ   := 0;
    D.MBInfo^.NZDC := 0;
    FillChar(D.IntraL, SizeOf(D.IntraL), B_DC_PRED);

    // Token partition for this row (all MBs in a row use the same partition)
    partIdx := mby mod D.NumParts;

    for mbx := 0 to D.MbW-1 do
    begin
      hasLeft := (mbx > 0);

      // --- Rotate right column → left column (left context for this MB) ---
      // Mirrors C's Copy32b(y_dst[j*BPS-4], y_dst[j*BPS+12]) for j=-1..15
      if mbx > 0 then
      begin
        for j := -1 to 15 do (yBase + j * BPS - 1)^ := (yBase + j * BPS + 15)^;
        for j := -1 to  7 do
        begin
          (uBase + j * BPS - 1)^ := (uBase + j * BPS + 7)^;
          (vBase + j * BPS - 1)^ := (vBase + j * BPS + 7)^;
        end;
      end;

      // --- Copy top-row samples into the buffer (needed by I4x4 prediction) ---
      // Mirrors C's memcpy(y_dst-BPS, top_yuv[mb_x].y, 16)
      if hasTop then
      begin
        Move((D.YTopBuf + mbx * 16)^, (yBase - BPS)^, 16);
        Move((D.UTopBuf + mbx *  8)^, (uBase - BPS)^,  8);
        Move((D.VTopBuf + mbx *  8)^, (vBase - BPS)^,  8);
        // Top-right 4 pixels (extend top row beyond the 16-pixel MB width)
        if mbx < D.MbW - 1 then
          Move((D.YTopBuf + (mbx + 1) * 16)^, (yBase - BPS + 16)^, 4)
        else
          FillChar((yBase - BPS + 16)^, 4, (D.YTopBuf + mbx * 16 + 15)^);
      end;
      // Replicate top-right to rows 3/7/11 in the buffer — always, for I4x4
      // (C: top_right[k*BPS] = top_right[0] where top_right is uint32_t*,
      //  stride = BPS * sizeof(uint32_t) = 128 bytes each step)
      PCardinal(yBase + 3  * BPS + 16)^ := PCardinal(yBase - BPS + 16)^;
      PCardinal(yBase + 7  * BPS + 16)^ := PCardinal(yBase - BPS + 16)^;
      PCardinal(yBase + 11 * BPS + 16)^ := PCardinal(yBase - BPS + 16)^;

      mb  := @D.MBData;
      info := PVP8MB(NativeUInt(D.MBInfo) + (mbx+1)*SizeOf(TVP8MB));
      topCtx := D.IntraT + mbx * 4;

      // --- Parse intra modes from partition 0 ---
      br := @D.BR;

      // Segment ID — balanced binary tree (VP8 spec §9.3):
      //   bit0=0 → {0,1} via prob[1];  bit0=1 → {2,3} via prob[2]
      // Always consumes exactly 2 bits when update_map is set.
      if D.SegHdr.UseSegment and D.SegHdr.UpdateMap then
      begin
        if VP8RdGetBit(br^, D.SegHdr.SegProbs[0]) = 0 then
          mb^.Segment := VP8RdGetBit(br^, D.SegHdr.SegProbs[1])
        else
          mb^.Segment := 2 + VP8RdGetBit(br^, D.SegHdr.SegProbs[2]);
      end else
        mb^.Segment := 0;

      // Skip flag (read from partition 0 when use_skip_proba is set)
      if D.UseSkipProba then
        mb^.Skip := VP8RdGetBit(br^, D.SkipP) <> 0
      else
        mb^.Skip := False;

      // Intra mode
      mb^.IsI4x4 := VP8RdGetBit(br^, 145) = 0;
      if not mb^.IsI4x4 then
      begin
        ymode := ParseIntra16Mode(br^);
        // Fill all 16 sub-modes and update top/left context
        for ix := 0 to 15 do mb^.IModes[ix] := ymode;
        // Update IntraT (4 columns) and IntraL (4 rows)
        for ix := 0 to 3 do topCtx[ix] := ymode;
        for iy := 0 to 3 do D.IntraL[iy] := ymode;
      end else
      begin
        // I4x4: read 16 modes with proper top/left context
        // leftMode is the running left-neighbour mode, updated per-pixel (like
        // C's `ymode` variable in ParseIntraMode).
        for iy := 0 to 3 do
        begin
          leftMode := D.IntraL[iy];
          for ix := 0 to 3 do
          begin
            y := ParseIntra4x4Mode(br^,
              kBModesProba[topCtx[ix], leftMode]);
            mb^.IModes[iy*4 + ix] := y;
            topCtx[ix] := y;
            leftMode := y;
          end;
          D.IntraL[iy] := leftMode;  // = last decoded mode in this row
        end;
      end;
      mb^.UVMode := ParseUVMode(br^);

      // --- Residuals from AC partition ---
      if not mb^.Skip then
      begin
        VP8ParseResiduals(D, mbx, D.Parts[partIdx], partIdx);
      end else
      begin
        FillChar(mb^.Coeffs[0], SizeOf(mb^.Coeffs), 0);
        mb^.NonZeroY  := 0;
        mb^.NonZeroUV := 0;
        // Clear NZ context for both left and current-column slots (mirrors C's
        // VP8DecodeMB skip path). The DC (Y2) context must only be cleared for
        // I16x16 blocks — I4x4 blocks have no Y2, so their nz_dc context is left
        // untouched. Failing to clear left->nz_dc on an I16x16 skip leaves a
        // stale value that corrupts the Y2 context of a later I16x16 MB.
        D.MBInfo^.NZ := 0;   // left->nz_
        info^.NZ := 0;       // mb->nz_
        if not mb^.IsI4x4 then
        begin
          D.MBInfo^.NZDC := 0;  // left->nz_dc_
          info^.NZDC := 0;      // mb->nz_dc_
        end;
      end;

      // --- Reconstruct YUV ---
      VP8ReconstructMB(D, mbx, hasTop, hasLeft);

      // Record per-MB deblocking strength. Effective skip = no non-zero coeffs;
      // such MBs do not get their inner edges filtered.
      EffSkip := (mb^.NonZeroY = 0) and (mb^.NonZeroUV = 0);
      ComputeFInfo(D, mb^.Segment, mb^.IsI4x4, EffSkip,
                   (D.FInfo + (mby * D.MbW + mbx))^);

      // Copy reconstructed MB into full-frame YUV planes (MB-padded).
      // RGB conversion + loop filter run after the whole frame is reconstructed.
      for y := 0 to 15 do
        Move((@D.YuvBuf[Y_OFF + y * BPS])^,
             (D.YPlane + (mby * 16 + y) * D.YStride + mbx * 16)^, 16);
      for y := 0 to 7 do
      begin
        Move((@D.YuvBuf[U_OFF + y * BPS])^,
             (D.UPlane + (mby * 8 + y) * D.UVStride + mbx * 8)^, 8);
        Move((@D.YuvBuf[V_OFF + y * BPS])^,
             (D.VPlane + (mby * 8 + y) * D.UVStride + mbx * 8)^, 8);
      end;
    end;
  end;
  // Deblocking loop filter over the reconstructed planes (post-process pass).
  if D.FilterType > 0 then
    for py := 0 to D.MbH - 1 do
      for j := 0 to D.MbW - 1 do
        DoFilterMB(D, j, py);

  // Convert YUV planes to RGB with fancy (bilinear) chroma upsampling.
  CHc := (D.PicHeight + 1) div 2;
  // Row 0: chroma row 0 mirrored (no row above).
  UpsampleRowPair(D.YPlane, nil, D.UPlane, D.VPlane, D.UPlane, D.VPlane,
                  D.OutBuf, nil, D.PicWidth, D.OutputMode, D.OutBpp);
  for j := 1 to CHc - 1 do
  begin
    if 2 * j <= D.PicHeight - 1 then
    begin
      botY   := D.YPlane + (2 * j) * D.YStride;
      botOut := D.OutBuf + (2 * j) * D.OutStride;
    end
    else
    begin
      botY := nil; botOut := nil;
    end;
    UpsampleRowPair(
      D.YPlane + (2 * j - 1) * D.YStride, botY,
      D.UPlane + (j - 1) * D.UVStride, D.VPlane + (j - 1) * D.UVStride,
      D.UPlane + j * D.UVStride, D.VPlane + j * D.UVStride,
      D.OutBuf + (2 * j - 1) * D.OutStride, botOut,
      D.PicWidth, D.OutputMode, D.OutBpp);
  end;
  // Even height: final row uses the last chroma row mirrored (no row below).
  if (D.PicHeight and 1) = 0 then
    UpsampleRowPair(D.YPlane + (D.PicHeight - 1) * D.YStride, nil,
                    D.UPlane + (CHc - 1) * D.UVStride, D.VPlane + (CHc - 1) * D.UVStride,
                    D.UPlane + (CHc - 1) * D.UVStride, D.VPlane + (CHc - 1) * D.UVStride,
                    D.OutBuf + (D.PicHeight - 1) * D.OutStride, nil,
                    D.PicWidth, D.OutputMode, D.OutBpp);

  Result := True;
end;

// ============================================================
// VP8 FRAME HEADER PARSING
// ============================================================

function VP8ParseHeaders(var D: TVP8Decoder; Data: PByte; Size: NativeUInt): Boolean;
var
  tmp: Cardinal;
  partLen: Cardinal;
  dataBR: TVP8Rd;
  w, h: Integer;
  partData: PByte;
  szPtr:    PByte;
  partSize: NativeUInt;
  i: Integer;
begin
  Result := False;
  if Size < 10 then Exit;

  // 3-byte frame header
  tmp := PByte(Data)[0] or (Cardinal(PByte(Data)[1]) shl 8) or
         (Cardinal(PByte(Data)[2]) shl 16);
  D.KeyFrame := (tmp and 1) = 0;
  D.Profile  := (tmp shr 1) and 7;
  // show_frame = (tmp shr 4) and 1;
  partLen    := (tmp shr 5) and $7FFFF;

  if not D.KeyFrame then Exit;  // we only support key frames

  // 3-byte start code
  if (Data[3] <> $9D) or (Data[4] <> $01) or (Data[5] <> $2A) then Exit;

  // Width/Height
  w := (Data[6] or (Cardinal(Data[7]) shl 8)) and $3FFF;
  h := (Data[8] or (Cardinal(Data[9]) shl 8)) and $3FFF;
  D.PicWidth  := w;
  D.PicHeight := h;
  D.MbW       := (w + 15) shr 4;
  D.MbH       := (h + 15) shr 4;

  D.PartLen0 := partLen;

  // Partition 0: starts at Data+10 (after 3-byte frame tag + 7-byte picture header)
  // Length = partLen (= first_part_size from the frame tag, excludes picture header)
  VP8RdInit(D.BR, Data + 10, partLen);

  // Parse header fields from partition 0
  if VP8RdGet(D.BR) <> 0 then Exit; // color_space must be 0
  VP8RdGet(D.BR); // clamp_type (ignored)

  VP8ParseSegmentHeader(D.BR, D.SegHdr);
  VP8ParseFilterHeader(D.BR, D);
  // Number of token partitions: 2^n (n = 2-bit value)
  D.NumParts := 1 shl Integer(VP8RdGetValue(D.BR, 2));
  VP8ParseQuant(D.BR, D);
  VP8RdGet(D.BR); // update_proba bit — read and ignore (not an error if 1)
  VP8ParseProba(D.BR, D);  // also reads use_skip_proba/skip_p at the end

  // Token partition data starts immediately after partition 0.
  // Layout: [(NumParts-1) × 3-byte sizes][part0 data][part1 data]...
  // partData → size table entries; szPtr → pointer advancing through sizes
  partData := Data + 10 + partLen;           // start of token area (= size table)
  szPtr    := partData;                       // walks through 3-byte size entries
  partData := partData + NativeUInt(D.NumParts - 1) * 3;  // start of actual data
  for i := 0 to D.NumParts - 2 do
  begin
    partSize := szPtr[0] or (Cardinal(szPtr[1]) shl 8) or
                (Cardinal(szPtr[2]) shl 16);
    Inc(szPtr, 3);
    VP8RdInit(D.Parts[i], partData, partSize);
    Inc(partData, partSize);
  end;
  // Last partition: rest of the VP8 chunk
  if NativeUInt(partData) < NativeUInt(Data + Size) then
    partSize := NativeUInt(Data + Size) - NativeUInt(partData)
  else
    partSize := 0;
  VP8RdInit(D.Parts[D.NumParts-1], partData, partSize);

  Result := True;
end;

// ============================================================
// VP8L (LOSSLESS) DECODER
// ============================================================
// Implements 2-level Huffman, colour cache, meta-Huffman entropy image, and
// the four inverse transforms (predictor, cross-colour, subtract-green,
// colour-indexing).

const
  ARGB_BLACK               = Cardinal($FF000000);
  PREDICTOR_TRANSFORM      = 0;
  CROSS_COLOR_TRANSFORM    = 1;
  SUBTRACT_GREEN           = 2;
  COLOR_INDEXING_TRANSFORM = 3;
  CODE_TO_PLANE_CODES      = 120;
  NUM_LITERAL_CODES        = 256;
  NUM_LENGTH_CODES         = 24;
  MAX_VP8L_ALPHABET        = NUM_LITERAL_CODES + NUM_LENGTH_CODES + 2048; // green + max cache
  MAX_SINGLE_HUFF_TABLE    = 4096;   // upper bound on one built table (green@cc=11 ~2704)
  HASH_MUL                 = Cardinal($1E35A7BD);

type
  TVP8LTransform = record
    XForm: Integer;     // transform type
    Bits:  Integer;     // subsample / packing bits
    XSize: Integer;     // window width  (full, pre-packing)
    YSize: Integer;     // window height
    Data:  PCardinal;   // owned transform data (palette / sub-image)
  end;

  THTreeGroup = record
    HTrees: array[0..4] of PHuffmanCode;  // each a separate allocation
  end;

  TVP8LMeta = record
    HuffmanImage:   PCardinal;          // entropy image (group index per tile), owned
    HuffmanXSize:   Integer;
    HuffmanSubBits: Integer;            // 0 => single group
    HTreeGroups:    array of THTreeGroup;
    ColorCacheBits: Integer;            // 0 => no cache
    ColorCache:     PCardinal;          // 1<<bits entries, owned
  end;

  TVP8LState = record
    BR:            TVP8LBitReader;
    Transforms:    array[0..3] of TVP8LTransform;
    NumTransforms: Integer;
  end;

// ---- small helpers ---------------------------------------------------------

function VP8LSubSampleSize(Size, Bits: Integer): Integer; inline;
begin
  Result := (Size + (1 shl Bits) - 1) shr Bits;
end;

function VP8LAddPixels(A, B: Cardinal): Cardinal; inline;
var AlphaGreen, RedBlue: Cardinal;
begin
  AlphaGreen := (A and $FF00FF00) + (B and $FF00FF00);
  RedBlue    := (A and $00FF00FF) + (B and $00FF00FF);
  Result := (AlphaGreen and $FF00FF00) or (RedBlue and $00FF00FF);
end;

function Average2(A, B: Cardinal): Cardinal; inline;
begin
  Result := (((A xor B) and $FEFEFEFE) shr 1) + (A and B);
end;

function AddSubFull(A, B, C: Integer): Integer; inline;
begin
  Result := Clip8b(A + B - C);
end;

function AddSubHalf(A, B: Integer): Integer; inline;
begin
  Result := Clip8b(A + (A - B) div 2);
end;

function ClampedAddSubtractFull(C0, C1, C2: Cardinal): Cardinal; inline;
var A, R, G, B: Integer;
begin
  A := AddSubFull((C0 shr 24) and $ff, (C1 shr 24) and $ff, (C2 shr 24) and $ff);
  R := AddSubFull((C0 shr 16) and $ff, (C1 shr 16) and $ff, (C2 shr 16) and $ff);
  G := AddSubFull((C0 shr  8) and $ff, (C1 shr  8) and $ff, (C2 shr  8) and $ff);
  B := AddSubFull( C0         and $ff,  C1         and $ff,  C2         and $ff);
  Result := (Cardinal(A) shl 24) or (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or Cardinal(B);
end;

function ClampedAddSubtractHalf(C0, C1, C2: Cardinal): Cardinal; inline;
var Ave: Cardinal; A, R, G, B: Integer;
begin
  Ave := Average2(C0, C1);
  A := AddSubHalf((Ave shr 24) and $ff, (C2 shr 24) and $ff);
  R := AddSubHalf((Ave shr 16) and $ff, (C2 shr 16) and $ff);
  G := AddSubHalf((Ave shr  8) and $ff, (C2 shr  8) and $ff);
  B := AddSubHalf( Ave         and $ff,  C2         and $ff);
  Result := (Cardinal(A) shl 24) or (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or Cardinal(B);
end;

function Sub3(A, B, C: Integer): Integer; inline;
begin
  Result := Abs(B - C) - Abs(A - C);
end;

function VP8LSelect(A, B, C: Cardinal): Cardinal; inline; // A=top, B=left, C=top-left
var PaMinusPb: Integer;
begin
  PaMinusPb :=
    Sub3((A shr 24) and $ff, (B shr 24) and $ff, (C shr 24) and $ff) +
    Sub3((A shr 16) and $ff, (B shr 16) and $ff, (C shr 16) and $ff) +
    Sub3((A shr  8) and $ff, (B shr  8) and $ff, (C shr  8) and $ff) +
    Sub3( A         and $ff,  B         and $ff,  C         and $ff);
  if PaMinusPb <= 0 then Result := A else Result := B;
end;

// Predict an ARGB value from neighbours L=left, T=top, TL=top-left, TR=top-right.
function VP8LPredict(Mode: Integer; L, T, TL, TR: Cardinal): Cardinal;
begin
  case Mode of
    0:  Result := ARGB_BLACK;
    1:  Result := L;
    2:  Result := T;
    3:  Result := TR;
    4:  Result := TL;
    5:  Result := Average2(Average2(L, TR), T);
    6:  Result := Average2(L, TL);
    7:  Result := Average2(L, T);
    8:  Result := Average2(TL, T);
    9:  Result := Average2(T, TR);
    10: Result := Average2(Average2(L, TL), Average2(T, TR));
    11: Result := VP8LSelect(T, L, TL);
    12: Result := ClampedAddSubtractFull(L, T, TL);
    13: Result := ClampedAddSubtractHalf(L, T, TL);
  else  Result := ARGB_BLACK;
  end;
end;

function ColorTransformDelta(PredByte, ColorByte: Integer): Integer; inline;
begin
  Result := SarI(ShortInt(PredByte) * ShortInt(ColorByte), 5);
end;

// ---- the colour cache ------------------------------------------------------

procedure VP8LCacheInsert(Cache: PCardinal; HashShift: Integer; Argb: Cardinal); inline;
begin
  // The Cardinal() cast forces the 32-bit wraparound C relies on; without it
  // FPC widens the product to 64-bit and the shifted index goes out of range.
  Cache[Cardinal(HASH_MUL * Argb) shr HashShift] := Argb;
end;

// ---- inverse transforms ----------------------------------------------------

procedure InvSubtractGreen(Pix: PCardinal; NumPixels: Integer);
var I: Integer; Argb, Green, RedBlue: Cardinal;
begin
  for I := 0 to NumPixels - 1 do
  begin
    Argb    := Pix[I];
    Green   := (Argb shr 8) and $ff;
    RedBlue := Argb and $00FF00FF;
    RedBlue := (RedBlue + ((Green shl 16) or Green)) and $00FF00FF;
    Pix[I]  := (Argb and $FF00FF00) or RedBlue;
  end;
end;

procedure InvPredictor(Pix: PCardinal; const T: TVP8LTransform);
var
  W, H, Bits, TilesPerRow, X, Y, Mode, Idx: Integer;
  ModeRow: PCardinal;
begin
  W := T.XSize; H := T.YSize; Bits := T.Bits;
  TilesPerRow := VP8LSubSampleSize(W, Bits);
  // Row 0: (0,0) uses black, the rest use the Left predictor.
  Pix[0] := VP8LAddPixels(Pix[0], ARGB_BLACK);
  for X := 1 to W - 1 do
    Pix[X] := VP8LAddPixels(Pix[X], Pix[X - 1]);
  for Y := 1 to H - 1 do
  begin
    Idx := Y * W;
    // Column 0 uses the Top predictor.
    Pix[Idx] := VP8LAddPixels(Pix[Idx], Pix[Idx - W]);
    ModeRow := T.Data + (Y shr Bits) * TilesPerRow;
    for X := 1 to W - 1 do
    begin
      Mode := (ModeRow[X shr Bits] shr 8) and $0f;
      Idx  := Y * W + X;
      Pix[Idx] := VP8LAddPixels(Pix[Idx],
        VP8LPredict(Mode, Pix[Idx - 1], Pix[Idx - W], Pix[Idx - W - 1], Pix[Idx - W + 1]));
    end;
  end;
end;

procedure InvCrossColor(Pix: PCardinal; const T: TVP8LTransform);
var
  W, H, Bits, TilesPerRow, X, Y, Idx: Integer;
  M: Cardinal; GreenToRed, GreenToBlue, RedToBlue, Green, NewRed, NewBlue: Integer;
  ModeRow: PCardinal; Argb: Cardinal;
begin
  W := T.XSize; H := T.YSize; Bits := T.Bits;
  TilesPerRow := VP8LSubSampleSize(W, Bits);
  for Y := 0 to H - 1 do
  begin
    ModeRow := T.Data + (Y shr Bits) * TilesPerRow;
    for X := 0 to W - 1 do
    begin
      M := ModeRow[X shr Bits];
      GreenToRed  := M and $ff;
      GreenToBlue := (M shr 8) and $ff;
      RedToBlue   := (M shr 16) and $ff;
      Idx  := Y * W + X;
      Argb := Pix[Idx];
      Green   := (Argb shr 8) and $ff;
      NewRed  := (Argb shr 16) and $ff;
      NewBlue := Argb and $ff;
      NewRed  := (NewRed + ColorTransformDelta(GreenToRed, Green)) and $ff;
      NewBlue := NewBlue + ColorTransformDelta(GreenToBlue, Green);
      NewBlue := (NewBlue + ColorTransformDelta(RedToBlue, NewRed)) and $ff;
      Pix[Idx] := (Argb and $FF00FF00) or (Cardinal(NewRed) shl 16) or Cardinal(NewBlue);
    end;
  end;
end;

function ExpandColorMap(NumColors: Integer; var T: TVP8LTransform): Boolean;
var
  FinalNum, I: Integer;
  OldData, NewData: PByte;
  NewMap: PCardinal;
begin
  FinalNum := 1 shl (8 shr T.Bits);
  NewMap := AllocMem(FinalNum * 4);   // zero-filled tail
  NewData := PByte(NewMap);
  OldData := PByte(T.Data);
  NewMap[0] := T.Data[0];
  for I := 4 to 4 * NumColors - 1 do
    NewData[I] := Byte(OldData[I] + NewData[I - 4]);
  FreeMem(T.Data);
  T.Data := NewMap;
  Result := True;
end;

// Expand a colour-indexed (packed) image back to full width. Allocates a new
// buffer (width grows), frees the old one. CurW is updated to the full width.
function InvColorIndex(var Pix: PCardinal; const T: TVP8LTransform;
  var CurW: Integer): Boolean;
var
  W, H, Bits, BitsPerPixel, PixelsPerByte, CountMask, BitMask, PackedW: Integer;
  X, Y, Sp: Integer;
  Packed_: Cardinal;
  ColorMap, NewBuf, SrcRow, DstRow: PCardinal;
begin
  W := T.XSize; H := T.YSize; Bits := T.Bits;
  ColorMap := T.Data;
  BitsPerPixel := 8 shr Bits;
  NewBuf := AllocMem(W * H * 4);
  if BitsPerPixel = 8 then
  begin
    for Y := 0 to H - 1 do
      for X := 0 to W - 1 do
        NewBuf[Y * W + X] := ColorMap[(Pix[Y * W + X] shr 8) and $ff];
  end
  else
  begin
    PixelsPerByte := 1 shl Bits;
    CountMask := PixelsPerByte - 1;
    BitMask   := (1 shl BitsPerPixel) - 1;
    PackedW   := VP8LSubSampleSize(W, Bits);
    for Y := 0 to H - 1 do
    begin
      SrcRow := Pix + Y * PackedW;
      DstRow := NewBuf + Y * W;
      Packed_ := 0; Sp := 0;
      for X := 0 to W - 1 do
      begin
        if (X and CountMask) = 0 then
        begin
          Packed_ := (SrcRow[Sp] shr 8) and $ff;
          Inc(Sp);
        end;
        DstRow[X] := ColorMap[Packed_ and Cardinal(BitMask)];
        Packed_ := Packed_ shr BitsPerPixel;
      end;
    end;
  end;
  FreeMem(Pix);
  Pix  := NewBuf;
  CurW := W;
  Result := True;
end;

// ---- Huffman code reading --------------------------------------------------

procedure FreeMeta(var M: TVP8LMeta);
var I, J: Integer;
begin
  if M.HuffmanImage <> nil then begin FreeMem(M.HuffmanImage); M.HuffmanImage := nil; end;
  for I := 0 to High(M.HTreeGroups) do
    for J := 0 to 4 do
      if M.HTreeGroups[I].HTrees[J] <> nil then
      begin
        FreeMem(M.HTreeGroups[I].HTrees[J]);
        M.HTreeGroups[I].HTrees[J] := nil;
      end;
  SetLength(M.HTreeGroups, 0);
  if M.ColorCache <> nil then begin FreeMem(M.ColorCache); M.ColorCache := nil; end;
end;

// Decode the per-symbol code lengths driven by the 19-entry code-length code.
function VP8LReadHuffmanCodeLengths(ClCodeLengths: PInteger;
  NumSymbols: Integer; CodeLengths: PInteger; Sorted: PWord;
  var BR: TVP8LBitReader): Boolean;
var
  ClTable: array[0..255] of THuffmanCode;   // cl codes are <=7 bits, root=8 -> no 2nd level
  ClSorted: array[0..18] of Word;
  MaxSymbol, Symbol, CodeLen, LengthNBits: Integer;
  PrevCodeLen, ExtraBits, RepeatOffset, Repeat_, LengthVal: Integer;
begin
  Result := False;
  PrevCodeLen := 8;
  // Zero first: an incomplete code-length code leaves root slots unset, and a
  // garbage Bits>root would make VP8LReadSymbol chase a bogus 2nd-level pointer.
  FillChar(ClTable, SizeOf(ClTable), 0);
  if VP8LBuildHuffmanTable(@ClTable[0], HUFFMAN_TABLE_BITS, ClCodeLengths, 19, @ClSorted[0]) = 0 then Exit;
  if VP8LReadBits(BR, 1) <> 0 then
  begin
    LengthNBits := 2 + 2 * Integer(VP8LReadBits(BR, 3));
    MaxSymbol := 2 + Integer(VP8LReadBits(BR, LengthNBits));
    if MaxSymbol > NumSymbols then Exit;
  end
  else
    MaxSymbol := NumSymbols;
  Symbol := 0;
  while Symbol < NumSymbols do
  begin
    if MaxSymbol = 0 then Break;
    Dec(MaxSymbol);
    CodeLen := VP8LReadSymbol(@ClTable[0], BR);
    if CodeLen < 16 then
    begin
      CodeLengths[Symbol] := CodeLen; Inc(Symbol);
      if CodeLen <> 0 then PrevCodeLen := CodeLen;
    end
    else
    begin
      case CodeLen - 16 of
        0: begin ExtraBits := 2; RepeatOffset := 3;  end;
        1: begin ExtraBits := 3; RepeatOffset := 3;  end;
      else  begin ExtraBits := 7; RepeatOffset := 11; end;
      end;
      Repeat_ := Integer(VP8LReadBits(BR, ExtraBits)) + RepeatOffset;
      if Symbol + Repeat_ > NumSymbols then Exit;
      if CodeLen = 16 then LengthVal := PrevCodeLen else LengthVal := 0;
      while Repeat_ > 0 do
      begin
        CodeLengths[Symbol] := LengthVal; Inc(Symbol); Dec(Repeat_);
      end;
    end;
  end;
  Result := True;
end;

// Read one Huffman code into a freshly-allocated table. Returns the built
// table (caller frees) and its entry count, or nil/0 on error. Scratch is a
// reusable build buffer of MAX_SINGLE_HUFF_TABLE entries.
function VP8LReadHuffmanCode(Alphabet: Integer; Scratch: PHuffmanCode;
  CodeLengths: PInteger; Sorted: PWord; var BR: TVP8LBitReader;
  out Table: PHuffmanCode): Integer;
var
  NumSymbols, FirstLenCode, Sym, I, NumCodes, Size: Integer;
  ClLengths: array[0..18] of Integer;
begin
  Result := 0; Table := nil;
  FillChar(CodeLengths^, Alphabet * SizeOf(Integer), 0);
  FillChar(Scratch^, MAX_SINGLE_HUFF_TABLE * SizeOf(THuffmanCode), 0);
  if VP8LReadBits(BR, 1) <> 0 then        // simple code
  begin
    NumSymbols   := Integer(VP8LReadBits(BR, 1)) + 1;
    FirstLenCode := Integer(VP8LReadBits(BR, 1));
    if FirstLenCode = 0 then Sym := Integer(VP8LReadBits(BR, 1))
    else Sym := Integer(VP8LReadBits(BR, 8));
    if Sym >= Alphabet then Exit;
    CodeLengths[Sym] := 1;
    if NumSymbols = 2 then
    begin
      Sym := Integer(VP8LReadBits(BR, 8));
      if Sym >= Alphabet then Exit;
      CodeLengths[Sym] := 1;
    end;
  end
  else                                    // normal code
  begin
    FillChar(ClLengths, SizeOf(ClLengths), 0);
    NumCodes := Integer(VP8LReadBits(BR, 4)) + 4;
    for I := 0 to NumCodes - 1 do
      ClLengths[kCodeLengthCodeOrder[I]] := Integer(VP8LReadBits(BR, 3));
    if not VP8LReadHuffmanCodeLengths(@ClLengths[0], Alphabet, CodeLengths, Sorted, BR) then Exit;
  end;
  Size := VP8LBuildHuffmanTable(Scratch, HUFFMAN_TABLE_BITS, CodeLengths, Alphabet, Sorted);
  if (Size = 0) or (Size > MAX_SINGLE_HUFF_TABLE) then Exit;
  GetMem(Table, Size * SizeOf(THuffmanCode));
  Move(Scratch^, Table^, Size * SizeOf(THuffmanCode));
  Result := Size;
end;

// forward decl: ReadHuffmanCodes may recurse through DecodeImageStream
function VP8LDecodeImageStream(var XSize, YSize: Integer; IsLevel0: Boolean;
  var St: TVP8LState; out DecodedData: PCardinal): Boolean; forward;

function VP8LReadHuffmanCodes(XSize, YSize, ColorCacheBits: Integer;
  AllowRecursion: Boolean; var St: TVP8LState; var Meta: TVP8LMeta): Boolean;
var
  HuffImage: PCardinal;
  HuffPrecision, HuffXSize, HuffYSize, HuffPix: Integer;
  NumGroups, I, J, Grp, Alphabet, Size: Integer;
  CodeLengths: PInteger;
  Sorted: PWord;
  Scratch: PHuffmanCode;
  Tbl: PHuffmanCode;
begin
  Result := False;
  HuffImage := nil;
  NumGroups := 1;
  Meta.HuffmanSubBits := 0;
  Meta.HuffmanXSize := XSize;

  if AllowRecursion and (VP8LReadBits(St.BR, 1) <> 0) then
  begin
    HuffPrecision := Integer(VP8LReadBits(St.BR, 3)) + 2;
    HuffXSize := VP8LSubSampleSize(XSize, HuffPrecision);
    HuffYSize := VP8LSubSampleSize(YSize, HuffPrecision);
    HuffPix := HuffXSize * HuffYSize;
    if not VP8LDecodeImageStream(HuffXSize, HuffYSize, False, St, HuffImage) then Exit;
    Meta.HuffmanImage := HuffImage;
    Meta.HuffmanSubBits := HuffPrecision;
    Meta.HuffmanXSize := HuffXSize;
    for I := 0 to HuffPix - 1 do
    begin
      Grp := (Integer(HuffImage[I]) shr 8) and $ffff;
      HuffImage[I] := Cardinal(Grp);   // store bare group index for fast lookup
      if Grp >= NumGroups then NumGroups := Grp + 1;
    end;
    if NumGroups > 1000000 then Exit;  // sanity guard against absurd allocations
  end;

  SetLength(Meta.HTreeGroups, NumGroups);

  GetMem(CodeLengths, MAX_VP8L_ALPHABET * SizeOf(Integer));
  GetMem(Sorted, MAX_VP8L_ALPHABET * SizeOf(Word));
  GetMem(Scratch, MAX_SINGLE_HUFF_TABLE * SizeOf(THuffmanCode));
  try
    for I := 0 to NumGroups - 1 do
      for J := 0 to 4 do
      begin
        Alphabet := kAlphabetSize[J];
        if (J = 0) and (ColorCacheBits > 0) then Inc(Alphabet, 1 shl ColorCacheBits);
        Size := VP8LReadHuffmanCode(Alphabet, Scratch, CodeLengths, Sorted, St.BR, Tbl);
        if Size = 0 then Exit;
        Meta.HTreeGroups[I].HTrees[J] := Tbl;
      end;
    Result := True;
  finally
    FreeMem(CodeLengths);
    FreeMem(Sorted);
    FreeMem(Scratch);
  end;
end;

// ---- copy-distance / length prefix decoding --------------------------------

function GetCopyDistance(Sym: Integer; var BR: TVP8LBitReader): Integer; inline;
var ExtraBits, Offset: Integer;
begin
  if Sym < 4 then begin Result := Sym + 1; Exit; end;
  ExtraBits := (Sym - 2) shr 1;
  Offset := (2 + (Sym and 1)) shl ExtraBits;
  Result := Offset + Integer(VP8LReadBits(BR, ExtraBits)) + 1;
end;

function PlaneCodeToDistance(XSize, PlaneCode: Integer): Integer; inline;
var DistCode, YOff, XOff, Dist: Integer;
begin
  if PlaneCode > CODE_TO_PLANE_CODES then
  begin
    Result := PlaneCode - CODE_TO_PLANE_CODES;
    Exit;
  end;
  DistCode := kCodeToPlane[PlaneCode - 1];
  YOff := DistCode shr 4;
  XOff := 8 - (DistCode and $0f);
  Dist := YOff * XSize + XOff;
  if Dist >= 1 then Result := Dist else Result := 1;
end;

// ---- the main per-pixel decode loop ----------------------------------------

function VP8LDecodeImageData(var BR: TVP8LBitReader; var Meta: TVP8LMeta;
  Data: PCardinal; Width, Height: Integer): Boolean;
var
  NumPix, I, K, Col, Row, Grp: Integer;
  CacheSize, HashShift, LenCodeLimit, CacheLimit: Integer;
  Code, LengthSym, Length_, DistSym, DistCode, Dist: Integer;
  Red, Blue, Alpha: Integer;
  Cache: PCardinal;
  HTrees: ^THTreeGroup;
begin
  Result := False;
  NumPix := Width * Height;
  CacheSize := 0; HashShift := 0;
  if Meta.ColorCacheBits > 0 then
  begin
    CacheSize := 1 shl Meta.ColorCacheBits;
    HashShift := 32 - Meta.ColorCacheBits;
  end;
  Cache := Meta.ColorCache;
  LenCodeLimit := NUM_LITERAL_CODES + NUM_LENGTH_CODES;   // 280
  CacheLimit   := LenCodeLimit + CacheSize;

  Col := 0; Row := 0; I := 0;
  while I < NumPix do
  begin
    if Meta.HuffmanSubBits = 0 then Grp := 0
    else Grp := Integer(Meta.HuffmanImage[(Row shr Meta.HuffmanSubBits) * Meta.HuffmanXSize +
                                          (Col shr Meta.HuffmanSubBits)]);
    HTrees := @Meta.HTreeGroups[Grp];

    Code := VP8LReadSymbol(HTrees^.HTrees[0], BR);  // green channel / command
    if Code < NUM_LITERAL_CODES then          // literal ARGB pixel
    begin
      // green=Code, then read red/blue/alpha in this exact order. They must be
      // separate statements: as operands of one expression FPC may evaluate the
      // (side-effecting) reads in any order, desyncing the bitstream.
      Red   := VP8LReadSymbol(HTrees^.HTrees[1], BR);
      Blue  := VP8LReadSymbol(HTrees^.HTrees[2], BR);
      Alpha := VP8LReadSymbol(HTrees^.HTrees[3], BR);
      Data[I] := (Cardinal(Alpha) shl 24) or (Cardinal(Red) shl 16) or
                 (Cardinal(Code) shl 8) or Cardinal(Blue);
      if CacheSize > 0 then VP8LCacheInsert(Cache, HashShift, Data[I]);
      Inc(I); Inc(Col);
      if Col >= Width then begin Col := 0; Inc(Row); end;
    end
    else if Code < LenCodeLimit then          // backward reference
    begin
      LengthSym := Code - NUM_LITERAL_CODES;
      Length_   := GetCopyDistance(LengthSym, BR);   // length uses the same prefix coding
      DistSym   := VP8LReadSymbol(HTrees^.HTrees[4], BR);
      DistCode  := GetCopyDistance(DistSym, BR);
      Dist      := PlaneCodeToDistance(Width, DistCode);
      if (Dist < 1) or (I - Dist < 0) or (I + Length_ > NumPix) then Exit;  // corrupt
      for K := 0 to Length_ - 1 do
      begin
        Data[I + K] := Data[I + K - Dist];
        if CacheSize > 0 then VP8LCacheInsert(Cache, HashShift, Data[I + K]);
      end;
      Inc(I, Length_);
      Inc(Col, Length_);
      while Col >= Width do begin Dec(Col, Width); Inc(Row); end;
    end
    else if Code < CacheLimit then            // colour cache reference
    begin
      Data[I] := Cache[Code - LenCodeLimit];
      VP8LCacheInsert(Cache, HashShift, Data[I]);
      Inc(I); Inc(Col);
      if Col >= Width then begin Col := 0; Inc(Row); end;
    end
    else
      Exit;  // invalid symbol
  end;
  Result := True;
end;

// Decode one VP8L image stream: at level 0 it reads the transform list and may
// recurse for transform sub-images and the meta-Huffman entropy image. On
// return XSize/YSize hold the decoded buffer's dimensions (reduced for
// colour-indexing). DecodedData is a freshly-allocated XSize*YSize ARGB array.
function VP8LDecodeImageStream(var XSize, YSize: Integer; IsLevel0: Boolean;
  var St: TVP8LState; out DecodedData: PCardinal): Boolean;
var
  Meta: TVP8LMeta;
  T: ^TVP8LTransform;
  NumColors, Bits, TW, TH: Integer;
  Data: PCardinal;
begin
  Result := False;
  DecodedData := nil;
  FillChar(Meta, SizeOf(Meta), 0);
  Data := nil;

  // Transform list (level 0 only).
  if IsLevel0 then
    while VP8LReadBits(St.BR, 1) <> 0 do
    begin
      if St.NumTransforms >= 4 then Exit;
      T := @St.Transforms[St.NumTransforms];
      T^.XForm := Integer(VP8LReadBits(St.BR, 2));
      T^.XSize := XSize;
      T^.YSize := YSize;
      T^.Bits  := 0;
      T^.Data  := nil;
      Inc(St.NumTransforms);
      case T^.XForm of
        PREDICTOR_TRANSFORM, CROSS_COLOR_TRANSFORM:
        begin
          T^.Bits := Integer(VP8LReadBits(St.BR, 3)) + 2;
          TW := VP8LSubSampleSize(XSize, T^.Bits);
          TH := VP8LSubSampleSize(YSize, T^.Bits);
          if not VP8LDecodeImageStream(TW, TH, False, St, T^.Data) then Exit;
        end;
        SUBTRACT_GREEN: ;  // no data
        COLOR_INDEXING_TRANSFORM:
        begin
          NumColors := Integer(VP8LReadBits(St.BR, 8)) + 1;
          if NumColors > 16 then Bits := 0
          else if NumColors > 4 then Bits := 1
          else if NumColors > 2 then Bits := 2
          else Bits := 3;
          T^.Bits := Bits;
          XSize := VP8LSubSampleSize(XSize, Bits);
          TW := NumColors; TH := 1;
          if not VP8LDecodeImageStream(TW, TH, False, St, T^.Data) then Exit;
          if not ExpandColorMap(NumColors, T^) then Exit;
        end;
      else
        Exit;  // invalid transform type
      end;
    end;

  // Optional colour cache.
  if VP8LReadBits(St.BR, 1) <> 0 then
  begin
    Meta.ColorCacheBits := Integer(VP8LReadBits(St.BR, 4));
    if (Meta.ColorCacheBits < 1) or (Meta.ColorCacheBits > 11) then begin FreeMeta(Meta); Exit; end;
  end;

  // Huffman codes (meta-Huffman recursion allowed at level 0).
  if not VP8LReadHuffmanCodes(XSize, YSize, Meta.ColorCacheBits, IsLevel0, St, Meta) then
  begin FreeMeta(Meta); Exit; end;

  if Meta.ColorCacheBits > 0 then
    Meta.ColorCache := AllocMem((1 shl Meta.ColorCacheBits) * SizeOf(Cardinal));

  Data := AllocMem(XSize * YSize * SizeOf(Cardinal));
  if not VP8LDecodeImageData(St.BR, Meta, Data, XSize, YSize) then
  begin FreeMem(Data); FreeMeta(Meta); Exit; end;

  FreeMeta(Meta);
  DecodedData := Data;
  Result := True;
end;

// Decode a level-0 image whose bit reader is already positioned at the start of
// the image stream, then apply the inverse transforms. Pix is a fresh W*H ARGB
// array (caller frees). Transform data stays in St for VP8LFreeTransforms.
function VP8LDecodeToArgb(var St: TVP8LState; W, H: Integer;
  out Pix: PCardinal): Boolean;
var
  CurW, CurH, N: Integer;
  T: ^TVP8LTransform;
begin
  Result := False;
  Pix := nil;
  CurW := W; CurH := H;
  if not VP8LDecodeImageStream(CurW, CurH, True, St, Pix) then Exit;
  // Apply inverse transforms in reverse order of declaration.
  for N := St.NumTransforms - 1 downto 0 do
  begin
    T := @St.Transforms[N];
    case T^.XForm of
      SUBTRACT_GREEN:           InvSubtractGreen(Pix, T^.XSize * T^.YSize);
      PREDICTOR_TRANSFORM:      InvPredictor(Pix, T^);
      CROSS_COLOR_TRANSFORM:    InvCrossColor(Pix, T^);
      COLOR_INDEXING_TRANSFORM: if not InvColorIndex(Pix, T^, CurW) then Exit;
    end;
  end;
  Result := True;
end;

procedure VP8LFreeTransforms(var St: TVP8LState);
var N: Integer;
begin
  for N := 0 to St.NumTransforms - 1 do
    if St.Transforms[N].Data <> nil then
    begin
      FreeMem(St.Transforms[N].Data);
      St.Transforms[N].Data := nil;
    end;
end;

// Decode a lossless-compressed ALPH chunk: the alpha plane is carried in the
// green channel of a headerless VP8L image (no signature/size; dimensions come
// from the main image). Returns a fresh W*H byte plane, or nil on failure.
function VP8LDecodeAlphaPlane(AlphData: PByte; AlphSize: NativeUInt;
  W, H: Integer): PByte;
var
  St: TVP8LState;
  Pix: PCardinal;
  Plane: PByte;
  I: Integer;
begin
  Result := nil;
  if (AlphData = nil) or (AlphSize < 2) or (W <= 0) or (H <= 0) then Exit;
  FillChar(St, SizeOf(St), 0);
  VP8LInitBitReader(St.BR, AlphData + 1, AlphSize - 1);  // skip 1-byte ALPH header
  Pix := nil;
  try
    if not VP8LDecodeToArgb(St, W, H, Pix) then Exit;
    Plane := AllocMem(W * H);
    for I := 0 to W * H - 1 do
      Plane[I] := (Pix[I] shr 8) and $ff;   // alpha stored in the green channel
    Result := Plane;
  finally
    if Pix <> nil then FreeMem(Pix);
    VP8LFreeTransforms(St);
  end;
end;

// Public VP8L entry point: parse the signature + header, decode the level-0
// image, apply the inverse transforms, and emit straight-alpha RGBA bytes.
function VP8LDecode(Data: PByte; Size: NativeUInt;
  out PixBuf: PByte; out Width, Height: Integer): Boolean;
var
  St: TVP8LState;
  W, H, Version, I: Integer;
  Pix: PCardinal;
  Argb: Cardinal;
begin
  Result := False;
  PixBuf := nil;
  Width  := 0;
  Height := 0;
  if Size < 5 then Exit;
  if Data[0] <> $2F then Exit;          // VP8L signature byte
  FillChar(St, SizeOf(St), 0);
  VP8LInitBitReader(St.BR, Data + 1, Size - 1);
  W := Integer(VP8LReadBits(St.BR, 14)) + 1;
  H := Integer(VP8LReadBits(St.BR, 14)) + 1;
  VP8LReadBits(St.BR, 1);               // alpha_is_used (ignored)
  Version := Integer(VP8LReadBits(St.BR, 3));
  Pix := nil;
  try
    if Version <> 0 then Exit;
    Width := W; Height := H;
    if not VP8LDecodeToArgb(St, W, H, Pix) then Exit;
    // Pack ARGB cardinals into straight-alpha RGBA bytes.
    PixBuf := AllocMem(W * H * 4);
    for I := 0 to W * H - 1 do
    begin
      Argb := Pix[I];
      PixBuf[I * 4 + 0] := (Argb shr 16) and $ff;  // R
      PixBuf[I * 4 + 1] := (Argb shr  8) and $ff;  // G
      PixBuf[I * 4 + 2] :=  Argb         and $ff;  // B
      PixBuf[I * 4 + 3] := (Argb shr 24) and $ff;  // A
    end;
    Result := True;
  finally
    if Pix <> nil then FreeMem(Pix);
    VP8LFreeTransforms(St);
  end;
end;

// ============================================================
// RIFF CONTAINER PARSER
// ============================================================

function ReadLE32(p: PByte): Cardinal; inline;
begin
  Result := p[0] or (Cardinal(p[1]) shl 8) or
            (Cardinal(p[2]) shl 16) or (Cardinal(p[3]) shl 24);
end;

type
  TWebPChunk = record
    FourCC: Cardinal;
    Size:   Cardinal;
    Data:   PByte;
  end;

function FindChunk(const RIFF: PByte; RiffSize: NativeUInt;
  const Tag: AnsiString; out Chunk: TWebPChunk): Boolean;
var
  p:    PByte;
  left: NativeUInt;
  cc, sz: Cardinal;
  tagCC: Cardinal;
begin
  Result := False;
  tagCC := Ord(Tag[1]) or (Cardinal(Ord(Tag[2])) shl 8) or
           (Cardinal(Ord(Tag[3])) shl 16) or (Cardinal(Ord(Tag[4])) shl 24);
  p    := RIFF;
  left := RiffSize;
  while left >= 8 do
  begin
    cc := ReadLE32(p);
    sz := ReadLE32(p + 4);
    if cc = tagCC then
    begin
      Chunk.FourCC := cc;
      Chunk.Size   := sz;
      Chunk.Data   := p + 8;
      Result := True;
      Exit;
    end;
    // align to 2 bytes
    sz := (sz + 1) and (not 1);
    Inc(p, 8 + sz);
    if 8 + sz > left then Break;
    Dec(left, 8 + sz);
  end;
end;

// Parse RIFF header and locate the VP8/VP8L/VP8X chunk.
// Returns: 1 = VP8 lossy, 2 = VP8L lossless, 0 = error
function ParseRIFF(Data: PByte; Size: NativeUInt;
  out ChunkData: PByte; out ChunkSize: NativeUInt;
  out IsLossless: Boolean;
  out HasAlpha: Boolean): Integer;
var
  riffTag, webpTag, fmtTag: Cardinal;
  riffSize: Cardinal;
  inner: PByte;
  innerSize: NativeUInt;
  chunk: TWebPChunk;
  vp8x_flags: Cardinal;
  alphaChunk: TWebPChunk;
begin
  Result    := 0;
  IsLossless := False;
  HasAlpha   := False;
  ChunkData  := nil;
  ChunkSize  := 0;
  if Size < 12 then Exit;

  riffTag := ReadLE32(Data);
  riffSize := ReadLE32(Data + 4);
  webpTag := ReadLE32(Data + 8);

  // 'RIFF'
  if riffTag <> $46464952 then Exit;
  // 'WEBP'
  if webpTag <> $50424557 then Exit;

  inner     := Data + 12;
  innerSize := Size - 12;

  // Try VP8X (extended format)
  if FindChunk(inner, innerSize, 'VP8X', chunk) then
  begin
    if chunk.Size >= 10 then
    begin
      vp8x_flags := ReadLE32(chunk.Data);
      HasAlpha    := (vp8x_flags and 16) <> 0;
    end;
    // Now find actual image chunk
    if FindChunk(inner, innerSize, 'VP8L', chunk) then
    begin
      ChunkData  := chunk.Data;
      ChunkSize  := chunk.Size;
      IsLossless := True;
      Result     := 2;
      Exit;
    end;
    if FindChunk(inner, innerSize, 'VP8 ', chunk) then
    begin
      ChunkData  := chunk.Data;
      ChunkSize  := chunk.Size;
      IsLossless := False;
      Result     := 1;
      Exit;
    end;
    Exit;
  end;

  // Try VP8L directly
  if FindChunk(inner, innerSize, 'VP8L', chunk) then
  begin
    ChunkData  := chunk.Data;
    ChunkSize  := chunk.Size;
    IsLossless := True;
    Result     := 2;
    Exit;
  end;

  // Try VP8 (lossy) directly
  if FindChunk(inner, innerSize, 'VP8 ', chunk) then
  begin
    ChunkData  := chunk.Data;
    ChunkSize  := chunk.Size;
    IsLossless := False;
    Result     := 1;
    Exit;
  end;
end;

// ============================================================
// VP8 LOSSY DECODE (FULL DRIVER)
// ============================================================

function VP8Decode(Data: PByte; DataSize: NativeUInt;
  Mode: TCSMode; out Width, Height: Integer): PByte;
var
  D:          TVP8Decoder;
  outSize:    NativeUInt;
  topBufSize: NativeUInt;
  topBuf:     PByte;
  mbInfoSz:   NativeUInt;
  i:          Integer;
begin
  Result := nil;
  Width  := 0;
  Height := 0;

  FillChar(D, SizeOf(D), 0);
  D.OutputMode := Mode;
  case Mode of
    csmRGB, csmBGR:     D.OutBpp := 3;
    else                D.OutBpp := 4;
  end;
  D.SegHdr.UseSegment := False;
  D.SegHdr.AbsoluteDelta := True;

  if not VP8ParseHeaders(D, Data, DataSize) then Exit;
  Width  := D.PicWidth;
  Height := D.PicHeight;

  if D.FilterLevel = 0 then D.FilterType := 0
  else if D.FilterSimple then D.FilterType := 1
  else D.FilterType := 2;

  // Allocate output buffer
  D.OutStride := D.PicWidth * D.OutBpp;
  outSize  := NativeUInt(D.PicHeight) * NativeUInt(D.OutStride);
  D.OutBuf := AllocMem(outSize);

  // Allocate full-frame reconstruction planes (MB-padded dimensions)
  D.YStride  := D.MbW * 16;
  D.UVStride := D.MbW * 8;
  D.YPlane := AllocMem(NativeUInt(D.YStride) * NativeUInt(D.MbH) * 16);
  D.UPlane := AllocMem(NativeUInt(D.UVStride) * NativeUInt(D.MbH) * 8);
  D.VPlane := AllocMem(NativeUInt(D.UVStride) * NativeUInt(D.MbH) * 8);
  D.FInfo  := AllocMem(NativeUInt(D.MbW) * NativeUInt(D.MbH) * SizeOf(TVP8FInfo));

  // Allocate top-row context buffers
  topBufSize := D.MbW * 32;  // 16Y + 8U + 8V per MB column
  topBuf     := AllocMem(topBufSize);
  FillChar(topBuf^, topBufSize, 127);
  D.YTopBuf  := topBuf;
  D.UTopBuf  := topBuf + D.MbW * 16;
  D.VTopBuf  := topBuf + D.MbW * 24;

  // Allocate MB info array (MbW+1 entries)
  mbInfoSz := (D.MbW + 1) * SizeOf(TVP8MB);
  D.MBInfo  := PVP8MB(AllocMem(mbInfoSz));
  FillChar(D.MBInfo^, mbInfoSz, 0);

  // Allocate I4x4 top-context array and initialize to B_DC_PRED
  D.IntraT := AllocMem(D.MbW * 4 + 4);
  FillChar(D.IntraT^, D.MbW * 4 + 4, B_DC_PRED);

  // Initialize YUV buffer
  FillChar(D.YuvBuf, SizeOf(D.YuvBuf), 128);
  // Left border column (col -1 of Y/U/V, used as left context for first MB column)
  for i := 0 to 15 do D.YuvBuf[Y_OFF + i * BPS - 1] := 129;
  for i := 0 to  7 do D.YuvBuf[U_OFF + i * BPS - 1] := 129;
  for i := 0 to  7 do D.YuvBuf[V_OFF + i * BPS - 1] := 129;

  if VP8DecodeFrame(D) then
    Result := D.OutBuf
  else
  begin
    FreeMem(D.OutBuf);
    D.OutBuf := nil;
  end;

  FreeMem(topBuf);
  FreeMem(D.MBInfo);
  FreeMem(D.IntraT);
  FreeMem(D.YPlane);
  FreeMem(D.UPlane);
  FreeMem(D.VPlane);
  FreeMem(D.FInfo);
end;

// ============================================================
// PUBLIC API
// ============================================================

function WebPGetInfo(Data: PByte; DataSize: NativeUInt;
  out Width, Height: Integer): Boolean;
var
  chunkData: PByte;
  chunkSize: NativeUInt;
  isLossless, hasAlpha: Boolean;
  riffType: Integer;
  BR:  TVP8LBitReader;
  tmp: Cardinal;
  w, h: Integer;
begin
  Result := False;
  Width  := 0;
  Height := 0;
  if DataSize < 12 then Exit;

  riffType := ParseRIFF(Data, DataSize, chunkData, chunkSize, isLossless, hasAlpha);
  if riffType = 0 then Exit;

  if isLossless then
  begin
    // VP8L: signature + 14+14 bits
    if chunkSize < 5 then Exit;
    if chunkData[0] <> $2F then Exit;
    VP8LInitBitReader(BR, chunkData + 1, chunkSize - 1);
    Width  := Integer(VP8LReadBits(BR, 14)) + 1;
    Height := Integer(VP8LReadBits(BR, 14)) + 1;
    Result := True;
  end else
  begin
    // VP8: 3-byte frame header + start code + w/h
    if chunkSize < 10 then Exit;
    tmp := chunkData[0] or (Cardinal(chunkData[1]) shl 8) or
           (Cardinal(chunkData[2]) shl 16);
    if (tmp and 1) <> 0 then Exit; // not a key frame
    if (chunkData[3] <> $9D) or (chunkData[4] <> $01) or (chunkData[5] <> $2A) then Exit;
    Width  := (chunkData[6] or (Cardinal(chunkData[7]) shl 8)) and $3FFF;
    Height := (chunkData[8] or (Cardinal(chunkData[9]) shl 8)) and $3FFF;
    Result := True;
  end;
end;

// ============================================================
// ALPH (alpha) CHUNK DECODE  (lossy WebP alpha plane)
// ============================================================

function GradPred(A, B, C: Integer): Integer; inline;
begin
  Result := Clip8b(A + B - C);
end;

// Reverse one row of the alpha prediction filter.
// Prev = previous reconstructed row (nil for row 0).
procedure AlphaUnfilterRow(Filter: Integer; Prev, Inp, Outp: PByte; W: Integer);
var X, Pred, Top, TopLeft, Left: Integer;
begin
  case Filter of
    1:  // horizontal
    begin
      if Prev = nil then Pred := 0 else Pred := Prev[0];
      for X := 0 to W - 1 do begin Outp[X] := Byte(Pred + Inp[X]); Pred := Outp[X]; end;
    end;
    2:  // vertical
    begin
      if Prev = nil then
      begin
        Pred := 0;
        for X := 0 to W - 1 do begin Outp[X] := Byte(Pred + Inp[X]); Pred := Outp[X]; end;
      end
      else
        for X := 0 to W - 1 do Outp[X] := Byte(Prev[X] + Inp[X]);
    end;
    3:  // gradient
    begin
      if Prev = nil then
      begin
        Pred := 0;
        for X := 0 to W - 1 do begin Outp[X] := Byte(Pred + Inp[X]); Pred := Outp[X]; end;
      end
      else
      begin
        Top := Prev[0]; TopLeft := Top; Left := Top;
        for X := 0 to W - 1 do
        begin
          Top := Prev[X];
          Left := Byte(Inp[X] + GradPred(Left, Top, TopLeft));
          TopLeft := Top;
          Outp[X] := Left;
        end;
      end;
    end;
  else  // 0 = none
    Move(Inp^, Outp^, W);
  end;
end;

// Decode the ALPH chunk into a freshly-allocated W*H alpha plane (1 byte/pixel).
// Returns nil on failure (caller leaves alpha opaque). Method 0 is an optionally
// filtered raw plane; method 1 is a VP8L-compressed image whose green channel
// carries the alpha (the VP8L predictor transform subsumes the spatial filter,
// so no ALPH unfilter is applied in that case).
function DecodeAlphaPlane(AlphData: PByte; AlphSize: NativeUInt; W, H: Integer): PByte;
var
  Hdr, Method, Filter, Y: Integer;
  Src, Plane, Prev: PByte;
begin
  Result := nil;
  if (AlphData = nil) or (AlphSize < 1) or (W <= 0) or (H <= 0) then Exit;
  Hdr    := AlphData[0];
  Method := Hdr and 3;
  Filter := (Hdr shr 2) and 3;
  if Method = 1 then
  begin
    Result := VP8LDecodeAlphaPlane(AlphData, AlphSize, W, H);
    Exit;
  end;
  if Method <> 0 then Exit;   // unknown compression method
  if AlphSize - 1 < NativeUInt(W) * NativeUInt(H) then Exit;
  Src := AlphData + 1;
  Plane := AllocMem(W * H);
  for Y := 0 to H - 1 do
  begin
    if Y = 0 then Prev := nil else Prev := Plane + (Y - 1) * W;
    AlphaUnfilterRow(Filter, Prev, Src + Y * W, Plane + Y * W, W);
  end;
  Result := Plane;
end;

function InternalDecode(Data: PByte; DataSize: NativeUInt;
  Mode: TCSMode; out Width, Height: Integer): PByte;
var
  chunkData: PByte;
  chunkSize: NativeUInt;
  isLossless, hasAlpha: Boolean;
  riffType: Integer;
  lsBuf: PByte;
  lsW, lsH: Integer;
  outBuf, aplane: PByte;
  alphChunk: TWebPChunk;
  aoff, i: Integer;
begin
  Result := nil;
  Width  := 0;
  Height := 0;

  riffType := ParseRIFF(Data, DataSize, chunkData, chunkSize, isLossless, hasAlpha);
  if riffType = 0 then Exit;

  if isLossless then
  begin
    if not VP8LDecode(chunkData, chunkSize, lsBuf, lsW, lsH) then Exit;
    Width  := lsW;
    Height := lsH;
    // lsBuf is RGBA; convert to requested mode if needed
    if Mode = csmRGBA then
    begin
      Result := lsBuf;
      Exit;
    end;
    // Convert RGBA to target mode
    case Mode of
      csmARGB:
      begin
        outBuf := AllocMem(lsW * lsH * 4);
        for i := 0 to lsW * lsH - 1 do
        begin
          outBuf[i*4+0] := lsBuf[i*4+3]; // A
          outBuf[i*4+1] := lsBuf[i*4+0]; // R
          outBuf[i*4+2] := lsBuf[i*4+1]; // G
          outBuf[i*4+3] := lsBuf[i*4+2]; // B
        end;
        FreeMem(lsBuf);
        Result := outBuf;
      end;
      csmBGRA:
      begin
        outBuf := AllocMem(lsW * lsH * 4);
        for i := 0 to lsW * lsH - 1 do
        begin
          outBuf[i*4+0] := lsBuf[i*4+2]; // B
          outBuf[i*4+1] := lsBuf[i*4+1]; // G
          outBuf[i*4+2] := lsBuf[i*4+0]; // R
          outBuf[i*4+3] := lsBuf[i*4+3]; // A
        end;
        FreeMem(lsBuf);
        Result := outBuf;
      end;
      csmRGB:
      begin
        outBuf := AllocMem(lsW * lsH * 3);
        for i := 0 to lsW * lsH - 1 do
        begin
          outBuf[i*3+0] := lsBuf[i*4+0];
          outBuf[i*3+1] := lsBuf[i*4+1];
          outBuf[i*3+2] := lsBuf[i*4+2];
        end;
        FreeMem(lsBuf);
        Result := outBuf;
      end;
      csmBGR:
      begin
        outBuf := AllocMem(lsW * lsH * 3);
        for i := 0 to lsW * lsH - 1 do
        begin
          outBuf[i*3+0] := lsBuf[i*4+2];
          outBuf[i*3+1] := lsBuf[i*4+1];
          outBuf[i*3+2] := lsBuf[i*4+0];
        end;
        FreeMem(lsBuf);
        Result := outBuf;
      end;
    end;
  end else
  begin
    Result := VP8Decode(chunkData, chunkSize, Mode, Width, Height);
    // Lossy alpha: decode the ALPH chunk and patch the alpha channel.
    if (Result <> nil) and hasAlpha and (Mode <> csmRGB) and (Mode <> csmBGR)
       and (DataSize > 12)
       and FindChunk(Data + 12, DataSize - 12, 'ALPH', alphChunk) then
    begin
      aplane := DecodeAlphaPlane(alphChunk.Data, alphChunk.Size, Width, Height);
      if aplane <> nil then
      begin
        if Mode = csmARGB then aoff := 0 else aoff := 3;
        for i := 0 to Width * Height - 1 do Result[i * 4 + aoff] := aplane[i];
        FreeMem(aplane);
      end;
    end;
  end;
end;

function WebPDecodeRGBA(Data: PByte; DataSize: NativeUInt;
  out Width, Height: Integer): PByte;
begin
  Result := InternalDecode(Data, DataSize, csmRGBA, Width, Height);
end;

function WebPDecodeARGB(Data: PByte; DataSize: NativeUInt;
  out Width, Height: Integer): PByte;
begin
  Result := InternalDecode(Data, DataSize, csmARGB, Width, Height);
end;

function WebPDecodeBGRA(Data: PByte; DataSize: NativeUInt;
  out Width, Height: Integer): PByte;
begin
  Result := InternalDecode(Data, DataSize, csmBGRA, Width, Height);
end;

function WebPDecodeRGB(Data: PByte; DataSize: NativeUInt;
  out Width, Height: Integer): PByte;
begin
  Result := InternalDecode(Data, DataSize, csmRGB, Width, Height);
end;

function WebPDecodeBGR(Data: PByte; DataSize: NativeUInt;
  out Width, Height: Integer): PByte;
begin
  Result := InternalDecode(Data, DataSize, csmBGR, Width, Height);
end;

end.
