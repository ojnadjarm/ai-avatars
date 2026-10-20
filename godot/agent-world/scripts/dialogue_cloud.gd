class_name DialogueCloud
extends CanvasLayer
## Dialogue box: framed blinking portrait, name plate, typed history, chat input; group meetings show a portrait row above it.

const PortraitView := preload("res://scripts/hud/portrait_view.gd")
const MARGIN := 8
const PANEL_H := 136
const PANEL_H_EXPANDED := 300
const GROUP_GAP := 4
const PORTRAIT_K := 1
const STATS_W := 156

## Emitted when the player closes the dialogue — world_loader uses this to
## release any talking agent back to its normal state.
signal dismissed
## Emitted when the player closes the dialogue while meeting mode is
## active — world_loader uses this to tear down MeetingOrchestrator and
## end the meeting.
signal meeting_dismissed

# ── State ───────────────────────────────────────────────────────────────
var is_showing := false
var is_input_mode := false
var current_agent_id: String = ""
var conversation_history: Array = []

var _expanded: bool = false
var _expand_tween: Tween

# ── Meeting mode (user + N agents in one unified chat) ──────────────────
# conversation_history entries use {kind: user|agent|narration}.
var meeting_mode: bool = false
var meeting_attendees: Array = []  # [{id, name}]
var _group_views: Dictionary = {}  # agent_id -> PortraitView

# ── Widgets ─────────────────────────────────────────────────────────────
var panel: PanelContainer
var portrait: PortraitView
var name_tag: Label
var vbox: VBoxContainer
var header: HBoxContainer
var agent_label: Label
var mood_label: Label
var _group_row: HBoxContainer
var _end_meeting_btn: Button
var _expand_btn: Button
var _stats_btn: Button
var _stats_popup: PanelContainer
var _stats_popup_mood_dot: ColorRect
var _stats_popup_mood_emoji: Label
var _stats_popup_mood_label: Label
var _stats_popup_bars: Dictionary = {}
var _stats_popup_gateway_dot: ColorRect
var _stats_popup_gateway_label: Label
var _stats_popup_session_label: Label
var _stats_popup_last_mood: String = ""
var _stats_popup_emoji_tween: Tween
var close_btn: Button
var scroll: ScrollContainer
var history_label: RichTextLabel
var separator: HSeparator
var input_container: HBoxContainer
var input_field: LineEdit
var send_btn: Button
var _fade_tween: Tween

# ── Typewriter reveal ───────────────────────────────────────────────────
# Letters unveil one at a time via RichTextLabel.visible_characters.
# _prev_revealed_chars tracks how many characters were already fully
# revealed BEFORE the latest render, so appending a new entry only types
# out the NEW portion. Clicking the history skips the reveal.
var _typewriter_tween: Tween
var _prev_revealed_chars: int = 0
var _speaker_id: String = ""

# Injected by world_loader.
var world_loader: WorldLoader


func _ready() -> void:
	# Layer 11 keeps the dialogue above the main-menu layer (10).
	layer = 11
	_build_ui()
	panel.modulate.a = 0.0
	panel.visible = false
	_group_row.modulate.a = 0.0
	_group_row.visible = false


