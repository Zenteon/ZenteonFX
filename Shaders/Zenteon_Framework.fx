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
	Zenteon: Framework - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/
//========================================================================
#include "ReShade.fxh"
#include "ZenteonCommon.fxh"


#define _SUBPIXEL_FLOW 0

#ifndef SHOW_DEBUG
//============================================================================================
	#define SHOW_DEBUG 0
//============================================================================================
#endif

uniform float FRAME_TIME < source = "frametime"; >;

uniform int PROCESS_NORMALS <
	ui_type = "slider";
	ui_min = 0;
	ui_max = 1;
> = 0;
	
uniform float TEXTURE_INTENSITY <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.8;
	
uniform int MOT_QUALITY <
	ui_type = "combo";
	ui_label = "Motion Quality";
	ui_items = "Low\0Medium\0High\0";
> = 0;
	
uniform int DEBUG <
	ui_type = "combo";
	hidden = !SHOW_DEBUG;
	ui_items = "None\0Velocity\0Depth\0Albedo\0Normals\0Roughness\0";
> = 0;

/*
	16 taps
 6
 5
 4
 3   o o o o 
 2   o o o o 
 1   o o o o 
 0   o o o o 
-1
-2

-2-1 0 1 2 3 4 5 6 as

Big thanks to Marty for the idea
Lower noise, low cost increase, plays better with temporal stablization
	20 taps
 6
 5       o o
 4   o         o
 3     o     o
 2 o     o o     o 
 1 o     o o     o
 0     o     o 
-1   o         o
-2       o o

  -2-1 0 1 2 3 4 5 6 

 6
 5       o o
 4             
 3     o     o
 2 o     o o     o 
 1 o     o o     o
 0     o     o 
-1              
-2       o o

  -2-1 0 1 2 3 4 5 6 

	9 taps
 6
 5         o            
 4                
 3       o   o
 2   o     o     o 
 1       o   o    
 0             
-1         o      
-2          

  -2-1 0 1 2 3 4 5 6 


*/

static const int2 off16[16] = {
	int2(0,0), int2(1,0), int2(2,0), int2(3,0),
	int2(0,1), int2(1,1), int2(2,1), int2(3,1),
	int2(0,2), int2(1,2), int2(2,2), int2(3,2),
	int2(0,3), int2(1,3), int2(2,3), int2(3,3)
	};

static const int2 off20[20] = {
		int2(1,5), int2(2,5),
		int2(-1,4), int2(4,4),
		int2(0,3), int2(3,3),
	int2(-2,2), int2(1,2), int2(2,2), int2(5,2),
	int2(-2,1), int2(1,1), int2(2,1), int2(5,1),
		int2(0,0), int2(3,0),
		int2(-1,-1), int2(4,-1),
		int2(1,-2), int2(2,-2),
		
	};
	
static const int2 off16w[16] = {
		int2(1,5), int2(2,5),
		int2(0,3), int2(3,3),
	int2(-2,2), int2(1,2), int2(2,2), int2(5,2),
	int2(-2,1), int2(1,1), int2(2,1), int2(5,1),
		int2(0,0), int2(3,0),
		int2(1,-2), int2(2,-2),
	};

static const int2 off92[9] = {
	int2(2,5),
	int2(1,3),int2(3,3),
	int2(-1,2),int2(2,2),int2(5,2),
	int2(1,1),int2(3,1),
	int2(2,-1)
};

namespace FrameWork {
	
	#define FWRAP CLAMP
	#define LFORM RG16F
	#define LFILT LINEAR
	#define PFILT R16
	
	#define BLOCK_POS_CT 9
	#define UBLOCK off92
	#define TEMPORAL 1
	#define DIV_LEV 2
	
		
	texture2D tMaxD { DIVRES(4); Format = RG16; };
	sampler2D sMaxD { Texture = tMaxD; };
	
	texture2D tLevel0 { DIVRES((4 * DIV_LEV)); Format = RGBA16F; MipLevels = 1; };
	sampler2D sLevel0 { Texture = tLevel0; MagFilter = POINT; MinFilter = LINEAR; MipFilter = LINEAR; WRAPMODE(BORDER); };
	
	texture2D tTemp0M { DIVRES((4 * DIV_LEV)); Format = RGBA16F; };
	sampler2D sTemp0M { Texture = tTemp0M; FILTER(POINT); WRAPMODE(MIRROR); };
	texture2D tTemp1M { DIVRES((4 * DIV_LEV)); Format = RGBA16F; };
	sampler2D sTemp1M { Texture = tTemp1M; FILTER(POINT); WRAPMODE(MIRROR); };
	
	//subpixel is pretty expensive, so we render at 1/8th res instead of 1/4
	//Still a bit heavy but acceptable overall, and results don't really suffer
	texture2D tQuar  { DIVRES(4); Format = RGBA16F; };
	sampler2D sQuar  { Texture = tQuar; FILTER(POINT); };
	texture2D tHalf  { DIVRES(2); Format = RGBA16F; };
	sampler2D sHalf  { Texture = tHalf; FILTER(POINT); };
	texture2D tFull  { DIVRES(1); Format = RGBA16F; };
	sampler2D sFull  { Texture = tFull; FILTER(POINT); };
	
	texture2D tLD0 { DIVRES(1); Format = R16; };
	sampler2D sLD0 { Texture = tLD0; FILTER(POINT); };
	texture2D tLD1 { DIVRES(2); Format = R16; };
	sampler2D sLD1 { Texture = tLD1; FILTER(POINT); };
	texture2D tLD2 { DIVRES(4); Format = R16; };
	sampler2D sLD2 { Texture = tLD2; FILTER(POINT); };
	texture2D tLD3 { DIVRES(8); Format = R16; };
	sampler2D sLD3 { Texture = tLD3; FILTER(POINT); };
	
	
	texture2D tLevel1 { DIVRES((4 * DIV_LEV)); Format = LFORM; };
	sampler2D sLevel1 { Texture = tLevel1; FILTER(LFILT); WRAPMODE(FWRAP); };
	texture2D tLevel2 { DIVRES((8 * DIV_LEV)); Format = LFORM; };
	sampler2D sLevel2 { Texture = tLevel2; FILTER(LFILT); WRAPMODE(FWRAP); };
	texture2D tLevel3 { DIVRES((16 * DIV_LEV)); Format = LFORM; };
	sampler2D sLevel3 { Texture = tLevel3; FILTER(LFILT); WRAPMODE(FWRAP); };
	texture2D tLevel4 { DIVRES((32 * DIV_LEV)); Format = LFORM; };
	sampler2D sLevel4 { Texture = tLevel4; FILTER(LFILT); WRAPMODE(FWRAP); };
	texture2D tLevel5 { DIVRES((64 * DIV_LEV)); Format = LFORM; };
	sampler2D sLevel5 { Texture = tLevel5; FILTER(LFILT); WRAPMODE(FWRAP); };
	
