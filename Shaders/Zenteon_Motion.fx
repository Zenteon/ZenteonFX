#include "ReShade.fxh"
#include "ZenteonCommon.fxh"




//stablize debug
uniform float FRAME_TIME < source = "frametime"; >;
uniform int FRAME_COUNT < source = "framecount";>;
			
#define PYFILT LINEAR
#define MVFILT LINEAR
#define GSFILT LINEAR
#define PWRAP CLAMP


#ifndef SHOW_DEBUG
//============================================================================================
	#define SHOW_DEBUG 0
//============================================================================================
#endif

texture texMotionVectors { DIVRES(1); Format = RG16F; };
sampler sMV { Texture = texMotionVectors; };
texture tDOC { DIVRES(1); Format = R8; };
sampler sDOC { Texture = tDOC; };

namespace TinyMV2 {
	
	//=======================================================================================
	//Textures/Samplers
	//=======================================================================================
	
	texture2D tBN < source = "ZenteonBN.png"; >{ Width = 512; Height = 512; Format = RGBA8; };
	sampler2D sBN { Texture = tBN; };
	
	texture2D tCG0 { DIVRES(1); Format = R16; };
	sampler2D sCG0 { Texture = tCG0; FILTER(GSFILT); };
	texture2D tCG1 { DIVRES(2); Format = R16; };
	sampler2D sCG1 { Texture = tCG1; FILTER(GSFILT); };
	texture2D tCG2 { DIVRES(4); Format = R16; };
	sampler2D sCG2 { Texture = tCG2; FILTER(GSFILT); };
	texture2D tCG3 { DIVRES(8); Format = R16; };
	sampler2D sCG3 { Texture = tCG3; FILTER(GSFILT); };
	texture2D tCG4 { DIVRES(16); Format = R16; };
	sampler2D sCG4 { Texture = tCG4; FILTER(GSFILT); };
	texture2D tCG5 { DIVRES(32); Format = R16; };
	sampler2D sCG5 { Texture = tCG5; FILTER(GSFILT); };
	texture2D tCG6 { DIVRES(64); Format = R16; };
	sampler2D sCG6 { Texture = tCG6; FILTER(GSFILT); };
	texture2D tCG7 { DIVRES(128); Format = R16; };
	sampler2D sCG7 { Texture = tCG7; FILTER(GSFILT); };
	
	
	texture2D tCC0 { DIVRES(1); Format = RGBA8; };
	sampler2D sCC0 { Texture = tCC0; FILTER(PYFILT); WRAPMODE(PWRAP); };
	texture2D tCC1 { DIVRES(2); Format = RGBA8; };
	sampler2D sCC1 { Texture = tCC1; FILTER(PYFILT); WRAPMODE(PWRAP); };
	texture2D tCC2 { DIVRES(4); Format = RGBA8; };
	sampler2D sCC2 { Texture = tCC2; FILTER(PYFILT); WRAPMODE(PWRAP); };
	texture2D tCC3 { DIVRES(8); Format = RGBA8; };
	sampler2D sCC3 { Texture = tCC3; FILTER(PYFILT); WRAPMODE(PWRAP); };
	texture2D tCC4 { DIVRES(16); Format = RGBA8; };
	sampler2D sCC4 { Texture = tCC4; FILTER(PYFILT); WRAPMODE(PWRAP); };
	texture2D tCC5 { DIVRES(32); Format = RGBA8; };
	sampler2D sCC5 { Texture = tCC5; FILTER(PYFILT); WRAPMODE(PWRAP); };
	texture2D tCC6 { DIVRES(64); Format = RGBA8; };
	sampler2D sCC6 { Texture = tCC6; FILTER(PYFILT); WRAPMODE(PWRAP); };
	texture2D tCC7 { DIVRES(128); Format = RGBA8; };
	sampler2D sCC7 { Texture = tCC7; FILTER(PYFILT); WRAPMODE(PWRAP); };
	
