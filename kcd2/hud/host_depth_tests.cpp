#include "host_depth.hpp"
#include <iostream>
#include <stdexcept>
#include <string>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <future>
#include <thread>

using namespace minecome::host_depth;
static void check(bool value,const char *message) { if (!value) throw std::runtime_error(message); }

int wmain(int argc,wchar_t **argv) {
    try {
        {
            std::mutex mutex;std::atomic<std::uint64_t> contention{0};std::uint64_t waits=0;
            std::unique_lock held(mutex);
            auto skipped=std::async(std::launch::async,[&]{return lock_recording(mutex,false,contention).owns_lock();});
            check(!skipped.get()&&contention.load()==1,"legacy recording remains opportunistic");
            std::promise<void> started;std::promise<bool> acquired;
            auto ready=started.get_future();auto result=acquired.get_future();
            std::jthread recorder([&]{started.set_value();auto guard=lock_recording(mutex,true,contention,&waits);acquired.set_value(guard.owns_lock());});
            ready.wait();
            check(result.wait_for(std::chrono::milliseconds(10))==std::future_status::timeout,"complete presentation recording waits instead of dropping callback");
            held.unlock();
            check(result.get(),"complete recording acquires original state after contention");recorder.join();
            check(waits==1&&contention.load()==2,"contention counted once without invalidating a completed observation");
        }
        {
            std::mutex mutex;profile_snapshot disabled;
            check(profile_started(disabled,profile_category::draw)==profile_clock::time_point{},"disabled profile does not request timestamps");
            {profiled_lock guard{std::unique_lock<std::mutex>{mutex},disabled,profile_category::draw,{}};check(guard.owns_lock(),"disabled profiling retains the lock");}
            check(disabled.categories[0].calls==0&&disabled.categories[0].samples==0,"disabled profiling leaves counters untouched");
            profile_snapshot enabled{true};
            for(std::uint32_t i=0;i<257;++i){
                const auto started=profile_started(enabled,profile_category::draw);
                profiled_lock original{std::unique_lock<std::mutex>{mutex},enabled,profile_category::draw,started};
                profiled_lock moved{std::move(original)};
                check(moved.owns_lock()&&!original.owns_lock(),"moving sampled guard preserves sole lock ownership");
            }
            const auto &row=enabled.categories[0];
            check(row.calls==257&&row.samples==2,"all acquired callbacks counted with first/every256 timing and no move duplication");
            check(row.max_wait_ns<=row.wait_ns&&row.max_hold_ns<=row.hold_ns,"sample maxima cannot exceed total elapsed times");
            check(mutex.try_lock(),"profiling guard releases original mutex after recording");mutex.unlock();
            {profiled_lock failed{std::unique_lock<std::mutex>{mutex,std::defer_lock},enabled,profile_category::draw,profile_clock::now()};}
            check(row.calls==257&&row.samples==2,"unacquired callback does not write mutex-protected profiling counters");
        }
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
        check(layout->projection_row_major,"row-major matrix reflection retained");
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
        check(s.projection_row_major,"sample retains reflected matrix packing");
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
        check(validate_reason(s,expected,1300)==view_rejection::age,"stale camera diagnostic distinguished");
        wrong=s;wrong.position[0]+=2;check(validate_reason(wrong,expected,1100)==view_rejection::position,"position diagnostic distinguished");
        wrong=s;wrong.front[1]=1;check(validate_reason(wrong,expected,1100)==view_rejection::basis,"direction diagnostic distinguished");
        wrong=s;wrong.projection[5]*=2;check(validate_reason(wrong,expected,1100)==view_rejection::projection,"lens diagnostic distinguished");
        check(!validate(s,expected,900),"future camera rejected");
        check(!parse(*layout,bytes.data(),layout->size-1,wrong),"truncated buffer rejected");
        {
            // Asymmetric jitter terms catch an accidental matrix transpose;
            // diagonal-only FOV checks cannot establish projection packing.
            auto column_source=source;column_source.replace(column_source.find("row_major"),9,"column_major");
            code=nullptr;errors=nullptr;
            const auto column_hr=D3DCompile(column_source.data(),column_source.size(),nullptr,nullptr,nullptr,"main","ps_5_0",0,0,&code,&errors);
            if(errors)errors->Release();
            check(SUCCEEDED(column_hr)&&code,"column-major fixture compiles");
            const auto column_layout=reflect(code->GetBufferPointer(),code->GetBufferSize());code->Release();
            check(column_layout && !column_layout->projection_row_major,"column-major reflection retained");
            projection[2]=.002f;projection[6]=-.003f;projection[11]=-.1f;projection[14]=1.0f;
            put(field::projection,projection.data(),64);
            sample row;check(parse(*layout,bytes.data(),layout->size,row),"row projection parses");
            auto column_bytes=bytes;std::array<float,16> transposed{};
            for(unsigned r=0;r<4;++r)for(unsigned c=0;c<4;++c)transposed[c*4+r]=projection[r*4+c];
            std::memcpy(column_bytes.data()+column_layout->offsets[static_cast<std::size_t>(field::projection)],transposed.data(),64);
            sample column;check(parse(*column_layout,column_bytes.data(),column_layout->size,column),"column projection parses");
            check(row.projection_element(0,2)==.002f&&column.projection_element(0,2)==.002f&&column.projection_element(2,0)==0,
                "projection accessor canonicalizes asymmetric jitter without changing raw bytes");
            check(same_native_view(row,column),"canonical projection compares equal across matrix packing");
        }
        wrong=s;wrong.position[0]+=2;
        check(validate_native(wrong,1920,1080,2000),"current native view need not match old guest position");
        wrong.front={0,0,0,0};check(!validate_native(wrong,1920,1080,2000),"native intrinsic validation rejects invalid basis");
        {
            api::descriptor_range ranges[2]{};
            ranges[0].type=api::descriptor_type::shader_resource_view;ranges[0].count=8;
            ranges[0].visibility=api::shader_stage::all_graphics;
            ranges[1].type=api::descriptor_type::constant_buffer;ranges[1].count=2;
            ranges[1].binding=8;ranges[1].dx_register_index=3;ranges[1].dx_register_space=1;
            ranges[1].visibility=api::shader_stage::all_graphics;
            api::descriptor_range_with_flags flagged{};
            static_cast<api::descriptor_range &>(flagged)=ranges[1];flagged.binding=12;flagged.dx_register_space=2;
            api::pipeline_layout_param parameters[]={api::pipeline_layout_param{2,ranges},api::pipeline_layout_param{1,&flagged},api::pipeline_layout_param{ranges[1]}};
            const auto bindings=constant_bindings(3,parameters);
            check(bindings.size()==3&&bindings[0].parameter==0&&bindings[0].binding==8&&bindings[0].register_index==3&&bindings[0].register_space==1&&bindings[0].count==2,
                "real descriptor_table CBV range remains addressable after SRV range");
            check(bindings[1].parameter==1&&bindings[1].binding==12&&bindings[1].register_space==2&&bindings[2].parameter==2,
                "descriptor_table_with_flags and root CBV preserve distinct binding spaces");
            check(descriptor_bindings(3,parameters,api::descriptor_type::shader_resource_view).size()==1,
                "actual SRV table range retained for exact shader copy source lookup");
            api::descriptor_range split_srvs[2]{ranges[0],ranges[0]};split_srvs[0].visibility=api::shader_stage::vertex;split_srvs[1].visibility=api::shader_stage::pixel;
            api::pipeline_layout_param split_parameters[]{api::pipeline_layout_param{1,&split_srvs[0]},api::pipeline_layout_param{1,&split_srvs[1]}};
            check(descriptor_bindings(1,split_parameters,api::descriptor_type::shader_resource_view,api::shader_stage::pixel).empty(),
                "vertex-only t0 cannot certify pixel depth-copy source");
            const auto pixel_binding=descriptor_bindings(2,split_parameters,api::descriptor_type::shader_resource_view,api::shader_stage::pixel);
            check(pixel_binding.size()==1&&pixel_binding[0].parameter==1,"distinct VS and PS t0 select only the pixel-visible descriptor");
            check(descriptor_bindings(3,parameters,api::descriptor_type::shader_resource_view,api::shader_stage::pixel).size()==1,
                "all-graphics t0 remains a valid pixel descriptor");
            ranges[1].visibility=api::shader_stage::compute;
            check(constant_bindings(3,parameters).size()==2,"compute-only table cannot supply graphics view");
            api::sampler_desc point;point.filter=api::filter_mode::min_mag_mip_point;point.mip_lod_bias=0;
            flagged.type=api::descriptor_type::sampler;flagged.dx_register_index=1;flagged.dx_register_space=0;flagged.count=1;flagged.static_samplers=&point;
            check(static_copy_sampler(3,parameters),"actual immutable point sampler s1 certifies known depth copy");
            point.filter=api::filter_mode::min_mag_mip_linear;
            check(!static_copy_sampler(3,parameters),"linear depth-copy sampler is not inferred from shader name");
            flagged.static_samplers=nullptr;
            check(!static_copy_sampler(3,parameters),"unobserved dynamic sampler cannot certify exact depth copy");
        }
        {
            descriptor_buffers descriptors;
            const api::descriptor_heap cpu{71},gpu{72};
            const api::buffer_range a_range{{81},256,1024},b_range{{82},512,2048};
            constant_selection selected;selected.observe(a_range,cpu,3);selected.observe(a_range,gpu,20);selected.observe(a_range,cpu,3);
            check(!selected.ambiguous&&selected.table_count==2,"identical CBV aliases share one camera and retain every distinct descriptor slot");
            auto ambiguous=selected;ambiguous.observe(b_range);
            check(ambiguous.ambiguous,"two distinct bound CBVs cannot select the first convenient camera");
            ambiguous=selected;auto shifted=a_range;shifted.offset+=256;ambiguous.observe(shifted);
            check(ambiguous.ambiguous,"same buffer at different offsets remains ambiguous");
            ambiguous=selected;shifted=a_range;shifted.size*=2;ambiguous.observe(shifted);
            check(ambiguous.ambiguous,"different visible CBV ranges fail closed");
            descriptors.update(cpu,3,a_range);descriptors.update(cpu,4,b_range);
            descriptors.copy(cpu,3,gpu,20,2);
            check(constant_aliases_current(descriptors,{selected.tables.data(),selected.table_count},a_range.buffer,a_range.offset,1024),
                "all aliased CBVs revalidate at submission");
            descriptors.update(gpu,20,b_range);
            check(!constant_aliases_current(descriptors,{selected.tables.data(),selected.table_count},a_range.buffer,a_range.offset,1024),
                "changing the second alias invalidates proof even while the first remains intact");
            descriptors.update(gpu,20,a_range);
            check(descriptors.find(gpu,20)->buffer==a_range.buffer&&descriptors.find(gpu,21)->offset==512,
                "CBV copies preserve resource and offset across CPU and GPU tables");
            descriptors.update(gpu,20,std::nullopt);
            check(!descriptors.find(gpu,20)&&descriptors.find(gpu,21).has_value(),"SRV/null overwrite removes only old CBV slot");
            descriptors.copy(cpu,99,gpu,21,1);
            check(!descriptors.find(gpu,21),"unknown descriptor source erases destination proof");
            descriptors.copy(cpu,3,cpu,4,2);
            check(descriptors.find(cpu,4)->buffer==a_range.buffer&&descriptors.find(cpu,5)->buffer==b_range.buffer,
                "overlapping table copy snapshots all original source descriptors");
            descriptors.erase_resource(a_range.buffer);
            check(!descriptors.find(cpu,3)&&!descriptors.find(cpu,4)&&descriptors.find(cpu,5).has_value(),
                "destroyed constant buffer cannot remain in any copied descriptor");
            descriptors.copy(cpu,5,gpu,10,1);descriptors.copy(cpu,0,gpu,0,4097);
            check(!descriptors.find(gpu,10),"oversized descriptor copy invalidates destination heap metadata");
            const descriptor_buffers::texture_view depth_view{{93},api::resource_view_desc{api::format::r32_float}};
            check(raw_depth_view_format(api::format::r32_float)&&raw_depth_view_format(api::format::r24_unorm_x8_uint)&&
                !raw_depth_view_format(api::format::r32_uint)&&!raw_depth_view_format(api::format::r8g8b8a8_unorm),
                "copy provenance only accepts native normalized/float depth views");
            descriptors.update_view(cpu,20,depth_view);descriptors.copy(cpu,20,gpu,32,1);
            check(descriptors.find_view(gpu,32)->resource==depth_view.resource&&!descriptors.find(gpu,32),
                "copied SRV preserves actual depth resource without masquerading as CBV");
            descriptors.copy(cpu,20,cpu,20,1);
            check(descriptors.find_view(cpu,20)->resource==depth_view.resource,"single-slot SRV self-copy retains source before overwrite");
            descriptors.copy(cpu,99,gpu,32,1);
            check(!descriptors.find_view(gpu,32)&&!descriptors.find(gpu,32),"single-slot unknown source clears old SRV and CBV proof");
            descriptors.copy(cpu,20,gpu,32,1);
            descriptors.update(cpu,20,a_range);
            descriptors.copy(cpu,20,cpu,20,1);
            check(descriptors.find(cpu,20)->buffer==a_range.buffer&&!descriptors.find_view(cpu,20),"single-slot CBV self-copy retains source before overwrite");
            check(!descriptors.find_view(cpu,20)&&descriptors.find_view(gpu,32).has_value(),"CPU descriptor reuse does not rewrite captured GPU SRV copy");
            descriptors.erase_resource(depth_view.resource);
            check(!descriptors.find_view(gpu,32),"destroyed depth resource invalidates copied SRV proof");
            api::depth_stencil_desc depth_state;
            check(classify_depth(depth_state)==depth_access::writing,"enabled writable depth is a writer");
            depth_state.depth_func=api::compare_op::never;
            check(classify_depth(depth_state)==depth_access::read_only,"NEVER depth comparison cannot modify depth");
            depth_state.depth_func=api::compare_op::always;depth_state.depth_write_mask=false;
            check(classify_depth(depth_state)==depth_access::read_only,"depth read-only pass is excluded from writer proof");
        }
        // Regression: both resources use a valid main-view camera, but only A
        // is bound as DEPTH. Submission of B must not disable A's occlusion.
        submitted_samples samples;
        {
            native_submission_guard guard;
            check(guard.submit(1)&&guard.submit(2),"read-only command lists do not poison native epochs");
            guard.observe(2);check(guard.submit(2),"fresh native depth work submits once in its own epoch");
            check(!guard.submit(2),"replaying consumed native commands cannot silently reuse camera proof");
            guard={};guard.observe(3);check(!guard.submit(4),"late submission of depth work invalidates the receiving epoch");
            guard={};guard.observe(3);guard.observe(4);check(!guard.submit(4),"recording new draws cannot hide earlier depth writes across a present");
            guard={};guard.observe(5);check(guard.submit(5),"Reset creates a fresh eligible native command recording");
        }
        auto main_depth=s;main_depth.device=reinterpret_cast<api::device *>(1);main_depth.source_depth={11};main_depth.captured_unix_ms=1000;
        auto auxiliary=main_depth;auxiliary.source_depth={22};auxiliary.captured_unix_ms=1001;
        samples.publish(main_depth);samples.publish(auxiliary);
        check(samples.take(main_depth.device,main_depth.source_depth)->source_depth==main_depth.source_depth,"auxiliary target does not replace selected depth proof");
        check(samples.take(auxiliary.device,auxiliary.source_depth).has_value(),"other selected resource retains its own proof");
        samples.publish(main_depth);main_depth.captured_unix_ms=1002;samples.publish(main_depth);
        auto older=main_depth;older.captured_unix_ms=999;samples.publish(older);
        check(samples.take(main_depth.device,main_depth.source_depth)->captured_unix_ms==1002,"older submission cannot replace newer camera proof");
        samples.publish(main_depth);samples.erase(main_depth.device,main_depth.source_depth);
        check(!samples.take(main_depth.device,main_depth.source_depth),"destroyed depth proof removed");
        samples.publish(main_depth);samples.clear();
        check(!samples.take(main_depth.device,main_depth.source_depth),"disarm invalidates submitted proof");
        samples.publish(main_depth);
        check(!samples.take(reinterpret_cast<api::device *>(2),main_depth.source_depth),"depth proof cannot cross device identity");
        {
            presentation_samples frames;
            const auto device=main_depth.device;auto *window=reinterpret_cast<void *>(7);const api::resource back_buffer{50};
            auto current=main_depth;current.captured_unix_ms=1000;current.submitted_unix_ms=1010;
            unique_views views;views.observe(current);views.observe(current);frames.submit(views);frames.seal(device,window,back_buffer,1020);
            {
                unique_views no_local;
                check(copy_source_proof(no_local,device,current.source_depth,presentation_failure::missing,{},current).has_value(),
                    "depth copy accepts source observed in prior current-epoch submission");
                const auto copy_view=copy_source_proof(views,device,current.source_depth,presentation_failure::none,current,{});
                check(copy_view&&copy_view->captured_unix_ms==current.captured_unix_ms,"same-command source proof preserves original capture time");
                auto future_local=current;future_local.position[0]+=.05f;no_local.observe(future_local);
                check(!copy_source_proof(no_local,device,current.source_depth,presentation_failure::missing,{},current),
                    "a view written after the copy cannot authorize its earlier source contents");
                unique_views poisoned=views;poisoned.invalidate(device,current.source_depth);
                check(!copy_source_proof(poisoned,device,current.source_depth,presentation_failure::none,current,current),
                    "submission-time changed source buffer poisons captured copy prefix");
                presentation_samples copies;copies.submit(views);
                check(copies.pending(device,current.source_depth).has_value(),"current epoch source visible to submitted copies");
                copies.seal(device,window,back_buffer,1020);
                check(!copies.pending(device,current.source_depth),"copy provenance cannot borrow last presentation source");
            }
            check(!frames.take(device,window,{51},current.source_depth,1040),"wrong backbuffer cannot consume presentation proof");
            check(!frames.take(device,reinterpret_cast<void *>(8),back_buffer,current.source_depth,1040),"wrong window cannot consume presentation proof");
            check(!frames.take(reinterpret_cast<api::device *>(2),window,back_buffer,current.source_depth,1040),"presentation proof cannot cross devices");
            const auto first=frames.take(device,window,back_buffer,current.source_depth,1040);
            check(first&&first->epoch>0&&first->view.captured_unix_ms==1000&&first->presented_unix_ms==1020,"current submitted view sealed without timestamp renewal");
            check(!frames.take(device,window,back_buffer,current.source_depth,1040),"proof consumed once per presentation");
            frames.submit(views);frames.seal(device,window,back_buffer,1045,false);
            presentation_failure incomplete_reason=presentation_failure::none;
            check(!frames.take(device,window,back_buffer,current.source_depth,1045,&incomplete_reason)&&incomplete_reason==presentation_failure::unknown,
                "dropped recording callback poisons entire presentation despite later matching draws");
            frames.submit(views);frames.seal(device,window,back_buffer,1046);
            check(frames.take(device,window,back_buffer,current.source_depth,1046).has_value(),"only next complete epoch can recover recording proof");
            frames.submit(views);frames.seal(device,window,back_buffer,1050);frames.seal(device,window,back_buffer,1060);
            check(!frames.take(device,window,back_buffer,current.source_depth,1060),"duplicate present has no prior-epoch fallback");
            frames.submit(views);frames.seal(device,window,back_buffer,1100);
            check(!frames.take(device,window,back_buffer,current.source_depth,1251),"recent presentation cannot renew stale native sample");
            views.clear();auto conflict=current;conflict.position[0]+=.01f;views.observe(current);views.observe(conflict);
            frames.submit(views);frames.seal(device,window,back_buffer,1100);
            check(!frames.take(device,window,back_buffer,current.source_depth,1100),"two camera views on selected DSV are ambiguous");
            views.clear();conflict=current;conflict.projection[2]+=.001f;views.observe(current);views.observe(conflict);
            frames.submit(views);frames.seal(device,window,back_buffer,1100);
            check(!frames.take(device,window,back_buffer,current.source_depth,1100),"different jitter projections cannot share a presentation proof");
            views.clear();views.observe(current);views.invalidate(device,current.source_depth);views.observe(current);
            frames.submit(views);frames.seal(device,window,back_buffer,1100);
            check(!frames.take(device,window,back_buffer,current.source_depth,1100),"unknown view poisons resource despite later matching view");
            views.clear();observe_native_draw(views,depth_access::writing,device,current.source_depth,&current);
            observe_native_draw(views,depth_access::read_only,device,current.source_depth,nullptr);
            check(views.status(device,current.source_depth)==presentation_failure::none,"unreflected read-only HUD pass does not poison depth writer proof");
            observe_native_draw(views,depth_access::unknown,device,current.source_depth,&current);
            check(views.status(device,current.source_depth)==presentation_failure::unknown,"unknown PSO cannot authorize a depth writing view");
            views.clear();observe_native_draw(views,depth_access::writing,device,current.source_depth,nullptr);
            check(views.status(device,current.source_depth)==presentation_failure::unknown,"known depth writer without reflected view fails closed");
            views.clear();observe_native_draw(views,depth_access::writing,device,current.source_depth,&current);
            conflict=current;conflict.front[1]=1;observe_native_draw(views,depth_access::writing,device,current.source_depth,&conflict);
            check(views.status(device,current.source_depth)==presentation_failure::ambiguous,"writer ambiguity distinguished from unknown view diagnostic");
            views.clear();views.observe(current);frames.submit(views);frames.seal(device,window,back_buffer,1100);frames.erase(device,current.source_depth);
            check(!frames.take(device,window,back_buffer,current.source_depth,1100),"destroyed source invalidates sealed proof");
            frames.submit(views);frames.seal(device,window,back_buffer,1100);frames.clear();
            check(!frames.take(device,window,back_buffer,current.source_depth,1100),"disarm clears presentation proof");
            views.clear();views.observe(current);auto other=current;other.source_depth={22};other.position[0]+=10;views.observe(other);
            frames.submit(views);frames.seal(device,window,back_buffer,1100);
            check(frames.take(device,window,back_buffer,current.source_depth,1100).has_value(),"auxiliary DSV view does not contaminate selected source");
            views.clear();for(unsigned i=0;i<9;++i){other=current;other.source_depth={100+i};views.observe(other);}
            frames.submit(views);frames.seal(device,window,back_buffer,1100);
            check(!frames.take(device,window,back_buffer,{100},1100),"bounded proof overflow fails closed");
            views.clear();current.captured_unix_ms=1110;current.submitted_unix_ms=1120;views.observe(current);
            frames.submit(views);frames.seal(device,window,back_buffer,1100);
            check(!frames.take(device,window,back_buffer,current.source_depth,1130),"future command sample cannot prove an earlier presentation");
            check(presentation_preserve_mode_supported(0)&&!presentation_preserve_mode_supported(1)&&!presentation_preserve_mode_supported(2),
                "only nonpreserved GenericDepth copies admit current-presentation proof");
        }
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
