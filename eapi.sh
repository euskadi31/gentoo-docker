#!/bin/bash
# Copyright 1999-2014 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# We need this next line for "die" and "assert". It expands
# It _must_ preceed all the calls to die and assert.
shopt -s expand_aliases
alias save_IFS='[ "${IFS:-unset}" != "unset" ] && old_IFS="${IFS}"'
alias restore_IFS='if [ "${old_IFS:-unset}" != "unset" ]; then IFS="${old_IFS}"; unset old_IFS; else unset IFS; fi'

shopt -s extdebug

__bashpid() {
    # The BASHPID variable is new to bash-4.0, so add a hack for older
    # versions.  This must be used like so:
    # ${BASHPID:-$(__bashpid)}
    sh -c 'echo ${PPID}'
}

__quiet_mode() {
    [[ ${PORTAGE_QUIET} -eq 1 ]]
}

__vecho() {
    __quiet_mode || echo "$@"
}

# Internal logging function, don't use this in ebuilds
__elog_base() {
    local messagetype
    [ -z "${1}" -o -z "${T}" -o ! -d "${T}/logging" ] && return 1
    case "${1}" in
        INFO|WARN|ERROR|LOG|QA)
            messagetype="${1}"
            shift
            ;;
        *)
            __vecho -e " ${BAD}*${NORMAL} Invalid use of internal function __elog_base(), next message will not be logged"
            return 1
            ;;
    esac
    echo -e "$@" | while read -r ; do
        echo "$messagetype $REPLY" >> \
            "${T}/logging/${EBUILD_PHASE:-other}"
    done
    return 0
}

eqawarn() {
    __elog_base QA "$*"
    [[ ${RC_ENDCOL} != "yes" && ${LAST_E_CMD} == "ebegin" ]] && echo
    echo -e "$@" | while read -r ; do
        __vecho " $WARN*$NORMAL $REPLY" >&2
    done
    LAST_E_CMD="eqawarn"
    return 0
}

elog() {
    __elog_base LOG "$*"
    [[ ${RC_ENDCOL} != "yes" && ${LAST_E_CMD} == "ebegin" ]] && echo
    echo -e "$@" | while read -r ; do
        echo " $GOOD*$NORMAL $REPLY"
    done
    LAST_E_CMD="elog"
    return 0
}

einfo() {
    __elog_base INFO "$*"
    [[ ${RC_ENDCOL} != "yes" && ${LAST_E_CMD} == "ebegin" ]] && echo
    echo -e "$@" | while read -r ; do
        echo " $GOOD*$NORMAL $REPLY"
    done
    LAST_E_CMD="einfo"
    return 0
}

einfon() {
    __elog_base INFO "$*"
    [[ ${RC_ENDCOL} != "yes" && ${LAST_E_CMD} == "ebegin" ]] && echo
    echo -ne " ${GOOD}*${NORMAL} $*"
    LAST_E_CMD="einfon"
    return 0
}

ewarn() {
    __elog_base WARN "$*"
    [[ ${RC_ENDCOL} != "yes" && ${LAST_E_CMD} == "ebegin" ]] && echo
    echo -e "$@" | while read -r ; do
        echo " $WARN*$NORMAL $RC_INDENTATION$REPLY" >&2
    done
    LAST_E_CMD="ewarn"
    return 0
}

eerror() {
    __elog_base ERROR "$*"
    [[ ${RC_ENDCOL} != "yes" && ${LAST_E_CMD} == "ebegin" ]] && echo
    echo -e "$@" | while read -r ; do
        echo " $BAD*$NORMAL $RC_INDENTATION$REPLY" >&2
    done
    LAST_E_CMD="eerror"
    return 0
}

