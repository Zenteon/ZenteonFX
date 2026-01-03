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

uniform float INTENSITY <
	ui_type = "drag";
	ui_label = "Sharpening Intensity";
	ui_min = 0.0;
	ui_max = 2.0;
> = 1.0;

uniform float DEHALO <
	ui_type = "drag";
	ui_label = "Dehaloing Intensity";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.6;

uniform bool SHOW_WEIGHTS <
	ui_label = "Show Weights";
> = 0;

namespace ZenSharpen {
	
	//=======================================================================================
	//Textures/Samplers
	//=======================================================================================
	
	texture2D tLum { DIVRES(1); Format = R8; };
	sampler2D sLum { Texture = tLum; };
	
	texture2D tLap { DIVRES(1); Format = R8; };
	sampler2D sLap { Texture = tLap; };
	
	
	//=======================================================================================
	//Functions
	//=======================================================================================
	
	static const float2 spos8[8] = {
		float2(-1,-1), float2(0,-1), float2(1,-1),
		float2(-1,0), 			  float2(1,0),
		float2(-1,1), float2(0,1), float2(1,1) };
	
	
	static const float2 spos4[4] = {
		float2(0,-1),
		float2(-1,0), 			  float2(1,0),
		float2(0,1), };
	
	float4 GetLaplacian(sampler2D tex, float2 xy)
	{
	    float2 ip = rcp(RES);
		float4 acc = float4(GetBackBuffer(xy), 1.0);
		acc.a = 4.0 * GetLuminance(acc.rgb);
		for(int i = 0; i < 4; i++)
		{
			float2 nxy = xy + spos4[i] * ip;
			float t = tex2D(tex, nxy).x;
			acc.a -= t;
		}
		acc.a /= 4.0;
	    return acc;
	}
	
	float TL(sampler2D tex, float2 xy)
	{
		return tex2Dlod(tex, float4(xy,0,0)).x;
	}
	
	float GetLap4(sampler2D tex, float2 xy, float add)
	{
		float acc = 4.0 * (TL(tex, xy) + add);
		
		float2 hp = 0.5 * rcp(RES);
		
		acc -= TL(tex, xy + float2( 1, 1)*hp) + add;
		acc -= TL(tex, xy + float2( 1,-1)*hp) + add;
		acc -= TL(tex, xy + float2(-1, 1)*hp) + add;
		acc -= TL(tex, xy + float2(-1,-1)*hp) + add;
		
		return 0.25 * acc;
	}
	
	float2 WeightLap(float lap)
	{
		float w = exp(-exp2(2.0 + 6.0 * DEHALO) * lap*lap);
		return float2(lap * w, w);
	}
	
	//=======================================================================================
	//Passes
	//=======================================================================================
	
	float StoreLumPS(PS_INPUTS) : SV_Target
	{
		float3 t = GetBackBuffer(xy);
		t.x = GetLuminance(t);
		return t.y;
	}
	
	//=======================================================================================
	//Blending
	//=======================================================================================
	
	float GetLapPS(PS_INPUTS) : SV_Target
	{
		return 0.5 + INTENSITY * GetLap4(sLum, xy, 0.0);
	}
	
	float3 BlendPS(PS_INPUTS) : SV_Target
	{
		/*
		float4 data = GetLaplacian(sLum, xy);
		float2 data2 = WeightLap(data.a);
		return SHOW_WEIGHTS ? float3(1.0 - data2.y, 5.0*data.a, 0.0) : data.rgb + INTENSITY * data2.x;
		*/
		
		float3 c = GetBackBuffer(xy);
		float lap = tex2D(sLap, xy).x - 0.5;
		float halo = 2.0 * abs(GetLap4(sLap, xy, -0.5));
		
		//halo = (1.0 - saturate(2.0 * sqrt(DEHALO * halo)));
		halo = WeightLap(halo).y;
		
		return SHOW_WEIGHTS ? float3(-lap, lap, 1.0 - halo) : c + lap * halo;
	}
	
	technique ZenSharpen <
		ui_label = "Zenteon: Sharpen";
		    ui_tooltip =        
		        "								  	 Zenteon - Sharpen           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nA dead simple sharpening shader that maximizes detail and minimizes halos"
		        "\n"
		        "\n=================================================================================================";
		>	
	{
		pass {	PASS1(StoreLumPS, tLum); }
		pass {	PASS1(GetLapPS, tLap); }
		pass {	PASS0(BlendPS); }
	}
}
