// Minimal C-ABI bridge over NeuralAmpModelerCore. See ../include/wyrmtone_nam.h
// for the contract. No exception, no C++ type, ever crosses wyrmtone_nam_*.

#include "wyrmtone_nam.h"

#include <algorithm>
#include <exception>
#include <filesystem>
#include <memory>
#include <string>
#include <vector>

#include "NAM/dsp.h"
#include "NAM/get_dsp.h"

namespace {
constexpr const char* kBridgeVersion = "wyrmtone-nam-bridge/0.1 (NeuralAmpModelerCore 0b3d3c9)";
}

struct wyrmtone_nam_engine {
  std::unique_ptr<nam::DSP> model;
  std::string lastError;
  int maxBlockSize = 0;
  // Scratch buffers reused across process() calls to avoid per-call heap
  // churn; sized to maxBlockSize once a model is loaded.
  std::vector<double> inScratch;
  std::vector<double> outScratch;

  void setError(const std::string& message) { lastError = message; }
};

namespace {

/// Runs [fn] and converts any thrown exception into a status + message on
/// [engine]; nothing ever escapes across the ABI boundary.
template <typename Fn>
wyrmtone_nam_status guard(wyrmtone_nam_engine* engine, wyrmtone_nam_status onException, Fn&& fn) {
  try {
    return fn();
  } catch (const std::exception& e) {
    if (engine) engine->setError(e.what());
    return onException;
  } catch (...) {
    if (engine) engine->setError("unknown native exception");
    return onException;
  }
}

}  // namespace

WYRMTONE_NAM_API wyrmtone_nam_engine* wyrmtone_nam_create(void) {
  try {
    return new wyrmtone_nam_engine();
  } catch (...) {
    return nullptr;
  }
}

WYRMTONE_NAM_API wyrmtone_nam_status wyrmtone_nam_load(wyrmtone_nam_engine* engine, const char* nam_path_utf8,
                                                         double sample_rate, int32_t max_block_size) {
  if (engine == nullptr || nam_path_utf8 == nullptr) return WYRMTONE_NAM_ERR_INVALID_ARGUMENT;
  if (sample_rate <= 0.0 || max_block_size <= 0) {
    engine->setError("sample_rate and max_block_size must be positive");
    return WYRMTONE_NAM_ERR_INVALID_ARGUMENT;
  }
  if (engine->model != nullptr) {
    engine->setError("a model is already loaded on this handle; call wyrmtone_nam_unload first");
    return WYRMTONE_NAM_ERR_ALREADY_LOADED;
  }
  return guard(engine, WYRMTONE_NAM_ERR_LOAD_FAILED, [&]() -> wyrmtone_nam_status {
    const std::filesystem::path path = std::filesystem::path(reinterpret_cast<const char8_t*>(nam_path_utf8));
    if (!std::filesystem::exists(path)) {
      engine->setError("file does not exist: " + path.string());
      return WYRMTONE_NAM_ERR_FILE_NOT_FOUND;
    }
    auto model = nam::get_dsp(path);
    if (model == nullptr) {
      engine->setError("nam::get_dsp returned null for " + path.string());
      return WYRMTONE_NAM_ERR_LOAD_FAILED;
    }
    model->Reset(sample_rate, max_block_size);
    engine->model = std::move(model);
    engine->maxBlockSize = max_block_size;
    engine->inScratch.assign(static_cast<size_t>(max_block_size), 0.0);
    engine->outScratch.assign(static_cast<size_t>(max_block_size), 0.0);
    engine->lastError.clear();
    return WYRMTONE_NAM_OK;
  });
}

WYRMTONE_NAM_API double wyrmtone_nam_expected_sample_rate(const wyrmtone_nam_engine* engine) {
  if (engine == nullptr || engine->model == nullptr) return 0.0;
  const double rate = engine->model->GetExpectedSampleRate();
  return rate > 0.0 ? rate : 0.0;
}

WYRMTONE_NAM_API wyrmtone_nam_status wyrmtone_nam_process(wyrmtone_nam_engine* engine, const float* input,
                                                            float* output, int32_t num_frames) {
  if (engine == nullptr || input == nullptr || output == nullptr) return WYRMTONE_NAM_ERR_INVALID_ARGUMENT;
  if (num_frames < 0) return WYRMTONE_NAM_ERR_INVALID_ARGUMENT;
  if (engine->model == nullptr) {
    engine->setError("no model loaded; call wyrmtone_nam_load first");
    return WYRMTONE_NAM_ERR_NOT_LOADED;
  }
  if (num_frames == 0) return WYRMTONE_NAM_OK;
  return guard(engine, WYRMTONE_NAM_ERR_PROCESS_FAILED, [&]() -> wyrmtone_nam_status {
    const int block = engine->maxBlockSize;
    double* inPtr = engine->inScratch.data();
    double* outPtr = engine->outScratch.data();
    int32_t done = 0;
    while (done < num_frames) {
      const int32_t chunk = std::min<int32_t>(block, num_frames - done);
      for (int32_t i = 0; i < chunk; i++) inPtr[i] = static_cast<double>(input[done + i]);
      engine->model->process(&inPtr, &outPtr, chunk);
      for (int32_t i = 0; i < chunk; i++) output[done + i] = static_cast<float>(outPtr[i]);
      done += chunk;
    }
    return WYRMTONE_NAM_OK;
  });
}

WYRMTONE_NAM_API void wyrmtone_nam_unload(wyrmtone_nam_engine* engine) {
  if (engine == nullptr) return;
  engine->model.reset();
  engine->inScratch.clear();
  engine->outScratch.clear();
  engine->maxBlockSize = 0;
}

WYRMTONE_NAM_API void wyrmtone_nam_destroy(wyrmtone_nam_engine* engine) { delete engine; }

WYRMTONE_NAM_API const char* wyrmtone_nam_last_error(const wyrmtone_nam_engine* engine) {
  if (engine == nullptr) return "";
  return engine->lastError.c_str();
}

WYRMTONE_NAM_API const char* wyrmtone_nam_bridge_version(void) { return kBridgeVersion; }
