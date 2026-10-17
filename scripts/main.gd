extends Node2D

const ROAD = 170.0
const BLOCK = 430.0
const WORLD = 2400.0
var player := Vector2(120, 120)
var car := Vector2(270, 100)
var angle := 0.0
var speed := 0.0
var driving := false
var camera: Camera2D
var hud: Label
var _e_held := false

func _ready() -> void:
    camera = Camera2D.new()
    camera.position_smoothing_enabled = true
    camera.position_smoothing_speed = 6.0
    add_child(camera)
    camera.make_current()
    hud = Label.new()
    hud.position = Vector2(18, 18)
    hud.add_theme_font_size_override("font_size", 18)
    hud.text = "FIRST DRIVE 0.1 | WASD: Move/Drive | E: Enter/Exit | Space: Brake"
    var ui := CanvasLayer.new()
    add_child(ui)
    ui.add_child(hud)
    queue_redraw()

func _process(delta: float) -> void:
    var move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    if driving:
        var throttle := -move.y
        speed = move_toward(speed, throttle * 380.0, 350.0 * delta)
        if Input.is_key_pressed(KEY_SPACE):
            speed = move_toward(speed, 0.0, 900.0 * delta)
        if abs(speed) > 5.0:
            angle += move.x * 2.3 * delta * sign(speed)
        car += Vector2.UP.rotated(angle) * speed * delta
        player = car
    else:
        player += move * 230.0 * delta
    if Input.is_key_pressed(KEY_E) and not _e_held:
        if driving:
            driving = false
            player = car + Vector2(60, 0)
            speed = 0.0
        elif player.distance_to(car) < 100.0:
            driving = true
    _e_held = Input.is_key_pressed(KEY_E)
    player = player.clamp(Vector2(-WORLD / 2, -WORLD / 2), Vector2(WORLD / 2, WORLD / 2))
    car = car.clamp(Vector2(-WORLD / 2, -WORLD / 2), Vector2(WORLD / 2, WORLD / 2))
    camera.position = player
    queue_redraw()

func _draw() -> void:
    draw_rect(Rect2(-WORLD / 2, -WORLD / 2, WORLD, WORLD), Color("6c8a62"))
    for n in range(-3, 4):
        var x := n * BLOCK
        draw_rect(Rect2(x - ROAD / 2, -WORLD / 2, ROAD, WORLD), Color("303b45"))
        draw_rect(Rect2(-WORLD / 2, x - ROAD / 2, WORLD, ROAD), Color("303b45"))
        for m in range(-10, 11):
            draw_rect(Rect2(x - 2, m * 130 + 20, 4, 58), Color("d8c88c"))
            draw_rect(Rect2(m * 130 + 20, x - 2, 58, 4), Color("d8c88c"))
    for x in range(-3, 3):
        for y in range(-3, 3):
            var p := Vector2(x * BLOCK + 110, y * BLOCK + 110)
            draw_rect(Rect2(p + Vector2(9, 12), Vector2(180, 180)), Color(0, 0, 0, 0.2))
            draw_rect(Rect2(p, Vector2(180, 180)), Color("9fafa9"))
            draw_rect(Rect2(p + Vector2(14, 14), Vector2(152, 152)), Color("506575"))
            for i in range(3):
                draw_rect(Rect2(p + Vector2(30 + i * 45, 38), Vector2(24, 55)), Color("88bac3"))
    draw_set_transform(car, angle)
    draw_rect(Rect2(-21, -40, 42, 80), Color("e8b746"))
    draw_rect(Rect2(-17, -22, 34, 23), Color("2c4b5d"))
    draw_rect(Rect2(-17, 8, 34, 17), Color("2c4b5d"))
    draw_set_transform(Vector2.ZERO, 0.0)
    if not driving:
        draw_circle(player + Vector2(3, 5), 13, Color(0, 0, 0, 0.25))
        draw_circle(player, 11, Color("e7c8a2"))
        draw_arc(player, 12, 0, TAU, 32, Color("294b86"), 4)
