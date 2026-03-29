#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cmd="${1:-}"
shift || true

log() {
  printf '[ci] %s\n' "$*"
}

die() {
  printf '[ci][error] %s\n' "$*" >&2
  exit 1
}

as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    "$@"
  fi
}

write_env() {
  local key="$1"
  local value="$2"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_ENV"
  fi
  export "$key=$value"
}

source_ini() {
  local file="$1"
  if [[ -f "$file" ]]; then
    # shellcheck disable=SC1090
    source "$file"
  fi
}

urlencode() {
  python3 - "$1" <<'PY'
import urllib.parse
import sys
print(urllib.parse.quote(sys.argv[1]))
PY
}

gh_api() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local token="${REPO_TOKEN:-${GITHUB_TOKEN:-}}"
  [[ -n "$token" ]] || die "REPO_TOKEN or GITHUB_TOKEN is required"
  if [[ -n "$data" ]]; then
    curl -fsSL -X "$method" \
      -H "Authorization: Bearer $token" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -d "$data" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}${path}"
  else
    curl -fsSL -X "$method" \
      -H "Authorization: Bearer $token" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}${path}"
  fi
}

load_context() {
  local folder="${1:?usage: load-context <folder>}"
  local build_dir="$repo_root/build/$folder"
  local base_ini="$build_dir/settings.ini"
  local rel_ini="$build_dir/relevance/settings.ini"

  local _REPO_BRANCH="${REPO_BRANCH:-}"
  local _CONFIG_FILE="${CONFIG_FILE:-}"
  local _SOURCE_BRANCH="${SOURCE_BRANCH:-}"
  local _SOURCE="${SOURCE:-}"
  local _SOURCE_CODE="${SOURCE_CODE:-}"
  local _INFORMATION_NOTICE="${INFORMATION_NOTICE:-}"
  local _KEEP_WORKFLOWS="${KEEP_WORKFLOWS:-}"
  local _KEEP_RELEASES="${KEEP_RELEASES:-}"
  local _SSH_ACTION="${SSH_ACTION:-}"
  local _UPLOAD_FIRMWARE="${UPLOAD_FIRMWARE:-}"
  local _UPLOAD_RELEASE="${UPLOAD_RELEASE:-}"
  local _CACHEWRTBUILD_SWITCH="${CACHEWRTBUILD_SWITCH:-}"
  local _UPDATE_FIRMWARE_ONLINE="${UPDATE_FIRMWARE_ONLINE:-}"
  local _COMPILATION_INFORMATION="${COMPILATION_INFORMATION:-}"

  source_ini "$base_ini"
  source_ini "$rel_ini"

  [[ -n "$_REPO_BRANCH" ]] && REPO_BRANCH="$_REPO_BRANCH"
  [[ -n "$_CONFIG_FILE" ]] && CONFIG_FILE="$_CONFIG_FILE"
  [[ -n "$_SOURCE_BRANCH" ]] && SOURCE_BRANCH="$_SOURCE_BRANCH"
  [[ -n "$_SOURCE" ]] && SOURCE="$_SOURCE"
  [[ -n "$_SOURCE_CODE" ]] && SOURCE_CODE="$_SOURCE_CODE"
  [[ -n "$_INFORMATION_NOTICE" ]] && INFORMATION_NOTICE="$_INFORMATION_NOTICE"
  [[ -n "$_KEEP_WORKFLOWS" ]] && KEEP_WORKFLOWS="$_KEEP_WORKFLOWS"
  [[ -n "$_KEEP_RELEASES" ]] && KEEP_RELEASES="$_KEEP_RELEASES"
  [[ -n "$_SSH_ACTION" ]] && SSH_ACTION="$_SSH_ACTION"
  [[ -n "$_UPLOAD_FIRMWARE" ]] && UPLOAD_FIRMWARE="$_UPLOAD_FIRMWARE"
  [[ -n "$_UPLOAD_RELEASE" ]] && UPLOAD_RELEASE="$_UPLOAD_RELEASE"
  [[ -n "$_CACHEWRTBUILD_SWITCH" ]] && CACHEWRTBUILD_SWITCH="$_CACHEWRTBUILD_SWITCH"
  [[ -n "$_UPDATE_FIRMWARE_ONLINE" ]] && UPDATE_FIRMWARE_ONLINE="$_UPDATE_FIRMWARE_ONLINE"
  [[ -n "$_COMPILATION_INFORMATION" ]] && COMPILATION_INFORMATION="$_COMPILATION_INFORMATION"

  SOURCE_CODE="${SOURCE_CODE:-${folder^^}}"
  SOURCE="${SOURCE:-${SOURCE_BRANCH:-$SOURCE_CODE}}"
  REPO_BRANCH="${REPO_BRANCH:-master}"
  CONFIG_FILE="${CONFIG_FILE:-${TARGET_PROFILE:-}}"
  if [[ -z "$CONFIG_FILE" ]]; then
    CONFIG_FILE="x86_64"
  fi
  TARGET_PROFILE="${TARGET_PROFILE:-$CONFIG_FILE}"
  DIY_WORK="${DIY_WORK:-workdir}"
  UPDATE_FIRMWARE_ONLINE="${UPDATE_FIRMWARE_ONLINE:-false}"
  ONLINE_FIRMWARE="${ONLINE_FIRMWARE:-$UPDATE_FIRMWARE_ONLINE}"
  UPLOAD_FIRMWARE="${UPLOAD_FIRMWARE:-false}"
  UPLOAD_RELEASE="${UPLOAD_RELEASE:-false}"
  CACHEWRTBUILD_SWITCH="${CACHEWRTBUILD_SWITCH:-false}"
  COMPILATION_INFORMATION="${COMPILATION_INFORMATION:-false}"
  KEEP_WORKFLOWS="${KEEP_WORKFLOWS:-50}"
  KEEP_RELEASES="${KEEP_RELEASES:-30}"
  INFORMATION_NOTICE="${INFORMATION_NOTICE:-关闭}"
  SSH_ACTION="${SSH_ACTION:-false}"
  RELEASE_KEEP_KEYWORD="${RELEASE_KEEP_KEYWORD:-targz/Update}"
  CLEAR_PATH_FILE="$repo_root/.ci/$folder.clear"
  DELETE_FILE="$repo_root/.ci/$folder.delete"

  case "$SOURCE_CODE" in
    OFFICIAL)
      REPO_URL="${REPO_URL:-https://github.com/openwrt/openwrt}"
      ;;
    COOLSNOWWOLF)
      REPO_URL="${REPO_URL:-https://github.com/coolsnowwolf/lede}"
      ;;
    LIENOL)
      REPO_URL="${REPO_URL:-https://github.com/Lienol/openwrt}"
      ;;
    IMMORTALWRT)
      REPO_URL="${REPO_URL:-https://github.com/immortalwrt/immortalwrt}"
      ;;
    XWRT)
      REPO_URL="${REPO_URL:-https://github.com/x-wrt/x-wrt}"
      ;;
    MT798X)
      if [[ "$REPO_BRANCH" == "hanwckf-21.02" ]]; then
        REPO_URL="${REPO_URL:-https://github.com/hanwckf/immortalwrt-mt798x}"
      else
        REPO_URL="${REPO_URL:-https://github.com/padavanonly/immortalwrt-mt798x-24.10}"
      fi
      ;;
    *)
      REPO_URL="${REPO_URL:-}"
      ;;
  esac

  mkdir -p "$repo_root/.ci/$folder"

  write_env BUILD_DIR "$build_dir"
  write_env FOLDER_NAME "$folder"
  write_env DIY_WORK "$DIY_WORK"
  write_env SOURCE_CODE "$SOURCE_CODE"
  write_env SOURCE "$SOURCE"
  write_env SOURCE_BRANCH "${SOURCE_BRANCH:-}"
  write_env REPO_BRANCH "$REPO_BRANCH"
  write_env REPO_URL "$REPO_URL"
  write_env CONFIG_FILE "$CONFIG_FILE"
  write_env TARGET_PROFILE "$TARGET_PROFILE"
  write_env ONLINE_FIRMWARE "$ONLINE_FIRMWARE"
  write_env UPDATE_FIRMWARE_ONLINE "$UPDATE_FIRMWARE_ONLINE"
  write_env UPLOAD_FIRMWARE "$UPLOAD_FIRMWARE"
  write_env UPLOAD_RELEASE "$UPLOAD_RELEASE"
  write_env CACHEWRTBUILD_SWITCH "$CACHEWRTBUILD_SWITCH"
  write_env COMPILATION_INFORMATION "$COMPILATION_INFORMATION"
  write_env KEEP_WORKFLOWS "$KEEP_WORKFLOWS"
  write_env KEEP_RELEASES "$KEEP_RELEASES"
  write_env INFORMATION_NOTICE "$INFORMATION_NOTICE"
  write_env SSH_ACTION "$SSH_ACTION"
  write_env RELEASE_KEEP_KEYWORD "$RELEASE_KEEP_KEYWORD"
  write_env CLEAR_PATH_FILE "$CLEAR_PATH_FILE"
  write_env DELETE_FILE "$DELETE_FILE"

  log "context loaded: folder=$folder source=$SOURCE_CODE branch=$REPO_BRANCH config=$CONFIG_FILE"
}

