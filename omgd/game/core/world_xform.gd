# The only place backend world units become Godot space: x stays x, backend y becomes -z.
class_name WorldXform
extends RefCounted

const SCALE := 0.01


static func to_3d(x: float, y: float, height := 0.0) -> Vector3:
	return Vector3(x * SCALE, height, -y * SCALE)
