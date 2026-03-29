#!/bin/bash
# ============================================================
# [A] APEX PHOENIX — PSOBB Performance Sentinel for Linux/Wine
# Architecture: Three-Tier Sentinel + Goliath In-Memory SM + ALU-Topology
# Telemetry: /proc/PID/task/TID/schedstat ctx-switch delta (30s)
# Author: Jangis
# [A0] ── VERSION ─────────────────────────────────────────────
# Version: apxp_v4.7.3
# APXP_VERSION constant: see [B1] — single source, both contact points must match
# ─────────────────────────────────────────────────────────────
#
# Primer:   apex_primer.md
# Mental Models - GEARS_v2.6.md
# Changelog: CHANGELOG.md  ← full history; inline [vN.n:ID] tags cross-ref
#
# HARDWARE: auto-detected at runtime by init_tp and hw_init
#   Topology: 4T/8T/12T/16T classified from /sys core_id files (D1-D8)
#   GPU:      Intel: gt_max_freq_mhz; AMD/Steam Deck: pp_dpm_sclk → performance level high [v4.7]
#   RAPL:     PL1/PL2 read from system at F1; battery = 50% of AC
#   CPU max:  cpuinfo_max_freq + scaling_max_freq cross-check at F5 [v4.7.1]
#   CLK_TCK:  getconf at A2
#   Display:  DISPLAY + XAUTHORITY discovered from user session at A3
#   MSR:      0x1A4 prefetch + 0x620 uncore — Intel only (vendor gate at F4)
#   Fan:      /proc/acpi/ibm/fan (ThinkPad) — graceful miss if absent
#   GRUB:     DISABLED — no boot changes made.
#
# TOPOLOGY (example 8T — init_tp sets actual values at runtime):
#   C0=WS C1=HEART+WSI_E+WSI_Q(RT-45)+DINPUT C2=MONSTER C3=MANAGER
#   C4=AUDIO(TI>MIX>MA RT hierarchy) C5=FEEDER+SUBMIT C6=RENDER(CS+Q) C7=MUD
#   FRAME=C1 default, shifts to C2 under DXVK_Q fence pressure
#   SHADERS: H→CORE_RENDER(NICE_DXVK_CS), L→CORE_RENDER(NICE_MUD_ENFORCE)
#   4T/12T/16T: see D6 topology branches
#
# WINE: Wine-GE GE-Proton8-26 preferred (GnuTLS TLS1.3, FAudio, launcher splash fix)
#   Path: ~/.local/share/lutris/runners/wine/lutris-GE-Proton8-26-x86_64/bin/wine
#   Falls back to system Wine if declined; WINESERVER_BIN tracks active server binary
#   Game path: configurable at S2 setup prompt (default ~/EphineaPSO)
#
# TELEMETRY: /proc schedstat ctx-switches (30s delta)
#   IDLE<50 PULSING<1500 ACTIVE<8000 COMBAT<25000 CARNAGE>25000
#
# GOLIATH: ARM(tick-sort top-2) → EVALUATE(I19:heart-rate · I20:ambiguity · I21:CPU%-range) → CONFIRM
# ==============================================================================
#
# POINTER MAP  (regen: grep -n "^# \[[A-Z][0-9]*\]" % )
#  [A]   HEADER & BOOTSTRAP
#  [A0]  VERSION anchor — contact point 1 of 2 (contact point 2 = [B1a])
#  [A1]  Bootstrap environment and sudo validation
#  [A2]  Runtime system constants — CLK_TCK from getconf [v4.5.1]
#  [A3]  Display session discovery — DISPLAY_ID + XAUTH_PATH from live session [v4.5.3]
#  [B]   GLOBALS & CONFIGURATION
#  [B1]  PIDs, TIDs, path caches (TASK_BASE, MON/HEART/Q_SCHED_PATH) [v4.1.1]
#  [B1a] VERSION constant — contact point 2 of 2; must match [A0]
#  [B2]  Thread pool arrays; TC_ caches; _TASK_DIRS shared path list [v4.0.21]
#  [B3]  Sentinel/telemetry counters; B4: pipeline event trackers
#  [B5]  Logging, paths, Wine debug level; GAME_DIR + WINE_PREFIX configurable [v4.5.1/v4.5.4]; B6: RAM log buffer
#  [B7]  Burst sampler + benchmark state; B8: CPU/GPU freq variables
#  [B9]  HW sysfs paths + thermal nodes; B10: emergency revert + fan globals (MSR Intel gate [v4.5.1])
#  [B11] Capability flags — HAS_FREQ_NODE/HAS_GPU_NODE [v4.4.4]; HW_CPU_COUNT [v4.5.3]; HAS_RAPL_WRITABLE [v4.7]
#  [B11b] Platform identity — IS_STEAMOS + CPU_VENDOR globals detected once at boot [v4.7]
#  [B12] Binaries; B12b: XAUTH_PATH+DISPLAY_ID from session discovery [v4.5.3]
#  [B13] Operation counters, BROWSER/BRIDGE_PIDS cache [v4.1.0]; Silk vars removed [v4.4.3]
#  [B15] Thermal probes; B16: Goliath SM; B17: scratch
#  [B18] Core assignments (CORE_BROWSER=FEEDER+MUD v4.0.12; FEEDER/RENDER defaults corrected [v4.5.0])
#  [B19] Nice levels — game threads; B20: background + bridge
#  [B21] Thresholds — THM_THR=63°C (hwmon corrected v4.3.2); GOL_HEART_RDY=600 [v4.4.7]
#  [B22] Timing constants (DEFERRED:RT-02/03/TIM-01/03); B23: RAPL limits (dynamic [v4.5.1]); RAPL_PATH [v4.6]; HAS_RAPL_WRITABLE [v4.7]
#  [B24] Sched tunables + burst timing (DEFERRED:TIM-02); B25: pgrep
#  [B26] Restore snapshots — R_SMP_AFF/R_ASPM_POLICY/R_COMPACTION now snapshotted [v4.4.3]
#  [B27] DXVK runtime + quarantine init
#  [C]   PRIMITIVE HELPERS
#  [C1]  t_echo; C2: lg/flush_logs; C3: r_csw (vol/nonvol split needed)
#  [C3b] r_sw — schedstat 1-line total-switch; hot-path r_csw replacement
#  [C4]  sw (sysfs swap); C5: c_renice/c_tset (TC_NICE/CORE gated); C6: c_chrt
#  [C7]  inv_tc (clears TC_*/EPP cache, refreshes BROWSER+BRIDGE) / inv_critical  [v4.1.1]
#  [C8]  log_init (session CSV header); C9: set_pr stub (absorbed into pin_th v4.4.9)
#  [C10] cage_external — PID + all TIDs, multithreaded-safe
#  [C12] cleanup trap entry; C13: data integrity + RAM flush
#  [C14] SW priority + MSR release; C14b: RAPL restore fallback
#  [C15] C-state re-enable + freq_unlock + turbo restore (R_NO_TURBO)
#  [C16] Fan restore; C17: IRQ (R_SMP_AFF now restored); C18: VM/THP/sched/ASPM/compaction
#  [C18b] OS liberation (cpu-count-aware affinity restore [v4.5.3]); C20: keymap restore
#  [D]   HARDWARE FUNCTIONS
#  [D1]  init_tp — CPU topology classifier: 4T/8T/12T/16T [v4.5.2] (D2→D8 internal)
#  [D9]  set_turbo — Intel no_turbo + AMD boost node support [v4.5.3]
#  [D10b] freq_lock — scaling_max_freq write; D11: EPP gate; D12: pstate pct
#  [D12b] set_turbo 1 — turbo disable in freq_lock for telemetry consistency
#  [D13] freq_unlock entry; D13b: scaling_max_freq release; EPP→balance_perf
#  [E]   PRE-FLIGHT CAPABILITY CHECK
#  [E1]  pf() entry; E2: binaries; E2b: ALSA i386 (apt-only) [v4.5.3]; E3: PM-detect install [v4.5.3]; E3c: post-install rescan + hard abort [v4.5.3]
#  [E4]  X11 focus; E5: cpupower/msr-tools cache
#  [E6]  Wine-GE detect→install→fallback (E6b: download); E7: RAPL probe Intel+AMD [v4.5.3]
#  [E8]  RT throttle 5% limit; E9: debugfs + fan (DMI-gated [v4.5.3]) + turbo Intel+AMD [v4.5.3]
#  [E10] REMOVED Silk Mode prompt; E11: ev_tier (PID + TID affinity utility)
#  [E12] topology portability complete [v4.5.2]; E13: [DEFERRED:PORT-03/04] fan/GPU portability
#  [F]   STAGE 0A: HW HARNESS & IRQ SCALPEL
#  [F5]  hw_init entry — HW_MAX_MHZ from cpuinfo_max_freq [v4.5.1]; freq node + sysfs pre-expand
#  [F1]  RAPL limits read dynamically from system [v4.5.1]; F2: IRQ bitmasks + DMA lock
#  [F3]  GPU lock — Intel gt_max_freq + AMD pp_dpm_sclk/amdgpu fallback [v4.7]; F4: MSR Intel-only via CPU_VENDOR global [v4.7]
#  [G]   STAGE 0B: OS EVICTION & TIERING
#  [G1]  FS 60s commit; G2: VM/THP/IRQ/ASPM/compaction snapshot [v4.4.3]; G3: high-throughput VM strategy
#  [G4]  Service eviction; G5: REMOVED Silk Mode; G6: caging
#  [G7]  Browser + bridge isolation; cache BROWSER/BRIDGE_PIDS at boot [v4.1.0]
#  [H]   FAST-TIER FUNCTIONS
#  [H1]  check_ac — poll + state change; H2: battery release; H3: AC re-engage
#  [H4]  mng_thm — thermal monitor + fan SM; H4b: GAME-only purge gate [v4.0.4]
#  [H5]  Thermal purge + restore; H6: hotkey handler (F/G/T/P/L/R/B/U/I/C/H); P suspends TEL_EN  [v4.4.2]
#  [I]   GOLIATH & THREAD CLASSIFICATION
#  [I1]  t_cls — O(1) TC_CLASS hash lookup; fallback FEEDER/MUD [v4.0.18]
#  [I4]  cls_th entry; I5: PSOBB_PID + TASK_BASE/path caches [v4.1.1]
#  [I6]  Pass 1 gate; I7: COMM scan + TC_CORE evict on shader first-set [v4.4.9]
#  [I7b] AUDIO_ID closest-exec fallback if MA unclassified [v4.0.4]
#  [I8]  Pass 2 Goliath — I9: candidates; I10: arm; I11: eval (I19/I20/I21)
#  [I12] Confirm + t_echo + MON_SCHED_PATH [v4.4.9]; I13: CLAIMED+TC_CLASS+_TASK_DIRS
#  [J]   MEDIUM-TIER FUNCTIONS (pin_th)
#  [J5]  pin_th — TC_CLASS dispatch (O1 v4.4.9); _TASK_DIRS reuse [v4.0.21]
#  [J6]  HEART; J7: Render pipeline (case dispatch); J8: WSI RT-45 [v4.0.11]
#  [J9]  Audio TI>MIX>MA RT; J10: DINPUT+MON+MGR direct BIN_TSET bypass [v4.5.0]; J11: MUD+BATCH
#  [K]   TELEMETRY
#  [K1]  tel_start — r_sw baselines; MUD stat skip; _TASK_DIRS reuse [v4.1.1]
#  [K2]  per-thread r_sw snapshot + CPU baseline; K3: MON/Q schedstat health baselines
#  [K4]  tel_end entry; K5: elapsed init; K6: /proc stat + t_cls inlined [v4.4.4]
#  [K7]  Combat burst trigger; K8: DXVK_Q fence-ratio via Q_SCHED_PATH [v4.1.1]
#  [K9]  MUD aggregation; K10: status classify; K11: CSV row format
#  [K12] Swap detector (MGR/MON inversion); K13: print_health MONSTER/HEART
#  [L]   TRIGGERED / INTERACTIVE FUNCTIONS
#  [L1]  burst_sample (L2: paths; L3: baseline+loop; L4: dead TID detect)
#  [L5]  Artifact cap + CSV; L6: benchmark (L9: monitor; L10: delta report)
#  [M]   BOOTSTRAP SEQUENCE
#  [M1]  Entry + CPU model banner from /proc/cpuinfo [v4.5.1]; M1b: AC check; M2: pre-flight warnings
#  [S]   SETUP WIZARD (stateless) — runs between M2 and M3 if install not detected [v4.5.4]
#  [S0]  Wine prefix path prompt; S1: wineboot --init + multi-distro Wine hint [v4.7]; S2: zip-first install + wipe safeguard [v4.7.2]; S3: DXVK d3d8+d3d9 both verified [v4.7.2]; S4: dxvk.conf; S5: test launch marker [v4.7.1]
#  [M3]  Thermal guard + Wine debug + CSV + Frequency Forger + post-M3 game path safety net [v4.5.4]
#  [M3b] Keymap: F10→F1 (guide), F1→F12, F11 disabled; C20 restores on exit
#  [M4]  Wine env + PSOBB launch; M4a: regedit DISPLAY+XAUTH [v4.7]; M4b: log rotate; M4c: XDG fallback+PULSE+PW_QUANTUM; INTEL_DEBUG/MESA conditional [v4.7]
#  [M5]  Engine wait loop; M6: settle delay; M7: initial cls_th/set_pr/pin_th
#  [N]   SENTINEL LOOP (Core Engine)
#  [N1]  TICK_CTR + outer while; N2: tel_start; N3: churn (no glob) [v4.0.20]
#  [N4]  Inner loop (15 × 2s = 30s window)
#  [N5]  AC poll every 4 ticks; N6: inv_tc + WSRV_PIDS gated G_VLD=0 [v4.1.0]
#  [N7]  Focus poll %7 ticks; FOCUS_PENDING removed (was always-true) [v4.4.4]
#  [N8]  GAME — cage browser+bridge from cache (pgrep fork removed) [v4.4.4]; freq_lock
#  [N9]  DESKTOP — liberate browser, backgrounded; freq_unlock
#  [N11] Exit gates — N11: /proc dir; N12: comm mismatch gated 5 ticks [v4.0.20]
#  [N13] mng_thm (gated THM_GUARD_EN) [v4.4.5]; N14: clock read (HAS_FREQ_NODE) [v4.4.4]; N15: MT_DUE
#  [N16] MT_DUE exec — N17: cls(stderr only suppressed)/set_pr/pin [v4.4.11]; N18-N20: hitch delta+ring+alert (cold skip) [v4.4.8]
#  [N21] HUD — N22: GPU read (HAS_GPU_NODE flag, %7) [v4.4.4]; N23: print; N24: keypress; N25: tel_end
#  [N26] Combat burst; N27: periodic burst
# ============================================================

# [A1] --- BOOTSTRAP ENVIRONMENT ---
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run with sudo."
    exit 1
fi

if [[ -z "$SUDO_USER" ]]; then
    echo "[!] Must be run via sudo. Exiting."
    exit 1
fi
USER_HOME="/home/${SUDO_USER}"

# [B] --- GLOBALS ---                                                          

# [B1] Process and thread identifier globals
# [B1a] ── VERSION ── contact point 2 of 2 — must match [A0] header  ──────────
declare -g -r APXP_VERSION="apxp_v4.7.2"
# ─────────────────────────────────────────────────────────────────────────────
declare -g PSOBB_PID="" HEART_ID="" MON_ID="" MGR_ID="" SUBMIT_ID="" CS_ID="" Q_ID="" FRAME_ID="" \
           DINPUT_ID="" SHADER_H_ID="" SHADER_L_ID="" AUDIO_ID="" AUDIO_TI_ID="" AUDIO_MIX_ID="" \
           WSI_Q_ID="" WSI_E_ID="" WSRV_PIDS="" THREAD_CLASS="" _exit_comm=""
# Pre-built path caches — set when IDs confirm, invalidated on inv_tc  [v4.1.1]
declare -g TASK_BASE=""          # /proc/$PSOBB_PID/task — eliminates 32 inline constructions
declare -g MON_SCHED_PATH=""     # $TASK_BASE/$MON_ID/schedstat
declare -g HEART_SCHED_PATH=""   # $TASK_BASE/$HEART_ID/schedstat
declare -g Q_SCHED_PATH=""       # $TASK_BASE/$Q_ID/schedstat

# [B2] Thread pool and association arrays
declare -g -a MUD_IDS=() FEEDER_IDS=() MT_RING=() _cur_tid_glob=() _TASK_DIRS=()
declare -g -A FEEDER_SET=() MF_SW=() MF_HITS=() CLAIMED=() TC_CORE=() TC_NICE=() TC_SCHED=() TC_CLASS=()  # TC_CLASS drives pin_th dispatch [v4.4.9]

# [B3] Sentinel status and telemetry counters
declare -g -i G_VLD=0 TICK_CTR=0 MT_DUE=0 LAST_TID_COUNT=0 CUR_TID_COUNT=0 FORCE_MEDIUM=0 \
              MON_WAIT_NS=0 MT_HITCH_US=0 mt_w0=0 mt_w1=0 w_us=0 mt_us=0 MT_RING_POS=0 \
              MT_COLD_SKIP=1  # [v4.4.8] suppress first MT cycle from ring+alert — cold cls_th hitch is ~2.5s noise

# [B4] Pipeline and window event trackers
declare -g -i DQ_CTR=0 DQ_FENCE=0 DQ_EXEC_LAST=0 DQ_WAIT_LAST=0 SWAP_CTR=0 \
              FEEDER_LAST_TS=0 TEL_WINDOW=0 TEL_EN=1  # [v3.9.7:M4]
declare -g -A T_START_SW=() T_START_CPU=()
declare -g -i T_START_TS=0 _PTH_MON_BASE_E=0 _PTH_MON_BASE_W=0 _PTH_DQ_BASE_E=0 _PTH_DQ_BASE_W=0

# [B5] Logging and directory path configurations
declare -g PLAYER_CLASS="Ramar" SES_LOG="" SES_CSV="" SES_TS="" LOG_DIR="${USER_HOME}/.apxp" LOG_EN=1
declare -g WINE_DEBUG_LEVEL="+err,+warn"  # [v3.9.4] user-selectable at boot
declare -g WINE_LOG=""                    # [v3.9.5] set at M3 — game dir, near exe
declare -g GAME_DIR="${USER_HOME}/EphineaPSO"  # [v4.5.4] resolved by [S2] setup wizard
declare -g WINE_PREFIX="${USER_HOME}/.wine"    # [v4.5.4] configurable at S0 prompt — never hardcode ~/.wine

# [B6] No-disk policy RAM log buffering
declare -g -a LOG_BUFFER=()
declare -g -i LOG_BUFFER_LIMIT=100

# [B7] Burst sampler and benchmark state
declare -g -i BURST_ID=0 BURST_ARMED=0 BURST_LAST_WINDOW=0
declare -g BURST_CSV=""

# [B8] Target CPU and GPU frequency variables
declare -g -i GAME_MHZ=2600 DSK_MHZ=3400 TARGET_MHZ=2600 \
              GPU_LOCK_MHZ=1300 GPU_GAME_MHZ=1300

# [B9] Hardware system paths and thermal node null-guards
declare -g CPU_FREQ_NODE="/dev/null"
declare -g GPU_CUR_NODE="/dev/null"
declare -g GPU_MAX_NODE="/dev/null"
declare -g GPU_MIN_NODE="/dev/null"
declare -g THM_PATH="" CPU_TEMP="--" CPU_LIVE_MHZ="---" GPU_CUR_MHZ="---"  # [v3.9.9:F1] GPU_DISPLAY_MHZ retired

# [B10] Emergency Revert function and fan status globals  [v3.8.0:L2]
apxp_revert() {
    modprobe msr >/dev/null 2>&1
    [[ "$CPU_VENDOR" == "GenuineIntel" ]] && wrmsr -a 0x620 0x800
    cpupower frequency-set -g powersave; systemctl start irqbalance
}
declare -g -i FAN_IS_LOCKED=0 FAN_TIMER=0 FAN_START_TS=0

# [B11] Hardware capability and system state flags
declare -g -i HAS_FAN_NODE=0 HAS_DMA_LATENCY=0 HAS_CPWR=0 HAS_WRMSR=0 HAS_WINE=0 \
              HAS_GAME_EXE=0 HAS_DXVK_CONF=0 HAS_RAPL_NODE=0 HAS_SCHED_DEBUG=0 HAS_PSTATE=0 \
              HAS_XDOTOOL=0 HAS_WMCTRL=0 HAS_RT_THROTTLE=0 HAS_TURBO_CTRL=0 \
              HAS_FREQ_NODE=0 HAS_GPU_NODE=0  # [v4.4.4] boot-time flags eliminate per-tick -f guards
declare -g -i THM_GUARD_EN=1  # [v4.4.5] thermal guard toggle — set at M3; 0 skips mng_thm entirely
declare -g -i HW_MAX_MHZ=4200 HW_CPU_COUNT=8 HOT_SWAP=0 DEPS_CHECKED=0 HW_INIT_TS=0  # HW_CPU_COUNT set by init_tp [v4.5.3]
# CLK_TCK: read from system at A1 below — getconf CLK_TCK (100 on standard kernels, never hardcode)  [v4.5.1]
declare -g -i CLK_TCK=100

# [B11b] Platform identity — detected once at global scope, used by E/F/M guards  [v4.7]
declare -g CPU_VENDOR=""   # GenuineIntel / AuthenticAMD — set here, used by F4/MSR/M4
declare -g -i IS_STEAMOS=0 # 1 on SteamOS/Steam Deck — gates steamos-readonly + pkg skips
CPU_VENDOR=$(grep -m1 "^vendor_id" /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}' | tr -d '[:space:]')
[[ -f /etc/os-release ]] && grep -qi "steamos\|holo" /etc/os-release 2>/dev/null && IS_STEAMOS=1
[[ "$CPU_VENDOR" == "GenuineIntel" || "$CPU_VENDOR" == "AuthenticAMD" ]] || CPU_VENDOR="unknown"

# [B12] Binary path and focus state globals
declare -g WINE_BIN="" BIN_CPWR="" BIN_WRMSR="" BIN_RDMSR="" BIN_TSET="" BIN_RENICE="" BIN_CHRT="" \
           SYS_STATE="GAME" LAST_AC_STATUS="" AC_NODE="" LOCK_PID=""
# [B12b] Cached constants — built once at hw_init/bootstrap, never recomputed  [v4.1.1]
declare -g XAUTH_PATH=""        # discovered from user session at A3 [v4.5.3]; fallback ~/.Xauthority
declare -g DISPLAY_ID=""        # discovered from user session at A3 [v4.5.3]; fallback :0
declare -g -i GAME_PCT=0 DSK_PCT=0  # pre-computed pstate pct for freq_lock/unlock
declare -g _EPP_STATE=""        # tracks current EPP value — skips redundant sysfs writes
declare -g -a _SF_MAX_FREQ=()   # pre-expanded scaling_max_freq paths (cpu0-cpu7)
declare -g -a _SF_EPP=()        # pre-expanded energy_performance_preference paths

# [B13] Operation counters and browser PID cache
declare -g -i APPLIED_COUNT=0 SKIPPED_COUNT=0
declare -g BROWSER_PIDS=""  # [v3.9.8:H3] cached at boot in G7; refreshed on inv_tc
declare -g BRIDGE_PIDS=""   # [v4.1.0] cached at boot in G7; refreshed on inv_tc — eliminates N8 pgrep fork

# [B15] Thermal zone and CPU max probes
# Primary: thinkpad-isa hwmon temp1 (CPU die) — matches btop/sensors, matches fan controller
# Fallback 1: x86_pkg_temp thermal zone (broken on this hw — returns -273°C, kept for portability)
# Fallback 2: first hwmon temp1 found
for _hwmon_name in /sys/class/hwmon/hwmon*/name; do
    [[ -f "$_hwmon_name" ]] || continue
    read -r _hwmon_val < "$_hwmon_name" 2>/dev/null
    if [[ "$_hwmon_val" == "thinkpad" ]]; then
        THM_PATH="${_hwmon_name/name/temp1_input}"
        break
    fi
done
unset _hwmon_name _hwmon_val
if [[ -z "$THM_PATH" ]]; then
    for _tz_type in /sys/class/thermal/thermal_zone*/type; do
        [[ -f "$_tz_type" ]] || continue
        read -r _tz_val < "$_tz_type" 2>/dev/null
        if [[ "$_tz_val" == "x86_pkg_temp" ]]; then
            THM_PATH="${_tz_type/type/temp}"
            break
        fi
    done
    unset _tz_type _tz_val
fi
[[ -z "$THM_PATH" ]] && THM_PATH=$(find /sys/class/hwmon/hwmon*/ -name "temp1_input" 2>/dev/null | head -n 1)

# [B16] Goliath in-memory state machine variables
declare -g -i G_STATE=0 G_T0_HEART=0 G_T0_A_EXEC=0 G_T0_B_EXEC=0 G_T0_A_UTIME=0 G_T0_B_UTIME=0 G_T0_TS=0 PHASE_E_PCT=0
declare -g G_CAND_A="" G_CAND_B=""

# [B17] Shared scratch pads
declare -g -i _READ_VOL=0 _READ_NONVOL=0
declare -g _TS=""

# [B18] Core assignments and role mappings
declare -g -i CORE_WSRV=0 CORE_HEART=1 CORE_MON=2 CORE_MGR=3 CORE_AUDIO=4 \
              CORE_FEEDER=5 CORE_RENDER=6 CORE_MUD=7 CORE_FRAME=1  # [v4.5.0] FEEDER/RENDER defaults corrected to match topology
declare -g CORE_DISCORD="4,7"  # placeholder; init_tp rebuilds to CORE_AUDIO,CORE_MUD
declare -g CORE_BROWSER="5,7"  # FEEDER+MUD (P1-sib + P3-sib) — keeps browser off P3, MGR uncontested  [v4.0.12]

# [B19] Nice levels for game threads
declare -g -ir NICE_CRIT=-15 NICE_DXVK_CS=-16 NICE_WSRV=-20 NICE_AUDIO=-10

