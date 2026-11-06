extends SceneTree

const OUTPUT='res://../output/pass-playtest/'
const Pass=preload('res://scripts/tactical/pass_battle.gd')
const DT=1./60
var failures=0
var main
var t
var initial={}
var direct: Array[Vector2]=[]
var completed=0
var ledger: FileAccess
var baseline: bool

func _initialize():call_deferred('run')

func check(ok: bool,message: String):
	if not ok:
		failures+=1
		push_error(message)

func click(pos: Vector2):
	for down in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=pos
		event.global_position=pos
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
		root.push_input(event,true)

func army_stats(r,side: String) -> Dictionary:
	var deployed=0
	var missing=0
	var dead=0
	var broken=0
	var active=0
	var morale=0.
	var rows=[]
	for u in r.units:
		if u.side!=side:continue
		var soldiers=int(r.config.types[u.kind].soldiers)
		deployed+=soldiers
		missing+=soldiers-ceili(soldiers*u.hp/u.max_hp)
		if u.hp<=0:dead+=1
		elif u.routing:broken+=1
		else:
			active+=1
			morale+=u.morale
		rows.append({'id':u.id,'kind':u.kind,'hp':snappedf(u.hp,.01),'morale':snappedf(u.morale,.01),'routing':u.routing,'pos':[snappedf(u.pos.x,.1),snappedf(u.pos.y,.1)]})
	return {'fielded':deployed,'missing':missing,'destroyed':dead,'routed_alive':broken,'active':active,'mean_active_morale':snappedf(morale/active,.1) if active else null,'units':rows}

func log_event(r,plan: String,event: String,facts: Dictionary={}):
	ledger.store_line(JSON.stringify({'plan':plan,'time':snappedf(r.elapsed,.01),'event':event,'facts':facts,'ally':army_stats(r,'ally'),'enemy':army_stats(r,'enemy'),'flag':r.flag_state,'capture':snappedf(r.capture_time,.01)}))

func snap(label: String):
	if not t:return
	t.refresh()
	t.field.queue_redraw()
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OUTPUT+label+'.png')

func play(plan: String):
	var r
	if t:
		if t.rules.phase!='deploy':
			click(t.replay_button.get_global_rect().get_center())
		else:click(t.defender_button.get_global_rect().get_center())
		t.refresh()
		r=t.rules
	else:
		r=Pass.new()
		r.deploy_defenders()
	if baseline:r.assault.signal_at=4.
	var formation={'ally':army_stats(r,'ally'),'enemy':army_stats(r,'enemy'),'reserve':r.reserve.duplicate(),'oil':r.barrels.duplicate(true)}
	if initial.is_empty():initial=formation
	check(initial==formation,'Identical deployment, health, morale, oil and reserves')
	if t:click(t.start_button.get_global_rect().get_center())
	else:r.start()
	check(r.phase=='battle' and not r.unlimited_powers,'Official pass begins with limited powers')
	var d=r.alive('ally')
	var archers=r.alive('enemy').filter(func(u):return u.kind=='archer')
	var horse: Dictionary={}
	var focus=false
	var rear=false
	var rescue=false
	var oils=0
	var contacts=false
	var max_gap=0.
	var start_gap=archers[0].pos.x-r.alive('enemy')[0].pos.x
	var journal_index=0
	var first_contact=-1.
	log_event(r,plan,'begin')
	if plan=='abandon':
		for i in d.size():check(r.command([d[i].id],'move',Vector2(280+i%3*52,325+int(i/3)*45)),'Withdraw')
	var ticks=0
	while r.phase=='battle' and ticks<10802:
		if plan=='feint' and ticks==120:
			for i in 4:
				var goal: Vector2=d[i].pos-Vector2(325,0)
				if i==0:goal=r.flag_center
				elif i==1:goal=r.flag_center+Vector2(45,-45)
				check(r.march_route(d[i].id,direct,goal),'Yield forward line')
			log_event(r,plan,'yield_first_line')
		if plan=='feint' and ticks==240:
			r.command([d[6].id],'attack',archers[0].pos,archers[0].id)
		# Pass the archers first, leaving a straight run back into their exposed rear.
		if plan=='feint' and ticks==900:
			check(r.deploy('cavalry',Vector2(1065,325)),'Reserve cavalry enters northern approach')
			horse=r.units.back()
			var via: Array[Vector2]=[Vector2(1430,291)]
			check(r.march_route(horse.id,via,Vector2(2600,291)),'Northern turning route accepted')
			log_event(r,plan,'reserve_northern_arc')
		if plan=='feint' and not horse.is_empty() and not focus and (horse.order!='move' or horse.pos.x>maxf(archers[0].pos.x+520,1520)):
			check(r.command([horse.id],'attack',archers[0].pos,archers[0].id),'Focus enemy archers')
			focus=true
			log_event(r,plan,'focus_archers')
		var support_tick=60 if plan=='feint' else 900
		if plan!='abandon' and ticks==support_tick:
			check(r.deploy('siege',r.flag_center),'Onager reserve')
			r.command([r.units.back().id],'hold',Vector2.ZERO)
			check(r.deploy('medic',r.flag_center+Vector2(130,30)),'Medic reserve')
			log_event(r,plan,'support_deployed')
		if plan!='abandon' and ticks%15==0:
			for barrel in r.barrels:
				if barrel.state=='ready' and r.alive('enemy').filter(func(u):return u.pos.distance_to(barrel.pos)<155).size()>=2 and r.ignite(barrel):
					oils+=1
					log_event(r,plan,'fire_arrow',{'barrel':r.barrels.find(barrel)})
		r.step(DT)
		ticks+=1
		if t:t.field.advance(DT)
		for e in r.events:
			if t and e.kind!='flank_signal':t.field.effect(e)
			if not contacts and e.has('attacker') and e.kind in ['hit','charge','flanking_charge']:
				first_contact=r.elapsed
				contacts=true
				log_event(r,plan,'first_melee',{'attacker':e.attacker,'target':e.target})
			if plan=='feint' and not horse.is_empty() and e.get('attacker',-1)==horse.id and e.get('target',-1)==archers[0].id and e.kind=='flanking_charge' and e.sector=='rear' and e.damage>0 and not rear:
				rear=true
				log_event(r,plan,'rear_charge_on_archers',{'damage':e.damage,'attacker':horse.id,'target':archers[0].id,'line_gap':max_gap,'initial_gap':start_gap})
				if t:
					t.set_camera(t.field.project(archers[0].pos)-Vector2(960,540))
					await snap('feint-rear')
			if e.kind=='flank_signal' and not baseline and plan!='abandon':check(contacts,'Front engages before flank warning')
			if plan=='shield' and e.kind=='flank_signal':
				check(r.deploy('cavalry',Vector2(900,1170)),'Deploy rescue cavalry after signal')
				horse=r.units.back()
				check(r.march_route(horse.id,direct,r.terrain.inverse*r.terrain.SIDE_GATE.get_center()),'Seal side gate')
				log_event(r,plan,'reserve_rides_to_intercept')
		if plan=='shield' and not horse.is_empty() and r.terrain.touches_gate(horse.kind,horse.pos):rescue=true
		if plan=='feint' and not rear:
			var front=r.alive('enemy').filter(func(u):return u.kind=='legion')
			for u in front:max_gap=maxf(max_gap,archers[0].pos.x-u.pos.x)
		for i in range(journal_index,r.journal.size()):log_event(r,plan,r.journal[i].kind,r.journal[i])
		journal_index=r.journal.size()
		r.events.clear()
		if ticks%300==0:log_event(r,plan,'sample')
	log_event(r,plan,'end',{'result':r.outcome,'power_used':int(r.config.lightning.charges)-r.charges,'rear':rear,'rescued':rescue,'oil':oils})
	check(r.charges==r.config.lightning.charges and r.phase!='battle','No divine power and terminal battle')
	if plan=='shield':check(oils>0 and rescue and r.phase=='victory','Shield, oil and rescue win')
	if plan=='feint':check(rear and max_gap>start_gap+80 and r.phase=='victory','Yielded line stretches attackers and mounted rear blow wins')
	if plan=='abandon':check(r.outcome=='flag_lost' and not r.alive('ally').is_empty(),'Abandoned flag loses despite surviving defenders')
	if plan=='feint':check(r.key_event().kind=='rear_archers','Debrief cites actual rear charge')
	if t:await snap(plan+'-result')
	completed+=1
	print(plan,' ',r.outcome,' seconds=',snappedf(r.elapsed,.01),' first melee=',snappedf(first_contact,.01),' rear=',rear,' gap=',max_gap,' starting gap=',start_gap,' oils=',oils)

