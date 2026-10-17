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
    for n in range(-2, 3):
        var road := float(n) * BLOCK
        traffic.append({"pos": Vector2(-1000.0 + n * 120.0, road + 30), "dir": Vector2.RIGHT})
        traffic.append({"pos": Vector2(1000.0 - n * 120.0, road - 30), "dir": Vector2.LEFT})
        traffic.append({"pos": Vector2(road - 30, -900.0 + n * 130.0), "dir": Vector2.DOWN})
        traffic.append({"pos": Vector2(road + 30, 900.0 - n * 130.0), "dir": Vector2.UP})

func _blocked(pos: Vector2, radius: float, check_traffic: bool = true) -> bool:
    if abs(pos.x) + radius > WORLD / 2.0 or abs(pos.y) + radius > WORLD / 2.0:
        return true
    for rect in blockers:
        var q := Vector2(clampf(pos.x, rect.position.x, rect.end.x), clampf(pos.y, rect.position.y, rect.end.y))
        if q.distance_squared_to(pos) < radius * radius:
            return true
    if check_traffic:
        for vehicle in traffic:
            var p: Vector2 = vehicle["pos"]
            if p.distance_squared_to(pos) < (radius + 23.0) * (radius + 23.0):
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
    for vehicle in traffic:
        var pos: Vector2 = vehicle["pos"]
        var dir: Vector2 = vehicle["dir"]
        var axis := pos.x if abs(dir.x) > 0.5 else pos.y
        var heading := dir.x if abs(dir.x) > 0.5 else dir.y
        var red := light_time >= 7.0 if abs(dir.x) > 0.5 else light_time < 7.0
        var stop := false
        if red:
            for n in range(-3, 4):
                var dist := (float(n) * BLOCK - axis) * heading
                if dist >= 76.0 and dist < 79.0 + 100.0 * delta:
                    stop = true
        if not stop:
            var next := pos + dir * 100.0 * delta
            if next.distance_to(car) > 53.0:
                pos = next
        if pos.x > 1390.0:
            pos.x = -1390.0
        if pos.x < -1390.0:
            pos.x = 1390.0
        if pos.y > 1390.0:
            pos.y = -1390.0
        if pos.y < -1390.0:
            pos.y = 1390.0
        vehicle["pos"] = pos


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
    hud.text = "FIRST DRIVE 0.2  |  WASD: Move / Drive   E: Enter / Exit   Space: Brake"
    ui.add_child(hud)
    _setup_world()
    queue_redraw()

func _process(delta: float) -> void:
    _traffic_tick(delta)
    var move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    if driving:
        speed = move_toward(speed, -move.y * 380.0, 350.0 * delta)
        if Input.is_key_pressed(KEY_SPACE):
            speed = move_toward(speed, 0.0, 900.0 * delta)
        if abs(speed) > 5.0:
            angle += move.x * 2.3 * delta * sign(speed)
        var motion := Vector2.UP.rotated(angle) * speed * delta
        var next := _move_safely(car, motion, 22.0)
        if next.distance_to(car + motion) > 2.0:
            speed = 0.0
        car = next
        player = car
    else:
        player = _move_safely(player, move * 230.0 * delta, 11.0)
    if Input.is_key_pressed(KEY_E) and not _e_held:
        if driving:
            var exit_pos := car + Vector2.RIGHT.rotated(angle) * 58.0
            if not _blocked(exit_pos, 11.0):
                driving = false
                player = exit_pos
                speed = 0.0
        elif player.distance_to(car) < 85.0:
            driving = true
    _e_held = Input.is_key_pressed(KEY_E)
    camera.position = player
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
        draw_set_transform(p, dir.angle() + PI / 2.0)
        draw_rect(Rect2(-19, -32, 38, 64), Color("b96455"))
        draw_rect(Rect2(-15, -16, 30, 20), Color("354e64"))
    draw_set_transform(Vector2.ZERO, 0.0)
    draw_set_transform(car, angle)
    draw_rect(Rect2(-21, -40, 42, 80), Color("e8b746"))
    draw_rect(Rect2(-17, -22, 34, 23), Color("2c4b5d"))
    draw_rect(Rect2(-17, 8, 34, 17), Color("2c4b5d"))
    draw_rect(Rect2(-22, -30, 4, 14), Color("20242b"))
    draw_rect(Rect2(18, -30, 4, 14), Color("20242b"))
    draw_set_transform(Vector2.ZERO, 0.0)
    if not driving:
        draw_circle(player + Vector2(3, 5), 13, Color(0, 0, 0, 0.25))
        draw_circle(player, 11, Color("e7c8a2"))
        draw_arc(player, 12, 0, TAU, 32, Color("294b86"), 4)
