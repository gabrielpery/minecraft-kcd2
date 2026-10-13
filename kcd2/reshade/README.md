# MineCome's bounded DirectInput mouse capture

`mouse-capture.patch` is an original patch against ReShade commit
`18deaa52de0c425a78b329e9cb3c497281cd00ec` (6.8.0). Apply it only to a
separate pinned build checkout. Copy these original headers into its
`source/windows/` directory:

- `kcd2/hud/mouse_capture_api.hpp`
- `kcd2/hud/mouse_capture_policy.hpp`
- `kcd2/reshade/mouse_capture_adapter.hpp`

The patch extends the existing ReShade A/W DirectInput8 hook chain, including
its dynamically resolved original-call mechanism. It changes no engine code,
SDK source, project configuration, original executable, or installed proxy.
`MineComeGetMouseCaptureApi(1, sizeof(minecome::mouse::Api))` exports the v1
function table. The add-on must check its own exact executable and proxy build
compatibility before using it.

The SDK `IDirectInputDevice8A/W` declarations in Windows SDK `dinput.h` define
the hook slots: QueryInterface0, Release2, GetProperty5, SetProperty6,
GetDeviceState9, GetDeviceData10, SetDataFormat11, SetCooperativeLevel13,
Initialize17, SetActionMap30. The adapter uses actual SDK `DIMOUSESTATE`,
`DIMOUSESTATE2`, `DIDEVICEOBJECTDATA`, and property constants. The tests check
the real SDK `c_dfDIMouse` and `c_dfDIMouse2` descriptors.

Ownership requires every observed mouse to have the exact target HWND,
recognized relative layout, successful hook installation, and actual relative
`DIPROP_AXISMODE` readback. An unknown device, another mouse HWND, unknown
layout, absolute mode, action map, foreign COM interface alias, or exhausted
16-device registry rejects capability. The factory uses public `GetDeviceInfo`
to identify enumerated mouse GUIDs. Failed unknown-device classification also
rejects capture. Those conservative faults require a new process; the adapter
does not assume a different interface shares a valid interception path.

The process-owned, visible foreground HWND and nonzero token bind a maximum
100ms lease measured internally with `GetTickCount64`. Renewal preserves the
generation; a new lease, revocation, or observed configuration change advances
it. Render-thread API calls only try the fixed-state lock. Contention reports
busy with no active flag and schedules revocation; they never wait or call COM.
The add-on must stop forwarding when any call fails or generation changes.

While owned, successful immediate polls return zero axes, wheel, and buttons.
Successful buffered polls report zero events, including `DIGDD_PEEK`. The
original HRESULT is preserved, especially every failed HRESULT. Original
immediate and non-PEEK buffered reads drain both accumulated relative axes and
queued events on the device's callback thread. `DIERR_NOTBUFFERED` means no
buffered queue exists; other drain failures revoke capability and remain
visible in the snapshot counters/reason.

Release or expiry marks a final drain pending. The next successful device poll
discards its first sample and drains both sources before ordinary input resumes.
No COM pointer is called from the render thread. An old in-flight callback
cannot clear a drain belonging to a newer generation. If a configuration change
loses relative-layout knowledge, the adapter does not zero an unknown or absolute
state and cannot claim that cleanup has completed.

This controls the observed DirectInput8 mouse path. It does not establish that
an arbitrary game's other input routes are intercepted. Host validation and a
bounded physical test remain necessary; stock ReShade message/raw-input blocking
and the add-on's inventory/cursor checks remain separate requirements.
