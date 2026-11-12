class_name Game
extends RefCounted
## Pure simulation: map, flags, paths, carriers, buildings, ware flow and eras.

signal message(text: String)

const W := 64
const H := 48
const GRASS := 0
const WATER := 1
const TREE := 2
const SAPLING := 3
const ROCK := 4
const BUSH := 5
const BUSH_EMPTY := 6
const COPPER := 7
const TIN := 8
const IRON := 9
const DEPOSITS := [ROCK, COPPER, TIN, IRON]

const FLAG_OFFSET := Vector2i(1, 1)
const CARRIER_SPEED := 2.4
const BUILD_TIME := 8.0
const OUT_MAX := 4
const INPUT_STOCK := 3
const SAPLING_GROW := 45.0
const BUSH_REGROW := 40.0
const SAVE_PATH := "user://savegame.txt"

const WARES := ["log", "pole", "stone", "food", "copper_ore", "copper", "tin_ore", "bronze", "iron_ore", "iron", "tool"]
const WARE_NAMES := {
	"log": "Stämme", "pole": "Pfähle", "stone": "Steine", "food": "Nahrung",
	"copper_ore": "Kupfererz", "copper": "Kupfer", "tin_ore": "Zinnerz", "bronze": "Bronze",
	"iron_ore": "Eisenerz", "iron": "Eisen", "tool": "Werkzeug",
}

## Eras: name, name in the old tongue, wares that appear, goal (wares produced during the era).
const ERAS := [
	{"name": "Jungsteinzeit", "old": "Stainaldr", "wares": ["log", "pole", "stone", "food"],
		"goal": {"pole": 15, "food": 10}},
	{"name": "Kupferzeit", "old": "Kupraldr", "wares": ["copper_ore", "copper"], "goal": {"copper": 8}},
	{"name": "Bronzezeit", "old": "Bronsaldr", "wares": ["tin_ore", "bronze"], "goal": {"bronze": 8}},
	{"name": "Eisenzeit", "old": "Isarnaldr", "wares": ["iron_ore", "iron", "tool"], "goal": {"tool": 8}},
]

## kind: gather (take from nature), plant, craft (turn wares into wares).
const DEFS := {
	"hq": {"name": "Langhaus", "icon": "home", "era": 0, "kind": "hq", "cost": {}},
	"woodcutter": {"name": "Holzsammler", "icon": "axe", "era": 0, "kind": "gather", "cost": {"pole": 2},
		"time": 12.0, "res": TREE, "after": GRASS, "out": "log"},
	"forester": {"name": "Pflanzer", "icon": "plant-2", "era": 0, "kind": "plant", "cost": {"pole": 2}, "time": 14.0},
	"quarry": {"name": "Steinklopfer", "icon": "pick", "era": 0, "kind": "gather", "cost": {"pole": 2},
		"time": 14.0, "res": ROCK, "out": "stone"},
	"carver": {"name": "Schnitzplatz", "icon": "tools", "era": 0, "kind": "craft", "cost": {"pole": 2, "stone": 1},
		"time": 9.0, "in": {"log": 1}, "out": "pole"},
	"gatherer": {"name": "Sammlerin", "icon": "basket", "era": 0, "kind": "gather", "cost": {"pole": 2},
		"time": 10.0, "res": BUSH, "after": BUSH_EMPTY, "out": "food"},
	"hunter": {"name": "Jäger", "icon": "bow", "era": 0, "kind": "gather", "cost": {"pole": 2},
		"time": 16.0, "res": TREE, "keep": true, "out": "food"},
	"copper_mine": {"name": "Kupfergrube", "icon": "shovel", "era": 1, "kind": "gather", "cost": {"pole": 3, "stone": 2},
		"time": 14.0, "res": COPPER, "in": {"food": 1}, "out": "copper_ore"},
	"smelter": {"name": "Schmelzofen", "icon": "flame", "era": 1, "kind": "craft", "cost": {"pole": 3, "stone": 3},
		"time": 12.0, "in": {"copper_ore": 1, "log": 1}, "out": "copper"},
	"tin_mine": {"name": "Zinngrube", "icon": "shovel", "era": 2, "kind": "gather", "cost": {"pole": 3, "stone": 2},
		"time": 14.0, "res": TIN, "in": {"food": 1}, "out": "tin_ore"},
	"caster": {"name": "Bronzegießer", "icon": "bucket", "era": 2, "kind": "craft",
		"cost": {"pole": 3, "stone": 3, "copper": 2}, "time": 12.0, "in": {"copper": 1, "tin_ore": 1}, "out": "bronze"},
	"iron_mine": {"name": "Eisengrube", "icon": "shovel", "era": 3, "kind": "gather",
		"cost": {"pole": 3, "stone": 2, "bronze": 1}, "time": 14.0, "res": IRON, "in": {"food": 1}, "out": "iron_ore"},
	"bloomery": {"name": "Rennofen", "icon": "campfire", "era": 3, "kind": "craft",
		"cost": {"pole": 3, "stone": 3, "bronze": 2}, "time": 12.0, "in": {"iron_ore": 1, "log": 1}, "out": "iron"},
	"smith": {"name": "Schmied", "icon": "hammer", "era": 3, "kind": "craft",
		"cost": {"pole": 3, "stone": 2, "iron": 2}, "time": 12.0, "in": {"iron": 1, "log": 1}, "out": "tool"},
}
const BUILD_ORDER := ["woodcutter", "forester", "quarry", "carver", "gatherer", "hunter", "copper_mine", "smelter",
	"tin_mine", "caster", "iron_mine", "bloomery", "smith"]

