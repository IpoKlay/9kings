extends SceneTree
## Bake the larger field from unscaled pieces of the Iberian combat plate.
## All rectangles here use source-art pixels, not window or simulation units.
func _initialize():
	var source=load("res://assets/environments/iberia-grass.png").get_image()
	var w=source.get_width()
	var h=source.get_height()
	var land=Image.create(w*2,h*2,false,source.get_format())
	var xs=sections(w,0.74)
	var ys=sections(h,0.61)
	var y=0
	for sy in ys:
		var x=0
		for sx in xs:
			var tile=source.get_region(Rect2i(sx.x,sy.x,sx.y,sy.y))
			if sx.z:tile.flip_x()
			# Upright tree and cliff silhouettes along the sides.
			land.blit_rect(tile,Rect2i(Vector2i.ZERO,tile.get_size()),Vector2i(x,y))
			x+=sx.y
		y+=sy.y

	# Quilt irregular, overlapping meadow cutouts across the interior.
	# Hard pixel masks retain the existing palette and grass detail.
	var rng=RandomNumberGenerator.new()
	rng.seed=43107
	var tile_size=Vector2i(372,230)
	var mask=Image.create(tile_size.x,tile_size.y,false,Image.FORMAT_RGBA8)
	for j in tile_size.y:
		for i in tile_size.x:
			var edge=minf(minf(i,tile_size.x-1-i),minf(j,tile_size.y-1-j))
			var uneven=14+7*sin(i*.058+j*.041)+5*sin(i*.097-j*.072)
			if edge>uneven:mask.set_pixel(i,j,Color.WHITE)
	for j in range(205,land.get_height()-tile_size.y-105,170):
		for i in range(260,land.get_width()-tile_size.x-110,300):
			var from=Vector2i(rng.randi_range(320,1100),rng.randi_range(162,326))
			var to=Vector2i(i+rng.randi_range(-28,28),j+rng.randi_range(-18,18))
			stamp(land,source,mask,from,to,tile_size)
	# A low stone ridge marks the northern approach.
	var ridge=source.get_region(Rect2i(508,0,342,105))
	var cutout=Image.create(342,105,false,Image.FORMAT_RGBA8)
	for j in ridge.get_height():
		for i in ridge.get_width():
			var pos=(Vector2(i,j)+Vector2(.5,.5))/Vector2(ridge.get_size())*2-Vector2.ONE
			if pos.length()<.89+.045*sin(i*.08+j*.05):cutout.set_pixel(i,j,Color.WHITE)
	land.blit_rect_mask(ridge,cutout,Rect2i(Vector2i.ZERO,ridge.get_size()),Vector2i(1930,250))
	var error=land.save_png("res://assets/environments/iberia-rts.png")
	print("RTS landscape ",land.get_size()," save=",error)
	quit(error)

func stamp(land: Image,source: Image,mask: Image,from: Vector2i,to: Vector2i,size: Vector2i):
	var tile=source.get_region(Rect2i(from,size))
	land.blit_rect_mask(tile,mask,Rect2i(Vector2i.ZERO,size),to)

func sections(length: int,split: float) -> Array:
	var high=roundi(length*split)
	var half=floori(length*.5)
	var low=high-half
	# Reflect only the inserted strip. Each source pixel retains its footprint.
	return [Vector3i(0,high,0),Vector3i(low,half,1),Vector3i(low,half,0),Vector3i(high-length%2,length-high+length%2,0)]
