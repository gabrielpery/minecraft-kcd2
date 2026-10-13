package dev.minecome.hud;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import dev.minecome.protocol.BridgeClient;
import dev.minecome.protocol.Protocol;
import net.minecraft.block.Blocks;
import net.minecraft.client.MinecraftClient;
import net.minecraft.item.ItemStack;
import net.minecraft.registry.Registries;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.Hand;
import net.minecraft.util.hit.BlockHitResult;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Direction;
import net.minecraft.util.math.Vec3d;
import net.minecraft.world.GameMode;
import org.joml.Quaternionf;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.file.Path;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Explicit opt-in bridge for one cell inside the already-owned HUD Creative world.
 * It never creates a world, changes a slot, or changes either game's camera.
 */
public final class HudStoneBridge implements HudBlockBridge {
    private static final Logger LOG = LoggerFactory.getLogger("MineComeHudStone");
    // Detailed request predicates remain bounded within the HUD receipt size limit.
    private static final int MAX_RECORDS = 16;
    private record Stack(int slot, String item, int count) {}
    private record Observation(long epoch, long at, boolean air, boolean stone, boolean support,
                               Stack selected) {}
    private record Pending(long id, int action, long at, Stack selected) {}

    private final BridgeClient bridge;
    private final AtomicReference<Observation> observation = new AtomicReference<>();
    private final AtomicReference<String> serverFailure = new AtomicReference<>();
    private final AtomicBoolean serverReadPending = new AtomicBoolean();
    private final JsonArray requests = new JsonArray(), confirmations = new JsonArray();
    private Object world, player;
    // These two fields are used only by serialized server-thread observation tasks.
    private Object observedServerWorld, observedServerPlayer;
    private MinecraftServer server;
    private UUID playerId;
    private String save, failure;
    private BlockPos support, target;
    private Pending pending;
    private boolean started, closed, baselineConfirmed, ready, usableSession, observedStone;
    private long epoch, session, lastReadAt;
    private long requestCount, acceptedDispatches, unavailableResults, staleResults, busyResults;
    private long confirmedActions, confirmedPlaces, confirmedBreaks, eventsQueued, omittedRequests, omittedConfirmations;
    private long cancelledPending;
    private boolean vanillaDispatchInventoryUnchanged = true;
    private JsonObject requestGate;

    public HudStoneBridge(Path tokenFile) {
        bridge = new BridgeClient(tokenFile, "minecraft-hud-stone-1.21.1", Protocol.ROLE_MC,
                message -> LOG.info("HUD_STONE_TRANSPORT {}", message), true);
    }

    /** Called only from the owning HUD lab's client tick after its normal inventory setup. */
    public void tick(MinecraftClient client, boolean actionsEnabled) {
        if (closed || failure != null) return;
        if (!client.isOnThread()) { disable("HUD stone tick left the client thread"); return; }
        try {
            if (!started) pin(client);
            if (!owned(client)) { disable("HUD world/player/server/save identity changed"); return; }
            if (serverFailure.get() != null) { disable(serverFailure.get()); return; }
            long now = System.nanoTime();
            var status = bridge.status();
            var currentHost = bridge.latestHostPose();
            if (usableSession && (!status.connected() || status.session() != session
                    || currentHost == null || (currentHost.flags() & 3) != 3)) {
                disable("Previously usable stone transport session or host pose was lost"); return;
            }
            if (status.connected() && status.session() != session) {
                session = status.session(); epoch++; baselineConfirmed = false; ready = false;
                observation.set(null); pending = null; lastReadAt = 0;
            }
            publishPose(client);
            if (target == null && client.player.isOnGround()) initializeCell(client);
            if (target != null) {
                if (!client.world.isChunkLoaded(target) || !client.world.isChunkLoaded(support)) {
                    disable("Owned stone cell chunk became unavailable"); return;
                }
                if (!client.world.getBlockState(support).isSideSolidFullSquare(client.world, support, Direction.UP)) {
                    disable("Owned stone support changed"); return;
                }
                updateProof(client);
                if (failure != null) return;
                if (now - lastReadAt >= 50_000_000L && !serverReadPending.get()) {
                    lastReadAt = now; readServer(client);
                }
            }
            var host = bridge.latestHostPose();
            boolean canUse = baselineConfirmed && bridge.supportsStoneInput() && host != null
                    && (host.flags() & (Protocol.HAS_PLAYER | Protocol.HAS_CAMERA)) == 3;
            if (canUse && !ready) {
                ready = true; usableSession = true;
                LOG.info("HUD_STONE_READY save={} target={} support={} session={}; selected inventory is unchanged", save, target, support, session);
            }
            for (int count = 0; count < 16; count++) {
                var envelope = bridge.pollStoneInputRequest();
                if (envelope == null) break;
                Stack selected = selected(client);
                int result = bridge.stoneInputAvailability(envelope);
                requestGate = new JsonObject();
                requestGate.addProperty("reason", result == 0 ? "not_evaluated" : "transport_unavailable_before_gate");
                requestGate.addProperty("transport_result", result);
                if (result == 0) result = dispatch(client, envelope, actionsEnabled, selected);
                boolean queued = bridge.sendStoneInputResult(envelope, result);
                recordRequest(client, envelope, selected, actionsEnabled, result, queued);
                if (!queued) { disable("Stone input result could not be queued in its original session"); return; }
            }
        } catch (Exception error) { disable("HUD stone bridge: " + error.getMessage()); }
    }

