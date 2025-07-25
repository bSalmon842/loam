/*
Project: Loam
File: utility.jai
Author: Brock Salmon
Created: 27APR2025
*/

APP_NAME :: "loam";

Invalid_Codepath :: () {
    assert(false, "Invalid Codepath");
}

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

round_to :: (value : $T, $type : Type) -> s64 {
    return cast(type) (value + 0.5);
}

to_radians :: (degrees : float) -> float {
    return degrees * (TAU / 360.0);
}

is_in_array :: (value : $T, array : [] T) -> bool {
    for array { if it == value then return true; }
    return false;
}

from_array_cstr :: (cstr : [] u8) -> string {
    result := cast(string) cstr;
    result.count = find_index_from_left(result, "\0");
    return result;
}

seconds_to_nanoseconds :: (seconds : u64) -> u64 {
    return seconds * 1_000_000_000;
}

get_ram_usage :: () -> u64 {
    #if OS == .WINDOWS {
	info : WindowsE.PROCESS_MEMORY_COUNTERS;
	WindowsE.GetProcessMemoryInfo(WindowsE.GetCurrentProcess(), *info, size_of(WindowsE.PROCESS_MEMORY_COUNTERS));
	return info.WorkingSetSize;
    } else #if OS == .ANDROID {
	// NOTE: Doing stupid stuff to get RAM usage without the NDK because that was an entire mess
	usageKB : u64;
	file := fopen("/proc/self/status", "r");
	if file {
	    line : [256] u8;
	    
	    strncmp :: (a : *u8, b : *u8, count : s64) -> s64 {
		for 0 .. count-1 {
		    aChar := a[it];
		    bChar := b[it];
		    if aChar < bChar then return -1;
		    if aChar > bChar then return 1;
		}

		return 0;
	    }
	    while fgets(line.data, line.count, file) {
		if strncmp(line.data, "VmRSS:", 6) == 0 {
		    sscanf(line.data + 6, "%lu", *usageKB);
		    break;
		}
	    }
	}

	fclose(file);
	return KB(usageKB);
    }

    return 0;
}

get_refresh_rate :: (window : Window_Type) -> u32 {
    #if OS == .WINDOWS {
	monitor := Windows.MonitorFromWindow(window, Windows.MONITOR_DEFAULTTONEAREST);
	info : WindowsE.MONITORINFOEXA;
	info.cbSize = size_of(WindowsE.MONITORINFOEXA);
	if WindowsE.GetMonitorInfoA(monitor, *info) {
	    deviceMode : WindowsE.DEVMODEA;
	    deviceMode.dmSize = size_of(WindowsE.DEVMODEA);
	    if WindowsE.EnumDisplaySettingsA(info.szDevice.data, WindowsE.ENUM_CURRENT_SETTINGS, *deviceMode) {
		return deviceMode.dmDisplayFrequency;
	    }
	}
    } else #if OS == .ANDROID {
	env : *JNIEnv;
	context.android_app.activity.vm.*.GetEnv(context.android_app.activity.vm, cast(**void) *env, JNI_VERSION_1_6);
	if context.android_app.activity.vm.*.AttachCurrentThread(context.android_app.activity.vm, *env, null) == 0 {
	    activityClass := env.*.GetObjectClass(env, context.android_app.activity.clazz);
	    getWindowManager := env.*.GetMethodID(env, activityClass, "getWindowManager".data, "()Landroid/view/WindowManager;".data);
	    windowManager := env.*.CallObjectMethod(env, context.android_app.activity.clazz, getWindowManager);
	    
	    wmClass := env.*.GetObjectClass(env, windowManager);
	    getDefaultDisplay := env.*.GetMethodID(env, wmClass, "getDefaultDisplay".data, "()Landroid/view/Display;".data);
	    display := env.*.CallObjectMethod(env, windowManager, getDefaultDisplay);

	    displayClass := env.*.GetObjectClass(env, display);
	    getRefreshRate := env.*.GetMethodID(env, displayClass, "getRefreshRate".data, "()F".data);
	    refreshRate := env.*.CallFloatMethod(env, display, getRefreshRate);

            context.android_app.activity.vm.*.DetachCurrentThread(context.android_app.activity.vm);
	    if refreshRate > 0 then return cast(u32) (refreshRate + 0.5);
	}
    }

    return 60; // Fallback value
}
