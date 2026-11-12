class_name WorldView
extends Node2D
## Draws the map and everything on it. All art is simple original shapes.

const TILE := 40.0
const WARE_COLORS := {
	"log": Color("8b5a2b"), "pole": Color("e3b873"), "stone": Color("a3a8ad"), "food": Color("c8433a"),
	"copper_ore": Color("4fa38f"), "copper": Color("d9813b"), "tin_ore": Color("6b7486"), "bronze": Color("b8913a"),
	"iron_ore": Color("8e4a3a"), "iron": Color("5a6068"), "tool": Color("e8e2d0"),
}
const DEPOSIT_COLORS := {
	Game.ROCK: Color(0.55, 0.56, 0.58), Game.COPPER: Color(0.36, 0.6, 0.54),
	Game.TIN: Color(0.42, 0.46, 0.55), Game.IRON: Color(0.55, 0.32, 0.25),
}

var game: Game
var icons := {}
var selected = null          # Vector2i or null
var road_from = null         # Vector2i or null while drawing a road
var hover = null             # Vector2i under the pointer while drawing a road
var _preview: Array = []


func setup(g: Game) -> void:
	game = g
	for b in Game.DEFS.values():
		icons[b.icon] = load("res://icons/%s.svg" % b.icon)
	icons["hammer"] = load("res://icons/hammer.svg")


static func node_pos(p: Vector2i) -> Vector2:
	return Vector2(p) * TILE


static func to_node(world: Vector2) -> Vector2i:
	return Vector2i(roundi(world.x / TILE), roundi(world.y / TILE))


func set_hover(p) -> void:
	if p == hover:
		return
	hover = p
	_preview = []
	if road_from != null and hover != null and game.in_bounds(hover) and hover != road_from:
		_preview = game.find_path(road_from, hover)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	_draw_terrain()
	for r in game.roads:
		_draw_road(r)
	if _preview.size() > 1:
		var pts := PackedVector2Array()
		for p in _preview:
			pts.append(node_pos(p))
		draw_polyline(pts, Color(1, 1, 1, 0.55), 5.0, true)
	for b in game.buildings.values():
		_draw_building(b)
	for f in game.flags.values():
		_draw_flag(f)
	for r in game.roads:
		_draw_carrier(r)
	if selected != null:
		draw_arc(node_pos(selected), TILE * 0.5, 0, TAU, 32, Color(1, 0.95, 0.4), 3.0, true)
	if road_from != null:
		draw_arc(node_pos(road_from), TILE * 0.45, 0, TAU, 32, Color(0.5, 1, 0.6), 3.0, true)


func _draw_terrain() -> void:
	var half := TILE / 2.0
	for y in Game.H:
		for x in Game.W:
			var p := Vector2i(x, y)
			var c := node_pos(p)
			var t := game.terrain_at(p)
			var shade := float(((x * 73856093) ^ (y * 19349663)) & 7) / 7.0
			var base := Color(0.33, 0.52, 0.27).lerp(Color(0.38, 0.58, 0.3), shade)
			if t == Game.WATER:
				base = Color(0.18, 0.38, 0.6).lerp(Color(0.2, 0.42, 0.64), shade)
			draw_rect(Rect2(c - Vector2(half, half), Vector2(TILE, TILE)), base)
			match t:
				Game.TREE:
					draw_rect(Rect2(c + Vector2(-2, 2), Vector2(4, 10)), Color(0.35, 0.22, 0.1))
					draw_circle(c + Vector2(0, -3), 12.0, Color(0.13, 0.36, 0.15))
					draw_circle(c + Vector2(-3, -6), 6.0, Color(0.18, 0.45, 0.2))
				Game.SAPLING:
					draw_circle(c, 5.0, Color(0.3, 0.6, 0.25))
				Game.BUSH, Game.BUSH_EMPTY:
					draw_circle(c, 11.0, Color(0.2, 0.42, 0.18))
					if t == Game.BUSH:
						for o in [Vector2(-5, -3), Vector2(4, -5), Vector2(2, 4), Vector2(-3, 5)]:
							draw_circle(c + o, 2.5, Color(0.8, 0.15, 0.2))
				Game.ROCK, Game.COPPER, Game.TIN, Game.IRON:
					var col: Color = DEPOSIT_COLORS[t]
					var pts := PackedVector2Array([c + Vector2(-13, 9), c + Vector2(-8, -8), c + Vector2(4, -12),
						c + Vector2(13, -2), c + Vector2(10, 10)])
					draw_colored_polygon(pts, col)
					draw_line(c + Vector2(-8, -8), c + Vector2(2, 2), col.darkened(0.25), 2.0)
					if t != Game.ROCK:
						draw_circle(c + Vector2(4, 2), 3.0, col.lightened(0.35))


