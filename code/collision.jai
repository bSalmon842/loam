/*
Project: Loam
File: collision.jai
Author: Brock Salmon
Created: 27MAR2026
*/

// TODO: Implement Capsule Collider visualisation

ColliderShape :: enum {
    Box;
    Capsule;
}

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

CollisionVolume :: struct {
    offset : Vector3; // Position relative to a connected entity
    shape : ColliderShape;
    boxInfo : Shape_Rect;
    #overlay (boxInfo) capsuleInfo : Shape_Capsule;
    
    solid : bool;
    static : bool;
    
    triggers : [..] CollisionTrigger;

    #if IS_DEV {
	colliding : bool;
    }
}

add_collision_trigger :: (volume : *CollisionVolume, func : CollisionTriggerFunction, when : CollisionTriggerPoint) {
    array_add(*volume.triggers, { func, when });
}

make_box_collider :: (offset : Vector3, dimensions : Vector3, solid : bool, static : bool) -> *CollisionVolume {
    volume := New(CollisionVolume);
    triggers : [..] CollisionTrigger;

    rect := make_rect(dimensions);
    
    #if IS_DEV {
	volume.* = { offset, .Box, rect, solid, static, triggers, false };
    } else {
	volume.* = { offset, .Box, rect, solid, static, triggers };
    }
    return volume;
}

make_capsule_collider :: (offset : Vector3, height : float32, radius : float32, solid : bool, static : bool) -> *CollisionVolume {
    volume := New(CollisionVolume);
    triggers : [..] CollisionTrigger;

    rect := make_rect(dimensions);
    
    #if IS_DEV {
	volume.* = { offset, rect, solid, static, triggers, false };
    } else {
	volume.* = { offset, rect, solid, static, triggers };
    }
    return volume;
}

handle_collision_for_entity :: (entity : *Entity, newTransform : Transform) -> Transform {
    resultTransform := newTransform;
    for loam.entities[EntityUpdateRate.Full] {
	if it != entity && it.collider && entity.collider {
	    collided, simplex := gjk_collision(entity.collider, resultTransform, it.collider, it.transform);
	    if collided {
                #if IS_DEV {
		    entity.collider.colliding = true;
		    it.collider.colliding = true;
		}

		if simplex.count == 4 {
		    contact := epa_collision(entity.collider, resultTransform, it.collider, it.transform, simplex);
		    resultTransform.position += -contact.normal * contact.depth;
		} else {
		    log(.WARN, "GJK returned a degenerate simplex, this might cause unpredicable collision results");
		}
	    }
	}
    }
    
    return resultTransform;
}

//////////////////////
// GJK ///////////////
//////////////////////

MAX_GJK_ITERATIONS :: 64;
GJK_TOLERANCE :: 1.0e-10;

Simplex :: [..] Vector3;

gjk_collision :: (a : *CollisionVolume, aT : Transform, b : *CollisionVolume, bT : Transform) -> bool, Simplex {
    simplexResult : Simplex;
    
    // Initial Search direction
    dir := (aT.position + a.offset) - (bT.position + b.offset);
    if length_squared(dir) < GJK_TOLERANCE then dir = { 1, 0, 0 };
    
    // First support point
    support := minkowski_support(a, aT, b, bT, dir);
    array_add(*simplexResult, support);

    dir = -support;

    for 1 .. MAX_GJK_ITERATIONS {
	if length_squared(dir) < GJK_TOLERANCE then return true, simplexResult;
	
	support = minkowski_support(a, aT, b, bT, dir);

	if dot(support, dir) < 0 then return false, simplexResult;

	array_insert_at(*simplexResult, support, 0);

	if evolve_simplex(*simplexResult, *dir) then return true, simplexResult;
    }

    log(.WARN, "Exceeded GJK iteration limit");
    return false, simplexResult;
}

minkowski_support :: (a : *CollisionVolume, aT : Transform, b : *CollisionVolume, bT : Transform, dir : Vector3) -> Vector3 {
    return support(a, aT, dir) - support(b, bT, -dir);
}

support :: (col : *CollisionVolume, colT : Transform, dir : Vector3) -> Vector3 {
    if #complete col.shape == {
	case .Box;     return support_box(col, colT, dir);
	case .Capsule; return support_capsule(col, colT, dir);
    }
    
    return {};
}

