.PHONY: deps sponsors compile test

default: deps sponsors compile test

deps:
	scripts/dep.sh Olical aniseed origin/develop
	scripts/dep.sh Olical bencode origin/master

sponsors:
	echo "[ ;; Generated by: make sponsors" > fnl/conjure/sponsors.fnl
	curl https://github.com/sponsors/Olical \
		| grep '"avatar avatar-user"' \
		| sed 's/.*alt="@\(.*\)".*/"\1"/' \
		| tail -n +2 \
		| sort \
		>> fnl/conjure/sponsors.fnl
	echo "]" >> fnl/conjure/sponsors.fnl

compile:
	rm -rf lua
	deps/aniseed/scripts/compile.sh
	deps/aniseed/scripts/embed.sh aniseed conjure
	cp deps/bencode/bencode.lua lua/conjure/bencode.lua

test:
	rm -rf test/lua
	deps/aniseed/scripts/test.sh