bootstrap() {
  log "installing build dependencies"
  as_root apt-get -qq update
  as_root env DEBIAN_FRONTEND=noninteractive apt-get -qq install -y \
    build-essential clang flex bison gawk gcc-multilib g++-multilib gettext git \
    libncurses5-dev libssl-dev python2.7 python3 python3-distutils python3-pip \
    python3-setuptools rsync unzip zlib1g-dev file wget curl subversion swig time \
    xxd ccache libelf-dev patch zstd zip jq libpython3-dev tmate
  as_root timedatectl set-timezone "${TZ:-Asia/Shanghai}" || true
  mkdir -p "${HOME}/.ccache" || true
  ccache -M 5G >/dev/null 2>&1 || true
}

cleanup_disk() {
  log "freeing runner disk space"
  as_root env DEBIAN_FRONTEND=noninteractive apt-get -y purge --auto-remove \
    azure-cli google-cloud-cli microsoft-edge-stable google-chrome-stable firefox \
    'postgresql*' 'temurin-*' '*llvm*' 'mysql*' 'dotnet-sdk-*' || true
  as_root rm -rf /usr/share/swift /usr/share/miniconda /usr/share/az* /usr/share/glade* \
    /usr/local/lib/node_modules /usr/local/share/chromium /usr/local/share/powershell || true
  as_root rm -rf /opt/ghc /usr/local/.ghcup /swapfile || true
  as_root swapoff -a || true
  as_root apt-get -qq clean || true
  as_root rm -rf /var/lib/apt/lists/* || true
}

prepare_openwrt() {
  local folder="${1:?usage: prepare-openwrt <folder> <openwrt-root>}"
  local openwrt_root="${2:?usage: prepare-openwrt <folder> <openwrt-root>}"
  local build_dir="$repo_root/build/$folder"
  local seed_file="$build_dir/seed/${CONFIG_FILE:-}"

  [[ -d "$openwrt_root" ]] || die "openwrt root not found: $openwrt_root"
  mkdir -p "$repo_root/.ci/$folder"
  : > "$CLEAR_PATH_FILE"
  : > "$DELETE_FILE"

  if [[ -f "$seed_file" ]]; then
    cp -f "$seed_file" "$openwrt_root/.config"
    log "seed applied: $seed_file"
  fi

  if [[ -d "$build_dir/diy" ]]; then
    rsync -a --exclude 'README' "$build_dir/diy/" "$openwrt_root/"
    log "diy tree applied"
  fi

  if [[ -d "$build_dir/files" ]]; then
    mkdir -p "$openwrt_root/files"
    rsync -a --exclude 'README' "$build_dir/files/" "$openwrt_root/files/"
    log "files overlay applied"
  fi

  if [[ -d "$build_dir/patches" ]]; then
    while IFS= read -r patch; do
      [[ -n "$patch" ]] || continue
      patch -d "$openwrt_root" -p1 < "$patch"
    done < <(find "$build_dir/patches" -type f \( -name '*.patch' -o -name '*.diff' \) | sort)
    log "patches applied"
  fi

  if [[ -x "$build_dir/diy-part.sh" ]]; then
    CLEAR_PATH="$CLEAR_PATH_FILE" DELETE="$DELETE_FILE" bash "$build_dir/diy-part.sh"
    log "diy-part executed"
  fi

  if [[ -x "$openwrt_root/scripts/feeds" ]]; then
    (cd "$openwrt_root" && ./scripts/feeds update -a && ./scripts/feeds install -a)
    log "feeds updated and installed"
  fi

  if [[ -f "$openwrt_root/.config" ]]; then
    (cd "$openwrt_root" && make defconfig)
    log "defconfig completed"
  fi
}

finalize_firmware() {
  local folder="${1:?usage: finalize-firmware <folder> <openwrt-root>}"
  local openwrt_root="${2:?usage: finalize-firmware <folder> <openwrt-root>}"
  local clear_file="$repo_root/.ci/$folder.clear"
  local targets="$openwrt_root/bin/targets"

  [[ -d "$targets" ]] || die "targets directory not found: $targets"
  if [[ -f "$clear_file" ]]; then
    while IFS= read -r pattern; do
      [[ -n "$pattern" ]] || continue
      find "$targets" -name "$pattern" -exec rm -rf {} +
    done < "$clear_file"
    log "firmware artifacts pruned by clear list"
  fi
}

package_aarch() {
  local dir="${1:-${FIRMWARE_PATH:-$repo_root/openwrt/bin/targets}}"
  [[ -d "$dir" ]] || die "packaging directory not found: $dir"
  local rootfs
  rootfs="$(find "$dir" -type f -name '*rootfs.tar.gz' | sort | head -n1 || true)"
  [[ -n "$rootfs" ]] || die "no rootfs.tar.gz found in $dir"
  if [[ -n "${amlogic_model:-}" || -n "${amlogic_kernel:-}" || -n "${kernel_usage:-}" || -n "${openwrt_size:-}" ]]; then
    local workdir repo_dir
    workdir="$(mktemp -d /tmp/aarch-pack.XXXXXX)"
    repo_dir="$workdir/amlogic-s9xxx-openwrt"
    log "packaging with ophub/amlogic-s9xxx-openwrt"
    git clone --depth 1 https://github.com/ophub/amlogic-s9xxx-openwrt.git "$repo_dir"
    mkdir -p "$repo_dir/openwrt-armvirt"
    cp -f "$rootfs" "$repo_dir/openwrt-armvirt/openwrt-armvirt-64-default-rootfs.tar.gz"
    (
      cd "$repo_dir"
      as_root ./make \
        -b "${amlogic_model:-all}" \
        -k "${amlogic_kernel:-}" \
        -u "${kernel_usage:-stable}" \
        -a "${auto_kernel:-true}" \
        -s "${openwrt_size:-1024}" \
        -n "${builder_name:-ophub}"
    )
    [[ -d "$repo_dir/out" ]] || die "packager did not produce out/ directory"
    rsync -a "$repo_dir/out/" "$dir/"
    log "aarch packaging completed into $dir"
  else
    log "aarch packaging source: $rootfs"
  fi
}

notice() {
  local stage="${1:-notice}"
  local msg="[${FOLDER_NAME:-unknown}] ${stage}: source=${SOURCE_CODE:-unknown} branch=${REPO_BRANCH:-unknown} config=${CONFIG_FILE:-unknown}"
  log "$msg"

  case "${INFORMATION_NOTICE:-关闭}" in
    Telegram)
      if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
        curl -fsSL -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
          -d "chat_id=${TELEGRAM_CHAT_ID}" -d "text=${msg}" >/dev/null || true
      fi
      ;;
    Pushplus)
      if [[ -n "${PUSH_PLUS_TOKEN:-}" ]]; then
        curl -fsSL -X POST -H "Content-Type: application/json" \
          -d "$(jq -n --arg token "$PUSH_PLUS_TOKEN" --arg title "$stage" --arg content "$msg" \
            '{token:$token,title:$title,content:$content,template:"html"}')" \
          "http://www.pushplus.plus/send" >/dev/null || true
      fi
      ;;
  esac
}

need() {
  if [[ "${SSH_ACTION:-false}" == "true" ]]; then
    local sock="/tmp/tmate.sock"
    local cont_file="/tmp/ssh-action-continue"
    if ! command -v tmate >/dev/null 2>&1; then
      log "tmate not found, installing it"
      as_root env DEBIAN_FRONTEND=noninteractive apt-get -qq update
      as_root env DEBIAN_FRONTEND=noninteractive apt-get -qq install -y tmate
    fi
    rm -f "$cont_file"
    log "starting tmate session"
    tmate -S "$sock" new-session -d
    tmate -S "$sock" wait tmate-ready
    log "SSH: $(tmate -S "$sock" display -p '#{tmate_ssh}' 2>/dev/null || true)"
    log "Web: $(tmate -S "$sock" display -p '#{tmate_web}' 2>/dev/null || true)"
    log "When config work is done, run: touch $cont_file"
    while [[ ! -f "$cont_file" ]]; do
      if ! tmate -S "$sock" display -p '#{tmate_session_id}' >/dev/null 2>&1; then
        log "tmate session ended"
        break
      fi
      sleep 10
    done
    tmate -S "$sock" kill-session >/dev/null 2>&1 || true
    log "SSH session finished"
  else
    log "SSH_ACTION disabled"
  fi
}

check_token() {
  [[ -n "${REPO_TOKEN:-${GITHUB_TOKEN:-}}" ]] || die "REPO_TOKEN is required"
  log "token check passed"
}

cleanup_github() {
  local keep_releases="${KEEP_RELEASES:-0}"
  local keep_workflows="${KEEP_WORKFLOWS:-0}"
  local release_keyword="${RELEASE_KEEP_KEYWORD:-targz|Update}"
  local token="${REPO_TOKEN:-${GITHUB_TOKEN:-}}"
  [[ -n "$token" ]] || die "REPO_TOKEN or GITHUB_TOKEN is required"

  log "cleaning releases/workflows"

  local page=1
  local kept=0
  while :; do
    local data
    data="$(curl -fsSL \
      -H "Authorization: Bearer $token" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases?per_page=100&page=${page}")"
    [[ "$(jq 'length' <<<"$data")" -gt 0 ]] || break
    while IFS=$'\t' read -r rid rtag rname; do
      if [[ "$rtag" =~ $release_keyword || "$rname" =~ $release_keyword ]]; then
        continue
      fi
      if [[ "$kept" -lt "$keep_releases" ]]; then
        kept=$((kept + 1))
        continue
      fi
      curl -fsSL -X DELETE \
        -H "Authorization: Bearer $token" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/${rid}" >/dev/null || true
      if [[ -n "$rtag" && "$rtag" != "null" ]]; then
        curl -fsSL -X DELETE \
          -H "Authorization: Bearer $token" \
          -H "Accept: application/vnd.github+json" \
          -H "X-GitHub-Api-Version: 2022-11-28" \
          "https://api.github.com/repos/${GITHUB_REPOSITORY}/git/refs/tags/${rtag}" >/dev/null || true
      fi
    done < <(jq -r '.[] | [.id, .tag_name, .name] | @tsv' <<<"$data")
    page=$((page + 1))
  done

  page=1
  kept=0
  while :; do
    local data
    data="$(curl -fsSL \
      -H "Authorization: Bearer $token" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/runs?per_page=100&page=${page}")"
    [[ "$(jq '.workflow_runs | length' <<<"$data")" -gt 0 ]] || break
    while IFS=$'\t' read -r rid status; do
      if [[ "$status" != "completed" ]]; then
        continue
      fi
      if [[ "$kept" -lt "$keep_workflows" ]]; then
        kept=$((kept + 1))
        continue
      fi
      curl -fsSL -X DELETE \
        -H "Authorization: Bearer $token" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/runs/${rid}" >/dev/null || true
    done < <(jq -r '.workflow_runs[] | [.id, .status] | @tsv' <<<"$data")
    page=$((page + 1))
  done
}

upload_release() {
  local tag="${1:-${RELEASE_TAG:-targz}}"
  local dir="${2:-${FIRMWARE_PATH:-$repo_root/openwrt/bin/targets}}"
  local token="${REPO_TOKEN:-${GITHUB_TOKEN:-}}"
  [[ -n "$token" ]] || die "REPO_TOKEN or GITHUB_TOKEN is required"
  [[ -d "$dir" ]] || die "upload directory not found: $dir"

  local release
  if ! release="$(curl -fsSL \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/tags/${tag}" 2>/dev/null)"; then
    local payload
    payload="$(jq -n --arg tag "$tag" --arg name "$tag" --arg target "${GITHUB_REF_NAME:-main}" \
      '{tag_name:$tag,name:$name,target_commitish:$target,draft:false,prerelease:false}')"
    release="$(curl -fsSL -X POST \
      -H "Authorization: Bearer $token" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -d "$payload" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases")"
  fi

  local upload_url release_id
  release_id="$(jq -r '.id' <<<"$release")"
  upload_url="$(jq -r '.upload_url' <<<"$release" | sed 's/{.*//')"

  mapfile -t files < <(find "$dir" -type f ! -path '*/packages/*' \
    \( -name '*.tar.gz' -o -name '*.img.gz' -o -name '*.bin' -o -name '*.manifest' -o -name '*.buildinfo' -o -name 'sha256sums' \) | sort)
  [[ "${#files[@]}" -gt 0 ]] || die "no uploadable files found in $dir"

  local file base encoded assets asset_id
  assets="$(curl -fsSL \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/${release_id}/assets")"

  for file in "${files[@]}"; do
    base="$(basename "$file")"
    encoded="$(urlencode "$base")"
    asset_id="$(jq -r --arg n "$base" '.[] | select(.name == $n) | .id' <<<"$assets" | head -n1)"
    if [[ -n "${asset_id:-}" && "${asset_id:-null}" != "null" ]]; then
      curl -fsSL -X DELETE \
        -H "Authorization: Bearer $token" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/assets/${asset_id}" >/dev/null || true
    fi
    curl -fsSL -X POST \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/octet-stream" \
      --data-binary @"$file" \
      "${upload_url}?name=${encoded}" >/dev/null
    log "uploaded $base to release $tag"
  done
}

