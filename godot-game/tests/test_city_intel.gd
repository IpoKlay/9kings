extends SceneTree
## Check the actual shaped labels and controls across scouts, visits and full rosters.
const OUT='res://../output/city-intel-polish/'
var app
var checks=0
var failures=0

func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		printerr('FAIL: '+message)

func click(control: Control):
	for pressed in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=control.get_global_rect().get_center();event.global_position=event.position
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		root.push_input(event,true)
	await process_frame

func capture(id: String):
	if DisplayServer.get_name()=='headless': return
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	var image=root.get_texture().get_image()
	image.save_png(OUT+id+'.png')
	var scale=float(image.get_width())/1920.0
	var rect=Rect2i(Vector2(1458,522)*scale,Vector2(452,484)*scale)
	var detail=image.get_region(rect)
	detail.resize(detail.get_width()*2,detail.get_height()*2,Image.INTERPOLATE_NEAREST)
	detail.save_png(OUT+id+'-detail.png')

func check_panel(id: String):
	var panel=app.expedition_map.info
	var footer=panel.get_node('HistoryButton')
	var travel=panel.get_node('Travel')
	check(panel.size==Vector2(430,462),'Compact map footprint '+id)
	check(footer.position.y==travel.position.y and footer.size.y==travel.size.y,'Aligned actions '+id)
	check(travel.disabled!=app.expedition.can_travel(id),'Real route permissions '+id)
	for child in panel.get_children():
		if child is Label:
			check(Rect2(Vector2(20,12),Vector2(390,382)).encloses(child.get_rect()),'Text stays in reading area '+id+' '+child.text)
			check(child.get_minimum_size().y<=child.size.y+.1,'All wrapped text visible '+id+' '+child.text)
			check(child.get_theme_font('font')==app.font,'Existing pixel font '+id)
		elif child is Button:
			check(child.size.y>=44,'Full pointer target '+id)
			var face=child.get_theme_stylebox('normal')
			var width=child.size.x-face.get_content_margin(SIDE_LEFT)-face.get_content_margin(SIDE_RIGHT)
			check(app.font.get_string_size(child.text,HORIZONTAL_ALIGNMENT_LEFT,-1,child.get_theme_font_size('font_size')).x<=width+.1,'Button label fits '+id+' '+child.text)
	var labels=panel.get_children().filter(func(c):return c is Label)
	for i in labels.size():
		for j in range(i+1,labels.size()):
			check(not labels[i].get_rect().intersects(labels[j].get_rect()),'Reading regions do not overlap '+id+' '+str(labels[i].name)+' / '+str(labels[j].name))

func run():
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/private/tmp/eagle-city-intel-test.cfg'
	root.add_child(app);current_scene=app
	app.set_process(false);app.sound.enabled=false
	for language in ['en','zh']:
		app.language=language;app.world.language=language
		app.restart_expedition(1)
		app.expedition_map.settle_entry()
		app.expedition_map.select_city('246349')
		await capture('intel-'+language+'-720')
		check(app.expedition_map.info.get_node('CitySubtitle').text!=app.expedition_map.info.get_node('CityTitle').text,'No duplicate English city name')
		# Actual native buttons still open the archive and close the panel.
		var route_before=app.expedition.state.duplicate(true)
		await click(app.expedition_map.info.get_node('HistoryButton'))
		check(app.dialog_kind=='archive','History opens native book')
		app.close_dialog()
		check(app.expedition.state==route_before,'History preserves route state')
		await click(app.expedition_map.info.get_node('CloseInfo'))
		check(app.expedition_map.selected=='','Close dismisses panel')
		# Read all known destinations, including five-type rosters and recovery rewards.
		app.expedition.state.opening=''
		for n in app.expedition.data.nodes:
			app.expedition.state.visited.append(n.id)
		for n in app.expedition.data.nodes:
			app.expedition_map.select_city(n.id)
			await process_frame
			check_panel(n.id+'')
		app.expedition_map.select_city('727070')
		await capture('full-roster-'+language)
		app.expedition_map.select_city('148127')
		await capture('peaceful-'+language)
		app.restart_expedition(1);app.expedition_map.settle_entry()
		app.expedition_map.select_city('727070')
		await process_frame
		check_panel('727070')
		check(not app.expedition_map.info.has_node('IntelStats'),'Unknown cities hide combat multipliers')
		check(app.expedition_map.info.get_node('RewardText').text==app.loc('expedition_map.not_yet_scouted'),'Unknown cities hide rewards')
		await capture('unknown-'+language)
		if DisplayServer.get_name()!='headless':
			root.size=Vector2i(1920,1080)
			app.expedition_map.select_city('246349')
			await capture('intel-'+language+'-1080')
			root.size=Vector2i(1280,720)
	print('City intel: %d checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
