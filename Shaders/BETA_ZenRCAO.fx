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
	Zenteon: RCAO BETA - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/


#define NRES (512 * int2(DIV_RND_UP(RES.x, 512), DIV_RND_UP(RES.y, 1024)))
//(512 * int2(DIV_RND_UP(RES.x, 512), DIV_RND_UP(RES.y, 512)))
//float2(2048,1024)
	
#include "ReShade.fxh"
#include "ZenteonCommon.fxh"

uniform int FRAME_COUNT <
	source = "framecount";>;

uniform float C0_M <
	ui_type = "slider";
	ui_label = "C0 Multiplier";
	ui_min = 0.1;
	ui_max = 20.0;
	hidden = 1;
> = 1.0;

uniform float INTENSITY <
	ui_type = "drag";
	ui_label = "Intensity";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.8;

uniform float FADEOUT <
	ui_type = "drag";
	ui_label = "Fadeout\n\n";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.8;

uniform float THICKNESS <
	ui_type = "drag";
	ui_label = "Z thickness";
	ui_min = 0.1;
	ui_max = 10.0;
	hidden = 1;
> = 0.5;

uniform float THICK_SCALE <
	ui_type = "drag";
	ui_label = "Thickness Z Scale";
	ui_min = 0.1;
	ui_max = 1.0;
	hidden = 1;
> = 0.25;
	
uniform bool SHOW_WEIGHTS <
	ui_label = "Debug";
> = 0;
//assumes 8 dirs for cascade 0
#define PRES(RDIV) Width = NRES.x; Height = DIV_RND_UP(NRES.y, RDIV)

#define C_FILTER LINEAR


namespace ZenAO {
	
	//=======================================================================================
	//Textures/Samplers
	//=======================================================================================
	
	texture2D tAOMin0 { PRES(4); Format = RGBA8; };
	sampler2D sAOMin0 { Texture = tAOMin0; FILTER(C_FILTER); };
	texture2D tAOMax0 { PRES(4); Format = RGBA8; };
	sampler2D sAOMax0 { Texture = tAOMax0; FILTER(C_FILTER); };
	
	texture2D tAOMin1 { PRES(8); Format = RGBA8; };
	sampler2D sAOMin1 { Texture = tAOMin1; FILTER(C_FILTER); };
	texture2D tAOMax1 { PRES(8); Format = RGBA8; };
	sampler2D sAOMax1 { Texture = tAOMax1; FILTER(C_FILTER); };
	
	texture2D tAOMin2 { PRES(16); Format = RGBA8; };
	sampler2D sAOMin2 { Texture = tAOMin2; FILTER(C_FILTER); };
	texture2D tAOMax2 { PRES(16); Format = RGBA8; };
	sampler2D sAOMax2 { Texture = tAOMax2; FILTER(C_FILTER); };
	
	texture2D tAOMin3 { PRES(32); Format = RGBA8; };
	sampler2D sAOMin3 { Texture = tAOMin3; FILTER(C_FILTER); };
	texture2D tAOMax3 { PRES(32); Format = RGBA8; };
	sampler2D sAOMax3 { Texture = tAOMax3; FILTER(C_FILTER); };
	
	texture2D tAOMin4 { PRES(64); Format = RGBA8; };
	sampler2D sAOMin4 { Texture = tAOMin4; FILTER(C_FILTER); };
	texture2D tAOMax4 { PRES(64); Format = RGBA8; };
	sampler2D sAOMax4 { Texture = tAOMax4; FILTER(C_FILTER); };
	
	texture2D tAOMin5 { PRES(128); Format = RGBA8; };
	sampler2D sAOMin5 { Texture = tAOMin5; FILTER(C_FILTER); };
	texture2D tAOMax5 { PRES(128); Format = RGBA8; };
	sampler2D sAOMax5 { Texture = tAOMax5; FILTER(C_FILTER); };
	
	texture2D tHIZ0 { DIVRES_N(1, NRES); Format = RG16; };
	sampler2D sHIZ0 { Texture = tHIZ0; };
	
	texture2D tHIZ1 { DIVRES_N(2, NRES); Format = RG16; };
	sampler2D sHIZ1 { Texture = tHIZ1; };
	
	texture2D tHIZ2 { DIVRES_N(4, NRES); Format = RG16; };
	sampler2D sHIZ2 { Texture = tHIZ2; };
	
	texture2D tHIZ3 { DIVRES_N(8, NRES); Format = RG16; };
	sampler2D sHIZ3 { Texture = tHIZ3; };
	
