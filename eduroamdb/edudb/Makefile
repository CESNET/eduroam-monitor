#!/usr/bin/make

VERSION=$(shell cat ChangeLog  |grep Version | sed "s/.*: *//" | head -1)
DISTRIBUTION=/tmp/edudb-${VERSION}.tar.bz2
FILES=README ChangeLog COPYING bin/get_institution.pl cfg-example/get_institution.cfg xsd/ver17042008/institution.xsd
PUB_TARGET=semik@wiki.eduroam.cz:/var/www/non-ssl/edudb/
PUB_FILES=${DISTRIBUTION} README ChangeLog

${DISTRIBUTION}: ${FILES}
	(mkdir /tmp/edudb-${VERSION}; \
	 tar jcf ${DISTRIBUTION} ${FILES}; \
	 cd /tmp/edudb-${VERSION}; \
	 tar jxf ${DISTRIBUTION}; \
	 find -type f -exec chmod 644 {} \; ; \
	 chmod 755 bin/*.pl ; \
	 find -type d -exec chmod 755 {} \; ; \
	 cd ..; \
	 pwd ;\
	 tar -j -c --owner=root --group=staff -f ${DISTRIBUTION} edudb-${VERSION})

tar: ${DISTRIBUTION}

publish: tar
	scp ${PUB_FILES} ${PUB_TARGET}

all: tar publish
