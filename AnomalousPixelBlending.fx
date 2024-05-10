#include "ReShadeUI.fxh"
#include "ReShade.fxh"

#ifndef MAX_CORNER_WEIGHT
  #define MAX_CORNER_WEIGHT 0.0625
#endif
#ifndef MAX_TRANSVERSE_WEIGHT
  #define MAX_TRANSVERSE_WEIGHT 0.125
#endif

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

uniform float CornerWeight <
  ui_label = "CornerWeight";
  ui_type = "slider";
  ui_min = 0.0; ui_max = MAX_CORNER_WEIGHT; ui_step = 0.001;
> = MAX_CORNER_WEIGHT;

uniform float TransverseWeight <
  ui_label = "TransverseWeight";
  ui_type = "slider";
  ui_min = 0.0; ui_max = MAX_TRANSVERSE_WEIGHT; ui_step = 0.001;
> = MAX_TRANSVERSE_WEIGHT;

uniform float MaxBlendingStrength <
  ui_label = "MaxBlendingStrength";
  ui_type = "slider";
  ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.8;


#define SPB_LUMA_WEIGHTS float3(0.26, 0.6, 0.14)
#define BACKGROUND_DEPTH 1.0


float getLuma(float3 rgb)
{
  return dot(rgb, SPB_LUMA_WEIGHTS);
}

float getDelta(float3 colA, float3 colB) 
{
  return getLuma(abs(colA - colB));
}

float4 getDeltas(float3 target, float3 w, float3 n, float3 e, float3 s)
{
  float4 deltas;
  deltas.r = getDelta(target, w);
  deltas.g = getDelta(target, n);
  deltas.b = getDelta(target, e);
  deltas.a = getDelta(target, s);

  return deltas;
}

float3 BlendingPS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_TARGET {
  // Skip if pixel is part of background. May prevent stars from being eaten
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

  float4 deltas = getDeltas(i, w, n, e, s);

  float maxDelta = max(max(deltas.r,deltas.g), max(deltas.b,deltas.a));

  // early return if Max delta is smaller than min threshold
  if(maxDelta < thresholds.x) discard;

  // Interpolate values between min and max threshold.
  deltas = smoothstep(thresholds.x, thresholds.y, deltas);

  // taking the root of the products of the perpendicular deltas detects corners
  float4 cornerWeights = sqrt(deltas.rgba * deltas.gbar) * CornerWeight;
  // sum of each corner a given pixel is involved in yields its total weight (so far)
  float4 weights = cornerWeights.xyzw + cornerWeights.wxyz;
  float weightSum = dot(weights, float(1.0).xxxx);

  // taking the root of the products of transverse deltas detects whether target pixel is not part of a larger structure
  // this is only an estimate of course
  float2 transWeights = sqrt(deltas.rg * deltas.ba) * TransverseWeight;
  // Scale weight of transverse weights by size of existing weights. Prevents shader from blending too aggressively
  weights += ((8 * MAX_CORNER_WEIGHT) - weightSum) * transWeights.xyxy;
  weightSum = dot(weights, float(1.0).xxxx);

  // finally, determine how much of the neighbouring pixels must be blended in, according to their weight
  float3 blendColors = n * weights.g + w * weights.r + e * weights.b + s * weights.a;

  float3 result = blendColors + (i * (1.0 - weightSum));
  return lerp(i, result, MaxBlendingStrength);
}

technique AnomalousPixelBlending {
  pass Blending
  {
    VertexShader = PostProcessVS;
    PixelShader = BlendingPS;
  }
}