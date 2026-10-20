package dev.minecome.aim;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import dev.minecome.protocol.AimGeometry;
import dev.minecome.protocol.Protocol;
import net.minecraft.block.Blocks;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.item.ItemStack;
import net.minecraft.registry.Registries;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.Hand;
import net.minecraft.util.hit.BlockHitResult;
import net.minecraft.util.hit.HitResult;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Direction;
import net.minecraft.util.math.Vec3d;
import net.minecraft.world.GameMode;
import net.minecraft.world.RaycastContext;
import net.minecraft.world.World;

import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Real vanilla selection/interaction in an explicitly owned fresh Creative test save.
 * Owns at most sixteen confirmed stones inside a five-block cube around one seed.
 * It never writes blocks, changes inventory/camera, or grants a transport capability.
 */
public final class AimedStoneArena implements AutoCloseable {
    public static final long MAX_RAY_AGE_NS = 500_000_000L;
    // A captured host view may shift slightly during look. This allowance only
    // compares the unchanged mapped request origin with the real player eye;
    // it never rebases the arena, moves the player, or changes vanilla reach.
    public static final double MAX_REQUEST_VIEW_ORIGIN_OFFSET = .25;
    public static final double MAX_HOST_RAY_RANGE = 4.5;
    private static final long PROOF_TIMEOUT_NS = 3_000_000_000L;
    private static final int MAX_RECEIPTS = 96;

    public enum OcclusionKind { KNOWN_CLEAR, HIT, UNAVAILABLE }
    public record Occlusion(OcclusionKind kind, double distance) {
        public Occlusion {
            Objects.requireNonNull(kind);
            if (!Double.isFinite(distance) || distance < 0 || (kind != OcclusionKind.HIT && distance != 0))
                throw new IllegalArgumentException("Invalid host obstruction distance");
        }
        public static Occlusion clear() { return new Occlusion(OcclusionKind.KNOWN_CLEAR, 0); }
        public static Occlusion hit(double distance) { return new Occlusion(OcclusionKind.HIT, distance); }
        public static Occlusion unavailable() { return new Occlusion(OcclusionKind.UNAVAILABLE, 0); }
    }
    public record HostRay(long capturedAtNanos, AimGeometry.Alignment alignment,
                          AimGeometry.Ray hostRay, Occlusion occlusion) {
        public HostRay { Objects.requireNonNull(alignment); Objects.requireNonNull(hostRay); Objects.requireNonNull(occlusion); }
    }
    public record Hit(BlockPos block, Direction side, Vec3d point, boolean inside) {
        private static Hit of(BlockHitResult hit) {
            return new Hit(hit.getBlockPos().toImmutable(), hit.getSide(), hit.getPos(), hit.isInsideBlock());
        }
        private BlockHitResult vanilla() { return new BlockHitResult(point, side, block, inside); }
    }
    public record Selection(boolean allowed, String reason, BlockPos target, Hit hit) {}
    public record Decision(boolean queued, String reason) {}
    public record Result(long id, int action, String status, String reason,
                         BlockPos target, Hit hit, boolean clientAndServer) {}
    private record Stack(int slot, String item, int count) {}
    private record CellState(String block, boolean air, boolean stone, boolean solidUp) {}
    private record Plan(long id, int action, long at, boolean bootstrap, HostRay ray,
                        BlockPos target, Hit hit, Stack selected, Map<BlockPos, CellState> before) {}
    private record Observation(long id, String phase, long at, Map<BlockPos, CellState> cells,
                               Stack selected, Hit hit, String failure) {}

    private final AimGeometry.Alignment alignment;
    private final String ownedHudSave;
    private final Set<BlockPos> owned = new LinkedHashSet<>();
    private final AtomicReference<Observation> observation = new AtomicReference<>();
    private final AtomicBoolean reading = new AtomicBoolean();
    private final JsonArray requests = new JsonArray(), confirmations = new JsonArray();
    private Object world, player, serverWorld, serverPlayer;
    private MinecraftServer server;
    private UUID playerId;
    private String save, failure;
    private BlockPos seed, support;
    private Plan pending;
    private Result lastResult;
    private boolean baseline, bootstrapped, dispatched, closed;
    private long lastId, dispatchedAt, lastReadAt;
    private int omittedReceipts;

