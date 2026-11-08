// src/combat_kernel.cpp
#include "combat_kernel.hpp"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <unordered_map>
#include <vector>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

namespace godot {
namespace {

static_assert(sizeof(real_t) == 4, "Requires standard single-precision Godot.");

// Keep these operations under this translation unit's original strict FP flags.
Vector2 subtract(Vector2 a, Vector2 b) {
	return Vector2(a.x - b.x, a.y - b.y);
}

Vector2 add(Vector2 a, Vector2 b) {
	return Vector2(a.x + b.x, a.y + b.y);
}

Vector2 scale(Vector2 v, double scalar) {
	// GDScript's Vector2 * float converts the float64 scalar to real_t first.
	const real_t s = static_cast<real_t>(scalar);
	return Vector2(v.x * s, v.y * s);
}

real_t dot(Vector2 a, Vector2 b) {
	const real_t x = a.x * b.x;
	const real_t y = a.y * b.y;
	return x + y;
}

Vector2 limit_length(Vector2 v, double cap) {
	const real_t length = std::sqrt(dot(v, v));
	const real_t limit = static_cast<real_t>(cap);
	if (length > real_t(0) && limit < length) {
		// Match Vector2::limit_length: divide components, then multiply.
		v.x /= length;
		v.y /= length;
		v.x *= limit;
		v.y *= limit;
	}
	return v;
}

double random_axis(int64_t &seed) {
	// Explicit modulo 2^32; no signed overflow.
	const uint32_t previous = static_cast<uint32_t>(seed);
	const uint32_t next = static_cast<uint32_t>(
			uint64_t(previous) * uint64_t(1103515245) + uint64_t(12345));
	seed = static_cast<int64_t>(next);
	return double((next >> 16) & uint32_t(32767)) / 16383.5 - 1.0;
}

Vector2 response(Vector2 delta, double radius, double strength,
		double cap, double elapsed, int64_t &seed) {
	const double squared = static_cast<double>(dot(delta, delta));
	const double radius_squared = radius * radius;
	if (squared >= radius_squared) {
		return Vector2();
	}
	if (squared <= 0.01) {
		// Do not put RNG calls in constructor arguments: order is significant.
		const double x = random_axis(seed);
		const double y = random_axis(seed);
		const Vector2 random(static_cast<real_t>(x), static_cast<real_t>(y));
		const double amplitude = elapsed * strength * 0.5;
		const double amount = 16.0 < amplitude ? 16.0 : amplitude;
		return scale(random, amount);
	}

	Vector2 shift = scale(delta, elapsed * strength / radius);
	shift = scale(shift, 1.0 - squared / radius_squared);
	const double inner = radius_squared * 0.16;
	if (squared < inner) {
		shift = scale(shift, 1.0 + 5.0 * (1.0 - squared / inner));
	}
	return limit_length(shift, cap);
}

struct CellBounds {
	int32_t low_x;
	int32_t low_y;
	int32_t high_x;
	int32_t high_y;
};

uint64_t cell_key(int32_t x, int32_t y) {
	// Preserve both signed 32-bit coordinates without signed shifts.
	return (uint64_t(static_cast<uint32_t>(x)) << 32) |
			uint64_t(static_cast<uint32_t>(y));
}

bool finite_vector(Vector2 v) {
	return std::isfinite(v.x) && std::isfinite(v.y);
}

bool floor_coordinate(real_t value, int32_t &coordinate) {
	if (!std::isfinite(value)) {
		return false;
	}

	const real_t floored = std::floor(value);
	const double checked = static_cast<double>(floored);
	if (checked < static_cast<double>(std::numeric_limits<int32_t>::min()) ||
			checked > static_cast<double>(std::numeric_limits<int32_t>::max())) {
		return false;
	}

	coordinate = static_cast<int32_t>(floored);
	return true;
}

bool grid_cell(Vector2 point, int32_t &x, int32_t &y) {
	// Match (point / 64.).floor(): division and Vector2 storage are float32.
	const Vector2 divided(point.x / real_t(64), point.y / real_t(64));
	return floor_coordinate(divided.x, x) &&
			floor_coordinate(divided.y, y);
}

} // namespace

void EagleCombatKernel::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("repel", "points", "radii", "headings", "flags",
					"sides", "fastest", "elapsed", "seed"),
			&EagleCombatKernel::repel);
}

