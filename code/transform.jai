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
    alignment : Alignment;
}

make_transform :: (position := Vector3.{}, orientation := Quaternion.{}, scale : Vector3 = .{ 1, 1, 1 }, alignment := Alignment.Center) -> Transform {
    return Transform.{ position, orientation, scale, alignment };
}

get_transform_matrix :: (t : Transform, dims : Vector3) -> Matrix4 {
    translate, rotation, scale := Matrix4_Identity;

    adjDims := dims * t.scale;
    
    {
	adj := t.position - adjDims * 0.5;
	
	if t.alignment & .Left  then adj.x += adjDims.x * 0.5;
	if t.alignment & .Right then adj.x -= adjDims.x * 0.5;
	
	if t.alignment & .Top    then adj.y -= adjDims.y * 0.5;
	if t.alignment & .Bottom then adj.y += adjDims.y * 0.5;
	
	if t.alignment & .Front then adj.z += adjDims.z * 0.5;
	if t.alignment & .Back  then adj.z -= adjDims.z * 0.5;
	
	translate._41 = adj.x;
	translate._42 = adj.y;
	translate._43 = adj.z;
    }

    {
	scale._11 = t.scale.x;
	scale._22 = t.scale.y;
	scale._33 = t.scale.z;
    }
    
    return scale * rotation * translate;
}