trigger_compile() {
  local folder="${1:?usage: trigger <folder>}"
  local token="${REPO_TOKEN:-${GITHUB_TOKEN:-}}"
  [[ -n "$token" ]] || die "REPO_TOKEN or GITHUB_TOKEN is required"

  local build_dir="$repo_root/build/$folder"
  local rel_dir="$build_dir/relevance"
  local rel_ini="$rel_dir/settings.ini"
  local start_file="$rel_dir/start"
  mkdir -p "$rel_dir"

  cat > "$rel_ini" <<EOF
SOURCE_CODE=${SOURCE_CODE}
REPO_BRANCH=${REPO_BRANCH}
CONFIG_FILE=${CONFIG_FILE}
INFORMATION_NOTICE=${INFORMATION_NOTICE}
UPLOAD_FIRMWARE=${UPLOAD_FIRMWARE}
UPLOAD_RELEASE=${UPLOAD_RELEASE}
CACHEWRTBUILD_SWITCH=${CACHEWRTBUILD_SWITCH}
UPDATE_FIRMWARE_ONLINE=${UPDATE_FIRMWARE_ONLINE}
COMPILATION_INFORMATION=${COMPILATION_INFORMATION}
KEEP_WORKFLOWS=${KEEP_WORKFLOWS}
KEEP_RELEASES=${KEEP_RELEASES}
ERRUN_NUMBER=${ERRUN_NUMBER:-3}
EOF

  printf '%s-%s-%s-%s\n' \
    "$folder" "${REPO_BRANCH:-master}" "${CONFIG_FILE:-x86_64}" \
    "$(TZ="${TZ:-Asia/Shanghai}" date '+%Y年%m月%d号%H时%M分%S秒')" > "$start_file"

  git -C "$repo_root" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git -C "$repo_root" config user.name "github-actions[bot]"
  git -C "$repo_root" remote set-url origin "https://x-access-token:${token}@github.com/${GITHUB_REPOSITORY}.git"
  git -C "$repo_root" add "$rel_ini" "$start_file"
  git -C "$repo_root" commit -m "Update $(date +%Y-%m%d-%H%M%S)" || true
  git -C "$repo_root" push --quiet origin HEAD:"${GITHUB_REF_NAME:-main}"
  log "trigger pushed for $folder"

  local workflow_path="compile.yml"
  local payload
  payload="$(jq -n --arg ref "${GITHUB_REF_NAME:-main}" '{ref:$ref}')"
  curl -fsSL -X POST \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d "$payload" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/workflows/${workflow_path}/dispatches" >/dev/null
  log "workflow dispatched: $workflow_path on ref ${GITHUB_REF_NAME:-main}"
}