func power_profiles():
	var spells=Pass.new()
	for row in spells.characters:
		var r=Pass.new()
		r.deploy_defenders()
		check(r.select_deity(row.id),'Choose a role during deployment')
		for u in r.units:u.order='hold'
		r.start()
		var cfg=r.power_config()
		var aim=Vector2(2850,800)
		check(not r.unlimited_powers and r.charges==int(cfg.charges),'Official charge budget')
		for cast in int(cfg.charges):
			check(r.strike(aim) and r.cooldown==float(cfg.cooldown) and r.charges==int(cfg.charges)-cast-1,'Official cast cost and cooldown')
			check(not r.strike(aim),'Immediate recast rejected')
			for tick in ceili(float(cfg.cooldown)*60)+1:r.step(DT)
		check(not r.strike(aim),'Exhausted charges stay spent')
	var lab=Pass.new(true)
	lab.deploy_defenders()
	lab.start()
	check(lab.strike(lab.flag_center) and lab.strike(lab.flag_center) and lab.cooldown==0 and lab.charges==int(lab.config.lightning.charges),'Explicit lab still permits unlimited casts')
	print('Checked official charges and cooldowns for ',spells.characters.size(),' roles and explicit unlimited testing')

func run():
	power_profiles()
	baseline='--baseline-horn' in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	ledger=FileAccess.open(OUTPUT+('baseline' if baseline else 'final')+'-battles.jsonl',FileAccess.WRITE)
	if DisplayServer.get_name()!='headless':
		main=load('res://scenes/main.tscn').instantiate()
		main.run_path_override='user://pass-playtest-absent.cfg'
		root.add_child(main)
		await process_frame
		main.language='zh'
		click(main.menu_view.get_node('TacticalTrial').get_global_rect().get_center())
		await process_frame
		t=root.get_child(-1)
		# Drive the live scene at exactly the native 60 Hz simulation step.
		t.set_process(false)
	for strategy in ['shield','feint','abandon']:await play(strategy)
	check(completed==3,'All three battles finished')
	ledger.close()
	if t:
		t.closed.emit()
		await process_frame
		main.queue_free()
		await process_frame
	print('PASS LEVEL failures: ',failures)
	quit(1 if failures else 0)
