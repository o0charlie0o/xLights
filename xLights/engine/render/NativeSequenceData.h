#pragma once

/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// NativeSequenceData: A wx-free channel data buffer for the native macOS build.
//
// Stores rendered channel data as a flat contiguous array (numFrames * numChannels bytes)
// laid out as: frame 0 channels [0..N-1], frame 1 channels [0..N-1], etc.
//
// Uses calloc for allocation — on macOS this leverages mmap with lazy zero-fill
// pages, making even 1 GB+ allocations near-instant (pages are zero-filled by
// the kernel on first access rather than upfront).
//
// Thread safety: Multiple threads may write to different channel ranges within
// the same frame simultaneously (non-overlapping channel ranges are independent).
// Frame-level operations (zeroFrame) should not overlap with channel writes to
// that frame. exportToFSEQ must be called after all rendering is complete.

#include <cstdint>
#include <string>

class NativeSequenceData {
public:
    // Allocate buffer for the given dimensions.
    // All channel data is initialized to zero.
    NativeSequenceData(uint32_t numChannels, uint32_t numFrames, uint32_t frameTimeMS);
    ~NativeSequenceData();

    NativeSequenceData(const NativeSequenceData&) = delete;
    NativeSequenceData& operator=(const NativeSequenceData&) = delete;

    // Move semantics supported
    NativeSequenceData(NativeSequenceData&& other) noexcept;
    NativeSequenceData& operator=(NativeSequenceData&& other) noexcept;

    // --- Frame access ---

    // Get a writable pointer to the start of frame data.
    // Returns nullptr if frameIndex is out of range.
    // The returned pointer covers _numChannels contiguous bytes.
    uint8_t* getFrame(uint32_t frameIndex);

    // Const access to frame data.
    const uint8_t* getFrame(uint32_t frameIndex) const;

    // --- Channel access within a frame ---

    // Set a single channel value within a frame.
    // No-op if frame or channel is out of range.
    void setChannel(uint32_t frame, uint32_t channel, uint8_t value);

    // Get a single channel value within a frame.
    // Returns 0 if frame or channel is out of range.
    uint8_t getChannel(uint32_t frame, uint32_t channel) const;

    // --- Bulk operations ---

    // Zero all channels in the specified frame.
    void zeroFrame(uint32_t frameIndex);

    // Zero the entire data buffer.
    void zeroAll();

    // --- Properties ---

    uint32_t getNumChannels() const { return _numChannels; }
    uint32_t getNumFrames() const { return _numFrames; }
    uint32_t getFrameTimeMS() const { return _frameTimeMS; }

    // Total size of the data buffer in bytes.
    size_t getTotalBytes() const { return _totalBytes; }

    // Check if the buffer has been allocated and has valid dimensions.
    bool isValid() const { return _data != nullptr && _numChannels > 0 && _numFrames > 0; }

    // --- FSEQ export ---

    // Export all frame data to an FSEQ V2 file with optional zstd compression.
    // compressionLevel: zstd compression level (typically 1-22, default 2 for speed).
    //                   Use 0 for no compression, negative values for fast mode.
    // Returns true on success, false on failure (bad path, I/O error, etc.).
    // Must be called after all rendering is complete (not thread-safe with writes).
    bool exportToFSEQ(const std::string& outputPath, int compressionLevel = 2);

private:
    uint8_t* _data = nullptr;       // calloc-allocated flat array: numFrames * numChannels
    size_t _totalBytes = 0;
    uint32_t _numChannels = 0;
    uint32_t _numFrames = 0;
    uint32_t _frameTimeMS = 0;
};
