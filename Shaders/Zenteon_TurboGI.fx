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
	Zenteon: TurboGI vSomething - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/

#include "ReShade.fxh"
#include "ZenteonCommon.fxh"

uniform int FRAME_COUNT <
	source = "framecount";>;

uniform float INTENSITY <
	ui_type = "drag";
	ui_label = "GI Intensity";
	ui_min = 0.0;
	ui_max = 5.0;
> = 1.0;

uniform float AO_INTENSITY <
	ui_min = 0.0;
	ui_max = 1.0;
	ui_type = "drag";
	ui_label = "AO Intensity";
> = 0.8;

uniform float RAY_LENGTH <
	ui_min = 0.5;
	ui_max = 1.0;
	ui_type = "drag";
	ui_label = "Ray Length";
> = 1.0;

uniform float FADEOUT <
	ui_min = 0.0;
	ui_max = 1.0;
	ui_type = "drag";
	ui_label = "Fadeout";
> = 0.6;

uniform int DEBUG <
	ui_type = "combo";
	ui_items = "None\0GI\0";
	ui_label = "Debug";
> = 0;

uniform bool MV_COMP <
	ui_label = "Zenteon: Motion Compatibility";
	ui_tooltip = "Enable ONLY IF USING Zenteon: Motion, reduces flickering almost completely.\n"
	"WILL INCRESE NOISE IF OTHER MOTION VECTORS ARE USED";
> = 0;

texture texMotionVectors { DIVRES(1); Format = RG16F; };
sampler MVSam0 { Texture = texMotionVectors; };	
texture tDOC { DIVRES(1); Format = R8; MipLevels = 3; };
sampler sDOC { Texture = tDOC; };

namespace ZenTGI {
	
	//=======================================================================================
	//Textures/Samplers
	//=======================================================================================
	
	texture2D tDep1 { DIVRES(2); Format = R16; };
	sampler2D sDep1 { Texture = tDep1; };
	texture2D tDep2 { DIVRES(4); Format = R16; MipLevels = 6; };
	sampler2D sDep2 { Texture = tDep2; };
	
	texture2D tNormal { DIVRES(1); Format = RGB10A2; MipLevels = 8; };
	sampler2D sNormal { Texture = tNormal; };
	texture2D tRadiance { DIVRES(4); Format = RGBA16F; MipLevels = 6; };
	sampler2D sRadiance { Texture = tRadiance; };
	
	texture2D tGI0 { DIVRES(4); Format = RGBA16F; };
	sampler2D sGI0 { Texture = tGI0; };
	
	texture2D tPGI { DIVRES(4); Format = RGBA16F; };
	sampler2D sPGI { Texture = tPGI; };
	
	texture2D tPDep { DIVRES(4); Format = R16; };
	sampler2D sPDep { Texture = tPDep; };
	
	texture2D tSH0 { DIVRES(4); Format = RGBA16F; };
	sampler2D sSH0 { Texture = tSH0; };
	texture2D tCol0 { DIVRES(4); Format = RGBA16F; };
	sampler2D sCol0 { Texture = tCol0; };
	
	texture2D tSH1 { DIVRES(2); Format = RGBA16F; };
	sampler2D sSH1 { Texture = tSH1; FILTER(POINT); };
	texture2D tCol1 { DIVRES(2); Format = RGBA16F; };
	sampler2D sCol1 { Texture = tCol1; FILTER(POINT); };
	
	texture2D tSH2 { DIVRES(1); Format = RGBA16F; };
	sampler2D sSH2 { Texture = tSH2; };
	texture2D tCol2 { DIVRES(1); Format = RGBA16F; };
	sampler2D sCol2 { Texture = tCol2; };
	
	//=======================================================================================
	//Functions
	//=======================================================================================


