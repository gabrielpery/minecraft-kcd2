package dev.minecome.input;

import dev.minecome.terrain.GroundCollision;
import dev.minecome.terrain.GroundPatch;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientLifecycleEvents;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.minecraft.client.MinecraftClient;
import net.minecraft.registry.RegistryKeys;
import net.minecraft.registry.entry.RegistryEntryList;
import net.minecraft.resource.DataConfiguration;
import net.minecraft.util.math.*;
import net.minecraft.world.*;
import net.minecraft.world.biome.BiomeKeys;
import net.minecraft.world.gen.*;
import net.minecraft.world.gen.chunk.*;
import net.minecraft.world.level.LevelInfo;
import org.slf4j.*;

import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;

/** Isolated external-input application proof. Vanilla alone ticks movement, jumping and collision. */
public final class ExternalInputLab {
    private static final Logger LOG = LoggerFactory.getLogger("MineComeExternalInput");
    private static volatile ExternalInputLab active;
    private static final double SPAWN_X = 0.5, SPAWN_Z = 0.5;
    private final GroundPatch patch;
    private final Path inputFile;
    private final ExternalInputSessionGate.Identity identity;
    private final ExternalInputSessionGate gate;
    private final boolean fixture;
    private final long initializedAt = System.nanoTime();
    private final AtomicLong corrections = new AtomicLong();
    private final AtomicBoolean serverReadPending = new AtomicBoolean(), prepared = new AtomicBoolean(), installed = new AtomicBoolean();
    private final AtomicReference<Object> serverWorldIdentity = new AtomicReference<>();
    private final AtomicReference<ServerSample> serverSample = new AtomicReference<>();
    private final AtomicReference<String> serverFailure = new AtomicReference<>();
    private record Motion(double x, double y, double z, double vx, double vy, double vz,
                          boolean grounded, boolean support, float yaw, float pitch) {}
    private record ServerSample(Object world, long sequence, long receivedAt, Motion motion) {}
    private ExternalInputFileReader reader;
    private Object labWorld, labPlayer, ownedServer;
    private UUID playerId;
    private String saveName;
    private long worldAt, teleportAt, stableAt, stableCorrectionCount, correctionBaseline, inputAt, terminalAt;
    private long lastServerSequence, serverSequence, landingStableAt;
    private int ticks, receivedFrames, appliedFrames, mouseApplications;
    private boolean started, setupRequested, teleportRequested, ready, terminal, clientAir, serverAir, clientLand, serverLand;
    private volatile boolean stopping;
    private Boolean oldPauseOnLostFocus;
    private Motion baselineClient, baselineServer, latestClient;
    private double clientWalk, serverWalk;
    private boolean clientYaw, clientPitch, serverYaw, serverPitch;
    private ExternalInputSessionGate.Input held = ExternalInputSessionGate.Input.NEUTRAL;

    private ExternalInputLab(GroundPatch patch, Path inputFile, ExternalInputSessionGate.Identity identity, boolean fixture) {
        this.patch = patch; this.inputFile = inputFile; this.identity = identity; this.fixture = fixture;
        gate = new ExternalInputSessionGate(identity);
    }
    public static void initialize() {
        if (!Boolean.getBoolean("minecome.externalInputLab")) return;
        if (active != null) throw new IllegalStateException("External input lab already initialized");
        try {
            var identity = new ExternalInputSessionGate.Identity(required("minecome.externalInputRun"),
                    Long.parseLong(required("minecome.externalInputTargetPid")), required("minecome.externalInputTargetStartFiletime"));
            var lab = new ExternalInputLab(GroundPatch.read(Path.of(required("minecome.groundPatchFile"))),
                    Path.of(required("minecome.externalInputFile")), identity, Boolean.getBoolean("minecome.externalInputFixture"));
            active = lab;
            LOG.info("EXTERNAL_INPUT_LAB_INITIALIZED inputRun={} sourceKind={} patchRun={} patchSha256={} fixture={} physicalInputVerified=false approximateHeightfield=true fullCollisionExportVerified=false",
                    identity.run(), lab.patch.sourceKind(), lab.patch.run(), lab.patch.sha256(), lab.fixture);
            ClientTickEvents.START_CLIENT_TICK.register(lab::beforeTick);
            ClientTickEvents.END_CLIENT_TICK.register(lab::afterTick);
            ClientLifecycleEvents.CLIENT_STOPPING.register(client -> {
                lab.stopping = true; lab.release(client); lab.gate.disconnect();
                if (lab.reader != null) lab.reader.close();
                if (lab.oldPauseOnLostFocus != null) client.options.pauseOnLostFocus = lab.oldPauseOnLostFocus;
                GroundCollision.clear(); active = null;
            });
        } catch (Exception e) {
            LOG.error("EXTERNAL_INPUT_LAB_FAIL phase=initialization reason={}", e.getMessage());
            ClientTickEvents.END_CLIENT_TICK.register(MinecraftClient::scheduleStop);
        }
    }
    private static String required(String property) {
        String value = System.getProperty(property);
        if (value == null || value.isBlank()) throw new IllegalArgumentException(property + " is required");
        return value;
    }
    /** Observation only, called by the existing vanilla correction-handler RETURN mixin. */
    public static void positionCorrection() { var lab = active; if (lab != null) lab.corrections.incrementAndGet(); }

