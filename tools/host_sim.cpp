#include <minecome/bridge.hpp>
#include <chrono>
#include <iostream>
#include <thread>

int main(int argc,char** argv) {
    try {
        if(argc<3) {std::cerr<<"Usage: minecome_host TOKEN_FILE LOG_FILE [seconds=10] [port=38765]\nThis is a simulated host, not KCD2.\n";return 2;}
        auto seconds=argc>3?std::stoi(argv[3]):10;auto port=argc>4?std::stoi(argv[4]):38765;
        if(seconds<1||seconds>3600||port<1||port>65535) return 2;
        minecome::Bridge bridge;if(!bridge.start(argv[1],argv[2],static_cast<std::uint16_t>(port),"MineCome simulated host/0.1.0")) {std::cerr<<"Bridge failed to start; inspect log\n";return 1;}
        std::cout<<"SIMULATED KCD host listening; no engine hooks or live game\n"<<std::flush;
        auto end=std::chrono::steady_clock::now()+std::chrono::seconds(seconds);
        while(std::chrono::steady_clock::now()<end) {
            minecome::protocol::Pose p;p.player={100,200,30};p.camera={100,200,31.62};p.kcd_origin={100,200,30};p.flags=3;
            bridge.publish(p);std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }
        auto poses=bridge.received_poses(),events=bridge.received_events();bridge.stop();
        std::cout<<"received_poses="<<poses<<" received_block_events="<<events<<"\n";
        return poses>0?0:3;
    } catch(const std::exception& e) {std::cerr<<e.what()<<"\n";return 1;}
}
