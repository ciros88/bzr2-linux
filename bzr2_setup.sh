#!/bin/bash
#
# NAME
#     bzr2_setup.sh - distribution-agnostic BZR Player 2.x (BZR2) linux installer
#
# SYNOPSIS
#     ./bzr2_setup.sh
#
# DESCRIPTION
#     download, install and configure BZR2 using wine, also providing the way to remove it
#
#     handle multiple BZR2 versions (useful for testing purposes) in separated
#     wine prefixes at ~/.bzr-player/<version>-<wine arch>
#
#     also install icons and generates an XDG desktop entry for launching the player,
#     eventually associated to supported MIME types
#
# NOTES
#     - versions older than 2.0.19 are not supported
#
# AUTHOR
#     Ciro Scognamiglio

set -e

main() {

  if [ "$(id -u)" -ne 0 ]; then
    echo "Root privileges are required"
    exit 1
  fi

  USER=${SUDO_USER}
  HOME=$(eval echo ~"$SUDO_USER")

  action_default="setup"
  bzr2_last_version_url="https://raw.githubusercontent.com/ciros88/bzr2-linux/artifacts/last_version"
  bzr2_version_default="2.0.70"
  winearch_default="win32"
  force_reinstall_default="n"
  download_urls=(
    "http://bzrplayer.blazer.nu/getFile.php?id="
    "https://raw.githubusercontent.com/ciros88/bzr2-linux/artifacts/artifacts/"
  )
  download_tries=2
  bzr2_zip_dir_default="."
  bzr2_xml_dir_default="."
  dpi_default="auto"
  mime_types_association_default="y"
  mime_types_supported=(
    application/ogg audio/flac audio/midi audio/mp2 audio/mpeg audio/prs.sid audio/vnd.wave audio/x-ahx audio/x-aon
    audio/x-cust audio/x-ddmf audio/x-dw audio/x-dz audio/x-fc audio/x-fc-bsi audio/x-flac+ogg audio/x-fp audio/x-hip
    audio/x-hip-7v audio/x-hip-coso audio/x-hip-st audio/x-hip-st-coso audio/x-it audio/x-lds audio/x-m2 audio/x-mcmd
    audio/x-mdx audio/x-minipsf audio/x-ml audio/x-mmdc audio/x-mo3 audio/x-mod audio/x-mpegurl audio/x-mptm
    audio/x-nds-strm audio/x-nds-strm-ffta2 audio/x-ntk audio/x-okt audio/x-prun audio/x-psf audio/x-psm audio/x-pt3
    audio/x-ptk audio/x-s3m audio/x-sc2 audio/x-sc68 audio/x-scl audio/x-scn audio/x-sid2 audio/x-sndh audio/x-soundmon
    audio/x-spc audio/x-spl audio/x-stk audio/x-stm audio/x-sun audio/x-sunvox audio/x-symmod audio/x-tfmx
    audio/x-tfmx-st audio/x-umx audio/x-v2m audio/x-vgm audio/x-vorbis+ogg audio/x-xm
  )

  bold=$'\e[1m'
  bold_reset=$'\e[0m'

  invalid_value_inserted_message="please insert a valid value"

  bzr2_name="BZR Player"
  bzr2_pkgname="bzr-player"
  bzr2_wineprefix_dir_unversioned="$HOME/.$bzr2_pkgname"
  bzr2_exe_filename="BZRPlayer.exe"
  bzr2_launcher_filename="$bzr2_pkgname.sh"
  bzr2_xml_filename="x-$bzr2_pkgname.xml"
  bzr2_desktop_filename="$bzr2_pkgname.desktop"

  check_requirements
  check_setup_files

  has_matched_versioning_pattern_old=false
  icon_sizes=(16 32 48 64 128 256 512)
  icons_hicolor_path="/usr/share/icons/hicolor"
  mime_dir_system=/usr/share/mime
  mime_packages_dir_system="$mime_dir_system/packages"
  desktop_apps_dir_system="/usr/share/applications"

  get_action

  if [ "$action" == "setup" ]; then
    setup
  else
    remove
  fi
}

