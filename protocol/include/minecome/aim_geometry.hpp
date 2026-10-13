// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <minecome/protocol.hpp>
#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <optional>
#include <span>
#include <stdexcept>
#include <tuple>
#include <vector>

// Pure display-island geometry. This does not enable aiming or grant calibration.
namespace minecome::aim {
using protocol::Vec3;
constexpr std::size_t maximum_owned_cells=16;
constexpr double maximum_coordinate=10000000,maximum_ray_range=32;
enum class Face {down,up,north,south,west,east,inside};
inline double dot(Vec3 a,Vec3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
inline Vec3 position(Vec3 p){if(!std::isfinite(p.x)||!std::isfinite(p.y)||!std::isfinite(p.z)||std::abs(p.x)>maximum_coordinate||std::abs(p.y)>maximum_coordinate||std::abs(p.z)>maximum_coordinate)throw std::invalid_argument("aim position out of bounds");return p;}
inline void positive(double value){if(!std::isfinite(value)||value<=0)throw std::invalid_argument("expected positive finite geometry value");}
inline Vec3 add(Vec3 p,Vec3 d,double t){return {p.x+d.x*t,p.y+d.y*t,p.z+d.z*t};}
struct Ray {
    const Vec3 origin,direction;const double range;
    Ray(Vec3 o,Vec3 d,double r):origin(position(o)),direction(d),range(r){positive(r);auto norm=dot(d,d);if(!std::isfinite(norm)||std::abs(norm-1)>1e-9||r>maximum_ray_range)throw std::invalid_argument("non-unit/bounded aim ray");position(add(o,d,r));}
};
struct Alignment {
    const Vec3 minecraft_anchor,kcd_anchor;const double blocks_per_unit;
    Alignment(Vec3 mc,Vec3 kcd,double scale):minecraft_anchor(position(mc)),kcd_anchor(position(kcd)),blocks_per_unit(scale){positive(scale);}
    Vec3 to_kcd(Vec3 p)const{position(p);return position({kcd_anchor.x+(p.x-minecraft_anchor.x)/blocks_per_unit,kcd_anchor.y-(p.z-minecraft_anchor.z)/blocks_per_unit,kcd_anchor.z+(p.y-minecraft_anchor.y)/blocks_per_unit});}
    Vec3 to_minecraft(Vec3 p)const{position(p);return position({minecraft_anchor.x+(p.x-kcd_anchor.x)*blocks_per_unit,minecraft_anchor.y+(p.z-kcd_anchor.z)*blocks_per_unit,minecraft_anchor.z-(p.y-kcd_anchor.y)*blocks_per_unit});}
    Ray to_minecraft(const Ray& r)const{return {to_minecraft(r.origin),{r.direction.x,r.direction.z,-r.direction.y},r.range*blocks_per_unit};}
    Ray to_kcd(const Ray& r)const{return {to_kcd(r.origin),{r.direction.x,-r.direction.z,r.direction.y},r.range/blocks_per_unit};}
};
struct Bounds {
    const Vec3 minimum,maximum;
    Bounds(Vec3 lo,Vec3 hi):minimum(position(lo)),maximum(position(hi)){if(lo.x>=hi.x||lo.y>=hi.y||lo.z>=hi.z)throw std::invalid_argument("empty aim bounds");}
};
struct Cell {
    int x,y,z;
    Bounds bounds()const{return {{double(x),double(y),double(z)},{double(x)+1,double(y)+1,double(z)+1}};}
    bool operator==(const Cell&)const=default;
};
struct Hit {double distance;Vec3 point;Face face;bool inside()const{return face==Face::inside;}};
struct Pick {Cell cell;Hit hit;};
// The wire camera basis remains +X right, +Y up, -Z forward.
inline Vec3 forward(protocol::Quaternion q){
    auto norm=q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w;
    if(!std::isfinite(norm)||std::abs(norm-1)>0.001)throw std::invalid_argument("invalid camera quaternion");
    Vec3 f{-2*(q.x*q.z+q.w*q.y),-2*(q.y*q.z-q.w*q.x),-(1-2*(q.x*q.x+q.y*q.y))};
    auto n=std::sqrt(dot(f,f));if(!std::isfinite(n)||n<1e-8)throw std::invalid_argument("invalid camera forward");return {f.x/n,f.y/n,f.z/n};
}
// Reference only: actual Minecraft interactions must use World.raycast OUTLINE.
inline std::optional<Hit> intersect(const Ray& ray,const Bounds& box){
    std::array<double,3> origin{ray.origin.x,ray.origin.y,ray.origin.z},direction{ray.direction.x,ray.direction.y,ray.direction.z},lo{box.minimum.x,box.minimum.y,box.minimum.z},hi{box.maximum.x,box.maximum.y,box.maximum.z};
    constexpr std::array<Face,3> lower{Face::west,Face::down,Face::north},upper{Face::east,Face::up,Face::south};
    double near=-std::numeric_limits<double>::infinity(),far=ray.range;Face face=Face::inside;
    for(std::size_t axis=0;axis<3;++axis){
        if(direction[axis]==0){if(origin[axis]<lo[axis]||origin[axis]>hi[axis])return {};continue;}
        double a=(lo[axis]-origin[axis])/direction[axis],b=(hi[axis]-origin[axis])/direction[axis];Face side=lower[axis];
        if(a>b){std::swap(a,b);side=upper[axis];}if(a>near){near=a;face=side;}far=std::min(far,b);if(near>far)return {};
    }
    if(far<0||near>ray.range)return {};double distance=std::max(0.0,near);
    return Hit{distance,add(ray.origin,ray.direction,distance),near<0?Face::inside:face};
}
// Equal-distance reference hits sort XYZ, independent of owned-list order.
inline std::optional<Pick> nearest_owned(const Ray& ray,std::span<const Cell> cells){
    if(cells.size()>maximum_owned_cells)throw std::invalid_argument("owned aim-cell bound exceeded");
    std::optional<Pick> nearest;std::vector<Cell> seen;
    for(auto cell:cells){
        if(std::find(seen.begin(),seen.end(),cell)!=seen.end())throw std::invalid_argument("duplicate owned aim cell");seen.push_back(cell);
        auto hit=intersect(ray,cell.bounds());if(!hit)continue;Pick candidate{cell,*hit};
        if(!nearest||std::tie(candidate.hit.distance,cell.x,cell.y,cell.z)<std::tie(nearest->hit.distance,nearest->cell.x,nearest->cell.y,nearest->cell.z))nearest=candidate;
    }
    return nearest;
}
}
