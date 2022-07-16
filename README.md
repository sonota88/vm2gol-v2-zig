素朴な自作言語のコンパイラをZigに移植した - memo88  
https://memo88.hatenablog.com/entry/2021/01/07/235019

```sh
git clone --recursive https://github.com/sonota88/vm2gol-v2-zig.git
cd vm2gol-v2-zig
./docker_build.sh
./test.sh all
```

```sh
./docker_run.sh zig version
  # 0.9.0

LANG=C wc -l vg{lexer,parser,codegen}.zig lib/{types,utils,json}.zig
  #  189 vglexer.zig
  #  630 vgparser.zig
  #  552 vgcodegen.zig
  #  209 lib/types.zig
  #  244 lib/utils.zig
  #  144 lib/json.zig
  # 1968 total
```