# [B20] Nice levels for background and bridge
declare -g -ir NICE_FEEDER=-5 NICE_MUD_ENFORCE=5 NICE_MUD_APPLY=19 \
               NICE_CHAFF=10 NICE_BRIDGE=5 NICE_VIP=-10

# [B21] Thermal and rate detection thresholds
declare -g -ir THM_THR=63           # [v4.3.2] restored to 63°C — hwmon corrected; prior 70°C was compensating for bad x86_pkg_temp sensor (+7°C offset)
declare -g -ir FEEDER_RATE_THRESH=500 FEEDER_CONFIRM_CYCLES=3
declare -g -ir GOL_HEART_RDY=600    # [v4.4.7] lowered 1000→600; lobby observed 808/s in v4.4.6 test — I19 was rejecting valid confirmation all lobby; 600 clears load screen noise (~0/s) while capturing lobby navigation
declare -g -ir MON_CPU_FLOOR=10 MON_CPU_CEIL=90

# [B22] Settle delay and timing constants
declare -g -ir SETTLE_DELAY_FRESH=12 SETTLE_DELAY_HOTSWAP=2 \
               MT_RING_SIZE=10 MT_HITCH_THR_US=3000 GAME_LAUNCH_TIMEOUT_S=180
declare -g -ir FAST_TIER_TICK_S=2   # [DEFERRED:TIM-01] try 1s; doubles sysfs read rate
declare -g -ir MT_INTV=3            # [DEFERRED:RT-02] try 2 (4s); validate via MT_RING hitch delta
declare -g -ir DXVK_Q_FENCE_THR=4 DXVK_Q_FENCE_CONFIRM=2  # [DEFERRED:RT-03] revisit with burst CSV fence-ratio data
declare -g -ir INV_TC_INTV=225      # [v3.8.2:M1] [DEFERRED:TIM-03] validate ~7.5min doesn't mask topology drift

# [B23] RAPL power limit microwatt constraints — set dynamically from system at hw_init [v4.5.1]
# Defaults are conservative fallback values; hw_init overwrites from actual system RAPL node.
# Battery limits default to 50% of game limits as a safe throttle for any TDP class.
# RAPL_PATH: set at E7 from detected node (intel-rapl:0 or amd_energy) — used by F1/H2/C14b  [v4.6]
declare -g RAPL_PATH=""
# HAS_RAPL_WRITABLE: 1 only if constraint files exist AND are writable (intel-rapl only)  [v4.7]
# amd_energy node sets HAS_RAPL_NODE=1 but HAS_RAPL_WRITABLE=0 — no constraint_ files
declare -g -i HAS_RAPL_WRITABLE=0
declare -g -i RAPL_PL1_UW=35000000 RAPL_PL2_UW=64000000 \
              RAPL_RESTORE_PL1=35000000 RAPL_RESTORE_PL2=64000000 \
              RAPL_BATTERY_PL1_UW=15000000 RAPL_BATTERY_PL2_UW=25000000

# [B24] Kernel scheduler and VM tunables
declare -g -ir SCHED_BASE_SLICE_NS=500000 SCHED_MIGRATION_COST_NS=5000000
declare -g -ir BURST_MGR_ARM_THRESH=4000 PERIODIC_BURST_INTV=3  # [v3.8.0:L3]
declare -g -ir BURST_SAMPLES=31     # [DEFERRED:TIM-02] 144Hz: use 0.007s sleep, recalc samples for 500ms window
declare -g -r  BURST_SLEEP_S="0.016" FAN_CTRL_EN=0  # [DEFERRED:TIM-02]

# [B25] OS eviction pgrep search patterns  [v4.5.3: multi-DE]
# PGREP_CHAFF: low-priority background daemons + common editors/terminals across DEs
declare -g -r PGREP_CHAFF="udisks|gnome-keyring|applet|fusermount|haveged|cron|smartd|rsyslogd|ModemManager|gvfs|goa-|colord|xed|gnome-terminal|konsole|kate|dolphin|gnome-text-editor|gedit|mousepad|thunar"

# PGREP_BRIDGE: compositor/WM processes that need CPU budget for smooth display,
# and Firefox sub-processes that are real work but lower priority than the game.
# Additive across DEs — pgrep returns zero matches for absent processes, no harm.
#   Cinnamon:  muffin (WM), nemo (file mgr)
#   KDE:       kwin_x11, kwin_wayland, kded5, kglobalaccel5
#   GNOME:     mutter, nautilus
#   XFCE:      xfwm4, thunar (also in CHAFF)
#   Firefox:   RDD Process (media decoder), Utility Process (GPU/network)
declare -g -r PGREP_BRIDGE="muffin|nemo|kwin_x11|kwin_wayland|kded5|kglobalaccel5|mutter|nautilus|xfwm4|RDD Process|Utility Process"

# PGREP_VIP: processes that must never be starved — display server, audio, network, DM
# Display managers: lightdm (Mint/Ubuntu), sddm (KDE), gdm (GNOME) — all included
# DE settings: csd-* (Cinnamon), gsd-* (GNOME), kscreen (KDE) — additive, no harm if absent
# Wayland compositors added: kwin_wayland, mutter (already in BRIDGE but VIP protection independent)
declare -g -r PGREP_VIP="pulseaudio|Xorg|NetworkManager|wpa_supplicant|lightdm|sddm|gdm|pipewire|wireplumber|dbus-daemon|power-profiles-daemon|acpid|upowerd|polkitd|csd-keyboard|csd-mouse|csd-media-keys|csd-wacom|cinnamon-settings|gsd-media-keys|gsd-keyboard|kscreen|plasmashell"

# [B26] Live restore snapshot variables
declare -g R_RAPL_PL1="" R_RAPL_PL2="" R_SMP_AFF="" R_ASPM_POLICY="" R_SWAPPINESS="" \
           R_VFS_PRESSURE="" R_DIRTY_RATIO="" R_DIRTY_BG="" R_COMPACTION="" \
           R_SCHED_SLICE="" R_SCHED_MIG_COST="" R_THP_EN="" R_THP_DEFRAG="" \
           R_F11_LINE="" R_F1_LINE="" R_F12_LINE="" R_F10_LINE="" \
           MSR_RESTORE="" MSR_CPU="" R_NO_TURBO="" R_UNCORE_LIMIT=""  # MSR: prefetch(0x1A4) + uncore(0x620) + turbo(no_turbo) restore

# [B27] DXVK runtime and quarantine initialization
export DXVK_ASYNC=1
export DXVK_STATE_CACHE=1
export DXVK_NUM_COMPILER_THREADS=2
export DXVK_ENABLE_GPL=1

taskset -a -pc 0 $$ >/dev/null 2>&1
renice -n 0 -p $$ >/dev/null 2>&1

# [A2] Runtime system constants — read once after globals, before any function uses them  [v4.5.1]
_clk=$(getconf CLK_TCK 2>/dev/null); (( _clk > 0 )) && CLK_TCK=$_clk; unset _clk

# [A3] Display session discovery — DISPLAY and XAUTHORITY from user's live session  [v4.5.3]
# Hardcoding DISPLAY=:0 and ~/.Xauthority breaks on Wayland/XWayland, multi-seat,
# and display managers that write auth cookies to /run/user/ (SDDM, GDM).
# Strategy: walk /proc/*/environ for the user's graphical processes to extract
# the real values. Falls back to :0 / ~/.Xauthority if discovery fails.
_discover_display() {
    local _uid; _uid=$(id -u "$SUDO_USER" 2>/dev/null); [[ -z "$_uid" ]] && return 1
    local _disp="" _xauth="" _pid _env_file
    # Search running processes owned by the user for DISPLAY and XAUTHORITY
    for _env_file in /proc/*/environ; do
        _pid=${_env_file%/environ}; _pid=${_pid##*/}
        [[ ! -r "$_env_file" ]] && continue
        # Check process owner matches SUDO_USER
        local _proc_uid; _proc_uid=$(stat -c '%u' "$_env_file" 2>/dev/null)
        [[ "$_proc_uid" != "$_uid" ]] && continue
        # Read null-delimited environ, extract DISPLAY and XAUTHORITY
        local _d _x
        _d=$(tr '\0' '\n' < "$_env_file" 2>/dev/null | grep '^DISPLAY=' | head -1)
        _x=$(tr '\0' '\n' < "$_env_file" 2>/dev/null | grep '^XAUTHORITY=' | head -1)
        [[ -n "$_d" && -z "$_disp" ]] && _disp="${_d#DISPLAY=}"
        [[ -n "$_x" && -z "$_xauth" ]] && _xauth="${_x#XAUTHORITY=}"
        # Stop once we have both
        [[ -n "$_disp" && -n "$_xauth" ]] && break
    done
    # Apply discovered values, falling back to safe defaults
    DISPLAY_ID="${_disp:-:0}"
    if [[ -n "$_xauth" && -f "$_xauth" ]]; then
        XAUTH_PATH="$_xauth"
    else
        XAUTH_PATH="${USER_HOME}/.Xauthority"
    fi
}
_discover_display; unset -f _discover_display


# [C] --- PRIMITIVE HELPERS ---                              

# [C1] Formatted timestamp console echo helper
t_echo() { printf -v _TS "%(%H:%M:%S)T" -1; echo -e "[${_TS}] $1"; }

