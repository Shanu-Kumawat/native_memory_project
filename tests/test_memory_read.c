/**
 * Comprehensive Cross-Platform Memory Read Test Suite
 *
 * Validates the safe memory reading approach used by the
 * _readNativeMemory RPC on each platform. Tests cover:
 *   - Valid reads (struct simulation, heap, stack, partial)
 *   - Error cases (NULL, invalid address, high address, guard page)
 *   - Edge cases (zero-length, misaligned, page boundary, large reads)
 *   - Robustness (freed memory, unmapped memory, concurrent access)
 *
 * Build:
 *   Linux:   gcc -pthread -o test_memory_read test_memory_read.c
 *   macOS:   clang -pthread -o test_memory_read test_memory_read.c
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
#include <sys/mman.h>
#include <pthread.h>
#define PLATFORM_NAME "Linux"
#elif defined(__APPLE__)
#include <mach/mach.h>
#include <sys/mman.h>
#include <pthread.h>
#include <unistd.h>
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

    if (count == 0) return 0;

#if defined(__linux__) || defined(__ANDROID__)
    struct iovec local_iov = { buffer, count };
    struct iovec remote_iov = { (void*)address, count };
    return process_vm_readv(getpid(), &local_iov, 1, &remote_iov, 1, 0);

#elif defined(__APPLE__)
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
        printf("  + PASS: %s\n", msg); \
        tests_passed++; \
    } else { \
        printf("  x FAIL: %s (expected %lld, got %lld)\n", \
               msg, (long long)(b), (long long)(a)); \
        tests_failed++; \
    } \
} while(0)

#define ASSERT_TRUE(cond, msg) do { \
    if (cond) { \
        printf("  + PASS: %s\n", msg); \
        tests_passed++; \
    } else { \
        printf("  x FAIL: %s\n", msg); \
        tests_failed++; \
    } \
} while(0)

/* ── Helper: get system page size ── */
static size_t get_page_size(void) {
#if defined(_WIN32)
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    return (size_t)si.dwPageSize;
#else
    return (size_t)sysconf(_SC_PAGESIZE);
#endif
}

/* ══════════════════════════════════════════════════════════════
 * EXISTING TESTS (kept from original suite)
 * ══════════════════════════════════════════════════════════════ */

void test_read_valid_memory(void) {
    printf("\nTest: Read valid memory (struct simulation)\n");

    uint8_t data[16];
    memset(data, 0, sizeof(data));

    int32_t id = 42;
    float value = 3.14f;
    int64_t timestamp = 1234567890LL;

    memcpy(data + 0, &id, 4);
    memcpy(data + 4, &value, 4);
    memcpy(data + 8, &timestamp, 8);

    uint8_t readback[16];
    memset(readback, 0xFF, sizeof(readback));
    ssize_t bytes = safe_read_memory(data, readback, sizeof(data));

    ASSERT_EQ(bytes, 16, "Read 16 bytes from valid address");
    ASSERT_EQ(memcmp(data, readback, 16), 0, "Read data matches original");

    int32_t read_id;
    float read_value;
    int64_t read_ts;
    memcpy(&read_id, readback + 0, 4);
    memcpy(&read_value, readback + 4, 4);
    memcpy(&read_ts, readback + 8, 8);

    ASSERT_EQ(read_id, 42, "id field = 42");
    ASSERT_TRUE(read_value > 3.13f && read_value < 3.15f,
                "value field ~ 3.14");
    ASSERT_EQ(read_ts, 1234567890LL, "timestamp field = 1234567890");
}

void test_read_null_address(void) {
    printf("\nTest: Read from NULL address (should fail safely)\n");

    uint8_t buffer[16];
    ssize_t bytes = safe_read_memory(NULL, buffer, sizeof(buffer));

    ASSERT_TRUE(bytes < 0, "NULL read returns error (no crash)");
}

