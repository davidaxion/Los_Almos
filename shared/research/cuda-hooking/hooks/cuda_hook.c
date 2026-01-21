/*
 * cuda_hook.c - Comprehensive CUDA API Hooking Library
 *
 * Intercepts all major CUDA Driver API calls to trace the complete
 * pipeline from model loading through inference to result retrieval.
 *
 * Compile: gcc -shared -fPIC cuda_hook.c -o libcuda_hook.so -ldl
 * Usage: LD_PRELOAD=./libcuda_hook.so python your_inference.py
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/time.h>
#include <stdint.h>
#include <string.h>
#include <pthread.h>

// CUDA types (minimal definitions needed for hooking)
typedef void* CUdevice;
typedef void* CUcontext;
typedef void* CUstream;
typedef void* CUfunction;
typedef void* CUmodule;
typedef unsigned long long CUdeviceptr;
typedef int CUresult;

// Thread-safe counter for operation IDs
static uint64_t operation_counter = 0;
static pthread_mutex_t counter_mutex = PTHREAD_MUTEX_INITIALIZER;

// Trace output file
static FILE* trace_file = NULL;
static pthread_mutex_t file_mutex = PTHREAD_MUTEX_INITIALIZER;

// Initialize tracing on library load
__attribute__((constructor))
static void init_tracing(void) {
    const char* trace_path = getenv("CUDA_HOOK_TRACE");
    if (!trace_path) {
        trace_path = "cuda_trace.jsonl";
    }

    trace_file = fopen(trace_path, "w");
    if (!trace_file) {
        fprintf(stderr, "[CUDA_HOOK] Failed to open trace file: %s\n", trace_path);
        trace_file = stderr;
    }

    fprintf(stderr, "[CUDA_HOOK] Tracing initialized. Output: %s\n", trace_path);
    fflush(stderr);
}

__attribute__((destructor))
static void cleanup_tracing(void) {
    if (trace_file && trace_file != stderr) {
        fclose(trace_file);
    }
}

// Get high-resolution timestamp
static double get_timestamp(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

// Get next operation ID
static uint64_t next_op_id(void) {
    pthread_mutex_lock(&counter_mutex);
    uint64_t id = operation_counter++;
    pthread_mutex_unlock(&counter_mutex);
    return id;
}

// Generic trace logging (JSON Lines format)
static void log_trace(const char* phase, const char* category, const char* name,
                      uint64_t op_id, double timestamp, const char* details) {
    pthread_mutex_lock(&file_mutex);
    fprintf(trace_file,
            "{\"ts\":%.9f,\"op_id\":%llu,\"phase\"%s\",\"category\":\"%s\",\"name\":\"%s\"",
            timestamp, op_id, phase, category, name);
    if (details) {
        fprintf(trace_file, ",\"details\":%s", details);
    }
    fprintf(trace_file, "}\n");
    fflush(trace_file);
    pthread_mutex_unlock(&file_mutex);
}

// Macro to define hooks with timing
#define HOOK_FUNCTION(ret_type, func_name, params, args) \
    static ret_type (*real_##func_name) params = NULL; \
    ret_type func_name params { \
        if (!real_##func_name) { \
            real_##func_name = dlsym(RTLD_NEXT, #func_name); \
            if (!real_##func_name) { \
                fprintf(stderr, "[CUDA_HOOK] Failed to load " #func_name "\n"); \
                return 1; \
            } \
        } \
        uint64_t op_id = next_op_id(); \
        double start = get_timestamp();

#define END_HOOK(category, name, details) \
        double end = get_timestamp(); \
        log_trace("\"E\"", category, name, op_id, end, details); \
        return result; \
    }

//
// Memory Management Hooks
//

HOOK_FUNCTION(CUresult, cuMemAlloc, (CUdeviceptr *dptr, size_t bytesize), (dptr, bytesize))
    char details[256];
    snprintf(details, sizeof(details), "{\"size\":%zu}", bytesize);
    log_trace("\"B\"", "memory", "cuMemAlloc", op_id, start, details);

    CUresult result = real_cuMemAlloc(dptr, bytesize);

    snprintf(details, sizeof(details), "{\"size\":%zu,\"ptr\":\"%p\",\"status\":%d}",
             bytesize, (void*)*dptr, result);
END_HOOK("memory", "cuMemAlloc", details)

HOOK_FUNCTION(CUresult, cuMemFree, (CUdeviceptr dptr), (dptr))
    char details[256];
    snprintf(details, sizeof(details), "{\"ptr\":\"%p\"}", (void*)dptr);
    log_trace("\"B\"", "memory", "cuMemFree", op_id, start, details);

    CUresult result = real_cuMemFree(dptr);

    snprintf(details, sizeof(details), "{\"ptr\":\"%p\",\"status\":%d}", (void*)dptr, result);
END_HOOK("memory", "cuMemFree", details)

HOOK_FUNCTION(CUresult, cuMemcpyHtoD, (CUdeviceptr dstDevice, const void *srcHost, size_t ByteCount),
              (dstDevice, srcHost, ByteCount))
    char details[512];
    snprintf(details, sizeof(details),
             "{\"direction\":\"host_to_device\",\"dst\":\"%p\",\"src\":\"%p\",\"size\":%zu}",
             (void*)dstDevice, srcHost, ByteCount);
    log_trace("\"B\"", "transfer", "cuMemcpyHtoD", op_id, start, details);

    CUresult result = real_cuMemcpyHtoD(dstDevice, srcHost, ByteCount);

    snprintf(details, sizeof(details),
             "{\"direction\":\"host_to_device\",\"size\":%zu,\"bandwidth_gbps\":%.2f,\"status\":%d}",
             ByteCount, ByteCount / ((end - start) * 1e9), result);
END_HOOK("transfer", "cuMemcpyHtoD", details)

HOOK_FUNCTION(CUresult, cuMemcpyDtoH, (void *dstHost, CUdeviceptr srcDevice, size_t ByteCount),
              (dstHost, srcDevice, ByteCount))
    char details[512];
    snprintf(details, sizeof(details),
             "{\"direction\":\"device_to_host\",\"dst\":\"%p\",\"src\":\"%p\",\"size\":%zu}",
             dstHost, (void*)srcDevice, ByteCount);
    log_trace("\"B\"", "transfer", "cuMemcpyDtoH", op_id, start, details);

    CUresult result = real_cuMemcpyDtoH(dstHost, srcDevice, ByteCount);

    snprintf(details, sizeof(details),
             "{\"direction\":\"device_to_host\",\"size\":%zu,\"bandwidth_gbps\":%.2f,\"status\":%d}",
             ByteCount, ByteCount / ((end - start) * 1e9), result);
END_HOOK("transfer", "cuMemcpyDtoH", details)

HOOK_FUNCTION(CUresult, cuMemcpyDtoD, (CUdeviceptr dstDevice, CUdeviceptr srcDevice, size_t ByteCount),
              (dstDevice, srcDevice, ByteCount))
    char details[512];
    snprintf(details, sizeof(details),
             "{\"direction\":\"device_to_device\",\"dst\":\"%p\",\"src\":\"%p\",\"size\":%zu}",
             (void*)dstDevice, (void*)srcDevice, ByteCount);
    log_trace("\"B\"", "transfer", "cuMemcpyDtoD", op_id, start, details);

    CUresult result = real_cuMemcpyDtoD(dstDevice, srcDevice, ByteCount);

    snprintf(details, sizeof(details),
             "{\"direction\":\"device_to_device\",\"size\":%zu,\"bandwidth_gbps\":%.2f,\"status\":%d}",
             ByteCount, ByteCount / ((end - start) * 1e9), result);
END_HOOK("transfer", "cuMemcpyDtoD", details)

//
// Context Management Hooks
//

HOOK_FUNCTION(CUresult, cuCtxCreate, (CUcontext *pctx, unsigned int flags, CUdevice dev),
              (pctx, flags, dev))
    char details[256];
    snprintf(details, sizeof(details), "{\"flags\":%u,\"device\":\"%p\"}", flags, dev);
    log_trace("\"B\"", "context", "cuCtxCreate", op_id, start, details);

    CUresult result = real_cuCtxCreate(pctx, flags, dev);

    snprintf(details, sizeof(details), "{\"ctx\":\"%p\",\"status\":%d}", *pctx, result);
END_HOOK("context", "cuCtxCreate", details)

HOOK_FUNCTION(CUresult, cuCtxDestroy, (CUcontext ctx), (ctx))
    char details[256];
    snprintf(details, sizeof(details), "{\"ctx\":\"%p\"}", ctx);
    log_trace("\"B\"", "context", "cuCtxDestroy", op_id, start, details);

    CUresult result = real_cuCtxDestroy(ctx);

    snprintf(details, sizeof(details), "{\"ctx\":\"%p\",\"status\":%d}", ctx, result);
END_HOOK("context", "cuCtxDestroy", details)

HOOK_FUNCTION(CUresult, cuCtxSetCurrent, (CUcontext ctx), (ctx))
    char details[256];
    snprintf(details, sizeof(details), "{\"ctx\":\"%p\"}", ctx);
    log_trace("\"B\"", "context", "cuCtxSetCurrent", op_id, start, details);

    CUresult result = real_cuCtxSetCurrent(ctx);

    snprintf(details, sizeof(details), "{\"ctx\":\"%p\",\"status\":%d}", ctx, result);
END_HOOK("context", "cuCtxSetCurrent", details)

HOOK_FUNCTION(CUresult, cuCtxSynchronize, (void), ())
    log_trace("\"B\"", "sync", "cuCtxSynchronize", op_id, start, NULL);

    CUresult result = real_cuCtxSynchronize();

    char details[256];
    snprintf(details, sizeof(details), "{\"duration_ms\":%.3f,\"status\":%d}",
             (end - start) * 1000, result);
END_HOOK("sync", "cuCtxSynchronize", details)

//
// Stream Management Hooks
//

HOOK_FUNCTION(CUresult, cuStreamCreate, (CUstream *phStream, unsigned int Flags),
              (phStream, Flags))
    char details[256];
    snprintf(details, sizeof(details), "{\"flags\":%u}", Flags);
    log_trace("\"B\"", "stream", "cuStreamCreate", op_id, start, details);

    CUresult result = real_cuStreamCreate(phStream, Flags);

    snprintf(details, sizeof(details), "{\"stream\":\"%p\",\"status\":%d}", *phStream, result);
END_HOOK("stream", "cuStreamCreate", details)

HOOK_FUNCTION(CUresult, cuStreamDestroy, (CUstream hStream), (hStream))
    char details[256];
    snprintf(details, sizeof(details), "{\"stream\":\"%p\"}", hStream);
    log_trace("\"B\"", "stream", "cuStreamDestroy", op_id, start, details);

    CUresult result = real_cuStreamDestroy(hStream);

    snprintf(details, sizeof(details), "{\"stream\":\"%p\",\"status\":%d}", hStream, result);
END_HOOK("stream", "cuStreamDestroy", details)

HOOK_FUNCTION(CUresult, cuStreamSynchronize, (CUstream hStream), (hStream))
    char details[256];
    snprintf(details, sizeof(details), "{\"stream\":\"%p\"}", hStream);
    log_trace("\"B\"", "sync", "cuStreamSynchronize", op_id, start, details);

    CUresult result = real_cuStreamSynchronize(hStream);

    snprintf(details, sizeof(details),
             "{\"stream\":\"%p\",\"duration_ms\":%.3f,\"status\":%d}",
             hStream, (end - start) * 1000, result);
END_HOOK("sync", "cuStreamSynchronize", details)

//
// Kernel Execution Hooks
//

HOOK_FUNCTION(CUresult, cuLaunchKernel,
              (CUfunction f, unsigned int gridDimX, unsigned int gridDimY, unsigned int gridDimZ,
               unsigned int blockDimX, unsigned int blockDimY, unsigned int blockDimZ,
               unsigned int sharedMemBytes, CUstream hStream, void **kernelParams, void **extra),
              (f, gridDimX, gridDimY, gridDimZ, blockDimX, blockDimY, blockDimZ,
               sharedMemBytes, hStream, kernelParams, extra))
    char details[512];
    snprintf(details, sizeof(details),
             "{\"function\":\"%p\",\"grid\":[%u,%u,%u],\"block\":[%u,%u,%u],\"shared_mem\":%u,\"stream\":\"%p\"}",
             f, gridDimX, gridDimY, gridDimZ, blockDimX, blockDimY, blockDimZ,
             sharedMemBytes, hStream);
    log_trace("\"B\"", "kernel", "cuLaunchKernel", op_id, start, details);

    CUresult result = real_cuLaunchKernel(f, gridDimX, gridDimY, gridDimZ,
                                          blockDimX, blockDimY, blockDimZ,
                                          sharedMemBytes, hStream, kernelParams, extra);

    unsigned int total_threads = gridDimX * gridDimY * gridDimZ *
                                blockDimX * blockDimY * blockDimZ;
    snprintf(details, sizeof(details),
             "{\"grid\":[%u,%u,%u],\"block\":[%u,%u,%u],\"total_threads\":%u,\"duration_us\":%.3f,\"status\":%d}",
             gridDimX, gridDimY, gridDimZ, blockDimX, blockDimY, blockDimZ,
             total_threads, (end - start) * 1e6, result);
END_HOOK("kernel", "cuLaunchKernel", details)

HOOK_FUNCTION(CUresult, cuModuleLoad, (CUmodule *module, const char *fname), (module, fname))
    char details[512];
    snprintf(details, sizeof(details), "{\"file\":\"%s\"}", fname ? fname : "null");
    log_trace("\"B\"", "module", "cuModuleLoad", op_id, start, details);

    CUresult result = real_cuModuleLoad(module, fname);

    snprintf(details, sizeof(details), "{\"module\":\"%p\",\"file\":\"%s\",\"status\":%d}",
             *module, fname ? fname : "null", result);
END_HOOK("module", "cuModuleLoad", details)

HOOK_FUNCTION(CUresult, cuModuleUnload, (CUmodule hmod), (hmod))
    char details[256];
    snprintf(details, sizeof(details), "{\"module\":\"%p\"}", hmod);
    log_trace("\"B\"", "module", "cuModuleUnload", op_id, start, details);

    CUresult result = real_cuModuleUnload(hmod);

    snprintf(details, sizeof(details), "{\"module\":\"%p\",\"status\":%d}", hmod, result);
END_HOOK("module", "cuModuleUnload", details)

HOOK_FUNCTION(CUresult, cuModuleGetFunction, (CUfunction *hfunc, CUmodule hmod, const char *name),
              (hfunc, hmod, name))
    char details[512];
    snprintf(details, sizeof(details), "{\"module\":\"%p\",\"name\":\"%s\"}", hmod, name ? name : "null");
    log_trace("\"B\"", "module", "cuModuleGetFunction", op_id, start, details);

    CUresult result = real_cuModuleGetFunction(hfunc, hmod, name);

    snprintf(details, sizeof(details), "{\"function\":\"%p\",\"name\":\"%s\",\"status\":%d}",
             *hfunc, name ? name : "null", result);
END_HOOK("module", "cuModuleGetFunction", details)

//
// Device Management Hooks
//

HOOK_FUNCTION(CUresult, cuInit, (unsigned int Flags), (Flags))
    char details[256];
    snprintf(details, sizeof(details), "{\"flags\":%u}", Flags);
    log_trace("\"B\"", "init", "cuInit", op_id, start, details);

    CUresult result = real_cuInit(Flags);

    snprintf(details, sizeof(details), "{\"status\":%d}", result);
END_HOOK("init", "cuInit", details)

HOOK_FUNCTION(CUresult, cuDeviceGet, (CUdevice *device, int ordinal), (device, ordinal))
    char details[256];
    snprintf(details, sizeof(details), "{\"ordinal\":%d}", ordinal);
    log_trace("\"B\"", "device", "cuDeviceGet", op_id, start, details);

    CUresult result = real_cuDeviceGet(device, ordinal);

    snprintf(details, sizeof(details), "{\"device\":\"%p\",\"ordinal\":%d,\"status\":%d}",
             *device, ordinal, result);
END_HOOK("device", "cuDeviceGet", details)
