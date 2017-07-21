#!/bin/bash
# Java executable is required

cd "$(dirname "$0")"

if [ "$TNS_ADM" = "" ] ; then
    export DBCLI_ENCODING=UTF-8
fi

if [ "$TNS_ADM" = "" ] && [[ -n "$ORACLE_HOME" ]] ; then
    export TNS_ADM="$ORACLE_HOME/network/admin"
fi

if [[ -r ./data/init.conf ]]; then
    source ./data/init.conf
elif [[ -r ./data/init.cfg ]]; then
    source ./data/init.cfg
fi

# find executable java program
if [[ -n "$JRE_HOME" ]] && [[ -x "$JRE_HOME/bin/java" ]];  then
    _java="$JRE_HOME/bin/java"
elif type -p java &>/dev/null; then
    _java="`type -p java`"
elif [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then    
    _java="$JAVA_HOME/bin/java"
fi

# find executable java program
found=0
if [[ "$_java" ]]; then
    found=2
    version=$("$_java" -version 2>&1)
    ver=$(echo $version | awk -F '"' '/version/ {print $2}')
    
    if [[ "$ver" < "1.8" ]]; then
        found=1
    fi
    echo $version|grep "64-Bit" &>/dev/null ||  found=1
fi

chmod  777 ./jre_linux/bin/* &>/dev/null
if [[ $found < 2 ]]; then
    if [[ -x ./jre_linux/bin/java ]];  then
        _java=./jre_linux/bin/java
    else
        echo "Cannot find java 1.8 64-bit executable, exit."
        exit 1
    fi
fi

unset _JAVA_OPTIONS JAVA_BIN

JAVA_BIN="$(echo "$_java"|sed 's|/[^/]*$||')"
JAVA_HOME="$(echo "$JAVA_BIN"|sed 's|/[^/]*$||')"

if [[ -r "$JAVA_HOME/jre" ]]; then
    JAVA_BIN="$JAVA_HOME/jre/bin"
    JAVA_HOME="$JAVA_HOME/jre"
fi

export LD_LIBRARY_PATH="./lib/linux:$JAVA_HOME/lib/amd64/server:$JAVA_HOME/lib/amd64:$JAVA_HOME/bin"


./lib/linux/luajit ./lib/bootstrap.lua "$_java" $*

