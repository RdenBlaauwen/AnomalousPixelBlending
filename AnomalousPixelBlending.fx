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
#define BUFFER_METRICS float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT)

float getDelta(float3 colA, float3 colB) 
{
  return dot(abs(colA - colB), SPB_LUMA_WEIGHTS);
}

void VS(
	in uint id : SV_VertexID,
	out float4 position : SV_Position,
	out float2 texcoord : TEXCOORD0,
	out float4 offset[2] : TEXCOORD1)
{
	PostProcessVS(id, position, texcoord);
  offset[0] = mad(BUFFER_METRICS.xyxy, float4(-1.0, 0.0, 0.0, 1.0), texcoord.xyxy);
  offset[1] = mad(BUFFER_METRICS.xyxy, float4( 0.0, -1.0, 0.0,  1.0), texcoord.xyxy);
}

float3 PS(float2 texcoord : TEXCOORD, float4 offset[2] : TEXCOORD1) : SV_TARGET {
  //  x [n] y
  // [w][i][e]
  //  w [s] z
  float3 n,w,e,s,i;
  i = tex2D(ReShade::BackBuffer, texcoord).rgb;
  n = tex2D(ReShade::BackBuffer, offset[1].xy).rgb; // N
  w = tex2D(ReShade::BackBuffer, offset[0].xy).rgb; // W
  e = tex2D(ReShade::BackBuffer, offset[0].wz).rgb; // E
  s = tex2D(ReShade::BackBuffer, offset[1].wz).rgb; // S

  float4 deltas;
  deltas.r = getDelta(i, w);
  deltas.g = getDelta(i, n);
  deltas.b = getDelta(i, e);
  deltas.a = getDelta(i, s);

  float maxDelta = max(max(deltas.r,deltas.g), max(deltas.b,deltas.a));
  if(maxDelta < MinDeltaThreshold) discard;

  float4 cornerWeights = sqrt(deltas.rgba * deltas.gbar);
  cornerWeights = smoothstep(MinDeltaThreshold, MaxDeltaThreshold, cornerWeights) * MAX_CORNER_WEIGHT;
  float4 weights = cornerWeights.xyzw + cornerWeights.wxyz;

  float3 blendColors = n * weights.g + w * weights.r + e * weights.b + s * weights.a;

  float weightSum = dot(weights, float(1.0).xxxx);
  float gap = (MAX_CORNER_WEIGHT * 8.0) - weightSum;

  float2 transDeltas;
  transDeltas.x = getDelta(w,e);
  transDeltas.y = getDelta(n,s);
  
  float2 transWeights = smoothstep(MinDeltaThreshold, MaxDeltaThreshold, transDeltas) * MAX_TRANSVERSE_WEIGHT * gap;

  blendColors += transWeights.x * w + transWeights.x * e + transWeights.y * n + transWeights.y * s;
  float transWeightSum = dot(transWeights, float(1.0).xx);

  float3 result = blendColors + i * (1 - transWeightSum - weightSum);

  return lerp(i, result, MaxBlendingStrength);
}

technique AnomalousPixelBlending {
  pass
  {
    VertexShader = VS;
    PixelShader = PS;
  }
}