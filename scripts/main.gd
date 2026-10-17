extends Node2D

const ROAD := 150.0
const BLOCK := 440.0
const WORLD := 2800.0
var player := Vector2(220, 30)
var car := Vector2(270, 30)
var angle := 0.0
var speed := 0.0
var driving := false
var camera: Camera2D
var hud: Label
var _e_held := false
var blockers: Array[Rect2] = []
var traffic: Array[Dictionary] = []
var light_time := 0.0
var health := 100.0
var vehicle_health := 100.0
var vehicle_kind := 0
var parked: Array[Dictionary] = []
var pedestrians: Array[Dictionary] = []
const VEHICLE_NAMES := ["Sedan", "Van", "Pickup", "Truck", "Motorcycle", "Quad"]
const VEHICLE_COLORS := ["e8b746", "6da2bd", "c46e58", "8a9b72", "d85c59", "d8b86d"]
const VEHICLE_SIZES := [Vector2(42, 80), Vector2(49, 95), Vector2(48, 90), Vector2(57, 130), Vector2(21, 62), Vector2(34, 57)]
var health_bar: ProgressBar
var vehicle_bar: ProgressBar
var status_label: Label
var health_tiles: HBoxContainer
var last_hit := -10.0
var game_time := 0.0
var car_invulnerability := 0.0


func _setup_world() -> void:
    for x in range(-3, 3):
        for y in range(-3, 3):
            var p := Vector2(x * BLOCK + 90, y * BLOCK + 90)
            if x >= 1 and y >= 1:
                blockers.append(Rect2(p + Vector2(12, 12), Vector2(262, 132)))
                for i in range(4):
                    blockers.append(Rect2(p + Vector2(18 + i * 65, 185), Vector2(52, 86)))
            elif x <= -1 and y <= -1:
                for a in range(2):
                    for b in range(2):
                        blockers.append(Rect2(p + Vector2(26 + a * 145, 25 + b * 145), Vector2(87, 85)))
            elif (x == -1 and y == 1) or (x == 0 and y == 1) or (x == -2 and y == 0):
                pass
            elif (x + y) % 3 == 0:
                for i in range(3):
                    blockers.append(Rect2(p + Vector2(22 + i * 86, 42), Vector2(28, 53)))
            else:
                blockers.append(Rect2(p + Vector2(14, 14), Vector2(125, 260)))
                blockers.append(Rect2(p + Vector2(155, 14), Vector2(120, 123)))
                blockers.append(Rect2(p + Vector2(155, 152), Vector2(120, 122)))
    # Spawn traffic in separated lanes and away from intersections.
    for n in range(-2, 3):
        var road := float(n) * BLOCK
        var offset := float(n + 2) * 440.0
        traffic.append({"kind": (n + 3) % 6, "pos": Vector2(-1100.0 + offset, road + 30.0), "dir": Vector2.RIGHT})
        traffic.append({"kind": (n + 4) % 6, "pos": Vector2(1100.0 - offset, road - 30.0), "dir": Vector2.LEFT})
        traffic.append({"kind": (n + 5) % 6, "pos": Vector2(road - 30.0, -1150.0 + offset), "dir": Vector2.DOWN})
        traffic.append({"kind": (n + 2) % 6, "pos": Vector2(road + 30.0, 1150.0 - offset), "dir": Vector2.UP})
    # Drop conflicting initial positions rather than spawning overlapping cars.
    var clean: Array[Dictionary] = []
    for item in traffic:
        var clear := item["pos"].distance_to(car) > _vehicle_radius(int(item["kind"])) + _vehicle_radius(vehicle_kind) + 12.0
        for other in clean:
            if item["pos"].distance_to(other["pos"]) < _vehicle_radius(int(item["kind"])) + _vehicle_radius(int(other["kind"])) + 12.0:
                clear = false
                break
        if clear:
            clean.append(item)
    traffic = clean