setup() {
  check_bzr2_last_version
  get_bzr2_version
  check_arch
  get_winearch

  bzr2_exe="$bzr2_dir/$bzr2_exe_filename"
  bzr2_launcher="$bzr2_wineprefix_dir/$bzr2_launcher_filename"
  bzr2_desktop="$bzr2_wineprefix_dir/$bzr2_desktop_filename"
  bzr2_icon="$bzr2_dir/resources/icon.png"

  if [ -f "$bzr2_exe" ]; then
    is_already_installed=true

    echo -e "\nBZR2 ${bold}$bzr2_version${bold_reset} ${bold}$winearch${bold_reset} installation detected at \
${bold}$bzr2_wineprefix_dir${bold_reset}"
    get_force_reinstall
  else
    is_already_installed=false
    force_reinstall="$force_reinstall_default"
  fi

  if ! $is_already_installed || [ "$force_reinstall" = y ]; then
    get_bzr2_zip_filenames
    download_bzr2

    if [ "$is_zip_downloaded" == false ]; then
      get_bzr2_local_zip_dir
    fi
  fi

  get_dpi
  get_mime_types_association

  if ! $is_already_installed || [ "$force_reinstall" = y ]; then
    if [ "$force_reinstall" = y ]; then
      sudo -u "$USER" rm -rf "$bzr2_wineprefix_dir"
    fi

    echo
    setup_bzr2
  fi

  setup_dpi
  setup_launcher_script
  setup_icon
  setup_desktop_entry

  if [ "$mime_types_association" = y ]; then
    setup_mime_types
  fi

  echo -e "\nAll done, enjoy ${bold}BZR2 $bzr2_version $winearch${bold_reset}!"
}

check_requirements() {
  local requirements=(
    cat curl install mktemp realpath sed sort sudo uname unzip update-desktop-database update-mime-database wget wine
    xdg-desktop-menu xdg-icon-resource xdg-mime xrdb
  )

  for requirement in "${requirements[@]}"; do
    if ! type "$requirement" &>/dev/null; then
      echo -e "\nplease install ${bold}$requirement${bold_reset}"
      exit 1
    fi
  done
}

check_setup_files() {
  local bzr2_xml_dir
  bzr2_xml_dir=$(realpath -s "$bzr2_xml_dir_default")
  bzr2_xml="$bzr2_xml_dir/$bzr2_xml_filename"

  if [ ! -f "$bzr2_xml" ]; then
    echo -e "\nfile ${bold}$bzr2_xml${bold_reset} not found"
    exit 1
  fi
}

show_message_and_read_input() {
  read -rp $'\n'"$1 (${bold}$2${bold_reset}): " input
  if [ -n "$input" ]; then
    echo "$input"
  else
    echo "$2"
  fi
}

get_action() {
  while :; do
    local input
    input=$(show_message_and_read_input "do you want to ${bold}setup${bold_reset} or ${bold}remove${bold_reset} \
BZR2?" ${action_default})

    case $input in
    setup | remove)
      break
      ;;
    *)
      echo -e "\n$invalid_value_inserted_message"
      ;;
    esac
  done

  action="$input"
}

check_bzr2_last_version() {
  echo -en "\nchecking last version online... "

  set +e
  local last_version
  last_version=$(curl -fs "$bzr2_last_version_url")
  local curl_result=$?
  set -e

  if [ $curl_result -eq 0 ]; then
    echo "${bold}$last_version${bold_reset} found"
    bzr2_version_default=$last_version
  else
    echo "FAIL"
  fi
}

