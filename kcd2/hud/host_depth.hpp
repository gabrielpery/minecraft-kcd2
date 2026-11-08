#pragma once

// Public ReShade 6.8.0 callbacks only; no engine pointers or guessed CB offsets.
// KCD2Mod 1.5.5 source evidence: Engine/Shaders.pak, FXConstantDefs.cfi
// CBPerViewGlobal and PostEffects.cfx LinearizeDepthPS (624-639). The installed
// DXIL cache rewrites source b6 to b0,space1; reflect binding as well as offsets.
// Original shader source is retained only under ignored runtime/evidence.
#include <reshade.hpp>
#include <d3dcompiler.h>
#include <d3d11shader.h>
#include <d3d12shader.h>
#include <dxcapi.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <optional>
#include <unordered_map>
#include <vector>
#include "native_depth_copy.hpp"

namespace minecome::host_depth {
namespace api = reshade::api;
using vec3 = std::array<float, 3>;
using vec4 = std::array<float, 4>;
constexpr std::size_t max_constant_bytes = 4096;

inline std::uint64_t unix_milliseconds() {
    return static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count());
}

struct expected_view {
    std::uint32_t width{}, height{};
    vec3 position{}, forward{}, up{};
    float vertical_fov{}; // radians, actual KCD camera
    std::uint64_t captured_unix_ms{};
    std::uint32_t max_age_ms{250};
    float position_tolerance{0.35f};
    float direction_cosine{0.995f};
    float fov_tolerance{0.03f};
};

enum class field : std::size_t {
    ratio, nearest, clips, position, right, front, up, screen, hpos, projection, count
};
struct reflected_layout {
    std::uint32_t size{};
    std::uint32_t register_index{}, register_space{};
    bool projection_row_major{true};
    std::array<std::uint32_t, static_cast<std::size_t>(field::count)> offsets{};
    bool operator==(const reflected_layout &) const = default;
};
struct sample {
    vec4 ratio{}, nearest{}, clips{}, position{}, right{}, front{}, up{}, screen{}, hpos{};
    std::array<float, 16> projection{};
    bool projection_row_major{true};
    api::viewport viewport{};
    api::resource source_depth{};
    api::device *device{};
    std::uint64_t captured_unix_ms{}, submitted_unix_ms{};
    bool reversed{};
    float far_metres{};
    float projection_element(std::size_t row,std::size_t column) const {
        return projection[projection_row_major?row*4+column:column*4+row];
    }
};

// A presentation proof cannot choose the last convenient view of a resource.
// Conflicting/unknown observations poison that resource until the next seal.
inline bool same_native_view(const sample &a,const sample &b) {
    const auto equal=[](float x,float y){return std::isfinite(x)&&std::isfinite(y)&&
        std::abs(x-y)<=1e-5f*std::max(1.0f,std::max(std::abs(x),std::abs(y)));};
    if(a.device!=b.device || a.source_depth!=b.source_depth)return false;
    for(unsigned i=0;i<3;++i)if(!std::isfinite(a.position[i])||!std::isfinite(b.position[i])||std::abs(a.position[i]-b.position[i])>0.0001f)return false;
    const vec4 *av[]={&a.ratio,&a.nearest,&a.clips,&a.right,&a.front,&a.up,&a.screen,&a.hpos};
    const vec4 *bv[]={&b.ratio,&b.nearest,&b.clips,&b.right,&b.front,&b.up,&b.screen,&b.hpos};
    for(unsigned v=0;v<std::size(av);++v)for(unsigned i=0;i<4;++i)if(!equal((*av[v])[i],(*bv[v])[i]))return false;
    for(unsigned r=0;r<4;++r)for(unsigned c=0;c<4;++c)if(!equal(a.projection_element(r,c),b.projection_element(r,c)))return false;
    return equal(a.viewport.x,b.viewport.x)&&equal(a.viewport.y,b.viewport.y)&&
        equal(a.viewport.width,b.viewport.width)&&equal(a.viewport.height,b.viewport.height)&&
        equal(a.viewport.min_depth,b.viewport.min_depth)&&equal(a.viewport.max_depth,b.viewport.max_depth);
}
enum class presentation_failure { none, identity, missing, ambiguous, unknown, overflow, age };
class unique_views {
    struct entry { api::device *device{};api::resource source{};std::optional<sample> value;bool invalid{},unknown{}; };
    std::array<entry,8> entries_{};
    bool overflow_{},incomplete_{};
    entry *get(api::device *device,api::resource source) {
        if(!device || !source.handle)return nullptr;
        for(auto &e:entries_)if(e.device==device && e.source==source)return &e;
        for(auto &e:entries_)if(!e.device){e.device=device;e.source=source;return &e;}
        overflow_=true;return nullptr;
    }
public:
    void clear(){entries_={};overflow_=false;incomplete_=false;}
    void invalidate_all(){incomplete_=true;}
    void erase(api::device *device,api::resource source){for(auto &e:entries_)if(e.device==device&&e.source==source)e={};}
    void invalidate(api::device *device,api::resource source){if(auto *e=get(device,source)){e->invalid=true;e->unknown=true;}}
    void observe(const sample &value){
        if(auto *e=get(value.device,value.source_depth)){
            if(e->value&&!same_native_view(*e->value,value))e->invalid=true;
            if(!e->value || e->value->captured_unix_ms<value.captured_unix_ms)e->value=value;
        }
    }
    void merge(const unique_views &other){
        overflow_=overflow_||other.overflow_;incomplete_=incomplete_||other.incomplete_;
        for(const auto &e:other.entries_)if(e.device){if(e.value)observe(*e.value);if(e.invalid){if(auto *target=get(e.device,e.source)){target->invalid=true;target->unknown=target->unknown||e.unknown;}}}
    }
    void submitted(std::uint64_t now){for(auto &e:entries_)if(e.value)e.value->submitted_unix_ms=now;}
    presentation_failure status(api::device *device,api::resource source) const {
        if(incomplete_)return presentation_failure::unknown;
        if(overflow_)return presentation_failure::overflow;
        for(const auto &e:entries_)if(e.device==device&&e.source==source){
            if(e.invalid)return e.unknown?presentation_failure::unknown:presentation_failure::ambiguous;
            return e.value?presentation_failure::none:presentation_failure::missing;
        }
        return presentation_failure::missing;
    }
    std::optional<sample> take(api::device *device,api::resource source){
        for(auto &e:entries_)if(e.device==device&&e.source==source){
            auto value=(!overflow_&&!incomplete_&&!e.invalid)?e.value:std::optional<sample>{};e.value.reset();return value;
        }
        return {};
    }
    std::optional<sample> peek(api::device *device,api::resource source)const{
        if(status(device,source)!=presentation_failure::none)return {};
        for(const auto &e:entries_)if(e.device==device&&e.source==source)return e.value;
        return {};
    }
};
enum class depth_access { unknown, read_only, writing };
inline depth_access classify_depth(const api::depth_stencil_desc &desc){
    return desc.depth_enable&&desc.depth_write_mask&&desc.depth_func!=api::compare_op::never?depth_access::writing:depth_access::read_only;
}
inline void observe_native_draw(unique_views &views,depth_access access,api::device *device,api::resource source,const sample *value) {
    if(access==depth_access::read_only)return;
    if(access==depth_access::unknown || !value)views.invalidate(device,source);
    else views.observe(*value);
}
struct presentation_sample { sample view;std::uint64_t epoch{},presented_unix_ms{}; };
class presentation_samples {
    unique_views pending_,sealed_;
    api::device *device_{};void *window_{};api::resource back_buffer_{};
    std::uint64_t epoch_{},presented_unix_ms_{};
public:
    void clear(){pending_.clear();sealed_.clear();device_=nullptr;window_=nullptr;back_buffer_={};++epoch_;}
    void erase(api::device *device,api::resource source){pending_.erase(device,source);sealed_.erase(device,source);}
    void submit(const unique_views &views){pending_.merge(views);}
    std::optional<sample> pending(api::device *device,api::resource source)const{return pending_.peek(device,source);}
    presentation_failure pending_status(api::device *device,api::resource source)const{return pending_.status(device,source);}
    void seal(api::device *device,void *window,api::resource back_buffer,std::uint64_t now,bool complete=true){
        sealed_=pending_;pending_.clear();device_=device;window_=window;back_buffer_=back_buffer;presented_unix_ms_=now;++epoch_;
        if(!complete)sealed_.invalidate_all();
    }
    std::optional<presentation_sample> take(api::device *device,void *window,api::resource back_buffer,api::resource source,std::uint64_t now,presentation_failure *failure=nullptr){
        const auto reject=[&](presentation_failure reason)->std::optional<presentation_sample>{if(failure)*failure=reason;return {};};
        if(failure)*failure=presentation_failure::none;
        if(!device || !window || !back_buffer.handle || device!=device_ || window!=window_ || back_buffer!=back_buffer_)return reject(presentation_failure::identity);
        if(!presented_unix_ms_ || now<presented_unix_ms_ || now-presented_unix_ms_>250)return reject(presentation_failure::age);
        const auto status=sealed_.status(device,source);if(status!=presentation_failure::none)return reject(status);
        auto value=sealed_.take(device,source);
        if(!value || !value->captured_unix_ms || value->captured_unix_ms>presented_unix_ms_ ||
            !value->submitted_unix_ms || value->submitted_unix_ms>presented_unix_ms_ ||
            value->captured_unix_ms>value->submitted_unix_ms || now-value->captured_unix_ms>250)return reject(presentation_failure::age);
        return presentation_sample{*value,epoch_,presented_unix_ms_};
    }
};

// Several full-size depth targets can use the same camera in one frame. Keep
// their submitted proofs separate: an auxiliary target must never replace the
// proof for the resource actually selected by GenericDepth.
class submitted_samples {
    std::array<std::optional<sample>,8> values_{};
public:
    void clear() { for (auto &value:values_) value.reset(); }
    void erase(api::device *device,api::resource resource) {
        for (auto &value:values_) if(value && value->device==device && value->source_depth==resource)value.reset();
    }
    void publish(const sample &value) {
        if(!value.device || !value.source_depth.handle)return;
        auto slot=values_.end();
        for(auto it=values_.begin();it!=values_.end();++it) {
            if(*it && (*it)->device==value.device && (*it)->source_depth==value.source_depth){slot=it;break;}
            if(!*it && slot==values_.end())slot=it;
        }
        if(slot==values_.end())slot=std::min_element(values_.begin(),values_.end(),[](const auto &a,const auto &b){return a->captured_unix_ms<b->captured_unix_ms;});
        if(!*slot || (*slot)->device!=value.device || (*slot)->source_depth!=value.source_depth || (*slot)->captured_unix_ms<=value.captured_unix_ms)*slot=value;
    }
    std::optional<sample> take(api::device *device,api::resource resource) {
        for(auto &value:values_)if(value && value->device==device && value->source_depth==resource){auto result=value;value.reset();return result;}
        return {};
    }
};