func _setup_people_and_vehicles() -> void:
    parked.clear()
    # Park cars along quieter streets, not in the center of a junction.
    for i in range(5):
        var x := float(i - 2) * BLOCK + 130.0
        var p := Vector2(x, -1320.0)
        if not _static_blocked(p, 42.0) and p.distance_to(car) > 135.0:
            parked.append({"pos": p, "kind": i + 1, "health": 100.0})
    for i in range(24):
        var col := i % 6 - 3
        var row := int(i / 6) - 2
        var origin := Vector2(float(col) * BLOCK + 102.0, float(row) * BLOCK + 120.0)
        pedestrians.append({"pos": origin, "origin": origin, "phase": float(i) * 1.7, "axis": i % 2})

func _vehicle_radius(kind: int) -> float:
    var size: Vector2 = VEHICLE_SIZES[kind]
    return sqrt(size.x * size.x + size.y * size.y) * 0.5 + 7.0

func _static_blocked(pos: Vector2, radius: float) -> bool:
    if abs(pos.x) + radius > WORLD * 0.5 or abs(pos.y) + radius > WORLD * 0.5:
        return true
    for rect in blockers:
        var nearest := Vector2(clampf(pos.x, rect.position.x, rect.end.x), clampf(pos.y, rect.position.y, rect.end.y))
        if nearest.distance_squared_to(pos) < radius * radius:
            return true
    return false

func _vehicle_clear(pos: Vector2, kind: int, ignore_traffic: int = -1) -> bool:
    var radius := _vehicle_radius(kind)
    if _static_blocked(pos, radius):
        return false
    for i in range(traffic.size()):
        if i == ignore_traffic:
            continue
        var other: Dictionary = traffic[i]
        if pos.distance_to(other["pos"]) < radius + _vehicle_radius(int(other["kind"])):
            return false
    for other in parked:
        if pos.distance_to(other["pos"]) < radius + _vehicle_radius(int(other["kind"])):
            return false
    return true

func _make_bar(ui: CanvasLayer, at: Vector2, tint: Color) -> ProgressBar:
    var bar := ProgressBar.new()
    bar.position = at
    bar.size = Vector2(180, 20)
    bar.max_value = 100.0
    bar.value = 100.0
    bar.show_percentage = false
    var fill := StyleBoxFlat.new()
    fill.bg_color = tint
    bar.add_theme_stylebox_override("fill", fill)
    ui.add_child(bar)
    return bar

func _update_pedestrians(delta: float) -> void:
    for person in pedestrians:
        var p: Vector2 = person["pos"]
        var origin: Vector2 = person["origin"]
        var phase: float = person["phase"]
        var axis: int = person["axis"]
        var desired := origin + (Vector2(0, sin(light_time * 0.7 + phase) * 72.0) if axis == 0 else Vector2(sin(light_time * 0.7 + phase) * 72.0, 0))
        var away := p - car
        if away.length() < 85.0:
            desired = p + away.normalized() * 70.0
        var next := p.move_toward(desired, 55.0 * delta)
        if not _blocked(next, 9.0, false):
            person["pos"] = next

func _blocked(pos: Vector2, radius: float, check_traffic: bool = true) -> bool:
    if _static_blocked(pos, radius):
        return true
    if check_traffic:
        for item in parked:
            if pos.distance_to(item["pos"]) < radius + _vehicle_radius(int(item["kind"])):
                return true
        for item in traffic:
            if pos.distance_to(item["pos"]) < radius + _vehicle_radius(int(item["kind"])):
                return true
    return false

func _move_safely(pos: Vector2, motion: Vector2, radius: float) -> Vector2:
    var result := pos
    var count := maxi(1, int(ceil(motion.length() / 8.0)))
    var step := motion / float(count)
    for i in range(count):
        if not _blocked(result + Vector2(step.x, 0), radius):
            result.x += step.x
        if not _blocked(result + Vector2(0, step.y), radius):
            result.y += step.y
    return result