    public AimedStoneArena(AimGeometry.Alignment alignment) {
        this.alignment = Objects.requireNonNull(alignment); this.ownedHudSave = null;
    }

    /** HUD callers must supply the exact save they created, never merely a prefix. */
    public AimedStoneArena(AimGeometry.Alignment alignment, String ownedHudSave) {
        this.alignment = Objects.requireNonNull(alignment);
        if (ownedHudSave == null || !ownedHudSave.matches("MineCome-HudStream-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"))
            throw new IllegalArgumentException("Exact owned HUD save required");
        this.ownedHudSave = ownedHudSave;
    }

    /** Only the Minecraft client tick calls this method. Authoritative reads use server.execute. */
    public void tick(MinecraftClient client) {
        tick(client, true);
    }

    /** Revocation cancels only actions not dispatched to vanilla; dispatched actions still need proof. */
    public void tick(MinecraftClient client, boolean actionsEnabled) {
        if (closed || failure != null) return;
        if (!client.isOnThread()) { fail("arena_client_thread_required"); return; }
        try {
            if (world == null) {
                if (client.world == null || client.player == null || !client.player.isOnGround()) return;
                pin(client);
                readServer(client, null, "baseline");
            }
            if (!owner(client)) { fail("arena_owner_changed"); return; }
            if (pending != null && !dispatched && !actionsEnabled)
                finishRejected(pending, "actions_disabled_before_dispatch");
            Observation proof = observation.getAndSet(null);
            long now = System.nanoTime();
            if (pending != null && now - pending.at > PROOF_TIMEOUT_NS) {
                fail("vanilla_action_proof_timeout"); return;
            }
            if (proof != null) {
                if (proof.failure != null) {
                    // A revoked request may finish its read later. It cannot poison a
                    // subsequent request; ordinary lease expiry is a terminal refusal.
                    if (pending != null && proof.id == pending.id) {
                        if (proof.phase.equals("pre") && proof.failure.equals("authoritative_ray_stale"))
                            finishRejected(pending, "ray_stale");
                        else fail(proof.failure);
                    } else if (proof.phase.equals("baseline")) fail(proof.failure);
                    return;
                }
                if (proof.phase.equals("baseline")) {
                    if (now - proof.at < 0 || now - proof.at > MAX_RAY_AGE_NS) {
                        fail("baseline_proof_stale"); return;
                    }
                    if (!loaded(client.world, Set.of(seed, support)) || !states(client, Set.of(seed, support)).equals(proof.cells)
                            || !proof.cells.get(seed).air || !proof.cells.get(support).solidUp) {
                        fail("baseline_client_server_disagreement"); return;
                    }
                    baseline = true;
                } else if (pending != null && proof.id == pending.id) {
                    if (proof.phase.equals("pre")) dispatchProved(client, proof, now);
                    else if (proof.phase.equals("post")) confirm(client, proof, now);
                }
            }
            // A proof may be published just before the server task clears its
            // in-flight bit. Retry preproof scheduling rather than losing that
            // request when a baseline and the first action meet in one tick.
            if (pending != null && !dispatched && !reading.get() && observation.get() == null)
                readServer(client, pending, "pre");
            if (pending != null && dispatched && now - lastReadAt >= 50_000_000L && !reading.get()) {
                lastReadAt = now; readServer(client, pending, "post");
            }
        } catch (Exception error) { fail("arena_exception: " + error.getMessage()); }
    }

