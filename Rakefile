require "rake/clean"

dep_list = [
  {
    target: "bin/test_json",
    deps: [
      "test_json.zig"
    ]
  },
  {
    target: "bin/lexer",
    deps: [
      "lexer.zig"
    ]
  },
  {
    target: "bin/parser",
    deps: [
      "parser.zig"
    ]
  },
  {
    target: "bin/codegen",
    deps: [
      "codegen.zig"
    ]
  },
]

all_targets = dep_list.map { |dep| dep[:target] }

desc "build"
task :build => all_targets

CLEAN.include(all_targets)
CLEAN.include("*.o")

dep_list.each { |dep|
  file dep[:target] => dep[:deps] do
    f_main = dep[:deps][0]
    bname = File.basename(f_main, ".zig")
    sh "zig build-exe -freference-trace #{f_main}"
    sh "mv #{bname} bin/"
  end
}