ebegin() {
    local msg="$*" dots spaces=${RC_DOT_PATTERN//?/ }
    if [[ -n ${RC_DOT_PATTERN} ]] ; then
        dots=$(printf "%$(( COLS - 3 - ${#RC_INDENTATION} - ${#msg} - 7 ))s" '')
        dots=${dots//${spaces}/${RC_DOT_PATTERN}}
        msg="${msg}${dots}"
    else
        msg="${msg} ..."
    fi
    einfon "${msg}"
    [[ ${RC_ENDCOL} == "yes" ]] && echo
    LAST_E_LEN=$(( 3 + ${#RC_INDENTATION} + ${#msg} ))
    LAST_E_CMD="ebegin"
    return 0
}

__eend() {
    local retval=${1:-0} efunc=${2:-eerror} msg
    shift 2

    if [[ ${retval} == "0" ]] ; then
        msg="${BRACKET}[ ${GOOD}ok${BRACKET} ]${NORMAL}"
    else
        if [[ -n $* ]] ; then
            ${efunc} "$*"
        fi
        msg="${BRACKET}[ ${BAD}!!${BRACKET} ]${NORMAL}"
    fi

    if [[ ${RC_ENDCOL} == "yes" ]] ; then
        echo -e "${ENDCOL} ${msg}"
    else
        [[ ${LAST_E_CMD} == ebegin ]] || LAST_E_LEN=0
        printf "%$(( COLS - LAST_E_LEN - 7 ))s%b\n" '' "${msg}"
    fi

    return ${retval}
}

eend() {
    local retval=${1:-0}
    shift

    __eend ${retval} eerror "$*"

    LAST_E_CMD="eend"
    return ${retval}
}

__unset_colors() {
    COLS=80
    ENDCOL=

    GOOD=
    WARN=
    BAD=
    NORMAL=
    HILITE=
    BRACKET=
}

__set_colors() {
    COLS=${COLUMNS:-0}      # bash's internal COLUMNS variable
    # Avoid wasteful stty calls during the "depend" phases.
    # If stdout is a pipe, the parent process can export COLUMNS
    # if it's relevant. Use an extra subshell for stty calls, in
    # order to redirect "/dev/tty: No such device or address"
    # error from bash to /dev/null.
    [[ $COLS == 0 && $EBUILD_PHASE != depend ]] && \
        COLS=$(set -- $( ( stty size </dev/tty ) 2>/dev/null || echo 24 80 ) ; echo $2)
    (( COLS > 0 )) || (( COLS = 80 ))

    # Now, ${ENDCOL} will move us to the end of the
    # column;  irregardless of character width
    ENDCOL=$'\e[A\e['$(( COLS - 8 ))'C'
    if [ -n "${PORTAGE_COLORMAP}" ] ; then
        eval ${PORTAGE_COLORMAP}
    else
        GOOD=$'\e[32;01m'
        WARN=$'\e[33;01m'
        BAD=$'\e[31;01m'
        HILITE=$'\e[36;01m'
        BRACKET=$'\e[34;01m'
        NORMAL=$'\e[0m'
    fi
}

RC_ENDCOL="yes"
RC_INDENTATION=''
RC_DEFAULT_INDENT=2
RC_DOT_PATTERN=''

case "${NOCOLOR:-false}" in
    yes|true)
        __unset_colors
        ;;
    no|false)
        __set_colors
        ;;
esac

if [[ -z ${USERLAND} ]] ; then
    case $(uname -s) in
    *BSD|DragonFly)
        export USERLAND="BSD"
        ;;
    *)
        export USERLAND="GNU"
        ;;
    esac
fi

if [[ -z ${XARGS} ]] ; then
    case ${USERLAND} in
    BSD)
        export XARGS="xargs"
        ;;
    *)
        export XARGS="xargs -r"
        ;;
    esac
fi

hasq() {
    has $EBUILD_PHASE prerm postrm || eqawarn \
        "QA Notice: The 'hasq' function is deprecated (replaced by 'has')"
    has "$@"
}

hasv() {
    if has "$@" ; then
        echo "$1"
        return 0
    fi
    return 1
}

has() {
    local needle=$1
    shift

    local x
    for x in "$@"; do
        [ "${x}" = "${needle}" ] && return 0
    done
    return 1
}

__repo_attr() {
    local appropriate_section=0 exit_status=1 line saved_extglob_shopt=$(shopt -p extglob)
    shopt -s extglob
    while read line; do
        [[ ${appropriate_section} == 0 && ${line} == "[$1]" ]] && appropriate_section=1 && continue
        [[ ${appropriate_section} == 1 && ${line} == "["*"]" ]] && appropriate_section=0 && continue
        # If a conditional expression like [[ ${line} == $2*( )=* ]] is used
        # then bash-3.2 produces an error like the following when the file is
        # sourced: syntax error in conditional expression: unexpected token `('
        # Therefore, use a regular expression for compatibility.
        if [[ ${appropriate_section} == 1 && ${line} =~ ^${2}[[:space:]]*= ]]; then
            echo "${line##$2*( )=*( )}"
            exit_status=0
            break
        fi
    done <<< "${PORTAGE_REPOSITORIES}"
    eval "${saved_extglob_shopt}"
    return ${exit_status}
}

true