	texture2D tPC0 { DIVRES(1); Format = RGBA8; };
	sampler2D sPC0 { Texture = tPC0; FILTER(PYFILT); WRAPMODE(PWRAP); };
	texture2D tPC1 { DIVRES(2); Format = RGBA8; };
	sampler2D sPC1 { Texture = tPC1; FILTER(PYFILT); WRAPMODE(PWRAP); };
	texture2D tPC2 { DIVRES(4); Format = RGBA8; };
	sampler2D sPC2 { Texture = tPC2; FILTER(PYFILT); WRAPMODE(PWRAP); };
	texture2D tPC3 { DIVRES(8); Format = RGBA8; };
	sampler2D sPC3 { Texture = tPC3; FILTER(PYFILT); WRAPMODE(PWRAP); };
	texture2D tPC4 { DIVRES(16); Format = RGBA8; };
	sampler2D sPC4 { Texture = tPC4; FILTER(PYFILT); WRAPMODE(PWRAP); };
	texture2D tPC5 { DIVRES(32); Format = RGBA8; };
	sampler2D sPC5 { Texture = tPC5; FILTER(PYFILT); WRAPMODE(PWRAP); };
	texture2D tPC6 { DIVRES(64); Format = RGBA8; };
	sampler2D sPC6 { Texture = tPC6; FILTER(PYFILT); WRAPMODE(PWRAP); };
	texture2D tPC7 { DIVRES(128); Format = RGBA8; };
	sampler2D sPC7 { Texture = tPC7; FILTER(PYFILT); WRAPMODE(PWRAP); };
	
	//MV P
	
	texture2D tMV0 { DIVRES(8); Format = RGBA16F; MipLevels = 4; };
	sampler2D sMV0 { Texture = tMV0; FILTER(MVFILT); };
	texture2D tMV1 { DIVRES(8); Format = RGBA16F; MipLevels = 4; };
	sampler2D sMV1 { Texture = tMV1; FILTER(MVFILT); };
	texture2D tMV2 { DIVRES(8); Format = RGBA16F; MipLevels = 4; };
	sampler2D sMV2 { Texture = tMV2; FILTER(MVFILT); };
	texture2D tMV3 { DIVRES(8); Format = RGBA16F; MipLevels = 4; };
	sampler2D sMV3 { Texture = tMV3; FILTER(MVFILT); };
	texture2D tMV4 { DIVRES(16); Format = RGBA16F; MipLevels = 4; };
	sampler2D sMV4 { Texture = tMV4; FILTER(MVFILT); };
	texture2D tMV5 { DIVRES(32); Format = RGBA16F; MipLevels = 4; };
	sampler2D sMV5 { Texture = tMV5; FILTER(MVFILT); };
	texture2D tMV6 { DIVRES(64); Format = RGBA16F; MipLevels = 4; };
	sampler2D sMV6 { Texture = tMV6; FILTER(MVFILT); };
	texture2D tMV7 { DIVRES(128); Format = RGBA16F; MipLevels = 4; };
	sampler2D sMV7 { Texture = tMV7; FILTER(MVFILT); };
	
	texture2D tMV0F { DIVRES(8); Format = RGBA16F; MipLevels = 7; };
	sampler2D sMV0F { Texture = tMV0F; FILTER(MVFILT); };
	texture2D tMV1F { DIVRES(8); Format = RGBA16F; };
	sampler2D sMV1F { Texture = tMV1F; FILTER(MVFILT); };
	texture2D tMV2F { DIVRES(8); Format = RGBA16F; };
	sampler2D sMV2F { Texture = tMV2F; FILTER(MVFILT); };
	texture2D tMV3F { DIVRES(8); Format = RGBA16F; };
	sampler2D sMV3F { Texture = tMV3F; FILTER(MVFILT); };
	texture2D tMV4F { DIVRES(16); Format = RGBA16F; };
	sampler2D sMV4F { Texture = tMV4F; FILTER(MVFILT); };
	texture2D tMV5F { DIVRES(32); Format = RGBA16F; };
	sampler2D sMV5F { Texture = tMV5F; FILTER(MVFILT); };
	texture2D tMV6F { DIVRES(64); Format = RGBA16F; };
	sampler2D sMV6F { Texture = tMV6F; FILTER(MVFILT); };
	texture2D tMV7F { DIVRES(128); Format = RGBA16F; };
	sampler2D sMV7F { Texture = tMV7F; FILTER(MVFILT); };
	
	texture2D tMVF { DIVRES(1); Format = RGBA16F; };
	sampler2D sMVF { Texture = tMVF; FILTER(POINT); };
	texture2D tMVF2 { DIVRES(1); Format = RG16F; };
	sampler2D sMVF2 { Texture = tMVF2; FILTER(POINT); };
	
	texture tTDOC { DIVRES(1); Format = R8; };
	sampler sTDOC { Texture = tTDOC; };
	
