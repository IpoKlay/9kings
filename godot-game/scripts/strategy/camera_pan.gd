extends RefCounted
## Velocity is in logical screen pixels/second, independent of zoom.
var velocity=Vector2.ZERO
static func edge_direction(point: Vector2,viewport_size: Vector2) -> Vector2:
	if not Rect2(Vector2.ZERO,viewport_size).has_point(point):return Vector2.ZERO
	var direction=Vector2.ZERO
	for axis in 2:
		if point[axis]<24.:direction[axis]=-1.
		elif point[axis]>viewport_size[axis]-24.:direction[axis]=1.
	return direction.normalized()
func advance(direction: Vector2,dt: float) -> Vector2:
	var target=direction.limit_length()*920.
	var rate=8. if direction!=Vector2.ZERO else 12.
	var decay=exp(-rate*dt)
	var displacement=target*dt+(velocity-target)*(1.-decay)/rate
	velocity=target+(velocity-target)*decay
	if velocity.length()<.1 and direction==Vector2.ZERO:velocity=Vector2.ZERO
	return displacement
func stop():velocity=Vector2.ZERO
