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
    Mesh;
}

CollisionVolume :: struct {
    offset     : Vector3; // Position relative to a connected entity
    dimensions : Vector3; // Only used for box colliders
    shape      : CollisionShape;
    
    solid : bool;
    static : bool;
    
    triggers : [..] CollisionTrigger;

    #if IS_DEV {
	colliding : bool;
    }
}

add_collision_trigger :: (volume : *CollisionVolume, func : CollisionTriggerFunction, when : CollisionTriggerPoint) {
    array_add(*volume.triggers, .{ func, when });
}

make_collision_volume :: (offset : Vector3, dimensions : Vector3, shape : CollisionShape, solid : bool, static : bool) -> *CollisionVolume {
    volume := New(CollisionVolume);
    triggers : [..] CollisionTrigger;
    #if IS_DEV {
	volume.* = .{ offset, dimensions, shape, solid, static, triggers, false };
    } else {
	volume.* = .{ offset, dimensions, shape, solid, static, triggers };
    }
    return volume;
}

collision_detected :: (a : *CollisionVolume, aPosition : Vector3, b : *CollisionVolume, bPosition : Vector3) -> bool {
    collision := false;

    aPos := aPosition + a.offset;
    bPos := bPosition + b.offset;
    
    aMin := aPosition - a.dimensions * 0.5;
    aMax := aPosition + a.dimensions * 0.5;
    bMin := bPosition - b.dimensions * 0.5;
    bMax := bPosition + b.dimensions * 0.5;
    
    collision = !(bMax.x <= aMin.x ||
		  bMin.x >= aMax.x ||
		  bMax.y <= aMin.y ||
		  bMin.y >= aMax.y ||
		  bMax.z <= aMin.z ||
		  bMin.z >= aMax.z);
    
    #if IS_DEV {
	if collision {
	    a.colliding = collision;
	    b.colliding = collision;
	}
    }
    return collision;
}

handle_collision :: (a : *Entity, b : *Entity) {
    
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