get_bzr2_version() {
  # matches 2. >=0 AND <=9 . >=61 AND <=999
  local versioning_pattern="^2\.[0-9]\.{1}+(6[1-9]|[7-9][0-9]|[1-9][0-9]{2})$"

  # matches 2.0. >=19 AND <=60
  local versioning_pattern_old="^2\.0\.{1}+(19|[2-5][0-9]|60){1}$"

  while :; do
    local input
    input=$(show_message_and_read_input "select the version to manage" "${bzr2_version_default}")

    if [[ "$input" =~ $versioning_pattern ]]; then
      break
    fi

    if [[ "$input" =~ $versioning_pattern_old ]]; then
      has_matched_versioning_pattern_old=true
      break
    fi

    echo -e "\n$invalid_value_inserted_message"
  done

  bzr2_version="${input,,}"
}

check_arch() {
  if [ "$(uname -m)" == "x86_64" ]; then
    winearch_default="win64"
  fi
}

get_winearch() {
  while :; do
    local input
    input=$(show_message_and_read_input "select the 32/64 bit ${bold}win32${bold_reset} or ${bold}win64${bold_reset} \
wine environment (multilib pkgs could be required)" ${winearch_default})

    case $input in
    win32)
      bzr2_wineprefix_dir="$bzr2_wineprefix_dir_unversioned/$bzr2_version-$input"
      bzr2_dir="$bzr2_wineprefix_dir/drive_c/Program Files/$bzr2_name"
      break
      ;;
    win64)
      bzr2_wineprefix_dir="$bzr2_wineprefix_dir_unversioned/$bzr2_version-$input"
      bzr2_dir="$bzr2_wineprefix_dir/drive_c/Program Files (x86)/$bzr2_name"
      break
      ;;
    *)
      echo -e "\n$invalid_value_inserted_message"
      ;;
    esac
  done

  winearch="$input"
}

get_force_reinstall() {
  while :; do
    local input
    input=$(show_message_and_read_input "force reinstall (fresh installation, does not keep settings), \
otherwise only the configuration will be performed" ${force_reinstall_default})

    case $input in
    y | n)
      break
      ;;
    *)
      echo -e "\n$invalid_value_inserted_message"
      ;;
    esac
  done

  force_reinstall="$input"
}

get_bzr2_zip_filenames() {
  if $has_matched_versioning_pattern_old; then
    bzr2_zip_filenames=("$(echo "$bzr2_version" | sed 's/.0.//;s/$/.zip/')")
  else
    local bzr2_version_minor="${bzr2_version##*.}"

    if [ "$bzr2_version_minor" -lt 67 ]; then
      bzr2_zip_filenames=("$bzr2_version.zip")
    elif [ "$bzr2_version_minor" -eq 67 ]; then
      bzr2_zip_filenames=("$bzr2_version.zip" "BZR-Player-$bzr2_version.zip")
    else
      bzr2_zip_filenames=("BZR-Player-$bzr2_version.zip")
    fi
  fi
}

bzr2_zip_sanity_check() {
  echo -n "sanity check... "

  if unzip -tq "$1" >/dev/null 2>&1 && [ "$(unzip -l "$1" | grep -c "$bzr2_exe_filename")" -eq 1 ] >/dev/null 2>&1; then
    echo "OK"
    return 0
  else
    echo -n "FAIL"
    return 1
  fi
}

