extends SceneTree
const Feedback=preload('res://scripts/previews/impact_feedback.gd')
var failures=0
var checks=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred('run')
func run():
	var source=Image.create(2,1,false,Image.FORMAT_RGBA8)
	source.set_pixel(0,0,Color(.4,.2,.1,1));source.set_pixel(1,0,Color(.2,.1,.3,.25))
	var texture=ImageTexture.create_from_image(source)
	var feedback=Feedback.new()
	feedback.prepare({'legion':{'ally':texture}},[{'kind':'legion','side':'ally'}])
	var mask: Image=feedback.masks[texture.get_instance_id()].get_image()
	check(mask.get_pixel(0,0)==Color.WHITE,'Actual white pixels, not multiplication of a dark red shield')
	check(is_equal_approx(mask.get_pixel(1,0).a,source.get_pixel(1,0).a),'Preserve original alpha')
	feedback.prepare({'legion':{'ally':texture}},[{'kind':'legion','side':'ally'}])
	check(feedback.texture_bytes==8,'Whitening cache is built once per atlas')
	var base={'cell':9,'upper_cell':-1,'bearing':2,'pose':{},'texture':texture,'foot':Vector2(100,100)}
	var actor={'hp':80.,'position':Vector2(100,100),'preview_hit':{'start':1.,'heavy':true,'direction':Vector2.RIGHT}}
	var figure=base.duplicate(true)
	feedback.apply(figure,actor,1.)
	check(figure.flash_alpha==1. and figure.flash_texture!=null,'Contact starts the white silhouette')
	check(actor.hp==80. and actor.position==Vector2(100,100) and figure.foot==actor.position,'Feedback never changes physical feet or HP')
	figure=base.duplicate(true);figure.cell=12
	feedback.apply(figure,actor,1.+2./60.)
	check(figure.cell==9,'Hold the actual contact animation cell')
	figure=base.duplicate(true);figure.cell=12
	feedback.apply(figure,actor,1.15)
	check(figure.cell==12 and not figure.has('flash_alpha'),'Animation resumes and white flash finishes')
	figure=base.duplicate(true);feedback.apply(figure,{},1.01)
	check(figure==base,'Untouched soldiers keep their original animation and color')
	feedback.enabled=false
	figure=base.duplicate(true);feedback.apply(figure,actor,1.01)
	check(figure==base,'Feedback off restores the unmodified draw data')
	check(Feedback.camera_offset(.03,0.)==Vector2.ZERO,'Camera shake can be disabled independently')
	check(Feedback.camera_offset(.2,1.)==Vector2.ZERO,'Camera returns exactly to its original position')
	feedback.enabled=true
	var enemy_texture=ImageTexture.create_from_image(source)
	feedback.prepare({'legion':{'enemy':enemy_texture}},[{'kind':'legion','side':'enemy'}])
	for side_texture in [texture,enemy_texture]:
		var ordinary={'preview_hit':{'start':2.,'heavy':false,'direction':Vector2.LEFT}}
		figure=base.duplicate(true);figure.texture=side_texture
		feedback.apply(figure,ordinary,2.+2./60.)
		check(figure.flash_alpha==1.,'Both teams use full white for ordinary received hits')
	check(feedback.flashed_sides.has('ally') and feedback.flashed_sides.has('enemy'),'Both team atlases were actually used for flashing')
	print('Impact feedback: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