func _build_ui() -> void:
	_group_row = HBoxContainer.new()
	_group_row.name = "GroupPortraits"
	_group_row.anchor_left = 0.0
	_group_row.anchor_right = 1.0
	_group_row.anchor_top = 1.0
	_group_row.anchor_bottom = 1.0
	_group_row.offset_bottom = -(MARGIN + PANEL_H + GROUP_GAP)
	_group_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_group_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_group_row.add_theme_constant_override("separation", 8)
	_group_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_group_row)

	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = MARGIN
	panel.offset_right = -MARGIN
	panel.offset_bottom = -MARGIN
	panel.offset_top = -(MARGIN + PANEL_H)
	panel.add_theme_stylebox_override("panel", UITheme.kit_style("dialogue", 10, 8))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	portrait = PortraitView.new()
	portrait.name = "Portrait"
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	portrait.visible = false
	row.add_child(portrait)

	vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(vbox)

	# ── Header: name plate, mood, quiet pills on the right ──
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)

	_end_meeting_btn = _pill("dialogue.end_meeting_btn", func() -> void:
		if world_loader != null:
			world_loader.end_meeting())
	_end_meeting_btn.add_theme_color_override("font_color", UITheme.WARN)
	_end_meeting_btn.add_theme_color_override("font_hover_color", UITheme.WARN_HOVER)
	_end_meeting_btn.visible = false
	header.add_child(_end_meeting_btn)

	name_tag = PortraitView.name_tag("")
	name_tag.visible = false
	header.add_child(name_tag)
	agent_label = name_tag

	mood_label = Label.new()
	mood_label.add_theme_font_override("font", _hud_font())
	mood_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HUD)
	mood_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	mood_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(mood_label)

	# Stats pill — visible only in 1:1 chat; hovering opens the stats popup.
	_stats_btn = _pill("dialogue.stats_btn", Callable())
	_stats_btn.add_theme_color_override("font_color", UITheme.DANGER)
	_stats_btn.add_theme_color_override("font_hover_color", UITheme.DANGER_HOVER)
	_stats_btn.mouse_entered.connect(_show_stats_popup)
	_stats_btn.mouse_exited.connect(_hide_stats_popup)
	_stats_btn.visible = false
	header.add_child(_stats_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)

	header.add_child(_pill("emotion.btn_agent_log", _on_agent_log_pressed))
	_expand_btn = _pill("dialogue.expand", _toggle_expand)
	header.add_child(_expand_btn)
	close_btn = _pill("dialogue.close", _on_close_pressed)
	close_btn.add_theme_color_override("font_hover_color", UITheme.CLOSE_HOVER)
	header.add_child(close_btn)
	vbox.add_child(header)

	# ── History scroll ──
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 36)

	history_label = RichTextLabel.new()
	history_label.bbcode_enabled = true
	history_label.fit_content = true
	history_label.scroll_active = false
	history_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	history_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	history_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key: String in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		history_label.add_theme_font_size_override(key, UITheme.FONT_SIZE_BODY)
	history_label.add_theme_color_override("default_color", UITheme.TEXT)
	history_label.add_theme_constant_override("line_separation", 0)
	# Room past the last line so the scroll can rest on a whole top line.
	var tail := StyleBoxEmpty.new()
	tail.content_margin_bottom = UITheme.FONT_SIZE_BODY * 2
	history_label.add_theme_stylebox_override("normal", tail)

	scroll.add_child(history_label)
	scroll.gui_input.connect(_on_scroll_gui_input)
	vbox.add_child(scroll)

	# Kept for callers; the input field's own frame separates it.
	separator = HSeparator.new()
	separator.visible = false
	vbox.add_child(separator)

	# ── Input row ──
	input_container = HBoxContainer.new()
	input_container.add_theme_constant_override("separation", 4)
	input_container.visible = false

	input_field = LineEdit.new()
	input_field.name = "ChatInput"
	input_field.placeholder_text = Strings.get_string("dialogue.placeholder")
	input_field.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_field.text_submitted.connect(_on_message_submitted)
	input_container.add_child(input_field)

	send_btn = UITheme.action_button(Strings.get_string("dialogue.send"))
	send_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	send_btn.pressed.connect(func() -> void: _on_message_submitted(input_field.text))
	input_container.add_child(send_btn)

	vbox.add_child(input_container)
	add_child(panel)
	_build_stats_popup()
	GatewayHealth.health_changed.connect(_on_stats_gateway_health_changed)


func _hud_font() -> Font:
	UITheme.ensure_fonts_loaded()
	return UITheme.FONT_HUD


func _pill(key: String, action: Callable) -> Button:
	var btn := UITheme.prominent_button(Strings.get_string(key))
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if action.is_valid():
		btn.pressed.connect(action)
	return btn


