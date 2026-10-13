#include <minecome/protocol.hpp>
#include <bit>
#include <cmath>
#include <limits>
#include <stdexcept>
#include <type_traits>

namespace minecome::protocol {
namespace {
struct Writer {
    Bytes b;
    template<class T> void integer(T x) { using U=std::make_unsigned_t<T>; auto u=static_cast<U>(x); for(std::size_t i=0;i<sizeof(T);++i) b.push_back(static_cast<std::uint8_t>(u>>(i*8))); }
    void real(double x) { integer(std::bit_cast<std::uint64_t>(x)); }
    void vec(Vec3 v) { real(v.x); real(v.y); real(v.z); }
    void text(const std::string& s) { b.insert(b.end(),s.begin(),s.end()); }
};
struct Reader {
    std::span<const std::uint8_t> b; std::size_t p{};
    template<class T> T integer() { if(b.size()-p<sizeof(T)) throw std::runtime_error("truncated payload"); using U=std::make_unsigned_t<T>; U u{}; for(std::size_t i=0;i<sizeof(T);++i) u|=static_cast<U>(b[p++])<<(i*8); return static_cast<T>(u); }
    double real() { auto d=std::bit_cast<double>(integer<std::uint64_t>()); if(!std::isfinite(d)) throw std::runtime_error("nonfinite pose"); return d; }
    Vec3 vec() { return {real(),real(),real()}; }
    std::string text(std::size_t n) { if(n>b.size()-p) throw std::runtime_error("truncated string"); std::string s(reinterpret_cast<const char*>(b.data()+p),n); p+=n; return s; }
    void end() { if(p!=b.size()) throw std::runtime_error("trailing payload"); }
};
void scale_ok(double s) { if(!std::isfinite(s)||s<=0) throw std::runtime_error("invalid coordinate scale"); }
void pose_ok(const Pose& p) {
    auto v=std::array{p.player.x,p.player.y,p.player.z,p.camera.x,p.camera.y,p.camera.z,p.orientation.x,p.orientation.y,p.orientation.z,p.orientation.w,p.vertical_fov,p.kcd_origin.x,p.kcd_origin.y,p.kcd_origin.z};
    for(double d:v) if(!std::isfinite(d)) throw std::runtime_error("nonfinite pose");
    scale_ok(p.blocks_per_unit);
    double q=p.orientation.x*p.orientation.x+p.orientation.y*p.orientation.y+p.orientation.z*p.orientation.z+p.orientation.w*p.orientation.w;
    if(std::abs(q-1)>0.001) throw std::runtime_error("orientation must be unit quaternion");
    if(p.vertical_fov<=0||p.vertical_fov>=3.141592653589793) throw std::runtime_error("invalid vertical FOV");
    if((p.space!=Space::kcd&&p.space!=Space::minecraft)||(p.flags&~15u)) throw std::runtime_error("invalid pose metadata");
}
bool valid_utf8(const std::string& s) {
    std::size_t i=0; while(i<s.size()) { unsigned c=static_cast<unsigned char>(s[i++]); if(c==0) return false; if(c<128) continue;
        unsigned n, cp, minimum; if(c>=0xc2&&c<=0xdf) {n=1;cp=c&31;minimum=0x80;} else if(c>=0xe0&&c<=0xef) {n=2;cp=c&15;minimum=0x800;} else if(c>=0xf0&&c<=0xf4) {n=3;cp=c&7;minimum=0x10000;} else return false;
        if(s.size()-i<n) return false; while(n--) {unsigned d=static_cast<unsigned char>(s[i++]); if((d&0xc0)!=0x80) return false; cp=(cp<<6)|(d&63);} if(cp<minimum||cp>0x10ffff||(cp>=0xd800&&cp<=0xdfff)) return false;
    } return true;
}
void hello_ok(const Hello& h) {
    if(h.role!=Role::kcd&&h.role!=Role::minecraft&&h.role!=Role::harness) throw std::runtime_error("invalid role");
    if(h.capabilities>CAP_AIMED_STONE||(h.capabilities&&h.role==Role::harness)||h.name.empty()||h.name.size()>128||h.credential.size()>128||!valid_utf8(h.name)||!valid_utf8(h.credential)) throw std::runtime_error("invalid hello");
}
void input_ok(std::uint64_t id,std::uint32_t action) {
    if(id==0||id>maximum_input_id||action<1||action>2) throw std::runtime_error("invalid stone input");
}
void id_ok(std::uint64_t id) { if(id==0||id>maximum_input_id) throw std::runtime_error("invalid exact53 ID"); }
void bounded(Vec3 p) { for(double d:{p.x,p.y,p.z}) if(!std::isfinite(d)||std::abs(d)>1e7) throw std::runtime_error("aim coordinate out of bounds"); }
void arena_ok(const AimedArena& a) {
    id_ok(a.arena_id);bounded(a.minecraft_anchor);bounded(a.kcd_anchor);
    if(a.blocks_per_unit!=1) throw std::runtime_error("aimed arena requires unit scale");
    const std::array seed{a.seed.x,a.seed.y,a.seed.z}, lo{a.minimum.x,a.minimum.y,a.minimum.z}, hi{a.maximum.x,a.maximum.y,a.maximum.z};
    for(std::size_t i=0;i<3;++i) if(std::abs(static_cast<double>(seed[i]))>1e7||static_cast<std::int64_t>(lo[i])!=static_cast<std::int64_t>(seed[i])-2||static_cast<std::int64_t>(hi[i])!=static_cast<std::int64_t>(seed[i])+2) throw std::runtime_error("invalid arena bounds");
    for(double x:{static_cast<double>(a.minimum.x),static_cast<double>(a.maximum.x)+1})
      for(double y:{static_cast<double>(a.minimum.y),static_cast<double>(a.maximum.y)+1})
        for(double z:{static_cast<double>(a.minimum.z),static_cast<double>(a.maximum.z)+1}) {
            bounded({x,y,z});bounded({a.kcd_anchor.x+x-a.minecraft_anchor.x,a.kcd_anchor.y-z+a.minecraft_anchor.z,a.kcd_anchor.z+y-a.minecraft_anchor.y});
        }
}
void aimed_request_ok(const AimedStoneRequest& a) {
    id_ok(a.arena_id);input_ok(a.request_id,a.action);id_ok(a.permit_id);bounded(a.origin);
    const double norm=a.direction.x*a.direction.x+a.direction.y*a.direction.y+a.direction.z*a.direction.z;
    if(!std::isfinite(norm)||std::abs(norm-1)>1e-9||!std::isfinite(a.range)||a.range<=0||a.range>4.5||!std::isfinite(a.nearest_distance)) throw std::runtime_error("invalid aimed ray");
    auto o=static_cast<std::uint32_t>(a.occlusion);
    if(o>2||(o<2&&a.nearest_distance!=0)||(o==2&&(a.nearest_distance<0||a.nearest_distance>a.range))) throw std::runtime_error("invalid aim occlusion");
    bounded({a.origin.x+a.direction.x*a.range,a.origin.y+a.direction.y*a.range,a.origin.z+a.direction.z*a.range});
}
void block_ok(const BlockEvent& e) {
    if(e.operation<1||e.operation>2||e.block_id.empty()||e.block_id.size()>256) throw std::runtime_error("invalid block event");
    bool colon=false; for(char c:e.block_id) { if(c==':'&&!colon) colon=true; else if(!((c>='a'&&c<='z')||(c>='0'&&c<='9')||c=='_'||c=='-'||c=='.'||(c=='/'&&colon))) throw std::runtime_error("invalid registry id"); }
    if(!colon||e.block_id.front()==':'||e.block_id.back()==':') throw std::runtime_error("registry id requires namespace");
}
Quaternion multiply(Quaternion a,Quaternion b) { return {a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w,a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z}; }
Vec3 finite_vec(Vec3 v) {if(!std::isfinite(v.x)||!std::isfinite(v.y)||!std::isfinite(v.z)) throw std::runtime_error("nonfinite coordinate");return v;}
}
Bytes encode_header(const Header& h) {
    const auto type=static_cast<unsigned>(h.type);
    if(h.payload_size>max_payload||h.sequence==0||h.minor>2||type<1||type>(h.minor==2?14u:h.minor==1?9u:7u)||(h.minor==2&&(type==8||type==9))) throw std::runtime_error("invalid header");
    Writer w; w.text("MCME"); w.integer<std::uint16_t>(1);w.integer(h.minor);w.integer<std::uint16_t>(static_cast<std::uint16_t>(h.type));w.integer<std::uint16_t>(0);w.integer(h.payload_size);w.integer(h.sequence);w.integer(h.timestamp_us); return w.b;
}
Header decode_header(std::span<const std::uint8_t> b) {
    if(b.size()!=header_size) throw std::runtime_error("header length"); Reader r{b};
    if(r.text(4)!="MCME"||r.integer<std::uint16_t>()!=1) throw std::runtime_error("protocol/version mismatch");
    Header h;h.minor=r.integer<std::uint16_t>();h.type=static_cast<Type>(r.integer<std::uint16_t>());if(r.integer<std::uint16_t>()!=0) throw std::runtime_error("unknown header flags");
    h.payload_size=r.integer<std::uint32_t>();h.sequence=r.integer<std::uint64_t>();h.timestamp_us=r.integer<std::uint64_t>(); r.end(); (void)encode_header(h); return h;
}
Bytes encode(const Hello& h) { hello_ok(h); Writer w;w.integer(static_cast<std::uint32_t>(h.role));w.integer(h.capabilities);w.integer<std::uint16_t>(static_cast<std::uint16_t>(h.name.size()));w.integer<std::uint16_t>(static_cast<std::uint16_t>(h.credential.size()));w.text(h.name);w.text(h.credential);return w.b; }
Hello decode_hello(std::span<const std::uint8_t> b) { Reader r{b};Hello h;h.role=static_cast<Role>(r.integer<std::uint32_t>());h.capabilities=r.integer<std::uint32_t>();auto n=r.integer<std::uint16_t>();auto c=r.integer<std::uint16_t>();h.name=r.text(n);h.credential=r.text(c);r.end();hello_ok(h);return h; }
Bytes encode(const Pose& p) { pose_ok(p); Writer w;w.vec(p.player);w.vec(p.camera);w.real(p.orientation.x);w.real(p.orientation.y);w.real(p.orientation.z);w.real(p.orientation.w);w.real(p.vertical_fov);w.vec(p.kcd_origin);w.real(p.blocks_per_unit);w.integer(static_cast<std::uint32_t>(p.space));w.integer(p.flags);return w.b; }
Pose decode_pose(std::span<const std::uint8_t> b) { Reader r{b};Pose p;p.player=r.vec();p.camera=r.vec();p.orientation={r.real(),r.real(),r.real(),r.real()};p.vertical_fov=r.real();p.kcd_origin=r.vec();p.blocks_per_unit=r.real();p.space=static_cast<Space>(r.integer<std::uint32_t>());p.flags=r.integer<std::uint32_t>();r.end();pose_ok(p);return p; }
Bytes encode(const BlockEvent& e) { block_ok(e);Writer w;w.integer(e.operation);w.integer(e.x);w.integer(e.y);w.integer(e.z);w.integer<std::uint16_t>(static_cast<std::uint16_t>(e.block_id.size()));w.text(e.block_id);return w.b; }
BlockEvent decode_block_event(std::span<const std::uint8_t> b) { Reader r{b};BlockEvent e;e.operation=r.integer<std::uint32_t>();e.x=r.integer<std::int32_t>();e.y=r.integer<std::int32_t>();e.z=r.integer<std::int32_t>();auto n=r.integer<std::uint16_t>();e.block_id=r.text(n);r.end();block_ok(e);return e; }
Bytes encode(const StoneInputRequest& input) {input_ok(input.id,input.action);Writer w;w.integer(input.id);w.integer(input.action);return w.b;}
StoneInputRequest decode_stone_input_request(std::span<const std::uint8_t> b) {Reader r{b};StoneInputRequest input{r.integer<std::uint64_t>(),r.integer<std::uint32_t>()};r.end();input_ok(input.id,input.action);return input;}
Bytes encode(const StoneInputResult& input) {input_ok(input.id,input.action);const auto code=static_cast<std::uint32_t>(input.result);if(code<1||code>7) throw std::runtime_error("invalid stone input result");Writer w;w.integer(input.id);w.integer(input.action);w.integer(code);return w.b;}
StoneInputResult decode_stone_input_result(std::span<const std::uint8_t> b) {Reader r{b};StoneInputResult input{r.integer<std::uint64_t>(),r.integer<std::uint32_t>(),static_cast<StoneInputResultCode>(r.integer<std::uint32_t>())};r.end();(void)encode(input);return input;}
Bytes encode(const AimedArena& a) {arena_ok(a);Writer w;w.integer(a.arena_id);w.vec(a.minecraft_anchor);w.vec(a.kcd_anchor);w.real(a.blocks_per_unit);for(auto c:{a.seed,a.minimum,a.maximum}) {w.integer(c.x);w.integer(c.y);w.integer(c.z);}return w.b;}
AimedArena decode_aimed_arena(std::span<const std::uint8_t> b) {Reader r{b};AimedArena a;a.arena_id=r.integer<std::uint64_t>();a.minecraft_anchor=r.vec();a.kcd_anchor=r.vec();a.blocks_per_unit=r.real();for(auto* c:{&a.seed,&a.minimum,&a.maximum}) *c={r.integer<std::int32_t>(),r.integer<std::int32_t>(),r.integer<std::int32_t>()};r.end();arena_ok(a);return a;}
Bytes encode(const AimPermit& a) {id_ok(a.arena_id);id_ok(a.permit_id);Writer w;w.integer(a.arena_id);w.integer(a.permit_id);return w.b;}
AimPermit decode_aim_permit(std::span<const std::uint8_t> b) {Reader r{b};AimPermit a{r.integer<std::uint64_t>(),r.integer<std::uint64_t>()};r.end();(void)encode(a);return a;}
Bytes encode(const AimedStoneRequest& a) {aimed_request_ok(a);Writer w;w.integer(a.arena_id);w.integer(a.request_id);w.integer(a.permit_id);w.integer(a.action);w.integer(static_cast<std::uint32_t>(a.occlusion));w.vec(a.origin);w.vec(a.direction);w.real(a.range);w.real(a.nearest_distance);return w.b;}
AimedStoneRequest decode_aimed_stone_request(std::span<const std::uint8_t> b) {Reader r{b};AimedStoneRequest a;a.arena_id=r.integer<std::uint64_t>();a.request_id=r.integer<std::uint64_t>();a.permit_id=r.integer<std::uint64_t>();a.action=r.integer<std::uint32_t>();a.occlusion=static_cast<AimOcclusion>(r.integer<std::uint32_t>());a.origin=r.vec();a.direction=r.vec();a.range=r.real();a.nearest_distance=r.real();r.end();aimed_request_ok(a);return a;}
Bytes encode(const AimedStoneResult& a) {id_ok(a.arena_id);input_ok(a.request_id,a.action);const auto code=static_cast<std::uint32_t>(a.result);if(code<1||code>10) throw std::runtime_error("invalid aimed result");Writer w;w.integer(a.arena_id);w.integer(a.request_id);w.integer(a.action);w.integer(code);return w.b;}
AimedStoneResult decode_aimed_stone_result(std::span<const std::uint8_t> b) {Reader r{b};AimedStoneResult a{r.integer<std::uint64_t>(),r.integer<std::uint64_t>(),r.integer<std::uint32_t>(),static_cast<AimedStoneResultCode>(r.integer<std::uint32_t>())};r.end();(void)encode(a);return a;}
Bytes frame(Type t,std::uint64_t seq,std::uint64_t time,std::span<const std::uint8_t> payload,std::uint16_t minor) { if(payload.size()>max_payload) throw std::runtime_error("oversized payload"); auto b=encode_header({t,static_cast<std::uint32_t>(payload.size()),seq,time,minor});b.insert(b.end(),payload.begin(),payload.end());return b; }
Vec3 to_minecraft(Vec3 k,Vec3 o,double s) {scale_ok(s);finite_vec(k);finite_vec(o);return finite_vec({(k.x-o.x)*s,(k.z-o.z)*s,-(k.y-o.y)*s});}
Vec3 to_kcd(Vec3 m,Vec3 o,double s) {scale_ok(s);finite_vec(m);finite_vec(o);return finite_vec({m.x/s+o.x,-m.z/s+o.y,m.y/s+o.z});}
Quaternion to_minecraft(Quaternion q) {constexpr double r=0.7071067811865475244; return multiply({-r,0,0,r},q);}
Quaternion to_kcd(Quaternion q) {constexpr double r=0.7071067811865475244; return multiply({r,0,0,r},q);}
}
