/*
Project: Loam
File: ui.jai
Author: Brock Salmon
Created: 07JUL2025
*/

// TODO: This file used to also support interactive UI, however the system for using it was really awkward and didn't work
//       with the new input system, so for now this only supports non-interactive UI

UI_Type :: enum {
    Empty;
    Text;
    Sprite;
}

UI_Element :: struct {
    type : UI_Type;
    union {
	text : *Text;
	sprite : *Sprite;
    }
}

make_ui_element :: (item : *$T) -> *UI_Element {
    elem := New(UI_Element);
    #if T == {
	case Text; {
	    elem.type = .Text;
	    elem.text = item;
	}

	case Sprite; {
	    elem.type = .Sprite;
	    elem.sprite = item;
	}

	case; Invalid_Codepath();
    }
    return elem;
}
