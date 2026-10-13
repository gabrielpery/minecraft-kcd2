#include <minecome/protocol.hpp>
#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <functional>

using namespace minecome::protocol;
static int checks=0;
void require(bool b,const char* message) {++checks;if(!b) throw std::runtime_error(message);}
void rejects(const std::function<void()>& f) {bool rejected=false;try{f();}catch(const std::runtime_error&){rejected=true;}require(rejected,"malformed data accepted");}
bool near(double a,double b) {return std::abs(a-b)<1e-9;}
int main() {
    try {
        auto h=encode_header({Type::kcd_pose,128,0x0102030405060708ULL,9});
        require(h.size()==32&&h[0]=='M'&&h[4]==1&&h[8]==3&&h[12]==128&&h[16]==8&&h[23]==1,"header byte order");
        require(decode_header(h).sequence==0x0102030405060708ULL,"header sequence");
        auto bad=h;bad[0]='X';rejects([&]{decode_header(bad);});bad=h;bad[4]=2;rejects([&]{decode_header(bad);});bad=h;bad[6]=3;rejects([&]{decode_header(bad);});bad=h;bad[10]=1;rejects([&]{decode_header(bad);});bad=h;bad[14]=2;rejects([&]{decode_header(bad);});bad=h;bad[8]=8;rejects([&]{decode_header(bad);});rejects([&]{decode_header(std::span(h).first(31));});rejects([&]{encode_header({Type::heartbeat,0,0,0});});
        Hello hello{Role::minecraft,0,"Minecraft / \xe2\x98\x83",std::string(64,'a')};auto hb=encode(hello);auto hr=decode_hello(hb);require(hr.name==hello.name&&hr.credential==hello.credential,"hello UTF8 roundtrip");
        hb.push_back(0);rejects([&]{decode_hello(hb);});rejects([&]{encode(Hello{Role::minecraft,0,"\xc0\x80",{}});});rejects([&]{encode(Hello{Role::minecraft,3,"name",{}});});
        for(auto role:{Role::minecraft,Role::kcd}) require(decode_hello(encode(Hello{role,CAP_STONE_INPUT,"input-capable",{}})).capabilities==CAP_STONE_INPUT,"capability hello roundtrip");
        rejects([&]{encode(Hello{Role::harness,CAP_STONE_INPUT,"fixture",{}});});
        const StoneInputRequest request{maximum_input_id,2};auto request_bytes=encode(request);
        require(request_bytes.size()==12&&request_bytes[0]==255&&request_bytes[6]==31&&request_bytes[7]==0&&request_bytes[8]==2,"input request wire layout");
        const auto request_back=decode_stone_input_request(request_bytes);require(request_back.id==maximum_input_id&&request_back.action==2,"exact53bit input token roundtrip");
        for(std::size_t length=0;length<12;++length) rejects([&]{decode_stone_input_request(std::span(request_bytes).first(length));});
        auto trailing_request=request_bytes;trailing_request.push_back(0);rejects([&]{decode_stone_input_request(trailing_request);});
        for(auto invalid_input:{StoneInputRequest{0,1},StoneInputRequest{maximum_input_id+1,1},StoneInputRequest{1,0},StoneInputRequest{1,3}}) rejects([&]{encode(invalid_input);});
        for(std::uint32_t code=1;code<=7;++code) {const auto result=decode_stone_input_result(encode(StoneInputResult{maximum_input_id,1,static_cast<StoneInputResultCode>(code)}));require(result.id==maximum_input_id&&result.action==1&&static_cast<std::uint32_t>(result.result)==code,"input result roundtrip");}
        auto result_bytes=encode(StoneInputResult{1,1,StoneInputResultCode::accepted});require(result_bytes.size()==16,"input result wire size");
        for(std::size_t length=0;length<16;++length) rejects([&]{decode_stone_input_result(std::span(result_bytes).first(length));});
        result_bytes.push_back(0);rejects([&]{decode_stone_input_result(result_bytes);});
        rejects([&]{encode(StoneInputResult{1,1,static_cast<StoneInputResultCode>(0)});});rejects([&]{encode(StoneInputResult{1,1,static_cast<StoneInputResultCode>(8)});});
        auto input_frame=frame(Type::stone_input_request,1,2,request_bytes,1);const auto input_header=decode_header(std::span(input_frame).first(header_size));require(input_header.minor==1&&input_header.type==Type::stone_input_request&&input_header.payload_size==12,"minor1 input frame");
        rejects([&]{frame(Type::stone_input_request,1,2,request_bytes);});rejects([&]{frame(Type::heartbeat,1,2,{},3);});
        Pose p;p.player={-123.5,2e6,17.25};p.camera={-123.5,2e6,18.87};p.kcd_origin={-123,2e6,0};p.flags=3;p.blocks_per_unit=2.5;
        auto pb=encode(p);auto pr=decode_pose(pb);require(pb.size()==128&&near(pr.player.x,p.player.x)&&near(pr.camera.z,p.camera.z)&&pr.flags==3,"pose layout/roundtrip");
        for(std::size_t i=0;i<pb.size();++i) rejects([&]{decode_pose(std::span(pb).first(i));});
        auto invalid=p;invalid.player.x=std::numeric_limits<double>::quiet_NaN();rejects([&]{encode(invalid);});invalid=p;invalid.blocks_per_unit=0;rejects([&]{encode(invalid);});invalid=p;invalid.orientation.w=2;rejects([&]{encode(invalid);});invalid=p;invalid.vertical_fov=4;rejects([&]{encode(invalid);});invalid=p;invalid.flags=16;rejects([&]{encode(invalid);});
        BlockEvent e{1,-10,64,20,"minecraft:grass_block"};auto eb=encode(e);auto er=decode_block_event(eb);require(er.x==-10&&er.block_id==e.block_id,"block signed coordinates");rejects([&]{encode(BlockEvent{1,0,0,0,"bad:foo:bar"});});rejects([&]{encode(BlockEvent{0,0,0,0,"minecraft:stone"});});
        rejects([&]{encode(BlockEvent{1,0,0,0,"bad/ns:stone"});});require(decode_block_event(encode(BlockEvent{1,0,0,0,"custom:path/stone"})).block_id=="custom:path/stone","valid registry path");
        auto m=to_minecraft({102,204,33},{100,200,30},2);require(near(m.x,4)&&near(m.y,6)&&near(m.z,-8),"basis/scale/origin conversion");
        auto k=to_kcd(m,{100,200,30},2);require(near(k.x,102)&&near(k.y,204)&&near(k.z,33),"inverse conversion");
        for(int i=-100;i<=100;++i) {Vec3 a{100.25+i*13.1,-200000.25+i*4.3,i*0.23};auto b=to_kcd(to_minecraft(a,{100,-200000,30},0.37),{100,-200000,30},0.37);require(near(a.x,b.x)&&near(a.y,b.y)&&near(a.z,b.z),"transform roundtrip");}
        rejects([&]{to_minecraft({}, {}, -1);});
        rejects([&]{to_minecraft({std::numeric_limits<double>::infinity(),0,0},{},1);});rejects([&]{to_kcd({1e308,0,0},{},1e-308);});
        Quaternion q{0.2,-0.3,0.1,std::sqrt(0.86)};auto qr=to_kcd(to_minecraft(q));require(near(q.x,qr.x)&&near(q.y,qr.y)&&near(q.z,qr.z)&&near(q.w,qr.w),"orientation roundtrip");
        constexpr double r=0.7071067811865475244;auto mc_camera=to_minecraft(Quaternion{r,0,0,r});require(near(mc_camera.x,0)&&near(mc_camera.w,1),"KCD +Y-forward +Z-up camera maps to Minecraft -Z-forward +Y-up");
        auto f=frame(Type::hello,1,2,encode(hello));require(f.size()==32+encode(hello).size(),"framing");
        std::cout<<checks<<" protocol/coordinate checks passed\n";return 0;
    } catch(const std::exception& e) {std::cerr<<"FAIL: "<<e.what()<<"\n";return 1;}
}
