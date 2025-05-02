#pragma once

#define HDR 1.05, 0, 0
#define RES float2(BUFFER_WIDTH, BUFFER_HEIGHT)
//#define iRES rcp(float2(BUFFER_WIDTH, BUFFER_HEIGHT))
#define FARPLANE RESHADE_DEPTH_LINEARIZATION_FAR_PLANE
#define ASPECT_RATIO (RES.x/RES.y)
#define IASPECT_RATIO float2(1.0, RES.x / RES.y)
#define PASPECT_RATIO float2(1.0, RES.y / RES.x)

#define WRAPMODE(WTYPE) AddressU = WTYPE; AddressV = WTYPE; AddressW = WTYPE
#define FILTER(FTYPE) MagFilter = FTYPE; MinFilter = FTYPE; MipFilter = FTYPE

#define CS_INPUTS uint3 id : SV_DispatchThreadID, uint3 tid : SV_GroupThreadID
#define DIV_RND_UP(a, b) ((int(a)+int(b)-1)/int(b))
#define DISPATCH_RES(X, Y, DIS_RES_DIV) DispatchSizeX = DIV_RND_UP(RES.x, X * DIS_RES_DIV); DispatchSizeY = DIV_RND_UP(RES.y, Y * DIS_RES_DIV)
#define DIVRES_DEP(DIVRES_RIV, DEP) Width = DIV_RND_UP(RES.x, DIVRES_RIV); Height = DIV_RND_UP(RES.y, DIVRES_RIV); Depth = DEP
#define DIVRES(DIVRES_RIV) Width = DIV_RND_UP(RES.x, DIVRES_RIV); Height = DIV_RND_UP(RES.y, DIVRES_RIV)
#define DIVRES_N(DIVRES_RIV, NRES) Width = DIV_RND_UP(NRES.x, DIVRES_RIV); Height = DIV_RND_UP(NRES.y, DIVRES_RIV)


#define PS_INPUTS float4 vpos : SV_Position, float2 xy : TEXCOORD0

//Pass helpers

#define PASS0(iPS) VertexShader = PostProcessVS; PixelShader = iPS
#define PASS1(iPS, oRT) VertexShader = PostProcessVS; PixelShader = iPS; RenderTarget = oRT
#define PASS2(iPS, oRT0, oRT1) VertexShader = PostProcessVS; PixelShader = iPS; RenderTarget0 = oRT0; RenderTarget1 = oRT1
#define PASS3(iPS, oRT0, oRT1, oRT2) VertexShader = PostProcessVS; PixelShader = iPS; RenderTarget0 = oRT0; RenderTarget1 = oRT1; RenderTarget2 = oRT2
#define PASS4(iPS, oRT0, oRT1, oRT2, oRT3) VertexShader = PostProcessVS; PixelShader = iPS; RenderTarget0 = oRT0; RenderTarget1 = oRT1; RenderTarget2 = oRT2; RenderTarget3 = oRT3


#define IGNSCROLL 5.588238

namespace zfw {
	texture2D tNormal { DIVRES(1); Format = RG16; MipLevels = 7; };
	sampler2D sNormal { Texture = tNormal; FILTER(POINT); };
	texture2D tAlbedo { DIVRES(1); Format = RGBA8; };
	sampler2D sAlbedo { Texture = tAlbedo; };
	texture2D tRoughness { DIVRES(1); Format = R8; };
	sampler2D sRoughness { Texture = tRoughness; };
	//store disocclusion in b channel
	texture2D tVelocity { DIVRES(1); Format = RGBA16F; };
	sampler2D sVelocity { Texture = tVelocity; FILTER(POINT); };
	texture2D tLowNormal { DIVRES(4); Format = RG8; MipLevels = 7; };
	sampler2D sLowNormal { Texture = tLowNormal; MagFilter = POINT; };
	texture2D tLowDepth { DIVRES(4); Format = R16; MipLevels = 7; };
	sampler2D sLowDepth { Texture = tLowDepth; };
	
	//texture2D tTest < source = "TestImage.jpg"; > { Width = 4032; Height = 3024; Format = RGBA8; };
	//sampler2D sTest { Texture = tTest; };	

}



//===================================================================================
//Projections
//===================================================================================

float GetDepth(float2 xy)
{
	return ReShade::GetLinearizedDepth(xy);
}


#define FOV (1.0 * 0.0174533 * 70.0)
#define fl rcp(tan(0.5 * FOV))

float3 GetEyePos(float2 xy, float z)
{
	float3 m = float3(fl / IASPECT_RATIO, 1.0);
	float3 xyz = float3(2*xy-1,1.0);
	return (z * FARPLANE + 1.0) * xyz*m;
}

float3 GetEyePos(float3 xyz)
{
	float3 m = float3(fl / IASPECT_RATIO, 1.0);
	float z = xyz.z;
	xyz = float3(2*xyz.xy-1,1.0);
	return (z * FARPLANE + 1.0) * xyz*m;
}

float3 NorEyePos(float2 xy)
{
	float z = GetDepth(xy);
	float3 m = float3(fl / IASPECT_RATIO, 1.0);
	float3 xyz = float3(2*xy-1,1.0);
	return (z * FARPLANE + 1.0) * xyz*m;
}

float3 GetScreenPos(float3 xyz)
{
	float3 m = float3(fl / IASPECT_RATIO, 1.0);
	xyz /= m * xyz.z;
	return 0.5 + 0.5 * xyz;
}



float3 UVtoOCT(float2 xy)
{
	
	float3 xyz = float3(2f * xy - 1f, 0.0);                

	float2 posAbs = abs(xyz.xy);
	xyz.z = 1.0 - (posAbs.x + posAbs.y);

	if(xyz.z < 0) {
        xyz.xy = sign(xyz.xy) * (1.0 - posAbs.yx);
	}
	return xyz; //already normalized
}

