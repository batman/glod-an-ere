class_name GameUI
extends CanvasLayer
## Top bar, context panel, hint bar and toasts. Built in code, touch friendly.

const BUTTON_HEIGHT := 56

var main
var _ware_labels := {}
var _ware_flow: HFlowContainer
var _shown_era := -1
var _goal_label: Label
var _scroll: ScrollContainer
var _new_armed := 0.0
var _panel: PanelContainer
var _title: Label
var _info: Label
var _buttons: VBoxContainer
var _info_provider := Callable()
var _hint: PanelContainer
var _hint_label: Label
var _toast: PanelContainer
var _toast_label: Label
var _toast_time := 0.0


func setup(m) -> void:
	main = m
	var theme := Theme.new()
	theme.default_font_size = 20
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	add_child(root)

	# Top bar
	var top := _panel_box()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 20)
	top.add_child(bar)
	_ware_flow = HFlowContainer.new()
	_ware_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ware_flow.add_theme_constant_override("h_separation", 18)
	bar.add_child(_ware_flow)
	var trophy := TextureRect.new()
	trophy.texture = load("res://icons/trophy.svg")
	trophy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	trophy.custom_minimum_size = Vector2(26, 26)
	trophy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(trophy)
	_goal_label = Label.new()
	bar.add_child(_goal_label)
	var group := ButtonGroup.new()
	for s in [[0.0, "player-pause"], [1.0, "player-play"], [3.0, "player-track-next"]]:
		var b := _icon_button(s[1])
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(BUTTON_HEIGHT, BUTTON_HEIGHT)
		b.button_pressed = s[0] == 1.0
		b.pressed.connect(main.set_speed.bind(s[0]))
		bar.add_child(b)
	var fresh := _icon_button("refresh")
	fresh.custom_minimum_size = Vector2(BUTTON_HEIGHT, BUTTON_HEIGHT)
	fresh.pressed.connect(_on_new_game)
	bar.add_child(fresh)

	# Context panel on the right
	_panel = _panel_box()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -350
	_panel.offset_right = -12
	_panel.offset_top = 130
	_panel.visible = false
	root.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_panel.add_child(vb)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	vb.add_child(_title)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(310, 0)
	vb.add_child(_info)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(_scroll)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 8)
	_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_buttons)

	# Hint bar (road drawing)
	_hint = _panel_box()
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -280
	_hint.offset_right = 280
	_hint.offset_top = -86
	_hint.offset_bottom = -16
	_hint.visible = false
	root.add_child(_hint)
	var hb := HBoxContainer.new()
	_hint.add_child(hb)
	_hint_label = Label.new()
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_hint_label)
	var cancel := _icon_button("x", "Abbrechen")
	cancel.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	cancel.pressed.connect(main.cancel_road)
	hb.add_child(cancel)

	# Toast
	_toast = _panel_box()
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_left = -280
	_toast.offset_right = 280
	_toast.offset_top = -160
	_toast.offset_bottom = -100
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	root.add_child(_toast)
	_toast_label = Label.new()
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_label)


func _panel_box() -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.09, 0.08, 0.9)
	s.set_corner_radius_all(10)
	s.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", s)
	return p


func _icon_button(icon_name: String, text := "") -> Button:
	var b := Button.new()
	b.icon = load("res://icons/%s.svg" % icon_name)
	b.text = text
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 28)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT if text != "" else HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	return b


## items: Array of {text, icon, cb: Callable, enabled: bool}
func show_menu(title: String, info_provider: Callable, items: Array) -> void:
	_title.text = title
	_info_provider = info_provider
	_info.text = info_provider.call()
	for c in _buttons.get_children():
		c.queue_free()
	for it in items:
		var b := _icon_button(it.icon, it.text)
		b.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
		b.disabled = not it.get("enabled", true)
		b.pressed.connect(it.cb)
		_buttons.add_child(b)
	var close := _icon_button("x", "Schließen")
	close.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	close.pressed.connect(main.clear_selection)
	_buttons.add_child(close)
	var wanted := (items.size() + 1) * (BUTTON_HEIGHT + 8)
	var room: float = get_viewport().get_visible_rect().size.y - 330.0
	_scroll.custom_minimum_size = Vector2(0, clampf(wanted, BUTTON_HEIGHT, maxf(room, BUTTON_HEIGHT * 3)))
	_panel.visible = true


func hide_menu() -> void:
	_panel.visible = false
	_info_provider = Callable()


func show_hint(text: String) -> void:
	_hint_label.text = text
	_hint.visible = true


func hide_hint() -> void:
	_hint.visible = false


func toast(text: String) -> void:
	_toast_label.text = text
	_toast.visible = true
	_toast_time = 3.0


func _on_new_game() -> void:
	if _new_armed > 0.0:
		_new_armed = 0.0
		main.new_game()
	else:
		_new_armed = 3.0
		toast("Nochmal tippen, um ein neues Spiel zu beginnen.")


func _rebuild_wares() -> void:
	for c in _ware_flow.get_children():
		c.queue_free()
	_ware_labels.clear()
	for w in main.game.unlocked_wares():
		var box := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.color = WorldView.WARE_COLORS[w]
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(swatch)
		var l := Label.new()
		box.add_child(l)
		_ware_flow.add_child(box)
		_ware_labels[w] = l


func _process(delta: float) -> void:
	_new_armed = maxf(0.0, _new_armed - delta)
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast.visible = false
	if main == null:
		return
	var g: Game = main.game
	if _shown_era != g.era:
		_shown_era = g.era
		_rebuild_wares()
	var stock: Dictionary = g.hq().stock
	for w in _ware_labels:
		_ware_labels[w].text = "%s %d" % [Game.WARE_NAMES[w], stock.get(w, 0)]
	var era: Dictionary = Game.ERAS[g.era]
	if g.won:
		_goal_label.text = "%s · Gewonnen!" % era.name
	else:
		var parts := []
		var prog := g.goal_progress()
		for w in era.goal:
			parts.append("%s %d/%d" % [Game.WARE_NAMES[w], prog[w], era.goal[w]])
		_goal_label.text = "%s · Ziel: %s" % [era.name, ", ".join(parts)]
	if _panel.visible and _info_provider.is_valid():
		_info.text = _info_provider.call()
