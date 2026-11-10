extends SceneTree
func _init():
	var r=load('res://scripts/strategy/battle.gd').new(false)
	var nav=r.Soldiers.navigator(r,'guard',r.alive('ally')[5])
	var terrain=r.terrain
	for method in ['indexed','linear']:
		var begin=Time.get_ticks_usec();var hits=0
		for i in 20000:
			var a=Vector2(1000+i%1000,2000+i%900);var b=a+Vector2(.5,.5)
			if method=='indexed':
				if terrain.clear_segment(nav,a,b):hits+=1
			else:
				var clear=true
				for wall in terrain.clearances[nav]:
					if terrain.crosses(wall,a,b):clear=false;break
				if clear:hits+=1
		print(method,' ms=',(Time.get_ticks_usec()-begin)/1000.,' hits=',hits)
	quit()
