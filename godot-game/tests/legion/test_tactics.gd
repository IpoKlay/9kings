extends SceneTree
const Battle = preload('res://scripts/legion/battle.gd')
var checks = 0
var failures = 0

func check(value: bool, message: String):
	checks += 1
	if not value: failures += 1; printerr('FAIL: '+message)

func step(b, seconds: float):
	for i in roundi(seconds*30): b.update(1.0/30.0)

func fixture(kind: String, count: int, enemy: String = 'shield', enemies: int = 1):
	var b = Battle.new()
	b.regiments.clear(); b.soldiers.clear()
	b.add_regiment(kind,'ally',Vector2(1000,900),count)
	b.add_regiment(enemy,'enemy',Vector2(1800,500),enemies)
	b.start()
	for r in b.regiments: r.order = 'hold'
	return b

func place(b, id: int, p: Vector2, heading: Vector2 = Vector2.UP):
	b.regiments[id].pos = p; b.regiments[id].heading = heading
	b.reform(b.regiments[id],true)

func _initialize(): call_deferred('run')

func run():
	groups_and_rings()
	infantry()
	movement()
	charges()
	ring_contact()
	free_attack()
	print('TACTICS CHECKS=',checks,' FAILURES=',failures)
	quit(1 if failures else 0)

func groups_and_rings():
	var b = Battle.new()
	for i in 4: check(b.selected_group(i+1) == [i],'default numbered regiment '+str(i+1))
	for i in [5,6,7]:
		check(b.selected_group(i).is_empty(),'unassigned group is empty')
		b.bind_group(i,[0,2]); check(b.selected_group(i) == [0,2],'all seven groups bind and recall')
	check(not b.set_formation([0],'wedge') and not b.set_formation([1],'wedge'),'infantry cannot use wedge')
	check(b.set_formation([2],'wedge'),'cavalry can deploy wedge')
	check(b.Combination.candidates(b,1) == [0,3],'only spear and archer partners highlighted')
	check(not b.Combination.create(b,1,2) and b.regiments[1].pair == -1,'invalid pairing is atomic')
	var original = b.regiments.duplicate(true)
	check(b.Combination.create(b,1,3),'shield and archers combine')
	check(b.regiments[1].form == 'ring' and b.regiments[3].form == 'ring_inner','both formations change')
	check(b.regiments[1].pair == 3 and b.regiments[3].pair == 1,'reciprocal combination')
	check(b.mods(b.regiments[1]).attack == -0.25 and b.mods(b.regiments[1]).armor == 0.6,'outer attack penalty and armor boost')
	check(b.mods(b.regiments[3]).rate == 1.3 and b.mods(b.regiments[3]).armor == 0.6,'inner attack speed plus thirty percent and armor boost')
	for id in b.members(b.regiments[3]):
		var inner = b.soldiers[id]
		var nearest = INF
		for oid in b.members(b.regiments[1]): nearest = minf(nearest,inner.pos.distance_to(b.soldiers[oid].pos))
		check(is_equal_approx(nearest,26),'inner soldiers hug corresponding outer soldiers')
	check(b.selected_group(4) == [3,1],'numbering either half selects the whole combination')
	check(b.deploy([3],Vector2(1200,1230)),'moving inner deploys both')
	check(b.regiments[1].pos == b.regiments[3].pos,'combined centers remain linked')
	check(not b.set_formation([3],'dense'),'individual reform cannot break a pair')
	check(b.Combination.dissolve(b,3),'prebattle combination can be undone')
	check(b.regiments[1].pos == original[1].pos and b.regiments[3].pos == original[3].pos,'unlink restores original deployment')
	check(b.Combination.create(b,0,3),'spear and archers combine')
	b.start()
	check(not b.set_formation([2],'wedge') and not b.Combination.create(b,1,0) ,'wedge and combination are prebattle only')
	check(b.command([3],'move',Vector2(900,900)),'linked move accepted from inner')
	step(b,1)
	check(b.regiments[0].pos == b.regiments[3].pos and b.regiments[0].order == 'move','both move under one center and order')
	for id in b.members(b.regiments[0]): b.hit(b.soldiers[id],9999,false)
	check(b.mods(b.regiments[3]).rate == 1 and b.mods(b.regiments[3]).armor == 0,'destroyed outer cannot grant permanent combination benefits')
	var blocked = Battle.new()
	place(blocked,1,Vector2(840,1140))
	var old = blocked.regiments.duplicate(true)
	check(not blocked.Combination.create(blocked,0,3),'collision rejects composite deployment')
	check(blocked.regiments == old,'rejected composite does not partially mutate either army')
	var circle = Battle.new(); circle.Combination.create(circle,0,3); circle.start()
	for r in circle.regiments: r.order = 'hold'
	circle.hit(circle.soldiers[0],9999,false)
	var slots = circle.soldiers.map(func(s): return s.slot)
	step(circle,1)
	check(circle.soldiers.map(func(s): return s.slot) == slots,'idle ring does not circulate vacancies without a reachable enemy')

