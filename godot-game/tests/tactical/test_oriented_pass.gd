extends SceneTree
const Battle=preload('res://scripts/tactical/pass_battle.gd')
var errors=0
func check(ok:bool,what:String):
 if not ok:errors+=1;push_error(what)
func _initialize():call_deferred('run')
func run():
 var r=Battle.new();r.units.clear()
 for kind in r.config.types:
  r.spawn(kind,'ally',r.terrain.inverse*Vector2(600,600))
  var u=r.units.back()
  for direction in 8:
   var h=Vector2.RIGHT.rotated(direction*PI/4)
   var row=r.Contact.feet(r,u,h)
   for foot in row:
    var ground=r.ground_basis.affine_inverse().basis_xform(foot)
    check(absf(ground.dot(h))<.001,'Mountain row perpendicular to facing')
    var limit=r.terrain.extents[kind]
    check(absf(foot.x)<=limit.x and absf(foot.y)<=limit.y,'Fullturn envelope contains every foot')
 r.units.clear()
 r.spawn('legion','enemy',r.terrain.inverse*Vector2(2100,1030));r.units.back().order='hold'
 r.spawn('legion','ally',r.terrain.inverse*Vector2(790,900));var lead=r.units.back()
 r.spawn('cavalry','ally',r.terrain.inverse*Vector2(440,900));var rear=r.units.back()
 r.start()
 check(r.command([lead.id],'move',r.terrain.inverse*Vector2(1540,900)),'Lead valid gate route')
 check(r.command([rear.id],'move',r.terrain.inverse*Vector2(1210,900)),'Rear valid gate route')
 var waits=0
 var overlap=false
 var rock=false
 for tick in 2200:
  r.step(1./60)
  if rear.obstruction=='queue':waits+=1
  var delta=(r.projection*(lead.pos-rear.pos)-r.projection.origin).abs()
  var extent=r.terrain.extents[lead.kind]+r.terrain.extents[rear.kind]
  if delta.x<extent.x and delta.y<extent.y:overlap=true
  for u in [lead,rear]:
   var row=r.Contact.feet(r,u)
   for foot in row:
    var boots=Rect2(r.projection*u.pos+foot-Vector2(9,5)*r.contact_profiles[u.kind].scale,Vector2(18,10)*r.contact_profiles[u.kind].scale)
    for wall in r.terrain.ROCKS:
     if boots.intersects(wall):rock=true
  if rear.order=='hold' and lead.order=='hold':break
 check(waits>0 and not overlap,'Rear queues without overlap')
 check(not rock,'No rotated boot enters rock')
 check((r.projection*rear.pos).distance_to(Vector2(1210,900))<.1,'Rear reached exit')
 check((r.projection*lead.pos).distance_to(Vector2(1540,900))<.1,'Lead reached exit')
 route_cases()
 flag_cases()
 await pause_case()
 print('Oriented terrain failures=',errors,' waits=',waits,' lead=',r.projection*lead.pos,' rear=',r.projection*rear.pos)
 quit(1 if errors else 0)

func fixture() -> RefCounted:
 var r=Battle.new();r.units.clear()
 r.spawn('legion','enemy',r.terrain.inverse*Vector2(2100,1030))
 r.units.back().order='hold'
 return r

func clear_boots(r,u: Dictionary) -> bool:
 var feet=r.Contact.feet(r,u)
 var half=Vector2(9,5)*r.contact_profiles[u.kind].scale
 for slot in feet.size():
  var boots=Rect2(r.projection*u.pos+feet[slot]+r.Contact.body_shift(u,slot,r.elapsed)-half,half*2)
  for rock in r.terrain.ROCKS:
   if boots.intersects(rock):return false
 return true