	//=======================================================================================
	//Functions
	//=======================================================================================
	
	float4 TL(sampler2D tex, float2 xy)
	{
		return tex2Dlod(tex, float4(saturate(xy),0,0));
	}

	
	float3 VecToCol(float2 v)
	{
	    float rad = length(v);
	    float a = atan2(-v.y, -v.x) / 3.14159265;
	
	    float fk = (a + 1.0) / 2.0 * 6.0;
	    int k0 = fk % 7;
	    int k1 = (k0 + 1) % 7;
	    float f = fk - k0;
	
	    float3 cols[7] = {
	        float3(1, 0, 0),
	        float3(1, 1, 0),
	        float3(0, 1, 0),
	        float3(0, 1, 1),
	        float3(0, 0, 1),
	        float3(1, 0, 1),
	        float3(1, 0, 0),
			};
	
	    float3 col0 = cols[k0];
	    float3 col1 = cols[k1];
	
	    float3 col = lerp(col0, col1, frac(f));
	    
	    float j = 0.666667 * rad;
	    float k = rad / (rad + 0.5);
	    float l = saturate(rad*rad);
		l = lerp(j,k,l);
		
	    
	    return any(isnan(col)) ? 0.0 : lerp(0.0, col, saturate(l));
	}
	//https://bartwronski.com/2022/03/07/fast-gpu-friendly-antialiasing-downsampling-filter/
	float DUSample(sampler input, float2 xy)
	{
		float2 its = rcp(tex2Dsize(input));
		float2 hp = 0.75777*its;
		float2 fp = 2.907*its;
		
		float acc; float4 t;
		float minD = 1.0;
		
		acc += 0.37487566 * tex2D(input, xy + float2( hp.x,  hp.y)).x;
		acc += 0.37487566 * tex2D(input, xy + float2( hp.x, -hp.y)).x;
		acc += 0.37487566 * tex2D(input, xy + float2(-hp.x,  hp.y)).x;
		acc += 0.37487566 * tex2D(input, xy + float2(-hp.x, -hp.y)).x;
		
		acc -= 0.12487566 * tex2D(input, xy + float2( 0   ,  fp.y)).x;
		acc -= 0.12487566 * tex2D(input, xy + float2( 0   , -fp.y)).x;
		acc -= 0.12487566 * tex2D(input, xy + float2( fp.x,  0   )).x;
		acc -= 0.12487566 * tex2D(input, xy + float2(-fp.x,  0   )).x;
	
		return acc;
	}
	
	static const int2 off8[8] = {
		int2(-1,-1), int2( 0,-1), int2( 1,-1), 
		int2(-1, 0), 			 int2( 1, 0), 
		int2(-1, 1), int2( 0, 1), int2( 1, 1) };
	
	float4 PreBlock(sampler2D tex, float2 xy)
	{
		float2 m = 1.5 * rcp(tex2Dsize(tex));
		
		return float4(
			TL(tex, xy + float2(-0.5,-0.5) * m).x,
			TL(tex, xy + float2(-0.5, 0.5) * m).x,
			TL(tex, xy + float2( 0.5,-0.5) * m).x,
			TL(tex, xy + float2( 0.5, 0.5) * m).x
		);
	}
	
	float Loss(float4 a, float4 b)
	{
		float c0 = dot(a*b,0.25);
		float c1 = dot(a,0.25);
		float c2 = dot(b,0.25);
		
		float cov = c0 - c1*c2;
		
		float vA = dot(a*a,0.25) - dot(a,0.25)*dot(a,0.25);
		float vB = dot(b*b,0.25) - dot(b,0.25)*dot(b,0.25);
		
		return dot(abs(a-b) / (a + b + 0.01),0.25);// / dot(a+b + 0.1,0.5);//0.5 - cov / (vA+vB+1e-6);
	}
	
	float4 median3(float4 a, float4 b, float4 c)
	{
	    return max(min(a, b), min(max(a, b), c));
	}
	
