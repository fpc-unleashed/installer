unit Pixie.ElBeforeAfter;

// ::before and ::after pseudo-element implementations.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils,
  Pixie.Types, Pixie.Style,
  Pixie.Element, Pixie.HtmlTag;

type
  { TPixieElBeforeAfterBase }

  TPixieElBeforeAfterBase = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject; IsBefore: Boolean);
    procedure AddStyle(const AStyle: TPixieStyle); override;
  protected
    procedure AddText(const Txt: string);
    procedure AddFunction(const Func, Params: string);
    class function ConvertEscape(const Txt: string): string; static;
  end;

  { TPixieElBefore }

  TPixieElBefore = class(TPixieElBeforeAfterBase)
  public
    constructor Create(ADoc: TObject);
  end;

  { TPixieElAfter }

  TPixieElAfter = class(TPixieElBeforeAfterBase)
  public
    constructor Create(ADoc: TObject);
  end;

implementation

uses
  StrUtils,
  Pixie.StringId, Pixie.Utils, Pixie.Utf8,
  Pixie.ElText, Pixie.ElImage;

const
  ContentPropertyString = 'none;normal;open-quote;close-quote;' +
    'no-open-quote;no-close-quote';

{ TPixieElBeforeAfterBase }

constructor TPixieElBeforeAfterBase.Create(ADoc: TObject;
  IsBefore: Boolean);
begin
  inherited Create(ADoc);
  if IsBefore then
    FTag := Ord(psid__tag_before)
  else
    FTag := Ord(psid__tag_after);
end;

procedure TPixieElBeforeAfterBase.AddStyle(const AStyle: TPixieStyle);
var
  Prop: TPixiePropertyValue;
  Str: string;
  Idx, I: Integer;
  Ch: Char;
  QuoteChar: Char;
  Fnc: string;
  Pos_: Integer;
  Txt, Params: string;
  SavedChildren: TPixieElementList;
