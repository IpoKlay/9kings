extends RefCounted

static func candidates(b, outer_id: int) -> Array:
	if b.phase != 'deploy' or outer_id < 0: return []
	var outer: Dictionary = b.regiments[outer_id]
	if outer.kind not in ['spear','shield'] or outer.pair >= 0: return []
	return b.regiments.filter(func(r): return r.id != outer_id and r.side == outer.side and r.kind in ['spear','archer'] and r.pair < 0 and not b.members(r).is_empty()).map(func(r): return r.id)

static func create(b, outer_id: int, inner_id: int) -> bool:
	if inner_id not in candidates(b,outer_id): b.report = '组合需要未组合的枪兵或持盾步兵作为外环，枪兵或弓兵作为内环。'; return false
	var outer: Dictionary = b.regiments[outer_id]; var inner: Dictionary = b.regiments[inner_id]
	var radius = maxf(100,maxi(b.members(outer).size(),b.members(inner).size())*29.0/TAU)
	var margin = Vector2.ONE*(radius+12)
	var center: Vector2 = outer.pos.clamp(b.DEPLOYMENT.position+margin,b.DEPLOYMENT.end-margin)
	var outer_points = b.Formation.offsets(b.members(outer).size(),'ring',radius)
	var inner_points = b.Formation.offsets(b.members(inner).size(),'ring_inner',radius-26.0)
	var plans = [ {'r':outer,'pos':center,'heading':outer.heading,'offsets':outer_points}, {'r':inner,'pos':center,'heading':outer.heading,'offsets':inner_points} ]
	if not b.valid_layouts(plans,[outer_id,inner_id]): b.report = '组合环阵空间不足，请先移动外侧军团。'; return false
	for r in [outer,inner]: r.pair_home = {'pos':r.pos,'heading':r.heading,'form':r.form}
	outer.pair = inner.id; inner.pair = outer.id
	outer.form = 'ring'; inner.form = 'ring_inner'; outer.radius = radius; inner.radius = radius-26.0
	for r in [outer,inner]:
		r.pos = center; r.goal = center; r.heading = outer.heading; b.reform(r,true)
	b.report = '组合完成：外环包裹内环。选中任一军团即可共同下令。'
	return true

static func dissolve(b, id: int) -> bool:
	if b.phase != 'deploy' or b.regiments[id].pair < 0: return false
	var a: Dictionary = b.regiments[id]; var c: Dictionary = b.regiments[a.pair]
	var plans = []
	for r in [a,c]:
		var home: Dictionary = r.pair_home
		plans.append({'r':r,'pos':home.pos,'heading':home.heading,'offsets':b.Formation.offsets(b.members(r).size(),home.form)})
	if not b.valid_layouts(plans,[a.id,c.id]): b.report = '原部署位置被占用，请先移开其他军团，再解除组合。'; return false
	for r in [a,c]:
		r.pos = r.pair_home.pos; r.goal = r.pos; r.heading = r.pair_home.heading; r.form = r.pair_home.form
		r.pair = -1; r.pair_home = {}; b.reform(r,true)
	b.report = '已解除组合，两支军团恢复组合前的部署。'
	return true

static func expand(b, ids: Array) -> Array:
	var result = []
	for id in ids:
		if id < 0 or id >= b.regiments.size(): continue
		var r: Dictionary = b.regiments[id]
		if not b.members(r).is_empty() and id not in result: result.append(id)
		if r.pair >= 0 and r.pair not in result and not b.members(b.regiments[r.pair]).is_empty(): result.append(r.pair)
	return result

static func leader(b, r: Dictionary) -> Dictionary:
	if r.form == 'ring_inner' and r.pair >= 0 and not b.members(b.regiments[r.pair]).is_empty(): return b.regiments[r.pair]
	return r
