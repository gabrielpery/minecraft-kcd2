package dev.minecome.terrain;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Bounded prototype file IPC. Only immutable scalar observations enter this writer. */
final class MovementTraceSink implements AutoCloseable {
    static final int MAX_RECORDS=200,MAX_BYTES=64*1024,END_RESERVE=2048;
    static final long PERIOD_NS=100_000_000L,MAX_SERVER_AGE_NS=250_000_000L;
    enum Profile {
        GROUND("MineCome-Ground-"),HUD_COUPLED("MineCome-HudStream-");
        private final String savePrefix;
        Profile(String savePrefix){this.savePrefix=savePrefix;}
    }
    record Context(String run,String patchSha256,String sourceKind,String save,String world,
                   double centerX,double centerY,double centerZ,Profile profile) {
        Context(String run,String patchSha256,String sourceKind,String save,String world,double centerX,double centerY,double centerZ) {
            this(run,patchSha256,sourceKind,save,world,centerX,centerY,centerZ,Profile.GROUND);
        }
        Context {
            if(!run.matches("[A-Za-z0-9_-]{1,128}") || !patchSha256.matches("[0-9a-f]{64}") ||
                    !sourceKind.matches("[A-Za-z0-9_-]{1,64}") || !world.equals(UUID.fromString(world).toString()) ||
                    profile==null || !save.equals(profile.savePrefix+world) ||
                    (profile==Profile.HUD_COUPLED && !sourceKind.equals("live_kcd_ground_patch")) || !finite(centerX,centerY,centerZ) ||
                    Math.abs(centerX)>10_000_000 || Math.abs(centerY)>10_000_000 || Math.abs(centerZ)>10_000_000)
                throw new IllegalArgumentException("Invalid movement trace context");
        }
    }
    record Motion(double x,double y,double z,double vx,double vy,double vz,boolean onGround,boolean proxySupport) {
        Motion {
            if(!finite(x,y,z,vx,vy,vz) || Math.abs(x)>2 || Math.abs(z)>2 || y<52 || y>76 ||
                    Math.abs(vx)>4 || Math.abs(vy)>4 || Math.abs(vz)>4)
                throw new IllegalArgumentException("Invalid/beyond-probe trace motion");
        }
    }
    private final Path path;
    private final Context context;
    private final OutputStream output;
    private long sequence,lastServerSequence,lastSampleNs;
    private int bytes;
    private boolean sampled,closed;
    private MovementTraceSink(Path path,Context context,OutputStream output){this.path=path;this.context=context;this.output=output;}
    static MovementTraceSink open(Path requested,Path evidenceRoot,Context context,long nowNs,long utcMs) throws IOException {
        if(!requested.isAbsolute())throw new IOException("Movement trace path must be absolute");
        Path root=evidenceRoot.toRealPath();
        Path normalized=requested.normalize();
        if(normalized.getFileName()==null || !normalized.getFileName().toString().matches("[A-Za-z0-9_.-]{1,80}"))
            throw new IOException("Invalid movement trace filename");
        Path parent=normalized.getParent().toRealPath();
        if(!parent.startsWith(root))throw new IOException("Movement trace must remain within resolved workspace runtime/evidence");
        Path target=parent.resolve(normalized.getFileName());
        if(Files.exists(target,LinkOption.NOFOLLOW_LINKS))throw new IOException("Refusing existing trace file: "+target);
        var output=new BufferedOutputStream(Files.newOutputStream(target,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE),4096);
        var sink=new MovementTraceSink(target,context,output);
        try {
            String begin=sink.prefix("begin",utcMs)+",\"phase\":\"SETTLING\",\"started_monotonic_ns\":"+nowNs+
                    ",\"center\":{\"x\":"+context.centerX()+",\"y\":"+context.centerY()+",\"z\":"+context.centerZ()+"}"+
                    ",\"anchor_mc\":{\"x\":0,\"y\":64,\"z\":0},\"approximate_heightfield\":true,\"full_collision_export_verified\":false}";
            sink.write(begin,false);return sink;
        }catch(IOException|RuntimeException e){try{output.close();}catch(IOException close){e.addSuppressed(close);}throw e;}
    }
    Path path(){return path;}
    long records(){return sequence;}
    int byteCount(){return bytes;}
    boolean closed(){return closed;}
    /** Returns false for throttled, stale or non-advancing observations; these cannot drive a follower. */
    boolean sample(long nowNs,long utcMs,String phase,Motion client,Motion server,long serverSequence,long receivedAtNs,boolean force) throws IOException {
        if(closed)return false;
        validatePhase(phase);
        long age=nowNs-receivedAtNs;
        if(age<0 || age>MAX_SERVER_AGE_NS || serverSequence<=lastServerSequence || serverSequence<1)return false;
        if(sampled && (nowNs<lastSampleNs || (!force && nowNs-lastSampleNs<PERIOD_NS)))return false;
        String record=prefix("sample",utcMs)+",\"phase\":"+quote(phase)+",\"monotonic_ns\":"+nowNs+
                ",\"server_seq\":"+serverSequence+",\"server_age_ns\":"+age+
                ",\"client\":"+motion(client)+",\"server\":"+motion(server)+"}";
        write(record,false);lastServerSequence=serverSequence;lastSampleNs=nowNs;sampled=true;return true;
    }
    void finish(long utcMs,String result,String phase,String reason) throws IOException {
        if(closed)return;
        if(!Set.of("passed","failed","stopped").contains(result))throw new IllegalArgumentException("Invalid trace termination result");
        validatePhase(phase);
        String shortReason=Objects.requireNonNull(reason);
        if(shortReason.codePointCount(0,shortReason.length())>160)shortReason=shortReason.substring(0,shortReason.offsetByCodePoints(0,160));
        try {
            write(prefix("end",utcMs)+",\"phase\":"+quote(phase)+",\"result\":"+quote(result)+
                    ",\"reason\":"+quote(shortReason)+",\"last_server_seq\":"+lastServerSequence+"}",true);
        }finally {closed=true;output.close();}
    }
    private String prefix(String kind,long utcMs) {
        if(utcMs<0)throw new IllegalArgumentException("Invalid UTC timestamp");
        return "{\"schema\":1,\"kind\":"+quote(kind)+",\"run\":"+quote(context.run())+
                ",\"patch_sha256\":"+quote(context.patchSha256())+",\"source_kind\":"+quote(context.sourceKind())+
                ",\"save\":"+quote(context.save())+",\"world\":"+quote(context.world())+
                ",\"seq\":"+(sequence+1)+",\"utc_ms\":"+utcMs;
    }
    private void write(String record,boolean end) throws IOException {
        byte[] line=(record+"\n").getBytes(StandardCharsets.UTF_8);
        int limit=end?MAX_BYTES:MAX_BYTES-END_RESERVE;
        if(sequence>=(end?MAX_RECORDS:MAX_RECORDS-1) || bytes+line.length>limit)
            throw new IOException("Movement trace bounded record/byte budget exhausted");
        output.write(line);output.flush();bytes+=line.length;sequence++;
    }
    private static String motion(Motion m) {
        return "{\"x\":"+m.x()+",\"y\":"+m.y()+",\"z\":"+m.z()+",\"vx\":"+m.vx()+",\"vy\":"+m.vy()+
                ",\"vz\":"+m.vz()+",\"on_ground\":"+m.onGround()+",\"proxy_support\":"+m.proxySupport()+"}";
    }
    private static void validatePhase(String phase) {
        if(!Set.of("SETTLING","WALKING","RESTING","JUMPING","LANDING","PASSED","FAILED","STOPPED").contains(phase))
            throw new IllegalArgumentException("Invalid movement trace phase");
    }
    private static boolean finite(double... values){for(double value:values)if(!Double.isFinite(value))return false;return true;}
    private static String quote(String value) {
        StringBuilder escaped=new StringBuilder("\"");
        for(int i=0;i<value.length();i++) {
            char c=value.charAt(i);
            switch(c) {
                case '"' -> escaped.append("\\\"");case '\\' -> escaped.append("\\\\");
                case '\n' -> escaped.append("\\n");case '\r' -> escaped.append("\\r");case '\t' -> escaped.append("\\t");
                default -> {if(c<32)escaped.append(String.format(Locale.ROOT,"\\u%04x",(int)c));else escaped.append(c);}
            }
        }
        return escaped.append('"').toString();
    }
    @Override public void close() throws IOException {finish(System.currentTimeMillis(),"stopped","STOPPED","Writer closed before explicit lab result");}
}
