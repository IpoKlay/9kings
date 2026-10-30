extends RefCounted
## Shared setup through the current destination -> infantry combat -> post-victory cards flow.
static func choose_supply(c) -> bool:
	if c.g.phase!='reward': return false
	var id=c.offers()[0]
	if not c.choose(id): return false
	if c.g.phase!='place': return true
	for cell in c.g.unlocked_cells:
		var building=c.building_at(cell)
		if building==null or (building.type==id and building.level<3): return c.place(cell)
	return false

static func deploy(app) -> bool:
	if app.expedition.state.opening=='destination': app.travel_to(app.expedition.destinations()[0])
	if app.campaign.g.phase=='battle': return true
	if not choose_supply(app.campaign): return false
	app.render_ui()
	return app.campaign.g.phase=='battle'

# Flow tests skip presentation explicitly; test_departure.gd exercises the whole animation.
static func finish_departure(app):
	if is_instance_valid(app.departure): app.departure.finish_immediately()
