/*
Project: Loam
File: input.jai
Author: Brock Salmon
Created: 03JUL2025
*/

InputBinds :: struct {
    keyboardBinds : Table(u64, ButtonInputFuncInfo);
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
ButtonInputFunc :: #type (loam : *LoamState, extraData : *void);
ButtonInputFuncInfo :: struct {
    func : ButtonInputFunc;
    extraData : *void;
}

AxisInputFunc :: #type (loam : *LoamState, extraData : *void, axis : s64);


// Registration and Calling Functions
register_keyboard_input :: (loam : *LoamState, code : Key_Code, modifiers : Event.Modifier_Flags, func : ButtonInputFunc, extraData : *void) {
    keyInput := keyboard_to_u64(code, modifiers);
    if !table_contains(*loam.input.keyboardBinds, keyInput) {
	table_add(*loam.input.keyboardBinds, keyInput, .{ func, extraData });
    }
}

handle_keyboard_input :: (loam : *LoamState, keyCode : Key_Code, modifiers : Event.Modifier_Flags) {
    foundBind := table_find_pointer(*loam.input.keyboardBinds, keyboard_to_u64(keyCode, modifiers));
    if foundBind {
	foundBind.func(loam, foundBind.extraData);
    }
    /*
    if keyCode == {
	
	case #char "W"; loam.sceneCamera.position.z += cast(float) (5.0 * deltaTime);
	case #char "S"; loam.sceneCamera.position.z -= cast(float) (5.0 * deltaTime);
    }
*/
}

handle_mouse_input :: (loam : *LoamState) {
    // TODO: Functors from game
}


