#include "ReShadeUI.fxh"
#include "ReShade.fxh"

#define UI_MORPHOLOGICAL_AA_LIST "FXAA/CMAA/SMAA"
#define UI_TEMPORAL_AA_LIST "TAA/Upscaling"

uniform bool _SkipBackground <
  ui_label = "Skip background";
  ui_type = "radio";
  ui_tooltip = 
    "Stops blending on the background/skybox.\n"
    "Prevents erasure of stars, but may impede\n"
    "the blending of the borders of objects\n"
    "in front of the background.";
> = false;

uniform float _LowerThreshold <
  ui_label = "Lower threshold";
  ui_type = "slider";
  ui_min = 0.002; ui_max = 1.0; ui_step = 0.01;
  ui_tooltip = 
    "The minimum delta at which the shader activates.\n"
    "Must be less or equal than the upper threshold.\n"
    "Recommended values:\n"
    " - No AA (standalone): 0.15 - 0.23\n"
    " - " UI_MORPHOLOGICAL_AA_LIST ": 0.15 - 0.25\n"
    " - " UI_TEMPORAL_AA_LIST ": 0.2 - 0.45";
> = 0.2;

uniform float _UpperThreshold <
  ui_label = "Upper threshold";
  ui_type = "slider";
  ui_min = 0.002; ui_max = 1.0; ui_step = 0.01;
  ui_tooltip = 
    "The delta at which the shader reaches full strength.\n"
    "Must be greater or equal than the lower threshold.\n"
    "Recommended values:\n"
    " - No AA (standalone): 0.3 - 0.45\n"
    " - " UI_MORPHOLOGICAL_AA_LIST ": 0.3 - 0.5\n"
    " - " UI_TEMPORAL_AA_LIST ": 0.4 - 0.6";
> = 0.45;

uniform float _LumaAdaptationRange <
  ui_label = "Luma adaptation range";
  ui_type = "slider";
  ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
  ui_tooltip = 
    "Lowers the tresholds in darker spots. This compensates\n"
    "for the fact that darker spots can't have as big of a\n"
    "delta as brighter spots.\n"
    "Recommended values: 0.8 - 0.95";
> = 0.85;

uniform float _TransverseBlendingWeight <
  ui_label = "Transverse blending";
  ui_type = "slider";
  ui_min = 0.0; ui_max = 0.5; ui_step = 0.01;
  ui_tooltip = 
    "Blends pixels which are straddled by differently colored pixels.\n"
    "Helps to make thin, aliased lines less noticeable.\n"
    "Recommended values: 0.1 - 0.35";
> = 0.25;

uniform float _IsolatedPixelremoval <
  ui_label = "Isolated pixel removal";
  ui_type = "slider";
  ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
  ui_tooltip = 
    "Extra blending for pixels which have no similar\n"
    "pixels above, below, left or right.\n"
    "May eat stars if 'Skip Background' isn't enabled.\n"
    "Recommended values: 0.25 - 0.75";
> = 0.55;

uniform float _HighlightPreservationStrength <
  ui_label = "Highlight preservation";
  ui_type = "slider";
  ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
  ui_tooltip = 
    "Helps to preserve highlights and bright details.\n"
    "Higher values may reduce the shader's effect.\n"
    "Try raising this value if you notice a loss of detail.\n"
    "Recommended values: 0.6 - 1.0";
> = 0.80;

uniform float _BlendingStrength <
  ui_label = "Blending strength";
  ui_type = "slider";
  ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
  ui_tooltip = 
    "The degree in which the processed result is\n"
    "applied to the scene.";
> = 1.0;


uniform int _Help <
  ui_type = "radio"; ui_label = " ";
  ui_text = 
    "Transverse blending blends pixels which are straddled by\n"
    "differently colored pixels. Set `NO_TRANSVERSE_BLENDING`\n"
    "to `1` to disable it entirely.\n"
    "\n"
    "`MAX_HIGHLIGHT_CURVE` determines how much brighter a pixel\n"
    "must be than it's surroundings before highlight preservation\n"
    "kicks in fully. Higher values mean lower brightness differences\n"
    "are preserved more aggressively.\n"
    "\n"
    "Transverse blending strength is boosted for dark lines\n"
    "`MAX_DARK_LINE_BOOST` is a multiplier which represents the\n"
    "maximum blending boost for dark lines.\n"
    "`DARK_LINE_CURVE` determines how dark a pixel must be to be\n"
    "boosted. The higher this value, the darker a pixel must be."
    ;
>;

#ifndef NO_TRANSVERSE_BLENDING
  #define NO_TRANSVERSE_BLENDING 0
#endif

// #ifndef CORNER_WEIGHT
  #define CORNER_WEIGHT 0.0625 // 1/16
// #endif

