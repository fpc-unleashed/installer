unit Pixie.Encoding;

// Statistical encoding detection using bigram frequency models.
//
// The PixieModelData const contains 19 bigram frequency tables extracted from
// Python chardet 7.4.0 (https://github.com/chardet/chardet), which descends
// from Mozilla's Universal Charset Detector. Each table is a 256x256 matrix
// where entry [b1, b2] indicates how likely byte pair (b1, b2) is to appear
// in text encoded with that encoding/language. The tables are:
//
//   Index  Codepage  Language    Model key
//   -----  --------  ----------  ---------
//     0      874     Thai        th/cp874
//     1     1250     Polish      pl/cp1250
//     2     1250     Czech       cs/cp1250
//     3     1250     Hungarian   hu/cp1250
//     4     1251     Russian     ru/cp1251
//     5     1251     Ukrainian   uk/cp1251
//     6     1251     Bulgarian   bg/cp1251
//     7     1252     English     en/cp1252
//     8     1252     German      de/cp1252
//     9     1252     French      fr/cp1252
//    10     1253     Greek       el/cp1253
//    11     1254     Turkish     tr/cp1254
//    12     1255     Hebrew      he/cp1255
//    13     1256     Arabic      ar/cp1256
//    14     1257     Lithuanian  lt/cp1257
//    15     1257     Latvian     lv/cp1257
//    16     1258     Vietnamese  vi/cp1258
//    17    20866     Russian     ru/koi8-r
//    18    21866     Ukrainian   uk/koi8-u
//
// Values are quantized from 8-bit (0-255) to 4-bit (0-15) by shifting right 4,
// then packed two per byte (high nibble first). Each model is 32768 bytes
// uncompressed. The 19 models are concatenated and zlib-compressed.
//
// To regenerate from a newer version of chardet:
//
//   pip install chardet
//   python -c "
//   import zlib
//   from chardet.models import load_models
//   models = load_models()
//   picks = [
//       'th/cp874', 'pl/cp1250', 'cs/cp1250', 'hu/cp1250',
//       'ru/cp1251', 'uk/cp1251', 'bg/cp1251',
//       'en/cp1252', 'de/cp1252', 'fr/cp1252',
//       'el/cp1253', 'tr/cp1254', 'he/cp1255', 'ar/cp1256',
//       'lt/cp1257', 'lv/cp1257',
//       'vi/cp1258', 'ru/koi8-r', 'uk/koi8-u',
//   ]
//   blob = bytearray()
//   for key in picks:
//       m = bytes(models[key])
//       for i in range(0, 65536, 2):
//           blob.append(((m[i] >> 4) << 4) | (m[i+1] >> 4))
//   compressed = zlib.compress(bytes(blob), 9)
//   for i in range(0, len(compressed), 16):
//       chunk = compressed[i:i+16]
//       print(', '.join(f'\x24{b:02X}' for b in chunk) + ',')
//   "

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils;

function PixieGuessCodePage(const Bytes: TBytes; Len: Integer): Integer;
function PixieIsValidUtf8(const Bytes: TBytes; Len: Integer;
  out HasMultiByte: Boolean): Boolean;

// Cross-compiler zlib (RFC 1950) inflate. Returns False if the stream
// is malformed or short. When ExpectedSize > 0, Plain is sized exactly
// to ExpectedSize and the inflate is required to fill it; otherwise
// the entire stream is decoded into a dynamically-sized buffer.
function PixieInflateZlib(const Comp: TBytes;
  out Plain: TBytes; ExpectedSize: Integer = -1): Boolean;

implementation

uses
  Classes,
  {$IFDEF FPC}ZStream{$ELSE}System.ZLib{$ENDIF};

