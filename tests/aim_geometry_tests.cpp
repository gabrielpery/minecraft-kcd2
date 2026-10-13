// SPDX-License-Identifier: GPL-3.0-or-later
#include <minecome/aim_geometry.hpp>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
using namespace minecome::aim;
namespace {
int checks;
void check(bool value,const char* message){++checks;if(!value)throw std::runtime_error(message);}
void near(double a,double b){check(std::abs(a-b)<1e-9,"geometry differs");}
void near(Vec3 a,Vec3 b){near(a.x,b.x);near(a.y,b.y);near(a.z,b.z);}
Vec3 vector(std::istringstream& row){Vec3 v;row>>v.x>>v.y>>v.z;return v;}
template<class F> void reject(F action){try{action();}catch(const std::invalid_argument&){++checks;return;}throw std::runtime_error("invalid geometry accepted");}
}
int main(int argc,char** argv){try{
    if(argc!=2)throw std::runtime_error("pass shared aim_geometry.txt path");
    std::ifstream input(argv[1]);if(!input)throw std::runtime_error("shared fixture unavailable");
    std::string line;int maps=0,rays=0,orientations=0;
    while(std::getline(input,line)){
        if(line.empty()||line[0]=='#')continue;std::istringstream row(line);std::string kind;row>>kind;
        if(kind=="map"){
            auto mc=vector(row),kcd=vector(row);double scale;row>>scale;auto p=vector(row),expected=vector(row);Alignment alignment{mc,kcd,scale};
            near(alignment.to_kcd(p),expected);near(alignment.to_minecraft(expected),p);
            Ray ray{kcd,{0,1,0},2};auto mapped=alignment.to_minecraft(ray);near(mapped.direction,{0,0,-1});near(mapped.range,2*scale);
            auto returned=alignment.to_kcd(mapped);near(returned.origin,ray.origin);near(returned.direction,ray.direction);near(returned.range,ray.range);++maps;
        }else if(kind=="forward"){
            minecome::protocol::Quaternion q;row>>q.x>>q.y>>q.z>>q.w;auto expected=vector(row);near(forward(q),expected);++orientations;
        }else if(kind=="ray"){
            auto origin=vector(row),direction=vector(row);double range;row>>range;auto lo=vector(row),hi=vector(row);double expected;int face;row>>expected>>face;
            Ray ray{origin,direction,range};auto hit=intersect(ray,Bounds{lo,hi});check(bool(hit)==(expected>=0),"golden hit/miss");
            if(hit){near(hit->distance,expected);check(int(hit->face)==face,"golden face");near(hit->point,add(origin,direction,expected));}++rays;
        }else throw std::runtime_error("unknown shared fixture kind");
        check(!row.fail(),"golden field parsing");row>>std::ws;check(row.eof(),"unexpected golden fields");
    }
    check(maps==4&&rays==14&&orientations==4,"all shared golden vectors executed");
    Vec3 zero{},direction{1,0,0};Ray ray{{-2,.5,.5},direction,4.5};
    for(double value:std::array<double,4>{0,-1,std::numeric_limits<double>::quiet_NaN(),std::numeric_limits<double>::infinity()}){
        reject([&]{Alignment ignored{zero,zero,value};});reject([&]{Ray ignored{zero,direction,value};});
    }
    reject([&]{Ray ignored{zero,zero,4.5};});reject([&]{Ray ignored{zero,{2,0,0},4.5};});reject([&]{Ray ignored{zero,direction,32.01};});
    reject([&]{Ray ignored{{1e7,0,0},direction,1};});reject([&]{Alignment ignored{{1e7+1,0,0},zero,1};});
    reject([&]{Alignment{zero,zero,std::numeric_limits<double>::denorm_min()}.to_kcd(direction);});
    reject([&]{Alignment{zero,zero,std::numeric_limits<double>::max()}.to_minecraft(direction);});
    reject([&]{Bounds ignored{zero,zero};});reject([&]{Bounds ignored{direction,zero};});
    reject([&]{forward({0,0,0,0});});reject([&]{position({std::numeric_limits<double>::quiet_NaN(),0,0});});
    Cell a{0,0,0},b{2,0,0},miss{0,2,0};std::array<Cell,3> unordered{miss,b,a},ordered{a,b,miss};
    check(nearest_owned(ray,unordered)->cell==a,"nearest owned cell");check(nearest_owned(ray,ordered)->cell==a,"order independent nearest cell");
    std::array<Cell,1> missed{miss};check(!nearest_owned(ray,missed),"unowned/intersection miss yields no target");check(!nearest_owned(ray,{}),"empty arena has no invented support");
    std::array<Cell,2> duplicate{a,a};reject([&]{nearest_owned(ray,duplicate);});
    std::vector<Cell> many;for(int i=0;i<17;++i)many.push_back({i,0,0});reject([&]{nearest_owned(ray,many);});
    std::array<Cell,1> outside{{{std::numeric_limits<int>::max(),0,0}}};reject([&]{nearest_owned(ray,outside);});
    std::array<Cell,2> shared{{{0,1,0},a}};check(nearest_owned(Ray{{-2,1,.5},direction,4.5},shared)->cell==a,"shared edge reference tie");
    std::array<Cell,1> inside{a};check(nearest_owned(Ray{{.5,.5,.5},direction,4.5},inside)->hit.inside(),"inside-origin explicitly marked");
    std::cout<<"aim_geometry_tests: "<<checks<<" checks passed; shared golden vectors=22; math only, no aiming integration.\n";return 0;
}catch(const std::exception& error){std::cerr<<error.what()<<'\n';return 1;}}
