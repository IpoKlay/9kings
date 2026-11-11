extends SceneTree
const Battle=preload('res://scripts/strategy/battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func fixture(kind: String,front: bool):
	var r=Battle.new(false);r.units.clear();r.next_id=0
	var wall=r.spawn_person(kind,'ally',Vector2(1700,1800))
	var horse=r.spawn_person('light_cavalry','enemy',Vector2(1350,1800))
	horse.order='hold'
	wall.soldiers[0].heading=Vector2.LEFT if front else Vector2.UP
	wall.soldiers[0].shield_raised=kind=='shield'
	wall.soldiers[0].cooldown=999.
	horse.soldiers[0].heading=Vector2.RIGHT
	return r
func tick(r,seconds: float):
	for i in roundi(seconds*60):r.step(1./60.)
func run_case(kind: String,front: bool):
	var r=fixture(kind,front);var horse=r.units[1].soldiers[0]
	r.Charges.issue(r,[Vector2i(r.units[1].id,0)],Vector2(2000,1800),'enemy')
	var damage_events=0;var contact_position=Vector2.ZERO;var max_x=horse.position.x
	for i in 480:
		r.step(1./60.)
		max_x=maxf(max_x,horse.position.x)
		for event in r.events:
			if event.get('personal_charge',false):
				damage_events+=1;contact_position=horse.position
				check(horse.has('charge_run') and is_equal_approx(horse.charge_run.penalty,.12),'First contact keeps the run active with 0.12 slowdown: '+kind+str(front))
		r.events.clear()
	check(damage_events==1,'Single victim receives one charge grant: '+kind+str(front))
	check(not horse.has('charge_run') and horse.charge_cooldown>0.,'Charge finishes into cooldown')
	return {'rules':r,'horse':horse,'max_x':max_x,'contact':contact_position}
func _initialize():call_deferred('run')
func run():
	var side=run_case('shield',false)
	var shield=run_case('shield',true)
	var spear=run_case('spear',true)
	for case in [side,shield,spear]:
		check(case.horse.charge_end.reason in ['goal','duration','stalled','blocked'],'Charge ends from movement conditions, not a defender type')
		check(case.max_x>1720.,'A single stationary shield or spear does not impose a scripted barrier')
	var packed=fixture('shield',true);var mount=packed.units[1];var charging=mount.soldiers[0]
	var point=charging.position+Vector2.RIGHT*5.
	for i in 8:packed.spawn_person('shield','ally',point)
	var occupied=[]
	for u in packed.units:
		if u.side=='enemy':continue
		u.hp=100000.;u.soldiers[0].hp=100000.;u.soldiers[0].position=point
		occupied.append({'unit':u,'slot':0,'point':point})
	charging.velocity=Vector2.RIGHT*120.
	packed.Charges.issue(packed,[Vector2i(mount.id,0)],Vector2(2000,1800),'enemy')
	packed.Charges.step(packed,{'unit':mount,'slot':0},occupied,1./60.)
	check(charging.has('charge_run') and charging.charge_run.hits.size()==9 and is_equal_approx(charging.charge_run.penalty,.65),'Nine distinct contacts cap slowdown at 0.65 without type-based termination')
	packed.Charges.step(packed,{'unit':mount,'slot':0},occupied,1./60.)
	check(charging.charge_run.hits.size()==9 and is_equal_approx(charging.charge_run.penalty,.65),'Repeated overlap cannot award another charge hit or additional slowdown')
	var r=fixture('spear',true);var defender=r.units[0].soldiers[0];var rider=r.units[1].soldiers[0]
	defender.velocity=Vector2(50,0)
	check(r.Charges.brace(r,r.units[0],defender,Vector2.RIGHT)=='','Moving spears cannot brace')
	defender.velocity=Vector2.ZERO;defender.form_left=2.
	check(r.Charges.brace(r,r.units[0],defender,Vector2.RIGHT)=='','Spears still building a formation cannot brace')
	defender.erase('form_left');defender.heading=Vector2.UP
	check(r.Charges.brace(r,r.units[0],defender,Vector2.RIGHT)=='','Side-hit spears cannot brace')
	r.Charges.issue(r,[Vector2i(r.units[1].id,0)],Vector2(2000,1800),'enemy')
	var before: Vector2=rider.position;r.step(0.)
	check(rider.position==before and rider.charge_run.age==0.,'Pause freezes the charge')
	var via: Array[Vector2]=[]
	r.Soldiers.command(r,[Vector2i(r.units[1].id,0)],'move',Vector2(1400,2000),-1,-1,via,true,'enemy')
	check(not rider.has('charge_run') and rider.personal_order=='move','Mid-charge command cancels old charge and accepts new route')
	# The same return path must remain occupied until a live enemy leaves it.
	defender.wall_slot=Vector2(1720,1800);defender.position=Vector2(1700,1800)
	rider.position=Vector2(1710,1800)
	var row={'unit':r.units[0],'slot':0,'radius':9.}
	var enemy={'unit':r.units[1],'slot':0,'radius':13.,'point':rider.position}
	check(r.Soldiers.return_occupied(row,[enemy]),'Enemy standing inside a gap blocks return')
	enemy.point=Vector2(1710,1900)
	check(not r.Soldiers.return_occupied(row,[enemy]),'Return becomes available after enemy leaves')
	var field=load('res://scripts/tactical/whiteboard_battle.gd').new(false)
	field.units.clear();field.spawn('legion','ally',Vector2(1600,1600));field.spawn('legion','enemy',Vector2(2800,400))
	for unit in field.units:unit.order='hold'
	field.start()
	var line=field.units[0];var block=field.units[1]
	var plan=field.Walls.layout(field,field.Soldiers.group_members([line]),Vector2(1500,1600),Vector2(1760,1600))
	field.Walls.place(field,plan)
	for a in line.soldiers:a.position=a.wall_slot;a.path=[];a.personal_order='hold'
	var displaced=line.soldiers[5]
	field.Charges.knock(field,line,5,Vector2(0,-320.))
	tick(field,2.)
	check(displaced.position.distance_to(displaced.wall_slot)>17. and displaced.personal_order=='hold','Hit soldier keeps the actual gap open after two seconds')
	field.Charges.detach(field,block,0)
	for i in block.soldiers.size():block.soldiers[i].hp=10000. if i==0 else 0.
	block.soldiers[0].max_hp=10000.;field.Soldiers.total(block)
	block.soldiers[0].position=displaced.wall_slot;block.soldiers[0].cooldown=999.;block.soldiers[0].personal_order='hold'
	tick(field,2.)
	check(displaced.position.distance_to(displaced.wall_slot)>17. and displaced.personal_order=='hold','Live enemy occupying the gap prevents automatic return after the timer')
	block.soldiers[0].position+=Vector2(0,-500.)
	tick(field,3.)
	check(displaced.position.distance_to(displaced.wall_slot)<3.,'Soldier walks back after the gap is genuinely clear')
	field=null
	print('READABILITY CHECKS=',checks,' FAILURES=',failures)
	side.clear();shield.clear();spear.clear();r=null
	await process_frame
	quit(1 if failures else 0)