const
  PixieModelSize = 32768; // 256*256/2 bytes per model (4-bit packed)

  PixieModelDataSize = 6085;
  PixieModelDataUncompressed = 622592;
  PixieModelCount = 19;

  PixieModelCodePages: array[0..PixieModelCount - 1] of Integer = (
    874, 1250, 1250, 1250, 1251, 1251, 1251, 1252,
    1252, 1252, 1253, 1254, 1255, 1256, 1257, 1257,
    1258, 20866, 21866
  );

  PixieModelData: array[0..PixieModelDataSize - 1] of Byte = (
    $78, $DA, $ED, $DD, $CB, $6E, $24, $57, $9A, $18, $E0, $FF, $44, $64, $92, $25,
    $D9, $42, $9F, $24, $4B, $D2, $18, $33, $8B, $60, $49, $6A, $63, $60, $2F, $B2,
    $4A, $EA, $99, $5E, $78, $91, $AA, $F1, $D8, $0B, $1B, $70, $4A, $EA, $85, $DB,
    $C0, $00, $54, $5F, $3C, $F0, $8E, $D3, $ED, $DE, $13, $30, $BC, $98, $D5, $D4,
    $5C, $EC, $75, $2D, $6C, $C0, $CB, $EA, $37, $10, $EC, $17, $28, $D8, $2F, $A0,
    $86, $5F, $A0, $60, $D8, $7B, $47, $64, $92, $75, $25, $99, $59, $CC, $8C, $3C,
    $59, $99, $DF, $27, $55, $A9, $58, $22, $79, $E2, $5C, $23, $18, $11, $E7, $FF,
    $23, $00, $00, $00, $80, $7D, $94, $DB, $5F, $55, $F3, $DA, $5F, $A6, $E5, $BE,
    $B6, $CE, $4D, $E4, $D9, $E7, $8E, $EA, $34, $8A, $5C, $55, $29, $C5, $83, $EA,
    $F9, $FF, $FF, $8F, $A3, $46, $03, $03, $D7, $AE, $3D, $94, $D3, $18, $7F, $7B,
    $3D, $0C, $73, $E1, $79, $98, $F7, $BC, $FE, $00, $00, $00, $00, $00, $10, $1E,
    $13, $12, $7B, $FA, $FC, $D1, $08, $30, $FF, $61, $3F, $07, $96, $F1, $BF, $E3,
    $EF, $1F, $6C, $6F, $F9, $C9, $20, $01, $EB, $1F, $00, $00, $00, $00, $C4, $A6,
    $F7, $9F, $A6, $17, $77, $B0, $66, $37, $AA, $AB, $41, $17, $80, $20, $C5, $E0,
    $BB, $7C, $F9, $FD, $AB, $CD, $DF, $E3, $1A, $76, $37, $D6, $9E, $17, $5B, $ED,
    $49, $5F, $CE, $3A, $60, $90, $06, $17, $0D, $9F, $1A, $F7, $18, $17, $9A, $AE,
    $F8, $F5, $B3, $F8, $1B, $F3, $D6, $EF, $06, $7E, $74, $BF, $E2, $A4, $FD, $AD,
    $99, $FF, $ED, $C3, $54, $A6, $F5, $BF, $3C, $D9, $BF, $BE, $7C, $F9, $49, $59,
    $CA, $2F, $3E, $1A, $85, $5B, $FB, $C0, $1E, $C4, $FF, $C8, $97, $6B, $E1, $D1,
    $6C, $3D, $EC, $3E, $3C, $DC, $E4, $22, $55, $CD, $4B, $AF, $F2, $8B, $9A, $3D,
    $2C, $B3, $14, $96, $59, $7F, $2F, $4E, $36, $D5, $D1, $07, $EF, $44, $6C, $8B,
    $F3, $95, $AF, $7F, $2E, $2F, $B4, $8F, $06, $DD, $A5, $CE, $EC, $E2, $FF, $A4,
    $8E, $41, $73, $3C, $FB, $DB, $AF, $D2, $B8, $1D, $89, $B9, $B7, $4E, $7A, $E9,
    $E7, $8F, $F9, $05, $6F, $35, $1F, $84, $97, $17, $BF, $1B, $6F, $FB, $61, $7A,
    $FD, $6A, $64, $50, $EA, $2A, $68, $5F, $7E, $EE, $79, $73, $FD, $99, $8D, $8B,
    $32, $2F, $4E, $6D, $CB, $EB, $5A, $CD, $A6, $7E, $FE, $7F, $F1, $C7, $74, $39,
    $DD, $DA, $A6, $4F, $67, $C3, $EA, $F2, $FB, $4F, $6E, $F8, $FA, $F1, $EA, $E5,
    $A7, $97, $BB, $3E, $5D, $FC, $DB, $CD, $FF, $CB, $F3, $5F, $D3, $EB, $FA, $73,
    $51, $7E, $9A, $AF, $FC, $55, $35, $1F, $7A, $BF, $39, $FD, $BC, $4E, $17, $F5,
    $3F, $5A, $B9, $96, $5B, $7D, $92, $4C, $AF, $FC, $21, $CF, $FF, $F4, $F5, $78,
    $F4, $7C, $21, $7C, $10, $BB, $FB, $FE, $D5, $1B, $E3, $6F, $3C, $FF, $B0, $9E,
    $34, $97, $DF, $3F, $4D, $5C, $E6, $6E, $6C, $E9, $4D, $E9, $62, $3A, $9E, $9C,
    $C4, $C9, $86, $AF, $BF, $EA, $D9, $FC, $AF, $D3, $EB, $0B, $EB, $60, $87, $C7,
    $7F, $5B, $E7, $0F, $2E, $2F, $7C, $87, $6D, $9D, $AB, $AF, $D3, $C5, $F5, $57,
    $72, $13, $64, $33, $EB, $CF, $2B, $97, $C2, $E9, $B5, $6F, $3A, $EE, $B9, $07,
    $EA, $D9, $F0, $9E, $DD, $F4, $8C, $3B, $67, $B3, $B2, $DF, $B8, $EC, $BC, $7B,
    $C3, $D7, $AF, $BA, $36, $1E, $46, $73, $27, $CF, $AA, $38, $AA, $EE, $B4, $A5,
    $1F, $FE, $55, $AA, $BA, $89, $7F, $59, $EB, $A6, $C4, $FD, $D7, $B4, $B9, $1F,
    $42, $5F, $9C, $7F, $1E, $CC, $D6, $99, $74, $C5, $F8, $6A, $7A, $BC, $FE, $AB,
    $16, $74, $68, $57, $FE, $FF, $2E, $7C, $C5, $BD, $F9, $FB, $BF, $07, $AF, $7C,
    $F4, $D5, $26, $2A, $DF, $5E, $F0, $A6, $02, $37, $42, $96, $F9, $71, $E7, $D8,
    $32, $0F, $BD, $18, $34, $ED, $19, $6E, $36, $C1, $4F, $AA, $74, $10, $E3, $6A,
    $30, $A8, $E2, $5E, $2A, $72, $E3, $65, $7E, $AA, $3D, $D8, $BB, $9D, $34, $39,
    $3F, $7F, $EB, $E0, $B5, $3F, $C4, $66, $9F, $64, $57, $DD, $C5, $58, $B2, $FF,
    $A9, $90, $61, $7E, $FB, $9B, $80, $CD, $1A, $8B, $1D, $CE, $EE, $C7, $B7, $97,
    $E4, $F9, $BD, $88, $EF, $97, $BB, $FE, $6D, $56, $3F, $FF, $D7, $2F, $0F, $FB,
    $F9, $C7, $ED, $13, $A7, $BF, $16, $DF, $7E, $19, $63, $4D, $00, $00, $00, $00,
    $00, $00, $10, $FB, $F0, $22, $60, $F7, $0A, $7D, $F7, $DF, $EA, $93, $69, $AA,
    $BF, $B8, $FB, $8B, $47, $FF, $F0, $CB, $3B, $71, $1A, $82, $C5, $02, $EC, $88,
    $B3, $3D, $3F, $D7, $4D, $0D, $01, $00, $00, $00, $00, $00, $80, $B5, $FA, $6E,
    $D1, $27, $D4, $4D, $C4, $27, $0F, $A6, $F1, $A0, $A9, $6E, $DC, $AC, $5D, $F5,
    $B3, $C5, $3B, $C5, $8B, $97, $1A, $4A, $05, $74, $FC, $E6, $32, $A6, $EE, $69,
    $6C, $7C, $FF, $7B, $35, $AF, $F5, $2C, $84, $4A, $1F, $81, $E4, $16, $F6, $7F,
    $D5, $F6, $FB, $83, $A3, $49, $7C, $9E, $F7, $39, $98, $57, $1D, $3B, $BA, $FF,
    $7B, $D1, $F3, $E7, $61, $F5, $83, $6E, $0A, $9C, $2C, $33, $F9, $D2, $2D, $2A,
    $D9, $2C, $1C, $FF, $75, $AF, $A1, $57, $F3, $12, $1D, $3F, $8F, $71, $36, $2A,
    $14, $CE, $B6, $EE, $CA, $EF, $AD, $F0, $C9, $12, $F1, $BD, $EA, $E7, $51, $BD,
    $37, $EF, $B0, $2D, $FD, $EF, $CF, $CA, $CF, $BD, $4C, $C2, $F3, $45, $9F, $70,
    $32, $69, $DF, $C4, $1B, $8D, $F3, $83, $7C, $F0, $E6, $60, $C9, $9B, $89, $69,
    $D9, $85, $D6, $D8, $D3, $17, $25, $86, $F3, $A1, $37, $8B, $31, $98, $A6, $65,
    $E2, $32, $D7, $B3, $D0, $46, $A7, $AB, $07, $2B, $BC, $C5, $FA, $37, $98, $8F,
    $FA, $BA, $0D, $E4, $B2, $5A, $3C, $EF, $B4, $C2, $F9, $27, $97, $4B, $A2, $D2,
    $B7, $C9, $C2, $F6, $4F, $5D, $5C, $9B, $A3, $57, $02, $DD, $EC, $90, $D3, $A5,
    $AE, $7C, $AA, $D9, $F4, $2B, $71, $FD, $33, $68, $E3, $89, $D5, $31, $0F, $E5,
    $3B, $08, $00, $00, $00, $80, $D8, $ED, $A4, $C6, $00, $00, $40, $F4, $FB, $FE,
    $9D, $AB, $70, $76, $57, $E3, $E7, $4F, $30, $01, $00, $00, $00, $00, $20, $0A,
    $DC, $7F, $46, $FF, $03, $44, $D1, $17, $05, $2A, $8D, $00, $00, $00, $00, $00,
    $C0, $DB, $4A, $2F, $6F, $44, $4B, $29, $E7, $34, $DF, $9A, $76, $F0, $60, $9A,
    $4F, $FE, $ED, $87, $FF, $F5, $E9, $3F, $FE, $D9, $A3, $2B, $82, $75, $2E, $15,
    $80, $38, $6B, $5E, $80, $AD, $F3, $28, $F6, $FB, $A5, $8F, $53, $43, $00, $D7,
    $28, $00, $00, $00, $00, $00, $10, $1B, $CD, $FF, $9E, $9A, $36, $FB, $FC, $97,
    $E3, $B8, $37, $6E, $A2, $48, $F4, $C5, $74, $11, $84, $31, $15, $DA, $80, $57,
    $C7, $B7, $A9, $BF, $18, $92, $79, $E1, $57, $D6, $ED, $AF, $FC, $E9, $6A, $09,
    $58, $AF, $2F, $E5, $D9, $A2, $2F, $1D, $B5, $19, $5A, $47, $9F, $9F, $C5, $83,
    $26, $7B, $48, $13, $1B, $CF, $7F, $7B, $D1, $7F, $BD, $A5, $BE, $3D, $5B, $F4,
    $09, $55, $EE, $D6, $80, $71, $A4, $71, $2E, $33, $FF, $87, $CF, $57, $80, $3E,
    $E6, $DF, $78, $A9, $F8, $DF, $79, $18, $F9, $DE, $AD, $D6, $9F, $F4, $4A, $E9,
    $6F, $1E, $47, $B3, $30, $FF, $F1, $B0, $CB, $7B, $7C, $7C, $DB, $06, $58, $F4,
    $55, $D3, $85, $5F, $5F, $75, $F5, $AE, $56, $EB, $80, $7C, $EB, $F5, $EF, $60,
    $9E, $01, $7E, $D0, $25, $20, $BF, $CD, $11, $54, $B3, $5F, $3F, $BE, $B6, $35,
    $1E, $2F, $FA, $06, $F7, $27, $91, $47, $F7, $9A, $FC, $C9, $67, $67, $57, $1C,
    $6C, $DE, $CC, $F9, $2F, $1F, $2C, $EC, $A8, $B5, $AD, $35, $DB, $65, $D0, $F6,
    $5E, $DB, $02, $1F, $DF, $76, $FC, $55, $2B, $C7, $1F, $69, $33, $C0, $57, $B9,
    $5D, $05, $1F, $15, $CA, $3F, $3F, $CB, $7F, $FE, $61, $34, $AB, $9C, $FF, $47,
    $D7, $0E, $D6, $B3, $65, $E6, $6E, $F7, $6F, $CA, $BD, $BC, $B6, $D1, $2C, $BC,
    $FA, $9A, $F5, $FF, $D1, $32, $7D, $79, $5D, $FF, $A7, $8B, $FA, $8B, $E5, $FD,
    $A6, $D3, $D8, $F6, $FC, $1B, $69, $A5, $71, $A6, $C7, $01, $00, $00, $20, $F6,
    $24, $FF, $9A, $BB, $00, $F1, $CE, $EE, $FB, $12, $76, $15, $00, $00, $00, $00,
    $00, $00, $00, $20, $56, $CE, $BF, $3D, $6A, $3F, $2D, $DB, $FD, $0D, $51, $E4,
    $FD, $B7, $DE, $E6, $DE, $24, $96, $79, $47, $CB, $FB, $73, $51, $36, $FE, $43,
    $6F, $43, $E0, $D1, $52, $AF, $DF, $79, $07, $0F, $20, $0A, $C4, $9F, $5A, $FD,
    $EC, $5B, $C9, $BB, $C1, $ED, $7E, $FE, $73, $E9, $07, $00, $00, $00, $B0, $56,
    $55, $3C, $0F, $77, $3F, $F3, $83, $93, $8F, $BE, $FC, $E6, $E3, $1F, $DF, $6F,
    $3E, $9A, $4E, $E2, $96, $4F, $0F, $07, $9A, $15, $60, $EB, $3C, $8E, $FD, $0E,
    $FA, $33, $35, $04, $00, $00, $B6, $2C, $FE, $22, $00, $00, $00, $F0, $AE, $7B,
    $BA, $F8, $0E, $41, $95, $EE, $7E, $3D, $CD, $0F, $4E, $97, $DB, $2C, $1C, $6B,
    $CE, $FF, $99, $EB, $D8, $8A, $1D, $D8, $55, $99, $FB, $2F, $69, $9E, $01, $35,
    $45, $B1, $FD, $DF, $6D, $EE, $E9, $E1, $7F, $39, $8F, $5F, $9E, $17, $4A, $20,
    $5D, $F5, $BA, $0B, $A9, $59, $2A, $FF, $F6, $FC, $B7, $3B, $51, $62, $F7, $5F,
    $BF, $1B, $B0, $4F, $17, $D6, $3F, $B7, $43, $30, $4F, $A2, $CE, $85, $E6, $5E,
    $EA, $35, $F3, $CF, $A3, $05, $B3, $B0, $9A, $65, $20, $8F, $7A, $0D, $C7, $70,
    $E5, $50, $9B, $2E, $91, $FF, $3B, $A5, $FB, $A9, $9B, $7C, $B7, $CF, $7F, $DD,
    $FD, $96, $6E, $35, $FE, $AB, $18, $76, $95, $4F, $AB, $D4, $FD, $A6, $2F, $3E,
    $5F, $38, $FE, $3F, $4D, $55, $EA, $3A, $68, $7C, $AB, $F7, $D8, $D2, $EA, $8B,
    $47, $15, $F5, $FD, $49, $3C, $6C, $0A, $DD, $2C, $4F, $3B, $BD, $0B, $B3, $59,
    $D8, $FF, $83, $6E, $0D, $68, $4F, $82, $4D, $2F, $F3, $FF, $F1, $E2, $CE, $EF,
    $BE, $47, $5B, $7E, $DB, $F9, $DF, $DD, $AE, $FC, $6A, $61, $F9, $D7, $C7, $56,
    $1A, $C6, $E1, $C5, $FA, $F3, $E5, $2D, $CF, $1F, $97, $67, $D0, $B4, $C2, $E8,
    $6D, $8F, $2F, $E5, $42, $EF, $C3, $AE, $B6, $FF, $3D, $D9, $C2, $BC, $D2, $F5,
    $5F, $EA, $F9, $FA, $6B, $71, $F9, $C3, $8B, $EB, $DF, $E6, $D6, $57, $8F, $FA,
    $1F, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $80, $D8, $DD, $00,
    $81, $ED, $F6, $BB, $49, $13, $5F, $34, $DA, $02, $62, $0F, $53, $92, $A4, $A6,
    $C9, $3F, $14, $29, $34, $64, $0A, $86, $3D, $8C, $7F, $9C, $C5, $7F, $DE, $86,
    $03, $75, $0A, $C2, $B9, $17, $00, $00, $00, $80, $78, $F7, $EE, $C1, $AE, $2D,
    $BC, $EA, $EC, $3E, $E9, $E8, $79, $B4, $E7, $4F, $FF, $FB, $B7, $C7, $8F, $7E,
    $F5, $6F, $FE, $EA, $CF, $BE, $C9, $55, $8F, $61, $C4, $01, $88, $75, $E7, $5F,
    $89, $9D, $7E, $9C, $71, $66, $08, $E0, $D1, $2E, $98, $F7, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $B0, $66, $4F, $66, $BF, $E7, $DE, $C2, $60, $A6, $F1, $E8, $38, $FD, $E9, $1F,
    $A7, $2F, $4E, $D3, $A8, $FD, $F0, $68, $F3, $35, $4C, $91, $53, $8C, $73, $9A,
    $FD, $F1, $0D, $A7, $3D, $97, $7E, $1A, $83, $18, $A7, $74, $3A, $2B, $BA, $8E,
    $52, $69, $6B, $4F, $4B, $C5, $39, $9D, $C4, $30, $9A, $94, $E6, $ED, $7F, $85,
    $EF, $FB, $8E, $C2, $7A, $74, $3F, $55, $9F, $FD, $8B, $F8, $CD, $59, $A4, $32,
    $2D, $50, $B7, $B5, $4B, $C5, $E2, $CF, $4E, $66, $05, $5C, $9F, $DD, $E3, $FB,
    $9E, $E7, $7F, $34, $C7, $D5, $C9, $27, $5F, $C4, $F1, $34, $75, $C9, $3F, $06,
    $AF, $FF, $EF, $B3, $1D, $CF, $6C, $DB, $AD, $2F, $93, $14, $E7, $79, $54, $A8,
    $FF, $DB, $F9, $77, $DA, $FD, $67, $36, $04, $4F, $8F, $5F, $FF, $FF, $D3, $9E,
    $CB, $1F, $77, $EB, $DF, $65, $F9, $69, $F3, $F5, $7F, $1C, $07, $ED, $AF, $FA,
    $BB, $74, $D2, $7E, $70, $F0, $E6, $11, $3C, $ED, $F9, $28, $06, $FF, $E9, $67,
    $27, $77, $7F, $F8, $93, $F4, $E7, $A7, $65, $D6, $9F, $DC, $E6, $DC, $69, $D7,
    $DE, $F3, $52, $F3, $EC, $71, $DC, $69, $C7, $58, $7A, $34, $3B, $F3, $A7, $CD,
    $CF, $BF, $DC, $A6, $1D, $6A, $1E, $A6, $07, $E9, $77, $B3, $8F, $EA, $8D, $9F,
    $FF, $C7, $87, $5D, $FD, $9F, $3C, $9C, $8D, $FF, $D3, $2B, $E6, $47, $EF, $23,
    $A0, $3B, $FD, $A4, $D1, $FC, $24, $54, $EA, $32, $E0, $86, $F5, $69, $D7, $C3,
    $BC, $A7, $A2, $D9, $D3, $9B, $76, $FD, $9D, $75, $7D, $2E, $57, $FF, $B2, $83,
    $2E, $6D, $75, $8C, $FF, $FE, $C7, $7F, $75, $D1, $02, $D5, $B5, $D7, $27, $B1,
    $91, $63, $88, $AD, $4C, $F4, $D0, $14, $2E, $FF, $91, $44, $17, $00, $00, $00,
    $40, $6C, $E6, $D6, $40, $CA, $2B, $DD, $62, $8B, $F6, $31, $D3, $CB, $0F, $9C,
    $53, $BA, $B8, $E1, $F3, $E9, $FF, $3C, $7B, $3F, $BE, $FA, $E9, $BF, $FA, $E9,
    $AF, $F3, $BD, $EA, $BA, $9B, $50, $00, $6C, $DC, $D3, $7D, $AC, $F4, $78, $D3,
    $CF, $3F, $90, $07, $1C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $80, $B0, $EF, $03, $00, $00, $80, $D8, $EA, $FC, $4B, $B1, $B6, $40, $DB, $AF,
    $9B, $9E, $A6, $EA, $78, $10, $C7, $CD, $75, $19, $38, $60, $7F, $35, $9A, $80,
    $D8, $F5, $FC, $27, $96, $7D, $00, $00, $00, $88, $BD, $8F, $FF, $BC, $A6, $FB,
    $CF, $57, $24, $3A, $4F, $5F, $8E, $47, $E9, $8F, $7E, $9C, $3E, $3F, $4D, $A3,
    $5E, $5F, $B7, $4A, $D7, $1F, $52, $EE, $52, $B0, $56, $D1, $6F, $FE, $CB, $83,
    $AB, $FF, $FA, $AC, $2D, $F8, $2C, $55, $D3, $94, $CA, $DC, $E2, $69, $2E, $AA,
    $99, $FB, $7E, $FF, $AD, $BA, $2E, $D4, $76, $15, $E3, $B6, $FE, $D7, $1D, $DF,
    $59, $FF, $E9, $8F, $53, $9C, $7C, $1C, $7F, $D1, $94, $9A, $61, $D5, $8D, $F7,
    $DF, $FA, $CE, $FF, $3C, $CD, $37, $74, $4E, $EB, $FB, $CB, $1C, $D1, $D1, $5F,
    $AC, $F5, $FA, $FE, $E7, $71, $3C, $19, $5C, $D9, $08, $D3, $28, $7B, $FF, $73,
    $6D, $C3, $A2, $8E, $6B, $EF, $EF, $4E, $DA, $FC, $EB, $CD, $71, $CF, $55, $BC,
    $B6, $FC, $BA, $6B, $E3, $8B, $61, $36, $3D, $EE, $ED, $FE, $73, $7D, $C3, $FC,
    $EF, $8A, $A9, $7A, $5E, $7F, $0E, $E3, $9A, $E7, $AB, $C3, $38, $CF, $07, $8F,
    $D2, $BD, $59, $69, $07, $3D, $E7, $3F, $78, $A3, $96, $83, $FF, $3C, $BD, $17,
    $9F, $FE, $22, $FD, $B2, $E9, $39, $FF, $FA, $B5, $ED, $5B, $77, $E7, $BF, $B3,
    $DE, $D7, $D9, $C1, $D5, $7F, $7D, $DE, $B6, $FF, $69, $A4, $27, $71, $54, $66,
    $8A, $77, $CB, $7F, $1E, $A5, $A3, $F8, $ED, $6C, $34, $D6, $BD, $8D, $BF, $6B,
    $C6, $FF, $59, $1E, $B4, $39, $9E, $D3, $74, $5C, $5D, $BD, $DA, $3D, $EA, $FB,
    $2D, $F4, $A6, $FD, $DE, $A3, $9C, $46, $79, $9F, $9F, $7F, $6D, $E0, $35, $FF,
    $C1, $76, $3E, $7B, $EB, $96, $9D, $A6, $68, $DA, $AD, $B4, $0D, $7B, $2C, $9A,
    $A0, $DC, $FC, $1B, $57, $39, $ED, $FB, $FB, $1F, $D7, $4C, $82, $47, $9B, $58,
    $9E, $1A, $1B, $9D, $00, $00, $00, $80, $FE, $A4, $FB, $F7, $AB, $C9, $F8, $87,
    $3F, $FA, $B8, $B1, $09, $01, $20, $F6, $EF, $F9, $5B, $6C, $6B, $D0, $AF, $C6,
    $10, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $D6, $EC, $59, $F4, $9C, $7F, $30, $B7, $71,
    $FF, $47, $C7, $31, $9A, $C4, $B6, $87, $82, $8E, $7E, $E2, $6B, $CF, $F2, $9F,
    $E6, $C2, $F5, $2B, $56, $FE, $78, $41, $FD, $1F, $C5, $06, $32, $7C, $A6, $BB,
    $31, $6A, $F6, $73, $7E, $2F, $AA, $F6, $79, $EF, $47, $90, $52, $B4, $E9, $B7,
    $D3, $78, $96, $FF, $A3, $DA, $B7, $F6, $1F, $CF, $27, $5F, $53, $6E, $FE, $77,
    $F9, $9F, $53, $2E, $59, $FE, $4D, $F3, $BF, $EF, $03, $3B, $6B, $87, $DC, $74,
    $DE, $0D, $57, $3A, $ED, $7B, $F4, $77, $F9, $D7, $DB, $29, $30, $1A, $97, $5D,
    $06, $C6, $C5, $F2, $4B, $D4, $DD, $E0, $6F, $4A, $F5, $7F, $6E, $FB, $3F, $E7,
    $8B, $44, $17, $F9, $EA, $F9, $D9, $6B, $FD, $F3, $A0, $AB, $FC, $44, $FA, $E5,
    $FD, $55, $B6, $EF, $A5, $DD, $32, $06, $D8, $FB, $71, $61, $00, $02, $00, $00,
    $00, $F1, $FC, $69, $DD, $FC, $8E, $E1, $C5, $23, $A3, $F7, $BE, $B8, $77, $FF,
    $B3, $38, $FA, $70, $FC, $D9, $6F, $07, $49, $F3, $00, $EC, $8C, $49, $EC, $F7,
    $4D, $F7, $B1, $21, $00, $00, $00, $00, $40, $78, $47, $15, $00, $62, $83, $FB,
    $93, $BB, $F7, $10, $52, $DC, $3F, $8B, $87, $D3, $42, $3B, $99, $CA, $BE, $F5,
    $90, $BA, $FD, $8B, $B3, $7D, $D3, $B9, $A7, $FD, $B1, $8B, $54, $BD, $B6, $C0,
    $B3, $45, $A5, $A7, $FB, $ED, $EF, $27, $93, $F8, $F7, $B9, $CC, $F8, $9B, $8F,
    $80, $D4, $E7, $FE, $F0, $92, $E3, $6F, $51, $FD, $EB, $B8, $D3, $0D, $BE, $72,
    $93, $A0, $1A, $B5, $65, $8F, $FE, $26, $8E, $C7, $7B, $7A, $19, $9A, $7A, $8F,
    $4F, $70, $73, $E9, $75, $DB, $FF, $4D, $EA, $EB, $48, $F2, $12, $EB, $5F, $9F,
    $F3, $EF, $74, $E1, $FB, $70, $0F, $07, $B3, $F2, $D3, $B8, $D4, $FB, $17, $ED,
    $14, $3D, $FA, $2A, $BE, $BC, $9B, $CA, $8C, $BE, $AE, $D8, $9C, $76, $F5, $87,
    $C0, $E9, $C2, $B3, $DF, $41, $B7, $FE, $55, $7D, $85, $D0, $78, $BC, $C4, $F9,
    $F7, $A8, $C7, $F1, $77, $B6, $B0, $FF, $07, $F1, $77, $D1, $FE, $36, $2A, $7A,
    $07, $22, $C7, $49, $A9, $01, $58, $17, $BD, $02, $4C, $17, $33, $30, $F6, $FB,
    $FD, $33, $AF, $1E, $03, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $B0, $13, $52, $1E, $8D, $DA, $A0, $C7,
    $91, $AB, $3C, $8B, $B9, $59, $E7, $5F, $8F, $8E, $53, $95, $A3, $AE, $8E, $24,
    $82, $01, $88, $7D, $8B, $BF, $1C, $BB, $9A, $D0, $6C, $6C, $08, $00, $00, $00,
    $00, $00, $00, $6C, $D6, $A8, $CB, $FD, $D9, $E6, $7F, $BF, $F7, $49, $A1, $03,
    $18, $14, $6F, $82, $C7, $51, $32, $FF, $F7, $61, $97, $FF, $B8, $5C, $DD, $72,
    $A4, $8F, $E3, $FE, $B3, $F8, $BF, $79, $27, $F3, $AF, $37, $0B, $3F, $63, $18,
    $A5, $F3, $BF, $CF, $FB, $A1, $29, $D3, $FC, $F5, $61, $DB, $01, $A3, $B3, $38,
    $DA, $D7, $27, $B5, $69, $53, $8F, $C2, $AF, $ED, $FF, $6A, $36, $4A, $73, $91,
    $F1, $9F, $BA, $D4, $EB, $3D, $D6, $FF, $E9, $65, $7E, $F1, $6B, $CB, $FF, $49,
    $9D, $66, $AB, $50, $53, $70, $0C, $B4, $93, $CF, $BB, $77, $BD, $38, $5F, $F0,
    $FF, $AB, $B8, $DB, $8D, $BF, $36, $09, $FB, $49, $2F, $E5, $4F, $17, $7D, $42,
    $D5, $CD, $BF, $AE, $FC, $49, $2F, $E5, $9F, $2E, $7B, $FE, $1F, $E5, $5E, $96,
    $80, $BC, $78, $F9, $6B, $3F, $25, $4D, $67, $E5, $97, $5B, $7F, $0B, $E6, $9F,
    $4F, $25, $0B, $E7, $79, $EB, $EB, $05, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $20, $B6, $26, $67, $0E, $00, $00, $00, $00,
    $BB, $A3, $AE, $FF, $43, $7B, $E7, $E7, $EB, $FC, $D5, $F1, $ED, $02, $B0, $BA,
    $6D, $04, $B0, $9D, $C6, $E1, $B1, $06, $00, $00, $00, $00, $00, $00, $B1, $C1,
    $FC, $E7, $5D, $0E, $DE, $3C, $8E, $93, $D1, $9E, $B6, $50, $D5, $3D, $A3, $AA,
    $CA, $95, $3F, $EC, $35, $F3, $E9, $B3, $A5, $3E, $6B, $34, $8D, $3F, $3E, $31,
    $59, $62, $1F, $9F, $BF, $76, $43, $3F, $DF, $8B, $A3, $46, $63, $15, $68, $FF,
    $6A, $36, $FF, $73, $C1, $EC, $CB, $FD, $2E, $7D, $93, $85, $07, $70, $74, $D1,
    $10, $93, $92, $19, $C0, $A7, $91, $07, $25, $B3, $8F, $A7, $F2, $2F, $4A, $54,
    $45, $FA, $7F, $3E, $FE, $BB, $66, $C8, $2B, $67, $10, $BF, $CA, $93, $25, $C6,
    $FF, $BC, $FC, $7E, $AE, $7F, $4E, $17, $96, $5F, $B7, $FF, $B4, $FF, $69, $A2,
    $97, $FA, $2F, $B3, $FE, $A7, $EE, $D3, $EE, $E7, $92, $F9, $DF, $25, $7F, $07,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $42, $FC, $63, $C0,
    $FA, $03, $00, $00, $00, $00, $00, $00, $94, $96, $E6, $D1, $5A, $23, $A7, $79,
    $EC, $D6, $C3, $A3, $3F, $4A, $F9, $EC, $EB, $EA, $FC, $F0, $77, $23, $4F, $FB,
    $00, $B6, $C7, $34, $F6, $FB, $A5, $93, $C6, $10, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $A0,
    $07, $CD, $26, $0A, $49, $29, $8A, $47, $A5, $CF, $05, $EB, $1F, $D7, $27, $BA,
    $EE, $3B, $22, $7E, $B5, $1D, $1D, $70, $AD, $A7, $FD, $77, $7D, $1C, $8E, $EE,
    $C6, $83, $7B, $F7, $F7, $76, $8E, $57, $B3, $56, $28, $37, $F7, $AA, $28, $16,
    $7F, $BC, $EE, $7E, $1B, $8E, $AA, $38, $6E, $4E, $B6, $B2, $6F, $4E, $37, $52,
    $CA, $71, $C4, $FD, $5C, $AC, $FF, $6F, $F2, $B8, $E7, $45, $77, $38, $1B, $64,
    $A9, $8A, $A3, $12, $75, $CF, $F9, $20, $D2, $8B, $65, $78, $E3, $F9, $4F, $72,
    $77, $E6, $6B, $DD, $38, $05, $7B, $ED, $FB, $3A, $06, $5D, $0B, $5C, $77, $FA,
    $ED, $B9, $FF, $23, $0E, $A2, $EA, $4E, $7E, $D5, $B6, $46, $FA, $3F, $DB, $C4,
    $FA, $9F, $8E, $E3, $E8, $E4, $FD, $17, $C3, $70, $A3, $E7, $9E, $59, $46, $A0,
    $61, $55, $24, $DB, $42, $4E, $75, $EA, $C6, $60, $3B, $08, $AF, $99, $7F, $CF,
    $2E, $E6, $69, $EC, $6C, $3E, $A6, $BA, $4E, $B3, $6C, $4C, $DF, $16, $5A, $FF,
    $EA, $C3, $B6, $F1, $DF, $4F, $B3, $63, $C9, $85, $F2, $8F, $1C, $C5, $68, $94,
    $F7, $36, $23, $17, $95, $D4, $63, $D7, $18, $47, $D9, $1F, $80, $B3, $39, $08,
    $00, $00, $00, $B0, $11, $97, $0F, $68, $52, $33, $6A, $EF, $16, $BF, $78, $62,
    $33, $3C, $FF, $F9, $DD, $1F, $1D, $54, $77, $F3, $C1, $78, $32, $BC, $DD, $7D,
    $8F, $EA, $C5, $AD, $9E, $DD, $BD, $CF, $0E, $F0, $AE, $99, $EE, $63, $A5, $5F,
    $3A, $0B, $4D, $0C, $01, $00, $00, $00, $00, $00, $80, $B5, $7A, $B2, $E8, $13,
    $46, $E3, $C8, $C3, $9F, $3F, $C9, $FF, $6B, $1C, $83, $BC, $F2, $23, $9F, $26,
    $6E, $B1, $7F, $71, $58, $70, $0F, $47, $9A, $EF, $9F, $2C, $E6, $30, $EE, $5C,
    $6C, $9E, $4C, $6B, $D9, $87, $F7, $BA, $EF, $17, $36, $40, $BB, $43, $69, $F0,
    $CD, $79, $FC, $8F, $49, $5E, $65, $F7, $6A, $7E, $67, $77, $EE, $54, $EB, $3A,
    $86, $7C, $9B, $56, $A8, $7A, $1E, $7F, $8F, $97, $3A, $88, $5F, $3D, $8E, $5F,
    $E5, $A8, $C7, $B7, $EF, $C2, $1C, $45, $36, $20, $C7, $AA, $F1, $1F, $86, $6D,
    $0F, $D4, $31, $6E, $EB, $30, $EA, $65, $1F, $DA, $A2, $06, $F9, $20, $FE, $51,
    $BB, $87, $FE, $68, $4D, $7B, $C7, $EB, $78, $DB, $FD, $87, $87, $ED, $EA, $53,
    $AD, $6D, $97, $60, $BA, $66, $FF, $F7, $0D, $47, $9C, $7E, $D1, $1E, $C1, $C9,
    $95, $6B, $D7, $DB, $1B, $DC, $F2, $B0, $27, $E3, $0D, $6E, $D4, $DC, $AB, $9D,
    $8B, $67, $0B, $86, $E1, $41, $7C, $1A, $07, $A9, $ED, $FF, $54, $A6, $FF, $EB,
    $76, $F4, $0F, $66, $DD, $70, $D2, $CB, $FC, $6B, $16, $1E, $71, $F7, $4F, $5E,
    $6B, $34, $AA, $B7, $DF, $7F, $7C, $32, $2E, $B5, $72, $A7, $DB, $CE, $59, $62,
    $3D, $F1, $5B, $BA, $31, $9B, $AB, $BE, $56, $B3, $66, $A9, $EB, $6F, $AF, $2D,
    $03, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $10, $57, $EC,
    $40, $03, $88, $52, $D9, $B3, $45, $13, $60, $9F, $65, $5B, $C0, $D9, $63, $CD,
    $6C, $FC, $E7, $DE, $E2, $AF, $2C, $38, $01, $9D, $9C, $75, $81, $1A, $D2, $EA,
    $F1, $DF, $F2, $DB, $C6, $05, $4B, $B3, $5F, $EB, $AA, $BC, $F3, $1F, $00, $00,
    $00, $B0, $7B, $FE, $72, $F4, $FF, $8E, $EA, $FA, $D1, $F9, $C9, $24, $A7, $DF,
    $73, $0F, $15, $20, $DE, $95, $FC, $03, $B1, $9B, $4F, $F3, $E2, $ED, $E2, $8F,
    $03, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $2C, $AF, $FF, $F8, $C7, $75, $AA, $2E, $D3, $A7,
    $36, $11, $6F, $9B, $7F, $31, $56, $0E, $F5, $7C, $14, $75, $E4, $D9, $01, $34,
    $B1, $7D, $F9, $DB, $9B, $0D, $94, $7F, $53, $FE, $E6, $27, $3D, $F7, $42, $6E,
    $4B, $AF, $2E, $AA, $39, $BA, $A2, $98, $69, $CF, $B5, $BF, $57, $8D, $52, $4A,
    $F7, $47, $27, $39, $A7, $FB, $E7, $51, $36, $D8, $F8, $16, $8E, $BF, $D2, $E5,
    $9F, $F5, $5C, $FA, $28, $7D, $DA, $AE, $40, $BF, $37, $6A, $07, $60, $3A, $19,
    $97, $98, $7F, $B1, $05, $FD, $9F, $8B, $B5, $7F, $13, $0F, $DA, $F5, $F7, $FA,
    $03, $78, $B2, $15, $73, $A4, $CF, $D9, $7F, $3C, $5F, $7F, $F3, $D5, $EB, $DF,
    $64, $E7, $C7, $DF, $71, $0C, $B6, $78, $FD, $E9, $7F, $E4, $55, $6D, $F9, $BB,
    $BF, $CA, $2C, $D3, $FE, $79, $CF, $EB, $5F, $66, $FC, $DD, $DC, $FE, $7D, $5F,
    $7F, $8D, $DA, $F9, $5F, $DF, $50, $D9, $FE, $EB, $7F, $D4, $CE, $C0, $71, $BE,
    $2E, $83, $FB, $D3, $0D, $5E, $7F, $4B, $7F, $06, $00, $00, $00, $C0, $3B, $AF,
    $4A, $1F, $34, $CD, $C5, $9F, $9B, $2A, $55, $83, $EE, $11, $47, $D2, $2E, $00,
    $C4, $76, $3D, $9F, $07, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $20, $F6, $2A, $FE, $36, $00, $00, $00, $00, $21, $FF, $66, $AC, $FB,
    $A6, $DA, $65, $C4, $CD, $1F, $A4, $BC, $E9, $F8, $67, $69, $A9, $BF, $BA, $70,
    $1A, $EE, $3F, $12, $E2, $0F, $46, $BF, $39, $A8, $62, $7F, $EE, $FF, $A7, $77,
    $A9, $FE, $C0, $EE, $AE, $BF, $56, $9E, $6D, $50, $69, $82, $7D, $39, $FF, $77,
    $E9, $36, $F3, $8B, $C9, $9D, $EA, $79, $16, $D2, $FD, $BD, $FE, $B9, $B9, $84,
    $69, $E1, $25, $2F, $EF, $DE, $92, $5B, $59, $FF, $F1, $FE, $D5, $72, $26, $3D,
    $CC, $FF, $EA, $95, $79, $27, $C2, $3F, $00, $00, $00, $00, $00, $C0, $CB, $06,
    $CD, $B8, $1A, $7E, $74, $3C, $39, $FF, $68, $3A, $5E, $E5, $61, $AC, $A7, $30,
    $00, $DB, $E5, $3C, $F6, $FB, $A5, $CF, $89, $21, $00, $00, $00, $00, $00, $00,
    $B0, $56, $D3, $25, $76, $A8, $BE, $97, $FE, $64, $92, $FF, $F9, $8F, $8A, $BC,
    $42, $90, $B6, $60, $07, $77, $C9, $23, $A8, $67, $01, $15, $56, $3C, $84, $B4,
    $DA, $FE, $DF, $BA, $1A, $4D, $E2, $41, $13, $FB, $1A, $B9, $64, $97, $63, $08,
    $3C, $8A, $9B, $DF, $0E, $3A, $88, $0F, $53, $7C, $7A, $F7, $6F, $F3, $9F, $DE,
    $8B, $55, $F7, $B9, $37, $B7, $6A, $FF, $D9, $0A, $50, $2C, $80, $CC, $B0, $2D,
    $7D, $10, $B9, $8D, $69, $32, $2A, $34, $FE, $52, $7B, $0C, $E5, $86, $E0, $A0,
    $3D, $82, $AA, $5B, $86, $0A, $1D, $42, $1D, $C7, $69, $30, $1B, $02, $F7, $7B,
    $59, $FF, $CE, $63, $89, $97, $15, $4E, $46, $4D, $7C, $96, $8B, $8D, $BF, $D4,
    $D5, $60, $1C, $7B, $19, $7F, $75, $D8, $8E, $BE, $83, $D9, $FC, $EF, $A7, $FD,
    $9F, $CD, $57, $A7, $7C, $E3, $FC, $9B, $8D, $9F, $07, $51, $22, $FE, $D9, $B0,
    $9D, $01, $77, $BA, $69, $90, $AB, $95, $67, $60, $BE, $5D, $FC, $91, $76, $00,
    $B6, $51, $9C, $0A, $8D, $FF, $6E, $F5, $A9, $85, $F1, $29, $2F, $7B, $83, $18,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $80, $90, $FF, $39, $8A,
    $85, $62, $06, $B6, $90, $CD, $8F, $85, $D7, $BF, $1C, $05, $23, $10, $60, $FE,
    $03, $B1, $97, $F1, $B7, $C0, $F9, $0F, $00, $00, $00, $60, $57, $0D, $4F, $9A,
    $34, $BC, $7B, $6F, $72, $F6, $E1, $9F, $4C, $B4, $06, $C0, $EE, $38, $8B, $FD,
    $7E, $E9, $62, $6C, $08, $00, $00, $00, $00, $00, $00, $C4, $66, $9F, $3F, $E5,
    $18, $A4, $7B, $E3, $FC, $AF, $1F, $E4, $52, $7B, $3F, $D2, $16, $E4, $80, $2F,
    $57, $76, $7A, $51, $FF, $26, $0A, $EC, $7F, $CE, $91, $AA, $A3, $71, $7C, $DA,
    $EC, $E5, $FC, $A8, $F6, $7E, $FF, $E1, $1F, $44, $DC, $CB, $E3, $F8, $3C, $AF,
    $36, $FE, $F2, $6D, $F3, $BF, $AF, $D8, $13, $2B, $AE, $5A, $83, $E7, $39, $B0,
    $8F, $8A, $94, $5F, $AD, $3A, $06, $F3, $CD, $47, $D1, $2C, $6C, $FF, $8B, $F5,
    $27, $A5, $5E, $EA, $3F, $5E, $22, $FF, $77, $35, $6B, $82, $51, $F4, $11, $60,
    $67, $B9, $21, $9D, $72, $8C, $CA, $AC, $7F, $F5, $65, $FF, $E7, $DD, $DC, $3E,
    $39, $59, $62, $FC, $CD, $FA, $3F, $8D, $7A, $19, $FF, $CF, $E6, $A3, $20, $DF,
    $34, $FF, $BA, $A1, $9F, $17, $1E, $E9, $ED, $8C, $17, $D6, $BF, $EA, $D6, $A0,
    $2A, $46, $D5, $2A, $E3, $3F, $DF, $7C, $FD, $B7, $68, $70, $D5, $E3, $D9, $F4,
    $CB, $25, $C6, $7F, $7A, $E9, $1C, $60, $FB, $70, $EC, $61, $FC, $1D, $1D, $08,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $65, $8C, $97, $D9,
    $21, $34, $6A, $77, $00, $8D, $B2, $C6, $22, $8A, $6D, $52, $CB, $C6, $1F, $14,
    $98, $7B, $69, $2D, $81, $14, $42, $FC, $11, $00, $00, $00, $00, $00, $A0, $90,
    $74, $F9, $B0, $E3, $E2, $79, $C7, $BF, $6C, $AA, $C9, $E0, $9F, $9E, $9F, $1C,
    $3F, $9B, $E6, $90, $67, $1A, $60, $57, $4C, $62, $BF, $83, $3E, $7B, $AB, $06,
    $00, $00, $00, $00, $00, $20, $4A, $3C, $7F, $6A, $E2, $6D, $DF, $36, $68, $5E,
    $CB, $32, $3E, $8E, $AD, $4C, $DE, $7A, $1A, $8B, $F7, $5F, $4E, $67, $87, $61,
    $27, $E6, $2E, $FA, $AE, $F0, $18, $9C, $C6, $E2, $FC, $F3, $C3, $59, $1A, $F0,
    $15, $F2, $3F, $CF, $1E, $B2, $9E, $44, $5C, $91, $49, $F9, $D1, $72, $75, $7F,
    $CB, $C7, $B4, $AF, $7D, $FA, $69, $7E, $A7, $1F, $F4, $36, $B1, $BB, $FB, $BF,
    $C7, $85, $D7, $DF, $25, $E6, $DF, $0F, $CE, $CB, $D7, $3F, $AF, $3C, $82, $F2,
    $ED, $C7, $56, $13, $DB, $F3, $62, $62, $A1, $52, $77, $36, $05, $F8, $74, $89,
    $FA, $7F, $B5, $5C, $A0, $A4, $5B, $F5, $E1, $E4, $2D, $BE, $22, $DD, $FA, $14,
    $90, $6F, $1D, $3F, $27, $C9, $FF, $5E, $38, $FE, $56, $AC, $F5, $7D, $2F, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $80, $D8, $F1, $F7, $7F, $63, $FE, $FE,
    $EB, $A9, $B7, $60, $89, $3D, $DC, $7F, $78, $F1, $FE, $77, $A3, $A5, $00, $62,
    $57, $43, $01, $87, $1D, $24, $F4, $33, $AA, $1A, $23, $08, $76, $FE, $34, $F1,
    $F2, $7E, $D3, $78, $75, $97, $63, $F3, $8E, $C6, $5F, $19, $CC, $62, $00, $4C,
    $F2, $66, $76, $6A, $12, $DB, $97, $0E, $28, $AD, $65, $F6, $E4, $D8, $C6, $7B,
    $48, $0B, $A7, $65, $3D, $3B, $EA, $76, $FC, $EF, $F5, $2D, $80, $66, $E5, $2F,
    $6F, $36, $BC, $FE, $BA, $FE, $02, $D7, $6D, $CF, $AF, $C7, $06, $5A, $03, $00,
    $00, $00, $88, $FD, $BD, $49, $52, $45, $5A, $D3, $FD, $D1, $6A, $F2, $ED, $D1,
    $7B, $87, $9F, $FD, $B7, $67, $7F, $F6, $CD, $1F, $C4, $B8, $69, $66, $7F, $99,
    $52, $CE, $C9, $0B, $A4, $00, $DB, $E4, $69, $EC, $61, $6E, $83, $E6, $95, $4C,
    $31, $DE, $EF, $C3, $00, $00, $F3, $1E, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $62, $37, $E2, $2F, $2D, $17, $59, $E3,
    $C9, $FC, $73, $D7, $16, $86, $23, $8F, $46, $91, $EF, $7E, $73, $76, $F4, $C5,
    $E9, $71, $9B, $B2, $2A, $97, $C8, $98, $94, $22, $D7, $51, $2C, $E0, $61, $EA,
    $F2, $75, $15, $33, $88, $61, $5B, $7E, $3E, $EE, $EA, $BF, $8C, $EF, $D7, $1E,
    $85, $E5, $7E, $15, $F7, $7E, $F2, $24, $7E, $73, $D6, $76, $C3, $FE, $85, $77,
    $B9, $C8, $D7, $75, $B0, $6C, $CD, $27, $FD, $1D, $C6, $DB, $F4, $FF, $1A, $FB,
    $E9, $38, $8E, $8E, $3E, $9F, $D4, $C7, $D3, $AA, $5D, $DC, $16, $2E, $6F, $67,
    $3B, $B6, $FE, $1E, $CC, $E6, $60, $BE, $D3, $2E, $84, $45, $E2, $1F, $DD, $6D,
    $E7, $7F, $7B, $0C, $83, $BA, $1D, $02, $A7, $4B, $7C, $FE, $74, $CD, $E5, $D7,
    $6D, $ED, $EB, $59, $D6, $C2, $E5, $D6, $DF, $75, $D7, $FF, $FD, $B6, $F6, $EF,
    $47, $FC, $93, $94, $4E, $66, $7D, $11, $4B, $C5, $5F, $5C, $E3, $51, $4C, $7E,
    $36, $4C, $0F, $7F, $39, $C9, $7F, $7E, $FA, $87, $25, $D6, $BF, $EE, $EC, $93,
    $BA, $F1, $B7, $E4, $C4, $7A, $B4, $63, $91, $BD, $DE, $8F, $3B, $ED, $0C, $88,
    $7F, $10, $71, $B4, $D4, $F8, $6B, $7A, $68, $FF, $6A, $D0, $1C, $7F, $92, $7E,
    $B7, $54, $48, $E7, $D3, $B5, $AF, $3F, $87, $5D, $FD, $7F, $3F, $1E, $A6, $FA,
    $DB, $25, $3E, $7F, $BC, $F6, $5E, $CF, $F3, $DF, $47, $39, $97, $19, $04, $DD,
    $CA, $B7, $7C, $B9, $EB, $6F, $FF, $6E, $FD, $CB, $1F, $75, $07, $51, $17, $28,
    $FF, $F9, $B0, $4E, $A5, $AE, $3F, $DA, $D3, $7E, $4E, $C5, $56, $89, $8B, $2C,
    $73, $A3, $72, $C9, $4E, $B7, $25, $D0, $7A, $8E, $7D, $AC, $7F, $D5, $8E, $80,
    $F4, $66, $02, $68, $00, $00, $00, $00, $00, $00, $00, $80, $E8, $F7, $4D, $8D,
    $F6, $9D, $BD, $DB, $BF, $AE, $F0, $CA, $2B, $9C, $D5, $C3, $B3, $A3, $18, $7E,
    $F8, $77, $FF, $E7, $A7, $BF, $FE, $20, $1E, $57, $CD, $EC, $2F, $53, $FB, $46,
    $60, $4A, $49, $4B, $03, $6C, $8F, $A7, $B1, $AB, $FB, $CF, $62, $A9, $97, $8E,
    $4F, $0D, $01, $E4, $01, $07, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $62, $1F, $F2, $3F, $BE, $1B, $9E, $AC, $BE, $FB, $B3, $7A, $23,
    $A3, $CE, $C9, $78, $92, $8E, $9B, $E1, $32, $F9, $B7, $26, $61, $3B, $2B, $00,
    $00, $F0, $AE, $FF, $FC, $97, $DF, $22, $FE, $D4, $2A, $3F, $AE, $BC, $9A, $EC,
    $33, $8F, $C6, $29, $1F, $FF, $FC, $3C, $7F, $3E, $BD, $BB, $A1, $FC, $C7, $F9,
    $F5, $EC, $93, $6D, $B4, $C3, $EA, $8D, $1F, $0B, $FB, $33, $B9, $65, $EA, $F5,
    $75, $FD, $A0, $D8, $BC, $9A, $FD, $B6, $EA, $F2, $CF, $7E, $B6, $EC, $71, $9C,
    $F5, $D1, $1D, $D5, $E8, $2C, $FE, $A2, $49, $7B, $F2, $53, $70, $BE, $E2, $66,
    $C4, $C1, $B2, $75, $9F, $44, $4F, $49, $58, $97, $F4, $FD, $BC, $0A, $6B, $ED,
    $A9, $C9, $E7, $C7, $E3, $38, $9E, $D4, $CB, $0C, $EF, $69, $E1, $FB, $2F, $CD,
    $5A, $A3, $D9, $CD, $F3, $0F, $0F, $BA, $FC, $EB, $CD, $71, $6C, $3E, $9A, $5E,
    $C4, $DD, $76, $F6, $B7, $F9, $BF, $EB, $7A, $C9, $B6, $9D, $AC, $B9, $FC, $F9,
    $FA, $D3, $35, $43, $B5, $A9, $F5, $EF, $95, $25, $EC, $EF, $B5, $B5, $BF, $93,
    $E2, $DF, $1D, $A4, $7B, $4B, $7D, $EF, $A7, $EB, $48, $39, $FC, $72, $7D, $26,
    $D3, $83, $A8, $FE, $D9, $24, $FF, $B2, $F9, $C3, $76, $70, $E5, $4D, $5F, $42,
    $A4, $59, $FE, $F3, $7C, $B8, $EC, $C2, $FE, $A8, $8F, $DB, $95, $D5, $46, $6F,
    $81, $BE, $32, $84, $EF, $B4, $FD, $7F, $10, $F1, $FB, $11, $47, $45, $D6, $FF,
    $D9, $F5, $47, $CA, $A3, $4F, $E2, $B7, $69, $BC, $99, $F1, $FF, $4A, $31, $87,
    $ED, $D4, $7B, $2F, $E2, $C3, $18, $57, $69, $5A, $A4, $FF, $DB, $EF, $D5, $06,
    $B3, $CE, $A3, $BC, $B1, $0B, $B0, $55, $06, $DF, $E9, $EA, $05, $9E, $BE, $DA,
    $FE, $55, $FB, $AB, $BD, $FE, $5A, $32, $DC, $76, $2F, $E7, $FF, $3A, $4E, $E2,
    $1D, $89, $F6, $3D, $5E, $F3, $F7, $1B, $BE, $58, $13, $0B, $B5, $40, $0A, $81,
    $D6, $A3, $2A, $57, $70, $EA, $0A, $6F, $74, $01, $00, $00, $00, $50, $CA, $FF,
    $07, $91, $95, $5E, $4F
  );

