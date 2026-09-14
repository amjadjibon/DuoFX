#include <metal_stdlib>
using namespace metal;

struct MeshVertex { float2 position; float2 uv; };
struct Uniforms {
    float progress;
    float opacity;
    float shadow;
    float edgeSoftness;
    uint isOverlay;
    uint direction;
    uint isFold;
    float foldShadow;
    float foldWidth;
    float foldBlurRadius;
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

// Variable-radius sampling adapted from iphone-duo by jadon7 (MIT).
// See IPhoneDuoLicense.txt. Source coordinates remain anchored to the desktop;
// clamped samples preserve its edges without introducing the phone's black frame.
float3 foldBlur(texture2d<float> desktop, sampler textureSampler, float2 uv, float radius) {
    if (radius <= 0.001) return desktop.sample(textureSampler, uv, level(0.0)).rgb;
    float lod = log2(max(1.0, radius));
    float2 pixel = 1.0 / float2(desktop.get_width(), desktop.get_height());
    float3 color = 0.0;
    for (int y = -2; y <= 2; y++) {
        for (int x = -2; x <= 2; x++) {
            float wx = x == 0 ? 6.0 : (abs(x) == 1 ? 4.0 : 1.0);
            float wy = y == 0 ? 6.0 : (abs(y) == 1 ? 4.0 : 1.0);
            color += desktop.sample(textureSampler, uv + float2(x, y) * pixel * radius, level(lod)).rgb
                * wx * wy / 256.0;
        }
    }
    return color;
}

fragment float4 blurFragment(VertexOut in [[stage_in]],
                              texture2d<float> blurredDesktop [[texture(0)]],
                              texture2d<float> sharpDesktop [[texture(1)]],
                              sampler linearSampler [[sampler(0)]],
                              constant Uniforms &u [[buffer(0)]]) {
    // Transform only coverage coordinates; desktop pixels keep their positions.
    float coordinate = in.uv.y;
    if (u.direction == 1) coordinate = 1.0 - in.uv.y;
    if (u.direction == 2) coordinate = in.uv.x;
    if (u.direction == 3) coordinate = 1.0 - in.uv.x;
    // Start/end beyond the screen for fully clear / fully covered endpoints.
    float boundary = mix(-u.edgeSoftness, 1.0 + u.edgeSoftness, u.progress);
    float coverage = 1.0 - smoothstep(boundary - u.edgeSoftness,
                                      boundary + u.edgeSoftness, coordinate);
    float3 blurred = blurredDesktop.sample(linearSampler, in.uv).rgb;
    if (u.isFold != 0) {
        // Carry the reference's progressive blur/shading behind a moving front.
        // Darkness starts after the blur and grows with closing, without a rim
        // or a separate shadow stripe. Opening traverses this same path backward.
        float depth = saturate((boundary + u.edgeSoftness - coordinate)
                               / (3.0 * u.foldWidth + u.edgeSoftness));
        float motion = smoothstep(0.0, 1.0, u.progress);
        float radius = u.foldBlurRadius * motion * pow(depth, 1.35);
        blurred = foldBlur(blurredDesktop, linearSampler, in.uv, radius);
        float shade = motion * pow(saturate((depth - 0.2) / 0.8), 1.35);
        blurred *= 1.0 - saturate(2.0 * u.foldShadow * shade);
    }
    blurred *= 1.0 - u.shadow * 0.35 * u.progress;
    if (u.isOverlay != 0) {
        float alpha = coverage * u.opacity;
        // Beyond the boundary, leave the real desktop completely unobscured.
        return float4(blurred * alpha, alpha);
    }
    float3 sharp = sharpDesktop.sample(linearSampler, in.uv).rgb;
    return float4(mix(sharp, blurred, coverage), 1.0);
}
