/*
Project: Loam
File: collision.jai
Author: Brock Salmon
Created: 27MAR2026
*/

// When do we want to fire the trigger function
CollisionTriggerPoint :: enum {
    Invalid;

    Enter;
    Exit;
    Collision; // For solid colliders
}

CollisionTriggerFunction :: #type ();
CollisionTrigger :: struct {
    func : CollisionTriggerFunction;
    when : CollisionTriggerPoint;
}

CollisionShape :: enum {
    Box;
    Capsule;
    Sphere;
}

CollisionVolume :: struct {
    origin     : Vector3;
    offset     : Vector3; // Position relative to a connected entity
    dimensions : Vector3;
    shape      : CollisionShape;
    
    solid : bool;
    static : bool;
    
    triggers : [..] CollisionTrigger;
}

add_collision_trigger :: (volume : *CollisionVolume, func : CollisionTriggerFunction, when : CollisionTriggerPoint) {
    array_add(*volume.triggers, .{ func, when });
}

make_collision_volume :: (origin : Vector3, offset : Vector3, dimensions : Vector3, shape : CollisionShape, solid : bool, static : bool) -> *CollisionVolume {
    volume := New(CollisionVolume);
    triggers : [..] CollisionTrigger;
    volume.* = .{ origin, offset, dimensions, shape, solid, static, triggers };
    return volume;
}

//////////////////////
// DEBUG /////////////
//////////////////////
#if IS_DEV {
    __showColliders : bool;

    MAX_VISIBLE_COLLIDERS : u32 : 1024;
    
    GPUBoxColliderInfo :: struct {
	transform  : Matrix4;
	colour     : Vector4;
	dimensions : Vector3;
	padding    : u32;
    }
}