	//current
	texture2D tCG0 { Width = RES.x / (0.5 * DIV_LEV); Height = RES.y / (0.5 * DIV_LEV); Format = PFILT; };
	sampler2D sCG0 { Texture = tCG0; WRAPMODE(FWRAP); };
	texture2D tCG1 { DIVRES((1 * DIV_LEV)); Format = PFILT; };
	sampler2D sCG1 { Texture = tCG1; WRAPMODE(FWRAP); };
	texture2D tCG2 { DIVRES((2 * DIV_LEV)); Format = PFILT; };
	sampler2D sCG2 { Texture = tCG2; WRAPMODE(FWRAP); };
	texture2D tCG3 { DIVRES((4 * DIV_LEV)); Format = PFILT; };
	sampler2D sCG3 { Texture = tCG3; WRAPMODE(FWRAP); };
	texture2D tCG4 { DIVRES((8 * DIV_LEV)); Format = PFILT; };
	sampler2D sCG4 { Texture = tCG4; WRAPMODE(FWRAP); };
	texture2D tCG5 { DIVRES((16 * DIV_LEV)); Format = PFILT; };
	sampler2D sCG5 { Texture = tCG5; WRAPMODE(FWRAP); };
	//previous
	texture2D tPG0 { Width = RES.x / (0.5 * DIV_LEV); Height = RES.y / (0.5 * DIV_LEV); Format = PFILT; };
	sampler2D sPG0 { Texture = tPG0; WRAPMODE(FWRAP); };
	texture2D tPG1 { DIVRES((1 * DIV_LEV)); Format = PFILT; };
	sampler2D sPG1 { Texture = tPG1; WRAPMODE(FWRAP); };
	texture2D tPG2 { DIVRES((2 * DIV_LEV)); Format = PFILT; };
	sampler2D sPG2 { Texture = tPG2; WRAPMODE(FWRAP); };
	texture2D tPG3 { DIVRES((4 * DIV_LEV)); Format = PFILT; };
	sampler2D sPG3 { Texture = tPG3; WRAPMODE(FWRAP); };
	texture2D tPG4 { DIVRES((8 * DIV_LEV)); Format = PFILT; };
	sampler2D sPG4 { Texture = tPG4; WRAPMODE(FWRAP); };
	texture2D tPG5 { DIVRES((16 * DIV_LEV)); Format = PFILT; };
	sampler2D sPG5 { Texture = tPG5; WRAPMODE(FWRAP); };
	
	texture2D tPreFrm { DIVRES(1); Format = RGB10A2; };
	sampler2D sPreFrm { Texture = tPreFrm; };
	/*
	#define LAP_FILT POINT
	texture2D tLG0 { DIVRES(1); Format = R16F; };
	sampler2D sLG0 { Texture = tLG0; FILTER(LAP_FILT); };
	texture2D tLG1 { DIVRES(2); Format = R16F; };
	sampler2D sLG1 { Texture = tLG1; FILTER(LAP_FILT); };
	texture2D tLG2 { DIVRES(4); Format = R16F; };
	sampler2D sLG2 { Texture = tLG2; FILTER(LAP_FILT); };
	texture2D tLG3 { DIVRES(8); Format = R16F; };
	sampler2D sLG3 { Texture = tLG3; FILTER(LAP_FILT); };
	texture2D tLG4 { DIVRES(16); Format = R16F; };
	sampler2D sLG4 { Texture = tLG4; FILTER(LAP_FILT); };
	*/
	//Color differences albedo
	texture2D tNorC { DIVRES(2); Format = RG16; };
	sampler2D sNorC { Texture = tNorC; };
	
	texture2D tMask { DIVRES(2); Format = R8; };
	sampler2D sMask { Texture = tMask; };
	
	texture2D tTemp0 { DIVRES(2); Format = R16; };
	sampler2D sTemp0 { Texture = tTemp0; };
	
	texture2D tTemp1 { DIVRES(2); Format = R16; };
	sampler2D sTemp1 { Texture = tTemp1; };
	
	
	texture2D tPreF { DIVRES(1); Format = RGBA16; MipLevels = 2; };
	sampler2D sPreF { Texture = tPreF; };
	
	texture2D tTempN0 { DIVRES(1); Format = RGBA16F; };
	sampler2D sTempN0 { Texture = tTempN0; };
	texture2D tHN0 { DIVRES(2); Format = RGBA16F; };
	sampler2D sHN0 { Texture = tHN0; };
	texture2D tHN1 { DIVRES(2); Format = RGBA16F; };
	sampler2D sHN1 { Texture = tHN1; };
	
	texture2D tCurve { DIVRES(1); Format = RGBA16; };
	
	//=======================================================================================
	//Functions
	//=======================================================================================
	
	float IGN(float2 xy)
	{
	    float3 conVr = float3(0.06711056, 0.00583715, 52.9829189);
	    return frac( conVr.z * frac(dot(xy % RES,conVr.xy)) );
	}
	
	//#define BLOCK_SIZE 4
	#define BLOCKS_SIZE 2
	
	//=======================================================================================
	//Optical Flow Functions
	//=======================================================================================
	
	float4 tex2DfetchLin(sampler2D tex, float2 vpos)
	{
		//return tex2Dfetch(tex, vpos);
		float2 s = tex2Dsize(tex);
		return tex2Dlod(tex, float4(vpos / s, 0, 0));
		//return texLodBicubic(tex, vpos / s, 0.0);
	}
	
	float3 tex2DfetchLinD(sampler2D tex, float2 vpos)
	{
		float2 s = tex2Dsize(tex);
		float2 t = tex2Dlod(tex, float4(vpos / s, 0, 0)).xy;
		float d = GetDepth(vpos / s);
		return float3(t,d);
	}
	
	float GetBlock(sampler2D tex, float2 vpos, float2 offset, float div, inout float Block[BLOCK_POS_CT] )
	{
		vpos = (vpos) * div;
		float acc;
		[loop]
		for(int i; i < BLOCK_POS_CT; i++)
		{
			int2 np = UBLOCK[i];
			float tCol = tex2DfetchLin(tex, vpos + np + offset).r;
			//tCol /= dot(tCol, 0.333) + 0.001;
			Block[i] = tCol;
			acc += tCol;
		}
		return acc / (BLOCK_POS_CT);
	}
	
	float4 GetBlock4(sampler2D tex, float2 vpos, float2 offset, float div)
	{
		vpos = (vpos) * div;
		return tex2DgatherR(tex, vpos + offset);
		
	}
	
	
	float BlockErr(float Block0[BLOCK_POS_CT], float Block1[BLOCK_POS_CT])
	{
		float ssd; float norm;
		[loop]
		for(int i; i < BLOCK_POS_CT; i++)
		{
			float t = (Block0[i] - Block1[i]);
			ssd += abs(t);
			norm += Block0[i] + Block1[i];
		
		}
		ssd /= norm + 0.001;
		return ssd;
	}
	

