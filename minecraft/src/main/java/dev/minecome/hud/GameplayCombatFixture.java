package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.*;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.ingame.InventoryScreen;
import net.minecraft.entity.EquipmentSlot;
import net.minecraft.entity.projectile.PersistentProjectileEntity;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerEntityEvents;
import net.minecraft.item.Items;
import net.minecraft.block.Blocks;
import net.minecraft.util.math.BlockPos;
import net.minecraft.registry.Registries;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.math.Vec3d;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Actual vanilla attack packets and mob damage, with an explicitly synthetic host.
 * The fixture writes only its host transport, evidence and ordinary chat commands.
 * It never assigns player health, equipment, entity position or combat cooldowns.
 */
public final class GameplayCombatFixture {
    private record State(long at,int tick,UUID player,String mode,Vec3d position,float health,
                         String held,int heldDamage,String chest,int chestDamage,int armor,boolean chestEnchanted,int arrows,boolean using,int useTicks){}
    private record Shot(UUID id,UUID owner,double speed,boolean critical){}
    private record Sample(String stage,HudReadback.Completed frame){}
    private final GameplayCombat combat;private final GameplayBlocks blocks;private final GameplayMovement movement;
    private final GameplayWorld save;private final HudInputProtocol.Identity identity;private final Path directory;
    private final Consumer<JsonObject> completed;private final long created=System.nanoTime();
    private final AtomicReference<State> observation=new AtomicReference<>();private final AtomicReference<String> failure=new AtomicReference<>();
    private final AtomicBoolean observing=new AtomicBoolean();private final ArrayBlockingQueue<Sample> samples=new ArrayBlockingQueue<>(2);
    private final Map<String,JsonObject> images=new ConcurrentHashMap<>();private final Set<String> queued=new HashSet<>();
    private final CopyOnWriteArrayList<JsonObject> hits=new CopyOnWriteArrayList<>();private final List<String> commands=new ArrayList<>();
    private MinecraftServer server;private Object world,player;private UUID playerId;private HudVanillaUiAdapter ui;
    private volatile boolean closing,finished;private volatile long hitAck,hurtAck,requestedHurt,hostWrites,viewWrites;
    private volatile Vec3d forward=new Vec3d(1,0,0);private int targetToken=1,stage,ticks,actionTick,readyTick=-1;
    private long begun,stageAt,events;private double bareHit,woodHit,diamondHit,quickHit,bareHurt,armoredHurt;
    private double projectileHurt,projectileProtectedHurt;private boolean incomingProjectileVerified,projectileProtectionVerified;
    private boolean fistVerified,woodVerified,diamondVerified,cooldownVerified,durabilityVerified,inventoryVerified,inventoryAttackAttempted,occlusionVerified,incomingVerified,armorVerified,rendered;
    private float beforeHurt;private State finalState;
    private final boolean bowCheck=GameplayRangedUse.enabled();
    private final CopyOnWriteArrayList<Shot> shots=new CopyOnWriteArrayList<>();
    private boolean bowInventoryCancel,bowAuthorityCancel,bowShortRelease,bowFullRelease,bowNoAmmo,bowRendered;
    private BlockPos bowWall;
    private final boolean projectileCheck=Boolean.getBoolean("minecome.gameplayProjectileFixture");
    private volatile Vec3d projectileOrigin;
    private volatile long projectileSequence,projectileScenery,projectileImpacts;
    private volatile double projectileHealth=100,projectileDamage;

