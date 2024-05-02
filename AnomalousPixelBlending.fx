#include "ReShadeUI.fxh"
#include "ReShade.fxh"

uniform bool SkipBackground <
  ui_label = "SkipBackground";
  ui_type = "radio";
> = false;

uniform float MinDeltaThreshold <
  ui_label = "MinDeltaThreshold";
  ui_type = "slider";
  ui_min = 0.002; ui_max = 1.0; ui_step = 0.001;
> = 0.075;

uniform float MaxDeltaThreshold <
  ui_label = "MaxDeltaThreshold";
  ui_type = "slider";
  ui_min = 0.002; ui_max = 1.0; ui_step = 0.001;
> = 0.2;

uniform float LumaAdaptationRange <
  ui_label = "LumaAdaptationRange";
  ui_type = "slider";
  ui_min = 0.0; ui_max = 0.97; ui_step = 0.01;
> = 0.95;

uniform float MaxBlendingStrength <
  ui_label = "MaxBlendingStrength";
  ui_type = "slider";
  ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.8;

#define SPB_LUMA_WEIGHTS float3(0.26, 0.6, 0.14)
#define BACKGROUND_DEPTH 1.0
#ifndef MAX_CORNER_WEIGHT
  #define MAX_CORNER_WEIGHT 0.0625
#endif
#ifndef MAX_TRANSVERSE_WEIGHT
  #define MAX_TRANSVERSE_WEIGHT 0.125
#endif
#define BUFFER_METRICS float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT)

float getLuma(float3 rgb)
{
  return dot(rgb, SPB_LUMA_WEIGHTS);
}

float getDelta(float3 colA, float3 colB) 
{
  return getLuma(abs(colA - colB));
}

float3 MyPS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_TARGET {
  if (SkipBackground) {
    float currDepth = ReShade::GetLinearizedDepth(texcoord);
    if (currDepth == BACKGROUND_DEPTH) discard;
  }
  //  x [n] y
  // [w][i][e]
  //  w [s] z
  float3 n,w,e,s,i;
  i = tex2D(ReShade::BackBuffer, texcoord).rgb;
  n = tex2Doffset(ReShade::BackBuffer, texcoord, int2(0.0, -1.0)).rgb; // N
  w = tex2Doffset(ReShade::BackBuffer, texcoord, int2(-1.0, 0.0)).rgb; // W
  e = tex2Doffset(ReShade::BackBuffer, texcoord, int2(1.0, 0.0)).rgb; // E
  s = tex2Doffset(ReShade::BackBuffer, texcoord, int2(0.0, 1.0)).rgb; // S

  // Get luminance of each pixel
  float ln,lw,le,ls,li;
  li = getLuma(i);
  ln = getLuma(n);
  lw = getLuma(w);
  le = getLuma(e);
  ls = getLuma(s);

  // Get largest luma
  float maxLuma = max(max(max(li,ln), max(lw,le)),ls);
  // Get factor by which thresholds should be adapted/predicated. Lower max luma --> lower factor --> lower thresholds
  float adaptationFactor = mad(-LumaAdaptationRange, 1.0 - maxLuma, 1.0);
  // float adaptationFactor = lerp(1.0 - LumaAdaptationRange, 1.0, maxLuma);
  // adapt thresholds
  float2 thresholds = float2(MinDeltaThreshold, MaxDeltaThreshold) * adaptationFactor;

  float4 deltas;
  deltas.r = getDelta(i, w);
  deltas.g = getDelta(i, n);
  deltas.b = getDelta(i, e);
  deltas.a = getDelta(i, s);

  float maxDelta = max(max(deltas.r,deltas.g), max(deltas.b,deltas.a));

  // Max delta must be equal or larger than min threshold
  if(maxDelta < thresholds.x) discard;

  // Interpolate values between min and max threshold.
  deltas = smoothstep(thresholds.x, thresholds.y, deltas);

  // float4 cornerWeights = smoothstep(MinDeltaThreshold, MaxDeltaThreshold, deltas.rgba * deltas.gbar);
  // float4 cornerWeights = deltas.rgba * deltas.gbar * MAX_CORNER_WEIGHT;
  float4 cornerWeights = sqrt(deltas.rgba * deltas.gbar) * MAX_CORNER_WEIGHT;
  // float4 cornerWeights = deltas.aaaa * deltas.rbrb;

  // float4 cornerWeights = sqrt(deltas.rgba * deltas.gbar);
  // cornerWeights = smoothstep(MinDeltaThreshold, MaxDeltaThreshold, cornerWeights) * MAX_CORNER_WEIGHT;

  float4 weights = cornerWeights.xyzw + cornerWeights.wxyz;

  float3 blendColors = n * weights.g + w * weights.r + e * weights.b + s * weights.a;

  float weightSum = dot(weights, float(1.0).xxxx);

  float3 result = blendColors + (i * (1.0 - weightSum));

  return lerp(i, result, MaxBlendingStrength);
}

technique AnomalousPixelBlending {
  pass
  {
    VertexShader = PostProcessVS;
    PixelShader = MyPS;
  }
}