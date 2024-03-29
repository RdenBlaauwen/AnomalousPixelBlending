#include "ReShadeUI.fxh"
#include "ReShade.fxh"

uniform float MinDeltaThreshold <
  ui_label = "MinDeltaThreshold";
  ui_type = "slider";
  ui_min = 0.0; ui_max = 1.0; ui_step = 0.001;
> = 0.05;

uniform float MaxDeltaThreshold <
  ui_label = "MaxDeltaThreshold";
  ui_type = "slider";
  ui_min = 0.0; ui_max = 1.0; ui_step = 0.001;
> = 0.15;

uniform float MaxBlendingStrength <
  ui_label = "MaxBlendingStrength";
  ui_type = "slider";
  ui_min = 0.; ui_max = 1.0; ui_step = 0.01;
> = 1.0;

#define SPB_LUMA_WEIGHTS float3(0.26, 0.6, 0.14)
#ifndef MAX_CORNER_WEIGHT
  #define MAX_CORNER_WEIGHT 0.0625
#endif
#ifndef MAX_TRANSVERSE_WEIGHT
  #define MAX_TRANSVERSE_WEIGHT 0.125
#endif
#define BUFFER_METRICS float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT)

float getDelta(float3 colA, float3 colB) 
{
  return dot(abs(colA - colB), SPB_LUMA_WEIGHTS);
}

void MyVS(
	in uint id : SV_VertexID,
	out float4 position : SV_Position,
	out float2 texcoord : TEXCOORD0,
	out float4 offset[2] : TEXCOORD1)
{
	PostProcessVS(id, position, texcoord);
  offset[0] = mad(BUFFER_METRICS.xyxy, float4(-1.0, 0.0, 0.0, 1.0), texcoord.xyxy);
  offset[1] = mad(BUFFER_METRICS.xyxy, float4( 0.0, -1.0, 0.0, 0.0), texcoord.xyxy);
}

float3 MyPS(float4 position : SV_Position, float2 texcoord : TEXCOORD, float4 offset[2] : TEXCOORD1) : SV_TARGET {
  //  x [n] y
  // [w][i][e]
  //  w [s] z
  float3 n,w,e,s,i;
  // i = tex2D(ReShade::BackBuffer, texcoord).rgb;
  // n = tex2D(ReShade::BackBuffer, offset[1].xy).rgb; // N
  // w = tex2D(ReShade::BackBuffer, offset[0].xy).rgb; // W
  // e = tex2D(ReShade::BackBuffer, offset[0].zw).rgb; // E
  // s = tex2D(ReShade::BackBuffer, offset[1].zw).rgb; // S

    i = tex2D(ReShade::BackBuffer, texcoord).rgb;
  n = tex2Doffset(ReShade::BackBuffer, texcoord, int2(0.0, -1.0)).rgb; // N
  w = tex2Doffset(ReShade::BackBuffer, texcoord, int2(-1.0, 0.0)).rgb; // W
  e = tex2Doffset(ReShade::BackBuffer, texcoord, int2(1.0, 0.0)).rgb; // E
  s = tex2Doffset(ReShade::BackBuffer, texcoord, int2(0.0, 1.0)).rgb; // S

  float4 deltas;
  deltas.r = getDelta(i, w);
  deltas.g = getDelta(i, n);
  deltas.b = getDelta(i, e);
  deltas.a = getDelta(i, s);

  float maxDelta = max(max(deltas.r,deltas.g), max(deltas.b,deltas.a));
  if(maxDelta < MinDeltaThreshold) discard;

  deltas = smoothstep(MinDeltaThreshold, MaxDeltaThreshold, deltas);

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
    VertexShader = MyVS;
    PixelShader = MyPS;
  }
}