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
	Zenteon: Sharpen v0.1 - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/

#include "ReShade.fxh"
#include "ZenteonCommon.fxh"

uniform int FRAME_COUNT <
	source = "framecount";>;

#ifndef AO_METHOD
//============================================================================================
	#define AO_METHOD 3
//============================================================================================
#endif

//0 SSAO
//1 SAO
//2 GTAO
//3 BFGTAO

uniform int LABEL <
	ui_type = "radio";
	ui_label = " ";
	#if(AO_METHOD == 0)
		ui_text = "Screenspace Ambient Occlusion";
	#elif(AO_METHOD == 1)
		ui_text = "Scalable Ambient Obscurance";
	#elif(AO_METHOD == 2)
		ui_text = "Ground Truth Ambient Occlulsion";
	#elif(AO_METHOD == 3)
		ui_text = "Visibility Bitmask Ambient Occlusion";
	#endif
> = 0;

uniform int AO_QUALITY <
	ui_type = "combo";
	ui_label = "Quality";
	ui_items = "Low\0Medium\0High\0Ultra\0";
> = 2;

uniform float INTENSITY <
	ui_type = "drag";
	ui_label = "Intensity";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.9;

uniform float FADEOUT <
	ui_type = "drag";
	ui_label = "Fadeout\n\n";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.9;

uniform int SSAO_TYPE <
	ui_type = "combo";
	ui_label = "SSAO Type";
	ui_items = "Crytek\0SSAO\0SSAO Cosine\0";
	hidden = AO_METHOD != 0;
> = 1;

uniform float THICKNESS <
	ui_type = "drag";
	ui_label = "Z thickness";
	ui_min = 0.1;
	ui_max = 10.0;
	hidden = (AO_METHOD != 0) && (AO_METHOD < 3);
> = 1.0;

uniform float THICKNESS_M <
	ui_type = "drag";
	ui_label = "Z Distance Multiplier";
	ui_min = 0.0;
	ui_max = 0.2;
	hidden = AO_METHOD != 3;
> = 0.01;


uniform float GTAO_ATT <
	ui_type = "drag";
	ui_label = "Attenuation";
	ui_min = 0.0;
	ui_max = 10.0;
	hidden = AO_METHOD != 2;
> = 0.5;


uniform float THIN_AVD <
	ui_type = "drag";
	ui_label = "Thin Object Heuristic";
	ui_tooltip = "Slightly modified from the original to prevent haloing on foliage";
	ui_min = 0.0;
	ui_max = 1.0;
	hidden = AO_METHOD != 2;
> = 0.75;

uniform float RADIUS <
	ui_type = "drag";
	ui_label = "Radius";
	ui_min = 0.1;
	ui_max = 10.0;
> = 1.0;	

uniform float SIGMA <
	ui_type = "drag";
	ui_min = 0.5;
	ui_max = 10.0;
	ui_label = "Sigma";
	hidden = AO_METHOD != 1;
> = 1.5;

uniform float SAO_K <
	ui_type = "drag";
	ui_min = 0.5;
	ui_max = 2.0;
	ui_label = "K";
	hidden = AO_METHOD != 1;
> = 1.0;

uniform int DEBUG <
	ui_type = "combo";
	ui_label = "Debug";
	ui_items = "None\0Ambient Occlusion\0";
> = 1;


const static int RAYQUALITY[4] = { 2, 2, 4, 4};
const static int STEPQUALITY[4] = { 4, 8, 12, 24};;

#define SLICES (RAYQUALITY[AO_QUALITY])
#define STEPS (STEPQUALITY[AO_QUALITY])


namespace SSAO_HISTORY {
	
	//Functions
	//=======================================================================================
	
	float Bayer(uint2 p, uint level) //Thanks Marty
	{
	    p = (p ^ (p << 8u)) & 0x00ff00ffu;
	    p = (p ^ (p << 4u)) & 0x0f0f0f0fu;
		p = (p ^ (p << 2u)) & 0x33333333u;
		p = (p ^ (p << 1u)) & 0x55555555u;     
		
		uint i = (p.x ^ p.y) | (p.x << 1);     
		i = reversebits(i); 
		i >>= 32 - level * 2;  
		return float(i) / float(1 << (2 * level));
	}
	
	float GRnoise(float2 xy)
	{  
	    const float2 igr2 = float2(0.754877666, 0.56984029); 
	    xy *= igr2;
	    return frac(xy.x + xy.y);
	}
		
	//=======================================================================================
	//AO
	//=======================================================================================
	
	//normalized dot product assumuing component b is already normalized
	float dotnv(float3 a, float3 b)//Thx marty
	{
		return dot(a, b) * rsqrt(dot(a, a));
	}
	
	float2 FastAcos2(float2 x) {
	   return (-0.69813170*x*x - 0.87266463)*x + 1.57079633;
	}