	float4 GatherLinDepth(float2 texcoord)
	{
		#if RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN
		texcoord.y = 1.0 - texcoord.y;
		#endif
		#if RESHADE_DEPTH_INPUT_IS_MIRRORED
		        texcoord.x = 1.0 - texcoord.x;
		#endif
		texcoord.x /= RESHADE_DEPTH_INPUT_X_SCALE;
		texcoord.y /= RESHADE_DEPTH_INPUT_Y_SCALE;
		#if RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET
		texcoord.x -= RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET * BUFFER_RCP_WIDTH;
		#else // Do not check RESHADE_DEPTH_INPUT_X_OFFSET, since it may be a decimal number, which the preprocessor cannot handle
		texcoord.x -= RESHADE_DEPTH_INPUT_X_OFFSET / 2.000000001;
		#endif
		#if RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET
		texcoord.y += RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET * BUFFER_RCP_HEIGHT;
		#else
		texcoord.y += RESHADE_DEPTH_INPUT_Y_OFFSET / 2.000000001;
		#endif
		float4 depth = tex2DgatherR(ReShade::DepthBuffer, texcoord) * RESHADE_DEPTH_MULTIPLIER;
		
		#if RESHADE_DEPTH_INPUT_IS_LOGARITHMIC
		const float C = 0.01;
		depth = (exp(depth * log(C + 1.0)) - 1.0) / C;
		#endif
		#if RESHADE_DEPTH_INPUT_IS_REVERSED
		depth = 1.0 - depth;
		#endif
		const float N = 1.0;
		depth /= RESHADE_DEPTH_LINEARIZATION_FAR_PLANE - depth * (RESHADE_DEPTH_LINEARIZATION_FAR_PLANE - N);
		
		return depth;
	}
	
	float Bayer(uint2 p, uint level) //Thanks Marty
	{
		//p += uint2(FRAME_COUNT, 0.2 * FRAME_COUNT);
	    p = (p ^ (p << 8u)) & 0x00ff00ffu;
	    p = (p ^ (p << 4u)) & 0x0f0f0f0fu;
		p = (p ^ (p << 2u)) & 0x33333333u;
		p = (p ^ (p << 1u)) & 0x55555555u;     
		
		uint i = (p.x ^ p.y) | (p.x << 1);     
		i = reversebits(i); 
		i >>= 32 - level * 2;  
		return float(i) / float(1 << (2 * level));
	}
	
	float2 GetNoise(int2 vpos, float z)
	{
		int size = 8;
		vpos.x = 64 * Bayer(vpos, 3u);
		vpos.x += 11 * z;
		vpos %= size*size;
		
		return float2(vpos.x / 64.0, frac(vpos.x / 1.6180339887498948482) );
	}
	
	float GRnoise2(float2 xy)
	{  
	  const float2 igr2 = float2(0.754877666, 0.56984029); 
	  xy *= igr2;
	  float n = frac(xy.x + xy.y);
	  return n;// < 0.5 ? 2.0 * n : 2.0 - 2.0 * n;
	}
	
	float GRnoise3(float2 xy)
	{  
	  const float2 igr2 = float2(0.754877666, 0.56984029); 
	  xy *= igr2;
	  float n = frac(xy.x + xy.y);
	  return n < 0.5 ? 2.0 * n : 2.0 - 2.0 * n;
	}
	
	float GTAOContrH(float a, float n)
	{
		float g = 0.25 * (-cos(2.0 * a - n) + cos(n) + 2.0 * a * sin(n) );
		//float2 g = 0.5 * (1.0 - cos(a));
		return any(isnan(g)) ? 1.0 : g.x;
	}

	float3 Albedont(float2 xy)
	{
		float3 c = GetBackBuffer(xy);
		float3 ci = c*c;
		ci = ci / dot(ci,rcp(3.0));
		
		float M0 = dot(c, rcp(3.0));
		float M1 = dot(c*c, rcp(3.0));
		
		float cl = dot(c, 0.333334);//GetLuminance(c);
		float g = abs(ddx_fine(cl)) + abs(ddy_fine(cl));
		c = c / (0.15 + cl);
		
		c *= (1.0 - sqrt(M1 - M0*M0 + 1e-3) / (M1 + M0 + 0.05));
		
		c*= c * (0.5 + 0.5 * c);
	
		return c;
		
	}

	//=======================================================================================
	//Passes
	//=======================================================================================
	
	float GenDep1PS(PS_INPUTS) : SV_Target
	{
		float4 d = GatherLinDepth(xy);
		return min(d.x, min(d.y, min(d.z, d.w)));
	}
	
	float GenDep2PS(PS_INPUTS) : SV_Target
	{
		float4 d = tex2DgatherR(sDep1, xy);
		return min(d.x, min(d.y, min(d.z, d.w)));
	}
	