func _traffic_tick(delta: float) -> void:
    light_time = fmod(light_time + delta, 14.0)
    var previous: Array[Vector2] = []
    for item in traffic:
        previous.append(item["pos"])
    var planned: Array[Vector2] = []
    for i in range(traffic.size()):
        var item: Dictionary = traffic[i]
        var pos: Vector2 = previous[i]
        var direction: Vector2 = item["dir"]
        var radius := _vehicle_radius(int(item["kind"]))
        var distance_to_stop := 75.0 + radius
        var axis := pos.x if abs(direction.x) > 0.5 else pos.y
        var sign_axis := direction.x if abs(direction.x) > 0.5 else direction.y
        var red := light_time >= 7.0 if abs(direction.x) > 0.5 else light_time < 7.0
        var movement := direction * 100.0 * delta
        var blocked := false
        if red:
            for n in range(-3, 4):
                var dist := (float(n) * BLOCK - axis) * sign_axis
                if dist >= distance_to_stop and dist < distance_to_stop + movement.length() + 2.0:
                    blocked = true
                    break
        var next := pos + movement
        if next.distance_to(car) < radius + _vehicle_radius(vehicle_kind) + 12.0:
            blocked = true
        for other in parked:
            if next.distance_to(other["pos"]) < radius + _vehicle_radius(int(other["kind"])) + 8.0:
                blocked = true
                break
        for j in range(traffic.size()):
            if i == j:
                continue
            var other_pos: Vector2 = previous[j]
            var other_kind := int(traffic[j]["kind"])
            var clearance := radius + _vehicle_radius(other_kind) + 10.0
            # Both old and intended positions matter at crossings.
            if next.distance_to(other_pos) < clearance or next.distance_to(other_pos + traffic[j]["dir"] * 100.0 * delta) < clearance:
                blocked = true
                break
        for other_pos in planned:
            if next.distance_to(other_pos) < radius + 85.0:
                blocked = true
                break
        if blocked:
            next = pos
        var wrapped := next
        if next.x > 1390.0:
            wrapped.x = -1370.0
        elif next.x < -1390.0:
            wrapped.x = 1370.0
        if next.y > 1390.0:
            wrapped.y = -1370.0
        elif next.y < -1390.0:
            wrapped.y = 1370.0
        if wrapped != next:
            var can_wrap := wrapped.distance_to(car) > radius + _vehicle_radius(vehicle_kind)
            for j in range(traffic.size()):
                if i != j and wrapped.distance_to(previous[j]) < radius + _vehicle_radius(int(traffic[j]["kind"])) + 10.0:
                    can_wrap = false
            if can_wrap:
                next = wrapped
            else:
                next = pos
        planned.append(next)
    for i in range(traffic.size()):
        traffic[i]["pos"] = planned[i]

func _ready() -> void:
    camera = Camera2D.new()
    camera.position_smoothing_enabled = true
    camera.position_smoothing_speed = 6.0
    add_child(camera)
    camera.make_current()
    var ui := CanvasLayer.new()
    add_child(ui)
    hud = Label.new()
    hud.position = Vector2(18, 18)
    hud.add_theme_font_size_override("font_size", 18)
    hud.text = "FIRST DRIVE 0.5  |  WASD: Move / Drive   E: Enter / Exit   Space: Brake"
    ui.add_child(hud)
    _setup_world()
    _setup_people_and_vehicles()
    camera.zoom = Vector2(1.55, 1.55)
    # HUD anchors to the upper-right corner, not the game world.
    health_tiles = HBoxContainer.new()
    health_tiles.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    health_tiles.anchor_left = 1.0
    health_tiles.anchor_right = 1.0
    health_tiles.offset_left = -268.0
    health_tiles.offset_right = -18.0
    health_tiles.offset_top = 18.0
    health_tiles.offset_bottom = 40.0
    health_tiles.add_theme_constant_override("separation", 4)
    ui.add_child(health_tiles)
    for i in range(10):
        var tile := ColorRect.new()
        tile.custom_minimum_size = Vector2(20, 20)
        tile.color = Color("43c978")
        health_tiles.add_child(tile)
    vehicle_bar = _make_bar(ui, Vector2(18, 56), Color("e7a54e"))
    status_label = Label.new()
    status_label.position = Vector2(18, 88)
    status_label.add_theme_font_size_override("font_size", 16)
    ui.add_child(status_label)
    queue_redraw()

