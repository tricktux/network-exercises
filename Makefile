
.PHONY: git_clean cmake_clean debug release sanitize ci-ubuntu

all: debug

format:
	@find source/ -name '*.cpp' -o -name '*.hpp' -o -name '*.c' -o -name '*.h' | \
		xargs clang-format -i -style=file
	@find test/ -name '*.cpp' -o -name '*.hpp' -o -name '*.c' -o -name '*.h' | \
		xargs clang-format -i -style=file

clean:
	rm -rf build

git_clean:
	git clean -fxd

debug:
	cmake --preset=dev
	cmake --build --preset=dev
	ln -sf build/dev/compile_commands.json .

release:
	cmake --preset=release
	cmake --build --preset=release
	ln -sf build/release/compile_commands.json .

zig_release:
	cmake --preset=zig-release
	cmake --build --preset=zig-release
	ln -sf build/zig-release/compile_commands.json .

sanitize:
	cmake --preset=sanitize
	cmake --build --preset=sanitize
	ln -sf build/sanitize/compile_commands.json .

ci-ubuntu:
	cmake --preset=ci-linux-local
	cmake --build --preset=ci-linux-local
	ln -sf build/ci-linux-local/compile_commands.json .
