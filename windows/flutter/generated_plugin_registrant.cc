//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <flutter_saver/flutter_saver_plugin_c_api.h>
#include <image_picker_master/image_picker_master_plugin_c_api.h>
#include <url_launcher_windows/url_launcher_windows.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  FlutterSaverPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterSaverPluginCApi"));
  ImagePickerMasterPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ImagePickerMasterPluginCApi"));
  UrlLauncherWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("UrlLauncherWindows"));
}
