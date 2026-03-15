/**
 * Standalone Cross-Platform Memory Read Test
 *
 * This program validates the safe memory reading approach used by the
 * _readNativeMemory RPC on each platform. It allocates known data,
 * reads it back using the platform-specific safe-read syscall, and
 * verifies correctness. It also tests error handling for invalid
 * addresses.
 *
 * Build:
 *   Linux:   gcc -o test_memory_read test_memory_read.c
 *   macOS:   clang -o test_memory_read test_memory_read.c
 *   Windows: cl test_memory_read.c /Fe:test_memory_read.exe
 *
 * The CI workflow compiles and runs this on all three platforms.
 */

/* Enable process_vm_readv on Linux (it's a GNU extension) */
#if defined(__linux__) || defined(__ANDROID__)
#define _GNU_SOURCE
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#if defined(__linux__) || defined(__ANDROID__)
#include <sys/uio.h>
#include <unistd.h>
#define PLATFORM_NAME "Linux"
#elif defined(__APPLE__)
#include <mach/mach.h>
#define PLATFORM_NAME "macOS"
#elif defined(_WIN32)
#include <windows.h>
#include <BaseTsd.h>
typedef SSIZE_T ssize_t;  /* MSVC doesn't provide POSIX ssize_t */
#define PLATFORM_NAME "Windows"
#else
#error "Unsupported platform"
#endif

/**
 * Safe memory read — mirrors the implementation in service.cc.
 * Returns bytes read, or -1 on failure.
 */
static ssize_t safe_read_memory(
    const void* address, void* buffer, size_t count) {

#if defined(__linux__) || defined(__ANDROID__)
    struct iovec local_iov = { buffer, count };
    struct iovec remote_iov = { (void*)address, count };
    return process_vm_readv(getpid(), &local_iov, 1, &remote_iov, 1, 0);

#elif defined(__APPLE__)
    /* vm_read_overwrite is in <mach/mach.h>; mach_vm_read_overwrite
     * requires <mach/mach_vm.h> which may not be found by all toolchains.
     * On 64-bit macOS, vm_address_t == mach_vm_address_t (both uint64_t). */
    vm_size_t bytes_read = 0;
    kern_return_t kr = vm_read_overwrite(
        mach_task_self(),
        (vm_address_t)address,
        (vm_size_t)count,
        (vm_address_t)buffer,
        &bytes_read);
    return (kr == KERN_SUCCESS) ? (ssize_t)bytes_read : -1;

#elif defined(_WIN32)
    SIZE_T bytes_read = 0;
    BOOL ok = ReadProcessMemory(
        GetCurrentProcess(),
        (LPCVOID)address,
        buffer,
        (SIZE_T)count,
        &bytes_read);
    return ok ? (ssize_t)bytes_read : -1;
#endif
}

/* ── Test helpers ── */

static int tests_passed = 0;
static int tests_failed = 0;

#define ASSERT_EQ(a, b, msg) do { \
    if ((a) == (b)) { \
        printf("  ✓ PASS: %s\n", msg); \
        tests_passed++; \
    } else { \
        printf("  ✗ FAIL: %s (expected %lld, got %lld)\n", \
               msg, (long long)(b), (long long)(a)); \
        tests_failed++; \
    } \
} while(0)

#define ASSERT_TRUE(cond, msg) do { \
    if (cond) { \
        printf("  ✓ PASS: %s\n", msg); \
        tests_passed++; \
    } else { \
        printf("  ✗ FAIL: %s\n", msg); \
        tests_failed++; \
    } \
} while(0)

/* ── Tests ── */

