extends RefCounted
## Immutable authored data. Gameplay instances receive separate mutable state.
static var _cache: Dictionary={}
static var _manifest: Dictionary={}
static func freeze(value):
	if value is Dictionary:
		for child in value.values(): freeze(child)
		value.make_read_only()
	elif value is Array:
		for child in value: freeze(child)
		value.make_read_only()
	return value
static func data(id: String):
	if _manifest.is_empty():
		_manifest=JSON.parse_string(FileAccess.get_file_as_string('res://data/manifest.json'))
	if not _cache.has(id):
		assert(_manifest.json.has(id),'Unknown data category: '+id)
		var value=JSON.parse_string(FileAccess.get_file_as_string(_manifest.json[id]))
		assert(value!=null,'Invalid data: '+id)
		_cache[id]=freeze(value)
	return _cache[id]
static func new_state(id: String) -> Dictionary:
	return data('defaults/'+id).duplicate(true)
static func rules() -> Dictionary:
	if _cache.has('resolved/rules'): return _cache['resolved/rules']
	var cards: Dictionary=data('balance/cards').duplicate(true)
	var translated={}
	for key in data('localization/legacy_zh'):
		translated[format_text(key)]=format_text(data('localization/legacy_zh')[key])
	for id in cards:
		var copy=data('localization/cards')[id]
		for field in copy.en:
			var english=format_text(copy.en[field])
			cards[id][field]=english
			if copy.zh.has(field): translated[english]=format_text(copy.zh[field])
	_cache['resolved/rules']=freeze({'types':data('balance/units'),'cards':cards,'enemies':data('balance/enemies'),'zh':translated,'woodland':data('sources/legacy_woodland')})
	return _cache['resolved/rules']
static func expedition() -> Dictionary:
	var value: Dictionary=data('content/routes').duplicate(true)
	value.acts=data('content/theaters')
	value.nodes=data('content/locations')
	return freeze(value)
static func presentation(id: String) -> Dictionary:
	var key='presentation/'+id
	if not _cache.has(key):
		var resource=load('res://data/presentation/'+id+'.tres')
		assert(resource!=null,'Missing presentation preset '+id)
		_cache[key]=freeze(resource.values.duplicate(true))
	return _cache[key]

static func resolve_value(path: String):
	var parts=path.split('#')
	var value=data(parts[0])
	for field in parts[1].split('.'): value=value[field]
	return value

static func binding_value(id: String) -> String:
	var binding=data('localization/bindings')[id]
	var values: Array=[]
	for source in binding.sources: values.append(resolve_value(source))
	var value=float(values[0])
	match binding.operation:
		'percent': value*=100
		'bonus_percent': value=(value-1)*100
		'reduction_percent': value=(1-value)*100
		'sum_bonus_percent': value=(value+float(values[1])-1)*100
		'product_percent': value=value*float(values[1])*100
		'roman': return ['','I','II','III'][int(value)]
		'chinese': return ['零','一','两','三','四','五','六','七','八','九','十'][int(value)] if value<=10 else str(int(value))
		'english': return ['zero','one','two','three','four','five','six','seven','eight','nine','ten'][int(value)] if value<=10 else str(int(value))
	value=snappedf(value,.000001)
	return str(roundi(value)) if is_equal_approx(value,roundf(value)) else str(value)

static func format_text(template: String) -> String:
	var result=template
	for key in data('localization/bindings'):
		if result.contains('{'+key+'}'): result=result.replace('{'+key+'}',binding_value(key))
	return result

static func text(id: String,language: String) -> String:
	var entry=data('localization/interface')[id]
	return format_text(entry[language])
