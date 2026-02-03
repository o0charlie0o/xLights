#pragma once

#import <simd/simd.h>

// Shared types between Metal shaders and Objective-C++ code

struct TimelineVertex {
    simd_float2 position;
    simd_float4 color;
};

struct TimelineUniforms {
    simd_float2 viewportSize;
    simd_float2 scrollOffset;
    float zoomScale;
    float padding;
};

// Effect block data (CPU-side)
struct EffectBlock {
    int rowIndex;
    float startTime;    // seconds
    float endTime;      // seconds
    float r, g, b, a;
    bool selected;
    int effectId;       // unique ID for hit-testing
};

// Timeline layout constants
static const float kRowHeight = 28.0f;
static const float kRulerHeight = 32.0f;
static const float kRowLabelWidth = 160.0f;
static const float kGridLineWidth = 1.0f;
static const float kPixelsPerSecond = 100.0f;  // base zoom level
static const float kPlayheadWidth = 2.0f;
static const float kEffectPadding = 1.0f;
static const float kMinZoom = 0.1f;
static const float kMaxZoom = 20.0f;
