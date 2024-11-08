#!/bin/bash

# Define colors
BOLD=$'\033[1m'
RESET=$'\033[0m'
WHITE=$'\033[97m'
GREEN=$'\033[32m'

# Check if the script is running on Android
if [ -f "/system/build.prop" ]; then
	SUDO=""
else
	# Check for sudo availability on other Unix-like systems
	if command -v sudo >/dev/null 2>&1; then
		SUDO="sudo"
	else
		echo "Sorry, sudo is not available."
		exit 1
	fi
fi

# this will check for sudo permission
allow_sudo() {
	if [ -n "$SUDO" ]; then
		$SUDO -n true 2>/dev/null
		if [ $? -ne 0 ]; then
			$SUDO -v
		fi
	fi
}

# Function to display usage
usage() {
	echo "${BOLD}Usage:${RESET}"
	echo "  $(basename "$0" .sh) [branch_to_delete]"
	echo
	echo "${BOLD}Description:${RESET}"
	echo "  This script deletes a specified Git branch or the current branch if no"
	echo "  branch name is provided. It will prompt for confirmation before deleting"
	echo "  the branch, and will also handle deletion of remote branches if they exist."
	echo "  The branch to be deleted cannot be the default branch of the repository."
	echo
	echo "${BOLD}Options:${RESET}"
	echo "  [branch_to_delete]  Name of the branch to delete."
	echo "                      If omitted, the current branch is deleted."
	echo "                      The branch cannot be the default"
	echo "                      branch of the repository."
	echo
	echo "  --help              Display this help message."
	echo
	echo " If no arguments are provided, the current branch"
	echo " will be deleted if it's not the default branch."
	exit 0
}

# Check if GitHub CLI is installed
if ! gh --version >/dev/null 2>&1; then
	echo "gh is not installed."
	exit 1
fi

# Check if --help is the first argument
[ "$1" = "--help" ] && usage

# Check if it is a git repo and suppress errors
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  is_a_git_repo=true
else
  is_a_git_repo=false
fi

# Initialize has_remote variable
has_remote=false

# Check if it has a remote only if it's a git repo
if [ "$is_a_git_repo" = true ]; then
	if git remote -v | grep -q .; then
		has_remote=true
	fi
fi

if [ "$is_a_git_repo" = "true" ]; then
	current_branch=$(git branch | awk '/\*/ {print $2}')
	default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
	current_user=$(awk '/user:/ {print $2; exit}' ~/.config/gh/hosts.yml)

	if [ -z "$default_branch" ]; then
		default_branch=$(git config --get init.defaultBranch)
	fi

	if [ $# -eq 1 ]; then
		if [ "$1" = "$default_branch" ]; then
			echo "${BOLD} ■■▶ Fatal ! Cannot Delete the Default Branch "
		elif ! git show-ref --verify --quiet "refs/heads/$1" &>/dev/null; then
			echo "${BOLD} ■■▶ Fatal ! Branch ${GREEN}$1 ${WHITE}doesn't exist ${RESET}"
		else
			# this to check if we want to delete the remote branch too
			check_delete_remote_branch() {
				if [ "$current_branch" = "$default_branch" ]; then
					echo "${BOLD} ■■▶ Fatal ! Cannot Delete the Default Branch "
				else
					printf "${BOLD}${WHITE}Delete remote branch${GREEN} "$current_branch"${WHITE} ? (y/n) ${RESET}"
					read delete_remote_branch
					echo ${RESET}
					if [ "$delete_remote_branch" = "y" ]; then
						git push origin --delete "$current_branch"
					elif [ "$delete_remote_branch" = "n" ]; then
						return 0
					else
						check_delete_remote_branch
					fi
				fi
			}

			check_delete_branch() {
				branch_name="$1"

				printf "${BOLD}${WHITE}Delete branch${GREEN} "$branch_name"${WHITE} ? (y/n) ${RESET}"
				read delete_branch

				if [ "$delete_branch" = "y" ]; then
					if [ "$current_branch" != "$default_branch" ]; then
						git checkout $default_branch >/dev/null 2>&1
					fi

					if [ "$has_remote" = "true" ]; then
						repo_url=$(git config --get remote.origin.url)
						repo_owner=$(echo "$repo_url" | awk -F '[/:]' '{print $(NF-1)}')

						# check if we are not the owner of the repo
						if [ "$repo_owner" == "$current_user" ]; then
							is_remote_branch=$(git branch -r | grep "origin/$1")
							if [ -n "$is_remote_branch" ]; then
								# prompt for sudo
								# password if required
								allow_sudo

								# Check for internet connectivity to GitHub
								if $SUDO ping -c 1 github.com &>/dev/null; then
									check_delete_remote_branch
								fi
							fi
						fi
					fi	
					git branch -D "$1"
				elif [ "$delete_branch" = "n" ]; then
					return 0
				else
					check_delete_branch $branch_name
				fi
			}
			check_delete_branch $1
		fi
	elif [ $# -eq 0 ]; then
		if [ "$current_branch" = "$default_branch" ]; then
			echo "${BOLD}${WHITE} ■■▶ Fatal ! Cannot Delete the Default Branch "
		else
			check_delete_branch() {
				printf "${BOLD}${WHITE}Delete branch${GREEN} "$current_branch"${WHITE} ? (y/n) ${RESET}"
				read delete_branch
				if [ "$delete_branch" = "y" ]; then
					# TODO : Remote branch Deletion
					check_delete_remote_branch() {
						if [ "$current_branch" = "$default_branch" ]; then
							echo "${BOLD}${WHITE} ■■▶ Fatal ! Cannot Delete the Default Branch "
						else
							printf "${BOLD}${WHITE}Delete remote branch${GREEN} "$current_branch"${WHITE} ? (y/n) ${RESET}"
							read delete_remote_branch
							echo ${RESET}
							if [ "$delete_remote_branch" = "y" ]; then
								git push origin --delete "$current_branch"
							elif [ "$delete_remote_branch" = "n" ]; then
								return 0
							else
								check_delete_remote_branch
							fi
						fi
					}

					git checkout "$default_branch" >/dev/null 2>&1

					if [ "$has_remote" = "true" ]; then
						repo_url=$(git config --get remote.origin.url)
						repo_owner=$(echo "$repo_url" | awk -F '[/:]' '{print $(NF-1)}')

						# check if we are not the owner of the repo
						if [ "$repo_owner" == "$current_user" ]; then
							is_remote_branch=$(git branch -r | grep "origin/$current_branch")
							
							if [ -n "$is_remote_branch" ]; then
								# prompt for sudo
								# password if required
								allow_sudo

								# Check for internet connectivity to GitHub
								if $SUDO ping -c 1 github.com &>/dev/null; then
									check_delete_remote_branch
								fi
							fi
						fi
					fi
					git branch -D "$current_branch"
				elif [ "$delete_branch" = "n" ]; then
					return 0
				else
					check_delete_branch
				fi
			}
			check_delete_branch
		fi
	else
		echo "${BOLD}${WHITE} ■■▶ Usage : gbd branch_to_delete"
	fi
else
	echo "${BOLD}${WHITE} ■■▶ This won't work, you are not in a git repo !"
fi
