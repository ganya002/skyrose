// Metal port of Caelestia's `plugin/src/Caelestia/Blobs/shaders/blob.frag` (@ bcbb5d5). One
// renderer draws the whole group (frame + every drawer), so the per-renderer ownership discard is
// gone; everything else (circular smin, border compression, border sinks, sharp outer frame
// edge) is line for line. Extras for macOS: the display's physical corner radii, a soft shadow
// (upstream: MultiEffect blurMax 15 on the group) and a mask mode for the behind-window blur.
//
// Buffers (all float4):
//   u[0] = (viewW pt, viewH pt, backing scale, smoothFactor k)
//   u[1] = (rectCount, hasInverted, mode 0 fill / 1 mask, invertedRadius)
//   u[2] = fill colour (straight rgb, alpha)
//   u[3] = inverted outer (cx, cy, hw, hh)   u[4] = inverted inner (cx, cy, hw, hh)
//   u[5] = shadow (rgb, opacity)             u[6] = display corner radii (tr, br, bl, tl)
//   u[7] = (shadow blur pt, 0, 0, 0)        u[8] = frame inner radii (tr, br, bl, tl)
//   rd[i*5 + 0] = (cx, cy, hw, hh)  rd[i*5 + 1] = (excludeMask, 0, 0, minEig)
//   rd[i*5 + 2] = inverse deform (m00, m01, m10, m11)  rd[i*5 + 3] = (screenHalfX, screenHalfY, 0, 0)
//   rd[i*5 + 4] = effective radii (tr, br, bl, tl)
enum BlobShader {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct VOut { float4 position [[position]]; };

