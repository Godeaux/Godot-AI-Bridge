## Reusable lightweight HTTP server base class for the AI bridge.
## Handles TCP connections, HTTP request parsing, routing, and response sending.
## Both the editor and runtime bridges extend this class.
class_name BridgeHTTPServer
extends Node

## Parsed HTTP request data.
class BridgeRequest:
	var method: String = ""
	var path: String = ""
	var query_params: Dictionary = {}
	var headers: Dictionary = {}
	var body: String = ""
	var json_body: Variant = null
	var raw_complete: bool = false

## Active client connection being accumulated.
class ClientConnection:
	var peer: StreamPeerTCP
	var buffer: PackedByteArray = PackedByteArray()
	var request: BridgeRequest = null
	var headers_parsed: bool = false
	var content_length: int = 0
	var header_end_index: int = -1
	var created_at: float = 0.0

	func _init(p_peer: StreamPeerTCP) -> void:
		peer = p_peer
		request = BridgeRequest.new()
		created_at = Time.get_ticks_msec() / 1000.0

var _tcp_server: TCPServer = null
var _routes: Dictionary = {}  # "METHOD /path" -> Callable
var _active_connections: Array[ClientConnection] = []
var _port: int = 0
const CONNECTION_TIMEOUT: float = 30.0

## Optional activity panel for logging requests. Set by the plugin.
var activity_panel: Node = null


## Start the HTTP server on the given port.
func start(port: int) -> Error:
	_port = port
	_tcp_server = TCPServer.new()
	var err: Error = _tcp_server.listen(port, BridgeConfig.LISTEN_HOST)
	if err != OK:
		push_error("BridgeHTTPServer: Failed to listen on port %d: %s" % [port, error_string(err)])
		_tcp_server = null
		return err
	print("BridgeHTTPServer: Listening on port %d" % port)
	return OK


## Stop the HTTP server and clean up connections.
func stop() -> void:
	if _tcp_server != null:
		_tcp_server.stop()
		_tcp_server = null
	for conn: ClientConnection in _active_connections:
		if conn.peer != null:
			conn.peer.disconnect_from_host()
	_active_connections.clear()
	print("BridgeHTTPServer: Stopped on port %d" % _port)


## Register a route handler. Method should be "GET" or "POST".
func register_route(method: String, path: String, handler: Callable) -> void:
	var key: String = "%s %s" % [method.to_upper(), path]
	_routes[key] = handler


## Process incoming connections and data each frame.
func _process(_delta: float) -> void:
	if _tcp_server == null:
		return
	if not _tcp_server.is_listening():
		return

	# Accept new connections
	while _tcp_server.is_connection_available():
		var peer: StreamPeerTCP = _tcp_server.take_connection()
		if peer != null:
			peer.set_no_delay(true)
			var conn := ClientConnection.new(peer)
			_active_connections.append(conn)

	# Process existing connections
	var to_remove: Array[int] = []
	var current_time: float = Time.get_ticks_msec() / 1000.0

	for i: int in range(_active_connections.size()):
		var conn: ClientConnection = _active_connections[i]

		# Check timeout
		if current_time - conn.created_at > CONNECTION_TIMEOUT:
			_close_connection(conn)
			to_remove.append(i)
			continue

		# Poll the peer to update its status
		conn.peer.poll()
		var status: StreamPeerTCP.Status = conn.peer.get_status()

		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			_close_connection(conn)
			to_remove.append(i)
			continue

		if status != StreamPeerTCP.STATUS_CONNECTED:
			continue

		# Read available data
		var available: int = conn.peer.get_available_bytes()
		if available > 0:
			var data: Array = conn.peer.get_data(available)
			if data[0] == OK and data[1] is PackedByteArray:
				conn.buffer.append_array(data[1])

		# Try to parse if we have data
		if conn.buffer.size() > 0 and not conn.request.raw_complete:
			_try_parse_request(conn)

		# If request is complete, handle it
		if conn.request.raw_complete:
			_handle_request(conn)
			to_remove.append(i)

	# Remove processed/dead connections in reverse order
	to_remove.reverse()
	for idx: int in to_remove:
		if idx < _active_connections.size():
			_active_connections.remove_at(idx)


