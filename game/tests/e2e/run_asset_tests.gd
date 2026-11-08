extends SceneTree

const Art = preload("res://game/ui/asset_theme.gd")
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
	var health_icon: TextureRect = app.ui.find_child("HealthIcon", true, false)
	check(health_icon != null and health_icon.size == Vector2(14, 14) and health_icon.get_global_rect().end.x + 4 <= app.ui.hud.get_global_rect().position.x, "health icon respects target size and does not overlap HUD text")
	var viewport: Vector2 = app.ui.get_viewport_rect().size
	var shelter_button: Button = app.ui.shelter_nav_button
	check(shelter_button != null and shelter_button.get_global_rect().end.x <= viewport.x and shelter_button.get_global_rect().end.y <= 35, "permanent shelter quick button fits top HUD without overlapping world")
	for child in app.ui.get_children():
		if child is Panel:
			var nav = child.get_child(child.get_child_count() - 1)
			if nav is HBoxContainer:
				for button in nav.get_children():
					check(button is Button and button.icon != null and button.get_global_rect().end.x <= viewport.x and button.get_global_rect().end.y <= 85, "navigation icon fits viewport without covering world")
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
