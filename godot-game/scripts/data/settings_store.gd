extends RefCounted
## Player preferences only. Never contains campaign, card or scenery definitions.
## Version 0 is the existing unversioned settings.cfg; its keys remain compatible.
const Catalog=preload('res://scripts/data/catalog.gd')
const DEFAULT_PATH='user://settings.cfg'
const FRAME_LIMITS=[30,60,120,0]

static func valid_frame_limit(value) -> bool:
	if not (value is int or value is float): return false
	for limit in FRAME_LIMITS:
		if float(value)==float(limit): return true
	return false

static func normalized(values: Dictionary) -> Dictionary:
	var result=Catalog.new_state('settings')
	for key in result:
		var value=values.get(key,result[key])
		match key:
			'language':
				if value is String and value in Catalog.data('schema/contracts').languages: result[key]=value
			'volume','voices','music_volume':
				if (value is float or value is int) and is_finite(float(value)): result[key]=clampf(float(value),0,1)
			'enabled','impact':
				if value is bool: result[key]=value
			'fps_limit':
				if valid_frame_limit(value): result[key]=int(value)
	return result

static func load_file(path: String) -> Dictionary:
	var config=ConfigFile.new()
	if config.load(path)!=OK or not config.has_section('settings'): return {}
	var version=config.get_value('metadata','version',0)
	if not (version is int or version is float) or version<0 or version>Catalog.data('schema/contracts').settings_version: return {}
	var values={}
	for key in config.get_section_keys('settings'): values[key]=config.get_value('settings',key)
	return normalized(values)

static func read_settings(path: String=DEFAULT_PATH) -> Dictionary:
	var values=load_file(path)
	if values.is_empty(): values=load_file(path+'.bak')
	return Catalog.new_state('settings') if values.is_empty() else values

static func write_settings(values: Dictionary,path: String=DEFAULT_PATH) -> Error:
	var config=ConfigFile.new()
	var clean=normalized(values)
	for key in clean: config.set_value('settings',key,clean[key])
	config.set_value('metadata','version',int(Catalog.data('schema/contracts').settings_version))
	var error=config.save(path+'.tmp')
	if error!=OK: return error
	if load_file(path+'.tmp')!=clean: return ERR_FILE_CORRUPT
	# Never replace the good backup with an unreadable primary file.
	if FileAccess.file_exists(path) and not load_file(path).is_empty():
		error=DirAccess.copy_absolute(path,path+'.bak')
		if error!=OK: return error
	error=DirAccess.rename_absolute(path+'.tmp',path)
	return error
