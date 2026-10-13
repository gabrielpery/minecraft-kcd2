package dev.minecome.hud;

import com.google.gson.JsonObject;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/** Pure timing/receipt checks; no game, OpenGL, native mapping or input. */
public final class HudRenderTimingTests {
    private static int checks;
    private static final long BASE = 10_000_000_000L;
    private static void check(boolean value, String reason) {
        checks++;
        if (!value) throw new AssertionError(reason);
    }
    private static long number(JsonObject value, String key) {
        return value.get(key).getAsLong();
    }

    private static void phaseAccounting() {
        try (var timing = new HudRenderTiming(Thread.currentThread(), () -> false)) {
            timing.tick(false, false, false, BASE);
            timing.tick(false, false, true, BASE + 50_000_000L);
            timing.tick(false, true, false, BASE + 120_000_000L);
            timing.inputTick(BASE);
            timing.inputTick(BASE + 90_000_000L);
            timing.readbackAge(23);
            timing.readbackAge(7);
            JsonObject first = timing.phase();
            check(number(first, "waiting_max_tick_gap_ms") == 70, "waiting tick peak uses real tick entry");
            check(number(first, "armed_max_tick_gap_ms") == 0, "waiting phase has no armed gap");
            check(number(first, "max_input_tick_gap_ms") == 90, "lab callback gap is independent of tick gap");
            check(number(first, "focused_ticks") == 1 && number(first, "unfocused_ticks") == 2,
                "focus observations counted separately");
            check(number(first, "overlay_skipped_ticks") == 1, "overlay observations retained");
            check(number(first, "max_readback_age_ms") == 23, "readback age is a maximum");
            check(number(first, "max_tick_gap_utc_ms") > 0, "tick peak carries an observation timestamp");

            timing.beginPhase();
            JsonObject reset = timing.phase();
            check(number(reset, "waiting_max_tick_gap_ms") == 0 && number(reset, "armed_max_tick_gap_ms") == 0,
                "phase reset clears tick peaks");
            check(number(reset, "focused_ticks") == 0 && number(reset, "unfocused_ticks") == 0,
                "phase reset clears focus counts");
            check(number(reset, "max_input_tick_gap_ms") == 0 && number(reset, "max_readback_age_ms") == 0,
                "phase reset clears independent callback/readback data");
            check(number(timing.overall(), "waiting_max_tick_gap_ms") == 70,
                "phase reset preserves overall timing");

            timing.tick(true, false, false, BASE + 2_000_000_000L);
            timing.tick(true, false, false, BASE + 2_030_000_000L);
            timing.inputTick(BASE + 2_000_000_000L);
            timing.inputTick(BASE + 2_020_000_000L);
            timing.readbackAge(5);
            JsonObject second = timing.phase();
            check(number(second, "armed_max_tick_gap_ms") == 30, "new phase excludes previous phase tick gap");
            check(number(timing.overall(), "state_transition_tick_gap_ms") == 1_880,
                "waiting-to-armed gap is separately attributed");
            check(number(timing.overall(), "armed_max_tick_gap_ms") == 30,
                "transition interval does not inflate active tick peak");
            check(number(second, "waiting_max_tick_gap_ms") == 0, "armed phase does not inherit waiting peaks");
            check(number(second, "max_input_tick_gap_ms") == 20, "new phase excludes previous callback timestamp");
            check(number(second, "max_readback_age_ms") == 5, "new phase owns its readback maximum");
            check(number(timing.overall(), "max_readback_age_ms") == 23, "overall preserves earlier readback maximum");
            check(number(first, "unfocused_ticks") == 2 && number(first, "max_readback_age_ms") == 23,
                "earlier snapshots are stable after later observations");
            second.addProperty("focused_ticks", 999);
            second.getAsJsonObject("stage_max_ms").addProperty("injected", 123);
            check(number(timing.phase(), "focused_ticks") == 0, "mutating returned counters does not alter collector");
            check(!timing.phase().getAsJsonObject("stage_max_ms").has("injected"),
                "nested stage snapshots do not alias collector");
        }
    }

    private static void stageBoundary() throws InterruptedException {
        try (var timing = new HudRenderTiming(Thread.currentThread(), () -> false)) {
            timing.stage("baseline_section");
            Thread.sleep(30);
            timing.beginPhase();
            timing.stage("trial_section");
            double total = timing.overall().getAsJsonObject("stage_max_ms").get("baseline_section").getAsDouble();
            double phase = timing.phase().getAsJsonObject("stage_max_ms").get("baseline_section").getAsDouble();
            check(total >= 20, "baseline stage measured before phase reset");
            check(total - phase >= 20, "new phase excludes time spent in preceding phase stage");
        }
    }

    private static void samplerClosure() throws InterruptedException {
        var sampled = new CountDownLatch(1);
        var calls = new AtomicInteger();
        var timing = new HudRenderTiming(Thread.currentThread(), () -> {
            calls.incrementAndGet();
            sampled.countDown();
            return false;
        });
        try {
            timing.stage("bounded_block");
            check(sampled.await(2, TimeUnit.SECONDS), "slow stage reaches bounded worker sampler");
            long deadline = System.nanoTime() + 2_000_000_000L;
            while (timing.overall().getAsJsonArray("slow_samples").isEmpty() && System.nanoTime() < deadline) {
                Thread.sleep(5);
            }
            check(!timing.overall().getAsJsonArray("slow_samples").isEmpty(), "completed same-stage stack is retained");
        } finally {
            timing.close();
        }
        JsonObject closed = timing.overall();
        check(closed.get("sampler_stopped").getAsBoolean(), "worker exit confirmed before receipt freeze");
        int count = calls.get();
        Thread.sleep(75);
        check(calls.get() == count, "closed sampler stops observing client state");
        check(closed.equals(timing.overall()), "closed diagnostics cannot change after final snapshot");
        var samples = closed.getAsJsonArray("slow_samples");
        check(samples.size() <= 8 && timing.phase().getAsJsonArray("slow_samples").size() <= 4,
            "sample receipts respect collection bounds");
        for (var value : samples) {
            var sample = value.getAsJsonObject();
            check(sample.getAsJsonArray("stack").size() <= 6, "stack sample depth is bounded");
            for (var frame : sample.getAsJsonArray("stack")) {
                check(frame.getAsString().length() <= 180, "stack frame text is bounded");
            }
            check(sample.get("stage").getAsString().equals("bounded_block"), "sample belongs to observed stage");
        }
        timing.close();
        check(closed.equals(timing.overall()), "closing sampler twice is harmless");
    }

    public static void main(String[] args) throws InterruptedException {
        phaseAccounting();
        stageBoundary();
        samplerClosure();
        System.out.println("HudRenderTimingTests: " + checks + " checks passed; pure timing diagnostics; no games launched.");
    }
}
