class_name DialogueCloud
extends CanvasLayer
## Dialogue panel — conversations and prop descriptions.

# Layout — anchor fractions used in multiple methods.
const _PANEL_TOP: float = 0.62
const _PANEL_TOP_EXPANDED: float = 0.28
const _PORTRAIT_GAP: float = 0.025

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

# Expand/collapse toggle. Tweens panel.anchor_top between the two values.
# In group mode also animates the portrait rects' anchor_bottom.
var _expanded: bool = false
var _expand_tween: Tween

# ── Meeting mode (user + N agents in one unified chat) ──────────────────
# Parallel to the 1:1 path — no shared mutable state between the two modes.
# conversation_history entries use {kind: user|agent|narration}.
# Portraits live OUTSIDE the panel as full-screen background TextureRects,
# not inside the panel as avatar thumbnails.
var meeting_mode: bool = false
var meeting_attendees: Array = []  # [{id, name}]
var _portrait_rects: Array = []    # TextureRect nodes added to CanvasLayer

# ── Widgets ─────────────────────────────────────────────────────────────
var panel: PanelContainer
var portrait_rect: TextureRect
var vbox: VBoxContainer
var header: HBoxContainer
var agent_label: Label
var mood_label: Label
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
# out the NEW portion — prior entries stay fully visible. Clicking the
# history scroll area skips the current reveal to full visibility.
var _typewriter_tween: Tween
var _prev_revealed_chars: int = 0

# Injected by world_loader.
var world_loader: WorldLoader


func _ready() -> void:
	# Layer 11 keeps the dialogue above the main-menu layer (10) so its
	# buttons always receive input first — even when the panel is expanded
	# into the top-right region where the menu stack lives.
	layer = 11
	_build_ui()
	panel.modulate.a = 0.0
	panel.visible = false
	portrait_rect.modulate.a = 0.0
	portrait_rect.visible = false


