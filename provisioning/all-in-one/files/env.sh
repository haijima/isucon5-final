#!/bin/sh
export PATH=/usr/local/bin:/home/isucon/.local/ruby/bin:/home/isucon/.local/node/bin:/home/isucon/.local/python3/bin:/home/isucon/.local/perl/bin:/home/isucon/.local/php/bin:/home/isucon/.local/php/sbin:/home/isucon/.local/go/bin:/home/isucon/.local/scala/bin:$PATH
export GOPATH=/home/isucon/gocode
export _JAVA_OPTIONS="-Dfile.encoding=UTF-8"

exec $*
