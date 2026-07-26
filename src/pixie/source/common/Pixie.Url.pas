unit Pixie.Url;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils;

type
  { TPixieUrl }
  TPixieUrl = record
  private
    FStr: string;
    FScheme: string;
    FAuthority: string;
    FPath: string;
    FQuery: string;
    FFragment: string;
  public
    class function Create(const AStr: string): TPixieUrl; overload; static;
    class function Create(const AScheme, AAuthority, APath, AQuery, AFragment: string): TPixieUrl; overload; static;
    class function Encode(const S: string): string; static;
    class function Decode(const S: string): string; static;
    function HasScheme: Boolean;
    function HasAuthority: Boolean;
    function HasPath: Boolean;
    function HasQuery: Boolean;
    function HasFragment: Boolean;
    property Str: string read FStr;
    property Scheme: string read FScheme;
    property Authority: string read FAuthority;
    property Path: string read FPath;
    property Query: string read FQuery;
    property Fragment: string read FFragment;
  end;

function PixieResolveUrl(const Base, Reference: TPixieUrl): TPixieUrl;
function PixieIsUrlPathAbsolute(const APath: string): Boolean;
function PixieUrlPathDirectoryName(const APath: string): string;
function PixieUrlPathBaseName(const APath: string): string;
function PixieUrlPathAppend(const ABase, APath: string): string;
function PixieUrlPathResolve(const ABase, APath: string): string;

implementation

uses
  Pixie.Utf8;

function IsUrlSchemeCodepoint(C: Char): Boolean;
begin
  Result := ((C >= 'a') and (C <= 'z')) or
            ((C >= 'A') and (C <= 'Z')) or
            ((C >= '0') and (C <= '9')) or
            (C = '+') or (C = '-') or (C = '.');
end;

{ TPixieUrl }

class function TPixieUrl.Create(const AStr: string): TPixieUrl;
var
  Tmp: string;
  Offset, I: Integer;
  ValidScheme: Boolean;
begin
  Result.FStr := AStr;
  Result.FScheme := '';
  Result.FAuthority := '';
  Result.FPath := '';
  Result.FQuery := '';
  Result.FFragment := '';

  Tmp := AStr;

  // Check for scheme
  Offset := Pos(':', Tmp);
  if Offset > 0 then
  begin
    ValidScheme := True;
    for I := 1 to Offset - 1 do
      if not IsUrlSchemeCodepoint(Tmp[I]) then
      begin
        ValidScheme := False;
        Break;
      end;
    if ValidScheme and (Offset > 1) then
    begin
      Result.FScheme := Copy(Tmp, 1, Offset - 1);
      Tmp := Copy(Tmp, Offset + 1, Length(Tmp) - Offset);
    end;
  end;

  // Check for authority (preceded by //)
  if (Length(Tmp) >= 2) and (Tmp[1] = '/') and (Tmp[2] = '/') then
  begin
    Tmp := Copy(Tmp, 3, Length(Tmp) - 2);
    Offset := Length(Tmp) + 1;
    for I := 1 to Length(Tmp) do
      if (Tmp[I] = '/') or (Tmp[I] = '?') or (Tmp[I] = '#') then
      begin
        Offset := I;
        Break;
      end;
    Result.FAuthority := Copy(Tmp, 1, Offset - 1);
    Tmp := Copy(Tmp, Offset, Length(Tmp) - Offset + 1);
  end;

  // Check for fragment
  Offset := Pos('#', Tmp);
  if Offset > 0 then
  begin
    Result.FFragment := Copy(Tmp, Offset + 1, Length(Tmp) - Offset);
    Tmp := Copy(Tmp, 1, Offset - 1);
  end;

  // Check for query
  Offset := Pos('?', Tmp);
  if Offset > 0 then
  begin
    Result.FQuery := Copy(Tmp, Offset + 1, Length(Tmp) - Offset);
    Tmp := Copy(Tmp, 1, Offset - 1);
  end;

  // Remainder is the path
  Result.FPath := Tmp;
end;

class function TPixieUrl.Create(const AScheme, AAuthority, APath, AQuery, AFragment: string): TPixieUrl;
begin
  Result.FScheme := AScheme;
  Result.FAuthority := AAuthority;
  Result.FPath := APath;
  Result.FQuery := AQuery;
  Result.FFragment := AFragment;

  Result.FStr := '';
  if AScheme <> '' then
    Result.FStr := Result.FStr + AScheme + ':';
  if AAuthority <> '' then
    Result.FStr := Result.FStr + '//' + AAuthority;
  if APath <> '' then
    Result.FStr := Result.FStr + APath;
  if AQuery <> '' then
    Result.FStr := Result.FStr + '?' + AQuery;
  if AFragment <> '' then
    Result.FStr := Result.FStr + '#' + AFragment;
end;

