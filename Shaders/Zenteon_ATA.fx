//========================================================================
/*
	Copyright © Daniel Oren-Ibarra - 2025
	All Rights Reserved.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND
	EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
	MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
	IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
	CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
	TORT OR OTHERWISE,ARISING FROM, OUT OF OR IN CONNECTION WITH THE
	SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
	
	
	======================================================================	
	Zenteon: ATA v0.3 - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/

#include "ReShade.fxh"
#include "ZenteonCommon.fxh"

#ifndef USE_FRAMEWORK_MOTION
//============================================================================================
	#define USE_FRAMEWORK_MOTION 0
//============================================================================================
#endif

//Slower, less blur
#ifndef ACCUMULATION_QUALITY
//============================================================================================
	#define ACCUMULATION_QUALITY 0
//============================================================================================
#endif

#define RESD (ACCUMULATION_QUALITY + 1)

uniform bool KILLSWITCH <
	hidden = 1;
> = 0;

uniform bool DO_NEIGHBORHOOD <
	hidden = 1;
> = 1;


uniform int ACC_MODE <
	ui_type = "combo";
	ui_label = "Accumulation Mode";
	ui_items = "Naive\0Adaptive\0NonLocal\0";
	ui_tooltip = "NOTE: While other motion vector shaders will work, Zenteon Motion is highly recommended, as others will likely cause blurring\n"
				"Naive Reprojection is the blurriest, not recommended unless a game has untameable specular aliasing or flicker\n"
				"Adaptive detects flicker and removes it dynamically to prevent blur\n"
				"NonLocal uses a small best match nonlocal means filter to completely remove blur, but can't remove spatial aliasing\n"
				"NOTE: NonLocal only works on ACCUMULATION_QUALITY 0";
	ui_min = 0;
	ui_max = 2;
	//hidden = 1;
> = 1;

uniform float FILTER_STRENGTH <
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "Filter Strength";
	ui_tooltip = "Non Local Filter Strength \nHigher values will give a more stable but less detailed image, can introduce aliasing";
	ui_type = "slider";
> = 0.0;

uniform int WEIGHT_MODE <
	ui_type = "combo";
	ui_items = "SSD\0Exp (configurable weight)\0";
	ui_label = "Weight Type";
	hidden = true;
> = 1;
#define NLM_WEIGHT_COEFF ( 5000.0 * (1.0 - 0.95 * FILTER_STRENGTH) * (1.0 - 0.95 * FILTER_STRENGTH) )

uniform float TAA_LERP_VALUE <
	ui_min = 0.7;
	ui_max = 0.95;
	ui_label = "Accumulation value";
	ui_tooltip = "How much of the previous frames are blended, higher values will give a more stable but less responsive image";
	ui_type = "slider";
> = 0.85;


texture2D texMotionVectors { DIVRES(1); Format = RG16F; };
sampler2D sMV { Texture = texMotionVectors; };

texture2D tDOC { DIVRES(1); Format = R8; };
sampler2D sDOC { Texture = tDOC; };

namespace ZenATA {
	
	//=======================================================================================
	//Textures/Samplers
	//=======================================================================================
	
	texture2D tCur { DIVRES_N(1, RESD*RES); Format = RGBA16; };
	sampler2D sCur { Texture = tCur; };
	
	texture2D tPre { DIVRES_N(1, RESD*RES); Format = RGBA16; };
	sampler2D sPre { Texture = tPre; };
	
	//=======================================================================================
	//Functions
	//=======================================================================================
	
	float fastExpN(float x)
	{
		return rcp( x + (x*x + 1.0)) + 1e-19;
	}
	
	void GetPatch( sampler2D tex, float2 pos, inout float3 Patch[9] )
	{
		for(int i = 0; i < 9; i++)
		{
			float2 ni = pos + (float2( floor(i / 3.0), i % 3 ) - 1.0);
			float3 t = tex2Dfetch(tex, pos).rgb;//slightly better results in gamma
			Patch[i] = t;
		}
	}
	
	float WeightPatch( float3 P0[9], float3 P1[9], float wm)
	{
		float err;
		for(int i = 0; i < 9; i++)
		{
			float3 ti = P0[i] - P1[i];
			err += dot(ti, ti) / dot(1.0, P0[i] + P1[i] + 0.001);
		}
		if(WEIGHT_MODE == 0) return rcp(wm * err + 1e-18); //  I like this better, but less configurable
		return fastExpN( 0.1111111 * wm * err);
		//TODO replace with explicit optimization of the minimum
	}
	
	float PatchLoss( float3 P0[9], float3 P1[9])
	{
		float err;
		for(int i = 0; i < 9; i++)
		{
			float3 ti = P0[i] - P1[i];
			
			err += dot(ti, ti);
		}
		return err / 9.0;
	}
	
	
	float Lanczos(float x)
	{
		float p = 3.14159*abs(x);
		return (sin(p)/p) * (sin(0.25*p)/(0.25*p));
	}
	
	float4 tex2DLanczos(sampler2D tex, float2 xy)
	{
		float2 pos = tex2Dsize(tex) * xy;
		float4 I = float4(tex2Dfetch(tex, pos).rgb, 1.0);
		
		float4 acc;
		for(int i = -2; i < 2; i++) for(int j = -2; j < 2; j++)
		{
			float2 np = pos + (float2(i,j)+0.5);
			float ld = length( 2.6 * (float2(i,j)+0.5) );
			float3 s = tex2Dfetch(tex, np).rgb;
			
			acc += Lanczos(ld) * float4(pow(s,2.2), 1.0);
		}
		return float4( pow(acc.rgb / acc.w, rcp(2.2) ), 1.0 );
	}	
	
	//=======================================================================================
	//Passes
	//=======================================================================================

	
	float4 CurPS(PS_INPUTS) : SV_Target
	{	
	#if(USE_FRAMEWORK_MOTION)
		float2 MVi = RES * GetVelocity(xy).xy;
	#else
		float2 MVi = RES * tex2D(sMV, xy).xy;
	#endif
		float4 acn;
		
		[branch]
		if(ACC_MODE == 2)
		{
			float3 CP[9], OP[9];
			float4 S[9];
			
			GetPatch(ReShade::BackBuffer, vpos.xy, CP);
			float4 acc;
			for(int i = 0; i < 9; i++)
			{
				float2 ni = MVi + vpos.xy + (float2( floor(i / 3.0), i % 3 ) - 1.0);
				GetPatch(sPre, ni, OP);
				float w = WeightPatch( CP, OP, NLM_WEIGHT_COEFF);
				acc += float4(OP[4], 1.0) * w;
				S[i] = float4(OP[4], 1.0) * w;
			}
			
			float3 wm = 0.0; //offset, current weight
			float t;
			/*
				6 7 8
				3 4 5
				0 1 2
			*/
			
			t = S[1].w+S[2].w+S[4].w+S[5].w;
			wm = t > wm.z ? float3( 0, 1, t) : wm;
			t = S[4].w+S[5].w+S[7].w+S[8].w;
			wm = t > wm.z ? float3( 0, 0, t) : wm;	
			t = S[0].w+S[1].w+S[3].w+S[4].w;
			wm = t > wm.z ? float3(-1, 1, t) : wm;	
			t = S[3].w+S[4].w+S[6].w+S[7].w;
			wm = t > wm.z ? float3(-1, 0, t) : wm;
			
			
			acn = all( abs(wm.xy - float2( 0, 1)) < 0.001 ) ? S[1]+S[2]+S[4]+S[5] : acn;
			acn = all( abs(wm.xy - float2( 0, 0)) < 0.001 ) ? S[4]+S[5]+S[7]+S[8] : acn;
			acn = all( abs(wm.xy - float2(-1, 1)) < 0.001 ) ? S[0]+S[1]+S[3]+S[4] : acn;
			acn = all( abs(wm.xy - float2(-1, 0)) < 0.001 ) ? S[3]+S[4]+S[6]+S[7] : acn;
			
		}
		[branch]
		switch(ACC_MODE) {
			case 0: return tex2D(sPre, xy + MVi/RES);
			case 1: return tex2D(sPre, xy + MVi/RES);//float4(acc.rgb / acc.w, 1.0);
			case 2: return float4(acn.rgb / acn.w, 1.0);
		}
		return 0;
	}
	
	float4 PrePS(PS_INPUTS) : SV_Target
	{	 
		float4 pre = tex2D(sCur, xy);
		
		float4 cur = float4(GetBackBuffer(xy), 1.0);
		cur.a = dot(cur.rgb*cur.rgb, float3(0.2126,0.7152,0.0722));
		
		float3 MV;
		
		#if(USE_FRAMEWORK_MOTION)
			MV = GetVelocity(xy).xy;
		#else
			MV.xy = tex2D(sMV, xy).xy;
			MV.z = tex2D(sDOC, xy).x;
		#endif
		//MV.z = 1.0;
		
		float2 txy = xy + MV.xy;
		float2 range = saturate(txy * txy - txy);
		MV.z *= range.x == -range.y;
		
		float3 minC = 1.0, maxC = 0.0;
		
		for(int i = 0; i < 9; i++)
		{
			float2 ni = vpos.xy + (float2( floor(i / 3.0), i % 3 ) - 1.0) * RESD;
			float3 t = tex2Dfetch(ReShade::BackBuffer, ni/RESD).rgb;
			minC = min(minC, t);
			maxC = max(maxC, t);
		}
		if(DO_NEIGHBORHOOD) pre.rgb = clamp(pre.rgb, minC, maxC);
		
		return lerp(cur, pre, MV.z * TAA_LERP_VALUE);
	}
	
	//=======================================================================================
	//Blending
	//=======================================================================================
	
	float3 BlendPS(PS_INPUTS) : SV_Target
	{
		float3 c = GetBackBuffer(xy);
		if(KILLSWITCH) return c;
		
		float2 hp = 0.5 * rcp(RES);
		
		float4 p = tex2D(sPre, xy).rgba;
		
		float3 pA = tex2D(sPre,xy + hp*float2( 1, 1)).rgb;
		float3 pB = tex2D(sPre,xy + hp*float2( 1,-1)).rgb;
		float3 pC = tex2D(sPre,xy + hp*float2(-1, 1)).rgb;
		float3 pD = tex2D(sPre,xy + hp*float2(-1,-1)).rgb;
		
		float lap = dot(p.rgb - 0.25*(pA+pB+pC+pD), float3(0.299,0.587,0.114));
		
		float3 A = GetBackBuffer(xy + hp*float2( 1, 1));
		float3 B = GetBackBuffer(xy + hp*float2( 1,-1));
		float3 C = GetBackBuffer(xy + hp*float2(-1, 1));
		float3 D = GetBackBuffer(xy + hp*float2(-1,-1));
		
		float3 M = 4.0*max( max(A,B), max(C,D) );
		
		float G = dot(abs(-4.0*c + (A+B+C+D)) / M, float3(0.299,0.587,0.114));
		float tG = 4.0 * dot(abs(c-p.rgb), float3(0.299,0.587,0.114));
		//
		
		float l = saturate( tG + (ACC_MODE!=1));
		float l2 = saturate(p.a - dot(p.rgb*p.rgb, float3(0.2126,0.7152,0.0722)) ) / (dot(p.rgb, float3(0.2126,0.7152,0.0722)) + 0.01);
		l2 = saturate(2.0 * sqrt(l2));
		//l = l*l*(3.0-2.0*l);
		l = sqrt(l2);
		return lerp(c,p.rgb + (ACC_MODE==1)*lap, l);//saturate(dot(G,));//tex2D(sPre, xy).rgb;//
	}
	
	technique ZenATA <
		ui_label = "BETA - Zenteon: ATA (Anti Temporal Aliasing) ";
		    ui_tooltip =        
		        "								  	 Zenteon - ATA          \n"
		        "\n================================================================================================="
		        "\n"
		        "\nLike TAA but not, reduces temporal aliasing with minimal smearing in motion"
		        "\nrecommended to use after SMAA, before Sharpening."
		        "\nREQUIRES High quality motion vectors, Zenteon: Motion or framework recommeded."
		        "\n"
		        "\n=================================================================================================";
		>	
	{
		pass {	PASS1(CurPS, tCur); }
		pass {	PASS1(PrePS, tPre); }
		pass {	PASS0(BlendPS); }
	}
}
