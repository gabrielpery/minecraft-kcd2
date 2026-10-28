// SPDX-License-Identifier: GPL-3.0-or-later
#include <minecome/tools_pose.hpp>
#include <cmath>
#include <iostream>
#include <stdexcept>

void require(bool value,const char* message) {if(!value) throw std::runtime_error(message);}
int main() {
    try {
        const auto identity="[MineComePose] {\"schema\":1,\"player\":{\"x\":10,\"y\":20,\"z\":30},\"camera\":{\"x\":10,\"y\":20,\"z\":31.7},\"forward\":{\"x\":0,\"y\":1,\"z\":0},\"up\":{\"x\":0,\"y\":0,\"z\":1},\"fov_raw\":1.3,\"calibrated\":false}";
        auto pose=minecome::parse_tools_pose(identity,minecome::FovUnit::radians);
        require(pose&&pose->has_player&&pose->pose.flags==3,"world sample validity flags wrong");
        require(std::abs(pose->pose.orientation.w-std::sqrt(.5))<1e-9&&std::abs(pose->pose.orientation.x-std::sqrt(.5))<1e-9,"KCD forward+Y camera-local basis failed");
        const auto minecraft_orientation=minecome::protocol::to_minecraft(pose->pose.orientation);
        require(std::abs(minecraft_orientation.w-1)<1e-9&&std::abs(minecraft_orientation.x)<1e-9,"KCD forward+Y did not map to Minecraft forward-Z identity camera");
        const auto quarter_turn="[MineComePose] {\"schema\":1,\"player\":null,\"camera\":{\"x\":0,\"y\":0,\"z\":0},\"forward\":{\"x\":-1,\"y\":0,\"z\":0},\"up\":{\"x\":0,\"y\":0,\"z\":1},\"fov_raw\":75,\"calibrated\":false}";
        pose=minecome::parse_tools_pose(quarter_turn,minecome::FovUnit::degrees);
        require(pose&&!pose->has_player&&pose->pose.flags==2,"menu sample incorrectly claimed valid player");
        require(std::abs(pose->pose.orientation.x-.5)<1e-9&&std::abs(pose->pose.orientation.y-.5)<1e-9&&std::abs(pose->pose.orientation.z-.5)<1e-9&&std::abs(pose->pose.orientation.w-.5)<1e-9,"quarter turn basis quaternion failed");
        require(std::abs(pose->pose.vertical_fov-1.3089969389957472)<1e-9,"explicit degrees conversion failed");
        require(!minecome::parse_tools_pose(quarter_turn,minecome::FovUnit::radians),"invalid radian FOV accepted");
        require(!minecome::parse_tools_pose("[MineComePose] {}",minecome::FovUnit::radians),"invalid diagnostic schema accepted");
        require(!minecome::parse_tools_pose("garbage",minecome::FovUnit::radians),"non-diagnostic log accepted");
        const std::string run="0123456789abcdef0123456789abcdef";
        const std::string physical="[MineComeHudPhysicalView] {\"schema\":1,\"run\":\""+run+"\",\"seq\":1,\"result\":\"sampled\",\"physical_movement\":true,\"sampled_engine_seconds\":123.5,\"player\":{\"x\":10,\"y\":20,\"z\":30},\"camera\":{\"position\":{\"x\":10,\"y\":20,\"z\":31.7},\"forward\":{\"x\":0,\"y\":1,\"z\":0},\"up\":{\"x\":0,\"y\":0,\"z\":1},\"fov\":1.3},\"camera_basis_valid\":true}";
        auto external=minecome::parse_physical_tools_pose(physical);
        require(external&&external->sample.has_player&&external->sample.pose.flags==3&&external->run==run
            &&external->sequence==1&&external->sampled_engine_seconds==123.5,"physical sampler identity or capture metadata lost");
        const auto original=minecome::parse_tools_pose(identity,minecome::FovUnit::radians);
        require(minecome::protocol::encode(external->sample.pose)==minecome::protocol::encode(original->pose),"external pose changed captured geometry or camera basis");
        auto modified=[&](const std::string& from,const std::string& to){auto text=physical;const auto at=text.find(from);require(at!=std::string::npos,"test replacement missing");text.replace(at,from.size(),to);return text;};
        require(minecome::parse_physical_tools_pose("[Engine] "+physical+"\r\n").has_value(),"engine prefix / line ending rejected");
        require(minecome::parse_physical_tools_pose(modified("\"seq\":1,","\"seq\":1024,")).has_value(),"last sampler sequence rejected");
        require(!minecome::parse_physical_tools_pose(modified("\"seq\":1,","\"seq\":1025,")),"sampler budget exceeded");
        require(!minecome::parse_physical_tools_pose(modified("\"seq\":1,","\"seq\":0,")),"zero sample sequence accepted");
        require(!minecome::parse_physical_tools_pose(modified("\"seq\":1,","\"seq\":01,")),"invalid JSON sequence accepted");
        require(!minecome::parse_physical_tools_pose(modified("123.5","-0.1")),"negative engine clock accepted");
        require(!minecome::parse_physical_tools_pose(modified("123.5","1e999")),"nonfinite engine clock accepted");
        require(!minecome::parse_physical_tools_pose(modified("123.5","1000000000000")),"unbounded engine clock accepted");
        require(!minecome::parse_physical_tools_pose(modified("\"sampled\"","\"failed\"")),"failed sampler accepted");
        require(!minecome::parse_physical_tools_pose(modified("\"physical_movement\":true","\"physical_movement\":false")),"nonphysical sampler accepted");
        require(!minecome::parse_physical_tools_pose(modified("\"camera_basis_valid\":true","\"camera_basis_valid\":false")),"invalid basis authority accepted");
        require(!minecome::parse_physical_tools_pose(modified("31.7","33.01")),"detached camera accepted");
        require(!minecome::parse_physical_tools_pose(modified("\"forward\":{\"x\":0,\"y\":1,\"z\":0}","\"forward\":{\"x\":0,\"y\":2,\"z\":0}")),"nonunit camera basis accepted");
        require(!minecome::parse_physical_tools_pose(modified("\"up\":{\"x\":0,\"y\":0,\"z\":1}","\"up\":{\"x\":0,\"y\":1,\"z\":0}")),"parallel camera basis accepted");
        require(!minecome::parse_physical_tools_pose(modified("\"fov\":1.3","\"fov\":75")),"degrees silently accepted by external radians contract");
        require(!minecome::parse_physical_tools_pose(modified("abcdef0123456789abcdef","ABCDEF0123456789abcdef")),"noncanonical run accepted");
        require(!minecome::parse_physical_tools_pose(physical+" garbage"),"non-final physical record accepted");
        require(!minecome::parse_physical_tools_pose(physical.substr(0,physical.size()-1)),"partial physical record accepted");
        require(!minecome::parse_physical_tools_pose(identity),"legacy pose acquired external authority");
        bool bad_run_rejected=false;
        try {minecome::PhysicalPoseCursor invalid("123");} catch(const std::invalid_argument&) {bad_run_rejected=true;}
        require(bad_run_rejected,"cursor accepted unbound run");
        minecome::PhysicalPoseCursor cursor(run);
        using Decision=minecome::PhysicalPoseDecision;
        auto record=*external;
        record.run=std::string(32,'f');record.sequence=100;
        require(cursor.observe(record,true)==Decision::foreign_run,"foreign run acquired authority");
        record=*external;
        require(cursor.observe(record,true)==Decision::accepted,"first matching sample rejected");
        require(cursor.observe(record,true)==Decision::replayed_or_regressed,"same physical sample renewed authority");
        record.sequence=2;record.sampled_engine_seconds=124;
        require(cursor.observe(record,false)==Decision::stale_batch,"stale log batch acquired authority");
        require(cursor.observe(record,true)==Decision::replayed_or_regressed,"stale record replay renewed authority");
        record.sequence=3;record.sampled_engine_seconds=123.9;
        require(cursor.observe(record,true)==Decision::replayed_or_regressed,"regressed engine clock accepted");
        record.sampled_engine_seconds=124.1;
        require(cursor.observe(record,true)==Decision::replayed_or_regressed,"spent sequence reused after clock repair");
        record.sequence=4;record.sampled_engine_seconds=124.2;
        require(cursor.observe(record,true)==Decision::accepted,"fresh advancing sampler failed recovery");
        std::cout<<"Tools pose parsing, camera basis conversion, explicit FOV units and validity flags passed\n";
        std::cout<<"Physical sampler strict schema, original geometry, run binding, stale/replay/clock rejection passed\n";
        return 0;
    } catch(const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
}
