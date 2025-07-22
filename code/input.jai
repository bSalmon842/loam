/*
Project: Loam
File: input.jai
Author: Brock Salmon
Created: 03JUL2025
*/

/////////////////////// INPUT REGISTRATION
InputBinds :: struct {
    keycodeBinds : Table(u64, ButtonInputFuncInfo);
}

// Input Types
KeyboardInput :: struct {
    code : Key_Code;
    modifiers : Event.Modifier_Flags;
}
keyboard_to_u64 :: (code : Key_Code, modifiers : Event.Modifier_Flags) -> u64 {
    return (cast(u64) code) | ((cast(u64) modifiers.packed) << 32);
}

// Function Types
ButtonInputFunc :: #type (extraData : *void);
ButtonInputFuncInfo :: struct {
    func : ButtonInputFunc;
    extraData : *void;
}

// Registration and Calling Functions
register_keycode_input :: (code : Key_Code, modifiers : Event.Modifier_Flags, func : ButtonInputFunc, extraData : *void) {
    keyInput := keyboard_to_u64(code, modifiers);
    if !table_contains(*loam.binds.keycodeBinds, keyInput) {
	table_add(*loam.binds.keycodeBinds, keyInput, .{ func, extraData });
    }
}

handle_keycode_input :: (keyCode : Key_Code, modifiers : Event.Modifier_Flags) {
    foundBind := table_find_pointer(*loam.binds.keycodeBinds, keyboard_to_u64(keyCode, modifiers));
    if foundBind {
	foundBind.func(foundBind.extraData);
    }
}

/////////////////////// POINTER INPUT
// Used to unify info we want from the mouse and touch inputs
PointerStatus :: struct {
    pressedThisFrame : bool;
    pressedLastFrame : bool;

    position : Vector2;
}

// TODO: We probably want a way to make sure this is only being called once per frame
update_pointer_status :: (window : Window_Type, status : *PointerStatus) {
    status.pressedLastFrame = status.pressedThisFrame;
    status.pressedThisFrame = cast(bool) (input_button_states[Key_Code.MOUSE_BUTTON_LEFT] & .DOWN);

    #if OS == .ANDROID {
	androidPointer := android_pointers[0];
	status.position = .{ androidPointer.window_position_x, loam.windowHeight - androidPointer.window_position_y };
    } else {
	x, y := get_mouse_pointer_position(window, false);
	y = loam.windowHeight - y;
	status.position = .{ cast(float) x, cast(float) y };
    }
}

is_press_action :: (pointer : PointerStatus) -> bool { return pointer.pressedThisFrame && !pointer.pressedLastFrame; }
is_release_action :: (pointer : PointerStatus) -> bool { return !pointer.pressedThisFrame && pointer.pressedLastFrame; }
is_down_action :: (pointer : PointerStatus) -> bool { return pointer.pressedThisFrame; }

