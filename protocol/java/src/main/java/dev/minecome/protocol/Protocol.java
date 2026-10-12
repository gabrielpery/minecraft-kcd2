package dev.minecome.protocol;

import java.io.*;
import java.nio.*;
import java.nio.charset.*;
import java.util.Arrays;

/** The v1 wire format, with an opt-in minor 1 stone input extension. */
public final class Protocol {
    private Protocol() {}
    public static final int PORT = 38765, HEADER_SIZE = 32, MAX_PAYLOAD = 65536;
    public static final int HELLO = 1, HEARTBEAT = 2, KCD_POSE = 3, MC_POSE = 4,
            BLOCK_EVENT = 5, ERROR = 6, GOODBYE = 7, STONE_INPUT_REQUEST = 8, STONE_INPUT_RESULT = 9;
    public static final int CAP_STONE_INPUT = 1, PLACE_STONE = 1, BREAK_STONE = 2;
    public static final int INPUT_ACCEPTED = 1, INPUT_UNAVAILABLE = 2, INPUT_STALE = 3,
            INPUT_BUSY = 4, INPUT_OCCUPIED = 5, INPUT_ABSENT = 6, INPUT_VANILLA_FAILED = 7;
    public static final long MAX_INPUT_ID = 9_007_199_254_740_991L;
    public static final int ROLE_KCD = 1, ROLE_MC = 2, ROLE_HARNESS = 3;
    public static final int SPACE_KCD = 1, SPACE_MC = 2;
    public static final int HAS_PLAYER = 1, HAS_CAMERA = 2, CALIBRATED = 4, IN_WORLD = 8;
    public record Frame(int type, int minor, long sequence, long timestampMicros, byte[] payload) {
        public Frame(int type,long sequence,long timestampMicros,byte[] payload) { this(type,0,sequence,timestampMicros,payload); }
        public Frame {
            if (minor < 0 || minor > 1 || type < HELLO || type > (minor==0?GOODBYE:STONE_INPUT_RESULT) ||
                    sequence == 0 || payload.length > MAX_PAYLOAD)
                throw new IllegalArgumentException("Invalid frame");
            payload = payload.clone();
        }
        @Override public byte[] payload() { return payload.clone(); }
    }
    public record Hello(int role, int capabilities, String name, String credential) {}
    public record Vec3(double x, double y, double z) {
        public Vec3 {
            if (!Double.isFinite(x) || !Double.isFinite(y) || !Double.isFinite(z))
                throw new IllegalArgumentException("Non-finite vector");
        }
    }
    /** Camera-to-world unit quaternion, components x/y/z/w. */
    public record Quaternion(double x, double y, double z, double w) {
        public Quaternion {
            double length = x*x + y*y + z*z + w*w;
            if (!Double.isFinite(length) || Math.abs(length - 1) > 0.001)
                throw new IllegalArgumentException("Quaternion must be finite and normalized");
        }
    }
    public record Pose(Vec3 player, Vec3 camera, Quaternion orientation, double verticalFov,
                       Vec3 kcdOrigin, double blocksPerUnit, int space, int flags) {
        public Pose {
            if (!Double.isFinite(verticalFov) || verticalFov <= 0 || verticalFov >= Math.PI ||
                    !Double.isFinite(blocksPerUnit) || blocksPerUnit <= 0 ||
                    (space != SPACE_KCD && space != SPACE_MC) || (flags & ~15) != 0)
                throw new IllegalArgumentException("Invalid pose metadata");
        }
    }
    public record BlockEvent(int operation, int x, int y, int z, String blockId) {}
    public record StoneInputRequest(long requestId,int action) {
        public StoneInputRequest { validateInput(requestId,action); }
    }
    public record StoneInputResult(long requestId,int action,int result) {
        public StoneInputResult {
            validateInput(requestId,action);
            if(result<INPUT_ACCEPTED || result>INPUT_VANILLA_FAILED)throw new IllegalArgumentException("Invalid stone input result");
        }
    }
    private static void validateInput(long requestId,int action) {
        if(requestId<1 || requestId>MAX_INPUT_ID || (action!=PLACE_STONE && action!=BREAK_STONE))
            throw new IllegalArgumentException("Invalid stone input ID/action");
    }
    public static byte[] stoneInputRequest(StoneInputRequest request) {
        return buffer(12).putLong(request.requestId()).putInt(request.action()).array();
    }
    public static StoneInputRequest parseStoneInputRequest(byte[] data) throws IOException {
        if(data.length!=12)throw new IOException("Stone input request must be 12 bytes");
        ByteBuffer b=wrap(data);
        try{return new StoneInputRequest(b.getLong(),b.getInt());}
        catch(IllegalArgumentException e){throw new IOException(e.getMessage(),e);}
    }
    public static byte[] stoneInputResult(StoneInputResult result) {
        return buffer(16).putLong(result.requestId()).putInt(result.action()).putInt(result.result()).array();
    }
    public static StoneInputResult parseStoneInputResult(byte[] data) throws IOException {
        if(data.length!=16)throw new IOException("Stone input result must be 16 bytes");
        ByteBuffer b=wrap(data);
        try{return new StoneInputResult(b.getLong(),b.getInt(),b.getInt());}
        catch(IllegalArgumentException e){throw new IOException(e.getMessage(),e);}
    }
    private static ByteBuffer buffer(int size) { return ByteBuffer.allocate(size).order(ByteOrder.LITTLE_ENDIAN); }
    private static ByteBuffer wrap(byte[] bytes) { return ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN); }
    public static byte[] encode(Frame frame) {
        byte[] payload = frame.payload();
        ByteBuffer b = buffer(HEADER_SIZE + payload.length);
        b.put(new byte[] {'M','C','M','E'}).putShort((short)1).putShort((short)frame.minor())
                .putShort((short)frame.type()).putShort((short)0).putInt(payload.length)
                .putLong(frame.sequence()).putLong(frame.timestampMicros()).put(payload);
        return b.array();
    }
    private static int payloadSize(byte[] header) throws IOException {
        ByteBuffer b = wrap(header);
        if (b.get() != 'M' || b.get() != 'C' || b.get() != 'M' || b.get() != 'E')
            throw new IOException("Bad MineCome magic");
        int major=Short.toUnsignedInt(b.getShort()),minor=Short.toUnsignedInt(b.getShort());
        if (major != 1 || minor > 1)
            throw new IOException("Unsupported protocol version");
        int type = Short.toUnsignedInt(b.getShort()), flags = Short.toUnsignedInt(b.getShort());
        long size = Integer.toUnsignedLong(b.getInt());
        if (type < HELLO || type > (minor==0?GOODBYE:STONE_INPUT_RESULT) || flags != 0 || size > MAX_PAYLOAD)
            throw new IOException("Invalid header type, flags, or length");
        return (int)size;
    }
    public static Frame decode(byte[] wire) throws IOException {
        if (wire.length < HEADER_SIZE) throw new IOException("Truncated header");
        byte[] header = Arrays.copyOf(wire, HEADER_SIZE);
        int size = payloadSize(header);
        if (wire.length != HEADER_SIZE + size) throw new IOException("Payload length mismatch");
        ByteBuffer b = wrap(header);
        int type = Short.toUnsignedInt(b.getShort(8));
        try {
            return new Frame(type,Short.toUnsignedInt(b.getShort(6)), b.getLong(16), b.getLong(24), Arrays.copyOfRange(wire, HEADER_SIZE, wire.length));
        } catch (IllegalArgumentException e) { throw new IOException(e.getMessage(), e); }
    }
    public static Frame read(InputStream in) throws IOException {
        byte[] header = in.readNBytes(HEADER_SIZE);
        if (header.length != HEADER_SIZE) throw new EOFException("Disconnected while reading header");
        int size = payloadSize(header);
        byte[] payload = in.readNBytes(size);
        if (payload.length != size) throw new EOFException("Disconnected while reading payload");
        byte[] wire = Arrays.copyOf(header, HEADER_SIZE + size);
        System.arraycopy(payload, 0, wire, HEADER_SIZE, size);
        return decode(wire);
    }
    public static void write(OutputStream out, Frame frame) throws IOException { out.write(encode(frame)); out.flush(); }
    /** Incremental reader preserves fragmented TCP headers and payloads across polls. */
    public static final class Reader {
        private final byte[] bytes = new byte[HEADER_SIZE + MAX_PAYLOAD];
        private int count, wanted = HEADER_SIZE;
        public Frame poll(InputStream in) throws IOException {
            while (in.available() > 0) {
                int read = in.read(bytes, count, Math.min(in.available(), wanted-count));
                if (read < 0) throw new EOFException("Disconnected");
                count += read;
                if (count == HEADER_SIZE && wanted == HEADER_SIZE) {
                    wanted = HEADER_SIZE + payloadSize(Arrays.copyOf(bytes, HEADER_SIZE));
                }
                if (count == wanted) {
                    Frame result = decode(Arrays.copyOf(bytes, wanted));
                    count=0; wanted=HEADER_SIZE; return result;
                }
            }
            return null;
        }
    }
    public static byte[] hello(Hello h) {
        if (!validHelloCapabilities(h.role(),h.capabilities()))
            throw new IllegalArgumentException("Invalid Hello role/capabilities");
        byte[] name = encodeUtf8(h.name()), token = encodeUtf8(h.credential());
        if (name.length < 1 || name.length > 128 || token.length > 128) throw new IllegalArgumentException("Hello name must be 1..128 UTF-8 bytes; credential at most 128");
        return buffer(12 + name.length + token.length).putInt(h.role()).putInt(h.capabilities())
                .putShort((short)name.length).putShort((short)token.length).put(name).put(token).array();
    }
    private static byte[] encodeUtf8(String text) {
        try {
            ByteBuffer encoded=StandardCharsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).encode(CharBuffer.wrap(text));
            byte[] result=new byte[encoded.remaining()]; encoded.get(result); return result;
        } catch(CharacterCodingException e) { throw new IllegalArgumentException("Invalid Unicode string",e); }
    }
    private static String utf8(ByteBuffer b, int length) throws IOException {
        if (length > b.remaining()) throw new IOException("Truncated UTF-8 string");
        byte[] data = new byte[length]; b.get(data);
        try {
            return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(data)).toString();
        } catch (CharacterCodingException e) { throw new IOException("Invalid UTF-8", e); }
    }
    public static Hello parseHello(byte[] data) throws IOException {
        if (data.length < 12) throw new IOException("Truncated Hello");
        ByteBuffer b = wrap(data); int role = b.getInt(), caps = b.getInt();
        int nl = Short.toUnsignedInt(b.getShort()), tl = Short.toUnsignedInt(b.getShort());
        if (!validHelloCapabilities(role,caps) || nl < 1 || nl > 128 || tl > 128 || nl + tl != b.remaining())
            throw new IOException("Invalid Hello");
        return new Hello(role, caps, utf8(b, nl), utf8(b, tl));
    }
    private static boolean validHelloCapabilities(int role,int caps) {
        return role>=ROLE_KCD && role<=ROLE_HARNESS &&
                (caps==0 || (caps==CAP_STONE_INPUT && role!=ROLE_HARNESS));
    }
    private static void vec(ByteBuffer b, Vec3 v) { b.putDouble(v.x()).putDouble(v.y()).putDouble(v.z()); }
    private static Vec3 vec(ByteBuffer b) { return new Vec3(b.getDouble(), b.getDouble(), b.getDouble()); }
    public static byte[] pose(Pose p) {
        ByteBuffer b = buffer(128); vec(b,p.player()); vec(b,p.camera());
        Quaternion q = p.orientation(); b.putDouble(q.x()).putDouble(q.y()).putDouble(q.z()).putDouble(q.w());
        b.putDouble(p.verticalFov()); vec(b,p.kcdOrigin());
        return b.putDouble(p.blocksPerUnit()).putInt(p.space()).putInt(p.flags()).array();
    }
    public static Pose parsePose(byte[] data) throws IOException {
        if (data.length != 128) throw new IOException("Pose must be 128 bytes");
        ByteBuffer b = wrap(data);
        try {
            return new Pose(vec(b),vec(b),new Quaternion(b.getDouble(),b.getDouble(),b.getDouble(),b.getDouble()),
                    b.getDouble(),vec(b),b.getDouble(),b.getInt(),b.getInt());
        } catch (IllegalArgumentException e) { throw new IOException("Invalid pose: " + e.getMessage(),e); }
    }
    public static byte[] blockEvent(BlockEvent e) {
        byte[] id = e.blockId().getBytes(StandardCharsets.UTF_8);
        if ((e.operation() != 1 && e.operation() != 2) || id.length == 0 || id.length > 1024 || !validBlockId(e.blockId()))
            throw new IllegalArgumentException("Invalid block event");
        return buffer(18+id.length).putInt(e.operation()).putInt(e.x()).putInt(e.y()).putInt(e.z())
                .putShort((short)id.length).put(id).array();
    }
    public static BlockEvent parseBlockEvent(byte[] data) throws IOException {
        if (data.length < 18) throw new IOException("Truncated block event");
        ByteBuffer b=wrap(data); int op=b.getInt(), x=b.getInt(), y=b.getInt(), z=b.getInt();
        int size=Short.toUnsignedInt(b.getShort());
        if ((op!=1 && op!=2) || size==0 || size>1024 || size!=b.remaining()) throw new IOException("Invalid block event");
        String id=utf8(b,size);
        if (!validBlockId(id)) throw new IOException("Invalid block registry identifier");
        return new BlockEvent(op,x,y,z,id);
    }
    private static boolean validBlockId(String id) { return id.matches("[a-z0-9_.-]+:[a-z0-9_./-]+"); }
    /** Basis: KCD +X east/+Y north/+Z up -> MC +X east/+Y up/-Z north.
     * This is a calibrated hypothesis until measurements from the installed KCD build exist. */
    public static Vec3 toMinecraft(Vec3 p, Vec3 origin, double scale) {
        validScale(scale); return new Vec3((p.x()-origin.x())*scale,(p.z()-origin.z())*scale,-(p.y()-origin.y())*scale);
    }
    public static Vec3 toKcd(Vec3 p, Vec3 origin, double scale) {
        validScale(scale); return new Vec3(p.x()/scale+origin.x(),-p.z()/scale+origin.y(),p.y()/scale+origin.z());
    }
    /** Local camera basis stays +X right/+Y up/-Z forward. Change only the world basis. */
    public static Quaternion toMinecraftOrientation(Quaternion kcd) {
        double half=Math.sqrt(0.5);
        return multiply(new Quaternion(-half,0,0,half),kcd);
    }
    public static Quaternion toKcdOrientation(Quaternion minecraft) {
        double half=Math.sqrt(0.5);
        return multiply(new Quaternion(half,0,0,half),minecraft);
    }
    private static Quaternion multiply(Quaternion a,Quaternion b) {
        double x=a.w()*b.x()+a.x()*b.w()+a.y()*b.z()-a.z()*b.y();
        double y=a.w()*b.y()-a.x()*b.z()+a.y()*b.w()+a.z()*b.x();
        double z=a.w()*b.z()+a.x()*b.y()-a.y()*b.x()+a.z()*b.w();
        double w=a.w()*b.w()-a.x()*b.x()-a.y()*b.y()-a.z()*b.z();
        double length=Math.sqrt(x*x+y*y+z*z+w*w);
        return new Quaternion(x/length,y/length,z/length,w/length);
    }
    private static void validScale(double scale) {
        if (!Double.isFinite(scale) || scale<=0) throw new IllegalArgumentException("Scale must be finite and positive");
    }
    public static long nowMicros() { return System.nanoTime()/1000; }
}
