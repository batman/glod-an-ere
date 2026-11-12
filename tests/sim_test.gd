extends SceneTree
## Headless tests for the changed areas: stone-age economy, era unlock, save/load.

var _failed := 0


func _check(name: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if detail == "" else "  (" + detail + ")"))
	if not ok:
		_failed += 1


func _build_connected(g: Game, type: String, near: Vector2i) -> Vector2i:
	# Like a player: try spots near the target and join any existing flag a path can reach.
	for r in range(2, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := near + Vector2i(dx, dy)
				if not g.can_place_building(type, p):
					continue
				g.place_building(type, p)
				for f in g.flags.keys():
					if f != p + Game.FLAG_OFFSET and g.build_road(p + Game.FLAG_OFFSET, f) == "":
						return p
				g.demolish_flag(p + Game.FLAG_OFFSET)
	print("  setup failed for " + type)
	return Vector2i(-1, -1)


func _init() -> void:
	var g := Game.new()
	g.new_game(7)

	# Economy: wood -> carving -> poles, berries -> food.
	var wc := _build_connected(g, "woodcutter", g.hq_pos + Vector2i(5, -3))
	var cv := _build_connected(g, "carver", g.hq_pos + Vector2i(-3, -3))
	var ga := _build_connected(g, "gatherer", g.hq_pos + Vector2i(-5, -4))
	for i in 4000:  # 400 s of game time
		g.step(0.1)
	var built: bool = g.buildings[wc].built and g.buildings[cv].built and g.buildings[ga].built
	_check("buildings get built", built)
	_check("poles are carved", g.produced.get("pole", 0) > 0 or g.era > 0, "poles %d" % g.produced.get("pole", 0))
	_check("food is gathered", g.produced.get("food", 0) > 0 or g.era > 0, "food %d" % g.produced.get("food", 0))

	# Era unlock: copper buildings are locked until the stone-age goal is met.
	var g2 := Game.new()
	g2.new_game(3)
	var locked := not g2.is_unlocked("copper_mine")
	g2.produced = {"pole": 15, "food": 10}
	g2.step(0.1)
	_check("copper age unlocks", locked and g2.era == 1 and g2.is_unlocked("smelter"))

	# Save and load keep the world intact.
	var path := "user://test_save.txt"
	g.save_game(path)
	var g3 := Game.new()
	var loaded := g3.load_game(path)
	_check("save and load", loaded and g3.roads.size() == g.roads.size() and g3.buildings.size() == g.buildings.size()
		and g3.hq().stock == g.hq().stock and g3.terrain == g.terrain)
	for i in 600:
		g3.step(0.1)
	_check("loaded game keeps running", g3.roads.size() == g.roads.size())
	DirAccess.remove_absolute(path)

	print("TEST " + ("PASSED" if _failed == 0 else "FAILED"))
	quit(0 if _failed == 0 else 1)
