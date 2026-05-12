/*
Project: Loam
File: collision.jai
Author: Brock Salmon
Created: 27MAR2026
*/

COLLISION_SAFE_ITERATION_TOLERANCE :: 64;

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
    boxVertices : [..] Vector3; // Always needed for Broad-phase AABB checks
    meshVertices : [..] Vector3; // Can have a 0 count if using a Box collider
    
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
    
    boxVertices : [..] Vector3;
    halfDim := dimensions * 0.5;
    array_add(*boxVertices, -halfDim);
    array_add(*boxVertices, .{  halfDim.x, -halfDim.y, -halfDim.z});
    array_add(*boxVertices, .{  halfDim.x, -halfDim.y,  halfDim.z});
    array_add(*boxVertices, .{ -halfDim.x, -halfDim.y,  halfDim.z});
    
    array_add(*boxVertices,  halfDim);
    array_add(*boxVertices, .{  halfDim.x, halfDim.y, -halfDim.z});
    array_add(*boxVertices, .{ -halfDim.x, halfDim.y, -halfDim.z});
    array_add(*boxVertices, .{ -halfDim.x, halfDim.y,  halfDim.z});

    vertices : [..] Vector3;
    if shape == .Mesh {
	// TODO: Get mesh vertices
	Invalid_Codepath();
    }
    
    #if IS_DEV {
	volume.* = .{ offset, dimensions, shape, boxVertices, vertices, solid, static, triggers, false };
    } else {
	volume.* = .{ offset, dimensions, shape, boxVertices, vertices, solid, static, triggers };
    }
    return volume;
}

broad_phase_collision_cull :: (moving : *Entity, newPosition : Vector3, entities : EntityMap) -> [..] *Entity {
    aMin := moving.collider.boxVertices[0] + newPosition + moving.collider.offset;
    aMax := moving.collider.boxVertices[3] + newPosition + moving.collider.offset;
    
    culledEntityList : [..] *Entity;
    for entities {
	if it == moving then continue;
	if !moving.collider.solid && moving.collider.triggers.count == 0 && !it.collider.solid && it.collider.triggers.count == 0 then continue;
	
	bMin := it.collider.boxVertices[0] + it.position + it.collider.offset;
	bMax := it.collider.boxVertices[3] + it.position + it.collider.offset;

	if !(bMax.x <= aMin.x ||
	     bMin.x >= aMax.x ||
	     bMax.y <= aMin.y ||
	     bMin.y >= aMax.y ||
	     bMax.z <= aMin.z ||
	     bMin.z >= aMax.z) {
	    array_add(*culledEntityList, it);
	}
    }

    return culledEntityList;
}

narrow_phase_collision_cull :: (moving : *Entity, newPosition : Vector3, entities : [] *Entity) -> [..] *Entity {
    culledEntityList : [..] *Entity;
    for entities {
	if gjk_collision(moving.collider, newPosition, it.collider, it.position) {
	    array_add(*culledEntityList, it);
	}
    }
    
    return culledEntityList;
}

handle_collision_for_entity :: (entity : *Entity, newPosition : Vector3) -> Vector3 {
    potentialCollisionEntities := broad_phase_collision_cull(entity, newPosition, loam.entities[EntityUpdateRate.Full]);
    confirmedCollisionEntities := narrow_phase_collision_cull(entity, newPosition, potentialCollisionEntities);
    array_reset(*potentialCollisionEntities);

    // TODO: Implement search in T (maybe use a returned simplex for the wall in the hh code?)
    /*
    closestT := FLOAT32_MAX;
    closestEntity := null;
    
    if collided {
        #if IS_DEV {
	    a.collider.colliding = true;
	    b.collider.colliding = true;
	}
	
	if a.collider.solid && b.collider.solid {
	    return a.position;
	}
    }
*/
    return newPosition;
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

    aSupport := Vector3.{};
    bSupport := Vector3.{};
    
    if a.shape == .Box {
	aSupport = find_support_point_in_direction(a.boxVertices, a.offset + aPosition, direction);
    } else {
	aSupport = find_support_point_in_direction(a.meshVertices, a.offset + aPosition, direction);
    }

    if b.shape == .Box {
	bSupport = find_support_point_in_direction(b.boxVertices, b.offset + bPosition, -direction);
    } else {
	bSupport = find_support_point_in_direction(b.meshVertices, b.offset + bPosition, -direction);
    }
    
    return aSupport - bSupport;
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
    support := gjk_support(a, aPosition, b, bPosition, bPosition - aPosition);
    simplexPoints : Simplex;
    array_add(*simplexPoints, support);

    direction := -support;

    while true {
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