	float FastAcos1(float x) {
	   return (-0.69813170*x*x - 0.87266463)*x + 1.57079633;
	}

	float GTAOContr(float2 a, float2 n)
	{
		float2 g = 0.25 * (-cos(2.0 * a - n) + cos(n) + 2.0 * a * sin(n) );
		return any(isnan(g)) ? 1.0 : g.x+g.y;
	}
	
	float2 TraceSliceBF(float2 xy, float3 verPos, float3 viewV, float3 normal, float2 vec, float jit, inout uint BITFIELD, float dsign, float N, float3 prjN)
	{
		float2 no = 1.4*dsign * vec * rcp(RES);
		vec *= float2(1.0, RES.x / RES.y);
		float h = dsign * sin(N);
		float p = 0.0;
   	 for(int i = 0; i < STEPS; i++)
   	 {
   	 	float o = (i + jit) / STEPS;
   	 	o *= o*o;
   	 	float2 nxy = xy + no + dsign * 0.1 * RADIUS * vec * o;
   	 	
   	 	
   	 	float samD;
   	 	[branch]
			if(o < 1.0) samD = GetDepth( round(nxy*RES) / RES);
			else samD = SampleDepth(nxy, 0.0);
   	 	float3 samPos = GetEyePos(nxy, samD * 1.001);
   	 	float3 tv = samPos - verPos;
   	 	float tmx = dotnv(tv, viewV);
   	 	float2 minmax = FastAcos2(float2(tmx, dotnv( normalize(samPos) * THICKNESS + (1.0 + THICKNESS_M) * samPos - verPos, viewV) ));	
			h = lerp(h, max(h,tmx), lerp(1.0, o, THIN_AVD) * rcp( GTAO_ATT * dot(tv,tv) / length(samPos) + 1.0) );
			//p = lerp(p, max(p,dotnv(tv, prjN)), 0.7 * rcp(0.01 * dot(tv,tv) + 1.0) );//
			
   	 	minmax = saturate( (dsign * -minmax - N + 1.5707) / 3.14159);
   	 	minmax = minmax.x > minmax.y ? minmax.yx : minmax;
   	 	//minmax = smoothstep(0,1, minmax);
   	 	int2 ab = clamp(round(32.0 * float2(minmax.x, minmax.y - minmax.x)), 0, 32);
   	 	BITFIELD |= ((1 << ab.y) - 1) << ab.x;
   	 }
   	   	
   	 return float2(h,p);
	}
	

	//=======================================================================================
	//Passes
	//=======================================================================================

	
	
	float BFAO(float2 xy, float3 verPos, float3 viewV, float3 n, float2 noise)
	{
		float AOacc;
		float acc;
		for(int i = 0; i < SLICES; i++)
		{
			noise.x += 3.14159 / SLICES;
			float2 vec = float2(sin(noise.x), cos(noise.x));
			
			float3 slcN = normalize(cross(float3(vec, 0.0f), viewV));
			float3 T = cross(viewV, slcN);
	    	float3 prjN = n - slcN * dot(n, slcN);
	   	 float N = -sign(dot(prjN, T)) * acos( clamp(dot(normalize(prjN), viewV), -1, 1) ).x;
	    	float3 prjNN = normalize(prjN);

			uint BITFIELD;	float4 h;
			h.xz = TraceSliceBF(xy, verPos, viewV, n, vec, noise.y, BITFIELD,  1, N, prjNN);
			h.yw = TraceSliceBF(xy, verPos, viewV, n, vec, noise.y, BITFIELD, -1, N, prjNN);
			
			float cosI = dot(float3(vec,0.0), n);
			float2 hn = FastAcos2(h.xy);
			
			hn = float2(-1,1) * hn;
			float ht = FastAcos1(dot(n,viewV)) + 1.5707;
			float2 ta = float2(-1,1) * (float2(hn.x - 1.5707,1.5707-hn.y) + N);
			
			#if(AO_METHOD == 2)
				AOacc += length(prjN) * GTAOContr(hn, N ); //GTAO
			#else
				AOacc += (1.0 - countbits(BITFIELD) / 32.0); //GTAO with bitmasks
			#endif
		}
		return saturate(AOacc / SLICES);
	}
	
