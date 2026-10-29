package dev.minecome.terrain;

import com.google.gson.*;
import com.google.gson.stream.JsonReader;
import com.google.gson.stream.JsonToken;
import java.io.*;
import java.math.BigDecimal;
import java.nio.ByteBuffer;
import java.nio.CharBuffer;
import java.nio.charset.*;
import java.nio.file.*;
import java.security.*;
import java.util.*;

/** Two immutable overlapping captures; not a rolling terrain stream or live movement authority. */
public final class GroundCorridor implements GroundSurface {
    public static final int MAX_BYTES=192*1024;
    private static final int ROWS=9,COLUMNS=13;
    private static final double OVERLAP_EPSILON=.0001;
    private final String run,sourceKind,sha256;
    private final double centerX,centerY,centerZ;
    private final List<String> tileHashes;
    private final List<GroundPatch.Point> points;
    private final List<GroundPatch.Slab> slabs;
    private final List<GroundPatch.Cell> cells;

    private GroundCorridor(String run,String hash,GroundPatch first,GroundPatch second){
        if(!first.run().equals(run)||!second.run().equals(run))throw new IllegalArgumentException("Corridor tile run differs from manifest");
        if(second.centerX()!=first.centerX()+4 || second.centerY()!=first.centerY() || second.centerZ()!=first.centerZ())
            throw new IllegalArgumentException("Corridor requires exact tile offsets(0,0),(4,0) and one height anchor");
        if(!first.sourceKind().equals(second.sourceKind()))throw new IllegalArgumentException("Mixed corridor tile provenance");
        sourceKind=switch(first.sourceKind()){
            case "live_kcd_ground_patch" -> "live_kcd_ground_corridor";
            case "standalone_fixture" -> "standalone_corridor_fixture";
            default -> throw new IllegalArgumentException("Unsupported corridor tile provenance");
        };
        this.run=run;sha256=hash;centerX=first.centerX();centerY=first.centerY();centerZ=first.centerZ();
        tileHashes=List.of(first.sha256(),second.sha256());
        GroundPatch.Point[] grid=new GroundPatch.Point[ROWS*COLUMNS];
        GroundPatch[] tiles={first,second};
        for(int tile=0;tile<tiles.length;tile++)for(var point:tiles[tile].points()){
            int row=(point.index()-1)/9,col=(point.index()-1)%9+tile*4,index=row*COLUMNS+col;
            var previous=grid[index];
            if(previous!=null){
                if(!near(previous.x(),point.x())||!near(previous.y(),point.y())||!near(previous.z(),point.z())||
                        !near(previous.nx(),point.nx())||!near(previous.ny(),point.ny())||!near(previous.nz(),point.nz()))
                    throw new IllegalArgumentException("Corridor overlap samples disagree");
            }else grid[index]=new GroundPatch.Point(index+1,point.x(),point.y(),point.z(),point.nx(),point.ny(),point.nz());
        }
        for(var point:grid)if(point==null)throw new IllegalArgumentException("Corridor sample coverage has a gap");
        for(int row=0;row<ROWS;row++)for(int col=0;col<COLUMNS;col++){
            double height=grid[row*COLUMNS+col].z();
            if(col<COLUMNS-1 && Math.abs(height-grid[row*COLUMNS+col+1].z())>.5 ||
                    row<ROWS-1 && Math.abs(height-grid[(row+1)*COLUMNS+col].z())>.5)
                throw new IllegalArgumentException("Corridor adjacent height step exceeds0.5m");
        }
        points=List.copyOf(Arrays.asList(grid));
        var geometry=new ArrayList<GroundPatch.Slab>();var occupied=new ArrayList<GroundPatch.Cell>();
        for(int row=0;row<ROWS-1;row++)for(int col=0;col<COLUMNS-1;col++){
            double height=(grid[row*COLUMNS+col].z()+grid[row*COLUMNS+col+1].z()+
                    grid[(row+1)*COLUMNS+col].z()+grid[(row+1)*COLUMNS+col+1].z())/4;
            double top=GroundPatch.ANCHOR_Y+height-centerZ;int x=col-4,z=3-row;
            geometry.add(new GroundPatch.Slab(x,top-GroundPatch.THICKNESS,z,x+1,top,z+1));
            for(int y=(int)Math.floor(top-GroundPatch.THICKNESS);y<(int)Math.ceil(top);y++)
                occupied.add(new GroundPatch.Cell(x,y,z,Math.max(0,top-GroundPatch.THICKNESS-y),Math.min(1,top-y)));
        }
        slabs=List.copyOf(geometry);cells=List.copyOf(occupied);
    }
    private static boolean near(double a,double b){return Math.abs(a-b)<=OVERLAP_EPSILON;}
    public String run(){return run;}
    public String sourceKind(){return sourceKind;}
    public String sha256(){return sha256;}
    public double centerX(){return centerX;}
    public double centerY(){return centerY;}
    public double centerZ(){return centerZ;}
    public List<String> tileHashes(){return tileHashes;}
    public List<GroundPatch.Point> points(){return points;}
    public List<GroundPatch.Slab> slabs(){return slabs;}
    public List<GroundPatch.Cell> cells(){return cells;}
    public double minX(){return -4;}
    public double maxX(){return 8;}
    public double minZ(){return -4;}
    public double maxZ(){return 4;}
    /** Constituent captures are wide; this does not authorize the existing live-wide profile. */
    public boolean wide(){return true;}
    public boolean corridor(){return true;}
    public double heightAt(double x,double z){
        for(var slab:slabs)if(x>=slab.minX()&&x<slab.maxX()&&z>=slab.minZ()&&z<slab.maxZ())return slab.maxY();
        throw new IllegalArgumentException("Outside corridor coverage");
    }
    public double groundForFeet(double x,double z,double radius){
        if(!containsFeet(x,z,radius))throw new IllegalArgumentException("Feet extend outside corridor coverage");
        if(radius==0)return heightAt(x,z);
        double highest=Double.NEGATIVE_INFINITY;
        for(var slab:slabs)if(x+radius>slab.minX()&&x-radius<slab.maxX()&&z+radius>slab.minZ()&&z-radius<slab.maxZ())
            highest=Math.max(highest,slab.maxY());
        if(!Double.isFinite(highest))throw new IllegalArgumentException("Outside corridor coverage");return highest;
    }
    public boolean containsFeet(double x,double z,double margin){
        return Double.isFinite(x)&&Double.isFinite(z)&&Double.isFinite(margin)&&margin>=0&&margin<4&&
                x>=minX()+margin&&x<=maxX()-margin&&z>=minZ()+margin&&z<=maxZ()-margin;
    }
    public static GroundCorridor read(Path path)throws IOException{
        try(var input=Files.newInputStream(path)){
            byte[] bytes=input.readNBytes(MAX_BYTES+1);
            if(bytes.length>MAX_BYTES)throw new IOException("Corridor manifest exceeds192KiB");
            return parse(bytes);
        }
    }
    public static GroundCorridor parse(byte[] bytes)throws IOException{
        if(bytes.length==0||bytes.length>MAX_BYTES)throw new IOException("Invalid corridor byte count");
        String json;
        try{json=StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();}
        catch(CharacterCodingException e){throw new IOException("Invalid corridor UTF-8",e);}
        try(var reader=new JsonReader(new StringReader(json))){
            reader.setLenient(false);var root=object(readJson(reader,0,new int[]{0}));
            if(reader.peek()!=JsonToken.END_DOCUMENT)throw new IllegalArgumentException("Trailing corridor JSON");
            keys(root,"schema","kind","run","tiles");
            var schema=root.get("schema");
            if(!schema.isJsonPrimitive()||!schema.getAsJsonPrimitive().isNumber()||schema.getAsBigDecimal().compareTo(BigDecimal.ONE)!=0||
                    !text(root,"kind").equals("minecome_ground_corridor_v1"))throw new IllegalArgumentException("Unsupported corridor schema/kind");
            String run=text(root,"run");
            if(!run.matches("[A-Za-z0-9_-]{1,128}"))throw new IllegalArgumentException("Invalid corridor run");
            var entries=root.get("tiles");
            if(!entries.isJsonArray()||entries.getAsJsonArray().size()!=2)throw new IllegalArgumentException("Exactly two corridor tiles required");
            GroundPatch[] tiles=new GroundPatch[2];
            for(int i=0;i<2;i++){
                var entry=object(entries.getAsJsonArray().get(i));keys(entry,"sha256","json");
                String expected=text(entry,"sha256"),raw=text(entry,"json");
                if(!expected.matches("[0-9a-f]{64}"))throw new IllegalArgumentException("Invalid corridor tile hash");
                ByteBuffer encoded=StandardCharsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT).encode(CharBuffer.wrap(raw));
                byte[] tileBytes=new byte[encoded.remaining()];encoded.get(tileBytes);
                if(!hash(tileBytes).equals(expected))throw new IllegalArgumentException("Corridor tile hash mismatch");
                tiles[i]=GroundPatch.parse(tileBytes,true);
            }
            return new GroundCorridor(run,hash(bytes),tiles[0],tiles[1]);
        }catch(IllegalArgumentException|IllegalStateException e){throw new IOException("Invalid ground corridor: "+e.getMessage(),e);}
    }
    private static String hash(byte[] bytes){
        try{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));}
        catch(NoSuchAlgorithmException e){throw new IllegalStateException("SHA-256 unavailable",e);}
    }
    private static JsonObject object(JsonElement value){
        if(value==null||!value.isJsonObject())throw new IllegalArgumentException("Corridor JSON object required");return value.getAsJsonObject();
    }
    private static String text(JsonObject object,String name){
        var value=object.get(name);
        if(value==null||!value.isJsonPrimitive()||!value.getAsJsonPrimitive().isString())throw new IllegalArgumentException("Missing corridor string "+name);
        return value.getAsString();
    }
    private static void keys(JsonObject object,String... expected){
        if(!object.keySet().equals(Set.of(expected)))throw new IllegalArgumentException("Unknown or missing corridor fields");
    }
    private static JsonElement readJson(JsonReader reader,int depth,int[] count)throws IOException{
        if(depth>8||++count[0]>64)throw new IOException("Corridor JSON bound exceeded");
        return switch(reader.peek()){
            case BEGIN_OBJECT -> {
                reader.beginObject();var object=new JsonObject();
                while(reader.hasNext()){String name=reader.nextName();if(object.has(name))throw new IOException("Duplicate corridor field "+name);object.add(name,readJson(reader,depth+1,count));}
                reader.endObject();yield object;
            }
            case BEGIN_ARRAY -> {
                reader.beginArray();var array=new JsonArray();while(reader.hasNext())array.add(readJson(reader,depth+1,count));reader.endArray();yield array;
            }
            case STRING -> new JsonPrimitive(reader.nextString());
            case NUMBER -> new JsonPrimitive(new BigDecimal(reader.nextString()));
            case BOOLEAN -> new JsonPrimitive(reader.nextBoolean());
            case NULL -> {reader.nextNull();yield JsonNull.INSTANCE;}
            default -> throw new IOException("Invalid corridor JSON token");
        };
    }
}
