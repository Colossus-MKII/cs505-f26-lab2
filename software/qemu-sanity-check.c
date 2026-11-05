#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <assert.h>
#include <string.h>

// assembly routines
extern uint32_t get_nth_fibonacci(uint32_t a);
extern uint32_t popcount(uint32_t a);
extern uint32_t gcd(uint32_t a, uint32_t b);
extern uint32_t crc32(const uint8_t *data, uint32_t length);
extern uint32_t histogram_benchmark(void);
extern uint32_t histogram_bins[8];
extern uint32_t sieve127_benchmark(void);
extern uint8_t sieve127_flags[64];
extern uint32_t sqrt_benchmark(void);

// Compile and link with the assembly routines tested below.
int main(int argc, char **argv)
{
    // test get_nth_fibonacci
    assert(get_nth_fibonacci(0) == 0);
    assert(get_nth_fibonacci(1) == 1);
    assert(get_nth_fibonacci(2) == 1);
    assert(get_nth_fibonacci(5) == 5);
    assert(get_nth_fibonacci(10) == 55);
    assert(get_nth_fibonacci(20) == 6765);
    assert(get_nth_fibonacci(46) == 1836311903);
    assert(get_nth_fibonacci(47) == 2971215073 );

    // test popcount
    assert(popcount(0) == 0);
    assert(popcount(1) == 1);
    assert(popcount(0x55555555) == 16);
    assert(popcount(0xaaaaaaaa) == 16);
    assert(popcount(0x80000000) == 1);
    assert(popcount(0xffffffff) == 32);

    // test gcd
    assert(gcd(0, 0) == 0);
    assert(gcd(5, 0) == 5);
    assert(gcd(1, 1) == 1);
    assert(gcd(8, 9) == 1);
    assert(gcd(12, 18) == 6);
    assert(gcd(4294967295, 1) == 1);
    assert(gcd(4294967295, 4294967295) == 4294967295);

    // test crc32
    const uint8_t crc_input[] = "123456789";
    assert(crc32(crc_input, 0) == 0);
    assert(crc32(crc_input, 1) == 0x83dcefb7);
    assert(crc32(crc_input, 9) == 0xcbf43926);

    // Histogram requires cleared counters for each invocation.
    const uint32_t expected_bins[] = {82, 98, 76, 89, 90, 91, 89, 89};
    for (unsigned run = 0; run < 2; ++run) {
        memset(histogram_bins, 0, sizeof(histogram_bins));
        assert(histogram_benchmark() == 0);
        for (unsigned i = 0; i < 8; ++i)
            assert(histogram_bins[i] == expected_bins[i]);
    }

    // The sieve initializes its own 63 flags; the final byte is padding.
    memset(sieve127_flags, 0xa5, sizeof(sieve127_flags));
    assert(sieve127_benchmark() == 0); // 31 primes through 127.
    assert(sieve127_flags[0] == 1);   // 3 is prime.
    assert(sieve127_flags[3] == 0);   // 9 is composite.
    assert(sieve127_flags[47] == 1);  // 97 is prime.
    assert(sieve127_flags[59] == 0);  // 121 is composite.
    assert(sieve127_flags[62] == 1);  // 127 is prime.
    assert(sieve127_flags[63] == 0xa5);
    assert(sieve127_benchmark() == 0); // Safe to run again without clearing.

    // The 128 integer square roots must sum to 248498.
    assert(sqrt_benchmark() == 0);

    printf("[INFO] no assertion failures!\n");
    return EXIT_SUCCESS;
}
