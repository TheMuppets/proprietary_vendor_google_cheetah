#!/vendor/bin/sh

###################################################################
### init.insmod.cfg format:                                     ###
### ----------------------------------------------------------- ###
### [insmod|setprop|enable|moprobe|rmmod|wait] [path|prop name] ###
### ...                                                         ###
###################################################################

modules_dir=
system_modules_dir=
vendor_modules_dir=

# This directory ONLY contains the 16k modules loaded in 16k mode
# during the Second Boot Stage. This directory is not present in the
# <device>_16k targets.
mode_16k_modules_dir=/vendor/lib/modules/16k-mode
pagesize=$(getconf PAGE_SIZE)

for dir in system vendor; do
  for f in /${dir}/lib/modules/*/modules.dep /${dir}/lib/modules/modules.dep; do
    if [[ -f "$f" ]]; then
      if [[ "${dir}" == "system" ]]; then
        system_modules_dir="$(dirname "$f")"
      else
        vendor_modules_dir="$(dirname "$f")"
        modules_dir=${vendor_modules_dir}
      fi
      break
    fi
  done
done

if [[ -z "${system_modules_dir}" ]]; then
  echo "Unable to locate system kernel modules directory" 2>&1
fi

if [[ -z "${vendor_modules_dir}" ]]; then
  echo "Unable to locate vendor kernel modules directory" 2>&1
  exit 1
fi

# imitates wait_for_file() in init
wait_for_file()
{
    filename="${1}"
    timeout="${2:-5}"

    expiry=$(($(date "+%s")+timeout))
    while [[ ! -e "${filename}" ]] && [[ "$(date "+%s")" -le "${expiry}" ]]
    do
        sleep 0.01
    done
}

if [ $# -eq 1 ]; then
  cfg_file=$1
else
  # Set property even if there is no insmod config
  # to unblock early-boot trigger
  setprop vendor.common.modules.ready 1
  setprop vendor.device.modules.ready 1
  setprop vendor.all.modules.ready 1
  setprop vendor.all.devices.ready 1
  exit 1
fi

if [ -f $cfg_file ]; then
  while IFS="|" read -r action arg
  do
    case $action in
      "insmod") insmod $arg ;;
      "setprop") setprop $arg 1 ;;
      "enable") echo 1 > $arg ;;
      "condinsmod")
        prop=$(echo $arg | cut -d '|' -f 1)
        module1=$(echo $arg | cut -d '|' -f 2)
        module2=$(echo $arg | cut -d '|' -f 3)
        value=$(getprop $prop)
        if [[ ${value} == "true" ]]; then
          insmod ${vendor_modules_dir}/${module1}
        else
          insmod ${vendor_modules_dir}/${module2}
        fi
        ;;
      "modprobe")
        case ${arg} in
          "system -b *" | "system -b")
            modules_dir=${system_modules_dir}
            arg="-b --all=${system_modules_dir}/modules.load" ;;
          "system *" | "system")
            modules_dir=${system_modules_dir}
            arg="--all=${system_modules_dir}/modules.load" ;;
          "-b *" | "-b" | "vendor -b *" | "vendor -b")
            modules_dir=${vendor_modules_dir}
            arg="-b --all=${vendor_modules_dir}/modules.load" ;;
          "*" | "" | "vendor *" | "vendor")
            modules_dir=${vendor_modules_dir}
            arg="--all=${vendor_modules_dir}/modules.load" ;;
        esac
        if [[ "${pagesize}" == "16384" && -d "${mode_16k_modules_dir}" ]]; then
          insmod ${mode_16k_modules_dir}/$arg
        elif [[ -d "${modules_dir}" ]]; then
          modprobe -a -d "${modules_dir}" $arg
        fi
        ;;
      "rmmod") rmmod $arg ;;
      "wait") wait_for_file $arg ;;
    esac
  done < $cfg_file
fi
