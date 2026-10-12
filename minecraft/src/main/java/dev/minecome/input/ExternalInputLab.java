package dev.minecome.input;

import dev.minecome.terrain.GroundCollision;
import dev.minecome.terrain.GroundPatch;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientLifecycleEvents;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import net.minecraft.client.MinecraftClient;
import net.minecraft.server.MinecraftServer;
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
import java.math.BigInteger;
import java.util.*;
import java.util.concurrent.atomic.*;

/** Isolated external-input application proof. Vanilla alone ticks movement, jumping and collision. */
public final class ExternalInputLab {
    private static final Logger LOG = LoggerFactory.getLogger("MineComeExternalInput");
    private static volatile ExternalInputLab active;
    private static final double SPAWN_X = 0.5, SPAWN_Z = 0.5;
    private final GroundPatch patch;
    private final HostViewSeed viewSeed;
    private final Path inputFile;
    private final Path poseFile;
    private final ExternalInputSessionGate.Identity identity;
    private final ExternalInputSessionGate gate;
    private final boolean fixture;
    private final long initializedAt = System.nanoTime();
    private final AtomicLong corrections = new AtomicLong();
    private final AtomicBoolean prepared = new AtomicBoolean(), installed = new AtomicBoolean();
    private final AtomicReference<Object> serverWorldIdentity = new AtomicReference<>();
    private final AtomicReference<ServerSample> serverSample = new AtomicReference<>();
    private final AtomicReference<String> serverFailure = new AtomicReference<>();
    private record Motion(double x, double y, double z, double vx, double vy, double vz,
                          boolean grounded, boolean support, float yaw, float pitch) {}
    private record ServerSample(Object world, long sequence, long receivedAt, Motion motion) {}
    private ExternalInputFileReader reader;
    private ExternalInputPoseSink poseSink;
    private BigInteger inputDispatchWatermark = BigInteger.ZERO;
    private boolean initialPosePending = true, poseFinalQueued;
    private Object labWorld, labPlayer, ownedServer;
    private UUID playerId;
    private String saveName;
    private long worldAt, teleportAt, stableAt, stableCorrectionCount, correctionBaseline, inputAt, terminalAt;
    private long lastServerSequence, serverSequence, landingStableAt, serverStaleAt;
    private int serverObservationPauses;
    private int ticks, receivedFrames, appliedFrames, mouseApplications, discardedFrames;
    private boolean started, setupRequested, teleportRequested, ready, terminal, clientAir, serverAir, clientLand, serverLand;
    private volatile boolean stopping;
    private Boolean oldPauseOnLostFocus;
    private record RenderSettings(boolean vsync, int frameLimit, int viewDistance, int simulationDistance) {}
    private RenderSettings oldRenderSettings;
    private Motion baselineClient, baselineServer, latestClient;
    private double clientWalk, serverWalk;
    private boolean clientYaw, clientPitch, serverYaw, serverPitch;
    private ExternalInputSessionGate.Input held = ExternalInputSessionGate.Input.NEUTRAL;

