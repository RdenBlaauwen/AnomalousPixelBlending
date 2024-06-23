#include "ReShadeUI.fxh"
#include "ReShade.fxh"

uniform bool SkipBackground <
  ui_label = "SkipBackground";
  ui_type = "radio";
> = false;

uniform float MinDeltaThreshold <
  ui_label = "MinDeltaThreshold";
  ui_type = "slider";
  ui_min = 0.002; ui_max = 1.0; ui_step = 0.01;
> = 0.12;

uniform float MaxDeltaThreshold <
  ui_label = "MaxDeltaThreshold";
  ui_type = "slider";
  ui_min = 0.002; ui_max = 1.0; ui_step = 0.01;
> = 0.2;

uniform float LumaAdaptationRange <
  ui_label = "LumaAdaptationRange";
  ui_type = "slider";
  ui_min = 0.0; ui_max = 0.97; ui_step = 0.01;
> = 0.85;

uniform float HighlightCurve <
  ui_label = "HighlightCurve";
  ui_type = "slider";
  ui_min = 1.0; ui_max = 10.0; ui_step = 0.1;
> = 5.0;

uniform float BlendingStrength <
  ui_label = "BlendingStrength";
  ui_type = "slider";
  ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 1.0;

//TODO: change to highlight preservation (ivnert values)
uniform float HighlightBlendingStrength <
  ui_label = "HighlightBlendingStrength";
  ui_type = "slider";
  ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;

//TODO: rename, add reccomandations
uniform float IsolatedPixelremoval <
  ui_label = "IsolatedPixelremoval";
  ui_type = "slider";
  ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.5;

#ifndef CORNER_WEIGHT
  #define CORNER_WEIGHT 0.0625
#endif
#ifndef TRANSVERSE_WEIGHT
  #define TRANSVERSE_WEIGHT 0.125
#endif


#define SPB_LUMA_WEIGHTS float3(0.26, 0.6, 0.14)
#define BACKGROUND_DEPTH 1.0
#define EULER 2.71828
#define LOG_CURVE_CENTER .5


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

  //    [n]  
  // [w][i][e]
  //    [s]  
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
  // adapt thresholds
  float2 thresholds = float2(MinDeltaThreshold, MaxDeltaThreshold) * adaptationFactor;

  float4 deltas = getDeltas(i, w, n, e, s);

  float maxDelta = max(max(deltas.r,deltas.g), max(deltas.b,deltas.a));

  // early return if Max delta is smaller than min threshold
  if(maxDelta < thresholds.x) discard;

  // Interpolate values between min and max threshold.
  deltas = smoothstep(thresholds.x, thresholds.y, deltas);

  // taking the root of the products of the perpendicular deltas detects corners
  //  * [n] *
  // [w]   [e]
  //  * [s] *
  float4 cornerProducts = deltas.rgba * deltas.gbar;
  //early return if none of the cornerproducts is greater than 0
  if(dot(cornerProducts,float(1.0).xxxx) == 0f) discard;
  // finally the root
  float4 cornerDeltas = sqrt(cornerProducts);

  // The smallest weight determines whether the pixel has no similar pixels nearby (aka is isolated)
  float leastCornerDelta = min(min(cornerDeltas.r,cornerDeltas.g),min(cornerDeltas.b,cornerDeltas.a));
  float isolatedPixelBlendStrength = leastCornerDelta * IsolatedPixelremoval;
  // If pixel is isolated, increase the blending amounts
  const float2 blendWeights = float2(CORNER_WEIGHT, TRANSVERSE_WEIGHT) * (1f + isolatedPixelBlendStrength);

  float4 cornerWeights = cornerDeltas * blendWeights.x;
  // sum of each corner a given pixel is involved in yields its total weight (so far)
  float4 weights = cornerWeights.xyzw + cornerWeights.wxyz;
  float weightSum = dot(weights, float(1.0).xxxx);

  // taking the root of the products of transverse deltas detects whether target pixel is not part of a larger structure
  // this is only an estimate of course
  //    [n]  
  // [w] * [e]
  //    [s]  
  float2 transWeights = sqrt(deltas.rg * deltas.ba) * blendWeights.y;
  // Scale weight of transverse weights by size of existing weights. Prevents shader from blending too aggressively
  weights += ((8 * blendWeights.x) - weightSum) * transWeights.xyxy;
  weightSum = dot(weights, float(1.0).xxxx);

  // finally, determine how much of the neighbouring pixels must be blended in, according to their weight
  float3 blendColors = n * weights.g + w * weights.r + e * weights.b + s * weights.a;

  float3 result = blendColors + (i * (1.0 - weightSum));

  // If the current pixel is brighter than the brightest adjacent "corner", highlight preservation must happen
  // THe "corner" check exists to preserve blending strength around diagonal jaggies, even when the target pixel is bright.
  float brightestCorner = sqrt(max(lw,le) * max(ln,ls));
  float excessBrightness = smoothstep(brightestCorner, 1f, li);

  // If the current pixel is very bright, apply a lower "highlight blending strength" to preserve highlights.
  // float highlightPreservationFactor = rcp(1 + pow(EULER, -HighlightCurve * (excessBrightness - LOG_CURVE_CENTER))); // Logistic function to scale brightness
  // Simpler function, achieves the same purpose but is simpler and faster.
  float highlightPreservationFactor = saturate(excessBrightness * HighlightCurve); // Logistic function to scale brightness

  //If isolatedPixelBlendStrength is high, highlightBlendStrength should be closer to normal blendingStrength
  float highlightBlendStrength = lerp(HighlightBlendingStrength, BlendingStrength, isolatedPixelBlendStrength);

  float strength = lerp(BlendingStrength, highlightBlendStrength, highlightPreservationFactor);

  return lerp(i, result, strength);
}

technique AnomalousPixelBlending {
  pass Blending
  {
    VertexShader = PostProcessVS;
    PixelShader = BlendingPS;
  }
}