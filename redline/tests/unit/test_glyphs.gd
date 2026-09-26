extends RedlineTestCase
## M9 T03 (D4 §5): controller glyph families, layout-aware key names and
## labels that follow rebinds.

var _snap: Dictionary = {}
var _was_pad: bool = false
var _was_device: int = 0


func before_each() -> void:
	_snap = snapshot_settings()
	_was_pad = InputGlyphs.using_pad
	_was_device = InputGlyphs.last_pad_device
	InputBindings.apply({})


func after_each() -> void:
	InputGlyphs.using_pad = _was_pad
	InputGlyphs.last_pad_device = _was_device
	restore_settings(_snap)


func test_family_for_name() -> void:
	check(InputGlyphs.family_for_name("DualSense Wireless Controller") == &"playstation", "DualSense")
	check(InputGlyphs.family_for_name("PS4 Controller") == &"playstation", "PS4")
	check(InputGlyphs.family_for_name("Sony Interactive Entertainment Wireless Controller") == &"playstation", "Sony")
	check(InputGlyphs.family_for_name("Nintendo Switch Pro Controller") == &"nintendo", "Switch Pro")
	check(InputGlyphs.family_for_name("Joy-Con (L/R)") == &"nintendo", "Joy-Con")
	check(InputGlyphs.family_for_name("Xbox Wireless Controller") == &"xbox", "Xbox")
	check(InputGlyphs.family_for_name("Steam Deck") == &"xbox", "Steam Deck reads as Xbox")
	check(InputGlyphs.family_for_name("") == &"xbox", "unknown reads as Xbox")
	Settings.pad_glyphs = 2
	check(InputGlyphs.family_id() == &"playstation", "forced PlayStation")
	Settings.pad_glyphs = 3
	check(InputGlyphs.family().id == &"nintendo", "forced Nintendo set")


func test_nintendo_positional_labels() -> void:
	InputGlyphs.using_pad = true
	Settings.pad_glyphs = 3
	check(InputGlyphs.label(&"jump") == "B", "bottom face button prints B on Nintendo (%s)" % InputGlyphs.label(&"jump"))
	check(InputGlyphs.label(&"dodge") == "A", "right face button prints A")
	check(InputGlyphs.label(&"attack_light") == "Y", "left face button prints Y")
	check(InputGlyphs.label(&"heal") == "ZL", "left trigger")
	Settings.pad_glyphs = 2
	check(InputGlyphs.label(&"jump") == "Cross", "PlayStation bottom button")
	check(InputGlyphs.label(&"heal") == "L2", "PlayStation left trigger")
	Settings.pad_glyphs = 1
	check(InputGlyphs.label(&"jump") == "A" and InputGlyphs.label(&"heal") == "LT", "Xbox names as in M8")
	check(InputGlyphs.label(&"move_left") == "D-Pad Left", "move prompts name the D-pad, not the stick")


func test_label_follows_rebind() -> void:
	InputGlyphs.using_pad = false
	check(InputGlyphs.label(&"attack_light") == "J", "shipped J")
	InputBindings.apply({"attack_light": {"key": ["k%d" % KEY_T]}})
	check(InputGlyphs.label(&"attack_light") == "T", "rebind shows at once (%s)" % InputGlyphs.label(&"attack_light"))
	InputGlyphs.using_pad = true
	Settings.pad_glyphs = 1
	InputBindings.apply({"attack_light": {"pad": ["b3"]}})
	check(InputGlyphs.label(&"attack_light") == "Y", "pad rebind shows at once")


func test_labels_join() -> void:
	check(InputGlyphs.labels(&"jump", &"key") == "Space · K · Z", "keys joined (%s)" % InputGlyphs.labels(&"jump", &"key"))
	check(InputGlyphs.labels(&"jump", &"key", 2) == "Space · K", "max")
	Settings.pad_glyphs = 1
	check(InputGlyphs.labels(&"dodge", &"pad") == "B · RT", "pad events joined (%s)" % InputGlyphs.labels(&"dodge", &"pad"))
	check(InputGlyphs.labels(&"move_left", &"pad") == "Left stick · D-Pad Left", "the stick is listed (%s)" % InputGlyphs.labels(&"move_left", &"pad"))


func test_key_label_fallback_headless() -> void:
	check(InputGlyphs.key_label(KEY_SPACE) == "Space", "Space")
	check(InputGlyphs.key_label(KEY_Q) == "Q", "headless falls back to the QWERTY name")
	check(InputGlyphs.key_label(KEY_SHIFT) == "Shift", "modifier")
	InputGlyphs.using_pad = false
	var l := InputGlyphs.label(&"ui_accept")
	check(l == "Enter" or l == "Space", "M8 menu prompt unchanged (%s)" % l)
