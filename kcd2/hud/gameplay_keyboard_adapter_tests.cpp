#define DIRECTINPUT_VERSION 0x0800
#include <Windows.h>
#include <dinput.h>
#include "../reshade/gameplay_keyboard_adapter.hpp"
#include <iostream>
#include <stdexcept>
namespace a=minecome::gameplay_keyboard::adapter;
namespace k=minecome::gameplay_keyboard;
unsigned checks=0;
void check(bool pass,const char *why){++checks;if(!pass)throw std::runtime_error(why);}
int main(){try{
    std::array<DIOBJECTDATAFORMAT,256> objects{};
    for(unsigned i=0;i<256;++i)objects[i]={&GUID_Key,i,static_cast<DWORD>(DIDFT_BUTTON|DIDFT_MAKEINSTANCE(i)),0};
    DIDATAFORMAT format{sizeof(DIDATAFORMAT),sizeof(DIOBJECTDATAFORMAT),DIDF_RELAXIS,256,256,objects.data()};
    check(a::canonical(&format),"canonical keyboard witnessed");
    objects[18].dwOfs=17;check(!a::canonical(&format),"remapped keyboard offsets rejected");objects[18].dwOfs=18;
    objects[18].pguid=&GUID_Button;check(!a::canonical(&format),"nonkeyboard object rejected");objects[18].pguid=&GUID_Key;
    format.dwDataSize=255;check(!a::canonical(&format),"partial keyboard layout rejected");format.dwDataSize=256;
    std::array<BYTE,256> state;state.fill(0x80);a::filter_state(256,state.data(),k::ui_scan);
    check(state[DIK_E]==0&&state[DIK_ESCAPE]==0&&state[DIK_1]==0&&state[DIK_9]==0,"UI state suppressed");
    check(state[DIK_W]==0x80&&state[DIK_A]==0x80&&state[DIK_S]==0x80&&state[DIK_D]==0x80&&state[DIK_SPACE]==0x80,"walking state preserved");
    std::array<DIDEVICEOBJECTDATA,3> records{{{DIK_E,0x80,10,11,12},{DIK_W,0x80,20,21,22},{DIK_E,0,30,31,32}}};
    a::filter_data(sizeof(DIDEVICEOBJECTDATA),records.data(),3,k::ui_scan);
    check(records[0].dwData==0&&records[1].dwData==0x80&&records[2].dwData==0,"buffered UI down becomes release and walking survives");
    check(records[0].dwOfs==DIK_E&&records[0].dwTimeStamp==10&&records[0].dwSequence==11&&records[0].uAppData==12,"buffer count/order/metadata retained for PEEK and consumption");
    a::filter_data(sizeof(DIDEVICEOBJECTDATA),records.data(),3,k::ui_scan);
    check(records[1].dwData==0x80,"repeated PEEK filter is stable");
    std::array<DIDEVICEOBJECTDATA_DX3,2> old{{{DIK_2,0x80,10,11},{DIK_S,0x80,20,21}}};
    a::filter_data(sizeof(DIDEVICEOBJECTDATA_DX3),reinterpret_cast<LPDIDEVICEOBJECTDATA>(old.data()),2,k::ui_scan);
    check(old[0].dwData==0&&old[1].dwData==0x80&&old[1].dwSequence==21,"DX3 stride honored");
    a::filter_state(256,state.data(),[](unsigned){return true;});check(state[DIK_W]==0&&state[DIK_SPACE]==0,"inventory full mask suppresses movement");
    a::devices={};a::capacity_failed=false;a::add(1);check(!a::devices_ready(99),"unconfigured device refuses activation");
    a::format(1,&format);a::cooperative(1,reinterpret_cast<HWND>(99));check(a::devices_ready(99)&&!a::devices_ready(100),"canonical device requires same cooperative owner");
    a::format(1,nullptr);check(!a::devices_ready(99),"configuration loss revokes readiness");a::remove(1);
    check(!a::query(1,0)&&!a::request(1,2,100,k::Mode::ui),"invalid window cannot acquire native keyboard");
    std::cout<<"GAMEPLAY_KEYBOARD_ADAPTER_TESTS checks="<<checks<<" PASS\n";return 0;
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}
