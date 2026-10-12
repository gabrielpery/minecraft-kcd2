#pragma once
#include "input_contract.hpp"
#include "stream_channel.hpp"

namespace minecome::hud::input {
struct Status {
    Ack ack;
    std::uint64_t sequence=0,observed=0;
    std::uint32_t state=0;
    bool live=false;
};
// All methods called by one worker. The host header and guest acknowledgement
// bytes have separate owners and are preserved under the common mutex.
class Writer {
public:
    ~Writer();
    bool create(const Identity &identity);
    bool poll();
    bool arm();
    bool append(std::span<const Event> events);
    void finish(std::string_view reason="closed");
    const Status &status() const { return status_; }
    const std::string &reason() const { return reason_; }
    bool ready() const;
private:
    bool transact(std::span<const Event> events,bool closing=false);
    void dispose();
    Identity identity_;
    stream::Handle mapping_,mutex_,producer_;
    std::uint8_t *mapped_=nullptr;
    std::array<std::uint8_t,128> owned_{};
    Status status_;
    bool consumed_=false;
    std::uint64_t begun_=0,deadline_=0;
    std::string reason_;
};
} // namespace minecome::hud::input