void test_read_valid_memory(void) {
    printf("\nTest: Read valid memory\n");

    /* Simulate a struct layout: { int32_t id; float value; int64_t ts; } */
    uint8_t data[16];
    memset(data, 0, sizeof(data));

    int32_t id = 42;
    float value = 3.14f;
    int64_t timestamp = 1234567890LL;

    memcpy(data + 0, &id, 4);         /* offset 0: Int32 */
    memcpy(data + 4, &value, 4);      /* offset 4: Float */
    memcpy(data + 8, &timestamp, 8);  /* offset 8: Int64 */

    /* Read it back using safe_read_memory */
    uint8_t readback[16];
    memset(readback, 0xFF, sizeof(readback));
    ssize_t bytes = safe_read_memory(data, readback, sizeof(data));

    ASSERT_EQ(bytes, 16, "Read 16 bytes from valid address");
    ASSERT_EQ(memcmp(data, readback, 16), 0, "Read data matches original");

    /* Verify individual field values */
    int32_t read_id;
    float read_value;
    int64_t read_ts;
    memcpy(&read_id, readback + 0, 4);
    memcpy(&read_value, readback + 4, 4);
    memcpy(&read_ts, readback + 8, 8);

    ASSERT_EQ(read_id, 42, "id field = 42");
    ASSERT_TRUE(read_value > 3.13f && read_value < 3.15f,
                "value field ≈ 3.14");
    ASSERT_EQ(read_ts, 1234567890LL, "timestamp field = 1234567890");
}

void test_read_null_address(void) {
    printf("\nTest: Read from NULL address (should fail safely)\n");

    uint8_t buffer[16];
    ssize_t bytes = safe_read_memory(NULL, buffer, sizeof(buffer));

    /* Should return -1 (error), NOT crash */
    ASSERT_TRUE(bytes < 0, "NULL read returns error (no crash)");
}

void test_read_invalid_address(void) {
    printf("\nTest: Read from invalid address 0xDEADBEEF (should fail safely)\n");

    uint8_t buffer[16];
    ssize_t bytes = safe_read_memory(
        (const void*)(uintptr_t)0xDEADBEEF, buffer, sizeof(buffer));

    /* Should return -1 (error), NOT crash */
    ASSERT_TRUE(bytes < 0, "Invalid address read returns error (no crash)");
}

void test_read_heap_allocation(void) {
    printf("\nTest: Read from heap-allocated memory\n");

    /* Allocate and populate like a real FFI struct */
    uint8_t* heap = (uint8_t*)malloc(32);
    if (!heap) {
        printf("  ✗ FAIL: malloc failed\n");
        tests_failed++;
        return;
    }

    for (int i = 0; i < 32; i++) {
        heap[i] = (uint8_t)(i * 7 + 3);  /* Known pattern */
    }

    uint8_t readback[32];
    ssize_t bytes = safe_read_memory(heap, readback, 32);

    ASSERT_EQ(bytes, 32, "Read 32 bytes from heap allocation");
    ASSERT_EQ(memcmp(heap, readback, 32), 0, "Heap data matches");

    free(heap);
}

void test_read_after_free(void) {
    printf("\nTest: Read from freed memory (behavior is platform-dependent)\n");

    uint8_t* heap = (uint8_t*)malloc(16);
    if (!heap) {
        printf("  ✗ FAIL: malloc failed\n");
        tests_failed++;
        return;
    }

    memset(heap, 0xAA, 16);
    void* saved_addr = heap;
    free(heap);

    /* Read from the freed address — may succeed or fail,
     * but must NOT crash. This is the key safety property. */
    uint8_t readback[16];
    ssize_t bytes = safe_read_memory(saved_addr, readback, 16);

    /* The address might still be mapped (freed back to allocator, not OS),
     * so we can't assert bytes < 0. The key test is: no crash/SIGSEGV. */
    printf("  ✓ PASS: Freed memory read completed without crash "
           "(bytes=%zd)\n", bytes);
    tests_passed++;
}

void test_partial_read(void) {
    printf("\nTest: Read single byte\n");

    uint8_t source = 0x42;
    uint8_t dest = 0x00;
    ssize_t bytes = safe_read_memory(&source, &dest, 1);

    ASSERT_EQ(bytes, 1, "Read 1 byte");
    ASSERT_EQ(dest, 0x42, "Byte value matches");
}

/* ── Main ── */

int main(void) {
    printf("═══ Cross-Platform Safe Memory Read Test ═══\n");
    printf("Platform: %s\n", PLATFORM_NAME);
    printf("Pointer size: %zu bytes\n", sizeof(void*));

    test_read_valid_memory();
    test_read_null_address();
    test_read_invalid_address();
    test_read_heap_allocation();
    test_read_after_free();
    test_partial_read();

    printf("\n═══ Results: %d passed, %d failed ═══\n",
           tests_passed, tests_failed);

    return tests_failed > 0 ? 1 : 0;
}
