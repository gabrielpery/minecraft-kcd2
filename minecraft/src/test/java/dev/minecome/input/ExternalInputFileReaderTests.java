package dev.minecome.input;

import com.sun.nio.file.ExtendedOpenOption;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;
import java.util.function.BooleanSupplier;

/** Standalone file/queue fixtures only; never starts a game or consumes real keys. */
public final class ExternalInputFileReaderTests {
    private static int checks, skipped;
    private static Path root, fixtures;
    private static void check(boolean condition, String message) {
        checks++; if (!condition) throw new AssertionError(message);
    }
    private static void waitFor(BooleanSupplier condition, String message) throws InterruptedException {
        long deadline = System.nanoTime() + Duration.ofSeconds(3).toNanos();
        while (!condition.getAsBoolean() && System.nanoTime() < deadline) Thread.sleep(5);
        check(condition.getAsBoolean(), message);
    }
    private static Path source(String name) throws IOException {
        Path directory = fixtures.resolve(name);
        Files.createDirectories(directory);
        return directory.resolve("input.ndjson");
    }
    private static ExternalInputFileReader ready(Path path) throws Exception {
        var reader = new ExternalInputFileReader(root, path);
        reader.start();
        waitFor(() -> reader.isReady() || reader.failure() != null, "reader completes new-file preflight");
        if (reader.failure() != null) {
            reader.close(); reader.awaitStopped(Duration.ofSeconds(1));
            throw reader.failure();
        }
        check(reader.isReady(), "fresh source ready before writer creation");
        return reader;
    }
    private static void stopped(ExternalInputFileReader reader) throws Exception {
        reader.close();
        check(reader.awaitStopped(Duration.ofSeconds(1)), "reader daemon/channel stopped within bounded join");
        check(reader.isClosed() && reader.drain(64).isEmpty(), "close clears queued input");
    }
    private static void fail(ExternalInputFileReader reader, String message) throws Exception {
        waitFor(() -> reader.failure() != null, message);
        check(reader.isClosed() && reader.drain(64).isEmpty(), "failure closes/clears mailbox");
        check(reader.awaitStopped(Duration.ofSeconds(1)), "failed reader daemon/channel stopped");
    }
    private static void writeNew(Path path, byte[] bytes) throws IOException {
        Files.write(path, bytes, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE);
    }
    private static void append(Path path, String text) throws IOException {
        Files.writeString(path, text, StandardCharsets.UTF_8, StandardOpenOption.APPEND);
    }
    private static List<byte[]> drainUntil(ExternalInputFileReader reader, int count) throws Exception {
        List<byte[]> frames = new ArrayList<>();
        long deadline = System.nanoTime() + Duration.ofSeconds(3).toNanos();
        while (frames.size() < count && reader.failure() == null && System.nanoTime() < deadline) {
            List<byte[]> batch = reader.drain(Math.min(64, count - frames.size()));
            if (!batch.isEmpty()) {
                try { batch.add(new byte[0]); throw new AssertionError("mutable drain list"); }
                catch (UnsupportedOperationException expected) { checks++; }
            }
            frames.addAll(batch);
            if (frames.size() < count) Thread.sleep(5);
        }
        check(reader.failure() == null && frames.size() == count, "expected complete records delivered");
        return frames;
    }

    private static void partialAppendAndCopies() throws Exception {
        Path path = source("partial-append");
        var reader = ready(path);
        try {
            check(reader.drain(64).isEmpty(), "missing file before writer is not EOF/failure");
            writeNew(path, "first".getBytes(StandardCharsets.UTF_8));
            Thread.sleep(50);
            check(reader.drain(64).isEmpty() && reader.failure() == null, "partial tail is never decoded or emitted: " + reader.failure());
            append(path, "\nsecond\r\nthird");
            List<byte[]> frames = drainUntil(reader, 2);
            check(new String(frames.get(0), StandardCharsets.UTF_8).equals("first\n"), "LF framing exact");
            check(new String(frames.get(1), StandardCharsets.UTF_8).equals("second\r\n"), "CRLF preserved for strict decoder");
            frames.get(0)[0] = 'X';
            check(frames.get(1)[0] == 's', "delivered byte arrays have independent ownership");
            Thread.sleep(30);
            check(reader.failure() == null && reader.drain(64).isEmpty(), "EOF with partial tail continues waiting");
            append(path, "\n");
            check(new String(drainUntil(reader, 1).get(0), StandardCharsets.UTF_8).equals("third\n"), "appending after EOF resumes exactly once");
            append(path, "fourth\n");
            drainUntil(reader, 1);
            check(reader.drain(64).isEmpty(), "no replay from reopened/repeated reads");
        } finally { stopped(reader); }
    }

