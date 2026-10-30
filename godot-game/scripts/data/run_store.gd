extends RefCounted
const C=preload('res://scripts/campaign.gd')
const E=preload('res://scripts/expedition.gd')
const VERSION=1

static func snapshot(c,e) -> Dictionary:
	var army=c.g.duplicate(true);var journey=e.state.duplicate(true)
	if army.phase=='battle':
		army.battle=null;army.phase='prepare';army.erase('expedition_wave')
		journey.target='';journey.mode='map'
	elif army.phase=='result':
		var clone=C.new(0)
		var route=E.new(clone);clone.g=army;route.configure_route(int(e.stage_order[0]));route.state=journey
		var won=army.battle.report.won
		route.settle()
		if not won:route.state.mode='camp'
		army=clone.g;journey=route.state
	# Materialize pending cards before writing, so reload never rerolls them.
	if army.phase=='reward':
		var clone=C.new(0);clone.g=army;clone.offers()
	return {'version':VERSION,'first_act':int(e.stage_order[0]),'campaign':army,'expedition':journey}

static func valid(data) -> bool:
	if not data is Dictionary or data.get('version')!=VERSION or data.get('first_act') not in [1,2,3] or not finite_values(data):return false
	var g=data.get('campaign');var e=data.get('expedition')
	if not g is Dictionary or not e is Dictionary:return false
	var c=C.new(0);var route=E.new(c)
	for key in c.g:
		if not g.has(key):return false
		if typeof(g[key])!=typeof(c.g[key]) and not ((g[key] is int or g[key] is float) and (c.g[key] is int or c.g[key] is float)):
			if key not in ['battle','pending','chosen']:return false
	for key in route.state:
		if not e.has(key) or typeof(e[key])!=typeof(route.state[key]):return false
	if g.phase not in ['prepare','reward','place','defeat'] or g.defense<0 or g.defense>3:return false
	if e.current not in route.nodes or (e.locked_target!='' and e.locked_target not in route.nodes):return false
	if e.target!='' and e.target not in route.nodes:return false
	for id in e.visited:
		if id not in route.nodes:return false
	var cells=[];var ids=[]
	for b in g.buildings:
		if not b is Dictionary or not b.has_all(['id','type','cell','level']):return false
		if not b.type is String or b.type not in c.types:return false
		if not whole(b.level,1,3) or not whole(b.cell,0,24) or not whole(b.id,1,1000000):return false
		if int(b.cell) not in g.unlocked_cells or b.cell in cells or b.id in ids:return false
		cells.append(b.cell);ids.append(b.id)
	for cell in g.unlocked_cells:
		if not whole(cell,0,24):return false
	for id in g.offered:
		if id not in c.cards:return false
	for id in g.upgrades:
		if id not in c.cards or not whole(g.upgrades[id],1,3):return false
	for id in g.temporary_orders:
		if id not in ['shield','testudo','rally']:return false
	if g.reward_context not in ['', 'elite','recovery'] or not whole(g.reward_rerolls,0,1):return false
	for id in g.orders:
		if id not in c.cards or c.cards[id].kind!='Battle order':return false
	for id in g.recovery_used:
		if id not in route.nodes:return false
	for id in g.boosts:
		if id not in ['legion','archer','siege'] or not whole(g.boosts[id],0,3):return false
	if g.phase=='defeat':
		if not g.battle is Dictionary or not g.battle.has_all(['units','report','time','events','projectiles']):return false
		if not g.battle.report is Dictionary or not g.battle.report.has_all(['won','surviving','deployed','enemyLosses','enemyCount']):return false
	elif g.battle!=null:return false
	if g.phase=='place' and g.pending not in c.types:return false
	return true

static func read_one(path: String) -> Dictionary:
	var file=ConfigFile.new()
	if file.load(path)!=OK:return {}
	var value=file.get_value('run','data',{})
	return value if valid(value) else {}

static func read_run(path: String) -> Dictionary:
	var value=read_one(path)
	return read_one(path+'.bak') if value.is_empty() else value

static func write_run(path: String,data: Dictionary) -> Error:
	if not valid(data):return ERR_INVALID_DATA
	var file=ConfigFile.new();file.set_value('run','data',data)
	var error=file.save(path+'.tmp')
	if error!=OK:return error
	# ConfigFile rounds rendered Vector2 values in the terminal battle report.
	if read_one(path+'.tmp').is_empty():return ERR_FILE_CORRUPT
	if not read_one(path).is_empty():
		error=DirAccess.copy_absolute(path,path+'.bak')
		if error!=OK:return error
	return DirAccess.rename_absolute(path+'.tmp',path)

static func finite_values(value) -> bool:
	if value is float:return is_finite(value)
	if value is Vector2:return value.is_finite()
	if value is Dictionary:
		for child in value.values():
			if not finite_values(child):return false
	elif value is Array:
		for child in value:
			if not finite_values(child):return false
	elif value is Object:return false
	return true

static func whole(value,low: int,high: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value==floor(value) and value>=low and value<=high