	texture2D tHIZ4 { DIVRES_N(16, NRES); Format = RG16; };
	sampler2D sHIZ4 { Texture = tHIZ4; };
	
	texture2D tHIZ5 { DIVRES_N(32, NRES); Format = RG16; };
	sampler2D sHIZ5 { Texture = tHIZ5; };
	
	texture2D tHIZ6 { DIVRES_N(64, NRES); Format = RG16; };
	sampler2D sHIZ6 { Texture = tHIZ6; };
	
	texture2D tHIZ7 { DIVRES_N(128, NRES); Format = RG16; };
	sampler2D sHIZ7 { Texture = tHIZ7; };
	
	//=======================================================================================
	//Functions
	//=======================================================================================
	
	float4 tex2DBicubic(sampler2D tex, float2 xy)
	{
		float mip = 0.0;
	    float2 ta = tex2Dsize(tex, mip);
	    float2 its = rcp(ta);
	
	    float2 tc = xy * ta - 0.5;
	    float2 f = frac(tc);
	    tc -= f;
	
	    float2 f2 = f * f;
	    float2 f3 = f2 * f;
	
	    float4 nx = float4(1.0, 2.0, 3.0, 4.0) - f.x;
	    float4 sx = nx * nx * nx;
	    float x1 = sx.y - 4.0 * sx.x;
	    float x2 = sx.z - 4.0 * sx.y + 6.0 * sx.x;
	    float4 wx = float4(sx.x, x1, x2, 6.0 - sx.x - x1 - x2) * (1.0 / 6.0);
	
	    float4 ny = float4(1.0, 2.0, 3.0, 4.0) - f.y;
	    float4 sy = ny * ny * ny;
	    float y1 = sy.y - 4.0 * sy.x;
	    float y2 = sy.z - 4.0 * sy.y + 6.0 * sy.x;
	    float4 wy = float4(sy.x, y1, y2, 6.0 - sy.x - y1 - y2) * (1.0 / 6.0);
	
	    float4 c = tc.xxyy + float4(-0.5, 1.5, -0.5, 1.5);
	
	    float2 sX = wx.xz + wx.yw;
	    float2 sY = wy.xz + wy.yw;
	
	    float2 oX = c.xy + (wx.yw / sX);
	    float2 oY = c.zw + (wy.yw / sY);
	
	    float2 xy0 = float2(oX.x, oY.x) * its	;
	    float2 xy1 = float2(oX.y, oY.x) * its;
	    float2 xy2 = float2(oX.x, oY.y) * its;
	    float2 xy3 = float2(oX.y, oY.y) * its;
	
	    float4 s0 = tex2Dlod(tex, float4(xy0, 0, mip));
	    float4 s1 = tex2Dlod(tex, float4(xy1, 0, mip));
	    float4 s2 = tex2Dlod(tex, float4(xy2, 0, mip));
	    float4 s3 = tex2Dlod(tex, float4(xy3, 0, mip));

	    float fx = sX.x / (sX.x + sX.y);
	    float fy = sY.x / (sY.x + sY.y);
	
	    return lerp(lerp(s3, s2, fx), lerp(s1, s0, fx), fy);
	}
	
	float4 tex2DfetchLin(sampler2D tex, float2 vpos)
	{
		float2 s = tex2Dsize(tex);
		return tex2Dlod(tex, float4(vpos / s, 0, 0));
	}
	
	float4 tex2DfetchBic(sampler2D tex, float2 vpos)
	{
		float2 s = tex2Dsize(tex);
		return tex2DBicubic(tex, vpos / s);//tex2D(tex, vpos / s);
	}
	
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
	
