// Original standalone reverse-input fixture; never calls KCD or injects OS input.
#include "input_channel.hpp"
#include "input_json.hpp"
#include "input_background_trial.hpp"
#include "input_offscreen_trial.hpp"
#include <filesystem>
#include <iostream>
#include <set>
#include <sstream>

namespace ui=minecome::hud::input;
namespace st=minecome::hud::stream;
namespace {
void save(const std::wstring &path,const std::string &text) {
    st::Handle file(CreateFileW(path.c_str(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL|FILE_FLAG_OPEN_REPARSE_POINT,nullptr));
    DWORD written=0;
    if(!file||!WriteFile(file.value,text.data(),static_cast<DWORD>(text.size()),&written,nullptr)||written!=text.size()||!FlushFileBuffers(file.value))throw std::runtime_error("receipt_create_failed");
}
ui::json::Value read(const std::wstring &path,HANDLE stop) {
    std::vector<std::uint8_t> bytes;
    if(!st::read_file(path,65536,stop,&bytes,nullptr))throw std::runtime_error("receipt_read_failed");
    return ui::json::Parser(std::string_view(reinterpret_cast<const char *>(bytes.data()),bytes.size())).parse();
}
bool exists(const std::wstring &path) {const DWORD attrs=GetFileAttributesW(path.c_str());return attrs!=INVALID_FILE_ATTRIBUTES&&!(attrs&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT));}
}
int wmain(int argc,wchar_t **argv) {
    std::wstring output;std::string run;std::uint64_t sent=0,image_frames=0,delay_ms=0,max_ack_age=0,stale_observations=0,recoveries=0,close_wait_ms=0;
    bool opened=false,closed=false,guest_closed=false,passed=false,background=false,background_completed=false;
    bool offscreen=false,offscreen_completed=false,unfocused_events_verified=false;
    ui::BackgroundTrial background_summary;
    ui::OffscreenTrial offscreen_summary;
    std::uint64_t longest_fresh_pair_ms=0;
    std::set<std::uint32_t> selected;std::string reason="fixture_exception";
    try {
        std::map<std::wstring,std::wstring> args;
        for(int i=1;i<argc;i+=2)if(i+1>=argc||!args.emplace(argv[i],argv[i+1]).second)throw std::runtime_error("arguments");
        for(const auto &[key,value]:args){(void)value;if(key!=L"--run"&&key!=L"--expires"&&key!=L"--ready-output"&&key!=L"--guest-ready"&&key!=L"--output"&&key!=L"--prearm-delay-ms"&&key!=L"--background-trial"&&key!=L"--offscreen-trial")throw std::runtime_error("arguments");}
        if(args.size()<5||args.size()>8)throw std::runtime_error("arguments");
        if(args.contains(L"--background-trial")) {
            if(args.at(L"--background-trial")!=L"1")throw std::runtime_error("background_trial_argument");
            background=true;
        }
        if(args.contains(L"--offscreen-trial")) {
            if(args.at(L"--offscreen-trial")!=L"1")throw std::runtime_error("offscreen_trial_argument");
            offscreen=true;
        }
        if(args.contains(L"--prearm-delay-ms")) {
            std::string value;for(auto c:args.at(L"--prearm-delay-ms")){if(c<L'0'||c>L'9')throw std::runtime_error("prearm_delay");value+=static_cast<char>(c);}
            const auto delay=std::from_chars(value.data(),value.data()+value.size(),delay_ms);
            if(delay.ec!=std::errc{}||delay.ptr!=value.data()+value.size()||delay_ms>5000)throw std::runtime_error("prearm_delay");
        }
        if((background&&delay_ms)||(offscreen&&(background||delay_ms)))throw std::runtime_error("fixture_modes_conflict");
        output=args.at(L"--output");for(auto c:args.at(L"--run")){if(c>127)throw std::runtime_error("run");run+=static_cast<char>(c);}
        std::string expiry;for(auto c:args.at(L"--expires")){if(c<L'0'||c>L'9')throw std::runtime_error("expiry");expiry+=static_cast<char>(c);}
        std::uint64_t expires=0;const auto parsed=std::from_chars(expiry.data(),expiry.data()+expiry.size(),expires);
        if(parsed.ec!=std::errc{}||parsed.ptr!=expiry.data()+expiry.size())throw std::runtime_error("expiry");
        const auto now=st::utc_ms(),begun=st::steady_ms();
        st::Identity id{run,1,GetCurrentProcessId(),1,st::process_start(),expires};
        if(!st::valid_identity(id)||expires<=now||expires-now>st::max_lease_ms)throw std::runtime_error("identity_expiry");
        const auto deadline=begun+(expires-now);
        st::Handle stop(CreateEventW(nullptr,TRUE,FALSE,nullptr));if(!stop)throw std::runtime_error("event");
        std::ostringstream ready;
        ready << "{\"schema\":1,\"kind\":\"minecome_hud_input_fixture_ready_v1\",\"run\":\"" << run
              << "\",\"host_pid\":" << id.target_pid << ",\"host_start_filetime\":\"" << id.target_start
              << "\",\"expires_utc_ms\":" << expires << ",\"physical_host_input\":false,\"kcd_compositing_verified\":false}\n";
        save(args.at(L"--ready-output"),ready.str());
        auto alive=[&] {return st::utc_ms()<expires&&st::steady_ms()>=begun&&st::steady_ms()<deadline;};
        while(!exists(args.at(L"--guest-ready"))) {if(!alive())throw std::runtime_error("guest_ready_timeout");Sleep(10);}
        const auto guest=read(args.at(L"--guest-ready"),stop.value);
        if(guest.at("schema").integer()!=1||guest.at("run").text()!=run||guest.at("target_pid").integer()!=id.target_pid||
            guest.at("target_start_filetime").integer()!=id.target_start||guest.at("expires_utc_ms").integer()!=expires||
            guest.at("ui_input_protocol").integer()!=1||!guest.at("ui_input_fixture").boolean()||
            guest.at("ui_input_delay_fixture").boolean()!=(delay_ms>0)||
            guest.at("ui_input_background_trial").boolean()!=background||
            guest.at("ui_input_offscreen_trial").boolean()!=offscreen||
            guest.at("ui_input_offscreen_presentation").boolean()!=offscreen)throw std::runtime_error("guest_ready_identity");
        const auto producer_pid=guest.at("producer_pid").integer();if(!producer_pid||producer_pid>0xffffffffULL)throw std::runtime_error("guest_pid");
        id.producer_pid=static_cast<std::uint32_t>(producer_pid);id.producer_start=guest.at("producer_start_filetime").integer();
        st::Handle producer(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|SYNCHRONIZE,FALSE,id.producer_pid));
        if(!producer||st::process_start(producer.value)!=id.producer_start)throw std::runtime_error("guest_process_identity");
        ui::Writer writer;if(!writer.create(id))throw std::runtime_error(writer.reason());
        st::Channel images;if(!images.open(id))throw std::runtime_error("paired_image_channel_failed");
        std::uint64_t image_capture=0;
        auto pump=[&] {
            if(!alive())throw std::runtime_error("fixture_expired");
            if(!writer.poll()||(!writer.status().live&&writer.status().state!=2))throw std::runtime_error(writer.reason());
            std::shared_ptr<const st::Frame> frame;
            const auto received=images.poll(frame);
            if(received==st::Poll::failed||received==st::Poll::closed)throw std::runtime_error("paired_image_closed");
            if(frame){image_capture=frame->header.capture_utc_ms;++image_frames;}
        };
        // Like the live addon, require both a real fresh image and client-tick
        // readiness before ownership. A ready file alone is not rendered UI.
        while(!writer.ready()||!images.fresh()||!ui::fresh(image_capture,st::utc_ms())) {
            pump();if(writer.status().state==2)throw std::runtime_error(writer.reason());Sleep(5);
        }
        if(delay_ms) {
            const auto delay_started=st::steady_ms();
            while(st::steady_ms()-delay_started<delay_ms) {
                pump();if(writer.status().state==2)throw std::runtime_error(writer.reason());Sleep(5);
            }
            while(!writer.ready()||!images.fresh()||!ui::fresh(image_capture,st::utc_ms())) {
                pump();if(writer.status().state==2)throw std::runtime_error(writer.reason());Sleep(5);
            }
        }
        if(background||offscreen) {
            const auto trial_path=(std::filesystem::path(args.at(L"--guest-ready")).parent_path()/
                (offscreen?L"offscreen-trial-ready.json":L"background-trial-ready.json")).wstring();
            std::uint64_t fresh_since=0,last_poll=0;
            while(!exists(trial_path)) {
                pump();if(writer.status().state==2)throw std::runtime_error(writer.reason());
                const auto observed=st::steady_ms();
                if(writer.ready()&&images.fresh()&&ui::fresh(image_capture,st::utc_ms())) {
                    if(!fresh_since||observed<last_poll||observed-last_poll>ui::fresh_ms)fresh_since=observed;
                    longest_fresh_pair_ms=std::max(longest_fresh_pair_ms,observed-fresh_since);
                } else fresh_since=0;
                last_poll=observed;Sleep(5);
            }
            const auto trial=read(trial_path,stop.value);
            if(offscreen) {offscreen_summary=ui::validate_offscreen_trial(trial,id);offscreen_completed=true;}
            else {background_summary=ui::validate_background_trial(trial,id);background_completed=true;}
            // The trial receipt is evidence, never a substitute for current
            // real image/client-tick readiness before taking UI ownership.
            while(!writer.ready()||!images.fresh()||!ui::fresh(image_capture,st::utc_ms())) {
                pump();if(writer.status().state==2)throw std::runtime_error(writer.reason());Sleep(5);
            }
        }
        max_ack_age=writer.status().max_prearm_ack_age_ms;stale_observations=writer.status().prearm_stale_observations;recoveries=writer.status().prearm_recoveries;
        if(delay_ms&&(max_ack_age<=ui::fresh_ms||!stale_observations||!recoveries))throw std::runtime_error("waiting_recovery_not_observed");
        if(!writer.arm())throw std::runtime_error("arm_failed");
        auto emit=[&](ui::Kind kind,std::uint32_t code,float x=0,float y=0) {
            ui::Event event{st::utc_ms(),kind,code,x,y,0};
            while(!writer.append(std::span<const ui::Event>(&event,1))) {
                if(!writer.status().live)throw std::runtime_error(writer.reason());pump();Sleep(2);
            }
            sent=writer.status().sequence;
            const auto wait_started=st::steady_ms();
            while(writer.status().ack.sequence<sent) {
                pump();if(writer.status().state==2||st::steady_ms()-wait_started>2000)throw std::runtime_error("event_ack_timeout");Sleep(2);
            }
        };
        for(std::uint32_t key=0x31;key<=0x39;++key) {
            emit(ui::Kind::key_down,key);
            if(writer.status().ack.selected!=key-0x31)throw std::runtime_error("selected_slot_ack");
            selected.insert(writer.status().ack.selected);emit(ui::Kind::key_up,key);
        }
        emit(ui::Kind::key_down,0x45);emit(ui::Kind::key_up,0x45);
        if(writer.status().ack.screen!=1)throw std::runtime_error("inventory_open_ack");opened=true;
        const auto targets_path=(std::filesystem::path(args.at(L"--guest-ready")).parent_path()/L"fixture-targets.json").wstring();
        while(!exists(targets_path)){pump();if(writer.status().state==2)throw std::runtime_error(writer.reason());Sleep(5);}
        const auto targets=read(targets_path,stop.value);
        if(targets.at("schema").integer()!=1||targets.at("run").text()!=run||targets.at("target_pid").integer()!=id.target_pid||
            targets.at("producer_pid").integer()!=id.producer_pid)throw std::runtime_error("target_receipt_identity");
        const auto &slots=targets.at("slots");if(slots.type!=ui::json::Value::Type::array||slots.array.size()!=2)throw std::runtime_error("target_slots");
        std::array<std::pair<float,float>,2> points{};std::array<bool,2> seen{};
        for(const auto &slot:slots.array) {
            const auto index=slot.at("slot").integer();if(index>1||seen[index])throw std::runtime_error("target_slot_index");seen[index]=true;
            const auto x=slot.at("x").real(),y=slot.at("y").real();if(x<0||x>1||y<0||y>1)throw std::runtime_error("target_coordinates");points[index]={x,y};
        }
        for(const auto index:{0,1,0}) {
            const auto [x,y]=points[index];emit(ui::Kind::move,0,x,y);emit(ui::Kind::button_down,0,x,y);emit(ui::Kind::button_up,0,x,y);
        }
        emit(ui::Kind::key_down,0x1b);emit(ui::Kind::key_up,0x1b);
        if(writer.status().ack.screen!=0)throw std::runtime_error("inventory_close_ack");closed=true;
        writer.finish("fixture_complete");
        const auto close_started=st::steady_ms();
        while(writer.status().ack.state!=2) {
            if(!alive()||st::steady_ms()-close_started>=1500||WaitForSingleObject(producer.value,0)!=WAIT_TIMEOUT)throw std::runtime_error("guest_close_ack_missing");
            writer.poll();Sleep(5);
        }
        close_wait_ms=st::steady_ms()-close_started;
        if(delay_ms&&close_wait_ms<400)throw std::runtime_error("closed_ack_delay_not_observed");
        guest_closed=true;passed=writer.status().ack.sequence==sent&&selected.size()==9;reason=passed?"guest_closed_all_events_acked":"ack_incomplete";
        // The image receiver remains bound to this exact target process. Keep it
        // alive until Minecraft exits naturally and allow its final close read.
        while(WaitForSingleObject(producer.value,0)==WAIT_TIMEOUT&&alive())Sleep(20);
        if(WaitForSingleObject(producer.value,0)==WAIT_TIMEOUT){passed=false;reason="guest_exit_timeout";}
        if(offscreen&&passed) {
            const auto final_path=(std::filesystem::path(args.at(L"--guest-ready")).parent_path()/L"stream-result.json").wstring();
            ui::validate_offscreen_final(read(final_path,stop.value),id,sent);unfocused_events_verified=true;
        }
        Sleep(2000);
    } catch(const std::exception &e) {passed=false;reason=e.what();}
    catch(...) {passed=false;reason="unknown_fixture_failure";}
    try {
        if(output.empty())return 2;
        // Reasons originate only from our fixed internal literals.
        if(reason.find_first_not_of("abcdefghijklmnopqrstuvwxyz_0123456789")!=std::string::npos)reason="fixture_exception";
        std::ostringstream result;
        result << "{\"schema\":1,\"kind\":\"minecome_hud_input_fixture_result_v1\",\"run\":\"" << run << "\",\"result\":\"" << (passed?"passed":"failed")
               << "\",\"reason\":\"" << reason << "\",\"events_sent\":" << sent << ",\"all_events_acknowledged\":" << (passed?"true":"false")
               << ",\"selected_slots_seen\":" << selected.size() << ",\"inventory_opened\":" << (opened?"true":"false")
               << ",\"inventory_closed\":" << (closed?"true":"false") << ",\"guest_closed_seen\":" << (guest_closed?"true":"false")
               << ",\"genuine_image_frames_received\":" << image_frames
               << ",\"prearm_delay_fixture\":" << (delay_ms?"true":"false") << ",\"max_prearm_ack_age_ms\":" << max_ack_age
               << ",\"prearm_stale_observations\":" << stale_observations << ",\"prearm_recoveries\":" << recoveries
               << ",\"closed_ack_wait_ms\":" << close_wait_ms
               << ",\"background_trial\":" << (background?"true":"false")
               << ",\"background_trial_completed\":" << (background_completed?"true":"false")
               << ",\"background_trial_receipt\":" << (background?"\"capture/background-trial-ready.json\"":"null")
               << ",\"offscreen_trial\":" << (offscreen?"true":"false")
               << ",\"offscreen_trial_completed\":" << (offscreen_completed?"true":"false")
               << ",\"offscreen_trial_receipt\":" << (offscreen?"\"capture/offscreen-trial-ready.json\"":"null")
               << ",\"unfocused_events_verified\":" << (unfocused_events_verified?"true":"false")
               << ",\"longest_observed_fresh_pair_ms\":" << longest_fresh_pair_ms;
        if(offscreen_completed) {
            result << ",\"offscreen_trial_summary\":{\"duration_ms\":" << offscreen_summary.duration
                   << ",\"focused_ticks\":0,\"unfocused_ticks\":" << offscreen_summary.unfocused_ticks
                   << ",\"presentation_suppressed\":true}";
        }
        if(background_completed) {
            result << ",\"background_trial_summary\":[";
            for(unsigned i=0;i<2;++i) {
                const auto &phase=background_summary.phases[i];
                if(i)result << ',';
                result << "{\"name\":\"" << (i?"trial":"baseline") << "\",\"duration_ms\":" << phase.duration
                       << ",\"focused_ticks\":0,\"unfocused_ticks\":" << phase.unfocused_ticks
                       << ",\"vsync\":" << (phase.vsync?"true":"false") << ",\"max_fps\":" << phase.max_fps << '}';
            }
            result << ']';
        }
        result
               << ",\"physical_host_input\":false,\"kcd_compositing_verified\":false}\n";
        save(output,result.str());std::cout << "HUD_INPUT_FIXTURE result=" << (passed?"passed":"failed") << " reason=" << reason << " events=" << sent << '\n';
    } catch(...) {return 3;}
    return passed?0:1;
}