	float4 Median9(sampler2D tex, float2 xy)
	{
		float2 vpos = xy * tex2Dsize(tex);
	    float4 row0[3];
	    float4 row1[3];
	    float4 row2[3];
		int m = 2;
	
	    row0[0] = tex2Dfetch(tex, vpos + m*m*int2(-1, -1));
	    row0[1] = tex2Dfetch(tex, vpos + int2( 0, -1));
	    row0[2] = tex2Dfetch(tex, vpos + m*int2( 1, -1));
	    
	    row1[0] = tex2Dfetch(tex, vpos + m*int2(-1,  0));
	    row1[1] = tex2Dfetch(tex, vpos + m*int2( 0,  0));
	    row1[2] = tex2Dfetch(tex, vpos + m*int2( 1,  0));
	    
	    row2[0] = tex2Dfetch(tex, vpos + m*int2(-1,  1));
	    row2[1] = tex2Dfetch(tex, vpos + m*( 0,  1));
	    row2[2] = tex2Dfetch(tex, vpos + m*int2( 1,  1));
	
	    float4 m0 = median3(row0[0], row0[1], row0[2]);
	    float4 m1 = median3(row1[0], row1[1], row1[2]);
	    float4 m2 = median3(row2[0], row2[1], row2[2]);
	
	    float4 med = median3(m0, m1, m2);
	    return float4(med.rgb, med.a);
	}
	
	float4 Median5(sampler2D tex, float2 xy)
	{
		float2 ts = tex2Dsize(tex);
		float2 vpos = xy * ts;
		
		float4 data[5];
		
		data[0] = tex2Dfetch(tex, vpos + int2(0,0));
		
		data[1] = tex2Dfetch(tex, vpos + int2(1,0));
		data[2] = tex2Dfetch(tex, vpos + int2(-1,0));
		data[3] = tex2Dfetch(tex, vpos + int2(0,1));
		data[4] = tex2Dfetch(tex, vpos + int2(0,-1));
		
		float4 t0 = max( min(data[0], data[1]), min(data[2], data[3]) );
		float4 t1 = min( max(data[0], data[1]), max(data[2], data[3]) );
		
		float4 med = max( min(data[4], t0), min(t1,max(data[4], t0)) );
		
		return float4(med.rgb, med.a);
	}
	
	//=======================================================================================
	//Gaussian/Census Pyramid
	//=======================================================================================	
	
	float GenG0PS(PS_INPUTS) : SV_Target
	{
		float3 c = GetBackBuffer(xy);
		float M = max(c.r, max(c.g,c.b));
		float m = min(c.r, min(c.g,c.b));
		//(M-m) / (M + 0.1);//
		return M;//sqrt(dot(c*c,float3(0.2126,0.7152,0.0722)));//M - m;
	}
	float GenG1PS(PS_INPUTS) : SV_Target { return DUSample(sCG0, xy); }
	float GenG2PS(PS_INPUTS) : SV_Target { return DUSample(sCG1, xy); }
	float GenG3PS(PS_INPUTS) : SV_Target { return DUSample(sCG2, xy); }
	float GenG4PS(PS_INPUTS) : SV_Target { return DUSample(sCG3, xy); }
	float GenG5PS(PS_INPUTS) : SV_Target { return DUSample(sCG4, xy); }
	float GenG6PS(PS_INPUTS) : SV_Target { return DUSample(sCG5, xy); }
	float GenG7PS(PS_INPUTS) : SV_Target { return DUSample(sCG6, xy); }
	
	
	float4 ConC0PS(PS_INPUTS) : SV_Target { return PreBlock(sCG0, xy); }
	float4 ConC1PS(PS_INPUTS) : SV_Target { return PreBlock(sCG1, xy); }
	float4 ConC2PS(PS_INPUTS) : SV_Target { return PreBlock(sCG2, xy); }
	float4 ConC3PS(PS_INPUTS) : SV_Target { return PreBlock(sCG3, xy); }
	float4 ConC4PS(PS_INPUTS) : SV_Target { return PreBlock(sCG4, xy); }
	float4 ConC5PS(PS_INPUTS) : SV_Target { return PreBlock(sCG5, xy); }
	float4 ConC6PS(PS_INPUTS) : SV_Target { return PreBlock(sCG6, xy); }
	float4 ConC7PS(PS_INPUTS) : SV_Target { return PreBlock(sCG7, xy); }
	