func infantry():
	var b = fixture('shield',35)
	place(b,1,Vector2(1000,815))
	b.soldiers[3].cooldown = 0
	var rear = b.soldiers[31]; var before: Vector2 = rear.pos
	step(b,0.1)
	check(b.can_attack(b.soldiers[3]),'shield front can attack within short reach')
	check(not b.can_attack(rear) and rear.pos == before and rear.attack_age > 10,'rear shield neither chases nor attacks out of range')
	check(b.soldiers[35].hp < b.soldiers[35].max_hp,'front actually deals independent damage')
	var spear = fixture('spear',35)
	place(spear,1,Vector2(1000,815)); step(spear,0.1)
	check(spear.can_attack(spear.soldiers[10]) and not b.can_attack(b.soldiers[10]),'second spear rank reaches while shield rank cannot')
	b = fixture('shield',35)
	var positions = b.soldiers.map(func(s): return s.pos)
	b.hit(b.soldiers[3],999,false)
	b.Cohesion.refill(b,b.regiments[0])
	check(b.soldiers[10].slot == 3 and b.soldiers[17].slot == 10 and b.soldiers[24].slot == 17 and b.soldiers[31].slot == 24,'nearest idle back ranks fill one-by-one')
	check(b.soldiers[0].slot == 0 and b.regiments[0].offsets.size() == 35,'death never recenters unrelated soldiers')
	check(b.soldiers.map(func(s): return s.pos) == positions,'slot assignment does not teleport soldiers')
	step(b,0.3)
	check(b.soldiers[10].pos.distance_to(positions[3]) < positions[10].distance_to(positions[3]),'replacement walks into vacancy')
	b = fixture('shield',35)
	place(b,1,b.soldiers[10].pos+Vector2(25,0))
	var engaged = b.soldiers[10]; engaged.target = 35; engaged.cooldown = 0
	b.hit(b.soldiers[3],999,false); b.Cohesion.refill(b,b.regiments[0])
	check(engaged.slot == 10 and b.can_attack(engaged),'surrounded rear soldier prioritizes attack over filling front')
	check(b.members(b.regiments[0]).any(func(id): return b.soldiers[id].slot == 3),'another idle soldier fills that vacancy')
	var target = b.soldiers[35]; var hp: float = target.hp
	b.update(0.1)
	check(target.hp < hp and engaged.slot == 10,'engaged rear soldier actually attacks without leaving its slot')
	var cav = fixture('cavalry',7)
	place(cav,1,Vector2(1000,720))
	var p: Vector2 = cav.soldiers[3].pos
	step(cav,0.2)
	check(cav.soldiers[3].pos.y < p.y-10,'cavalry independently pursue nearby enemies')

