#include <iostream>
#define WIN32_LEAN_AND_MEAN
#include <initguid.h>
#include <windows.h>
#include <dbt.h>
#include <hidclass.h>
#include <setupapi.h>
#include <devguid.h>
#include <regstr.h>
#pragma comment(lib, "winmm.lib")
#pragma comment(lib, "setupapi.lib")
#include <mmsystem.h>

#include <atomic>
#include <list>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <thread>
#include <sstream>
#include <iomanip>
#include <vector>

#include "gamepad.h"
#include "utils.h"

Gamepads gamepads;

std::list<Event> Gamepads::diff_states(Gamepad* gamepad,
                                       const JOYINFOEX& old,
                                       const JOYINFOEX& current) {
  std::time_t now = std::time(nullptr);
  int time = static_cast<int>(now);

  std::list<Event> events;
  if (old.dwXpos != current.dwXpos) {
    events.push_back(
        {time, "analog", "dwXpos", static_cast<int>(current.dwXpos)});
  }
  if (old.dwYpos != current.dwYpos) {
    events.push_back(
        {time, "analog", "dwYpos", static_cast<int>(current.dwYpos)});
  }
  if (old.dwZpos != current.dwZpos) {
    events.push_back(
        {time, "analog", "dwZpos", static_cast<int>(current.dwZpos)});
  }
  if (old.dwRpos != current.dwRpos) {
    events.push_back(
        {time, "analog", "dwRpos", static_cast<int>(current.dwRpos)});
  }
  if (old.dwUpos != current.dwUpos) {
    events.push_back(
        {time, "analog", "dwUpos", static_cast<int>(current.dwUpos)});
  }
  if (old.dwVpos != current.dwVpos) {
    events.push_back(
        {time, "analog", "dwVpos", static_cast<int>(current.dwVpos)});
  }
  if (old.dwPOV != current.dwPOV) {
    events.push_back({time, "analog", "pov", static_cast<int>(current.dwPOV)});
  }
  if (old.dwButtons != current.dwButtons) {
    for (int i = 0; i < gamepad->num_buttons; ++i) {
      bool was_pressed = old.dwButtons & (1 << i);
      bool is_pressed = current.dwButtons & (1 << i);
      if (was_pressed != is_pressed) {
        events.push_back(
            {time, "button", "button-" + std::to_string(i), is_pressed});
      }
    }
  }
  return events;
}

bool Gamepads::are_states_different(const JOYINFOEX& a, const JOYINFOEX& b) {
  return a.dwXpos != b.dwXpos || a.dwYpos != b.dwYpos || a.dwZpos != b.dwZpos ||
         a.dwRpos != b.dwRpos || a.dwUpos != b.dwUpos || a.dwVpos != b.dwVpos ||
         a.dwButtons != b.dwButtons || a.dwPOV != b.dwPOV;
}

void Gamepads::read_gamepad(std::shared_ptr<Gamepad> gamepad) {
  JOYINFOEX state;
  state.dwSize = sizeof(JOYINFOEX);
  state.dwFlags = JOY_RETURNALL;

  int joy_id = gamepad->joy_id;

  std::cout << "Listening to gamepad " << joy_id << std::endl;

  while (gamepad->alive.load()) {
    JOYINFOEX previous_state = state;
    MMRESULT result = joyGetPosEx(joy_id, &state);
    if (result == JOYERR_NOERROR) {
      if (are_states_different(previous_state, state)) {
        std::list<Event> events = diff_states(gamepad.get(), previous_state, state);
        for (auto joy_event : events) {
          if (event_emitter.has_value()) {
            (*event_emitter)(gamepad.get(), joy_event);
          }
        }
      }
    } else {
      std::cout << "Fail to listen to gamepad " << joy_id << std::endl;
      gamepad->alive.store(false);
      
      // Safe removal with mutex protection
      std::lock_guard<std::mutex> lock(gamepads_mutex);
      auto it = gamepads.find(joy_id);
      if (it != gamepads.end() && it->second == gamepad) {
        gamepads.erase(it);
      }
      break; // Exit loop after error
    }
    
    // Rate limiting: Sleep for 8ms (~125 Hz polling rate)
    // This prevents high CPU usage from the busy loop
    // Most gamepads operate at 60-120 Hz, so 125 Hz is more than enough
    // to capture all input events without missing any
    Sleep(8);
  }
  
  std::cout << "Stopped listening to gamepad " << joy_id << std::endl;
}

