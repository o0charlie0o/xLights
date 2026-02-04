/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "PicturesEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"
#include "../StringUtils.h"

#include <algorithm>
#include <cmath>
#include <fstream>
#include <sstream>
#include <cctype>

namespace xlCore {

// ============================================================================
// Direction and Scaling Parsing
// ============================================================================

PictureDirection parsePictureDirection(const std::string& dir) {
    if (dir == "left") return PictureDirection::Left;
    if (dir == "right") return PictureDirection::Right;
    if (dir == "up") return PictureDirection::Up;
    if (dir == "down") return PictureDirection::Down;
    if (dir == "none") return PictureDirection::None;
    if (dir == "up-left") return PictureDirection::UpLeft;
    if (dir == "down-left") return PictureDirection::DownLeft;
    if (dir == "up-right") return PictureDirection::UpRight;
    if (dir == "down-right") return PictureDirection::DownRight;
    if (dir == "peekaboo") return PictureDirection::Peekaboo0;
    if (dir == "wiggle") return PictureDirection::Wiggle;
    if (dir == "zoom in") return PictureDirection::ZoomIn;
    if (dir == "peekaboo 90") return PictureDirection::Peekaboo90;
    if (dir == "peekaboo 180") return PictureDirection::Peekaboo180;
    if (dir == "peekaboo 270") return PictureDirection::Peekaboo270;
    if (dir == "vix 2 routine") return PictureDirection::VixRemap;
    if (dir == "flag wave") return PictureDirection::FlagWave;
    if (dir == "up once") return PictureDirection::UpOnce;
    if (dir == "down once") return PictureDirection::DownOnce;
    if (dir == "vector") return PictureDirection::Vector;
    if (dir == "tile-left") return PictureDirection::TileLeft;
    if (dir == "tile-right") return PictureDirection::TileRight;
    if (dir == "tile-down") return PictureDirection::TileDown;
    if (dir == "tile-up") return PictureDirection::TileUp;
    return PictureDirection::None;
}

PictureScaling parsePictureScaling(const std::string& scaling) {
    if (scaling == "Scale To Fit") return PictureScaling::ScaleToFit;
    if (scaling == "Scale Keep Aspect Ratio") return PictureScaling::ScaleKeepAspectRatio;
    if (scaling == "Scale Keep Aspect Ratio Crop") return PictureScaling::ScaleKeepAspectRatioCrop;
    return PictureScaling::NoScaling;
}

// ============================================================================
// PicturesEffect Implementation
// ============================================================================

PicturesEffect::PicturesEffect() = default;

std::vector<EffectParameter> PicturesEffect::parameters() const {
    std::vector<EffectParameter> params;

    // File picker
    auto file = EffectParameter::createFile(
        "E_FILEPICKER_Pictures_Filename",
        "Filename",
        "Image files|*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.webp");
    file.group = "Image";
    params.push_back(file);

    // Direction
    auto dir = EffectParameter::createChoice(
        "E_CHOICE_Pictures_Direction",
        "Movement",
        "none",
        {"left", "right", "up", "down", "none", "up-left", "down-left",
         "up-right", "down-right", "peekaboo", "wiggle", "zoom in",
         "peekaboo 90", "peekaboo 180", "peekaboo 270", "vix 2 routine",
         "flag wave", "up once", "down once", "vector",
         "tile-left", "tile-right", "tile-down", "tile-up"});
    dir.group = "Movement";
    params.push_back(dir);

    // Speed
    auto speed = EffectParameter::createDouble(
        "E_TEXTCTRL_Pictures_Speed", "Movement Speed", 1.0, 0.0, 10.0, 0.1);
    speed.group = "Movement";
    params.push_back(speed);

    // Frame rate adjustment
    auto frameRate = EffectParameter::createDouble(
        "E_TEXTCTRL_Pictures_FrameRateAdj", "Frame Rate Adj", 1.0, 0.1, 10.0, 0.1);
    frameRate.group = "Movement";
    params.push_back(frameRate);

    // Position adjustments (with value curve support)
    auto xc = EffectParameter::createInt(
        "E_SLIDER_PicturesXC", "X Position", 0, -100, 100, true);
    xc.group = "Position";
    params.push_back(xc);

    auto yc = EffectParameter::createInt(
        "E_SLIDER_PicturesYC", "Y Position", 0, -100, 100, true);
    yc.group = "Position";
    params.push_back(yc);

    // End position for vector mode
    auto xce = EffectParameter::createInt(
        "E_SLIDER_PicturesEndXC", "End X Position", 0, -100, 100);
    xce.group = "Position";
    params.push_back(xce);

    auto yce = EffectParameter::createInt(
        "E_SLIDER_PicturesEndYC", "End Y Position", 0, -100, 100);
    yce.group = "Position";
    params.push_back(yce);

    // Scale
    auto startScale = EffectParameter::createInt(
        "E_SLIDER_Pictures_StartScale", "Start Scale %", 100, 1, 1000);
    startScale.group = "Scale";
    params.push_back(startScale);

    auto endScale = EffectParameter::createInt(
        "E_SLIDER_Pictures_EndScale", "End Scale %", 100, 1, 1000);
    endScale.group = "Scale";
    params.push_back(endScale);

    // Scaling mode
    auto scaling = EffectParameter::createChoice(
        "E_CHOICE_Scaling", "Scaling",
        "No Scaling",
        {"No Scaling", "Scale To Fit", "Scale Keep Aspect Ratio", "Scale Keep Aspect Ratio Crop"});
    scaling.group = "Scale";
    params.push_back(scaling);

    // Options
    auto pixelOffsets = EffectParameter::createBool(
        "E_CHECKBOX_Pictures_PixelOffsets", "Pixel Offsets", false);
    pixelOffsets.group = "Options";
    params.push_back(pixelOffsets);

    auto wrapX = EffectParameter::createBool(
        "E_CHECKBOX_Pictures_WrapX", "Wrap X", false);
    wrapX.group = "Options";
    params.push_back(wrapX);

    auto shimmer = EffectParameter::createBool(
        "E_CHECKBOX_Pictures_Shimmer", "Shimmer", false);
    shimmer.group = "Options";
    params.push_back(shimmer);

    // GIF options
    auto loopGIF = EffectParameter::createBool(
        "E_CHECKBOX_LoopGIF", "Loop GIF", false);
    loopGIF.group = "Animation";
    params.push_back(loopGIF);

    auto suppressGIFBg = EffectParameter::createBool(
        "E_CHECKBOX_SuppressGIFBackground", "Suppress GIF Background", true);
    suppressGIFBg.group = "Animation";
    params.push_back(suppressGIFBg);

    // Transparent black
    auto transparentBlack = EffectParameter::createBool(
        "E_CHECKBOX_Pictures_TransparentBlack", "Transparent Black", false);
    transparentBlack.group = "Transparency";
    params.push_back(transparentBlack);

    auto transparentLevel = EffectParameter::createInt(
        "E_TEXTCTRL_Pictures_TransparentBlackLevel", "Transparent Level", 0, 0, 765);
    transparentLevel.group = "Transparency";
    params.push_back(transparentLevel);

    return params;
}

std::vector<std::string> PicturesEffect::fileReferences(const EffectSettings& settings) const {
    std::vector<std::string> refs;
    std::string file = settings.get("E_FILEPICKER_Pictures_Filename");
    if (!file.empty()) {
        refs.push_back(file);
    }
    return refs;
}

bool PicturesEffect::isPictureFile(const std::string& path) {
    // Extract extension
    size_t dotPos = path.rfind('.');
    if (dotPos == std::string::npos || dotPos == path.length() - 1) {
        return false;
    }

    std::string ext = path.substr(dotPos + 1);
    std::transform(ext.begin(), ext.end(), ext.begin(),
                   [](unsigned char c) { return std::tolower(c); });

    return (ext == "gif" || ext == "jpg" || ext == "jpeg" ||
            ext == "png" || ext == "webp" || ext == "bmp");
}

bool PicturesEffect::loadImage(PicturesRenderCache& cache,
                               const std::string& filename,
                               const RenderState& state,
                               float frameRateAdj,
                               bool loopGIF,
                               bool suppressGIFBackground) {
    // Check if we need to reload
    bool needReload = (filename != cache.currentFile);

    if (needReload || state.frameIndex == 0) {
        cache.currentFile = filename;

        // Check for movie file sequence (filename-1.ext pattern)
        std::string baseName = filename;
        std::string ext;
        size_t dotPos = filename.rfind('.');
        if (dotPos != std::string::npos) {
            ext = filename.substr(dotPos);
            baseName = filename.substr(0, dotPos);
        }

        // Check if this is a movie sequence (-1 suffix)
        if (baseName.length() >= 2 && baseName.substr(baseName.length() - 2) == "-1") {
            std::string base = baseName.substr(0, baseName.length() - 2);
            // Check if frame 2 exists
            std::string frame2 = base + "-2" + ext;
            auto* loader = ImageLoader::instance();
            if (loader && loader->isImageFile(frame2)) {
                // This is a movie sequence - find max frame count
                if (state.frameIndex == 0) {
                    cache.maxMovieFrames = 1;
                    for (int f = 1; f <= 9999; f++) {
                        std::string framePath = base + "-" + std::to_string(f) + ext;
                        // Check if file exists by trying to get info
                        auto info = loader->getInfo(framePath);
                        if (info) {
                            cache.maxMovieFrames = f;
                        } else {
                            break;
                        }
                    }
                }

                // Calculate which frame to load
                cache.movieFrame = static_cast<int>(std::floor(state.frameIndex * frameRateAdj)) + 1;
                if (cache.movieFrame > cache.maxMovieFrames) {
                    return false; // Past end of sequence
                }

                std::string framePath = base + "-" + std::to_string(cache.movieFrame) + ext;
                auto img = ImageLoader::loadImage(framePath);
                if (img) {
                    cache.image = std::move(*img);
                    cache.rawImage = cache.image;
                    cache.orientation = getExifOrientation(framePath);
                    cache.image = applyExifOrientation(cache.image, cache.orientation);
                    return true;
                }
                return false;
            }
        }

        // Regular image loading
        auto* loader = ImageLoader::instance();
        if (!loader) {
            return false;
        }

        auto info = loader->getInfo(filename);
        if (!info) {
            return false;
        }

        cache.frameCount = info->frameCount;
        cache.orientation = getExifOrientation(filename);

        if (cache.frameCount > 1) {
            // Animated image (GIF)
            cache.gifDecoder = AnimatedImageDecoder::create();
            if (cache.gifDecoder && cache.gifDecoder->open(filename)) {
                cache.gifDecoder->setSuppressBackground(suppressGIFBackground);
                auto frame = cache.gifDecoder->getFrame(0);
                if (frame) {
                    cache.image = std::move(*frame);
                    cache.rawImage = cache.image;
                }
            } else {
                // Fall back to static load
                cache.gifDecoder.reset();
                cache.frameCount = 1;
                auto img = loader->load(filename);
                if (img) {
                    cache.image = std::move(*img);
                    cache.image = applyExifOrientation(cache.image, cache.orientation);
                    cache.rawImage = cache.image;
                }
            }
        } else {
            // Static image
            auto img = loader->load(filename);
            if (img) {
                cache.image = std::move(*img);
                cache.image = applyExifOrientation(cache.image, cache.orientation);
                cache.rawImage = cache.image;
            }
        }
    } else if (cache.frameCount > 1 && cache.gifDecoder) {
        // Update GIF frame
        int frameTimeMs = static_cast<int>(1000.0 / 20.0); // Assuming 20fps default
        int effectTimeMs = static_cast<int>(state.frameIndex * frameTimeMs * frameRateAdj);

        std::optional<ImageBuffer> frame;
        if (loopGIF) {
            frame = cache.gifDecoder->getFrameForTime(effectTimeMs, true);
        } else {
            int targetFrame = static_cast<int>(cache.frameCount * state.progress * 0.99);
            frame = cache.gifDecoder->getFrame(targetFrame);
        }

        if (frame) {
            cache.image = std::move(*frame);
            cache.rawImage = cache.image;
        }
    }

    return !cache.image.isEmpty();
}

void PicturesEffect::loadPixelsFromTextFile(PicturesRenderCache& cache,
                                            const std::string& filename,
                                            int bufferWidth,
                                            int bufferHeight) {
    cache.pixelsByFrame.clear();

    std::ifstream file(filename);
    if (!file.is_open()) {
        return;
    }

    int nodeSize = 1;
    uint8_t rgb[3] = {0, 0, 0};

    std::string line;
    while (std::getline(file, line)) {
        // Remove comments
        size_t commentPos = line.find('#');
        if (commentPos != std::string::npos) {
            line = line.substr(0, commentPos);
        }

        // Trim whitespace
        line.erase(line.find_last_not_of(" \t\r\n") + 1);
        line.erase(0, line.find_first_not_of(" \t\r\n"));

        if (line.empty()) continue;

        // Check for node size directive
        if (line.find("ChannelsPerNode") != std::string::npos) {
            size_t eqPos = line.find('=');
            if (eqPos != std::string::npos) {
                int val = strings::parseInt(line.substr(eqPos + 1), 1);
                if (val == 1 || val == 3) {
                    nodeSize = val;
                }
            }
            continue;
        }

        // Parse frame data
        std::vector<PicturesRenderCache::PixelData> framePixels;
        std::istringstream iss(line);
        std::string token;
        int chNum = 0;

        while (iss >> token) {
            int chVal = strings::parseInt(token, 0);
            if (chVal == 0) {
                chNum++;
                continue;
            }

            PicturesRenderCache::PixelData pixel;
            if (nodeSize == 1) {
                pixel.color = Color(chVal, chVal, chVal);
                pixel.x = chNum % bufferWidth;
                pixel.y = chNum / bufferWidth;
                framePixels.push_back(pixel);
            } else if (nodeSize == 3) {
                switch (chNum % 3) {
                    case 0: rgb[0] = chVal; break;
                    case 1: rgb[1] = chVal; break;
                    case 2:
                        rgb[2] = chVal;
                        pixel.color = Color(rgb[0], rgb[1], rgb[2]);
                        pixel.x = (chNum / 3) % bufferWidth;
                        pixel.y = (chNum / 3) / bufferWidth;
                        framePixels.push_back(pixel);
                        break;
                }
            }
            chNum++;
        }

        cache.pixelsByFrame.push_back(std::move(framePixels));
    }
}

void PicturesEffect::setTransparentBlackPixel(RenderContext& ctx,
                                              int x, int y,
                                              const Color& c,
                                              bool wrap,
                                              bool transparentBlack,
                                              int transparentBlackLevel) {
    if (transparentBlack) {
        int level = c.red + c.green + c.blue;
        if (level <= transparentBlackLevel) {
            return; // Don't draw this pixel
        }
    }

    ctx.setPixel(x, y, c, wrap);
}

ImageBuffer PicturesEffect::scaleImage(const ImageBuffer& source,
                                       int targetWidth,
                                       int targetHeight,
                                       PictureScaling scaling) {
    auto* loader = ImageLoader::instance();
    if (!loader) {
        return source;
    }

    switch (scaling) {
        case PictureScaling::ScaleToFit:
            return loader->scale(source, targetWidth, targetHeight);

        case PictureScaling::ScaleKeepAspectRatio:
            return loader->scaleKeepAspect(source, targetWidth, targetHeight);

        case PictureScaling::ScaleKeepAspectRatioCrop: {
            // Scale to fill the target, then crop
            float xr = static_cast<float>(targetWidth) / source.width();
            float yr = static_cast<float>(targetHeight) / source.height();
            float sc = std::max(xr, yr);
            int newW = static_cast<int>(source.width() * sc);
            int newH = static_cast<int>(source.height() * sc);
            return loader->scale(source, newW, newH);
        }

        case PictureScaling::NoScaling:
        default:
            return source;
    }
}

void PicturesEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Initialize cache if needed
    if (!m_cache) {
        m_cache = std::make_unique<PicturesRenderCache>();
    }