var terrain := PackedInt32Array()
var amount := {}        # deposit node -> units left
var regrow := {}        # sapling / empty bush node -> seconds grown
var flags := {}         # Vector2i -> {pos, items: Array, roads: Array}
var roads: Array = []   # {a, b, path, carrier}
var road_at := {}       # interior path node -> road
var buildings := {}     # Vector2i -> building dict
var hq_pos := Vector2i()
var era := 0
var produced := {}      # ware -> amount produced in the current era
var won := false

var _hop_cache := {}
var _dispatch_timer := 0.0
var _item_id := 0
var _rng := RandomNumberGenerator.new()


# ---------- setup ----------

func new_game(seed_value: int = 7) -> void:
	_rng.seed = seed_value
	terrain.resize(W * H)
	terrain.fill(GRASS)
	amount.clear(); regrow.clear(); flags.clear(); roads.clear()
	road_at.clear(); buildings.clear(); _hop_cache.clear(); produced.clear()
	era = 0
	won = false
	hq_pos = Vector2i(W / 2 - 4, H / 2)

	var water_noise := FastNoiseLite.new()
	water_noise.seed = seed_value
	water_noise.frequency = 0.045
	var forest_noise := FastNoiseLite.new()
	forest_noise.seed = seed_value + 11
	forest_noise.frequency = 0.08

	for y in H:
		for x in W:
			var p := Vector2i(x, y)
			if _dist(p, hq_pos) < 4.5:
				continue
			var n := water_noise.get_noise_2d(x, y)
			var f := forest_noise.get_noise_2d(x, y)
			if n > 0.38:
				terrain[_i(p)] = WATER
			elif f > 0.2 and _rng.randf() < 0.75:
				terrain[_i(p)] = TREE
			elif f < -0.45 and _rng.randf() < 0.45:
				_set_deposit(p, ROCK)
			elif f < -0.2 and _rng.randf() < 0.06:
				terrain[_i(p)] = BUSH
			elif _rng.randf() < 0.03:
				terrain[_i(p)] = TREE

	# Guarantee the basics near the start, rarer ores further away.
	_scatter(hq_pos + Vector2i(7, -5), 3, 16, TREE)
	_scatter(hq_pos + Vector2i(-6, 5), 2, 6, ROCK)
	_scatter(hq_pos + Vector2i(-6, -5), 2, 7, BUSH)
	_scatter(hq_pos + Vector2i(10, 7), 2, 5, COPPER)
	_scatter(hq_pos + Vector2i(-13, 2), 2, 5, TIN)
	_scatter(hq_pos + Vector2i(3, 15), 2, 6, IRON)

	var hq := _new_building("hq", hq_pos, true)
	hq.stock = {"log": 6, "pole": 24, "stone": 12, "food": 6}
	buildings[hq_pos] = hq
	_add_flag(hq_pos + FLAG_OFFSET)


