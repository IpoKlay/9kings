extends SceneTree
const Catalog=preload('res://scripts/data/catalog.gd')
const Settings=preload('res://scripts/data/settings_store.gd')
const Campaign=preload('res://scripts/campaign.gd')
const Expedition=preload('res://scripts/expedition.gd')
var checks=0
var failures=0
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func same(actual,expected,path: String):
	if actual is Dictionary and expected is Dictionary:
		check(actual.size()==expected.size(),path+' field count')
		for key in expected:
			check(actual.has(key),path+'/'+str(key)+' exists')
			if actual.has(key): same(actual[key],expected[key],path+'/'+str(key))
	elif actual is Array and expected is Array:
		check(actual.size()==expected.size(),path+' array length')
		for i in mini(actual.size(),expected.size()): same(actual[i],expected[i],path+'/'+str(i))
	else: check(actual==expected,path+' unchanged: '+str(actual)+' / '+str(expected))
func frozen(value,path: String):
	if value is Dictionary:
		check(value.is_read_only(),path+' immutable dictionary')
		for key in value: frozen(value[key],path+'/'+str(key))
	elif value is Array:
		check(value.is_read_only(),path+' immutable array')
		for i in value.size(): frozen(value[i],path+'/'+str(i))
func _init():
	var original=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/pre_migration_rules.json'))
	# Troop/card definitions intentionally changed with native three-level deployment.
	# Keep the migration baseline for untouched enemy/terrain data and unit base stats.
	same(Catalog.rules().enemies,original.enemies,'enemy rules')
	same(Catalog.rules().woodland,original.woodland,'woodland rules')
	for type in original.types:
		for key in original.types[type]:
			if key!='name':same(Catalog.rules().types[type][key],original.types[type][key],'base unit '+type+'/'+key)
	same(Catalog.expedition(),JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/pre_migration_expedition.json')),'expedition')
	frozen(Catalog.rules(),'rules');frozen(Catalog.expedition(),'expedition');frozen(Catalog.presentation('environment'),'environment')
	var a=Campaign.new(42);var b=Campaign.new(42)
	a.g.buildings[0].level=3;a.g.orders.rally=true;a.offers()
	check(b.g.buildings[0].level==1 and b.g.orders.is_empty() and b.g.offered.is_empty(),'Independent nested run state')
	check(Catalog.data('defaults/campaign').buildings[0].level==1,'Runtime did not change defaults')
	var e1=Expedition.new(a);var e2=Expedition.new(b)
	e1.reset(3);check(e2.stage_order==[1,2,3],'Independent route configurations')
	check(e1.original_data.final=='727070','Route permutation did not mutate content')
	# Simulate a future designer edit in memory, without writing production data.
	var saved_cache=Catalog._cache.duplicate()
	var changed=Catalog.data('balance/effects').duplicate(true)
	changed.shield.amount=73
	Catalog._cache['balance/effects']=Catalog.freeze(changed)
	Catalog._cache.erase('resolved/rules')
	var edited=Campaign.new(42)
	edited.g.armyShield=true
	check(edited.muster()[0].shield==73,'One edited effect feeds actual combat')
	check(edited.cards.shield.text.contains('73 shield') and edited.cards.shield.impact=='+73','Same value feeds card explanation and badge')
	check(edited.rules.zh[edited.cards.shield.text].contains('73点护盾'),'Same value feeds Chinese explanation')
	check(a.effects.shield.amount==40,'Existing run retains immutable definitions')
	Catalog._cache=saved_cache.duplicate()
	var validator=preload('res://scripts/data/validator.gd').new()
	changed=Catalog.data('balance/combat').duplicate(true)
	changed.survivor_heal_fraction=1.5
	Catalog._cache['balance/combat']=Catalog.freeze(changed)
	check(not validator.validate().is_empty(),'Invalid recovery percentage rejected')
	Catalog._cache=saved_cache.duplicate()
	check(validator.validate().is_empty(),'Production catalog restored after negative test')
	var path='res://../output/data-organization/test-settings.cfg'
	for suffix in ['','.bak','.tmp']:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	check(Settings.read_settings(path)==Catalog.new_state('settings'),'Missing file uses defaults')
	var legacy=ConfigFile.new()
	legacy.set_value('settings','language','en');legacy.set_value('settings','volume',.37);legacy.set_value('settings','enabled',false)
	legacy.save(path)
	var loaded=Settings.read_settings(path)
	check(loaded.language=='en' and loaded.volume==.37 and not loaded.enabled and loaded.voices==.55,'Old unversioned preferences preserved')
	loaded.volume=.63
	check(Settings.write_settings(loaded,path)==OK,'Settings saved')
	check(Settings.read_settings(path)==loaded,'Settings round trip')
	check(Settings.load_file(path+'.bak').volume==.37,'Previous valid settings backed up')
	var corrupt=FileAccess.open(path,FileAccess.WRITE);corrupt.store_string('[broken');corrupt.close()
	check(Settings.read_settings(path).volume==.37,'Corrupt primary recovers backup')
	check(Settings.write_settings(loaded,path)==OK and Settings.load_file(path+'.bak').volume==.37,'Corruption cannot replace good backup')
	var invalid=Settings.normalized({'language':'xx','enabled':'false','volume':INF,'voices':-5,'impact':[]})
	check(invalid.language=='zh' and invalid.enabled==true and invalid.volume==.7 and invalid.voices==0 and invalid.impact==true,'Invalid preference types/ranges safe')
	legacy.clear();legacy.set_value('metadata','version',999);legacy.set_value('settings','volume',.9);legacy.save(path)
	check(Settings.read_settings(path).volume==.37,'Unknown future settings version does not load as current')
	for suffix in ['','.bak','.tmp']:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print('%d data-layer checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
