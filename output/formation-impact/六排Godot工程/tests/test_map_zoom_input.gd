extends SceneTree
var view: SubViewport
var app
var checks=0
var failures=0
var previous_pointer=Vector2.ZERO
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func mouse(p: Vector2,pressed: bool,button: int=MOUSE_BUTTON_LEFT):
	var event=InputEventMouseButton.new();event.position=p;event.global_position=p
	event.pressed=pressed;event.button_index=button;view.push_input(event,true)
func move(p: Vector2,held: bool=false):
	var event=InputEventMouseMotion.new();event.position=p;event.global_position=p
	event.relative=p-previous_pointer;previous_pointer=p
	event.button_mask=MOUSE_BUTTON_MASK_LEFT if held else 0;view.push_input(event,true)
func check_wheel(atlas,p: Vector2,button: int,message: String):
	var before=atlas.zoom
	var expected=clampf(before*(1.18 if button==MOUSE_BUTTON_WHEEL_UP else 1.0/1.18),atlas.minimum_zoom(),atlas.preset.max_zoom)
	mouse(p,true,button);mouse(p,false,button)
	check(is_equal_approx(atlas.zoom,expected),message)
func run():
	var host=Window.new();root.add_child(host)
	view=SubViewport.new();view.size=Vector2i(1280,720)
	view.size_2d_override=Vector2i(1920,1080);view.size_2d_override_stretch=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;host.add_child(view)
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/private/tmp/eagle-map-zoom-input.cfg';view.add_child(app)
	app.set_process(false);app.sound.enabled=false;app.starting_theaters.assign([1]);app.start_game()
	var map=app.expedition_map;map.settle_entry()
	var atlas=map.atlas;atlas.set_process(false);atlas.zoom=.8;atlas.center=atlas.WORLD*.5;atlas.layout()
	await process_frame
	view.notify_mouse_entered()
	var p=Vector2.ZERO
	for y in range(200,800,40):
		for x in range(200,1400,40):
			var point=Vector2(x,y)
			if map.sea.is_water(atlas.world_at(point)) and map.sea.is_water(atlas.world_at(point+Vector2(40,0))) and not atlas.buttons.values().any(func(b):return b.visible and b.get_rect().grow(50).has_point(point)):
				p=point;break
		if p!=Vector2.ZERO: break
	check(p!=Vector2.ZERO,'Open water found away from controls and city icons')
	move(p);move(p+Vector2(20,0))
	check(not map.sea.gusts.is_empty() and atlas.sea_cache.direct,'Actual mouse movement activates the live sea layer')
	check_wheel(atlas,p+Vector2(20,0),MOUSE_BUTTON_WHEEL_UP,'Wheel zoom responds immediately after water ripples appear')
	for direct in [false,true,false,true]:
		atlas.sea_cache.refresh_if_needed(direct,not direct)
		check_wheel(atlas,p,MOUSE_BUTTON_WHEEL_UP,'Exactly one zoom-in step with live sea: '+str(direct))
		check_wheel(atlas,p,MOUSE_BUTTON_WHEEL_DOWN,'Exactly one zoom-out step with live sea: '+str(direct))
	var gesture=InputEventMagnifyGesture.new();gesture.position=p;gesture.factor=1.1
	var zoom=atlas.zoom;view.push_input(gesture,true)
	check(is_equal_approx(atlas.zoom,zoom*1.1),'Pinch zoom works above the live sea')
	var center=atlas.center
	mouse(p,true);move(p+Vector2(60,40),true);atlas._process(1.0/60.0);mouse(p+Vector2(60,40),false)
	check(atlas.center!=center and not atlas.holding and map.selected=='','Dragging and release remain responsive without selecting a city')
	var city=map.app.expedition.state.current
	atlas.focus_city(city);atlas.sea_cache.refresh_if_needed(true)
	var target=atlas.buttons[city].get_global_rect().get_center()
	check_wheel(atlas,target,MOUSE_BUTTON_WHEEL_DOWN,'Wheel zoom works over a city while the sea is live')
	target=atlas.buttons[city].get_global_rect().get_center()
	mouse(target,true);mouse(target,false)
	check(map.selected==city,'City click passes through the decorative live sea')
	atlas=map.atlas;atlas.set_process(false)
	zoom=atlas.zoom
	mouse(Vector2(6,400),true,MOUSE_BUTTON_WHEEL_UP)
	check(atlas.zoom==zoom,'Wheel outside the map border remains ignored')
	app.open_dialog('settings');zoom=atlas.zoom
	mouse(Vector2(960,540),true,MOUSE_BUTTON_WHEEL_UP)
	check(atlas.zoom==zoom,'Settings modal still blocks background map zoom')
	app.sound.stop();print('%d map zoom input checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