	float4 CopC0PS(PS_INPUTS) : SV_Target { return tex2D(sCC0, xy); }
	float4 CopC1PS(PS_INPUTS) : SV_Target { return tex2D(sCC1, xy); }
	float4 CopC2PS(PS_INPUTS) : SV_Target { return tex2D(sCC2, xy); }
	float4 CopC3PS(PS_INPUTS) : SV_Target { return tex2D(sCC3, xy); }
	float4 CopC4PS(PS_INPUTS) : SV_Target { return tex2D(sCC4, xy); }
	float4 CopC5PS(PS_INPUTS) : SV_Target { return tex2D(sCC5, xy); }
	float4 CopC6PS(PS_INPUTS) : SV_Target { return tex2D(sCC6, xy); }
	float4 CopC7PS(PS_INPUTS) : SV_Target { return tex2D(sCC7, xy); }
	
	//=======================================================================================
	//Motion
	//=======================================================================================
	
	struct B2 {
		float4 a;
		float4 b;
	};
	
	B2 TL2(sampler2D tex, float2 xy)
	{
		float2 fp = rcp(tex2Dsize(tex));
		
		B2 o;
		o.a = TL(tex, xy + fp);
		o.b = TL(tex, xy - fp);
		return o;
	}
	
	float BLoss(B2 a, B2 b)
	{
		float err = Loss(a.a,b.a);
		err += Loss(a.b, b.b);
		return err;
	}
	
	float4 BM_Pre(sampler2D pre, sampler2D cur, float2 xy, float4 mv, int R)
	{
		float2 ts = tex2Dsize(cur);
		float2 its = 0.125 * rcp(ts);
		
		float4 di = tex2Dfetch(sBN, (xy*ts) % 512).xyzw;
		//di = frac(di + float2(0.754877666, 0.56984029099).xyxy * (FRAME_COUNT % 64));
		di = (2.0 * (di - 0.5));
		
		float4 C = TL(cur, xy);
		float4 P = TL(pre, xy);
		
		float err = 1000.0;
		float2 fmv = mv.xy;
		//naive full search
		for(int i = -R; i <= R; i++) for(int j = -R; j <= R; j++)
		{	
			float2 tmv = mv.xy + its*(float2(i,j) + di.xy);
			float2 nxy = xy + tmv;
			
			P = TL(pre, nxy);

			float terr =  Loss(C,P);
			
			[flatten]
			if(terr < err) {
				err = terr;
				fmv = tmv;
			}
		}
		
		err = 1000.0;
		float2 bmv = mv.zw;
		//naive full search
		
		P = TL(pre, xy);
		
		for(int i = -R; i <= R; i++) for(int j = -R; j <= R; j++)
		{	
			float2 tmv = mv.zw + its*(float2(i,j) + di.zw);
			float2 nxy = xy + tmv;
			
			C = TL(cur, nxy);

			float terr =  Loss(C,P);
			
			[flatten]
			if(terr < err) {
				err = terr;
				bmv = tmv;
			}
		}
		
		
		return float4(fmv,bmv);
	}
	
	float4 PreMV(sampler2D MV, sampler2D pre, sampler2D cur, float2 xy, float mult)
	{
		float2 ts = tex2Dsize(MV);
		float2 its = mult * rcp(ts);
		
		float4 cmv = tex2Dlod(MV, float4(xy,0,3) );
		float4 CF = TL(cur, xy);
		float4 PF = TL(pre, xy + cmv.xy);
		
		//backwards flow
		float4 CB = TL(pre, xy);
		float4 PB = TL(cur, xy + cmv.zw);
		
		float2 err = float2(Loss(CF,PF), Loss(CB,PB));
		float4 fmv = cmv;
		float2 f0 = xy;
		
		for(int i = -1; i <= 1; i++) for(int j = -1; j <= 1; j++)
		{
			//di = frac(di + float2(0.754877666, 0.56984029099)
			float2 nxy = xy + its*float2(i,j);
			float4 tmv = Median5(MV,nxy);//
			
			PF = TL(pre, xy + tmv.xy);
			PB = TL(cur, xy + tmv.zw);
			
			float2 terr = float2(Loss(CF,PF), Loss(CB,PB));
			
			[flatten]
			if(terr.x < err.x) {
				err.x = terr.x;
				fmv.xy = tmv.xy;
			}
			[flatten]
			if(terr.y < err.y) {
				err.y = terr.y;
				fmv.zw = tmv.zw;
			}
		}
	
		return fmv;//TL(MV, xy).xy; 
	}
	
