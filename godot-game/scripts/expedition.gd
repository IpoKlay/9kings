extends RefCounted
## Native expedition state. The existing campaign remains the sole army/combat owner.
var campaign
var language = 'zh'
const Catalog=preload('res://scripts/data/catalog.gd')
var assault: Dictionary=Catalog.data('balance/assaults')
var travel_rules: Dictionary=Catalog.data('balance/expedition_rules')
var march_paths: Dictionary=Catalog.data('generated/march_paths').edges
var march_choices: Dictionary=Catalog.data('content/march_choices')
var doctrines: Dictionary=Catalog.data('balance/enemy_doctrines')
var original_data=Catalog.expedition()
var data = original_data.duplicate(true)
var stage_order: Array = [1,2,3]
var nodes: Dictionary = {}
var state: Dictionary

func _init(current_campaign):
	campaign = current_campaign
	for n in data.nodes: nodes[n.id] = n
	reset()

func reset(first_act: int = 1):
	configure_route(clampi(first_act,1,3))
	state=Catalog.new_state('expedition')
	state.current=data.start
	state.visited=[data.start]
	campaign.g.phase = 'prepare'
	campaign.g.erase('expedition_wave')


func configure_route(first_act: int):
	data=original_data.duplicate(true)
	stage_order=[first_act,first_act%3+1,(first_act+1)%3+1]
	nodes.clear()
	var entries={}
	var goals={}
	for n in data.nodes:
		nodes[n.id]=n
		if n.act==0: continue
		if n.step==1: entries[int(n.act)]=n.id
		if n.step==data.steps_per_act:
			goals[int(n.act)]=n.id
			n.kind='boss'
		# Difficulty follows stage position, not which coast was randomly drawn.
		var stage=stage_order.find(int(n.act))+1
		n.stage=stage
		if n.roster!=null:
			for template in original_data.nodes:
				if int(template.act)==stage and template.step==n.step and template.lane==n.lane:
					n.roster=template.roster.duplicate() if template.roster!=null else n.roster
					break
			if stage==1 and assault.early_roster_limits.has(str(int(n.step))):
				n.roster=n.roster.slice(0,int(assault.early_roster_limits[str(int(n.step))]))
			# Stage sets force size; geography sets tactics, even with a rotated start.
			var doctrine=doctrine_id(n.id)
			if doctrine not in ['patrol','peace']:
				var pattern=doctrines.profiles[doctrine].roster
				for index in n.roster.size(): n.roster[index]=pattern[index%pattern.size()]
	data.edges=data.edges.filter(func(edge):return nodes[edge[0]].act==nodes[edge[1]].act)
	data.edges.append([data.start,entries[first_act]])
	data.goals=[]
	for index in stage_order.size():
		data.goals.append(goals[stage_order[index]])
		if index<2: data.edges.append([goals[stage_order[index]],entries[stage_order[index+1]]])
	data.final=goals[stage_order.back()]
	nodes[data.final].kind='final'

func battlefield_act() -> int:
	var id=state.target if state.target!='' else state.current
	return stage_order[0] if nodes[id].act==0 else int(nodes[id].act)

func completed_steps() -> int:
	return state.visited.size()-1

func current_act() -> int:
	var n = nodes[state.current]
	if n.kind == 'home': return stage_order[0]
	var index=stage_order.find(int(n.act))
	return stage_order[index+1] if n.kind=='boss' and index<2 else int(n.act)

func act_progress(act: int) -> int:
	var total = 0
	for id in state.visited:
		if int(nodes[id].act)==act: total+=1
	return total

func act_text(act: int,field: String = 'name') -> String:
	return data.acts[act-1][field if language=='zh' else field+'_en']

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
			if id==state.current and state.locked_target!='' and successor!=state.locked_target: continue
			if not out.has(successor):
				out[successor] = out[id]+1
				queue.append(successor)
	return out

func march_mode(from: String,to: String) -> String:
	return march_paths[from+'>'+to].mode

func choice_text(id: String) -> String:
	var branch=march_choices.get(state.current,{})
	return branch.get('choices',{}).get(id,{}).get(language,'')

func doctrine_id(id: String) -> String:
	var n=nodes[id]
	if n.roster==null: return 'peace'
	if n.stage==doctrines.intro_stage and n.step<=doctrines.intro_last_step: return 'patrol'
	if doctrines.sites.has(id): return doctrines.sites[id]
	var regional=doctrines.theaters[str(int(n.act))]
	return regional[(int(n.step)-1)%regional.size()]

func doctrine_text(id: String,field: String) -> String:
	return loc('routeintel.'+doctrine_id(id)+'.'+field)

