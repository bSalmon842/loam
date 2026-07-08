/*
Project: Loam Engine
File: file.jai
Author: Brock Salmon
Created: 06JUL2026
*/

read_file :: (path : string, errorOnFail := true) -> string, bool {
    #if OS == .ANDROID {
    	found := true;
	fileStream := SDL.io_from_file(tprint("%\0", path).data, "rb");
	if !fileStream {
	    log(ifx errorOnFail then .FATAL else .WARN, "Failed to open file for reading % with SDL error: %", path, to_string(SDL.get_error()));
	    return .{}, false;
	}
	
	data := alloc_string(SDL.get_io_size(fileStream));
	bytesRead := SDL.read_io(fileStream, data.data, cast(u32) data.count);
	if bytesRead == 0 {
	    log(ifx errorOnFail then .FATAL else .WARN, "Failed to read file %!", path);
	    free(data);
	    SDL.close_io(fileStream);
	    return .{}, false;
	}
	SDL.close_io(fileStream);
    } else {
	data, found := read_entire_file(path);
    }

    return data, found;
}

write_file :: (path : string, data : string) -> bool {
    #if OS == .ANDROID {
	fileStream := SDL.io_from_file(tprint("%\0", path).data, "wb");
	if !fileStream {
	    log(.FATAL, "Failed to open file for writing % with SDL error: %", path, to_string(SDL.get_error()));
	    return false;
	}

	bytesWritten := SDL.write_io(fileStream, data.data, cast(u32) data.count);
	if bytesWritten == 0 {
	    log(.FATAL, "Failed to write file %!", path);
	    SDL.close_io(fileStream);
	    return false;
	}
	SDL.close_io(fileStream);
	return true;
    } else {
	return write_entire_file(path, data);
    }
}
