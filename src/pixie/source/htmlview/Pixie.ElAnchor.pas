unit Pixie.ElAnchor;

// Anchor element (<a>).

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils,
  Pixie.Types,
  Pixie.Stylesheet,
  Pixie.Element, Pixie.HtmlTag;

type
  { TPixieElAnchor }

  TPixieElAnchor = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject);
    procedure OnClick; override;
    procedure ApplyStylesheet(
      Stylesheet: TPixieStylesheet); override;
  end;

implementation

uses
  Pixie.StringId, Pixie.Container;

{ TPixieElAnchor }

constructor TPixieElAnchor.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

procedure TPixieElAnchor.OnClick;
var
  Href: string;
  Cont: TPixieContainer;
begin
  Href := GetAttr('href');
  if Href <> '' then
  begin
    Cont := GetDocContainer;
    if Cont <> nil then
      Cont.OnAnchorClick(Href, Self);
  end;
  inherited OnClick;
end;

procedure TPixieElAnchor.ApplyStylesheet(Stylesheet: TPixieStylesheet);
var
  Href: string;
begin
  Href := GetAttr('href');
  if Href <> '' then
  begin
    if FPseudoClasses.IndexOf(Ord(psid_link)) < 0 then
      FPseudoClasses.Add(Ord(psid_link));
  end;
  inherited ApplyStylesheet(Stylesheet);
end;

end.
