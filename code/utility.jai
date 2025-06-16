/*
Project: Loam
File: utility.jai
Author: Brock Salmon
Created: 27APR2025
*/

APP_NAME :: "loam";

KB :: (value : u64) -> u64 {
    return value * 1024;
}

MB :: (value : u64) -> u64 {
    return KB(value * 1024);
}

GB :: (value : u64) -> u64 {
    return MB(value * 1024);
}

to_size_string :: (value : u64) -> string {
    if value > GB(1) {
	floatValue := cast(float) value / cast(float) GB(1);
	return tprint("% GB", formatFloat(floatValue, 1, 2));
    } else if value > MB(1) {
	floatValue := cast(float) value / cast(float) MB(1);
	return tprint("% MB", formatFloat(floatValue, 1, 2));
    } else if value > KB(1) {
	floatValue := cast(float) value / cast(float) KB(1);
	return tprint("% KB", formatFloat(floatValue, 1, 2));
    } else {
	return tprint("% bytes", value);
    }
}

to_radians :: (degrees : float) -> float {
    return degrees * (TAU / 360.0);
}

is_in_array :: (value : $T, array : [] T) -> bool #must {
    for array { if it == value then return true; }
    return false;
}

from_array_cstr :: (cstr : [] u8) -> string #must {
    result := cast(string) cstr;
    result.count = find_index_from_left(result, "\0");
    return result;
}

seconds_to_nanoseconds :: (seconds : u64) -> u64 #must {
    return seconds * 1_000_000_000;
}
