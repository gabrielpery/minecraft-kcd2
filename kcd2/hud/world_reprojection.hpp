#pragma once

#include "host_depth.hpp"

// Projection convention is checked against the reflected KCD depth equation,
// not guessed from byte offsets. Installed Shaders.pak/PostAA.cfx:1199-1200
// uses CV_ProjMatr[0][2] and [1][2] for projection jitter (column-vector form).
namespace minecome::world_reprojection {
namespace depth = minecome::host_depth;
struct transform {
    std::array<depth::vec4,4> clip{};
    depth::vec3 source_position{}, source_forward{}, source_up{};
    depth::vec3 target_position{}, target_right{}, target_forward{}, target_up{};
    std::array<float,2> source_tan_half{};
};

inline std::optional<transform> make(const depth::sample &s,const depth::expected_view &guest,
        std::uint32_t width,std::uint32_t height,std::uint64_t image_utc,std::uint64_t now) {
    // This first raster profile has one quad per source pixel. Other sizes use
    // the original strict same-view compositor, never a rescaled guessed grid.
    // The source basis describes the already-captured colour/depth image. Its
    // lease must have been valid AT CAPTURE; current-view alignment comes from
    // this presentation's independent native proof. Keep each original UTC.
    // This render-only rule never renews input, movement or strict-fallback age.
    if(width!=1280 || height!=720 || image_utc==0 || !depth::fresh(guest,image_utc) ||
       image_utc>now || now-image_utc>250 || s.captured_unix_ms==0 ||
       s.captured_unix_ms>now || now-s.captured_unix_ms>250)return {};
    transform result;
    result.source_position=guest.position;
    for(unsigned i=0;i<3;++i){
        result.target_position[i]=s.position[i];result.target_right[i]=s.right[i];
        result.target_forward[i]=-s.front[i];result.target_up[i]=s.up[i];
    }
    if(!depth::unit(guest.forward) || !depth::unit(guest.up) ||
       std::abs(depth::dot(guest.forward,guest.up))>.02f ||
       !depth::unit(result.target_right) || !depth::unit(result.target_forward) || !depth::unit(result.target_up))return {};
    const auto cross=[](const depth::vec3 &a,const depth::vec3 &b){return depth::vec3{
        a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]};};
    const auto normalize=[](depth::vec3 v){const float length=std::sqrt(depth::dot(v,v));for(auto &x:v)x/=length;return v;};
    // Match JOML setLookAt in GameplayWorldRenderer: the guest renderer
    // orthonormalizes the admitted basis before projecting any world pixels.
    result.source_forward=normalize(guest.forward);
    const auto source_right=normalize(cross(result.source_forward,guest.up));
    result.source_up=cross(source_right,result.source_forward);
    if(depth::dot(cross(result.target_forward,result.target_up),result.target_right)<.999f)return {};
    // Guarded warp bounds, not permission to use mismatched same-UV depth.
    float distance=0;
    for(unsigned i=0;i<3;++i){const float d=s.position[i]-guest.position[i];if(!std::isfinite(d))return {};distance+=d*d;}
    if(distance>.75f*.75f || depth::dot(guest.forward,result.target_forward)<.93969262f ||
       depth::dot(guest.up,result.target_up)<.93969262f)return {};
    if(!std::isfinite(guest.vertical_fov) || guest.vertical_fov<=.05f || guest.vertical_fov>=3.f)return {};
    const float tangent=std::tan(guest.vertical_fov*.5f);
    result.source_tan_half={tangent*static_cast<float>(width)/height,tangent};
    std::array<depth::vec4,4> p{};
    for(unsigned row=0;row<4;++row)for(unsigned col=0;col<4;++col){
        const float value=s.projection_element(row,col);if(!std::isfinite(value))return {};p[row][col]=value;
    }
    // Accept a reflected perspective lens including XY jitter, while refusing
    // oblique, orthographic and unverified packing/convention combinations.
    constexpr float epsilon=.00001f;
    for(const auto index:std::array<std::array<unsigned,2>,8>{{{0,1},{0,3},{1,0},{1,3},{2,0},{2,1},{3,0},{3,1}}})
        if(std::abs(p[index[0]][index[1]])>epsilon)return {};
    if(p[0][0]<=0 || p[1][1]<=0 || std::abs(p[3][3])>epsilon || std::abs(std::abs(p[3][2])-1.f)>epsilon ||
       std::abs(p[0][2])>.02f || std::abs(p[1][2])>.02f)return {};
    const float z_sign=p[3][2]<0?-1.f:1.f;
    for(unsigned row=0;row<4;++row){result.clip[row]=p[row];result.clip[row][2]*=z_sign;}
    if(!std::isfinite(s.far_metres) || s.far_metres<=1)return {};
    for(const float d:std::array<float,3>{1.f,10.f,s.far_metres*.5f}){
        const float actual=(result.clip[2][2]*d+result.clip[2][3])/(result.clip[3][2]*d+result.clip[3][3]);
        const float expected=s.ratio[0]+s.ratio[1]*s.far_metres/d;
        if(!std::isfinite(actual) || !std::isfinite(expected) || std::abs(actual-expected)>.00002f)return {};
    }
    return result;
}
} // namespace minecome::world_reprojection
