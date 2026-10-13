#pragma once
#include <minecome/protocol.hpp>
#include <atomic>
#include <chrono>
#include <deque>
#include <filesystem>
#include <fstream>
#include <future>
#include <mutex>
#include <optional>
#include <thread>
#include <vector>

namespace minecome {
enum class EventResetReason { none, started, connected, disconnected, stopped, overflow };

struct BlockEventReceipt {
    protocol::BlockEvent event;
    std::uint64_t connection_generation{};
    std::uint64_t reset_generation{};
    std::uint64_t receive_order{};
    std::uint64_t wire_sequence{};
    protocol::Role peer_role{};
    // Present only for MC-space HAS_PLAYER|IN_WORLD poses <=1s old at receipt.
    std::optional<protocol::Pose> client_pose;
};

struct BlockEventBatch {
    std::vector<BlockEventReceipt> events;
    std::uint64_t connection_generation{};
    std::uint64_t reset_generation{};
    EventResetReason reset_reason{EventResetReason::none};
    bool reset_required{};
    bool connected{};
    std::optional<protocol::Role> peer_role;
};

struct StoneInputResultReceipt {
    protocol::StoneInputResult result;
    std::uint64_t connection_generation{};
    std::uint64_t reset_generation{};
    std::uint64_t receive_order{};
    std::uint64_t wire_sequence{};
};
struct AimedArenaReceipt {
    protocol::AimedArena arena;
    std::uint64_t connection_generation{}, reset_generation{};
};
struct AimPermitReceipt {
    protocol::AimPermit permit;
    std::uint64_t connection_generation{}, reset_generation{};
    std::chrono::steady_clock::time_point received;
};
struct AimedStoneResultReceipt {
    protocol::AimedStoneResult result;
    std::uint64_t connection_generation{}, reset_generation{}, wire_sequence{};
};

class Bridge {
public:
    static constexpr std::size_t block_event_capacity = 256;
    static constexpr std::size_t maximum_event_drain = 64;
    static constexpr std::size_t stone_input_capacity = 16;
    Bridge() = default;
    ~Bridge();
    Bridge(const Bridge&) = delete;
    Bridge& operator=(const Bridge&) = delete;
    bool start(const std::filesystem::path& token_file, const std::filesystem::path& log_file, std::uint16_t port=38765, std::string identity="MineCome native/0.1.0", bool allow_aimed=false);
    void stop();
    void publish(const protocol::Pose&);
    std::optional<protocol::Pose> latest_client_pose() const;
    // Clear/re-anchor the consumer before acknowledging the current reset token.
    // No events are returned until that acknowledgement succeeds.
    BlockEventBatch drain_block_events(std::size_t maximum = maximum_event_drain);
    bool acknowledge_event_reset(std::uint64_t reset_generation);
    std::uint64_t connection_generation() const;
    std::optional<protocol::Role> peer_role() const;
    // Revalidate copied receipts immediately before any game-thread write.
    // Harness sessions and receipts from obsolete/reset sessions are rejected.
    bool game_write_allowed(const BlockEventReceipt&) const;
    // Only negotiated real-Minecraft sessions with a fresh in-world pose.
    bool input_ready() const;
    // IDs must increase within each connection. False means not dispatched.
    // Queue, inflight requests and undrained results share a hard capacity of16.
    bool request_stone_input(const protocol::StoneInputRequest&);
    bool request_stone_input(const protocol::StoneInputRequest&, std::uint64_t expected_connection_generation, std::uint64_t expected_reset_generation);
    // Waits for any in-progress send, then discards all queued/inflight/results.
    // Requests already sent cannot be recalled. ID monotonicity is preserved.
    void cancel_stone_inputs();
    std::vector<StoneInputResultReceipt> drain_stone_input_results(std::size_t maximum = stone_input_capacity);
    // Experimental minor 2 is disabled for every existing caller. Receipts are
    // revoked on reset/disconnect; local monotonic capture follows permit receipt.
    std::optional<AimedArenaReceipt> aimed_arena() const;
    std::optional<AimPermitReceipt> latest_aimed_permit() const;
    bool request_aimed_stone(const protocol::AimedStoneRequest&, const AimPermitReceipt&, std::chrono::steady_clock::time_point captured_at);
    std::vector<AimedStoneResultReceipt> drain_aimed_results();
    bool connected() const { return connected_.load(); }
    std::uint64_t received_poses() const { return poses_.load(); }
    std::uint64_t received_events() const { return events_.load(); }
private:
    void run(std::stop_token, std::uint16_t, std::promise<bool>);
    void log(const std::string&);
    void reset_events_locked(EventResetReason, bool clear_pose = true);
    bool input_ready_locked() const;
    bool request_stone_input_locked(const protocol::StoneInputRequest&);
    void clear_inputs_locked();
    void clear_aimed_locked();
    bool aimed_ready_locked() const;
    struct PendingInput {
        protocol::StoneInputRequest request;
        std::uint64_t connection_generation{}, reset_generation{};
        std::chrono::steady_clock::time_point created;
    };
    std::jthread worker_;
    std::atomic<bool> connected_{};
    std::atomic<std::uint64_t> poses_{}, events_{};
    mutable std::mutex mailbox_, log_mutex_;
    std::mutex input_dispatch_;
    std::optional<protocol::Pose> host_pose_, client_pose_;
    std::chrono::steady_clock::time_point client_pose_time_{};
    std::chrono::steady_clock::time_point host_pose_time_{};
    std::uint64_t host_generation_{};
    std::deque<BlockEventReceipt> block_events_;
    std::optional<protocol::Role> peer_role_;
    std::uint16_t peer_minor_{};
    std::uint32_t peer_capabilities_{};
    std::deque<PendingInput> stone_inputs_, inflight_inputs_;
    std::deque<StoneInputResultReceipt> stone_input_results_;
    std::uint64_t last_input_id_{}, input_receive_order_{};
    std::uint64_t connection_generation_{}, event_reset_generation_{}, event_receive_order_{};
    EventResetReason event_reset_reason_{EventResetReason::none};
    bool event_reset_required_{};
    bool allow_aimed_{}, arena_offer_seen_{}, arena_ack_sent_{};
    std::optional<protocol::AimedArena> aimed_arena_;
    protocol::Bytes arena_offer_bytes_;
    std::chrono::steady_clock::time_point arena_offered_time_{};
    std::deque<AimPermitReceipt> aim_permits_;
    struct PendingAim {
        protocol::AimedStoneRequest request;
        std::uint64_t connection_generation{}, reset_generation{};
        std::chrono::steady_clock::time_point captured, permit_received, dispatched;
    };
    std::optional<PendingAim> queued_aim_, inflight_aim_;
    std::deque<AimedStoneResultReceipt> aimed_results_;
    std::uint64_t last_aim_request_id_{}, last_aim_permit_id_{};
    std::vector<protocol::Cell> aimed_owned_cells_;
    bool aimed_bootstrap_seen_{};
    std::string token_;
    std::string identity_;
    std::ofstream logfile_;
};
}