    private void pin(MinecraftClient client) {
        if (client.world == null || client.player == null || client.interactionManager == null
                || !client.isIntegratedServerRunning() || client.getServer() == null
                || client.interactionManager.getCurrentGameMode() != GameMode.CREATIVE)
            throw new IllegalStateException("Owned integrated Creative world is required");
        world = client.world; player = client.player; server = client.getServer();
        save = server.getSaveProperties().getLevelName(); playerId = client.player.getUuid();
        if (!save.startsWith("MineCome-HudStream-"))
            throw new IllegalStateException("Only a fresh HUD stream save may own a stone cell");
        started = true; epoch++; bridge.start();
    }

    private boolean owned(MinecraftClient client) {
        return started && !closed && failure == null && client.world == world && client.player == player
                && client.getServer() == server && client.isIntegratedServerRunning()
                && client.interactionManager != null && save.equals(server.getSaveProperties().getLevelName());
    }

    private void initializeCell(MinecraftClient client) {
        BlockPos base = client.player.getBlockPos().add(2, -1, 0), cell = base.up();
        if (!client.world.isChunkLoaded(base) || !client.world.isChunkLoaded(cell)) return;
        if (!client.world.getBlockState(cell).isAir()
                || !client.world.getBlockState(base).isSideSolidFullSquare(client.world, base, Direction.UP))
            throw new IllegalStateException("Fresh owned stone cell lacks air and solid support");
        support = base; target = cell; observedStone = false;
    }