	float4 MV7PS(PS_INPUTS) : SV_Target { return BM_Pre(sPC7, sCC7, xy, tex2Dlod(sMV0, float4(xy,0,5)), 3); }
	float4 MV6PS(PS_INPUTS) : SV_Target { return BM_Pre(sPC6, sCC6, xy, PreMV(sMV7, sPC6, sCC6, xy, 3.0), 3); }
	float4 MV5PS(PS_INPUTS) : SV_Target { return BM_Pre(sPC5, sCC5, xy, PreMV(sMV6, sPC5, sCC5, xy, 3.0), 3); }
	float4 MV4PS(PS_INPUTS) : SV_Target { return BM_Pre(sPC4, sCC4, xy, PreMV(sMV5, sPC4, sCC4, xy, 3.0), 2); }
	float4 MV3PS(PS_INPUTS) : SV_Target { return BM_Pre(sPC3, sCC3, xy, PreMV(sMV4F, sPC3, sCC3, xy, 3.0), 1); }
	float4 MV2PS(PS_INPUTS) : SV_Target { return BM_Pre(sPC2, sCC2, xy, PreMV(sMV3F, sPC2, sCC2, xy, 3.0), 1); }
	float4 MV1PS(PS_INPUTS) : SV_Target { return BM_Pre(sPC1, sCC1, xy, PreMV(sMV2F, sPC1, sCC1, xy, 3.0), 1); }
	float4 MV0PS(PS_INPUTS) : SV_Target { return BM_Pre(sPC0, sCC0, xy, PreMV(sMV1F, sPC0, sCC0, xy, 3.0), 1); }

	//MV filtering
	static const int2 off4[4] = { int2(1,0), int2(0,1), int2(-1,0), int2(0,-1) };
	float4 FilterMV(sampler2D tex, float2 xy)
	{
		
		float2 its = rcp(tex2Dsize(tex));
		float4 cenC = TL(tex,xy);
		float4 minC = 1000.0, maxC = -1000.0;
		
		for(int i = 0; i < 4; i++)
		{
			float2 nxy = xy + off4[i]*its;
			
			float4 tmv = tex2D(tex, nxy);
			minC = min(minC, tmv);
			maxC = max(maxC, tmv);
			
		}
		float4 mv = clamp(cenC, minC, maxC);
		return tex2D(tex, xy);//mv;//float2( length(mv), atan2(mv.y, mv.x) );
		
	}
	
	float4 FilterMV2(sampler2D tex, sampler2D guide, float2 xy, float mult)
	{
		float cenG = TL(guide, xy).y;//minD
		float dz = fwidth(cenG);
		float2 ts = tex2Dsize(tex);
		float2 its = 1.0 * rcp(ts);
		
		//float2 cenMV = TL(tex, xy ).xy;
		//float2 cm2 = TL(tex, xy + cenMV).xy;
		//float dw = dot(normalize(cenMV), normalize(cm2));;
		//dw = isnan(dw) ? 1.0 : dw;
		
		float4 acc; float accw;
		for(int i = -1; i <= 1; i++) for(int j = -1; j <= 1; j++)
		{
			float2 nxy = xy + mult*its*float2(i,j);
			
			float samG =  TL(guide,(floor(nxy*ts)+0.5)*its).y;
			float4 samMV = TL(tex, nxy );
			//float4 sm2 = TL(tex, nxy + samMV).xy;
			
			float w = exp( -10.0 * abs(cenG - samG) / (dz + 0.01) );
			//float aw = dot(normalize(samMV), normalize(sm2));
			//w *= isnan(aw) ? 1.0 : aw + 1e-5;// / (dot(samMV, samMV) + 0.01) + 0.01;
			
			acc += samMV * w;
			accw += w;
		}
		
		float4 mv = acc / accw;
		return mv;
	}
	
	float4 FMV7APS(PS_INPUTS) : SV_Target { return FilterMV(sMV7, xy); }
	float4 FMV6APS(PS_INPUTS) : SV_Target { return FilterMV(sMV6, xy); }
	float4 FMV5APS(PS_INPUTS) : SV_Target { return FilterMV(sMV5, xy); }
	float4 FMV4APS(PS_INPUTS) : SV_Target { return FilterMV(sMV4, xy); }
	float4 FMV3APS(PS_INPUTS) : SV_Target { return FilterMV(sMV3, xy); }
	float4 FMV2APS(PS_INPUTS) : SV_Target { return FilterMV(sMV2, xy); }
	float4 FMV1APS(PS_INPUTS) : SV_Target { return FilterMV(sMV1, xy); }
	float4 FMV0APS(PS_INPUTS) : SV_Target { return FilterMV(sMV0, xy); }
	
