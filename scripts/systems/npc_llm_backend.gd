class_name NpcLlmBackend
extends Node
## Optional live brain for persona shells.
##
## Configuration is environment-only, so no key ever lands in the repo:
##   AI_NPC_PROVIDER  "ollama" | "openai"   (unset / anything else = OFFLINE)
##   AI_NPC_BASE_URL  endpoint (defaults below)
##   AI_NPC_MODEL     model name
##   AI_NPC_API_KEY   required for "openai"-compatible providers
##
## Defaults target Ollama on localhost — free, open-source, offline-friendly.
## "openai" covers OpenRouter / Groq / llama.cpp server, all of which expose
## the same /chat/completions shape; free-tier models work fine for two
## sentences of noir.
##
## Every failure path (no key, connection refused, timeout, junk JSON) resolves
## to an empty string, and PersonaShell falls back to its offline kernel.

signal request_finished(success: bool)

enum Provider { OFFLINE, OLLAMA, OPENAI_COMPATIBLE }

const DEFAULT_OLLAMA_URL := "http://127.0.0.1:11434/api/generate"
const DEFAULT_OLLAMA_MODEL := "llama3.2:3b"
const DEFAULT_OPENAI_URL := "https://openrouter.ai/api/v1/chat/completions"
const DEFAULT_OPENAI_MODEL := "meta-llama/llama-3.2-3b-instruct:free"
const REQUEST_TIMEOUT := 9.0

var provider: Provider = Provider.OFFLINE
var model: String = ""
var base_url: String = ""

var _api_key: String = ""
var _http: HTTPRequest
var _timer: Timer
var _busy: bool = false
var _callback: Callable


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_timer = Timer.new()
	_timer.one_shot = true
	add_child(_timer)
	_timer.timeout.connect(_on_timeout)
	_configure_from_env()


func _configure_from_env() -> void:
	match OS.get_environment("AI_NPC_PROVIDER").to_lower():
		"ollama":
			provider = Provider.OLLAMA
			base_url = _env_or("AI_NPC_BASE_URL", DEFAULT_OLLAMA_URL)
			model = _env_or("AI_NPC_MODEL", DEFAULT_OLLAMA_MODEL)
		"openai", "openrouter", "groq":
			provider = Provider.OPENAI_COMPATIBLE
			base_url = _env_or("AI_NPC_BASE_URL", DEFAULT_OPENAI_URL)
			model = _env_or("AI_NPC_MODEL", DEFAULT_OPENAI_MODEL)
			_api_key = OS.get_environment("AI_NPC_API_KEY")
			if _api_key.is_empty():
				push_warning("[NpcLlmBackend] openai provider set but AI_NPC_API_KEY is empty; offline")
				provider = Provider.OFFLINE
		_:
			provider = Provider.OFFLINE

	if provider != Provider.OFFLINE:
		print("[NpcLlmBackend] provider=%s model=%s" % [
			Provider.keys()[provider], model,
		])


func _env_or(key: String, fallback: String) -> String:
	var value := OS.get_environment(key)
	return value if not value.is_empty() else fallback


func is_active() -> bool:
	return provider != Provider.OFFLINE


func is_busy() -> bool:
	return _busy


## Ask for one short reply. Exactly one request may be in flight; a second
## caller gets an immediate empty response so shells fall back to the kernel.
func request_completion(system_prompt: String, user_prompt: String, callback: Callable) -> void:
	if not is_active() or _busy:
		callback.call_deferred("")
		return

	_busy = true
	_callback = callback

	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := ""
	if provider == Provider.OLLAMA:
		body = JSON.stringify({
			"model": model,
			"system": system_prompt,
			"prompt": user_prompt,
			"stream": false,
			"options": {"temperature": 0.7, "num_predict": 90},
		})
	else:
		headers.append("Authorization: Bearer %s" % _api_key)
		body = JSON.stringify({
			"model": model,
			"messages": [
				{"role": "system", "content": system_prompt},
				{"role": "user", "content": user_prompt},
			],
			"max_tokens": 90,
			"temperature": 0.7,
		})

	var err := _http.request(base_url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_finish("")
		return
	_timer.start(REQUEST_TIMEOUT)


func _on_request_completed(
	_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if not _busy:
		return
	_timer.stop()
	if response_code != 200:
		push_warning("[NpcLlmBackend] HTTP %d" % response_code)
		_finish("")
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		_finish("")
		return
	var data: Dictionary = parsed

	var text := ""
	if provider == Provider.OLLAMA:
		text = str(data.get("response", ""))
	else:
		var choices: Variant = data.get("choices", [])
		if choices is Array and not choices.is_empty():
			var message: Variant = choices[0].get("message", {})
			if message is Dictionary:
				text = str(message.get("content", ""))
	_finish(text)


func _on_timeout() -> void:
	if _busy:
		push_warning("[NpcLlmBackend] request timed out")
		_http.cancel_request()
		_finish("")


func _finish(text: String) -> void:
	_busy = false
	request_finished.emit(not text.is_empty())
	var callback := _callback
	_callback = Callable()
	if callback.is_valid():
		callback.call(text)