    private ExternalInputLab(GroundPatch patch, HostViewSeed viewSeed, Path inputFile, Path poseFile, ExternalInputSessionGate.Identity identity, boolean fixture) {
        this.patch = patch; this.viewSeed = viewSeed; this.inputFile = inputFile; this.poseFile = poseFile; this.identity = identity; this.fixture = fixture;
        gate = new ExternalInputSessionGate(identity);
    }
    public static void initialize() {
        if (!Boolean.getBoolean("minecome.externalInputLab")) return;
        if (active != null) throw new IllegalStateException("External input lab already initialized");
        try {
            var identity = new ExternalInputSessionGate.Identity(required("minecome.externalInputRun"),
                    Long.parseLong(required("minecome.externalInputTargetPid")), required("minecome.externalInputTargetStartFiletime"));
            var patch = GroundPatch.read(Path.of(required("minecome.groundPatchFile")));
            boolean fixture = Boolean.getBoolean("minecome.externalInputFixture");
            var viewSeed = HostViewSeed.read(Path.of(required("minecome.externalInputViewFile")), identity, patch.sha256(), fixture,
                    patch.centerX(), patch.centerY(), patch.centerZ(), System.currentTimeMillis());
            var lab = new ExternalInputLab(patch, viewSeed, Path.of(required("minecome.externalInputFile")),
                    Path.of(required("minecome.externalInputPoseFile")), identity, fixture);
            active = lab;
            LOG.info("EXTERNAL_INPUT_LAB_INITIALIZED inputRun={} sourceKind={} patchRun={} patchSha256={} fixture={} physicalInputVerified=false approximateHeightfield=true fullCollisionExportVerified=false viewSeedSha256={} viewSeedKind={} viewCapturedUtcMs={} initialYaw={} initialPitch={} initialViewSnapshotOnly=true",
                    identity.run(), lab.patch.sourceKind(), lab.patch.run(), lab.patch.sha256(), lab.fixture,
                    viewSeed.sha256(), viewSeed.sourceKind(), viewSeed.capturedUtcMillis(), viewSeed.yawDegrees(), viewSeed.pitchDegrees());
            ClientTickEvents.START_CLIENT_TICK.register(lab::beforeTick);
            ClientTickEvents.END_CLIENT_TICK.register(lab::afterTick);
            // Fabric lifecycle-v1 END_SERVER_TICK: sampled on the server's own thread,
            // independent of client render stalls or focus changes.
            ServerTickEvents.END_SERVER_TICK.register(lab::observeServer);
            ClientLifecycleEvents.CLIENT_STOPPING.register(client -> {
                lab.stopping = true; lab.release(client); lab.gate.disconnect();
                if (lab.reader != null) lab.reader.close();
                if (lab.poseSink != null) lab.poseSink.close();
                if (lab.oldPauseOnLostFocus != null) client.options.pauseOnLostFocus = lab.oldPauseOnLostFocus;
                if (lab.oldRenderSettings != null) {
                    var previous = lab.oldRenderSettings;
                    client.getWindow().setVsync(previous.vsync());
                    client.getWindow().setFramerateLimit(previous.frameLimit());
                    client.options.getViewDistance().setValue(previous.viewDistance());
                    client.options.getSimulationDistance().setValue(previous.simulationDistance());
                    LOG.info("EXTERNAL_INPUT_RENDER_SETTINGS_RESTORED inputRun={} previous={}", lab.identity.run(), previous);
                }
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
        if (now - initializedAt >= 180_000_000_000L) { fail(client, "Global startup/runtime deadline180s"); return; }
        if (!started && client.currentScreen != null && client.getOverlay() == null) create(client);
        if (!started || client.world == null || client.player == null || !client.isIntegratedServerRunning()) {
            release(client); if (labWorld != null) fail(client, "Owned singleplayer connection ended"); return;
        }
        if (!owned(client)) { fail(client, "World/player identity changed; refusing other saves"); return; }
        // Inspected Yarn1.21.1 Mouse.tick requires cursorLocked for local camera input.
        // unlockCursor changes only cursor state; the explicit external look path remains active.
        if (client.mouse.isCursorLocked()) client.mouse.unlockCursor();
        if (labWorld == null) {
            labWorld = client.world; labPlayer = client.player; ownedServer = client.getServer();
            playerId = client.player.getUuid(); worldAt = now;
        }
        // Allows60s operator arm wait +40s active input + bounded setup/terminal settling.
        // The independent gate still caps all input at120s and every sample lease at300ms.
        if (now - worldAt >= 135_000_000_000L) { fail(client, "World runtime135s without complete terminal proof"); return; }
        if (serverFailure.get() != null) { fail(client, serverFailure.get()); return; }
        if (poseSink != null && poseSink.failure() != null) { fail(client, "Pose output failed: " + poseSink.failure().getMessage()); return; }
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
        ServerSample sample = serverSample.get();
        if (sample != null && sample.world() != serverWorldIdentity.get()) { fail(client, "Server observation world identity changed"); return; }
        boolean serverFresh = sample != null && System.nanoTime() - sample.receivedAt() <= 250_000_000L;
        if (!serverFresh && !ready) {
            release(client);
            stableAt = 0;
            if (now - teleportAt > 20_000_000_000L) fail(client, "Fresh server observation missing");
            return;
        }
        if (ready && !observeServerFreshness(client, serverFresh, now)) return;
        if (!ready) {
            release(client);
            if (client.currentScreen != null || client.getOverlay() != null || client.player.getPos().squaredDistanceTo(
                    SPAWN_X, patch.heightAt(SPAWN_X, SPAWN_Z) + 0.05, SPAWN_Z) > 1) {
                stableAt = 0;
                if (now - teleportAt > 20_000_000_000L) fail(client, "Initial vanilla loading/teleport handoff timeout"); return;
            }
            var current = motion(client.world, client.player);
            boolean viewMatches = initialViewMatches(current) && initialViewMatches(sample.motion());
            if (!grounded(current) || !grounded(sample.motion()) || corrections.get() != stableCorrectionCount || !viewMatches) {
                stableAt = 0; stableCorrectionCount = corrections.get();
                if (!viewMatches && now - teleportAt > 20_000_000_000L) fail(client, "Initial view seed did not reach both client/server within startup handoff deadline");
                return;
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
                if (poseSink == null) {
                    Path project = client.runDirectory.toPath().toAbsolutePath().normalize().getParent().getParent();
                    var s = sample.motion();
                    var context = new ExternalInputPoseSink.Context(identity, patch.run(), patch.sha256(), viewSeed.sha256(),
                            patch.sourceKind(), fixture, saveName, saveName.substring("MineCome-ExternalInput-".length()),
                            new ExternalInputPoseSink.Vec3(patch.centerX(), patch.centerY(), patch.centerZ()),
                            new ExternalInputPoseSink.Vec3(s.x(), s.y(), s.z()));
                    poseSink = new ExternalInputPoseSink(project, poseFile, context, System.currentTimeMillis()); poseSink.start();
                }
                if (poseSink.failure() != null) throw poseSink.failure();
                if (!poseSink.isReady()) return;
            } catch (Exception e) { fail(client, "Input/pose daemon initialization: " + e.getMessage()); return; }
            baselineClient = current; baselineServer = sample.motion(); latestClient = current;
            correctionBaseline = corrections.get(); ready = true;
            LOG.info("EXTERNAL_INPUT_LAB_READY inputRun={} save={} patchRun={} patchSha256={} sourceKind={} fixture={} physicalInputVerified=false client={} server={} correctionBaseline={} inputFile={} serverInstalled=true clientInstalled=true viewSeedSha256={} viewSeedKind={} viewCapturedUtcMs={} initialYaw={} initialPitch={} initialClientViewVerified=true initialServerViewVerified=true initialViewSnapshotOnly=true",
                    identity.run(), saveName, patch.run(), patch.sha256(), patch.sourceKind(), fixture,
                    baselineClient, baselineServer, correctionBaseline, inputFile,
                    viewSeed.sha256(), viewSeed.sourceKind(), viewSeed.capturedUtcMillis(), viewSeed.yawDegrees(), viewSeed.pitchDegrees());
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
        if (!safe(motion(client.world, client.player)) || (sample != null && !safe(sample.motion()))) { fail(client, "Leaving bounded sampled collision coverage"); return; }
        if (reader.failure() != null) { fail(client, "External input reader failed: " + reader.failure().getMessage()); return; }
        try {
            for (byte[] frame : reader.drain(64)) {
                var record = ExternalInputDecoder.decode(frame);
                boolean accepted = gate.receiveLive(frame, System.currentTimeMillis(), System.nanoTime()); receivedFrames++;
                if (!accepted) {
                    discardedFrames++;
                    LOG.info("EXTERNAL_INPUT_EXPIRED_SAMPLE_DROPPED inputRun={} inputSeq={} discardedFrames={} requiresFreshNeutral=true",
                            identity.run(), record.sequence(), discardedFrames);
                }
                if (record.kind() == ExternalInputRecord.Kind.BEGIN) inputAt = System.nanoTime();
                if (record.kind() == ExternalInputRecord.Kind.END) { terminal = true; terminalAt = System.nanoTime(); }
            }
        } catch (Exception e) { fail(client, "External input rejected: " + e.getMessage()); return; }
        if (reader.failure() != null) { fail(client, "External input reader failed after drain: " + reader.failure().getMessage()); return; }
        if (!terminal && inputAt != 0 && now - inputAt >= 105_000_000_000L) { fail(client, "Input session105s deadline; terminal end missing"); return; }
        held = gate.consume(System.nanoTime(), serverFresh); apply(client, held);
        if (held.active()) {
            // Dispatch watermark only: it does not identify a vanilla server packet ACK.
            inputDispatchWatermark = gate.lastSequence();
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
        latestClient = motion(client.world, client.player);
        var sample = serverSample.get();
        if (!safe(latestClient)) { fail(client, "Vanilla client movement reached coverage boundary"); return; }
        if (sample != null && sample.world() != serverWorldIdentity.get()) { fail(client, "End-tick server world identity changed"); return; }
        boolean serverFresh = sample != null && System.nanoTime() - sample.receivedAt() <= 250_000_000L;
        if (!gate.consume(now, serverFresh).active()) release(client);
        if (!observeServerFreshness(client, serverFresh, now) || !serverFresh) return;
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
        if (!terminal) { publishPose(client, sample, initialPosePending); return; }
        release(client);
        if (now - terminalAt > 4_000_000_000L) { fail(client, "Terminal proof/output flush exceeded existing4s deadline"); return; }
        boolean resting = grounded(latestClient) && grounded(sample.motion()) && horizontalSpeed(latestClient) < 0.02 && horizontalSpeed(sample.motion()) < 0.02;
        if (!resting) landingStableAt = 0; else if (landingStableAt == 0) landingStableAt = now;
        boolean proof = clientWalk >= 0.15 && serverWalk >= 0.15 && clientAir && serverAir && clientLand && serverLand &&
                clientYaw && clientPitch && serverYaw && serverPitch && mouseApplications > 0 && gate.closed() && keysReleased(client) &&
                corrections.get() == correctionBaseline && resting && now - landingStableAt >= 500_000_000L;
        if (proof) {
            try {
                if (!poseFinalQueued) {
                    if (!writePose(sample, true)) {
                        if (now - terminalAt > 4_000_000_000L) fail(client, "Fresh advancing final pose sample missing within existing terminal deadline");
                        return;
                    }
                    poseSink.finish(System.currentTimeMillis(), "passed", "Actual vanilla client/server input proof; audit-only pose output");
                    poseFinalQueued = true;
                }
                if (poseSink.failure() != null) throw poseSink.failure();
                if (!poseSink.isFinished()) {
                    if (now - terminalAt > 4_000_000_000L) fail(client, "Pose terminal flush did not finish within existing terminal deadline");
                    return;
                }
                // The worker publishes its failure before finished. Re-read after
                // observing completion so a concurrent close failure cannot pass.
                if (poseSink.failure() != null) throw poseSink.failure();
            } catch (Exception e) { fail(client, "Pose output finalization: " + e.getMessage()); return; }
            LOG.info("EXTERNAL_INPUT_POSE_OUTPUT_COMPLETE inputRun={} file={} records={} bytes={} auditOnly=true followerEligible=false controlOwnershipVerified=false kcdMovementApplied=false",
                    identity.run(), poseFile, poseSink.records(), poseSink.byteCount());
            LOG.info("EXTERNAL_INPUT_LAB_PASS inputRun={} save={} patchRun={} patchSha256={} sourceKind={} fixture={} physicalInputVerified=false actualVanillaMCInputApplication=true clientWalk={} serverWalk={} clientAir={} serverAir={} clientLand={} serverLand={} clientYawChanged={} clientPitchChanged={} serverYawChanged={} serverPitchChanged={} inputNeutralAfterEnd=true postSettleCorrections={} receivedFrames={} appliedFrames={} mouseApplications={} client={} server={} serverSeq={} fullWorldMovementAuthorityVerified=false viewSeedSha256={} viewSeedKind={} viewCapturedUtcMs={} initialYaw={} initialPitch={} initialClientViewVerified=true initialServerViewVerified=true initialViewSnapshotOnly=true",
                    identity.run(), saveName, patch.run(), patch.sha256(), patch.sourceKind(), fixture, clientWalk, serverWalk,
                    clientAir, serverAir, clientLand, serverLand, clientYaw, clientPitch, serverYaw, serverPitch,
                    corrections.get() - correctionBaseline, receivedFrames, appliedFrames, mouseApplications, latestClient, sample.motion(), sample.sequence(),
                    viewSeed.sha256(), viewSeed.sourceKind(), viewSeed.capturedUtcMillis(), viewSeed.yawDegrees(), viewSeed.pitchDegrees());
            stopping = true; reader.close(); client.scheduleStop();
        } else if (now - terminalAt > 4_000_000_000L) fail(client, "Terminal received but client/server walk/jump/look/neutral proof incomplete");
        else publishPose(client, sample, initialPosePending);
    }

    private void create(MinecraftClient client) {
        started = true;
        if (client.world != null || client.isIntegratedServerRunning()) { fail(client, "Refusing already open world"); return; }
        oldPauseOnLostFocus = client.options.pauseOnLostFocus; client.options.pauseOnLostFocus = false;
        // Exact1.21.1 Window setters update swap interval/frame budget without writing options.
        // Keep this tiny collision lab inexpensive while the full KCD renderer is active.
        oldRenderSettings = new RenderSettings(client.options.getEnableVsync().getValue(), client.getWindow().getFramerateLimit(),
                client.options.getViewDistance().getValue(), client.options.getSimulationDistance().getValue());
        client.getWindow().setVsync(false); client.getWindow().setFramerateLimit(60);
        client.options.getViewDistance().setValue(4); client.options.getSimulationDistance().setValue(5);
        LOG.info("EXTERNAL_INPUT_RENDER_SETTINGS inputRun={} vsync=false frameLimit=60 viewDistance=4 simulationDistance=5 previous={}", identity.run(), oldRenderSettings);
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
                viewSeed.revalidate(identity, patch.sha256(), fixture, patch.centerX(), patch.centerY(), patch.centerZ(), System.currentTimeMillis());
                player.teleport(world, SPAWN_X, patch.heightAt(SPAWN_X, SPAWN_Z) + 0.05, SPAWN_Z,
                        (float) viewSeed.yawDegrees(), (float) viewSeed.pitchDegrees());
                player.setVelocity(Vec3d.ZERO); player.fallDistance = 0; installed.set(true);
            } catch (Exception e) { serverFailure.set("Initial server teleport: " + e.getMessage()); }
        });
    }
    private void observeServer(MinecraftServer server) {
        if (stopping || !installed.get()) return;
        try {
            var world = server.getOverworld(); var player = server.getPlayerManager().getPlayer(playerId);
            if (server != ownedServer || world != serverWorldIdentity.get() || player == null || player.getWorld() != world ||
                    !saveName.equals(server.getSaveProperties().getLevelName()) || !GroundCollision.installed(world, true) || !allProxyCellsAir(world))
                throw new IllegalStateException("Server player/proxy identity changed");
            serverSample.set(new ServerSample(world, ++serverSequence, System.nanoTime(), motion(world, player)));
        } catch (Exception e) { serverFailure.set("Server observation: " + e.getMessage()); }
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
    private boolean initialViewMatches(Motion motion) {
        return Math.abs(MathHelper.wrapDegrees(motion.yaw() - (float) viewSeed.yawDegrees())) <= 0.1 &&
                Math.abs(motion.pitch() - viewSeed.pitchDegrees()) <= 0.1;
    }
    /** A brief scheduling gap suppresses controls, never relaxes input age or server freshness. */
    private boolean observeServerFreshness(MinecraftClient client, boolean fresh, long now) {
        if (fresh) {
            if (serverStaleAt != 0) LOG.info("EXTERNAL_INPUT_SERVER_RESUMED inputRun={} pauseMillis={} requiresFreshNeutral=true",
                    identity.run(), (now - serverStaleAt) / 1_000_000);
            serverStaleAt = 0;
            return true;
        }
        release(client); gate.consume(now, false); landingStableAt = 0;
        if (serverStaleAt == 0) {
            serverStaleAt = now; serverObservationPauses++;
            LOG.info("EXTERNAL_INPUT_SERVER_PAUSED inputRun={} inputNeutral=true pauseCount={}", identity.run(), serverObservationPauses);
        }
        if (now - serverStaleAt >= 2_000_000_000L) { fail(client, "Server observation unavailable for2s; input neutralized"); return false; }
        return true;
    }
    private static double horizontal(Motion a, Motion b) { return Math.hypot(a.x() - b.x(), a.z() - b.z()); }
    private static ExternalInputPoseSink.Motion poseMotion(Motion motion) {
        return new ExternalInputPoseSink.Motion(motion.x(), motion.y(), motion.z(), motion.vx(), motion.vy(), motion.vz(),
                motion.grounded(), motion.support(), motion.yaw(), motion.pitch());
    }
    private boolean writePose(ServerSample sample, boolean force) throws java.io.IOException {
        boolean written = poseSink.sample(System.nanoTime(), System.currentTimeMillis(), poseMotion(latestClient), poseMotion(sample.motion()),
                sample.sequence(), sample.receivedAt(), inputDispatchWatermark, force);
        if (written) initialPosePending = false;
        return written;
    }
    private void publishPose(MinecraftClient client, ServerSample sample, boolean force) {
        if (!force && inputDispatchWatermark.signum() == 0) return; // Operator arm-wait does not spend the pose stream budget.
        try { writePose(sample, force); }
        catch (Exception e) { fail(client, "Pose output sample: " + e.getMessage()); }
    }
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
        if (poseSink != null) {
            try { poseSink.finish(System.currentTimeMillis(), "failed", reason); }
            catch (Exception e) { LOG.error("EXTERNAL_INPUT_POSE_OUTPUT_FAIL inputRun={} reason={}", identity.run(), e.getMessage()); }
        }
        LOG.error("EXTERNAL_INPUT_LAB_FAIL inputRun={} save={} sourceKind={} fixture={} physicalInputVerified=false reason={} receivedFrames={} appliedFrames={} inputNeutral={} client={} server={} postSettleCorrections={}",
                identity.run(), saveName, patch.sourceKind(), fixture, reason, receivedFrames, appliedFrames,
                keysReleased(client), latestClient, serverSample.get(), corrections.get() - correctionBaseline);
        client.scheduleStop();
    }
}
