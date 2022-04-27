# BEGIN - tmu

# BEGIN - tmux (from .bashrc_common)
alias vtm='pushd ${HOME};vi ${HOME}/.tmux.conf;popd'

alias tm='tmux attach-session -d -t'
alias ta='tmux attach-session'
alias tma='tmux attach-session -t'
alias tml='tmux list-sessions'
alias tmt='tmux rename-window'
alias tmta='tmux set-window-option automatic-rename on'
alias tmd='cd ${TMUX_SESSION_PATH}'
alias tmm='~/local/bin/tmuxSetupMusicSession.bash'
alias tmn='tn main'
alias tmg='tn game'
alias tmp='tn photos'
alias tmw='tn work'

# create a new session and attach
function tn()
{
  if [ -z "$1" ]
  then
    echo "Usage: ${FUNCNAME[0]} <session-name>"
    return
  fi

  __tmux_create $1
  tm $1
}

# create a new session if it doesn't exist already
function __tmux_create()
{
  if [ -z "$1" ]
  then
    echo "Usage: ${FUNCNAME[0]} <session-name>"
    return
  fi

  # maybe should match exactly...
  tmux has-session -t ${1} > /dev/null 2>&1
  if [ $? != 0 ]
  then
    tmux new-session -d -s $1 -c ${HOME}
  fi
}

# find panes that have a specific process running in
function tmps()
{
  if [[ -z "$1" ]]
  then
    echo "Usage: ${FUNCNAME[0]} <pid>"
    return
  fi
  local -r panes=$(tmux list-panes -a -F "#{pane_pid} #{pane_id}" | grep ${1})
  if [[ -z "${panes}" ]]
  then
    echo "nothing found"
    return
  fi
  if [[ "$(echo "$panes" | wc -l)" == "1" ]]
  then
    tm $(echo "$panes" | cut -d\  -f 2)
  else
    echo $panes
  fi
}

# find panes with vi running it it
function tmvi()
{
  if [ -z "$1" ]
  then
    echo "Usage: ${FUNCNAME[0]} <name>"
    return
  fi

  local vipid=$(sps "${1}" | grep "vi " | awk '{print $2;}')
  echo ${vipid}
  local ppid=$(ps ho ppid ${vipid})
  echo ${ppid}
  tmps ${ppid}
}

# source .bashrc in every pane
function tmsb()
{
  tmuxExecuteInAllSessions "tmuxExecuteInAllPanes 'source ~/.bashrc'"
}

# optionally rename window if it isn't already customized
function tmto()
{
  if [[ -z "$1" ]]
  then
    echo "Usage: ${FUNCNAME[0]} <name>"
    return
  fi

  local -r window_automatic_rename_setting=$(tmux show-window-option automatic-rename)
  if [[ -z "${window_automatic_rename_setting}" ]]
  then
    #echo "automatic (from global)"
    tmt "$1"
  elif [[ "${window_automatic_rename_setting##* }" == "on" ]]
  then
    #echo "automatic (from window)"
    tmt "$1"
  fi
}

function __tmux_attach_autocomplete()
{
  TMUX_SESSIONS=$(tmux list-session -F "#{session_name}" | xargs)
  local -r cur=${COMP_WORDS[COMP_CWORD]}
  COMPREPLY=($(compgen -W "${TMUX_SESSIONS}" -- ${cur}))
}

complete -F __tmux_attach_autocomplete tm
complete -F __tmux_attach_autocomplete ta
complete -F __tmux_attach_autocomplete tma
complete -F __tmux_attach_autocomplete "tmux attach-session"
# END - tmux (from .bashrc_common)

# BEGIN - tmux (from tmuxCommon.bash)

# send quit command to known programs (in preparation for exit)
function __tmux_SendQuitCommand()
{
  local -r targetPane=${1}
  shift
  local -r paneProcessList=${1}

  local -r vimPattern='^(vi|vim) '
  if [[ "${paneProcessList}" =~ $vimPattern ]]
  then
    tmux send-keys -t ${targetPane} Escape ":q" Enter
    return 0
  fi

  local -r morePattern='^(more|less\s+[0-9]+\s+less.*-K) '
  local -r longCmdPattern='^(platinumNotify.bash|submitNotify.bash|iblaze|watch|ping) |(textBillboard)'
  if [[ "${paneProcessList}" =~ $morePattern ]] \
      || [[ "${paneProcessList}" =~ $longCmdPattern ]]
  then
    tmux send-keys -t ${targetPane} C-c
    return 0
  fi

  local -r quitPattern='^(mtr|less|man|calctool|ncmpcpp|top|ncdu) '
  if [[ "${paneProcessList}" =~ $lessPattern ]]
  then
    tmux send-keys -t ${targetPane} q
    return 0
  fi

  local -r lessPattern='^(less|man|calctool|ncmpcpp|top|git\s+[0-9]+\s+git grep) '
  if [[ "${paneProcessList}" =~ $lessPattern ]]
  then
    tmux send-keys -t ${targetPane} C-c
    tmux send-keys -t ${targetPane} q
    return 0
  fi

  return 1
}