	float4 GenNormalsPS(PS_INPUTS) : SV_Target
	{
		float3 vc	  = NorEyePos(xy);
		float3 vx0	  = vc - NorEyePos(xy + float2(1, 0) / RES);
		float3 vy0 	 = vc - NorEyePos(xy + float2(0, 1) / RES);
		
		float3 vx1	  = -vc + NorEyePos(xy - float2(1, 0) / RES);
		float3 vy1 	 = -vc + NorEyePos(xy - float2(0, 1) / RES);
	
		float3 vx = abs(vx0.z) < abs(vx1.z) ? vx0 : vx1;
		float3 vy = abs(vy0.z) < abs(vy1.z) ? vy0 : vy1;
		
		return float4(0.5 + 0.5 * normalize(cross(vy, vx)), 1.0);
	}
	
	float4 GenRadPS(PS_INPUTS) : SV_Target
	{
		float3 albedo = Albedont(xy);
		float3 GI = albedo * tex2D(sGI0, xy).rgb;
		float3 c = GetBackBuffer(xy);
		float3 col = c * c / (GetLuminance(c*c) + 0.001);
		
		c = IReinJ(c, HDR);
		
		return float4(GI + c, 1.0);
	}
	
	float CopyDepPS(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		if(MV_COMP) return 0.0;
		return tex2D(sDep2, xy).r;
	}
	
	float4 CopyGIPS(PS_INPUTS) : SV_Target
	{
		return tex2D(sGI0, xy);
	}
	
	//=======================================================================================
	//GI
	//=======================================================================================
	
	#define FRAME_MOD (IGNSCROLL * (FRAME_COUNT % 32 + 1))
	#define STEPS 12
	
	float4 CalcGIPS(PS_INPUTS) : SV_Target
	{
		//xy = 4.0 * floor(xy * RES * 0.33334) / RES;
		float3 surfN = 2f * tex2Dlod(sNormal, float4(xy,0,2)).xyz - 1f;
		const float lr = RAY_LENGTH * 0.0625 * 0.25 * length(RES);
		float cenD = tex2D(sDep2, xy).x;
		float3 posV  = GetEyePos(xy, cenD);//NorEyePos(xy);
		float3 vieV  = -normalize(posV);
		if(posV.z == FARPLANE) discard;	
		
		//float2 noise = GetNoise(vpos.xy, FRAME_COUNT % 1024);
		
		#define RAYS 6
		float dir = (6.28 / RAYS) * GRnoise2(vpos.yx + FRAME_MOD );
		float3 acc;
		float aoAcc;
		
		float2 minA;
		
		float attm = 1.0 + 0.05 * posV.z;
		for(int ii; ii < RAYS; ii++)
		{
			dir += 6.28 / RAYS;
			float2 vec = float2(cos(dir), sin(dir));		
			float jit = GRnoise2((FRAME_MOD + vpos.xy) % RES);
			float nMul = ii > (RAYS / 2) ? -1 : 1;
			
			float3 slcN = normalize(cross(float3( nMul * vec, 0.0f), vieV));
			float3 T = cross(vieV, slcN);
	    	float3 prjN = surfN - slcN * dot(surfN, slcN);
	    	float prjNL = length(prjN);
	   	 float N = -sign(dot(prjN, T)) * acos( dot(prjN / prjNL, vieV) );
	   	
	   	 
			vec /= normalize(RES);
			float2 maxDot = float2(sin(N) * nMul, -1.0);
			float2 maxAtt;
			
			for(int i; i < STEPS; i++) 
			{
				
				float ji = (jit + i) / (STEPS);	
				float noff = ji*ji;
				float nint = noff;//would normaly be ^2, but compensating for the agressive mipmaps
				
				float lod = floor(6.0 * ji);
				
				float2 sampXY = xy + vec * 0.5 * RAY_LENGTH * noff;
				if( any( abs(sampXY - 0.5) > 0.5 ) ) break;

				
				float  sampD = tex2Dlod(sDep2, float4(sampXY, 0, lod)).x + 0.0002;
				float3 sampN = (2f * tex2Dlod(sNormal, float4(sampXY, 0, lod + 2)).xyz - 1f);
				float3 sampL = tex2Dlod(sRadiance, float4(sampXY, 0, lod + 1)).rgb;
				
				float3 posR  = GetEyePos(sampXY, sampD);
				float3 sV = normalize(posR - posV);
				float vDot = dot(vieV, sV);
				
				float att = rcp(1.0 + 0.5 * dot(posR.z - posV.z, posR.z - posV.z) / attm);
				float att2 = rcp(1.0 + 0.1 * dot(posR - posV, posR - posV) / attm);
				
				float sh = 0.0;
				[flatten]
				if(vDot > maxDot.x) {
					maxDot.x = lerp(maxDot.x, vDot, att2 * 1.0);
				}
				
				[flatten]
				if(vDot >= maxDot.y) {
					sh = vDot - maxDot.y;//(acos(maxDot.x) - acos(vDot)) / 3.14159;
					maxDot.y = lerp(maxDot.y, vDot, 0.75 + 0.25 * att2);
					
				}
				
				float  trns  = saturate(dot(surfN, sV)) * ceil(-dot(sampN, sV));//max(CalcTransfer(posV, surfN, posR, sampN, 1.0, 0.1, 0.0), 0.0);
				//trns *= nint;
				//trns *= dot(sV, surfN) > 0.03;
				acc += sh * sampL * trns;
			}
			
			maxDot.x = acos(maxDot.x);
			maxDot.x *= -nMul.x;
			
			aoAcc += GTAOContrH(maxDot.x, N) * prjNL;
			
		}
		
		float2 MV = tex2D(MVSam0, xy).xy;
		float4 cur = float4(max(acc / RAYS, 0.0), 2.0 * aoAcc / RAYS);
		float4 pre = tex2D(sPGI, xy + MV);
		
		float DEG;

		if(MV_COMP) {
			DEG = tex2Dlod(sDOC, float4(xy,0,2) ).x;
		}
		else {
		
			float CD = GetDepth(xy);
			float PD = tex2D(sPDep, xy + MV).r;
			DEG = min(saturate(pow(abs(PD / CD), 10.0) + 0.0), saturate(pow(abs(CD / PD), 5.0) + 0.0));
		}
		
		return lerp(cur, pre, DEG * (0.8 + 0.1 * MV_COMP) );
		
	}
	
