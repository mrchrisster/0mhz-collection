#!/bin/bash

# Script to download DOS games and stay up to date with the 0mhz project
# Checks Github for new mgl files and then checks archive to download those zip files.
# Please visit https://0mhz.net/ for more info

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# Copyright 2024 mrchrisster


# NOTE: If this is the first time you install ao486, make sure you run update_all to install all necessary files for the core

# NOTE: 
# Save games are stored in the vhd. No save games will be deleted by this program
# If a game gets updated you have a save for, the new vhd will have a different name than the old version (e.g. "Game Name.r2.vhd")
# If you played a game and have a save and a new version is out, you would have to manually edit the mgl to point to the old vhd or transfer your save to the new version



# Where should the games be installed? Change accordingly if you want games to be stored on usb or cifs
games_loc="/media/fat"

# Path for mgl files. Should be on /media/fat drive.
dos_mgl="/media/fat/_DOS Games"

# Prefer mt32 files. This will download all mgl files but if a MT-32 version exist, it will use that version.
prefer_mt32=false

# Always download fresh copies of mgls to assure we stay up to date
always_dl_mgl=false

# Deletes mgls that are not associated with files on archive. Set to false to disable automatic deletion
unresolved_mgls=true




###### CODE STARTS HERE

base_dir="${games_loc}/games/AO486"

# archive.org URL of the 0mhz XML file
xml_url="https://archive.org/download/0mhz-dos/0mhz-dos_files.xml"

# github 0mhz url
temp_dir="/tmp/0mhz-collection"
repo_zip_url="https://github.com/0mhz-net/0mhz-collection/archive/refs/heads/main.zip"
repo_zip_path="/tmp/0mhz-collection.zip"
mgls_dir_name="0mhz-collection-main/mgls"
gh_mgl_dir="$temp_dir/$mgls_dir_name"



#### PREP