# [C2] Log buffer append and flush logic
lg() {
    local _now; printf -v _now "%(%H:%M:%S)T" -1
    LOG_BUFFER+=("[$_now] $1")
    (( ${#LOG_BUFFER[@]} >= LOG_BUFFER_LIMIT )) && flush_logs
}
flush_logs() {
    [[ ${#LOG_BUFFER[@]} -eq 0 ]] && return
    [[ -n "$SES_LOG" ]] && printf '%s\n' "${LOG_BUFFER[@]}" >> "$SES_LOG" 2>/dev/null
    LOG_BUFFER=()
}

# [C3] Proc status context switch parser — used where vol/nonvol split is needed
r_csw() {
    _READ_VOL=0; _READ_NONVOL=0; local _rk _rv _rf=0
    while IFS=': '$'\t' read -r _rk _rv _; do
        if [[ "$_rk" == "voluntary_ctxt_switches" ]]; then _READ_VOL=$_rv; (( ++_rf == 2 )) && break
        elif [[ "$_rk" == "nonvoluntary_ctxt_switches" ]]; then _READ_NONVOL=$_rv; (( ++_rf == 2 )) && break; fi
    done < "$1" 2>/dev/null
}
# [C3b] Fast ctx-switch total via schedstat — single-line read, no loop  [v4.1.0]
# schedstat: exec_ns wait_ns nr_switches — field 3 = vol+nonvol total
# Use this for all hot-path callers that only need the combined total
r_sw() {
    local _path="$1" _e _w
    _READ_VOL=0; _READ_NONVOL=0
    read -r _e _w _READ_VOL < "$_path" 2>/dev/null || _READ_VOL=0
}

# [C4] Writable sysfs node value swapper
sw() {
    local value=$1 target=$2
    if [[ -w "$target" ]]; then
        local _ssw_cur=""; read -r _ssw_cur < "$target" 2>/dev/null
        if [[ "$_ssw_cur" != *"$value"* ]]; then printf '%s\n' "$value" > "$target" 2>/dev/null; (( APPLIED_COUNT++ ))
        else (( SKIPPED_COUNT++ )); fi
    fi
}

# [C5] Cached renice and taskset wrappers
c_renice() {
    local tid=$1 nice=$2; [[ "${TC_NICE[$tid]}" == "$nice" ]] && return
    "$BIN_RENICE" -n "$nice" -p "$tid" >/dev/null 2>&1; TC_NICE[$tid]="$nice"
}
c_tset() {
    local tid=$1 core=$2
    # [v3.9.8:H2] Fast path: cache hit skips /proc/stat read entirely
    # ⚠ STABILITY NOTE: live core verification only runs on cache miss. If an external
    #   agent migrates a thread between inv_tc() cycles, the next pin_th will re-correct it.
    #   TC_CORE is cleared on inv_tc() (every G_VLD=0 event), so drift window ≤ MT_INTV.
    if [[ "${TC_CORE[$tid]}" == "$core" ]]; then return; fi
    local _live_core="?" _stat_raw=""
    local _stat_file="$TASK_BASE/$tid/stat"
    if [[ -f "$_stat_file" ]]; then
        read -r _stat_raw < "$_stat_file" 2>/dev/null
        if [[ -n "$_stat_raw" ]]; then
            _stat_raw="${_stat_raw##*) }"; local -a _stat_arr=( $_stat_raw )
            _live_core="${_stat_arr[36]}"
        fi
    fi
    [[ "$_live_core" == "$core" ]] && { TC_CORE[$tid]="$core"; return; }
    "$BIN_TSET" -cp "$core" "$tid" >/dev/null 2>&1; TC_CORE[$tid]="$core"
}

# [C6] Cached RT scheduler wrapper — skips chrt syscall if policy+priority unchanged  [v3.9.8:H1]
# ⚠ STABILITY NOTE: TC_SCHED is cleared on inv_tc() (topology invalidation) and on G_VLD=0.
#   This is safe because chrt assignments are per-TID and survive across pin_th cycles.
#   Risk: if an external process resets a thread's scheduler policy between MT intervals,
#   the cache will not detect it. Acceptable — no external agent should touch game thread
#   scheduling while the sentinel is running.
c_chrt() {
    local policy=$1 prio=$2 tid=$3
    local _key="${tid}_${policy}_${prio}"
    [[ "${TC_SCHED[$tid]}" == "$_key" ]] && return
    "$BIN_CHRT" "$policy" -p "$prio" "$tid" 2>/dev/null && TC_SCHED[$tid]="$_key"
}
# [C7] Cache invalidation — clears TC_*/path caches, refreshes BROWSER/BRIDGE PIDs  [v4.1.1]
# _EPP_STATE reset: freq_lock/unlock skip EPP writes when cached state matches; topology change
# may reassign cores, so EPP must be re-verified on next freq transition.
inv_tc() {
    TC_CORE=(); TC_NICE=(); TC_SCHED=(); TC_CLASS=(); _EPP_STATE=""
    BROWSER_PIDS=$(pgrep -if "firefox|chrome|chromium|brave" 2>/dev/null)
    BRIDGE_PIDS=$(pgrep -if "$PGREP_BRIDGE" 2>/dev/null)
}
inv_critical() {
    unset "TC_CORE[$MON_ID]" "TC_CORE[$MGR_ID]" "TC_NICE[$MON_ID]" "TC_NICE[$MGR_ID]"
    # Also clear shader entries — their IDs may have been cached as MUD before confirmation  [v4.4.9]
    [[ -n "$SHADER_H_ID" ]] && unset "TC_CORE[$SHADER_H_ID]"
    [[ -n "$SHADER_L_ID" ]] && unset "TC_CORE[$SHADER_L_ID]"
}

# [C8] Session log and CSV initialization
log_init() {
    [[ "$LOG_EN" -ne 1 ]] && return; local ts; printf -v ts "%(%Y%m%d_%H%M%S)T" -1  # [v3.9.8:L2] mkdir removed — M3 guarantees dir
    SES_LOG="${LOG_DIR}/session_${ts}.log"; SES_CSV="${LOG_DIR}/session_${ts}.csv"; BURST_CSV="${LOG_DIR}/burst_${ts}.csv"
    SES_TS="$ts"  # pre-computed once — eliminates SES_CSV strip in tel_end + burst_sample  [v4.2.0G]
    { echo "# APEX PHOENIX — session log"; echo "# Version : ${APXP_VERSION}"; printf -v _log_started "Started : %(%Y-%m-%d %H:%M:%S)T" -1; echo "# $_log_started"; echo "# PID     : $$"; } >> "$SES_LOG"
    echo "timestamp_us,ses_ts,window,event_type,sys_state,player_class,monster_rate,manager_rate,heart_rate,dxvk_q_ratio,dxvk_cs_pct,mt_hitch_us,cpu_temp,gpu_mhz,idle_counter,fence_active,burst_fired" > "$SES_CSV"
    echo "timestamp_us,ses_ts,burst_id,trigger,sample_idx,t_cls,tid,core,exec_delta_ns,wait_delta_ns,vol_sw_delta,nonvol_sw_delta" > "$BURST_CSV"
    t_echo "  [✓] Session Engines Armed."
}

# [C9] Base Priority Assignment (set_pr) — absorbed into pin_th J10/J11 [v4.4.9]
# MON/MGR renice: now in pin_th case MON/MGR. MUD renice+BATCH: now in pin_th J11 *).
# Stub retained for call-site compatibility; all callers (M7, N17, benchmark) are no-ops.
set_pr() { return 0; }

# [C10] External process caging utility
# Applies nice, chrt, and taskset to PID and all its TIDs.
# taskset on PID alone only constrains the main thread — multithreaded
# processes (Firefox, DXVK) require per-TID affinity to be fully caged.
cage_external() {
    local pids="$1" nice="$2" chrt_flag="$3" mask="$4"
    [[ -z "$pids" ]] && return 1
    local pid _tid
    for pid in $pids; do
        "$BIN_RENICE" -n "$nice" -p "$pid" >/dev/null 2>&1
        "$BIN_CHRT" "$chrt_flag" -p 0 "$pid" >/dev/null 2>&1
        "$BIN_TSET" -cp "$mask" "$pid" >/dev/null 2>&1
        # Apply affinity to all threads — PID-level taskset misses child TIDs
        for _tid in /proc/"$pid"/task/*/; do
            [[ -d "$_tid" ]] || continue
            _tid=${_tid%/}; _tid=${_tid##*/}
            "$BIN_TSET" -cp "$mask" "$_tid" >/dev/null 2>&1 || true
        done
    done
    return 0
}

# [C12] --- CLEANUP TRAP ATOMIC RESTORATION ---
cleanup() {
    trap - EXIT INT TERM; echo -e "\n[!] SESSION ENDED: Executing Flash-Clear Restoration..."
    # [C13] Data integrity and RAM buffer flush
    lg "SESSION ENDED — ticks:${TICK_CTR} uptime:$(( TICK_CTR * 2 ))s"; flush_logs
    # Clean up any interrupted download temp files  [v4.7.2]
    rm -f /tmp/wine-ge-GE-Proton*.tar.xz /tmp/wine-ge-*.tar.xz 2>/dev/null
    rm -f /tmp/dxvk_apxp.tar.gz /tmp/EphineaPSO_installer_*.exe 2>/dev/null
    rm -rf /tmp/dxvk_apxp_extract /tmp/_apxp_zip_* 2>/dev/null
    rm -f /tmp/apxp_mon_tid 2>/dev/null
    
    # [C14] Restoration Sequence
    [[ -n "$BIN_CHRT" && -n "$PSOBB_PID" ]] && "$BIN_CHRT" -o -p 0 "$PSOBB_PID" >/dev/null 2>&1
    [[ -n "$LOCK_PID" ]] && kill "$LOCK_PID" 2>/dev/null && wait "$LOCK_PID" 2>/dev/null
    if (( HAS_WRMSR )); then
        [[ -n "$MSR_RESTORE" && -n "$MSR_CPU" ]] && "$BIN_WRMSR" -p "$MSR_CPU" 0x1A4 "$(( 16#${MSR_RESTORE} ))" 2>/dev/null
        [[ -n "$R_UNCORE_LIMIT" ]] && "$BIN_WRMSR" 0x620 "$R_UNCORE_LIMIT" 2>/dev/null
    fi
    # [C14b] RAPL restore — fallback to safe constants if snapshot empty  [v3.9.3:M1]
    if (( HAS_RAPL_WRITABLE )); then
        local _r_pl1="${R_RAPL_PL1:-$RAPL_RESTORE_PL1}" _r_pl2="${R_RAPL_PL2:-$RAPL_RESTORE_PL2}"
        [[ -n "$_r_pl1" ]] && printf '%s\n' "$_r_pl1" > "${RAPL_PATH}/constraint_0_power_limit_uw" 2>/dev/null
        [[ -n "$_r_pl2" ]] && printf '%s\n' "$_r_pl2" > "${RAPL_PATH}/constraint_1_power_limit_uw" 2>/dev/null
    fi
    
    # [C15] C-state re-enable, frequency unlock, and turbo restore
    for _cs in /sys/devices/system/cpu/cpu*/cpuidle/state{2,3}/disable; do  # [v3.8.2:M2]
        [[ -w "$_cs" ]] && printf '0\n' > "$_cs" 2>/dev/null
    done
    freq_unlock
    set_turbo "${R_NO_TURBO:-0}"  # restore pre-session state; default = turbo enabled

    # [C16] Fan restore  [v3.8.3:H1]
    (( HAS_FAN_NODE )) && printf "level auto\n" > /proc/acpi/ibm/fan 2>/dev/null

    # [C17] IRQ affinity restore
    [[ -n "$R_SMP_AFF" ]] && printf '%s\n' "$R_SMP_AFF" > /proc/irq/default_smp_affinity 2>/dev/null
    systemctl start irqbalance thermald avahi-daemon bluetooth >/dev/null 2>&1

    # [C18] VM / THP / sched / ASPM / FS restore  [v3.8.3:H1]
    grep -q "^[^ ]* / ext4 " /proc/mounts 2>/dev/null && mount -o remount,commit=5 / >/dev/null 2>&1  # [v3.9.3:L2]
    [[ -n "$R_SWAPPINESS" ]]   && sysctl -w vm.swappiness="$R_SWAPPINESS" >/dev/null 2>&1
    [[ -n "$R_VFS_PRESSURE" ]] && sysctl -w vm.vfs_cache_pressure="$R_VFS_PRESSURE" >/dev/null 2>&1
    [[ -n "$R_DIRTY_RATIO" ]]  && sysctl -w vm.dirty_ratio="$R_DIRTY_RATIO" >/dev/null 2>&1
    [[ -n "$R_DIRTY_BG" ]]     && sysctl -w vm.dirty_background_ratio="$R_DIRTY_BG" >/dev/null 2>&1
    [[ -n "$R_COMPACTION" ]]   && sysctl -w vm.compaction_proactiveness="$R_COMPACTION" >/dev/null 2>&1
    [[ -n "$R_THP_EN" ]]       && sw "$R_THP_EN"       "/sys/kernel/mm/transparent_hugepage/enabled"
    [[ -n "$R_THP_DEFRAG" ]]   && sw "$R_THP_DEFRAG"   "/sys/kernel/mm/transparent_hugepage/defrag"
    [[ -n "$R_ASPM_POLICY" ]]  && sw "$R_ASPM_POLICY"  "/sys/module/pcie_aspm/parameters/policy"
    if (( HAS_SCHED_DEBUG )); then
        [[ -n "$R_SCHED_SLICE" ]]    && sw "$R_SCHED_SLICE"    "/sys/kernel/debug/sched/base_slice_ns"
        [[ -n "$R_SCHED_MIG_COST" ]] && sw "$R_SCHED_MIG_COST" "/sys/kernel/debug/sched/migration_cost_ns"
    fi

    # [C18b] OS liberation — release background apps from MUD cage on exit  [v3.9.7:M3]
    local _lib_pids _all_cores="0-$(( HW_CPU_COUNT > 0 ? HW_CPU_COUNT - 1 : 7 ))"
    _lib_pids=$(pgrep -if "firefox|chrome|chromium|brave|$PGREP_CHAFF|$PGREP_BRIDGE" 2>/dev/null)
    if [[ -n "$_lib_pids" ]]; then
        t_echo "  [~] Liberating caged background processes..."
        local _lp _lt
        for _lp in $_lib_pids; do
            [[ -n "$BIN_CHRT"   ]] && "$BIN_CHRT"   -o -p 0 "$_lp" >/dev/null 2>&1
            [[ -n "$BIN_RENICE" ]] && "$BIN_RENICE"  -n 0 -p "$_lp" >/dev/null 2>&1
            [[ -n "$BIN_TSET"   ]] && "$BIN_TSET"   -a -cp "$_all_cores" "$_lp" >/dev/null 2>&1
            for _lt in /proc/"$_lp"/task/*/; do
                [[ -d "$_lt" ]] || continue
                _lt=${_lt%/}; _lt=${_lt##*/}
                [[ -n "$BIN_TSET" ]] && "$BIN_TSET" -a -cp "$_all_cores" "$_lt" >/dev/null 2>&1 || true
            done
        done
    fi

    # [C20] Keymap restore
    local _xauth="sudo -u $SUDO_USER env XAUTHORITY=$XAUTH_PATH DISPLAY=$DISPLAY_ID xmodmap"
    [[ -n "$R_F1_LINE" ]]  && $_xauth -e "$R_F1_LINE" 2>/dev/null
    [[ -n "$R_F10_LINE" ]] && $_xauth -e "$R_F10_LINE" 2>/dev/null
    [[ -n "$R_F11_LINE" ]] && $_xauth -e "$R_F11_LINE" 2>/dev/null
    [[ -n "$R_F12_LINE" ]] && $_xauth -e "$R_F12_LINE" 2>/dev/null

    echo -e "  [✓] SYSTEM STATE RESTORED. Goodbye, Zordon.\n"; exit 0
}
trap cleanup EXIT INT TERM
# [D] --- HARDWARE FUNCTIONS (bootstrap-tier) ---                              

# [D1] CPU Topology Auto-Detection
init_tp() {
    local topo_dir="/sys/devices/system/cpu"
    local -A phys_to_logical   
    local -a phys_cores_sorted 
    local cpu_count=0

    # [D2] Build physical and logical CPU mapping from core_id files
    for cpu_dir in "$topo_dir"/cpu[0-9]*/; do
        local cpu_n=${cpu_dir##*cpu}; cpu_n=${cpu_n%/}
        [[ ! "$cpu_n" =~ ^[0-9]+$ ]] && continue
        local core_id_file="${cpu_dir}topology/core_id"
        [[ ! -f "$core_id_file" ]] && continue
        local core_id
        read -r core_id < "$core_id_file" 2>/dev/null
        [[ -z "$core_id" ]] && continue
        phys_to_logical[$core_id]+="$cpu_n "
        ((cpu_count++))
    done

    # [D3] Classify topology — branch instead of reject  [v4.5.2]
    local phys_count=${#phys_to_logical[@]}
    local max_siblings=0
    for phys_id in "${!phys_to_logical[@]}"; do
        local sib_count; sib_count=$(( $(echo "${phys_to_logical[$phys_id]}" | wc -w) ))
        (( sib_count > max_siblings )) && max_siblings=$sib_count
    done

    # [D4] Hybrid detection — E-cores have >2 siblings in topology; defer to defaults
    if (( max_siblings > 2 )); then
        t_echo "  [!] Topology: hybrid CPU detected (E+P cores) — using config defaults"
        t_echo "        Assign CORE_* manually for this architecture."
        return 1
    fi
    if (( phys_count < 4 )); then
        t_echo "  [!] Topology: only ${phys_count} physical cores — minimum 4 required"
        return 1
    fi

    local topo_class
    if   (( phys_count == 4 && max_siblings == 1 )); then topo_class="4T"
    elif (( phys_count == 4 && max_siblings == 2 )); then topo_class="8T"
    elif (( phys_count == 6 && max_siblings == 2 )); then topo_class="12T"
    elif (( phys_count >= 8 && max_siblings == 2 )); then topo_class="16T"
    else
        t_echo "  [!] Topology: ${phys_count}C/${cpu_count}T unrecognised — using defaults"
        return 1
    fi

    # [D5] Sort physical core IDs — forkless insertion sort
    local -a phys_cores_sorted=( "${!phys_to_logical[@]}" )
    local _si _sj _sv
    for (( _si=1; _si<${#phys_cores_sorted[@]}; _si++ )); do
        _sv=${phys_cores_sorted[$_si]}
        for (( _sj=_si-1; _sj>=0 && phys_cores_sorted[_sj]>_sv; _sj-- )); do
            phys_cores_sorted[$((_sj+1))]=${phys_cores_sorted[$_sj]}
        done
        phys_cores_sorted[$((_sj+1))]=$_sv
    done

    # [D6] Topology-branched role assignment  [v4.5.2]
    #
    # Invariants across all maps:
    #   MON always on a physical core primary, never shares physical with HEART
    #   HEART always on a physical core primary
    #   First 4 slots always: WS / HEART / MON / MGR (primary), AUDIO / FEEDER / RENDER / MUD (sibling)
    #   On 12T/16T the extra physical cores upgrade AUDIO and FEEDER to dedicated physicals
    #
    # Helper: extract primary/sibling from a physical core's logical list
    # Lower logical ID = primary on all x86 HT implementations
    _assign_slot() {
        local phys_id=$1 primary_var=$2 sibling_var=$3
        local -a _raw=( ${phys_to_logical[$phys_id]} )
        local _p _s
        if (( ${#_raw[@]} == 2 && _raw[0] > _raw[1] )); then
            _p=${_raw[1]}; _s=${_raw[0]}
        else
            _p=${_raw[0]}; _s=${_raw[1]:-${_raw[0]}}
        fi
        printf -v "$primary_var" '%s' "$_p"
        printf -v "$sibling_var" '%s' "$_s"
    }

    local _p0 _s0 _p1 _s1 _p2 _s2 _p3 _s3 _p4 _s4 _p5 _s5 _p6 _s6 _p7 _s7
    _assign_slot "${phys_cores_sorted[0]}" _p0 _s0
    _assign_slot "${phys_cores_sorted[1]}" _p1 _s1
    _assign_slot "${phys_cores_sorted[2]}" _p2 _s2
    _assign_slot "${phys_cores_sorted[3]}" _p3 _s3

    if [[ "$topo_class" == "4T" ]]; then
        # 4C/4T — no HT siblings. 4 logical cores total.
        # MON gets C2 isolated from HEART(C1). Audio/MUD/MGR share C3.
        # DXVK_RENDER shares C2 with MON — unavoidable on 4T.
        # DXVK_SUBMIT shares C1 with HEART — keeps it off MON's core.
        CORE_WSRV=$_p0;  CORE_HEART=$_p1; CORE_MON=$_p2;  CORE_MGR=$_p3
        CORE_AUDIO=$_p3; CORE_FEEDER=$_p1; CORE_RENDER=$_p2; CORE_MUD=$_p3
        CORE_FRAME=$_p1
        CORE_BROWSER="${_p1},${_p3}"

    elif [[ "$topo_class" == "8T" ]]; then
        # 4C/8T — current hardware. Existing proven map.
        # P0: WS+AUDIO  P1: HEART+FEEDER  P2: MON+RENDER  P3: MGR+MUD
        CORE_WSRV=$_p0;  CORE_HEART=$_p1; CORE_MON=$_p2;  CORE_MGR=$_p3
        CORE_AUDIO=$_s0; CORE_FEEDER=$_s1; CORE_RENDER=$_s2; CORE_MUD=$_s3
        CORE_FRAME=$_p1
        CORE_BROWSER="${_s1},${_s3}"

    elif [[ "$topo_class" == "12T" ]]; then
        # 6C/12T — 2 extra physical cores.
        # First 4 slots: same as 8T.
        # P4: dedicated AUDIO physical — moves audio off P0-sibling.
        # P5: dedicated FEEDER physical — moves feeder off P1-sibling.
        # P0-sibling and P1-sibling become extra MUD pool cores.
        _assign_slot "${phys_cores_sorted[4]}" _p4 _s4
        _assign_slot "${phys_cores_sorted[5]}" _p5 _s5
        CORE_WSRV=$_p0;  CORE_HEART=$_p1; CORE_MON=$_p2;  CORE_MGR=$_p3
        CORE_AUDIO=$_p4; CORE_FEEDER=$_p5; CORE_RENDER=$_s2; CORE_MUD=$_s3
        CORE_FRAME=$_p1
        # Browser: audio-sib + MUD — keep off MON/HEART/MGR physicals
        CORE_BROWSER="${_s4},${_s3}"

    elif [[ "$topo_class" == "16T" ]]; then
        # 8C/16T — 4 extra physical cores.
        # First 4 slots: identical to 8T (proven map preserved).
        # P4: dedicated AUDIO physical.
        # P5-P7: expanded MUD pool / FEEDER overflow.
        _assign_slot "${phys_cores_sorted[4]}" _p4 _s4
        _assign_slot "${phys_cores_sorted[5]}" _p5 _s5
        _assign_slot "${phys_cores_sorted[6]}" _p6 _s6
        _assign_slot "${phys_cores_sorted[7]}" _p7 _s7
        CORE_WSRV=$_p0;  CORE_HEART=$_p1; CORE_MON=$_p2;  CORE_MGR=$_p3
        CORE_AUDIO=$_p4; CORE_FEEDER=$_s1; CORE_RENDER=$_s2; CORE_MUD=$_s3
        CORE_FRAME=$_p1
        CORE_BROWSER="${_s4},${_s3}"
    fi

    # [D7] Rebuild derived Discord and dynamic frame shift core values
    CORE_DISCORD="${CORE_AUDIO},${CORE_MUD}"
    (( DQ_FENCE == 0 )) && CORE_FRAME=$CORE_HEART

    # [D8] Print hardware topology summary
    HW_CPU_COUNT=$cpu_count  # persist for cleanup/liberation use  [v4.5.3]
    t_echo "  [✓] Topology: ${cpu_count} logical / ${phys_count} physical (${topo_class})"
    t_echo "   C${CORE_WSRV}=WS C${CORE_HEART}=♥ C${CORE_MON}=MON C${CORE_MGR}=MGR"
    t_echo "   C${CORE_AUDIO}=AU C${CORE_FEEDER}=FD C${CORE_RENDER}=RD C${CORE_MUD}=MUD"
    return 0
}

# [D9] Frequency Controls (freq_lock / freq_unlock / set_turbo)
# set_turbo 0 = enable, set_turbo 1 = disable
# Ownership: freq_lock calls set_turbo 1; N9/freq_unlock path calls set_turbo 0;
# C15 cleanup calls set_turbo with R_NO_TURBO snapshot. No double-writes.  [v4.0.3]
set_turbo() {
    # Supports Intel (intel_pstate/no_turbo) and AMD (cpufreq/boost) turbo nodes  [v4.5.3]
    # R_NO_TURBO="amd" sentinel set by E9 if AMD boost node was detected
    if [[ "$R_NO_TURBO" == "amd" ]]; then
        local _amd_boost="/sys/devices/system/cpu/cpufreq/boost"
        [[ -w "$_amd_boost" ]] || return 0
        # AMD boost: 1=enabled, 0=disabled — inverted from Intel no_turbo
        local _amd_val=$(( 1 - $1 ))
        printf '%s\n' "$_amd_val" > "$_amd_boost" 2>/dev/null
        return 0
    fi
    local _nt_node="/sys/devices/system/cpu/intel_pstate/no_turbo"
    [[ -w "$_nt_node" ]] || return 0
    [[ -z "$R_NO_TURBO" ]] && read -r R_NO_TURBO < "$_nt_node" 2>/dev/null  # snapshot once
    printf '%s\n' "$1" > "$_nt_node" 2>/dev/null
    # Verify write landed — silent failure possible in HWP passive/BIOS-locked configs
    local _verify; read -r _verify < "$_nt_node" 2>/dev/null
    [[ "$_verify" == "$1" ]] && HAS_TURBO_CTRL=1 || HAS_TURBO_CTRL=0
}

freq_lock() {
    local target_mhz="$1"
    local _sf

    # [D10b] Direct scaling_max_freq write using pre-expanded path array  [v4.1.1]
    local _khz=$(( target_mhz * 1000 ))
    for _sf in "${_SF_MAX_FREQ[@]:-/sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq}"; do
        [[ -w "$_sf" ]] && printf '%s\n' "$_khz" > "$_sf" 2>/dev/null
    done

    # [D11] EPP — skip if already 'performance' (cache-gated)  [v4.1.1]
    if [[ "$_EPP_STATE" != "performance" ]]; then
        for _sf in "${_SF_EPP[@]:-/sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference}"; do
            [[ -w "$_sf" ]] && printf '%s\n' "performance" > "$_sf" 2>/dev/null
        done
        _EPP_STATE="performance"
    fi

    # [D12] pstate pct — use pre-computed GAME_PCT; fall back to arithmetic if not set  [v4.1.1]
    if (( HAS_PSTATE )); then
        local _pct=${GAME_PCT:-0}
        if (( _pct == 0 )); then
            _pct=$(( target_mhz * 100 / HW_MAX_MHZ ))
            (( _pct < 1 )) && _pct=1; (( _pct > 100 )) && _pct=100
        fi
        printf '%s\n' "$_pct" > /sys/devices/system/cpu/intel_pstate/min_perf_pct 2>/dev/null
        printf '%s\n' "$_pct" > /sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null
    fi

    # [D12b] Disable turbo — fixed clock baseline for telemetry A/B consistency
    set_turbo 1
}

freq_unlock() {
    # [D13] Release pstate frequency constraints and restore EPP
    local _sf

    # [D13b] Release scaling_max_freq cap using pre-expanded array  [v4.1.1]
    local _max_khz=$(( HW_MAX_MHZ * 1000 ))
    for _sf in "${_SF_MAX_FREQ[@]:-/sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq}"; do
        [[ -w "$_sf" ]] && printf '%s\n' "$_max_khz" > "$_sf" 2>/dev/null
    done

    # EPP restore — skip if already balance_performance  [v4.1.1]
    if [[ "$_EPP_STATE" != "balance_performance" ]]; then
        for _sf in "${_SF_EPP[@]:-/sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference}"; do
            [[ -w "$_sf" ]] && printf '%s\n' "balance_performance" > "$_sf" 2>/dev/null
        done
        _EPP_STATE="balance_performance"
    fi

    if (( HAS_PSTATE )); then
        printf '%s\n' "0"   > /sys/devices/system/cpu/intel_pstate/min_perf_pct 2>/dev/null
        printf '%s\n' "100" > /sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null
    fi
    # Turbo intentionally NOT set here — caller owns turbo state
    # N9 DESKTOP path calls set_turbo 0; C15 cleanup calls set_turbo R_NO_TURBO
}

# [E] --- PRE-FLIGHT CAPABILITY CHECK ---                                          

# [E1] Capability Check (pf)
pf() {
    [[ "$DEPS_CHECKED" -eq 1 ]] && return  
    DEPS_CHECKED=1
    t_echo "[+] Pre-flight: dependency check and install..."
    local _pf_abort=0 _dep _pf_cont
    local _missing_pkgs=""

    # [E2] Fast binary scan for taskset renice and chrt — scan all; missing any adds util-linux
    local _bin _e2_missing=0
    for _dep in taskset renice chrt; do
        _bin=$(command -v "$_dep" 2>/dev/null)
        if [[ -z "$_bin" ]]; then
            _e2_missing=1
        else
            case "$_dep" in
                taskset) BIN_TSET="$_bin" ;;
                renice)  BIN_RENICE="$_bin" ;;
                chrt)    BIN_CHRT="$_bin" ;;
            esac
        fi
    done
    (( _e2_missing )) && _missing_pkgs+=" util-linux"

    [[ -z "$(command -v curl 2>/dev/null)" ]]  && _missing_pkgs+=" curl"   # [v4.0.0:S2] required for Wine-GE download
    [[ -z "$(command -v unzip 2>/dev/null)" ]] && _missing_pkgs+=" unzip"  # [v4.6] required for S2 zip extraction
    [[ -z "$(command -v xdotool 2>/dev/null)" ]] && _missing_pkgs+=" xdotool"
    [[ -z "$(command -v wmctrl 2>/dev/null)" ]]  && _missing_pkgs+=" wmctrl"
    [[ -z "$(command -v cpupower 2>/dev/null)" ]] && _missing_pkgs+=" cpupower"
    
    if [[ -z "$(command -v wrmsr 2>/dev/null)" || -z "$(command -v rdmsr 2>/dev/null)" ]]; then
        _missing_pkgs+=" msr-tools"
    fi

    # [E2b] 32-bit ALSA bridge — required for Wine audio; Debian/Ubuntu only  [v4.5.3]
    # Skip on SteamOS: PipeWire-native, apt unavailable, read-only root FS  [v4.7]
    if (( ! IS_STEAMOS )) && command -v dpkg >/dev/null 2>&1; then
        if ! dpkg -l libasound2-plugins:i386 2>/dev/null | grep -q "^ii"; then
            _missing_pkgs+=" libasound2-plugins:i386"
        fi
    fi

    # [E3] Package manager detection + batch install  [v4.5.3]
    # Detects: apt (Debian/Ubuntu/Mint), pacman (Arch), dnf (Fedora), zypper (openSUSE)
    # Falls back to manual install hint if no known package manager found.
    if [[ -n "$_missing_pkgs" ]]; then
        t_echo "  [!] Missing dependencies:${_missing_pkgs}"
        read -r -p "  [>] Install now? [Y/n]: " _pf_cont
        if [[ ! "$_pf_cont" =~ ^[Nn] ]]; then
            local _pm=""
            command -v apt-get >/dev/null 2>&1 && _pm="apt"
            command -v pacman  >/dev/null 2>&1 && _pm="pacman"
            command -v dnf     >/dev/null 2>&1 && _pm="dnf"
            command -v zypper  >/dev/null 2>&1 && _pm="zypper"

            if [[ -z "$_pm" ]]; then
                t_echo "  [!] No supported package manager found (apt/pacman/dnf/zypper)"
                t_echo "      Install manually: ${_missing_pkgs}"
            else
                read -ra _pkg_arr <<< "$_missing_pkgs"
                # Strip :i386 suffix from package names on non-apt systems
                if [[ "$_pm" != "apt" ]]; then
                    local _pkg_clean=()
                    for _p in "${_pkg_arr[@]}"; do _pkg_clean+=("${_p%:i386}"); done
                    _pkg_arr=("${_pkg_clean[@]}")
                    unset _pkg_clean _p
                fi
                # [E3b] i386 multiarch bootstrap for apt — idempotent  [v4.5.3]
                if [[ "$_pm" == "apt" && "$_missing_pkgs" == *":i386"* ]]; then
                    if ! dpkg --print-foreign-architectures 2>/dev/null | grep -q "^i386$"; then
                        t_echo "  [~] Registering i386 architecture..."
                        dpkg --add-architecture i386
                        apt-get update >/dev/null 2>&1
                    fi
                fi
                t_echo "  [~] Installing via ${_pm}..."
                local _install_ok=0
                case "$_pm" in
                    apt)    apt-get update >/dev/null 2>&1
                            apt-get install -y "${_pkg_arr[@]}" >/dev/null 2>&1 && _install_ok=1 ;;
                    pacman) # SteamOS has a read-only root FS — must disable before pacman  [v4.7]
                            if (( IS_STEAMOS )); then
                                steamos-readonly disable 2>/dev/null
                                pacman -Sy --noconfirm "${_pkg_arr[@]}" >/dev/null 2>&1 && _install_ok=1
                                steamos-readonly enable 2>/dev/null  # re-lock regardless of install result
                            else
                                pacman -Sy --noconfirm "${_pkg_arr[@]}" >/dev/null 2>&1 && _install_ok=1
                            fi ;;
                    dnf)    dnf install -y "${_pkg_arr[@]}" >/dev/null 2>&1 && _install_ok=1 ;;
                    zypper) zypper install -y "${_pkg_arr[@]}" >/dev/null 2>&1 && _install_ok=1 ;;
                esac
                if (( _install_ok )); then
                    t_echo "  [✓] Dependencies installed"
                else
                    t_echo "  [!] Install failed — install manually: ${_missing_pkgs}"
                    (( IS_STEAMOS )) && t_echo "      Steam Deck: steamos-readonly disable && sudo pacman -Sy ${_missing_pkgs[*]} && steamos-readonly enable"
                fi
            fi
        else
            t_echo "  [!] Skipping install — some features will be degraded"
        fi
    fi

    # [E3c] Post-install core binary re-scan — re-check after potential install above  [v4.5.3]
    # taskset/renice/chrt are non-negotiable: empty BIN_* causes silent failure everywhere
    for _dep in taskset renice chrt; do
        _bin=$(command -v "$_dep" 2>/dev/null)
        [[ -n "$_bin" ]] || continue
        case "$_dep" in
            taskset) BIN_TSET="$_bin" ;;
            renice)  BIN_RENICE="$_bin" ;;
            chrt)    BIN_CHRT="$_bin" ;;
        esac
    done
    if [[ -z "$BIN_TSET" || -z "$BIN_RENICE" || -z "$BIN_CHRT" ]]; then
        t_echo "  [!] FATAL: taskset/renice/chrt not found — cannot continue"
        t_echo "      Install util-linux:"
        t_echo "        Debian/Ubuntu/Mint: sudo apt install util-linux"
        t_echo "        Arch/Manjaro:       sudo pacman -Sy util-linux"
        t_echo "        Fedora:             sudo dnf install util-linux"
        t_echo "        Steam Deck:         steamos-readonly disable && sudo pacman -Sy util-linux && steamos-readonly enable"
        exit 1
    fi

    # [E4] Resolve X11 focus shifting and Silk compositor bypass
    if [[ -n "$(command -v xdotool 2>/dev/null)" ]]; then
        declare -g -i HAS_XDOTOOL=1
        t_echo "  [✓] xdotool → active"
    else
        declare -g -i HAS_XDOTOOL=0
        t_echo "  [!] xdotool unavailable — dynamic focus shifting disabled"
    fi

    if [[ -n "$(command -v wmctrl 2>/dev/null)" ]]; then
        declare -g -i HAS_WMCTRL=1
        t_echo "  [✓] wmctrl → active"
    else
        declare -g -i HAS_WMCTRL=0
        t_echo "  [!] wmctrl unavailable — Silk compositor bypass disabled"
    fi

    # [E5] Cache cpupower and msr-tools prefetch tuning status
    BIN_CPWR=$(command -v cpupower 2>/dev/null)
    if [[ -n "$BIN_CPWR" ]]; then
        HAS_CPWR=1
        t_echo "  [✓] cpupower → ${BIN_CPWR}"
    else
        HAS_CPWR=0
        t_echo "  [!] cpupower unavailable — freq lock layers 2+3 (EPP/pstate) skipped"
    fi

    BIN_WRMSR=$(command -v wrmsr 2>/dev/null)
    BIN_RDMSR=$(command -v rdmsr 2>/dev/null)
    if [[ -n "$BIN_WRMSR" && -n "$BIN_RDMSR" ]]; then
        HAS_WRMSR=1
        # modprobe msr may fail on locked kernels (SteamOS secure boot, hardened kernels)
        # Treat as non-fatal — msr module may already be loaded or compiled in  [v4.7]
        if ! modprobe msr >/dev/null 2>&1; then
            t_echo "  [~] modprobe msr unavailable (locked kernel) — MSR tuning may be limited"
        fi
        t_echo "  [✓] msr-tools → active"
    else
        HAS_WRMSR=0
        # Only warn on Intel — AMD skips MSR tuning by design; use CPU_VENDOR global  [v4.7]
        if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
            t_echo "  [!] msr-tools unavailable — prefetch + uncore tuning skipped (Intel)"
        else
            t_echo "  [~] msr-tools not used on ${CPU_VENDOR:-unknown} — skipped"
        fi
    fi

    # [E6] Wine-GE detection and auto-install — falls back to system Wine  [v4.0.0]
    # Wine-GE (GE-Proton8-26) ships GnuTLS with full TLS 1.3 support, fixing the
    # Ephinea launcher blank splash screen caused by secur32 cipher negotiation failure.
    local _wge_tag="GE-Proton8-26"
    local _wge_dir="${USER_HOME}/.local/share/lutris/runners/wine/lutris-GE-Proton8-26-x86_64"
    local _wge_bin="${_wge_dir}/bin/wine"
    local _wge_server="${_wge_dir}/bin/wineserver"
    local _wge_url="https://github.com/GloriousEggroll/wine-ge-custom/releases/download/${_wge_tag}/wine-lutris-${_wge_tag}-x86_64.tar.xz"

    if [[ -x "$_wge_bin" ]]; then
        WINE_BIN="$_wge_bin"
        HAS_WINE=1
        t_echo "  [✓] Wine-GE ${_wge_tag} → ${_wge_bin}"
    else
        # [E6b] Wine-GE not found — offer download and install
        t_echo "  [~] Wine-GE not found — system Wine lacks TLS 1.3 (launcher splash will be blank)"
        t_echo "      Wine-GE fixes: Ephinea launcher display · GnuTLS 1.3 · FAudio · staging patches"
        read -r -p "  [>] Download and install Wine-GE ${_wge_tag}? [Y/n]: " _wge_choice
        if [[ ! "$_wge_choice" =~ ^[Nn] ]]; then
            local _wge_tmp="/tmp/wine-ge-${_wge_tag}.tar.xz"
            local _wge_dest="${USER_HOME}/.local/share/lutris/runners/wine"
            t_echo "  [~] Downloading Wine-GE ${_wge_tag} (~300MB)..."
            mkdir -p "$_wge_dest" 2>/dev/null
            if curl -L --progress-bar "$_wge_url" -o "$_wge_tmp"; then
                # Validate download is a real tarball — GitHub can return HTML on rate-limit/error
                # A real .tar.xz starts with magic bytes FD 37 7A 58 5A 00 (XZ magic)
                local _magic; _magic=$(xxd -p -l 6 "$_wge_tmp" 2>/dev/null || od -A n -N 6 -t x1 "$_wge_tmp" 2>/dev/null | tr -d ' ')
                local _fsize; _fsize=$(stat -c%s "$_wge_tmp" 2>/dev/null || echo 0)
                if [[ "$_fsize" -lt 10000000 || ! "$_magic" =~ ^fd377a585a00 ]]; then
                    t_echo "  [!] Download appears corrupt or is an error page (${_fsize} bytes) — falling back to system Wine"
                    t_echo "      Try manually: curl -L '${_wge_url}' -o ~/wine-ge.tar.xz"
                    rm -f "$_wge_tmp"
                    WINE_BIN=$(command -v wine 2>/dev/null)
                    [[ -n "$WINE_BIN" ]] && HAS_WINE=1 || { HAS_WINE=0; _pf_abort=1; }
                else
                    t_echo "  [~] Extracting to ${_wge_dest}..."
                    if tar -xf "$_wge_tmp" -C "$_wge_dest" 2>/dev/null; then
                        rm -f "$_wge_tmp"
                        if [[ -x "$_wge_bin" ]]; then
                            WINE_BIN="$_wge_bin"
                            HAS_WINE=1
                            t_echo "  [✓] Wine-GE ${_wge_tag} installed and active"
                        else
                            t_echo "  [!] Extraction succeeded but binary not found — falling back to system Wine"
                            WINE_BIN=$(command -v wine 2>/dev/null)
                            [[ -n "$WINE_BIN" ]] && HAS_WINE=1 || { HAS_WINE=0; _pf_abort=1; }
                        fi
                    else
                        t_echo "  [!] Extraction failed — falling back to system Wine"
                        rm -f "$_wge_tmp"
                        WINE_BIN=$(command -v wine 2>/dev/null)
                        [[ -n "$WINE_BIN" ]] && HAS_WINE=1 || { HAS_WINE=0; _pf_abort=1; }
                    fi
                fi  # end magic check
            else
                t_echo "  [!] Download failed — check network — falling back to system Wine"
                rm -f "$_wge_tmp"
                WINE_BIN=$(command -v wine 2>/dev/null)
                [[ -n "$WINE_BIN" ]] && HAS_WINE=1 || { HAS_WINE=0; _pf_abort=1; }
            fi
        else
            # User declined — use system Wine with warning
            t_echo "  [~] Wine-GE declined — using system Wine (launcher splash may be blank)"
            WINE_BIN=$(command -v wine 2>/dev/null)
            if [[ -n "$WINE_BIN" ]]; then
                HAS_WINE=1; t_echo "  [✓] wine (system) → $WINE_BIN"
            else
                HAS_WINE=0; t_echo "  [!] wine not found"; _pf_abort=1
            fi
        fi
        unset _wge_choice
    fi
    # Wire Wine-GE wineserver if active — flag avoids fragile local var comparison  [v4.0.0:S1]
    if [[ -x "${_wge_dir}/bin/wineserver" && "$HAS_WINE" -eq 1 && "$WINE_BIN" == *"wine-lutris"* ]]; then
        declare -g WINESERVER_BIN="${_wge_dir}/bin/wineserver"
    else
        declare -g WINESERVER_BIN="$(command -v wineserver 2>/dev/null)"
    fi
    unset _wge_tag _wge_dir _wge_bin _wge_server _wge_url
    
    if [[ -f "$GAME_DIR/online.exe" ]]; then
        HAS_GAME_EXE=1
        t_echo "  [✓] online.exe found"
    else
        HAS_GAME_EXE=0
        # Warning only — GAME_DIR can be corrected at the [S2] setup prompt; recheck runs after
        t_echo "  [~] online.exe not found at $GAME_DIR — set correct path at the Game path prompt"
    fi

    if [[ -f "$GAME_DIR/dxvk.conf" ]]; then
        HAS_DXVK_CONF=1
        t_echo "  [✓] dxvk.conf found"
    else
        HAS_DXVK_CONF=0
        t_echo "  [~] dxvk.conf not found at $GAME_DIR — S4 will generate one at launch"
    fi

    # [E7] Verify RAPL powercap node — probe Intel and AMD paths  [v4.5.3]
    local _rapl_node=""
    [[ -d /sys/class/powercap/intel-rapl:0 ]] && _rapl_node="/sys/class/powercap/intel-rapl:0"
    # AMD energy driver uses a different powercap path
    [[ -z "$_rapl_node" && -d /sys/class/powercap/amd_energy ]] && _rapl_node="/sys/class/powercap/amd_energy"
    if [[ -n "$_rapl_node" ]]; then
        HAS_RAPL_NODE=1; RAPL_PATH="$_rapl_node"
        # HAS_RAPL_WRITABLE: only if constraint files exist — amd_energy has no constraint_ files  [v4.7]
        if [[ -w "${_rapl_node}/constraint_0_power_limit_uw" ]]; then
            HAS_RAPL_WRITABLE=1; t_echo "  [✓] RAPL node present (${_rapl_node##*/}) — power limits writable"
        else
            HAS_RAPL_WRITABLE=0; t_echo "  [✓] RAPL node present (${_rapl_node##*/}) — monitoring only, no power limit writes"
        fi
    else
        HAS_RAPL_NODE=0; t_echo "  [~] RAPL powercap node not found — power limit management disabled"
    fi
    unset _rapl_node

    # Detect active cpufreq scaling driver for accurate labelling  [v4.5.3]
    local _pstate_driver; _pstate_driver=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || echo "unknown")
    if [[ -w /sys/devices/system/cpu/intel_pstate/min_perf_pct ]]; then
        HAS_PSTATE=1; t_echo "  [✓] ${_pstate_driver} active (pstate pct control available)"
    else
        HAS_PSTATE=0; t_echo "  [~] ${_pstate_driver} — pstate pct control unavailable (scaling_max_freq used)"
    fi
    unset _pstate_driver

    # [E8] Enforce kernel real-time throttling five percent safety limit
    if [[ -w /proc/sys/kernel/sched_rt_runtime_us ]]; then
        local _rt_runtime=""
        read -r _rt_runtime < /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null
        if [[ "$_rt_runtime" == "-1" || "$_rt_runtime" -gt 950000 ]]; then
            sysctl -w kernel.sched_rt_runtime_us=950000 >/dev/null 2>&1
            t_echo "  [✓] RT Throttling enforced (950000us)"
        else
            t_echo "  [✓] RT Throttling already safe (${_rt_runtime}us)"
        fi
        HAS_RT_THROTTLE=1
    else
        HAS_RT_THROTTLE=0
        t_echo "  [!] RT Throttle node unwritable — WARNING: RT limits bypassed"
    fi

    # [E9] Verify scheduler debugfs, thinkpad_acpi fan node, and turbo control
    if [[ -f /sys/kernel/debug/sched/base_slice_ns ]]; then
        HAS_SCHED_DEBUG=1; t_echo "  [✓] sched debugfs mounted"
    else
        HAS_SCHED_DEBUG=0; t_echo "  [~] sched debugfs not mounted — scheduler tuning skipped"
    fi

    # [E9b] Turbo control — probe Intel (no_turbo) and AMD (boost) paths  [v4.5.3]
    local _nt_node="/sys/devices/system/cpu/intel_pstate/no_turbo"
    local _amd_boost="/sys/devices/system/cpu/cpufreq/boost"
    if [[ -w "$_nt_node" ]]; then
        local _nt_cur; read -r _nt_cur < "$_nt_node" 2>/dev/null
        printf '%s\n' "$_nt_cur" > "$_nt_node" 2>/dev/null
        local _nt_verify; read -r _nt_verify < "$_nt_node" 2>/dev/null
        if [[ "$_nt_verify" == "$_nt_cur" ]]; then
            HAS_TURBO_CTRL=1; t_echo "  [✓] Turbo control active (no_turbo node writable)"
        else
            HAS_TURBO_CTRL=0; t_echo "  [~] Turbo node write ignored — scaling_max_freq is primary cap"
        fi
    elif [[ -w "$_amd_boost" ]]; then
        HAS_TURBO_CTRL=1; t_echo "  [✓] Turbo control active (amd boost node)"
        # Remap set_turbo to use AMD path — no_turbo logic inverted on AMD (1=boost on)
        R_NO_TURBO="amd"  # sentinel value; set_turbo checks this to use correct node
    else
        HAS_TURBO_CTRL=0; t_echo "  [~] Turbo node unavailable — scaling_max_freq is primary cap"
    fi
    unset _nt_node _amd_boost

    # Fan node — ThinkPad ACPI only; gate modprobe on DMI check  [v4.5.3]
    if (( FAN_CTRL_EN )) && [[ ! -w /proc/acpi/ibm/fan ]]; then
        local _dmi_vendor; _dmi_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "")
        if [[ "$_dmi_vendor" == *"LENOVO"* || "$_dmi_vendor" == *"Lenovo"* ]]; then
            t_echo "  [~] Fan node not writable — loading thinkpad_acpi fan_control=1"
            modprobe thinkpad_acpi fan_control=1 >/dev/null 2>&1
            sleep 0.5
        fi
        unset _dmi_vendor
    fi
    if [[ -w /proc/acpi/ibm/fan ]] && (( FAN_CTRL_EN )); then  
        HAS_FAN_NODE=1; t_echo "  [✓] Fan node writable"
    else
        HAS_FAN_NODE=0
        (( FAN_CTRL_EN == 0 )) && t_echo "  [~] Fan control disabled (FAN_CTRL_EN=0)" \
                               || t_echo "  [!] Fan node unavailable — thermal fan management disabled"
    fi 

    if (( _pf_abort )); then
        t_echo "  [!] Pre-flight found critical issues — review above"
        read -r -p "  [>] Continue anyway? [y/N]: " _pf_cont
        [[ ! "$_pf_cont" =~ ^[Yy] ]] && exit 1
    fi

    t_echo "  [✓] Pre-flight complete — capability cache set"
}

