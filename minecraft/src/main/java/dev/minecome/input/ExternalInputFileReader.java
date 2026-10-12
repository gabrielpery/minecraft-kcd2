package dev.minecome.input;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.NoSuchFileException;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.BasicFileAttributes;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.locks.LockSupport;

/**
 * One newly created, append-only input file; transport only, with no game APIs.
 * All filesystem access (including real-path validation and channel close) occurs
 * on the owned daemon. A caller starts it, waits for isReady(), then announces READY
 * to its trusted writer. This format/path is not a claim of source authentication.
 *
 * Java21 API contracts:
 * https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/nio/channels/FileChannel.html
 * https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/nio/file/attribute/BasicFileAttributes.html
 * https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/concurrent/ArrayBlockingQueue.html
 */
public final class ExternalInputFileReader implements AutoCloseable {
    public static final int MAX_BYTES = 1_048_576, MAX_RECORDS = 2500;
    public static final int MAX_LINE_BYTES = 4096, QUEUE_CAPACITY = 128, MAX_DRAIN = 64;
    public static final Duration MAX_CREATION_WAIT = Duration.ofSeconds(20);
    private static final long POLL_NANOS = 10_000_000L;
    private final Path projectRoot, source;
    private final long creationWaitNanos;
    private final ArrayBlockingQueue<byte[]> records = new ArrayBlockingQueue<>(QUEUE_CAPACITY);
    private final Object mailbox = new Object();
    private final AtomicBoolean closeRequested = new AtomicBoolean();
    private final AtomicBoolean ready = new AtomicBoolean();
    private final AtomicBoolean stopped = new AtomicBoolean();
    private final AtomicReference<IOException> failure = new AtomicReference<>();
    private volatile Thread worker;

    /** Syntax only; no filesystem operations or threads are started here. */
    public ExternalInputFileReader(Path projectRoot, Path source) throws IOException {
        this(projectRoot, source, MAX_CREATION_WAIT);
    }

    /** Shorter creation waits support controllers/tests; the maximum remains20s. */
    public ExternalInputFileReader(Path projectRoot, Path source, Duration creationWait) throws IOException {
        Objects.requireNonNull(projectRoot); Objects.requireNonNull(source); Objects.requireNonNull(creationWait);
        if (!projectRoot.isAbsolute() || !source.isAbsolute() || source.getParent() == null || source.getFileName() == null)
            throw new IOException("External input requires absolute project/file paths");
        this.projectRoot = projectRoot.normalize();
        this.source = source.normalize();
        if (this.source.getFileName() == null || this.source.getFileName().toString().isBlank())
            throw new IOException("External input requires a file name");
        long wait;
        try { wait = creationWait.toNanos(); }
        catch (ArithmeticException error) { throw new IOException("Invalid external input creation wait", error); }
        if (wait <= 0 || wait > MAX_CREATION_WAIT.toNanos())
            throw new IOException("External input creation wait must be positive and at most20s");
        creationWaitNanos = wait;
    }

    /** Returns promptly. Path/new-file validation happens before isReady() turns true. */
    public synchronized void start() {
        if (worker != null || closeRequested.get()) throw new IllegalStateException("External input reader cannot restart");
        Thread thread = new Thread(this::read, "MineComeExternalInputFileReader");
        thread.setDaemon(true);
        worker = thread;
        thread.start();
    }

    public boolean isReady() { return ready.get() && !closeRequested.get(); }
    public boolean isClosed() { return closeRequested.get(); }
    /** A non-null failure means the consumer must release controls and close its gate. */
    public IOException failure() { return failure.get(); }

    /** Complete LF frames only. No file IO; immutable list, independent byte copies. */
    public List<byte[]> drain(int maxRecords) {
        if (maxRecords < 1 || maxRecords > MAX_DRAIN) throw new IllegalArgumentException("Drain must be1..64");
        synchronized (mailbox) {
            if (closeRequested.get() || failure.get() != null) return List.of();
            List<byte[]> result = new ArrayList<>(maxRecords);
            for (int i = 0; i < maxRecords; i++) {
                byte[] frame = records.poll();
                if (frame == null) break;
                result.add(frame.clone());
            }
            return List.copyOf(result);
        }
    }

