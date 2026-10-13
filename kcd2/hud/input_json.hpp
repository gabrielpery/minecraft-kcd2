#pragma once
// Small strict bounded JSON reader for original local fixture receipts only.
#include <charconv>
#include <cmath>
#include <map>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>
namespace minecome::hud::input::json {
struct Value {
    enum class Type {object,array,string,number,boolean,null_};
    Type type=Type::null_;
    std::string scalar;
    std::map<std::string,Value> object;
    std::vector<Value> array;
    const Value &at(const std::string &key) const {
        const auto found=object.find(key);
        if(found==object.end())throw std::runtime_error("json_missing_field:"+key.substr(0,80));
        return found->second;
    }
    std::string text() const {if(type!=Type::string)throw std::runtime_error("json_string");return scalar;}
    std::uint64_t integer() const {
        if(type!=Type::string&&type!=Type::number)throw std::runtime_error("json_integer_type");
        std::uint64_t out=0;auto result=std::from_chars(scalar.data(),scalar.data()+scalar.size(),out);
        if(scalar.empty()||scalar.front()<'0'||scalar.front()>'9'||result.ec!=std::errc{}||result.ptr!=scalar.data()+scalar.size())throw std::runtime_error("json_integer");
        return out;
    }
    float real() const {
        if(type!=Type::number)throw std::runtime_error("json_float_type");
        float out=0;auto result=std::from_chars(scalar.data(),scalar.data()+scalar.size(),out);
        if(result.ec!=std::errc{}||result.ptr!=scalar.data()+scalar.size()||!std::isfinite(out))throw std::runtime_error("json_float");return out;
    }
    bool boolean() const {if(type!=Type::boolean)throw std::runtime_error("json_boolean");return scalar=="true";}
};
// Fixture failures are evidence, not JSON syntax. Bound even library exception
// messages and escape every non-ASCII byte so locale text cannot corrupt receipts.
inline std::string bounded_diagnostic(const char *message) {
    std::string out;
    if(message)for(std::size_t i=0;i<512&&message[i];++i)out+=message[i];
    return out;
}
inline std::string diagnostic_json(std::string_view message) {
    constexpr char hex[]="0123456789abcdef";
    std::string out="\"";
    for(const unsigned char c:message.substr(0,512)) {
        if(c=='\"'||c=='\\'){out+='\\';out+=static_cast<char>(c);}
        else if(c<32||c>=127){out+="\\u00";out+=hex[c>>4];out+=hex[c&15];}
        else out+=static_cast<char>(c);
    }
    out+='\"';return out;
}
class Parser {
public:
    explicit Parser(std::string_view text):text_(text) {if(text.empty()||text.size()>65536)fail();}
    Value parse() {auto value=next(0);space();if(position_!=text_.size())fail();return value;}
private:
    std::string_view text_;std::size_t position_=0,nodes_=0;
    [[noreturn]] void fail() const {throw std::runtime_error("bounded_json_invalid");}
    void space() {while(position_<text_.size()&&(text_[position_]==' '||text_[position_]=='\n'||text_[position_]=='\r'||text_[position_]=='\t'))++position_;}
    bool take(char c) {space();if(position_<text_.size()&&text_[position_]==c){++position_;return true;}return false;}
    void need(char c) {if(!take(c))fail();}
    unsigned hex4() {
        unsigned value=0;
        for(unsigned i=0;i<4;++i) {if(position_>=text_.size())fail();auto c=text_[position_++];unsigned n;
            if(c>='0'&&c<='9')n=c-'0';else if(c>='a'&&c<='f')n=c-'a'+10;else if(c>='A'&&c<='F')n=c-'A'+10;else {fail();}
            value=(value<<4)|n;}
        return value;
    }
    std::string string() {
        need('"');std::string out;
        while(position_<text_.size()) {
            unsigned char c=static_cast<unsigned char>(text_[position_++]);if(c=='"')return out;if(c<32)fail();
            if(c!='\\') {out+=static_cast<char>(c);continue;}
            if(position_>=text_.size())fail();c=static_cast<unsigned char>(text_[position_++]);
            if(c=='"'||c=='\\'||c=='/')out+=static_cast<char>(c);
            else if(c=='b')out+='\b';else if(c=='f')out+='\f';else if(c=='n')out+='\n';else if(c=='r')out+='\r';else if(c=='t')out+='\t';
            else if(c=='u') {
                unsigned cp=hex4();
                if(cp>=0xd800&&cp<=0xdbff) {if(position_+2>text_.size()||text_.substr(position_,2)!="\\u")fail();position_+=2;const auto low=hex4();if(low<0xdc00||low>0xdfff)fail();cp=0x10000+((cp-0xd800)<<10)+(low-0xdc00);}
                else if(cp>=0xdc00&&cp<=0xdfff)fail();
                if(cp<128)out+=static_cast<char>(cp);
                else if(cp<2048){out+=static_cast<char>(0xc0|(cp>>6));out+=static_cast<char>(0x80|(cp&63));}
                else if(cp<65536){out+=static_cast<char>(0xe0|(cp>>12));out+=static_cast<char>(0x80|((cp>>6)&63));out+=static_cast<char>(0x80|(cp&63));}
                else {out+=static_cast<char>(0xf0|(cp>>18));out+=static_cast<char>(0x80|((cp>>12)&63));out+=static_cast<char>(0x80|((cp>>6)&63));out+=static_cast<char>(0x80|(cp&63));}
            } else fail();
        }fail();
    }
    Value next(unsigned depth) {
        if(depth>16||++nodes_>2048)fail();space();if(position_>=text_.size())fail();Value value;
        if(take('{')) {value.type=Value::Type::object;if(take('}'))return value;do{auto key=string();need(':');if(!value.object.emplace(std::move(key),next(depth+1)).second)fail();}while(take(','));need('}');return value;}
        if(take('[')) {value.type=Value::Type::array;if(take(']'))return value;do{value.array.push_back(next(depth+1));}while(take(','));need(']');return value;}
        if(text_[position_]=='"'){value.type=Value::Type::string;value.scalar=string();return value;}
        for(auto literal:{std::string_view("true"),std::string_view("false"),std::string_view("null")})
            if(text_.substr(position_,literal.size())==literal){position_+=literal.size();value.type=literal=="null"?Value::Type::null_:Value::Type::boolean;value.scalar=literal;return value;}
        const auto begin=position_;if(text_[position_]=='-')++position_;if(position_>=text_.size())fail();
        if(text_[position_]=='0')++position_;else {if(text_[position_]<'1'||text_[position_]>'9')fail();while(position_<text_.size()&&text_[position_]>='0'&&text_[position_]<='9')++position_;}
        if(position_<text_.size()&&text_[position_]=='.'){++position_;const auto digits=position_;while(position_<text_.size()&&text_[position_]>='0'&&text_[position_]<='9')++position_;if(position_==digits)fail();}
        if(position_<text_.size()&&(text_[position_]=='e'||text_[position_]=='E')){++position_;if(position_<text_.size()&&(text_[position_]=='+'||text_[position_]=='-'))++position_;const auto digits=position_;while(position_<text_.size()&&text_[position_]>='0'&&text_[position_] <='9')++position_;if(position_==digits)fail();}
        value.type=Value::Type::number;value.scalar=text_.substr(begin,position_-begin);return value;
    }
};
} // namespace minecome::hud::input::json
