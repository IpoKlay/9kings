extends RefCounted
# Keep the original sheet width. Vertical power-of-two pages preserve the
# original nearest-neighbour sampling at fractional scales and rotated poses.
const ROOT = 'res://assets/rts-armies/atlas/'
static var manifest: Dictionary = {}
static var pages: Dictionary = {}
static var sheets: Dictionary = {}
static var shadows: Dictionary = {}

static func sheet(id: String) -> Texture2D:
 if sheets.has(id):return sheets[id]
 if manifest.is_empty():manifest=JSON.parse_string(FileAccess.get_file_as_string(ROOT+'units.json'))
 var entry: Dictionary=manifest.sheets[id]
 if not pages.has(entry.page):
  pages[entry.page]=load(ROOT+entry.page)
  var white=AtlasTexture.new();white.atlas=pages[entry.page]
  var box=manifest.pages[entry.page].white_pixel
  white.region=Rect2(box[0],box[1],box[2],box[3]);white.filter_clip=true
  shadows[entry.page]=white
 var result=AtlasTexture.new();result.atlas=pages[entry.page]
 var r=entry.region
 result.region=Rect2(r[0],r[1],r[2],r[3]);result.filter_clip=true
 result.set_meta('foot_shadow',shadows[entry.page])
 sheets[id]=result
 return result