    private static void utf8AndLineBounds() throws Exception {
        var valid = ready(source("split-utf8"));
        Path validPath = fixtures.resolve("split-utf8/input.ndjson");
        try {
            writeNew(validPath, new byte[]{(byte)0xc3});
            Thread.sleep(30);
            check(valid.drain(64).isEmpty() && valid.failure() == null, "split UTF8 waits for complete LF");
            Files.write(validPath, new byte[]{(byte)0xa9, '\n'}, StandardOpenOption.APPEND);
            check(Arrays.equals(drainUntil(valid, 1).get(0), new byte[]{(byte)0xc3, (byte)0xa9, '\n'}), "valid split UTF8 delivered intact");
        } finally { stopped(valid); }
        byte[][] invalid = {
            {(byte)0xc3, 0x28, '\n'}, {(byte)0xef, (byte)0xbb, (byte)0xbf, '{', '}', '\n'},
            {'\n'}, {'\r', '\n'}, {' ', '\t', '\n'}
        };
        for (int i = 0; i < invalid.length; i++) {
            Path path = source("invalid-frame-" + i);
            var reader = ready(path);
            try { writeNew(path, invalid[i]); fail(reader, "invalid UTF8/BOM/empty frame rejected"); }
            finally { stopped(reader); }
        }
        Path bounded = source("line-bound-valid");
        var reader = ready(bounded);
        try {
            writeNew(bounded, ("a".repeat(4095) + "\n").getBytes(StandardCharsets.UTF_8));
            check(drainUntil(reader, 1).get(0).length == 4096, "4096byte frame including LF accepted");
        } finally { stopped(reader); }
        for (int length : new int[]{4096, 4097}) {
            Path path = source("line-bound-invalid-" + length);
            reader = ready(path);
            try { writeNew(path, "a".repeat(length).getBytes(StandardCharsets.UTF_8)); fail(reader, "unfinishable/oversized partial line rejected"); }
            finally { stopped(reader); }
        }
    }

    private static void replacementTruncationAndOverflow() throws Exception {
        Path path = source("truncate");
        var reader = ready(path);
        try {
            writeNew(path, "one\ntwo\n".getBytes(StandardCharsets.UTF_8));
            drainUntil(reader, 2);
            Files.write(path, new byte[0], StandardOpenOption.TRUNCATE_EXISTING);
            fail(reader, "truncation below read cursor rejected");
        } finally { stopped(reader); }
        path = source("replacement"); reader = ready(path);
        try {
            writeNew(path, "original\n".getBytes(StandardCharsets.UTF_8)); drainUntil(reader, 1);
            Files.move(path, path.resolveSibling("original.ndjson"));
            writeNew(path, "replacement\n".getBytes(StandardCharsets.UTF_8));
            fail(reader, "path replacement cannot silently reopen a new source");
        } finally { stopped(reader); }
        path = source("queue-overflow"); reader = ready(path);
        try {
            writeNew(path, "frame\n".repeat(129).getBytes(StandardCharsets.UTF_8));
            fail(reader, "129unconsumed frames overflow bounded128mailbox");
        } finally { stopped(reader); }
        path = source("byte-budget"); reader = ready(path);
        try {
            writeNew(path, new byte[ExternalInputFileReader.MAX_BYTES + 1]);
            fail(reader, "file size beyond1MiB rejected before reading");
        } finally { stopped(reader); }
    }

    private static void recordBudget() throws Exception {
        Path path = source("record-budget");
        var reader = ready(path);
        try {
            writeNew(path, new byte[0]);
            int sent = 0;
            while (sent < 2500) {
                int batch = Math.min(64, 2500 - sent);
                append(path, "x\n".repeat(batch));
                drainUntil(reader, batch); sent += batch;
            }
            check(reader.failure() == null, "2500complete records within reader budget accepted");
            append(path, "overflow\n");
            fail(reader, "2501strecord exceeds bounded session");
        } finally { stopped(reader); }
    }

    private static void closeWithWindowsWriterOpen() throws Exception {
        if (!System.getProperty("os.name").startsWith("Windows")) return;
        Path path = source("writer-kept-open");
        var reader = ready(path);
        // Same sharing contract as native CREATE_NEW / GENERIC_WRITE / FILE_SHARE_READ.
        // Exercise actual cleanup before the writer handle is closed.
        try (var writer = FileChannel.open(path, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE,
                ExtendedOpenOption.NOSHARE_WRITE, ExtendedOpenOption.NOSHARE_DELETE)) {
            writer.write(ByteBuffer.wrap("held-open\n".getBytes(StandardCharsets.UTF_8)));
            drainUntil(reader, 1);
            stopped(reader);
            check(reader.failure() == null, "reader cleanup succeeds while Windows writer is open: " + reader.failure());
            try (var paths = Files.list(path.getParent())) {
                check(paths.noneMatch(file -> file.getFileName().toString().startsWith(".reader-identity-")),
                        "identity link removed before Windows writer shutdown");
            }
            check(writer.isOpen() && Files.isRegularFile(path), "reader close preserves owned writer/source");
        } finally { stopped(reader); }
    }