begin
  inherited AddStyle(AStyle);

  // Save children in case content parsing produces nothing
  SavedChildren := TPixieElementList.Create(False);
  try
    for I := 0 to FChildren.Count - 1 do
      SavedChildren.Add(FChildren[I]);
    FChildren.Clear;

    Prop := AStyle.GetProperty(Ord(psid_content));
    if Prop.Kind = pkString then
    begin
      Str := Prop.StrVal;
      Idx := PixieValueIndex(Str, ContentPropertyString);

      if (Idx < 0) and (Str <> '') then
      begin
        // Parse as function/string content list
        Fnc := '';
        I := 1;
        while I <= Length(Str) do
        begin
          Ch := Str[I];

          // String literal (quoted)
          if (Ch = '"') or (Ch = '''') then
          begin
            QuoteChar := Ch;
            Fnc := '';
            Inc(I);
            Pos_ := PosEx(QuoteChar, Str, I);
            if Pos_ = 0 then
            begin
              Txt := Copy(Str, I, Length(Str));
              I := Length(Str) + 1;
            end
            else
            begin
              Txt := Copy(Str, I, Pos_ - I);
              I := Pos_ + 1;
            end;
            AddText(Txt);
          end
          // Function call
          else if Ch = '(' then
          begin
            Inc(I);
            Fnc := PixieTrim(Fnc);
            Fnc := PixieLowerCase(Fnc);
            Pos_ := PosEx(')', Str, I);
            if Pos_ = 0 then
            begin
              Params := Copy(Str, I, Length(Str));
              I := Length(Str) + 1;
            end
            else
            begin
              Params := Copy(Str, I, Pos_ - I);
              I := Pos_ + 1;
            end;
            AddFunction(Fnc, Params);
            Fnc := '';
          end
          // Accumulate function name
          else
          begin
            Fnc := Fnc + Ch;
            Inc(I);
          end;
        end;
      end;
    end;

    // If no children created, restore saved
    if FChildren.Count = 0 then
    begin
      for I := 0 to SavedChildren.Count - 1 do
        FChildren.Add(SavedChildren[I]);
    end;
  finally
    SavedChildren.Free;
  end;
end;

procedure TPixieElBeforeAfterBase.AddText(const Txt: string);
var
  Word, Esc: string;
  I: Integer;
  Ch: Char;
  IsHex: Boolean;
  El: TPixieElement;
begin
  Word := '';
  Esc := '';

  for I := 1 to Length(Txt) do
  begin
    Ch := Txt[I];

    // Detect escape sequences
    IsHex := PixieIsHexDigit(Ord(Ch));

    if (Ch = '\') or
       ((Esc <> '') and (Length(Esc) < 7) and IsHex) then
    begin
      // If we have a pending escape and hit another backslash, finalize
      if (Esc <> '') and (Ch = '\') then
      begin
        Word := Word + ConvertEscape(Copy(Esc, 2, Length(Esc)));
        Esc := '';
      end;
      Esc := Esc + Ch;
    end
    else
    begin
      // Finalize pending escape
      if Esc <> '' then
      begin
        Word := Word + ConvertEscape(Copy(Esc, 2, Length(Esc)));
        Esc := '';
      end;

      // Whitespace handling
      if (Ch = ' ') or (Ch = #9) or (Ch = #10) or
         (Ch = #13) or (Ch = #12) then
      begin
        if Word <> '' then
        begin
          El := TPixieElText.Create(Word, FDoc);
          AppendChild(El);
          Word := '';
        end;
        El := TPixieElSpace.Create(Ch, FDoc);
        AppendChild(El);
      end
      else
        Word := Word + Ch;
    end;
  end;

  // Finalize remaining escape
  if Esc <> '' then
    Word := Word + ConvertEscape(Copy(Esc, 2, Length(Esc)));

  // Emit final word
  if Word <> '' then
  begin
    El := TPixieElText.Create(Word, FDoc);
    AppendChild(El);
  end;
end;

class function TPixieElBeforeAfterBase.ConvertEscape(
  const Txt: string): string;
var
  CodePoint: UInt32;
  Code: Integer;
begin
  Val('$' + Txt, CodePoint, Code);
  if Code <> 0 then
    CodePoint := $FFFD;
  Result := '';
  AppendUtf8Char(Result, CodePoint);
end;

procedure TPixieElBeforeAfterBase.AddFunction(
  const Func, Params: string);
var
  Idx: Integer;
  ParamName, AttrVal, Url: string;
  Tokens: TPixieStringVector;
  El: TPixieElement;
  Par: TPixieElement;
  I: Integer;
begin
  Idx := PixieValueIndex(Func, 'attr;counter;counters;url');

  case Idx of
    // attr(name)
    0:
    begin
      ParamName := PixieTrim(Params);
      ParamName := PixieLowerCase(ParamName);
      Par := Parent;
      if Par <> nil then
      begin
        AttrVal := Par.GetAttr(ParamName);
        if AttrVal <> '' then
          AddText(AttrVal);
      end;
    end;

    // counter(name[, style])
    1:
    begin
      Tokens := TPixieStringVector.Create;
      try
        PixieSplitString(Params, Tokens, ',');
        for I := 0 to Tokens.Count - 1 do
          Tokens[I] := PixieTrim(Tokens[I]);
        if Tokens.Count >= 2 then
          AddText(GetCounterValue(Tokens[0], Tokens[1]))
        else
          AddText(GetCounterValue(Tokens[0]));
      finally
        Tokens.Free;
      end;
    end;

    // counters(name, separator)
    2:
    begin
      Tokens := TPixieStringVector.Create;
      try
        PixieSplitString(Params, Tokens, ',');
        for I := 0 to Tokens.Count - 1 do
          Tokens[I] := PixieTrim(Tokens[I]);
        AddText(GetCountersValue(Tokens));
      finally
        Tokens.Free;
      end;
    end;

    // url(url)
    3:
    begin
      Url := PixieTrim(Params);
      // Strip quotes
      if (Length(Url) > 0) and
         ((Url[1] = '''') or (Url[1] = '"')) then
        Delete(Url, 1, 1);
      if (Length(Url) > 0) and
         ((Url[Length(Url)] = '''') or (Url[Length(Url)] = '"')) then
        Delete(Url, Length(Url), 1);

      if Url <> '' then
      begin
        El := TPixieElImage.Create(FDoc);
        El.SetAttr('src', Url);
        El.SetAttr('style', 'display:inline-block');
        El.SetTagName('img');
        AppendChild(El);
        El.ParseAttributes;
      end;
    end;
  end;
end;

{ TPixieElBefore }

constructor TPixieElBefore.Create(ADoc: TObject);
begin
  inherited Create(ADoc, True);
end;

{ TPixieElAfter }

constructor TPixieElAfter.Create(ADoc: TObject);
begin
  inherited Create(ADoc, False);
end;

function CreateBeforeAfter(ADoc: TObject;
  IsBefore: Boolean): TPixieElement;
begin
  if IsBefore then
    Result := TPixieElBefore.Create(ADoc)
  else
    Result := TPixieElAfter.Create(ADoc);
end;

initialization
  PixieCreateBeforeAfterFunc := CreateBeforeAfter;

end.
