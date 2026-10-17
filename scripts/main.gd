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
var wanted := 0
var police: Array[Dictionary] = []
var wanted_star: Label
var car_invulnerability := 0.0
var crash_audio: AudioStreamPlayer
var crash_cooldown := 0.0


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
        var clear: bool = (item["pos"] as Vector2).distance_to(car) > _vehicle_radius(int(item["kind"])) + _vehicle_radius(vehicle_kind) + 12.0
        for other in clean:
            if (item["pos"] as Vector2).distance_to(other["pos"] as Vector2) < _vehicle_radius(int(item["kind"])) + _vehicle_radius(int(other["kind"])) + 12.0:
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


func _overlaps(a: Vector2, ar: float, ak: int, b: Vector2, br: float, bk: int, margin: float = 2.0) -> bool:
    var ah: Vector2 = VEHICLE_SIZES[ak] * 0.5 + Vector2.ONE * margin
    var bh: Vector2 = VEHICLE_SIZES[bk] * 0.5 + Vector2.ONE * margin
    var ax := Vector2.RIGHT.rotated(ar)
    var ay := Vector2.DOWN.rotated(ar)
    var bx := Vector2.RIGHT.rotated(br)
    var by := Vector2.DOWN.rotated(br)
    for axis in [ax, ay, bx, by]:
        var ra := ah.x * absf(axis.dot(ax)) + ah.y * absf(axis.dot(ay))
        var rb := bh.x * absf(axis.dot(bx)) + bh.y * absf(axis.dot(by))
        if absf((b - a).dot(axis)) >= ra + rb:
            return false
    return true

func _angle_for(dir: Vector2) -> float:
    return dir.angle() + PI * 0.5

func _clear_vehicle(p: Vector2, rot: float, kind: int, skip: int = -1, include_player: bool = true) -> bool:
    var half: Vector2 = VEHICLE_SIZES[kind] * 0.5
    for x in [-1.0, 1.0]:
        for y in [-1.0, 1.0]:
            if _static_blocked(p + Vector2(x * half.x, y * half.y).rotated(rot), 1.0):
                return false
    if include_player and _overlaps(p, rot, kind, car, angle, vehicle_kind):
        return false
    for i in range(traffic.size()):
        if i != skip and _overlaps(p, rot, kind, traffic[i]["pos"], _angle_for(traffic[i]["dir"]), int(traffic[i]["kind"])):
            return false
    for other in parked:
        if _overlaps(p, rot, kind, other["pos"], 0.0, int(other["kind"])):
            return false
    return true

func _nearest_road(value: float) -> float:
    return clampf(roundf(value / BLOCK) * BLOCK, -2.0 * BLOCK, 2.0 * BLOCK)

func _police_road_spawn(target: Vector2) -> Vector2:
    var center := Vector2(_nearest_road(target.x), _nearest_road(target.y))
    var choices := [
        center + Vector2(-BLOCK, 30.0),
        center + Vector2(BLOCK, -30.0),
        center + Vector2(30.0, -BLOCK),
        center + Vector2(-30.0, BLOCK)
    ]
    for p in choices:
        if p.distance_to(target) > 140.0 and _road_clear(p, 0.0):
            return p
    return center + Vector2(0, 30)

func _on_road(p: Vector2, margin: float = 0.0) -> bool:
    if absf(p.x) > WORLD * 0.5 - 45.0 or absf(p.y) > WORLD * 0.5 - 45.0:
        return false
    return absf(p.x - _nearest_road(p.x)) < ROAD * 0.5 - margin or absf(p.y - _nearest_road(p.y)) < ROAD * 0.5 - margin

func _road_clear(p: Vector2, heading: float) -> bool:
    var half: Vector2 = VEHICLE_SIZES[0] * 0.5
    for x in [-1.0, 1.0]:
        for y in [-1.0, 1.0]:
            var corner := p + Vector2(x * half.x, y * half.y).rotated(heading)
            if not _on_road(corner, 3.0) or _static_blocked(corner, 1.0):
                return false
    return true

