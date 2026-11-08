package dev.minecome.gameplay;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.Set;

/** Immutable host publication read. Atomic replacement may briefly deny Windows
 * access; an unavailable read never changes the last accepted source timestamp.
 */
public final class GameplayCombatSnapshot {
    private static final int MAX_BYTES=131072;
    private GameplayCombatSnapshot(){}
    public static String read(Path path)throws IOException{
        try{
            var attributes=Files.readAttributes(path,BasicFileAttributes.class,LinkOption.NOFOLLOW_LINKS);
            if(attributes.isSymbolicLink()||!attributes.isRegularFile()||attributes.size()>MAX_BYTES)
                throw new IOException("Invalid combat snapshot file");
            // Resolve attributes again through the opened handle. The atomic
            // writer may replace the pathname between stat and open; either
            // complete publication is valid, but following a link is not.
            try(var channel=Files.newByteChannel(path,Set.of(StandardOpenOption.READ,LinkOption.NOFOLLOW_LINKS))){
                long size=channel.size();if(size>MAX_BYTES)throw new IOException("Oversized combat snapshot file");
                var bytes=ByteBuffer.allocate(MAX_BYTES+1);
                while(bytes.hasRemaining()&&channel.read(bytes)!=-1){}
                if(bytes.position()>MAX_BYTES||bytes.position()!=size||channel.size()!=size)
                    throw new IOException("Combat snapshot changed size while reading");
                bytes.flip();
                return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT).decode(bytes).toString();
            }
        }catch(FileSystemException busy){
            // Windows sharing violations are also reported as the generic
            // FileSystemException, not always AccessDeniedException. Match the
            // existing camera readers by exception type, never localized text.
            // One unavailable attempt returns immediately so guest publication
            // continues; the caller retains its original source freshness and
            // host-expiry deadline. Validation/UTF8 errors above still fail.
            return null;
        }
    }
}