# [E10] REMOVED — Silk Mode compositor latency bypass prompt
# [E11] OS Tiering Utility (ev_tier)
# Applies nice, chrt, and taskset to matched PIDs and their TIDs.
# Used for VIP and BRIDGE processes — multithreaded-safe via TID walk.
ev_tier() {
    local pids; pids=$(pgrep -if "$1")
    if [[ -n "$pids" ]]; then
        "$BIN_RENICE" -n "$2" -p $pids >/dev/null 2>&1
        local pid _tid
        for pid in $pids; do
            "$BIN_CHRT" "$3" -p 0 "$pid" >/dev/null 2>&1
            if [[ -n "$4" ]]; then
                "$BIN_TSET" -a -cp "$4" "$pid" >/dev/null 2>&1
                # Walk TIDs — required for multithreaded processes (muffin, nemo)
                for _tid in /proc/"$pid"/task/*/; do
                    [[ -d "$_tid" ]] || continue
                    _tid=${_tid%/}; _tid=${_tid##*/}
                    "$BIN_TSET" -a -cp "$4" "$_tid" >/dev/null 2>&1 || true
                done
            fi
        done
    fi
}
# [E12] Topology portability complete — 4T/8T/12T/16T classifier implemented [v4.5.2]
# [E13] [DEFERRED:PORT-03/04] Fan node portability — hwmon fallback + discrete GPU branch

# [F] --- STAGE 0A: HW HARNESS & IRQ SCALPEL ---                           
hw_init() {
    t_echo "[+] Stage 0A: C-State kill, IRQ scalpel, RAPL..."
    init_tp
    
    # [F5] Hardened Discovery
    [[ -z "$CORE_MON" ]] && CORE_MON=1 
    CPU_FREQ_NODE="/sys/devices/system/cpu/cpu${CORE_MON}/cpufreq/scaling_cur_freq"
    [[ ! -f "$CPU_FREQ_NODE" ]] && CPU_FREQ_NODE="/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
    # Read hardware max frequency — try multiple sources, take highest value  [v4.7.1]
    # cpuinfo_max_freq can return throttled value under battery/HWP; cross-check with
    # scaling_max_freq (before freq_lock overwrites it) and take the ceiling.
    local _max_khz=0 _max_khz_node="/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq"
    [[ -f "$_max_khz_node" ]] && read -r _max_khz < "$_max_khz_node" 2>/dev/null
    # scaling_max_freq may reflect BIOS/platform limit — cross-check
    local _scale_khz=0
    read -r _scale_khz < "/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq" 2>/dev/null
    (( _scale_khz > _max_khz )) && _max_khz=$_scale_khz
    (( _max_khz > 0 )) && HW_MAX_MHZ=$(( _max_khz / 1000 ))
    [[ -f "$CPU_FREQ_NODE" ]] && HAS_FREQ_NODE=1 || HAS_FREQ_NODE=0  # gate set once; eliminates per-tick -f  [v4.4.4]
    # Pre-expand CPU sysfs path arrays — eliminates glob on every freq_lock/unlock  [v4.1.1]
    _SF_MAX_FREQ=( /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq )
    _SF_EPP=(      /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference )

    (( HAS_CPWR )) && "$BIN_CPWR" frequency-set -g powersave >/dev/null 2>&1
    freq_lock "$TARGET_MHZ"
    for _cs in /sys/devices/system/cpu/cpu*/cpuidle/state{2,3}/disable; do  # [v3.8.2:M2]
        [[ -w "$_cs" ]] && printf '1\n' > "$_cs" 2>/dev/null; done
    systemctl stop irqbalance >/dev/null 2>&1

    # [F1] RAPL & Fan Status — read system limits dynamically  [v4.5.1]
    if (( HAS_RAPL_WRITABLE )); then
        read -r R_RAPL_PL1 < "${RAPL_PATH}/constraint_0_power_limit_uw"
        read -r R_RAPL_PL2 < "${RAPL_PATH}/constraint_1_power_limit_uw"
        # Use system's existing limits as the game performance envelope  [v4.5.1]
        (( R_RAPL_PL1 > 0 )) && RAPL_PL1_UW=$R_RAPL_PL1 && RAPL_RESTORE_PL1=$R_RAPL_PL1
        (( R_RAPL_PL2 > 0 )) && RAPL_PL2_UW=$R_RAPL_PL2 && RAPL_RESTORE_PL2=$R_RAPL_PL2
        RAPL_BATTERY_PL1_UW=$(( RAPL_PL1_UW / 2 ))   # 50% throttle for battery
        RAPL_BATTERY_PL2_UW=$(( RAPL_PL2_UW / 2 ))
        printf '%s\n' "$RAPL_PL1_UW" > "${RAPL_PATH}/constraint_0_power_limit_uw"
        printf '%s\n' "$RAPL_PL2_UW" > "${RAPL_PATH}/constraint_1_power_limit_uw"
        t_echo "  [✓] RAPL Envelopes: PL1=$(( RAPL_PL1_UW/1000000 ))W PL2=$(( RAPL_PL2_UW/1000000 ))W (Battery $(( RAPL_BATTERY_PL1_UW/1000000 ))W/$(( RAPL_BATTERY_PL2_UW/1000000 ))W)"
    elif (( HAS_RAPL_NODE )); then
        t_echo "  [~] RAPL node present but read-only (AMD/amd_energy) — power limits not applied"
    fi
    [[ -w /proc/acpi/ibm/fan ]] && (( FAN_CTRL_EN )) && HAS_FAN_NODE=1 || HAS_FAN_NODE=0

    # [F2] IRQ Routing & DMA Lock
    local irq_hw_mask irq_safe_mask
    printf -v irq_hw_mask "%x" $(( 1 << CORE_WSRV ))
    printf -v irq_safe_mask "%x" $(( (1<<CORE_WSRV) | (1<<CORE_HEART) | (1<<CORE_AUDIO) | (1<<CORE_RENDER) | (1<<CORE_FEEDER) | (1<<CORE_MUD) ))
    printf '%s\n' "$irq_safe_mask" > /proc/irq/default_smp_affinity 2>/dev/null
    
    local _irq_line _irq_num
    while IFS= read -r _irq_line; do
        _irq_num="${_irq_line%%:*}"; _irq_num="${_irq_num// /}"
        [[ -z "$_irq_num" || ! "$_irq_num" =~ ^[0-9]+$ ]] && continue
        case "$_irq_line" in
            *i915*|*" xe"*|*amdgpu*|*radeon*|*nvme*|*xhci*|*AudioDSP*|*snd_hda*|*HDA*)
                printf '%s\n' "$irq_hw_mask" > "/proc/irq/$_irq_num/smp_affinity" 2>/dev/null ;;
        esac
    done < /proc/interrupts

    [[ -w /dev/cpu_dma_latency ]] && { bash -c "exec 3>/dev/cpu_dma_latency; printf '\x64\x00\x00\x00' >&3; sleep infinity" & LOCK_PID=$!; HAS_DMA_LATENCY=1; t_echo "  [✓] DMA lock engaged (PID=${LOCK_PID})"; }

    # [F3] GPU Clock Lock — Intel (gt_max_freq_mhz) and AMD/amdgpu (pp_dpm_sclk)  [v4.7]
    local card_dir; for card_dir in /sys/class/drm/card*/; do
        # Intel iGPU path
        [[ -f "${card_dir}gt_max_freq_mhz" ]] && {
            GPU_MAX_NODE="${card_dir}gt_max_freq_mhz"; GPU_MIN_NODE="${card_dir}gt_min_freq_mhz"; GPU_CUR_NODE="${card_dir}gt_cur_freq_mhz"
            HAS_GPU_NODE=1
            local _hw_gpu_max; read -r _hw_gpu_max < "$GPU_MAX_NODE" 2>/dev/null
            (( _hw_gpu_max > 0 )) && GPU_LOCK_MHZ=$_hw_gpu_max && GPU_GAME_MHZ=$_hw_gpu_max
            { printf '%s\n' "$GPU_LOCK_MHZ" > "$GPU_MAX_NODE" && printf '%s\n' "$GPU_LOCK_MHZ" > "$GPU_MIN_NODE"; } 2>/dev/null && t_echo "  [✓] GPU ${GPU_LOCK_MHZ}MHz locked (Intel)"
            break
        }
        # AMD/amdgpu path — Steam Deck and discrete AMD GPUs  [v4.7]
        local _dpm="${card_dir}device/pp_dpm_sclk"
        [[ -f "$_dpm" ]] && {
            HAS_GPU_NODE=1
            # Force highest DPM performance level — locks to max clock state
            local _perf_lvl="${card_dir}device/power_dpm_force_performance_level"
            if [[ -w "$_perf_lvl" ]]; then
                printf 'high\n' > "$_perf_lvl" 2>/dev/null
                # Read actual max MHz from the last DPM state entry
                GPU_LOCK_MHZ=$(awk 'END{gsub(/[^0-9]/,"",$0); print $0+0}' "$_dpm" 2>/dev/null || echo 0)
                GPU_GAME_MHZ=$GPU_LOCK_MHZ
            fi
            # Wire GPU current freq node for HUD display
            local _gpu_hwmon; _gpu_hwmon=$(find "${card_dir}device/hwmon/" -name "freq1_input" 2>/dev/null | head -1)
            [[ -f "$_gpu_hwmon" ]] && GPU_CUR_NODE="$_gpu_hwmon"
            (( GPU_LOCK_MHZ > 0 )) && t_echo "  [✓] GPU locked to high DPM state (~${GPU_LOCK_MHZ}MHz, AMD)" \
                                    || t_echo "  [~] AMD GPU found — DPM forced high, MHz unread"
            unset _dpm _perf_lvl _gpu_hwmon
            break
        }
    done
    (( HAS_GPU_NODE == 0 )) && t_echo "  [~] No lockable GPU node found — GPU clock unmanaged"

    # [F4] MSR Tuning: Prefetch MLC and Uncore Ring Bus — Intel only  [v4.5.1]
    # Uses CPU_VENDOR global set at B11b — no redundant /proc/cpuinfo read  [v4.7]
    if (( HAS_WRMSR )) && [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
        local monster_cpu=$CORE_MON _msr_1a4
        _msr_1a4=$("$BIN_RDMSR" -p "$monster_cpu" 0x1A4 2>/dev/null)
        if [[ -n "$_msr_1a4" ]]; then
            MSR_RESTORE="$_msr_1a4"; MSR_CPU="$monster_cpu"
            "$BIN_WRMSR" -p "$monster_cpu" 0x1A4 "$(( (16#${_msr_1a4}) | 0x3 ))" 2>/dev/null
            t_echo "  [✓] Prefetch: C${monster_cpu} Streamers Disabled."
        fi

        local _uncore_raw; _uncore_raw=$("$BIN_RDMSR" -d 0x620 2>/dev/null)
        if [[ -n "$_uncore_raw" ]]; then
            R_UNCORE_LIMIT="$_uncore_raw"
            local _u_max=$(( _uncore_raw & 0xFF ))
            (( _u_max < 12 )) && _u_max=12
            local _u_lock=$(( (_u_max << 8) | _u_max ))
            "$BIN_WRMSR" 0x620 "$_u_lock" 2>/dev/null
            t_echo "  [✓] Uncore: Ratio ${_u_max} locked."
        fi
    elif (( HAS_WRMSR )) && [[ "$CPU_VENDOR" != "GenuineIntel" ]]; then
        t_echo "  [~] MSR tuning skipped (vendor: ${CPU_VENDOR:-unknown} — Intel-only)"
    fi
}
                          
# [G] --- STAGE 0B: OS EVICTION & PROCESS TIERING ---
evict_chaff() {
    t_echo "[+] Stage 0B: OS eviction, tiering, network..."

    # [G1] FS remount — 60s commit reduces write pressure (ext4 only)  [v3.9.3:L2]
    if grep -q "^[^ ]* / ext4 " /proc/mounts 2>/dev/null; then
        mount -o remount,commit=60 / >/dev/null 2>&1
    fi
    # [G2] Snapshot VM/THP/sched/IRQ/ASPM tunables for cleanup restore  [v4.4.3]
    read -r R_SWAPPINESS < /proc/sys/vm/swappiness; read -r R_VFS_PRESSURE < /proc/sys/vm/vfs_cache_pressure
    read -r R_DIRTY_RATIO < /proc/sys/vm/dirty_ratio; read -r R_DIRTY_BG < /proc/sys/vm/dirty_background_ratio
    read -r _thp_e < /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || _thp_e=""
    read -r _thp_d < /sys/kernel/mm/transparent_hugepage/defrag  2>/dev/null || _thp_d=""
    _thp_e="${_thp_e#*[}"; R_THP_EN="${_thp_e%%]*}"; _thp_d="${_thp_d#*[}"; R_THP_DEFRAG="${_thp_d%%]*}"
    read -r R_SMP_AFF    < /proc/irq/default_smp_affinity 2>/dev/null   # was never snapshotted — IRQ restore was silent no-op
    read -r R_ASPM_POLICY < /sys/module/pcie_aspm/parameters/policy 2>/dev/null
    read -r R_COMPACTION  < /proc/sys/vm/compaction_proactiveness 2>/dev/null
    (( HAS_SCHED_DEBUG )) && { read -r R_SCHED_SLICE < /sys/kernel/debug/sched/base_slice_ns; read -r R_SCHED_MIG_COST < /sys/kernel/debug/sched/migration_cost_ns; }

    # [G3] Apply High-Throughput Strategy
    sysctl -w vm.swappiness=1 vm.vfs_cache_pressure=10 vm.dirty_ratio=3 vm.dirty_background_ratio=1 \
           vm.compaction_proactiveness=0 >/dev/null 2>&1                  # =0: no background compaction during gameplay
    # Note: on SteamOS some sysctl writes are silently ignored (immutable kernel params) — harmless  [v4.7]
    sw "madvise" "/sys/kernel/mm/transparent_hugepage/enabled"; sw "defer+madvise" "/sys/kernel/mm/transparent_hugepage/defrag"
    sw "performance" "/sys/module/pcie_aspm/parameters/policy"
    (( HAS_SCHED_DEBUG )) && { sw "$SCHED_BASE_SLICE_NS" "/sys/kernel/debug/sched/base_slice_ns"; sw "$SCHED_MIGRATION_COST_NS" "/sys/kernel/debug/sched/migration_cost_ns"; }

    # [G4] Service eviction — systemctl targets are cross-distro; absent services fail silently
    systemctl stop thermald packagekit speech-dispatcher bluetooth cups avahi-daemon geoclue fwupd 2>/dev/null
    # DE-agnostic process eviction — Mint/Cinnamon, KDE, GNOME patterns combined  [v4.5.3]
    # pkill returns non-zero if no match — harmless on DEs that don't have these processes
    pkill -9 -if "mintUpdate|mintreport|blueman|cinnamon-screensaver|deja-dup" 2>/dev/null
    pkill -9 -if "evolution-alarm-notify|gnome-software|speech-dispatch" 2>/dev/null
    pkill -9 -if "korgac|kdeconnectd|kscreen_backend_launcher" 2>/dev/null  # KDE non-essentials

# REMOVED [G5] Silk Mode & Compositor  [v4.2.0G:H1]
    
    # [G6] Chaff/Bridge/VIP single-pass caging
    cage_external "$(pgrep -f "$PGREP_CHAFF")" "$NICE_CHAFF" "-b" "$CORE_MUD"
    # [G7] Cache BRIDGE_PIDS and BROWSER_PIDS at boot — reused in N8 focus shift  [v4.1.0]
    BRIDGE_PIDS=$(pgrep -if "$PGREP_BRIDGE" 2>/dev/null)
    cage_external "$BRIDGE_PIDS" "$NICE_BRIDGE" "-b" "$CORE_FEEDER,$CORE_MUD"
    ev_tier "$PGREP_VIP" "$NICE_VIP" "-o"
    BROWSER_PIDS=$(pgrep -if "firefox|chrome|chromium|brave" 2>/dev/null)
    if cage_external "$BROWSER_PIDS" 10 "-b" "$CORE_BROWSER"; then
        t_echo "  [✓] Audio Guard: Browser isolated to Cores ${CORE_BROWSER}"; fi

    t_echo "  [✓] Eviction done. Ring Bus & Goliath ready."
}

# [H] --- FAST-TIER FUNCTIONS ---                                              

# [H1] AC Power Sentinel loop check
check_ac() {
    local ac_val=""
    if [[ -z "$AC_NODE" ]]; then
        local ac_node
        for ac_node in /sys/class/power_supply/A*/online; do
            [[ -f "$ac_node" ]] && AC_NODE="$ac_node" && break
        done
    fi
    [[ -z "$AC_NODE" ]] && return
    read -r ac_val < "$AC_NODE" 2>/dev/null
    [[ -z "$ac_val" ]] && return
    
    if [[ "$LAST_AC_STATUS" != "$ac_val" ]]; then
        if [[ -n "$LAST_AC_STATUS" ]]; then
            if [[ "$ac_val" == "0" ]]; then
                echo -e "\n[!] AC lost — releasing constraints"
                freq_unlock
                # [H2] Release RAPL constraints to battery uW — Intel only  [v4.7]
                if (( HAS_RAPL_WRITABLE )); then
                    printf '%s\n' "$RAPL_BATTERY_PL1_UW" > "${RAPL_PATH}/constraint_0_power_limit_uw" 2>/dev/null
                    printf '%s\n' "$RAPL_BATTERY_PL2_UW" > "${RAPL_PATH}/constraint_1_power_limit_uw" 2>/dev/null
                fi
                lg "AC LOST — Hardware constraints released"
            else
                # [H3] Truncate timestamp for AC restore safety
                local _now_ac=${EPOCHREALTIME%%.*}
                if (( _now_ac - HW_INIT_TS >= 30 )); then
                    echo -e "\n[+] AC restored — re-engaging hardware harness"
                    HW_INIT_TS=$_now_ac
                    hw_init >/dev/null 2>&1
                    lg "AC RESTORED — Harness re-engaged"
                fi
            fi
        fi
        LAST_AC_STATUS="$ac_val"
    fi
}

# [H4] Thermal Monitoring & Fan State Machine
mng_thm() {
    if [[ -f "$THM_PATH" ]]; then
        local RAW_TEMP=0
        read -r RAW_TEMP < "$THM_PATH" 2>/dev/null
        if [[ -n "$RAW_TEMP" && "$RAW_TEMP" -gt 0 ]]; then
            CPU_TEMP=$((RAW_TEMP / 1000))
        else
            CPU_TEMP="--"; return  # bad probe — skip threshold comparisons entirely
        fi

        # [H4b] Thermal purge only triggers in GAME state — in DESKTOP the CPU is
        # free-running by design (turbo on, freq unlocked). Fan engages but no
        # clock intervention needed; a purge would be counterproductive.  [v4.0.4]
        if [[ "$CPU_TEMP" -ge $THM_THR && "$FAN_IS_LOCKED" -eq 0 && "$SYS_STATE" == "GAME" ]]; then
            echo -e "\n"
            t_echo "[!] Thermal Threshold Hit (${CPU_TEMP}°C)! Purging heat for 30s..."
            (( HAS_FAN_NODE )) && printf "level full-speed\n" > /proc/acpi/ibm/fan 2>/dev/null
            set_turbo 1  # ensure turbo is off during purge — prevents boosting while hot
            FAN_IS_LOCKED=1
            FAN_TIMER=30
            # [H5] Truncate timestamp to avoid FP syntax errors
            FAN_START_TS=${EPOCHREALTIME%%.*}
        elif [[ "$CPU_TEMP" -ge $THM_THR && "$FAN_IS_LOCKED" -eq 0 && "$SYS_STATE" == "DESKTOP" ]]; then
            # DESKTOP thermal — fan only, no clock intervention
            (( HAS_FAN_NODE )) && printf "level full-speed\n" > /proc/acpi/ibm/fan 2>/dev/null
        fi
    else
        CPU_TEMP="--"
    fi

    if [[ "$FAN_IS_LOCKED" -eq 1 ]]; then
        local _now_s=${EPOCHREALTIME%%.*}
        local _start_s=$FAN_START_TS
        local _elapsed_s=$(( _now_s - _start_s ))
        FAN_TIMER=$(( 30 - _elapsed_s ))

        if [[ "$FAN_TIMER" -le 0 ]]; then
            echo -e "\n"
            t_echo "[!] Purge Complete. Restoring Fan Control..."
            if (( HAS_FAN_NODE )); then
                printf "level 0\n" > /proc/acpi/ibm/fan 2>/dev/null
                sleep 2
                printf "level auto\n" > /proc/acpi/ibm/fan 2>/dev/null
            fi
            FAN_IS_LOCKED=0
            FAN_START_TS=0
            # Restore turbo to current state context — GAME stays locked, DESKTOP re-enables
            [[ "$SYS_STATE" == "DESKTOP" ]] && set_turbo 0 || set_turbo 1
            t_echo " [✓] Silence Restored."
        fi
    fi
}

