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
        std::cout<<checks<<" stone alignment/receipt checks passed\n";return 0;
    }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
}