var
  Models: TBytes;

function PixieInflateZlib(const Comp: TBytes;
  out Plain: TBytes; ExpectedSize: Integer = -1): Boolean;
{$IFDEF FPC}
const
  cChunkSize = 64 * 1024;
var
  InStream: TBytesStream;
  Decompressor: TDecompressionStream;
  Read, Total: Integer;
begin
  Result := False;
  SetLength(Plain, 0);
  if Length(Comp) = 0 then Exit;
  InStream := TBytesStream.Create(Comp);
  try
    Decompressor := TDecompressionStream.Create(InStream);
    try
      try
        if ExpectedSize > 0 then
        begin
          SetLength(Plain, ExpectedSize);
          Read := Decompressor.Read(Plain[0], ExpectedSize);
          Result := Read = ExpectedSize;
        end
        else
        begin
          Total := 0;
          repeat
            SetLength(Plain, Total + cChunkSize);
            Read := Decompressor.Read(Plain[Total], cChunkSize);
            Inc(Total, Read);
          until Read < cChunkSize;
          SetLength(Plain, Total);
          Result := Total > 0;
        end;
      except
        Result := False;
      end;
    finally
      Decompressor.Free;
    end;
  finally
    InStream.Free;
  end;
  if not Result then
    SetLength(Plain, 0);