// If fewer corners than this are detected, corner blending is skipped
#ifndef MIN_CORNER_COUNT_FOR_CORNER_BLENDING
  #define MIN_CORNER_COUNT_FOR_CORNER_BLENDING 1f
#endif

#define TRANSVERSE_WEIGHT_ _TransverseBlendingWeight

#ifndef MAX_HIGHLIGHT_CURVE
  #define MAX_HIGHLIGHT_CURVE 10.0
#endif

#ifndef MAX_DARK_LINE_BOOST
  #define MAX_DARK_LINE_BOOST 2.5
#endif

#ifndef DARK_LINE_CURVE
  #define DARK_LINE_CURVE 5.0
#endif

#define MAX_DARK_LINE_BOOST_REDUCTION (MAX_DARK_LINE_BOOST - 1f)
#define LUMA_WEIGHTS float3(0.26, 0.6, 0.14)
#define BACKGROUND_DEPTH 1.0


float getLuma(float3 rgb)
{
  return dot(rgb, LUMA_WEIGHTS);
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
  float adaptationFactor = mad(-_LumaAdaptationRange, 1.0 - brightness, 1.0);
  // adapt thresholds
  return float2(_LowerThreshold, _UpperThreshold) * adaptationFactor;
}

void SetCornerWeights(float4 deltas, float2 blendWeights, inout float4 weights, inout float weightSum){
  float4 cornerWeights = deltas * blendWeights.x;
  // sum of each corner a given pixel is involved in yields its total weight (so far)
  weights = cornerWeights.xyzw + cornerWeights.wxyz;
  weightSum = dot(weights, float(1f).xxxx);
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
  float leastCornerDelta = min(min(cornerDeltas.r,cornerDeltas.g), min(cornerDeltas.b,cornerDeltas.a));
  return leastCornerDelta * _IsolatedPixelremoval;
}

float3 BlendingPS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_TARGET {
  // Skip if pixel is part of background. May prevent stars from being eaten
  if (_SkipBackground) {
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

  float isolatedPixelBlendStrength = GetIsolatedPixelBlendStrength(cornerDeltas);
  // band-aid fix for the fact that dark lines dont receive as much blending as they should // TODO: find comprehensive solution
  float darkLineBlendBoostFactor = mad(saturate(currentL * DARK_LINE_CURVE), -MAX_DARK_LINE_BOOST_REDUCTION, MAX_DARK_LINE_BOOST);
  // If pixel is isolated, increase the blending amounts
  const float2 blendWeights = float2(CORNER_WEIGHT, TRANSVERSE_WEIGHT_ * darkLineBlendBoostFactor) * (1f + isolatedPixelBlendStrength);

  float4 weights;
  float weightSum;

  #if MIN_CORNER_COUNT_FOR_CORNER_BLENDING > 1f
  
    // Each cornerDelta > 0f becomes 1f, the rest stays 0f
    float4 cornerFlags = step(0f, cornerDeltas);
    float cornerCount = dot(cornerFlags, float(0f).xxxx);

    if (cornerCount >= MIN_CORNER_COUNT_FOR_CORNER_BLENDING) {
      SetCornerWeights(cornerDeltas, blendWeights, weights, weightSum);
    }

  #else
    SetCornerWeights(cornerDeltas, blendWeights, weights, weightSum);
  #endif

  #if NO_TRANSVERSE_BLENDING == 0
    SetTransverseWeights(deltas, blendWeights, weights, weightSum);
  #endif

  // finally, determine how much of the neighbouring pixels must be blended in, according to their weight
  float3 blendColors = north * weights.g + west * weights.r + east * weights.b + south * weights.a;

  float3 result = blendColors + (current * (1.0 - weightSum));

  // If the current pixel is brighter than the brightest adjacent "corner", highlight preservation must happen
  // This corner check exists to preserve blending strength around diagonal jaggies, even when the target pixel is bright.
  float brightestCorner = sqrt(max(westL, eastL) * max(northL, southL));
  float excessBrightness = smoothstep(brightestCorner, 1f, currentL);

  // apply modifier to excessBrightness to have lower excess brightnesses count more
  // Simplified version of an older logistic function, hence the "curve" var
  float highlightCurve = MAX_HIGHLIGHT_CURVE * _HighlightPreservationStrength; // mod strength scales with preservation strength
  float highlightPreservationFactor = saturate(excessBrightness * highlightCurve); 

  // calculate final belnding strength by calculating strength of highlightpreservation and subtracting it
  // If isolatedPixelBlendStrength is high, less highlight preservation is used
  float strength = _BlendingStrength - (_HighlightPreservationStrength * highlightPreservationFactor * (1f - isolatedPixelBlendStrength));

  return lerp(current, result, strength);
}

technique AnomalousPixelBlending {
  pass Blending
  {
    VertexShader = PostProcessVS;
    PixelShader = BlendingPS;
  }
}