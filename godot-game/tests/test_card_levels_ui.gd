extends SceneTree
var app
var checks=0
var failures=0
func _init():call_deferred('run')
func check(ok,message):
	checks+=1
	if not ok:failures+=1;printerr('FAIL: '+message)
func run():
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/private/tmp/eagle-card-levels.cfg'
	root.add_child(app);current_scene=app;app.set_process(false);app.sound.enabled=false
	app.restart_expedition(1);app.expedition_map.settle_entry()
	app.travel_to(app.expedition.destinations()[0])
	for language in ['zh','en']:
		app.language=language
		for level in range(1,4):
			for id in app.campaign.cards:
				if app.campaign.cards[id].get('retired',false):continue
				app.campaign.g.upgrades[id]=level-1
				app.card_hand=null;app.remove_children(app.ui);app.card_button(id,0)
				await process_frame
				var card=app.ui.get_child(0)
				for child in card.get_children():
					if child is Label:
						var rect:Rect2=app.CardFace.TEXT_RECTS[String(child.name)]
						check(child.position.y+child.size.y<=rect.end.y+.1 and child.position.x+child.size.x<=rect.end.x+.1,'Level copy fits '+id+' '+language+' '+str(level)+' '+str(child.name))
				check(card.get_node('CardKind').get_line_count()==1,'Rank badge stays on one line '+id+' '+language+' '+str(level))
				check(card.tooltip_text==app.campaign.card_copy(id,language).detail,'Full mechanics remain available in tooltip')
	app.sound.stop();print('%d three-level card UI checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