support_box :: (col : *CollisionVolume, colT : Transform, worldRelDir : Vector3) -> Vector3 {
    localRelDir := rotate(worldRelDir, conjugate(colT.orientation));
    localRelDir = rotate(localRelDir, conjugate(col.boxInfo.orientation));

    localPoint := col.boxInfo.dimensions * 0.5;
    if localRelDir.x < 0 then localPoint.x = -localPoint.x;
    if localRelDir.y < 0 then localPoint.y = -localPoint.y;
    if localRelDir.z < 0 then localPoint.z = -localPoint.z;

    localPoint += adjust_point_for_alignment(colT.position, col.boxInfo.dimensions, colT.alignment);
    localPoint += adjust_point_for_alignment(col.offset, col.boxInfo.dimensions, col.boxInfo.alignment);

    rotate(*localPoint, colT.orientation);
    rotate(*localPoint, col.boxInfo.orientation);

    localPoint *= colT.scale;
    localPoint *= col.boxInfo.scale;

    return localPoint;
}

support_capsule :: (col : *CollisionVolume, colT : Transform, worldRelDir : Vector3) -> Vector3 {
    localRelDir := rotate(worldRelDir, conjugate(colT.orientation));
    localShaftPoint := Vector3.{ 0, col.capsuleInfo.height * 0.5, 0 };
    if localRelDir.y < 0 then localShaftPoint.y = -localShaftPoint.y;
    
    worldShaftPoint := localShaftPoint + colT.position;
    worldShaftPoint *= colT.scale;
    worldShaftPoint *= col.capsuleInfo.scale;
    
    point := worldShaftPoint + normalize(worldRelDir) * col.capsuleInfo.radius;
    return point;
}

evolve_simplex :: (simplex : *Simplex, dir : *Vector3) -> bool {
    if simplex.count == {
	case 2; return line_simplex(simplex, dir);
	case 3; return triangle_simplex(simplex, dir);
	case 4; return tetrahedron_simplex(simplex, dir);
    }

    return false;
}

line_simplex :: (simplex : *Simplex, dir : *Vector3) -> bool {
    a := simplex.*[0];
    b := simplex.*[1];
    ab := b - a;
    ao := -a; // a towards origin
    
    if dot(ab, ao) > 0 {
	dir.* = triple_cross(ab, ao, ab);
    } else {
	simplex.count = 1;
	dir.* = ao;
    }
    
    return false; // A line cannout enclose the origin so this always returns false
}

triangle_simplex :: (simplex : *Simplex, dir : *Vector3) -> bool {
    a := simplex.*[0];
    b := simplex.*[1];
    c := simplex.*[2];
    ab := b - a;
    ac := c - a;
    ao := -a; // a towards origin
    
    abc := cross(ab, ac);
    abPerp := triple_cross(ac, ab, ab); // Perp to AB away from C
    acPerp := triple_cross(ab, ac, ac); // Perp to AC away from B
    
    if dot(abPerp, ao) > 0 {
	// Origin is outside AB edge
	simplex.count = 2;
	dir.* = triple_cross(ab, ao, ab);
    } else if dot(acPerp, ao) > 0 {
	// Origin is outside AC edge
	array_unordered_remove_by_index(simplex, 1);
	dir.* = triple_cross(ac, ao, ac);
    } else {
	// Origin is above or below triangle face
	if dot(abc, ao) > 0 {
	    // Above
	    dir.* = abc;
	} else {
	    // Below
	    swap(*simplex.*[1], *simplex.*[2]);
	    dir.* = -abc;
	}
    }
    
    return false;
}

tetrahedron_simplex :: (simplex : *Simplex, dir : *Vector3) -> bool {
    a := simplex.*[0];
    b := simplex.*[1];
    c := simplex.*[2];
    d := simplex.*[3];
    ab := b - a;
    ac := c - a;
    ad := d - a;
    ao := -a; // a towards origin
    
    abc := cross(ab, ac);
    acd := cross(ac, ad);
    adb := cross(ad, ab);
    
    if dot(abc, ao) > 0 {
	// Origin outside face abc
	simplex.count = 3;
	return triangle_simplex(simplex, dir);
    }
    
    if dot(acd, ao) > 0 {
	// Origin outside face acd
	simplex.*[1] = simplex.*[2];
	simplex.*[2] = simplex.*[3];
	simplex.count = 3;
	return triangle_simplex(simplex, dir);
    }
    
    if dot(adb, ao) > 0 {
	// Origin outside face adb
	simplex.*[2] = simplex.*[1];
	simplex.*[1] = simplex.*[3];
	simplex.count = 3;
	return triangle_simplex(simplex, dir);
    }
    
    return true;
}