end;
{$ELSE}
begin
  Result := False;
  SetLength(Plain, 0);
  if Length(Comp) = 0 then Exit;
  try
    ZDecompress(Comp, Plain);
  except
    SetLength(Plain, 0);
    Exit;
  end;
  if ExpectedSize > 0 then
    Result := Length(Plain) = ExpectedSize
  else
    Result := Length(Plain) > 0;
  if not Result then
    SetLength(Plain, 0);
end;
{$ENDIF}

procedure EnsureModelsLoaded;
var
  InBytes: TBytes;
begin
  if Length(Models) > 0 then
    Exit;
  SetLength(InBytes, PixieModelDataSize);
  Move(PixieModelData[0], InBytes[0], PixieModelDataSize);
  PixieInflateZlib(InBytes, Models, PixieModelDataUncompressed);
end;

function PixieGuessCodePage(const Bytes: TBytes; Len: Integer): Integer;
const
  MaxScan = 8192;
var
  ScanLen: Integer;
  I, J, Idx: Integer;
  Freq: array of Integer;
  NonZero: array of Integer;
  NonZeroCount: Integer;
  InputNormSq: Int64;
  ModelNormSq: Int64;
  DotProduct: Int64;
  InputNorm: Double;
  CpScores: array[0..PixieModelCount - 1] of Double;
  BestCp: Integer;
  BestCpScore: Double;
  V: Integer;
  ModelBase: Integer;
  B: Byte;
