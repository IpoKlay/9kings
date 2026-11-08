extends SceneTree
var checks=0
var failures=0
func check(ok: bool):
	checks+=1
	if not ok:failures+=1;push_error('Native boundary assertion failed')
func _initialize():
	var args=OS.get_cmdline_user_args()
	assert(args.size()==1)
	var loaded=GDExtensionManager.load_extension(args[0])
	assert(loaded==GDExtensionManager.LOAD_STATUS_OK or loaded==GDExtensionManager.LOAD_STATUS_ALREADY_LOADED)
	var kernel=ClassDB.instantiate('EagleCombatKernel')
	var points=PackedVector2Array([Vector2.ZERO,Vector2.ZERO])
	var before=points.duplicate()
	var radii=PackedFloat64Array([9.,9.])
	var headings=PackedVector2Array([Vector2.RIGHT,Vector2.LEFT])
	var flags=PackedByteArray([1,1]);var sides=PackedInt32Array([0,1])
	var rows=[{'physics_index':0,'neighbours':[]},{'physics_index':1,'neighbours':[]}]
	rows[0].neighbours.append(rows[1]);rows[1].neighbours.append(rows[0])
	var result=kernel.repel(points,radii,headings,flags,sides,480.,1./30.,12345)
	check(points==before)
	check(result.points!=before)
	check(result.seed!=12345)
	var repeated=kernel.repel(points,radii,headings,flags,sides,480.,1./30.,12345)
	check(repeated==result)
	var empty=kernel.repel(PackedVector2Array(),PackedFloat64Array(),PackedVector2Array(),PackedByteArray(),PackedInt32Array(),480.,1./30.,12345)
	check(empty.points.is_empty() and empty.seed==12345)
	# These two calls intentionally exercise the C++ error guards.
	print('EXPECTED_NATIVE_ERROR: packed array sizes differ')
	var wrong_size=kernel.repel(points,PackedFloat64Array(),headings,flags,sides,480.,1./30.,12345)
	check(wrong_size.points==before and wrong_size.seed==12345)

	print('EXPECTED_NATIVE_ERROR: invalid speed')
	var wrong_index=kernel.repel(points,radii,headings,flags,sides,-1.,1./30.,12345)
	check(wrong_index.points==before and wrong_index.seed==12345)
	for row in rows:row.neighbours.clear()
	print('Native boundary: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