    private void beforeTick(MinecraftClient client) {
        if (stopping) { release(client); return; }
        long now = System.nanoTime();
        if (now - initializedAt >= 120_000_000_000L) { fail(client, "Global startup/runtime deadline120s"); return; }
        if (!started && client.currentScreen != null && client.getOverlay() == null) create(client);
        if (!started || client.world == null || client.player == null || !client.isIntegratedServerRunning()) {
            release(client); if (labWorld != null) fail(client, "Owned singleplayer connection ended"); return;
        }
        if (!owned(client)) { fail(client, "World/player identity changed; refusing other saves"); return; }
        if (labWorld == null) {
            labWorld = client.world; labPlayer = client.player; ownedServer = client.getServer();
            playerId = client.player.getUuid(); worldAt = now;
        }
        if (now - worldAt >= 60_000_000_000L) { fail(client, "World runtime60s without complete terminal proof"); return; }
        if (serverFailure.get() != null) { fail(client, serverFailure.get()); return; }
        if (!setupRequested) { install(client, now); return; }
        if (!installed.get()) {
            release(client);
            if (prepared.get() && !teleportRequested) {
                if (!allProxyCellsAir(client.world)) { fail(client, "Client vanilla blocks overlap proxy cells"); return; }
                GroundCollision.install(client.world, patch, false);
                teleportRequested = true; teleportAt = now; teleport(client);
            } else if (now - teleportAt > 6_000_000_000L) fail(client, "Server proxy/teleport setup timeout");
            return;
        }
        requestServerSample(client);
        ServerSample sample = serverSample.get();
        if (sample == null || sample.world() != serverWorldIdentity.get() || System.nanoTime() - sample.receivedAt() > 250_000_000L) {
            release(client);
            if (!ready) stableAt = 0;
            if (ready || now - teleportAt > 20_000_000_000L) fail(client, "Fresh server observation missing");
            return;
        }
        if (!ready) {
            release(client);
            if (client.currentScreen != null || client.getOverlay() != null || client.player.getPos().squaredDistanceTo(
                    SPAWN_X, patch.heightAt(SPAWN_X, SPAWN_Z) + 0.05, SPAWN_Z) > 1) {
                stableAt = 0;
                if (now - teleportAt > 20_000_000_000L) fail(client, "Initial vanilla loading/teleport handoff timeout"); return;
            }
            var current = motion(client.world, client.player);
            if (!grounded(current) || !grounded(sample.motion()) || corrections.get() != stableCorrectionCount) {
                stableAt = 0; stableCorrectionCount = corrections.get(); return;
            }
            if (stableAt == 0) stableAt = now;
            if (now - stableAt < 2_000_000_000L) return;
            if (client.options.smoothCameraEnabled || client.player.isUsingSpyglass() || client.options.getSprintToggled().getValue()) {
                fail(client, "Held-input lab requires ordinary unsmoothed camera and hold-to-sprint options"); return;
            }
            try {
                if (reader == null) {
                    Path project = client.runDirectory.toPath().toAbsolutePath().normalize().getParent().getParent();
                    reader = new ExternalInputFileReader(project, inputFile); reader.start();
                }
                if (reader.failure() != null) throw reader.failure();
                if (!reader.isReady()) return;
            } catch (Exception e) { fail(client, "Input reader initialization: " + e.getMessage()); return; }
            baselineClient = current; baselineServer = sample.motion(); latestClient = current;
            correctionBaseline = corrections.get(); ready = true;
            LOG.info("EXTERNAL_INPUT_LAB_READY inputRun={} save={} patchRun={} patchSha256={} sourceKind={} fixture={} physicalInputVerified=false client={} server={} correctionBaseline={} inputFile={} serverInstalled=true clientInstalled=true",
                    identity.run(), saveName, patch.run(), patch.sha256(), patch.sourceKind(), fixture,
                    baselineClient, baselineServer, correctionBaseline, inputFile);
        }
        if (client.currentScreen != null || client.getOverlay() != null || client.isPaused()) { fail(client, "Menu/overlay/pause opened; input neutralized"); return; }
        if (client.interactionManager == null || client.interactionManager.getCurrentGameMode() != GameMode.ADVENTURE ||
                client.player.getAbilities().allowFlying || client.player.getAbilities().flying || client.options.smoothCameraEnabled || client.player.isUsingSpyglass()) {
            fail(client, "Adventure/nonflying ordinary unsmoothed camera contract changed"); return;
        }
        // GameOptions uses StickyKeyBinding for sprint. Repeated held-state replay is
        // only the inspected hold-to-sprint mode; toggled sprint ignores false releases.
        if (client.options.getSprintToggled().getValue()) { fail(client, "Toggle-sprint mode unsupported by bounded held-input lab"); return; }
        if (corrections.get() != correctionBaseline) { fail(client, "Server position correction after stable handoff"); return; }
        if (!safe(motion(client.world, client.player)) || !safe(sample.motion())) { fail(client, "Leaving bounded sampled collision coverage"); return; }
        if (reader.failure() != null) { fail(client, "External input reader failed: " + reader.failure().getMessage()); return; }
        try {
            for (byte[] frame : reader.drain(64)) {
                var record = ExternalInputDecoder.decode(frame);
                gate.receive(frame, System.currentTimeMillis(), System.nanoTime()); receivedFrames++;
                if (record.kind() == ExternalInputRecord.Kind.BEGIN) inputAt = System.nanoTime();
                if (record.kind() == ExternalInputRecord.Kind.END) { terminal = true; terminalAt = System.nanoTime(); }
            }
        } catch (Exception e) { fail(client, "External input rejected: " + e.getMessage()); return; }
        if (reader.failure() != null) { fail(client, "External input reader failed after drain: " + reader.failure().getMessage()); return; }
        if (!terminal && inputAt != 0 && now - inputAt >= 45_000_000_000L) { fail(client, "Input session45s deadline; terminal end missing"); return; }
        held = gate.consume(System.nanoTime(), true); apply(client, held);
        if (held.active()) {
            appliedFrames++;
            if (held.mouseDx() != 0 || held.mouseDy() != 0) {
                double sensitivity = client.options.getMouseSensitivity().getValue();
                if (!Double.isFinite(sensitivity) || sensitivity < 0 || sensitivity > 1) { fail(client, "Invalid mouse sensitivity option"); return; }
                // Exact cached Yarn1.21.1 Mouse.updateMouse ordinary branch. Entity applies0.15f itself.
                double f = sensitivity * 0.6000000238418579 + 0.20000000298023224;
                double scale = f * f * f * 8.0;
                client.player.changeLookDirection(held.mouseDx() * scale,
                        held.mouseDy() * scale * (client.options.getInvertYMouse().getValue() ? -1 : 1));
                mouseApplications++;
            }
        }
        if (receivedFrames > 0 && ++ticks % 2 == 0)
            LOG.info("EXTERNAL_INPUT_APPLIED inputRun={} inputSeq={} active={} held={} mouseDx={} mouseDy={} clientYaw={} clientPitch={} receivedFrames={} appliedFrames={}",
                    identity.run(), gate.lastSequence(), held.active(), held.held(), held.mouseDx(), held.mouseDy(),
                    client.player.getYaw(), client.player.getPitch(), receivedFrames, appliedFrames);
    }

