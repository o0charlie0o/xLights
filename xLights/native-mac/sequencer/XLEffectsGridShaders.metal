/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include <metal_stdlib>
using namespace metal;

struct EffectsGridUniforms {
    float2 viewportSize;
    float2 scrollOffset;
    float zoomLevel;
    float rowHeight;
    float padding0;
    float padding1;
};

struct VertexIn {
    float2 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

struct RoundedRectVertexIn {
    float2 position  [[attribute(0)]];
    float4 color     [[attribute(1)]];
    float2 rectMin   [[attribute(2)]];
    float2 rectMax   [[attribute(3)]];
    float  cornerRadius [[attribute(4)]];
};

struct RoundedRectVertexOut {
    float4 position [[position]];
    float4 color;
    float2 fragCoord;
    float2 rectMin;
    float2 rectMax;
    float  cornerRadius;
};

// Simple colored vertex shader for grid lines, selection overlays, playback indicator
vertex VertexOut effectsGridVertexShader(
    VertexIn in [[stage_in]],
    constant EffectsGridUniforms &uniforms [[buffer(1)]])
{
    VertexOut out;
    float2 pos = in.position;
    float2 ndc = (pos / uniforms.viewportSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;
    out.position = float4(ndc, 0.0, 1.0);
    out.color = in.color;
    return out;
}

fragment float4 effectsGridFragmentShader(VertexOut in [[stage_in]])
{
    return in.color;
}

// Rounded rectangle vertex shader for effect blocks
vertex RoundedRectVertexOut effectBlockVertexShader(
    RoundedRectVertexIn in [[stage_in]],
    constant EffectsGridUniforms &uniforms [[buffer(1)]])
{
    RoundedRectVertexOut out;
    float2 pos = in.position;
    float2 ndc = (pos / uniforms.viewportSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;
    out.position = float4(ndc, 0.0, 1.0);
    out.color = in.color;
    out.fragCoord = in.position;
    out.rectMin = in.rectMin;
    out.rectMax = in.rectMax;
    out.cornerRadius = in.cornerRadius;
    return out;
}

fragment float4 effectBlockFragmentShader(RoundedRectVertexOut in [[stage_in]])
{
    float2 p = in.fragCoord;
    float2 rMin = in.rectMin;
    float2 rMax = in.rectMax;
    float r = in.cornerRadius;

    // Signed distance to rounded rectangle
    float2 halfSize = (rMax - rMin) * 0.5;
    float2 center = (rMin + rMax) * 0.5;
    float2 q = abs(p - center) - halfSize + r;
    float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;

    if (dist > 0.5) {
        discard_fragment();
    }

    float4 color = in.color;

    // Subtle edge darkening for depth
    float edgeFactor = smoothstep(0.0, 2.0, -dist);
    color.rgb *= mix(0.85, 1.0, edgeFactor);

    // Anti-alias the edge
    float alpha = 1.0 - smoothstep(-0.5, 0.5, dist);
    color.a *= alpha;

    return color;
}

// Outline-only rounded rectangle fragment shader for selection highlight
fragment float4 effectBlockOutlineFragmentShader(RoundedRectVertexOut in [[stage_in]])
{
    float2 p = in.fragCoord;
    float2 rMin = in.rectMin;
    float2 rMax = in.rectMax;
    float r = in.cornerRadius;

    float2 halfSize = (rMax - rMin) * 0.5;
    float2 center = (rMin + rMax) * 0.5;
    float2 q = abs(p - center) - halfSize + r;
    float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;

    // Only render the outline band (2px wide)
    float outerEdge = smoothstep(0.5, -0.5, dist);
    float innerEdge = smoothstep(-1.5, -2.5, dist);
    float outline = outerEdge - innerEdge;

    if (outline < 0.01) {
        discard_fragment();
    }

    float4 color = in.color;
    color.a *= outline;
    return color;
}
