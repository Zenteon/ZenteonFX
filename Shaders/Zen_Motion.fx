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
	Zenteon: Motion - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/
//========================================================================
		
//Not sure what else to call this, half res vectors, half pixel precision

#define _SUBPIXEL_FLOW 0

#include "ReShade.fxh"
#include "ZenteonCommon.fxh"

uniform int MOT_QUALITY <
	ui_type = "combo";
	ui_label = "Motion QUality";
	ui_items = "Low\0Medium\0High\0";
> = 0;


uniform bool DEBUG <
	ui_label = "Debug Flow";
> = 0;



uniform bool TEST0 <
	hidden = true;
> = 0;

//stablize debug
uniform float FRAME_TIME < source = "frametime"; >;

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

-2-1 0 1 2 3 4 5 6 

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

static const int2 off9[9] = {
	int2(-1,-1), int2(5,-1),
	int2(1,1), int2(3,1),
	int2(2,2),
	int2(1,3), int2(3,3),
	int2(-1,5), int2(5,5),
	
	};
//slightly less noisy
static const int2 off92[9] = {
	int2(2,5),
	int2(1,3),int2(3,3),
	int2(-1,2),int2(2,2),int2(5,2),
	int2(1,1),int2(3,1),
	int2(2,-1)
	};


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
	
static const int2 off5[5] = { int2(0,0), int2(0,2), int2(2,0), int2(2,2), int2(1,1) };

	#define BLOCK_POS_CT 9
	#define UBLOCK off9
	#define TEMPORAL 1
	

	
	//Pass helpers
	
	texture texMotionVectors { DIVRES(1); Format = RG16F; };
	texture tDOC { DIVRES(1); Format = R8; };
	sampler sDOC { Texture = tDOC; };
	sampler sMV { Texture = texMotionVectors; };
namespace ZenMotion {
		
	#define FWRAP CLAMP
	#define LFORM RGBA16F
	#define LFILT POINT
	#define PFILT R16
	#define DIV_LEV (2 - _SUBPIXEL_FLOW)
	//#define BLOCK_SIZE 4
	
	#define BLOCKS_SIZE 2
	
	//optical flow
	
	texture2D tLevel0 { DIVRES((4 * DIV_LEV)); Format = RGBA16F; MipLevels = 1; };
	sampler2D sLevel0 { Texture = tLevel0; MagFilter = POINT; MinFilter = LINEAR; MipFilter = LINEAR; WRAPMODE(BORDER); };
	
	texture2D tTemp0 { DIVRES((4 * DIV_LEV)); Format = RGBA16F; };
	sampler2D sTemp0 { Texture = tTemp0; FILTER(POINT); WRAPMODE(MIRROR); };
	texture2D tTemp1 { DIVRES((4 * DIV_LEV)); Format = RGBA16F; };
	sampler2D sTemp1 { Texture = tTemp1; FILTER(POINT); WRAPMODE(MIRROR); };
	
	//subpixel is pretty expensive, so we render at 1/8th res instead of 1/4
	//Still a bit heavy but acceptable overall, and results don't really suffer
	texture2D tQuar  { DIVRES(4); Format = RGBA16F; };
	sampler2D sQuar  { Texture = tQuar; FILTER(POINT); };
	texture2D tHalf  { DIVRES(2); Format = RGBA16F; };
	sampler2D sHalf  { Texture = tHalf; FILTER(POINT); };
	texture2D tFull  { DIVRES(1); Format = RGBA16F; };
	sampler2D sFull  { Texture = tFull; FILTER(POINT); };
	
	
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
	
	
	//=======================================================================================
	//Functions
	//=======================================================================================
	
