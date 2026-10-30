extends SceneTree
## Native paper UI: real pointer input, archive navigation and one-time rewards.
var app
var checks=0
var failures=0
const RPGUI=preload('res://scripts/rpg_ui.gd')
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		printerr('FAIL: '+message)
func click(control: Control):
	var pos=control.get_global_rect().get_center()
	for pressed in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=pos;event.global_position=pos
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		root.push_input(event,true)
	await process_frame
func escape():
	var event=InputEventKey.new();event.keycode=KEY_ESCAPE;event.pressed=true
	root.push_input(event,true)
	await process_frame
func capture(id: String):
	if DisplayServer.get_name()=='headless': return
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png('res://../output/rpg-ui-integration/'+id+'.png')
func run():
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='res://../output/rpg-ui-integration/test-settings.cfg'
	root.add_child(app);current_scene=app
	app.set_process(false);app.sound.enabled=false
	for language in ['zh','en']:
		app.language=language;app.world.language=language
		app.restart_expedition(1)
		app.expedition_map.atlas.overview()
		await capture('map-'+language)
		app.expedition_map.select_city('246349')
		await capture('intel-'+language)
		check(app.expedition_map.info.size==Vector2(430,462),'City panel stays compact')
		var camera=app.expedition_map.atlas.center
		var zoom=app.expedition_map.atlas.zoom
		var state=app.expedition.state.duplicate(true)
		var army=app.campaign.g.duplicate(true)
		await click(app.expedition_map.info.get_node('HistoryButton'))
		check(app.dialog_kind=='archive','History button opens native book')
		await capture('archive-'+language)
		await click(app.modal.get_child(1).get_node('ArchiveRegion_3'))
		check(app.documents.archive_region==3,'External book tab accepts pointer input')
		check(int(app.expedition.nodes[app.documents.archive_city].act)==3,'Region tab filters cities')
		var previous=app.documents.archive_city
		await click(app.modal.get_child(1).get_node('ArchiveNext'))
		check(app.documents.archive_city!=previous or app.documents.archive_page>0,'Next page advances')
		await click(app.modal.get_child(1).get_node('ArchivePrevious'))
		check(app.documents.archive_city==previous,'Previous page returns')
		await escape()
		check(app.dialog_kind=='' and not app.expedition_map.history_open,'Escape closes only archive')
		check(app.expedition_map.atlas.center==camera and app.expedition_map.atlas.zoom==zoom,'Archive preserves camera and zoom')
		check(app.expedition.state==state and app.campaign.g==army,'Reading preserves route and army')
		app.documents.open_archive('727070')
		await click(app.modal.get_child(1).get_node('ArchiveClose'))
		check(app.expedition_map.selected=='246349','Archive browsing preserves selected city')
		app.expedition_map.select_city('727070')
		check(app.expedition_map.travel_button.disabled and not app.expedition.known('727070'),'History never reveals distant enemy intel or travel')
		app.expedition_map.select_city('246349')
		await click(app.expedition_map.travel_button)
		preload('res://tests/expedition_test_support.gd').finish_departure(app)
		check(app.dialog_kind=='' and app.expedition.state.opening=='done' and app.campaign.g.phase=='battle','Opening destination leads directly to infantry battle')
		check(preload('res://tests/expedition_test_support.gd').deploy(app),'First card launches combat')
		var peaceful_count=0
		while peaceful_count<2:
			if app.campaign.g.phase=='battle':
				app.campaign.finish(true)
				app.render_ui();app.open_dialog('result')
				var before=app.expedition.state.visited.size()
				await capture('report-'+language)
				await click(app.modal.get_child(1).get_node('ReportContinue'))
				check(app.expedition.state.visited.size()==before+1,'Report settles exactly one city')
				var settled=app.expedition.state.duplicate(true)
				app.advance()
				check(app.expedition.state==settled,'Repeated report action cannot duplicate progress')
				app.skip_supply();app.open_map()
			var next=app.expedition.next(app.expedition.state.current)[0]
			# Leave room to prove the original peaceful stop restores one life.
			if app.expedition.nodes[next].roster==null: app.campaign.g.defense=1
			app.travel_to(next)
			if app.dialog_kind=='event':
				peaceful_count+=1
				await capture('event-'+language)
				var recovery=int(app.expedition.nodes[next].kind in app.expedition.travel_rules.recovery_kinds)
				check(app.documents.event_recovered==recovery and app.campaign.g.defense==1+recovery,'Peaceful stop uses existing recovery rules')
				var visited_state=app.expedition.state.duplicate(true)
				var reward_state=app.campaign.g.duplicate(true)
				check(not app.card_hand.can_interact(),'Event blocks underlying cards')
				app.travel_to(next)
				check(app.expedition.state==visited_state and app.campaign.g==reward_state,'Modal blocks duplicate visits')
				if language=='zh': await click(app.modal.get_child(1).get_node('EventConfirm'))
				else: await escape()
				check(app.dialog_kind=='' and app.card_hand.can_interact(),'Confirm or Escape restores original supply cards')
				check(app.campaign.g==reward_state,'Acknowledgment adds no second reward')
				app.skip_supply();app.open_map()
				check(not app.expedition.can_travel(next),'Peaceful stop cannot be revisited for rewards')
				check(app.campaign.g.phase=='prepare' and app.expedition.state.mode=='map','Supply returns to expedition map')
		await capture('progress-'+language)
	for id in app.ui_preset.rpg_regions:
		check(RPGUI.texture(id)==RPGUI.texture(id),'Cropped texture cached: '+id)
		check(RPGUI.texture(id).get_size()==app.ui_preset.rpg_regions[id].size*app.ui_preset.rpg_scales[id],'Integer pixel scale: '+id)
	for id in app.ui_preset.rpg_margins:
		check(RPGUI.box(id)==RPGUI.box(id),'Nine-slice style cached: '+id)
	app.sound.stop()
	print('%d native RPG UI checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
