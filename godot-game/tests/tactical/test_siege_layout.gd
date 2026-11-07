extends SceneTree
const Battle=preload('res://scripts/tactical/siege_battle.gd')
func _initialize():
	var r=Battle.new();var wall=r.structures[3]
	var edited=Vector2(1050,1100)
	var u=r.alive('ally').filter(func(a):return a.kind=='legion')[0]
	var nav=r.Soldiers.navigator(r,u.kind,u)
	var moved=OS.get_cmdline_user_args().has('moved')
	var expected=edited if moved else Vector2(1050,900)
	var scene=r.Fort.instantiate();var node=scene.get_node('Wall4')
	var checks=[(r.projection.affine_inverse()*wall.rect.get_center()).is_equal_approx(expected),
		node.position.is_equal_approx(r.projection*expected),
		not r.terrain.clear_segment(nav,expected,expected),
		r.Structures.at(r,expected).get('id','')=='Wall4']
	if moved:
		checks.append(r.terrain.clear_segment(nav,Vector2(1050,900),Vector2(1050,900)))
		checks.append(r.Structures.at(r,Vector2(1050,900)).is_empty())
		var route=r.terrain.leg(nav,Vector2(1050,1400),Vector2(1050,700))
		checks.append(not route.is_empty() and route.size()>1)
		var from=Vector2(1050,1400)
		for to in route:
			checks.append(r.terrain.clear_segment(nav,from,to));from=to
	var failures=checks.count(false)
	scene.free()
	print('Siege authored layout: ',checks.size(),' checks, ',failures,' failures, moved=',moved)
	quit(1 if failures else 0)
