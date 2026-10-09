This fixture loads copied repository QML in a PySide6 Qt Quick window using the offscreen software renderer. It checks visible and unmapped palette reloads, pixel changes on retained canvases, and theme rounding, retained page identities, and narrow-window tab hit targets and scrolling. Weather, media, CPU, GPU and network values are synthetic; fixture clocks are pinned to 2026-10-03 18:30 UTC. FileView.reload completes on the next event loop turn. Normal-window tab/open frame times are recorded for information and have no timing thresholds. Process never executes commands, FileView reads only inside a newly created temporary fixture root, and Quickshell detached execution raises. It does not test Wayland popup grabs or real sensors.

Run `python tests/dashboard-render.test.py --output-dir /tmp/dashboard-artifacts` with PySide6 installed. Optional `--font-dir` loads JetBrainsMono Nerd Font.

Weather picker checks exercise Enter, clicking a non-first suggestion, saving,
retained-input focus, and Escape through the actual dashboard handlers. Writes
complete in memory. `python tests/weather-city-picker.test.py` separately uses
real offscreen Quickshell IO in temporary XDG directories, with a fixture curl,
to check boot precedence, delayed loads, snapshot saves and failed-write retries.
