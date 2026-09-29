#!/usr/bin/env bash
# Build, pasang, lalu potret setiap adegan demo di simulator.
# Pemakaian: ios/scripts/screenshots.sh [UDID simulator]
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UDID="${1:-$(xcrun simctl list devices available | grep -m1 'iPhone 17 Pro (' | grep -oE '[0-9A-F-]{36}')}"
OUT="$ROOT/Screenshots"
APP="$ROOT/build/DerivedData/Build/Products/Debug-iphonesimulator/RambuPuck.app"
BUNDLE=id.rambu.puck

xcodebuild -project "$ROOT/RambuPuck.xcodeproj" -scheme RambuPuck \
  -destination "id=$UDID" -derivedDataPath "$ROOT/build/DerivedData" build -quiet
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time "09:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
mkdir -p "$OUT"
find "$OUT" -name "*.png" ! -name "*lock-screen*" -delete

# nama | adegan | tunggu (detik) | kecepatan (fast/normal)
shots=(
  "01-onboarding-sambutan|onboarding:welcome|2|fast"
  "02-onboarding-nama|onboarding:parentProfile|2|fast"
  "03-onboarding-pasang-puck|onboarding:pairPuck|2|fast"
  "04-onboarding-persetujuan|onboarding:consent|2|fast"
  "05-onboarding-undang-pengawas|onboarding:invite|5|fast"
  "06-onboarding-kode-pengawas|onboarding:enterCode|2|fast"
  "07-onboarding-nama-pengawas|onboarding:guardianProfile|2|fast"
  "08-beranda-orang-tua|home|2|fast"
  "09-riwayat|history|2|fast"
  "10-puck|puck|2|fast"
  "11-telepon-aman-tanpa-notif|call:tetangga-aman|3|fast"
  "12-telepon-perlu-dicek|call:kurir-aplikasi|3|normal"
  "13-telepon-bahaya|call:bank-otp|6|fast"
  "14-telepon-keputusan-penipuan|call-decided:bank-otp|7|fast"
  "15-pengawas-beranda-peringatan|guardian-alert-home:bank-otp|7|fast"
  "16-pengawas-peringatan|alert:bank-otp|7|fast"
  "17-pengawas-terkunci|alert-locked:kecelakaan-transfer|7|fast"
  "18-pengawas-terkirim|alert-mine:kecelakaan-transfer|7|fast"
  "19-pengawas-tenang|guardian-home|2|fast"
)

for entry in "${shots[@]}"; do
  IFS='|' read -r name scene wait speed <<<"$entry"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  if [[ "$scene" == home ]]; then
    envs=(SIMCTL_CHILD_RAMBU_SKIP_ONBOARDING=1)
  else
    envs=(SIMCTL_CHILD_RAMBU_SCENE="$scene")
  fi
  [[ "$speed" == fast ]] && envs+=(SIMCTL_CHILD_RAMBU_FAST=1)
  env "${envs[@]}" xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "✓ $name"
done
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
echo "Selesai: $OUT"