class function TPixieUrl.Encode(const S: string): string;
var
  I: Integer;
  C: Byte;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := Ord(S[I]);
    if ((C >= Ord('A')) and (C <= Ord('Z'))) or
       ((C >= Ord('a')) and (C <= Ord('z'))) or
       ((C >= Ord('0')) and (C <= Ord('9'))) or
       (C = Ord('-')) or (C = Ord('_')) or (C = Ord('.')) or (C = Ord('~')) then
      AppendUtf8Char(Result, C)
    else
      Result := Result + '%' + UpperCase(IntToHex(C, 2));
  end;
end;

class function TPixieUrl.Decode(const S: string): string;
var
  I, Ch: Integer;
{$IFDEF FPC}
  C: Char;
{$ELSE}
  Bytes: TBytes;
  ByteCount: Integer;
{$ENDIF}
begin
{$IFDEF FPC}
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    C := S[I];
    if C = '%' then
    begin
      if I + 2 > Length(S) then
        Break;
      C := Chr(StrToIntDef('$' + Copy(S, I + 1, 2), 0));
      Inc(I, 2);
    end
    else if C = '+' then
      C := ' ';
    Result := Result + C;
    Inc(I);
  end;
{$ELSE}
  SetLength(Bytes, Length(S));
  ByteCount := 0;
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '%') and (I + 2 <= Length(S)) then
    begin
      Ch := StrToIntDef('$' + Copy(S, I + 1, 2), -1);
      if Ch >= 0 then
      begin
        Bytes[ByteCount] := Byte(Ch);
        Inc(ByteCount);
        Inc(I, 3);
        Continue;
      end;
    end;
    if S[I] = '+' then
      Bytes[ByteCount] := Byte(Ord(' '))
    else
      Bytes[ByteCount] := Byte(Ord(S[I]));
    Inc(ByteCount);
    Inc(I);
  end;
  Result := TEncoding.UTF8.GetString(Bytes, 0, ByteCount);
{$ENDIF}
end;

function TPixieUrl.HasScheme: Boolean;
begin
  Result := FScheme <> '';
end;

function TPixieUrl.HasAuthority: Boolean;
begin
  Result := FAuthority <> '';
end;

function TPixieUrl.HasPath: Boolean;
begin
  Result := FPath <> '';
end;

function TPixieUrl.HasQuery: Boolean;
begin
  Result := FQuery <> '';
end;

function TPixieUrl.HasFragment: Boolean;
begin
  Result := FFragment <> '';
end;

{ URL Path Helpers }

function PixieIsUrlPathAbsolute(const APath: string): Boolean;
begin
  Result := (Length(APath) > 0) and (APath[1] = '/');
end;

function PixieUrlPathDirectoryName(const APath: string): string;
var
  I: Integer;
begin
  I := Length(APath);
  while (I > 0) and (APath[I] <> '/') do
    Dec(I);
  if I = 0 then
    Result := '.'
  else
    Result := Copy(APath, 1, I);
end;

function PixieUrlPathBaseName(const APath: string): string;
var
  I: Integer;
begin
  I := Length(APath);
  while (I > 0) and (APath[I] <> '/') do
    Dec(I);
  if I = 0 then
    Result := APath
  else
    Result := Copy(APath, I + 1, Length(APath) - I);
end;

function PixieUrlPathAppend(const ABase, APath: string): string;
begin
  Result := ABase;
  if (Result <> '') and (APath <> '') and (Result[Length(Result)] <> '/') then
    Result := Result + '/';
  Result := Result + APath;
end;

function PixieUrlPathResolve(const ABase, APath: string): string;
begin
  if PixieIsUrlPathAbsolute(APath) then
    Result := APath
  else
    Result := PixieUrlPathAppend(PixieUrlPathDirectoryName(ABase), APath);
end;

{ Resolve }

function PixieResolveUrl(const Base, Reference: TPixieUrl): TPixieUrl;
var
  ResolvedPath: string;
begin
  if Reference.HasScheme then
    Exit(Reference);

  if Reference.HasAuthority then
    Exit(TPixieUrl.Create(Base.Scheme, Reference.Authority, Reference.Path, Reference.Query, Reference.Fragment));

  if Reference.HasPath then
  begin
    if PixieIsUrlPathAbsolute(Reference.Path) then
      Exit(TPixieUrl.Create(Base.Scheme, Base.Authority, Reference.Path, Reference.Query, Reference.Fragment))
    else
    begin
      ResolvedPath := PixieUrlPathResolve(Base.Path, Reference.Path);
      Exit(TPixieUrl.Create(Base.Scheme, Base.Authority, ResolvedPath, Reference.Query, Reference.Fragment));
    end;
  end;

  if Reference.HasQuery then
    Exit(TPixieUrl.Create(Base.Scheme, Base.Authority, Base.Path, Reference.Query, Reference.Fragment));

  Result := TPixieUrl.Create(Base.Scheme, Base.Authority, Base.Path, Base.Query, Reference.Fragment);
end;

end.
