/*
Project: Loam
File: resources.jai
Author: Brock Salmon
Created: 25JAN2026
*/


ResourceType :: enum {
    Image;
    Audio;
    JSON;
}

MAX_RESOURCE_POOL_COUNT : u32 : 256;
ResourcePool :: struct (T : Type) {
    sentinel : T;
    count    : u32;
    
    array : [MAX_RESOURCE_POOL_COUNT] *T;
}

ResourceBase :: struct (T : Type) {
    name : string;
    core : bool;
    next : *T;
    prev : *T;

    index : u32;
}

ImageResource :: struct {
    using _res : ResourceBase(#this);
    image : *AllocatedImageInfo;
}

AudioResource :: struct {
    using _res : ResourceBase(#this);
    audio : *Audio.Sound_Data;
}

JSONResource :: struct {
    using _res : ResourceBase(#this);
    json : *JSON_Value;
}

add_resource :: (name : string, resourceContent : *$T, core : bool = false) -> *$R
    #modify {
	     if T == AllocatedImageInfo { R = ImageResource; }
	else if T == Audio.Sound_Data   { R = AudioResource; }
	else if T == JSON_Value         { R = JSONResource; }
	else                            { return false; }
	
	return true;
    } {
    #if T == {
	case AllocatedImageInfo; {
	    if loam.assets.images.count == MAX_RESOURCE_POOL_COUNT {
		log(.FATAL, "Failed to add resource, image resource cache is full");
		return null;
	    }
	    resource := New(ImageResource);
	    resource.name = copy_string(name);
	    resource.core = core;
	    resource.image = resourceContent;
	    
	    resource.prev = loam.assets.images.sentinel.prev;
	    resource.next = *loam.assets.images.sentinel;
	    
	    loam.assets.images.sentinel.prev.next = resource;
	    loam.assets.images.sentinel.prev = resource;
	    loam.assets.images.count += 1;

	    for * loam.assets.images.array {
		if !it.* {
		    it.* = resource;
		    resource.index = cast(u32) it_index;
		    break;
		}
	    }

	    array_add(*vk.bindlessTextureUpdates, resource);
	    
	    return resource;
	}

	case Audio.Sound_Data; {
	    if loam.assets.audios.count == MAX_RESOURCE_POOL_COUNT {
		log(.FATAL, "Failed to add resource, audio resource cache is full");
		return null;
	    }
	    resource := New(AudioResource);
	    resource.name = copy_string(name);
	    resource.core = core;
	    resource.audio = resourceContent;
	    
	    resource.prev = loam.assets.audios.sentinel.prev;
	    resource.next = *loam.assets.audios.sentinel;
	    loam.assets.audios.count += 1;

	    for * loam.assets.audios.array {
		if !it.* {
		    it.* = resource;
		    resource.index = cast(u32) it_index;
		    break;
		}
	    }
	    
	    return resource;
	}

	case JSON_Value; {
	    if loam.assets.json.count == MAX_RESOURCE_POOL_COUNT {
		log(.FATAL, "Failed to add resource, json resource cache is full");
		return null;
	    }
	    resource := New(JSONResource);
	    resource.name = copy_string(name);
	    resource.core = core;

	    if resourceContent.name == "root" then resourceContent.name = copy_string(name);
	    resource.json = resourceContent;

	    resource.prev = loam.assets.json.sentinel.prev;
	    resource.next = *loam.assets.json.sentinel;
	    loam.assets.json.count += 1;

	    for * loam.assets.json.array {
		if !it.* {
		    it.* = resource;
		    resource.index = cast(u32) it_index;
		    break;
		}
	    }

	    return resource;
	}

	case; {
	    log(.FATAL, "Failed to add resource to cache");
	    return null;
	}
    }
}

// TODO: Reimplement when needed
/*
remove_resource :: ($T : Type, name : string, core : bool = false) {
    #if T == {
	case ImageResource; {
	    sentinel := *loam.assets.imageSentinel;
	    resource := loam.assets.imageSentinel.next;

	    while resource != sentinel {
		if compare(resource.name, name) == 0 && resource.core == core {
		    resource.prev.next = resource.next;
		    resource.next.prev = resource.prev;

		    loam.assets.images.array[resource.index] = null;
		    
		    destroy_vk_image(resource.image);
		    free(resource.name.data);
		    resource.* = .{};
		    free(resource);

		    loam.assets.images.count -= 1;
		    
		    return;
		}

		resource = resource.next;
	    }
	}
    }

    log(.WARN, "Failed to find resource to remove: { %, %, % }", T, name, core);
}
*/

find_resource :: ($T : Type, name : string, core : bool = false) -> *T {
    sentinel, resource : *T;
    #if T == {
	case ImageResource; {
	    sentinel = *loam.assets.images.sentinel;
	    resource = loam.assets.images.sentinel.next;
	}

	case AudioResource; {
	    sentinel = *loam.assets.audios.sentinel;
	    resource = loam.assets.audios.sentinel.next;
	}

	case JSONResource; {
	    sentinel = *loam.assets.json.sentinel;
	    resource = loam.assets.json.sentinel.next;
	}
    }

    while resource != sentinel {
	if compare(resource.name, name) == 0 && resource.core == core {
	    return resource;
	}

	resource = resource.next;
    }

    return null;
}

get_resource :: ($T : Type, name : string) -> *T {
    resource := find_resource(T, name);
    if resource then return resource;
    
    #if T == {
	case ImageResource; {
	    asset := get_asset(.Image, name);
	    if asset {
		image := create_vk_image_from_ktx(cast(*ktxTexture2) asset.data);
		return add_resource(name, image);
	    }

	    if name == ERROR_TEXTURE_NAME then log(.FATAL, "Failed to find error texture in cache");
	    return get_resource(T, ERROR_TEXTURE_NAME);
	}

	case AudioResource; {
	    asset := get_asset(.Audio, name);
	    if asset {
		data := string.{ xx asset.header.size, cast(*u8) asset.data };
		audio := New(Audio.Sound_Data);
		audio.* = Audio.unpack_sound_data(data);
		return add_resource(name, audio);
	    }

	    return null;
	}

	case JSONResource; {
	    asset := get_asset(.JSON, name);
	    if asset {
		data := string.{ xx asset.header.size, cast(*u8) asset.data };
		json := json_build_tree(data, name);
		return add_resource(name, json);
	    }

	    return null;
	}
    }
}


