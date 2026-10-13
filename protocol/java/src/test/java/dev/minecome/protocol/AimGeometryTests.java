package dev.minecome.protocol;
import java.nio.file.*;
import java.util.*;
import dev.minecome.protocol.Protocol.Vec3;
import dev.minecome.protocol.Protocol.Quaternion;
import dev.minecome.protocol.AimGeometry.*;

public final class AimGeometryTests {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static void near(double a,double b){check(Math.abs(a-b)<1e-9,"Geometry differs: "+a+" / "+b);}
    private static void near(Vec3 a,Vec3 b){near(a.x(),b.x());near(a.y(),b.y());near(a.z(),b.z());}
    private static Vec3 vector(String[] fields,int at){return new Vec3(Double.parseDouble(fields[at]),Double.parseDouble(fields[at+1]),Double.parseDouble(fields[at+2]));}
    private static void reject(Runnable action){try{action.run();}catch(IllegalArgumentException|NullPointerException expected){checks++;return;}throw new AssertionError("Invalid geometry accepted");}
    public static void main(String[] args)throws Exception{
        if(args.length!=1)throw new IllegalArgumentException("Pass shared aim_geometry.txt path");
        int maps=0,rays=0,orientations=0;
        for(String line:Files.readAllLines(Path.of(args[0]))){
            if(line.isBlank()||line.startsWith("#"))continue;String[] f=line.split("\\s+");
            switch(f[0]){
                case "map" -> {
                    check(f.length==14,"Map fixture fields");var alignment=new Alignment(vector(f,1),vector(f,4),Double.parseDouble(f[7]));
                    near(alignment.toKcd(vector(f,8)),vector(f,11));near(alignment.toMinecraft(vector(f,11)),vector(f,8));
                    var ray=new Ray(vector(f,4),new Vec3(0,1,0),2);var mapped=alignment.toMinecraft(ray);
                    near(mapped.direction(),new Vec3(0,0,-1));near(mapped.range(),2*alignment.blocksPerUnit());
                    near(alignment.toKcd(mapped).origin(),ray.origin());near(alignment.toKcd(mapped).direction(),ray.direction());near(alignment.toKcd(mapped).range(),ray.range());maps++;
                }
                case "forward" -> {
                    check(f.length==8,"Forward fixture fields");near(AimGeometry.forward(new Quaternion(Double.parseDouble(f[1]),Double.parseDouble(f[2]),Double.parseDouble(f[3]),Double.parseDouble(f[4]))),vector(f,5));orientations++;
                }
                case "ray" -> {
                    check(f.length==16,"Ray fixture fields");var ray=new Ray(vector(f,1),vector(f,4),Double.parseDouble(f[7]));var hit=AimGeometry.intersect(ray,new Bounds(vector(f,8),vector(f,11)));
                    double expected=Double.parseDouble(f[14]);check(hit.isPresent()==(expected>=0),"Golden hit/miss");
                    if(hit.isPresent()){near(hit.get().distance(),expected);check(hit.get().face().ordinal()==Integer.parseInt(f[15]),"Golden face");near(hit.get().point(),new Vec3(ray.origin().x()+ray.direction().x()*expected,ray.origin().y()+ray.direction().y()*expected,ray.origin().z()+ray.direction().z()*expected));}rays++;
                }
                default -> throw new AssertionError("Unknown shared fixture kind");
            }
        }
        check(maps==4&&rays==14&&orientations==4,"All shared golden vectors executed");
        var zero=new Vec3(0,0,0);var direction=new Vec3(1,0,0);var ray=new Ray(new Vec3(-2,.5,.5),direction,4.5);
        for(double value:new double[]{0,-1,Double.NaN,Double.POSITIVE_INFINITY}){
            reject(()->new Alignment(zero,zero,value));reject(()->new Ray(zero,direction,value));
        }
        reject(()->new Ray(zero,zero,4.5));reject(()->new Ray(zero,new Vec3(2,0,0),4.5));reject(()->new Ray(zero,direction,32.01));
        reject(()->new Ray(new Vec3(1e7,0,0),direction,1));reject(()->new Alignment(new Vec3(1e7+1,0,0),zero,1));
        reject(()->new Alignment(zero,zero,Double.MIN_VALUE).toKcd(direction));reject(()->new Alignment(zero,zero,Double.MAX_VALUE).toMinecraft(direction));
        reject(()->new Bounds(zero,zero));reject(()->new Bounds(direction,zero));
        var a=new Cell(0,0,0);var b=new Cell(2,0,0);var miss=new Cell(0,2,0);
        check(AimGeometry.nearestOwned(ray,List.of(miss,b,a)).orElseThrow().cell().equals(a),"Nearest owned cell");
        check(AimGeometry.nearestOwned(ray,List.of(a,b,miss)).orElseThrow().cell().equals(a),"Order independent nearest cell");
        check(AimGeometry.nearestOwned(ray,List.of(miss)).isEmpty(),"Unowned/intersection miss yields no target");
        check(AimGeometry.nearestOwned(ray,List.of()).isEmpty(),"Empty arena has no invented support");
        reject(()->AimGeometry.nearestOwned(ray,List.of(a,a)));
        var tooMany=new ArrayList<Cell>();for(int i=0;i<17;i++)tooMany.add(new Cell(i,0,0));reject(()->AimGeometry.nearestOwned(ray,tooMany));
        reject(()->AimGeometry.nearestOwned(ray,List.of(new Cell(Integer.MAX_VALUE,0,0))));
        var edgeRay=new Ray(new Vec3(-2,1,.5),direction,4.5);var upper=new Cell(0,1,0);
        check(AimGeometry.nearestOwned(edgeRay,List.of(upper,a)).orElseThrow().cell().equals(a),"Shared edge uses deterministic reference tie");
        var inside=AimGeometry.nearestOwned(new Ray(new Vec3(.5,.5,.5),direction,4.5),List.of(a));check(inside.orElseThrow().hit().inside(),"Inside-origin explicitly marked for caller refusal");
        System.out.println("AimGeometryTests: "+checks+" checks passed; shared golden vectors=22; math only, no aiming integration.");
    }
}
