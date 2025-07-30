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
	Zenteon: TurboGI v0.1 - Authored by Daniel Oren-Ibarra
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/

#include "ReShade.fxh"
#include "ZenteonCommon.fxh"

uniform int FRAME_COUNT <	source = "framecount";>;

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
> = 0.5;

uniform float FADEOUT <
	ui_type = "drag";
	ui_label = "Fadeout";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.5;

uniform int DEBUG <
	ui_type = "combo";
	ui_items = "None\0GI\0";
> = 0;


uniform bool MV_COMP <
	ui_label = "Zenteon: Motion Compatibility";
	ui_tooltip = "Enable ONLY IF USING Zenteon: Motion, reduces flickering almost completely.\n"
	"WILL INCRESE NOISE IF OTHER MOTION VECTORS ARE USED";
> = 0;

texture texMotionVectors { DIVRES(1); Format = RG16F; };
sampler MVSam0 { Texture = texMotionVectors; };	
texture tDOC { DIVRES(1); Format = R8; };
sampler sDOC { Texture = tDOC; };

namespace ZenTGI_Temp2 {
	
	//=======================================================================================
	//Textures/Samplers
	//=======================================================================================
	
	texture tVN < source = "ZenteonBN.png"; > { Width = 512; Height = 512; Format = RGBA8; };
	sampler sVN { Texture = tVN; FILTER(POINT); WRAPMODE(WRAP); }; 
	
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
		#else
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
	
	
	float GRnoise2(float2 xy)
	{  
	  const float2 igr2 = float2(0.754877666, 0.56984029); 
	  xy *= igr2;
	  float n = frac(xy.x + xy.y);
	  //return tex2Dfetch(sVN, xy % 512).x;
	  return n < 0.5 ? 2.0 * n : 2.0 - 2.0 * n;
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
		float cl = dot(c, 0.333334);//GetLuminance(c);
		float g = abs(ddx_fine(cl)) + abs(ddy_fine(cl));
		c = 0.95 * c / (0.1 + cl);
		c*=c;
	
		return lerp(c*cl, cl, 0.0);
		
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
		float3 GI = 0.5 * albedo * tex2D(sGI0, xy).rgb;
		float3 c = GetBackBuffer(xy);
		float3 col = c * c / (GetLuminance(c*c) + 0.001);
		
		c = lerp(IReinJ(c, HDR), max(-c / (c - 1.05), 0.0), 0.0);
		
		return float4(GI + c, 1.0);
	}
	
	float CopyDepPS(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		return tex2D(sDep2, xy).r;
	}
	
	float4 CopyGIPS(PS_INPUTS) : SV_Target
	{
		return tex2D(sGI0, xy);
	}
	
	//=======================================================================================
	//GI
	//=======================================================================================
	
	#define FRAME_MOD (32.0*IGNSCROLL * (FRAME_COUNT % 64 + 1))
	#define STEPS 12
	
	float4 CalcGIPS(PS_INPUTS) : SV_Target
	{
		//xy = 4.0 * floor(xy * RES * 0.33334) / RES;
		float3 surfN = 2f * tex2Dlod(sNormal, float4(xy,0,2)).xyz - 1f;//GetNormal(xy);//
		const float lr = RAY_LENGTH;// * length(RES);///0.0625 * 0.25 * 
		float cenD = tex2D(sDep2, xy).x;//
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
		float valid = 0.0;
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
			float2 maxDot = sin(N) * nMul;
			float2 maxAtt;
			
			for(int i; i < STEPS; i++) 
			{
				
				float ji = (jit + i) / (STEPS);	
				float noff = ji*ji;
				float nint = noff;//would normaly be ^2, but compensating for the agressive mipmaps
				
				float lod = floor(7.0 * ji);
				
				float2 sampXY = xy + vec * RAY_LENGTH * noff;
				if( any( abs(sampXY - 0.5) > 0.5 ) ) break;

				//GetDepth(sampXY);//
				float  sampD = tex2Dlod(sDep2, float4(sampXY, 0, lod + 0)).x + 0.0002;
				float3 sampN = (2f * tex2Dlod(sNormal, float4(sampXY, 0, lod + 2)).xyz - 1f);
				float3 sampL = tex2Dlod(sRadiance, float4(sampXY, 0, lod + 1)).rgb;
				
				float3 posR  = GetEyePos(sampXY, sampD);
				float3 sV = normalize(posR - posV);
				float vDot = dot(vieV, sV);
				
				float att = rcp(1.0 + 0.1 * dot(posR.z - posV.z, posR.z - posV.z) / attm);
				float att2 = rcp(1.0 + 0.05 * dot(posR - posV, posR - posV) / attm);
				
				float sh = 0.0;
				[flatten]
				if(vDot > maxDot.x) {
					maxDot.x = lerp(maxDot.x, vDot, att2 * 0.7);
				}
				
				[flatten]
				if(vDot >= maxDot.y) {
					sh = saturate(vDot-maxDot.y);
					maxDot.y = lerp(maxDot.y, vDot, 0.7 * att);
					//acos(maxDot.y) - acos(vDot);
				}
				
				float  trns  = CalcTransfer(posV, surfN, posR, sampN, 1.0, 0.000001, 0.0);
				trns /= abs(dot(sampN, normalize(posR) )) + 0.0001;
				trns *= 9.0 * noff*noff;
				acc += sh * sampL * trns;
			}
			valid = max(maxDot.x != sin(N) * nMul,valid);
			maxDot.x = acos(maxDot.x);
			maxDot.x *= -nMul.x;
			
			aoAcc += GTAOContrH(maxDot.x, N) * prjNL;
			
		}
		
