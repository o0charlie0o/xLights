#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

struct Uniforms {
    float2 viewportSize;
    float2 scrollOffset;
    float  zoomScale;
    float  padding;
};

// Vertex shader: transforms pixel coordinates to clip space with scroll/zoom
vertex VertexOut timelineVertex(VertexIn in [[stage_in]],
                                constant Uniforms &uniforms [[buffer(2)]]) {
    VertexOut out;

    // Apply scroll offset and zoom
    float2 pos = in.position;
    pos.x = (pos.x - uniforms.scrollOffset.x) * uniforms.zoomScale;
    pos.y = pos.y - uniforms.scrollOffset.y;

    // Convert from pixel coordinates to clip space [-1, 1]
    out.position = float4(
        (pos.x / uniforms.viewportSize.x) * 2.0 - 1.0,
        1.0 - (pos.y / uniforms.viewportSize.y) * 2.0,
        0.0,
        1.0
    );

    out.color = in.color;
    return out;
}

// Fragment shader: pass-through color
fragment float4 timelineFragment(VertexOut in [[stage_in]]) {
    return in.color;
}

// Text rendering vertex shader - passes through texture coords
struct TextVertexIn {
    float2 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

struct TextVertexOut {
    float4 position [[position]];
    float4 color;
    float2 texCoord;
};

vertex TextVertexOut textVertex(TextVertexIn in [[stage_in]],
                                constant Uniforms &uniforms [[buffer(2)]]) {
    TextVertexOut out;

    float2 pos = in.position;
    pos.x = (pos.x - uniforms.scrollOffset.x) * uniforms.zoomScale;
    pos.y = pos.y - uniforms.scrollOffset.y;

    out.position = float4(
        (pos.x / uniforms.viewportSize.x) * 2.0 - 1.0,
        1.0 - (pos.y / uniforms.viewportSize.y) * 2.0,
        0.0,
        1.0
    );

    out.color = in.color;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 textFragment(TextVertexOut in [[stage_in]],
                              texture2d<float> fontTexture [[texture(0)]]) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear);
    float alpha = fontTexture.sample(texSampler, in.texCoord).r;
    return float4(in.color.rgb, in.color.a * alpha);
}