	float2 GetNoise(int2 vpos, float z)
	{
		int size = 8;
		vpos.x = 64 * Bayer(vpos, 3u);
		vpos.x += 17 * z;
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
	
	//=======================================================================================
	//Dep
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
	

	
	float2 minax(float2 a, float2 b)
	{
		return float2( min(a.x,b.x), max(a.y,b.y) ); 
	}
	
	
	bool2 is2(float2 dim) {;
		float2 lv = 0.5 * dim;
		return frac(lv) < 0.01;
	}
	/*
	float2 HiZL(sampler2D texD, float2 pos, float level)
	{
		float2 ts = tex2Dsize(texD);
		bool2 es = 0;//is2(ts);
		float2 d = float2(1.0,0.0);
		float2 its = rcp(ts);
		pos = floor(2.0*pos) - 1.0;
		
		d = minax(d, tex2Dfetch(texD, pos + float2( 0, 0) ).xy );
		d = minax(d, tex2Dfetch(texD, pos + float2( 0, 1)  ).xy );
		d = minax(d, tex2Dfetch(texD, pos + float2( 1, 0)  ).xy );
		d = minax(d, tex2Dfetch(texD, pos + float2( 1, 1)  ).xy );
		
		if(es.x) {
			//d = minax(d, tex2Dfetch(texD, pos + float2( -1, 0) ).xy );
			//d = minax(d, tex2Dfetch(texD, pos + float2( -1, 1) ).xy );
			d = minax(d, tex2Dfetch(texD, pos + float2( 2, 0) ).xy );
			d = minax(d, tex2Dfetch(texD, pos + float2( 2, 1) ).xy );
		}		
		if(es.y) {
			//d = minax(d, tex2Dfetch(texD, pos + float2( 0, -1) ).xy );
			//d = minax(d, tex2Dfetch(texD, pos + float2( 1, -1) ).xy );
			d = minax(d, tex2Dfetch(texD, pos + float2( 0, 2) ).xy );
			d = minax(d, tex2Dfetch(texD, pos + float2( 1, 2) ).xy );
		}		
		if(es.x && es.y) {
			//d = minax(d, tex2Dfetch(texD, pos + float2( -1, -1) ).xy );
			d = minax(d, tex2Dfetch(texD, pos + float2( 2, 2) ).xy );
		}
		
		return d;
	}
	*/
	
	
	float2 HiZL(sampler2D texD, float2 pos, float level)
	{
	    float2 ts = tex2Dsize(texD);         
	    float2 d = float2(1.0, 0.0);          
	    float2 base = 2.0 * pos - 1.0;
	
	    #define C(c) clamp(c, 0.0, ts - 1.0)

	    d = minax(d, tex2Dfetch(texD, C(base + float2(0, 0))).xy);
	    d = minax(d, tex2Dfetch(texD, C(base + float2(1, 0))).xy);
	    d = minax(d, tex2Dfetch(texD, C(base + float2(0, 1))).xy);
	    d = minax(d, tex2Dfetch(texD, C(base + float2(1, 1))).xy);
	
	    return d;
	}
	
	
	float2 HZ0PS(PS_INPUTS) : SV_Target
	{
		float4 d = GatherLinDepth(xy);
		//min in max handles holes in depth buffer at the cost of some fullres artifacting
		
		float a = GetDepth(xy);
		float b = GetDepth( (floor(xy*RES) + float2(0.5,1.5) ) / RES );
		//min( min(d.x,d.y), min(d.z,d.w) );//
		return min( min(d.x,d.y), min(d.z,d.w) );//;//min( min(d.x,d.y), min(d.z,d.w) );//;//float2(min(d.x, min(d.y, min(d.z, d.w))),  max(d.x, max(d.y, min(d.z, d.w))) );
	}
	
	
	float2 HZ1PS(PS_INPUTS) : SV_Target
	{
		float4 d = GatherLinDepth(xy);
		return HiZL(sHIZ0, vpos.xy,0.0);//float2( min(d.x, min(d.y, min(d.z, d.w))),  max(d.x, max(d.y, min(d.z, d.w))) );
	}
	
	float2 HZ2PS(PS_INPUTS) : SV_Target
	{
		return HiZL(sHIZ1, vpos.xy, 1.0);
	}
		
	float2 HZ3PS(PS_INPUTS) : SV_Target
	{
		return HiZL(sHIZ2, vpos.xy, 2.0);
	}	
	
	float2 HZ4PS(PS_INPUTS) : SV_Target
	{
		return HiZL(sHIZ3, vpos.xy, 3.0);
	}	
	
	float2 HZ5PS(PS_INPUTS) : SV_Target
	{
		return HiZL(sHIZ4, vpos.xy, 4.0);
	}	
	
	float2 HZ6PS(PS_INPUTS) : SV_Target
	{
		return HiZL(sHIZ5, vpos.xy, 5.0);
	}	
	
	float2 HZ7PS(PS_INPUTS) : SV_Target
	{
		return HiZL(sHIZ6, vpos.xy, 6.0);
	}	
		
	//=======================================================================================
	//AO
	//=======================================================================================
	
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

	#define SLICES 4
	#define LEVELS 8

	void TraceSliceBF(float2 xy, float3 minPos, float3 maxPos, float3 viewV, float2 vec, float level, int STEPS, inout uint2 BITFIELD)
	{
		float exl = exp2(level);
		float ext = exp2(LEVELS);
		float exlp = max(0,exp2(level - 1.0));
		
		vec *= 1.41421356 * float2(1.0, NRES.x / NRES.y);
		
		float2 no = exl * 1.0 * vec * rcp(NRES);
		
   	 for(int i = 0; i < STEPS; i++)
   	 {
   	 	float o = (exlp + (exl - 1.0) * (float(i) / STEPS) ) / (ext);
   	 	
   	 	
   	 	float2 nxy = xy + no + 1.0 * C0_M*vec * o;
   	 	nxy = (floor(0.25*nxy*NRES) + 0.5)  / (0.25 * NRES);
   	 	float2 rg = saturate(nxy.xy * nxy.xy - nxy.xy);
			if(rg.x != -rg.y) break;
   	 	
   	 	float2 samD = tex2Dlod(sHIZ2, float4(nxy,0,0) ).xy;//GetDepth(nxy);// 
   	 	;
   	 	float3 samPos = GetEyePos(nxy, samD.y);
   	 	
   	 	float3 tvMin = samPos - minPos;
   	 	float3 tvMax = samPos - maxPos;

   	 	float4 minmax = float4(
				FastAcos2(float2(dotnv(tvMin, viewV), dotnv( THICKNESS * normalize(samPos) + (1.0 + 0.1 * THICK_SCALE) * samPos - minPos, viewV) )),
   	 		FastAcos2(float2(dotnv(tvMax, viewV), dotnv( THICKNESS * normalize(samPos) + (1.0 + 0.1 * THICK_SCALE) * samPos - maxPos, viewV) )) );
   	 	minmax = saturate(minmax / 3.14159);
   	 	
   	 	minmax.xy = minmax.x > minmax.y ? minmax.yx : minmax.xy;
   	 	minmax.zw = minmax.z > minmax.w ? minmax.wz : minmax.zw;
   	 	int4 ab = clamp(ceil(32.0 * float4(minmax.xz, minmax.yw - minmax.xz).xzyw), 0, 32);
   	 	BITFIELD |= ((1 << ab.yw) - 1) << ab.xz;
   	 }
	}
	
	float4 GatherMinus1(float2 xy, float3 verPos, float3 viewV, float2 vec, int STEPS)
	{
		//float2 vec = normalize(exy - xy);
		float2 no = 1.0 * vec * rcp(RES);
		
		vec *= 4.0 * 1.41421356 / NRES;
		//vec *= 4.0 * RES / NRES;
		
		
		
		uint BITFIELD;
   	 for(int i = 0; i < STEPS; i++)
   	 {
   	 	float o = (float(i) / STEPS);
   	 	
   	 	
   	 	float2 nxy = xy + no + C0_M*vec * o;
   	 	nxy = (floor(nxy*RES) + 0.5) / (RES);
   	 	float2 rg = saturate(nxy.xy * nxy.xy - nxy.xy);
			if(rg.x != -rg.y) break;
   	 	
   	 	float samD = GetDepth(nxy);// + 1e-4;//tex2Dlod(sHIZ2, float4(nxy,0,0) ).xy;//
   	 	float3 samPos = GetEyePos(nxy, samD.x);
   	 	
   	 	float3 tv = samPos - verPos;

   	 	float2 minmax = FastAcos2(float2(dotnv(tv, viewV), dotnv( THICKNESS * normalize(samPos) + (1.0 + 0.1 * THICK_SCALE) * samPos - verPos, viewV) ));
   	 	minmax = saturate(minmax / 3.14159);
   	 	
   	 	minmax.xy = minmax.x > minmax.y ? minmax.yx : minmax.xy;
   	 	int2 ab = clamp(ceil(32.0 * float2(minmax.x, minmax.y - minmax.x)), 0, 32);
   	 	BITFIELD |= ((1 << ab.y) - 1) << ab.x;
   	 }
   	 
   	 float4 o;
   	 
   	 float3 v = normalize(float3(vec, -0.75));
		float bl = countbits( BITFIELD.x & (((1 << 8) - 1) << 0) ) / 8.0;
		o.x += 1.0 - bl;
		
		v = normalize(float3(vec, -0.25));
		bl = countbits( BITFIELD.x & (((1 << 8) - 1) << 8) ) / 8.0;
		o.y += 1.0 - bl;
		
		v = normalize(float3(vec, 0.25));
		bl = countbits( BITFIELD.x & (((1 << 8) - 1) << 16) ) / 8.0;
		o.z += 1.0 - bl;

		v = normalize(float3(vec, 0.75));
		bl = countbits( BITFIELD.x & (((1 << 8) - 1) << 24) ) / 8.0;
		o.w += 1.0 - bl;
		
		return o;
	}
	
	
	float4 GetSH(float3 vec)
	{
		return float4(0.282095, 0.488603f * vec.y,  0.488603f * vec.z, 0.488603f * vec.x);
	}

	//=======================================================================================
	//RC
	//=======================================================================================
	
	struct mmprobe {
		float4 min;
		float4 max;
	};

	float3 GetPID(float2 pos, float level)
	{
		float exl = exp2(level);
		float2 lr = ceil(0.25 * NRES / exl);
		float2 lp = pos % lr;
		float2 luv = lp / lr;
		float id = (floor(pos.x / lr.x) + 0.0) / (4.0 * exl);
		id += 0.125 / exl - 0.125;
		return float3(luv, frac(-0.125 + id));
	}	
	
	mmprobe MergeCascade(sampler2D tex_m, sampler2D tex_M, sampler2D tex_d, sampler2D tex_hd, float2 pos, float2 xy, float level)
	{
		float exl = exp2(level);
		float exl2 = 0.5*exl;
		
		float2 lr = ceil(0.25 * NRES / exl);
		float2 lp = pos % lr;
		float2 luv = lp / lr;
	
		float qx = floor(4.0 * xy.x * exl) / (4.0 * exl);
		float fx = xy.x - qx;
		
		float4 minP = 0.5 * (
			tex2D(tex_m, float2( qx + 0.5 * fx, xy.y) ) +
			tex2D(tex_m, float2( qx + 0.5 * fx + 0.125 / exl, xy.y) ) );
		
		float4 maxP = 0.5 * (
			tex2D(tex_M, float2( qx + 0.5 * fx, xy.y) ) +
			tex2D(tex_M, float2( qx + 0.5 * fx + 0.125 / exl, xy.y) ) );
		//tex2DBicubic
		float2 d = tex2D(tex_d, float4(luv,0,0).xy ).xy;
		float2 hd = tex2D(tex_hd, float4(luv,0,0).xy ).xy;//High res depth
		
		float2 lval = saturate((hd - d.x) / (d.y - d.x + 1e-10));
		//lval = smoothstep(0,1,lval);
		
		mmprobe o;
		o.min = lerp(minP, maxP, lval.x);
		o.max = lerp(minP, maxP, lval.y);
		return o;
	}

	//=======================================================================================
	//Passes
	//=======================================================================================

	

	mmprobe BFAO(sampler2D texD, float2 xy, float dir, float level, int STEPS)
	{
		mmprobe o;
		float2 ds = tex2Dsize(texD);
		float2 d = tex2D(texD, (floor(xy * ds) + 0.5) / ds).xy;
		float3 minPos = GetEyePos(xy, d.x);
		float3 maxPos = GetEyePos(xy, d.y);
		
		minPos -= 0.001 * length(minPos);
		maxPos -= 0.001 * length(maxPos);
		float3 viewV = -normalize(maxPos);
		
		float2 vec = float2(sin(dir), cos(dir));
		
		uint2 BITFIELD;
		
		TraceSliceBF(xy, minPos, maxPos, viewV, vec, level, STEPS, BITFIELD);
		
		float3 v = normalize(float3(vec, -0.75));
		float bl = countbits( BITFIELD.x & (((1 << 8) - 1) << 0) ) / 8.0;
		o.min.x += 1.0 - bl;
		float bh = countbits( BITFIELD.y & (((1 << 8) - 1) << 0) ) / 8.0;
		o.max.x += 1.0 - bh;

		v = normalize(float3(vec, -0.25));
		bl = countbits( BITFIELD.x & (((1 << 8) - 1) << 8) ) / 8.0;
		o.min.y += 1.0 - bl;
		bh = countbits( BITFIELD.y & (((1 << 8) - 1) << 8) ) / 8.0;
		o.max.y += 1.0 - bh;
		
		v = normalize(float3(vec, 0.25));
		bl = countbits( BITFIELD.x & (((1 << 8) - 1) << 16) ) / 8.0;
		o.min.z += 1.0 - bl;
		bh = countbits( BITFIELD.y & (((1 << 8) - 1) << 16) ) / 8.0;
		o.max.z += 1.0 - bh;
		
		v = normalize(float3(vec, 0.75));
		bl = countbits( BITFIELD.x & (((1 << 8) - 1) << 24) ) / 8.0;
		o.min.w += 1.0 - bl;
		bh = countbits( BITFIELD.y & (((1 << 8) - 1) << 24) ) / 8.0;
		o.max.w += 1.0 - bh;
		
		return o;
	}
	
	void Cascade5PS(PS_INPUTS, out float4 pmin : SV_Target0, out float4 pmax : SV_Target1)
	{
		float3 pxy = GetPID(vpos.xy, 5.0);
		mmprobe slice = BFAO(sHIZ7, pxy.xy, 6.28 * pxy.z, 5.0, 32);
		pmin = slice.min;
		pmax = slice.max;
	}
	
	void Cascade4PS(PS_INPUTS, out float4 pmin : SV_Target0, out float4 pmax : SV_Target1)
	{
		mmprobe l = MergeCascade(sAOMin5, sAOMax5, sHIZ7, sHIZ6, vpos.xy, xy, 4.0);
		float3 pxy = GetPID(vpos.xy, 4.0);
		mmprobe slice = BFAO(sHIZ6, pxy.xy, 6.28 * pxy.z, 4.0, 32);
		
		float2 dn = tex2D(sHIZ6, pxy.xy).xy;
		
		float2 dx = ddx_fine(dn);
		float2 dy = ddy_fine(dn);
		
		float4 mn = 0.5 + 0.5 * normalize(float3(dx.x,dy.x,dn.x/1000.0)).xyzx;
		float4 Mn = 0.5 + 0.5 * normalize(float3(dx.y,dy.y,dn.y/1000.0)).xyzx;
		
		pmin = l.min * slice.min;//min(l.min, slice.min);
		pmax = l.max * slice.max;//min(l.max, slice.max);
	}
	
	void Cascade3PS(PS_INPUTS, out float4 pmin : SV_Target0, out float4 pmax : SV_Target1)
	{
		mmprobe l = MergeCascade(sAOMin4, sAOMax4, sHIZ6, sHIZ5, vpos.xy, xy, 3.0);
		float3 pxy = GetPID(vpos.xy, 3.0);
		mmprobe slice = BFAO(sHIZ5, pxy.xy, 6.28 * pxy.z, 3.0, 32);
		pmin = l.min * slice.min;//min(l.min, slice.min);
		pmax = l.max * slice.max;//min(l.max, slice.max);
	}
	
	void Cascade2PS(PS_INPUTS, out float4 pmin : SV_Target0, out float4 pmax : SV_Target1)
	{
		mmprobe l = MergeCascade(sAOMin3, sAOMax3, sHIZ5, sHIZ4, vpos.xy, xy, 2.0);
		float3 pxy = GetPID(vpos.xy, 2.0);
		mmprobe slice = BFAO(sHIZ4, pxy.xy, 6.28 * pxy.z, 2.0, 16);
		pmin = l.min * slice.min;//min(l.min, slice.min);
		pmax = l.max * slice.max;//min(l.max, slice.max);
	}
	
	void Cascade1PS(PS_INPUTS, out float4 pmin : SV_Target0, out float4 pmax : SV_Target1)
	{
		mmprobe l = MergeCascade(sAOMin2, sAOMax2, sHIZ4, sHIZ3, vpos.xy, xy, 1.0);
		float3 pxy = GetPID(vpos.xy, 1.0);
		mmprobe slice = BFAO(sHIZ3, pxy.xy, 6.28 * pxy.z, 1.0,8);
		pmin = l.min * slice.min;//min(l.min, slice.min);
		pmax = l.max * slice.max;//min(l.max, slice.max);
	}
	
	void Cascade0PS(PS_INPUTS, out float4 pmin : SV_Target0, out float4 pmax : SV_Target1)
	{
		mmprobe l = MergeCascade(sAOMin1, sAOMax1, sHIZ3, sHIZ2, vpos.xy, xy, 0.0);
		float3 pxy = GetPID(vpos.xy, 0.0);
		mmprobe slice = BFAO(sHIZ2, pxy.xy, 6.28 * pxy.z, 0.0, 4);
		pmin = l.min * slice.min;//min(l.min, slice.min);
		pmax = l.max * slice.max;//min(l.max, slice.max);
	}
	
	
	
	//=======================================================================================
	//Blending
	//=======================================================================================

	
	float3 CalcNormalsOrthographic(float2 xy)
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
		
		return normalize(cross(vy, vx));
	}
	
	
	//Deinterleaving was noticably more expensive for lower sample counts
	float3 BlendPS(PS_INPUTS) : SV_Target
	{
		float3 normal = CalcNormalsOrthographic(xy);
		#define NBIAS 0.0
		vpos.xy = xy * NRES;
		
		float3 verPos = NorEyePos(xy);
		float3 viewV = normalize(verPos);
		
		float3 k = cross(viewV, float3(0,0,1)); 
		float c = dot(viewV, float3(0,0,1));    
		float s = length(k);
		normal = normalize(normal * c + cross(k, normal) * s + k * dot(k, normal) * (1.0 - c));

		float3 v0 = float3(0.6124, 0.6124,-(0.75));
		float3 v1 = float3(0.6124, 0.6124,-(0.25));
		float3 v2 = float3(0.6124, 0.6124, (0.25));
		float3 v3 = float3(0.6124, 0.6124, (0.75));
		
		v0 = normalize(v0);
		v1 = normalize(v1);
		v2 = normalize(v2);
		v3 = normalize(v3);
		
		float4 Cm1_0 = GatherMinus1(xy, verPos, -viewV, float2(-1, 1) * 0.707106781, 2);
		float4 Cm1_1 = GatherMinus1(xy, verPos, -viewV, float2( 1, 1) * 0.707106781, 2);
		float4 Cm1_2 = GatherMinus1(xy, verPos, -viewV, float2( 1,-1) * 0.707106781, 2);
		float4 Cm1_3 = GatherMinus1(xy, verPos, -viewV, float2(-1,-1) * 0.707106781, 2);
		
		float4 AO_m0 = Cm1_0 * tex2DfetchBic(sAOMin0, 0.25 * vpos.xy + float2(0.0 * 0.25 * NRES.x, 0.0) ); 
		float4 AO_m1 = Cm1_1 * tex2DfetchBic(sAOMin0, 0.25 * vpos.xy + float2(1.0 * 0.25 * NRES.x, 0.0) ); 
		float4 AO_m2 = Cm1_2 * tex2DfetchBic(sAOMin0, 0.25 * vpos.xy + float2(2.0 * 0.25 * NRES.x, 0.0) ); 
		float4 AO_m3 = Cm1_3 * tex2DfetchBic(sAOMin0, 0.25 * vpos.xy + float2(3.0 * 0.25 * NRES.x, 0.0) ); 
		
		float4 AO_M0 = Cm1_0 * tex2DfetchBic(sAOMax0, 0.25 * vpos.xy + float2(0.0 * 0.25 * NRES.x, 0.0) ); 
		float4 AO_M1 = Cm1_1 * tex2DfetchBic(sAOMax0, 0.25 * vpos.xy + float2(1.0 * 0.25 * NRES.x, 0.0) ); 
		float4 AO_M2 = Cm1_2 * tex2DfetchBic(sAOMax0, 0.25 * vpos.xy + float2(2.0 * 0.25 * NRES.x, 0.0) ); 
		float4 AO_M3 = Cm1_3 * tex2DfetchBic(sAOMax0, 0.25 * vpos.xy + float2(3.0 * 0.25 * NRES.x, 0.0) ); 
		
		float AO_m = 0.0;
		AO_m += AO_m0.x * saturate( dot( float3(-1, 1, 1) * v0, normal ) + NBIAS );
		AO_m += AO_m0.y * saturate( dot( float3(-1, 1, 1) * v1, normal ) + NBIAS );
		AO_m += AO_m0.z * saturate( dot( float3(-1, 1, 1) * v2, normal ) + NBIAS );
		AO_m += AO_m0.w * saturate( dot( float3(-1, 1, 1) * v3, normal ) + NBIAS );
		
		AO_m += AO_m1.x * saturate( dot( float3( 1, 1, 1) * v0, normal ) + NBIAS );
		AO_m += AO_m1.y * saturate( dot( float3( 1, 1, 1) * v1, normal ) + NBIAS );
		AO_m += AO_m1.z * saturate( dot( float3( 1, 1, 1) * v2, normal ) + NBIAS );
		AO_m += AO_m1.w * saturate( dot( float3( 1, 1, 1) * v3, normal ) + NBIAS );
		
		AO_m += AO_m2.x * saturate( dot( float3( 1,-1, 1) * v0, normal ) + NBIAS );
		AO_m += AO_m2.y * saturate( dot( float3( 1,-1, 1) * v1, normal ) + NBIAS );
		AO_m += AO_m2.z * saturate( dot( float3( 1,-1, 1) * v2, normal ) + NBIAS );
		AO_m += AO_m2.w * saturate( dot( float3( 1,-1, 1) * v3, normal ) + NBIAS );
		
		AO_m += AO_m3.x * saturate( dot( float3(-1,-1, 1) * v0, normal ) + NBIAS );
		AO_m += AO_m3.y * saturate( dot( float3(-1,-1, 1) * v1, normal ) + NBIAS );
		AO_m += AO_m3.z * saturate( dot( float3(-1,-1, 1) * v2, normal ) + NBIAS );
		AO_m += AO_m3.w * saturate( dot( float3(-1,-1, 1) * v3, normal ) + NBIAS );
		
		float AO_M = 0.0;
		AO_M += AO_M0.x * saturate( dot( float3(-1, 1, 1) * v0, normal ) + NBIAS );
		AO_M += AO_M0.y * saturate( dot( float3(-1, 1, 1) * v1, normal ) + NBIAS );
		AO_M += AO_M0.z * saturate( dot( float3(-1, 1, 1) * v2, normal ) + NBIAS );
		AO_M += AO_M0.w * saturate( dot( float3(-1, 1, 1) * v3, normal ) + NBIAS );
		
		AO_M += AO_M1.x * saturate( dot( float3( 1, 1, 1) * v0, normal ) + NBIAS );
		AO_M += AO_M1.y * saturate( dot( float3( 1, 1, 1) * v1, normal ) + NBIAS );
		AO_M += AO_M1.z * saturate( dot( float3( 1, 1, 1) * v2, normal ) + NBIAS );
		AO_M += AO_M1.w * saturate( dot( float3( 1, 1, 1) * v3, normal ) + NBIAS );
		
		AO_M += AO_M2.x * saturate( dot( float3( 1,-1, 1) * v0, normal ) + NBIAS );
		AO_M += AO_M2.y * saturate( dot( float3( 1,-1, 1) * v1, normal ) + NBIAS );
		AO_M += AO_M2.z * saturate( dot( float3( 1,-1, 1) * v2, normal ) + NBIAS );
		AO_M += AO_M2.w * saturate( dot( float3( 1,-1, 1) * v3, normal ) + NBIAS );
		
		AO_M += AO_M3.x * saturate( dot( float3(-1,-1, 1) * v0, normal ) + NBIAS );
		AO_M += AO_M3.y * saturate( dot( float3(-1,-1, 1) * v1, normal ) + NBIAS );
		AO_M += AO_M3.z * saturate( dot( float3(-1,-1, 1) * v2, normal ) + NBIAS );
		AO_M += AO_M3.w * saturate( dot( float3(-1,-1, 1) * v3, normal ) + NBIAS );			
		
		AO_m *= 0.25;
		AO_M *= 0.25;
		
		
		
		float d = GetDepth(xy);
		float2 nd = tex2DBicubic(sHIZ2, xy).xy;
		float lval = (d - nd.x) / (nd.y - nd.x + 1e-10);
		
		float AO = 1.1 * lerp(AO_m, AO_M, saturate(lval));
		AO = lerp(1.0, AO, INTENSITY * exp(-4.0 * (1.0 - FADEOUT) * d) );
		
		float3 i = IReinJ(GetBackBuffer(xy), HDR);
		//return 0.25 * lerp(nm, nM, saturate(lval) ).xyz;//
		if(!SHOW_WEIGHTS) return ReinJ((0.01+0.99*AO) * i, HDR);		
		return AO;//pow(AO, rcp(2.2));
		
	}

	
	technique ZenSharpen <
		ui_label = "BETA Zenteon: RCAO";
		>	
	{
		pass {	PASS1(HZ0PS, tHIZ0); }
		pass {	PASS1(HZ1PS, tHIZ1); }
		pass {	PASS1(HZ2PS, tHIZ2); }
		pass {	PASS1(HZ3PS, tHIZ3); }
		pass {	PASS1(HZ4PS, tHIZ4); }
		pass {	PASS1(HZ5PS, tHIZ5); }
		pass {	PASS1(HZ6PS, tHIZ6); }
		pass {	PASS1(HZ7PS, tHIZ7); }
		
		pass {	PASS2(Cascade5PS, tAOMin5, tAOMax5); }
		pass {	PASS2(Cascade4PS, tAOMin4, tAOMax4); }
		pass {	PASS2(Cascade3PS, tAOMin3, tAOMax3); }
		pass {	PASS2(Cascade2PS, tAOMin2, tAOMax2); }
		pass {	PASS2(Cascade1PS, tAOMin1, tAOMax1); }
		pass {	PASS2(Cascade0PS, tAOMin0, tAOMax0); }
		pass {	PASS0(BlendPS); }
	}
}