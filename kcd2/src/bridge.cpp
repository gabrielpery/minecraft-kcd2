#include <winsock2.h>
#include <ws2tcpip.h>
#include <minecome/bridge.hpp>
#include <algorithm>
#include <chrono>
#include <iomanip>
#include <stdexcept>

namespace minecome {
namespace {
using Clock=std::chrono::steady_clock;
using namespace std::chrono_literals;
struct Socket {
    SOCKET value{INVALID_SOCKET};
    explicit Socket(SOCKET s=INVALID_SOCKET):value(s) {}
    ~Socket() { if(value!=INVALID_SOCKET) closesocket(value); }
    Socket(const Socket&)=delete; Socket& operator=(const Socket&)=delete;
};
struct Wsa {
    WSADATA data{}; bool ok{};
    Wsa():ok(WSAStartup(MAKEWORD(2,2),&data)==0) {}
    ~Wsa() { if(ok) WSACleanup(); }
};
bool ready(SOCKET s,bool write,long milliseconds) {
    fd_set f; FD_ZERO(&f);FD_SET(s,&f); timeval t{milliseconds/1000,(milliseconds%1000)*1000};
    int r=select(0,write?nullptr:&f,write?&f:nullptr,nullptr,&t);
    if(r==SOCKET_ERROR) throw std::runtime_error("socket select failed"); return r>0;
}
void nonblocking(SOCKET s) { u_long mode=1;if(ioctlsocket(s,FIONBIO,&mode)==SOCKET_ERROR) throw std::runtime_error("nonblocking setup failed"); }
std::uint64_t time_us() { return static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(Clock::now().time_since_epoch()).count()); }
void send_all(SOCKET s,const protocol::Bytes& b,std::stop_token stop) {
    std::size_t p=0;auto deadline=Clock::now()+500ms;
    while(p<b.size()) {
        if(stop.stop_requested()||Clock::now()>deadline) throw std::runtime_error("send cancelled or timed out");
        if(!ready(s,true,25)) continue;
        int n=send(s,reinterpret_cast<const char*>(b.data()+p),static_cast<int>(b.size()-p),0);
        if(n==SOCKET_ERROR) {if(WSAGetLastError()==WSAEWOULDBLOCK) continue;throw std::runtime_error("send failed");}
        if(n<=0) throw std::runtime_error("peer closed during send");p+=static_cast<std::size_t>(n);
    }
}
bool credential_matches(const std::string& a,const std::string& b) {
    if(a.size()!=64||b.size()!=64) return false; unsigned d=0;for(std::size_t i=0;i<64;++i) d|=static_cast<unsigned char>(a[i])^static_cast<unsigned char>(b[i]);return d==0;
}
bool valid_world_pose(const protocol::Pose& pose) {
    constexpr std::uint32_t required_flags=1u|8u; // HAS_PLAYER | IN_WORLD
    return pose.space==protocol::Space::minecraft&&(pose.flags&required_flags)==required_flags;
}
}
Bridge::~Bridge() {stop();}
bool Bridge::start(const std::filesystem::path& token_file,const std::filesystem::path& log_file,std::uint16_t port,std::string identity) {
    stop();
    std::filesystem::create_directories(log_file.parent_path());logfile_.open(log_file,std::ios::app);
    if(!logfile_) return false;
    std::ifstream input(token_file);std::getline(input,token_);if(!token_.empty()&&token_.back()=='\r') token_.pop_back();
    if(token_.size()!=64||!std::all_of(token_.begin(),token_.end(),[](char c){return (c>='0'&&c<='9')||(c>='a'&&c<='f');})||port==0) {log("invalid/missing local token or port; bridge disabled");return false;}
    try {(void)protocol::encode(protocol::Hello{protocol::Role::kcd,0,identity,{}});}catch(...) {log("invalid host identity; bridge disabled");return false;}
    identity_=std::move(identity);
    {std::lock_guard l(mailbox_);host_pose_.reset();host_generation_=0;peer_role_.reset();reset_events_locked(EventResetReason::started);}
    poses_=0;events_=0;std::promise<bool> promise;auto future=promise.get_future();
    worker_=std::jthread([this,port,p=std::move(promise)](std::stop_token s) mutable {run(s,port,std::move(p));});
    if(!future.get()) {stop();return false;}return true;
}
void Bridge::stop() {
    if(worker_.joinable()) {worker_.request_stop();worker_.join();}
    {std::lock_guard l(mailbox_);connected_=false;peer_role_.reset();reset_events_locked(EventResetReason::stopped);}
    if(logfile_.is_open()) {log("bridge stopped");logfile_.close();}token_.clear();
}
void Bridge::log(const std::string& msg) {
    std::lock_guard l(log_mutex_);logfile_<<time_us()<<" "<<msg<<"\n";logfile_.flush();
}
void Bridge::publish(const protocol::Pose& p) {
    (void)protocol::encode(p);if(p.space!=protocol::Space::kcd) throw std::runtime_error("host pose must use KCD space");
    std::lock_guard l(mailbox_);host_pose_=p;++host_generation_;
}
std::optional<protocol::Pose> Bridge::latest_client_pose() const {std::lock_guard l(mailbox_);if(Clock::now()-client_pose_time_>1s) return std::nullopt;return client_pose_;}
void Bridge::reset_events_locked(EventResetReason reason,bool clear_pose) {
    block_events_.clear();
    clear_inputs_locked();
    if(clear_pose) {client_pose_.reset();client_pose_time_={};}
    ++event_reset_generation_;
    event_reset_required_=true;
    event_reset_reason_=reason;
}
BlockEventBatch Bridge::drain_block_events(std::size_t maximum) {
    std::lock_guard l(mailbox_);
    BlockEventBatch result;
    result.connection_generation=connection_generation_;
    result.reset_generation=event_reset_generation_;
    result.reset_reason=event_reset_reason_;
    result.reset_required=event_reset_required_;
    result.connected=connected_.load();
    result.peer_role=peer_role_;
    if(event_reset_required_||!result.connected) return result;
    const auto count=std::min({maximum,maximum_event_drain,block_events_.size()});
    result.events.reserve(count);
    for(std::size_t i=0;i<count;++i) {
        result.events.push_back(std::move(block_events_.front()));
        block_events_.pop_front();
    }
    return result;
}
bool Bridge::acknowledge_event_reset(std::uint64_t reset_generation) {
    std::lock_guard l(mailbox_);
    if(reset_generation!=event_reset_generation_) return false;
    event_reset_required_=false;
    return true;
}
std::uint64_t Bridge::connection_generation() const {std::lock_guard l(mailbox_);return connection_generation_;}
std::optional<protocol::Role> Bridge::peer_role() const {std::lock_guard l(mailbox_);return peer_role_;}
bool Bridge::game_write_allowed(const BlockEventReceipt& receipt) const {
    std::lock_guard l(mailbox_);
    return connected_.load()&&!event_reset_required_&&peer_role_==protocol::Role::minecraft
        &&receipt.peer_role==protocol::Role::minecraft&&receipt.connection_generation==connection_generation_
        &&receipt.reset_generation==event_reset_generation_&&receipt.client_pose&&valid_world_pose(*receipt.client_pose)
        &&client_pose_&&valid_world_pose(*client_pose_)&&Clock::now()-client_pose_time_<=1s;
}
void Bridge::clear_inputs_locked() {
    stone_inputs_.clear();inflight_inputs_.clear();stone_input_results_.clear();
}
bool Bridge::input_ready_locked() const {
    return connected_.load()&&!event_reset_required_&&peer_role_==protocol::Role::minecraft
        &&peer_minor_==1&&peer_capabilities_==protocol::CAP_STONE_INPUT
        &&client_pose_&&valid_world_pose(*client_pose_)&&Clock::now()-client_pose_time_<=1s;
}
bool Bridge::input_ready() const {std::lock_guard l(mailbox_);return input_ready_locked();}
bool Bridge::request_stone_input(const protocol::StoneInputRequest& input) {
    std::lock_guard l(mailbox_);
    return request_stone_input_locked(input);
}
bool Bridge::request_stone_input(const protocol::StoneInputRequest& input,std::uint64_t expected_connection,std::uint64_t expected_reset) {
    std::lock_guard l(mailbox_);
    if(expected_connection!=connection_generation_||expected_reset!=event_reset_generation_) return false;
    return request_stone_input_locked(input);
}
bool Bridge::request_stone_input_locked(const protocol::StoneInputRequest& input) {
    try {(void)protocol::encode(input);}catch(const std::exception&) {return false;}
    if(!input_ready_locked()||input.id<=last_input_id_
        ||stone_inputs_.size()+inflight_inputs_.size()+stone_input_results_.size()>=stone_input_capacity) return false;
    stone_inputs_.push_back({input,connection_generation_,event_reset_generation_,Clock::now()});
    last_input_id_=input.id;return true;
}
void Bridge::cancel_stone_inputs() {
    std::lock_guard dispatch(input_dispatch_);
    std::lock_guard l(mailbox_);clear_inputs_locked();
}
std::vector<StoneInputResultReceipt> Bridge::drain_stone_input_results(std::size_t maximum) {
    std::lock_guard l(mailbox_);
    if(!input_ready_locked()) {clear_inputs_locked();return {};}
    std::vector<StoneInputResultReceipt> result;
    const auto count=std::min({maximum,stone_input_capacity,stone_input_results_.size()});result.reserve(count);
    for(std::size_t i=0;i<count;++i) {result.push_back(stone_input_results_.front());stone_input_results_.pop_front();}
    return result;
}
void Bridge::run(std::stop_token stop,std::uint16_t port,std::promise<bool> startup) {
    bool notified=false;
    try {
        Wsa wsa;if(!wsa.ok) throw std::runtime_error("WSAStartup failed");
        Socket listener(socket(AF_INET,SOCK_STREAM,IPPROTO_TCP));if(listener.value==INVALID_SOCKET) throw std::runtime_error("listener creation failed");
        BOOL exclusive=TRUE;if(setsockopt(listener.value,SOL_SOCKET,SO_EXCLUSIVEADDRUSE,reinterpret_cast<const char*>(&exclusive),sizeof(exclusive))==SOCKET_ERROR) throw std::runtime_error("exclusive bind setup failed");
        sockaddr_in address{};address.sin_family=AF_INET;address.sin_port=htons(port);address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
        if(bind(listener.value,reinterpret_cast<const sockaddr*>(&address),sizeof(address))==SOCKET_ERROR||listen(listener.value,1)==SOCKET_ERROR) throw std::runtime_error("loopback bind/listen failed (port in use?)");
        nonblocking(listener.value);log("listening on 127.0.0.1:"+std::to_string(port));startup.set_value(true);notified=true;
        while(!stop.stop_requested()) {
            if(!ready(listener.value,false,50)) continue;
            Socket client(accept(listener.value,nullptr,nullptr));if(client.value==INVALID_SOCKET) continue;
            try {
                nonblocking(client.value);BOOL no_delay=TRUE;setsockopt(client.value,IPPROTO_TCP,TCP_NODELAY,reinterpret_cast<const char*>(&no_delay),sizeof(no_delay));
                log("local TCP peer accepted; awaiting authenticated HELLO");
                protocol::Bytes buffer;std::uint64_t sent_seq=0,received_seq=0,generation=0;
                bool handshake=false;std::uint16_t negotiated_minor=0;auto last_received=Clock::now(),last_sent=Clock::now(),last_pose=Clock::now();
                std::optional<Clock::time_point> partial_since;
                auto emit=[&](protocol::Type type,const protocol::Bytes& payload=protocol::Bytes{}) {send_all(client.value,protocol::frame(type,++sent_seq,time_us(),payload,negotiated_minor),stop);last_sent=Clock::now();};
                while(!stop.stop_requested()) {
                    if(Clock::now()-last_received>6s) throw std::runtime_error(handshake?"heartbeat expired":"HELLO timed out");
                    if(partial_since&&Clock::now()-*partial_since>6s) throw std::runtime_error("partial frame timed out");
                    if(ready(client.value,false,25)) {
                        std::array<std::uint8_t,8192> chunk{};int n=recv(client.value,reinterpret_cast<char*>(chunk.data()),static_cast<int>(chunk.size()),0);
                        if(n==0) throw std::runtime_error("peer disconnected");
                        if(n==SOCKET_ERROR) {if(WSAGetLastError()!=WSAEWOULDBLOCK) throw std::runtime_error("receive failed");}
                        else { if(buffer.empty()) partial_since=Clock::now();buffer.insert(buffer.end(),chunk.begin(),chunk.begin()+n);if(buffer.size()>protocol::max_payload+protocol::header_size+chunk.size()) throw std::runtime_error("input buffer limit"); }
                    }
                    while(buffer.size()>=protocol::header_size) {
                        auto h=protocol::decode_header(std::span(buffer).first(protocol::header_size));
                        if(buffer.size()<protocol::header_size+h.payload_size) break;
                        if(h.sequence<=received_seq) throw std::runtime_error("replayed/out-of-order sequence");received_seq=h.sequence;
                        auto body=std::span(buffer).subspan(protocol::header_size,h.payload_size);
                        if(!handshake) {
                            if(h.type!=protocol::Type::hello) throw std::runtime_error("expected HELLO");
                            auto hello=protocol::decode_hello(body);
                            if((hello.role!=protocol::Role::minecraft&&hello.role!=protocol::Role::harness)||!credential_matches(hello.credential,token_)) throw std::runtime_error("authentication rejected");
                            if(!((h.minor==0&&hello.capabilities==0)
                                ||(h.minor==1&&hello.capabilities==protocol::CAP_STONE_INPUT&&hello.role==protocol::Role::minecraft)))
                                throw std::runtime_error("unsupported minor/capability/role negotiation");
                            negotiated_minor=h.minor;
                            emit(protocol::Type::hello,protocol::encode(protocol::Hello{protocol::Role::kcd,hello.capabilities,identity_,{}}));
                            std::uint64_t audit_connection=0,audit_reset=0;
                            {
                                std::lock_guard l(mailbox_);
                                ++connection_generation_;event_receive_order_=0;input_receive_order_=0;last_input_id_=0;peer_role_=hello.role;
                                peer_minor_=negotiated_minor;peer_capabilities_=hello.capabilities;
                                reset_events_locked(EventResetReason::connected);connected_=true;
                                audit_connection=connection_generation_;audit_reset=event_reset_generation_;
                            }
                            handshake=true;
                            log(std::string("HELLO authenticated; protocol 1.")+std::to_string(negotiated_minor)+" session ready; peer role="
                                +(hello.role==protocol::Role::minecraft?"minecraft":"harness"));
                            if(negotiated_minor==1) log("STONE_INPUT_AUDIT_SESSION schema=1 connection="+std::to_string(audit_connection)
                                +" reset="+std::to_string(audit_reset));
                        } else {
                            if(h.minor!=negotiated_minor) throw std::runtime_error("session minor changed");
                            switch(h.type) {
                                case protocol::Type::heartbeat: if(!body.empty()) throw std::runtime_error("heartbeat payload must be empty");break;
                                case protocol::Type::mc_pose: {
                                    auto p=protocol::decode_pose(body);if(p.space!=protocol::Space::minecraft) throw std::runtime_error("wrong client coordinate space");
                                    {std::lock_guard l(mailbox_);if(!valid_world_pose(p)) clear_inputs_locked();client_pose_=p;client_pose_time_=Clock::now();}++poses_;if(poses_.load()==1) log("first Minecraft POSE received");break;
                                }
                                case protocol::Type::stone_input_result: {
                                    if(negotiated_minor!=1) throw std::runtime_error("input result without capability");
                                    const auto result=protocol::decode_stone_input_result(body);std::optional<StoneInputResultReceipt> accepted;
                                    {
                                        std::lock_guard l(mailbox_);
                                        const auto found=std::find_if(inflight_inputs_.begin(),inflight_inputs_.end(),[&](const PendingInput& pending) {
                                            return pending.request.id==result.id&&pending.request.action==result.action
                                                &&pending.connection_generation==connection_generation_&&pending.reset_generation==event_reset_generation_
                                                &&Clock::now()-pending.created<=1s;
                                        });
                                        if(input_ready_locked()&&found!=inflight_inputs_.end()) {
                                            accepted=StoneInputResultReceipt{result,connection_generation_,event_reset_generation_,++input_receive_order_,h.sequence};
                                            stone_input_results_.push_back(*accepted);
                                            inflight_inputs_.erase(found);
                                        }
                                    }
                                    // Audit the validated receipt before another frame can disconnect/reset the
                                    // session. This journal never grants game-write or input authority.
                                    if(accepted) log("STONE_INPUT_AUDIT schema=1 connection="+std::to_string(accepted->connection_generation)
                                        +" reset="+std::to_string(accepted->reset_generation)+" order="+std::to_string(accepted->receive_order)
                                        +" sequence="+std::to_string(accepted->wire_sequence)+" request="+std::to_string(result.id)
                                        +" action="+std::to_string(result.action)+" result="+std::to_string(static_cast<unsigned>(result.result)));
                                    log(std::string(accepted?"stone input result accepted id=":"unmatched/stale stone input result ignored id=")+std::to_string(result.id));break;
                                }
                                case protocol::Type::block_event: {
                                    auto e=protocol::decode_block_event(body);
                                    bool overflow=false;
                                    {
                                        std::lock_guard l(mailbox_);
                                        if(block_events_.size()>=block_event_capacity) {
                                            reset_events_locked(EventResetReason::overflow,false);overflow=true;
                                        }
                                        std::optional<protocol::Pose> snapshot;
                                        if(client_pose_&&valid_world_pose(*client_pose_)&&Clock::now()-client_pose_time_<=1s) snapshot=client_pose_;
                                        block_events_.push_back(BlockEventReceipt{e,connection_generation_,event_reset_generation_,
                                            ++event_receive_order_,h.sequence,*peer_role_,std::move(snapshot)});
                                    }
                                    ++events_;
                                    if(overflow) log("block-event mailbox overflow; previous events invalidated; consumer clear/re-anchor acknowledgement required");
                                    log("Minecraft block event op="+std::to_string(e.operation)+" id="+e.block_id+" xyz="+std::to_string(e.x)+","+std::to_string(e.y)+","+std::to_string(e.z));break;
                                }
                                case protocol::Type::goodbye: if(!body.empty()) throw std::runtime_error("GOODBYE payload must be empty");throw std::runtime_error("graceful peer goodbye");
                                default: throw std::runtime_error("unexpected session message");
                            }
                        }
                        last_received=Clock::now();buffer.erase(buffer.begin(),buffer.begin()+static_cast<std::ptrdiff_t>(protocol::header_size+h.payload_size));
                        partial_since=buffer.empty()?std::nullopt:std::optional{Clock::now()};
                    }
                    if(handshake) {
                        for(std::size_t count=0;count<stone_input_capacity;++count) {
                            std::lock_guard dispatch(input_dispatch_);
                            std::optional<protocol::StoneInputRequest> input;
                            {
                                std::lock_guard l(mailbox_);
                                if(!input_ready_locked()) {clear_inputs_locked();break;}
                                std::erase_if(inflight_inputs_,[](const PendingInput& pending) {return Clock::now()-pending.created>1s;});
                                while(!stone_inputs_.empty()) {
                                    auto pending=stone_inputs_.front();stone_inputs_.pop_front();
                                    if(pending.connection_generation!=connection_generation_||pending.reset_generation!=event_reset_generation_||Clock::now()-pending.created>1s) continue;
                                    input=pending.request;inflight_inputs_.push_back(pending);break;
                                }
                            }
                            if(!input) break;
                            emit(protocol::Type::stone_input_request,protocol::encode(*input));
                        }
                        std::optional<protocol::Pose> snapshot;std::uint64_t current_generation;
                        {std::lock_guard l(mailbox_);current_generation=host_generation_;if(current_generation!=generation) snapshot=host_pose_;}
                        if(snapshot&&Clock::now()-last_pose>=50ms) {emit(protocol::Type::kcd_pose,protocol::encode(*snapshot));generation=current_generation;last_pose=Clock::now();}
                        if(Clock::now()-last_sent>=1s) emit(protocol::Type::heartbeat);
                    }
                }
                if(handshake) {try{send_all(client.value,protocol::frame(protocol::Type::goodbye,++sent_seq,time_us(),{},negotiated_minor),std::stop_token{});}catch(...) {}}
            } catch(const std::exception& e) {log(std::string("session ended: ")+e.what());}
            {std::lock_guard l(mailbox_);connected_=false;peer_role_.reset();reset_events_locked(EventResetReason::disconnected);}
        }
    } catch(const std::exception& e) {log(std::string("bridge failure: ")+e.what());if(!notified) startup.set_value(false);}
    {std::lock_guard l(mailbox_);connected_=false;if(peer_role_) {peer_role_.reset();reset_events_locked(EventResetReason::disconnected);}}
}
}