prep() {
	# Ensure the local directory exists
	mkdir -p "$dos_mgl"
	mkdir -p "$base_dir"/media
	
	# Delete extracted zip if it exists
	rm -rf /tmp/0mhz-collection
	
	# Empty out the mgl_dir if always_dl_mgl is true
	if [ "$always_dl_mgl" = true ]; then
		echo "Clearing out $dos_mgl..."
		rm -f "$dos_mgl"/*.mgl
	fi
	
	# Check available space on the device where base_dir is located
	available_space_gb=$(df -BG "$base_dir" | awk 'NR==2 {print substr($4, 1, length($4)-1)}')
	
	if [ "$available_space_gb" -lt 30 ]; then
		echo "Less than 30GB space available in $base_dir. Aborting."
		exit 1
	fi
}

#### MGL GH DOWNLOAD


download_mgl_gh() {
	
	# Download and unzip the repository
	download_and_unzip_repo() {
		echo "Downloading repository..."
		curl -s --insecure -L -o "$repo_zip_path" "$repo_zip_url"
		echo "Unzipping repository to $temp_dir..."
		mkdir -p "$temp_dir"
		unzip -qq -o "$repo_zip_path" -d "$temp_dir"
	}
	
	# Function to prefer MT-32 files
	prefer_mt32_files() {
		echo ""
		echo "Preferring MT-32 files"
		echo ""
	
		find "$gh_mgl_dir"  -maxdepth 1 -type f -name "*.mgl" | sort | while read standard_file; do
			# Determine MT-32 counterpart
			mt32_file="${standard_file%.*} (MT-32).mgl"
			mt32_file="${mt32_file/$gh_mgl_dir/$gh_mgl_dir/_MT-32}"
	
			if [[ -f "$mt32_file" ]]; then
				# If MT-32 counterpart exists, prefer it by deleting the standard file and moving it in place (tmp dir)
				rm -f "$standard_file"
				cp "$mt32_file" "$gh_mgl_dir"
			fi
		done
	}

	download_and_unzip_repo
	
	if [ "$prefer_mt32" = true ]; then
		prefer_mt32_files
	fi
	
	echo "Download of Github MGL Archive complete."
	echo ""
}

#### MGL COMPARE REMOTE TO LOCAL

mgl_updater() {
	# Store all local and remote mgls in arrays for later use
	shopt -s nullglob
	gh_mgl_files=("$gh_mgl_dir"/*.mgl)
	dos_mgl_files=("$dos_mgl"/*.mgl)
	shopt -u nullglob


    if [ ${#gh_mgl_files[@]} -eq 0 ]; then
        echo "No .mgl files found in GitHub directory. Skipping update check."
        return
    elif [ ${#dos_mgl_files[@]} -eq 0 ]; then
        echo "Rebuilding mgl directory..."
        for gh_mgl_file in "${gh_mgl_files[@]}"; do
			echo "Copying: $(basename "$gh_mgl_file") ... "
            cp -f "$gh_mgl_file" "$dos_mgl"
        done
        return
    fi
	
    echo "Comparing local and remote .mgl files..."
    for gh_mgl_file in "${gh_mgl_files[@]}"; do
        
		local_mgl_path="$dos_mgl/$(basename "$gh_mgl_file")"
        
		# Conditions to update
        if [[ ! -f "$local_mgl_path" ]] || ! cmp -s "$gh_mgl_file" "$local_mgl_path"; then
            echo "Copying: $(basename "$gh_mgl_file") ... "
            cp -f "$gh_mgl_file" "$dos_mgl/" 
		fi
    done
	echo "Comparison finished."
	echo ""
}



#### MGL FILES CHECK

mgl_files_check() {
	echo "Checking if local files exist"
	
	# Initialize an array to hold all paths mentioned in mgl
	referenced_paths=()
	
	# Initialize an array to hold the names of .mgl files with missing paths/files
	mgl_with_missing_paths=()
	
	
	# Loop through all .mgl files in the mgl_dir
	for mgl_file in "$dos_mgl"/*.mgl; do
	
		paths=$(grep -o 'path="[^"]*"' "$mgl_file" | sed 's/path="\(.*\)"/\1/')
	
		if [ -z "$paths" ]; then
			echo "No paths found in $mgl_file."
			continue
		fi
	
		has_missing_paths=false
		while IFS= read -r path; do
			# Trim leading and trailing spaces from the path
			trimmed_path=$(echo "$path" | sed 's/^ *//;s/ *$//')
	
			full_path="${base_dir}/${trimmed_path}"
			referenced_paths+=("$full_path")
			
			echo -n "Checking: $trimmed_path ..."
	
			if [ ! -f "$full_path" ]; then
				echo " Missing"
				has_missing_paths=true
			else
				echo " Found"
			fi
		done <<< "$paths"
	
		if [ "$has_missing_paths" = true ]; then
			mgl_with_missing_paths+=("$(basename "$mgl_file")")
		fi
	done
	
	# Check if any .mgl files with missing paths were found
	if [ ${#mgl_with_missing_paths[@]} -eq 0 ]; then
		echo ""
		echo "All .mgl files match up with installed games."
	else
		echo ""
		echo "List of .mgl files with missing files:"
		for mgl_file in "${mgl_with_missing_paths[@]}"; do
			echo "$mgl_file"
		done
	fi
	

	
}

#### ARCHIVE ZIP DOWNLOAD



archive_zip_view() {
	echo "$1"
    # Use jq to URL-encode the file name properly.
    encoded_file_name=$(echo "$1" | tr -d '\n' | jq -sRr '@uri')
    # Construct the new URL with the encoded file name and ensure it ends with a slash
    new_url="${xml_url/0mhz-dos_files.xml/$encoded_file_name}/"
    curl_output=$(curl -s --insecure -L "$new_url")

    # Check if curl command was successful
    if [ $? -ne 0 ]; then
        echo "Error accessing $new_url. Please check your internet connection or URL."
        return 1
    fi

    # Validate the output, for example, by checking if it includes expected file names
    if ! echo "$curl_output" | grep -q "games/"; then
        echo "Unexpected content received from $new_url."
        return 1
    fi

    # Process the output and make sure it's valid
    echo "$curl_output" | grep "media/" | python -c "import html, sys; print(html.unescape(sys.stdin.read()))" | sed -n 's/.*">\(.*\)<\/a>.*/\1/p' | sed 's|games/ao486/||'
}


zip_download() {
    # Function to check for zip file on archive.org and verify its contents
    check_and_download_zip() {
        local mgl_file="$1"
        local base_mgl="${mgl_file%.mgl}"
        local zip_name="${base_mgl}.zip"
        local selected_zip=""
        echo ""
        echo "Checking: $zip_name"

        # Use the archive_zip_view function to check if the zip file exists and has the correct contents
        if archive_zip_view_output=$(archive_zip_view "${zip_name}"); then
            # Assume the zip file is correct until proven otherwise
            zip_file_correct=true
            
            # Convert paths found in mgl to an array
            readarray -t mgl_paths < <(grep -o 'path="[^"]*"' "$dos_mgl/$mgl_file" | sed 's/path="//;s/"//')

            # Convert paths found in remote zip to an array
            readarray -t archive_paths <<< "$archive_zip_view_output"

            for mgl_path in "${mgl_paths[@]}"; do
                if ! fgrep -q -- "$mgl_path" <<< "${archive_paths[*]}"; then
                    zip_file_correct=false
                    echo "$mgl_path not found in archive.org zip"
                    break
                fi
            done

            if [ "$zip_file_correct" = true ]; then
                echo "Zip and contents verified. Downloading..."
                selected_zip="$zip_name"
            else
                echo "Zip file or contents incorrect. Skipping download."
                return
            fi
        else
            echo "Zip file not found on archive.org. Skipping download."
            return
        fi

        # Proceed with download if a file has been selected
        if [ ! -z "$selected_zip" ]; then
            dl_zip="$(echo https://archive.org/download/0mhz-dos/"$selected_zip" | sed 's/ /%20/g')"
            mkdir -p "${base_dir}/.0mhz_downloader"
            curl --insecure -L -# -o "${base_dir}/.0mhz_downloader/$selected_zip" "$dl_zip"
            
            # Verify the file was downloaded and is not empty
            if [ -s "${base_dir}/.0mhz_downloader/$selected_zip" ]; then
                # Only unzip media folder
                if unzip -o "$base_dir/.0mhz_downloader/${selected_zip}" "games/ao486/media/*" -d "$games_loc"; then
                    echo "Unzipped $selected_zip successfully."
                    rm "$base_dir/.0mhz_downloader/${selected_zip}"
                else
                    echo "Error unzipping $selected_zip. Archive may be corrupt or not a valid zip file."
                fi
            else
                echo "Download failed or file is empty for $selected_zip. Skipping."
            fi
        fi
    }

    for mgl_file in "${mgl_with_missing_paths[@]}"; do
        check_and_download_zip "$mgl_file"
    done
}


#### CLEANUP

cleanup() {
	echo "Cleanup..."
	rm -f "$repo_zip_path"
	rm -rf "$temp_dir"
	
	if [ "$unresolved_mgls" = true ]; then
		echo ""
		echo "Verifying .mgl files post-download..."
	
		for mgl_basename in "${mgl_with_missing_paths[@]}"; do
			still_missing_any=false
			mgl_file="$dos_mgl/$mgl_basename"
			while IFS= read -r line; do
				path=$(echo "$line" | grep -o 'path="[^"]*"' | sed 's/path="\(.*\)"/\1/')
				if [[ ! -z "$path" ]]; then
					full_path="$base_dir/${path}"
					if [ ! -f "$full_path" ]; then
						still_missing_any=true
						break
					fi
				fi
			done < "$mgl_file"
			
			if [ "$still_missing_any" = true ]; then
				echo "Incomplete .mgl detected, deleting: $mgl_basename"
				rm "$mgl_file"
			else
				echo "$mgl_basename is complete."
			fi
		done
	fi
	
	
	
	
	if [ "$delete_unmatched_files" = true ]; then
		echo "File cleanup is enabled."
		media_dir="${base_dir}/media"
	
		# List all files in the media directory
		find "$media_dir" -type f | while read media_file; do
			
			# Check if the relative path is in the referenced_paths array
			if [[ ! " ${referenced_paths[@]} " =~ " ${media_file} " ]]; then
				echo "Deleting file: $media_file"
				rm "$media_file"
			fi
		done
	fi
}


#####  MGL AWAY

prep
download_mgl_gh
mgl_updater
mgl_files_check
zip_download
cleanup