    private void pin(MinecraftClient client) {
        if (!client.isIntegratedServerRunning() || client.getServer() == null || client.interactionManager == null
                || !client.player.isCreative() || client.interactionManager.getCurrentGameMode() != GameMode.CREATIVE)
            throw new IllegalStateException("Fresh integrated Creative world required");
        save = client.getServer().getSaveProperties().getLevelName();
        if (ownedHudSave == null ? !save.startsWith("MineCome-AimedStone-") : !ownedHudSave.equals(save))
            throw new IllegalStateException("Owned aimed save required");
        world = client.world; player = client.player; server = client.getServer(); playerId = client.player.getUuid();
        seed = client.player.getBlockPos().add(2, 0, 0).toImmutable(); support = seed.down();
        if (!loaded(client.world, Set.of(seed, support)) || !client.world.getBlockState(seed).isAir()
                || !client.world.getBlockState(support).isSideSolidFullSquare(client.world, support, Direction.UP))
            throw new IllegalStateException("Seed lacks fresh air and solid UP support");
    }

    private boolean owner(MinecraftClient client) {
        return !closed && failure == null && client.world == world && client.player == player
                && client.getServer() == server && client.isIntegratedServerRunning()
                && client.interactionManager != null && save.equals(server.getSaveProperties().getLevelName());
    }

    /** The sole fixed UP-support exception initializes the empty arena through vanilla placement. */
    public Decision bootstrap(MinecraftClient client, long id) {
        Decision admission = admit(id, Protocol.PLACE_STONE);
        if (admission != null) return admission;
        String reject = gate(client);
        if (reject == null && bootstrapped) reject = "bootstrap_already_used";
        if (reject == null && !client.world.getBlockState(seed).isAir()) reject = "bootstrap_target_not_air";
        if (reject == null && (!client.player.canInteractWithBlockAt(seed, 0)
                || !client.player.canInteractWithBlockAt(support, 0))) reject = "out_of_reach";
        if (reject != null) return rejected(id, Protocol.PLACE_STONE, reject, null, null);
        Hit hit = new Hit(support, Direction.UP, new Vec3d(support.getX() + .5, support.getY() + 1, support.getZ() + .5), false);
        return queue(client, id, Protocol.PLACE_STONE, true, null, seed, hit);
    }

    /** Selection uses Minecraft's actual outline shapes; no cube-intersection replacement. */
    public Selection select(MinecraftClient client, int action, HostRay ray) {
        String reject = gate(client);
        if (reject == null && action != Protocol.PLACE_STONE && action != Protocol.BREAK_STONE) reject = "invalid_action";
        if (reject == null) reject = rayGate(ray, client.player, System.nanoTime());
        if (reject != null) return new Selection(false, reject, null, null);
        AimGeometry.Ray mapped = alignment.toMinecraft(ray.hostRay);
        BlockHitResult result = raycast(client.world, client.player, mapped);
        if (result.getType() != HitResult.Type.BLOCK) return new Selection(false, "ray_miss", null, null);
        Hit hit = Hit.of(result);
        BlockPos target = action == Protocol.PLACE_STONE ? hit.block.offset(hit.side) : hit.block;
        if (hit.inside) reject = "ray_started_inside_block";
        else if (!owned.contains(hit.block) || !client.world.getBlockState(hit.block).isOf(Blocks.STONE)) reject = "unowned_hit";
        else if (hostBlocked(ray, mapped, hit)) reject = "host_obstructed";
        else if (!bounded(target)) reject = "outside_arena";
        else if (!client.player.canInteractWithBlockAt(hit.block, 0) || !client.player.canInteractWithBlockAt(target, 0)
                || vec(mapped.origin()).distanceTo(hit.point) > client.player.getBlockInteractionRange()) reject = "out_of_reach";
        else if (!loaded(client.world, Set.of(target))) reject = "chunk_unavailable";
        else if (action == Protocol.PLACE_STONE && owned.size() >= AimGeometry.MAX_OWNED_CELLS) reject = "owned_limit";
        else if (action == Protocol.PLACE_STONE && (!client.world.getBlockState(target).isAir() || owned.contains(target))) reject = "placement_target_not_air";
        return new Selection(reject == null, reject == null ? "selected" : reject, target, hit);
    }

    public Decision request(MinecraftClient client, long id, int action, HostRay ray) {
        Decision admission = admit(id, action);
        if (admission != null) return admission;
        Selection selection = select(client, action, ray);
        if (!selection.allowed) return rejected(id, action, selection.reason, selection.target, selection.hit);
        return queue(client, id, action, false, ray, selection.target, selection.hit);
    }

