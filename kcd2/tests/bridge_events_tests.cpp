// SPDX-License-Identifier: GPL-3.0-or-later
// Actual loopback transport tests with explicit synthetic peers; no game APIs.
#include <winsock2.h>
#include <ws2tcpip.h>
#include <minecome/bridge.hpp>

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <limits>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>

namespace {
using namespace std::chrono_literals;
using Clock=std::chrono::steady_clock;
namespace protocol=minecome::protocol;
int checks=0;
void require(bool value,const char* message) {++checks;if(!value) throw std::runtime_error(message);}
void await(const std::function<bool()>& predicate,const char* message) {
    const auto deadline=Clock::now()+3s;
    while(!predicate()) {
        if(Clock::now()>=deadline) throw std::runtime_error(message);
        std::this_thread::sleep_for(5ms);
    }
    ++checks;
}
struct Wsa {
    Wsa() {WSADATA data{};require(WSAStartup(MAKEWORD(2,2),&data)==0,"test WSAStartup failed");}
    ~Wsa() {WSACleanup();}
};
struct Socket {
    SOCKET value{INVALID_SOCKET};
    Socket()=default;
    explicit Socket(SOCKET socket):value(socket) {require(value!=INVALID_SOCKET,"test socket creation failed");}
    Socket(const Socket&)=delete;
    Socket& operator=(const Socket&)=delete;
    ~Socket() {close();}
    void close() {if(value!=INVALID_SOCKET) {closesocket(value);value=INVALID_SOCKET;}}
};
std::uint16_t free_port() {
    Socket probe(socket(AF_INET,SOCK_STREAM,IPPROTO_TCP));
    sockaddr_in address{};address.sin_family=AF_INET;address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    require(bind(probe.value,reinterpret_cast<const sockaddr*>(&address),sizeof(address))==0,"test ephemeral bind failed");
    int size=sizeof(address);
    require(getsockname(probe.value,reinterpret_cast<sockaddr*>(&address),&size)==0,"test port discovery failed");
    return ntohs(address.sin_port);
}
class Peer {
    Socket socket_;
    std::uint64_t sequence_{};
    std::uint16_t minor_{};
    protocol::Bytes read_exact(std::size_t length) {
        protocol::Bytes bytes(length);
        std::size_t used=0;
        while(used<length) {
            const auto received=recv(socket_.value,reinterpret_cast<char*>(bytes.data()+used),static_cast<int>(length-used),0);
            require(received>0,"test peer response missing or timed out");
            used+=static_cast<std::size_t>(received);
        }
        return bytes;
    }
public:
    Peer(std::uint16_t port,protocol::Role role,const std::string& token,std::uint16_t minor=0,std::uint32_t capabilities=0,bool expect_hello=true):socket_(socket(AF_INET,SOCK_STREAM,IPPROTO_TCP)),minor_(minor) {
        DWORD timeout=1500;
        setsockopt(socket_.value,SOL_SOCKET,SO_RCVTIMEO,reinterpret_cast<const char*>(&timeout),sizeof(timeout));
        setsockopt(socket_.value,SOL_SOCKET,SO_SNDTIMEO,reinterpret_cast<const char*>(&timeout),sizeof(timeout));
        BOOL no_delay=TRUE;
        setsockopt(socket_.value,IPPROTO_TCP,TCP_NODELAY,reinterpret_cast<const char*>(&no_delay),sizeof(no_delay));
        sockaddr_in address{};address.sin_family=AF_INET;address.sin_port=htons(port);address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
        require(connect(socket_.value,reinterpret_cast<const sockaddr*>(&address),sizeof(address))==0,"test peer connect failed");
        // The invalid-capability fixture deliberately tampers a valid harness payload.
        auto hello_payload=protocol::encode(protocol::Hello{role,role==protocol::Role::harness?0:capabilities,"explicit-loopback-test",token});
        if(role==protocol::Role::harness) hello_payload[4]=static_cast<std::uint8_t>(capabilities);
        send(protocol::Type::hello,hello_payload);
        if(!expect_hello) return;
        const auto header=protocol::decode_header(read_exact(protocol::header_size));
        require(header.type==protocol::Type::hello,"host did not acknowledge HELLO");
        const auto hello=protocol::decode_hello(read_exact(header.payload_size));
        require(hello.role==protocol::Role::kcd&&hello.credential.empty()&&header.minor==minor&&hello.capabilities==capabilities,"host HELLO identity/capability echo invalid");
    }
    std::uint64_t send(protocol::Type type,const protocol::Bytes& payload={}) {
        const auto sequence=++sequence_;
        const auto bytes=protocol::frame(type,sequence,sequence,payload,minor_);
        std::size_t used=0;
        while(used<bytes.size()) {
            const auto written=::send(socket_.value,reinterpret_cast<const char*>(bytes.data()+used),static_cast<int>(bytes.size()-used),0);
            require(written>0,"test peer send failed");used+=static_cast<std::size_t>(written);
        }
        return sequence;
    }
    std::pair<protocol::Header,protocol::Bytes> receive(protocol::Type expected) {
        const auto deadline=Clock::now()+2s;
        do {
            auto header=protocol::decode_header(read_exact(protocol::header_size));auto body=read_exact(header.payload_size);
            require(header.minor==minor_,"host session minor changed");
            if(header.type==expected) return {header,std::move(body)};
            require(header.type==protocol::Type::heartbeat||header.type==protocol::Type::kcd_pose,"unexpected host frame during request wait");
        } while(Clock::now()<deadline);
        throw std::runtime_error("expected input request not delivered");
    }
    bool rejected() {
        char value{};const auto count=recv(socket_.value,&value,1,0);
        return count==0||(count==SOCKET_ERROR&&WSAGetLastError()==WSAECONNRESET);
    }
    void change_minor(std::uint16_t value) {minor_=value;}
    void replay_sequence() {--sequence_;}
    void close() {socket_.close();}
};
protocol::Pose pose(double player_x,std::uint32_t flags=11) {
    protocol::Pose result;result.space=protocol::Space::minecraft;result.flags=flags;
    result.player={player_x,64,200};result.camera={player_x,65.62,200};return result;
}
protocol::BlockEvent block(std::uint32_t operation,int coordinate=1) {return {operation,coordinate,64,200,"minecraft:stone"};}
minecome::BlockEventBatch connected_reset(minecome::Bridge& bridge,protocol::Role role) {
    await([&]{return bridge.connected()&&bridge.peer_role()==role;},"authenticated session not visible");
    auto batch=bridge.drain_block_events();
    require(batch.connected&&batch.peer_role==role&&batch.reset_required&&batch.events.empty(),"new session did not require clear/ack before drain");
    require(batch.reset_reason==minecome::EventResetReason::connected,"session reset reason wrong");
    require(bridge.connection_generation()==batch.connection_generation,"session generation API disagrees with batch");
    return batch;
}
}

