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
	Zenteon: Crystallis v0.2 - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/
//========================================================================

	

#if(__RENDERER__ != 0x9000)

	#ifndef GRAIN_QUALITY
	//============================================================================================
		#define GRAIN_QUALITY 0
	//============================================================================================
	#endif

	#include "ReShade.fxh"
	#include "ZenteonCommon.fxh"
	
	#define LP int(1.0 + (pow(1.0 - INTENSITY, 2.0) * 256 ))
	

	#define DISPATCH_DIM(X, Y, DIS_RESX, DIS_RESY) DispatchSizeX = DIV_RND_UP(DIS_RESX, X); DispatchSizeY = DIV_RND_UP(DIS_RESY, Y)
	
	
	uniform int FRAME_COUNT <
		source = "framecount";>;
	
	#define FRAME_MOD (ANIMT_GRAIN * (FRAME_COUNT % 64) + 1)
	
	uniform float INTENSITY <
		ui_type = "drag";
		ui_min = 0.0;
		ui_max = 1.0;
		ui_label = "Intensity";
	> = 0.8;
	
	uniform float GRAIN_SIZE <
		ui_type = "drag";
		ui_min = 0.0;
		ui_max = 2.0;
		ui_label = "Grain Size\n\n";
	> = 0.8;
	
	uniform float IMG_SAT <
		ui_type = "drag";
		ui_min = 0.0;
		ui_max = 1.0;
		ui_label = "Saturation";
	> = 1.0;
	
	uniform float GRAIN_SAT <
		ui_type = "drag";
		ui_min = 0.0;
		ui_max = 1.0;
		//ui_step = 1;
		ui_label = "Grain Saturation";
	> = 0.0;
	
	uniform int ANIMT_GRAIN <
		ui_label = "Animated Grain";
		ui_type = "slider";
		ui_min = 0;
		ui_max = 1;
	> = 0;
	
	namespace FFG {
		texture GrainTex { Width = RES.x; Height = RES.y; Format = RGBA8; };
		sampler GrainSam { Texture = GrainTex; };
		
		//Not a huge fan of LUT based, may take a crack at it later on 
		//texture2D tGrainLUT { Width = 256; Height = 512; Format = R16; };
		//sampler2D sGrainLUT { Texture = tGrainLUT; WRAPMODE(CLAMP); };
		//storage2D cGrainLUT { Texture = tGrainLUT; };
		
		//=============================================================================
		//Functions
		//=============================================================================
		
		float4 tex2DLhdr(sampler tex, float4 data)
		{
			float4 c = saturate(tex2Dlod(tex, data));
			//c *= c;
			return pow(c, 2.2);//-c / (c - 1.05);
		}
		
		float4 UpSample(sampler input, float2 xy, float offset)
		{
		    float2 hp = 0.6667 / RES;
			float4 acc;// = 4.0 * tex2DLhdr(input, float4(xy, 0, 0) ); 
		    
		    acc += tex2DLhdr(input, float4(xy - hp * offset, 0, 0));
		    acc += tex2DLhdr(input, float4(xy + hp * offset, 0, 0));
		    acc += tex2DLhdr(input, float4(xy + float2(hp.x, -hp.y) * offset, 0, 0));
		    acc += tex2DLhdr(input, float4(xy - float2(hp.x, -hp.y) * offset, 0, 0));
			
		    return acc / 4.0;
		}
		
		
		float4 hash42(float2 inp)
		{
		    uint pg = asuint(RES.x * RES.x * inp.y + inp.x * RES.x);
		    uint state = pg * 747796405u + 2891336453u;
		    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
		    uint4 RGBA = 0xFFu & word >> uint4(0,8,16,24); 
		    return float4(RGBA) / 0xFFu;
		}
		
		float4 lhash42(uint pg)
		{
		    uint state = pg * 747796405u + 2891336453u;
		    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
		    uint4 RGBA = 0xFFu & word >> uint4(0,8,16,24); 
		    return float4(RGBA) / 0xFFu;
		}
		
		float4 NormalInvCDFApprox(float4 x)
		{
			float4 g = 2.0 * x - 1.0;
			float4 g4 = g*g;
			g4 = g4*g4;
			float4 g8 = g4*g4;
			float4 g12 = g8 * g4;
			return 0.22222 * g + 0.5 + 0.13889 * g * (g4 + g12);
		}
		
		void rand_lcg(inout uint3 rand)
		{
		    rand = 1664525u * rand + 1013904223u;
		}
		
		void rand_lcg4(inout uint4 rand)
		{
		    rand = 1664525u * rand + 1013904223u;
		}
		
		
		void halfrand_lcg(inout min16uint3 rand)
		{
		    rand = 25u * rand + 15471u;
		}
		
		//=============================================================================
		//Passes
		//=============================================================================
		/*
		void GenLUTCS(CS_INPUTS)
		{
			float4 IC = pow( (id.y + 1) / 128.0, 1.0) * exp2(32);
			float4 IN = lhash42(id.y) * exp2(32);
			float4 iv;
			for(int i = 0; i < 256; i++)
			{
				iv += step(IN, IC);
				float4 piv = pow(iv / (i + 1.0), rcp(1.0));
				tex2Dstore(cGrainLUT, int2(i, id.y + 000), piv.r);
				tex2Dstore(cGrainLUT, int2(i, id.y + 128), piv.g );
				tex2Dstore(cGrainLUT, int2(i, id.y + 256), piv.b );
				tex2Dstore(cGrainLUT, int2(i, id.y + 384), piv.a );
				rand_lcg4(IN);
			}
		}
		*/
		
		float4 GenGrain(PS_INPUTS) : SV_Target
		{
			float3 input = pow(GetBackBuffer(xy), 2.2);//floor(128 * GetBackBuffer(xy)) / 128.0;
			
			/*
			int xp = 1.0 + (1.0 - INTENSITY) * 25.0;
			
			float4 noise = hash42(vpos.xy);
			
			noise = 128 * floor(noise * 4.0);// / 3.0;// * round(noise * 3.0);// * floor(noise * 3.0);
			*/
			//float4 RN = float4(abs(noise.r - float4(0.125, 0.375, 0.625, 0.875)) < 0.125);
			//float4 GN = float4(abs(noise.g - float4(0.125, 0.375, 0.625, 0.875)) < 0.125);
			//float4 BN = float4(abs(noise.b - float4(0.125, 0.375, 0.625, 0.875)) < 0.125);
			
			//float R = dot(tex2D(sGrainLUT, float2(INTENSITY, input.r) ) * RN, 1.0);
			//float G = dot(tex2D(sGrainLUT, float2(INTENSITY, input.g) ) * GN, 1.0);
			//float B = dot(tex2D(sGrainLUT, float2(INTENSITY, input.b) ) * BN, 1.0);
			//float3 rgb;
			//rgb.r = tex2Dfetch(sGrainLUT, float2(xp, 128 * input.r + noise.r - 1)).x;
			//rgb.g = tex2Dfetch(sGrainLUT, float2(xp, 128 * input.g + noise.g - 1)).x;
			//rgb.b = tex2Dfetch(sGrainLUT, float2(xp, 128 * input.b + noise.b - 1)).x;
			
			//return float4(rgb, 1.0);
			
			//return pow(1.0 - float4(R, G, B, 1.0), rcp(2.2));
				
			uint pg = uint(RES.x * RES.x * xy.y + xy.x * RES.x);
			float4 noise = lhash42((FRAME_MOD) * pg);
			noise.rgb = lerp(noise.a, noise.rgb, GRAIN_SAT);
			input = lerp(GetLuminance(input), input, IMG_SAT);
			//noise = NormalInvCDFApprox(noise);
			
			uint3 IP = exp2(32) * input;
			uint3 IN = exp2(32) * noise.rgb;
			
			
			#if(GRAIN_QUALITY > 0)
				
				int TLP = 0.5 + 0.5 * (noise.a + LP);
				float4 acc;
				[loop]
				for(int i; i < TLP; i++)
				{
					acc.rgb += step(IP, IN);
					halfrand_lcg(IN);
				}
				return pow(lerp(1.0 - acc / TLP, float4(input, 1.0), pow(1.0 - INTENSITY, 2.0) ), rcp(2.2));
			#else
				int TLP = 1.0 + 0.5 * LP;
				return float4( pow(floor(input * TLP + noise.rgb) / TLP, rcp(2.2)), 1.0);
			#endif
		}
		
		
		float3 QUARK_FILMGRAIN(PS_INPUTS) : SV_Target
		{
			float2 nxy = xy + GRAIN_SIZE * (hash42(FRAME_MOD * xy + 0.5).zw - 0.5) / RES;
			float3 grain = UpSample(GrainSam, nxy, 0.5 * saturate(GRAIN_SIZE) ).rgb;
			return pow(grain, rcp(2.2));
		}
		
		technique Crystallis <
		ui_label = "Zenteon: Crystallis";
		    ui_tooltip =        
		        "								   Zenteon: Crystallis           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nCrystallis is a unique approach to filmgrain"
		        "\nbuilt around using quantization to simulate subpixel binaries"
		        "\n"
		        "\n=================================================================================================";
		>	
		{
			//fastest seems to be 1x32
			//pass { ComputeShader = GenLUTCS<1,32>; DISPATCH_DIM(1,32,1,128); }
			pass
			{
				VertexShader = PostProcessVS;
				PixelShader = GenGrain;
				RenderTarget = GrainTex;
			}
			pass
			{
				VertexShader = PostProcessVS;
				PixelShader = QUARK_FILMGRAIN;
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
		
	technique Crystallis <
		ui_label = "Zenteon: Crystallis";
		    ui_tooltip =        
		        "								   Zenteon: Crystallis           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nCrystallis is a unique approach to filmgrain"
		        "\nbuilt around using quantization to simulate subpixel binaries"
		        "\n"
		        "\n=================================================================================================";
		>	
	{}
#endif	
	