extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var errors=0
var checks=0
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	checks+=1
	if not ok:errors+=1;push_error(note)

func run():
	var main=load('res://scenes/main.tscn').instantiate()
	main.settings_path='/tmp/eagle-square-prefs.cfg'
	root.add_child(main)
	main.menu_view.get_node('%TacticalTrial').pressed.emit()
	var t=main.active_trial
	t.set_process(false)
	# Legacy authored-map fixture; default menu coverage lives in test_whiteboard_battle.gd.
	t.rules=t.SquareBattle.new();t.field.load_battlefield();t.reset_camera()
	var r=t.rules
	check(r is Battle,'Legacy fixture uses square battlefield')
	check(r.bounds.size==Vector2(2100,2100),'True square world')
	check(r.enemy_zone.size==r.neutral_zone.size and r.deployment.size==r.neutral_zone.size,'Three equal thirds')
	check(r.alive('enemy').size()==7 and r.alive('ally').is_empty(),'Enemy awaits deployment')
	check(not r.deploy('legion',Vector2(1000,1100)) and not r.deploy('legion',Vector2(1000,400)),'Enemy and neutral zones reject deployment')
	t.combined_button.pressed.emit()
	check(r.alive('ally').size()==7,'Seven arms deployed through UI')
	for u in r.units:
		check((r.enemy_zone if u.side=='enemy' else r.deployment).has_point(u.pos),'Squad in own third')
		var hp: float=u.hp
		for bearing in 8:
			var h=Vector2.RIGHT.rotated(bearing*PI/4)
			var feet=r.Contact.feet(r,u,h)
			check(feet.size()==r.config.types[u.kind].files,'Single row count preserved')
			for point in feet:
				var ground: Vector2=r.ground_basis.affine_inverse().basis_xform(point)
				check(absf(ground.dot(h))<.001,'Row is perpendicular to front in world space')
		check(hp==u.hp and u.max_hp==r.config.types[u.kind].hp,'Facing leaves combat stats unchanged')
		var screen: Vector2=(t.field.project(u.pos)-t.camera_offset)*t.zoom
		check(t.squad_at(screen,u.side).get('id',-1)==u.id,'Current camera picks the correct squad')
	await snap('01-三分区布阵',t)
	t.start_button.pressed.emit()
	check(r.phase=='battle','Official Begin button starts battle')
	t.paused=true
	var old: Array=r.units.map(func(u):return u.pos)
	t._process(1.)
	check(r.elapsed==0 and old==r.units.map(func(u):return u.pos),'Pause freezes enemy attack')
	t.paused=false
	var entered=false
	var damaged=false
	for frame in 2400:
		t._process(1./60)
		entered=entered or r.alive('enemy').any(func(u):return r.neutral_zone.has_point(u.pos))
		damaged=damaged or r.units.any(func(u):return u.side=='ally' and u.hp<u.max_hp)
		if frame==600:await snap('02-敌军进入缓冲带',t)
		if frame==1800:await snap('03-正式接战',t)
	check(entered,'Enemy crosses neutral ground')
	check(damaged,'Enemy actually damages player army')
	check(r.units.any(func(u):return u.side=='enemy' and u.hp<u.max_hp),'Player troops fight back')
	print('Battle sample: elapsed=',r.elapsed,' ally strength=',r.strength('ally'),' enemy strength=',r.strength('enemy'))
	t.zoom=1.0
	t.set_camera(r.projection*Vector2(1050,1450)-Vector2(960,540))
	await snap('04-近景军团',t)
	t.retry()
	check(t.rules is Battle and t.rules.alive('enemy').size()==7 and t.rules.alive('ally').is_empty(),'Retry restores square deployment')
	t.refresh()
	check(t.defender_button.visible,'Player can still choose the original pass')
	t.defender_button.pressed.emit()
	check(not t.rules is Battle and t.rules.defender_preset and t.rules.alive('ally').size()==7,'Pass battle remains available')
	await snap('05-保留山口',t)
	var victory=Battle.new();victory.deploy_combined();victory.start()
	for u in victory.alive('enemy'):
		if u.kind!='medic':victory.hurt(u,u.hp)
	victory.resolve_battle(0)
	check(victory.phase=='victory','Enemy medics cannot prolong a lost battle')
	var defeat=Battle.new();defeat.deploy_combined();defeat.start()
	for u in defeat.alive('ally'):
		if u.kind!='medic':defeat.hurt(u,u.hp)
	defeat.resolve_battle(0)
	check(defeat.phase=='defeat','Player medics cannot prolong a lost battle')
	t.closed.emit()
	main.queue_free()
	await process_frame
	print('Square battle: ',checks,' checks, ',errors,' failures')
	quit(1 if errors else 0)

func snap(name: String,_t):
	_t.refresh()
	if DisplayServer.get_name()=='headless':return
	for frame in 5:await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png('res://../output/high-view/'+name+'.png')
