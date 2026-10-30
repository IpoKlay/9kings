extends SceneTree
var checks=0
var failures=0
func check(value: bool,message: String):
	checks+=1
	if not value:
		failures+=1
		printerr('FAIL: '+message)
func _init(): call_deferred('run')
func run():
	var scene=load('res://scenes/main.tscn').instantiate()
	scene.main_menu=false # Boot menu is covered separately.
	root.add_child(scene)
	current_scene=scene
	scene.sound.enabled=false
	scene.travel_to(scene.expedition.destinations()[0]);scene.campaign.finish(true);scene.advance()
	await create_timer(.5).timeout
	var hand=scene.card_hand
	hand.input_enabled=false
	check(hand.slots.size()==3,'Three cards in hand')
	var overlap=hand.CARD_SIZE.x-hand.STEP
	check(overlap>0 and overlap<hand.CARD_SIZE.x*.1,'Only slight edge overlap')
	for i in 3:
		var point=hand.slots[i].origin+Vector2(120,130)
		check(hand.hit_at(point)==i,'Each resting card can be selected')
	var boundary=hand.slots[1].origin+Vector2(2,150)
	var owner=hand.hit_at(boundary)
	hand.set_active(0,false)
	await create_timer(.3).timeout
	check(hand.hit_at(boundary)==owner,'Animated edge must not steal adjacent hit region')
	check(hand.slots[0].card.z_index>hand.slots[1].card.z_index,'Hovered card drawn above neighbours')
	check(is_equal_approx(hand.slots[0].card.scale.x,1.40),'Hover reaches intended scale')
	var raised=hand.slots[0].card.get_transform()*Vector2(120,25)
	check(hand.hit_at(raised)==0,'Raised card remains clickable above original footprint')
	for i in 30: hand.set_active(i%3,false)
	hand.set_active(1,false)
	await create_timer(.3).timeout
	for i in 3:
		check(hand.slots[i].card.scale.is_equal_approx(Vector2.ONE*(1.40 if i==1 else 1)),'Rapid switching leaves only one enlarged card')
	scene.open_dialog('settings')
	await process_frame
	check(not hand.can_interact() and hand.active==-1,'Modal blocks cards and returns raised card')
	scene.close_dialog()
	hand.input_enabled=true
	check(hand.can_interact(),'Cards become interactive after closing settings')
	var ids=scene.campaign.offers()
	scene.choose_card(ids[0])
	scene.choose_card(ids[1])
	check(scene.input_locked,'Selection animation locks repeat input')
	await create_timer(.3).timeout
	check(scene.campaign.g.chosen==ids[0],'Repeated commit requests award exactly the first card')
	check(not scene.input_locked and scene.campaign.g.phase!='reward','Selection finishes and unlocks next phase')
	for group in scene.sound.card_files.values():
		for i in group[1]:
			var path='res://assets/cards/'+group[0]+'-'+str(i+1)+'.ogg'
			var sample=load(path)
			check(sample!=null and sample.get_length()>0,'Paper recording decodes: '+path)
	scene.sound.stop()
	print('%s card interaction / audio checks, %s failures'%[checks,failures])
	quit(1 if failures else 0)
