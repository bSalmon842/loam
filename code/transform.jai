/*
Project: Loam
File: transform.jai
Author: Brock Salmon
Created: 25JUN2025
*/

Alignment :: enum_flags u8 {
    Center :: 0x0;
    
    // Horizontal
    Left  :: 0x1;
    Right :: 0x2;

    // Vertical
    Top    :: 0x4;
    Bottom :: 0x8;

    // Depth
    Front  :: 0x10;
    Back   :: 0x20;
}

Transform :: struct {
    position : Vector3;
    orientation : Quaternion;
    scale : Vector3 = .{ 1, 1, 1 };
    alignment : Alignment = .Center;
}

make_transform :: (position := Vector3.{}, orientation := Quaternion.{}, scale : Vector3 = .{ 1, 1, 1 }, alignment := Alignment.Center) -> Transform {
    return Transform.{ position, orientation, scale, alignment };
}

get_transform_matrix :: (t : Transform, dims : Vector2) -> Matrix4 {
    return get_transform_matrix(t, .{ dims.x, dims.y, 0 });
}

get_transform_matrix :: (t : Transform, dims : Vector3) -> Matrix4 {
    translate, rotation, scale := Matrix4_Identity;

    adjDims := dims * t.scale;
    
    {
	adj := t.position - adjDims * 0.5;
	adj = adjust_point_for_alignment(adj, adjDims, t.alignment);
	
	translate._41 = adj.x;
	translate._42 = adj.y;
	translate._43 = adj.z;
    }

    {
	x := t.orientation.x;
	y := t.orientation.y;
	z := t.orientation.z;
	w := t.orientation.w;
	
	rotation = Matrix4.{
	    1 - 2*y*y - 2*z*z, 2*x*y - 2*w*z,     2*x*z + 2*w*y,     0,
	    2*x*y + 2*w*z,     1 - 2*x*x - 2*z*z, 2*y*z - 2*w*x,     0,
	    2*x*z - 2*w*y,     2*y*z + 2*w*x,     1 - 2*x*x - 2*y*y, 0,
	    0,                 0,                 0,                 1
	};
    }

    {
	scale._11 = t.scale.x;
	scale._22 = t.scale.y;
	scale._33 = t.scale.z;
    }
    
    return scale * rotation * translate;
}

adjust_point_for_alignment :: (point : Vector3, dimensions : Vector3, alignment : Alignment) -> Vector3 {
    result := point;
    
    if alignment & .Left  then result.x += dimensions.x * 0.5;
    if alignment & .Right then result.x -= dimensions.x * 0.5;
    
    if alignment & .Top    then result.y -= dimensions.y * 0.5;
    if alignment & .Bottom then result.y += dimensions.y * 0.5;
    
    if alignment & .Front then result.z += dimensions.z * 0.5;
    if alignment & .Back  then result.z -= dimensions.z * 0.5;
    
    return result;
}

alter_transform :: (a : Transform, b : Transform) -> Transform {
    position := a.position + b.position;
    orientation := a.orientation + b.orientation;
    scale := a.scale * b.scale;
    return .{ position, orientation, scale, a.alignment };
}

