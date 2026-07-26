unit Pixie.StringId;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, {$IFNDEF FPC}TypInfo,{$ENDIF} Generics.Collections;

type
  TPixieStringId = (
    // HTML tags
    psid_a,
    psid_abbr,
    psid_acronym,
    psid_address,
    psid_applet,
    psid_area,
    psid_article,
    psid_aside,
    psid_audio,
    psid_b,
    psid_base,
    psid_basefont,
    psid_bdi,
    psid_bdo,
    psid_bgsound,
    psid_big,
    psid_blink,
    psid_blockquote,
    psid_body,
    psid_br,
    psid_button,
    psid_canvas,
    psid_caption,
    psid_center,
    psid_cite,
    psid_code,
    psid_col,
    psid_colgroup,
    psid_data,
    psid_datalist,
    psid_dd,
    psid_del,
    psid_desc,
    psid_details,
    psid_dfn,
    psid_dialog,
    psid_dir,
    psid_div,
    psid_dl,
    psid_dt,
    psid_em,
    psid_embed,
    psid_fieldset,
    psid_figcaption,
    psid_figure,
    psid_footer,
    psid_foreignobject,
    psid_form,
    psid_frame,
    psid_frameset,
    psid_h1,
    psid_h2,
    psid_h3,
    psid_h4,
    psid_h5,
    psid_h6,
    psid_head,
    psid_header,
    psid_hgroup,
    psid_hr,
    psid_html,
    psid_i,
    psid_iframe,
    psid_image,
    psid_img,
    psid_input,
    psid_ins,
    psid_isindex,
    psid_kbd,
    psid_keygen,
    psid_label,
    psid_legend,
    psid_li,
    psid_link,
    psid_listing,
    psid_main,
    psid_malignmark,
    psid_map,
    psid_mark,
    psid_marquee,
    psid_math,
    psid_menu,
    psid_menuitem,
    psid_meta,
    psid_meter,
    psid_mglyph,
    psid_mi,
    psid_mn,
    psid_mo,
    psid_ms,
    psid_mtext,
    psid_multicol,
    psid_nav,
    psid_nextid,
    psid_nobr,
    psid_noembed,
    psid_noframes,
    psid_noscript,
    psid_object,
    psid_ol,
    psid_optgroup,
    psid_option,
    psid_output,
    psid_p,
    psid_param,
    psid_picture,
    psid_plaintext,
    psid_pre,
    psid_progress,
    psid_q,
    psid_rb,
    psid_rp,
    psid_rt,
    psid_rtc,
    psid_ruby,
    psid_s,
    psid_samp,
    psid_script,
    psid_search,
    psid_section,
    psid_select,
    psid_small,
    psid_source,
    psid_spacer,
    psid_span,
    psid_strike,
    psid_strong,
    psid_style,
    psid_sub,
    psid_summary,
    psid_sup,
    psid_svg,
    psid_table,
    psid_tbody,
    psid_td,
    psid_template,
    psid_textarea,
    psid_tfoot,
    psid_th,
    psid_thead,
    psid_time,
    psid_title,
    psid_tr,
    psid_track,
    psid_tt,
    psid_u,
    psid_ul,
    psid_var,
    psid_video,
    psid_wbr,
    psid_xmp,
    psid_annotation_xml,

    // Internal pseudo-element tags
    psid__tag_before,
    psid__tag_after,

    // CSS pseudo-elements
    psid_before,
    psid_after,

    // CSS pseudo-classes
    psid_root,
    psid_only_child,
    psid_only_of_type,
    psid_first_child,
    psid_first_of_type,
    psid_last_child,
    psid_last_of_type,
    psid_nth_child,
    psid_nth_of_type,
    psid_nth_last_child,
    psid_nth_last_of_type,
    psid_is,
    psid_not,
    psid_lang,
    psid_active,
    psid_hover,
    psid_checked,
    psid_disabled,
    psid_enabled,
    psid_focus,

    // CSS property names
    psid_background,
    psid_background_color,
    psid_background_image,
    psid_background_image_baseurl,
    psid_background_repeat,
    psid_background_origin,
    psid_background_clip,
    psid_background_attachment,
    psid_background_size,
    psid_background_position,
    psid_background_position_x,
    psid_background_position_y,
    psid_background_gradient,

    psid_border,
    psid_border_width,
    psid_border_style,
    psid_border_color,

    psid_border_spacing,
    psid__pixie_border_spacing_x,
    psid__pixie_border_spacing_y,

    psid_border_top,
    psid_border_right,
    psid_border_bottom,
    psid_border_left,

    psid_border_top_style,
    psid_border_right_style,
    psid_border_bottom_style,
    psid_border_left_style,

    psid_border_top_width,
    psid_border_right_width,
    psid_border_bottom_width,
    psid_border_left_width,

    psid_border_top_color,
    psid_border_right_color,
    psid_border_bottom_color,
    psid_border_left_color,

    psid_border_radius,
    psid_border_radius_x,
    psid_border_radius_y,

    psid_border_top_left_radius,
    psid_border_top_right_radius,
    psid_border_bottom_right_radius,
    psid_border_bottom_left_radius,

    psid_border_top_left_radius_x,
    psid_border_top_right_radius_x,
    psid_border_bottom_right_radius_x,
    psid_border_bottom_left_radius_x,

    psid_border_top_left_radius_y,
    psid_border_top_right_radius_y,
    psid_border_bottom_right_radius_y,
    psid_border_bottom_left_radius_y,

    psid_outline,
    psid_outline_width,
    psid_outline_style,
    psid_outline_color,

    psid_list_style,
    psid_list_style_type,
    psid_list_style_position,
    psid_list_style_image,
    psid_list_style_image_baseurl,

    psid_margin,
    psid_margin_top,
    psid_margin_right,
    psid_margin_bottom,
    psid_margin_left,

    psid_padding,
    psid_padding_top,
    psid_padding_right,
    psid_padding_bottom,
    psid_padding_left,

    psid_font,
    psid_font_family,
    psid_font_style,
    psid_font_variant,
    psid_font_variant_caps,
    psid_font_weight,
    psid_font_size,
    psid_line_height,
    psid_text_decoration,
    psid_text_decoration_style,
    psid_text_decoration_line,
    psid_text_decoration_color,
    psid_text_decoration_thickness,
    psid_text_emphasis,
    psid_text_emphasis_style,
    psid_text_emphasis_color,
    psid_text_emphasis_position,

    psid_white_space,
    psid_text_align,
    psid_vertical_align,
    psid_color,
    psid_width,
    psid_height,
    psid_min_width,
    psid_min_height,
    psid_max_width,
    psid_max_height,
    psid_position,
    psid_overflow,
    psid_overflow_x,
    psid_overflow_y,
    psid_display,
    psid_visibility,
    psid_user_select,
    psid_appearance,
    psid_box_sizing,
    psid_z_index,
    psid_float,
    psid_clear,
    psid_text_indent,
    psid_top,
    psid_right,
    psid_bottom,
    psid_left,
    psid_cursor,
    psid_content,
    psid_border_collapse,
    psid_table_layout,
    psid_text_transform,
    psid_transform,
    psid_transform_origin,

    psid_flex,
    psid_flex_flow,
    psid_flex_direction,
    psid_flex_wrap,
    psid_justify_content,
    psid_align_items,
    psid_align_content,
    psid_align_self,
    psid_flex_grow,
    psid_flex_shrink,
    psid_flex_basis,

    psid_gap,
    psid_row_gap,
    psid_column_gap,
    psid_grid_gap,
    psid_grid_row_gap,
    psid_grid_column_gap,

    psid_grid_template_columns,
    psid_grid_template_rows,
    psid_grid_column_start,
    psid_grid_column_end,
    psid_grid_row_start,
    psid_grid_row_end,
    psid_grid_column,
    psid_grid_row,
    psid_justify_items,
    psid_justify_self,

    psid_caption_side,
    psid_order,

    psid_opacity,
    psid_overflow_wrap,
    psid_word_wrap,

    // SVG presentation properties (raw-string values; consumed by inline-SVG
    // bridge in Pixie.ElSvg, not by HTML layout/paint)
    psid_fill,
    psid_stroke,
    psid_stroke_width,
    psid_fill_opacity,
    psid_stroke_opacity,
    psid_fill_rule,

    psid_counter_reset,
    psid_counter_increment,

    // CSS dimensions
    psid_deg,
    psid_grad,
    psid_rad,
    psid_turn,

    // CSS property values
    psid_initial,
    psid_auto,
    psid_none,
    psid_linear_gradient,
    psid_repeating_linear_gradient,
    psid_radial_gradient,
    psid_repeating_radial_gradient,
    psid_conic_gradient,
    psid_repeating_conic_gradient,

    // at-rules and their components
    psid_charset,
    psid_layer,
    psid_import,
    psid_media,
    psid_font_face,
    psid_supports,
    psid_and,
    psid_or,
    psid_boolean,
    psid_plain,
    psid_range,
    psid_discrete,
    psid_integer,
    psid_length,
    psid_resolution,
    psid_ratio,
    psid_keyword,
    psid_orientation,
    psid_portrait,
    psid_landscape,
    psid_prefers_color_scheme,
    psid_light,
    psid_dark,
    psid_device_width,
    psid_device_height,
    psid_aspect_ratio,
    psid_device_aspect_ratio,
    psid_color_index,
    psid_monochrome
  );