## Try to parse headers and body from the connection buffer.
func _try_parse_request(conn: ClientConnection) -> void:
	var data_str: String = conn.buffer.get_string_from_utf8()

	# Look for header end
	if not conn.headers_parsed:
		var header_end: int = data_str.find("\r\n\r\n")
		if header_end == -1:
			return  # Headers not complete yet

		conn.header_end_index = header_end
		var header_section: String = data_str.substr(0, header_end)
		var lines: PackedStringArray = header_section.split("\r\n")

		if lines.size() == 0:
			conn.request.raw_complete = true
			return

		# Parse request line
		var request_line: String = lines[0]
		var parts: PackedStringArray = request_line.split(" ")
		if parts.size() < 2:
			conn.request.raw_complete = true
			return

		conn.request.method = parts[0].to_upper()
		var full_path: String = parts[1]

		# Parse query string
		var query_idx: int = full_path.find("?")
		if query_idx != -1:
			conn.request.path = full_path.substr(0, query_idx)
			var query_string: String = full_path.substr(query_idx + 1)
			conn.request.query_params = _parse_query_string(query_string)
		else:
			conn.request.path = full_path

		# Parse headers
		for j: int in range(1, lines.size()):
			var colon_idx: int = lines[j].find(":")
			if colon_idx != -1:
				var header_name: String = lines[j].substr(0, colon_idx).strip_edges().to_lower()
				var header_value: String = lines[j].substr(colon_idx + 1).strip_edges()
				conn.request.headers[header_name] = header_value

		# Get content length
		if conn.request.headers.has("content-length"):
			conn.content_length = int(conn.request.headers["content-length"])
		else:
			conn.content_length = 0

		conn.headers_parsed = true

	# Check if body is complete — use raw byte count, not string character count,
	# because Content-Length is in bytes and multi-byte UTF-8 chars would mismatch.
	if conn.headers_parsed:
		# Find the header/body boundary in the raw byte buffer
		var separator: PackedByteArray = "\r\n\r\n".to_utf8_buffer()
		var sep_pos: int = _find_bytes(conn.buffer, separator)
		if sep_pos == -1:
			return
		var body_byte_start: int = sep_pos + 4
		var body_byte_count: int = conn.buffer.size() - body_byte_start

		if body_byte_count >= conn.content_length:
			if conn.content_length > 0:
				var body_slice: PackedByteArray = conn.buffer.slice(body_byte_start, body_byte_start + conn.content_length)
				conn.request.body = body_slice.get_string_from_utf8()
				# Try to parse JSON body
				if conn.request.headers.get("content-type", "").find("application/json") != -1:
					var json := JSON.new()
					var parse_err: Error = json.parse(conn.request.body)
					if parse_err == OK:
						conn.request.json_body = json.data
			conn.request.raw_complete = true


## Parse a query string into a dictionary.
func _parse_query_string(query: String) -> Dictionary:
	var params: Dictionary = {}
	var pairs: PackedStringArray = query.split("&")
	for pair: String in pairs:
		var eq_idx: int = pair.find("=")
		if eq_idx != -1:
			var key: String = pair.substr(0, eq_idx).uri_decode()
			var val: String = pair.substr(eq_idx + 1).uri_decode()
			params[key] = val
		elif pair.length() > 0:
			params[pair.uri_decode()] = ""
	return params


## Handle a complete HTTP request by routing to the appropriate handler.
## Supports both synchronous and async (coroutine) handlers. When a handler
## uses `await` internally, this function suspends and sends the response
## once the handler completes. Called fire-and-forget from _process().
func _handle_request(conn: ClientConnection) -> void:
	var route_key: String = "%s %s" % [conn.request.method, conn.request.path]

	# Validate request was parsed correctly
	if conn.request.method == "" or conn.request.path == "":
		_log_activity("BAD", "???")
		_send_json_response(conn.peer, 400, {"error": "Malformed request"})
		_close_connection(conn)
		return

	# Reject POST requests with Content-Type: application/json but invalid JSON body
	if conn.request.method == "POST" and conn.request.body != "" and conn.request.json_body == null:
		if conn.request.headers.get("content-type", "").find("application/json") != -1:
			_log_activity(conn.request.method, conn.request.path, "invalid JSON body")
			_send_json_response(conn.peer, 400, {"error": "Invalid JSON in request body"})
			_close_connection(conn)
			return

	if _routes.has(route_key):
		var handler: Callable = _routes[route_key]
		# await works for both sync and async handlers:
		# - sync handlers return immediately with their value
		# - async handlers suspend until their internal awaits complete
		var result: Variant = await handler.call(conn.request)

		# Log to activity panel after handler completes, so we can
		# include the human-readable _description from the result.
		var summary: String = ""
		if result is Dictionary and result.has("_description"):
			summary = result["_description"]
		_log_activity(conn.request.method, conn.request.path, summary)

		if result is Dictionary or result is Array:
			_send_json_response(conn.peer, 200, result)
		elif result is String:
			_send_text_response(conn.peer, 200, result)
		elif result is PackedByteArray:
			_send_binary_response(conn.peer, 200, result, "application/octet-stream")
		elif result == null:
			_send_json_response(conn.peer, 200, {"ok": true})
		else:
			_send_json_response(conn.peer, 200, {"ok": true})
	else:
		_log_activity(conn.request.method, conn.request.path)
		_send_json_response(conn.peer, 404, {"error": "Not found", "path": conn.request.path, "method": conn.request.method})

	_close_connection(conn)


