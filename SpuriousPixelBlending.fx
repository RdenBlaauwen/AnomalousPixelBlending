#include "ReShadeUI.fxh"
#include "ReShade.fxh"

uniform float MinDeltaThreshold <
  ui_label = "MinDeltaThreshold";
  ui_min = 0.01; ui_max = 0.5; ui_step = 0.001;
> = 0.05;

uniform float MaxDeltaThreshold <
  ui_label = "MaxDeltaThreshold";
  ui_min = 0.05; ui_max = 1.0; ui_step = 0.001;
> = 0.2;

uniform float MaxBlendingStrength <
  ui_label = "MaxBlendingStrength";
  ui_min = 0.; ui_max = 1.0; ui_step = 0.01;
> = 1.0;

#define SPB_LUMA_WEIGHTS float3(0.26, 0.6, 0.14)
#define MAX_CORNER_WEIGHT (1/16)
#define MAX_TRANSVERSE_WEIGHT (1/8)

float getDelta(float3 colA, float3 colB) 
{
  return dot(abs(colA - colB), SPB_LUMA_WEIGHTS);
}

float3 PS(float2 texcoord : TEXCOORD, float4 offset[1]) : SV_TARGET {
  //  x [n] y
  // [w][i][e]
  //  w [s] z
  float3 n,w,e,s,i;
  i = tex2D(ReShade::BackBuffer, texcoord).rgb;
  n = tex2D(ReShade::BackBuffer, offset[1].xy).rgb; // N
  w = tex2D(ReShade::BackBuffer, offset[0].xy).rgb; // W
  e = tex2D(ReShade::BackBuffer, offset[1].wz).rgb; // E
  s = tex2D(ReShade::BackBuffer, offset[0].wz).rgb; // S

  float4 deltas;
  deltas.r = getDelta(i, w);
  deltas.g = getDelta(i, n);
  deltas.b = getDelta(i, e);
  deltas.a = getDelta(i, s);

  float maxDelta = max(max(r,g), max(b,a));
  if(maxDelta < MinDeltaThreshold) discard;

  float4 cornerWeights = sqrt(deltas.rgba * deltas.gbar);
  cornerWeights = smoothstep(MinDeltaThreshold, MaxDeltaThreshold, cornerWeights) * MAX_CORNER_WEIGHT;
  float4 weights = cornerWeights.xyzw + cornerWeights.wxyz;

  float3 blendColors = n * weights.g + w * weights.r + e * weights.b + s * weights.d;

  float weightSum = dot(weights, float(1.0).xxxx);
  float gap = (MAX_CORNER_WEIGHT * 8.0) - weightSum;

  float2 transDeltas;
  transDeltas.x = getDelta(b,c);
  transDeltas.y = getDelta(a,d);
  
  float2 transWeights = smoothstep(MinDeltaThreshold, MaxDeltaThreshold, transDeltas) * MAX_TRANSVERSE_WEIGHT * gap;

  blendColors += transWeights.x * w + transWeights.x * e + transWeights.y * n + transWeights.y * s;
  float transWeightSum = dot(transWeights, float(1.0).xx);

  float3 result = blendColors + i * (1 - transWeightSum - weightSum);

  return lerp(i, result, MaxBlendingStrength);
}

technique SpuriousPixelBlending {
  pass
  {
    VertexShader = PostProcessVS;
    PixelShader = PS;
  }
}