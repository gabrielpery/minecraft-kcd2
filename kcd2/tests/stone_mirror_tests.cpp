// SPDX-License-Identifier: GPL-3.0-or-later
#include <minecome/stone_mirror.hpp>
#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>
namespace {int checks=0;void check(bool ok){++checks;if(!ok)throw std::runtime_error("stone mirror check "+std::to_string(checks)+" failed");}}
int main() {
    try {
        using namespace minecome;using namespace minecome::protocol;
        Pose mc;mc.space=Space::minecraft;mc.flags=11;mc.player={10.5,64,20.5};
        Pose kcd;kcd.flags=3;kcd.player={100,200,50};kcd.camera={100,200,51.7};
        kcd.orientation={std::sqrt(0.5),0,0,std::sqrt(0.5)}; // forward +KCD Y
        const auto alignment=StoneAlignment::create(mc,kcd);check(alignment.has_value());
        check(alignment->kcd_anchor.x==100&&alignment->kcd_anchor.y==204&&alignment->kcd_anchor.z==50);
        BlockEvent event{1,11,65,21,"minecraft:stone"};auto p=alignment->map(event);check(p.has_value());
        check(p->x==100.5&&p->y==203.5&&p->z==51);
        ++event.x;auto px=alignment->map(event);check(px->x-p->x==1&&px->y==p->y&&px->z==p->z);
        --event.x;++event.z;auto pz=alignment->map(event);check(pz->y-p->y==-1&&pz->x==p->x);
        --event.z;++event.y;auto py=alignment->map(event);check(py->z-p->z==1);
        // Native bounds sweep the same eight corners as the transformed MC cell.
        for(int x=0;x<=1;++x)for(int y=0;y<=1;++y)for(int z=0;z<=1;++z) {
            const Vec3 native{p->x+x,p->y-z,p->z+y};
            check(native.x>=100.5&&native.x<=101.5&&native.y>=202.5&&native.y<=203.5&&native.z>=51&&native.z<=52);
        }
        event.operation=2;check(alignment->map(event).has_value());
        event.x=std::numeric_limits<int>::max();check(!alignment->map(event));
        event={1,11,65,21,"minecraft:dirt"};check(!alignment->map(event));
        event.block_id="minecraft:stone";event.operation=3;check(!alignment->map(event));
        mc.flags=3;check(!StoneAlignment::create(mc,kcd));mc.flags=11;
        kcd.flags=2;check(!StoneAlignment::create(mc,kcd));kcd.flags=3;
        kcd.orientation={0.5,0.5,0.5,0.5};auto turn=StoneAlignment::create(mc,kcd);
        check(turn&&turn->kcd_anchor.x==96&&turn->kcd_anchor.y==200&&turn->kcd_anchor.z==50);
        kcd.orientation={0,0,0,1};check(!StoneAlignment::create(mc,kcd));
        kcd.orientation={0,0,0,2};check(!StoneAlignment::create(mc,kcd));
        mc.player.x=std::numeric_limits<double>::quiet_NaN();check(!StoneAlignment::create(mc,kcd));
        auto r=parse_stone_receipt("prefix [MineComeBlockSession] {\"schema\":1,\"event\":\"begin\",\"session\":1800000000000000,\"result\":\"accepted\",\"owned_count\":0,\"pending_count\":0}");
        check(r&&r->event=="begin"&&r->session==1800000000000000ULL&&!r->block);
        const std::string block="[MineComeBlock] {\"schema\":1,\"event\":\"remove\",\"session\":1800000000000000,\"sequence\":57,\"operation\":2,\"mc\":{\"x\":-8,\"y\":60,\"z\":1},\"position\":null,\"result\":\"removed\",\"bounds_min\":null,\"bounds_max\":null,\"physics\":false,\"live_draw_verified\":false}";
        r=parse_stone_receipt(block);
        check(r&&r->sequence==57&&r->operation==2&&r->result=="removed"&&r->block);
        check(!parse_stone_receipt(block.substr(0,block.size()-1)));
        check(!parse_stone_receipt(block+"garbage"));
        auto malformed=block;malformed.replace(malformed.find("null"),4,"{\"x\":NaN,\"y\":0,\"z\":0}");check(!parse_stone_receipt(malformed));
        malformed=block;malformed.replace(malformed.find("null"),4,"{\"x\":1e999,\"y\":0,\"z\":0}");check(!parse_stone_receipt(malformed));
        const std::string placed="[MineComeBlock] {\"schema\":1,\"event\":\"place\",\"session\":1800000000000000,\"sequence\":58,\"operation\":1,\"mc\":{\"x\":-8,\"y\":60,\"z\":1},\"position\":{\"x\":1,\"y\":2,\"z\":3},\"result\":\"spawned\",\"bounds_min\":{\"x\":0,\"y\":-1,\"z\":0},\"bounds_max\":{\"x\":1,\"y\":0,\"z\":1},\"physics\":false,\"live_draw_verified\":false}";
        check(parse_stone_receipt(placed).has_value());
        malformed=placed;malformed.replace(malformed.find("\"bounds_min\":")+13,22,"null");check(!parse_stone_receipt(malformed));
        malformed=placed;malformed.replace(malformed.find("\"y\":-1"),6,"\"y\":-2");check(!parse_stone_receipt(malformed));
        check(!parse_stone_receipt("[MineComeBlockSession] {\"schema\":1,\"event\":\"begin\",\"session\":9007199254740992,\"result\":\"accepted\",\"owned_count\":0,\"pending_count\":0}"));
        check(!parse_stone_receipt("HTTP 200 ApplyStoneEvent"));
        check(stone_session_command("Begin",1800000000000000ULL)=="#MineCome.BeginBlockSession('1800000000000000')");
        event={1,-8,60,1,"minecraft:stone"};
        check(stone_event_command(1,57,event,{1.5,2,3})=="#MineCome.ApplyStoneEvent('1','57',1,-8,60,1,1.5,2,3)");
        check(stone_session_command("Begin",1791733572711306ULL)=="#MineCome.BeginBlockSession('1791733572711306')");
        event.x=16777216;try {stone_event_command(1,57,event,{1,2,3});check(false);}catch(const std::invalid_argument&){check(true);}
        try {stone_session_command("arbitrary",1);check(false);}catch(const std::invalid_argument&){check(true);}
        auto input=parse_stone_input_intent("prefix [MineComeInput] {\"schema\":1,\"request\":1791733572711306,\"action\":1}\r");
        check(input&&input->id==1791733572711306ULL&&input->action==1);
        check(parse_stone_input_intent("[MineComeInput] {\"schema\":1,\"request\":9007199254740991,\"action\":2}").has_value());
        for(const auto* invalid:{
            "[MineComeInput] {\"schema\":1,\"request\":0,\"action\":1}",
            "[MineComeInput] {\"schema\":1,\"request\":01,\"action\":1}",
            "[MineComeInput] {\"schema\":1,\"request\":1e3,\"action\":1}",
            "[MineComeInput] {\"schema\":1,\"request\":9007199254740992,\"action\":1}",
            "[MineComeInput] {\"schema\":1,\"request\":1,\"action\":3}",
            "[MineComeInput] {\"schema\":1,\"request\":1,\"action\":1",
            "[MineComeInput] {\"schema\":1,\"request\":1,\"action\":1}garbage",
            "[MineComeInput] {\"schema\":2,\"request\":1,\"action\":1}"}) check(!parse_stone_input_intent(invalid));
        check(!parse_stone_input_intent(std::string(1025,'x')));
        const AimedArena arena{1,{10.5,65.62,20.5},{100,200,51.7},1,{12,64,20},{10,62,18},{14,66,22}};
        auto fixed=StoneAlignment::from_arena(arena);check(fixed.has_value());
        const auto mapped=fixed->map({1,12,64,20,"minecraft:stone"});check(mapped&&std::abs(mapped->x-101.5)<1e-9&&std::abs(mapped->y-200.5)<1e-9&&std::abs(mapped->z-50.08)<1e-9);
        check(!fixed->map({1,15,64,20,"minecraft:stone"}));
        auto invalid_arena=arena;invalid_arena.blocks_per_unit=2;check(!StoneAlignment::from_arena(invalid_arena));
        const std::string run="0123456789abcdef0123456789abcdef";
        check(aimed_begin_command(run,9007199254740991ULL)=="#MineCome.BeginAimedInput('"+run+"','9007199254740991',60)");
        check(aimed_permit_command(run,{1,2})=="#MineCome.InstallAimedPermit('"+run+"','1','2')");
        check(aimed_end_command(run,1)=="#MineCome.EndAimedInput('"+run+"','1')");
        for(const auto bad_run:{"", "abc", "0123456789ABCDEF0123456789ABCDEF", "0123456789abcdef0123456789abcde'"}) {
            try {aimed_begin_command(bad_run,1);check(false);}catch(const std::invalid_argument&) {check(true);}
        }
        const std::string begin="[MineComeAimSession] {\"schema\":1,\"run\":\""+run+"\",\"arena\":\"1\",\"event\":\"begin\",\"result\":\"accepted\",\"engine_time\":10,\"expires_engine_time\":70}";
        const std::string permit="[MineComeAimPermit] {\"schema\":1,\"run\":\""+run+"\",\"arena\":\"1\",\"permit\":\"2\",\"result\":\"installed\",\"engine_time\":10,\"expires_engine_time\":10.5}";
        auto ack=parse_aimed_lua_receipt(begin);check(ack&&ack->event=="begin"&&ack->arena==1&&ack->engine_time==10);
        ack=parse_aimed_lua_receipt(permit);check(ack&&ack->event=="permit"&&ack->permit==2&&ack->expires_engine_time==10.5);
        check(parse_aimed_lua_receipt("prefix [MineComeAimSession] {\"schema\":1,\"run\":\""+run+"\",\"arena\":\"1\",\"event\":\"end\",\"result\":\"ended\",\"engine_time\":null,\"expires_engine_time\":null}\r").has_value());
        auto replace=[](std::string text,const std::string& from,const std::string& to){const auto at=text.find(from);if(at==std::string::npos)throw std::runtime_error("missing fixture token");text.replace(at,from.size(),to);return text;};
        for(const auto bad:{replace(begin,"\"arena\":\"1\"","\"arena\":\"01\""),replace(permit,"10.5","11.0"),replace(permit,"10.5","1e999"),replace(begin,"accepted","rejected"),begin+"garbage"}) check(!parse_aimed_lua_receipt(bad));
        const std::string intent="[MineComeAimInput] {\"schema\":1,\"run\":\""+run+"\",\"arena\":\"1\",\"request\":\"3\",\"permit\":\"2\",\"click\":\"3\",\"action\":2,\"result\":\"sampled\",\"reason\":\"none\",\"permit_engine_time\":10,\"engine_time\":10.1,\"completed_engine_time\":10.12,\"origin\":{\"x\":100,\"y\":200,\"z\":51.7},\"direction\":{\"x\":0.60000002384185791,\"y\":0.80000001192092896,\"z\":0},\"range\":4.5,\"occlusion\":1,\"nearest_distance\":0}";
        auto captured=parse_aimed_input_intent(intent);check(captured&&captured->request.request_id==3&&captured->click==3&&captured->request.permit_id==2);
        check(std::abs(captured->request.direction.x*captured->request.direction.x+captured->request.direction.y*captured->request.direction.y-1)<1e-9);
        check(encode(captured->request).size()==96);
        auto hit=replace(replace(intent,"\"occlusion\":1","\"occlusion\":2"),"\"nearest_distance\":0","\"nearest_distance\":2.25");
        check(parse_aimed_input_intent(hit).has_value());
        for(const auto bad:{
            replace(intent,"\"arena\":\"1\"","\"arena\":\"0\""),replace(intent,"\"permit\":\"2\"","\"permit\":\"9007199254740992\""),
            replace(intent,"\"click\":\"3\"","\"click\":\"4\""),replace(intent,"\"request\":\"3\"","\"request\":3"),
            replace(intent,"\"action\":2","\"action\":3"),replace(intent,"sampled","unavailable"),replace(intent,"none","ray_error"),
            replace(intent,"\"engine_time\":10.1","\"engine_time\":9.9"),replace(intent,"\"completed_engine_time\":10.12","\"completed_engine_time\":10.4"),
            replace(intent,"\"completed_engine_time\":10.12","\"completed_engine_time\":9.9"),replace(intent,"\"permit_engine_time\":10","\"permit_engine_time\":9"),
            replace(intent,"100","10000001"),replace(intent,"100","1e999"),replace(intent,"0.60000002384185791","0.61"),
            replace(intent,"\"range\":4.5","\"range\":5"),replace(intent,"\"occlusion\":1","\"occlusion\":0"),
            replace(intent,"\"nearest_distance\":0","\"nearest_distance\":1"),replace(hit,"2.25","4.6"),
            intent+"garbage",intent.substr(0,intent.size()-1),std::string(4097,'x')}) check(!parse_aimed_input_intent(bad));
        std::cout<<checks<<" stone alignment/receipt checks passed\n";return 0;
    }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
}