func _build_ui() -> void:
	# ── Full-screen graphic-novel portrait (behind the dialogue panel, 1:1 mode) ──
	portrait_rect = TextureRect.new()
	portrait_rect.name = "Portrait"
	portrait_rect.anchor_right = 1.0
	portrait_rect.anchor_bottom = 1.0
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait_rect)

	# ── Chat panel ──
	# Default: bottom ~38% of screen (anchor_top 0.62).
	# Expanded: ~72% of screen (anchor_top 0.28).
	# Group portraits fill the space above the panel.
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.10
	panel.anchor_right = 0.90
	panel.anchor_top = _PANEL_TOP
	panel.anchor_bottom = 0.97

	var style := UITheme.panel_style()
	style.shadow_color = UITheme.PANEL_SHADOW
	style.shadow_size = 6
	panel.add_theme_stylebox_override("panel", style)

	vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── Header ──
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)

	# End Meeting button — leftmost, visible only in meeting mode.
	# Calls world_loader.end_meeting() so the whole meeting teardown
	# path runs through the same place as the keyboard shortcut.
	_end_meeting_btn = Button.new()
	_end_meeting_btn.text = Strings.get_string("dialogue.end_meeting_btn").to_upper()
	_end_meeting_btn.add_theme_font_size_override("font_size", 32)
	_end_meeting_btn.flat = true
	_end_meeting_btn.add_theme_color_override("font_color", UITheme.WARN)
	_end_meeting_btn.add_theme_color_override("font_hover_color", UITheme.WARN_HOVER)
	_end_meeting_btn.pressed.connect(func() -> void:
		if world_loader != null:
			world_loader.end_meeting()
	)
	_end_meeting_btn.focus_mode = Control.FOCUS_NONE
	_end_meeting_btn.visible = false
	header.add_child(_end_meeting_btn)

	agent_label = Label.new()
	agent_label.add_theme_font_size_override("font_size", 32)
	agent_label.add_theme_color_override("font_color", UITheme.ACCENT)
	header.add_child(agent_label)

	mood_label = Label.new()
	mood_label.add_theme_font_size_override("font_size", 32)
	mood_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	header.add_child(mood_label)

	# Heart / stats button — visible only in 1:1 chat.
	# Hovering it opens a compact floating stats popup anchored to the button.
	_stats_btn = Button.new()
	_stats_btn.text = Strings.get_string("dialogue.stats_btn").to_upper()
	_stats_btn.custom_minimum_size = Vector2(22, 22)
	_stats_btn.add_theme_font_size_override("font_size", 32)
	_stats_btn.flat = true
	_stats_btn.add_theme_color_override("font_color", UITheme.DANGER)
	_stats_btn.add_theme_color_override("font_hover_color", UITheme.DANGER_HOVER)
	_stats_btn.focus_mode = Control.FOCUS_NONE
	_stats_btn.mouse_entered.connect(_show_stats_popup)
	_stats_btn.mouse_exited.connect(_hide_stats_popup)
	_stats_btn.visible = false
	header.add_child(_stats_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var _agent_log_btn := Button.new()
	_agent_log_btn.text = Strings.get_string("emotion.btn_agent_log").to_upper()
	_agent_log_btn.custom_minimum_size = Vector2(0, 24)
	_agent_log_btn.add_theme_font_size_override("font_size", 32)
	_agent_log_btn.flat = true
	_agent_log_btn.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_agent_log_btn.add_theme_color_override("font_hover_color", UITheme.ACCENT)
	_agent_log_btn.pressed.connect(_on_agent_log_pressed)
	_agent_log_btn.focus_mode = Control.FOCUS_NONE
	header.add_child(_agent_log_btn)

	_expand_btn = Button.new()
	_expand_btn.text = Strings.get_string("dialogue.expand").to_upper()
	_expand_btn.custom_minimum_size = Vector2(26, 24)
	_expand_btn.add_theme_font_size_override("font_size", 32)
	_expand_btn.flat = true
	_expand_btn.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_expand_btn.add_theme_color_override("font_hover_color", UITheme.ACCENT)
	_expand_btn.pressed.connect(_toggle_expand)
	_expand_btn.focus_mode = Control.FOCUS_NONE
	header.add_child(_expand_btn)

	close_btn = Button.new()
	close_btn.text = Strings.get_string("dialogue.close").to_upper()
	close_btn.custom_minimum_size = Vector2(24, 24)
	close_btn.add_theme_font_size_override("font_size", 32)
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	close_btn.add_theme_color_override("font_hover_color", UITheme.CLOSE_HOVER)
	close_btn.pressed.connect(_on_close_pressed)
	close_btn.focus_mode = Control.FOCUS_NONE
	header.add_child(close_btn)

	vbox.add_child(header)

	# ── History scroll ──
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 60)

	history_label = RichTextLabel.new()
	history_label.bbcode_enabled = true
	history_label.fit_content = true
	history_label.scroll_active = false
	history_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_label.add_theme_font_size_override("normal_font_size", 32)
	history_label.add_theme_font_size_override("bold_font_size", 32)
	history_label.add_theme_font_size_override("italics_font_size", 32)
	history_label.add_theme_color_override("default_color", UITheme.TEXT)

	scroll.add_child(history_label)
	scroll.gui_input.connect(_on_scroll_gui_input)
	vbox.add_child(scroll)

	# ── Separator ──
	separator = HSeparator.new()
	separator.add_theme_constant_override("separation", 2)
	separator.add_theme_stylebox_override("separator", UITheme.line_style())
	separator.visible = false
	vbox.add_child(separator)

	# ── Input row ──
	input_container = HBoxContainer.new()
	input_container.add_theme_constant_override("separation", 6)
	input_container.visible = false

	input_field = LineEdit.new()
	input_field.name = "ChatInput"
	input_field.placeholder_text = Strings.get_string("dialogue.placeholder")
	input_field.add_theme_font_size_override("font_size", 32)
	input_field.custom_minimum_size = Vector2(0, 32)
	input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_field.text_submitted.connect(_on_message_submitted)

	var input_style := UITheme.panel_style(UITheme.INPUT_BG, UITheme.INPUT_BORDER)
	input_style.content_margin_left = 10
	input_style.content_margin_right = 10
	input_style.content_margin_top = 6
	input_style.content_margin_bottom = 6
	input_field.add_theme_stylebox_override("normal", input_style)

	var focus_style := UITheme.panel_style(UITheme.INPUT_BG, UITheme.INPUT_FOCUS)
	focus_style.content_margin_left = 10
	focus_style.content_margin_right = 10
	focus_style.content_margin_top = 6
	focus_style.content_margin_bottom = 6
	input_field.add_theme_stylebox_override("focus", focus_style)

	input_field.add_theme_color_override("font_color", UITheme.TEXT)
	input_field.add_theme_color_override("font_placeholder_color", UITheme.INPUT_PLACEHOLDER)
	input_field.add_theme_color_override("caret_color", UITheme.ACCENT)

	input_container.add_child(input_field)

	send_btn = Button.new()
	send_btn.text = Strings.get_string("dialogue.send")
	send_btn.custom_minimum_size = Vector2(30, 32)
	send_btn.add_theme_font_size_override("font_size", 32)
	send_btn.flat = true
	send_btn.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	send_btn.add_theme_color_override("font_hover_color", UITheme.ACCENT)
	send_btn.focus_mode = Control.FOCUS_NONE
	send_btn.pressed.connect(func() -> void: _on_message_submitted(input_field.text))
	input_container.add_child(send_btn)

	vbox.add_child(input_container)
	panel.add_child(vbox)
	add_child(panel)

	# ── Floating stats popup (anchored to heart button, outside panel) ──
	_stats_popup = PanelContainer.new()
	_stats_popup.name = "StatsPopup"
	_stats_popup.custom_minimum_size = Vector2(520, 0)
	_stats_popup.visible = false
	_stats_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var popup_style := UITheme.panel_style()
	popup_style.content_margin_left = 8
	popup_style.content_margin_right = 8
	popup_style.content_margin_top = 4
	popup_style.content_margin_bottom = 4
	popup_style.shadow_color = UITheme.POPUP_SHADOW
	popup_style.shadow_size = 7
	_stats_popup.add_theme_stylebox_override("panel", popup_style)
	var popup_vbox := VBoxContainer.new()
	popup_vbox.add_theme_constant_override("separation", 2)
	# Mood row
	var mood_hbox := HBoxContainer.new()
	mood_hbox.add_theme_constant_override("separation", 5)
	_stats_popup_mood_dot = ColorRect.new()
	_stats_popup_mood_dot.custom_minimum_size = Vector2(8, 8)
	_stats_popup_mood_dot.color = UITheme.mood_color(UITheme.MOOD_NEUTRAL)
	_stats_popup_mood_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot_wrap := MarginContainer.new()
	dot_wrap.add_theme_constant_override("margin_top", 2)
	dot_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot_wrap.add_child(_stats_popup_mood_dot)
	mood_hbox.add_child(dot_wrap)
	_stats_popup_mood_emoji = Label.new()
	_stats_popup_mood_emoji.add_theme_font_override("font", UITheme.emoji_font())
	_stats_popup_mood_emoji.add_theme_font_size_override("font_size", 32)
	_stats_popup_mood_emoji.text = UITheme.mood_emoji(UITheme.MOOD_NEUTRAL)
	_stats_popup_mood_emoji.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mood_hbox.add_child(_stats_popup_mood_emoji)
	_stats_popup_mood_label = Label.new()
	_stats_popup_mood_label.add_theme_font_size_override("font_size", 32)
	_stats_popup_mood_label.add_theme_color_override("font_color", UITheme.TEXT)
	mood_hbox.add_child(_stats_popup_mood_label)
	popup_vbox.add_child(mood_hbox)
	var popup_sep := HSeparator.new()
	popup_sep.add_theme_constant_override("separation", 2)
	popup_sep.add_theme_stylebox_override("separator", UITheme.line_style())
	popup_vbox.add_child(popup_sep)
	# Stat bars — font_size 16 (on the pixel grid {16,32,48}) keeps the popup
	# short since metadata rows stack below.
	for bar_name: String in ["energy", "patience", "social_battery"]:
		var bar_key: String = "emotion." + bar_name
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var lbl := Label.new()
		lbl.text = Strings.get_string(bar_key).to_upper()
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		lbl.custom_minimum_size = Vector2(30, 0)
		row.add_child(lbl)
		var bar: ProgressBar = UITheme.build_stat_bar(bar_name, Vector2(0, 7))
		_stats_popup_bars[bar_name] = bar
		row.add_child(bar)
		popup_vbox.add_child(row)

	# Separator before the status rows (gateway / session).
	var status_sep := HSeparator.new()
	status_sep.add_theme_constant_override("separation", 1)
	status_sep.add_theme_stylebox_override("separator", UITheme.line_style())
	popup_vbox.add_child(status_sep)

	# Gateway row: [health dot] Gateway: id
	var gw_hbox := HBoxContainer.new()
	gw_hbox.add_theme_constant_override("separation", 5)
	_stats_popup_gateway_dot = ColorRect.new()
	_stats_popup_gateway_dot.custom_minimum_size = Vector2(8, 8)
	_stats_popup_gateway_dot.color = UITheme.HEALTH_UNKNOWN
	_stats_popup_gateway_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gw_dot_wrap := MarginContainer.new()
	gw_dot_wrap.add_theme_constant_override("margin_top", 2)
	gw_dot_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gw_dot_wrap.add_child(_stats_popup_gateway_dot)
	gw_hbox.add_child(gw_dot_wrap)
	_stats_popup_gateway_label = Label.new()
	_stats_popup_gateway_label.add_theme_font_size_override("font_size", 16)
	_stats_popup_gateway_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_stats_popup_gateway_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_popup_gateway_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gw_hbox.add_child(_stats_popup_gateway_label)
	popup_vbox.add_child(gw_hbox)

	# Session row
	_stats_popup_session_label = Label.new()
	_stats_popup_session_label.add_theme_font_size_override("font_size", 16)
	_stats_popup_session_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_stats_popup_session_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	popup_vbox.add_child(_stats_popup_session_label)

	_stats_popup.add_child(popup_vbox)
	add_child(_stats_popup)

	GatewayHealth.health_changed.connect(_on_stats_gateway_health_changed)


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
	var new_top: float = _PANEL_TOP_EXPANDED if _expanded else _PANEL_TOP
	var new_portrait_bottom: float = new_top - _PORTRAIT_GAP
	var expand_dur: float = GameState.get_ui_float("dialogue_expand", 0.22)
	if _expand_tween:
		_expand_tween.kill()
	_expand_tween = create_tween()
	_expand_tween.set_parallel(true)
	_expand_tween.tween_property(panel, "anchor_top", new_top, expand_dur) \
		.set_trans(Tween.TRANS_LINEAR)
	for rect: TextureRect in _portrait_rects:
		_expand_tween.tween_property(rect, "anchor_bottom", new_portrait_bottom, expand_dur) \
			.set_trans(Tween.TRANS_LINEAR)
	_update_expand_button()