begin
  Result := 0;
  if Len < 8 then
    Exit;

  EnsureModelsLoaded;

  ScanLen := Len;
  if ScanLen > MaxScan then
    ScanLen := MaxScan;

  SetLength(Freq, 65536);
  SetLength(NonZero, ScanLen);
  NonZeroCount := 0;

  for I := 0 to ScanLen - 2 do
  begin
    if (Bytes[I] < $80) and (Bytes[I + 1] < $80) then
      Continue;
    Idx := (Bytes[I] shl 8) or Bytes[I + 1];
    if Freq[Idx] = 0 then
    begin
      NonZero[NonZeroCount] := Idx;
      Inc(NonZeroCount);
    end;
    Inc(Freq[Idx]);
  end;

  if NonZeroCount = 0 then
    Exit;

  InputNormSq := 0;
  for I := 0 to NonZeroCount - 1 do
    InputNormSq := InputNormSq + Int64(Freq[NonZero[I]]) * Freq[NonZero[I]];
  InputNorm := Sqrt(InputNormSq);
  if InputNorm = 0 then
    Exit;

  // Score each model using cosine similarity over observed bigram positions
  for J := 0 to PixieModelCount - 1 do
  begin
    DotProduct := 0;
    ModelNormSq := 0;
    ModelBase := J * PixieModelSize;
    for I := 0 to NonZeroCount - 1 do
    begin
      Idx := NonZero[I];
      B := Models[ModelBase + (Idx shr 1)];
      if (Idx and 1) = 0 then
        V := B shr 4
      else
        V := B and $0F;
      if V > 0 then
      begin
        DotProduct := DotProduct + Int64(Freq[Idx]) * V;
        ModelNormSq := ModelNormSq + Int64(V) * V;
      end;
    end;

    if (DotProduct > 0) and (ModelNormSq > 0) then
      CpScores[J] := DotProduct / (InputNorm * Sqrt(ModelNormSq))
    else
      CpScores[J] := 0;
  end;

  BestCp := 0;
  BestCpScore := 0;
  for J := 0 to PixieModelCount - 1 do
    if CpScores[J] > BestCpScore then
    begin
      BestCpScore := CpScores[J];
      BestCp := PixieModelCodePages[J];
    end;

  if BestCpScore < 0.01 then
    Exit;

  Result := BestCp;
