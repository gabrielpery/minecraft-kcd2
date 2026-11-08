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
    std::array<std::uint32_t, static_cast<std::size_t>(field::count)> offsets{};
    bool operator==(const reflected_layout &) const = default;
};
struct sample {
    vec4 ratio{}, nearest{}, clips{}, position{}, right{}, front{}, up{}, screen{}, hpos{};
    std::array<float, 16> projection{};
    api::viewport viewport{};
    api::resource source_depth{};
    api::device *device{};
    std::uint64_t captured_unix_ms{}, submitted_unix_ms{};
    bool reversed{};
    float far_metres{};
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
};

class tracker {
    struct root_binding { std::uint32_t parameter{}, binding{}, register_index{}, register_space{}, count{}; };
    struct device_state {
        std::unordered_map<std::uint64_t, reflected_layout> pipelines;
        std::unordered_map<std::uint64_t, std::vector<root_binding>> layouts;
    };
    struct command_state {
        std::uint64_t pipeline{}, root_layout{}, sampled_generation{};
        std::unordered_map<std::uint64_t, api::buffer_range> buffers;
        api::viewport viewport{};
        api::resource source_depth{};
        std::optional<sample> candidate;
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
    diagnostics diagnostics_{};
    std::atomic<std::uint64_t> invalidation_{0}, contention_{0};
    std::uint64_t observed_invalidation_{};

