/*
Project: Loam
File: input.jai
Author: Brock Salmon
Created: 03JUL2025
*/

// NOTE: https://www.gamedeveloper.com/design/the-5-golden-rules-of-input

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
    buttonsAsAxis : bool; // NOTE: This changes how the bindings work so that it expect even array counts,
    //                             positive is first and negative is the second element
    invertAxis    : bool;
    innerDeadzone : s64 = 3200; // Approximately 10% of an s16 axis direction
    outerDeadzone : s64;
    
    keyboard      : [] SDL.Scancode;
    keyboardMod   : [] SDL.Keymod; // NOTE: The count of this array should match keyboard
    mouseButton   : [] s32; // Match BUTTON_xx globals at the top of SDL_mouse
    mouseAxis     : [] MouseAxis;
    gamepadButton : [] SDL.Gamepad_Button;
    gamepadAxis   : [] SDL.Gamepad_Axis;
    
    // TODO: SDL_joystick support (check via racing wheel or other weird controller type)
}

get_bindings_from_json :: (name : string, bindings : [..] *JSON_Value, $T : Type) -> [] T {
    if bindings.count == 0 {
	log(.WARN, tprint("No bindings found for %", name));
	return .[];
    }
    
    binds : [..] T;
    for bindings {
	array_add(*binds, cast(T) it.value_int);
    }
    
    return binds;
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
	    nameForLog := tprint("%: %", bindingSet.name, binding.name);
	    if binding.name != "buttons_as_axis" && binding.type != .Array {
		log(.ERROR, tprint("% bindings should be an array", nameForLog));
	    }
	    if binding.name == {
		case "buttons_as_axis"; bind.buttonsAsAxis = binding.value_bool;
		case "invert_axis";     bind.invertAxis    = binding.value_bool;
		case "inner_deadzone";  bind.innerDeadzone = binding.value_int;
		case "outer_deadzone";  bind.outerDeadzone = binding.value_int;
		
		case "keyboard";        bind.keyboard      = get_bindings_from_json(nameForLog, binding.values, SDL.Scancode);
		case "keyboard_mod";    bind.keyboardMod   = get_bindings_from_json(nameForLog, binding.values, SDL.Keymod);
		case "mouse_button";    bind.mouseButton   = get_bindings_from_json(nameForLog, binding.values, s32);
		case "mouse_axis";      bind.mouseAxis     = get_bindings_from_json(nameForLog, binding.values, MouseAxis);
		case "gamepad_button";  bind.gamepadButton = get_bindings_from_json(nameForLog, binding.values, SDL.Gamepad_Button);
		case "gamepad_axis";    bind.gamepadAxis   = get_bindings_from_json(nameForLog, binding.values, SDL.Gamepad_Axis);
		
		case; log(.ERROR, tprint("% is not a valid binding field", binding.name));
	    }
	}
	
	if bind.keyboard.count != bind.keyboardMod.count {
	    log(.ERROR, tprint("keyboard and keyboard_mod arrays were not the same length for: %", bindingSet.name));
	    continue;
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
	keyCount : s32;
	keys := SDL.get_keyboard_state(*keyCount);
	modState := SDL.get_mod_state();
	if keys {
	    if binding.buttonsAsAxis {
		positive := true;
		for binding.keyboard {
		    if keys[it] && binding.keyboardMod[it_index] == modState return ifx positive then 1.0 else -1.0;
		    positive = !positive;
		}
	    } else {
		for binding.keyboard {
		    if keys[it] && binding.keyboardMod[it_index] == modState then return 1.0;
		}
	    }
	}
    }

    // Check mouse bindings
    if SDL.has_mouse() {
	if binding.mouseButton.count > 0 || binding.mouseAxis.count > 0 {
	    relX, relY : float32;
	    mouseButtons := SDL.get_relative_mouse_state(*relX, *relY);

	    if binding.buttonsAsAxis {
		positive := true;
		for binding.mouseButton {
		    if cast(SDL.Mouse_Button_Flags) SDL.BUTTON_MASK(it) == mouseButtons then return ifx positive then 1.0 else -1.0;
		    positive = !positive;
		}
	    } else {
		for binding.mouseButton {
		    if cast(SDL.Mouse_Button_Flags) SDL.BUTTON_MASK(it) == mouseButtons then return 1.0;
		}
	    }

	    for binding.mouseAxis {
		if it == {
		    case .X;       return relX;
		    case .Y;       return relY;
		    case .Wheel_X; return loam.input.mouseWheel.x;
		    case .Wheel_Y; return loam.input.mouseWheel.y;
		}
	    }
	}
    }
    
    // Check gamepad bindings
    if loam.input.gamepad {
	if binding.buttonsAsAxis {
	    positive := true;
	    for binding.gamepadButton {
		if SDL.gamepad_has_button(loam.input.gamepad, it) && SDL.get_gamepad_button(loam.input.gamepad, it) {
		    return ifx positive then 1.0 else -1.0;
		}
		positive = !positive;
	    }
	} else {
	    for binding.gamepadButton {
		if SDL.gamepad_has_button(loam.input.gamepad, it) && SDL.get_gamepad_button(loam.input.gamepad, it) then return 1.0;
	    }
	}
	
	for binding.gamepadAxis {
	    if SDL.gamepad_has_axis(loam.input.gamepad, it) {
		axis := SDL.get_gamepad_axis(loam.input.gamepad, it);
		if axis == S16_MIN then axis += 1;
		if axis < binding.innerDeadzone && axis > -binding.innerDeadzone {
		    return 0;
		}
		if it == .LEFTY || it == .RIGHTY then axis = -axis; // NOTE: SDL stick Y direction is reversed to what we expect
		if binding.invertAxis then axis = -axis;
		min := (S16_MIN + 1) + binding.outerDeadzone;
		max := S16_MAX - binding.outerDeadzone;
		
		normalAxis : float32;
		if axis >= 0 {
		    normalAxis = normalise_0_to_1(cast(float32) axis, cast(float32) binding.innerDeadzone, cast(float32) max);
		} else {
		    normalAxis = -normalise_0_to_1(cast(float32) axis, cast(float32) -binding.innerDeadzone, cast(float32) min);
		}
		Clamp(*normalAxis, -1, 1);
		return normalAxis;
	    }
	}
    }
    
    return 0;
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
