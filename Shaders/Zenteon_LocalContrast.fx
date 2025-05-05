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
	Zenteon: Local Contrast v0.2 - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/
//========================================================================

#include "ReShade.fxh"
#include "ZenteonCommon.fxh"


#if(__RENDERER__ != 0x9000)


	uniform int MODE <
		ui_type = "combo";
		ui_items = "Zenteon LC\0Laplacian\0Saturation Boost\0Unsharp\0";
		ui_label = "Enhancement Mode";
		ui_tooltip = "Contrast enhancement method used.";
	> = 0;
	
	uniform float KERNEL_SHAPE <
		ui_type = "drag";
		ui_min = 0.0;
		ui_max = 1.0;
		ui_label = "Detail Precision";
		ui_tooltip = "Lower values effect larger areas, higher values affect finer details";
	> = 0.5;
	
	uniform float INTENSITY <
		ui_type = "drag";
		ui_min = -1.0;
		ui_max = 1.0;
		ui_label = "Texture Detail";
	> = 0.5;
	
	//Legitimately just threw the weights for exposure fusion with a different scheme for reducing haloing
	//Not remotely as good, but it's cheap and works better than inverting "obscurance"
	uniform float FUSION <
		ui_type = "drag";
		ui_min = 0.0;
		ui_max = 1.0;
		ui_label = "Highlight/Shadow Detail";
		ui_tooltip = "Enhances detail in over and underexposed regions";
	> = 0.0;
	
	uniform int DEBUG <
		ui_type = "combo";
		ui_items = "None\0Image Difference\0Mask Difference\0Gradient\0Blur\0";
		ui_label = "Debug";
	> = 0;
	#define DMULT 0.5
	#define TEX_FORMAT R16
	
	namespace QLC0 {
		texture BlurTex0  { DIVRES(2); Format = TEX_FORMAT; };
		texture BlurTex1  { DIVRES(2); Format = TEX_FORMAT; };
		
		texture DownTex0 { DIVRES(4); Format = TEX_FORMAT; };
		texture DownTex1 { DIVRES(8); Format = TEX_FORMAT; };
		texture DownTex2 { DIVRES(16); Format = TEX_FORMAT; };
		texture DownTex3 { DIVRES(32); Format = TEX_FORMAT; };
		texture DownTex4 { DIVRES(64); Format = TEX_FORMAT; };
		texture DownTex5 { DIVRES(128); Format = TEX_FORMAT; };
		texture DownTex6 { DIVRES(256); Format = TEX_FORMAT; };
	
		texture UpTex5 { DIVRES(128); Format = TEX_FORMAT; };
		texture UpTex4 { DIVRES(64); Format = TEX_FORMAT; };
		texture UpTex3 { DIVRES(32); Format = TEX_FORMAT; };
		texture UpTex2 { DIVRES(16); Format = TEX_FORMAT; };
		texture UpTex1 { DIVRES(8); Format = TEX_FORMAT; };
		texture UpTex0 { DIVRES(4); Format = TEX_FORMAT; };
	
		sampler BlurSam0  { Texture = BlurTex0;  };
		sampler BlurSam1  { Texture = BlurTex1;  };
		
		sampler DownSam0 { Texture = DownTex0; };
		sampler DownSam1 { Texture = DownTex1; };
		sampler DownSam2 { Texture = DownTex2; };
		sampler DownSam3 { Texture = DownTex3; };
		sampler DownSam4 { Texture = DownTex4; };
		sampler DownSam5 { Texture = DownTex5; };
		sampler DownSam6 { Texture = DownTex6; };
		
		sampler UpSam5 { Texture = UpTex5; };
		sampler UpSam4 { Texture = UpTex4; };
		sampler UpSam3 { Texture = UpTex3; };
		sampler UpSam2 { Texture = UpTex2; };
		sampler UpSam1 { Texture = UpTex1; };
		sampler UpSam0 { Texture = UpTex0; };
		
		//=============================================================================
		//Tonemappers
		//=============================================================================
		#define HDR_RED 1.05
		float3 Reinhardt(float3 x)
		{
			return HDR_RED * x / (x + 1.0);	
		}
		
		float3 IReinhardt(float3 x)
		{
			return -x / (x - HDR_RED);
		}
		
		//=============================================================================
		//Functions
		//=============================================================================
		#define OFF 1.0
		float DUSample(sampler input, float2 xy, float div)//0.375 + 0.25
		{
		    float2 hp = 2.0 * div * rcp(RES);
		   
		  
			float acc;
			
			acc += 0.03125 * tex2D(input, xy + float2(-hp.x, hp.y)).x;
			acc += 0.0625 * tex2D(input, xy + float2(0, hp.y)).x;
			acc += 0.03125 * tex2D(input, xy + float2(hp.x, hp.y)).x;
			
			acc += 0.0625 * tex2D(input, xy + float2(-hp.x, 0)).x;
			acc += 0.125 * tex2D(input, xy + float2(0, 0)).x;
			acc += 0.0625 * tex2D(input, xy + float2(hp.x, 0)).x;
			
			acc += 0.03125 * tex2D(input, xy + float2(-hp.x, -hp.y)).x;
			acc += 0.0625 * tex2D(input, xy + float2(0, -hp.y)).x;
			acc += 0.03125 * tex2D(input, xy + float2(hp.x, -hp.y)).x;
		  
			acc += 0.125 * tex2D(input, xy + 0.5 * float2(hp.x, hp.y)).x;
			acc += 0.125 * tex2D(input, xy + 0.5 * float2(hp.x, -hp.y)).x;
			acc += 0.125 * tex2D(input, xy + 0.5 * float2(-hp.x, hp.y)).x;
			acc += 0.125 * tex2D(input, xy + 0.5 * float2(-hp.x, -hp.y)).x;
			
		    return acc;
		
		}
		
		float GetLum(float3 x)
		{
			if(MODE == 0) return dot(x, float3(0.2126, 0.7152, 0.0722));
			if(MODE == 2) return dot(x, float3(0.2126, 0.7152, 0.0722));
			if(MODE == 1) return dot(x, float3(0.2126, 0.7152, 0.0722));
			if(MODE == 3) return dot(x, float3(0.2126, 0.7152, 0.0722));
			if(MODE == 4) return dot(x, float3(0.2126, 0.7152, 0.0722));
			if(MODE == 5) return dot(x, float3(0.2126, 0.7152, 0.0722));
			return 0.0;
		}
		
		float IGN(float2 xy)
		{
		    float3 conVr = float3(0.06711056, 0.00583715, 52.9829189);
		    return frac( conVr.z * frac(dot(xy,conVr.xy)) );
		}\
		
		//=============================================================================
		//Down Passes
		//=============================================================================
		float Lum(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			float3 col = pow(tex2D(ReShade::BackBuffer, xy).rgb, 2.2);
			col = GetLum(col);
			float dither = (IGN(vpos.xy) - 0.5) * exp2(-8);
			return saturate(col.r + dither);
		}
		
		
		float4 Down0(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return DUSample(BlurSam0, xy, 2.0);
		}
		
		float Down1(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return DUSample(DownSam0, xy, 4.0);
		}
		
		float Down2(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return DUSample(DownSam1, xy, 8.0);
		}
		
		float Down3(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return DUSample(DownSam2, xy, 16.0);
		}
		
		float Down4(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return DUSample(DownSam3, xy, 32.0);
		}
		
		float Down5(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return DUSample(DownSam4, xy, 64.0);
		}
		
		float Down6(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return DUSample(DownSam5, xy, 128.0);
		}
		
		//=============================================================================
		//Up Passes
		//=============================================================================
		
		//Not actually normalized anymore but the difference is almost 0
		#define coef00 lerp(0.354123, 0.2997328570, KERNEL_SHAPE)
		#define coef0  lerp(0.083186, 0.2332857140, KERNEL_SHAPE)
		#define coef1  lerp(0.086834, 0.1592857140, KERNEL_SHAPE)
		#define coef2  lerp(0.085278, 0.1301857140, KERNEL_SHAPE)
		#define coef3  lerp(0.078681, 0.0772857143, KERNEL_SHAPE)
		#define coef4  lerp(0.067094, 0.0460000000, KERNEL_SHAPE)
		#define coef5  lerp(0.047540, 0.0199085714, KERNEL_SHAPE)
		#define coef6  lerp(0.197264, 0.0170000000, KERNEL_SHAPE)
		
		
		#define KS sqrt(1.0 - KERNEL_SHAPE)
		
		float Up5(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return coef5 * tex2D(DownSam5, xy).x + coef6 * DUSample(DownSam6, xy, 64.0);
		}
		
		float Up4(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return coef4 * tex2D(DownSam4, xy).x + DUSample(UpSam5, xy, 32.0);
		}
		
		float Up3(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return coef3 * tex2D(DownSam3, xy).x + DUSample(UpSam4, xy, 16.0);
		}
		
		float Up2(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return coef2 * tex2D(DownSam2, xy).x + DUSample(UpSam3, xy, 8.0);
		}
		
		float Up1(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return coef1 * tex2D(DownSam1, xy).x + DUSample(UpSam2, xy, 4.0);
		}
		
		float Up0(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return coef0 * tex2D(DownSam0, xy).x + DUSample(UpSam1, xy, 2.0);
		}
		
		float Up00(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return coef00 * tex2D(BlurSam0, xy).x + DUSample(UpSam0, xy, 2.0);
		}
		
		//=============================================================================
		//Blend Passes
		//=============================================================================
		
		float4 ReExpose(float4 x, float mult)
		{
			x = saturate(x);
			x *= x;
			x = max(-x/(x-1.01), 0.0);
			x *= mult;
			x = 1.0 * x / (x + 1.0);
			return sqrt(x);
		}
		
		float4 GetOptimalFusedLC(float4 col_l)
		{
			float4 acc;
			float accw;
			[unroll]
			for(int i; i <= 4; i++)
			{
				//range is between 0.1 and infinity
				float exVal = 0.35 + 2*i*i;//pow(1.5, i) - 0.75;
				float4 tVal = ReExpose(col_l, exVal);
				float tLum = sqrt( dot(tVal.rgb * tVal.rgb, float3(0.2126, 0.7152, 0.0722)) );
				float w = 0.01 + dot(tLum - tVal.a, tLum - tVal.a) / (tLum + 0.01);
				w *= exp( -12.5 * (tVal.a - 0.5) * (tVal.a - 0.5));
				float cmax = max(max(tVal.r, tVal.g), tVal.b);
				float cmin = min(min(tVal.r, tVal.g), tVal.b);
				w *= 0.01 + (cmax - cmin) / (cmin + 0.01);
				
				acc += tVal * w;
				accw += w;
			}
			return acc / accw;
		}
		
		float3 QuarkLC(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			float dither = (IGN(vpos.xy) - 0.5) / exp2(BUFFER_COLOR_BIT_DEPTH);
			float3 input = tex2D(ReShade::BackBuffer, xy).rgb;
			input = saturate(input + dither);
			
			float lum = pow(GetLum(pow(input, 2.2)), rcp(2.2));
			float3 nCol = input / lum;
			
			
			
			float blum = pow(DUSample(BlurSam0, xy, 2.0), rcp(2.2)) + dither;
			float3 icopy = input;
			
			float blur = pow(tex2D(BlurSam1, xy).r, rcp(2.2)) + dither;
			
			
			
			//Bootleg exposure fusion
			float4 fusion = GetOptimalFusedLC( saturate(float4(input, blur )) );
			input = lerp(input, fusion.rgb, 0.9 * FUSION);
			blur = lerp(blur, fusion.a, 0.9 * FUSION);
			
			
			input = IReinhardt(input);
			//s curve gradient for dehaloing
			float grad = sqrt(abs(blur - lum));
			
			grad = grad * grad * grad * (grad * (6.0 * grad - 15.0) + 10.0);
			//grad = grad*grad*(3.0-2.0*grad);
			//grad = sqrt(grad);//pow(grad, rcp(2.2));
			
			
			float3 tempI = Reinhardt(input);
			
			float tempINT = INTENSITY;
			if(DEBUG) tempINT = 1.0;
			
			//laplacian
			if(MODE == 1) input = input + INTENSITY * 2.0 * (lum*lum - blur*blur);

			//input -= 3.0 * tempINT * input * (sqrt(blur) - sqrt(0.5 * lum + 0.5 * blum));
			//obscurance
			if(MODE == 4) input *= lerp(1.0, (1.5 + pow(1.0 - KERNEL_SHAPE, 2.0)) * blur, tempINT);
			//ZN_LC
			if(MODE == 2) input += sqrt(1.0 - blur) * tempINT * (input - blur);
			
		
			
			//QuarkLC
			if(MODE == 0) 
			{
				float3 detail = (1.0 - sqrt(abs(blur - lum)) * sign(blur - lum));
				input = Reinhardt(input);
				float3 detail2 = input * (detail);
				
				float3 screen = pow(input, 0.5 + input);
				detail = lerp(detail2, screen, input);
				input = lerp(input, detail, clamp(0.8 * tempINT, -0.8, 0.8));
			}
			else
			{
				input = Reinhardt(input);
			}
			
			
			//unsharp
			if(MODE == 3)
			{
				float neg = 1.0 - blur;
				float3 pos = -input / (input - 1.01);
				pos = pos * (0.5 + neg);
				pos /= (pos + 1.0);
				input = lerp(input, pos, INTENSITY);
			}
			//input = lerp(input * (1.0 - tempINT * blur), 1.0 - lerp(1.0, blur, tempINT) * (1.0 - input), pow(tempI, 2.2));
			
			if(MODE == 5)
			{	
				input = max(-input / (input - 1.01), 0.0);
				input /= 0.0 + 3.0 * blur;
				input /= input + 1.01;
			}
			//Reduce haloing
			input = lerp(input, icopy, grad);
			
			
			if(DEBUG == 1) input = sqrt(2.0 * abs(input - INTENSITY * tempI));
			if(DEBUG == 2) input = sqrt(distance(INTENSITY * blur, input));
			if(DEBUG == 3) input = grad;
			if(DEBUG == 4) input = blur;
			
			
			return saturate(input + dither);
		}
		
		technique ZenLC <
		ui_label = "Zenteon: Local Contrast";
		    ui_tooltip =        
		        "								   Zenteon: Local Contrast           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nQuark LC is an all in one local contrast enhancement shader"
		        "\nIt features methods to enhance small scale details, highlights, and image graduation"
		        "\n"
		        "\n=================================================================================================";
		>	
		{
			pass {	VertexShader = PostProcessVS; PixelShader = Lum; RenderTarget0 = BlurTex0;} 
			pass {	VertexShader = PostProcessVS; PixelShader = Down0; RenderTarget = DownTex0; } 
			pass {	VertexShader = PostProcessVS; PixelShader = Down1; RenderTarget = DownTex1; }
			pass {	VertexShader = PostProcessVS; PixelShader = Down2; RenderTarget = DownTex2; } 
			pass {	VertexShader = PostProcessVS; PixelShader = Down3; RenderTarget = DownTex3; }
			pass {	VertexShader = PostProcessVS; PixelShader = Down4; RenderTarget = DownTex4; }
			pass {	VertexShader = PostProcessVS; PixelShader = Down5; RenderTarget = DownTex5; }
			pass {	VertexShader = PostProcessVS; PixelShader = Down6; RenderTarget = DownTex6; }
			
			pass {	VertexShader = PostProcessVS; PixelShader = Up5; RenderTarget = UpTex5;} 
			pass {	VertexShader = PostProcessVS; PixelShader = Up4; RenderTarget = UpTex4;} 
			pass {	VertexShader = PostProcessVS; PixelShader = Up3; RenderTarget = UpTex3;} 
			pass {	VertexShader = PostProcessVS; PixelShader = Up2; RenderTarget = UpTex2;}
			pass {	VertexShader = PostProcessVS; PixelShader = Up1; RenderTarget = UpTex1;} 
			pass {	VertexShader = PostProcessVS; PixelShader = Up0; RenderTarget = UpTex0; }
			pass {	VertexShader = PostProcessVS; PixelShader = Up00; RenderTarget = BlurTex1; }
			
			pass
			{
				VertexShader = PostProcessVS;
				PixelShader = QuarkLC;
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
		
	technique Quark_LC <
		ui_label = "Zenteon: Local Contrast";
		    ui_tooltip =        
		        "								   Zenteon: Local Contrast           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nQuark LC is an all in one local contrast enhancement shader"
		        "\nIt features methods to enhance small scale details, highlights, and image graduation"
		        "\n"
		        "\n=================================================================================================";
		>	
	{ }
#endif
