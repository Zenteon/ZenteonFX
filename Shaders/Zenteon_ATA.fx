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

uniform bool KILLSWITCH <
	hidden = 1;
> = 0;

uniform bool DO_NEIGHBORHOOD <
	hidden = 1;
> = 1;


uniform int ACC_MODE <
	ui_type = "slider";
	ui_tooltip = "0 is naive reprojection, very smeary, 1 is 3x3 nonlocal means, tends to denoise a bit too much \n"
				"doesn't resolve a lot of flicker, 2 is 2x2 best match NLM, least blurry, and most stable";
	ui_min = 0;
	ui_max = 2;
	hidden = 1;
> = 2;

uniform float FILTER_STRENGTH <
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "Filter Strength";
	ui_tooltip = "Higher values will give a more stable but less detailed image, can introduce aliasing";
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
	ui_max = 0.99;
	ui_label = "Accumulation value";
	ui_tooltip = "How much of the previous frames are blended, higher values will give a more stable but less responsive image";
	ui_type = "slider";
> = 0.9;


texture2D texMotionVectors { DIVRES(1); Format = RG16F; };
sampler2D sMV { Texture = texMotionVectors; };

texture2D tDOC { DIVRES(1); Format = R8; };
sampler2D sDOC { Texture = tDOC; };

namespace ZenTDF {
	
	//=======================================================================================
	//Textures/Samplers
	//=======================================================================================
	
	texture2D tCur { DIVRES(1); Format = RGB10A2; };
	sampler2D sCur { Texture = tCur; };
	
	texture2D tPre { DIVRES(1); Format = RGB10A2; };
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
		
		float4 acn;
		
		acn = all( abs(wm.xy - float2( 0, 1)) < 0.001 ) ? S[1]+S[2]+S[4]+S[5] : acn;
		acn = all( abs(wm.xy - float2( 0, 0)) < 0.001 ) ? S[4]+S[5]+S[7]+S[8] : acn;
		acn = all( abs(wm.xy - float2(-1, 1)) < 0.001 ) ? S[0]+S[1]+S[3]+S[4] : acn;
		acn = all( abs(wm.xy - float2(-1, 0)) < 0.001 ) ? S[3]+S[4]+S[6]+S[7] : acn;
		
		
		switch(ACC_MODE) {
			case 0: return tex2D(sPre, xy + MVi/RES);
			case 1: return float4(acc.rgb / acc.w, 1.0);
			case 2: return float4(acn.rgb / acn.w, 1.0);
		}
		return 0;
	}
	
	float4 PrePS(PS_INPUTS) : SV_Target
	{	 
		float4 pre = tex2D(sCur, xy);
		
		float4 cur = float4(GetBackBuffer(xy), 1.0);
		
		float3 MV;
		
		#if(USE_FRAMEWORK_MOTION)
			MV = GetVelocity(xy).xy;
		#else
			MV.xy = tex2D(sMV, xy).xy;
			MV.z = tex2D(sDOC, xy).x;
		#endif
		
		float2 txy = xy + MV.xy;
		float2 range = saturate(txy * txy - txy);
		MV.z *= range.x == -range.y;
		
		float3 minC = 1.0, maxC = 0.0;
		
		for(int i = 0; i < 9; i++)
		{
			float2 ni = vpos.xy + (float2( floor(i / 3.0), i % 3 ) - 1.0);
			float3 t = tex2Dfetch(ReShade::BackBuffer, ni).rgb;
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
		if(KILLSWITCH) return GetBackBuffer(xy);
		return tex2D(sPre, xy).rgb;//
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
