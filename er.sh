#!/bin/bash

FOLDER="custom"
[[ "${FOLDER}" != */ ]] && FOLDER="${FOLDER}/"

SRC_PATH="~/src"
DIRS_360=("360_community" "360_generic" "360_ai")
DIRS_ODOO=("odoo" "enterprise")

VERSION=$(git rev-parse --abbrev-ref HEAD | sed 's/-.*//')
STAGING=${VERSION}-staging
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# checkout ticket branch
function _ch {
    if [ -n "$3" ]; then
        git checkout ${VERSION}-ticket-$2-$3
    else
        git checkout ${VERSION}-ticket-$2
    fi
    #git checkout ${VERSION}-ticket-$2
}
function _chs {
    git checkout ${STAGING}-ticket-$2
}

# checkout task branch
function _cht {
    if [ -n "$3" ]; then
        git checkout ${VERSION}-task-$2-$3
    else
        git checkout ${VERSION}-task-$2
    fi
}
function _chst {
    git checkout ${STAGING}-task-$2
}

# branch
function _b {
  TICKET=$2
  _check_ticket
  BRANCH_NAME="$(git rev-parse --abbrev-ref HEAD)-ticket-$TICKET"
  if [ -n "$3" ]; then
    git checkout -b $BRANCH_NAME-$3
  else
    git checkout -b $BRANCH_NAME
  fi
}

# branch for task
function _bt {
  TICKET=$2
  BRANCH_TYPE="task"
  export BRANCH_TYPE
  _check_ticket
  BRANCH_NAME="$(git rev-parse --abbrev-ref HEAD)-task-$TICKET"
  if [ -n "$3" ]; then
    git checkout -b $BRANCH_NAME-$3
  else
    git checkout -b $BRANCH_NAME
  fi
}

function _chm {
  git checkout ${VERSION}
}
function _chms {
  git checkout ${STAGING}
}

function _check_ticket {
  if [ -z "$TICKET" ]; then
    BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
    # Check for task branch pattern
    if [[ $BRANCH_NAME =~ -task-([0-9]+)(-.*)? ]]; then
      TICKET=${BASH_REMATCH[1]}
      BRANCH_TYPE="task"
      echo "Branch task: $TICKET"
    # Check for ticket branch pattern with suffix
    elif [[ $BRANCH_NAME =~ -ticket-([0-9]+)(-.*)? ]]; then
      TICKET=${BASH_REMATCH[1]}
      BRANCH_TYPE="ticket"
      echo "Branch ticket: $TICKET"
    # Check for ending with a number (ticket assumed for backward compatibility)
    elif [[ $BRANCH_NAME =~ -([0-9]+)$ ]]; then
      TICKET=${BASH_REMATCH[1]}
      BRANCH_TYPE="ticket"
      echo "Branch \$ ticket: $TICKET"
    else
      read -p "Please enter the ticket: " TICKET
      BRANCH_TYPE="ticket"
    fi
    export TICKET
    export BRANCH_TYPE
  else
    echo "Current ticket: $TICKET"
    # If BRANCH_TYPE not set, determine it from branch name
    if [ -z "$BRANCH_TYPE" ]; then
      BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
      if [[ $BRANCH_NAME =~ -task- ]]; then
        BRANCH_TYPE="task"
      else
        BRANCH_TYPE="ticket"
      fi
      export BRANCH_TYPE
    fi
  fi
}

function _check_clean_status {
  if [ -n "$(git status --porcelain)" ]; then
    echo "Error: Working directory is not clean"
    exit 1
  fi
}

function _check_feature_branch {
  if [[ ! $CURRENT_BRANCH =~ $TICKET ]]; then
    echo "Error: Not on a feature branch"
    exit 1
  fi
}

function _f {
  _check_clean_status
  git fetch --all
  git checkout ${STAGING}
  git merge
  git checkout ${VERSION}
  git merge
  git checkout ${CURRENT_BRANCH}
}

# check merge
function _cm {
    _check_clean_status
    _check_feature_branch

    diff_output=$(git merge-tree $(git merge-base ${VERSION} ${STAGING}) ${VERSION} ${STAGING})
    if [[ -n "$diff_output" ]]; then
        echo "Error: Staging is out of sync with master, use ccp to get a new feature-staging branch"
        exit 1
    fi

    git checkout ${STAGING}  > /dev/null 2>&1
    # Check if the feature branch can be merged into staging without conflict
    MERGE_TEST=$(git merge --no-commit --no-ff ${CURRENT_BRANCH} 2>&1)
        if [[ $MERGE_TEST =~ "conflict" ]]; then
        echo "Error: Cannot merge feature branch into staging without conflict"
        git merge --abort
        git checkout ${CURRENT_BRANCH}  > /dev/null 2>&1
        exit 1
    fi

    echo "Feature branch can be merged into staging without conflict and only brings its own commits"
}