	float3 mindV(float3 c, float3 a, float3 b)
	{
		float3 d0 = a - c;
		float3 d1 = c - b;
		return dot(d0,d0) < dot(d1,d1) ? d0 : d1;
	}
	
	
	//scalable ambient obscurance
	float SAO(float2 xy, float3 verPos, float3 n, float2 noise, float radius)
	{
		float g = 1.32471795724474602596;
		float2 ng = rcp(float2(g,g*g));
		float vl = length(verPos);
		
		float2 acc;
		for(int i = 0; i <= SLICES * STEPS; i++)
		{
			float2 ns = float2(6.28 * ( (noise.x + i) / (SLICES * STEPS) ), frac(noise.y + i/g) * radius / vl);//frac(noise.yy + ng.y*i);
			float2 nxy = xy + ns.y * float2(sin(ns.x), cos(ns.x)) * float2(1.0,RES.x/RES.y);
			
			float2 rg = saturate(nxy.xy * nxy.xy - nxy.xy);
			if(rg.x != -rg.y) continue;
			
			float3 samPos = NorEyePos(nxy);
			float3 tv = samPos - verPos;
   	 	acc += float2(max(0,dot(tv, n) ) / (dot(tv,tv) + 0.1), 1.0);
		}
		return pow(saturate(1.0 - SIGMA * 2.0 * acc.x / acc.y), SAO_K);
	}
	
	float3 GetCosVec(float3 normal, float2 rng, int c)
	{
	  rng.y = rng.y * 2.0 - 1.0;
	
	  float3 sphere;
	  sincos(6.28 * rng.x, sphere.y, sphere.x);
	  sphere.xy *= sqrt(1.0 - rng.y * rng.y);
	  sphere.z = rng.y;
	  
	  switch(c) {
	  	case 0: return (sphere);
	  	case 1: return dot(normal, sphere) > 0 ? sphere : -sphere;//
	  	case 2: return normalize(normal + sphere);
	  }
	  return 0.0;
	}
	
	float SSAO(float2 xy, float3 verPos, float3 n, float3 noise, float radius, float thickness)
	{
		float g = 1.220744084605759;
		float3 ng = rcp(float3(g,g*g,g*g*g));
		
		float2 acc = 0.0;
		for(int i = 0; i <= SLICES * STEPS; i++)
		{
			float3 ns = frac(noise + i * ng);
			float3 vec = (0.2 +ns.z) * 1.0*radius * (GetCosVec(n, ns.xy, SSAO_TYPE));
			float3 nxy = GetScreenPos(verPos + vec) + float3(1.0*(vec.xy) / (vec.z*RES), 0.000001);
			
			float2 rg = saturate(nxy.xy * nxy.xy - nxy.xy);
			if(rg.x != -rg.y) continue;
			
			float sZ = GetDepth(nxy.xy);
			acc += float2((nxy.z < sZ) || nxy.z > (sZ + 5.0 * thickness / FARPLANE), 1.0);
		}
		return acc.x / acc.y;
	}
	
	//=======================================================================================
	//Blending
	//=======================================================================================
	

	float3 BlendPS(PS_INPUTS) : SV_Target
	{
		const float Bayer5[25] = {
        0.00, 0.48, 0.12, 0.60, 0.24,
        0.32, 0.80, 0.44, 0.92, 0.56,
        0.08, 0.40, 0.04, 0.52, 0.16,
        0.64, 0.96, 0.76, 0.28, 0.88,
        0.72, 0.20, 0.84, 0.36, 0.68 };
        
        int2 pp = vpos.xy % 5;
        float dir = Bayer5[ (pp.x + 5*pp.y) ];
        float d = GetDepth(xy);
		float3 verPos = GetEyePos(xy,d);
		float vl = length(verPos);
		float3 normal = GetNormal(xy);
		float3 viewV = -verPos / vl;
		float2 noise = float2(dir, Bayer(vpos.xy, 3u) );
		float zn = GRnoise(vpos.xy);
		
		verPos += 0.002 * normal * vl;
		
		float AO;
		
		if(d > 0.99) return GetBackBuffer(xy) + DEBUG;
		
		#if(AO_METHOD == 0)
			AO = SSAO(xy, verPos, normal, float3(noise,zn), RADIUS, THICKNESS);
		#elif(AO_METHOD == 1)
			AO = SAO(xy, verPos, normal, noise, RADIUS);
		#elif(AO_METHOD > 1)
			AO = BFAO(xy, verPos, viewV, normal, float2(3.14159 / SLICES, 1.0) * noise);
		#endif
		
		AO = lerp(1.0, AO, INTENSITY);
		AO = lerp(1.0, AO, exp(-2.0 * (1.0 - FADEOUT) * d) );
		
		
		if(DEBUG) return AO;
		float3 b = IReinJ(GetBackBuffer(xy), HDR);
		return ReinJ(b*AO, HDR);
	}
	
	technique ZenSSAO_HISTORY <
		ui_label = "Zenteon: SSAO History";
		    ui_tooltip =        
		        "								  	 Zenteon - SSAO History           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nA barebones unoptimized implementation of various SSAO operators used since first introduced by"
		        "\nCrytek in 2007"
		        "\n"
		        "\n=================================================================================================";
		>	
	{	
		pass {	PASS0(BlendPS); }
	}
}
