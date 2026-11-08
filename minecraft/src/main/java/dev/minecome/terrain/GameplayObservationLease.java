package dev.minecome.terrain;

import java.util.function.LongSupplier;
import java.util.function.Supplier;
import java.util.function.ToLongFunction;

/** Sample first, then read the clock: a concurrent publication is not a future observation. */
final class GameplayObservationLease {
    static final long MAX_AGE_NS=250_000_000L;
    record Reading<T>(T observation,long capturedAt,long checkedAt,boolean fresh){}
    static <T> Reading<T> read(Supplier<T> source,ToLongFunction<T> capturedAt,LongSupplier clock){
        T value=source.get();
        long now=clock.getAsLong(),at=value==null?0:capturedAt.applyAsLong(value);
        return new Reading<>(value,at,now,value!=null&&now>=at&&now-at<=MAX_AGE_NS);
    }
}
