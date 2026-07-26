unit Pixie.ElTable;

// Table elements: <table>, <tr>, <td>/<th>.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils,
  Pixie.Types,
  Pixie.Element, Pixie.HtmlTag;

type
  { TPixieElTable }

  TPixieElTable = class(TPixieHtmlTag)
  public
    Rules: string;
    Cellpadding: string;
    Border: string;
    constructor Create(ADoc: TObject);
    function AppendChild(El: TPixieElement): Boolean; override;
    procedure ParseAttributes; override;
  end;

  { TPixieElTr }

  TPixieElTr = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject);
    procedure ParseAttributes; override;
  end;

  { TPixieElTd }

  TPixieElTd = class(TPixieHtmlTag)
  public
    constructor Create(ADoc: TObject);
    procedure ParseAttributes; override;
  end;

implementation

uses
  Pixie.StringId, Pixie.Style;

{ TPixieElTable }

constructor TPixieElTable.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

function TPixieElTable.AppendChild(El: TPixieElement): Boolean;
var
  ChildTag: Integer;
begin
  ChildTag := El.GetTag;
  if (ChildTag = Ord(psid_tbody)) or (ChildTag = Ord(psid_thead)) or
     (ChildTag = Ord(psid_tfoot)) or (ChildTag = Ord(psid_caption)) or
     (ChildTag = Ord(psid_colgroup)) then
    Result := inherited AppendChild(El)
  else
    Result := False;
end;

procedure TPixieElTable.ParseAttributes;
var
  Val: string;
begin
  Val := GetAttr('width');
  if Val <> '' then
    MapToDimensionPropertyIgnoreZero(Ord(psid_width), Val);

  Val := GetAttr('height');
  if Val <> '' then
    MapToDimensionProperty(Ord(psid_height), Val);

  Val := GetAttr('cellspacing');
  if Val <> '' then
    MapToPixelLengthProperty(Ord(psid_border_spacing), Val);

  Val := GetAttr('border');
  if Val <> '' then
    MapToPixelLengthPropertyWithDefault(
      Ord(psid_border_width), Val, 1);

  Val := GetAttr('bgcolor');
  if Val <> '' then
    FStyle.AddProperty(Ord(psid_background_color), Val);

  Val := GetAttr('align');
  if SameText(Val, 'center') then
  begin
    FStyle.AddProperty(Ord(psid_margin_left), 'auto');
    FStyle.AddProperty(Ord(psid_margin_right), 'auto');
  end;

  // HTML frame attribute — controls outer table border visibility
  Val := LowerCase(GetAttr('frame'));
  if Val = 'void' then
    FStyle.AddProperty(Ord(psid_border_style), 'none')
  else if (Val = 'border') or (Val = 'box') then
    FStyle.AddProperty(Ord(psid_border_style), 'solid')
  else if Val = 'hsides' then
  begin
    FStyle.AddProperty(Ord(psid_border_left_style), 'none');
    FStyle.AddProperty(Ord(psid_border_right_style), 'none');
  end
  else if Val = 'vsides' then
  begin
    FStyle.AddProperty(Ord(psid_border_top_style), 'none');
    FStyle.AddProperty(Ord(psid_border_bottom_style), 'none');
  end
  else if Val = 'above' then
  begin
    FStyle.AddProperty(Ord(psid_border_right_style), 'none');
    FStyle.AddProperty(Ord(psid_border_bottom_style), 'none');
    FStyle.AddProperty(Ord(psid_border_left_style), 'none');
  end
  else if Val = 'below' then
  begin
    FStyle.AddProperty(Ord(psid_border_top_style), 'none');
    FStyle.AddProperty(Ord(psid_border_right_style), 'none');
    FStyle.AddProperty(Ord(psid_border_left_style), 'none');
  end;

  // Cache table attributes for child cell access
  Rules := LowerCase(GetAttr('rules'));
  Cellpadding := GetAttr('cellpadding');
  Border := GetAttr('border');

  if (Rules = 'all') or (Rules = 'rows') or (Rules = 'cols') or
     (Rules = 'groups') then
    FStyle.AddProperty(Ord(psid_border_collapse), 'collapse');

  inherited ParseAttributes;