    private int dispatch(MinecraftClient client, BridgeClient.InputEnvelope envelope,
                         boolean actionsEnabled, Stack selected) {
        int action = envelope.request().action();
        Observation proof = observation.get();
        // The server can publish between tick entry and this request. Read the
        // observation before the clock so a new snapshot is not called future-dated.
        long now = System.nanoTime();
        boolean fresh = fresh(proof, now), hasCell = ready && target != null;
        var state = hasCell ? client.world.getBlockState(target) : Blocks.AIR.getDefaultState();
        boolean agreed = fresh && proof.air() == state.isAir() && proof.stone() == state.isOf(Blocks.STONE);
        boolean targetReach = hasCell && client.player.canInteractWithBlockAt(target, 0);
        boolean supportReach = hasCell && client.player.canInteractWithBlockAt(support, 0);
        var gate = new HudStoneGate.State(
                owned(client) && hasCell, actionsEnabled, client.currentScreen == null && client.getOverlay() == null,
                client.player.isCreative() && client.interactionManager.getCurrentGameMode() == GameMode.CREATIVE,
                hasCell && client.world.isChunkLoaded(target) && client.world.isChunkLoaded(support),
                targetReach && supportReach,
                hasCell && fresh && proof.support() && client.world.getBlockState(support).isSideSolidFullSquare(client.world, support, Direction.UP),
                fresh, agreed, fresh && selected.equals(proof.selected()),
                selected.item().equals("minecraft:stone") && selected.count() > 0,
                state.isAir(), state.isOf(Blocks.STONE), pending != null);
        var decision = HudStoneGate.decide(action, gate);
        requestGate = gateEvidence(gate, proof, now);
        requestGate.addProperty("target_in_reach", targetReach); requestGate.addProperty("support_in_reach", supportReach);
        requestGate.addProperty("client_block", Registries.BLOCK.getId(state.getBlock()).toString());
        requestGate.addProperty("reason", decision.reason()); requestGate.addProperty("transport_result", 0);
        if (decision.result() != 0) return decision.result();
        int available = bridge.stoneInputAvailability(envelope);
        if (available != 0) {
            requestGate.addProperty("reason", "transport_unavailable_before_dispatch"); requestGate.addProperty("transport_result", available);
            return available;
        }
        // These are the same vanilla APIs used by the existing interactive lab.
        // No block or inventory mutation is synthesized by MineCome.
        boolean dispatched;
        if (action == Protocol.PLACE_STONE) {
            var hit = new BlockHitResult(new Vec3d(support.getX() + .5, support.getY() + 1,
                    support.getZ() + .5), Direction.UP, support, false);
            dispatched = client.interactionManager.interactBlock(client.player, Hand.MAIN_HAND, hit).isAccepted();
        } else dispatched = client.interactionManager.attackBlock(target, Direction.UP);
        if (!dispatched) { requestGate.addProperty("reason", "vanilla_dispatch_rejected"); return Protocol.INPUT_VANILLA_FAILED; }
        vanillaDispatchInventoryUnchanged &= selected.equals(selected(client));
        pending = new Pending(envelope.request().requestId(), action, System.nanoTime(), selected);
        lastReadAt = 0;
        return Protocol.INPUT_ACCEPTED;
    }

    private void updateProof(MinecraftClient client) {
        Observation proof = observation.get();
        long now = System.nanoTime();
        if (fresh(proof, now)) {
            boolean air = client.world.getBlockState(target).isAir();
            boolean stone = client.world.getBlockState(target).isOf(Blocks.STONE);
            if (!proof.support()) { disable("Authoritative stone support changed"); return; }
            if (!baselineConfirmed) {
                if (!air || !proof.air()) { disable("Authoritative initial stone cell was not air"); return; }
                baselineConfirmed = true; observedStone = false;
            } else if (air == proof.air() && stone == proof.stone()) {
                if (!air && !stone) { disable("Owned stone target changed to an unsupported block"); return; }
                if (pending != null && proof.at() >= pending.at()) {
                    boolean expectedStone = pending.action() == Protocol.PLACE_STONE;
                    if (stone == expectedStone && air != expectedStone && stone != observedStone) {
                        var event = new Protocol.BlockEvent(pending.action(), target.getX(), target.getY(), target.getZ(), "minecraft:stone");
                        if (!bridge.blockEvent(event)) { disable("Confirmed stone event could not be queued"); return; }
                        observedStone = stone; eventsQueued++; confirmedActions++;
                        if (stone) confirmedPlaces++; else confirmedBreaks++;
                        var record = new JsonObject(); record.addProperty("id", pending.id()); record.addProperty("action", pending.action());
                        addStack(record, pending.selected()); record.addProperty("client_and_server", true);
                        record.addProperty("server_age_ms", (now - proof.at()) / 1_000_000L);
                        record.addProperty("inventory_mutated", false);
                        if (confirmations.size() < MAX_RECORDS) confirmations.add(record); else omittedConfirmations++;
                        LOG.info("HUD_STONE_CONFIRMED request={} action={} target={} selectedSlot={} selectedItem={} clientAndIntegratedServer=true",
                                pending.id(), pending.action(), target, pending.selected().slot(), pending.selected().item());
                        pending = null;
                    }
                } else if (pending == null && stone != observedStone) {
                    disable("Unrequested owned stone transition observed"); return;
                }
            }
        }
        if (pending != null && now - pending.at() > 3_000_000_000L)
            disable("Vanilla stone dispatch lacked client/server proof within three seconds");
    }