func _scatter(center: Vector2i, radius: int, count: int, kind: int) -> void:
	for n in count * 6:
		if count <= 0:
			return
		var p := center + Vector2i(_rng.randi_range(-radius, radius), _rng.randi_range(-radius, radius))
		if in_bounds(p) and (terrain[_i(p)] == GRASS or terrain[_i(p)] == TREE) and _dist(p, hq_pos) > 3.5:
			if kind in DEPOSITS:
				_set_deposit(p, kind)
			else:
				terrain[_i(p)] = kind
			count -= 1


func _set_deposit(p: Vector2i, kind: int) -> void:
	terrain[_i(p)] = kind
	amount[p] = 6 if kind == ROCK else 8


# ---------- queries ----------

func _i(p: Vector2i) -> int:
	return p.y * W + p.x


func _dist(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a).distance_to(Vector2(b))


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < W and p.y < H


func terrain_at(p: Vector2i) -> int:
	return terrain[_i(p)]


func is_free(p: Vector2i) -> bool:
	return in_bounds(p) and terrain[_i(p)] == GRASS and not buildings.has(p) \
		and not flags.has(p) and not road_at.has(p)


func can_place_flag(p: Vector2i) -> bool:
	if not in_bounds(p) or flags.has(p) or buildings.has(p) or terrain[_i(p)] != GRASS:
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if flags.has(p + Vector2i(dx, dy)):
				return false
	return true


func is_unlocked(type: String) -> bool:
	return DEFS[type].era <= era


func can_place_building(type: String, p: Vector2i) -> bool:
	if not DEFS.has(type) or not is_unlocked(type) or not is_free(p):
		return false
	var f := p + FLAG_OFFSET
	if not in_bounds(f):
		return false
	return flags.has(f) or can_place_flag(f)


func building_at_flag(f: Vector2i) -> Variant:
	return buildings.get(f - FLAG_OFFSET, null)


func hq() -> Dictionary:
	return buildings[hq_pos]


func unlocked_wares() -> Array:
	var list := []
	for i in era + 1:
		list.append_array(ERAS[i].wares)
	return list


func demand(b: Dictionary) -> Dictionary:
	var d := {}
	if b.type == "hq":
		return d
	if not b.built:
		for w in b.need:
			var missing: int = b.need[w] - b.incoming.get(w, 0)
			if missing > 0:
				d[w] = missing
		return d
	var inputs: Dictionary = DEFS[b.type].get("in", {})
	for w in inputs:
		var missing: int = INPUT_STOCK - b.stock.get(w, 0) - b.incoming.get(w, 0)
		if missing > 0:
			d[w] = missing
	return d


# ---------- building actions ----------

func place_flag(p: Vector2i) -> bool:
	if flags.has(p):
		return true
	if not can_place_flag(p):
		return false
	if road_at.has(p):
		_split_road(road_at[p], p)
	else:
		_add_flag(p)
	_graph_changed()
	return true


func place_building(type: String, p: Vector2i) -> bool:
	if not can_place_building(type, p):
		return false
	var f := p + FLAG_OFFSET
	if not flags.has(f):
		place_flag(f)
	buildings[p] = _new_building(type, p, false)
	return true


func build_road(from: Vector2i, to: Vector2i) -> String:
	if not flags.has(from):
		return "Starte den Pfad an einer Flagge."
	if from == to:
		return "Start und Ziel sind gleich."
	if not flags.has(to) and not can_place_flag(to):
		return "Hier kann keine Flagge stehen."
	var path := find_path(from, to)
	if path.size() < 2:
		return "Dorthin gibt es keinen Weg."
	if not flags.has(to):
		place_flag(to)
	_add_road(path)
	_graph_changed()
	return ""


func find_path(from: Vector2i, to: Vector2i) -> Array:
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, W, H)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in H:
		for x in W:
			var p := Vector2i(x, y)
			if not is_free(p):
				astar.set_point_solid(p, true)
	astar.set_point_solid(from, false)
	# A path may end on an existing path node; it becomes a flag there.
	astar.set_point_solid(to, false)
	var result := []
	for p in astar.get_id_path(from, to):
		result.append(p)
	return result


func demolish_building(p: Vector2i) -> void:
	if p == hq_pos or not buildings.has(p):
		return
	buildings.erase(p)


func demolish_flag(f: Vector2i) -> void:
	if not flags.has(f) or f == hq_pos + FLAG_OFFSET:
		return
	var b = building_at_flag(f)
	if b != null:
		demolish_building(b.pos)
	var attached: Array = flags[f].roads.duplicate()
	flags.erase(f)
	for r in attached:
		_remove_road(r)
	_graph_changed()