	float3 VecToCol(float2 v)
	{
	    float rad = length(v);
	    float a = atan2(-v.y, -v.x) / 3.14159265;
	
	    float fk = (a + 1.0) / 2.0 * 6.0;
	    int k0 = fk % 7;
	    int k1 = (k0 + 1) % 7;
	    float f = fk - k0;
	
	    float3 cols[7] = {
	        float3(1, 0, 0),
	        float3(1, 1, 0),
	        float3(0, 1, 0),
	        float3(0, 1, 1),
	        float3(0, 0, 1),
	        float3(1, 0, 1),
	        float3(1, 0, 0),
			};
	
	    float3 col0 = cols[k0];
	    float3 col1 = cols[k1];
	
	    float3 col = lerp(col0, col1, frac(f));
	    //col = tex2D(sMotGrad, float2(0.5 * a, 0.0)).rgb;
	    
	    float j = 0.666667 * rad;
	    float k = rad / (rad + 0.5);
	    float l = saturate(rad*rad);
		l = lerp(j,k,l);
		
	    
	    return any(isnan(col)) ? 0.0 : lerp(0.0, col, saturate(l));
	}
	
	
	float4 CalcMVL(sampler2D cur, sampler2D pre, int2 pos, float4 off, int RAD, bool reject)
	{
		float cBlock[BLOCK_POS_CT];
		GetBlock(cur, pos, 0.0, 4.0, cBlock);
		float sBlock[BLOCK_POS_CT];
		GetBlock(pre, pos, 0.0, 4.0, sBlock);
		
		float2 MV;
		float2 noff = off.xy;
		
		float Err = BlockErr(cBlock, sBlock);
		[loop]
		for(int q = 0; q <= MOT_QUALITY; q++)
		{
			float exm = exp2(-q);
			[loop]
			for(int i = -RAD; i <= RAD; i++) for(int ii = -RAD; ii <= RAD; ii++)
			{
				if(Err < 0.01) break;
				
				GetBlock(pre, pos, exm * float2(i, ii) + off.xy, 4.0, sBlock);
				float tErr = BlockErr(cBlock, sBlock);
				
				[flatten]
				if(tErr < Err)
				{
					Err = tErr;
					MV = exm * float2(i, ii);
				}	
			}
			off += MV;
			MV = 0.0;
		}
		return float4(MV + off.xy, Err, 1.0);
	}
	
	
	static const float2 soff4F[4] = {
					   float2(0,-1),
		float2(-1,0),				float2(1,0),
					   float2(0,1)  
	};
	
	//diamond search
	static const float2 soff8[8] = {
		float2(-1,-1), float2(0,-2), float2(1,-1),
		float2(-2,0),				float2(2,0),
		float2(-1,1),  float2(0,2),  float2(1,1)
	};
	
	float4 CalcMV(sampler2D cur, sampler2D pre, int2 pos, float4 off, int RAD, float mult)
	{
		float cBlock[BLOCK_POS_CT];
		GetBlock(cur, pos, 0.0, 4.0, cBlock);
		float sBlock[BLOCK_POS_CT];
		GetBlock(pre, pos, 0.0, 4.0, sBlock);
		
		float2 MV;
		
		float Err = BlockErr(cBlock, sBlock);
		
		
		for(int i = 0; i < 8; i++)
		{
			if(Err < 0.001) break;
			float2 noff = mult * soff8[i];
			GetBlock(pre, pos, noff + off.xy, 4.0, sBlock);
			float tErr = BlockErr(cBlock, sBlock);
			
			[flatten]
			if(tErr < Err)
			{
				Err = tErr;
				MV = noff;
			}	
		}
		off += MV;
		MV = 0.0;
		
		for(int q = 0; q <= MOT_QUALITY; q++)
		{
			float exm = exp2(-q);
			for(int i = 0; i < 4; i++)
			{
				if(Err < 0.001) break;
				float2 noff = mult * soff4F[i];
				GetBlock(pre, pos, exm * noff + off.xy, 4.0, sBlock);
				float tErr = BlockErr(cBlock, sBlock);
				
				[flatten]
				if(tErr < Err)
				{
					Err = tErr;
					MV = exm * noff;
				}	
			}
			off += MV;
			MV = 0.0;
		}
		return float4(off.xy, Err, 1.0);
	}
	
	//based on https://stackoverflow.com/questions/480960/how-do-i-calculate-the-median-of-five-in-c/6984153#6984153
	//Filtering between layers is more efficient than trying to filter samples as they're fetched
	//Yeah no it's not, with sample validation, no difference
	float4 FilterMV(sampler2D tex, sampler2D texC, float2 xy)
	{
		float2 its = rcp(tex2Dsize(tex));
		float cenC = tex2Dlod(texC, float4(xy,0,0)).x;
		
		float4 acc; float accw;
		
		for(int i = -1; i <= 1; i++) for(int j = -1; j <= 1; j++)
		{
			float2 nxy = xy + its * float2(i,j);
			float4 ts = tex2Dlod(tex, float4(nxy,0,0));
			float tc = tex2Dlod(texC, float4(xy,0,0)).x;
			float w = exp( -(10.0 * ts.z + 10.0 * abs(tc - cenC)) );
			
			acc += ts * w;
			accw += w;
		}
		
		return acc / accw;
	}
	
	static const int2 ioff[5] = { int2(0,0), int2(1,0), int2(0,1), int2(-1,0), int2(0,-1) };
	static const int4 ioffc[5] = { int4(1,0,-1,0), int4(1,-1,1,1), int4(1,1,-1,1), int4(-1,1,-1,-1), int4(1,-1,-1,-1) };
	
	float4 PrevLayerL(sampler2D tex, sampler2D cur, sampler2D pre, float2 vpos, float level, int ITER, float mult)
	{
		float cBlock[BLOCK_POS_CT];
		GetBlock(cur, vpos, 0.0, mult, cBlock);
		
		float sBlock[BLOCK_POS_CT];
		GetBlock(pre, vpos, 0.0, mult, sBlock);
		
		float Err = BlockErr(cBlock, sBlock);
		float4 MV = tex2DfetchLin(tex, 0.5 * vpos);
		[loop]
		for(int i = 1; i <= 1; i++) for(int ii; ii < 5; ii++)
		{
			float4 samMV = 2.0 * tex2DfetchLin(tex, 2 * i * ioff[ii] + 0.5 * vpos);
			float4 clampMV = 2.0 * tex2DfetchLin(tex, 2 * i * ioffc[ii].xy + 0.5 * vpos);
			clampMV.zw = 2.0 * tex2DfetchLin(tex, 2 * i * ioffc[ii].zw + 0.5 * vpos).xy;
			
			
			GetBlock(pre, vpos, samMV.xy, 4.0, sBlock);
			
			float tErr = BlockErr(cBlock, sBlock);
			
			[flatten]
			if(tErr < Err)
			{
				MV = samMV;
				Err = tErr;
			}
			
		}
		
		return MV;//

	}
	

	//=======================================================================================
	//Gaussian Pyramid
	//=======================================================================================
	
	float DUSample(sampler input, float2 xy, float div)//0.375 + 0.25
	{
		float2 hp = 0.5 * div * rcp(RES);
		float acc; float4 t;
		float minD = 1.0;
		
		acc += tex2D(input, xy + float2( hp.x,  hp.y)).x;
		acc += tex2D(input, xy + float2( hp.x, -hp.y)).x;
		acc += tex2D(input, xy + float2(-hp.x,  hp.y)).x;
		acc += tex2D(input, xy + float2(-hp.x, -hp.y)).x;
		return 0.25 * acc.x;
	}
	
	
	float Gauss0PS(PS_INPUTS) : SV_Target {
		float lum = dot(GetBackBuffer(xy), rcp(3.0) );
		float dep = GetDepth(xy + 0.5 / RES);
		
		float hlum = dot(GetBackBuffer(xy + 0.5 / RES), rcp(3.0) );
		
		if(lum <= exp2(-6)) lum += fwidth(dep) / (dep + 0.0001);
		
		return lum;//float2(lum, dep).xy; 
	}
	
	float minGather(sampler2D tex, float2 xy)
	{
		float4 g = tex2DgatherR(tex, xy);
		return min( min(g.x,g.y), min(g.z,g.w) );
	}
	float DD0PS(PS_INPUTS) : SV_Target { return GetDepth(xy); };
	float DD1PS(PS_INPUTS) : SV_Target { return minGather(sLD0, xy); };
	float DD2PS(PS_INPUTS) : SV_Target { return minGather(sLD1, xy); };
	float DD3PS(PS_INPUTS) : SV_Target { return minGather(sLD2, xy); };
	