    private boolean fresh(Observation proof, long now) {
        return proof != null && HudStoneGate.freshObservation(proof.epoch(), epoch, proof.at(), now);
    }

    private JsonObject gateEvidence(HudStoneGate.State gate, Observation proof, long now) {
        var value = new JsonObject();
        value.addProperty("owner", gate.owner()); value.addProperty("armed", gate.armed());
        value.addProperty("clear_screen", gate.clearScreen()); value.addProperty("creative", gate.creative());
        value.addProperty("chunks_loaded", gate.chunksLoaded()); value.addProperty("in_reach", gate.inReach());
        value.addProperty("support", gate.support()); value.addProperty("fresh_server", gate.freshServer());
        value.addProperty("agreed_cell", gate.agreedCell()); value.addProperty("selected_agrees", gate.selectedAgrees());
        value.addProperty("selected_stone", gate.selectedStone()); value.addProperty("air", gate.air());
        value.addProperty("stone", gate.stone()); value.addProperty("pending", gate.pending());
        value.addProperty("server_observation_present", proof != null); value.addProperty("expected_epoch", epoch);
        if (proof != null) {
            value.addProperty("server_epoch", proof.epoch()); value.addProperty("server_age_ns", now - proof.at());
            value.addProperty("server_age_ms", (now - proof.at()) / 1_000_000L);
            value.addProperty("server_air", proof.air()); value.addProperty("server_stone", proof.stone());
            value.addProperty("server_support", proof.support());
            var selected = new JsonObject(); addStack(selected, proof.selected()); value.add("server_selected", selected);
        }
        return value;
    }

    private void readServer(MinecraftClient client) {
        if (!serverReadPending.compareAndSet(false, true)) return;
        var dimension = client.world.getRegistryKey(); long capturedEpoch = epoch;
        BlockPos base = support, cell = target; MinecraftServer expectedServer = server;
        expectedServer.execute(() -> {
            try {
                if (!save.equals(expectedServer.getSaveProperties().getLevelName()))
                    throw new IllegalStateException("Stone server save changed");
                var serverWorld = expectedServer.getWorld(dimension);
                var entity = expectedServer.getPlayerManager().getPlayer(playerId);
                if (serverWorld == null || entity == null || entity.getWorld() != serverWorld
                        || !entity.isCreative() || !serverWorld.isChunkLoaded(base) || !serverWorld.isChunkLoaded(cell))
                    throw new IllegalStateException("Stone authoritative world/player/chunk owner unavailable");
                if (observedServerWorld == null) { observedServerWorld = serverWorld; observedServerPlayer = entity; }
                if (observedServerWorld != serverWorld || observedServerPlayer != entity)
                    throw new IllegalStateException("Stone authoritative world/player identity changed");
                var state = serverWorld.getBlockState(cell);
                int slot = entity.getInventory().selectedSlot;
                observation.set(new Observation(capturedEpoch, System.nanoTime(), state.isAir(), state.isOf(Blocks.STONE),
                        serverWorld.getBlockState(base).isSideSolidFullSquare(serverWorld, base, Direction.UP),
                        stack(slot, entity.getInventory().getStack(slot))));
            } catch (Exception error) { serverFailure.set("Stone server observation: " + error.getMessage()); }
            finally { serverReadPending.set(false); }
        });
    }

    private void publishPose(MinecraftClient client) {
        var camera = client.gameRenderer.getCamera(); var q = new Quaternionf(camera.getRotation()).normalize();
        bridge.publish(new Protocol.Pose(vector(client.player.getPos()), vector(camera.getPos()),
                new Protocol.Quaternion(q.x(), q.y(), q.z(), q.w()), Math.toRadians(client.options.getFov().getValue()),
                new Protocol.Vec3(0, 0, 0), 1, Protocol.SPACE_MC,
                Protocol.HAS_PLAYER | Protocol.HAS_CAMERA | Protocol.IN_WORLD));
    }

