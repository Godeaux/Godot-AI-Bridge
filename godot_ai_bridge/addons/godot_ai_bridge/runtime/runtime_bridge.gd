## Runtime bridge autoload — activates inside the running game.
## Starts an HTTP server on port 9900 that exposes game interaction endpoints.
extends BridgeHTTPServer

var _routes_handler: RuntimeRoutes


func _ready() -> void:
	# Only activate in debug builds
	if not OS.is_debug_build():
		queue_free()
		return

	_routes_handler = RuntimeRoutes.new(get_tree())

	# Register all runtime routes
	register_route("GET", "/snapshot", _on_snapshot)
	register_route("GET", "/screenshot", _on_screenshot)
	register_route("GET", "/screenshot/node", _on_screenshot_node)
	register_route("POST", "/click", _on_click)
	register_route("POST", "/click_node", _on_click_node)
	register_route("POST", "/key", _on_key)
	register_route("POST", "/action", _on_action)
	register_route("GET", "/actions", _on_actions)
	register_route("POST", "/mouse_move", _on_mouse_move)
	register_route("POST", "/sequence", _on_sequence)
	register_route("GET", "/state", _on_state)
	register_route("POST", "/call_method", _on_call_method)
	register_route("POST", "/wait", _on_wait)
	register_route("POST", "/wait_for", _on_wait_for)
	register_route("GET", "/info", _on_info)

	var err: Error = start(BridgeConfig.RUNTIME_PORT)
	if err == OK:
		print("[Godot AI Bridge] Runtime bridge listening on port %d" % BridgeConfig.RUNTIME_PORT)
	else:
		push_error("[Godot AI Bridge] Failed to start runtime bridge on port %d" % BridgeConfig.RUNTIME_PORT)


func _exit_tree() -> void:
	stop()


# Route handler wrappers — delegate to RuntimeRoutes

func _on_snapshot(request: BridgeHTTPServer.HTTPRequest) -> Variant:
	return await _routes_handler.handle_snapshot(request)

func _on_screenshot(request: BridgeHTTPServer.HTTPRequest) -> Variant:
	return await _routes_handler.handle_screenshot(request)

func _on_screenshot_node(request: BridgeHTTPServer.HTTPRequest) -> Variant:
	return await _routes_handler.handle_screenshot_node(request)

func _on_click(request: BridgeHTTPServer.HTTPRequest) -> Variant:
	return await _routes_handler.handle_click(request)

func _on_click_node(request: BridgeHTTPServer.HTTPRequest) -> Variant:
	return await _routes_handler.handle_click_node(request)

func _on_key(request: BridgeHTTPServer.HTTPRequest) -> Variant:
	return await _routes_handler.handle_key(request)

func _on_action(request: BridgeHTTPServer.HTTPRequest) -> Variant:
	return await _routes_handler.handle_action(request)

func _on_actions(request: BridgeHTTPServer.HTTPRequest) -> Variant:
	return _routes_handler.handle_actions(request)

func _on_mouse_move(request: BridgeHTTPServer.HTTPRequest) -> Variant:
	return _routes_handler.handle_mouse_move(request)

func _on_sequence(request: BridgeHTTPServer.HTTPRequest) -> Variant:
	return await _routes_handler.handle_sequence(request)

func _on_state(request: BridgeHTTPServer.HTTPRequest) -> Variant:
	return _routes_handler.handle_state(request)

func _on_call_method(request: BridgeHTTPServer.HTTPRequest) -> Variant:
	return _routes_handler.handle_call_method(request)

func _on_wait(request: BridgeHTTPServer.HTTPRequest) -> Variant:
	return await _routes_handler.handle_wait(request)

func _on_wait_for(request: BridgeHTTPServer.HTTPRequest) -> Variant:
	return await _routes_handler.handle_wait_for(request)

func _on_info(request: BridgeHTTPServer.HTTPRequest) -> Variant:
	return _routes_handler.handle_info(request)