func _update_expand_button() -> void:
	if not is_instance_valid(_expand_btn):
		return
	_expand_btn.text = Strings.get_string(
		"dialogue.collapse" if _expanded else "dialogue.expand"
	).to_upper()


# ── Public ──

func show_text(text: String, _duration: float = 0.0, agent_id: String = "") -> void:
	# Don't hijack an active player conversation with incoming agent thoughts.
	# The thought is still written to the world log by the caller.
	if is_input_mode:
		return
	conversation_history.clear()
	_prev_revealed_chars = 0
	agent_label.text = ""
	mood_label.text = ""
	close_btn.visible = true
	history_label.text = text
	_start_typewriter()
	separator.visible = false
	input_container.visible = false
	input_field.release_focus()
	is_input_mode = false
	current_agent_id = agent_id
	_load_portrait(agent_id)
	_fade_in()


func show_input(agent_id: String, agent_name: String) -> void:
	current_agent_id = agent_id
	conversation_history.clear()
	_prev_revealed_chars = 0
	# Pull any observations this agent had while the player wasn't listening —
	# they appear in the scrollback so the player can catch up on what they missed.
	var had_unread := false
	if world_loader:
		var agent = world_loader.find_agent(agent_id)
		if agent and agent.has_method("drain_unread_thoughts"):
			var unread: Array = agent.drain_unread_thoughts()
			if not unread.is_empty():
				had_unread = true
				var header_text := "◆ ─── %s ─── ◆" % Strings.get_string("dialogue.while_you_were_away").to_upper()
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
	agent_label.text = agent_name
	agent_label.add_theme_color_override("font_color", UITheme.agent_color(agent_id))
	mood_label.text = ""
	close_btn.visible = true
	_stats_btn.visible = true
	if had_unread:
		_render_history()
	else:
		history_label.text = "[color=#%s][i]%s[/i][/color]" % [UITheme.TEXT_DIM_HEX, Strings.get_string("dialogue.conversation_start")]
		_start_typewriter()
	is_input_mode = true
	separator.visible = true
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
	# Portraits live OUTSIDE the panel — N equal horizontal slices above it.
	# The panel header shows compact attendee names; no thumbnail strip inside.
	meeting_mode = true
	meeting_attendees = attendees.duplicate(true)
	current_agent_id = ""
	conversation_history.clear()
	_prev_revealed_chars = 0
	# Single-agent portrait hidden — replaced by group portraits outside.
	portrait_rect.texture = null
	portrait_rect.visible = false
	# Header: compact attendee names in accent color.
	var names: PackedStringArray = []
	for a: Dictionary in attendees:
		names.append(a.get("name", ""))
	var names_text: String = ", ".join(names)
	if names_text.length() > 32:
		names_text = names_text.substr(0, 30) + "…"
	agent_label.text = names_text
	agent_label.add_theme_color_override("font_color", UITheme.ACCENT)
	mood_label.text = ""
	close_btn.visible = true
	_end_meeting_btn.visible = true
	_stats_btn.visible = false
	# Opening narration line.
	conversation_history.append({
		"kind": "narration",
		"speaker_id": "",
		"speaker_name": "",
		"text": Strings.get_string("dialogue.meeting_opening", {"names": ", ".join(names)}),
	})
	_render_meeting_history()
	is_input_mode = true
	separator.visible = true
	input_container.visible = true
	input_field.editable = true
	input_field.placeholder_text = Strings.get_string("dialogue.meeting_placeholder")
	input_field.text = ""
	# Build and fade in group portraits THEN the panel.
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
	# Portrait rects fade out with the panel and are freed in _on_fade_out_done.
	_fade_out()