function _ccp {
  _check_clean_status
  _check_feature_branch
  _check_ticket
  _chms  # switch to staging
  # Create a new staging branch based on the branch type
  if [ "$BRANCH_TYPE" = "task" ]; then
    _bt 0 $TICKET  # switch to a new task staging branch
  else
    _b 0 $TICKET  # switch to a new ticket staging branch
  fi
  commits=$(git log --format="%H" ${VERSION}..${CURRENT_BRANCH}) # Cherry-pick the commits onto the VERSION branch 
  echo $commits
  for commit in $commits; do
    git cherry-pick -x $commit
    if [ $? -ne 0 ]; then
      echo "Error: cherry-pick failed at commit $commit"
      exit 1
    fi
  done
}

# show all branches containing ticket
function _ls {
    git branch --list "*-ticket-$2"
    git branch --list "*-task-$2"
}

# commit
function _c {
  _check_ticket
  local MSG="${2}"
  COMMIT_NAME="[${BRANCH_TYPE}-$TICKET]"
  PREFIX_LEN=${#FOLDER}
  FOLDERS=$(git -C "$folder" diff --cached --name-only --diff-filter=ACM | xargs -I {} dirname {} | \
    awk -v folder="$FOLDER" -v flen="$PREFIX_LEN" '{sub("^" folder, ""); sub("/.*", ""); print}' | \
    sort -u | sed ':a;N;$!ba;s/\n/, /g' | sed 's/, $//'
  )
  COMMIT_NAME="${COMMIT_NAME} ${FOLDERS}"
  if [ -n "$MSG" ]; then
    COMMIT_NAME="${COMMIT_NAME}: ${MSG}"
  fi
  git commit -m "$COMMIT_NAME"
}

# test
function _t {
  gh workflow run test.yml --ref $(git rev-parse --abbrev-ref HEAD)
}

# Check if a directory has uncommitted changes (ignoring untracked files)
function _check_dir_changes {
  local dir_path="$1"
  if [ -d "$dir_path" ]; then
    cd "$dir_path"
    if [ -n "$(git status --porcelain | grep -v '^??')" ]; then
      return 0  # Has changes
    fi
    return 1  # No changes
  fi
  return 1  # Directory doesn't exist
}

# Process 360 directories
function _process_360_dirs {
  local branch="$1"
  local changed_dirs=()
  
  for dir in "${DIRS_360[@]}"; do
    local dir_path="$SRC_PATH/$dir"
    if _check_dir_changes "$dir_path"; then
      changed_dirs+=("$dir")
    fi
  done
  
  if [ ${#changed_dirs[@]} -gt 0 ]; then
    echo "Directories with changes: ${changed_dirs[*]}"
    read -p "Do you want to interrupt the process completely? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "Process interrupted."
      exit 1
    fi
  fi
  
  for dir in "${DIRS_360[@]}"; do
    local dir_path="$SRC_PATH/$dir"
    if [ -d "$dir_path" ]; then
      cd "$dir_path"
      if [ -n "$(git status --porcelain | grep -v '^??')" ]; then
        echo "Folder $dir is ignored (has changes)"
      else
        if ! git checkout "$branch" 2>&1; then
          echo "Error checking out $branch in $dir"
        fi
      fi
    fi
  done
}

# Process Odoo directories
function _process_odoo_dirs {
  local branch="$1"
  
  for dir in "${DIRS_ODOO[@]}"; do
    local dir_path="$SRC_PATH/$dir"
    if [ -d "$dir_path" ]; then
      cd "$dir_path"
      if [ -n "$(git status --porcelain)" ]; then
        git stash
        echo "Stashed changes in $dir"
      fi
      if ! git checkout "$branch" 2>&1; then
        echo "Error checking out $branch in $dir"
      fi
    fi
  done
}

# Main checkout function
function _co {
  local branch="$1"
  if [ -z "$branch" ]; then
    echo "Usage: _co <branch_name>"
    return 1
  fi
  
  echo "Checking out branch: $branch"
  
  _process_360_dirs "$branch"
  _process_odoo_dirs "$branch"
  
  echo "Checkout process completed."
}

function _pr {
  local current_branch base_branch

  current_branch=$(git rev-parse --abbrev-ref HEAD)

  if [[ "$current_branch" =~ ^([0-9]+\.[0-9]+(-staging)?)-.+$ ]]; then
    base_branch="${BASH_REMATCH[1]}"
    gh pr create --base "$base_branch" --head "$current_branch"
  else
    echo "❌ Error: Branch name '$current_branch' does not match expected pattern VERSION[-STAGING]-something"
    return 1
  fi
}

_$1 "$@"
