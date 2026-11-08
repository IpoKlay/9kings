// src/register_types.cpp
#include "combat_kernel.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

static void initialize_combat_kernel(ModuleInitializationLevel level) {
	if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		ClassDB::register_class<EagleCombatKernel>();
	}
}

static void uninitialize_combat_kernel(ModuleInitializationLevel level) {
	(void)level;
}

extern "C" {

GDExtensionBool GDE_EXPORT eagle_combat_kernel_library_init(
		GDExtensionInterfaceGetProcAddress get_proc_address,
		GDExtensionClassLibraryPtr library,
		GDExtensionInitialization *initialization) {
	GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
	init.register_initializer(initialize_combat_kernel);
	init.register_terminator(uninitialize_combat_kernel);
	init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init.init();
}

}