# attempt to gracefully exit a pane
function __tmux_QuitGracefullyCommonInteractiveApps()
{
  local -r targetPane=${1}

  # Determine if window is in a mode (copy-mode, result from tmux command)
  #  Quit it, if so
  local -r is_in_mode=$(tmux display-message -t ${targetPane} -p -F "#{pane_in_mode}")
  if [[ ${is_in_mode} -ne 0 ]]
  then
    tmux send-keys -t ${targetPane} q
  fi

  # find parent PID and then look at children for intelligent exiting
  local -r pane_ppid=$(tmux display-message -t ${targetPane} -p -F "#{pane_pid}")
  local previousPaneProcessList=""
  while :
  do
    paneProcessList=$(ps h --ppid ${pane_ppid} -o comm,pid,cmd)
    # if failed (no child processes), then done
    if [[ $? -ne 0 ]]
    then
      return 0
    fi
    if [[ "${paneProcessList}" == "${previousPaneProcessList}" ]]
    then
      return 1
    fi
    __tmux_SendQuitCommand "${targetPane}" "${paneProcessList}"
    if [[ $? -eq 0 ]]
    then
      previousPaneProcessList=${paneProcessList}
      # give the application a little time to get its work done
      sleep 1
    else
      return 1
    fi
  done
}
# END - tmux (from tmuxCommon.bash)

# BEGIN - tmux (from tmuxExecuteInAllPanes.bash)

function __tmux_SendToAllPanes()
{
  local -r target_window_id="$1"
  shift
  local -r skip_pane_id="$1"
  for pane_id in $(tmux list-panes -t ${target_window_id} -F '#{pane_id}')
  do
    if [[ ! -z "$skip_pane_id" ]] && [[ "$skip_pane_id" == "$pane_id" ]]
    then
      echo "skipping pane_id: $pane_id (${skip_pane_id})"
      continue
    fi
    echo "select-pane -t ${pane_id}"
    tmux select-pane -t ${pane_id}
    #sleep 1
    __tmux_QuitGracefullyCommonInteractiveApps ${target_window_id}.${pane_id}
    if [[ $? -eq 0 ]]
    then
      tmux send-keys -t ${target_window_id}.${pane_id} C-u "${commandToExecute}" Enter
    fi
  done
}

function tmuxExecuteInAllPanes()
{
  # If not in a session, then quit
  if [[ -z "${TMUX}" ]]
  then
    echo "not in a tmux session, so nothing to do"
    return
  fi

  if [[ -z "${1}" ]]
  then
    echo "Usage: ${FUNCNAME[0]} <command>"
    return
  fi

  local -r commandToExecute="${@}"

  local -r ORIG_WINDOW_ID=$(tmux display-message -p '#{window_id}')
  local -r ORIG_PANE_ID=$(tmux display-message -p '#{pane_id}')

  for window in $(tmux list-windows -F '#{window_id}')
  do
    # skip first window
    if [[ "$window" == "$ORIG_WINDOW_ID" ]]
    then
      echo "skipping window: $window"
      continue
    fi
    echo "loop: select-window -t ${window}"
    tmux select-window -t "${window}"
    #sleep 1
    __tmux_SendToAllPanes "${window}"
  done

  ## Do the original window last
  echo "final: select-window -t ${window}"
  tmux select-window -t ${ORIG_WINDOW_ID}
  __tmux_SendToAllPanes ${ORIG_WINDOW_ID} ${ORIG_PANE_ID}

  # Finally, go back to the original pane
  tmux select-pane -t ${ORIG_WINDOW_ID}.${ORIG_PANE_ID}

  # and execute
  tmux send-keys -t ${ORIG_WINDOW_ID}.${ORIG_PANE_ID} C-u "${commandToExecute}" Enter
}
# END - tmux (from tmuxExecuteInAllPanes.bash)

