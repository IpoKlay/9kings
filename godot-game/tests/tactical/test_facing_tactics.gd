extends SceneTree

const Pass=preload('res://scripts/tactical/pass_battle.gd')
const Plain=preload('res://scripts/tactical/trial_rules.gd')
const OUT='res://../output/facing-tactics/'
var failures=0
var report: FileAccess

func _initialize():call_deferred('run')

func check(ok: bool,note: String):
	if not ok:
		failures+=1
		push_error(note)

func matchup(r, angle: float, offset: float, sector: String):
	r.units.clear()
	var center=Vector2(730,650)
	var heading=Vector2.RIGHT.rotated(angle)
	r.spawn('guard','enemy',center)
	r.spawn('cavalry','ally',center+heading.rotated(offset)*64)
	var shield: Dictionary=r.units[0]
	var riders: Dictionary=r.units[1]
	shield.heading=heading
	shield.order='hold'
	r.start()
	var hp: float=shield.hp
	var initial_morale: float=shield.get('morale',0)
	r.step(1./60)
	var damage=hp-float(shield.hp)
	var morale_loss=initial_morale-float(shield.get('morale',0))
	var expected: float=17*3.5*{'front':.72,'side':1.2,'rear':1.4}[sector]
	var morale_expected: float=expected/hp*125+{'front':0,'side':3,'rear':5}[sector] if r is Pass else 0.
	check(is_equal_approx(damage,expected) and is_equal_approx(morale_loss,morale_expected),'Rotated damage/morale '+sector)
	check(shield.heading.is_equal_approx(heading),'Shield held its front while striking')
	var impacts=r.events.filter(func(e):return e.kind in ['charge','flanking_charge'])
	check(impacts.size()==1 and impacts[0].sector==sector and (impacts[0].kind=='flanking_charge')==(sector!='front'),'First charge sector and cue')
	report.store_line('%s,%.0f,%.0f,%s,%.3f,%.3f'%['pass' if r is Pass else 'plain',rad_to_deg(angle),rad_to_deg(offset),sector,damage,morale_loss])
	r.events.clear()
	hp=shield.hp
	for tick in 120:r.step(1./60)
	check(r.events.all(func(e):return e.kind not in ['flanking_charge','charge']),'No repeated charge on contact')
	check(is_equal_approx(hp-shield.hp,17*(.72 if sector=='front' else 1.0)),'Second attack is ordinary melee')
	check(not riders.charge,'Charge consumed')

func click(pos: Vector2):
	for down in [true,false]:
		var e=InputEventMouseButton.new()
		e.position=pos
		e.global_position=pos
		e.button_index=MOUSE_BUTTON_LEFT
		e.pressed=down
		root.push_input(e,true)

func snap(name: String):
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OUT+name+'.png')

func visual(t):
	var r=t.rules
	r.units.clear()
	var center=Vector2(840,870)
	r.spawn('guard','enemy',center)
	r.spawn('cavalry','ally',center-Vector2(400,0))
	var enemy=r.units[0]
	var rider=r.units[1]
	enemy.order='hold'
	enemy.heading=Vector2.RIGHT
	t.refresh()
	click(t.start_button.get_global_rect().get_center())
	t.paused=true
	click(t.field.project(rider.pos)-Vector2(0,35))
	var goal=t.field.project(center+Vector2(95,0))
	root.warp_mouse(goal)
	await snap('before-charge')
	check(t.selected=='route','Select cavalry through field input')
	click(goal)
	check(rider.order=='move','Confirm cavalry approach')
	t.paused=false
	var seen=false
	for i in 600:
		await process_frame
		if t.field.effects.any(func(e):return e.kind=='flanking_charge' and e.sector=='rear'):
			seen=true
			break
	check(seen,'Rear charge reached renderer in live battle')
	t.paused=true
	await snap('rear-impact')
	# Retreat on a real move order, then charge the same holding shield again.
	r.march_route(rider.id,t.draft_waypoints,center-Vector2(560,0))
	t.paused=false
	for i in 500:
		await process_frame
		if rider.charge:break
	check(rider.charge,'Cavalry rearms after withdrawing into open ground')
	r.command([rider.id],'attack',enemy.pos,enemy.id)
	var second_charge=false
	for i in 600:
		await process_frame
		if t.field.effects.any(func(e):return e.kind=='flanking_charge' and e.sector=='rear'):
			second_charge=true
			break
	check(second_charge and not rider.charge,'One fresh charge after disengaging')

func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	report=FileAccess.open(OUT+'impacts.csv',FileAccess.WRITE)
	report.store_line('rules,shield_bearing_degrees,relative_attack_degrees,sector,hp_loss,morale_loss')
	for degrees in [0,90,45,135,180,270]:
		for attack in [[0,'front'],[60,'front'],[90,'side'],[-90,'side'],[120,'rear'],[180,'rear']]:
			for r in [Pass.new(),Plain.new()]:matchup(r,deg_to_rad(degrees),deg_to_rad(attack[0]),attack[1])
	report.close()
	var main=load('res://scenes/main.tscn').instantiate()
	main.run_path_override='user://facing-verification-absent.cfg'
	root.add_child(main)
	await process_frame
	main.language='zh'
	click(main.menu_view.get_node('TacticalTrial').get_global_rect().get_center())
	await process_frame
	var t=root.get_child(-1)
	await visual(t)
	t.closed.emit()
	await process_frame
	main.queue_free()
	await process_frame
	print('FACING TACTICS failures: ',failures)
	quit(1 if failures else 0)