download_bzr2() {
  local download_dir
  for tmp_dir in "$XDG_RUNTIME_DIR" "$TMPDIR" "$(dirname "$(mktemp -u --tmpdir)")" "/tmp" "/var/tmp" "/var/cache"; do
    if [ -w "$tmp_dir" ]; then
      download_dir="$tmp_dir"
      break
    fi
  done

  local download_dir_msg
  if [ -z "$download_dir" ]; then
    download_dir_msg="unable to find a writable temp directory: "
    download_dir="$HOME"
  fi

  download_dir_msg+="release archive will be downloaded to ${bold}$download_dir${bold_reset}"
  echo -e "\n$download_dir_msg"

  local is_download_url_fallback=false

  for download_url in "${download_urls[@]}"; do
    for bzr2_zip_filename in "${bzr2_zip_filenames[@]}"; do
      if [ $is_download_url_fallback = true ]; then
        local query_string="$bzr2_zip_filename"
      else
        local query_string="$bzr2_version"
      fi

      echo -en "\ndownloading ${bold}$bzr2_zip_filename${bold_reset} from $download_url$query_string... "

      set +e
      wget -q --tries=$download_tries -P "$download_dir" -O "$download_dir/$bzr2_zip_filename" \
        "$download_url$query_string"

      local wget_result=$?
      set -e

      bzr2_zip="$download_dir/$bzr2_zip_filename"

      if [ $wget_result -eq 0 ] && unzip -tq "$bzr2_zip" >/dev/null 2>&1; then
        set +e
        bzr2_zip_sanity_check "$bzr2_zip"
        local is_zip_sane=$?
        set -e

        if [ $is_zip_sane -eq 0 ]; then
          is_zip_downloaded=true
          return
        fi
      else
        echo -n "FAIL"
      fi
    done

    is_download_url_fallback=true
  done

  echo -e "\n\nunable to download the release archive"
  is_zip_downloaded=false
  return
}

get_bzr2_local_zip_dir() {
  while :; do
    local bzr2_zip_dir
    bzr2_zip_dir=$(show_message_and_read_input "specify the release archive folder path" \
      "$(realpath -s "$bzr2_zip_dir_default")")

    local bzr2_zips=()
    for bzr2_zip_filename in "${bzr2_zip_filenames[@]}"; do
      bzr2_zips+=("$bzr2_zip_dir/$bzr2_zip_filename")
    done

    for i in "${!bzr2_zips[@]}"; do
      if [ -f "${bzr2_zips[i]}" ]; then
        echo -en "\nrelease archive ${bold}${bzr2_zips[i]}${bold_reset} for version \
${bold}$bzr2_version${bold_reset} found... "

        set +e
        bzr2_zip_sanity_check "${bzr2_zips[i]}"
        local is_zip_sane=$?
        set -e

        if [ "$is_zip_sane" -eq 0 ]; then
          bzr2_zip="${bzr2_zips[i]}"
          break 2
        fi
      fi
    done

    if [ ${#bzr2_zips[@]} -gt 1 ]; then
      echo -e "\nnone of these files are found or valid:"

      for bzr2_zip in "${bzr2_zips[@]}"; do
        echo "${bold}${bzr2_zip}${bold_reset}"
      done

      echo -e "$invalid_value_inserted_message"
    else
      echo -e "\nvalid ${bold}${bzr2_zips[0]}${bold_reset} file not found... $invalid_value_inserted_message"
    fi

  done
}

get_dpi() {
  local dpi_pattern="^[1-9][0-9]*$"

  while :; do
    local input
    input=$(show_message_and_read_input "select the DPI, ${bold}auto${bold_reset} for using the current from xorg \
screen 0 or ${bold}default${bold_reset} for using the default one" ${dpi_default})

    case $input in
    default | auto)
      break
      ;;
    *)
      if ! [[ "$input" =~ $dpi_pattern ]]; then
        echo -e "\n$invalid_value_inserted_message"
      else
        break
      fi
      ;;
    esac
  done

  dpi="$input"
}