func _build_stats_popup() -> void:
	_stats_popup = PanelContainer.new()
	_stats_popup.name = "StatsPopup"
	_stats_popup.custom_minimum_size = Vector2(STATS_W, 0)
	_stats_popup.visible = false
	_stats_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_popup.add_theme_stylebox_override("panel", UITheme.kit_style("tooltip", 6, 4))
	var popup_vbox := VBoxContainer.new()
	popup_vbox.add_theme_constant_override("separation", 2)
	var mood_hbox := HBoxContainer.new()
	mood_hbox.add_theme_constant_override("separation", 4)
	_stats_popup_mood_dot = _status_dot(UITheme.mood_color(UITheme.MOOD_NEUTRAL))
	mood_hbox.add_child(_stats_popup_mood_dot)
	_stats_popup_mood_emoji = Label.new()
	_stats_popup_mood_emoji.add_theme_font_override("font", UITheme.emoji_font())
	_stats_popup_mood_emoji.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	_stats_popup_mood_emoji.text = UITheme.mood_emoji(UITheme.MOOD_NEUTRAL)
	_stats_popup_mood_emoji.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mood_hbox.add_child(_stats_popup_mood_emoji)
	_stats_popup_mood_label = Label.new()
	_stats_popup_mood_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	_stats_popup_mood_label.add_theme_color_override("font_color", UITheme.TEXT)
	mood_hbox.add_child(_stats_popup_mood_label)
	popup_vbox.add_child(mood_hbox)
	popup_vbox.add_child(HSeparator.new())
	for bar_name: String in ["energy", "patience", "social_battery"]:
		var bar_row := HBoxContainer.new()
		bar_row.add_theme_constant_override("separation", 4)
		var lbl := _hud_label(Strings.get_string("emotion." + bar_name).to_upper())
		lbl.custom_minimum_size = Vector2(24, 0)
		bar_row.add_child(lbl)
		var bar: ProgressBar = UITheme.build_stat_bar(bar_name, Vector2(0, 6))
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_stats_popup_bars[bar_name] = bar
		bar_row.add_child(bar)
		popup_vbox.add_child(bar_row)
	popup_vbox.add_child(HSeparator.new())
	var gw_hbox := HBoxContainer.new()
	gw_hbox.add_theme_constant_override("separation", 4)
	_stats_popup_gateway_dot = _status_dot(UITheme.HEALTH_UNKNOWN)
	gw_hbox.add_child(_stats_popup_gateway_dot)
	_stats_popup_gateway_label = _hud_label("")
	_stats_popup_gateway_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_popup_gateway_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gw_hbox.add_child(_stats_popup_gateway_label)
	popup_vbox.add_child(gw_hbox)
	_stats_popup_session_label = _hud_label("")
	_stats_popup_session_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	popup_vbox.add_child(_stats_popup_session_label)
	_stats_popup.add_child(popup_vbox)
	add_child(_stats_popup)


func _status_dot(color: Color) -> ColorRect:
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(4, 4)
	dot.color = color
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dot


func _hud_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", _hud_font())
	lbl.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HUD)
	lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


# ── Expand / collapse ────────────────────────────────────────────────────

func _on_agent_log_pressed() -> void:
	if current_agent_id == "" or world_loader == null:
		return
	var agent: Agent = world_loader.find_agent(current_agent_id)
	if agent == null or agent.emotion_engine == null:
		return
	var lines: Array[String] = []
	var now: int = int(Time.get_unix_time_from_system())
	for entry in agent.emotion_engine.full_log():
		var d: Dictionary = entry
		var reason: String = d.get("reason", "")
		var t: int = int(d.get("t", 0))
		var delta: int = now - t
		var stamp: String = ""
		if t > 0:
			if delta < 60:
				stamp = "%ds ago" % delta
			elif delta < 3600:
				stamp = "%dm ago" % (delta / 60)
			else:
				stamp = "%dh ago" % (delta / 3600)
		if stamp != "":
			lines.append("[color=#%s]%s[/color]  [color=#%s]%s[/color]" % [UITheme.TIMESTAMP_HEX, stamp, UITheme.TEXT_HEX, reason])
		else:
			lines.append("[color=#%s]%s[/color]" % [UITheme.TEXT_HEX, reason])
	var title: String = Strings.get_string("log_modal.title_agent", {"name": agent.display_name})
	LogModal.show_entries(get_tree().root, title, lines)


