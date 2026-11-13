extends RefCounted

const RunStore = preload('res://scripts/data/run_store.gd')
const DATA = 'res://data/content/cassius.json'
const VERSION = 1
var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
var state: Dictionary

func _init():
	reset()

func reset():
	state = {
		'version': VERSION, 'intro': 0, 'region': 'south', 'visits': ['south'],
		'goods': spec.starting_goods.duplicate(), 'growth': [], 'ledger': [],
		'choices': {}, 'omens': {}, 'battles': {}, 'orders': 0, 'fatigue': 0,
		'ended': false, 'ending': '', 'winter_food': 0,
	}

func region(id: String = '') -> Dictionary:
	var key = state.region if id.is_empty() else id
	for row in spec.regions:
		if row.id == key: return row
	return {}

func count(id: String) -> int:
	return int(state.goods.get(id, 0))

func add(goods: Dictionary):
	for id in goods:
		state.goods[id] = count(id) + int(goods[id])

func pay(id: String, cost: int) -> bool:
	if count(id) < cost: return false
	state.goods[id] = count(id) - cost
	return true

func record(line: String):
	state.ledger.append('%s · %s'%[region().name, line])

func price(offer: Dictionary) -> int:
	return int(offer.price) - (2 if 'trade' in state.growth else 0)

func buy(offer: Dictionary) -> bool:
	if state.ended or offer not in spec.goods or not pay('gold', price(offer)): return false
	add({offer.id: int(offer.count)})
	record('购买%s，支付 %d 王印币。'%[offer.name, price(offer)])
	return true

func sell(id: String) -> bool:
	if state.ended or not spec.sale_prices.has(id) or not pay(id, 1): return false
	add({'gold': spec.sale_prices[id]})
	record('交出%s，换得 %d 王印币。'%[spec.items[id], spec.sale_prices[id]])
	return true

func grow(node: Dictionary) -> bool:
	if state.ended or node not in spec.growth or node.id in state.growth: return false
	if node.parent != '' and node.parent not in state.growth: return false
	if not pay('gold', int(node.cost)): return false
	state.growth.append(node.id)
	record('军营完成%s，支付 %d 王印币。'%[node.name, int(node.cost)])
	return true

func decide(kind: String) -> bool:
	if state.ended or state.choices.has(state.region) or kind not in ['promise','levy','leave']: return false
	var land = region()
	state.choices[state.region] = kind
	match kind:
		'promise':
			add(land.grant)
			record('接受帮助。承诺：'+land.promise)
		'levy':
			add(land.levy)
			state.orders += 1
			record('依文书征收。当地人承担了过冬的风险。')
		'leave':
			state.fatigue += 1
			record('留下当地物资，队伍空手出发，疲惫 +1。')
	return true

func fulfill(id: String) -> bool:
	var land = region(id)
	if state.ended or state.choices.get(id) != 'promise' or not pay(land.settle, int(land.cost)): return false
	state.choices[id] = 'kept'
	record('兑现给%s的承诺，交付 %d %s。'%[land.name, int(land.cost), spec.items[land.settle]])
	return true

func omen(offer: String) -> bool:
	if state.ended or state.omens.has(state.region): return false
	var land = region()
	var cost = 1
	var answer = ''
	match offer:
		'ox': answer = '祭司看见雾中的号角，却无法辨明敌军的位置。白牛已经献出，前路仍需谨慎。'
		'ring': answer = '帝国要三份祭品才会发粮。交出祭器和密录，也会让沿途的旧约更难兑现。'
		'local':
			offer = land.offering
			cost = int(land.offering_cost)
			answer = land.omen
		_: return false
	if not pay(offer,cost): return false
	if offer == land.settle and offer in ['relic','record'] and state.choices.get(state.region) == 'promise':
		state.choices[state.region] = 'kept'
	state.omens[state.region] = answer
	record('祭献 %d %s。%s'%[cost,spec.items[offer],answer])
	return true

func routes() -> Array:
	if state.visits.size() >= int(spec.chapters): return []
	var available = spec.regions.filter(func(row): return row.id not in state.visits)
	return available if state.visits.size()==1 else available.slice(0,2)

