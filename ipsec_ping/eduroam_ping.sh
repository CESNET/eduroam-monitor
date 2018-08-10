#!/bin/bash

# ===========================================================================
# 2006.05.25 ....
# 2007.09.11 kontrola offline rezimu
#            vymena pingu ktery umi nastavit zdrojovou adresu
# ===========================================================================
DESC="eduroam ping daemon"
PIDFILE="/var/run/eduroam_ping.pid"

# Define LSB log_* functions.
# Depend on lsb-base (>= 3.0-6) to ensure that this file is present.
. /lib/lsb/init-functions
# ===========================================================================
function main()
{
  while true
  do
    run
    sleep 15
  done
}
# ===========================================================================
function run()
{
  ips=$(setkey -DP | grep ^[0-9] | cut -d " " -f 1,2 | sed 's/\[any\]//g' | tr " " "\n" | sort | uniq)
  while read IP
  do
    if [[ $(ip a | grep "inet $IP") != "" ]]
    then
      # Tohle je nase IPcko "X";
      false
    else
      create_file
  fi
  done <<< $ips
}
# ===========================================================================
function create_file()
{
  TMPF=`mktemp /tmp/eduRoam-ping-$IP-XXXXXX`

  echo "#!/bin/bash" >>$TMPF

  # Smazat sam sebe
  echo "rm $TMPF" >>$TMPF

  # Chvilicku pockat at vsechny pingy neodchazi v jeden okamzik, to by
  # mozna mohlo zahltit linku
  echo "sleep `perl -e 'print(rand(3));'`" >>$TMPF

  # Mrknout jesli tenhle host nahodou jeste neni opingavan jinym
  # procesem.  Bude se to poustet pomerne casto a opravdu nestojim o
  # to mit spustenych milion pingu najednou ;)
  echo "if [ -f /var/lock/eduRoam-ping-$IP ]
        then  
          PID=\`cat /var/lock/eduRoam-ping-$IP 2>/dev/null\`
          if [ -e /proc/\$PID ]
          then
            # Proces ktery si vytvoril zamek bezi - tak to zabalime my
            exit 0;
          fi     
        fi
        echo \$\$ > /var/lock/eduRoam-ping-$IP" >>$TMPF

  # Pingnout na protejsek
  echo "DATE=\`date +'%s'\`;" >>$TMPF
  echo "PING=\`ping -I {{ standby_ip }} -s 512 -c 3 -q $IP 2>/dev/null |grep transmitted\`">>$TMPF

  # Zapsat co jsme zjistili
  echo "logger -p local5.info -t eduRoamPing[\$\$] \"\$DATE: $IP: \$PING\"" >>$TMPF

  # Uklidit svuj zamek
  echo "rm /var/lock/eduRoam-ping-$IP" >>$TMPF

  chmod +x $TMPF && $TMPF &
}
# ========================================================================
# ========================================================================
# ========================================================================
# ========================================================================
# Function that starts the daemon/service
# ========================================================================
do_start()
{
  # Return
  #   0 if daemon has been started
  #   1 if daemon was already running
  #   2 if daemon could not be started
  if [[ -f $PIDFILE ]]
  then
    return 1;
  fi
  
  if [[ -f /etc/OFFLINE ]]
  then
    echo "skiped - now in OFFLINE mode.";
    return 2;
  fi
 
  main &
  echo $! >> $PIDFILE
  return 0 
}
# ========================================================================
# Function that stops the daemon/service
# ========================================================================
do_stop()
{
  # Return
  #   0 if daemon has been stopped
  #   1 if daemon was already stopped
  #   2 if daemon could not be stopped
  #   other if a failure occurred

  if [[ ! -f $PIDFILE ]]
  then
    return 1;
  fi
  
  local pid=$(cat $PIDFILE)

  kill -TERM $pid
  rm $PIDFILE

  # kontrola zda neni pid v aktivnich bezicich procesech
  if [[ $(ps aux | awk '{ print $2 }' | grep $pid) != "" ]]
  then
    return 2
  else
    return 0
  fi
}
# ========================================================================
# Function to get service status
# ========================================================================
status()
{
  # http://refspecs.linux-foundation.org/LSB_3.2.0/LSB-Core-generic/LSB-Core-generic/iniscrptact.html

  # kontrola zda neni pid v aktivnich bezicich procesech
  if [[ $(ps aux | grep "$0") != "" ]]
  then # program nebezi

    if [[ -f $PIDFILE ]]
    then # pidfile existuje
      return 1
    fi
  
    return 3

  else # program bezi

    if [[ -f $PIDFILE ]]
    then # pidfile existuje
      return 0
    fi
  fi
}
# ========================================================================
# ========================================================================

case "$1" in
  start)
	log_daemon_msg "Starting $DESC"
	do_start
	log_end_msg $?
	;;
  stop)
	log_daemon_msg "Stopping $DESC"
	do_stop
	log_end_msg $?
	;;
  status)
	status
	log_end_msg $?
	;;
  *)
	echo "Usage: $0 {start|stop|status}" >&2
	exit 3
	;;
esac

