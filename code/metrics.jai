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

update_debug_metrics :: (metrics : *DebugMetrics) {
    metrics.timeSinceLastMetricUpdate += loam.deltaTime;
    if metrics.timeSinceLastMetricUpdate >= METRIC_UPDATE_RATE {
	metrics.framesPerSecond = cast(u32) (1.0 / loam.deltaTime + 0.5);
	metrics.msPerFrame = loam.deltaTime * 1000.0;
	metrics.ramUsage = get_ram_usage();

	metrics.totalDrawCalls = 0;
	metrics.nonDebugDrawCalls = 0;
	for vk.pipelines {
	    metrics.totalDrawCalls += cast(u32) it.renderCommands.count;
	}

	metrics.nonDebugDrawCalls = metrics.totalDrawCalls;
	for loam.debugUIElements {
	    if it.type == .Text {
		metrics.nonDebugDrawCalls -= xx it.text.glyphs.count;
	    } else {
		metrics.nonDebugDrawCalls -= 1;
	    }
	}

	metrics.timeSinceLastMetricUpdate -= METRIC_UPDATE_RATE;

	TIMING_MARKER("Pre Metric Text Update");
	
	update_text(frameTimeText.text, tprint("Frame Time: % / % (%Hz)", metrics.framesPerSecond, metrics.msPerFrame, refreshRate));
	update_text(ramUsageText.text,  tprint(" RAM Usage: %", to_size_string(metrics.ramUsage)));
	update_text(drawCallText.text,  tprint("Draw Calls: % (D: %)", metrics.nonDebugDrawCalls, metrics.totalDrawCalls - metrics.nonDebugDrawCalls));
    }
}

update_debug_ui_regions :: () {
    update_region(frameTimeText, get_default_interact_region(frameTimeText.text));
    update_region(ramUsageText,  get_default_interact_region(ramUsageText.text));
    update_region(drawCallText,  get_default_interact_region(drawCallText.text));
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

    Scope :: struct {
	timeStart : float64;
	timeEnd   : float64;
	name      : string;
    }
    scopes : [..] Scope;
}
__timingData : TimingData;

TIMING_SCOPE :: (name := "") #expand {
    scopeName := name;
    if name.count == 0 {
	scopeName = context.stack_trace.info.name;
    }
    __loam_scope_time_start := seconds_since_init();
    `defer array_add(*__timingData.scopes, .{ __loam_scope_time_start, seconds_since_init(), scopeName });
}

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

TIMING_FRAME_END :: (print : bool) #expand {
    if print then TIMING_PRINT_DATA();
    array_reset(*__timingData.markers);
    array_reset(*__timingData.scopes);
    __timingData.start = 0;
}

TIMING_PRINT_DATA :: () #expand {
    print("\n=================================================\n");
    print("\nMARKERS:\n");
    deltaMs := loam.deltaTime * 1000.0;
    for * __timingData.markers {
	it.timeForSection *= 1000.0;
	print("%: % (%\%)\n", it.name, it.timeForSection, (it.timeForSection / deltaMs) * 100.0);
    }
    print("Total Frame Time: % (%)\n", deltaMs, cast(u32) (1.0 / loam.deltaTime + 1.0));

    if __timingData.scopes.count {
	print_color("\nSCOPES:\n", color=.HI_BLUE);
	for * __timingData.scopes {
	    timeForScope := (it.timeEnd - it.timeStart) * 1000.0;
	    print_color("%: % (%\%)\n", it.name, timeForScope, (timeForScope / deltaMs) * 100.0, color=.HI_BLUE);
	}
    }
    print("\n=================================================\n");
}