    private static void pathsWaitAndClose() throws Exception {
        Path existing = source("existing-recording");
        writeNew(existing, "historical\n".getBytes(StandardCharsets.UTF_8));
        var reader = new ExternalInputFileReader(root, existing); reader.start();
        try { fail(reader, "existing recording refused before readiness"); check(!reader.isReady(), "existing recording never READY"); }
        finally { stopped(reader); }
        reader = new ExternalInputFileReader(root, root.resolve("outside-evidence-never-created.ndjson")); reader.start();
        try { fail(reader, "parent outside evidence rejected"); }
        finally { stopped(reader); }
        try { new ExternalInputFileReader(root, Path.of("relative.ndjson")); throw new AssertionError("relative source accepted"); }
        catch (IOException expected) { checks++; }
        for (Duration invalid : List.of(Duration.ZERO, Duration.ofSeconds(-1), Duration.ofSeconds(21))) {
            try { new ExternalInputFileReader(root, source("invalid-wait-" + checks), invalid); throw new AssertionError("invalid creation wait accepted"); }
            catch (IOException expected) { checks++; }
        }
        reader = new ExternalInputFileReader(root, source("creation-deadline"), Duration.ofMillis(50)); reader.start();
        try { fail(reader, "missing file creation wait expires"); }
        finally { stopped(reader); }
        reader = ready(source("close-waiting"));
        long before = System.nanoTime(); reader.close();
        check(System.nanoTime() - before < Duration.ofMillis(100).toNanos(), "game-thread close is signal-only and prompt");
        check(reader.awaitStopped(Duration.ofSeconds(1)), "close while file missing stops daemon");
        check(reader.failure() == null, "normal close while waiting is not a failure");
        try { reader.start(); throw new AssertionError("closed reader restarted"); }
        catch (IllegalStateException expected) { checks++; }
        try { reader.drain(0); throw new AssertionError("zero drain accepted"); }
        catch (IllegalArgumentException expected) { checks++; }
        try { reader.drain(65); throw new AssertionError("oversized drain accepted"); }
        catch (IllegalArgumentException expected) { checks++; }
        reader = ready(source("close-queued"));
        Path queued = fixtures.resolve("close-queued/input.ndjson");
        try {
            writeNew(queued, "queued\npartial".getBytes(StandardCharsets.UTF_8));
            Thread.sleep(30); reader.close();
            check(reader.drain(64).isEmpty(), "world/session close cannot dispatch queued or partial input");
        } finally { stopped(reader); }
    }

    private static boolean symlink(Path link, Path target) throws IOException {
        try { Files.createSymbolicLink(link, target); return true; }
        catch (UnsupportedOperationException | java.nio.file.FileSystemException unavailable) {
            skipped++; System.out.println("EXTERNAL_INPUT_FILE_TEST_SKIP symlink_creation_unavailable"); return false;
        }
    }
    private static void symlinkContainment() throws Exception {
        Path linkParent = fixtures.resolve("linked-parent");
        if (symlink(linkParent, root.resolve("docs"))) {
            var reader = new ExternalInputFileReader(root, linkParent.resolve("never-created.ndjson")); reader.start();
            try { fail(reader, "symlink parent escaping evidence rejected"); }
            finally { stopped(reader); }
        }
        Path fakeRoot = fixtures.resolve("linked-evidence-root");
        Files.createDirectories(fakeRoot.resolve("runtime"));
        if (symlink(fakeRoot.resolve("runtime/evidence"), fixtures)) {
            var reader = new ExternalInputFileReader(fakeRoot, fixtures.resolve("never-created.ndjson")); reader.start();
            try { fail(reader, "evidence root resolving outside project rejected"); }
            finally { stopped(reader); }
        }
        Path source = source("symlink-file");
        Path target = source.resolveSibling("target.ndjson"); writeNew(target, "target\n".getBytes(StandardCharsets.UTF_8));
        var reader = ready(source);
        try { if (symlink(source, target)) fail(reader, "source replaced with symlink before open rejected"); }
        finally { stopped(reader); }
    }

    private static Path findRoot(String[] args) throws IOException {
        if (args.length > 1) throw new IOException("usage: ExternalInputFileReaderTests [absolute-project-root]");
        if (args.length == 1) return Path.of(args[0]).toRealPath();
        Path path = Path.of("").toAbsolutePath();
        for (int i = 0; path != null && i < 20; i++, path = path.getParent()) {
            if (Files.isRegularFile(path.resolve("AGENTS.md")) && Files.isRegularFile(path.resolve("CMakeLists.txt"))) return path.toRealPath();
        }
        throw new IOException("MineCome project root not found");
    }

    public static void main(String[] args) throws Exception {
        root = findRoot(args);
        fixtures = root.resolve("runtime/evidence/input-reader-tests-" + UUID.randomUUID());
        Files.createDirectories(fixtures);
        partialAppendAndCopies(); utf8AndLineBounds(); replacementTruncationAndOverflow();
        recordBudget(); pathsWaitAndClose(); symlinkContainment(); closeWithWindowsWriterOpen();
        try (var paths = Files.walk(fixtures)) {
            check(paths.noneMatch(path -> path.getFileName().toString().startsWith(".reader-identity-")),
                    "all owned identity links removed after normal and failed reads");
        }
        System.out.println("EXTERNAL_INPUT_FILE_TEST_PASS checks=" + checks + " skipped=" + skipped + " fixtures=" + fixtures);
    }
}