func travel_cost(land: Dictionary) -> int:
	return int(land.travel) - (1 if 'supply' in state.growth else 0)

func travel(id: String) -> bool:
	var land = region(id)
	if state.ended or not state.choices.has(state.region) or land not in routes(): return false
	var cost = travel_cost(land)
	var missing = maxi(0, cost-count('food'))
	state.goods.food = maxi(0, count('food')-cost)
	state.fatigue += missing
	state.region = id
	state.visits.append(id)
	record('抵达%s。消耗 %d 口粮，缺粮疲惫 +%d。'%[land.place, cost-missing, missing])
	return true

func avoid_battle() -> bool:
	if state.ended or state.battles.has(state.region): return false
	var cost = 2 - (1 if 'scout' in state.growth else 0)
	if not pay('food',cost): return false
	state.battles[state.region] = 'detour'
	record('以 %d 份口粮绕开岗哨。'%cost)
	return true

func battle_result(won: bool):
	if state.ended or state.battles.has(state.region): return
	state.battles[state.region] = 'won' if won else 'lost'
	if won:
		add(spec.battle_reward)
		state.orders += 1
		record('夺得通行文书和战利品。王印币 +12，口粮 +2，象牙与旧短剑各一。')
	else:
		state.fatigue += 2
		record('队伍从战场撤回，未获得补给，疲惫 +2。')

func tribute_available() -> int:
	return int(state.orders) + count('relic') + count('record') + count('ox')

func finish(kind: String) -> bool:
	if state.ended or not routes().is_empty() or not state.choices.has(state.region): return false
	if kind == 'rite':
		if tribute_available() < 3: return false
		var due = 3 - mini(3, int(state.orders))
		for id in ['ox','relic','record']:
			if due > 0 and pay(id,1): due -= 1
		state.winter_food = count('food') + 8
		record('交齐三份祭品，帝国拨下八份军粮。未兑现的承诺仍记在账上。')
	elif kind == 'home':
		state.winter_food = count('food') + (6 if 'relief' in state.growth else 0)
		record('保留现有物资回援要塞，放弃帝国的大祭配额。')
	else: return false
	var care = mini(int(state.winter_food),floori(float(state.fatigue)*.5))
	if care > 0:
		state.winter_food -= care
		record('照料疲惫的队伍用去 %d 份口粮。'%care)
	state.ending = kind
	state.ended = true
	return true

func load_run(path: String) -> bool:
	for file_path in [path,path+'.bak']:
		var file = ConfigFile.new()
		if file.load(file_path) != OK: continue
		var value = file.get_value('run','state',{})
		if valid(value):
			state = value
			return true
	return false

func valid(value) -> bool:
	if not value is Dictionary or not value.has_all(state.keys()) or value.version != VERSION: return false
	if not value.region is String or value.region.is_empty() or region(value.region).is_empty() or not RunStore.finite_values(value): return false
	for key in ['goods','choices','omens','battles']:
		if not value[key] is Dictionary: return false
	for key in ['visits','growth','ledger']:
		if not value[key] is Array: return false
	if not value.ended is bool or value.ending not in ['','rite','home']: return false
	if not RunStore.whole(value.intro,0,spec.intro.size()) or value.visits.is_empty() or value.visits.size() > int(spec.chapters) or value.visits.back() != value.region: return false
	for id in value.visits:
		if region(id).is_empty(): return false
	for id in spec.items:
		if not RunStore.whole(value.goods.get(id),0,1000000): return false
	for key in ['orders','fatigue','winter_food']:
		if not RunStore.whole(value[key],0,1000000): return false
	return true

func save_run(path: String) -> Error:
	if path.is_empty(): return OK
	var file = ConfigFile.new()
	file.set_value('run','state',state)
	var error = file.save(path+'.tmp')
	if error != OK: return error
	var previous = ConfigFile.new()
	if previous.load(path) == OK and valid(previous.get_value('run','state',{})):
		error = DirAccess.copy_absolute(path,path+'.bak')
		if error != OK: return error
	return DirAccess.rename_absolute(path+'.tmp',path)
