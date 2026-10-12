package dev.minecome.input;

import com.google.gson.*;
import com.google.gson.stream.JsonReader;
import com.google.gson.stream.JsonToken;
import java.io.*;
import java.math.*;
import java.nio.ByteBuffer;
import java.nio.charset.*;
import java.util.Set;

/** Strict bounded decoder for one complete windows_raw_input_v1 NDJSON record. */
public final class ExternalInputDecoder {
    public static final int MAX_RECORD_BYTES = 4096;
    public static final String SOURCE_KIND = "windows_raw_input_v1";
    public static final BigInteger MAX_U64 = new BigInteger("18446744073709551615");
    private static final Set<String> COMMON = Set.of("schema", "kind", "source_kind", "run", "seq",
            "utc_ms", "monotonic_ms", "target_pid", "target_start_filetime", "focused", "armed",
            "held", "mouse_dx", "mouse_dy");
    private static final Set<String> HELD = Set.of("forward", "back", "left", "right", "jump", "sprint");
    private static final Set<String> REASONS = Set.of("duration", "target_exit", "write_error", "shutdown");
    private ExternalInputDecoder() {}

    public static ExternalInputRecord decode(byte[] bytes) throws IOException {
        if (bytes == null || bytes.length == 0 || bytes.length > MAX_RECORD_BYTES)
            throw new IOException("Invalid external input record byte count");
        final String text;
        try {
            text = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();
        } catch (CharacterCodingException e) { throw new IOException("Invalid external input UTF-8", e); }
        // Accept the caller's complete line with an optional LF/CRLF, never a second record.
        String json = text.endsWith("\r\n") ? text.substring(0, text.length() - 2)
                : text.endsWith("\n") ? text.substring(0, text.length() - 1) : text;
        if (json.startsWith("\ufeff") || json.indexOf('\n') >= 0 || json.indexOf('\r') >= 0)
            throw new IOException("External input must be exactly one JSON line");
        try (var reader = new JsonReader(new StringReader(json))) {
            reader.setLenient(false);
            JsonObject value = object(readJson(reader, 0, new int[] { 0 }), "record");
            if (reader.peek() != JsonToken.END_DOCUMENT) throw new IOException("Trailing external input content");
            String kindText = string(value, "kind");
            var kind = switch (kindText) {
                case "begin" -> ExternalInputRecord.Kind.BEGIN;
                case "sample" -> ExternalInputRecord.Kind.SAMPLE;
                case "end" -> ExternalInputRecord.Kind.END;
                default -> throw new IOException("Unknown external input record kind");
            };
            var required = new java.util.HashSet<>(COMMON);
            if (kind == ExternalInputRecord.Kind.END) required.add("reason");
            exactKeys(value, required, "record");
            if (!integer(value, "schema").equals(BigInteger.ONE) || !SOURCE_KIND.equals(string(value, "source_kind")))
                throw new IOException("External input schema/source mismatch");
            String run = string(value, "run");
            if (!validRun(run)) throw new IOException("Invalid external input run identity");
            long pid = boundedInteger(value, "target_pid", BigInteger.ONE, new BigInteger("4294967295")).longValueExact();
            String start = string(value, "target_start_filetime");
            if (!validFiletime(start)) throw new IOException("Invalid external input process creation identity");
            BigInteger sequence = boundedInteger(value, "seq", BigInteger.ONE, MAX_U64);
            long utc = boundedInteger(value, "utc_ms", BigInteger.ONE, BigInteger.valueOf(Long.MAX_VALUE)).longValueExact();
            long monotonic = boundedInteger(value, "monotonic_ms", BigInteger.ZERO, BigInteger.valueOf(Long.MAX_VALUE)).longValueExact();
            boolean focused = bool(value, "focused"), armed = bool(value, "armed");
            if (armed && !focused) throw new IOException("External input cannot be armed while unfocused");
            JsonObject keys = object(value.get("held"), "held");
            exactKeys(keys, HELD, "held");
            var held = new ExternalInputRecord.Held(bool(keys, "forward"), bool(keys, "back"),
                    bool(keys, "left"), bool(keys, "right"), bool(keys, "jump"), bool(keys, "sprint"));
            int dx = boundedInteger(value, "mouse_dx", BigInteger.valueOf(-32767), BigInteger.valueOf(32767)).intValueExact();
            int dy = boundedInteger(value, "mouse_dy", BigInteger.valueOf(-32767), BigInteger.valueOf(32767)).intValueExact();
            String reason = kind == ExternalInputRecord.Kind.END ? string(value, "reason") : null;
            if (reason != null && !REASONS.contains(reason)) throw new IOException("Unknown external input end reason");
            var result = new ExternalInputRecord(kind, run, pid, start, sequence, utc, monotonic,
                    focused, armed, held, dx, dy, reason);
            if ((kind != ExternalInputRecord.Kind.SAMPLE || !focused || !armed) && !result.neutral())
                throw new IOException("Inactive/begin/end external input must be neutral");
            if (kind != ExternalInputRecord.Kind.SAMPLE && (focused || armed))
                throw new IOException("Begin/end external input must be unfocused and disarmed");
            if (kind == ExternalInputRecord.Kind.BEGIN && (!sequence.equals(BigInteger.ONE) || monotonic != 0))
                throw new IOException("Begin external input requires sequence1/elapsed0");
            return result;
        } catch (IllegalArgumentException | IllegalStateException | ArithmeticException e) {
            throw new IOException("Invalid external input JSON: " + e.getMessage(), e);
        }
    }

