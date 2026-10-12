// SPDX-License-Identifier: GPL-3.0-or-later
#include <minecome/tools_pose.hpp>
#include <algorithm>
#include <cmath>
#include <numbers>
#include <regex>
#include <string>

namespace minecome {
namespace {
using protocol::Vec3;
Vec3 cross(Vec3 a, Vec3 b) { return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x}; }
std::optional<Vec3> normalized(Vec3 a) {
    const auto length=std::sqrt(a.x*a.x+a.y*a.y+a.z*a.z);
    if(!std::isfinite(length)||length<1e-8) return std::nullopt;
    return Vec3{a.x/length,a.y/length,a.z/length};
}
protocol::Quaternion quaternion(Vec3 right,Vec3 forward,Vec3 up) {
    const double m00=right.x,m01=forward.x,m02=up.x;
    const double m10=right.y,m11=forward.y,m12=up.y;
    const double m20=right.z,m21=forward.z,m22=up.z;
    protocol::Quaternion q;
    const auto trace=m00+m11+m22;
    if(trace>0) {
        const auto s=std::sqrt(trace+1)*2;
        q={ (m21-m12)/s,(m02-m20)/s,(m10-m01)/s,s/4 };
    } else if(m00>m11&&m00>m22) {
        const auto s=std::sqrt(1+m00-m11-m22)*2;
        q={s/4,(m01+m10)/s,(m02+m20)/s,(m21-m12)/s};
    } else if(m11>m22) {
        const auto s=std::sqrt(1+m11-m00-m22)*2;
        q={(m01+m10)/s,s/4,(m12+m21)/s,(m02-m20)/s};
    } else {
        const auto s=std::sqrt(1+m22-m00-m11)*2;
        q={(m02+m20)/s,(m12+m21)/s,s/4,(m10-m01)/s};
    }
    const auto length=std::sqrt(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w);
    q.x/=length;q.y/=length;q.z/=length;q.w/=length;
    return q;
}
}

std::optional<ToolsPose> parse_tools_pose(std::string_view line,FovUnit unit) {
    const auto prefix=line.find("[MineComePose] ");
    if(prefix==std::string_view::npos||line.size()>8192) return std::nullopt;
    auto json=std::string(line.substr(prefix+15));
    while(!json.empty()&&(json.back()=='\r'||json.back()=='\n')) json.pop_back();
    static const std::string number=R"(([+-]?(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?))";
    static const std::string vector="\\{\\\"x\\\":"+number+",\\\"y\\\":"+number+",\\\"z\\\":"+number+"\\}";
    static const std::regex pattern("\\{\\\"schema\\\":1,\\\"player\\\":(null|"+vector+")"
        +",\\\"camera\\\":"+vector+",\\\"forward\\\":"+vector+",\\\"up\\\":"+vector
        +",\\\"fov_raw\\\":"+number+",\\\"calibrated\\\":false\\}");
    std::smatch match;
    if(!std::regex_match(json,match,pattern)) return std::nullopt;
    try {
        auto vec=[&](int start) {return Vec3{std::stod(match[start]),std::stod(match[start+1]),std::stod(match[start+2])};};
        ToolsPose result;
        result.has_player=match[1]!="null";
        if(result.has_player) result.pose.player=vec(2);
        result.pose.camera=vec(5);
        const auto forward=normalized(vec(8));
        const auto up=normalized(vec(11));
        if(!forward||!up) return std::nullopt;
        const auto right=normalized(cross(*forward,*up));
        if(!right) return std::nullopt;
        // Wire orientation maps camera-local (+X right, +Y up, -Z forward)
        // into KCD world axes, independently of the world's Z-up convention.
        result.pose.orientation=quaternion(*right,cross(*right,*forward),
            Vec3{-forward->x,-forward->y,-forward->z});
        result.pose.vertical_fov=std::stod(match[14]);
        if(unit==FovUnit::degrees) result.pose.vertical_fov*=std::numbers::pi/180;
        result.pose.flags=result.has_player?3:2; // player/camera valid; calibration bit is clear.
        (void)protocol::encode(result.pose); // Common finite/range/quaternion validation.
        return result;
    } catch(...) { return std::nullopt; }
}
}
