/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "NativeSequenceData.h"
#include "../../FSEQFile.h"

#include <cstdlib>
#include <cstring>
#include <memory>

NativeSequenceData::NativeSequenceData(uint32_t numChannels, uint32_t numFrames, uint32_t frameTimeMS)
    : _numChannels(numChannels)
    , _numFrames(numFrames)
    , _frameTimeMS(frameTimeMS)
{
    _totalBytes = static_cast<size_t>(numFrames) * numChannels;
    // calloc leverages mmap with lazy zero-fill on macOS — the kernel
    // provides zero-filled pages on demand rather than touching all 1 GB+
    // upfront. This makes allocation near-instant vs vector::resize which
    // explicitly memsets every byte.
    _data = static_cast<uint8_t*>(std::calloc(_totalBytes, 1));
}

NativeSequenceData::~NativeSequenceData()
{
    std::free(_data);
}

NativeSequenceData::NativeSequenceData(NativeSequenceData&& other) noexcept
    : _data(other._data)
    , _totalBytes(other._totalBytes)
    , _numChannels(other._numChannels)
    , _numFrames(other._numFrames)
    , _frameTimeMS(other._frameTimeMS)
{
    other._data = nullptr;
    other._totalBytes = 0;
    other._numChannels = 0;
    other._numFrames = 0;
    other._frameTimeMS = 0;
}

NativeSequenceData& NativeSequenceData::operator=(NativeSequenceData&& other) noexcept
{
    if (this != &other) {
        std::free(_data);
        _data = other._data;
        _totalBytes = other._totalBytes;
        _numChannels = other._numChannels;
        _numFrames = other._numFrames;
        _frameTimeMS = other._frameTimeMS;
        other._data = nullptr;
        other._totalBytes = 0;
        other._numChannels = 0;
        other._numFrames = 0;
        other._frameTimeMS = 0;
    }
    return *this;
}

// --- Frame access ---

uint8_t* NativeSequenceData::getFrame(uint32_t frameIndex)
{
    if (!_data || frameIndex >= _numFrames) {
        return nullptr;
    }
    return _data + static_cast<size_t>(frameIndex) * _numChannels;
}

const uint8_t* NativeSequenceData::getFrame(uint32_t frameIndex) const
{
    if (!_data || frameIndex >= _numFrames) {
        return nullptr;
    }
    return _data + static_cast<size_t>(frameIndex) * _numChannels;
}

// --- Channel access ---

void NativeSequenceData::setChannel(uint32_t frame, uint32_t channel, uint8_t value)
{
    if (!_data || frame >= _numFrames || channel >= _numChannels) {
        return;
    }
    _data[static_cast<size_t>(frame) * _numChannels + channel] = value;
}

uint8_t NativeSequenceData::getChannel(uint32_t frame, uint32_t channel) const
{
    if (!_data || frame >= _numFrames || channel >= _numChannels) {
        return 0;
    }
    return _data[static_cast<size_t>(frame) * _numChannels + channel];
}

// --- Bulk operations ---

void NativeSequenceData::zeroFrame(uint32_t frameIndex)
{
    if (!_data || frameIndex >= _numFrames) {
        return;
    }
    std::memset(_data + static_cast<size_t>(frameIndex) * _numChannels, 0, _numChannels);
}

void NativeSequenceData::zeroAll()
{
    if (_data && _totalBytes > 0) {
        std::memset(_data, 0, _totalBytes);
    }
}

// --- FSEQ export ---

bool NativeSequenceData::exportToFSEQ(const std::string& outputPath, int compressionLevel)
{
    if (!isValid()) {
        return false;
    }

    // Determine compression type based on level
    FSEQFile::CompressionType ct;
    int level;
    if (compressionLevel == 0) {
        ct = FSEQFile::CompressionType::none;
        level = 0;
    } else {
        ct = FSEQFile::CompressionType::zstd;
        level = compressionLevel;
    }

    // Create a V2 FSEQ file for writing
    std::unique_ptr<FSEQFile> fseqFile(FSEQFile::createFSEQFile(outputPath, 2, ct, level));
    if (!fseqFile) {
        return false;
    }

    // Configure the file header
    fseqFile->setChannelCount(_numChannels);
    fseqFile->setNumFrames(_numFrames);
    fseqFile->setStepTime(_frameTimeMS);

    // Write the header
    fseqFile->writeHeader();

    // Write each frame from the contiguous data buffer.
    // getFrame() returns a pointer to _numChannels contiguous bytes for each frame.
    for (uint32_t frame = 0; frame < _numFrames; ++frame) {
        const uint8_t* frameData = getFrame(frame);
        fseqFile->addFrame(frame, frameData);
    }

    // Finalize (flush and close)
    fseqFile->finalize();

    return true;
}