int wmain(int argc,wchar_t** argv) {
    try {
        require(argc==2,"usage: bridge_events_tests <fixture directory>");
        Wsa wsa;
        const auto fixture=std::filesystem::absolute(argv[1])/std::to_string(GetCurrentProcessId());
        std::filesystem::create_directories(fixture/"config");
        const std::string token(64,'c');
        const auto token_file=fixture/"config"/"bridge.token";
        std::ofstream(token_file)<<token<<'\n';
        const auto logfile=fixture/"logs"/"bridge-events.log";
        minecome::Bridge bridge;
        auto port=free_port();
        require(bridge.start(token_file,logfile,port,"MineCome explicit loopback test"),"bridge startup failed");
        const auto started=bridge.drain_block_events();
        require(started.reset_required&&!started.connected&&!started.peer_role&&started.events.empty(),"start state was not cleared");
        require(started.reset_reason==minecome::EventResetReason::started,"start reset reason wrong");

        Peer minecraft(port,protocol::Role::minecraft,token);
        const auto session=connected_reset(bridge,protocol::Role::minecraft);
        require(session.reset_generation>started.reset_generation,"reset token did not advance on connection");
        minecraft.send(protocol::Type::mc_pose,protocol::encode(pose(100)));
        const auto add_sequence=minecraft.send(protocol::Type::block_event,protocol::encode(block(1)));
        const auto remove_sequence=minecraft.send(protocol::Type::block_event,protocol::encode(block(2)));
        minecraft.send(protocol::Type::mc_pose,protocol::encode(pose(101)));
        const auto other_sequence=minecraft.send(protocol::Type::block_event,protocol::encode(block(1,2)));
        await([&]{return bridge.received_events()==3;},"ordered events were not received");
        require(bridge.drain_block_events().events.empty(),"pending reset leaked events");
        require(!bridge.acknowledge_event_reset(started.reset_generation),"obsolete reset acknowledgement accepted");
        require(bridge.acknowledge_event_reset(session.reset_generation),"current reset acknowledgement rejected");
        auto first=bridge.drain_block_events(2);
        require(first.events.size()==2,"bounded drain did not respect caller count");
        const auto original=first.events[0];
        require(original.event.operation==1&&first.events[1].event.operation==2,"add/removal order changed");
        require(original.receive_order==1&&first.events[1].receive_order==2&&original.wire_sequence==add_sequence
            &&first.events[1].wire_sequence==remove_sequence,"wire sequence or receipt order lost");
        require(original.client_pose&&original.client_pose->player.x==100&&first.events[1].client_pose
            &&first.events[1].client_pose->player.x==100,"events associated with later pose instead of receipt pose");
        require(original.peer_role==protocol::Role::minecraft&&original.connection_generation==session.connection_generation
            &&original.reset_generation==session.reset_generation&&bridge.game_write_allowed(original),"valid Minecraft receipt not gated correctly");
        auto second=bridge.drain_block_events();
        require(second.events.size()==1&&second.events[0].receive_order==3&&second.events[0].wire_sequence==other_sequence
            &&second.events[0].client_pose&&second.events[0].client_pose->player.x==101,"pose association across updates failed");
        require(bridge.drain_block_events().events.empty(),"draining replayed an event");

        minecraft.send(protocol::Type::mc_pose,protocol::encode(pose(102,0)));
        minecraft.send(protocol::Type::block_event,protocol::encode(block(2,2)));
        await([&]{return bridge.received_events()==4;},"invalid-world event not received");
        auto invalid=bridge.drain_block_events();
        require(invalid.events.size()==1&&!invalid.events[0].client_pose&&!bridge.game_write_allowed(invalid.events[0]),"invalid world pose enabled writes");
        require(!bridge.game_write_allowed(original),"old receipt enabled writes after peer left world");
        minecraft.send(protocol::Type::mc_pose,protocol::encode(pose(103)));
        await([&]{return bridge.received_poses()==4;},"freshness setup pose not received");
        std::this_thread::sleep_for(1100ms);
        minecraft.send(protocol::Type::block_event,protocol::encode(block(1,3)));
        await([&]{return bridge.received_events()==5;},"stale-pose event not received");
        auto stale=bridge.drain_block_events();
        require(stale.events.size()==1&&!stale.events[0].client_pose&&!bridge.game_write_allowed(stale.events[0])
            &&!bridge.latest_client_pose(),"pose older than one second was usable");

        minecraft.send(protocol::Type::mc_pose,protocol::encode(pose(104)));
        minecraft.send(protocol::Type::block_event,protocol::encode(block(2,3)));
        await([&]{return bridge.received_events()==6;},"disconnect setup event missing");
        minecraft.close();
        await([&]{return !bridge.connected();},"disconnect was not observed");
        auto disconnected=bridge.drain_block_events();
        require(disconnected.reset_required&&disconnected.events.empty()&&!disconnected.peer_role&&!bridge.latest_client_pose()
            &&disconnected.reset_reason==minecome::EventResetReason::disconnected,"disconnect retained queue or pose");
        require(!bridge.game_write_allowed(original),"copied previous-session receipt enabled writes after disconnect");

        Peer reconnected(port,protocol::Role::minecraft,token);
        const auto replacement=connected_reset(bridge,protocol::Role::minecraft);
        require(replacement.connection_generation>session.connection_generation&&replacement.reset_generation>disconnected.reset_generation,"reconnect reused session/reset token");
        require(bridge.acknowledge_event_reset(replacement.reset_generation),"reconnect acknowledgement failed");
        reconnected.send(protocol::Type::block_event,protocol::encode(block(1,4)));
        await([&]{return bridge.received_events()==7;},"reconnect event missing");
        auto no_pose=bridge.drain_block_events();
        require(no_pose.events.size()==1&&no_pose.events[0].receive_order==1&&!no_pose.events[0].client_pose
            &&!bridge.game_write_allowed(no_pose.events[0]),"reconnect inherited prior pose/order");
        require(!bridge.game_write_allowed(original),"previous-session receipt enabled writes after reconnect");

        reconnected.send(protocol::Type::mc_pose,protocol::encode(pose(105)));
        reconnected.send(protocol::Type::block_event,protocol::encode(block(1,5)));
        await([&]{return bridge.received_events()==8;},"overflow setup event missing");
        auto pre_overflow=bridge.drain_block_events();
        require(pre_overflow.events.size()==1&&bridge.game_write_allowed(pre_overflow.events[0]),"overflow setup receipt invalid");
        for(std::size_t i=0;i<minecome::Bridge::block_event_capacity+2;++i)
            reconnected.send(protocol::Type::block_event,protocol::encode(block(i%2?1:2,static_cast<int>(i))));
        await([&]{return bridge.received_events()==8+minecome::Bridge::block_event_capacity+2;},"overflow flood was not fully received");
        auto overflow=bridge.drain_block_events(std::numeric_limits<std::size_t>::max());
        require(overflow.reset_required&&overflow.reset_reason==minecome::EventResetReason::overflow&&overflow.events.empty()
            &&overflow.reset_generation>replacement.reset_generation,"overflow failed to invalidate bounded mailbox");
        require(!bridge.game_write_allowed(pre_overflow.events[0])&&!bridge.acknowledge_event_reset(replacement.reset_generation),"overflow failed to invalidate previously copied work");
        require(bridge.acknowledge_event_reset(overflow.reset_generation),"overflow clear/ack failed");
        auto after_overflow=bridge.drain_block_events();
        require(after_overflow.events.size()==2&&after_overflow.events[0].event.operation==2
            &&after_overflow.events[0].event.x==static_cast<int>(minecome::Bridge::block_event_capacity),"overflow triggering removal was not preserved after clear/ack");
        require(after_overflow.events[0].reset_generation==overflow.reset_generation,"post-overflow work has old reset token");

        const auto base_events=bridge.received_events();
        for(std::size_t i=0;i<100;++i) reconnected.send(protocol::Type::block_event,protocol::encode(block(1,static_cast<int>(i))));
        await([&]{return bridge.received_events()==base_events+100;},"drain bound setup failed");
        require(bridge.drain_block_events(std::numeric_limits<std::size_t>::max()).events.size()==minecome::Bridge::maximum_event_drain,"unbounded caller bypassed hard drain maximum");
        const auto stop_start=Clock::now();
        bridge.stop();
        require(Clock::now()-stop_start<2s,"transport stop was not bounded");
        const auto stopped=bridge.drain_block_events();
        require(stopped.reset_required&&stopped.reset_reason==minecome::EventResetReason::stopped&&stopped.events.empty()
            &&!stopped.connected&&!bridge.latest_client_pose(),"stop retained event state");
        require(!bridge.game_write_allowed(after_overflow.events[0]),"stopped bridge enabled copied work");
        reconnected.close();

        port=free_port();
        require(bridge.start(token_file,logfile,port,"MineCome explicit loopback test"),"bridge restart failed");
        require(bridge.drain_block_events().reset_generation>stopped.reset_generation,"restart reset IDs went backwards");
        Peer harness(port,protocol::Role::harness,token);
        const auto harness_session=connected_reset(bridge,protocol::Role::harness);
        require(harness_session.connection_generation>replacement.connection_generation,"restart reused connection generation");
        require(bridge.acknowledge_event_reset(harness_session.reset_generation),"harness session acknowledgement failed");
        harness.send(protocol::Type::mc_pose,protocol::encode(pose(200)));
        harness.send(protocol::Type::block_event,protocol::encode(block(1,6)));
        await([&]{return bridge.received_poses()==1&&bridge.received_events()==1;},"harness accounting compatibility lost");
        auto harness_batch=bridge.drain_block_events();
        require(harness_batch.peer_role==protocol::Role::harness&&harness_batch.events.size()==1
            &&harness_batch.events[0].peer_role==protocol::Role::harness&&harness_batch.events[0].client_pose
            &&!bridge.game_write_allowed(harness_batch.events[0]),"harness event could drive game writes");
        require(!bridge.input_ready()&&!bridge.request_stone_input({1,1}),"legacy harness enabled stone input");
        harness.close();await([&]{return !bridge.connected();},"harness disconnect missing");

        // Minor and capability are a single negotiated contract, never guessed.
        for(const auto invalid:std::array<std::pair<std::uint16_t,std::uint32_t>,2>{{{0,1},{1,0}}}) {
            Peer rejected(port,protocol::Role::minecraft,token,invalid.first,invalid.second,false);
            require(rejected.rejected(),"unsupported minor/capability handshake accepted");
        }
        {Peer rejected(port,protocol::Role::harness,token,1,1,false);require(rejected.rejected(),"input-capable harness handshake accepted");}
        {
            Peer legacy(port,protocol::Role::minecraft,token);auto legacy_session=connected_reset(bridge,protocol::Role::minecraft);
            require(bridge.acknowledge_event_reset(legacy_session.reset_generation),"legacy reset ACK failed");
            const auto count=bridge.received_poses()+1;legacy.send(protocol::Type::mc_pose,protocol::encode(pose(300)));
            await([&]{return bridge.received_poses()==count;},"legacy input gate pose missing");
            require(!bridge.input_ready()&&!bridge.request_stone_input({1,1}),"minor0 Minecraft enabled optional input");
            legacy.close();await([&]{return !bridge.connected();},"legacy disconnect missing");
        }
        Peer input(port,protocol::Role::minecraft,token,1,protocol::CAP_STONE_INPUT);
        const auto input_session=connected_reset(bridge,protocol::Role::minecraft);
        require(!bridge.input_ready()&&!bridge.request_stone_input({1,1}),"input enabled before reset ACK/world pose");
        require(bridge.acknowledge_event_reset(input_session.reset_generation),"input reset ACK failed");
        auto fence=[&](Peer& peer,std::uint32_t flags=11) {
            const auto count=bridge.received_poses()+1;peer.send(protocol::Type::mc_pose,protocol::encode(pose(301,flags)));
            await([&]{return bridge.received_poses()==count;},"input fixture pose fence missing");
        };
        fence(input);require(bridge.input_ready(),"negotiated fresh real Minecraft input unavailable");
        for(auto invalid:std::array<protocol::StoneInputRequest,4>{{{0,1},{protocol::maximum_input_id+1,1},{1,0},{1,3}}})
            require(!bridge.request_stone_input(invalid),"invalid input API argument queued");
        require(bridge.request_stone_input({1,1}),"valid input request refused");
        const auto dispatched=input.receive(protocol::Type::stone_input_request);
        const auto request=protocol::decode_stone_input_request(dispatched.second);
        require(request.id==1&&request.action==1,"input request changed before dispatch");
        require(!bridge.request_stone_input({1,1}),"same input ID queued twice");
        input.send(protocol::Type::stone_input_result,protocol::encode(protocol::StoneInputResult{2,1,protocol::StoneInputResultCode::accepted}));
        input.send(protocol::Type::stone_input_result,protocol::encode(protocol::StoneInputResult{1,2,protocol::StoneInputResultCode::accepted}));
        fence(input);require(bridge.drain_stone_input_results().empty(),"unmatched ID/action result accepted");
        const auto result_sequence=input.send(protocol::Type::stone_input_result,protocol::encode(protocol::StoneInputResult{1,1,protocol::StoneInputResultCode::accepted}));
        fence(input);const auto accepted=bridge.drain_stone_input_results();
        require(accepted.size()==1&&accepted[0].result.id==1&&accepted[0].result.result==protocol::StoneInputResultCode::accepted
            &&accepted[0].connection_generation==input_session.connection_generation&&accepted[0].reset_generation==input_session.reset_generation
            &&accepted[0].receive_order==1&&accepted[0].wire_sequence==result_sequence,"matching input result provenance lost");
        input.send(protocol::Type::stone_input_result,protocol::encode(protocol::StoneInputResult{1,1,protocol::StoneInputResultCode::accepted}));
        fence(input);require(bridge.drain_stone_input_results().empty(),"duplicate completion accepted");

        for(std::uint64_t id=2;id<=17;++id) require(bridge.request_stone_input({id,2}),"bounded request capacity too small");
        require(!bridge.request_stone_input({18,2}),"input queue/inflight bound bypassed");
        for(std::uint64_t id=2;id<=17;++id) require(protocol::decode_stone_input_request(input.receive(protocol::Type::stone_input_request).second).id==id,"queued input order changed");
        input.send(protocol::Type::stone_input_result,protocol::encode(protocol::StoneInputResult{2,2,protocol::StoneInputResultCode::busy}));
        fence(input);require(!bridge.request_stone_input({18,2}),"undrained result bypassed shared capacity");
        const auto busy=bridge.drain_stone_input_results(1);require(busy.size()==1&&busy[0].result.result==protocol::StoneInputResultCode::busy,"busy result changed");
        require(bridge.request_stone_input({18,2}),"draining result did not release capacity");
        require(protocol::decode_stone_input_request(input.receive(protocol::Type::stone_input_request).second).id==18,"replacement request missing");
        for(std::uint64_t id=3;id<=18;++id) input.send(protocol::Type::stone_input_result,protocol::encode(protocol::StoneInputResult{id,2,protocol::StoneInputResultCode::absent}));
        fence(input);require(bridge.drain_stone_input_results(0).empty(),"zero result drain ignored");
        const auto bounded=bridge.drain_stone_input_results(std::numeric_limits<std::size_t>::max());
        require(bounded.size()==minecome::Bridge::stone_input_capacity&&bounded.front().result.id==3&&bounded.back().result.id==18,"result mailbox order/capacity lost");

        require(bridge.request_stone_input({19,1}),"world-loss request missing");input.receive(protocol::Type::stone_input_request);
        fence(input,0);require(!bridge.input_ready(),"world loss kept input enabled");fence(input);
        input.send(protocol::Type::stone_input_result,protocol::encode(protocol::StoneInputResult{19,1,protocol::StoneInputResultCode::accepted}));
        fence(input);require(bridge.drain_stone_input_results().empty()&&!bridge.request_stone_input({19,1}),"world loss retained inflight/reused ID");
        require(bridge.request_stone_input({20,1}),"stale input setup missing");input.receive(protocol::Type::stone_input_request);
        std::this_thread::sleep_for(600ms);fence(input);std::this_thread::sleep_for(500ms);
        require(bridge.input_ready(),"fresh pose lost before isolated request-expiry test");
        input.send(protocol::Type::stone_input_result,protocol::encode(protocol::StoneInputResult{20,1,protocol::StoneInputResultCode::accepted}));
        fence(input);require(bridge.drain_stone_input_results().empty(),"expired input accepted late result");
        std::this_thread::sleep_for(1100ms);require(!bridge.input_ready(),"stale world pose allowed input");fence(input);
        require(bridge.request_stone_input({21,1}),"disconnect input setup missing");input.receive(protocol::Type::stone_input_request);
        input.close();await([&]{return !bridge.connected();},"input disconnect missing");
        require(!bridge.input_ready()&&bridge.drain_stone_input_results().empty(),"disconnect retained input state");

        Peer replacement_input(port,protocol::Role::minecraft,token,1,protocol::CAP_STONE_INPUT);
        const auto input_replacement=connected_reset(bridge,protocol::Role::minecraft);
        require(bridge.acknowledge_event_reset(input_replacement.reset_generation),"replacement input reset failed");fence(replacement_input);
        require(!bridge.request_stone_input({1,1},input_session.connection_generation,input_session.reset_generation),"obsolete tagged connection/reset input queued");
        replacement_input.send(protocol::Type::stone_input_result,protocol::encode(protocol::StoneInputResult{21,1,protocol::StoneInputResultCode::accepted}));
        fence(replacement_input);require(bridge.drain_stone_input_results().empty(),"reconnect accepted previous connection result");
        require(bridge.request_stone_input({1,1}),"new connection did not restart input ID namespace");replacement_input.receive(protocol::Type::stone_input_request);
        replacement_input.send(protocol::Type::stone_input_result,protocol::encode(protocol::StoneInputResult{1,1,protocol::StoneInputResultCode::occupied}));
        fence(replacement_input);const auto replaced_result=bridge.drain_stone_input_results();
        require(replaced_result.size()==1&&replaced_result[0].connection_generation>accepted[0].connection_generation,"reconnect result generation reused");
        require(bridge.request_stone_input({2,1}),"overflow inflight setup missing");replacement_input.receive(protocol::Type::stone_input_request);
        const auto before_flood=bridge.received_events();
        for(std::size_t i=0;i<=minecome::Bridge::block_event_capacity;++i) replacement_input.send(protocol::Type::block_event,protocol::encode(block(1,static_cast<int>(i))));
        await([&]{return bridge.received_events()==before_flood+minecome::Bridge::block_event_capacity+1;},"input overflow setup missing");
        const auto input_overflow=bridge.drain_block_events();require(input_overflow.reset_required&&!bridge.input_ready(),"overflow did not gate input");
        require(bridge.acknowledge_event_reset(input_overflow.reset_generation),"input overflow reset ACK failed");fence(replacement_input);
        replacement_input.send(protocol::Type::stone_input_result,protocol::encode(protocol::StoneInputResult{2,1,protocol::StoneInputResultCode::accepted}));
        fence(replacement_input);require(bridge.drain_stone_input_results().empty()&&!bridge.request_stone_input({2,1}),"overflow retained inflight input or reused ID");
        require(!bridge.request_stone_input({3,1},input_replacement.connection_generation,input_replacement.reset_generation),"obsolete same-connection reset input queued");
        require(bridge.request_stone_input({3,1},input_overflow.connection_generation,input_overflow.reset_generation),"current tagged input did not recover after reset");replacement_input.receive(protocol::Type::stone_input_request);
        replacement_input.send(protocol::Type::stone_input_result,protocol::encode(protocol::StoneInputResult{3,1,protocol::StoneInputResultCode::accepted}));fence(replacement_input);
        require(bridge.request_stone_input({4,1}),"cancellation inflight setup missing");replacement_input.receive(protocol::Type::stone_input_request);
        bridge.cancel_stone_inputs();require(bridge.drain_stone_input_results().empty(),"explicit cancellation retained completed receipt");
        replacement_input.send(protocol::Type::stone_input_result,protocol::encode(protocol::StoneInputResult{4,1,protocol::StoneInputResultCode::accepted}));fence(replacement_input);
        require(bridge.drain_stone_input_results().empty()&&!bridge.request_stone_input({3,1})&&!bridge.request_stone_input({4,1}),"cancellation retained inflight or allowed replayed ID");
        require(bridge.request_stone_input({5,1}),"input did not recover after cancellation");replacement_input.receive(protocol::Type::stone_input_request);
        replacement_input.replay_sequence();replacement_input.send(protocol::Type::heartbeat);
        await([&]{return !bridge.connected();},"replayed frame sequence was accepted");replacement_input.close();
        Peer wrong_minor(port,protocol::Role::minecraft,token,1,protocol::CAP_STONE_INPUT);connected_reset(bridge,protocol::Role::minecraft);
        wrong_minor.change_minor(0);wrong_minor.send(protocol::Type::heartbeat);
        await([&]{return !bridge.connected();},"changed session minor was accepted");

        // A validated result immediately followed by GOODBYE may never reach a
        // host poll. The audit survives, while all mutation queues still reset.
        Peer final_input(port,protocol::Role::minecraft,token,1,protocol::CAP_STONE_INPUT);
        const auto final_session=connected_reset(bridge,protocol::Role::minecraft);
        require(bridge.acknowledge_event_reset(final_session.reset_generation),"final receipt reset ACK failed");fence(final_input);
        const auto before_final_event=bridge.received_events();
        final_input.send(protocol::Type::block_event,protocol::encode(block(1,222)));
        await([&]{return bridge.received_events()==before_final_event+1;},"final receipt block setup missing");
        const auto final_blocks=bridge.drain_block_events();
        require(final_blocks.events.size()==1&&bridge.game_write_allowed(final_blocks.events[0]),"final receipt block setup invalid");
        require(bridge.request_stone_input({222,2}),"final receipt request refused");
        require(protocol::decode_stone_input_request(final_input.receive(protocol::Type::stone_input_request).second).id==222,"final receipt request changed");
        const auto final_sequence=final_input.send(protocol::Type::stone_input_result,protocol::encode(protocol::StoneInputResult{222,2,protocol::StoneInputResultCode::absent}));
        final_input.send(protocol::Type::goodbye);
        await([&]{return !bridge.connected();},"final receipt graceful disconnect missing");
        require(!bridge.input_ready()&&bridge.drain_stone_input_results().empty()&&!bridge.request_stone_input({223,1}),"audit repair retained disconnected input authority");
        require(!bridge.game_write_allowed(final_blocks.events[0])&&bridge.drain_block_events().reset_required,"audit repair retained disconnected game-write authority");
        bridge.stop();
        std::ifstream evidence(logfile);
        const std::string log((std::istreambuf_iterator<char>(evidence)),std::istreambuf_iterator<char>());
        require(log.find("mailbox overflow")!=std::string::npos&&log.find("peer role=harness")!=std::string::npos,"overflow/role evidence missing from log");
        std::vector<std::string> audited;
        std::istringstream lines(log);std::string line;std::size_t anchors=0;
        const std::regex receipt_pattern("^[1-9][0-9]* STONE_INPUT_AUDIT schema=1 connection=[1-9][0-9]* reset=[1-9][0-9]* order=[1-9][0-9]* sequence=[1-9][0-9]* request=[1-9][0-9]* action=[12] result=[1-7]$");
        while(std::getline(lines,line)) {
            if(line.find(" STONE_INPUT_AUDIT_SESSION ")!=std::string::npos) ++anchors;
            if(line.find(" STONE_INPUT_AUDIT ")!=std::string::npos) {
                require(std::regex_match(line,receipt_pattern),"accepted input audit format malformed");
                audited.push_back(line.substr(line.find("STONE_INPUT_AUDIT ")));
            }
        }
        auto audit_text=[](const minecome::StoneInputResultReceipt& receipt) {
            return "STONE_INPUT_AUDIT schema=1 connection="+std::to_string(receipt.connection_generation)
                +" reset="+std::to_string(receipt.reset_generation)+" order="+std::to_string(receipt.receive_order)
                +" sequence="+std::to_string(receipt.wire_sequence)+" request="+std::to_string(receipt.result.id)
                +" action="+std::to_string(receipt.result.action)+" result="+std::to_string(static_cast<unsigned>(receipt.result.result));
        };
        require(anchors==4,"audit anchor missing or emitted for unsupported/legacy peer");
        require(audited.size()==21,"duplicate, unmatched, cancelled, stale or reset-invalid result became an accepted audit");
        require(std::count(audited.begin(),audited.end(),audit_text(accepted[0]))==1,"accepted audit differs from drained receipt provenance");
        for(const auto& receipt:bounded) require(std::count(audited.begin(),audited.end(),audit_text(receipt))==1,"bounded result audit changed provenance/outcome");
        const minecome::StoneInputResultReceipt final_receipt{{222,2,protocol::StoneInputResultCode::absent},final_session.connection_generation,final_session.reset_generation,1,final_sequence};
        require(std::count(audited.begin(),audited.end(),audit_text(final_receipt))==1,"final absent result audit lost or duplicated across graceful disconnect");
        require(log.find(audit_text(final_receipt))<log.rfind("session ended: graceful peer goodbye"),"final result audit was not persisted before disconnect");

        // Minor 2 stays inaccessible to all production/default start() callers.
        port=free_port();require(bridge.start(token_file,logfile,port),"default restart failed");
        {Peer denied(port,protocol::Role::minecraft,token,2,protocol::CAP_AIMED_STONE,false);require(denied.rejected(),"default host enabled experimental aimed mode");}
        bridge.stop();port=free_port();require(bridge.start(token_file,logfile,port,"explicit aimed synthetic test",true),"aimed opt-in restart failed");
        for(const auto invalid:std::array<std::pair<std::uint16_t,std::uint32_t>,3>{{{2,0},{2,1},{1,2}}}) {
            Peer denied(port,protocol::Role::minecraft,token,invalid.first,invalid.second,false);require(denied.rejected(),"aimed mismatched negotiation accepted");
        }
        {Peer denied(port,protocol::Role::harness,token,2,2,false);require(denied.rejected(),"aimed harness enabled");}
        protocol::Pose host;host.camera={100,200,50};host.player={100,200,48.38};host.flags=11;
        auto fresh_aim=[&](Peer& peer) {bridge.publish(host);const auto count=bridge.received_poses()+1;peer.send(protocol::Type::mc_pose,protocol::encode(pose(301)));await([&]{return bridge.received_poses()==count;},"aimed pose fence missing");};
        const protocol::AimedArena offered{123,{301,65.62,200},{100,200,50},1,{303,64,200},{301,62,198},{305,66,202}};
        auto offer=[&](Peer& peer) {
            fresh_aim(peer);peer.send(protocol::Type::arena_offer,protocol::encode(offered));
            require(peer.receive(protocol::Type::arena_ack).second==protocol::encode(offered),"arena ACK changed exact bytes");
        };
        auto ready_aim=[&](Peer& peer) {
            const auto session=connected_reset(bridge,protocol::Role::minecraft);
            require(bridge.acknowledge_event_reset(session.reset_generation),"aimed reset ACK failed");offer(peer);
            await([&]{return bridge.aimed_arena().has_value();},"arena ACK did not enable aimed state");return session;
        };
        Peer aimed(port,protocol::Role::minecraft,token,2,2);
        const auto aimed_session=connected_reset(bridge,protocol::Role::minecraft);fresh_aim(aimed);
        aimed.send(protocol::Type::arena_offer,protocol::encode(offered));
        std::this_thread::sleep_for(40ms);
        require(!bridge.aimed_arena()&&!bridge.latest_aimed_permit(),"arena escaped cleanup reset gate");
        require(bridge.acknowledge_event_reset(aimed_session.reset_generation),"aimed cleanup ACK failed");
        require(aimed.receive(protocol::Type::arena_ack).second==protocol::encode(offered),"delayed arena ACK changed exact bytes");
        await([&]{return bridge.aimed_arena().has_value();},"aimed arena unavailable after reset ACK");
        require(!bridge.input_ready()&&!bridge.request_stone_input({1,2}),"aimed session enabled legacy fixed-cell input");
        aimed.send(protocol::Type::aim_permit,protocol::encode(protocol::AimPermit{123,1}));
        await([&]{return bridge.latest_aimed_permit().has_value();},"aim permit unavailable");const auto first_permit=*bridge.latest_aimed_permit();
        protocol::AimedStoneRequest aimed_request{123,1,1,2,protocol::AimOcclusion::clear,host.camera,{1,0,0},4.5,0};
        require(!bridge.request_aimed_stone(aimed_request,first_permit,first_permit.received-1ms),"pre-permit capture accepted");
        require(!bridge.request_aimed_stone(aimed_request,first_permit,Clock::now()+1s),"future capture accepted");
        auto forged=first_permit;forged.connection_generation++;require(!bridge.request_aimed_stone(aimed_request,forged,Clock::now()),"forged permit generation accepted");
        forged=first_permit;forged.reset_generation++;require(!bridge.request_aimed_stone(aimed_request,forged,Clock::now()),"forged permit reset accepted");
        forged=first_permit;forged.received-=1ms;require(!bridge.request_aimed_stone(aimed_request,forged,Clock::now()),"forged permit time accepted");
        auto wrong_request=aimed_request;wrong_request.origin.x+=1;require(!bridge.request_aimed_stone(wrong_request,first_permit,Clock::now()),"ray detached from actual eye accepted");
        require(bridge.request_aimed_stone(aimed_request,first_permit,Clock::now()),"valid aimed request rejected");
        require(aimed.receive(protocol::Type::aimed_stone_request).second==protocol::encode(aimed_request),"aimed dispatch changed immutable request");
        require(!bridge.request_aimed_stone(aimed_request,first_permit,Clock::now()),"aim permit replay accepted");
        aimed.send(protocol::Type::aimed_stone_result,protocol::encode(protocol::AimedStoneResult{123,1,2,protocol::AimedStoneResultCode::confirmed}));fresh_aim(aimed);
        const auto aimed_results=bridge.drain_aimed_results();require(aimed_results.size()==1&&aimed_results[0].connection_generation==aimed_session.connection_generation&&aimed_results[0].reset_generation==aimed_session.reset_generation&&aimed_results[0].result.result==protocol::AimedStoneResultCode::confirmed,"aimed result provenance lost");
        require(bridge.drain_block_events().events.empty(),"confirmed action result fabricated block transition");
        aimed.send(protocol::Type::aim_permit,protocol::encode(protocol::AimPermit{123,2}));fresh_aim(aimed);
        const auto expired=*bridge.latest_aimed_permit();std::this_thread::sleep_for(510ms);fresh_aim(aimed);
        aimed_request.request_id=2;aimed_request.permit_id=2;
        require(!bridge.latest_aimed_permit()&&!bridge.request_aimed_stone(aimed_request,expired,Clock::now()),"expired permit accepted with fresh poses");
        aimed.close();await([&]{return !bridge.connected();},"aimed disconnect missing");
        require(!bridge.aimed_arena()&&!bridge.latest_aimed_permit()&&bridge.drain_aimed_results().empty(),"aimed state survived disconnect");
        Peer aimed_reconnect(port,protocol::Role::minecraft,token,2,2);const auto aimed_replacement=ready_aim(aimed_reconnect);
        require(aimed_replacement.connection_generation>aimed_session.connection_generation,"aimed reconnect reused generation");
        aimed_reconnect.send(protocol::Type::aim_permit,protocol::encode(protocol::AimPermit{123,1}));fresh_aim(aimed_reconnect);
        aimed_request.request_id=1;aimed_request.permit_id=1;
        require(!bridge.request_aimed_stone(aimed_request,first_permit,Clock::now()),"reconnect accepted old permit receipt");
        auto current=*bridge.latest_aimed_permit();require(bridge.request_aimed_stone(aimed_request,current,Clock::now()),"reconnect did not allow fresh namespace");aimed_reconnect.receive(protocol::Type::aimed_stone_request);
        const auto before_aimed_event=bridge.received_events();aimed_reconnect.send(protocol::Type::block_event,protocol::encode(block(1,303)));
        await([&]{return bridge.received_events()==before_aimed_event+1;},"aimed owned event missing");
        const auto owned_receipts=bridge.drain_block_events();require(owned_receipts.events.size()==1&&bridge.game_write_allowed(owned_receipts.events[0]),"aimed event not write eligible before cancellation");
        bridge.cancel_stone_inputs();require(!bridge.aimed_arena()&&!bridge.latest_aimed_permit(),"cancellation kept aimed authority");
        require(!bridge.game_write_allowed(owned_receipts.events[0]),"copied aimed event retained write authority after cancellation");
        aimed_reconnect.send(protocol::Type::aimed_stone_result,protocol::encode(protocol::AimedStoneResult{123,1,2,protocol::AimedStoneResultCode::confirmed}));await([&]{return !bridge.connected();},"post-cancel result not rejected");aimed_reconnect.close();
        for(int violation=0;violation<16;++violation) {
            Peer invalid(port,protocol::Role::minecraft,token,2,2);
            if(violation==0) {
                auto reset=connected_reset(bridge,protocol::Role::minecraft);bridge.acknowledge_event_reset(reset.reset_generation);fresh_aim(invalid);
                invalid.send(protocol::Type::block_event,protocol::encode(block(1,303)));
            } else if(violation==1) {
                auto reset=connected_reset(bridge,protocol::Role::minecraft);bridge.acknowledge_event_reset(reset.reset_generation);fresh_aim(invalid);
                auto wrong=offered;wrong.minecraft_anchor.x+=1;invalid.send(protocol::Type::arena_offer,protocol::encode(wrong));
            } else if(violation>=14) {
                auto reset=connected_reset(bridge,protocol::Role::minecraft);bridge.acknowledge_event_reset(reset.reset_generation);fresh_aim(invalid);
                if(violation==14) {auto missing=host;missing.flags=9;bridge.publish(missing);}
                else invalid.send(protocol::Type::mc_pose,protocol::encode(pose(301,9)));
                invalid.send(protocol::Type::arena_offer,protocol::encode(offered));
            } else {
                ready_aim(invalid);
                if(violation==2) invalid.send(protocol::Type::arena_offer,protocol::encode(offered));
                if(violation==3) invalid.send(protocol::Type::aim_permit,protocol::encode(protocol::AimPermit{124,1}));
                if(violation==4) {invalid.send(protocol::Type::aim_permit,protocol::encode(protocol::AimPermit{123,1}));invalid.send(protocol::Type::aim_permit,protocol::encode(protocol::AimPermit{123,1}));}
                if(violation==5) invalid.send(protocol::Type::aimed_stone_result,protocol::encode(protocol::AimedStoneResult{123,1,2,protocol::AimedStoneResultCode::confirmed}));
                if(violation==6) invalid.send(protocol::Type::mc_pose,protocol::encode(pose(301,0)));
                if(violation==7) {for(std::uint64_t id=1;id<=17;++id) invalid.send(protocol::Type::aim_permit,protocol::encode(protocol::AimPermit{123,id}));}
                if(violation>=8) {
                    auto event=protocol::BlockEvent{1,303,64,200,"minecraft:stone"};
                    if(violation==8) event.x=306;
                    if(violation==9) event.block_id="minecraft:dirt";
                    if(violation==10) event.operation=2;
                    if(violation==11) event.x=302;
                    invalid.send(protocol::Type::block_event,protocol::encode(event));
                    if(violation==12) invalid.send(protocol::Type::block_event,protocol::encode(event));
                    if(violation==13) for(int i=0;i<16;++i) invalid.send(protocol::Type::block_event,protocol::encode(protocol::BlockEvent{1,301+i%5,62+i/5,198,"minecraft:stone"}));
                }
            }
            await([&]{return !bridge.connected();},"aimed protocol violation retained session");require(!bridge.aimed_arena()&&bridge.drain_aimed_results().empty(),"violation retained aimed authority");
        }
        bridge.stop();
        std::cout<<checks<<" native loopback event/session checks passed. Explicit synthetic peers; no games launched.\n";
        return 0;
    } catch(const std::exception& error) {std::cerr<<"FAIL: "<<error.what()<<'\n';return 1;}
}
