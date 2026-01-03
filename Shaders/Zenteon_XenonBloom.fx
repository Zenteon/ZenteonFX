//========================================================================
/*
	Copyright © Daniel Oren-Ibarra - 2024
	All Rights Reserved.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND
	EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
	MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
	IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
	CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
	TORT OR OTHERWISE,ARISING FROM, OUT OF OR IN CONNECTION WITH THE
	SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
	
	
	======================================================================	
	Zenteon: Xenon v0.2 - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/
//========================================================================





#if(__RENDERER__ != 0x9000)

	#include "ReShade.fxh"
	#include "ZenteonCommon.fxh"

	#ifndef CHEF_MODE
	//============================================================================================
		#define CHEF_MODE 0
	//============================================================================================
	#endif
	
	namespace ZenXenon {
		texture2D DirtTex < source = "procdirt.png"; >//ZenDirt
		{
			Width  = 1920;
			Height = 1080;
			Format = RGBA8;
			MipLevels = 8;
		};
	}
	
	sampler2D XenDirt { Texture = ZenXenon::DirtTex; WRAPMODE(WRAP); };
	
	
	uniform float LOG_WHITEPOINT <
		ui_type = "drag";
		ui_label = "Log Whitepoint";
		ui_tooltip = "Sets the max brightness in the scene, higher values will make bloom wider and more pronounced";
		ui_min = 0.0;
		ui_max = 12.0;
	> = 10.0;
	
	
	#define HDRP ( 1.0 + rcp(exp2(LOG_WHITEPOINT)) ), 0, 0
	
	uniform float INTENSITY <
		ui_type = "drag";
		ui_label = "Bloom Intensity";
		ui_tooltop = "Overall strength of the effect";
		ui_min = 0.0;
		ui_max = 1.0 + (2*CHEF_MODE);
	> = 0.5;
	
	uniform float DIRT_STRENGTH <
		ui_type = "drag";
		ui_min = 0.0;
		ui_max = 1.0;
		ui_label = "Dirt Instensity";
		ui_tooltip = "Intensity of the lens dirt effect";
	> = 0.5;
	
	uniform float WIDTH <
		ui_type = "drag";
		ui_label = "Kernel Width";
		ui_min = 0.0;
		ui_max = 1.0;
	> = 0.5;
	
	uniform int DEBUG <
		ui_label = "Debug";
		ui_type = "combo";
		ui_items = "None\0Raw Bloom Output\0";
		ui_category_closed = true;
		hidden = !CHEF_MODE;
	> = 0;
	
	uniform int BLEND_MODE <
		ui_type = "combo";
		ui_items = "Physical\0Soft Light\0Add\0Screen\0UI Preserving\0";
		ui_tooltip = "Sets the mode that is used for blending, Physical is the default, and emulates the results of an actual camera"; 
		hidden = !CHEF_MODE;
	> = 0;

	uniform float3 BLOOM_COL <
		ui_type = "color";
		ui_label = "Bloom Color";
		hidden = !CHEF_MODE;
	> = float3(1.0, 1.0, 1.0);	

	
namespace XEN2 {
	texture LightMap{Width = BUFFER_WIDTH;	 Height = BUFFER_HEIGHT;	 Format = RGBA16F;};
	texture DownTex0{Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA16F;};
	texture DownTex1{Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F;};
	texture DownTex2{Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F;};
	texture DownTex3{Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = RGBA16F;};
	texture DownTex4{Width = BUFFER_WIDTH / 32; Height = BUFFER_HEIGHT / 32; Format = RGBA16F;};
	texture DownTex5{Width = BUFFER_WIDTH / 64; Height = BUFFER_HEIGHT / 64; Format = RGBA16F;};
	texture DownTex6{Width = BUFFER_WIDTH / 128; Height = BUFFER_HEIGHT / 128; Format = RGBA16F;};
	texture DownTex7{Width = BUFFER_WIDTH / 256; Height = BUFFER_HEIGHT / 256; Format = RGBA16F;};
	texture DownTex8{Width = BUFFER_WIDTH / 512; Height = BUFFER_HEIGHT / 512; Format = RGBA16F;};
		
	texture UpTex0000{Width = BUFFER_WIDTH / 256; Height = BUFFER_HEIGHT / 256; Format = RGBA16F;};
	texture UpTex000{Width = BUFFER_WIDTH / 128; Height = BUFFER_HEIGHT / 128; Format = RGBA16F;};
	texture UpTex00{Width = BUFFER_WIDTH / 64; Height = BUFFER_HEIGHT / 64; Format = RGBA16F;};
	texture UpTex0{Width = BUFFER_WIDTH / 32; Height = BUFFER_HEIGHT / 32; Format = RGBA16F;};
	texture UpTex1{Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = RGBA16F;};
	texture UpTex2{Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F;};
	texture UpTex3{Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F;};
	texture UpTex4{Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA16F;};
		
	texture BloomTex{Width = BUFFER_WIDTH;	 Height = BUFFER_HEIGHT;	 Format = RGBA16F;};
	
	sampler LightSam{Texture = LightMap; WRAPMODE(BORDER); };
	sampler DownSam0{Texture = DownTex0; WRAPMODE(BORDER); };
	sampler DownSam1{Texture = DownTex1; WRAPMODE(BORDER); };
	sampler DownSam2{Texture = DownTex2; WRAPMODE(BORDER); };
	sampler DownSam3{Texture = DownTex3; WRAPMODE(BORDER); };
	sampler DownSam4{Texture = DownTex4; WRAPMODE(BORDER); };
	sampler DownSam5{Texture = DownTex5; WRAPMODE(BORDER); };
	sampler DownSam6{Texture = DownTex6; WRAPMODE(BORDER); };
	sampler DownSam7{Texture = DownTex7; WRAPMODE(BORDER); };
	sampler DownSam8{Texture = DownTex8; WRAPMODE(BORDER); };
	
	sampler UpSam0000{Texture = UpTex0000; WRAPMODE(BORDER); };
	sampler UpSam000{Texture = UpTex000;WRAPMODE(BORDER);  };
	sampler UpSam00{Texture = UpTex00; WRAPMODE(BORDER); };
	sampler UpSam0{Texture = UpTex0; WRAPMODE(BORDER); };
	sampler UpSam1{Texture = UpTex1; WRAPMODE(BORDER); };
	sampler UpSam2{Texture = UpTex2; WRAPMODE(BORDER); };
	sampler UpSam3{Texture = UpTex3; WRAPMODE(BORDER); };
	sampler UpSam4{Texture = UpTex4; WRAPMODE(BORDER); };
	
	sampler BloomSam{Texture = BloomTex; };
	
	//=============================================================================
	//Functions
	//=============================================================================
	
	float4 DUSample(float2 xy, sampler input)
	{
	    float2 hp = 2.0*rcp(tex2Dsize(input));
	   
		float4 acc;
		const float2 w = float2(0.0714, 0.1428);
		
		acc += w.x * tex2D(input, xy + float2(0, hp.y));
		//acc += 0.03125 * tex2D(input, xy + float2(hp.x, hp.y));
		
		acc += w.x * tex2D(input, xy + float2(-hp.x, 0));
		acc += w.y * tex2D(input, xy + float2(0, 0));
		acc += w.x * tex2D(input, xy + float2(hp.x, 0));
		
		//acc += 0.03125 * tex2D(input, xy + float2(-hp.x, -hp.y));
		acc += w.x * tex2D(input, xy + float2(0, -hp.y));
		//acc += 0.03125 * tex2D(input, xy + float2(hp.x, -hp.y));

	  
		acc += w.y * tex2D(input, xy + 0.5 * float2(hp.x, hp.y));
		acc += w.y * tex2D(input, xy + 0.5 * float2(hp.x, -hp.y));
		acc += w.y * tex2D(input, xy + 0.5 * float2(-hp.x, hp.y));
		acc += w.y * tex2D(input, xy + 0.5 * float2(-hp.x, -hp.y));
		
	    return acc / (w.x*4.0 + w.y*5.0);
	
	}

	float4 DSample(float2 xy, sampler input)
	{
		float2 its = rcp(tex2Dsize(input));
		float2 hp = 0.5 * its;//0.75777*its;
		
		float4 acc; float4 t;
		float minD = 1.0;
		
		acc += 0.25 * tex2D(input, xy + float2( hp.x,  hp.y));
		acc += 0.25 * tex2D(input, xy + float2( hp.x, -hp.y));
		acc += 0.25 * tex2D(input, xy + float2(-hp.x,  hp.y));
		acc += 0.25 * tex2D(input, xy + float2(-hp.x, -hp.y));
	
		return acc;
	}

	
	//Bicubic sampling in 4 taps from
	//https://web.archive.org/web/20180927181721/http://www.java-gaming.org/index.php?topic=35123.0
	float4 wCubic(float x)
	{	
		float4 n = float4(1,2,3,4) - x;
		float4 s = n*n*n;
		n = float4(s.x, s.y - 4.0*s.x, s.z - 4.0*s.y + 6.0*s.x, 1.0);
		n.w = 6.0 - (n.x+n.y+n.z);
		return 0.166666667 * n;
	}
	
	float4 USample(float2 xy, sampler2D tex)
	{
		float2 ts = tex2Dsize(tex);
		float2 its = rcp(ts);
		
		float2 pos = ts*xy - 0.5;
		float2 fxy = frac(pos); pos -= fxy;
		
		float4 xCb = wCubic(fxy.x);
		float4 yCb = wCubic(fxy.y);
		
		float4 c = pos.xxyy + float2(-0.5,1.5).xyxy;
		float4 s = float4(xCb.xz + xCb.yw, yCb.xz + yCb.yw);
		float4 o = its.xxyy * (c + float4(xCb.yw,yCb.yw) / s);
		
		float4 A = tex2Dlod(tex, float4(o.xz,0,0));
		float4 B = tex2Dlod(tex, float4(o.yz,0,0));
		float4 C = tex2Dlod(tex, float4(o.xw,0,0));
		float4 D = tex2Dlod(tex, float4(o.yw,0,0));
		
		float2 lv = s.xz / (s.xz + s.yw);
		
		return lerp(lerp(D,C,lv.x), lerp(B,A,lv.x), lv.y);
	}
	
	
	float4 tex2DlodBicubic(sampler2D tex, float2 xy, float mip)
	{
		float2 ts = tex2Dsize(tex, mip);
		float2 its = rcp(ts);
		
		float2 pos = ts*xy - 0.5;
		float2 fxy = frac(pos); pos -= fxy;
		
		float4 xCb = wCubic(fxy.x);
		float4 yCb = wCubic(fxy.y);
		
		float4 c = pos.xxyy + float2(-0.5,1.5).xyxy;
		float4 s = float4(xCb.xz + xCb.yw, yCb.xz + yCb.yw);
		float4 o = its.xxyy * (c + float4(xCb.yw,yCb.yw) / s);
		
		float4 A = tex2Dlod(tex, float4(o.xz,0,mip));
		float4 B = tex2Dlod(tex, float4(o.yz,0,mip));
		float4 C = tex2Dlod(tex, float4(o.xw,0,mip));
		float4 D = tex2Dlod(tex, float4(o.yw,0,mip));
		
		float2 lv = s.xz / (s.xz + s.yw);
		
		return lerp(lerp(D,C,lv.x), lerp(B,A,lv.x), lv.y);
	}
	
	float IGN(float2 xy)
	{
	    float3 conVr = float3(0.06711056, 0.00583715, 52.9829189);
	    return frac( conVr.z * frac(dot(xy % RES,conVr.xy)) );
	}

	//=============================================================================
	//Tonemappers
	//=============================================================================
	
	//for testing
	float3 LogC4ToLinear(float3 LogC4Color)
	{
	    float3 p;
	
	    p = 14.0 * (LogC4Color - 0.0928641251221896) / 0.9071358748778104 + 6.0;
	
	    return (exp2(p) - 64.0) / 2231.826309067688;
	}

	
	//=============================================================================
	//Passes
	//=============================================================================
	float4 BloomMap(PS_INPUTS) : SV_Target
	{
		float3 input = tex2D(ReShade::BackBuffer, xy).rgb;
		input = IReinJ(input, HDRP);
		
		float3 c = BLOOM_COL*BLOOM_COL;
		c /= dot(c, float3(0.2126, 0.7152, 0.0722)) + 0.01;
		
		input *= (0.75 * c + 0.25);
		//input = dot(vpos.xy - 0.5*RES, vpos.xy - 0.5*RES) < 120.0 ? 1024.0 : 0.0;
		
		return float4(input, 1.0);
	}
	//=============================================================================
	//Bloom Passes
	//=============================================================================
	
	float3 cLobe(float3 x, float3 o, float3 m)
	{
		x = m * (x-o);
		x = 1.0 - x*x;
		return max(x*x*x,0.0);
	}
	
	//From 400-700nm for a fractional x
	float3 ZenSpectrum(float x)
	{
	    return float3(1.00,0.800,0.200) * cLobe(x, float3(0.720,0.53,0.300),3.4				) +
	           float3(0.02,0.028,0.066) * cLobe(x, float3(0.156,0.60,0.695),float3(9.9,2.1,8.0));
	}
	
	float4 GetBC(float l, float2 xy)
	{
		
		float4 f = tex2Dlod(XenDirt, float4(xy,0,l.x)).rgba;
		f = pow(f, 2.2);
		f = lerp(1.0, 5.0 * max(-f / (f - 1.0), 0.0), DIRT_STRENGTH);

		float4 x = exp( -rcp(5.0 * WIDTH*WIDTH + 0.01) * l*f );
		x.w = dot(x.rgb,float3(0.2126, 0.7152, 0.0722) );
		return x;
		
		//return exp( -rcp(10.0 * WIDTH*WIDTH + 0.01) * l);
		
		//FOG integral
		//l = sqrt(l);
		/*
		l = log2(exp2(l) / ( (RES.y / 1080.0) * 4.0 * WIDTH + 0.5) );// WIDTH +
		l = sqrt(l);
		float x = clamp(l,0,10.999);
		return max((((-0.000285*x+0.006487)*x-0.037077)*x-0.070722)*x+0.802702,0.001);
		*/
	}
	
	
	float4 DownSample0(PS_INPUTS) : SV_Target {
		return DSample(xy, LightSam);	}
		
	float4 DownSample1(PS_INPUTS) : SV_Target {
		return DUSample(xy, DownSam0);	}
	
	float4 DownSample2(PS_INPUTS) : SV_Target {
		return DUSample(xy, DownSam1);	}
	
	float4 DownSample3(PS_INPUTS) : SV_Target {
		return DUSample(xy, DownSam2);	}
	
	float4 DownSample4(PS_INPUTS) : SV_Target {
		return DUSample(xy, DownSam3);	}
	
	float4 DownSample5(PS_INPUTS) : SV_Target {
		return DUSample(xy, DownSam4);	}
		
	float4 DownSample6(PS_INPUTS) : SV_Target {
		return DUSample(xy, DownSam5);	}
		
	float4 DownSample7(PS_INPUTS) : SV_Target {
		return DUSample(xy, DownSam6);	}
	//====
	
	float4 DownSample8(PS_INPUTS) : SV_Target {
		return GetBC(10, xy) * DUSample(xy, DownSam7);	}
	//====
	
	float4 UpSample0000(PS_INPUTS) : SV_Target {
		return GetBC(9, xy)*tex2D(DownSam7, xy) + USample(xy, DownSam8);	}
	
	float4 UpSample000(PS_INPUTS) : SV_Target {
		return GetBC(8, xy)*tex2D(DownSam6, xy) + USample(xy, UpSam0000);	}
	
	float4 UpSample00(PS_INPUTS) : SV_Target {
		return GetBC(7, xy)*tex2D(DownSam5, xy) + USample(xy, UpSam000);	}
	
	float4 UpSample0(PS_INPUTS) : SV_Target {
		return GetBC(6, xy)*tex2D(DownSam4, xy) + USample(xy, UpSam00);	}
	
	float4 UpSample1(PS_INPUTS) : SV_Target {
		return GetBC(5, xy)*tex2D(DownSam3, xy) + USample(xy, UpSam0);	}
	
	float4 UpSample2(PS_INPUTS) : SV_Target {
		return GetBC(4, xy)*tex2D(DownSam2, xy) + USample(xy, UpSam1);	}
	
	float4 UpSample3(PS_INPUTS) : SV_Target {
		return GetBC(3, xy)*tex2D(DownSam1, xy) + USample(xy, UpSam2);	}
	
	float4 UpSample4(PS_INPUTS) : SV_Target {
		return GetBC(2, xy)*tex2D(DownSam0, xy) + USample(xy, UpSam3);	}
	
	float4 UpSample5(PS_INPUTS) : SV_Target {
		return GetBC(1, xy)*USample(xy, LightSam) + USample(xy, UpSam4);	}
	
	//=============================================================================
	//Blending Functions
	//=============================================================================
	
	float3 TMSoftLight(float3 a, float3 b, float level)
	{
		a = ReinJ(a, HDRP);
		b = ReinJ(b, HDRP);
		return lerp(a, (1.0-2.0*a) * b*b + 2.0*b*a, level);
	}
	
	float3 TMScreen(float3 a, float3 b, float level)
	{
		a = ReinJ(a, HDRP);
		b = ReinJ(b, HDRP);
		b = 1.0 - ((1.0 - a) * (1.0 - b));
		return lerp(a, b, level);
	}
	
	float3 TMDodge(float3 a, float3 b, float level)
	{
		a = ReinJ(a, HDRP);
		b = ReinJ(b, HDRP);
		
	}
	
	
	float3 TM_UIPres(float3 a, float3 b, float level)
	{
		return ReinJ( lerp(a,b, (sqrt(ReinJ(GetLuminance(a), HDRP) ) + 0.03) * level), HDRP);
	}
	
	float3 Blend(float3 input, float3 bloom, float level, int mode)
	{
		if(mode == 0) return ReinJ(lerp(input, bloom, level), HDRP);
		if(mode == 1) return TMSoftLight(input, bloom, level);
		if(mode == 2) return ReinJ(input + level * bloom, HDRP);
		if(mode == 3) return TMScreen(input, bloom, level);
		if(mode == 4) return TM_UIPres(input, bloom, level);
		
		return 0;
	}
	
	
	//=============================================================================
	//Blending
	//=============================================================================
	float2 hash23(float3 p3)
	{
		p3 = frac(p3 * float3(.1031, .1030, .0973));
	    p3 += dot(p3, p3.yzx+33.33);
	    return frac((p3.xx+p3.yz)*p3.zy);
	}
	
	float3 QUARK_BLOOM(PS_INPUTS) : SV_Target
	{
		float3 input = GetBackBuffer(xy);
			   input = IReinJ(input, HDRP);

		float4 bloom = GetBC(0, xy) * float4(input,1.0) + tex2D(BloomSam, xy);//
		//
		
		bloom.rgb /= bloom.a;
		input.rgb = Blend(input.rgb, bloom.rgb, 0.5 * 0.33334 * INTENSITY, BLEND_MODE);
		
		float dither = (IGN(vpos.xy) - 0.5) * rcp(exp2(8));
		if(DEBUG) return dither + ReinJ(bloom.rgb, HDRP);
		
		
		float3 l = tex2Dlod(XenDirt, float4(xy,0,0)).rgb;
		
		float3 pos = NorEyePos(xy);
		float3 apos = round(2.0 * abs(pos));
		
		float lp = round(log2(1.0 + max(apos.x, max(apos.y, apos.z))));
		lp = exp2(lp);
		lp = max(lp,exp2(4));
		pos = round(64.0 * pos / (lp - 1.0) );
		
		float3 n = GetNormal(xy);
		n = (n > 0.01.xxx ? 1.0.xxx : -1.0.xxx);
		float3 id = float3(hash23(pos ), lp / exp2(8) );
		//return id;//round(apos) / 100.0;//round(lp);
		
		return dither + input;
	}
	
	technique Xenon <
	ui_label = "Zenteon: Xenon Bloom";
	    ui_tooltip =        
	        "								   Zenteon - Xenon Bloom           \n"
	        "\n================================================================================================="
	        "\n"
	        "\nXenon is a highly accurate bloom shader"
	        "\nIt emulates the falloff of real world cameras to provide the most pysically accurate output"
	        "\nin real time aside from fourier methods"
	        "\n"
	        "\n=================================================================================================";
	>	
	{
		pass
		{
			VertexShader = PostProcessVS;
			PixelShader = BloomMap;
			RenderTarget = XEN2::LightMap; 
		}
		
		pass {VertexShader = PostProcessVS; PixelShader = DownSample0;		RenderTarget = XEN2::DownTex0; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample1;		RenderTarget = XEN2::DownTex1; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample2;		RenderTarget = XEN2::DownTex2; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample3;		RenderTarget = XEN2::DownTex3; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample4;		RenderTarget = XEN2::DownTex4; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample5;		RenderTarget = XEN2::DownTex5; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample6;		RenderTarget = XEN2::DownTex6; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample7;		RenderTarget = XEN2::DownTex7; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample8;		RenderTarget = XEN2::DownTex8; }
		
		pass {VertexShader = PostProcessVS; PixelShader = UpSample0000;		RenderTarget = XEN2::UpTex0000; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample000;		RenderTarget = XEN2::UpTex000; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample00;		RenderTarget = XEN2::UpTex00; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample0;		RenderTarget = XEN2::UpTex0; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample1;		RenderTarget = XEN2::UpTex1; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample2;		RenderTarget = XEN2::UpTex2; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample3;		RenderTarget = XEN2::UpTex3; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample4;		RenderTarget = XEN2::UpTex4; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample5;		RenderTarget = XEN2::BloomTex; }
		pass
		{
			VertexShader = PostProcessVS;
			PixelShader = QUARK_BLOOM;
		}
	}
}
#else	
	int Dx9Warning <
		ui_type = "radio";
		ui_text = "Oops, looks like you're using DX9\n"
			"if you would like to use Quark Shaders in DX9 games, please use a wrapper like DXVK or dgVoodoo2";
		ui_label = " ";
		> = 0;
		
	technique Xenon <
	ui_label = "Quark: Xenon Bloom";
	    ui_tooltip =        
	        "								   Xenon Bloom - Made by Zenteon           \n"
	        "\n================================================================================================="
	        "\n"
	        "\nXenon is a highly accurate bloom shader"
	        "\nIt emulates the falloff of real world cameras to provide the most pysically accurate output"
	        "\nin real time aside from fourier methods"
	        "\n"
	        "\n=================================================================================================";
	>	
	{ }
#endif