func _process(delta: float) -> void:
    game_time += delta
    car_invulnerability = maxf(0.0, car_invulnerability - delta)
    _traffic_tick(delta)
    _update_pedestrians(delta)
    var move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    if driving:
        speed = move_toward(speed, -move.y * 380.0, 350.0 * delta)
        if Input.is_key_pressed(KEY_SPACE):
            speed = move_toward(speed, 0.0, 900.0 * delta)
        if abs(speed) > 5.0:
            angle += move.x * 2.3 * delta * sign(speed)
        var motion := Vector2.UP.rotated(angle) * speed * delta
        var next := car
        var steps := maxi(1, int(ceil(motion.length() / 5.0)))
        var step := motion / float(steps)
        for i in range(steps):
            var candidate := next + step
            if not _static_blocked(candidate, _vehicle_radius(vehicle_kind)) and _vehicle_clear(candidate, vehicle_kind):
                next = candidate
            else:
                break
        if next.distance_to(car + motion) > 1.0:
            if abs(speed) > 65.0 and car_invulnerability <= 0.0:
                vehicle_health = maxf(0.0, vehicle_health - abs(speed) * 0.035)
                car_invulnerability = 0.35
            speed = 0.0
        car = next
        player = car
    else:
        player = _move_safely(player, move * 230.0 * delta, 11.0)
    if Input.is_key_pressed(KEY_E) and not _e_held:
        if driving:
            var exit_pos := car + Vector2.RIGHT.rotated(angle) * (_vehicle_radius(vehicle_kind) + 25.0)
            if not _blocked(exit_pos, 11.0):
                driving = false
                player = exit_pos
                speed = 0.0
        else:
            # Find the closest car, including moving traffic; the original car
            # must not take priority just because it is already selected.
            var nearest := 105.0
            var source := ""
            var index := -1
            var d := player.distance_to(car)
            if d < nearest:
                nearest = d
                source = "own"
            for i in range(parked.size()):
                d = player.distance_to(parked[i]["pos"])
                if d < nearest:
                    nearest = d
                    source = "parked"
                    index = i
            for i in range(traffic.size()):
                d = player.distance_to(traffic[i]["pos"])
                if d < nearest:
                    nearest = d
                    source = "traffic"
                    index = i
            if source != "":
                if source == "traffic":
                    var stolen: Dictionary = traffic[index]
                    var stolen_pos: Vector2 = stolen["pos"]
                    var direction: Vector2 = stolen["dir"]
                    var stolen_kind := int(stolen["kind"])
                    traffic.remove_at(index)
                    parked.append({"pos": car, "kind": vehicle_kind, "health": vehicle_health})
                    car = stolen_pos
                    vehicle_kind = stolen_kind
                    vehicle_health = 100.0
                    angle = direction.angle() + PI * 0.5
                    # Driver appears next to the vehicle and becomes a pedestrian.
                    var driver_pos := stolen_pos + Vector2.RIGHT.rotated(angle) * (_vehicle_radius(stolen_kind) + 19.0)
                    if not _static_blocked(driver_pos, 10.0):
                        pedestrians.append({"pos": driver_pos, "origin": driver_pos, "phase": 0.0, "axis": 0})
                elif source == "parked":
                    var selected: Dictionary = parked[index]
                    parked.remove_at(index)
                    parked.append({"pos": car, "kind": vehicle_kind, "health": vehicle_health})
                    car = selected["pos"]
                    vehicle_kind = int(selected["kind"])
                    vehicle_health = float(selected["health"])
                    angle = 0.0
                driving = vehicle_health > 0.0
                if driving:
                    player = car
                    speed = 0.0
    _e_held = Input.is_key_pressed(KEY_E)
    camera.position = player
    var target_zoom := 1.55
    if driving:
        target_zoom = lerpf(1.55, 0.94, clampf(abs(speed) / 380.0, 0.0, 1.0))
    camera.zoom = camera.zoom.lerp(Vector2(target_zoom, target_zoom), clampf(delta * 2.5, 0.0, 1.0))
    vehicle_bar.value = vehicle_health
    vehicle_bar.visible = driving
    status_label.text = ("Vehicle: " + VEHICLE_NAMES[vehicle_kind] + "  |  Damage: " + str(roundi(100.0 - vehicle_health)) + "%" if driving else "On foot  |  E: Take nearest vehicle")
    for i in range(health_tiles.get_child_count()):
        var tile: ColorRect = health_tiles.get_child(i)
        tile.color = Color("43c978") if health > float(i) * 10.0 else Color("d95454")
    queue_redraw()

