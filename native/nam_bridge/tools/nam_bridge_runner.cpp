// Native smoke-test runner for the wyrmtone_nam bridge (V4a). Deliberately
// does NOT link the DLL: it compiles the same sources directly, so a
// mismatch between this runner and the Dart/FFI path can only come from the
// FFI boundary itself, never from "two different binaries".
//
// Usage:
//   nam_bridge_runner <model.nam> <input_48k_mono.wav> <out.wav> <out_f32.bin>
//
// Reads a mono PCM16/24 (or float32) WAV at 48 kHz, runs it through the real
// NeuralAmpModelerCore inference, and writes:
//   - out.wav: 16-bit stereo (L=R) WAV in the same layout the official
//     Sonicake editor's nam_output_wav.wav uses, so it can be fed unchanged
//     into the existing frozen MatriboxNamCloDataConverter.
//   - out_f32.bin: raw little-endian float32 samples (no quantization), for
//     an exact signal-level comparison against the official output.
//
// No Matribox/transport code here at all.

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include "wyrmtone_nam.h"

namespace {

struct WavIn {
  int sampleRate = 0;
  int channels = 0;
  int bits = 0;
  std::vector<float> mono;  // first channel, normalized to [-1, 1]
};

uint32_t rd_u32(const std::vector<uint8_t>& b, size_t o) {
  return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (uint32_t(b[o + 3]) << 24);
}
uint16_t rd_u16(const std::vector<uint8_t>& b, size_t o) { return b[o] | (b[o + 1] << 8); }

bool readWav(const std::string& path, WavIn* out) {
  std::ifstream f(path, std::ios::binary);
  if (!f) {
    std::cerr << "cannot open " << path << "\n";
    return false;
  }
  std::vector<uint8_t> b((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
  if (b.size() < 12 || std::memcmp(b.data(), "RIFF", 4) != 0 || std::memcmp(b.data() + 8, "WAVE", 4) != 0) {
    std::cerr << "not a RIFF/WAVE file\n";
    return false;
  }
  size_t offset = 12;
  uint16_t format = 0, bits = 0, channels = 0;
  uint32_t rate = 0;
  while (offset + 8 <= b.size()) {
    char id[5] = {0};
    std::memcpy(id, &b[offset], 4);
    uint32_t size = rd_u32(b, offset + 4);
    size_t body = offset + 8;
    if (std::memcmp(id, "fmt ", 4) == 0) {
      format = rd_u16(b, body);
      channels = rd_u16(b, body + 2);
      rate = rd_u32(b, body + 4);
      bits = rd_u16(b, body + 14);
    } else if (std::memcmp(id, "data", 4) == 0) {
      const int frameBytes = channels * (bits / 8);
      const uint32_t frames = frameBytes > 0 ? size / frameBytes : 0;
      out->sampleRate = static_cast<int>(rate);
      out->channels = channels;
      out->bits = bits;
      out->mono.resize(frames);
      for (uint32_t i = 0; i < frames; i++) {
        size_t at = body + static_cast<size_t>(i) * frameBytes;
        if (format == 3 && bits == 32) {
          float v;
          std::memcpy(&v, &b[at], 4);
          out->mono[i] = v;
        } else if (bits == 16) {
          int16_t v = static_cast<int16_t>(rd_u16(b, at));
          out->mono[i] = v / 32768.0f;
        } else if (bits == 24) {
          int32_t v = b[at] | (b[at + 1] << 8) | (b[at + 2] << 16);
          if (v & 0x800000) v -= 0x1000000;
          out->mono[i] = v / 8388608.0f;
        } else {
          std::cerr << "unsupported format " << format << "/" << bits << "bit\n";
          return false;
        }
      }
      return true;
    }
    offset = body + size + (size & 1);
  }
  std::cerr << "no data chunk\n";
  return false;
}

void wr_u32(std::vector<uint8_t>* b, uint32_t v) {
  b->push_back(v & 0xff);
  b->push_back((v >> 8) & 0xff);
  b->push_back((v >> 16) & 0xff);
  b->push_back((v >> 24) & 0xff);
}
void wr_u16(std::vector<uint8_t>* b, uint16_t v) {
  b->push_back(v & 0xff);
  b->push_back((v >> 8) & 0xff);
}

/// 16-bit stereo (L=R) PCM WAV, matching the official editor's
/// nam_output_wav.wav layout exactly (quantization included).
bool writeWavStereo16(const std::string& path, const std::vector<float>& mono, int sampleRate) {
  std::vector<uint8_t> b;
  const uint32_t dataSize = static_cast<uint32_t>(mono.size()) * 4;  // 2 ch * 2 bytes
  b.reserve(44 + dataSize);
  b.insert(b.end(), {'R', 'I', 'F', 'F'});
  wr_u32(&b, 36 + dataSize);
  b.insert(b.end(), {'W', 'A', 'V', 'E', 'f', 'm', 't', ' '});
  wr_u32(&b, 16);
  wr_u16(&b, 1);  // PCM
  wr_u16(&b, 2);  // stereo
  wr_u32(&b, static_cast<uint32_t>(sampleRate));
  wr_u32(&b, static_cast<uint32_t>(sampleRate) * 4);
  wr_u16(&b, 4);   // block align
  wr_u16(&b, 16);  // bits
  b.insert(b.end(), {'d', 'a', 't', 'a'});
  wr_u32(&b, dataSize);
  for (float s : mono) {
    float clamped = s < -1.0f ? -1.0f : (s > 1.0f ? 1.0f : s);
    int32_t q = static_cast<int32_t>(std::lround(clamped * 32768.0f));
    if (q > 32767) q = 32767;
    if (q < -32768) q = -32768;
    int16_t v = static_cast<int16_t>(q);
    wr_u16(&b, static_cast<uint16_t>(v));
    wr_u16(&b, static_cast<uint16_t>(v));
  }
  std::ofstream f(path, std::ios::binary);
  if (!f) return false;
  f.write(reinterpret_cast<const char*>(b.data()), static_cast<std::streamsize>(b.size()));
  return true;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 5) {
    std::cerr << "usage: nam_bridge_runner <model.nam> <input.wav> <out.wav> <out_f32.bin>\n";
    return 2;
  }
  const std::string namPath = argv[1], inPath = argv[2], outWavPath = argv[3], outF32Path = argv[4];

  WavIn in;
  if (!readWav(inPath, &in)) return 3;
  if (in.sampleRate != 48000) {
    std::cerr << "expected 48000 Hz input, got " << in.sampleRate << " (no resampling implemented here)\n";
    return 3;
  }
  std::cerr << "input: " << in.mono.size() << " frames, " << in.channels << "ch/" << in.bits << "bit\n";

  wyrmtone_nam_engine* engine = wyrmtone_nam_create();
  if (engine == nullptr) {
    std::cerr << "wyrmtone_nam_create failed\n";
    return 4;
  }
  const int32_t blockSize = 4096;
  wyrmtone_nam_status st = wyrmtone_nam_load(engine, namPath.c_str(), 48000.0, blockSize);
  if (st != WYRMTONE_NAM_OK) {
    std::cerr << "load failed (" << st << "): " << wyrmtone_nam_last_error(engine) << "\n";
    wyrmtone_nam_destroy(engine);
    return 5;
  }
  std::cerr << "model expected sample rate: " << wyrmtone_nam_expected_sample_rate(engine) << "\n";

  std::vector<float> output(in.mono.size(), 0.0f);
  st = wyrmtone_nam_process(engine, in.mono.data(), output.data(), static_cast<int32_t>(in.mono.size()));
  if (st != WYRMTONE_NAM_OK) {
    std::cerr << "process failed (" << st << "): " << wyrmtone_nam_last_error(engine) << "\n";
    wyrmtone_nam_destroy(engine);
    return 6;
  }

  bool anyNonFinite = false;
  float peak = 0.0f;
  for (float v : output) {
    if (!std::isfinite(v)) anyNonFinite = true;
    peak = std::max(peak, std::fabs(v));
  }
  std::cerr << "output: " << output.size() << " frames, peak=" << peak << ", nonFinite=" << (anyNonFinite ? "YES" : "no")
             << "\n";

  if (!writeWavStereo16(outWavPath, output, 48000)) {
    std::cerr << "failed to write " << outWavPath << "\n";
    wyrmtone_nam_destroy(engine);
    return 7;
  }
  {
    std::ofstream f(outF32Path, std::ios::binary);
    f.write(reinterpret_cast<const char*>(output.data()), static_cast<std::streamsize>(output.size() * sizeof(float)));
  }

  wyrmtone_nam_unload(engine);
  wyrmtone_nam_destroy(engine);
  std::cerr << "ok\n";
  return 0;
}
