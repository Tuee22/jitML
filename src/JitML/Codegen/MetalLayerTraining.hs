{-# LANGUAGE OverloadedStrings #-}

-- | Generated Metal program for typed layer-graph training.
--
-- The fixed host bridge compiles this MSL in-process with fast math disabled.
-- Each invocation dispatches one deterministic control thread: the operator
-- performs its reductions in explicit ascending-index order and writes the
-- forward value plus input/weight/bias gradients.  The deliberately serial
-- reference-grade launch is the correctness floor for the Apple lane; it keeps
-- the complete 'LayerOp' vocabulary on the host GPU without checking in native
-- kernel sources or substituting the pure Haskell oracle.
module JitML.Codegen.MetalLayerTraining
  ( metalLayerTrainingKernelSpec
  , metalLayerTrainingProgram
  , renderMetalLayerTrainingSource
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.Char (intToDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word8)

import JitML.Cache.Key (KernelSpec (..))
import JitML.Codegen.Metal (metalBridgeAbiVersion)
import JitML.Codegen.SourceFile (SourceFile (..))

metalLayerTrainingKernelSpec :: KernelSpec
metalLayerTrainingKernelSpec = KernelSpec "layer-graph-training-metal"

renderMetalLayerTrainingSource :: [SourceFile]
renderMetalLayerTrainingSource =
  [SourceFile "kernel.metal.json" metalLayerTrainingMetadata]

metalLayerTrainingMetadata :: Text
metalLayerTrainingMetadata =
  Text.unlines
    [ "{"
    , "  \"abi\": \"jitml-metal-source-v1\","
    , "  \"bridge_abi\": " <> jsonString metalBridgeAbiVersion <> ","
    , "  \"substrate\": \"apple-silicon\","
    , "  \"kernel_spec\": \"layer-graph-training-metal\","
    , "  \"kind\": \"training\","
    , "  \"tuning_choice\": \"default\","
    , "  \"family\": \"layer-graph-training-metal\","
    , "  \"functions\": { \"train\": \"jitml_layer_train\" },"
    , "  \"compile_options\": { \"fast_math\": false, \"math_mode\": \"safe\" },"
    , "  \"launch_policy\": \"single-control-thread-ascending-reductions\","
    , "  \"source_sha256\": " <> jsonString (sha256HexText metalLayerTrainingProgram) <> ","
    , "  \"source\": " <> jsonString metalLayerTrainingProgram
    , "}"
    ]

-- | One generated MSL program covering dense, spatial convolution, GeGLU,
-- normalization, patch embedding, multi-head attention, residual, pooling,
-- identity/dropout scale, and the block sub-primitives composed by the host.
metalLayerTrainingProgram :: Text
metalLayerTrainingProgram =
  Text.unlines
    [ "#include <metal_stdlib>"
    , "using namespace metal;"
    , ""
    , "inline float jitml_erf(float x) {"
    , "  float ax = fabs(x);"
    , "  float t = 1.0f / (1.0f + 0.3275911f * ax);"
    , "  float poly = (((((1.061405429f * t - 1.453152027f) * t) + 1.421413741f) * t - 0.284496736f) * t + 0.254829592f) * t;"
    , "  float value = 1.0f - poly * exp(-ax * ax);"
    , "  return x < 0.0f ? -value : value;"
    , "}"
    , "inline float jitml_gelu(float u) {"
    , "  return 0.5f * u * (1.0f + jitml_erf(u * 0.7071067811865476f));"
    , "}"
    , "inline float jitml_gelu_deriv(float u) {"
    , "  return 0.5f * (1.0f + jitml_erf(u * 0.7071067811865476f))"
    , "       + u * exp(-0.5f * u * u) * 0.3989422804014327f;"
    , "}"
    , "inline float jitml_act_fwd(int code, float z) {"
    , "  if (code == 1) { return tanh(z); }"
    , "  if (code == 2) { return z > 0.0f ? z : 0.0f; }"
    , "  return z;"
    , "}"
    , "inline float jitml_act_bwd(int code, float activated, float up) {"
    , "  if (code == 1) { return (1.0f - activated * activated) * up; }"
    , "  if (code == 2) { return activated > 0.0f ? up : 0.0f; }"
    , "  return up;"
    , "}"
    , ""
    , "inline void jitml_dense_train("
    , "    device float *out, device float *dx, device float *dw, device float *db,"
    , "    const device float *x, const device float *weights, const device float *bias,"
    , "    const device float *dy, int inputs, int outputs, int batch) {"
    , "  for (int n = 0; n < batch; ++n) {"
    , "    for (int o = 0; o < outputs; ++o) {"
    , "      float acc = bias[o];"
    , "      for (int i = 0; i < inputs; ++i) { acc += weights[o * inputs + i] * x[n * inputs + i]; }"
    , "      out[n * outputs + o] = acc;"
    , "    }"
    , "    for (int i = 0; i < inputs; ++i) {"
    , "      float acc = 0.0f;"
    , "      for (int o = 0; o < outputs; ++o) { acc += weights[o * inputs + i] * dy[n * outputs + o]; }"
    , "      dx[n * inputs + i] = acc;"
    , "    }"
    , "  }"
    , "  for (int o = 0; o < outputs; ++o) {"
    , "    float bacc = 0.0f;"
    , "    for (int n = 0; n < batch; ++n) { bacc += dy[n * outputs + o]; }"
    , "    db[o] = bacc;"
    , "    for (int i = 0; i < inputs; ++i) {"
    , "      float acc = 0.0f;"
    , "      for (int n = 0; n < batch; ++n) { acc += dy[n * outputs + o] * x[n * inputs + i]; }"
    , "      dw[o * inputs + i] = acc;"
    , "    }"
    , "  }"
    , "}"
    , ""
    , "inline void jitml_conv2d_train("
    , "    device float *out, device float *dx, device float *dw, device float *db,"
    , "    const device float *x, const device float *weights, const device float *bias,"
    , "    const device float *dy, const device int *g) {"
    , "  int cin=g[0], cout=g[1], h=g[2], w=g[3], kh=g[4], kw=g[5];"
    , "  int sh=g[6], sw=g[7], ph=g[8], pw=g[9], batch=g[10];"
    , "  int oh=(h+2*ph-kh)/sh+1, ow=(w+2*pw-kw)/sw+1;"
    , "  for (int n=0; n<batch; ++n) for (int co=0; co<cout; ++co) for (int oy=0; oy<oh; ++oy) for (int ox=0; ox<ow; ++ox) {"
    , "    float acc=bias[co];"
    , "    for (int ci=0; ci<cin; ++ci) for (int ky=0; ky<kh; ++ky) for (int kx=0; kx<kw; ++kx) {"
    , "      int iy=oy*sh+ky-ph, ix=ox*sw+kx-pw;"
    , "      if (iy>=0 && iy<h && ix>=0 && ix<w) {"
    , "        int xi=((n*cin+ci)*h+iy)*w+ix; int wi=((co*cin+ci)*kh+ky)*kw+kx;"
    , "        acc += x[xi]*weights[wi];"
    , "      }"
    , "    }"
    , "    out[((n*cout+co)*oh+oy)*ow+ox]=acc;"
    , "  }"
    , "  for (int n=0; n<batch; ++n) for (int ci=0; ci<cin; ++ci) for (int iy=0; iy<h; ++iy) for (int ix=0; ix<w; ++ix) {"
    , "    float acc=0.0f;"
    , "    for (int co=0; co<cout; ++co) for (int ky=0; ky<kh; ++ky) for (int kx=0; kx<kw; ++kx) {"
    , "      int yn=iy+ph-ky, xn=ix+pw-kx;"
    , "      if (yn>=0 && xn>=0 && yn%sh==0 && xn%sw==0) { int oy=yn/sh, ox=xn/sw;"
    , "        if (oy<oh && ox<ow) acc += weights[((co*cin+ci)*kh+ky)*kw+kx]*dy[((n*cout+co)*oh+oy)*ow+ox];"
    , "      }"
    , "    }"
    , "    dx[((n*cin+ci)*h+iy)*w+ix]=acc;"
    , "  }"
    , "  for (int co=0; co<cout; ++co) {"
    , "    float bacc=0.0f; for (int n=0; n<batch; ++n) for (int oy=0; oy<oh; ++oy) for (int ox=0; ox<ow; ++ox) bacc += dy[((n*cout+co)*oh+oy)*ow+ox]; db[co]=bacc;"
    , "    for (int ci=0; ci<cin; ++ci) for (int ky=0; ky<kh; ++ky) for (int kx=0; kx<kw; ++kx) {"
    , "      float acc=0.0f; for (int n=0; n<batch; ++n) for (int oy=0; oy<oh; ++oy) for (int ox=0; ox<ow; ++ox) {"
    , "        int iy=oy*sh+ky-ph, ix=ox*sw+kx-pw; if (iy>=0 && iy<h && ix>=0 && ix<w) acc += dy[((n*cout+co)*oh+oy)*ow+ox]*x[((n*cin+ci)*h+iy)*w+ix];"
    , "      }"
    , "      dw[((co*cin+ci)*kh+ky)*kw+kx]=acc;"
    , "    }"
    , "  }"
    , "}"
    , ""
    , "inline void jitml_conv3d_train("
    , "    device float *out, device float *dx, device float *dw, device float *db,"
    , "    const device float *x, const device float *weights, const device float *bias,"
    , "    const device float *dy, const device int *g) {"
    , "  int cin=g[0], cout=g[1], d=g[2], h=g[3], w=g[4], kd=g[5], kh=g[6], kw=g[7];"
    , "  int sd=g[8], sh=g[9], sw=g[10], pd=g[11], ph=g[12], pw=g[13], batch=g[14];"
    , "  int od=(d+2*pd-kd)/sd+1, oh=(h+2*ph-kh)/sh+1, ow=(w+2*pw-kw)/sw+1;"
    , "  for (int n=0;n<batch;++n) for(int co=0;co<cout;++co) for(int oz=0;oz<od;++oz) for(int oy=0;oy<oh;++oy) for(int ox=0;ox<ow;++ox){"
    , "    float acc=bias[co]; for(int ci=0;ci<cin;++ci) for(int kz=0;kz<kd;++kz) for(int ky=0;ky<kh;++ky) for(int kx=0;kx<kw;++kx){"
    , "      int iz=oz*sd+kz-pd, iy=oy*sh+ky-ph, ix=ox*sw+kx-pw; if(iz>=0&&iz<d&&iy>=0&&iy<h&&ix>=0&&ix<w){"
    , "        int xi=(((n*cin+ci)*d+iz)*h+iy)*w+ix; int wi=(((co*cin+ci)*kd+kz)*kh+ky)*kw+kx; acc+=x[xi]*weights[wi]; }}"
    , "    out[(((n*cout+co)*od+oz)*oh+oy)*ow+ox]=acc; }"
    , "  for(int n=0;n<batch;++n) for(int ci=0;ci<cin;++ci) for(int iz=0;iz<d;++iz) for(int iy=0;iy<h;++iy) for(int ix=0;ix<w;++ix){"
    , "    float acc=0.0f; for(int co=0;co<cout;++co) for(int kz=0;kz<kd;++kz) for(int ky=0;ky<kh;++ky) for(int kx=0;kx<kw;++kx){"
    , "      int zn=iz+pd-kz, yn=iy+ph-ky, xn=ix+pw-kx; if(zn>=0&&yn>=0&&xn>=0&&zn%sd==0&&yn%sh==0&&xn%sw==0){ int oz=zn/sd,oy=yn/sh,ox=xn/sw;"
    , "        if(oz<od&&oy<oh&&ox<ow) acc+=weights[(((co*cin+ci)*kd+kz)*kh+ky)*kw+kx]*dy[(((n*cout+co)*od+oz)*oh+oy)*ow+ox]; }}"
    , "    dx[(((n*cin+ci)*d+iz)*h+iy)*w+ix]=acc; }"
    , "  for(int co=0;co<cout;++co){ float bacc=0.0f; for(int n=0;n<batch;++n) for(int oz=0;oz<od;++oz) for(int oy=0;oy<oh;++oy) for(int ox=0;ox<ow;++ox) bacc+=dy[(((n*cout+co)*od+oz)*oh+oy)*ow+ox]; db[co]=bacc;"
    , "    for(int ci=0;ci<cin;++ci) for(int kz=0;kz<kd;++kz) for(int ky=0;ky<kh;++ky) for(int kx=0;kx<kw;++kx){ float acc=0.0f;"
    , "      for(int n=0;n<batch;++n) for(int oz=0;oz<od;++oz) for(int oy=0;oy<oh;++oy) for(int ox=0;ox<ow;++ox){ int iz=oz*sd+kz-pd,iy=oy*sh+ky-ph,ix=ox*sw+kx-pw;"
    , "        if(iz>=0&&iz<d&&iy>=0&&iy<h&&ix>=0&&ix<w) acc+=dy[(((n*cout+co)*od+oz)*oh+oy)*ow+ox]*x[(((n*cin+ci)*d+iz)*h+iy)*w+ix]; }"
    , "      dw[(((co*cin+ci)*kd+kz)*kh+ky)*kw+kx]=acc; }}"
    , "}"
    , ""
    , "inline void jitml_geglu_train(device float *out, device float *dx, device float *dw, device float *db, const device float *x, const device float *w, const device float *b, const device float *dy, const device int *g, device float *s) {"
    , "  int ni=g[0], nf=g[1], no=g[2]; device float *a=s,*z=s+nf,*gg=s+2*nf,*h=s+3*nf,*dh=s+4*nf,*da=s+5*nf,*dg=s+6*nf;"
    , "  int wa=0, wb=nf*ni, w2=2*nf*ni, ba=0, bb=nf, b2=2*nf;"
    , "  for(int j=0;j<nf;++j){ a[j]=b[ba+j]; z[j]=b[bb+j]; for(int i=0;i<ni;++i){ a[j]+=w[wa+j*ni+i]*x[i]; z[j]+=w[wb+j*ni+i]*x[i]; } gg[j]=jitml_gelu(z[j]); h[j]=a[j]*gg[j]; }"
    , "  for(int o=0;o<no;++o){ float v=b[b2+o]; for(int j=0;j<nf;++j)v+=w[w2+o*nf+j]*h[j]; out[o]=v; db[b2+o]=dy[o]; for(int j=0;j<nf;++j)dw[w2+o*nf+j]=dy[o]*h[j]; }"
    , "  for(int j=0;j<nf;++j){ dh[j]=0.0f; for(int o=0;o<no;++o)dh[j]+=w[w2+o*nf+j]*dy[o]; da[j]=dh[j]*gg[j]; dg[j]=dh[j]*a[j]*jitml_gelu_deriv(z[j]); db[ba+j]=da[j]; db[bb+j]=dg[j]; for(int i=0;i<ni;++i){dw[wa+j*ni+i]=da[j]*x[i];dw[wb+j*ni+i]=dg[j]*x[i];}}"
    , "  for(int i=0;i<ni;++i){float v=0.0f;for(int j=0;j<nf;++j)v+=w[wa+j*ni+i]*da[j]+w[wb+j*ni+i]*dg[j];dx[i]=v;}"
    , "}"
    , ""
    , "inline void jitml_norm_train(device float *out, device float *dx, device float *dw, device float *db, const device float *x, const device float *gamma, const device float *beta, const device float *dy, const device int *g, const device float *fp, int len, device float *s) {"
    , "  int flavor=g[0],channels=g[1],spatial=g[2],groups=g[3];float eps=fp[0];int ng=flavor==0?channels:(flavor==2?(groups>0?groups:1):1);"
    , "  device float *group=s,*mu=s+len,*var=mu+ng,*rstd=var+ng,*cnt=rstd+ng,*xhat=cnt+ng,*ghat=xhat+len,*meanG=ghat+len,*meanGX=meanG+ng;"
    , "  for(int q=0;q<ng;++q){mu[q]=0.0f;var[q]=0.0f;cnt[q]=0.0f;meanG[q]=0.0f;meanGX[q]=0.0f;}"
    , "  int gsz=(groups>0?channels/groups:channels);if(gsz<=0)gsz=1;for(int i=0;i<len;++i){int gi=flavor==1?0:(flavor==2?((i/spatial)/gsz):(i%channels));group[i]=float(gi);mu[gi]+=x[i];cnt[gi]+=1.0f;}"
    , "  for(int q=0;q<ng;++q)if(cnt[q]>0.0f)mu[q]/=cnt[q];for(int i=0;i<len;++i){int gi=int(group[i]);float d=x[i]-mu[gi];var[gi]+=d*d;}"
    , "  for(int q=0;q<ng;++q){if(cnt[q]>0.0f)var[q]/=cnt[q];rstd[q]=1.0f/sqrt(var[q]+eps);}"
    , "  for(int i=0;i<len;++i){int gi=int(group[i]);int c=flavor==0?(i%channels):(i/spatial);xhat[i]=(x[i]-mu[gi])*rstd[gi];out[i]=gamma[c]*xhat[i]+beta[c];ghat[i]=dy[i]*gamma[c];meanG[gi]+=ghat[i];meanGX[gi]+=ghat[i]*xhat[i];}"
    , "  for(int q=0;q<ng;++q)if(cnt[q]>0.0f){meanG[q]/=cnt[q];meanGX[q]/=cnt[q];}for(int i=0;i<len;++i){int gi=int(group[i]);dx[i]=rstd[gi]*(ghat[i]-meanG[gi]-xhat[i]*meanGX[gi]);}"
    , "  for(int c=0;c<channels;++c){dw[c]=0.0f;db[c]=0.0f;}for(int i=0;i<len;++i){int c=flavor==0?(i%channels):(i/spatial);dw[c]+=dy[i]*xhat[i];db[c]+=dy[i];}"
    , "}"
    , ""
    , "inline int jitml_patch_input_index(int patch,int k,const device int *g){int c=g[0],h=g[1],w=g[2],p=g[3],stride=g[4];int nx=(w-p)/stride+1;int py=patch/nx,px=patch%nx;int pixel=k/c,cc=k%c;int yy=py*stride+pixel/p,xx=px*stride+pixel%p;return(yy*w+xx)*c+cc;}"
    , "inline void jitml_patch_train(device float *out,device float *dx,device float *dw,device float *db,const device float *x,const device float *w,const device float *b,const device float *dy,const device int *g,int xlen){int c=g[0],h=g[1],ww=g[2],p=g[3],stride=g[4],d=g[5],cpp=c*p*p,np=((h-p)/stride+1)*((ww-p)/stride+1);"
    , "  for(int q=0;q<xlen;++q)dx[q]=0.0f;for(int o=0;o<d;++o){db[o]=0.0f;for(int k=0;k<cpp;++k)dw[o*cpp+k]=0.0f;}"
    , "  for(int patch=0;patch<np;++patch)for(int o=0;o<d;++o){float v=b[o];for(int k=0;k<cpp;++k)v+=w[o*cpp+k]*x[jitml_patch_input_index(patch,k,g)];out[patch*d+o]=v;db[o]+=dy[patch*d+o];for(int k=0;k<cpp;++k){int xi=jitml_patch_input_index(patch,k,g);dw[o*cpp+k]+=dy[patch*d+o]*x[xi];dx[xi]+=w[o*cpp+k]*dy[patch*d+o];}}}"
    , ""
    , "inline void jitml_attention_train(device float *out,device float *dx,device float *dw,device float *db,const device float *x,const device float *w,const device float *b,const device float *dy,const device int *g,device float *s){"
    , "  int n=g[0],d=g[1],heads=g[2],causal=g[3],dh=d/heads,dd=d*d,total=n*d;float sc=1.0f/sqrt(float(dh));"
    , "  device float *q=s,*k=q+total,*v=k+total,*c=v+total,*prob=c+total,*dc=prob+heads*n*n,*dq=dc+total,*dk=dq+total,*dv=dk+total;"
    , "  for(int t=0;t<n;++t)for(int o=0;o<d;++o){float qv=b[o],kv=b[d+o],vv=b[2*d+o];for(int j=0;j<d;++j){float xv=x[t*d+j];qv+=w[o*d+j]*xv;kv+=w[dd+o*d+j]*xv;vv+=w[2*dd+o*d+j]*xv;}q[t*d+o]=qv;k[t*d+o]=kv;v[t*d+o]=vv;}"
    , "  for(int hd=0;hd<heads;++hd)for(int i=0;i<n;++i){float mx=-3.402823466e+38f;for(int t=0;t<n;++t){float a=-3.402823466e+38f;if(causal==0||t<=i){a=0.0f;for(int e=0;e<dh;++e)a+=q[i*d+hd*dh+e]*k[t*d+hd*dh+e];a*=sc;}prob[(hd*n+i)*n+t]=a;if(a>mx)mx=a;}float den=0.0f;for(int t=0;t<n;++t){float a=prob[(hd*n+i)*n+t];float ex=(causal!=0&&t>i)?0.0f:exp(a-mx);prob[(hd*n+i)*n+t]=ex;den+=ex;}for(int t=0;t<n;++t)prob[(hd*n+i)*n+t]=den>0.0f?prob[(hd*n+i)*n+t]/den:1.0f/float(n);for(int e=0;e<dh;++e){float z=0.0f;for(int t=0;t<n;++t)z+=prob[(hd*n+i)*n+t]*v[t*d+hd*dh+e];c[i*d+hd*dh+e]=z;}}"
    , "  for(int i=0;i<n;++i)for(int o=0;o<d;++o){float z=b[3*d+o];for(int j=0;j<d;++j)z+=w[3*dd+o*d+j]*c[i*d+j];out[i*d+o]=x[i*d+o]+z;}"
    , "  for(int z=0;z<4*dd;++z)dw[z]=0.0f;for(int z=0;z<4*d;++z)db[z]=0.0f;for(int z=0;z<total;++z){dq[z]=0.0f;dk[z]=0.0f;dv[z]=0.0f;}"
    , "  for(int i=0;i<n;++i)for(int j=0;j<d;++j){float z=0.0f;for(int o=0;o<d;++o)z+=w[3*dd+o*d+j]*dy[i*d+o];dc[i*d+j]=z;}"
    , "  for(int o=0;o<d;++o){for(int i=0;i<n;++i)db[3*d+o]+=dy[i*d+o];for(int j=0;j<d;++j)for(int i=0;i<n;++i)dw[3*dd+o*d+j]+=dy[i*d+o]*c[i*d+j];}"
    , "  for(int hd=0;hd<heads;++hd){for(int t=0;t<n;++t)for(int e=0;e<dh;++e){float z=0.0f;for(int i=0;i<n;++i)z+=prob[(hd*n+i)*n+t]*dc[i*d+hd*dh+e];dv[t*d+hd*dh+e]=z;}"
    , "    for(int i=0;i<n;++i){float mean=0.0f;for(int t=0;t<n;++t){float dp=0.0f;for(int e=0;e<dh;++e)dp+=dc[i*d+hd*dh+e]*v[t*d+hd*dh+e];mean+=prob[(hd*n+i)*n+t]*dp;}for(int t=0;t<n;++t){float dp=0.0f;for(int e=0;e<dh;++e)dp+=dc[i*d+hd*dh+e]*v[t*d+hd*dh+e];float da=prob[(hd*n+i)*n+t]*(dp-mean);for(int e=0;e<dh;++e){dq[i*d+hd*dh+e]+=sc*da*k[t*d+hd*dh+e];dk[t*d+hd*dh+e]+=sc*da*q[i*d+hd*dh+e];}}}}"
    , "  for(int block=0;block<3;++block){device float *grad=block==0?dq:(block==1?dk:dv);int wo=block*dd,bo=block*d;for(int o=0;o<d;++o){for(int i=0;i<n;++i)db[bo+o]+=grad[i*d+o];for(int j=0;j<d;++j)for(int i=0;i<n;++i)dw[wo+o*d+j]+=grad[i*d+o]*x[i*d+j];}}"
    , "  for(int i=0;i<n;++i)for(int j=0;j<d;++j){float z=dy[i*d+j];for(int o=0;o<d;++o)z+=w[o*d+j]*dq[i*d+o]+w[dd+o*d+j]*dk[i*d+o]+w[2*dd+o*d+j]*dv[i*d+o];dx[i*d+j]=z;}"
    , "}"
    , ""
    , "inline void jitml_residual_train(device float *out,device float *dx,device float *dw,device float *db,const device float *x,const device float *w,const device float *b,const device float *dy,const device int *g,const device float *fp,device float *s){int ni=g[0],no=g[1],proj=g[2],inner=g[3],finalAct=g[4];float scale=fp[0];device float *z=s,*a=z+no,*sx=a+no,*yp=sx+no,*d=yp+no,*dp=d+no;int wp=no*ni,bp=no;"
    , "  for(int o=0;o<no;++o){z[o]=b[o];for(int i=0;i<ni;++i)z[o]+=w[o*ni+i]*x[i];a[o]=jitml_act_fwd(inner,z[o]);if(proj!=0){sx[o]=b[bp+o];for(int i=0;i<ni;++i)sx[o]+=w[wp+o*ni+i]*x[i];}else sx[o]=x[o];yp[o]=sx[o]+scale*a[o];out[o]=jitml_act_fwd(finalAct,yp[o]);d[o]=jitml_act_bwd(finalAct,out[o],dy[o]);dp[o]=scale*jitml_act_bwd(inner,a[o],d[o]);db[o]=dp[o];for(int i=0;i<ni;++i)dw[o*ni+i]=dp[o]*x[i];if(proj!=0){db[bp+o]=d[o];for(int i=0;i<ni;++i)dw[wp+o*ni+i]=d[o]*x[i];}}"
    , "  for(int i=0;i<ni;++i){float v0=0.0f;for(int o=0;o<no;++o)v0+=w[o*ni+i]*dp[o];if(proj==0)v0+=d[i];else for(int o=0;o<no;++o)v0+=w[wp+o*ni+i]*d[o];dx[i]=v0;}}"
    , ""
    , "inline void jitml_pool_train(device float *out,device float *dx,const device float *x,const device float *dy,const device int *g,int xlen){int algo=g[0],c=g[1],h=g[2],w=g[3],kh=g[4],kw=g[5],sh=g[6],sw=g[7],ph=g[8],pw=g[9],oh=(h+2*ph-kh)/sh+1,ow=(w+2*pw-kw)/sw+1;for(int i=0;i<xlen;++i)dx[i]=0.0f;"
    , "  for(int ch=0;ch<c;++ch)for(int oy=0;oy<oh;++oy)for(int ox=0;ox<ow;++ox){int oi=(ch*oh+oy)*ow+ox;float value=algo==0?-3.402823466e+38f:0.0f;int count=0,best=-1;for(int ky=0;ky<kh;++ky)for(int kx=0;kx<kw;++kx){int iy=oy*sh+ky-ph,ix=ox*sw+kx-pw;if(iy>=0&&iy<h&&ix>=0&&ix<w){int xi=(ch*h+iy)*w+ix;float xv=x[xi];if(algo==0){if(best<0||xv>value){value=xv;best=xi;}}else value+=xv;count++;}}if(algo!=0)value/=float(algo==2?kh*kw:count);out[oi]=value;if(algo==0){if(best>=0)dx[best]+=dy[oi];}else{float den=float(algo==2?kh*kw:count);for(int ky=0;ky<kh;++ky)for(int kx=0;kx<kw;++kx){int iy=oy*sh+ky-ph,ix=ox*sw+kx-pw;if(iy>=0&&iy<h&&ix>=0&&ix<w)dx[(ch*h+iy)*w+ix]+=dy[oi]/den;}}}}"
    , ""
    , "inline void jitml_scale_train(device float *out,device float *dx,const device float *x,const device float *dy,int n,float scale){for(int i=0;i<n;++i){out[i]=scale*x[i];dx[i]=scale*dy[i];}}"
    , ""
    , "kernel void jitml_layer_train("
    , "    device float *out [[buffer(0)]], device float *dx [[buffer(1)]],"
    , "    device float *dw [[buffer(2)]], device float *db [[buffer(3)]],"
    , "    const device float *x [[buffer(4)]], const device float *weights [[buffer(5)]],"
    , "    const device float *bias [[buffer(6)]], const device float *dy [[buffer(7)]],"
    , "    const device int *geom [[buffer(8)]], const device float *fparams [[buffer(9)]],"
    , "    device float *scratch [[buffer(10)]], device int *status [[buffer(11)]],"
    , "    constant int &opcode [[buffer(12)]], constant int &xlen [[buffer(13)]],"
    , "    uint gid [[thread_position_in_grid]]) {"
    , "  if (gid != 0u) { return; } status[0]=0;"
    , "  switch(opcode){"
    , "    case 0: jitml_dense_train(out,dx,dw,db,x,weights,bias,dy,geom[0],geom[1],geom[2]); break;"
    , "    case 1: jitml_conv2d_train(out,dx,dw,db,x,weights,bias,dy,geom); break;"
    , "    case 2: jitml_conv3d_train(out,dx,dw,db,x,weights,bias,dy,geom); break;"
    , "    case 10: jitml_geglu_train(out,dx,dw,db,x,weights,bias,dy,geom,scratch); break;"
    , "    case 11: jitml_norm_train(out,dx,dw,db,x,weights,bias,dy,geom,fparams,xlen,scratch); break;"
    , "    case 12: jitml_patch_train(out,dx,dw,db,x,weights,bias,dy,geom,xlen); break;"
    , "    case 13: jitml_attention_train(out,dx,dw,db,x,weights,bias,dy,geom,scratch); break;"
    , "    case 14: jitml_residual_train(out,dx,dw,db,x,weights,bias,dy,geom,fparams,scratch); break;"
    , "    case 15: jitml_pool_train(out,dx,x,dy,geom,xlen); break;"
    , "    case 16: jitml_scale_train(out,dx,x,dy,xlen,fparams[0]); break;"
    , "    default: status[0]=1; break;"
    , "  }"
    , "}"
    ]

jsonString :: Text -> Text
jsonString value = "\"" <> Text.concatMap escape value <> "\""

escape :: Char -> Text
escape '"' = "\\\""
escape '\\' = "\\\\"
escape '\n' = "\\n"
escape '\r' = "\\r"
escape '\t' = "\\t"
escape char = Text.singleton char

sha256HexText :: Text -> Text
sha256HexText =
  Text.pack . concatMap byteHex . ByteString.unpack . SHA256.hash . Text.Encoding.encodeUtf8
 where
  byteHex :: Word8 -> String
  byteHex byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]