void Gamepads::connect_gamepad(UINT joy_id, std::string name, int num_buttons) {
  // Obtener información extendida del dispositivo
  std::string connection_type = detect_connection_type(joy_id, name, num_buttons);
  std::string driver_type = get_driver_type(joy_id);
  auto vendor_product = get_vendor_product_id(joy_id);
  std::string hardware_id = get_hardware_id(joy_id);
  
  // Obtener número de ejes
  JOYCAPSW joy_caps;
  int num_axes = 0;
  if (joyGetDevCapsW(joy_id, &joy_caps, sizeof(JOYCAPSW)) == JOYERR_NOERROR) {
    num_axes = joy_caps.wNumAxes;
  }
  
  // Create shared_ptr using the constructor
  auto gamepad = std::make_shared<Gamepad>(
    joy_id, 
    name, 
    num_buttons, 
    num_axes,
    connection_type,
    driver_type,
    vendor_product.first,
    vendor_product.second,
    hardware_id
  );
  
  // Store in map with mutex protection
  {
    std::lock_guard<std::mutex> lock(gamepads_mutex);
    gamepads[joy_id] = gamepad;
  }
  
  // Start reading thread with shared_ptr (keeps gamepad alive)
  std::thread read_thread([this, gamepad]() { 
    read_gamepad(gamepad); 
  });
  read_thread.detach();
}