    static boolean validRun(String run) { return run != null && run.matches("[0-9a-f]{32}"); }
    static boolean validFiletime(String value) {
        return value != null && value.matches("[1-9][0-9]{0,19}") && new BigInteger(value).compareTo(MAX_U64) <= 0;
    }
    private static JsonElement readJson(JsonReader reader, int depth, int[] count) throws IOException {
        if (depth > 2 || ++count[0] > 64) throw new IOException("External input JSON nesting/member bound exceeded");
        return switch (reader.peek()) {
            case BEGIN_OBJECT -> {
                reader.beginObject(); var value = new JsonObject();
                while (reader.hasNext()) {
                    String name = reader.nextName();
                    if (value.has(name)) throw new IOException("Duplicate external input field: " + name);
                    value.add(name, readJson(reader, depth + 1, count));
                }
                reader.endObject(); yield value;
            }
            case NUMBER -> {
                String numeric = reader.nextString();
                if (numeric.length() > 64 || !numeric.matches("-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?"))
                    throw new IOException("Invalid external input number");
                BigDecimal value = new BigDecimal(numeric);
                // Every wire number is integral and bounded by u64. Check decimal size
                // before conversion, including tiny exponents whose double value is zero.
                if (value.precision() > 32 || Math.abs((long) value.scale()) > 32)
                    throw new IOException("External input numeric precision/scale bound exceeded");
                if (!Double.isFinite(value.doubleValue())) throw new IOException("Non-finite external input number");
                yield new JsonPrimitive(value);
            }
            case STRING -> new JsonPrimitive(reader.nextString());
            case BOOLEAN -> new JsonPrimitive(reader.nextBoolean());
            default -> throw new IOException("Unexpected external input JSON value");
        };
    }
    private static JsonObject object(JsonElement value, String name) throws IOException {
        if (value == null || !value.isJsonObject()) throw new IOException(name + " must be an object");
        return value.getAsJsonObject();
    }
    private static void exactKeys(JsonObject value, Set<String> required, String name) throws IOException {
        if (!value.keySet().equals(required)) throw new IOException("Unexpected/missing " + name + " fields");
    }
    private static String string(JsonObject value, String key) throws IOException {
        JsonElement item = value.get(key);
        if (item == null || !item.isJsonPrimitive() || !item.getAsJsonPrimitive().isString())
            throw new IOException(key + " must be a string");
        return item.getAsString();
    }
    private static boolean bool(JsonObject value, String key) throws IOException {
        JsonElement item = value.get(key);
        if (item == null || !item.isJsonPrimitive() || !item.getAsJsonPrimitive().isBoolean())
            throw new IOException(key + " must be a boolean");
        return item.getAsBoolean();
    }
    private static BigInteger integer(JsonObject value, String key) throws IOException {
        JsonElement item = value.get(key);
        if (item == null || !item.isJsonPrimitive() || !item.getAsJsonPrimitive().isNumber())
            throw new IOException(key + " must be an integer number");
        try { return item.getAsBigDecimal().toBigIntegerExact(); }
        catch (ArithmeticException e) { throw new IOException(key + " must be integral", e); }
    }
    private static BigInteger boundedInteger(JsonObject value, String key, BigInteger min, BigInteger max) throws IOException {
        BigInteger number = integer(value, key);
        if (number.compareTo(min) < 0 || number.compareTo(max) > 0) throw new IOException(key + " exceeds its bound");
        return number;
    }
}