func movement():
	for kind in ['shield','spear','archer','cavalry']:
		var b = fixture(kind,1)
		place(b,1,Vector2(1025,900)); b.soldiers[1].cooldown = 100
		var enemy_hp: float = b.soldiers[1].hp
		check(b.command([0],'move',Vector2(1250,900)),'forced move accepted '+kind)
		if kind == 'archer': check(not b.arrow_rain([0],b.soldiers[1].pos),'forced move also disables arrow rain')
		step(b,0.8)
		check(b.soldiers[1].hp == enemy_hp and b.soldiers[0].attack_age > 10 and not b.soldiers[0].charging,'forced movement cannot attack or charge '+kind)
		check(b.soldiers[0].pos.x > 1030,'forced movement continues past nearby enemy '+kind)
	var b = fixture('shield',7)
	place(b,1,Vector2(1210,900)); b.soldiers[7].hp = 500; b.soldiers[7].max_hp = 500; b.soldiers[7].cooldown = 100
	check(b.command([0],'attack_move',Vector2(1450,900)),'attack move accepted')
	step(b,5)
	check(b.soldiers[7].hp < 500 and b.regiments[0].order == 'attack_move','attack move engages enemies along route')
	# Leave a remote enemy alive so clearing the local encounter does not end the match.
	b.add_regiment('shield','enemy',Vector2(2200,400),1)
	b.hit(b.soldiers[7],9999,false)
	step(b,10)
	check(b.regiments[0].pos.distance_to(Vector2(1450,900)) < 5 and b.regiments[0].order == 'hold','attack move resumes and reaches original destination')
	for order in ['move','attack_move']:
		b = fixture('cavalry',35)
		b.regiments[0].form = 'wedge'; b.reform(b.regiments[0],true)
		check(b.command([0],order,Vector2(1250,1000)),'cavalry order accepted '+order)
		step(b,0.2)
		check(b.regiments[0].form == 'wedge','cavalry retain wedge before reaching destination '+order)
		step(b,10)
		check(b.regiments[0].form == 'default' and b.regiments[0].order == 'hold' and b.Cohesion.settled(b,b.regiments[0]),'all riders arrive then return to default '+order)
	b = fixture('shield',35)
	check(b.command([0],'move',Vector2(1150,950)),'full infantry move')
	step(b,5)
	check(b.Cohesion.settled(b,b.regiments[0]) and b.regiments[0].form == 'default','full infantry retain their formation at destination')
	# A straggler prevents the center alone from completing a move.
	b.regiments[0].order = 'move'; b.regiments[0].path = []
	b.soldiers[34].pos += Vector2(0,120)
	b.update(1.0/30)
	check(b.regiments[0].order == 'move','arrival waits for actual soldiers, not just the formation center')
	b = fixture('cavalry',7)
	place(b,1,Vector2(1210,900)); b.soldiers[7].hp = 3000; b.soldiers[7].max_hp = 3000; b.soldiers[7].cooldown = 100
	b.add_regiment('shield','enemy',Vector2(2200,400),1)
	b.command([0],'attack_move',Vector2(1500,1050)); step(b,2)
	check(b.soldiers[7].hp < 3000 and b.regiments[0].charge_cd == 0,'cavalry attack move pursues nearby enemies without automatically charging')
	b.hit(b.soldiers[7],9999,false); step(b,10)
	check(b.regiments[0].order == 'hold' and b.regiments[0].form == 'default' and b.Cohesion.settled(b,b.regiments[0]),'cavalry return to destination after local enemies are cleared')

func charge_fixture(enemy: String = 'shield'):
	var b = fixture('cavalry',7,enemy,7)
	place(b,0,Vector2(1000,900),Vector2.RIGHT)
	for i in 7:
		b.soldiers[7+i].pos = Vector2(1050+i*45,900)
		b.soldiers[7+i].cooldown = 100
	return b

