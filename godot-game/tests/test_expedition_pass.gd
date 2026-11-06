extends "res://tests/test_supply_to_battle.gd"
## Native pointer flow. The previous V1 writer produced this checkpoint after two victories.
const Store=preload('res://scripts/data/run_store.gd')
const FIXTURE='res://tests/fixtures/saguntum-v1.cfg'
const PILOT='266021'
const OUTPUT='res://../output/expedition-pass/'
var path='/tmp/eagle-pass-flow-%d.cfg'%OS.get_process_id()
var checkpoint=path+'.pending'
var direct: Array[Vector2]=[]

func boot(fresh: bool=false):
	if is_instance_valid(app):
		app.queue_free()
		await process_frame
		await process_frame
	if fresh:check(DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURE),path)==OK,'Copy V1 checkpoint')
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path=path+'.prefs'
	app.run_path_override=path
	root.add_child(app)
	current_scene=app
	app.language='zh'
	app.sound.enabled=false
	app.render_ui()
	await process_frame
	check(app.main_menu and app.has_run,'Old save exposed via Continue')

func resume():
	await press(app.menu_view.get_node('%ResumeGame'))
	check(not app.main_menu,'Continue Expedition clicked')

func enter_pass():
	var map=app.expedition_map
	check(map.visible and app.expedition.can_travel(PILOT),'Pilot is legitimately reachable')
	map.atlas.focus_city(PILOT)
	await process_frame
	await press(map.city_buttons[PILOT])
	check(map.selected==PILOT and not map.travel_button.disabled,'Map click selected Saguntum')
	var brief=map.info.find_child('PassBrief',true,false)
	check(brief!=null and 'II' in brief.text and '预备' in brief.text,'Intel gives garrison, reserves and level II escort')
	check('三选一' in map.info.find_child('RewardText',true,false).text,'Intel explains stakes')
	if app.expedition.state.locked_target=='':await snap('city')
	await press(map.travel_button)
	var skip=InputEventKey.new()
	skip.keycode=KEY_SPACE
	skip.pressed=true
	root.push_input(skip,true)
	await process_frame
	check(is_instance_valid(app.active_trial),'Travel animation hands over to native pass')
	var trial=app.active_trial
	trial.set_process(false)
	var army=trial.rules.alive('ally')
	var escort=army.filter(func(u):return u.get('escort',false))
	check(army.size()==8 and escort.size()==1 and escort[0].kind=='legion' and escort[0].max_hp>army[1].max_hp,'Actual level II escort alongside seven local defenders')
	check(not trial.setup_button.visible and not trial.rules.unlimited_powers,'Expedition uses official deployment')
	await press(trial.start_button)
	check(trial.rules.phase=='battle','Deployment Start button enters live battle')
	return trial

func snap(id: String):
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OUTPUT+id+'.png')

func fight(trial, defend: bool):
	var r=trial.rules
	if not defend:
		var units=r.alive('ally')
		for i in units.size():
			check(r.command([units[i].id],'move',Vector2(280+i%3*52,325+int(i/3)*45)),'Withdraw regiment')
	var ticks=0
	while r.phase=='battle' and ticks<10802:
		if defend and ticks==900:
			check(r.deploy('siege',r.flag_center),'Reserve onager')
			r.command([r.units.back().id],'hold',Vector2.ZERO)
			check(r.deploy('medic',r.flag_center+Vector2(190,120)),'Reserve medic')
		if defend and ticks%15==0:
			for barrel in r.barrels:
				if barrel.state=='ready' and r.alive('enemy').filter(func(u):return u.pos.distance_to(barrel.pos)<155).size()>=2:r.ignite(barrel)
		r.step(1./60)
		if defend:
			for event in r.events:
				if event.kind=='flank_signal':
					check(r.deploy('cavalry',Vector2(900,1170)),'Reserve cavalry')
					check(r.march_route(r.units.back().id,direct,r.terrain.inverse*r.terrain.SIDE_GATE.get_center()),'Intercept flank')
		r.events.clear()
		ticks+=1
	check(r.phase==('victory' if defend else 'defeat'),'Actual tactic produces expected outcome')
	trial.refresh()
	if not trial.pilot:return
	var history=app.campaign.g.history.duplicate(true)
	app.record_pass_result(trial)
	trial.refresh()
	check(app.campaign.g.history==history and history.size()==3,'Result and life change recorded once')
	print('Pass ',r.outcome,' at ',snappedf(r.elapsed,.01),'s: ',history.back().report)

func claim():
	check(app.card_hand!=null and app.campaign.g.phase=='reward','One normal card hand')
	var first=app.campaign.offers()[0]
	await create_timer(.5).timeout
	await use_card(app.card_hand)
	await create_timer(.35).timeout
	check(app.campaign.g.chosen==first,'Reward card claimed by upward swipe')
	if app.campaign.g.phase=='place':
		for cell in app.campaign.g.unlocked_cells:
			var b=app.campaign.building_at(cell)
			if b==null or (b.type==first and b.level<3):
				var p=app.world.center(cell)
				await click(app.world.project(p.x,p.y))
				break
	var after=app.campaign.g.duplicate(true)
	app.advance()
	check(app.campaign.g==after and not app.campaign.choose(first) and not app.expedition.travel(PILOT),'Cannot reclaim, resettle or re-enter cleared city')
	await press(app.ui.get_node('ContinueButton'))
	check(app.expedition_map.visible and app.expedition.state.current==PILOT and app.campaign.g.cities_captured==3 and app.campaign.g.round==4,'Back on map, exactly one new capture and round')
	check(app.expedition.can_travel(app.expedition.destinations()[0]),'Next city unlocked')

