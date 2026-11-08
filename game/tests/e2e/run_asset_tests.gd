extends SceneTree

const Art = preload("res://game/ui/asset_theme.gd")
const Radial = preload("res://game/ui/radial_menu.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(Art.texture("unknown_role") == null, "unlisted asset role cannot load arbitrary resources")
	var installed: bool = Art.texture("button_frame") != null
	if not installed:
		check(OS.get_environment("SHELTER_REQUIRE_ASSETS") != "1", "source fallback allowed only when assets are not required")
		print("ASSET PACK: NOT_INSTALLED; fallback checks only")
		finish()
		return
	for role in Art.ROLES:
		var texture := Art.texture(role)
		check(texture != null and texture.get_size() == Vector2(32, 32), "reviewed Kibyra texture loads: " + role)
	var app = preload("res://game/scenes/main/playable.tscn").instantiate()
	app.save_location = "user://asset-tests/" + str(Time.get_ticks_usec()) + ".json"
	root.add_child(app)
	await process_frame
	await process_frame
	check(app.ui.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "pixel art UI uses nearest filtering")
	check(app.ui.theme.get_stylebox("normal", "Button") is StyleBoxTexture, "real image-backed button style replaces flat placeholder")
	check(app.ui.theme.get_stylebox("hover", "Button") is StyleBoxTexture and app.ui.theme.get_stylebox("pressed", "Button") is StyleBoxTexture and app.ui.theme.get_stylebox("focus", "Button") is StyleBoxTexture, "hover pressed and keyboard focus states have texture styles")
	check(app.ui.heading_icon.texture == Art.texture("shelter"), "welcome header displays pack artwork")
	app.ui.close_panel()
	await process_frame
	var viewport: Vector2 = app.ui.get_viewport_rect().size
	var center: Vector2 = app.ui.radial.wheel_center()
	var wheel_rect := Rect2(center - Vector2.ONE * Radial.RADIUS,
		Vector2.ONE * Radial.RADIUS * 2.0)
	check(Rect2(Vector2.ZERO, viewport).encloses(wheel_rect)
		and wheel_rect.position.x >= viewport.x * 0.64
		and wheel_rect.end.y < viewport.y * 0.84,
		"PC radial wheel fits to the right of construction and above bottom shortcuts")
	check([app.ui.hud.map_node, app.ui.hud.hotbar, app.ui.hud.navigation].all(
		func(section): return not wheel_rect.intersects(section.get_global_rect())),
		"PC radial wheel does not obscure minimap, hotbar or bottom navigation")
	for section in [app.ui.hud.map_node, app.ui.hud.hotbar, app.ui.hud.navigation]:
		check(Rect2(Vector2.ZERO, viewport).encloses(section.get_global_rect()), "HUD section fits design viewport: " + section.name)
	var quick: Button = app.ui.shelter_nav_button
	check(quick != null and Rect2(Vector2.ZERO, viewport).encloses(quick.get_global_rect()) and quick.get_global_rect().end.y <= 35, "Shelter HUD button fits 640x360")
	check(app.ui.shelter_modal_button != null, "Shelter modal action exists with radial HUD")
	var panel: PanelContainer = app.ui.modal.get_child(0)
	check(panel.get_theme_stylebox("panel") is StyleBoxTexture, "modal frame uses selected Kibyra panel artwork")
	check(panel.get_global_rect().end.x <= viewport.x and panel.get_global_rect().end.y <= viewport.y, "skinned modal fits design viewport")
	for name in ["inventory", "farm", "rest", "residents", "quests", "shop", "save", "credits"]:
		app.ui.open_panel(name)
		await process_frame
		await process_frame
		check(app.ui.heading_icon.texture != null and app.ui.heading.text.length() > 0 and app.session.pauses.is_paused(), "skinned panel preserves icon title and pause: " + name)
	check(app.ui.body.get_child_count() >= 4, "credits include author and source")
	app.ui.close_panel()
	check(not app.session.pauses.is_paused(), "skin does not leave an extra pause owner")
	app.free()
	await process_frame
	finish()

func finish() -> void:
	print("ASSET TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
