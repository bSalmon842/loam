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
    
    shape    : CollisionShape;
    vertices : [..] Vector3;
    
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
    
    vertices : [..] Vector3;
    if shape == .Box {
	halfDim := dimensions * 0.5;
	array_add(*vertices, -halfDim);
	array_add(*vertices, .{  halfDim.x, -halfDim.y, -halfDim.z});
	array_add(*vertices, .{  halfDim.x, -halfDim.y,  halfDim.z});
	array_add(*vertices, .{ -halfDim.x, -halfDim.y,  halfDim.z});
	
	array_add(*vertices,  halfDim);
	array_add(*vertices, .{  halfDim.x, halfDim.y, -halfDim.z});
	array_add(*vertices, .{  halfDim.x, halfDim.y,  halfDim.z});
	array_add(*vertices, .{ -halfDim.x, halfDim.y,  halfDim.z});
    } else {
	// TODO: Get mesh vertices
	Invalid_Codepath();
    }
    
    #if IS_DEV {
	volume.* = .{ offset, dimensions, shape, vertices, solid, static, triggers, false };
    } else {
	volume.* = .{ offset, dimensions, shape, vertices, solid, static, triggers };
    }
    return volume;
}

///////////////////////////////////////////////////////
// GJK (courtesy of winter.dev) ///////////////////////
///////////////////////////////////////////////////////

Simplex :: [..] Vector3;

gjk_support :: (a : *CollisionVolume, aPosition : Vector3, b : *CollisionVolume, bPosition : Vector3, direction : Vector3) -> Vector3 {
    find_support_point_in_direction :: (vertices : [] Vector3, offset : Vector3, direction : Vector3) -> Vector3{
	supportPoint : Vector3;
	maxDistance := -FLOAT64_MAX;

	for vertices {
	    transformVert := it + offset;
	    distance := dot(transformVert, direction);
	    if distance > maxDistance {
		maxDistance = distance;
		supportPoint = transformVert;
	    }
	}

	return supportPoint;
    }

    return find_support_point_in_direction(a.vertices, a.offset + aPosition, direction) - find_support_point_in_direction(b.vertices, b.offset + bPosition, -direction);
}

same_direction :: (direction : Vector3, ao : Vector3) -> bool {
    return dot(direction, ao) > 0;
}

make_simplex :: (simplex : *Simplex, args : .. Vector3) {
    array_reset(simplex);
    for args {
	array_add(simplex, it);
    }
}

line_simplex :: (points : *Simplex, direction : *Vector3) -> bool {
    a := points.*[0];
    b := points.*[1];

    ab := b - a;
    ao := -a;

    if same_direction(ab, ao) {
	direction.* = cross(cross(ab, ao), ab);
    } else {
	make_simplex(points, a);
	direction.* = ao;
    }

    return false;
}

triangle_simplex :: (points : *Simplex, direction : *Vector3) -> bool {
    a := points.*[0];
    b := points.*[1];
    c := points.*[2];

    ab := b - a;
    ac := c - a;
    ao := -a;

    abc := cross(ab, ac);
    
    if same_direction(cross(abc, ac), ao) {
	if same_direction(ac, ao) {
	    make_simplex(points, a, c);
	    direction.* = cross(cross(ac, ao), ac);
	} else {
	    make_simplex(points, a, b);
	    return line_simplex(points, direction);
	}
    } else {
	if same_direction(cross(ab, abc), ao) {
	    make_simplex(points, a, b);
	    return line_simplex(points, direction);
	} else {
	    if same_direction(abc, ao) {
		direction.* = abc;
	    } else {
		make_simplex(points, a, c, b);
		direction.* = -abc;
	    }
	}
    }

    return false;
}

tetrahedron_simplex :: (points : *Simplex, direction : *Vector3) -> bool {
    a := points.*[0];
    b := points.*[1];
    c := points.*[2];
    d := points.*[3];

    ab := b - a;
    ac := c - a;
    ad := d - a;
    ao := -a;

    abc := cross(ab, ac);
    acd := cross(ac, ad);
    adb := cross(ad, ab);

    if same_direction(abc, ao) {
	make_simplex(points, a, b, c);
	return triangle_simplex(points, direction);
    }

    if same_direction(acd, ao) {
	make_simplex(points, a, c, d);
	return triangle_simplex(points, direction);
    }

    if same_direction(adb, ao) {
	make_simplex(points, a, d, b);
	return triangle_simplex(points, direction);
    }
    
    return true;
}

next_simplex :: (points : *Simplex, direction : *Vector3) -> bool {
    if points.count == {
	case 2; return line_simplex(points, direction);
	case 3; return triangle_simplex(points, direction);
	case 4; return tetrahedron_simplex(points, direction);
	
	case; log(.ERROR, "Invalid simplex point count: %", points.count);
    }

    log(.FATAL, "next_simplex failed and hit an invalid codepath");
    return false;
}

gjk_collision :: (a : *CollisionVolume, aPosition : Vector3, b : *CollisionVolume, bPosition : Vector3) -> bool {
    support := gjk_support(a, aPosition, b, bPosition, aPosition - bPosition);
    simplexPoints : Simplex;
    array_add(*simplexPoints, support);

    direction := -support;

    while true {
	print("point count: %, direction: %\n", simplexPoints.count, direction);
	support = gjk_support(a, aPosition, b, bPosition, direction);

	if dot(support, direction) <= 0 {
	    return false;
	}
	
	array_insert_at(*simplexPoints, support, 0);
	
	if next_simplex(*simplexPoints, *direction) {
	    return true;
	}
    }

    return false;
}

collision_detected :: (a : *CollisionVolume, aPosition : Vector3, b : *CollisionVolume, bPosition : Vector3) -> bool {
    collision := gjk_collision(a, aPosition, b, bPosition);
    
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
