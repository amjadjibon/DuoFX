#include <metal_stdlib>
using namespace metal;

struct MeshVertex { float2 position; float2 uv; };
struct Uniforms {
    float progress;
    float opacity;
    float shadow;
    float edgeSoftness;
    uint isOverlay;
};
struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut blurVertex(uint id [[vertex_id]],
                            constant MeshVertex *vertices [[buffer(0)]]) {
    MeshVertex v = vertices[id];
    VertexOut out;
    // Desktop coordinates stay fixed. Only the blur coverage moves.
    out.position = float4(v.position, 0.0, 1.0);
    out.uv = v.uv;
    return out;
}

fragment float4 blurFragment(VertexOut in [[stage_in]],
                              texture2d<float> blurredDesktop [[texture(0)]],
                              texture2d<float> sharpDesktop [[texture(1)]],
                              sampler linearSampler [[sampler(0)]],
                              constant Uniforms &u [[buffer(0)]]) {
    // UV y increases downward. Start/end beyond the screen for a fully clear
    // open state and a fully blurred closed state, including the feathered edge.
    float boundary = mix(-u.edgeSoftness, 1.0 + u.edgeSoftness, u.progress);
    float coverage = 1.0 - smoothstep(boundary - u.edgeSoftness,
                                      boundary + u.edgeSoftness, in.uv.y);
    float3 blurred = blurredDesktop.sample(linearSampler, in.uv).rgb;
    blurred *= 1.0 - u.shadow * 0.35 * u.progress;
    if (u.isOverlay != 0) {
        float alpha = coverage * u.opacity;
        // Below the boundary, leave the real desktop completely unobscured.
        return float4(blurred * alpha, alpha);
    }
    float3 sharp = sharpDesktop.sample(linearSampler, in.uv).rgb;
    return float4(mix(sharp, blurred, coverage), 1.0);
}
