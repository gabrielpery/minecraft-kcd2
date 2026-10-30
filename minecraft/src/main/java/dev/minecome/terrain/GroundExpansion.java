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

/** One bounded additive tile admission. Both generations retain the original host anchor. */
public final class GroundExpansion {
    public static final int MAX_BYTES=288*1024;
    private final String sha256;
    private final GroundCorridor initial;
    private final Expanded expanded;

    private GroundExpansion(String hash,GroundCorridor initial,GroundPatch third,List<String> tileHashes) {
        sha256=hash;this.initial=initial;
        if(!third.run().equals(initial.run()) || third.centerX()!=initial.centerX()+8 ||
                third.centerY()!=initial.centerY() || third.centerZ()!=initial.centerZ())
            throw new IllegalArgumentException("Extension requires tile offset (8,0) and the original run/height anchor");
        String source=switch(initial.sourceKind()) {
            case "live_kcd_ground_corridor" -> "live_kcd_ground_patch";
            case "standalone_corridor_fixture" -> "standalone_fixture";
            default -> throw new IllegalArgumentException("Unsupported initial corridor provenance");
        };
        if(!source.equals(third.sourceKind()))throw new IllegalArgumentException("Mixed extension tile provenance");
        var grid=new GroundPatch.Point[9*17];
        for(var point:initial.points()) {
            int row=(point.index()-1)/13,col=(point.index()-1)%13,index=row*17+col;
            grid[index]=renumber(point,index+1);
        }
        for(var point:third.points()) {
            int row=(point.index()-1)/9,col=(point.index()-1)%9+8,index=row*17+col;
            var previous=grid[index];
            if(previous!=null) {
                if(!near(previous.x(),point.x())||!near(previous.y(),point.y())||!near(previous.z(),point.z())||
                        !near(previous.nx(),point.nx())||!near(previous.ny(),point.ny())||!near(previous.nz(),point.nz()))
                    throw new IllegalArgumentException("Extension overlap samples disagree");
            } else grid[index]=renumber(point,index+1);
        }
        for(var point:grid)if(point==null)throw new IllegalArgumentException("Extension sample coverage has a gap");
        for(int row=0;row<9;row++)for(int col=0;col<17;col++) {
            double height=grid[row*17+col].z();
            if(col<16&&Math.abs(height-grid[row*17+col+1].z())>.5 ||
                    row<8&&Math.abs(height-grid[(row+1)*17+col].z())>.5)
                throw new IllegalArgumentException("Extension adjacent height step exceeds 0.5m");
        }
        // Retain the exact existing slabs and cells, including floating-point values.
        // Only columns outside the initial surface are admitted.
        var slabs=new ArrayList<>(initial.slabs());var cells=new ArrayList<>(initial.cells());
        for(int row=0;row<8;row++)for(int col=12;col<16;col++) {
            double height=(grid[row*17+col].z()+grid[row*17+col+1].z()+
                    grid[(row+1)*17+col].z()+grid[(row+1)*17+col+1].z())/4;
            double top=GroundPatch.ANCHOR_Y+height-initial.centerZ();int x=col-4,z=3-row;
            slabs.add(new GroundPatch.Slab(x,top-GroundPatch.THICKNESS,z,x+1,top,z+1));
            for(int y=(int)Math.floor(top-GroundPatch.THICKNESS);y<(int)Math.ceil(top);y++)
                cells.add(new GroundPatch.Cell(x,y,z,Math.max(0,top-GroundPatch.THICKNESS-y),Math.min(1,top-y)));
        }
        expanded=new Expanded(initial,hash,List.copyOf(tileHashes),List.copyOf(Arrays.asList(grid)),List.copyOf(slabs),List.copyOf(cells));
    }
    private static GroundPatch.Point renumber(GroundPatch.Point p,int index) {
        return new GroundPatch.Point(index,p.x(),p.y(),p.z(),p.nx(),p.ny(),p.nz());
    }
    private static boolean near(double a,double b){return Math.abs(a-b)<=.0001;}
    public String sha256(){return sha256;}
    public String run(){return initial.run();}
    public GroundCorridor initial(){return initial;}
    public GroundSurface expanded(){return expanded;}
    public List<String> tileHashes(){return expanded.tileHashes;}
    /** Only this verified immutable additive successor can replace its exact predecessor. */
    static boolean isTransition(GroundSurface expected,GroundSurface next) {
        return expected instanceof GroundCorridor && next instanceof Expanded expansion &&
                expected.run().equals(expansion.initial.run()) && expected.sha256().equals(expansion.initial.sha256()) &&
                expected.centerX()==expansion.centerX() && expected.centerY()==expansion.centerY() && expected.centerZ()==expansion.centerZ() &&
                expected.sourceKind().equals(expansion.initial.sourceKind()) &&
                expected.slabs().equals(expansion.initial.slabs()) && expected.cells().equals(expansion.initial.cells());
    }
    private static final class Expanded implements GroundSurface {
        private final GroundCorridor initial;
        private final String hash;
        private final List<String> tileHashes;
        private final List<GroundPatch.Point> points;
        private final List<GroundPatch.Slab> slabs;
        private final List<GroundPatch.Cell> cells;
        Expanded(GroundCorridor initial,String hash,List<String> tileHashes,List<GroundPatch.Point> points,
                List<GroundPatch.Slab> slabs,List<GroundPatch.Cell> cells) {
            this.initial=initial;this.hash=hash;this.tileHashes=tileHashes;this.points=points;this.slabs=slabs;this.cells=cells;
        }
        public String run(){return initial.run();}
        public String sourceKind(){return initial.sourceKind().equals("live_kcd_ground_corridor")?"live_kcd_ground_extension":"standalone_ground_extension_fixture";}
        public String sha256(){return hash;}
        public double centerX(){return initial.centerX();}
        public double centerY(){return initial.centerY();}
        public double centerZ(){return initial.centerZ();}
        public List<GroundPatch.Point> points(){return points;}
        public List<GroundPatch.Slab> slabs(){return slabs;}
        public List<GroundPatch.Cell> cells(){return cells;}
        public boolean wide(){return true;}
        public boolean corridor(){return true;}
        public double heightAt(double x,double z) {
            for(var slab:slabs)if(x>=slab.minX()&&x<slab.maxX()&&z>=slab.minZ()&&z<slab.maxZ())return slab.maxY();
            throw new IllegalArgumentException("Outside expanded coverage");
        }
        public double groundForFeet(double x,double z,double radius) {
            if(!containsFeet(x,z,radius))throw new IllegalArgumentException("Feet extend outside expanded coverage");
            if(radius==0)return heightAt(x,z);
            double highest=Double.NEGATIVE_INFINITY;
            for(var slab:slabs)if(x+radius>slab.minX()&&x-radius<slab.maxX()&&z+radius>slab.minZ()&&z-radius<slab.maxZ())
                highest=Math.max(highest,slab.maxY());
            if(!Double.isFinite(highest))throw new IllegalArgumentException("Outside expanded coverage");
            return highest;
        }
        public boolean containsFeet(double x,double z,double margin) {
            return Double.isFinite(x)&&Double.isFinite(z)&&Double.isFinite(margin)&&margin>=0&&margin<4&&
                    x>=-4+margin&&x<=12-margin&&z>=-4+margin&&z<=4-margin;
        }
    }
    public static GroundExpansion read(Path path)throws IOException {
        try(var input=Files.newInputStream(path)) {
            byte[] bytes=input.readNBytes(MAX_BYTES+1);
            if(bytes.length>MAX_BYTES)throw new IOException("Extension manifest exceeds 288KiB");
            return parse(bytes);
        }
    }
    public static GroundExpansion parse(byte[] bytes)throws IOException {
        if(bytes.length==0||bytes.length>MAX_BYTES)throw new IOException("Invalid extension byte count");
        String json;
        try{json=StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();}
        catch(CharacterCodingException e){throw new IOException("Invalid extension UTF-8",e);}
        try(var reader=new JsonReader(new StringReader(json))) {
            reader.setLenient(false);var root=object(readJson(reader,0,new int[]{0}));
            if(reader.peek()!=JsonToken.END_DOCUMENT)throw new IllegalArgumentException("Trailing extension JSON");
            keys(root,"schema","kind","run","tiles");var schema=root.get("schema");
            if(!schema.isJsonPrimitive()||!schema.getAsJsonPrimitive().isNumber()||schema.getAsBigDecimal().compareTo(BigDecimal.ONE)!=0||
                    !text(root,"kind").equals("minecome_ground_extension_v1"))throw new IllegalArgumentException("Unsupported extension schema/kind");
            String run=text(root,"run");if(!run.matches("[A-Za-z0-9_-]{1,128}"))throw new IllegalArgumentException("Invalid extension run");
            var entries=root.get("tiles");
            if(!entries.isJsonArray()||entries.getAsJsonArray().size()!=3)throw new IllegalArgumentException("Exactly three extension tiles required");
            var hashes=new ArrayList<String>();GroundPatch third=null;JsonElement provenance=null;
            for(int i=0;i<3;i++) {
                var entry=object(entries.getAsJsonArray().get(i));keys(entry,"sha256","json");
                String expected=text(entry,"sha256"),raw=text(entry,"json");
                if(!expected.matches("[0-9a-f]{64}"))throw new IllegalArgumentException("Invalid extension tile hash");
                ByteBuffer encoded=StandardCharsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT).encode(CharBuffer.wrap(raw));
                byte[] tileBytes=new byte[encoded.remaining()];encoded.get(tileBytes);
                if(tileBytes.length>GroundPatch.MAX_BYTES || !hash(tileBytes).equals(expected))throw new IllegalArgumentException("Extension tile hash/size mismatch");
                var tile=GroundPatch.parse(tileBytes,true);
                if(!tile.run().equals(run))throw new IllegalArgumentException("Extension tile run differs from manifest");
                var currentProvenance=JsonParser.parseString(raw).getAsJsonObject().get("provenance");
                if(currentProvenance==null || !currentProvenance.isJsonObject())throw new IllegalArgumentException("Missing extension tile provenance");
                if(provenance==null)provenance=currentProvenance;
                else if(!provenance.equals(currentProvenance))throw new IllegalArgumentException("Extension capture provenance differs between tiles");
                hashes.add(expected);if(i==2)third=tile;
            }
            var corridor=new JsonObject();corridor.addProperty("schema",1);corridor.addProperty("kind","minecome_ground_corridor_v1");corridor.addProperty("run",run);
            var initialTiles=new JsonArray();initialTiles.add(entries.getAsJsonArray().get(0).deepCopy());initialTiles.add(entries.getAsJsonArray().get(1).deepCopy());corridor.add("tiles",initialTiles);
            var initial=GroundCorridor.parse(corridor.toString().getBytes(StandardCharsets.UTF_8));
            return new GroundExpansion(hash(bytes),initial,third,hashes);
        }catch(IllegalArgumentException|IllegalStateException e){throw new IOException("Invalid ground extension: "+e.getMessage(),e);}
    }
    private static String hash(byte[] bytes) {
        try{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));}
        catch(NoSuchAlgorithmException e){throw new IllegalStateException("SHA-256 unavailable",e);}
    }
    private static JsonObject object(JsonElement value) {
        if(value==null||!value.isJsonObject())throw new IllegalArgumentException("Extension JSON object required");return value.getAsJsonObject();
    }
    private static String text(JsonObject object,String name) {
        var value=object.get(name);
        if(value==null||!value.isJsonPrimitive()||!value.getAsJsonPrimitive().isString())throw new IllegalArgumentException("Missing extension string "+name);
        return value.getAsString();
    }
    private static void keys(JsonObject object,String... expected) {
        if(!object.keySet().equals(Set.of(expected)))throw new IllegalArgumentException("Unknown or missing extension fields");
    }
    private static JsonElement readJson(JsonReader reader,int depth,int[] count)throws IOException {
        if(depth>8||++count[0]>64)throw new IOException("Extension JSON bound exceeded");
        return switch(reader.peek()) {
            case BEGIN_OBJECT -> {
                reader.beginObject();var object=new JsonObject();
                while(reader.hasNext()){String name=reader.nextName();if(object.has(name))throw new IOException("Duplicate extension field "+name);object.add(name,readJson(reader,depth+1,count));}
                reader.endObject();yield object;
            }
            case BEGIN_ARRAY -> {
                reader.beginArray();var array=new JsonArray();while(reader.hasNext())array.add(readJson(reader,depth+1,count));reader.endArray();yield array;
            }
            case STRING -> new JsonPrimitive(reader.nextString());
            case NUMBER -> new JsonPrimitive(new BigDecimal(reader.nextString()));
            case BOOLEAN -> new JsonPrimitive(reader.nextBoolean());
            case NULL -> {reader.nextNull();yield JsonNull.INSTANCE;}
            default -> throw new IOException("Invalid extension JSON token");
        };
    }
}
