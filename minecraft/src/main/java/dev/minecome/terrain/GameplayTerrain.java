package dev.minecome.terrain;

import java.nio.charset.StandardCharsets;
import java.security.*;
import java.util.*;

/** Immutable additive tile coverage. Protocol identity and all coordinates retain the first capture's anchor. */
public final class GameplayTerrain implements GroundSurface {
    public static final int TILE_SIZE=8,MAX_TILES=64,MAX_TILE_OFFSET=8;
    public record Tile(int tx,int tz,GroundPatch patch) {}
    private record Grid(int x,int z) {}
    private final GroundPatch base;
    private final GameplayTerrain previous;
    private final List<Tile> tiles;
    private final Map<Grid,Tile> byTile;
    private final Map<Grid,GroundPatch.Point> samples;
    private final Map<Grid,GroundPatch.Slab> columns;
    private final List<GroundPatch.Point> points;
    private final List<GroundPatch.Slab> slabs;
    private final List<GroundPatch.Cell> cells;
    private final String digest;

    private GameplayTerrain(GroundPatch base,GameplayTerrain previous,List<Tile> tiles,
                            Map<Grid,GroundPatch.Point> samples,Map<Grid,GroundPatch.Slab> columns,
                            List<GroundPatch.Slab> slabs,List<GroundPatch.Cell> cells){
        this.base=base;this.previous=previous;this.tiles=List.copyOf(tiles);this.samples=Map.copyOf(samples);
        this.columns=Map.copyOf(columns);this.slabs=List.copyOf(slabs);this.cells=List.copyOf(cells);
        var index=new HashMap<Grid,Tile>();for(var t:tiles)index.put(new Grid(t.tx(),t.tz()),t);byTile=Map.copyOf(index);
        var ordered=new ArrayList<>(samples.entrySet());ordered.sort(Comparator.comparingInt((Map.Entry<Grid,GroundPatch.Point> e)->e.getKey().x()).thenComparingInt(e->e.getKey().z()));
        var allPoints=new ArrayList<GroundPatch.Point>();for(var e:ordered){var p=e.getValue();allPoints.add(new GroundPatch.Point(allPoints.size()+1,p.x(),p.y(),p.z(),p.nx(),p.ny(),p.nz()));}points=List.copyOf(allPoints);
        var proof=new StringBuilder("minecome_gameplay_coverage_v1\n").append(base.sha256()).append('\n');
        for(var t:tiles)proof.append(t.tx()).append(',').append(t.tz()).append(':').append(t.patch().sha256()).append('\n');
        digest=hash(proof.toString().getBytes(StandardCharsets.UTF_8));
    }
    public static GameplayTerrain initial(GroundPatch base){
        Objects.requireNonNull(base);if(!base.wide())throw new IllegalArgumentException("Gameplay growth requires the wide base capture");
        if(!Set.of("live_kcd_ground_patch","standalone_fixture","standalone_ground_fixture").contains(base.sourceKind()))throw new IllegalArgumentException("Unsupported gameplay terrain provenance");
        var samples=new HashMap<Grid,GroundPatch.Point>();appendSamples(samples,base,0,0);
        var columns=new HashMap<Grid,GroundPatch.Slab>();for(var s:base.slabs())columns.put(new Grid((int)s.minX(),(int)s.minZ()),s);
        return new GameplayTerrain(base,null,List.of(new Tile(0,0,base)),samples,columns,base.slabs(),base.cells());
    }
    public GameplayTerrain admit(int tx,int tz,GroundPatch tile){
        Objects.requireNonNull(tile);
        if(tx< -MAX_TILE_OFFSET||tx>MAX_TILE_OFFSET||tz< -MAX_TILE_OFFSET||tz>MAX_TILE_OFFSET||tiles.size()>=MAX_TILES||hasTile(tx,tz))throw new IllegalArgumentException("Tile capacity, offset or duplicate");
        if(!hasTile(tx-1,tz)&&!hasTile(tx+1,tz)&&!hasTile(tx,tz-1)&&!hasTile(tx,tz+1))throw new IllegalArgumentException("Tile must share an admitted edge");
        if(!tile.wide()||!tile.sourceKind().equals(base.sourceKind())||tile.centerX()!=centerX()+TILE_SIZE*tx||
                tile.centerY()!=centerY()-TILE_SIZE*tz||tile.centerZ()!=centerZ())throw new IllegalArgumentException("Tile moved anchor or changed provenance");
        var nextSamples=new HashMap<>(samples);appendSamples(nextSamples,tile,tx,tz);
        var nextColumns=new HashMap<>(columns);var nextSlabs=new ArrayList<>(slabs);var nextCells=new ArrayList<>(cells);
        for(var s:tile.slabs()){
            var moved=new GroundPatch.Slab(s.minX()+TILE_SIZE*tx,s.minY(),s.minZ()+TILE_SIZE*tz,s.maxX()+TILE_SIZE*tx,s.maxY(),s.maxZ()+TILE_SIZE*tz);
            if(nextColumns.putIfAbsent(new Grid((int)moved.minX(),(int)moved.minZ()),moved)!=null)throw new IllegalArgumentException("Tile changes existing collision");nextSlabs.add(moved);
        }
        for(var c:tile.cells())nextCells.add(new GroundPatch.Cell(c.x()+TILE_SIZE*tx,c.y(),c.z()+TILE_SIZE*tz,c.minY(),c.maxY()));
        var nextTiles=new ArrayList<>(tiles);nextTiles.add(new Tile(tx,tz,tile));
        return new GameplayTerrain(base,this,nextTiles,nextSamples,nextColumns,nextSlabs,nextCells);
    }
    private static void appendSamples(Map<Grid,GroundPatch.Point> target,GroundPatch tile,int tx,int tz){
        for(var p:tile.points()){
            int row=(p.index()-1)/9,col=(p.index()-1)%9;var key=new Grid(tx*TILE_SIZE+col-4,tz*TILE_SIZE+4-row);
            var old=target.putIfAbsent(key,p);
            if(old!=null&&(!near(old.x(),p.x())||!near(old.y(),p.y())||!near(old.z(),p.z())||!near(old.nx(),p.nx())||!near(old.ny(),p.ny())||!near(old.nz(),p.nz())))
                throw new IllegalArgumentException("Captured tile edge disagrees with admitted terrain");
        }
    }
    private static boolean near(double a,double b){return Math.abs(a-b)<=.0001;}
    private static String hash(byte[] bytes){try{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));}catch(NoSuchAlgorithmException e){throw new IllegalStateException(e);}}
    public GroundPatch base(){return base;}
    public int generation(){return tiles.size()-1;}
    public int tileCount(){return tiles.size();}
    public String digest(){return digest;}
    public List<Tile> tiles(){return tiles;}
    public boolean hasTile(int tx,int tz){return byTile.containsKey(new Grid(tx,tz));}
    public boolean isSuccessorOf(GameplayTerrain expected){return previous==expected&&generation()==expected.generation()+1;}
    public String run(){return base.run();}
    public String sourceKind(){return base.sourceKind();}
    public String sha256(){return base.sha256();}
    public double centerX(){return base.centerX();}
    public double centerY(){return base.centerY();}
    public double centerZ(){return base.centerZ();}
    public List<GroundPatch.Point> points(){return points;}
    public List<GroundPatch.Slab> slabs(){return slabs;}
    public List<GroundPatch.Cell> cells(){return cells;}
    public boolean wide(){return true;}
    public double heightAt(double x,double z){
        if(!Double.isFinite(x)||!Double.isFinite(z))throw new IllegalArgumentException("Invalid height position");
        var slab=columns.get(new Grid((int)Math.floor(x),(int)Math.floor(z)));if(slab==null)throw new IllegalArgumentException("Outside admitted terrain");return slab.maxY();
    }
    public boolean containsFeet(double x,double z,double margin){
        if(!Double.isFinite(x)||!Double.isFinite(z)||!Double.isFinite(margin)||margin<0||margin>=4||Math.abs(x)>68||Math.abs(z)>68)return false;
        return containsRectangle(x-margin,z-margin,x+margin,z+margin);
    }
    /** Entire braking envelope must be covered; admitted opposite corners do not prove a hole-free interior. */
    public boolean containsRectangle(double minX,double minZ,double maxX,double maxZ){
        if(!Double.isFinite(minX)||!Double.isFinite(minZ)||!Double.isFinite(maxX)||!Double.isFinite(maxZ)||minX>maxX||minZ>maxZ||
                minX< -68||minZ< -68||maxX>68||maxZ>68)return false;
        int firstX=(int)Math.floor(minX),lastX=minX==maxX?firstX:(int)Math.ceil(maxX)-1;
        int firstZ=(int)Math.floor(minZ),lastZ=minZ==maxZ?firstZ:(int)Math.ceil(maxZ)-1;
        for(int x=firstX;x<=lastX;x++)for(int z=firstZ;z<=lastZ;z++)if(!columns.containsKey(new Grid(x,z)))return false;return true;
    }
    public double groundForFeet(double x,double z,double radius){
        if(!containsFeet(x,z,radius))throw new IllegalArgumentException("Feet extend outside admitted terrain");if(radius==0)return heightAt(x,z);
        double high=Double.NEGATIVE_INFINITY;
        for(int ix=(int)Math.floor(x-radius);ix<(int)Math.ceil(x+radius);ix++)for(int iz=(int)Math.floor(z-radius);iz<(int)Math.ceil(z+radius);iz++)high=Math.max(high,columns.get(new Grid(ix,iz)).maxY());
        if(!Double.isFinite(high))throw new IllegalArgumentException("No terrain beneath feet");return high;
    }
}