    /** Signal only: no channel IO, joins or game-thread waiting. Clears pending input. */
    @Override public void close() {
        synchronized (mailbox) { closeRequested.set(true); records.clear(); }
        LockSupport.unpark(worker);
    }

    /** Controller/tests only; never call this from a game tick. Does no file IO. */
    public boolean awaitStopped(Duration timeout) throws InterruptedException {
        Objects.requireNonNull(timeout);
        long millis;
        try { millis = timeout.toMillis(); }
        catch (ArithmeticException error) { throw new IllegalArgumentException("Invalid stop timeout", error); }
        if (millis < 1 || millis > 1000) throw new IllegalArgumentException("Stop wait must be1..1000ms");
        Thread thread = worker;
        if (thread == null) return closeRequested.get();
        if (thread == Thread.currentThread()) throw new IllegalStateException("Reader cannot join itself");
        thread.join(millis);
        return stopped.get() && !thread.isAlive();
    }

    private void fail(IOException error) {
        synchronized (mailbox) {
            failure.compareAndSet(null, error);
            closeRequested.set(true);
            records.clear();
        }
    }

    private record Paths(Path evidence, Path parent, Path canonicalSource) {}

    private Paths validateNewPath() throws IOException {
        Path root = projectRoot.toRealPath();
        Path evidence = projectRoot.resolve("runtime/evidence").toRealPath();
        if (!Files.isDirectory(root) || !Files.isDirectory(evidence) ||
                !evidence.startsWith(root) || evidence.equals(root))
            throw new IOException("Resolved external input evidence root escapes project");
        Path parent = source.getParent().toRealPath();
        if (!Files.isDirectory(parent) || !parent.startsWith(evidence))
            throw new IOException("Resolved external input parent escapes runtime/evidence");
        Path canonical = parent.resolve(source.getFileName());
        try {
            Files.readAttributes(canonical, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
            throw new IOException("External input file must be new, not an existing recording");
        } catch (NoSuchFileException expected) {
            // Only an actual missing-file result qualifies; permissions/IO errors fail.
        }
        return new Paths(evidence, parent, canonical);
    }

    private void verifyParent(Paths paths) throws IOException {
        try {
            if (!projectRoot.resolve("runtime/evidence").toRealPath().equals(paths.evidence()) ||
                    !source.getParent().toRealPath().equals(paths.parent()))
                throw new IOException("External input parent was replaced or redirected");
        } catch (NoSuchFileException missing) {
            throw new IOException("External input parent disappeared", missing);
        }
    }

    private BasicFileAttributes attributes(Paths paths) throws IOException {
        verifyParent(paths);
        BasicFileAttributes attrs = Files.readAttributes(paths.canonicalSource(), BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
        if (!attrs.isRegularFile() || attrs.isSymbolicLink())
            throw new IOException("External input must be a regular file without a symlink");
        if (attrs.size() < 0 || attrs.size() > MAX_BYTES) throw new IOException("External input exceeds1MiB");
        return attrs;
    }

    private void pause() { LockSupport.parkNanos(this, POLL_NANOS); }

    private void read() {
        Path identityLink = null;
        boolean ownsIdentityLink = false;
        try {
            if (closeRequested.get()) return;
            Paths paths = validateNewPath();
            synchronized (mailbox) {
                if (closeRequested.get()) return;
                ready.set(true);
            }
            final long waitingSince = System.nanoTime();
            BasicFileAttributes first = null;
            while (!closeRequested.get()) {
                if (System.nanoTime() - waitingSince >= creationWaitNanos)
                    throw new IOException("External input file creation deadline expired");
                try { first = attributes(paths); break; }
                catch (NoSuchFileException missing) {
                    if (System.nanoTime() - waitingSince >= creationWaitNanos)
                        throw new IOException("External input file creation deadline expired", missing);
                    pause();
                }
            }
            if (closeRequested.get() || first == null) return;
            // Windows JDK21/24 exposes a null BasicFileAttributes.fileKey(). A private
            // hard link keeps a stable name for Files.isSameFile's OS identity check.
            // Only diagnostic-file link metadata changes. Unsupported filesystems fail
            // closed. The trusted controller creates this source after our READY.
            if (first.fileKey() == null) {
                identityLink = paths.parent().resolve(".reader-identity-" + UUID.randomUUID());
                Files.createLink(identityLink, paths.canonicalSource());
                ownsIdentityLink = true;
                if (!Files.isSameFile(paths.canonicalSource(), identityLink))
                    throw new IOException("External input replaced while establishing identity");
            }
            Path channelPath = identityLink == null ? paths.canonicalSource() : identityLink;
            // Open once through the stable identity link on Windows. NOFOLLOW_LINKS
            // rejects a symlink substitution; source identity is checked every poll.
            try (FileChannel channel = FileChannel.open(channelPath, StandardOpenOption.READ, LinkOption.NOFOLLOW_LINKS)) {
                BasicFileAttributes opened = attributes(paths);
                if (identityLink == null ? !first.fileKey().equals(opened.fileKey())
                        : !Files.isSameFile(paths.canonicalSource(), identityLink))
                    throw new IOException("External input replaced during open");
                Object identity = opened.fileKey();
                long position = 0, observedSize = Math.max(first.size(), opened.size());
                int lines = 0;
                ByteBuffer buffer = ByteBuffer.allocate(8192);
                ByteArrayOutputStream partial = new ByteArrayOutputStream(512);
                while (!closeRequested.get()) {
                    BasicFileAttributes attrs = attributes(paths);
                    if (identityLink == null ? !identity.equals(attrs.fileKey())
                            : !Files.isSameFile(paths.canonicalSource(), identityLink))
                        throw new IOException("External input file identity was replaced");
                    if (attrs.size() < position || attrs.size() < observedSize)
                        throw new IOException("External input file was truncated");
                    observedSize = attrs.size();
                    buffer.clear();
                    int count = channel.read(buffer);
                    if (count <= 0) { pause(); continue; } // EOF is not a terminal record.
                    if (position + count > MAX_BYTES) throw new IOException("External input stream exceeds1MiB");
                    position += count;
                    buffer.flip();
                    while (buffer.hasRemaining() && !closeRequested.get()) {
                        byte value = buffer.get();
                        partial.write(value);
                        if (partial.size() > MAX_LINE_BYTES || (value != '\n' && partial.size() == MAX_LINE_BYTES))
                            throw new IOException("External input line exceeds4096bytes including LF");
                        if (value != '\n') continue;
                        byte[] frame = partial.toByteArray();
                        partial.reset();
                        if (++lines > MAX_RECORDS) throw new IOException("External input exceeds2500records");
                        validateFrame(frame);
                        synchronized (mailbox) {
                            if (closeRequested.get()) return;
                            if (!records.offer(frame)) throw new IOException("External input mailbox overflow");
                        }
                    }
                }
            }
        } catch (IOException error) {
            fail(error);
        } catch (RuntimeException error) {
            fail(new IOException("External input reader failed", error));
        } finally {
            if (ownsIdentityLink) {
                try { Files.deleteIfExists(identityLink); }
                catch (IOException error) { fail(new IOException("External input identity-link cleanup failed", error)); }
            }
            stopped.set(true);
        }
    }

    private static void validateFrame(byte[] frame) throws IOException {
        String text = StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(frame)).toString();
        if (text.startsWith("\ufeff") || text.isBlank())
            throw new IOException("External input contains BOM or empty record");
    }
}