func _toggle_expand() -> void:
	_expanded = not _expanded
	var expand_dur: float = GameState.get_ui_float("dialogue_expand", 0.22)
	if _expand_tween:
		_expand_tween.kill()
	_expand_tween = create_tween()
	_expand_tween.set_parallel(true)
	_expand_tween.tween_property(panel, "offset_top", -float(MARGIN + _panel_height()), expand_dur) \
		.set_trans(Tween.TRANS_LINEAR)
	if meeting_mode:
		_expand_tween.tween_property(_group_row, "modulate:a", 0.0 if _expanded else 1.0, expand_dur)
	_update_expand_button()


func _panel_height() -> int:
	return PANEL_H_EXPANDED if _expanded else PANEL_H


func _update_expand_button() -> void:
	if not is_instance_valid(_expand_btn):
		return
	_expand_btn.text = Strings.get_string("dialogue.collapse" if _expanded else "dialogue.expand").to_upper()


# ── Public ──

func show_text(text: String, _duration: float = 0.0, agent_id: String = "") -> void:
	# Don't hijack an active player conversation with incoming agent thoughts.
	if is_input_mode:
		return
	conversation_history.clear()
	_prev_revealed_chars = 0
	_set_name("", UITheme.ACCENT)
	mood_label.text = ""
	close_btn.visible = true
	current_agent_id = agent_id
	_speaker_id = agent_id
	history_label.text = text
	_start_typewriter()
	input_container.visible = false
	input_field.release_focus()
	is_input_mode = false
	_load_portrait(agent_id)
	_fade_in()


func show_input(agent_id: String, agent_name: String) -> void:
	current_agent_id = agent_id
	conversation_history.clear()
	_prev_revealed_chars = 0
	# Observations this agent had while the player wasn't listening appear in the scrollback.
	var had_unread := false
	if world_loader:
		var agent = world_loader.find_agent(agent_id)
		if agent and agent.has_method("drain_unread_thoughts"):
			var unread: Array = agent.drain_unread_thoughts()
			if not unread.is_empty():
				had_unread = true
				var header_text := "%s" % Strings.get_string("dialogue.while_you_were_away").to_upper()
				conversation_history.append({
					"speaker": "",
					"text": "[color=#%s]%s[/color]" % [UITheme.ACCENT_HEX, header_text],
					"is_player": false,
				})
				for thought in unread:
					conversation_history.append({
						"speaker": agent_name,
						"text": thought,
						"is_player": false,
						"is_thought": true,
					})
	_set_name(agent_name, UITheme.agent_color(agent_id))
	mood_label.text = ""
	close_btn.visible = true
	_stats_btn.visible = true
	_speaker_id = ""
	if had_unread:
		_render_history()
	else:
		history_label.text = "[color=#%s][i]%s[/i][/color]" % [UITheme.TEXT_DIM_HEX, Strings.get_string("dialogue.conversation_start")]
		_start_typewriter()
	is_input_mode = true
	input_container.visible = true
	input_field.text = ""
	_load_portrait(agent_id)
	_fade_in()
	if had_unread:
		_scroll_to_bottom()
	await get_tree().process_frame
	input_field.grab_focus()


