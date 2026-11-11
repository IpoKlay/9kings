extends 'res://tests/strategy/test_contextual_ui.gd'

const Art = preload('res://scripts/tactical/approved_unit_art.gd')
const StaticArt = preload('res://scripts/strategy/static_art.gd')

func check_library():
	var pages = Art.new()
	var roster: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Art.MANIFEST))
	var count = 0
	for unit in roster:
		for action in roster[unit]:
			var texture = pages.page(unit,action,'ally')
			var size = texture.get_size()
			var bounds = Rect2(Vector2.ZERO,size)
			check(size.x<=1024 and size.y<=1024,'Page fits import budget: '+unit+'/'+action)
			for bearing in 8:
				var clip = Art.clip(unit,action,bearing)
				check(clip.regions.size()>1 and clip.end_ms.size()==clip.regions.size()
					and clip.regions.all(func(region):return bounds.encloses(region)),
					'Valid animated regions: '+unit+'/'+action+'/'+str(bearing))
				count+=1
			pages.pages.clear()
	check(count==968 and roster.size()==23,'All 23 units and 968 clips are present')
	for unit in ['U13','U14','U15','U16','U17']:
		for bearing in 8:
			var clip=Art.clip(unit,'attack',bearing)
			var hit=clip.frame_at(clip.release_ms)
			check(clip.release_ms>0 and clip.attack_frame(.44,.8,.44)==hit
				and clip.attack_frame(.439,.8,.44)<hit and clip.release_offset!=Vector2.ZERO,
				'Bow release is pinned to the existing fire time')
	check(pages.page('U08','idle','ally')!=pages.page('U08','idle','enemy'),'Enemy shield retains separate team colors')

func pose(t,u: Dictionary,walking=false,distance=0.,attacking=false) -> Dictionary:
	var r=t.rules
	var a: Dictionary=u.soldiers[0]
	var figure={'bearing':Art.bearing_for(a.heading)}
	figure.pixel_action=t.field.apply_approved_pose(figure,r,u,a,walking,distance,attacking,a.attack_age,r.Soldiers.ATTACK_DURATION)
	return figure

