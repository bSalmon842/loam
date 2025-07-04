/*
Project: Loam
File: input.jai
Author: Brock Salmon
Created: 03JUL2025
*/

handle_input :: (loam : *LoamState) {
    for input_button_states {
	handle_keyboard_input(loam, it, it_index);
    }
    handle_mouse_input(loam);
}

handle_keyboard_input :: (loam : *LoamState, keyState : Key_Current_State, keyCode : s64) {
    // TODO: Functors from game
    if keyState & .DOWN {
	if keyCode == {
	    case #char "A"; loam.camera.position.x -= cast(float) (5.0 * deltaTime);
	    case #char "D"; loam.camera.position.x += cast(float) (5.0 * deltaTime);

	    case #char "Q"; loam.camera.position.y += cast(float) (5.0 * deltaTime);
	    case #char "Z"; loam.camera.position.y -= cast(float) (5.0 * deltaTime);
	    
	    case #char "W"; loam.camera.position.z += cast(float) (5.0 * deltaTime);
	    case #char "S"; loam.camera.position.z -= cast(float) (5.0 * deltaTime);
	}
    }
}

handle_mouse_input :: (loam : *LoamState) {
    // TODO: Functors from game
}