	float2 Gauss1PS(PS_INPUTS) : SV_Target { return DUSample(sCG0, xy, 2.0).x; }
	float2 Gauss2PS(PS_INPUTS) : SV_Target { return DUSample(sCG1, xy, 4.0).x; }
	float2 Gauss3PS(PS_INPUTS) : SV_Target { return DUSample(sCG2, xy, 8.0).x; }
	float2 Gauss4PS(PS_INPUTS) : SV_Target { return DUSample(sCG3, xy, 16.0).x; }
	float2 Gauss5PS(PS_INPUTS) : SV_Target { return DUSample(sCG4, xy, 32.0).x; }
	
	float4 CopyFlowPS(PS_INPUTS) : SV_Target { return tex2D(sLevel0, xy); }
	float3 CopyColPS(PS_INPUTS) : SV_Target { return GetBackBuffer(xy); }
	float Copy0PS(PS_INPUTS) : SV_Target { return tex2D(sCG0, xy).x; }
	float Copy1PS(PS_INPUTS) : SV_Target { return tex2D(sCG1, xy).x; }
	float Copy2PS(PS_INPUTS) : SV_Target { return tex2D(sCG2, xy).x; }
	float Copy3PS(PS_INPUTS) : SV_Target { return tex2D(sCG3, xy).x; }
	float Copy4PS(PS_INPUTS) : SV_Target { return tex2D(sCG4, xy).x; }
	float Copy5PS(PS_INPUTS) : SV_Target { return tex2D(sCG5, xy).x; }

	//=======================================================================================
	//Motion Passes
	//=======================================================================================
	
	float4 Level5PS(PS_INPUTS) : SV_Target
	{
		return CalcMVL(sCG5, sPG5, vpos.xy, tex2Dlod(sLevel0, float4(xy, 0, 5) ) / 32, 4, 1);
	}
	
	float4 Level4PS(PS_INPUTS) : SV_Target
	{
		return CalcMV(sCG4, sPG4, vpos.xy, PrevLayerL(sLevel5, sCG4, sPG4, vpos.xy, 2, 1, 4.0), 1, 1);
	}
	
	float4 Level3PS(PS_INPUTS) : SV_Target
	{
		return CalcMV(sCG3, sPG3, vpos.xy, PrevLayerL(sLevel4, sCG3, sPG3, vpos.xy, 2, 1, 4.0), 1, 1);
	}
	
	float4 Level2PS(PS_INPUTS) : SV_Target
	{
		return CalcMV(sCG2, sPG2, vpos.xy, PrevLayerL(sLevel3, sCG2, sPG2, vpos.xy, 2, 1, 4.0), 1, 1);
	}
	
	float4 Level1PS(PS_INPUTS) : SV_Target
	{
		return CalcMV(sCG1, sPG1, vpos.xy, PrevLayerL(sLevel2, sCG1, sPG1, vpos.xy, 1, 1, 4.0), 1, 1);
	}
	
	float4 Level0PS(PS_INPUTS) : SV_Target
	{
		float4 MV = CalcMV(sCG0, sPG0, 2*vpos.xy, PrevLayerL(sLevel1, sCG0, sPG0, 2*vpos.xy, 0, 1, 4.0), 1, 0.5);
		return MV;
	}
	
	float4 Filter5PS(PS_INPUTS) : SV_Target { return FilterMV(sLevel5, sCG5, xy); }
	float4 Filter4PS(PS_INPUTS) : SV_Target { return FilterMV(sLevel4, sCG5, xy); }
	float4 Filter3PS(PS_INPUTS) : SV_Target { return FilterMV(sLevel3, sCG5, xy); }
	float4 Filter2PS(PS_INPUTS) : SV_Target { return FilterMV(sLevel2, sCG4, xy); }
	float4 Filter1PS(PS_INPUTS) : SV_Target { return FilterMV(sLevel1, sCG3, xy); }
	
	
	//=======================================================================================
	//Final Filtering
	//=======================================================================================
	
	float4 median3(float4 a, float4 b, float4 c)
	{
	    return max(min(a, b), min(max(a, b), c));
	}
	
	float4 Median9(sampler2D tex, float2 xy)
	{
		float2 ts = tex2Dsize(tex);
		float2 vpos = xy * ts;
		
	    float4 row0[3];
	    float4 row1[3];
	    float4 row2[3];
	
	    row0[0] = tex2Dfetch(tex, vpos + int2(-1, -1)).xy;
	    row0[1] = tex2Dfetch(tex, vpos + int2( 0, -1)).xy;
	    row0[2] = tex2Dfetch(tex, vpos + int2( 1, -1)).xy;
	    
	    row1[0] = tex2Dfetch(tex, vpos + int2(-1,  0)).xy;
	    row1[1] = tex2Dfetch(tex, vpos + int2( 0,  0)).xy;
	    row1[2] = tex2Dfetch(tex, vpos + int2( 1,  0)).xy;
	    
	    row2[0] = tex2Dfetch(tex, vpos + int2(-1,  1)).xy;
	    row2[1] = tex2Dfetch(tex, vpos + int2( 0,  1)).xy;
	    row2[2] = tex2Dfetch(tex, vpos + int2( 1,  1)).xy;
	
	    float4 m0 = median3(row0[0], row0[1], row0[2]);
	    float4 m1 = median3(row1[0], row1[1], row1[2]);
	    float4 m2 = median3(row2[0], row2[1], row2[2]);
	
	    return median3(m0, m1, m2);
	}
	
	float4 Median5(sampler2D tex, float2 xy)
	{
		float2 ts = tex2Dsize(tex);
		float2 vpos = xy * ts;
		
		float4 data[5];
		
		data[0] = tex2Dfetch(tex, vpos + int2(0,0));
		
		data[1] = tex2Dfetch(tex, vpos + int2(1,0));
		data[2] = tex2Dfetch(tex, vpos + int2(-1,0));
		data[3] = tex2Dfetch(tex, vpos + int2(0,1));
		data[4] = tex2Dfetch(tex, vpos + int2(0,-1));
		
		float4 t0 = max( min(data[0], data[1]), min(data[2], data[3]) );
		float4 t1 = min( max(data[0], data[1]), max(data[2], data[3]) );
		
		float4 med = max( min(data[4], t0), min(t1,max(data[4], t0)) );
		
		return float4(med.rgb, med.a);
	}
	
	float4 Filter8(sampler2D tex, float2 xy, float level)
	{
		float cenD = tex2Dlod(sLD3, float4(xy,0,0)).x;
		
		float2 its = exp2(level) * 8.0 * rcp(RES);
		
		float4 acc; float accw;
		
		for(int i = -1; i <= 1; i++) for(int j = -1; j <= 1; j++)
		{
			float2 nxy = xy + float2(i,j) * its;
			
			float samD = tex2Dlod(sLD3, float4(nxy,0,0)).x;
			float w = exp( -30.0 * abs(cenD - samD) / (cenD + 1e-10)) + 1e-10;
			
			float4 sam = tex2Dlod(tex, float4(nxy,0,0));
			
			acc += sam * w;
			accw += w;
		}
		return acc / accw;
	}
	