func _police_update(delta: float) -> void:
    if wanted == 0:
        return
    for cop in police:
        var pos: Vector2 = cop["pos"]
        var heading: float = float(cop.get("angle", 0.0))
        var velocity: float = float(cop.get("speed", 0.0))
        # Choose a street intersection close to the suspect. Police stay
        # on the road grid instead of cutting diagonally through parking lots.
        var junction := Vector2(_nearest_road(pos.x), _nearest_road(pos.y))
        var suspect_junction := Vector2(_nearest_road(player.x), _nearest_road(player.y))
        var waypoint := junction
        if pos.distance_to(junction) > 38.0:
            waypoint = junction
        elif absf(suspect_junction.x - junction.x) > 20.0:
            waypoint = junction + Vector2(signf(suspect_junction.x - junction.x) * BLOCK, 0)
        elif absf(suspect_junction.y - junction.y) > 20.0:
            waypoint = junction + Vector2(0, signf(suspect_junction.y - junction.y) * BLOCK)
        else:
            waypoint = junction
        # Follow the chosen road segment using a gentle steering response.
        var target: Vector2 = waypoint - pos
        var desired: float = target.angle() + PI * 0.5 if target.length() > 3.0 else heading
        var difference: float = wrapf(desired - heading, -PI, PI)
        var desired_speed: float = 135.0 if target.length() > 24.0 else 0.0
        if absf(difference) > 0.45:
            desired_speed = minf(desired_speed, 42.0)
        velocity = move_toward(velocity, desired_speed, (230.0 if desired_speed < velocity else 120.0) * delta)
        heading += clampf(difference, -1.0, 1.0) * 1.85 * clampf(absf(velocity) / 80.0, 0.15, 1.0) * delta
        var motion := Vector2.UP.rotated(heading) * velocity * delta
        var steps := maxi(1, int(ceil(motion.length() / 3.0)))
        for i in range(steps):
            var candidate := pos + motion / float(steps)
            var blocked := not _road_clear(candidate, heading)
            if _overlaps(candidate, heading, 0, car, angle, vehicle_kind, 8.0):
                blocked = true
            for vehicle in traffic:
                if _overlaps(candidate, heading, 0, vehicle["pos"], _angle_for(vehicle["dir"]), int(vehicle["kind"]), 5.0):
                    blocked = true
                    break
            for vehicle in parked:
                if _overlaps(candidate, heading, 0, vehicle["pos"], 0.0, int(vehicle["kind"]), 5.0):
                    blocked = true
                    break
            if blocked:
                velocity = 0.0
                break
            pos = candidate
        cop["pos"] = pos
        cop["angle"] = heading
        cop["speed"] = velocity
        if pos.distance_to(player) < 56.0 and game_time - last_hit > 1.5:
            health = maxf(0.0, health - 10.0)
            last_hit = game_time

