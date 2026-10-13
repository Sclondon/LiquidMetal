extends RefCounted
## Dev flags from the command line (`-- --server=http://127.0.0.1:3111`) or the page URL
## (`?server=...`). Values are strings; a bare flag is "1".
##   server=<url>   use this rooms server for co-op instead of the live site's

static var _flags := {}
static var _read := false


static func all() -> Dictionary:
	if _read:
		return _flags
	_read = true
	var parts: Array = []
	for arg in OS.get_cmdline_user_args():
		parts.append(arg.trim_prefix("--"))
	if OS.has_feature("web"):
		var query: Variant = JavaScriptBridge.eval("location.search")
		if query is String and query.length() > 1:
			parts.append_array(query.substr(1).split("&"))
	for part: String in parts:
		var pair := part.split("=", true, 1)
		_flags[pair[0]] = pair[1].uri_decode() if pair.size() > 1 else "1"
	return _flags


static func value(flag: String, fallback := "") -> String:
	return str(all().get(flag, fallback))
