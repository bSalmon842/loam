/*
Project: Loam
File: utility.jai
Author: Brock Salmon
Created: 27APR2025
*/

is_in_array :: (value : $T, array : [] T) -> bool #must {
    for array { if it == value then return true; }
    return false;
}

from_array_cstr :: (cstr : [] u8) -> string #must {
    result := cast(string) cstr;
    result.count = find_index_from_left(result, "\0");
    return result;
}