void Gamepads::update_gamepads() {
  try {
    std::cout << "Updating gamepads..." << std::endl;
    UINT max_joysticks = joyGetNumDevs();
    std::cout << "Max joystick slots: " << max_joysticks << std::endl;
    
    bool state_changed = false;
    
    // First pass: scan all slots WITHOUT holding the mutex (fast, non-blocking)
    std::map<UINT, std::tuple<std::string, int, int>> detected_gamepads;
    
    for (UINT joy_id = 0; joy_id < max_joysticks; ++joy_id) {
      JOYCAPSW joy_caps;
      MMRESULT result = joyGetDevCapsW(joy_id, &joy_caps, sizeof(JOYCAPSW));
      
      std::cout << "Checking slot " << joy_id << ": ";
    
      if (result == JOYERR_NOERROR) {
        std::cout << "Device found!" << std::endl;
        std::string name = to_string(joy_caps.szPname);
        int num_buttons = static_cast<int>(joy_caps.wNumButtons);
        int num_axes = static_cast<int>(joy_caps.wNumAxes);
        
        // Validar que sea realmente un gamepad
        if (is_valid_gamepad(joy_id, name, num_buttons, num_axes)) {
          detected_gamepads[joy_id] = std::make_tuple(name, num_buttons, num_axes);
          std::cout << "Valid gamepad in slot " << joy_id << std::endl;
        } else {
          std::cout << "Skipping invalid gamepad candidate " << joy_id 
                    << ": " << name << " (buttons=" << num_buttons 
                    << ", axes=" << num_axes << ")" << std::endl;
        }
      } else {
        std::cout << "No device (error code: " << result << ")" << std::endl;
      }
    }
    
    std::cout << "Finished scanning, now updating state..." << std::endl;
    
    // Second pass: quick mutex operations to detect changes
    std::vector<UINT> gamepads_to_connect;
    {
      std::lock_guard<std::mutex> lock(gamepads_mutex);
      
      // Check for new gamepads or changed gamepads
      for (const auto& [joy_id, info] : detected_gamepads) {
        auto [name, num_buttons, num_axes] = info;
        
        auto it = gamepads.find(joy_id);
        if (it == gamepads.end()) {
          // New gamepad
          state_changed = true;
          gamepads_to_connect.push_back(joy_id);
          std::cout << "New gamepad detected: " << joy_id << std::endl;
        } else if (it->second->name != name) {
          // Gamepad changed
          state_changed = true;
          std::cout << "Gamepad " << joy_id << " changed" << std::endl;
          it->second->alive.store(false);
          gamepads.erase(it);
          gamepads_to_connect.push_back(joy_id);
        }
      }
      
      // Check for disconnected gamepads
      std::vector<UINT> to_remove;
      for (const auto& [joy_id, gamepad] : gamepads) {
        if (detected_gamepads.find(joy_id) == detected_gamepads.end()) {
          state_changed = true;
          std::cout << "Gamepad " << joy_id << " disconnected" << std::endl;
          gamepad->alive.store(false);
          to_remove.push_back(joy_id);
        }
      }
      
      for (UINT joy_id : to_remove) {
        gamepads.erase(joy_id);
      }
    } // Mutex released - UI won't freeze anymore
    
    // Third pass: connect new gamepads outside the mutex
    for (UINT joy_id : gamepads_to_connect) {
      auto [name, num_buttons, num_axes] = detected_gamepads[joy_id];
      std::cout << "Connecting gamepad " << joy_id << std::endl;
      connect_gamepad(joy_id, name, num_buttons);
    }
  
  std::cout << "Finished scanning all slots" << std::endl;
  
  // Smart throttling: If NO changes were detected, prevent rapid re-scanning
  // This stops the infinite loop while allowing legitimate connect/disconnect events
  if (!state_changed) {
    DWORD current_time = GetTickCount();
    DWORD last_call = last_update_call.load();
    
    if (last_call != 0 && (current_time - last_call) < 100) {
      // No changes and called too recently - skip future redundant calls
      last_update_call.store(current_time);
      std::cout << "Throttling: No changes detected" << std::endl;
      return;
    }
  }
  
  // Update timestamp for next throttling check
  last_update_call.store(GetTickCount());
  std::cout << "update_gamepads() completed successfully" << std::endl;
  
  } catch (const std::exception& e) {
    std::cerr << "EXCEPTION in update_gamepads(): " << e.what() << std::endl;
  } catch (...) {
    std::cerr << "UNKNOWN EXCEPTION in update_gamepads()" << std::endl;
  }
}

std::set<std::wstring> connected_devices;

std::optional<LRESULT> CALLBACK GamepadListenerProc(HWND hwnd,
                                                    UINT uMsg,
                                                    WPARAM wParam,
                                                    LPARAM lParam) {
  switch (uMsg) {
    case WM_DEVICECHANGE: {
      if (lParam != NULL) {
        PDEV_BROADCAST_HDR pHdr = (PDEV_BROADCAST_HDR)lParam;
        if (pHdr->dbch_devicetype == DBT_DEVTYP_DEVICEINTERFACE) {
          PDEV_BROADCAST_DEVICEINTERFACE pDevInterface =
              (PDEV_BROADCAST_DEVICEINTERFACE)pHdr;
          if (IsEqualGUID(pDevInterface->dbcc_classguid,
                          GUID_DEVINTERFACE_HID)) {
            std::wstring device_path = pDevInterface->dbcc_name;
            bool is_connected =
                connected_devices.find(device_path) != connected_devices.end();
            if (!is_connected && wParam == DBT_DEVICEARRIVAL) {
              connected_devices.insert(device_path);
              gamepads.update_gamepads();
            } else if (is_connected && wParam == DBT_DEVICEREMOVECOMPLETE) {
              connected_devices.erase(device_path);
              gamepads.update_gamepads();
            }
          }
        }
      }
      return 0;
    }
    case WM_DESTROY: {
      PostQuitMessage(0);
      return 0;
    }
  }
  return std::nullopt;
}

