/*
Project: Loam
File: shapes.jai
Author: Brock Salmon
Created: 24MAY2026
*/

// NOTE: These are just representations of shapes, although they contain a Transform, they do not use the position, only rotation, scale, and alignment.
//       Any positional calculation should be done where the shapes are being used or by using '_with_offset' functions.
// NOTE: Shape rotation is applied after entity rotation, so think of it as a rotation offset from the entity.

Shape_Rect :: struct {
    using transform : Transform;
    dimensions : Vector3;
}

make_rect :: (dimensions : Vector3, orientation := Quaternion.{}, scale := Vector3.{1,1,1}, alignment := Alignment.Center) -> Shape_Rect {
    rect : Shape_Rect;
    rect.orientation = orientation;
    rect.scale = scale;
    rect.alignment = alignment;
    rect.dimensions = dimensions;
    return rect;
}

get_min_max :: (rect : Shape_Rect) -> min : Vector3, max : Vector3 {
    min := -rect.dimensions * 0.5;
    max := rect.dimensions * 0.5;

    // Alignment
    min = adjust_point_for_alignment(min, rect.dimensions, rect.alignment);
    max = adjust_point_for_alignment(max, rect.dimensions, rect.alignment);
    
    // Rotate
    min = rotate(min, rect.orientation);
    max = rotate(max, rect.orientation);
    
    // Scale
    min *= rect.scale;
    max *= rect.scale;

    return min, max;
}

get_min_max_with_offset :: (rect : Shape_Rect, offset : Vector3) -> min : Vector3, max : Vector3 {
    min, max := get_min_max(rect);
    min, max += offset;
    return min, max;
}

// NOTE: Capsules only really use scale, alignment and orientation does not affect capsules (yet) TODO ???
Shape_Capsule :: struct {
    using transform : Transform;
    radius : float32;
    height : float32;
}

make_capsule :: (radius : float32, height : float32, scale := Vector3.{1,1,1}, alignment := Alignment.Center) -> Shape_Capsule {
    capsule : Shape_Capsule;
    rect.scale = scale;
    rect.radius = radius;
    rect.height = height;
    return capsule;
}

is_within_bounds_2D :: (point : Vector2, rect : Shape_Rect) -> bool {
    min, max := get_min_max_with_offset(rect, rect.position);
    if point.x >= min.x && point.y >= min.y && point.x <= max.x && point.y <= max.y {
	return true;
    }
    
    return false;
}
