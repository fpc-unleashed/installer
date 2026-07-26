unit Pixie.Iterators;

// Render tree traversal — iterates through children of a render item,
// optionally descending into inline parents and selecting specific items.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Pixie.Types, Pixie.RenderItem;

type
  TPixieIteratorItemType = (iitChild, iitStartParent, iitEndParent);

  TPixieIteratorCallback = procedure(El: TPixieRenderItem;
    ItemType: TPixieIteratorItemType) of object;

  TPixieIteratorSelect = function(El: TPixieRenderItem): Boolean;

procedure PixieIterateElements(Container: TPixieRenderItem;
  ReturnParents: Boolean;
  GoInside: TPixieIteratorSelect;
  Select: TPixieIteratorSelect;
  Callback: TPixieIteratorCallback);

// Selector functions for inline context
function PixieGoInsideInline(El: TPixieRenderItem): Boolean;
function PixieSelectInline(El: TPixieRenderItem): Boolean;

implementation

procedure PixieIterateElements(Container: TPixieRenderItem;
  ReturnParents: Boolean;
  GoInside: TPixieIteratorSelect;
  Select: TPixieIteratorSelect;
  Callback: TPixieIteratorCallback);

  procedure Process(Cont: TPixieRenderItem);
  var
    I: Integer;
    El: TPixieRenderItem;
  begin
    for I := 0 to Cont.FChildren.Count - 1 do
    begin
      El := Cont.FChildren[I];
      if Assigned(GoInside) and GoInside(El) then
      begin
        if ReturnParents then
          Callback(El, iitStartParent);
        Process(El);
        if ReturnParents then
          Callback(El, iitEndParent);
      end
      else
      begin
        if (not Assigned(Select)) or Select(El) then
          Callback(El, iitChild);
      end;
    end;
  end;

begin
  Process(Container);
end;

function PixieGoInsideInline(El: TPixieRenderItem): Boolean;
begin
  Result := (El.SrcEl.Css.Display = displayInline) and
            (El.SrcEl.Css.Float_ = efNone);
end;

function PixieSelectInline(El: TPixieRenderItem): Boolean;
begin
  Result := (El.SrcEl.Css.Display in [displayInlineText, displayInlineTable,
             displayInlineBlock, displayInlineFlex, displayInlineGrid]) or
            (El.SrcEl.Css.Float_ <> efNone);
end;

end.
