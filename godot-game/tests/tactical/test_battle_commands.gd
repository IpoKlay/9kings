extends SceneTree
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func key(code: Key):
	var e=InputEventKey.new();e.pressed=true;e.physical_keycode=code;root.push_input(e,true)
func click(p: Vector2):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;root.push_input(e,true)
func drag(from: Vector2,to: Vector2):
	var press=InputEventMouseButton.new();press.position=from;press.global_position=from;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;root.push_input(press,true)
	var motion=InputEventMouseMotion.new();motion.position=to;motion.global_position=to;motion.relative=to-from;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
	var release=InputEventMouseButton.new();release.position=to;release.global_position=to;release.button_index=MOUSE_BUTTON_LEFT;root.push_input(release,true)
func settled_at_goal(u: Dictionary) -> bool:
	return u.soldiers.all(func(a):return a.hp<=0 or a.personal_order=='idle' and (a.get('settled_position',a.position).distance_to(a.move_goal)<17. or a.get('settled_by_sibling',false) and a.get('settled_position',a.position).distance_to(a.move_batch.center)<=a.move_batch.radius))

func run():
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-command-test.cfg';root.add_child(app)
	# Explicit ordinary-field fixture; the normal menu now enters StrategyBattle.
	var t=load('res://scenes/tactical_trial.tscn').instantiate()
	t.app=app;t.rules=t.WhiteboardBattle.new(false);app.hide();app.set_process_input(false);app.set_process_unhandled_input(false);root.add_child(t)
	t.set_process(false);app.sound.enabled=false
	var r=t.rules;r.units.clear()
	r.spawn('legion','ally',Vector2(700,1100))
	r.spawn('legion','enemy',Vector2(900,1100))
	r.spawn('medic','enemy',Vector2(1600,100))
	r.spawn('legion','enemy',Vector2(1800,100))
	var a=r.units[0];var b=r.units[1]
	for u in r.units:u.order='hold';u.heading=Vector2.RIGHT;u.formation_heading=u.heading
	t.start_button.pressed.emit();t.squad_ids=[a.id];t.selected='route';t.paused=true
	t.set_camera(r.projection*Vector2(950,1100)-Vector2(960,540)/t.zoom)
	var destination=Vector2(1250,1100)
	key(KEY_X)
	check(t.selected=='attack_move','X arms attack-move from normal battle input')
	click((r.projection*destination-t.camera_offset)*t.zoom)
	check(a.order=='attack_move' and a.destination.distance_to(destination)<.001,'Ground click commits the destination')
	t._process(.1)
	check(a.pos==Vector2(700,1100),'Paused command does not move before resume')
	t.paused=false
	var fought=false
	for tick in 300:
		t._process(1./60)
		if b.hp<b.max_hp:fought=true;break
	check(fought and a.order=='attack_move','Attack-move acquires a nearby enemy and fights without discarding its order')
	check(a.destination.distance_to(destination)<.001,'Combat preserves the final destination')
	r.hurt(b,10000.)
	var arrived=false
	for tick in 600:
		t._process(1./60)
		if a.order=='idle':arrived=true;break
	check(arrived and a.pos.distance_to(destination)<17.,'After target death the squad resumes and arrives at the original destination')
	check(not r.command([a.id],'attack_move',Vector2(-500,-500)) and a.order=='idle','Invalid attack-move cannot replace the current order')
	key(KEY_X);key(KEY_ESCAPE)
	check(t.selected=='' and not t.paused,'Escape cancels aiming without pausing')
	key(KEY_X);key(KEY_H)
	check(t.selected=='' and a.order=='hold','Hold replaces the armed attack-move command')
	# F captures a left drag without panning, then the actual formation walks there.
	key(KEY_F)
	check(t.selected=='shield_line','F arms shield-line placement for eligible troops')
	var camera: Vector2=t.camera_offset
	var start=Vector2(1050,1000);var end=Vector2(1450,1000)
	drag((r.projection*start-camera)*t.zoom,(r.projection*end-camera)*t.zoom)
	check(a.get('shield_wall',false) and a.destination==Vector2(1250,1000),'Left drag commits a real shield-wall destination')
	check(t.camera_offset==camera and not t.drawing_wall,'Shield drag does not pan the battlefield or leave capture active')
	var previous: Vector2=a.pos
	t._process(1./60)
	check(a.soldiers.all(func(s):return s.get('velocity',Vector2.ZERO).length()<=50.01) and a.pos!=previous,'Shield march accelerates each person with the reference 50-unit speed cap')
	for tick in 420:t._process(1./60)
	check(a.order=='hold' and a.pos.distance_to(Vector2(1250,1000))<3. and a.heading.is_equal_approx(Vector2.UP),'Troops arrive on the dragged line and face its indicated normal')
	var foe=r.units[3]
	r.heal(a,10000.)
	foe.pos=a.pos+Vector2(0,-250)
	var hit=r.deal_blow(foe,a,100.,{}, {'attacker_slot':0,'target_slot':0})
	check(is_equal_approx(hit.damage,40.),'Explicit frontal shield wall applies 60 percent melee reduction once')
	foe.pos=a.pos+Vector2(0,250)
	hit=r.deal_blow(foe,a,100.,{}, {'attacker_slot':0,'target_slot':1})
	check(is_equal_approx(hit.damage,100.),'Exposed rear does not receive frontal shield protection')
	r.spawn('archer','enemy',a.pos+Vector2(0,-300));var bow=r.units.back();bow.order='hold'
	a.shield_wall=false;a.soldiers[3].shield_wall=false
	r.deal_blow(bow,a,15.,{}, {'attacker_slot':0,'target_slot':3})
	a.shield_wall=true;a.soldiers[3].shield_wall=true
	var hp: float=a.soldiers[3].hp
	r.advance_volleys(2.)
	check(is_equal_approx(hp-a.soldiers[3].hp,3.),'Arrow mitigation is evaluated at impact after the shield was raised, without double reduction')
	# A friendly rear unit cannot march through the shield wall, but may withdraw.
	r.spawn('legion','ally',a.pos+Vector2(0,65));var rear=r.units.back()
	rear.heading=Vector2.UP;rear.formation_heading=Vector2.UP;rear.order='hold'
	check(not r.may_advance(rear,rear.pos+Vector2(0,-20)),'Friendly shield wall blocks movement through its occupied row')
	check(r.may_advance(rear,rear.pos+Vector2(0,20)),'A blocked friendly unit can withdraw')
	check(not r.command_shield_line([a.id],a.pos,a.pos) and a.shield_wall,'Zero-length line preserves the old shield order')
	var rock=Rect2(r.projection*Vector2(1250,850)-Vector2(15,15),Vector2(30,30))
	r.terrain.ROCKS.append(rock)
	check(not r.command_shield_line([a.id],Vector2(1050,850),Vector2(1450,850)) and a.shield_wall,'Shield-line placement rejects rock occupancy and preserves the live order')
	r.terrain.ROCKS.erase(rock)
	check(not r.command_shield_line([bow.id],start,end),'Enemy or ineligible archers cannot be put in a player shield wall')
	r.command([a.id],'attack_move',Vector2(1300,1250))
	check(not a.get('shield_wall',false),'Accepted replacement attack-move cancels the shield stance')
	t.retry()
	check(not t.drawing_wall and t.rules.shield_walls.is_empty() and t.rules.wall_serial==0 and t.rules.units.all(func(u):return not u.get('shield_wall',false)),'Retry clears shield orders and gesture state')
	# A surviving off-centre soldier must remain reachable when both centres meet.
	r=t.rules;r.units.clear()
	r.spawn('legion','ally',Vector2(700,1150));r.spawn('legion','enemy',Vector2(900,1150));r.spawn('legion','enemy',Vector2(1800,300))
	a=r.units[0];b=r.units[1]
	for slot in b.soldiers.size():
		if slot!=5:b.soldiers[slot].hp=0.
	r.Soldiers.total(b);b.visible_slots=[5]
	for u in r.units:u.order='hold'
	r.start();r.command([a.id],'attack_move',Vector2(1250,1150))
	for tick in 1200:
		r.step(1./60)
		if a.order=='idle':break
	check(b.hp<=0 and a.order=='idle' and settled_at_goal(a),'Attack-move reaches the real surviving foot, defeats it, and resumes instead of stalling at the enemy centre')
	t.queue_free();app.queue_free();await process_frame
	print('Battle commands: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
