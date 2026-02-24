/*
Project: Loam
File: input.jai
Author: Brock Salmon
Created: 03JUL2025
*/

// NOTE: https://www.gamedeveloper.com/design/the-5-golden-rules-of-input

// TODO: Add ability to sim an axis via the keyboard for uses such as movement

InputType :: enum {
    None;

    Keyboard_Mouse;
    Gamepad;
    Touchscreen;
}

MouseAxis :: enum {
    Invalid;
    
    X;
    Y;
    Wheel_X;
    Wheel_Y;
}

InputState :: struct {
    activeType : InputType;
    
    keyboardMouseTimestamp : Apollo_Time;
    touchscreenTimestamp : Apollo_Time;

    gamepad : *SDL.Gamepad;
    gamepadTimestamp : Apollo_Time;

    mouseWheel : Vector2;

    // TODO: Splitscreen / Racing wheels will need support for multiple controllers at once
}

is_timestamp_most_recent :: (time : Apollo_Time, check : .. Apollo_Time) -> bool {
    for check {
	if time < it then return false;
    }
    return true;
}

update_input :: (event : SDL.Event) {
    using loam.input;
    
    if event.type >= .KEY_DOWN && event.type < .JOYSTICK_AXIS_MOTION {
	if event.mdevice.which != SDL.TOUCH_MOUSEID {
	    keyboardMouseTimestamp = current_time_consensus();
	}
    } else if event.type >= .GAMEPAD_AXIS_MOTION && event.type < .FINGER_DOWN {
	gamepadTimestamp = current_time_consensus();
	gamepad = SDL.open_gamepad(event.gdevice.which);
    } else if event.type >= .FINGER_DOWN && event.type < .FINGER_MOTION {
	touchscreenTimestamp = current_time_consensus();
    }

    if is_timestamp_most_recent(keyboardMouseTimestamp, gamepadTimestamp, touchscreenTimestamp) {
	activeType = .Keyboard_Mouse;
    } else if is_timestamp_most_recent(gamepadTimestamp, keyboardMouseTimestamp, touchscreenTimestamp) {
	activeType = .Gamepad;
    } else if is_timestamp_most_recent(touchscreenTimestamp, keyboardMouseTimestamp, gamepadTimestamp) {
	activeType = .Touchscreen;
    }
}

//////////////////////////////////////////////////
// KEYBINDS //////////////////////////////////////
//////////////////////////////////////////////////
KeybindMap :: Table(string, *Keybind);
Keybind :: struct {
    keyboard       : SDL.Scancode;
    keyboardMod    : SDL.Keymod;
    mouseButton   : s64; // Match BUTTON_xx globals at the top of SDL_mouse
    mouseAxis     : MouseAxis;
    gamepadButton : SDL.Gamepad_Button = .INVALID;
    gamepadAxis   : SDL.Gamepad_Axis = .INVALID;
    // TODO: SDL_joystick support
}

init_keybinds :: () -> *KeybindMap {
    keybindFilename := tprint("%.bind", APP_NAME);
    readData, readSuccess := read_entire_file(keybindFilename);
    if !readSuccess {
	log(.FATAL, tprint("Failed to load %", keybindFilename));
	return null;
    }
    
    map := New(KeybindMap);
    mapRoot, mapReadSuccess := json_build_tree(readData, "Keybind Map Tree");
    if mapReadSuccess != .Success {
	log(.FATAL, tprint("Failed to read the keybind map with error: %", mapReadSuccess));
	return null;
    }
    
    //Get binds from JSON
    for bindingSet : mapRoot.values {
	if bindingSet.values.count == 0 {
	    log(.WARN, tprint("No bindings found for %", bindingSet.name));
	    continue;
	}

	if table_contains(map, bindingSet.name) {
	    log(.ERROR, tprint("Duplicate binding for \"%\" found", bindingSet.name));
	    continue;
	}

	bind := New(Keybind);
	for binding : bindingSet.values {
	    if binding.name == {
		case "keyboard";       bind.keyboard      = cast(SDL.Scancode)       binding.value_int;
		case "keyboard_mod";   bind.keyboardMod   = cast(SDL.Keymod)         binding.value_int;
		case "mouse_button";   bind.mouseButton   =                          binding.value_int;
		case "mouse_axis";     bind.mouseAxis     = cast(MouseAxis)          binding.value_int;
		case "gamepad_button"; bind.gamepadButton = cast(SDL.Gamepad_Button) binding.value_int;
		case "gamepad_axis";   bind.gamepadAxis   = cast(SDL.Gamepad_Axis)   binding.value_int;
		
		case; log(.ERROR, tprint("% is not a valid binding field", binding.name));
	    }
	}

	table_add(map, bindingSet.name, bind);
    }
    
    return map;
}

