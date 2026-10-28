# add-u64-perf-flux

Measures the cost of adding two `u64` values in Flux, compiled with `idkc`
(Flux Compiler "Dangling Ditto" v2.0.8, source at `../IDEKA`).

## Result

On this machine, a `u64 + u64` in Flux costs **1 CPU cycle** on the dependent
path (about 0.247 ns at the ~4.05 GHz the core ran at), and the core sustains
**3.2 adds per cycle** when the adds are independent. The Flux build is
instruction-for-instruction equivalent to clang -O2 C and measures identically.

| kernel (1e9 iterations)   | Flux ns/add | Flux cycles/iter | C (clang -O2) ns/add |
|---------------------------|-------------|------------------|----------------------|
| empty loop (overhead)     | 0.247       | 1.0              | 0.247                |
| dep, 1 accumulator        | 0.247       | 1.0              | 0.247                |
| indep, 8 accumulators     | 0.077       | 2.5 (8 adds)     | 0.077                |

`perf stat` over the whole Flux run: 4.62 G cycles for 4.6 G loop iterations
(0.1 G warm-up + 1 G empty + 1 G dep + 1 G indep at 2.5 cycles), i.e. the
cycle counts above are exact, not inferred from the clock speed. The C
reference reports the same 4.62 G cycles.

Machine: AMD Ryzen 9 3900X (Zen 2), governor `powersave`, boost reached
4.0 to 4.45 GHz during runs. The ns figures move with boost; the cycle figures
do not.

## What is being measured

`add_u64.fx` has three kernels, each a counted loop over `n` iterations:

- `bench_empty`: counter add, compare, branch. Loop overhead alone.
- `bench_dep`: `acc = acc + b`. Every add waits for the previous one, so this
  is the add **latency**. On x86-64 that is 1 cycle, and the loop overhead is
  hidden underneath it.
- `bench_indep`: eight accumulators, each with its own addend, xor-combined at
  the end. This is add **throughput**. Per iteration the loop issues 8 adds +
  `inc` + `cmp` = 10 ALU ops. Zen 2 has 4 integer ALUs, so the floor is 2.5
  cycles per iteration, which is exactly what is measured.

The operands come from the low bits of the monotonic clock so nothing can be
folded at compile time, and the results are printed so they are not dead.

Generated code for `bench_dep` (from `objdump` on `build/add_u64/add_u64.o`):

```
add    rax,rsi
inc    rcx
cmp    rcx,rdx
jb     <loop>
```

Generated loop body for `bench_indep` (three of the eleven values were
spilled to the stack by register pressure; the loads hit L1 and do not change
the 2.5 cycle floor):

```
add    r8,QWORD PTR [rsp-0x10]
add    rdx,QWORD PTR [rsp-0x18]
add    rdi,rsi
add    r9,r10
add    rax,rbx
add    r12,r14
add    r15,r13
add    r11,rbp
inc    rcx
cmp    rcx,QWORD PTR [rsp-0x8]
jb     <loop>
```

## Build and run

```
idkc add_u64.fx
./build/add_u64/add_u64             # 1e9 iterations
./build/add_u64/add_u64 200000000   # custom iteration count
```

Sample output:

```
iterations: 1000000000
empty loop     : 246 ms, 0.2464 ns/add, 4.058 G adds/s  (result 1000000000)
dep   (1 acc)  : 247 ms, 0.2471 ns/add, 4.047 G adds/s  (result 163000046260)
indep (8 acc)  : 616 ms, 0.0771 ns/add, 12.970 G adds/s  (result 409657511936)
```

## Notes on the Flux toolchain that affected the measurement

- `idkc` emits LLVM IR, runs `opt -passes=mem2reg,sroa,dce,simplifycfg`, then
  `llc -O3`, then `ld`. There is no middle-end loop pipeline (no indvars,
  LICM, unrolling or vectorization). Running the emitted `.ll` through a full
  `opt -O3` folds `bench_dep` into `a + n*b` with no loop at all, which is why
  the C reference needs `asm volatile` barriers and the Flux version does not.
- The LLVM backend still reassociates: summing the eight accumulators with `+`
  turned the loop into a single `add` of `8*b`, and giving all eight chains
  the same addend turned it into one chain plus `lea` fix-ups. Distinct
  addends plus an `xor` combine were needed to keep eight real adds.
- In Flux `^` is exponentiation. XOR is the `xor` keyword (or `` `^| ``).
  Using `^` on `u64` made codegen silently skip the function ("Codegen
  incomplete: 1 function(s) skipped") and leave the previous binary in place.