create_workflow_folder() {
  local sample="${1:?usage: create-workflow-folder <sample> <name>}"
  local name="${2:?usage: create-workflow-folder <sample> <name>}"
  local src_build="$repo_root/build/$sample"
  local dst_build="$repo_root/build/$name"
  local src_workflow="$repo_root/.github/workflows/$sample.yml"
  local dst_workflow="$repo_root/.github/workflows/$name.yml"

  [[ -d "$src_build" ]] || die "sample build folder not found: $src_build"
  [[ -f "$src_workflow" ]] || die "sample workflow not found: $src_workflow"
  [[ ! -e "$dst_build" ]] || die "target build folder already exists: $dst_build"
  [[ ! -e "$dst_workflow" ]] || die "target workflow already exists: $dst_workflow"

  cp -Rf "$src_build" "$dst_build"
  cp -f "$src_workflow" "$dst_workflow"

  local sample_name="$name"
  if [[ "$name" != *"$sample"* ]]; then
    sample_name="${sample}_${name}"
  fi

  sed -i "s?target: \\[.*\\]?target: \\[${name}\\]?g" "$dst_workflow"
  sed -i "0,/^name: .*$/s//name: ${sample_name}/" "$dst_workflow"
  log "workflow folder created: $name"
}

case "$cmd" in
  bootstrap)
    bootstrap
    ;;
  cleanup-disk)
    cleanup_disk
    ;;
  load-context)
    load_context "${1:?usage: load-context <folder>}"
    ;;
  prepare-openwrt)
    prepare_openwrt "${1:?usage: prepare-openwrt <folder> <openwrt-root>}" "${2:?usage: prepare-openwrt <folder> <openwrt-root>}"
    ;;
  finalize-firmware)
    finalize_firmware "${1:?usage: finalize-firmware <folder> <openwrt-root>}" "${2:?usage: finalize-firmware <folder> <openwrt-root>}"
    ;;
  package-aarch|aarch)
    package_aarch "${1:-}"
    ;;
  notice)
    notice "${1:-notice}"
    ;;
  need)
    need
    ;;
  check-token|yaoshi)
    check_token
    ;;
  cleanup-github)
    cleanup_github
    ;;
  upload-release)
    upload_release "${1:-}" "${2:-}"
    ;;
  trigger)
    trigger_compile "${1:?usage: trigger <folder>}"
    ;;
  create-workflow-folder)
    create_workflow_folder "${1:?usage: create-workflow-folder <sample> <name>}" "${2:?usage: create-workflow-folder <sample> <name>}"
    ;;
  *)
    cat >&2 <<EOF
usage: $0 <command> [args]
commands:
  bootstrap
  cleanup-disk
  load-context <folder>
  prepare-openwrt <folder> <openwrt-root>
  finalize-firmware <folder> <openwrt-root>
  package-aarch [dir]
  notice [stage]
  need
  check-token
  cleanup-github
  upload-release [tag] [dir]
  trigger <folder>
  create-workflow-folder <sample> <name>
EOF
    exit 1
    ;;
esac
