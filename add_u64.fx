// add_u64.fx - measure the cost of adding two u64 values in Flux.
//
// Build:  idkc add_u64.fx
// Run:    ./build/add_u64/add_u64 [iterations]
//
// Two kernels, both adding u64 + u64 in a counted loop:
//   dep   : one accumulator, acc = acc + b. Every add depends on the previous
//           one, so this is bound by add LATENCY (1 cycle on x86-64).
//   indep : four independent accumulators, so the core can overlap the adds.
//           This is bound by add THROUGHPUT and by the loop's own counter adds.
//
// The operands are derived from the clock so the compiler cannot fold the
// loop at compile time, and the results are printed so they are not dead.

#import <standard.fx>;

using standard::io::console,
      standard::time;

def bench_dep(u64 a, u64 b, u64 n) -> u64
{
    u64 acc = a;
    for (u64 i = 0; i < n; i++)
    {
        acc = acc + b;
    };
    return acc;
};

// Eight accumulators, each with its own addend, combined with xor at the end.
// LLVM is aggressive here: summing the results with + lets it reassociate the
// loop into one add of (b0+..+b7) per iteration, and giving every chain the
// same addend lets it compute one chain and derive the rest with lea. Distinct
// addends and an xor combine keep eight real adds in the loop body.
def bench_indep(u64 a, u64 b, u64 c, u64 n) -> u64
{
    u64 b0 = b,                 b1 = b + c,
        b2 = b + c * (u64)2,    b3 = b + c * (u64)3,
        b4 = b + c * (u64)4,    b5 = b + c * (u64)5,
        b6 = b + c * (u64)6,    b7 = b + c * (u64)7;
    u64 acc0 = a,     acc1 = a + 1, acc2 = a + 2, acc3 = a + 3,
        acc4 = a + 4, acc5 = a + 5, acc6 = a + 6, acc7 = a + 7;
    for (u64 i = 0; i < n; i++)
    {
        acc0 = acc0 + b0;
        acc1 = acc1 + b1;
        acc2 = acc2 + b2;
        acc3 = acc3 + b3;
        acc4 = acc4 + b4;
        acc5 = acc5 + b5;
        acc6 = acc6 + b6;
        acc7 = acc7 + b7;
    };
    return acc0 xor acc1 xor acc2 xor acc3 xor acc4 xor acc5 xor acc6 xor acc7;
};

// Empty counted loop: the loop overhead alone (counter add + compare + branch).
def bench_empty(u64 n) -> u64
{
    u64 i = 0;
    for (i = 0; i < n; i++)
    {
    };
    return i;
};

def report(noopstr name, u64 adds, i64 ns, u64 result) -> void
{
    double ns_per_add = (double)ns / (double)adds;
    double gadds_per_s = (double)adds / (double)ns;   // adds per ns == G adds / s

    print(name);
    print(": ");
    print(ns_to_ms(ns));
    print(" ms, ");
    print(ns_per_add, 4);
    print(" ns/add, ");
    print(gadds_per_s, 3);
    print(" G adds/s  (result ");
    print(result);
    print(")\n");
    return;
};

def run(u64 n) -> int
{
    i64 t0, t1;
    u64 r;

    // Non-constant operands (low clock bits), b forced odd and non-zero.
    u64 a = (u64)time_now() & (u64)0xFFFF;
    u64 b = ((u64)time_now() >> (u64)3) & (u64)0xFF | (u64)1;
    u64 c = ((u64)time_now() >> (u64)5) & (u64)0x3F | (u64)1;

    print("iterations: ");
    print(n);
    print("\n");

    // Warm-up so the core is at speed before timing.
    r = bench_dep(a, b, n / (u64)10);

    t0 = time_now();
    r = bench_empty(n);
    t1 = time_now();
    report("empty loop     ", n, t1 - t0, r);

    t0 = time_now();
    r = bench_dep(a, b, n);
    t1 = time_now();
    report("dep   (1 acc)  ", n, t1 - t0, r);

    t0 = time_now();
    r = bench_indep(a, b, c, n);
    t1 = time_now();
    report("indep (8 acc)  ", n * (u64)8, t1 - t0, r);

    return 0;
};

def main() -> int
{
    return run((u64)1000000000);
};

def main(int argc, byte** argv) -> int
{
    u64 n = 0;
    byte* s = argv[1];
    int k = 0;
    while (s[k] >= (byte)48 & s[k] <= (byte)57)
    {
        n = n * (u64)10 + (u64)(s[k] - (byte)48);
        k++;
    };
    if (n == (u64)0) { n = (u64)1000000000; };
    return run(n);
};
