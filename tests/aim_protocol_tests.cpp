// SPDX-License-Identifier: GPL-3.0-or-later
#include <minecome/protocol.hpp>
#include <functional>
#include <fstream>
#include <iostream>
#include <limits>
#include <map>
#include <sstream>
#include <stdexcept>
using namespace minecome::protocol;
namespace {
int checks=0;
void require(bool value,const char* message) {++checks;if(!value) throw std::runtime_error(message);}
void rejects(const std::function<void()>& action) {bool bad=false;try {action();}catch(const std::runtime_error&) {bad=true;}require(bad,"malformed aimed data accepted");}
template<class Decode> void malformed(const Bytes& bytes,Decode decode) {
    for(std::size_t n=0;n<bytes.size();++n) rejects([&]{decode(std::span(bytes).first(n));});
    auto extra=bytes;extra.push_back(0);rejects([&]{decode(extra);});
}
}
int main(int argc,char** argv) {
    try {
        require(argc==2,"golden fixture required");std::ifstream file(argv[1]);require(static_cast<bool>(file),"golden fixture unavailable");
        std::map<std::string,Bytes> golden;std::string line;
        while(std::getline(file,line)) {if(line.empty()||line[0]=='#') continue;std::istringstream in(line);std::string name,hex;in>>name>>hex;Bytes bytes;for(std::size_t i=0;i<hex.size();i+=2) bytes.push_back(static_cast<std::uint8_t>(std::stoul(hex.substr(i,2),nullptr,16)));require(golden.emplace(name,bytes).second,"duplicate golden");}
        AimedArena arena{maximum_input_id,{-10,-58.38,2},{120,2040,56},1,{-8,-60,2},{-10,-62,0},{-6,-58,4}};
        AimPermit permit{maximum_input_id,maximum_input_id-1};
        AimedStoneRequest request{maximum_input_id,maximum_input_id-2,maximum_input_id-1,2,AimOcclusion::hit,{120,2040,56},{1,0,0},4.5,3.25};
        AimedStoneResult result{maximum_input_id,maximum_input_id-2,2,AimedStoneResultCode::confirmed};
        require(encode(arena)==golden.at("arena")&&encode(arena).size()==100,"arena shared golden mismatch");
        require(encode(permit)==golden.at("permit")&&encode(permit).size()==16,"permit shared golden mismatch");
        require(encode(request)==golden.at("request")&&encode(request).size()==96,"request shared golden mismatch");
        require(encode(result)==golden.at("result")&&encode(result).size()==24,"result shared golden mismatch");
        require(encode(decode_aimed_arena(golden.at("arena")))==golden.at("arena"),"arena roundtrip");
        require(encode(decode_aim_permit(golden.at("permit")))==golden.at("permit"),"permit roundtrip");
        require(encode(decode_aimed_stone_request(golden.at("request")))==golden.at("request"),"request roundtrip");
        require(encode(decode_aimed_stone_result(golden.at("result")))==golden.at("result"),"result roundtrip");
        malformed(encode(arena),decode_aimed_arena);malformed(encode(permit),decode_aim_permit);malformed(encode(request),decode_aimed_stone_request);malformed(encode(result),decode_aimed_stone_result);
        for(auto id:{0ULL,maximum_input_id+1}) {
            auto a=arena;a.arena_id=id;rejects([&]{encode(a);});auto p=permit;p.permit_id=id;rejects([&]{encode(p);});p=permit;p.arena_id=id;rejects([&]{encode(p);});
            for(int field=0;field<3;++field) {auto r=request;if(field==0) r.arena_id=id;else if(field==1) r.request_id=id;else r.permit_id=id;rejects([&]{encode(r);});}
        }
        for(double bad:{0.0,-1.0,2.0,std::numeric_limits<double>::infinity(),std::numeric_limits<double>::quiet_NaN()}) {auto a=arena;a.blocks_per_unit=bad;rejects([&]{encode(a);});}
        auto a=arena;a.maximum.x++;rejects([&]{encode(a);});a=arena;a.minimum.y--;rejects([&]{encode(a);});a=arena;a.seed.z=std::numeric_limits<int>::max();rejects([&]{encode(a);});
        a=arena;a.kcd_anchor.x=1e7;rejects([&]{encode(a);});a=arena;a.minecraft_anchor.z=std::numeric_limits<double>::quiet_NaN();rejects([&]{encode(a);});
        for(double bad:{0.0,-1.0,4.50001,std::numeric_limits<double>::infinity(),std::numeric_limits<double>::quiet_NaN()}) {auto r=request;r.range=bad;rejects([&]{encode(r);});}
        for(double bad:{0.0,1.00001,std::numeric_limits<double>::infinity(),std::numeric_limits<double>::quiet_NaN()}) {auto r=request;r.direction.x=bad;rejects([&]{encode(r);});}
        for(auto action:{0u,3u}) {auto r=request;r.action=action;rejects([&]{encode(r);});auto s=result;s.action=action;rejects([&]{encode(s);});}
        for(auto occlusion:{AimOcclusion::clear,AimOcclusion::unavailable}) {auto r=request;r.occlusion=occlusion;rejects([&]{encode(r);});r.nearest_distance=0;require(decode_aimed_stone_request(encode(r)).occlusion==occlusion,"known-clear and unknown distinction lost");}
        for(double bad:{-1.0,4.50001,std::numeric_limits<double>::quiet_NaN()}) {auto r=request;r.nearest_distance=bad;rejects([&]{encode(r);});}
        for(unsigned code=1;code<=10;++code) {auto r=result;r.result=static_cast<AimedStoneResultCode>(code);require(encode(decode_aimed_stone_result(encode(r)))==encode(r),"result outcome changed");}
        for(unsigned code:{0u,11u}) {auto r=result;r.result=static_cast<AimedStoneResultCode>(code);rejects([&]{encode(r);});}
        for(unsigned type=1;type<=14;++type) {if(type==8||type==9) rejects([&]{frame(static_cast<Type>(type),1,1,{},2);});else require(decode_header(encode_header({static_cast<Type>(type),0,1,1,2})).minor==2,"minor2 header rejected");}
        for(auto type:{Type::arena_offer,Type::arena_ack,Type::aim_permit,Type::aimed_stone_request,Type::aimed_stone_result}) for(std::uint16_t minor:{0,1}) rejects([&]{frame(type,1,1,{},minor);});
        for(auto role:{Role::kcd,Role::minecraft}) require(decode_hello(encode(Hello{role,CAP_AIMED_STONE,"aimed",{}})).capabilities==2,"capability2 encoding");
        rejects([&]{encode(Hello{Role::harness,CAP_AIMED_STONE,"fixture",{}});});rejects([&]{encode(Hello{Role::minecraft,3,"mixed",{}});});
        std::cout<<checks<<" aimed protocol checks passed\n";return 0;
    }catch(const std::exception& e) {std::cerr<<e.what()<<'\n';return 1;}
}
