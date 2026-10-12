# Dependency-free Java v1 codec

The Java codec is built into the Fabric JAR and can also be compiled independently.
It uses little-endian explicit binary fields, rejects bad magic/version/reserved
flags/oversized payloads, rejects non-finite pose values and malformed UTF-8, and
keeps fragmented TCP frames across polling boundaries. Sequence ordering is checked
as unsigned 64-bit values by the connection layer.
Names must contain 1..128 UTF-8 bytes and credentials at most 128 bytes; malformed
Unicode/UTF-8 and nonempty Heartbeat/Goodbye payloads are rejected. A fragmented
Hello has an absolute six-second deadline. A received pose is exposed only while
connected and for one second after its receipt; heartbeats do not refresh pose age.
The tests include real loopback sockets with synthetic valid and malformed peers.

```powershell
.\build-test.ps1 -JavaHome 'C:\Program Files\Java\jdk-24'
& 'C:\Program Files\Java\jdk-24\bin\java.exe' -cp build/classes dev.minecome.protocol.CodecCli ../../config/bridge.token 5
```

The CLI connects exclusively to 127.0.0.1:38765, authenticates as role HARNESS,
sends synthetic poses and one stone block event, receives native host poses and
heartbeats, and fails if it receives no host pose. This proves cross-language IPC
when run with a real native harness; it does not prove game hooks.
Use `-Dminecome.port=38770` before `-cp` to isolate protocol testing on a separate
localhost port. Port values must be 1..65535; the host remains hard-coded loopback.

Coordinate helpers use an explicitly unverified KCD basis hypothesis:
`MC=(KCD.x-origin.x, KCD.z-origin.z, -(KCD.y-origin.y))*blocksPerUnit`.
The inverse is implemented and round-trip tested. Engine measurements and calibration
are required before setting the CALIBRATED flag in a live plugin.
Orientation helpers keep the camera-local basis +X right/+Y up/-Z forward and
left-multiply the camera-to-world quaternion by the same world-basis rotation
`Rx(-90°)` for KCD→MC, or `Rx(+90°)` for MC→KCD. They do not conjugate the
quaternion, since the local camera basis stays fixed. The KCD native adapter must
first express its engine camera basis in this canonical local-camera convention.
