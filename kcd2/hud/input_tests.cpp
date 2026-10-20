#include "input_channel.hpp"
#include "input_json.hpp"
#include "input_background_trial.hpp"
#include "input_diagnostics.hpp"
#include "input_offscreen_trial.hpp"
#include "input_pointer_fixture.hpp"
#include <bit>
#include <cstring>
#include <iostream>
#include <limits>
#include <sstream>
#include <thread>
namespace ui=minecome::hud::input;
namespace st=minecome::hud::stream;
namespace {
unsigned checks=0;
void check(bool value,const char *message) {++checks;if(!value)throw std::runtime_error(message);}
void put32(std::span<std::uint8_t> b,std::size_t o,std::uint32_t n){for(unsigned i=0;i<4;++i)b[o+i]=static_cast<std::uint8_t>(n>>(i*8));}
void put64(std::span<std::uint8_t> b,std::size_t o,std::uint64_t n){for(unsigned i=0;i<8;++i)b[o+i]=static_cast<std::uint8_t>(n>>(i*8));}
std::array<std::uint8_t,128> ack(std::uint64_t sequence,std::uint64_t utc,std::uint32_t state=1) {
    std::array<std::uint8_t,128> bytes{};put64(bytes,0,sequence);put64(bytes,8,utc);put32(bytes,16,state);return bytes;
}
void contract() {
    check(ui::fresh(750,1000)&&ui::fresh(1100,1000),"freshness boundaries");
    check(!ui::fresh(749,1000)&&!ui::fresh(1101,1000)&&!ui::fresh(0,0),"stale future or zero");
    for(auto key:{0x31u,0x32u,0x39u,0x45u,0x1bu})check(ui::valid_event({1000,ui::Kind::key_down,key},1000),"allowed key");
    for(auto key:{0u,0x30u,0x3au,0x46u,0x77u})check(!ui::valid_event({1000,ui::Kind::key_down,key},1000),"unknown key rejected");
    check(!ui::valid_event({1000,ui::Kind::key_down,0x31,.5f,0},1000),"key coordinates zero");
    for(auto bad:{-1.0f,1.1f,std::numeric_limits<float>::infinity(),std::numeric_limits<float>::quiet_NaN()})
        check(!ui::valid_event({1000,ui::Kind::move,0,bad,0},1000),"coordinate malformed");
    check(ui::valid_event({1000,ui::Kind::button_down,1,1,1},1000),"right button valid");
    check(!ui::valid_event({1000,ui::Kind::button_down,2,0,0},1000),"invalid button");
    check(ui::valid_event({1000,ui::Kind::wheel,0,.2f,.5f,-16},1000),"wheel valid");
    check(!ui::valid_event({1000,ui::Kind::wheel,0,.2f,.5f,0},1000),"wheel zero rejected");
    check(!ui::valid_event({1000,static_cast<ui::Kind>(7),0},1000),"event kind unknown");
    ui::Ack previous{},parsed;std::string reason;
    auto bytes=ack(0,1000);
    check(ui::decode_ack(bytes,0,1000,previous,parsed,reason),"initial ready");previous=parsed;
    check(ui::decode_ack(bytes,0,1100,previous,parsed,reason),"duplicate ack fresh");
    check(!ui::decode_ack(bytes,0,1251,previous,parsed,reason),"duplicate ack expires");
    check(ui::decode_ack(bytes,0,1251,previous,parsed,reason,false)&&!ui::fresh(parsed.utc,1251),"old waiting ACK parses without readiness");
    auto fresh_recovery=ack(0,1251);
    check(ui::decode_ack(fresh_recovery,0,1251,previous,parsed,reason,false)&&ui::fresh(parsed.utc,1251),"new real client tick restores readiness");
    auto zero_time=ack(0,0);
    check(!ui::decode_ack(zero_time,0,1000,previous,parsed,reason,false)&&reason=="ack_timestamp_zero","waiting zero time fatal");
    auto future_time=ack(0,1101);
    check(!ui::decode_ack(future_time,0,1000,previous,parsed,reason,false)&&reason=="ack_future","waiting future time fatal");
    auto regressed_time=ack(0,999);
    check(!ui::decode_ack(regressed_time,0,1000,previous,parsed,reason,false)&&reason=="ack_time_regressed","waiting time regression fatal");
    check(!ui::decode_ack(bytes,0,1251,previous,parsed,reason,true)&&reason=="ack_aged","armed old ACK remains fatal");
    auto future=ack(1,1000);check(!ui::decode_ack(future,0,1000,previous,parsed,reason),"ack past event head rejected");
    auto waiting=ack(0,0,0);check(!ui::decode_ack(waiting,0,1000,previous,parsed,reason),"ready cannot regress waiting");
    auto closed=ack(0,1000,2);check(ui::decode_ack(closed,0,1000,previous,parsed,reason),"closed ack");
    for(auto offset:{28u,127u}){auto reserved=bytes;reserved[offset]=1;check(!ui::decode_ack(reserved,0,1000,previous,parsed,reason),"reserved ack rejected");}
    ui::Mailbox mailbox;ui::Event event{1000,ui::Kind::key_down,0x31},out;
    check(!mailbox.pop(out),"empty mailbox");
    for(unsigned i=0;i<64;++i){event.code=i;check(mailbox.push(event),"bounded mailbox write");}
    check(!mailbox.push(event)&&mailbox.overflowed(),"mailbox overflow terminal marker");
    for(unsigned i=0;i<64;++i)check(mailbox.pop(out)&&out.code==i,"mailbox exact order");
    check(!mailbox.pop(out),"mailbox drained");
    ui::KeyboardGate gate;
    check(gate.update(true,true,0,100)==ui::KeyboardGate::Step::idle,"held F8 without neutral cannot arm");
    check(gate.update(true,false,0,101)==ui::KeyboardGate::Step::idle,"neutral baseline");
    check(gate.update(true,true,0,102)==ui::KeyboardGate::Step::starting,"fresh F8 arms");
    check(gate.update(true,false,0,103)==ui::KeyboardGate::Step::starting,"settle frame1");
    check(gate.update(true,false,0,104)==ui::KeyboardGate::Step::starting,"settle frame2");
    check(gate.update(true,false,1,105)==ui::KeyboardGate::Step::active,"later UI key accepted");
    check(gate.update(false,false,0,106)==ui::KeyboardGate::Step::closed,"focus or fresh gate closes");
    check(gate.close_reason()==ui::KeyboardGate::Close::ineligible,"ineligible close discriminated");
    check(gate.update(true,true,0,107)==ui::KeyboardGate::Step::closed,"no rearm");
    ui::KeyboardGate bounded;bounded.update(true,false,0,100);bounded.update(true,true,0,101);
    check(bounded.update(true,false,0,30101)==ui::KeyboardGate::Step::closed,"30second bound");
    check(bounded.close_reason()==ui::KeyboardGate::Close::expired,"activation expiry discriminated");
    ui::KeyboardGate early;early.update(true,false,0,100);early.update(true,true,0,101);
    check(early.update(true,false,1,102)==ui::KeyboardGate::Step::closed,"early keys during settling close");
    check(early.close_reason()==ui::KeyboardGate::Close::key_during_settle,"early key discriminated");
    ui::KeyboardGate again;again.update(true,false,0,100);again.update(true,true,0,101);again.update(true,false,0,102);
    check(again.update(true,true,0,103)==ui::KeyboardGate::Step::closed&&again.close_reason()==ui::KeyboardGate::Close::second_f8,"second F8 discriminated");
    // Regression for the successful live sequence: E/Esc and slot changes are
    // ordinary forwarded keys, not ownership-ending commands after settling.
    ui::KeyboardGate inventory;std::uint64_t elapsed=999;
    check(!inventory.activation_age(100,elapsed)&&elapsed==999,"unarmed activation age is unknown without mutation");
    inventory.update(true,false,0,100);inventory.update(true,true,0,101);
    inventory.update(true,false,0,102);inventory.update(true,false,0,103);
    for(const auto keys:{1u,0u,1u<<8,0u,1u<<9,0u,1u<<10,0u})
        check(inventory.update(true,false,keys,10474)==ui::KeyboardGate::Step::active,"slot E and Esc sequence keeps keyboard ownership");
    check(inventory.activation_age(10474,elapsed)&&elapsed==10373,"activation age is elapsed since F8 not latest event");
    check(!inventory.activation_age(100,elapsed),"regressed diagnostic clock remains unknown");
    check(inventory.update(false,false,0,10475)==ui::KeyboardGate::Step::closed&&inventory.close_reason()==ui::KeyboardGate::Close::ineligible,"only failed eligibility closes post-inventory gate");
    check(inventory.activation_age(10475,elapsed)&&elapsed==10374,"terminal diagnostic retains original activation time");
    ui::WindowSnapshot window;
    check(std::string_view(window.value(ui::WindowCheck::foreground))=="null","unobserved foreground is unknown not false");
    for(const auto bit:{ui::WindowCheck::runtime_handle,ui::WindowCheck::valid_handle,ui::WindowCheck::owned_process,ui::WindowCheck::not_minimized,ui::WindowCheck::visible})
        window.record(bit,true);
    window.record(ui::WindowCheck::foreground,false);
    check(window.checked==63&&window.failed==32,"foreground loss differs from valid owned visible host window");
    check(std::string_view(window.value(ui::WindowCheck::foreground))=="false"&&std::string_view(window.value(ui::WindowCheck::owned_process))=="true","different foreground keeps actual owned process evidence");
    ui::WindowSnapshot minimized;minimized.record(ui::WindowCheck::not_minimized,false);
    check(std::string_view(minimized.value(ui::WindowCheck::not_minimized))=="false"&&std::string_view(minimized.value(ui::WindowCheck::visible))=="null","short-circuit minimization does not fabricate later visibility");
    ui::FirstClose first;ui::CloseSnapshot snapshot,outcome;
    check(!first.read(outcome),"close latch initially empty");snapshot.cause=ui::CloseCause::runtime_lock_contention;snapshot.utc=123;
    check(first.publish(snapshot),"first close captured");snapshot.cause=ui::CloseCause::session_end;snapshot.utc=456;
    check(!first.publish(snapshot)&&first.read(outcome)&&outcome.utc==123&&outcome.cause==ui::CloseCause::runtime_lock_contention,"later close cannot obscure first cause");
    ui::FirstClose detailed; snapshot.window=window;snapshot.window.foreground_pid=42;snapshot.window.foreground_pid_sampled=true;
    snapshot.activation_age_valid=true;snapshot.activation_age_ms=10473;
    check(detailed.publish(snapshot),"detailed first-close context published");
    snapshot.window.foreground_pid=99;snapshot.window.failed=0;snapshot.activation_age_ms=30000;
    check(!detailed.publish(snapshot)&&detailed.read(outcome)&&outcome.window.failed==32&&outcome.window.foreground_pid==42&&outcome.window.foreground_pid_sampled&&outcome.activation_age_ms==10473,"later terminal evidence cannot overwrite first window or activation context");
    const auto j=ui::json::Parser("{\"value\":\"134999999999999999\",\"array\":[true,0.25],\"escaped\":\"C:\\\\x\"}").parse();
    check(j.at("value").integer()==134999999999999999ULL&&j.at("array").array[0].boolean()&&j.at("array").array[1].real()==.25f,"bounded JSON precise receipt");
    for(const auto text:{"{\"x\":1,\"x\":2}","{\"x\":01}","[1,]","{\"x\":NaN}","{} trailing","\"\\ud800\""}) {
        bool rejected=false;try{ui::json::Parser(text).parse();}catch(...){rejected=true;}check(rejected,"malformed JSON");
    }
    const std::string detail="missing \"field\" at C:\\receipt\n\t\r\x01";
    check(ui::json::Parser(ui::json::diagnostic_json(detail)).parse().text()==detail,"exception detail cannot escape receipt JSON");
    const std::string long_detail(4096,'x');
    check(ui::json::bounded_diagnostic(long_detail.c_str())==long_detail.substr(0,512),"exception capture is bounded to512 bytes");
    check(ui::json::Parser(ui::json::diagnostic_json(long_detail)).parse().text().size()==512,"exception serialization independently bounds detail");
    std::string all_bytes;for(unsigned i=0;i<256;++i)all_bytes+=static_cast<char>(i);
    check(ui::json::Parser(ui::json::diagnostic_json(all_bytes)).parse().type==ui::json::Value::Type::string,"control and locale bytes always produce valid receipt JSON");
    check(ui::json::bounded_diagnostic(nullptr).empty(),"absent exception detail is safe");
}
void background_receipts() {
    const st::Identity id{"0123456789abcdef0123456789abcdef",2,3,4,5,100000};
    const auto valid=ui::json::Parser(R"({"schema":1,"run":"0123456789abcdef0123456789abcdef","producer_pid":2,"target_pid":3,"producer_start_filetime":"4","target_start_filetime":"5","expires_utc_ms":100000,"ui_input_background_trial":true,"background_trial":{"completed":true,"phases":[{"name":"baseline","duration_ms":12000,"focused_ticks":0,"unfocused_ticks":200,"vsync":true,"max_fps":120},{"name":"trial","duration_ms":12020,"focused_ticks":0,"unfocused_ticks":230,"vsync":false,"max_fps":60}]}})").parse();
    check(ui::validate_background_trial(valid,id).phases[1].duration==12020,"actual background receipt accepted");
    for(unsigned bad=0;bad<8;++bad) {
        auto value=valid;
        auto &trial=value.object.at("background_trial");auto &phases=trial.object.at("phases").array;
        if(bad==0)value.object.at("producer_start_filetime").scalar="6";
        if(bad==1)value.object.at("ui_input_background_trial").scalar="false";
        if(bad==2)trial.object.at("completed").scalar="false";
        if(bad==3)phases[0].object.at("duration_ms").scalar="11999";
        if(bad==4)phases[1].object.at("focused_ticks").scalar="1";
        if(bad==5)phases[1].object.at("vsync").scalar="true";
        if(bad==6)phases[1].object.at("max_fps").scalar="120";
        if(bad==7)phases.pop_back();
        bool rejected=false;try{ui::validate_background_trial(value,id);}catch(...){rejected=true;}
        check(rejected,"wrong identity mode incomplete focus or settings rejected");
    }
}
void offscreen_receipts() {
    const st::Identity id{"0123456789abcdef0123456789abcdef",2,3,4,5,100000};
    const auto valid=ui::json::Parser(R"({"schema":1,"run":"0123456789abcdef0123456789abcdef","producer_pid":2,"target_pid":3,"producer_start_filetime":"4","target_start_filetime":"5","expires_utc_ms":100000,"ui_input_offscreen_trial":true,"ui_input_offscreen_presentation":true,"offscreen_trial":{"completed":true,"duration_ms":12000,"focused_ticks":0,"unfocused_ticks":240,"presentation_suppressed":true,"timing":{}},"result":"input_passed","lab_evidence":{"offscreen_trial_events":{"unfocused_events_applied":31,"focused_events_applied":0,"focus_interruptions":0}}})").parse();
    check(ui::validate_offscreen_trial(valid,id).duration==12000,"single actual unfocused offscreen phase accepted");
    ui::validate_offscreen_final(valid,id,31);check(true,"all31 actual unfocused events accepted");
    auto pointer=valid;pointer.object["ui_input_pointer_fixture"]=ui::json::Parser("true").parse();
    pointer.object.at("lab_evidence").object.at("offscreen_trial_events").object.at("unfocused_events_applied").scalar="43";
    ui::validate_offscreen_final(pointer,id,43,43);check(true,"all43 pointer events explicitly unfocused accepted");
    bool pointer_rejected=false;try{ui::validate_offscreen_final(pointer,id,31);}catch(...){pointer_rejected=true;}
    check(pointer_rejected,"pointer mode cannot pass baseline offscreen identity");
    pointer.object.at("ui_input_pointer_fixture").scalar="false";pointer_rejected=false;
    try{ui::validate_offscreen_final(pointer,id,43,43);}catch(...){pointer_rejected=true;}
    check(pointer_rejected,"pointer43 mode requires explicit final pointer flag");
    for(unsigned bad=0;bad<9;++bad) {
        auto value=valid;auto &phase=value.object.at("offscreen_trial");
        if(bad==0)value.object.at("target_start_filetime").scalar="6";
        if(bad==1)value.object.at("ui_input_offscreen_presentation").scalar="false";
        if(bad==2)value.object.at("ui_input_offscreen_trial").scalar="false";
        if(bad==3)phase.object.at("completed").scalar="false";
        if(bad==4)phase.object.at("duration_ms").scalar="11999";
        if(bad==5)phase.object.at("focused_ticks").scalar="1";
        if(bad==6)phase.object.at("unfocused_ticks").scalar="0";
        if(bad==7)phase.object.at("presentation_suppressed").scalar="false";
        if(bad==8)phase.object.at("timing").type=ui::json::Value::Type::null_;
        bool rejected=false;try{ui::validate_offscreen_trial(value,id);}catch(...){rejected=true;}
        check(rejected,"offscreen wrong identity mode focus duration or suppression rejected");
    }
    for(unsigned bad=0;bad<5;++bad) {
        auto value=valid;auto &events=value.object.at("lab_evidence").object.at("offscreen_trial_events");
        if(bad==0)events.object.at("focus_interruptions").scalar="1";
        if(bad==1)events.object.at("focused_events_applied").scalar="1";
        if(bad==2)events.object.at("unfocused_events_applied").scalar="30";
        if(bad==3)value.object.at("result").scalar="failed";
        bool rejected=false;try{ui::validate_offscreen_final(value,id,bad==4?30:31);}catch(...){rejected=true;}
        check(rejected,"offscreen focus interruption incomplete events or failed guest rejected");
    }
}
void pointer_receipts() {
    const st::Identity id{"0123456789abcdef0123456789abcdef",2,3,4,5,100000};
    const auto root=ui::json::Parser(R"({"schema":1,"run":"0123456789abcdef0123456789abcdef","producer_pid":2,"target_pid":3,"producer_start_filetime":"4","target_start_filetime":"5","expires_utc_ms":100000,"ui_input_protocol":1,"ui_input_fixture":true,"ui_input_pointer_fixture":true})").parse();
    ui::validate_pointer_identity(root,id);check(true,"pointer receipt exact immutable identity accepted");
    for(const auto key:{"run","producer_start_filetime","target_start_filetime","expires_utc_ms","ui_input_pointer_fixture"}) {
        auto bad=root;bad.object.at(key).scalar=std::string(key)=="ui_input_pointer_fixture"?"false":"99";
        bool rejected=false;try{ui::validate_pointer_identity(bad,id);}catch(...){rejected=true;}check(rejected,"foreign or wrong-mode pointer receipt rejected");
    }
    auto opened=ui::json::Parser(R"({"stage":"opened","applied_sequence":20,"server_confirmed":true,"server_observation_age_ms":20,"client_slots":[{"slot":0,"item":"minecraft:stone","count":64},{"slot":1,"item":"minecraft:dirt","count":32},{"slot":2,"item":"minecraft:cobblestone","count":16},{"slot":3,"item":"minecraft:oak_planks","count":8},{"slot":4,"item":"minecraft:stick","count":3},{"slot":5,"item":"minecraft:apple","count":2},{"slot":6,"item":"minecraft:torch","count":12},{"slot":7,"item":"minecraft:air","count":0},{"slot":8,"item":"minecraft:air","count":0}],"cursor":{"item":"minecraft:air","count":0},"inventory_open":true,"scroll_position":0,"initial_scroll_position":0,"grid_matches_initial":true,"grid_changed_verified":false,"held_buttons":0,"pending_releases":0,"active_button":-1,"cleanup_releases":0,"late_releases_consumed":0,"screen_generation":1,"mouse_drag_calls":0,"wheel_calls":0})").parse();
    opened.object["server_slots"]=opened.at("client_slots");
    check(ui::validate_pointer_phase(opened,0)==0,"opened actual slot state accepted");
    auto split=opened;split.object.at("stage").scalar="split";split.object.at("applied_sequence").scalar="23";
    split.object.at("client_slots").array[0].object.at("count").scalar="32";split.object["server_slots"]=split.at("client_slots");
    split.object.at("cursor").object.at("item").scalar="minecraft:stone";split.object.at("cursor").object.at("count").scalar="32";
    check(ui::validate_pointer_phase(split,1)==0,"right-click half stack and real cursor accepted");
    for(unsigned bad=0;bad<7;++bad) {
        auto value=split;
        if(bad==0)value.object.at("applied_sequence").scalar="22";
        if(bad==1)value.object.at("server_confirmed").scalar="false";
        if(bad==2)value.object.at("server_observation_age_ms").scalar="251";
        if(bad==3)value.object.at("server_slots").array[0].object.at("count").scalar="64";
        if(bad==4)value.object.at("client_slots").array[8].object.at("slot").scalar="7";
        if(bad==5)value.object.at("cursor").object.at("count").scalar="31";
        if(bad==6)value.object.at("active_button").scalar="1";
        bool rejected=false;try{ui::validate_pointer_phase(value,1);}catch(...){rejected=true;}check(rejected,"unconfirmed stale replayed or incorrect split rejected");
    }
    auto distributed=opened;distributed.object.at("stage").scalar="distributed";distributed.object.at("applied_sequence").scalar="32";
    auto &slots=distributed.object.at("client_slots").array;
    slots[0].object.at("item").scalar="minecraft:air";slots[0].object.at("count").scalar="0";
    for(unsigned slot:{7,8}){slots[slot].object.at("item").scalar="minecraft:stone";slots[slot].object.at("count").scalar="32";}
    distributed.object["server_slots"]=distributed.at("client_slots");distributed.object.at("mouse_drag_calls").scalar="2";
    check(ui::validate_pointer_phase(distributed,4)==0,"drag distribution requires two actual32 stacks and empty cursor");
    auto scrolled=distributed;scrolled.object.at("stage").scalar="scrolled";scrolled.object.at("applied_sequence").scalar="33";
    scrolled.object.at("scroll_position").scalar="0.125";scrolled.object.at("grid_matches_initial").scalar="false";
    scrolled.object.at("grid_changed_verified").scalar="true";scrolled.object.at("wheel_calls").scalar="1";
    check(ui::validate_pointer_phase(scrolled,5)==0,"wheel needs changed position and changed grid");
    for(unsigned bad=0;bad<3;++bad) {
        auto value=scrolled;if(bad==0)value.object.at("scroll_position").scalar="0";
        if(bad==1)value.object.at("grid_matches_initial").scalar="true";if(bad==2)value.object.at("grid_changed_verified").scalar="false";
        bool rejected=false;try{ui::validate_pointer_phase(value,5);}catch(...){rejected=true;}check(rejected,"wheel call alone never proves real inventory scrolling");
    }
    auto restored=scrolled;restored.object.at("stage").scalar="scroll_restored";restored.object.at("applied_sequence").scalar="34";
    restored.object.at("scroll_position").scalar="0";restored.object.at("grid_matches_initial").scalar="true";restored.object.at("wheel_calls").scalar="2";
    check(ui::validate_pointer_phase(restored,6)==0,"return scroll requires original grid and position");
    auto held=restored;held.object.at("stage").scalar="closed_held";held.object.at("applied_sequence").scalar="38";
    held.object.at("inventory_open").scalar="false";held.object.at("scroll_position")={};held.object.at("pending_releases").scalar="1";
    held.object.at("cleanup_releases").scalar="1";
    check(ui::validate_pointer_phase(held,7)==0,"held button released to closing screen but real up remains pending");
    auto omitted_null=held;omitted_null.object.erase("scroll_position");std::string missing_detail;
    try{ui::validate_pointer_phase(omitted_null,7);}catch(const std::exception &e){missing_detail=e.what();}
    check(missing_detail=="json_missing_field:scroll_position","closed phase still requires explicit null and names missing proof field");
    auto reopened=held;reopened.object.at("stage").scalar="reopened_held";reopened.object.at("applied_sequence").scalar="40";
    reopened.object.at("inventory_open").scalar="true";reopened.object["scroll_position"]=restored.at("scroll_position");reopened.object.at("screen_generation").scalar="2";
    check(ui::validate_pointer_phase(reopened,8)==0,"new real screen retains pending old physical release");
    auto late=reopened;late.object.at("stage").scalar="late_release";late.object.at("applied_sequence").scalar="41";
    late.object.at("pending_releases").scalar="0";late.object.at("late_releases_consumed").scalar="1";
    check(ui::validate_pointer_phase(late,9)==0,"late release consumed without second cleanup callback");
    for(const auto key:{"pending_releases","late_releases_consumed","cleanup_releases","screen_generation"}) {
        auto value=late;value.object.at(key).scalar="9";
        bool rejected=false;try{ui::validate_pointer_phase(value,9);}catch(...){rejected=true;}check(rejected,"late release bookkeeping mismatch rejected");
    }
    auto complete=late;complete.object.at("stage").scalar="complete";complete.object.at("applied_sequence").scalar="43";
    complete.object.at("inventory_open").scalar="false";complete.object.at("scroll_position")={};
    complete.object["completed"]=ui::json::Parser("true").parse();
    auto final=root;final.object["result"]=ui::json::Parser("\"input_passed\"").parse();
    final.object["lab_evidence"]=ui::json::Parser("{\"input_events_applied\":43,\"pointer_fixture\":true}").parse();final.object.at("lab_evidence").object["pointer_evidence"]=complete;
    ui::validate_pointer_final(final,id,43,0);check(true,"final43 events complete phase accepted");
    bool rejected=false;try{ui::validate_pointer_final(final,id,31,0);}catch(...){rejected=true;}check(rejected,"baseline31 cannot masquerade as pointer fixture");
    const auto points=ui::json::Parser(R"({"slots":[{"slot":0,"x":0.25,"y":0.8},{"slot":7,"x":0.7,"y":0.8},{"slot":8,"x":0.75,"y":0.8}],"drag_entry":{"x":0.69,"y":0.8},"scroll":{"x":0.5,"y":0.5},"blank":{"x":0.3,"y":0.3}})").parse();
    check(ui::pointer_targets(points).slots[2].first==0.75f,"targets use exact real slot identifiers");
    for(unsigned bad=0;bad<4;++bad) {
        auto value=points;if(bad==0)value.object.at("slots").array[2].object.at("slot").scalar="7";
        if(bad==1)value.object.at("slots").array[2].object.at("x").scalar="1.01";
        if(bad==2)value.object.at("blank").object.at("y").scalar="-0.01";
        if(bad==3)value.object.at("drag_entry").object.at("x").scalar="NaN";
        bool invalid=false;try{ui::pointer_targets(value);}catch(...){invalid=true;}check(invalid,"duplicate invalid or nonfinite pointer targets refused");
    }
}
ui::Identity identity(unsigned serial) {
    std::ostringstream run;run<<std::hex;run.width(16);run.fill('0');run<<GetCurrentProcessId();run.width(16);run<<st::steady_ms()+serial;
    return {run.str(),GetCurrentProcessId(),GetCurrentProcessId(),st::process_start(),st::process_start(),st::utc_ms()+10000};
}
struct Guest {
    st::Handle mapping,mutex;std::uint8_t *bytes=nullptr;
    explicit Guest(const ui::Identity &id) {
        const std::wstring token(id.run.begin(),id.run.end());mapping.reset(OpenFileMappingW(FILE_MAP_READ|FILE_MAP_WRITE,FALSE,(L"Local\\MineComeHudInput_"+token).c_str()));
        mutex.reset(OpenMutexW(SYNCHRONIZE|MUTEX_MODIFY_STATE,FALSE,(L"Local\\MineComeHudInputLock_"+token).c_str()));
        bytes=static_cast<std::uint8_t *>(MapViewOfFile(mapping.value,FILE_MAP_READ|FILE_MAP_WRITE,0,0,ui::mapping_bytes));check(mapping&&mutex&&bytes,"fixture guest open");
    }
    ~Guest(){if(bytes)UnmapViewOfFile(bytes);}
    void write(std::uint64_t sequence,std::uint32_t state=1) {
        auto header=ack(sequence,st::utc_ms(),state);check(WaitForSingleObject(mutex.value,5)==WAIT_OBJECT_0,"guest lock");
        std::memcpy(bytes+128,header.data(),128);check(ReleaseMutex(mutex.value)!=FALSE,"guest unlock");
    }
};
void channels() {
    auto id=identity(1);ui::Writer writer;check(writer.create(id),"writer new objects");Guest guest(id);
    check(!writer.ready()&&writer.poll(),"initial waiting permitted");guest.write(0);check(writer.poll()&&writer.ready(),"client ready acknowledged");
    ui::Writer collision;check(!collision.create(id),"existing mapping refused");
    check(writer.arm()&&writer.status().state==1,"one arm");check(!writer.arm(),"cannot rearm");
    ui::Event e{st::utc_ms(),ui::Kind::key_down,0x31};check(writer.append(std::span<const ui::Event>(&e,1)),"event published");
    check(writer.status().sequence==1&&guest.bytes[256]==1&&guest.bytes[128]==0,"host preserves guest-owned ack");
    guest.write(1);check(writer.poll()&&writer.status().ack.sequence==1,"client event ack");
    writer.finish("test_complete");check(guest.bytes[96]==2,"closed publication");guest.write(1,2);check(writer.poll()&&writer.status().ack.state==2,"guest close ack read");
    check(!writer.create(id),"cannot reopen");
    auto overflow_id=identity(2);ui::Writer full;check(full.create(overflow_id),"overflow fixture");Guest stalled(overflow_id);stalled.write(0);full.poll();full.arm();
    std::array<ui::Event,64> events;events.fill({st::utc_ms(),ui::Kind::key_down,0x31});check(full.append(events),"ring fills without overwrite");
    e.captured=st::utc_ms();check(!full.append(std::span<const ui::Event>(&e,1))&&full.status().state==2&&full.reason()=="ring_overflow","unacked overwrite closes");
    auto bad_id=identity(3);ui::Writer bad;check(bad.create(bad_id),"tamper fixture");Guest tamper(bad_id);tamper.write(0);bad.poll();
    WaitForSingleObject(tamper.mutex.value,5);tamper.bytes[16]^=1;ReleaseMutex(tamper.mutex.value);
    check(!bad.poll()&&bad.status().state==2&&bad.reason()=="host_bytes_changed","foreign header closes");
    auto abandoned_id=identity(4);ui::Writer abandoned;check(abandoned.create(abandoned_id),"abandoned fixture");Guest abandon(abandoned_id);
    std::thread quitter([&]{WaitForSingleObject(abandon.mutex.value,INFINITE);});quitter.join();
    check(!abandoned.poll()&&abandoned.reason()=="mutex_abandoned","abandon closes");
    auto stale_id=identity(5);ui::Writer stale;check(stale.create(stale_id),"stale fixture");Guest lag(stale_id);lag.write(0);stale.poll();stale.arm();
    WaitForSingleObject(lag.mutex.value,5);auto old=ack(0,st::utc_ms()-251);std::memcpy(lag.bytes+128,old.data(),128);ReleaseMutex(lag.mutex.value);
    check(!stale.poll()&&stale.status().state==2&&stale.reason()=="ack_time_regressed","regressed tick closes");
    auto recovery_id=identity(6);ui::Writer recovery;check(recovery.create(recovery_id),"waiting recovery fixture");Guest recovery_peer(recovery_id);
    recovery_peer.write(0);check(recovery.poll()&&recovery.ready(),"waiting real initial ACK");
    Sleep(270);check(recovery.poll()&&!recovery.ready()&&recovery.status().state==0,"waiting old ACK suspends readiness only");
    check(!recovery.arm()&&recovery.status().state==0,"cannot arm on stale waiting ACK");
    check(recovery.status().max_prearm_ack_age_ms>250&&recovery.status().prearm_stale_observations>0,"waiting diagnostic records actual age");
    recovery_peer.write(0);check(recovery.poll()&&recovery.ready()&&recovery.status().prearm_recoveries==1,"real fresh ACK recovers waiting session");
    check(recovery.arm(),"arm after real recovery");Sleep(270);
    check(!recovery.poll()&&recovery.status().state==2&&recovery.reason()=="ack_aged","active ACK lapse remains terminal");
    check(recovery.status().rejected_host_state==1&&recovery.status().rejected_at_utc_ms-recovery.status().rejected_ack_utc_ms>250,"rejection records exact active ACK age");
    recovery_peer.write(0);recovery.poll();check(!recovery.ready()&&!recovery.arm(),"fresh ACK never rearms closed ownership");
    Sleep(270);check(recovery.poll()&&recovery.status().state==2,"closed rendezvous may await delayed ACK without ownership");
    recovery_peer.write(0,2);check(recovery.poll()&&recovery.status().ack.state==2,"delayed real closed acknowledgement observed");
    auto movement_id=identity(7);ui::Writer movement;check(movement.create(movement_id,ui::Profile::movement),"explicit movement writer");
    Guest movement_peer(movement_id);movement_peer.write(0);check(movement.poll()&&movement.arm(),"movement guest readiness arms");
    check(!std::memcmp(movement_peer.bytes,"MCHUDI02",8)&&movement_peer.bytes[8]==2,"actual movement mapping explicit v2");
    ui::Event forward{st::utc_ms(),ui::Kind::key_down,0x57};
    check(movement.append(std::span<const ui::Event>(&forward,1))&&movement.status().sequence==1,"actual v2 movement down published");
    movement_peer.write(1);movement.poll();forward.kind=ui::Kind::key_up;forward.captured=st::utc_ms();
    check(movement.append(std::span<const ui::Event>(&forward,1))&&movement.status().sequence==2,"actual v2 movement up published");
    movement.finish("test_complete");movement_peer.write(2,2);check(movement.poll()&&movement.status().ack.state==2,"movement closed acknowledgement");
    auto legacy_id=identity(8);ui::Writer legacy;check(legacy.create(legacy_id),"v1 regression writer");
    Guest legacy_peer(legacy_id);legacy_peer.write(0);legacy.poll();legacy.arm();
    forward.captured=st::utc_ms();
    check(!legacy.append(std::span<const ui::Event>(&forward,1))&&legacy.reason()=="invalid_or_stale_event","v1 writer rejects movement even on valid fresh session");
    ui::Writer invalid;check(!invalid.create(identity(9),static_cast<ui::Profile>(3))&&invalid.reason()=="input_profile","unsupported writer profile refused");
}
}
int main() {try{contract();background_receipts();offscreen_receipts();pointer_receipts();channels();std::cout<<"HUD_INPUT_TESTS checks="<<checks<<" PASS\n";return 0;}catch(const std::exception&e){std::cerr<<"HUD_INPUT_TESTS FAIL "<<checks<<" "<<e.what()<<'\n';return 1;}}