	float IGN(float2 xy)
	{
	    float3 conVr = float3(0.06711056, 0.00583715, 52.9829189);
	    return frac( conVr.z * frac(dot(xy % RES,conVr.xy)) );
	}
	
	
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
		for(int i; i < BLOCK_POS_CT; i++)
		{
			float t = (Block0[i] - Block1[i]);
			ssd += abs(t);
			norm += Block0[i] + Block1[i];
		
		}
		ssd /= norm + 0.001;
		return ssd;
	}
	

	float3 HueToRGB(float hue)
	{
	    float3 fr = frac(hue.xxx + float3(0.0, -1.0/3.0, 1.0/3.0));
	    return 3.0 * abs(1.0 - 2.0*fr) - 1.0;
	}
		
	float3 MVtoRGB( float2 MV )
	{
		float3 col = HueToRGB(atan2(MV.y, MV.x) / 6.28);
		if(any(isnan(col))) return 0.7152;
		float lmv = length(MV);
		
		return lerp(0.7152, col, lmv );
	
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

		for(int q = 0; q <= MOT_QUALITY; q++)
		{
			float exm = exp2(-q);
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
	
	float4 FloodAPS(PS_INPUTS) : SV_Target { return Median9(sLevel0, xy); }
	float4 FloodBPS(PS_INPUTS) : SV_Target { return Median9(sTemp1, xy); }
	
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
		//large offset since median sampling, helps quite a bit at finding good candidates
		float2 mult = 4.0 * rcp(tex2Dsize(sTemp0));
		float cenD = GetDepth(xy);
		
		float4 cenC = tex2DgatherR(sCG0, xy);
		
		float4 cd;
		float err = 1.0;
		
		for(int i=0; i <5; i++)
		{
			float2 nxy = xy + mult * (ioff[i]);
			float4 sam = Median5(sTemp0, float4(nxy,0,0).xy);
			//float samD = tex2D(sMaxD, nxy).x;
			
			float4 samC = tex2DgatherR(sPG0, xy + sam.xy / RES);
			float tErr = distance(cenC, samC);
			
			[flatten]
			if(tErr < err)
			{
				err = tErr;
				cd = sam;
			}
		}
		return cd;
	}
	
	float4 UpscaleMVI(PS_INPUTS) : SV_Target
	{
		//large offset since median sampling, helps quite a bit at finding good candidates
		float2 mult = 2.0 * rcp(tex2Dsize(sQuar));
		float cenD = GetDepth(xy);
		//not as robust as multiple points, but it should be within a single pixel by now
		float3 cenC = GetBackBuffer(xy);
		
		float4 cd;
		float err = 10.0;
		
		for(int i=0; i <5; i++)
		{
			float2 nxy = xy + mult * (ioff[i]);
			float4 sam = Median5(sQuar, float4(nxy,0,0).xy);
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
	}
	
	float4 UpscaleMV(PS_INPUTS) : SV_Target
	{
		float2 mult = 1.0 * rcp(tex2Dsize(sHalf));
		float cenD = GetDepth(xy);
		
		float3 cenC = GetBackBuffer(xy);
		
		float4 cd;
		float err = 10.0;
		
		for(int i=0; i <5; i++)
		{
			float2 nxy = xy + mult * (ioff[i]);
			float4 sam = Median5(sHalf, float4(nxy,0,0).xy);
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
	}
	
	
	
	void SavePS(PS_INPUTS, out float2 mv : SV_Target0, out float doc : SV_Target1)
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
		
		
		
		float2 backV = tex2D(sFull, xy + MV.xy / RES).xy;
		//doc = length(MV.xy - backV) < 0.25 * (length(MV.xy) + 1.0);\
		doc = rcp(length(MV.xy - backV) / length(MV.xy) + 1.0);
		doc = all(abs(MV.xy) < 1.0) ? 1.0 : doc; 
		
		
		MV.xy /= 1.0 + _SUBPIXEL_FLOW;
		mv = any(abs(MV.xy) > 0.0001) ? MV.xy / RES : 0.0;
	}
	
	float3 BlendPS(PS_INPUTS) : SV_Target
	{
		float2 MV = tex2D(sMV, xy + 2.0 / RES).xy;
		//MV *= (RES);
		
		MV *= rcp(FRAME_TIME);
		//MV = 2.0 * MV / (abs(MV) + 0.002);
		//MV = lerp(MV, MV / (abs(MV) + 0.001), saturate(MV));
		MV = MV / (abs(MV) + 0.001);
		float doc = tex2D(sDOC, xy).x;
		return DEBUG ? MVtoRGB(MV) : GetBackBuffer(xy);
	}
	
	technique ZenMotion <
		ui_label = "Zenteon: Motion";
		    ui_tooltip =        
		        "								  	 Zenteon - Motion           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nGenerates motion vectors for other shaders"
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
	
		//optical flow
		pass {	PASS1(Level5PS, tLevel5); }
		pass {	PASS1(Level4PS, tLevel4); }
		pass {	PASS1(Level3PS, tLevel3); }
		pass {	PASS1(Level2PS, tLevel2); }
		pass {	PASS1(Level1PS, tLevel1); }
		pass {	PASS1(Level0PS, tLevel0); }	
		
		pass {	PASS1(FloodAPS, tTemp1); }
		pass {	PASS1(FloodBPS, tTemp0); }	
		
		pass {	PASS1(UpscaleMVI0, tQuar); }	
		pass {	PASS1(UpscaleMVI, tHalf); }	
		pass {	PASS1(UpscaleMV, tFull); }	
		
		pass {	PASS2(SavePS, texMotionVectors, tDOC); }

		pass {	PASS1(CopyColPS, tPreFrm); }	
		pass {	PASS1(Copy0PS, tPG0); }	
		pass {	PASS1(Copy1PS, tPG1); }
		pass {	PASS1(Copy2PS, tPG2); }
		pass {	PASS1(Copy3PS, tPG3); }
		pass {	PASS1(Copy4PS, tPG4); }
		pass {	PASS1(Copy5PS, tPG5); }
	
		
		pass {	PASS0(BlendPS); }
	}
}