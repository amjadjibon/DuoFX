#include <metal_stdlib>
using namespace metal;

struct MeshVertex { float2 position; float2 uv; };
struct Uniforms {
    float progress;
    float perspective;
    float stretch;
    float opacity;
    float shadow;
    float fade;
    float viewerDistance;
    float padding;
};
struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float height;
};

vertex VertexOut bendVertex(uint id [[vertex_id]],
                            constant MeshVertex *vertices [[buffer(0)]],
                            constant Uniforms &u [[buffer(1)]]) {
    MeshVertex v = vertices[id];
    float height = (v.position.y + 1.0) * 0.5;
    float theta = u.progress * M_PI_F * 0.5;
    float depth = height * sin(theta) * u.perspective;
    float w = 1.0 + depth / u.viewerDistance;
    float y = height * cos(theta) * (1.0 + u.stretch * u.progress * (1.0 - u.progress));
    VertexOut out;
    // Homogeneous projection preserves perspective-correct texture interpolation.
    out.position = float4(v.position.x, 2.0 * y - w, 0.0, w);
    out.uv = v.uv;
    out.height = height;
    return out;
}

fragment float4 bendFragment(VertexOut in [[stage_in]],
                              texture2d<float> desktop [[texture(0)]],
                              sampler linearSampler [[sampler(0)]],
                              constant Uniforms &u [[buffer(0)]]) {
    float3 color = desktop.sample(linearSampler, in.uv).rgb;
    float shade = 1.0 - u.shadow * u.progress * (0.25 + 0.75 * in.height);
    color *= shade * (1.0 - u.fade);
    return float4(color * u.opacity, u.opacity);
}