func check_escorts():
	var campaign=preload('res://scripts/campaign.gd').new(17)
	var expedition=preload('res://scripts/expedition.gd').new(campaign)
	campaign.g.temporary_orders={'shield':true,'testudo':true}
	for kind in ['legion','spear','guard','archer','cavalry','medic','siege']:
		campaign.g.buildings=[{'type':'training','level':3,'cell':6,'id':1},{'type':kind,'level':2,'cell':12,'id':3},{'type':'legion','level':2,'cell':18,'id':4}]
		var building=expedition.escort_building()
		check(building.type==kind and building.id==3,'Highest combat unit; deterministic tie for '+kind)
		var rules=preload('res://scripts/tactical/pass_battle.gd').new()
		rules.deploy_defenders()
		rules.deploy_escort(campaign,building)
		var escort=rules.units.back()
		check(escort.kind==kind and escort.escort and escort.max_hp>rules.config.types[kind].hp and rules.terrain.clear_segment(kind,escort.pos,escort.pos),'Camp unit fits deployment with upgraded health')
		check(escort.camp_shield>0 and rules.hurt(escort,1)==0,'Recovery shield available in the pass')
		if kind=='legion':check(escort.camp_damage_taken<1 and escort.combat_stats.speed<rules.config.types.legion.speed,'Testudo carries defense and movement cost')
		rules.reserve_squads([escort.id])
		check(escort in rules.units,'Escort retains identity during rearrangement')

func run():
	check_escorts()
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	await boot(true)
	var initial=Store.read_run(path)
	await press(app.menu_view.get_node('%TacticalTrial'))
	var standalone=app.active_trial
	standalone.set_process(false)
	await press(standalone.defender_button)
	standalone.refresh()
	await press(standalone.start_button)
	fight(standalone,false)
	check(standalone.rules.outcome=='flag_lost' and standalone.replay_button.visible,'Independent skirmish resolves and offers replay')
	await click(Vector2(1850,36))
	check(app.main_menu and Store.read_run(path)==initial and app.campaign.g==initial.campaign,'Standalone play preserves expedition save')
	await resume()
	app.language='en'
	app.render_ui()
	app.expedition_map.select_city(PILOT)
	check('Legionary II' in app.expedition_map.info.get_node('PassBrief').text,'English briefing names the actual camp unit')
	await snap('city-en')
	app.language='zh'
	app.render_ui()
	var t=await enter_pass()
	fight(t,true)
	var pending=Store.read_run(path)
	check(pending.campaign.phase=='reward' and pending.expedition.current==PILOT,'Victory immediately persists one pending reward')
	check(DirAccess.copy_absolute(path,checkpoint)==OK,'Preserve post-victory checkpoint')
	await press(t.start_button)
	check(app.dialog_kind=='result','Results button opens normal expedition report')
	await snap('report')
	await press(app.modal.find_child('ReportContinue',true,false))
	check(pending.campaign.offered==app.campaign.offers(),'Reload and live hand match')
	await claim()
	await snap('map-return')
	await boot()
	await resume()
	check(app.expedition.state.current==PILOT and app.campaign.g.phase=='prepare','Restart after claim stays on map')
	DirAccess.copy_absolute(checkpoint,path)
	await boot()
	await resume()
	check(app.campaign.offers()==pending.campaign.offered,'Restart before claiming preserves exact hand')
	await claim()
	await boot(true)
	await resume()
	t=await enter_pass()
	t.rules.step(.016)
	await click(Vector2(1850,36))
	check(app.expedition_map.visible and app.expedition.state.locked_target==PILOT and app.campaign.g.defense==3 and app.campaign.g.history.size()==2,'Mid-battle Back returns to locked city without life or reward')
	t=await enter_pass()
	t.rules.step(.016)
	await boot()
	await resume()
	check(app.expedition_map.visible and app.expedition.state.locked_target==PILOT and app.campaign.g.history.size()==2 and app.campaign.g.defense==3,'Restart from disk during battle restores pre-battle checkpoint')
	t=await enter_pass()
	fight(t,false)
	check(t.rules.outcome=='flag_lost','Withdrawal loses the standard')
	await press(t.start_button)
	await press(app.modal.find_child('ReportContinue',true,false))
	check(app.campaign.g.phase=='prepare' and app.campaign.g.defense==2 and app.expedition.state.mode=='camp' and not app.expedition.state.reward_due,'Defeat debits one life and returns to camp')
	await boot()
	await resume()
	check(app.campaign.g.defense==2 and app.expedition.state.locked_target==PILOT and app.expedition.can_travel(PILOT),'Defeat restart keeps same retry and life balance')
	# One-life fixture differs only in remaining lives. The defeat itself is played out.
	var last_life=initial.duplicate(true)
	last_life.campaign.defense=1
	check(Store.write_run(path,last_life)==OK,'Persist one-life fixture')
	await boot()
	await resume()
	t=await enter_pass()
	fight(t,false)
	check(app.campaign.g.phase=='defeat' and app.campaign.g.defense==0,'Last life ends the expedition')
	await boot()
	await resume()
	check(app.campaign.g.phase=='defeat' and app.campaign.g.history.back().report.passOutcome=='flag_lost','Terminal defeat survives restart')
	for suffix in ['','.bak','.pending','.prefs']:DirAccess.remove_absolute(path+suffix)
	app.sound.stop()
	app.music.set_process(false)
	for i in 2:app.music.retire_slot(i)
	app.queue_free()
	await process_frame
	await process_frame
	print('Expedition pass: %d checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
