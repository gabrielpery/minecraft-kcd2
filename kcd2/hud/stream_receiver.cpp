// Standalone genuine-producer transport observer. Never loads game APIs.
#include "stream_channel.hpp"
#include <charconv>
#include <iostream>
#include <map>
#include <set>
#include <sstream>

namespace st = minecome::hud::stream;
namespace {
template<class T> bool number(const std::wstring &s, T &out) {
    if (s.empty()) return false;
    std::string n;
    for (wchar_t c : s) { if (c < L'0' || c > L'9') return false; n += static_cast<char>(c); }
    const auto result = std::from_chars(n.data(),n.data()+n.size(),out);
    return result.ec == std::errc{} && result.ptr == n.data()+n.size();
}
bool save(const std::wstring &path, const std::string &json) {
    st::Handle file(CreateFileW(path.c_str(),GENERIC_WRITE,0,nullptr,CREATE_NEW,
        FILE_ATTRIBUTE_NORMAL|FILE_FLAG_OPEN_REPARSE_POINT,nullptr));
    if (!file) return false;
    DWORD wrote = 0;
    return WriteFile(file.value,json.data(),static_cast<DWORD>(json.size()),&wrote,nullptr) && wrote == json.size() && FlushFileBuffers(file.value);
}
}
int wmain(int argc, wchar_t **argv) {
    try {
        std::map<std::wstring,std::wstring> args;
        for (int i=1;i<argc;i+=2) {
            if (i+1 >= argc || !args.emplace(argv[i],argv[i+1]).second) return 2;
        }
        for (const auto &[key,value] : args) {
            (void)value;
            if (key != L"--run" && key != L"--target-pid" && key != L"--target-start" && key != L"--producer-pid" &&
                key != L"--producer-start" && key != L"--expires" && key != L"--output") return 2;
        }
        if (args.size() != 7 || args[L"--output"].empty()) return 2;
        st::Identity id;
        for (auto c : args[L"--run"]) { if (c > 127) return 2; id.run += static_cast<char>(c); }
        if (!number(args[L"--target-pid"],id.target_pid) || !number(args[L"--target-start"],id.target_start) ||
            !number(args[L"--producer-pid"],id.producer_pid) || !number(args[L"--producer-start"],id.producer_start) ||
            !number(args[L"--expires"],id.expires_utc_ms) || !st::valid_identity(id)) return 2;
        st::Channel channel;
        std::uint64_t accepted=0, repeated=0, busy=0, nontransparent=0, first=0,last=0;
        bool closed=false, stale=false, resumed=false, had_fresh=false;
        std::set<std::pair<std::uint32_t,std::uint32_t>> states;
        std::string reason;
        if (channel.open(id)) {
            for (;;) {
                std::shared_ptr<const st::Frame> frame;
                const auto result = channel.poll(frame);
                const bool fresh = channel.fresh();
                if (had_fresh && !fresh && result != st::Poll::closed && result != st::Poll::failed) stale=true;
                if (stale && fresh) resumed=true;
                if (fresh) had_fresh=true;
                if (result == st::Poll::frame) {
                    ++accepted; if (!first) first=frame->header.sequence; last=frame->header.sequence;
                    states.emplace(frame->header.selected,frame->header.screen);
                    for (std::size_t i=3;i<frame->premultiplied.size();i+=4)
                        if (frame->premultiplied[i]) { ++nontransparent; break; }
                } else if (result == st::Poll::unchanged) ++repeated;
                else if (result == st::Poll::busy) ++busy;
                else if (result == st::Poll::closed) { closed=true; reason="closed"; break; }
                else if (result == st::Poll::failed) { reason=channel.reason(); break; }
                Sleep(5);
            }
        } else reason=channel.reason();
        const bool passed = closed && accepted > 0 && nontransparent > 0;
        std::ostringstream json;
        json << "{\n  \"schema\":1,\n  \"run\":\"" << id.run << "\",\n  \"result\":\"" << (passed?"passed":"failed")
             << "\",\n  \"reason\":\"" << reason << "\",\n  \"accepted_frames\":" << accepted
             << ",\n  \"nontransparent_frames\":" << nontransparent << ",\n  \"first_sequence\":" << first << ",\n  \"last_sequence\":" << last
             << ",\n  \"repeated_polls\":" << repeated << ",\n  \"busy_polls\":" << busy
             << ",\n  \"closed_seen\":" << (closed?"true":"false") << ",\n  \"stale_hidden_verified\":" << (stale?"true":"false")
             << ",\n  \"fresh_resumption_verified\":" << (resumed?"true":"false") << ",\n  \"kcd_compositing_verified\":false,\n  \"states_seen\":[";
        bool comma=false;
        for (const auto &[selected,screen] : states) {
            if (comma) json << ','; comma=true;
            json << "{\"selected\":" << selected << ",\"screen\":" << screen << '}';
        }
        json << "]\n}\n";
        if (!save(args[L"--output"],json.str())) { std::cerr << "Receipt create-new write failed\n"; return 3; }
        std::cout << "HUD_STREAM_RECEIVER result=" << (passed?"passed":"failed") << " reason=" << reason << " frames=" << accepted << '\n';
        return passed?0:1;
    } catch (...) { std::cerr << "HUD_STREAM_RECEIVER exception\n"; return 4; }
}
