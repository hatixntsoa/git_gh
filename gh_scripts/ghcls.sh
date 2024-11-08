#!/bin/bash

# Define colors
BOLD=$'\033[1m'
RED=$'\033[31m'
GREEN=$'\033[32m'
LIGHT_BLUE=$'\033[94m'
WHITE=$'\033[97m'
RESET=$'\033[0m'

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
	echo "  $(basename "$0" .sh)"
	echo
	echo "${BOLD}Description:${RESET}"
	echo "  This script interacts with a GitHub repository"
	echo "  associated with the current local Git repository."
	echo
	echo "  It lists the collaborators and pending invitations"
	echo "  for the repository."
	echo
	echo "${BOLD}Options:${RESET}"
	echo "  --help           Display this help message."
	echo
	echo "  If no arguments are provided, the script will"
	echo "  display the list of collaborators and pending invitations."
	exit 0
}

# Check if GitHub CLI is installed
if ! gh --version >/dev/null 2>&1; then
	echo "gh is not installed."
	exit 1
fi

# Check if --help is the first argument
[ "$1" = "--help" ] && usage

# prompt for sudo
# password if required
allow_sudo

# Check for internet connectivity to GitHub
if ! $SUDO ping -c 1 github.com &>/dev/null; then
	echo "${BOLD} ■■▶ This won't work, you are offline !${RESET}"
	exit 0
fi

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

# check if the collaborator is a GitHub user
is_a_github_user() {
	username="$1"

	# Check if username is empty
	if [ -z "$username" ]; then
		return 1
	fi

	# Build the API URL
	url="https://api.github.com/users/$username"

	# Use wget to capture the response (redirecting output to a variable)
	# wget by default outputs content, so we use the -q (quiet) option to suppress it
	# -O- option specifies that the downloaded content should be written
	# to standard output (stdout) instead of a file.
	response=$(wget -qO- --no-check-certificate "$url")

	# Check if there is no output
	# meaning it is not found
	if [ -z "$response" ]; then
		# Not Found
		return 1
	else
		# Found
		return 0
	fi
}

# ghcls functions
if [ "$is_a_git_repo" = "true" ]; then
	if [ "$has_remote" = "true" ]; then
		current_user=$(awk '/user:/ {print $2; exit}' ~/.config/gh/hosts.yml)
		repo_url=$(git config --get remote.origin.url)
		repo_owner=$(echo "$repo_url" | awk -F '[/:]' '{print $(NF-1)}')
		repo_name="$(echo "$repo_url" | awk -F '/' '{print $NF}' | sed 's/.git$//')"

		# check if we are not the owner of the repo
		if [ "$repo_owner" != "$current_user" ]; then
			echo "${BOLD} ■■▶ Sorry, you are not the owner of this repo !"
		else
			printf "${BOLD} ${LIGHT_BLUE}Collaborators ${WHITE}for the ${LIGHT_BLUE}$repo_name ${WHITE}repository "

			# List collaborators using gh api
			collaborators=$(gh api "repos/$current_user/$repo_name/collaborators" --jq '.[].login')
			invitations=$(gh api "repos/$current_user/$repo_name/invitations" --jq '.[].invitee.login')

			collaborators_count=$(echo "$collaborators" | wc -l)
			invitations_count=$(echo "$invitations" | wc -l)
			collaborators_num=$((collaborators_count + invitations_count))
			echo "${WHITE}${BOLD}($collaborators_count)"

			# Iterate through each collaborator
			if [ -n "$collaborators" ]; then
				echo "$collaborators" | while IFS= read -r collaborator; do
					if [ "$collaborator" = "$current_user" ]; then
						echo " ● $collaborator (owner)"
					else
						echo " ● $collaborator"
					fi
				done
			else
				echo "No collaborators found."
			fi

			# Check if there are pending invitations
			if [ -n "$invitations" ]; then
				# Print pending invitations
				echo "$invitations" | while IFS= read -r invitee; do
					echo " ● $invitee (invitation pending)"
				done
			fi
		fi
	else
		echo "${BOLD} ■■▶ This repo has no remote on GitHub !"
	fi
else
	echo "${BOLD} ■■▶ This won't work, you are not in a git repo !"
fi