    private void afterTick(MinecraftClient client) {
        if (stopping || !ready || !owned(client)) return;
        long now = System.nanoTime();
        if (!gate.consume(now, true).active()) release(client);
        latestClient = motion(client.world, client.player);
        var sample = serverSample.get();
        if (!safe(latestClient)) { fail(client, "Vanilla client movement reached coverage boundary"); return; }
        if (sample == null || sample.world() != serverWorldIdentity.get() || System.nanoTime() - sample.receivedAt() > 250_000_000L) {
            fail(client, "End-tick server observation missing/stale"); return;
        }
        clientWalk = Math.max(clientWalk, horizontal(latestClient, baselineClient));
        if (!latestClient.grounded() && latestClient.y() > baselineClient.y() + 0.15) clientAir = true;
        if (clientAir && grounded(latestClient)) clientLand = true;
        clientYaw |= Math.abs(MathHelper.wrapDegrees(latestClient.yaw() - baselineClient.yaw())) > 0.1;
        clientPitch |= Math.abs(latestClient.pitch() - baselineClient.pitch()) > 0.1;
        if (sample.sequence() > lastServerSequence) {
            lastServerSequence = sample.sequence(); var s = sample.motion();
            if (!safe(s)) { fail(client, "Vanilla server movement reached coverage boundary"); return; }
            serverWalk = Math.max(serverWalk, horizontal(s, baselineServer));
            if (!s.grounded() && s.y() > baselineServer.y() + 0.15) serverAir = true;
            if (serverAir && grounded(s)) serverLand = true;
            serverYaw |= Math.abs(MathHelper.wrapDegrees(s.yaw() - baselineServer.yaw())) > 0.1;
            serverPitch |= Math.abs(s.pitch() - baselineServer.pitch()) > 0.1;
        }
        if (ticks % 10 == 0) LOG.info("EXTERNAL_INPUT_OBSERVATION inputRun={} client={} server={} serverSeq={} serverAgeMillis={} postSettleCorrections={}",
                identity.run(), latestClient, sample.motion(), sample.sequence(), (System.nanoTime() - sample.receivedAt()) / 1_000_000, corrections.get() - correctionBaseline);
        if (!terminal) return;
        release(client);
        boolean resting = grounded(latestClient) && grounded(sample.motion()) && horizontalSpeed(latestClient) < 0.02 && horizontalSpeed(sample.motion()) < 0.02;
        if (!resting) landingStableAt = 0; else if (landingStableAt == 0) landingStableAt = now;
        boolean proof = clientWalk >= 0.15 && serverWalk >= 0.15 && clientAir && serverAir && clientLand && serverLand &&
                clientYaw && clientPitch && serverYaw && serverPitch && mouseApplications > 0 && gate.closed() && keysReleased(client) &&
                corrections.get() == correctionBaseline && resting && now - landingStableAt >= 500_000_000L;
        if (proof) {
            LOG.info("EXTERNAL_INPUT_LAB_PASS inputRun={} save={} patchRun={} patchSha256={} sourceKind={} fixture={} physicalInputVerified=false actualVanillaMCInputApplication=true clientWalk={} serverWalk={} clientAir={} serverAir={} clientLand={} serverLand={} clientYawChanged={} clientPitchChanged={} serverYawChanged={} serverPitchChanged={} inputNeutralAfterEnd=true postSettleCorrections={} receivedFrames={} appliedFrames={} mouseApplications={} client={} server={} serverSeq={} fullWorldMovementAuthorityVerified=false",
                    identity.run(), saveName, patch.run(), patch.sha256(), patch.sourceKind(), fixture, clientWalk, serverWalk,
                    clientAir, serverAir, clientLand, serverLand, clientYaw, clientPitch, serverYaw, serverPitch,
                    corrections.get() - correctionBaseline, receivedFrames, appliedFrames, mouseApplications, latestClient, sample.motion(), sample.sequence());
            stopping = true; reader.close(); client.scheduleStop();
        } else if (now - terminalAt > 4_000_000_000L) fail(client, "Terminal received but client/server walk/jump/look/neutral proof incomplete");
    }