    // Get parameters
    std::string filename = settings.get("E_FILEPICKER_Pictures_Filename");
    std::string dirStr = settings.get("E_CHOICE_Pictures_Direction", "none");
    float movementSpeed = settings.getDouble("E_TEXTCTRL_Pictures_Speed", 1.0);
    float frameRateAdj = settings.getDouble("E_TEXTCTRL_Pictures_FrameRateAdj", 1.0);

    int xcAdj = settings.getInt("E_SLIDER_PicturesXC", 0);
    int ycAdj = settings.getInt("E_SLIDER_PicturesYC", 0);
    int xceAdj = settings.getInt("E_SLIDER_PicturesEndXC", 0);
    int yceAdj = settings.getInt("E_SLIDER_PicturesEndYC", 0);

    int startScale = settings.getInt("E_SLIDER_Pictures_StartScale", 100);
    int endScale = settings.getInt("E_SLIDER_Pictures_EndScale", 100);
    std::string scalingStr = settings.get("E_CHOICE_Scaling", "No Scaling");

    bool pixelOffsets = settings.getBool("E_CHECKBOX_Pictures_PixelOffsets", false);
    bool wrapX = settings.getBool("E_CHECKBOX_Pictures_WrapX", false);
    bool shimmer = settings.getBool("E_CHECKBOX_Pictures_Shimmer", false);
    bool loopGIF = settings.getBool("E_CHECKBOX_LoopGIF", false);
    bool suppressGIFBackground = settings.getBool("E_CHECKBOX_SuppressGIFBackground", true);
    bool transparentBlack = settings.getBool("E_CHECKBOX_Pictures_TransparentBlack", false);
    int transparentBlackLevel = settings.getInt("E_TEXTCTRL_Pictures_TransparentBlackLevel", 0);

