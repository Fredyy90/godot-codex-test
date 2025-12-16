# OpenSeeFace VTuber PoC (Godot 4)

Minimal 2D VTuber avatar driven by [OpenSeeFace](https://github.com/emilianavt/OpenSeeFace) tracking. The project renders with a transparent background for OBS (Game Capture preferred). A chroma-key fallback is available.

## Project layout
- `project.godot`: Godot 4 project settings (transparent clear color, main scene).
- `main.tscn`: Entry scene (Node2D) that instantiates the avatar, network receiver, and control panel.
- `scripts/`
  - `tracking_state.gd`: Lightweight data container for incoming tracking.
- `network_receiver.gd`: UDP listener for OpenSeeFace packets (JSON or raw byte array).
  - `avatar.gd`: Stick-figure renderer with eyes, mouth, and rotation.
  - `main.gd`: Scene wiring, smoothing, calibration, UI, and OBS toggles.

## Requirements
- Godot 4.x
- OpenSeeFace (tested with the default UDP JSON stream)
- OBS (for capture)

## Running OpenSeeFace
1. Clone the [OpenSeeFace](https://github.com/emilianavt/OpenSeeFace) repository and install its Python dependencies.
2. Start tracking with the built-in UDP sender (default port 11573). JSON output works, but the project also accepts the default byte-array stream:
   ```bash
   python run.py --tracker 0 --model 0 --detection_threshold 0.6 --output_format json --udp_host 127.0.0.1 --udp_port 11573
   ```
   Each frame contains a `faces` array (JSON) or a packed byte payload. The binary layout (little-endian) for each detected face is:
   - `timestamp` (f64), `id` (i32)
   - `frame_width`/`frame_height` (f32)
   - `eye_blink[0]`/`eye_blink[1]` (f32)
   - `success` (u8), `pnp_error` (f32)
   - `quaternion` (4 x f32), `euler` (3 x f32)
   - `translation` (3 x f32)
   - Landmark confidence for each point (70 x f32), then landmark coordinates as `(y, x)` pairs (70 x 2 x f32)
   The remaining 3D points and feature floats are ignored by the sample; the first face in the packet is used.
   For each face we map:
   - `translation` (x, y, z) → head position (x, -y in 2D)
   - `euler` (yaw, pitch, roll) → head roll (Z rotation)
   - `eye_blink` ([left, right]) → blink amount (0=open, 1=closed)
   - `mouth` or `mouth_open` → mouth open (0..1)
   - `landmarks`/`lm` (array of [x, y] pairs or flattened list) → debug overlay
   - `score` → confidence

If you start OpenSeeFace with OSC instead of JSON, adapt `network_receiver.gd` to parse the OSC bundle similarly (the current implementation expects JSON packets).

## Running the Godot scene
1. Open the project folder in Godot 4.x.
2. Run the scene (`main.tscn`). The control panel appears in the top-left.
3. Set IP/Port to match the OpenSeeFace sender and press **Start**.
4. Press **Calibrate neutral** while looking straight to store zero offsets.
5. Toggle **Debug landmarks** to see incoming landmark points. Toggle **Use green background** for chroma-key fallback.
6. Optional: press **Import character** to load a ready-made character scene (`.tscn/.scn/.res`) or texture (`.png/.jpg/.webp`). Use **Reset to stick figure** to go back to the built-in renderer.

### Smoothing and idle
- Position, rotation, and expressions are exponentially smoothed (`lerp` per frame).
- When no packets arrive for `idle_timeout` seconds (0.75s by default), the avatar switches to a light idle animation (head bob, relaxed blink cycle, gentle mouth breathing) so OBS still shows motion until tracking resumes. Idle starts immediately if the UDP socket fails to bind or tracking is stopped, keeping the avatar alive even when OpenSeeFace is unavailable.

### Avatar mapping
- Head: circle with Z rotation from `euler[2]` (roll). Translation uses X and -Y.
- Eyes: small ellipses; blink scales the vertical radius (`1 - eye_blink`).
- Mouth: two small lines whose vertical separation follows `mouth_open`.
- Body: stick figure anchored below the head.

## OBS setup
Primary (preferred):
1. Add **Game Capture** → capture the Godot window.
2. Ensure the project clear color stays transparent (default). In OBS, transparency should pass through automatically.

Fallback chroma-key:
1. Enable **Use green background** in the control panel.
2. In OBS, switch the source to **Window Capture** if Game Capture transparency fails.
3. Add a **Chroma Key** filter using pure green (0,255,0).

## Troubleshooting
- No movement? Check packet counter in the panel. Verify IP/Port and that OpenSeeFace is sending JSON.
- Drifting pose? Re-run **Calibrate neutral** while facing the camera.
- Landmark overlay looks mirrored? Flip in OBS or adjust `translation` sign in `network_receiver.gd` to match your camera setup.

## Technical notes
- **TrackingState** fields: `head_pos`, `head_rot`, `eye_blink_l/r`, `mouth_open`, `confidence`, `timestamp`, `packet_rate`, `landmarks`.
- **Smoothing**: `lerp` per frame with tunable alphas (`position_smooth`, `rotation_smooth`, `expression_smooth`). Idle fallback lerps rotation toward 0 using `neutral_gravity`.
- **Calibration**: Captures the current smoothed state and subtracts it from subsequent frames (position, rotation, blink, mouth).
- **Background**: Transparent by default; chroma green when toggled.
- **Custom characters**: The importer accepts Godot scenes (`PackedScene`) or textures. If your scene contains nodes named `Head`, `LeftEye`/`RightEye`, or `Mouth`, the importer will animate those nodes for rotation, blinking, and mouth-open. Otherwise the whole scene moves/rotates from the head transform only.
