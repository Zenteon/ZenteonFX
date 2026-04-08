//========================================================================
/*
	Copyright © Daniel Oren-Ibarra - 2026
	All Rights Reserved.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND
	EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
	MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
	IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
	CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
	TORT OR OTHERWISE,ARISING FROM, OUT OF OR IN CONNECTION WITH THE
	SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
	
	
	======================================================================	
	Zenteon: TurboGI - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/

#include "ReShade.fxh"
#include "ZenteonCommon.fxh"

#ifndef USE_FRAMEWORK
	//============================================================================================
		#define USE_FRAMEWORK 0
	//============================================================================================
#endif

uniform int FRAME_COUNT <	source = "framecount";>;



uniform float INTENSITY <
	ui_type = "drag";
	ui_label = "GI Intensity";
	ui_min = 0.0;
	ui_max = 5.0;
	ui_category = "\n Global \n\n";
	ui_category_closed = true;
> = 1.0;

uniform float AO_INTENSITY <
	ui_min = 0.0;
	ui_max = 1.0;
	ui_type = "drag";
	ui_label = "AO Intensity";
	ui_category = "\n Global \n\n";
	ui_category_closed = true;
> = 0.8;

uniform float RAY_LENGTH <
	ui_min = 0.5;
	ui_max = 1.0;
	ui_type = "drag";
	ui_label = "Ray Length";
	ui_category = "\n Global \n\n";
	ui_category_closed = true;
> = 1.0;

uniform float AMBIENT_LEVEL <
	ui_type = "drag";
	ui_min = 0.5;
	ui_max = 3.0;
	ui_label = "Light Level";
	ui_category = "\n Enviroment \n\n";
	ui_category_closed = true;
> = 1.0;

uniform float3 AMBIENT_COL <
	ui_min = 0.1;
	ui_max = 1.0;
	ui_type = "color";
	ui_label = "Light Color";
	ui_category = "\n Enviroment \n\n";
	ui_category_closed = true;
> = float3(0.95,0.95,1.0);

uniform float FADEOUT <
	ui_type = "drag";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_category = "\n Enviroment \n\n";
	ui_category_closed = true;
	ui_label = "Fadeout";
> = 0.6;

uniform int DEBUG <
	ui_type = "combo";
	ui_label = "Debug";
	ui_items = "None\0GI\0AO\0";
	ui_category = "\n Extra \n\n";
	ui_category_closed = true;
> = 0;

#if USE_FRAMEWORK
	#define MV_COMP 1
#else
	uniform bool MV_COMP <
		ui_label = "Zenteon: Motion Compatibility";
		ui_tooltip = "Enable ONLY IF USING Zenteon: Motion, reduces flickering almost completely.\n"
		"WILL INCRESE NOISE IF OTHER MOTION VECTORS ARE USED";
		ui_category = "\n Extra \n\n";
		ui_category_closed = true;
	> = 0;
#endif

#if !USE_FRAMEWORK
	texture texMotionVectors { DIVRES(1); Format = RG16F; };
	sampler MVSam0 { Texture = texMotionVectors; };	
	texture tDOC { DIVRES(1); Format = R8; };
	sampler sDOC { Texture = tDOC; };
#endif
namespace ZenTGI_4 {
	
	//=======================================================================================
	//Textures/Samplers
	//=======================================================================================
	
	texture tVN < source = "ZenteonBN.png"; > { Width = 512; Height = 512; Format = RGBA8; };
	sampler sVN { Texture = tVN; FILTER(POINT); WRAPMODE(WRAP); }; 
	

	texture2D tDep { DIVRES(4); Format = R16; MipLevels = 6; };
	sampler2D sDep { Texture = tDep; FILTER(POINT); };
	sampler2D sDepF { Texture = tDep; MipFilter = POINT; WRAPMODE(BORDER); };
	
	texture2D tNormal { DIVRES(1); Format = RG8; MipLevels = 8; };
	sampler2D sNormal { Texture = tNormal; FILTER(POINT); WRAPMODE(BORDER); };
	texture2D tRadiance { DIVRES(4); Format = RGBA16F; MipLevels = 7; };
	sampler2D sRadiance { Texture = tRadiance; WRAPMODE(BORDER); MipFilter = POINT; };
	
	
	texture2D tPSH { DIVRES(4); Format = RGBA16F; };
	sampler2D sPSH { Texture = tPSH; };
	texture2D tPCol { DIVRES(4); Format = RGBA16F; };
	sampler2D sPCol { Texture = tPCol; };
	
	texture2D tPDep { DIVRES(4); Format = R16; };
	sampler2D sPDep { Texture = tPDep; };
	
	texture2D tSH0 { DIVRES(4); Format = RGBA16F; };
	sampler2D sSH0 { Texture = tSH0; FILTER(POINT); };
	texture2D tCol0 { DIVRES(4); Format = RGBA16F; };
	sampler2D sCol0 { Texture = tCol0; FILTER(POINT); };
	
	texture2D tSH1 { DIVRES(4); Format = RGBA16F; };
	sampler2D sSH1 { Texture = tSH1; };
	texture2D tCol1 { DIVRES(4); Format = RGBA16F; };
	sampler2D sCol1 { Texture = tCol1; };
	
	texture2D tSHF { DIVRES(1); Format = RGBA16F; };
	sampler2D sSHF { Texture = tSHF; FILTER(POINT); };
	texture2D tColF { DIVRES(1); Format = RGBA16F; };
	sampler2D sColF { Texture = tColF; FILTER(POINT); };
	
	//=======================================================================================
	//Functions
	//=======================================================================================

	float3 OverrideVelocity(float2 uv, float cenD)
	{
		#if USE_FRAMEWORK
			return GetVelocity(uv);
		#else
			float deg;
			float2 mv = tex2Dlod(MVSam0, float4(uv,0,0)).xy;
			if(MV_COMP) {
			deg = tex2D(sDOC, uv).x;
			}
			else {
			
				float CD = cenD;
				float PD = tex2D(sPDep, uv + mv).r;
				deg = min(saturate(pow(abs(PD / CD), 10.0) + 0.0), saturate(pow(abs(CD / PD), 5.0) + 0.0));
			}
			
			return float3(mv, deg);
		#endif
	}

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
	  return n < 0.5 ? 2.0 * n : 2.0 - 2.0 * n;
	}
	
	float GRnoise3(float2 xy)
	{  
	  const float2 igr2 = float2(0.754877666, 0.56984029); 
	  xy *= igr2;
	  float n = frac(xy.x + xy.y);
	  return n < 0.5 ? 2.0 * n : 2.0 - 2.0 * n;
	}
	
	float BrdfSH(float4 sh, float3 normal)
	{
	    if(sh.x < 1e-10) return sh.x;
	    float t = dot(normalize(sh.yzw), normal.yzx);
	    
	    float tl = saturate(length(sh.yzw) / (1.73205081 * sh.x));
	    
	    float l0 = lerp(0.25 + 0.25 * t, max(t, 0.0), 2.0 * clamp(tl-0.5, 0.0, 0.5));
	    float l1 = lerp(0.0,   0.25 - 0.25 * t,       2.0 * clamp(0.5-tl, 0.0, 0.5));
	    
	    l0 *= l0;
	    l1 *= l1;
	    
	    return max(sh.x * 3.54490509 * (l0 + l1), 0.0);
	}
	
	float3 NormalOverride(float2 uv, float mip)
	{
		return NormalDecode(tex2Dlod(sNormal, float4(uv,0,mip)).xy);
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
	
	float4 GetSH(float3 vec)
	{
		return float4(0.282095, 0.488603f * vec.y,  0.488603f * vec.z, 0.488603f * vec.x);
	}

	float2 RGBtoCoCg(float3 c)
	{
		float Co =  0.5*c.r - 0.5*c.b;
		float Cg = -0.25*c.r + 0.5*c.g - 0.25*c.b;
		return float2(Co,Cg);
	}

	float3 CoCgtoRGB(float2 x)
	{
		float tmp = 1.0 - 0.5 * x.y;
		float G   = x.y + tmp;
		float B   = tmp - 0.5 * x.x;
		float R   = B + x.x;
		return float3(R,G,B);
	}

	float3 CoCgtoRGB(float2 cocg, float Y)
	{
	    float Co = cocg.x;
	    float Cg = cocg.y;
	
	    float R = Y + Co - 0.5 * Cg;
	    float G = Y + Cg;
	    float B = Y - Co - 0.5 * Cg;
	    return float3(R, G, B);
}

	//=======================================================================================
	//Passes
	//=======================================================================================
	
	float MinMaxC(float4 a, bool doMin)
	{
		return doMin ? min( min(a.x, a.y), min(a.z,a.w) ) :
			   		max( max(a.y, a.y), max(a.z,a.w) );
	}
	
	
	uint UnrollPos(uint2 pos)
	{
		return pos.x + 4 * pos.y;
	}
	
	groupshared float sharedDepth[4];
	//[shader("compute")]
	float DepDS_SP(PS_INPUTS) : SV_Target//CS_INPUTS)
	{
		uint2 id = floor(vpos.xy);
		float2 uv = 4.0 * id.xy / RES;//floored uv, apply offsets later
		
		bool doMin = ((id.x + id.y) % 2) == 0;
		
		float4 A = GatherLinDepth(uv);
		float4 B = GatherLinDepth(uv + float2(0.0, 2.0) / RES);
		float4 C = GatherLinDepth(uv + float2(2.0, 0.0) / RES);
		float4 D = GatherLinDepth(uv + float2(2.0, 2.0) / RES);
		
		float4 E = float4(MinMaxC(A, doMin), MinMaxC(B, doMin), MinMaxC(C, doMin), MinMaxC(D, doMin));
		return MinMaxC(E, doMin);
	}
	
	float2 GenNormalsPS(PS_INPUTS) : SV_Target
	{
		float3 vc	  = NorEyePos(xy);
		float3 vx0	  = vc - NorEyePos(xy + float2(1, 0) / RES);
		float3 vy0 	 = vc - NorEyePos(xy + float2(0, 1) / RES);
		
		float3 vx1	  = -vc + NorEyePos(xy - float2(1, 0) / RES);
		float3 vy1 	 = -vc + NorEyePos(xy - float2(0, 1) / RES);
	
		float3 vx = abs(vx0.z) < abs(vx1.z) ? vx0 : vx1;
		float3 vy = abs(vy0.z) < abs(vy1.z) ? vy0 : vy1;
		
		return NormalEncode(normalize(cross(vy, vx)));
	}
	
	float4 GenRadPS(PS_INPUTS) : SV_Target
	{
		float3 albedo = Albedont(xy);
		float3 c = GetBackBuffer(xy);
	
		c = IReinJ(c, 1.1, 0, 0);
		
		float2 mv = OverrideVelocity(xy, 1.0).xy;
		float4 GIBasis = tex2D(sSHF, xy + mv);
		float3 GICol = tex2D(sColF, xy + mv).rgb;
		float3 N = NormalOverride(xy, 0.0);
		float3 GI = GICol * BrdfSH(GIBasis, N);
		
		c += 3.0 * GI * albedo;
		c *= exp(-GetDepth(xy) / (0.001 + FADEOUT * FADEOUT));
		
		return float4(c, 1.0);
	}
	
	float CopyDepPS(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		//if(MV_COMP) return 0.0;
		return tex2D(sDep, xy).r;
	}
	
	void CopyGIPS(PS_INPUTS, out float4 sh : SV_Target0, out float4 col : SV_Target1)
	{
		sh = tex2D(sSH1, xy);
		col = tex2D(sCol1, xy);
	}
	
	//=======================================================================================
	//GI
	//=======================================================================================
	
	#define FRAME_MOD (32.0*IGNSCROLL * (FRAME_COUNT % 64 + 1))
	#define RAYS 7
	#define STEPS 12
	
	void CalcGIPS(PS_INPUTS, out float4 sh : SV_Target0, out float4 col : SV_Target1)
	{
		//xy = 4.0 * floor(xy * RES * 0.33334) / RES;
		float3 surfN = NormalOverride(xy, 2.0);//GetNormal(xy);//
		const float lr = RAY_LENGTH;// * length(RES);///0.0625 * 0.25 * 
		float cenD = tex2D(sDep, xy).x;//
		if(cenD == 1.0) discard;
		
		float3 posV  = GetEyePos(xy, cenD);//NorEyePos(xy);
		float3 vieV  = -normalize(posV);
		if(posV.z == FARPLANE) discard;	
		
		//float2 noise = GetNoise(vpos.xy, FRAME_COUNT % 1024);
		
		
		float dir = (6.28 / RAYS) * GRnoise2(vpos.yx + FRAME_MOD );
		float3 colAcc;
		float4 sh1Acc;
		float  aoAcc;
		
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
				
				float lod = max(log2(noff * RES.y + 1.0) - 3.0, 0.0);//floor(6.0 * ji);
				
				float2 sampXY = xy + vec * 0.5 * RAY_LENGTH * noff;
				if( any( abs(sampXY - 0.5) > 0.5 ) ) break;


				float nlod = max(lod - 2.0,0.0);
				
				float  sampD = tex2Dlod(sDep, float4(sampXY, 0, nlod)).x + 0.0002;
				float3 sampN = NormalOverride(sampXY, nlod + 2.0);
				float3 sampL = tex2Dlod(sRadiance, float4(sampXY, 0, lod)).rgb;
				
				float3 posR  = GetEyePos(sampXY, sampD);
				float3 sV = normalize(posR - posV);
				float vDot = dot(vieV, sV);
				float att2 = rcp(1.0 + 0.05 * dot(posR - posV, posR - posV) / attm);
				
				float tOcc = 0.0;
				[flatten]
				if(vDot > maxDot.x) {
					maxDot.x = lerp(maxDot.x, vDot, att2);
				}
				
				[flatten]
				if(vDot >= maxDot.y) {
					tOcc = vDot - maxDot.y;
					maxDot.y = lerp(maxDot.y, vDot, 0.75 + 0.25 * att2);
					
				}
				
				float  trns  = tOcc * saturate(dot(surfN, sV)) * ceil(-dot(sampN, sV));
				
				float l = dot(sampL, float3(0.2126,0.7152,0.0722));
				
				sh1Acc += trns * l * GetSH(sV);
				colAcc += trns * sampL;
			}
			valid = max(maxDot.x != sin(N) * nMul,valid);
			maxDot.x = acos(maxDot.x);
			maxDot.x *= -nMul.x;
			
			aoAcc += GTAOContrH(maxDot.x, N) * prjNL;
			
		}
		
		aoAcc /= 0.5 * RAYS;
		sh = sh1Acc / RAYS;
		
		
	    colAcc = max(colAcc, 1e-6);
	    //This is hilariously weird, not the best choice
		col = float4(aoAcc, NormalEncode(colAcc), sh.x*sh.x);
		
		float3 MV = OverrideVelocity(xy, cenD);
		
		float4 shPre = tex2D(sPSH, xy + MV.xy);
		float4 colPre = tex2D(sPCol, xy + MV.xy);
		
		float lv =  MV.z * (0.8 + 0.1 * MV_COMP);
		sh = lerp(sh, shPre,lv);
		col = lerp(col, colPre, lv);
		col.a += 2.0 * (1.0 - MV.z);//increase variance in dissoclusions
	}
	
	//=======================================================================================
	//Denoising
	//=======================================================================================
	
	//e^-x
	float fastExpN(float x)
	{
		return rcp( x + (x*x + 1.0));
	}
	
	#define RAD 2
	void Denoise0PS(PS_INPUTS, out float4 shLum : SV_Target0, out float4 shCol : SV_Target1)
	{
		float M = tex2Dlod(sSH1, float4(xy,0,0)).x;
		float M2 = tex2Dlod(sCol1, float4(xy,0,0)).w;
		float std = sqrt(abs(M-M2));
	
		float2 its = 8.0 * rcp(RES);
		float cenD = tex2D(sDep, xy).x;
		if(cenD == 1.0) discard;
		float3 cenN = NormalOverride(xy, 2.0);
		float accw = 0.0;
		
		for(int i = -RAD; i <= RAD; i++) for(int j = -RAD; j <= RAD; j++)
		{
			float2 nxy = xy + its * float2(i,j);
			float4 samSH = tex2Dlod(sSH1, float4(nxy,0,0));
			float4 samC = tex2Dlod(sCol1, float4(nxy,0,0));
			float samD = tex2Dlod(sDep, float4(nxy,0,0)).x;
			float3 samN = NormalOverride(nxy, 2.0);
			float w = fastExpN( 100.0 * abs(cenD - samD) / (cenD + 0.0001) );
			w *= pow(saturate(dot(samN, cenN)), 4.0);
			
			//w *= fastExpN( 4.0 * abs(samSH.x - M) / (std + 0.1) );
			
			shLum += samSH * w;
			shCol += float4(samC.rgb, abs(samSH.x - samC.w)) * w;//variance in alpha
			accw += w;

		}
		shLum /= accw;
		shCol /= accw;
	}
	
	static const int2 ioff[5] = {
				 int2( 0, 0), 
	int2(-1, 0), int2( 0,-1), int2( 1, 0), 
				 int2( 0, 1) };
	
	void Denoise1PS(PS_INPUTS, out float4 shLum : SV_Target0, out float4 shCol : SV_Target1)
	{
		float2 its = 4.0 * rcp(RES);
		float cenD = tex2D(sDep, xy).x;
		if(cenD == 1.0) discard;
		//float3 cenN = 2.0 * tex2Dlod(sNormal, float4(xy,0,2)).xyz - 1.0;
		float2 accw = 0.0;
		for(int i = 0; i < 5; i++)//for(int i = -1; i <= 1; i++) for(int j = -1; j <= 1; j++)
		{
			float2 nxy = xy + its * ioff[i];//float2(i,j);
			float4 samSH = tex2Dlod(sSH0, float4(nxy,0,0));
			float4 samC = tex2Dlod(sCol0, float4(nxy,0,0));
			float samD = tex2Dlod(sDep, float4(nxy,0,0)).x;
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
		float2 its = 4.0 * rcp(RES);
		float cenD = GetDepth(xy);
		if(cenD == 1.0)
		{
			shLum = 0.0;
			shCol = 1.0;
		}
		else
		{
			float2 accw = 0.0;
			for(int i = 0; i < 5; i++)
			{
				float2 nxy = xy + its * ioff[i];
				float4 samSH = tex2Dlod(sSH1, float4(nxy,0,0));
				float4 samC = tex2Dlod(sCol1, float4(nxy,0,0));
				float samD = tex2Dlod(sDepF, float4(nxy,0,0)).x;
				
				
				float w = fastExpN( 1000.0 * abs(cenD - samD) / (cenD + 0.0001) );
				
				shLum += samSH * w;
				shCol += samC * w;
				accw += w;
				
				if(abs(samD - cenD) <= 0.015 * cenD) break;
			}
			shLum /= accw;
			shCol /= accw;
		}
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
		#if USE_FRAMEWORK 
			float3 normal = GetNormal(xy);
		#else
			float3 normal = NormalOverride(xy, 0.0);
		#endif
		
		float4 GIbasis = tex2D(sSHF, xy );
		float3 GICol = tex2D(sColF, xy ).rgb;
		float  AO	= GICol.x;
		
		GICol.rgb = NormalDecode(GICol.yz);
	
		
		if(!DEBUG)
		{
			GICol.r = dot(GICol.rgb, float3(0.721397,0.265387,0.013216));
			GICol.g = dot(GICol.rgb, float3(0.211942,0.576117,0.211942));
			GICol.b = dot(GICol.rgb, float3(0.013216,0.265387,0.721397));
		}
		
		GICol /= AO;
		float3 GI = 2.0 * 3.14159 * GICol * BrdfSH(GIbasis, normal);
		
		float3 c = GetBackBuffer(xy);
		c = IReinJ(c, HDR);
		
			
		float F = exp(-GetDepth(xy) / (0.001 + FADEOUT * FADEOUT));
		GI *= F;
		AO = lerp(1.0, AO, F);
		
		float3 alb = Albedont(xy);
		if(DEBUG == 1) {
			c = 0.00;
			alb = 1.0;
		}
		if(DEBUG == 2) {
			return AO;
		}
		
		float3 ambient = 0.5 + 0.5 * AMBIENT_COL*AMBIENT_COL;
		c *= AMBIENT_LEVEL * (ambient / GetLuminance(ambient)) / (1.0 + 0.01 * AMBIENT_LEVEL * c);
		
		return ReinJ(
			lerp(1.0, AO, AO_INTENSITY) * c +
			INTENSITY * alb * AO * GI,
		 HDR);
	}
	
	technique ZenTurboGI <
		ui_label = "Zenteon: TurboGI";
		    ui_tooltip =        
		        "								  	 Zenteon - TurboGI           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nGlobal illumination, but turbo, speedy even"
		        "\n"
		        "\n=================================================================================================";
		>	
	{
		pass {	PASS1(DepDS_SP, tDep); }
		
		pass {	PASS1(GenNormalsPS, tNormal); }
		pass {	PASS1(GenRadPS, tRadiance); }
		
		pass {	PASS2(CalcGIPS,   tSH1, tCol1); }
		
		//copy unfiltered GI
		pass {	PASS2(CopyGIPS, tPSH, tPCol); }
		pass {	PASS1(CopyDepPS, tPDep); }
		
		pass {	PASS2(Denoise0PS, tSH0, tCol0); }
		pass {	PASS2(Denoise1PS, tSH1, tCol1); }
		pass {	PASS2(Denoise2PS, tSHF, tColF); }
		
		
		
		
		pass {	PASS0(BlendPS); }
	}
}