func show_meeting(attendees: Array) -> void:
	# attendees: Array of {id: String, name: String}
	meeting_mode = true
	meeting_attendees = attendees.duplicate(true)
	current_agent_id = ""
	conversation_history.clear()
	_prev_revealed_chars = 0
	portrait.set_frames([])
	var names: PackedStringArray = []
	for a: Dictionary in attendees:
		names.append(a.get("name", ""))
	_set_name("", UITheme.ACCENT)
	mood_label.text = ""
	close_btn.visible = true
	_end_meeting_btn.visible = true
	_stats_btn.visible = false
	conversation_history.append({
		"kind": "narration",
		"speaker_id": "",
		"speaker_name": "",
		"text": Strings.get_string("dialogue.meeting_opening", {"names": ", ".join(names)}),
	})
	_render_meeting_history()
	is_input_mode = true
	input_container.visible = true
	input_field.editable = true
	input_field.placeholder_text = Strings.get_string("dialogue.meeting_placeholder")
	input_field.text = ""
	_build_group_portraits(attendees)
	_fade_in()
	await get_tree().process_frame
	input_field.grab_focus()


func append_meeting_line(speaker_id: String, speaker_name: String, text: String, kind: String) -> void:
	if not meeting_mode:
		return
	conversation_history.append({
		"kind": kind,
		"speaker_id": speaker_id,
		"speaker_name": speaker_name,
		"text": text,
	})
	_render_meeting_history()
	_scroll_to_bottom()


func set_meeting_input_enabled(enabled: bool) -> void:
	if not meeting_mode:
		return
	input_field.editable = enabled
	if enabled:
		input_field.placeholder_text = Strings.get_string("dialogue.meeting_placeholder")
		await get_tree().process_frame
		input_field.grab_focus()
	else:
		input_field.placeholder_text = Strings.get_string("dialogue.meeting_thinking")


func close_meeting() -> void:
	meeting_mode = false
	meeting_attendees.clear()
	conversation_history.clear()
	input_field.placeholder_text = Strings.get_string("dialogue.placeholder")
	input_field.editable = true
	_end_meeting_btn.visible = false
	_fade_out()


func show_response(agent_name: String, response: String) -> void:
	conversation_history.append({"speaker": agent_name, "text": response, "is_player": false})
	_render_history()
	is_showing = true
	is_input_mode = true
	input_container.visible = true
	input_field.text = ""
	if input_field.is_inside_tree():
		input_field.grab_focus()
	_scroll_to_bottom()


func set_mood(mood: String) -> void:
	mood_label.text = "" if mood == "" or mood == "neutral" else mood.to_upper()


func dismiss() -> void:
	if meeting_mode:
		# world_loader's handler calls end_meeting() which calls close_meeting().
		meeting_dismissed.emit()
		return
	if is_input_mode:
		dismissed.emit()
	current_agent_id = ""
	is_input_mode = false
	_fade_out()


# ── Group portraits ──────────────────────────────────────────────────────

func _build_group_portraits(attendees: Array) -> void:
	_clear_group_portraits()
	for a: Dictionary in attendees:
		var id: String = a.get("id", "")
		var view := PortraitView.new()
		if not view.show_agent(id, PORTRAIT_K):
			view.free()
			continue
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", -6)
		col.alignment = BoxContainer.ALIGNMENT_END
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(view)
		var tag := PortraitView.name_tag(a.get("name", id), UITheme.agent_color(id))
		tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(tag)
		_group_row.add_child(col)
		_group_views[id] = view
	_group_row.visible = not _group_views.is_empty()


func _clear_group_portraits() -> void:
	for child: Node in _group_row.get_children():
		child.queue_free()
	_group_views.clear()


# ── Stats popup ──────────────────────────────────────────────────────────

func _show_stats_popup() -> void:
	if not _stats_btn.visible:
		return
	if not _refresh_stats_popup():
		return
	_stats_popup.visible = true
	_stats_popup.reset_size()
	call_deferred("_position_stats_popup")


func _hide_stats_popup() -> void:
	_stats_popup.visible = false


func _position_stats_popup() -> void:
	if not is_instance_valid(_stats_btn) or not is_instance_valid(_stats_popup):
		return
	_stats_popup.reset_size()
	var btn_rect: Rect2 = _stats_btn.get_global_rect()
	var popup_size: Vector2 = _stats_popup.size
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var x: float = btn_rect.position.x + btn_rect.size.x * 0.5 - popup_size.x * 0.5
	x = clampf(x, MARGIN, maxf(MARGIN, vp_size.x - popup_size.x - MARGIN))
	var y: float = maxf(MARGIN, btn_rect.position.y - popup_size.y - 4.0)
	_stats_popup.position = Vector2(x, y).round()


