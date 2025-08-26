/*
Project: Loam
File: thread.jai
Author: Brock Salmon
Created: 11JUL2025
*/

ThreadWorkType :: enum {
    // Audio;
}

ThreadWork :: struct {
    type : ThreadWorkType;

    next : *ThreadWork;
    prev : *ThreadWork;
}

ThreadWorkQueue :: struct {
    sentinel : ThreadWork;
    count : u32;
}

get_number_of_threads_for_device :: () -> s32 {
    cpuCount := get_number_of_processors();
    assert(cpuCount > 1);

    if cpuCount > 64 then cpuCount = 64;    
    cpuCount = max(cpuCount-1, 2);
    
    return cpuCount;
}
