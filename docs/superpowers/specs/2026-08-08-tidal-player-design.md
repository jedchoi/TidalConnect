# Tidal Connect Lite - System Design Spec

- **Date**: 2026-08-08
- **Topic**: Lightweight Tidal Player & DLNA Audio Renderer Controller for Android
- **Target Platform**: Android (Flutter)
- **Primary Goal**: Replace mconnect Player lite with a streamlined, zero-friction Tidal player that opens directly into "My Collection" (Favorites) and streams audio to local Wi-Fi UPnP/DLNA renderers (e.g., Chord Poly).

---

## 1. Executive Summary & Core Requirements

1. **Direct Access to Favorites (My Collection)**: Unlike mconnect Player lite which requires navigating through `Browser -> Tidal -> My Collection`, this app opens directly into user's Tidal Favorites upon launch.
2. **Persistent Auto-Login**: OAuth 2.0 Access/Refresh tokens are encrypted and saved using Android KeyStore (`EncryptedSharedPreferences`). Re-authentication is handled automatically on startup.
3. **Local DLNA/UPnP Speaker Discovery & Streaming**: Discover local audio renderers on local Wi-Fi via SSDP (`M-SEARCH`). Stream Tidal FLAC/AAC audio URLs directly to renderers like Chord Poly via UPnP `AVTransport` (`SetAVTransportURI`, `Play`, `Pause`, `Seek`).
4. **Hardware Volume Integration**: Intercept physical Android volume key presses and map them to UPnP `RenderingControl` (`SetVolume`) on the active DLNA speaker.

---

## 2. Technical Stack & Architecture

- **Framework**: Flutter 3.x (Dart 3.x)
- **State Management**: `flutter_riverpod`
- **Secure Storage**: `flutter_secure_storage` (Android `EncryptedSharedPreferences`)
- **Network & API**: `dio` / `http` for Tidal REST API
- **DLNA / UPnP Protocol**: Native Dart SSDP Client (UDP `239.255.255.250:1900`) & XML SOAP RPC Client for `AVTransport:1` and `RenderingControl:1`
- **Volume Interception**: `flutter_volume_controller`
- **Theme & Aesthetics**: Dark Elegant Tidal (`#121212` Charcoal Dark Background, `#1E1E2E` Surface Card, `#00FFFF` Tidal Cyan Accent, Outfit/Inter Typography)

```
+-------------------------------------------------------------------+
|                        Flutter UI Layer                           |
|  [Tab 1: 즐겨찾기]  [Tab 2: 추천]  [Tab 3: 검색]  [Tab 4: 설정]   |
|                 +---------------------------------+               |
|                 |  Mini Player & Output Selector  |               |
+-----------------+---------------------------------+---------------+
                                  |
                   State Management (Riverpod)
                                  |
        +-------------------------+-------------------------+
        |                                                   |
[Tidal Auth & API Service]                       [DLNA / UPnP Controller]
 - OAuth 2.0 PKCE / Device Auth                   - SSDP Discovery (M-SEARCH)
 - Token Auto-Refresh                             - AVTransport (SetURI, Play, Pause, Seek)
 - Secure Storage Persistence                     - RenderingControl (SetVolume)
        |                                                   |
        v                                                   v
   Tidal Cloud                                       Chord Poly / Speakers
 (REST Streaming API)                                (Local Wi-Fi Network)
```

---

## 3. Detailed UI / UX Specification

### 3.1 Bottom Navigation Bar (4 Tabs)
1. **Tab 1: My Collection (Default Home Screen)**
   - Top User Profile bar with quick account status.
   - Favorite Albums horizontal scroll grid.
   - Favorite Playlists list view (with cover artwork & track counts).
   - Favorite Tracks list (instant play on tap).
   - Favorite Artists avatars.
2. **Tab 2: Explore & Recent**
   - Recently played tracks & albums.
   - Tidal Daily Mixes and recommendation playlists.
3. **Tab 3: Search**
   - Debounced search bar.
   - Search results categorised into Tracks, Albums, Artists, Playlists chips.
4. **Tab 4: Settings**
   - Tidal Account info & re-authentication button.
   - Audio Streaming Quality selector (LOW, HIGH, LOSSLESS, HI_RES).
   - DLNA Renderer Discovery refresh & SSDP network timeout settings.

### 3.2 Playback Controller & Speaker Selector
- **Floating Mini Player**: Positioned directly above the Bottom Navigation Bar. Displays album thumbnail, track title, artist name, play/pause toggle, and active speaker icon.
- **Now Playing Full-Screen View**:
  - Full-screen view with high-res album artwork.
  - Quality badge (e.g. `FLAC 16-bit 44.1kHz` / `HI-RES`).
  - Seekbar, playback controls (Previous, Play/Pause, Next, Shuffle/Repeat).
  - Top-right Speaker Selector button opening a bottom sheet modal listing all discovered DLNA renderers (e.g. `Chord Poly`, `Phone Speaker`).
- **Hardware Volume Sync**:
  - Physical Volume Up/Down buttons trigger `SetVolume(volume_level)` over UPnP `RenderingControl` on the active Chord Poly renderer, displaying a volume feedback toast on screen.

---

## 4. Authentication & Data Persistence Flow

```
App Launch
  │
  ▼
Read EncryptedSharedPreferences (flutter_secure_storage)
  │
  ├── [1] Token Valid ─────────────────────────────────┐
  ├── [2] Token Expired ──► Refresh Token via API ─────┤
  │                                                    ▼
  └── [3] No Token ──► Show Tidal OAuth Login Screen  Open Tab 1 (My Collection)
```

---

## 5. Verification & Testing Strategy

1. **Unit Testing**:
   - Token storage & auto-refresh logic.
   - Tidal API JSON parsing for albums, playlists, tracks.
   - UPnP SOAP XML payload generator (`AVTransport` & `RenderingControl`).
2. **Integration / Manual Testing**:
   - SSDP M-SEARCH discovery on local Wi-Fi with Android Multicast Lock enabled.
   - Verification of audio playback on Chord Poly DLNA renderer.
   - Physical volume button interception test on Android device.