func response_cards(id: String) -> Dictionary:
	var candidates=doctrines.profiles.get(doctrine_id(id),{}).get('answers',['legion'])
	var owned=[]
	for card in candidates:
		var active=false
		if campaign.types.has(card): active=campaign.g.buildings.any(func(b):return b.type==card)
		elif campaign.cards[card].kind=='Battle order': active=campaign.order_rank(card)>0
		else:
			active=campaign.rank(card)>0
			for required in campaign.cards[card].get('requires',[]):
				active=active and campaign.g.buildings.any(func(b):return b.type==required)
		if active: owned.append(card)
	return {'owned':owned,'suggested':candidates}

func response_text(id: String) -> String:
	if doctrine_id(id)=='peace': return doctrine_text(id,'advice')
	var response=response_cards(id)
	var available=not response.owned.is_empty()
	var names=[]
	for card in (response.owned if available else response.suggested).slice(0,2):
		names.append(campaign.card_copy(card,language).name)
	return loc('routeintel.owned' if available else 'routeintel.missing')%(' / '.join(names))

func briefing() -> Dictionary:
	if state.finished: return {}
	var source=departure_port() if state.opening=='destination' else state.current
	if state.locked_target!='': return {'source':source,'choices':[state.locked_target],'ahead':false,'merge':''}
	var cursor=source
	# Scout one city ahead, so the preceding reward can prepare for a fork.
	for depth in 2:
		if march_choices.has(cursor):
			var branch=march_choices[cursor]
			return {'source':cursor,'choices':branch.choices.keys(),'ahead':depth>0,'merge':branch.merge}
		var successors=next(cursor)
		if successors.size()!=1 or nodes[successors[0]].act!=nodes[source].act: break
		cursor=successors[0]
	return {'source':source,'choices':destinations(),'ahead':false,'merge':''}

func route_hint(view_act: int) -> String:
	if view_act!=current_act(): return loc('route.preview')%act_text(view_act)
	if state.locked_target!='': return loc('route.forward')%[node_text(state.current),node_text(state.locked_target)]
	if campaign.g.phase!='prepare' or state.finished: return notice_text()
	var source=departure_port() if state.opening=='destination' else state.current
	var options=destinations()
	if march_choices.has(source):
		return loc('route.branch')%[node_text(source),options.size(),node_text(march_choices[source].merge)]
	if options.is_empty(): return notice_text()
	var key='route.port' if nodes[source].act!=nodes[options[0]].act else 'route.forward'
	return loc(key)%[node_text(source),node_text(options[0])]

func preview_edges(id: String) -> Array:
	var result=[]
	if not can_travel(id): return result
	var source=departure_port() if state.opening=='destination' else state.current
	result.append(source+'>'+id)
	var merge=march_choices.get(source,{}).get('merge',id)
	var cursor=id
	while cursor!=merge and next(cursor).size()==1:
		var successor=next(cursor)[0]
		result.append(cursor+'>'+successor)
		cursor=successor
	return result

func known(id: String) -> bool:
	return id in state.visited or distances().get(id,99) <= travel_rules.scouting_distance

func can_travel(id: String) -> bool:
	return campaign.g.phase == 'prepare' and not state.reward_due and not state.finished and state.target == '' and id in destinations() and (state.locked_target == '' or state.locked_target == id)

func departure_port() -> String:
	return next(data.start)[0]

func destinations() -> Array:
	# The friendly departure port is transit, not a second opening card stop.
	return next(departure_port()) if state.opening=='destination' else next(state.current)

func encounter(id: String) -> Dictionary:
	if not nodes.has(id) or nodes[id].roster == null: return {}
	var n = nodes[id]
	var progress = (int(n.stage)-1)*int(data.steps_per_act)+int(n.step)
	var strength = assault.strength[n.kind]
	var count = int(assault.waves[n.kind]) if n.kind in ['boss','final','elite'] else int(assault.waves.early) if n.step<=assault.early_step_max else int(assault.waves.normal)
	var waves: Array = []
	for index in count:
		var roster = n.roster.duplicate()
		# Keep opening scouting accurate; subsequent waves alternate tactical pressure.
		if index>0:
			var variants = assault.early_variants if progress<assault.early_progress_threshold else assault.later_variants
			var doctrine=doctrine_id(id)
			if doctrine not in ['patrol','peace']:
				variants=doctrines.profiles[doctrine].relief
				# Keep the defining second squad in small two-squad assaults.
				roster[0 if roster.size()==2 else roster.size()-1]=variants[(index-1)%variants.size()]
			else: roster[roster.size()-1] = variants[(index-1)%variants.size()]
		# Long assaults alternate relief waves with pressure waves instead of repeating
		# the former one-off boss at full strength ten times.
		var pressure = 1.0 if index==0 or index==count-1 else assault.relief_pressure if index%2==1 else assault.mid_pressure
		var ramp = (1.0+assault.wave_growth*mini(index,int(assault.growth_wave_cap)))*pressure
		var opening_health = assault.health_factor.boss if count==assault.waves.boss else assault.health_factor.elite if count==assault.waves.elite else assault.health_factor.normal
		waves.append({'roster':roster,
			'health':(1.0+assault.health_per_progress*maxi(0,progress-int(assault.progress_growth_start)))*strength*opening_health*ramp,
			'attack':(1.0+assault.attack_per_progress*maxi(0,progress-int(assault.progress_growth_start)))*strength*(assault.relief_attack_multiplier if pressure<assault.relief_attack_threshold else 1.0)})
	var result = waves[0].duplicate(true)
	result.name = node_text(id,'title')
	result.waves = waves
	return result