func show_response(agent_name: String, response: String) -> void:
	conversation_history.append({"speaker": agent_name, "text": response, "is_player": false})
	_render_history()
	is_showing = true
	is_input_mode = true
	separator.visible = true
	input_container.visible = true
	input_field.text = ""
	input_field.grab_focus()
	_scroll_to_bottom()


func set_mood(mood: String) -> void:
	mood_label.text = "" if mood == "" or mood == "neutral" else mood


func dismiss() -> void:
	if meeting_mode:
		# Emit — world_loader's handler calls end_meeting() which calls
		# close_meeting() to tear down the panel and the orchestrator.
		meeting_dismissed.emit()
		return
	if is_input_mode:
		dismissed.emit()
	current_agent_id = ""
	is_input_mode = false
	_fade_out()


# ── Group portraits ──────────────────────────────────────────────────────
# N portrait TextureRects added directly to the CanvasLayer (behind panel).
# Each occupies a 1/N horizontal slice of the screen from top=0 to just
# above the panel. They fade in with the panel and animate on expand.

func _build_group_portraits(attendees: Array) -> void:
	_clear_group_portraits()
	# Collect only attendees that have a portrait texture.
	var valid: Array = []
	for a: Dictionary in attendees:
		var id: String = a.get("id", "")
		var tex: Texture2D = GameState.load_agent_portrait_texture(id)
		if tex != null:
			valid.append({"id": id, "tex": tex, "name": a.get("name", "")})
	var n := valid.size()
	if n == 0:
		return
	# Portraits occupy the space above the panel with a small gap.
	var portrait_bottom: float = panel.anchor_top - _PORTRAIT_GAP
	var slice_w: float = 1.0 / float(n)
	for i in range(n):
		var entry: Dictionary = valid[i]
		var rect := TextureRect.new()
		rect.texture = entry["tex"]
		rect.anchor_left = i * slice_w
		rect.anchor_right = (i + 1) * slice_w
		rect.anchor_top = 0.0
		rect.anchor_bottom = portrait_bottom
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# CENTER keeps faces visible even in narrow slices.
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.modulate.a = 0.0   # _fade_in will reveal it
		add_child(rect)
		move_child(rect, 0)     # behind everything (panel, portrait_rect)
		_portrait_rects.append(rect)


