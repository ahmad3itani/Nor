class_name LocFields
extends RefCounted
## The LOC_FIELDS protocol (M9 D5 §4.1). A Resource or Node script with
## player-visible text declares, next to its exports:
##
##   const LOC_FIELDS := {"text": 120}    # field -> max source chars (0 = none)
##   const LOC_EXEMPT := ["label"]         # text-like fields that are not shown
##   const LOC_CONTEXT := {"verb": "verb"} # optional msgctxt per field
##
## Godot 4.3 refuses a constant a base script already declares ("member
## already exists in parent class"), so each name appears once per script
## chain; a subclass adds fields to a base that has LOC_FIELDS through
## `const LOC_FIELDS_EXTRA := {...}`. All of them merge up the chain.
##
## Source text stays English in the data; Loc translates at display. This
## class reads the declarations up the script inheritance chain and walks a
## Resource (sub-resources included) or a scene's SceneState into catalog
## entries, generically, so no content type needs extractor code of its own.
## Shared by the extractor, the StringRules lints and the tests.

## Engine controls whose text is shown as-is (decor Labels in room scenes).
const ENGINE_FIELDS := {"Label": {"text": 0}, "Button": {"text": 0}, "RichTextLabel": {"text": 0}}
## Properties never walked: engine plumbing, not content.
const SKIP_PROPS := ["script", "resource_path", "resource_name", "resource_local_to_scene", "metadata/_custom_type_script"]


## LOC_FIELDS merged up the base-script chain (a subclass overrides its base).
static func fields_for(script: Script) -> Dictionary:
	var out := _merged(script, "LOC_FIELDS")
	out.merge(_merged(script, "LOC_FIELDS_EXTRA"), true)
	return out


static func context_for(script: Script) -> Dictionary:
	return _merged(script, "LOC_CONTEXT")


static func exempt_for(script: Script) -> PackedStringArray:
	var out := PackedStringArray()
	var s := script
	while s != null:
		for f in s.get_script_constant_map().get("LOC_EXEMPT", []):
			if not out.has(str(f)):
				out.append(str(f))
		s = s.get_base_script()
	return out


static func _merged(script: Script, const_name: String) -> Dictionary:
	var chain: Array[Script] = []
	var s := script
	while s != null:
		chain.push_front(s)
		s = s.get_base_script()
	var out := {}
	for c in chain:
		var d: Variant = c.get_script_constant_map().get(const_name, {})
		if d is Dictionary:
			out.merge(d, true)
	return out


## L-2: exported text-like properties (String, PackedStringArray, Array of
## String, Dictionary) whose name matches the config pattern but that neither
## LOC_FIELDS nor LOC_EXEMPT mentions. A new content type must say what the
## player sees.
static func unclassified(script: Script, pattern: RegEx) -> PackedStringArray:
	var out := PackedStringArray()
	if script == null or pattern == null:
		return out
	var fields := fields_for(script)
	var exempt := exempt_for(script)
	for p in script.get_script_property_list():
		var usage := int(p.get("usage", 0))
		if (usage & PROPERTY_USAGE_EDITOR) == 0 or (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n := str(p["name"])
		if not _text_like(p) or pattern.search(n) == null:
			continue
		if not fields.has(n) and not exempt.has(n) and not out.has(n):
			out.append(n)
	return out


static func _text_like(p: Dictionary) -> bool:
	match int(p.get("type", TYPE_NIL)):
		TYPE_STRING, TYPE_PACKED_STRING_ARRAY, TYPE_DICTIONARY:
			return true
		TYPE_ARRAY:
			var h := str(p.get("hint_string", ""))
			return int(p.get("hint", 0)) == PROPERTY_HINT_ARRAY_TYPE and (h == "String" or h.begins_with("%d:" % TYPE_STRING))
	return false


## One catalog location. `out` maps CatalogEntry.id() -> CatalogEntry, and
## out["__seq"] counts insertions for the stable catalog order.
static func add(out: Dictionary, msgid: String, ctx: String, ref: String, key: String, max_len: int, note: String,
		plural: String = "") -> void:
	if msgid == "":
		return
	var id := CatalogEntry.key_of(ctx, msgid)
	var e: CatalogEntry = out.get(id)
	if e == null:
		e = CatalogEntry.new()
		e.ctx = ctx
		e.msgid = msgid
		out[id] = e
	if plural != "" and e.msgid_plural == "":
		e.msgid_plural = plural
	var seq := int(out.get("__seq", 0))
	out["__seq"] = seq + 1
	e.add_location(ref, key, max_len, note, seq)


## Every value of one declared field as [location suffix, text] pairs:
## a String, each array element (field[i]) or each Dictionary value (field[key]).
static func values_of(field: String, v: Variant) -> Array:
	var out: Array = []
	if v is String or v is StringName:
		out.append([field, str(v)])
	elif v is PackedStringArray or v is Array:
		var arr: Array = v if v is Array else Array(v as PackedStringArray)
		for i in arr.size():
			var item: Variant = arr[i]
			if item is String or item is StringName:
				out.append(["%s[%d]" % [field, i], str(item)])
	elif v is Dictionary:
		var keys: Array = (v as Dictionary).keys()
		for k: Variant in keys:
			var item: Variant = v[k]
			if item is String or item is StringName:
				out.append(["%s[%s]" % [field, str(k)], str(item)])
	return out


## Short description for translators: the class, and the speaker of a line.
static func note_for(obj: Object, script: Script) -> String:
	var parts := PackedStringArray()
	parts.append(class_label(script, obj.get_class() if obj else ""))
	for sp in ["speaker_id", "speaker"]:
		if obj != null and sp in obj:
			var who := str(obj.get(sp))
			if who != "":
				parts.append("speaker: " + who)
				break
	return " · ".join(parts)


## The script's file name (every class_name script is named after its class),
## else the engine class.
static func class_label(script: Script, fallback: String) -> String:
	return script.resource_path.get_file().get_basename() if script and script.resource_path != "" else fallback


## Walks a Resource and its built-in sub-resources (arrays and dictionaries
## of them too) for declared fields. `rel` is the file path without res://,
## `prefix` the location of `res` inside that file. External resources are
## not followed: they are extracted from their own file.
static func walk(res: Resource, rel: String, out: Dictionary, prefix: String = "", visited: Dictionary = {}) -> void:
	if res == null or visited.has(res.get_instance_id()):
		return
	visited[res.get_instance_id()] = true
	var script := res.get_script() as Script
	if script != null:
		var fields := fields_for(script)
		var ctxs := context_for(script)
		var note := note_for(res, script)
		for field: String in fields:
			if not field in res:
				continue
			for pair: Array in values_of(field, res.get(field)):
				var key := "%s::%s%s" % [rel, prefix, pair[0]]
				add(out, str(pair[1]), str(ctxs.get(field, "")), rel, key, int(fields[field]), note)
	for p in res.get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_STORAGE) == 0 or SKIP_PROPS.has(str(p["name"])):
			continue
		var n := str(p["name"])
		var v: Variant = res.get(n)
		if v is Resource:
			if _is_embedded(v, rel):
				walk(v, rel, out, "%s%s." % [prefix, n], visited)
		elif v is Array:
			for i in (v as Array).size():
				var item: Variant = v[i]
				if item is Resource and _is_embedded(item, rel):
					walk(item, rel, out, "%s%s[%d]." % [prefix, n, i], visited)
		elif v is Dictionary:
			for k: Variant in (v as Dictionary).keys():
				var item: Variant = v[k]
				if item is Resource and _is_embedded(item, rel):
					walk(item, rel, out, "%s%s[%s]." % [prefix, n, str(k)], visited)


