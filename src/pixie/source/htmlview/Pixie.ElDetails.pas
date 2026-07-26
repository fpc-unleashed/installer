unit Pixie.ElDetails;

// <details> and <summary> elements with expand/collapse toggle.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils,
  Pixie.Types, Pixie.CssProperties,
  Pixie.Element, Pixie.HtmlTag;

type
  { TPixieElDetails }

  TPixieElDetails = class(TPixieHtmlTag)
  private
    FOpen: Boolean;
  public
    constructor Create(ADoc: TObject);
    procedure ParseAttributes; override;
    procedure ComputeStyles(Recursive: Boolean = True); override;
    procedure Toggle;
    property IsOpen: Boolean read FOpen;
  end;

  { TPixieElSummary }

  TPixieElSummary = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject);
    procedure OnClick; override;
  end;

implementation

uses
  Pixie.StringId, Pixie.Document;

{ TPixieElDetails }

constructor TPixieElDetails.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
  FOpen := False;
end;

procedure TPixieElDetails.ParseAttributes;
begin
  FOpen := FAttrs.ContainsKey('open');
  inherited ParseAttributes;
end;

procedure TPixieElDetails.ComputeStyles(Recursive: Boolean);
var
  I: Integer;
  Ch: TPixieElement;
  IsSummary: Boolean;
begin
  inherited ComputeStyles(False);

  if Recursive then
    for I := 0 to FChildren.Count - 1 do
    begin
      Ch := FChildren[I];
      IsSummary := (Ch is TPixieHtmlTag) and
        (TPixieHtmlTag(Ch).Tag = Ord(psid_summary));
      if FOpen or IsSummary then
        Ch.ComputeStyles
      else
        Ch.Css.Display := displayNone;
    end;
end;

procedure TPixieElDetails.Toggle;
begin
  FOpen := not FOpen;
  if FOpen then
    SetAttr('open', '')
  else
    FAttrs.Remove('open');
  Assert(FDoc is TPixieDocument);
  TPixieDocument(FDoc).Changed;
end;

{ TPixieElSummary }

constructor TPixieElSummary.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

procedure TPixieElSummary.OnClick;
var
  Par: TPixieElement;
begin
  Par := Parent;
  if Par is TPixieElDetails then
    TPixieElDetails(Par).Toggle
  else
    inherited OnClick;
end;

end.