func _building(p: Vector2, size: Vector2, roof: Color, windows: bool = true) -> void:
    draw_rect(Rect2(p + Vector2(9, 11), size), Color(0, 0, 0, 0.23))
    draw_rect(Rect2(p, size), Color("aeb9b7"))
    draw_rect(Rect2(p + Vector2(8, 8), size - Vector2(16, 16)), roof)
    draw_rect(Rect2(p + Vector2(18, 18), size - Vector2(36, 36)), roof.lightened(0.09), false, 3.0)
    if windows:
        for i in range(3):
            draw_rect(Rect2(p + Vector2(22 + i * (size.x - 52) / 3.0, 25), Vector2(18, 27)), Color("83b8c3"))

func _tree(p: Vector2, radius: float = 19.0) -> void:
    draw_circle(p + Vector2(5, 8), radius + 2.0, Color(0, 0, 0, 0.18))
    draw_circle(p, radius, Color("275e43"))
    draw_circle(p + Vector2(-5, -5), radius * 0.65, Color("45895a"))

func _park(origin: Vector2) -> void:
    draw_rect(Rect2(origin, Vector2(290, 290)), Color("639f67"))
    draw_rect(Rect2(origin + Vector2(132, 0), Vector2(25, 290)), Color("d2c8a4"))
    draw_rect(Rect2(origin + Vector2(0, 132), Vector2(290, 25)), Color("d2c8a4"))
    draw_circle(origin + Vector2(67, 65), 39, Color("55a9bd"))
    draw_arc(origin + Vector2(67, 65), 40, 0, TAU, 40, Color("d2c8a4"), 5.0)
    for p in [Vector2(27, 24), Vector2(245, 28), Vector2(28, 235), Vector2(243, 244), Vector2(211, 78), Vector2(78, 211)]:
        _tree(origin + p)

func _parking(origin: Vector2) -> void:
    draw_rect(Rect2(origin, Vector2(290, 290)), Color("49535c"))
    for i in range(6):
        var x := origin.x + 15.0 + i * 45.0
        draw_line(Vector2(x, origin.y + 20), Vector2(x, origin.y + 104), Color("c9c7b4"), 3.0)
        draw_line(Vector2(x, origin.y + 187), Vector2(x, origin.y + 270), Color("c9c7b4"), 3.0)
    for i in range(3):
        draw_rect(Rect2(origin + Vector2(22 + i * 86, 42), Vector2(28, 53)), Color("a9c1cb" if i % 2 == 0 else "b86657"))
    _tree(origin + Vector2(275, 145), 12)

func _industrial(origin: Vector2) -> void:
    draw_rect(Rect2(origin, Vector2(290, 290)), Color("7d8581"))
    _building(origin + Vector2(12, 12), Vector2(262, 132), Color("687985"), false)
    for i in range(7):
        draw_line(origin + Vector2(22, 25 + i * 18), origin + Vector2(262, 25 + i * 18), Color("8999a1"), 2.0)
    for i in range(4):
        draw_rect(Rect2(origin + Vector2(18 + i * 65, 185), Vector2(52, 86)), Color("bd7955" if i % 2 == 0 else "4c8790"))
        draw_line(origin + Vector2(18 + i * 65, 204), origin + Vector2(70 + i * 65, 204), Color("d4b69b"), 2.0)

