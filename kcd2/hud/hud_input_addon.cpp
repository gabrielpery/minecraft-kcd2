// Separate keyboard UI experiment derived from the verified stream compositor.
// The installed/default hud_stream_addon.cpp remains byte-for-byte untouched.
// Input APIs: pinned ReShade include/reshade_api.hpp:114-152,721;
// source/runtime_api.cpp:16-63 and runtime_gui.cpp:843-845,1502-1508.
// EldenCraft compositor/src/addon.cpp:350-389 uses the same public key/block APIs.
// Only keys 1-9/E/Esc are forwarded. F8 is a one-shot physical ownership latch.
// No mouse forwarding: public DirectInput blocking does not prove axis capture.
// Exact inspected upstreams for unchanged rendering:
// ReShade v6.8.0 18deaa52de0c425a78b329e9cb3c497281cd00ec,
// include/reshade_api_device.hpp; source/d3d12/d3d12_impl_command_queue.cpp:130-134;
// source/d3d12/d3d12_impl_command_list_immediate.cpp:169-172;
// source/runtime.cpp reset ordering and runtime_api.cpp semantic cache.
// EldenCraft ba7591cdde9fb16e17552cfe53546f44d0fd856e,
// compositor/src/addon.cpp:171-190,250-297: persistent texture, aligned upload
// buffers, copy barriers and fences. This original transport uses a Win32 mutex,
// not EldenCraft's mapping protocol. No engine offsets or game API calls.
// Public ReShade signal/semantic APIs may internally flush/wait; our frame path
// never waits for a free staging slot or performs mapping/file IO.
#include "stream_channel.hpp"
#include "input_channel.hpp"
#include "hud_contract.hpp"
#include <reshade.hpp>
#include <algorithm>
#include <array>
#include <atomic>
#include <cstring>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <thread>
#include <unordered_map>

