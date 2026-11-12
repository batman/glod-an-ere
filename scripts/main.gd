extends Node2D
## Glue: runs the simulation, handles mouse/touch input and context menus.

const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.5

var game := Game.new()
var view: WorldView
var cam: Camera2D
var ui: GameUI
var speed := 1.0

var _touches := {}
var _press_pos = null
var _panned := false
var _pinch_dist := 0.0


var _autosave := 0.0


func _ready() -> void:
	if not game.load_game():
		game.new_game(randi())
	view = WorldView.new()
	add_child(view)
	view.setup(game)
	cam = Camera2D.new()
	add_child(cam)
	cam.position = WorldView.node_pos(game.hq_pos)
	cam.zoom = Vector2(1.2, 1.2)
	ui = GameUI.new()
	add_child(ui)
	ui.setup(self)
	game.message.connect(ui.toast)
	ui.toast("Tippe auf eine freie Wiese, um zu bauen. Verbinde alles mit Pfaden.")


func new_game() -> void:
	cancel_road()
	clear_selection()
	game.new_game(randi())
	cam.position = WorldView.node_pos(game.hq_pos)
	game.save_game()
	ui.toast("Ein neues Land wartet auf dich.")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		game.save_game()


func _process(delta: float) -> void:
	_autosave += delta
	if _autosave >= 30.0:
		_autosave = 0.0
		game.save_game()
	var dt := delta * speed
	while dt > 0.0:
		var s := minf(dt, 0.1)
		game.step(s)
		dt -= s


func set_speed(s: float) -> void:
	speed = s


# ---------- camera ----------

func _world(screen: Vector2) -> Vector2:
	return cam.position + (screen - get_viewport_rect().size / 2.0) / cam.zoom.x


func _pan(rel: Vector2) -> void:
	cam.position -= rel / cam.zoom.x
	var max_pos := WorldView.node_pos(Vector2i(Game.W - 1, Game.H - 1))
	cam.position = cam.position.clamp(Vector2.ZERO, max_pos)


func _zoom_by(factor: float, screen: Vector2) -> void:
	var before := _world(screen)
	var z := clampf(cam.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	cam.zoom = Vector2(z, z)
	cam.position += before - _world(screen)


func _pinch() -> float:
	var pts: Array = _touches.values()
	return pts[0].distance_to(pts[1]) if pts.size() >= 2 else 0.0


# ---------- input ----------

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
			if _touches.size() == 1:
				_press_pos = e.position
				_panned = false
			else:
				_pinch_dist = _pinch()
				_panned = true
		else:
			_touches.erase(e.index)
			if _touches.is_empty():
				if not _panned and _press_pos != null:
					_tap(e.position)
				_press_pos = null
	elif e is InputEventScreenDrag:
		_touches[e.index] = e.position
		if _touches.size() >= 2:
			var d := _pinch()
			if _pinch_dist > 0.0 and d > 0.0:
				var pts: Array = _touches.values()
				_zoom_by(d / _pinch_dist, (pts[0] + pts[1]) / 2.0)
			_pinch_dist = d
		elif _press_pos != null and (_panned or e.position.distance_to(_press_pos) > 12.0):
			_panned = true
			_pan(e.relative)
	elif e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press_pos = e.position
				_panned = false
			else:
				if _press_pos != null and not _panned:
					_tap(e.position)
				_press_pos = null
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(1.1, e.position)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / 1.1, e.position)
		elif e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			cancel_road()
	elif e is InputEventMouseMotion:
		if view.road_from != null:
			view.set_hover(WorldView.to_node(_world(e.position)))
		if (e.button_mask & MOUSE_BUTTON_MASK_LEFT) and _press_pos != null:
			if _panned or e.position.distance_to(_press_pos) > 6.0:
				_panned = true
				_pan(e.relative)


func _tap(screen: Vector2) -> void:
	var p := WorldView.to_node(_world(screen))
	if not game.in_bounds(p):
		return
	if view.road_from != null:
		if p == view.road_from:
			cancel_road()
			return
		var err := game.build_road(view.road_from, p)
		if err != "":
			ui.toast(err)
			return
		cancel_road()
		return
	select(p)