    PictureDirection dir = parsePictureDirection(dirStr);
    PictureScaling scaling = parsePictureScaling(scalingStr);

    int bufferWi = state.bufferWidth;
    int bufferHt = state.bufferHeight;
    double position = state.progress * movementSpeed;

    // Handle empty filename
    if (filename.empty()) {
        ctx.fill(Color::Red());
        return;
    }

    // Handle Vixen remap mode
    if (dir == PictureDirection::VixRemap) {
        if (m_cache->pixelsByFrame.empty() || m_cache->currentFile != filename) {
            loadPixelsFromTextFile(*m_cache, filename, bufferWi, bufferHt);
            m_cache->currentFile = filename;
        }

        size_t frameIdx = state.frameIndex;
        if (frameIdx < m_cache->pixelsByFrame.size()) {
            for (const auto& pixel : m_cache->pixelsByFrame[frameIdx]) {
                setTransparentBlackPixel(ctx, pixel.x, pixel.y, pixel.color,
                                         false, transparentBlack, transparentBlackLevel);
            }
        }
        return;
    }

    // Load image
    if (!loadImage(*m_cache, filename, state, frameRateAdj, loopGIF, suppressGIFBackground)) {
        ctx.fill(Color::Red());
        return;
    }

    // Get working image
    ImageBuffer image = m_cache->rawImage;
    bool scaleImage = (state.frameIndex == 0);