    private void create(MinecraftClient client) {
        started = true;
        if (client.world != null || client.isIntegratedServerRunning()) { fail(client, "Refusing already open world"); return; }
        oldPauseOnLostFocus = client.options.pauseOnLostFocus; client.options.pauseOnLostFocus = false;
        saveName = "MineCome-ExternalInput-" + UUID.randomUUID();
        Path save = client.runDirectory.toPath().resolve("saves").resolve(saveName).normalize();
        if (Files.exists(save)) { fail(client, "Refusing existing save"); return; }
        GameRules rules = new GameRules(); rules.get(GameRules.DO_MOB_SPAWNING).set(false, null);
        rules.get(GameRules.SPAWN_CHUNK_RADIUS).set(0, null); rules.get(GameRules.SPAWN_RADIUS).set(0, null);
        LevelInfo info = new LevelInfo(saveName, GameMode.ADVENTURE, false, Difficulty.PEACEFUL, true, rules, DataConfiguration.SAFE_MODE);
        LOG.info("External input lab creating NEW isolated empty Adventure world: {}", save);
        client.createIntegratedServerLoader().createAndStart(saveName, info, new GeneratorOptions(42, false, false), registries -> {
            var biome = registries.get(RegistryKeys.BIOME).getEntry(BiomeKeys.THE_VOID).orElseThrow();
            var config = new FlatChunkGeneratorConfig(Optional.of(RegistryEntryList.of()), biome, List.of()); config.updateLayerBlocks();
            return registries.get(RegistryKeys.WORLD_PRESET).get(WorldPresets.FLAT).createDimensionsRegistryHolder().with(registries, new FlatChunkGenerator(config));
        }, client.currentScreen);
    }
    private boolean owned(MinecraftClient client) {
        return !stopping && saveName != null && client.world != null && client.player != null && client.getServer() != null &&
                client.isIntegratedServerRunning() && (ownedServer == null || ownedServer == client.getServer()) &&
                (labWorld == null || labWorld == client.world) && (labPlayer == null || labPlayer == client.player) &&
                client.world.getRegistryKey() == World.OVERWORLD;
    }
    private void install(MinecraftClient client, long now) {
        setupRequested = true; teleportAt = now; release(client); var server = client.getServer();
        server.execute(() -> {
            if (stopping) return;
            try {
                var world = server.getOverworld(); var player = server.getPlayerManager().getPlayer(playerId);
                if (!saveName.equals(server.getSaveProperties().getLevelName()) || player == null || player.getWorld() != world ||
                        !(world.getChunkManager().getChunkGenerator() instanceof FlatChunkGenerator generator) || !generator.getConfig().getLayerBlocks().isEmpty())
                    throw new IllegalStateException("Server new empty world/player identity failed");
                if (!allProxyCellsAir(world)) throw new IllegalStateException("Server vanilla blocks overlap proxy cells");
                GroundCollision.install(world, patch, true); server.setFlightEnabled(true);
                if (player.getAbilities().allowFlying || player.getAbilities().flying) throw new IllegalStateException("Unexpected player flight abilities");
                serverWorldIdentity.set(world); prepared.set(true);
            } catch (Exception e) { serverFailure.set("Server proxy setup: " + e.getMessage()); }
        });
    }
    private void teleport(MinecraftClient client) {
        var server = client.getServer(); server.execute(() -> {
            if (stopping) return;
            try {
                var world = server.getOverworld(); var player = server.getPlayerManager().getPlayer(playerId);
                if (server != ownedServer || world != serverWorldIdentity.get() || player == null || player.getWorld() != world ||
                        !saveName.equals(server.getSaveProperties().getLevelName()) || !GroundCollision.installed(world, true))
                    throw new IllegalStateException("Owned server identity before initial teleport changed");
                player.teleport(world, SPAWN_X, patch.heightAt(SPAWN_X, SPAWN_Z) + 0.05, SPAWN_Z, 90, 0);
                player.setVelocity(Vec3d.ZERO); player.fallDistance = 0; installed.set(true);
            } catch (Exception e) { serverFailure.set("Initial server teleport: " + e.getMessage()); }
        });
    }
    private void requestServerSample(MinecraftClient client) {
        if (!serverReadPending.compareAndSet(false, true)) return;
        var server = client.getServer(); long sequence = ++serverSequence;
        server.execute(() -> {
            try {
                if (stopping) return;
                var world = server.getOverworld(); var player = server.getPlayerManager().getPlayer(playerId);
                if (server != ownedServer || world != serverWorldIdentity.get() || player == null || player.getWorld() != world ||
                        !saveName.equals(server.getSaveProperties().getLevelName()) || !GroundCollision.installed(world, true) || !allProxyCellsAir(world))
                    throw new IllegalStateException("Server player/proxy identity changed");
                serverSample.set(new ServerSample(world, sequence, System.nanoTime(), motion(world, player)));
            } catch (Exception e) { serverFailure.set("Server observation: " + e.getMessage()); }
            finally { serverReadPending.set(false); }
        });
    }
    private boolean allProxyCellsAir(BlockView world) {
        for (var cell : patch.cells()) if (!world.getBlockState(new BlockPos(cell.x(), cell.y(), cell.z())).isAir()) return false;
        return true;
    }
    private static Motion motion(CollisionView world, net.minecraft.entity.Entity player) {
        var p = player.getPos(); var v = player.getVelocity(); var b = player.getBoundingBox(); boolean support = false;
        var below = new Box(b.minX + 0.001, b.minY - 0.06, b.minZ + 0.001, b.maxX - 0.001, b.minY + 0.001, b.maxZ - 0.001);
        for (var shape : world.getBlockCollisions(player, below)) if (!shape.isEmpty()) { support = true; break; }
        return new Motion(p.x, p.y, p.z, v.x, v.y, v.z, player.isOnGround(), support, player.getYaw(), player.getPitch());
    }
    private boolean safe(Motion motion) {
        if (!Double.isFinite(motion.y()) || !Double.isFinite(motion.vy()) || !Float.isFinite(motion.yaw()) || !Float.isFinite(motion.pitch()) ||
                !patch.containsFeet(motion.x(), motion.z(), 0.5) || !patch.containsFeet(motion.x() + motion.vx() * 2, motion.z() + motion.vz() * 2, 0.5)) return false;
        double floor = patch.groundForFeet(motion.x(), motion.z(), 0.29);
        return motion.y() >= floor - 0.2 && motion.y() <= floor + 2.0;
    }
    private boolean grounded(Motion motion) {
        return motion.grounded() && motion.support() && safe(motion) && Math.abs(motion.vy()) < 0.1 &&
                Math.abs(motion.y() - patch.groundForFeet(motion.x(), motion.z(), 0.29)) < 0.16;
    }
    private static double horizontal(Motion a, Motion b) { return Math.hypot(a.x() - b.x(), a.z() - b.z()); }
    private static double horizontalSpeed(Motion motion) { return Math.hypot(motion.vx(), motion.vz()); }
    private static void apply(MinecraftClient client, ExternalInputSessionGate.Input input) {
        var h = input.held(); client.options.forwardKey.setPressed(h.forward()); client.options.backKey.setPressed(h.back());
        client.options.leftKey.setPressed(h.left()); client.options.rightKey.setPressed(h.right());
        client.options.jumpKey.setPressed(h.jump()); client.options.sprintKey.setPressed(h.sprint());
    }
    private void release(MinecraftClient client) { held = ExternalInputSessionGate.Input.NEUTRAL; apply(client, held); }
    private static boolean keysReleased(MinecraftClient client) {
        return !client.options.forwardKey.isPressed() && !client.options.backKey.isPressed() && !client.options.leftKey.isPressed() &&
                !client.options.rightKey.isPressed() && !client.options.jumpKey.isPressed() && !client.options.sprintKey.isPressed();
    }
    private void fail(MinecraftClient client, String reason) {
        if (stopping) return;
        stopping = true; release(client); gate.disconnect(); if (reader != null) reader.close();
        LOG.error("EXTERNAL_INPUT_LAB_FAIL inputRun={} save={} sourceKind={} fixture={} physicalInputVerified=false reason={} receivedFrames={} appliedFrames={} inputNeutral={} client={} server={} postSettleCorrections={}",
                identity.run(), saveName, patch.sourceKind(), fixture, reason, receivedFrames, appliedFrames,
                keysReleased(client), latestClient, serverSample.get(), corrections.get() - correctionBaseline);
        client.scheduleStop();
    }
}
