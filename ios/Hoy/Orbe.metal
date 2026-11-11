#include <metal_stdlib>
using namespace metal;

// El orbe del modo voz (Hoy/Orbe.swift lo usa con .colorEffect). Port del GLSL del probador: borde ondulante con
// ruido de valor, halo exponencial, veta de color y un brillo arriba a la izquierda. Solo en el target Hoy.

// Azar sin seno (hash12 de Dave Hoskins): estable en float con cualquier tamaño de entrada.
float orbeAzar(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031f);
    p3 = p3 + float3(dot(p3, p3.yzx + float3(33.33f)));
    return fract((p3.x + p3.y) * p3.z);
}

// Ruido de valor suavizado.
float orbeRuido(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0f - 2.0f * f);
    float a = orbeAzar(i);
    float b = orbeAzar(i + float2(1.0f, 0.0f));
    float c = orbeAzar(i + float2(0.0f, 1.0f));
    float d = orbeAzar(i + float2(1.0f, 1.0f));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// size: lado del lienzo en puntos. time: segundos (ya acelerados según el estado). amp: cuánto ondula el borde.
// azul / ambar: 0…1, cuánto tira la veta hacia cada color. Los colores llegan premultiplicados y opacos.
[[ stitchable ]] half4 orbeTom(float2 position, half4 color, float2 size, float time, float amp,
                               float azul, float ambar, half4 acento, half4 colorAzul, half4 colorAmbar) {
    float lado = max(min(size.x, size.y), 1.0f);
    float2 uv = (position - 0.5f * size) / lado * 2.4f;
    uv.y = -uv.y;   // en SwiftUI la y crece hacia abajo; en el GLSL, hacia arriba
    float l = length(uv);

    // el borde se ondula con ruido muestreado sobre la dirección (sin la costura de atan2 en ±π)
    float2 dir = uv / max(l, 0.0001f);
    float w = orbeRuido(dir * 1.6f + float2(time * 0.6f, time * 0.4f)) * 0.5f
            + orbeRuido(dir * 3.0f + float2(1.0f + time, time * 1.3f)) * 0.25f;
    float radio = 0.62f + 0.05f * sin(time * 1.2f) + amp * (w - 0.3f) * 0.9f;

    float d = l - radio;
    float cuerpo = 1.0f - smoothstep(-0.02f, 0.02f, d);
    float halo = exp(-max(d, 0.0f) * 9.0f) * 0.55f;

    float veta = orbeRuido(uv * 3.0f + float2(time * 0.5f, -time * 0.3f));
    float3 base = float3(acento.rgb);
    float3 otro = mix(base, float3(colorAzul.rgb), clamp(azul, 0.0f, 1.0f));
    otro = mix(otro, float3(colorAmbar.rgb), clamp(ambar, 0.0f, 1.0f));
    float3 col = mix(base, otro, clamp(veta * 1.2f - l * 0.3f, 0.0f, 1.0f));

    float brillo = max(0.0f, 1.0f - length(uv - float2(-0.22f, 0.25f)) * 2.2f);
    col += pow(brillo, 3.0f) * 0.35f;
    col = min(col, float3(1.0f));

    float alfa = clamp(max(cuerpo, halo), 0.0f, 1.0f);
    return half4(half3(col * alfa), half(alfa));   // premultiplicado, como espera SwiftUI
}