func reward_text(id: String) -> String:
	var n = nodes[id]
	if n.kind == 'home': return loc('expedition.starting_legion_infantry_archers_and_catapults')
	if state.opening=='destination' and id==departure_port(): return loc('expedition.passed_en_route_to_the_first_battle_no_separate')
	if n.kind == 'final': return loc('expedition.complete_the_campaign_unite_the_mediterranean')
	if n.kind == 'elite':return loc('routeintel.elite')
	return (loc('expedition.legion_life_1_max_3') if n.kind in travel_rules.recovery_kinds else '')+loc('expedition.choose_1_of_3_building_doctrine_or_order')

func arrive(id: String):
	state.current = id
	state.visited.append(id)
	state.target = ''
	state.locked_target = ''
	state.finished = id == data.final
	if nodes[id].kind in travel_rules.recovery_kinds:
		campaign.g.defense = mini(int(campaign.camp.max_lives),int(campaign.g.defense)+int(travel_rules.recovery_lives))

func supply():
	campaign.g.round += 1
	campaign.g.phase = 'reward'
	campaign.g.pending = null
	campaign.g.chosen = null
	campaign.g.battle = null
	campaign.g.erase('expedition_wave')
	campaign.g.reward_context='elite' if nodes[state.current].kind=='elite' else ''
	campaign.g.reward_rerolls=1 if campaign.g.reward_context=='elite' else 0
	state.reward_due = true
	state.mode = 'camp'

func travel(id: String) -> bool:
	if not can_travel(id): return false
	var n = nodes[id]
	if n.roster != null:
		var first_battle = state.opening=='destination'
		if first_battle: arrive(departure_port())
		campaign.g.expedition_wave = encounter(id)
		state.target = id
		state.locked_target = id
		if first_battle:
			state.opening = 'done'
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
	campaign.g.temporary_orders={}
	campaign.g.armyShield = false
	campaign.g.armyTestudo = false
	campaign.g.chosen = null
	campaign.g.pending = null
	campaign.g.battle = null
	campaign.g.erase('expedition_wave')
	state.target = ''
	if won:
		campaign.record_capture()
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
		if state.opening=='card':
			state.opening = 'done'
			state.mode = 'battle'
			return campaign.start()
		state.mode = 'camp'
		return true
	return false

func tx(zh: String,en: String) -> String:
	return zh if language=='zh' else en

func node_text(id: String,field: String = 'name') -> String:
	return nodes[id][field] if language=='zh' else nodes[id][field+'_en']

func notice_text() -> String:
	if state.opening=='destination':
		return loc('expedition.choose_the_highlighted_first_destination_pick_one_starting_card')
	if state.opening=='card':
		return loc('expedition.opening_deployment_pending_return_to_deployment_choose_a_card')
	if campaign.g.phase in ['result','defeat']:
		return loc('expedition.battle_complete_open_view_report_at_the_top_right')
	if campaign.g.phase == 'battle':
		return loc('expedition.battle_suspended_select_back_to_battle_at_the_top')
	if campaign.g.phase == 'place':
		return loc('expedition.building_placement_pending_return_to_camp_and_finish_building')
	if campaign.g.phase == 'reward':
		return loc('expedition.supplies_pending_return_to_camp_and_choose_a_card')
	var city = node_text(state.notice_city) if state.notice_city!='' else ''
	match state.notice:
		'visit': return city+' · '+node_text(state.notice_city,'title')+loc('expedition.supplies_ready_choose_your_next_destination')
		'captured': return loc('expedition.s_secured_your_army_buildings_and_permanent_doctrines_carry')%city
		'victory': return loc('expedition.victory_the_eagle_reaches_s_the_mediterranean_is_united')%node_text(data.final)
		'defeat': return loc('expedition.attack_repelled_life_1_no_reward_you_may_attack')%city
	return loc('expedition.the_legion_is_ready_choose_s_to_begin_the')%node_text(next(data.start)[0])

func loc(id: String) -> String:
	return Catalog.text(id,language)

func can_reorganize() -> bool:
	return state.notice=='defeat' and state.locked_target!='' and campaign.g.phase=='prepare' and state.locked_target not in campaign.g.recovery_used

func reorganize() -> bool:
	if not can_reorganize():return false
	campaign.g.recovery_used.append(state.locked_target)
	campaign.g.reward_context='recovery';campaign.g.reward_rerolls=0
	campaign.g.offered=['shield','testudo','rally'];campaign.g.offerYear=campaign.g.round
	campaign.g.phase='reward';state.reward_due=true;state.mode='camp'
	return true
