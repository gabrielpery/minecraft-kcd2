// Separate keyboard UI experiment derived from the verified stream compositor.
// The installed/default hud_stream_addon.cpp remains byte-for-byte untouched.
// Input APIs: pinned ReShade include/reshade_api.hpp:114-152,721;
// source/runtime_api.cpp:16-63 and runtime_gui.cpp:843-845,1502-1508.
// EldenCraft compositor/src/addon.cpp:350-389 uses the same public key/block APIs.
// F8 is a one-shot physical ownership latch. The default target forwards only
// 1-9/E/Esc; the separate mouse target requires the original strict-capture API.
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
#include "input_diagnostics.hpp"
#ifdef MINECOME_HUD_REPEAT_SESSION
#include "rearm_receipt.hpp"
#include "rearm_native.hpp"
#if !defined(MINECOME_HUD_WALKING_AIMED)
#error Repeat sessions require the explicit walking aimed profile.
#endif
#endif
#if defined(MINECOME_HUD_WALKING_AIMED) && (!defined(MINECOME_HUD_PHYSICAL_MOVEMENT) || !defined(MINECOME_HUD_WORLD_CLICKS) || !defined(MINECOME_HUD_SELECTIVE_MOUSE))
#error Walking aimed input requires its explicit movement, world-click and selective capture definitions.
#endif
#if defined(MINECOME_HUD_PHYSICAL_MOVEMENT) && defined(MINECOME_HUD_WORLD_CLICKS) && !defined(MINECOME_HUD_WALKING_AIMED)
#error Movement and world-click profiles may only be combined by the explicit walking aimed target.
#endif
#if defined(MINECOME_HUD_GAMEPLAY_MOVEMENT) && (!defined(MINECOME_HUD_GAMEPLAY) || !defined(MINECOME_HUD_PHYSICAL_MOVEMENT) || !defined(MINECOME_HUD_SELECTIVE_MOUSE) || defined(MINECOME_HUD_WORLD_CLICKS))
#error Gameplay movement requires its explicit gameplay, physical movement and selective inventory profile without world clicks.
#endif
#if defined(MINECOME_HUD_GAMEPLAY_BLOCKS) && !defined(MINECOME_HUD_GAMEPLAY_MOVEMENT)
#error Gameplay world buttons require the sustained movement profile.
#endif
#ifdef MINECOME_HUD_GAMEPLAY_BLOCKS
#include "gameplay_world_buttons.hpp"
#endif
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
#include "gameplay_chat.hpp"
#if !defined(MINECOME_HUD_GAMEPLAY_BLOCKS)
#error Gameplay chat requires sustained movement and world-button ownership.
#endif
#endif
#ifdef MINECOME_HUD_PHYSICAL_MOVEMENT
#include "movement_forwarding.hpp"
#endif
#ifdef MINECOME_HUD_MOTION_FILTER
#include "motion_diagnostics_api.hpp"
#endif
#ifdef MINECOME_HUD_RAW_OWNER_FILTER
#include "raw_motion_diagnostics_api.hpp"
#endif
#ifdef MINECOME_HUD_LIVE_MOUSE
#ifdef MINECOME_HUD_SELECTIVE_MOUSE
#include "selective_capture_api.hpp"
#include "selective_diagnostics.hpp"
#include "selective_forwarding.hpp"
#else
#include "mouse_capture_api.hpp"
#include "mouse_diagnostics.hpp"
#endif
#include "mouse_forwarding.hpp"
#endif
#ifdef MINECOME_HUD_WORLD_CLICKS
#include "world_click.hpp"
#endif
#include "hud_contract.hpp"
#ifdef MINECOME_HUD_GAMEPLAY
#include "gameplay_keyboard_api.hpp"
#endif
#include <reshade.hpp>
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
#include "host_depth.hpp"
#include "world_reprojection.hpp"
#endif
#include <algorithm>
#include <array>
#include <atomic>
#include <cstring>
#include <filesystem>
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
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
namespace depth = minecome::host_depth;
std::atomic<std::uint64_t> depth_frames{0};
std::atomic<std::uint64_t> depth_considered{0},depth_no_sample{0},depth_bad_view{0},depth_bad_source{0},depth_ready_changes{0};
std::atomic<std::uint64_t> depth_sample_age{0},depth_camera_age{0},depth_position{0},depth_basis{0},depth_projection{0},depth_other{0};
std::atomic<std::uint64_t> depth_reprojected{0},depth_warp_rejected{0},depth_strict_fallback{0};
// Five-second evidence must describe completed frames, not an atomic counter
// read midway through one frame's considered/outcome/readiness updates.
std::mutex depth_counters_mutex;
struct WarpRejection {
    depth::sample native;
    depth::expected_view guest;
    std::uint32_t width=0,height=0;
    std::uint64_t image_utc=0,now=0;
};
std::optional<WarpRejection> first_warp_rejection;
bool warp_rejection_reported=false;
constexpr const char *warp_uniform_names[]={"McWarpSourceOrigin","McWarpSourceForward","McWarpSourceUp","McWarpSourceTanHalf",
    "McWarpTargetOrigin","McWarpTargetRight","McWarpTargetForward","McWarpTargetUp","McWarpClipX","McWarpClipY","McWarpClipZ","McWarpClipW"};