float2 OCTtoUV(float3 xyz) {
	float3 octsn = sign(xyz);
	
	float sd = dot(xyz, octsn);        
	float3 oct = xyz / sd;    
	
	if(oct.z < 0) {
		float3 posAbs = abs(oct);
		oct.xy = octsn.xy * (1.0 - posAbs.yx);
	}
		return 0.5 + 0.5 * oct.xy;
}

//===================================================================================
//Encoding
//===================================================================================

float2 OctWrap(float2 v)
{
    return (1.0- abs(v.yx)) * (v.xy >= 0.0 ? 1.0 : -1.0);
}
 
float2 NormalEncode(float3 n)
{
	return OCTtoUV(-n);
	//return 0.5 - 0.5 * normalize(n).xy;
}
 
float3 NormalDecode(float2 n)
{
	/*n = -2f * n + 1f;
	float z = 1.0 - length(n);
	return float3(n.xy, -z);*/
	return normalize(-UVtoOCT(n));
}

//===================================================================================
//Sampling
//===================================================================================

float3 GetNormal(float2 xy)
{
	float2 n = tex2Dlod(zfw::sNormal, float4(xy, 0, 0)).xy;
	return NormalDecode(n);	
}

float GetRoughness(float2 xy)
{
	return tex2Dlod(zfw::sRoughness, float4(xy,0,0)).x;
}

//dissoclusion in b
float3 GetVelocity(float2 xy)
{
	return tex2Dlod(zfw::sVelocity, float4(xy,0,0)).xyz;
}


float3 SampleNormal(float2 xy, float l)
{
	float2 n = tex2Dlod(zfw::sLowNormal, float4(xy, 0, l)).xy;
	return NormalDecode(n);	
}


float SampleDepth(float2 xy, float l)
{
	return tex2Dlod(zfw::sLowDepth, float4(xy, 0, l)).x;
}

float3 GetBackBuffer(float2 xy)
{
	return tex2D(ReShade::BackBuffer, xy).rgb;
	//return tex2D(Zenteon::sTest, xy).rgb;
}

float3 GetAlbedo(float2 xy)
{
	return pow(tex2D(zfw::sAlbedo, xy).rgb, 2.2);
}


//===================================================================================
//Functions
//===================================================================================

float GetLuminance( float3 x)
{
	return 0.2126 * x.r + 0.7152 * x.g + 0.0722 * x.b;
}	

float3 ReinJ(float3 x, float HDR_RED, bool bypass, bool forceLinear)
{
	if(bypass) return max( pow(x, 1.0 / (1.0 + 1.2 * forceLinear) ), 0.001);
	float l = dot(x, float3(0.2126, 0.7152,0.0722));
	x /= l + 0.0001;
	return pow(x * HDR_RED * l / (l + 1.0), rcp(2.2));
}

float3 IReinJ(float3 x, float HDR_RED, bool bypass, bool forceLinear)
{
	if(bypass) return max( pow(x, 1.0 + 1.2 * forceLinear), 0.001);
	x = pow(x, 2.2);
	
	float l = dot(x, float3(0.2126, 0.7152,0.0722));
	x /= l + 0.0001;
	return  max(x * -l / (l - HDR_RED), 0.0000001);

}

float CalcDiffuse(float3 pos0, float3 nor0, float3 pos1, float3 nor1, float backface)
{
	float diff0 = saturate(dot(nor0, normalize(pos1 - pos0)) + 0.0312);
	
	//Option for backface lighting, looks bad
	float diff1 = saturate(dot(nor1, normalize(pos0 - pos1)) + 0.0312);
	return diff0 * diff1;//pow(diff1, 1.0);
}

float CalcTransfer(float3 pos0, float3 nor0, float3 pos1, float3 nor1, float disDiv, float att, float backface)
{
	float lumMult = dot(pos1, pos1) + 0.001;//length(pos1) / (1.0 + disDiv) + 1.0; lumMult *= lumMult;
	float dist = rcp(att + dot(pos1-pos0,pos1-pos0));//distance(pos0, pos1) / (1.0 + disDiv) + 1.0; dist = rcp(dist*dist);
	float lamb = CalcDiffuse(pos0, nor0, pos1, nor1, backface);
	return max(lamb * lumMult * dist, 0.000);
}	


float CalcSpecular(float3 pos0, float3 refl0, float3 pos1, float3 nor1, float disDiv, float att, float power)
{
	float diff0 = pow(saturate(dot(refl0, normalize(pos1 - pos0)) - 0.1), power);
	float diff1 = saturate((dot(nor1, normalize(pos0 - pos1)) - 0.1));
	
	float lumMult = pow(length(pos1) / (1.0 + disDiv) , 2.0);
	float eyeMult = rcp( pow(length(pos0) / (1.0 + disDiv) , 2.0 ));
	float dist = rcp( pow(att + distance(pos0, pos1) / disDiv, 2.0) );
	float trns = diff0 * diff1;
	return max(power * trns * eyeMult * lumMult * dist, 0.00);
}

float CalcSSS(float thk, float3 viewV, float3 surfN, float3 lightV)
{
	#define DISTORT  1.0
	#define POWER	1.0
	#define SCALE	1.0
	#define AMBIENT  0.2
	
	float3 thvLum = lightV + surfN * DISTORT;
	float  thkDot = pow( saturate(dot(viewV, - thvLum)), POWER) * SCALE;
	float sss = (thkDot + AMBIENT) * thk;
	return sss;
}