    std::unique_lock<std::mutex> recording_lock(bool invalidate_on_failure=true) {
        std::unique_lock lock(mutex_,std::try_to_lock);
        if (!lock.owns_lock()) {
            contention_.fetch_add(1,std::memory_order_relaxed);
            if (invalidate_on_failure) invalidation_.fetch_add(1,std::memory_order_release);
            return lock;
        }
        const auto invalidation=invalidation_.load(std::memory_order_acquire);
        if (invalidation!=observed_invalidation_) {
            // A dropped state-changing callback makes all command snapshots
            // incomplete. Reconstruct them from subsequent game bindings.
            commands_.clear(); submitted_.clear(); observed_invalidation_=invalidation;
        }
        return lock;
    }

public:
    // Supply before enabling metadata collection. Module lifetime must cover all
    // registered callbacks; the parent owns its verified DLL handle.
    void set_dxc_factory(DxcCreateInstanceProc factory) { dxc_factory_.store(factory); }
    bool metadata_available() const noexcept { return compatible_.load() && reflected_.load(); }
    // Exact executable guard belongs to the caller. Enable metadata collection
    // before game pipelines are created, but do not arm reads before gameplay.
    void set_compatible(bool value) { compatible_.store(value); if (!value) arm(false,{}); }
    void arm(bool value, const expected_view &view) {
        armed_.store(false);
        std::scoped_lock lock(mutex_);
        expected_=view; ++generation_; frame_attempts_=0; submitted_.clear();
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
        for (std::uint32_t i=0;i<count;++i) {
            if (objects[i].type!=api::pipeline_subobject_type::vertex_shader &&
                objects[i].type!=api::pipeline_subobject_type::pixel_shader) continue;
            if (!objects[i].data || objects[i].count!=1) continue;
            const auto &shader=*static_cast<const api::shader_desc *>(objects[i].data);
            auto layout=reflect(shader.code,shader.code_size,dxc_factory_.load());
            if (layout) {
                if (found && *found!=*layout) return;
                found=layout;
            }
        }
        std::scoped_lock lock(mutex_);
        if (found) { devices_[device].pipelines[pipeline.handle]=*found; ++diagnostics_.shaders_reflected; reflected_.store(true); }
        else ++diagnostics_.reflection_rejected;
    }
    void destroy_pipeline(api::device *device, api::pipeline pipeline) {
        std::scoped_lock lock(mutex_); devices_[device].pipelines.erase(pipeline.handle);
    }
    void init_pipeline_layout(api::device *device, std::uint32_t count,
                              const api::pipeline_layout_param *params, api::pipeline_layout layout) {
        if (!compatible_.load() || device->get_api()!=api::device_api::d3d12) return;
        std::vector<root_binding> found;
        const auto add=[&](std::uint32_t parameter,const api::descriptor_range &r) {
            if (r.type==api::descriptor_type::constant_buffer && r.count!=0 &&
                (r.visibility & api::shader_stage::all_graphics)!=api::shader_stage{})
                found.push_back({parameter,r.binding,r.dx_register_index,r.dx_register_space,r.count});
        };
        for (std::uint32_t i=0;i<count;++i) {
            if (params[i].type==api::pipeline_layout_param_type::push_descriptors) add(i,params[i].push_descriptors);
            else if (params[i].type==api::pipeline_layout_param_type::push_descriptors_with_ranges) {
                for (std::uint32_t j=0;j<params[i].descriptor_table.count;++j) add(i,params[i].descriptor_table.ranges[j]);
            } else if (params[i].type==api::pipeline_layout_param_type::push_descriptors_with_ranges_and_flags) {
                for (std::uint32_t j=0;j<params[i].descriptor_table_with_flags.count;++j) add(i,params[i].descriptor_table_with_flags.ranges[j]);
            }
        }
        std::scoped_lock lock(mutex_); devices_[device].layouts[layout.handle]=std::move(found);
    }
    void destroy_pipeline_layout(api::device *device, api::pipeline_layout layout) {
        std::scoped_lock lock(mutex_); devices_[device].layouts.erase(layout.handle);
    }
    void destroy_device(api::device *device) {
        std::scoped_lock lock(mutex_); devices_.erase(device); commands_.clear(); submitted_.clear();
    }
    void destroy_resource(api::device *device,api::resource resource) {
        if (!armed_.load()) return;
        auto lock=recording_lock(); if (!lock.owns_lock()) return;
        submitted_.erase(device,resource);
        for (auto &[cmd,state]:commands_) {
            if (cmd->get_device()!=device) continue;
            const auto previous=state.buffers.size();
            std::erase_if(state.buffers,[&](const auto &entry) { return entry.second.buffer==resource; });
            if (state.source_depth==resource || previous!=state.buffers.size()) {
                if (state.source_depth==resource) state.source_depth={};
                state.candidate.reset(); state.sampled_generation=0;
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
    void bind_depth(api::command_list *cmd,api::resource_view dsv) {
        if (!armed_.load()) return;
        auto lock=recording_lock(); if (!lock.owns_lock()) return;
        commands_[cmd].source_depth=dsv.handle ? cmd->get_device()->get_resource_from_view(dsv) : api::resource{};
    }
    void push_descriptors(api::command_list *cmd,api::shader_stage stages,api::pipeline_layout layout,
                          std::uint32_t parameter,const api::descriptor_table_update &update) {
        if (!armed_.load() || (stages & api::shader_stage::all_graphics)==api::shader_stage{}) return;
        auto lock=recording_lock(); if (!lock.owns_lock()) return;
        auto &state=commands_[cmd];
        if (state.root_layout!=layout.handle) { state.buffers.clear(); state.root_layout=layout.handle; }
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
                                std::uint32_t,std::uint32_t,const api::descriptor_table *,std::uint32_t,const std::uint32_t *) {
        if (!armed_.load() || (stages & api::shader_stage::all_graphics)==api::shader_stage{}) return;
        auto lock=recording_lock(); if (!lock.owns_lock()) return;
        auto &state=commands_[cmd];
        if (state.root_layout!=layout.handle) { state.buffers.clear(); state.root_layout=layout.handle; }
    }
    void draw(api::command_list *cmd) {
        if (!armed_.load()) return;
        auto lock=recording_lock(false); if (!lock.owns_lock()) return;
        auto &state=commands_[cmd];
        if (frame_attempts_>=64 || state.sampled_generation==generation_ ||
            !state.source_depth.handle || !fresh(expected_,unix_milliseconds()) || !viewport_matches(state.viewport,expected_)) return;
        auto *device=cmd->get_device();
        auto &data=devices_[device];
        const auto pipeline=data.pipelines.find(state.pipeline);
        const auto layout=data.layouts.find(state.root_layout);
        if (pipeline==data.pipelines.end() || layout==data.layouts.end()) return;
        for (const auto &root:layout->second) {
            const auto &reflected=pipeline->second;
            if (root.register_space!=reflected.register_space || root.register_index>reflected.register_index ||
                reflected.register_index-root.register_index>=root.count) continue;
            const std::uint64_t binding=static_cast<std::uint64_t>(root.binding)+reflected.register_index-root.register_index;
            if (binding>UINT32_MAX) continue;
            const auto buffer=state.buffers.find((static_cast<std::uint64_t>(root.parameter)<<32)|binding);
            if (buffer==state.buffers.end() || !buffer->second.buffer.handle) continue;
            const auto range=buffer->second;
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
inline void bind_targets(api::command_list *c,std::uint32_t,const api::resource_view *,api::resource_view d) { instance().bind_depth(c,d); }
inline bool begin_pass(api::command_list *c,std::uint32_t,const api::render_pass_render_target_desc *,const api::render_pass_depth_stencil_desc *d,api::render_pass_flags) { instance().bind_depth(c,d ? d->view : api::resource_view{}); return false; }
inline bool end_pass(api::command_list *c) { instance().bind_depth(c,{}); return false; }
inline void push(api::command_list *c,api::shader_stage s,api::pipeline_layout l,std::uint32_t p,const api::descriptor_table_update &u) { instance().push_descriptors(c,s,l,p,u); }
inline void tables(api::command_list *c,api::shader_stage s,api::pipeline_layout l,std::uint32_t f,std::uint32_t n,const api::descriptor_table *t,std::uint32_t dn,const std::uint32_t *o) { instance().bind_descriptor_tables(c,s,l,f,n,t,dn,o); }
inline bool draw(api::command_list *c,std::uint32_t,std::uint32_t,std::uint32_t,std::uint32_t) { instance().draw(c); return false; }
inline bool draw_indexed(api::command_list *c,std::uint32_t,std::uint32_t,std::uint32_t,std::int32_t,std::uint32_t) { instance().draw(c); return false; }
inline bool indirect(api::command_list *c,api::indirect_command type,api::resource,std::uint64_t,std::uint32_t,std::uint32_t) {
    if (type==api::indirect_command::draw || type==api::indirect_command::draw_indexed) instance().draw(c);
    return false;
}
inline void execute(api::command_queue *q,api::command_list *c) { instance().execute_command_list(q,c); }
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
    reshade::register_event<reshade::addon_event::bind_render_targets_and_depth_stencil>(callbacks::bind_targets);
    reshade::register_event<reshade::addon_event::begin_render_pass>(callbacks::begin_pass);
    reshade::register_event<reshade::addon_event::end_render_pass>(callbacks::end_pass);
    reshade::register_event<reshade::addon_event::push_descriptors>(callbacks::push);
    reshade::register_event<reshade::addon_event::bind_descriptor_tables>(callbacks::tables);
    reshade::register_event<reshade::addon_event::draw>(callbacks::draw);
    reshade::register_event<reshade::addon_event::draw_indexed>(callbacks::draw_indexed);
    reshade::register_event<reshade::addon_event::draw_or_dispatch_indirect>(callbacks::indirect);
    reshade::register_event<reshade::addon_event::execute_command_list>(callbacks::execute);
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
    reshade::unregister_event<reshade::addon_event::bind_render_targets_and_depth_stencil>(callbacks::bind_targets);
    reshade::unregister_event<reshade::addon_event::begin_render_pass>(callbacks::begin_pass);
    reshade::unregister_event<reshade::addon_event::end_render_pass>(callbacks::end_pass);
    reshade::unregister_event<reshade::addon_event::push_descriptors>(callbacks::push);
    reshade::unregister_event<reshade::addon_event::bind_descriptor_tables>(callbacks::tables);
    reshade::unregister_event<reshade::addon_event::draw>(callbacks::draw);
    reshade::unregister_event<reshade::addon_event::draw_indexed>(callbacks::draw_indexed);
    reshade::unregister_event<reshade::addon_event::draw_or_dispatch_indirect>(callbacks::indirect);
    reshade::unregister_event<reshade::addon_event::execute_command_list>(callbacks::execute);
}
} // namespace minecome::host_depth
