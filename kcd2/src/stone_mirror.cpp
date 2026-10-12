// SPDX-License-Identifier: GPL-3.0-or-later
#include <minecome/stone_mirror.hpp>
#include <cmath>
#include <iomanip>
#include <locale>
#include <regex>
#include <sstream>
#include <stdexcept>

namespace minecome {
namespace {
constexpr std::uint64_t max_lua_integer=9007199254740991ULL;
bool bounded(protocol::Vec3 p) {
    return std::isfinite(p.x)&&std::isfinite(p.y)&&std::isfinite(p.z)
        &&std::abs(p.x)<=1e7&&std::abs(p.y)<=1e7&&std::abs(p.z)<=1e7;
}
bool valid_id(std::uint64_t value) {return value>0&&value<=max_lua_integer;}
}
std::optional<StoneAlignment> StoneAlignment::create(const protocol::Pose& mc,const protocol::Pose& kcd) {
    if(mc.space!=protocol::Space::minecraft||(mc.flags&9)!=9||!bounded(mc.player)
        ||kcd.space!=protocol::Space::kcd||(kcd.flags&3)!=3||!bounded(kcd.player)||!bounded(kcd.camera)) return {};
    const auto q=kcd.orientation;
    const auto norm=q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w;
    if(!std::isfinite(norm)||std::abs(norm-1)>0.01) return {};
    // Quaternion columns are right/up/back. Project the camera's -Z forward
    // onto KCD's horizontal XY plane. The cube itself stays axis aligned.
    const auto x=-2*(q.x*q.z+q.w*q.y),y=-2*(q.y*q.z-q.w*q.x);
    const auto horizontal=std::hypot(x,y);
    if(horizontal<0.1) return {};
    StoneAlignment result{mc.player,{kcd.camera.x+4*x/horizontal,kcd.camera.y+4*y/horizontal,kcd.player.z}};
    if(!bounded(result.kcd_anchor)) return {};
    return result;
}
std::optional<protocol::Vec3> StoneAlignment::map(const protocol::BlockEvent& event) const {
    if(event.block_id!="minecraft:stone"||(event.operation!=1&&event.operation!=2)
        ||!bounded(minecraft_anchor)||!bounded(kcd_anchor)) return {};
    const double x=event.x-minecraft_anchor.x,y=event.y-minecraft_anchor.y,z=event.z-minecraft_anchor.z;
    if(x*x+y*y+z*z>16*16) return {};
    protocol::Vec3 result{kcd_anchor.x+x,kcd_anchor.y-z,kcd_anchor.z+y};
    return bounded(result)?std::optional(result):std::nullopt;
}
std::string stone_session_command(std::string_view action,std::uint64_t session) {
    if(!valid_id(session)||(action!="Begin"&&action!="Heartbeat"&&action!="End"))
        throw std::invalid_argument("invalid stone session command");
    // The live engine's Lua numbers round like float32. Decimal text preserves
    // the full token without depending on the interpreter's lua_Number type.
    return "#MineCome."+std::string(action)+"BlockSession('"+std::to_string(session)+"')";
}
std::string stone_event_command(std::uint64_t session,std::uint64_t sequence,const protocol::BlockEvent& event,protocol::Vec3 origin) {
    if(!valid_id(session)||!valid_id(sequence)||!bounded(origin)||event.block_id!="minecraft:stone"
        ||(event.operation!=1&&event.operation!=2)||std::abs(static_cast<double>(event.x))>16777215
        ||std::abs(static_cast<double>(event.y))>16777215||std::abs(static_cast<double>(event.z))>16777215)
        throw std::invalid_argument("invalid stone event command");
    std::ostringstream command;command.imbue(std::locale::classic());command<<std::setprecision(17);
    command<<"#MineCome.ApplyStoneEvent('"<<session<<"','"<<sequence<<"',"<<event.operation<<','
        <<event.x<<','<<event.y<<','<<event.z<<','<<origin.x<<','<<origin.y<<','<<origin.z<<')';
    return command.str();
}
std::optional<StoneReceipt> parse_stone_receipt(std::string_view line) {
    if(line.size()>8192) return {};
    static const std::regex session(R"re(\[MineComeBlockSession\] \{"schema":1,"event":"(begin|heartbeat|end|cleanup|expired|timer_failed)","session":([0-9]+),"result":"([a-z_]+)","owned_count":([0-9]+),"pending_count":([0-9]+)\}\r?$)re");
    static const std::string number=R"([+-]?(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)";
    static const std::string vector="(?:null|\\{\"x\":"+number+",\"y\":"+number+",\"z\":"+number+"\\})";
    static const std::regex block(std::string(R"re(\[MineComeBlock\] \{"schema":1,"event":"(place|remove)","session":([0-9]+),"sequence":([0-9]+),"operation":([12]),"mc":\{"x":-?[0-9]+,"y":-?[0-9]+,"z":-?[0-9]+\},"position":)re")
        +vector+R"re(,"result":"([a-z_]+)","bounds_min":)re"+vector+",\"bounds_max\":"+vector
        +R"re(,"physics":false,"live_draw_verified":false\}\r?$)re");
    static const std::regex vectors("\"(position|bounds_min|bounds_max)\":(null|\\{\"x\":("+number+
        +"),\"y\":("+number+"),\"z\":("+number+")\\})");
    std::smatch match;const std::string text(line);
    try {
        StoneReceipt result;
        if(std::regex_search(text,match,session)) {
            result.event=match[1];result.session=std::stoull(match[2]);result.result=match[3];
            const auto owned=std::stoull(match[4]),pending=std::stoull(match[5]);
            if(owned>128||pending>owned) return {};
            result.owned_count=static_cast<std::uint32_t>(owned);result.pending_count=static_cast<std::uint32_t>(pending);
        } else if(std::regex_search(text,match,block)) {
            result.block=true;result.event=match[1];result.session=std::stoull(match[2]);
            result.sequence=std::stoull(match[3]);result.operation=static_cast<std::uint32_t>(std::stoul(match[4]));result.result=match[5];
            if(!valid_id(result.sequence)||(result.event=="place")!=(result.operation==1)) return {};
            std::optional<protocol::Vec3> position,minimum,maximum;
            for(auto it=std::sregex_iterator(text.begin(),text.end(),vectors);it!=std::sregex_iterator();++it) {
                if((*it)[2]=="null") continue;
                protocol::Vec3 value{std::stod((*it)[3]),std::stod((*it)[4]),std::stod((*it)[5])};
                if(!bounded(value)) return {};
                if((*it)[1]=="position") position=value;
                else if((*it)[1]=="bounds_min") minimum=value;else maximum=value;
            }
            if(result.result=="spawned"||result.result=="already_present") {
                if(result.operation!=1||!position||!minimum||!maximum||std::abs(minimum->x)>0.01
                    ||std::abs(minimum->y+1)>0.01||std::abs(minimum->z)>0.01
                    ||std::abs(maximum->x-1)>0.01||std::abs(maximum->y)>0.01||std::abs(maximum->z-1)>0.01) return {};
            }
        } else return {};
        return valid_id(result.session)?std::optional(result):std::nullopt;
    } catch(const std::exception&) {return {};}
}
std::optional<protocol::StoneInputRequest> parse_stone_input_intent(std::string_view line) {
    if(line.size()>1024) return {};
    static const std::regex intent(R"re(\[MineComeInput\] \{"schema":1,"request":([1-9][0-9]{0,15}),"action":([12])\}\r?$)re");
    std::smatch match;const std::string text(line);
    if(!std::regex_search(text,match,intent)) return {};
    try {
        const auto id=std::stoull(match[1]);
        if(!valid_id(id)) return {};
        return protocol::StoneInputRequest{id,static_cast<std::uint32_t>(std::stoul(match[2]))};
    } catch(const std::exception&) {return {};}
}
}