get_size_of_longer_array_entry() {
  local array=("$@")
  local longer_size=-1

  for entry in "${array[@]}"; do
    local length=${#entry}
    ((length > longer_size)) && longer_size=$length
  done

  echo "$longer_size"
}

get_mime_types_association() {
  while :; do
    local input
    input=$(show_message_and_read_input "associate to all suppported MIME types (enter ${bold}list${bold_reset} \
for listing all)" ${mime_types_association_default})

    case $input in
    y | n)
      break
      ;;

    list)
      local mime_length_max
      mime_length_max=$(get_size_of_longer_array_entry "${mime_types_supported[@]}")
      local mime_comments=()
      local mime_patterns=()
      local bzr2_xml_content
      bzr2_xml_content=$(cat "$bzr2_xml_filename")

      for mime_type in "${mime_types_supported[@]}"; do
        local sed_pattern="\|<mime-type type=\"$mime_type\">| , \|</mime-type>|{p; \|</mime-type>|q}"
        local mime_single
        mime_single=$(echo "$bzr2_xml_content" | sed -n "$sed_pattern")

        if [ -z "$mime_single" ]; then
          mime_single=$(sed -n "$sed_pattern" "/usr/share/mime/packages/freedesktop.org.xml")
        fi

        mime_comments+=("$(echo "$mime_single" | grep "<comment>" | sed 's:<comment>::;s:</comment>::;s:    ::')")
        local mime_pattern
        mime_pattern=$(echo "$mime_single" | grep "<glob pattern=" | sed -e 's:<glob pattern="::g' -e 's:"/>::g')
        local mime_pattern_split=()

        while read -r line; do
          mime_pattern_split+=("$line")
        done <<<"$mime_pattern"

        local mime_comment_length_max
        mime_comment_length_max=$(get_size_of_longer_array_entry "${mime_comments[@]}")
        local delimiter="  "
        local padding_size=$((mime_length_max + mime_comment_length_max + ${#delimiter} + ${#delimiter}))
        local padding_string=""

        for ((i = 0; i < "$padding_size"; i++)); do
          padding_string+=" "
        done

        local max_patterns_per_chunk=4
        local mime_pattern_chunks=()

        for ((i = 0; i < ${#mime_pattern_split[@]}; i++)); do
          local div=$((i / max_patterns_per_chunk))
          if [ $div -gt 0 ] && [ $((i % max_patterns_per_chunk)) -eq 0 ]; then
            mime_pattern_chunks[div]=${mime_pattern_chunks[div]}$padding_string"["${mime_pattern_split[$i]}]
          else
            if [ "$i" -eq 0 ]; then
              mime_pattern_chunks[div]="${mime_pattern_chunks[div]}[${mime_pattern_split[$i]}]"
            else
              mime_pattern_chunks[div]="${mime_pattern_chunks[div]}[${mime_pattern_split[$i]}]"
            fi
          fi
        done

        mime_pattern=""

        for ((i = 0; i < ${#mime_pattern_chunks[@]}; i++)); do
          mime_pattern="$mime_pattern${mime_pattern_chunks[$i]}"$'\n'
        done

        mime_pattern=$(sed -z 's/.$//' <<<"$mime_pattern")
        mime_patterns+=("$mime_pattern")
      done

      echo -e "\nBZR2 supports following MIME types:\n"

      for i in "${!mime_types_supported[@]}"; do
        printf "%${mime_length_max}s$delimiter%${mime_comment_length_max}s$delimiter%s\n" "${mime_types_supported[$i]}" \
          "${mime_comments[$i]}" "${mime_patterns[$i]}"
      done
      ;;
    *)
      echo -e "\n$invalid_value_inserted_message"
      ;;
    esac
  done

  mime_types_association="$input"
}

setup_bzr2() {
  sudo -u "$USER" mkdir -p "$bzr2_dir"
  sudo -u "$USER" unzip -oq "$bzr2_zip" -d "$bzr2_dir"

  # disable wine crash dialog (winetricks nocrashdialog)
  sudo -u "$USER" WINEDEBUG=-all WINEPREFIX="$bzr2_wineprefix_dir" WINEARCH="$winearch" WINEDLLOVERRIDES="mscoree=" \
    wine reg add "HKEY_CURRENT_USER\Software\Wine\WineDbg" /v ShowCrashDialog /t REG_DWORD /d 0 /f

  # disable wine debugger (winetricks autostart_winedbg=disabled)
  sudo -u "$USER" WINEDEBUG=-all WINEPREFIX="$bzr2_wineprefix_dir" WINEARCH="$winearch" WINEDLLOVERRIDES="mscoree=" \
    wine reg add "HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\AeDebug" \
    /v Debugger /t REG_SZ /d "false" /f
}

setup_dpi() {
  local dpi_to_set

  case "$dpi" in
  default)
    dpi_to_set=96
    ;;

  auto)
    dpi_to_set=$(sudo -u "$USER" xrdb -query | grep dpi | sed 's/.*://;s/^[[:space:]]*//')
    if [ -z "$dpi_to_set" ]; then
      echo -e "\nunable to retrieve the screen ${bold}DPI${bold_reset}: the ${bold}default${bold_reset} will be used \
in wine"
      return
    fi
    ;;

  *)
    dpi_to_set=$dpi
    ;;
  esac

  echo -e "\nsetting wine ${bold}DPI${bold_reset} to ${bold}$dpi_to_set${bold_reset}\n"

  dpi_to_set='0x'$(printf '%x\n' "$dpi_to_set")

  sudo -u "$USER" WINEDEBUG=-all WINEPREFIX="$bzr2_wineprefix_dir" WINEARCH="$winearch" WINEDLLOVERRIDES="mscoree=" \
    wine reg add "HKEY_CURRENT_USER\Control Panel\Desktop" /v LogPixels /t REG_DWORD /d "$dpi_to_set" /f

  sudo -u "$USER" WINEDEBUG=-all WINEPREFIX="$bzr2_wineprefix_dir" WINEARCH="$winearch" WINEDLLOVERRIDES="mscoree=" \
    wine reg add "HKEY_CURRENT_USER\Software\Wine\Fonts" /v LogPixels /t REG_DWORD /d "$dpi_to_set" /f

  sudo -u "$USER" WINEDEBUG=-all WINEPREFIX="$bzr2_wineprefix_dir" WINEARCH="$winearch" WINEDLLOVERRIDES="mscoree=" \
    wine reg add "HKEY_CURRENT_CONFIG\Software\Fonts" /v LogPixels /t REG_DWORD /d "$dpi_to_set" /f
}

setup_launcher_script() {

  bzr2_launcher_content=$(
    cat <<EOF
#!/bin/bash
#
# NAME
#     bzr-player.sh - BZR Player 2.x (BZR2) launcher
#
# SYNOPSIS
#     ./bzr-player.sh [target(s)]
#
# EXAMPLES
#     ./bzr-player.sh
#         run BZR2
#
#     ./bzr-player.sh file1 file2 dir1 dir2
#         run BZR2 with selected files and/or directories as arguments
#
# AUTHOR
#     Ciro Scognamiglio

set -e

export WINEDEBUG=warn
export WINEPREFIX="$bzr2_wineprefix_dir"
export WINEARCH="$winearch"
export WINEDLLOVERRIDES="mscoree=" # disable mono

wine "$bzr2_exe"
EOF
  )

  bzr2_launcher_content=$(echo "$bzr2_launcher_content" | sed '$s/$/ "$@" \&/')
  sudo -u "$USER" bash -c "echo '$bzr2_launcher_content' > '$bzr2_launcher'"
  sudo -u "$USER" chmod +x "$bzr2_launcher"
}

setup_icon() {
  if [ -f "$bzr2_icon" ]; then
    echo -e "\ninstalling ${bold}icons${bold_reset}"

    for size in "${icon_sizes[@]}"; do
      xdg-icon-resource install --noupdate --novendor --context apps --mode system --size "${size}" "$bzr2_icon" "$bzr2_pkgname"
    done

    xdg-icon-resource forceupdate --theme hicolor

    if type gtk-update-icon-cache &>/dev/null; then
      echo
      gtk-update-icon-cache -t -f "$icons_hicolor_path"
    fi
  else
    echo -e "\nskipping ${bold}icons${bold_reset} installation"
  fi
}

setup_desktop_entry() {
  echo -e "\ninstalling ${bold}desktop menu entry${bold_reset}"
  local desktop_entry_mime_types=""

  for mime_type in "${mime_types_supported[@]}"; do
    desktop_entry_mime_types="$desktop_entry_mime_types$mime_type;"
  done

  bzr2_desktop_content=$(
    cat <<EOF
[Desktop Entry]
Type=Application
Name=$bzr2_name
GenericName=Audio player
Comment=Audio player supporting a wide types of multi-platform exotic file formats
Exec=$bzr2_launcher %U
Icon=$bzr2_pkgname
Terminal=false
StartupNotify=false
Categories=AudioVideo;Audio;Player;Music;
MimeType=$desktop_entry_mime_types
NoDisplay=false

EOF
  )

  sudo -u "$USER" bash -c "echo '$bzr2_desktop_content' > '$bzr2_desktop'"
  xdg-desktop-menu install --novendor --mode system "$bzr2_desktop"
}

setup_mime_types() {
  echo -e "\nassociating to all supported ${bold}MIME types${bold_reset}"

  install -Dm644 "$bzr2_xml" "$mime_packages_dir_system"
  sudo -u "$USER" xdg-mime default $bzr2_desktop_filename "${mime_types_supported[@]}"
  update-mime-database "$mime_dir_system"
  update-desktop-database "$desktop_apps_dir_system"
}

remove() {
  local nothing_to_remove=true

  if [ -d "$bzr2_wineprefix_dir_unversioned" ]; then
    local targets=()
    mapfile -t targets \
      < <(sudo -u "$USER" find "$bzr2_wineprefix_dir_unversioned" -maxdepth 1 -path "$bzr2_wineprefix_dir_unversioned*" -type d -print | sort -V)

    for target in "${targets[@]}"; do
      if [ -d "$target" ]; then
        while :; do
          local input
          input=$(show_message_and_read_input "remove ${bold}$target${bold_reset} ?" "y")

          case $input in
          y)
            nothing_to_remove=false
            sudo -u "$USER" rm -rf "$target"
            break
            ;;
          n)
            break
            ;;
          *)
            echo -e "\n$invalid_value_inserted_message"
            ;;
          esac
        done
      fi
    done
  fi

  while :; do
    local input
    input=$(show_message_and_read_input "remove ${bold}desktop menu entry${bold_reset} ?" "y")

    case $input in
    y)
      nothing_to_remove=false
      xdg-desktop-menu uninstall --mode system "$bzr2_desktop_filename"
      break
      ;;
    n)
      break
      ;;
    *)
      echo -e "\n$invalid_value_inserted_message"
      ;;
    esac
  done

  while :; do
    local input
    input=$(show_message_and_read_input "remove ${bold}icons${bold_reset} ?" "y")

    case $input in
    y)
      nothing_to_remove=false
      for size in "${icon_sizes[@]}"; do
        xdg-icon-resource uninstall --noupdate --context apps --mode system --size "${size}" "$bzr2_pkgname"
      done

      xdg-icon-resource forceupdate --theme hicolor

      if type gtk-update-icon-cache &>/dev/null; then
        echo
        gtk-update-icon-cache -t -f "$icons_hicolor_path"
      fi

      break
      ;;
    n)
      break
      ;;
    *)
      echo -e "\n$invalid_value_inserted_message"
      ;;
    esac
  done

  while :; do
    local input
    input=$(show_message_and_read_input "remove associtated ${bold}MIME types${bold_reset} ?" "y")

    case $input in
    y)
      nothing_to_remove=false
      rm -f "$mime_packages_dir_system/$bzr2_xml_filename"
      update-mime-database "$mime_dir_system"
      update-desktop-database "$desktop_apps_dir_system"
      break
      ;;
    n)
      break
      ;;
    *)
      echo -e "\n$invalid_value_inserted_message"
      ;;
    esac
  done

  if [ "$nothing_to_remove" == true ]; then
    echo -e "\nnothing to remove"
  else
    echo -e "\nAll done"
  fi
}

main "$@" exit
