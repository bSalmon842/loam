/*
Project: Loam
File: metrics.jai
Author: Brock Salmon
Created: 22JUN2025
*/

ACTIVATE_TIMING :: false;

METRIC_UPDATE_RATE :: 0.1;
DebugMetrics :: struct {
    timeSinceLastMetricUpdate : float64;
    updateMetrics : bool;
    
    framesPerSecond : u32;
    msPerFrame : float64;
    ramUsage : u64;
    
    pipelineDrawCalls : [PIPELINE_COUNT] u32;
}

update_debug_metrics :: (metrics : *DebugMetrics) {
    metrics.updateMetrics = false;
    metrics.timeSinceLastMetricUpdate += loam.deltaTime;
    if metrics.timeSinceLastMetricUpdate >= METRIC_UPDATE_RATE {
	metrics.framesPerSecond = cast(u32) (1.0 / loam.deltaTime + 0.5);
	metrics.msPerFrame = loam.deltaTime * 1000.0;
	metrics.ramUsage = get_ram_usage();
	
	for pipeline : vk.pipelines {
	    metrics.pipelineDrawCalls[it_index] = 0;
	    if pipeline.isSpritePipeline {
		metrics.pipelineDrawCalls[it_index] += pipeline.sprites.count;
	    } else {
		for render : pipeline.renderCommands {
		    if render {
			metrics.pipelineDrawCalls[it_index] += 1;
		    }
		}
	    }
	}
	
	metrics.timeSinceLastMetricUpdate -= METRIC_UPDATE_RATE;
	metrics.updateMetrics = true;
    }
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

#if ACTIVATE_TIMING {
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
} else {
    TIMING_SCOPE :: (name := "") #expand {}
    TIMING_FRAME_START :: () #expand {}
    TIMING_MARKER :: (name : string) #expand {}
    TIMING_FRAME_END :: (print : bool) #expand {}
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

// RAM Tracking (must be in same scope currently
__totalRAMDiff := 0;
RAM_CHECK_START :: () #expand {
    `__frameRAMStart := cast(s64) get_ram_usage();
}

RAM_CHECK_END :: () #expand {
    ramDiff := cast(s64) get_ram_usage() - `__frameRAMStart;
    if ramDiff != 0 {
	__totalRAMDiff += ramDiff;
	print(ifx ramDiff > 0 then "Frame: +%\n" else "Frame: -%\n", to_size_string(abs_to_u64(ramDiff)));
	print(ifx totalRAMDiff > 0 then "\tTotal: +%\n" else "\tTotal: -%\n", to_size_string(abs_to_u64(__totalRAMDiff)));
    }
}

