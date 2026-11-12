extends SceneTree
const ARMY=[['guard','draugr',450.,1350.],['spear','skeleton_spearman',1050.,1350.],['legion','gravewalker',1650.,1350.],['archer','skeleton_archer',450.,1700.],['cavalry','death_rider',1050.,1700.],['legion','fell_hound',1650.,1700.]]
var checks=0
var failures=0
func check(ok:bool,note:String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func run():
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-undead-input.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	for language in ['zh','en']:
		app.language=language
		for row in ARMY:
			t.retry();t.refresh();var b=t.loadout_buttons[row[0]];var pos=b.position
			for i in t.rules.config.loadouts[row[0]].size():
				if t.rules.selected_variant(row[0])==row[1]:break
				b.pressed.emit()
			check(t.rules.selected_variant(row[0])==row[1] and b.position==pos and b.pressed.get_connections().size()==1,language+' '+row[1]+' real selector without duplicate callbacks or layout reset')
			await process_frame
			check(t.buttons[row[0]].get_combined_minimum_size().x<=148.,language+' '+row[1]+' reserve caption fits authored 148px width')
			var variant=t.rules.config.unit_variants[row[1]]
			check(t.buttons[row[0]].text.begins_with(variant.name_short if language=='zh' else variant.name_short_en),language+' '+row[1]+' localized reserve label')
			t.combined_button.pressed.emit();var units=t.rules.alive('ally').filter(func(u):return u.get('archetype','')==row[1])
			check(units.size()==1 and t.field.regiments.has(row[1]) and t.field.regiments[row[1]].values().all(func(tex):return tex!=null),row[1]+' deploys actual textures on both teams and petrification')
			t.start_button.pressed.emit();t.refresh();check(not b.visible,'Selector hides during battle')
			t.retry();check(t.rules.selected_variant(row[0])=='' and t.field.effects.is_empty(),'Retry restores default loadout and clears transient effects')
	var baseline={};var results=[]
	for fps in [30,60,120]:
		t.retry();var r=t.rules;r.units.clear()
		for side in ['ally','enemy']:
			for row in ARMY:r.spawn(row[0],side,Vector2(row[2],row[3] if side=='ally' else 2100.-row[3]),row[1])
		r.start();r.command(r.alive('ally').map(func(u):return u.id),'auto',Vector2.ZERO)
		var saw_arrows=false
		for frame in fps*150:
			t._process(1./fps);saw_arrows=saw_arrows or not r.volleys.is_empty()
			if r.phase!='battle':break
		check(r.phase in ['victory','defeat'],'Undead battle reaches result at '+str(fps)+' FPS')
		check(saw_arrows,'Skeleton bows take part in battle')
		var state={'time':snappedf(r.elapsed,.001),'phase':r.phase,'soldiers':r.units.map(func(u):return u.soldiers.map(func(a):return [snappedf(a.hp,.001),a.position.snapped(Vector2(.001,.001))]))}
		if baseline.is_empty():baseline=state
		else:check(state==baseline,'Undead final personal health, positions and outcome agree at '+str(fps)+' FPS')
		results.append({'fps':fps,'time':r.elapsed,'phase':r.phase,'alive_ally':r.strength('ally'),'alive_enemy':r.strength('enemy')})
	var output_directory_error=DirAccess.make_dir_recursive_absolute('res://../output/sword-banner-reference/undead-roster')
	assert(output_directory_error==OK)
	FileAccess.open('res://../output/sword-banner-reference/undead-roster/full-undead-battle.json',FileAccess.WRITE).store_string(JSON.stringify(results,'\t'))
	t.closed.emit();app.queue_free();await process_frame
	print('Undead roster input: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