func _residential(origin: Vector2, ix: int, iy: int) -> void:
    draw_rect(Rect2(origin, Vector2(290, 290)), Color("82a879"))
    for a in range(2):
        for b in range(2):
            var p := origin + Vector2(13 + a * 145, 13 + b * 145)
            draw_rect(Rect2(p, Vector2(125, 125)), Color("a8bc8c"))
            _building(p + Vector2(13, 12), Vector2(87, 85), Color("8c6259" if (a + b + ix) % 2 == 0 else "617d86"), false)
            _tree(p + Vector2(105, 106), 12)

func _downtown(origin: Vector2, ix: int, iy: int) -> void:
    draw_rect(Rect2(origin, Vector2(290, 290)), Color("b8b9ad"))
    if (ix + iy) % 3 == 0:
        _parking(origin)
    else:
        _building(origin + Vector2(14, 14), Vector2(125, 260), Color("465d6d"))
        _building(origin + Vector2(155, 14), Vector2(120, 123), Color("697987"))
        _building(origin + Vector2(155, 152), Vector2(120, 122), Color("8a7869"))

func _draw() -> void:
    draw_rect(Rect2(-WORLD / 2, -WORLD / 2, WORLD, WORLD), Color("71906a"))
    # Main roads, sidewalks and center markings.
    for n in range(-3, 4):
        var v := n * BLOCK
        draw_rect(Rect2(v - ROAD / 2 - 15, -WORLD / 2, ROAD + 30, WORLD), Color("a8aba5"))
        draw_rect(Rect2(-WORLD / 2, v - ROAD / 2 - 15, WORLD, ROAD + 30), Color("a8aba5"))
        draw_rect(Rect2(v - ROAD / 2, -WORLD / 2, ROAD, WORLD), Color("333c43"))
        draw_rect(Rect2(-WORLD / 2, v - ROAD / 2, WORLD, ROAD), Color("333c43"))
        for m in range(-11, 12):
            var d := m * 115.0 + 25.0
            draw_rect(Rect2(v - 2, d, 4, 52), Color("c9b975"))
            draw_rect(Rect2(d, v - 2, 52, 4), Color("c9b975"))
    # Crosswalks at intersections.
    for x in range(-3, 4):
        for y in range(-3, 4):
            var center := Vector2(x * BLOCK, y * BLOCK)
            for z in range(5):
                draw_rect(Rect2(center + Vector2(-52 + z * 24, -104), Vector2(14, 25)), Color("d6d7cc"))
                draw_rect(Rect2(center + Vector2(-52 + z * 24, 79), Vector2(14, 25)), Color("d6d7cc"))
                draw_rect(Rect2(center + Vector2(-104, -52 + z * 24), Vector2(25, 14)), Color("d6d7cc"))
                draw_rect(Rect2(center + Vector2(79, -52 + z * 24), Vector2(25, 14)), Color("d6d7cc"))
    # Distinct neighborhoods: residential, downtown, park, industrial.
    for x in range(-3, 3):
        for y in range(-3, 3):
            var origin := Vector2(x * BLOCK + 90, y * BLOCK + 90)
            if x >= 1 and y >= 1:
                _industrial(origin)
            elif x <= -1 and y <= -1:
                _residential(origin, x, y)
            elif (x == -1 and y == 1) or (x == 0 and y == 1) or (x == -2 and y == 0):
                _park(origin)
            else:
                _downtown(origin, x, y)
    for x in range(-3, 4):
        for y in range(-3, 4):
            var p := Vector2(float(x) * BLOCK - 63, float(y) * BLOCK - 63)
            draw_rect(Rect2(p, Vector2(16, 16)), Color("202a30"))
            draw_circle(p + Vector2(8, 8), 5, Color("e24b42") if light_time >= 7.0 else Color("4dc76e"))
    for vehicle in traffic:
        var p: Vector2 = vehicle["pos"]
        var dir: Vector2 = vehicle["dir"]
        _draw_vehicle(p, dir.angle() + PI / 2.0, int(vehicle["kind"]), 1.0)
    draw_set_transform(Vector2.ZERO, 0.0)
    for item in parked:
        _draw_vehicle(item["pos"], 0.0, item["kind"], 1.0)
    for person in pedestrians:
        var p: Vector2 = person["pos"]
        draw_circle(p + Vector2(2, 4), 10.0, Color(0, 0, 0, 0.2))
        draw_circle(p, 8.0, Color("d6ae8e"))
        draw_arc(p, 9.0, 0.0, TAU, 16, Color("4d7290"), 3.0)
    _draw_vehicle(car, angle, vehicle_kind, vehicle_health / 100.0)
    draw_set_transform(Vector2.ZERO, 0.0)
    if not driving:
        draw_circle(player + Vector2(3, 5), 13, Color(0, 0, 0, 0.25))
        draw_circle(player, 11, Color("e7c8a2"))
        draw_arc(player, 12, 0, TAU, 32, Color("294b86"), 4)

