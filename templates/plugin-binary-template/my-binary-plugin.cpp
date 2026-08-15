// Template for a Neutrino Native Binary Plugin (.so)
// Replace "my-binary-plugin" with your actual plugin name
//
// This template demonstrates:
// - Basic plugin structure for Neutrino
// - Parameter handling
// - Simple GUI integration

#include <cstdio>
#include <cstring>
#include <string>

// Neutrino plugin interface
// Note: Actual headers depend on your Neutrino version
// Adjust includes based on your installation

extern "C" {

// Plugin metadata structure
struct PluginParam {
	const char* name;
	const char* version;
	int type;
	void* data;
};

// Plugin execution function
// Called when user selects this plugin from Neutrino menu
PluginParam* plugin_exec(PluginParam* param)
{
	printf("[my-binary-plugin] Plugin started\n");

	// Plugin information
	const char* plugin_name = "My Binary Plugin";
	const char* plugin_version = "1.0.0";

	printf("[my-binary-plugin] Name: %s\n", plugin_name);
	printf("[my-binary-plugin] Version: %s\n", plugin_version);

	// Check if we received parameters
	if (param != nullptr) {
		printf("[my-binary-plugin] Received parameter: %s\n",
		       param->name ? param->name : "none");
	}

	// TODO: Add your plugin logic here
	// Examples:
	// - Show a menu or dialog
	// - Process data
	// - Control hardware features
	// - Network operations
	// - File operations

	printf("[my-binary-plugin] Plugin execution completed\n");

	// Return parameter (can be modified to pass results back)
	return param;
}

// Plugin initialization (optional)
// Called when Neutrino loads the plugin
void plugin_init()
{
	printf("[my-binary-plugin] Initializing plugin\n");
	// Initialize resources, load configuration, etc.
}

// Plugin cleanup (optional)
// Called when Neutrino unloads the plugin
void plugin_del()
{
	printf("[my-binary-plugin] Cleaning up plugin\n");
	// Free resources, save state, etc.
}

// Plugin information query (optional)
const char* plugin_get_name()
{
	return "My Binary Plugin";
}

const char* plugin_get_version()
{
	return "1.0.0";
}

} // extern "C"