# [H6] Interactive Hotkey Handler
handle_keypress() {
    local key="$1"
    case "$key" in
        p|P) local _tty_state _tel_was; _tty_state=$(stty -g 2>/dev/null); stty sane 2>/dev/null
            # Suspend telemetry window to prevent elapsed-time corruption while frozen  [v4.4.2]
            _tel_was=$TEL_EN; TEL_EN=0
            echo -e "\n[!] FROZEN — copy now. Press [ENTER] to resume..."
            read -s < /dev/tty
            echo "[+] Resuming..."
            # Restore telemetry and re-seed baselines so the remainder of the window is clean
            TEL_EN=$_tel_was; [[ $TEL_EN -eq 1 ]] && tel_start
            [[ -n "$_tty_state" ]] && stty "$_tty_state" 2>/dev/null ;;
        b|B) benchmark ;;
        h|H) echo -e "\n  ┌─ HOTKEYS ─────────────────────────────────────────────────\n  │  [F] CPU MHz     [G] GPU MHz\n  │  [T] Telemetry   [P] Freeze\n  │  [L] Log viewer  [R] Re-arm\n  │  [B] Benchmark   [U] Dump\n  │  [I] Schedstat   [C] Cache stats (DESKTOP only)\n  │  [H] Help        Ctrl+C to quit and restore\n  └────────────────────────────────────────────────────────────" ;;
        f|F) local _tty_state; _tty_state=$(stty -g 2>/dev/null); local new_game_mhz="" new_desk_mhz=""
            stty sane 2>/dev/null; echo -e "\n  [i] CPU: Game=${GAME_MHZ}MHz Desktop=${DSK_MHZ}MHz"
            read -r -p "  [>] Game MHz [${GAME_MHZ}]: " new_game_mhz < /dev/tty; read -r -p "  [>] Desktop MHz [${DSK_MHZ}]: " new_desk_mhz < /dev/tty
            local _changed=0; [[ "$new_game_mhz" =~ ^[0-9]+$ ]] && GAME_MHZ="$new_game_mhz" && _changed=1
            [[ "$new_desk_mhz" =~ ^[0-9]+$ ]] && DSK_MHZ="$new_desk_mhz" && _changed=1
            if (( _changed )); then TARGET_MHZ="$GAME_MHZ"; freq_lock "$TARGET_MHZ"; echo "  [+] CPU locked to ${TARGET_MHZ}MHz."; fi
            [[ -n "$_tty_state" ]] && stty "$_tty_state" 2>/dev/null ;;
        g|G) local _tty_state; _tty_state=$(stty -g 2>/dev/null); stty sane 2>/dev/null  # [v3.8.5:M1] stty guard added
            echo -e "\n"; local _live_gpu="---" new_gpu_game=""; [[ -f "$GPU_CUR_NODE" ]] && read -r _live_gpu < "$GPU_CUR_NODE" 2>/dev/null  # [v3.8.0:L1]
            read -r -p "  [>] Game GPU MHz [${GPU_GAME_MHZ}]: " new_gpu_game < /dev/tty
            [[ "$new_gpu_game" =~ ^[0-9]+$ ]] && GPU_GAME_MHZ="$new_gpu_game" && GPU_LOCK_MHZ="$new_gpu_game"
            if [[ -n "$GPU_MAX_NODE" && -e "$GPU_MAX_NODE" ]]; then printf '%s\n' "$GPU_GAME_MHZ" > "$GPU_MAX_NODE" 2>/dev/null; printf '%s\n' "$GPU_GAME_MHZ" > "$GPU_MIN_NODE" 2>/dev/null; echo "  [+] GPU profile applied."; fi
            [[ -n "$_tty_state" ]] && stty "$_tty_state" 2>/dev/null ;;
        l|L) local _tty_state; _tty_state=$(stty -g 2>/dev/null); stty sane 2>/dev/null; echo -e "\n"
            if [[ -n "$SES_LOG" && -f "$SES_LOG" ]]; then less -eK +G "$SES_LOG" < /dev/tty > /dev/tty 2>/dev/null; else echo "  [!] No active log."; fi
            [[ -n "$_tty_state" ]] && stty "$_tty_state" 2>/dev/null ;;
        t|T) TEL_EN=$((1 - TEL_EN)); [[ $TEL_EN -eq 1 ]] && tel_start ;;
        r|R) echo -e "\n[+] Re-Arm: Goliath extraction..."; MON_ID=""; MGR_ID=""; G_VLD=0; inv_tc; FORCE_MEDIUM=1; cls_th 2>/dev/null; echo "  [✓] MON=${MON_ID} MGR=${MGR_ID}" ;;
        u|U) local _tty_state; _tty_state=$(stty -g 2>/dev/null); stty sane 2>/dev/null  # [v3.8.5:M1]
            echo -e "\n  ┌─ THREAD DUMP ───────────────────────────────"
            while IFS=" " read -r dtid dcore dcpu dwchan; do
                t_cls "$dtid" hits
                printf "  │ %-7s %-11s %-5s %s\n" "$dtid" "$THREAD_CLASS" "$dcpu" "$dwchan"
            done < <(ps -L -p "$PSOBB_PID" -o lwp,psr,pcpu,wchan:24 --no-headers 2>/dev/null)
            [[ -n "$_tty_state" ]] && stty "$_tty_state" 2>/dev/null ;;
        i|I) local _tty_state; _tty_state=$(stty -g 2>/dev/null); stty sane 2>/dev/null  # [v3.8.5:M1]
            echo -e "\n  ┌─ SCHEDSTAT ──────────────────────"
            for stid_dir in /proc/"$PSOBB_PID"/task/*; do
                local stid=${stid_dir##*/}
                local s_exec=0 s_wait=0
                read -r s_exec s_wait _ < "$stid_dir/schedstat" 2>/dev/null
                r_csw "$stid_dir/status"
                if (( s_exec > 0 )); then
                    t_cls "$stid"
                    printf "  │ %-7s %-11s %5d%% %8s %7s\n" \
                        "$stid" "$THREAD_CLASS" \
                        "$(( s_exec*100/(s_exec+s_wait+1) ))" \
                        "$_READ_VOL" "$_READ_NONVOL"
                fi
            done
            [[ -n "$_tty_state" ]] && stty "$_tty_state" 2>/dev/null ;;
        c|C) # [H6:C] Cache stats — DESKTOP state only; perf blocks for sample duration  [v4.0.2]
            if [[ "$SYS_STATE" != "DESKTOP" ]]; then
                echo -e "\n  [~] Cache stats available in DESKTOP state only (game must be unfocused)"
            elif ! command -v perf >/dev/null 2>&1; then
                echo -e "\n  [!] perf not installed — install 'perf' or 'linux-tools' via your package manager"
            else
                # Write confirmed MON_ID for cache_stats to consume
                [[ -n "$MON_ID" ]] && echo "$MON_ID" > /tmp/apxp_mon_tid 2>/dev/null
                local _cs_path="${USER_HOME}/Desktop/cache_stats.sh"
                if [[ ! -f "$_cs_path" ]]; then
                    echo -e "\n  [!] cache_stats.sh not found at ${_cs_path}"
                else
                    echo -e "\n  [~] Launching cache stats in new terminal (MON_ID=${MON_ID})..."
                    sudo -u "$SUDO_USER" env DISPLAY="$DISPLAY_ID" XAUTHORITY="$XAUTH_PATH" \
                        x-terminal-emulator -e "sudo bash ${_cs_path}" &
                fi
            fi ;;
    esac
}

# [I] --- GOLIATH & THREAD CLASSIFICATION ---

# [I1] Thread Class Resolver — O(1) TC_CLASS lookup; fallback to FEEDER/MUD  [v4.0.18]
t_cls() {
    local _tid="$1" _hits_mode="${2:-}"; THREAD_CLASS="MUD"
    # [I2] Fast path: TC_CLASS populated at I13 — one hash lookup for all named threads
    if [[ -n "${TC_CLASS[$_tid]+x}" ]]; then
        THREAD_CLASS="${TC_CLASS[$_tid]}"
        return
    fi
    # [I2] FEEDER check — dynamic set, not in TC_CLASS
    if [[ -n "${FEEDER_SET[$_tid]+x}" ]]; then
        THREAD_CLASS="FEEDER$([[ "$_hits_mode" == "hits" ]] && echo "(hits:${MF_HITS[$_tid]:-0})")"; return
    fi
    # [I3] MUD hit-count annotation
    [[ "$_hits_mode" == "hits" ]] && (( MF_HITS[$_tid] > 0 )) && THREAD_CLASS="MUD(hits:${MF_HITS[$_tid]})"
}

# [I4] Single-Pass Classification & Goliath
cls_th() {
    # [I5] Discovery
    [[ -z "$PSOBB_PID" || ! -d "/proc/$PSOBB_PID" ]] && { PSOBB_PID=$(pgrep -nx "psobb.exe"); [[ -z "$PSOBB_PID" ]] && return; }
    HEART_ID="$PSOBB_PID"
    # Pre-build path caches — eliminates inline string interpolation at 32 sites  [v4.1.1]
    TASK_BASE="/proc/$PSOBB_PID/task"
    HEART_SCHED_PATH="$TASK_BASE/$HEART_ID/schedstat"
    [[ -z "$WSRV_PIDS" || "$G_VLD" -eq 0 ]] && WSRV_PIDS=$(pgrep -fi "wineserver")

    # [I6] Pipeline verification — skip Pass 1 if named IDs still valid
    local _p1_skip=0
    if (( G_VLD == 1 )); then
        _p1_skip=1
        for _v in "$SUBMIT_ID:dxvk-submit" "$CS_ID:dxvk-cs"; do
            [[ ! -f "/proc/$PSOBB_PID/task/${_v%%:*}/comm" ]] && _p1_skip=0 && break
        done
    fi

    if (( _p1_skip == 0 )); then
        # [I7] Pass 1: Named Threads (Hardened Discovery)
        for tdir in /proc/"$PSOBB_PID"/task/*; do
            local tid=${tdir##*/}; local comm=""; read -r comm < "$tdir/comm" 2>/dev/null
            case "$comm" in
                "dxvk-submit") SUBMIT_ID="$tid" ;;
                "dxvk-cs") CS_ID="$tid" ;;
                "dxvk-queue") Q_ID="$tid" ;;
                "dxvk-frame") FRAME_ID="$tid" ;;
                "wine_dinput_wor") DINPUT_ID="$tid" ;;
                *"shader"*)  # [v3.9.7:M1] glob: catches dxvk-shader-h/l and any variant
                    if [[ -z "$SHADER_H_ID" ]]; then SHADER_H_ID="$tid"; unset "TC_CORE[$tid]"   # [v4.4.9] evict stale MUD placement
                    elif [[ -z "$SHADER_L_ID" ]]; then SHADER_L_ID="$tid"; unset "TC_CORE[$tid]"; fi ;;
                *"audio"*|*"snd"*|*"dsound"*|*"mmdevapi"*|*"winepulse"*|*"winealsa"*|*"RtpPrio"*)
                    # sub-classify by comm substring: ti→TI timer, mix→MIX pipe, else→MA main
                    if [[ "$comm" =~ "ti" ]]; then AUDIO_TI_ID="$tid"
                    elif [[ "$comm" =~ "mix" ]]; then AUDIO_MIX_ID="$tid"
                    else AUDIO_ID="$tid"; fi ;;
            esac
        done
        # Pre-build Q schedstat path after Pass 1 — stable until next inv_tc  [v4.1.1]
        [[ -n "$Q_ID" ]] && Q_SCHED_PATH="$TASK_BASE/$Q_ID/schedstat"
    fi  # [v3.7.5:I7] Pass 1 close — Pass 2 is unconditional

    # [I7b] AUDIO_ID fallback — if TI+MIX found but MA still empty after Pass 1,
    # find the unclaimed thread whose exec_ns is closest to AUDIO_TI_ID.
    # MA feeds the pipe that MIX reads — it should have comparable exec to TI.
    # Logs the actual comm for permanent I7 pattern update.  [v4.0.4]
    if [[ -z "$AUDIO_ID" && -n "$AUDIO_TI_ID" && -n "$AUDIO_MIX_ID" ]]; then
        local _ti_exec=0
        read -r _ti_exec _ < "/proc/$PSOBB_PID/task/$AUDIO_TI_ID/schedstat" 2>/dev/null
        local _ma_best_delta=999999999 _ma_tid="" _ma_comm=""
        for tdir in /proc/"$PSOBB_PID"/task/*; do
            local _atid=${tdir##*/}
            [[ "$_atid" == "$HEART_ID"    || "$_atid" == "$MON_ID"      || \
               "$_atid" == "$MGR_ID"      || "$_atid" == "$SUBMIT_ID"   || \
               "$_atid" == "$CS_ID"       || "$_atid" == "$Q_ID"        || \
               "$_atid" == "$FRAME_ID"    || "$_atid" == "$DINPUT_ID"   || \
               "$_atid" == "$SHADER_H_ID" || "$_atid" == "$SHADER_L_ID" || \
               "$_atid" == "$AUDIO_TI_ID" || "$_atid" == "$AUDIO_MIX_ID" ]] && continue
            local _ae=0; read -r _ae _ < "$tdir/schedstat" 2>/dev/null
            (( _ae == 0 )) && continue  # skip idle/zero threads
            local _delta=$(( _ae > _ti_exec ? _ae - _ti_exec : _ti_exec - _ae ))
            if (( _delta < _ma_best_delta )); then
                local _ac=""; read -r _ac < "$tdir/comm" 2>/dev/null
                _ma_best_delta=$_delta; _ma_tid=$_atid; _ma_comm="$_ac"
            fi
        done
        if [[ -n "$_ma_tid" ]]; then
            AUDIO_ID="$_ma_tid"
            lg "AUDIO_ID fallback: TID=${_ma_tid} comm=[${_ma_comm}] exec_delta=${_ma_best_delta}ns — add comm to I7 if confirmed"
            t_echo "  [~] AUDIO_MA fallback: TID=${_ma_tid} comm=[${_ma_comm}]"
        fi
    fi

        # [I8] Pass 2: Goliath Extraction
        if [[ -z "$MON_ID" || "$G_VLD" -eq 0 ]]; then
        # [I9] Step A: Candidates — collect unclaimed threads by CPU tick count
        local -a THREAD_TICKS=()
        for tdir in /proc/"$PSOBB_PID"/task/*; do
            local tid=${tdir##*/}
            [[ "$tid" == "$HEART_ID" ]] && continue           # [v3.8.7:L1]
            local comm=""
            read -r comm < "$tdir/comm" 2>/dev/null
            [[ "$comm" =~ (dxvk|glthread|wine_|audio|WSI|shader) ]] && continue
            local _s=""
            read -r _s < "$tdir/stat" 2>/dev/null
            if [[ -n "$_s" ]]; then
                _s="${_s##*) }"; local -a _sf=( $_s )
                THREAD_TICKS+=( "$(( _sf[11] + _sf[12] )):$tid" )
            fi
        done
        (( ${#THREAD_TICKS[@]} < 2 )) && { G_VLD=0; return; }

        # Top-2 insertion sort — forkless, O(n) single pass
        local _tk _t _i _b1t=0 _b1i="" _b2t=0 _b2i=""
        for _tk in "${THREAD_TICKS[@]}"; do
            _t=${_tk%%:*}; _i=${_tk##*:}
            if (( _t > _b1t )); then
                _b2t=$_b1t; _b2i=$_b1i; _b1t=$_t; _b1i=$_i
            elif (( _t > _b2t )); then
                _b2t=$_t; _b2i=$_i
            fi
        done
        
        if (( G_STATE == 0 )); then
            # [I10] Arm: snapshot exec_ns, utime, heart ctx-switches  [v3.7.7:I10]
            G_CAND_A=$_b1i; G_CAND_B=$_b2i
            G_T0_TS=${EPOCHREALTIME/./}
            G_T0_A_EXEC=0; G_T0_B_EXEC=0; G_T0_A_UTIME=0; G_T0_B_UTIME=0; G_T0_HEART=0
            local _ga_sched _gb_sched _ga_stat _gb_stat
            [[ -f "/proc/$PSOBB_PID/task/$G_CAND_A/schedstat" ]] && read -r G_T0_A_EXEC _ _ < "/proc/$PSOBB_PID/task/$G_CAND_A/schedstat" 2>/dev/null
            [[ -f "/proc/$PSOBB_PID/task/$G_CAND_B/schedstat" ]] && read -r G_T0_B_EXEC _ _ < "/proc/$PSOBB_PID/task/$G_CAND_B/schedstat" 2>/dev/null
            if read -r _ga_stat < "/proc/$PSOBB_PID/task/$G_CAND_A/stat" 2>/dev/null && [[ -n "$_ga_stat" ]]; then
                _ga_stat="${_ga_stat##*) }"; local -a _ga_sf=($_ga_stat); G_T0_A_UTIME=$(( _ga_sf[11] + _ga_sf[12] )); fi
            if read -r _gb_stat < "/proc/$PSOBB_PID/task/$G_CAND_B/stat" 2>/dev/null && [[ -n "$_gb_stat" ]]; then
                _gb_stat="${_gb_stat##*) }"; local -a _gb_sf=($_gb_stat); G_T0_B_UTIME=$(( _gb_sf[11] + _gb_sf[12] )); fi
            [[ -n "$HEART_SCHED_PATH" ]] && r_sw "$HEART_SCHED_PATH" && G_T0_HEART=$_READ_VOL
            G_STATE=1; G_VLD=0; lg "Goliath: Armed A=$G_CAND_A B=$G_CAND_B"

        else
            # [I11] Evaluate: apply I19/I20/I21 gates before confirming  [v3.7.7:I11]
            local _g1_exec=0 _g1_utime=0 _g_heart_now=0 _g_elapsed_s=0 _g_reset=0
            local _g_now_ts=${EPOCHREALTIME/./}
            _g_elapsed_s=$(( (_g_now_ts - G_T0_TS) / 1000000 )); (( _g_elapsed_s <= 0 )) && _g_elapsed_s=1

            # [I19] Heart_rate gate — abort if engine is idle (not in gameplay)
            if [[ -n "$HEART_ID" ]]; then
                r_sw "$HEART_SCHED_PATH"
                _g_heart_now=$_READ_VOL
                local _heart_rate=$(( (_g_heart_now - G_T0_HEART) / _g_elapsed_s ))
                if (( _heart_rate < GOL_HEART_RDY )); then
                    G_STATE=0; G_VLD=0; _g_reset=1; lg "Goliath: I19 heart_rate=${_heart_rate} < ${GOL_HEART_RDY} — re-arm"; fi
            fi

            if (( _g_reset == 0 )); then
                # [I20] Ambiguity gate — exec_ns delta must be nonzero; utime must confirm rank order
                [[ -f "/proc/$PSOBB_PID/task/$G_CAND_A/schedstat" ]] && read -r _g1_exec _ _ < "/proc/$PSOBB_PID/task/$G_CAND_A/schedstat" 2>/dev/null
                local _exec_delta=$(( _g1_exec - G_T0_A_EXEC ))
                if read -r _ga_stat < "/proc/$PSOBB_PID/task/$G_CAND_A/stat" 2>/dev/null && [[ -n "$_ga_stat" ]]; then
                    _ga_stat="${_ga_stat##*) }"; local -a _ga_sf=($_ga_stat); _g1_utime=$(( _ga_sf[11] + _ga_sf[12] )); fi
                local _utime_delta=$(( _g1_utime - G_T0_A_UTIME ))
                if (( _exec_delta <= 0 || _utime_delta <= 0 )); then
                    G_STATE=0; G_VLD=0; _g_reset=1; lg "Goliath: I20 exec_delta=${_exec_delta} utime_delta=${_utime_delta} — re-arm"; fi
            fi

            if (( _g_reset == 0 )); then
                # [I21] Phase E gate — candidate A CPU% must be within MON_CPU_FLOOR..MON_CPU_CEIL
                local _g_jif=$(( _g_elapsed_s * CLK_TCK )); (( _g_jif <= 0 )) && _g_jif=1
                PHASE_E_PCT=$(( (_utime_delta * 100) / _g_jif ))
                if (( PHASE_E_PCT < MON_CPU_FLOOR || PHASE_E_PCT > MON_CPU_CEIL )); then
                    G_STATE=0; G_VLD=0; _g_reset=1; lg "Goliath: I21 PHASE_E_PCT=${PHASE_E_PCT} outside [${MON_CPU_FLOOR},${MON_CPU_CEIL}] — re-arm"; fi
            fi

            # [I12] All gates passed — confirm
            if (( _g_reset == 0 )); then
                G_VLD=1; G_STATE=0; MON_ID=$G_CAND_A; MGR_ID=$G_CAND_B; inv_critical
                MON_SCHED_PATH="$TASK_BASE/$MON_ID/schedstat"  # [v4.1.1]
                t_echo "  [✓] Goliath: MON=${MON_ID} MGR=${MGR_ID} PHASE_E=${PHASE_E_PCT}%"  # [v4.4.9]
                lg "Goliath: CONFIRMED MON=$MON_ID MGR=$MGR_ID PHASE_E=${PHASE_E_PCT}%"; fi
        fi
    fi
    
# [I13] Pass 3: Construct association pools — gated on topology change  [v3.9.8:M2]
# ⚠ STABILITY NOTE: When G_VLD=1 and TID count stable, CLAIMED/MUD_IDS reuse prior cycle.
#   Safe because named IDs are fixed until next inv_tc(). MUD_IDS may include newly spawned
#   Wine threads on the next churn-triggered MT cycle (CUR_TID_COUNT != LAST_TID_COUNT in N15).
    if (( G_VLD == 0 || MT_DUE == 1 )); then
        CLAIMED=(); TC_CLASS=()
        # Build TID→class map imperatively — literal initializer evaluates subscripts at
        # construction time, emitting "bad array subscript" for any unset ID  [v4.4.8]
        local -A _id_map=()
        local -a _id_pairs=(
            "$HEART_ID"    "HEART"        "$MON_ID"       "MON"         "$MGR_ID"       "MGR"
            "$SUBMIT_ID"   "DXVK_SUBMIT"  "$CS_ID"        "DXVK_CS"    "$Q_ID"         "DXVK_Q"
            "$FRAME_ID"    "DXVK_FRAME"   "$DINPUT_ID"    "DINPUT"
            "$SHADER_H_ID" "SHADER_H"     "$SHADER_L_ID"  "SHADER_L"
            "$AUDIO_ID"    "AUDIO_MA"     "$AUDIO_TI_ID"  "AUDIO_TI"   "$AUDIO_MIX_ID" "AUDIO_MIX"
            "$WSI_Q_ID"    "WSI_Q"        "$WSI_E_ID"     "WSI_E"
        )
        local _ip; for (( _ip=0; _ip<${#_id_pairs[@]}; _ip+=2 )); do
            [[ -n "${_id_pairs[_ip]}" ]] && _id_map["${_id_pairs[_ip]}"]="${_id_pairs[_ip+1]}"
        done
        local _id _cls
        for _id in "${!_id_map[@]}"; do
            [[ -z "$_id" ]] && continue
            _cls="${_id_map[$_id]}"
            CLAIMED[$_id]=1
            TC_CLASS[$_id]="$_cls"
        done
        # Build shared task path list — pin_th and feeder reuse this, no re-glob  [v4.0.20]
        MUD_IDS=(); _TASK_DIRS=()
        for tdir in /proc/"$PSOBB_PID"/task/*; do
            [[ -d "$tdir" ]] || continue
            _TASK_DIRS+=("$tdir")
            tid=${tdir##*/}; [[ -z "${CLAIMED[$tid]+x}" ]] && MUD_IDS+=("$tid")
        done
    fi
}

# [J] --- MEDIUM-TIER FUNCTIONS ---

# [J5] Topology Application entry  [v4.4.9]
# TC_CLASS built at I13 drives dispatch — comm read deferred to unclassified threads only.
# ~14 /proc/comm reads per MT fire eliminated (~70/window at MT_INTV=3).
# BATCH assignment absorbed from set_pr into J11 — set_pr now a stub.
pin_th() {
    [[ -z "$PSOBB_PID" ]] && return
    local tid _cls tdir comm
    # [J5] Reuse _TASK_DIRS built at I13 — eliminates redundant /proc/task glob  [v4.0.20]
    for tdir in "${_TASK_DIRS[@]}"; do
        [[ -d "$tdir" ]] || continue
        tid=${tdir%/}; tid=${tid##*/}
        [[ -n "${FEEDER_SET[$tid]+x}" ]] && continue

        # Fast path: TC_CLASS populated at I13 — dispatch without comm read  [v4.4.9]
        _cls="${TC_CLASS[$tid]:-}"
        if [[ -z "$_cls" ]]; then
            # Unclassified — read comm for WSI/shader discovery and MUD fallback
            read -r comm < "${tdir}/comm" 2>/dev/null
            if [[ -z "$SHADER_H_ID" && "$comm" =~ "shader" ]]; then
                SHADER_H_ID="$tid"; unset "TC_CORE[$tid]"; _cls="SHADER_H"
            elif [[ -z "$SHADER_L_ID" && "$comm" =~ "shader" ]]; then
                SHADER_L_ID="$tid"; unset "TC_CORE[$tid]"; _cls="SHADER_L"
            elif [[ -z "$WSI_E_ID" && "$comm" =~ ^"WSI swapchain e" ]]; then
                WSI_E_ID="$tid"; _cls="WSI_E"
            elif [[ -z "$WSI_Q_ID" && "$comm" =~ ^"WSI swapchain q" ]]; then
                WSI_Q_ID="$tid"; _cls="WSI_Q"
            elif [[ "$comm" =~ WSI ]]; then
                _cls="WSI_GENERIC"
            fi
        fi

        case "$_cls" in
            # [J6] Engine
            HEART)        c_renice "$tid" "$NICE_CRIT";     c_tset "$tid" "$CORE_HEART" ;;
            # [J7] Render pipeline
            DXVK_SUBMIT)  c_renice "$tid" "$NICE_CRIT";     c_tset "$tid" "$CORE_FEEDER" ;;
            DXVK_CS)      c_renice "$tid" "$NICE_DXVK_CS";  c_tset "$tid" "$CORE_RENDER" ;;
            DXVK_Q)       c_renice "$tid" "$NICE_CRIT";     c_tset "$tid" "$CORE_RENDER" ;;
            DXVK_FRAME)   c_renice "$tid" "$NICE_MUD_ENFORCE"; c_tset "$tid" "$CORE_FRAME" ;;
            SHADER_H)     c_renice "$tid" "$NICE_DXVK_CS";    c_tset "$tid" "$CORE_RENDER" ;;
            # SHADER_L note: 0.0/s idle thread — kernel freely migrates between MT cycles.
            # Telemetry will show varying cores; c_tset corrects on each MT fire. Cosmetic only.
            SHADER_L)     c_renice "$tid" "$NICE_MUD_ENFORCE"; c_tset "$tid" "$CORE_RENDER" ;;
            # [J8] WSI presentation  [v4.0.11:CS-01]
            WSI_E|WSI_Q)  c_chrt "-r" 45 "$tid";            c_tset "$tid" "$CORE_HEART" ;;
            WSI_GENERIC)  c_renice "$tid" "$NICE_CRIT"
                          [[ "$comm" =~ [Ee]vent|[Ee]xecut ]] && c_tset "$tid" "$CORE_HEART" \
                                                               || c_tset "$tid" "$CORE_RENDER" ;;
            # [J9] Audio RT hierarchy  [v3.9.7:M2]
            AUDIO_TI)     c_chrt "-r" 45 "$tid";            c_tset "$tid" "$CORE_AUDIO" ;;
            AUDIO_MIX)    c_chrt "-r" 40 "$tid";            c_tset "$tid" "$CORE_AUDIO" ;;
            AUDIO_MA)     c_chrt "-r" 35 "$tid";            c_tset "$tid" "$CORE_AUDIO" ;;
            # [J10] DINPUT + Goliath
            DINPUT)       c_renice "$tid" "$NICE_CRIT";     c_tset "$tid" "$CORE_HEART" ;;
            # MON/MGR: bypass c_tset cache — TC_CORE stale after Goliath re-arm cycles caused  [v4.5.0]
            # drift (4/8 windows on wrong core, confirmed via CSV). Direct write guarantees pin
            # every MT fire. Cost: 2 taskset syscalls per MT fire — negligible vs correctness.
            MON)          c_renice "$tid" "$NICE_CRIT"
                          "$BIN_TSET" -cp "$CORE_MON" "$tid" >/dev/null 2>&1; TC_CORE[$tid]="$CORE_MON" ;;
            MGR)          c_renice "$tid" "$NICE_CRIT"
                          "$BIN_TSET" -cp "$CORE_MGR" "$tid" >/dev/null 2>&1; TC_CORE[$tid]="$CORE_MGR" ;;
            # [J11] MUD residency + BATCH — absorbs set_pr BATCH assignment  [v4.4.9]
            *)            (( G_VLD )) && c_renice "$tid" "$NICE_MUD_APPLY" \
                                      || c_renice "$tid" "$NICE_MUD_ENFORCE"
                          c_tset "$tid" "$CORE_MUD"
                          [[ "${TC_NICE[${tid}_sched]}" != "BATCH" ]] && {
                              "$BIN_CHRT" -b -p 0 "$tid" >/dev/null 2>&1
                              TC_NICE[${tid}_sched]="BATCH"
                          } ;;
        esac
    done

    # [J5b] Feeder rebuild — ctx-switch rate scan over unclaimed threads  [v3.7.5:J5]
    local now_ms=${EPOCHREALTIME/./}; local elapsed=$(( now_ms - FEEDER_LAST_TS ))
    local el_s=$(( elapsed / 1000000 )); (( el_s <= 0 )) && el_s=1; FEEDER_LAST_TS=$now_ms
    FEEDER_IDS=(); FEEDER_SET=()
    for tdir in "${_TASK_DIRS[@]}"; do
        [[ -d "$tdir" ]] || continue
        local ftid=${tdir%/}; ftid=${ftid##*/}
        [[ -n "${CLAIMED[$ftid]+x}" ]] && continue  # skip named/goliath threads
        r_sw "$tdir/schedstat"
        local f_total=$_READ_VOL
        local f_prev=${MF_SW[$ftid]:-0}
        local f_delta=$(( f_total - f_prev ))
        MF_SW[$ftid]=$f_total
        local f_rate=$(( f_delta / el_s ))
        if (( f_rate >= FEEDER_RATE_THRESH )); then
            MF_HITS[$ftid]=$(( ${MF_HITS[$ftid]:-0} + 1 ))
            if (( MF_HITS[$ftid] >= FEEDER_CONFIRM_CYCLES )); then
                FEEDER_IDS+=("$ftid"); FEEDER_SET[$ftid]=1
                c_renice "$ftid" "$NICE_FEEDER"; c_tset "$ftid" "$CORE_FEEDER"
            fi
        else
            (( ${MF_HITS[$ftid]:-0} > 0 )) && MF_HITS[$ftid]=$(( MF_HITS[$ftid] - 1 ))
        fi
    done
    
    # Wineserver residency
    for ws_pid in $WSRV_PIDS; do c_renice "$ws_pid" "$NICE_WSRV"; c_tset "$ws_pid" "$CORE_WSRV"; done
}
# [K] --- TELEMETRY ---

