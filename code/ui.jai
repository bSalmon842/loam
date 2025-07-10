/*
Project: Loam
File: ui.jai
Author: Brock Salmon
Created: 07JUL2025
*/

MouseInteractableRegion :: struct {
    p0 : Vector2;
    p1 : Vector2;
}

is_point_within_region :: (point : Vector2, region : MouseInteractableRegion) -> bool {
    if point.x < region.p0.x || point.x > region.p1.x then return false;
    if point.y < region.p0.y || point.y > region.p1.y then return false;
    
    return true;
}

get_default_interact_region :: (text : *Text) -> MouseInteractableRegion {
    region : MouseInteractableRegion;

    halfDims := (text.dimensions * text.scale.xy) * 0.5;
    region.p0 = Vector2.{ text.position.x, text.position.y } - halfDims;
    
    if text.alignment & .Left  then region.p0.x += halfDims.x;
    if text.alignment & .Right then region.p0.x -= halfDims.x;

    if text.alignment & .Top    then region.p0.y -= halfDims.y;
    if text.alignment & .Bottom then region.p0.y += halfDims.y;
    
    region.p1 = region.p0 + (text.dimensions * text.scale.xy);
    return region;
}

update_region :: (elem : *UI_Element, region : MouseInteractableRegion) {
    elem.interact.region = region;
}

UI_InteractFunc :: #type (loam : *LoamState, elem : *UI_Element);
UI_HoverFunc :: #type (loam : *LoamState, elem : *UI_Element);
MouseInteractionInfo :: struct {
    interactable : bool;
    region : MouseInteractableRegion;
    hovered : bool;
    hoverTint : Vector4;
    hoverFunc : UI_HoverFunc;
    
    activateOnRelease : bool; // If true, onClickFunc is only called on the release action, otherwise on the initial press action
    activateFunc : UI_InteractFunc;
}

UI_Type :: enum {
    Empty;
    Text;
    Image;
}

UI_Element :: struct {
    interact : MouseInteractionInfo;

    type : UI_Type;
    union {
	text : *Text;
	//image : *AllocatedI;
    }
}

make_ui_element :: (loam : *LoamState, text : *Text, interactable : bool, hoverTint : Vector4, region : MouseInteractableRegion, hoverFunc : UI_HoverFunc = null, activateOnRelease := false, activateFunc : UI_InteractFunc = null) -> *UI_Element {
    elem := New(UI_Element);
    elem.type = .Text;
    elem.text = text;

    elem.interact.interactable = interactable;
    elem.interact.region = region;
    elem.interact.hoverTint = hoverTint;
    elem.interact.hoverFunc = hoverFunc;
    elem.interact.activateOnRelease = activateOnRelease;
    elem.interact.activateFunc = activateFunc;
    
    return elem;
}

update_ui_element :: (loam : *LoamState, pointer : PointerStatus, elem : *UI_Element) {
    if elem.interact.interactable {
	if is_point_within_region(pointer.position, elem.interact.region) {
	    elem.interact.hovered = true;
	    if elem.interact.hoverFunc then elem.interact.hoverFunc(loam, elem);

	    // TODO: The way this is currently setup, we can press off the button, then move onto the button and release to activate, is that okay?
	    if elem.interact.activateFunc {
		if elem.interact.activateOnRelease {
		    if is_release_action(pointer) then elem.interact.activateFunc(loam, elem);
		} else {
		    if is_press_action(pointer) then elem.interact.activateFunc(loam, elem);
		}
	    }
	} else {
	    elem.interact.hovered = false;
	}
    }
}
