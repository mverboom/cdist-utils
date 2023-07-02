#!/usr/bin/env bash
#
# ExplorereQuery
#

require=( bc expr cdist )

debug() {
   printf "%s" "$1"
}

sanitycheck() {
   for file in "${require[@]}"; do
      type "$file" > /dev/null 2>&1 || { echo "$file not available."; exit 1; }
   done
   ! test -d "$CDIST_EXPLORE" && { echo "Can't find explorer directory at $CDIST_EXPLORE."; exit 1; }
}

pipeall() {
   if test "$#" -gt 0; then
      local cmd="$1"
      shift
      eval "$cmd" | pipeall "$@"
   else
      cat
   fi
}

# <explorer>:<mod>:<mod>:<mod>
# mod:
#   f[char][nr]   field[nr] where explorer line is split by [char]
#   ~[word]       line contains word
procexplore() {
   local host="$1"
   local explorer="$2"
   local explfile="${CDIST_EXPLORE}/${host}/${explorer/:*/}"

   ! test -f "$explfile" && { ( >&2 echo "Explorer file does not exist ($explfile)." ); exit 1; }
   local mods
   IFS=":" read -a mods <<< "$explorer"
   cmds=()
   for mod in "${mods[@]:1}"; do
      case ${mod:0:1} in
      \~) cmds+=( "grep \"${mod:1}\"" ) ;;
      f) cmds+=( "cut -d \" \" -f ${mod:1}" ) ;;
      *) ( 2>&1 echo "Unknown explore modifier: ${mod:0:1}." )
         exit 1 ;;
      esac
   done
   cat "$explfile" | pipeall "${cmds[@]}"
}

getexpr() {
   local host="$1"
   local items=()
   while test $pos -lt ${#ex[@]} -a ${#items[@]} -ne 3; do
      case "${ex[$pos]}" in
         [) pos=$(( pos + 1 ))
            getexpr "$host"
            items+=( $? )
            ;;
         ]) break ;;
         *) items+=( "${ex[$pos]}" ) ;;
      esac
      pos=$(( pos + 1 ))
   done
   # ToDo: verify if 0 or 1
   test "${#items[@]}" -eq 1 && return ${items[0]}
   test "${#items[@]}" -ne 3 && { echo "Invalid expression: ${items[@]}"; exit 1; }
   evaluate "$host" "${items[@]}"
   return $?
}

numexpr() {
   local res=$(echo "$1 $2 $3" | bc)
   test "$res" = "0" && return 0 || return 1
}

evaluate() {
   local host="$1"
   shift
   local items=( "$@" )

   if test "${items[0]}" != "0" -a "${items[0]}" != "1"; then
      local lval="$(procexplore "$host" "${items[0]}")"
      numfmt --from=si "${items[2]}" > /dev/null 2>&1
      test "$?" -eq 0 && local rval=$( numfmt --from=si "${items[2]}") || local rval=${items[2]}
   fi

   case "${items[1]}" in
   and) return $( expr ${items[0]} \& ${items[2]} ) ;;
   or) return $( expr ${items[0]} \| ${items[2]} ) ;;
   gt) numexpr "$lval" \> "$rval"
       return $? ;;
   ge) numexpr "$lval" \>= "$rval"
       return $? ;;
   lt) numexpr "$lval" \< "$rval"
       return $? ;;
   le) numexpr "$lval" \<= "$rval"
       return $? ;;
   =|==) test "$lval" = "$rval" > /dev/null
       test "$?" -eq 0 && return 1 || return 0 ;;
   contains) [[ "$lval" =~ .*$rval.* ]]
       test "$?" -eq 0 && return 1 || return 0 ;;
   *) echo "Error: unknown operator ${items[1]}"
      exit 1
      ;;
   esac
}

usage() {
   echo "$0 <options> <query>"
   echo
   echo "Mandatory options:"
   echo " -r <report fields>    Comma seperated list of explorer files to report for each match."
   echo "Optional options:"
   echo " -h                    This help."
   echo " -H <hosts>            Comma seperated list of hostnames."
   echo " -t <tags>             Comma seperated list of host tags, any of which should match."
   echo " -T <tags>             Comma seperated list of host tags, all of which should match."
   echo " -j                    Output in json."
   echo
   echo "Query"
   echo "The query consists of expressions which can be combined with logical operators."
   echo "An expression consists of:"
   echo "   <explorer filename> <operator> <operand>"
   echo "Supported operators:"
   echo "   ==        exact string match"
   echo "   contains  file contains string anywhere"
   echo "   eq        numerical exact match"
   echo "   gt        numerical greater than"
   echo "   ge        numerical greater or equall than"
   echo "   lt        numerical less than"
   echo "   le        numerical less or equall than"
   echo "Supported logical operators between expressions:"
   echo "   and       both are true"
   echo "   or        either or are true"
   echo "Expression always need to be grouped with brackets, no precedence is applied."
   echo
   echo "Examples:"
   echo "Show hostname and kernel if distr explorer is debian:"
   echo "  $0 -r hostname,kernel distr == debian"
   echo "Show fqnd and IPv4 address for all debian systems with more than 1 cpu core:"
   echo "  $0 -r fqdn,ipv4 \( distr == debian \) and \( cpu_cores gt 1 \)"
   echo "Show hostname of all systems that have bluez installed as package:"
   echo "  $0 -r hostname packages contains bluez"
   exit 1
}

main() {
   sanitycheck

   declare -a ex
   pos=0
   reporting=()
   DEBUG=0
   output=basic
   while getopts :hjH:t:T:r:x opt; do
      case $opt in
      h) usage ;;
      H) hosts+=( ${OPTARG//,/ } ) ;;
      j) output=json ;;
      x) DEBUG=1 ;;
      r) reporting=( ${OPTARG//,/ } ) ;;
      t) tags+=( ${OPTARG//,/ } ); tagall=0 ;;
      T) tags+=( ${OPTARG//,/ } ); tagall=1 ;;
      \?) echo "Unknown option: -$OPTARG"
          usage
      ;;
      :) echo "Option -$OPTARG requires argument"
         usage
      ;;
      esac
   done
   shift $((OPTIND-1))

   test "${#reporting[@]}" -eq 0 && { echo "No reporting output defined."; exit 1; }

   if test "${#hosts[@]}" -eq 0; then
      if test "${#tags[@]}" -eq 0; then
         hosts=( $( cdist inventory list -H ) )
      else
         if test "$tagall" = "1"; then
            hosts=( $( cdist inventory list -H -a -t "${tags[@]}" ) )
         else
            hosts=( $( cdist inventory list -H -t "${tags[@]}" ) )
         fi
      fi
   fi

   if test "$#" -eq 0; then
      reshosts=( "${hosts[@]}" )
   else
      reshosts=()
      for host in "${hosts[@]}"; do
         ex=( "$@" )  
         pos=0
         getexpr "$host"
         test "$?" -eq 1 && reshosts+=( "$host" )
      done
   fi

   for host in "${reshosts[@]}"; do
      result=()
      for report in "${reporting[@]}"; do
         result+=( "$(procexplore "$host" "$report")" )
      done
      echo "${result[@]}"
   done
}

main "$@"