# BEGIN - tmux (from tmuxExecuteInAllSessions.bash)
function tmuxExecuteInAllSessions()
{
  if [[ -z "${1}" ]]
  then
    echo "Usage: ${FUNCNAME[0]} <command>"
    return
  fi

  local -r commandToExecute="${1}"

  # if in a session, capture to skip and do this session last
  local ORIG_SESSION=""
  if [[ ! -z "${TMUX}" ]]
  then
    ORIG_SESSION=$(tmux display-message -p '#S')
  fi

  for session in $(tmux list-sessions -F '#S')
  do
    # 2021-04-14: may not be needed, as tmuxExecuteInSession now bypasses
    # __tmux_QuitGracefullyCommonInteractiveApps when executed in like named
    # session
    if [[ "${session}" == "${ORIG_SESSION}" ]]
    then
      echo ${session} - SKIPPING
      continue
    else
      echo ${session}
    fi

    tmuxExecuteInSession "${session}" "${commandToExecute}"
  done

  # if in a session, then do command last
  if [[ ! -z "${ORIG_SESSION}" ]]
  then
    tmux send-keys -t "${ORIG_SESSION}" "${commandToExecute}" ENTER
  fi
}
# END - tmux (from tmuxExecuteInAllSessions.bash)

function tmuxExecuteInSession()
{
  if [[ -z "${1}" ]] || [[ -z "${2}" ]]
  then
    echo "Usage: ${FUNCNAME[0]} <session> <command>"
    return
  fi

  local -r session="${1}"
  local -r commandToExecute="${2}"

  local ORIG_SESSION=""
  if [[ ! -z "${TMUX}" ]]
  then
    ORIG_SESSION=$(tmux display-message -p '#S')
  fi

  if [[ "${ORIG_SESSION}" != "${session}" ]]
  then
    __tmux_QuitGracefullyCommonInteractiveApps "${session}"
    if [[ $? -ne 0 ]]
    then
      echo WARNING: unable to gain control of ===${session}===
      return
    fi
  fi
  tmux send-keys -t "${session}" C-u "${commandToExecute}" ENTER
}

# BEGIN - tmux (from tmuxCloseDownAllPanes.bash)
function tmcap()
{
  tmuxExecuteInAllPanes exit
  tmuxExecuteInAllPanes exit
}
# END - tmux (from tmuxCloseDownAllPanes.bash)

# BEGIN - tmux (from tmuxCloseDownAllSessions.bash)
function tmcas()
{
  tmuxExecuteInAllSessions "tmuxExecuteInAllPanes exit"
  sleep 5
  echo === Still Open ===
  tmux list-sessions
}
# END - tmux (from tmuxCloseDownAllSessions.bash)

# BEGIN - tmuxCodingSession
function tmuxCodingSession()
{
  if [[ -z "$1" ]]
  then
    echo "Usage: ${FUNCNAME[0]} <name> [<directory>]"
    return
  fi
  session_name=${1}
  shift

  if [[ ! -z "$1" ]]
  then
    working_directory=${1}
    shift

    if [ ! -d "${working_directory}" ]
    then
      echo "Usage: ${FUNCNAME[0]} <name> [<directory>]"
      echo "ERROR: <directory> (${working_directory}) must exist"
      return
    fi
  elif ! $(tmux list-sessions | grep -qe "^${session_name}:")
  then
    echo "Usage: ${FUNCNAME[0]} <name> [<directory>]"
    echo "ERROR: <directory> must be specified if session does not exist (AND is being created)."
    return
  fi

  tmux list-sessions | grep -qe "^${session_name}:" || {
    # create new session and give it a name but don't attach
    TMUX= tmux new-session -d -s ${session_name} -c ${working_directory}
    # since the next command doesn't tell the very first pane,
    # tell it explicitly.
    tmux send-keys -t ${session_name}:0 "export TMUX_SESSION_PATH=${working_directory}; clear" Enter
    # tell all new windows created in session to start at this path
    tmux set-environment -t ${session_name} TMUX_SESSION_PATH ${working_directory}

    window_index=0
    tmux split-window -t ${session_name}:${window_index} -c ${working_directory}
    tmux split-window -t ${session_name}:${window_index} -c ${working_directory}
    tmux select-layout -t ${session_name}:${window_index} even-vertical
    tmux select-pane -t ${session_name}:${window_index}.0

    window_index=1
    tmux new-window -t ${session_name} -c ${working_directory}
    tmux split-window -t ${session_name}:${window_index} -p 30 -c ${working_directory}
    tmux select-pane -t ${session_name}:${window_index}.0

    window_index=2
    tmux new-window -t ${session_name} -c ${working_directory}
    tmux split-window -t ${session_name}:${window_index} -p 30 -c ${working_directory}
    tmux select-pane -t ${session_name}:${window_index}.0

    tmux select-window -t ${session_name}:1
  }
  # attach to the session (cause now it exists for sure)
  if [[ -z ${TMUX} ]]
  then
    tmux attach-session -d -t ${session_name}
  else
    current_session=$(tmux display-message -p '#{session_name}')
    if [[ "${current_session}" == "${session_name}" ]]
    then
      echo "INFO: already in session: ${session_name}"
    else
      tmux switch-client -t ${session_name}
    fi
  fi
}

