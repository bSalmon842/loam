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

get_default_interact_region :: (renderable : *$T) -> MouseInteractableRegion {
    region : MouseInteractableRegion;

    halfDims := (renderable.dimensions.xy * renderable.scale.xy) * 0.5;
    region.p0 = Vector2.{ renderable.position.x, renderable.position.y } - halfDims;
    
    if renderable.alignment & .Left  then region.p0.x += halfDims.x;
    if renderable.alignment & .Right then region.p0.x -= halfDims.x;

    if renderable.alignment & .Top    then region.p0.y -= halfDims.y;
    if renderable.alignment & .Bottom then region.p0.y += halfDims.y;
    
    region.p1 = region.p0 + (renderable.dimensions.xy * renderable.scale.xy);
    return region;
}

update_region :: (elem : *UI_Element, region : MouseInteractableRegion) {
    elem.interact.region = region;
}

UI_ActivateMode :: enum {
    InitialPress;
    WhileDown;
    OnRelease;
}

UI_InteractFunc :: #type (extraData : *void);
UI_HoverFunc :: #type (elem : *UI_Element);
MouseInteractionInfo :: struct {
    interactable : bool;
    region : MouseInteractableRegion;
    hovered : bool;
    hoverTint : Vector4;
    hoverFunc : UI_HoverFunc;
    
    activateMode : UI_ActivateMode;
    activateFunc : UI_InteractFunc;
    activateData : *void;
}

UI_Type :: enum {
    Empty;
    Text;
    Sprite;
}

UI_Element :: struct {
    interact : MouseInteractionInfo;

    type : UI_Type;
    union {
	text : *Text;
	sprite : *Sprite;
    }
}

make_ui_element :: (text : *Text, interactable : bool, hoverTint : Vector4 = .{}, region : MouseInteractableRegion = .{}, hoverFunc : UI_HoverFunc = null, activateMode := UI_ActivateMode.InitialPress, activateFunc : UI_InteractFunc = null, activateData : *void = null) -> *UI_Element {
    elem := New(UI_Element);
    elem.type = .Text;
    elem.text = text;

    elem.interact.interactable = interactable;
    elem.interact.region = ifx region.p0 == region.p1 then get_default_interact_region(text) else region;
    elem.interact.hoverTint = hoverTint;
    elem.interact.hoverFunc = hoverFunc;
    elem.interact.activateMode = activateMode;
    elem.interact.activateFunc = activateFunc;
    elem.interact.activateData = activateData;
    
    return elem;
}

make_ui_element :: (sprite : *Sprite, interactable : bool, hoverTint : Vector4 = .{}, region : MouseInteractableRegion = .{}, hoverFunc : UI_HoverFunc = null, activateMode := UI_ActivateMode.InitialPress, activateFunc : UI_InteractFunc = null, activateData : *void = null) -> *UI_Element {
    elem := New(UI_Element);
    elem.type = .Sprite;
    elem.sprite = sprite;

    elem.interact.interactable = interactable;
    elem.interact.region = ifx region.p0 == region.p1 then get_default_interact_region(sprite) else region;
    elem.interact.hoverTint = hoverTint;
    elem.interact.hoverFunc = hoverFunc;
    elem.interact.activateMode = activateMode;
    elem.interact.activateFunc = activateFunc;
    elem.interact.activateData = activateData;
    
    return elem;
}

update_ui_element :: (pointer : PointerStatus, elem : *UI_Element) {
    if elem.interact.interactable {
	pointerWithinRegion := is_point_within_region(pointer.position, elem.interact.region);
        #if OS == .ANDROID {
	    pointerWithinRegion &&= pointer.pressedThisFrame;
	}
	
	if pointerWithinRegion {
	    elem.interact.hovered = true;
	    if elem.interact.hoverFunc then elem.interact.hoverFunc(elem);

	    // TODO: The way this is currently setup, we can press off the button, then move onto the button and release to activate, is that okay?
	    if elem.interact.activateFunc {
		if elem.interact.activateMode == .InitialPress && is_press_action(pointer) then elem.interact.activateFunc(elem.interact.activateData);
		if elem.interact.activateMode == .WhileDown && is_down_action(pointer) then elem.interact.activateFunc(elem.interact.activateData);
		if elem.interact.activateMode == .OnRelease && is_release_action(pointer) then elem.interact.activateFunc(elem.interact.activateData);
	    }
	} else {
	    elem.interact.hovered = false;
	}
    }
}