# [K1] Telemetry Start entry
tel_start() {
    # [K2] Seed baselines — reset arrays, timestamp; reuse _TASK_DIRS if valid  [v4.1.0]
    # MUD threads skip stat read — CPU delta ~0 for idle threads; tel_end clamps negatives
    T_START_SW=(); T_START_CPU=(); T_START_TS=${EPOCHREALTIME/./}; [[ -z "$PSOBB_PID" ]] && return
    local _tlist
    if (( G_VLD == 1 && ${#_TASK_DIRS[@]} > 0 )); then
        _tlist=( "${_TASK_DIRS[@]}" )
    else
        _tlist=( /proc/"$PSOBB_PID"/task/* )
    fi
    for tdir in "${_tlist[@]}"; do
        [[ -d "$tdir" ]] || continue
        local tid=${tdir##*/}
        r_sw "$tdir/schedstat"; T_START_SW["$tid"]=$_READ_VOL
        if [[ -z "${CLAIMED[$tid]+x}" && -z "${FEEDER_SET[$tid]+x}" ]]; then
            T_START_CPU["$tid"]=${T_START_CPU["$tid"]:-0}
            continue
        fi
        local _stat=""
        read -r _stat < "$tdir/stat" 2>/dev/null
        if [[ -n "$_stat" ]]; then
            _stat="${_stat##*) }"; local _s=( $_stat )
            T_START_CPU["$tid"]=$(( _s[11] + _s[12] ))
        else
            T_START_CPU["$tid"]=0
        fi
    done
    # [K3] Seed Health baselines — guard against race on game exit
    _PTH_MON_BASE_E=0; _PTH_MON_BASE_W=0
    [[ -n "$MON_ID" && -d "$TASK_BASE/$MON_ID" ]] && \
        read -r _PTH_MON_BASE_E _PTH_MON_BASE_W _ < "$MON_SCHED_PATH" 2>/dev/null
    _PTH_DQ_BASE_E=0; _PTH_DQ_BASE_W=0
    [[ -n "$Q_SCHED_PATH" ]] && \
        read -r _PTH_DQ_BASE_E _PTH_DQ_BASE_W _ < "$Q_SCHED_PATH" 2>/dev/null
}

# [K4] Telemetry End report
tel_end() {
    [[ -z "$PSOBB_PID" ]] && return; local _ts; printf -v _ts "%(%H:%M:%S)T" -1
    lg "── [${_ts}] CPU:${CPU_LIVE_MHZ}M GPU:${GPU_CUR_MHZ:-?}M ${CPU_TEMP}°C ────────────────"
    echo "TID     CLASS       C SW      RATE      CPU% ST   STATUS"
    # [K5] Elapsed time and jiffies
    local _now=${EPOCHREALTIME/./}
    local _el_us=$(( _now - T_START_TS )); (( _el_us <= 0 )) && _el_us=30000000
    local _el_jif=$(( _el_us * CLK_TCK / 1000000 ))
    local _csv_mon=0 _csv_mgr=0 _csv_hrt=0 _csv_q=0 _csv_cs=0
    local _tel_mon=0 _tel_mgr=0 _mud_c=0 _mud_sw=0
    for tid in "${!T_START_SW[@]}"; do
        local b_sw=${T_START_SW[$tid]}; local a_sw=0
        if [[ -f "$TASK_BASE/$tid/status" ]]; then
            r_sw "$TASK_BASE/$tid/schedstat"; a_sw=$_READ_VOL
        fi
        (( a_sw == 0 && b_sw == 0 )) && continue
        local delta=$(( a_sw - b_sw )); (( delta < 0 )) && delta=0
        
        # [K6] Single-read /proc stat — core, state, CPU ticks
        local core="-" stat="-" pcpu="0.0" _c_now=0
        local _sf="$TASK_BASE/$tid/stat"
        
        # [TEL-01] Option F: Rate-limit stat reads for non-critical (MUD) threads to every 2nd window
        if [[ -z "${CLAIMED[$tid]+x}" && -z "${FEEDER_SET[$tid]+x}" ]] && (( TEL_WINDOW % 2 != 0 )); then
            core="~" stat="~" pcpu="~"
            _c_now=${T_START_CPU[$tid]:-0}
        else
            if [[ -f "$_sf" ]]; then
                local _r=""; read -r _r < "$_sf" 2>/dev/null || true
                if [[ -n "$_r" ]]; then
                    _r="${_r##*) }"; local -a _s=($_r)
                    stat="${_s[0]:-?}"; core="${_s[36]:--}"; _c_now=$(( ${_s[11]:-0} + ${_s[12]:-0} ))
                fi
            fi
        fi
        
        local _c_d=$(( _c_now - T_START_CPU[$tid] )); (( _c_d < 0 )) && _c_d=0
        local _pi=$(( _c_d * 100 / _el_jif ))
        [[ "$pcpu" != "~" ]] && pcpu="${_pi}.$(( (_c_d * 1000 / _el_jif) % 10 ))"

        [[ -z "${core}" ]] && continue; local r_i=$(( delta / 30 ))
        # Inline t_cls — TC_CLASS pre-populated at I13; FEEDER_SET checked as fallback  [v4.4.4]
        local class="${TC_CLASS[$tid]:-}"
        [[ -z "$class" ]] && { [[ -n "${FEEDER_SET[$tid]+x}" ]] && class="FEEDER" || class="MUD"; }
        
        # [K7] Burst trigger
        [[ "$class" == "MGR" ]] && { (( r_i > BURST_MGR_ARM_THRESH )) && BURST_ARMED=1; _tel_mgr=$r_i; }
        [[ "$class" == "MON" ]] && _tel_mon=$r_i
        
        # [K8] DXVK_Q fence-shift — wait:exec ratio drives CORE_FRAME  [v3.8.4:M1]
        if [[ "$class" == "DXVK_Q" && -n "$Q_SCHED_PATH" ]]; then
            local q_e=0 q_w=0
            read -r q_e q_w _ < "$Q_SCHED_PATH" 2>/dev/null
            if (( DQ_EXEC_LAST > 0 )); then
                local q_ed=$(( q_e - DQ_EXEC_LAST )) q_wd=$(( q_w - DQ_WAIT_LAST ))
                if (( q_ed > 0 )); then
                    local q_r=$(( q_wd / q_ed )); _csv_q=$q_r  # wait:exec ratio
                    if (( q_r > DXVK_Q_FENCE_THR )); then
                        (( DQ_CTR++ ))
                        if (( DQ_CTR >= DXVK_Q_FENCE_CONFIRM && DQ_FENCE == 0 )); then
                            DQ_FENCE=1; CORE_FRAME=$CORE_MON; FORCE_MEDIUM=1
                            lg "DXVK_Q fence-shift: $q_r:1"
                        fi
                    else
                        if (( DQ_FENCE == 1 )); then
                            DQ_FENCE=0; CORE_FRAME=$CORE_HEART; DQ_CTR=0; FORCE_MEDIUM=1
                            lg "DXVK_Q normalized: $q_r:1"
                        else
                            (( DQ_CTR > 0 )) && (( DQ_CTR-- ))  # decay on sub-threshold
                        fi
                    fi
                fi
            fi
            DQ_EXEC_LAST=$q_e; DQ_WAIT_LAST=$q_w
        fi
        
        # [K9] MUD aggregation
        if (( _pi < 1 && r_i < 1500 )) && [[ "$class" == "MUD" ]]; then (( _mud_c++ )); (( _mud_sw += delta )); continue; fi  # [v3.7.9:M4]
        
        # [K10/K11] Format & Accumulate
        if [[ "$class" != "MUD" || delta -gt 10 ]]; then
            # Disambiguate active MUD threads to identify background offenders
            if [[ "$class" == "MUD" ]]; then
                local _mc=""; read -r _mc < "$TASK_BASE/$tid/comm" 2>/dev/null
                [[ -n "$_mc" ]] && class="MUD[${_mc:0:6}]"
            fi

            # [K10] Status classification — thresholds from header comment  [v3.7.9:M4]
            local st="[IDLE]   "
            (( r_i >    50 )) && st="[PULSING]"
            (( r_i >  1500 )) && st="[ACTIVE] "
            (( r_i >  8000 )) && st="[COMBAT] "
            (( r_i > 25000 )) && st="[CARNAGE]"
            
            # [K11] Format row and accumulate CSV fields
            local row; printf -v row "%-7s %-11s %-1s %-7s %-9s %-4s %-4s %s" \
                "$tid" "$class" "$core" "$delta" \
                "${r_i}.$(( (delta*10/30)%10 ))/s" "$pcpu" "$stat" "$st"
            echo "$row"; lg "$row"
            [[ "$class" == "MON" ]]     && _csv_mon=$r_i
            [[ "$class" == "MGR" ]]     && _csv_mgr=$r_i
            [[ "$class" == "HEART" ]]   && _csv_hrt=$r_i
            [[ "$class" == "DXVK_CS" ]] && _csv_cs=$pcpu
        fi
    done
    if (( _mud_c > 0 )); then
        printf -v m_r "%-7s %-11s %-1s %-7s %-9s %-4s %-4s %s" \
            "($_mud_c)" "MUD_POOL" "-" "$_mud_sw" \
            "$(( _mud_sw/30 )).$(( (_mud_sw*10/30)%10 ))/s" "0.0" "-" "[AGGREGATED]"
        echo "$m_r"; lg "$m_r"
    fi
    # [K11] CSV write — one row per telemetry window
    if [[ -n "$SES_CSV" && "$LOG_EN" -eq 1 ]]; then
        printf "%s,%s,%d,telemetry,%s,%s,%d,%d,%d,%d,%s,%d,%s,%s,%d,%d,%d\n" \
            "$_now" "$SES_TS" "$TEL_WINDOW" "$SYS_STATE" "$PLAYER_CLASS" \
            "$_csv_mon" "$_csv_mgr" "$_csv_hrt" "$_csv_q" "$_csv_cs" \
            "$MT_HITCH_US" "$CPU_TEMP" "$GPU_CUR_MHZ" "0" "$DQ_FENCE" "$BURST_ARMED" \
            >> "$SES_CSV"
    fi
    MT_HITCH_US=0; (( TEL_WINDOW++ ))
    # [K12] Swap detection — MGR/MON rate inversion confirms identity swap  [v3.8.6:M1]
    if (( G_VLD == 1 && TEL_WINDOW > 8 )); then
        local _mon_floor=$(( _tel_mon < 1 ? 1 : _tel_mon ))  # clamp: prevents false trigger when MON==0
        if (( _tel_mgr > 8000 && _tel_mon < 2000 && _tel_mgr > _mon_floor * 10 )); then
            (( SWAP_CTR++ ))
            if (( SWAP_CTR >= 2 )); then
                echo -e "\n[!] Swap confirmed: re-arming Goliath"
                lg "SWAP CONFIRMED mgr=${_tel_mgr} mon=${_tel_mon} ratio=$(( _tel_mgr / _mon_floor ))"
                MON_ID=""; MGR_ID=""; G_VLD=0; SWAP_CTR=0; inv_tc; FORCE_MEDIUM=1
            fi
        else
            (( SWAP_CTR > 0 )) && SWAP_CTR=0
        fi
    fi
    flush_logs  # [v3.9.8:L1] flush once per telemetry window — predictable 30s write cadence
}

# [K13] Health Printer
print_health() {
    local _tag="$1"
    if [[ -n "$MON_SCHED_PATH" ]]; then
        local me=0 mw=0
        read -r me mw _ < "$MON_SCHED_PATH" 2>/dev/null
        local med=$(( (me - _PTH_MON_BASE_E) / 1000000 ))
        local mwd=$(( (mw - _PTH_MON_BASE_W) / 1000000 ))
        local mt=$(( med + mwd )); (( mt == 0 )) && mt=1
        local mp=$(( (mwd * 100) / mt ))
        printf "  │ MON wait: %d%% (%dms/%dms) — ideal <15%%\n" "$mp" "$mwd" "$mt"
        [[ -n "$_tag" ]] && lg "$_tag MONSTER wait=${mp}%"
    fi
    if [[ -n "$HEART_SCHED_PATH" ]]; then
        local he=0 hw=0
        read -r he hw _ < "$HEART_SCHED_PATH" 2>/dev/null
        if (( he > 0 )); then
            local ht=$(( he + hw )) hp=$(( (hw * 100) / ht ))
            printf "  │ ♥   wait: %d%% (%dms/%dms)\n" "$hp" "$(( hw / 1000000 ))" "$(( ht / 1000000 ))"
        fi
    fi
}


# [L] --- TRIGGERED / INTERACTIVE FUNCTIONS ---

# [L1] Burst Sampler entry
burst_sample() {
    local trg="${1:-periodic}"; [[ -z "$PSOBB_PID" || -z "$BURST_CSV" || "$LOG_EN" -ne 1 ]] && return
    (( BURST_ID++ )); local bid=$BURST_ID  # [v3.7.5:L1]
    lg "BURST start: id=${bid} trg=${trg}"
    # Pairing threads
    # Thread ID → class name pairs — order determines burst report ordering
    local -a pairs=(
        "$HEART_ID"    HEART
        "$MON_ID"      MONSTER
        "$MGR_ID"      MANAGER
        "$SUBMIT_ID"   DXVK_SUBMIT
        "$CS_ID"       DXVK_CS
        "$Q_ID"        DXVK_Q
        "$FRAME_ID"    DXVK_FRAME
        "$WSI_Q_ID"    WSI_Q
        "$WSI_E_ID"    WSI_E
        "$AUDIO_ID"    AUDIO_MA
        "$AUDIO_TI_ID" AUDIO_TI
        "$AUDIO_MIX_ID" AUDIO_MIX
    )
    local tids=() clss=()
    local pi; for (( pi=0; pi<${#pairs[@]}; pi+=2 )); do
        local bt="${pairs[$pi]}" bc="${pairs[$((pi+1))]}"
        [[ -n "$bt" && -d "/proc/$PSOBB_PID/task/$bt" ]] && tids+=("$bt") && clss+=("$bc")
    done
    local n_th=${#tids[@]}; (( n_th == 0 )) && return
    # [L2] Pre-compute sysfs paths — eliminates string concat inside sample loop
    local -a p_dir=() p_sched=() p_stat=() b_comm=()
    for (( i=0; i<n_th; i++ )); do
        local r_tid="${tids[$i]}"
        p_dir[$i]="/proc/$PSOBB_PID/task/$r_tid"
        p_sched[$i]="${p_dir[$i]}/schedstat"
        p_stat[$i]="${p_dir[$i]}/stat"
        local c=""
        read -r c < "${p_dir[$i]}/comm" 2>/dev/null
        b_comm[$i]="$c"
    done
    # [L3] Baseline snapshot — exec/wait/ctxsw per tracked thread
    local -a pe=() pw=() pv=() pnv=()
    for (( i=0; i<n_th; i++ )); do
        local e=0 w=0
        [[ -f "${p_sched[$i]}" ]] && read -r e w _ < "${p_sched[$i]}" 2>/dev/null
        pe[$i]=$e; pw[$i]=$w
        r_csw "${p_dir[$i]}/status"
        pv[$i]=$_READ_VOL; pnv[$i]=$_READ_NONVOL
    done
    local s; for (( s=1; s<=BURST_SAMPLES; s++ )); do
        sleep "$BURST_SLEEP_S"; local now=${EPOCHREALTIME/./}
        for (( i=0; i<n_th; i++ )); do
            local cls="${clss[$i]}"
            # [L4] Dead thread check
            if [[ ! -d "${p_dir[$i]}" ]]; then
                printf "%s,%s,%d,%s,%d,DEAD:%s,%s,?,0,0,0,0\n" \
                    "$now" "$SES_TS" "$bid" "$trg" "$s" "$cls" "${tids[$i]}" >> "$BURST_CSV"
                b_comm[$i]=""; continue
            fi
            # Core read from stat
            local core="?" st=""
            read -r st < "${p_stat[$i]}" 2>/dev/null
            [[ -n "$st" ]] && { st="${st##*) }"; local -a _sf=( $st ); core="${_sf[36]}"; }
            # Schedstat + ctxsw read
            local e=0 w=0
            [[ -f "${p_sched[$i]}" ]] && read -r e w _ < "${p_sched[$i]}" 2>/dev/null
            r_csw "${p_dir[$i]}/status"; local v=$_READ_VOL nv=$_READ_NONVOL
            # Delta calc — clamp negatives (TID reuse guard)
            local ed=$(( e - pe[$i] )) wd=$(( w - pw[$i] ))
            local vd=$(( v - pv[$i] )) nvd=$(( nv - pnv[$i] ))
            (( ed  < 0 )) && ed=0;  (( wd  < 0 )) && wd=0
            (( vd  < 0 )) && vd=0;  (( nvd < 0 )) && nvd=0
            # [L4] TID reuse detection — comm changed mid-burst
            local cur_c=""
            read -r cur_c < "${p_dir[$i]}/comm" 2>/dev/null
            if [[ -n "${b_comm[$i]}" && "$cur_c" != "${b_comm[$i]}" ]]; then
                printf "%s,%s,%d,%s,%d,REUSE:%s,%s,%s,0,0,0,0\n" \
                    "$now" "$SES_TS" "$bid" "$trg" "$s" "$cls" "${tids[$i]}" "$core" >> "$BURST_CSV"
                pe[$i]=$e; pw[$i]=$w; pv[$i]=$v; pnv[$i]=$nv; continue
            fi
            # [L5] Artifact cap + CSV record
            local _pfx="%s,%s,%d,%s,%d"
            local _sfx="%s,%s,%s,%d,%d,%d,%d\n"
            if (( nvd > 500 )); then
                printf "${_pfx},ART:${_sfx}" \
                    "$now" "$SES_TS" "$bid" "$trg" "$s" \
                    "$cls" "${tids[$i]}" "$core" "$ed" "$wd" "$vd" "$nvd" >> "$BURST_CSV"
            else
                printf "${_pfx},${_sfx}" \
                    "$now" "$SES_TS" "$bid" "$trg" "$s" \
                    "$cls" "${tids[$i]}" "$core" "$ed" "$wd" "$vd" "$nvd" >> "$BURST_CSV"
            fi
            pe[$i]=$e; pw[$i]=$w; pv[$i]=$v; pnv[$i]=$nv
        done
    done
    lg "BURST end: id=${bid} trg=${trg} n=${n_th}"; BURST_LAST_WINDOW=$TEL_WINDOW
}

# [L6] Benchmark entry
benchmark() {
    [[ -z "$PSOBB_PID" ]] && return; echo -e "\n  ┌─ BENCHMARK MODE ─────────────────────────\n  │  Monitoring Active deltas for 30s...\n  └────────────────────────────────────────────────────"
    local -A be=() bw=() bv=() bnv=()
    local t; for t in /proc/"$PSOBB_PID"/task/*; do
        [[ ! -d "$t" ]] && continue
        local tid=${t##*/}
        local e=0 w=0
        [[ -f "$t/schedstat" ]] && read -r e w _ < "$t/schedstat" 2>/dev/null
        be[$tid]=$e; bw[$tid]=$w
        r_csw "$t/status" 2>/dev/null
        bv[$tid]=$_READ_VOL; bnv[$tid]=$_READ_NONVOL
    done
    local start=${EPOCHREALTIME}; for (( i=1; i<=15; i++ )); do
        # [L9] Benchmark: 15-cycle active monitor phase
        (( THM_GUARD_EN )) && mng_thm; if (( TICK_CTR % MT_INTV == 0 )); then cls_th >/dev/null; set_pr >/dev/null; pin_th >/dev/null; fi
        ((TICK_CTR++)); local khz; read -r khz < "$CPU_FREQ_NODE" 2>/dev/null; CPU_LIVE_MHZ=$(( khz / 1000 )); printf "\r\033[K  [BM %2d/15 | %2s°C | %4sMHz]" "$i" "$CPU_TEMP" "$CPU_LIVE_MHZ"; read -t 2 -n 1 -s k; [[ "$k" =~ [qQ] ]] && return
    done
    local el=$(( (${EPOCHREALTIME/./} - ${start/./}) / 1000000 )); (( el <= 0 )) && el=30
   # [L10] Benchmark: delta report and health footer
    echo -e "\n  ┌─ BENCHMARK ${el}s ── %H:%M:%S ──────"
    echo    "  │ TID      CLASS          exec_Δms   wait_Δms   SW/s"
    echo    "  ├────────────────────────────────────────────────────"
    for t in /proc/"$PSOBB_PID"/task/*; do
        local tid=${t##*/}
        [[ -z "${be[$tid]+x}" ]] && continue
        local e1=0 w1=0
        [[ -f "$t/schedstat" ]] && read -r e1 w1 _ < "$t/schedstat" 2>/dev/null
        r_csw "$t/status" 2>/dev/null
        local ed=$(( (e1 - be[$tid]) / 1000000 ))
        local wd=$(( (w1 - bw[$tid]) / 1000000 ))
        
        # [L10b] Negative SW/s guard — /proc/status ctx fields are uint64; wrap is
        # unreachable in practice. Guard defends against TID reuse mid-benchmark
        # (same TID assigned to a new thread, resetting its counter below baseline).
        local _v_diff=$(( _READ_VOL - bv[$tid] ))
        (( _v_diff < 0 )) && _v_diff=$(( _READ_VOL ))
        local _nv_diff=$(( _READ_NONVOL - bnv[$tid] ))
        (( _nv_diff < 0 )) && _nv_diff=$(( _READ_NONVOL ))
        
        local sw=$(( (_v_diff + _nv_diff) / el ))
        
        t_cls "$tid"
        printf "  │ %-8s %-14s %-10s %-10s %-8s\n" \
            "$tid" "$THREAD_CLASS" "${ed}ms" "${wd}ms" "${sw}/s"
    done
    echo -e "  └─────────────────────────────────────\n  [Press any key to return...]"
    read -t 60 -n 1 -s >/dev/null 2>&1
}
# [M] --- BOOTSTRAP ---                                                        

# [M1] Bootstrap: Entry — read CPU model name for banner, detect hot-swap
_cpu_model=$(grep -m1 "^model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//')
echo "=========================================="
t_echo "APEX PHOENIX ${APXP_VERSION} — ${_cpu_model:-Unknown CPU}"
echo "=========================================="
unset _cpu_model

if pgrep -x "psobb.exe" >/dev/null; then
    t_echo "[!] Hot-Swap: psobb.exe active — bypassing launch"
    HOT_SWAP=1
else
    pkill -9 -fi "wine|psobb|online.exe|wineserver" -u "$SUDO_USER" 2>/dev/null  # [v3.9.3:H2] scoped to SUDO_USER
    WINEPREFIX="$WINE_PREFIX" "${WINESERVER_BIN:-wineserver}" -k >/dev/null 2>&1
fi

# [M1b] AC power check before hardware harness  [v3.9.3:H3]
_ac_node=""; _ac_val=""
for _ac_node in /sys/class/power_supply/A*/online; do [[ -f "$_ac_node" ]] && break; done
[[ -f "$_ac_node" ]] && read -r _ac_val < "$_ac_node" 2>/dev/null
if [[ "$_ac_val" == "0" ]]; then
    t_echo "[!] WARNING: Running on BATTERY — hardware harness will reduce performance envelope"
    read -r -p "  [>] Continue on battery? [y/N]: " _bat_cont
    [[ ! "$_bat_cont" =~ ^[Yy] ]] && exit 1
fi
unset _ac_node _ac_val _bat_cont

pf; hw_init; evict_chaff; log_init

# [M2] Bootstrap: Stability summary
(( HAS_FAN_NODE == 0 && FAN_CTRL_EN == 1 )) && t_echo "  [!] BOOT RISK: Fan node unavailable"
(( HAS_FAN_NODE == 0 && FAN_CTRL_EN == 0 )) && t_echo "  [~] Fan control disabled — thermal monitoring active"
(( HAS_DMA_LATENCY == 0 )) && t_echo "  [!] BOOT RISK: cpu_dma_latency unavailable"
(( HAS_CPWR == 0 )) && t_echo "  [~] cpupower unavailable"
(( HAS_PSTATE == 0 )) && t_echo "  [~] CPU freq pstate control unavailable — scaling_max_freq used"
(( HAS_SCHED_DEBUG == 0 )) && t_echo "  [~] sched debugfs not mounted"
(( HAS_DXVK_CONF == 0 )) && (( HOT_SWAP )) && t_echo "  [~] dxvk.conf missing — DXVK will use internal defaults"

# [S] --- SETUP WIZARD ---  [v4.5.4]
# Stateless: every check is a fast file/dir existence test.
# Skips completed steps automatically — safe to run on every boot.
# Runs only when HOT_SWAP=0 (game not already running).

if (( ! HOT_SWAP )); then

# [S0] Wine prefix path — prompt only if prefix not yet initialised; confirm silently if healthy
if [[ ! -f "$WINE_PREFIX/system.reg" ]]; then
    echo ""
    t_echo "[+] SETUP: Wine Prefix"
    echo "  Default: $WINE_PREFIX"
    echo "  (Press Enter to accept, or type a custom path)"
    read -r -p "  [>] Wine prefix path [${WINE_PREFIX}]: " _wp_in
    [[ -n "$_wp_in" ]] && WINE_PREFIX="${_wp_in/#\~/$USER_HOME}"
    unset _wp_in
    t_echo "  [~] Using prefix: $WINE_PREFIX"
else
    t_echo "[S0] [✓] Wine prefix: $WINE_PREFIX"
fi

# [S1] Wine prefix initialisation — create if system.reg absent
if [[ ! -f "$WINE_PREFIX/system.reg" ]]; then
    t_echo "[S1] Wine prefix not initialised — running wineboot..."
    if [[ -z "$WINE_BIN" ]]; then
        t_echo "  [!] WINE_BIN not set — cannot init prefix. Install Wine first."
        t_echo "      Ubuntu/Mint:  sudo dpkg --add-architecture i386 && sudo apt install wine wine32"
        t_echo "      Arch/Manjaro: sudo pacman -Sy wine wine-gecko wine-mono"
        t_echo "      Steam Deck:   steamos-readonly disable && sudo pacman -Sy wine && steamos-readonly enable"
        t_echo "      Then re-run this script."
        exit 1
    fi
    sudo -u "$SUDO_USER" env WINEPREFIX="$WINE_PREFIX" DISPLAY="$DISPLAY_ID" XAUTHORITY="$XAUTH_PATH" \
        "$WINE_BIN" wineboot --init >/dev/null 2>&1
    if [[ ! -f "$WINE_PREFIX/system.reg" ]]; then
        t_echo "  [!] wineboot failed — prefix still missing system.reg."
        t_echo "      Try: sudo -u $SUDO_USER WINEPREFIX=$WINE_PREFIX wine wineboot --init"
        exit 1
    fi
    t_echo "  [✓] Wine prefix initialised at $WINE_PREFIX"
else
    t_echo "  [✓] Wine prefix OK ($WINE_PREFIX/system.reg present)"
fi

# [S2] Game installation — zip-first priority, fresh-extract safeguard  [v4.7.1]
# Priority: found zip → found folder → found .exe installer → download installer → manual
# A zip is always preferred over an existing folder: it is the authoritative clean source.
# An existing folder may be a partial/corrupt previous attempt.

_s2_found_zip=""
_s2_found_exe=""
_s2_found_dir=""

if [[ ! -f "$GAME_DIR/online.exe" ]]; then
    echo ""
    t_echo "[S2] Game not found — scanning for Ephinea files..."

    # [S2a] Scan common locations — zip first, then installer exe, then extracted folder
    for _scan_dir in "$USER_HOME/Downloads" "$USER_HOME/Desktop" "/tmp" "$USER_HOME"; do
        [[ -d "$_scan_dir" ]] || continue
        for _scan_f in \
            "$_scan_dir"/Ephinea*.zip "$_scan_dir"/ephinea*.zip \
            "$_scan_dir"/PSOBB*.zip   "$_scan_dir"/psobb*.zip \
            "$_scan_dir"/EphineaPSO*.zip; do
            [[ -f "$_scan_f" ]] && { _s2_found_zip="$_scan_f"; break 2; }
        done
    done
    for _scan_dir in "$USER_HOME/Downloads" "$USER_HOME/Desktop" "/tmp" "$USER_HOME"; do
        [[ -d "$_scan_dir" ]] || continue
        for _scan_f in \
            "$_scan_dir"/Ephinea*.exe "$_scan_dir"/EphineaPSO*.exe \
            "$_scan_dir"/ephinea*.exe; do
            [[ -f "$_scan_f" ]] && { _s2_found_exe="$_scan_f"; break 2; }
        done
    done
    for _scan_dir in \
        "$USER_HOME/Desktop/EphineaPSO" "$USER_HOME/Desktop/Ephinea" \
        "$USER_HOME/Downloads/EphineaPSO" "$USER_HOME/Downloads/Ephinea" \
        "$USER_HOME/EphineaPSO" \
        "$USER_HOME/Games/EphineaPSO" "$USER_HOME/Games/Ephinea"; do
        [[ -f "$_scan_dir/online.exe" ]] && { _s2_found_dir="$_scan_dir"; break; }
    done
    unset _scan_dir _scan_f

    # Report findings — zip wins over folder even if both present
    [[ -n "$_s2_found_zip" ]] && t_echo "  [~] Found zip:        $_s2_found_zip"
    [[ -n "$_s2_found_exe" ]] && t_echo "  [~] Found installer:  $_s2_found_exe"
    [[ -n "$_s2_found_dir" ]] && t_echo "  [~] Found folder:     $_s2_found_dir"
    [[ -z "$_s2_found_zip" && -z "$_s2_found_exe" && -z "$_s2_found_dir" ]] && \
        t_echo "  [~] Nothing found in Downloads/Desktop."

    # [S2b] Menu — label option 1 based on best available source
    echo ""
    echo "  ┌─ Ephinea PSOBB Installation ──────────────────────────────────────┐"
    if [[ -n "$_s2_found_zip" ]]; then
        printf "  │  [1] Extract zip:    %-47s│\n" "$(basename "$_s2_found_zip")"
    elif [[ -n "$_s2_found_exe" ]]; then
        printf "  │  [1] Run installer:  %-47s│\n" "$(basename "$_s2_found_exe")"
    elif [[ -n "$_s2_found_dir" ]]; then
        printf "  │  [1] Use folder:     %-47s│\n" "$(basename "$_s2_found_dir")"
    else
        echo  "  │  [1] Download installer from Ephinea (~600MB)                     │"
    fi
    echo "  │  [2] Enter path manually (installed somewhere else)               │"
    echo "  │  [3] Exit — I will download the zip and re-run                    │"
    echo "  │       https://ephinea.pioneer2.net                                │"
    echo "  └───────────────────────────────────────────────────────────────────┘"
    echo ""
    read -r -p "  [>] Choice [1]: " _s2_choice

    case "${_s2_choice:-1}" in

        # ── Option 1 ──────────────────────────────────────────────────────────
        1)
            # ── 1A: extract zip (preferred — authoritative clean source) ──────
            if [[ -n "$_s2_found_zip" ]]; then
                echo ""
                echo "  Where should the game be extracted?"
                echo "  [a] Home folder  → ${USER_HOME}/EphineaPSO"
                echo "  [b] Desktop      → ${USER_HOME}/Desktop/EphineaPSO"
                echo "  [c] Custom path"
                read -r -p "  [>] Choice [a]: " _dest_choice
                case "${_dest_choice:-a}" in
                    b) _extract_dest="${USER_HOME}/Desktop/EphineaPSO" ;;
                    c) read -r -p "  [>] Path: " _cust_dest
                       _extract_dest="${_cust_dest/#\~/$USER_HOME}"; unset _cust_dest ;;
                    *) _extract_dest="${USER_HOME}/EphineaPSO" ;;
                esac
                unset _dest_choice

                # Safeguard: if destination already exists warn and offer clean wipe  [v4.7.1]
                if [[ -d "$_extract_dest" ]]; then
                    t_echo "  [!] Destination already exists: $_extract_dest"
                    t_echo "      This may be from a previous failed install."
                    read -r -p "  [>] Wipe it and extract fresh? [Y/n]: " _wipe_ch
                    if [[ ! "$_wipe_ch" =~ ^[Nn] ]]; then
                        t_echo "  [~] Removing previous installation..."
                        rm -rf "$_extract_dest"
                        t_echo "  [✓] Cleared."
                    else
                        t_echo "  [~] Keeping existing — extracting on top (may leave corrupt files)"
                    fi
                    unset _wipe_ch
                fi

                t_echo "  [~] Extracting $(basename "$_s2_found_zip") → $_extract_dest ..."
                mkdir -p "$_extract_dest"
                chown "$SUDO_USER":"$SUDO_USER" "$_extract_dest" 2>/dev/null

                # Detect zip structure: flat (online.exe at root) vs nested (wrapped folder)
                if ! unzip -Z1 "$_s2_found_zip" 2>/dev/null | grep -q '^online\.exe$'; then
                    _ztmp="/tmp/_apxp_zip_$$"; mkdir -p "$_ztmp"
                    unzip -q "$_s2_found_zip" -d "$_ztmp" 2>/dev/null
                    _ztop=$(find "$_ztmp" -maxdepth 1 -mindepth 1 -type d | head -1)
                    if [[ -n "$_ztop" && -f "$_ztop/online.exe" ]]; then
                        cp -a "$_ztop/." "$_extract_dest/"
                        t_echo "  [✓] Extracted (stripped wrapper folder)"
                    else
                        unzip -q "$_s2_found_zip" -d "$_extract_dest" 2>/dev/null
                        t_echo "  [✓] Extracted (flat fallback)"
                    fi
                    rm -rf "$_ztmp"; unset _ztmp _ztop
                else
                    unzip -q "$_s2_found_zip" -d "$_extract_dest" 2>/dev/null
                    t_echo "  [✓] Extracted"
                fi
                chown -R "$SUDO_USER":"$SUDO_USER" "$_extract_dest" 2>/dev/null

                # Locate online.exe — may be in a subfolder
                if [[ -f "$_extract_dest/online.exe" ]]; then
                    GAME_DIR="$_extract_dest"
                else
                    _found_exe=$(find "$_extract_dest" -name "online.exe" 2>/dev/null | head -1)
                    if [[ -n "$_found_exe" ]]; then
                        GAME_DIR=$(dirname "$_found_exe")
                        t_echo "  [~] Found in subfolder: $GAME_DIR"
                    else
                        t_echo "  [!] online.exe not found after extraction."
                        read -r -p "  [>] Enter game directory manually: " _manual_path
                        [[ -n "$_manual_path" ]] && GAME_DIR="${_manual_path/#\~/$USER_HOME}"
                        unset _manual_path
                    fi
                    unset _found_exe
                fi
                unset _extract_dest

            # ── 1B: run .exe installer via Wine ──────────────────────────────
            elif [[ -n "$_s2_found_exe" ]]; then
                t_echo "  [~] Launching installer: $(basename "$_s2_found_exe")"
                echo "  ┌─────────────────────────────────────────────────────────┐"
                echo "  │  The Ephinea installer will open.                       │"
                echo "  │  Click Next → accept defaults → let it finish.          │"
                echo "  │  When the installer closes, press Enter here.           │"
                echo "  └─────────────────────────────────────────────────────────┘"
                sudo -u "$SUDO_USER" env \
                    WINEPREFIX="$WINE_PREFIX" DISPLAY="$DISPLAY_ID" XAUTHORITY="$XAUTH_PATH" \
                    "$WINE_BIN" "$_s2_found_exe" >/dev/null 2>&1 &
                _inst_pid=$!
                read -r -p "  [>] Press Enter when the installer has finished..." _dummy
                wait "$_inst_pid" 2>/dev/null; unset _inst_pid _dummy
                for _try in \
                    "$WINE_PREFIX/drive_c/EphineaPSO" "$WINE_PREFIX/drive_c/Ephinea" \
                    "$WINE_PREFIX/drive_c/Program Files (x86)/SEGA/Phantasy Star Online Blue Burst" \
                    "$WINE_PREFIX/drive_c/Program Files/SEGA/Phantasy Star Online Blue Burst" \
                    "$USER_HOME/EphineaPSO"; do
                    if [[ -f "$_try/online.exe" ]]; then
                        GAME_DIR="$_try"; t_echo "  [✓] Game detected at: $GAME_DIR"; break
                    fi
                done; unset _try
                if [[ ! -f "$GAME_DIR/online.exe" ]]; then
                    t_echo "  [!] Could not auto-detect install path."
                    read -r -p "  [>] Enter game directory: " _manual_path
                    [[ -n "$_manual_path" ]] && GAME_DIR="${_manual_path/#\~/$USER_HOME}"
                    unset _manual_path
                fi

            # ── 1C: use found folder (lowest priority — may be a failed install) ──
            elif [[ -n "$_s2_found_dir" ]]; then
                GAME_DIR="$_s2_found_dir"
                t_echo "  [~] Using found folder: $GAME_DIR"
                t_echo "      Note: if this is from a failed install, choose [2] to enter a different path."

            # ── 1D: download installer from Ephinea ───────────────────────────
            else
                t_echo "  [~] Downloading Ephinea installer (~600MB)..."
                _inst_url="https://ephinea.pioneer2.net/dl/EphineaPSO.exe"
                _inst_dest="/tmp/EphineaPSO_installer_$$.exe"
                if curl -L --progress-bar -o "$_inst_dest" "$_inst_url"; then
                    t_echo "  [✓] Download complete. Launching installer..."
                    echo "  ┌─────────────────────────────────────────────────────────┐"
                    echo "  │  The Ephinea installer will open.                       │"
                    echo "  │  Click Next → accept defaults → let it finish.          │"
                    echo "  │  When the installer closes, press Enter here.           │"
                    echo "  └─────────────────────────────────────────────────────────┘"
                    sudo -u "$SUDO_USER" env \
                        WINEPREFIX="$WINE_PREFIX" DISPLAY="$DISPLAY_ID" XAUTHORITY="$XAUTH_PATH" \
                        "$WINE_BIN" "$_inst_dest" >/dev/null 2>&1 &
                    _inst_pid=$!
                    read -r -p "  [>] Press Enter when the installer has finished..." _dummy
                    wait "$_inst_pid" 2>/dev/null; unset _inst_pid _dummy
                    for _try in \
                        "$WINE_PREFIX/drive_c/EphineaPSO" "$WINE_PREFIX/drive_c/Ephinea" \
                        "$WINE_PREFIX/drive_c/Program Files (x86)/SEGA/Phantasy Star Online Blue Burst" \
                        "$WINE_PREFIX/drive_c/Program Files/SEGA/Phantasy Star Online Blue Burst" \
                        "$USER_HOME/EphineaPSO"; do
                        if [[ -f "$_try/online.exe" ]]; then
                            GAME_DIR="$_try"; t_echo "  [✓] Game detected at: $GAME_DIR"; break
                        fi
                    done; unset _try
                    rm -f "$_inst_dest"
                    if [[ ! -f "$GAME_DIR/online.exe" ]]; then
                        t_echo "  [!] Could not auto-detect. Enter path manually."
                        read -r -p "  [>] Game directory: " _manual_path
                        [[ -n "$_manual_path" ]] && GAME_DIR="${_manual_path/#\~/$USER_HOME}"
                        unset _manual_path
                    fi
                else
                    t_echo "  [!] Download failed. Check internet connection."
                    t_echo "      Download the zip manually: https://ephinea.pioneer2.net"
                    rm -f "$_inst_dest"; exit 1
                fi
                unset _inst_url _inst_dest
            fi
            ;;

        # ── Option 2: manual path ─────────────────────────────────────────────
        2)
            read -r -p "  [>] Enter game directory path: " _manual_path
            [[ -n "$_manual_path" ]] && GAME_DIR="${_manual_path/#\~/$USER_HOME}"
            unset _manual_path
            ;;

        # ── Option 3: exit ────────────────────────────────────────────────────
        *)
            t_echo "  [~] Exiting. Download the Ephinea zip, then re-run this script."
            t_echo "      https://ephinea.pioneer2.net"
            exit 0
            ;;
    esac
    unset _s2_choice _s2_found_zip _s2_found_exe _s2_found_dir

    # [S2c] Minimum file verification — online.exe + data/ directory check
    if [[ ! -f "$GAME_DIR/online.exe" ]]; then
        t_echo "  [!] online.exe not found at: $GAME_DIR — cannot continue."
        exit 1
    fi
    if [[ ! -d "$GAME_DIR/data" ]]; then
        t_echo "  [!] WARNING: $GAME_DIR/data directory missing."
        t_echo "      This may be an incomplete extraction. The game may not launch correctly."
        read -r -p "  [>] Continue anyway? [y/N]: " _s2c_cont
        [[ ! "$_s2c_cont" =~ ^[Yy] ]] && exit 1
        unset _s2c_cont
    fi
    t_echo "  [✓] Game installation looks complete: $GAME_DIR"

