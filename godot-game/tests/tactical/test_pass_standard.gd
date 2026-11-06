extends SceneTree
const Shutdown=preload('res://tests/tactical/helpers/native_shutdown.gd')

const Pass=preload('res://scripts/tactical/pass_battle.gd')
const Plain=preload('res://scripts/tactical/trial_rules.gd')
const OUT='res://../output/pass-standard/'
const DT=1./60
var failures=0
var t

func _initialize():call_deferred('run')

func check(ok: bool,note: String):
	if ok:print('PASS ',note)
	else:
		failures+=1
		push_error(note)

func fixture(r):
	r.units.clear()
	r.spawn('legion','ally',Vector2(1900,1100))
	r.spawn('legion','enemy',r.flag_center)
	for u in r.units:u.order='hold'
	r.start()

func ticks(r,n: int):
	for i in n:r.step(DT)

func cases():
	var r=Pass.new()
	fixture(r)
	r.units[1].pos=Vector2(2350,650)
	ticks(r,10800)
	check(r.phase=='victory' and r.outcome=='time_held','Held for full 180 simulated seconds')
	r=Pass.new()
	fixture(r)
	ticks(r,719)
	check(r.phase=='battle' and r.units[0].hp>0 and r.capture_time<12,'Flag holds until the 720th tick')
	r.step(DT)
	check(r.phase=='defeat' and r.outcome=='flag_lost' and r.units[0].hp>0,'Loses flag at 12 seconds with surviving defenders')
	r=Pass.new()
	fixture(r)
	check(r.deploy('medic',r.flag_center+Vector2(40,r.flag_radius+42)),'Reserve medic deployed behind the pass')
	var relief: Dictionary=r.units.back()
	r.units[1].stun=60
	ticks(r,240)
	r.command([relief.id],'move',r.flag_center+Vector2(40,r.flag_radius-25))
	ticks(r,75)
	var saved: float=r.capture_time
	ticks(r,60)
	check(r.flag_state=='contested' and saved>4 and saved<5.25 and r.capture_time==saved,'Returning regiment enters on a move order and freezes progress')
	relief.pos=r.flag_center+Vector2(40,r.flag_radius+20)
	ticks(r,30)
	check(is_equal_approx(r.capture_time,saved+.5),'Enemy resumes from contested progress')
	r.units[0].pos=r.flag_center
	r.units[1].pos=r.flag_center+Vector2(180,0)
	r.step(DT)
	check(r.flag_state=='secure' and r.capture_time==0,'Defender control resets progress')
	r.units[0].pos=Vector2(1950,1100)
	r.units[1].pos=r.flag_center
	ticks(r,60)
	r.units[1].pos=Vector2(2350,650)
	r.step(DT)
	check(r.capture_time==0,'Empty zone clears progress')
	r.spawn('archer','enemy',r.flag_center)
	r.units.back().routing=true
	r.spawn('cavalry','enemy',r.flag_center)
	r.units.back().hp=0
	ticks(r,20)
	check(r.flag_state=='secure' and r.capture_time==0,'Routing and dead attackers inside zone do not capture')
	r.units[0].pos=r.flag_center
	r.units[0].routing=true
	r.units[1].pos=r.flag_center
	r.step(DT)
	check(r.flag_state=='capturing','Routing defenders cannot contest')
	r=Pass.new()
	fixture(r)
	r.elapsed=r.config.duration-DT
	r.capture_time=r.capture_seconds-DT
	r.step(DT)
	check(r.outcome=='flag_lost','Capture beats the defense deadline on the same tick')
	r=Pass.new()
	fixture(r)
	r.elapsed=r.config.duration-DT
	r.capture_time=r.capture_seconds-DT
	# The last captor falls to an active poison tick while the flag and clock are one tick from completion.
	r.units[1].hp=.001
	r.units[1].poison=1
	r.step(DT)
	check(r.phase=='victory' and r.outcome=='enemy_routed','Final captor killed this tick beats the deadline and imminent capture')
	r=Pass.new()
	fixture(r)
	r.units[1].routing=true
	r.step(DT)
	check(r.phase=='victory' and r.outcome=='enemy_routed' and r.elapsed<1,'Early rout wins immediately')
	r=Pass.new()
	fixture(r)
	r.capture_time=r.capture_seconds-DT
	r.elapsed=r.config.duration-DT
	r.units[0].pos=r.flag_center+Vector2(80,0)
	r.step(DT)
	check(r.outcome=='time_held' and r.flag_state=='contested','Last-tick contest interrupts capture at the deadline')
	var plain=Plain.new(false)
	plain.deploy_vanguard()
	plain.start()
	plain.elapsed=plain.config.duration-.001
	plain.step(DT)
	check(plain.phase=='timeout','Ordinary RTS uses its original timeout')
	r=Pass.new()
	fixture(r)
	r.units[1].pos=r.flag_center+Vector2(300,0)
	r.units[1].order='auto'
	ticks(r,1200)
	check(r.outcome=='flag_lost','An unopposed attacker marches into the flag zone and takes it')

func click(pos: Vector2):
	for down in [true,false]:
		var e=InputEventMouseButton.new()
		e.position=pos
		e.global_position=pos
		e.button_index=MOUSE_BUTTON_LEFT
		e.pressed=down
		root.push_input(e,true)

func snap(name: String):
	t.refresh()
	t.field.queue_redraw()
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OUT+name+'.png')

func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	cases()
	var main=load('res://scenes/main.tscn').instantiate()
	main.run_path_override='user://pass-standard-test-absent.cfg'
	root.add_child(main)
	await process_frame
	main.language='zh'
	click(main.menu_view.get_node('TacticalTrial').get_global_rect().get_center())
	await process_frame
	t=root.get_child(-1)
	click(t.defender_button.get_global_rect().get_center())
	await process_frame
	await snap('01-deployment')
	click(t.start_button.get_global_rect().get_center())
	await process_frame
	t.paused=true
	var r=t.rules
	var raider=r.alive('enemy')[0]
	raider.pos=r.flag_center
	for u in r.units:u.order='hold'
	ticks(r,360)
	await snap('02-threat')
	check(t.flag_alert.visible and t.flag_alert.text.contains('军旗告急'),'Threat HUD shown beside strength bar')
	var defender=r.alive('ally')[0]
	defender.pos=r.flag_center+Vector2(85,0)
	r.step(DT)
	await snap('03-contested')
	check(t.flag_alert.text.contains('争夺'),'Contested HUD shown')
	defender.pos=Vector2(1750,1100)
	ticks(r,361)
	await snap('04-defeat')
	check(t.result.text.contains('军旗失守') and r.phase=='defeat','Defeat screen gives flag loss as cause')
	click(t.start_button.get_global_rect().get_center())
	await process_frame
	check(t.rules.outcome=='' and t.rules.capture_time==0 and not t.flag_alert.visible,'Retry clears capture, warning and outcome')
	fixture(t.rules)
	t.rules.units[1].routing=true
	t.rules.step(DT)
	t.refresh()
	check(t.result.text.contains('敌军已被击溃'),'Victory screen distinguishes an enemy rout')
	t.retry()
	fixture(t.rules)
	t.rules.units[1].pos=Vector2(2300,630)
	t.rules.elapsed=t.rules.config.duration-DT
	t.rules.step(DT)
	t.refresh()
	check(t.result.text.contains('守城时间已到'),'Victory screen distinguishes holding to the deadline')
	t.closed.emit()
	await process_frame
	main.queue_free()
	await process_frame
	print('PASS STANDARD failures: ',failures)
	await Shutdown.settle(self)
	quit(1 if failures else 0)