func demolish_road(r: Dictionary) -> void:
	_remove_road(r)
	_graph_changed()


func _add_flag(p: Vector2i) -> void:
	flags[p] = {"pos": p, "items": [], "roads": []}


func _add_road(path: Array, carrier = null) -> void:
	if carrier == null:
		carrier = {"pos": (path.size() - 1) / 2.0, "state": "idle", "item": null, "target": 0.0}
	var r := {"a": path[0], "b": path[path.size() - 1], "path": path, "carrier": carrier}
	roads.append(r)
	for i in range(1, path.size() - 1):
		road_at[path[i]] = r
	flags[r.a].roads.append(r)
	flags[r.b].roads.append(r)


func _remove_road(r: Dictionary) -> void:
	if not roads.has(r):
		return
	roads.erase(r)
	for i in range(1, r.path.size() - 1):
		road_at.erase(r.path[i])
	for end in [r.a, r.b]:
		if flags.has(end):
			flags[end].roads.erase(r)
	var c: Dictionary = r.carrier
	if c.item != null and c.state == "carry":
		var near: Vector2i = r.a if c.pos < (r.path.size() - 1) / 2.0 else r.b
		if not flags.has(near):
			near = r.b if near == r.a else r.a
		if flags.has(near):
			_drop_item(near, c.item)


func _split_road(r: Dictionary, p: Vector2i) -> void:
	var path: Array = r.path
	var i := path.find(p)
	_remove_road(r)
	_add_flag(p)
	_add_road(path.slice(0, i + 1))
	_add_road(path.slice(i))


func _graph_changed() -> void:
	_hop_cache.clear()
	for f in flags.values():
		for item in f.items:
			item.reserved = false
	for r in roads:
		if r.carrier.state == "to_pick":
			r.carrier.state = "idle"
			r.carrier.item = null


func _new_building(type: String, p: Vector2i, built: bool) -> Dictionary:
	return {
		"type": type, "pos": p, "flag": p + FLAG_OFFSET, "built": built,
		"progress": 0.0, "need": DEFS[type].cost.duplicate(), "incoming": {},
		"stock": {}, "out": [], "timer": 0.0, "status": "",
	}


# ---------- routing ----------

func next_hop(from: Vector2i, dest: Vector2i) -> Variant:
	if from == dest:
		return from
	if not _hop_cache.has(dest):
		_hop_cache[dest] = _dijkstra(dest)
	return _hop_cache[dest].get(from, null)


func reachable(a: Vector2i, b: Vector2i) -> bool:
	return next_hop(a, b) != null


func _dijkstra(dest: Vector2i) -> Dictionary:
	var dist := {dest: 0.0}
	var nxt := {}
	var open := [dest]
	var done := {}
	while not open.is_empty():
		var best := 0
		for k in open.size():
			if dist[open[k]] < dist[open[best]]:
				best = k
		var u: Vector2i = open[best]
		open.remove_at(best)
		done[u] = true
		if not flags.has(u):
			continue
		for r in flags[u].roads:
			var v: Vector2i = r.b if r.a == u else r.a
			if done.has(v):
				continue
			var nd: float = dist[u] + r.path.size() - 1
			if not dist.has(v) or nd < dist[v]:
				dist[v] = nd
				nxt[v] = u
				if not open.has(v):
					open.append(v)
	return nxt


# ---------- simulation ----------

func step(dt: float) -> void:
	for r in roads.duplicate():
		_update_carrier(r, dt)
	for b in buildings.values():
		_update_building(b, dt)
	for p in regrow.keys():
		regrow[p] += dt
		var t := terrain[_i(p)]
		if t == SAPLING and regrow[p] >= SAPLING_GROW:
			terrain[_i(p)] = TREE
			regrow.erase(p)
		elif t == BUSH_EMPTY and regrow[p] >= BUSH_REGROW:
			terrain[_i(p)] = BUSH
			regrow.erase(p)
		elif t != SAPLING and t != BUSH_EMPTY:
			regrow.erase(p)
	_dispatch_timer += dt
	if _dispatch_timer >= 0.4:
		_dispatch_timer = 0.0
		_dispatch()
	_check_era()


func goal_progress() -> Dictionary:
	var g := {}
	for w in ERAS[era].goal:
		g[w] = mini(produced.get(w, 0), ERAS[era].goal[w])
	return g


