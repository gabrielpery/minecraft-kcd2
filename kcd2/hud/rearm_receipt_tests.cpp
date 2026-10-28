#include "rearm_receipt.hpp"
#include "rearm_native.hpp"
#include <iostream>
#include <stdexcept>

namespace r = minecome::hud::rearm;
namespace {
unsigned checks = 0;
void check(bool condition, const char *message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
std::string replace(std::string value, std::string_view before, std::string_view after) {
    const auto at = value.find(before);
    if (at == value.npos) throw std::runtime_error("test replacement missing");
    value.replace(at, before.size(), after);
    return value;
}
}
int main() {
    using Cause=minecome::hud::input::CloseCause;
    for(auto cause:{Cause::activation_expired,Cause::second_f8,Cause::session_end})
        check(r::normal_input_close(cause,"ownership_closed"),"normal explicit/timed closure may retire");
    for(auto cause:{Cause::none,Cause::eligibility_lost,Cause::clock_regressed,Cause::key_during_settle,
        Cause::overlay_open,Cause::runtime_reload,Cause::runtime_destroy,Cause::runtime_lock_contention,
        Cause::callback_exception,Cause::mailbox_overflow,Cause::render_stale,Cause::worker_terminal,
        Cause::mouse_capture,Cause::mouse_transition})
        check(!r::normal_input_close(cause,"ownership_closed"),"cleanup cannot recover a failed input session");
    check(!r::normal_input_close(Cause::session_end,"ack_stale"),"writer fault remains terminal");
    namespace m=minecome::selective;
    m::Snapshot capture;capture.token=7;capture.generation=11;
    check(r::capture_released(m::Result::ok,capture,7,10),"released owner with advanced generation");
    check(!r::capture_released(m::Result::ok,capture,8,10),"foreign token cannot prove cleanup");
    check(!r::capture_released(m::Result::ok,capture,7,12),"earlier capture generation rejected");
    check(!r::capture_released(m::Result::ok,capture,7,0),"uncaptured runtime cannot prove owner cleanup");
    for(auto result:{m::Result::bad_argument,m::Result::busy,m::Result::unavailable,m::Result::foreign_owner,m::Result::draining})
        check(!r::capture_released(result,capture,7,10),"unsuccessful release is not proof");
    for(auto flag:{m::active,m::draining}){
        capture.flags=flag;check(!r::capture_released(m::Result::ok,capture,7,10),"capture must be inactive and drained");
    }
    const r::Generation owner{1, {{std::string(32, 'a'), std::string(64, 'b'), 101, 202,
        134059385250000001ULL, 134059385260000002ULL}, {1280, 720, 5120}, 10000}};
    const auto text = std::string("[MineComeRearmCleanup]\nSchema=1\nRunId=") + std::string(32, 'a') +
        "\nArmSha256=" + std::string(64, 'b') +
        "\nTargetPid=101\nTargetStartFileTime=134059385250000001\nProducerPid=202\nProducerStartFileTime=134059385260000002"
        "\nVerificationSha256=" + std::string(64, 'c') +
        "\nVerified=1\nAimedCleanup=1\nMovementRestored=1\nGuestCleanup=1\n";
    r::ControllerCleanup proof;
    std::string error;
    check(r::parse_cleanup(text, owner, proof, error) && error.empty(), "valid owner-bound receipt");
    check(proof.verified && proof.aimed_cleanup && proof.movement_restored && proof.guest_cleanup &&
        proof.verification_sha256 == std::string(64, 'c'), "complete proof parsed");
    std::string crlf;
    for (char c : text) { if (c == '\n') crlf += '\r'; crlf += c; }
    check(r::parse_cleanup(crlf, owner, proof, error), "Windows newline receipt");
    check(r::parse_cleanup(std::string_view(text).substr(0, text.size() - 1), owner, proof, error), "final newline optional");
    const auto reject = [&](std::string bad) {
        proof = {true, true, true, true, std::string(64, 'c')};
        check(!r::parse_cleanup(bad, owner, proof, error) && !error.empty(), "invalid receipt rejected");
        check(!proof.verified && !proof.aimed_cleanup && !proof.movement_restored && !proof.guest_cleanup &&
            proof.verification_sha256.empty(), "failure cannot retain earlier proof");
    };
    reject(""); reject(std::string(4097, 'x')); reject("\xef\xbb\xbf" + text);
    reject(text + std::string("\0", 1)); reject(text + "Unknown=1\n"); reject(text + "Schema=1\n");
    reject(text + "[MineComeRearmCleanup]\n"); reject(replace(text, "Schema=1\n", ""));
    reject(replace(text, "Schema=1", "Schema=2")); reject(replace(text, "[MineComeRearmCleanup]", "[MineComeRearmRetired]"));
    reject(replace(text, "RunId=" + std::string(32, 'a'), "RunId=" + std::string(32, 'd')));
    reject(replace(text, "ArmSha256=" + std::string(64, 'b'), "ArmSha256=" + std::string(64, 'd')));
    reject(replace(text, "VerificationSha256=" + std::string(64, 'c'), "VerificationSha256=" + std::string(64, 'G')));
    reject(replace(text, "VerificationSha256=" + std::string(64, 'c'), "VerificationSha256=" + std::string(63, 'c')));
    for (const auto *field : {"TargetPid=101", "TargetStartFileTime=134059385250000001", "ProducerPid=202", "ProducerStartFileTime=134059385260000002"}) {
        auto key = std::string(field); key.resize(key.find('=') + 1);
        for (const auto *bad : {"0", "-1", "+1", "18446744073709551616", "1x", " 1", ""}) reject(replace(text, field, key + bad));
    }
    for (const auto *field : {"Verified=1", "AimedCleanup=1", "MovementRestored=1", "GuestCleanup=1"}) {
        auto replacement = std::string(field); replacement.back() = '0'; reject(replace(text, field, replacement));
    }
    auto foreign = owner; foreign.arm.identity.producer_start++;
    check(!r::parse_cleanup(text, foreign, proof, error), "producer incarnation mismatch");
    foreign = owner; foreign.ordinal = 0;
    check(!r::parse_cleanup(text, foreign, proof, error), "unadmitted owner rejected");
    check(r::parse_cleanup(text, owner, proof, error), "restore valid parsed proof");
    const auto idle = r::format_retired(owner, proof, r::Phase::idle);
    check(idle.starts_with("[MineComeRearmRetired]\nSchema=1\n") &&
        idle.find("TargetStartFileTime=134059385250000001\n") != idle.npos &&
        idle.ends_with("Generation=1\nState=idle\n"), "first retirement retains exact FILETIME and idle state");
    auto second = owner; second.ordinal = 2;
    check(r::format_retired(second, proof, r::Phase::exhausted).ends_with("Generation=2\nState=exhausted\n"), "second retirement exhausted");
    check(r::format_retired(second, proof, r::Phase::idle).empty(), "second generation cannot advertise idle");
    check(r::format_retired(owner, proof, r::Phase::exhausted).empty(), "first generation cannot advertise exhausted");
    check(r::format_retired(owner, proof, r::Phase::failed).empty(), "failed session cannot emit receipt");
    proof.guest_cleanup = false;
    check(r::format_retired(owner, proof, r::Phase::idle).empty(), "incomplete controller proof cannot emit receipt");
    std::cout << "HUD_REARM_RECEIPT_PASS checks=" << checks << '\n';
}
