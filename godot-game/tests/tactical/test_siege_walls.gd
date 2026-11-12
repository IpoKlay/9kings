extends SceneTree
const Battle=preload('res://scripts/tactical/siege_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func run():
	var r=Battle.new();var wall=r.structures[3]
	var from=Vector2(1050,1300);var to=Vector2(1050,700)
	var u=r.alive('ally').filter(func(a):return a.kind=='legion')[0]
	var nav=r.Soldiers.navigator(r,u.kind,u)
	check(r.structures.size()==7,'Authored seven wall sections are loaded headlessly')
	check(r.terrain.leg(nav,from,to).is_empty(),'Intact wall closes the ground route')
	check(r.Structures.pick(r,Vector2(1050,830)).get('id','')==wall.id,'Visible upper wall face can be picked independently of ground collision')
	for i in 4:
		var shot={'pos':Vector2(1050,900),'side':'ally'}
		r.Structures.impact(r,shot);r.Structures.impact(r,shot)
		check(wall.hits==i+1,'Each stone counts exactly once')
		check(r.terrain.leg(nav,from,to).is_empty(),'Wall blocks through impact four')
	r.Structures.impact(r,{'pos':Vector2(1050,900),'side':'enemy'})
	check(wall.hits==4,'Friendly artillery does not breach its own wall')
	r.Structures.impact(r,{'pos':Vector2(1050,900),'side':'ally'})
	check(wall.hits==5 and r.terrain.clear_segment(nav,from,to),'Fifth stone opens the same visible footprint')
	check(not r.terrain.leg(nav,from,to).is_empty(),'New navigation uses the breach')
	check(r.structures[2].hits==0 and not r.terrain.clear_segment(nav,Vector2(750,1300),Vector2(750,700)),'Neighbouring sections remain intact and blocking')
	check(r.terrain.clear_segment('legion',from,to),'Already registered full-regiment clearance is rebuilt too')
	var fresh=Battle.new()
	check(fresh.structures.all(func(s):return s.hits==0),'New battle restores the authored wall states')
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-siege-test.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	check(t.siege_button.visible,'Normal main-menu battle exposes the persistent siege entry')
	t.siege_button.pressed.emit();check(t.rules is Battle and t.field.has_node('RomanSiege'),'Siege entry loads real rules and visible authored wall scene')
	r=t.rules;wall=r.structures[3]
	var engines=r.alive('ally').filter(func(a):return a.kind=='siege')[0]
	check(r.layout_valid({engines.id:engines.pos}),'Initial artillery placement belongs to the editable siege deployment zone')
	t.start_button.pressed.emit()
	t.squad_ids=[engines.id];t.selected=''
	var point=(r.projection*Vector2(1050,900)-t.camera_offset)*t.zoom
	var e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_RIGHT;e.pressed=true
	root.push_input(e,true)
	check(engines.soldiers.all(func(s):return s.get('personal_order','')=='bombard'),'Real right-click assigns every selected engine')
	t.paused=true
	for i in 60:t._process(1./60.)
	check(wall.hits==0 and r.stones.is_empty(),'Pause freezes windup and flight')
	t.paused=false
	var first_landing=-1.;var launched={};var breach=-1.
	for i in 1200:
		t._process(1./60.)
		for shot in r.stones:launched[shot.serial]=true
		t.field.effects.clear()
		if wall.hits>0 and first_landing<0:first_landing=r.elapsed
		if wall.hits==5:breach=r.elapsed;break
	check(launched.size()>=5 and first_landing>1.,'Real windup, release and existing projectile flight precede damage')
	check(breach>first_landing and wall.hits==5,'Natural artillery fire breaches after five actual landings')
	check(t.field.get_node('RomanSiege/Wall4').hits==5,'Runtime art shares the rules wall state')
	var infantry=r.alive('ally').filter(func(a):return a.kind=='legion')[0]
	check(r.Soldiers.command(r,r.Soldiers.group_members([infantry]),'move',Vector2(1050,770)), 'Infantry accept a normal movement order through the breached section')
	for i in 1200:
		t._process(1./60.)
		if infantry.soldiers.all(func(s):return s.position.y<860.):break
	check(infantry.soldiers.all(func(s):return s.position.y<860.),'Every living infantryman actually passes through the breach')
	t.retry();check(t.rules is Battle and t.rules.structures.all(func(s):return s.hits==0),'Retry retains siege mode and restores all walls')
	check(t.rules.stones.is_empty() and not t.rules.units.any(func(a):return a.soldiers.any(func(s):return s.get('personal_order','')=='bombard')),'Retry clears shells and bombard orders')
	print('Siege wall checks=',checks,' failures=',failures,' first_landing=',first_landing,' breach=',breach)
	var out='res://../output/sword-banner-reference/siege-walls/rules.json'
	var output_directory_error=DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	assert(output_directory_error==OK)
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify({'checks':checks,'failures':failures,'first_landing':first_landing,'breach':breach,'launches':launched.size()},'\t'))
	await app.prepare_shutdown()
	t.closed.emit();app.queue_free();await process_frame;quit(1 if failures else 0)