//////////////////////
// EPA ///////////////
//////////////////////

MAX_EPA_ITERATIONS :: 64;
EPA_TOLERANCE :: 1.0e-10;

CollisionInfo :: struct {
    normal       : Vector3;
    depth        : float32;
    contactPoint : Vector3;
}

EPA_Face :: struct {
    indices  : [3] s64;
    normal   : Vector3;
    distance : float32;
}

EPA_Edge :: struct {
    a, b : s64;
}

epa_collision :: (a : *CollisionVolume, aT : Transform, b : *CollisionVolume, bT : Transform, simplex : Simplex) -> CollisionInfo {    
    verts : [..] Vector3;
    for simplex {
	array_add(*verts, it);
    }
    
    centroid : Vector3;
    for verts {
	centroid += it;
    }
    centroid *= (1.0 / cast(float32) verts.count);

    faces : [..] EPA_Face;
    array_add(*faces, make_epa_face(verts, 0, 1, 2, centroid));
    array_add(*faces, make_epa_face(verts, 0, 1, 3, centroid));
    array_add(*faces, make_epa_face(verts, 0, 2, 3, centroid));
    array_add(*faces, make_epa_face(verts, 1, 2, 3, centroid));
    
    collisionInfo : CollisionInfo;

    for 1 .. MAX_EPA_ITERATIONS {
	minDistance := FLOAT32_MAX;
	minIndex := 0;
	for faces {
	    if it.distance < minDistance {
		minDistance = it.distance;
		minIndex = it_index;
	    }
	}

	closestFace := faces[minIndex];

	support := minkowski_support(a, aT, b, bT, closestFace.normal);
	depth := dot(closestFace.normal, support);
	if (depth - closestFace.distance) < EPA_TOLERANCE {
	    collisionInfo.normal = closestFace.normal;
	    collisionInfo.depth = closestFace.distance;
	    break;
	}

	array_add(*verts, support);

	edges : [..] EPA_Edge;

	faceIndex := faces.count - 1;
	while faceIndex >= 0 {
	    face := faces[faceIndex];
	    if dot(face.normal, support - verts[face.indices[0]]) > 0 {
		add_silhouette_edge(*edges, face.indices[0], face.indices[1]);
		add_silhouette_edge(*edges, face.indices[1], face.indices[2]);
		add_silhouette_edge(*edges, face.indices[2], face.indices[0]);
		array_unordered_remove_by_index(*faces, faceIndex);
	    }
	    
	    faceIndex -= 1;
	}

	for edges {
	    array_add(*faces, make_epa_face(verts, it.a, it.b, verts.count-1, centroid));
	}
    }

    pointOnA := support(a, aT, collisionInfo.normal);
    pointOnB := support(b, bT, -collisionInfo.normal);
    collisionInfo.contactPoint = (pointOnA + pointOnB) * 0.5;
    
    return collisionInfo;
}

make_epa_face :: (verts : [..] Vector3, iA : s64, iB : s64, iC : s64, centroid : Vector3) -> EPA_Face {
    face : EPA_Face;
    face.indices = .[iA, iB, iC];

    a := verts[iA];
    b := verts[iB];
    c := verts[iC];

    // Check normal points outwards
    normal := normalize(cross(b - a, c - a));
    if dot(normal, a - centroid) < 0 {
	normal = -normal;
	face.indices = .[iA, iC, iB];
    }

    face.normal = normal;
    face.distance = dot(normal, a);
    
    return face;
}

add_silhouette_edge :: (edges : *[..] EPA_Edge, i0 : s64, i1 : s64) {
    edgeIndex := 0;
    while edgeIndex < edges.count {
	edge := edges.*[edgeIndex];
	if edge.a == i1 && edge.b == i0 {
	    array_unordered_remove_by_index(edges, edgeIndex);
	    return;
	}

	edgeIndex += 1;
    }

    array_add(edges, { i0, i1 });
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

    /*
    GPUCapsuleColliderInfo :: struct {
	transform  : Matrix4;
	colour     : Vector4;
	radius     : float32;
	height     : float32;
	pad0, pad1 : float32;
    }
    */
}