	//=======================================================================================
	//Denoising
	//=======================================================================================
	
	float4 GetSH(float3 vec)
	{
		return float4(0.282095, 0.488603f * vec.y,  0.488603f * vec.z, 0.488603f * vec.x);
	}
	#define RAD 2
	void Denoise0PS(PS_INPUTS, out float4 shLum : SV_Target0, out float4 shCol : SV_Target1)
	{
		float2 its = 6.0 * rcp(RES);
		float cenD = tex2D(sDep2, xy).x;
		float3 cenN = 2.0 * tex2Dlod(sNormal, float4(xy,0,2)).xyz - 1.0;
		float accw = 0.0;
		for(int i = -RAD; i <= RAD; i++) for(int j = -RAD; j <= RAD; j++)
		{
			float2 nxy = xy + its * float2(i,j);
			
			float4 samC = tex2Dlod(sGI0, float4(nxy,0,0));
			float3 samN = 2.0 * tex2Dlod(sNormal, float4(nxy,0,2)).xyz - 1.0;
			float samD = tex2Dlod(sDep2, float4(nxy,0,0)).x;
			
			float samL = GetLuminance(samC.rgb);
			float w = saturate(dot(cenN, samN));
			w *= w;
			w *= exp( -40.0 * abs(cenD - samD) / (cenD + 1e-7) ) + 1e-7;
			
			shLum += w * GetSH(samN) * samL;
			shCol += w * samC / float4(samL + 0.0001.xxx, 1.0);
			accw += w;
		}
		shLum /= accw;
		shCol /= accw;
	}
	
	static const int2 ioff[5] = {
				 int2( 0,-1), 
	int2(-1, 0), int2( 0, 0), int2( 1, 0), 
				 int2( 0, 1) };
	