	float4 Flood0PS(PS_INPUTS) : SV_Target { return Median9(sLevel0, xy); }
	float4 Flood1PS(PS_INPUTS) : SV_Target { return Filter8(sTemp1M, xy, 2.0); }
	float4 Flood2PS(PS_INPUTS) : SV_Target { return Filter8(sTemp0M, xy, 1.0); }
	float4 Flood3PS(PS_INPUTS) : SV_Target { return Filter8(sTemp1M, xy, 0.0); }
	
	//=======================================================================================
	//Blending
	//=======================================================================================
	#define FRAD 1
	float4 FilterMVAtrous(sampler2D tex, float2 xy, float level)
	{
		float cenC = sqrt(tex2D(sCG1, xy).x);
		float2 its = 8.0 * rcp(RES);
		
		float4 acc; float accw;
		
		for( int i = -FRAD; i <= FRAD; i++) for( int j = -FRAD; j <= FRAD; j++)
		{
			float2 nxy = xy + its * float2(i,j);
			float samC = sqrt(tex2Dlod(sCG1, float4(nxy,0,0)).x);
			float4 samM = tex2Dlod(tex, float4(nxy,0,0));
			
			float w = exp( -10.0 * abs(samC - cenC) / (samC + cenC + 0.01) );
			acc += samM * w;
			accw += w;
		}
		return acc / accw;
	}
	
	float4 SmoothMV3(PS_INPUTS) : SV_Target { return FilterMVAtrous(sTemp0, xy, 3.0); }
	float4 SmoothMV2(PS_INPUTS) : SV_Target { return FilterMVAtrous(sTemp1, xy, 2.0); }
	float4 SmoothMV1(PS_INPUTS) : SV_Target { return FilterMVAtrous(sTemp0, xy, 1.0); }
	float4 SmoothMV0(PS_INPUTS) : SV_Target { return FilterMVAtrous(sTemp1, xy, 0.0); }
	
	
	float4 UpscaleMVI0(PS_INPUTS) : SV_Target
	{
		/*
		//large offset since median sampling, helps quite a bit at finding good candidates
		float2 mult = 1.0 * rcp(tex2Dsize(sTemp0));
		float cenD = tex2Dlod(sLD2, float4(xy,0,0)).x;
		
		float4 cenC = tex2DgatherR(sCG0, xy);
		
		float4 cd;
		float err = 100.0;
		float4 acc; float accw;
		
		for(int i=0; i <5; i++)
		{
			float2 nxy = xy + mult * (ioff[i]);
			float4 sam = tex2Dlod(sTemp0, float4(nxy,0,0));
			
			float samD = tex2Dlod(sLD3, float4(nxy,0,0)).x;
			float4 samC = tex2DgatherR(sPG0, xy + sam.xy / RES);
			float tErr = abs(cenD - samD);//(cenC, samC);
			
			[flatten]
			if(tErr < err)
			{
				err = tErr;
				cd = sam;
			}
		}
		return cd;
		*/
		
		float cenD = tex2Dlod(sLD2, float4(xy,0,0)).x;
		
		float2 its = 8.0 * rcp(RES);
		
		float4 acc; float accw;
		
		for(int i = -1; i <= 1; i++) for(int j = -1; j <= 1; j++)
		{
			float2 nxy = xy + float2(i,j) * its;
			
			float samD = tex2Dlod(sLD3, float4(nxy,0,0)).x;
			float w = exp( -50.0 * abs(cenD - samD) / (cenD + 1e-10)) + 1e-10;
			
			float4 sam = tex2Dlod(sTemp0M, float4(nxy,0,0));
			
			acc += sam * w;
			accw += w;
		}
		return acc / accw;
	}
	
	float4 UpscaleMVI(PS_INPUTS) : SV_Target
	{
		/*
		//large offset since median sampling, helps quite a bit at finding good candidates
		float2 mult = 1.0 * rcp(tex2Dsize(sQuar));
		float cenD = GetDepth(xy);
		//not as robust as multiple points, but it should be within a single pixel by now
		float3 cenC = nBackBuffer(xy);
		
		float4 cd;
		float err = 100.0;
		
		for(int i=0; i <5; i++)
		{
			float2 nxy = xy + mult * (ioff[i]);
			float4 sam = tex2Dlod(sQuar, float4(nxy,0,0));
			//float samD = tex2D(sMaxD, nxy).x;
			
			float3 samC = tex2D(sPreFrm, xy + sam.xy / RES).rgb;
			float tErr = dot(cenC - samC, cenC - samC);
			
			[flatten]
			if(tErr < err)
			{
				err = tErr;
				cd = sam;
			}
		}
		return cd;
		*/
		
		float cenD = tex2Dlod(sLD1, float4(xy,0,0)).x;
		
		float2 its = 4.0 * rcp(RES);
		
		float4 acc; float accw;
		
		for(int i = -1; i <= 1; i++) for(int j = -1; j <= 1; j++)
		{
			float2 nxy = xy + float2(i,j) * its;
			
			float samD = tex2Dlod(sLD2, float4(nxy,0,0)).x;
			float w = exp( -50.0 * abs(cenD - samD) / (cenD + 1e-10)) + 1e-10;
			
			float4 sam = tex2Dlod(sQuar, float4(nxy,0,0));
			
			acc += sam * w;
			accw += w;
		}
		return acc / accw;
	}
	
	float4 UpscaleMV(PS_INPUTS) : SV_Target
	{
		/*
		float2 mult = 1.0 * rcp(tex2Dsize(sHalf));
		float cenD = GetDepth(xy);
		
		float3 cenC = nBackBuffer(xy);
		
		float4 cd;
		float err = 100.0;
		
		for(int i=0; i <5; i++)
		{
			float2 nxy = xy + mult * (ioff[i]);
			float4 sam = tex2Dlod(sHalf, float4(nxy,0,0));
			//float samD = tex2D(sMaxD, nxy).x;
			
			float3 samC = tex2D(sPreFrm, xy + sam.xy / RES).rgb;
			float tErr = dot(cenC - samC, cenC - samC);
			
			[flatten]
			if(tErr < err)
			{
				err = tErr;
				cd = sam;
			}	
		}
		return float4(cd.xy, err, 1.0);
		*/
		
		float cenD = tex2Dlod(sLD0, float4(xy,0,0)).x;
		
		float2 its = 2.0 * rcp(RES);
		
		float4 acc; float accw;
		
		for(int i = -1; i <= 1; i++) for(int j = -1; j <= 1; j++)
		{
			float2 nxy = xy + float2(i,j) * its;
			
			float samD = tex2Dlod(sLD1, float4(nxy,0,0)).x;
			float w = exp( -50.0 * abs(cenD - samD) / (cenD + 1e-10)) + 1e-10;
			
			float4 sam = tex2Dlod(sHalf, float4(nxy,0,0));
			
			acc += sam * w;
			accw += w;
		}
		return acc / accw;
	}
	//=======================================================================================
	//Albedo
	//=======================================================================================
	/*
	float GetWeightedPyramid(sampler2D cuL, sampler2D loL, float2 xy, float level)
	{
		float div = exp2(level);
		float cur = tex2D(cuL, xy).x;
		//float pre = DUSample(loL, xy, exp2(level + 1.0) ).x;
		float pre = tex2D(loL, xy).x;
			
		float lap = (cur - pre) / (cur + exp2(-32) );
		return 0.35 * lap * exp(-32.0 * (1.0 + level) * lap*lap);
	}
	
	float4 GenLapN3(PS_INPUTS) : SV_Target { return GetWeightedPyramid(sCG3, sCG4, xy, 8.0); }
	float4 GenLapN2(PS_INPUTS) : SV_Target { return DUSample(sLG3, xy, 8.0).x + GetWeightedPyramid(sCG2, sCG3, xy, 4.0); }
	float4 GenLapN1(PS_INPUTS) : SV_Target { return DUSample(sLG2, xy, 4.0).x + GetWeightedPyramid(sCG1, sCG2, xy, 2.0); }
	float4 GenLapN0(PS_INPUTS) : SV_Target { return DUSample(sLG1, xy, 2.0).x + GetWeightedPyramid(sCG0, sCG1, xy, 1.0); }
	*/
	
