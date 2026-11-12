extends SceneTree
const ARMY=[['legion','goblin_runt',220.,1350.],['legion','goblin_brat',630.,1350.],['spear','goblin_spiker',1040.,1350.],['guard','goblin_stabber',1450.,1350.],['guard','goblin_troll',1860.,1350.],['archer','goblin_archer',220.,1700.],['archer','goblin_slinger',630.,1700.],['cavalry','goblin_wolf_rider',1040.,1700.],['cavalry','goblin_wolf_skirmisher',1450.,1700.],['archer','goblin_shaman',1860.,1470.]]
var checks=0
var failures=0
func check(ok:bool,note:String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func run():
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-goblin-input.cfg';root.add_child(app)
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
	t.retry();t.rules.units.clear()
	for row in ARMY:t.rules.spawn(row[0],'ally',Vector2(row[2],row[3]),row[1])
	t.refresh();await process_frame;await process_frame
	var scroll: ScrollContainer=t.get_node('BattleHUD/RegimentRoster')
	check(scroll.get_global_rect().end.x<t.order_strip.get_global_rect().position.x,'Ten-regiment roster is clipped before order summary')
	check(t.roster[9].position.x>scroll.size.x,'Long roster actually exercises horizontal overflow')
	scroll.ensure_control_visible(t.roster[9]);await process_frame;await process_frame
	var last: Button=t.roster[9]
	check(scroll.get_global_rect().encloses(last.get_global_rect()),'Scrolling exposes full last regiment button')
	for down in [true,false]:
		var event=InputEventMouseButton.new();event.position=last.get_global_rect().get_center();event.global_position=event.position;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;root.push_input(event,true)
	check(t.rules.units[9].id in t.squad_ids,'Visible last regiment can be selected with actual mouse input')
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
		check(r.phase in ['victory','defeat'],'Goblin battle reaches result at '+str(fps)+' FPS')
		check(saw_arrows,'Goblin ranged units take part in battle')
		var state={'time':snappedf(r.elapsed,.001),'phase':r.phase,'soldiers':r.units.map(func(u):return u.soldiers.map(func(a):return [snappedf(a.hp,.001),a.position.snapped(Vector2(.001,.001))]))}
		if baseline.is_empty():baseline=state
		else:check(state==baseline,'Goblin final personal health, positions and outcome agree at '+str(fps)+' FPS')
		results.append({'fps':fps,'time':r.elapsed,'phase':r.phase,'alive_ally':r.strength('ally'),'alive_enemy':r.strength('enemy')})
	var output_directory_error=DirAccess.make_dir_recursive_absolute('res://../output/sword-banner-reference/goblin-roster')
	assert(output_directory_error==OK)
	FileAccess.open('res://../output/sword-banner-reference/goblin-roster/full-goblin-battle.json',FileAccess.WRITE).store_string(JSON.stringify(results,'\t'))
	t.closed.emit();app.queue_free();await process_frame
	print('Goblin roster input: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