end;

function PixieIsValidUtf8(const Bytes: TBytes; Len: Integer;
  out HasMultiByte: Boolean): Boolean;
var
  I: Integer;
  B: Byte;
begin
  Result := True;
  HasMultiByte := False;
  I := 0;
  while I < Len do
  begin
    B := Bytes[I];
    if B <= $7F then
      Inc(I)
    else if (B >= $C2) and (B <= $DF) then
    begin
      if (I + 1 >= Len) or ((Bytes[I + 1] and $C0) <> $80) then
        Exit(False);
      HasMultiByte := True;
      Inc(I, 2);
    end
    else if (B and $F0) = $E0 then
    begin
      if (I + 2 >= Len) or ((Bytes[I + 1] and $C0) <> $80) or
         ((Bytes[I + 2] and $C0) <> $80) then
        Exit(False);
      if (B = $E0) and (Bytes[I + 1] < $A0) then Exit(False);
      if (B = $ED) and (Bytes[I + 1] >= $A0) then Exit(False);
      HasMultiByte := True;
      Inc(I, 3);
    end
    else if (B >= $F0) and (B <= $F4) then
    begin
      if (I + 3 >= Len) or ((Bytes[I + 1] and $C0) <> $80) or
         ((Bytes[I + 2] and $C0) <> $80) or ((Bytes[I + 3] and $C0) <> $80) then
        Exit(False);
      if (B = $F0) and (Bytes[I + 1] < $90) then Exit(False);
      if (B = $F4) and (Bytes[I + 1] >= $90) then Exit(False);
      HasMultiByte := True;
      Inc(I, 4);
    end
    else
      Exit(False);
  end;
end;

initialization // required by Delphi before finalization
finalization
  Models := nil;

end.