	float3 SRGBtoOKLAB(float3 c) 
	{
	    float l = 0.4122214708f * c.r + 0.5363325363f * c.g + 0.0514459929f * c.b;
		float m = 0.2119034982f * c.r + 0.6806995451f * c.g + 0.1073969566f * c.b;
		float s = 0.0883024619f * c.r + 0.2817188376f * c.g + 0.6299787005f * c.b;
	
	    float l_ = pow(l, 0.3334);
	    float m_ = pow(m, 0.3334);
	    float s_ = pow(s, 0.3334);
	
	   return float3(
	        0.2104542553f*l_ + 0.7936177850f*m_ - 0.0040720468f*s_,
	        1.9779984951f*l_ - 2.4285922050f*m_ + 0.4505937099f*s_,
	        0.0259040371f*l_ + 0.7827717662f*m_ - 0.8086757660f*s_);
	}
	
	float3 OKLABtoSRGB(float3 c) 
	{
	    float l_ = c.x + 0.3963377774f * c.y + 0.2158037573f * c.z;
	    float m_ = c.x - 0.1055613458f * c.y - 0.0638541728f * c.z;
	    float s_ = c.x - 0.0894841775f * c.y - 1.2914855480f * c.z;
	
	    float l = l_*l_*l_;
	    float m = m_*m_*m_;
	    float s = s_*s_*s_;
	
	    return float3(
			 4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s,
			-1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s,
			-0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s);
	}
	
	float GradMag(sampler2D tex, float2 xy)
	{
		float2 mult = rcp(tex2Dsize(tex));
		
		float4 acc; float2 accn;
		float3 accd;
		
		for(int i = -1; i <= 1; i++) for(int j = -1; j <= 1; j++)
		{
			float2 nxy = xy + mult * float2(i,j);
			float2 samp = tex2Dlod(tex, float4(nxy,0,0)).xy;
			acc += float2(i,j).xyxy * samp.xxyy;
			accn += samp.xy;
			accd += GetDepth(nxy) * float3(i,j, 1.0);
		}
		return 15.0 * dot(abs(acc),1.0) + dot(abs(accd.xy), 20.0) / accd.z;
		//return ;//dot(0.5, float2(abs(acc.x) + abs(acc.y), abs(acc.z) + abs(acc.w)) / abs(accn + 0.01));
	}
	
	
	float StopBlur(sampler2D tex, float2 xy, int rad, bool x)
	{
		float2 mult = float2(x,!x) / tex2Dsize(tex);
		
		float acc; float mw = 1.0; float accw;
		
		for(int i=0; i<rad; i++)
		{
			float2 nxy = xy + mult*i;
			acc += mw * tex2Dlod(tex, float4(nxy,0,0)).x;
			accw += mw;
			
			mw *= tex2Dlod(sMask, float4(nxy,0,0)).x;
		}
		
		mw = 1.0;
		
		for(int i=1; i<rad; i++)
		{
			float2 nxy = xy - mult*i;
			mw *= tex2Dlod(sMask, float4(nxy,0,0)).x;
			acc += mw * tex2Dlod(tex, float4(nxy,0,0)).x;
			accw += mw;
			
			
		}
		return acc / accw;
	}
	
	float2 NormalizePS(PS_INPUTS) : SV_Target
	{
		float3 c = GetBackBuffer(xy);
		c = SRGBtoOKLAB(c);
		return 0.5 + c.yz;
	}
	
	float MaskPS(PS_INPUTS) : SV_Target
	{
		return 1.0 - GradMag(sNorC, xy);
	}
	
	float PrepPS(PS_INPUTS) : SV_Target
	{
		return  pow(tex2D(sCG0, xy).x,2.2);
	}
	
	float Blur0PS(PS_INPUTS) : SV_Target { return StopBlur(sTemp0, xy, 4, 1); }
	float Blur1PS(PS_INPUTS) : SV_Target { return StopBlur(sTemp1, xy, 4, 0); }
	float Blur2PS(PS_INPUTS) : SV_Target { return StopBlur(sTemp0, xy, 4, 1); }
	float Blur3PS(PS_INPUTS) : SV_Target { return StopBlur(sTemp1, xy, 4, 0); }
	
	//=======================================================================================
	//Normals
	//=======================================================================================
	
	float3 AtrousN(sampler2D tex, float2 xy, float level, int rad)
	{
		if(!PROCESS_NORMALS) discard;
		float3 cenN = tex2D(tex, xy).xyz;
		float cenD = GetDepth(xy);
		float2 mult = exp2(level) / tex2Dsize(tex);
		
		float4 acc;
		for(int i = -rad; i <= rad; i++) for(int ii = -rad; ii <= rad; ii++)
		{
			float2 nxy = xy + mult * float2(i,ii);
			float samD = GetDepth(nxy);
			float3 samN = tex2Dlod(tex, float4(nxy,0,0)).xyz;
			
			float w = dot(cenN, samN) > 0.8 + 0.19 * (level / (level + 1.0));
			//w *= dot(cenN, samN) < 0.9999;
			w *= exp(-10.0 * abs(cenD - samD) / (cenD + 0.01));
			acc += w * float4(samN, 1.0);
		}
		return acc.w > 0.01 ? normalize(acc.xyz) : cenN;
	}
	
	float4 GenNormalsPS(PS_INPUTS) : SV_Target 
	{
		float3 vc	  = NorEyePos(xy);
		float3 vx0	  = vc - NorEyePos(xy + float2(1, 0) / RES);
		float3 vy0 	 = vc - NorEyePos(xy + float2(0, 1) / RES);
		
		float3 vx1	  = -vc + NorEyePos(xy - float2(1, 0) / RES);
		float3 vy1 	 = -vc + NorEyePos(xy - float2(0, 1) / RES);
		float3 vx01	  = vc - NorEyePos(xy + float2(2, 0) / RES);
		float3 vy01 	 = vc - NorEyePos(xy + float2(0, 2) / RES);	
		float3 vx11	  = -vc + NorEyePos(xy - float2(2, 0) / RES);
		float3 vy11 	 = -vc + NorEyePos(xy - float2(0, 2) / RES);
		
		float dx0 = abs(vx0.z + (vx0.z - vx01.z));
		float dx1 = abs(vx1.z + (vx1.z - vx11.z));
		float dy0 = abs(vy0.z + (vy0.z - vy01.z));
		float dy1 = abs(vy1.z + (vy1.z - vy11.z));
		
		float3 vx = dx0 < dx1 ? vx0 : vx1;
		float3 vy = dy0 < dy1 ? vy0 : vy1;
		
		return float4(normalize(cross(vy, vx)), 1.0);
	}
	
