extends RefCounted
## Native expedition state. The existing campaign remains the sole army/combat owner.
var campaign
var language = 'zh'
var data = JSON.parse_string(FileAccess.get_file_as_string('res://data/expedition.json'))
var nodes: Dictionary = {}
var state: Dictionary

func _init(current_campaign):
	campaign = current_campaign
	for n in data.nodes: nodes[n.id] = n
	reset()

func reset():
	state = {'current':'423025','visited':['423025'],'target':'','locked_target':'',
		'mode':'camp','reward_due':true,'finished':false,
		'notice':'assembly','notice_city':''}
	campaign.g.erase('expedition_wave')

func next(id: String) -> Array:
	var choices: Array = []
	for edge in data.edges:
		if edge[0] == id: choices.append(edge[1])
	return choices

func distances() -> Dictionary:
	var out = {state.current:0}
	var queue: Array = [state.current]
	while not queue.is_empty():
		var id = queue.pop_front()
		for successor in next(id):
			if not out.has(successor):
				out[successor] = out[id]+1
				queue.append(successor)
	return out

func known(id: String) -> bool:
	return id in state.visited or distances().get(id,99) <= 2

func can_travel(id: String) -> bool:
	return campaign.g.phase == 'prepare' and not state.reward_due and not state.finished and state.target == '' and id in next(state.current) and (state.locked_target == '' or state.locked_target == id)

func encounter(id: String) -> Dictionary:
	if not nodes.has(id) or nodes[id].roster == null: return {}
	var n = nodes[id]
	var strength = {'battle':1.0,'elite':1.03,'boss':1.07,'final':1.15}[n.kind]
	return {'name':node_text(id,'title'),'roster':n.roster.duplicate(),'health':strength,'attack':strength}

func reward_text(id: String) -> String:
	var n = nodes[id]
	if n.kind == 'home': return tx('初始军团：军团兵、弓兵、投石车','Starting legion: infantry, archers and catapults')
	if n.kind == 'final': return tx('完成本局远征 · 地中海成为内海','Complete the campaign · Unite the Mediterranean')
	return (tx('军团生命 +1（上限3）\n','Legion life +1 (max 3)\n') if n.kind in ['port','elite','boss'] else '')+tx('补给三选一：建筑 / 教义 / 军令','Choose 1 of 3: building, doctrine or order')

func arrive(id: String):
	state.current = id
	state.visited.append(id)
	state.target = ''
	state.locked_target = ''
	state.finished = id == '727070'
	if nodes[id].kind in ['port','elite','boss']:
		campaign.g.defense = mini(3,int(campaign.g.defense)+1)

func supply():
	campaign.g.round += 1
	campaign.g.phase = 'reward'
	campaign.g.pending = null
	campaign.g.chosen = null
	campaign.g.battle = null
	campaign.g.erase('expedition_wave')
	state.reward_due = true
	state.mode = 'camp'

func travel(id: String) -> bool:
	if not can_travel(id): return false
	var n = nodes[id]
	if n.roster != null:
		campaign.g.expedition_wave = encounter(id)
		state.target = id
		state.locked_target = id
		state.mode = 'battle'
		return campaign.start()
	arrive(id)
	supply()
	state.notice = 'visit'
	state.notice_city = id
	return true

func settle() -> bool:
	if state.target == '' or campaign.g.phase != 'result' or campaign.g.battle == null or campaign.g.battle.report == null: return false
	var target = state.target
	var won = campaign.g.battle.report.won
	campaign.g.orders = {}
	campaign.g.armyShield = false
	campaign.g.armyTestudo = false
	campaign.g.chosen = null
	campaign.g.pending = null
	campaign.g.battle = null
	campaign.g.erase('expedition_wave')
	state.target = ''
	if won:
		arrive(target)
		state.notice = 'captured'
		state.notice_city = target
		if state.finished:
			campaign.g.phase = 'prepare'
			state.mode = 'map'
			state.notice = 'victory'
		else: supply()
	else:
		campaign.g.phase = 'prepare'
		state.mode = 'map'
		state.notice = 'defeat'
		state.notice_city = target
	return true

func finish_supply() -> bool:
	if state.reward_due and campaign.g.phase == 'prepare':
		state.reward_due = false
		state.mode = 'camp'
		return true
	return false

func tx(zh: String,en: String) -> String:
	return zh if language=='zh' else en

func node_text(id: String,field: String = 'name') -> String:
	return nodes[id][field] if language=='zh' else nodes[id][field+'_en']

func notice_text() -> String:
	if campaign.g.phase in ['result','defeat']:
		return tx('战斗已结束。点击右上角“查看战报”完成结算。','Battle complete. Open View report at the top right to settle the encounter.')
	if campaign.g.phase == 'battle':
		return tx('战斗已暂停。点击右上角“返回战场”继续。','Battle suspended. Select Back to battle at the top right to return.')
	if campaign.g.phase == 'place':
		return tx('建筑尚未放置。返回军营完成建造后继续远征。','Building placement pending. Return to camp and finish building before traveling.')
	if campaign.g.phase == 'reward':
		return tx('补给尚未领取。返回军营选择一张卡牌后继续远征。','Supplies pending. Return to camp and choose a card before traveling.')
	var city = node_text(state.notice_city) if state.notice_city!='' else ''
	match state.notice:
		'visit': return city+' · '+node_text(state.notice_city,'title')+tx('。整备完毕，选择下一站。','. Supplies ready. Choose your next destination.')
		'captured': return tx('已夺取%s。军团、建筑与永久教义继续随军。','%s secured. Your army, buildings and permanent doctrines carry over.')%city
		'victory': return tx('远征告捷。鹰旗抵达亚历山大里亚，地中海成为内海。','Victory! The eagle reaches Alexandria. The Mediterranean is united.')
		'defeat': return tx('进攻失利，生命 −1。未领取奖励；可再次进攻%s。','Attack repelled. Life −1; no reward. You may attack %s again.')%city
	return tx('军团在罗马集结完毕。选择马西利亚，展开地中海远征。','The legion is ready in Rome. Choose Massilia to begin the Mediterranean campaign.')
