#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <math.h>
#include <time.h>
static volatile uint32_t inputs[10] = {
    0, 1, 15, 16, 4095, 65535,
    123456789, 987654321, 4294836225u, 4294967295u
};
static uint32_t golden_isqrt(uint32_t x)
{
    return (uint32_t)floor(sqrt((double)x));
}
static double timestamp_us(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e6 + (double)ts.tv_nsec / 1e3;
}
static int hand_check(uint32_t x, uint32_t r)
{
    uint64_t r_sq = (uint64_t)r * r;
    uint64_t r_next = (uint64_t)r + 1;
    uint64_t r_next_sq = r_next * r_next;
    return (r_sq <= x) && (x < r_next_sq);
}
static double time_n_calls(long reps)
{
    double start = timestamp_us();
    for (long i = 0; i < reps; i++) {
        for (int j = 0; j < 10; j++) {
            volatile uint32_t val = golden_isqrt(inputs[j]);
            (void)val;
        }
    }
    double end = timestamp_us();
    return ((end - start) * 1e3) / (reps * 10.0);
}
int main(void)
{
    printf("Golden measure output table (hand-checked):\n");
    int all_passed = 1;
    for (int i = 0; i < 10; i++) {
        uint32_t x = inputs[i];
        uint32_t r = golden_isqrt(x);
        int passed = hand_check(x, r);
        if (!passed) all_passed = 0;

        uint64_t r_sq = (uint64_t)r * r;
        uint64_t r_next_sq = (uint64_t)(r + 1) * (r + 1);
        printf("x = %10" PRIu32 "  isqrt = %5" PRIu32 "    check: %12" PRIu64 " <= %10" PRIu32 " < %12" PRIu64 "   %s\n",
               x, r, r_sq, x, r_next_sq, passed ? "PASS" : "FAIL");
    }
    printf("All hand-checks: %s\n\n", all_passed ? "PASS" : "FAIL");

    uint32_t hx = inputs[7];
    uint32_t hr = golden_isqrt(hx);
    printf("Full hand-check for x = %" PRIu32 ":\n", hx);
    printf("isqrt(x) = %" PRIu32 "\n", hr);
    printf("r^2 = %" PRIu64 " <= x = %" PRIu32 "\n", (uint64_t)hr * hr, hx);
    printf("(r+1)^2 = %" PRIu64 " > x = %" PRIu32 "\n\n", (uint64_t)(hr + 1) * (hr + 1), hx);

    long reps1 = 1000000L;
    long reps2 = 5000000L;
    printf("Repetitions per run: Run 1 = %ld, Run 2 = %ld\n", reps1, reps2);
    double t1 = time_n_calls(reps1);
    double t2 = time_n_calls(reps2);
    printf("Timing (two runs with different repetition counts):\n");
    printf("Run 1 (reps = %8ld): %.3f ns/call\n", reps1, t1);
    printf("Run 2 (reps = %8ld): %.3f ns/call\n", reps2, t2);
    printf("Mean: %.3f ns, Spread: %.3f ns\n", (t1 + t2) / 2.0, fabs(t1 - t2));
    return 0;
}