    // Handle scaling modes
    if (scaling == PictureScaling::ScaleToFit) {
        image = this->scaleImage(image, bufferWi, bufferHt, scaling);
    } else if (scaling == PictureScaling::ScaleKeepAspectRatio ||
               scaling == PictureScaling::ScaleKeepAspectRatioCrop) {
        image = this->scaleImage(image, bufferWi, bufferHt, scaling);
    } else if (startScale != 100 || endScale != 100) {
        // Dynamic scaling
        int deltaScale = endScale - startScale;
        int currentScale = startScale + static_cast<int>(deltaScale * position);
        int newW = std::max(1, static_cast<int>(m_cache->rawImage.width() * currentScale / 100));
        int newH = std::max(1, static_cast<int>(m_cache->rawImage.height() * currentScale / 100));
        auto* loader = ImageLoader::instance();
        if (loader) {
            image = loader->scale(m_cache->rawImage, newW, newH);
        }
    }

    int imgWidth = static_cast<int>(image.width());
    int imgHeight = static_cast<int>(image.height());
    int yOffset = (bufferHt + imgHeight) / 2;
    int xOffset = (imgWidth - bufferWi) / 2;

    // Calculate position adjustments
    int xOffsetAdj = xcAdj;
    int yOffsetAdj = ycAdj;