// Reflection is required even on the exact supported executable: float3x4 packing
// and compiler optimizations must not turn source declaration order into an ABI.
template<class Reflection,class BufferDesc,class VariableDesc,class TypeDesc>
inline std::optional<reflected_layout> reflect_layout(Reflection *reflection,
        std::uint32_t register_index,std::uint32_t register_space) {
    auto *buffer = reflection->GetConstantBufferByName("CBPerViewGlobal");
    BufferDesc description{};
    if (!buffer || FAILED(buffer->GetDesc(&description)) || description.Type != D3D_CT_CBUFFER ||
        description.Size == 0 || description.Size > max_constant_bytes) return {};
    constexpr const char *names[] = {
        "CV_ProjRatio", "CV_ProjRatioNearestScaled", "CV_NearFarClipDist",
        "CV_WorldViewPosition", "CV_CameraRightVector", "CV_CameraFrontVector",
        "CV_CameraUpVector", "CV_ScreenSize", "CV_HPosScale", "CV_ProjMatr"
    };
    reflected_layout result{};
    result.size = description.Size;
    result.register_index=register_index;
    result.register_space=register_space;
    for (std::size_t i = 0; i < std::size(names); ++i) {
        auto *variable = buffer->GetVariableByName(names[i]);
        VariableDesc vd{};
        TypeDesc td{};
        if (!variable || FAILED(variable->GetDesc(&vd)) || !variable->GetType() ||
            FAILED(variable->GetType()->GetDesc(&td))) return {};
        const bool matrix = i == static_cast<std::size_t>(field::projection);
        const std::uint32_t bytes = matrix ? 64u : 16u;
        if (td.Type != D3D_SVT_FLOAT || td.Elements != 0 || td.Columns != 4 ||
            td.Rows != (matrix ? 4u : 1u) || vd.Size != bytes ||
            (matrix ? (td.Class != D3D_SVC_MATRIX_ROWS && td.Class != D3D_SVC_MATRIX_COLUMNS)
                    : td.Class != D3D_SVC_VECTOR) ||
            vd.StartOffset > result.size || bytes > result.size - vd.StartOffset) return {};
        result.offsets[i] = vd.StartOffset;
        if(matrix)result.projection_row_major=td.Class==D3D_SVC_MATRIX_ROWS;
    }
    return result;
}

template<class T> struct com_release { T *p{}; ~com_release() { if (p) p->Release(); } };
inline std::optional<reflected_layout> reflect(const void *code,std::size_t size,DxcCreateInstanceProc dxc_factory=nullptr) {
    if (!code || size<4 || std::memcmp(code,"DXBC",4)!=0) return {};
    com_release<ID3D11ShaderReflection> legacy;
    if (SUCCEEDED(D3DReflect(code,size,__uuidof(ID3D11ShaderReflection),reinterpret_cast<void **>(&legacy.p))) && legacy.p) {
        D3D11_SHADER_INPUT_BIND_DESC binding{};
        if (FAILED(legacy.p->GetResourceBindingDescByName("CBPerViewGlobal",&binding)) ||
            binding.Type!=D3D_SIT_CBUFFER || binding.BindCount!=1) return {};
        return reflect_layout<ID3D11ShaderReflection,D3D11_SHADER_BUFFER_DESC,D3D11_SHADER_VARIABLE_DESC,D3D11_SHADER_TYPE_DESC>(
            legacy.p,binding.BindPoint,0);
    }
    if (!dxc_factory) return {};
    // Parent supplies DxcCreateInstance only after verifying and securely loading
    // the actual game-shipped dxcompiler.dll. No DLL discovery/loading on draws.
    com_release<IDxcUtils> utils;
    if (FAILED(dxc_factory(CLSID_DxcUtils,__uuidof(IDxcUtils),reinterpret_cast<void **>(&utils.p))) || !utils.p) return {};
    const DxcBuffer data{code,size,0};
    com_release<ID3D12ShaderReflection> dxil;
    if (FAILED(utils.p->CreateReflection(&data,__uuidof(ID3D12ShaderReflection),reinterpret_cast<void **>(&dxil.p))) || !dxil.p) return {};
    D3D12_SHADER_INPUT_BIND_DESC binding{};
    if (FAILED(dxil.p->GetResourceBindingDescByName("CBPerViewGlobal",&binding)) ||
        binding.Type!=D3D_SIT_CBUFFER || binding.BindCount!=1) return {};
    return reflect_layout<ID3D12ShaderReflection,D3D12_SHADER_BUFFER_DESC,D3D12_SHADER_VARIABLE_DESC,D3D12_SHADER_TYPE_DESC>(
        dxil.p,binding.BindPoint,binding.Space);
}

inline bool parse(const reflected_layout &layout, const void *bytes, std::size_t size, sample &out) {
    if (!bytes || layout.size > size || layout.size > max_constant_bytes) return false;
    vec4 *vectors[] = {&out.ratio, &out.nearest, &out.clips, &out.position,
        &out.right, &out.front, &out.up, &out.screen, &out.hpos};
    for (std::size_t i = 0; i < std::size(vectors); ++i) {
        if (layout.offsets[i] > size || 16 > size - layout.offsets[i]) return false;
        std::memcpy(vectors[i]->data(), static_cast<const char *>(bytes) + layout.offsets[i], 16);
        for (const float value : *vectors[i]) if (!std::isfinite(value)) return false;
    }
    const auto offset = layout.offsets[static_cast<std::size_t>(field::projection)];
    if (offset > size || 64 > size - offset) return false;
    std::memcpy(out.projection.data(), static_cast<const char *>(bytes) + offset, 64);
    out.projection_row_major=layout.projection_row_major;
    for (const float value : out.projection) if (!std::isfinite(value)) return false;
    return true;
}

