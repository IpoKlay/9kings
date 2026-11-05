extends SceneTree
const Rules=preload('res://scripts/tactical/trial_rules.gd')
const Field=preload('res://scripts/tactical/trial_field.gd')
var output='res://../output/myth-cast-integration/'
func _initialize():call_deferred('run')
func run():
 var main=load('res://scenes/main.tscn').instantiate()
 main.run_path_override='user://myth-cast-verification-absent.json'
 root.add_child(main)
 await process_frame
 var before=main.campaign.g.duplicate(true)
 main.language='zh'
 main.open_tactical_trial()
 await process_frame
 var trial=root.get_child(root.get_child_count()-1)
 assert(trial.rules.characters.size()==14)
 assert(trial.character_ids.filter(func(id):return id!='').size()==14)
 for row in trial.rules.characters:
  trial.retry()
  trial.rules.deploy('legion',Vector2(650,420))
  trial.rules.deploy('archer',Vector2(380,650))
  trial.rules.start()
  trial.character_picker.item_selected.emit(trial.character_ids.find(row.id))
  assert(trial.rules.deity==row.id and trial.selected=='lightning')
  assert(trial.portrait.texture!=null)
  var hp=trial.rules.alive('enemy')[1].hp
  var click=InputEventMouseButton.new()
  click.button_index=MOUSE_BUTTON_LEFT
  click.pressed=true
  click.position=trial.field.project(Vector2(650,420) if row.id=='athena' else Vector2(1160,545))
  click.global_position=click.position
  root.push_input(click,true)
  click=click.duplicate()
  click.pressed=false
  root.push_input(click,true)
  await process_frame
  await process_frame
  trial.paused=true
  var casts=trial.field.effects.filter(func(e):return e.get('character','')==row.id)
  assert(casts.size()==1,'Input did not create cast: '+row.id)
  var cast=casts[0]
  assert(cast.kind!='earthquake')
  if row.preview_only:assert(trial.rules.alive('enemy')[1].hp==hp)
  var frames: SpriteFrames=trial.field.animations[row.id]
  assert(frames.get_frame_count('action')==6)
  for i in 6:
   cast.age=i/6.0+.08
   assert(trial.field.apparition_frame(cast.age)==i)
   trial.field.queue_redraw()
   await process_frame
   await RenderingServer.frame_post_draw
   if DisplayServer.get_name()!='headless':
    root.get_texture().get_image().save_png(output+row.id+'-frame-'+str(i)+'.png')
  cast.age=.65
  trial.field.queue_redraw()
  await process_frame
  assert(cast.age==.65,'Pause advanced animation')
  trial.paused=false
  for i in 30:assert(trial.rules.strike(Vector2(500,600)))
  assert(trial.rules.cooldown==0 and trial.rules.charges==2)
  trial.rules.events.clear()
  trial.field.advance(10)
  assert(trial.field.effects.is_empty())
  assert(not trial.rules.strike(Vector2(-1,-1)))
  print('CAST PASS ',row.id,' 6 frames, pointer cast, pause, no cooldown, cleanup')
 # Verify the real dropdown opens without deploying or casting underneath.
 trial.paused=true
 var count=trial.rules.units.size()
 var menu_click=InputEventMouseButton.new()
 menu_click.button_index=MOUSE_BUTTON_LEFT
 menu_click.pressed=true
 menu_click.position=trial.character_picker.get_global_rect().get_center()
 root.push_input(menu_click,true)
 await process_frame
 assert(trial.character_picker.get_popup().visible)
 assert(trial.rules.units.size()==count)
 trial.character_picker.get_popup().hide()
 trial.retry()
 assert(trial.field.effects.is_empty() and trial.rules.waves.is_empty())
 trial.closed.emit()
 await process_frame
 assert(main.visible and main.campaign.g==before)
 main.queue_free()
 await process_frame
 print('ALL 14 CASTS + CAMPAIGN ISOLATION PASS')
 quit()
