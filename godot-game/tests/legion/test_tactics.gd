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
	check(not b.set_formation([2],'wedge') and not b.Combination.create(b,1,0) and not b.Combination.dissolve(b,0),'wedge and combination are prebattle only')
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
	for id in cav.regiments[0].members: cav.soldiers[id].charge_cd = 20
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
	check(b.soldiers[7].hp < 3000 and b.members(b.regiments[0]).any(func(id): return b.soldiers[id].charge_cd > 0),'cavalry attack move breaks ranks to charge a nearby enemy')
	b.hit(b.soldiers[7],9999,false); step(b,10)
	check(b.regiments[0].order == 'hold' and b.regiments[0].form == 'default' and b.Cohesion.settled(b,b.regiments[0]),'cavalry return to destination after local enemies are cleared')

func charge_fixture(kind: String = 'shield', wedge: bool = false):
	var b = fixture('cavalry',1,kind,5)
	place(b,0,Vector2(900,800),Vector2.RIGHT)
	b.regiments[0].form = 'wedge' if wedge else 'default'
	for i in 5: b.soldiers[i+1].pos = Vector2(950+i*45,800)
	return b

func charges():
	var b = charge_fixture()
	var rider = b.soldiers[0]
	check(b.Charge.begin(b,rider,b.soldiers[1]) and rider.charge_cd == 20,'charge starts a twenty-second cooldown')
	b.Charge.advance(b,rider,b.alive('enemy'),1.0)
	var expected = [36.0,18.0,9.0,4.5,0.0]
	for i in 5: check(is_equal_approx(b.soldiers[i+1].max_hp-b.soldiers[i+1].hp,expected[i]),'swept charge damage factor at victim '+str(i+1))
	check(rider.charge_hits.size() == 4 and not rider.charging and rider.pos.x <= 1085,'four targets stop penetration before fifth')
	check(not b.Charge.begin(b,rider,b.soldiers[5]),'cannot restart a charge during cooldown')
	b.regiments[0].order = 'move'; b.regiments[0].path = [Vector2(900,1200)]
	step(b,19.9)
	check(rider.charge_cd > 0,'charge cooldown cannot expire early')
	step(b,0.2)
	b.regiments[0].order = 'hold'; b.soldiers[5].pos = rider.pos+Vector2(100,0)
	check(b.Charge.begin(b,rider,b.soldiers[5]),'new charge available after twenty seconds')
	b = charge_fixture('spear')
	rider = b.soldiers[0]; b.Charge.begin(b,rider,b.soldiers[1]); b.Charge.advance(b,rider,b.alive('enemy'),1)
	check(b.soldiers[1].max_hp-b.soldiers[1].hp == 18 and rider.charge_hits.size() == 1 and not rider.charging,'spears receive exactly one multiplier and immediately stop penetration')
	check(b.soldiers[2].hp == b.soldiers[2].max_hp and rider.pos.x <= 950,'no charging through the spear regiment')
	b = charge_fixture('shield',true)
	rider = b.soldiers[0]; b.Charge.begin(b,rider,b.soldiers[1]); b.Charge.advance(b,rider,b.alive('enemy'),1)
	check(b.soldiers[1].max_hp-b.soldiers[1].hp == 18 and b.soldiers[2].max_hp-b.soldiers[2].hp == 18,'wedge first and second hits each use one multiplier')
	for i in 4:
		check(b.soldier_mods(b.soldiers[i+1]).rate == 0.5 and b.soldier_mods(b.soldiers[i+1]).speed == 0,'first wedge charge halves attack speed and roots each victim')
	var frozen: Vector2 = b.soldiers[1].pos
	b.soldiers[1].wedge_debuff = 4; b.regiments[1].order = 'auto'
	b.update(0.1)
	check(b.soldiers[1].pos == frozen,'rooted foot soldier cannot be moved by formation or collision')
	rider.charge_cd = 0; b.Charge.stop(rider)
	place(b,0,Vector2(900,800),Vector2.RIGHT)
	for i in 5:
		b.soldiers[i+1].pos = Vector2(950+i*45,800); b.soldiers[i+1].wedge_debuff = 0
	b.Charge.begin(b,rider,b.soldiers[1]); b.Charge.advance(b,rider,b.alive('enemy'),1)
	check(b.soldiers[1].wedge_debuff == 0,'later wedge charge does not repeat first-charge control')
	b = charge_fixture()
	b.regiments[0].attack_bonuses = [4.0]; b.regiments[0].charge_bonuses = [0.2,0.3]
	b.regiments[1].form = 'testudo'
	var old_offsets = b.regiments[1].offsets.duplicate()
	b.Charge.begin(b,b.soldiers[0],b.soldiers[1]); b.Charge.advance(b,b.soldiers[0],b.alive('enemy'),1)
	check(b.soldiers[1].max_hp-b.soldiers[1].hp == 54,'charge uses additive charge buffs and ignores normal buffs and armor')
	check(b.mods(b.regiments[1]).armor == 0 and b.mods(b.regiments[1]).speed == 0.38,'charge strips testudo benefit while retaining slow')
	check(b.regiments[1].form == 'testudo' and b.regiments[1].offsets == old_offsets,'formation break preserves its positions')
	b.regiments[1].broken = 0
	check(b.mods(b.regiments[1]).armor == 1.8,'formation benefits return when temporary break expires')
	b = charge_fixture()
	b.soldiers[2].pos = Vector2(950,815)
	b.soldiers[3].pos = Vector2(950,835)
	b.Charge.begin(b,b.soldiers[0],b.soldiers[1]); b.Charge.advance(b,b.soldiers[0],b.alive('enemy'),0.2)
	check(b.soldiers[2].hp < b.soldiers[2].max_hp and b.soldiers[3].hp == b.soldiers[3].max_hp,'small swept charge area hits nearby targets, not distant neighbors')
