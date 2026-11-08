package dev.minecome.gameplay;

import net.fabricmc.fabric.api.object.builder.v1.entity.FabricDefaultAttributeRegistry;
import net.fabricmc.fabric.api.client.rendering.v1.EntityRendererRegistry;
import net.minecraft.client.render.Frustum;
import net.minecraft.client.render.entity.EntityRenderer;
import net.minecraft.entity.*;
import net.minecraft.entity.attribute.EntityAttributes;
import net.minecraft.entity.damage.DamageSource;
import net.minecraft.entity.data.*;
import net.minecraft.item.ItemStack;
import net.minecraft.registry.*;
import net.minecraft.util.Arm;
import net.minecraft.util.Identifier;
import net.minecraft.util.math.Vec3d;
import net.minecraft.world.World;
import java.util.List;

/** Ephemeral, invisible actor target. Native code owns its position/lifetime;
 * the actual 1.21.1 LivingEntity damage pipeline owns cooldowns and modifiers.
 * Inspected mapped bytecode: runtime/evidence/combat-source-20261108.
 */
public final class GameplayActorEntity extends LivingEntity {
    public interface DamageSink {
        boolean accepts(GameplayActorEntity target,DamageSource source,float amount);
        void applied(GameplayActorEntity target,DamageSource source,float amount);
        default void attempted(GameplayActorEntity target,DamageSource source,boolean accepted){}
    }
    private static final TrackedData<Integer> TOKEN=DataTracker.registerData(GameplayActorEntity.class,TrackedDataHandlerRegistry.INTEGER);
    private static final TrackedData<Float> WIDTH=DataTracker.registerData(GameplayActorEntity.class,TrackedDataHandlerRegistry.FLOAT);
    private static final TrackedData<Float> HEIGHT=DataTracker.registerData(GameplayActorEntity.class,TrackedDataHandlerRegistry.FLOAT);
    public static final EntityType<GameplayActorEntity> TYPE=EntityType.Builder.<GameplayActorEntity>create(GameplayActorEntity::new,SpawnGroup.MISC)
            .dimensions(.6f,1.8f).disableSaving().disableSummon().maxTrackingRange(10).trackingTickInterval(1).build("minecome:host_actor");
    private static boolean registered;
    private DamageSink sink;
    public static void register(){
        if(registered)return;registered=true;
        Registry.register(Registries.ENTITY_TYPE,Identifier.of("minecome","host_actor"),TYPE);
        FabricDefaultAttributeRegistry.register(TYPE,LivingEntity.createLivingAttributes().add(EntityAttributes.GENERIC_MAX_HEALTH,1024));
        EntityRendererRegistry.register(TYPE,context->new EntityRenderer<GameplayActorEntity>(context){
            @Override public boolean shouldRender(GameplayActorEntity entity,Frustum frustum,double x,double y,double z){return false;}
            @Override public Identifier getTexture(GameplayActorEntity entity){return Identifier.ofVanilla("textures/misc/white.png");}
        });
    }
    public GameplayActorEntity(EntityType<? extends GameplayActorEntity> type,World world){
        super(type,world);setNoGravity(true);noClip=true;setInvisible(true);setSilent(true);setHealth(getMaxHealth());
    }
    @Override protected void initDataTracker(DataTracker.Builder builder){super.initDataTracker(builder);builder.add(TOKEN,0);builder.add(WIDTH,.6f);builder.add(HEIGHT,1.8f);}
    public int token(){return dataTracker.get(TOKEN);}
    public void bind(int token,float width,float height,DamageSink sink){
        if(token<1||token>256||!Float.isFinite(width)||!Float.isFinite(height)||width<=0||width>4||height<=0||height>8)throw new IllegalArgumentException("Invalid host actor shape");
        if(token()!=0&&token()!=token)throw new IllegalStateException("Actor identity changed");
        dataTracker.set(TOKEN,token);dataTracker.set(WIDTH,width);dataTracker.set(HEIGHT,height);calculateDimensions();this.sink=sink;
    }
    @Override public void onTrackedDataSet(TrackedData<?> field){super.onTrackedDataSet(field);if(field.equals(WIDTH)||field.equals(HEIGHT))calculateDimensions();}
    @Override protected EntityDimensions getBaseDimensions(EntityPose pose){return EntityDimensions.changing(dataTracker.get(WIDTH),dataTracker.get(HEIGHT));}
    @Override public boolean damage(DamageSource source,float amount){
        if(getWorld().isClient||sink==null)return false;
        if(!Float.isFinite(amount)||amount<=0||amount>1000||!sink.accepts(this,source,amount)){sink.attempted(this,source,false);return false;}
        boolean accepted=super.damage(source,amount);sink.attempted(this,source,accepted);return accepted;
    }
    @Override protected void applyDamage(DamageSource source,float amount){
        // 1.21.1 applies armour/effects/absorption inside super.applyDamage.
        // Read its real health delta, then restore this unsaved adapter before
        // the outer vanilla damage() checks death. Host death owns removal.
        float before=getHealth();super.applyDamage(source,amount);float applied=before-getHealth();setHealth(before);
        if(applied>0&&sink!=null)sink.applied(this,source,applied);
    }
    @Override public void tick(){baseTick();setVelocity(Vec3d.ZERO);}
    @Override public void updateTrackedPositionAndAngles(double x,double y,double z,float yaw,float pitch,int steps){refreshPositionAndAngles(x,y,z,yaw,pitch);}
    @Override public void takeKnockback(double strength,double x,double z){/* The native actor owns physical movement. */}
    @Override public boolean isPushable(){return false;}
    @Override public boolean collidesWith(Entity other){return false;}
    @Override public boolean isAttackable(){return true;}
    @Override public boolean canHit(){return isAlive();}
    @Override public Iterable<ItemStack> getArmorItems(){return List.of();}
    @Override public ItemStack getEquippedStack(EquipmentSlot slot){return ItemStack.EMPTY;}
    @Override public void equipStack(EquipmentSlot slot,ItemStack stack){}
    @Override public Arm getMainArm(){return Arm.RIGHT;}
}
