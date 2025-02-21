#!/bin/bash

### restore-it-kup.sh <file-to-restore-from-backup>
### get-it-back-kup.sh <file-to-restore-from-backup>

### TODO
### https://store.kde.org/p/1127689 says: kup can backup to remote storages as well.  Check this out!
### https://store.kde.org/p/1127689 says: kup can backup incrementaly (keeping older versions) or keep source and target directory in sync (i.e. not keeping older versions). Do we have to take care on this?

### where kup stores its config (via kde plasma system settings)
# kuprc_file_path="${2:-$HOME/.config/kuprc}"
kuprc_file_path="$HOME/.config/kuprc"
options="$( getopt -o c: --long config: --name "$0" -- "$@" )"
eval set -- "${options}"
while true; do
	case "$1" in
		-c | --config )
			kuprc_file_path="$1"
			shift 2
		;;
		--)
            shift
            break
		;;
		*)
            echo "unknown option: $1" >&2
            exit 1
        ;;
    esac
done

### no file to retore, TODO: just quit or usage
file_to_restore_path="${1:-/nodir}"

### get kreadconfig command installed
kreadconfig_commands_array=( $(type -p kreadconfig6 kreadconfig5 kreadconfig) )
kreadconfig_command="${kreadconfig_commands_array[0]}"

# function get_key_from_config_dumb_version ()
# {
# 	kuprc_key="${1}"
# 	kuprc_file="${2:$kuprc_file_path}"
# 	grep -i "$kuprc_key" "$kuprc_file" | cut -d '=' -f 2
# }

### get a value by key from config file
function get_key_from_config ()
{
	kuprc_group="${1}"
	kuprc_key="${2}"
	kuprc_file="${3:-$kuprc_file_path}"
	$kreadconfig_command --file "$kuprc_file" --group "$kuprc_group" --key "$kuprc_key"
}

### check if we there (with bup?)
# WARNING: bup might be able to create more than one "name" in the same backup storage path. can kup this too?
function is_kup_repository ()
{
	repository_path="$1"
	is_kup_repository=$(bup --bup-dir="$repository_path" ls 2>/dev/null)
	# for clarity of code we return explicitly here
	[[ "$is_kup_repository" == 'kup' ]] && return 0
 	return 1
}