// Detectar tipo de conexión basado en patrones conocidos
std::string Gamepads::detect_connection_type(UINT joy_id, const std::string& name, int num_buttons) {
  // Análisis basado en patrones de botones
  if (num_buttons > 10) {
    // Bluetooth típicamente reporta más botones
    return "bluetooth";
  } else if (num_buttons <= 10 && num_buttons >= 6) {
    // Wireless/USB típicamente reporta menos botones
    return "wireless";
  }
  
  // Análisis basado en el nombre del dispositivo (case-insensitive search)
  if (name.find("bluetooth") != std::string::npos || name.find("Bluetooth") != std::string::npos) {
    return "bluetooth";
  } else if (name.find("wireless") != std::string::npos || name.find("Wireless") != std::string::npos) {
    return "wireless";
  } else if (name.find("usb") != std::string::npos || name.find("USB") != std::string::npos) {
    return "usb";
  }
  
  return "wireless"; // Default para Windows
}

// Obtener tipo de driver (XInput, DirectInput, etc.)
std::string Gamepads::get_driver_type(UINT joy_id) {
  // Por defecto, Windows MM API usa drivers compatibles con DirectInput
  // XInput devices aparecen típicamente a través de este sistema también
  return "xinput";
}

// Obtener VID/PID del dispositivo usando registry del joystick específico
std::pair<std::string, std::string> Gamepads::get_vendor_product_id(UINT joy_id) {
  std::string vendor_id = "unknown";
  std::string product_id = "unknown";
  
  // Intentar obtener información del registry para este joystick específico
  JOYCAPSW joy_caps;
  if (joyGetDevCapsW(joy_id, &joy_caps, sizeof(JOYCAPSW)) == JOYERR_NOERROR) {
    // El registry key para joysticks está en HKEY_CURRENT_USER\System\CurrentControlSet\Control\MediaResources\Joystick
    // Pero es complejo acceder directamente, así que usaremos un enfoque alternativo
    
    // Por ahora, intentar extraer VID/PID de devices conocidos usando naming patterns
    std::string name = to_string(joy_caps.szPname);
    
    // Mapeo de nombres conocidos a VID/PID
    if (name.find("8BitDo") != std::string::npos || name.find("8bitdo") != std::string::npos) {
      vendor_id = "2DC8";
      product_id = "310A"; // Ultimate 2C common PID
    } else if (name.find("Xbox") != std::string::npos && name.find("Wireless") != std::string::npos) {
      vendor_id = "045E";
      product_id = "02FD"; // Xbox Wireless Controller common PID
    } else if (name.find("DualSense") != std::string::npos) {
      vendor_id = "054C";
      product_id = "0CE6"; // DualSense common PID
    }
    
    // Si no es un nombre conocido, intentar obtener por HID enumeración más específica
    if (vendor_id == "unknown") {
      // Buscar solo dispositivos HID que correspondan a este joystick
      HDEVINFO device_info_set = SetupDiGetClassDevs(&GUID_DEVINTERFACE_HID, NULL, NULL, 
                                                      DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
      
      if (device_info_set != INVALID_HANDLE_VALUE) {
        SP_DEVICE_INTERFACE_DATA device_interface_data;
        device_interface_data.cbSize = sizeof(SP_DEVICE_INTERFACE_DATA);
        
        // Solo tomar el primer dispositivo HID válido encontrado
        // (esto es una aproximación, idealmente correlaríamos mejor)
        if (SetupDiEnumDeviceInterfaces(device_info_set, NULL, &GUID_DEVINTERFACE_HID, 
                                       joy_id, &device_interface_data)) {
          
          DWORD required_size = 0;
          SetupDiGetDeviceInterfaceDetail(device_info_set, &device_interface_data, 
                                        NULL, 0, &required_size, NULL);
          
          if (required_size > 0) {
            auto detail_data = (PSP_DEVICE_INTERFACE_DETAIL_DATA)malloc(required_size);
            detail_data->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA);
            
            SP_DEVINFO_DATA device_info_data;
            device_info_data.cbSize = sizeof(SP_DEVINFO_DATA);
            
            if (SetupDiGetDeviceInterfaceDetail(device_info_set, &device_interface_data,
                                              detail_data, required_size, NULL, &device_info_data)) {
              
              WCHAR hardware_id[256];
              if (SetupDiGetDeviceRegistryProperty(device_info_set, &device_info_data,
                                                 SPDRP_HARDWAREID, NULL, (PBYTE)hardware_id,
                                                 sizeof(hardware_id), NULL)) {
                
                std::wstring hw_id_str(hardware_id);
                std::string hw_id = to_string(hw_id_str);
                
                // Buscar patrones VID_xxxx&PID_xxxx
                size_t vid_pos = hw_id.find("VID_");
                size_t pid_pos = hw_id.find("PID_");
                
                if (vid_pos != std::string::npos) {
                  vendor_id = hw_id.substr(vid_pos + 4, 4);
                }
                if (pid_pos != std::string::npos) {
                  product_id = hw_id.substr(pid_pos + 4, 4);
                }
              }
            }
            free(detail_data);
          }
        }
        SetupDiDestroyDeviceInfoList(device_info_set);
      }
    }
  }
  
  return {vendor_id, product_id};
}

