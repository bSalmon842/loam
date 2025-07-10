/*
Project: Loam
File: interactable.jai
Author: Brock Salmon
Created: 07JUL2025
*/

HoverFunc :: #type (data : *void);

InteractableRegion :: struct {
    p0 : Vector2;
    p1 : Vector2;
}

InteractionInfo :: struct {
    interactable : bool;
    region : InteractableRegion;

    hovered : bool;
    onHover : HoverFunc
}

