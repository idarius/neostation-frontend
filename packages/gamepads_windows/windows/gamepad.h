#include <windows.h>
#include <atomic>
#include <functional>
#include <iostream>
#include <list>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>

struct Gamepad {
  UINT joy_id;
  std::string name;
  int num_buttons;
  int num_axes;
  std::string connection_type;
  std::string driver_type;
  std::string vendor_id;
  std::string product_id;
  std::string hardware_id;
  std::atomic<bool> alive; // Use atomic to prevent race conditions
  
  // Constructor
  Gamepad(UINT id, std::string n, int buttons, int axes, 
          std::string conn_type, std::string drv_type,
          std::string vid, std::string pid, std::string hw_id)
    : joy_id(id), name(std::move(n)), num_buttons(buttons), num_axes(axes),
      connection_type(std::move(conn_type)), driver_type(std::move(drv_type)),
      vendor_id(std::move(vid)), product_id(std::move(pid)),
      hardware_id(std::move(hw_id)), alive(true) {}
  
  // Disable copy (atomic can't be copied)
  Gamepad(const Gamepad&) = delete;
  Gamepad& operator=(const Gamepad&) = delete;
  
  // Enable move
  Gamepad(Gamepad&& other) noexcept
    : joy_id(other.joy_id), name(std::move(other.name)),
      num_buttons(other.num_buttons), num_axes(other.num_axes),
      connection_type(std::move(other.connection_type)),
      driver_type(std::move(other.driver_type)),
      vendor_id(std::move(other.vendor_id)),
      product_id(std::move(other.product_id)),
      hardware_id(std::move(other.hardware_id)),
      alive(other.alive.load()) {}
};

struct Event {
  int time;
  std::string type;
  std::string key;
  int value;
};

class Gamepads {
 private:
  std::list<Event> diff_states(Gamepad* gamepad,
                               const JOYINFOEX& old,
                               const JOYINFOEX& current);
  bool are_states_different(const JOYINFOEX& a, const JOYINFOEX& b);
  void read_gamepad(std::shared_ptr<Gamepad> gamepad); // Use shared_ptr to prevent dangling pointers
  void connect_gamepad(UINT joy_id, std::string name, int num_buttons);
  std::string detect_connection_type(UINT joy_id, const std::string& name, int num_buttons);
  std::string get_driver_type(UINT joy_id);
  std::pair<std::string, std::string> get_vendor_product_id(UINT joy_id);
  std::string get_hardware_id(UINT joy_id);
  bool is_valid_gamepad(UINT joy_id, const std::string& name, int num_buttons, int num_axes);

 public:
  std::map<UINT, std::shared_ptr<Gamepad>> gamepads; // Use shared_ptr to manage lifetime
  std::mutex gamepads_mutex; // Protect concurrent access to gamepads map
  std::optional<std::function<void(Gamepad* gamepad, const Event& event)>>
      event_emitter;
  
  // Smart throttling: track last call to prevent rapid spam but allow legitimate updates
  std::atomic<DWORD> last_update_call{0};
  
  void update_gamepads();
};

extern Gamepads gamepads;

std::optional<LRESULT> CALLBACK GamepadListenerProc(HWND hwnd,
                                                    UINT uMsg,
                                                    WPARAM wParam,
                                                    LPARAM lParam);