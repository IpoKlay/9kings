extends Control
## Presentation owns the input lock; the existing travel operation commits exactly once.
const Catalog=preload('res://scripts/data/catalog.gd')
const RPGUI=preload('res://scripts/rpg_ui.gd')
const Walk=preload('res://assets/unit_legion_ally_walk.png')
const Idle=preload('res://assets/unit_legion_ally_idle.png')
const Raised=preload('res://assets/unit_legion_ally_testudo.png')
const Flag=preload('res://assets/ui_roman/legion_flag.png')
const Ship=preload('res://assets/expedition/sea_life/ship_red.tres')
const Directions=['East','SouthEast','South','SouthWest','West','NorthWest','North','NorthEast']
var preset: Dictionary=Catalog.presentation('atlas').departure
var app
var map
var target=''
var phase='rally'
var age=0.0
var elapsed=0.0
var committed=false
var finished=false
var reduced=false
var battle=false
var legs: Array=[]
var length=0.0
var march_seconds=1.0
var pose=Vector2.ZERO
var heading=Vector2.RIGHT
var sailing=false
var coverage=0.0
var last_pose=-1
var last_cloud=-1
var last_step=-1
var cloud_view: SubViewport
var cloud_image: TextureRect
var cloud_field: Node2D
var caption: Label
var skip_hint: Label

func begin(id: String):
	target=id;map=app.expedition_map
	app.input_locked=true
	reduced=RPGUI.reduced_motion()
	battle=app.expedition.nodes[id].roster!=null
	size=app.size;z_index=100;mouse_filter=Control.MOUSE_FILTER_STOP
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	map.settle_entry()
	map.selected=id;map.render()
	map.info.hide()
	map.content.get_node('RouteLegend').hide()
	var exp=app.expedition
	var stops=[exp.state.current,id]
	if exp.state.opening=='destination': stops.insert(1,exp.departure_port())
	var bounds=Rect2(map.atlas.anchors[stops[0]],Vector2.ONE)
	for i in range(1,stops.size()):
		for p in exp.march_paths[stops[i-1]+'>'+stops[i]].points: bounds=bounds.expand(Vector2(p[0],p[1]))
	map.atlas.zoom=clampf(minf((size.x-400)/(bounds.size.x+240),(size.y-460)/(bounds.size.y+240)),map.atlas.minimum_zoom(),map.atlas.preset.focus_max_zoom)
	map.atlas.center=bounds.get_center();map.atlas.layout()
	map.atlas.legion_flag.hide();map.atlas.queue_redraw()
	for i in range(1,stops.size()):
		var key=stops[i-1]+'>'+stops[i]
		var route=map.atlas.draw_routes.filter(func(r):return r.key==key)[0]
		var curve=Curve2D.new()
		for p in route.points:
			if curve.point_count==0 or curve.get_point_position(curve.point_count-1).distance_squared_to(p)>0.01: curve.add_point(p)
		var distance=curve.get_baked_length()
		legs.append({'curve':curve,'length':distance,'sea':route.sea})
		length+=distance
	march_seconds=clampf(length/preset.march_pixels_per_second,preset.march_min_seconds,preset.march_max_seconds)
	caption=app.label(self,'',Vector2(400,895),Vector2(1120,52),28,Color('#ffedbc'))
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	skip_hint=app.label(self,app.loc('journey.skip'),Vector2(600,954),Vector2(720,38),20,Color('#d8d8bb'))
	skip_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	for l in [caption,skip_hint]:
		var plate=StyleBoxFlat.new();plate.bg_color=Color('#102b31ed');plate.anti_aliasing=false
		l.add_theme_stylebox_override('normal',plate)
	cloud_view=SubViewport.new();cloud_view.size=preset.cloud_size;cloud_view.transparent_bg=true
	cloud_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(cloud_view)
	cloud_field=preload('res://scripts/pixel_cloud_field.gd').new()
	cloud_view.add_child(cloud_field)
	cloud_image=TextureRect.new();cloud_image.texture=cloud_view.get_texture();cloud_image.size=size
	cloud_image.mouse_filter=Control.MOUSE_FILTER_IGNORE;cloud_image.z_index=1;cloud_image.hide();add_child(cloud_image)
	if reduced: phase='cover' if battle else 'rally'
	update_pose(0.0)
	caption.text=app.loc('journey.rally')%exp.node_text(target)
	app.sound.play_rally()