    private Decision queue(MinecraftClient client, long id, int action, boolean bootstrap,
                           HostRay ray, BlockPos target, Hit hit) {
        Set<BlockPos> cells = new LinkedHashSet<>(owned); cells.add(target); cells.add(hit.block);
        if (!loaded(client.world, cells)) return rejected(id, action, "chunk_unavailable", target, hit);
        pending = new Plan(id, action, System.nanoTime(), bootstrap, ray, target.toImmutable(), hit,
                selected(client.player), states(client, cells));
        dispatched = false;
        lastResult = new Result(id, action, "queued", "awaiting_server_preproof", target, hit, false);
        readServer(client, pending, "pre");
        return new Decision(true, "queued");
    }

    private String gate(MinecraftClient client) {
        if (!client.isOnThread()) return "client_thread_required";
        if (!ready() || !owner(client)) return "arena_unavailable";
        if (pending != null) return "action_pending";
        if (client.currentScreen != null || client.getOverlay() != null) return "inventory_or_screen_open";
        if (!client.player.isCreative() || client.interactionManager.getCurrentGameMode() != GameMode.CREATIVE) return "creative_required";
        for (BlockPos cell : owned) {
            if (!client.world.isChunkLoaded(cell) || !client.world.getBlockState(cell).isOf(Blocks.STONE)) {
                fail("unrequested_owned_cell_change"); return "unrequested_owned_cell_change";
            }
        }
        Stack selected = selected(client.player);
        if (!selected.item.equals("minecraft:stone") || selected.count <= 0) return "selected_item_not_stone";
        return null;
    }

    private String rayGate(HostRay ray, PlayerEntity entity, long now) {
        if (ray == null) return "ray_unavailable";
        if (!alignment.equals(ray.alignment)) return "alignment_changed";
        long age = now - ray.capturedAtNanos;
        if (age < 0 || age > MAX_RAY_AGE_NS) return "ray_stale";
        if (ray.hostRay.range() > MAX_HOST_RAY_RANGE) return "host_ray_range_exceeded";
        if (ray.occlusion.kind == OcclusionKind.UNAVAILABLE) return "host_obstruction_unavailable";
        if (ray.occlusion.kind == OcclusionKind.HIT && ray.occlusion.distance > ray.hostRay.range()) return "invalid_host_obstruction";
        if (vec(alignment.toMinecraft(ray.hostRay).origin()).distanceTo(entity.getEyePos()) > MAX_REQUEST_VIEW_ORIGIN_OFFSET) return "ray_origin_disagrees_with_eye";
        return null;
    }

    private boolean hostBlocked(HostRay ray, AimGeometry.Ray mapped, Hit hit) {
        return ray.occlusion.kind == OcclusionKind.HIT
                && ray.occlusion.distance * alignment.blocksPerUnit() <= vec(mapped.origin()).distanceTo(hit.point) + 1e-6;
    }

