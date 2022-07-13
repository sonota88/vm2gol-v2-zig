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
  # 0.7.1

LANG=C wc -l vg{lexer,parser,codegen}.zig lib/{types,utils}.zig
  #  204 vglexer.zig
  #  670 vgparser.zig
  #  564 vgcodegen.zig
  #  211 lib/types.zig
  #  244 lib/utils.zig
  # 1893 total
```