	void Denoise1PS(PS_INPUTS, out float4 shLum : SV_Target0, out float4 shCol : SV_Target1)
	{
		float2 its = 4.0 * rcp(RES);
		float cenD = tex2D(sDep1, xy).x;
		//float3 cenN = 2.0 * tex2Dlod(sNormal, float4(xy,0,2)).xyz - 1.0;
		float2 accw = 0.0;
		for(int i = 0; i < 5; i++)//for(int i = -1; i <= 1; i++) for(int j = -1; j <= 1; j++)
		{
			float2 nxy = xy + its * ioff[i];//float2(i,j);
			float4 samSH = tex2Dlod(sSH0, float4(nxy,0,0));
			float4 samC = tex2Dlod(sCol0, float4(nxy,0,0));
			float samD = tex2Dlod(sDep2, float4(nxy,0,0)).x;
			float w = exp( -40.0 * abs(cenD - samD) / (cenD + 1e-7) ) + 1e-7;
			
			shLum += samSH * w;
			shCol += samC * w;
			accw += w;
		}
		shLum /= accw;
		shCol /= accw;
	}
	
	
	void Denoise2PS(PS_INPUTS, out float4 shLum : SV_Target0, out float4 shCol : SV_Target1)
	{
		float2 its = 2.0 * rcp(RES);
		float cenD = GetDepth(xy);
		//float3 cenN = 2.0 * tex2Dlod(sNormal, float4(xy,0,2)).xyz - 1.0;
		float2 accw = 0.0;
		for(int i = 0; i < 5; i++)
		{
			float2 nxy = xy + its * ioff[i];
			float4 samSH = tex2Dlod(sSH1, float4(nxy,0,0));
			float4 samC = tex2Dlod(sCol1, float4(nxy,0,0));
			float samD = tex2Dlod(sDep1, float4(nxy,0,0)).x;
			float w = exp( -50.0 * abs(cenD - samD) / (cenD + 1e-7) ) + 1e-7;
			
			shLum += samSH * w;
			shCol += samC * w;
			accw += w;
		}
		shLum /= accw;
		shCol /= accw;
	}
	
	//=======================================================================================
	//Blending
	//=======================================================================================
	
	float4 ClampSH(float4 sh)
	{
		sh.x += saturate(length(sh.yzw) - sh.x);
		return sh;
	}
	
	
	float3 BlendPS(PS_INPUTS) : SV_Target
	{
		float4 GI = tex2D(sGI0, xy);
		float3 normal = 2f * tex2Dlod(sNormal, float4(xy,0,0)).xyz - 1f;
		
		float4 Nbasis = GetSH(normal);
		float4 GIbasis = tex2D(sSH2, xy);
		GIbasis = ClampSH(GIbasis);
		
		float4 GICol = tex2D(sCol2, xy);
		float rad = dot(float4(3.14159, 2.59439.xxx) * GIbasis, float4(3.14159, 2.59439.xxx) * Nbasis);
		
		float3 c = IReinJ(GetBackBuffer(xy), HDR);
		float3 alb = Albedont(xy);
		if(DEBUG) {
			c = 0.05;
			alb = 1.0;
		}
		
		float lval = exp(-8.0 * (1.0-FADEOUT) * GetDepth(xy));
		GICol.a = lerp(1.0, GICol.a, lval);
		rad *= lval;
		
		float dither = (GRnoise3(vpos.xy) - 0.5) * exp2(-8);
		//return ReinJ(0.05 * GICol.a + GICol.a * GICol.rgb * rad, HDR);		
		
		float3 pfGI = tex2D(sGI0, xy).rgb;
		//return ReinJ(pfGI, HDR);
		
		float3 acc = GICol.rgb;
		
		if(!DEBUG) {
			acc.r = dot(acc.rgb, float3(0.721397,0.265387,0.013216));
			acc.g = dot(acc.rgb, float3(0.211942,0.576117,0.211942));
			acc.b = dot(acc.rgb, float3(0.013216,0.265387,0.721397));
		}
		
		return dither + ReinJ(
			lerp(1.0, GICol.a, AO_INTENSITY) * c +
			INTENSITY * alb * GICol.a * acc * rad,
		 HDR);
	
		//return pow(GICol.a, rcp(2.2));
		//return GetBackBuffer(xy);
	}
	
	technique ZenTurboGI <
		ui_label = "Zenteon: TurboGI";
		    ui_tooltip =        
		        "								  	 Zenteon - TurboGI           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nGI but fast"
		        "\n"
		        "\n=================================================================================================";
		>	
	{
		pass {	PASS1(GenDep1PS, tDep1); }
		pass {	PASS1(GenDep2PS, tDep2); }
		pass {	PASS1(GenNormalsPS, tNormal); }
		pass {	PASS1(GenRadPS, tRadiance); }
		
		pass {	PASS1(CalcGIPS, tGI0); }
		pass {	PASS2(Denoise0PS, tSH0, tCol0); }
		pass {	PASS2(Denoise1PS, tSH1, tCol1); }
		pass {	PASS2(Denoise2PS, tSH2, tCol2); }
		
		pass {	PASS1(CopyDepPS, tPDep); }
		pass {	PASS1(CopyGIPS, tPGI); }
		
		pass {	PASS0(BlendPS); }
	}
}