func _refresh_stats_popup() -> bool:
	if world_loader == null or current_agent_id == "":
		return false
	var agent: Agent = world_loader.find_agent(current_agent_id)
	if agent == null or agent.emotion_engine == null:
		return false
	var emo: Dictionary = agent.emotion_engine.to_dict()
	var mood: String = emo.get("mood", UITheme.MOOD_NEUTRAL)
	_stats_popup_mood_label.text = mood.capitalize()
	_stats_popup_mood_dot.color = UITheme.mood_color(mood)
	_stats_popup_mood_emoji.text = UITheme.mood_emoji(mood)
	if mood != _stats_popup_last_mood:
		_pulse_stats_emoji()
	_stats_popup_last_mood = mood
	for bar_name: String in _stats_popup_bars:
		var val = emo.get(bar_name)
		if val != null:
			(_stats_popup_bars[bar_name] as ProgressBar).value = float(val)
	var gw_id: String = GameState.get_agent_gateway(current_agent_id)
	_stats_popup_gateway_label.text = "%s: %s" % [Strings.get_string("emotion.gateway").to_upper(), gw_id]
	_apply_stats_gateway_health(gw_id)
	_stats_popup_session_label.text = "%s: %s" % [Strings.get_string("emotion.session").to_upper(), GameState.get_agent_session(current_agent_id)]
	return true


func _pulse_stats_emoji() -> void:
	if _stats_popup_emoji_tween and _stats_popup_emoji_tween.is_valid():
		_stats_popup_emoji_tween.kill()
	_stats_popup_mood_emoji.scale = Vector2.ONE
	_stats_popup_mood_emoji.pivot_offset = _stats_popup_mood_emoji.size * 0.5
	_stats_popup_emoji_tween = create_tween()
	_stats_popup_emoji_tween.tween_property(_stats_popup_mood_emoji, "scale", Vector2(2, 2), 0.12)
	_stats_popup_emoji_tween.tween_property(_stats_popup_mood_emoji, "scale", Vector2.ONE, 0.18)


func _apply_stats_gateway_health(gateway_id: String) -> void:
	if _stats_popup_gateway_dot == null:
		return
	if gateway_id == "":
		_stats_popup_gateway_dot.color = UITheme.HEALTH_UNKNOWN
		return
	match GatewayHealth.get_status(gateway_id):
		GatewayHealth.STATE_OK:
			_stats_popup_gateway_dot.color = UITheme.HEALTH_OK
		GatewayHealth.STATE_FAIL:
			_stats_popup_gateway_dot.color = UITheme.HEALTH_FAIL
		_:
			_stats_popup_gateway_dot.color = UITheme.HEALTH_UNKNOWN


func _on_stats_gateway_health_changed(gateway_id: String, _state: String) -> void:
	if current_agent_id == "":
		return
	if GameState.get_agent_gateway(current_agent_id) == gateway_id:
		_apply_stats_gateway_health(gateway_id)


# ── Internals ────────────────────────────────────────────────────────────

func _set_name(text: String, color: Color) -> void:
	name_tag.text = text
	name_tag.add_theme_color_override("font_color", color)
	name_tag.visible = text != ""


func _load_portrait(agent_id: String) -> void:
	portrait.show_agent(agent_id, PORTRAIT_K)


func _fade_in() -> void:
	if _fade_tween:
		_fade_tween.kill()
	panel.visible = true
	is_showing = true
	var fade_in_dur: float = GameState.get_ui_float("dialogue_fade_in", 0.18)
	var portrait_in_dur: float = GameState.get_ui_float("dialogue_portrait_fade_in", 0.28)
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(panel, "modulate:a", 1.0, fade_in_dur).set_trans(Tween.TRANS_LINEAR)
	if meeting_mode and not _group_views.is_empty():
		_group_row.visible = true
		_fade_tween.tween_property(_group_row, "modulate:a", 0.0 if _expanded else 1.0, portrait_in_dur).set_trans(Tween.TRANS_LINEAR)


