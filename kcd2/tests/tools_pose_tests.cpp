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
        std::cout<<"Tools pose parsing, camera basis conversion, explicit FOV units and validity flags passed\n";
        return 0;
    } catch(const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
}
