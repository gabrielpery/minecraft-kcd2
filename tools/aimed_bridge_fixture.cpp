// SPDX-License-Identifier: GPL-3.0-or-later
// Synthetic KCD coordinates; this fixture never calls or starts either game.
#include <minecome/bridge.hpp>
#include <chrono>
#include <cmath>
#include <fstream>
#include <iostream>
#include <map>
#include <thread>

int wmain(int argc,wchar_t** argv) {
    using namespace std::chrono_literals;
    namespace p=minecome::protocol;
    using Clock=std::chrono::steady_clock;
    std::filesystem::path receipt;
    minecome::Bridge bridge;
    bool passed=false,ack=false,stopped=false,owned_receipt=false;
    unsigned placed=0,removed=0,code=0;
    std::uint64_t arena_id=0,request_id=0;
    p::Cell seed{};p::Vec3 center{};
    auto write_receipt=[&] {
        if(receipt.empty()||!owned_receipt) return;
        std::ofstream out(receipt);
        out.precision(17);
        out<<"{\"schema\":1,\"kind\":\"minecome_aimed_bridge_fixture_v1\",\"result\":\""<<(passed?"passed":"failed")
           <<"\",\"arena_id\":"<<arena_id<<",\"request_id\":"<<request_id<<",\"result_code\":"<<code
           <<",\"placed\":"<<placed<<",\"removed\":"<<removed<<",\"seed\":{\"x\":"<<seed.x<<",\"y\":"<<seed.y<<",\"z\":"<<seed.z
           <<"},\"mapped_seed_center\":{\"x\":"<<center.x<<",\"y\":"<<center.y<<",\"z\":"<<center.z
           <<"},\"alignment_ack\":"<<(ack?"true":"false")<<",\"kcd_connected\":false,\"synthetic_host\":true,\"graceful_stop\":"<<(stopped?"true":"false")<<"}\n";
        if(!out) throw std::runtime_error("cannot save native receipt");
    };
    try {
        std::map<std::wstring,std::wstring> options;
        for(int i=1;i<argc;i+=2) {
            if(i+1>=argc||!options.emplace(argv[i],argv[i+1]).second) throw std::runtime_error("invalid fixture arguments");
        }
        for(const auto& [key,value]:options) if(key!=L"--token"&&key!=L"--log"&&key!=L"--receipt"&&key!=L"--port"&&key!=L"--seconds") throw std::runtime_error("unknown fixture argument");
        if(!options.contains(L"--token")||!options.contains(L"--log")||!options.contains(L"--receipt")) throw std::runtime_error("usage: --token PATH --log PATH --receipt PATH [--port N] [--seconds N]");
        receipt=options.at(L"--receipt");
        const auto port=options.contains(L"--port")?std::stoi(options.at(L"--port")):38766;
        const auto seconds=options.contains(L"--seconds")?std::stoi(options.at(L"--seconds")):200;
        if(port<1||port>65535||seconds<1||seconds>300) throw std::runtime_error("fixture bounds invalid");
        if(std::filesystem::exists(receipt)) throw std::runtime_error("receipt already exists");
        owned_receipt=true;
        if(!bridge.start(options.at(L"--token"),options.at(L"--log"),static_cast<std::uint16_t>(port),"MineCome synthetic aimed fixture/0.1.0",true)) throw std::runtime_error("bridge startup failed");
        std::cout<<"AIMED_FIXTURE_READY synthetic_host=true port="<<port<<"\n"<<std::flush;
        const auto end=Clock::now()+std::chrono::seconds(seconds);
        std::optional<minecome::AimedArenaReceipt> arena;
        std::optional<std::uint64_t> session;
        while(Clock::now()<end) {
            if(std::filesystem::exists(receipt.parent_path()/"stop.request")) throw std::runtime_error("owned fixture controller requested stop");
            p::Pose host;host.player={100,200,48.38};host.camera={100,200,50};host.flags=11;bridge.publish(host);
            auto batch=bridge.drain_block_events();
            if(batch.connected) {
                if(session&&*session!=batch.connection_generation) throw std::runtime_error("fixture cannot reconnect/retry");
                session=batch.connection_generation;
            } else if(session) throw std::runtime_error("guest disconnected before complete proof");
            if(batch.reset_required) {
                if(arena) throw std::runtime_error("fixture arena invalidated");
                if(!bridge.acknowledge_event_reset(batch.reset_generation)) throw std::runtime_error("reset ACK lost");
            }
            if(auto active=bridge.aimed_arena()) {
                if(!arena) {arena=active;ack=true;arena_id=active->arena.arena_id;seed=active->arena.seed;
                    const auto& a=active->arena;
                    center={a.kcd_anchor.x+seed.x+.5-a.minecraft_anchor.x,a.kcd_anchor.y-seed.z-.5+a.minecraft_anchor.z,a.kcd_anchor.z+seed.y+.5-a.minecraft_anchor.y};}
                else if(active->connection_generation!=arena->connection_generation||active->reset_generation!=arena->reset_generation||p::encode(active->arena)!=p::encode(arena->arena)) throw std::runtime_error("arena changed");
            }
            for(const auto& event:batch.events) {
                if(!arena||!bridge.game_write_allowed(event)||event.event.block_id!="minecraft:stone"||event.event.x!=seed.x||event.event.y!=seed.y||event.event.z!=seed.z) throw std::runtime_error("unexpected confirmed block event");
                if(event.event.operation==1) {if(placed||removed||request_id) throw std::runtime_error("duplicate/out-of-order bootstrap");++placed;}
                else {if(placed!=1||removed||request_id!=1) throw std::runtime_error("unexpected removal");++removed;}
            }
            if(arena&&placed==1&&!request_id) {
                auto permit=bridge.latest_aimed_permit();auto mc=bridge.latest_client_pose();
                if(permit&&mc) {
                    // This ray is deliberately synthetic. Its origin is the actual
                    // guest eye mapped through the acknowledged fixed alignment.
                    const auto captured=Clock::now();const auto& a=arena->arena;
                    const p::Vec3 origin{a.kcd_anchor.x+mc->camera.x-a.minecraft_anchor.x,a.kcd_anchor.y-mc->camera.z+a.minecraft_anchor.z,a.kcd_anchor.z+mc->camera.y-a.minecraft_anchor.y};
                    p::Vec3 direction{center.x-origin.x,center.y-origin.y,center.z-origin.z};
                    const auto length=std::sqrt(direction.x*direction.x+direction.y*direction.y+direction.z*direction.z);
                    if(length<=0||length>4.5) throw std::runtime_error("fixture seed out of reach");
                    direction={direction.x/length,direction.y/length,direction.z/length};
                    const p::AimedStoneRequest request{arena_id,1,permit->permit.permit_id,2,p::AimOcclusion::clear,origin,direction,4.5,0};
                    if(!bridge.request_aimed_stone(request,*permit,captured)) throw std::runtime_error("fresh aimed request refused");
                    request_id=1;
                }
            }
            for(const auto& result:bridge.drain_aimed_results()) {
                if(code||result.result.arena_id!=arena_id||result.result.request_id!=1||result.result.action!=2||result.connection_generation!=arena->connection_generation||result.reset_generation!=arena->reset_generation) throw std::runtime_error("unexpected aimed result");
                code=static_cast<unsigned>(result.result.result);
                if(code!=1) throw std::runtime_error("vanilla aimed action refused");
            }
            if(placed==1&&removed==1&&code==1) {bridge.stop();stopped=true;passed=true;write_receipt();std::cout<<"AIMED_FIXTURE_PASS synthetic_host=true\n";return 0;}
            std::this_thread::sleep_for(10ms);
        }
        throw std::runtime_error("native fixture deadline expired");
    } catch(const std::exception& e) {
        bridge.stop();std::cerr<<"AIMED_FIXTURE_FAIL "<<e.what()<<"\n";
        try {write_receipt();}catch(const std::exception& save) {std::cerr<<save.what()<<"\n";}
        return 1;
    }
}