    private static Protocol.Vec3 vector(Vec3d value) { return new Protocol.Vec3(value.x, value.y, value.z); }
    private static Stack selected(MinecraftClient client) {
        int slot = client.player.getInventory().selectedSlot;
        return stack(slot, client.player.getInventory().getStack(slot));
    }
    private static Stack stack(int slot, ItemStack item) { return new Stack(slot, Registries.ITEM.getId(item.getItem()).toString(), item.getCount()); }
    private static void addStack(JsonObject record, Stack stack) {
        record.addProperty("selected_slot", stack.slot()); record.addProperty("selected_item", stack.item()); record.addProperty("selected_count", stack.count());
    }
    private void recordRequest(MinecraftClient client, BridgeClient.InputEnvelope envelope, Stack stack,
                               boolean enabled, int result, boolean queued) {
        requestCount++;
        if (result == Protocol.INPUT_ACCEPTED) acceptedDispatches++;
        if (result == Protocol.INPUT_UNAVAILABLE) unavailableResults++;
        if (result == Protocol.INPUT_STALE) staleResults++;
        if (result == Protocol.INPUT_BUSY) busyResults++;
        var record = new JsonObject(); record.addProperty("id", envelope.request().requestId()); record.addProperty("action", envelope.request().action());
        record.addProperty("result", result); record.addProperty("result_queued", queued); addStack(record, stack);
        record.addProperty("actions_enabled", enabled); record.addProperty("screen_open", client.currentScreen != null || client.getOverlay() != null);
        record.add("gate", requestGate.deepCopy());
        if (requests.size() < MAX_RECORDS) requests.add(record); else omittedRequests++;
        LOG.info("HUD_STONE_RESULT request={} action={} result={} queued={} selectedSlot={} selectedItem={} screenOpen={} actionsEnabled={} gate={}",
                envelope.request().requestId(), envelope.request().action(), result, queued, stack.slot(), stack.item(), record.get("screen_open"), enabled, requestGate);
    }

    private void disable(String reason) {
        if (failure == null) { failure = reason; LOG.error("HUD_STONE_DISABLED {}", reason); }
        ready = false; baselineConfirmed = false; if (pending != null) cancelledPending++;
        pending = null; epoch++; observation.set(null); bridge.close();
    }
    public boolean failed() { return failure != null; }
    public String failure() { return failure; }
    public JsonObject evidence() {
        var value = new JsonObject(); value.addProperty("schema", 1); value.addProperty("kind", "minecome_hud_stone_bridge_v1");
        value.addProperty("ready", ready && !closed && failure == null); value.addProperty("baseline_confirmed", baselineConfirmed);
        value.addProperty("closed", closed); value.addProperty("failed", failed()); value.addProperty("failure", failure); value.addProperty("save", save);
        value.addProperty("session", session); value.addProperty("pending", pending != null); value.addProperty("request_count", requestCount);
        value.addProperty("accepted_dispatches", acceptedDispatches); value.addProperty("unavailable_results", unavailableResults);
        value.addProperty("stale_results", staleResults); value.addProperty("busy_results", busyResults);
        value.addProperty("confirmed_actions", confirmedActions); value.addProperty("confirmed_places", confirmedPlaces); value.addProperty("confirmed_breaks", confirmedBreaks);
        value.addProperty("block_events_queued", eventsQueued); value.addProperty("inventory_mutated", false); value.addProperty("camera_mutated", false);
        value.addProperty("vanilla_dispatch_inventory_unchanged", vanillaDispatchInventoryUnchanged);
        value.addProperty("cancelled_pending", cancelledPending); value.addProperty("confirmed_cell_stone", observedStone);
        value.addProperty("engine_mirroring_verified", false); value.addProperty("visual_verified", false);
        value.addProperty("omitted_requests", omittedRequests); value.addProperty("omitted_confirmations", omittedConfirmations);
        value.add("requests", requests.deepCopy()); value.add("confirmations", confirmations.deepCopy());
        if (target != null) value.add("target", position(target)); if (support != null) value.add("support", position(support));
        return value;
    }
    private static JsonObject position(BlockPos pos) {
        var value = new JsonObject(); value.addProperty("x", pos.getX()); value.addProperty("y", pos.getY()); value.addProperty("z", pos.getZ()); return value;
    }
    @Override public void close() {
        closed = true; ready = false; epoch++; if (pending != null) cancelledPending++;
        pending = null; observation.set(null); bridge.close();
    }
}