var
  PixieEmptyId: Integer;
  PixieStarId: Integer;

function PixieId(const S: string): Integer;
function PixieStr(ID: Integer): string;

const
  // Inline-SVG-only CSS presentation properties: stored as raw strings by
  // Pixie.Style and surfaced as XML attributes by Pixie.ElSvg. Used by both
  // sites so the recognized set stays in lockstep.
  PixieSvgPresentationPropIds: array[0..5] of TPixieStringId = (
    psid_fill,
    psid_stroke,
    psid_stroke_width,
    psid_fill_opacity,
    psid_stroke_opacity,
    psid_fill_rule
  );

implementation

type
  TStringIdMap = TDictionary<string, Integer>;
  TIdStringArray = TList<string>;

var
  IdMap: TStringIdMap;
  IdArray: TIdStringArray;

function EnumToString(Id: TPixieStringId): string;
var
  S: string;
  I: Integer;
begin
  // Get the enum name using RTTI
  // We manually build the name from the enum constant
  // The enum names follow pattern psid_xxx where xxx maps to the CSS string
  // with underscores replaced by hyphens
  S := '';
  {$IFDEF FPC}
  WriteStr(S, Id);
  {$ELSE}
  S := GetEnumName(TypeInfo(TPixieStringId), Ord(Id));
  {$ENDIF}

  // Strip 'psid_' prefix
  if (Length(S) > 5) and (StrLComp(PChar(S), 'psid_', 5) = 0) then
    S := Copy(S, 6, Length(S) - 5);

  // Replace underscores with hyphens
  for I := 1 to Length(S) do
    if S[I] = '_' then
      S[I] := '-';

  Result := S;
