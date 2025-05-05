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
	
	namespace Xenon {
		texture DirtTex < source = "ZenDirt.png"; >
		{
			Width  = 1920;
			Height = 1080;
			Format = RGBA8;
		};
	}
	
	sampler XenDirt { Texture = Xenon::DirtTex; WRAPMODE(WRAP); };
	
	
	uniform float LOG_WHITEPOINT <
		ui_type = "drag";
		ui_label = "Log Whitepoint";
		ui_tooltip = "Sets the max brightness in the scene, higher values will make bloom wider and more pronounced";
		ui_min = 0.0;
		ui_max = 8.0;
	> = 5.0;
	
	
	#define HDRP ( 1.0 + rcp(exp(LOG_WHITEPOINT)) ), 0, 0
	
	uniform float INTENSITY <
		ui_type = "drag";
		ui_label = "Bloom Intensity";
		ui_tooltop = "Overall strength of the effect";
		ui_min = 0.0;
		ui_max = 1.0 + CHEF_MODE;
	> = 0.5;
	
	uniform float DIRT_STRENGTH <
		ui_type = "drag";
		ui_min = 0.0;
		ui_max = 1.0 + CHEF_MODE;
		ui_label = "Dirt Instensity";
		ui_tooltip = "Intensity of the lens dirt effect";
	> = 0.5;
	
	uniform int WAVEDEF <
		ui_label = "Wave Deflection";
		//hidden = !CHEF_MODE;
		ui_type = "slider";
		ui_tooltop = "Takes the wavelength into account for the bloom kernel";
		ui_min = 0;
		ui_max = 1;
		hidden = true;
	> = 0;
	
		
	uniform float WIDTH <
		ui_type = "drag";
		ui_label = "Kernel Width";
		ui_min = 0.0;
		ui_max = 1.0;
	> = 1.0-1.0/(RES.y/1080.0);
	
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

	
namespace XEN {
	texture LightMap{Width = BUFFER_WIDTH;	 Height = BUFFER_HEIGHT;	 Format = RGBA16F;};
	texture DownTex0{Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA16F;};
	texture DownTex1{Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F;};
	texture DownTex2{Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F;};
	texture DownTex3{Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = RGBA16F;};
	texture DownTex4{Width = BUFFER_WIDTH / 32; Height = BUFFER_HEIGHT / 32; Format = RGBA16F;};
	texture DownTex5{Width = BUFFER_WIDTH / 64; Height = BUFFER_HEIGHT / 64; Format = RGBA16F;};
	texture DownTex6{Width = BUFFER_WIDTH / 128; Height = BUFFER_HEIGHT / 128; Format = RGBA16F;};
	texture DownTex7{Width = BUFFER_WIDTH / 256; Height = BUFFER_HEIGHT / 256; Format = RGBA16F;};
		
	texture UpTex000{Width = BUFFER_WIDTH / 128; Height = BUFFER_HEIGHT / 128; Format = RGBA16F;};
	texture UpTex00{Width = BUFFER_WIDTH / 64; Height = BUFFER_HEIGHT / 64; Format = RGBA16F;};
	texture UpTex0{Width = BUFFER_WIDTH / 32; Height = BUFFER_HEIGHT / 32; Format = RGBA16F;};
	texture UpTex1{Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = RGBA16F;};
	texture UpTex2{Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F;};
	texture UpTex3{Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F;};
	texture UpTex4{Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA16F;};
		
	texture BloomTex{Width = BUFFER_WIDTH;	 Height = BUFFER_HEIGHT;	 Format = RGBA16F;};
	
	sampler LightSam{Texture = LightMap; };
	sampler DownSam0{Texture = DownTex0; };
	sampler DownSam1{Texture = DownTex1; };
	sampler DownSam2{Texture = DownTex2; };
	sampler DownSam3{Texture = DownTex3; };
	sampler DownSam4{Texture = DownTex4; };
	sampler DownSam5{Texture = DownTex5; };
	sampler DownSam6{Texture = DownTex6; };
	sampler DownSam7{Texture = DownTex7; };
	
	sampler UpSam000{Texture = UpTex000; };
	sampler UpSam00{Texture = UpTex00; };
	sampler UpSam0{Texture = UpTex0; };
	sampler UpSam1{Texture = UpTex1; };
	sampler UpSam2{Texture = UpTex2; };
	sampler UpSam3{Texture = UpTex3; };
	sampler UpSam4{Texture = UpTex4; };
	
	sampler BloomSam{Texture = BloomTex; };
	
	//=============================================================================
	//Functions
	//=============================================================================
	
