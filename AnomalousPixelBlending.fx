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

uniform float BlendingStrength <
  ui_label = "BlendingStrength";
  ui_type = "slider";
  ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 1.0;

uniform float HighlightPreservationStrength <
  ui_label = "HighlightPreservation";
  ui_type = "slider";
  ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 1.0;

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
#ifndef MAX_HIGHLIGHT_CURVE
  #define MAX_HIGHLIGHT_CURVE 10.0
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

float4 getDeltas(float3 target, float3 west, float3 north, float3 east, float3 south)
{
  float4 deltas;
  deltas.r = getDelta(target, west);
  deltas.g = getDelta(target, north);
  deltas.b = getDelta(target, east);
  deltas.a = getDelta(target, south);

  return deltas;
}

float2 getAdaptedThresholds(float brightness) {
  // Get factor by which thresholds should be adapted/predicated. Lower max luma --> lower factor --> lower thresholds
  float adaptationFactor = mad(-LumaAdaptationRange, 1.0 - brightness, 1.0);
  // adapt thresholds
  return float2(MinDeltaThreshold, MaxDeltaThreshold) * adaptationFactor;
}

void SetCornerWeights(float4 deltas, float2 blendWeights, inout float4 weights, inout float weightSum){
  float4 cornerWeights = deltas * blendWeights.x;
  // sum of each corner a given pixel is involved in yields its total weight (so far)
  weights = cornerWeights.xyzw + cornerWeights.wxyz;
  weightSum = dot(weights, float(1.0).xxxx);
}

void SetTransverseWeights(float4 deltas, float2 blendWeights, inout float4 weights, inout float weightSum){
  const float MAX_NEIGHBOUR_INFLUENCE = 8f;
  // taking the least transverse delta (that is, the lowest delta on the vertical and horizontal planes respectively) represents transverse weight
  // If these values are high it means the pixel is likely part of a structure of no more than 1 pixel wide,
  // making it a target for blending
  // this is only an estimate of course
  //      [g(n)]  
  // [r(w)]    [a(e)]
  //      [b(s)]  
  float2 transWeights = min(deltas.rg, deltas.ba) * blendWeights.y;
  // Scale weight of transverse weights by size of existing weights. Prevents shader from blending too aggressively
  float maxWeightSum = MAX_NEIGHBOUR_INFLUENCE * blendWeights.x;
  weights += (maxWeightSum - weightSum) * transWeights.xyxy;
  weightSum = dot(weights, float(1.0).xxxx);
}

float GetIsolatedPixelBlendStrength(float4 cornerDeltas){
  // The smallest weight determines whether the pixel has no similar pixels nearby (aka is isolated)
  float leastCornerDelta = min(min(cornerDeltas.r,cornerDeltas.g),min(cornerDeltas.b,cornerDeltas.a));
  return leastCornerDelta * IsolatedPixelremoval;
}

float3 BlendingPS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_TARGET {
  // Skip if pixel is part of background. May prevent stars from being eaten
  if (SkipBackground) {
    float currDepth = ReShade::GetLinearizedDepth(texcoord);
    if (currDepth == BACKGROUND_DEPTH) discard;
  }

  //    [n]  
  // [w][c][e]
  //    [s]  
  float3 north, west, east, south, current;
  current = tex2D(ReShade::BackBuffer, texcoord).rgb;
  north = tex2Doffset(ReShade::BackBuffer, texcoord, int2(0.0, -1.0)).rgb; // N
  west = tex2Doffset(ReShade::BackBuffer, texcoord, int2(-1.0, 0.0)).rgb; // W
  east = tex2Doffset(ReShade::BackBuffer, texcoord, int2(1.0, 0.0)).rgb; // E
  south = tex2Doffset(ReShade::BackBuffer, texcoord, int2(0.0, 1.0)).rgb; // S

  // Get luminance of each pixel
  float northL,westL,eastL,southL,currentL;
  currentL = getLuma(current);
  northL = getLuma(north);
  westL = getLuma(west);
  eastL = getLuma(east);
  southL = getLuma(south);

  // Get largest luma
  float maxLuma = max(max(max(currentL, northL), max(westL, eastL)), southL);
  // use it to decrease threshold accordingly
  float2 thresholds = getAdaptedThresholds(maxLuma);

  float4 deltas = getDeltas(current, west, north, east, south);

  float maxDelta = max(max(deltas.r,deltas.g), max(deltas.b,deltas.a));

  // early return if Max delta is smaller than min threshold
  if(maxDelta < thresholds.x) discard;

  // Interpolate values between min and max threshold.
  deltas = smoothstep(thresholds.x, thresholds.y, deltas);

  // The smallest delta of each corner is used to represent the delta of that corner as a whole
  float4 cornerDeltas = min(deltas.rgba, deltas.gbar);
  //early return if none of the cornerproducts is greater than 0
  if(dot(cornerDeltas,float(1.0).xxxx) == 0f) discard;
  // finally the root

  float isolatedPixelBlendStrength = GetIsolatedPixelBlendStrength(cornerDeltas);
  // If pixel is isolated, increase the blending amounts
  const float2 blendWeights = float2(CORNER_WEIGHT, TRANSVERSE_WEIGHT) * (1f + isolatedPixelBlendStrength);

  float4 weights;
  float weightSum;
  SetCornerWeights(deltas, blendWeights, weights, weightSum);
  SetTransverseWeights(deltas, blendWeights, weights, weightSum);

  // finally, determine how much of the neighbouring pixels must be blended in, according to their weight
  float3 blendColors = north * weights.g + west * weights.r + east * weights.b + south * weights.a;

  float3 result = blendColors + (current * (1.0 - weightSum));

  // If the current pixel is brighter than the brightest adjacent "corner", highlight preservation must happen
  // This corner check exists to preserve blending strength around diagonal jaggies, even when the target pixel is bright.
  float brightestCorner = sqrt(max(westL, eastL) * max(northL, southL));
  float excessBrightness = smoothstep(brightestCorner, 1f, currentL);

  // apply modifier to excessBrightness to have lower excess brightnesses count more
  // Simplified version of an older logistic function, hence the "curve" var
  float highlightCurve = MAX_HIGHLIGHT_CURVE * HighlightPreservationStrength; // mod strength scales with preservation strength
  float highlightPreservationFactor = saturate(excessBrightness * highlightCurve); 

  // calculate final belnding strength by calculating strength of highlightpreservation and subtracting it
  // If isolatedPixelBlendStrength is high, less highlight preservation is used
  float strength = BlendingStrength - (HighlightPreservationStrength * highlightPreservationFactor * (1f - isolatedPixelBlendStrength));

  return lerp(current, result, strength);
}

technique AnomalousPixelBlending {
  pass Blending
  {
    VertexShader = PostProcessVS;
    PixelShader = BlendingPS;
  }
}