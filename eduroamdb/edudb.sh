#!/bin/bash

CFG=~/cfg/edudb.cfg
TMPF=`mktemp /tmp/edudb.sh-XXXXXX`

export PERLLIB=~/edudb/bin

#(cat $CFG-header ;
# ~/edudb/bin/buildConfig.pl --CFGFilename ~/cfg/edudb-buildConfig.cfg | cstocs utf8 il2 ) > $TMPF
(cat $CFG-header ;
 ~/edudb/bin/buildConfig.pl --CFGFilename ~/cfg/edudb-buildConfig.cfg ) > $TMPF

OLD_MD5=`md5sum $CFG | sed "s/ .*$//" 2>/dev/null`
NEW_MD5=`md5sum $TMPF | sed "s/ .*$//" 2>/dev/null`

if [ "x$OLD_MD5" != "x$NEW_MD5" ]
then
  # md5sum of files is different
  CNT=`grep '\[' $TMPF | wc -l`
  if [ $CNT  -gt 5 ]
  then
    DATE=`date +"%Y%m%d-%H%M%S"`
    if [ -f $CFG ]
    then 
      mv $CFG $CFG-$DATE
    fi
    mv $TMPF $CFG
  else 
    logger "Builded config file $TMPF is suspiciously small"
    exit 1;
  fi
else
    # config se nezmenil
    rm $TMPF
    if find ~/www/general -name institution.xml -type f -mmin +360 |grep institution >/dev/null 2>&1
    then
	# ale uz je to dost dlouho takze stejne pregenerujem, protoze
	# mohly prifrcet nejaky novy data
	true
    else
	exit 1;
    fi
fi

# Try to get fresh institution.xml from edudb
~/edudb/bin/get_institution2.pl --CFG ~/cfg/edudb.cfg

# Build KML
~/edudb/bin/convert_institution.pl --CFG ~/cfg/edudb.cfg --OUT_MODULE kml \
    --OUTFILE ~/www/pokryti/eduroam-cs_CZ.kml --LANG=cs --OUT_DESC=org_name --TIDY_XML=1 2>/dev/null
~/edudb/bin/convert_institution.pl --CFG ~/cfg/edudb.cfg --OUT_MODULE kml \
    --OUTFILE ~/www/pokryti/eduroam-en_CZ.kml --LANG=en --OUT_DESC=org_name --TIDY_XML=1 2>/dev/null

# Build DokuWiki
~/edudb/bin/convert_institution.pl --CFG ~/cfg/edudb.cfg --OUT_MODULE dokuwiki \
    -OUTFILE ~/www/pokryti/eduroam-cs_CZ.dokuwiki --LANG=cs --OUT_DESC=acronymunit,acronym --PRINT_EMPTY_LOCNAME=1 2>/dev/null
~/edudb/bin/convert_institution.pl --CFG ~/cfg/edudb.cfg --OUT_MODULE dokuwiki \
    -OUTFILE ~/www/pokryti/eduroam-en_CZ.dokuwiki --LANG=en --OUT_DESC=acronymunit,acronym --PRINT_EMPTY_LOCNAME=1 2>/dev/null

# Build GPX
~/edudb/bin/convert_institution.pl --CFG ~/cfg/edudb.cfg --OUT_MODULE gpx \
    --OUTFILE ~/www/pokryti/eduroam-cs_CZ.gpx --LANG=cs --OUT_DESC=acronym --TIDY_XML=1 2>/dev/null
~/edudb/bin/convert_institution.pl --CFG ~/cfg/edudb.cfg --OUT_MODULE gpx \
    --OUTFILE ~/www/pokryti/eduroam-en_CZ.gpx --LANG=en --OUT_DESC=acronym --TIDY_XML=1 2>/dev/null
