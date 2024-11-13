
.PHONY: git_clean cmake_clean debug release sanitize ci-ubuntu

all: debug

cmake_clean:
	rm -rf build

git_clean:
	git clean -fxd

debug:
	cmake --preset=dev
	cmake --build --preset=dev
	ln -sf build/dev/compile_commands.json .

debug:
	cmake --preset=release
	cmake --build --preset=release
	ln -sf build/dev/compile_commands.json .

sanitize:
	cmake --preset=sanitize
	cmake --build --preset=sanitize
	ln -sf build/dev/compile_commands.json .

ci-ubuntu:
	cmake --preset=ci-linux-local
	cmake --build --preset=ci-linux-local
	ln -sf build/dev/compile_commands.json .