func _clear_group_portraits() -> void:
	for rect: TextureRect in _portrait_rects:
		if is_instance_valid(rect):
			rect.queue_free()
	_portrait_rects.clear()


# ── Stats popup ──────────────────────────────────────────────────────────

func _show_stats_popup() -> void:
	if not _stats_btn.visible:
		return
	# Don't flash a big empty panel while agent/emotion data is still loading —
	# only render once the popup has populated rows.
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
	# Float above the button, horizontally centered on it, then clamp into the
	# viewport so the popup doesn't overflow off-screen on narrow windows.
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var margin: float = 8.0
	var x: float = btn_rect.position.x + btn_rect.size.x * 0.5 - popup_size.x * 0.5
	var max_x: float = vp_size.x - popup_size.x - margin
	if max_x < margin:
		max_x = margin
	x = clamp(x, margin, max_x)
	var y: float = btn_rect.position.y - popup_size.y - 6.0
	if y < margin:
		y = margin
	_stats_popup.position = Vector2(x, y)


func _refresh_stats_popup() -> bool:
	if world_loader == null or current_agent_id == "":
		return false
	var agent: Agent = world_loader.find_agent(current_agent_id)
	if agent == null:
		return false
	if agent.emotion_engine == null:
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

	# Status rows: gateway (with health dot) + session id.
	var gw_id: String = GameState.get_agent_gateway(current_agent_id)
	_stats_popup_gateway_label.text = "%s: %s" % [Strings.get_string("emotion.gateway"), gw_id]
	_apply_stats_gateway_health(gw_id)
	_stats_popup_session_label.text = "%s: %s" % [Strings.get_string("emotion.session"), GameState.get_agent_session(current_agent_id)]
	return true