### check if file to restore is any of the backups plans
### it is in a plan, when its path starts with any element in $path_incluced_array
function file_is_in_path_included ()
{
	path_file="$1"
	path_included="$2"
	# file is included, if  its full path starts with path_included
	# (or we can succesfully reduce files full path by path included)
	# is a single file allowed as path included?
	path_relativ=${path_file#$path_included}
	# if this reduction was succesfull, path included and relativ path are equal to file path
	[[ "${path_included}${path_relativ}" == "${path_file}" ]] && return 0
 	return 1
}

# function get_plan_count ()
# {
# 	# we loop over an index (starting with 1) until we have no match or ...
# 	# we just grep over the key 'Paths included', get just the values and count elements
# 	kuprc_file="${1:-$kuprc_file_path}"
# 	kuprc_key='Paths included'
# 	path_incluced_array=( $(grep -i "$kuprc_key" "$kuprc_file" | cut -d '=' -f 2) )
# 	# return count
# 	echo "${#path_incluced_array[@]}"
# }

function get_external_drive_mount_path ()
{
	external_volume_label="$1"
	echo "$(mount | grep "$external_volume_label" | cut -f 3 -d ' ')"
}

function get_path_incluced_array_DRAFT ()
{
	kuprc_file="${1:-$kuprc_file_path}"
	echo -n 'DEBUG: backup pathes included: ( ' >&2; echo -n $(grep -i 'Paths included' "$kuprc_file" | cut -d '=' -f 2 | sed 's/^/"/' | sed 's/$/"/') >&2; echo ' )' >&2
	grep -i 'Paths included' "$kuprc_file" | cut -d '=' -f 2 | sed 's/^/"/' | sed 's/$/"/'
}

### get pathes that are backed up in kup plans
# TODO: use a function (as we do for getting values by keys) or use the redundant kuprc_file def ?
# NOTE: any ancluded backup path might be included more than once !
# kuprc_file="${1:-$kuprc_file_path}"
# path_incluced_array=( $(grep -i 'Paths included' "$kuprc_file" | cut -d '=' -f 2) )
path_incluced_array=( $(get_path_incluced_array_DRAFT) )

### loop over kup plans
kup_plan_count=${#path_incluced_array[@]}
# TODO: add even more error resistance
for (( i = 0 ; i < $kup_plan_count ; i++ )); do
	path_incluced="${path_incluced_array[$i]}"
	plan_num=$(( i+1 ))
	echo plan: "Plan/$plan_num"
	echo "plan path included: $path_incluced" >&2
	filesystem_destination_path="$(get_key_from_config "Plan/$plan_num" 'Filesystem destination path')"
	external_volume_label=$(get_key_from_config "Plan/$plan_num" "External volume label")
	external_drive_destination_path=$(get_key_from_config "Plan/$plan_num" "External drive destination path")
	### use volume label stuff only if we have no (internal/local) filesystem destination path
	if [[ "$filesystem_destination_path"  =~ 'file://' ]]; then
		repository_path=${filesystem_destination_path#'file://'}
		is_kup_repository "$repository_path" && echo "valid (local) path: $repository_path" >&2 || echo "NO valid (local) path: $repository_path" >&2
	else
		external_drive_mount_path="$(get_external_drive_mount_path "$external_volume_label")"	# hidden or
		external_drive_mount_path="$(mount | grep "$external_volume_label" | cut -f 3 -d ' ')"	# visible?
		if [[ -z "$external_drive_mount_path" ]]; then
			echo "external volume label is defined, but volume not mounted: '$external_volume_label'" >&2
		else
			repository_path="$external_drive_mount_path/$external_drive_destination_path"
			is_kup_repository "$repository_path" && echo "valid (external) path: $repository_path" >&2 || echo "NO valid (external) path: $repository_path" >&2

			# try to get file back ...
			# with bup(1) or kioclient(1)? (bup:///media/christian/MyBook/BACKUPS/Auto/Kup/solo/Entwicklung/)

		fi
	fi
done

exit 0


# sample saving operation
/usr/bin/bup \
	--bup-dir=/media/christian/MyBook/BACKUPS/Auto/Kup/solo/Misc \
	index \
	--update \
	--exclude /home/christian/.local/share/Trash \
	--exclude /home/christian/.local/share/baloo \
		/home/christian/.local \
		/home/christian/Entwicklung/KDE/Dolphin/Service Menus/Get my D-Bus ID/get-my-dbus-id \
		/home/christian/Entwicklung/KDE/Dolphin/Service Menus/Preview lt/preview-it \
		/home/christian/Entwicklung/KDE/Dolphin/Service Menus/Refresh (F5)/refresh-view-f5-dbus \
		/home/christian/Entwicklung/KDE/Dolphin/Service Menus/Remove Extension/remove-ext/remove-ext \
		/home/christian/Entwicklung/KDE/Dolphin/Service Menus/Run It/run-it/run-it \
		/home/christian/Entwicklung/KDE/Dolphin/Service Menus/Select All/select-all-dbus \
		/home/christian/Entwicklung/KDE/Dolphin/Service Menus/Select It/toggle-selection-mode-shift-dbus \
		/home/christian/Entwicklung/KDE/Dolphin/Service Menus/Terminal (F4)/terminal-panel-f4-dbus \
		/home/christian/Entwicklung/KDE/Dolphin/Service Menus/Undo lt/undo-it \
		/home/christian/Entwicklung/Trash It \
		/home/christian/Entwicklung/Virtualization/VMMCON/src/bin \
		/home/christian/Entwicklung/Virtualization/VMMCON/src/share/vmmcon