    private void dispatchProved(MinecraftClient client, Observation proof, long now) {
        Plan plan = pending;
        String reason = null;
        if (now - proof.at < 0 || now - proof.at > MAX_RAY_AGE_NS) reason = "server_preproof_stale";
        else if (!loaded(client.world, plan.before.keySet())) reason = "chunk_unavailable";
        else if (!plan.before.equals(proof.cells) || !plan.before.equals(states(client, plan.before.keySet()))) reason = "client_server_prestate_disagrees";
        else if (!plan.selected.equals(proof.selected) || !plan.selected.equals(selected(client.player))) reason = "selected_stack_changed";
        else if (client.currentScreen != null || client.getOverlay() != null) reason = "inventory_or_screen_open";
        else if (!client.player.isCreative() || client.interactionManager.getCurrentGameMode() != GameMode.CREATIVE) reason = "creative_required";
        else if (!client.player.canInteractWithBlockAt(plan.target, 0) || !client.player.canInteractWithBlockAt(plan.hit.block, 0)) reason = "out_of_reach";
        else if (!plan.bootstrap) {
            reason = rayGate(plan.ray, client.player, now);
            if (reason == null && (!sameHit(plan.hit, proof.hit)
                    || !sameHit(plan.hit, blockHit(client.world, client.player, alignment.toMinecraft(plan.ray.hostRay)))))
                reason = "ray_hit_changed_before_dispatch";
        } else if (!proof.cells.get(support).solidUp) reason = "bootstrap_support_changed";
        if (reason != null) { finishRejected(plan, reason); return; }
        boolean accepted = plan.action == Protocol.PLACE_STONE
                ? client.interactionManager.interactBlock(client.player, Hand.MAIN_HAND, plan.hit.vanilla()).isAccepted()
                : client.interactionManager.attackBlock(plan.target, plan.hit.side);
        if (!accepted) { finishRejected(plan, "vanilla_dispatch_rejected"); return; }
        if (!plan.selected.equals(selected(client.player))) { fail("vanilla_creative_inventory_changed"); return; }
        dispatched = true; dispatchedAt = System.nanoTime(); lastReadAt = 0;
        if (plan.bootstrap) bootstrapped = true;
        lastResult = new Result(plan.id, plan.action, "dispatched", "awaiting_server_postproof", plan.target, plan.hit, false);
    }

    private void confirm(MinecraftClient client, Observation proof, long now) {
        Plan plan = pending;
        if (!dispatched || proof.at - dispatchedAt < 0 || now - proof.at < 0 || now - proof.at > MAX_RAY_AGE_NS) return;
        if (!loaded(client.world, plan.before.keySet())) { fail("confirmation_chunk_unavailable"); return; }
        Map<BlockPos, CellState> clientStates = states(client, plan.before.keySet());
        if (!clientStates.equals(proof.cells)) return;
        if (!plan.selected.equals(proof.selected) || !plan.selected.equals(selected(client.player))) { fail("selected_stack_changed_during_action"); return; }
        for (var entry : plan.before.entrySet()) {
            CellState after = proof.cells.get(entry.getKey());
            if (entry.getKey().equals(plan.target)) {
                if (plan.action == Protocol.PLACE_STONE ? !after.stone : !after.air) return;
            } else if (!entry.getValue().equals(after)) { fail("unrequested_arena_transition"); return; }
        }
        if (plan.action == Protocol.PLACE_STONE) owned.add(plan.target); else owned.remove(plan.target);
        lastResult = new Result(plan.id, plan.action, "confirmed", "client_and_integrated_server", plan.target, plan.hit, true);
        append(confirmations, plannedReceipt(plan, lastResult)); append(requests, plannedReceipt(plan, lastResult));
        pending = null; dispatched = false;
    }

    private void readServer(MinecraftClient client, Plan plan, String phase) {
        if (!reading.compareAndSet(false, true)) return;
        var dimension = client.world.getRegistryKey();
        Set<BlockPos> cells = plan == null ? Set.of(seed, support) : plan.before.keySet();
        long id = plan == null ? 0 : plan.id;
        server.execute(() -> {
            try {
                var authoritative = server.getWorld(dimension); var entity = server.getPlayerManager().getPlayer(playerId);
                if (!save.equals(server.getSaveProperties().getLevelName()) || authoritative == null || entity == null
                        || entity.getWorld() != authoritative || !entity.isCreative() || !loaded(authoritative, cells))
                    throw new IllegalStateException("authoritative_owner_unavailable");
                if (serverWorld == null) { serverWorld = authoritative; serverPlayer = entity; }
                if (serverWorld != authoritative || serverPlayer != entity) throw new IllegalStateException("authoritative_identity_changed");
                Hit hit = null;
                if (plan != null && phase.equals("pre")) {
                    if (!entity.canInteractWithBlockAt(plan.target, 0) || !entity.canInteractWithBlockAt(plan.hit.block, 0))
                        throw new IllegalStateException("authoritative_out_of_reach");
                    if (!plan.bootstrap) {
                        String rayReject = rayGate(plan.ray, entity, System.nanoTime());
                        if (rayReject != null) throw new IllegalStateException("authoritative_" + rayReject);
                        hit = blockHit(authoritative, entity, alignment.toMinecraft(plan.ray.hostRay));
                    }
                }
                observation.set(new Observation(id, phase, System.nanoTime(), states(authoritative, cells), selected(entity), hit, null));
            } catch (Exception error) {
                observation.set(new Observation(id, phase, System.nanoTime(), Map.of(), null, null, error.getMessage()));
            } finally { reading.set(false); }
        });
    }