	float4 FMV7BPS(PS_INPUTS) : SV_Target { return FilterMV2(sMV7F, sCG7, xy, 2.0); }
	float4 FMV6BPS(PS_INPUTS) : SV_Target { return FilterMV2(sMV6F, sCG6, xy, 2.0); }
	float4 FMV5BPS(PS_INPUTS) : SV_Target { return FilterMV2(sMV5F, sCG5, xy, 2.0); }
	float4 FMV4BPS(PS_INPUTS) : SV_Target { return FilterMV2(sMV4F, sCG4, xy, 2.0); }
	float4 FMV3BPS(PS_INPUTS) : SV_Target { return FilterMV2(sMV3F, sCG3, xy, 2.0); }
	float4 FMV2BPS(PS_INPUTS) : SV_Target { return FilterMV2(sMV2F, sCG2, xy, 4.0); }
	float4 FMV1BPS(PS_INPUTS) : SV_Target { return FilterMV2(sMV1F, sCG2, xy, 2.0); }
	float4 FMV0BPS(PS_INPUTS) : SV_Target { return FilterMV2(sMV0F, sCG2, xy, 1.0); }

	static const int2 off5[5] = { int2(0,0), int2(1,0), int2(0,1), int2(-1,0), int2(0,-1) };
	
	float4 FullMVPS(PS_INPUTS) : SV_Target
	{
		/*
		return PreMV(sMV0F, sPC0, sCC0, xy, 1.0);
		*/
		
		float2 its = rcp(tex2Dsize(sMV0F));
		
		float4 cmv = tex2Dlod(sMV0F, float4(xy,0,3) );
		float4 CF = TL(sCC0, xy);
		float4 PF = TL(sPC0, xy + cmv.xy);
		
		//backwards flow
		float4 CB = TL(sPC0, xy);
		float4 PB = TL(sCC0, xy + cmv.zw);
		
		float2 err = float2(Loss(CF,PF), Loss(CB,PB));
		float4 fmv = cmv;
		float2 f0 = xy;
		
		for(int i = 0; i < 5; i++)
		{
			//di = frac(di + float2(0.754877666, 0.56984029099)
			float2 nxy = xy + its*off5[i];
			float4 tmv = TL(sMV0F, nxy);//Median9(MV,nxy).xy;//
			
			PF = TL(sPC0, xy + tmv.xy);
			PB = TL(sCC0, xy + tmv.zw);
			
			float2 terr = float2(Loss(CF,PF), Loss(CB,PB));
			
			[flatten]
			if(terr.x < err.x) {
				err.x = terr.x;
				fmv.xy = tmv.xy;
			}
			[flatten]
			if(terr.y < err.y) {
				err.y = terr.y;
				fmv.zw = tmv.zw;
			}
		}
	
		return fmv;//TL(MV, xy).xy; 
		
	}
	
	float l2(float2 a)
	{
		return length(a);//dot(a,a);
	}
	
	void SwapMVPS(PS_INPUTS, out float2 o1 : SV_Target0, out float2 o2 : SV_Target1, out float doc : SV_Target2)
	{
		
		float4 MV = TL(sMVF, xy);
		
		float4 C = TL(sCC1, xy);
		float4 F = TL(sPC1, xy + MV.xy);
		float4 P = TL(sPC1, xy);
		float4 B = TL(sCC1, xy + MV.zw);
		
		float2 LS = float2( Loss(C,F), Loss(P,B) );
		
		float2 backV = TL(sMVF, xy - MV.xy / RES).zw;
		doc = rcp(l2(MV.xy - backV) / (l2(MV.xy) + 0.0005) + 1.0);
		doc = doc > 0.33;//all(abs(MV.xy) < 1.0) ? 1.0 : doc; 
		doc = round(doc - fwidth(doc));
		
		MV.xy = LS.x <= LS.y ? MV.xy : -MV.zw;
		doc *= all(abs(xy+MV.xy-0.5) <= 0.5);
		
		o1, o2 = MV.xy;
	}
	
	float DOC_PS(PS_INPUTS) : SV_Target
	{
		float a = 0.0;
		float2 hp = 0.5 / RES;
		
		
		a += tex2Dlod(sTDOC, float4(xy + float2( 1, 1)*hp,0,0)).x;
		a += tex2Dlod(sTDOC, float4(xy + float2( 1,-1)*hp,0,0)).x;
		a += tex2Dlod(sTDOC, float4(xy + float2(-1, 1)*hp,0,0)).x;
		a += tex2Dlod(sTDOC, float4(xy + float2(-1,-1)*hp,0,0)).x;
		
		return a >= 4.0;
	}
	