end;

function PixieId(const S: string): Integer;
var
  LowerS: string;
  I: Integer;
begin
  LowerS := S;
  for I := 1 to Length(LowerS) do
    if (LowerS[I] >= 'A') and (LowerS[I] <= 'Z') then
      LowerS[I] := Chr(Ord(LowerS[I]) + 32);

  if IdMap.TryGetValue(LowerS, Result) then
    Exit;

  // Not found: add as dynamic ID
  IdArray.Add(LowerS);
  Result := IdArray.Count - 1;
  IdMap.Add(LowerS, Result);
end;

function PixieStr(ID: Integer): string;
begin
  if (ID >= 0) and (ID < IdArray.Count) then
    Result := IdArray[ID]
  else
    Result := '';
end;

procedure InitStringIds;
var
  Id: TPixieStringId;
  S: string;
  Idx: Integer;
begin
  IdMap := TStringIdMap.Create;
  IdArray := TIdStringArray.Create;

  for Id := Low(TPixieStringId) to High(TPixieStringId) do
  begin
    S := EnumToString(Id);
    IdArray.Add(S);
    Idx := Ord(Id);
    if not IdMap.ContainsKey(S) then
      IdMap.Add(S, Idx);
  end;

  PixieEmptyId := PixieId('');
  PixieStarId := PixieId('*');
end;

initialization
  InitStringIds;

finalization
  IdMap.Free;
  IdArray.Free;

end.