	float4 DUSample(float2 xy, sampler input, float div)//0.375 + 0.25
	{
	    float2 hp = div * rcp(RES);
	   
		float4 acc;
		
		acc += 0.03125 * tex2D(input, xy + float2(-hp.x, hp.y));
		acc += 0.0625 * tex2D(input, xy + float2(0, hp.y));
		acc += 0.03125 * tex2D(input, xy + float2(hp.x, hp.y));
		
		acc += 0.0625 * tex2D(input, xy + float2(-hp.x, 0));
		acc += 0.125 * tex2D(input, xy + float2(0, 0));
		acc += 0.0625 * tex2D(input, xy + float2(hp.x, 0));
		
		acc += 0.03125 * tex2D(input, xy + float2(-hp.x, -hp.y));
		acc += 0.0625 * tex2D(input, xy + float2(0, -hp.y));
		acc += 0.03125 * tex2D(input, xy + float2(hp.x, -hp.y));
	  
		acc += 0.125 * tex2D(input, xy + 0.5 * float2(hp.x, hp.y));
		acc += 0.125 * tex2D(input, xy + 0.5 * float2(hp.x, -hp.y));
		acc += 0.125 * tex2D(input, xy + 0.5 * float2(-hp.x, hp.y));
		acc += 0.125 * tex2D(input, xy + 0.5 * float2(-hp.x, -hp.y));
		
	    return acc;
	
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
		float3 input	  = tex2D(ReShade::BackBuffer, xy).rgb;
		float  depth	  = 1f - ReShade::GetLinearizedDepth(xy);
		float inl = GetLuminance(input*input) / (0.0001 + dot(input*input, rcp(3.0) ));
		input = IReinJ(input, HDRP);
		input /= inl + 0.001;//GetLuminance(incol);
		
		
		float3 tint = pow(0.5 + 0.5 * BLOOM_COL, 2.2);
		tint /= 0.5 + 0.5 * dot(tint, float3(0.2126,0.7152,0.0722));
		//return 50.0 * (distance(vpos.xy, 0.5 * RES) <= 30.0);//(xy-0.5, xy-0.5)
		return float4(tint * input, 1.0);
	}
	//=============================================================================
	//Bloom Passes
	//=============================================================================
	//Normalized, scary numbers
	//#define coef00 (0.26735)
	/*
	#define coef00  (WAVEDEF ? float4(0.4472, 1.25, 1.394, 1) : 0.9)
	#define coef0  (WAVEDEF ? float4(0.18, 0.285, 0.285, 1 ) : 0.34)
	#define coef1  (WAVEDEF ? float4(0.1467, 0.18, 0.15, 1 ) : 0.22)
	#define coef2  (WAVEDEF ? float4(0.099, 0.059, 0.047, 1 ) : 0.09)
	#define coef3  (WAVEDEF ? float4(0.06, 0.051, 0.0495, 1 ) : 0.05)
	#define coef4  (WAVEDEF ? float4(0.034, 0.016, 0.01, 1 ) : 0.02161)
	#define coef5  (WAVEDEF ? float4(0.0155, 0.013, 0.0117, 1 ) : 0.0116)
	#define coef6  (WAVEDEF ? float4(0.0086, 0.0045, 0.0026, 1 ) : 0.0058)
	#define coef7  (WAVEDEF ? float4(0.004, 0.00325, 0.0025, 1 ) : 0.005)
	#define coef8  (WAVEDEF ? float4(0.005, 0.0024, 0.002, 1 ) : 0.0018)
	*/
	
	#define coef00 lerp(0.4472, 0.156, WIDTH)
	#define coef0 lerp(0.1800, 0.1350, WIDTH)
	#define coef1 lerp(0.1467, 0.1590, WIDTH)
	#define coef2 lerp(0.0990, 0.1770, WIDTH)
	#define coef3 lerp(0.0600, 0.1500, WIDTH)
	#define coef4 lerp(0.0340, 0.1000, WIDTH)
	#define coef5 lerp(0.0155, 0.0400, WIDTH)
	#define coef6 lerp(0.0086, 0.0396, WIDTH)
	#define coef7 lerp(0.0040, 0.0199, WIDTH)
	#define coef8 lerp(0.0050, 0.0235, WIDTH)
	
	/*
	#define coef00 0.0
	#define coef0 0.0
	#define coef1 0.0
	#define coef2 0.0
	#define coef3 0.0
	#define coef4 0.0
	#define coef5 1.0
	#define coef6 0.0
	#define coef7 0.0
	#define coef8 0.0
	*/
	
	float4 DownSample0(PS_INPUTS) : SV_Target {
		return DUSample(xy, LightSam, 2.0);	}
		
	float4 DownSample1(PS_INPUTS) : SV_Target {
		return DUSample(xy, DownSam0, 4.0);	}
	
	float4 DownSample2(PS_INPUTS) : SV_Target {
		return DUSample(xy, DownSam1, 8.0);	}
	
