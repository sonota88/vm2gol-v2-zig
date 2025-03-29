素朴な自作言語のコンパイラをZigに移植した - memo88  
https://memo88.hatenablog.com/entry/2021/01/07/235019

```sh
git clone --recursive https://github.com/sonota88/vm2gol-v2-zig.git
cd vm2gol-v2-zig
./docker.sh build
./test.sh all
```

```sh
./docker.sh run zig version
  # 0.14.0

LANG=C wc -l {lexer,parser,codegen}.zig lib/{types,utils,json}.zig
  #  189 lexer.zig
  #  630 parser.zig
  #  552 codegen.zig
  #  209 lib/types.zig
  #  210 lib/utils.zig
  #  144 lib/json.zig
  # 1934 total
```
