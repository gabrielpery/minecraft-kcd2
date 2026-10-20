// SPDX-License-Identifier: GPL-3.0-or-later
// Official development-build integration: fixed localhost HTTP console calls,
// original Lua diagnostics, shared log reads and MineCome's normal transport.
#include <minecome/bridge.hpp>
#include <minecome/tools_pose.hpp>
#include <minecome/stone_mirror.hpp>
#include <Windows.h>
#include <tlhelp32.h>
#include <winhttp.h>

#include <chrono>
#include <algorithm>
#include <cmath>
#include <deque>
#include <functional>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>

namespace {
using Clock=std::chrono::steady_clock;
using namespace std::chrono_literals;
struct HttpHandle {
    HINTERNET value{};
    explicit HttpHandle(HINTERNET handle):value(handle) {if(!value) throw std::runtime_error("WinHTTP handle creation failed");}
    ~HttpHandle() {WinHttpCloseHandle(value);}
    HttpHandle(const HttpHandle&)=delete;
};
std::wstring url_escape(const std::string& value) {
    constexpr wchar_t hex[]=L"0123456789ABCDEF";
    std::wstring result;
    for(unsigned char c:value) {
        if((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='-'||c=='_'||c=='.'||c=='~') result.push_back(c);
        else {result.push_back(L'%');result.push_back(hex[c>>4]);result.push_back(hex[c&15]);}
    }
    return result;
}
class ToolsHttp {
    HttpHandle session_{WinHttpOpen(L"MineCome/0.1.0",WINHTTP_ACCESS_TYPE_NO_PROXY,WINHTTP_NO_PROXY_NAME,WINHTTP_NO_PROXY_BYPASS,0)};
    HttpHandle connection_;
public:
    explicit ToolsHttp(INTERNET_PORT port):connection_(WinHttpConnect(session_.value,L"127.0.0.1",port,0)) {
        WinHttpSetTimeouts(session_.value,1000,1000,1000,1000);
    }
    std::string get(const std::wstring& path) {
        const auto body_deadline=Clock::now()+2s;
        HttpHandle request(WinHttpOpenRequest(connection_.value,L"GET",path.c_str(),nullptr,WINHTTP_NO_REFERER,WINHTTP_DEFAULT_ACCEPT_TYPES,0));
        DWORD redirect=WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
        WinHttpSetOption(request.value,WINHTTP_OPTION_REDIRECT_POLICY,&redirect,sizeof(redirect));
        if(!WinHttpSendRequest(request.value,WINHTTP_NO_ADDITIONAL_HEADERS,0,WINHTTP_NO_REQUEST_DATA,0,0,0)||!WinHttpReceiveResponse(request.value,nullptr))
            throw std::runtime_error("official tools HTTP request failed; is the development game running?");
        DWORD status=0,size=sizeof(status);
        if(!WinHttpQueryHeaders(request.value,WINHTTP_QUERY_STATUS_CODE|WINHTTP_QUERY_FLAG_NUMBER,WINHTTP_HEADER_NAME_BY_INDEX,&status,&size,WINHTTP_NO_HEADER_INDEX)||status!=200)
            throw std::runtime_error("official tools HTTP returned non-200 status");
        std::string response;
        for(;;) {
            const auto remaining=std::chrono::duration_cast<std::chrono::milliseconds>(body_deadline-Clock::now()).count();
            if(remaining<=0) throw std::runtime_error("HTTP absolute response deadline exceeded");
            const auto timeout=static_cast<int>(std::min<std::int64_t>(remaining,1000));
            WinHttpSetTimeouts(request.value,timeout,timeout,timeout,timeout);
            DWORD available=0;
            if(!WinHttpQueryDataAvailable(request.value,&available)) throw std::runtime_error("HTTP body query failed");
            if(!available) break;
            if(response.size()+available>1024*1024) throw std::runtime_error("HTTP response exceeded bounded diagnostic size");
            const auto previous=response.size();response.resize(previous+available);
            DWORD received=0;if(!WinHttpReadData(request.value,response.data()+previous,available,&received)) throw std::runtime_error("HTTP body read failed");
            response.resize(previous+received);
            if(Clock::now()>=body_deadline) throw std::runtime_error("HTTP absolute response deadline exceeded");
        }
        return response;
    }
    void command(const std::string& value) {
        (void)get(L"/api/System/Console/ExecuteString?command="+url_escape(value));
    }
};
std::string new_log_bytes(const std::filesystem::path& path,std::uint64_t& offset) {
    const auto file=CreateFileW(path.c_str(),GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(file==INVALID_HANDLE_VALUE) return {};
    struct Close {HANDLE file;~Close(){CloseHandle(file);}} close{file};
    LARGE_INTEGER size{};if(!GetFileSizeEx(file,&size)||size.QuadPart<0) return {};
    const auto length=static_cast<std::uint64_t>(size.QuadPart);
    if(length<offset) offset=0;
    if(length-offset>1024*1024) offset=length-1024*1024;
    LARGE_INTEGER position{};position.QuadPart=static_cast<LONGLONG>(offset);
    if(!SetFilePointerEx(file,position,nullptr,FILE_BEGIN)) return {};
    std::string result(static_cast<std::size_t>(length-offset),'\0');
    DWORD received=0;
    if(!result.empty()&&!ReadFile(file,result.data(),static_cast<DWORD>(result.size()),&received,nullptr)) return {};
    result.resize(received);offset+=received;return result;
}
unsigned bounded_integer(const std::wstring& text,unsigned maximum) {
    std::size_t used=0;const auto value=std::stoul(text,&used);
    if(used!=text.size()||value<1||value>maximum) throw std::runtime_error("invalid numeric argument");
    return static_cast<unsigned>(value);
}
// No engine pointer/offset access. Still require the tested development
// executable/distribution before enabling console mutations in a real game.
void require_supported_tools_process(const std::filesystem::path& game_log) {
    const auto executable=std::filesystem::weakly_canonical(game_log.parent_path()/L"Bin/Win64ReleaseSteamLTO_DLL/KingdomCome.exe");
    DWORD ignored=0;const auto length=GetFileVersionInfoSizeW(executable.c_str(),&ignored);
    if(!length) throw std::runtime_error("stone mirroring requires the official development executable beside the game log");
    std::vector<std::uint8_t> version(length);
    if(!GetFileVersionInfoW(executable.c_str(),0,length,version.data())) throw std::runtime_error("could not verify development executable version");
    VS_FIXEDFILEINFO* info=nullptr;UINT info_size=0;
    if(!VerQueryValueW(version.data(),L"\\",reinterpret_cast<void**>(&info),&info_size)||info_size<sizeof(*info)
        ||info->dwSignature!=0xfeef04bd||info->dwFileVersionMS!=(1U<<16)||info->dwFileVersionLS!=0)
        throw std::runtime_error("unexpected fixed version metadata in official development executable");
    // This installed development EXE has fixed 1.0.0.0 metadata; the actual
    // game build is in its translated FileVersion/ProductVersion strings.
    struct Translation {WORD language,codepage;};
    Translation* translations=nullptr;UINT translation_size=0;bool version_matches=false;
    if(VerQueryValueW(version.data(),L"\\VarFileInfo\\Translation",reinterpret_cast<void**>(&translations),&translation_size)) {
        for(UINT i=0;i<translation_size/sizeof(Translation);++i) {
            auto expected=[&](const wchar_t* key) {
                wchar_t query[128];swprintf_s(query,L"\\StringFileInfo\\%04x%04x\\%s",translations[i].language,translations[i].codepage,key);
                wchar_t* text=nullptr;UINT count=0;
                return VerQueryValueW(version.data(),query,reinterpret_cast<void**>(&text),&count)
                    &&text&&count==8&&std::wstring_view(text,count-1)==L"1.5.5.0";
            };
            if(expected(L"FileVersion")&&expected(L"ProductVersion")) {version_matches=true;break;}
        }
    }
    if(!version_matches)
        throw std::runtime_error("stone mirroring requires the tested official 1.5.5.0 development executable");
    const auto snapshot=CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0);
    if(snapshot==INVALID_HANDLE_VALUE) throw std::runtime_error("could not verify the running development process");
    struct Close {HANDLE value;~Close(){CloseHandle(value);}} close{snapshot};
    PROCESSENTRY32W entry{};entry.dwSize=sizeof(entry);
    for(bool found=Process32FirstW(snapshot,&entry);found;found=Process32NextW(snapshot,&entry)) {
        if(CompareStringOrdinal(entry.szExeFile,-1,L"KingdomCome.exe",-1,TRUE)!=CSTR_EQUAL) continue;
        const auto process=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,entry.th32ProcessID);
        if(!process) continue;
        wchar_t path[32768];DWORD count=32768;const bool queried=QueryFullProcessImageNameW(process,0,path,&count);CloseHandle(process);
        if(queried&&CompareStringOrdinal(path,static_cast<int>(count),executable.c_str(),-1,TRUE)==CSTR_EQUAL) return;
    }
    throw std::runtime_error("the verified official development game must already be running before stone mirroring");
}
class StoneConsumer {
    enum class Phase {idle,begin,ready,ending};
    minecome::Bridge& bridge_;
    ToolsHttp& http_;
    std::function<void(const std::string&)> record_;
    Phase phase_{Phase::idle};
    std::uint64_t session_{},last_session_{},pending_sequence_{},pending_operation_{};
    std::optional<minecome::StoneAlignment> alignment_;
    std::optional<minecome::AimedArenaReceipt> aimed_arena_;
    bool aimed_{};
    std::deque<minecome::BlockEventReceipt> queue_;
    Clock::time_point pending_since_{},last_heartbeat_{},last_end_{},last_wait_report_{};
    void command(const std::string& value) {
        try {http_.command(value);record_("STONE_DISPATCH "+value);}
        catch(const std::exception& error) {record_(std::string("STONE_DISPATCH_FAILED ")+error.what());}
    }
public:
    std::uint64_t spawned{},removed{},rejected{};
    StoneConsumer(minecome::Bridge& bridge,ToolsHttp& http,std::function<void(const std::string&)> record,bool aimed=false)
        :bridge_(bridge),http_(http),record_(std::move(record)),aimed_(aimed) {}
    bool idle() const {return phase_==Phase::idle;}
    bool aimed_session_current() const {
        const auto current=bridge_.aimed_arena();
        return aimed_&&aimed_arena_&&current&&(phase_==Phase::begin||phase_==Phase::ready)
            &&current->connection_generation==aimed_arena_->connection_generation&&current->reset_generation==aimed_arena_->reset_generation
            &&minecome::protocol::encode(current->arena)==minecome::protocol::encode(aimed_arena_->arena);
    }
    bool ready_for_aim() const {return aimed_session_current()&&phase_==Phase::ready&&!pending_sequence_&&queue_.empty();}
    void end(const char* reason) {
        queue_.clear();pending_sequence_=0;
        if(phase_==Phase::idle||phase_==Phase::ending) return;
        if(aimed_) bridge_.cancel_stone_inputs();
        record_(std::string("STONE_SESSION_END reason=")+reason+" session="+std::to_string(session_));
        phase_=Phase::ending;last_end_=Clock::now();last_wait_report_=last_end_;
        command(minecome::stone_session_command("End",session_));
    }
    void receipt(const minecome::StoneReceipt& receipt) {
        if(receipt.session!=session_) return;
        if(!receipt.block) {
            const bool ended=(receipt.event=="end"||receipt.event=="cleanup"||receipt.event=="expired"||receipt.event=="timer_failed")&&receipt.result=="ended";
            const bool never_registered=receipt.event=="end"&&receipt.result=="rejected_session"&&phase_==Phase::ending;
            if((ended||never_registered)&&receipt.owned_count==0&&receipt.pending_count==0) {
                record_("STONE_CLEANUP_ACK session="+std::to_string(session_));
                phase_=Phase::idle;alignment_.reset();aimed_arena_.reset();queue_.clear();pending_sequence_=0;
            } else if(receipt.event=="expired"||receipt.event=="timer_failed"||(receipt.event=="heartbeat"&&receipt.result!="alive")) {
                end("Lua session lease or timer unavailable");
            } else if(receipt.event=="begin"&&phase_==Phase::begin) {
                if(receipt.result=="accepted") {phase_=Phase::ready;last_heartbeat_=Clock::now();record_("STONE_BEGIN_ACK session="+std::to_string(session_));}
                else {++rejected;end("Lua rejected session begin");}
            }
            return;
        }
        if(phase_!=Phase::ready||receipt.sequence!=pending_sequence_||receipt.operation!=pending_operation_) return;
        const bool placed=receipt.operation==1&&(receipt.result=="spawned"||receipt.result=="already_present");
        const bool erased=receipt.operation==2&&(receipt.result=="removed"||receipt.result=="absent");
        if(receipt.operation==2&&receipt.result=="cleanup_pending") {
            // CryEngine may keep the entity until a later game frame. Keep the
            // original event deadline and queue blocked until its final receipt.
            record_("STONE_REMOVAL_PENDING session="+std::to_string(session_)+" sequence="+std::to_string(receipt.sequence));
            return;
        }
        if(placed||erased) {
            if(placed) ++spawned;else ++removed;
            record_("STONE_ENGINE_ACK session="+std::to_string(session_)+" sequence="+std::to_string(receipt.sequence)+" result="+receipt.result);
            pending_sequence_=0;
        } else {++rejected;end("Lua rejected or could not complete block event");}
    }
    void update(const std::optional<minecome::protocol::Pose>& kcd) {
        const auto now=Clock::now();
        const auto mc=bridge_.latest_client_pose();
        const bool valid=kcd&&mc&&bridge_.connected()&&bridge_.peer_role()==minecome::protocol::Role::minecraft
            &&(mc->flags&9)==9&&(kcd->flags&3)==3&&(!aimed_||((mc->flags&11)==11&&(kcd->flags&11)==11));
        auto batch=bridge_.drain_block_events(queue_.size()<64?std::min<std::size_t>(8,64-queue_.size()):0);
        if(batch.reset_required) {
            end("transport connection or bounded queue reset");
            if(idle()) bridge_.acknowledge_event_reset(batch.reset_generation);
        }
        if(!valid) end("fresh world pose or authenticated Minecraft peer unavailable");
        if(aimed_arena_&&!aimed_session_current()) end("acknowledged aimed arena was revoked");
        if(alignment_&&valid) {
            const auto a=alignment_->minecraft_anchor;
            const auto dx=mc->player.x-a.x,dy=mc->player.y-a.y,dz=mc->player.z-a.z;
            const auto b=alignment_->kcd_anchor;
            const auto kx=kcd->player.x-b.x,ky=kcd->player.y-b.y,kz=kcd->player.z-b.z;
            if(dx*dx+dy*dy+dz*dz>32*32||kx*kx+ky*ky+kz*kz>32*32) end("player left transient display area");
        }
        if(phase_==Phase::ending) {
            if(now-last_end_>=1s) {last_end_=now;command(minecome::stone_session_command("End",session_));}
            if(now-last_wait_report_>=3s) {last_wait_report_=now;record_("STONE_WAITING_FOR_CLEANUP_ACK session="+std::to_string(session_));}
            return;
        }
        if(!valid||batch.reset_required) return;
        for(auto& event:batch.events) {
            if(event.event.block_id=="minecraft:stone"&&bridge_.game_write_allowed(event)) queue_.push_back(std::move(event));
        }
        if(phase_==Phase::idle&&!queue_.empty()) {
            // Anchor only on a real accepted event; transport HELLO is not sink readiness.
            const auto& first=queue_.front();
            if(!first.client_pose||!bridge_.game_write_allowed(first)) {queue_.pop_front();return;}
            if(aimed_) {
                aimed_arena_=bridge_.aimed_arena();
                if(!aimed_arena_||aimed_arena_->connection_generation!=first.connection_generation||aimed_arena_->reset_generation!=first.reset_generation) {queue_.pop_front();return;}
                alignment_=minecome::StoneAlignment::from_arena(aimed_arena_->arena);
            } else alignment_=minecome::StoneAlignment::create(*first.client_pose,*kcd);
            if(!alignment_||!alignment_->map(first.event)) {queue_.pop_front();alignment_.reset();++rejected;return;}
            const auto micros=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
            session_=std::max(last_session_+1,static_cast<std::uint64_t>(micros));last_session_=session_;
            phase_=Phase::begin;pending_since_=now;
            command(minecome::stone_session_command("Begin",session_));
            return;
        }
        if(phase_==Phase::begin) {if(now-pending_since_>2s) end("no engine acknowledgement for session begin");return;}
        if(phase_!=Phase::ready) return;
        if(now-last_heartbeat_>=1s) {last_heartbeat_=now;command(minecome::stone_session_command("Heartbeat",session_));}
        if(pending_sequence_) {if(now-pending_since_>2s) end("no engine acknowledgement for block event");return;}
        while(!queue_.empty()) {
            auto event=std::move(queue_.front());queue_.pop_front();
            if(!bridge_.game_write_allowed(event)) {end("copied event is no longer current");return;}
            auto origin=alignment_->map(event.event);
            if(!origin) {++rejected;continue;}
            pending_sequence_=event.wire_sequence;pending_operation_=event.event.operation;pending_since_=now;
            command(minecome::stone_event_command(session_,pending_sequence_,event.event,*origin));
            break;
        }
    }
};
// This opt-in adapter never creates an aiming sample itself. It installs a
// guest-issued permit first, then admits only a Lua record carrying that same
// permit after the physical controller requested capture in the game callback.
class AimedInputRelay {
    enum class Phase {waiting,begin,ready,ended};
    struct Installed {
        minecome::AimPermitReceipt original;
        bool acknowledged{};
        double engine_time{};
    };
    minecome::Bridge& bridge_;
    ToolsHttp& http_;
    StoneConsumer& stones_;
    std::function<void(const std::string&)> record_;
    std::string run_;
    Phase phase_{Phase::waiting};
    std::optional<minecome::AimedArenaReceipt> arena_;
    std::deque<Installed> installed_;
    std::uint64_t last_permit_{},last_request_{};
    bool end_acknowledged_{};
    Clock::time_point began_{},last_install_{};
    bool same_arena() const {
        auto current=bridge_.aimed_arena();
        return current&&arena_&&current->connection_generation==arena_->connection_generation&&current->reset_generation==arena_->reset_generation
            &&minecome::protocol::encode(current->arena)==minecome::protocol::encode(arena_->arena);
    }
    void command(const std::string& command) {
        http_.command(command);record_("AIM_LUA_DISPATCH "+command);
    }
public:
    AimedInputRelay(minecome::Bridge& bridge,ToolsHttp& http,StoneConsumer& stones,std::function<void(const std::string&)> record,std::string run)
        :bridge_(bridge),http_(http),stones_(stones),record_(std::move(record)),run_(std::move(run)) {}
    bool cleanup_complete() const {return phase_==Phase::waiting||(phase_==Phase::ended&&end_acknowledged_);}
    void end(const char* reason) {
        if(phase_==Phase::waiting||phase_==Phase::ended) return;
        phase_=Phase::ended;installed_.clear();
        record_(std::string("AIM_INPUT_END reason=")+reason+" run="+run_);
        // Revoke queued/inflight authority under the bridge dispatch lock.
        // Already-written requests cannot be recalled: the immutable bridge
        // AIM_REQUEST journal remains the evidence of that earlier dispatch.
        bridge_.cancel_stone_inputs();
        record_("AIM_INPUT_CANCEL run="+run_+" arena="+std::to_string(arena_->arena.arena_id)+" authority_revoked=true sent_requests_recallable=false");
        stones_.end("aimed input session ended");
        try {command(minecome::aimed_end_command(run_,arena_->arena.arena_id));}catch(const std::exception& e) {record_(std::string("AIM_END_DISPATCH_FAILED ")+e.what());}
    }
    void update() {
        const auto now=Clock::now();
        if(phase_==Phase::ended) return;
        if(phase_==Phase::waiting) {
            if(!stones_.ready_for_aim()) return;
            arena_=bridge_.aimed_arena();if(!arena_) return;
            phase_=Phase::begin;began_=now;
            try {command(minecome::aimed_begin_command(run_,arena_->arena.arena_id));}
            catch(const std::exception&) {end("Lua begin dispatch unavailable");}
            return;
        }
        if(!same_arena()||!stones_.aimed_session_current()) {end("arena or engine session invalidated");return;}
        if(now-began_>60s) {end("bounded input session complete");return;}
        if(phase_==Phase::begin) {if(now-began_>1s) end("Lua begin acknowledgement unavailable");return;}
        std::erase_if(installed_,[&](const Installed& value){return now-value.original.received>500ms;});
        if(!stones_.ready_for_aim()||now-last_install_<100ms) return;
        auto permit=bridge_.latest_aimed_permit();
        if(!permit||permit->permit.permit_id<=last_permit_||permit->connection_generation!=arena_->connection_generation||permit->reset_generation!=arena_->reset_generation||now-permit->received>250ms||installed_.size()>=16) return;
        // Record the immutable receipt before HTTP dispatch. A later log record
        // must match this original permit; observing an ACK never renews it.
        installed_.push_back({*permit});last_permit_=permit->permit.permit_id;last_install_=now;
        try {command(minecome::aimed_permit_command(run_,permit->permit));}
        catch(const std::exception&) {end("Lua permit dispatch unavailable");}
    }
    void receipt(const minecome::AimedLuaReceipt& receipt,bool fresh) {
        if(receipt.run!=run_||!arena_||receipt.arena!=arena_->arena.arena_id) return;
        if(receipt.event=="end") {
            if(phase_==Phase::ended&&!end_acknowledged_) {end_acknowledged_=true;record_("AIM_INPUT_END_ACK run="+run_+" arena="+std::to_string(receipt.arena));}
            return;
        }
        if(!fresh||!same_arena()) return;
        if(receipt.event=="begin"&&phase_==Phase::begin&&Clock::now()-began_<=1s) {
            phase_=Phase::ready;record_("AIM_INPUT_BEGIN_ACK run="+run_+" arena="+std::to_string(receipt.arena));return;
        }
        if(receipt.event!="permit"||phase_!=Phase::ready) return;
        const auto found=std::find_if(installed_.begin(),installed_.end(),[&](const Installed& value){return value.original.permit.permit_id==receipt.permit;});
        if(found==installed_.end()||found->acknowledged||Clock::now()-found->original.received>350ms) return;
        found->acknowledged=true;found->engine_time=receipt.engine_time;
        const auto utc=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
        record_("AIM_PERMIT_READY run="+run_+" arena="+std::to_string(receipt.arena)+" permit="+std::to_string(receipt.permit)+" installed_utc_ms="+std::to_string(utc));
    }
    void intent(const minecome::AimedInputIntent& intent,bool fresh) {
        const auto& request=intent.request;
        auto refuse=[&](const char* reason){record_(std::string("AIM_INPUT_REJECTED reason=")+reason+" run="+intent.run+" request="+std::to_string(request.request_id)+" permit="+std::to_string(request.permit_id));};
        if(intent.run!=run_||!arena_||request.arena_id!=arena_->arena.arena_id) {refuse("wrong_run_or_arena");return;}
        if(request.request_id<=last_request_) {refuse("replayed_intent");return;}
        last_request_=request.request_id;
        const auto found=std::find_if(installed_.begin(),installed_.end(),[&](const Installed& value){return value.original.permit.permit_id==request.permit_id;});
        if(found==installed_.end()) {refuse("unknown_or_consumed_permit");return;}
        const auto original=*found;installed_.erase(found);
        if(!fresh) {refuse("stale_log_batch");return;}
        if(phase_!=Phase::ready) {refuse("input_session_unready");return;}
        if(!original.acknowledged) {refuse("permit_unacknowledged");return;}
        if(!same_arena()) {refuse("arena_invalidated");return;}
        if(!stones_.ready_for_aim()) {refuse("engine_session_unready");return;}
        if(Clock::now()-original.original.received>500ms) {refuse("original_permit_expired");return;}
        if(std::abs(original.engine_time-intent.permit_engine_time)>.000001) {refuse("permit_clock_mismatch");return;}
        // Permit receipt precedes installation and the observed click callback;
        // using that original time is conservative in the shared 500 ms budget.
        minecome::AimedInputRejection reason{};
        if(!bridge_.request_aimed_stone(request,original.original,original.original.received,&reason)) {
            refuse((std::string("bridge_")+minecome::aimed_input_rejection_name(reason)).c_str());return;
        }
        record_("AIM_INPUT_DISPATCH run="+run_+" arena="+std::to_string(request.arena_id)+" request="+std::to_string(request.request_id)+" permit="+std::to_string(request.permit_id)+" click="+std::to_string(intent.click)+" action="+std::to_string(request.action));
    }
};
}