/////////////////////////////////////////////////////////
// INPUT INTERFACE //////////////////////////////////////
/////////////////////////////////////////////////////////

get_input :: (name : string) -> float32 {
    foundInput, binding := table_find(loam.keybinds, name);
    if !foundInput {
	log(.ERROR, tprint("Failed to find input with name: %", name));
    }

    // Check keyboard binding
    if SDL.has_keyboard() {
	if binding.keyboard != 0 {
	    keyCount : s32;
	    keys := SDL.get_keyboard_state(*keyCount);
	    modState := SDL.get_mod_state();
	    if keys {
		if keys[binding.keyboard] && binding.keyboardMod == modState then return 1.0;
	    }
	}
    }

    // Check mouse bindings
    if SDL.has_mouse() {
	if binding.mouseButton != 0 || binding.mouseAxis != .Invalid {
	    relX, relY : float32;
	    mouseButtons := SDL.get_relative_mouse_state(*relX, *relY);
	    if binding.mouseButton != 0 && cast(SDL.Mouse_Button_Flags) SDL.BUTTON_MASK(cast(s32) binding.mouseButton) == mouseButtons then return 1.0;
	    if binding.mouseAxis == .X then return relX;
	    if binding.mouseAxis == .Y then return relY;
	    if binding.mouseAxis == .Wheel_X then return loam.input.mouseWheel.x;
	    if binding.mouseAxis == .Wheel_Y then return loam.input.mouseWheel.y;
	}
    }
    
    // Check gamepad bindings
    if loam.input.gamepad {
	if binding.gamepadButton != .INVALID && SDL.gamepad_has_button(loam.input.gamepad, binding.gamepadButton) {
	    if SDL.get_gamepad_button(loam.input.gamepad, binding.gamepadButton) then return 1.0;
	}

	if binding.gamepadAxis != .INVALID && SDL.gamepad_has_axis(loam.input.gamepad, binding.gamepadAxis) {
	    return cast(float32) SDL.get_gamepad_axis(loam.input.gamepad, binding.gamepadAxis);
	}
    }

    return 0.0;
}

get_any_button_input :: () -> bool {
    // Check keyboard input
    keyCount : s32;
    keys := SDL.get_keyboard_state(*keyCount);
    if keys {
	scancodes := enum_values_as_enum(SDL.Scancode);
	assert(cast(s32) SDL.Scancode.COUNT == keyCount, "Got unexpected key state count, expected %, got %", cast(s32) SDL.Scancode.COUNT, keyCount);

	for scancodes {
	    if it != SDL.Scancode.COUNT {
		if keys[it] {
		    return true;
		}
	    }
	}
    }
    
    // Check mouse button input
    unusedX, unusedY : float32;
    mouseButtons := SDL.get_mouse_state(*unusedX, *unusedY);
    if mouseButtons > 0 then return true;

    // Check gamepad button input
    if loam.input.gamepad {
	for enum_values_as_enum(SDL.Gamepad_Button) {
	    if it != .INVALID && it != .COUNT {
		if SDL.get_gamepad_button(loam.input.gamepad, it) then return true;
	    }
	}
    }

    // Check touches
    // TODO: This is yet to be verified, check with android build
    touchDeviceCount : s32;
    touchDevices := SDL.get_touch_devices(*touchDeviceCount);
    if touchDevices && touchDeviceCount > 0 {
	for 0 .. touchDeviceCount-1 {
	    id := touchDevices[it];
	    fingerCount : s32;
	    fingers := SDL.get_touch_fingers(id, *fingerCount);
	    if fingers && fingerCount > 0 then return true;

	    if fingers then SDL.free(fingers);
	}
    }

    if touchDevices then SDL.free(touchDevices);
    
    return false;
}