    if (dir == PictureDirection::Vector) {
        dir = PictureDirection::None;
        xOffsetAdj = static_cast<int>(std::round(position * (xceAdj - xcAdj))) + xcAdj;
        yOffsetAdj = static_cast<int>(std::round(position * (yceAdj - ycAdj))) + ycAdj;
    }

    if (!pixelOffsets) {
        xOffsetAdj = static_cast<int>(xOffsetAdj * bufferWi / 100.0);
        yOffsetAdj = static_cast<int>(yOffsetAdj * bufferHt / 100.0);
    }

    // Direction-specific calculations
    int waveX = 0, waveW = 0, waveN = 0;
    float xScale = 0.0f, yScale = 0.0f;
    int calcPositionWi = static_cast<int>((imgWidth + bufferWi) * position);
    int calcPositionHt = static_cast<int>((imgHeight + bufferHt) * position);

    switch (dir) {
        case PictureDirection::ZoomIn:
            xScale = (imgWidth > 1) ? static_cast<float>(bufferWi) / imgWidth : 1.0f;
            yScale = (imgHeight > 1) ? static_cast<float>(bufferHt) / imgHeight : 1.0f;
            xScale *= position;
            yScale *= position;
            break;

        case PictureDirection::Peekaboo0:
        case PictureDirection::Peekaboo180:
            yOffset = static_cast<int>((-bufferHt) * (1.0 - position * 2.0));
            if (yOffset > 10) yOffset = -yOffset + 10;
            else if (yOffset > 0) yOffset = 0;
            break;

        case PictureDirection::Peekaboo90:
        case PictureDirection::Peekaboo270:
            yOffset = (imgHeight - bufferWi) / 2;
            xOffset = static_cast<int>((-bufferHt) * (1.0 - position * 2.0));
            if (xOffset > 10) xOffset = -xOffset + 10;
            else if (xOffset > 0) xOffset = 0;
            break;

        case PictureDirection::UpOnce:
        case PictureDirection::DownOnce:
            position = std::min(state.progress * movementSpeed, 1.0);
            calcPositionHt = static_cast<int>((imgHeight + bufferHt) * position);
            break;

        case PictureDirection::Wiggle:
            if (position >= 0.5) {
                xOffset += static_cast<int>(bufferWi * ((1.0 - position) * 2.0 - 0.5));
            } else {
                xOffset += static_cast<int>(bufferWi * (position * 2.0 - 0.5));
            }
            break;

        case PictureDirection::FlagWave:
            waveW = bufferWi;
            waveX = static_cast<int>(position * 200);
            waveN = waveX / std::max(1, waveW);
            break;

        default:
            break;
    }

