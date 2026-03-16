extends Node

var _console: TextEdit = null

func set_label(console: TextEdit) -> void:
	_console = console

func log_msg(msg: String) -> void:
	var timestamp: String = "%.2f" % (Time.get_ticks_msec() * 0.001)
	var line: String = "[%s] %s\n" % [timestamp, msg]
	if _console == null:
		return
	_console.text += line
	# Scroll to bottom
	_console.scroll_vertical = _console.get_line_count()
