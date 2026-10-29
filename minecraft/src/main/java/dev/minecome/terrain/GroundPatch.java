package dev.minecome.terrain;

import com.google.gson.*;
import com.google.gson.stream.JsonReader;
import com.google.gson.stream.JsonToken;
import java.io.*;
import java.math.BigDecimal;
import java.nio.*;
import java.nio.charset.*;
import java.nio.file.*;
import java.security.*;
import java.util.*;

/** Immutable numeric host samples. This is a bounded heightfield approximation, not mesh extraction. */
public final class GroundPatch implements GroundSurface {
    public static final int GRID_SIZE=5,WIDE_GRID_SIZE=9,MAX_BYTES=65_536;
    public static final double ANCHOR_Y=64,THICKNESS=0.5;
    public record Point(int index,double x,double y,double z,double nx,double ny,double nz) {}
    public record Slab(double minX,double minY,double minZ,double maxX,double maxY,double maxZ) {}
    public record Cell(int x,int y,int z,double minY,double maxY) {}
    private final String run,sourceKind,sha256;
    private final double centerX,centerY,centerZ;
    private final int gridSize;
    private final List<Point> points;
    private final List<Slab> slabs;
    private final List<Cell> cells;
    private GroundPatch(String run,String sourceKind,String sha256,double cx,double cy,double cz,int gridSize,List<Point> points) {
        this.run=run;this.sourceKind=sourceKind;this.sha256=sha256;
        this.gridSize=gridSize;int half=(gridSize-1)/2;
        centerX=cx;centerY=cy;centerZ=cz;this.points=List.copyOf(points);
        var slabs=new ArrayList<Slab>();var cells=new ArrayList<Cell>();
        for(int row=0;row<gridSize-1;row++)for(int col=0;col<gridSize-1;col++) {
            double height=(points.get(row*gridSize+col).z()+points.get(row*gridSize+col+1).z()+
                    points.get((row+1)*gridSize+col).z()+points.get((row+1)*gridSize+col+1).z())/4;
            double top=ANCHOR_Y+height-cz;int x=col-half,z=half-1-row;
            slabs.add(new Slab(x,top-THICKNESS,z,x+1,top,z+1));
            for(int y=(int)Math.floor(top-THICKNESS);y<(int)Math.ceil(top);y++)
                cells.add(new Cell(x,y,z,Math.max(0,top-THICKNESS-y),Math.min(1,top-y)));
        }
        this.slabs=List.copyOf(slabs);this.cells=List.copyOf(cells);
    }
    public String run(){return run;}
    public String sourceKind(){return sourceKind;}
    public String sha256(){return sha256;}
    public List<Point> points(){return points;}
    public List<Slab> slabs(){return slabs;}
    public List<Cell> cells(){return cells;}
    public double centerX(){return centerX;}
    public double centerY(){return centerY;}
    public double centerZ(){return centerZ;}
    public int gridSize(){return gridSize;}
    public boolean wide(){return gridSize==WIDE_GRID_SIZE;}
    public double halfExtent(){return (gridSize-1)/2.0;}
    public double heightAt(double x,double z) {
        for(var slab:slabs)if(x>=slab.minX() && x<slab.maxX() && z>=slab.minZ() && z<slab.maxZ())return slab.maxY();
        throw new IllegalArgumentException("Outside sampled coverage");
    }
    public double groundForFeet(double x,double z,double radius) {
        double highest=Double.NEGATIVE_INFINITY;
        for(var slab:slabs)if(x+radius>slab.minX() && x-radius<slab.maxX() && z+radius>slab.minZ() && z-radius<slab.maxZ())
            highest=Math.max(highest,slab.maxY());
        if(!Double.isFinite(highest))throw new IllegalArgumentException("Outside sampled coverage");return highest;
    }
    public boolean containsFeet(double x,double z,double margin) {
        double half=halfExtent();
        return Double.isFinite(x) && Double.isFinite(z) && Double.isFinite(margin) && margin>=0 && margin<half &&
                x>=-half+margin && x<=half-margin && z>=-half+margin && z<=half-margin;
    }
    public static GroundPatch read(Path path) throws IOException {
        return read(path,false);
    }
    public static GroundPatch read(Path path,boolean wide) throws IOException {
        try(var in=Files.newInputStream(path)) {
            byte[] data=in.readNBytes(MAX_BYTES+1);
            if(data.length>MAX_BYTES)throw new IOException("Ground patch exceeds 65536 bytes");
            return parse(data,wide);
        }
    }
    public static GroundPatch parse(byte[] data) throws IOException {
        return parse(data,false);
    }
    public static GroundPatch parse(byte[] data,boolean wide) throws IOException {
        if(data.length==0 || data.length>MAX_BYTES)throw new IOException("Invalid ground patch byte count");
        String json;
        try{json=StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(data)).toString();}
        catch(CharacterCodingException e){throw new IOException("Invalid patch UTF-8",e);}
        try(var reader=new JsonReader(new StringReader(json))) {
            reader.setLenient(false);
            JsonObject root=object(readJson(reader,0,new int[]{0,wide?2048:1024}),"patch");
            if(reader.peek()!=JsonToken.END_DOCUMENT)throw new IllegalArgumentException("Trailing JSON content");
            int grid=wide?WIDE_GRID_SIZE:GRID_SIZE,count=grid*grid,half=(grid-1)/2;
            if(integer(root,"schema")!=1 || integer(root,"grid_size")!=grid || number(root,"spacing")!=1)
                throw new IllegalArgumentException("Expected explicitly selected schema1/grid"+grid+"/spacing1");
            if(wide?!root.has("walking_area")||!string(root,"walking_area").equals("wide"):root.has("walking_area"))
                throw new IllegalArgumentException("Patch walking-area marker differs from explicit profile");
            String run=string(root,"run");
            if(!run.matches("[A-Za-z0-9_-]{1,128}"))throw new IllegalArgumentException("Invalid patch run token");
            JsonObject center=object(root.get("center"),"center");
            double cx=coordinate(center,"x"),cy=coordinate(center,"y"),cz=coordinate(center,"z");
            if(root.has("stable_player") && !bool(root,"stable_player"))throw new IllegalArgumentException("Unstable host sampling");
            if(root.has("point_count") && integer(root,"point_count")!=count || root.has("valid_count") && integer(root,"valid_count")!=count)
                throw new IllegalArgumentException("Partial host patch");
            JsonElement values=root.get("points");
            if(values==null || !values.isJsonArray() || values.getAsJsonArray().size()!=count)throw new IllegalArgumentException("Complete selected grid required");
            Point[] points=new Point[count];
            for(var value:values.getAsJsonArray()) {
                JsonObject p=object(value,"point");int index=integer(p,"index");
                if(index<1 || index>count || points[index-1]!=null)throw new IllegalArgumentException("Invalid/duplicate point index");
                double x=coordinate(p,"x"),y=coordinate(p,"y"),z=coordinate(p,"z");
                int row=(index-1)/grid,col=(index-1)%grid;
                if(Math.abs(x-(cx+col-half))>0.0001 || Math.abs(y-(cy+row-half))>0.0001 || Math.abs(z-cz)>8)
                    throw new IllegalArgumentException("Point outside exact sampled grid/height bounds");
                double nx=number(p,"nx"),ny=number(p,"ny"),nz=number(p,"nz");
                double length=nx*nx+ny*ny+nz*nz;
                if(Math.abs(length-1)>0.05 || nz<0.5)throw new IllegalArgumentException("Non-unit or steep/downward terrain normal");
                if(p.has("valid") && !bool(p,"valid") || p.has("result") && !string(p,"result").equals("hit"))
                    throw new IllegalArgumentException("Invalid terrain sample");
                points[index-1]=new Point(index,x,y,z,nx,ny,nz);
            }
            // Large discontinuities are outside this deliberately small vanilla-walking probe.
            for(int row=0;row<grid;row++)for(int col=0;col<grid;col++) {
                double z=points[row*grid+col].z();
                if(col<grid-1 && Math.abs(z-points[row*grid+col+1].z())>0.5 || row<grid-1 && Math.abs(z-points[(row+1)*grid+col].z())>0.5)
                    throw new IllegalArgumentException("Adjacent height step exceeds bounded probe limit0.5m");
            }
            String kind="unspecified_file";
            if(root.has("provenance"))kind=string(object(root.get("provenance"),"provenance"),"kind");
            if(!kind.matches("[A-Za-z0-9_-]{1,64}"))throw new IllegalArgumentException("Invalid provenance kind");
            String hash=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));
            return new GroundPatch(run,kind,hash,cx,cy,cz,grid,Arrays.asList(points));
        }catch(IllegalArgumentException|IllegalStateException|NoSuchAlgorithmException e){throw new IOException("Invalid ground patch: "+e.getMessage(),e);}
    }
    private static JsonElement readJson(JsonReader reader,int depth,int[] count) throws IOException {
        if(depth>12 || ++count[0]>count[1])throw new IOException("Patch JSON nesting/member bound exceeded");
        return switch(reader.peek()) {
            case BEGIN_OBJECT -> {
                reader.beginObject();JsonObject obj=new JsonObject();
                while(reader.hasNext()) {String name=reader.nextName();if(obj.has(name))throw new IOException("Duplicate JSON field: "+name);
                    obj.add(name,readJson(reader,depth+1,count));}
                reader.endObject();yield obj;
            }
            case BEGIN_ARRAY -> {
                reader.beginArray();JsonArray array=new JsonArray();while(reader.hasNext())array.add(readJson(reader,depth+1,count));
                reader.endArray();yield array;
            }
            case NUMBER -> new JsonPrimitive(new BigDecimal(reader.nextString()));
            case STRING -> new JsonPrimitive(reader.nextString());
            case BOOLEAN -> new JsonPrimitive(reader.nextBoolean());
            case NULL -> {reader.nextNull();yield JsonNull.INSTANCE;}
            default -> throw new IOException("Invalid JSON token");
        };
    }
    private static JsonObject object(JsonElement e,String name) {
        if(e==null || !e.isJsonObject())throw new IllegalArgumentException(name+" must be an object");return e.getAsJsonObject();
    }
    private static double number(JsonObject o,String key) {
        JsonElement e=o.get(key);
        if(e==null || !e.isJsonPrimitive() || !e.getAsJsonPrimitive().isNumber())throw new IllegalArgumentException("Missing numeric "+key);
        double value=e.getAsDouble();if(!Double.isFinite(value))throw new IllegalArgumentException("Non-finite "+key);return value;
    }
    private static double coordinate(JsonObject o,String key) {
        double value=number(o,key);if(Math.abs(value)>10_000_000)throw new IllegalArgumentException("Coordinate bound exceeded");return value;
    }
    private static int integer(JsonObject o,String key) {
        double value=number(o,key);if(value!=Math.rint(value) || value<Integer.MIN_VALUE || value>Integer.MAX_VALUE)
            throw new IllegalArgumentException("Invalid integer "+key);return(int)value;
    }
    private static String string(JsonObject o,String key) {
        JsonElement e=o.get(key);if(e==null || !e.isJsonPrimitive() || !e.getAsJsonPrimitive().isString())throw new IllegalArgumentException("Missing string "+key);return e.getAsString();
    }
    private static boolean bool(JsonObject o,String key) {
        JsonElement e=o.get(key);if(e==null || !e.isJsonPrimitive() || !e.getAsJsonPrimitive().isBoolean())throw new IllegalArgumentException("Missing boolean "+key);return e.getAsBoolean();
    }
}
