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
    
    collider : *CollisionVolume;
    
    using transform : Transform;
    
    lastUpdated : float64;
    updateFunc : EntityUpdateFunc;
    updateData : *void;
}

make_entity :: (name : string, sprite : *Sprite, collider : *CollisionVolume, updateRate := EntityUpdateRate.Full) -> *Entity {
    if table_contains(*loam.entities[updateRate], name) {
	log(.WARN, "Entity already exists with name \"%\"", name);
	return null;
    }
    
    entity := New(Entity);
    entity.* = .{ name, sprite, collider, .{}, 0, null, null };
    
    table_add(*loam.entities[updateRate], name, entity);
    return entity;
}

make_entity :: (name : string, sprite : *Sprite, updateRate := EntityUpdateRate.Full) -> *Entity {
    if table_contains(*loam.entities[updateRate], name) {
	log(.WARN, "Entity already exists with name \"%\"", name);
	return null;
    }
    
    entity := New(Entity);
    entity.* = .{ name, sprite, make_collision_volume(.{}, make_vector3(sprite.dimensions, 1), .Box, false, false), .{}, 0, null, null };
    
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

move_entity :: (entity : *Entity, moveDelta : Vector3, updateRate : EntityUpdateRate) {
    newPosition := entity.position + moveDelta * loam.deltaTime;
    
    // Search for entities for collision
    collidedEntities := [..] *Entity;

    // We only need to worry about collisions with those in the same update rate
    for other : loam.entities[updateRate] {
	if other != entity {
	    if collision_detected(entity.collider, newPosition, other.collider, other.position) {
		handle_collision(entity, other);
	    }
	}
    }

    entity.position = newPosition;
}

update_entities :: () {
    for map : loam.entities {
	if map.count > 0 {
	    rate := cast(EntityUpdateRate) it_index;
	    if #complete rate == {
		case .Off;
		
		case .Full; {
		    for entity : map {
			if entity.updateFunc {
			    entity.updateFunc(entity, entity.updateData);
			}
			
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
	    if entity.collider.shape == .Box {
		add_box_collider_render_command(entity.collider.dimensions, entity.transform, entity.collider.colliding);
	    }
	}
    }
}

get_entity_data_as :: (entity : *Entity, $T : Type) -> *T {
    return cast(*T) entity.updateData;
}