## Built-in (sub-)resources and in-memory ones belong to the file being walked.
static func _is_embedded(r: Resource, _rel: String) -> bool:
	if r.get_script() == null:
		return false
	var p := r.resource_path
	return p == "" or p.contains("::")


## A node's declared fields: its script's LOC_FIELDS plus the engine fields
## of its native class (a scripted Label still shows its text).
static func node_fields(script: Script, type: String) -> Dictionary:
	var out := {}
	var native := type
	if script != null:
		native = String(script.get_instance_base_type())
	for cls: String in ENGINE_FIELDS:
		if native != "" and ClassDB.is_parent_class(native, cls):
			out.merge(ENGINE_FIELDS[cls], true)
	if script != null:
		out.merge(fields_for(script), true)
		for ex in exempt_for(script):
			out.erase(ex)
	return out


## Values a scene sets on its nodes, read from the SceneState without
## instancing (no _ready side effects). Only properties the scene itself
## sets are extracted here; script defaults come from script_defaults().
## Returns the scripts it met, for their defaults.
static func walk_scene(state: SceneState, rel: String, out: Dictionary) -> Array[Script]:
	var scripts: Array[Script] = []
	for i in state.get_node_count():
		var script: Script = null
		var type := String(state.get_node_type(i))
		var props := {}
		for j in state.get_node_property_count(i):
			props[String(state.get_node_property_name(i, j))] = state.get_node_property_value(i, j)
		if props.get("script") is Script:
			script = props["script"]
		if script == null and type == "":
			# An instanced scene: its root decides the class.
			var inst := state.get_node_instance(i)
			if inst != null:
				var root := inst.get_state()
				type = String(root.get_node_type(0))
				for j in root.get_node_property_count(0):
					if String(root.get_node_property_name(0, j)) == "script":
						script = root.get_node_property_value(0, j) as Script
		if script != null and not scripts.has(script):
			scripts.append(script)
		var fields := node_fields(script, type)
		if fields.is_empty():
			continue
		var ctxs := context_for(script) if script else {}
		var node_path := String(state.get_node_path(i)).trim_prefix("./")
		var note := class_label(script, type)
		for field: String in fields:
			if not props.has(field):
				continue
			for pair: Array in values_of(field, props[field]):
				add(out, str(pair[1]), str(ctxs.get(field, "")), rel, "%s::%s.%s" % [rel, node_path, pair[0]],
					int(fields[field]), note)
		# Sub-resources a node holds (e.g. an exported data resource built in).
		for pn: String in props:
			var v: Variant = props[pn]
			if v is Resource and pn != "script" and _is_embedded(v, rel):
				walk(v, rel, out, "%s.%s." % [String(state.get_node_path(i)).trim_prefix("./"), pn])
	return scripts


## Default values of a Node script's declared fields, located at the script
## (a default no scene overrides is still shown, e.g. FlowZone's hint).
static func script_defaults(script: Script, out: Dictionary) -> void:
	if script == null or not ClassDB.is_parent_class(String(script.get_instance_base_type()), "Node"):
		return
	var fields := fields_for(script)
	if fields.is_empty():
		return
	var rel := script.resource_path.trim_prefix("res://")
	var ctxs := context_for(script)
	var note := class_label(script, "")
	# Script.get_property_default_value only answers inside the editor, so
	# read the defaults off a bare instance: _init runs, never _ready (the
	# node is not added to a tree).
	if not script.can_instantiate():
		return
	var probe: Object = script.new()
	for field: String in fields:
		if not field in probe:
			continue
		for pair: Array in values_of(field, probe.get(field)):
			add(out, str(pair[1]), str(ctxs.get(field, "")), rel, "%s::%s" % [rel, pair[0]], int(fields[field]), note)
	if probe is Node:
		(probe as Node).free()
