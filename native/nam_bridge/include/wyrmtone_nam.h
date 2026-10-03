#ifndef WYRMTONE_NAM_H
#define WYRMTONE_NAM_H

/// Stable C ABI between Dart (via dart:ffi) and the vendored
/// NeuralAmpModelerCore (see D:\Develop\Wyrmtone\third_party\NeuralAmpModelerCore,
/// pinned at 0b3d3c97b0859a3a8c92a8628c4dd89a25eb5842). This header is the ONLY
/// contract Dart is allowed to depend on: no C++ classes, no exceptions, no
/// STL types cross this boundary.
///
/// Ownership: one wyrmtone_nam_handle owns at most one loaded model at a
/// time. It is NOT safe to call two functions on the SAME handle
/// concurrently from different threads; create one handle per worker
/// thread/isolate if you need concurrency. Different handles are fully
/// independent (no shared global state).
///
/// Every function returns a wyrmtone_nam_status; on failure call
/// wyrmtone_nam_last_error(handle) for a human-readable message. The
/// returned string is owned by the handle and stays valid until the next
/// call on that same handle (copy it if you need it longer).

#include <stddef.h>
#include <stdint.h>

#ifdef _WIN32
#define WYRMTONE_NAM_API extern "C" __declspec(dllexport)
#else
#define WYRMTONE_NAM_API extern "C" __attribute__((visibility("default")))
#endif

typedef enum {
  WYRMTONE_NAM_OK = 0,
  WYRMTONE_NAM_ERR_INVALID_ARGUMENT = 1,
  WYRMTONE_NAM_ERR_FILE_NOT_FOUND = 2,
  WYRMTONE_NAM_ERR_LOAD_FAILED = 3,
  WYRMTONE_NAM_ERR_NOT_LOADED = 4,
  WYRMTONE_NAM_ERR_ALREADY_LOADED = 5,
  WYRMTONE_NAM_ERR_PROCESS_FAILED = 6,
  WYRMTONE_NAM_ERR_OUT_OF_MEMORY = 7,
  WYRMTONE_NAM_ERR_UNKNOWN = 99,
} wyrmtone_nam_status;

/// Opaque handle. Never dereferenced by callers.
typedef struct wyrmtone_nam_engine wyrmtone_nam_engine;

/// Creates a fresh, unloaded engine instance. Returns NULL only on
/// allocation failure (never throws).
WYRMTONE_NAM_API wyrmtone_nam_engine* wyrmtone_nam_create(void);

/// Loads a .nam file and resets the model for the given sample rate and
/// maximum block size (frames per wyrmtone_nam_process call the caller
/// intends to use; the bridge also chunks internally, so this is a hint,
/// not a hard cap). Fails with WYRMTONE_NAM_ERR_ALREADY_LOADED if a model
/// is already loaded on this handle (call wyrmtone_nam_unload first).
/// [nam_path_utf8] must be a NUL-terminated UTF-8 path.
WYRMTONE_NAM_API wyrmtone_nam_status wyrmtone_nam_load(wyrmtone_nam_engine* engine, const char* nam_path_utf8,
                                                         double sample_rate, int32_t max_block_size);

/// The model's own expected/native sample rate (Hz), or 0.0 if nothing is
/// loaded. The caller is responsible for resampling its input to the rate
/// passed to wyrmtone_nam_load; the bridge does not resample.
WYRMTONE_NAM_API double wyrmtone_nam_expected_sample_rate(const wyrmtone_nam_engine* engine);

/// Runs mono inference over [num_frames] float32 samples. [input] and
/// [output] must each point to at least [num_frames] floats and may alias
/// only if input == output (in place). Internally chunks into blocks of at
/// most the max_block_size given to wyrmtone_nam_load. Deterministic for a
/// freshly loaded model with the same input.
WYRMTONE_NAM_API wyrmtone_nam_status wyrmtone_nam_process(wyrmtone_nam_engine* engine, const float* input,
                                                            float* output, int32_t num_frames);

/// Releases the loaded model, if any, so the handle can be reused with
/// wyrmtone_nam_load again. Safe to call when nothing is loaded (no-op).
WYRMTONE_NAM_API void wyrmtone_nam_unload(wyrmtone_nam_engine* engine);

/// Destroys the handle (unloading any model first). [engine] must not be
/// used again afterwards; calling any other function with it is undefined
/// behaviour (caller's responsibility, matching normal C ABI conventions).
/// Safe to call with NULL (no-op).
WYRMTONE_NAM_API void wyrmtone_nam_destroy(wyrmtone_nam_engine* engine);

/// Human-readable message for the most recent non-OK status returned by
/// this handle, or "" if none yet. Never NULL. Owned by [engine].
WYRMTONE_NAM_API const char* wyrmtone_nam_last_error(const wyrmtone_nam_engine* engine);

/// Version string of this bridge (not of NeuralAmpModelerCore itself), for
/// diagnostics.
WYRMTONE_NAM_API const char* wyrmtone_nam_bridge_version(void);

#endif // WYRMTONE_NAM_H
