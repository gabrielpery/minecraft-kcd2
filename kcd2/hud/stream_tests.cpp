#include "stream_channel.hpp"
#include <algorithm>
#include <array>
#include <bit>
#include <limits>
#include <cstring>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <thread>

namespace st=minecome::hud::stream;
namespace {
unsigned checks=0;
void check(bool value, const char *label) {
    ++checks; if (!value) throw std::runtime_error(label);
}
void put32(std::span<std::uint8_t> h, std::size_t at, std::uint32_t n) {
    for (unsigned i=0;i<4;++i) h[at+i]=static_cast<std::uint8_t>(n >> (i*8));
}
void put64(std::span<std::uint8_t> h, std::size_t at, std::uint64_t n) {
    for (unsigned i=0;i<8;++i) h[at+i]=static_cast<std::uint8_t>(n >> (i*8));
}
void putf(std::span<std::uint8_t> h,std::size_t at,float value) { put32(h,at,std::bit_cast<std::uint32_t>(value)); }
st::Identity identity() { return {"0123456789abcdef0123456789abcdef",17,19,100,200,120000}; }
std::array<std::uint8_t,st::header_bytes> header(const st::Identity &id, std::uint32_t state=1, std::uint32_t format=1) {
    std::array<std::uint8_t,st::header_bytes> h{};
    std::memcpy(h.data(),id.schema==3?"MCHUDS03":"MCHUDS01",8); put32(h,8,id.schema); put32(h,12,256); std::memcpy(h.data()+16,id.run.data(),32);
    put32(h,48,id.producer_pid); put32(h,52,id.target_pid); put64(h,56,id.producer_start); put64(h,64,id.target_start);
    put64(h,72,id.expires_utc_ms); put32(h,112,format); put32(h,116,state);
    if (state != 0) { put64(h,80,1); put64(h,88,100000); put32(h,96,2); put32(h,100,1); put32(h,104,8); put32(h,108,format==2?24:8); }
    if(state!=0&&format==2) {
        putf(h,136,120.f);putf(h,140,2040.f);putf(h,144,58.f);
        putf(h,152,1.f);putf(h,168,1.f);putf(h,172,1.265f);putf(h,176,.05f);putf(h,180,512.f);
    }
    return h;
}
std::string arm(const st::Identity &id) {
    return "[HudStream]\nSchema="+std::to_string(id.schema)+"\nRun="+id.run+"\nTargetPid="+std::to_string(id.target_pid)+
        "\nTargetStart="+std::to_string(id.target_start)+"\nProducerPid="+std::to_string(id.producer_pid)+
        "\nProducerStart="+std::to_string(id.producer_start)+"\nExpiresUtcMs="+std::to_string(id.expires_utc_ms)+"\n";
}
void contract_tests() {
    const auto id=identity(); st::Identity parsed; std::string error;
    check(st::parse_arm(arm(id),19,200,100000,parsed,error),"valid arm");
    check(parsed.run == id.run && parsed.producer_start == 100,"parsed identity");
    const std::array<std::string,9> badarms{arm(id)+"Schema=1\n",arm(id)+"Other=1\n",arm(id)+"[HudStream]\n",
        "[wrong]\n"+arm(id),std::string(4097,'a'),std::string("\xef\xbb\xbf")+arm(id),arm(id)+"#comment\n",arm(id)+std::string(1,'\0'),"[HudStream]\nSchema=1\n"};
    for (const auto &bad : badarms) check(!st::parse_arm(bad,19,200,100000,parsed,error),"malformed arm rejected");
    check(!st::parse_arm(arm(id),18,200,100000,parsed,error),"wrong target rejected");
    check(!st::parse_arm(arm(id),19,201,100000,parsed,error),"wrong target start rejected");
    check(!st::parse_arm(arm(id),19,200,120000,parsed,error),"expired arm rejected");
    auto longid=id; longid.expires_utc_ms=280001;
    check(!st::parse_arm(arm(longid),19,200,100000,parsed,error),"long arm rejected");
    auto invalidtoken=id; invalidtoken.run[0]='G';
    check(!st::parse_arm(arm(invalidtoken),19,200,100000,parsed,error),"uppercase run rejected");
    auto overflow=arm(id); overflow.replace(overflow.find("TargetPid=19"),12,"TargetPid=4294967296");
    check(!st::parse_arm(overflow,19,200,100000,parsed,error),"pid overflow rejected");
    st::Validator valid; st::Header out;
    check(valid.start(id,100000,5000),"lease starts");
    check(!valid.start(id,100000,5000),"lease cannot restart");
    auto h=header(id,0);
    check(valid.accept(h,100000,5000,out) == st::Result::waiting,"waiting accepted");
    check(!valid.fresh(100000,5000),"waiting not fresh");
    h=header(id);
    check(valid.accept(h,100000,5000,out) == st::Result::frame,"first frame accepted");
    check(valid.fresh(100500,5500),"500ms still fresh");
    check(!valid.fresh(100501,5501),"501ms stale");
    check(valid.accept(h,100900,5900,out) == st::Result::unchanged,"duplicate skipped");
    check(!valid.fresh(100900,5900),"duplicate cannot refresh");
    put64(h,80,8); put64(h,88,100901);
    check(valid.accept(h,100901,5901,out) == st::Result::frame,"sequence skips accepted");
    check(valid.fresh(100901,5901),"new publication resumes");
    check(!st::uploaded_fresh(5000,5901),"new pub cannot refresh old GPU resident");
    check(!st::uploaded_fresh(5901,5000),"resident rejects reversed clock");
    put32(h,116,2); put64(h,88,1);
    check(valid.accept(h,110000,15000,out) == st::Result::closed,"closed ignores old capture age");
    check(!valid.fresh(110000,15000),"closed hides");
    put32(h,116,1);
    check(valid.accept(h,110000,15000,out) == st::Result::invalid,"closed terminal");
    for (const auto offset : {0u,8u,12u,16u,48u,52u,56u,64u,72u,128u,255u}) {
        auto bad=header(id); bad[offset]^=1;
        st::Validator v; v.start(id,100000,5000);
        check(v.accept(bad,100000,5000,out) == st::Result::invalid,"immutable malformed rejected");
        check(!v.fresh(100000,5000),"malformed hidden");
    }
    for (const auto pair : {std::pair{96u,0u},{96u,1921u},{100u,1081u},{104u,9u},{108u,9u},{112u,2u},{116u,3u},{120u,9u},{124u,2u}}) {
        auto bad=header(id); put32(bad,pair.first,pair.second);
        st::Validator v; v.start(id,100000,5000);
        check(v.accept(bad,100000,5000,out) == st::Result::invalid,"frame fields rejected");
    }
    for (const auto timestamp : {0ULL,98999ULL,100251ULL}) {
        auto bad=header(id); put64(bad,88,timestamp);
        st::Validator v; v.start(id,100000,5000);
        check(v.accept(bad,100000,5000,out) == st::Result::invalid,"capture age rejected");
    }
    for (const auto timestamp : {99000ULL,100250ULL}) {
        auto boundary=header(id); put64(boundary,88,timestamp);
        st::Validator v; v.start(id,100000,5000);
        check(v.accept(boundary,100000,5000,out) == st::Result::frame,"capture boundary accepted");
    }
    for (const auto offset : {80u,88u,96u,100u,104u,108u,120u,124u}) {
        auto bad=header(id,0); bad[offset]=1;
        st::Validator v; v.start(id,100000,5000);
        check(v.accept(bad,100000,5000,out) == st::Result::invalid,"waiting zeros required");
    }
    for (int kind=0;kind<5;++kind) {
        st::Validator v; v.start(id,100000,5000);
        auto previous=header(id); put64(previous,80,2);
        check(v.accept(previous,100000,5000,out) == st::Result::frame,"baseline valid");
        if (kind==0) put64(previous,80,1);
        if (kind==1) put64(previous,80,0);
        if (kind==2) { put32(previous,96,1); put32(previous,104,4); put32(previous,108,4); }
        if (kind==3) previous=header(id,0);
        if (kind==4) put64(previous,72,120001);
        check(v.accept(previous,100001,5001,out) == st::Result::invalid,"replay resize renewal or waiting rejected");
    }
    st::Validator monotonic; monotonic.start(id,100000,5000);
    check(!monotonic.live(90000,25000),"backward wallclock cannot extend lease");
    check(!monotonic.live(100000,4999),"backward monotonic rejected");
    st::Validator expiry; expiry.start(id,100000,5000);
    check(expiry.accept(header(id),120000,6000,out) == st::Result::expired,"UTC expiry enforced");
    st::Validator short_header; short_header.start(id,100000,5000);
    const std::array<std::uint8_t,10> tiny{};
    check(short_header.accept(tiny,100000,5000,out) == st::Result::invalid,"short header rejected");
}
void layered_contract_tests() {
    auto id=identity();id.schema=3;st::Header out;st::Identity parsed;std::string error;
    check(st::mapping_for_schema(1)==st::mapping_bytes&&st::mapping_for_schema(3)==st::header_bytes+3*st::pixel_capacity,"schema capacities stay separate");
    check(st::parse_arm(arm(id),19,200,100000,parsed,error,3),"gameplay arm accepted");
    st::Validator layered;check(layered.start(id,100000,5000),"layered lease starts");
    check(layered.accept(header(id,0,2),100000,5000,out)==st::Result::waiting&&out.format==2,"layered waiting accepted");
    auto h=header(id,1,2);
    check(layered.accept(h,100000,5000,out)==st::Result::frame&&out.bytes==24&&out.pitch==8&&out.height==1,"three planes retain logical dimensions");
    check(layered.accept(h,100501,5501,out)==st::Result::unchanged&&!layered.fresh(100501,5501),"layered replay cannot refresh");
    put32(h,116,2);put64(h,88,1);
    check(layered.accept(h,110000,15000,out)==st::Result::closed,"layered closed permits old capture");
    st::Validator empty;empty.start(id,100000,5000);h=header(id,0,2);put32(h,116,2);
    check(empty.accept(h,100000,5000,out)==st::Result::closed,"layered closes before first frame");
    for(const auto initial:{0u,1u}) {
        st::Validator changing;changing.start(id,100000,5000);
        check(changing.accept(header(id,initial,2),100000,5000,out)==(initial?st::Result::frame:st::Result::waiting),"layered baseline for immutable format");
        h=header(id);put64(h,80,2);
        check(changing.accept(h,100001,5001,out)==st::Result::invalid&&changing.reason()=="frame_format_changed","format cannot change after waiting or frame");
    }
    for(const auto pair:{std::pair{108u,8u},{108u,23u},{108u,25u},{108u,0xffffffffu},{112u,3u},{96u,1921u},{100u,1081u}}) {
        st::Validator bad;bad.start(id,100000,5000);h=header(id,1,2);put32(h,pair.first,pair.second);
        check(bad.accept(h,100000,5000,out)==st::Result::invalid,"layered malformed dimensions or format refused");
    }
    st::Validator largest;largest.start(id,100000,5000);h=header(id,1,2);
    put32(h,96,1920);put32(h,100,1080);put32(h,104,1920*4);put32(h,108,static_cast<std::uint32_t>(st::gameplay_pixel_capacity));
    check(largest.accept(h,100000,5000,out)==st::Result::frame,"largest bounded layered frame accepted");
    check(out.camera_position[0]==120.f&&out.camera_direction[1]==1.f&&out.camera_up[2]==1.f&&out.near_plane==.05f&&out.far_plane==512.f,"layered camera and lens decoded");
    for(const auto pair:{std::pair{136u,std::numeric_limits<float>::quiet_NaN()},{148u,1.f},{160u,2.f},{168u,0.f},{172u,0.f},{176u,0.f},{180u,.01f}}) {
        st::Validator bad;bad.start(id,100000,5000);h=header(id,1,2);putf(h,pair.first,pair.second);
        check(bad.accept(h,100000,5000,out)==st::Result::invalid&&bad.reason()=="frame_camera","malformed camera basis/lens refused");
    }
    for(const auto stamp:{98999ULL,100051ULL}) {
        st::Validator old;old.start(id,100000,5000);h=header(id,1,2);put64(h,128,stamp);
        check(old.accept(h,100000,5000,out)==st::Result::invalid&&old.reason()=="frame_camera_age","stale or future camera refused");
    }
    for(const auto stamp:{0ULL,99000ULL,100050ULL}) {
        st::Validator boundary;boundary.start(id,100000,5000);h=header(id,1,2);put64(h,128,stamp);
        check(boundary.accept(h,100000,5000,out)==st::Result::frame,"fixture camera or boundary age accepted");
    }
    h=header(id,1,2);std::fill(h.begin()+128,h.begin()+176,0);
    st::Validator overlay_only;overlay_only.start(id,100000,5000);
    check(overlay_only.accept(h,100000,5000,out)==st::Result::frame&&out.vertical_fov==0.f,"overlay-only camera sentinel accepted");
    for(const auto field:{128u,136u,176u}) {
        auto bad=h;if(field==128)put64(bad,field,100000);else putf(bad,field,field==176?0.f:1.f);
        st::Validator partial;partial.start(id,100000,5000);
        check(partial.accept(bad,100000,5000,out)==st::Result::invalid&&partial.reason()=="frame_camera","partial or timestamped empty camera refused");
    }
    st::Validator reserved;reserved.start(id,100000,5000);h=header(id,1,2);h[184]=1;
    check(reserved.accept(h,100000,5000,out)==st::Result::invalid&&reserved.reason()=="header_reserved","remaining layered extension reserved");
    st::Validator flat;flat.start(id,100000,5000);
    check(flat.accept(header(id),100000,5000,out)==st::Result::frame&&out.format==1&&out.bytes==8,"flat gameplay format preserved");
    auto lab=identity();st::Validator forbidden;forbidden.start(lab,100000,5000);
    check(forbidden.accept(header(lab,0,2),100000,5000,out)==st::Result::invalid,"lab waiting cannot select layered format");
}
struct Fixture {
    st::Identity id;
    st::Handle mapping,mutex;
    std::uint8_t *data=nullptr;
    explicit Fixture(unsigned serial, std::size_t size=0, std::uint32_t schema=1) {
        std::ostringstream run; run << std::hex; run.width(16); run.fill('0'); run << GetCurrentProcessId();
        run.width(16); run << (st::steady_ms()+serial);
        id={run.str(),GetCurrentProcessId(),GetCurrentProcessId(),st::process_start(),st::process_start(),st::utc_ms()+15000};
        id.schema=schema;if(!size)size=st::mapping_for_schema(schema);
        const std::wstring suffix(id.run.begin(),id.run.end());
        mapping.reset(CreateFileMappingW(INVALID_HANDLE_VALUE,nullptr,PAGE_READWRITE,0,static_cast<DWORD>(size),(L"Local\\MineComeHud_"+suffix).c_str()));
        check(mapping && GetLastError() != ERROR_ALREADY_EXISTS,"new fixture mapping");
        mutex.reset(CreateMutexW(nullptr,FALSE,(L"Local\\MineComeHudLock_"+suffix).c_str()));
        check(mutex && GetLastError() != ERROR_ALREADY_EXISTS,"new fixture mutex");
        data=static_cast<std::uint8_t *>(MapViewOfFile(mapping.value,FILE_MAP_WRITE,0,0,size));
        check(data != nullptr,"fixture mapped");
    }
    ~Fixture() { if (data) UnmapViewOfFile(data); }
    void write(std::uint64_t seq, std::uint32_t state=1, std::uint32_t format=1, float depth=.25f) {
        auto h=header(id,state,format); put64(h,80,seq); put64(h,88,st::utc_ms());
        check(WaitForSingleObject(mutex.value,5) == WAIT_OBJECT_0,"fixture mutex acquired");
        std::memcpy(data,h.data(),h.size());
        const std::array<std::uint8_t,8> pixels{200,100,50,128,99,80,33,0}; std::memcpy(data+256,pixels.data(),pixels.size());
        if(format==2) {
            const std::array<std::uint8_t,8> world{100,200,50,64,19,23,29,255};std::memcpy(data+264,world.data(),world.size());
            put32(std::span(data+272,8),0,std::bit_cast<std::uint32_t>(depth));put32(std::span(data+272,8),4,std::bit_cast<std::uint32_t>(1.f));
        }
        check(ReleaseMutex(mutex.value) != FALSE,"fixture mutex released");
    }
};
void channel_tests(const std::wstring &self) {
    Fixture fixture(1); fixture.write(1);
    st::Channel channel; check(channel.open(fixture.id),"channel opens existing objects");
    std::shared_ptr<const st::Frame> frame;
    check(channel.poll(frame) == st::Poll::frame,"coherent shared frame accepted");
    check(frame && frame->premultiplied[0] == 100 && frame->premultiplied[1] == 50 &&
        frame->premultiplied[3] == 128 && frame->premultiplied[4] == 0,"worker premultiplies exactly once");
    check(channel.poll(frame) == st::Poll::unchanged && !frame,"same sequence skipped");
    std::thread holder([&] {
        WaitForSingleObject(fixture.mutex.value,INFINITE); Sleep(80); ReleaseMutex(fixture.mutex.value);
    });
    Sleep(10); const auto began=st::steady_ms();
    check(channel.poll(frame) == st::Poll::busy,"busy mutex skipped");
    check(st::steady_ms()-began < 60,"mutex wait bounded"); holder.join();
    fixture.write(2); check(channel.poll(frame) == st::Poll::frame,"new frame after contention");
    fixture.write(2,2); check(channel.poll(frame) == st::Poll::closed,"closed delivered");
    check(!channel.fresh(),"closed channel hidden");
    check(!channel.open(fixture.id),"same channel cannot reopen");
    Fixture wrong(2); wrong.write(1); auto wrongid=wrong.id; ++wrongid.producer_start;
    st::Channel mismatched; check(!mismatched.open(wrongid) && mismatched.reason() == "process_identity","PID reuse identity rejected");
    Fixture small(3,256); st::Channel shortmap;
    check(!shortmap.open(small.id) && shortmap.reason() == "channel_mapping_size","short mapping refused");
    Fixture abandoned(4); abandoned.write(1);
    std::thread quitter([&] { WaitForSingleObject(abandoned.mutex.value,INFINITE); }); quitter.join();
    st::Channel orphan; check(orphan.open(abandoned.id),"abandoned fixture opens");
    check(orphan.poll(frame) == st::Poll::failed && orphan.reason() == "mutex_abandoned","abandonment terminal");
    Fixture changed(5); changed.write(1); st::Channel tampered;
    check(tampered.open(changed.id),"tamper fixture opens");
    check(tampered.poll(frame) == st::Poll::frame,"tamper baseline frame");
    WaitForSingleObject(changed.mutex.value,5); changed.data[16]^=1; ReleaseMutex(changed.mutex.value);
    check(tampered.poll(frame) == st::Poll::failed && !tampered.fresh(),"tampered identity hides immediately");
    Fixture dead(6);
    std::wstring command=L"\""+self+L"\" --child";
    STARTUPINFOW startup{}; startup.cb=sizeof(startup); PROCESS_INFORMATION process{};
    check(CreateProcessW(self.c_str(),command.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW,nullptr,nullptr,&startup,&process) != FALSE,"original non-game child started");
    st::Handle child(process.hProcess), thread(process.hThread);
    dead.id.producer_pid=process.dwProcessId; dead.id.producer_start=st::process_start(child.value); dead.write(1);
    st::Channel mortality; check(mortality.open(dead.id),"live child identity opens");
    check(mortality.poll(frame) == st::Poll::frame,"live child frame received");
    check(WaitForSingleObject(child.value,3000) == WAIT_OBJECT_0,"child exits naturally");
    check(mortality.poll(frame) == st::Poll::failed && mortality.reason() == "producer_exited" && !mortality.fresh(),"producer death hides without new frame");
    auto absent=fixture.id; absent.run[0]=absent.run[0]=='a'?'b':'a'; st::Channel missing;
    check(!missing.open(absent) && missing.reason() == "channel_missing","no creation or reconnect on missing producer");
}
void layered_channel_tests() {
    Fixture layered(101,0,3);layered.write(1,1,2);st::Channel channel;
    check(channel.open(layered.id),"layered shared mapping opens");std::shared_ptr<const st::Frame> frame;
    check(channel.poll(frame)==st::Poll::frame&&frame&&frame->header.format==2&&frame->premultiplied.size()==24,"layered coherent publication received");
    check(frame->premultiplied[0]==100&&frame->premultiplied[1]==50&&frame->premultiplied[3]==128&&frame->premultiplied[4]==0,"overlay premultiplied independently");
    check(frame->premultiplied[8]==25&&frame->premultiplied[9]==50&&frame->premultiplied[11]==64&&frame->premultiplied[12]==19,"world premultiplied independently");
    const std::array<std::uint8_t,8> expected{0,0,128,62,0,0,128,63};
    check(std::equal(expected.begin(),expected.end(),frame->premultiplied.begin()+16),"depth bytes preserved without alpha conversion");
    layered.write(2,2,2);check(channel.poll(frame)==st::Poll::closed&&!channel.fresh(),"layered normal closure");
    Fixture flat(102,0,3);flat.write(1);st::Channel flatChannel;
    check(flatChannel.open(flat.id)&&flatChannel.poll(frame)==st::Poll::frame&&frame->premultiplied.size()==8,"flat gameplay uses larger mapping without extra planes");
    Fixture tooSmall(103,st::mapping_bytes,3);st::Channel truncated;
    check(!truncated.open(tooSmall.id)&&truncated.reason()=="channel_mapping_size","gameplay rejects truncated mapping before payload reads");
    Fixture changed(104,0,3);changed.write(1,1,2);st::Channel immutable;
    check(immutable.open(changed.id)&&immutable.poll(frame)==st::Poll::frame,"layered change baseline");
    changed.write(2);check(immutable.poll(frame)==st::Poll::failed&&!immutable.fresh()&&immutable.reason()=="frame_format_changed","layered transport cannot silently downgrade");
    unsigned serial=110;
    for(float depth:{-.01f,1.01f,std::numeric_limits<float>::infinity(),std::numeric_limits<float>::quiet_NaN()}) {
        Fixture invalid(serial++,0,3);invalid.write(1,1,2,depth);st::Channel bad;
        check(bad.open(invalid.id),"invalid depth fixture opens");
        check(bad.poll(frame)==st::Poll::failed&&!frame&&!bad.fresh()&&bad.reason()=="depth_sample_invalid","nonfinite or out-of-range depth rejected");
    }
    Fixture oversize(120,0,3);oversize.write(1,1,2);
    WaitForSingleObject(oversize.mutex.value,5);put32(std::span(oversize.data,256),108,0xffffffffu);ReleaseMutex(oversize.mutex.value);
    st::Channel bounded;check(bounded.open(oversize.id),"oversize fixture opens");
    check(bounded.poll(frame)==st::Poll::failed&&bounded.reason()=="frame_dimensions","oversized layered byte count rejected before copy");
}
}
int wmain(int argc, wchar_t **argv) {
    if (argc == 2 && std::wstring_view(argv[1]) == L"--child") { Sleep(500); return 0; }
    try { contract_tests(); layered_contract_tests(); channel_tests(st::module_path()); layered_channel_tests(); std::cout << "HUD_STREAM_TESTS checks=" << checks << " PASS\n"; return 0; }
    catch (const std::exception &e) { std::cerr << "HUD_STREAM_TESTS FAIL after " << checks << ": " << e.what() << '\n'; return 1; }
}
