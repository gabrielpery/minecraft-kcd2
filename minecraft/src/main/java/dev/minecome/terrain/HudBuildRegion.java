package dev.minecome.terrain;

import dev.minecome.protocol.AimGeometry;
import dev.minecome.protocol.AimGeometry.Cell;
import java.util.LinkedHashSet;
import java.util.Set;

/**
 * Immutable geometric ownership policy for a small arena beside imported ground.
 * Imported collision cells always remain AIR in the actual world. Even a partial
 * imported slab protects its entire block cell from placement, break and cleanup.
 * This policy neither writes blocks nor establishes ownership: callers supply
 * only stones already confirmed by the real client and integrated server in the
 * exact owned world, and must recheck those observations before dispatch/cleanup.
 */
public final class HudBuildRegion {
    public static final int MAX_OWNED=AimGeometry.MAX_OWNED_CELLS;
    private final String patchRun,patchSha256;
    private final Cell support,seed,minimum,maximum;
    private final Set<Cell> imported;

    public HudBuildRegion(GroundPatch patch,Cell support){
        if(patch==null || support==null)throw new IllegalArgumentException("Build region requires a patch and explicit bootstrap support");
        // The one-cell perimeter allows a fixture support immediately beside
        // the sampled footprint without granting a distant arbitrary region.
        int half=(int)patch.halfExtent();
        if(support.x()<-half-1 || support.x()>half || support.z()<-half-1 || support.z()>half)
            throw new IllegalArgumentException("Bootstrap support is outside sampled footprint/perimeter");
        double lowest=Double.POSITIVE_INFINITY,highest=Double.NEGATIVE_INFINITY;
        for(var slab:patch.slabs()){lowest=Math.min(lowest,slab.minY());highest=Math.max(highest,slab.maxY());}
        if(support.y()<Math.floor(lowest)-2 || support.y()>Math.ceil(highest)+2)
            throw new IllegalArgumentException("Bootstrap support is outside sampled height bounds");
        patchRun=patch.run();patchSha256=patch.sha256();this.support=support;
        seed=new Cell(support.x(),support.y()+1,support.z());
        var cells=new LinkedHashSet<Cell>();
        for(var cell:patch.cells())cells.add(new Cell(cell.x(),cell.y(),cell.z()));
        imported=Set.copyOf(cells);
        if(imported.contains(support) || imported.contains(seed))
            throw new IllegalArgumentException("Bootstrap support/seed intersects imported collision cells");
        minimum=new Cell(seed.x()-2,seed.y()-2,seed.z()-2);
        maximum=new Cell(seed.x()+2,seed.y()+2,seed.z()+2);
    }

    public String patchRun(){return patchRun;}
    public String patchSha256(){return patchSha256;}
    public Cell support(){return support;}
    public Cell seed(){return seed;}
    public Cell minimum(){return minimum;}
    public Cell maximumInclusive(){return maximum;}
    public Set<Cell> importedCells(){return imported;}
    public boolean isImported(Cell cell){return cell!=null && imported.contains(cell);}
    public boolean contains(Cell cell){
        return cell!=null && cell.x()>=minimum.x() && cell.x()<=maximum.x() &&
                cell.y()>=minimum.y() && cell.y()<=maximum.y() && cell.z()>=minimum.z() && cell.z()<=maximum.z();
    }
    /** Null means geometrically mutable; it does not certify air/stone or grant world access. */
    public String targetRejection(Cell target){
        if(target==null)return "target_missing";
        if(!contains(target))return "outside_build_region";
        if(imported.contains(target))return "imported_collision_cell";
        if(support.equals(target))return "bootstrap_support_immutable";
        return null;
    }
    /** An immutable support is never part of the vanilla-owned stone set. */
    public String ownedRejection(Set<Cell> confirmedOwned){
        if(confirmedOwned==null)return "owned_cells_missing";
        if(confirmedOwned.size()>MAX_OWNED)return "owned_limit";
        for(Cell cell:confirmedOwned){String reason=targetRejection(cell);if(reason!=null)return reason;}
        return null;
    }
    public String placementRejection(Cell target,Set<Cell> confirmedOwned){
        String reason=ownedRejection(confirmedOwned);if(reason!=null)return reason;
        reason=targetRejection(target);if(reason!=null)return reason;
        if(confirmedOwned.contains(target))return "already_owned";
        if(confirmedOwned.size()>=MAX_OWNED)return "owned_limit";
        return null;
    }
    public String breakRejection(Cell target,Set<Cell> confirmedOwned){
        String reason=ownedRejection(confirmedOwned);if(reason!=null)return reason;
        reason=targetRejection(target);if(reason!=null)return reason;
        return confirmedOwned.contains(target)?null:"unowned_target";
    }
    /** Cleanup has no broader authority than breaking an actually confirmed stone. */
    public String cleanupRejection(Cell target,Set<Cell> confirmedOwned){return breakRejection(target,confirmedOwned);}
}
