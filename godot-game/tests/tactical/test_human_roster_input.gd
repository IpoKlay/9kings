extends SceneTree
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func run():
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-human-input.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	for language in ['zh','en']:
		app.language=language;t.retry();t.refresh()
		for kind in t.loadout_buttons:
			var button: Button=t.loadout_buttons[kind];var original=button.position
			check(button.visible and button.pressed.get_connections().size()==1,language+' '+kind+' persistent selector has exactly one callback')
			var options: Array=t.rules.config.loadouts[kind]
			for i in options.size():
				button.pressed.emit()
				check(t.rules.selected_variant(kind)==options[(i+1)%options.size()],language+' '+kind+' cycles complete variant list')
				check(button.position==original,language+' '+kind+' refresh preserves authored position')
				check(t.buttons[kind].size.x<=152.,language+' '+kind+' compact reserve label stays within its button row')
		t.legion_variant_button.pressed.emit();t.guard_variant_button.pressed.emit();t.spear_variant_button.pressed.emit()
		t.archer_variant_button.pressed.emit();t.archer_variant_button.pressed.emit();t.cavalry_variant_button.pressed.emit();t.cavalry_variant_button.pressed.emit()
		t.combined_button.pressed.emit();var r=t.rules
		for name in ['peasant','heavy','veteran_spearman','crossbow','knight']:
			var units=r.alive('ally').filter(func(u):return u.get('archetype','')==name)
			check(units.size()==1 and t.field.regiments.has(name) and t.field.regiments[name].ally!=null,language+' '+name+' deploys with real imported sprite')
		t.start_button.pressed.emit();t.refresh();check(t.loadout_buttons.values().all(func(b):return not b.visible),'Deployment selectors hide during battle')
		var heavy=r.alive('ally').filter(func(u):return u.get('archetype','')=='heavy')[0]
		t.squad_ids=[heavy.id];t.soldier_ids=[];t.selected=''
		var e=InputEventKey.new();e.physical_keycode=KEY_F;e.pressed=true;root.push_input(e,true)
		check(t.selected!='shield_line','Whole-squad F refuses heavy infantry despite guard base slot')
		var crossbow=r.alive('ally').filter(func(u):return u.get('archetype','')=='crossbow')[0]
		t.squad_ids=[crossbow.id];t.refresh();check(not t.volley_button.visible,'Crossbow roster cannot expose longbow volley')
		t.retry();check(t.loadout_buttons.keys().all(func(k):return t.rules.selected_variant(k)==''),'Retry restores every default loadout')
	t.legion_variant_button.pressed.emit();t.legion_variant_button.pressed.emit();t.combined_button.pressed.emit()
	check(t.rules.alive('ally').any(func(u):return u.get('archetype','')=='noble_son'),'Noble sons are reachable through the same normal deployment controls')
	var baseline={};var results=[]
	var army=[['guard','heavy',450.,1350.],['spear','veteran_spearman',1050.,1350.],['legion','noble_son',1650.,1350.],['legion','peasant',450.,1700.],['archer','crossbow',1050.,1700.],['cavalry','knight',1650.,1700.]]
	for fps in [30,60,120]:
		t.retry();var r=t.rules;r.units.clear()
		for side in ['ally','enemy']:
			for row in army:r.spawn(row[0],side,Vector2(row[2],row[3] if side=='ally' else 2100.-row[3]),row[1])
		r.start();r.command(r.alive('ally').map(func(u):return u.id),'auto',Vector2.ZERO)
		var saw_bolts=false
		for frame in fps*150:
			t._process(1./fps);saw_bolts=saw_bolts or not r.volleys.is_empty()
			if r.phase!='battle':break
		check(r.phase in ['victory','defeat'],'Six-variant mirror battle reaches a real result at '+str(fps)+' FPS')
		check(saw_bolts,'Crossbow actually participates in the six-variant battle')
		var state={'time':snappedf(r.elapsed,.001),'phase':r.phase,'soldiers':r.units.map(func(u):return u.soldiers.map(func(a):return [snappedf(a.hp,.001),a.position.snapped(Vector2(.001,.001))]))}
		if baseline.is_empty():baseline=state
		else:check(state==baseline,'Six-variant result and positions agree at '+str(fps)+' FPS')
		results.append({'fps':fps,'time':r.elapsed,'phase':r.phase,'alive_ally':r.strength('ally'),'alive_enemy':r.strength('enemy')})
	FileAccess.open('res://../output/sword-banner-reference/human-roster/full-human-battle.json',FileAccess.WRITE).store_string(JSON.stringify(results,'\t'))
	t.closed.emit();app.queue_free();await process_frame
	print('Human roster input: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