		float2 MV = tex2D(MVSam0, xy).xy;
		float4 cur = float4(max(RAY_LENGTH * RAY_LENGTH * acc / (RAYS), 0.0), 2.0 * aoAcc / RAYS);
		float4 pre = tex2D(sPGI, xy + MV);
		
		float DEG;

		if(MV_COMP) {
			DEG = tex2D(sDOC, xy).x;
		}
		else {
		
			float CD = cenD;
			float PD = tex2D(sPDep, xy + MV).r;
			DEG = min(saturate(pow(abs(PD / CD), 10.0) + 0.0), saturate(pow(abs(CD / PD), 5.0) + 0.0));
		}
		//float4(ReinJ(cur.rgb, HDR), 1.0);//
		return lerp(cur, pre, DEG * (0.8 + 0.1 * MV_COMP) );
		
	}
	
	//=======================================================================================
	//Denoising
	//=======================================================================================
	
	float4 GetSH(float3 vec)
	{
		return float4(0.282095, 0.488603f * vec.y,  0.488603f * vec.z, 0.488603f * vec.x);
	}
	//e^-x
	float fastExpN(float x)
	{
		return rcp( x + (x*x + 1.0)) + exp2(-32);
	}
	
	#define RAD 2
	void Denoise0PS(PS_INPUTS, out float4 shLum : SV_Target0, out float4 shCol : SV_Target1)
	{
		float2 its = 4.0 * rcp(RES);
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
			w *= fastExpN( 50.0 * abs(cenD - samD) / (cenD + 0.001) );
			
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
		float2 accw = 0.0;
		for(int i = 0; i < 5; i++)
		{
			float2 nxy = xy + its * ioff[i];//float2(i,j);
			float4 samSH = tex2Dlod(sSH0, float4(nxy,0,0));
			float4 samC = tex2Dlod(sCol0, float4(nxy,0,0));
			float samD = tex2Dlod(sDep2, float4(nxy,0,0)).x;
			float w = fastExpN( 100.0 * abs(cenD - samD) / (cenD + 0.0001) );
			
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
		float2 accw = 0.0;
		for(int i = 0; i < 5; i++)
		{
			float2 nxy = xy + its * ioff[i];
			float4 samSH = tex2Dlod(sSH1, float4(nxy,0,0));
			float4 samC = tex2Dlod(sCol1, float4(nxy,0,0));
			float samD = tex2Dlod(sDep1, float4(nxy,0,0)).x;
			float w = fastExpN( 100.0 * abs(cenD - samD) / (cenD + 0.0001) );
			
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
	
	
	float CalcFog(float d, float den)
	{
		float2 se = float2(0.0, 0.001 + 0.999 * FADEOUT);
		se.y = max(se.y, se.x + 0.001);
		d = saturate(1.0 / (se.y) * d - se.x);
		float f = 1.0 - 1.0 / exp(pow(d * den, 2.0));
		
		return saturate(f);
	}
	
	float3 BlendPS(PS_INPUTS) : SV_Target
	{
		float4 GI = tex2D(sGI0, xy);
		float3 normal = 2f * tex2Dlod(sNormal, float4(xy,0,0)).xyz - 1f;
		
		float4 Nbasis = GetSH(normal);
		float4 GIbasis = tex2D(sSH2, xy );
		//GIbasis = ClampSH(GIbasis);
		
		float4 GICol = tex2D(sCol2, xy );
		float rad = dot(float4(3.14159, 2.59439.xxx) * GIbasis, float4(3.14159, 2.59439.xxx) * Nbasis);
		rad = max(rad, 0.0);
		
		float3 c = IReinJ(GetBackBuffer(xy), HDR);
		float3 alb = Albedont(xy);
		if(DEBUG) {
			c = 0.02;
			alb = 1.0;
		}
		float dither = (GRnoise3(vpos.xy) - 0.5) * exp2(-8);	
		return dither + ReinJ(
			lerp(c, 
			lerp(1.0, GICol.a, AO_INTENSITY) * c + INTENSITY * alb * GICol.a * GICol.rgb * rad, 1.0 - CalcFog(GetDepth(xy), 2.0) ),
		 HDR);
		 
	}
	
	technique ZenTurboGI <
		ui_label = "Zenteon: TurboGI 3";
		    ui_tooltip =        
		        "								  	 Zenteon - TurboGI           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nA very fast global illumination shader targeting older mobile GPUs"
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
