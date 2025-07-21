/*
Project: Loam
File: metrics.jai
Author: Brock Salmon
Created: 22JUN2025
*/

METRIC_UPDATE_RATE :: 0.1;
DebugMetrics :: struct {
    timeSinceLastMetricUpdate : float64;
    
    framesPerSecond : u32;
    msPerFrame : float64;
    ramUsage : u64;

    totalDrawCalls    : u32;
    nonDebugDrawCalls : u32;
}

frameTimeText : *UI_Element;
ramUsageText  : *UI_Element;
drawCallText  : *UI_Element;

update_debug_metrics :: (loam : *LoamState, metrics : *DebugMetrics) {
    metrics.timeSinceLastMetricUpdate += loam.deltaTime;
    if metrics.timeSinceLastMetricUpdate >= METRIC_UPDATE_RATE {
	metrics.framesPerSecond = cast(u32) (1.0 / loam.deltaTime + 0.5);
	metrics.msPerFrame = loam.deltaTime * 1000.0;
	metrics.ramUsage = get_ram_usage();

	metrics.totalDrawCalls = 0;
	metrics.nonDebugDrawCalls = 0;
	for loam.vk.pipelines {
	    metrics.totalDrawCalls += cast(u32) it.renderCommands.count;
	    
	}

	metrics.nonDebugDrawCalls = metrics.totalDrawCalls;
	metrics.nonDebugDrawCalls -= xx loam.debugUIElements.count;

	metrics.timeSinceLastMetricUpdate -= METRIC_UPDATE_RATE;

	update_text(loam, frameTimeText.text, tprint("Frame Time: % / % (%Hz)", metrics.framesPerSecond, metrics.msPerFrame, refreshRate));
	update_text(loam, ramUsageText.text, tprint(" RAM Usage: %", to_size_string(metrics.ramUsage)));
	update_text(loam, drawCallText.text, tprint("Draw Calls: % (D: %)", metrics.nonDebugDrawCalls, metrics.totalDrawCalls - metrics.nonDebugDrawCalls));
    }
}

update_debug_ui_regions :: () {
    update_region(frameTimeText, get_default_interact_region(frameTimeText.text));
    update_region(ramUsageText, get_default_interact_region(ramUsageText.text));
    update_region(drawCallText, get_default_interact_region(drawCallText.text));
}

// Timing System
TimingData :: struct {
    start : float64;

    Marker :: struct {
	timeAtPoint : float64;
	timeForSection : float64;
	name : string;
    }
    markers : [..] Marker;
}
__timingData : TimingData;


TIMING_FRAME_START :: () #expand {
    __timingData.start = seconds_since_init();
}

TIMING_MARKER :: (name : string) #expand {
    timeAtPoint := seconds_since_init();
    cumulativeMarkerTime : float64;
    for __timingData.markers {
	cumulativeMarkerTime += it.timeForSection;
    }
    timeForSection := timeAtPoint - (cumulativeMarkerTime + __timingData.start);
    array_add(*__timingData.markers, .{ timeAtPoint, timeForSection, name });
}

TIMING_FRAME_END :: (print : bool, loam : *LoamState) #expand {
    if print then TIMING_PRINT_DATA();
    array_reset(*__timingData.markers);
    __timingData.start = 0;
}

TIMING_PRINT_DATA :: () #expand {
    print("\n");
    deltaMs := `loam.deltaTime * 1000.0;
    for * __timingData.markers {
	it.timeForSection *= 1000.0;
	print("%: % (%\%)\n", it.name, it.timeForSection, (it.timeForSection / deltaMs) * 100.0);
    }
    print("Total Frame Time: % (%)\n\n", deltaMs, cast(u32) (1.0 / `loam.deltaTime + 1.0));
}


