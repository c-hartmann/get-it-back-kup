#!/bin/bash

### get-it-back-kup.sh <file-to-restore-from-backup>
### restore-it-kup.sh <file-to-restore-from-backup>

# TODO
# handle multiple files to restore
# https://store.kde.org/p/1127689 says: kup can backup to remote storages as well.  Check this out!
# https://store.kde.org/p/1127689 says: kup can backup incrementaly (keeping older versions) or keep source and target directory in sync (i.e. not keeping older versions). Do we have to take care on this?
# setup a remote backup repository and build code for this case as well (NOTE: bup can do this, but kup as well?)

function usage ()
{
	echo "usage: $(basename $0) [ opions ] <file-to-restore-full-path>" >&2
}

### where kup stores its config (via kde plasma system settings)
kuprc_file_path="$HOME/.config/kuprc"

### bup restores to current directory by default
out_dir='.'

### evaluate options given (out dir option names taken from bup)
options="$( getopt --alternative --options C:c:k: --longoptions outdir:,config:,kuprc: --name "$0" -- "$@" )"
eval set -- "${options}"
while true; do
	case "$1" in
		-k | --kuprc | -c | --config )
			kuprc_file_path="$2"
			shift 2
		;;
		-C | --outdir )
			option_out_dir="$2"
			shift 2
		;;
		--)
            shift
            break
		;;
		*)
            echo "Unknown option: $1" >&2
            usage
            exit 2
        ;;
    esac
done

### no file to retore, just quit with usage
file_to_restore_path="${1:-/nopath}"
[[ "$file_to_restore_path" == '/nopath' ]] && usage && exit 2

### get kreadconfig command installed here
kreadconfig_commands_array=( $(type -p kreadconfig6 kreadconfig5 kreadconfig) )
kreadconfig_command="${kreadconfig_commands_array[0]}"

### get a value by key from config file
function get_key_from_config ()
{
	kuprc_group="${1}"
	kuprc_key="${2}"
	$kreadconfig_command --file "$kuprc_file_path" --group "$kuprc_group" --key "$kuprc_key"
}

### check if we there (with bup?)
# WARNING: bup might be able to create more than one "name" in the same backup storage path. can kup this too?
function is_kup_repository ()
{
	repository_path="$1"
	is_kup_repository=$(bup --bup-dir="$repository_path" ls 2>/dev/null)
	# for sake of clarity of code we return explicitly here
	[[ "$is_kup_repository" == 'kup' ]] && return 0
 	return 1
}

### check if file to restore is any of the backups plans
### it is in a plan, when its path starts with any element in $path_incluced_array
# function file_is_in_path_included ()
# {
# 	path_file="$1"
# 	path_included="$2"
# 	# file is included, if  its full path starts with path_included
# 	# (or we can succesfully reduce files full path by path included)
# 	# is a single file allowed as path included?
# 	path_relativ=${path_file#$path_included}
# 	# if this reduction was succesfull, path included and relativ path are equal to file path
# 	[[ "${path_included}${path_relativ}" == "${path_file}" ]] && return 0
#  	return 1
# }

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

### get pathes that are backed up in kup plans
# TODO: use a function (as we do for getting values by keys) or use the redundant kuprc_file def ?
# NOTE: any ancluded backup path might be included more than once !
# kuprc_file="${1:-$kuprc_file_path}"
# path_incluced_array=( $(grep -i 'Paths included' "$kuprc_file" | cut -d '=' -f 2) )
# path_incluced_array=( $(get_path_incluced_array_DRAFT) )

### loop over kup plans
# kup_plan_count=${#path_incluced_array[@]}
kup_plan_count=$(grep 'Paths included=' "$kuprc_file_path" | wc -l)

### loop over files given
for file_to_restore_path in "${@}"; do

### we restore to original directory by default (if not given as option)
[[ "$option_out_dir" == '.' ]] && out_dir="$(dirname "$file_to_restore_path")" || out_dir="$option_out_dir"

# TODO: add even more error resistance
for (( i = 0 ; i < $kup_plan_count ; i++ )); do
	echo >&2 # just some visual separation
	plan_num=$(( i+1 ))
	echo "plan group: [Plan/$plan_num]" >&2
	path_incluced="$(get_key_from_config "Plan/$plan_num" 'Paths included')"

	### get some values from plan, that might be required later
	filesystem_destination_path="$(get_key_from_config "Plan/$plan_num" 'Filesystem destination path')"
	external_volume_label=$(get_key_from_config "Plan/$plan_num" "External volume label")
	external_drive_destination_path=$(get_key_from_config "Plan/$plan_num" "External drive destination path")

	### use volume label stuff only if we have no (internal/local) filesystem destination path
	if [[ "$filesystem_destination_path"  =~ 'file://' ]]; then
		repository_path=${filesystem_destination_path#'file://'}
		is_kup_repository "$repository_path" && echo "valid local path: $repository_path" >&2 || echo "no valid local path: $repository_path" >&2
	else
		external_drive_mount_path="$(get_external_drive_mount_path "$external_volume_label")"	# hidden or
		external_drive_mount_path="$(mount | grep "$external_volume_label" | cut -f 3 -d ' ')"	# visible?
		if [[ -z "$external_drive_mount_path" ]]; then
			echo "external volume label is defined, but volume not mounted: '$external_volume_label'" >&2
		else
			repository_path="$external_drive_mount_path/$external_drive_destination_path"
			is_kup_repository "$repository_path" && echo "valid external path: $repository_path" >&2 || echo "no valid external path: $repository_path" >&2

			# try to get file back ...
			# with 'kioclient ls' with this url: bup:///media/christian/MyBook/BACKUPS/Auto/Kup/solo/Entwicklung/ ?
			# ERROR:  kf.kio.core: UDSEntry for '.' not found, creating a default one. Please fix the "kioworker" KIO worker.
			# BUT: it returns 'kup', which is correct
			bup_dir="$repository_path"

			base_path_latest="kup/latest"

			# get other pathes
			kioclient_url="bup://$repository_path/"
			echo "kioclient url: $kioclient_url" >&2
			### commands pre last line is mysterious single '.' and last line is an empty one. we remove that
			kup="$(kioclient ls "$kioclient_url" 2>/dev/null | head --lines=-2)"
 			echo "snapshots: ..." >&2
 			kioclient ls "$kioclient_url/$kup" 2>/dev/null | head --lines=-2 >&2
			snapshots=( $(kioclient ls "$kioclient_url/$kup" 2>/dev/null | head --lines=-2) )

			# do we have the file?
			search_in_backup_path="$base_path_latest/$file_to_restore_path"

			# TODO: test on entire directories
			# TODO: is there a do-not-override option with bup?
			echo "looking for: $search_in_backup_path …" >&2
 			found="$(bup --bup-dir="$bup_dir" ls "$search_in_backup_path" 2>/dev/null)"
 			if [[ $? = 0 ]]; then
				echo "found: $found" >&2
				echo "restoring to: $out_dir" >&2
 				echo "running command: bup --bup-dir="$bup_dir" restore --outdir="$out_dir" -v -v "$search_in_backup_path"" >&2
				bup --bup-dir="$bup_dir" restore --outdir="$out_dir" -v -v "$search_in_backup_path"
				continue 2 # with next file to restore
			else
				echo "not found" >&2
 			fi
		fi
	fi
done

done

exit 0