alias tmcs='tmuxCodingSession'

SRC_ROOT=${HOME}/src

# Create a new session for an existing replica
function createTmuxCodingSessionForGitRepo()
{
  if [[ -z "$1" ]] || [[ -z "$2" ]]
  then
    echo "Usage: ${FUNCNAME[0]} <repository> <work_area>"
    return
  fi
  repository=${1}
  shift
  work_area=${1}
  shift

  working_directory="${SRC_ROOT}/${work_area}"

  temp1=${repository%%.git}
  full_working_directory="${working_directory}/${temp1##*/}"
  if [[ ! -d  ${full_working_directory} ]]
  then
    echo "ERROR: full working directory does not exist (${full_working_directory})"
    ls "${working_directory}"
    return
  fi

  # verify the clone matches
  remote_origin_url=$(cd ${full_working_directory} && git config --get remote.origin.url)
  if [[ "${repository}" != "${remote_origin_url}" ]]
  then
    echo "ERROR: repository does not match remote origin (${repository} != ${remote_origin_url})"
    return
  fi

  tmuxCodingSession "${work_area}-src" "${full_working_directory}"
}

# Create a new replica by cloning and create a new session
function createNewTmuxCodingSessionForGitRepo()
{
  if [[ -z "$1" ]] || [[ -z "$2" ]]
  then
    echo "Usage: ${FUNCNAME[0]} <repository> <work_area>"
    return
  fi
  repository=${1}
  shift
  work_area=${1}
  shift

  working_directory="${SRC_ROOT}/${work_area}"
  if [[ -d "${working_directory}" ]]
  then
    echo "ERROR: work area (${work_area}) exists"
    ls ${SRC_ROOT}
    return
  fi

  mkdir -p "${working_directory}"
  cd "${working_directory}"
  git clone "${repository}"
  cd

  createTmuxCodingSessionForGitRepo "${repository}" "${work_area}"
}

alias listRepos='echo "use '"'"repos"'"'"'
function repos()
{
  for dirname in ${SRC_ROOT}/*
  do
    if [[ ! -d ${dirname} ]]
    then
      echo "skipping non directory (${dirname})"
      continue
    fi
    for subdirname in ${dirname}/*
    do
      if [[ ! -d ${subdirname} ]]
      then
        echo "skipping non directory (${dirname}/${subdirname})"
        continue
      fi
      remote_origin_url=$(git -C "${subdirname}" config --get remote.origin.url)
      echo "$(basename ${dirname}) $(basename ${subdirname}) ${remote_origin_url}"
    done
  done
}

# Adjust path for easy LLVM testing
function llpath()
{
  if [[ ! -z "${TMUX}" ]] && [[ ! -z "${TMUX_SESSION_PATH}" ]]
  then
    remote_origin_url=$(git -C "${TMUX_SESSION_PATH}" config --get remote.origin.url)
    if [[ "${remote_origin_url}" == "${LLVM_REPOSITORY}" ]]
    then
      # If it is already there, then return
      if [[ "${PATH}" =~ "${TMUX_SESSION_PATH}/build/bin" ]]
      then
        return
      fi
      export PATH=${TMUX_SESSION_PATH}/build/bin:${PATH}
      tmux set-environment PATH ${PATH}
    fi
  fi
}

# automate path addition
llpath
# END - tmuxCodingSession

# ensure this variable is set in the environment
if [[ ! -z "${TMUX}" ]] && [[ ! -z "${TMUX_DISK_STATUS_SPEC}" ]]
then
  tmux set-environment TMUX_DISK_STATUS_SPEC "${TMUX_DISK_STATUS_SPEC}"
fi

# END - tmux support
# vim: filetype=bash