else
    t_echo "[S2] [✓] online.exe found at: $GAME_DIR"
fi

# [S3] DXVK detection and installation
# Detection strategy: check DXVK version string in BOTH d3d8.dll and d3d9.dll.
# PSOBB is DX8 — missing d3d8.dll causes an immediate crash even if d3d9 is present.
# Marker file .dxvk_apxp_installed written after successful install for fast re-detection.
_dxvk_sys32="$WINE_PREFIX/drive_c/windows/system32"
_dxvk_marker="$WINE_PREFIX/.dxvk_apxp_installed"
_dxvk_ok=0

if [[ -f "$_dxvk_marker" ]]; then
    _dxvk_ok=1
elif [[ -f "$_dxvk_sys32/d3d9.dll" && -f "$_dxvk_sys32/d3d8.dll" ]]; then
    # Both DLLs must be present AND contain the DXVK build string
    _d9_ok=0; _d8_ok=0
    strings "$_dxvk_sys32/d3d9.dll" 2>/dev/null | grep -qi "dxvk" && _d9_ok=1
    strings "$_dxvk_sys32/d3d8.dll" 2>/dev/null | grep -qi "dxvk" && _d8_ok=1
    if (( _d9_ok && _d8_ok )); then
        _dxvk_ok=1
        touch "$_dxvk_marker" 2>/dev/null
    elif (( _d9_ok && ! _d8_ok )); then
        t_echo "  [!] DXVK d3d9.dll found but d3d8.dll missing or not DXVK — reinstalling"
    fi
    unset _d9_ok _d8_ok
fi

if (( _dxvk_ok == 0 )); then
    echo ""
    t_echo "[S3] DXVK not detected — installing latest release..."
    _dxvk_api="https://api.github.com/repos/doitsujin/dxvk/releases/latest"
    _dxvk_url=$(curl -s "$_dxvk_api" 2>/dev/null | grep '"browser_download_url"' | grep '\.tar\.gz"' | head -1 | cut -d'"' -f4)
    if [[ -n "$_dxvk_url" ]]; then
        _dxvk_tmp="/tmp/dxvk_apxp.tar.gz"
        _dxvk_dir="/tmp/dxvk_apxp_extract"
        curl -L --progress-bar -o "$_dxvk_tmp" "$_dxvk_url" && {
            mkdir -p "$_dxvk_dir"
            tar -xzf "$_dxvk_tmp" -C "$_dxvk_dir" --strip-components=1
            # Copy x32 DLLs to system32 (32-bit Wine prefix layout)
            _sys32="$WINE_PREFIX/drive_c/windows/system32"
            _sysw64="$WINE_PREFIX/drive_c/windows/syswow64"
            for _dll_name in d3d8.dll d3d9.dll; do
                [[ -f "$_dxvk_dir/x32/$_dll_name" ]] && cp "$_dxvk_dir/x32/$_dll_name" "$_sys32/" 2>/dev/null
                [[ -f "$_dxvk_dir/x32/$_dll_name" && -d "$_sysw64" ]] && cp "$_dxvk_dir/x32/$_dll_name" "$_sysw64/" 2>/dev/null
            done
            # DLLs copied as root — hand ownership to the user so Wine can load them  [v4.6]
            chown -R "$SUDO_USER":"$SUDO_USER" "$_sys32" "$_sysw64" 2>/dev/null
            unset _sys32 _sysw64 _dll_name
            rm -rf "$_dxvk_tmp" "$_dxvk_dir"
            _dxvk_ver=$(basename "$_dxvk_url"); _dxvk_ver="${_dxvk_ver%.tar.gz}"
            touch "$_dxvk_marker" 2>/dev/null  # fast-path detection on future boots
            t_echo "  [✓] DXVK installed: $_dxvk_ver"
            unset _dxvk_ver
        } || {
            t_echo "  [!] DXVK download failed — game may fall back to wined3d (degraded performance)"
            t_echo "      Install manually: https://github.com/doitsujin/dxvk/releases"
        }
        unset _dxvk_tmp _dxvk_dir
    else
        t_echo "  [!] Could not fetch DXVK release info from GitHub — skipping"
        t_echo "      Install manually: https://github.com/doitsujin/dxvk/releases"
    fi
    unset _dxvk_api _dxvk_url
else
    if [[ -f "$_dxvk_marker" ]]; then
        t_echo "[S3] [✓] DXVK previously installed (marker present)"
    else
        t_echo "[S3] [✓] DXVK detected in prefix"
    fi
fi
unset _dxvk_sys32 _dxvk_marker _dxvk_ok

# [S4] dxvk.conf generation — create minimal config if missing
if [[ ! -f "$GAME_DIR/dxvk.conf" ]]; then
    t_echo "[S4] Generating dxvk.conf..."
    cat > "$GAME_DIR/dxvk.conf" << 'DXVK_CONF_EOF'
dxvk.numCompilerThreads = 2
dxvk.enableAsync = True
dxvk.maxFrameLatency = 1
DXVK_CONF_EOF
    chown "$SUDO_USER":"$SUDO_USER" "$GAME_DIR/dxvk.conf" 2>/dev/null
    t_echo "  [✓] dxvk.conf written to $GAME_DIR/dxvk.conf"
    HAS_DXVK_CONF=1