    // Copy image to buffer
    for (int x = 0; x < imgWidth; x++) {
        for (int y = 0; y < imgHeight; y++) {
            Color c = image.getPixel(x, y);

            // Skip transparent pixels
            if (c.alpha < 64 && !ctx.allowAlpha()) {
                continue;
            }

            int destX, destY;

            switch (dir) {
                case PictureDirection::Left:
                    destX = x + xOffsetAdj + bufferWi - calcPositionWi;
                    destY = yOffset - y - yOffsetAdj - 1;
                    break;

                case PictureDirection::Right:
                    destX = x + xOffsetAdj + calcPositionWi - imgWidth;
                    destY = yOffset - y - yOffsetAdj - 1;
                    break;

                case PictureDirection::Up:
                case PictureDirection::UpOnce:
                    destX = x - xOffset + xOffsetAdj;
                    destY = calcPositionHt - y - yOffsetAdj;
                    break;

                case PictureDirection::Down:
                case PictureDirection::DownOnce:
                    destX = x - xOffset + xOffsetAdj;
                    destY = bufferHt + imgHeight - y - yOffsetAdj - calcPositionHt;
                    break;

                case PictureDirection::UpLeft:
                    destX = x + xOffsetAdj + bufferWi - calcPositionWi;
                    destY = calcPositionHt - y - yOffsetAdj;
                    break;

                case PictureDirection::DownLeft:
                    destX = x + xOffsetAdj + bufferWi - calcPositionWi;
                    destY = bufferHt + imgHeight - y - yOffsetAdj - calcPositionHt;
                    break;

                case PictureDirection::UpRight:
                    destX = x + xOffsetAdj + calcPositionWi - imgWidth;
                    destY = calcPositionHt - y - yOffsetAdj;
                    break;

                case PictureDirection::DownRight:
                    destX = x + xOffsetAdj + calcPositionWi - imgWidth;
                    destY = bufferHt + imgHeight - y - yOffsetAdj - calcPositionHt;
                    break;

                case PictureDirection::Peekaboo0:
                    destX = x - xOffset + xOffsetAdj;
                    destY = bufferHt + yOffset - y - yOffsetAdj - 1;
                    break;

                case PictureDirection::ZoomIn:
                    destX = static_cast<int>((x + xOffsetAdj) * xScale);
                    destY = static_cast<int>((bufferHt - 1 - y - yOffsetAdj) * yScale);
                    break;

                case PictureDirection::Peekaboo90:
                    destX = bufferWi + xOffset - y + xOffsetAdj;
                    destY = x - yOffset - yOffsetAdj;
                    break;

                case PictureDirection::Peekaboo180:
                    destX = x - xOffset + xOffsetAdj;
                    destY = y - yOffset - yOffsetAdj;
                    break;

                case PictureDirection::Peekaboo270:
                    destX = y - xOffset + xOffsetAdj;
                    destY = bufferHt + yOffset + yOffsetAdj - x;
                    break;

                case PictureDirection::FlagWave: {
                    int waveY;
                    if (bufferHt < 20) {
                        waveN = (x - waveX) / std::max(1, waveW);
                        waveY = !x ? 0 : (waveN & 1) ? -1 : 0;
                    } else {
                        waveY = !x ? 0 : (waveN & 1) ? 0 : (waveN & 2) ? -1 : +1;
                        if (waveX < 0) waveY *= -1;
                    }
                    destX = x - xOffset + xOffsetAdj;
                    destY = yOffset - y - yOffsetAdj + waveY - 1;
                    break;
                }

                case PictureDirection::TileLeft:
                case PictureDirection::TileRight:
                case PictureDirection::TileDown:
                case PictureDirection::TileUp: {
                    int xMult = (bufferWi + 2 * imgWidth) / std::max(1, imgWidth);
                    int yMult = (bufferHt + 2 * imgHeight) / std::max(1, imgHeight);
                    int startX = xOffsetAdj;
                    int startY = yOffsetAdj;

                    int frameOffset = state.frameIndex;
                    switch (dir) {
                        case PictureDirection::TileLeft:
                            startX = xOffsetAdj - static_cast<int>(frameOffset * movementSpeed) % imgWidth;
                            startY = yOffsetAdj - imgHeight;
                            break;
                        case PictureDirection::TileRight:
                            startX = xOffsetAdj - imgWidth + static_cast<int>(frameOffset * movementSpeed) % imgWidth;
                            startY = yOffsetAdj - imgHeight;
                            break;
                        case PictureDirection::TileDown:
                            startX = xOffsetAdj - imgWidth;
                            startY = yOffsetAdj - static_cast<int>(frameOffset * movementSpeed) % imgHeight;
                            break;
                        case PictureDirection::TileUp:
                            startX = xOffsetAdj - imgWidth;
                            startY = yOffsetAdj - imgHeight + static_cast<int>(frameOffset * movementSpeed) % imgHeight;
                            break;
                        default:
                            break;
                    }

                    for (int xx = 0; xx < xMult; ++xx) {
                        for (int yy = 0; yy < yMult; ++yy) {
                            setTransparentBlackPixel(ctx,
                                xx * imgWidth + x + startX,
                                yy * imgHeight + (imgHeight - y - 1) + startY,
                                c, false, transparentBlack, transparentBlackLevel);
                        }
                    }
                    continue; // Skip normal pixel setting for tiling
                }

                case PictureDirection::Wiggle:
                case PictureDirection::None:
                default:
                    destX = x - xOffset + xOffsetAdj;
                    destY = yOffset + yOffsetAdj - y - 1;
                    break;
            }

            setTransparentBlackPixel(ctx, destX, destY, c, wrapX,
                                     transparentBlack, transparentBlackLevel);
        }
    }

    // Apply shimmer effect
    if (shimmer) {
        for (int x = 0; x < bufferWi; x++) {
            for (int y = 0; y < bufferHt; y++) {
                // Use deterministic random based on position and time
                uint32_t seed = state.randomSeed ^ (x * 1031) ^ (y * 1033);
                float rand = (seed % 1000) / 1000.0f;
                if (rand > 0.5f) {
                    Color existing = ctx.getPixel(x, y);
                    if (existing != Color::Black()) {
                        ctx.setPixel(x, y, Color::Black());
                    }
                }
            }
        }
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(PicturesEffect)

} // namespace xlCore