func _draw_police_car(pos: Vector2, heading: float) -> void:
    draw_set_transform(pos, heading)
    # Vehicle front points towards local -Y, matching the steering physics.
    draw_rect(Rect2(-25, -44, 50, 90), Color(0, 0, 0, 0.27))
    for side in [-1.0, 1.0]:
        var wheel_x := -27.0 if side < 0.0 else 22.0
        draw_rect(Rect2(wheel_x, -30, 6, 20), Color("1b2026"))
        draw_rect(Rect2(wheel_x, 19, 6, 20), Color("1b2026"))
    draw_rect(Rect2(-23, -44, 46, 88), Color("e6e9e9"))
    draw_rect(Rect2(-23, -12, 46, 32), Color("245c9b"))
    draw_rect(Rect2(-19, -30, 38, 17), Color("344d63"))
    draw_rect(Rect2(-19, 23, 38, 13), Color("344d63"))
    draw_rect(Rect2(-18, -42, 12, 6), Color("fff1bd"))
    draw_rect(Rect2(6, -42, 12, 6), Color("fff1bd"))
    draw_rect(Rect2(-18, 38, 12, 5), Color("e74242"))
    draw_rect(Rect2(6, 38, 12, 5), Color("e74242"))
    draw_rect(Rect2(-20, -7, 40, 15), Color("f3f5f4"))
    draw_line(Vector2(-16, 0), Vector2(16, 0), Color("244e7a"), 2.0)
    # Alternating red and blue roof lights with a subtle light halo.
    var flash := int(game_time * 7.0) % 2 == 0
    var left := Color("e9323d") if flash else Color("6b1e29")
    var right := Color("255fff") if not flash else Color("172b68")
    draw_circle(Vector2(-12, -10), 16, Color(1.0, 0.13, 0.15, 0.18) if flash else Color(0.0, 0.0, 0.0, 0.0))
    draw_circle(Vector2(12, -10), 16, Color(0.12, 0.35, 1.0, 0.2) if not flash else Color(0.0, 0.0, 0.0, 0.0))
    draw_rect(Rect2(-20, -15, 40, 10), Color("202a34"))
    draw_rect(Rect2(-18, -14, 17, 8), left)
    draw_rect(Rect2(1, -14, 17, 8), right)
    draw_set_transform(Vector2.ZERO, 0.0)


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
    var old: Array[Vector2] = []
    for item in traffic:
        old.append(item["pos"])
    var next_positions: Array[Vector2] = []
    for i in range(traffic.size()):
        var item: Dictionary = traffic[i]
        var pos: Vector2 = old[i]
        var dir: Vector2 = item["dir"]
        var kind := int(item["kind"])
        var rot := _angle_for(dir)
        var next := pos + dir * 100.0 * delta
        var red := light_time >= 7.0 if absf(dir.x) > 0.5 else light_time < 7.0
        var axis := pos.x if absf(dir.x) > 0.5 else pos.y
        var heading := dir.x if absf(dir.x) > 0.5 else dir.y
        var stop := false
        # Slow traffic near a pedestrian so the E interaction is achievable.
        if not driving and pos.distance_to(player) < 155.0:
            stop = true
        if red:
            for n in range(-3, 4):
                var d := (float(n) * BLOCK - axis) * heading
                var threshold: float = 75.0 + (VEHICLE_SIZES[kind] as Vector2).y * 0.5
                if d >= threshold and d < threshold + 100.0 * delta + 2.0:
                    stop = true
        if _overlaps(next, rot, kind, car, angle, vehicle_kind, 4.0):
            stop = true
        for other in parked:
            if _overlaps(next, rot, kind, other["pos"], 0.0, int(other["kind"]), 4.0):
                stop = true
        for j in range(traffic.size()):
            if j != i and _overlaps(next, rot, kind, old[j], _angle_for(traffic[j]["dir"]), int(traffic[j]["kind"]), 4.0):
                stop = true
        for j in range(next_positions.size()):
            if _overlaps(next, rot, kind, next_positions[j], _angle_for(traffic[j]["dir"]), int(traffic[j]["kind"]), 4.0):
                stop = true
        if not stop and _clear_vehicle(next, rot, kind, i):
            pos = next
        var wrapped := pos
        if pos.x > 1370.0:
            wrapped.x = -1370.0
        elif pos.x < -1370.0:
            wrapped.x = 1370.0
        if pos.y > 1370.0:
            wrapped.y = -1370.0
        elif pos.y < -1370.0:
            wrapped.y = 1370.0
        if wrapped != pos and _clear_vehicle(wrapped, rot, kind, i):
            pos = wrapped
        next_positions.append(pos)
    for i in range(traffic.size()):
        traffic[i]["pos"] = next_positions[i]

func _setup_crash_sound() -> void:
    crash_audio = AudioStreamPlayer.new()
    add_child(crash_audio)
    var sample := AudioStreamWAV.new()
    sample.mix_rate = 22050
    sample.format = AudioStreamWAV.FORMAT_16_BITS
    var pcm := PackedByteArray()
    var rng := RandomNumberGenerator.new()
    rng.seed = 8731
    for i in range(6500):
        var t := float(i) / 22050.0
        var envelope := pow(maxf(0.0, 1.0 - t / 0.295), 2.0)
        var rumble := sin(TAU * (85.0 * t - 80.0 * t * t))
        var noise := rng.randf_range(-1.0, 1.0)
        var value := clampf((rumble * 0.55 + noise * 0.45) * envelope, -1.0, 1.0)
        var v := int(value * 20000.0)
        pcm.append(v & 255)
        pcm.append((v >> 8) & 255)
    sample.data = pcm
    crash_audio.stream = sample
    crash_audio.volume_db = -7.0

