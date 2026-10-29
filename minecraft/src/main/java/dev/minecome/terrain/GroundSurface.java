package dev.minecome.terrain;

import java.util.List;

/** Immutable collision geometry with one host-to-Minecraft coordinate anchor. */
public interface GroundSurface {
    String run();
    String sourceKind();
    String sha256();
    double centerX();
    double centerY();
    double centerZ();
    List<GroundPatch.Point> points();
    List<GroundPatch.Slab> slabs();
    List<GroundPatch.Cell> cells();
    double heightAt(double x,double z);
    double groundForFeet(double x,double z,double radius);
    boolean containsFeet(double x,double z,double margin);
    boolean wide();
    default boolean corridor(){return false;}
}