    public GameplayCombatFixture(String mode,GameplayCombat combat,GameplayBlocks blocks,GameplayMovement movement,
                                 GameplayWorld save,HudInputProtocol.Identity identity,Path directory,Consumer<JsonObject> completed)throws IOException{
        if(!mode.equals("combat")||!Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayCombat")||!Boolean.getBoolean("minecome.gameplayWorldBlocks"))
            throw new IllegalArgumentException("Explicit standalone WorldBlocks combat fixture required");
        this.combat=combat;this.blocks=blocks;this.movement=movement;this.save=save;this.identity=identity;this.directory=directory.toRealPath();this.completed=completed;
        save.verifyOwnership();if(!save.newlyCreated()||Files.exists(this.directory.resolve("host-combat.json"))||Files.exists(this.directory.resolve("gameplay-combat-fixture.json")))throw new IOException("Combat fixture needs a fresh owned save and transport");
        if(bowCheck)ServerEntityEvents.ENTITY_LOAD.register((entity,world)->{
            if(closing||finished||server==null||world!=server.getOverworld()||!(entity instanceof PersistentProjectileEntity arrow)||
                arrow.getOwner()==null||!arrow.getOwner().getUuid().equals(playerId))return;
            if(shots.size()>=4){failure.compareAndSet(null,"Unexpected extra fixture arrows");return;}
            // Read actual vanilla spawn velocity before its first collision tick.
            shots.add(new Shot(arrow.getUuid(),arrow.getOwner().getUuid(),arrow.getVelocity().length(),arrow.isCritical()));
        });
        var worker=new Thread(this::writeLoop,"MineComeGameplayCombatFixture");worker.setDaemon(true);worker.start();
    }
    public void beforeTick(MinecraftClient c){if(closing||finished||begun==0)return;try{owner(c);movement.authority(c,System.nanoTime(),true);}catch(Exception e){complete(c,false,e.toString());}}
    private Vec3d target(){return bowCheck&&stage>=20?MinecraftClient.getInstance().player.getEyePos().add(forward.multiply(3)):new Vec3d(2.2,64.9,targetToken==1?0:1.1);}
    public GameplayWorldRenderer.View view(){
        var c=MinecraftClient.getInstance();if(begun==0||closing||finished||c.player!=player)return null;
        var eye=c.player.getEyePos();var f=target().subtract(eye).normalize();var right=f.crossProduct(new Vec3d(0,1,0)).normalize();return new GameplayWorldRenderer.View(eye,f,right.crossProduct(f).normalize(),Math.toRadians(70));
    }
    public GameplayBlocks.Aim renderAim(){
        var c=MinecraftClient.getInstance();if(begun==0||closing||finished||c.player!=player)return null;
        var eye=c.player.getEyePos();var direction=target().subtract(eye).normalize();return new GameplayBlocks.Aim(System.currentTimeMillis(),System.nanoTime(),eye,direction,3,true,-1,false);
    }
    public void tick(MinecraftClient c){
        if(closing||finished)return;
        try{
            if(failure.get()!=null)throw new IllegalStateException(failure.get());
            if(!movement.ready()||!blocks.ready()){if(System.nanoTime()-created>60_000_000_000L)throw new IllegalStateException("Combat fixture terrain readiness timeout");return;}
            if(begun==0)begin(c);owner(c);long now=System.nanoTime();
            if(now-begun>60_000_000_000L||now-stageAt>12_000_000_000L)throw new IllegalStateException("Combat fixture timeout stage="+stage+" state="+state(observation.get())+" combat="+combat.evidence(c));
            observe();var s=observation.get();if(s==null||now<s.at()||now-s.at()>500_000_000L)return;
            if(!s.player().equals(playerId))throw new IllegalStateException("Combat fixture player changed");ticks++;
            combat.tick(c,c.currentScreen==null,renderAim(),-1);
            switch(stage){
                case 0->{send(c,"gamemode survival");send(c,"difficulty normal");send(c,"gamerule naturalRegeneration false");next(1,now);}
                case 1->{if(!s.mode().equals("survival")||!s.held().equals("minecraft:air")||s.health()!=20||!ready(c))return;if(!delay(s,25))return;attack(c);actionTick=s.tick();next(2,now);}
                case 2->{if(!acknowledged(c,1))return;bareHit=damage(0);near(bareHit,1,"Bare-hand vanilla damage");fistVerified=true;if(s.tick()-actionTick<25)return;send(c,"item replace entity @s hotbar.0 with minecraft:wooden_sword");next(3,now);}
                case 3->{if(!s.held().equals("minecraft:wooden_sword")||!c.player.getMainHandStack().isOf(Items.WOODEN_SWORD)||s.heldDamage()!=0||!delay(s,25))return;attack(c);actionTick=s.tick();next(4,now);}
                case 4->{if(!acknowledged(c,2)||s.heldDamage()!=1)return;woodHit=damage(1);near(woodHit,4,"Wooden sword vanilla damage");woodVerified=durabilityVerified=true;if(s.tick()-actionTick<25)return;send(c,"item replace entity @s hotbar.0 with minecraft:diamond_sword");next(5,now);}
                case 5->{if(!s.held().equals("minecraft:diamond_sword")||!c.player.getMainHandStack().isOf(Items.DIAMOND_SWORD)||s.heldDamage()!=0||!delay(s,25))return;targetToken=1;attack(c);actionTick=s.tick();next(6,now);}
                case 6->{if(!acknowledged(c,3)||s.heldDamage()!=1)return;diamondHit=damage(2);near(diamondHit,7,"Diamond sword vanilla damage");diamondVerified=true;if(s.tick()-actionTick>9)throw new IllegalStateException("Cooldown comparison missed its bounded rapid-hit window");targetToken=2;attack(c);next(7,now);}
                case 7->{if(!acknowledged(c,4)||s.heldDamage()!=2)return;quickHit=damage(3);if(quickHit<=0||quickHit>=diamondHit-.2)throw new IllegalStateException("Vanilla cooldown did not reduce rapid second-target damage: "+quickHit);cooldownVerified=true;key(c,'E');actionTick=s.tick();next(8,now);}
                case 8->{if(!(c.currentScreen instanceof InventoryScreen))return;combat.tick(c,false,renderAim(),-1);if(!inventoryAttackAttempted){combat.event(c,event(7,0));combat.event(c,event(8,0));inventoryAttackAttempted=true;}if(s.tick()-actionTick<8)return;if(hits.size()!=4||hitAck!=4)throw new IllegalStateException("Inventory permitted a world attack");inventoryVerified=true;key(c,'E');targetToken=1;send(c,"fill 1 65 -1 1 65 1 minecraft:stone");next(12,now);}
                case 9->{if(hurtAck<1||s.health()>=beforeHurt)return;bareHurt=beforeHurt-s.health();near(bareHurt,8,"Unarmored mobAttack damage");incomingVerified=true;send(c,"item replace entity @s armor.chest with minecraft:diamond_chestplate");send(c,"effect give @s minecraft:instant_health 1 4 true");actionTick=s.tick();next(10,now);}
                case 10->{if(!s.chest().equals("minecraft:diamond_chestplate")||s.armor()<=0||s.health()!=20||s.tick()-actionTick<25)return;beforeHurt=s.health();requestedHurt=2;next(11,now);}
                case 11->{if(hurtAck<2||s.health()>=beforeHurt||s.chestDamage()==0)return;armoredHurt=beforeHurt-s.health();if(armoredHurt<=0||armoredHurt>=bareHurt)throw new IllegalStateException("Minecraft armor did not reduce native damage");armorVerified=true;if(!images.containsKey("combat"))return;validateImage();rendered=true;send(c,"effect give @s minecraft:instant_health 1 4 true");actionTick=s.tick();next(40,now);}
                case 40->{if(s.health()!=20||s.chestEnchanted()||s.tick()-actionTick<25)return;beforeHurt=s.health();requestedHurt=3;next(41,now);}
                case 41->{if(hurtAck<3||s.health()>=beforeHurt)return;projectileHurt=beforeHurt-s.health();near(projectileHurt,armoredHurt,"Unenchanted armor receives the same vanilla melee/arrow damage");incomingProjectileVerified=true;
                    send(c,"item replace entity @s armor.chest with minecraft:diamond_chestplate[minecraft:enchantments={levels:{\"minecraft:projectile_protection\":4}}]");send(c,"effect give @s minecraft:instant_health 1 4 true");actionTick=s.tick();next(42,now);}
                case 42->{if(s.health()!=20||!s.chestEnchanted()||s.chestDamage()!=0||s.tick()-actionTick<25)return;beforeHurt=s.health();requestedHurt=4;next(43,now);}
                case 43->{if(hurtAck<4||s.health()>=beforeHurt||s.chestDamage()==0)return;projectileProtectedHurt=beforeHurt-s.health();near(projectileProtectedHurt,projectileHurt*.68,"Vanilla ProjectileProtectionIV reduces arrow damage by32percent");projectileProtectionVerified=true;finalState=s;if(bowCheck)next(20,now);else complete(c,true,null);}
                case 12->{if(!c.world.getBlockState(new BlockPos(1,65,0)).isOf(Blocks.STONE))return;if(combat.aimedTargetDistance(c,renderAim())>=0||combat.event(c,event(7,0)))throw new IllegalStateException("Minecraft wall permitted actor attack");combat.event(c,event(8,0));actionTick=s.tick();next(13,now);}
                case 13->{if(s.tick()-actionTick<5)return;if(hits.size()!=4||hitAck!=4)throw new IllegalStateException("Occluded actor attack changed host health");send(c,"fill 1 65 -1 1 65 1 minecraft:air");next(14,now);}
                case 14->{if(!c.world.getBlockState(new BlockPos(1,65,0)).isAir()||combat.aimedTargetDistance(c,renderAim())<0)return;occlusionVerified=true;beforeHurt=s.health();requestedHurt=1;next(9,now);}
                case 20->{if(!c.player.isOnGround()||c.player.getVelocity().horizontalLengthSquared()>.0001||!delay(s,10))return;forward=new Vec3d(s.position().x<0?1:-1,0,0);bowWall=BlockPos.ofFloored(s.position().add(forward.multiply(3)));if(!movement.surface().containsFeet(bowWall.getX()+.5,bowWall.getZ(),1.1))throw new IllegalStateException("Bow backstop outside captured coverage");send(c,"item replace entity @s hotbar.0 with minecraft:bow");send(c,"item replace entity @s hotbar.1 with minecraft:arrow 4");projectileOrigin=s.position();if(!projectileCheck)send(c,bowWallCommand("stone"));next(21,now);}
                case 21->{if(!s.held().equals("minecraft:bow")||s.arrows()!=4||c.player.getInventory().count(Items.ARROW)!=4||!c.player.getMainHandStack().isOf(Items.BOW)||!delay(s,6))return;bowPress(c);next(22,now);}
                case 22->{if(!s.using()||s.useTicks()<25)return;blocks.suspend(c);key(c,'E');actionTick=s.tick();next(23,now);}
                case 23->{if(!(c.currentScreen instanceof InventoryScreen)||s.tick()-actionTick<6)return;unchangedBow(c,s);bowInventoryCancel=true;key(c,'E');next(24,now);}
                case 24->{if(c.currentScreen!=null||!delay(s,3))return;bowPress(c);next(25,now);}
                case 25->{if(!s.using()||s.useTicks()<25)return;blocks.beforeTick(c,false);actionTick=s.tick();next(26,now);}
                case 26->{if(s.tick()-actionTick<6)return;unchangedBow(c,s);bowAuthorityCancel=true;bowPress(c);next(27,now);}
                case 27->{if(!s.using()||s.useTicks()<5)return;bowRelease(c);next(28,now);}
                case 28->{if(s.using()||s.arrows()!=3||s.heldDamage()!=1||c.player.getMainHandStack().getDamage()!=1||shots.size()!=1)return;var shot=shots.getFirst();if(shot.critical()||shot.speed()<=.3||shot.speed()>=2.5)throw new IllegalStateException("Short vanilla bow charge differs: "+shot);bowShortRelease=true;bowPress(c);next(29,now);}
                case 29->{if(!s.using()||s.useTicks()<25)return;bowRelease(c);next(30,now);}
                case 30->{if(s.using()||s.arrows()!=2||s.heldDamage()!=2||shots.size()!=2)return;var shot=shots.get(1);if(!shot.critical()||shot.speed()<2.8||shot.speed()>3.2||shot.speed()<=shots.getFirst().speed())throw new IllegalStateException("Full vanilla bow charge differs: "+shot);bowFullRelease=true;next(31,now);}
                case 31->{if(projectileCheck&&(projectileScenery!=1||projectileImpacts!=1||combat.evidence(c).getAsJsonObject("projectiles").get("pending").getAsBoolean()))return;if(!images.containsKey("bow"))return;validateBowImage();bowRendered=true;send(c,"clear @s minecraft:arrow");send(c,bowWallCommand("air"));next(32,now);}
                case 32->{if(s.arrows()!=0||c.player.getInventory().count(Items.ARROW)!=0||!c.world.getBlockState(bowWall.up()).isAir()||!delay(s,3))return;blocks.tick(c,true);blocks.event(c,event(7,1));actionTick=s.tick();next(33,now);}
                case 33->{if(s.tick()-actionTick<6)return;blocks.event(c,event(8,1));if(s.using()||c.player.isUsingItem()||shots.size()!=2||s.heldDamage()!=2)throw new IllegalStateException("Bow fired without ammunition");bowNoAmmo=true;complete(c,true,null);}
                default->throw new IllegalStateException("Unknown combat fixture stage");
            }
        }catch(Exception e){complete(c,false,e.toString());}
    }
    private void begin(MinecraftClient c)throws IOException{
        if(!c.isOnThread()||c.world==null||c.player==null||c.getServer()==null||!c.isIntegratedServerRunning()||!c.options.getPerspective().isFirstPerson())throw new IllegalStateException("Owned first-person integrated client required");
        save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();ui=new HudVanillaUiAdapter(c,true);begun=stageAt=System.nanoTime();
    }
    private boolean delay(State s,int duration){if(readyTick<0){readyTick=s.tick();return false;}return s.tick()-readyTick>=duration;}
    private boolean ready(MinecraftClient c){var e=combat.evidence(c);return e.get("ready").getAsBoolean()&&!e.get("pending").getAsBoolean();}
    private boolean acknowledged(MinecraftClient c,int n){return hits.size()>=n&&hitAck>=n&&ready(c);}
    private double damage(int index){return hits.get(index).get("damage_mc").getAsDouble();}
    private static void near(double value,double expected,String label){if(Math.abs(value-expected)>.01)throw new IllegalStateException(label+" differs: "+value);}
    private void attack(MinecraftClient c){combat.tick(c,true,renderAim(),-1);if(!combat.event(c,event(7,0)))throw new IllegalStateException("Combat controller did not consume aimed attack");combat.event(c,event(8,0));}
    private void bowPress(MinecraftClient c){blocks.tick(c,true);blocks.event(c,event(7,1));if(!c.player.isUsingItem())throw new IllegalStateException("Bow draw did not start: "+blocks.evidence(c).get("ranged_use"));}
    private void bowRelease(MinecraftClient c){blocks.event(c,event(8,1));}
    private String bowWallCommand(String block){return "fill "+bowWall.getX()+" "+bowWall.getY()+" "+(bowWall.getZ()-1)+" "+bowWall.getX()+" "+(bowWall.getY()+4)+" "+(bowWall.getZ()+1)+" minecraft:"+block;}
    private void unchangedBow(MinecraftClient c,State s){if(s.using()||c.player.isUsingItem()||s.arrows()!=4||s.heldDamage()!=0||!shots.isEmpty()||blocks.evidence(c).getAsJsonObject("ranged_use").get("cancel_pending").getAsBoolean())throw new IllegalStateException("Cancelled bow fired or retained draw: "+state(s));}
    private void owner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Combat fixture owner changed");}
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{
        if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);if(!server.isOnThread()||p==null||p.getWorld()!=server.getOverworld()||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Combat fixture server owner changed");
        var held=p.getMainHandStack();var chest=p.getEquippedStack(EquipmentSlot.CHEST);observation.set(new State(System.nanoTime(),server.getTicks(),p.getUuid(),p.interactionManager.getGameMode().getName(),p.getPos(),p.getHealth(),Registries.ITEM.getId(held.getItem()).toString(),held.getDamage(),Registries.ITEM.getId(chest.getItem()).toString(),chest.getDamage(),p.getArmor(),chest.hasEnchantments(),p.getInventory().count(Items.ARROW),p.isUsingItem(),p.getItemUseTime()));
    }catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private HudInputProtocol.Event event(int kind,int code){return new HudInputProtocol.Event(++events,System.currentTimeMillis(),kind,code,0,0,0);}
    private void key(MinecraftClient c,int code){ui.apply(c,event(1,code));ui.apply(c,event(2,code));}
    private void send(MinecraftClient c,String command){owner(c);c.getNetworkHandler().sendChatCommand(command);commands.add(command);}
    private void next(int value,long now){stage=value;stageAt=now;ticks=0;readyTick=-1;}
    public String captureStage(){if(closing||finished)return null;String label=stage==11&&armorVerified&&ticks>=5?"combat":bowCheck&&stage==31&&bowFullRelease?"bow":null;return label!=null&&!queued.contains(label)&&!images.containsKey(label)?label:null;}
    public void captured(HudReadback.Completed frame){if(closing||finished)return;var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();if(!meta.has("combat_fixture_stage"))return;String label=meta.get("combat_fixture_stage").getAsString();if(!Set.of("combat","bow").contains(label)||label.equals("bow")&&(!bowCheck||meta.get("projectile_render_count").getAsInt()<1)||!queued.add(label))return;if(!samples.offer(new Sample(label,frame)))failure.compareAndSet(null,"Combat capture queue full");}
    private void validateImage(){var image=images.get("combat");var m=image.getAsJsonObject("metadata");if(!m.get("screen_kind").getAsString().equals("none")||m.get("frame_format").getAsInt()!=2||!m.has("world_camera")||image.get("hud_pixels").getAsLong()<1000)throw new IllegalStateException("Combat HUD pixels/world view missing");}
    private void validateBowImage(){var image=images.get("bow");var m=image.getAsJsonObject("metadata");if(image.get("world_pixels").getAsLong()<1||image.get("world_with_depth_pixels").getAsLong()<1||m.get("projectile_render_count").getAsInt()<1||m.get("rendered_world_blocks").getAsInt()!=0||m.get("dropped_item_render_count").getAsInt()!=0||m.get("player_pixels").getAsBoolean())throw new IllegalStateException("Isolated real arrow world/depth pixels missing");for(var entry:m.getAsJsonArray("projectiles")){var p=entry.getAsJsonObject();if(!p.get("owner").getAsString().equals(playerId.toString())||shots.stream().noneMatch(shot->shot.id().toString().equals(p.get("id").getAsString())))throw new IllegalStateException("Rendered projectile not an observed vanilla bow shot");}}
    private void writeSample(Sample sample)throws Exception{
        var f=sample.frame();byte[] layers=f.layersBottomUp();HudLayerPixels.require(layers,f.width(),f.height());int plane=HudPixels.byteSize(f.width(),f.height());long pixels=0;for(int i=3;i<plane;i+=4)if((layers[i]&255)>8)pixels++;
        byte[] png=HudPixels.png(HudPixels.straightTopLeft(Arrays.copyOfRange(layers,0,plane),f.width(),f.height()),f.width(),f.height());String file="combat-"+sample.stage()+".png";Files.write(directory.resolve(file),png,StandardOpenOption.CREATE_NEW);
        var p=new JsonObject();p.addProperty("stage",sample.stage());p.addProperty("file",file);p.addProperty("sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(png)));p.addProperty("hud_pixels",pixels);p.add("metadata",JsonParser.parseString(f.metadata()));
        if(sample.stage().equals("bow")){long worldPixels=0,withDepth=0;var raw=java.nio.ByteBuffer.wrap(layers).order(java.nio.ByteOrder.LITTLE_ENDIAN);for(int i=0;i<plane;i+=4){float d=raw.getFloat(plane*2+i);if(!Float.isFinite(d)||d<0||d>1)throw new IllegalStateException("Invalid arrow frame depth");if((layers[plane+i+3]&255)>8){worldPixels++;if(d>0&&d<1)withDepth++;}}byte[] worldPng=HudPixels.png(HudPixels.straightTopLeft(Arrays.copyOfRange(layers,plane,plane*2),f.width(),f.height()),f.width(),f.height());String worldFile="combat-bow-world.png";Files.write(directory.resolve(worldFile),worldPng,StandardOpenOption.CREATE_NEW);p.addProperty("world_file",worldFile);p.addProperty("world_sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(worldPng)));p.addProperty("world_pixels",worldPixels);p.addProperty("world_with_depth_pixels",withDepth);images.put(sample.stage(),p);}
        images.put(sample.stage(),p);
    }
    private JsonObject identity(String kind,long sequence){var p=new JsonObject();p.addProperty("schema",1);p.addProperty("kind",kind);p.addProperty("run",identity.run());p.addProperty("world_id",save.id().toString());p.addProperty("target_pid",identity.targetPid());p.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));p.addProperty("patch_run",movement.surface().run());p.addProperty("patch_sha256",movement.surface().sha256());p.addProperty("seq",sequence);p.addProperty("utc_ms",System.currentTimeMillis());return p;}
    private void writeLoop(){long sequence=0,actorHurt=0;GameplayCombatProtocol.Point incomingActor=null;double[] health={100,100};var hurtSources=new HashMap<Long,Long>();try{while(!closing){
        var sample=samples.poll();if(sample!=null)writeSample(sample);
        if(projectileCheck)projectileHost();
        var output=directory.resolve("combat.json");if(Files.exists(output,LinkOption.NOFOLLOW_LINKS)){
            if(Files.isSymbolicLink(output)||Files.size(output)>16384)throw new IOException("Combat guest fixture publication invalid");JsonObject guest;
            try{guest=JsonParser.parseString(Files.readString(output,StandardCharsets.UTF_8)).getAsJsonObject();}catch(java.nio.file.FileSystemException sharing){Thread.sleep(5);continue;}
            if(!guest.get("run").getAsString().equals(identity.run())||!guest.get("world_id").getAsString().equals(save.id().toString())||!guest.get("kind").getAsString().equals("minecome_gameplay_combat_guest_v1"))throw new IOException("Combat fixture guest identity differs");
            hurtAck=guest.get("hurt_ack").getAsLong();if(hurtAck>requestedHurt)throw new IOException("Combat fixture unexpected hurt ACK");
            if(guest.has("hit")&&!guest.get("hit").isJsonNull()){
                var hit=guest.getAsJsonObject("hit");long seq=hit.get("seq").getAsLong();if(seq>hitAck){if(seq!=hitAck+1)throw new IOException("Combat fixture skipped hit");int token=hit.get("token").getAsInt();double amount=hit.get("damage_mc").getAsDouble();if(token<1||token>2||!Double.isFinite(amount)||amount<=0||amount>20)throw new IOException("Combat fixture hit invalid");near(hit.get("damage_fraction").getAsDouble(),amount/20,"Combat damage fraction");var record=hit.deepCopy();record.addProperty("synthetic_host_health_before",health[token-1]);health[token-1]=Math.max(0,health[token-1]-amount*5);record.addProperty("synthetic_host_health_after",health[token-1]);hits.add(record);hitAck=seq;}
            }
        }
        if(requestedHurt>actorHurt){
            // Keep each synthetic attack position immutable until its ACK, and
            // let ordinary knockback push toward the small fixture arena's
            // centre. Four same-direction hits would knock the player off it.
            var state=observation.get();if(state==null)throw new IOException("Incoming fixture actor lacks observed player position");
            var radial=new Vec3d(state.position().x,0,state.position().z);if(radial.lengthSquared()<.01)radial=new Vec3d(1,0,0);
            var point=state.position().add(radial.normalize().multiply(2.2));incomingActor=GameplayCombatProtocol.toHost(new GameplayCombatProtocol.Point(point.x,point.y,point.z),movement.surface());actorHurt=requestedHurt;
        }
        var p=identity("minecome_gameplay_combat_host_v1",++sequence);var actors=new JsonArray();for(int token=1;token<=2;token++){var a=new JsonObject();a.addProperty("token",token);a.addProperty("x",token==1&&incomingActor!=null?incomingActor.x():movement.surface().centerX()+2.2);a.addProperty("y",token==1&&incomingActor!=null?incomingActor.y():movement.surface().centerY()-(token==1?0:1.1));a.addProperty("z",token==1&&incomingActor!=null?incomingActor.z():movement.surface().centerZ());a.addProperty("width",.8);a.addProperty("height",1.8);a.addProperty("health",health[token-1]);a.addProperty("max_health",100);a.addProperty("alive",health[token-1]>0);actors.add(a);}p.add("actors",actors);var hurts=new JsonArray();for(long seq=hurtAck+1;seq<=requestedHurt;seq++){var h=new JsonObject();h.addProperty("seq",seq);h.addProperty("attacker_token",1);h.addProperty("damage",8);h.addProperty("kind",seq>=3?"projectile":"melee");h.addProperty("source_utc_ms",hurtSources.computeIfAbsent(seq,ignored->System.currentTimeMillis()));hurts.add(h);}p.add("hurts",hurts);p.addProperty("hit_ack",hitAck);write("host-combat",p);hostWrites++;
        var view=new JsonObject();view.addProperty("schema",1);view.addProperty("source_kind","standalone_hud_physical_view_fixture");view.addProperty("run",identity.run());view.addProperty("patch_run",movement.surface().run());view.addProperty("patch_sha256",movement.surface().sha256());view.addProperty("target_pid",identity.targetPid());view.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));view.addProperty("seq",sequence);view.addProperty("utc_ms",System.currentTimeMillis());var f=forward;view.add("forward",vector(new Vec3d(f.x,-f.z,0)));view.add("up",vector(new Vec3d(0,0,1)));write("host-view",view);viewWrites++;Thread.sleep(25);
    }}catch(Exception e){if(!closing)failure.compareAndSet(null,e.toString());}}
    /** Synthetic contact replies exercise the production arrow tick/vanilla damage path. */
    private void projectileHost()throws Exception{
        var text=GameplayCombatSnapshot.read(directory.resolve("projectiles.json"));if(text==null)return;
        var request=JsonParser.parseString(text).getAsJsonObject();long seq=request.get("seq").getAsLong();if(seq==projectileSequence)return;
        if(seq!=projectileSequence+1||!request.get("run").getAsString().equals(identity.run())||!request.get("world_id").getAsString().equals(save.id().toString())||!request.get("kind").getAsString().equals("minecome_gameplay_projectiles_guest_v1"))throw new IOException("Synthetic projectile identity/order changed");
        var q=request.getAsJsonObject("request");String id=q.get("projectile").getAsString();int shot=-1;
        for(int i=0;i<shots.size();i++)if(shots.get(i).id().toString().replace("-","").equals(id))shot=i;
        if(shot<0||shot>1||projectileOrigin==null)throw new IOException("Synthetic projectile was not a real observed bow shot");
        var reply=new JsonObject();String operation=q.get("operation").getAsString();reply.addProperty("operation",operation);reply.addProperty("projectile",id);reply.addProperty("segment",q.get("segment").getAsInt());reply.addProperty("reason","");reply.addProperty("actor_token",0);reply.add("actor",JsonNull.INSTANCE);reply.add("before",JsonNull.INSTANCE);reply.add("after",JsonNull.INSTANCE);reply.add("normal",vector(Vec3d.ZERO));
        var from=readVector(q.getAsJsonObject("from"));var to=readVector(q.getAsJsonObject("to"));reply.add("contact",vector(to));
        if(operation.equals("trace")){
            double plane=movement.surface().centerX()+projectileOrigin.x+forward.x*(shot==0?2.25:2.75);
            double fraction=(plane-from.x)/(to.x-from.x);
            if(Double.isFinite(fraction)&&fraction>=0&&fraction<=1){
                var point=from.lerp(to,fraction);reply.add("contact",vector(point));reply.add("normal",vector(new Vec3d(-forward.x,0,0)));
                if(shot==0){reply.addProperty("result","scenery");projectileScenery++;}
                else{reply.addProperty("result","actor");reply.addProperty("actor_token",200);var actor=new JsonObject();actor.addProperty("token",200);actor.addProperty("x",plane+forward.x*.3);actor.addProperty("y",movement.surface().centerY()-projectileOrigin.z);actor.addProperty("z",movement.surface().centerZ()+projectileOrigin.y-64);actor.addProperty("width",.6);actor.addProperty("height",1.8);actor.addProperty("health",projectileHealth);actor.addProperty("max_health",100);actor.addProperty("alive",true);reply.add("actor",actor);}
            }else reply.addProperty("result","clear");
        }else if(operation.equals("impact")){
            if(shot!=1||projectileImpacts!=0||q.get("actor_token").getAsInt()!=200)throw new IOException("Unexpected synthetic arrow impact");
            double damage=q.get("damage_mc").getAsDouble();if(!Double.isFinite(damage)||damage<=0||damage>20)throw new IOException("Vanilla projectile damage invalid");near(q.get("damage_fraction").getAsDouble(),damage/20,"Arrow damage fraction");
            reply.addProperty("result","damaged");reply.addProperty("actor_token",200);reply.addProperty("before",projectileHealth);projectileHealth-=damage*5;reply.addProperty("after",projectileHealth);projectileDamage=damage;projectileImpacts++;
        }else throw new IOException("Unexpected projectile operation");
        var response=identity("minecome_gameplay_projectiles_host_v1",seq);response.addProperty("request_utc_ms",request.get("utc_ms").getAsLong());response.add("reply",reply);write("host-projectiles",response);projectileSequence=seq;
    }
    private static Vec3d readVector(JsonObject p){return new Vec3d(p.get("x").getAsDouble(),p.get("y").getAsDouble(),p.get("z").getAsDouble());}
    private void write(String name,JsonObject value)throws IOException,InterruptedException{var temp=directory.resolve(name+"-combat-fixture.tmp");Files.writeString(temp,value.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);HudFixtureCameraFiles.replace(temp,directory.resolve(name+".json"));}
    private static JsonObject vector(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private static JsonObject state(State s){var j=new JsonObject();if(s==null)return j;j.addProperty("player_id",s.player().toString());j.addProperty("mode",s.mode());j.addProperty("health",s.health());j.addProperty("held",s.held());j.addProperty("held_damage",s.heldDamage());j.addProperty("chest",s.chest());j.addProperty("chest_damage",s.chestDamage());j.addProperty("armor",s.armor());j.addProperty("chest_enchanted",s.chestEnchanted());j.addProperty("server_tick",s.tick());j.add("position",vector(s.position()));j.addProperty("arrows",s.arrows());j.addProperty("using",s.using());j.addProperty("use_ticks",s.useTicks());return j;}
    private void complete(MinecraftClient c,boolean passed,String error){
        if(finished)return;finished=true;try{combat.suspend(c);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("kind","minecome_gameplay_combat_fixture_v1");p.addProperty("mode","combat");p.addProperty("result",passed?"passed":"failed");p.addProperty("failure",error);p.addProperty("world_id",save.id().toString());p.addProperty("actual_minecraft",true);p.addProperty("standalone_scripted",true);p.addProperty("synthetic_host",true);p.addProperty("native_input_verified",false);p.addProperty("live_kcd_verified",false);p.addProperty("position_writes_used",false);p.addProperty("direct_health_inventory_entity_writes",false);p.addProperty("fist_damage_verified",fistVerified);p.addProperty("wooden_sword_verified",woodVerified);p.addProperty("diamond_sword_verified",diamondVerified);p.addProperty("cooldown_verified",cooldownVerified);p.addProperty("durability_verified",durabilityVerified);p.addProperty("inventory_suppression_verified",inventoryVerified);p.addProperty("minecraft_block_occlusion_verified",occlusionVerified);p.addProperty("incoming_damage_verified",incomingVerified);p.addProperty("armor_verified",armorVerified);p.addProperty("render_pixels_verified",rendered);p.addProperty("barehand_damage",bareHit);p.addProperty("wooden_sword_damage",woodHit);p.addProperty("diamond_sword_damage",diamondHit);p.addProperty("rapid_diamond_damage",quickHit);p.addProperty("unarmored_hurt",bareHurt);p.addProperty("armored_hurt",armoredHurt);p.addProperty("incoming_projectile_verified",incomingProjectileVerified);p.addProperty("projectile_protection_verified",projectileProtectionVerified);p.addProperty("projectile_hurt",projectileHurt);p.addProperty("projectile_protected_hurt",projectileProtectedHurt);p.addProperty("host_writes",hostWrites);p.addProperty("scripted_view_writes",viewWrites);p.addProperty("last_stage",stage);p.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);var a=new JsonArray();commands.forEach(a::add);p.add("commands",a);a=new JsonArray();for(var h:hits)a.add(h.deepCopy());p.add("hits",a);a=new JsonArray();if(images.containsKey("combat"))a.add(images.get("combat").deepCopy());p.add("images",a);p.add("final_state",state(finalState==null?observation.get():finalState));p.add("combat",combat.evidence(c));
        if(bowCheck){var bow=new JsonObject();bow.addProperty("experimental_fixture_only",true);bow.addProperty("inventory_cancel_verified",bowInventoryCancel);bow.addProperty("authority_cancel_verified",bowAuthorityCancel);bow.addProperty("short_charge_verified",bowShortRelease);bow.addProperty("full_charge_verified",bowFullRelease);bow.addProperty("no_ammunition_verified",bowNoAmmo);bow.addProperty("projectile_render_pixels_verified",bowRendered);bow.addProperty("native_projectile_collision_verified",false);bow.addProperty("synthetic_projectile_contacts_verified",projectileCheck&&projectileScenery==1&&projectileImpacts==1&&projectileDamage>0);bow.addProperty("synthetic_projectile_scenery_hits",projectileScenery);bow.addProperty("synthetic_projectile_impacts",projectileImpacts);bow.addProperty("synthetic_projectile_damage",projectileDamage);bow.add("controller",blocks.evidence(c).get("ranged_use").deepCopy());bow.add("final_state",state(observation.get()));var arrows=new JsonArray();for(var shot:shots){var j=new JsonObject();j.addProperty("id",shot.id().toString());j.addProperty("owner",shot.owner().toString());j.addProperty("initial_speed",shot.speed());j.addProperty("critical",shot.critical());arrows.add(j);}bow.add("shots",arrows);p.add("bow",bow);if(images.containsKey("bow"))p.getAsJsonArray("images").add(images.get("bow").deepCopy());}
        try{save.verifyOwnership();Files.writeString(directory.resolve("gameplay-combat-fixture.json"),p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}catch(Exception e){p.addProperty("result","failed");p.addProperty("failure",e.toString());}completed.accept(p);
    }
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){combat.suspend(c);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