end;

{ TPixieElTr }

constructor TPixieElTr.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

procedure TPixieElTr.ParseAttributes;
var
  Val: string;
begin
  Val := GetAttr('height');
  if Val <> '' then
    MapToDimensionProperty(Ord(psid_height), Val);

  Val := GetAttr('align');
  if Val <> '' then
    MapAlignToTextAlign(Val);

  Val := GetAttr('valign');
  if Val <> '' then
    FStyle.AddProperty(Ord(psid_vertical_align), Val);

  Val := GetAttr('bgcolor');
  if Val <> '' then
    FStyle.AddProperty(Ord(psid_background_color), Val);

  inherited ParseAttributes;
end;

{ TPixieElTd }

constructor TPixieElTd.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
end;

function FindAncestorTable(El: TPixieElement): TPixieElTable;
var
  Cur: TPixieElement;
begin
  Cur := El.Parent;
  while Cur <> nil do
  begin
    if Cur is TPixieElTable then
      Exit(TPixieElTable(Cur));
    Cur := Cur.Parent;
  end;
  Result := nil;
end;

procedure TPixieElTd.ParseAttributes;
var
  Val: string;
  Table: TPixieElTable;
begin
  Val := GetAttr('width');
  if Val <> '' then
    MapToDimensionPropertyIgnoreZero(Ord(psid_width), Val);

  Val := GetAttr('height');
  if Val <> '' then
    MapToDimensionPropertyIgnoreZero(Ord(psid_height), Val);

  Val := GetAttr('background');
  if Val <> '' then
    FStyle.AddProperty(Ord(psid_background_image), 'url(''' + Val + ''')');

  Val := GetAttr('bgcolor');
  if Val <> '' then
    FStyle.AddProperty(Ord(psid_background_color), Val);

  Val := GetAttr('align');
  if Val <> '' then
    MapAlignToTextAlign(Val)
  else
  begin
    // HTML spec presentational hint: when no align attribute exists on
    // the cell or any ancestor in the table hierarchy, td defaults to
    // 'start' (left) and th defaults to 'center'.  Check parent <tr>
    // first; if it has align, inherit that; otherwise apply the default.
    if Parent <> nil then
      Val := Parent.GetAttr('align');
    if Val <> '' then
      MapAlignToTextAlign(Val)
    else if Tag = PixieId('th') then
      FStyle.AddProperty(Ord(psid_text_align), 'center')
    else
      FStyle.AddProperty(Ord(psid_text_align), 'left');
  end;

  Val := GetAttr('valign');
  if Val <> '' then
    FStyle.AddProperty(Ord(psid_vertical_align), Val);

  // Inherit rules and cellpadding from ancestor table
  Table := FindAncestorTable(Self);
  if Table <> nil then
  begin
    if Table.Cellpadding <> '' then
      MapToPixelLengthProperty(Ord(psid_padding), Table.Cellpadding);

    // Set cell border style from the nearest ancestor table's border
    // attribute (UA descendant selectors can't distinguish nearest vs any)
    if (Table.Border <> '') and (Table.Border <> '0') then
      FStyle.AddProperty(Ord(psid_border_style), 'inset')
    else if Table.Border = '0' then
      FStyle.AddProperty(Ord(psid_border_style), 'none');

    if Table.Rules = 'all' then
      FStyle.AddProperty(Ord(psid_border), '1px solid')
    else if Table.Rules = 'rows' then
    begin
      FStyle.AddProperty(Ord(psid_border_top), '1px solid');
      FStyle.AddProperty(Ord(psid_border_bottom), '1px solid');
    end
    else if Table.Rules = 'cols' then
    begin
      FStyle.AddProperty(Ord(psid_border_left), '1px solid');
      FStyle.AddProperty(Ord(psid_border_right), '1px solid');
    end;
  end;

  inherited ParseAttributes;
end;

end.