func charges():
	var b = Battle.new(); var r = b.regiments[2]
	check(b.set_formation([2],'wedge'),'deploy wedge before planning charge')
	var before = b.soldiers.duplicate(true)
	check(b.command([2],'charge',Vector2(1960,650)) and r.charge_queued,'charge can be explicitly queued before battle')
	step(b,2)
	check(b.soldiers == before and r.charge_cd == 0,'queued charge does not move or consume cooldown during deployment')
	check(b.command([2],'hold') and not r.charge_queued,'H cancels queued charge')
	b.command([2],'charge',Vector2(1960,650)); b.start()
	check(r.charge_state == 'forming','battle start executes the queued order through formation assembly')
	step(b,0.5)
	check(b.regiments[6].charge_state == '' and b.regiments[6].charge_cd == 0,'enemy cavalry do not automatically charge at nearby targets')
	b = charge_fixture(); r = b.regiments[0]
	r.attack_bonuses = [5.0]; b.stats.shield.melee_armor = 1000
	check(b.command([0],'charge',Vector2(1500,900)),'explicit battlefield charge accepted')
	check(r.charge_cd == 0,'cooldown starts on actual launch, not during formation gathering')
	b.Charge.advance(b,r,b.alive('enemy'),0.1)
	check(r.charge_state == 'running' and r.charge_cd == 20,'launch starts regiment-wide twenty-second cooldown')
	var relative = b.members(r).map(func(id): return b.soldiers[id].pos-b.soldiers[3].pos)
	for i in 30:
		if r.charge_state != 'running': break
		b.Charge.advance(b,r,b.alive('enemy'),0.1)
		check(b.members(r).all(func(id): return (b.soldiers[id].pos-b.soldiers[3].pos).is_equal_approx(relative[id])),'all riders translate in one fixed formation')
	for i in 7: check(is_equal_approx(b.soldiers[7+i].max_hp-b.soldiers[7+i].hp,6.0),'all path contacts receive one third attack, including targets beyond four')
	check(b.soldiers[3].pos.is_equal_approx(Vector2(1500,900)) and r.charge_state == '','center soldier arrives at the clicked destination')
	check(not b.command([0],'charge',Vector2(1700,900)),'explicit charge still enforces cooldown')
	b.command([0],'move',Vector2(1500,1250)); step(b,19.8)
	check(r.charge_cd > 0,'twenty-second cooldown does not expire early')
	step(b,0.3)
	check(b.command([0],'charge',Vector2(1800,1250)),'explicit charge available after cooldown')
	b.command([0],'move',Vector2(1450,1200))
	check(r.charge_state == '' and b.members(r).all(func(id): return not b.soldiers[id].charging),'ordinary move cancels charge preparation')
	# Touching a spear is no longer itself a stop condition. Actual spear attacks are.
	b = charge_fixture('spear'); r = b.regiments[0]
	b.command([0],'charge',Vector2(1500,900))
	for i in 20: b.Charge.advance(b,r,b.alive('enemy'),0.1)
	check(b.soldiers[3].pos.is_equal_approx(Vector2(1500,900)),'unattacking spears do not use the deleted touch-to-stop rule')
	check(b.soldiers[13].hp == b.soldiers[13].max_hp-6,'spears use the same one-third path damage')
	b = charge_fixture('spear'); r = b.regiments[0]
	b.soldiers[7].cooldown = 0
	b.command([0],'charge',Vector2(1500,900)); b.update(1.0/30)
	check(b.soldiers[3].hp < b.soldiers[3].max_hp,'spear actually lands a normal attack on a charging rider')
	check(r.charge_state == '' and b.members(r).all(func(id): return not b.soldiers[id].charging),'spear hit interrupts the whole synchronized charge immediately')
	check(r.charge_cd > 19 and b.soldiers[3].pos.x < 1050,'interruption retains cooldown and stops before the target')
	b = charge_fixture(); r = b.regiments[0]
	b.command([0],'charge',Vector2(1500,900)); b.Charge.advance(b,r,b.alive('enemy'),0.1)
	b.hit(b.soldiers[3],1,false,'shield')
	check(r.charge_state == 'running','non-spear attacks do not interrupt charge')
	# A swept area covers near-path contacts, without repeat hits on later frames.
	b = charge_fixture(); r = b.regiments[0]
	b.soldiers[8].pos = Vector2(1050,915); b.soldiers[9].pos = Vector2(1050,1020)
	b.command([0],'charge',Vector2(1500,900))
	for i in 20: b.Charge.advance(b,r,b.alive('enemy'),0.1)
	check(b.soldiers[8].hp < b.soldiers[8].max_hp and b.soldiers[9].hp == b.soldiers[9].max_hp,'small area hits near a rider path but misses distant soldiers')
	b = charge_fixture(); r = b.regiments[0]; r.form = 'wedge'
	b.reform(r,true)
	b.command([0],'charge',Vector2(1500,900))
	for i in 20: b.Charge.advance(b,r,b.alive('enemy'),0.1)
	check(b.soldiers[7].wedge_debuff > 0 and b.soldier_mods(b.soldiers[7]).rate == 0.5 and b.soldier_mods(b.soldiers[7]).speed == 0,'first wedge control remains separate from damage calculation')
	check(b.regiments[1].broken > 0,'shield formation break remains separate from path damage')
	# The marker belongs to the central soldier even when the wedge centroid has no slot.
	check(b.soldiers[r.charge_anchor].pos.is_equal_approx(Vector2(1500,900)),'wedge center soldier, not geometric centroid, lands on marker')
	b = Battle.new(); before = b.regiments.duplicate(true)
	check(not b.command([2],'charge',Vector2(1550,300)) and b.regiments == before,'invalid full-formation lane is rejected atomically')
	b = charge_fixture(); step(b,2)
	check(b.regiments[0].charge_cd == 0 and not b.soldiers.any(func(s): return s.charging),'nearby enemies never automatically trigger a charge')

