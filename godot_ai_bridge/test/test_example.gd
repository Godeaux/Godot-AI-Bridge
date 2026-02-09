extends GdUnitTestSuite

func test_config_ports() -> void:
	var config = preload("res://addons/godot_ai_bridge/shared/config.gd")
	assert_int(config.EDITOR_PORT).is_equal(9899)
	assert_int(config.RUNTIME_PORT).is_equal(9900)

func test_config_host() -> void:
	var config = preload("res://addons/godot_ai_bridge/shared/config.gd")
	assert_str(config.EDITOR_HOST).is_equal("127.0.0.1")