// Obtener Hardware ID completo
std::string Gamepads::get_hardware_id(UINT joy_id) {
  std::string hardware_id = "unknown";
  
  HDEVINFO device_info_set = SetupDiGetClassDevs(&GUID_DEVINTERFACE_HID, NULL, NULL, 
                                                  DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
  
  if (device_info_set != INVALID_HANDLE_VALUE) {
    SP_DEVICE_INTERFACE_DATA device_interface_data;
    device_interface_data.cbSize = sizeof(SP_DEVICE_INTERFACE_DATA);
    
    for (DWORD device_index = 0; 
         SetupDiEnumDeviceInterfaces(device_info_set, NULL, &GUID_DEVINTERFACE_HID, 
                                   device_index, &device_interface_data); 
         device_index++) {
      
      DWORD required_size = 0;
      SetupDiGetDeviceInterfaceDetail(device_info_set, &device_interface_data, 
                                    NULL, 0, &required_size, NULL);
      
      if (required_size > 0) {
        auto detail_data = (PSP_DEVICE_INTERFACE_DETAIL_DATA)malloc(required_size);
        detail_data->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA);
        
        SP_DEVINFO_DATA device_info_data;
        device_info_data.cbSize = sizeof(SP_DEVINFO_DATA);
        
        if (SetupDiGetDeviceInterfaceDetail(device_info_set, &device_interface_data,
                                          detail_data, required_size, NULL, &device_info_data)) {
          
          WCHAR hw_id[256];
          if (SetupDiGetDeviceRegistryProperty(device_info_set, &device_info_data,
                                             SPDRP_HARDWAREID, NULL, (PBYTE)hw_id,
                                             sizeof(hw_id), NULL)) {
            
            std::wstring hw_id_str(hw_id);
            hardware_id = to_string(hw_id_str);
            
            // Tomar el primer hardware ID válido encontrado
            if (hardware_id != "unknown" && !hardware_id.empty()) {
              free(detail_data);
              break;
            }
          }
        }
        free(detail_data);
      }
    }
    SetupDiDestroyDeviceInfoList(device_info_set);
  }
  
  return hardware_id;
}