func _draw_vehicle(pos: Vector2, rotation: float, kind: int, condition: float) -> void:
    var size: Vector2 = VEHICLE_SIZES[kind]
    var w := size.x
    var h := size.y
    draw_set_transform(pos, rotation)
    var paint := Color(VEHICLE_COLORS[kind]).darkened((1.0 - condition) * 0.45)
    draw_rect(Rect2(-w * 0.5 + 5, -h * 0.5 + 7, w, h), Color(0, 0, 0, 0.25))
    # Tires, wheel wells and body trim.
    for side in [-1.0, 1.0]:
        var wx := -w * 0.5 - 3.0 if side < 0 else w * 0.5 - 2.0
        draw_rect(Rect2(wx, -h * 0.36, 5, 19), Color("171e23"))
        draw_rect(Rect2(wx, h * 0.18, 5, 19), Color("171e23"))
    draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), paint)
    draw_rect(Rect2(-w * 0.5 + 3, -h * 0.5 + 4, w - 6, h - 8), paint.lightened(0.08), false, 1.5)
    if kind == 4 or kind == 5:
        draw_rect(Rect2(-w * 0.26, -h * 0.16, w * 0.52, h * 0.32), Color("253b4c"))
        draw_circle(Vector2(0, -h * 0.06), 5, Color("31353b"))
    else:
        draw_rect(Rect2(-w * 0.41, -h * 0.28, w * 0.82, h * 0.23), Color("395c72"))
        draw_line(Vector2(-w * 0.36, -h * 0.05), Vector2(w * 0.36, -h * 0.05), Color("b7d0d5"), 2.0)
        if kind == 2 or kind == 3:
            draw_rect(Rect2(-w * 0.41, h * 0.13, w * 0.82, h * 0.30), Color("59666e"))
            if kind == 2:
                for i in range(3):
                    draw_line(Vector2(-w * 0.34, h * (0.18 + i * 0.07)), Vector2(w * 0.34, h * (0.18 + i * 0.07)), Color("839097"), 1.0)
        else:
            draw_rect(Rect2(-w * 0.41, h * 0.10, w * 0.82, h * 0.19), Color("395c72"))
        draw_line(Vector2(0, -h * 0.49), Vector2(0, -h * 0.31), paint.darkened(0.22), 1.0)
    # Headlamps face the front (-Y); red taillamps face the rear (+Y).
    var lamp_w := maxf(4.0, w * 0.19)
    for side in [-1.0, 1.0]:
        var lamp_x := -w * 0.39 if side < 0 else w * 0.39 - lamp_w
        draw_rect(Rect2(lamp_x, -h * 0.5 + 2, lamp_w, 6), Color("fff3c1"))
        draw_rect(Rect2(lamp_x, h * 0.5 - 8, lamp_w, 6), Color("f0443e"))
        draw_rect(Rect2(lamp_x, h * 0.5 - 10, lamp_w, 2), Color("ff9a63"))
    draw_rect(Rect2(-w * 0.24, -h * 0.5 + 1, w * 0.48, 3), Color("28323b"))
    draw_rect(Rect2(-w * 0.24, h * 0.5 - 4, w * 0.48, 3), Color("28323b"))
    draw_set_transform(Vector2.ZERO, 0.0)