# ---------- selection & menus ----------

func clear_selection() -> void:
	view.selected = null
	ui.hide_menu()


func cancel_road() -> void:
	view.road_from = null
	view.set_hover(null)
	ui.hide_hint()


func select(p: Vector2i) -> void:
	view.selected = p
	if game.buildings.has(p):
		_building_menu(p)
	elif game.flags.has(p):
		_flag_menu(p)
	elif game.road_at.has(p):
		_road_menu(p)
	elif game.is_free(p):
		_build_menu(p)
	else:
		clear_selection()


func _build_menu(p: Vector2i) -> void:
	var items := [{"text": "Flagge", "icon": "flag", "enabled": game.can_place_flag(p),
		"cb": func(): _do(func(): game.place_flag(p))}]
	var any: bool = game.can_place_flag(p)
	for type in Game.BUILD_ORDER:
		if not game.is_unlocked(type):
			continue
		var def: Dictionary = Game.DEFS[type]
		var ok := game.can_place_building(type, p)
		any = any or ok
		items.append({"text": "%s · %s" % [def.name, _cost_text(def.cost)], "icon": def.icon, "enabled": ok,
			"cb": func(): _do(func(): game.place_building(type, p))})
	var info := "Was soll hier entstehen?" if any else "Hier ist zu wenig Platz."
	ui.show_menu("Bauplatz", func(): return info, items)


func _flag_menu(p: Vector2i) -> void:
	var items := [{"text": "Pfad anlegen", "icon": "road", "cb": func(): _start_road(p)}]
	if p != game.hq_pos + Game.FLAG_OFFSET:
		items.append({"text": "Flagge abreißen", "icon": "trash", "cb": func(): _do(func(): game.demolish_flag(p))})
	ui.show_menu("Flagge", func():
		return "Waren an dieser Flagge: %d" % game.flags[p].items.size() if game.flags.has(p) else "", items)


func _road_menu(p: Vector2i) -> void:
	var r: Dictionary = game.road_at[p]
	var items := [
		{"text": "Flagge setzen", "icon": "flag", "enabled": game.can_place_flag(p),
			"cb": func(): _do(func(): game.place_flag(p))},
		{"text": "Pfad entfernen", "icon": "trash", "cb": func(): _do(func(): game.demolish_road(r))},
	]
	ui.show_menu("Pfad", func(): return "Jede Flagge teilt den Pfad. Jeder Abschnitt bekommt einen eigenen Träger, so fließen mehr Waren.", items)


func _building_menu(p: Vector2i) -> void:
	var b: Dictionary = game.buildings[p]
	var items := []
	if b.type != "hq":
		items.append({"text": "Abreißen", "icon": "trash", "cb": func(): _do(func(): game.demolish_building(p))})
	ui.show_menu(Game.DEFS[b.type].name, func(): return _building_info(p), items)


func _building_info(p: Vector2i) -> String:
	if not game.buildings.has(p):
		return ""
	var b: Dictionary = game.buildings[p]
	if b.type == "hq":
		var lines := ["Hier lagern deine Waren."]
		for w in game.unlocked_wares():
			lines.append("%s: %d" % [Game.WARE_NAMES[w], b.stock.get(w, 0)])
		return "\n".join(lines)
	var text: String = b.status
	if not b.built and not b.need.is_empty():
		text += "\nFehlt noch: " + _cost_text(b.need)
	if b.built:
		for w in Game.DEFS[b.type].get("in", {}):
			text += "\n%s vorrätig: %d" % [Game.WARE_NAMES[w], b.stock.get(w, 0)]
	if b.built and not b.out.is_empty():
		text += "\nAbholbereit: %d" % b.out.size()
	return text


func _cost_text(cost: Dictionary) -> String:
	var parts := []
	for w in cost:
		parts.append("%d %s" % [cost[w], Game.WARE_NAMES[w]])
	return ", ".join(parts) if not parts.is_empty() else "kostenlos"


func _start_road(p: Vector2i) -> void:
	clear_selection()
	view.road_from = p
	ui.show_hint("Tippe auf das Ziel des Pfads.")


func _do(action: Callable) -> void:
	action.call()
	clear_selection()