func _pulse_stats_emoji() -> void:
	if _stats_popup_emoji_tween and _stats_popup_emoji_tween.is_valid():
		_stats_popup_emoji_tween.kill()
	_stats_popup_mood_emoji.scale = Vector2(1.0, 1.0)
	_stats_popup_mood_emoji.pivot_offset = _stats_popup_mood_emoji.size * 0.5
	_stats_popup_emoji_tween = create_tween()
	_stats_popup_emoji_tween.tween_property(_stats_popup_mood_emoji, "scale", Vector2(1.35, 1.35), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_stats_popup_emoji_tween.tween_property(_stats_popup_mood_emoji, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


func _apply_stats_gateway_health(gateway_id: String) -> void:
	if _stats_popup_gateway_dot == null:
		return
	if gateway_id == "":
		_stats_popup_gateway_dot.color = UITheme.HEALTH_UNKNOWN
		return
	var state: String = GatewayHealth.get_status(gateway_id)
	match state:
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

func _load_portrait(agent_id: String) -> void:
	var tex: Texture2D = GameState.load_agent_portrait_texture(agent_id)
	portrait_rect.texture = tex
	portrait_rect.visible = tex != null


# ── Fade ──

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
	if portrait_rect.visible:
		_fade_tween.tween_property(portrait_rect, "modulate:a", 1.0, fade_in_dur).set_trans(Tween.TRANS_LINEAR)
	# Group portraits fade in a touch slower for a layered atmospheric reveal.
	for rect: TextureRect in _portrait_rects:
		_fade_tween.tween_property(rect, "modulate:a", 0.82, portrait_in_dur).set_trans(Tween.TRANS_LINEAR)


func _fade_out() -> void:
	if _fade_tween:
		_fade_tween.kill()
	var fade_out_dur: float = GameState.get_ui_float("dialogue_fade_out", 0.12)
	var portrait_out_dur: float = GameState.get_ui_float("dialogue_portrait_fade_out", 0.15)
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(panel, "modulate:a", 0.0, fade_out_dur).set_trans(Tween.TRANS_LINEAR)
	_fade_tween.tween_property(portrait_rect, "modulate:a", 0.0, fade_out_dur).set_trans(Tween.TRANS_LINEAR)
	for rect: TextureRect in _portrait_rects:
		_fade_tween.tween_property(rect, "modulate:a", 0.0, portrait_out_dur).set_trans(Tween.TRANS_LINEAR)
	_fade_tween.chain().tween_callback(_on_fade_out_done)


func _on_fade_out_done() -> void:
	panel.visible = false
	portrait_rect.visible = false
	_clear_group_portraits()
	if _typewriter_tween and _typewriter_tween.is_valid():
		_typewriter_tween.kill()
	_prev_revealed_chars = 0
	history_label.visible_characters = -1
	# Reset expand state silently (panel is invisible, no animation needed).
	if _expanded:
		_expanded = false
		panel.anchor_top = _PANEL_TOP
		_update_expand_button()
	is_showing = false
	is_input_mode = false
	separator.visible = false
	input_container.visible = false
	input_field.release_focus()
	_stats_btn.visible = false
	_stats_popup.visible = false


# ── Input ──

func _input(event: InputEvent) -> void:
	# Use _input (not _unhandled) so we intercept Esc before LineEdit's
	# internal handler gets a chance to merely release focus instead of
	# closing the panel. set_input_as_handled prevents LineEdit from
	# receiving the event at all.
	if not is_showing:
		return
	if event.is_action_pressed("ui_cancel"):
		# Esc hierarchy: if a LogModal (agent log / world log) is open, it owns
		# Esc. Let the modal close itself; don't also dismiss the dialogue.
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
		append_meeting_line(
			"player",
			Strings.get_string("dialogue.you"),
			trimmed,
			"user",
		)
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
	for msg: Dictionary in conversation_history:
		var kind: String = msg.get("kind", "")
		var text: String = msg.get("text", "")
		var speaker_id: String = msg.get("speaker_id", "")
		var speaker_name: String = msg.get("speaker_name", "")
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
	history_label.text = bbcode
	_start_typewriter()


func _render_history() -> void:
	var agent_hex: String = UITheme.agent_color_hex(current_agent_id)
	var player_hex: String = "#" + UITheme.TEXT_PLAYER_HEX
	var dim_hex: String = "#" + UITheme.TEXT_DIM_HEX
	var bbcode := ""
	for msg in conversation_history:
		if msg.get("is_player", false):
			bbcode += Strings.get_string("dialogue.player_line", {
				"color": player_hex,
				"name": Strings.get_string("dialogue.you"),
				"text": msg["text"],
			}) + "\n"
		elif msg.get("is_thought", false):
			# Unread thoughts render dim + italic so they read as "passive
			# observation the player missed", not as spoken dialogue.
			bbcode += Strings.get_string("dialogue.thought_line", {
				"color": dim_hex,
				"name": msg["speaker"],
				"text": msg["text"],
			}) + "\n"
		elif msg["speaker"] == "":
			bbcode += "%s\n" % msg["text"]
		else:
			bbcode += Strings.get_string("dialogue.agent_line", {
				"color": agent_hex,
				"name": msg["speaker"],
				"text": msg["text"],
			}) + "\n"
	history_label.text = bbcode
	_start_typewriter()


# ── Typewriter ───────────────────────────────────────────────────────────
# Pin visible_characters to the previous total BEFORE the new bbcode parses
# so already-revealed lines stay frozen and only the appended suffix types
# out. One process_frame wait lets RichTextLabel finish its threaded parse
# and report an accurate get_total_character_count().

func _start_typewriter() -> void:
	if _typewriter_tween and _typewriter_tween.is_valid():
		_typewriter_tween.kill()
	history_label.visible_characters = _prev_revealed_chars
	await get_tree().process_frame
	var total: int = history_label.get_total_character_count()
	if total <= _prev_revealed_chars:
		history_label.visible_characters = -1
		_prev_revealed_chars = total
		return
	var cps: float = GameState.get_ui_float("typewriter_chars_per_second", 40.0)
	var duration: float = float(total - _prev_revealed_chars) / max(cps, 1.0)
	_typewriter_tween = create_tween()
	_typewriter_tween.tween_property(history_label, "visible_characters", total, duration) \
		.set_trans(Tween.TRANS_LINEAR)
	_typewriter_tween.tween_callback(_on_typewriter_done.bind(total))


func _on_typewriter_done(total: int) -> void:
	history_label.visible_characters = -1
	_prev_revealed_chars = total


func _skip_typewriter() -> void:
	if _typewriter_tween and _typewriter_tween.is_valid():
		_typewriter_tween.kill()
	var total: int = history_label.get_total_character_count()
	history_label.visible_characters = -1
	_prev_revealed_chars = total


func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if _typewriter_tween and _typewriter_tween.is_valid():
			_skip_typewriter()


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	if scroll:
		scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value
