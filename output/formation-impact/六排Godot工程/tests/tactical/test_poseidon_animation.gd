extends SceneTree
const Field=preload('res://scripts/tactical/trial_field.gd')
func _initialize():
 var field=Field.new()
 var frames: SpriteFrames=field.animations.poseidon
 assert(frames.get_frame_count('action')==6)
 for i in 6:
  assert(field.apparition_frame(i/6.0+.001)==i)
  assert(frames.get_frame_texture('action',i)!=null)
 assert(field.apparition_alpha(0)==0)
 assert(field.apparition_alpha(.12)==1)
 assert(field.apparition_alpha(.88)>0 and field.apparition_alpha(.88)<1)
 assert(field.apparition_alpha(1.0)==0)
 field.free()
 print('POSEIDON: six registered frames, one-second timing and fade PASS')
 quit()