func _check_era() -> void:
	if won:
		return
	var goal: Dictionary = ERAS[era].goal
	for w in goal:
		if produced.get(w, 0) < goal[w]:
			return
	if era == ERAS.size() - 1:
		won = true
		message.emit("Gewonnen! Dein Volk hat das Eisen gemeistert.")
		return
	era += 1
	produced.clear()
	message.emit("Eine neue Zeit beginnt: %s (%s). Neue Gebäude sind verfügbar." % [ERAS[era].name, ERAS[era].old])


func _update_carrier(r: Dictionary, dt: float) -> void:
	var c: Dictionary = r.carrier
	var last := float(r.path.size() - 1)
	match c.state:
		"idle":
			if not _find_job(r):
				c.pos = move_toward(c.pos, last / 2.0, CARRIER_SPEED * dt)
		"to_pick":
			c.pos = move_toward(c.pos, c.target, CARRIER_SPEED * dt)
			if is_equal_approx(c.pos, c.target):
				var end: Vector2i = r.a if c.target == 0.0 else r.b
				var items: Array = flags[end].items
				var idx := -1
				for k in items.size():
					if items[k].id == c.item.id:
						idx = k
				if idx < 0:
					c.state = "idle"
					c.item = null
				else:
					items.remove_at(idx)
					c.state = "carry"
					c.target = last if c.target == 0.0 else 0.0
		"carry":
			c.pos = move_toward(c.pos, c.target, CARRIER_SPEED * dt)
			if is_equal_approx(c.pos, c.target):
				var end: Vector2i = r.a if c.target == 0.0 else r.b
				var item = c.item
				c.item = null
				c.state = "idle"
				_drop_item(end, item)


func _find_job(r: Dictionary) -> bool:
	var c: Dictionary = r.carrier
	var ends := [r.a, r.b] if c.pos < (r.path.size() - 1) / 2.0 else [r.b, r.a]
	for end in ends:
		var other: Vector2i = r.b if end == r.a else r.a
		for item in flags[end].items:
			if item.reserved or not buildings.has(item.dest):
				continue
			if next_hop(end, buildings[item.dest].flag) == other:
				item.reserved = true
				c.item = item
				c.state = "to_pick"
				c.target = 0.0 if end == r.a else float(r.path.size() - 1)
				return true
	return false


func _drop_item(f: Vector2i, item: Dictionary) -> void:
	if not buildings.has(item.dest):
		item.dest = hq_pos
	var b: Dictionary = buildings[item.dest]
	if b.flag == f:
		_deliver(b, item.ware)
		return
	item.reserved = false
	flags[f].items.append(item)


func _deliver(b: Dictionary, ware: String) -> void:
	b.incoming[ware] = maxi(0, b.incoming.get(ware, 0) - 1)
	if b.type == "hq" or b.built:
		b.stock[ware] = b.stock.get(ware, 0) + 1
	else:
		b.need[ware] = b.need.get(ware, 0) - 1
		if b.need[ware] <= 0:
			b.need.erase(ware)


func _spawn_item(f: Vector2i, ware: String, dest: Vector2i) -> void:
	_item_id += 1
	_drop_item(f, {"id": _item_id, "ware": ware, "dest": dest, "reserved": false})


func _has_inputs(b: Dictionary, inputs: Dictionary) -> bool:
	for w in inputs:
		if b.stock.get(w, 0) < inputs[w]:
			return false
	return true


func _use_inputs(b: Dictionary, inputs: Dictionary) -> void:
	for w in inputs:
		b.stock[w] -= inputs[w]


func _produce(b: Dictionary, ware: String) -> void:
	b.out.append(ware)
	produced[ware] = produced.get(ware, 0) + 1
	b.timer = 0.0