Dictionary EagleCombatKernel::repel(PackedVector2Array points,
		PackedFloat64Array radii, PackedVector2Array headings,
		PackedByteArray flags, PackedInt32Array sides, double fastest,
		double elapsed, int64_t seed) {
	Dictionary result;
	result["points"] = points;
	result["seed"] = seed;

	const int64_t count = points.size();
	ERR_FAIL_COND_V_MSG(
			radii.size() != count || headings.size() != count ||
					flags.size() != count || sides.size() != count,
			result, "EagleCombatKernel: packed array sizes differ.");
	ERR_FAIL_COND_V_MSG(
			!std::isfinite(fastest) || fastest < 0.0 ||
					!std::isfinite(elapsed) || elapsed < 0.0,
			result, "EagleCombatKernel: fastest and elapsed must be finite and nonnegative.");

	const Vector2 *original = points.ptr();
	const double *radius = radii.ptr();
	const Vector2 *heading = headings.ptr();
	const uint8_t *flag = flags.ptr();
	const int32_t *side = sides.ptr();

	double widest = 0.0;
	for (int64_t i = 0; i < count; ++i) {
		ERR_FAIL_COND_V_MSG(
				!std::isfinite(radius[i]) || radius[i] <= 0.0 ||
						!finite_vector(original[i]),
				result, "EagleCombatKernel: radii must be positive and finite; positions must be finite.");
		if (radius[i] > widest) {
			widest = radius[i];
		}
	}

	if (count == 0) {
		return result;
	}

	std::unordered_map<uint64_t, std::vector<int64_t>> cells;
	cells.reserve(static_cast<std::size_t>(count));
	std::vector<CellBounds> bounds(static_cast<std::size_t>(count));

	// Include every input row, regardless of flags, in original input order.
	// Hash-table iteration never determines neighbour or pair ordering.
	for (int64_t i = 0; i < count; ++i) {
		int32_t x;
		int32_t y;
		ERR_FAIL_COND_V_MSG(
				!grid_cell(original[i], x, y),
				result, "EagleCombatKernel: position is outside the supported grid.");
		cells[cell_key(x, y)].push_back(i);
	}

	// Validate and freeze every query before mutating points or consuming RNG.
	for (int64_t i = 0; i < count; ++i) {
		const double largest = radius[i] > widest ? radius[i] : widest;
		// Preserve the GDScript float64 expression's operation order.
		const double padding_scalar =
				radius[i] + widest + 0.6 * largest + 2.0 * fastest * elapsed;

		ERR_FAIL_COND_V_MSG(
				!std::isfinite(padding_scalar) ||
						padding_scalar >
								static_cast<double>(std::numeric_limits<real_t>::max()),
				result, "EagleCombatKernel: invalid grid padding.");

		// Vector2.ONE * scalar converts the scalar to float32 first.
		const Vector2 padding = scale(Vector2(real_t(1), real_t(1)), padding_scalar);
		const Vector2 low_point = subtract(original[i], padding);
		const Vector2 high_point = add(original[i], padding);

		CellBounds &b = bounds[static_cast<std::size_t>(i)];
		ERR_FAIL_COND_V_MSG(
				!grid_cell(low_point, b.low_x, b.low_y) ||
						!grid_cell(high_point, b.high_x, b.high_y),
				result, "EagleCombatKernel: query bounds are outside the supported grid.");
		ERR_FAIL_COND_V_MSG(
				b.low_x > b.high_x || b.low_y > b.high_y,
				result, "EagleCombatKernel: invalid grid query bounds.");
	}

	// Explicit copy before mutation; caller's pre-terrain points stay intact.
	points = points.duplicate();
	Vector2 *positions = points.ptrw();

	for (int64_t i = 0; i < count; ++i) {
		if ((flag[i] & 1) == 0) {
			continue;
		}

		const CellBounds &b = bounds[static_cast<std::size_t>(i)];

		// Match prepare_neighbours: y outermost, then x, then insertion order.
		// int64_t counters make inclusive INT32_MAX endpoints safe.
		for (int64_t y = b.low_y; y <= static_cast<int64_t>(b.high_y); ++y) {
			for (int64_t x = b.low_x; x <= static_cast<int64_t>(b.high_x); ++x) {
				const auto found = cells.find(
						cell_key(static_cast<int32_t>(x), static_cast<int32_t>(y)));
				if (found == cells.end()) {
					continue;
				}

				// No sorting, deduplication, or live grid-membership updates.
				for (const int64_t j : found->second) {
					if (j <= i || (flag[j] & 1) == 0) {
						continue;
					}

					const Vector2 delta = subtract(positions[i], positions[j]);
					const double size = radius[i] + radius[j];
					const double maximum = size * 1.6;
					if (static_cast<double>(dot(delta, delta)) >= maximum * maximum) {
						continue;
					}

					const bool friendly = side[i] == side[j];
					if (friendly && (flag[i] & 4) && (flag[j] & 4)) {
						continue;
					}

					double spread = friendly ? 1.2 : 1.1;
					double strength = friendly ? 120.0 : 60.0;
					double cap = 16.0;
					if (!friendly &&
							(((flag[i] & 2) && dot(delta, heading[i]) < 0.0) ||
									((flag[j] & 2) && dot(delta, heading[j]) > 0.0))) {
						spread = 1.6;
						strength = 200.0;
						cap = 32.0;
					}

					const Vector2 shift =
							response(delta, size * spread, strength, cap, elapsed, seed);
					if (shift.x == real_t(0) && shift.y == real_t(0)) {
						continue;
					}
					if ((flag[i] & 2) == 0) {
						positions[i] = add(positions[i], shift);
					}
					if ((flag[j] & 2) == 0) {
						positions[j] = subtract(positions[j], shift);
					}
				}
			}
		}
	}

	result["points"] = points;
	result["seed"] = seed;
	return result;
}

} // namespace godot
