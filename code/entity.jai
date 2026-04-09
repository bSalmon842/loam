/*
Project: Loam
File: entity.jai
Author: Brock Salmon
Created: 01APR2026
*/

EntityUpdateRate :: enum {
    Off;
    Low;    // Entity is updated once every 10 seconds
    Medium; // Entity is updated once per second
    Full;   // Entity is updated every frame
}
EntityUpdateFunc :: #type (*Entity, *void);

EntityMap :: Table(string, *Entity);
Entity :: struct {
    name : string;
    
    sprite : *Sprite;
    // mesh : *Mesh;
    
    colliders : [..] *CollisionVolume;
    
    using transform : Transform;
    
    lastUpdated : float64;
    updateFunc : EntityUpdateFunc;
    updateData : *void;
}

make_entity :: (name : string, sprite : *Sprite, colliders : [..] *CollisionVolume, updateRate := EntityUpdateRate.Full) -> *Entity {
    if table_contains(*loam.entities[updateRate], name) {
	log(.WARN, "Entity already exists with name \"%\"", name);
	return null;
    }
    
    entity := New(Entity);
    entity.* = .{ name, sprite, colliders, .{}, 0, null, null };
    table_add(*loam.entities[updateRate], name, entity);
    return entity;
}

make_entity :: (name : string, sprite : *Sprite, updateRate := EntityUpdateRate.Full) -> *Entity {
    if table_contains(*loam.entities[updateRate], name) {
	log(.WARN, "Entity already exists with name \"%\"", name);
	return null;
    }
    
    entity := New(Entity);
    colliders : [..] *CollisionVolume;
    array_add(*colliders, make_collision_volume(.{}, .{}, make_vector3(sprite.dimensions, 1), .Box, true, false));
    entity.* = .{ name, sprite, colliders, .{}, 0, null, null };
    table_add(*loam.entities[updateRate], name, entity);
    return entity;
}


change_entity_update_rate :: (name : string, newRate : EntityUpdateRate) {
    entity : *Entity;
    for * map : loam.entities {
	found, entity= := table_find(map, name);
	if found && it_index == newRate then return;
	else if !found then continue;
	
	removed := table_remove(map, name);
	if !removed {
	    log(.ERROR, "Failed to remove \"%\" from the % update rate map", name, cast(EntityUpdateRate) it_index);
	    return;
	}
	break;
    }

    table_add(*loam.entities[newRate], name, entity);
}

update_entities :: () {
    for map : loam.entities {
	if map.count > 0 {
	    rate := cast(EntityUpdateRate) it_index;
	    if #complete rate == {
		case .Off;
		
		case .Full; {
		    for entity : map {
			entity.updateFunc(entity, entity.updateData);
			if entity.sprite {
			    update_sprite_animation(entity.sprite);
			}
			entity.lastUpdated = seconds_since_init();
		    }
		}
		
		case .Medium; {
		    Invalid_Codepath(); // Unimmplemented;
		}
		
		case .Low; {
		    Invalid_Codepath(); // Unimmplemented;
		}
	    }
	}
    }
}

add_render_commands_for_entity :: (entity : *Entity) {
    if entity.sprite {
	entity.sprite.transform = entity.transform;
	add_sprite_render_command(.Sprite, entity.sprite.renderable, entity.sprite.transform);
    } /* else if entity.mesh {
        
    } */
    
    #if IS_DEV {
	if __showColliders {
	    for entity.colliders {
		if it.shape == .Box {
		    transform := entity.transform;
		    transform.position = it.origin;
		    add_box_collider_render_command(it.dimensions, transform, false);
		}
	    }
	}
    }
}

get_entity_data_as :: (entity : *Entity, $T : Type) -> *T {
    return cast(*T) entity.updateData;
}

