// SPDX-License-Identifier: GPL-3.0-or-later
#include <minecome/stone_mirror.hpp>
#include <algorithm>
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
bool valid_run(std::string_view run) {return run.size()==32&&std::all_of(run.begin(),run.end(),[](char c){return (c>='0'&&c<='9')||(c>='a'&&c<='f');});}
}
std::optional<StoneAlignment> StoneAlignment::from_arena(const protocol::AimedArena& arena) {
    try {(void)protocol::encode(arena);}catch(const std::exception&) {return {};}
    return StoneAlignment{arena.minecraft_anchor,arena.kcd_anchor,arena};
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
    if(arena&&(event.x<arena->minimum.x||event.x>arena->maximum.x||event.y<arena->minimum.y||event.y>arena->maximum.y||event.z<arena->minimum.z||event.z>arena->maximum.z)) return {};
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
std::string aimed_begin_command(std::string_view run,std::uint64_t arena) {
    if(!valid_run(run)||!valid_id(arena)) throw std::invalid_argument("invalid aimed begin command");
    return "#MineCome.BeginAimedInput('"+std::string(run)+"','"+std::to_string(arena)+"',60)";
}
std::string aimed_permit_command(std::string_view run,const protocol::AimPermit& permit) {
    if(!valid_run(run)) throw std::invalid_argument("invalid aimed permit run");(void)protocol::encode(permit);
    return "#MineCome.InstallAimedPermit('"+std::string(run)+"','"+std::to_string(permit.arena_id)+"','"+std::to_string(permit.permit_id)+"')";
}
std::string aimed_end_command(std::string_view run,std::uint64_t arena) {
    if(!valid_run(run)||!valid_id(arena)) throw std::invalid_argument("invalid aimed end command");
    return "#MineCome.EndAimedInput('"+std::string(run)+"','"+std::to_string(arena)+"')";
}
std::optional<AimedLuaReceipt> parse_aimed_lua_receipt(std::string_view line) {
    if(line.size()>4096) return {};
    static const std::string number=R"(([+-]?(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?))";
    static const std::string run=R"re("run":"([0-9a-f]{32})","arena":"([1-9][0-9]{0,15})")re";
    static const std::regex begin("\\[MineComeAimSession\\] \\{\"schema\":1,"+run+",\"event\":\"begin\",\"result\":\"accepted\",\"engine_time\":"+number+",\"expires_engine_time\":"+number+"\\}\\r?$");
    static const std::regex permit("\\[MineComeAimPermit\\] \\{\"schema\":1,"+run+",\"permit\":\"([1-9][0-9]{0,15})\",\"result\":\"installed\",\"engine_time\":"+number+",\"expires_engine_time\":"+number+"\\}\\r?$");
    static const std::regex end("\\[MineComeAimSession\\] \\{\"schema\":1,"+run+",\"event\":\"end\",\"result\":\"ended\",\"engine_time\":(?:"+number+"|null),\"expires_engine_time\":null\\}\\r?$");
    std::smatch match;const std::string text(line);
    try {
        AimedLuaReceipt result;
        if(std::regex_search(text,match,begin)) {result.event="begin";result.engine_time=std::stod(match[3]);result.expires_engine_time=std::stod(match[4]);}
        else if(std::regex_search(text,match,permit)) {result.event="permit";result.permit=std::stoull(match[3]);if(!valid_id(result.permit)) return {};result.engine_time=std::stod(match[4]);result.expires_engine_time=std::stod(match[5]);}
        else if(std::regex_search(text,match,end)) {result.event="end";result.engine_time=match[3].matched?std::stod(match[3]):0;}
        else return {};
        result.run=match[1];result.arena=std::stoull(match[2]);if(!valid_id(result.arena)) return {};
        if(!std::isfinite(result.engine_time)||result.engine_time<0||result.engine_time>1e12||!std::isfinite(result.expires_engine_time)) return {};
        if(result.event!="end") {
            const auto duration=result.expires_engine_time-result.engine_time,expected=result.event=="permit"?.5:60.;
            if(result.expires_engine_time>1e12||std::abs(duration-expected)>.001) return {};
        }
        return result;
    }catch(const std::exception&) {return {};}
}
std::optional<AimedInputIntent> parse_aimed_input_intent(std::string_view line) {
    if(line.size()>4096) return {};
    static const std::string number=R"(([+-]?(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?))";
    static const std::string vector="\\{\"x\":"+number+",\"y\":"+number+",\"z\":"+number+"\\}";
    static const std::regex pattern("\\[MineComeAimInput\\] \\{\"schema\":1,\"run\":\"([0-9a-f]{32})\",\"arena\":\"([1-9][0-9]{0,15})\",\"request\":\"([1-9][0-9]{0,15})\",\"permit\":\"([1-9][0-9]{0,15})\",\"click\":\"([1-9][0-9]{0,15})\",\"action\":([12]),\"result\":\"sampled\",\"reason\":\"none\",\"permit_engine_time\":"+number+",\"engine_time\":"+number+",\"completed_engine_time\":"+number+",\"origin\":"+vector+",\"direction\":"+vector+",\"range\":"+number+",\"occlusion\":([12]),\"nearest_distance\":"+number+"\\}\\r?$");
    std::smatch match;const std::string text(line);
    if(!std::regex_search(text,match,pattern)) return {};
    try {
        AimedInputIntent result;result.run=match[1];auto& request=result.request;
        request.arena_id=std::stoull(match[2]);request.request_id=std::stoull(match[3]);request.permit_id=std::stoull(match[4]);result.click=std::stoull(match[5]);request.action=static_cast<std::uint32_t>(std::stoul(match[6]));
        if(!valid_id(result.click)||result.click!=request.request_id) return {};
        result.permit_engine_time=std::stod(match[7]);result.engine_time=std::stod(match[8]);result.completed_engine_time=std::stod(match[9]);
        for(const auto time:{result.permit_engine_time,result.engine_time,result.completed_engine_time}) if(!std::isfinite(time)||time<0||time>1e12) return {};
        if(result.engine_time<result.permit_engine_time||result.completed_engine_time<result.engine_time||result.completed_engine_time-result.engine_time>.25||result.completed_engine_time-result.permit_engine_time>.5) return {};
        auto vec=[&](int index){return protocol::Vec3{std::stod(match[index]),std::stod(match[index+1]),std::stod(match[index+2])};};
        request.origin=vec(10);request.direction=vec(13);request.range=std::stod(match[16]);request.occlusion=static_cast<protocol::AimOcclusion>(std::stoul(match[17]));request.nearest_distance=std::stod(match[18]);
        const auto norm=request.direction.x*request.direction.x+request.direction.y*request.direction.y+request.direction.z*request.direction.z;
        if(!std::isfinite(norm)||std::abs(norm-1)>1e-5||request.range!=4.5) return {};
        // Lua uses float32 on the inspected build. Preserve its measured ray,
        // correcting only normalized-vector rounding before strict wire encoding.
        const auto length=std::sqrt(norm);request.direction.x/=length;request.direction.y/=length;request.direction.z/=length;
        (void)protocol::encode(request);return result;
    }catch(const std::exception&) {return {};}
}
}
