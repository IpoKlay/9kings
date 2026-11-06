extends SceneTree

const Pass=preload('res://scripts/tactical/pass_battle.gd')
const OUTPUT='res://../output/pass-assault/'
const DT=1./60
var failures=0
var trace: FileAccess

func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	if not ok:
		failures+=1
		push_error(note)

func simulate(strategy: String):
	var r=Pass.new()
	r.deploy_defenders()
	var defenders=r.alive('ally')
	var riders=r.alive('enemy').back()
	r.start()
	# Every case begins with the same formation, stock, health and clocks.
	if strategy in ['withdraw','lure']:
		for i in defenders.size():
			r.command([defenders[i].id],'move',Vector2(280+i%3*52,325+int(i/3)*45))
		if strategy=='lure':r.command([defenders.back().id],'move',r.terrain.inverse*Vector2(1170,630))
	elif strategy=='front':
		r.command([defenders[1].id],'move',r.terrain.inverse*Vector2(916,600))
	var horn=0
	var warning_at=-1.
	var release=-1.
	var crossed=false
	var diverted=false
	var shots=0
	var friendly_reached=false
	var responding: Dictionary={}
	var first_capture=-1.
	var closest_bait=INF
	var bait_withdrew=false
	var fire_orders=0
	var supports=false
	var max_shot=0.
	var previous_state='reserve'
	var last_pos={}
	for tick in 10801:
		if r.phase!='battle':break
		for u in r.alive('enemy'):last_pos[u.id]=u.pos
		r.step(DT)
		for e in r.events:
			if e.kind=='flank_signal':
				horn+=1
				warning_at=r.elapsed
				if strategy=='seal':
					check(r.deploy('cavalry',Vector2(900,1170)),'Reserve cavalry deployed')
					responding=r.units.back()
					check(r.march_route(responding.id,[],r.terrain.inverse*r.terrain.SIDE_GATE.get_center()),'Reserve interception order')
				elif strategy=='front':
					responding=defenders[0]
					check(r.march_route(responding.id,[],r.flag_center),'Front line recall order')
			if e.kind=='arrow':
				for archer in r.alive('enemy'):
					if archer.kind=='archer' and archer.pos.distance_to(e.from)<1:
						shots+=1
						max_shot=maxf(max_shot,e.from.distance_to(e.pos))
						break
		r.events.clear()
		if strategy in ['front','seal'] and not supports and r.elapsed>=15:
			supports=true
			check(r.deploy('siege',r.flag_center),'Reserve onager covers the standard')
			r.command([r.units.back().id],'hold',Vector2.ZERO)
			check(r.deploy('medic',r.flag_center+Vector2(125,30)),'Reserve medic supports the defenders')
		if strategy in ['front','seal'] and tick%15==0:
			for barrel in r.barrels:
				if barrel.state!='ready':continue
				var nearby=r.alive('enemy').filter(func(u):return u.pos.distance_to(barrel.pos)<155)
				if nearby.size()>=2 and r.ignite(barrel):fire_orders+=1
		if strategy=='lure':
			if not bait_withdrew and r.alive('enemy').any(func(u):return u.pos.distance_to(defenders.back().pos)<420):
				r.command([defenders.back().id],'move',Vector2(270,1300))
				bait_withdrew=true
			closest_bait=minf(closest_bait,defenders.back().pos.distance_to(Vector2(270,1300)))
		if r.flank_state!=previous_state:
			print(strategy,' t=',snappedf(r.elapsed,.01),' ',previous_state,' -> ',r.flank_state)
			previous_state=r.flank_state
		if release<0 and r.flank_state in ['divert','crossing']:release=r.elapsed
		diverted=diverted or r.flank_state=='divert'
		crossed=crossed or r.terrain.SIDE_GATE.has_point(r.projection*riders.pos)
		if strategy=='seal' and not responding.is_empty():friendly_reached=friendly_reached or r.terrain.touches_gate(responding.kind,responding.pos)
		if strategy=='front' and not responding.is_empty():friendly_reached=friendly_reached or r.inside_flag(responding)
		if r.capture_time>0 and first_capture<0:first_capture=r.elapsed
		for u in r.alive('enemy'):
			if not r.terrain.clear_segment(u.kind,last_pos[u.id],u.pos):
				check(false,'Rock crossing by '+u.kind)
				return
			if tick%60==0:trace.store_line('%s,%.2f,%d,%s,%.1f,%.1f,%s,%.2f'%[strategy,r.elapsed,u.id,u.kind,u.pos.x,u.pos.y,r.flank_state,r.capture_time])
	check(horn==1 and release-warning_at>=5.99,'One horn and six seconds of warning')
	check(r.phase in ['victory','defeat'],'Scenario completes')
	if strategy=='withdraw':
		check(r.outcome=='flag_lost' and crossed,'Vacated flag is captured and riders cross side lane')
	if strategy=='lure':
		check(bait_withdrew and closest_bait<5 and r.outcome=='flag_lost' and defenders.back().hp>0,'Corner rider survives while attackers capture the flag')
	if strategy in ['front','seal']:check(r.phase=='victory','Prepared defense wins with reserve support and oil')
	if strategy=='seal':check(friendly_reached and diverted and not crossed,'Reserve seals side gate and diverts the attack')
	if strategy=='front':check(friendly_reached and shots>0,'Front guard returns to flag and enemy archers shoot')
	check(max_shot<=float(r.config.types.archer.range)+.1,'Enemy support fires in range')
	print('%s result=%s time=%.2f crossed=%s diverted=%s response_reached=%s shots=%d max_range=%.1f capture_at=%.2f oil=%d'%[strategy,r.outcome,r.elapsed,crossed,diverted,friendly_reached,shots,max_shot,first_capture,fire_orders])