void test_read_invalid_address(void) {
    printf("\nTest: Read from invalid address 0xDEADBEEF (should fail safely)\n");

    uint8_t buffer[16];
    ssize_t bytes = safe_read_memory(
        (const void*)(uintptr_t)0xDEADBEEF, buffer, sizeof(buffer));

    ASSERT_TRUE(bytes < 0, "Invalid address read returns error (no crash)");
}

void test_read_heap_allocation(void) {
    printf("\nTest: Read from heap-allocated memory\n");

    uint8_t* heap = (uint8_t*)malloc(32);
    if (!heap) {
        printf("  x FAIL: malloc failed\n");
        tests_failed++;
        return;
    }

    for (int i = 0; i < 32; i++) {
        heap[i] = (uint8_t)(i * 7 + 3);
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
        printf("  x FAIL: malloc failed\n");
        tests_failed++;
        return;
    }

    memset(heap, 0xAA, 16);
    void* saved_addr = heap;
    free(heap);

    uint8_t readback[16];
    ssize_t bytes = safe_read_memory(saved_addr, readback, 16);

    /* May succeed or fail, but must NOT crash */
    printf("  + PASS: Freed memory read completed without crash "
           "(bytes=%lld)\n", (long long)bytes);
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

/* ══════════════════════════════════════════════════════════════
 * NEW TESTS: Edge cases and robustness
 * ══════════════════════════════════════════════════════════════ */

void test_zero_length_read(void) {
    printf("\nTest: Zero-length read\n");

    uint8_t source = 0x42;
    uint8_t dest = 0xFF;
    ssize_t bytes = safe_read_memory(&source, &dest, 0);

    ASSERT_EQ(bytes, 0, "Zero-length read returns 0");
    ASSERT_EQ(dest, 0xFF, "Destination buffer unchanged");
}

void test_high_address_invalid(void) {
    printf("\nTest: High-address invalid pointer (UINTPTR_MAX)\n");

    uint8_t buffer[16];
    ssize_t bytes = safe_read_memory(
        (const void*)(uintptr_t)UINTPTR_MAX, buffer, sizeof(buffer));

    ASSERT_TRUE(bytes < 0, "UINTPTR_MAX read returns error (no crash)");
}

void test_misaligned_reads(void) {
    printf("\nTest: Misaligned address reads\n");

    /* Create a buffer and read from odd offsets */
    uint8_t data[32];
    for (int i = 0; i < 32; i++) data[i] = (uint8_t)(i + 1);

    uint8_t readback[8];

    /* Read from offset +1 (misaligned for all multi-byte types) */
    ssize_t bytes = safe_read_memory(data + 1, readback, 4);
    ASSERT_EQ(bytes, 4, "Read 4 bytes from addr+1 (misaligned)");
    ASSERT_EQ(readback[0], 2, "First byte at offset+1 is correct");

    /* Read from offset +3 */
    bytes = safe_read_memory(data + 3, readback, 4);
    ASSERT_EQ(bytes, 4, "Read 4 bytes from addr+3 (misaligned)");
    ASSERT_EQ(readback[0], 4, "First byte at offset+3 is correct");

    /* Read from offset +7 */
    bytes = safe_read_memory(data + 7, readback, 8);
    ASSERT_EQ(bytes, 8, "Read 8 bytes from addr+7 (misaligned)");
    ASSERT_EQ(readback[0], 8, "First byte at offset+7 is correct");
}

void test_stack_memory_read(void) {
    printf("\nTest: Stack memory read\n");

    /* Stack-allocated buffer should be readable */
    uint8_t stack_data[64];
    for (int i = 0; i < 64; i++) stack_data[i] = (uint8_t)(i ^ 0xA5);

    uint8_t readback[64];
    ssize_t bytes = safe_read_memory(stack_data, readback, 64);

    ASSERT_EQ(bytes, 64, "Read 64 bytes from stack");
    ASSERT_EQ(memcmp(stack_data, readback, 64), 0, "Stack data matches");
}

void test_large_reads(void) {
    printf("\nTest: Large memory reads (1KB, 64KB, 1MB)\n");

    /* 1 KB */
    size_t size_1k = 1024;
    uint8_t* buf_1k = (uint8_t*)malloc(size_1k);
    if (buf_1k) {
        memset(buf_1k, 0xBB, size_1k);
        uint8_t* rb_1k = (uint8_t*)malloc(size_1k);
        if (rb_1k) {
            ssize_t bytes = safe_read_memory(buf_1k, rb_1k, size_1k);
            ASSERT_EQ(bytes, (ssize_t)size_1k, "Read 1KB successfully");
            ASSERT_EQ(memcmp(buf_1k, rb_1k, size_1k), 0, "1KB data matches");
            free(rb_1k);
        }
        free(buf_1k);
    }

    /* 64 KB */
    size_t size_64k = 64 * 1024;
    uint8_t* buf_64k = (uint8_t*)malloc(size_64k);
    if (buf_64k) {
        memset(buf_64k, 0xCC, size_64k);
        uint8_t* rb_64k = (uint8_t*)malloc(size_64k);
        if (rb_64k) {
            ssize_t bytes = safe_read_memory(buf_64k, rb_64k, size_64k);
            ASSERT_EQ(bytes, (ssize_t)size_64k, "Read 64KB successfully");
            ASSERT_EQ(memcmp(buf_64k, rb_64k, size_64k), 0, "64KB data matches");
            free(rb_64k);
        }
        free(buf_64k);
    }

    /* 1 MB */
    size_t size_1m = 1024 * 1024;
    uint8_t* buf_1m = (uint8_t*)malloc(size_1m);
    if (buf_1m) {
        memset(buf_1m, 0xDD, size_1m);
        uint8_t* rb_1m = (uint8_t*)malloc(size_1m);
        if (rb_1m) {
            ssize_t bytes = safe_read_memory(buf_1m, rb_1m, size_1m);
            ASSERT_EQ(bytes, (ssize_t)size_1m, "Read 1MB successfully");
            ASSERT_EQ(memcmp(buf_1m, rb_1m, size_1m), 0, "1MB data matches");
            free(rb_1m);
        }
        free(buf_1m);
    }
}

void test_guard_page(void) {
    printf("\nTest: Guard page (inaccessible memory)\n");

#if defined(_WIN32)
    /* Allocate a page then mark it as no-access */
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    size_t page_size = si.dwPageSize;

    void* page = VirtualAlloc(NULL, page_size, MEM_COMMIT | MEM_RESERVE,
                              PAGE_READWRITE);
    if (!page) {
        printf("  x FAIL: VirtualAlloc failed\n");
        tests_failed++;
        return;
    }
    memset(page, 0xEE, page_size);

    /* Mark as no-access */
    DWORD old_protect;
    VirtualProtect(page, page_size, PAGE_NOACCESS, &old_protect);

    uint8_t readback[16];
    ssize_t bytes = safe_read_memory(page, readback, 16);

    ASSERT_TRUE(bytes < 0, "Guard page read returns error (no crash)");

    /* Restore and free */
    VirtualProtect(page, page_size, PAGE_READWRITE, &old_protect);
    VirtualFree(page, 0, MEM_RELEASE);

#else
    /* POSIX: mmap + mprotect */
    size_t page_size = get_page_size();

    void* page = mmap(NULL, page_size, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (page == MAP_FAILED) {
        printf("  x FAIL: mmap failed\n");
        tests_failed++;
        return;
    }
    memset(page, 0xEE, page_size);

    /* Mark as inaccessible */
    mprotect(page, page_size, PROT_NONE);

    uint8_t readback[16];
    ssize_t bytes = safe_read_memory(page, readback, 16);

    ASSERT_TRUE(bytes < 0, "Guard page read returns error (no crash)");

    /* Restore and unmap */
    mprotect(page, page_size, PROT_READ | PROT_WRITE);
    munmap(page, page_size);
#endif
}

void test_page_boundary_read(void) {
    printf("\nTest: Page boundary read (cross into unmapped page)\n");

#if defined(_WIN32)
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    size_t page_size = si.dwPageSize;

    /* Allocate two pages, then free the second one */
    void* pages = VirtualAlloc(NULL, page_size * 2, MEM_COMMIT | MEM_RESERVE,
                               PAGE_READWRITE);
    if (!pages) {
        printf("  x FAIL: VirtualAlloc failed\n");
        tests_failed++;
        return;
    }
    memset(pages, 0xAA, page_size * 2);

    /* Mark second page as no-access */
    DWORD old_protect;
    VirtualProtect((uint8_t*)pages + page_size, page_size,
                   PAGE_NOACCESS, &old_protect);

    /* Read from last 8 bytes of page 1 into page 2 (16 bytes) */
    uint8_t readback[16];
    const void* near_boundary = (uint8_t*)pages + page_size - 8;
    ssize_t bytes = safe_read_memory(near_boundary, readback, 16);

    /* Should either fail (-1) or return partial (8 bytes) — never crash */
    ASSERT_TRUE(bytes <= 8,
                "Page boundary read: partial or error (no crash)");

    VirtualProtect((uint8_t*)pages + page_size, page_size,
                   PAGE_READWRITE, &old_protect);
    VirtualFree(pages, 0, MEM_RELEASE);

#else
    size_t page_size = get_page_size();

    /* Allocate two pages */
    void* pages = mmap(NULL, page_size * 2, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (pages == MAP_FAILED) {
        printf("  x FAIL: mmap failed\n");
        tests_failed++;
        return;
    }
    memset(pages, 0xAA, page_size * 2);

    /* Unmap second page */
    munmap((uint8_t*)pages + page_size, page_size);

    /* Read from last 8 bytes of page 1 into unmapped page 2 */
    uint8_t readback[16];
    const void* near_boundary = (uint8_t*)pages + page_size - 8;
    ssize_t bytes = safe_read_memory(near_boundary, readback, 16);

    /* Should fail or partial read — never crash */
    ASSERT_TRUE(bytes <= 8,
                "Page boundary read: partial or error (no crash)");

    munmap(pages, page_size);
#endif
}

void test_read_after_unmap(void) {
    printf("\nTest: Read after unmap (explicitly released memory)\n");

#if defined(_WIN32)
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    size_t page_size = si.dwPageSize;

    void* page = VirtualAlloc(NULL, page_size, MEM_COMMIT | MEM_RESERVE,
                              PAGE_READWRITE);
    if (!page) {
        printf("  x FAIL: VirtualAlloc failed\n");
        tests_failed++;
        return;
    }
    memset(page, 0xFF, page_size);
    void* saved = page;

    VirtualFree(page, 0, MEM_RELEASE);

    uint8_t readback[16];
    ssize_t bytes = safe_read_memory(saved, readback, 16);

    ASSERT_TRUE(bytes < 0, "Read after VirtualFree returns error (no crash)");

#else
    size_t page_size = get_page_size();

    void* page = mmap(NULL, page_size, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (page == MAP_FAILED) {
        printf("  x FAIL: mmap failed\n");
        tests_failed++;
        return;
    }
    memset(page, 0xFF, page_size);
    void* saved = page;

    munmap(page, page_size);

    uint8_t readback[16];
    ssize_t bytes = safe_read_memory(saved, readback, 16);

    ASSERT_TRUE(bytes < 0, "Read after munmap returns error (no crash)");
#endif
}

/* ── Multi-threaded concurrent read test ── */

#if defined(_WIN32)

/* Simple Windows thread test — writer writes while reader reads */
typedef struct {
    volatile uint8_t* shared_buf;
    volatile int running;
    size_t buf_size;
} ThreadData;

static DWORD WINAPI writer_thread(LPVOID arg) {
    ThreadData* td = (ThreadData*)arg;
    uint8_t val = 0;
    while (td->running) {
        memset((void*)td->shared_buf, val++, td->buf_size);
    }
    return 0;
}

void test_multithreaded_read(void) {
    printf("\nTest: Multi-threaded concurrent read\n");

    size_t buf_size = 256;
    ThreadData td;
    td.shared_buf = (volatile uint8_t*)malloc(buf_size);
    td.running = 1;
    td.buf_size = buf_size;
    if (!td.shared_buf) {
        printf("  x FAIL: malloc failed\n");
        tests_failed++;
        return;
    }
    memset((void*)td.shared_buf, 0, buf_size);

    HANDLE hThread = CreateThread(NULL, 0, writer_thread, &td, 0, NULL);
    if (!hThread) {
        printf("  x FAIL: CreateThread failed\n");
        tests_failed++;
        free((void*)td.shared_buf);
        return;
    }

    /* Read concurrently 1000 times */
    uint8_t readback[256];
    int success_count = 0;
    for (int i = 0; i < 1000; i++) {
        ssize_t bytes = safe_read_memory(
            (const void*)td.shared_buf, readback, buf_size);
        if (bytes == (ssize_t)buf_size) success_count++;
    }

    td.running = 0;
    WaitForSingleObject(hThread, INFINITE);
    CloseHandle(hThread);
    free((void*)td.shared_buf);

    ASSERT_TRUE(success_count > 0, "Concurrent reads completed without crash");
    printf("  + PASS: %d/1000 reads succeeded during concurrent writes\n",
           success_count);
    tests_passed++;
}

#else /* POSIX */

typedef struct {
    volatile uint8_t* shared_buf;
    volatile int running;
    size_t buf_size;
} ThreadData;

static void* writer_thread(void* arg) {
    ThreadData* td = (ThreadData*)arg;
    uint8_t val = 0;
    while (td->running) {
        memset((void*)td->shared_buf, val++, td->buf_size);
    }
    return NULL;
}

void test_multithreaded_read(void) {
    printf("\nTest: Multi-threaded concurrent read\n");

    size_t buf_size = 256;
    ThreadData td;
    td.shared_buf = (volatile uint8_t*)malloc(buf_size);
    td.running = 1;
    td.buf_size = buf_size;
    if (!td.shared_buf) {
        printf("  x FAIL: malloc failed\n");
        tests_failed++;
        return;
    }
    memset((void*)td.shared_buf, 0, buf_size);

    pthread_t thread;
    if (pthread_create(&thread, NULL, writer_thread, &td) != 0) {
        printf("  x FAIL: pthread_create failed\n");
        tests_failed++;
        free((void*)td.shared_buf);
        return;
    }

    /* Read concurrently 1000 times */
    uint8_t readback[256];
    int success_count = 0;
    for (int i = 0; i < 1000; i++) {
        ssize_t bytes = safe_read_memory(
            (const void*)td.shared_buf, readback, buf_size);
        if (bytes == (ssize_t)buf_size) success_count++;
    }

    td.running = 0;
    pthread_join(thread, NULL);
    free((void*)td.shared_buf);

    ASSERT_TRUE(success_count > 0, "Concurrent reads completed without crash");
    printf("  + PASS: %d/1000 reads succeeded during concurrent writes\n",
           success_count);
    tests_passed++;
}

#endif

/* ── Main ── */

int main(void) {
    printf("=== Cross-Platform Safe Memory Read Test Suite ===\n");
    printf("Platform: %s\n", PLATFORM_NAME);
    printf("Pointer size: %zu bytes\n", sizeof(void*));
    printf("Page size: %zu bytes\n", get_page_size());

    /* Existing tests */
    test_read_valid_memory();
    test_read_null_address();
    test_read_invalid_address();
    test_read_heap_allocation();
    test_read_after_free();
    test_partial_read();

    /* New edge-case tests */
    test_zero_length_read();
    test_high_address_invalid();
    test_misaligned_reads();
    test_stack_memory_read();
    test_large_reads();
    test_guard_page();
    test_page_boundary_read();
    test_read_after_unmap();
    test_multithreaded_read();

    printf("\n=== Results: %d passed, %d failed ===\n",
           tests_passed, tests_failed);

    return tests_failed > 0 ? 1 : 0;
}
