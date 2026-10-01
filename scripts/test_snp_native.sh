#!/usr/bin/env bash
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
task_native_dir="$(mktemp -d /tmp/gene-snp-tests.XXXXXX)"
task_native_source="android/app/src/main/cpp/snp"

# Core C tests run with UBSan. JNI loads a plain library because macOS JVM
# library validation rejects the Apple sanitizer dynamic runtime.
clang -std=c99 -Wall -Wextra -Werror -pedantic -fsanitize=undefined \
  test/native/snp_engine_test.c "$task_native_source/snp_engine.c" -o "$task_native_dir/engine"
"$task_native_dir/engine"
clang -std=c99 -Wall -Wextra -Werror -pedantic -fsanitize=undefined \
  test/native/snp_locus_test.c "$task_native_source/snp_engine.c" -o "$task_native_dir/locus"
"$task_native_dir/locus"
clang -std=c99 -Wall -Wextra -Werror -Wconversion -pedantic -fsanitize=undefined \
  test/native/locus_genotype_model_test.c "$task_native_source/locus_genotype_model.c" -lm -o "$task_native_dir/locus-model"
"$task_native_dir/locus-model"
clang -std=c99 -Wall -Wextra -Werror -Wconversion -pedantic -fsanitize=undefined \
  -I"$task_native_source" test/native/genotype_model_test.c "$task_native_source/genotype_model.c" \
  -lm -o "$task_native_dir/model"
"$task_native_dir/model"
clang -std=c99 -Wall -Wextra -Werror -pedantic -fsanitize=undefined \
  test/native/snp_pipeline_test.c "$task_native_source/snp_engine.c" "$task_native_source/genotype_model.c" \
  -lm -o "$task_native_dir/pipeline"
"$task_native_dir/pipeline"

if [[ "$(uname -s)" == Darwin ]]; then
  task_jdk="$(/usr/libexec/java_home)"
  task_jni_os=darwin
  task_jni_lib="$task_native_dir/libsnp.dylib"
  task_jni_link=-dynamiclib
else
  task_jdk="${JAVA_HOME:?Set JAVA_HOME to run JNI integration tests}"
  task_jni_os=linux
  task_jni_lib="$task_native_dir/libsnp.so"
  task_jni_link=-shared
fi
clang -std=c99 -Wall -Wextra -Werror -fPIC -c "$task_native_source/snp_engine.c" -o "$task_native_dir/engine.o"
clang -std=c99 -Wall -Wextra -Werror -fPIC -c "$task_native_source/genotype_model.c" -o "$task_native_dir/model.o"
clang -std=c99 -Wall -Wextra -Werror -fPIC -c "$task_native_source/locus_genotype_model.c" -o "$task_native_dir/locus-model.o"
clang++ -std=c++17 -Wall -Wextra -Werror -fPIC "$task_jni_link" \
  -I"$task_jdk/include" -I"$task_jdk/include/$task_jni_os" "$task_native_source/snp_bridge.cpp" \
  "$task_native_dir/engine.o" "$task_native_dir/model.o" "$task_native_dir/locus-model.o" -o "$task_jni_lib"
"$task_jdk/bin/javac" -d "$task_native_dir" test/native/jni/com/example/geneapp/SnpComputePlugin.java
"$task_jdk/bin/java" --add-opens java.base/java.io=ALL-UNNAMED \
  -cp "$task_native_dir" com.example.geneapp.SnpComputePlugin "$task_jni_lib"
printf 'Native verification complete; diagnostic binaries: %s\n' "$task_native_dir"
