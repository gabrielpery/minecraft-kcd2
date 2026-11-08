// Executes the actual pinned ReShade FX compiler output on headless D3D11 WARP.
// No game, swapchain, window, input injection, or duplicate reprojection kernel.
#include "effect_codegen.hpp"
#include "effect_parser.hpp"
#include "effect_preprocessor.hpp"
#include "world_reprojection.hpp"
#include <d3d11.h>
#include <dxgi.h>
#include <wrl/client.h>
#include <filesystem>
#include <iostream>
#include <memory>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>
#include <chrono>
#include <cstring>

using Microsoft::WRL::ComPtr;
namespace fx=reshadefx;
namespace {
unsigned checks=0;
void check(bool ok,const std::string &why){++checks;if(!ok)throw std::runtime_error(why);}
void hr(HRESULT value,const char *what){if(FAILED(value))throw std::runtime_error(std::string(what)+" HRESULT="+std::to_string(static_cast<unsigned long>(value)));}
struct pixel {float r,g,b,a;};
constexpr pixel background{.05f,.1f,.15f,1.f};
bool same(pixel a,pixel b,float e=.002f){return std::abs(a.r-b.r)<e&&std::abs(a.g-b.g)<e&&std::abs(a.b-b.b)<e&&std::abs(a.a-b.a)<e;}
constexpr pixel red{1,0,0,1},blue{0,0,1,1},green{0,1,0,1};
constexpr std::uint32_t red8=0xff0000ff,blue8=0xffff0000,green8=0xff00ff00;
struct texture {ComPtr<ID3D11Texture2D> object;ComPtr<ID3D11ShaderResourceView> srv;ComPtr<ID3D11RenderTargetView> rtv;};
D3D11_BLEND blend(fx::blend_factor v){
 switch(v){case fx::blend_factor::zero:return D3D11_BLEND_ZERO;case fx::blend_factor::one:return D3D11_BLEND_ONE;
 case fx::blend_factor::source_color:return D3D11_BLEND_SRC_COLOR;case fx::blend_factor::one_minus_source_color:return D3D11_BLEND_INV_SRC_COLOR;
 case fx::blend_factor::dest_color:return D3D11_BLEND_DEST_COLOR;case fx::blend_factor::one_minus_dest_color:return D3D11_BLEND_INV_DEST_COLOR;
 case fx::blend_factor::source_alpha:return D3D11_BLEND_SRC_ALPHA;case fx::blend_factor::one_minus_source_alpha:return D3D11_BLEND_INV_SRC_ALPHA;
 case fx::blend_factor::dest_alpha:return D3D11_BLEND_DEST_ALPHA;case fx::blend_factor::one_minus_dest_alpha:return D3D11_BLEND_INV_DEST_ALPHA;}
 throw std::runtime_error("unsupported actual FX blend factor");
}
struct effect {
 unsigned width,height;float tanx;
 std::unique_ptr<fx::codegen> backend;
 ComPtr<ID3D11Device> device;ComPtr<ID3D11DeviceContext> context;
 ComPtr<ID3D11Buffer> constants;ComPtr<ID3D11RasterizerState> raster;ComPtr<ID3D11DepthStencilState> no_depth;
 std::map<std::string,texture> textures;texture target;
 std::map<std::string,ComPtr<ID3D11VertexShader>> vertex;
 std::map<std::string,ComPtr<ID3D11PixelShader>> fragment;
 std::vector<ComPtr<ID3D11SamplerState>> samplers;
 std::vector<std::byte> uniforms;
 std::vector<std::uint32_t> atlas;
 std::vector<float> host_depth;
 texture make_texture(unsigned w,unsigned h,DXGI_FORMAT format,bool output){
  texture t;D3D11_TEXTURE2D_DESC d{};d.Width=w;d.Height=h;d.MipLevels=1;d.ArraySize=1;d.Format=format;d.SampleDesc.Count=1;d.Usage=D3D11_USAGE_DEFAULT;
  d.BindFlags=D3D11_BIND_SHADER_RESOURCE|(output?D3D11_BIND_RENDER_TARGET:0);hr(device->CreateTexture2D(&d,nullptr,&t.object),"texture");
  hr(device->CreateShaderResourceView(t.object.Get(),nullptr,&t.srv),"SRV");if(output)hr(device->CreateRenderTargetView(t.object.Get(),nullptr,&t.rtv),"RTV");return t;
 }
 effect(const std::filesystem::path &path,unsigned w,unsigned h,bool production,D3D_DRIVER_TYPE driver=D3D_DRIVER_TYPE_WARP):width(w),height(h),tanx(float(w)/h),atlas(std::size_t(w)*h*3),host_depth(std::size_t(w)*h,1.f){
  fx::preprocessor pp;pp.add_include_path(path.parent_path());
  for(const auto &[name,value]:std::map<std::string,std::string>{{"__RESHADE__","60800"},{"__RESHADE_PERMUTATION__","0"},{"__RESHADE_PERFORMANCE_MODE__","0"},{"__RENDERER__","45056"},{"BUFFER_WIDTH",std::to_string(w)},{"BUFFER_HEIGHT",std::to_string(h)},{"BUFFER_RCP_WIDTH","(1.0 / BUFFER_WIDTH)"},{"BUFFER_RCP_HEIGHT","(1.0 / BUFFER_HEIGHT)"},{"BUFFER_COLOR_BIT_DEPTH","8"},{"BUFFER_COLOR_SPACE","1"}})pp.add_macro_definition(name,value);
  if(!production){pp.add_macro_definition("MINECOME_WORLD_SOURCE_WIDTH",std::to_string(w));pp.add_macro_definition("MINECOME_WORLD_SOURCE_HEIGHT",std::to_string(h));}
  const bool preprocessed=pp.append_file(path);check(preprocessed,"FX preprocessing: "+pp.errors());
  backend.reset(fx::create_codegen_dxbc(50,false,false,1));fx::parser parser;
  const bool parsed=parser.parse(pp.output(),backend.get());check(parsed,"actual FX parsing: "+parser.errors());
  const auto &m=backend->module();check(m.techniques.size()==2&&m.techniques[0].name=="MineComeWorldWarp"&&m.techniques[1].name=="MineComeHud","actual warp-before-HUD technique order");
  check(m.techniques[0].passes.size()==2&&m.techniques[0].passes[0].num_vertices==w*h*6,"actual source-grid draw count");
  D3D_FEATURE_LEVEL level{};const D3D_FEATURE_LEVEL requested=D3D_FEATURE_LEVEL_11_0;
  hr(D3D11CreateDevice(nullptr,driver,nullptr,0,&requested,1,D3D11_SDK_VERSION,&device,&level,&context),"headless D3D11 device");
  for(const auto &[name,type]:m.entry_points){std::string code,assembly,errors;check(backend->assemble_code_for_entry_point(name,code,assembly,errors),"actual FX DXBC "+name+": "+errors);
   if(type==fx::shader_type::vertex)hr(device->CreateVertexShader(code.data(),code.size(),nullptr,&vertex[name]),"actual FX vertex shader");
   else if(type==fx::shader_type::pixel)hr(device->CreatePixelShader(code.data(),code.size(),nullptr,&fragment[name]),"actual FX pixel shader");else throw std::runtime_error("unexpected FX stage");}
  for(const auto &t:m.textures){
   if(t.semantic.rfind("MINECOME_HUD_",0)==0)textures[t.unique_name]=make_texture(w,h*3,DXGI_FORMAT_R8G8B8A8_UNORM,false);
   else if(t.semantic=="DEPTH")textures[t.unique_name]=make_texture(w,h,DXGI_FORMAT_R32_FLOAT,false);
   else{check(t.semantic.empty()&&t.width==w&&t.height==h,"actual internal target dimensions");textures[t.unique_name]=make_texture(t.width,t.height,static_cast<DXGI_FORMAT>(t.format),true);}}
  target=make_texture(w,h,DXGI_FORMAT_R32G32B32A32_FLOAT,true);
  for(const auto &s:m.samplers){D3D11_SAMPLER_DESC d{};d.Filter=static_cast<D3D11_FILTER>(s.filter);d.AddressU=static_cast<D3D11_TEXTURE_ADDRESS_MODE>(s.address_u);d.AddressV=static_cast<D3D11_TEXTURE_ADDRESS_MODE>(s.address_v);d.AddressW=static_cast<D3D11_TEXTURE_ADDRESS_MODE>(s.address_w);d.MinLOD=s.min_lod;d.MaxLOD=s.max_lod;d.MipLODBias=s.lod_bias;d.MaxAnisotropy=1;d.ComparisonFunc=D3D11_COMPARISON_NEVER;ComPtr<ID3D11SamplerState> state;hr(device->CreateSamplerState(&d,&state),"sampler");samplers.push_back(state);}
  uniforms.resize((m.total_uniform_size+15)&~15u);for(const auto &u:m.uniforms)if(u.has_initializer_value){check(u.size<=sizeof(u.initializer_value.as_uint),"bounded scalar/vector uniform initializer");std::memcpy(uniforms.data()+u.offset,u.initializer_value.as_uint,u.size);}
  D3D11_BUFFER_DESC cb{};cb.ByteWidth=static_cast<UINT>(uniforms.size());cb.Usage=D3D11_USAGE_DEFAULT;cb.BindFlags=D3D11_BIND_CONSTANT_BUFFER;hr(device->CreateBuffer(&cb,nullptr,&constants),"uniform buffer");
  D3D11_RASTERIZER_DESC rs{};rs.FillMode=D3D11_FILL_SOLID;rs.CullMode=D3D11_CULL_NONE;rs.DepthClipEnable=true;hr(device->CreateRasterizerState(&rs,&raster),"rasterizer");
  D3D11_DEPTH_STENCIL_DESC ds{};ds.DepthEnable=false;hr(device->CreateDepthStencilState(&ds,&no_depth),"no hardware depth, matching ReShade FX");
  defaults();
 }
 void set(const char *name,const void *data,std::size_t size){const auto &m=backend->module();const auto it=std::find_if(m.uniforms.begin(),m.uniforms.end(),[&](const auto &u){return u.name==name;});check(it!=m.uniforms.end()&&size<=it->size,"uniform "+std::string(name));std::memcpy(uniforms.data()+it->offset,data,size);}
 void f(const char *name,std::initializer_list<float> values){set(name,values.begin(),values.size()*sizeof(float));}
 void b(const char *name,bool value){const std::uint32_t v=value?1:0;set(name,&v,4);}
 void defaults(){
  b("McHudActive",true);b("McHudLayers",true);b("McWorldWarpReady",true);b("McHostDepthReady",true);b("McHostDepthAvailable",true);b("McHudCursorVisible",false);
  f("McHudRect",{0,0,1,1});f("McGuestProjection",{.05f,512});f("McWarpSourceOrigin",{0,0,0});f("McWarpSourceForward",{0,1,0});f("McWarpSourceUp",{0,0,1});f("McWarpSourceTanHalf",{tanx,1});
  f("McWarpTargetOrigin",{0,0,0});f("McWarpTargetRight",{1,0,0});f("McWarpTargetForward",{0,1,0});f("McWarpTargetUp",{0,0,1});
  f("McWarpClipX",{1/tanx,0,0,0});f("McWarpClipY",{0,1,0,0});f("McWarpClipZ",{0,0,100.f/99.9f,-10.f/99.9f});f("McWarpClipW",{0,0,1,0});
  f("McHostProjection",{100.f/99.9f,-.1f/99.9f,100,0});f("McHostNearest",{100.f/99.9f,-.1f/99.9f,1,0});
 }
 void clear(){std::fill(atlas.begin(),atlas.end(),0);std::fill(atlas.begin()+width*height*2,atlas.end(),0x3f800000u);std::fill(host_depth.begin(),host_depth.end(),1.f);defaults();for(unsigned y=1;y<3;++y)for(unsigned x=1;x<5;++x)atlas[y*width+x]=green8;}
 void patch(unsigned x,unsigned y,unsigned w,unsigned h,float depth,std::uint32_t color){const float raw=512.f*(depth-.05f)/(depth*(512.f-.05f));std::uint32_t bits;std::memcpy(&bits,&raw,4);for(unsigned j=y;j<y+h;++j)for(unsigned i=x;i<x+w;++i){atlas[(height+j)*width+i]=color;atlas[(height*2+j)*width+i]=bits;}}
 std::vector<pixel> render(bool reverse=false,double *gpu_ms=nullptr,bool readback=true){
  const auto &m=backend->module();for(const auto &t:m.textures){auto &resource=textures.at(t.unique_name);if(t.semantic.rfind("MINECOME_HUD_",0)==0)context->UpdateSubresource(resource.object.Get(),0,nullptr,atlas.data(),width*4,0);else if(t.semantic=="DEPTH")context->UpdateSubresource(resource.object.Get(),0,nullptr,host_depth.data(),width*4,0);}
  context->UpdateSubresource(constants.Get(),0,nullptr,uniforms.data(),0,0);ID3D11Buffer *cb=constants.Get();context->VSSetConstantBuffers(0,1,&cb);context->PSSetConstantBuffers(0,1,&cb);context->RSSetState(raster.Get());context->OMSetDepthStencilState(no_depth.Get(),0);
  D3D11_VIEWPORT viewport{0,0,float(width),float(height),0,1};context->RSSetViewports(1,&viewport);context->ClearRenderTargetView(target.rtv.Get(),&background.r);
  ComPtr<ID3D11Query> disjoint,begin,end;
  if(gpu_ms){D3D11_QUERY_DESC q{D3D11_QUERY_TIMESTAMP_DISJOINT,0};hr(device->CreateQuery(&q,&disjoint),"GPU disjoint query");q.Query=D3D11_QUERY_TIMESTAMP;hr(device->CreateQuery(&q,&begin),"GPU begin timestamp");hr(device->CreateQuery(&q,&end),"GPU end timestamp");context->Begin(disjoint.Get());context->End(begin.Get());}
  for(const auto &tech:m.techniques)for(const auto &p:tech.passes){
   ID3D11ShaderResourceView *empty[16]{};context->VSSetShaderResources(0,16,empty);context->PSSetShaderResources(0,16,empty);
   auto &out=p.render_target_names[0].empty()?target:textures.at(p.render_target_names[0]);ID3D11RenderTargetView *rt=out.rtv.Get();context->OMSetRenderTargets(1,&rt,nullptr);if(p.clear_render_targets){const float zero[4]{};context->ClearRenderTargetView(rt,zero);}
   D3D11_BLEND_DESC bd{};auto &r=bd.RenderTarget[0];r.BlendEnable=p.blend_enable[0];r.SrcBlend=blend(p.source_color_blend_factor[0]);r.DestBlend=blend(p.dest_color_blend_factor[0]);r.BlendOp=static_cast<D3D11_BLEND_OP>(p.color_blend_op[0]);r.SrcBlendAlpha=blend(p.source_alpha_blend_factor[0]);r.DestBlendAlpha=blend(p.dest_alpha_blend_factor[0]);r.BlendOpAlpha=static_cast<D3D11_BLEND_OP>(p.alpha_blend_op[0]);r.RenderTargetWriteMask=p.render_target_write_mask[0];ComPtr<ID3D11BlendState> bs;hr(device->CreateBlendState(&bd,&bs),"actual pass blend");context->OMSetBlendState(bs.Get(),nullptr,0xffffffff);
   for(const auto &binding:p.texture_bindings){auto *view=textures.at(m.samplers.at(binding.index).texture_name).srv.Get();context->VSSetShaderResources(binding.entry_point_binding,1,&view);context->PSSetShaderResources(binding.entry_point_binding,1,&view);}
   for(const auto &binding:p.sampler_bindings){auto *s=samplers.at(binding.index).Get();context->VSSetSamplers(binding.entry_point_binding,1,&s);context->PSSetSamplers(binding.entry_point_binding,1,&s);}
   context->VSSetShader(vertex.at(p.vs_entry_point).Get(),nullptr,0);context->PSSetShader(fragment.at(p.ps_entry_point).Get(),nullptr,0);context->IASetInputLayout(nullptr);context->IASetPrimitiveTopology(static_cast<D3D11_PRIMITIVE_TOPOLOGY>(p.topology));
   if(reverse&&tech.name=="MineComeWorldWarp"){
    // SV_VertexID excludes Draw.StartVertexLocation; explicit index values
    // reverse surface submission without altering the actual compiled kernel.
    std::vector<unsigned> indices;indices.reserve(width*height*6);for(unsigned id=width*height;id-->0;)for(unsigned v=0;v<6;++v)indices.push_back(id*6+v);
    D3D11_BUFFER_DESC ib{};ib.ByteWidth=UINT(indices.size()*sizeof(unsigned));ib.Usage=D3D11_USAGE_IMMUTABLE;ib.BindFlags=D3D11_BIND_INDEX_BUFFER;D3D11_SUBRESOURCE_DATA data{indices.data(),0,0};ComPtr<ID3D11Buffer> index;hr(device->CreateBuffer(&ib,&data,&index),"reversed source-pixel order");context->IASetIndexBuffer(index.Get(),DXGI_FORMAT_R32_UINT,0);context->DrawIndexed(UINT(indices.size()),0,0);
   }else context->Draw(p.num_vertices,0);
  }
  if(gpu_ms){context->End(end.Get());context->End(disjoint.Get());context->Flush();D3D11_QUERY_DATA_TIMESTAMP_DISJOINT frequency{};const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(5);HRESULT status;
   while((status=context->GetData(disjoint.Get(),&frequency,sizeof(frequency),0))==S_FALSE){check(std::chrono::steady_clock::now()<deadline,"bounded GPU query completion");Sleep(1);}hr(status,"GPU disjoint result");UINT64 first{},last{};hr(context->GetData(begin.Get(),&first,sizeof(first),0),"GPU begin result");hr(context->GetData(end.Get(),&last,sizeof(last),0),"GPU end result");check(!frequency.Disjoint&&frequency.Frequency>0&&last>=first,"valid GPU timing interval");*gpu_ms=1000.0*double(last-first)/frequency.Frequency;}
  context->OMSetRenderTargets(0,nullptr,nullptr);if(!readback)return {};
  D3D11_TEXTURE2D_DESC desc{};target.object->GetDesc(&desc);desc.Usage=D3D11_USAGE_STAGING;desc.BindFlags=0;desc.CPUAccessFlags=D3D11_CPU_ACCESS_READ;ComPtr<ID3D11Texture2D> staging;hr(device->CreateTexture2D(&desc,nullptr,&staging),"readback texture");context->CopyResource(staging.Get(),target.object.Get());D3D11_MAPPED_SUBRESOURCE mapped{};hr(context->Map(staging.Get(),0,D3D11_MAP_READ,0,&mapped),"actual GPU readback");std::vector<pixel> output(std::size_t(width)*height);for(unsigned y=0;y<height;++y)std::memcpy(output.data()+y*width,static_cast<const char *>(mapped.pData)+y*mapped.RowPitch,width*sizeof(pixel));context->Unmap(staging.Get(),0);return output;
 }
};
unsigned count(const std::vector<pixel> &image,pixel value){return unsigned(std::count_if(image.begin(),image.end(),[&](pixel p){return same(p,value);}));}
float centroid(const std::vector<pixel> &image,unsigned width,pixel value){double sum=0;unsigned n=0;for(std::size_t i=0;i<image.size();++i)if(same(image[i],value)){sum+=i%width;++n;}check(n>0,"rendered colour exists");return float(sum/n);}
void hud(const std::vector<pixel> &image,unsigned width){for(unsigned y=1;y<3;++y)for(unsigned x=1;x<5;++x)check(same(image[y*width+x],green),"unchanged HUD overlay pixel");}
void cpu_guards(){
 using namespace minecome::host_depth;sample s{};s.position={0,0,0,1};s.right={1,0,0,0};s.front={0,-1,0,0};s.up={0,0,1,0};s.far_metres=100;s.captured_unix_ms=1000;s.ratio={100.f/99.9f,-.1f/99.9f,0,0};
 s.projection={1.f/(1280.f/720),0,.002f,0,0,1,-.003f,0,0,0,100.f/99.9f,-10.f/99.9f,0,0,1,0};expected_view v{1280,720,{0,0,0},{0,1,0},{0,0,1},float(std::acos(-1.)/2),1000};
 auto t=minecome::world_reprojection::make(s,v,1280,720,1000,1100);check(t.has_value(),"actual transform helper accepts canonical row-major lens");check(std::abs(t->clip[0][2]-.002f)<1e-6&&std::abs(t->clip[1][2]+.003f)<1e-6,"actual jitter rows retained");
 auto column=s;column.projection_row_major=false;for(unsigned r=0;r<4;++r)for(unsigned c=0;c<4;++c)column.projection[c*4+r]=s.projection[r*4+c];auto tc=minecome::world_reprojection::make(column,v,1280,720,1000,1100);check(tc&&tc->clip==t->clip,"reflected column-major packing matches row-major");
 auto negative=s;for(unsigned r=0;r<4;++r)negative.projection[r*4+2]*=-1;auto tn=minecome::world_reprojection::make(negative,v,1280,720,1000,1100);check(tn&&tn->clip==t->clip,"negative local camera Z convention canonicalized");
 auto bad=s;bad.projection[10]+=.01f;check(!minecome::world_reprojection::make(bad,v,1280,720,1000,1100),"projection incompatible with actual depth equation rejected");
 check(!minecome::world_reprojection::make(s,v,640,360,1000,1100),"production guard refuses rescaled source grid");check(!minecome::world_reprojection::make(s,v,1280,720,1101,1100),"future image rejected");check(!minecome::world_reprojection::make(s,v,1280,720,849,1100),"stale image rejected");
 bad=s;bad.captured_unix_ms=1101;check(!minecome::world_reprojection::make(bad,v,1280,720,1000,1100),"future native sample rejected");bad.captured_unix_ms=849;check(!minecome::world_reprojection::make(bad,v,1280,720,1000,1100),"stale native sample rejected");auto old=v;old.captured_unix_ms=749;check(!minecome::world_reprojection::make(s,old,1280,720,1000,1100),"source camera expired at image capture rejected");old.captured_unix_ms=1101;check(!minecome::world_reprojection::make(s,old,1280,720,1000,1100),"future source camera rejected");
 old=v;old.captured_unix_ms=800;check(!fresh(old,1100)&&minecome::world_reprojection::make(s,old,1280,720,1000,1100).has_value(),"captured source remains usable for current-view warp without renewing original camera lease");
 old.captured_unix_ms=750;check(minecome::world_reprojection::make(s,old,1280,720,1000,1250).has_value(),"independent capture and presentation leases accept their exact250ms boundaries");
 old.captured_unix_ms=1001;check(!minecome::world_reprojection::make(s,old,1280,720,1000,1100),"camera newer than its captured image rejected even if fresh now");
 bad=s;bad.position[0]=.751f;check(!minecome::world_reprojection::make(bad,v,1280,720,1000,1100),"translation beyond0.75m refused");bad=s;const float a=21.f*float(std::acos(-1.))/180;bad.front={-std::sin(a),-std::cos(a),0,0};bad.right={std::cos(a),-std::sin(a),0,0};check(!minecome::world_reprojection::make(bad,v,1280,720,1000,1100),"yaw beyond20 degrees refused");
}
void gpu_cases(effect &e){
 const unsigned w=e.width;const float shift=40*e.tanx/w;
 e.clear();e.patch(32,18,4,4,10,red8);const auto identity=e.render();check(count(identity,red)==16,"identity preserves all16 source pixels");hud(identity,w);const float baseline=centroid(identity,w,red);
 e.f("McWarpTargetOrigin",{shift,0,0});const auto translated=e.render();check(count(translated,red)==16&&std::abs(centroid(translated,w,red)-(baseline-2))<.1f,"translation shifts real source depth by two pixels");hud(translated,w);check(same(translated[19*w+35],background),"disocclusion leaves former source location empty");
 e.defaults();const float angle=10.f*float(std::acos(-1.))/180;e.f("McWarpTargetForward",{std::sin(angle),std::cos(angle),0});e.f("McWarpTargetRight",{std::cos(angle),-std::sin(angle),0});const auto rotated=e.render();const float delta=baseline-centroid(rotated,w,red);check(delta>2&&delta<4.5f,"rotation changes reconstructed world position in the correct direction");hud(rotated,w);
 e.defaults();e.f("McWarpClipX",{1/e.tanx,0,2.f/w,0});const auto jitter=e.render();check(std::abs(centroid(jitter,w,red)-baseline-1)<.1f,"native projection jitter shifts world one pixel");hud(jitter,w);
 e.defaults();const float raw5=100.f/99.9f+(-.1f/99.9f)*100/5;std::fill(e.host_depth.begin(),e.host_depth.end(),raw5);auto occluded=e.render();check(count(occluded,red)==0,"current native foreground depth occludes reprojected geometry");hud(occluded,w);
 e.clear();e.patch(26,18,2,4,10,red8);e.patch(28,18,2,4,5,blue8);e.f("McWarpTargetOrigin",{shift,0,0});auto overlap=e.render();check(count(overlap,red)==0&&count(overlap,blue)==8,"reciprocal MAX resolves nearer overlapping surface");const auto reverse=e.render(true);check(overlap.size()==reverse.size()&&std::equal(overlap.begin(),overlap.end(),reverse.begin(),[](pixel a,pixel b){return same(a,b);}),"overlap resolution is independent of source draw order");hud(overlap,w);
 e.clear();e.patch(32,18,2,4,5,red8);e.patch(34,18,2,4,10,blue8);e.f("McWarpTargetOrigin",{shift,0,0});auto discontinuity=e.render();check(count(discontinuity,red)==8&&count(discontinuity,blue)==8,"separate depth surfaces retain independent pixel quads");for(unsigned y=18;y<22;++y)for(unsigned x=30;x<32;++x)check(same(discontinuity[y*w+x],background),"depth discontinuity has no connecting triangles or hole fill");hud(discontinuity,w);
 e.clear();e.patch(32,18,2,2,10,red8);for(unsigned y=18;y<20;++y)for(unsigned x=32;x<34;++x)e.atlas[(e.height*2+y)*w+x]=0x3f800000u;e.patch(36,18,2,2,5,0x000000ff);auto invalid=e.render();check(count(invalid,red)==0&&count(invalid,blue)==0,"sky and zero-alpha cells generate no world fragments");hud(invalid,w);
 e.clear();e.patch(32,18,4,4,10,red8);e.f("McWarpTargetOrigin",{0,20,0});auto behind=e.render();check(count(behind,red)==0,"entire pixel behind target eye is rejected");hud(behind,w);
}
void hardware_benchmark(const std::filesystem::path &path){
 ComPtr<ID3D11Device> probe;const D3D_FEATURE_LEVEL requested=D3D_FEATURE_LEVEL_11_0;D3D_FEATURE_LEVEL obtained{};
 if(FAILED(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,0,&requested,1,D3D11_SDK_VERSION,&probe,&obtained,nullptr))){std::cout<<"WORLD_REPROJECTION_HARDWARE_SKIP no_d3d11_hardware_device=true\n";return;}
 ComPtr<IDXGIDevice> dxgi;hr(probe.As(&dxgi),"DXGI device");ComPtr<IDXGIAdapter> adapter;hr(dxgi->GetAdapter(&adapter),"hardware adapter");DXGI_ADAPTER_DESC description{};hr(adapter->GetDesc(&description),"hardware description");probe.Reset();
 effect gpu(path,1280,720,true,D3D_DRIVER_TYPE_HARDWARE);
 for(const bool filled:{false,true}){
  gpu.clear();if(filled)gpu.patch(0,0,1280,720,10,red8);else gpu.patch(512,90,256,540,10,red8);
  const auto visible=gpu.render();check(count(visible,red)==(filled?1280u*720u-8u:256u*540u),"hardware timing scene really rasterizes the stated occupied area");hud(visible,1280);
  // Three warmups and five GPU timestamps, all exact production-grid draws.
  // Resource upload/readback and shader compilation are outside this interval.
  double elapsed{};for(unsigned i=0;i<3;++i)gpu.render(false,&elapsed,false);
  std::vector<double> samples;for(unsigned i=0;i<5;++i){gpu.render(false,&elapsed,false);samples.push_back(elapsed);}std::sort(samples.begin(),samples.end());
  std::cout<<"WORLD_REPROJECTION_HARDWARE_TIMING occupied_percent="<<(filled?100:15)<<" gpu_median_ms="<<samples[2]<<" gpu_peak_ms="<<samples.back()<<" measured_frames=5 warmup_frames=3 geometry_passes=2 composition_passes=1 production_vertices_per_geometry_pass=5529600 adapter_vendor="<<description.VendorId<<" adapter_device="<<description.DeviceId<<"\n";
 }
}
}
int wmain(int argc,wchar_t **argv){try{
 check(argc==2,"usage: minecome_world_reprojection_tests <actual MineComeWorldHud.fx>");const auto path=std::filesystem::absolute(argv[1]);check(std::filesystem::is_regular_file(path)&&std::filesystem::file_size(path)<1024*1024,"bounded actual shader source");cpu_guards();
 const auto began=std::chrono::steady_clock::now();effect synthetic(path,64,36,false);gpu_cases(synthetic);const auto correctness_ms=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-began).count();
 effect production(path,1280,720,true);production.clear();production.patch(640,360,4,4,10,red8);const auto full_at=std::chrono::steady_clock::now();const auto smoke=production.render();const auto full_ms=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-full_at).count();check(count(smoke,red)==16,"default1280x720 full-grid production smoke");hud(smoke,1280);
 std::cout<<"WORLD_REPROJECTION_GPU_PASS checks="<<checks<<" synthetic_resolution=64x36 production_resolution=1280x720 production_vertices_per_geometry_pass=5529600 correctness_ms="<<correctness_ms<<" production_full_grid_ms="<<full_ms<<" adapter=WARP actual_fx_bytecode=true live_game_verified=false\n";
 hardware_benchmark(path);return 0;
 }catch(const std::exception &e){std::cerr<<"WORLD_REPROJECTION_GPU_FAIL "<<e.what()<<'\n';return 1;}}
