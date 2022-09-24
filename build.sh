#!/bin/sh

cd "$(dirname $0)"

[ -e build-stamp ] || \
	touch -d '@0' build-stamp

if [ -n "$(find . -type f -anewer build-stamp)" ]; then
	debuild -tc
	: > build-stamp
else
	echo "Nothing to do" >&2
fi
