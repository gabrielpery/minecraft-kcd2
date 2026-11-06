#include "host_depth.hpp"
#include <iostream>
#include <stdexcept>
#include <string>
#include <filesystem>
#include <fstream>
#include <iterator>

using namespace minecome::host_depth;
static void check(bool value,const char *message) { if (!value) throw std::runtime_error(message); }

int wmain(int argc,wchar_t **argv) {
    try {
        // This is an original synthetic shader deliberately using a different
        // declaration order/padding from the game. Reflection must supply offsets.
        const std::string source=R"(
cbuffer CBPerViewGlobal : register(b6) {
 float4 padding[3];
 float4 CV_ScreenSize, CV_WorldViewPosition, CV_CameraFrontVector, CV_CameraUpVector;
 row_major float4x4 CV_ProjMatr;
 float4 CV_CameraRightVector, CV_NearFarClipDist, CV_ProjRatioNearestScaled, CV_ProjRatio, CV_HPosScale;
};
float4 main(float4 position:SV_Position):SV_Target {
 return padding[0]+CV_ScreenSize+CV_WorldViewPosition+CV_CameraFrontVector+CV_CameraUpVector+
 CV_ProjMatr[0]+CV_CameraRightVector+CV_NearFarClipDist+CV_ProjRatioNearestScaled+CV_ProjRatio+CV_HPosScale;
})";
        ID3DBlob *code=nullptr,*errors=nullptr;
        const auto hr=D3DCompile(source.data(),source.size(),nullptr,nullptr,nullptr,"main","ps_5_0",0,0,&code,&errors);
        if (errors) errors->Release();
        check(SUCCEEDED(hr) && code,"synthetic shader compiles");
        const auto layout=reflect(code->GetBufferPointer(),code->GetBufferSize());
        code->Release();
        check(layout.has_value(),"b6 layout reflects");
        check(layout->register_index==6 && layout->register_space==0,"legacy register and space reflected");
        check(layout->offsets[static_cast<std::size_t>(field::screen)]==48,"synthetic offset retained");
        check(!reflect(source.data(),source.size()),"non-bytecode rejected");

        std::array<std::byte,max_constant_bytes> bytes{};
        const auto put=[&](field target,const void *value,std::size_t count) {
            std::memcpy(bytes.data()+layout->offsets[static_cast<std::size_t>(target)],value,count);
        };
        const auto put4=[&](field target,vec4 value) {put(target,value.data(),16);};
        constexpr float near_plane=.1f, far_plane=1000.0f, fov=1.0f;
        const float a=far_plane/(far_plane-near_plane),b=-near_plane/(far_plane-near_plane);
        put4(field::ratio,{a,b,0,0}); put4(field::nearest,{a,b,0,0});
        put4(field::clips,{near_plane,far_plane,0,1.0f/far_plane});
        put4(field::position,{1,2,3,1}); put4(field::front,{0,-1,0,0});
        put4(field::up,{0,0,1,0}); put4(field::right,{1,0,0,0});
        put4(field::screen,{1920,1080,1.0f/1920,1.0f/1080}); put4(field::hpos,{1,1,1,1});
        std::array<float,16> projection{};
        projection[5]=1.0f/std::tan(fov*.5f); projection[0]=projection[5]/(1920.0f/1080.0f);
        put(field::projection,projection.data(),64);
        sample s{}; check(parse(*layout,bytes.data(),layout->size,s),"synthetic buffer parses");
        s.viewport={0,0,1920,1080,0,1};
        expected_view expected{1920,1080,{1,2,3},{0,1,0},{0,0,1},fov,1000};
        check(validate(s,expected,1100),"matching main forward view accepted");
        check(!s.reversed && s.far_metres==far_plane,"forward projection detected");
        const float device_at_ten=a+b*far_plane/10.0f;
        check(std::abs(linear_metres(s,device_at_ten)-10.0f)<.001f,"forward metric depth");
        check(std::isinf(linear_metres(s,1.0f)),"forward sky ignored");
        auto wrong=s; wrong.position[0]+=2; check(!validate(wrong,expected,1100),"shadow camera rejected");
        wrong=s; wrong.front[1]=1; check(!validate(wrong,expected,1100),"opposite camera rejected");
        wrong=s; wrong.viewport.width=1024; check(!validate(wrong,expected,1100),"wrong viewport rejected");
        wrong=s; wrong.projection[5]*=2; check(!validate(wrong,expected,1100),"wrong lens rejected");
        check(!validate(s,expected,1300),"stale camera rejected");
        check(!validate(s,expected,900),"future camera rejected");
        check(!parse(*layout,bytes.data(),layout->size-1,wrong),"truncated buffer rejected");
        s.ratio={-near_plane/(far_plane-near_plane),-b,0,0}; s.nearest={s.ratio[0],s.ratio[1],1,0};
        check(validate(s,expected,1100) && s.reversed,"reversed projection detected");
        const float reversed_ten=s.ratio[0]+s.ratio[1]*far_plane/10.0f;
        check(std::abs(linear_metres(s,reversed_ten)-10.0f)<.001f,"reversed metric depth");
        check(std::isinf(linear_metres(s,0.0f)),"reversed sky ignored");
        s.nearest={s.ratio[0],2.0f*s.ratio[1],.001f,0};
        check(std::abs(linear_metres(s,reversed_ten)-20.0f)<.002f,"nearest-camera remap follows engine formula");
        s.ratio[0]=NAN; check(!validate(s,expected,1100),"malformed projection rejected");
        if (argc==3 || argc==4) {
            // Optional local-only installed cache fixture. The invoking receipt
            // verifies the supplied game DLL hash before this test is run.
            const std::filesystem::path shader_path(argv[1]),compiler_path(argv[2]);
            check(shader_path.is_absolute() && compiler_path.is_absolute(),"fixture paths must be absolute");
            std::ifstream file(shader_path,std::ios::binary);
            std::vector<char> installed_shader((std::istreambuf_iterator<char>(file)),std::istreambuf_iterator<char>());
            check(!installed_shader.empty(),"installed fixture readable");
            const auto module=LoadLibraryExW(compiler_path.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
            check(module!=nullptr,"verified game DXC loads");
            const auto factory=reinterpret_cast<DxcCreateInstanceProc>(GetProcAddress(module,"DxcCreateInstance"));
            check(factory!=nullptr,"game DXC factory exported");
            const auto game_layout=reflect(installed_shader.data(),installed_shader.size(),factory);
            check(game_layout.has_value(),"actual installed DXIL reflects");
            const unsigned long expected_space=argc==4 ? std::stoul(argv[3]) : 1;
            check(game_layout->register_index==0 && game_layout->register_space==expected_space,"installed DXIL register/space matches independent dump");
            check(game_layout->size==1136,"installed reflected CB size matches independent dxc dump");
            check(game_layout->offsets[static_cast<std::size_t>(field::ratio)]==640 &&
                game_layout->offsets[static_cast<std::size_t>(field::projection)]==1008,
                "installed reflected offsets match independent dxc dump");
            FreeLibrary(module);
            std::cout << "host_depth_actual_installed_dxil_reflection PASS register=0 space=" << expected_space << " size=1136\n";
        } else check(argc==1,"expected no args or shader+compiler fixture paths and optional expected register space");
        std::cout << "host_depth_reflection_and_projection PASS\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n'; return 1;
    }
}