func _fade_out() -> void:
	if _fade_tween:
		_fade_tween.kill()
	var fade_out_dur: float = GameState.get_ui_float("dialogue_fade_out", 0.12)
	var portrait_out_dur: float = GameState.get_ui_float("dialogue_portrait_fade_out", 0.15)
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(panel, "modulate:a", 0.0, fade_out_dur).set_trans(Tween.TRANS_LINEAR)
	_fade_tween.tween_property(_group_row, "modulate:a", 0.0, portrait_out_dur).set_trans(Tween.TRANS_LINEAR)
	_fade_tween.chain().tween_callback(_on_fade_out_done)


func _on_fade_out_done() -> void:
	panel.visible = false
	_group_row.visible = false
	_clear_group_portraits()
	portrait.set_frames([])
	if _typewriter_tween and _typewriter_tween.is_valid():
		_typewriter_tween.kill()
	_prev_revealed_chars = 0
	history_label.visible_characters = -1
	if _expanded:
		_expanded = false
		panel.offset_top = -float(MARGIN + PANEL_H)
		_update_expand_button()
	is_showing = false
	is_input_mode = false
	input_container.visible = false
	input_field.release_focus()
	_stats_btn.visible = false
	_stats_popup.visible = false


# ── Input ──

func _input(event: InputEvent) -> void:
	# _input (not _unhandled) so Esc closes the panel before LineEdit merely releases focus.
	if not is_showing:
		return
	if event.is_action_pressed("ui_cancel"):
		# A LogModal owns Esc while open.
		if LogModal.is_any_open():
			return
		get_viewport().set_input_as_handled()
		dismiss()


func _on_close_pressed() -> void:
	dismiss()


func _on_message_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed == "":
		return
	if meeting_mode:
		append_meeting_line("player", Strings.get_string("dialogue.you"), trimmed, "user")
		input_field.text = ""
		set_meeting_input_enabled(false)
		if world_loader:
			world_loader.request_meeting_message(trimmed)
		return
	if current_agent_id == "":
		return
	conversation_history.append({"speaker": Strings.get_string("dialogue.you"), "text": trimmed, "is_player": true})
	conversation_history.append({"speaker": "", "text": "[i]...[/i]", "is_player": false})
	_render_history()
	_scroll_to_bottom()
	input_field.text = ""
	input_field.grab_focus()
	if world_loader:
		world_loader.request_agent_talk(current_agent_id, trimmed)


# ── Rendering ──

func _render_meeting_history() -> void:
	var bbcode := ""
	_speaker_id = ""
	for msg: Dictionary in conversation_history:
		var kind: String = msg.get("kind", "")
		var text: String = msg.get("text", "")
		var speaker_id: String = msg.get("speaker_id", "")
		var speaker_name: String = msg.get("speaker_name", "")
		_speaker_id = speaker_id if kind == "agent" else ""
		if kind == "narration":
			bbcode += Strings.get_string("dialogue.meeting_narration_line", {
				"color": "#" + UITheme.TEXT_DIM_HEX,
				"text": text,
			}) + "\n"
		elif kind == "user":
			bbcode += Strings.get_string("dialogue.meeting_user_line", {
				"color": "#" + UITheme.TEXT_PLAYER_HEX,
				"name": speaker_name,
				"text": text,
			}) + "\n"
		else:
			bbcode += Strings.get_string("dialogue.meeting_speaker_line", {
				"color": UITheme.agent_color_hex(speaker_id),
				"name": speaker_name,
				"text": text,
			}) + "\n"
	history_label.text = bbcode.strip_edges(false, true)
	_start_typewriter()


