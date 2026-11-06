extends SceneTree
const Clouds=preload('res://scripts/pixel_cloud_field.gd')
const OUT='res://../output/cloud-scatter-v2/'
var checks=0
var failures=0
func _init():call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;printerr('FAIL: '+message)
func render_image(view):
	for i in 2:await process_frame;RenderingServer.force_draw()
	return view.get_texture().get_image()
func signature(field):
	return field.clouds.map(func(c):return [c.center,c.size,c.drift,c.delay,c.end])
func run():
	if DisplayServer.get_name()=='headless':printerr('Native renderer required');quit(1);return
	root.size=Vector2i(960,540)
	var view=SubViewport.new();view.size=Vector2i(480,270);view.transparent_bg=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var preview=TextureRect.new();preview.texture=view.get_texture();preview.size=Vector2(960,540);preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;root.add_child(preview)
	var first=[]
	for seed_value in range(12):
		var field=Clouds.new();field.layout_seed=seed_value+701;view.add_child(field)
		var quadrants={};var widths={};var delays={};var rows={}
		for c in field.clouds:
			quadrants[Vector2i(1 if c.drift.x>0 else -1,1 if c.drift.y>0 else -1)]=true
			widths[c.size.x]=true;delays[snappedf(c.delay,.01)]=true;rows[roundi(c.center.y)]=true
		check(quadrants.size()==4,'Independent drift spans all four directions, seed '+str(seed_value))
		check(widths.size()>12 and delays.size()>8 and rows.size()>16,'Cloud size, phase and position are not a repeated tile row')
		if seed_value==0:first=signature(field)
		else:check(signature(field)!=first,'Different seeds change the layout')
		var nodes=field.get_child_count()
		field.set_progress(.55,true,false)
		check(field.clouds.all(func(c):return c.rect.position==c.rect.position.round() and c.rect.size==c.rect.size.round()),'Motion stays on whole viewport pixels')
		var moved=field.clouds.map(func(c):return c.rect.position)
		field.set_progress(.3,true,false)
		check(field.clouds.any(func(c):return c.rect.position!=moved[field.clouds.find(c)]),'Clouds actually drift while dispersing')
		check(field.get_child_count()==nodes,'Animation does not allocate additional cloud nodes')
		field.set_progress(.5,true,true)
		var positions=field.clouds.map(func(c):return c.rect.position)
		field.set_progress(.2,true,true)
		check(field.clouds.map(func(c):return c.rect.position)==positions,'Reduced motion fades stationary clouds')
		if seed_value in [0,4,11]:
			field.set_progress(1,false,false)
			var im=await render_image(view);var pixels=im.get_data();var opaque=true
			for i in range(3,pixels.size(),4):
				if pixels[i]!=255:opaque=false;break
			check(opaque,'Every pixel hides the scene swap, seed '+str(seed_value))
			im.save_png(OUT+'clouds-'+str(seed_value)+'-covered.png')
			field.set_progress(.45,true,false);im=await render_image(view)
			im.save_png(OUT+'clouds-'+str(seed_value)+'-scattered.png')
			var holes=[0,0,0];var solid=[0,0,0]
			for y in range(0,270,2):
				for x in range(0,480,2):
					var a=im.get_pixel(x,y).a;var third=int(x/160.0)
					if a<.1:holes[third]+=1
					if a>.8:solid[third]+=1
			check(holes.all(func(n):return n>50) and solid.all(func(n):return n>50),'Holes and lingering clouds coexist across the left, center and right')
			field.set_progress(0,true,false);im=await render_image(view);pixels=im.get_data();var clear=true
			for i in range(3,pixels.size(),4):
				if pixels[i]!=0:clear=false;break
			check(clear,'No cloud or backing rectangle remains after reveal')
		field.queue_free();await process_frame
	var repeat=Clouds.new();repeat.layout_seed=701;view.add_child(repeat)
	check(signature(repeat)==first,'Fixed visual seed reproduces a reported layout')
	view.queue_free();preview.queue_free();await process_frame
	print('%d pixel cloud scatter checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