## Send a JSON response with appropriate headers.
func _send_json_response(peer: StreamPeerTCP, status_code: int, data: Variant) -> void:
	var json_str: String = JSON.stringify(data)
	var body_bytes: PackedByteArray = json_str.to_utf8_buffer()
	var status_text: String = _get_status_text(status_code)

	var header: String = "HTTP/1.1 %d %s\r\n" % [status_code, status_text]
	header += "Content-Type: application/json; charset=utf-8\r\n"
	header += "Content-Length: %d\r\n" % body_bytes.size()
	header += "Access-Control-Allow-Origin: *\r\n"
	header += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
	header += "Access-Control-Allow-Headers: Content-Type\r\n"
	header += "Connection: close\r\n"
	header += "\r\n"

	peer.put_data(header.to_utf8_buffer())
	peer.put_data(body_bytes)


## Send a plain text response.
func _send_text_response(peer: StreamPeerTCP, status_code: int, text: String) -> void:
	var body_bytes: PackedByteArray = text.to_utf8_buffer()
	var status_text: String = _get_status_text(status_code)

	var header: String = "HTTP/1.1 %d %s\r\n" % [status_code, status_text]
	header += "Content-Type: text/plain; charset=utf-8\r\n"
	header += "Content-Length: %d\r\n" % body_bytes.size()
	header += "Access-Control-Allow-Origin: *\r\n"
	header += "Connection: close\r\n"
	header += "\r\n"

	peer.put_data(header.to_utf8_buffer())
	peer.put_data(body_bytes)


## Send a binary response (e.g., raw PNG data).
func _send_binary_response(peer: StreamPeerTCP, status_code: int, data: PackedByteArray, content_type: String) -> void:
	var status_text: String = _get_status_text(status_code)

	var header: String = "HTTP/1.1 %d %s\r\n" % [status_code, status_text]
	header += "Content-Type: %s\r\n" % content_type
	header += "Content-Length: %d\r\n" % data.size()
	header += "Access-Control-Allow-Origin: *\r\n"
	header += "Connection: close\r\n"
	header += "\r\n"

	peer.put_data(header.to_utf8_buffer())
	peer.put_data(data)


## Send an error response as JSON.
func send_error(peer: StreamPeerTCP, status_code: int, message: String) -> void:
	_send_json_response(peer, status_code, {"error": message})


## Close a client connection.
func _close_connection(conn: ClientConnection) -> void:
	if conn.peer != null:
		conn.peer.disconnect_from_host()


## Log an incoming request to the activity panel (if attached).
func _log_activity(method: String, path: String, summary: String = "") -> void:
	if activity_panel != null and activity_panel.has_method("log_action"):
		activity_panel.log_action(method, path, summary)


## Find a byte sequence in a PackedByteArray. Returns index or -1.
func _find_bytes(haystack: PackedByteArray, needle: PackedByteArray) -> int:
	var h_size: int = haystack.size()
	var n_size: int = needle.size()
	if n_size == 0 or n_size > h_size:
		return -1
	for i: int in range(h_size - n_size + 1):
		var found: bool = true
		for j: int in range(n_size):
			if haystack[i + j] != needle[j]:
				found = false
				break
		if found:
			return i
	return -1


## Get HTTP status text for common codes.
func _get_status_text(code: int) -> String:
	match code:
		200: return "OK"
		201: return "Created"
		400: return "Bad Request"
		404: return "Not Found"
		500: return "Internal Server Error"
		_: return "Unknown"