inline float dot(const vec3 &a, const vec3 &b) {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
inline bool unit(const vec3 &v) { return std::isfinite(dot(v,v)) && std::abs(dot(v,v)-1.0f) < 0.02f; }
inline bool fresh(const expected_view &view, std::uint64_t now) {
    return view.captured_unix_ms != 0 && now >= view.captured_unix_ms &&
        now - view.captured_unix_ms <= view.max_age_ms;
}
inline bool viewport_matches(const api::viewport &v, const expected_view &e) {
    if (!e.width || !e.height || !std::isfinite(v.width) || !std::isfinite(v.height) ||
        v.width < 64 || v.height < 64 || std::abs(v.x) > 0.5f || std::abs(v.y) > 0.5f ||
        v.min_depth != 0 || v.max_depth != 1) return false;
    // Permit render-resolution scaling; require full-frame aspect and size bound.
    const float sx = v.width / static_cast<float>(e.width);
    const float sy = v.height / static_cast<float>(e.height);
    return sx >= 0.25f && sx <= 1.01f && sy >= 0.25f && sy <= 1.01f && std::abs(sx-sy) < 0.005f;
}

enum class view_rejection { none, age, viewport, basis, position, projection, parameters };
inline view_rejection validate_reason(sample &s, const expected_view &e, std::uint64_t now) {
    if (!fresh(e,now)) return view_rejection::age;
    if (!viewport_matches(s.viewport,e))return view_rejection::viewport;
    if (!unit(e.forward) || !unit(e.up))return view_rejection::basis;
    if (!std::isfinite(e.vertical_fov) || e.vertical_fov < 0.1f || e.vertical_fov > 3.0f)return view_rejection::projection;
    // CommonZPass.cfi uses -CV_CameraFrontVector for forward eye depth.
    const vec3 forward{-s.front[0],-s.front[1],-s.front[2]};
    const vec3 up{s.up[0],s.up[1],s.up[2]}, right{s.right[0],s.right[1],s.right[2]};
    if (!unit(forward) || !unit(up) || !unit(right) || std::abs(dot(forward,up)) > 0.02f ||
        std::abs(dot(forward,right)) > 0.02f || std::abs(dot(up,right)) > 0.02f ||
        dot(forward,e.forward) < e.direction_cosine || dot(up,e.up) < e.direction_cosine) return view_rejection::basis;
    float distance_squared = 0;
    for (std::size_t i=0;i<3;++i) {
        if (!std::isfinite(e.position[i])) return view_rejection::position;
        const float delta = s.position[i]-e.position[i]; distance_squared += delta*delta;
    }
    if (distance_squared > e.position_tolerance*e.position_tolerance) return view_rejection::position;
    if (std::abs(s.screen[0]-s.viewport.width) > 1.0f || std::abs(s.screen[1]-s.viewport.height) > 1.0f) return view_rejection::viewport;
    const float fy = std::abs(s.projection[5]), fx = std::abs(s.projection[0]);
    if (fx <= 0 || fy <= 0 || std::abs(2.0f*std::atan(1.0f/fy)-e.vertical_fov) > e.fov_tolerance ||
        std::abs(fy/fx-s.viewport.width/s.viewport.height) > 0.02f) return view_rejection::projection;
    const float d0 = s.ratio[1]/(-s.ratio[0]), d1 = s.ratio[1]/(1.0f-s.ratio[0]);
    if (!std::isfinite(d0) || !std::isfinite(d1) || d0 <= 0 || d1 <= 0 ||
        std::abs(std::max(d0,d1)-1.0f) > 0.002f || std::min(d0,d1) >= 0.1f ||
        s.clips[1] <= 0 || std::abs(s.clips[1]*s.clips[3]-1.0f) > 0.002f ||
        std::abs(s.nearest[1]) < 1e-10f || std::abs(s.nearest[2]-s.ratio[0]) < 1e-10f) return view_rejection::parameters;
    s.reversed = d0 > d1;
    s.far_metres = s.clips[1];
    return view_rejection::none;
}
inline bool validate(sample &s,const expected_view &e,std::uint64_t now){return validate_reason(s,e,now)==view_rejection::none;}

inline bool validate_native(sample &s,std::uint32_t width,std::uint32_t height,std::uint64_t observed) {
    // These are observed native constants, not a refreshed guest camera lease.
    // Projection/pose deltas against the guest belong to the reprojection guard.
    expected_view native{width,height,{s.position[0],s.position[1],s.position[2]},
        {-s.front[0],-s.front[1],-s.front[2]},{s.up[0],s.up[1],s.up[2]},
        2.0f*std::atan(1.0f/std::abs(s.projection_element(1,1))),observed};
    return validate(s,native,observed);
}
inline bool presentation_preserve_mode_supported(std::uint32_t mode){return mode==0;}

// Public descriptor callbacks identify CBVs in both CPU and GPU tables. Never
// inspect heap memory or infer a GPU virtual-address/resource relationship.
class descriptor_buffers {
    struct key { std::uint64_t heap{};std::uint32_t offset{};bool operator==(const key &)const=default; };
    struct hash {std::size_t operator()(const key &k)const{return std::hash<std::uint64_t>{}(k.heap)^(std::size_t(k.offset)*0x9e3779b9u);}};
    std::unordered_map<key,api::buffer_range,hash> values_;
public:
    struct texture_view {api::resource resource{};api::resource_view_desc desc{};};
private:
    std::unordered_map<key,texture_view,hash> views_;
public:
    void clear(){values_.clear();views_.clear();}
    void erase_heap(api::descriptor_heap heap){std::erase_if(values_,[&](const auto &v){return v.first.heap==heap.handle;});std::erase_if(views_,[&](const auto &v){return v.first.heap==heap.handle;});}
    void erase_resource(api::resource resource){std::erase_if(values_,[&](const auto &v){return v.second.buffer==resource;});std::erase_if(views_,[&](const auto &v){return v.second.resource==resource;});}
    std::optional<api::buffer_range> find(api::descriptor_heap heap,std::uint32_t offset)const{
        const auto found=values_.find({heap.handle,offset});return found==values_.end()?std::optional<api::buffer_range>{}:found->second;
    }
    void update(api::descriptor_heap heap,std::uint32_t offset,const std::optional<api::buffer_range> &range){
        if(!heap.handle)return;const key slot{heap.handle,offset};
        views_.erase(slot);
        if(!range || !range->buffer.handle || !range->size){values_.erase(slot);return;}
        if(values_.size()>=65536 && !values_.contains(slot)){values_.clear();return;}
        values_[slot]=*range;
    }
    std::optional<texture_view> find_view(api::descriptor_heap heap,std::uint32_t offset)const{
        const auto found=views_.find({heap.handle,offset});return found==views_.end()?std::optional<texture_view>{}:found->second;
    }
    void update_view(api::descriptor_heap heap,std::uint32_t offset,const std::optional<texture_view> &view){
        if(!heap.handle)return;const key slot{heap.handle,offset};values_.erase(slot);
        if(!view || !view->resource.handle){views_.erase(slot);return;}
        if(views_.size()>=16384&&!views_.contains(slot)){views_.clear();return;}
        views_[slot]=*view;
    }
    void copy(api::descriptor_heap source,std::uint32_t source_offset,api::descriptor_heap destination,std::uint32_t destination_offset,std::uint32_t count){
        if(count>4096 || count>UINT32_MAX-source_offset || count>UINT32_MAX-destination_offset){erase_heap(destination);return;}
        struct saved {std::optional<api::buffer_range> buffer;std::optional<texture_view> view;};
        std::vector<saved> snapshot;snapshot.reserve(count);
        for(std::uint32_t i=0;i<count;++i)snapshot.push_back({find(source,source_offset+i),find_view(source,source_offset+i)});
        for(std::uint32_t i=0;i<count;++i){if(snapshot[i].view)update_view(destination,destination_offset+i,snapshot[i].view);else update(destination,destination_offset+i,snapshot[i].buffer);}
    }
};
struct rejected_pipeline {
    std::uint64_t pipeline{},source_depth{};
    std::uint32_t width{},height{},depth_compare{};
    bool depth_enabled{},depth_write{};
    std::vector<std::uint8_t> vertex,pixel;
};

struct root_binding { std::uint32_t parameter{}, binding{}, register_index{}, register_space{}, count{}; };
inline std::vector<root_binding> descriptor_bindings(std::uint32_t count,const api::pipeline_layout_param *params,api::descriptor_type type,api::shader_stage visibility=api::shader_stage::all_graphics) {
    std::vector<root_binding> found;
    const auto add=[&](std::uint32_t parameter,const api::descriptor_range &r) {
        if(r.type==type && r.count!=0 &&
            (r.visibility&visibility)!=api::shader_stage{})
            found.push_back({parameter,r.binding,r.dx_register_index,r.dx_register_space,r.count});
    };
    for(std::uint32_t i=0;i<count;++i){
        const auto &p=params[i];
        if(p.type==api::pipeline_layout_param_type::push_descriptors)add(i,p.push_descriptors);
        else if(p.type==api::pipeline_layout_param_type::descriptor_table ||
                p.type==api::pipeline_layout_param_type::push_descriptors_with_ranges){
            for(std::uint32_t j=0;j<p.descriptor_table.count;++j)add(i,p.descriptor_table.ranges[j]);
        }else if(p.type==api::pipeline_layout_param_type::descriptor_table_with_flags ||
                 p.type==api::pipeline_layout_param_type::push_descriptors_with_ranges_and_flags){
            for(std::uint32_t j=0;j<p.descriptor_table_with_flags.count;++j)add(i,p.descriptor_table_with_flags.ranges[j]);
        }
    }
    return found;
}
inline std::vector<root_binding> constant_bindings(std::uint32_t count,const api::pipeline_layout_param *params){return descriptor_bindings(count,params,api::descriptor_type::constant_buffer);}
inline bool static_copy_sampler(std::uint32_t count,const api::pipeline_layout_param *params){
    bool found=false;
    for(std::uint32_t i=0;i<count;++i){const auto &p=params[i];
        if(p.type!=api::pipeline_layout_param_type::descriptor_table_with_flags&&p.type!=api::pipeline_layout_param_type::push_descriptors_with_ranges_and_flags)continue;
        for(std::uint32_t j=0;j<p.descriptor_table_with_flags.count;++j){const auto &r=p.descriptor_table_with_flags.ranges[j];
            if(r.type!=api::descriptor_type::sampler || (r.visibility&api::shader_stage::pixel)==api::shader_stage{} || r.dx_register_space!=0 || r.dx_register_index>1 || 1-r.dx_register_index>=r.count)continue;
            if(found||!r.static_samplers)return false;
            const auto &s=r.static_samplers[1-r.dx_register_index];
            if(s.filter!=api::filter_mode::min_mag_mip_point || s.mip_lod_bias!=0 || s.min_lod>0 || s.max_lod<0)return false;
            found=true;
        }
    }
    return found;
}
struct copy_diagnostic {
    std::uint64_t source{},destination{};
    std::uint32_t source_width{},source_height{},destination_width{},destination_height{},source_format{},view_format{},source_samples{},source_levels{},stage{},proof_status{};
};
inline bool raw_depth_view_format(api::format format){
    return format==api::format::r32_float||format==api::format::r24_unorm_x8_uint||format==api::format::r32_float_x8_uint||format==api::format::r16_unorm;
}
struct constant_selection {
    struct table_slot {api::descriptor_heap heap{};std::uint32_t offset{};bool operator==(const table_slot &)const=default;};
    std::optional<api::buffer_range> range;
    std::array<table_slot,8> tables{};std::uint32_t table_count{};bool ambiguous{};
    void observe(const api::buffer_range &candidate,api::descriptor_heap heap={},std::uint32_t offset=0){
        if(!candidate.buffer.handle)return;
        if(range&&(range->buffer!=candidate.buffer||range->offset!=candidate.offset||range->size!=candidate.size)){ambiguous=true;return;}
        range=candidate;
        if(!heap.handle)return;
        const table_slot slot{heap,offset};for(std::uint32_t i=0;i<table_count;++i)if(tables[i]==slot)return;
        if(table_count==tables.size()){ambiguous=true;return;}tables[table_count++]=slot;
    }
};
inline bool constant_aliases_current(const descriptor_buffers &descriptors,std::span<const constant_selection::table_slot> slots,
        api::resource buffer,std::uint64_t offset,std::uint32_t required_bytes){
    for(const auto &slot:slots){const auto current=descriptors.find(slot.heap,slot.offset);
        if(!current||current->buffer!=buffer||current->offset!=offset||current->size<required_bytes)return false;
    }
    return true;
}
// Recording may finish on another CPU worker after a present. Such a command,
// or an already submitted list replayed without fresh observations, cannot
// silently disappear from the next presentation's writer set.
struct native_submission_guard {
    std::uint64_t recorded_epoch{};bool depth_work{},submitted{},crossed{};
    void observe(std::uint64_t epoch){if(depth_work&&recorded_epoch!=epoch)crossed=true;if(!depth_work)recorded_epoch=epoch;depth_work=true;}
    bool submit(std::uint64_t epoch){if(!depth_work)return true;const bool valid=!submitted&&!crossed&&recorded_epoch==epoch;submitted=true;return valid;}
};
inline std::optional<sample> copy_source_proof(const unique_views &local_views,api::device *device,api::resource source,
        presentation_failure prefix_status,const std::optional<sample> &prefix,const std::optional<sample> &previous_submission){
    const auto final_status=local_views.status(device,source);
    if(prefix_status==presentation_failure::none && prefix && final_status==presentation_failure::none){
        const auto final_view=local_views.peek(device,source);
        if(final_view&&same_native_view(*prefix,*final_view))return prefix;
    }
    // A source first written later in this command cannot establish the contents
    // read by an earlier copy. Only prior submitted commands may supply it.
    if(prefix_status==presentation_failure::missing&&final_status==presentation_failure::missing)return previous_submission;
    return {};
}

// Same normalized-depth formula and nearest-camera remap as LinearizeDepthPS.
// A shader should treat the exact sky endpoint as infinity before this formula.
inline float linear_metres(const sample &s, float device_depth) {
    const float sky = s.reversed ? 0.0f : 1.0f;
    if (device_depth == sky) return INFINITY;
    float value = s.ratio[1]/(device_depth-s.ratio[0]);
    const float nearest_max = s.ratio[1]/(s.nearest[2]-s.ratio[0]);
    if (value < nearest_max) value = s.nearest[1]/(device_depth-s.nearest[0]);
    return std::isfinite(value) && value > 0 ? value*s.far_metres : INFINITY;
}

struct diagnostics {
    std::uint64_t shaders_reflected{}, reflection_rejected{}, map_attempts{}, non_upload_rejected{},
        map_failed{}, incoherent_rejected{}, view_rejected{}, accepted{}, submitted{}, recording_contention{};
    std::uint64_t presentation_seals{},presentation_accepted{},presentation_identity{},presentation_missing{},
        presentation_ambiguous{},presentation_unknown{},presentation_overflow{},presentation_age{},native_reads{},native_nonwriters{},native_unknown_draws{},native_budget_rejected{};
    std::uint64_t recording_waits{},native_incomplete_epochs{},native_unknown_access{},native_viewport_rejected{},
        native_pipeline_missing{},native_layout_missing{},native_binding_missing{},native_resource_rejected{},native_map_failed{},
        native_incoherent{},native_invalid_view{},native_submission_changed{};
    std::uint64_t native_descriptor_updates{},native_descriptor_copies{};
    std::uint64_t native_copy_draws{},native_copy_accepted{},native_copy_source_missing{},native_copy_rejected{};
    std::uint64_t native_binding_ambiguous{};
};

inline std::unique_lock<std::mutex> lock_recording(std::mutex &mutex,bool complete,
        std::atomic<std::uint64_t> &contention,std::uint64_t *waits=nullptr) {
    std::unique_lock lock(mutex,std::try_to_lock);
    if(!lock.owns_lock()){
        contention.fetch_add(1,std::memory_order_relaxed);
        if(complete){lock.lock();if(waits)++*waits;}
    }
    return lock;
}

class tracker {
    struct device_state {
        std::unordered_map<std::uint64_t, reflected_layout> pipelines;
        std::unordered_map<std::uint64_t, depth_access> depth_accesses;
        std::unordered_map<std::uint64_t, std::vector<root_binding>> layouts;
        std::unordered_map<std::uint64_t, std::vector<root_binding>> view_layouts;
        std::unordered_map<std::uint64_t,bool> copy_samplers,copy_pipelines;
        descriptor_buffers descriptors;
        std::unordered_map<std::uint64_t,rejected_pipeline> unreflected_writers;
        std::size_t writer_shader_bytes{};
    };
    struct command_state {
        struct native_binding {
            api::resource depth{},buffer{};std::uint64_t offset{};reflected_layout layout;api::viewport viewport{};sample value;
            api::descriptor_heap table_heap{};std::uint32_t table_offset{};
            std::array<constant_selection::table_slot,8> tables{};std::uint32_t table_count{};
        };
        std::uint64_t pipeline{}, root_layout{}, sampled_generation{};
        std::unordered_map<std::uint64_t, api::buffer_range> buffers;
        std::unordered_map<std::uint64_t,descriptor_buffers::texture_view> resource_views;
        struct table_binding {api::descriptor_heap heap{};std::uint32_t offset{};};
        std::unordered_map<std::uint32_t,table_binding> tables;
        api::viewport viewport{};
        api::rect scissor{};
        api::resource source_depth{};
        std::optional<sample> candidate;
        std::uint64_t native_epoch{};
        std::vector<native_binding> native_bindings;
        unique_views native_views;
        struct depth_copy {
            api::resource source{},destination{};
            api::descriptor_heap heap{};std::uint32_t offset{};
            descriptor_buffers::texture_view view;
            std::optional<sample> local_source;
            presentation_failure local_status{presentation_failure::missing};
            copy_diagnostic diagnostic;
        };
        std::vector<depth_copy> depth_copies;
        native_submission_guard submission_guard;
    };
    std::atomic<bool> compatible_{false}, armed_{false}, reflected_{false};
    std::atomic<DxcCreateInstanceProc> dxc_factory_{nullptr};
    std::mutex mutex_;
    std::unordered_map<api::device *, device_state> devices_;
    std::unordered_map<api::command_list *, command_state> commands_;
    expected_view expected_{};
    std::uint64_t generation_{1};
    std::uint32_t frame_attempts_{};
    submitted_samples submitted_;
    std::atomic<bool> presented_sampling_{false};
    bool native_epoch_incomplete_{};
    std::uint64_t native_epoch_{1};
    std::uint32_t native_attempts_{};
    presentation_samples presentations_;
    std::optional<rejected_pipeline> rejected_writer_;
    bool rejected_writer_recorded_{};
    std::optional<copy_diagnostic> copy_diagnostic_;
    void record_copy_diagnostic(const copy_diagnostic &value){
        if(!copy_diagnostic_ || (copy_diagnostic_->stage==6&&value.stage!=6))copy_diagnostic_=value;
    }
    diagnostics diagnostics_{};
    std::atomic<std::uint64_t> invalidation_{0}, contention_{0};
    std::uint64_t observed_invalidation_{};

    std::unique_lock<std::mutex> recording_lock(bool invalidate_on_failure=true) {
        // Complete per-presentation proof must observe concurrent recording,
        // not discard it. Pinned D3D12 getters/maps below do not acquire a queue
        // lock or wait on the GPU; resource registry locks are released before
        // our callbacks (d3d12_device.cpp:2313-2318). No queue API under mutex_.
        // Keep the original opportunistic path for legacy strict-only sampling.
        auto lock=lock_recording(mutex_,presented_sampling_.load(std::memory_order_relaxed),contention_,&diagnostics_.recording_waits);
        if (!lock.owns_lock()) {
            if (invalidate_on_failure) invalidation_.fetch_add(1,std::memory_order_release);
            return lock;
        }
        const auto invalidation=invalidation_.load(std::memory_order_acquire);
        if (invalidation!=observed_invalidation_) {
            // A dropped state-changing callback makes all command snapshots
            // incomplete. Reconstruct them from subsequent game bindings.
            commands_.clear(); submitted_.clear(); presentations_.clear(); observed_invalidation_=invalidation;
            // Later valid draws cannot prove that a dropped earlier callback
            // did not write this presentation's selected depth with another view.
            if(presented_sampling_.load())native_epoch_incomplete_=true;
        }
        return lock;
    }
    std::optional<api::buffer_range> bound_constant(const device_state &data,const command_state &state,std::uint32_t parameter,std::uint32_t binding)const{
        if(const auto table=state.tables.find(parameter);table!=state.tables.end()){
            if(binding>UINT32_MAX-table->second.offset)return {};
            return data.descriptors.find(table->second.heap,table->second.offset+binding);
        }
        const auto found=state.buffers.find((static_cast<std::uint64_t>(parameter)<<32)|binding);
        return found==state.buffers.end()?std::optional<api::buffer_range>{}:found->second;
    }
    void record_native_work(command_state &state){
        state.submission_guard.observe(native_epoch_);
        if(state.native_epoch!=native_epoch_){state.native_epoch=native_epoch_;state.native_bindings.clear();state.native_views.clear();state.depth_copies.clear();}
    }

    bool collect_depth_copy(api::device *device,command_state &state,device_state &data,bool direct_copy_shape){
        const auto known=data.copy_pipelines.find(state.pipeline);
        if(known==data.copy_pipelines.end()||!known->second)return false;
        ++diagnostics_.native_copy_draws;
        copy_diagnostic info;info.destination=state.source_depth.handle;
        const auto destination=device->get_resource_desc(state.source_depth);
        info.destination_width=destination.texture.width;info.destination_height=destination.texture.height;
        const auto reject=[&](std::uint32_t stage){info.stage=stage;record_copy_diagnostic(info);++diagnostics_.native_copy_rejected;state.native_views.invalidate(device,state.source_depth);return true;};
        if(!direct_copy_shape || state.viewport.x!=0 || state.viewport.y!=0 || state.viewport.min_depth!=0 || state.viewport.max_depth!=1 ||
            state.scissor.left>0 || state.scissor.top>0 || state.scissor.right<state.viewport.width || state.scissor.bottom<state.viewport.height || state.depth_copies.size()>=4)return reject(1);
        const auto layout=data.view_layouts.find(state.root_layout);if(layout==data.view_layouts.end())return reject(2);
        std::optional<descriptor_buffers::texture_view> source_view;api::descriptor_heap heap{};std::uint32_t offset{};
        for(const auto &root:layout->second){
            if(root.register_space!=0 || root.register_index!=0 || !root.count)continue;
            if(source_view)return reject(2);
            if(const auto table=state.tables.find(root.parameter);table!=state.tables.end()){
                if(root.binding>UINT32_MAX-table->second.offset)return reject(2);
                heap=table->second.heap;offset=table->second.offset+root.binding;source_view=data.descriptors.find_view(heap,offset);
            }else{const auto entry=state.resource_views.find((std::uint64_t(root.parameter)<<32)|root.binding);if(entry!=state.resource_views.end())source_view=entry->second;}
        }
        if(!source_view)return reject(2);
        const auto source=device->get_resource_desc(source_view->resource);
        info.source=source_view->resource.handle;info.source_width=source.texture.width;info.source_height=source.texture.height;
        info.source_format=static_cast<std::uint32_t>(source.texture.format);info.view_format=static_cast<std::uint32_t>(source_view->desc.format);
        info.source_samples=source.texture.samples;info.source_levels=source.texture.levels;
        const auto &v=source_view->desc;
        if(source_view->resource==state.source_depth || source.type!=api::resource_type::texture_2d || destination.type!=api::resource_type::texture_2d ||
            source.texture.width!=destination.texture.width || source.texture.height!=destination.texture.height || source.texture.samples!=1 || destination.texture.samples!=1 ||
            source.texture.depth_or_layers!=1 || destination.texture.depth_or_layers!=1 || source.texture.levels!=1 || destination.texture.levels!=1 ||
            v.type!=api::resource_view_type::texture_2d || !raw_depth_view_format(v.format) || v.texture.first_level!=0 || (v.texture.levels!=1&&v.texture.levels!=UINT32_MAX) || v.texture.first_layer!=0 ||
            state.viewport.width!=source.texture.width || state.viewport.height!=source.texture.height)return reject(3);
        if(!data.copy_samplers[state.root_layout])return reject(4);
        state.depth_copies.push_back({source_view->resource,state.source_depth,heap,offset,*source_view,state.native_views.peek(device,source_view->resource),state.native_views.status(device,source_view->resource),info});
        return true;
    }
    void collect_presented(api::device *device,command_state &state,device_state &data,bool direct_copy_shape) {
        if(!presented_sampling_ || !state.source_depth.handle)return;
        const auto access_entry=data.depth_accesses.find(state.pipeline);
        const auto access=access_entry==data.depth_accesses.end()?depth_access::unknown:access_entry->second;
        // Read-only depth passes may bind the same DSV without contributing any
        // depth. In particular an unreflected HUD shader is not a camera writer.
        if(access==depth_access::read_only){++diagnostics_.native_nonwriters;return;}
        // No proof survives across native presentation epochs merely because a
        // reusable command list still names the same buffer/DSV handles.
        const auto reject=[&]{record_native_work(state);++diagnostics_.native_unknown_draws;observe_native_draw(state.native_views,access,device,state.source_depth,nullptr);};
        if(!viewport_matches(state.viewport,expected_)){
            // A cropped/unknown view can still modify a full-size selected DSV.
            // Do not silently skip that observation and retain another camera.
            const auto desc=device->get_resource_desc(state.source_depth);
            if(desc.type==api::resource_type::texture_2d && viewport_matches({0,0,float(desc.texture.width),float(desc.texture.height),0,1},expected_)){++diagnostics_.native_viewport_rejected;reject();}
            return;
        }
        record_native_work(state);
        if(access==depth_access::unknown){++diagnostics_.native_unknown_access;reject();return;}
        if(collect_depth_copy(device,state,data,direct_copy_shape))return;
        const auto pipeline=data.pipelines.find(state.pipeline);const auto layout=data.layouts.find(state.root_layout);
        if(pipeline==data.pipelines.end()){
            ++diagnostics_.native_pipeline_missing;
            if(!rejected_writer_recorded_){if(const auto writer=data.unreflected_writers.find(state.pipeline);writer!=data.unreflected_writers.end()){
                rejected_writer_=writer->second;rejected_writer_->source_depth=state.source_depth.handle;
                rejected_writer_->width=static_cast<std::uint32_t>(state.viewport.width);rejected_writer_->height=static_cast<std::uint32_t>(state.viewport.height);rejected_writer_recorded_=true;
            }}
            reject();return;
        }
        if(layout==data.layouts.end()){++diagnostics_.native_layout_missing;reject();return;}
        constant_selection selected;
        for(const auto &root:layout->second){
            const auto &reflected=pipeline->second;
            if(root.register_space!=reflected.register_space||root.register_index>reflected.register_index||reflected.register_index-root.register_index>=root.count)continue;
            const auto binding=std::uint64_t(root.binding)+reflected.register_index-root.register_index;if(binding>UINT32_MAX)continue;
            const auto candidate=bound_constant(data,state,root.parameter,static_cast<std::uint32_t>(binding));if(!candidate)continue;
            if(const auto table=state.tables.find(root.parameter);table!=state.tables.end())selected.observe(*candidate,table->second.heap,table->second.offset+static_cast<std::uint32_t>(binding));
            else selected.observe(*candidate);
        }
        if(selected.ambiguous){++diagnostics_.native_binding_ambiguous;reject();return;}
        for(const auto &root:layout->second){
            const auto &reflected=pipeline->second;
            if(root.register_space!=reflected.register_space || root.register_index>reflected.register_index ||
                reflected.register_index-root.register_index>=root.count)continue;
            const auto binding=static_cast<std::uint64_t>(root.binding)+reflected.register_index-root.register_index;
            if(binding>UINT32_MAX)continue;
            const auto found=bound_constant(data,state,root.parameter,static_cast<std::uint32_t>(binding));
            if(!found || !found->buffer.handle)continue;
            const auto range=*found;
            api::descriptor_heap table_heap{};std::uint32_t table_offset{};
            if(const auto table=state.tables.find(root.parameter);table!=state.tables.end()){
                table_heap=table->second.heap;table_offset=table->second.offset+static_cast<std::uint32_t>(binding);
            }
            for(const auto &cached:state.native_bindings){
                if(cached.depth==state.source_depth && cached.buffer==range.buffer && cached.offset==range.offset && cached.layout==reflected &&
                    cached.table_heap==table_heap && cached.table_offset==table_offset &&
                    cached.table_count==selected.table_count && cached.tables==selected.tables &&
                    cached.viewport.x==state.viewport.x && cached.viewport.y==state.viewport.y && cached.viewport.width==state.viewport.width &&
                    cached.viewport.height==state.viewport.height && cached.viewport.min_depth==state.viewport.min_depth && cached.viewport.max_depth==state.viewport.max_depth){
                    observe_native_draw(state.native_views,access,device,state.source_depth,&cached.value);return;
                }
            }
            if(native_attempts_>=64 || state.native_bindings.size()>=16){++diagnostics_.native_budget_rejected;reject();return;}
            ++native_attempts_;++diagnostics_.native_reads;
            const auto desc=device->get_resource_desc(range.buffer),depth_desc=device->get_resource_desc(state.source_depth);
            if(desc.type!=api::resource_type::buffer || desc.heap!=api::memory_heap::upload || range.offset>desc.buffer.size ||
                reflected.size>desc.buffer.size-range.offset || range.size<reflected.size || depth_desc.type!=api::resource_type::texture_2d ||
                depth_desc.texture.samples!=1 || std::abs(float(depth_desc.texture.width)-state.viewport.width)>1 ||
                std::abs(float(depth_desc.texture.height)-state.viewport.height)>1){++diagnostics_.native_resource_rejected;reject();return;}
            void *mapped=nullptr;
            if(!device->map_buffer_region(range.buffer,range.offset,reflected.size,api::map_access::read_only,&mapped)||!mapped){++diagnostics_.native_map_failed;reject();return;}
            std::array<std::byte,max_constant_bytes> first{},second{};
            std::memcpy(first.data(),mapped,reflected.size);std::atomic_thread_fence(std::memory_order_seq_cst);
            std::memcpy(second.data(),mapped,reflected.size);device->unmap_buffer_region(range.buffer);
            sample value{};value.viewport=state.viewport;value.source_depth=state.source_depth;value.device=device;
            const auto now=unix_milliseconds();
            if(first!=second){++diagnostics_.native_incoherent;reject();return;}
            if(!parse(reflected,first.data(),reflected.size,value) || !validate_native(value,expected_.width,expected_.height,now)){++diagnostics_.native_invalid_view;reject();return;}
            value.captured_unix_ms=now;
            state.native_bindings.push_back({state.source_depth,range.buffer,range.offset,reflected,state.viewport,value,table_heap,table_offset,selected.tables,selected.table_count});
            observe_native_draw(state.native_views,access,device,state.source_depth,&value);return;
        }
        ++diagnostics_.native_binding_missing;reject();
    }

public:
    // Supply before enabling metadata collection. Module lifetime must cover all
    // registered callbacks; the parent owns its verified DLL handle.
    void set_dxc_factory(DxcCreateInstanceProc factory) { dxc_factory_.store(factory); }
    std::optional<rejected_pipeline> take_rejected_pipeline(){std::scoped_lock lock(mutex_);auto result=std::move(rejected_writer_);rejected_writer_.reset();return result;}
    std::optional<copy_diagnostic> take_copy_diagnostic(){std::scoped_lock lock(mutex_);auto result=copy_diagnostic_;copy_diagnostic_.reset();return result;}
    void set_presented_sampling(bool value){
        std::scoped_lock lock(mutex_);presented_sampling_=value;presentations_.clear();++native_epoch_;native_attempts_=0;native_epoch_incomplete_=true;
        copy_diagnostic_.reset();for(auto &[cmd,state]:commands_){state.native_bindings.clear();state.native_views.clear();state.depth_copies.clear();state.native_epoch=0;state.submission_guard={};}
    }
    void present(api::swapchain *swapchain){
        if(!armed_.load() || !swapchain)return;
        auto lock=recording_lock();if(!lock.owns_lock() || !presented_sampling_)return;
        if(native_epoch_incomplete_)++diagnostics_.native_incomplete_epochs;
        presentations_.seal(swapchain->get_device(),swapchain->get_hwnd(),swapchain->get_current_back_buffer(),unix_milliseconds(),!native_epoch_incomplete_);
        ++native_epoch_;native_attempts_=0;native_epoch_incomplete_=false;++diagnostics_.presentation_seals;
    }
    std::optional<presentation_sample> take_current_presentation(api::device *device,void *window,api::resource back_buffer,api::resource depth,std::uint64_t now){
        auto lock=recording_lock(false);if(!lock.owns_lock() || !armed_.load() || !presented_sampling_)return {};
        presentation_failure failure;auto result=presentations_.take(device,window,back_buffer,depth,now,&failure);
        switch(failure){
        case presentation_failure::none:++diagnostics_.presentation_accepted;break;
        case presentation_failure::identity:++diagnostics_.presentation_identity;break;
        case presentation_failure::missing:++diagnostics_.presentation_missing;break;
        case presentation_failure::ambiguous:++diagnostics_.presentation_ambiguous;break;
        case presentation_failure::unknown:++diagnostics_.presentation_unknown;break;
        case presentation_failure::overflow:++diagnostics_.presentation_overflow;break;
        case presentation_failure::age:++diagnostics_.presentation_age;break;
        }
        return result;
    }
    bool metadata_available() const noexcept { return compatible_.load() && reflected_.load(); }
    // Exact executable guard belongs to the caller. Enable metadata collection
    // before game pipelines are created, but do not arm reads before gameplay.
    void set_compatible(bool value) { compatible_.store(value); if (!value) arm(false,{}); }
    void arm(bool value, const expected_view &view) {
        armed_.store(false);
        std::scoped_lock lock(mutex_);
        expected_=view; ++generation_; frame_attempts_=0; submitted_.clear();presentations_.clear();++native_epoch_;native_attempts_=0;native_epoch_incomplete_=true;
        if(value){rejected_writer_.reset();rejected_writer_recorded_=false;copy_diagnostic_.reset();for(auto &[cmd,state]:commands_)state.submission_guard={};}
        if (!value) commands_.clear();
        armed_.store(value && compatible_.load());
    }
    // Call with each new guest frame, preserving last published sample until read.
    void update_expected(const expected_view &view) {
        auto lock=recording_lock(); if (!lock.owns_lock()) return;
        expected_=view; ++generation_; frame_attempts_=0;
    }
    diagnostics counters() {
        std::scoped_lock lock(mutex_); auto result=diagnostics_;
        result.recording_contention=contention_.load(std::memory_order_relaxed); return result;
    }
    std::optional<sample> take_sample(api::device *device,api::resource selected_depth) {
        auto lock=recording_lock(false); if (!lock.owns_lock()) return {};
        auto result=submitted_.take(device,selected_depth);
        const auto now=unix_milliseconds();
        if (result && (!armed_.load() || now<result->captured_unix_ms ||
            now-result->captured_unix_ms>expected_.max_age_ms || !validate(*result,expected_,now))) return {};
        return result;
    }

    void init_pipeline(api::device *device, api::pipeline_layout, std::uint32_t count,
                       const api::pipeline_subobject *objects, api::pipeline pipeline) {
        if (!compatible_.load() || device->get_api()!=api::device_api::d3d12) return;
        std::optional<reflected_layout> found;
        copy::ShaderRole vertex_role=copy::ShaderRole::none,pixel_role=copy::ShaderRole::none;
        bool extra_stage=false,seen_vertex=false,seen_pixel=false;
        depth_access access=depth_access::unknown;api::depth_stencil_desc observed_depth{};
        bool have_depth_state=false,ambiguous_depth_state=false,ambiguous_layout=false;
        for (std::uint32_t i=0;i<count;++i) {
            if((objects[i].type==api::pipeline_subobject_type::geometry_shader || objects[i].type==api::pipeline_subobject_type::hull_shader || objects[i].type==api::pipeline_subobject_type::domain_shader) && objects[i].count && objects[i].data){
                const auto &shader=*static_cast<const api::shader_desc *>(objects[i].data);if(shader.code_size)extra_stage=true;
            }
            if(objects[i].type==api::pipeline_subobject_type::depth_stencil_state){
                if(have_depth_state || objects[i].count!=1 || !objects[i].data)ambiguous_depth_state=true;
                else{const auto &desc=*static_cast<const api::depth_stencil_desc *>(objects[i].data);observed_depth=desc;access=classify_depth(desc);have_depth_state=true;}
            }
            if (objects[i].type!=api::pipeline_subobject_type::vertex_shader &&
                objects[i].type!=api::pipeline_subobject_type::pixel_shader) continue;
            if (!objects[i].data || objects[i].count!=1) continue;
            const auto &shader=*static_cast<const api::shader_desc *>(objects[i].data);
            if(objects[i].type==api::pipeline_subobject_type::vertex_shader){if(seen_vertex)extra_stage=true;seen_vertex=true;vertex_role=copy::identify({static_cast<const std::byte *>(shader.code),shader.code_size});}
            else{if(seen_pixel)extra_stage=true;seen_pixel=true;pixel_role=copy::identify({static_cast<const std::byte *>(shader.code),shader.code_size});}
            auto layout=reflect(shader.code,shader.code_size,dxc_factory_.load());
            if (layout) {
                if (found && *found!=*layout)ambiguous_layout=true;
                found=layout;
            }
        }
        std::scoped_lock lock(mutex_);
        devices_[device].depth_accesses[pipeline.handle]=ambiguous_depth_state?depth_access::unknown:access;
        devices_[device].copy_pipelines[pipeline.handle]=!extra_stage&&!ambiguous_depth_state&&copy::exact_shader_pair(vertex_role,pixel_role);
        if(ambiguous_layout)found.reset();
        if (found) { devices_[device].pipelines[pipeline.handle]=*found; ++diagnostics_.shaders_reflected; reflected_.store(true); }
        else {
            ++diagnostics_.reflection_rejected;
            auto &data=devices_[device];
            if(access==depth_access::writing && data.writer_shader_bytes<8*1024*1024 && data.unreflected_writers.size()<64){
                rejected_pipeline writer;writer.pipeline=pipeline.handle;writer.depth_enabled=observed_depth.depth_enable;
                writer.depth_write=observed_depth.depth_write_mask;writer.depth_compare=static_cast<std::uint32_t>(observed_depth.depth_func);
                for(std::uint32_t i=0;i<count;++i)if(objects[i].count==1&&objects[i].data&&
                    (objects[i].type==api::pipeline_subobject_type::vertex_shader||objects[i].type==api::pipeline_subobject_type::pixel_shader)){
                    const auto &shader=*static_cast<const api::shader_desc *>(objects[i].data);
                    if(shader.code && shader.code_size && shader.code_size<=2*1024*1024 && data.writer_shader_bytes+shader.code_size<=8*1024*1024){
                        auto &bytes=objects[i].type==api::pipeline_subobject_type::vertex_shader?writer.vertex:writer.pixel;
                        bytes.assign(static_cast<const std::uint8_t *>(shader.code),static_cast<const std::uint8_t *>(shader.code)+shader.code_size);
                        data.writer_shader_bytes+=shader.code_size;
                    }
                }
                data.unreflected_writers.emplace(pipeline.handle,std::move(writer));
            }
        }
    }
    void destroy_pipeline(api::device *device, api::pipeline pipeline) {
        std::scoped_lock lock(mutex_);auto &data=devices_[device];data.pipelines.erase(pipeline.handle);data.depth_accesses.erase(pipeline.handle);data.copy_pipelines.erase(pipeline.handle);
        if(const auto writer=data.unreflected_writers.find(pipeline.handle);writer!=data.unreflected_writers.end()){
            data.writer_shader_bytes-=writer->second.vertex.size()+writer->second.pixel.size();data.unreflected_writers.erase(writer);
        }
    }
    void init_pipeline_layout(api::device *device, std::uint32_t count,
                              const api::pipeline_layout_param *params, api::pipeline_layout layout) {
        if (!compatible_.load() || device->get_api()!=api::device_api::d3d12) return;
        auto found=constant_bindings(count,params);
        auto views=descriptor_bindings(count,params,api::descriptor_type::shader_resource_view,api::shader_stage::pixel);const bool point=static_copy_sampler(count,params);
        std::scoped_lock lock(mutex_);auto &data=devices_[device];data.layouts[layout.handle]=std::move(found);data.view_layouts[layout.handle]=std::move(views);data.copy_samplers[layout.handle]=point;
    }
    void destroy_pipeline_layout(api::device *device, api::pipeline_layout layout) {
        std::scoped_lock lock(mutex_);auto &data=devices_[device];data.layouts.erase(layout.handle);data.view_layouts.erase(layout.handle);data.copy_samplers.erase(layout.handle);
    }
    void destroy_device(api::device *device) {
        std::scoped_lock lock(mutex_); devices_.erase(device); commands_.clear(); submitted_.clear();presentations_.clear();
    }
    void destroy_resource(api::device *device,api::resource resource) {
        if (!compatible_.load()) return;
        std::scoped_lock lock(mutex_);
        devices_[device].descriptors.erase_resource(resource);
        if(!armed_.load())return;
        submitted_.erase(device,resource);
        presentations_.erase(device,resource);
        for (auto &[cmd,state]:commands_) {
            if (cmd->get_device()!=device) continue;
            for(const auto &binding:state.native_bindings)if(binding.buffer==resource || binding.depth==resource)state.native_views.invalidate(device,binding.depth);
            std::erase_if(state.native_bindings,[&](const auto &binding){return binding.buffer==resource || binding.depth==resource;});
            const auto previous=state.buffers.size();
            std::erase_if(state.buffers,[&](const auto &entry) { return entry.second.buffer==resource; });
            if (state.source_depth==resource || previous!=state.buffers.size()) {
                if (state.source_depth==resource) state.source_depth={};
                state.candidate.reset(); state.sampled_generation=0;
                // Keep poisoned source entries until submission/present; losing
                // an input buffer must not turn an incomplete command into proof.
            }
        }
    }
    void reset_command_list(api::command_list *cmd) {
        if (!armed_.load()) return;
        auto lock=recording_lock(); if (!lock.owns_lock()) return;
        commands_.erase(cmd);
    }
    void bind_pipeline(api::command_list *cmd, api::pipeline_stage stages, api::pipeline pipeline) {
        if (!armed_.load() || (stages & api::pipeline_stage::all_graphics)==api::pipeline_stage{}) return;
        auto lock=recording_lock(); if (!lock.owns_lock()) return;
        commands_[cmd].pipeline=pipeline.handle;
    }
    void bind_viewports(api::command_list *cmd,std::uint32_t first,std::uint32_t count,const api::viewport *views) {
        if (!armed_.load() || first!=0 || count==0 || !views) return;
        auto lock=recording_lock(); if (!lock.owns_lock()) return;
        commands_[cmd].viewport= count==1 ? views[0] : api::viewport{};
    }
    void bind_scissors(api::command_list *cmd,std::uint32_t first,std::uint32_t count,const api::rect *rects){
        if(!armed_.load()||first!=0||!count||!rects)return;
        auto lock=recording_lock();if(lock.owns_lock())commands_[cmd].scissor=count==1?rects[0]:api::rect{};
    }
    void bind_depth(api::command_list *cmd,api::resource_view dsv) {
        if (!armed_.load()) return;
        auto lock=recording_lock(); if (!lock.owns_lock()) return;
        commands_[cmd].source_depth=dsv.handle ? cmd->get_device()->get_resource_from_view(dsv) : api::resource{};
    }
    void resource_transfer(api::command_list *cmd,api::resource destination){
        if(!armed_.load()||!presented_sampling_.load()||!destination.handle)return;
        auto lock=recording_lock();if(!lock.owns_lock())return;
        const auto desc=cmd->get_device()->get_resource_desc(destination);
        if(desc.type!=api::resource_type::texture_2d || (desc.usage&api::resource_usage::depth_stencil)==api::resource_usage{} ||
            !viewport_matches({0,0,float(desc.texture.width),float(desc.texture.height),0,1},expected_))return;
        auto &state=commands_[cmd];
        record_native_work(state);
        // A native copy can replace depth without any reflected draw. We do
        // not borrow its source camera until that path has separate proof.
        state.native_views.invalidate(cmd->get_device(),destination);
    }
    void push_descriptors(api::command_list *cmd,api::shader_stage stages,api::pipeline_layout layout,
                          std::uint32_t parameter,const api::descriptor_table_update &update) {
        if (!armed_.load() || (stages & api::shader_stage::all_graphics)==api::shader_stage{}) return;
        auto lock=recording_lock(); if (!lock.owns_lock()) return;
        auto &state=commands_[cmd];
        if (state.root_layout!=layout.handle) { state.buffers.clear();state.resource_views.clear();state.tables.clear(); state.root_layout=layout.handle; }
        state.tables.erase(parameter);
        const auto &layouts=devices_[cmd->get_device()].layouts;
        const auto entry=layouts.find(layout.handle);
        if (entry==layouts.end()) return;
        for (const auto &root:entry->second) {
            if (root.parameter!=parameter || update.count>256) continue;
            for (std::uint32_t i=0;i<update.count;++i) {
                const std::uint64_t binding=static_cast<std::uint64_t>(update.binding)+i;
                if (binding<root.binding || binding-root.binding>=root.count || binding>UINT32_MAX) continue;
                const std::uint64_t key=(static_cast<std::uint64_t>(parameter)<<32)|binding;
                state.buffers.erase(key);
                if (update.type==api::descriptor_type::constant_buffer && update.descriptors && update.array_offset==0)
                    state.buffers[key]=static_cast<const api::buffer_range *>(update.descriptors)[i];
            }
        }
    }
    // A table bind can change the root signature without a root-CBV write.
    void bind_descriptor_tables(api::command_list *cmd,api::shader_stage stages,api::pipeline_layout layout,
                                std::uint32_t first,std::uint32_t count,const api::descriptor_table *tables,std::uint32_t dynamic_count,const std::uint32_t *) {
        if (!armed_.load() || (stages & api::shader_stage::all_graphics)==api::shader_stage{}) return;
        auto lock=recording_lock(); if (!lock.owns_lock()) return;
        auto &state=commands_[cmd];
        if (state.root_layout!=layout.handle) { state.buffers.clear();state.resource_views.clear();state.tables.clear(); state.root_layout=layout.handle; }
        if(count>64 || first>UINT32_MAX-count || (count&&!tables)){state.buffers.clear();state.tables.clear();return;}
        for(std::uint32_t i=0;i<count;++i){
            command_state::table_binding table;
            if(!dynamic_count && tables[i].handle)cmd->get_device()->get_descriptor_heap_offset(tables[i],0,0,&table.heap,&table.offset);
            state.tables[first+i]=table;
        }
    }
    void update_descriptor_tables(api::device *device,std::uint32_t count,const api::descriptor_table_update *updates){
        if(!compatible_.load() || !updates)return;
        // D3D12Device::CreateConstantBufferView emits this after creating the
        // real CBV; non-CBV overwrites must erase previously tracked CBVs too.
        std::scoped_lock lock(mutex_);auto &descriptors=devices_[device].descriptors;
        if(count>4096){descriptors.clear();return;}
        for(std::uint32_t u=0;u<count;++u){const auto &update=updates[u];if(!update.table.handle)continue;
            api::descriptor_heap heap{};std::uint32_t offset{};
            device->get_descriptor_heap_offset(update.table,update.binding,0,&heap,&offset);
            if(update.array_offset || update.count>4096 || update.count>UINT32_MAX-offset){descriptors.erase_heap(heap);continue;}
            ++diagnostics_.native_descriptor_updates;
            for(std::uint32_t i=0;i<update.count;++i){
                const auto range=update.type==api::descriptor_type::constant_buffer&&update.descriptors?
                    std::optional<api::buffer_range>{static_cast<const api::buffer_range *>(update.descriptors)[i]}:std::optional<api::buffer_range>{};
                descriptors.update(heap,offset+i,range);
                if(update.type==api::descriptor_type::shader_resource_view&&update.descriptors){
                    const auto view=static_cast<const api::resource_view *>(update.descriptors)[i];
                    if(view.handle){const auto desc=device->get_resource_view_desc(view);
                        if(desc.type==api::resource_view_type::texture_2d && desc.texture.first_level==0 &&
                            raw_depth_view_format(desc.format))
                            descriptors.update_view(heap,offset+i,descriptor_buffers::texture_view{device->get_resource_from_view(view),desc});
                    }
                }
            }
        }
    }
    void copy_descriptor_tables(api::device *device,std::uint32_t count,const api::descriptor_table_copy *copies){
        if(!compatible_.load() || !copies)return;
        std::scoped_lock lock(mutex_);auto &descriptors=devices_[device].descriptors;
        if(count>4096){descriptors.clear();return;}
        for(std::uint32_t i=0;i<count;++i){const auto &copy=copies[i];if(!copy.dest_table.handle)continue;
            api::descriptor_heap source{},destination{};std::uint32_t source_offset{},destination_offset{};
            device->get_descriptor_heap_offset(copy.dest_table,copy.dest_binding,0,&destination,&destination_offset);
            if(!copy.source_table.handle || copy.source_array_offset || copy.dest_array_offset){descriptors.erase_heap(destination);continue;}
            device->get_descriptor_heap_offset(copy.source_table,copy.source_binding,0,&source,&source_offset);
            descriptors.copy(source,source_offset,destination,destination_offset,copy.count);++diagnostics_.native_descriptor_copies;
        }
    }
    void draw(api::command_list *cmd,bool direct_copy_shape=false) {
        if (!armed_.load()) return;
        auto lock=recording_lock(presented_sampling_.load(std::memory_order_relaxed)); if (!lock.owns_lock()) return;
        auto &state=commands_[cmd];
        auto *device=cmd->get_device();
        auto &data=devices_[device];
        collect_presented(device,state,data,direct_copy_shape);
        if (frame_attempts_>=64 || state.sampled_generation==generation_ ||
            !state.source_depth.handle || !fresh(expected_,unix_milliseconds()) || !viewport_matches(state.viewport,expected_)) return;
        const auto pipeline=data.pipelines.find(state.pipeline);
        const auto layout=data.layouts.find(state.root_layout);
        if (pipeline==data.pipelines.end() || layout==data.layouts.end()) return;
        for (const auto &root:layout->second) {
            const auto &reflected=pipeline->second;
            if (root.register_space!=reflected.register_space || root.register_index>reflected.register_index ||
                reflected.register_index-root.register_index>=root.count) continue;
            const std::uint64_t binding=static_cast<std::uint64_t>(root.binding)+reflected.register_index-root.register_index;
            if (binding>UINT32_MAX) continue;
            const auto buffer=bound_constant(data,state,root.parameter,static_cast<std::uint32_t>(binding));
            if (!buffer || !buffer->buffer.handle) continue;
            const auto range=*buffer;
            ++frame_attempts_;
            const auto desc=device->get_resource_desc(range.buffer);
            if (desc.type!=api::resource_type::buffer || desc.heap!=api::memory_heap::upload) {
                ++diagnostics_.non_upload_rejected; continue;
            }
            const auto size=pipeline->second.size;
            if (range.offset>desc.buffer.size || size>desc.buffer.size-range.offset || range.size<size) continue;
            const auto depth_desc=device->get_resource_desc(state.source_depth);
            if (depth_desc.type!=api::resource_type::texture_2d || depth_desc.texture.samples!=1 ||
                std::abs(static_cast<float>(depth_desc.texture.width)-state.viewport.width)>1.0f ||
                std::abs(static_cast<float>(depth_desc.texture.height)-state.viewport.height)>1.0f) {
                ++diagnostics_.view_rejected; continue;
            }
            ++diagnostics_.map_attempts;
            void *mapped=nullptr;
            if (!device->map_buffer_region(range.buffer,range.offset,size,api::map_access::read_only,&mapped) || !mapped) {
                ++diagnostics_.map_failed; continue;
            }
            std::array<std::byte,max_constant_bytes> first{}, second{};
            std::memcpy(first.data(),mapped,size);
            std::atomic_thread_fence(std::memory_order_seq_cst);
            std::memcpy(second.data(),mapped,size);
            device->unmap_buffer_region(range.buffer);
            if (std::memcmp(first.data(),second.data(),size)!=0) { ++diagnostics_.incoherent_rejected; continue; }
            sample candidate{}; candidate.viewport=state.viewport; candidate.source_depth=state.source_depth; candidate.device=device;
            if (!parse(pipeline->second,first.data(),size,candidate) || !validate(candidate,expected_,unix_milliseconds())) {
                ++diagnostics_.view_rejected; continue;
            }
            candidate.captured_unix_ms=unix_milliseconds();
            state.candidate=candidate; state.sampled_generation=generation_; ++diagnostics_.accepted; return;
        }
    }
    // Publication happens only when the command list containing that draw is submitted.
    void execute_command_list(api::command_queue *,api::command_list *cmd) {
        if (!armed_.load()) return;
        auto lock=recording_lock(); if (!lock.owns_lock()) return;
        const auto entry=commands_.find(cmd);
        if (entry==commands_.end()) return;
        auto &state=entry->second;
        const bool current_native_submission=state.submission_guard.submit(native_epoch_);
        if(presented_sampling_ && !current_native_submission)native_epoch_incomplete_=true;
        if(presented_sampling_ && current_native_submission && state.native_epoch==native_epoch_){
            // Upload memory must still describe the recorded view when its
            // commands are submitted. A reused address never renews the proof.
            for(const auto &binding:state.native_bindings){
                const bool aliases_current=constant_aliases_current(devices_[cmd->get_device()].descriptors,
                    {binding.tables.data(),binding.table_count},binding.buffer,binding.offset,binding.layout.size);
                if(!aliases_current){++diagnostics_.native_submission_changed;state.native_views.invalidate(cmd->get_device(),binding.depth);continue;}
                if(binding.table_heap.handle){
                    const auto current=devices_[cmd->get_device()].descriptors.find(binding.table_heap,binding.table_offset);
                    if(!current || current->buffer!=binding.buffer || current->offset!=binding.offset || current->size<binding.layout.size){
                        ++diagnostics_.native_submission_changed;state.native_views.invalidate(cmd->get_device(),binding.depth);continue;
                    }
                }
                void *mapped=nullptr;sample observed{};observed.device=cmd->get_device();observed.source_depth=binding.depth;observed.viewport=binding.viewport;
                bool valid=false;
                if(cmd->get_device()->map_buffer_region(binding.buffer,binding.offset,binding.layout.size,api::map_access::read_only,&mapped)&&mapped){
                    std::array<std::byte,max_constant_bytes> first{},second{};
                    std::memcpy(first.data(),mapped,binding.layout.size);std::atomic_thread_fence(std::memory_order_seq_cst);
                    std::memcpy(second.data(),mapped,binding.layout.size);cmd->get_device()->unmap_buffer_region(binding.buffer);
                    valid=first==second && parse(binding.layout,first.data(),binding.layout.size,observed)&&same_native_view(observed,binding.value);
                }
                if(!valid){++diagnostics_.native_submission_changed;state.native_views.invalidate(cmd->get_device(),binding.depth);}
            }
            for(const auto &copy:state.depth_copies){
                auto info=copy.diagnostic;
                bool unchanged=true;
                if(copy.heap.handle){const auto current=devices_[cmd->get_device()].descriptors.find_view(copy.heap,copy.offset);
                    unchanged=current&&current->resource==copy.source&&current->desc.type==copy.view.desc.type&&current->desc.format==copy.view.desc.format&&
                        current->desc.texture.first_level==copy.view.desc.texture.first_level&&current->desc.texture.levels==copy.view.desc.texture.levels&&
                        current->desc.texture.first_layer==copy.view.desc.texture.first_layer&&current->desc.texture.layers==copy.view.desc.texture.layers;
                }
                auto source=unchanged?copy_source_proof(state.native_views,cmd->get_device(),copy.source,copy.local_status,copy.local_source,
                    presentations_.pending(cmd->get_device(),copy.source)):std::optional<sample>{};
                const auto local_status=state.native_views.status(cmd->get_device(),copy.source);
                info.proof_status=static_cast<std::uint32_t>(!unchanged?presentation_failure::unknown:
                    local_status==presentation_failure::missing?presentations_.pending_status(cmd->get_device(),copy.source):local_status);
                const auto now=unix_milliseconds();
                if(source&&source->captured_unix_ms&&source->captured_unix_ms<=now&&now-source->captured_unix_ms<=250){
                    source->source_depth=copy.destination;state.native_views.observe(*source);++diagnostics_.native_copy_accepted;info.stage=6;
                }else{state.native_views.invalidate(cmd->get_device(),copy.destination);++diagnostics_.native_copy_source_missing;info.stage=5;}
                record_copy_diagnostic(info);
            }
            state.native_views.submitted(unix_milliseconds());presentations_.submit(state.native_views);
            state.native_bindings.clear();state.native_views.clear();state.depth_copies.clear();
        }
        if (state.candidate && state.sampled_generation==generation_) {
            state.candidate->submitted_unix_ms=unix_milliseconds(); submitted_.publish(*state.candidate); ++diagnostics_.submitted;
        }
        state.candidate.reset();
    }
};

// One tracker per add-on module. Registration is separate from compatibility and
// arming so a mismatched executable performs no reflection or buffer reads.
inline tracker &instance() { static tracker value; return value; }

// Source-specific GenericDepth metadata, NOT an engine memory layout. Mirrors
// external/reshade/examples/09-depth/generic_depth_addon.cpp:158-171 at pinned
// 18deaa52de0c425a78b329e9cb3c497281cd00ec (6.8.0). Caller must verify the actual
// loaded ReShade DLL hash before enabling this tracker or reading this metadata.
// Public api_object::get_private_data supplies the add-on-owned value by UUID.
struct __declspec(uuid("7c6363c7-f94e-437a-9160-141782c44a98")) generic_depth_metadata {
    api::resource selected_depth_stencil{};
    api::resource override_depth_stencil{};
    api::resource_view selected_shader_resource{};
    bool using_backup_texture{};
};
inline api::resource selected_depth(api::effect_runtime *runtime,api::resource_view actual_depth) {
    if(!runtime || !actual_depth.handle)return {};
    const auto *data=runtime->get_private_data<generic_depth_metadata>();
    if(!data || !data->selected_depth_stencil.handle || !data->selected_shader_resource.handle)return {};
    auto *device=runtime->get_device();
    const auto expected=device->get_resource_from_view(data->selected_shader_resource);
    return expected.handle && expected==device->get_resource_from_view(actual_depth) ? data->selected_depth_stencil : api::resource{};
}
inline bool matches_depth(api::effect_runtime *runtime,api::resource_view actual_depth,const sample &captured) {
    // Read only on this runtime's render/effects thread, after GenericDepth has
    // selected and bound DEPTH. D3D12 always uses a backup resource, so compare
    // both the selected original DSV and the selected backup's actual SRV.
    if (!runtime || !actual_depth.handle || !captured.source_depth.handle ||
        runtime->get_device()!=captured.device) return false;
    return selected_depth(runtime,actual_depth)==captured.source_depth;
}
inline std::optional<presentation_sample> take_current_presentation(api::effect_runtime *runtime,api::resource_view actual_depth) {
    if(!runtime || !instance().metadata_available())return {};
    // Pinned GenericDepth defaults to zero and updates this config whenever its
    // UI changes the mode. In zero mode its begin-effects callback copies the
    // selected source for this presentation; preserved earlier copies are not
    // interchangeable with this proof. This guard never changes user settings.
    std::uint32_t preserve_mode=0;
    reshade::get_config_value(nullptr,"DEPTH","DepthCopyBeforeClears",preserve_mode);
    if(!presentation_preserve_mode_supported(preserve_mode))return {};
    const auto selected=selected_depth(runtime,actual_depth);
    if(!selected.handle)return {};
    return instance().take_current_presentation(runtime->get_device(),runtime->get_hwnd(),runtime->get_current_back_buffer(),selected,unix_milliseconds());
}
namespace callbacks {
inline void init_pipeline(api::device *d,api::pipeline_layout l,std::uint32_t n,const api::pipeline_subobject *s,api::pipeline p) { instance().init_pipeline(d,l,n,s,p); }
inline void destroy_pipeline(api::device *d,api::pipeline p) { instance().destroy_pipeline(d,p); }
inline void init_layout(api::device *d,std::uint32_t n,const api::pipeline_layout_param *p,api::pipeline_layout l) { instance().init_pipeline_layout(d,n,p,l); }
inline void destroy_layout(api::device *d,api::pipeline_layout l) { instance().destroy_pipeline_layout(d,l); }
inline void destroy_device(api::device *d) { instance().destroy_device(d); }
inline void destroy_resource(api::device *d,api::resource r) { instance().destroy_resource(d,r); }
inline void reset(api::command_list *c) { instance().reset_command_list(c); }
inline void bind_pipeline(api::command_list *c,api::pipeline_stage s,api::pipeline p) { instance().bind_pipeline(c,s,p); }
inline void bind_viewports(api::command_list *c,std::uint32_t f,std::uint32_t n,const api::viewport *v) { instance().bind_viewports(c,f,n,v); }
inline void bind_scissors(api::command_list *c,std::uint32_t f,std::uint32_t n,const api::rect *r) { instance().bind_scissors(c,f,n,r); }
inline void bind_targets(api::command_list *c,std::uint32_t,const api::resource_view *,api::resource_view d) { instance().bind_depth(c,d); }
inline bool begin_pass(api::command_list *c,std::uint32_t,const api::render_pass_render_target_desc *,const api::render_pass_depth_stencil_desc *d,api::render_pass_flags) { instance().bind_depth(c,d ? d->view : api::resource_view{}); return false; }
inline bool end_pass(api::command_list *c) { instance().bind_depth(c,{}); return false; }
inline void push(api::command_list *c,api::shader_stage s,api::pipeline_layout l,std::uint32_t p,const api::descriptor_table_update &u) { instance().push_descriptors(c,s,l,p,u); }
inline void tables(api::command_list *c,api::shader_stage s,api::pipeline_layout l,std::uint32_t f,std::uint32_t n,const api::descriptor_table *t,std::uint32_t dn,const std::uint32_t *o) { instance().bind_descriptor_tables(c,s,l,f,n,t,dn,o); }
inline bool draw(api::command_list *c,std::uint32_t v,std::uint32_t n,std::uint32_t f,std::uint32_t fi) { instance().draw(c,copy::exact_fullscreen_draw(v,n,f,fi)); return false; }
inline bool draw_indexed(api::command_list *c,std::uint32_t,std::uint32_t,std::uint32_t,std::int32_t,std::uint32_t) { instance().draw(c); return false; }
inline bool indirect(api::command_list *c,api::indirect_command type,api::resource,std::uint64_t,std::uint32_t,std::uint32_t) {
    if (type==api::indirect_command::draw || type==api::indirect_command::draw_indexed) instance().draw(c);
    return false;
}
inline void execute(api::command_queue *q,api::command_list *c) { instance().execute_command_list(q,c); }
inline void present(api::command_queue *,api::swapchain *s,const api::rect *,const api::rect *,std::uint32_t,const api::rect *){instance().present(s);}
inline bool update_descriptors(api::device *d,std::uint32_t n,const api::descriptor_table_update *u){instance().update_descriptor_tables(d,n,u);return false;}
inline bool copy_descriptors(api::device *d,std::uint32_t n,const api::descriptor_table_copy *c){instance().copy_descriptor_tables(d,n,c);return false;}
inline bool copy_resource(api::command_list *c,api::resource,api::resource d){instance().resource_transfer(c,d);return false;}
inline bool copy_texture(api::command_list *c,api::resource,std::uint32_t,const api::subresource_box *,api::resource d,std::uint32_t,const api::subresource_box *,api::filter_mode){instance().resource_transfer(c,d);return false;}
}
inline void register_callbacks() {
    reshade::register_event<reshade::addon_event::init_pipeline>(callbacks::init_pipeline);
    reshade::register_event<reshade::addon_event::destroy_pipeline>(callbacks::destroy_pipeline);
    reshade::register_event<reshade::addon_event::init_pipeline_layout>(callbacks::init_layout);
    reshade::register_event<reshade::addon_event::destroy_pipeline_layout>(callbacks::destroy_layout);
    reshade::register_event<reshade::addon_event::destroy_device>(callbacks::destroy_device);
    reshade::register_event<reshade::addon_event::destroy_resource>(callbacks::destroy_resource);
    reshade::register_event<reshade::addon_event::reset_command_list>(callbacks::reset);
    reshade::register_event<reshade::addon_event::destroy_command_list>(callbacks::reset);
    reshade::register_event<reshade::addon_event::bind_pipeline>(callbacks::bind_pipeline);
    reshade::register_event<reshade::addon_event::bind_viewports>(callbacks::bind_viewports);
    reshade::register_event<reshade::addon_event::bind_scissor_rects>(callbacks::bind_scissors);
    reshade::register_event<reshade::addon_event::bind_render_targets_and_depth_stencil>(callbacks::bind_targets);
    reshade::register_event<reshade::addon_event::begin_render_pass>(callbacks::begin_pass);
    reshade::register_event<reshade::addon_event::end_render_pass>(callbacks::end_pass);
    reshade::register_event<reshade::addon_event::push_descriptors>(callbacks::push);
    reshade::register_event<reshade::addon_event::bind_descriptor_tables>(callbacks::tables);
    reshade::register_event<reshade::addon_event::draw>(callbacks::draw);
    reshade::register_event<reshade::addon_event::draw_indexed>(callbacks::draw_indexed);
    reshade::register_event<reshade::addon_event::draw_or_dispatch_indirect>(callbacks::indirect);
    reshade::register_event<reshade::addon_event::execute_command_list>(callbacks::execute);
    reshade::register_event<reshade::addon_event::present>(callbacks::present);
    reshade::register_event<reshade::addon_event::update_descriptor_tables>(callbacks::update_descriptors);
    reshade::register_event<reshade::addon_event::copy_descriptor_tables>(callbacks::copy_descriptors);
    reshade::register_event<reshade::addon_event::copy_resource>(callbacks::copy_resource);
    reshade::register_event<reshade::addon_event::copy_texture_region>(callbacks::copy_texture);
}
inline void unregister_callbacks() {
    instance().set_compatible(false);
    reshade::unregister_event<reshade::addon_event::init_pipeline>(callbacks::init_pipeline);
    reshade::unregister_event<reshade::addon_event::destroy_pipeline>(callbacks::destroy_pipeline);
    reshade::unregister_event<reshade::addon_event::init_pipeline_layout>(callbacks::init_layout);
    reshade::unregister_event<reshade::addon_event::destroy_pipeline_layout>(callbacks::destroy_layout);
    reshade::unregister_event<reshade::addon_event::destroy_device>(callbacks::destroy_device);
    reshade::unregister_event<reshade::addon_event::destroy_resource>(callbacks::destroy_resource);
    reshade::unregister_event<reshade::addon_event::reset_command_list>(callbacks::reset);
    reshade::unregister_event<reshade::addon_event::destroy_command_list>(callbacks::reset);
    reshade::unregister_event<reshade::addon_event::bind_pipeline>(callbacks::bind_pipeline);
    reshade::unregister_event<reshade::addon_event::bind_viewports>(callbacks::bind_viewports);
    reshade::unregister_event<reshade::addon_event::bind_scissor_rects>(callbacks::bind_scissors);
    reshade::unregister_event<reshade::addon_event::bind_render_targets_and_depth_stencil>(callbacks::bind_targets);
    reshade::unregister_event<reshade::addon_event::begin_render_pass>(callbacks::begin_pass);
    reshade::unregister_event<reshade::addon_event::end_render_pass>(callbacks::end_pass);
    reshade::unregister_event<reshade::addon_event::push_descriptors>(callbacks::push);
    reshade::unregister_event<reshade::addon_event::bind_descriptor_tables>(callbacks::tables);
    reshade::unregister_event<reshade::addon_event::draw>(callbacks::draw);
    reshade::unregister_event<reshade::addon_event::draw_indexed>(callbacks::draw_indexed);
    reshade::unregister_event<reshade::addon_event::draw_or_dispatch_indirect>(callbacks::indirect);
    reshade::unregister_event<reshade::addon_event::execute_command_list>(callbacks::execute);
    reshade::unregister_event<reshade::addon_event::present>(callbacks::present);
    reshade::unregister_event<reshade::addon_event::update_descriptor_tables>(callbacks::update_descriptors);
    reshade::unregister_event<reshade::addon_event::copy_descriptor_tables>(callbacks::copy_descriptors);
    reshade::unregister_event<reshade::addon_event::copy_resource>(callbacks::copy_resource);
    reshade::unregister_event<reshade::addon_event::copy_texture_region>(callbacks::copy_texture);
}
} // namespace minecome::host_depth
