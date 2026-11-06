extends RefCounted
## Static marks belong to the paper, not the camera or the sea animation.
const Catalog=preload('res://scripts/data/catalog.gd')
static var cached: Texture2D
static var cached_back: Texture2D
static var cached_edges: Texture2D

static func edge_texture() -> Texture2D:
	if cached_edges==null: texture()
	return cached_edges

static func back_texture(paper: Texture2D) -> Texture2D:
	if cached_back==null:
		var stock=paper.get_image()
		stock.convert(Image.FORMAT_RGBA8)
		var wear=texture().get_image()
		stock.blend_rect(wear,Rect2i(Vector2i.ZERO,wear.get_size()),Vector2i.ZERO)
		cached_back=ImageTexture.create_from_image(stock)
	return cached_back

static func texture() -> Texture2D:
	if cached!=null: return cached
	var preset=Catalog.presentation('atlas').boundary
	var dimensions=Vector2i(Vector2(1920,1080)/preset.pixel_step)
	var image=Image.create(dimensions.x,dimensions.y,false,Image.FORMAT_RGBA8)
	var dark: Color=preset.paper_palette[0].darkened(.60)
	var light: Color=preset.paper_palette[-1]
	# Unequal lengths and small changes of direction keep old folds from becoming a grid.
	crease(image,[Vector2(.305,0),Vector2(.302,.24),Vector2(.308,.49),Vector2(.304,.76),Vector2(.307,1)],dark,light,.22)
	crease(image,[Vector2(.705,0),Vector2(.699,.31),Vector2(.702,.59),Vector2(.695,.82),Vector2(.698,1)],dark,light,.18)
	crease(image,[Vector2(.02,.571),Vector2(.29,.563),Vector2(.52,.574),Vector2(.76,.567),Vector2(.98,.578)],dark,light,.14)
	# Short compressed creases are concentrated at handled edges; the centre stays quiet.
	for points in [
		[Vector2(.00,.27),Vector2(.025,.287),Vector2(.064,.30)],
		[Vector2(.12,1),Vector2(.126,.966),Vector2(.145,.936)],
		[Vector2(.84,1),Vector2(.827,.972),Vector2(.822,.936)],
		[Vector2(1,.69),Vector2(.979,.674),Vector2(.955,.669)],
		[Vector2(.53,0),Vector2(.541,.025),Vector2(.546,.054)]]:
		crease(image,points,dark,light,.16)
	# Scuffed fibres stay within the outer paper margin, without changing its repeated outline.
	var edges=Image.create(dimensions.x,dimensions.y,false,Image.FORMAT_RGBA8)
	for i in 31:
		var side=i%4
		var along=17+(i*83)%(dimensions.y-34 if side<2 else dimensions.x-34)
		var depth=1+i%4
		var p=Vector2i(depth,along) if side==0 else Vector2i(dimensions.x-1-depth,along) if side==1 else Vector2i(along,depth) if side==2 else Vector2i(along,dimensions.y-1-depth)
		var length=2+i%5
		for j in length:
			var offset=Vector2i(0,j) if side<2 else Vector2i(j,0)
			put(edges,p+offset,Color(dark,.20))
			put(edges,p+offset+Vector2i.ONE,Color(light,.16))
	# Two tiny, unequal turned tips sit in the margin and never cover map controls.
	corner(edges,Vector2i(0,dimensions.y-1),Vector2i(1,-1),Vector2i(14,9),preset.paper_palette)
	corner(edges,Vector2i(dimensions.x-1,0),Vector2i(-1,1),Vector2i(9,6),preset.paper_palette)
	cached_edges=ImageTexture.create_from_image(edges)
	image.blend_rect(edges,Rect2i(Vector2i.ZERO,dimensions),Vector2i.ZERO)
	cached=ImageTexture.create_from_image(image)
	return cached

static func put(image: Image,p: Vector2i,color: Color):
	if Rect2i(Vector2i.ZERO,image.get_size()).has_point(p):
		image.set_pixelv(p,image.get_pixelv(p).blend(color))

static func crease(image: Image,points: Array,dark: Color,light: Color,strength: float):
	var extent=Vector2(image.get_size())
	var tick=0
	for i in range(1,points.size()):
		var a: Vector2=points[i-1]*extent;var b: Vector2=points[i]*extent
		var delta=b-a
		var count=ceili(maxf(absf(delta.x),absf(delta.y)))
		var normal=Vector2i(1,0) if absf(delta.y)>absf(delta.x) else Vector2i(0,1)
		for j in count:
			var p=Vector2i(a.lerp(b,float(j)/count).round())
			# Four held pigment levels, with occasional worn-through sections, no blurred highlights.
			var fade=[.4,.7,1.0,.7,.4,.15,.4,.7][(tick/13)%8]
			for d in range(-5,5):
				var color=dark if d<1 else light
				var weight=[.12,.24,.40,.65,.85,1.0,.85,.55,.30,.12][d+5]
				color.a=strength*fade*weight
				put(image,p+normal*d,color)
			tick+=1

static func corner(image: Image,origin: Vector2i,direction: Vector2i,extent: Vector2i,palette: Array):
	for y in extent.y:
		var width=roundi(extent.x*(1.0-float(y)/extent.y))
		for x in range(1,width+2):
			var pigment: Color=palette[1] if x>=width else palette[5] if x==width-1 else palette[4]
			# A stepped underside and thin crease suggest a lifted tip without moving the sheet.
			put(image,origin+Vector2i(x,y)*direction,Color(pigment,.92 if x<width else .45))
