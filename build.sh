#!/bin/sh

cd "$(dirname $0)"

[ -e build-stamp ] || \
	touch -d '@0' build-stamp

changed=
if [ -n "${changed:="$(find . -type f -cnewer build-stamp)"}" ]; then
	printf '%s\n' "Changed files:" ${changed} ""
	debuild -tc
	: > build-stamp
else
	echo "Nothing to do" >&2
fi