func _draw_road(r: Dictionary) -> void:
	var pts := PackedVector2Array()
	for p in r.path:
		pts.append(node_pos(p))
	draw_polyline(pts, Color(0.42, 0.36, 0.22, 0.8), 8.0, true)
	draw_polyline(pts, Color(0.62, 0.52, 0.34), 4.0, true)


func _draw_flag(f: Dictionary) -> void:
	var c := node_pos(f.pos)
	draw_line(c + Vector2(0, 6), c + Vector2(0, -16), Color(0.25, 0.18, 0.1), 3.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(1, -16), c + Vector2(14, -12), c + Vector2(1, -7)]),
		Color(0.85, 0.2, 0.2))
	var i := 0
	for item in f.items:
		if i >= 8:
			break
		var off := Vector2(-14 + (i % 4) * 7, 8 + (i / 4) * 7)
		draw_rect(Rect2(c + off, Vector2(6, 6)), WARE_COLORS[item.ware])
		i += 1


func _draw_building(b: Dictionary) -> void:
	var c := node_pos(b.pos)
	var f := node_pos(b.flag)
	draw_line(c, f, Color(0.62, 0.52, 0.34), 3.0)
	var def: Dictionary = Game.DEFS[b.type]
	if b.type == "hq":
		var rect := Rect2(c - Vector2(24, 15), Vector2(48, 30))
		draw_rect(rect, Color(0.78, 0.64, 0.35))
		draw_line(rect.position + Vector2(0, 15), rect.end - Vector2(0, 15), Color(0.55, 0.42, 0.2), 2.0)
		draw_rect(rect, Color(0.35, 0.25, 0.12), false, 2.0)
		draw_texture_rect(icons[def.icon], Rect2(c - Vector2(11, 11), Vector2(22, 22)), false, Color(0.3, 0.2, 0.1))
		return
	if b.built:
		draw_circle(c, 15.0, Color(0.78, 0.64, 0.35))
		draw_arc(c, 15.0, 0, TAU, 24, Color(0.35, 0.25, 0.12), 2.0, true)
		draw_arc(c, 9.0, 0, TAU, 20, Color(0.6, 0.47, 0.24), 1.5, true)
		draw_texture_rect(icons[def.icon], Rect2(c - Vector2(10, 10), Vector2(20, 20)), false, Color(0.25, 0.16, 0.08))
	else:
		for k in 8:
			var a := TAU * k / 8.0
			draw_line(c + Vector2.from_angle(a) * 10.0, c + Vector2.from_angle(a) * 15.0, Color(0.45, 0.33, 0.18), 3.0)
		draw_texture_rect(icons["hammer"], Rect2(c - Vector2(9, 9), Vector2(18, 18)), false, Color(0.95, 0.9, 0.75))
		if b.need.is_empty():
			draw_rect(Rect2(c + Vector2(-15, 19), Vector2(30 * b.progress, 4)), Color(0.4, 0.9, 0.4))


func _draw_carrier(r: Dictionary) -> void:
	var c: Dictionary = r.carrier
	var path: Array = r.path
	var i := clampi(int(floor(c.pos)), 0, path.size() - 1)
	var j := mini(i + 1, path.size() - 1)
	var pos := node_pos(path[i]).lerp(node_pos(path[j]), c.pos - i)
	draw_circle(pos, 6.0, Color(0.95, 0.85, 0.65))
	draw_arc(pos, 6.0, 0, TAU, 16, Color(0.3, 0.2, 0.1), 1.5)
	if c.state == "carry" and c.item != null:
		draw_rect(Rect2(pos + Vector2(-4, -15), Vector2(8, 8)), WARE_COLORS[c.item.ware])