	float4 SmoothNormals0PS(PS_INPUTS) : SV_Target { return float4(AtrousN(sTempN0, xy, 3.0, 1), 1.0); }
	float4 SmoothNormals1PS(PS_INPUTS) : SV_Target { return float4(AtrousN(sHN0, xy, 2.0, 2), 1.0); }
	float4 SmoothNormals2PS(PS_INPUTS) : SV_Target { return float4(AtrousN(sHN1, xy, 0.0, 1), 1.0); }
	float4 SmoothNormals3PS(PS_INPUTS) : SV_Target { return float4(AtrousN(sHN0, xy, 1.0, 1), 1.0); }
	
	float4 GenCurvePS(PS_INPUTS) : SV_Target 
	{
		float3 vc	  = GetNormal(xy);
		float3 vx0	  = vc - GetNormal(xy + float2(1, 0) / RES);
		float3 vy0 	 = vc - GetNormal(xy + float2(0, 1) / RES);
		
		float3 vx1	  = -vc + GetNormal(xy - float2(1, 0) / RES);
		float3 vy1 	 = -vc + GetNormal(xy - float2(0, 1) / RES);
		float3 vx01	  = vc - GetNormal(xy + float2(2, 0) / RES);
		float3 vy01 	 = vc - GetNormal(xy + float2(0, 2) / RES);	
		float3 vx11	  = -vc + GetNormal(xy - float2(2, 0) / RES);
		float3 vy11 	 = -vc + GetNormal(xy - float2(0, 2) / RES);
		
		float dx0 = abs(vx0.z + (vx0.z - vx01.z));
		float dx1 = abs(vx1.z + (vx1.z - vx11.z));
		float dy0 = abs(vy0.z + (vy0.z - vy01.z));
		float dy1 = abs(vy1.z + (vy1.z - vy11.z));
		
		float3 vx = dx0 < dx1 ? vx0 : vx1;
		float3 vy = dy0 < dy1 ? vy0 : vy1;
		
		float3 xn = vc - vx;
		float3 xp = vc + vx;

		float3 yn = vc - vy;
		float3 yp = vc + vy;
		
		float c = (cross(xn,xp).y - cross(yn,yp).x);
		
		return float4(sqrt(c.xxx), 1.0);
		//return vx.y//0.5 + 0.5 * float4( 1000.0 * cross(vy, vx) , 1.0);
	}
	
	float2 TexNormalsPS(PS_INPUTS) : SV_Target
	{
		float3 rawN = tex2D(sTempN0, xy).xyz;
		if(!PROCESS_NORMALS) return NormalEncode(rawN);
		
		float3 smoothN = tex2D(sHN1, xy).xyz;
		float3 finalN = dot(smoothN, rawN) > 0.83 ? smoothN : rawN;
		
		
		float3 cenP = NorEyePos(xy);
		float cenpL2 = dot(cenP, cenP);
		//float cenD = GetDepth(xy);
		float3 texN; float tacc;
		for(int i = -1; i <= 1; i++) for(int ii = -1; ii <= 1; ii++)
		{
			float2 nxy = xy + float2(i,ii) / RES;
			float4 samL = tex2D(zfw::sAlbedo, nxy);
			float sLum = GetLuminance(samL.rgb);
			float3 samP = NorEyePos(nxy);
			//float samD = GetDepth(nxy);
			float w = exp(-FARPLANE * distance(cenP, samP) / (cenpL2 + exp(-32) ));
			texN += float3(-i,-ii, 1.0 / w) * lerp(sLum.x, samL.w, 0.8);
			tacc += samL.w;
		}
		texN.xy /= texN.z + 1.0;
		texN = normalize(float3(texN.xy, 2.5 * pow(1.0 - 0.75 * TEXTURE_INTENSITY, 4.0) ) );
		
		//finalN = (0.5 + 0.5 * finalN) * 2.0 + float3(-1,-1,0);
		//texN = (0.5 - 0.5 * texN) * float3(-2,-2,2) + float3(1,1,-1);
		//finalN = finalN * dot(finalN, texN) / finalN.z - texN;
		//finalN = -normalize(finalN);
		finalN = normalize(float3(finalN.xy + texN.xy, finalN.z*texN.z));
		
		return NormalEncode(finalN);
	}
	
	//======================================================================================
	//Texture Storing
	//=======================================================================================
	
	float4 softRound(float4 x)
	{
		x = x - 0.5;
		return 0.5 + 0.52 * (x / (abs(x) + 0.02));
	}
	
	float3 Albedont(float2 xy)
	{
		float3 c = GetBackBuffer(xy + 0.0 / RES);
		
		float cl = 0.9 * dot(c, 0.3334) + 0.1;//GetLuminance(c);
		//float g = abs(ddx_fine(cl)) + abs(ddy_fine(cl));
		c *= c;
		c = c / (cl*cl);
		
		return c;
		
	}
	
	void SaveAlbedoPS(PS_INPUTS, out float4 albedo : SV_Target0, out float roughness : SV_Target1)
	{
		float4 col = GetBackBuffer(xy).rgbr;
		float2 its = rcp(RES);
		
		float3 i = IReinJ(col.rgb, HDR);
		float3 c = 0.5 * (i) / (dot( i, rcp(3.0)) + exp2(-8));
		float M0 = dot(c, rcp(3.0));
		float M1 = dot(c*c, rcp(3.0));
		
		float clum = GetLuminance(col.rgb);
		
		float blum = 1000.0;
		float err = 1.0;
		
		for(int i=0; i <5; i++)
		{
			float2 nxy = xy + its * (ioff[i]);
			float tlum = tex2D(sTemp0, nxy).x;
			float3 tcol = GetBackBuffer(nxy);			
			
			[flatten]
			if(dot(abs(col.rgb - tcol),0.33334) < err)
			{
				blum = tlum;
				err = dot(abs(col.rgb - tcol),0.33334);//abs(clum-tlum);
			}
		}
		
		
		col.a = blum;
		
		albedo = pow(0.5 * pow(col,2.2) / (3.0*blum + 0.01), rcp(2.2));
		albedo.rgb *= 0.5 + 1.5 * (abs(M0-M1) / (M0 + M1 + 0.1) );
		
		
		
		float lum = GetLuminance(pow(col.rgb,2.2));
		roughness = saturate(0.33334 * blum / (lum + 0.0001) - 0.18);
	}
	