func route_cases():
 var r=fixture()
 r.spawn('cavalry','ally',r.terrain.inverse*Vector2(300,450))
 var horse=r.units.back();horse.order='hold';r.start()
 var via: Array[Vector2]=[r.terrain.inverse*Vector2(520,450),r.terrain.inverse*Vector2(520,620)]
 var goal: Vector2=r.terrain.inverse*Vector2(700,620)
 check(r.march_route(horse.id,via,goal),'Noncollinear waypoints accepted on the mountain')
 var requested=via.duplicate();requested.append(goal)
 var visited=0;var safe=true
 for tick in 1800:
  r.step(1./60);safe=safe and clear_boots(r,horse)
  if visited<requested.size() and horse.pos.distance_to(requested[visited])<.02:visited+=1
  if horse.order=='hold':break
 check(visited==3 and safe,'Actual cavalry position crosses both waypoints, with oriented feet clear')
 check(not horse.charge and horse.charge_target==-1,'Sharp route corners and arrival leave no armed impact')
 r=fixture();r.spawn('cavalry','ally',r.terrain.inverse*Vector2(630,796))
 horse=r.units.back();horse.order='hold';r.start()
 var none: Array[Vector2]=[]
 goal=r.terrain.inverse*Vector2(1430,796)
 var preview: Dictionary=r.plan_route(horse,none,goal)
 check(preview.ok and preview.points.size()>1,'Rock route preview has an actual detour')
 check(r.march_route(horse.id,none,goal),'Detour order accepted')
 var issued=[horse.destination];issued.append_array(horse.waypoints)
 check(issued==preview.points,'Preview vertices match the executed route')
 visited=0;safe=true
 for tick in 2000:
  var old: Vector2=horse.pos
  r.step(1./60)
  safe=safe and clear_boots(r,horse) and r.terrain.clear_segment(horse.kind,old,horse.pos)
  if visited<issued.size() and horse.pos.distance_to(issued[visited])<.02:visited+=1
  if horse.order=='hold':break
 check(safe and visited==issued.size() and horse.pos.distance_to(goal)<.02,'Actual rotated boots follow every detour vertex without entering rock')
 var invalid=r.terrain.inverse*Vector2(1022,791)
 var before=horse.destination
 check(not r.plan_route(horse,none,invalid).ok and not r.march_route(horse.id,none,invalid),'Rock endpoint rejected before confirmation')
 check(horse.order=='hold' and horse.destination==before,'Rejected route preserves the current command')
 check(not r.plan_route(horse,none,Vector2(-100,-100)).ok,'Out-of-map endpoint is rejected')

func flag_fixture():
 var r=Battle.new();r.units.clear()
 r.spawn('legion','ally',Vector2(1900,1100))
 r.spawn('legion','enemy',r.flag_center)
 for u in r.units:u.order='hold'
 r.start()
 return r

func flag_cases():
 var r=flag_fixture()
 for tick in 719:r.step(1./60)
 check(r.phase=='battle' and r.capture_time<12,'Flag still holds before twelve seconds')
 r.step(1./60)
 check(r.outcome=='flag_lost' and r.units[0].hp>0,'Twelve-second flag loss remains independent of surviving defenders')
 r=flag_fixture();r.units[1].stun=60
 for tick in 240:r.step(1./60)
 r.units[0].pos=r.flag_center+Vector2(85,0)
 var saved: float=r.capture_time
 for tick in 60:r.step(1./60)
 check(r.flag_state=='contested' and is_equal_approx(r.capture_time,saved),'Returning defender freezes capture')
 r.units[1].pos=Vector2(2350,650);r.step(1./60)
 check(r.flag_state=='secure' and r.capture_time==0,'Enemy departure clears capture')
 r.units[1].pos=r.flag_center;r.units[1].routing=true;r.step(1./60)
 check(r.phase=='victory' and r.outcome=='enemy_routed','A routing attacker cannot capture')
 r=flag_fixture();r.elapsed=r.config.duration-1./60;r.capture_time=r.capture_seconds-1./60
 r.step(1./60)
 check(r.outcome=='flag_lost','Same-tick flag capture precedes defensive deadline')
 r=flag_fixture();r.elapsed=r.config.duration-1./60;r.capture_time=r.capture_seconds-1./60
 r.units[1].hp=.001;r.units[1].poison=1;r.step(1./60)
 check(r.outcome=='enemy_routed','Same-tick final enemy death precedes flag capture')

func pause_case():
 var app=load('res://scenes/main.tscn').instantiate()
 app.settings_path='/tmp/eagle-oriented-pass-prefs.cfg'
 root.add_child(app)
 app.menu_view.get_node('%TacticalTrial').pressed.emit()
 var t=app.active_trial;t.set_process(false)
 t.defender_button.pressed.emit()
 var r=t.rules;r.units.clear()
 r.spawn('legion','enemy',r.terrain.inverse*Vector2(2100,1030));r.units.back().order='hold'
 r.spawn('cavalry','ally',r.terrain.inverse*Vector2(400,600))
 var horse=r.units.back();horse.order='hold'
 t.start_button.pressed.emit();t.paused=true
 var origin: Vector2=horse.pos
 var via: Array[Vector2]=[r.terrain.inverse*Vector2(500,600)]
 check(r.march_route(horse.id,via,r.terrain.inverse*Vector2(650,600)),'Mountain accepts a route while paused')
 horse.cooldown=.6;horse.clear_run=25.;horse.recover_until=r.elapsed+.8
 var elapsed: float=r.elapsed
 for tick in 60:t._process(1./60)
 check(horse.pos==origin and r.elapsed==elapsed and horse.cooldown==.6 and horse.clear_run==25. and horse.recover_until-r.elapsed==.8,'Native pause freezes motion, run-up distance, recovery and cooldown')
 t.paused=false;t.slow=true
 for tick in 60:t._process(1./60)
 check(absf(r.elapsed-elapsed-.5)<.00001 and horse.pos!=origin,'Native half speed advances half a simulated second and moves')
 t.closed.emit();app.queue_free()
 await process_frame