#endif
#ifdef MINECOME_HUD_GAMEPLAY
constexpr std::uint32_t stream_schema = 3;
namespace gameplay_keyboard=minecome::gameplay_keyboard;
const gameplay_keyboard::Api *gameplay_keyboard_api=nullptr;
#else
constexpr std::uint32_t stream_schema = 1;
#endif
#ifdef MINECOME_HUD_MOTION_FILTER
namespace motion = minecome::motion;
motion::ReadDiagnostics motion_diagnostics=nullptr;
#endif
#ifdef MINECOME_HUD_RAW_OWNER_FILTER
namespace raw_motion = minecome::raw_motion;
raw_motion::ReadDiagnostics raw_motion_diagnostics=nullptr;
#endif
#ifdef MINECOME_HUD_WORLD_CLICKS
namespace world = minecome::hud::world;
#endif
#ifdef MINECOME_HUD_LIVE_MOUSE
#ifdef MINECOME_HUD_SELECTIVE_MOUSE
namespace mouse = minecome::selective;
#else
namespace mouse = minecome::mouse;
#endif
const mouse::Api *mouse_api=nullptr;
mouse::Notices mouse_notices;
void mouse_receipt(const char *event,mouse::Result result,const mouse::Snapshot &snapshot) noexcept {
    mouse_notices.push({event,result,snapshot});
}
void write_mouse_receipt(const mouse::Notice &notice,std::string_view run) {
    const auto &snapshot=notice.snapshot;
    std::ostringstream line;
    line<<"[MineComeHudInput] {\"schema\":1,\"event\":\""<<notice.event<<"\",\"run\":\""<<run<<"\",\"result\":"<<static_cast<unsigned>(notice.result)
        <<",\"flags\":"<<snapshot.flags<<",\"reason\":"<<snapshot.reason<<",\"generation\":"<<snapshot.generation
        <<",\"device_count\":"<<snapshot.device_count<<",\"eligible_devices\":"<<snapshot.eligible_devices
        <<",\"state_suppressions\":"<<snapshot.state_suppressions<<",\"data_suppressions\":"<<snapshot.data_suppressions
        <<",\"peek_suppressions\":"<<snapshot.peek_suppressions<<",\"queue_drains\":"<<snapshot.queue_drains
        <<",\"drain_failures\":"<<snapshot.drain_failures
#ifdef MINECOME_HUD_SELECTIVE_MOUSE
        <<",\"mode\":"<<static_cast<unsigned>(snapshot.mode)<<",\"axis_records_delivered\":"<<snapshot.axis_records_delivered
        <<",\"button_records_filtered\":"<<snapshot.button_records_filtered<<",\"buffer_overflows\":"<<snapshot.buffer_overflows
#endif
        ;
#ifdef MINECOME_HUD_MOTION_FILTER
    motion::Snapshot routes;
    const bool sampled=motion_diagnostics&&motion_diagnostics(&routes);
    line<<",\"motion_routes_sampled\":"<<(sampled?"true":"false");
    if(sampled)line<<",\"state_xy_observed\":"<<routes.state_xy_observed<<",\"state_xy_passed\":"<<routes.state_xy_passed
        <<",\"window_moves_passed\":"<<routes.window_moves_passed<<",\"raw_moves_passed\":"<<routes.raw_moves_passed
        <<",\"raw_mixed_blocked\":"<<routes.raw_mixed_blocked<<",\"raw_buffer_blocked\":"<<routes.raw_buffer_blocked
        <<",\"hook_motion_blocked\":"<<routes.hook_motion_blocked;
#endif
#ifdef MINECOME_HUD_RAW_OWNER_FILTER
    raw_motion::Snapshot raw_routes;
    const bool raw_sampled=raw_motion_diagnostics&&raw_motion_diagnostics(&raw_routes);
    line<<",\"raw_routes_sampled\":"<<(raw_sampled?"true":"false");
    if(raw_sampled)line<<",\"mouse_raw_packets_seen\":"<<raw_routes.mouse_raw_packets_seen
        <<",\"registered_helper_candidates\":"<<raw_routes.registered_helper_candidates
        <<",\"helper_moves_passed\":"<<raw_routes.helper_moves_passed
        <<",\"route_owner_rejected\":"<<raw_routes.route_owner_rejected
        <<",\"packet_rejected\":"<<raw_routes.packet_rejected;
#endif
    line<<",\"live_verified\":false}";
    reshade::log::message(reshade::log::level::info,line.str().c_str());
}
void drain_mouse_receipts(std::string_view run) {
    mouse::Notice notice;
    // Bound each worker iteration even if a producer continually refills.
    for(unsigned i=0;i<32&&mouse_notices.pop(notice);++i)write_mouse_receipt(notice,run);
    if(const auto dropped=mouse_notices.take_dropped()){
        const auto line="[MineComeHudInput] {\"schema\":1,\"event\":\"mouse_diagnostics_lost\",\"run\":\""+std::string(run)+"\",\"dropped\":"+std::to_string(dropped)+",\"live_verified\":false}";
        reshade::log::message(reshade::log::level::warning,line.c_str());
    }
}
#endif
constexpr char exe_sha[] = "a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a";
constexpr char effect_name[] = "MineComeHud.fx", semantic[] = "MINECOME_HUD_1";
// Stable until module unload; fallback callbacks must never dereference Service
// without the runtime lifetime lock while AddonUninit can delete it.
std::atomic<bool> has_armed{false};
struct InputSignals {
    std::atomic<bool> input_has_started{false},input_force_close{false};
    ui::FirstClose first_close;
};
// A contended callback retains its original signals, never the next run's.
std::atomic<std::shared_ptr<InputSignals>> input_signals{std::make_shared<InputSignals>()};
void record_close(ui::CloseCause cause) noexcept {
    ui::CloseSnapshot snapshot;snapshot.cause=cause;snapshot.utc=st::utc_ms();input_signals.load()->first_close.publish(snapshot);
}
bool close_receipt(std::string_view run) {
    ui::CloseSnapshot value;if(!input_signals.load()->first_close.read(value))return false;
    auto predicate=[&](unsigned mask){return !value.eligibility_sampled?"null":(value.eligibility_failures&mask)?"false":"true";};
    std::ostringstream line;
    line << "[MineComeHudInput] {\"schema\":1,\"event\":\"first_input_close\",\"run\":\"" << run
         << "\",\"cause\":\"" << ui::close_name(value.cause) << "\",\"closed_utc_ms\":" << value.utc
         << ",\"ack_utc_ms\":" << value.ack_utc << ",\"ack_observation_age_ms\":" << value.ack_observed_age
         << ",\"publication_age_ms\":" << value.publication_age << ",\"resident_age_ms\":" << value.resident_age
         << ",\"eligibility_failures\":" << value.eligibility_failures << ",\"composition_stage\":" << value.composition_stage
         << ",\"eligibility_sampled\":" << (value.eligibility_sampled?"true":"false")
         << ",\"composed\":" << predicate(1) << ",\"overlay_closed\":" << predicate(2)
         << ",\"focus_visible\":" << predicate(4) << ",\"ack_fresh\":" << predicate(32)
         << ",\"ack_snapshot_fresh\":" << predicate(64)
         << ",\"authorized_keys_held\":" << value.held_keys << ",\"f8_held\":" << (value.f8?"true":"false")
         << ",\"window_checks_sampled\":" << value.window.checked << ",\"window_checks_failed\":" << value.window.failed
         << ",\"runtime_window_matches\":" << value.window.value(ui::WindowCheck::runtime_handle)
         << ",\"window_handle_valid\":" << value.window.value(ui::WindowCheck::valid_handle)
         << ",\"window_process_owned\":" << value.window.value(ui::WindowCheck::owned_process)
         << ",\"window_not_minimized\":" << value.window.value(ui::WindowCheck::not_minimized)
         << ",\"window_visible\":" << value.window.value(ui::WindowCheck::visible)
         << ",\"window_is_foreground\":" << value.window.value(ui::WindowCheck::foreground)
         << ",\"foreground_pid\":";
    if(value.window.foreground_pid_sampled)line << value.window.foreground_pid;else line << "null";
    line << ",\"activation_elapsed_ms\":";
    if(value.activation_age_valid)line << value.activation_age_ms;else line << "null";
    line << '}';
    reshade::log::message(reshade::log::level::info,line.str().c_str());
    return true;
}
void receipt(std::string_view event, std::string_view result, std::string_view run = {}) {
    const std::string message = "[MineComeHudInput] {\"schema\":1,\"event\":\""+std::string(event)+
        "\",\"result\":\""+std::string(result)+"\",\"run\":\""+std::string(run)+"\",\"visual_verified\":false}";
    reshade::log::message(reshade::log::level::info,message.c_str());
}
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
// Optional developer capture: the test launcher supplies a fresh ignored
// runtime/evidence directory. No default disk writes, no draw-thread I/O and no
// shader assets in source control. Never overwrite a previous observation.
void save_rejected_depth_writer(std::string_view run) noexcept {
    try {
        std::array<wchar_t,4096> configured{};
        const auto size=GetEnvironmentVariableW(L"MINECOME_DEPTH_DIAGNOSTIC_DIR",configured.data(),static_cast<DWORD>(configured.size()));
        if(!size||size>=configured.size()||run.size()!=32||run.find_first_not_of("0123456789abcdef")!=std::string_view::npos)return;
        const std::filesystem::path directory(configured.data());if(!directory.is_absolute())return;
        for(auto cursor=directory;!cursor.empty();){
            const auto attributes=GetFileAttributesW(cursor.c_str());
            if(attributes==INVALID_FILE_ATTRIBUTES||(attributes&FILE_ATTRIBUTE_REPARSE_POINT)||!(attributes&FILE_ATTRIBUTE_DIRECTORY))return;
            auto parent=cursor.parent_path();if(parent==cursor)break;cursor=std::move(parent);
        }
        const auto snapshot=depth::instance().take_rejected_pipeline();if(!snapshot)return;
        const auto prefix="native-depth-rejected-"+std::string(run);
        const auto write=[&](const std::string &suffix,const void *data,std::size_t bytes){
            if(bytes>2u*1024u*1024u)return false;
            const auto path=directory/(prefix+suffix);
            st::Handle file(CreateFileW(path.c_str(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL|FILE_FLAG_OPEN_REPARSE_POINT,nullptr));
            DWORD written=0;return file&&WriteFile(file.value,data,static_cast<DWORD>(bytes),&written,nullptr)&&written==bytes;
        };
        bool saved=true;
        if(!snapshot->vertex.empty())saved=write("-vs.dxil",snapshot->vertex.data(),snapshot->vertex.size())&&saved;
        if(!snapshot->pixel.empty())saved=write("-ps.dxil",snapshot->pixel.data(),snapshot->pixel.size())&&saved;
        std::ostringstream metadata;
        metadata<<"{\"schema\":1,\"run\":\""<<run<<"\",\"pipeline\":"<<snapshot->pipeline
            <<",\"source_depth\":"<<snapshot->source_depth<<",\"vertex_bytes\":"<<snapshot->vertex.size()
            <<",\"pixel_bytes\":"<<snapshot->pixel.size()<<",\"width\":"<<snapshot->width<<",\"height\":"<<snapshot->height
            <<",\"depth_compare\":"<<snapshot->depth_compare<<",\"depth_enabled\":"<<(snapshot->depth_enabled?"true":"false")
            <<",\"depth_write\":"<<(snapshot->depth_write?"true":"false")<<",\"saved\":"<<(saved?"true":"false")<<"}";
        const auto text=metadata.str();saved=write(".json",text.data(),text.size())&&saved;
        receipt("depth_writer_snapshot",saved?"saved":"write_failed",run);
    }catch(...){receipt("depth_writer_snapshot","capture_failed",run);}
}
#endif
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
#ifdef MINECOME_HUD_REPEAT_SESSION
namespace rearm = minecome::hud::rearm;
bool prepare_repeat_generation();
bool repeat_render_retired();
#endif
struct Service {
    st::Handle stop{CreateEventW(nullptr,TRUE,FALSE,nullptr)};
    std::thread worker;
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
    HMODULE renderer_module=nullptr,shader_compiler_module=nullptr;
#endif
    std::wstring config;
    std::atomic<bool> compatible{false}, terminal{false}, busy_request_preserves_lease{false};
    std::atomic<std::shared_ptr<const Session>> session;
    std::atomic<std::shared_ptr<const st::Frame>> publication;
    std::atomic<std::shared_ptr<const ui::Status>> input_status;
    std::unique_ptr<ui::Mailbox> input_mailbox=std::make_unique<ui::Mailbox>();
#ifdef MINECOME_HUD_WORLD_CLICKS
    std::unique_ptr<world::Queue> world_clicks=std::make_unique<world::Queue>();
    world::Click pending_click;
#endif
    std::atomic<unsigned> input_request{0}; // 0 waiting, 1 arm, 2 close.
    std::atomic<std::uint64_t> last_input_render{0};
    std::atomic<api::effect_runtime *> input_owner{nullptr};
    std::atomic<std::uint64_t> uploaded{0}, dropped{0}, submitted{0}, busy_renewals_deferred{0};
    std::atomic<unsigned> renderer_error{0};
    // Latest preactivation observation only; worker logs it at the existing
    // five-second cadence. Independent diagnostic fields may span two adjacent
    // frames and never authorize capture or refresh any ownership/freshness.
    std::atomic<std::uint64_t> prearm_samples{0},prearm_observed{0};
    std::atomic<std::uint32_t> prearm_failures{0},prearm_keys{0},prearm_f8{0},prearm_stage{0};
#ifdef MINECOME_HUD_LIVE_MOUSE
    std::atomic<std::uint32_t> prearm_mouse_result{0},prearm_mouse_flags{0},prearm_mouse_reason{0};
    std::atomic<std::uint32_t> prearm_mouse_buttons{0},prearm_mouse_devices{0},prearm_mouse_eligible{0};
#endif
#ifdef MINECOME_HUD_REPEAT_SESSION
    rearm::Policy rearm_policy;
    std::atomic<bool> retiring{false};
    st::Handle producer;
#endif
    explicit Service(HMODULE module) {
        const auto path = st::module_path(module); const auto slash = path.find_last_of(L"/\\");
        if (slash != path.npos) config = path.substr(0,slash+1)+
#ifdef MINECOME_HUD_GAMEPLAY_BLOCKS
            #ifdef MINECOME_HUD_GAMEPLAY_CHAT
            L"MineComeHudGameplayChat.ini";
            #else
            L"MineComeHudGameplayBlocks.ini";
            #endif
#elif defined(MINECOME_HUD_GAMEPLAY_MOVEMENT)
            L"MineComeHudGameplayMovement.ini";
#elif defined(MINECOME_HUD_GAMEPLAY)
            L"MineComeHudGameplay.ini";
#elif defined(MINECOME_HUD_REPEAT_SESSION)
            L"MineComeHudWalkingRepeat.ini";
#elif defined(MINECOME_HUD_WALKING_AIMED)
            L"MineComeHudWalkingAimed.ini";
#elif defined(MINECOME_HUD_PHYSICAL_MOVEMENT)
            L"MineComeHudMovement.ini";
#elif defined(MINECOME_HUD_SELECTIVE_MOUSE)
            L"MineComeHudSelective.ini";
#elif defined(MINECOME_HUD_WORLD_CLICKS)
            L"MineComeHudWorld.ini";
#elif defined(MINECOME_HUD_LIVE_MOUSE)
            L"MineComeHudMouse.ini";
#else
            L"MineComeHudInput.ini";
#endif
    }
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
    ~Service(){depth::instance().set_dxc_factory(nullptr);if(shader_compiler_module)FreeLibrary(shader_compiler_module);}
#endif
    bool stopping() const { return !stop || WaitForSingleObject(stop.value,0) != WAIT_TIMEOUT; }
#ifdef MINECOME_HUD_WORLD_CLICKS
    void drain_world_clicks(const Session &accepted,ui::Writer &inputs) {
        // Worker-only formatting/log IO. No record may outlive the current
        // activation, image, ACK or original physical capture freshness.
        for(unsigned i=0;i<world::max_clicks;++i){
            if(!pending_click.sequence&&!world_clicks->pop(pending_click))return;
            const auto now=st::steady_ms(),utc=st::utc_ms();const auto &peer=inputs.status();
            const auto frame=publication.load(std::memory_order_acquire);
            const auto rendered=last_input_render.load(std::memory_order_acquire);
            const bool closed=stopping()||terminal.load(std::memory_order_acquire)||input_signals.load()->input_force_close.load(std::memory_order_acquire)||
                input_request.load(std::memory_order_acquire)==2||peer.state!=1;
            // HUD freshness is 250 ms, but strict mouse ownership expires at
            // 100 ms. Re-query its exact captured owner/generation here; a
            // render stall must not emit after that shorter lease has expired.
            mouse::Snapshot capture;
            const auto capture_result=closed?mouse::Result::unavailable:mouse_api->query(pending_click.window,pending_click.token,&capture);
            const bool captured=world::capture_matches(pending_click,capture_result==mouse::Result::ok&&(capture.flags&mouse::active)
#ifdef MINECOME_HUD_SELECTIVE_MOUSE
                &&!(capture.flags&mouse::draining)&&capture.mode==mouse::Mode::buttons
#endif
                ,capture.token,capture.generation);
            const bool session_live=accepted.live(utc,now),ack_fresh=ui::fresh(peer.ack.utc,utc),
                observation_fresh=now>=peer.observed&&now-peer.observed<=ui::fresh_ms,
                render_fresh=rendered&&now>=rendered&&now-rendered<=ui::fresh_ms,
                image_fresh=frame&&st::uploaded_fresh(frame->observation,now),overflow=world_clicks->overflowed();
            const bool live=!closed&&session_live&&peer.live&&peer.ack.state==1&&ack_fresh&&
                observation_fresh&&render_fresh&&image_fresh&&!overflow;
            const auto decision=world::delivery_with_capture(pending_click,live,utc,now,peer.ack.sequence,peer.ack.screen,
                captured?world::Capture::matched:capture_result==mouse::Result::busy?world::Capture::busy:world::Capture::unavailable);
            if(decision.outcome==world::Delivery::wait)return;
            if(decision.outcome==world::Delivery::drop){
                // Never silently skip an in-session sequence and emit later
                // clicks. Closed-session records are discarded without IO.
                if(!closed){
                    std::ostringstream details;
                    details<<"[MineComeWorldInputDiagnostic] {\"schema\":1,\"run\":\""<<accepted.identity.run
                        <<"\",\"event\":\"delivery_dropped\",\"reason\":\""<<world::name(decision.reason)
                        <<"\",\"sequence\":"<<pending_click.sequence<<",\"utc_ms\":"<<utc<<",\"click_utc_ms\":"<<pending_click.utc
                        <<",\"lease_deadline_ms\":"<<pending_click.lease_deadline<<",\"steady_ms\":"<<now
                        <<",\"session_live\":"<<session_live<<",\"peer_live\":"<<peer.live<<",\"ack_state\":"<<peer.ack.state
                        <<",\"ack_sequence\":"<<peer.ack.sequence<<",\"required_ack_sequence\":"<<pending_click.ui_sequence
                        <<",\"ack_screen\":"<<peer.ack.screen<<",\"ack_fresh\":"<<ack_fresh
                        <<",\"ack_observation_fresh\":"<<observation_fresh<<",\"render_fresh\":"<<render_fresh
                        <<",\"image_fresh\":"<<image_fresh<<",\"queue_overflow\":"<<overflow
                        <<",\"capture_result\":"<<static_cast<unsigned>(capture_result)<<",\"capture_reason\":"<<capture.reason
                        <<",\"capture_flags\":"<<capture.flags<<",\"capture_generation\":"<<capture.generation
                        <<",\"required_capture_generation\":"<<pending_click.generation
                        <<",\"capture_owner_matches\":"<<(capture.token==pending_click.token)
                        <<",\"capture_lease_remaining_ms\":"<<capture.lease_remaining_ms<<'}';
                    reshade::log::message(reshade::log::level::info,details.str().c_str());
                    record_close(ui::CloseCause::mouse_transition);input_signals.load()->input_force_close.store(true,std::memory_order_release);
                    inputs.finish("world_click_delivery_failed");
                    receipt("world_click","delivery_failed",accepted.identity.run);
                }
                pending_click={};
                continue;
            }
            std::ostringstream line;
            line<<"[MineComeWorldInput] {\"schema\":1,\"run\":\""<<accepted.identity.run<<"\",\"sequence\":"<<pending_click.sequence
                <<",\"utc_ms\":"<<pending_click.utc<<",\"action\":"<<pending_click.action<<'}';
            // Re-check asynchronous closure immediately before publication.
            if(!input_signals.load()->input_force_close.load(std::memory_order_acquire)&&!terminal.load(std::memory_order_acquire)&&!stopping())
                reshade::log::message(reshade::log::level::info,line.str().c_str());
            pending_click={};
        }
    }
#endif
    void end(std::string_view why, std::string_view run) {
        if(input_signals.load()->input_has_started.load(std::memory_order_acquire))record_close(ui::CloseCause::session_end);
        input_signals.load()->input_force_close.store(true,std::memory_order_release);
        terminal.store(true,std::memory_order_release);
        publication.store({},std::memory_order_release);
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
        depth::instance().arm(false,{});
#endif
        receipt("session_end",why,run);
        std::ostringstream counters;
        counters << "[MineComeHudInput] {\"schema\":1,\"event\":\"final_counters\",\"run\":\"" << run
                 << "\",\"uploaded\":" << uploaded.load() << ",\"dropped\":" << dropped.load()
                 << ",\"submitted\":" << submitted.load()
                 << ",\"busy_renewals_deferred\":" << busy_renewals_deferred.load()
                 << ",\"visual_verified\":false}";
        reshade::log::message(reshade::log::level::info,counters.str().c_str());
    }
#ifdef MINECOME_HUD_REPEAT_SESSION
    bool retire_session(const ui::Status &closed,std::string_view reason,std::vector<ui::Event> &pending) {
        const auto owner=rearm_policy.current();
        ui::CloseSnapshot closure;
        if(!input_signals.load()->first_close.read(closure)||!rearm::normal_input_close(closure.cause,reason)||
           closed.state!=2||closed.ack.state!=2||closed.sequence!=closed.ack.sequence||renderer_error.load()||
           input_mailbox->overflowed()||world_clicks->overflowed()) {
            rearm_policy.fail(owner);receipt("rearm","unclean_native_close",owner.arm.identity.run);return false;
        }
        if(rearm_policy.begin_retirement(owner,rearm::Outcome::completed,st::steady_ms())!=rearm::Result::accepted)return false;
        // Render callbacks hide and relinquish capture on their own thread.
        // The worker only observes their receipts under the lifetime lock.
        retiring.store(true,std::memory_order_release);
        const auto prefix=config+L"."+std::wstring(owner.arm.identity.run.begin(),owner.arm.identity.run.end());
        const auto until=st::steady_ms()+60000;
        while(!stopping()&&st::steady_ms()<until) {
            if(!repeat_render_retired()||WaitForSingleObject(producer.value,0)!=WAIT_OBJECT_0) {
                WaitForSingleObject(stop.value,25);continue;
            }
            std::vector<std::uint8_t> bytes;
            rearm::ControllerCleanup cleanup;std::string error,digest;
            if(!st::read_file(prefix+L".cleanup.ini",4096,stop.value,&bytes,nullptr)) {
                WaitForSingleObject(stop.value,25);continue;
            }
            if(!rearm::parse_cleanup(std::string_view(reinterpret_cast<const char *>(bytes.data()),bytes.size()),owner,cleanup,error)||
               !st::read_file(prefix+L".verification.json",1024u*1024u,stop.value,nullptr,&digest)||digest!=cleanup.verification_sha256) {
                receipt("rearm","controller_proof_rejected",owner.arm.identity.run);rearm_policy.fail(owner);return false;
            }
            // With callbacks retired, discard only this closed generation's
            // undelivered records. Fresh queues are allocated before next arm.
            pending.clear();ui::Event ignored;while(input_mailbox->pop(ignored)){}
            world::Click click;while(world_clicks->pop(click)){}pending_click={};
            const auto now=st::steady_ms();rearm::Retirement proof;
            proof.input={owner,now,{true,true,closed.sequence,closed.ack.sequence}};
            proof.queues={owner,now,{true,0,0,false}};
            proof.renderer={owner,now,{true,true,true,true}};
            proof.capture={owner,now,{true,true,false}};
            proof.producer={owner,now,{true}};
            proof.controller={owner,now,cleanup};
            if(rearm_policy.retire(proof,now)!=rearm::Result::accepted)return false;
            const auto text=rearm::format_retired(owner,cleanup,rearm_policy.phase());
            const auto temporary=prefix+L".retired.ini.tmp",destination=prefix+L".retired.ini";
            st::Handle file(CreateFileW(temporary.c_str(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr));
            DWORD written=0;
            if(text.empty()||!file||!WriteFile(file.value,text.data(),static_cast<DWORD>(text.size()),&written,nullptr)||
               written!=text.size()||!FlushFileBuffers(file.value))return false;
            file.reset();
            if(!MoveFileExW(temporary.c_str(),destination.c_str(),MOVEFILE_WRITE_THROUGH))return false;
            receipt("rearm",rearm_policy.phase()==rearm::Phase::idle?"idle":"exhausted",owner.arm.identity.run);
            return rearm_policy.phase()==rearm::Phase::idle;
        }
        rearm_policy.fail(owner);receipt("rearm","cleanup_timeout",owner.arm.identity.run);return false;
    }
#endif
    void run() noexcept {
        try {
            std::string digest;
            if (!st::read_file(st::module_path(),512u*1024u*1024u,stop.value,nullptr,&digest) || digest != exe_sha) {
                receipt("compatibility","exe_rejected"); return;
            }
            const auto pid=GetCurrentProcessId(); const auto start=st::process_start();
            if (!start || config.empty()) { receipt("compatibility","process_identity_failed"); return; }
            compatible.store(true,std::memory_order_release); receipt("compatibility","exact_tools_exe");
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
            // Generic Depth metadata is source-specific. Read it only with this
            // exact deployed v6.8.0.7 selective-r5 binary, not a version guess.
            const bool proxy_read=renderer_module && st::read_file(st::module_path(renderer_module),16u*1024u*1024u,stop.value,nullptr,&digest);
            const bool depth_compatible=proxy_read && digest=="f0552e7cc1ea8f1490e2953d562639843e13c478502ab40eb2c315beb1ecfeab";
            // The older same-ABI proxy revoked ownership after a BUSY request.
            // Enable bounded renewal deferral only for the rebuilt exact proxy;
            // this identity is independent of optional DXIL reflection support.
            busy_request_preserves_lease.store(proxy_read && digest=="f0552e7cc1ea8f1490e2953d562639843e13c478502ab40eb2c315beb1ecfeab",std::memory_order_release);
            if(depth_compatible){
                const auto existing=GetModuleHandleW(L"dxcompiler.dll");
                const auto compiler_path=existing?std::filesystem::path(st::module_path(existing)):
                    std::filesystem::path(st::module_path()).parent_path().parent_path()/L"Win64Shared"/L"dxcompiler.dll";
                if(st::read_file(compiler_path.wstring(),64u*1024u*1024u,stop.value,nullptr,&digest) &&
                    digest=="570a1a7357893615417edf5ab356625b5b6b721a131bc7331bf17289d4928ed7"){
                    shader_compiler_module=LoadLibraryExW(compiler_path.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
                    if(shader_compiler_module)depth::instance().set_dxc_factory(reinterpret_cast<DxcCreateInstanceProc>(GetProcAddress(shader_compiler_module,"DxcCreateInstance")));
                }
                receipt("host_depth",shader_compiler_module?"exact_dxil_compiler":"dxil_compiler_unavailable");
            }
            depth::instance().set_compatible(depth_compatible);
            receipt("host_depth",depth_compatible?"exact_proxy":"proxy_unavailable");
#endif
#ifdef MINECOME_HUD_REPEAT_SESSION
            for(unsigned attempt=0;attempt<rearm::maximum_sessions&&!stopping();++attempt) {
            bool repeat_ready=false;
            std::string arm_digest;
#endif
            st::Identity identity;
            std::string last_error;
            while (!stopping()) {
                std::vector<std::uint8_t> bytes;
                if (st::read_file(config,st::max_arm_bytes,stop.value,&bytes,
#ifdef MINECOME_HUD_REPEAT_SESSION
                                  &arm_digest
#else
                                  nullptr
#endif
                                  )) {
                    std::string error;
                    if (st::parse_arm(std::string_view(reinterpret_cast<const char *>(bytes.data()),bytes.size()),
                                      pid,start,st::utc_ms(),identity,error,stream_schema)) {
#ifdef MINECOME_HUD_REPEAT_SESSION
                        // Leave the retired arm untouched until the explicit
                        // controller archives it; never auto-replay that arm.
                        if(attempt&&identity.run==rearm_policy.current().arm.identity.run) {
                            WaitForSingleObject(stop.value,100);continue;
                        }
#endif
                        break;
                    }
                    if (error != last_error) { receipt("arm",error); last_error=error; }
                }
                WaitForSingleObject(stop.value,100);
            }
            if (stopping()) return;
            // One accepted immutable arm per process. No runtime reload, bad
            // producer or replacement config can reopen or renew this session.
            auto accepted=std::make_shared<Session>(); accepted->identity=identity;
            const auto utc=st::utc_ms(); accepted->begun=st::steady_ms();
            if (identity.expires_utc_ms <= utc || identity.expires_utc_ms-utc > st::maximum_lease(identity)) {
                end("arm_expired",identity.run); return;
            }
            accepted->deadline=accepted->begun+(identity.expires_utc_ms-utc);
            st::Channel channel;
            if (!channel.open(identity)) { end(channel.reason(),identity.run); return; }
#ifdef MINECOME_HUD_REPEAT_SESSION
            producer.reset(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|SYNCHRONIZE,FALSE,identity.producer_pid));
            if(!producer||st::process_start(producer.value)!=identity.producer_start){end("producer_identity",identity.run);return;}
            std::shared_ptr<const st::Frame> initial;
            while(!stopping()&&!initial) {
                const auto result=channel.poll(initial);
                if(result==st::Poll::closed||result==st::Poll::failed){end("initial_frame_failed",identity.run);return;}
                if(!initial)WaitForSingleObject(stop.value,5);
            }
            if(stopping())return;
            rearm::Arm arm{{identity.run,arm_digest,identity.target_pid,identity.producer_pid,identity.target_start,identity.producer_start},
                {initial->header.width,initial->header.height,initial->header.pitch},identity.expires_utc_ms};
            if(rearm_policy.admit(arm,true,st::utc_ms(),st::steady_ms())!=rearm::Result::accepted||!prepare_repeat_generation()) {
                end("rearm_admission_failed",identity.run);return;
            }
            publication.store(initial,std::memory_order_release);
#endif
            session.store(accepted,std::memory_order_release); has_armed.store(true,std::memory_order_release);
            receipt("arm","accepted",identity.run);
            ui::Writer inputs;
            bool input_created=inputs.create(identity
#ifdef MINECOME_HUD_GAMEPLAY_BLOCKS
                #ifdef MINECOME_HUD_GAMEPLAY_CHAT
                ,ui::Profile::gameplay_chat
                #else
                ,ui::Profile::gameplay_blocks
                #endif
#elif defined(MINECOME_HUD_GAMEPLAY_MOVEMENT)
                ,ui::Profile::gameplay_movement
#elif defined(MINECOME_HUD_GAMEPLAY)
                ,ui::Profile::gameplay
#elif defined(MINECOME_HUD_PHYSICAL_MOVEMENT)
                ,ui::Profile::movement
#endif
                ),input_closed_logged=false,first_close_logged=false;
            if(!input_created) receipt("input",inputs.reason(),identity.run);
            input_status.store(std::make_shared<ui::Status>(inputs.status()),std::memory_order_release);
            std::vector<ui::Event> pending_input;pending_input.reserve(ui::ring_count);
            auto reported=st::steady_ms(); bool first=false; unsigned last_renderer_error=0;
            while (!stopping()) {
                if(input_created) {
#ifdef MINECOME_HUD_LIVE_MOUSE
                    drain_mouse_receipts(identity.run);
#endif
                    const auto now=st::steady_ms();
                    const auto last_render=last_input_render.load(std::memory_order_acquire);
                    if(input_signals.load()->input_force_close.load(std::memory_order_acquire)||input_request.load(std::memory_order_acquire)==2||input_mailbox->overflowed()
#ifdef MINECOME_HUD_WORLD_CLICKS
                        ||world_clicks->overflowed()
#endif
                        ) {
                        if(input_mailbox->overflowed())record_close(ui::CloseCause::mailbox_overflow);
                        inputs.finish("ownership_closed");
                    } else if(inputs.status().state==1&&(!last_render||now<last_render||now-last_render>ui::fresh_ms)) {
                        record_close(ui::CloseCause::render_stale);
                        inputs.finish("render_stale");
                    } else {
                        inputs.poll();
                        if(inputs.status().state==0&&input_request.load(std::memory_order_acquire)==1) {
                            if(!inputs.arm())inputs.finish("arm_not_ready");
                            else {receipt("input","keyboard_armed",identity.run);input_receipt("input_armed",inputs,identity.run);}
                        }
                        if(inputs.status().state==1) {
                            ui::Event event;
                            while(pending_input.size()<ui::ring_count&&input_mailbox->pop(event))pending_input.push_back(event);
                            if(!pending_input.empty()&&inputs.append(pending_input))pending_input.clear();
                        }
                    }
                    // A contended mutex may defer the terminal header. Retry
                    // that bounded write and observe the guest's close ACK.
                    if(inputs.status().state==2)inputs.poll();
                    input_status.store(std::make_shared<ui::Status>(inputs.status()),std::memory_order_release);
                    if(inputs.status().state==2&&!input_closed_logged) {
                        record_close(ui::CloseCause::worker_terminal);
                        receipt("input",inputs.reason(),identity.run);input_receipt("input_closed",inputs,identity.run);input_closed_logged=true;
                    }
                    if(inputs.status().state==2&&!first_close_logged)first_close_logged=close_receipt(identity.run);
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
                        record_close(ui::CloseCause::worker_terminal);
                        const auto close_started=st::steady_ms();
                        while(!stopping()&&(inputs.status().ack.state!=2||!first_close_logged)&&st::steady_ms()-close_started<1500) {
#ifdef MINECOME_HUD_LIVE_MOUSE
                            drain_mouse_receipts(identity.run);
#endif
                            inputs.poll();
                            input_status.store(std::make_shared<ui::Status>(inputs.status()),std::memory_order_release);
                            if(!first_close_logged)first_close_logged=close_receipt(identity.run);
                            WaitForSingleObject(stop.value,5);
                        }
                        input_receipt("input_final",inputs,identity.run,st::steady_ms()-close_started);
                        if(!first_close_logged)first_close_logged=close_receipt(identity.run);
                    }
#ifdef MINECOME_HUD_REPEAT_SESSION
                    if(result==st::Poll::closed&&input_created&&retire_session(inputs.status(),inputs.reason(),pending_input)) {
                        repeat_ready=true;break;
                    }
#endif
                    return;
                }
                if (next) {
                    publication.store(std::move(next),std::memory_order_release);
                    if (!first) { receipt("frame","first_received",identity.run); first=true; }
                }
#ifdef MINECOME_HUD_WORLD_CLICKS
                if(input_created)drain_world_clicks(*accepted,inputs);
#endif
                const auto renderer=renderer_error.load(std::memory_order_relaxed);
                if (renderer && renderer != last_renderer_error) {
                    receipt("renderer","failure_"+std::to_string(renderer),identity.run); last_renderer_error=renderer;
                }
                const auto now=st::steady_ms();
                if (now-reported >= 5000) {
                    std::ostringstream line;
                    line << "[MineComeHudInput] {\"schema\":1,\"event\":\"counters\",\"run\":\"" << identity.run
                         << "\",\"uploaded\":" << uploaded.load() << ",\"dropped\":" << dropped.load()
                         << ",\"submitted\":" << submitted.load()
                         << ",\"busy_renewals_deferred\":" << busy_renewals_deferred.load();
                    if(input_created&&inputs.status().state==0) {
                        const auto observed=prearm_observed.load(std::memory_order_relaxed);
                        line << ",\"prearm_samples\":" << prearm_samples.load(std::memory_order_relaxed)
                             << ",\"prearm_observation_age_ms\":" << (observed&&now>=observed?now-observed:~std::uint64_t{0})
                             << ",\"prearm_failures\":" << prearm_failures.load(std::memory_order_relaxed)
                             << ",\"prearm_keys\":" << prearm_keys.load(std::memory_order_relaxed)
                             << ",\"prearm_f8\":" << prearm_f8.load(std::memory_order_relaxed)
                             << ",\"prearm_composition_stage\":" << prearm_stage.load(std::memory_order_relaxed);
#ifdef MINECOME_HUD_LIVE_MOUSE
                        line << ",\"prearm_mouse_result\":" << prearm_mouse_result.load(std::memory_order_relaxed)
                             << ",\"prearm_mouse_flags\":" << prearm_mouse_flags.load(std::memory_order_relaxed)
                             << ",\"prearm_mouse_reason\":" << prearm_mouse_reason.load(std::memory_order_relaxed)
                             << ",\"prearm_mouse_buttons\":" << prearm_mouse_buttons.load(std::memory_order_relaxed)
                             << ",\"prearm_mouse_devices\":" << prearm_mouse_devices.load(std::memory_order_relaxed)
                             << ",\"prearm_mouse_eligible_devices\":" << prearm_mouse_eligible.load(std::memory_order_relaxed);
#endif
                    }
                    line << ",\"visual_verified\":false}";
                    reshade::log::message(reshade::log::level::info,line.str().c_str()); reported=now;
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
                    const auto depth_stats=depth::instance().counters();
                    std::unique_lock depth_count_lock(depth_counters_mutex);
                    std::ostringstream depth_line;
                    depth_line << "[MineComeHudInput] {\"event\":\"host_depth\",\"run\":\"" << identity.run
                        << "\",\"reflected\":" << depth_stats.shaders_reflected << ",\"reflection_rejected\":" << depth_stats.reflection_rejected
                        << ",\"mapped\":" << depth_stats.map_attempts << ",\"map_failed\":" << depth_stats.map_failed
                        << ",\"non_upload\":" << depth_stats.non_upload_rejected << ",\"view_rejected\":" << depth_stats.view_rejected
                        << ",\"accepted\":" << depth_stats.accepted << ",\"submitted\":" << depth_stats.submitted
                        << ",\"composited\":" << depth_frames.load() << ",\"considered\":" << depth_considered.load()
                        << ",\"no_sample\":" << depth_no_sample.load() << ",\"bad_view\":" << depth_bad_view.load()
                        << ",\"bad_source\":" << depth_bad_source.load() << ",\"ready_changes\":" << depth_ready_changes.load()
                        << ",\"sample_age\":" << depth_sample_age.load() << ",\"camera_age\":" << depth_camera_age.load()
                        << ",\"position\":" << depth_position.load() << ",\"basis\":" << depth_basis.load()
                        << ",\"projection\":" << depth_projection.load() << ",\"other_view\":" << depth_other.load()
                        << ",\"reprojected\":" << depth_reprojected.load() << ",\"warp_rejected\":" << depth_warp_rejected.load()
                        << ",\"strict_fallback\":" << depth_strict_fallback.load()
                        << ",\"presentation_seals\":" << depth_stats.presentation_seals << ",\"presentation_accepted\":" << depth_stats.presentation_accepted
                        << ",\"presentation_identity\":" << depth_stats.presentation_identity << ",\"presentation_missing\":" << depth_stats.presentation_missing
                        << ",\"presentation_ambiguous\":" << depth_stats.presentation_ambiguous << ",\"presentation_unknown\":" << depth_stats.presentation_unknown
                        << ",\"presentation_overflow\":" << depth_stats.presentation_overflow << ",\"presentation_age\":" << depth_stats.presentation_age
                        << ",\"native_reads\":" << depth_stats.native_reads << ",\"native_nonwriters\":" << depth_stats.native_nonwriters
                        << ",\"native_unknown_draws\":" << depth_stats.native_unknown_draws << ",\"native_budget_rejected\":" << depth_stats.native_budget_rejected
                        << ",\"recording_contention\":" << depth_stats.recording_contention << ",\"recording_waits\":" << depth_stats.recording_waits
                        << ",\"native_incomplete_epochs\":" << depth_stats.native_incomplete_epochs << ",\"native_unknown_access\":" << depth_stats.native_unknown_access
                        << ",\"native_viewport_rejected\":" << depth_stats.native_viewport_rejected << ",\"native_pipeline_missing\":" << depth_stats.native_pipeline_missing
                        << ",\"native_layout_missing\":" << depth_stats.native_layout_missing << ",\"native_binding_missing\":" << depth_stats.native_binding_missing
                        << ",\"native_binding_ambiguous\":" << depth_stats.native_binding_ambiguous
                        << ",\"native_resource_rejected\":" << depth_stats.native_resource_rejected << ",\"native_map_failed\":" << depth_stats.native_map_failed
                        << ",\"native_incoherent\":" << depth_stats.native_incoherent << ",\"native_invalid_view\":" << depth_stats.native_invalid_view
                        << ",\"native_submission_changed\":" << depth_stats.native_submission_changed
                        << ",\"native_copy_draws\":" << depth_stats.native_copy_draws << ",\"native_copy_accepted\":" << depth_stats.native_copy_accepted
                        << ",\"native_copy_source_missing\":" << depth_stats.native_copy_source_missing << ",\"native_copy_rejected\":" << depth_stats.native_copy_rejected
                        << ",\"native_descriptor_updates\":" << depth_stats.native_descriptor_updates
                        << ",\"native_descriptor_copies\":" << depth_stats.native_descriptor_copies << "}";
                    const auto warp_rejection=warp_rejection_reported?std::optional<WarpRejection>{}:first_warp_rejection;
                    if(warp_rejection)warp_rejection_reported=true;
                    depth_count_lock.unlock();
                    reshade::log::message(reshade::log::level::info,depth_line.str().c_str());
                    const auto profile=depth::instance().profile_counters();
                    if(profile.enabled){
                        std::ostringstream timing;
                        timing << "[MineComeHudInput] {\"event\":\"native_depth_profile\",\"run\":\"" << identity.run
                            << "\",\"sample_interval\":" << profile.sample_interval << ",\"categories\":{";
                        for(std::size_t i=0;i<profile.categories.size();++i){
                            if(i)timing << ',';
                            const auto &p=profile.categories[i];
                            timing << '"' << depth::profile_category_names[i] << "\":{\"calls\":" << p.calls
                                << ",\"samples\":" << p.samples << ",\"wait_ns\":" << p.wait_ns
                                << ",\"hold_ns\":" << p.hold_ns << ",\"max_wait_ns\":" << p.max_wait_ns
                                << ",\"max_hold_ns\":" << p.max_hold_ns << '}';
                        }
                        timing << "},\"descriptor_copy_counts\":[";
                        for(std::size_t i=0;i<profile.descriptor_copy_counts.size();++i){if(i)timing << ',';timing << profile.descriptor_copy_counts[i];}
                        timing << "]}";
                        reshade::log::message(reshade::log::level::info,timing.str().c_str());
                    }
                    if(warp_rejection){
                        const auto &r=*warp_rejection;
                        std::ostringstream detail;
                        detail<<"[MineComeHudInput] {\"event\":\"world_warp_rejected\",\"run\":\""<<identity.run
                            <<"\",\"width\":"<<r.width<<",\"height\":"<<r.height<<",\"now\":"<<r.now
                            <<",\"image_utc\":"<<r.image_utc<<",\"camera_utc\":"<<r.guest.captured_unix_ms
                            <<",\"native_utc\":"<<r.native.captured_unix_ms;
                        const auto array=[&](const char *name,const auto &values){detail<<",\""<<name<<"\":[";bool first=true;
                            for(const auto value:values){if(!first)detail<<',';first=false;if(std::isfinite(value))detail<<value;else detail<<"null";}detail<<']';};
                        array("source_position",r.guest.position);array("source_forward",r.guest.forward);array("source_up",r.guest.up);
                        array("target_position",r.native.position);array("target_right",r.native.right);array("target_front",r.native.front);array("target_up",r.native.up);
                        array("ratio",r.native.ratio);array("far_and_fov",std::array<float,2>{r.native.far_metres,r.guest.vertical_fov});
                        for(unsigned row=0;row<4;++row){depth::vec4 values{};for(unsigned col=0;col<4;++col)values[col]=r.native.projection_element(row,col);
                            array(("projection_row"+std::to_string(row)).c_str(),values);}
                        detail<<'}';reshade::log::message(reshade::log::level::info,detail.str().c_str());
                    }
                    save_rejected_depth_writer(identity.run);
                    if(const auto copy=depth::instance().take_copy_diagnostic()){
                        std::ostringstream detail;
                        detail<<"[MineComeHudInput] {\"event\":\"native_depth_copy\",\"run\":\""<<identity.run
                            <<"\",\"stage\":"<<copy->stage<<",\"proof_status\":"<<copy->proof_status
                            <<",\"source\":"<<copy->source<<",\"destination\":"<<copy->destination
                            <<",\"source_width\":"<<copy->source_width<<",\"source_height\":"<<copy->source_height
                            <<",\"destination_width\":"<<copy->destination_width<<",\"destination_height\":"<<copy->destination_height
                            <<",\"source_format\":"<<copy->source_format<<",\"view_format\":"<<copy->view_format
                            <<",\"source_samples\":"<<copy->source_samples<<",\"source_levels\":"<<copy->source_levels<<'}';
                        reshade::log::message(reshade::log::level::info,detail.str().c_str());
                    }
#endif
                }
                WaitForSingleObject(stop.value,5);
            }
#ifdef MINECOME_HUD_REPEAT_SESSION
            if(repeat_ready)continue;
#endif
            end("stopped",identity.run);
#ifdef MINECOME_HUD_REPEAT_SESSION
            return;
            }
#endif
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
#ifdef MINECOME_HUD_REPEAT_SESSION
    bool repeat_retired=false;
#endif
    HWND window=nullptr;
    api::resource texture{};
    api::resource_view view{};
    api::fence fence{};
    std::array<Upload,3> uploads{};
    api::effect_uniform_variable active{},frame{},rect{};
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
    api::effect_uniform_variable layers{},depth_ready{},depth_projection{},depth_nearest{},guest_projection{};
    api::effect_texture_variable host_depth{};
    api::effect_uniform_variable warp_ready{};
    std::array<api::effect_uniform_variable,12> warp_uniforms{};
    api::effect_technique warp_technique{};
    st::Header uploaded_header{};
    bool depth_armed=false;
    bool previous_depth_ready=false;
    std::uint64_t depth_sequence=0;
    std::optional<depth::sample> depth_sample;
#endif
    api::effect_technique technique{};
    bool bound=false, failed=false;
    bool reshade_overlay=false;
#ifdef MINECOME_HUD_GAMEPLAY
    ui::KeyboardGate keyboard{true};
    bool gameplay_keyboard_leased=false;
#else
    ui::KeyboardGate keyboard;
#endif
    std::uint32_t previous_keys=0;
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
    ui::ChatKeyboard chat_keyboard;
    ui::ReleasedTapGate chat_taps;
    std::uint32_t chat_world_held=0;
    bool chat_caps=false,chat_caps_initialized=false,chat_caps_down=false;
#endif
#ifdef MINECOME_HUD_PHYSICAL_MOVEMENT
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
    ui::MovementGate movement{127u};
#else
    ui::MovementGate movement;
#endif
#endif
    std::uint32_t width=0,height=0,pitch=0,texture_height=0,format=1;
    std::uint64_t next_fence=0,uploaded_sequence=0,uploaded_observation=0;
#ifdef MINECOME_HUD_LIVE_MOUSE
    api::effect_uniform_variable cursor_visible{},cursor{};
    ui::PointerForwarder pointer;
#ifdef MINECOME_HUD_GAMEPLAY_BLOCKS
    ui::GameplayWorldButtons world_buttons;
#endif
    hud::Rect rectangle;
    std::uint32_t target_width=0,target_height=0,uploaded_screen=0;
    std::uint64_t forwarded_events=0,transition_sequence=0,mouse_generation=0;
    std::uint32_t transition_screen=0;
    bool transition=false,mouse_leased=false,mouse_capability_reported=false;
#ifdef MINECOME_HUD_SELECTIVE_MOUSE
    mouse::ForwardingLease selective_lease;
    mouse::ModeGate selective_mode;
    mouse::ObservationRecovery observation_recovery;
#endif
#ifdef MINECOME_HUD_WORLD_CLICKS
    world::Gate world_click;
#endif
#endif
};
std::mutex runtimes_mutex;
std::unordered_map<api::effect_runtime *,RuntimeState> runtimes;
bool owned_window(HWND window) {
    DWORD pid=0;
    return window && IsWindow(window) && GetWindowThreadProcessId(window,&pid) && pid == GetCurrentProcessId();
}
bool visible(api::effect_runtime *runtime, const RuntimeState &state,ui::WindowSnapshot *details=nullptr,HWND *observed_foreground=nullptr) {
    ui::WindowSnapshot discarded;
    auto &snapshot=details?*details:discarded;
    // Same predicates and short-circuit order as the previous visibility gate.
    // PID lookup for a different foreground window is diagnostic-only, and is
    // performed below only when the gate closes. No app titles are collected.
    if(!snapshot.record(ui::WindowCheck::runtime_handle,reinterpret_cast<HWND>(runtime->get_hwnd())==state.window))return false;
    if(!snapshot.record(ui::WindowCheck::valid_handle,state.window&&IsWindow(state.window)))return false;
    DWORD pid=0;
    if(!snapshot.record(ui::WindowCheck::owned_process,GetWindowThreadProcessId(state.window,&pid)&&pid==GetCurrentProcessId()))return false;
    if(!snapshot.record(ui::WindowCheck::not_minimized,!IsIconic(state.window)))return false;
    if(!snapshot.record(ui::WindowCheck::visible,IsWindowVisible(state.window)!=FALSE))return false;
    const HWND foreground=GetForegroundWindow();
    if(observed_foreground)*observed_foreground=foreground;
    return snapshot.record(ui::WindowCheck::foreground,foreground==state.window);
}
#ifdef MINECOME_HUD_LIVE_MOUSE
void release_mouse(api::effect_runtime *runtime,RuntimeState &state) {
    if(!state.mouse_leased||!mouse_api)return;
    mouse::Snapshot snapshot;
    auto result=mouse_api->release(reinterpret_cast<std::uintptr_t>(state.window),reinterpret_cast<std::uintptr_t>(runtime),&snapshot);
    state.mouse_leased=false;mouse_receipt("mouse_release",result,snapshot);
#ifdef MINECOME_HUD_SELECTIVE_MOUSE
    state.selective_lease.released();
#endif
}
bool queue_input(RuntimeState &state,const ui::Event &event) {
    if(!service->input_mailbox->push(event))return false;
    ++state.forwarded_events;return true;
}
bool queue_pointer(RuntimeState &state,const ui::PointerBatch &batch) {
    for(std::size_t i=0;i<batch.count;++i)if(!queue_input(state,batch.events[i]))return false;
    return true;
}
#ifdef MINECOME_HUD_PHYSICAL_MOVEMENT
bool queue_movement(RuntimeState &state,const ui::MovementEdges &edges,std::uint64_t utc) {
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
    constexpr auto &movement_keys=ui::flight_movement_keys;
#else
    constexpr auto &movement_keys=ui::movement_keys;
#endif
    // Releases precede any new presses, including before E/Esc reaches Java.
    for(std::size_t i=0;i<movement_keys.size();++i)if(edges.up&(1u<<i))
        if(!queue_input(state,{utc,ui::Kind::key_up,movement_keys[i],0,0,0}))return false;
    for(std::size_t i=0;i<movement_keys.size();++i)if(edges.down&(1u<<i))
        if(!queue_input(state,{utc,ui::Kind::key_down,movement_keys[i],0,0,0}))return false;
    for(std::size_t i=0;i<movement_keys.size();++i)if(edges.pulse&(1u<<i)){
        if(!queue_input(state,{utc,ui::Kind::key_down,movement_keys[i],0,0,0})||
           !queue_input(state,{utc,ui::Kind::key_up,movement_keys[i],0,0,0}))return false;
    }
    return true;
}
#endif
#endif
void close_keyboard(api::effect_runtime *runtime,ui::CloseCause cause,const ui::CloseSnapshot *snapshot=nullptr) noexcept {
#ifdef MINECOME_HUD_GAMEPLAY
    if(gameplay_keyboard_api)gameplay_keyboard_api->release(reinterpret_cast<std::uintptr_t>(runtime->get_hwnd()),reinterpret_cast<std::uintptr_t>(runtime));
#endif
    if(service&&service->input_owner.load(std::memory_order_acquire)==runtime) {
        if(snapshot)input_signals.load()->first_close.publish(*snapshot);else record_close(cause);
        service->input_request.store(2,std::memory_order_release);
        input_signals.load()->input_force_close.store(true,std::memory_order_release);
    }
}
void capture_keyboard(api::effect_runtime *runtime,RuntimeState &state,bool composed,std::uint32_t composition_stage) {
    if(!service)return;
    const auto peer=service->input_status.load(std::memory_order_acquire);
    if(!peer)return;
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
    constexpr auto ui_key_count=ui::gameplay_ui_key_count;
    constexpr auto keys=ui::gameplay_capture_keys;
#else
    constexpr std::size_t ui_key_count=11;
#ifdef MINECOME_HUD_PHYSICAL_MOVEMENT
    constexpr std::array<std::uint32_t,16> keys{0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x45,0x1b,0x57,0x41,0x53,0x44,0x20};
#else
    constexpr std::array<std::uint32_t,11> keys{0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x45,0x1b};
#endif
#endif
    std::uint32_t held=0;
    for(std::size_t i=0;i<keys.size();++i)if(runtime->is_key_down(keys[i]))held|=1u<<i;
    const auto now=st::steady_ms();
    const auto utc=st::utc_ms();const bool f8=runtime->is_key_down(VK_F8);
#ifdef MINECOME_HUD_LIVE_MOUSE
    unsigned mouse_buttons=0;
    for(unsigned i=0;i<2;++i)if(runtime->is_mouse_button_down(i))mouse_buttons|=1u<<i;
    mouse::Snapshot mouse_status;
    const auto mouse_query=mouse_api->query(reinterpret_cast<std::uintptr_t>(state.window),0,&mouse_status);
    const bool mouse_capable=mouse_query==mouse::Result::ok&&(mouse_status.flags&mouse::eligible)!=0;
    if(!state.mouse_capability_reported&&f8){mouse_receipt("mouse_capability",mouse_query,mouse_status);state.mouse_capability_reported=true;}
#endif
    ui::WindowSnapshot window;HWND observed_foreground=nullptr;
    const bool window_eligible=visible(runtime,state,&window,&observed_foreground);
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
    ui::ChatKeyState chat_keys{},chat_released{};
    if(window_eligible){
        for(unsigned key=0;key<chat_keys.size();++key){
            chat_keys[key]=runtime->is_key_down(key)?0x80:0;
            chat_released[key]=runtime->is_key_released(key)?1:0;
        }
        chat_keys[VK_SHIFT]|=chat_keys[VK_LSHIFT]|chat_keys[VK_RSHIFT];
        chat_keys[VK_CONTROL]|=chat_keys[VK_LCONTROL]|chat_keys[VK_RCONTROL];
        // Public ReShade input_windows.cpp stores the reported virtual key;
        // accept generic and side-specific modifier reports as one world key.
        if(chat_keys[VK_SHIFT])held|=1u<<(ui_key_count+5);
        if(chat_keys[VK_CONTROL])held|=1u<<(ui_key_count+6);
        // GetKeyState is suppressed by the existing v5 full keyboard lease.
        // Bootstrap Caps Lock only before acquiring it, then track physical
        // ReShade edges instead of asking a deliberately filtered game API.
        if(!state.chat_caps_initialized&&!state.gameplay_keyboard_leased){
            state.chat_caps=(GetKeyState(VK_CAPITAL)&1)!=0;state.chat_caps_initialized=true;
            state.chat_caps_down=chat_keys[VK_CAPITAL]!=0;
        } else if(chat_keys[VK_CAPITAL]&&!state.chat_caps_down)state.chat_caps=!state.chat_caps;
        state.chat_caps_down=chat_keys[VK_CAPITAL]!=0;
    }
#endif
    // Diagnostic bits mirror the existing eligibility predicates, with no
    // added grace or refresh: composed/overlay/focus/peer/ACK/observation/end.
    std::uint32_t failures=(!composed?1u:0u)|(state.reshade_overlay?2u:0u)|(!window_eligible?4u:0u)|
        ((!peer->live||peer->state>=2)?8u:0u)|(peer->ack.state!=1?16u:0u)|(!ui::fresh(peer->ack.utc,utc)?32u:0u)|
        ((now<peer->observed||now-peer->observed>ui::fresh_ms)?64u:0u)|
        (input_signals.load()->input_force_close.load(std::memory_order_acquire)?128u:0u)|(service->terminal.load(std::memory_order_acquire)?256u:0u);
#ifdef MINECOME_HUD_GAMEPLAY
    if(!gameplay_keyboard_api->query(reinterpret_cast<std::uintptr_t>(state.window),state.gameplay_keyboard_leased?reinterpret_cast<std::uintptr_t>(runtime):0))failures|=2048u;
#endif
#ifdef MINECOME_HUD_LIVE_MOUSE
    if(!state.keyboard.consumed()&&(!mouse_capable||mouse_buttons))failures|=512u;
#ifdef MINECOME_HUD_SELECTIVE_MOUSE
    const bool defer_mouse_query=state.mouse_leased&&state.selective_lease.defer_busy(mouse_query,now);
    if(state.mouse_leased&&!defer_mouse_query&&!state.selective_lease.observe(mouse_query,mouse_status,reinterpret_cast<std::uintptr_t>(runtime),now))failures|=1024u;
#else
    if(state.mouse_leased&&(!mouse_capable||!(mouse_status.flags&mouse::active)||mouse_status.generation!=state.mouse_generation))failures|=1024u;
#endif
#endif
    auto gate_controls=held;
#ifdef MINECOME_HUD_GAMEPLAY
    // No movement, modifier or jump control may be held during takeover.
    for(const auto key:std::array<std::uint32_t,7>{'W','A','S','D',VK_SPACE,VK_SHIFT,VK_CONTROL})
        if(runtime->is_key_down(key))gate_controls|=1u<<31;
#endif
    if(!state.keyboard.consumed()) {
        service->prearm_failures.store(failures,std::memory_order_relaxed);
        service->prearm_keys.store(gate_controls,std::memory_order_relaxed);
        service->prearm_f8.store(f8?1u:0u,std::memory_order_relaxed);
        service->prearm_stage.store(composition_stage,std::memory_order_relaxed);
#ifdef MINECOME_HUD_LIVE_MOUSE
        service->prearm_mouse_result.store(static_cast<std::uint32_t>(mouse_query),std::memory_order_relaxed);
        service->prearm_mouse_flags.store(mouse_status.flags,std::memory_order_relaxed);
        service->prearm_mouse_reason.store(mouse_status.reason,std::memory_order_relaxed);
        service->prearm_mouse_buttons.store(mouse_buttons,std::memory_order_relaxed);
        service->prearm_mouse_devices.store(mouse_status.device_count,std::memory_order_relaxed);
        service->prearm_mouse_eligible.store(mouse_status.eligible_devices,std::memory_order_relaxed);
#endif
        service->prearm_observed.store(now,std::memory_order_relaxed);
        service->prearm_samples.fetch_add(1,std::memory_order_relaxed);
    }
    const auto step=state.keyboard.update(failures==0,f8,gate_controls,now);
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
    const auto chat_pulses=state.chat_taps.update(step==ui::KeyboardGate::Step::active&&failures==0&&
        !state.transition&&!state.observation_recovery.pending()&&!defer_mouse_query&&
        state.selective_lease.owned()&&!state.selective_lease.pending(),chat_keys,chat_released);
    std::uint32_t ui_pulses=0;
    for(std::size_t i=0;i<ui_key_count;++i)if(chat_pulses[keys[i]])ui_pulses|=1u<<i;
#endif
    if(step==ui::KeyboardGate::Step::closed) {
#ifdef MINECOME_HUD_LIVE_MOUSE
        release_mouse(runtime,state);
#endif
        auto cause=ui::CloseCause::eligibility_lost;
        switch(state.keyboard.close_reason()) {
        case ui::KeyboardGate::Close::second_f8:cause=ui::CloseCause::second_f8;break;
        case ui::KeyboardGate::Close::clock_regressed:cause=ui::CloseCause::clock_regressed;break;
        case ui::KeyboardGate::Close::expired:cause=ui::CloseCause::activation_expired;break;
        case ui::KeyboardGate::Close::key_during_settle:cause=ui::CloseCause::key_during_settle;break;
        default:break;
        }
        auto age=[&](std::uint64_t observed){return observed&&now>=observed?now-observed:~std::uint64_t{0};};
        const auto pub=service->publication.load(std::memory_order_acquire);
        ui::CloseSnapshot snapshot{cause,failures,composition_stage,held,f8,utc,peer->ack.utc,
            age(peer->observed),pub?age(pub->observation):~std::uint64_t{0},age(state.uploaded_observation),true};
        snapshot.window=window;
        // Resolve only the HWND from this gate's actual foreground query. A
        // disappeared window leaves the PID unknown; no replacement is queried.
        DWORD foreground_pid=0;
        if(observed_foreground&&GetWindowThreadProcessId(observed_foreground,&foreground_pid)) {
            snapshot.window.foreground_pid=foreground_pid;snapshot.window.foreground_pid_sampled=true;
        }
        snapshot.activation_age_valid=state.keyboard.activation_age(now,snapshot.activation_age_ms);
        close_keyboard(runtime,cause,&snapshot);return;
    }
    if(step==ui::KeyboardGate::Step::idle)return;
    api::effect_runtime *empty=nullptr;
    if(service->input_owner.load(std::memory_order_acquire)!=runtime&&
        !service->input_owner.compare_exchange_strong(empty,runtime,std::memory_order_acq_rel))return;
    input_signals.load()->input_has_started.store(true,std::memory_order_release);
    service->last_input_render.store(now,std::memory_order_release);
    unsigned request=0;
    service->input_request.compare_exchange_strong(request,1,std::memory_order_acq_rel);
    // Public ReShade request affects the following frame. The gate waits two
    // fully neutral frames before forwarding UI edges. F8 itself may reach KCD.
#ifndef MINECOME_HUD_GAMEPLAY
    runtime->block_input_next_frame();
#endif
#ifdef MINECOME_HUD_SELECTIVE_MOUSE
    if(defer_mouse_query){
        // Preserve only the already-owned bounded lease. No capture renewal or
        // keyboard/pointer/world edge is authorized by a busy observation.
        // A button held across this uncertainty must release before rearming.
#ifdef MINECOME_HUD_WORLD_CLICKS
        state.world_click.suspend();
#endif
#ifdef MINECOME_HUD_GAMEPLAY_BLOCKS
        if(!queue_pointer(state,state.world_buttons.update(false,0,utc))){close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;}
#endif
        state.observation_recovery.defer();
        return;
    }
    // Enter full capture before forwarding E/Esc. The native device callbacks
    // drain old state on a mode change; no world/pointer edge crosses that drain.
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
    const auto new_keys=(held&~state.previous_keys)|ui_pulses;
    const bool chat_open=peer->ack.screen==0&&(new_keys&((1u<<11)|(1u<<12)))!=0;
    const bool toggle_edge=!state.observation_recovery.pending()&&
        (chat_open||(peer->ack.screen!=2&&(new_keys&((1u<<9)|(1u<<10)))!=0));
#else
    const bool toggle_edge=!state.observation_recovery.pending()&&((held&~state.previous_keys)&((1u<<9)|(1u<<10)))!=0;
#endif
    const auto desired=state.selective_mode.update(step==ui::KeyboardGate::Step::active&&peer->state==1,
        state.transition,peer->ack.screen,state.uploaded_screen,toggle_edge,mouse_buttons,
#if defined(MINECOME_HUD_GAMEPLAY_MOVEMENT) && !defined(MINECOME_HUD_GAMEPLAY_BLOCKS)
        // Once neutral world passthrough is established, ordinary native clicks
        // must not reacquire full mouse capture or interrupt walking. Inventory
        // still owns a mouse lease until held buttons drain on screen close.
        state.gameplay_keyboard_leased&&!state.mouse_leased);
#else
        state.selective_lease.allows(mouse::Mode::buttons));
#endif
#ifdef MINECOME_HUD_GAMEPLAY
    // UI-only gameplay preserves native walking. The separate movement profile
    // captures the keyboard in-world too; neither captures native camera axes.
    const bool full_capture=desired==mouse::Mode::full;
#ifdef MINECOME_HUD_GAMEPLAY_MOVEMENT
    constexpr auto keyboard_mode=gameplay_keyboard::Mode::full;
#else
    const auto keyboard_mode=full_capture?gameplay_keyboard::Mode::full:gameplay_keyboard::Mode::ui;
#endif
    if(!gameplay_keyboard_api->request(reinterpret_cast<std::uintptr_t>(state.window),reinterpret_cast<std::uintptr_t>(runtime),100,
        keyboard_mode)){
        close_keyboard(runtime,ui::CloseCause::eligibility_lost);release_mouse(runtime,state);return;
    }
    state.gameplay_keyboard_leased=true;
#ifdef MINECOME_HUD_GAMEPLAY_BLOCKS
    // World capture absorbs buttons, not camera motion. Inventory still uses
    // the established full capture and device drain before any UI dispatch.
    if(full_capture)runtime->block_input_next_frame();
#else
    if(!full_capture)release_mouse(runtime,state);
    else {
        runtime->block_input_next_frame();
#endif
#endif
    const auto requested=state.selective_lease.request_mode(desired);
    mouse::Snapshot world_capture;
    const bool previously_owned=state.selective_lease.owned(),previously_pending=state.selective_lease.pending();
    const auto old_generation=state.selective_lease.generation();
    const auto capture_result=mouse_api->request(reinterpret_cast<std::uintptr_t>(state.window),
        reinterpret_cast<std::uintptr_t>(runtime),100,requested,&world_capture);
    if(service->busy_request_preserves_lease.load(std::memory_order_acquire)&&
       state.selective_lease.defer_renewal(capture_result,requested,st::steady_ms())){
        // Requires the coordinated proxy: an unapplied BUSY request preserves
        // only the last proven lease. No deadline, generation, mode or control
        // edge is accepted here. A subsequent fresh query/request must succeed
        // before existing neutral recovery can resume forwarding.
#ifdef MINECOME_HUD_WORLD_CLICKS
        state.world_click.suspend();
#endif
#ifdef MINECOME_HUD_GAMEPLAY_BLOCKS
        if(!queue_pointer(state,state.world_buttons.update(false,0,utc))){close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;}
#endif
        state.observation_recovery.defer();
        service->busy_renewals_deferred.fetch_add(1,std::memory_order_relaxed);
        return;
    }
    const auto capture_step=state.selective_lease.accept(capture_result,world_capture,requested,
        reinterpret_cast<std::uintptr_t>(runtime),now);
    // A contradictory screen edge while a buttons-mode drain is pending ends
    // this bounded session, rather than opening inventory with camera passthrough.
    if(capture_step==mouse::ForwardingLease::Step::failed||(desired==mouse::Mode::full&&requested==mouse::Mode::buttons)){
        if((world_capture.flags&mouse::active)&&world_capture.token==reinterpret_cast<std::uintptr_t>(runtime))state.mouse_leased=true;
        mouse_receipt("selective_mouse_request_failed",capture_result,world_capture);
        close_keyboard(runtime,ui::CloseCause::mouse_capture);release_mouse(runtime,state);return;
    }
    state.mouse_leased=state.selective_lease.owned();state.mouse_generation=state.selective_lease.generation();
    if(!previously_owned||old_generation!=state.mouse_generation||previously_pending!=state.selective_lease.pending())
        mouse_receipt(state.selective_lease.pending()?"selective_mouse_pending":"selective_mouse_ready",capture_result,world_capture);
#if defined(MINECOME_HUD_GAMEPLAY) && !defined(MINECOME_HUD_GAMEPLAY_BLOCKS)
    }
#endif
#elif defined(MINECOME_HUD_WORLD_CLICKS)
    // Deliberate bounded-lab policy: strict v1 capture freezes the complete
    // KCD mouse while world clicks or inventory own input. It is acquired
    // during neutral settling and kept across screen transitions.
    mouse::Snapshot world_capture;
    const auto capture_result=mouse_api->request(reinterpret_cast<std::uintptr_t>(state.window),reinterpret_cast<std::uintptr_t>(runtime),100,&world_capture);
    if(capture_result==mouse::Result::draining&&!state.mouse_leased)return;
    if(capture_result!=mouse::Result::ok||!(world_capture.flags&mouse::active)||
        (state.mouse_leased&&world_capture.generation!=state.mouse_generation)){
        mouse_receipt("world_mouse_request_failed",capture_result,world_capture);close_keyboard(runtime,ui::CloseCause::mouse_capture);release_mouse(runtime,state);return;
    }
    if(!state.mouse_leased){state.mouse_generation=world_capture.generation;state.mouse_leased=true;mouse_receipt("world_mouse_acquired",capture_result,world_capture);}
#endif
    if(step!=ui::KeyboardGate::Step::active||peer->state!=1)return;
#ifdef MINECOME_HUD_SELECTIVE_MOUSE
    if(state.observation_recovery.pending()){
        // Successful query/request has restored observation of the same lease.
        // Release only previously forwarded controls, never replay input from
        // the unavailable interval. New input requires two neutral frames.
#ifdef MINECOME_HUD_PHYSICAL_MOVEMENT
        if(!queue_movement(state,state.movement.update(false,held>>ui_key_count),utc)){
            close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;
        }
#endif
        for(std::size_t i=0;i<ui_key_count;++i)if(
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
            state.chat_world_held
#else
            state.previous_keys
#endif
            &(1u<<i)){
            if(!queue_input(state,{utc,ui::Kind::key_up,keys[i],0,0,0})){
                close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;
            }
        }
        state.previous_keys=0;
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
        state.chat_world_held=0;
        const auto recovered_chat=state.chat_keyboard.update(false,chat_keys,now);
        for(unsigned key=0;key<chat_keys.size();++key)if(recovered_chat.up[key]){
            if(!queue_input(state,{utc,ui::Kind::edit_up,key,0,0,0})){close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;}
        }
#endif
        ui::PointerBatch releases;state.pointer.close(utc,releases);
        if(!queue_pointer(state,releases)){close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;}
        std::uint32_t recovery_x=0,recovery_y=0;std::int16_t recovery_wheel=0;
        runtime->get_mouse_cursor_position(&recovery_x,&recovery_y,&recovery_wheel);
        if(!state.observation_recovery.update(held,mouse_buttons,recovery_wheel))return;
    }
#endif
#ifdef MINECOME_HUD_LIVE_MOUSE
    if(state.transition&&peer->ack.sequence>=state.transition_sequence&&peer->ack.screen==state.transition_screen&&state.uploaded_screen==
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
        ui::chat_render_screen(peer->ack.screen))
#else
        peer->ack.screen)
#endif
        state.transition=false;
#if !defined(MINECOME_HUD_WORLD_CLICKS) && !defined(MINECOME_HUD_SELECTIVE_MOUSE)
    if(state.mouse_leased){ // Also covers the bounded close-screen ACK interval.
        mouse::Snapshot renewed;
        const auto result=mouse_api->request(reinterpret_cast<std::uintptr_t>(state.window),reinterpret_cast<std::uintptr_t>(runtime),100,&renewed);
        if(result!=mouse::Result::ok||!(renewed.flags&mouse::active)||renewed.generation!=state.mouse_generation){
            mouse_receipt("mouse_renew_failed",result,renewed);close_keyboard(runtime,ui::CloseCause::mouse_capture);release_mouse(runtime,state);return;
        }
    }
#endif
#endif
#ifdef MINECOME_HUD_PHYSICAL_MOVEMENT
    // Movement must release before the UI toggle, including simultaneous W+E.
    // Wait for both actual guest screen and its composed pixels to agree.
    const bool movement_ready=!state.transition&&!toggle_edge&&peer->ack.screen==0&&state.uploaded_screen==0&&
#if defined(MINECOME_HUD_GAMEPLAY_MOVEMENT) && !defined(MINECOME_HUD_GAMEPLAY_BLOCKS)
        state.gameplay_keyboard_leased&&!full_capture;
#else
        state.selective_lease.allows(mouse::Mode::buttons);
#endif
    if(!queue_movement(state,state.movement.update(movement_ready,held>>ui_key_count
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
        // source/input.hpp is_key_released preserves one sub-frame release;
        // ReleasedTapGate has already rejected transitions/modifier ambiguity.
        ,chat_pulses[VK_SPACE]?16u:0u
#endif
        ),utc)){
        close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;
    }
#endif
#ifdef MINECOME_HUD_GAMEPLAY_BLOCKS
    // Release held world actions before E/Esc is put into the same ordered ring.
    if(state.transition||toggle_edge||peer->ack.screen!=0||state.uploaded_screen!=0||!state.selective_lease.allows(mouse::Mode::buttons)){
        if(!queue_pointer(state,state.world_buttons.update(false,0,utc))){close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;}
    }
#endif
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
    const bool chat_ready=peer->ack.screen==2&&!state.transition&&state.uploaded_screen==1&&state.selective_lease.allows(mouse::Mode::full)&&!state.observation_recovery.pending();
    const auto chat_edges=state.chat_keyboard.update(chat_ready,chat_keys,now,chat_pulses);
    for(unsigned key=0;key<chat_keys.size();++key)if(chat_edges.up[key]){
        if(!queue_input(state,{utc,ui::Kind::edit_up,key,0,0,0})){close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;}
    }
    if(chat_ready){
        // ReShade v6.8.0 publicly exposes key state, not its private WM_CHAR
        // buffer (source/input.hpp). Use the foreground owning thread's layout
        // and ToUnicodeEx flag 4: Win10 1607+ leaves kernel dead-key state intact.
        // https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-tounicodeex
        // No hooks, IME, clipboard or Ctrl/Alt shortcuts are synthesized.
        const auto layout=GetKeyboardLayout(GetWindowThreadProcessId(state.window,nullptr));
        chat_keys[VK_CAPITAL]|=state.chat_caps?1:0;
        for(unsigned key=0;key<chat_keys.size();++key)if(chat_edges.down[key]){
            if(ui::valid_edit(key)){
                if(!queue_input(state,{utc,ui::Kind::edit_down,key,0,0,0})){close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;}
                if(chat_edges.pulse[key]){
                    if(!queue_input(state,{utc,ui::Kind::edit_up,key,0,0,0})){close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;}
                } else state.chat_keyboard.forwarded_edit(key);
                if(key==VK_RETURN||key==VK_ESCAPE){
                    ui::PointerBatch releases;state.pointer.close(utc,releases);
                    if(!queue_pointer(state,releases)){close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;}
                    state.transition=true;state.transition_screen=0;state.transition_sequence=state.forwarded_events;
                    break; // Do not type later same-frame keys into a closing chat.
                }
            } else {
                std::array<wchar_t,8> text{};
                const int count=ToUnicodeEx(key,MapVirtualKeyExW(key,MAPVK_VK_TO_VSC,layout),chat_keys.data(),text.data(),static_cast<int>(text.size()),4,layout);
                if(count>0&&count<=static_cast<int>(text.size())&&!ui::chat_utf16(
                    std::span<const std::uint16_t>(reinterpret_cast<const std::uint16_t *>(text.data()),static_cast<std::size_t>(count)),
                    [&](std::uint32_t scalar){return queue_input(state,{utc,ui::Kind::text,scalar,0,0,0});})){
                    close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;
                }
            }
        }
    }
    // Acknowledged chat owns every printable key, including E and digits.
    // During either handoff keep a baseline but dispatch no world UI toggles.
    const bool chat_owned=peer->ack.screen==2||(state.transition&&state.transition_screen==2);
#endif
    const auto changed=(held^state.previous_keys)
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
        |ui_pulses
#endif
        ;
    for(std::size_t i=0;i<ui_key_count;++i)if(changed&(1u<<i)) {
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
        const bool pulse=(ui_pulses&(1u<<i))!=0;
        const bool down=pulse||(held&(1u<<i))!=0;
        if(chat_owned)continue;
        if(ui::world_one_shot(keys[i])&&(peer->ack.screen!=0||!down))continue;
        if(ui::perspective_key(keys[i])&&!ui::perspective_allowed(state.format,peer->ack.screen))continue;
        if(!down&&!(state.chat_world_held&(1u<<i)))continue;
        if(state.transition&&down)continue;
#else
        const bool down=(held&(1u<<i))!=0;
#endif
        const ui::Event event{st::utc_ms(),down?ui::Kind::key_down:ui::Kind::key_up,keys[i],0,0,0};
#ifdef MINECOME_HUD_LIVE_MOUSE
        const bool toggle=event.kind==ui::Kind::key_down&&(keys[i]==0x45||keys[i]==0x1b
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
            ||ui::chat_opener(keys[i])
#endif
            );
        if(toggle){
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
            if(ui::chat_opener(keys[i])){
                for(std::size_t held_key=0;held_key<ui_key_count;++held_key)if(state.chat_world_held&(1u<<held_key)){
                    if(!queue_input(state,{utc,ui::Kind::key_up,keys[held_key],0,0,0})){close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;}
                }
                state.chat_world_held=0;
            }
#endif
#ifdef MINECOME_HUD_WORLD_CLICKS
            state.world_click.suspend();
#endif
            if(state.transition){close_keyboard(runtime,ui::CloseCause::mouse_transition);release_mouse(runtime,state);return;}
            ui::PointerBatch releases;state.pointer.close(utc,releases);
            if(!queue_pointer(state,releases)){close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;}
        }
        if(!queue_input(state,event)){close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;}
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
        if(!ui::world_one_shot(keys[i])&&!pulse){
            if(event.kind==ui::Kind::key_down)state.chat_world_held|=1u<<i;
            else state.chat_world_held&=~(1u<<i);
        }
        // Chat openers and F5 are one-shot requests. Pair their releases now;
        // F5 never enters a screen handoff or leaves a held key in Java.
        if((ui::world_one_shot(keys[i])||pulse)&&!queue_input(state,{utc,ui::Kind::key_up,keys[i],0,0,0})){
            close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;
        }
#endif
        if(toggle){state.transition=true;state.transition_sequence=state.forwarded_events;
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
            state.transition_screen=ui::chat_opener(keys[i])?2u:(keys[i]==0x45&&peer->ack.screen==0?1u:0u);
#else
            state.transition_screen=keys[i]==0x45&&peer->ack.screen==0;
#endif
        }
#else
        if(!service->input_mailbox->push(event)) {close_keyboard(runtime,ui::CloseCause::mailbox_overflow);return;}
#endif
    }
    state.previous_keys=held&((1u<<ui_key_count)-1);
#ifdef MINECOME_HUD_LIVE_MOUSE
    if(state.transition){
#ifdef MINECOME_HUD_WORLD_CLICKS
        state.world_click.suspend();
#endif
        return;
    }
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
    // Chat editing is keyboard-only. Keep the full native mouse lease to stop
    // camera/attacks, but never send inventory pointer edges to ChatScreen.
    if(peer->ack.screen==2)return;
#endif
    if(peer->ack.screen==0){
        ui::PointerBatch releases;state.pointer.close(utc,releases);
        if(releases.count){close_keyboard(runtime,ui::CloseCause::mouse_transition);release_mouse(runtime,state);return;}
        // Closing inventory while dragging releases the guest first. Keep the
        // bounded native lease until the physical buttons are neutral so a
        // still-held click cannot become a KCD attack on screen close.
#ifdef MINECOME_HUD_GAMEPLAY_BLOCKS
        const bool buttons_ready=state.uploaded_screen==0&&state.mouse_leased&&state.selective_lease.allows(mouse::Mode::buttons);
        if(!queue_pointer(state,state.world_buttons.update(buttons_ready,mouse_buttons,utc))){close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;}
#elif defined(MINECOME_HUD_WORLD_CLICKS)
        auto click=state.world_click.update(state.uploaded_screen==0&&state.mouse_leased
#ifdef MINECOME_HUD_SELECTIVE_MOUSE
            &&state.selective_lease.allows(mouse::Mode::buttons)
#endif
            ,mouse_buttons,utc,now,state.forwarded_events);
        if(state.world_click.failure()!=world::Gate::Failure::none){close_keyboard(runtime,ui::CloseCause::mouse_transition);release_mouse(runtime,state);return;}
        click.window=reinterpret_cast<std::uintptr_t>(state.window);click.token=reinterpret_cast<std::uintptr_t>(runtime);click.generation=state.mouse_generation;
        click.lease_deadline=now+world_capture.lease_remaining_ms;
        if(click.sequence&&!service->world_clicks->push(click)){close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;}
#elif !defined(MINECOME_HUD_PHYSICAL_MOVEMENT)
        if(!mouse_buttons)release_mouse(runtime,state);
#endif
        return;
    }
#ifdef MINECOME_HUD_WORLD_CLICKS
    state.world_click.suspend();
#endif
    if(state.uploaded_screen!=1)return;
#ifdef MINECOME_HUD_SELECTIVE_MOUSE
    if(!state.selective_lease.allows(mouse::Mode::full))return;
#else
    if(!state.mouse_leased){
        mouse::Snapshot capture;
        const auto result=mouse_api->request(reinterpret_cast<std::uintptr_t>(state.window),reinterpret_cast<std::uintptr_t>(runtime),100,&capture);
        if(result==mouse::Result::draining)return;
        if(result!=mouse::Result::ok||!(capture.flags&mouse::active)){
            mouse_receipt("mouse_request_failed",result,capture);close_keyboard(runtime,ui::CloseCause::mouse_capture);release_mouse(runtime,state);return;
        }
        state.mouse_generation=capture.generation;state.mouse_leased=true;mouse_receipt("mouse_acquired",result,capture);
    }
#endif
    RECT client{};std::uint32_t x=0,y=0;std::int16_t wheel=0;
    runtime->get_mouse_cursor_position(&x,&y,&wheel);
    if(!GetClientRect(state.window,&client)){close_keyboard(runtime,ui::CloseCause::mouse_capture);release_mouse(runtime,state);return;}
    const auto point=ui::pointer_point(static_cast<float>(static_cast<std::int32_t>(x)),static_cast<float>(static_cast<std::int32_t>(y)),
        static_cast<float>(client.right-client.left),static_cast<float>(client.bottom-client.top),state.rectangle);
    if(!point.valid){close_keyboard(runtime,ui::CloseCause::mouse_capture);release_mouse(runtime,state);return;}
    const auto batch=state.pointer.update(true,true,mouse_buttons,point,wheel,utc);
    if(!queue_pointer(state,batch)){close_keyboard(runtime,ui::CloseCause::mailbox_overflow);release_mouse(runtime,state);return;}
    if(state.pointer.active()&&point.inside){
        runtime->set_uniform_value_float(state.cursor,(state.rectangle.x+point.x*state.rectangle.width)*state.target_width,
            (state.rectangle.y+point.y*state.rectangle.height)*state.target_height,std::max(1.0f,state.target_height/720.0f),0.0f);
        runtime->set_uniform_value_bool(state.cursor_visible,true);
    }
#endif
}
struct InputFrame {
    api::effect_runtime *runtime;
    RuntimeState &state;
    bool composed=false;
    std::uint32_t composition_stage=0;
    ~InputFrame() {
        try {capture_keyboard(runtime,state,composed,composition_stage);}
        catch(...) {
            close_keyboard(runtime,ui::CloseCause::callback_exception);
#ifdef MINECOME_HUD_LIVE_MOUSE
            try {release_mouse(runtime,state);} catch(...) { /* Internal lease still expires after 100 ms. */ }
#endif
        }
    }
};
bool sdr(api::format format) {
    return format == api::format::r8g8b8a8_unorm || format == api::format::r8g8b8a8_unorm_srgb ||
        format == api::format::b8g8r8a8_unorm || format == api::format::b8g8r8a8_unorm_srgb;
}
void hide(api::effect_runtime *runtime, RuntimeState &state) {
    if (state.active != 0) runtime->set_uniform_value_bool(state.active,false);
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
    if(state.warp_ready!=0)runtime->set_uniform_value_bool(state.warp_ready,false);
    if(state.warp_technique!=0)runtime->set_technique_state(state.warp_technique,false);
#endif
#ifdef MINECOME_HUD_LIVE_MOUSE
    if(state.cursor_visible!=0)runtime->set_uniform_value_bool(state.cursor_visible,false);
#endif
}
void forget(RuntimeState &state) { state.active={}; state.frame={}; state.rect={}; state.technique={}; state.bound=false;
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
    state.layers={};state.depth_ready={};state.depth_projection={};state.depth_nearest={};state.guest_projection={};state.host_depth={};
    state.warp_ready={};state.warp_uniforms={};state.warp_technique={};
#endif
#ifdef MINECOME_HUD_LIVE_MOUSE
    state.cursor_visible={};state.cursor={};
#endif
}
bool handles(api::effect_runtime *runtime, RuntimeState &state) {
    if (state.active == 0) {
        state.active=runtime->find_uniform_variable(effect_name,"McHudActive");
        state.frame=runtime->find_uniform_variable(effect_name,"McHudFrame");
        state.rect=runtime->find_uniform_variable(effect_name,"McHudRect");
        state.technique=runtime->find_technique(effect_name,"MineComeHud");
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
        state.layers=runtime->find_uniform_variable(effect_name,"McHudLayers");
        state.depth_ready=runtime->find_uniform_variable(effect_name,"McHostDepthReady");
        state.depth_projection=runtime->find_uniform_variable(effect_name,"McHostProjection");
        state.depth_nearest=runtime->find_uniform_variable(effect_name,"McHostNearest");
        state.guest_projection=runtime->find_uniform_variable(effect_name,"McGuestProjection");
        state.host_depth=runtime->find_texture_variable(effect_name,"McHostDepth");
        state.warp_ready=runtime->find_uniform_variable(effect_name,"McWorldWarpReady");
        state.warp_technique=runtime->find_technique(effect_name,"MineComeWorldWarp");
        for(std::size_t i=0;i<state.warp_uniforms.size();++i)state.warp_uniforms[i]=runtime->find_uniform_variable(effect_name,warp_uniform_names[i]);
#endif
#ifdef MINECOME_HUD_LIVE_MOUSE
        state.cursor_visible=runtime->find_uniform_variable(effect_name,"McHudCursorVisible");
        state.cursor=runtime->find_uniform_variable(effect_name,"McHudCursor");
#endif
    }
    if (state.active == 0 || state.frame == 0 || state.rect == 0 || state.technique == 0) { forget(state); return false; }
#ifdef MINECOME_HUD_LIVE_MOUSE
    if(state.cursor_visible==0||state.cursor==0){forget(state);return false;}
#endif
    return true;
}
void release(api::effect_runtime *runtime, RuntimeState &state, bool after_reset) {
#ifdef MINECOME_HUD_LIVE_MOUSE
    release_mouse(runtime,state);
#endif
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
    if (state.texture != 0) return state.width == frame.header.width && state.height == frame.header.height && state.format == frame.header.format;
#ifndef MINECOME_HUD_GAMEPLAY_CHAT
    if (frame.header.format != 1) return fail(state,7);
#endif
    auto *device=runtime->get_device();
    state.width=frame.header.width; state.height=frame.header.height; state.pitch=(state.width*4+255u)&~255u;
    state.format=frame.header.format;state.texture_height=state.height*(state.format==2?3u:1u);
    if (!device->create_resource(api::resource_desc(state.width,state.texture_height,1,1,api::format::r8g8b8a8_unorm,1,
            api::memory_heap::default_,api::resource_usage::shader_resource|api::resource_usage::copy_dest),
            nullptr,api::resource_usage::shader_resource,&state.texture) ||
        !device->create_resource_view(state.texture,api::resource_usage::shader_resource,
            api::resource_view_desc(api::format::r8g8b8a8_unorm),&state.view) ||
        !device->create_fence(0,api::fence_flags::none,&state.fence)) return fail(state,1);
    for (auto &slot : state.uploads) {
        if (!device->create_resource(api::resource_desc(std::uint64_t(state.pitch)*state.texture_height,api::memory_heap::upload,
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
    if (!device->map_buffer_region(slot->buffer,0,std::uint64_t(state.pitch)*state.texture_height,api::map_access::write_only,&mapped)) {
        ++service->dropped; return false;
    }
    for (std::uint32_t row=0;row<state.texture_height;++row)
        std::memcpy(static_cast<std::uint8_t *>(mapped)+std::size_t(row)*state.pitch,
            frame.premultiplied.data()+std::size_t(row)*frame.header.pitch,frame.header.pitch);
    device->unmap_buffer_region(slot->buffer);
    commands->barrier(state.texture,api::resource_usage::shader_resource,api::resource_usage::copy_dest);
    commands->copy_buffer_to_texture(slot->buffer,0,state.pitch/4,state.texture_height,state.texture,0);
    commands->barrier(state.texture,api::resource_usage::copy_dest,api::resource_usage::shader_resource);
    // Pinned ReShade signal flushes its immediate command list before Signal.
    // This fences staging reads only; later effects and next uploads share the
    // same ordered queue. No explicit wait or busy-slot retry loop here.
    slot->completion=++state.next_fence;
    if (!queue->signal(state.fence,slot->completion)) return fail(state,4);
    state.uploaded_sequence=frame.header.sequence;
    state.uploaded_observation=frame.observation; // Never use latest pub age instead.
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
    state.uploaded_header=frame.header;
#endif
#ifdef MINECOME_HUD_LIVE_MOUSE
    state.uploaded_screen=frame.header.screen;
#endif
    ++service->uploaded; return true;
}
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
void update_layers(api::effect_runtime *runtime, RuntimeState &state) {
    std::lock_guard depth_count_lock(depth_counters_mutex);
    struct Readiness {
        RuntimeState &state; bool ready=false;
        ~Readiness(){if(state.previous_depth_ready!=ready)++depth_ready_changes;state.previous_depth_ready=ready;}
    } readiness{state};
    const bool layered=state.format==2;
    runtime->set_uniform_value_bool(state.layers,layered);
    runtime->set_uniform_value_bool(state.depth_ready,false);
    if(!layered)return;
    ++depth_considered;
    if(!depth::instance().metadata_available()){++depth_bad_source;return;}
    const auto &h=state.uploaded_header;
    runtime->set_uniform_value_float(state.guest_projection,h.near_plane,h.far_plane);
    depth::expected_view expected;
    expected.width=state.target_width;expected.height=state.target_height;
    expected.position=h.camera_position;expected.forward=h.camera_direction;expected.up=h.camera_up;
    expected.vertical_fov=h.vertical_fov;expected.captured_unix_ms=h.camera_utc_ms;
    expected.position_tolerance=0.03f;expected.direction_cosine=0.99995f;expected.fov_tolerance=0.005f;
    if(!state.depth_armed){depth::instance().set_presented_sampling(true);depth::instance().arm(true,expected);state.depth_armed=true;}
    else if(state.depth_sequence!=state.uploaded_sequence)depth::instance().update_expected(expected);
    state.depth_sequence=state.uploaded_sequence;
    // DEPTH is maintained by ReShade's public generic-depth addon. Never assume
    // a semantic name itself is a handle or that a dummy depth texture is valid.
    api::resource_view view{},srgb{};
    runtime->get_texture_binding(state.host_depth,&view,&srgb);
    auto *device=runtime->get_device();
    const auto selected=depth::selected_depth(runtime,view);
    if(selected==0){++depth_bad_source;return;}
    // Preserve the proven strict same-view path separately. Its cached sample
    // must pass every original age/pose/source check and can NEVER enable warp.
    if(auto strict=depth::instance().take_sample(device,selected))state.depth_sample=*strict;
    // Reprojection requires a unique current presentation; a matching resource
    // handle or an older strict sample is not sufficient to authorize it.
    const auto presented=depth::take_current_presentation(runtime,view);
    if(!presented&&!state.depth_sample){++depth_no_sample;return;}
    auto selected_sample=presented?presented->view:*state.depth_sample;
    const auto depth_now=st::utc_ms();
    if(depth_now<selected_sample.captured_unix_ms || depth_now-selected_sample.captured_unix_ms>250){++depth_bad_view;++depth_sample_age;return;}
    const auto warp=presented?minecome::world_reprojection::make(presented->view,expected,state.width,state.height,h.capture_utc_ms,depth_now):std::nullopt;
    if(presented&&!warp){++depth_warp_rejected;if(!first_warp_rejection)first_warp_rejection=WarpRejection{presented->view,expected,state.width,state.height,h.capture_utc_ms,depth_now};}
    const auto rejection=warp?depth::view_rejection::none:depth::validate_reason(selected_sample,expected,depth_now);
    if(rejection!=depth::view_rejection::none){
        ++depth_bad_view;
        switch(rejection){
        case depth::view_rejection::age:++depth_camera_age;break;
        case depth::view_rejection::position:++depth_position;break;
        case depth::view_rejection::basis:++depth_basis;break;
        case depth::view_rejection::projection:++depth_projection;break;
        default:++depth_other;break;
        }
        return;
    }
    const auto resource=device->get_resource_from_view(view);
    if(resource==0){++depth_bad_source;return;}
    const auto desc=device->get_resource_desc(resource);
    const auto format=device->get_resource_view_desc(view).format;
    if(desc.type!=api::resource_type::texture_2d || desc.texture.samples!=1 ||
       (format!=api::format::r32_float && format!=api::format::r24_unorm_x8_uint &&
        format!=api::format::r32_float_x8_uint && format!=api::format::r16_unorm)){++depth_bad_source;return;}
    const auto &s=selected_sample;
    if(!depth::matches_depth(runtime,view,s)){++depth_bad_source;return;}
    if(std::abs(static_cast<float>(desc.texture.width)-s.viewport.width)>1 ||
       std::abs(static_cast<float>(desc.texture.height)-s.viewport.height)>1){++depth_bad_source;return;}
    // Letterboxing would compare different camera rays. Fallback captured-ground
    // depth remains active until both renderers cover the same full viewport.
    if(std::abs(state.rectangle.width-1.0f)>0.001f || std::abs(state.rectangle.height-1.0f)>0.001f){++depth_bad_source;return;}
    runtime->set_uniform_value_float(state.depth_projection,s.ratio[0],s.ratio[1],s.far_metres,s.reversed?1.0f:0.0f);
    runtime->set_uniform_value_float(state.depth_nearest,s.nearest[0],s.nearest[1],s.nearest[2],s.nearest[3]);
    if(warp){
        const auto set3=[&](std::size_t index,const depth::vec3 &value){runtime->set_uniform_value_float(state.warp_uniforms[index],value.data(),3);};
        set3(0,warp->source_position);set3(1,warp->source_forward);set3(2,warp->source_up);
        runtime->set_uniform_value_float(state.warp_uniforms[3],warp->source_tan_half.data(),2);
        set3(4,warp->target_position);set3(5,warp->target_right);set3(6,warp->target_forward);set3(7,warp->target_up);
        for(unsigned i=0;i<4;++i)runtime->set_uniform_value_float(state.warp_uniforms[8+i],warp->clip[i].data(),4);
        runtime->set_uniform_value_bool(state.warp_ready,true);
        runtime->set_technique_state(state.warp_technique,true);++depth_reprojected;
    }else if(!presented)++depth_strict_fallback;
    runtime->set_uniform_value_bool(state.depth_ready,true);++depth_frames;readiness.ready=true;
}
#endif
#ifdef MINECOME_HUD_REPEAT_SESSION
bool prepare_repeat_generation() {
    std::lock_guard lock(runtimes_mutex);
    for(const auto &[runtime,state]:runtimes) {
        if(state.failed||(service->rearm_policy.admitted_count()>1&&!state.repeat_retired))return false;
    }
    // New input gates and sequence state; keep same-sized GPU storage and its
    // fences. Same-queue ordering protects reuse without a render-thread wait.
    for(auto &[runtime,state]:runtimes) {
        RuntimeState next;
        next.window=state.window;next.reshade_overlay=state.reshade_overlay;
        next.texture=state.texture;next.view=state.view;next.fence=state.fence;next.uploads=state.uploads;
        next.width=state.width;next.height=state.height;next.pitch=state.pitch;next.next_fence=state.next_fence;
        next.texture_height=state.texture_height;next.format=state.format;
        state=std::move(next);
    }
    service->session.store({});service->publication.store({});service->input_status.store({});
    service->input_mailbox=std::make_unique<ui::Mailbox>();service->world_clicks=std::make_unique<world::Queue>();
    service->pending_click={};service->input_request.store(0);service->input_owner.store(nullptr);service->last_input_render.store(0);
    service->uploaded.store(0);service->dropped.store(0);service->submitted.store(0);
    input_signals.store(std::make_shared<InputSignals>(),std::memory_order_release);
    service->terminal.store(false,std::memory_order_release);service->retiring.store(false,std::memory_order_release);
    return true;
}
bool repeat_render_retired() {
    std::unique_lock lock(runtimes_mutex,std::try_to_lock);
    if(!lock.owns_lock()||runtimes.empty()||service->publication.load())return false;
    for(const auto &[runtime,state]:runtimes)if(!state.repeat_retired||state.failed)return false;
    return true;
}
void retire_render_generation(api::effect_runtime *runtime,RuntimeState &state) {
    hide(runtime,state);
    state.repeat_retired=false;
    if(service->input_owner.load(std::memory_order_acquire)==runtime) {
        mouse::Snapshot capture;
        // query alone does not assert token ownership in API2. Release checks
        // the real window/token even if an earlier release already succeeded.
        const auto token=reinterpret_cast<std::uintptr_t>(runtime);
        const auto result=mouse_api->release(reinterpret_cast<std::uintptr_t>(state.window),token,&capture);
        if(!rearm::capture_released(result,capture,token,state.mouse_generation))return;
        state.mouse_leased=false;state.selective_lease.released();
    } else if(state.mouse_leased) return;
    state.uploaded_sequence=0;state.uploaded_observation=0;state.uploaded_screen=0;
    state.repeat_retired=true;
}
#endif
void on_init(api::effect_runtime *runtime) {
    if (runtime->get_device()->get_api() != api::device_api::d3d12) return;
    std::lock_guard lock(runtimes_mutex);
    RuntimeState state; state.window=reinterpret_cast<HWND>(runtime->get_hwnd());
    if (owned_window(state.window)) runtimes.try_emplace(runtime,std::move(state));
}
void on_destroy(api::effect_runtime *runtime) {
    std::lock_guard lock(runtimes_mutex);
    const auto it=runtimes.find(runtime); if (it == runtimes.end()) return;
    close_keyboard(runtime,ui::CloseCause::runtime_destroy);release(runtime,it->second,true); runtimes.erase(it); receipt("cleanup","runtime_owned_resources_released");
}
void on_reload(api::effect_runtime *runtime) {
    std::lock_guard lock(runtimes_mutex);
    const auto it=runtimes.find(runtime); if (it != runtimes.end()) {close_keyboard(runtime,ui::CloseCause::runtime_reload);
#ifdef MINECOME_HUD_LIVE_MOUSE
        release_mouse(runtime,it->second);
#endif
        forget(it->second);}
}
bool on_overlay(api::effect_runtime *runtime,bool open,api::input_source) {
    std::lock_guard lock(runtimes_mutex);
    const auto it=runtimes.find(runtime);
    if(it!=runtimes.end()) {it->second.reshade_overlay=open;if(open){
        close_keyboard(runtime,ui::CloseCause::overlay_open);
#ifdef MINECOME_HUD_LIVE_MOUSE
        release_mouse(runtime,it->second);
#endif
    }}
    return false; // Observe ReShade's UI; never prevent it opening.
}
void on_begin(api::effect_runtime *runtime, api::command_list *commands, api::resource_view rtv, api::resource_view) {
    const auto callback_signals=input_signals.load(std::memory_order_acquire);
    std::unique_lock lock(runtimes_mutex,std::try_to_lock);
    if (!lock.owns_lock()) {
        if(callback_signals->input_has_started.load(std::memory_order_acquire)) {
            ui::CloseSnapshot snapshot;snapshot.cause=ui::CloseCause::runtime_lock_contention;snapshot.utc=st::utc_ms();
            callback_signals->first_close.publish(snapshot);callback_signals->input_force_close.store(true,std::memory_order_release);
        }
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
#ifdef MINECOME_HUD_REPEAT_SESSION
    if(callback_signals!=input_signals.load(std::memory_order_acquire))return;
    if(service->retiring.load(std::memory_order_acquire)) {
        try {retire_render_generation(runtime,state);} catch(...) {fail(state,6);}
        return;
    }
#endif
    InputFrame input_frame{runtime,state};
    try {
        // A withdrawn/expired publication must hide previously enabled effects.
        // Unarmed runtime has zero handles, so this makes no effect API call.
        hide(runtime,state);
        input_frame.composition_stage=1; // Renderer or whole session unavailable.
        if (state.failed || service->terminal.load(std::memory_order_acquire)) return;
        const auto session=service->session.load(std::memory_order_acquire);
        const auto frame=service->publication.load(std::memory_order_acquire);
        auto now=st::steady_ms();
        input_frame.composition_stage=2; // Session/publication freshness.
        if (!session || !frame || !session->live(st::utc_ms(),now) || !st::uploaded_fresh(frame->observation,now)) return;
        input_frame.composition_stage=3; // Foreground, command list, effects, SDR.
        if (!visible(runtime,state) || !commands || rtv == 0 || !handles(runtime,state) ||
            !sdr(runtime->get_device()->get_resource_view_desc(rtv).format)) return;
        input_frame.composition_stage=4;
        const auto target=runtime->get_device()->get_resource_from_view(rtv);
        if (target == 0) return;
        input_frame.composition_stage=5;
        const auto desc=runtime->get_device()->get_resource_desc(target);
        if (desc.type != api::resource_type::texture_2d || !sdr(desc.texture.format)) return;
        input_frame.composition_stage=6;
        const auto rectangle=hud::fit_rect(frame->header.width,frame->header.height,desc.texture.width,desc.texture.height);
#ifdef MINECOME_HUD_LIVE_MOUSE
        state.rectangle=rectangle;state.target_width=desc.texture.width;state.target_height=desc.texture.height;
#endif
        if (rectangle.width <= 0 || rectangle.height <= 0) return;
        input_frame.composition_stage=7;
        upload(runtime,commands,state,*frame);
        if (state.failed || state.uploaded_sequence == 0 || state.view == 0) return;
        input_frame.composition_stage=8;
        if (!state.bound) {
            runtime->update_texture_bindings(semantic,state.view,state.view);
            runtime->set_uniform_value_int(state.frame,0);
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
            if(state.warp_technique==0 || state.warp_ready==0 ||
               std::any_of(state.warp_uniforms.begin(),state.warp_uniforms.end(),[](auto value){return value==0;})){fail(state,9);return;}
            // ReShade preset sorting can override declaration order. The two
            // owned techniques must run warp first, foreground composition last.
            // This precedes runtime.cpp's technique iteration in begin-effects.
            const api::effect_technique order[]={state.warp_technique,state.technique};
            runtime->reorder_techniques(std::size(order),order);
#endif
            runtime->set_technique_state(state.technique,true);
            state.bound=true;
        }
        now=st::steady_ms();
        input_frame.composition_stage=9; // Resident texture/lease/focus recheck.
        // Recheck after ReShade resource/semantic APIs; their implementation can
        // take time. A stream of dropped new frames never refreshes resident age.
        if (service->terminal.load(std::memory_order_acquire) || !session->live(st::utc_ms(),now) ||
            !st::uploaded_fresh(state.uploaded_observation,now) || !visible(runtime,state)) return;
        input_frame.composition_stage=10;
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
        if(state.layers==0 || state.depth_ready==0 || state.depth_projection==0 || state.depth_nearest==0 || state.guest_projection==0 || state.host_depth==0){fail(state,8);return;}
        update_layers(runtime,state);
#endif
        runtime->set_uniform_value_float(state.rect,rectangle.x,rectangle.y,rectangle.width,rectangle.height);
        runtime->set_uniform_value_bool(state.active,true); ++service->submitted;
        input_frame.composition_stage=11;
        input_frame.composed=true;
    } catch (...) { fail(state,5); hide(runtime,state); }
}
} // namespace
#if defined(MINECOME_HUD_GAMEPLAY_CHAT)
extern "C" __declspec(dllexport) const char *NAME="MineCome continuous Minecraft HUD, walking, blocks and chat";
extern "C" __declspec(dllexport) const char *DESCRIPTION="Gameplay input v6: world buttons, WASD/Space/Shift/Ctrl, inventory, T/slash vanilla chat and commands. Foreground layout text/edit keys only; no clipboard, IME or editor Ctrl/Alt chords. F8 stops.";
#elif defined(MINECOME_HUD_GAMEPLAY_BLOCKS)
extern "C" __declspec(dllexport) const char *NAME="MineCome continuous Minecraft HUD walking and blocks";
extern "C" __declspec(dllexport) const char *DESCRIPTION="Gameplay input v5 with held world buttons, WASD/Space and inventory, automatic neutral activation and F8 stop. Native camera passes outside inventory; no diagnostic click or duration cap.";
#elif defined(MINECOME_HUD_GAMEPLAY_MOVEMENT)
extern "C" __declspec(dllexport) const char *NAME="MineCome continuous Minecraft HUD and walking";
extern "C" __declspec(dllexport) const char *DESCRIPTION="Opt-in gameplay input v4 with v5 keyboard capture; neutral activation, F8 stop, WASD/Space and inventory forwarding. KCD camera and world mouse remain native; no world-click bridge or demo timer.";
#elif defined(MINECOME_HUD_GAMEPLAY)
extern "C" __declspec(dllexport) const char *NAME="MineCome continuous Minecraft HUD and inventory";
extern "C" __declspec(dllexport) const char *DESCRIPTION="Opt-in gameplay v3 with v5 per-key capture; neutral activation, F8 stop and short peer leases. KCD owns world movement and mouse outside inventory; no demo timer.";
#elif defined(MINECOME_HUD_REPEAT_SESSION)
extern "C" __declspec(dllexport) const char *NAME="MineCome repeatable walking aimed lab";
extern "C" __declspec(dllexport) const char *DESCRIPTION="Opt-in two-session profile; each session retains its original 30-second input limit. A new producer and verified native/controller cleanup are required before explicit rearm.";
#elif defined(MINECOME_HUD_WALKING_AIMED)
extern "C" __declspec(dllexport) const char *NAME="MineCome bounded walking aimed lab";
extern "C" __declspec(dllexport) const char *DESCRIPTION="Exact KCD2 tools/D3D12 genuine HUD; explicit input v2 walking and UI keys, selective inventory capture and original physical world-click edges; one F8 activation at most30 seconds and sixteen clicks. Guest/controller settled proof is required for aimed actions.";
#elif defined(MINECOME_HUD_PHYSICAL_MOVEMENT)
extern "C" __declspec(dllexport) const char *NAME="MineCome bounded physical movement lab";
extern "C" __declspec(dllexport) const char *DESCRIPTION="Exact KCD2 tools/D3D12 genuine HUD; explicit input v2 WASD/Space and UI keys, host camera look, full inventory capture; one F8 activation at most30 seconds, no stone click publication.";
#elif defined(MINECOME_HUD_RAW_OWNER_FILTER)
extern "C" __declspec(dllexport) const char *NAME="MineCome bounded Minecraft raw owner lab";
extern "C" __declspec(dllexport) const char *DESCRIPTION="Exact KCD2 tools/D3D12 genuine HUD; registered helper motion follows the resolved capture owner; full inventory capture, one F8 activation, at most 30 seconds and sixteen clicks. Fixed-cell stone target.";
#elif defined(MINECOME_HUD_MOTION_FILTER)
extern "C" __declspec(dllexport) const char *NAME="MineCome bounded Minecraft motion filter lab";
extern "C" __declspec(dllexport) const char *DESCRIPTION="Exact KCD2 tools/D3D12 genuine HUD; selective DI capture and button-free movement messages; full inventory capture, one F8 activation, at most 30 seconds and sixteen clicks. Fixed-cell stone target.";
#elif defined(MINECOME_HUD_SELECTIVE_MOUSE)
extern "C" __declspec(dllexport) const char *NAME="MineCome bounded Minecraft selective mouse lab";
extern "C" __declspec(dllexport) const char *DESCRIPTION="Exact KCD2 tools/D3D12 genuine HUD; world clicks with KCD camera look, full inventory capture; one F8 activation, at most 30 seconds and sixteen clicks. Fixed-cell stone target.";
#elif defined(MINECOME_HUD_WORLD_CLICKS)
extern "C" __declspec(dllexport) const char *NAME="MineCome bounded Minecraft world click lab";
extern "C" __declspec(dllexport) const char *DESCRIPTION="Exact KCD2 tools/D3D12 genuine HUD; left break/right place intents and inventory mouse; strict capture freezes KCD look, one F8 activation, at most 30 seconds and sixteen clicks.";
#elif defined(MINECOME_HUD_LIVE_MOUSE)
extern "C" __declspec(dllexport) const char *NAME="MineCome bounded Minecraft mouse UI lab";
extern "C" __declspec(dllexport) const char *DESCRIPTION="Exact KCD2 tools/D3D12 genuine UI stream; inventory cursor, left/right clicks, drag and wheel with strict capture; one F8 activation, at most 30 seconds.";
#else
extern "C" __declspec(dllexport) const char *NAME="MineCome bounded Minecraft keyboard UI lab";
extern "C" __declspec(dllexport) const char *DESCRIPTION="Exact KCD2 tools/D3D12 genuine UI stream; one F8 activation, keys 1-9/E/Esc only, at most 30 seconds.";
#endif
extern "C" __declspec(dllexport) bool AddonInit(HMODULE addon, HMODULE reshade_module) {
    if (!reshade::register_addon(addon,reshade_module)) return false;
    try {
#ifdef MINECOME_HUD_GAMEPLAY
        const auto get_keyboard_api=reinterpret_cast<gameplay_keyboard::GetApi>(GetProcAddress(reshade_module,"MineComeGetGameplayKeyboardApi"));
        gameplay_keyboard_api=get_keyboard_api?get_keyboard_api(gameplay_keyboard::api_version,sizeof(gameplay_keyboard::Api)):nullptr;
        if(!gameplay_keyboard_api||gameplay_keyboard_api->size!=sizeof(gameplay_keyboard::Api)||gameplay_keyboard_api->version!=gameplay_keyboard::api_version||
            !gameplay_keyboard_api->query||!gameplay_keyboard_api->request||!gameplay_keyboard_api->release)
            throw std::runtime_error("gameplay_keyboard_v5_runtime_required");
#endif
#ifdef MINECOME_HUD_LIVE_MOUSE
        const auto get_api=reinterpret_cast<mouse::GetApi>(GetProcAddress(reshade_module,
#ifdef MINECOME_HUD_SELECTIVE_MOUSE
            "MineComeGetSelectiveMouseCaptureApi"
#else
            "MineComeGetMouseCaptureApi"
#endif
        ));
        mouse_api=get_api?get_api(mouse::api_version,sizeof(mouse::Api)):nullptr;
        if(!mouse_api||mouse_api->version!=mouse::api_version||mouse_api->size!=sizeof(mouse::Api)||!mouse_api->query||!mouse_api->request||!mouse_api->release)
            throw std::runtime_error("custom_mouse_runtime_required");
#endif
#ifdef MINECOME_HUD_MOTION_FILTER
        motion_diagnostics=reinterpret_cast<motion::ReadDiagnostics>(GetProcAddress(reshade_module,"MineComeReadMotionDiagnostics"));
        motion::Snapshot routes;
        if(!motion_diagnostics||!motion_diagnostics(&routes)||routes.version!=motion::api_version||routes.size!=sizeof(routes))
            throw std::runtime_error("motion_diagnostics_runtime_required");
#endif
#ifdef MINECOME_HUD_RAW_OWNER_FILTER
        raw_motion_diagnostics=reinterpret_cast<raw_motion::ReadDiagnostics>(GetProcAddress(reshade_module,"MineComeReadRawMotionDiagnostics"));
        raw_motion::Snapshot raw_routes;
        if(!raw_motion_diagnostics||!raw_motion_diagnostics(&raw_routes)||raw_routes.version!=raw_motion::api_version||raw_routes.size!=sizeof(raw_routes))
            throw std::runtime_error("raw_motion_diagnostics_runtime_required");
#endif
        service=new Service(addon);
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
        service->renderer_module=reshade_module;
#endif
        if (!service->stop || service->config.empty()) throw std::runtime_error("service_init");
        service->worker=std::thread([] { service->run(); });
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
        depth::register_callbacks();
#endif
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
#ifdef MINECOME_HUD_GAMEPLAY_CHAT
    depth::unregister_callbacks();
#endif
    reshade::unregister_event<reshade::addon_event::init_effect_runtime>(on_init);
    reshade::unregister_event<reshade::addon_event::destroy_effect_runtime>(on_destroy);
    reshade::unregister_event<reshade::addon_event::reshade_reloaded_effects>(on_reload);
    reshade::unregister_event<reshade::addon_event::reshade_begin_effects>(on_begin);
    reshade::unregister_event<reshade::addon_event::reshade_open_overlay>(on_overlay);
    if (service) service->shutdown();
    {
        std::lock_guard lock(runtimes_mutex);
        for (auto &[runtime,state] : runtimes) release(runtime,state,false);
#ifdef MINECOME_HUD_LIVE_MOUSE
        const auto session=service?service->session.load(std::memory_order_acquire):nullptr;
        drain_mouse_receipts(session?session->identity.run:std::string{});
#endif
        runtimes.clear(); delete service; service=nullptr;
    }
    receipt("addon","worker_joined_resources_released"); reshade::unregister_addon(addon,reshade_module);
}
BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) DisableThreadLibraryCalls(instance);
    return TRUE;
}