func _play_crash(intensity: float) -> void:
    if crash_cooldown > 0.0:
        return
    crash_cooldown = 0.28
    crash_audio.volume_db = lerpf(-17.0, -2.0, clampf(intensity / 350.0, 0.0, 1.0))
    crash_audio.play()

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
    _setup_crash_sound()
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
    wanted_star = Label.new()
    wanted_star.text = "★"
    wanted_star.add_theme_font_size_override("font_size", 42)
    wanted_star.add_theme_color_override("font_color", Color("ffd54a"))
    wanted_star.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    wanted_star.anchor_left = 1.0
    wanted_star.anchor_right = 1.0
    wanted_star.offset_left = -322.0
    wanted_star.offset_right = -272.0
    wanted_star.offset_top = 4.0
    wanted_star.offset_bottom = 58.0
    wanted_star.visible = false
    ui.add_child(wanted_star)
    queue_redraw()

func _process(delta: float) -> void:
    game_time += delta
    crash_cooldown = maxf(0.0, crash_cooldown - delta)
    car_invulnerability = maxf(0.0, car_invulnerability - delta)
    _traffic_tick(delta)
    _update_pedestrians(delta)
    _police_update(delta)
    wanted_star.visible = wanted > 0 and int(game_time * 3.5) % 2 == 0
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
            if _clear_vehicle(candidate, angle, vehicle_kind, -1, false):
                next = candidate
            else:
                break
        if next.distance_to(car + motion) > 1.0:
            if abs(speed) > 65.0 and car_invulnerability <= 0.0:
                _play_crash(absf(speed))
                vehicle_health = maxf(0.0, vehicle_health - abs(speed) * 0.035)
                car_invulnerability = 0.35
            speed = 0.0
        car = next
        player = car
        if absf(speed) > 45.0:
            for i in range(pedestrians.size() - 1, -1, -1):
                if car.distance_to(pedestrians[i]["pos"]) < _vehicle_radius(vehicle_kind):
                    pedestrians.remove_at(i)
                    wanted = 1
                    if police.is_empty():
                        police.append({"pos": _police_road_spawn(player), "angle": 0.0, "speed": 0.0})
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
            var nearest := 170.0
            var source := ""
            var index := -1
            var d := player.distance_to(car)
            if d < 80.0:
                nearest = d
                source = "own"
            for i in range(parked.size()):
                d = player.distance_to(parked[i]["pos"])
                if d < nearest and d < 115.0:
                    nearest = d
                    source = "parked"
                    index = i
            for i in range(traffic.size()):
                d = player.distance_to(traffic[i]["pos"])
                if d < nearest and d < 155.0:
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
    if not driving:
        var nearest_car := 999999.0
        for item in traffic:
            nearest_car = minf(nearest_car, player.distance_to(item["pos"]))
        for item in parked:
            nearest_car = minf(nearest_car, player.distance_to(item["pos"]))
        if nearest_car < 155.0:
            status_label.text = "E: Fahrzeug übernehmen"
    if wanted > 0:
        status_label.text += "  |  WANTED: POLICE"
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
    # Visible concrete barriers close the streets at the city limits.
    var edge := WORLD * 0.5 - 15.0
    for n in range(-3, 4):
        var lane := float(n) * BLOCK
        for k in range(-3, 4):
            var off := float(k) * 20.0
            for side in [-1.0, 1.0]:
                draw_rect(Rect2(Vector2(side * edge - 10.0, lane + off - 9.0), Vector2(20, 18)), Color("d7d6cb"))
                draw_rect(Rect2(Vector2(lane + off - 9.0, side * edge - 10.0), Vector2(18, 20)), Color("d7d6cb"))
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
    for cop in police:
        _draw_police_car(cop["pos"], float(cop.get("angle", 0.0)))
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
