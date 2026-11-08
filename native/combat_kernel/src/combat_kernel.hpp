// src/combat_kernel.hpp
#ifndef EAGLE_COMBAT_KERNEL_HPP
#define EAGLE_COMBAT_KERNEL_HPP

#include <cstdint>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

class EagleCombatKernel : public RefCounted {
	GDCLASS(EagleCombatKernel, RefCounted);

protected:
	static void _bind_methods();

public:
	Dictionary repel(PackedVector2Array points,
			PackedFloat64Array radii, PackedVector2Array headings,
			PackedByteArray flags, PackedInt32Array sides, double fastest,
			double elapsed, int64_t seed);
};

} // namespace godot

#endif // EAGLE_COMBAT_KERNEL_HPP