	float4 SaveMVPS(PS_INPUTS) : SV_Target
	{
		float3 MV = tex2D(sFull, xy).xyz;
		float cenD = GetDepth(xy);
		float2 its = rcp(RES);
		for(int i=0; i <5; i++)
		{
			float2 nxy = xy + its * (ioff[i]);
			float samD = GetDepth(nxy).x;
			float3 samMV = tex2D(sFull, nxy).xyz;
			
			[flatten]
			if(samD < cenD)
			{
				cenD = samD;
				MV = samMV;
			}
		}
		
		//float fd = dot(normalize(GetEyePos(xy, 1.0)), -GetNormal(xy));

		float2 backV = tex2D(sFull, xy + MV.xy / RES).xy;
		cenD = GetDepth(xy + MV.xy / RES);
		for(int i=0; i <5; i++)
		{
			float2 nxy = xy + its * (ioff[i]) + MV.xy / RES;
			float samD = GetDepth(nxy).x;
			float3 samMV = tex2D(sFull, nxy).xyz;
			
			[flatten]
			if(samD < cenD)
			{
				cenD = samD;
				backV = samMV.xy;
			}
		}
		
		
		float doc = rcp(length(MV.xy - backV) / length(MV.xy) + 1.0);// < 0.125 * (length(MV.xy) + 1.0) / fd;
		doc = all(abs(MV.xy) < 1.0) ? 1.0 : doc; 
		doc *= all(abs(xy+MV.xy/RES - 0.5) <= 0.5);
		//doc = doc * doc * doc * (doc * (6.0 * doc - 15.0) + 10.0);
		//doc = doc * doc * doc * (doc * (6.0 * doc - 15.0) + 10.0);
		doc = doc > 0.9;//smoothstep(0,1,doc);
		//doc = smoothstep(0,1,doc);
		//doc = smoothstep(0,1,doc);
		
		MV.xy /= 1.0 + _SUBPIXEL_FLOW;
		MV.xy = any(abs(MV.xy) > 0.00000001) ? MV.xy / RES : 0.0;
		
		return float4(MV.xy, doc, 1.0);
	}
	
	float4 SavePreFPS(PS_INPUTS) : SV_Target
	{
		//float2 n = tex2D(Zenteon::sNormal, xy).xy;
		//float d = GetDepth(xy);
		//return float4(n,d,1.0);
		//return float4(GetBackBuffer(xy), 1.0);
		return float4(GetAlbedo(xy), 1.0);
	}
	
	void SaveSmallPS(PS_INPUTS, out float4 nor : SV_Target0, out float dep : SV_Target1)
	{
		xy = 4.0 * floor(vpos.xy) / RES;
		float maxD = 0.0;
		for(int i = 0; i < 4; i++) for(int ii = 0; ii < 4; ii++)
		{
			float2 nxy = xy + 1.0 * float2(i,ii) / RES;
			maxD = max(maxD, GetDepth(nxy));
		}
		
		dep = maxD;//GetDepth(xy);
		nor = tex2D(zfw::sNormal, xy);
	}
	//=======================================================================================
	//Blending
	//=======================================================================================
	
	float3 BlendPS(PS_INPUTS) : SV_Target
	{
		float dither = (IGN(vpos.xy) - 0.5) * exp2(-8);
		float2 MV = GetVelocity(xy).xy;
		
		if(DEBUG == 3) return pow(GetAlbedo(xy), rcp(2.2));
		
		float3 n = GetNormal(xy);
		//float3 v = normalize(GetEyePos(xy,1.0));
		//float l = saturate(dot(n,-v));
		if(DEBUG == 4) return 0.5 + 0.5 * n;
		
		float dep = GetDepth(xy);
		//if(DEBUG == 2) return pow(dep, 0.35) * lerp(float3(0.9, 0.5, 0.1), float3(0.5,0.1,0.9), 2.0 * abs(sqrt(dep) - 0.5));
		float3 depCol = lerp(lerp( float3(1.0,0.7,0.0), float3(0.4,0.0,0.4), saturate(2.0 * sqrt(dep)) ), 0.0, saturate(2.0*sqrt(dep)-1.0));
		if(DEBUG == 2) return dither + depCol;
		//if(DEBUG == 2) return round(frac(0.25*NorEyePos(xy).xyz));;
		if(DEBUG == 1) return VecToCol(RES * MV / FRAME_TIME);
		if(DEBUG == 5) return GetRoughness(xy);
		return GetBackBuffer(xy);
	}
	
	technique ZenteonFrameWork <
		ui_label = "Zenteon: Framework";
		    ui_tooltip =        
		        "								  	 Zenteon - Framework           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nFramework creates information for other Zenteon shaders"
		        "\nMake sure it gets placed at the top of your shader list"
		        "\n"
		        "\n=================================================================================================";
		>	
	{
		pass {	PASS1(Gauss0PS, tCG0); }
		pass {	PASS1(Gauss1PS, tCG1); }
		pass {	PASS1(Gauss2PS, tCG2); }
		pass {	PASS1(Gauss3PS, tCG3); }
		pass {	PASS1(Gauss4PS, tCG4); }
		pass {	PASS1(Gauss5PS, tCG5); }
	
		pass {	PASS1(DD0PS, tLD0); }
		pass {	PASS1(DD1PS, tLD1); }
		pass {	PASS1(DD2PS, tLD2); }
		pass {	PASS1(DD3PS, tLD3); }
	
		//optical flow
		pass {	PASS1(Level5PS, tLevel5); }
		pass {	PASS1(Level4PS, tLevel4); }
		pass {	PASS1(Level3PS, tLevel3); }
		pass {	PASS1(Level2PS, tLevel2); }
		pass {	PASS1(Level1PS, tLevel1); }
		pass {	PASS1(Level0PS, tLevel0); }	
		
		pass {	PASS1(Flood0PS, tTemp1M); }
		pass {	PASS1(Flood1PS, tTemp0M); }	
		pass {	PASS1(Flood2PS, tTemp1M); }	
		pass {	PASS1(Flood3PS, tTemp0M); }	
		
		pass {	PASS1(UpscaleMVI0, tQuar); }	
		pass {	PASS1(UpscaleMVI, tHalf); }	
		pass {	PASS1(UpscaleMV, tFull); }	
		
		pass {	PASS1(SaveMVPS, zfw::tVelocity); }

		pass {	PASS1(CopyColPS, tPreFrm); }	
		pass {	PASS1(Copy0PS, tPG0); }	
		pass {	PASS1(Copy1PS, tPG1); }
		pass {	PASS1(Copy2PS, tPG2); }
		pass {	PASS1(Copy3PS, tPG3); }
		pass {	PASS1(Copy4PS, tPG4); }
		pass {	PASS1(Copy5PS, tPG5); }
		/*
		//albedo
		pass {	PASS1(GenLapN3, tLG3); }
		pass {	PASS1(GenLapN2, tLG2); }
		pass {	PASS1(GenLapN1, tLG1); }
		pass {	PASS1(GenLapN0, tLG0); }
		*/
		pass {	PASS1(NormalizePS, tNorC); }
		pass {	PASS1(MaskPS, tMask); }
		
		pass {	PASS1(PrepPS, tTemp0); }
		pass {	PASS1(Blur0PS, tTemp1); }
		pass {	PASS1(Blur1PS, tTemp0); }
		pass {	PASS1(Blur2PS, tTemp1); }
		pass {	PASS1(Blur3PS, tTemp0); }
		
		pass {	PASS2(SaveAlbedoPS, zfw::tAlbedo, zfw::tRoughness); }
		
		pass {	PASS1(GenNormalsPS, tTempN0); }
		pass {	PASS1(SmoothNormals0PS, tHN0); }
		pass {	PASS1(SmoothNormals1PS, tHN1); }
		pass {	PASS1(SmoothNormals2PS, tHN0); }
		pass {	PASS1(SmoothNormals3PS, tHN1); }
		
		pass {	PASS1(TexNormalsPS, zfw::tNormal); }
		//pass {	PASS1(GenCurvePS, tCurve); }
		
		pass {	PASS1(SaveMVPS, zfw::tVelocity); }
		pass {	PASS2(SaveSmallPS, zfw::tLowNormal, zfw::tLowDepth); }
		
		pass {	PASS1(SavePreFPS, tPreF); }
		
		#if(SHOW_DEBUG)
			pass {	PASS0(BlendPS); }
		#endif
	}
}