else
    t_echo "[S4] [✓] dxvk.conf present"
    HAS_DXVK_CONF=1
fi

# [S5] Test launch — smoke test to confirm game starts; skipped if marker exists (game has run before)
_s5_marker="$WINE_PREFIX/.apxp_s5_complete"
if [[ ! -f "$_s5_marker" && -n "$WINE_BIN" ]]; then
    echo ""
    t_echo "[S5] First run detected — performing test launch to verify game starts"
    echo "  The launcher window should appear. Close it when ready, or wait 20s."
    sudo -u "$SUDO_USER" env \
        WINEPREFIX="$WINE_PREFIX" DISPLAY="$DISPLAY_ID" XAUTHORITY="$XAUTH_PATH" \
        WINEDLLOVERRIDES="d3d8=b;d3d9=n,b" WINEDEBUG="-all" \
        "$WINE_BIN" "$GAME_DIR/online.exe" >/dev/null 2>&1 &
    _test_pid=$!
    _test_ok=0
    for (( _ts=0; _ts<20; _ts++ )); do
        printf "\r  [ Test launch: %ds ]" "$(( 20 - _ts ))"
        sleep 1
        if pgrep -x "online.exe" >/dev/null 2>&1 || pgrep -x "psobb.exe" >/dev/null 2>&1; then
            _test_ok=1; break  # confirmed running — no need to wait full 20s
        fi
        kill -0 "$_test_pid" 2>/dev/null || break
    done
    printf "\r\033[K"
    pkill -fi "online.exe|psobb.exe" -u "$SUDO_USER" 2>/dev/null
    WINEPREFIX="$WINE_PREFIX" "${WINESERVER_BIN:-wineserver}" -k >/dev/null 2>&1
    wait "$_test_pid" 2>/dev/null || true
    if (( _test_ok )); then
        touch "$_s5_marker" 2>/dev/null  # skip S5 on all future boots
        chown "$SUDO_USER":"$SUDO_USER" "$_s5_marker" 2>/dev/null
        t_echo "  [✓] Test launch passed — game process confirmed"
    else
        t_echo "  [!] Test launch: process exited immediately"
        t_echo "      Check $WINE_PREFIX and $GAME_DIR are correct."
        t_echo "      Try launching manually: WINEPREFIX=$WINE_PREFIX wine $GAME_DIR/online.exe"
        read -r -p "  [>] Continue anyway? [y/N]: " _tl_cont
        [[ ! "$_tl_cont" =~ ^[Yy] ]] && exit 1
        unset _tl_cont
    fi
    unset _test_pid _test_ok _ts
else
    t_echo "[S5] [✓] Game previously verified — skipping test launch"
fi
unset _s5_marker

fi  # end HOT_SWAP gate for [S] section

# [M3] Bootstrap: Thermal guard, Wine debug level, CSV logging, and frequency forger  [v3.9.5]
echo ""
echo "=========================================="
t_echo "[+] LAUNCH CONFIGURATION"
echo "=========================================="
WINE_LOG="${GAME_DIR}/wine_launch.log"
read -r -p "  [>] Enable thermal guard? [Y/n]: " _thm_choice
if [[ "$_thm_choice" =~ ^[Nn] ]]; then
    THM_GUARD_EN=0; t_echo "  [~] Thermal guard disabled — mng_thm skipped each tick"
else
    THM_GUARD_EN=1; t_echo "  [✓] Thermal guard active"
fi
unset _thm_choice

t_echo "\n[+] WINE DEBUG LEVEL"
echo "  Log: ${WINE_LOG}"
echo "  [1] Silent  — no output  (fastest, no diagnostics)"
echo "  [2] Errors  — +err,+warn (default, catches launch failures)"
echo "  [3] Verbose — +all       (full trace, large log)"
read -r -p "  [>] Choice [2]: " _dbg_choice
case "${_dbg_choice:-2}" in
    1) WINE_DEBUG_LEVEL="-all";     t_echo "  [~] Wine debug: Silent (no log written)" ;;
    3) WINE_DEBUG_LEVEL="+all";     t_echo "  [~] Wine debug: Verbose → ${WINE_LOG}" ;;
    *) WINE_DEBUG_LEVEL="+err,+warn"; t_echo "  [✓] Wine debug: Errors → ${WINE_LOG}" ;;
esac
unset _dbg_choice

echo ""
read -r -p "  [>] Enable CSV telemetry logging? [Y/n]: " _log_choice
if [[ "$_log_choice" =~ ^[Nn] ]]; then
    LOG_EN=0; t_echo "  [~] CSV logging disabled — RAM telemetry only"
else
    LOG_EN=1
    mkdir -p "$LOG_DIR" 2>/dev/null
    _csv_ts=""; printf -v _csv_ts "%(%Y%m%d_%H%M%S)T" -1
    t_echo "  [✓] CSV logging enabled → ${LOG_DIR}/session_${_csv_ts}.csv"
    unset _csv_ts
fi
unset _log_choice

t_echo "\n[+] FREQUENCY FORGER\n  Hardware max: ${HW_MAX_MHZ}MHz Defaults: Game=${GAME_MHZ}MHz Desktop=${DSK_MHZ}MHz"
read -r -p "  [>] Use defaults? [Y/n]: " _use_defaults
if [[ "$_use_defaults" =~ ^[Nn] ]]; then
    read -r -p "  [>] Game Engine MHz [${GAME_MHZ}]: " GAME_IN
    read -r -p "  [>] Desktop MHz    [${DSK_MHZ}]: " DESK_IN
    GAME_MHZ=${GAME_IN:-$GAME_MHZ}
    DSK_MHZ=${DESK_IN:-$DSK_MHZ}
fi
read -r -p "  [>] Character class: " CLASS_IN
PLAYER_CLASS=${CLASS_IN:-"unknown"}
# Game path finalised by [S2] setup wizard above; GAME_DIR is ready.
TARGET_MHZ="$GAME_MHZ"
# Pre-compute cached constants now that GAME_MHZ/DSK_MHZ/USER_HOME are final  [v4.1.1]
# XAUTH_PATH and DISPLAY_ID already set by A3 session discovery — not overwritten here
(( HW_MAX_MHZ > 0 )) && {
    GAME_PCT=$(( GAME_MHZ * 100 / HW_MAX_MHZ ))
    (( GAME_PCT < 1 ))   && GAME_PCT=1
    (( GAME_PCT > 100 )) && GAME_PCT=100
    DSK_PCT=100  # Desktop: release pstate ceiling to full range
}
freq_lock "$TARGET_MHZ"
t_echo "  [✓] Game:${GAME_MHZ}MHz Desktop:${DSK_MHZ}MHz Class:${PLAYER_CLASS}"
unset GAME_IN DESK_IN CLASS_IN _use_defaults

# Post-M3 safety net — GAME_DIR resolved by [S2]; this catches hot-swap paths and edge cases  [v4.5.4]
if [[ ! -f "$GAME_DIR/online.exe" ]]; then
    t_echo "  [!] online.exe not found at $GAME_DIR/online.exe"
    t_echo "      Verify PSOBB is installed and the path is correct."
    read -r -p "  [>] Continue anyway? [y/N]: " _path_cont
    [[ ! "$_path_cont" =~ ^[Yy] ]] && exit 1
    unset _path_cont
else
    HAS_GAME_EXE=1
    t_echo "  [✓] online.exe confirmed at $GAME_DIR"
fi

# [M3b] Keymap: Physical F10->F1 (guide), Physical F1->F12, F11 disabled
_xm_pke=$(sudo -u "$SUDO_USER" env XAUTHORITY="$XAUTH_PATH" DISPLAY="$DISPLAY_ID" xmodmap -pke 2>/dev/null)

if [[ -z "$_xm_pke" ]]; then
    t_echo "  [!] Keymap: xmodmap -pke returned empty — skipping remap"
else
    # 1. Pure Bash parsing: Zero external processes, operates entirely in memory
    while read -r line; do
        # Extract the fields: $1=keycode, $2=number, $3="=", $4=First_Keysym
        read -r _kc _code _eq _sym _ <<< "$line"
        
        # Match against our targets and capture both the full line and the keycode
        case "$_sym" in
            F1)  R_F1_LINE="$line" ; KC_F1="$_code" ;;
            F10) R_F10_LINE="$line"; KC_F10="$_code" ;;
            F11) R_F11_LINE="$line"; KC_F11="$_code" ;;
            F12) R_F12_LINE="$line"; KC_F12="$_code" ;;
        esac
    done <<< "$_xm_pke"

    # 2. Build the remap array safely using correct routing
    _xmod_args=()
    
    # Physical F1 sends F12
    [[ -n "$KC_F1" ]]  && _xmod_args+=("-e" "keycode $KC_F1 = F12")
    
    # Physical F10 sends F1
    [[ -n "$KC_F10" ]] && _xmod_args+=("-e" "keycode $KC_F10 = F1")
    
    # Physical F11 disabled
    [[ -n "$KC_F11" ]] && _xmod_args+=("-e" "keycode $KC_F11 = NoSymbol")

    # 3. Execute the remap
    if sudo -u "$SUDO_USER" env XAUTHORITY="$XAUTH_PATH" DISPLAY="$DISPLAY_ID" xmodmap "${_xmod_args[@]}" >/dev/null 2>&1; then
        t_echo "  [✓] Keymap: Hardware keycodes successfully remapped (restored on exit)"
    else
        t_echo "  [!] Keymap: xmodmap remap failed"
    fi
fi
unset _xm_pke

# [M4] Bootstrap: Wine environment and launch
if (( ! HOT_SWAP )); then
    if (( ! HAS_WINE )); then
        t_echo "[!] Cannot launch — Wine not found. Install Wine-GE or system Wine, then re-run."
        exit 1
    fi
    if (( ! HAS_GAME_EXE )); then
        t_echo "[!] Cannot launch — online.exe not found at $GAME_DIR"
        t_echo "      Verify PSOBB is installed and the path is correct."
        exit 1
    fi
    
    # [M4a] Headless Registry Patch: Fix 30s IPv6/WPAD Network Hang
    # Checks user.reg first to avoid spinning up regedit on every boot
    if ! grep -q '"AutoDetect"=dword:00000000' "$WINE_PREFIX/user.reg" 2>/dev/null; then
        t_echo "  [~] Applying AutoDetect WPAD registry patch..."
        _reg_file="/tmp/apxp_wpad_fix_$$.reg"
        
        # Indent-safe registry write
        printf 'Windows Registry Editor Version 5.00\n\n[HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings]\n"AutoDetect"=dword:00000000\n' > "$_reg_file"
        
        sudo -u "$SUDO_USER" env \
            DISPLAY="$DISPLAY_ID" XAUTHORITY="$XAUTH_PATH" \
            WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" regedit "$_reg_file" >/dev/null 2>&1
        rm -f "$_reg_file"
    fi

    t_echo "[+] Launching PSOBB via Wine..."
    # [M4b] Wine log rotation — cap at 2MB to prevent runaway disk use  [v3.9.5]
    if [[ "$WINE_DEBUG_LEVEL" != "-all" && -f "$WINE_LOG" ]]; then
        (( $(stat -c%s "$WINE_LOG" 2>/dev/null || echo 0) > 2097152 )) && \
            mv "$WINE_LOG" "${WINE_LOG%.log}_prev.log" 2>/dev/null
    fi
    [[ "$WINE_DEBUG_LEVEL" != "-all" ]] && t_echo "  [~] Wine log: ${WINE_LOG}"
    "$BIN_TSET" -a -pc "0-$(( HW_CPU_COUNT > 0 ? HW_CPU_COUNT - 1 : 7 ))" $$ >/dev/null 2>&1
    
    # [M4c] Audio socket env — Wine-GE FAudio needs XDG_RUNTIME_DIR for PipeWire  [v4.0.9]
    # PIPEWIRE_QUANTUM=1024/48000 aligns buffer (21ms); PULSE_LATENCY_MSEC smooths bridge  [v4.1.5]
    _uid=$(id -u "$SUDO_USER" 2>/dev/null)
    # XDG_RUNTIME_DIR fallback to /tmp if /run/user/$uid not yet created (race on early boot)  [v4.7]
    _xdg_rt="/run/user/${_uid}"
    [[ ! -d "$_xdg_rt" ]] && _xdg_rt="/tmp"
    _pulse_srv="unix:${_xdg_rt}/pulse/native"
    # Single launch block — output destination is the only branch  [v4.4.3]
    _wine_cmd=(
        sudo -u "$SUDO_USER" env
        DISPLAY="$DISPLAY_ID"
        XAUTHORITY="$XAUTH_PATH"
        XDG_RUNTIME_DIR="$_xdg_rt"
        PULSE_SERVER="$_pulse_srv"
        PULSE_LATENCY_MSEC=60
        PIPEWIRE_QUANTUM="1024/48000"
        WINEPREFIX="$WINE_PREFIX"
        WINEDLLOVERRIDES="d3d8=b;d3d9=n,b;dinput8=n,b"
        WINEESYNC=0 WINEFSYNC=0
        WINE_LARGE_ADDRESS_AWARE=1
        DXVK_CONFIG_FILE="$GAME_DIR/dxvk.conf"
        DXVK_ENABLE_OPENVR=0 DXVK_LOG_LEVEL=none
        MESA_DISK_CACHE_SINGLE_FILE=1
        vblank_mode=0 WINEDEBUG="$WINE_DEBUG_LEVEL"
    )
    # Intel-only env vars — noccs and GL override are meaningless/harmful on AMD/Mesa  [v4.7]
    [[ "$CPU_VENDOR" == "GenuineIntel" ]] && _wine_cmd+=( MESA_GL_VERSION_OVERRIDE=4.6 INTEL_DEBUG=noccs )
    _wine_cmd+=( "$WINE_BIN" "$GAME_DIR/online.exe" )
    if [[ "$WINE_DEBUG_LEVEL" == "-all" ]]; then
        "${_wine_cmd[@]}" >/dev/null 2>&1 &
    else
        "${_wine_cmd[@]}" >> "$WINE_LOG" 2>&1 &
    fi
    unset _wine_cmd

    "$BIN_TSET" -a -pc 0 $$ >/dev/null 2>&1
    unset _uid _xdg_rt _pulse_srv

    # [M5] Bootstrap: Wait for engine lock
    wait_timer=0
    while ! pgrep -x "psobb.exe" >/dev/null; do
        echo -ne "     [ Waiting for Engine: ${wait_timer}s ]\r"
        sleep 1
        (( ++wait_timer ))
        if [[ $wait_timer -gt $GAME_LAUNCH_TIMEOUT_S ]]; then
            echo -e "\n[X] Engine failed to start. Aborting."
            exit 1
        fi
    done
    echo -e "\n"
    unset wait_timer
fi

t_echo " [✓] Engine locked. Sentinel running..."

# [M6] Bootstrap: settle delay
if (( HOT_SWAP )); then
    sleep "$SETTLE_DELAY_HOTSWAP"
else
    for ((settle_i=SETTLE_DELAY_FRESH; settle_i>=1; settle_i--)); do
        printf "\r     [ Thread pool settling: %ds ]" "$settle_i"
        sleep 1
    done
    printf "\r\033[K"
    unset settle_i
fi

# [M7] Bootstrap: authoritative classification
t_echo "[+] Bootstrap: classifying threads..."
MF_HITS=(); MF_SW=(); FEEDER_IDS=(); FEEDER_SET=()
cls_th >/dev/null 2>&1
set_pr >/dev/null 2>&1
pin_th >/dev/null 2>&1
t_echo "  [✓] PID=${PSOBB_PID} MON=${MON_ID} MGR=${MGR_ID}"


# [N] --- SENTINEL LOOP ---                                                    

# [N1] Sentinel: Initialize tick counter and start loop
TICK_CTR=0
while true; do

    # [N2] Slow tier baseline
    [[ $TEL_EN -eq 1 ]] && tel_start  
    # [N3] Fast-path churn baseline — count seeded at MT_DUE rebuild; no glob here  [v4.0.19]

    # [N4] Inner cycle loop
    for ((i=1; i<=15; i++)); do
        ((TICK_CTR++))
        # [N5] AC Power poll
        (( TICK_CTR % 4 == 1 )) && check_ac        
        # [N6] Cache invalidation poll — also refreshes WSRV_PIDS on topology change  [v3.9.8:M4]
        if (( TICK_CTR % INV_TC_INTV == 1 )); then
            inv_tc  # [v3.8.2:M1]
            # Wineserver PID is session-stable; only re-query on topology invalidation  [v4.1.0]
            [[ -z "$WSRV_PIDS" || "$G_VLD" -eq 0 ]] && WSRV_PIDS=$(pgrep -fi "wineserver")
        fi
        
        # [N7] Focus shift poll  [v3.9.7:M4]
        # xdotool every 7 ticks = 2x per 30s window; FOCUS_PENDING removed — threshold=1 was always-true  [v4.4.4]
        if (( HAS_XDOTOOL == 1 && TICK_CTR % 7 == 1 )); then
            _aw=""; _aw=$(XAUTHORITY="$XAUTH_PATH" DISPLAY="$DISPLAY_ID" xdotool getwindowfocus getwindowname 2>/dev/null)
            _new_state="DESKTOP"; [[ "$_aw" =~ (Phantasy|Ephinea|psobb) ]] && _new_state="GAME"
            if [[ "$_new_state" != "$SYS_STATE" ]]; then
                # [N8] GAME focus — cage browser, lock freq; backgrounded to avoid blocking sentinel
                if [[ "$_new_state" == "GAME" ]]; then
                    t_echo "[+] Focus: GAME → Caging Browser..."
                    {
                        cage_external "$BROWSER_PIDS" "$NICE_MUD_APPLY" "-b" "$CORE_BROWSER"
                        cage_external "$BRIDGE_PIDS"  "$NICE_MUD_APPLY" "-b" "$CORE_MUD"
                    } &
                    [[ "$SYS_STATE" != "GAME" ]] && freq_lock "$GAME_MHZ"
                    SYS_STATE="GAME"
                else
                    # [N9] DESKTOP focus — liberate browser, unlock freq; TID loop backgrounded
                    t_echo "[+] Focus: DESKTOP → Liberating Browser..."
                    {
                        _all_cpus="0-$(( HW_CPU_COUNT > 0 ? HW_CPU_COUNT - 1 : 7 ))"
                        for _lp in $BROWSER_PIDS; do
                            "$BIN_CHRT" -o -p 0 "$_lp" >/dev/null 2>&1
                            "$BIN_RENICE" -n 0 -p "$_lp" >/dev/null 2>&1
                            "$BIN_TSET" -a -cp "$_all_cpus" "$_lp" >/dev/null 2>&1
                            for _lt in /proc/"$_lp"/task/*/; do
                                [[ -d "$_lt" ]] || continue
                                _lt=${_lt%/}; _lt=${_lt##*/}
                                "$BIN_TSET" -a -cp "$_all_cpus" "$_lt" >/dev/null 2>&1 || true
                            done
                        done
                    } &
                    [[ "$SYS_STATE" != "DESKTOP" ]] && { freq_unlock; set_turbo 0; }
                    SYS_STATE="DESKTOP"
                fi
                # [N10] Log state change
                lg "FOCUS SHIFT: $_new_state"
            fi
        fi

        # [N11] Exit Gate: Missing Dir
        if [[ -n "$PSOBB_PID" ]]; then  
            if [[ ! -d "/proc/$PSOBB_PID" ]]; then
                echo -e "\n"; [[ "$FAN_IS_LOCKED" -eq 1 && "$HAS_FAN_NODE" -eq 1 ]] && printf "level auto\n" > /proc/acpi/ibm/fan 2>/dev/null
                t_echo "[!] Game process gone. Triggering Cleanup Trap..."; exit 0
            fi
            # [N12] Exit Gate: Restart — gated every 5 ticks; comm change is not sub-second  [v4.0.19]
            if (( TICK_CTR % 5 == 0 )); then
                _exit_comm=""; read -r _exit_comm < "/proc/$PSOBB_PID/comm" 2>/dev/null
                if [[ -n "$_exit_comm" && "$_exit_comm" != "psobb.exe" ]]; then
                    echo -e "\n"; [[ "$FAN_IS_LOCKED" -eq 1 && "$HAS_FAN_NODE" -eq 1 ]] && printf "level auto\n" > /proc/acpi/ibm/fan 2>/dev/null
                    t_echo "[!] Game Engine Terminated. Triggering Cleanup Trap..."; exit 0
                fi
            fi
        fi

        # [N13] Thermal state machine — gated on THM_GUARD_EN  [v4.4.5]
        (( THM_GUARD_EN )) && mng_thm

        # [N14] Hardened live clock read
        if (( HAS_FREQ_NODE )); then
            read -r _cur_khz < "$CPU_FREQ_NODE" 2>/dev/null
            [[ -n "$_cur_khz" ]] && CPU_LIVE_MHZ=$(( _cur_khz / 1000 )) || CPU_LIVE_MHZ="---"
        fi

        # [N15] MT_DUE — force, interval, or TID churn  [v3.9.2:M1]
        MT_DUE=0
        if (( FORCE_MEDIUM == 1 )); then
            MT_DUE=1; FORCE_MEDIUM=0                          # explicit force
        elif (( TICK_CTR % MT_INTV == 0 )); then
            MT_DUE=1                                          # interval trigger
        else
            set -- /proc/"$PSOBB_PID"/task/*                  # count-only glob — no array alloc  [v4.2.0G]
            CUR_TID_COUNT=$#
            if (( CUR_TID_COUNT != LAST_TID_COUNT )); then
                MT_DUE=1; LAST_TID_COUNT=$CUR_TID_COUNT       # churn trigger
                G_VLD=0; inv_tc
            fi
        fi

        if (( MT_DUE == 1 )); then
            # Refresh TID count at rebuild so churn baseline stays current  [v4.0.19]
            _cur_tid_glob=( /proc/"$PSOBB_PID"/task/* ); LAST_TID_COUNT=${#_cur_tid_glob[@]}
            printf -v _mt_time "%(%H:%M:%S)T" -1; mt_w0=0; mt_w1=0; w_us=0; mt_us=0
            # [N16] MT baseline wait
            if [[ -n "$MON_SCHED_PATH" ]]; then read -r _ mt_w0 _ < "$MON_SCHED_PATH" 2>/dev/null; (( MON_WAIT_NS == 0 )) && MON_WAIT_NS=$mt_w0; fi
            # [N17] Authoritative re-pin — stderr suppressed, stdout open for Goliath t_echo  [v4.4.11]
            cls_th 2>/dev/null; set_pr >/dev/null 2>&1; pin_th >/dev/null 2>&1
            # [N18] Calculate hitch delta
            if [[ -n "$MON_SCHED_PATH" ]]; then mt_w1=0; read -r _ mt_w1 _ < "$MON_SCHED_PATH" 2>/dev/null; w_us=$(( (mt_w1 - MON_WAIT_NS) / 1000 )); mt_us=$(( (mt_w1 - mt_w0) / 1000 )); MT_HITCH_US=$mt_us; MON_WAIT_NS=$mt_w1; (( mt_us < 0 )) && mt_us=0; (( w_us < 0 )) && w_us=0
                if (( MT_COLD_SKIP )); then
                    MT_COLD_SKIP=0  # [v4.4.8] discard cold hitch — cls_th on fresh thread pool takes ~2.5s
                else
                    # [N19] Update ring buffer
                    printf -v _mt_ring_entry 'tick:%-4d %s Δ=%-8dµs total=%-8dµs' "$TICK_CTR" "$_mt_time" "$mt_us" "$w_us"; MT_RING[$MT_RING_POS]="$_mt_ring_entry"; MT_RING_POS=$(( (MT_RING_POS + 1) % MT_RING_SIZE ))
                    # [N20] Edge-trigger alert
                    if (( mt_us > MT_HITCH_THR_US )); then printf "\n  [MT:%s t:%d] Δ=%dµs | tot=%dµs\n" "$_mt_time" "$TICK_CTR" "$mt_us" "$w_us"; lg "MT tick:${TICK_CTR} MONSTER wait Δ=${mt_us}µs | total=${w_us}µs"; fi
                fi
            fi
        fi

        # [N21] Interface HUD strings
        [[ $TEL_EN -eq 0 ]] && MODE_TEXT="MUT" || MODE_TEXT="LIV"; [[ "$FAN_IS_LOCKED" -eq 1 ]] && FAN_TEXT="${FAN_TIMER}s" || FAN_TEXT="Auto"
        
        # [N22] GPU read — gated every 7 ticks; single variable GPU_CUR_MHZ  [v3.9.9:F1]
        if (( HAS_GPU_NODE && i % 7 == 1 )); then
            read -r _gpu_raw < "$GPU_CUR_NODE" 2>/dev/null
            [[ -n "$_gpu_raw" ]] && GPU_CUR_MHZ="${_gpu_raw}" || GPU_CUR_MHZ="---"
        fi
        # [N23] HUD print
        printf "\r\033[K [♥%-5s %sC %sM %sMg F:%-4s %s]" "$i/15" "$CPU_TEMP" "$CPU_LIVE_MHZ" "$GPU_CUR_MHZ" "$FAN_TEXT" "$MODE_TEXT"

        # [N24] Keypress poll — drain stale input then block for tick duration
        read -t 0 -n 1 discard 2>/dev/null || true; read -t "$FAST_TIER_TICK_S" -n 1 -s key || true
        handle_keypress "$key" || break
    done 
    # [N25] Telemetry close report
    if [[ $TEL_EN -eq 1 ]]; then tel_end; t_echo "[!] 30s Session Over. Recalibrating..."; else printf "\n"; fi
# [N26/27] Burst trigger sequence
    if [[ "$LOG_EN" -eq 1 && -n "$PSOBB_PID" ]]; then
        if (( BURST_ARMED == 1 )); then
            BURST_ARMED=0; burst_sample "combat"              # [N26] combat-triggered
        elif (( TEL_WINDOW > 0 &&
                TEL_WINDOW % PERIODIC_BURST_INTV == 0 &&
                BURST_LAST_WINDOW != TEL_WINDOW )); then
            burst_sample "periodic"                           # [N27] periodic
        fi
    fi
done