    vertex VOut blob_vertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        VOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }

    static float sdRoundedBox(float2 p, float2 c, float2 h, float r) {
        float2 d = abs(p - c) - h + float2(r);
        return length(max(d, float2(0.0))) + min(max(d.x, d.y), 0.0) - r;
    }

    static float sdRoundedBox4(float2 p, float2 c, float2 h, float4 r) {
        p -= c;
        r.xy = (p.x > 0.0) ? r.xy : r.wz;
        r.x = (p.y > 0.0) ? r.y : r.x;
        float2 q = abs(p) - h + r.x;
        return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
    }

    static float sdBox(float2 p, float2 c, float2 h) {
        float2 d = abs(p - c) - h;
        return length(max(d, float2(0.0))) + min(max(d.x, d.y), 0.0);
    }

    static float smin(float a, float b, float k) {
        return max(k, min(a, b)) - length(max(float2(k) - float2(a, b), float2(0.0)));
    }

    static float smaxSharpA(float a, float b, float k) {
        float sm = min(-k, max(a, b)) + length(max(float2(a, b) + float2(k), float2(0.0)));
        float blend = (sm - max(a, b)) * smoothstep(0.0, k * 0.5, -a);
        return max(a, b) + blend;
    }

    fragment float4 blob_fragment(VOut in [[stage_in]],
                                  constant float4 *u [[buffer(0)]],
                                  constant float4 *rd [[buffer(1)]]) {
        float scale = u[0].z;
        float smoothFactor = u[0].w;
        int rectCount = int(u[1].x);
        bool hasInverted = u[1].y > 0.5;
        bool mask = u[1].z > 0.5;
        float4 invertedOuter = u[3];
        float4 invertedInner = u[4];
        float2 pixel = in.position.xy / scale;

        float dArr[16];
        for (int i = 0; i < rectCount; i++) {
            float4 rect = rd[i * 5];
            float4 props = rd[i * 5 + 1];
            float4 invDm = rd[i * 5 + 2];
            float4 sh = rd[i * 5 + 3];
            float4 radii = rd[i * 5 + 4];
            float2 center = rect.xy;
            float2 extent = sh.xy + float2(smoothFactor * 1.5);
            if (abs(pixel.x - center.x) > extent.x || abs(pixel.y - center.y) > extent.y) {
                dArr[i] = 1e10;
                continue;
            }
            float2 rel = pixel - center;
            float2 tp = center + float2(invDm.x * rel.x + invDm.y * rel.y, invDm.z * rel.x + invDm.w * rel.y);
            float d = sdRoundedBox4(tp, center, rect.zw, radii);
            d *= max(props.w, 0.01);
            if (hasInverted) {
                float2 screenHalf = sh.xy;
                float distY0 = (center.y + screenHalf.y) - (invertedInner.y - invertedInner.w);
                float distY1 = (invertedInner.y + invertedInner.w) - (center.y - screenHalf.y);
                float distX0 = (center.x + screenHalf.x) - (invertedInner.x - invertedInner.z);
                float distX1 = (invertedInner.x + invertedInner.z) - (center.x - screenHalf.x);
                float yProx = 1.0 - min(smoothstep(0.0, smoothFactor, distY0), smoothstep(0.0, smoothFactor, distY1));
                float xProx = 1.0 - min(smoothstep(0.0, smoothFactor, distX0), smoothstep(0.0, smoothFactor, distX1));
                float2 q = abs(pixel - center) - screenHalf;
                float2 qp = max(q, float2(0.0));
                float cornerLen = length(qp);
                float gradX = qp.x / max(cornerLen, 0.001);
                float gradY = qp.y / max(cornerLen, 0.001);
                float faceY = smoothstep(-4.0, 4.0, q.y - q.x);
                float faceX = 1.0 - faceY;
                float t = smoothstep(0.0, 2.0, cornerLen);
                float xWeight = mix(faceX, gradX, t);
                float yWeight = mix(faceY, gradY, t);
                d *= 1.0 + (xProx * xWeight + yProx * yWeight) * 3.0;
            }
            dArr[i] = d;
        }

        float mergedSdf = 1e10;
        for (int i = 0; i < rectCount; i++) mergedSdf = min(mergedSdf, dArr[i]);
        for (int i = 0; i < rectCount; i++) {
            if (dArr[i] >= 1e9) continue;
            int excludeMask = int(rd[i * 5 + 1].x);
            for (int j = i + 1; j < rectCount; j++) {
                if (dArr[j] >= 1e9) continue;
                if ((excludeMask & (1 << j)) != 0) continue;
                if (max(dArr[i], dArr[j]) >= smoothFactor) continue;
                mergedSdf = min(mergedSdf, smin(dArr[i], dArr[j], smoothFactor));
            }
        }

        if (hasInverted) {
            float dOuter = sdBox(pixel, invertedOuter.xy, invertedOuter.zw) - 1.0;
            float dInner = sdRoundedBox4(pixel, invertedInner.xy, invertedInner.zw, u[8]);
            float innerTop = invertedInner.y - invertedInner.w;
            float innerBot = invertedInner.y + invertedInner.w;
            float innerLeft = invertedInner.x - invertedInner.z;
            float innerRight = invertedInner.x + invertedInner.z;
            float outerTop = invertedOuter.y - invertedOuter.w;
            float outerBot = invertedOuter.y + invertedOuter.w;
            float outerLeft = invertedOuter.x - invertedOuter.z;
            float outerRight = invertedOuter.x + invertedOuter.z;
            float sinkValue = 0.0;
            float preOff = smoothFactor * (2.0 - sqrt(2.0)) * 0.5;
            for (int i = 0; i < rectCount; i++) {
                float2 ctr = rd[i * 5].xy;
                float2 sinkSh = rd[i * 5 + 3].xy;
                float topPen = clamp(innerTop - (ctr.y + sinkSh.y) - preOff, 0.0, innerTop - outerTop);
                float botPen = clamp((ctr.y - sinkSh.y) - innerBot - preOff, 0.0, outerBot - innerBot);
                float leftPen = clamp(innerLeft - (ctr.x + sinkSh.x) - preOff, 0.0, innerLeft - outerLeft);
                float rightPen = clamp((ctr.x - sinkSh.x) - innerRight - preOff, 0.0, outerRight - innerRight);
                float hLat = max(abs(pixel.x - ctr.x) - sinkSh.x, 0.0);
                float vLat = max(abs(pixel.y - ctr.y) - sinkSh.y, 0.0);
                float topZone = 1.0 - smoothstep(innerTop, innerTop + smoothFactor, pixel.y);
                float botZone = smoothstep(innerBot - smoothFactor, innerBot, pixel.y);
                float leftZone = 1.0 - smoothstep(innerLeft, innerLeft + smoothFactor, pixel.x);
                float rightZone = smoothstep(innerRight - smoothFactor, innerRight, pixel.x);
                float s = smoothFactor * 2.0;
                float sink = max(max(topPen * smoothstep(s, 0.0, hLat) * topZone, botPen * smoothstep(s, 0.0, hLat) * botZone),
                                 max(leftPen * smoothstep(s, 0.0, vLat) * leftZone, rightPen * smoothstep(s, 0.0, vLat) * rightZone));
                sinkValue = max(sinkValue, sink);
            }
            dInner -= sinkValue;
            float minThick = min(min(innerTop - outerTop, outerBot - innerBot), min(innerLeft - outerLeft, outerRight - innerRight));
            float kFrame = clamp(min(smoothFactor, minThick - 1.0), 1.0, smoothFactor);
            float dFrame = smaxSharpA(dOuter, -dInner, kFrame);
            mergedSdf = smin(mergedSdf, dFrame, smoothFactor);
        }

        // Anti-aliasing width. Clamped: a rect is culled to 1e10 outside its box (half + 1.5 k),
        // and fwidth across that jump is ~1e10, which made smoothstep paint half-opaque fill
        // along the box edges (Part 7a: the black outline / rectangle around the launcher while
        // it opened and closed). A real edge changes by at most a few points per pixel even under
        // border compression (×4) and jelly, so 4 px is plenty.
        float fw = clamp(fwidth(mergedSdf), 0.5 / scale, 4.0 / scale);
        float alpha = 1.0 - smoothstep(-fw, fw, mergedSdf);

        // The display's own rounded corners (built-in panels): nothing outside them.
        float2 view = u[0].xy;
        float dScreen = sdRoundedBox4(pixel, view * 0.5, view * 0.5, u[6]);
        float sfw = clamp(fwidth(dScreen), 0.5 / scale, 4.0 / scale);
        float screenCover = 1.0 - smoothstep(-sfw, sfw, dScreen);

        if (mask) {
            float a = alpha * screenCover;
            return float4(a, a, a, a);
        }
        float4 fill = u[2];
        float4 shadowColour = u[5];
        float blur = max(u[7].x, 1.0);
        float s = 1.0 - smoothstep(0.0, blur, mergedSdf);
        float shadowA = shadowColour.a * s * s * (1.0 - alpha);
        float a = fill.a * alpha;
        float3 rgb = fill.rgb * a + shadowColour.rgb * shadowA * (1.0 - a);
        float outA = a + shadowA * (1.0 - a);
        return float4(rgb, outA) * screenCover;
    }
    """
}
