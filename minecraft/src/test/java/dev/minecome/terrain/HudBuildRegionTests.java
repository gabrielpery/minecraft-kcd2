package dev.minecome.terrain;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import dev.minecome.protocol.AimGeometry.Cell;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashSet;
import java.util.Set;

/** Pure policy/heightfield tests: no Minecraft world, bootstrap or block setters. */
public final class HudBuildRegionTests {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static void reject(Runnable action,String message){
        try{action.run();throw new AssertionError(message);}catch(IllegalArgumentException expected){checks++;}
    }
    private static GroundPatch patch(double height,boolean slope)throws Exception{
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("run","owned-build-fixture");p.addProperty("grid_size",5);p.addProperty("spacing",1);
        var center=new JsonObject();center.addProperty("x",0);center.addProperty("y",0);center.addProperty("z",0);p.add("center",center);
        var provenance=new JsonObject();provenance.addProperty("kind","standalone_ground_fixture");p.add("provenance",provenance);
        var points=new JsonArray();
        for(int row=0;row<5;row++)for(int col=0;col<5;col++){
            var point=new JsonObject();point.addProperty("index",row*5+col+1);point.addProperty("x",col-2);point.addProperty("y",row-2);
            point.addProperty("z",height+(slope?.1*(col-2)+.2*(row-2):0));point.addProperty("nx",0);point.addProperty("ny",0);point.addProperty("nz",1);points.add(point);
        }
        p.add("points",points);return GroundPatch.parse(p.toString().getBytes(StandardCharsets.UTF_8));
    }
    public static void main(String[] args)throws Exception{
        var patch=patch(0,false);var support=new Cell(2,63,0);var region=new HudBuildRegion(patch,support);
        check(region.patchRun().equals(patch.run()) && region.patchSha256().equals(patch.sha256()),"Region pins its exact imported patch identity");
        check(region.support().equals(support) && region.seed().equals(new Cell(2,64,0)),"Explicit perimeter support supplies only its upper seed");
        check(region.minimum().equals(new Cell(0,62,-2)) && region.maximumInclusive().equals(new Cell(4,66,2)),"Build area is exactly seed plus/minus two cells");
        check(region.contains(region.minimum()) && region.contains(region.maximumInclusive()),"All finite boundary cells are included");
        for(Cell outside:Set.of(new Cell(-1,64,0),new Cell(5,64,0),new Cell(2,61,0),new Cell(2,67,0),new Cell(2,64,-3),new Cell(2,64,3),new Cell(Integer.MAX_VALUE,64,0),new Cell(Integer.MIN_VALUE,64,0)))
            check("outside_build_region".equals(region.targetRejection(outside)),"No side of the finite arena or overflowing coordinate is mutable");
        check("target_missing".equals(region.targetRejection(null)),"Missing cell is never admitted");
        for(var cell:patch.cells()){
            Cell imported=new Cell(cell.x(),cell.y(),cell.z());check(region.isImported(imported),"Every imported slab cell remains explicitly protected");
            check(region.targetRejection(imported)!=null && region.placementRejection(imported,Set.of())!=null && region.breakRejection(imported,Set.of(imported))!=null && region.cleanupRejection(imported,Set.of(imported))!=null,
                    "Placement, breaking and cleanup cannot acquire imported collision cells");
        }
        check(region.importedCells().size()==16,"Flat patch protects all sixteen full cells");
        try{region.importedCells().clear();throw new AssertionError("Mutable imported cell snapshot");}catch(UnsupportedOperationException expected){checks++;}
        check(region.placementRejection(region.seed(),Set.of())==null,"Fresh seed is a possible vanilla placement target");
        check("bootstrap_support_immutable".equals(region.targetRejection(support)) && region.breakRejection(support,Set.of(support))!=null && region.cleanupRejection(support,Set.of(support))!=null,
                "Fixture bootstrap support never masquerades as a confirmed vanilla stone or cleanup target");
        var owned=new LinkedHashSet<Cell>();owned.add(region.seed());
        check(region.breakRejection(region.seed(),owned)==null && region.cleanupRejection(region.seed(),owned)==null,"Only a supplied confirmed stone can break or clean up");
        check("already_owned".equals(region.placementRejection(region.seed(),owned)),"Owned stone cannot be placed twice");
        Cell unused=new Cell(3,64,0);check("unowned_target".equals(region.breakRejection(unused,owned)) && "unowned_target".equals(region.cleanupRejection(unused,owned)),"Air/unconfirmed cells receive no mutation or cleanup authority");
        owned.clear();check("unowned_target".equals(region.breakRejection(region.seed(),owned)),"Policy retains no hidden ownership ledger after caller removes a confirmation");
        for(int y=64;y<=66 && owned.size()<16;y++)for(int x=2;x<=4 && owned.size()<16;x++)for(int z=-2;z<=2 && owned.size()<16;z++)owned.add(new Cell(x,y,z));
        check(owned.size()==16 && region.ownedRejection(owned)==null,"Exactly sixteen confirmed mutable cells are allowed");
        Cell seventeenth=new Cell(4,66,2);check(!owned.contains(seventeenth) && "owned_limit".equals(region.placementRejection(seventeenth,owned)),"A seventeenth owned stone is refused before placement");
        owned.add(seventeenth);check("owned_limit".equals(region.ownedRejection(owned)) && region.cleanupRejection(region.seed(),owned)!=null,"Oversized confirmation sets cannot grant cleanup authority");
        check(region.ownedRejection(null)!=null,"Missing confirmation set cannot grant ownership");
        var badOwned=new LinkedHashSet<Cell>();badOwned.add(null);check(region.ownedRejection(badOwned)!=null,"Null cells in owned state fail closed");
        check(region.ownedRejection(Set.of(new Cell(5,64,0)))!=null,"Foreign owned cells cannot expand the arena");
        reject(()->new HudBuildRegion(patch,new Cell(4,63,0)),"Distant support accepted");
        reject(()->new HudBuildRegion(patch,new Cell(-4,63,0)),"Negative distant support accepted");
        reject(()->new HudBuildRegion(patch,new Cell(2,Integer.MAX_VALUE,0)),"Unbounded support height accepted");
        reject(()->new HudBuildRegion(patch,new Cell(2,Integer.MIN_VALUE,0)),"Underflowing support accepted");
        reject(()->new HudBuildRegion(patch,new Cell(1,63,0)),"Imported support accepted");
        reject(()->new HudBuildRegion(patch,new Cell(1,62,0)),"Imported seed above support accepted");
        reject(()->new HudBuildRegion(null,support),"Null patch accepted");reject(()->new HudBuildRegion(patch,null),"Null support accepted");
        var fractional=patch(.25,false);var partial=new HudBuildRegion(fractional,support);
        check(partial.isImported(new Cell(1,63,0)) && partial.isImported(new Cell(1,64,0)),"A split slab protects both intersected full block cells");
        check("imported_collision_cell".equals(partial.targetRejection(new Cell(1,64,0))),"Air above a partial slab within the same block cell is still protected");
        check(partial.targetRejection(new Cell(1,65,0))==null,"A wholly separate cell above the slab remains eligible");
        check(partial.targetRejection(new Cell(2,64,0))==null,"Boundary contact beside imported geometry is not false overlap");
        var sloped=patch(0,true);var slopeRegion=new HudBuildRegion(sloped,support);
        for(var cell:sloped.cells())check(slopeRegion.isImported(new Cell(cell.x(),cell.y(),cell.z())),"Sloping and split imported cells receive the same protection");
        check(!slopeRegion.patchSha256().equals(region.patchSha256()),"Different sampled geometry cannot silently share patch identity");
        var corridor=GroundCorridorTests.flatCorridor();var corridorSupport=HudBuildRegion.corridorSupport(corridor,63);
        var corridorRegion=new HudBuildRegion(corridor,corridorSupport);
        check(corridorSupport.equals(new Cell(-1,63,-5))&&corridorRegion.seed().equals(new Cell(-1,64,-5)),
                "Corridor fixed side support is reachable without occupying the expanded walking lane");
        check(corridorRegion.corridor()&&corridorRegion.patchSha256().equals(corridor.sha256()),"Corridor build policy pins the composite identity");
        check(corridorRegion.importedCells().size()==96,"Composite policy protects both tiles, not just the first footprint");
        for(var imported:corridor.cells()){
            var cell=new Cell(imported.x(),imported.y(),imported.z());
            check(corridorRegion.isImported(cell)&&corridorRegion.placementRejection(cell,Set.of())!=null&&corridorRegion.breakRejection(cell,Set.of(cell))!=null&&corridorRegion.cleanupRejection(cell,Set.of(cell))!=null,
                    "All composite slab cells remain immutable for placement, break and cleanup");
        }
        for(var target:Set.of(new Cell(-1,65,-5),new Cell(0,64,-5)))
            check(corridorRegion.placementRejection(target,Set.of(corridorRegion.seed()))==null,"Top and east-side targets remain outside every imported cell");
        check(corridorRegion.targetRejection(corridorSupport)!=null,"Corridor support cannot become a vanilla-owned target");
        var bootstrap=corridorRegion.bootstrapPoint();var eye=new dev.minecome.protocol.Protocol.Vec3(0,65.73239337921143,0);
        double dx=bootstrap.x()-eye.x(),dy=bootstrap.y()-eye.y(),dz=bootstrap.z()-eye.z(),distance=Math.sqrt(dx*dx+dy*dy+dz*dz);
        var hit=dev.minecome.protocol.AimGeometry.intersect(new dev.minecome.protocol.AimGeometry.Ray(eye,new dev.minecome.protocol.Protocol.Vec3(dx/distance,dy/distance,dz/distance),4.5),corridorSupport.bounds());
        check(hit.isPresent()&&hit.get().face()==dev.minecome.protocol.AimGeometry.Face.UP&&hit.get().distance()<4.5,
                "Corridor bootstrap inner point reaches the support UP face from the recorded settled height");
        check(region.bootstrapPoint().equals(new dev.minecome.protocol.Protocol.Vec3(2.5,64,.5)),"Legacy bootstrap retains its original face centre");
        reject(()->HudBuildRegion.corridorSupport(patch,63),"Ordinary patch cannot request corridor selection");
        reject(()->new HudBuildRegion(corridor,new Cell(9,63,0)),"Corridor cannot expand beyond its one-cell support perimeter");
        System.out.println("HudBuildRegionTests: "+checks+" checks passed (no Minecraft/game bootstrap)");
    }
}
