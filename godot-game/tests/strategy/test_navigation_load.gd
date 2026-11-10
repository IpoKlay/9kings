extends SceneTree
const Battle=preload('res://scripts/strategy/battle.gd')
func _init():
	var r=Battle.new(false)
	var ids=[]
	for i in 63:
		var u=r.spawn_person('shield','ally',Vector2(1120+(i%9)*42,2200+(i/9)*38))
		ids.append(Vector2i(u.id,0))
	var start=Time.get_ticks_usec()
	var accepted=r.Soldiers.command(r,ids,'move',Vector2(1450,2030))
	var ms=(Time.get_ticks_usec()-start)/1000.
	start=Time.get_ticks_usec()
	for i in 120:r.step(1./60);r.events.clear()
	print('NAV_LOAD accepted=',accepted,' order_ms=',ms,' step_ms=',(Time.get_ticks_usec()-start)/120000.)
	quit()