func _render_history() -> void:
	var agent_hex: String = UITheme.agent_color_hex(current_agent_id)
	var player_hex: String = "#" + UITheme.TEXT_PLAYER_HEX
	var dim_hex: String = "#" + UITheme.TEXT_DIM_HEX
	var bbcode := ""
	_speaker_id = ""
	for msg in conversation_history:
		_speaker_id = ""
		if msg.get("is_player", false):
			bbcode += Strings.get_string("dialogue.player_line", {
				"color": player_hex,
				"name": Strings.get_string("dialogue.you"),
				"text": msg["text"],
			}) + "\n"
		elif msg.get("is_thought", false):
			bbcode += Strings.get_string("dialogue.thought_line", {
				"color": dim_hex,
				"name": msg["speaker"],
				"text": msg["text"],
			}) + "\n"
		elif msg["speaker"] == "":
			bbcode += "%s\n" % msg["text"]
		else:
			_speaker_id = current_agent_id
			bbcode += Strings.get_string("dialogue.agent_line", {
				"color": agent_hex,
				"name": msg["speaker"],
				"text": msg["text"],
			}) + "\n"
	history_label.text = bbcode.strip_edges(false, true)
	_start_typewriter()


# ── Typewriter ───────────────────────────────────────────────────────────
# Pin visible_characters to the previous total BEFORE the new bbcode parses
# so already-revealed lines stay frozen and only the appended suffix types
# out. The speaking agent's portrait opens its mouth while it types.

func _start_typewriter() -> void:
	if _typewriter_tween and _typewriter_tween.is_valid():
		_typewriter_tween.kill()
	history_label.visible_characters = _prev_revealed_chars
	await get_tree().process_frame
	var total: int = history_label.get_total_character_count()
	if total <= _prev_revealed_chars:
		history_label.visible_characters = -1
		_prev_revealed_chars = total
		_set_talking(false)
		return
	var cps: float = GameState.get_ui_float("typewriter_chars_per_second", 40.0)
	var duration: float = float(total - _prev_revealed_chars) / max(cps, 1.0)
	_set_talking(true)
	_typewriter_tween = create_tween()
	_typewriter_tween.tween_method(_reveal, _prev_revealed_chars, total, duration)
	_typewriter_tween.tween_callback(_on_typewriter_done.bind(total))


## Shows the first `n` characters and keeps the line being typed in view.
func _reveal(n: int) -> void:
	history_label.visible_characters = n
	var line: int = history_label.get_character_line(maxi(n - 1, 0))
	if line < 0 or scroll == null:
		return
	var bottom: float = history_label.get_line_offset(line + 1) if line + 1 < history_label.get_line_count() else float(history_label.get_content_height())
	scroll.scroll_vertical = _line_aligned_top(bottom)


## Scroll offset that starts on a whole line and keeps history y `bottom` in view.
func _line_aligned_top(bottom: float) -> int:
	var top: float = bottom - scroll.size.y
	if top <= 0.0:
		return 0
	for i in history_label.get_line_count():
		if history_label.get_line_offset(i) >= top:
			return int(history_label.get_line_offset(i))
	return int(top)


func _on_typewriter_done(total: int) -> void:
	history_label.visible_characters = -1
	_prev_revealed_chars = total
	_set_talking(false)


func _skip_typewriter() -> void:
	if _typewriter_tween and _typewriter_tween.is_valid():
		_typewriter_tween.kill()
	var total: int = history_label.get_total_character_count()
	history_label.visible_characters = -1
	_prev_revealed_chars = total
	_set_talking(false)


## Open-mouth animation on the portrait of whoever is typing out, off for everyone else.
func _set_talking(on: bool) -> void:
	portrait.talking = on and _speaker_id != "" and _speaker_id == current_agent_id
	for id: String in _group_views:
		(_group_views[id] as PortraitView).talking = on and id == _speaker_id


func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if _typewriter_tween and _typewriter_tween.is_valid():
			_skip_typewriter()


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	if scroll:
		scroll.scroll_vertical = _line_aligned_top(history_label.get_content_height())
