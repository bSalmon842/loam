/*
Project: Loam
File: config.jai
Author: Brock Salmon
Created: 17SEP2025
*/

CONFIG_FILENAME : string;

Config :: struct {
    audioDeviceName : string;
    masterVolume    : float;
    bgVolume        : float;
    sfxVolume       : float;

    vsync : bool;
}

init_config :: () {
    CONFIG_FILENAME = sprint("%1%2.cfg", get_packaged_assets_path(), APP_NAME);
    
    devices := Audio.get_devices();
    loam.config.audioDeviceName = devices[0].name;
    loam.config.masterVolume = 0.2;
    loam.config.bgVolume = 1.0;
    loam.config.sfxVolume = 1.0;
    loam.config.vsync = false;

    loaded := load_config();
    Audio.set_master_volume(loam.config.masterVolume);
    if loaded then return;
    log(.WARN, "Failed to find config file");
    
    save_config();
}

load_config :: () -> bool {
    readData, readSuccess := read_entire_file(CONFIG_FILENAME);
    if readSuccess {
	lines := split(readData, "\n");
	ti := type_info(Config);
	for member : ti.members {
	    field := (cast(*u8) *loam.config) + member.offset_in_bytes;
	    if !read_from_config(lines, member.name, member.type.type, field) {
		log(.WARN, tprint("Failed to find config field for \"%\", config might be out of date!", member.name));
	    }
	}

	return true;
    }
    
    return false;
}

save_config :: () {
    builder : String_Builder;
    init_string_builder(*builder);
    
    ti := type_info(Config);
    for member : ti.members {
	field := (cast(*u8) *loam.config) + member.offset_in_bytes;
	write_to_config(*builder, member.name, member.type.type, field);
    }
    
    write_entire_file(CONFIG_FILENAME, *builder);
}

read_from_config :: (lines : [] string, name : string, tag : Type_Info_Tag, ptr : *void) -> bool {
    for lines {
	segments := split(it, ":");
	fieldName := segments[0];
	fieldValue := segments[1];
	if compare(name, fieldName) == 0 {
	    if tag == {
		case .FLOAT; {
		    convertedValue, convertSuccess: = string_to_float(fieldValue);
		    assert(convertSuccess, tprint("Failed to convert float value for %", fieldName));
		    (cast(*float) ptr).* = convertedValue;
		    return true;
		}
		
		case .STRING; {
		    (cast(*string) ptr).* = copy_string(fieldValue);
		    return true;
		}
		
		case .BOOL; {
		    if compare(fieldValue, "true") == 0 {
			(cast(*bool) ptr).* = true;
		    } else if compare(fieldValue, "false") == 0 {
			(cast(*bool) ptr).* = false;
		    } else {
			assert(false, tprint("Invalid config value \"%\" for bool type", fieldValue));
		    }
		    return true;
		}
		
		case; assert(false, "Variable type not implemented for read");
	    }
	}
    }
    
    return false;
}

write_to_config :: (builder : *String_Builder, name : string, tag : Type_Info_Tag, ptr : *void) {
    append(builder, name);
    append(builder, ":");
    if tag == {
	case .FLOAT;  append(builder, tprint("%", formatFloat((cast(*float) ptr).*, trailing_width = 2, zero_removal = .NO)));
	case .STRING; append(builder, (cast(*string) ptr).*);
	case .BOOL;   append(builder, tprint("%", (cast(*bool) ptr).*));
	
	case; assert(false, "Variable type not implemented for write");
    }
    
    append(builder, "\n");
}