func ring_contact():
	var b = fixture('shield',35)
	b.phase = 'deploy'; b.regiments.clear(); b.soldiers.clear()
	b.add_regiment('shield','ally',Vector2(1000,1200),35)
	b.add_regiment('spear','ally',Vector2(1400,1250),35)
	b.add_regiment('shield','enemy',Vector2(1000,700),1)
	check(b.Combination.create(b,0,1),'contact fixture creates composite ring')
	b.start()
	for r in b.regiments: r.order = 'hold'
	var front = 0
	for id in b.members(b.regiments[0]):
		if b.soldiers[id].pos.y < b.soldiers[front].pos.y: front = id
	place(b,2,b.soldiers[front].pos+Vector2(0,-25))
	b.soldiers[70].hp = 10000; b.soldiers[70].max_hp = 10000
	b.soldiers[70].cooldown = 1000; b.soldiers[front].cooldown = 0
	var center: Vector2 = b.regiments[0].pos
	var heading: Vector2 = b.regiments[0].heading
	var rear: Vector2 = b.soldiers[(front+17)%35].pos
	b.command([0],'attack_move',center+Vector2(200,-400)); step(b,2)
	check(b.regiments[0].pos == center and b.regiments[1].pos == center,'touching ring stops both armies instead of walking through the enemy')
	check(b.soldiers[70].hp < 10000,'contact-facing soldiers actually attack')
	check(b.soldiers[(front+17)%35].pos == rear and b.soldiers[(front+17)%35].attack_age > 10,'out-of-range ring soldiers neither circle through enemies nor attack')
	check(b.regiments[0].heading == heading,'attack-move does not rotate the ring slot assignments')
	b.add_regiment('shield','enemy',Vector2(2200,400),1)
	b.hit(b.soldiers[70],99999,false); step(b,2)
	check(b.regiments[0].pos.y < center.y-30,'cleared contact lets composite ring resume its move')
	var positions = b.soldiers.map(func(s): return s.pos)
	check(b.Combination.dissolve(b,0),'ring can dissolve during battle')
	check(b.regiments[0].form == 'free' and b.regiments[1].form == 'free' and b.regiments[0].pair == -1 and b.regiments[1].pair == -1,'dissolve frees both armies and removes link')
	check(b.soldiers.map(func(s): return s.pos) == positions,'battle dissolution never teleports to deployment positions')
	check(b.mods(b.regiments[0]).armor == 0 and b.mods(b.regiments[0]).attack == 0 and b.mods(b.regiments[1]).rate == 1,'free mode removes both ring benefits and penalties')
	b.command([0,1],'move',Vector2(1200,1100))
	check(b.regiments[0].goal.distance_to(b.regiments[1].goal) >= 220,'dissolved concentric armies receive separate default formation destinations')

func free_attack():
	for kind in ['spear','shield','archer','cavalry']:
		var b = fixture(kind,7)
		b.regiments[0].form = {'spear':'scatter','shield':'testudo','archer':'dense','cavalry':'wedge'}[kind]
		var old: Vector2 = b.soldiers[3].pos
		check(b.enter_free([0]),'every type can enter free mode '+kind)
		check(b.mods(b.regiments[0]) == b.Formation.modifiers('default'),'free mode has neither formation bonuses nor penalties '+kind)
		check(not b.set_formation([0],'default'),'free mode cannot directly select a formation '+kind)
		step(b,0.5)
		check(b.soldiers[3].pos.distance_to(b.soldiers[7].pos) < old.distance_to(b.soldiers[7].pos),'free soldier pursues its nearest enemy '+kind)
		check(b.regiments[0].charge_cd == 0,'free attack does not auto-charge '+kind)
		var order = 'attack_move' if kind in ['spear','cavalry'] else 'move'
		check(b.command([0],order,Vector2(1100,1000)),'move command leaves free mode '+kind)
		check(b.regiments[0].form == 'default' and b.regiments[0].regrouping,'move first gathers a default formation '+kind)
		check(not b.set_formation([0],'default'),'other formations locked until actual regrouping '+kind)
		step(b,10)
		check(not b.regiments[0].regrouping and b.Cohesion.settled(b,b.regiments[0]),'regroup completes with actual soldiers at slots '+kind)
		if kind != 'cavalry': check(b.set_formation([0],'scatter'),'formations unlock after default is assembled '+kind)
	var edge = fixture('shield',35)
	edge.enter_free([0])
	for id in edge.members(edge.regiments[0]): edge.soldiers[id].pos = Vector2(2330,1200)
	edge.regiments[0].pos = edge.centroid(edge.regiments[0])
	check(edge.command([0],'move',Vector2(1900,1100)),'dispersed army at map edge can be ordered to regroup')
	step(edge,15)
	check(not edge.regiments[0].regrouping and edge.Cohesion.settled(edge,edge.regiments[0]),'regrouping near map edge never assigns impossible outside-map slots')