namespace {
namespace api = reshade::api;
namespace hud = minecome::hud;
namespace st = minecome::hud::stream;
namespace ui = minecome::hud::input;
constexpr char exe_sha[] = "a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a";
constexpr char effect_name[] = "MineComeHud.fx", semantic[] = "MINECOME_HUD_1";
// Stable until module unload; fallback callbacks must never dereference Service
// without the runtime lifetime lock while AddonUninit can delete it.
std::atomic<bool> has_armed{false};
std::atomic<bool> input_has_started{false},input_force_close{false};
void receipt(std::string_view event, std::string_view result, std::string_view run = {}) {
    const std::string message = "[MineComeHudInput] {\"schema\":1,\"event\":\""+std::string(event)+
        "\",\"result\":\""+std::string(result)+"\",\"run\":\""+std::string(run)+"\",\"visual_verified\":false}";
    reshade::log::message(reshade::log::level::info,message.c_str());
}
void input_receipt(std::string_view event,const ui::Writer &inputs,std::string_view run,std::uint64_t closed_wait=0) {
    const auto &status=inputs.status();
    std::ostringstream line;
    line << "[MineComeHudInput] {\"schema\":1,\"event\":\"" << event << "\",\"run\":\"" << run
         << "\",\"reason\":\"" << inputs.reason() << "\",\"host_state\":" << status.state
         << ",\"guest_state\":" << status.ack.state << ",\"events_sent\":" << status.sequence
         << ",\"events_acknowledged\":" << status.ack.sequence
         << ",\"max_prearm_ack_age_ms\":" << status.max_prearm_ack_age_ms
         << ",\"prearm_stale_observations\":" << status.prearm_stale_observations
         << ",\"prearm_recoveries\":" << status.prearm_recoveries
         << ",\"rejected_at_utc_ms\":" << status.rejected_at_utc_ms
         << ",\"rejected_ack_utc_ms\":" << status.rejected_ack_utc_ms
         << ",\"rejected_host_state\":" << status.rejected_host_state
         << ",\"closed_ack_wait_ms\":" << closed_wait << ",\"visual_verified\":false}";
    reshade::log::message(reshade::log::level::info,line.str().c_str());
}
struct Session {
    st::Identity identity;
    std::uint64_t begun = 0, deadline = 0;
    bool live(std::uint64_t utc, std::uint64_t steady) const {
        return utc < identity.expires_utc_ms && steady >= begun && steady < deadline;
    }
};
struct Service {
    st::Handle stop{CreateEventW(nullptr,TRUE,FALSE,nullptr)};
    std::thread worker;
    std::wstring config;
    std::atomic<bool> compatible{false}, terminal{false};
    std::atomic<std::shared_ptr<const Session>> session;
    std::atomic<std::shared_ptr<const st::Frame>> publication;
    std::atomic<std::shared_ptr<const ui::Status>> input_status;
    ui::Mailbox input_mailbox;
    std::atomic<unsigned> input_request{0}; // 0 waiting, 1 arm, 2 close.
    std::atomic<std::uint64_t> last_input_render{0};
    std::atomic<api::effect_runtime *> input_owner{nullptr};
    std::atomic<std::uint64_t> uploaded{0}, dropped{0}, submitted{0};
    std::atomic<unsigned> renderer_error{0};
    explicit Service(HMODULE module) {
        const auto path = st::module_path(module); const auto slash = path.find_last_of(L"/\\");
        if (slash != path.npos) config = path.substr(0,slash+1)+L"MineComeHudInput.ini";
    }
    bool stopping() const { return !stop || WaitForSingleObject(stop.value,0) != WAIT_TIMEOUT; }
    void end(std::string_view why, std::string_view run) {
        input_force_close.store(true,std::memory_order_release);
        terminal.store(true,std::memory_order_release);
        publication.store({},std::memory_order_release);
        receipt("session_end",why,run);
        std::ostringstream counters;
        counters << "[MineComeHudInput] {\"schema\":1,\"event\":\"final_counters\",\"run\":\"" << run
                 << "\",\"uploaded\":" << uploaded.load() << ",\"dropped\":" << dropped.load()
                 << ",\"submitted\":" << submitted.load() << ",\"visual_verified\":false}";
        reshade::log::message(reshade::log::level::info,counters.str().c_str());
    }
    void run() noexcept {
        try {
            std::string digest;
            if (!st::read_file(st::module_path(),512u*1024u*1024u,stop.value,nullptr,&digest) || digest != exe_sha) {
                receipt("compatibility","exe_rejected"); return;
            }
            const auto pid=GetCurrentProcessId(); const auto start=st::process_start();
            if (!start || config.empty()) { receipt("compatibility","process_identity_failed"); return; }
            compatible.store(true,std::memory_order_release); receipt("compatibility","exact_tools_exe");
            st::Identity identity;
            std::string last_error;
            while (!stopping()) {
                std::vector<std::uint8_t> bytes;
                if (st::read_file(config,st::max_arm_bytes,stop.value,&bytes,nullptr)) {
                    std::string error;
                    if (st::parse_arm(std::string_view(reinterpret_cast<const char *>(bytes.data()),bytes.size()),
                                      pid,start,st::utc_ms(),identity,error)) break;
                    if (error != last_error) { receipt("arm",error); last_error=error; }
                }
                WaitForSingleObject(stop.value,100);
            }
            if (stopping()) return;
            // One accepted immutable arm per process. No runtime reload, bad
            // producer or replacement config can reopen or renew this session.
            auto accepted=std::make_shared<Session>(); accepted->identity=identity;
            const auto utc=st::utc_ms(); accepted->begun=st::steady_ms();
            if (identity.expires_utc_ms <= utc || identity.expires_utc_ms-utc > st::max_lease_ms) {
                end("arm_expired",identity.run); return;
            }
            accepted->deadline=accepted->begun+(identity.expires_utc_ms-utc);
            st::Channel channel;
            if (!channel.open(identity)) { end(channel.reason(),identity.run); return; }
            session.store(accepted,std::memory_order_release); has_armed.store(true,std::memory_order_release);
            receipt("arm","accepted",identity.run);
            ui::Writer inputs;
            bool input_created=inputs.create(identity),input_closed_logged=false;
            if(!input_created) receipt("input",inputs.reason(),identity.run);
            input_status.store(std::make_shared<ui::Status>(inputs.status()),std::memory_order_release);
            std::vector<ui::Event> pending_input;pending_input.reserve(ui::ring_count);
            auto reported=st::steady_ms(); bool first=false; unsigned last_renderer_error=0;
            while (!stopping()) {
                if(input_created) {
                    const auto now=st::steady_ms();
                    const auto last_render=last_input_render.load(std::memory_order_acquire);
                    if(input_force_close.load(std::memory_order_acquire)||input_request.load(std::memory_order_acquire)==2||input_mailbox.overflowed())
                        inputs.finish("ownership_closed");
                    else if(inputs.status().state==1&&(!last_render||now<last_render||now-last_render>ui::fresh_ms))
                        inputs.finish("render_stale");
                    else {
                        inputs.poll();
                        if(inputs.status().state==0&&input_request.load(std::memory_order_acquire)==1) {
                            if(!inputs.arm())inputs.finish("arm_not_ready");
                            else {receipt("input","keyboard_armed",identity.run);input_receipt("input_armed",inputs,identity.run);}
                        }
                        if(inputs.status().state==1) {
                            ui::Event event;
                            while(pending_input.size()<ui::ring_count&&input_mailbox.pop(event))pending_input.push_back(event);
                            if(!pending_input.empty()&&inputs.append(pending_input))pending_input.clear();
                        }
                    }
                    // A contended mutex may defer the terminal header. Retry
                    // that bounded write and observe the guest's close ACK.
                    if(inputs.status().state==2)inputs.poll();
                    input_status.store(std::make_shared<ui::Status>(inputs.status()),std::memory_order_release);
                    if(inputs.status().state==2&&!input_closed_logged) {
                        receipt("input",inputs.reason(),identity.run);input_receipt("input_closed",inputs,identity.run);input_closed_logged=true;
                    }
                }
                std::shared_ptr<const st::Frame> next;
                const auto result=channel.poll(next);
                if (result == st::Poll::closed || result == st::Poll::failed) {
                    // Withdraw rendered ownership immediately. Keep only the
                    // closed input mapping briefly so the real client tick can
                    // acknowledge its control release before handles vanish.
                    end(channel.reason(),identity.run);
                    if(input_created) {
                        inputs.finish("image_channel_closed");
                        const auto close_started=st::steady_ms();
                        while(!stopping()&&inputs.status().ack.state!=2&&st::steady_ms()-close_started<1500) {
                            inputs.poll();
                            input_status.store(std::make_shared<ui::Status>(inputs.status()),std::memory_order_release);
                            WaitForSingleObject(stop.value,5);
                        }
                        input_receipt("input_final",inputs,identity.run,st::steady_ms()-close_started);
                    }
                    return;
                }
                if (next) {
                    publication.store(std::move(next),std::memory_order_release);
                    if (!first) { receipt("frame","first_received",identity.run); first=true; }
                }
                const auto renderer=renderer_error.load(std::memory_order_relaxed);
                if (renderer && renderer != last_renderer_error) {
                    receipt("renderer","failure_"+std::to_string(renderer),identity.run); last_renderer_error=renderer;
                }
                const auto now=st::steady_ms();
                if (now-reported >= 5000) {
                    std::ostringstream line;
                    line << "[MineComeHudInput] {\"schema\":1,\"event\":\"counters\",\"run\":\"" << identity.run
                         << "\",\"uploaded\":" << uploaded.load() << ",\"dropped\":" << dropped.load()
                         << ",\"submitted\":" << submitted.load() << ",\"visual_verified\":false}";
                    reshade::log::message(reshade::log::level::info,line.str().c_str()); reported=now;
                }
                WaitForSingleObject(stop.value,5);
            }
            end("stopped",identity.run);
        } catch (...) {
            terminal.store(true,std::memory_order_release); publication.store({},std::memory_order_release);
            try { end("worker_exception",{}); } catch (...) { /* Already hidden; no exception may leave the worker. */ }
        }
    }
    void shutdown() {
        if (stop) SetEvent(stop.value);
        if (worker.joinable()) worker.join(); // AddonUninit, never DllMain/render.
    }
};
Service *service=nullptr;
struct Upload { api::resource buffer{}; std::uint64_t completion=0; };
struct RuntimeState {
    HWND window=nullptr;
    api::resource texture{};
    api::resource_view view{};
    api::fence fence{};
    std::array<Upload,3> uploads{};
    api::effect_uniform_variable active{},frame{},rect{};
    api::effect_technique technique{};
    bool bound=false, failed=false;
    bool reshade_overlay=false;
    ui::KeyboardGate keyboard;
    std::uint32_t previous_keys=0;
    std::uint32_t width=0,height=0,pitch=0;
    std::uint64_t next_fence=0,uploaded_sequence=0,uploaded_observation=0;
};
std::mutex runtimes_mutex;
std::unordered_map<api::effect_runtime *,RuntimeState> runtimes;
bool owned_window(HWND window) {
    DWORD pid=0;
    return window && IsWindow(window) && GetWindowThreadProcessId(window,&pid) && pid == GetCurrentProcessId();
}
bool visible(api::effect_runtime *runtime, const RuntimeState &state) {
    return reinterpret_cast<HWND>(runtime->get_hwnd()) == state.window && owned_window(state.window) &&
        !IsIconic(state.window) && IsWindowVisible(state.window) && GetForegroundWindow() == state.window;
}
void close_keyboard(api::effect_runtime *runtime) noexcept {
    if(service&&service->input_owner.load(std::memory_order_acquire)==runtime) {
        service->input_request.store(2,std::memory_order_release);
        input_force_close.store(true,std::memory_order_release);
    }
}
void capture_keyboard(api::effect_runtime *runtime,RuntimeState &state,bool composed) {
    if(!service)return;
    const auto peer=service->input_status.load(std::memory_order_acquire);
    if(!peer)return;
    constexpr std::array<std::uint32_t,11> keys{0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x45,0x1b};
    std::uint32_t held=0;
    for(std::size_t i=0;i<keys.size();++i)if(runtime->is_key_down(keys[i]))held|=1u<<i;
    const auto now=st::steady_ms();
    const bool eligible=composed&&!state.reshade_overlay&&visible(runtime,state)&&peer->live&&peer->state<2&&peer->ack.state==1&&
        ui::fresh(peer->ack.utc,st::utc_ms())&&now>=peer->observed&&now-peer->observed<=ui::fresh_ms&&
        !input_force_close.load(std::memory_order_acquire)&&!service->terminal.load(std::memory_order_acquire);
    const auto step=state.keyboard.update(eligible,runtime->is_key_down(VK_F8),held,now);
    if(step==ui::KeyboardGate::Step::closed) {close_keyboard(runtime);return;}
    if(step==ui::KeyboardGate::Step::idle)return;
    api::effect_runtime *empty=nullptr;
    if(service->input_owner.load(std::memory_order_acquire)!=runtime&&
        !service->input_owner.compare_exchange_strong(empty,runtime,std::memory_order_acq_rel))return;
    input_has_started.store(true,std::memory_order_release);
    service->last_input_render.store(now,std::memory_order_release);
    unsigned request=0;
    service->input_request.compare_exchange_strong(request,1,std::memory_order_acq_rel);
    // Public ReShade request affects the following frame. The gate waits two
    // fully neutral frames before forwarding UI edges. F8 itself may reach KCD.
    runtime->block_input_next_frame();
    if(step!=ui::KeyboardGate::Step::active||peer->state!=1)return;
    const auto changed=held^state.previous_keys;
    for(std::size_t i=0;i<keys.size();++i)if(changed&(1u<<i)) {
        const ui::Event event{st::utc_ms(),(held&(1u<<i))?ui::Kind::key_down:ui::Kind::key_up,keys[i],0,0,0};
        if(!service->input_mailbox.push(event)) {close_keyboard(runtime);return;}
    }
    state.previous_keys=held;
}
struct InputFrame {
    api::effect_runtime *runtime;
    RuntimeState &state;
    bool composed=false;
    ~InputFrame() {
        try {capture_keyboard(runtime,state,composed);}
        catch(...) {close_keyboard(runtime);}
    }
};
bool sdr(api::format format) {
    return format == api::format::r8g8b8a8_unorm || format == api::format::r8g8b8a8_unorm_srgb ||
        format == api::format::b8g8r8a8_unorm || format == api::format::b8g8r8a8_unorm_srgb;
}
void hide(api::effect_runtime *runtime, RuntimeState &state) {
    if (state.active != 0) runtime->set_uniform_value_bool(state.active,false);
}
void forget(RuntimeState &state) { state.active={}; state.frame={}; state.rect={}; state.technique={}; state.bound=false; }
bool handles(api::effect_runtime *runtime, RuntimeState &state) {
    if (state.active == 0) {
        state.active=runtime->find_uniform_variable(effect_name,"McHudActive");
        state.frame=runtime->find_uniform_variable(effect_name,"McHudFrame");
        state.rect=runtime->find_uniform_variable(effect_name,"McHudRect");
        state.technique=runtime->find_technique(effect_name,"MineComeHud");
    }
    if (state.active == 0 || state.frame == 0 || state.rect == 0 || state.technique == 0) { forget(state); return false; }
    return true;
}
void release(api::effect_runtime *runtime, RuntimeState &state, bool after_reset) {
    // ReShade invalidates effect handles before destroy_effect_runtime. Never
    // write a cached uniform then; clearing the external semantic cache is safe.
    if (after_reset) forget(state); else hide(runtime,state);
    if (state.view != 0) runtime->update_texture_bindings(semantic,{},{});
    if (state.texture != 0 || state.fence != 0 || state.uploads[0].buffer != 0) {
        // Lifecycle only. The staging fence precedes later effect draws and
        // cannot protect texture retirement; queue idle protects all of them.
        runtime->get_command_queue()->wait_idle();
        auto *device=runtime->get_device();
        for (auto &slot : state.uploads) { if (slot.buffer != 0) device->destroy_resource(slot.buffer); slot={}; }
        if (state.view != 0) device->destroy_resource_view(state.view);
        if (state.texture != 0) device->destroy_resource(state.texture);
        if (state.fence != 0) device->destroy_fence(state.fence);
    }
    state.texture={}; state.view={}; state.fence={}; forget(state);
}
bool fail(RuntimeState &state, unsigned code) {
    state.failed=true;
    if (service) service->renderer_error.store(code,std::memory_order_relaxed);
    return false;
}
bool allocate(api::effect_runtime *runtime, RuntimeState &state, const st::Frame &frame) {
    if (state.failed) return false;
    if (state.texture != 0) return state.width == frame.header.width && state.height == frame.header.height;
    auto *device=runtime->get_device();
    state.width=frame.header.width; state.height=frame.header.height; state.pitch=(state.width*4+255u)&~255u;
    if (!device->create_resource(api::resource_desc(state.width,state.height,1,1,api::format::r8g8b8a8_unorm,1,
            api::memory_heap::default_,api::resource_usage::shader_resource|api::resource_usage::copy_dest),
            nullptr,api::resource_usage::shader_resource,&state.texture) ||
        !device->create_resource_view(state.texture,api::resource_usage::shader_resource,
            api::resource_view_desc(api::format::r8g8b8a8_unorm),&state.view) ||
        !device->create_fence(0,api::fence_flags::none,&state.fence)) return fail(state,1);
    for (auto &slot : state.uploads) {
        if (!device->create_resource(api::resource_desc(std::uint64_t(state.pitch)*state.height,api::memory_heap::upload,
            api::resource_usage::copy_source),nullptr,api::resource_usage::cpu_access,&slot.buffer)) return fail(state,2);
    }
    return true;
}
bool upload(api::effect_runtime *runtime, api::command_list *commands, RuntimeState &state, const st::Frame &frame) {
    if (frame.header.sequence == state.uploaded_sequence) return true;
    auto *device=runtime->get_device(); auto *queue=runtime->get_command_queue();
    if (commands != queue->get_immediate_command_list()) return fail(state,3);
    if (!allocate(runtime,state,frame)) return false;
    const auto completed=device->get_completed_fence_value(state.fence);
    const auto slot=std::find_if(state.uploads.begin(),state.uploads.end(),[&](const auto &item) { return item.completion <= completed; });
    if (slot == state.uploads.end()) { ++service->dropped; return false; }
    void *mapped=nullptr;
    if (!device->map_buffer_region(slot->buffer,0,std::uint64_t(state.pitch)*state.height,api::map_access::write_only,&mapped)) {
        ++service->dropped; return false;
    }
    for (std::uint32_t row=0;row<state.height;++row)
        std::memcpy(static_cast<std::uint8_t *>(mapped)+std::size_t(row)*state.pitch,
            frame.premultiplied.data()+std::size_t(row)*frame.header.pitch,frame.header.pitch);
    device->unmap_buffer_region(slot->buffer);
    commands->barrier(state.texture,api::resource_usage::shader_resource,api::resource_usage::copy_dest);
    commands->copy_buffer_to_texture(slot->buffer,0,state.pitch/4,state.height,state.texture,0);
    commands->barrier(state.texture,api::resource_usage::copy_dest,api::resource_usage::shader_resource);
    // Pinned ReShade signal flushes its immediate command list before Signal.
    // This fences staging reads only; later effects and next uploads share the
    // same ordered queue. No explicit wait or busy-slot retry loop here.
    slot->completion=++state.next_fence;
    if (!queue->signal(state.fence,slot->completion)) return fail(state,4);
    state.uploaded_sequence=frame.header.sequence;
    state.uploaded_observation=frame.observation; // Never use latest pub age instead.
    ++service->uploaded; return true;
}
void on_init(api::effect_runtime *runtime) {
    if (runtime->get_device()->get_api() != api::device_api::d3d12) return;
    std::lock_guard lock(runtimes_mutex);
    RuntimeState state; state.window=reinterpret_cast<HWND>(runtime->get_hwnd());
    if (owned_window(state.window)) runtimes.try_emplace(runtime,std::move(state));
}
void on_destroy(api::effect_runtime *runtime) {
    std::lock_guard lock(runtimes_mutex);
    const auto it=runtimes.find(runtime); if (it == runtimes.end()) return;
    close_keyboard(runtime);release(runtime,it->second,true); runtimes.erase(it); receipt("cleanup","runtime_owned_resources_released");
}
void on_reload(api::effect_runtime *runtime) {
    std::lock_guard lock(runtimes_mutex);
    const auto it=runtimes.find(runtime); if (it != runtimes.end()) {close_keyboard(runtime);forget(it->second);}
}
bool on_overlay(api::effect_runtime *runtime,bool open,api::input_source) {
    std::lock_guard lock(runtimes_mutex);
    const auto it=runtimes.find(runtime);
    if(it!=runtimes.end()) {it->second.reshade_overlay=open;if(open)close_keyboard(runtime);}
    return false; // Observe ReShade's UI; never prevent it opening.
}
void on_begin(api::effect_runtime *runtime, api::command_list *commands, api::resource_view rtv, api::resource_view) {
    std::unique_lock lock(runtimes_mutex,std::try_to_lock);
    if (!lock.owns_lock()) {
        if(input_has_started.load(std::memory_order_acquire))input_force_close.store(true,std::memory_order_release);
        // Another runtime may be in a lifecycle callback. Do not wait, and do
        // not leave this runtime's previous layer enabled. Only a fresh handle
        // obtained inside this live effects callback is usable without access
        // to the guarded cache. Unarmed sessions still make no effect calls.
        try {
            if (has_armed.load(std::memory_order_acquire)) {
                const auto active=runtime->find_uniform_variable(effect_name,"McHudActive");
                if (active != 0) runtime->set_uniform_value_bool(active,false);
            }
        } catch (...) { /* No cached handles or Service access on the contended path. */ }
        return;
    }
    const auto it=runtimes.find(runtime);
    if (it == runtimes.end() || !service || !service->compatible.load(std::memory_order_acquire)) return;
    auto &state=it->second;
    InputFrame input_frame{runtime,state};
    try {
        // A withdrawn/expired publication must hide previously enabled effects.
        // Unarmed runtime has zero handles, so this makes no effect API call.
        hide(runtime,state);
        if (state.failed || service->terminal.load(std::memory_order_acquire)) return;
        const auto session=service->session.load(std::memory_order_acquire);
        const auto frame=service->publication.load(std::memory_order_acquire);
        auto now=st::steady_ms();
        if (!session || !frame || !session->live(st::utc_ms(),now) || !st::uploaded_fresh(frame->observation,now)) return;
        if (!visible(runtime,state) || !commands || rtv == 0 || !handles(runtime,state) ||
            !sdr(runtime->get_device()->get_resource_view_desc(rtv).format)) return;
        const auto target=runtime->get_device()->get_resource_from_view(rtv);
        if (target == 0) return;
        const auto desc=runtime->get_device()->get_resource_desc(target);
        if (desc.type != api::resource_type::texture_2d || !sdr(desc.texture.format)) return;
        const auto rectangle=hud::fit_rect(frame->header.width,frame->header.height,desc.texture.width,desc.texture.height);
        if (rectangle.width <= 0 || rectangle.height <= 0) return;
        upload(runtime,commands,state,*frame);
        if (state.failed || state.uploaded_sequence == 0 || state.view == 0) return;
        if (!state.bound) {
            runtime->update_texture_bindings(semantic,state.view,state.view);
            runtime->set_uniform_value_int(state.frame,0);
            runtime->set_technique_state(state.technique,true);
            state.bound=true;
        }
        now=st::steady_ms();
        // Recheck after ReShade resource/semantic APIs; their implementation can
        // take time. A stream of dropped new frames never refreshes resident age.
        if (service->terminal.load(std::memory_order_acquire) || !session->live(st::utc_ms(),now) ||
            !st::uploaded_fresh(state.uploaded_observation,now) || !visible(runtime,state)) return;
        runtime->set_uniform_value_float(state.rect,rectangle.x,rectangle.y,rectangle.width,rectangle.height);
        runtime->set_uniform_value_bool(state.active,true); ++service->submitted;
        input_frame.composed=true;
    } catch (...) { fail(state,5); hide(runtime,state); }
}
} // namespace
extern "C" __declspec(dllexport) const char *NAME="MineCome bounded Minecraft keyboard UI lab";
extern "C" __declspec(dllexport) const char *DESCRIPTION="Exact KCD2 tools/D3D12 genuine UI stream; one F8 activation, keys 1-9/E/Esc only, at most 30 seconds.";
extern "C" __declspec(dllexport) bool AddonInit(HMODULE addon, HMODULE reshade_module) {
    if (!reshade::register_addon(addon,reshade_module)) return false;
    try {
        service=new Service(addon);
        if (!service->stop || service->config.empty()) throw std::runtime_error("service_init");
        service->worker=std::thread([] { service->run(); });
        reshade::register_event<reshade::addon_event::init_effect_runtime>(on_init);
        reshade::register_event<reshade::addon_event::destroy_effect_runtime>(on_destroy);
        reshade::register_event<reshade::addon_event::reshade_reloaded_effects>(on_reload);
        reshade::register_event<reshade::addon_event::reshade_begin_effects>(on_begin);
        reshade::register_event<reshade::addon_event::reshade_open_overlay>(on_overlay);
        receipt("addon","disarmed"); return true;
    } catch (...) {
        if (service) { service->shutdown(); delete service; service=nullptr; }
        reshade::unregister_addon(addon,reshade_module); return false;
    }
}
extern "C" __declspec(dllexport) void AddonUninit(HMODULE addon, HMODULE reshade_module) {
    reshade::unregister_event<reshade::addon_event::init_effect_runtime>(on_init);
    reshade::unregister_event<reshade::addon_event::destroy_effect_runtime>(on_destroy);
    reshade::unregister_event<reshade::addon_event::reshade_reloaded_effects>(on_reload);
    reshade::unregister_event<reshade::addon_event::reshade_begin_effects>(on_begin);
    reshade::unregister_event<reshade::addon_event::reshade_open_overlay>(on_overlay);
    if (service) service->shutdown();
    {
        std::lock_guard lock(runtimes_mutex);
        for (auto &[runtime,state] : runtimes) release(runtime,state,false);
        runtimes.clear(); delete service; service=nullptr;
    }
    receipt("addon","worker_joined_resources_released"); reshade::unregister_addon(addon,reshade_module);
}
BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) DisableThreadLibraryCalls(instance);
    return TRUE;
}