func click(pos: Vector2):
	for down in [true,false]:
		var e=InputEventMouseButton.new()
		e.position=pos
		e.global_position=pos
		e.button_index=MOUSE_BUTTON_LEFT
		e.pressed=down
		root.push_input(e,true)

func live_warning():
	var main=load('res://scenes/main.tscn').instantiate()
	main.run_path_override='user://pass-assault-test-absent.cfg'
	root.add_child(main)
	await process_frame
	main.language='zh'
	click(main.menu_view.get_node('%TacticalTrial').get_global_rect().get_center())
	await process_frame
	var t=root.get_child(-1)
	click(t.defender_button.get_global_rect().get_center())
	await process_frame
	main.sound.enabled=true
	main.sound.volume=.7
	click(t.start_button.get_global_rect().get_center())
	await process_frame
	var launch_horn: float=main.sound.last.get('horn',-10)
	for i in ceili((float(t.rules.assault.signal_at)+2)*60):
		await process_frame
		if t.rules.flank_state=='warning':break
	check(t.flag_alert.visible and t.flag_alert.text.contains('侧道敌骑'),'Live side warning HUD')
	check(main.sound.last.get('horn',-10)>launch_horn,'Existing horn audio actually played again at the warning')
	t.paused=true
	var clock_at_warning=t.rules.elapsed
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OUTPUT+'flank-warning.png')
	check(t.rules.elapsed==clock_at_warning,'Pause freezes reaction window')
	t.paused=false
	for i in 700:
		await process_frame
		if t.rules.flank_state=='crossing':break
	check(t.rules.flank_state=='crossing','Open side lane commits after warning')
	t.paused=true
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OUTPUT+'flank-attack.png')
	t.closed.emit()
	await process_frame
	main.queue_free()
	await process_frame

func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	trace=FileAccess.open(OUTPUT+'attack-tracks.csv',FileAccess.WRITE)
	trace.store_line('defense,seconds,unit,kind,world_x,world_y,flank_state,capture_seconds')
	for strategy in ['front','seal','withdraw','lure']:simulate(strategy)
	trace.close()
	if DisplayServer.get_name()!='headless':await live_warning()
	print('PASS ASSAULT failures: ',failures)
	quit(1 if failures else 0)