func run():
	check_library()
	var main=load('res://scenes/main.tscn').instantiate()
	main.settings_path='/tmp/approved-unit-animations.cfg'
	root.add_child(main)
	main.sound.enabled=false
	for i in 4:await process_frame
	click(main.menu_view.get_node('%TacticalTrial').get_global_rect().get_center())
	for i in 4:await process_frame
	var t=main.active_trial
	t.set_process(false)
	var r=t.rules
	check(r.has_method('strategy_paths') and r.phase=='battle','Main menu enters the production strategy battle')
	var worker: Dictionary=r.alive('ally')[0]
	var soldier: Dictionary=r.alive('ally').filter(func(u):return u.unit_type=='shield')[0]
	check(worker.approved_art=='U01' and soldier.approved_art=='U08','Opening villagers and shields use the approved sprites')
	check(pose(t,worker).pixel_action=='idle','Opening villagers use animated idle')
	await snap('approved-animation-opening',t)

	var worker_id=Vector2i(worker.id,0)
	var resource: Dictionary=r.resources[0]
	check(r.gathering([worker_id],0),'Villager accepts the real gather command')
	worker.pos=resource.pos+Vector2(0,32)
	worker.soldiers[0].position=worker.pos
	var resource_before: float=resource.remaining
	r.advance_economy(1./60.)
	var working=pose(t,worker)
	check(resource.remaining<resource_before and working.pixel_action=='attack'
		and working.bearing==4,'Actual gathering plays the work frames toward the resource')

	var ram: Dictionary=r.spawn_person('ram','ally',Vector2(1440,2210))
	var engineer: Dictionary=r.spawn_person('engineer','ally',ram.pos+Vector2(40,0))
	check(ram.approved_art=='' and engineer.approved_art=='U02','Only supplied units change sheets')
	r.hurt(ram,100.,'sword',0.,0)
	check(r.interact_unit([Vector2i(engineer.id,0)],ram.pos),'Engineer accepts repair')
	var previous_hp: float=ram.hp
	r.advance_siege(1./60.)
	check(ram.hp>previous_hp and pose(t,engineer).pixel_action=='attack','Repair plays the actual engineer work clip')

	r.stock={'food':10000.,'wood':10000.,'iron':10000.}
	for expected in range(2,6):
		check(r.research('promotion',1),'Normal promotion command starts')
		r.advance_economy(20.)
		check(r.level==expected and soldier.approved_art==StaticArt.unit_id('shield',expected),'Existing shield soldier upgrades on the field')
		for kind in ['spear','archer','light_cavalry']:
			var recruit: Dictionary=r.spawn_person(kind,'ally',Vector2(1550,2210))
			check(recruit.approved_art==StaticArt.unit_id(kind,expected),'Recruited unit matches upgraded art')
			r.units.erase(recruit)

	r.units.clear()
	var shield: Dictionary=r.spawn_person('shield','ally',Vector2(1580,2300))
	var spear: Dictionary=r.spawn_person('spear','ally',Vector2(1520,2300))
	var archer: Dictionary=r.spawn_person('archer','ally',Vector2(1460,2300))
	var horse: Dictionary=r.spawn_person('light_cavalry','ally',Vector2(1530,2440))
	var guard: Dictionary=r.spawn_person('elite_cavalry','ally',Vector2(1600,2440))
	t.set_camera(t.field.project(Vector2(1570,2300))-root.get_visible_rect().size/(2.*t.zoom))
	check(r.Soldiers.command(r,[Vector2i(spear.id,0)],'move',spear.pos+Vector2(0,65)),'Normal movement command starts')
	for i in 36:r.step(1./60.)
	var walking=pose(t,spear,spear.slot_speeds[0]>.2,spear.slot_distances[0])
	check(walking.pixel_action=='walk' and walking.pixel_frame>0,'Walk advances by actual distance')
	check(walking.scale==pose(t,shield).scale and walking.scale==pose(t,horse).scale,
		'All approved sprites preserve the source infantry-to-cavalry pixel ratio')

	var target: Dictionary=r.spawn_person('shield','enemy',Vector2(1700,2300))
	check(target.approved_art=='U08' and guard.approved_art=='U23','Enemy base tier and elite rider choose the right atlas')
	r.Soldiers.attack(r,archer,target,0,0)
	var a: Dictionary=archer.soldiers[0]
	check(a.get('attack_pending',false) and pose(t,archer,false,0.,true).pixel_action=='attack','Attack starts through normal soldier combat')
	var release: float=r.Soldiers.ATTACK_DURATION*(1.-archer.individual_stats.fire_fraction)
	r.Soldiers.advance(archer,release)
	r.Soldiers.fire_actor(r,archer,0)
	check(r.volleys.size()==1 and r.volleys[0].has('sprite_origin'),'Actual shot has one visual bow origin')
	if r.volleys.size()==1:
		var shot: Dictionary=r.volleys[0]
		var release_pose=pose(t,archer,false,0.,true)
		var clip=release_pose.pixel_clip
		var expected_origin: Vector2=archer.pos+clip.release_offset*Art.DISPLAY_SCALE
		check(release_pose.pixel_frame==clip.frame_at(clip.release_ms)
			and shot.sprite_origin.is_equal_approx(expected_origin)
			and shot.origin.is_equal_approx(r.Projectiles.origin(r,archer,0)),
			'Release frame matches the arrow while the physical projectile origin stays unchanged')
	await snap('approved-animation-release',t)

	check(r.Charges.issue(r,[Vector2i(horse.id,0)],horse.pos+Vector2(200,0)),'Real mounted charge order')
	var first=pose(t,horse)
	horse.soldiers[0].charge_run.age=.23
	var next=pose(t,horse)
	check(first.pixel_action=='charge' and next.pixel_action=='charge' and first.pixel_frame!=next.pixel_frame,'Mounted charge plays its own full-frame gallop')
	r.hurt(shield,10.,'sword',0.,0,target.id,0)
	check(pose(t,shield).pixel_action=='hurt','Ordinary damage plays a hurt clip')
	r.hurt(target,10000.,'sword',0.,0,shield.id,0)
	r.step(1./60.)
	check(not r.casualties.is_empty() and target.soldiers[0].death_state!=0
		and r.casualties.back().approved_art=='U08' and r.casualties.back().side=='enemy',
		'Normal casualty lifecycle retains the correct approved tier and team')
	if not r.casualties.is_empty():
		var fall=Art.clip('U08','death',r.casualties.back().bearing)
		check(fall.frame_at(3000)==fall.regions.size()-1,'Death holds on the final pose')
		r.advance_casualties(.72)
	await snap('approved-animation-combat',t)

	print('APPROVED ANIMATION CHECKS=',checks,' FAILURES=',failures)
	t.queue_free()
	main.queue_free()
	await process_frame
	await create_timer(.2).timeout
	quit(1 if failures else 0)