// Validar que un dispositivo sea realmente un gamepad
bool Gamepads::is_valid_gamepad(UINT joy_id, const std::string& name, int num_buttons, int num_axes) {
  std::cout << "Validating gamepad " << joy_id << ": '" << name 
            << "' (buttons: " << num_buttons << ", axes: " << num_axes << ")" << std::endl;
  
  // Validación básica: debe responder a consultas
  JOYINFOEX joy_info;
  joy_info.dwSize = sizeof(JOYINFOEX);
  joy_info.dwFlags = JOY_RETURNALL;
  
  MMRESULT result = joyGetPosEx(joy_id, &joy_info);
  if (result != JOYERR_NOERROR) {
    // Allow JOYERR_UNPLUGGED (165) - device might be temporarily unavailable but will reconnect
    if (result == JOYERR_UNPLUGGED) {
      std::cout << "  -> WARNING: Device temporarily unplugged, but will retry connection" << std::endl;
      // Don't reject - let it try to connect, the read thread will handle errors
    } else {
      std::cout << "  -> REJECTED: Cannot read joystick state (error: " << result << ")" << std::endl;
      return false;
    }
  }
  
  // Debe tener al menos algún control
  if (num_buttons == 0 && num_axes == 0) {
    std::cout << "  -> REJECTED: No buttons or axes" << std::endl;
    return false;
  }
  
  // Obtener VID para validación adicional
  auto vendor_product = get_vendor_product_id(joy_id);
  std::string vid = vendor_product.first;
  std::string pid = vendor_product.second;
  
  std::cout << "  -> Device VID: " << vid << ", PID: " << pid << std::endl;
  
  // FILTROS NEGATIVOS: Rechazar dispositivos que claramente NO son gamepads
  
  // Configuración sospechosa: muchos botones sin ejes (patrón típico de mouse/teclado)
  if (num_axes == 0 && num_buttons > 16) {
    std::cout << "  -> REJECTED: Too many buttons without axes (likely keyboard/mouse)" << std::endl;
    return false;
  }
  
  // Configuración sospechosa: sin ejes (la mayoría de gamepads tienen al menos 2 ejes)
  if (num_axes == 0) {
    std::cout << "  -> REJECTED: No axes detected" << std::endl;
    return false;
  }
  
  // Nombres que indican otros dispositivos
  if (name.find("Mouse") != std::string::npos || 
      name.find("Keyboard") != std::string::npos ||
      name.find("Headset") != std::string::npos ||
      name.find("Audio") != std::string::npos) {
    std::cout << "  -> REJECTED: Device name indicates non-gamepad" << std::endl;
    return false;
  }
  
  // CRITERIOS POSITIVOS: Aceptar si cumple alguno de estos
  
  // 1. Configuración típica de gamepad
  bool has_reasonable_config = (num_axes >= 2 && num_buttons >= 4) || 
                               (num_axes >= 4 && num_buttons >= 6) ||
                               (num_axes >= 1 && num_buttons >= 8);
  
  // 2. Nombres conocidos de gamepads
  bool has_gamepad_name = (name.find("Xbox") != std::string::npos) ||
                          (name.find("PlayStation") != std::string::npos) ||
                          (name.find("DualSense") != std::string::npos) ||
                          (name.find("DualShock") != std::string::npos) ||
                          (name.find("8BitDo") != std::string::npos) ||
                          (name.find("8bitdo") != std::string::npos) ||
                          (name.find("Pro Controller") != std::string::npos) ||
                          (name.find("Gamepad") != std::string::npos) ||
                          (name.find("Controller") != std::string::npos) ||
                          (name.find("Joystick") != std::string::npos);
  
  // 3. VIDs conocidos de fabricantes de gamepads
  bool has_gamepad_vid = (vid == "045E") ||  // Microsoft Xbox
                         (vid == "054C") ||  // Sony PlayStation
                         (vid == "057E") ||  // Nintendo
                         (vid == "2DC8") ||  // 8BitDo
                         (vid == "0F0D") ||  // Hori
                         (vid == "0738") ||  // Mad Catz
                         (vid == "28DE") ||  // Valve Steam Controller
                         (vid == "0079") ||  // DragonRise
                         (vid == "1949") ||  // Amazon Luna Controller
                         (vid == "18D1");    // Google Stadia Controller
  
  // Decisión final
  if (has_reasonable_config || has_gamepad_name || has_gamepad_vid) {
    std::cout << "  -> ACCEPTED: config=" << has_reasonable_config 
              << ", name=" << has_gamepad_name 
              << ", vid=" << has_gamepad_vid << std::endl;
    return true;
  }
  
  std::cout << "  -> REJECTED: Does not meet gamepad criteria" << std::endl;
  return false;
}