int wmain(int argc,wchar_t** argv) {
    try {
        std::filesystem::path home,game_log,stop_file;
        unsigned seconds=120,port=38765,http_port=1403;
        std::optional<minecome::FovUnit> fov;
        bool camera_only=false,mirror_stone=false,interactive_stone=false,standalone_fixture=false,aimed_stone=false;
        std::string aimed_run;
        for(int i=1;i<argc;++i) {
            const std::wstring argument=argv[i];
            if(argument==L"--camera-only") {camera_only=true;continue;}
            if(argument==L"--mirror-stone") {mirror_stone=true;continue;}
            if(argument==L"--interactive-stone") {interactive_stone=true;mirror_stone=true;continue;}
            if(argument==L"--aimed-stone") {aimed_stone=true;mirror_stone=true;continue;}
            if(argument==L"--standalone-fixture") {standalone_fixture=true;continue;}
            if(i+1==argc) throw std::runtime_error("missing argument value");
            const std::wstring value=argv[++i];
            if(argument==L"--home") home=value;
            else if(argument==L"--game-log") game_log=value;
            else if(argument==L"--stop-file") stop_file=value;
            else if(argument==L"--aimed-run") {
                if(value.size()!=32||!std::all_of(value.begin(),value.end(),[](wchar_t c){return (c>=L'0'&&c<=L'9')||(c>=L'a'&&c<=L'f');})) throw std::runtime_error("aimed run must be 32 lowercase hexadecimal characters");
                aimed_run.clear();for(wchar_t c:value) aimed_run.push_back(static_cast<char>(c));
            }
            else if(argument==L"--seconds") seconds=bounded_integer(value,3600);
            else if(argument==L"--port") port=bounded_integer(value,65535);
            else if(argument==L"--tools-port") http_port=bounded_integer(value,65535);
            else if(argument==L"--fov-unit") {
                if(value==L"radians") fov=minecome::FovUnit::radians;
                else if(value==L"degrees") fov=minecome::FovUnit::degrees;
                else throw std::runtime_error("fov unit must be radians or degrees");
            } else throw std::runtime_error("unknown argument");
        }
        if(home.empty()||game_log.empty()||!home.is_absolute()||!game_log.is_absolute()||!fov)
            throw std::runtime_error("Usage: minecome_tools_host --home ABS --game-log ABS --fov-unit radians|degrees [--seconds 120] [--port 38765] [--tools-port 1403] [--stop-file ABS] [--camera-only] [--mirror-stone] [--interactive-stone | --aimed-stone --aimed-run HEX32]");
        if(aimed_stone&&(interactive_stone||camera_only)) throw std::runtime_error("aimed stone mode cannot mix with fixed-cell or camera-only modes");
        if(aimed_stone) (void)minecome::aimed_begin_command(aimed_run,1);
        else if(!aimed_run.empty()) throw std::runtime_error("aimed run requires explicit aimed stone mode");
        if(!stop_file.empty()&&!stop_file.is_absolute()) throw std::runtime_error("stop file must be an absolute path");
        if(standalone_fixture&&(http_port==1403||game_log.filename()!=L"fixture-kcd.log"
            ||std::filesystem::exists(game_log.parent_path()/L"Bin/Win64ReleaseSteamLTO_DLL/KingdomCome.exe")))
            throw std::runtime_error("standalone engine fixtures require a separate non-game log and non-default HTTP port");
        if(mirror_stone&&!standalone_fixture) require_supported_tools_process(game_log);
        std::filesystem::create_directories(home/"runtime"/"logs");
        std::ofstream evidence(home/"runtime"/"logs"/"tools-live-evidence.log",std::ios::app);
        auto record=[&](const std::string& text){evidence<<text<<'\n';evidence.flush();std::cout<<text<<'\n'<<std::flush;};
        if(standalone_fixture) record("STANDALONE_ENGINE_FIXTURE: simulated engine and peers, no live KCD proof");
        ToolsHttp http(static_cast<INTERNET_PORT>(http_port));
        const auto info=http.get(L"/api/System/Console?info");
        if(info.find("ExecuteString")==std::string::npos) throw std::runtime_error("expected official console binding missing");
        minecome::Bridge bridge;
        if(!bridge.start(home/"config"/"bridge.token",home/"runtime"/"logs"/"tools-bridge.log",static_cast<std::uint16_t>(port),"MineCome KCD2 official-tools/0.1.0",aimed_stone))
            throw std::runtime_error("transport startup failed; inspect tools-bridge.log");
        auto offset=std::filesystem::file_size(game_log);
        std::optional<StoneConsumer> stones;
        if(mirror_stone) {stones.emplace(bridge,http,record,aimed_stone);record(aimed_stone?"Aimed stone mirroring enabled: acknowledged arena alignment, physics disabled, engine log acknowledgement required":"Stone mirroring enabled: transient display alignment, physics disabled, engine log acknowledgement required");}
        std::optional<AimedInputRelay> aimed_inputs;
        if(aimed_stone) aimed_inputs.emplace(bridge,http,*stones,record,aimed_run);
        std::optional<minecome::protocol::Pose> current_world;
        std::string pending;
        // A complete critical JSON record can precede KCD's next newline.
        // Retain its exact bytes until that separator arrives; never replay it.
        std::string processed_critical_tail;
        struct LoggedInput {
            minecome::protocol::StoneInputRequest request;
            std::uint64_t connection_generation{},reset_generation{};
            Clock::time_point received;
        };
        std::deque<LoggedInput> pending_inputs;
        auto last_input_log_read=Clock::now();
        auto last_input_generation=bridge.drain_block_events(0);
        bool partial_input_stale=false;
        auto partial_input_received=Clock::now();
        std::uint64_t last_input_id=0;
        if(interactive_stone) record("Interactive stone input enabled; use minecome_place / minecome_break in the KCD2 console. Minecraft input capability and fresh world state required.");
        http.command("#MineCome.Ping('MINECOME_PING_TOOLS_ADAPTER')");
        record("Official tools console binding verified; waiting for fresh in-game diagnostic log receipt");
        const auto deadline=Clock::now()+std::chrono::seconds(seconds);
        std::uint64_t samples=0,world_samples=0,acknowledged_poses=0,acknowledged_events=0;
        bool was_connected=false,menu_reported=false,world_state_valid=false,had_world=false;
        auto last_world_sample=Clock::now();
        unsigned http_failures=0;
        auto invalidate_world=[&](const char* reason) {
            pending_inputs.clear();
            if(aimed_inputs) aimed_inputs->end(reason);
            bridge.cancel_stone_inputs();
            if(!world_state_valid) return;
            minecome::protocol::Pose invalid;
            invalid.flags=0;
            bridge.publish(invalid);
            world_state_valid=false;
            current_world.reset();
            if(stones) stones->end(reason);
            record(std::string("World POSE invalidated; all validity flags cleared: ")+reason);
        };
        auto drain_game_log=[&] {
            const auto input_generation=bridge.drain_block_events(0);
            const bool carried_partial=!pending.empty();
            pending+=new_log_bytes(game_log,offset);
            const auto input_log_read=Clock::now();
            const auto after_read_generation=bridge.drain_block_events(0);
            const bool fresh_input_batch=input_log_read-last_input_log_read<=1s
                &&input_generation.connection_generation==last_input_generation.connection_generation
                &&input_generation.reset_generation==last_input_generation.reset_generation
                &&input_generation.connection_generation==after_read_generation.connection_generation
                &&input_generation.reset_generation==after_read_generation.reset_generation;
            last_input_log_read=input_log_read;
            last_input_generation=after_read_generation;
            // KCD commonly writes a newline before the next record, leaving the
            // latest record unterminated. Taint belongs to that carried line,
            // not all future records in a buffer that may never become empty.
            bool line_input_stale=!fresh_input_batch||(carried_partial
                &&(partial_input_stale||input_log_read-partial_input_received>1s));
            bool consumed_line=false;
            while(true) {
                const auto end=pending.find('\n');if(end==std::string::npos) break;
                const auto line=pending.substr(0,end);pending.erase(0,end+1);
                if(!processed_critical_tail.empty()) {
                    if(line!=processed_critical_tail&&line!=processed_critical_tail+"\r") {
                        invalidate_world("completed critical log record changed before separator");
                        pending.clear();processed_critical_tail.clear();partial_input_stale=true;return;
                    }
                    processed_critical_tail.clear();
                    line_input_stale=!fresh_input_batch;consumed_line=true;continue;
                }
                if(line.find("[MineComePing]")!=std::string::npos) record("KCD2_LOG "+line);
                if(auto receipt=minecome::parse_stone_receipt(line)) {record("KCD2_LOG "+line);if(stones) stones->receipt(*receipt);}
                if(aimed_inputs) {
                    if(auto receipt=minecome::parse_aimed_lua_receipt(line)) {record("KCD2_LOG "+line);aimed_inputs->receipt(*receipt,!line_input_stale);}
                    if(auto intent=minecome::parse_aimed_input_intent(line)) {record("KCD2_LOG "+line);aimed_inputs->intent(*intent,!line_input_stale);}
                    else if(line.find("[MineComeAimInput]")!=std::string::npos) {
                        record("KCD2_LOG "+line.substr(0,4096));
                        record("AIM_INPUT_REJECTED reason=unavailable_or_malformed_sample");
                    }
                }
                if(auto input=minecome::parse_stone_input_intent(line)) {
                    record("KCD2_LOG "+line);
                    if(input->id<=last_input_id) record("STONE_INPUT_REJECTED reason=replayed_intent request="+std::to_string(input->id));
                    else {
                        last_input_id=input->id;
                        if(line_input_stale) record("STONE_INPUT_REJECTED reason=stale_log_batch request="+std::to_string(input->id));
                        else if(interactive_stone&&pending_inputs.size()<16)
                            pending_inputs.push_back({*input,input_generation.connection_generation,input_generation.reset_generation,input_log_read});
                        else record("STONE_INPUT_REJECTED reason=disabled_or_busy request="+std::to_string(input->id));
                    }
                }
                if(auto sample=minecome::parse_tools_pose(line,*fov)) {
                    ++samples;
                    if(sample->has_player) {
                        if(aimed_stone) sample->pose.flags|=8u;
                        ++world_samples;bridge.publish(sample->pose);
                        world_state_valid=true;had_world=true;last_world_sample=Clock::now();
                        current_world=sample->pose;
                    } else {
                        invalidate_world("player is absent from fresh game diagnostic");
                        if(camera_only&&!had_world) bridge.publish(sample->pose);
                        if(!menu_reported) {record("Fresh live camera sample has no player; world POSE publishing withheld until a world/save is loaded");menu_reported=true;}
                    }
                    if(samples==1||world_samples==1) record("KCD2_LOG "+line);
                }
                // Subsequent lines started in this read; the old partial's
                // age/reset history must not reject these independent records.
                line_input_stale=!fresh_input_batch;
                consumed_line=true;
            }
            if(!processed_critical_tail.empty()) {
                if(pending!=processed_critical_tail&&pending!=processed_critical_tail+"\r") {
                    invalidate_world("completed critical log tail changed before separator");
                    pending.clear();processed_critical_tail.clear();partial_input_stale=true;return;
                }
            } else if(aimed_inputs&&!pending.empty()) {
                // Only strict, bounded, end-anchored parsers can complete a tail.
                // A marker or partially-written JSON object is not a record.
                // Keep the carried line's first-read age/reset taint unchanged.
                if(auto receipt=minecome::parse_aimed_lua_receipt(pending)) {
                    record("KCD2_LOG "+pending);aimed_inputs->receipt(*receipt,!line_input_stale);
                    processed_critical_tail=pending;
                } else if(auto intent=minecome::parse_aimed_input_intent(pending)) {
                    record("KCD2_LOG "+pending);aimed_inputs->intent(*intent,!line_input_stale);
                    processed_critical_tail=pending;
                }
            }
            if(pending.size()>8192) {pending.clear();processed_critical_tail.clear();}
            partial_input_stale=!pending.empty()&&line_input_stale;
            if(consumed_line||!carried_partial||pending.empty()) partial_input_received=input_log_read;
        };
        auto next_pose_request=Clock::now();
        while(Clock::now()<deadline&&(stop_file.empty()||!std::filesystem::exists(stop_file))) {
            // Read already-captured intent before another synchronous HTTP round
            // trip, but only while the previous endpoint/world authority is fresh.
            if(aimed_stone&&http_failures==0&&world_state_valid&&Clock::now()-last_world_sample<=500ms)
                drain_game_log();
            if(!aimed_stone||Clock::now()>=next_pose_request) {
                try {
                    http.command("#MineCome.SamplePose()");
                    http_failures=0;
                    // Faster log polling must not increase sampling HTTP rate.
                    next_pose_request=Clock::now()+50ms;
                } catch(const std::exception& error) {
                    invalidate_world("official game HTTP endpoint unavailable");
                    if(++http_failures==1) record(std::string("Official HTTP temporarily unavailable: ")+error.what());
                    if(http_failures>=5) {
                        record("Official HTTP recovery limit reached; shutting down bridge gracefully");
                        break;
                    }
                    std::this_thread::sleep_for(200ms);
                    continue;
                }
            }
            drain_game_log();
            if(world_state_valid&&Clock::now()-last_world_sample>1s) invalidate_world("no fresh valid world sample for one second");
            if(stones) stones->update(current_world);
            if(aimed_inputs) aimed_inputs->update();
            // Permit ACKs/captures written during those synchronous commands
            // should not wait for another pose call or log separator.
            if(aimed_stone) drain_game_log();
            while(!pending_inputs.empty()) {
                const auto logged=pending_inputs.front();pending_inputs.pop_front();
                const auto& input=logged.request;
                if(current_world&&world_state_valid&&Clock::now()-last_world_sample<=1s&&Clock::now()-logged.received<=1s
                    &&(current_world->flags&3)==3&&bridge.input_ready()
                    &&bridge.request_stone_input(input,logged.connection_generation,logged.reset_generation))
                    record("STONE_INPUT_DISPATCH request="+std::to_string(input.id)+" action="+std::to_string(input.action));
                else record("STONE_INPUT_REJECTED reason=no_ready_world_or_input_peer request="+std::to_string(input.id));
            }
            for(const auto& receipt:bridge.drain_stone_input_results()) {
                const auto& result=receipt.result;
                record("STONE_INPUT_RESULT request="+std::to_string(result.id)+" action="+std::to_string(result.action)
                    +" result="+std::to_string(static_cast<std::uint32_t>(result.result)));
            }
            if(aimed_inputs) for(const auto& receipt:bridge.drain_aimed_results()) {
                const auto& result=receipt.result;
                record("AIM_INPUT_RESULT run="+aimed_run+" arena="+std::to_string(result.arena_id)+" request="+std::to_string(result.request_id)+" action="+std::to_string(result.action)+" result="+std::to_string(static_cast<unsigned>(result.result)));
            }
            const bool connected=bridge.connected();
            if(connected&&!was_connected) {
                try {http.command("#MineCome.Ping('MC_CONNECTED_AUTHENTICATED')");}
                catch(const std::exception& error) {record(std::string("In-game connect acknowledgement unavailable: ")+error.what());}
            }
            was_connected=connected;
            const auto poses=bridge.received_poses(),events=bridge.received_events();
            if(poses>acknowledged_poses) {
                if(acknowledged_poses==0) {
                    try {http.command("#MineCome.Ping('MC_POSE_RECEIVED count="+std::to_string(poses)+"')");}
                    catch(const std::exception& error) {record(std::string("In-game pose acknowledgement unavailable: ")+error.what());}
                }
                acknowledged_poses=poses;
            }
            if(events>acknowledged_events) {
                try {http.command("#MineCome.Ping('MC_BLOCK_EVENT_RECEIVED count="+std::to_string(events)+"')");}
                catch(const std::exception& error) {record(std::string("In-game event acknowledgement unavailable: ")+error.what());}
                acknowledged_events=events;
            }
            std::this_thread::sleep_for(aimed_stone?5ms:200ms);
        }
        pending_inputs.clear();
        if(aimed_inputs) aimed_inputs->end("relay shutting down");
        bridge.cancel_stone_inputs();
        if(stones) {
            stones->end("relay shutting down");
            const auto cleanup_deadline=Clock::now()+2s;
            while((!stones->idle()||(aimed_inputs&&!aimed_inputs->cleanup_complete()))&&Clock::now()<cleanup_deadline) {
                // Read-only sampling supplies the next log separator: KCD can
                // leave its final End receipt without a terminating newline.
                try {http.command("#MineCome.SamplePose()");} catch(const std::exception&) {}
                pending+=new_log_bytes(game_log,offset);
                while(true) {
                    const auto newline=pending.find('\n');if(newline==std::string::npos) break;
                    const auto line=pending.substr(0,newline);pending.erase(0,newline+1);
                    if(!processed_critical_tail.empty()) {
                        if(line!=processed_critical_tail&&line!=processed_critical_tail+"\r") record("Completed critical log record changed during cleanup");
                        processed_critical_tail.clear();continue;
                    }
                    if(auto receipt=minecome::parse_stone_receipt(line)) {record("KCD2_LOG "+line);stones->receipt(*receipt);}
                    if(aimed_inputs) if(auto receipt=minecome::parse_aimed_lua_receipt(line)) {record("KCD2_LOG "+line);aimed_inputs->receipt(*receipt,false);}
                }
                std::this_thread::sleep_for(50ms);
            }
            record("Stone engine acknowledgements: placed="+std::to_string(stones->spawned)+" removed="+std::to_string(stones->removed)+" rejected="+std::to_string(stones->rejected)
                +" cleanup_ack="+(stones->idle()?"true":"false; Lua lease remains responsible"));
            if(aimed_inputs) record(std::string("Aimed input cleanup acknowledgement: ")+(aimed_inputs->cleanup_complete()?"true":"false; Lua lease remains responsible"));
        }
        bridge.stop();
        record("Fresh live camera samples="+std::to_string(samples)+" world/player samples="+std::to_string(world_samples)
            +" Minecraft poses received="+std::to_string(acknowledged_poses)+" block events received="+std::to_string(acknowledged_events));
        return acknowledged_poses>0?0:3;
    } catch(const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
}