func _update_building(b: Dictionary, dt: float) -> void:
	if b.type == "hq":
		return
	var def: Dictionary = DEFS[b.type]
	if not b.built:
		if b.need.is_empty():
			b.status = "Wird gebaut"
			b.progress += dt / BUILD_TIME
			if b.progress >= 1.0:
				b.built = true
				b.progress = 0.0
				message.emit("%s ist fertig." % def.name)
		else:
			b.status = "Wartet auf Baumaterial"
		return
	if b.out.size() >= OUT_MAX:
		b.status = "Waren stapeln sich. Fehlt ein Pfad?"
		return
	var inputs: Dictionary = def.get("in", {})
	if not _has_inputs(b, inputs):
		b.status = "Wartet auf " + ", ".join(inputs.keys().map(func(w): return WARE_NAMES[w]))
		return
	b.status = "Arbeitet"
	b.timer = minf(b.timer + dt, def.time)
	if b.timer < def.time:
		return
	match def.kind:
		"gather":
			var spot = _nearest(b.pos, def.res, 6)
			if spot == null:
				b.status = "Nichts mehr in der Nähe zu holen"
				return
			_use_inputs(b, inputs)
			if def.res in DEPOSITS:
				amount[spot] -= 1
				if amount[spot] <= 0:
					amount.erase(spot)
					terrain[_i(spot)] = GRASS
			elif not def.get("keep", false):
				terrain[_i(spot)] = def.after
				if def.after == BUSH_EMPTY:
					regrow[spot] = 0.0
			_produce(b, def.out)
		"plant":
			b.timer = 0.0
			for n in 25:
				var p: Vector2i = b.pos + Vector2i(_rng.randi_range(-5, 5), _rng.randi_range(-5, 5))
				if is_free(p) and p != b.pos:
					terrain[_i(p)] = SAPLING
					regrow[p] = 0.0
					break
		"craft":
			_use_inputs(b, inputs)
			_produce(b, def.out)


func _nearest(center: Vector2i, kind: int, radius: int) -> Variant:
	var best = null
	var best_d := INF
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var p := center + Vector2i(dx, dy)
			if in_bounds(p) and terrain[_i(p)] == kind:
				var d := _dist(center, p)
				if d <= radius and d < best_d:
					best_d = d
					best = p
	return best


func _dispatch() -> void:
	# Items whose target vanished go back to the long house.
	for f in flags.values():
		for item in f.items.duplicate():
			if not buildings.has(item.dest):
				f.items.erase(item)
				_drop_item(f.pos, item)

	# Producers hand their goods to whoever needs them, else to storage.
	var main := hq()
	for b in buildings.values():
		if b.type == "hq" or not b.built or b.out.is_empty():
			continue
		var ware: String = b.out[0]
		var dest = _find_consumer(ware, b.flag)
		if dest == null and reachable(b.flag, main.flag):
			dest = hq_pos
		if dest != null:
			b.out.pop_front()
			if dest != hq_pos:
				buildings[dest].incoming[ware] = buildings[dest].incoming.get(ware, 0) + 1
			_spawn_item(b.flag, ware, dest)

	# Storage supplies construction sites and workshops.
	for b in buildings.values():
		var d := demand(b)
		for ware in d:
			if main.stock.get(ware, 0) > 0 and reachable(main.flag, b.flag):
				main.stock[ware] -= 1
				b.incoming[ware] = b.incoming.get(ware, 0) + 1
				_spawn_item(main.flag, ware, b.pos)


func _find_consumer(ware: String, from: Vector2i) -> Variant:
	for b in buildings.values():
		if b.type != "hq" and demand(b).has(ware) and reachable(from, b.flag):
			return b.pos
	return null


# ---------- save / load ----------

func to_data() -> Dictionary:
	var flag_list := []
	for f in flags.values():
		flag_list.append({"pos": f.pos, "items": f.items})
	var road_list := []
	for r in roads:
		road_list.append({"path": r.path, "carrier": r.carrier})
	return {
		"version": 1, "terrain": terrain, "amount": amount, "regrow": regrow, "flags": flag_list,
		"roads": road_list, "buildings": buildings, "hq_pos": hq_pos, "era": era, "produced": produced,
		"won": won, "item_id": _item_id, "rng": _rng.state,
	}


func from_data(d: Dictionary) -> void:
	terrain = d.terrain
	amount = d.amount
	regrow = d.regrow
	buildings = d.buildings
	hq_pos = d.hq_pos
	era = d.era
	produced = d.produced
	won = d.won
	_item_id = d.item_id
	_rng.state = d.rng
	flags.clear(); roads.clear(); road_at.clear()
	for f in d.flags:
		_add_flag(f.pos)
		flags[f.pos].items = f.items
	for r in d.roads:
		_add_road(r.path, r.carrier)
	_graph_changed()


func save_game(path := SAVE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(var_to_str(to_data()))
	return true


func load_game(path := SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = str_to_var(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or data.get("version", 0) != 1:
		return false
	from_data(data)
	return true
