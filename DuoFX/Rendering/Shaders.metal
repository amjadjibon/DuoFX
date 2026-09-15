#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float progress;
    float opacity;
    float shadow;
    float edgeSoftness;
    uint isOverlay;
    uint direction;
    uint animation; // 0: sweep, 1: soft fold, 2: perspective
    float foldShadow;
    float foldWidth;
    float foldBlurRadius;
    float perspectiveStrength;
    float perspectiveFeather;
};
struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut blurVertex(uint id [[vertex_id]]) {
    // One oversized triangle covers the viewport without a CPU vertex buffer
    // or a diagonal seam. Texture coordinates still map the desktop exactly.
    constexpr float2 positions[] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    VertexOut out;
    out.position = float4(positions[id], 0.0, 1.0);
    out.uv = positions[id] * float2(0.5, -0.5) + 0.5;
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

float2 directedUV(float2 uv, uint direction) {
    if (direction == 1) return float2(uv.x, 1.0 - uv.y);
    if (direction == 2) return float2(uv.y, uv.x);
    if (direction == 3) return float2(uv.y, 1.0 - uv.x);
    return uv;
}

float2 desktopUV(float2 uv, uint direction) {
    if (direction == 1) return float2(uv.x, 1.0 - uv.y);
    if (direction == 2) return float2(uv.y, uv.x);
    if (direction == 3) return float2(1.0 - uv.y, uv.x);
    return uv;
}

fragment float4 blurFragment(VertexOut in [[stage_in]],
                              texture2d<float> blurredDesktop [[texture(0)]],
                              texture2d<float> sharpDesktop [[texture(1)]],
                              sampler linearSampler [[sampler(0)]],
                              constant Uniforms &u [[buffer(0)]]) {
    float2 sourceUV = in.uv;
    float panelCoverage = 1.0;
    bool perspective = u.animation == 2 && u.perspectiveStrength > 0.0;
    if (perspective && u.progress > 0.0) {
        float2 local = directedUV(in.uv, u.direction);
        // Rotate away from the viewer around the destination edge (bottom for
        // downward motion). Invert the planar projection per output pixel:
        // projectedHeight = height*cos(angle)/(1 + height*depth).
        float angle = u.progress * u.perspectiveStrength * (M_PI_F * 75.0 / 180.0);
        float depth = 0.6 * sin(angle);
        float height = (1.0 - local.y) / max(0.0001, cos(angle) - (1.0 - local.y) * depth);
        float2 projected = float2(0.5 + (local.x - 0.5) * (1.0 + height * depth), 1.0 - height);
        float halfWidth = 0.5 / (1.0 + height * depth);
        float top = 1.0 - cos(angle) / (1.0 + depth);
        // Fade inward from all three moving edges into the dark backdrop.
        // Derivatives express the width in screen pixels, keeping the fade
        // consistent along sloped sides and across portrait/landscape outputs.
        float3 distance = float3(local.x - (0.5 - halfWidth),
                                 (0.5 + halfWidth) - local.x, local.y - top);
        float3 aa = max(fwidth(distance), float3(0.00001));
        float2 pixel = max(fwidth(local), float2(0.00001));
        float reveal = smoothstep(0.0, 0.2, u.progress * u.perspectiveStrength);
        float shortSidePixels = 1.0 / max(pixel.x, pixel.y);
        float fadePixels = u.perspectiveFeather * shortSidePixels * reveal;
        // Round the two corners opposite the hinge independently of tilt
        // strength, so gentle perspective still has a visible curve. Ease in
        // near fully open and zero strength; compensate for the inward fade.
        float cornerReveal = smoothstep(0.0, 0.15, u.progress)
            * smoothstep(0.0, 0.03, u.perspectiveStrength);
        float radius = 0.012 * shortSidePixels * cornerReveal + fadePixels * 0.5;
        float3 edgePixels = distance / aa;
        float2 corner = radius - float2(min(edgePixels.x, edgePixels.y), edgePixels.z);
        float outline = radius - length(max(corner, 0.0))
            - min(max(corner.x, corner.y), 0.0);
        panelCoverage = smoothstep(-1.0, 1.0 + fadePixels, outline);
        sourceUV = desktopUV(saturate(projected), u.direction);
    }
    float coordinate = directedUV(sourceUV, u.direction).y;
    // Start/end beyond the screen for fully clear / fully covered endpoints.
    float boundary = mix(-u.edgeSoftness, 1.0 + u.edgeSoftness, u.progress);
    float coverage = 1.0 - smoothstep(boundary - u.edgeSoftness,
                                      boundary + u.edgeSoftness, coordinate);
    float3 blurred = blurredDesktop.sample(linearSampler, sourceUV).rgb;
    if (u.animation != 0) {
        // Carry the reference's progressive blur/shading behind a moving front.
        // Darkness starts after the blur and grows with closing, without a rim
        // or a separate shadow stripe. Opening traverses this same path backward.
        float depth = saturate((boundary + u.edgeSoftness - coordinate)
                               / (3.0 * u.foldWidth + u.edgeSoftness));
        float motion = smoothstep(0.0, 1.0, u.progress);
        float radius = u.foldBlurRadius * motion * pow(depth, 1.35);
        blurred = foldBlur(blurredDesktop, linearSampler, sourceUV, radius);
        float shade = motion * pow(saturate((depth - 0.2) / 0.8), 1.35);
        blurred *= 1.0 - saturate(2.0 * u.foldShadow * shade);
    }
    blurred *= 1.0 - u.shadow * 0.35 * u.progress;
    float3 sharp = sharpDesktop.sample(linearSampler, sourceUV).rgb;
    if (perspective) {
        // Opaque black behind the panel covers the untransformed live desktop,
        // so it does not appear twice as the captured image tilts inward.
        float3 color = mix(sharp, blurred, coverage) * panelCoverage;
        return float4(color * u.opacity, u.opacity);
    }
    if (u.isOverlay != 0) {
        float alpha = coverage * u.opacity;
        // Beyond the boundary, leave the real desktop completely unobscured.
        return float4(blurred * alpha, alpha);
    }
    return float4(mix(sharp, blurred, coverage), 1.0);
}
