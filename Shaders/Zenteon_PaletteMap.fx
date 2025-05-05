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
	Zenteon: Palette Remap - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/
//========================================================================

#if(__RENDERER__ != 0x9000)

	#include "ReShade.fxh"
	//#include "QuarkCommon.fxh"
	#define RES (float2(BUFFER_WIDTH, BUFFER_HEIGHT))
	#define PS_INPUTS float4 vpos : SV_Position, float2 xy : TEXCOORD0
	#define GetBackBuffer(XY) (tex2Dlod(ReShade::BackBuffer, float4(XY, 0, 0)).rgb)
	#define GetLuminance(X) ( sqrt( 0.299*X.r*X.r + 0.587*X.g*X.g + 0.114*X.b*X.b ) )

	uniform int ERP_TYPE <
		ui_type = "combo";
		ui_items = "Catmull Rom\0Linear\0";
		hidden = true;
	> = 0;
	
	uniform bool PRESERVE_LUM < hidden = true; > = 1;

	uniform float  BLEND <
		ui_type = "drag";
		ui_label = "Blend";
		ui_min = 0.0;
		ui_max = 1.0;
		ui_category = "Blending";
	> = 1.0;

	uniform float  SELECTN <
		ui_type = "drag";
		ui_label = "Color Selectiveness";
		ui_min = 1.0;
		ui_max = 5.0;
		ui_category = "Blending";
	> = 1.5;
	
	uniform float PRESERVE_SAT < 
		ui_type = "drag";
		ui_label = "Chroma Preservation\n\n";
		ui_min = 0.0;
		ui_max = 1.0;
		ui_category = "Blending";
	> = 1.0;

	#define catP ui_category = "Palette"
	uniform float3 c0 < ui_type = "color"; ui_label = "Color 1"; catP; > = float3(1.0000, 0.6235, 0.54117);
	uniform float3 c1 < ui_type = "color"; ui_label = "Color 2"; catP; > = float3(0.9852, 0.7490, 0.1372);
	uniform float3 c2 < ui_type = "color"; ui_label = "Color 3"; catP; > = float3(1.0000, 0.6253, 0.2993);
	uniform float3 c3 < ui_type = "color"; ui_label = "Color 4"; catP; > = float3(0.7532, 0.3376, 0.3282);
	uniform float3 c4 < ui_type = "color"; ui_label = "Color 5"; catP; > = float3(0.2691, 0.1983, 0.3074);
	uniform float3 c5 < ui_type = "color"; ui_label = "Color 6"; catP; > = float3(0.1843, 0.1323, 0.2298);
	uniform float3 c6 < ui_type = "color"; ui_label = "Color 7"; catP; > = float3(0.0000, 0.0000, 0.0000);
	uniform float3 c7 < ui_type = "color"; ui_label = "Color 8\n\n"; catP; > = float3(0.0000, 0.0000, 0.0000);
	
	
	uniform int  CHROMA_QUANT <
		ui_type = "slider";
		ui_label = "Chroma Factor";
		ui_min = 16;
		ui_max = 255;
		hidden = true;
		ui_category = "Quantization";
	> = 255;\

	uniform int  HUE_QUANT <
		ui_type = "slider";
		ui_label = "Hue Factor";
		ui_min = 1;
		ui_max = 8;
		hidden = true;
		ui_category = "Quantization";
	> = 255;
	
	
	uniform bool DEBUG < ui_label = "Show Color Cube"; > = 0;
	
	//Fancy Debug Stuff
	uniform int frame_ct < source = "framecount"; >;
	uniform bool lmb_down < source = "mousebutton"; keycode = 0; mode = "press"; >;
	uniform float2 mouse_xy < source = "mousepoint"; >;
	
	namespace PaletteMap {
		
		texture tLUT32x { Width = 1024; Height = 32; Format = RGBA8; };
		
		//=====================================================================
		//Functions
		//=====================================================================
		
		float3 SRGBtoOKLAB(float3 c) 
		{
		    float l = 0.4122214708f * c.r + 0.5363325363f * c.g + 0.0514459929f * c.b;
			float m = 0.2119034982f * c.r + 0.6806995451f * c.g + 0.1073969566f * c.b;
			float s = 0.0883024619f * c.r + 0.2817188376f * c.g + 0.6299787005f * c.b;
		
		    float l_ = pow(l, 0.3334);
		    float m_ = pow(m, 0.3334);
		    float s_ = pow(s, 0.3334);
		
		   return float3(
		        0.2104542553f*l_ + 0.7936177850f*m_ - 0.0040720468f*s_,
		        1.9779984951f*l_ - 2.4285922050f*m_ + 0.4505937099f*s_,
		        0.0259040371f*l_ + 0.7827717662f*m_ - 0.8086757660f*s_);
		}
		
		float3 OKLABtoSRGB(float3 c) 
		{
		    float l_ = c.x + 0.3963377774f * c.y + 0.2158037573f * c.z;
		    float m_ = c.x - 0.1055613458f * c.y - 0.0638541728f * c.z;
		    float s_ = c.x - 0.0894841775f * c.y - 1.2914855480f * c.z;
		
		    float l = l_*l_*l_;
		    float m = m_*m_*m_;
		    float s = s_*s_*s_;
		
		    return float3(
				 4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s,
				-1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s,
				-0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s);
		}
		
		float ColorDistance(float3 x, float3 y)
		{
			x = SRGBtoOKLAB(x);
			y = SRGBtoOKLAB(y);
			return distance(x,y);
		}
		
		
		float3 Remap(float3 x)
		{
			float3 cp[10] = {0.0, 1.0, c0, c1, c2, c3, c4, c5, c6, c7};
			
			float3 acc;
			float accw;
			
			for(int i; i < 10; i++)
			{
				float3 temCol = cp[i];
				float temDis = ColorDistance(x, temCol);
				float w = exp( -10.0 * SELECTN * SELECTN * temDis * temDis ) + 0.000001;
				
				acc += temCol * w;
				accw += w;
				
			}
			
			return acc / accw;
		}
		
		//=====================================================================
		//The Magic
		//=====================================================================
		
		float3 NormalRemap(float3 x)
		{
			float3 c = Remap(x);
			
			x = SRGBtoOKLAB(x);
			c = SRGBtoOKLAB(c);
			
			//Lab to LCh
			float3 xLCh = float3( x.x, sqrt(x.y*x.y+x.z*x.z), atan2(x.z,x.y) );
			float3 cLCh = float3( c.x, sqrt(c.y*c.y+c.z*c.z), atan2(c.z,c.y) );
			
			//cLCh.y = PRESERVE_SAT ? xLCh.y : cLCh.y;
			cLCh.y = lerp(cLCh.y, xLCh.y, PRESERVE_SAT);
			
			
			cLCh.y = round(cLCh.y * CHROMA_QUANT) / CHROMA_QUANT;
			cLCh.z = round(cLCh.z * HUE_QUANT) / HUE_QUANT;
			
			//LCh to Lab
			x = float3( xLCh.x, xLCh.y * cos(xLCh.z), xLCh.y * sin(xLCh.z));
			c = float3( cLCh.x, cLCh.y * cos(cLCh.z), cLCh.y * sin(cLCh.z));
			
			//Lum preservation
			c = lerp(x, c, float3(0.0, BLEND.xx) );
			//c.x = x.x;
			
			x = OKLABtoSRGB(x);
			c = OKLABtoSRGB(c);
			
			return max(c, 0.0);
		}
		
		//=====================================================================
		//Raymarching
		//=====================================================================
		
		struct Ray {
			float3 pos;
			float3 vec;
		};
		
		float IGN(float2 xy)
		{
			xy += 5.68 * frame_ct;
			xy %= RES;
		    float3 conVr = float3(0.06711056, 0.00583715, 52.9829189);
		    return frac( conVr.z * frac(dot(xy,conVr.xy)) );
		}
		
		float3 CalcRayVectors(float3 cP, float3 cV, float2 uv)
		{
			//Normalized "Up" vector, incorrect to start but ensures correct camera orientation
			float3 cU = float3(0.0, -1.0, 0.0);
			float3 cR = cross(cV, cU);
				   cU = cross(cR, cV);
				   
			uv -= 0.5;
			uv *= 0.5;
			return ( uv.x * cR + uv.y * cU + cV );
		}
		
		float3 CalcCamPos(float2 mxy)
		{
			mxy = mxy;
			mxy *= 30.0;
			mxy *= 6.2831;
			float3 pos = float3( sin(mxy.x), cos(mxy.x), cos(mxy.y) );
			return 3.0 * (pos);
		}
		
		
		float3 RayMarch(float2 uv, float2 mxy, float2 vpos, bool og)
		{
		
			uv += 2.0 * (IGN(vpos.xy + 3.0) - 0.5) / RES;
			float3 camPos = CalcCamPos(mxy);
			float3 camVec = -normalize(camPos);
			float3 rayVec = CalcRayVectors(camPos, camVec, uv);
			
			float3 acc;
			
			float step = 0.014;
			//camPos += (1.0 + step * (0.5 + 1.0 * IGN(vpos)) ) * rayVec * 2.0;
			camPos += (1.0 + step * 2.0 * IGN(vpos) ) * rayVec * 2.5;
			//rayVec = camVec;
			
			for(int i; i <= 90; i++)
			{
				
				float3 tPos = camPos + rayVec * (step * pow(i, 1.1) + 0.0);
				
				float3 tCol = (0.5 + tPos.rgb);
				if(!og) tCol = lerp(tCol, NormalRemap(tCol), BLEND);
				tCol = pow(tCol, 2.2);//Linearish blending
				acc = all( abs(tPos - 0.0) < 0.5 ) ? acc + tCol : acc;	
			}
			acc /= 90.0;
			
			acc = -acc / (acc - 1.01);
			acc *= 4.0;
			acc = 1.01 * acc / (acc + 1.0);
			return pow(acc, 1.0 / 2.2);
		}
		
		//=====================================================================
		//Passes
		//=====================================================================
		
		float4 GenLutPS(PS_INPUTS) : SV_Target
		{
			vpos.xy -= 0.5;
			float3 lutPos = float3(vpos.xy % 32, floor(vpos.x / 32.0)) / 32.0;
			lutPos = lerp(lutPos, NormalRemap(lutPos), BLEND);
			return float4(lutPos, 1.0);
		}
		
		float3 RemapColorPS(PS_INPUTS) : SV_Target
		{
			float3 x = GetBackBuffer(xy);
			
			float3 c = NormalRemap(x);
			//if(distance(vpos.xy, mouse_xy) < 30.0) return 0.0;
			
			float AR = RES.x / RES.y;
			[branch]
			if(DEBUG && 1.0 - xy.x < 0.15 && xy.y < rcp(AR) )
			{
				xy.x = (1.0 - xy.x) / 0.15;	
				
				float2 mxy = float2(300, 1100);
				if(xy.y < 0.5 * rcp(AR) ) return RayMarch(xy * float2(1.0,2.0*AR), mxy, vpos.xy, 1);
				else return RayMarch(xy * float2(1.0, 2.0*AR) - float2(0,1), mxy, vpos.xy, 0);
			}
		
			//x = pow(x, 2.2);
			//x = SRGBtoOKLAB(x);
			
			//x.yz = 0.25 * x.yz;
			
			//x = OKLABtoSRGB(x);
			//x = pow(x, rcp(2.2));
		
			return c;//lerp(x, c, BLEND);
			
			
			
			
		}
		
		technique PaletteMap <
		ui_label = "Zenteon: Palette Remap";
		    ui_tooltip =        
		        "								   Zenteon: Palette Remap           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nRemaps an input image to match any color palette"
		        "\n"
		        "\n=================================================================================================";
		>	
		{
			pass
			{
				VertexShader = PostProcessVS;
				PixelShader = RemapColorPS;
			}
			
			pass
			{
				VertexShader = PostProcessVS;
				PixelShader = GenLutPS;
				RenderTarget = tLUT32x;
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
		
	technique PaletteMap <
		ui_label = "Zenteon: Palette Remap";
		    ui_tooltip =        
		        "								   Zenteon: Palette Remap           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nRemaps an input image to match any color palette"
		        "\n"
		        "\n=================================================================================================";
		>	
	{}
#endif	
	