	//=======================================================================================
	//Blending
	//=======================================================================================
	
	
	float3 BlendPS(PS_INPUTS) : SV_Target
	{
		float2 its = rcp(RES);
		float2 MV = TL(sMV, xy).xy;
		
		MV *= rcp(FRAME_TIME);
		MV.xy *= 0.5 * RES;//normalize(MV.xy);
		
		//mvl = 2.0 * mvl * (mvl + 2.0 - sqrt(mvl*mvl + 4.0*mvl));
		
		//MV *= mvl;
		
		//MV = 4.0 * sign(MV) * (MV*MV+0.5*abs(MV)) / (MV*MV+0.5*abs(MV) + 0.002);
		
		return VecToCol(MV.xy);
	}
	
	technique ZenMV2 <
		ui_label = "Zenteon: Motion";
		   
		>	
	{
		//G/C pyramid
		pass ds0 {	PASS1(GenG0PS, tCG0); }
		pass ds1 {	PASS1(GenG1PS, tCG1); }
		pass ds2 {	PASS1(GenG2PS, tCG2); }
		pass ds3 {	PASS1(GenG3PS, tCG3); }
		pass ds4 {	PASS1(GenG4PS, tCG4); }
		pass ds5 {	PASS1(GenG5PS, tCG5); }
		pass ds6 {	PASS1(GenG6PS, tCG6); }
		pass ds7 {	PASS1(GenG7PS, tCG7); }
		
		pass pb0 {	PASS1(ConC0PS, tCC0); }
		pass pb1 {	PASS1(ConC1PS, tCC1); }
		pass pb2 {	PASS1(ConC2PS, tCC2); }
		pass pb3 {	PASS1(ConC3PS, tCC3); }
		pass pb4 {	PASS1(ConC4PS, tCC4); }
		pass pb5 {	PASS1(ConC5PS, tCC5); }
		pass pb6 {	PASS1(ConC6PS, tCC6); }
		pass pb7 {	PASS1(ConC7PS, tCC7); }
		
		//MV
		pass mv7{	PASS1(MV7PS, tMV7); }
		pass mv6{	PASS1(MV6PS, tMV6); }
		pass mv5{	PASS1(MV5PS, tMV5); }
		pass mv4{	PASS1(MV4PS, tMV4); }
		pass mv4_f{	PASS1(FMV4APS, tMV4F); }

		pass mv3{	PASS1(MV3PS, tMV3); }
		pass mv3_f{	PASS1(FMV3APS, tMV3F); }
		//pass {	PASS1(FMV3BPS, tMV3); }
		
		pass mv2{	PASS1(MV2PS, tMV2); }
		pass mv2_f{	PASS1(FMV2APS, tMV2F); }
		//pass {	PASS1(FMV2BPS, tMV2); }
		
		pass mv1{	PASS1(MV1PS, tMV1); }
		pass mv1_f{	PASS1(FMV1APS, tMV1F); }
		//pass {	PASS1(FMV1BPS, tMV1); }
		
		pass mv0{	PASS1(MV0PS, tMV0); }
		pass mv0_f{	PASS1(FMV0APS, tMV0F); }
		//pass {	PASS1(FMV0BPS, tMV0); }
		
		pass mvu{	PASS1(FullMVPS, tMVF); }
		pass mvs{	PASS3(SwapMVPS, tMVF2, texMotionVectors, tTDOC); }
		pass mvu{	PASS1(DOC_PS, tDOC); }
		
		#if(SHOW_DEBUG)
			pass dbg{	PASS0(BlendPS); }
		#endif
		//previous frame data
		
		pass cp0{	PASS1(CopC0PS, tPC0); }
		pass cp1{	PASS1(CopC1PS, tPC1); }
		pass cp2{	PASS1(CopC2PS, tPC2); }
		pass cp3{	PASS1(CopC3PS, tPC3); }
		pass cp4{	PASS1(CopC4PS, tPC4); }
		pass cp5{	PASS1(CopC5PS, tPC5); }
		pass cp6{	PASS1(CopC6PS, tPC6); }
		pass cp7{	PASS1(CopC7PS, tPC7); }
	}
}