    private static BlockHitResult raycast(World world, PlayerEntity entity, AimGeometry.Ray ray) {
        Vec3d origin = vec(ray.origin()), end = origin.add(vec(ray.direction()).multiply(ray.range()));
        return world.raycast(new RaycastContext(origin, end, RaycastContext.ShapeType.OUTLINE,
                RaycastContext.FluidHandling.NONE, entity));
    }
    private static Hit blockHit(World world, PlayerEntity entity, AimGeometry.Ray ray) {
        BlockHitResult result = raycast(world, entity, ray);
        return result.getType() == HitResult.Type.BLOCK ? Hit.of(result) : null;
    }
    private static boolean sameHit(Hit first, Hit second) {
        return first != null && second != null && first.block.equals(second.block) && first.side == second.side
                && first.inside == second.inside && first.point.squaredDistanceTo(second.point) < 1e-12;
    }
    private boolean bounded(BlockPos target) {
        return Math.abs(target.getX() - seed.getX()) <= 2 && Math.abs(target.getY() - seed.getY()) <= 2
                && Math.abs(target.getZ() - seed.getZ()) <= 2;
    }
    private static Vec3d vec(Protocol.Vec3 value) { return new Vec3d(value.x(), value.y(), value.z()); }
    private static boolean loaded(World world, Set<BlockPos> cells) {
        return cells.stream().allMatch(world::isChunkLoaded);
    }
    private static Map<BlockPos, CellState> states(MinecraftClient client, Set<BlockPos> cells) { return states(client.world, cells); }
    private static Map<BlockPos, CellState> states(World world, Set<BlockPos> cells) {
        var values = new LinkedHashMap<BlockPos, CellState>();
        for (BlockPos pos : cells) {
            var state = world.getBlockState(pos);
            values.put(pos, new CellState(Registries.BLOCK.getId(state.getBlock()).toString(), state.isAir(),
                    state.isOf(Blocks.STONE), state.isSideSolidFullSquare(world, pos, Direction.UP)));
        }
        return Map.copyOf(values);
    }
    private static Stack selected(PlayerEntity entity) {
        int slot = entity.getInventory().selectedSlot; ItemStack stack = entity.getInventory().getStack(slot);
        return new Stack(slot, Registries.ITEM.getId(stack.getItem()).toString(), stack.getCount());
    }
    private Decision rejected(long id, int action, String reason, BlockPos target, Hit hit) {
        lastResult = new Result(id, action, "rejected", reason, target, hit, false);
        append(requests, receipt(lastResult)); return new Decision(false, reason);
    }
    private Decision admit(long id, int action) {
        if (id <= lastId) return rejected(id, action, "request_id_not_increasing", null, null);
        lastId = id;
        return null;
    }
    private void finishRejected(Plan plan, String reason) {
        lastResult = new Result(plan.id, plan.action, "rejected", reason, plan.target, plan.hit, false);
        append(requests, plannedReceipt(plan, lastResult)); pending = null; dispatched = false;
    }
    private void fail(String reason) {
        if (failure == null) failure = reason;
        if (pending != null) finishRejected(pending, reason);
        baseline = false;
    }
    private void append(JsonArray array, JsonObject value) { if (array.size() < MAX_RECEIPTS) array.add(value); else omittedReceipts++; }
    private static JsonObject receipt(Result result) {
        var value = new JsonObject(); value.addProperty("id", result.id); value.addProperty("action", result.action);
        value.addProperty("status", result.status); value.addProperty("reason", result.reason);
        value.addProperty("client_and_server", result.clientAndServer);
        if (result.target != null) value.add("target", pos(result.target));
        if (result.hit != null) {
            value.add("hit_block", pos(result.hit.block)); value.addProperty("face", result.hit.side.name());
            var point = new JsonArray(); point.add(result.hit.point.x); point.add(result.hit.point.y); point.add(result.hit.point.z); value.add("hit_point", point);
        }
        return value;
    }
    private static JsonObject plannedReceipt(Plan plan, Result result) {
        var value = receipt(result); value.addProperty("bootstrap", plan.bootstrap);
        value.addProperty("selected_slot", plan.selected.slot); value.addProperty("selected_item", plan.selected.item);
        value.addProperty("selected_count", plan.selected.count);
        if (plan.ray != null) {
            var ray = new JsonObject(); ray.add("origin", vector(plan.ray.hostRay.origin()));
            ray.add("direction", vector(plan.ray.hostRay.direction())); ray.addProperty("range", plan.ray.hostRay.range());
            ray.addProperty("age_at_queue_ns", plan.at - plan.ray.capturedAtNanos);
            ray.addProperty("host_obstruction", plan.ray.occlusion.kind.name());
            ray.addProperty("host_obstruction_distance", plan.ray.occlusion.distance); value.add("host_ray", ray);
        }
        return value;
    }
    private static JsonObject vector(Protocol.Vec3 vector) {
        var value = new JsonObject(); value.addProperty("x", vector.x()); value.addProperty("y", vector.y()); value.addProperty("z", vector.z()); return value;
    }
    private static JsonObject pos(BlockPos pos) {
        var value = new JsonObject(); value.addProperty("x", pos.getX()); value.addProperty("y", pos.getY()); value.addProperty("z", pos.getZ()); return value;
    }
    public boolean ready() { return baseline && failure == null && !closed; }
    public boolean pending() { return pending != null; }
    public boolean failed() { return failure != null; }
    public String failure() { return failure; }
    public BlockPos seedCell() { return seed; }
    public Result lastResult() { return lastResult; }
    public Set<BlockPos> ownedCells() { return Set.copyOf(owned); }
    public JsonObject evidence() {
        var value = new JsonObject(); value.addProperty("schema", 1); value.addProperty("kind", "minecome_aimed_stone_arena_v1");
        value.addProperty("save", save); value.addProperty("ready", ready()); value.addProperty("failure", failure);
        value.addProperty("pending", pending()); value.addProperty("bootstrapped", bootstrapped); value.addProperty("owned_count", owned.size());
        value.addProperty("max_owned_count", AimGeometry.MAX_OWNED_CELLS); value.addProperty("eye_tolerance", MAX_REQUEST_VIEW_ORIGIN_OFFSET);
        value.addProperty("max_host_ray_range", MAX_HOST_RAY_RANGE);
        var pinned = new JsonObject(); pinned.add("minecraft_anchor", vector(alignment.minecraftAnchor()));
        pinned.add("host_anchor", vector(alignment.kcdAnchor())); pinned.addProperty("blocks_per_host_unit", alignment.blocksPerUnit()); value.add("alignment", pinned);
        value.addProperty("max_ray_age_ms", MAX_RAY_AGE_NS / 1_000_000L); value.addProperty("omitted_receipts", omittedReceipts);
        value.addProperty("vanilla_outline_raycast", true); value.addProperty("fluid_raycast", "NONE");
        value.addProperty("block_writes", 0); value.addProperty("inventory_writes", 0); value.addProperty("camera_writes", 0);
        value.addProperty("live_transport_enabled", false); value.add("requests", requests.deepCopy()); value.add("confirmations", confirmations.deepCopy());
        if (seed != null) {
            value.add("seed", pos(seed)); value.add("arena_minimum", pos(seed.add(-2, -2, -2)));
            value.add("arena_maximum_inclusive", pos(seed.add(2, 2, 2)));
        }
        var cells = new JsonArray(); owned.forEach(cell -> cells.add(pos(cell))); value.add("owned_cells", cells);
        return value;
    }
    @Override public void close() { closed = true; if (pending != null) finishRejected(pending, "arena_closed"); observation.set(null); }
}