	float4 DownSample3(PS_INPUTS) : SV_Target {
		return DUSample(xy, DownSam2, 16.0);	}
	
	float4 DownSample4(PS_INPUTS) : SV_Target {
		return DUSample(xy, DownSam3, 32.0);	}
	
	float4 DownSample5(PS_INPUTS) : SV_Target {
		return DUSample(xy, DownSam4, 64.0);	}
		
	float4 DownSample6(PS_INPUTS) : SV_Target {
		return DUSample(xy, DownSam5, 128.0);	}
		
	float4 DownSample7(PS_INPUTS) : SV_Target {
		return coef8 * DUSample(xy, DownSam6, 256.0);	}
	//====
	
	float4 UpSample000(PS_INPUTS) : SV_Target {
		return coef7*tex2D(DownSam6, xy) + DUSample(xy, DownSam7, 256.0);	}
	
	float4 UpSample00(PS_INPUTS) : SV_Target {
		return coef6*tex2D(DownSam5, xy) + DUSample(xy, UpSam000, 128.0);	}
	
	float4 UpSample0(PS_INPUTS) : SV_Target {
		return coef5*tex2D(DownSam4, xy) + DUSample(xy, UpSam00, 64.0);	}
	
	float4 UpSample1(PS_INPUTS) : SV_Target {
		return coef4*tex2D(DownSam3, xy) + DUSample(xy, UpSam0, 32.0);	}
	
	float4 UpSample2(PS_INPUTS) : SV_Target {
		return coef3*tex2D(DownSam2, xy) + DUSample(xy, UpSam1, 16.0);	}
	
	float4 UpSample3(PS_INPUTS) : SV_Target {
		return coef2*tex2D(DownSam1, xy) + DUSample(xy, UpSam2, 8.0);	}
	
	float4 UpSample4(PS_INPUTS) : SV_Target {
		return coef1*tex2D(DownSam0, xy) + DUSample(xy, UpSam3, 4.0);	}
	
	float4 UpSample5(PS_INPUTS) : SV_Target {
		return coef0*tex2D(LightSam, xy) + DUSample(xy, UpSam4, 2.0);	}
	
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
	
	float IGN(float2 xy)
		{
		    float3 conVr = float3(0.06711056, 0.00583715, 52.9829189);
		    return frac( conVr.z * frac(dot(xy % RES,conVr.xy)) );
		}
	
	float3 QUARK_BLOOM(PS_INPUTS) : SV_Target
	{
		float3 input = GetBackBuffer(xy);
			   input = IReinJ(input, HDRP);
		
		float4 bloom = (coef00 * tex2D(LightSam, xy) + DUSample(xy, BloomSam, 1.0));
		bloom.rgb /= WAVEDEF ? float3(1.0, 1.86415, 1.9543) : 1.64581;
		//bloom.rgb = bloom.bbb;
		
		float4 dirt  = bloom * tex2D(XenDirt, ASPECT_RATIO * xy);
		bloom.rgb += dirt.rgb * DIRT_STRENGTH;
		input.rgb = Blend(input.rgb, bloom.rgb, 0.5 * INTENSITY, BLEND_MODE);
		
		float dither = (IGN(vpos.xy) - 0.5) * rcp(exp2(8));
		if(DEBUG) return dither + ReinJ(bloom.rgb, HDRP);
		return dither + input;
		//float ref = 50.0 / pow(0.66 * max(distance(vpos.xy, 0.5 * RES) - 30.0, 1.0), 2.0);
		//return dither + ReinJ(ref, HDRP);
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
			RenderTarget = XEN::LightMap; 
		}
		
		pass {VertexShader = PostProcessVS; PixelShader = DownSample0;		RenderTarget = XEN::DownTex0; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample1;		RenderTarget = XEN::DownTex1; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample2;		RenderTarget = XEN::DownTex2; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample3;		RenderTarget = XEN::DownTex3; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample4;		RenderTarget = XEN::DownTex4; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample5;		RenderTarget = XEN::DownTex5; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample6;		RenderTarget = XEN::DownTex6; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample7;		RenderTarget = XEN::DownTex7; }
		
		pass {VertexShader = PostProcessVS; PixelShader = UpSample000;		RenderTarget = XEN::UpTex000; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample00;		RenderTarget = XEN::UpTex00; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample0;		RenderTarget = XEN::UpTex0; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample1;		RenderTarget = XEN::UpTex1; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample2;		RenderTarget = XEN::UpTex2; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample3;		RenderTarget = XEN::UpTex3; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample4;		RenderTarget = XEN::UpTex4; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample5;		RenderTarget = XEN::BloomTex; }
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