func update_pose(fraction: float):
	var remaining=length*clampf(fraction,0,1)
	var leg=legs[-1]
	for candidate in legs:
		leg=candidate
		if remaining<=leg.length: break
		remaining-=leg.length
	remaining=clampf(remaining,0,leg.length)
	pose=leg.curve.sample_baked(remaining).snapped(Vector2.ONE*2)
	heading=(leg.curve.sample_baked(minf(leg.length,remaining+2))-leg.curve.sample_baked(maxf(0,remaining-2))).normalized()
	sailing=phase!='rally' and leg.sea and map.sea.is_water(map.atlas.world_at(pose))

func set_cover(value: float):
	coverage=clampf(value,0,1)
	cloud_image.visible=coverage>0
	cloud_field.set_progress(coverage,phase=='reveal',reduced)
	cloud_view.render_target_update_mode=SubViewport.UPDATE_ONCE

func advance_phase(next: String):
	phase=next;age=0;last_pose=-1;last_cloud=-1

func _process(delta):
	step(delta)

func step(delta: float):
	if finished: return
	age+=delta;elapsed+=delta
	match phase:
		'rally':
			if age>=preset.rally_seconds:
				if reduced: commit();complete();return
				advance_phase('march')
		'march':
			update_pose(age/march_seconds)
			if not sailing and int(age/.32)!=last_step:
				last_step=int(age/.32);app.sound.play('foot',.6)
			caption.text=app.loc('journey.sea' if sailing else 'journey.land')%app.expedition.node_text(target)
			if age>=march_seconds:
				if not battle: commit();complete();return
				caption.text=app.loc('journey.arrival')%app.expedition.node_text(target)
				advance_phase('cover')
		'cover':
			var duration=preset.reduced_seconds if reduced else preset.cover_seconds
			var progress=clampf(age/duration,0,1)
			if int(elapsed*preset.cloud_fps)!=last_cloud or progress==1:
				last_cloud=int(elapsed*preset.cloud_fps)
				set_cover(1-pow(1-progress,3))
			if progress==1: advance_phase('covered')
		'covered':
			# At least one fully opaque rendered frame precedes the scene change.
			if age>=preset.covered_seconds:
				commit();advance_phase('reveal');caption.hide();skip_hint.hide()
		'reveal':
			var duration=preset.reduced_seconds if reduced else preset.reveal_seconds
			var progress=clampf(age/duration,0,1)
			if int(elapsed*preset.cloud_fps)!=last_cloud or progress==1:
				last_cloud=int(elapsed*preset.cloud_fps)
				set_cover(1-progress)
			if progress==1: complete();return
	var frame=int(elapsed*preset.pose_fps)
	if frame!=last_pose: last_pose=frame;queue_redraw()

func commit():
	if committed or finished: return
	committed=true
	app.input_locked=false
	app.travel_to(target,false)
	app.input_locked=true

func finish_immediately():
	if finished: return
	commit();complete()

func complete():
	if finished: return
	finished=true;app.input_locked=false;app.departure=null
	app.accumulator=0
	hide();queue_free()

func cancel():
	if finished: return
	if not committed: map.render()
	complete()

func _exit_tree():
	if is_instance_valid(app) and app.departure==self:
		app.departure=null;app.input_locked=false

func _input(event):
	if finished: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE,KEY_ESCAPE,KEY_ENTER,KEY_KP_ENTER]: finish_immediately()
	if event is InputEventKey or event is InputEventMouse or event is InputEventGesture: get_viewport().set_input_as_handled()

func _draw():
	if finished or committed or legs.is_empty(): return
	if sailing:
		var facing=Directions[posmod(roundi(heading.angle()/(PI/4.0)),8)]
		var texture=Ship.get_frame_texture(facing,int(elapsed*5)%Ship.get_frame_count(facing))
		var dimensions=texture.get_size()*preset.ship_scale
		draw_texture_rect(texture,Rect2(pose-dimensions*.5,dimensions),false)
		return
	var direction=-1 if heading.x<0 else 1
	var tick=int(elapsed*preset.pose_fps)
	for i in 6:
		var offset=Vector2((i%3-1)*32,int(i/3.0)*24-8)
		var cheering=phase=='rally' and age>0.10+(i%3)*.035 and age<0.40+(i%3)*.035
		var texture=Raised if cheering else Walk if phase=='march' else Idle
		var frame=(tick+i*2)%16 if phase=='march' else 0
		var p=(pose+offset-Vector2(0,4 if cheering else 0)).snapped(Vector2.ONE*2)
		draw_set_transform(p,0,Vector2(direction,1)*preset.soldier_scale)
		draw_texture_rect_region(texture,Rect2(-32,-52,64,64),Rect2(frame*64,0,64,64))
	draw_set_transform(Vector2.ZERO)
	draw_texture_rect(Flag,Rect2((pose+Vector2(-60,-118)).snapped(Vector2.ONE*2),Vector2(72,72)),false)
